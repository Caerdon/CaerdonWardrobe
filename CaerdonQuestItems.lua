-- Quest value for items that are not Quest-class items.
--
-- The client has no "which quest needs this item" API: quest objectives only expose their text,
-- and nothing at all exists for quests that are not in the log yet. Two sources answer it here:
--
--   1. The quest log. Item objectives of the quests the toon is on, matched by item name
--      ("Flagon of Dwarven Honeymead: 0/1"). Always available, no dependency.
--   2. QuestieDB, when it is loaded (LibQuestieDB, read through its public contract). It maps
--      item IDs to the quests that take them, which also covers quests that have not been
--      accepted yet - the "guide has you buy it early" case. Its own item -> quest field
--      (Item.relatedQuests) only covers a fraction of the pairs, so a reverse index is built
--      from every quest's objectives, a few milliseconds a frame.
--   3. AllTheThings, when it is loaded (CaerdonQuestSourceATT.lua): a second source of the
--      same two answers, for retail, where there is no QuestieDB, and beside it on WoW Forever.
--      It names further quests for an item, and a quest QuestieDB does not have is judged from
--      its data.
--
-- Whichever of the two a quest is judged from, its level and whether it is trivial for the
-- toon are the client's own word where it has the quest's data (CaerdonQuestClient.lua). For a
-- quest that is not in the log it has to be asked for that, so the quest is judged from the
-- quest data first and again when the client has answered.
--
-- A Quest-class item has the quest icon by its class. The same answer says when that is over:
-- every quest known for the item is behind the toon (done, or one it can never take), which is
-- how such an item loses the icon once its quest is turned in.
--
-- CaerdonItemMixin:GetQuestItemInfo() is the entry point for callers; the Debug Frame export
-- prints the full verdict list ("[Quest Value]").

local ADDON_NAME, NS = ...

CaerdonQuestItems = {}

-- The QuestieDB contract this was written for (the first with WoW Forever data).
local QUESTIEDB_CONTRACT = 2

-- A quest that is not in the log counts as "upcoming" when the toon can take it within this
-- many levels and it is not trivial (gray) for the toon yet.
-- (Icon.UpcomingQuestLevels; this is the value where the setting is not there.)
local DEFAULT_UPCOMING_LEVELS = 5
-- "Any level", as a number of levels.
local ANY_LEVEL = 1000
-- How many quests one question follows back along a chain before it gives up.
local CHAIN_BUDGET = 200

-- The player's choices for quests not picked up yet: how many levels ahead one still counts,
-- and whether one that is trivial for the toon does.
local function UpcomingSettings()
    local icon = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon
    local levels = icon and icon.UpcomingQuestLevels
    if levels == "any" then
        levels = ANY_LEVEL
    else
        levels = tonumber(levels) or DEFAULT_UPCOMING_LEVELS
    end
    return levels, icon ~= nil and icon.IncludeTrivialQuests == true
end
-- Used only if the client cannot report the trivial range.
local FALLBACK_TRIVIAL_RANGE = 7

-- Milliseconds of index building a frame gets.
local BUILD_SLICE_MS = 3
-- Quest events arrive in bursts and completion flags settle a moment after QUEST_TURNED_IN.
local REFRESH_DELAY = 0.5
-- Objective text can be empty until the client has the item cached; stop retrying eventually.
local MAX_INCOMPLETE_RESCANS = 10
local RESCAN_INTERVAL = 2

-- QuestieDB questFlags that mark a quest as repeating (daily, weekly, monthly).
local REPEATING_QUEST_FLAGS = { 4096, 32768, 65536 }
-- QuestieDB specialFlags: repeatable.
local SPECIAL_FLAG_REPEATABLE = 1

-- QuestieDB zoneOrSort values (negative = quest sort) for holidays and world events. Those quests
-- are only offered while the event runs, so they never count as upcoming. Questie's own event
-- list covers the same ground when Questie is loaded; this also works with QuestieDB alone.
local EVENT_QUEST_SORTS = {
    [-404] = true, -- Winter Veil
    [-402] = true, -- Harvest Festival
    [-378] = true, -- Children's Week
    [-376] = true, -- Love is in the Air
    [-375] = true, -- Pilgrim's Bounty
    [-374] = true, -- Noblegarden
    [-370] = true, -- Brewfest
    [-369] = true, -- Midsummer
    [-368] = true, -- Invasion
    [-366] = true, -- Lunar Festival
    [-365] = true, -- Ahn'Qiraj War Effort
    [-364] = true, -- Darkmoon Faire
    [-41] = true,  -- Day of the Dead
    [-22] = true,  -- Seasonal
    [-21] = true,  -- Hallow's End
}

-- Questie's blacklist value for a quest it only keeps off the map; the quest is still offered.
local QUESTIE_HIDE_ON_MAP = "HIDE_ON_MAP"

-- Classic-era faction-wide race masks. WoW Forever's Skyborne races use bits 32 and 33, which
-- these masks do not carry, so they are matched against the toon's faction instead of its race bit.
local CLASSIC_FACTION_MASK = { [77] = "Alliance", [178] = "Horde" }

-- Skill lines that are professions. requiredSkill can also name other skills (riding,
-- lockpicking), which cannot be checked reliably, so only these exclude a quest.
local PROFESSION_SKILL_LINES = {
    [129] = true, -- First Aid
    [164] = true, -- Blacksmithing
    [165] = true, -- Leatherworking
    [171] = true, -- Alchemy
    [182] = true, -- Herbalism
    [185] = true, -- Cooking
    [186] = true, -- Mining
    [197] = true, -- Tailoring
    [202] = true, -- Engineering
    [333] = true, -- Enchanting
    [356] = true, -- Fishing
    [393] = true, -- Skinning
}

local questLog = {
    dirty = true,         -- rescan before the next lookup
    awaitingData = true,  -- the log is not populated until the first QUEST_LOG_UPDATE after login
    incomplete = false,   -- an item objective had no name yet
    rescanAttempts = 0,
    lastRescanRequest = 0,
    lastScan = nil,
    questCount = 0,
    objectiveCount = 0,
    itemNames = {},       -- objective item name -> { questID, ... }
    error = nil,
    keptNames = 0,        -- objectives of the last scan that had no text and kept their name
}

