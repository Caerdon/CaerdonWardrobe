-- What a recipe item teaches, by its tooltip's own line.
--
-- The addon finds a recipe item's recipe by the item's name. The tooltip has a line of a type
-- of its own for what an item teaches (ItemSpellTriggerLearn, 38), and every recording of a
-- recipe has one with a spell ID: the one WoW Forever recording (Plans: Silvered Bronze
-- Leggings, 12259) and retail's eleven. The test addon's contract recipe.taughtSpell asks a
-- client whether that spell is the recipe's ID in the profession's list. This runs the
-- contract against hand-made bags: the lines here are made after the recorded ones, the
-- recipes and their IDs are invented.
--
-- Real code: the addon (for the name's way and the recorded lists), the test addon's runner
-- and contracts, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 33 }

    local LEARN_LINE, REQUIREMENT_LINE = 38, 43
    local RECIPE_CLASS, MISC_CLASS = 9, 15
    -- Known and in this toon's list; in another toon's list alone; worded another way in the
    -- list than on the item; a book that teaches no recipe of a list; a recipe without the
    -- line; and something that is no recipe and has the line.
    local KNOWN_ID, OTHERS_ID, REWORDED_ID, BOOK_ID, BARE_ID, MOUNT_ID = 991001, 991002, 991003, 991004, 991005, 991006
    -- And one with the known recipe's name that teaches another recipe of the list.
    local TWIN_ID = 991007
    local KNOWN_SPELL, OTHERS_SPELL, REWORDED_SPELL, BOOK_SPELL, MOUNT_SPELL = 70001, 70002, 70003, 70004, 70005

    local function Recipe(name, spell, known)
        local tooltip = { { text = "Binds when picked up", type = 20, bonding = 6 } }
        if spell then
            tooltip[#tooltip + 1] = { text = "Use: Teaches you how to sew something.", type = LEARN_LINE, spellID = spell }
        end
        tooltip[#tooltip + 1] = { text = "Requires Tailoring (50)", type = REQUIREMENT_LINE, requirementType = 0 }
        if known then
            tooltip[#tooltip + 1] = { text = "Already known", type = REQUIREMENT_LINE, r = 1, g = 0.125, b = 0.125 }
        end
        return { name = name, quality = 1, level = 20, minLevel = 0, type = "Recipe", subType = "Tailoring", stack = 1,
            price = 100, classID = RECIPE_CLASS, subClassID = 2, bindType = 1, tooltip = tooltip }
    end

    local function Start(flavor)
        local items = {
            [KNOWN_ID] = Recipe("Pattern: Blue Shirt", KNOWN_SPELL, true),
            [OTHERS_ID] = Recipe("Pattern: Red Shirt", OTHERS_SPELL),
            [REWORDED_ID] = Recipe("Pattern: fine green shirt", REWORDED_SPELL),
            [BOOK_ID] = Recipe("Expert Tailoring", BOOK_SPELL),
            [BARE_ID] = Recipe("Pattern: Grey Shirt", nil),
            [TWIN_ID] = Recipe("Pattern: Blue Shirt", REWORDED_SPELL),
            [MOUNT_ID] = { name = "Reins of the Test", quality = 3, level = 20, minLevel = 20, type = "Miscellaneous",
                subType = "Mount", stack = 1, price = 100, classID = MISC_CLASS, subClassID = 5, bindType = 1,
                tooltip = { { text = "Use: Teaches you how to summon this mount.", type = LEARN_LINE, spellID = MOUNT_SPELL } } },
        }
        local saved = {
            CaerdonRecipeData = {
                globalRecipeNameToID = { ["Blue Shirt"] = KNOWN_SPELL },
                Farrealm = {
                    Zzyxa = {
                        knownRecipes = { ["Blue Shirt"] = KNOWN_SPELL }, scannedProfessions = { Tailoring = true }, tools = {},
                        recipes = { Tailoring = { complete = true, recipes = {
                            [KNOWN_SPELL] = { name = "Blue Shirt", learned = true },
                            [REWORDED_SPELL] = { name = "Green Shirt of Fineness", learned = false },
                        } } },
                    },
                    Other = { knownRecipes = { ["Red Shirt"] = OTHERS_SPELL },
                        recipes = { Tailoring = { complete = true, recipes = { [OTHERS_SPELL] = { name = "Red Shirt", learned = true } } } } },
                },
            },
        }
        local game = H.StockGame(TOON, items)
        local spells = { [KNOWN_SPELL] = "Blue Shirt", [OTHERS_SPELL] = "Red Shirt", [REWORDED_SPELL] = "Green Shirt of Fineness",
            [BOOK_SPELL] = "Tailoring" }
        game:Set("C_Spell.GetSpellName", function(spell) return spells[spell] end)
        game:Set("C_TradeSkillUI.GetRecipeInfo", function(spell)
            return spells[spell] and { name = spells[spell], learned = spell == KNOWN_SPELL, recipeID = spell } or nil
        end)
        local client = H.Client.New({ flavor = flavor, provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
        for name, value in pairs(saved) do
            rawset(client.env, name, H.DeepCopy(value))
        end
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)
        Equal(#client.errors, 0, flavor .. ": no error reached the error handler at the start (" .. tostring(client.errors[1]) .. ")")
        return client, game, items
    end

    for _, flavor in ipairs({ "forever", "retail" }) do
        local client, game, items = Start(flavor)
        local env = client.env
        Equal(env.Enum.TooltipDataLineType.ItemSpellTriggerLearn, LEARN_LINE, flavor .. ": the line type the cases use is the client's")
        Equal(env.Enum.ItemClass.Recipe, RECIPE_CLASS, flavor .. ": and so is the item class")
        local kinds = env.Enum.TooltipDataUsageRequirementType
        for _, itemID in ipairs({ KNOWN_ID }) do
            local lines = items[itemID].tooltip
            lines[#lines].requirementType = kinds.NotAlreadyKnown
        end

        local bag = { KNOWN_ID, OTHERS_ID, REWORDED_ID, BOOK_ID, BARE_ID, MOUNT_ID }
        local slotSpell = {} -- item ID -> another spell on the slot's teaching line
        local hyperlink = game.names["C_TooltipInfo.GetHyperlink"]
        game:Set("C_Container.GetContainerNumSlots", function(index) return index == 0 and #bag or 0 end)
        game:Set("C_Container.GetContainerItemID", function(index, slot) return index == 0 and bag[slot] or nil end)
        game:Set("C_Container.GetContainerItemLink", function(index, slot)
            return index == 0 and bag[slot] and game.Link(bag[slot]) or nil
        end)
        game:Set("C_TooltipInfo.GetBagItem", function(index, slot)
            local itemID = index == 0 and bag[slot]
            if not itemID then
                return nil
            end
            local data = hyperlink(game.Link(itemID))
            for _, line in ipairs(data.lines) do
                if line.type == LEARN_LINE and slotSpell[itemID] then
                    line.spellID = slotSpell[itemID]
                end
            end
            data.hyperlink, data.guid = nil, "Item-1-0-" .. itemID
            return data
        end)

        local wanted = { ["Core.lua"] = true, ["Runner.lua"] = true, ["Contracts.lua"] = true, ["Plan.lua"] = true }
        local T = H.LoadAddon(client, "CaerdonWardrobe_Tests", H.addonDir .. "/CaerdonWardrobe_Tests",
            function(relative) return not wanted[relative] end)
        client:Fire("ADDON_LOADED", "CaerdonWardrobe_Tests")
        client:Fire("PLAYER_LOGIN")
        local ID = "recipe.taughtSpell"
        local function Run()
            T.RunTests({ match = ID, force = true })
            Check(client:TickUntil(function() return not T.IsBusy() end, 120), flavor .. ": the job ends")
            return (T.db.contracts[T.GetClient().build] or {})[ID] or {}
        end

        local result = Run()
        Equal(result.status, "pass", flavor .. ": it passes on the bags (" .. tostring(result.message) .. ")")
        local detail = result.detail or {}
        Equal(detail.items, 6, flavor .. ": six items")
        Equal(detail.recipeItems, 5, flavor .. ": five of them recipes")
        Equal(detail.learnLines, 10, flavor .. ": a teaching line in both tooltips of five items")
        Equal(detail.withoutLine, 1, flavor .. ": one recipe without the line")
        Equal(detail.inRecordedList, 3, flavor .. ": three teach a spell a recorded list has")
        Equal(detail.nameAgrees, 1, flavor .. ": one is found by its name as well, and it is the same recipe")
        Equal(detail.nameFindsNone, 3, flavor .. ": three have a line and a name that finds nothing")
        local recipes = detail.recipes or {}
        local known = recipes[tostring(KNOWN_ID)] or {}
        Check(known.linkSpells == tostring(KNOWN_SPELL) and known.slotSpells == tostring(KNOWN_SPELL) and known.saysKnown == true
            and known.byName == KNOWN_SPELL and known.listedName == "Blue Shirt" and known.listedLearned == true
            and known.listedOf == "this toon" and known.infoLearned == true and known.profession == "Tailoring",
            flavor .. ": the known recipe is kept with its spell, its name's recipe, the list's entry and the tooltip's word")
        local others = recipes[tostring(OTHERS_ID)] or {}
        Check(others.listedOf == "another toon" and others.listedName == "Red Shirt" and others.byName == nil and others.saysKnown == false,
            flavor .. ": one that another toon's list alone has says whose list")
        local reworded = recipes[tostring(REWORDED_ID)] or {}
        Check(reworded.recipeName == "fine green shirt" and reworded.byName == nil and reworded.listedName == "Green Shirt of Fineness"
            and reworded.listedLearned == false,
            flavor .. ": a recipe worded another way in the list is found by its spell where its name finds nothing")
        local book = recipes[tostring(BOOK_ID)] or {}
        Check(book.linkSpells == tostring(BOOK_SPELL) and book.listedName == nil and book.spellName == "Tailoring",
            flavor .. ": a book's spell is in no list")
        local bare = recipes[tostring(BARE_ID)] or {}
        Check(bare.linkSpells == "" and bare.slotSpells == "", flavor .. ": a recipe without the line has no spell")
        local elsewhere = detail.elsewhere or {}
        Check(elsewhere["slot: an item of class " .. MISC_CLASS] == 1 and elsewhere["link: an item of class " .. MISC_CLASS] == 1,
            flavor .. ": what else has the line is kept by its class")

        -- What was seen is added to what the run before saw.
        result = Run()
        Equal((result.detail or {}).learnLines, 20, flavor .. ": a second run adds its lines to the first's")

        -- Bags without a recipe, and bags whose recipes no list has.
        bag = { MOUNT_ID }
        result = Run()
        Equal(result.status, "info", flavor .. ": no recipe is no pass")
        Check(tostring(result.message):find("no recipe in these bags", 1, true) ~= nil, flavor .. ": and says so")
        bag = { BOOK_ID, BARE_ID }
        result = Run()
        Equal(result.status, "info", flavor .. ": recipes that no list has are no pass either")
        Check(tostring(result.message):find("nothing to compare", 1, true) ~= nil, flavor .. ": and says so")

        -- A recipe the toon does not carry is asked by its ID: the link's tooltip alone. What
        -- is no recipe in this client, or lies in the bags already, is not asked.
        local stockPool = T.TaughtSpellPool
        Check(type(stockPool) == "table" and #stockPool > 0, flavor .. ": the contract has recipes to ask by ID")
        T.TaughtSpellPool = { KNOWN_ID, OTHERS_ID, MOUNT_ID, 991999, TWIN_ID }
        bag = { KNOWN_ID }
        result = Run()
        Equal(result.status, "pass", flavor .. ", by ID: it passes (" .. tostring(result.message) .. ")")
        detail = result.detail or {}
        Equal(detail.byID, 2, flavor .. ", by ID: two recipes were asked by their ID")
        Equal(detail.nameFindsAnother, 1, flavor .. ", by ID: one has a name that finds another recipe than it teaches")
        local twin = (detail.recipes or {})[tostring(TWIN_ID)] or {}
        Check(twin.nameFindsAnother == true and twin.byName == KNOWN_SPELL and twin.foundID == REWORDED_SPELL and twin.foundBy == "spell",
            flavor .. ", by ID: and the addon finds the one it teaches, by its spell")
        Check(((detail.recipes or {})[tostring(KNOWN_ID)] or {}).foundBy == "spell", flavor .. ", by ID: as it does the known one")
        Equal(detail.poolNotRecipes, 2, flavor .. ", by ID: a mount and an item the client has not are left out")
        Equal(detail.poolNotLoaded, 0, flavor .. ", by ID: none failed to load")
        others = (detail.recipes or {})[tostring(OTHERS_ID)] or {}
        Check(others.asked == "by its ID" and others.slotSpells == "" and others.linkSpells == tostring(OTHERS_SPELL)
            and others.listedOf == "another toon", flavor .. ", by ID: it is kept with the link's spell and the list's entry")
        Equal(((detail.recipes or {})[tostring(KNOWN_ID)] or {}).asked, "in the bags", flavor .. ", by ID: the one carried is asked in the bags")
        bag = { MOUNT_ID }
        T.TaughtSpellPool = { BOOK_ID }
        result = Run()
        Equal(result.status, "info", flavor .. ", by ID: a recipe no list has is no pass")
        T.TaughtSpellPool = {}
        bag = { KNOWN_ID, OTHERS_ID, REWORDED_ID, BOOK_ID, BARE_ID, MOUNT_ID }

        -- Faults, one at a time.
        local function Fault(label, plant, undo, expected)
            plant()
            local faulty = Run()
            Equal(faulty.status, "fail", flavor .. ", fault, " .. label .. ": the contract fails")
            Check(tostring(faulty.message):find(expected, 1, true) ~= nil,
                flavor .. ", fault, " .. label .. ": and says why (" .. tostring(faulty.message) .. ")")
            undo()
        end
        Fault("the slot teaches another spell", function() slotSpell[KNOWN_ID] = REWORDED_SPELL end,
            function() slotSpell[KNOWN_ID] = nil end, "the slot's tooltip teaches spell")
        local knownLine = items[KNOWN_ID].tooltip[2]
        Fault("a teaching line without a spell", function() knownLine.spellID = nil end,
            function() knownLine.spellID = KNOWN_SPELL end, "the teaching line's spellID is a nil")
        -- The addon has the item's spell from before, so it finds another recipe than the line now names.
        Fault("the addon finds another recipe than the line names", function() knownLine.spellID = REWORDED_SPELL end,
            function() knownLine.spellID = KNOWN_SPELL end, "and the addon finds recipe")
        Equal(Run().status, "pass", flavor .. ": and passes again with the faults gone")
        Equal(#client.errors, 0, flavor .. ": no error reached the error handler")
    end
end
