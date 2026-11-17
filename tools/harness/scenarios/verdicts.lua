-- The test addon's verdict tests and its canary contract, run against a hand-made game.
--
-- Real code: the addon's item side, and of the test addon Core, Runner, Facts, Contracts,
-- Verdicts, VerdictCases and Plan. Hand-made: the game. So this proves that the tests judge
-- as they say they do (a fitting item passes, a wrong status fails, the same failure with the
-- same facts is a regression, a changed reading fails the canary), and nothing about what a
-- client answers or whether an expectation is right.

return function(H, S)
    local Check, Equal = S.Check, S.Equal
    local TESTS = H.addonDir .. "/CaerdonWardrobe_Tests"

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 29 }

    local function Armor(name, slot, appearance, more)
        local item = { name = name, quality = 2, level = 25, minLevel = 20, type = "Armor", subType = "Leather",
            stack = 1, equipLoc = slot, price = 500, classID = 4, subClassID = 2, bindType = 2,
            tooltip = { { text = "Binds when equipped", type = 20, bonding = 2 } }, appearance = appearance }
        for key, value in pairs(more or {}) do
            item[key] = value
        end
        return item
    end

    local items = {
        -- The canary's item, and the three the Forever "collected" test names: learned.
        [6125] = Armor("Brawler's Harness", "INVTYPE_BODY", { appearanceID = 1979, sourceID = 2260 },
            { subType = "Miscellaneous", subClassID = 0, minLevel = 0, level = 10 }),
        [2969] = Armor("Spellbinder Vest", "INVTYPE_CHEST", { appearanceID = 5201, sourceID = 7201, collected = true }),
        [6550] = Armor("Soldier's Wristguards", "INVTYPE_WRIST", { appearanceID = 5202, sourceID = 7202, collected = true }),
        [5212] = Armor("Blazing Wand", "INVTYPE_RANGEDRIGHT", { appearanceID = 5203, sourceID = 7203, collected = true },
            { type = "Weapon", subType = "Wands", classID = 2, subClassID = 19 }),
        -- A new look, a look known from another item, and a piece above the toon's level.
        [910001] = Armor("Plain Vest", "INVTYPE_CHEST", { appearanceID = 5101, sourceID = 7101 }),
        [910002] = Armor("Twin Gloves", "INVTYPE_HAND", { appearanceID = 5102, sourceID = 7102 }),
        [910003] = Armor("Elder Gloves", "INVTYPE_HAND", { appearanceID = 5102, sourceID = 7103, collected = true }),
        [910006] = Armor("Lofty Vest", "INVTYPE_CHEST", { appearanceID = 5106, sourceID = 7106 }, { minLevel = 40,
            tooltip = { { text = "Binds when equipped", type = 20, bonding = 2 },
                { text = "Requires Level 40", type = 0, r = 1, g = 0.125, b = 0.125 } } }),
    }

    local buildNumber = "70938"
    local game = H.StockGame(TOON, items)
    game:Set("GetBuildInfo", function() return "1.60.1", buildNumber, "Nov 1 2026", 16001 end)
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

    local wanted = { ["Core.lua"] = true, ["Runner.lua"] = true, ["Facts.lua"] = true, ["Contracts.lua"] = true,
        ["Verdicts.lua"] = true, ["VerdictCases.lua"] = true, ["Plan.lua"] = true }
    local T = H.LoadAddon(client, "CaerdonWardrobe_Tests", TESTS, function(relative) return not wanted[relative] end)

    -- Tests of the scenario's own, registered as a file of the test addon would: the stock
    -- game answers "the toon can collect it", which is the retail tests' kind of shape, and
    -- those do not run in a Forever client.
    local LEARN = { "own", "ownPlus", "other", "otherPlus", "otherNoLoot", "lowSkill", "lowSkillPlus" }
    local function Scenario(id, shape, pool, expect)
        T.Verdict({ id = id, version = 1, title = id, facts = "appearance", shape = shape,
            kinds = { { name = "hunter", toon = { class = "HUNTER" }, pool = pool, expect = expect } }, confirmed = false })
    end
    Scenario("scenario.learnable", { sourceCollected = false, playerCanCollect = true, lookKnownElsewhere = false,
        levelMet = true }, { 910001, 910002, 910006 }, { status = "own" })
    Scenario("scenario.belowLevel", { sourceCollected = false, playerCanCollect = true, lookKnownElsewhere = false,
        levelMet = false }, { 910001, 910006 }, { status = "lowSkill" })
    Scenario("scenario.knownLook", { sourceCollected = false, playerCanCollect = true, lookKnownUsable = true,
        sameLookShown = true }, { 910002 }, { status = "ownPlus" })
    Scenario("scenario.knownLookHidden", { sourceCollected = false, playerCanCollect = true, lookKnownUsable = true,
        sameLookShown = false }, { 910002 }, { notStatus = LEARN })
    -- An expectation that is wrong on purpose. The toon wears nothing, so a learned piece is
    -- an upgrade to it: the status this "must not" be.
    Scenario("scenario.wrong", { sourceCollected = true }, { 910003 }, { notStatus = { "collected", "upgrade" } })

    client:Fire("ADDON_LOADED", "CaerdonWardrobe_Tests")
    client:Fire("PLAYER_LOGIN")

    local function NoErrors(label)
        Equal(#client.errors, 0, label .. ": no error reached the error handler")
        for _, message in ipairs(client.errors) do
            Check(false, label .. ": " .. message)
        end
        Equal(#T.db.errors, 0, label .. ": no error of the tests' own")
        for _, entry in ipairs(T.db.errors) do
            Check(false, label .. ": " .. tostring(entry.message))
        end
    end
    NoErrors("start")

    local function Run(options)
        T.RunTests(options)
        Check(client:TickUntil(function() return not T.IsBusy() end, 120), "run: the job ends")
    end

    --------------------------------------------------------------------------------------
    -- Judging, with no client in it
    --------------------------------------------------------------------------------------

    do
        local facts = { sourceCollected = true }
        local none = { notStatus = LEARN }
        Equal(T.JudgeCase(facts, nil, { status = "sellable" }, none, nil, 1).result, "pass",
            "judge: a status that is none of the wrong ones passes")
        Equal(T.JudgeCase(facts, nil, { status = "" }, none, nil, 1).result, "pass", "judge: so does no status at all")
        local failed = T.JudgeCase(facts, nil, { status = "ownPlus" }, none, nil, 1)
        Equal(failed.result, "fail", "judge: one of the wrong ones fails")
        Check(tostring(failed.note):find("expected none of own, ownPlus", 1, true) ~= nil
            and tostring(failed.note):find("got ownPlus", 1, true) ~= nil, "judge: and says what was expected ("
            .. tostring(failed.note) .. ")")
        local prior = { result = "pass", v = 1, facts = { sourceCollected = true } }
        Equal(T.JudgeCase(facts, nil, { status = "own" }, none, prior, 1).result, "regression",
            "judge: failing after a pass with the same facts is a regression")
        Equal(T.JudgeCase({ sourceCollected = true, toonLevel = 30 }, nil, { status = "own" }, none, prior, 1).result,
            "fail", "judge: with other facts it is a failure that says what moved")
        Equal(T.JudgeCase(facts, nil, { status = "own", binding = "BoE" }, { status = "own", binding = "BoA" }, nil, 1).result,
            "fail", "judge: an expected status with another binding text fails")
        Equal(T.DescribeExpectation({ status = "own" }), "own", "judge: an expected status in words")
        Check(not H.Guards.pcall(T.Verdict, { id = "scenario.empty", version = 1, shape = {},
            kinds = { { name = "x", expect = {} } } }), "judge: a kind of toon without an expectation is refused")
    end

    --------------------------------------------------------------------------------------
    -- The verdict tests, through the runner
    --------------------------------------------------------------------------------------

    Run({ kind = "verdict" })
    NoErrors("verdicts")

    local function Kind(id, kind)
        return (T.db.verdicts[id] or {})[kind or "hunter"] or { cases = {} }
    end
    local function Case(id, itemID, kind)
        return Kind(id, kind).cases[itemID] or {}
    end

    -- The Forever tests that came from the old suite.
    do
        local record = Kind("forever.appearance.collected")
        Equal(record.state, "pass", "collected: learned sources leave nothing to learn")
        for _, itemID in ipairs({ 2969, 6550, 5212 }) do
            Equal(Case("forever.appearance.collected", itemID).result, "pass", "collected: item " .. itemID)
        end
        Check(T.db.verdicts["forever.appearance.collected"].rogue == nil, "collected: a kind the toon is not does not run")
        Equal(Kind("forever.appearance.knownLook").state, "uncovered", "known look: a test without items is uncovered")
        Equal(Kind("forever.appearance.validSourceNotCollectable", "hunter below 40").state, "uncovered",
            "forever: a pool the account has learned is uncovered, not failed")
        Equal(Case("forever.appearance.validSourceNotCollectable", 2969, "hunter below 40").result, "unfit",
            "forever: and its items are unfit")
        Check(T.db.verdicts["retail.appearance.learnable"] == nil, "retail: its tests do not run in this client")
    end

    -- The facts the old expectations needed, read by the real reader.
    do
        local plain, twin, lofty = Case("scenario.learnable", 910001), Case("scenario.learnable", 910002),
            Case("scenario.learnable", 910006)
        Equal(plain.result, "pass", "facts: a new look the toon can collect is own")
        Equal(plain.facts and plain.facts.levelMet, true, "facts: the toon has the level")
        Equal(plain.facts and plain.facts.lookKnownUsable, false, "facts: the look is not known")
        Equal(plain.facts and plain.facts.sameLookShown, false, "facts: the setting of a new install is in the facts")
        Equal(twin.result, "unfit", "facts: a look known from another item is not a case of 'new look'")
        Equal(twin.facts and twin.facts.lookKnownElsewhere, true, "facts: known from another item")
        Equal(twin.facts and twin.facts.lookKnownUsable, true, "facts: one this toon can use")
        Equal(twin.facts and twin.facts.lookKnownUnusable, false, "facts: and none it cannot")
        Equal(lofty.result, "unfit", "facts: a piece above the toon's level is not a case of 'has the level'")
        Equal(lofty.facts and lofty.facts.levelMet, false, "facts: the level is not met")
        Equal(Case("scenario.belowLevel", 910006).result, "pass", "level: below the item's level it is lowSkill")
        Equal(Case("scenario.belowLevel", 910001).result, "unfit", "level: and the plain vest is no case of that")

        Equal(Kind("scenario.knownLook").state, "uncovered", "known look: with the setting off the Plus test has no case")
        Check(tostring(Case("scenario.knownLook", 910002).note):find("sameLookShown is false", 1, true) ~= nil,
            "known look: and says the setting is why (" .. tostring(Case("scenario.knownLook", 910002).note) .. ")")
        Equal(Case("scenario.knownLookHidden", 910002).result, "pass", "known look: hidden, it is nothing to learn")

        local wrong = Case("scenario.wrong", 910003)
        Equal(wrong.result, "fail", "wrong: an expectation the addon does not meet fails")
        Check(tostring(wrong.note):find("expected none of collected, upgrade, got upgrade", 1, true) ~= nil,
            "wrong: with the expectation in words (" .. tostring(wrong.note) .. ")")
        local state, message = T.VerdictStatus(T.GetTest("scenario.wrong"), T.GetToon())
        Equal(state, "fail", "wrong: the status listing says fail")
        Check(tostring(message):find("item 910003 fail", 1, true) ~= nil, "wrong: and names the item")
    end

    -- A second run: the failure repeats with the same facts, which is a regression only after
    -- a pass, so it stays a failure. Then the setting is switched on, as a player would.
    do
        Run({ kind = "verdict" })
        Equal(Case("scenario.wrong", 910003).result, "fail", "again: a failure that never passed is no regression")

        client.env.CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem = true
        client.env.CaerdonWardrobe:RefreshItems()
        client:Tick(20)
        Run({ kind = "verdict" })
        Equal(Case("scenario.knownLook", 910002).result, "pass", "setting on: the known look is ownPlus")
        Equal(Case("scenario.knownLook", 910002).status, "ownPlus", "setting on: by its status")
        local hidden = Case("scenario.knownLookHidden", 910002)
        Equal(hidden.result, "retired", "setting on: the hidden case no longer fits and is retired, not failed")
        Check(hidden.moved and hidden.moved.sameLookShown and hidden.moved.sameLookShown.after == true,
            "setting on: with the fact that moved")
        NoErrors("setting on")
    end

    -- A quest takes the plain vest: it shows the quest icon, which is no failure of the rule
    -- for a look to learn. The quest module's answer is put in its place; the item code and
    -- the tests' reader are the real ones.
    do
        local quests = client.env.CaerdonQuestItems
        local real = quests.GetItemQuestInfo
        quests.GetItemQuestInfo = function(_, itemID)
            return itemID == 910001 and { hasQuestValue = true, isActive = false, isUpcoming = true, quests = {} } or nil
        end
        client.env.CaerdonWardrobe:RefreshItems()
        client:Tick(20)
        Run({ kind = "verdict" })
        local taken = Case("scenario.learnable", 910001)
        Equal(taken.result, "retired", "quest: a piece a quest takes is retired from the look-to-learn test, not failed")
        Check(tostring(taken.note):find("questTakes is true", 1, true) ~= nil,
            "quest: and says the quest is why (" .. tostring(taken.note) .. ")")
        Equal(Case("scenario.belowLevel", 910006).result, "pass", "quest: a piece no quest takes is judged as before")

        quests.GetItemQuestInfo = real
        client.env.CaerdonWardrobe:RefreshItems()
        client:Tick(20)
        Run({ kind = "verdict" })
        Equal(Case("scenario.learnable", 910001).result, "pass", "quest: the quest gone, the vest is a case again")
        NoErrors("quest")
    end

    --------------------------------------------------------------------------------------
    -- The canary
    --------------------------------------------------------------------------------------

    local function Canary()
        local build = T.GetClient().build
        return (T.db.contracts[build] or {})["canary.knownItem"] or {}
    end
    -- A patch later: another build, and the clock has moved on (results carry their time).
    local function NextBuild(number)
        buildNumber = number
        T.client = nil
        client:Tick(1, 60)
    end

    do
        Run({ match = "canary.knownItem", force = true })
        local first = Canary()
        Equal(first.status, "info", "canary: a first reading is an answer, not a pass (" .. tostring(first.message) .. ")")
        local reading = first.detail and first.detail.reading or {}
        Equal(reading.name, "Brawler's Harness", "canary: the item's name is read")
        Equal(reading.equipLoc, "INVTYPE_BODY", "canary: its slot")
        Equal(reading.appearanceID, 1979, "canary: its look")
        Equal(reading["source.itemID"], 6125, "canary: the source's item")
        Equal(#(first.detail.unlikeTheOldTest or {}), 0, "canary: this game answers as the old test expected ("
            .. table.concat(first.detail.unlikeTheOldTest or {}, "; ") .. ")")
        Check(type(first.detail.sourceKeys) == "string" and first.detail.sourceKeys:find("visualID", 1, true) ~= nil,
            "canary: the source's fields are listed")

        -- The saved variables keep results as text; the comparison must hold through that.
        T.db.contracts = H.ReadSavedVariables((function()
            local temp = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("\\", "/") .. "/caerdon-harness-canary-"
                .. os.time() .. ".lua"
            H.WriteFile(temp, "Saved = " .. H.Serialize(T.db.contracts) .. "\n")
            return temp
        end)()).Saved

        NextBuild("70999")
        Run({ match = "canary.knownItem", force = true })
        Equal(Canary().status, "pass", "canary: the same reading in the next build passes (" .. tostring(Canary().message) .. ")")
        Equal(Canary().detail and Canary().detail.comparedWith, "1.60.1.70938", "canary: compared with the build before")

        -- A patch changes the item.
        items[6125].quality = 1
        items[6125].appearance.appearanceID = 1980
        NextBuild("71000")
        Run({ match = "canary.knownItem", force = true })
        local changed = Canary()
        Equal(changed.status, "fail", "canary: a changed reading fails")
        Equal(changed.detail and changed.detail.comparedWith, "1.60.1.70999", "canary: against the newest earlier build")
        local said = table.concat(changed.failures or {}, " | ")
        Check(said:find("quality went from 2 to 1", 1, true) ~= nil, "canary: it names the quality (" .. said .. ")")
        Check(said:find("appearanceID went from 1979 to 1980", 1, true) ~= nil, "canary: and the look")
        Check(#(changed.detail.unlikeTheOldTest or {}) >= 2, "canary: the old test's values are compared for the reader")

        -- A client without the item.
        items[6125] = nil
        NextBuild("71001")
        Run({ match = "canary.knownItem", force = true })
        Equal(Canary().status, "skip", "canary: a client without the item skips (" .. tostring(Canary().message) .. ")")

        -- The run's errors: a failed contract is no error of the tests' own.
        Equal(#client.errors, 0, "canary: no error reached the error handler")
        Equal(#T.db.errors, 0, "canary: no error of the tests' own")
        for _, entry in ipairs(T.db.errors) do
            Check(false, "canary: " .. tostring(entry.message))
        end
    end
end
