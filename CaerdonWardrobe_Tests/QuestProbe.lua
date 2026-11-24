-- /cwtest quest <quest ID> [item ID ...]: what the client, AllTheThings and the addon each say
-- about one quest, and about the items it is said to take.
--
-- For an item that has no quest icon reason the addon can name ("no quest is known for it")
-- although a quest takes it: the record shows which of the three lacks the tie. The client is
-- asked for the quest's data first, as the addon asks it (C_QuestLog.RequestLoadQuestByID),
-- and what it said before and after is kept: its level for the quest, whether it calls it
-- trivial, and its objectives, whose text names an item only while the client has that
-- item's data, so the items are loaded before the objectives are read.
--
-- Stored under db.questProbes[toon][questID]; tools/test-results.lua prints it with the
-- probes.

local _, T = ...

local ANSWER_SECONDS = 5

-- What the client says of the quest at this moment.
local function ClientWord(questID)
    local word = {
        haveData = HaveQuestData(questID) == true,
        level = C_QuestLog.GetQuestDifficultyLevel(questID),
        trivial = C_QuestLog.IsQuestTrivial(questID) == true,
        completed = C_QuestLog.IsQuestFlaggedCompleted(questID) == true,
        inLog = C_QuestLog.IsOnQuest(questID) == true,
        title = C_QuestLog.GetTitleForQuestID(questID),
    }
    return word
end

local function Objectives(questID)
    local list = {}
    local objectives = C_QuestLog.GetQuestObjectives(questID)
    if type(objectives) ~= "table" then
        return list, false
    end
    for index, objective in ipairs(objectives) do
        list[index] = {
            type = tostring(objective.type),
            text = objective.text ~= nil and tostring(objective.text) or nil,
            required = objective.numRequired,
            finished = objective.finished == true,
        }
    end
    return list, true
end

