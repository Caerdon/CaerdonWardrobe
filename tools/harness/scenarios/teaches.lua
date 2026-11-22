-- What teaches what: the test addon's walk over the items of the classes Consumable and
-- Recipe (/cwtest teaches, CaerdonWardrobe_Tests/Teaches.lua).
--
-- The walk is a measurement, so what is checked here is that it counts what is there: each
-- item in the shape its tooltip and the client's answers give it, the shapes that were asked
-- about kept apart, an item the game has not counted as not loaded, a tooltip that is late
-- read on the second try, a run that stops for time gone on from where it stopped without
-- counting anything twice.
--
-- The items are hand-made, their lines after the recorded recipes' (a teaching line of type
-- 38 with a spellID, a skill requirement line of type 43); the spells are invented.
--
-- Real code: the addon (for what it takes an item for), the test addon's core and the walk,
-- Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 33 }

    local LEARN_LINE, REQUIREMENT_LINE = 38, 43
    local CONSUMABLE, RECIPE, MISC = 0, 9, 15
    local FIRST = 991000
    local PATTERN, PATTERN_TWO, BARE_PATTERN, BOOK = 991001, 991002, 991003, 991004
    local SCHEMATIC, SCROLL, FAKE = 991005, 991006, 991007
    local POTION_ONE, POTION_TWO, POTION_THREE = 991008, 991009, 991010
    local GHOST, MOUNT, LATE, NEVER, RAISES, NO_SPELL = 991011, 991012, 991013, 991014, 991015, 991016
    -- A recipe whose tooltip has two teaching lines: the made item's own, then the recipe's.
    local TWO_LINES = 991017
    local MADE_ITEM_SPELL = 70098
    -- What a star on a class book or a rune would rest on: a rune of another class with a
    -- level the toon has not, and a book of the toon's own class that it has learned.
    local RUNE, KNOWN_BOOK = 991018, 991019
    -- The spell an item teaches is its ID less 921000; these are recipes of a trade skill.
    local function SpellOf(itemID) return itemID - 921000 end
    local RECIPE_SPELLS = { [SpellOf(PATTERN)] = "Blue Shirt", [SpellOf(PATTERN_TWO)] = "Red Shirt",
        [SpellOf(BARE_PATTERN)] = "Grey Shirt", [SpellOf(SCHEMATIC)] = "Test Gadget", [SpellOf(SCROLL)] = "Odd Thing",
        [SpellOf(RAISES)] = "Torn Shirt", [SpellOf(TWO_LINES)] = "Test Pet Box" }
    local BOOK_SPELL = SpellOf(BOOK)

    local function Item(name, classID, subType, teaches, skillLine, spellless)
        local tooltip = {}
        if teaches then
            tooltip[#tooltip + 1] = { text = "Use: Teaches you how to make something.", type = LEARN_LINE }
        end
        if skillLine then
            tooltip[#tooltip + 1] = { text = skillLine, type = REQUIREMENT_LINE }
        end
        return { name = name, quality = 1, level = 20, minLevel = 0, type = classID == RECIPE and "Recipe" or "Consumable",
            subType = subType, stack = 1, price = 100, classID = classID, subClassID = 1, bindType = 0, tooltip = tooltip,
            teaches = teaches, spellless = spellless }
    end

    local function Start(flavor)
        local items = {
            [PATTERN] = Item("Pattern: Blue Shirt", RECIPE, "Tailoring", true, "Requires Tailoring (50)"),
            [PATTERN_TWO] = Item("Pattern: Red Shirt", RECIPE, "Tailoring", true, "Requires Tailoring (60)"),
            [BARE_PATTERN] = Item("Pattern: Grey Shirt", RECIPE, "Tailoring", true, nil),
            [BOOK] = Item("Tome of Tests", RECIPE, "Book", true, nil),
            [SCHEMATIC] = Item("Schematic: Test Gadget", CONSUMABLE, "Other", true, "Requires Engineering (75)"),
            [SCROLL] = Item("Odd Scroll", CONSUMABLE, "Other", true, nil),
            [FAKE] = Item("Recipe: Nothing", CONSUMABLE, "Other", false, nil),
            [POTION_ONE] = Item("Potion One", CONSUMABLE, "Potion", false, nil),
            [POTION_TWO] = Item("Potion Two", CONSUMABLE, "Potion", false, nil),
            [POTION_THREE] = Item("Potion Three", CONSUMABLE, "Potion", false, nil),
            [GHOST] = Item("Ghost", CONSUMABLE, "Potion", false, nil),
            [MOUNT] = { name = "Reins of the Test", quality = 3, level = 20, minLevel = 20, type = "Miscellaneous",
                subType = "Mount", stack = 1, price = 100, classID = MISC, subClassID = 5, bindType = 1,
                tooltip = { { text = "Use: Teaches you how to summon this mount.", type = LEARN_LINE, spellID = 70099 } } },
            [LATE] = Item("Late Potion", CONSUMABLE, "Potion", false, nil),
            [NEVER] = Item("Never Potion", CONSUMABLE, "Potion", false, nil),
            [RAISES] = Item("Pattern: Torn Shirt", RECIPE, "Tailoring", true, "Requires Tailoring (70)"),
            [NO_SPELL] = Item("Pattern: Blank Shirt", RECIPE, "Tailoring", true, "Requires Tailoring (80)", true),
        }
        items[TWO_LINES] = Item("Schematic: Test Pet", RECIPE, "Engineering", true, "Requires Engineering (90)")
        table.insert(items[TWO_LINES].tooltip, 1,
            { text = "Use: Teaches you how to summon this companion.", type = LEARN_LINE, spellID = MADE_ITEM_SPELL })
        items[RUNE] = Item("Rune of Tests", CONSUMABLE, "Other", true, nil)
        table.insert(items[RUNE].tooltip, 1, { text = "Classes: Mage", type = REQUIREMENT_LINE, class = true, usable = false })
        table.insert(items[RUNE].tooltip, 2, { text = "Requires Level 40", type = REQUIREMENT_LINE, level = true, usable = false })
        items[KNOWN_BOOK] = Item("Guide: Testing Shot", RECIPE, "Book", true, nil)
        table.insert(items[KNOWN_BOOK].tooltip, 1, { text = "Classes: Hunter", type = REQUIREMENT_LINE, class = true, usable = true })
        table.insert(items[KNOWN_BOOK].tooltip, { text = "Already known", type = REQUIREMENT_LINE, known = true, usable = false })
        for itemID, item in pairs(items) do
            if item.teaches and (itemID == RUNE or itemID == KNOWN_BOOK) then
                for _, line in ipairs(item.tooltip) do
                    if line.type == LEARN_LINE then
                        line.spellID = SpellOf(itemID)
                    end
                end
            elseif item.teaches and itemID == TWO_LINES then
                item.tooltip[2].spellID = SpellOf(itemID)
            elseif item.teaches and not item.spellless then
                item.tooltip[1].spellID = SpellOf(itemID)
            end
        end

        local game = H.StockGame(TOON, items)
        game:Set("C_Spell.GetSpellName", function(spell) return RECIPE_SPELLS[spell] or (spell == BOOK_SPELL and "Testing") or nil end)
        -- The client answers with a recipe's info for a spell that is no recipe as well (seen
        -- on retail for a potion's own effect).
        game:Set("C_TradeSkillUI.GetRecipeInfo", function(spell)
            local name = RECIPE_SPELLS[spell] or (spell == BOOK_SPELL and "Testing")
            return name and { name = name, learned = false, recipeID = spell } or nil
        end)
        game:Set("C_SpellBook.IsSpellKnown", function(spell) return spell == SpellOf(KNOWN_BOOK) end)
        game:Set("C_TradeSkillUI.GetTradeSkillLineForRecipe", function(spell)
            if RECIPE_SPELLS[spell] then
                return 197, "Tailoring", 197
            end
        end)
        game:Set("C_TradeSkillUI.IsRecipeProfessionLearned", function(spell)
            if spell == SpellOf(RAISES) then
                error("no such recipe")
            end
            return RECIPE_SPELLS[spell] ~= nil and spell ~= SpellOf(SCHEMATIC)
        end)

        -- An item's data is there once it was asked for; the ghost's never comes.
        local cached, asks = {}, {}
        game:Set("C_Item.IsItemDataCachedByID", function(id) return cached[id] == true end)
        game:Set("C_Item.RequestLoadItemDataByID", function(id)
            asks[id] = (asks[id] or 0) + 1
            if items[id] and id ~= GHOST then
                game.client.env.C_Timer.After(0, function() cached[id] = true end)
            end
        end)
        -- A tooltip that is the client's "retrieving" one the first time, and one that stays so.
        local hyperlink, reads = game.names["C_TooltipInfo.GetHyperlink"], {}
        game:Set("C_TooltipInfo.GetHyperlink", function(link)
            local itemID = tonumber(tostring(link):match("item:(%d+)"))
            reads[itemID] = (reads[itemID] or 0) + 1
            if itemID == NEVER or (itemID == LATE and reads[itemID] == 1) then
                return { type = 0, id = itemID, lines = { { type = 0, leftText = game.client.env.RETRIEVING_ITEM_INFO } } }
            end
            return hyperlink(link)
        end)

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
        Equal(#client.errors, 0, flavor .. ": no error reached the error handler at the start (" .. tostring(client.errors[1]) .. ")")
        return client, game, { cached = cached, asks = asks, reads = reads }
    end

    local TAUGHT = "; the spell: of a trade skill yes, recipe info yes, profession learned true"
    -- What an item that teaches is kept with besides: no made item's lines, no class or level
    -- line, not "Already known", a spell the client does not call known.
    local PLAIN = "; a made item's lines: no; class line: none; level line: none; says known: no; spell known: false"
    local SHAPES = {
        pattern = "Recipe / Tailoring, the addon: Recipe; teaching lines: 1; skill line: yes" .. TAUGHT .. PLAIN,
        bare = "Recipe / Tailoring, the addon: Recipe; teaching lines: 1; skill line: no" .. TAUGHT .. PLAIN,
        book = "Recipe / Book, the addon: Recipe; teaching lines: 1; skill line: no; the spell: of a trade skill no, recipe info yes, profession learned false" .. PLAIN,
        schematic = "Consumable / Other, the addon: Recipe; teaching lines: 1; skill line: yes; the spell: of a trade skill yes, recipe info yes, profession learned false" .. PLAIN,
        scroll = "Consumable / Other, the addon: Consumable; teaching lines: 1; skill line: no" .. TAUGHT .. PLAIN,
        fake = "Consumable / Other, the addon: Recipe; teaching lines: 0; skill line: no",
        potion = "Consumable / Potion, the addon: Consumable; teaching lines: 0; skill line: no",
        raises = "Recipe / Tailoring, the addon: Recipe; teaching lines: 1; skill line: yes; the spell: of a trade skill yes, recipe info yes, profession learned <error>" .. PLAIN,
        noSpell = "Recipe / Tailoring, the addon: Recipe; teaching lines: 1; skill line: yes; the spell: of a trade skill no, recipe info no, profession learned nil"
            .. "; a made item's lines: no; class line: none; level line: none; says known: no; spell known: nil",
        -- By its last line, the recipe's own.
        twoLines = "Recipe / Engineering, the addon: Recipe; teaching lines: 2; skill line: yes" .. TAUGHT .. PLAIN,
        rune = "Consumable / Other, the addon: Consumable; teaching lines: 1; skill line: no; the spell: of a trade skill no, recipe info no, profession learned false"
            .. "; a made item's lines: no; class line: unmet; level line: unmet; says known: no; spell known: false",
        knownBook = "Recipe / Book, the addon: Recipe; teaching lines: 1; skill line: no; the spell: of a trade skill no, recipe info no, profession learned false"
            .. "; a made item's lines: no; class line: met; level line: none; says known: yes; spell known: true",
    }
    local COUNTS = { pattern = 2, bare = 1, book = 1, schematic = 1, scroll = 1, fake = 1, potion = 4, raises = 1, noSpell = 1, twoLines = 1,
        rune = 1, knownBook = 1 }
    -- Asked about: a Consumable that teaches or that the addon takes for a recipe, and a
    -- Recipe that teaches without a skill line (which a book is as well).
    local ASKED = { bare = true, book = true, schematic = true, scroll = true, fake = true, rune = true, knownBook = true }

    local function CheckRecord(record, label)
        local shapes = record.shapes or {}
        local known = 0
        for key, shape in pairs(SHAPES) do
            local tally = shapes[shape]
            Equal(tally and tally.count, COUNTS[key], label .. ": the shape of " .. key .. " has its items")
            Equal(tally and tally.asked == true, ASKED[key] == true, label .. ": and is one asked about or not (" .. key .. ")")
            known = known + 1
        end
        local found = 0
        for shape in pairs(shapes) do
            found = found + 1
            Check(found <= known, label .. ": no other shape (" .. shape .. ")")
        end
        Equal(record.records and record.records.Consumable, 10, label .. ": ten records of class Consumable")
        Equal(record.records and record.records.Recipe, 8, label .. ": eight of class Recipe")
        Equal(record.loaded and record.loaded.Consumable, 9, label .. ": nine Consumables loaded")
        Equal(record.loaded and record.loaded.Recipe, 8, label .. ": eight Recipes loaded")
        Equal(record.notLoaded, 1, label .. ": the item the game has not is not loaded")
        Equal(record.noTooltip, 1, label .. ": one tooltip never came")
        Equal(record.lastRecord, KNOWN_BOOK, label .. ": the last item with a record")
        Equal(record.done, true, label .. ": the walk is over")
        Equal(record.cursor, nil, label .. ": with nowhere to go on from")
    end

    for _, flavor in ipairs({ "forever", "retail" }) do
        local client, game, seen = Start(flavor)
        local env = client.env
        Equal(env.Enum.TooltipDataLineType.ItemSpellTriggerLearn, LEARN_LINE, flavor .. ": the line type the cases use is the client's")
        Equal(env.Enum.TooltipDataLineType.UsageRequirement, REQUIREMENT_LINE, flavor .. ": and the requirement line's")
        Equal(env.Enum.ItemClass.Consumable, CONSUMABLE, flavor .. ": the item classes are the client's")
        Equal(env.Enum.ItemClass.Recipe, RECIPE, flavor .. ": both")
        Check(type(env.RETRIEVING_ITEM_INFO) == "string", flavor .. ": the client has a text for a tooltip that is not there yet")
        local kinds = env.Enum.TooltipDataUsageRequirementType
        for _, item in pairs(game.items) do
            for _, line in ipairs(item.tooltip or {}) do
                if line.type == REQUIREMENT_LINE then
                    line.requirementType = (line.class and kinds.RaceClass) or (line.level and kinds.Level)
                        or (line.known and kinds.NotAlreadyKnown) or kinds.Skill
                end
            end
        end

        local wanted = { ["Core.lua"] = true, ["Runner.lua"] = true, ["Teaches.lua"] = true, ["Plan.lua"] = true }
        local T = H.LoadAddon(client, "CaerdonWardrobe_Tests", H.addonDir .. "/CaerdonWardrobe_Tests",
            function(relative) return not wanted[relative] end)
        client:Fire("ADDON_LOADED", "CaerdonWardrobe_Tests")
        client:Fire("PLAYER_LOGIN")
        Check(type(T.TeachesCommand) == "function" and type(T.TeachesLimits) == "table", flavor .. ": the walk is loaded")
        Equal(T.TeachesLimits.firstID, 1, flavor .. ": as shipped it starts at the first item")

        local function Run(rest)
            T.TeachesCommand(rest or "")
            Check(client:TickUntil(function() return not T.IsBusy() end, 600), flavor .. ": the job ends")
            return T.db.teaches
        end

        -- In one run.
        T.TeachesLimits = { firstID = FIRST, lastID = FIRST + 100, batch = 4, seconds = 240 }
        local record = Run()
        CheckRecord(record, flavor .. ", one run")
        Equal(record.runs, 1, flavor .. ", one run: it is one")
        Equal(record.looked, 101, flavor .. ", one run: every ID of the range was looked at")
        Equal(seen.asks[MOUNT], nil, flavor .. ": an item of another class is not asked for")
        Equal(seen.asks[GHOST], 1, flavor .. ": the item the game has not was asked for once")
        Equal(seen.reads[LATE], 2, flavor .. ": the late tooltip was read a second time")

        local scroll = (record.shapes[SHAPES.scroll] or {}).examples or {}
        Check(scroll[1] and scroll[1].id == SCROLL and scroll[1].name == "Odd Scroll" and scroll[1].spell == SpellOf(SCROLL)
            and scroll[1].spellName == "Odd Thing" and scroll[1].tradeSkill == "Tailoring" and scroll[1].infoName == "Odd Thing",
            flavor .. ": a Consumable that teaches a recipe is kept with its spell and the trade skill")
        local schematic = (record.shapes[SHAPES.schematic] or {}).examples or {}
        Equal(schematic[1] and schematic[1].skillLine, "Requires Engineering (75)", flavor .. ": the skill line is kept as written")
        local book = (record.shapes[SHAPES.book] or {}).examples or {}
        Check(book[1] and book[1].tradeSkill == nil and book[1].infoName == "Testing",
            flavor .. ": a spell that is no recipe is kept with what the client's recipe info says of it")
        Equal(#((record.shapes[SHAPES.potion] or {}).examples or {}), 4, flavor .. ": a shape keeps a few examples")
        local twoLines = ((record.shapes[SHAPES.twoLines] or {}).examples or {})[1] or {}
        Check(twoLines.spell == SpellOf(TWO_LINES) and twoLines.spells == MADE_ITEM_SPELL .. ", " .. SpellOf(TWO_LINES)
            and twoLines.spellName == "Test Pet Box" and twoLines.tradeSkill == "Tailoring",
            flavor .. ": an item with two teaching lines is judged by the last and kept with both")
        Equal(scroll[1] and scroll[1].spells, nil, flavor .. ": one with a single line is not")
        local rune = ((record.shapes[SHAPES.rune] or {}).examples or {})[1] or {}
        Check(rune.classLine == "Classes: Mage (unmet, below 0 of 1 teaching lines)"
            and rune.levelLine == "Requires Level 40 (unmet, below 0 of 1 teaching lines)",
            flavor .. ": a class line and a level line are kept as written, with whether the toon meets them and where they stand")

        -- A finished walk is not gone on from: the next run is a new one.
        record = Run()
        Equal(record.runs, 1, flavor .. ": a run after a finished walk starts anew")
        CheckRecord(record, flavor .. ", anew")

        -- Stopped for time, and gone on with. With no item's data there, each four wait a
        -- frame at least, so no run gets through more than four.
        local function Forget()
            for itemID in pairs(seen.cached) do
                seen.cached[itemID] = nil
            end
        end
        Forget()
        T.TeachesLimits = { firstID = FIRST, lastID = FIRST + 100, batch = 4, seconds = 0 }
        record = Run("restart")
        Equal(record.done, nil, flavor .. ", in parts: the first run is not the whole walk")
        Equal(record.cursor, BOOK + 1, flavor .. ", in parts: it goes on behind its first four of the two classes")        Check(tostring(record.stoppedBy):find("seconds", 1, true) ~= nil, flavor .. ", in parts: and says what stopped it")
        local runs = 1
        while not record.done and runs < 20 do
            record = Run()
            runs = runs + 1
        end
        Equal(runs, 5, flavor .. ", in parts: five runs for eighteen items, four at a time, the last two at the walk's end")
        Equal(record.runs, runs, flavor .. ", in parts: each counted")
        CheckRecord(record, flavor .. ", in parts")
        Equal(record.looked, 101, flavor .. ", in parts: no ID was looked at twice")

        -- Another build's record is not added to.
        Forget()
        T.TeachesLimits = { firstID = FIRST, lastID = FIRST + 100, batch = 4, seconds = 0 }
        record = Run("restart")
        Equal(record.done, nil, flavor .. ": a walk that is not over")
        record.build = "0.0.0.1"
        T.TeachesLimits.seconds = 240
        record = Run()
        Equal(record.runs, 1, flavor .. ": is not gone on with in another build")
        CheckRecord(record, flavor .. ", another build")

        Equal(#client.errors, 0, flavor .. ": no error reached the error handler (" .. tostring(client.errors[1]) .. ")")
        Equal(#T.db.errors, 0, flavor .. ": and none in the tests themselves (" .. tostring((T.db.errors[1] or {}).message) .. ")")
    end
end
