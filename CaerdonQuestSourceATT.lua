-- AllTheThings as a source of quest data, beside QuestieDB (CaerdonQuestItems.lua).
--
-- AllTheThings holds every quest it lists as a table in its own database, with what the quest
-- takes and what it asks of a character, for retail and for WoW Forever alike. It is read while
-- it is loaded, through the functions on its global table; nothing of it is copied. Those are
-- its own internals and no promised interface, so every read is protected and a function that
-- is gone leaves the source "unsupported" (the export's [Quest Value] says which state it is in).
--
-- Where an item's quests are found:
--   "itemIDAsCost"  a quest's cost ({"i", itemID, count}: handed in at the turn-in), and the
--                   items that start a quest (providers of type "i", qss)
--   "qItemID"       the items a quest has collected (qis), and qss again
--   a quest's objective (key "objectiveID", WoW Forever's data) is found by its item, and its
--   parent is the quest
--
-- What is asked of the toon comes from the quest's own table: lvl, races, r (faction), c
-- (classes), the repeating flags, requireSkill, sourceQuests / sqreq, altQuests, the breadcrumb's
-- nextQuests, u (2: removed from the game) and e (an event's), the last ones from the headers
-- above it where the quest has none. Fields are read raw where the quest's own are meant: a
-- missing field goes through AllTheThings' class code, and "name" asks the client to load it.

local ADDON_NAME, NS = ...

local Source = {
    readySeen = false,   -- AllTheThings said it is ready (its OnReady) while this was listening
    listening = false,
    lastState = "unchecked",
    lastError = nil,
    asked = 0,           -- items asked about since the caches were last dropped
    named = 0,           -- quests it named for them
}
NS.QuestSourceATT = Source

-- questID -> quest table, or false for a quest AllTheThings does not have.
local questGroups = {}

local UNOBTAINABLE_NEVER_IMPLEMENTED = 1
local UNOBTAINABLE_REMOVED = 2
local FACTION_BY_R = { [1] = "Horde", [2] = "Alliance" }

-- The functions read here. One of them missing means another AllTheThings than this was
-- written for.
local NEEDED = { "GetRawField", "GetRawFieldContainer", "GetRelativeValue" }

local function App()
    local app = _G.AllTheThings
    if type(app) ~= "table" then
        return nil, "missing"
    end
    for _, name in ipairs(NEEDED) do
        if type(app[name]) ~= "function" then
            return nil, "unsupported"
        end
    end
    return app
end

-- AllTheThings builds its data at login, in one go or over many frames (its own setting), and
-- tells the handlers that were registered before it was through. A handler added later is
-- never called, so the data being there is the other sign.
local function Listen(app)
    if Source.listening then
        return
    end
    Source.listening = true
    if type(app.AddEventHandler) == "function" then
        pcall(app.AddEventHandler, "OnReady", function()
            Source.readySeen = true
            wipe(questGroups)
            if Source.OnReady then
                Source.OnReady()
            end
        end)
    end
end

-- The app when its quest data can be read, or nil and why not.
local function Resolve()
    local app, reason = App()
    if not app then
        Source.lastState = reason
        return nil, reason
    end
    Listen(app)
    local ok, quests = pcall(app.GetRawFieldContainer, "questID")
    if not ok then
        Source.lastState, Source.lastError = "failed", tostring(quests)
        return nil, "failed"
    end
    if type(quests) ~= "table" or next(quests) == nil then
        Source.lastState = "not ready"
        return nil, "not ready"
    end
    Source.lastState = "ready"
    return app
end

local function IsQuestGroup(group)
    return type(group) == "table" and rawget(group, "questID") ~= nil and group.key == "questID"
end

-- A copy of a quest in one of AllTheThings' hidden lists is not the quest as it is offered:
-- its hidden triggers, what it has not sorted, and what was never in the game.
local function IsHidden(app, group)
    local Relative = app.GetRelativeValue
    return Relative(group, "_hqt") ~= nil or Relative(group, "_unsorted") ~= nil or
        Relative(group, "u") == UNOBTAINABLE_NEVER_IMPLEMENTED
end

local function ListHas(list, wanted)
    if type(list) ~= "table" then
        return false
    end
    for _, value in pairs(list) do
        if value == wanted then
            return true
        end
    end
    return false
end

-- { { kind, id, ... }, ... }
local function PairsHave(list, kind, wanted)
    if type(list) ~= "table" then
        return false
    end
    for _, entry in pairs(list) do
        if type(entry) == "table" and entry[1] == kind and entry[2] == wanted then
            return true
        end
    end
    return false
end

local function QuestGroup(app, questID)
    local known = questGroups[questID]
    if known ~= nil then
        return known or nil
    end
    local found = false
    local groups = app.GetRawField("questID", questID)
    if type(groups) == "table" then
        for _, group in ipairs(groups) do
            if IsQuestGroup(group) and rawget(group, "questID") == questID and not IsHidden(app, group) then
                found = group
                break
            end
        end
    end
    questGroups[questID] = found
    return found or nil
end

-- The quests AllTheThings names for an item: those that take it (questID -> "objective") and
-- those it starts (questID -> true). nil for either when there are none, and for both while
-- AllTheThings is not there or not ready.
function Source:GetItemQuests(itemID)
    local app = Resolve()
    if not app or type(itemID) ~= "number" then
        return nil, nil
    end

    local takes, starts
    local ok, problem = pcall(function()
        for _, field in ipairs({ "itemIDAsCost", "qItemID" }) do
            local groups = app.GetRawField(field, itemID)
            if type(groups) == "table" then
                for _, group in ipairs(groups) do
                    local quest, viaObjective = group, false
                    if type(group) == "table" and not IsQuestGroup(group) and group.key == "objectiveID" then
                        quest, viaObjective = rawget(group, "parent"), true
                    end
                    if IsQuestGroup(quest) and not IsHidden(app, quest) then
                        local questID = rawget(quest, "questID")
                        if viaObjective or PairsHave(rawget(quest, "cost"), "i", itemID) or
                            ListHas(rawget(quest, "qis"), itemID) then
                            takes = takes or {}
                            takes[questID] = "objective"
                        end
                        if not viaObjective and (PairsHave(rawget(quest, "providers"), "i", itemID) or
                                ListHas(rawget(quest, "qss"), itemID)) then
                            starts = starts or {}
                            starts[questID] = true
                        end
                    end
                end
            end
        end
    end)
    if not ok then
        Source.lastState, Source.lastError = "failed", tostring(problem)
        return nil, nil
    end

    Source.asked = Source.asked + 1
    for _ in pairs(takes or {}) do
        Source.named = Source.named + 1
    end
    return takes, starts
end

-- Whether AllTheThings has the quest.
function Source:Knows(questID)
    local app = Resolve()
    if not app then
        return false
    end
    local ok, group = pcall(QuestGroup, app, questID)
    return ok and group ~= nil
end

local function IsRepeatingGroup(group)
    return rawget(group, "repeatable") ~= nil or rawget(group, "isDaily") ~= nil or
        rawget(group, "isWeekly") ~= nil or rawget(group, "isMonthly") ~= nil or
        rawget(group, "isYearly") ~= nil or rawget(group, "isWorldQuest") ~= nil
end

-- A quest that can be done again (daily, weekly, monthly, yearly, repeatable, a world quest).
function Source:IsRepeating(questID)
    local app = Resolve()
    if not app then
        return false
    end
    local ok, group = pcall(QuestGroup, app, questID)
    return ok and group ~= nil and IsRepeatingGroup(group)
end

local function IsDone(questID)
    return type(questID) == "number" and questID > 0 and C_QuestLog.IsQuestFlaggedCompleted(questID) == true
end

local function IsDoneOrActive(questID)
    return type(questID) == "number" and questID > 0 and
        (C_QuestLog.IsQuestFlaggedCompleted(questID) == true or C_QuestLog.IsOnQuest(questID) == true)
end

-- How many quests one question follows back along a chain before it gives up.
local CHAIN_BUDGET = 200

-- Whether the quests before a quest are done, in the log, or themselves further along a chain
-- the toon is on: all of them, or as many as the quest asks for (sqreq). A quest with none
-- before it has nothing to wait for. Second value: the first quest that is not, for the reason
-- shown. One in the log counts, since the item is wanted by the time it is turned in. An entry
-- below 1 names a character, not a quest.
local Begun
local function SourcesBegun(app, group, seen, budget)
    local sourceQuests = rawget(group, "sourceQuests")
    if type(sourceQuests) ~= "table" then
        return true
    end
    local needed, have, missing = 0, 0, nil
    for _, sourceQuestID in pairs(sourceQuests) do
        if type(sourceQuestID) == "number" and sourceQuestID >= 1 then
            needed = needed + 1
            if Begun(app, sourceQuestID, seen, budget) then
                have = have + 1
            else
                missing = missing or sourceQuestID
            end
        end
    end
    local required = rawget(group, "sqreq")
    if type(required) ~= "number" or required > needed then
        required = needed
    end
    return have >= required, missing, needed > 0
end

-- A quest of a chain the toon is on: done or in the log, or one whose own quests before it
-- are. A first step that is neither is a chain not begun.
Begun = function(app, questID, seen, budget)
    if IsDoneOrActive(questID) then
        return true
    end
    if seen[questID] or budget.left <= 0 then
        return false
    end
    seen[questID] = true
    budget.left = budget.left - 1
    local group = QuestGroup(app, questID)
    if not group or type(rawget(group, "sourceQuests")) ~= "table" then
        return false
    end
    return (SourcesBegun(app, group, seen, budget))
end

-- Why a quest that is neither in the log nor done will not be picked up, or nil when it still
-- can be. Second value: the quest is behind this toon for good. Third: it can be done again.
-- Fourth and fifth: the level it asks for and the one it stops being offered at, where the
-- data has them. Sixth: the player's own options keep it out. Seventh: what the client said
-- of it where it was asked, { level } or { state }. The reason is the first one found; "for
-- good" is asked of every rule that can say so (as in CaerdonQuestItems.lua, UpcomingBlocker).
--
-- player: { level, raceID, classID, faction, skillLines, levelWindow, includeTrivial }, the
-- last two the player's settings: how many levels ahead a quest still counts as coming, and
-- whether one that is trivial for the toon does.
function Source:Blocker(questID, player)
    local app = Resolve()
    if not app then
        return "no quest data", false
    end

    local blocker, forGood, repeating, minLevel, maxLevel = nil, false, false, nil, nil
    -- Kept out by the player's own options: the range of levels, or trivial quests left out.
    local optedOut = false
    -- What the client said of the quest where it was asked: { level } (nil where it names
    -- none), or { state, waiting } with why it had no word and whether one is on its way.
    local client
    local function Block(reason, behind)
        blocker = blocker or reason
        forGood = forGood or behind == true
    end

    local ok, problem = pcall(function()
        local group = QuestGroup(app, questID)
        if not group then
            Block("no quest data")
            return
        end
        local Relative = app.GetRelativeValue

        if Relative(group, "u") == UNOBTAINABLE_REMOVED then
            Block("removed from the game", true)
        end
        if Relative(group, "e") ~= nil then
            Block("event quest")
        end

        local faction = FACTION_BY_R[Relative(group, "r")]
        if faction and player.faction and faction ~= player.faction then
            Block("other faction", true)
        end
        local races = rawget(group, "races")
        if type(races) == "table" and player.raceID and not ListHas(races, player.raceID) then
            Block("other race", true)
        end
        local classes = Relative(group, "c")
        if type(classes) == "table" and player.classID and not ListHas(classes, player.classID) then
            Block("other class", true)
        end

        if IsRepeatingGroup(group) then
            repeating = true
            Block("repeatable")
        end

        local skillLine = Relative(group, "requireSkill")
        if type(skillLine) == "number" and player.skillLines and not player.skillLines[skillLine] then
            Block("profession not learned")
        end

        -- Any of them done locks this one.
        local altQuests = rawget(group, "altQuests")
        if type(altQuests) == "table" then
            for _, otherQuestID in pairs(altQuests) do
                if IsDone(otherQuestID) then
                    Block("exclusive with quest " .. tostring(otherQuestID), true)
                end
            end
        end

        -- A breadcrumb leads to its next quests, and is gone once one of them is taken.
        if rawget(group, "isBreadcrumb") ~= nil then
            local nextQuests = rawget(group, "nextQuests")
            if type(nextQuests) == "table" then
                for _, nextQuestID in pairs(nextQuests) do
                    if IsDoneOrActive(nextQuestID) then
                        Block("chain already past it", true)
                    end
                end
            end
        end

        local lvl = rawget(group, "lvl")
        if type(lvl) == "table" then
            minLevel, maxLevel = lvl[1], lvl[2]
        elseif type(lvl) == "number" then
            minLevel = lvl
        end
        if type(maxLevel) == "number" and maxLevel > 0 and player.level > maxLevel then
            Block("outleveled", true)
        end

        -- The quest's own level and whether it is trivial are the client's to say, where it
        -- has the quest's data (CaerdonQuestClient.lua): AllTheThings has neither. Where the
        -- client has no data it is asked for it, and the quest is judged again when the
        -- answer comes. Asked only where its word can change the verdict, as for QuestieDB's
        -- quests (CaerdonQuestItems.lua, UpcomingBlocker).
        local facts
        local function ClientFacts()
            if facts == nil then
                facts = false
                if not forGood then
                    local said, why, waiting = NS.QuestClient:GetFacts(questID)
                    if said then
                        facts = said
                        client = { level = said.level > 0 and said.level or nil }
                    else
                        -- waiting: the answer is on its way. Nothing here says whether the
                        -- quest is trivial meanwhile, so the caller may put its verdict off.
                        client = { state = why, waiting = waiting == true }
                    end
                end
            end
            return facts or nil
        end

        -- The level is what bounds a quest still to come, as it is for QuestieDB's quests: one
        -- within the player's range counts, whether its chain is begun or not. Beyond the
        -- range, a later quest of a chain the toon is on still counts, whatever its level: the
        -- quests before it are followed back, and only for a quest the level would keep out.
        -- Where the data has no level the quest asks for, the quest's own level stands in for
        -- it, as for QuestieDB's quests; that one is the client's.
        local levelKnown = type(minLevel) == "number"
        local levelAsked = minLevel
        if not levelKnown then
            ClientFacts()
            levelAsked = client and client.level or nil
        end
        local beyondRange = false
        if levelAsked and levelAsked > player.level + player.levelWindow then
            local met, _, hasSources = SourcesBegun(app, group, {}, { left = CHAIN_BUDGET })
            if not (hasSources and met) then
                beyondRange = true
                optedOut = true
                if levelKnown then
                    Block(format("needs level %d", minLevel))
                else
                    Block(format("of level %d, and the level it asks for is not known", levelAsked))
                end
            end
        end
        -- A quest that has turned gray. Without the client's word nothing says so here.
        if not player.includeTrivial and not (beyondRange and levelKnown) then
            local said = ClientFacts()
            if said and said.trivial then
                optedOut = true
                Block("trivial at this level")
            end
        end
    end)
    if not ok then
        Source.lastState, Source.lastError = "failed", tostring(problem)
        return "error: " .. tostring(problem), false
    end

    return blocker, forGood, repeating, minLevel, maxLevel, optedOut, client
end

-- Drops what is kept about quests. AllTheThings changes a quest's "u" as the session goes.
function Source:InvalidateCaches()
    wipe(questGroups)
    Source.asked, Source.named = 0, 0
end

-- For the Debug Frame export.
function Source:GetDebugState()
    local app, reason = Resolve()
    local version
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        version = C_AddOns.GetAddOnMetadata("AllTheThings", "Version")
    end
    local missing
    if type(_G.AllTheThings) == "table" then
        for _, name in ipairs(NEEDED) do
            if type(_G.AllTheThings[name]) ~= "function" then
                missing = (missing and missing .. ", " or "") .. name
            end
        end
    end
    return {
        state = app and "ready" or reason,
        version = version,
        readySeen = Source.readySeen,
        listening = Source.listening,
        missingFunctions = missing,
        error = Source.lastError,
        asked = Source.asked,
        named = Source.named,
    }
end

-- AllTheThings loads before this addon (by name), so its ready call can be listened for from
-- the start. Where it is not loaded yet, the first question asks again.
do
    local app = App()
    if app then
        Listen(app)
    end
end