-- A plain copy of one of AllTheThings' raw lists: numbers, or { kind, id, count } entries.
local function PlainList(list)
    if type(list) ~= "table" then
        return nil
    end
    local parts = {}
    for _, entry in pairs(list) do
        if type(entry) == "table" then
            local inner = {}
            for position = 1, #entry do
                inner[position] = tostring(entry[position])
            end
            parts[#parts + 1] = "{" .. table.concat(inner, ",") .. "}"
        else
            parts[#parts + 1] = tostring(entry)
        end
    end
    table.sort(parts)
    return table.concat(parts, " ")
end

-- "itemID 36758 < headerID -63 < mapID 116": a group of AllTheThings and what it lies under.
local function Describe(group)
    local parts, depth = {}, 0
    while type(group) == "table" and depth < 6 do
        local key = rawget(group, "key")
        if type(key) ~= "string" then
            -- Its class code names the key; a group without one is the root.
            key = type(group.key) == "string" and group.key or nil
        end
        if not key then
            break
        end
        parts[#parts + 1] = key .. " " .. tostring(rawget(group, key))
        group = rawget(group, "parent")
        depth = depth + 1
    end
    return table.concat(parts, " < ")
end

-- What AllTheThings holds for the quest and for each item, read as the addon reads it
-- (CaerdonQuestSourceATT.lua). Nothing here waits, so a protected call is safe.
local function AllTheThingsWord(questID, itemIDs)
    local app = _G.AllTheThings
    if type(app) ~= "table" or type(app.GetRawField) ~= "function" then
        return { state = "not loaded, or without GetRawField" }
    end
    local word = { state = "read", quest = {}, items = {} }
    local ok, problem = pcall(function()
        local groups = app.GetRawField("questID", questID)
        for _, group in ipairs(type(groups) == "table" and groups or {}) do
            word.quest[#word.quest + 1] = {
                where = Describe(group),
                qis = PlainList(rawget(group, "qis")),
                cost = PlainList(rawget(group, "cost")),
                providers = PlainList(rawget(group, "providers")),
                qss = PlainList(rawget(group, "qss")),
                sourceQuests = PlainList(rawget(group, "sourceQuests")),
                lvl = type(rawget(group, "lvl")) == "table" and PlainList(rawget(group, "lvl")) or rawget(group, "lvl"),
            }
        end
        for _, itemID in ipairs(itemIDs) do
            local found = {}
            for _, field in ipairs({ "itemID", "itemIDAsCost", "qItemID" }) do
                local listed = app.GetRawField(field, itemID)
                for _, group in ipairs(type(listed) == "table" and listed or {}) do
                    found[#found + 1] = field .. ": " .. Describe(group)
                end
            end
            word.items[tostring(itemID)] = found
        end
    end)
    if not ok then
        word.state = "error: " .. tostring(problem)
    end
    return word
end

function T.ProbeQuest(questID, itemIDs)
    T.Start("quest probe", function()
        local toon = T.GetToon()
        T.db.questProbes = T.db.questProbes or {}
        local store = T.db.questProbes[toon.key] or {}
        T.db.questProbes[toon.key] = store

        local probe = { at = GetServerTime(), sig = toon.signature, build = T.GetClient().build, level = toon.level }
        probe.before = ClientWord(questID)

        -- The items first: an objective's text names its item only while the client has it.
        probe.items = {}
        for _, itemID in ipairs(itemIDs) do
            local entry = { id = itemID }
            local item, why = T.LoadItem(itemID, 5)
            if item then
                entry.name = item:GetItemName()
            else
                entry.note = why
            end
            probe.items[#probe.items + 1] = entry
        end

        -- The quest's data, asked for as the addon asks for it.
        local startedAt = GetTime()
        if not probe.before.haveData then
            C_QuestLog.RequestLoadQuestByID(questID)
            probe.asked = true
            probe.came = T.WaitUntil(function() return HaveQuestData(questID) == true end, ANSWER_SECONDS)
            probe.waited = GetTime() - startedAt
        end
        probe.after = ClientWord(questID)
        probe.objectives, probe.hasObjectives = Objectives(questID)

        -- Whether the client's objectives name each item, and which quests the addon names
        -- for it: asked now that the client has answered, so that the addon's reason is the
        -- one it draws from and not the one it holds while it waits for the client.
        for _, entry in ipairs(probe.items) do
            entry.clientNamesIt = false
            if entry.name then
                local info = CaerdonQuestItems:GetItemQuestInfo(entry.id, entry.name)
                local named = {}
                entry.addonNamesThisQuest = false
                for _, quest in ipairs(info and info.quests or {}) do
                    named[#named + 1] = tostring(quest.questID) .. " (" .. tostring(quest.reason) .. ")"
                    if quest.questID == questID then
                        entry.addonNamesThisQuest = true
                    end
                end
                entry.addonQuests = #named > 0 and table.concat(named, "; ") or "none"
                for _, objective in ipairs(probe.objectives) do
                    if objective.text and objective.text:find(entry.name, 1, true) then
                        entry.clientNamesIt = true
                        entry.clientObjectiveType = objective.type
                    end
                end
            end
        end

        probe.allTheThings = AllTheThingsWord(questID, itemIDs)
        store[questID] = probe

        local after = probe.after
        T.Print("quest %d %s: the client %s; level %s, %s, %s, %d objectives", questID, tostring(after.title or "?"),
            after.haveData and "has its data" or "has no data of it", tostring(after.level),
            after.trivial and "trivial" or "not trivial", after.completed and "done" or "not done", #probe.objectives)
        for index, objective in ipairs(probe.objectives) do
            T.Print("  objective %d (%s): %s", index, objective.type, tostring(objective.text))
        end
        for _, entry in ipairs(probe.items) do
            T.Print("  item %d %s: the client's objectives %s it; the addon names for it: %s", entry.id,
                tostring(entry.name or entry.note), entry.clientNamesIt and "name" or "do not name",
                tostring(entry.addonQuests))
        end
        T.Print("stored; /reload, then luajit tools/test-results.lua probes")
    end)
end
