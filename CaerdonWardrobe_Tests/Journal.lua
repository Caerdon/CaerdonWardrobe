-- The journal: every time the toon learns something, with what happened around it.
--
-- It explains drift in the verdict tests (the look was learned, the toon levelled) and it is
-- the evidence for server rules that no API states, such as selling an item to a vendor
-- teaching its appearance. Also here: how often the events fire that make the addon refresh.

local _, T = ...

local SECONDS_BEFORE = 6
local SECONDS_AFTER = 1.5
local JOURNAL_LIMIT = 400

local context = {} -- what the toon just did: { time, kind, ... }, newest last
local open = { merchant = false, bank = false, mail = false }
local bagCounts    -- item ID -> how many the bags hold, nil until first read

function T.IsOpen(what)
    return open[what]
end

local function AddContext(kind, data)
    data = data or {}
    data.kind, data.time = kind, GetTime()
    T.Push(context, data, 80)
end

------------------------------------------------------------------------------------------
-- What the toon just did
------------------------------------------------------------------------------------------

local function ReadBagCounts()
    local counts = {}
    for bag = Enum.BagIndex.Backpack, Enum.BagIndex.ReagentBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
    return counts
end

-- Pure: what was gained and lost between two counts, as item ID -> amount, or nil for neither.
function T.BagDelta(before, after)
    local gained, lost
    for itemID, count in pairs(after) do
        local change = count - (before[itemID] or 0)
        if change > 0 then
            gained = gained or {}
            gained[itemID] = change
        end
    end
    for itemID, count in pairs(before) do
        local change = count - (after[itemID] or 0)
        if change > 0 then
            lost = lost or {}
            lost[itemID] = change
        end
    end
    return gained, lost
end

T.RegisterEvent("BAG_UPDATE_DELAYED", function()
    local counts = ReadBagCounts()
    if bagCounts then
        local gained, lost = T.BagDelta(bagCounts, counts)
        if gained or lost then
            AddContext("bags", { gained = gained, lost = lost })
        end
    end
    bagCounts = counts
end)

T.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function(_, slot, hasCurrent)
    AddContext("equipment", { slot = slot, hasCurrent = hasCurrent, itemID = GetInventoryItemID("player", slot) })
end)

T.RegisterEvent("QUEST_TURNED_IN", function(_, questID)
    AddContext("questTurnedIn", { questID = questID })
end)

for event, change in pairs({
    MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
    BANKFRAME_OPENED = { "bank", true }, BANKFRAME_CLOSED = { "bank", false },
    MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail", false },
}) do
    T.RegisterEvent(event, function()
        open[change[1]] = change[2]
        AddContext(change[1] .. (change[2] and "Opened" or "Closed"))
    end)
end

------------------------------------------------------------------------------------------
-- What was learned
------------------------------------------------------------------------------------------

local function DescribeSource(sourceID)
    local info = sourceID and C_TransmogCollection.GetSourceInfo(sourceID)
    if not info then
        return { sourceID = sourceID }
    end
    return {
        sourceID = sourceID, itemID = info.itemID, name = info.name, appearanceID = info.visualID,
        category = info.categoryID,
    }
end

local DESCRIBE = {
    TRANSMOG_COLLECTION_SOURCE_ADDED = DescribeSource,
    TRANSMOG_COLLECTION_SOURCE_REMOVED = DescribeSource,
    TRANSMOG_COSMETIC_COLLECTION_SOURCE_ADDED = DescribeSource,
    NEW_RECIPE_LEARNED = function(recipeID, recipeLevel, baseRecipeID)
        local info = recipeID and C_TradeSkillUI.GetRecipeInfo(recipeID)
        return { recipeID = recipeID, recipeLevel = recipeLevel, baseRecipeID = baseRecipeID, name = info and info.name }
    end,
    NEW_TOY_ADDED = function(itemID)
        return { itemID = itemID }
    end,
    NEW_MOUNT_ADDED = function(mountID)
        return { mountID = mountID, name = mountID and C_MountJournal.GetMountInfoByID(mountID) }
    end,
    NEW_PET_ADDED = function(petGUID)
        return { petGUID = petGUID }
    end,
    PLAYER_LEVEL_UP = function(level)
        return { level = level }
    end,
}

-- Pure: the likely reason an item's look, toy or recipe was learned, from what happened
-- around it. A guess, and stored as one.
function T.GuessCause(what, around, wasOpen)
    local itemID = what and what.itemID
    local lostIt, equippedIt, questTurnedIn = false, false, false
    for _, entry in ipairs(around) do
        if entry.kind == "bags" and itemID and entry.lost and entry.lost[itemID] then
            lostIt = true
        elseif entry.kind == "equipment" and itemID and entry.itemID == itemID then
            equippedIt = true
        elseif entry.kind == "questTurnedIn" then
            questTurnedIn = true
        end
    end
    if equippedIt then return "equipped" end
    if lostIt and wasOpen.merchant then return "sold to a vendor" end
    if lostIt and wasOpen.mail then return "mailed" end
    if lostIt then return "left the bags (used, destroyed or traded)" end
    if questTurnedIn then return "quest turned in" end
    return "unknown"
end

