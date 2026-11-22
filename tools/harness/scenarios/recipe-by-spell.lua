-- A recipe item's recipe, by the spell its tooltip says it teaches.
--
-- The item's name is no key of a profession's list. A WoW Forever client showed both ways it
-- goes wrong: "Recipe: Elixir of Ogre's Strength" teaches a recipe the list calls "Elixir of
-- Ogre Strength", which the name does not find, and a list there has pairs of recipes with one
-- name (an old one and one that client added), of which the name finds whichever was read
-- last. The tooltip's teaching line names the spell, and that is the list's own key. This
-- holds the rule (CaerdonRecipe:FindRecipeID and what asks it) against hand-made lists: the
-- lines are made after recorded ones, the recipes and their IDs are invented.
--
-- Real code: the addon, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 33 }

    local LEARN_LINE, USE_LINE, REQUIREMENT_LINE = 38, 44, 43
    local RECIPE_CLASS = 9
    -- Worded another way in the list; the two of one name; one whose spell no list has; one
    -- without the line; a book whose line is a plain use; another item of the old one, whose
    -- tooltip comes late.
    local REWORDED_ID, OLD_ID, ADDED_ID, UNLISTED_ID, BARE_ID, BOOK_ID, LATE_ID = 992001, 992002, 992003, 992004, 992005, 992006, 992007
    local REWORDED_SPELL, OLD_SPELL, ADDED_SPELL, UNLISTED_SPELL, BARE_SPELL, PLAIN_SPELL =
        71001, 71002, 71003, 71004, 71005, 71006
    -- A recipe for an item that teaches something itself: its tooltip has the made item's
    -- teaching line first and the recipe's own last (a WoW Forever client: Schematic: Lil'
    -- Smoky 11827 has 15049 "Summon Robot" and then 15633, the recipe). The list words the
    -- recipe another way than the item, so only the spell finds it.
    local PET_ID, PET_SUMMON_SPELL, PET_RECIPE_SPELL = 992008, 71008, 71009

    local function Recipe(name, spell, lineType)
        local tooltip = { { text = "Binds when picked up", type = 20, bonding = 6 } }
        if spell then
            tooltip[#tooltip + 1] = { text = "Use: Teaches you how to make something.", type = lineType or LEARN_LINE, spellID = spell }
        end
        tooltip[#tooltip + 1] = { text = "Requires Alchemy (50)", type = REQUIREMENT_LINE, requirementType = 0 }
        return { name = name, quality = 1, level = 20, minLevel = 0, type = "Recipe", subType = "Alchemy", stack = 1,
            price = 100, classID = RECIPE_CLASS, subClassID = 6, bindType = 1, tooltip = tooltip }
    end

    local NAMES = {
        [REWORDED_SPELL] = "Elixir of Test Strength",
        [OLD_SPELL] = "Test Banner",
        [ADDED_SPELL] = "Test Banner",
        [UNLISTED_SPELL] = "Unlisted Potion",
        [BARE_SPELL] = "Bare Potion",
        [PLAIN_SPELL] = "Plain Potion",
        [PET_SUMMON_SPELL] = "Summon Test Pet",
        [PET_RECIPE_SPELL] = "Test Pet Crate",
    }

    local function Start(flavor)
        local items = {
            [REWORDED_ID] = Recipe("Recipe: Elixir of Test's Strength", REWORDED_SPELL),
            [OLD_ID] = Recipe("Recipe: Test Banner", OLD_SPELL),
            [ADDED_ID] = Recipe("Recipe: Test Banner", ADDED_SPELL),
            [UNLISTED_ID] = Recipe("Recipe: Plain Potion", UNLISTED_SPELL),
            [BARE_ID] = Recipe("Recipe: Bare Potion", nil),
            [BOOK_ID] = Recipe("Expert Alchemy", PLAIN_SPELL, USE_LINE),
            [LATE_ID] = Recipe("Recipe: Test Banner", nil),
            [PET_ID] = Recipe("Recipe: Test Pet Box", PET_RECIPE_SPELL),
        }
        table.insert(items[PET_ID].tooltip, 2,
            { text = "Use: Teaches you how to summon this companion.", type = LEARN_LINE, spellID = PET_SUMMON_SPELL })
        local saved = {
            CaerdonProfessionData = { Farrealm = {
                Zzyxa = { Alchemy = { skillLevel = 120 } },
                Other = { Alchemy = { skillLevel = 150 } },
                Third = { Alchemy = { skillLevel = 150 } },
            } },
            CaerdonRecipeData = {
                -- The name of the pair has kept the added one's ID, which was read last.
                globalRecipeNameToID = { ["Test Banner"] = ADDED_SPELL, ["Bare Potion"] = BARE_SPELL, ["Plain Potion"] = PLAIN_SPELL },
                Farrealm = {
                    -- This toon knows the old one of the pair and not the added one.
                    Zzyxa = {
                        knownRecipes = { ["Test Banner"] = OLD_SPELL }, scannedProfessions = { Alchemy = true }, tools = {},
                        recipes = { Alchemy = { complete = true, recipes = {
                            [REWORDED_SPELL] = { name = "Elixir of Test Strength", learned = false },
                            [OLD_SPELL] = { name = "Test Banner", learned = true },
                            [ADDED_SPELL] = { name = "Test Banner", learned = false },
                            [PET_RECIPE_SPELL] = { name = "Test Pet Crate", learned = true },
                        } } },
                    },
                    -- Another toon knows the added one and not the old one, and has learned the
                    -- reworded one since its list was recorded.
                    Other = {
                        knownRecipes = { ["Test Banner"] = ADDED_SPELL, ["Elixir of Test Strength"] = REWORDED_SPELL },
                        scannedProfessions = { Alchemy = true }, tools = {},
                        recipes = { Alchemy = { complete = true, recipes = {
                            [REWORDED_SPELL] = { name = "Elixir of Test Strength", learned = false },
                            [OLD_SPELL] = { name = "Test Banner", learned = false },
                            [ADDED_SPELL] = { name = "Test Banner", learned = true },
                        } } },
                    },
                    -- A third knows none of them.
                    Third = {
                        knownRecipes = {}, scannedProfessions = { Alchemy = true }, tools = {},
                        recipes = { Alchemy = { complete = true, recipes = {
                            [REWORDED_SPELL] = { name = "Elixir of Test Strength", learned = false },
                            [OLD_SPELL] = { name = "Test Banner", learned = false },
                            [ADDED_SPELL] = { name = "Test Banner", learned = false },
                        } } },
                    },
                },
            },
        }
        local game = H.StockGame(TOON, items)
        local asked = {}
        -- As the client answers with no profession window open: a recipe's name, never "learned".
        game:Set("C_TradeSkillUI.GetRecipeInfo", function(recipeID)
            asked[#asked + 1] = recipeID
            return NAMES[recipeID] and { name = NAMES[recipeID], learned = false, recipeID = recipeID } or nil
        end)
        game:Set("C_TradeSkillUI.GetRecipeSchematic", function() return {} end)
        game:Set("C_TradeSkillUI.IsRecipeProfessionLearned", function() return true end)
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
        return client, game, items, asked
    end

    for _, flavor in ipairs({ "forever", "retail" }) do
        local client, game, items, asked = Start(flavor)
        local env = client.env
        Equal(env.Enum.TooltipDataLineType.ItemSpellTriggerLearn, LEARN_LINE, flavor .. ": the teaching line's type is the client's")
        Equal(env.Enum.TooltipDataLineType.ItemSpellTriggerOnUse, USE_LINE, flavor .. ": and so is the plain use line's")

        local function Item(itemID)
            local item = env.CaerdonItem:CreateFromItemID(itemID)
            local loaded = false
            item:ContinueOnItemLoad(function() loaded = true end)
            client:TickUntil(function() return loaded end, 10)
            return item
        end
        local function Info(itemID)
            return Item(itemID):GetItemData():GetRecipeInfo()
        end
        local function Toon(others, name)
            for _, toon in ipairs(others and others.toons or {}) do
                if toon.name == name then
                    return toon
                end
            end
            return {}
        end
        local function Names(list)
            local names = {}
            for _, toon in ipairs(list or {}) do
                names[#names + 1] = toon.name
            end
            return table.concat(names, ", ")
        end

        -- What the item teaches.
        Equal(Item(REWORDED_ID):GetTaughtSpellID(), REWORDED_SPELL, flavor .. ": the teaching line's spell is what the item teaches")
        Equal(Item(BARE_ID):GetTaughtSpellID(), nil, flavor .. ": an item without the line teaches none")
        Equal(Item(BOOK_ID):GetTaughtSpellID(), nil, flavor .. ": a plain use line is no teaching line")
        Equal(Item(PET_ID):GetTaughtSpellID(), PET_RECIPE_SPELL,
            flavor .. ": of two teaching lines the last is the recipe's, the first the made item's own")

        -- Which recipe that is.
        local id, by = env.CaerdonRecipe:FindRecipeID(Item(REWORDED_ID))
        Check(id == REWORDED_SPELL and by == "spell", flavor .. ": a recipe the list words another way is found by its spell")
        id, by = env.CaerdonRecipe:FindRecipeID(Item(OLD_ID))
        Check(id == OLD_SPELL and by == "spell", flavor .. ": of two recipes with one name, the old one's item finds the old one")
        id, by = env.CaerdonRecipe:FindRecipeID(Item(ADDED_ID))
        Check(id == ADDED_SPELL and by == "spell", flavor .. ": and the added one's item the added one")
        id, by = env.CaerdonRecipe:FindRecipeID(Item(UNLISTED_ID))
        Check(id == PLAIN_SPELL and by == "name", flavor .. ": a spell no list has shown is left for the name")
        id, by = env.CaerdonRecipe:FindRecipeID(Item(BARE_ID))
        Check(id == BARE_SPELL and by == "name", flavor .. ": an item without the line is found by its name")
        id, by = env.CaerdonRecipe:FindRecipeID(Item(PET_ID))
        Check(id == PET_RECIPE_SPELL and by == "spell", flavor .. ": a recipe for an item that teaches something itself is found by its own spell")
        local pet = Info(PET_ID) or {}
        Check(pet.recipeID == PET_RECIPE_SPELL and pet.learned == true, flavor .. ": and is learned where the list says so")
        id, by = env.CaerdonRecipe:FindRecipeID(Item(BOOK_ID))
        Check(id == nil and by == nil, flavor .. ": a book whose name no list has finds none")

        -- What this toon's saved lists say of it. The client says "not learned" of all of
        -- them here, as it does with no profession window open.
        local reworded = Info(REWORDED_ID) or {}
        Check(reworded.recipeID == REWORDED_SPELL and reworded.foundBy == "spell" and reworded.learned == false
            and reworded.canLearn == true, flavor .. ": the reworded recipe has its info, not learned, to learn")
        local old = Info(OLD_ID) or {}
        Check(old.recipeID == OLD_SPELL and old.learned == true and old.canLearn == false,
            flavor .. ": the one of the pair this toon knows is learned")
        local added = Info(ADDED_ID) or {}
        Check(added.recipeID == ADDED_SPELL and added.learned == false and added.canLearn == true,
            flavor .. ": the one it does not know is not, though a recipe of that name is among those it knows")
        local bare = Info(BARE_ID) or {}
        Check(bare.recipeID == BARE_SPELL and bare.foundBy == "name" and bare.learned == false,
            flavor .. ": the one found by its name is asked as before")
        Equal(Info(BOOK_ID), nil, flavor .. ": the book has no recipe info")

        -- A recipe learned since its list was recorded is filed under its ID among the known.
        local saved = env.CaerdonRecipeData.Farrealm.Zzyxa
        saved.knownRecipes["Elixir of Test Strength"] = REWORDED_SPELL
        Equal((Info(REWORDED_ID) or {}).learned, true, flavor .. ": a recipe filed under its ID among the known is learned")
        saved.knownRecipes["Elixir of Test Strength"] = nil

        -- What the realm's other toons have of it.
        local others = Item(OLD_ID):GetItemData():GetOtherToonRecipeInfo()
        Check(others ~= nil and others.taughtSpell == OLD_SPELL and others.knownByPlayer == true,
            flavor .. ": the old one of the pair is known by this toon")
        Check(Toon(others, "Other").knowsRecipe == false and Toon(others, "Other").inRecordedList == true,
            flavor .. ": a toon that knows the added one alone lacks the old one")
        Equal(Names(others and others.missing), "Other, Third", flavor .. ": so both other toons can take it")
        others = Item(ADDED_ID):GetItemData():GetOtherToonRecipeInfo()
        Check(others ~= nil and others.knownByPlayer == false, flavor .. ": the added one is not known by this toon")
        Equal(Toon(others, "Other").knowsRecipe, true, flavor .. ": and is known by the toon that has it")
        Equal(Names(others and others.missing), "Third", flavor .. ": so only the third can take it")
        others = Item(REWORDED_ID):GetItemData():GetOtherToonRecipeInfo()
        Check(Toon(others, "Other").knowsRecipe == true,
            flavor .. ": a recipe learned since the recording is known by its ID, whatever the item calls it")
        Check(Toon(others, "Third").knowsRecipe == false and Toon(others, "Third").inRecordedList == true,
            flavor .. ": a toon's list has the reworded recipe, by its ID")
        Equal(Names(others and others.missing), "Third", flavor .. ": so the toon that lacks it can take it")
        Equal(Names(others and others.notInList), "", flavor .. ": and none is said to have no such recipe in its list")
        others = Item(BOOK_ID):GetItemData():GetOtherToonRecipeInfo()
        Equal(Names(others and others.notInList), "Other, Third", flavor .. ": a book is in no toon's list, as before")

        -- A tooltip that is not there when the item's data is made: the name's recipe stands
        -- until the line is, and the spell's replaces it.
        local data = Item(LATE_ID):GetItemData()
        local info = data:GetRecipeInfo() or {}
        Check(info.foundBy == "name" and info.recipeID == ADDED_SPELL,
            flavor .. ": without its line yet, the item's recipe is the name's")
        table.insert(items[LATE_ID].tooltip, 2,
            { text = "Use: Teaches you how to make something.", type = LEARN_LINE, spellID = OLD_SPELL })
        info = data:GetRecipeInfo() or {}
        Check(info.foundBy == "spell" and info.recipeID == OLD_SPELL and info.learned == true,
            flavor .. ": with the line, the same item's recipe is the spell's")

        Equal(#client.errors, 0, flavor .. ": no error reached the error handler (" .. tostring(client.errors[1]) .. ")")
        Check(#asked > 0, flavor .. ": the client was asked for recipe info")
    end
end
