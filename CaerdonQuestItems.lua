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
--
-- CaerdonItemMixin:GetQuestItemInfo() is the entry point for callers; the Debug Frame export
-- prints the full verdict list ("[Quest Value]").

local ADDON_NAME, NS = ...

CaerdonQuestItems = {}

-- The QuestieDB contract this was written for (the first with WoW Forever data).
local QUESTIEDB_CONTRACT = 2

-- A quest that is not in the log counts as "upcoming" when the toon can take it within this
-- many levels and it is not trivial (gray) for the toon yet.
local UPCOMING_LEVEL_WINDOW = 5
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
}

local provider = {
    state = "unchecked",  -- unchecked | missing | unsupported | building | ready | failed
    lib = nil,
    index = nil,          -- itemID -> { [questID] = role }
    starters = nil,       -- itemID -> { [questID] = true } for items that start a quest
    itemCount = 0,
    questCount = 0,
    buildMs = 0,
    error = nil,
}

-- questID -> verdict; dropped whenever the main frame refreshes.
local verdicts = {}
local playerContext
local questieModules
local questieReadyHooked = false
local refreshTimer

local function HasBit(mask, flag)
    -- Race masks go past 2^32 on WoW Forever, so no bit library here.
    return mask % (flag * 2) >= flag
end

local function RequestRefresh()
    if refreshTimer then
        return
    end

    refreshTimer = C_Timer.NewTimer(REFRESH_DELAY, function()
        refreshTimer = nil
        -- RefreshItems calls InvalidateCaches below, so anything evaluated while this timer
        -- was pending (a bag update racing the quest completion flag) is dropped again.
        if CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
            CaerdonWardrobe:RefreshItems()
        end
    end)
end

function CaerdonQuestItems:InvalidateCaches()
    wipe(verdicts)
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

    local numEntries = C_QuestLog.GetNumQuestLogEntries() or 0
    for index = 1, numEntries do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader and info.questID and info.questID > 0 then
            questCount = questCount + 1

            local objectives = C_QuestLog.GetQuestObjectives(info.questID)
            if objectives then
                for _, objective in ipairs(objectives) do
                    if objective.type == "item" then
                        local name = ObjectiveItemName(objective.text)
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

    return itemNames, incomplete, questCount, objectiveCount
end

local function EnsureQuestLog()
    if not questLog.dirty then
        return
    end
    questLog.dirty = false

    local ok, itemNames, incomplete, questCount, objectiveCount = pcall(ScanQuestLog)
    if ok then
        questLog.itemNames = itemNames
        questLog.incomplete = incomplete
        questLog.questCount = questCount
        questLog.objectiveCount = objectiveCount
        questLog.error = nil
    else
        questLog.error = tostring(itemNames)
        questLog.itemNames = {}
        questLog.incomplete = false
        questLog.questCount = 0
        questLog.objectiveCount = 0
    end
    questLog.lastScan = GetTime()
end

local function SameItemNames(left, right)
    for name, quests in pairs(left) do
        local other = right[name]
        if not other or table.concat(quests, ",") ~= table.concat(other, ",") then
            return false
        end
    end
    for name in pairs(right) do
        if not left[name] then
            return false
        end
    end
    return true
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
                RequestRefresh()
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

