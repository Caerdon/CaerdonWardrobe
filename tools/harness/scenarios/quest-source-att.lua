-- AllTheThings as a source of quest data (CaerdonQuestSourceATT.lua): which quests take an
-- item, and whether the toon can still take them, read from AllTheThings' own tables while it
-- is loaded. Alone, as on retail, and beside QuestieDB, as on WoW Forever.
--
-- The game and AllTheThings are hand-made. The stand-in for AllTheThings has the functions and
-- the shapes its source has (5.4.16, src/Cache.lua and src/Classes/Quests.lua): GetRawField and
-- GetRawFieldContainer over its caches "questID", "itemIDAsCost" and "qItemID",
-- GetRelativeValue up the parents, AddEventHandler, and quests as tables with key = "questID"
-- and the raw fields cost, qis, qss, providers, lvl, races, r, c, u, e, sourceQuests, altQuests,
-- the repeating flags. It proves what the addon does with such data, and nothing about
-- AllTheThings itself: no client has run this.
--
-- Real code: the addon's item side and features/DebugFrame.lua, Blizzard's base files from
-- the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 33 }

    local QUEST_LINE = { text = "Quest Item", type = 20, bonding = 0 }
    local function QuestItem(name)
        return { name = name, quality = 1, level = 1, minLevel = 0, type = "Quest", subType = "Quest", stack = 1,
            equipLoc = "INVTYPE_NON_EQUIP_IGNORE", price = 0, classID = 12, subClassID = 0, bindType = 4,
            tooltip = { QUEST_LINE } }
    end

    local CLOTH, FANG, BANNER, LATER, GONE, DAILY, NOTE, HIDDEN, EAR, PSALM, DONE, FAR, YOUNG, ELVEN, EITHER, SEAL =
        994001, 994002, 994003, 994004, 994005, 994006, 994007, 994008, 994009, 994010, 994011, 994012, 994013,
        994014, 994015, 994016
    local SLIP, SUMMONS = 994017, 994018
    local ITEMS = {
        -- Starts a quest that can be done again, and one of the other faction.
        [SLIP] = QuestItem("Daily Slip"),
        [SUMMONS] = QuestItem("Horde Summons"),
        -- No quest item by its class: only a quest that takes it gives it the quest icon.
        [CLOTH] = { name = "Bolt of Cloth", quality = 1, level = 20, minLevel = 0, type = "Miscellaneous",
            subType = "Other", stack = 20, equipLoc = "INVTYPE_NON_EQUIP_IGNORE", price = 100, classID = 15,
            subClassID = 4, bindType = 0, tooltip = {} },
        [FANG] = QuestItem("Wolf Fang"),
        [BANNER] = QuestItem("Horde Banner"),
        [LATER] = QuestItem("Later Token"),
        [GONE] = QuestItem("Token of a Removed Quest"),
        [DAILY] = QuestItem("Daily Token"),
        [NOTE] = QuestItem("Strange Note"),
        [HIDDEN] = QuestItem("Trigger Token"),
        [EAR] = QuestItem("Gnoll Ear"),
        [PSALM] = QuestItem("Priest's Psalm"),
        [DONE] = QuestItem("Token of a Finished Quest"),
        [FAR] = QuestItem("Far Token"),
        [YOUNG] = QuestItem("Token of Youth"),
        [ELVEN] = QuestItem("Elven Token"),
        [EITHER] = QuestItem("Token of Two Paths"),
        -- Handed in at the fifth step of a chain.
        [SEAL] = QuestItem("Seal for the Fifth Step"),
    }

    -- AllTheThings' data, as its caches hold it.
    local function Quest(questID, fields)
        fields.questID = questID
        fields.key = "questID"
        return fields
    end
    local hiddenHeader = { key = "headerID", _hqt = true }
    local eventHeader = { key = "headerID", e = 7 }
    local QUESTS = {
        [9101] = Quest(9101, { cost = { { "i", CLOTH, 20 } }, lvl = 30 }),
        [9102] = Quest(9102, { qis = { FANG }, lvl = 30 }),
        [9103] = Quest(9103, { cost = { { "i", BANNER, 1 } }, r = 1 }),
        [9104] = Quest(9104, { cost = { { "i", LATER, 1 } }, sourceQuests = { 9199, -5 } }),
        [9105] = Quest(9105, { cost = { { "i", GONE, 1 } }, u = 2 }),
        [9106] = Quest(9106, { cost = { { "i", DAILY, 1 } }, isDaily = 1 }),
        [9107] = Quest(9107, { providers = { { "i", NOTE }, { "n", 77 } } }),
        [9108] = Quest(9108, { cost = { { "i", HIDDEN, 1 } }, parent = hiddenHeader }),
        [9109] = Quest(9109, { lvl = 30 }),
        [9110] = Quest(9110, { cost = { { "i", PSALM, 1 } }, c = { 5 } }),
        [9111] = Quest(9111, { cost = { { "i", DONE, 1 } } }),
        [9112] = Quest(9112, { cost = { { "i", FAR, 1 } }, lvl = 60 }),
        [9113] = Quest(9113, { cost = { { "i", YOUNG, 1 } }, lvl = { 10, 20 } }),
        [9114] = Quest(9114, { cost = { { "i", ELVEN, 1 } }, races = { 4, 10 } }),
        [9115] = Quest(9115, { cost = { { "i", EITHER, 1 } }, altQuests = { 9116 } }),
        [9116] = Quest(9116, {}),
        [9117] = Quest(9117, { providers = { { "i", SLIP } }, isDaily = 1 }),
        [9118] = Quest(9118, { providers = { { "i", SUMMONS } }, r = 1, isDaily = 1 }),
        [9199] = Quest(9199, {}),
        -- A chain of five; the last takes the seal. Its fourth step asks for one of two.
        [9131] = Quest(9131, {}),
        [9132] = Quest(9132, { sourceQuests = { 9131 } }),
        [9133] = Quest(9133, { sourceQuests = { 9132 } }),
        [9134] = Quest(9134, { sourceQuests = { 9133, 9139 }, sqreq = 1 }),
        [9135] = Quest(9135, { cost = { { "i", SEAL, 1 } }, sourceQuests = { 9134 }, lvl = 60 }),
        [9139] = Quest(9139, {}),
        -- An event's quest that takes the cloth too.
        [9120] = Quest(9120, { cost = { { "i", CLOTH, 5 } }, parent = eventHeader }),
    }
    -- A quest's objective names the item, and its parent is the quest (WoW Forever's data).
    local earObjective = { key = "objectiveID", objectiveID = 1, parent = QUESTS[9109], providers = { { "i", EAR } } }
    -- A vendor's ware costs the cloth as well, and is no quest.
    local vendorWare = { key = "itemID", itemID = 995000, cost = { { "i", CLOTH, 2 } } }

    local function Caches()
        local caches = { questID = {}, itemIDAsCost = {}, qItemID = {} }
        for questID, quest in pairs(QUESTS) do
            caches.questID[questID] = { quest }
            for _, entry in pairs(type(quest.cost) == "table" and quest.cost or {}) do
                if entry[1] == "i" then
                    caches.itemIDAsCost[entry[2]] = caches.itemIDAsCost[entry[2]] or {}
                    table.insert(caches.itemIDAsCost[entry[2]], quest)
                end
            end
            for _, entry in pairs(quest.providers or {}) do
                if entry[1] == "i" then
                    caches.itemIDAsCost[entry[2]] = caches.itemIDAsCost[entry[2]] or {}
                    table.insert(caches.itemIDAsCost[entry[2]], quest)
                end
            end
            for _, itemID in pairs(quest.qis or {}) do
                caches.qItemID[itemID] = caches.qItemID[itemID] or {}
                table.insert(caches.qItemID[itemID], quest)
            end
        end
        caches.itemIDAsCost[EAR] = { earObjective }
        table.insert(caches.itemIDAsCost[CLOTH], 1, vendorWare)
        return caches
    end

    -- A world: the game, AllTheThings in it, and the addon. questie: the quests QuestieDB has.
    local function World(flavor, questie)
        local world = { ready = true, handlers = {}, completed = {}, onQuest = {}, trivial = {}, haveData = {},
            caches = Caches() }
        local game = H.StockGame(TOON, ITEMS)
        local app = {}
        function app.GetRawField(field, id)
            local cache = world.ready and world.caches[field]
            return cache and cache[id] or nil
        end
        function app.GetRawFieldContainer(field)
            return world.ready and world.caches[field] or nil
        end
        function app.GetRelativeValue(group, field)
            while type(group) == "table" do
                local value = rawget(group, field)
                if value ~= nil then
                    return value
                end
                group = rawget(group, "parent")
            end
        end
        function app.AddEventHandler(name, handler)
            world.handlers[#world.handlers + 1] = { name = name, handler = handler }
        end
        world.app = app
        game:Set("AllTheThings", app)
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
        game:Set("C_QuestLog.IsOnQuest", function(questID) return world.onQuest[questID] == true end)
        game:Set("C_QuestLog.IsQuestFlaggedCompleted", function(questID) return world.completed[questID] == true end)
        game:Set("C_QuestLog.GetTitleForQuestID", function(questID) return "Quest " .. tostring(questID) end)
        game:Set("C_QuestLog.IsQuestTrivial", function(questID) return world.trivial[questID] == true end)
        game:Set("HaveQuestData", function(questID) return world.haveData[questID] == true end)
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
        world.client, world.env, world.namespace = client, client.env, namespace

        function world.Loaded(item)
            local loaded = false
            item:ContinueOnItemLoad(function() loaded = true end)
            client:TickUntil(function() return loaded end, 10)
            return item
        end
        function world.Info(id)
            return world.Loaded(world.env.CaerdonItem:CreateFromItemID(id)):GetQuestItemInfo()
        end
        function world.Status(id)
            local item = world.Loaded(world.env.CaerdonItem:CreateFromItemID(id))
            local ready, status
            client:TickUntil(function()
                ready, status = item:GetCaerdonStatus()
                return ready
            end, 10)
            return ready and (status or "") or "<not ready>"
        end
        -- The one quest named for an item, and its verdict.
        function world.Only(id)
            local info = world.Info(id)
            return info and #info.quests == 1 and info.quests[1] or {}, info
        end
        function world.After(event)
            client:Fire(event)
            client:Tick(60)
        end
        function world.Row(id, label)
            local feature = world.env.CaerdonWardrobe:GetFeature("DebugFrame")
            local payload = feature:BuildClipboardPayload(world.Loaded(world.env.CaerdonItem:CreateFromItemID(id)))
            for line in (payload .. "\n"):gmatch("(.-)\n") do
                if line:find(label, 1, true) then
                    return line
                end
            end
        end
        return world
    end

    -- Alone, as on retail.
    do
        local world = World("retail")
        local Info, Only, Status = world.Info, world.Only, world.Status
        Equal(#world.client.errors, 0, "start: no error reached the error handler")
        Equal(world.namespace.QuestSourceATT:GetDebugState().state, "ready", "start: AllTheThings is read")
        Equal(#world.handlers, 1, "start: its ready call is listened for, once")

        -- An item handed in at a quest that is still to come: the quest icon on an item that
        -- is no quest item, and a vendor's ware that costs it is no quest.
        local quest
        local info = Info(CLOTH)
        Equal(info and #info.quests, 2, "cost: both quests that take the cloth are listed, and the vendor's ware is not")
        Check(info and info.hasQuestValue and info.isUpcoming and not info.isActive, "cost: one of them is still to come")
        for _, entry in ipairs(info and info.quests or {}) do
            Equal(entry.source, "AllTheThings", "cost: quest " .. entry.questID .. " is judged from AllTheThings")
            if entry.questID == 9101 then
                Equal(entry.reason, "upcoming", "cost: the plain one is still to come")
                Equal(entry.role, "objective", "cost: as one that takes the item")
                Equal(entry.requiredLevel, 30, "cost: with the level it asks for")
            else
                Equal(entry.reason, "event quest", "cost: the one under an event's header is the event's")
                Equal(entry.over, false, "cost: which is not behind the toon")
            end
        end
        Equal(Status(CLOTH), "quest", "cost: the cloth has the quest icon")

        -- An item a quest has collected, and one named by a quest's objective.
        quest = Only(FANG)
        Check(quest.questID == 9102 and quest.eligible == true, "collected: the quest that has the fang collected is still to come")
        quest = Only(EAR)
        Check(quest.questID == 9109 and quest.eligible == true, "objective: an objective's item names the quest above it")

        -- An item that starts a quest.
        quest = Only(NOTE)
        Check(quest.questID == 9107 and quest.role == "starts quest" and quest.eligible == true,
            "starter: the note starts a quest still to come (" .. tostring(quest.role) .. ")")
        -- Which makes it one to act on: the star in the quest icon's place.
        info = Info(NOTE)
        Check(info and info.starts and info.starts.questID == 9107, "starter: the note is one that starts a quest not taken yet")
        Equal(Status(NOTE), "own", "starter: so it has the star")
        -- A quest that can be done again is none still to come, and one an item starts.
        quest, info = Only(SLIP)
        Check(quest.reason == "repeatable" and quest.eligible == false and quest.startable == true,
            "starter: a quest that can be done again is one its item can start (" .. tostring(quest.reason) .. ")")
        Check(info and info.starts and info.starts.questID == 9117, "starter: so the slip is one to act on")
        Equal(Status(SLIP), "own", "starter: with the star")
        -- Not where something else keeps the quest from the toon as well.
        quest, info = Only(SUMMONS)
        Check(quest.startable == false and quest.over == true and info.starts == nil,
            "starter: one of the other faction that can be done again is none to start (" .. tostring(quest.reason) .. ")")

        -- A quest in one of AllTheThings' hidden lists is not the quest as it is offered.
        Equal(Info(HIDDEN), nil, "hidden: a hidden trigger's quest is not named")

        -- What the toon can never take is behind it.
        for _, case in ipairs({
            { BANNER, "other faction" }, { GONE, "removed from the game" }, { PSALM, "other class" },
            { YOUNG, "outleveled" }, { ELVEN, "other race" },
        }) do
            quest = Only(case[1])
            Equal(quest.reason, case[2], "for good: " .. case[2])
            Check(quest.eligible == false and quest.over == true, "for good: and behind the toon (" .. case[2] .. ")")
            Equal(Status(case[1]), "sellable", "for good: its item is one to get rid of (" .. case[2] .. ")")
        end

        -- What is only out of reach for now is not.
        -- A quest the player's range keeps out gives its item no icon; one that is out of
        -- reach for another reason keeps the icon its class gives.
        for _, case in ipairs({
            { DAILY, "repeatable", "quest" }, { FAR, "needs level 60", "" },
        }) do
            quest = Only(case[1])
            Equal(quest.reason, case[2], "for now: " .. case[2])
            Check(quest.eligible == false and quest.over == false, "for now: not behind the toon (" .. case[2] .. ")")
            Equal(Status(case[1]), case[3], "for now: its item's icon, and it is not one to get rid of (" .. case[2] .. ")")
        end

        -- A chain: its fifth step is not coming while the chain is not begun, and is from the
        -- moment the toon is on a step of it, however far back.
        quest = Only(SEAL)
        Equal(quest.reason, "needs level 60", "chain: not begun, its fifth step is not coming, by its level first")
        Equal(quest.over, false, "chain: and not behind the toon")
        world.completed[9131], world.onQuest[9132] = true, true
        world.After("QUEST_ACCEPTED")
        quest = Only(SEAL)
        Check(quest.eligible == true and quest.reason == "upcoming",
            "chain: on its second step, the fifth is still to come, whatever its level (" .. tostring(quest.reason) .. ")")
        Equal(Status(SEAL), "quest", "chain: and its item has the quest icon")
        world.onQuest[9132] = nil
        world.After("QUEST_REMOVED")
        quest = Only(SEAL)
        Check(quest.eligible == true, "chain: the second step dropped, the first is done and the chain still begun")
        world.completed[9131] = nil
        world.After("QUEST_REMOVED")

        -- The player's settings: how far ahead a quest counts, and whether a trivial one does.
        do
            local config = world.env.CaerdonWardrobeConfig.Icon
            config.UpcomingQuestLevels = "any"
            world.env.CaerdonWardrobe:RefreshItems()
            Check(Only(FAR).eligible == true, "settings: a quest of level 60 is still to come within any level")
            config.UpcomingQuestLevels = "5"
            world.trivial[9102] = true
            world.env.CaerdonWardrobe:RefreshItems()
            Equal(Only(FAR).reason, "needs level 60", "settings: and not within five")
            -- The client's word counts only where it has the quest's data.
            Check(Only(FANG).eligible == true, "settings: trivial by a client that has no data of the quest is no word on it")
            world.haveData[9102] = true
            world.env.CaerdonWardrobe:RefreshItems()
            Equal(Only(FANG).reason, "trivial at this level", "settings: a quest the client has and calls trivial does not count")
            config.IncludeTrivialQuests = true
            world.env.CaerdonWardrobe:RefreshItems()
            Check(Only(FANG).eligible == true, "settings: and does where the player asks for those")
            config.IncludeTrivialQuests = false
            world.trivial[9102], world.haveData[9102] = nil, nil
            world.env.CaerdonWardrobe:RefreshItems()
        end

        -- A quest whose chain is not begun counts where its level is within the range.
        quest = Only(LATER)
        Check(quest.eligible == true and quest.reason == "upcoming",
            "chain: a quest within the range is still to come though the quest before it is not begun (" ..
            tostring(quest.reason) .. ")")

        -- A finished quest.
        world.completed[9111] = true
        world.env.CaerdonWardrobe:RefreshItems()
        quest = Only(DONE)
        Check(quest.reason == "completed" and quest.over == true, "done: a finished quest is behind the toon")
        Equal(Status(DONE), "sellable", "done: its item is one to get rid of")

        -- The quest before it done: the quest is still to come, and the icons follow.
        Equal(Status(EITHER), "quest", "events: a quest another one would lock is still to come")
        world.completed[9199], world.completed[9116] = true, true
        world.After("QUEST_TURNED_IN")
        quest = Only(EITHER)
        Equal(quest.reason, "exclusive with quest 9116", "events: the other quest done locks this one")
        Equal(quest.over, true, "events: for good")
        Equal(Status(EITHER), "sellable", "events: and its item is one to get rid of")

        -- The export.
        local row = world.Row(CLOTH, "AllTheThings:") or ""
        Check(row:find("ready", 1, true) ~= nil, "export: the source's state (" .. row .. ")")
        row = world.Row(CLOTH, "9101 Quest 9101") or ""
        Check(row:find("judged from AllTheThings", 1, true) ~= nil, "export: the quest's line says where it was judged from (" .. row .. ")")
        Equal(#world.client.errors, 0, "end: no error reached the error handler")
        for _, message in ipairs(world.client.errors) do
            Check(false, "error: " .. message)
        end
    end

    -- Data that comes after the first question: answered without it, then drawn again.
    do
        local world = World("retail")
        world.ready = false
        world.env.CaerdonWardrobe:RefreshItems()
        Equal(world.Info(CLOTH), nil, "late: nothing is known while AllTheThings has no data")
        Equal(world.namespace.QuestSourceATT:GetDebugState().state, "not ready", "late: and the source says so")
        Check(world.Status(CLOTH) ~= "quest", "late: no quest icon then")
        world.ready = true
        for _, entry in ipairs(world.handlers) do
            if entry.name == "OnReady" then
                entry.handler()
            end
        end
        world.client:Tick(60)
        Check(world.Info(CLOTH) ~= nil, "late: its ready call brings the quests")
        Equal(world.Status(CLOTH), "quest", "late: and the icon")
        Equal(world.namespace.QuestSourceATT:GetDebugState().readySeen, true, "late: the call is noted")

        -- Another AllTheThings than this was written for: nothing is read, and the export says what is gone.
        world.app.GetRawField = nil
        world.env.CaerdonWardrobe:RefreshItems()
        Equal(world.Info(CLOTH), nil, "changed: with a function gone nothing is read")
        local state = world.namespace.QuestSourceATT:GetDebugState()
        Equal(state.state, "unsupported", "changed: the source is unsupported")
        Equal(state.missingFunctions, "GetRawField", "changed: and names the function")
        local row = world.Row(CLOTH, "AllTheThings Functions Not Found") or ""
        Check(row:find("GetRawField", 1, true) ~= nil, "changed: the export says so (" .. row .. ")")
        Equal(#world.client.errors, 0, "changed: no error reached the error handler")
    end

    -- Beside QuestieDB, as on WoW Forever: a quest QuestieDB has is judged from QuestieDB,
    -- also where only AllTheThings ties the item to it, and one it lacks from AllTheThings.
    do
        local world = World("forever", {
            [9101] = { name = "Cloth for the Quartermaster", requiredLevel = 60, questLevel = 60, startedBy = { { 5 } } },
            [9300] = { name = "Fangs for the Hunter", requiredLevel = 30, questLevel = 33, startedBy = { { 5 } },
                objectives = { [3] = { { FANG } } } },
        })
        -- The index is built after the first question, over the next frames.
        world.Info(FANG)
        world.client:Tick(20)
        world.env.CaerdonWardrobe:RefreshItems()

        local info = world.Info(CLOTH)
        local byQuest = {}
        for _, entry in ipairs(info and info.quests or {}) do
            byQuest[entry.questID] = entry
        end
        Check(byQuest[9101] ~= nil, "both: AllTheThings ties the cloth to a quest QuestieDB has")
        Equal(byQuest[9101] and byQuest[9101].source, nil, "both: which is judged from QuestieDB")
        Equal(byQuest[9101] and byQuest[9101].reason, "needs level 60", "both: by QuestieDB's level for it")
        Equal(byQuest[9101] and byQuest[9101].name, "Cloth for the Quartermaster", "both: under QuestieDB's name")

        info = world.Info(FANG)
        byQuest = {}
        for _, entry in ipairs(info and info.quests or {}) do
            byQuest[entry.questID] = entry
        end
        Check(byQuest[9300] ~= nil and byQuest[9300].source == nil and byQuest[9300].eligible == true,
            "both: QuestieDB's own quest for the fang is still to come")
        Check(byQuest[9102] ~= nil and byQuest[9102].source == "AllTheThings" and byQuest[9102].eligible == true,
            "both: and the one only AllTheThings has is judged from it")
        Equal(#world.client.errors, 0, "both: no error reached the error handler")
        for _, message in ipairs(world.client.errors) do
            Check(false, "error: " .. message)
        end
    end
end
