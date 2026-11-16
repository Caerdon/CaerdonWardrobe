-- Client contracts: facts about the client the addon leans on, checked in the client.
--
-- Each one answers a question that reading Blizzard's code cannot settle. A contract names
-- client functions only when both clients have them; anything that may be missing is looked
-- up by name at run time, so a missing name is an answer and not an error.

local _, T = ...

-- "C_Item.GetItemInfo", "Enum.ItemBind.Quest", "InboxFrame.Update": nil when any step is missing.
local function Lookup(path)
    local value = _G
    for part in path:gmatch("[^.]+") do
        if type(value) ~= "table" then
            return nil
        end
        value = value[part]
        if value == nil then
            return nil
        end
    end
    return value
end
T.Lookup = Lookup

local function Join(list, limit)
    table.sort(list)
    local shown = table.concat(list, ", ", 1, math.min(#list, limit or 8))
    if #list > (limit or 8) then
        shown = shown .. (", +%d more"):format(#list - (limit or 8))
    end
    return shown
end

-- Bag slots that hold an item, backpack first: a list of { bag, slot }.
local function FilledBagSlots(limit)
    local found = {}
    for bag = Enum.BagIndex.Backpack, Enum.BagIndex.ReagentBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            if C_Container.GetContainerItemID(bag, slot) then
                found[#found + 1] = { bag = bag, slot = slot }
                if limit and #found >= limit then
                    return found
                end
            end
        end
    end
    return found
end

local function TypeOf(value)
    return issecretvalue(value) and "secret" or type(value)
end

-- Checks the fields of a table against the types the addon expects. A type ending in "?"
-- may be nil.
local function CheckFields(c, what, value, fields)
    if not c:Check(type(value) == "table", "%s is a %s, not a table", what, TypeOf(value)) then
        return
    end
    for _, name in ipairs(T.SortedKeys(fields)) do
        local want = fields[name]
        local optional = want:sub(-1) == "?"
        if optional then
            want = want:sub(1, -2)
        end
        local have = TypeOf(value[name])
        c:Check(have == want or (optional and have == "nil"), "%s.%s is a %s, expected %s", what, name, have, want)
    end
    c:Note(what .. " keys", T.SortedKeys(value))
end

------------------------------------------------------------------------------------------
-- Who we are
------------------------------------------------------------------------------------------

T.Contract({
    id = "client.identity",
    version = 1,
    title = "The client reports the flavor the addon assumes",
    run = function(c)
        local client = T.GetClient()
        c:Note("client", client)
        c:Note("isForeverClient", CaerdonAPI:IsForeverClient())
        c:Check(client.flavor == "retail" or client.flavor == "forever", "unknown flavor %s", client.flavor)
        if client.flavor == "forever" then
            c:Check(client.projectID == 18, "WOW_PROJECT_ID is %s, expected 18", tostring(client.projectID))
            c:Check(client.toc >= 16000 and client.toc < 20000, "interface version is %s", tostring(client.toc))
        end
    end,
})

------------------------------------------------------------------------------------------
-- Reloading the UI from addon code
------------------------------------------------------------------------------------------

-- The results only reach the disk on a reload or logout, and rotating bag addons needs a
-- reload per addon. Blizzard's own UI calls the plain ReloadUI() from click handlers; these
-- three say whether addon code may do the same, and whether it needs the click.

local RELOAD_HOW = {
    click = "press \"Save results (reload)\" in the /cwtest window",
    slash = "type /cwtest reload",
    timer = "type /cwtest reload timer (reloads a second later, with no click or key behind it)",
}

for how, instruction in pairs(RELOAD_HOW) do
    T.Contract({
        id = "reload." .. how,
        version = 1,
        title = "ReloadUI() from addon code: " .. how,
        run = function()
            return "manual", instruction
        end,
    })
end

local lastBlocked
local TIMER_REFUSED = "ReloadUI() is refused without a click or key press behind it"

local function OnActionBlocked(event, addon, blockedFunction)
    if addon == T.NAME then
        lastBlocked = { event = event, blocked = blockedFunction, time = GetTime() }
    end
end
T.RegisterEvent("ADDON_ACTION_FORBIDDEN", OnActionBlocked)
T.RegisterEvent("ADDON_ACTION_BLOCKED", OnActionBlocked)

-- Reloads, leaving a note in the saved variables. The note coming back after the reload is
-- the proof that it worked; still being here two seconds later is the proof that it did not.
function T.RequestReload(how)
    T.db.pending.reload = { how = how, at = GetServerTime() }
    lastBlocked = nil
    C_Timer.After(2, function()
        local pending = T.db.pending.reload
        if pending and pending.how == how then
            T.db.pending.reload = nil
            if how == "timer" then
                -- Without a click or key press the client may refuse, and that is an answer.
                T.SetResult("reload.timer", "info", { blocked = lastBlocked }, TIMER_REFUSED)
                T.Print("The client refused to reload without a click or key press behind it, which is what this was asking. Use /reload to save the results.")
            else
                T.SetResult("reload." .. how, "fail", { blocked = lastBlocked },
                    "the UI was still running 2 seconds after ReloadUI()")
                T.Print("ReloadUI() did nothing (%s). Recorded; use /reload to save the results.", how)
            end
        end
    end)
    ReloadUI()
end

T.OnLogin(function()
    local pending = T.db.pending.reload
    if pending then
        T.db.pending.reload = nil
        T.SetResult("reload." .. pending.how, "pass", { secondsAway = GetServerTime() - pending.at })
    end
    -- A refusal recorded as a failure before it was called an answer.
    local stored = (T.db.contracts[T.GetClient().build] or {})["reload.timer"]
    if stored and stored.status == "fail" then
        stored.status, stored.message = "info", TIMER_REFUSED
    end
end)

------------------------------------------------------------------------------------------
-- What the static check believes, against the client
------------------------------------------------------------------------------------------

-- StaticFacts.lua is written by tools/static-checks.lua. The check decides from Blizzard's
-- code and listings which names each client has; these contracts ask the client. A name the
-- check calls missing that exists here means its model of the client is wrong. A name it
-- expects that is absent here is not proof: its Blizzard addon may load on demand.

-- The file is generated and not tracked, so a working copy may not have it.
local NO_STATIC_FACTS = "StaticFacts.lua has not been generated: luajit tools/static-checks.lua --emit-facts"

local function NoteStaticBuild(c)
    local facts, client = T.StaticFacts, T.GetClient()
    c:Note("generatedFor", facts.builds[client.flavor])
    c:Note("clientBuild", client.build)
    if facts.builds[client.flavor] ~= client.build then
        c:Note("warning", "the static facts were generated for another build; run update.sh and the static check")
    end
end

T.Contract({
    id = "static.names",
    version = 2,
    title = "Names the static check calls missing from this client are missing",
    run = function(c)
        if not T.StaticFacts then
            return "skip", NO_STATIC_FACTS
        end
        local flavor = T.GetClient().flavor
        local unexpected, fromAddons, absent, checked = {}, {}, {}, 0
        for name, state in pairs(T.StaticFacts.names) do
            checked = checked + 1
            local predicted = state == flavor
            local found = Lookup(name) ~= nil
            if found and not predicted then
                -- A global another addon created says nothing about the client: several of
                -- these names are plain words (options, feature) that addons leak.
                local isSecure, taintedBy = issecurevariable(name:match("^[^.]+"))
                if isSecure then
                    unexpected[#unexpected + 1] = name
                else
                    fromAddons[name] = taintedBy or "an addon"
                end
            elseif predicted and not found then
                absent[#absent + 1] = name
            end
        end
        table.sort(unexpected)
        table.sort(absent)
        NoteStaticBuild(c)
        c:Note("checked", checked)
        c:Note("existsAgainstPrediction", unexpected)
        c:Note("createdByOtherAddons", fromAddons)
        c:Note("absentButExpected", absent)
        -- Names Blizzard's deprecation fallbacks define or wrap: there while the CVar is on.
        -- Listed, not judged.
        local fallbacks = { cvar = C_CVar.GetCVar("loadDeprecationFallbacks"), present = {}, absent = {} }
        for name in pairs(T.StaticFacts.deprecated or {}) do
            local list = Lookup(name) ~= nil and fallbacks.present or fallbacks.absent
            list[#list + 1] = name
        end
        table.sort(fallbacks.present)
        table.sort(fallbacks.absent)
        c:Note("deprecationFallbacks", fallbacks)
        c:Check(#unexpected == 0, "%d names exist here although the static check calls them missing: %s",
            #unexpected, Join(unexpected))
    end,
})

T.Contract({
    id = "static.hooks",
    version = 1,
    title = "Blizzard functions the features hook exist",
    run = function(c)
        if not T.StaticFacts then
            return "skip", NO_STATIC_FACTS
        end
        local flavor = T.GetClient().flavor
        local unexpected, absent, found = {}, {}, 0
        for name, state in pairs(T.StaticFacts.hooks) do
            local predicted = state == "both" or state == flavor
            local exists = type(Lookup(name)) == "function"
            if exists then
                found = found + 1
            end
            if exists and not predicted then
                unexpected[#unexpected + 1] = name
            elseif predicted and not exists then
                absent[#absent + 1] = name
            end
        end
        table.sort(unexpected)
        table.sort(absent)
        NoteStaticBuild(c)
        c:Note("found", found)
        c:Note("existsAgainstPrediction", unexpected)
        -- Not a failure: the target's Blizzard addon may not be loaded yet.
        c:Note("absentButExpected", absent)
        c:Check(#unexpected == 0, "%d hook targets exist here although the static check calls them missing: %s",
            #unexpected, Join(unexpected))
    end,
})

T.Contract({
    id = "static.events",
    version = 1,
    title = "Events the static check gives to one client only are known to that client only",
    run = function(c)
        if not T.StaticFacts then
            return "skip", NO_STATIC_FACTS
        end
        local flavor = T.GetClient().flavor
        local probe = CreateFrame("Frame")
        local function Knows(event)
            local ok = pcall(probe.RegisterEvent, probe, event)
            if ok then
                probe:UnregisterEvent(event)
            end
            return ok
        end

        local unexpected, absent = {}, {}
        for event, state in pairs(T.StaticFacts.events) do
            local predicted = state == flavor
            local known = Knows(event)
            if known and not predicted then
                unexpected[#unexpected + 1] = event
            elseif predicted and not known then
                absent[#absent + 1] = event
            end
        end
        NoteStaticBuild(c)
        c:Note("knownAgainstPrediction", unexpected)
        c:Note("unknownButExpected", absent)
        c:Check(#unexpected == 0, "events known here that the static check calls unknown: %s", Join(unexpected))
        c:Check(#absent == 0, "events unknown here that the static check expects: %s", Join(absent))

        -- Events the addon registers through pcall because a client might not know them.
        local guarded = {}
        for _, event in ipairs({ "UPDATE_EXPANSION_LEVEL", "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED",
            "ACTIVE_COMBAT_CONFIG_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE" }) do
            guarded[event] = Knows(event)
        end
        c:Note("guardedEvents", guarded)
    end,
})

T.Contract({
    id = "static.addons",
    version = 2,
    title = "The static check's list of Blizzard addons this client loads is right",
    run = function(c)
        if not T.StaticFacts then
            return "skip", NO_STATIC_FACTS
        end
        local flavor = T.GetClient().flavor
        local notLoaded, loads = T.StaticFacts.notLoaded[flavor], T.StaticFacts.loads[flavor]

        -- The client may raise an error for a name it has never heard of.
        local function Ask(fn, name)
            local ok, first, second = pcall(fn, name)
            if ok then
                return first, second
            end
            return nil, "error"
        end

        -- Addons the check says never load here must not be loaded.
        local loadedAnyway, reasons = {}, {}
        for _, name in ipairs(notLoaded) do
            if Ask(C_AddOns.IsAddOnLoaded, name) then
                loadedAnyway[#loadedAnyway + 1] = name
            end
            local loadable, reason = Ask(C_AddOns.IsAddOnLoadable, name)
            local key = Ask(C_AddOns.DoesAddOnExist, name) and (loadable and "loadable" or tostring(reason))
                or "unknown to the client"
            -- By name: "loadable" for an addon the check says never loads is worth a look.
            reasons[key] = reasons[key] or {}
            table.insert(reasons[key], name)
        end

        -- Addons it says load here should at least be known to the client.
        local unknown = {}
        for _, name in ipairs(loads) do
            if not Ask(C_AddOns.DoesAddOnExist, name) then
                unknown[#unknown + 1] = name
            end
        end

        NoteStaticBuild(c)
        c:Note("loadedAgainstPrediction", loadedAnyway)
        c:Note("notLoadedByAnswer", reasons)
        c:Note("expectedButUnknown", unknown)
        c:Note("expected", #loads)
        c:Check(#loadedAnyway == 0, "loaded although the static check says this client never loads them: %s",
            Join(loadedAnyway))
        -- If the client does not answer for Blizzard's own addons at all, that is a fact about
        -- the API and says nothing about the list.
        if #unknown > #loads / 2 then
            c:Note("warning", "C_AddOns.DoesAddOnExist does not answer for most Blizzard addons")
        else
            c:Check(#unknown == 0, "unknown to this client although the static check says it loads them: %s",
                Join(unknown))
        end
    end,
})

------------------------------------------------------------------------------------------
-- Shapes of the answers the addon reads
------------------------------------------------------------------------------------------

T.Contract({
    id = "shape.itemInfo",
    version = 1,
    title = "C_Item.GetItemInfo returns its values where the addon reads them",
    run = function(c)
        local item, why = T.LoadItem(6948) -- Hearthstone, in both clients
        if not item then
            return "skip", why
        end
        local values = { C_Item.GetItemInfo(item:GetItemLink()) }
        c:Note("values", values)
        c:Check(type(values[1]) == "string", "value 1 (name) is a %s", TypeOf(values[1]))
        c:Check(type(values[2]) == "string", "value 2 (link) is a %s", TypeOf(values[2]))
        c:Check(type(values[8]) == "number", "value 8 (max stack) is a %s", TypeOf(values[8]))
        c:Check(type(values[9]) == "string", "value 9 (equip location) is a %s", TypeOf(values[9]))
        c:Check(type(values[11]) == "number", "value 11 (sell price) is a %s", TypeOf(values[11]))
        c:Check(type(values[12]) == "number", "value 12 (class) is a %s", TypeOf(values[12]))
        c:Check(type(values[13]) == "number", "value 13 (subclass) is a %s", TypeOf(values[13]))
        c:Check(type(values[14]) == "number", "value 14 (bind type) is a %s", TypeOf(values[14]))
        c:Check(type(values[15]) == "number", "value 15 (expansion) is a %s", TypeOf(values[15]))
        c:Check(type(values[17]) == "boolean", "value 17 (crafting reagent) is a %s", TypeOf(values[17]))
    end,
})

T.Contract({
    id = "shape.containerItemInfo",
    version = 1,
    title = "C_Container.GetContainerItemInfo has the fields the addon reads",
    run = function(c)
        local slots = FilledBagSlots(1)
        if #slots == 0 then
            return "skip", "needs an item in the bags"
        end
        local info = C_Container.GetContainerItemInfo(slots[1].bag, slots[1].slot)
        CheckFields(c, "containerItemInfo", info, {
            stackCount = "number", isLocked = "boolean", quality = "number?", isReadable = "boolean",
            hasLoot = "boolean", hyperlink = "string", isFiltered = "boolean", itemID = "number",
            isBound = "boolean",
        })
    end,
})

T.Contract({
    id = "shape.tooltipData",
    version = 1,
    title = "C_TooltipInfo.GetHyperlink returns typed lines with colors",
    run = function(c)
        local item, why = T.LoadItem(6948)
        if not item then
            return "skip", why
        end
        local data = C_TooltipInfo.GetHyperlink(item:GetItemLink())
        CheckFields(c, "tooltipData", data, { lines = "table", type = "number", dataInstanceID = "number" })
        local line = type(data) == "table" and type(data.lines) == "table" and data.lines[1]
        CheckFields(c, "line", line, { leftText = "string", type = "number", leftColor = "table" })
        if type(line) == "table" and type(line.leftColor) == "table" then
            CheckFields(c, "leftColor", line.leftColor, { r = "number", g = "number", b = "number" })
        end
    end,
})

T.Contract({
    id = "shape.sourceInfo",
    version = 1,
    title = "The transmog source answers have the fields the addon reads",
    perToon = true,
    run = function(c)
        local sourceID, link
        for slot = 1, 19 do
            link = GetInventoryItemLink("player", slot)
            if link then
                local _, source = C_TransmogCollection.GetItemInfo(link)
                if source then
                    sourceID = source
                    break
                end
            end
        end
        if not sourceID then
            return "skip", "needs an equipped item with an appearance"
        end
        c:Note("item", link)
        CheckFields(c, "sourceInfo", C_TransmogCollection.GetSourceInfo(sourceID), {
            isCollected = "boolean", isValidSourceForPlayer = "boolean", categoryID = "number",
            itemID = "number", visualID = "number", sourceType = "number?", useErrorType = "number?",
        })
        local ready, canCollect = C_TransmogCollection.PlayerCanCollectSource(sourceID)
        c:Check(type(ready) == "boolean" and type(canCollect) == "boolean",
            "PlayerCanCollectSource returned %s, %s", TypeOf(ready), TypeOf(canCollect))
        ready, canCollect = C_TransmogCollection.AccountCanCollectSource(sourceID)
        c:Check(type(ready) == "boolean" and type(canCollect) == "boolean",
            "AccountCanCollectSource returned %s, %s", TypeOf(ready), TypeOf(canCollect))
    end,
})

------------------------------------------------------------------------------------------
-- One known item, build after build
------------------------------------------------------------------------------------------

-- The WoWUnit tests the addon used to ship began with a "data change canary": everything the
-- client says about one plain item, Brawler's Harness, so that a patch which changes what
-- the client hands out is noticed. This is that canary. It reads what does not depend on the
-- toon or the collection and compares it with the reading of the build before, so it needs no
-- expected values and holds for either client. The old test's values (retail, 2020) are kept
-- for the reader: where today's reading differs from them is noted, not judged.

local CANARY_ITEM = 6125
local CANARY_ID, CANARY_VERSION = "canary.knownItem", 1

local CANARY_2020 = {
    name = "Brawler's Harness", quality = 2, minLevel = 0, equipLoc = "INVTYPE_BODY", classID = 4, subClassID = 0,
    bindType = 2, expansionID = 0, craftingReagent = false, appearanceID = 1979, sourceID = 2260,
    ["source.visualID"] = 1979, ["source.itemID"] = 6125, ["source.categoryID"] = 5, ["source.invType"] = 5,
    ["source.itemModID"] = 0, ["source.name"] = "Brawler's Harness", ["source.quality"] = 2,
    ["source.isHideVisual"] = false,
}
-- The fields GetSourceInfo had then, for a source nobody had collected.
local CANARY_2020_SOURCE_KEYS = "categoryID, invType, isCollected, isHideVisual, itemID, itemModID, name, quality, "
    .. "sourceID, visualID"

-- The same contract's reading from the newest other build the results still hold.
local function EarlierReading(id, version)
    local current = T.GetClient().build
    local found, foundBuild
    for build, results in pairs(T.db.contracts) do
        local stored = results[id]
        if build ~= current and stored and stored.v == version and type(stored.detail) == "table"
            and type(stored.detail.reading) == "table" and (not found or stored.at > found.at) then
            found, foundBuild = stored, build
        end
    end
    return found and found.detail.reading, foundBuild
end

T.Contract({
    id = CANARY_ID,
    version = CANARY_VERSION,
    title = "What the client says about one plain item is what it said in the build before",
    run = function(c)
        local item, why = T.LoadItem(CANARY_ITEM)
        if not item then
            return "skip", why
        end
        local link = item:GetItemLink()
        local values = { C_Item.GetItemInfo(link) }
        local reading = {
            name = values[1], quality = values[3], minLevel = values[5], maxStack = values[8], equipLoc = values[9],
            classID = values[12], subClassID = values[13], bindType = values[14], expansionID = values[15],
            craftingReagent = values[17],
        }
        local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(link)
        reading.appearanceID, reading.sourceID = appearanceID or false, sourceID or false

        local source = sourceID and C_TransmogCollection.GetSourceInfo(sourceID)
        if type(source) == "table" then
            for _, key in ipairs({ "visualID", "itemID", "categoryID", "invType", "itemModID", "name", "quality",
                "isHideVisual" }) do
                local value = source[key]
                if value == nil then
                    value = false
                end
                reading["source." .. key] = T.Plain(value)
            end
            -- Which fields a source has depends on the toon and the collection as well (a use
            -- error, a source type), so the list is kept to be read and is no part of the
            -- comparison.
            local keys = table.concat(T.SortedKeys(source), ", ")
            c:Note("sourceKeys", keys)
            c:Note("sourceKeysAsIn2020", keys == CANARY_2020_SOURCE_KEYS)
            c:Note("source", T.Facts.Scalars(source))
            c:Note("lookSources", #(appearanceID and C_TransmogCollection.GetAllAppearanceSources(appearanceID) or {}))
        end
        reading = T.Plain(reading)
        c:Note("reading", reading)
        c:Note("link", link)

        local unlike2020 = {}
        for _, key in ipairs(T.SortedKeys(CANARY_2020)) do
            if reading[key] ~= CANARY_2020[key] then
                unlike2020[#unlike2020 + 1] = ("%s is %s, was %s"):format(key, tostring(reading[key]),
                    tostring(CANARY_2020[key]))
            end
        end
        c:Note("unlikeTheOldTest", unlike2020)

        local earlier, earlierBuild = EarlierReading(CANARY_ID, CANARY_VERSION)
        if not earlier then
            return "info", "a first reading: the next build is compared with it"
        end
        c:Note("comparedWith", earlierBuild)
        local changed = T.Facts.Diff(earlier, reading)
        for _, key in ipairs(T.SortedKeys(changed or {})) do
            c:Check(false, "since build %s, %s went from %s to %s", earlierBuild, key, tostring(changed[key].before),
                tostring(changed[key].after))
        end
    end,
})

------------------------------------------------------------------------------------------
-- Tooltip lines
------------------------------------------------------------------------------------------

-- The fields of a tooltip line are documented for neither client. This collects every field
-- seen on the lines of the items in the bags, per line type, with one example each. It adds
-- to what earlier runs saw, so the list grows with what the toons carry.

local function MergeKeySets(old, new)
    local merged = old
    merged.items = (old.items or 0) + (new.items or 0)
    merged.data = merged.data or {}
    for key, sample in pairs(new.data or {}) do
        if merged.data[key] == nil then
            merged.data[key] = sample
        end
    end
    merged.lineTypes = merged.lineTypes or {}
    for lineType, entry in pairs(new.lineTypes or {}) do
        local target = merged.lineTypes[lineType]
        if not target then
            merged.lineTypes[lineType] = entry
        else
            target.lines = (target.lines or 0) + (entry.lines or 0)
            for key, sample in pairs(entry.fields or {}) do
                if target.fields[key] == nil then
                    target.fields[key] = sample
                end
            end
        end
    end
    return merged
end

T.Contract({
    id = "tooltip.lineFields",
    version = 1,
    title = "Which fields tooltip lines carry, per line type",
    accumulate = true,
    merge = MergeKeySets,
    run = function(c)
        local slots = FilledBagSlots()
        if #slots == 0 then
            return "skip", "needs items in the bags"
        end
        local dataKeys, lineTypes = {}, {}
        for index, where in ipairs(slots) do
            local data = C_TooltipInfo.GetBagItem(where.bag, where.slot)
            if type(data) == "table" then
                for key, value in pairs(data) do
                    if key ~= "lines" and dataKeys[key] == nil then
                        dataKeys[key] = T.Plain(value, 2)
                    end
                end
                for _, line in ipairs(data.lines or {}) do
                    local lineType = tostring(line.type)
                    local entry = lineTypes[lineType]
                    if not entry then
                        entry = { lines = 0, fields = {} }
                        lineTypes[lineType] = entry
                    end
                    entry.lines = entry.lines + 1
                    for key, value in pairs(line) do
                        if entry.fields[key] == nil then
                            entry.fields[key] = T.Plain(value, 2)
                        end
                    end
                end
            end
            if index % 20 == 0 then
                T.Yield()
            end
        end
        c:Note("items", #slots)
        c:Note("data", dataKeys)
        c:Note("lineTypes", lineTypes)
        return "info"
    end,
})

-- The export's tooltip sections (Copy Details), asked for every item in the bags: each line
-- of the client's answer has its row, and every field of the line is on it. An item in a bag
-- has two tooltips, the slot's and the bare link's, which is the one the addon computes the
-- status from; where the two differ, the line types that differ are collected with a few
-- examples each. That list is what the addon cannot know about a copy from its link.

local EXPORT_ROW_FIELDS = { type = true, leftText = true, rightText = true, leftColor = true, rightColor = true }
local EXPORT_EXAMPLE_LENGTH = 200
local EXPORT_EXAMPLES = 6

-- Keeps an example unless one like it is there: two lines that differ in their numbers only
-- (a cooldown, a price) are one kind of line.
local function AddExportExample(list, example)
    local shape = example:gsub("%d+", "#")
    for _, known in ipairs(list) do
        local knownShape = known:gsub("%d+", "#")
        if knownShape == shape then
            return
        end
    end
    if #list < EXPORT_EXAMPLES then
        list[#list + 1] = example
    end
end

-- The export's rows as sections: { title, info = { row text }, lines = { { row, fields } } }.
-- A line's row loses its "[3] " so that a line can be found again where the count differs.
local function ExportSections(rows)
    local sections, current = {}, nil
    for _, row in ipairs(rows) do
        local text = row.text
        if row.indent == 0 and text:sub(1, 1) == "[" then
            current = { title = text, info = {}, lines = {} }
            sections[#sections + 1] = current
        elseif current and row.indent == 1 and text:find("^%[%d+%] ") then
            current.lines[#current.lines + 1] = { row = (text:gsub("^%[%d+%] ", "")), fields = "" }
        elseif current and row.indent == 3 and #current.lines > 0 then
            current.lines[#current.lines].fields = text
        elseif current and row.indent == 1 then
            current.info[#current.info + 1] = text
        end
    end
    return sections
end

-- Whether a section's lines are the client's lines, one row each with every field.
local function CheckExportLines(c, what, section, data)
    local lines = type(data) == "table" and data.lines or {}
    if not c:Check(#section.lines == #lines, "%s: %d rows for %d tooltip lines", what, #section.lines, #lines) then
        return
    end
    for index, line in ipairs(lines) do
        local shown = section.lines[index]
        local leftText = line.leftText
        if type(leftText) == "string" and leftText ~= "" then
            c:Check(shown.row:find(leftText, 1, true) ~= nil, "%s: line %d does not show its text", what, index)
        end
        for key, value in pairs(line) do
            if not EXPORT_ROW_FIELDS[key] and type(value) ~= "function" then
                c:Check((", " .. shown.fields):find(", " .. tostring(key) .. "=", 1, true) ~= nil,
                    "%s: line %d (type %s) does not show its field %s", what, index, tostring(line.type), tostring(key))
            end
        end
    end
end

-- Counts the lines one section has and the other lacks, by line type, into differs.
local function NoteExportDifferences(differs, section, other, side)
    local has = {}
    for _, line in ipairs(other.lines) do
        has[line.row .. "\n" .. line.fields] = true
    end
    for _, line in ipairs(section.lines) do
        if not has[line.row .. "\n" .. line.fields] then
            local lineType = line.row:match("^type=%S+ %b()") or line.row:match("^type=%S+") or "?"
            local entry = differs[lineType]
            if not entry then
                entry = { slotOnly = 0, linkOnly = 0, slotExamples = {}, linkExamples = {} }
                differs[lineType] = entry
            end
            entry[side .. "Only"] = entry[side .. "Only"] + 1
            local example = line.row .. (line.fields ~= "" and ("  {" .. line.fields .. "}") or "")
            AddExportExample(entry[side .. "Examples"], example:sub(1, EXPORT_EXAMPLE_LENGTH))
        end
    end
end

local function MergeExportLines(old, new)
    local merged = old
    for _, key in ipairs({ "items", "linkSame", "linkDiffers" }) do
        merged[key] = (old[key] or 0) + (new[key] or 0)
    end
    merged.sample = old.sample or new.sample
    merged.differs = merged.differs or {}
    for lineType, entry in pairs(new.differs or {}) do
        local target = merged.differs[lineType]
        if not target then
            merged.differs[lineType] = entry
        else
            target.slotOnly = (target.slotOnly or 0) + (entry.slotOnly or 0)
            target.linkOnly = (target.linkOnly or 0) + (entry.linkOnly or 0)
            for _, side in ipairs({ "slotExamples", "linkExamples" }) do
                target[side] = target[side] or {}
                for _, example in ipairs(entry[side] or {}) do
                    AddExportExample(target[side], example)
                end
            end
        end
    end
    return merged
end

T.Contract({
    id = "export.tooltipLines",
    version = 2,
    title = "The export shows every tooltip line of a bag item with every field, for the slot and for the link",
    accumulate = true,
    merge = MergeExportLines,
    run = function(c)
        local feature = CaerdonWardrobe and CaerdonWardrobe.GetFeature and CaerdonWardrobe:GetFeature("DebugFrame")
        if not feature or type(feature.GetTooltipReportRows) ~= "function" then
            return "skip", "the addon's Debug Frame has no GetTooltipReportRows"
        end
        local slots = FilledBagSlots()
        if #slots == 0 then
            return "skip", "needs items in the bags"
        end
        local items, linkSame, linkDiffers, differs, sample = 0, 0, 0, {}, nil
        for index, where in ipairs(slots) do
            local link = C_Container.GetContainerItemLink(where.bag, where.slot)
            if link then
                items = items + 1
                local what = ("bag %d slot %d"):format(where.bag, where.slot)
                local rows = feature:GetTooltipReportRows(link, ItemLocation:CreateFromBagAndSlot(where.bag, where.slot))
                local sections = ExportSections(rows)
                local slotSection, linkSection = sections[1], sections[2]
                if c:Check(#sections == 2 and slotSection.title == "[Tooltip Lines (Raw)]"
                        and linkSection.title == "[Tooltip Lines (Link)]", "%s: %d sections, expected the slot's and the link's",
                        what, #sections) then
                    CheckExportLines(c, what .. ", slot", slotSection, C_TooltipInfo.GetBagItem(where.bag, where.slot))
                    local linkData = C_TooltipInfo.GetHyperlink(link)
                    local same = false
                    for _, text in ipairs(linkSection.info) do
                        same = same or text:find("^Lines: %d+, each the same") ~= nil
                    end
                    if same then
                        linkSame = linkSame + 1
                        c:Check(#linkSection.lines == 0, "%s: the link's lines are called the same and printed as well", what)
                    else
                        linkDiffers = linkDiffers + 1
                        CheckExportLines(c, what .. ", link", linkSection, linkData)
                        NoteExportDifferences(differs, slotSection, linkSection, "slot")
                        NoteExportDifferences(differs, linkSection, slotSection, "link")
                    end
                    if not sample or (not same and not sample.differs) then
                        local texts = {}
                        for rowIndex, row in ipairs(rows) do
                            texts[rowIndex] = string.rep("  ", row.indent) .. row.text
                        end
                        sample = { link = link, differs = not same, rows = texts }
                    end
                end
            end
            if index % 10 == 0 then
                T.Yield()
            end
        end
        c:Note("items", items)
        c:Note("linkSame", linkSame)
        c:Note("linkDiffers", linkDiffers)
        c:Note("differs", differs)
        c:Note("sample", sample)
    end,
})

-- Whether what C_TooltipInfo answers is the game's alone. Other addons write on tooltips, and
-- the addon decides statuses from tooltip lines, so a line of theirs must never be among the
-- lines it reads. They have three ways in, and each is tried here:
--   * adding a line to a tooltip frame while it is filled (what nearly all of them do): the
--     test does exactly that on a frame of its own and looks for its line in the data;
--   * changing the table the frame hands to their callback: the test changes a table it got
--     and asks again;
--   * replacing a C_TooltipInfo function: a function that is not the client's own is named.

local MARKER_TEXT = "CaerdonWardrobe_Tests: a line an addon added"
local MARKER_TOOLTIP = "CaerdonWardrobeTestsMarkerTooltip"
local markerTooltip, markerArmed

local function HasMarker(data)
    for _, line in ipairs(type(data) == "table" and data.lines or {}) do
        if not issecretvalue(line.leftText) and line.leftText == MARKER_TEXT then
            return true
        end
    end
    return false
end

T.Contract({
    id = "tooltip.gameOnly",
    version = 1,
    title = "Tooltip data holds the game's lines only: nothing an addon adds to a tooltip reaches it",
    run = function(c)
        if InCombatLockdown() then
            return "skip", "out of combat only"
        end
        local slots = FilledBagSlots(1)
        if #slots == 0 then
            return "skip", "needs an item in the bags"
        end
        local bag, slot = slots[1].bag, slots[1].slot

        -- A function an addon assigned is not secure, and the client says whose it is.
        local replaced, functions = {}, 0
        for name, value in pairs(C_TooltipInfo) do
            if type(value) == "function" then
                functions = functions + 1
                local isSecure, taintedBy = issecurevariable(C_TooltipInfo, name)
                if not isSecure then
                    replaced[#replaced + 1] = ("%s (%s)"):format(tostring(name), tostring(taintedBy))
                end
            end
        end
        c:Note("functions", functions)
        c:Note("replaced", replaced)
        c:Check(#replaced == 0, "%d C_TooltipInfo functions are not the client's own: %s", #replaced, Join(replaced))

        -- A line added to a frame, the way an addon adds one.
        if not markerTooltip then
            markerTooltip = CreateFrame("GameTooltip", MARKER_TOOLTIP, UIParent, "GameTooltipTemplate")
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
                if markerArmed and tooltip == markerTooltip then
                    tooltip:AddLine(MARKER_TEXT)
                end
            end)
        end
        markerArmed = true
        markerTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        markerTooltip:SetBagItem(bag, slot)
        markerArmed = false
        local frameLines, onFrame = markerTooltip:NumLines() or 0, false
        for index = 1, frameLines do
            local fontString = _G[MARKER_TOOLTIP .. "TextLeft" .. index]
            local text = fontString and fontString:GetText()
            if not issecretvalue(text) and text == MARKER_TEXT then
                onFrame = true
            end
        end
        markerTooltip:Hide()

        local data = C_TooltipInfo.GetBagItem(bag, slot)
        if not c:Check(type(data) == "table" and type(data.lines) == "table", "the slot's tooltip data is a %s", type(data)) then
            return
        end
        c:Note("frameLines", frameLines)
        c:Note("dataLines", #data.lines)
        c:Check(onFrame, "the line added to the tooltip frame is not on it (%d lines), so the test shows nothing", frameLines)
        c:Check(not HasMarker(data), "a line an addon added to a tooltip frame is in the data of C_TooltipInfo.GetBagItem")
        local link = C_Container.GetContainerItemLink(bag, slot)
        if link then
            c:Check(not HasMarker(C_TooltipInfo.GetHyperlink(link)),
                "a line an addon added to a tooltip frame is in the data of C_TooltipInfo.GetHyperlink")
        end

        -- A table that was handed out and changed.
        data.lines[#data.lines + 1] = { type = 0, leftText = MARKER_TEXT }
        local again = C_TooltipInfo.GetBagItem(bag, slot)
        c:Check(again ~= data, "two calls for one slot return the same table, so a change by anyone is seen by everyone")
        c:Check(not HasMarker(again), "a line written into one answer's table is in the next answer")
    end,
})

------------------------------------------------------------------------------------------
-- Secret values
------------------------------------------------------------------------------------------

local function CountSecrets(value, depth)
    if issecretvalue(value) then
        return 1
    end
    if type(value) ~= "table" or depth <= 0 then
        return 0
    end
    local count = 0
    for _, item in pairs(value) do
        count = count + CountSecrets(item, depth - 1)
    end
    return count
end

T.Contract({
    id = "secrets.itemData",
    version = 1,
    title = "The item, container, tooltip and transmog answers hold no secret values out of combat",
    run = function(c)
        local slots = FilledBagSlots(15)
        if #slots == 0 then
            return "skip", "needs items in the bags"
        end
        local secrets, calls = {}, 0
        local function Probe(name, ...)
            calls = calls + 1
            local count = CountSecrets({ ... }, 4)
            if count > 0 then
                secrets[name] = (secrets[name] or 0) + count
            end
        end
        for _, where in ipairs(slots) do
            local bag, slot = where.bag, where.slot
            local link = C_Container.GetContainerItemLink(bag, slot)
            Probe("C_Container.GetContainerItemInfo", C_Container.GetContainerItemInfo(bag, slot))
            Probe("C_Container.GetContainerItemLink", link)
            Probe("C_TooltipInfo.GetBagItem", C_TooltipInfo.GetBagItem(bag, slot))
            if link and not issecretvalue(link) then
                Probe("C_Item.GetItemInfo", C_Item.GetItemInfo(link))
                Probe("C_Item.GetItemStats", C_Item.GetItemStats(link))
                Probe("C_TooltipInfo.GetHyperlink", C_TooltipInfo.GetHyperlink(link))
                local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(link)
                Probe("C_TransmogCollection.GetItemInfo", appearanceID, sourceID)
                if sourceID and not issecretvalue(sourceID) then
                    Probe("C_TransmogCollection.GetSourceInfo", C_TransmogCollection.GetSourceInfo(sourceID))
                    Probe("C_TransmogCollection.PlayerCanCollectSource",
                        C_TransmogCollection.PlayerCanCollectSource(sourceID))
                end
            end
        end
        c:Note("items", #slots)
        c:Note("calls", calls)
        c:Note("secretValuesByFunction", secrets)
        c:Check(next(secrets) == nil, "secret values came back from: %s", Join(T.SortedKeys(secrets)))
    end,
})

------------------------------------------------------------------------------------------
-- Transmog collection
------------------------------------------------------------------------------------------

T.Contract({
    id = "transmog.categoryAppearances",
    version = 1,
    title = "GetCategoryAppearances lists appearances that are not collected",
    run = function(c)
        local api = C_TransmogCollection
        local collectedShown, uncollectedShown = api.GetCollectedShown(), api.GetUncollectedShown()
        c:Note("filtersFound", { collected = collectedShown, uncollected = uncollectedShown })
        -- The list follows the wardrobe's own filter, so both sides are switched on for the
        -- reading and put back afterwards.
        if not collectedShown then api.SetCollectedShown(true) end
        if not uncollectedShown then api.SetUncollectedShown(true) end

        local totals = { categories = 0, appearances = 0, collected = 0, uncollected = 0 }
        local perCategory, fields, refused = {}, nil, {}
        for name, category in pairs(Enum.TransmogCollectionType) do
            -- Not every value of the enum is a category the function takes.
            local ok, list = pcall(api.GetCategoryAppearances, category)
            if not ok then
                refused[name] = tostring(list)
            elseif type(list) == "table" and #list > 0 then
                local collected = 0
                for _, appearance in ipairs(list) do
                    if appearance.isCollected then
                        collected = collected + 1
                    end
                end
                fields = fields or T.SortedKeys(list[1])
                perCategory[name] = { total = #list, collected = collected }
                totals.categories = totals.categories + 1
                totals.appearances = totals.appearances + #list
                totals.collected = totals.collected + collected
                totals.uncollected = totals.uncollected + (#list - collected)
            end
            T.Yield()
        end

        if not collectedShown then api.SetCollectedShown(false) end
        if not uncollectedShown then api.SetUncollectedShown(false) end

        c:Note("totals", totals)
        c:Note("perCategory", perCategory)
        c:Note("categoriesRefused", refused)
        c:Note("appearanceFields", fields)
        if not c:Check(totals.appearances > 0, "no category returned an appearance") then
            return
        end
        c:Check(totals.uncollected > 0, "all %d appearances returned are collected", totals.appearances)
    end,
})

------------------------------------------------------------------------------------------
-- The client's own addon profiler
------------------------------------------------------------------------------------------

local PROFILER_METRICS = {
    "SessionAverageTime", "RecentAverageTime", "EncounterAverageTime", "LastTime", "PeakTime",
    "CountTimeOver1Ms", "CountTimeOver5Ms", "CountTimeOver10Ms", "CountTimeOver50Ms", "CountTimeOver100Ms",
    "CountTimeOver500Ms", "CountTimeOver1000Ms",
}

-- The profiler's figures for one addon, by metric name, plus the share the addon list shows
-- (Blizzard_AddOnList: the addon's time over the application's time without the other addons).
function T.ReadProfiler(addonName)
    if not C_AddOnProfiler.IsEnabled() then
        return nil
    end
    local figures, share = {}, {}
    for _, name in ipairs(PROFILER_METRICS) do
        local metric = Enum.AddOnProfilerMetric[name]
        if metric then
            local value = C_AddOnProfiler.GetAddOnMetric(addonName, metric)
            figures[name] = value
            if not name:find("^Count") then
                local total = C_AddOnProfiler.GetApplicationMetric(metric) - C_AddOnProfiler.GetOverallMetric(metric)
                    + value
                share[name] = total > 0 and (value / total) or 0
            end
        end
    end
    figures.share = share
    return figures
end

T.Contract({
    id = "profiler.metrics",
    version = 1,
    title = "C_AddOnProfiler reports this addon's CPU time without extra setup",
    run = function(c)
        local enabled = C_AddOnProfiler.IsEnabled()
        c:Note("enabled", enabled)
        if not c:Check(enabled, "the addon profiler is off") then
            return
        end
        local figures = T.ReadProfiler(T.SUBJECT)
        c:Note("subject", figures)
        c:Note("tests", T.ReadProfiler(T.NAME))
        for _, name in ipairs(PROFILER_METRICS) do
            c:Check(type(figures[name]) == "number", "%s is a %s", name, TypeOf(figures[name]))
        end

        -- Timing.lua adds up LastTime frame by frame to get the addon's time for a stretch of
        -- play. That is only right if LastTime is the time spent in the frame before. Over three
        -- seconds, compare the sum with what the session average grew by.
        local frames, sum = 0, 0
        local deadline = GetTime() + 3
        while GetTime() < deadline do
            T.Yield()
            frames = frames + 1
            sum = sum + C_AddOnProfiler.GetAddOnMetric(T.SUBJECT, Enum.AddOnProfilerMetric.LastTime)
        end
        c:Note("lastTimeSample", {
            frames = frames,
            sumMs = sum,
            meanMs = frames > 0 and sum / frames or 0,
            recentAverageMs = C_AddOnProfiler.GetAddOnMetric(T.SUBJECT, Enum.AddOnProfilerMetric.RecentAverageTime),
        })
    end,
})

------------------------------------------------------------------------------------------
-- WoW Forever
------------------------------------------------------------------------------------------

local RED = { r = 0.9, g = 0.2, b = 0.2 }

local function HasRedText(lines)
    for _, line in ipairs(lines) do
        for _, color in ipairs({ line.leftColor, line.rightColor }) do
            if type(color) == "table" and (color.r or 0) > RED.r and (color.g or 1) < RED.g and (color.b or 1) < RED.b then
                return true
            end
        end
    end
    return false
end

T.Contract({
    id = "forever.canUseItem",
    version = 1,
    title = "Does C_PlayerInfo.CanUseItem know the classic armor proficiencies",
    flavor = "forever",
    perToon = true,
    run = function(c)
        local toon = T.GetToon()
        if not ((toon.class == "HUNTER" or toon.class == "SHAMAN") and toon.level < 40) then
            return "skip", "needs a hunter or shaman below level 40 (mail comes at 40)"
        end
        local itemID = 6550 -- Soldier's Wristguards, mail
        local item, why = T.LoadItem(itemID)
        if not item then
            return "skip", why
        end
        local facts = T.Facts.Item(item)
        local data = C_TooltipInfo.GetHyperlink(item:GetItemLink())
        local redText = HasRedText(data and data.lines or {})
        c:Note("item", facts)
        c:Note("tooltipHasRedText", redText)
        if (facts.minLevel or 0) > toon.level then
            return "skip", "the toon is below the item's own level requirement, so the answer proves nothing"
        end
        c:Note("answer", facts.canUse and "CanUseItem says usable: it does not know the proficiency"
            or "CanUseItem says not usable: it knows the proficiency")
        return "info"
    end,
})

T.Contract({
    id = "forever.laterExpansionItems",
    version = 1,
    title = "Does the client have item data from later expansions",
    flavor = "forever",
    run = function(c)
        local samples = {
            { id = 6948, from = "classic (control)" },
            { id = 34334, from = "The Burning Crusade" },
            { id = 49623, from = "Wrath of the Lich King" },
            { id = 71086, from = "Cataclysm" },
            { id = 93607, from = "Mists of Pandaria" },
            { id = 110560, from = "Warlords of Draenor" },
            { id = 140192, from = "Legion" },
        }
        local found = 0
        for _, sample in ipairs(samples) do
            sample.exists = C_Item.DoesItemExistByID(sample.id)
            if sample.exists then
                local item = T.LoadItem(sample.id, 5)
                if item then
                    sample.name = item:GetItemName()
                    sample.hasAppearance = select(2, C_TransmogCollection.GetItemInfo(item:GetItemLink())) ~= nil
                    if sample.id ~= 6948 then
                        found = found + 1
                    end
                end
            end
        end
        c:Note("items", samples)
        c:Note("laterExpansionItemsLoaded", found)
        return "info"
    end,
})
