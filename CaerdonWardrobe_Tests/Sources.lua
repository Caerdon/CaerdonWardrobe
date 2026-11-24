-- Appearance sources whose item the client does not have.
--
-- A look can come from several items, and the addon reads every one of them to decide
-- whether the look is known. The client cannot load some of those items (an item of another
-- game mode that shares the look), and a question about one makes it ask the server again.
-- The answer comes back as an event that other windows redraw on.
--
-- Four parts: everything the addon drew this session, every item the client refused this
-- session, the probe that puts the two together (/cwtest sources), and a trace of who calls
-- the client about an item the plan names. The probe names the refused item, its source and
-- appearance, the drawn items that lead to it, and which of the calls the addon makes on a
-- source is the one that makes the client ask.

local _, T = ...

local function Round(value)
    return math.floor(value * 10 + 0.5) / 10
end

------------------------------------------------------------------------------------------
-- What the addon drew
------------------------------------------------------------------------------------------

local MAX_DRAWN = 3000

local drawn, drawnCount = {}, 0 -- link -> { feature name -> draws }
local tracedInDraw = {}         -- traced calls made since the last draw finished

-- Called from the counting hook on ProcessItem (Journal.lua), so it stays cheap: one lookup
-- for an item seen before.
function T.NoteDrawn(item, featureName)
    local ok, link = pcall(item.GetItemLink, item)
    if not ok or type(link) ~= "string" then
        link = nil
    end
    -- This runs when a draw has finished, so the traced calls waiting were made for this item.
    if tracedInDraw[1] then
        for index = #tracedInDraw, 1, -1 do
            tracedInDraw[index].during = link or "(an item without a link)"
            tracedInDraw[index].drawnBy = featureName
            tracedInDraw[index] = nil
        end
    end
    if not link then
        return
    end
    local features = drawn[link]
    if not features then
        if drawnCount >= MAX_DRAWN then
            return
        end
        drawnCount = drawnCount + 1
        features = {}
        drawn[link] = features
    end
    features[featureName] = (features[featureName] or 0) + 1
end

------------------------------------------------------------------------------------------
-- What the client refused
------------------------------------------------------------------------------------------

-- Jobs of the tests that ask for items themselves. A refusal that arrives while one of them
-- runs may be the answer to its own question, so it is counted apart.
local ASKING_JOBS = { probe = true, tests = true, sources = true, search = true, teaches = true }

local refused = {} -- item ID -> { info, load, duringTests, first }
local watching     -- the probe's current step: { itemID, events, started, lastEvent }

local function OnItemAnswer(event, itemID, success)
    if watching and itemID == watching.itemID then
        local seen = watching.events[event]
        if not seen then
            seen = { count = 0, afterMs = Round(T.Milliseconds() - watching.started) }
            watching.events[event] = seen
        end
        seen.count = seen.count + 1
        seen.ok = success and true or false
        watching.lastEvent = GetTime()
    end
    if success or type(itemID) ~= "number" then
        return
    end
    local entry = refused[itemID]
    if not entry then
        entry = { info = 0, load = 0, duringTests = 0, first = Round(GetTime() - (T.loadedAt or GetTime())) }
        refused[itemID] = entry
    end
    if ASKING_JOBS[T.ActiveJob() or ""] then
        entry.duringTests = entry.duringTests + 1
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        entry.info = entry.info + 1
    else
        entry.load = entry.load + 1
    end
end

-- GET_ITEM_INFO_RECEIVED answers a question about an item's data (C_Item.GetItemInfo and
-- whatever else needs it); ITEM_DATA_LOAD_RESULT answers C_Item.RequestLoadItemDataByID.
T.RegisterEvent("GET_ITEM_INFO_RECEIVED", OnItemAnswer)
T.RegisterEvent("ITEM_DATA_LOAD_RESULT", OnItemAnswer)