local function OnLearn(event, ...)
    local now = GetTime()
    local toon = T.GetToon()
    local entry = {
        at = GetServerTime(),
        event = event,
        what = T.Plain(DESCRIBE[event](...)),
        toon = toon.key,
        level = toon.level,
        build = T.GetClient().build,
        open = { merchant = open.merchant, bank = open.bank, mail = open.mail },
    }
    T.Push(T.db.journal, entry, JOURNAL_LIMIT)

    -- The bag update that shows the item leaving can arrive after the learn event, so the
    -- surroundings are filled in a moment later.
    C_Timer.After(SECONDS_AFTER, function()
        local around = {}
        for _, item in ipairs(context) do
            local offset = item.time - now
            if offset >= -SECONDS_BEFORE and offset <= SECONDS_AFTER then
                local copy = T.Plain(item)
                copy.time = nil
                copy.offset = math.floor(offset * 100 + 0.5) / 100
                around[#around + 1] = copy
            end
        end
        entry.around = around
        entry.likely = T.GuessCause(entry.what, around, entry.open)
    end)
end

for event in pairs(DESCRIBE) do
    T.RegisterEvent(event, OnLearn)
end

------------------------------------------------------------------------------------------
-- How often things fire
------------------------------------------------------------------------------------------

-- Counted per build, with the minutes of play they were counted over. RefreshItems is the
-- addon's full refresh; the events beside it are the triggers suspected of being noise.
local COUNTED = {
    "PLAYER_FLAGS_CHANGED", "SKILL_LINES_CHANGED", "TRANSMOG_COLLECTION_UPDATED", "BAG_UPDATE_DELAYED",
    "PLAYER_EQUIPMENT_CHANGED", "QUEST_TURNED_IN", "TRANSMOG_COLLECTION_SOURCE_ADDED", "NEW_RECIPE_LEARNED",
}

T.counters = { refreshItems = 0, processItem = 0, byFeature = {} }
local sessionCounts = {}

for _, event in ipairs(COUNTED) do
    sessionCounts[event] = 0
    T.RegisterEvent(event, function()
        sessionCounts[event] = sessionCounts[event] + 1
    end)
end

function T.GetSessionCounts()
    local copy = { RefreshItems = T.counters.refreshItems }
    for event, count in pairs(sessionCounts) do
        copy[event] = count
    end
    return copy
end

T.OnInit(function()
    hooksecurefunc(CaerdonWardrobe, "RefreshItems", function()
        T.counters.refreshItems = T.counters.refreshItems + 1
    end)
    hooksecurefunc(CaerdonWardrobe, "ProcessItem", function(_, _, item, feature)
        T.counters.processItem = T.counters.processItem + 1
        local ok, name = pcall(feature.GetName, feature)
        name = ok and type(name) == "string" and name or "?"
        -- Draws per feature: for an integration, the proof that its hooks deliver.
        T.counters.byFeature[name] = (T.counters.byFeature[name] or 0) + 1
        -- Every item drawn this session, for the probe of appearance sources (Sources.lua).
        T.NoteDrawn(item, name)
        local run = T.timingRun
        if run then
            local now = T.Milliseconds()
            run.firstDraw = run.firstDraw or now
            run.lastDraw = now
            -- Which window drew, and when: two refreshes that drew a different number of
            -- items differ in one of these.
            local entry = run.byFeature[name]
            if not entry then
                entry = { draws = 0, first = now }
                run.byFeature[name] = entry
            end
            entry.draws = entry.draws + 1
            entry.last = now
        end
    end)
end)

-- Events a window redraws itself on. Counted only while a refresh is being timed, with the
-- time of the first one.
local WATCHED_IN_RUN = {
    "TOOLTIP_DATA_UPDATE", "MERCHANT_UPDATE", "BAG_UPDATE", "BAG_UPDATE_DELAYED", "UNIT_INVENTORY_CHANGED",
    "GET_ITEM_INFO_RECEIVED", "CURRENCY_DISPLAY_UPDATE", "HEIRLOOMS_UPDATED", "BANKFRAME_OPENED",
    "PLAYERBANKSLOTS_CHANGED",
}

for _, event in ipairs(WATCHED_IN_RUN) do
    T.RegisterEvent(event, function(_, first, second)
        local run = T.timingRun
        if run then
            local entry = run.events[event]
            if not entry then
                entry = { count = 0, first = T.Milliseconds() }
                run.events[event] = entry
            end
            entry.count = entry.count + 1
            -- Item data arriving: which item, and whether the client has it at all. An item
            -- that never loads is asked for again on every refresh.
            if event == "GET_ITEM_INFO_RECEIVED" and entry.count <= 8 then
                entry.items = entry.items or {}
                entry.items[#entry.items + 1] = T.Plain({ id = first, ok = second })
            end
        end
    end)
end

-- Fires on logout and on a reload, just before the saved variables are written.
T.RegisterEvent("PLAYER_LOGOUT", function()
    if not T.db or not T.loginTime then
        return
    end
    local totals = T.db.events[T.GetClient().build]
    if not totals then
        return
    end
    totals.minutes = (totals.minutes or 0) + (GetTime() - T.loginTime) / 60
    totals.counts = totals.counts or {}
    for name, count in pairs(T.GetSessionCounts()) do
        totals.counts[name] = (totals.counts[name] or 0) + count
    end
end)