-- The names the log's item objectives have had this session: questID -> { [objective] = name }.
-- An objective's text names its item only while the client has that item's data, and the
-- client drops item data again (notes: Upgrades, the item cache). A scan that finds an
-- objective without its text takes the name it had: forgetting it took the item's quest icon
-- away, and the name's return was then a change, with a refresh of everything for it. Seen
-- (retail 12.1.5.70961): two objectives of one quest named again 0.2 s into the first full
-- refresh of a session, and every window drawn a second time. A quest that leaves the log
-- takes its names with it.
local objectiveNames = {}
-- For the export: how often a scan kept a name, when last, and the rechecks made by timer.
local namesHistory = { scansThatKept = 0, lastKept = nil, rechecks = 0 }

-- AllTheThings, the second source of quest data (CaerdonQuestSourceATT.lua).
local SecondSource = NS.QuestSourceATT
-- The client's own word on a quest's level and on trivial (CaerdonQuestClient.lua).
local QuestClient = NS.QuestClient
-- For the export: how often the client's answers were compared with what the icons were made
-- from, how often that was a change, and the last one; how many quests were judged again for
-- it and what that took, always, since it runs with no window being drawn.
local clientHistory = { checks = 0, changes = 0, lastChange = nil, judged = 0, ms = 0, longestMs = 0 }

local provider = {
    state = "unchecked",  -- unchecked | missing | unsupported | building | ready | failed
    lib = nil,
    index = nil,          -- itemID -> { [questID] = role }
    known = nil,          -- [questID] = true for every quest QuestieDB has
    starters = nil,       -- itemID -> { [questID] = true } for items that start a quest
    itemCount = 0,
    questCount = 0,
    buildMs = 0,
    error = nil,
}

-- questID -> verdict; dropped whenever the main frame refreshes.
local verdicts = {}
-- questID -> the verdict last handed out since then, the ones that are not kept included.
-- The icons on screen were made from these, and a quest event is compared with them
-- (CompareWithAnswers).
local answered = {}
local playerContext
local questieModules
local questieReadyHooked = false
local refreshTimer

local function HasBit(mask, flag)
    -- Race masks go past 2^32 on WoW Forever, so no bit library here.
    return mask % (flag * 2) >= flag
end

-- For what is always a change: the quest data has come, or the log's objectives have their
-- names. A quest event is compared first and goes through the watch at the end of this file.
local function RequestRefresh(reason, detail)
    if refreshTimer then
        return
    end

    refreshTimer = C_Timer.NewTimer(REFRESH_DELAY, function()
        refreshTimer = nil
        -- RefreshItems calls InvalidateCaches below, so anything judged while this timer
        -- was pending is dropped again.
        if CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
            CaerdonWardrobe:RefreshItems(reason, detail)
        end
    end)
end

-- Forgets the answers with the verdicts, so it goes with a redraw of every icon: RefreshItems
-- calls it, and the callers in this file ask for a refresh.
--
-- changed: what the refresh is about (CaerdonWardrobe:RefreshItems), nil for anything. A quest
-- is judged from the log, the completion flags, the quest data and the toon's level, race,
-- class, faction and professions, and the client's word on the quest's level and on trivial
-- (JudgeQuest, UpcomingBlocker), and the log's objectives name
-- items whatever is worn or learned. So a refresh about what is worn or about something
-- learned keeps all of it: no quest is judged again and the log is not read again. The answers
-- then hold quests of items that may not be drawn again, and a quest event judges those too:
-- at worst a refresh nobody needed.
function CaerdonQuestItems:InvalidateCaches(changed)
    if changed == "worn" or changed == "collection" then
        return
    end
    wipe(verdicts)
    wipe(answered)
    SecondSource:InvalidateCaches()
    QuestClient:InvalidateCaches()
    playerContext = nil
    questLog.dirty = true
end

----------------------------------------------------------------------------------------------
-- Quest log
----------------------------------------------------------------------------------------------

-- "Flagon of Dwarven Honeymead: 0/1" (classic layout) or "0/1 Flagon of Dwarven Honeymead"
-- (retail layout) -> "Flagon of Dwarven Honeymead". nil while the client has no name yet.
local function ObjectiveItemName(text)
    if type(text) ~= "string" then
        return nil
    end

    local name = text:gsub("^%s*%d+%s*/%s*%d+%s*", "")
    name = name:gsub("%s*%d+%s*/%s*%d+%s*$", "")
    name = name:gsub("：$", "") -- full-width colon (zhCN / zhTW)
    name = name:gsub(":$", "")
    name = strtrim(name)

    if name == "" then
        return nil
    end
    return name
end

