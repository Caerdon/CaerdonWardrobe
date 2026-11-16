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
            T.SetResult("reload." .. how, "fail", { blocked = lastBlocked },
                "the UI was still running 2 seconds after ReloadUI()")
            T.Print("ReloadUI() did nothing (%s). Recorded; use /reload to save the results.", how)
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
    version = 1,
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
