-- A quest accepted, removed or turned in refreshes the icons only when it changes one.
--
-- The quest module used to refresh on each of the three events, whatever the quest. Now it
-- judges again every quest it has answered about since the last refresh and reads the log's
-- item objectives again (CaerdonQuestItems:CompareWithAnswers), and refreshes on a difference.
-- Here: quests that take nothing, quests that decide about another quest without taking an
-- item themselves, objectives named in the log only, answers that come late.
--
-- The game and the quest database are hand-made, so this checks the compare's logic. When a
-- client sends these events and when its flags follow, only a client shows.
--
-- Real code: the whole addon, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 31 }

    -- An off-hand whose look is learned: without a quest it has a status of its own, which
    -- the quest icon replaces.
    local function Holdable(name, number)
        return { name = name, quality = 2, level = 31, minLevel = 26, type = "Armor", subType = "Miscellaneous",
            stack = 1, equipLoc = "INVTYPE_HOLDABLE", price = 0, classID = 4, subClassID = 0, bindType = 4,
            tooltip = { { text = "Quest Item", type = 20, bonding = 0 } },
            appearance = { appearanceID = 5200 + number, sourceID = 7200 + number, collected = true } }
    end

    local EYE, ORB, LANTERN, BOLT, KEY, TUSK, LETTER, PELT = 950001, 950002, 950003, 950004, 950005, 950006, 950007, 950008
    local ITEMS = {
        [EYE] = Holdable("Cursed Eye", 1),   -- handed over by a chain of two quests
        [ORB] = Holdable("Quiet Orb", 2),    -- no quest names it
        [BOLT] = Holdable("Silk Bolt", 4),   -- taken by a quest that another quest excludes
        [KEY] = Holdable("Old Key", 5),      -- taken by a quest with a later quest in its chain
        [TUSK] = Holdable("Boar Tusk", 6),   -- named by objectives in the log, not by the database
        [LETTER] = Holdable("Torn Letter", 7), -- starts a quest
        [PELT] = Holdable("Wolf Pelt", 8),   -- named by an objective whose text comes late
    }
    -- Worn in the off-hand and better than all of them, so none is an upgrade.
    ITEMS[LANTERN] = Holdable("Worn Lantern", 3)
    ITEMS[LANTERN].level, ITEMS[LANTERN].bindType, ITEMS[LANTERN].tooltip = 45, 1, {}
    local OFFHAND = 17

    local function Common(fields)
        fields.requiredLevel, fields.questLevel = 22, 30
        fields.startedBy = fields.startedBy or { { 5 } }
        return fields
    end
    local QUESTS = {
        [8001] = Common({ name = "The Eye", sourceItemId = EYE, nextQuestInChain = 8002 }),
        [8002] = Common({ name = "Cleansing the Eye", sourceItemId = EYE }),
        [8003] = Common({ name = "Silk for the Tailor", objectives = { [3] = { { BOLT } } }, exclusiveTo = { 8004 } }),
        [8004] = Common({ name = "Linen for the Tailor" }),
        [8005] = Common({ name = "The Locked Chest", objectives = { [3] = { { KEY } } }, nextQuestInChain = 8006,
            exclusiveTo = { 8012 } }),
        [8006] = Common({ name = "What Was Inside" }),
        [8008] = Common({ name = "A Letter Found", startedBy = { nil, nil, { LETTER } } }),
        [8010] = Common({ name = "Ten Boars" }),
    }

    local onQuest, completed, owned = {}, {}, { [LETTER] = 1 }
    local log = {} -- the quest log, in its order: { questID =, objectives = }

    local function Accept(questID, objectives)
        onQuest[questID] = true
        log[#log + 1] = { questID = questID, objectives = objectives or {} }
    end
    local function Leave(questID)
        onQuest[questID] = nil
        for index = #log, 1, -1 do
            if log[index].questID == questID then
                table.remove(log, index)
            end
        end
    end

    local game = H.StockGame(TOON, ITEMS)
    game:Set("GetInventoryItemID", function(_, slot) return slot == OFFHAND and LANTERN or nil end)
    game:Set("GetInventoryItemLink", function(_, slot) return slot == OFFHAND and game.Link(LANTERN) or nil end)
    local function Worn(location)
        return type(location) == "table" and location.IsEquipmentSlot and location:IsEquipmentSlot() and
            location:GetEquipmentSlot() == OFFHAND
    end
    game:Set("C_Item.DoesItemExist", function(location) return Worn(location) == true end)
    game:Set("C_Item.GetItemLink", function(location) return Worn(location) and game.Link(LANTERN) or nil end)
    game:Set("C_Item.GetItemID", function(location) return Worn(location) and LANTERN or nil end)
    game:Set("C_Item.GetCurrentItemLevel", function(location) return Worn(location) and ITEMS[LANTERN].level or nil end)
    game:Set("C_Item.GetItemCount", function(itemID) return type(itemID) == "number" and owned[itemID] or 0 end)
    game:Set("GetInstanceInfo", function() return "Wetlands", "none" end)
    game:Set("C_TooltipInfo.GetInventoryItem", function(_, slot)
        return slot == OFFHAND and game.client.env.C_TooltipInfo.GetHyperlink(game.Link(LANTERN)) or nil
    end)
    game:Set("LibQuestieDB.RequireContract", function() return true end)
    game:Set("LibQuestieDB.Quest.GetAllIds", function() return { 8001, 8002, 8003, 8004, 8005, 8006, 8008, 8010 } end)
    game:Set("LibQuestieDB.Quest.Get", function(questID, field) return QUESTS[questID] and QUESTS[questID][field] end)
    game:Set("LibQuestieDB.Enum", { classKeys = { HUNTER = 4 }, raceMaskById = { [3] = 4 } })
    game:Set("C_QuestLog.IsOnQuest", function(questID) return onQuest[questID] == true end)
    game:Set("C_QuestLog.IsQuestFlaggedCompleted", function(questID) return completed[questID] == true end)
    game:Set("C_QuestLog.GetTitleForQuestID", function() return nil end)
    game:Set("C_QuestLog.GetNumQuestLogEntries", function() return #log end)
    game:Set("C_QuestLog.GetInfo", function(index)
        return log[index] and { questID = log[index].questID, isHeader = false } or nil
    end)
    game:Set("C_QuestLog.GetQuestObjectives", function(questID)
        for _, entry in ipairs(log) do
            if entry.questID == questID then
                return entry.objectives
            end
        end
    end)

    local client = H.Client.New({ flavor = "forever", provider = game })
    game.client = client
    H.LoadBlizzardBase(client)
    local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
    client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
    rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
    client:Fire("ADDON_LOADED", "CaerdonWardrobe")
    client:Fire("VARIABLES_LOADED")
    client:Fire("PLAYER_LOGIN")
    client:Fire("PLAYER_ENTERING_WORLD", true, false)
    client:Tick(40)
    local env = client.env
    Equal(#client.errors, 0, "start: no error reached the error handler")

    local function Report()
        return env.CaerdonCounters:GetReport().refreshes
    end
    local function Total()
        return Report().total
    end
    local function By(name)
        return Report().by[name] or 0
    end
    local function Last()
        local recent = Report().recent
        local entry = recent[#recent]
        return entry and entry.trigger, entry and entry.detail
    end
    local function Watch()
        for _, watch in ipairs(Report().watched) do
            if watch.name == "quests" then
                return watch
            end
        end
    end
    local function Answered()
        return env.CaerdonQuestItems:GetDebugState().answeredCount
    end

    -- The index is built after the first question, over the next frames, and is a change.
    env.CaerdonQuestItems:GetItemQuestInfo(EYE, "Cursed Eye")
    client:Tick(20)
    Equal(By("quest data"), 1, "start: the index of the quest database refreshes once when it is built")
    Equal(select(2, Last()), "the index is built", "start: and says so")
    client:Fire("QUEST_LOG_UPDATE")
    client:Tick(20)
    Equal(By("quest log"), 0, "start: the log's first update with no item objective in it refreshes nothing")
    Check(Watch() ~= nil, "start: the quest events are a watch of the refresh watcher")

    local items = {}
    for itemID in pairs(ITEMS) do
        if itemID ~= LANTERN then
            local item = env.CaerdonItem:CreateFromItemID(itemID)
            local loaded = false
            item:ContinueOnItemLoad(function() loaded = true end)
            client:TickUntil(function() return loaded end, 10)
            items[itemID] = item
        end
    end

    -- Every item asked for its status, as a redraw does. Returns which carry the quest icon.
    local function Draw()
        local quest = {}
        for itemID, item in pairs(items) do
            local ready, status
            client:TickUntil(function()
                ready, status = item:GetCaerdonStatus()
                return ready
            end, 10)
            Check(ready, "draw: the status of " .. ITEMS[itemID].name .. " is ready")
            quest[itemID] = status == "quest"
        end
        return quest
    end

    -- An event, the half second the watch waits, and the refresh's own tenth.
    local function After(event, ...)
        client:Fire(event, ...)
        client:Tick(20)
    end

    local shown = Draw()
    Check(shown[EYE] and shown[BOLT] and shown[KEY] and shown[LETTER], "first: the four items a quest still to come takes have the quest icon")
    Check(not shown[ORB] and not shown[TUSK] and not shown[PELT], "first: the three no quest names do not")
    Check(Answered() >= 5, "first: the quests asked about are held as answered (" .. tostring(Answered()) .. ")")

    -- A quest that takes nothing and decides about no other quest.
    local total, generation = Total(), env.CaerdonWardrobe.refreshGeneration
    Accept(8010)
    After("QUEST_ACCEPTED", 8010)
    Equal(Total(), total, "nothing: a quest that takes no item is accepted and nothing is refreshed")
    Equal(env.CaerdonWardrobe.refreshGeneration, generation, "nothing: the verdicts are the ones from before")
    Check(Watch().events == 1 and Watch().checks == 1 and Watch().changes == 0, "nothing: the watch read once and found no change")
    Leave(8010)
    completed[8010] = true
    client:Fire("QUEST_TURNED_IN", 8010)
    client:Fire("QUEST_REMOVED", 8010)
    client:Tick(20)
    Equal(Total(), total, "nothing: nor when it is turned in")
    Check(Watch().events == 3 and Watch().checks == 2, "nothing: two events of one run are one check")
    shown = Draw()
    Check(shown[EYE] and shown[BOLT] and shown[KEY] and shown[LETTER] and not shown[ORB], "nothing: the icons are as they were")

    -- A quest that takes an item.
    Accept(8001)
    After("QUEST_ACCEPTED", 8001)
    Equal(By("quests"), 1, "taken: the quest that hands the eye over is accepted and the icons are refreshed")
    Equal(select(2, Last()), "quest 8001: upcoming -> in the log", "taken: the refresh says which quest and how")
    Equal(Answered(), 0, "taken: a refresh forgets the answers")
    shown = Draw()
    Check(shown[EYE], "taken: the eye keeps the quest icon")

    -- A quest with no item of its own that decides about one that has.
    Accept(8004)
    After("QUEST_ACCEPTED", 8004)
    Equal(By("quests"), 2, "excluded: a quest that excludes the bolt's quest is accepted and the icons are refreshed")
    Equal(select(2, Last()), "quest 8003: upcoming -> not wanted", "excluded: named by the quest that changed, not the one accepted")
    shown = Draw()
    Check(not shown[BOLT] and shown[KEY], "excluded: the bolt loses the quest icon, the key keeps it")

    Accept(8006)
    After("QUEST_ACCEPTED", 8006)
    Equal(By("quests"), 3, "chain: a later quest of the key's chain is accepted and the icons are refreshed")
    Equal(select(2, Last()), "quest 8005: upcoming -> not wanted", "chain: the quest before it is behind the toon")
    shown = Draw()
    Check(not shown[KEY], "chain: the key loses the quest icon")

    -- An item only the log's objectives name.
    Accept(8007, { { type = "item", text = "Boar Tusk: 0/4" }, { type = "monster", text = "Boars slain: 0/10" } })
    After("QUEST_ACCEPTED", 8007)
    Equal(By("quests"), 4, "objective: a quest whose objective names an item is accepted and the icons are refreshed")
    Equal(select(2, Last()), "objective Boar Tusk: new, 8007", "objective: the refresh names the item and the quest")
    shown = Draw()
    Check(shown[TUSK], "objective: the tusk gets the quest icon")

    -- A second quest for the same item, then the log in another order.
    Accept(8011, { { type = "item", text = "Boar Tusk: 0/2" } })
    After("QUEST_ACCEPTED", 8011)
    Equal(By("quests"), 5, "objective: a second quest for the tusk is a change")
    Equal(select(2, Last()), "objective Boar Tusk: 8007 -> 8007,8011", "objective: with both quests named")
    Draw()
    total = Total()
    log[#log], log[#log - 1] = log[#log - 1], log[#log]
    Accept(8012)
    After("QUEST_ACCEPTED", 8012)
    Equal(Total(), total, "objective: the same quests in another order of the log are no change")
    -- That quest also excludes the key's, which was not wanted already: no change for an icon,
    -- and the verdict that is kept is the new one, with its reason.
    local keyInfo = env.CaerdonQuestItems:GetItemQuestInfo(KEY, "Old Key")
    Equal(keyInfo and keyInfo.quests[1] and keyInfo.quests[1].reason, "exclusive with quest 8012",
        "reason: a verdict that stays not wanted for another reason is kept with the new reason")

    -- An objective whose text is not there yet when the quest is accepted.
    local late = { { type = "item", text = "" } }
    Accept(8009, late)
    After("QUEST_ACCEPTED", 8009)
    Equal(Total(), total, "late: an objective without its text changes nothing yet")
    client:Tick(40)
    late[1].text = "Wolf Pelt: 0/2"
    After("QUEST_LOG_UPDATE")
    Equal(By("quest log"), 1, "late: when the text has come the log's update refreshes")
    Equal(select(2, Last()), "objective Wolf Pelt: new, 8009", "late: and names the item")
    shown = Draw()
    Check(shown[PELT], "late: the pelt gets the quest icon")

    -- The event before the client's answers have changed.
    total = Total()
    client:Fire("QUEST_TURNED_IN", 8001)
    client:Tick(4)
    Equal(Total(), total, "settling: nothing is refreshed while the run of events lasts")
    Leave(8001)
    completed[8001] = true
    client:Fire("QUEST_REMOVED", 8001)
    client:Tick(20)
    Equal(By("quests"), 6, "settling: the check after the run finds the quest turned in")
    Equal(select(2, Last()), "quest 8001: in the log -> not wanted", "settling: and says so")
    shown = Draw()
    Check(shown[EYE], "settling: the eye keeps the icon for the next quest of its chain")

    -- An answer first given while the events are still coming.
    env.CaerdonWardrobe:RefreshItems("scenario")
    client:Tick(4)
    Equal(Answered(), 0, "window: nothing is answered after a refresh nobody drew for")
    total = Total()
    client:Fire("QUEST_ACCEPTED", 8002)
    shown = Draw()
    Check(shown[EYE], "window: the eye is drawn from the answers of before the quest is in the log")
    Accept(8002)
    client:Tick(20)
    Equal(Total(), total + 1, "window: what was answered inside the run is compared when it is over")
    Equal(select(2, Last()), "quest 8002: upcoming -> in the log", "window: and the difference found")
    Draw()

    -- An answer that is not kept, because it depends on the bags: the quest a carried item starts.
    total = Total()
    Accept(8013)
    After("QUEST_ACCEPTED", 8013)
    Equal(Total(), total, "starter: an answer that is not kept is no change by itself")
    Accept(8008)
    After("QUEST_ACCEPTED", 8008)
    Equal(Total(), total + 1, "starter: the quest the letter starts is accepted and the icons are refreshed")
    Equal(select(2, Last()), "quest 8008: upcoming -> in the log", "starter: under that quest")

    -- Nothing drawn since the refresh: no icon was made from the old answers.
    total = Total()
    Equal(Answered(), 0, "undrawn: nothing is answered")
    Leave(8002)
    completed[8002] = true
    client:Fire("QUEST_TURNED_IN", 8002)
    client:Fire("QUEST_REMOVED", 8002)
    client:Tick(20)
    Equal(Total(), total, "undrawn: a quest turned in with nothing drawn since the last refresh refreshes nothing")
    shown = Draw()
    Check(not shown[EYE], "undrawn: and the next draw is made from the client as it is: no quest wants the eye")

    -- A level gained is a refresh of its own, with its own name.
    local quests = By("quests")
    TOON.level = 32
    After("PLAYER_LEVEL_UP", 32)
    Equal(By("level"), 1, "level: a level gained refreshes under its own name")
    Equal(By("quests"), quests, "level: and not under the quest module's")

    Equal(#client.errors, 0, "end: no error reached the error handler")
    for _, message in ipairs(client.errors) do
        Check(false, "error: " .. message)
    end
end
