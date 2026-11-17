-- The round trip: the test addon's real recorder records a hand-made game, what it saved goes
-- through the import, and the replay has to reproduce it. Then the faults a replay exists to
-- find are planted one at a time.
--
-- Real code: the addon's item side, the recorder (Core, RecordKeys, Recorder, Plan of the test
-- addon), Blizzard's base files from the mirror. Hand-made: the game (tools/harness/game.lua).
-- So this proves the machinery, and nothing about what a client answers.

return function(H, S)
    local Check, Equal = S.Check, S.Equal
    local TESTS = H.addonDir .. "/CaerdonWardrobe_Tests"

    if not H.ReadFile(TESTS .. "/ApiNames.lua") then
        error("CaerdonWardrobe_Tests/ApiNames.lua is not there: run `luajit tools/static-checks.lua --emit-facts`", 0)
    end

    --------------------------------------------------------------------------------------
    -- The two Lua 5.1 guards are on
    --------------------------------------------------------------------------------------

    do
        local thread = coroutine.create(function()
            return pcall(function() coroutine.yield() end)
        end)
        local _, ok, problem = coroutine.resume(thread)
        Check(ok == false and tostring(problem):find("LUA 5.1", 1, true) ~= nil, "guard: a yield inside pcall is refused")
        local formatted = H.Guards.pcall(string.format, "%s", {})
        Check(formatted == false, "guard: %s refuses a table")
        Check(H.Guards.pcall(string.format, "%d and %s", "5", 6) == true, "guard: a number as text still formats")
    end

    --------------------------------------------------------------------------------------
    -- What the recorder and the harness share
    --------------------------------------------------------------------------------------

    do
        local Keys = H.Keys
        Equal(Keys.Args(2, "a", nil), Keys.Args(1, "a"), "keys: trailing nils are no part of a question")
        Check(Keys.Args(1, 1) ~= Keys.Args(1, "1"), "keys: a number and its text are two questions")
        Equal(Keys.Args(1, { slotIndex = 3, bagID = 0, IsValid = function() end }),
            Keys.Args(1, { bagID = 0, slotIndex = 3 }), "keys: a table is its data, in any order, without its methods")
        local long = Keys.Args(1, ("x"):rep(5000))
        Check(#long <= 400 and long ~= Keys.Args(1, ("x"):rep(5001)), "keys: a long argument is cut and still tells apart")
        for _, name in ipairs({ "C_Item.GetItemInfo", "UnitLevel", "HaveQuestData", "InCombatLockdown",
            "C_TransmogCollection.PlayerCanCollectSource", "PawnGetItemData", "C_Container.ContainerIDToInventoryID" }) do
            Check(Keys.IsGetter(name), "keys: " .. name .. " is asked again for its answer")
        end
        for _, name in ipairs({ "C_Item.RequestLoadItemDataByID", "EquipPendingItem", "ProfessionsFrame_LoadUI",
            "PlaySound", "Getaway" }) do
            Check(not Keys.IsGetter(name), "keys: " .. name .. " is never called a second time")
        end
    end

    --------------------------------------------------------------------------------------
    -- A client that plays the game, with the addon and the recorder in it
    --------------------------------------------------------------------------------------

    local function Items()
        return {
            [900001] = { name = "Cracked Fang", quality = 0, level = 5, minLevel = 0, type = "Miscellaneous",
                subType = "Junk", stack = 20, price = 12, classID = 15, subClassID = 0 },
            [900002] = { name = "Sturdy Vest", quality = 2, level = 25, minLevel = 20, type = "Armor",
                subType = "Leather", stack = 1, equipLoc = "INVTYPE_CHEST", price = 900, classID = 4, subClassID = 2,
                bindType = 2,
                tooltip = { { text = "Binds when equipped", type = 20, bonding = 2 }, { text = "Chest", type = 21 } },
                appearance = { appearanceID = 5001, sourceID = 7001 } },
            -- A requirement the toon does not meet: a red line, which is a color with methods
            -- in the client and plain numbers in a recording.
            [900004] = { name = "Lofty Helm", quality = 2, level = 25, minLevel = 20, type = "Armor",
                subType = "Leather", stack = 1, equipLoc = "INVTYPE_HEAD", price = 1200, classID = 4, subClassID = 2,
                bindType = 2,
                tooltip = { { text = "Binds when equipped", type = 20, bonding = 2 }, { text = "Head", type = 21 },
                    { text = "Requires Engineering (300)", type = 43, r = 1, g = 0.125, b = 0.125 } },
                appearance = { appearanceID = 5002, sourceID = 7002 } },
            -- Two sources of one look, one of them collected: the same question asked about
            -- two sources, with two answers.
            [900005] = { name = "Plain Gloves", quality = 2, level = 25, minLevel = 20, type = "Armor",
                subType = "Leather", stack = 1, equipLoc = "INVTYPE_HAND", price = 700, classID = 4, subClassID = 2,
                bindType = 2,
                tooltip = { { text = "Binds when equipped", type = 20, bonding = 2 }, { text = "Hands", type = 21 } },
                appearance = { appearanceID = 5003, sourceID = 7005 } },
            [900006] = { name = "Old Gloves", quality = 1, level = 10, minLevel = 5, type = "Armor",
                subType = "Leather", stack = 1, equipLoc = "INVTYPE_HAND", price = 50, classID = 4, subClassID = 2,
                appearance = { appearanceID = 5003, sourceID = 7006, collected = true } },
            -- Trade goods with a price at the auction house.
            [900007] = { name = "Thick Hide", quality = 1, level = 20, minLevel = 0, type = "Tradeskill",
                subType = "Leather", stack = 20, price = 50, classID = 7, subClassID = 6 },
            -- Two foods in the bags. The addon judges one against the other, and keeps what it
            -- learned about each for the session.
            [900008] = { name = "Tough Jerky", quality = 1, level = 5, minLevel = 5, type = "Consumable",
                subType = "Food & Drink", stack = 20, price = 6, classID = 0, subClassID = 5,
                tooltip = { { text = "Use: Restores 61 health over 18 sec. Must remain seated while eating.", type = 0 } } },
            [900009] = { name = "Roasted Boar", quality = 1, level = 25, minLevel = 25, type = "Consumable",
                subType = "Food & Drink", stack = 20, price = 100, classID = 0, subClassID = 5,
                tooltip = { { text = "Use: Restores 874 health over 27 sec. Must remain seated while eating.", type = 0 } } },
            -- Named after the toon, so its link carries the toon's name into every question.
            [900003] = { name = "Zzyxa's Trophy", quality = 1, level = 1, minLevel = 0, type = "Miscellaneous",
                subType = "Junk", stack = 1, price = 1, classID = 15, subClassID = 0 },
        }
    end
    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 29 }

    local function StartGame(items)
        local game = H.StockGame(TOON, items)
        -- The client names a realm in two ways: UnitName returns a shorter one beside the name.
        game:Set("UnitName", function() return TOON.name, "Farshort" end)

        -- What the toon carries.
        local bag = { 900008, 900009 }
        game:Set("C_Container.GetContainerNumSlots", function(bagID) return bagID == 0 and #bag or 0 end)
        game:Set("C_Container.GetContainerItemID", function(bagID, slot) return bagID == 0 and bag[slot] or nil end)
        game:Set("C_Container.GetContainerItemLink", function(bagID, slot)
            return bagID == 0 and bag[slot] and game.Link(bag[slot]) or nil
        end)
        game:Set("C_Container.GetContainerItemInfo", function(bagID, slot)
            local id = bagID == 0 and bag[slot]
            if id then
                return { itemID = id, stackCount = 1, hyperlink = game.Link(id), isBound = false, quality = 1,
                    iconFileID = 134400 }
            end
        end)

        -- Two other addons, as the addon reads them. An auction addon with a price, and a
        -- listing history that it hands to a function it is given. A gear addon whose table
        -- of scales the addon walks through itself.
        game:Set("Auctionator.API.v1.GetAuctionPriceByItemLink", function(_, link)
            return link:find("item:900007:", 1, true) and 4000 or nil
        end)
        game:Set("Auctionator.API.v1.GetAuctionAgeByItemLink", function() return 0 end)
        game:Set("Auctionator.API.v1.RegisterForDBUpdate", function() end)
        game:Set("Auctionator.Utilities.DBKeyFromLink", function(link, callback)
            callback({ "key:" .. tostring(link:match("item:(%d+)")) })
        end)
        game:Set("Auctionator.Database.GetPriceHistory", function(_, key)
            if key ~= "key:900007" then
                return {}
            end
            local history = {}
            for day = 1, 6 do
                history[day] = { rawDay = 100 + day, minSeen = 3900 + day, available = 12 }
            end
            return history
        end)
        game:Set("PawnCommon.Scales", {
            Marksman = { LocalizedName = "Marksman", ClassID = 3, SpecID = 254, Values = { Agility = 1 } },
            Healer = { LocalizedName = "Healer", ClassID = 5, Values = { Intellect = 1 } },
        })
        game:Set("PawnCommon.ShowItemLevelUpgrades", false)

        -- A quest database of one quest, which takes the fang and which the toon has not
        -- picked up. The addon reads every quest of it once, over several frames, to know
        -- which quests take which item.
        local quests = {
            [7001] = { name = "Fangs for the Collector", objectives = { [3] = { { 900001 } } }, startedBy = { { 5 } },
                requiredLevel = 25, questLevel = 28 },
        }
        game:Set("LibQuestieDB.RequireContract", function() return true end)
        game:Set("LibQuestieDB.Quest.GetAllIds", function()
            game.readAllQuests = (game.readAllQuests or 0) + 1
            return { 7001 }
        end)
        game:Set("LibQuestieDB.Quest.Get", function(questID, field) return quests[questID] and quests[questID][field] end)
        game:Set("LibQuestieDB.Enum", { classKeys = { HUNTER = 4 }, raceMaskById = { [3] = 4 } })
        game:Set("C_QuestLog.IsOnQuest", function() return false end)
        game:Set("C_QuestLog.GetTitleForQuestID", function() return nil end)
        local client = H.Client.New({ flavor = "forever", provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        -- The settings a new install starts with, from the addon's own file.
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
        rawset(client.env, "CaerdonProfessionData", { ["Farrealm"] = { Zzyxa = {}, Otherone = { Mining = { rank = 5 } } } })
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)

        local wanted = { ["Core.lua"] = true, ["ApiNames.lua"] = true, ["RecordKeys.lua"] = true,
            ["Recorder.lua"] = true, ["Plan.lua"] = true }
        local T = H.LoadAddon(client, "CaerdonWardrobe_Tests", TESTS, function(relative) return not wanted[relative] end)
        client:Fire("ADDON_LOADED", "CaerdonWardrobe_Tests")
        client:Fire("PLAYER_LOGIN")
        return client, game, T
    end

    local client, game, T = StartGame(Items())
    Equal(#client.errors, 0, "start: the addon and the recorder load without an error")
    for _, message in ipairs(client.errors) do
        Check(false, "start: " .. message)
    end
    for name in pairs(H.Keys.BASICS) do
        Check(client.env[name] ~= nil, "basics: the mocked client has " .. name .. " of its own")
    end

    -- The same caches RefreshItems empties are the ones the recorder empties.
    do
        local core = H.ReadFile(H.addonDir .. "/CaerdonWardrobe.lua")
        local refresh = core:match("function CaerdonWardrobeMixin:RefreshItems%([%w_, ]*%)(.-)\nend")
        local recorder = H.ReadFile(TESTS .. "/Recorder.lua")
        local count = 0
        for call in (refresh or ""):gmatch("([%w_]+:Invalidate[%w_]*%(%))") do
            count = count + 1
            Check(recorder:find(call, 1, true) ~= nil, "caches: the recorder empties " .. call .. " as RefreshItems does")
        end
        Check(count >= 5, "caches: RefreshItems' list was found in CaerdonWardrobe.lua")
    end

    --------------------------------------------------------------------------------------
    -- Record
    --------------------------------------------------------------------------------------

    -- The client refuses a hook on some functions. One the addon names and the status never
    -- asks stands in for them here.
    Check(T.ApiNames.GetCursorInfo ~= nil, "refused: GetCursorInfo is a name the recorder would hook")
    game:Set("GetCursorInfo", function() return nil end)
    client.forbiddenHooks.GetCursorInfo = true

    -- The addon builds its index of the quest database after the first question, over the
    -- next frames. A recording is made in a session that has it.
    client.env.CaerdonQuestItems:GetItemQuestInfo(900001, "Cracked Fang")
    client:Tick(20)
    Equal(game.readAllQuests, 1, "quests: the addon read the quest database once to build its index")

    local untouched = game.names["C_Item.GetItemInfo"]
    local generation = client.env.CaerdonWardrobe.refreshGeneration
    T.RecordItems({ { itemID = 900001 }, { itemID = 900002 }, { itemID = 900003 }, { itemID = 123 },
        { itemID = 900004 }, { itemID = 900005 }, { itemID = 900007 }, { itemID = 900008 } })
    Check(client:TickUntil(function() return not T.IsBusy() end, 60), "record: the job ends")
    -- The caches were emptied behind the icons on screen; the job owes them one redraw.
    Equal(client.env.CaerdonWardrobe.refreshGeneration, generation + 1, "record: the job ends in one full refresh")
    Equal(#client.errors, 0, "record: no error reached the error handler")
    Equal(#T.db.errors, 0, "record: no error of the tests' own")
    for _, message in ipairs(client.errors) do
        Check(false, "record: " .. message)
    end
    for _, entry in ipairs(T.db.errors) do
        Check(false, "record: " .. tostring(entry.message))
    end

    local list = T.db.recordings.list
    Equal(#list, 7, "record: seven recordings, and none for an item the game does not have")
    local jerky = list[7] or {}
    Check(jerky.verdict and jerky.verdict.status == "sellable",
        "record: food the toon has outgrown, with better food in the bags, is for selling ("
            .. tostring(jerky.verdict and jerky.verdict.status) .. ")")
    local asked = false
    for key in pairs(jerky.calls and jerky.calls["C_Item.GetItemInfo"] or {}) do
        asked = asked or key:find("item:900009:", 1, true) ~= nil
    end
    Check(asked, "record: the addon asked about the other food again, although it had learned it this session")
    local fang, vest, helm, gloves, hide = list[1] or {}, list[2] or {}, list[4] or {}, list[5] or {}, list[6] or {}
    Check(hide.verdict and hide.verdict.status == "auctionGoods",
        "record: trade goods worth more at auction say so (" .. tostring(hide.verdict and hide.verdict.status) .. ")")
    local keyAnswers = hide.calls and hide.calls["Auctionator.Utilities.DBKeyFromLink"]
    local keyAnswer = keyAnswers and select(2, next(keyAnswers))
    Check(keyAnswer and keyAnswer[1].callback and keyAnswer[1].callback[1][1] == "key:900007",
        "record: an answer handed to a function is kept")
    Check(hide.methods and hide.methods["Auctionator.Database.GetPriceHistory"] == true,
        "record: a call made as a method of another addon's table is marked")
    Check(gloves.verdict and gloves.verdict.status ~= vest.verdict.status,
        "record: gloves whose look is known from another item are something else than the vest ("
            .. tostring(gloves.verdict and gloves.verdict.status) .. ")")
    Check(helm.verdict and helm.verdict.status ~= vest.verdict.status,
        "record: the helm's red line makes it something else than the vest (" .. tostring(helm.verdict
            and helm.verdict.status) .. ")")
    Check(fang.complete and vest.complete, "record: both went through in one call")
    Equal(fang.attempts, 1, "record: at the first try")
    Check(vest.verdict and vest.verdict.status == "own" and vest.verdict.binding == "BoE",
        "record: the vest is learnable and binds on equip (" .. tostring(vest.verdict and vest.verdict.status) .. ")")
    Check(fang.verdict and fang.verdict.ready == true and fang.verdict.status == "quest",
        "record: the fang is wanted by a quest the toon has not picked up (" .. tostring(fang.verdict
            and fang.verdict.status) .. ")")
    local seamAnswers = fang.calls and fang.calls["CaerdonQuestItems.GetIndexedQuests"]
    local seamAnswer = seamAnswers and seamAnswers[H.Keys.Args(1, 900001)]
    Check(seamAnswer and seamAnswer[1][1] and seamAnswer[1][1][7001] == "objective",
        "record: what the addon's index says about the item is kept, without the module as part of the question")
    Check(fang.calls and fang.calls["LibQuestieDB.Quest.Get"] ~= nil and fang.calls["LibQuestieDB.Quest.GetAllIds"] == nil,
        "record: with what the quest database says about that quest, and not the whole of it")
    Check(vest.calls and vest.calls["C_TransmogCollection.GetSourceInfo"] ~= nil, "record: the transmog answers are in it")
    Check(vest.calls and vest.calls["UnitLevel"] ~= nil, "record: so is the toon, asked for at the end of the run")
    Check(vest.calls and vest.calls["C_Item.GetItemQualityByID"] ~= nil or vest.calls["C_Item.GetItemInfo"] ~= nil,
        "record: and what Blizzard's own item code asked")
    Check(vest.calls and vest.calls["C_Item.RequestLoadItemDataByID"] == nil, "record: a request is not called a second time")
    Check(T.Recorder.HookCount() > 20, "record: the functions were hooked (" .. T.Recorder.HookCount() .. ")")
    Check(client.env.C_Item.GetItemInfo ~= untouched, "record: by a secure hook on the client's function")
    Check(type(vest.config) == "table" and vest.config.Icon ~= nil, "record: the settings are in the recording")

    local environment = T.db.recordings.environments[vest.environment] or {}
    Check(environment.values and environment.values["Enum.ItemClass.Questitem"] == 12, "environment: enum values by path")
    Check(environment.values and type(environment.values.LOCKED) == "string", "environment: global strings")
    Check(environment.absent and environment.absent.CanIMogIt == true, "environment: what the client lacks")
    local scales = environment.tables and environment.tables["PawnCommon.Scales"]
    Check(scales and scales.Marksman and scales.Marksman.ClassID == 3 and scales.Marksman.Values == nil,
        "environment: another addon's table the addon walks through, its keys and plain values one level down")
    Check(environment.values and environment.values["PawnCommon.ShowItemLevelUpgrades"] == false,
        "environment: a value that is false is a value, not something missing")
    Check(environment.kinds and environment.kinds.C_Item == "table", "environment: namespaces")
    Check(environment.kinds and environment.kinds["C_Item.GetItemInfo"] == "function", "environment: functions")
    Check(environment.saved and environment.saved.CaerdonProfessionData ~= nil, "environment: the saved data")
    Equal(fang.environment, vest.environment, "environment: one for the session")
    local _, refusedHooks = T.Recorder.HookCount()
    Equal(refusedHooks, 1, "refused: a function the client will not let be hooked is passed over")
    Check(environment.notHooked and tostring(environment.notHooked.GetCursorInfo):find("forbidden", 1, true) ~= nil,
        "refused: and listed in the environment with the client's words")
    local said = false
    for _, line in ipairs(client.printed) do
        said = said or line:find("1 the client would not let be hooked", 1, true) ~= nil
    end
    Check(said, "refused: the chat line says so")

    -- A second run of the same item is the same recording: nothing in it depends on the try.
    do
        local before = H.Serialize(vest.calls)
        T.RecordItems({ { itemID = 900002 } })
        client:TickUntil(function() return not T.IsBusy() end, 60)
        Equal(H.Serialize(list[#list].calls), before, "record: recording the vest again gives the same answers")
        table.remove(list)
    end

    --------------------------------------------------------------------------------------
    -- Through the saved variables, into fixtures, and back
    --------------------------------------------------------------------------------------

    local temp = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("\\", "/") .. "/caerdon-harness-" .. os.time()
    H.MakeDir(temp)
    local saved = temp .. "/CaerdonWardrobe_Tests.lua"
    H.WriteFile(saved, "CaerdonWardrobeTestsDB = " .. H.Serialize(T.db) .. "\n")
    local globals = H.ReadSavedVariables(saved)
    Check(globals and globals.CaerdonWardrobeTestsDB ~= nil, "import: the saved variables read back")

    local realFixtures = H.fixturesDir
    H.fixturesDir = temp .. "/fixtures"
    local log = {}
    local counts = H.Import(globals.CaerdonWardrobeTestsDB, { log = function(line) log[#log + 1] = line end,
        verbose = os.getenv("CAERDON_HARNESS_VERBOSE") ~= nil })
    Equal(counts.written, 6, "import: six fixtures written (" .. table.concat(log, " | ") .. ")")
    Equal(counts.rejected, 0, "import: none rejected")
    Equal(counts.unusable, 1, "import: the item whose link holds the toon's name is refused")

    local fixtures = H.ListFixtures()
    Equal(#fixtures, 6, "fixtures: six are listed")
    local byItem = {}
    for _, fixture in ipairs(fixtures) do
        local text = H.ReadFile(fixture.path)
        Check(not text:find("Zzyxa", 1, true) and not text:find("Farrealm", 1, true)
            and not text:find("Farshort", 1, true), "fixtures: " .. fixture.name .. " holds no toon or realm name")
        local recording, recordedEnvironment = H.LoadFixture(fixture.path)
        Check(recording ~= nil and recordedEnvironment ~= nil, "fixtures: " .. fixture.name .. " loads with its environment")
        if recording then
            byItem[recording.itemID] = { recording = recording, environment = recordedEnvironment }
            local environmentText = H.ReadFile(fixture.path:gsub("[^/]+$", "") .. recording.environment .. ".lua")
            Check(not environmentText:find("Zzyxa", 1, true) and not environmentText:find("Farrealm", 1, true)
                and not environmentText:find("Farshort", 1, true) and not environmentText:find("Otherone", 1, true),
                "fixtures: nor does its environment, other toons and the realm's second name included")
            Check(recordedEnvironment.calls and recordedEnvironment.calls.UnitLevel ~= nil and recording.calls.UnitLevel == nil,
                "fixtures: an answer every recording agrees on is in the environment's file, once")
            Check(recording.calls["C_TooltipInfo.GetHyperlink"] ~= nil, "fixtures: an item's own answers stay with it")
            Check(environmentText:find("Toon2", 1, true) ~= nil, "fixtures: another toon's saved data is kept under a stand-in name")
            local result = H.Replay(recordedEnvironment, recording)
            Equal(result.state, "pass", "replay: " .. fixture.name .. " (" .. table.concat(H.DescribeReplay(result), " | ") .. ")")
            Equal(result.unansweredInVerdict, 0, "replay: " .. fixture.name .. " had every answer")
            Equal(#result.unknown, 0, "replay: " .. fixture.name .. " read no name the recording lacks ("
                .. table.concat(result.unknown, ", ") .. ")")
            Check(result.answered > 5, "replay: " .. fixture.name .. " was answered from the recording")
        end
    end

    -- Importing again changes nothing; a different recording of the same item needs --replace.
    do
        local again = H.Import(globals.CaerdonWardrobeTestsDB, { log = function() end })
        Equal(again.same, 6, "import: a second import finds them as they are")
        local changed = H.DeepCopy(globals.CaerdonWardrobeTestsDB)
        changed.recordings.list[2].note = "another take"
        local third = H.Import(changed, { log = function() end })
        Equal(third.exists, 1, "import: another recording of an item does not overwrite the first")
        local fourth = H.Import(changed, { log = function() end, replace = true })
        Equal(fourth.written, 1, "import: unless asked to")
    end

    --------------------------------------------------------------------------------------
    -- Planted faults
    --------------------------------------------------------------------------------------

    local vestFixture = byItem[900002]
    if vestFixture then
        -- 1. The addon decides differently from the same answers. Planted the cheap way round:
        --    the recorded verdict is changed, which is the same disagreement.
        local recording = H.DeepCopy(vestFixture.recording)
        recording.verdict.status = "other"
        local result = H.Replay(vestFixture.environment, recording)
        Equal(result.state, "differs", "fault: another verdict from the same answers is a difference")

        -- 2. The client's answer changes what the addon decides: a collected source.
        recording = H.DeepCopy(vestFixture.recording)
        for _, answers in pairs(recording.calls["C_TransmogCollection.GetSourceInfo"]) do
            for _, answer in ipairs(answers) do
                answer[1].isCollected = true
            end
        end
        for _, name in ipairs({ "C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance",
            "C_TransmogCollection.PlayerHasTransmogByItemInfo", "C_TransmogCollection.PlayerKnowsSource" }) do
            for _, answers in pairs(recording.calls[name] or {}) do
                for _, answer in ipairs(answers) do
                    answer[1] = true
                end
            end
        end
        result = H.Replay(vestFixture.environment, recording)
        Check(result.state == "differs" and result.status ~= "own",
            "fault: the replay follows the answers, a collected source is not learnable (" .. tostring(result.status) .. ")")

        -- 3. The code asks something the recording does not hold.
        recording = H.DeepCopy(vestFixture.recording)
        recording.calls["C_TooltipInfo.GetHyperlink"] = nil
        result = H.Replay(vestFixture.environment, recording)
        Check(result.unansweredInVerdict > 0, "fault: a question without an answer is counted")
        Check(result.state == "stale" or result.state == "pass" or result.state == "error",
            "fault: and never passes for a difference in the addon (" .. result.state .. ")")
        local described = table.concat(H.DescribeReplay(result), "\n")
        Check(described:find("C_TooltipInfo.GetHyperlink", 1, true) ~= nil, "fault: the report names the question")

        -- 4. The code reads a name the environment does not have.
        local environment = H.DeepCopy(vestFixture.environment)
        environment.values.LOCKED, environment.values.ITEM_SOULBOUND = nil, nil
        result = H.Replay(environment, vestFixture.recording)
        local fromMirror = table.concat(result.fromMirror or {}, ",")
        Check(fromMirror:find("ITEM_SOULBOUND", 1, true) ~= nil or fromMirror:find("LOCKED", 1, true) ~= nil,
            "fault: a string the recording lacks comes from the listings mirror and is counted (" .. fromMirror .. ")")

        -- The quest verdict came out of the replay through the seam, with the addon's own
        -- judging on the recorded facts, and without the quest database being read again.
        local fangFixture = byItem[900001]
        do
            local replayed = H.Replay(fangFixture.environment, fangFixture.recording)
            Equal(replayed.status, "quest", "seam: the quest verdict is reproduced")
            Equal(table.concat(replayed.provider.seams, ","),
                "CaerdonQuestItems.GetIndexedQuests,CaerdonQuestItems.GetQuestieHiddenReason",
                "seam: both of the quest module's read functions were answered from the recording")
            local enum = replayed.client.env.LibQuestieDB.Enum
            Check(enum.classKeys.HUNTER == 4 and enum.raceMaskById[3] == 4,
                "seam: the quest database's tables of race and class flags are there as recorded")
        end
        recording = H.DeepCopy(fangFixture.recording)
        recording.calls["CaerdonQuestItems.GetIndexedQuests"] = nil
        result = H.Replay(fangFixture.environment, recording)
        Check(result.state ~= "pass" and result.status ~= "quest",
            "fault: without the seam's answer the quest verdict does not come out (" .. tostring(result.state) .. ")")
        recording = H.DeepCopy(fangFixture.recording)
        for _, answers in pairs(recording.calls["LibQuestieDB.Quest.Get"]) do
            for _, answer in ipairs(answers) do
                if answer[1] == 25 then
                    answer[1] = 60 -- the quest's required level
                end
            end
        end
        result = H.Replay(fangFixture.environment, recording)
        Check(result.state == "differs" and result.status ~= "quest",
            "fault: the addon's judging runs for real: a quest far above the toon's level does not count ("
                .. tostring(result.status) .. ")")

        -- 5. The history an auction addon hands to a function decides: without it the
        --    replay must not come out the same by luck, it has to say what was missing.
        local hideFixture = byItem[900007]
        local scales
        do
            local replayed = H.Replay(hideFixture.environment, hideFixture.recording)
            scales = replayed.client.env.PawnCommon.Scales
        end
        local seen = {}
        for scaleName, scale in pairs(scales) do
            seen[#seen + 1] = scaleName .. "=" .. tostring(scale.LocalizedName)
        end
        table.sort(seen)
        Equal(table.concat(seen, ","), "Healer=Healer,Marksman=Marksman",
            "replay: another addon's table can be walked through as recorded")
        recording = H.DeepCopy(hideFixture.recording)
        recording.calls["Auctionator.Utilities.DBKeyFromLink"] = nil
        result = H.Replay(hideFixture.environment, recording)
        Check(result.unansweredInVerdict > 0, "fault: a lost callback answer is a question without an answer")

        -- 6. An error in the addon's code is an error, not a difference.
        environment = H.DeepCopy(vestFixture.environment)
        environment.kinds["C_Item.GetItemInfo"] = nil
        environment.absent["C_Item.GetItemInfo"] = true
        recording = H.DeepCopy(vestFixture.recording)
        recording.calls["C_Item.GetItemInfo"] = nil
        result = H.Replay(environment, recording)
        Equal(result.state, "error", "fault: a function that is gone raises an error")
    else
        Check(false, "fault: the vest's fixture is there to plant faults in")
    end

    H.fixturesDir = realFixtures

    -- Leave nothing behind, unless the files are wanted for a look.
    if os.getenv("CAERDON_HARNESS_KEEP") then
        print("        the scenario's files are kept in " .. temp)
        return
    end
    for _, file in ipairs(H.ListDir(temp .. "/fixtures/forever")) do
        os.remove(temp .. "/fixtures/forever/" .. file)
    end
    os.remove(saved)
    for _, dir in ipairs({ "/fixtures/forever", "/fixtures", "" }) do
        os.remove(temp .. dir) -- removes an empty folder where the system allows it
        if package.config:sub(1, 1) == "\\" then
            os.execute(('rmdir "%s" 2>NUL'):format((temp .. dir):gsub("/", "\\")))
        end
    end
end