-- Pure apart from reading the tally: the items the client refused since the tests loaded,
-- in the order of their first refusal. `first` is in seconds after the tests' load. Any
-- addon's question counts: the events do not say who asked.
function T.RefusedItems(limit)
    local ids = T.SortedKeys(refused)
    table.sort(ids, function(a, b)
        if refused[a].first ~= refused[b].first then
            return refused[a].first < refused[b].first
        end
        return a < b
    end)
    local items = {}
    for index = 1, math.min(#ids, limit or 30) do
        local entry = refused[ids[index]]
        items[index] = {
            id = ids[index], info = entry.info, load = entry.load, duringTests = entry.duringTests, first = entry.first,
        }
    end
    return { distinct = #ids, items = items }
end

------------------------------------------------------------------------------------------
-- The probe
------------------------------------------------------------------------------------------

local MAX_TRIED = 8    -- source items the calls are tried on; each takes some seconds
local MAX_LISTED = 60  -- source items listed without trying them
local MAX_OWNERS = 6
local STEP_TIMEOUT = 1.5
local STEP_SETTLE = 0.3

-- The calls the addon makes on each source of an appearance, in its order
-- (types/EquipmentMixin.lua, the loop over GetAllAppearanceSources), and then the request
-- its source loading makes. Each returns something short to store.
local STEPS = {
    {
        call = "C_TransmogCollection.GetSourceInfo",
        run = function(sourceID)
            local info = C_TransmogCollection.GetSourceInfo(sourceID)
            if not info then
                return nil
            end
            return info.name or "(a table without a name)"
        end,
    },
    {
        call = "C_Item.GetItemInfoInstant",
        run = function(_, itemID)
            return (C_Item.GetItemInfoInstant(itemID))
        end,
    },
    {
        call = "C_Item.GetItemSpecInfo",
        run = function(_, itemID)
            local specs = C_Item.GetItemSpecInfo(itemID)
            return specs and ("a table of " .. #specs) or nil
        end,
    },
    {
        call = "C_Item.GetItemInfo",
        run = function(_, itemID)
            return (C_Item.GetItemInfo(itemID))
        end,
    },
    {
        call = "C_Item.RequestLoadItemDataByID",
        run = function(_, itemID)
            C_Item.RequestLoadItemDataByID(itemID)
            return "(nothing)"
        end,
    },
}

-- Inside a job: makes one call and waits for the client's answer about that item.
local function RunStep(step, sourceID, itemID)
    T.Yield() -- a fresh frame, so an answer to the step before is not counted here
    local drawsBefore, refreshesBefore = T.counters.processItem, T.counters.refreshItems
    watching = { itemID = itemID, events = {}, started = T.Milliseconds() }
    local ok, returned = pcall(step.run, sourceID, itemID)
    local state = watching
    T.WaitUntil(function()
        return state.lastEvent ~= nil and GetTime() - state.lastEvent >= STEP_SETTLE
    end, STEP_TIMEOUT)
    watching = nil

    local result = { call = step.call }
    if not ok then
        result.returned = "error: " .. tostring(returned)
    elseif returned == nil then
        result.returned = "nil"
    else
        result.returned = T.Plain(returned)
    end
    if next(state.events) ~= nil then
        result.events = state.events
    end
    -- The addon drawing meanwhile may have asked too, so the answer may not be this call's.
    result.draws = T.counters.processItem - drawsBefore
    result.refreshes = T.counters.refreshItems - refreshesBefore
    return result
end

local function ItemIDFromLink(link)
    return tonumber(link:match("item:(%d+)"))
end

-- The appearance an item link stands for, read as the addon's source loading reads it.
local function AppearanceOf(link, itemID)
    local ok, appearanceID, sourceID = pcall(C_TransmogCollection.GetItemInfo, link)
    if not ok then
        return nil
    end
    if not sourceID then
        appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemID)
    end
    if sourceID and not appearanceID then
        local info = C_TransmogCollection.GetAppearanceInfoBySource(sourceID)
        appearanceID = info and info.appearanceID
    end
    return appearanceID, sourceID
end

-- Inside a job. An item the collection has no entry for can still have a look: the addon
-- finds it by trying the item on a model (types/EquipmentMixin.lua). The probe does not
-- repeat that; it asks the addon, since the sources the addon walks are the question here.
local function AppearanceByTryingOn(link, itemID)
    if not C_Item.IsDressableItemByID(itemID) then
        return nil
    end
    local item = T.LoadItem(link, 3)
    local data = item and item:GetItemData()
    local info = data and data.GetTransmogInfo and data:GetTransmogInfo()
    return info and info.appearanceID or nil
end

local function FeatureList(features)
    local names = {}
    for _, name in ipairs(T.SortedKeys(features)) do
        names[#names + 1] = name
    end
    return table.concat(names, ", ")
end

-- Inside a job. Returns the record.
local function Probe()
    local toon, client = T.GetToon(), T.GetClient()
    local record = {
        at = GetServerTime(),
        toon = toon.key,
        sig = toon.signature,
        flavor = client.flavor,
        build = client.build,
        addons = T.NoteAddons(),
        open = { merchant = T.IsOpen("merchant"), bank = T.IsOpen("bank"), mail = T.IsOpen("mail") },
        -- Before the probe asks anything itself.
        refused = T.RefusedItems(60),
    }

    -- Everything drawn this session, and what the toon wears.
    local items = {}
    for link, features in pairs(drawn) do
        items[link] = FeatureList(features)
    end
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local link = GetInventoryItemLink("player", slot)
        if link then
            items[link] = items[link] and (items[link] .. ", (equipped)") or "(equipped)"
        end
    end

    -- Their appearances.
    local appearances = {} -- appearance ID -> the items that have it
    local looked, withAppearance, appearanceCount, byTryingOn = 0, 0, 0, 0
    for _, link in ipairs(T.SortedKeys(items)) do
        local itemID = ItemIDFromLink(link)
        if itemID then
            looked = looked + 1
            local appearanceID = AppearanceOf(link, itemID)
            local triedOn = false
            if not appearanceID then
                appearanceID = AppearanceByTryingOn(link, itemID)
                triedOn = appearanceID ~= nil
            end
            if appearanceID then
                withAppearance = withAppearance + 1
                if triedOn then
                    byTryingOn = byTryingOn + 1
                end
                local owners = appearances[appearanceID]
                if not owners then
                    owners = {}
                    appearances[appearanceID] = owners
                    appearanceCount = appearanceCount + 1
                end
                owners[#owners + 1] = { link = link, itemID = itemID, drawnBy = items[link], triedOn = triedOn or nil }
            end
            if looked % 50 == 0 then
                T.Yield()
            end
        end
    end
    record.itemsLooked, record.itemsWithAppearance, record.appearances = looked, withAppearance, appearanceCount
    -- Items whose look the collection does not list and the addon found by trying them on.
    record.itemsTriedOn = byTryingOn

    -- Every source of those appearances, by the item behind it.
    local sourceItems = {} -- item ID -> { sources = { source ID -> appearance ID }, owners }
    local sourceCount, sourceItemCount, walked = 0, 0, 0
    record.sourcesWithoutItem = {}
    for _, appearanceID in ipairs(T.SortedKeys(appearances)) do
        for _, sourceID in ipairs(C_TransmogCollection.GetAllAppearanceSources(appearanceID) or {}) do
            sourceCount = sourceCount + 1
            local itemID = C_TransmogCollection.GetSourceItemID(sourceID)
            if not itemID or itemID == 0 then
                if #record.sourcesWithoutItem < 20 then
                    record.sourcesWithoutItem[#record.sourcesWithoutItem + 1] = { sourceID = sourceID, appearanceID = appearanceID }
                end
            else
                local entry = sourceItems[itemID]
                if not entry then
                    entry = { sources = {}, owners = {} }
                    sourceItems[itemID] = entry
                    sourceItemCount = sourceItemCount + 1
                end
                entry.sources[sourceID] = appearanceID
                for _, owner in ipairs(appearances[appearanceID]) do
                    entry.owners[owner.link] = owner
                end
            end
        end
        walked = walked + 1
        if walked % 50 == 0 then
            T.Yield()
        end
    end
    record.sources, record.sourceItems = sourceCount, sourceItemCount

    -- The ones the client has no data for, the ones it refused, the ones the addon gave up on.
    local remembered = CaerdonEquipment and CaerdonEquipment.failedSourceItemLoads or {}
    local missing = {}
    for _, itemID in ipairs(T.SortedKeys(sourceItems)) do
        local cached = C_Item.IsItemDataCachedByID(itemID) and true or false
        if not cached or refused[itemID] or remembered[itemID] then
            local entry = sourceItems[itemID]
            local owners, ownerCount = {}, 0
            for _, link in ipairs(T.SortedKeys(entry.owners)) do
                ownerCount = ownerCount + 1
                if #owners < MAX_OWNERS then
                    owners[#owners + 1] = entry.owners[link]
                end
            end
            local tally = refused[itemID]
            missing[#missing + 1] = {
                itemID = itemID,
                sources = entry.sources,
                owners = owners,
                ownerCount = ownerCount,
                exists = C_Item.DoesItemExistByID(itemID) and true or false,
                cached = cached,
                refusedBefore = tally and (tally.info + tally.load + tally.duringTests) or 0,
                -- The addon's source loading saw the refusal and no longer asks for it there.
                addonGaveUp = remembered[itemID] and true or false,
            }
        end
    end
    -- The refused ones first: they are the question.
    table.sort(missing, function(a, b)
        if a.refusedBefore ~= b.refusedBefore then
            return a.refusedBefore > b.refusedBefore
        end
        return a.itemID < b.itemID
    end)
    record.missingCount = #missing
    record.missing = {}
    for index = 1, math.min(#missing, MAX_LISTED) do
        record.missing[index] = missing[index]
    end

    for index = 1, math.min(#missing, MAX_TRIED) do
        local entry = missing[index]
        local sourceID = T.SortedKeys(entry.sources)[1]
        entry.triedSource = sourceID
        entry.steps, entry.askedBy = {}, {}
        for _, step in ipairs(STEPS) do
            local result = RunStep(step, sourceID, entry.itemID)
            entry.steps[#entry.steps + 1] = result
            if result.events then
                entry.askedBy[#entry.askedBy + 1] = step.call
            end
        end
        entry.cachedAfter = C_Item.IsItemDataCachedByID(entry.itemID) and true or false
    end

    -- Refused items that no drawn item's appearance explains: asked for some other way, or by
    -- another addon.
    record.unexplained = {}
    for _, item in ipairs(record.refused.items) do
        if not sourceItems[item.id] then
            record.unexplained[#record.unexplained + 1] = item.id
        end
    end
    return record
end

-- /cwtest sources
function T.ProbeSources()
    T.Start("sources", function()
        if not T.WaitForIdle(0.5, 20) then
            T.Print("the addon's queue did not go idle, so nothing was probed.")
            return
        end
        T.Print("looking at the appearance sources of everything drawn this session...")
        local record = Probe()
        T.db.sources[record.toon] = record

        T.Print("%d items looked at, %d with an appearance; %d sources from %d items. The client has no data for %d of those items.",
            record.itemsLooked, record.itemsWithAppearance, record.sources, record.sourceItems, record.missingCount)
        for index = 1, math.min(#record.missing, MAX_TRIED) do
            local entry = record.missing[index]
            local owner = entry.owners[1]
            print(("  item %d (refused %d times before): a source of the look of %s%s. Asked for by: %s"):format(
                entry.itemID, entry.refusedBefore, owner and owner.link or "?",
                entry.ownerCount > 1 and (" and %d more"):format(entry.ownerCount - 1) or "",
                (entry.askedBy and #entry.askedBy > 0) and table.concat(entry.askedBy, ", ") or "none of the calls tried"))
        end
        if #record.unexplained > 0 then
            T.Print("%d refused item%s no drawn item leads to: %s", #record.unexplained,
                #record.unexplained == 1 and "" or "s", table.concat(record.unexplained, ", "))
        end
        T.Print("reload to save it.")
        if T.OnTestsFinished then
            T.OnTestsFinished()
        end
    end)
end

------------------------------------------------------------------------------------------
-- Who asks for an item
------------------------------------------------------------------------------------------

-- The refusal events do not say who asked. For the item IDs the plan names (traceItems),
-- every function of C_Item and C_TooltipInfo is hooked, and a call that names one of those
-- items is stored with its stack. Nothing has to be typed: the record is in the saved
-- variables after the next reload.
--
-- A caller that took its own reference to a function before the tests loaded
-- (local GetItemInfo = C_Item.GetItemInfo) is not seen. So an item that was refused with no
-- call on record was asked for that way, or through another API.
--
-- The hooks add a little to every addon's item calls and cannot be taken off again, so they
-- are only installed when the plan names an item: empty the list and reload to be rid of them.

local MAX_TRACES = 60
local traced -- item ID -> true
local traceKeys = {}

local function OnItemCall(fn, first)
    if issecretvalue(first) then
        return
    end
    local itemID
    local kind = type(first)
    if kind == "number" then
        itemID = traced[first] and first
    elseif kind == "string" then
        local id = tonumber(first:match("item:(%d+)"))
        itemID = id and traced[id] and id
    end
    if not itemID then
        return
    end

    local stack = debugstack(3, 14, 6) or ""
    local key = fn .. "\n" .. itemID .. "\n" .. stack
    local entry = traceKeys[key]
    if entry then
        entry.count = entry.count + 1
        return
    end
    local calls = T.db.traces.calls
    if #calls >= MAX_TRACES then
        T.db.traces.more = (T.db.traces.more or 0) + 1
        return
    end
    -- The addons on the stack, innermost first: the first is the one that made the call.
    local addons, seen = {}, {}
    for name in stack:gmatch("AddOns/([^/%]]+)/") do
        if not seen[name] and name ~= T.NAME then
            seen[name] = true
            addons[#addons + 1] = name
        end
    end
    entry = {
        id = itemID,
        fn = fn,
        count = 1,
        first = Round(GetTime() - (T.loadedAt or GetTime())),
        addons = addons,
        stack = stack,
    }
    traceKeys[key] = entry
    calls[#calls + 1] = entry
    -- Made while the addon draws an item: the draw's end names the item (T.NoteDrawn).
    if stack:find("ProcessItem", 1, true) then
        tracedInDraw[#tracedInDraw + 1] = entry
    end
end

local function HookNamespace(namespaceName)
    local namespace = _G[namespaceName]
    if type(namespace) ~= "table" then
        return 0
    end
    local names = {}
    for name, value in pairs(namespace) do
        if type(value) == "function" then
            names[#names + 1] = name
        end
    end
    for _, name in ipairs(names) do
        local fn = namespaceName .. "." .. name
        hooksecurefunc(namespace, name, function(first)
            OnItemCall(fn, first)
        end)
    end
    return #names
end

T.OnInit(function()
    local ids = T.GetPlan().traceItems or {}
    if #ids == 0 then
        return
    end
    traced = {}
    for _, itemID in ipairs(ids) do
        traced[itemID] = true
    end
    T.db.traces = { started = GetServerTime(), ids = ids, calls = {} }
    T.db.traces.hooked = HookNamespace("C_Item") + HookNamespace("C_TooltipInfo")
end)

-- Fires on logout and on a reload, just before the saved variables are written.
T.RegisterEvent("PLAYER_LOGOUT", function()
    if traced and T.db and T.db.traces then
        local toon, client = T.GetToon(), T.GetClient()
        T.db.traces.toon, T.db.traces.build, T.db.traces.flavor = toon.key, client.build, client.flavor
        T.db.traces.seconds = Round(GetTime() - (T.loadedAt or GetTime()))
        T.db.traces.refused = T.RefusedItems(60)
    end
end)