local function ScanQuestLog()
    local itemNames = {}
    local incomplete = false
    local questCount = 0
    local objectiveCount = 0
    local kept = 0
    local inLog = {}

    local numEntries = C_QuestLog.GetNumQuestLogEntries() or 0
    for index = 1, numEntries do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader and info.questID and info.questID > 0 then
            questCount = questCount + 1
            inLog[info.questID] = true

            local objectives = C_QuestLog.GetQuestObjectives(info.questID)
            if objectives then
                for objectiveIndex, objective in ipairs(objectives) do
                    if objective.type == "item" then
                        local name = ObjectiveItemName(objective.text)
                        local known = objectiveNames[info.questID]
                        if name then
                            if not known then
                                known = {}
                                objectiveNames[info.questID] = known
                            end
                            known[objectiveIndex] = name
                        elseif known and known[objectiveIndex] then
                            name = known[objectiveIndex]
                            kept = kept + 1
                        end
                        if name then
                            objectiveCount = objectiveCount + 1
                            local quests = itemNames[name]
                            if not quests then
                                quests = {}
                                itemNames[name] = quests
                            end
                            quests[#quests + 1] = info.questID
                        else
                            incomplete = true
                        end
                    end
                end
            end
        end
    end

    -- In the order of their IDs, so that a quest moving in the log is not a change.
    for _, quests in pairs(itemNames) do
        table.sort(quests)
    end
    for questID in pairs(objectiveNames) do
        if not inLog[questID] then
            objectiveNames[questID] = nil
        end
    end

    return itemNames, incomplete, questCount, objectiveCount, kept
end

-- An objective without a name is asked about again by the clock, and not only when the next
-- QUEST_LOG_UPDATE comes: the one that brings the name can come within RESCAN_INTERVAL of the
-- scan that found it missing, where the event's own check lets it pass, and standing still
-- sends no other. As many times as the event's check allows (MAX_INCOMPLETE_RESCANS).
local RescanForNames
local recheckTimer
local function ScheduleRecheck()
    if recheckTimer or questLog.awaitingData or questLog.rescanAttempts >= MAX_INCOMPLETE_RESCANS then
        return
    end
    recheckTimer = C_Timer.NewTimer(RESCAN_INTERVAL, function()
        recheckTimer = nil
        if questLog.incomplete and not questLog.awaitingData then
            questLog.rescanAttempts = questLog.rescanAttempts + 1
            namesHistory.rechecks = namesHistory.rechecks + 1
            RescanForNames()
        end
    end)
end

local function EnsureQuestLog()
    if not questLog.dirty then
        return
    end
    questLog.dirty = false

    local ok, itemNames, incomplete, questCount, objectiveCount, kept = pcall(ScanQuestLog)
    if ok then
        questLog.itemNames = itemNames
        questLog.incomplete = incomplete
        questLog.questCount = questCount
        questLog.objectiveCount = objectiveCount
        questLog.keptNames = kept
        questLog.error = nil
    else
        questLog.error = tostring(itemNames)
        questLog.itemNames = {}
        questLog.incomplete = false
        questLog.questCount = 0
        questLog.objectiveCount = 0
        questLog.keptNames = 0
    end
    questLog.lastScan = GetTime()
    if questLog.keptNames > 0 then
        namesHistory.scansThatKept = namesHistory.scansThatKept + 1
        namesHistory.lastKept = questLog.lastScan
    end
    if questLog.incomplete then
        ScheduleRecheck()
    end
end

-- The log's item objectives as a flat reading (NS.Refresh:Difference): which quests name
-- which item.
local function AddNamesReading(itemNames, reading)
    for name, quests in pairs(itemNames) do
        reading["objective " .. name] = table.concat(quests, ",")
    end
    return reading
end

-- Reads the log again and asks for a refresh where the objectives' names are not what they
-- were: for the event that may have brought a name (byEvent: the interval between two such
-- checks counts from this one), and for the recheck by the clock, which leaves the next
-- event free to be checked at once.
RescanForNames = function(byEvent)
    if byEvent then
        questLog.lastRescanRequest = GetTime()
    end
    local previous = AddNamesReading(questLog.itemNames, {})
    questLog.dirty = true
    EnsureQuestLog()
    local what = NS.Refresh:Difference(previous, AddNamesReading(questLog.itemNames, {}))
    if what then
        RequestRefresh("quest log", what)
    end
end

----------------------------------------------------------------------------------------------
-- QuestieDB
----------------------------------------------------------------------------------------------

-- QuestieDB, when its contract and shape are the ones this was written for.
local function ResolveLibrary()
    local lib = _G.LibQuestieDB
    if type(lib) ~= "table" then
        return nil, "missing"
    end
    if type(lib.RequireContract) ~= "function" then
        return nil, "unsupported"
    end

    local ok, compatible = pcall(lib.RequireContract, QUESTIEDB_CONTRACT)
    local quest = lib.Quest
    if not (ok and compatible) or type(quest) ~= "table" or type(quest.Get) ~= "function" or
        type(quest.GetAllIds) ~= "function" then
        return nil, "unsupported"
    end

    return lib
end

-- Questie's own quest policy (blacklist, holiday quests), when Questie is loaded.
local function GetQuestieModules()
    if questieModules then
        return questieModules
    end

    local loader = _G.QuestieLoader
    if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then
        return nil
    end

    local okCorrections, corrections = pcall(loader.ImportModule, loader, "QuestieCorrections")
    local okEvents, events = pcall(loader.ImportModule, loader, "QuestieEvent")
    questieModules = {
        corrections = okCorrections and type(corrections) == "table" and corrections or nil,
        events = okEvents and type(events) == "table" and events or nil,
    }

    -- Questie fills its blacklist while it starts, so verdicts reached before that are redone.
    if not questieReadyHooked then
        questieReadyHooked = true
        local api = type(_G.Questie) == "table" and _G.Questie.API
        if type(api) == "table" and type(api.RegisterOnReady) == "function" then
            pcall(api.RegisterOnReady, function()
                CaerdonQuestItems:InvalidateCaches()
                RequestRefresh("quest data", "Questie is ready")
            end)
        end
    end

    return questieModules
end

-- Returns a reason when Questie considers the quest unavailable in this game version.
local function QuestieHiddenReason(questID)
    local modules = GetQuestieModules()
    if not modules then
        return nil
    end

    local hidden = modules.corrections and modules.corrections.hiddenQuests
    local value = type(hidden) == "table" and hidden[questID]
    if value ~= nil and value ~= false and value ~= QUESTIE_HIDE_ON_MAP then
        return "hidden by Questie"
    end

    local isEventQuest = modules.events and modules.events.IsEventQuest
    if type(isEventQuest) == "function" and isEventQuest(questID) == true then
        return "event quest"
    end

    return nil
end

-- What Questie's own policy says about one quest. With GetIndexedQuests below, this is all the
-- judging code takes from data it cannot ask for one item at a time: Questie's module tables
-- here, the index over every quest there. Both are methods so that a test can record what
-- they answered for one item and hand it back (docs/dev-notes.md, Offline Harness).
function CaerdonQuestItems:GetQuestieHiddenReason(questID)
    return QuestieHiddenReason(questID)
end

-- Runs inside the build coroutine. Reads four fields for every quest.
local function BuildIndex(lib, yieldIfNeeded)
    local Get = lib.Quest.Get
    local ids = lib.Quest.GetAllIds()
    local index, starters, known = {}, {}, {}
    local itemCount = 0

    local function Add(itemID, questID, role)
        if type(itemID) ~= "number" or itemID <= 0 then
            return
        end
        local quests = index[itemID]
        if not quests then
            quests = {}
            index[itemID] = quests
            itemCount = itemCount + 1
        end
        -- A quest can name an item twice: what it hands over is often an objective too, and
        -- which of them it is decides whether the item was that quest's own.
        local had = quests[questID]
        if not had then
            quests[questID] = role
        elseif not had:find(role, 1, true) then
            quests[questID] = had .. ", " .. role
        end
    end

    for position = 1, #ids do
        local questID = ids[position]
        known[questID] = true

        -- { creatures, objects, items, reputation, killCredit, spells }
        local objectives = Get(questID, "objectives")
        if type(objectives) == "table" then
            local items = objectives[3]
            if type(items) == "table" then
                for _, entry in pairs(items) do
                    if type(entry) == "table" then
                        Add(entry[1], questID, "objective")
                    end
                end
            end
            -- Spell objectives name the item that casts the spell: { spellID, text, itemID }
            local spells = objectives[6]
            if type(spells) == "table" then
                for _, entry in pairs(spells) do
                    if type(entry) == "table" then
                        Add(entry[3], questID, "used")
                    end
                end
            end
        end

        -- Not objectives, but still needed to complete the quest
        local required = Get(questID, "requiredSourceItems")
        if type(required) == "table" then
            for _, itemID in pairs(required) do
                Add(itemID, questID, "required")
            end
        end

        -- The item the quest hands over when it is accepted, carried until it is turned in
        -- (a letter, a kit, a cursed relic to take somewhere). Often neither an objective nor
        -- a required item, so nothing above names it.
        Add(Get(questID, "sourceItemId"), questID, "provided")

        -- { npcs, objects, items }
        local startedBy = Get(questID, "startedBy")
        local starterItems = type(startedBy) == "table" and startedBy[3]
        if type(starterItems) == "table" then
            for _, itemID in pairs(starterItems) do
                if type(itemID) == "number" and itemID > 0 then
                    local quests = starters[itemID]
                    if not quests then
                        quests = {}
                        starters[itemID] = quests
                    end
                    quests[questID] = true
                end
            end
        end

        yieldIfNeeded()
    end

    return index, starters, itemCount, #ids, known
end

local function StartBuild(lib)
    provider.state = "building"

    local sliceStart = 0
    local workMs = 0
    local builder = coroutine.create(function()
        return BuildIndex(lib, function()
            if debugprofilestop() - sliceStart >= BUILD_SLICE_MS then
                coroutine.yield()
            end
        end)
    end)

    local function Step()
        sliceStart = debugprofilestop()
        local ok, index, starters, itemCount, questCount, known = coroutine.resume(builder)
        workMs = workMs + (debugprofilestop() - sliceStart)

        if not ok then
            -- Unexpected data shape: leave the quest-log matching in place and say why.
            provider.state = "failed"
            provider.error = tostring(index)
            return
        end

        if coroutine.status(builder) ~= "dead" then
            C_Timer.After(0, Step)
            return
        end

        provider.index = index
        provider.starters = starters
        provider.known = known
        provider.itemCount = itemCount
        provider.questCount = questCount
        provider.buildMs = workMs
        provider.state = "ready"

        CaerdonQuestItems:InvalidateCaches()
        RequestRefresh("quest data", "the index is built")
    end

    -- Never inside the lookup that discovered the library
    C_Timer.After(0, Step)
end

local function EnsureProvider()
    local state = provider.state
    if state ~= "unchecked" and state ~= "missing" then
        return
    end

    -- "missing" is checked again on every lookup: QuestieDB loads after this addon.
    local lib, reason = ResolveLibrary()
    if not lib then
        provider.state = reason
        return
    end

    provider.lib = lib
    GetQuestieModules()
    StartBuild(lib)
end

----------------------------------------------------------------------------------------------
-- Quest eligibility
----------------------------------------------------------------------------------------------

local function GetPlayerContext()
    if playerContext then
        return playerContext
    end

    local enum = provider.lib and provider.lib.Enum
    local _, _, raceID = UnitRace("player")
    local _, classFile, classID = UnitClass("player")

    local raceFlag = type(enum) == "table" and type(enum.raceMaskById) == "table" and enum.raceMaskById[raceID]
    if not raceFlag and raceID then
        raceFlag = 2 ^ (raceID - 1)
    end

    local classFlag = type(enum) == "table" and type(enum.classKeys) == "table" and enum.classKeys[classFile]
    if not classFlag and classID then
        classFlag = 2 ^ (classID - 1)
    end

    -- Profession skill lines. If the client reports IDs this does not recognise, the profession
    -- check is skipped rather than excluding every profession quest.
    local skillLines
    if GetProfessions and GetProfessionInfo then
        local found, recognised = {}, false
        local hasAny = false
        for _, professionIndex in pairs({ GetProfessions() }) do
            local skillLine = select(7, GetProfessionInfo(professionIndex))
            if skillLine then
                hasAny = true
                found[skillLine] = true
                if PROFESSION_SKILL_LINES[skillLine] then
                    recognised = true
                end
            end
        end
        if recognised or not hasAny then
            skillLines = found
        end
    end

    local trivialRange = UnitQuestTrivialLevelRange and UnitQuestTrivialLevelRange("player")
    if type(trivialRange) ~= "number" then
        trivialRange = GetQuestGreenRange and GetQuestGreenRange() or FALLBACK_TRIVIAL_RANGE
    end

    local levelWindow, includeTrivial = UpcomingSettings()
    playerContext = {
        levelWindow = levelWindow,
        includeTrivial = includeTrivial,
        level = UnitLevel("player") or 0,
        raceID = raceID,
        classID = classID,
        raceFlag = raceFlag,
        classFlag = classFlag,
        faction = UnitFactionGroup("player"),
        skillLines = skillLines,
        trivialRange = trivialRange,
    }
    return playerContext
end

local function IsQuestDone(questID)
    return type(questID) == "number" and questID > 0 and C_QuestLog.IsQuestFlaggedCompleted(questID)
end

local function IsQuestDoneOrActive(questID)
    return type(questID) == "number" and questID > 0 and
        (C_QuestLog.IsQuestFlaggedCompleted(questID) or C_QuestLog.IsOnQuest(questID))
end

-- A quest that can be done again (repeatable, daily, weekly, monthly).
local function IsRepeating(questID, Get)
    if HasBit(Get(questID, "specialFlags") or 0, SPECIAL_FLAG_REPEATABLE) then
        return true
    end
    local questFlags = Get(questID, "questFlags") or 0
    for _, flag in ipairs(REPEATING_QUEST_FLAGS) do
        if HasBit(questFlags, flag) then
            return true
        end
    end
    return false
end

-- Whether a quest has quests before it, and whether those are done, in the log, or
-- themselves further along a chain the toon is on: every one of preQuestGroup, and one of
-- preQuestSingle. A first step that is neither done nor in the log is a chain not begun.
local ChainQuestBegun
local function PrerequisitesBegun(questID, Get, seen, budget)
    local has, begun = false, true
    local group = Get(questID, "preQuestGroup")
    if type(group) == "table" then
        for _, beforeID in pairs(group) do
            if type(beforeID) == "number" and beforeID ~= 0 then
                has = true
                if not ChainQuestBegun(math.abs(beforeID), Get, seen, budget) then
                    begun = false
                end
            end
        end
    end
    local single = Get(questID, "preQuestSingle")
    if type(single) == "table" then
        local any, one = false, false
        for _, beforeID in pairs(single) do
            if type(beforeID) == "number" and beforeID ~= 0 then
                any = true
                if ChainQuestBegun(math.abs(beforeID), Get, seen, budget) then
                    one = true
                end
            end
        end
        if any then
            has = true
            begun = begun and one
        end
    end
    return has, has and begun
end

ChainQuestBegun = function(questID, Get, seen, budget)
    if IsQuestDoneOrActive(questID) then
        return true
    end
    if seen[questID] or budget.left <= 0 then
        return false
    end
    seen[questID] = true
    budget.left = budget.left - 1
    return (select(2, PrerequisitesBegun(questID, Get, seen, budget)))
end

-- Why a quest that is neither in the log nor completed will not be picked up, or nil when it
-- still can be. Second value: the answer depends on bag contents and must not be cached.
-- Third: the quest is behind this toon for good (another faction's, a chain that has gone
-- past it). A blocker that time, a level or a profession can lift does not say that, and
-- neither does one that only says the quest is not offered now.
--
-- The reason given is the first one found. Whether the quest is behind the toon is asked of
-- every rule that can say so, whichever was found first: otherwise a quest a chain had gone
-- past would stop being behind the toon when a quest it is exclusive with is accepted, which
-- is found earlier and is not for good.
local function UpcomingBlocker(questID, verdict, Get)
    local blocker, forGood = nil, false
    local function Block(reason, behind)
        blocker = blocker or reason
        forGood = forGood or behind == true
    end

    local hiddenReason = CaerdonQuestItems:GetQuestieHiddenReason(questID)
    if hiddenReason then
        Block(hiddenReason)
    end

    if EVENT_QUEST_SORTS[Get(questID, "zoneOrSort") or 0] then
        Block("event quest")
    end

    local player = GetPlayerContext()

    local raceMask = Get(questID, "requiredRaces") or 0
    if raceMask ~= 0 and player.raceFlag then
        local factionOfMask = CLASSIC_FACTION_MASK[raceMask]
        if factionOfMask then
            if factionOfMask ~= player.faction then
                Block("other faction", true)
            end
        elseif not HasBit(raceMask, player.raceFlag) then
            Block("other race", true)
        end
    end

    local classMask = Get(questID, "requiredClasses") or 0
    if classMask ~= 0 and player.classFlag and not HasBit(classMask, player.classFlag) then
        Block("other class", true)
    end

    if IsRepeating(questID, Get) then
        verdict.repeating = true
        Block("repeatable")
    end

    local requiredSkill = Get(questID, "requiredSkill")
    local skillLine = type(requiredSkill) == "table" and requiredSkill[1]
    if skillLine and PROFESSION_SKILL_LINES[skillLine] and player.skillLines and not player.skillLines[skillLine] then
        Block("profession not learned")
    end

    local exclusiveTo = Get(questID, "exclusiveTo")
    if type(exclusiveTo) == "table" then
        for _, otherQuestID in pairs(exclusiveTo) do
            if IsQuestDoneOrActive(otherQuestID) then
                -- For good once the other one is done; one in the log can still be abandoned.
                Block("exclusive with quest " .. tostring(otherQuestID), IsQuestDone(otherQuestID) == true)
            end
        end
    end

    -- A later quest of the chain being active or done means this one is behind the toon.
    local nextQuest = Get(questID, "nextQuestInChain")
    if IsQuestDoneOrActive(nextQuest) then
        Block("chain already past it", true)
    end

    -- Only offered while its parent is in progress
    if IsQuestDone(Get(questID, "parentQuest")) then
        Block("parent quest completed", true)
    end

    if IsQuestDone(Get(questID, "availableUntilCompleted")) then
        Block("no longer offered", true)
    end

    local requiredLevel = Get(questID, "requiredLevel") or 0
    local questLevel = Get(questID, "questLevel") or 0
    verdict.requiredLevel = requiredLevel
    verdict.questLevel = questLevel

    local maxLevel = Get(questID, "requiredMaxLevel") or 0
    if maxLevel > 0 and player.level > maxLevel then
        Block("outleveled", true)
    end

    -- The quest's own level and whether it is trivial are the client's to say, where it has
    -- the quest's data (CaerdonQuestClient.lua); where it has none it is asked for it, the
    -- quest data's level stands meanwhile, and the quest is judged again when the answer
    -- comes (CompareWithClient). It is asked only where its word can change the verdict: not
    -- of a quest that is behind the toon whatever its level, and not of one the level it is
    -- known to ask for keeps out. The level a quest asks for is the quest data's: no client
    -- has a function for it.
    local client
    local function ClientFacts()
        if client == nil then
            client = false
            if not forGood then
                local facts, why = QuestClient:GetFacts(questID)
                if facts then
                    client = facts
                    if facts.level > 0 then
                        questLevel = facts.level
                        verdict.levelFromClient = true
                    end
                else
                    verdict.clientState = why
                end
            end
        end
        return client or nil
    end

    -- A later quest of a chain the toon is on is still to come, whatever its level: the
    -- quests before it are followed back, and only for a quest the level would keep out.
    -- Where the data has no level the quest asks for (0: over a hundred of the quests WoW
    -- Forever added, all of level 50 and up), the quest's own level stands in for it. It is
    -- never below the level asked for, so it keeps out no quest the toon is of a level for
    -- by more than the difference between the two.
    local levelKnown = requiredLevel > 0
    if not levelKnown then
        ClientFacts()
    end
    local levelAsked = levelKnown and requiredLevel or questLevel
    local beyondRange = levelAsked > player.level + player.levelWindow and
        not select(2, PrerequisitesBegun(questID, Get, {}, { left = CHAIN_BUDGET }))
    if beyondRange then
        verdict.optedOut = true
        if levelKnown then
            Block(format("needs level %d", requiredLevel))
        else
            Block(format("of level %d, and the level it asks for is not known", questLevel))
        end
    end
    if not player.includeTrivial then
        local facts = not (beyondRange and levelKnown) and ClientFacts() or nil
        local trivial
        if facts then
            trivial = facts.trivial
        else
            -- Zero and negative quest levels scale with the toon
            trivial = questLevel > 0 and questLevel < player.level - player.trivialRange
        end
        if trivial then
            verdict.optedOut = true
            Block("trivial at this level")
        end
    end
    verdict.questLevel = questLevel

    if blocker then
        return blocker, false, forGood
    end

    -- A quest only an item can start is not upcoming unless that item is already owned.
    local startedBy = Get(questID, "startedBy")
    if type(startedBy) == "table" then
        local hasGiver = (type(startedBy[1]) == "table" and next(startedBy[1]) ~= nil) or
            (type(startedBy[2]) == "table" and next(startedBy[2]) ~= nil)
        local starterItems = startedBy[3]
        if not hasGiver and type(starterItems) == "table" and next(starterItems) ~= nil then
            for _, starterItemID in pairs(starterItems) do
                -- Asked off C_Item at the time, which both clients have: a function taken
                -- into a local as this file loads is one the test addon's recorder cannot
                -- hear, and a recording of such an item then lacks the answer.
                if (C_Item.GetItemCount(starterItemID, true) or 0) > 0 then
                    return nil, true
                end
            end
            return "starter item not owned", true
        end
    end

    return nil
end

-- One quest judged from the client and the quest data as they are now; nothing is kept.
-- Second value: the answer depends on what is in the bags and must not be kept.
-- verdict.over: the quest is behind this toon, done or never to be taken. A quest that is
-- done and can be done again is not, and without quest data nothing says which it is.
local function JudgeQuest(questID)
    local verdict = { questID = questID, eligible = false, isActive = false, over = false }

    local Get = provider.lib and provider.lib.Quest.Get
    -- A quest QuestieDB does not have is judged from AllTheThings' data, where that has it.
    -- While the index is not built yet nothing says which quests QuestieDB has, and it is
    -- asked as before.
    local second = nil
    if not (Get and (provider.known == nil or provider.known[questID])) then
        Get = nil
        if SecondSource:Knows(questID) then
            second = SecondSource
            verdict.source = "AllTheThings"
        end
    end
    local volatile = false

    local ok, failure = pcall(function()
        verdict.name = (Get and Get(questID, "name")) or C_QuestLog.GetTitleForQuestID(questID)

        if C_QuestLog.IsOnQuest(questID) then
            verdict.isActive = true
            verdict.eligible = true
            verdict.reason = "in quest log"
        elseif C_QuestLog.IsQuestFlaggedCompleted(questID) then
            verdict.reason = "completed"
            verdict.repeating = (Get ~= nil and IsRepeating(questID, Get)) or
                (second ~= nil and second:IsRepeating(questID))
            verdict.over = (Get ~= nil or second ~= nil) and not verdict.repeating
        elseif second then
            local blocker, forGood, repeating, minLevel, _, optedOut, client = second:Blocker(questID, GetPlayerContext())
            verdict.eligible = blocker == nil
            verdict.reason = blocker or "upcoming"
            verdict.over = blocker ~= nil and forGood == true
            verdict.repeating = repeating == true
            verdict.requiredLevel = minLevel
            verdict.optedOut = optedOut == true
            -- What the client said of it, or why it has not: AllTheThings has no quest level.
            if client then
                verdict.questLevel = client.level
                verdict.levelFromClient = client.level ~= nil
                verdict.clientState = client.state
            end
        elseif not Get then
            verdict.reason = "no quest data"
        else
            local blocker, dependsOnBags, forGood = UpcomingBlocker(questID, verdict, Get)
            volatile = dependsOnBags or false
            verdict.eligible = blocker == nil
            verdict.reason = blocker or "upcoming"
            verdict.over = blocker ~= nil and forGood == true
        end
    end)

    if not ok then
        verdict.eligible = false
        verdict.isActive = false
        verdict.over = false
        verdict.reason = "error: " .. tostring(failure)
    end

    return verdict, volatile
end

local function EvaluateQuest(questID)
    local verdict = verdicts[questID]
    if verdict then
        return verdict
    end

    local volatile
    verdict, volatile = JudgeQuest(questID)
    if not volatile then
        verdicts[questID] = verdict
    end
    answered[questID] = verdict
    return verdict
end

-- What a verdict means for an icon, which is all a quest event or the client's word is
-- compared on. "Behind it" is apart from "not wanted": a Quest-class item keeps its icon
-- through the second and loses it with the first. And "kept out by the options" is apart from
-- "not wanted": where that is all that is left for an item, its class gives it no quest icon.
local function StateOf(verdict)
    return verdict.isActive and "in the log" or verdict.eligible and "upcoming" or
        verdict.over and "behind it" or verdict.optedOut and "kept out by the options" or "not wanted"
end

-- The check after a run of quest events (accepted, removed, turned in): what differs from
-- what was answered since the caches were last dropped, in words, or nil.
--
-- Most quests take no item that is carried or shown, and their events change no icon. An
-- icon follows from two things here: whether a quest it was asked about is in the log, still
-- to come, behind the toon or none of those, and which items the log's objectives name. Both
-- are read again. Every
-- answered quest is judged again, not only the quest of the event: that one can decide about
-- others (the one before it in a chain, one it excludes, one offered only until it is done).
function CaerdonQuestItems:CompareWithAnswers()
    -- A new quest's objectives may have no text yet; QUEST_LOG_UPDATE tries again from zero.
    questLog.rescanAttempts = 0

    local before, after = {}, {}

    -- A log that was not read since the caches were dropped has answered nothing.
    if not questLog.dirty then
        AddNamesReading(questLog.itemNames, before)
        questLog.dirty = true
        EnsureQuestLog()
        AddNamesReading(questLog.itemNames, after)
    end

    for questID, answer in pairs(answered) do
        local verdict, volatile = JudgeQuest(questID)
        local key = "quest " .. questID
        before[key], after[key] = StateOf(answer), StateOf(verdict)
        -- Where nothing differs the new verdict stands in: its reason is the export's.
        answered[questID] = verdict
        verdicts[questID] = not volatile and verdict or nil
    end

    return NS.Refresh:Difference(before, after)
end

-- The client's data of these quests has come (CaerdonQuestClient.lua). Each one that was
-- answered since the caches were last dropped is judged again, now with the client's word on
-- its level and on trivial, and the icons are drawn again only where that is another answer
-- for an icon than the quest data's was. Only these quests: a quest's level decides about no
-- other quest.
--
-- Returns what differs, in words, or nil; for the tests and the counters.
function CaerdonQuestItems:CompareWithClient(questIDs)
    local startedAt = debugprofilestop()
    local before, after = {}, {}
    for _, questID in ipairs(questIDs) do
        local answer = answered[questID]
        if answer then
            local verdict, volatile = JudgeQuest(questID)
            local key = "quest " .. questID
            before[key], after[key] = StateOf(answer), StateOf(verdict)
            -- Where nothing differs the new verdict stands in: its level is the export's.
            answered[questID] = verdict
            verdicts[questID] = not volatile and verdict or nil
            clientHistory.judged = clientHistory.judged + 1
        end
    end

    local what = NS.Refresh:Difference(before, after)
    clientHistory.checks = clientHistory.checks + 1
    local spent = debugprofilestop() - startedAt
    clientHistory.ms = clientHistory.ms + spent
    if spent > clientHistory.longestMs then
        clientHistory.longestMs = spent
    end
    if what then
        clientHistory.changes = clientHistory.changes + 1
        clientHistory.lastChange = what
        if CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
            CaerdonWardrobe:RefreshItems("quest data", "the client's word: " .. what)
        end
    end
    return what
end

-- Through the table, so that the counters' wrapper is the one called.
QuestClient.OnAnswers = function(questIDs)
    CaerdonQuestItems:CompareWithClient(questIDs)
end

-- Forgets what the client said of quests this session, which a refresh rightly keeps. For the
-- test addon's recorder: a replay starts a session of its own.
function CaerdonQuestItems:ForgetClientAnswers()
    QuestClient:Forget()
end

----------------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------------

local function SortQuests(left, right)
    if left.isActive ~= right.isActive then
        return left.isActive
    end
    if left.eligible ~= right.eligible then
        return left.eligible
    end
    return left.questID < right.questID
end

-- The quests QuestieDB names for an item, from the index built over every quest: those that
-- take it (questID -> role) and those it starts (questID -> true). nil for either when there
-- are none, or while there is no index.
function CaerdonQuestItems:GetIndexedQuests(itemID)
    if not itemID then
        return nil, nil
    end
    local indexed = provider.index and provider.index[itemID] or nil
    local started = provider.starters and provider.starters[itemID] or nil

    -- What AllTheThings names beside that. The index's tables are not written to.
    local takes, starts = SecondSource:GetItemQuests(itemID)
    if takes then
        local merged = {}
        for questID, role in pairs(indexed or {}) do
            merged[questID] = role
        end
        for questID, role in pairs(takes) do
            merged[questID] = merged[questID] or role
        end
        indexed = merged
    end
    if starts then
        local merged = {}
        for questID in pairs(started or {}) do
            merged[questID] = true
        end
        for questID in pairs(starts) do
            merged[questID] = true
        end
        started = merged
    end
    return indexed, started
end

-- What the client itself says about the item in a bag slot, as Blizzard's bags read it for
-- their quest border and bang: { isQuestItem, questID, isActive }, where questID is the quest
-- the item starts and isActive whether that quest is in the log. nil where the client has no
-- answer. It is read for the export and the test addon; no status is made from it.
function CaerdonQuestItems:GetSlotQuestInfo(bag, slot)
    local ask = C_Container and C_Container.GetContainerItemQuestInfo
    if not ask or bag == nil or slot == nil then
        return nil
    end
    local info = ask(bag, slot)
    return type(info) == "table" and info or nil
end

-- How many levels ahead of the toon a quest still counts as coming, by the player's setting
-- (a large number for "any"). For a quest's item no quest is known for, whose own required
-- level is all there is to go by (CaerdonItemMixin:IsQuestItemBeyondRange).
function CaerdonQuestItems:GetUpcomingLevelWindow()
    return (UpcomingSettings())
end

-- Returns nil when no known quest takes the item. Otherwise:
--   hasQuestValue  an unfinished quest that applies to this toon takes the item (honours the
--                  "upcoming quests" setting)
--   isActive       a quest in the log takes it
--   isUpcoming     a quest the toon has not accepted yet takes it
--   isOver         every quest known for it is behind the toon: done, or never to be taken.
--                  False while one of them is only out of reach for now (a level, a
--                  profession, an event) or can be done again. One that can be done again
--                  does not count (setAside) where a quest that handed the item over is
--                  behind the toon.
--   repeatableLeft isOver is true by that alone: a quest that can be done again still takes
--                  the item.
--   keptOutByOptions  every quest not behind the toon is beyond the player's range of levels
--                  or trivial where those are not wanted (optedOut on each)
--   quests         every candidate quest with its verdict, the rejected ones included:
--                  { questID, name, role, isActive, eligible, over, repeating, setAside,
--                  reason, requiredLevel, questLevel, levelFromClient, clientState }; the
--                  last one says why the client had no word where it was wanted
function CaerdonQuestItems:GetItemQuestInfo(itemID, itemName)
    EnsureQuestLog()
    EnsureProvider()

    local nameMatches = itemName and questLog.itemNames[itemName]
    local indexed, started = self:GetIndexedQuests(itemID)
    if not nameMatches and not indexed and not started then
        return nil
    end

    local info = { hasQuestValue = false, isActive = false, isUpcoming = false, isOver = true, quests = {} }
    local byQuest = {}

    local function Add(questID, role)
        local entry = byQuest[questID]
        if entry then
            entry.role = entry.role .. ", " .. role
            return
        end

        local verdict = EvaluateQuest(questID)
        entry = {
            questID = questID,
            name = verdict.name,
            role = role,
            isActive = verdict.isActive,
            eligible = verdict.eligible,
            over = verdict.over,
            source = verdict.source,
            optedOut = verdict.optedOut == true,
            repeating = verdict.repeating == true,
            reason = verdict.reason,
            requiredLevel = verdict.requiredLevel,
            questLevel = verdict.questLevel,
            levelFromClient = verdict.levelFromClient == true,
            clientState = verdict.clientState,
        }
        byQuest[questID] = entry
        info.quests[#info.quests + 1] = entry

        if verdict.isActive then
            info.isActive = true
        elseif verdict.eligible then
            info.isUpcoming = true
        end
        if not verdict.over then
            info.isOver = false
        end
    end

    if indexed then
        for questID, role in pairs(indexed) do
            Add(questID, role)
        end
    end
    if started then
        for questID in pairs(started) do
            Add(questID, "starts quest")
        end
    end
    if nameMatches then
        for _, questID in ipairs(nameMatches) do
            Add(questID, "quest log objective")
        end
    end

    table.sort(info.quests, SortQuests)
    info.isOver = info.isOver and #info.quests > 0

    -- Every quest that is not behind the toon is one the player's own options keep out: beyond
    -- the range of levels chosen, or trivial where those are not wanted. A quest's item has no
    -- quest icon by its class then, in the bags as anywhere. One kept out for another reason
    -- (it can be done again, an event's, a profession not learned) is not the player's choice,
    -- and its item keeps the icon.
    if not info.isOver and #info.quests > 0 then
        local wanted = false
        for _, entry in ipairs(info.quests) do
            if not entry.over and not entry.optedOut then
                wanted = true
                break
            end
        end
        info.keptOutByOptions = not wanted
    end

    -- An item a quest handed over to be carried for that quest, the quest behind the toon: it
    -- hands over no more of them, and the item was that quest's own. A quest that can be done
    -- again and takes such an item (a scrip to exchange for the book the first quest speaks
    -- of) is the first one's helper, which the quest data does not say, and would keep the
    -- item wanted for ever. It is set aside, unless it is in the log.
    if not info.isOver then
        local handedOutAndOver = false
        for _, entry in ipairs(info.quests) do
            if entry.over and entry.role:find("provided", 1, true) then
                handedOutAndOver = true
                break
            end
        end
        if handedOutAndOver then
            local over = true
            for _, entry in ipairs(info.quests) do
                if not entry.over then
                    if entry.repeating and not entry.isActive then
                        entry.setAside = true
                    else
                        over = false
                    end
                end
            end
            info.isOver = over
            info.repeatableLeft = over
        end
    end

    local showUpcoming = not CaerdonWardrobeConfig or not CaerdonWardrobeConfig.Icon or
        CaerdonWardrobeConfig.Icon.ShowUpcomingQuestItems ~= false
    info.hasQuestValue = info.isActive or (info.isUpcoming and showUpcoming)

    return info
end

-- State for the Debug Frame export.
function CaerdonQuestItems:GetDebugState()
    local lib = provider.lib
    local api = type(_G.Questie) == "table" and _G.Questie.API
    local player = GetPlayerContext()

    local professions
    if player.skillLines then
        professions = {}
        for skillLine in pairs(player.skillLines) do
            professions[#professions + 1] = skillLine
        end
        table.sort(professions)
        professions = table.concat(professions, ", ")
    end

    local answeredCount = 0
    for _ in pairs(answered) do
        answeredCount = answeredCount + 1
    end

    return {
        -- nil professions: the client's skill lines were not recognised, so the check is off
        professions = professions,
        questLog = {
            questCount = questLog.questCount,
            objectiveCount = questLog.objectiveCount,
            incomplete = questLog.incomplete,
            awaitingData = questLog.awaitingData,
            lastScan = questLog.lastScan,
            error = questLog.error,
            -- Objectives the client had no text for: those of the last scan that kept the name
            -- they had, how many scans did, when last, and the rechecks made by the clock.
            keptNames = questLog.keptNames,
            scansThatKept = namesHistory.scansThatKept,
            lastKept = namesHistory.lastKept,
            rechecks = namesHistory.rechecks,
            rescanAttempts = questLog.rescanAttempts,
        },
        provider = {
            state = provider.state,
            contractVersion = lib and lib.contractVersion,
            readMode = lib and lib.readMode,
            itemCount = provider.itemCount,
            questCount = provider.questCount,
            buildMs = provider.buildMs,
            error = provider.error,
        },
        second = SecondSource:GetDebugState(),
        client = QuestClient:GetDebugState(),
        clientChecks = clientHistory.checks,
        clientChanges = clientHistory.changes,
        clientLastChange = clientHistory.lastChange,
        clientJudged = clientHistory.judged,
        clientCompareMs = clientHistory.ms,
        clientLongestCompareMs = clientHistory.longestMs,
        questie = {
            loaded = questieModules ~= nil,
            isReady = type(api) == "table" and api.isReady or nil,
        },
        upcomingLevelWindow = player.levelWindow >= ANY_LEVEL and "any" or player.levelWindow,
        includeTrivial = player.includeTrivial,
        trivialRange = player.trivialRange,
        -- How many quests a quest event judges again (CompareWithAnswers).
        answeredCount = answeredCount,
    }
end

----------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------

-- AllTheThings builds its data at login and says when it is through, which is listened for
-- where it was loaded before this addon. Where that call was missed (it loaded later, or was
-- through already), its data being there is looked for a few times instead. Either way what
-- was answered without it is dropped and the icons are drawn again.
local secondSourceChecks = 0
SecondSource.OnReady = function()
    CaerdonQuestItems:InvalidateCaches()
    RequestRefresh("quest data", "AllTheThings is ready")
end
local function WatchSecondSource()
    local state = SecondSource:GetDebugState()
    if state.readySeen or state.state == "missing" or state.state == "unsupported" then
        return
    end
    if state.state == "ready" then
        if state.asked > 0 or secondSourceChecks > 0 then
            SecondSource.OnReady()
        end
        return
    end
    secondSourceChecks = secondSourceChecks + 1
    if secondSourceChecks <= 30 then
        C_Timer.After(2, WatchSecondSource)
    end
end

local eventFrame = CreateFrame("Frame")

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        questLog.awaitingData = true
        questLog.dirty = true
        questLog.rescanAttempts = 0
        -- Build the index before the bags are first opened rather than on that first lookup.
        C_Timer.After(3, EnsureProvider)
        C_Timer.After(3, WatchSecondSource)
    elseif event == "QUEST_LOG_UPDATE" then
        -- Fires on every objective tick. The set of item objectives only changes with the
        -- quests themselves (the watch below), so this only matters until the log has loaded.
        if not questLog.awaitingData and not questLog.incomplete then
            return
        end

        local now = GetTime()
        if not questLog.awaitingData then
            if questLog.rescanAttempts >= MAX_INCOMPLETE_RESCANS or
                now - questLog.lastRescanRequest < RESCAN_INTERVAL then
                return
            end
            questLog.rescanAttempts = questLog.rescanAttempts + 1
        end
        questLog.awaitingData = false
        RescanForNames(true)
    end
end)

for _, event in ipairs({
    "PLAYER_ENTERING_WORLD",
    "QUEST_LOG_UPDATE",
}) do
    pcall(eventFrame.RegisterEvent, eventFrame, event)
end

-- A quest accepted, removed or turned in is compared before anything is refreshed
-- (CompareWithAnswers). The events come in runs and the completion flags settle a moment
-- after QUEST_TURNED_IN, so there is one check, when the run is over. Through the table, so
-- that the counters' wrapper is the one called. A level gained refreshes by itself
-- (CaerdonRefresh.lua), which drops what is kept here about the toon.
NS.Refresh:Watch({
    name = "quests",
    events = { "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" },
    compare = function()
        return CaerdonQuestItems:CompareWithAnswers()
    end,
    delay = REFRESH_DELAY,
})
