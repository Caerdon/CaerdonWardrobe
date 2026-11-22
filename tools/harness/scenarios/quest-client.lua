-- The client's own word on a quest that is not in the log (CaerdonQuestClient.lua): its level
-- and whether it is trivial come before the quest data's, the client is asked to load the
-- quests it has no data of, and a quest is judged again when its answer comes.
--
-- What a Forever client showed, typed in game (1.60.1.71037): without a request it has no
-- data of a quest that is not in the log (HaveQuestData false, GetQuestDifficultyLevel 0,
-- IsQuestTrivial false), and after C_QuestLog.RequestLoadQuestByID it has (the level 55 for a
-- quest whose quest data names no level it asks for).
--
-- The game, the quest database and AllTheThings are hand-made, and so is the client's way of
-- answering a request: after a moment, at once from inside the call, with a refusal, or never.
-- Which of those a client does, and how fast, is not known from this.
--
-- Real code: the addon's item side and features/DebugFrame.lua, Blizzard's base files from
-- the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local QUEST_LINE = { text = "Quest Item", type = 20, bonding = 0 }
    local function QuestItem(name)
        return { name = name, quality = 1, level = 1, minLevel = 0, type = "Quest", subType = "Quest", stack = 1,
            equipLoc = "INVTYPE_NON_EQUIP_IGNORE", price = 0, classID = 12, subClassID = 0, bindType = 4,
            tooltip = { QUEST_LINE } }
    end

    -- A world: the game with a client that answers requests for quest data, and the addon.
    -- questie: the quests QuestieDB has; app: AllTheThings' stand-in.
    local function World(flavor, toon, items, questie, app)
        local world = {
            have = {},        -- questID -> { level, trivial }: the quests the client has the data of
            answers = {},     -- questID -> { after, level, trivial, refuse, atOnce }: how it answers a request
            requested = {},   -- every request, in order
            timesAsked = {},  -- questID -> how often
            outstanding = 0,
            mostOutstanding = 0,
            completed = {},
            onQuest = {},
            refreshes = {},
        }
        local game = H.StockGame(toon, items)
        if questie then
            local ids = {}
            for questID in pairs(questie) do
                ids[#ids + 1] = questID
            end
            table.sort(ids)
            game:Set("LibQuestieDB.RequireContract", function() return true end)
            game:Set("LibQuestieDB.Quest.GetAllIds", function() return ids end)
            game:Set("LibQuestieDB.Quest.Get", function(questID, field) return questie[questID] and questie[questID][field] end)
            game:Set("LibQuestieDB.Enum", { classKeys = { HUNTER = 4 }, raceMaskById = { [3] = 4 } })
        end
        if app then
            game:Set("AllTheThings", app)
        end
        game:Set("C_QuestLog.IsOnQuest", function(questID) return world.onQuest[questID] == true end)
        game:Set("C_QuestLog.IsQuestFlaggedCompleted", function(questID) return world.completed[questID] == true end)
        game:Set("C_QuestLog.GetTitleForQuestID", function() return nil end)
        -- The client's quest data.
        game:Set("HaveQuestData", function(questID) return world.have[questID] ~= nil end)
        game:Set("C_QuestLog.GetQuestDifficultyLevel", function(questID)
            return world.have[questID] and world.have[questID].level or 0
        end)
        game:Set("C_QuestLog.IsQuestTrivial", function(questID)
            return world.have[questID] ~= nil and world.have[questID].trivial == true
        end)
        game:Set("C_QuestLog.RequestLoadQuestByID", function(questID)
            world.requested[#world.requested + 1] = questID
            world.timesAsked[questID] = (world.timesAsked[questID] or 0) + 1
            world.outstanding = world.outstanding + 1
            world.mostOutstanding = math.max(world.mostOutstanding, world.outstanding)
            local answer = world.answers[questID]
            if not answer then
                return
            end
            local function Deliver()
                world.outstanding = world.outstanding - 1
                if not answer.refuse then
                    world.have[questID] = { level = answer.level, trivial = answer.trivial == true }
                end
                world.client:Fire("QUEST_DATA_LOAD_RESULT", questID, not answer.refuse)
            end
            if answer.atOnce then
                Deliver()
            else
                world.client.env.C_Timer.After(answer.after or 0.3, Deliver)
            end
        end)
        -- What an item of the Quest type asks as it loads (types/QuestMixin.lua).
        game:Set("C_QuestLog.IsWorldQuest", function() return false end)
        game:Set("QuestInfoFrame", {})
        game:Set("GetNumQuestRewards", function() return 0 end)
        game:Set("GetNumQuestChoices", function() return 0 end)
        game:Set("GetInstanceInfo", function() return "Elsewhere", "none" end)
        -- What the whole export asks beyond the item.
        game:Set("C_AddOns.GetAddOnInfo", function(name) return name, name, "", true, nil, "INSECURE" end)
        game:Set("PLAYER_FACTION_GROUP", { [0] = "Horde", [1] = "Alliance" })

        local client = H.Client.New({ flavor = flavor, provider = game })
        game.client = client
        world.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "features/DebugFrame.lua", namespace)
        local env = client.env
        world.env, world.namespace = env, namespace

        -- Every full refresh, with what it said had changed.
        local core = env.CaerdonWardrobe
        local refreshItems = core.RefreshItems
        function core:RefreshItems(reason, detail, changed)
            world.refreshes[#world.refreshes + 1] = { reason = reason, detail = detail }
            return refreshItems(self, reason, detail, changed)
        end

        -- What the queue was told has come, by its key.
        world.retried = {}
        local retryWaitingFor = core.RetryWaitingFor
        function core:RetryWaitingFor(key)
            world.retried[tostring(key)] = (world.retried[tostring(key)] or 0) + 1
            return retryWaitingFor(self, key)
        end

        function world.Loaded(item)
            local loaded = false
            item:ContinueOnItemLoad(function() loaded = true end)
            client:TickUntil(function() return loaded end, 10)
            return item
        end
        function world.Info(id)
            return world.Loaded(env.CaerdonItem:CreateFromItemID(id)):GetQuestItemInfo()
        end
        -- The one quest named for an item, and its verdict.
        function world.Only(id)
            local info = world.Info(id)
            return info and #info.quests == 1 and info.quests[1] or {}, info
        end
        function world.Status(id)
            local item = world.Loaded(env.CaerdonItem:CreateFromItemID(id))
            local ready, status
            client:TickUntil(function()
                ready, status = item:GetCaerdonStatus()
                return ready
            end, 10)
            return ready and (status or "") or "<not ready>"
        end
        -- The status as it is at this moment, with what it waits for where it is not ready.
        function world.StatusNow(id)
            local item = world.Loaded(env.CaerdonItem:CreateFromItemID(id))
            local ready, status, key = item:GetCaerdonStatus()
            if ready then
                return true, status or ""
            end
            return false, status, key
        end
        function world.Row(id, label)
            local feature = env.CaerdonWardrobe:GetFeature("DebugFrame")
            local payload = feature:BuildClipboardPayload(world.Loaded(env.CaerdonItem:CreateFromItemID(id)))
            for line in (payload .. "\n"):gmatch("(.-)\n") do
                if line:find(label, 1, true) then
                    return line
                end
            end
        end
        -- A refresh that is the scenario's own, which the log of refreshes leaves out.
        function world.Refresh()
            refreshItems(core)
        end
        function world.Seconds(seconds)
            client:Tick(math.floor(seconds / 0.05 + 0.5))
        end
        -- The refreshes since the last call, as their details.
        function world.NewRefreshes()
            local details = {}
            for _, entry in ipairs(world.refreshes) do
                details[#details + 1] = tostring(entry.reason) .. ": " .. tostring(entry.detail)
            end
            world.refreshes = {}
            return details
        end
        function world.ClientState()
            return env.CaerdonQuestItems:GetDebugState()
        end
        return world
    end

    ------------------------------------------------------------------------------------------
    -- QuestieDB's quests, as on WoW Forever
    ------------------------------------------------------------------------------------------
    do
        local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
            faction = "Alliance", level = 33 }
        local ORB, SAME, GRAY, COIN, STONE, RELIC, DONE, LOGGED, NOPE, MUTE, SYNC, PLAIN = 996001, 996002, 996003,
            996004, 996005, 996006, 996007, 996008, 996009, 996010, 996011, 996012
        local ITEMS = {
            [ORB] = QuestItem("Flawless Orb"), [SAME] = QuestItem("Plain Token"), [GRAY] = QuestItem("Gray Token"),
            [COIN] = QuestItem("Old Coin"), [STONE] = QuestItem("Far Stone"), [RELIC] = QuestItem("Priest's Relic"),
            [DONE] = QuestItem("Spent Token"), [LOGGED] = QuestItem("Token in Hand"), [NOPE] = QuestItem("Unknown Token"),
            [MUTE] = QuestItem("Silent Token"), [SYNC] = QuestItem("Quick Token"), [PLAIN] = QuestItem("Late Token"),
        }
        local function Quest(name, item, fields)
            local quest = { name = name, requiredLevel = 28, questLevel = 33, startedBy = { { 5 } },
                objectives = { [3] = { { item } } } }
            for key, value in pairs(fields or {}) do
                quest[key] = value
            end
            return quest
        end
        local QUESTS = {
            -- No level it asks for in the quest data, and of level 55 by it.
            [7001] = Quest("To Serve the Orb", ORB, { requiredLevel = 0, questLevel = 55 }),
            [7002] = Quest("A Plain Errand", SAME),
            -- Not trivial by the quest data's level (30 against a toon of 33).
            [7003] = Quest("An Errand Outgrown", GRAY, { requiredLevel = 20, questLevel = 30 }),
            -- Trivial by the quest data's level.
            [7004] = Quest("An Old Debt", COIN, { requiredLevel = 5, questLevel = 10 }),
            [7005] = Quest("A Later Errand", STONE, { requiredLevel = 45, questLevel = 47 }),
            [7006] = Quest("The Priest's Task", RELIC, { requiredClasses = 16 }),
            [7007] = Quest("Done and Dusted", DONE),
            [7008] = Quest("Under Way", LOGGED),
            [7009] = Quest("Nobody Knows It", NOPE),
            [7010] = Quest("No Word of It", MUTE),
            [7011] = Quest("Answered at Once", SYNC),
            [7012] = Quest("Asked Later", PLAIN),
        }
        -- Sixty more, to be asked for in one frame.
        local MANY = {}
        for index = 1, 60 do
            local item, questID = 996100 + index, 7100 + index
            ITEMS[item] = QuestItem("Token " .. index)
            QUESTS[questID] = Quest("Errand " .. index, item)
            MANY[index] = { item = item, questID = questID }
        end

        local world = World("forever", TOON, ITEMS, QUESTS)
        local Info, Only, Status = world.Info, world.Only, world.Status
        world.completed[7007], world.onQuest[7008] = true, true
        Equal(#world.client.errors, 0, "start: no error reached the error handler")
        -- The index is built after the first question, over the next frames.
        Info(SAME)
        world.Seconds(3)
        world.Refresh()
        world.NewRefreshes()
        world.requested, world.timesAsked = {}, {}

        -- A quest whose quest data has no level it asks for: judged by the quest data's level
        -- for it, then by the client's.
        do
            world.answers[7001] = { level = 36 }
            local quest, info = Only(ORB)
            Equal(quest.reason, "of level 55, and the level it asks for is not known", "orb: judged from the quest data first")
            Equal(quest.clientState, "the client is asked for it", "orb: and the client is asked")
            Check(info and not info.hasQuestValue and info.keptOutByOptions == true, "orb: kept out by the range meanwhile")
            local ready = world.StatusNow(ORB)
            Equal(ready, true, "orb: its verdict does not wait: the quest data has a level to go by")
            Equal(Status(ORB), "", "orb: no icon meanwhile")
            Equal(#world.requested, 0, "orb: the request is not put from inside the question")
            world.client:Tick(1)
            Equal(table.concat(world.requested, ","), "7001", "orb: it is put on the next frame")
            world.Seconds(2)
            local refreshes = world.NewRefreshes()
            Equal(#refreshes, 1, "orb: its answer is one refresh")
            Equal(refreshes[1], "quest data: the client's word: quest 7001: kept out by the options -> upcoming",
                "orb: which says what changed")
            quest, info = Only(ORB)
            Check(info and info.hasQuestValue and info.isUpcoming, "orb: of level 36 by the client, it is still to come")
            Equal(quest.questLevel, 36, "orb: the level is the client's")
            Equal(quest.levelFromClient, true, "orb: and said to be")
            Equal(quest.clientState, nil, "orb: nothing is waited for")
            Equal(Status(ORB), "quest", "orb: the quest icon")
            world.Seconds(2)
            Equal(world.timesAsked[7001], 1, "orb: asked for once")
            Equal(#world.NewRefreshes(), 0, "orb: and no further refresh")
        end

        -- A quest the client says the same of as the quest data: asked, and nothing redrawn.
        do
            world.answers[7002] = { level = 33 }
            Check(Only(SAME).eligible == true, "same: still to come by the quest data")
            world.Seconds(2)
            Equal(world.timesAsked[7002], 1, "same: the client was asked")
            Equal(#world.NewRefreshes(), 0, "same: its answer changes no icon and refreshes nothing")
            local quest = Only(SAME)
            Check(quest.eligible == true and quest.levelFromClient == true, "same: the verdict is the one made with the client's word")
        end

        -- Trivial is the client's to say, both ways.
        do
            world.answers[7003] = { level = 24, trivial = true }
            world.answers[7004] = { level = 10, trivial = false }
            Check(Only(GRAY).eligible == true, "trivial: a quest of level 30 is not trivial by the quest data")
            Equal(Only(COIN).reason, "trivial at this level", "trivial: one of level 10 is")
            Equal(Status(GRAY), "quest", "trivial: the first one's item has the quest icon")
            Equal(Status(COIN), "", "trivial: the second one's has none")
            world.Seconds(2)
            local refreshes = world.NewRefreshes()
            Equal(#refreshes, 1, "trivial: the two answers of one run are one refresh")
            Equal(refreshes[1], "quest data: the client's word: quest 7003: upcoming -> kept out by the options; " ..
                "quest 7004: kept out by the options -> upcoming", "trivial: which names both")
            Equal(Only(GRAY).reason, "trivial at this level", "trivial: the client calls the first trivial")
            Check(Only(COIN).eligible == true, "trivial: and the second not")
            Equal(Status(GRAY), "", "trivial: the icons follow")
            Equal(Status(COIN), "quest", "trivial: both ways")
        end

        -- Asked only where the client's word can change the verdict.
        do
            Equal(Only(STONE).reason, "needs level 45", "not asked: a quest the level it asks for keeps out")
            Check(Only(RELIC).over == true, "not asked: one of another class")
            Equal(Only(DONE).reason, "completed", "not asked: one that is done")
            Equal(Only(LOGGED).reason, "in quest log", "not asked: one in the log")
            local config = world.env.CaerdonWardrobeConfig.Icon
            config.IncludeTrivialQuests = true
            world.Refresh()
            Check(Only(PLAIN).eligible == true, "not asked: with trivial quests wanted, one whose level is known")
            world.Seconds(2)
            for _, questID in ipairs({ 7005, 7006, 7007, 7008, 7012 }) do
                Equal(world.timesAsked[questID], nil, "not asked: quest " .. questID)
            end
            config.IncludeTrivialQuests = false
            world.Refresh()
            world.answers[7012] = { level = 33 }
            Only(PLAIN)
            world.Seconds(2)
            Equal(world.timesAsked[7012], 1, "not asked: and asked once trivial quests are left out")
            world.NewRefreshes()
        end

        -- A quest the client refuses, and one it never answers for: judged from the quest data,
        -- and not asked for again.
        do
            world.answers[7009] = { refuse = true }
            Check(Only(NOPE).eligible == true, "refused: still to come by the quest data")
            Only(MUTE)
            world.Seconds(2)
            world.Refresh()
            local quest = Only(NOPE)
            Check(quest.eligible == true, "refused: and stays so")
            Equal(quest.clientState, "the client has no data of it", "refused: the verdict says why it is the quest data's")
            Equal(Only(MUTE).clientState, "the client is asked for it", "silent: two seconds on, the answer is still waited for")
            world.Seconds(13)
            world.Refresh()
            Equal(Only(MUTE).clientState, "the client did not answer", "silent: and given up on after a while")
            Only(NOPE)
            world.Seconds(2)
            Equal(world.timesAsked[7009], 1, "refused: asked for once")
            Equal(world.timesAsked[7010], 1, "silent: asked for once")
            Equal(#world.NewRefreshes(), 0, "refused, silent: no refresh by either")
            local state = world.ClientState().client
            Equal(state.refused, 1, "refused: counted")
            Equal(state.silent, 1, "silent: counted")
            Equal(state.inFlight, 0, "silent: its place is free again")

            -- The answer comes after all: the quest is judged with it.
            world.have[7010] = { level = 20, trivial = true }
            world.client:Fire("QUEST_DATA_LOAD_RESULT", 7010, true)
            world.Seconds(2)
            local refreshes = world.NewRefreshes()
            Equal(refreshes[1], "quest data: the client's word: quest 7010: upcoming -> kept out by the options",
                "late: an answer after that is still heard")
            state = world.ClientState().client
            Equal(state.late, 1, "late: counted")
            Equal(state.silent, 0, "late: and no longer as not answered")
        end

        -- An answer about a quest nobody here asked for is nobody's.
        do
            local checks = world.ClientState().clientChecks
            world.have[424242] = { level = 33 }
            world.client:Fire("QUEST_DATA_LOAD_RESULT", 424242, true)
            world.client:Fire("QUEST_DATA_LOAD_RESULT", 7002, true)
            world.Seconds(2)
            Equal(world.ClientState().clientChecks, checks, "other: an answer to somebody else's request judges nothing")
            Equal(#world.NewRefreshes(), 0, "other: and refreshes nothing")
        end

        -- The client answers from inside the call.
        do
            world.answers[7011] = { level = 20, trivial = true, atOnce = true }
            Check(Only(SYNC).eligible == true, "at once: still to come by the quest data")
            world.Seconds(2)
            Equal(world.NewRefreshes()[1], "quest data: the client's word: quest 7011: upcoming -> kept out by the options",
                "at once: an answer from inside the request is heard as any other")
            Equal(#world.client.errors, 0, "at once: no error reached the error handler")
        end

        -- Many at a time: a few are out at once, and the run of answers is one check.
        do
            for index, entry in ipairs(MANY) do
                -- Six of them the client calls trivial.
                world.answers[entry.questID] = { level = 33, trivial = index % 10 == 0, after = 0.4 }
            end
            local before = #world.requested
            local runs = world.ClientState().client.handedOn
            world.outstanding, world.mostOutstanding = 0, 0
            for _, entry in ipairs(MANY) do
                world.env.CaerdonQuestItems:GetItemQuestInfo(entry.item, ITEMS[entry.item].name)
            end
            world.client:Tick(1)
            Equal(#world.requested - before, 25, "many: twenty-five requests are put on the first frame")
            Equal(world.ClientState().client.queued, 35, "many: the others wait their turn")
            world.Seconds(5)
            Equal(#world.requested - before, 60, "many: all of them are put in the end")
            Check(world.mostOutstanding <= 25, "many: never more than twenty-five at a time (" .. world.mostOutstanding .. ")")
            Equal(world.ClientState().client.handedOn - runs, 1, "many: the answers are one run")
            local refreshes = world.NewRefreshes()
            Equal(#refreshes, 1, "many: and one refresh, for the six the client calls trivial")
            Equal(refreshes[1], "quest data: the client's word: quest 7110: upcoming -> kept out by the options; " ..
                "quest 7120: upcoming -> kept out by the options; quest 7130: upcoming -> kept out by the options; " ..
                "and 3 more", "many: named")
            Equal(world.ClientState().client.inFlight, 0, "many: nothing is left on its way")
        end

        -- What the client said stands when it drops the quest's data again, while the toon is
        -- of the level it said it for.
        do
            world.have[7001] = nil
            world.Refresh()
            local quest, info = Only(ORB)
            Check(info and info.hasQuestValue and quest.questLevel == 36, "kept: the data gone, the level it said stands")
            world.Seconds(2)
            Equal(world.timesAsked[7001], 1, "kept: and it is not asked again")
            Check(world.ClientState().client.fromMemory >= 1, "kept: the export counts it")
            Equal(#world.NewRefreshes(), 0, "kept: nothing is refreshed")

            -- The recorder's forgetting: a replay starts with nothing said.
            world.env.CaerdonQuestItems:ForgetClientAnswers()
            world.Refresh()
            Equal(Only(ORB).reason, "of level 55, and the level it asks for is not known", "forgotten: judged from the quest data again")
            world.Seconds(2)
            Equal(world.timesAsked[7001], 2, "forgotten: and asked again")
            Equal(#world.NewRefreshes(), 1, "forgotten: its answer is a refresh as the first was")

            -- A level gained: trivial is said for a level, so what was said for the last one
            -- is not used.
            world.have[7001] = nil
            TOON.level = 34
            world.Refresh()
            Equal(Only(ORB).clientState, "the client is asked for it", "level: at another level the client is asked anew")
            world.Seconds(2)
            Equal(world.timesAsked[7001], 3, "level: once")
            Check(Only(ORB).eligible == true, "level: and answers")
            world.NewRefreshes()
            TOON.level = 33
            world.Refresh()
        end

        -- The export.
        do
            Only(ORB)
            local row = world.Row(ORB, "The Client's Quest Data") or ""
            Check(row:find("this session asked for", 1, true) ~= nil, "export: what the client was asked (" .. row .. ")")
            row = world.Row(ORB, "The Client's Answers Compared") or ""
            Check(row:find("changed an icon", 1, true) ~= nil, "export: and what came of it (" .. row .. ")")
            row = world.Row(ORB, "The Client's Quest Data Cost") or ""
            Check(row:find("putting the requests took", 1, true) ~= nil, "export: and what the asking and the judging cost (" .. row .. ")")
            local state = world.ClientState()
            Check(state.client.pumps >= 3 and state.client.pumps <= state.client.asked, "export: the frames in which requests were put are counted")
            Check(state.clientJudged >= 25, "export: so are the quests judged again for an answer (" .. tostring(state.clientJudged) .. ")")
            row = world.Row(ORB, "7001 To Serve the Orb") or ""
            Check(row:find("level 36 by the client, requires 0", 1, true) ~= nil, "export: the quest's level is said to be the client's (" .. row .. ")")
            row = world.Row(NOPE, "7009 Nobody Knows It") or ""
            Check(row:find("the client has no data of it", 1, true) ~= nil, "export: a refused quest says so (" .. row .. ")")
            row = world.Row(STONE, "7005 A Later Errand") or ""
            Check(row:find("[level 47, requires 45]", 1, true) ~= nil, "export: a quest that was not asked for has the quest data's level (" .. row .. ")")
        end

        -- The counters' ledger has the requests, filed under the file that puts them.
        do
            local loads = world.env.CaerdonCounters:GetReport().itemLoads
            local filed
            for by, entry in pairs(loads.by) do
                if by:find("CaerdonQuestClient", 1, true) then
                    filed = entry
                end
            end
            Check(filed ~= nil and filed.asked >= 25, "ledger: the requests are in the counters, under this file")
            Check(filed ~= nil and filed.failed == 1, "ledger: with the one the client refused")
        end

        Equal(#world.client.errors, 0, "QuestieDB: no error reached the error handler")
        for _, message in ipairs(world.client.errors) do
            Check(false, "error: " .. message)
        end
    end

    ------------------------------------------------------------------------------------------
    -- AllTheThings' quests, as on retail: it has no quest level at all
    ------------------------------------------------------------------------------------------
    do
        local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
            faction = "Alliance", level = 33 }
        local FANG, HIGH, FAR, BANNER, EAR, NOPE, MUTE, BOTH, OFF = 997001, 997002, 997003, 997004, 997005,
            997006, 997007, 997008, 997009
        local ITEMS = {
            [FANG] = QuestItem("Wolf Fang"), [HIGH] = QuestItem("High Token"), [FAR] = QuestItem("Far Token"),
            [BANNER] = QuestItem("Horde Banner"), [EAR] = QuestItem("Gnoll Ear"), [NOPE] = QuestItem("Unknown Token"),
            [MUTE] = QuestItem("Silent Token"), [BOTH] = QuestItem("Token of Two Quests"),
            [OFF] = QuestItem("Token for Later"),
        }
        local function Quest(questID, fields)
            fields.questID = questID
            fields.key = "questID"
            return fields
        end
        local QUESTS = {
            [9201] = Quest(9201, { cost = { { "i", FANG, 1 } }, lvl = 30 }),
            -- No level it asks for.
            [9202] = Quest(9202, { cost = { { "i", HIGH, 1 } } }),
            [9203] = Quest(9203, { cost = { { "i", FAR, 1 } }, lvl = 60 }),
            [9204] = Quest(9204, { cost = { { "i", BANNER, 1 } }, r = 1 }),
            [9205] = Quest(9205, { cost = { { "i", EAR, 1 } }, lvl = 30 }),
            [9206] = Quest(9206, { cost = { { "i", NOPE, 1 } }, lvl = 30 }),
            [9207] = Quest(9207, { cost = { { "i", MUTE, 1 } }, lvl = 30 }),
            -- Two quests take one item, and the toon is on the first.
            [9208] = Quest(9208, { lvl = 30 }),
            [9209] = Quest(9209, { lvl = 30 }),
            [9210] = Quest(9210, { cost = { { "i", OFF, 1 } }, lvl = 30 }),
        }
        local caches = { questID = {}, itemIDAsCost = {}, qItemID = {} }
        for questID, quest in pairs(QUESTS) do
            caches.questID[questID] = { quest }
            if quest.cost then
                caches.itemIDAsCost[quest.cost[1][2]] = { quest }
            end
        end
        QUESTS[9208].cost, QUESTS[9209].cost = { { "i", BOTH, 1 } }, { { "i", BOTH, 1 } }
        caches.itemIDAsCost[BOTH] = { QUESTS[9208], QUESTS[9209] }
        local app = {
            GetRawField = function(field, id) return caches[field] and caches[field][id] or nil end,
            GetRawFieldContainer = function(field) return caches[field] end,
            GetRelativeValue = function(group, field)
                while type(group) == "table" do
                    local value = rawget(group, field)
                    if value ~= nil then
                        return value
                    end
                    group = rawget(group, "parent")
                end
            end,
            AddEventHandler = function() end,
        }

        local world = World("retail", TOON, ITEMS, nil, app)
        local Only, Status, StatusNow = world.Only, world.Status, world.StatusNow
        -- AllTheThings' data is looked for a few seconds after the world is entered, which
        -- is a refresh of its own.
        world.Seconds(3)
        world.Refresh()
        world.NewRefreshes()

        -- Nothing in this data says whether a quest is trivial, and at the level cap nearly
        -- every older quest is. So while the client is asked the item's verdict is put off,
        -- and the button that waits is asked again when the answer is in: no icon is drawn to
        -- be taken away, and nothing is refreshed.
        world.answers[9201] = { level = 20, trivial = true }
        local ready, why, key = StatusNow(FANG)
        Equal(ready, false, "AllTheThings: the verdict waits while the client is asked")
        Equal(why, "the client's word on a quest", "AllTheThings: and says what for")
        Equal(key, "quest:9201", "AllTheThings: with the quest's key for the queue")
        local quest, info = Only(FANG)
        Check(quest.pending == true and quest.clientState == "the client is asked for it",
            "AllTheThings: the quest's verdict says it waits")
        Equal(info and info.waitingFor, 9201, "AllTheThings: and the item names the quest")
        world.Seconds(2)
        Equal(world.retried["quest:9201"], 1, "AllTheThings: the answer asks the buttons that wait for that quest again")
        Equal(#world.NewRefreshes(), 0, "AllTheThings: and nothing is refreshed for it")
        ready = StatusNow(FANG)
        Equal(ready, true, "AllTheThings: the verdict is ready then")
        quest, info = Only(FANG)
        Equal(quest.reason, "trivial at this level", "AllTheThings: trivial by the client")
        Equal(quest.questLevel, 20, "AllTheThings: with the client's level for it")
        Equal(info and info.waitingFor, nil, "AllTheThings: nothing is waited for")
        Equal(Status(FANG), "", "AllTheThings: and no quest icon, which was never drawn")

        -- A quest the client does not call trivial: the icon comes with the answer.
        world.answers[9205] = { level = 33 }
        Equal(StatusNow(EAR), false, "not trivial: the verdict waits as well")
        world.Seconds(2)
        Equal(select(2, StatusNow(EAR)), "quest", "not trivial: and is the quest icon once the client has answered")
        Equal(#world.NewRefreshes(), 0, "not trivial: with no refresh")

        -- A quest with no level it asks for goes by its own level, which is the client's.
        world.answers[9202] = { level = 60 }
        Equal(StatusNow(HIGH), false, "no level: the verdict waits")
        world.Seconds(2)
        Equal(Only(HIGH).reason, "of level 60, and the level it asks for is not known",
            "no level: of level 60 by the client, it is beyond the range")
        Equal(select(2, StatusNow(HIGH)), "", "no level: and its item has no icon")
        Equal(#world.NewRefreshes(), 0, "no level: with no refresh")

        -- The client refuses: the wait ends with the refusal, and the quest is judged without.
        world.answers[9206] = { refuse = true }
        Equal(StatusNow(NOPE), false, "refused: the verdict waits for the answer")
        world.Seconds(2)
        Equal(world.retried["quest:9206"], 1, "refused: a refusal is an answer for the buttons that wait")
        Equal(select(2, StatusNow(NOPE)), "quest", "refused: judged without the client, the quest is still to come")
        Equal(Only(NOPE).clientState, "the client has no data of it", "refused: and its line says why")

        -- The client never answers: the wait ends when the request is given up on.
        Equal(StatusNow(MUTE), false, "silent: the verdict waits")
        world.Seconds(3)
        Equal(StatusNow(MUTE), false, "silent: three seconds on it still does")
        world.Seconds(5)
        Equal(world.retried["quest:9207"], 1, "silent: giving up on the request asks the waiting buttons again")
        Equal(select(2, StatusNow(MUTE)), "quest", "silent: judged without the client")
        Equal(Only(MUTE).clientState, "the client did not answer", "silent: and its line says why")
        Equal(#world.NewRefreshes(), 0, "refused, silent: nothing is refreshed")

        -- A quest in the log takes the item too: the quest icon whatever the client says of
        -- the other quest, so nothing is waited for.
        world.onQuest[9208] = true
        world.Refresh()
        ready, why = StatusNow(BOTH)
        Check(ready == true and why == "quest", "in the log: an item a quest in the log takes does not wait (" .. tostring(why) .. ")")
        Equal(world.Info(BOTH).waitingFor, nil, "in the log: and names no quest to wait for")

        -- With the quest icon switched off no icon hangs on the answer.
        local config = world.env.CaerdonWardrobeConfig.Icon
        config.ShowQuestItems = false
        world.Refresh()
        Equal(StatusNow(OFF), true, "off: with the quest icon off nothing waits")
        config.ShowQuestItems = true
        world.Refresh()

        -- Not asked where its word changes nothing, and so not waited for either.
        Equal(Only(FAR).reason, "needs level 60", "AllTheThings: a quest the level it asks for keeps out")
        Check(Only(BANNER).over == true, "AllTheThings: one of another faction")
        Equal(StatusNow(FAR), true, "AllTheThings: the first does not wait")
        Equal(StatusNow(BANNER), true, "AllTheThings: nor the second")
        world.Seconds(2)
        Equal(world.timesAsked[9203], nil, "AllTheThings: the first is not asked for")
        Equal(world.timesAsked[9204], nil, "AllTheThings: nor the second")

        Equal(#world.client.errors, 0, "AllTheThings: no error reached the error handler")
        for _, message in ipairs(world.client.errors) do
            Check(false, "error: " .. message)
        end
    end
end