-- Runs inside the build coroutine. Reads three fields for every quest.
local function BuildIndex(lib, yieldIfNeeded)
    local Get = lib.Quest.Get
    local ids = lib.Quest.GetAllIds()
    local index, starters = {}, {}
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
        if not quests[questID] then
            quests[questID] = role
        end
    end

    for position = 1, #ids do
        local questID = ids[position]

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

    return index, starters, itemCount, #ids
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
        local ok, index, starters, itemCount, questCount = coroutine.resume(builder)
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
        provider.itemCount = itemCount
        provider.questCount = questCount
        provider.buildMs = workMs
        provider.state = "ready"

        CaerdonQuestItems:InvalidateCaches()
        RequestRefresh()
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

    playerContext = {
        level = UnitLevel("player") or 0,
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

local GetItemCount = C_Item and C_Item.GetItemCount or GetItemCount

-- Why a quest that is neither in the log nor completed will not be picked up, or nil when it
-- still can be. Second value: the answer depends on bag contents and must not be cached.
local function UpcomingBlocker(questID, verdict, Get)
    local hiddenReason = QuestieHiddenReason(questID)
    if hiddenReason then
        return hiddenReason
    end

    if EVENT_QUEST_SORTS[Get(questID, "zoneOrSort") or 0] then
        return "event quest"
    end

    local player = GetPlayerContext()

    local raceMask = Get(questID, "requiredRaces") or 0
    if raceMask ~= 0 and player.raceFlag then
        local factionOfMask = CLASSIC_FACTION_MASK[raceMask]
        if factionOfMask then
            if factionOfMask ~= player.faction then
                return "other faction"
            end
        elseif not HasBit(raceMask, player.raceFlag) then
            return "other race"
        end
    end

    local classMask = Get(questID, "requiredClasses") or 0
    if classMask ~= 0 and player.classFlag and not HasBit(classMask, player.classFlag) then
        return "other class"
    end

    local specialFlags = Get(questID, "specialFlags") or 0
    if HasBit(specialFlags, SPECIAL_FLAG_REPEATABLE) then
        return "repeatable"
    end
    local questFlags = Get(questID, "questFlags") or 0
    for _, flag in ipairs(REPEATING_QUEST_FLAGS) do
        if HasBit(questFlags, flag) then
            return "repeatable"
        end
    end

    local requiredSkill = Get(questID, "requiredSkill")
    local skillLine = type(requiredSkill) == "table" and requiredSkill[1]
    if skillLine and PROFESSION_SKILL_LINES[skillLine] and player.skillLines and not player.skillLines[skillLine] then
        return "profession not learned"
    end

    local exclusiveTo = Get(questID, "exclusiveTo")
    if type(exclusiveTo) == "table" then
        for _, otherQuestID in pairs(exclusiveTo) do
            if IsQuestDoneOrActive(otherQuestID) then
                return "exclusive with quest " .. tostring(otherQuestID)
            end
        end
    end

    -- A later quest of the chain being active or done means this one is behind the toon.
    local nextQuest = Get(questID, "nextQuestInChain")
    if IsQuestDoneOrActive(nextQuest) then
        return "chain already past it"
    end

    -- Only offered while its parent is in progress
    if IsQuestDone(Get(questID, "parentQuest")) then
        return "parent quest completed"
    end

    if IsQuestDone(Get(questID, "availableUntilCompleted")) then
        return "no longer offered"
    end

    local requiredLevel = Get(questID, "requiredLevel") or 0
    local questLevel = Get(questID, "questLevel") or 0
    verdict.requiredLevel = requiredLevel
    verdict.questLevel = questLevel

    local maxLevel = Get(questID, "requiredMaxLevel") or 0
    if maxLevel > 0 and player.level > maxLevel then
        return "outleveled"
    end
    if requiredLevel > player.level + UPCOMING_LEVEL_WINDOW then
        return format("needs level %d", requiredLevel)
    end
    -- Zero and negative quest levels scale with the toon
    if questLevel > 0 and questLevel < player.level - player.trivialRange then
        return "trivial at this level"
    end

    -- A quest only an item can start is not upcoming unless that item is already owned.
    local startedBy = Get(questID, "startedBy")
    if type(startedBy) == "table" then
        local hasGiver = (type(startedBy[1]) == "table" and next(startedBy[1]) ~= nil) or
            (type(startedBy[2]) == "table" and next(startedBy[2]) ~= nil)
        local starterItems = startedBy[3]
        if not hasGiver and type(starterItems) == "table" and next(starterItems) ~= nil then
            for _, starterItemID in pairs(starterItems) do
                if GetItemCount and (GetItemCount(starterItemID, true) or 0) > 0 then
                    return nil, true
                end
            end
            return "starter item not owned", true
        end
    end

    return nil
end

local function EvaluateQuest(questID)
    local verdict = verdicts[questID]
    if verdict then
        return verdict
    end

    verdict = { questID = questID, eligible = false, isActive = false }

    local Get = provider.lib and provider.lib.Quest.Get
    local volatile = false

    local ok, failure = pcall(function()
        verdict.name = (Get and Get(questID, "name")) or C_QuestLog.GetTitleForQuestID(questID)

        if C_QuestLog.IsOnQuest(questID) then
            verdict.isActive = true
            verdict.eligible = true
            verdict.reason = "in quest log"
        elseif C_QuestLog.IsQuestFlaggedCompleted(questID) then
            verdict.reason = "completed"
        elseif not Get then
            verdict.reason = "no quest data"
        else
            local blocker, dependsOnBags = UpcomingBlocker(questID, verdict, Get)
            volatile = dependsOnBags or false
            verdict.eligible = blocker == nil
            verdict.reason = blocker or "upcoming"
        end
    end)

    if not ok then
        verdict.eligible = false
        verdict.isActive = false
        verdict.reason = "error: " .. tostring(failure)
    end

    if not volatile then
        verdicts[questID] = verdict
    end
    return verdict
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

-- Returns nil when no known quest takes the item. Otherwise:
--   hasQuestValue  an unfinished quest that applies to this toon takes the item (honours the
--                  "upcoming quests" setting)
--   isActive       a quest in the log takes it
--   isUpcoming     a quest the toon has not accepted yet takes it
--   quests         every candidate quest with its verdict, the rejected ones included:
--                  { questID, name, role, isActive, eligible, reason, requiredLevel, questLevel }
function CaerdonQuestItems:GetItemQuestInfo(itemID, itemName)
    EnsureQuestLog()
    EnsureProvider()

    local nameMatches = itemName and questLog.itemNames[itemName]
    local indexed = itemID and provider.index and provider.index[itemID]
    local started = itemID and provider.starters and provider.starters[itemID]
    if not nameMatches and not indexed and not started then
        return nil
    end

    local info = { hasQuestValue = false, isActive = false, isUpcoming = false, quests = {} }
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
            reason = verdict.reason,
            requiredLevel = verdict.requiredLevel,
            questLevel = verdict.questLevel,
        }
        byQuest[questID] = entry
        info.quests[#info.quests + 1] = entry

        if verdict.isActive then
            info.isActive = true
        elseif verdict.eligible then
            info.isUpcoming = true
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
        questie = {
            loaded = questieModules ~= nil,
            isReady = type(api) == "table" and api.isReady or nil,
        },
        upcomingLevelWindow = UPCOMING_LEVEL_WINDOW,
        trivialRange = player.trivialRange,
    }
end

----------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        questLog.awaitingData = true
        questLog.dirty = true
        -- Build the index before the bags are first opened rather than on that first lookup.
        C_Timer.After(3, EnsureProvider)
    elseif event == "QUEST_LOG_UPDATE" then
        -- Fires on every objective tick. The set of item objectives only changes with the
        -- quests themselves (handled below), so this only matters until the log has loaded.
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
        questLog.lastRescanRequest = now

        local previous = questLog.itemNames
        questLog.dirty = true
        EnsureQuestLog()
        if not SameItemNames(previous, questLog.itemNames) then
            RequestRefresh()
        end
    else
        -- QUEST_ACCEPTED, QUEST_REMOVED, QUEST_TURNED_IN, PLAYER_LEVEL_UP
        questLog.rescanAttempts = 0
        CaerdonQuestItems:InvalidateCaches()
        RequestRefresh()
    end
end)

for _, event in ipairs({
    "PLAYER_ENTERING_WORLD",
    "QUEST_LOG_UPDATE",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "QUEST_TURNED_IN",
    "PLAYER_LEVEL_UP",
}) do
    pcall(eventFrame.RegisterEvent, eventFrame, event)
end
