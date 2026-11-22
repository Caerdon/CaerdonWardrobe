-- What the toon's recipes take, recorded when a profession window opens (types/RecipeMixin.lua,
-- RecordRecipes) and read per item (CaerdonIngredients.lua, the export's [Ingredients]).
--
-- An ingredient has a use while a recipe that takes it gives skill, learned or not. One this
-- toon's recipes have outgrown is one to sell; one another toon's recipes take, and this
-- toon has no use for, is one to send (CaerdonItemMixin:GetIngredientStatus).
--
-- The game is hand-made from the client's documentation (both flavors describe the recipe
-- info and the schematic alike). No client has shown what it answers: whether the list holds
-- recipes the toon has not learned, what their difficulty reads, or what a classic recipe's
-- reagent slots are typed as.
--
-- Real code: the addon's item side, core and features/DebugFrame.lua, Blizzard's base files
-- from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 33 }

    local function Goods(name)
        return { name = name, quality = 1, level = 20, minLevel = 0, type = "Tradeskill", subType = "Cooking",
            stack = 20, price = 10, classID = 7, subClassID = 8 }
    end
    local WOLF, BOAR, SPICE, SPIDER, ORE, CLAM, CLOTH = 970001, 970002, 970003, 970004, 970005, 970006, 970007
    local HIDE, DUST = 970008, 970009
    local ITEMS = {
        [WOLF] = Goods("Wolf Flank"), [BOAR] = Goods("Boar Meat"), [SPICE] = Goods("Mild Spices"),
        [SPIDER] = Goods("Spider Leg"), [ORE] = Goods("Odd Ore"), [CLAM] = Goods("Clam Meat"),
        [CLOTH] = Goods("Linen Cloth"), [HIDE] = Goods("Cursed Hide"), [DUST] = Goods("Bone Dust"),
    }
    ITEMS[HIDE].bindType = 1 -- binds when picked up
    local PATTERN = 970010
    ITEMS[PATTERN] = { name = "Recipe: Clam Bake", quality = 1, level = 20, minLevel = 0, type = "Recipe", subType = "Cooking",
        stack = 1, price = 50, classID = 9, subClassID = 5 }
    -- A book that raises the profession's cap: of class Recipe, and it teaches no recipe.
    local BOOK = 970012
    ITEMS[BOOK] = { name = "Expert Cookbook", quality = 1, level = 30, minLevel = 0, type = "Recipe", subType = "Cooking",
        stack = 1, price = 2500, classID = 9, subClassID = 5 }
    ITEMS[DUST].price = 0
    -- Ammunition a recipe takes: not a material to the client.
    local ARROW = 970011
    ITEMS[ARROW] = { name = "Sharp Arrow", quality = 1, level = 30, minLevel = 25, type = "Projectile", subType = "Arrow",
        stack = 200, price = 0, classID = 6, subClassID = 2, equipLoc = "INVTYPE_AMMO" }

    local ORANGE, GREEN, GRAY = 0, 2, 3
    local BASIC, MODIFYING = 1, 0
    local STEAK, ROAST, CAKE, RIBS, MYSTERY = 9001, 9002, 9003, 9004, 9005
    local COOKING, FIRST_AID = 185, 129

    local function Slot(itemIDs, quantity, reagentType, required)
        local reagents = {}
        for index, itemID in ipairs(itemIDs) do
            reagents[index] = { itemID = itemID }
        end
        return { reagents = reagents, quantityRequired = quantity, reagentType = reagentType or BASIC,
            required = required ~= false }
    end

    -- options: flavor, fullList (the client has GetAllRecipeIDs), saved (CaerdonRecipeData from
    -- an earlier session)
    local function Start(options)
        local world = { rank = 150, ready = false, linked = false, filtered = false, schematicsAsked = 0,
            build = "70938", professions = { { "Cooking", COOKING }, { "First Aid", FIRST_AID } } }
        world.recipes = {
            [STEAK] = { name = "Wolf Steak", learned = true, difficulty = GREEN, canSkillUp = true, skillUps = 1,
                trivial = 165, slots = { Slot({ WOLF }, 1), Slot({ SPICE }, 1) } },
            [ROAST] = { name = "Roasted Boar", learned = true, difficulty = GRAY, canSkillUp = false, skillUps = 0,
                trivial = 90, slots = { Slot({ BOAR }, 1), Slot({ DUST }, 1) } },
            [CAKE] = { name = "Spider Cake", learned = false, difficulty = ORANGE, canSkillUp = true, skillUps = 1,
                trivial = 215, slots = { Slot({ SPIDER }, 2), Slot({ SPICE }, 1) } },
            -- An optional slot is not what the recipe takes.
            [RIBS] = { name = "Boar Ribs", learned = true, difficulty = GRAY, canSkillUp = false, skillUps = 0,
                trivial = 120, slots = { Slot({ BOAR }, 1), Slot({ ORE }, 1, MODIFYING, false) } },
            -- A recipe the client gives no difficulty for.
            [MYSTERY] = { name = "Mystery Stew", learned = true, slots = { Slot({ CLAM }, 3) } },
        }
        world.listed = { STEAK, ROAST, CAKE, RIBS, MYSTERY }

        local game = H.StockGame(TOON, ITEMS)
        game:Set("GetBuildInfo", function() return "1.60.1", world.build, "Nov 1 2026", 16001 end)
        game:Set("GetProfessions", function()
            local indexes = {}
            for index in ipairs(world.professions) do
                indexes[index] = index
            end
            return unpack(indexes)
        end)
        game:Set("GetProfessionInfo", function(index)
            local profession = world.professions[index]
            if profession then
                return profession[1], 134400, world.rank, 225, 0, 0, profession[2]
            end
        end)
        game:Set("C_TradeSkillUI.IsTradeSkillReady", function() return world.ready end)
        game:Set("C_TradeSkillUI.IsTradeSkillLinked", function() return world.linked end)
        game:Set("C_TradeSkillUI.GetOnlyShowMakeableRecipes", function() return world.filtered end)
        game:Set("C_TradeSkillUI.GetAllProfessionTradeSkillLines", function() return { COOKING } end)
        game:Set("C_TradeSkillUI.GetProfessionInfoBySkillLineID", function(skillLine)
            if skillLine == COOKING then
                return { professionID = COOKING, professionName = "Cooking", skillLevel = world.rank, maxSkillLevel = 225 }
            end
        end)
        -- A secondary profession as WoW Forever has it: no rank on the base, one child line of
        -- the same name that has it.
        game:Set("C_TradeSkillUI.GetBaseProfessionInfo", function()
            return { professionID = COOKING, professionName = "Cooking", skillLevel = 0, maxSkillLevel = 0 }
        end)
        game:Set("C_TradeSkillUI.GetChildProfessionInfo", function()
            return { professionID = 2548, professionName = options.line or "Cooking", skillLevel = world.rank, maxSkillLevel = 225,
                parentProfessionID = COOKING, parentProfessionName = "Cooking" }
        end)
        if options.fullList ~= false then
            game:Set("C_TradeSkillUI.GetAllRecipeIDs", function() return H.DeepCopy(world.listed) end)
        end
        game:Set("C_TradeSkillUI.GetFilteredRecipeIDs", function() return H.DeepCopy(world.listed) end)
        game:Set("C_TradeSkillUI.GetRecipeInfo", function(recipeID)
            local recipe = world.recipes[recipeID]
            if not recipe then
                return nil
            end
            -- Outside the profession window the client knows the recipe and not what it is to
            -- the toon (a retail recording shows that shape).
            if not world.ready then
                return { recipeID = recipeID, name = recipe.name, learned = false, relativeDifficulty = 0,
                    canSkillUp = false, numSkillUps = 0, maxTrivialLevel = 0 }
            end
            return { recipeID = recipeID, name = recipe.name, learned = recipe.learned,
                relativeDifficulty = recipe.difficulty, canSkillUp = recipe.canSkillUp or false,
                numSkillUps = recipe.skillUps or 0, maxTrivialLevel = recipe.trivial or 0 }
        end)
        game:Set("C_TradeSkillUI.GetRecipeSchematic", function(recipeID)
            world.schematicsAsked = world.schematicsAsked + 1
            local recipe = world.recipes[recipeID]
            return recipe and { recipeID = recipeID, name = recipe.name, reagentSlotSchematics = recipe.slots } or nil
        end)
        game:Set("C_TradeSkillUI.GetRecipeRequirements", function() return {} end)
        game:Set("C_TradeSkillUI.GetProfessionInfoByRecipeID", function(recipeID)
            if world.recipes[recipeID] then
                return { professionID = 2548, professionName = options.line or "Cooking", skillLevel = world.rank,
                    maxSkillLevel = 225 }
            end
        end)
        game:Set("C_TradeSkillUI.GetRecipeSourceText", function(recipeID)
            return world.ready and recipeID == CAKE and "Sold by:\n  a cook" or nil
        end)
        game:Set("C_TradeSkillUI.IsRecipeProfessionLearned", function() return true end)
        -- What the rest of the export asks for and this client has no answer to.
        game:Set("C_AddOns.GetAddOnInfo", function(name) return name, name, "", true, nil, "INSECURE" end)
        game:Set("PLAYER_FACTION_GROUP", { [0] = "Horde", [1] = "Alliance" })
        -- features/Tooltip.lua registers with it as it loads.
        game:Set("TooltipDataProcessor.AddTooltipPostCall", function() end)
        game:Set("TooltipDataProcessor.AddLinePreCall", function() end)
        -- QuestieDB, as far as the vendor goods module reads it: how many vendors sell an
        -- item (world.vendors). It has no quests, so the quest module leaves it alone.
        world.vendors = {}
        if options.vendors then
            game:Set("LibQuestieDB.RequireContract", function() return true end)
            game:Set("LibQuestieDB.Item.Get", function(itemID, field)
                local count = field == "vendors" and world.vendors[itemID]
                if not count then
                    return nil
                end
                local npcs = {}
                for index = 1, count do
                    npcs[index] = 1000 + index
                end
                return npcs
            end)
        end

        local client = H.Client.New({ flavor = options.flavor, provider = game })
        game.client = client
        local env = client.env
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
        if options.saved then
            rawset(env, "CaerdonRecipeData", H.DeepCopy(options.saved))
        end
        if options.professions then
            rawset(env, "CaerdonProfessionData", H.DeepCopy(options.professions))
        end
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "features/DebugFrame.lua", namespace)
        if options.tooltip then
            client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "features/Tooltip.lua", namespace)
        end
        Equal(#client.errors, 0, options.label .. ": no error reached the error handler at the start")

        world.client, world.env, world.game, world.namespace = client, env, game, namespace
        -- How often the items were judged again, by the reason given.
        -- And what the newest refresh of each reason said had changed.
        world.reasons, world.details = {}, {}
        local core = env.CaerdonWardrobe
        local refreshItems = core.RefreshItems
        function core:RefreshItems(reason, detail, ...)
            world.reasons[tostring(reason)] = (world.reasons[tostring(reason)] or 0) + 1
            world.details[tostring(reason)] = detail
            return refreshItems(self, reason, detail, ...)
        end
        -- The lines the addon adds to the item's tooltip about other toons.
        function world.TooltipLines(itemID)
            local tooltip = { lines = {} }
            function tooltip:AddLine(line) self.lines[#self.lines + 1] = line end
            namespace.Tooltip:AddIngredientUsers(tooltip, world.Item(itemID))
            return table.concat(tooltip.lines, " | ")
        end

        -- The lines the addon adds to a recipe item's tooltip about other toons.
        -- known: the tooltip carries the client's "Already known" line.
        function world.TooltipLinesFor(itemID, known)
            local tooltip = { lines = {} }
            function tooltip:AddLine(line) self.lines[#self.lines + 1] = line end
            function tooltip:GetPrimaryTooltipData()
                return { lines = known and { { type = env.Enum.TooltipDataLineType.UsageRequirement,
                    requirementType = env.Enum.TooltipDataUsageRequirementType.NotAlreadyKnown } } or {} }
            end
            namespace.Tooltip:AddRecipeLearners(tooltip, world.Item(itemID))
            return table.concat(tooltip.lines, " | ")
        end

        -- The profession window opens on Cooking, stays open a moment and closes.
        function world.Open()
            world.ready = true
            client:Fire("TRADE_SKILL_DATA_SOURCE_CHANGED")
            client:Tick(10)
            world.ready = false
        end
        function world.Item(itemID)
            local item = env.CaerdonItem:CreateFromItemID(itemID)
            local loaded = false
            item:ContinueOnItemLoad(function() loaded = true end)
            client:TickUntil(function() return loaded end, 10)
            return item
        end
        function world.Info(itemID)
            return world.Item(itemID):GetIngredientInfo()
        end
        function world.Status(itemID)
            local item = world.Item(itemID)
            local ready, status
            client:TickUntil(function()
                ready, status = item:GetCaerdonStatus()
                return ready
            end, 10)
            return status
        end
        function world.Saved()
            local data = env.CaerdonRecipeData
            return data and data[TOON.realm] and data[TOON.realm][TOON.name] and data[TOON.realm][TOON.name].recipes
        end
        -- The rows of the export's section, from its title to the blank line after it.
        function world.Section(itemID, title)
            title = title or "[Ingredients]"
            local feature = env.CaerdonWardrobe:GetFeature("DebugFrame")
            local payload = feature:BuildClipboardPayload(world.Item(itemID))
            local rows, inside = {}, false
            for line in (payload .. "\n"):gmatch("(.-)\n") do
                if line == title then
                    inside = true
                elseif inside and line == "" then
                    break
                elseif inside then
                    rows[#rows + 1] = line
                end
            end
            return inside and table.concat(rows, "\n") or nil
        end
        function world.Errors(label)
            Equal(#client.errors, 0, label .. ": no error reached the error handler")
            for _, message in ipairs(client.errors) do
                print("        error: " .. tostring(message))
            end
        end
        return world
    end

    local function Has(text, piece)
        return type(text) == "string" and text:find(piece, 1, true) ~= nil
    end

    ------------------------------------------------------------------------------------
    -- Both flavors: the recording and what an item reads from it
    ------------------------------------------------------------------------------------
    for _, flavor in ipairs({ "forever", "retail" }) do
        local world = Start({ flavor = flavor, label = flavor })
        local function Label(text) return flavor .. ": " .. text end

        -- Nothing was recorded: nothing is known, and the export says which professions lack it.
        Equal(world.Info(WOLF), nil, Label("before the window was open, no recipe is known to take an item"))
        local section = world.Section(WOLF)
        Check(Has(section, "  Has A Use: no recorded recipe takes it"), Label("the export says so (" .. tostring(section) .. ")"))
        Check(Has(section, "  Recorded Professions: none"), Label("and that nothing is recorded"))
        Check(Has(section, "  Not Recorded (open the profession once): Cooking, First Aid"),
            Label("and which professions were never opened"))
        Check(Has(section, "  Vendors That Sell It: not known (QuestieDB is not loaded)"),
            Label("and that nothing says who sells it, without QuestieDB"))
        Equal(world.Item(WOLF):GetVendorInfo(), nil, Label("which the item reads as nothing known"))
        local statusBefore = world.Status(BOAR)

        world.Open()
        local saved = world.Saved()
        local cooking = saved and saved.Cooking
        Check(type(cooking) == "table", Label("the window open: the profession is recorded under its name"))
        if type(cooking) ~= "table" then
            return
        end
        Equal(cooking.rank, 150, Label("with the rank the difficulties were said at, the child line's"))
        Equal(cooking.maxRank, 225, Label("and its maximum"))
        Equal(cooking.skillLine, COOKING, Label("and the base skill line"))
        Equal(cooking.complete, true, Label("as the whole list"))
        Equal(cooking.build, "70938", Label("with the build the reagents were read in"))
        Equal(world.schematicsAsked, 5, Label("one schematic per recipe"))
        Equal(cooking.recipes[STEAK].reagents[WOLF], 1, Label("a recipe's reagent with its quantity"))
        Equal(cooking.recipes[CAKE].reagents[SPIDER], 2, Label("a recipe that is not learned is recorded too"))
        Equal(cooking.recipes[CAKE].learned, false, Label("as not learned"))
        Equal(cooking.recipes[RIBS].reagents[ORE], nil, Label("an optional slot is not recorded"))
        Equal(cooking.recipes[STEAK].maxTrivialLevel, 165, Label("the client's trivial level is kept as it was said"))

        -- What the recording makes of the items.
        Equal(statusBefore, "", Label("marked: nothing before a recording"))
        Equal(world.reasons["recipes recorded"], nil,
            Label("marked: the skills watch refreshed for the ranks this opening saved, so the recording asks for nothing more"))
        Equal(world.Status(BOAR), "sellable", Label("marked: an ingredient every recipe has outgrown is one to sell"))
        Equal(world.Status(WOLF), "", Label("marked: one a recipe still gives skill for is kept"))
        Equal(world.Status(SPIDER), "", Label("marked: one only a recipe not learned gives skill for is kept"))
        Equal(world.Status(CLAM), "", Label("marked: one with a recipe the client gave no difficulty for is left alone"))
        Equal(world.Status(ORE), "", Label("marked: one no recorded recipe takes is left alone"))
        Equal(world.Status(DUST), "", Label("marked: an outgrown one no vendor pays for is left alone"))
        -- A quest's item is not marked, with the quest icon on or off (the quest module's
        -- answer, stood in for here): a quest in the log, then one still to come whose icon
        -- is switched off.
        local getItemQuestInfo = world.env.CaerdonQuestItems.GetItemQuestInfo
        local questAnswer
        world.env.CaerdonQuestItems.GetItemQuestInfo = function(_, itemID) return itemID == BOAR and questAnswer or nil end
        questAnswer = { hasQuestValue = true, isActive = true, isUpcoming = false, quests = {} }
        world.env.CaerdonWardrobe:RefreshItems("test")
        Equal(world.Status(BOAR), "quest", Label("marked: an ingredient a quest takes has the quest's icon"))
        questAnswer = { hasQuestValue = false, isActive = false, isUpcoming = true, quests = {} }
        world.env.CaerdonWardrobe:RefreshItems("test")
        Equal(world.Status(BOAR), "", Label("marked: nor one for a quest still to come whose icon is off"))
        world.env.CaerdonQuestItems.GetItemQuestInfo = getItemQuestInfo
        world.env.CaerdonWardrobe:RefreshItems("test")
        Check(Has(world.Section(BOAR), "  Status From This Rule: sellable"), Label("marked: and the export says what the rule gave"))
        -- Food kept for a hunter's pet is not outgrown (the food module's answer, stood in for here).
        local isKeptForPet = world.env.CaerdonFoodDrink.IsKeptForPet
        world.env.CaerdonFoodDrink.IsKeptForPet = function(_, itemID) return itemID == BOAR end
        world.env.CaerdonWardrobe:RefreshItems("test")
        Equal(world.Status(BOAR), "", Label("marked: not what is kept for the pet"))
        world.env.CaerdonFoodDrink.IsKeptForPet = isKeptForPet
        world.env.CaerdonWardrobe:RefreshItems("test")
        local iconConfig = world.env.CaerdonWardrobeConfig.Icon
        iconConfig.ShowOutgrownIngredients = false
        world.env.CaerdonWardrobe:RefreshItems("test")
        Equal(world.Status(BOAR), "", Label("marked: not with the setting off"))
        iconConfig.ShowOutgrownIngredients = true
        world.env.CaerdonWardrobe:RefreshItems("test")

        -- Which trade goods the auction icon leaves alone.
        local function Kept(itemID) return world.Item(itemID):IsIngredientKeptFromAuction() end
        Equal(iconConfig.AuctionTradeGoods, "skill", Label("auction: the default leaves out what still gives skill"))
        Check(Kept(WOLF) and Kept(CLAM) and not Kept(BOAR) and not Kept(ORE),
            Label("auction: an ingredient with a use is kept from it, an outgrown one and one no recipe takes are not"))
        iconConfig.AuctionTradeGoods = "professions"
        Check(Kept(WOLF) and Kept(BOAR) and not Kept(ORE), Label("auction: or every ingredient a recipe takes"))
        iconConfig.AuctionTradeGoods = "none"
        Check(Kept(ORE), Label("auction: or every trade good"))
        iconConfig.AuctionTradeGoods = "all"
        Check(not Kept(WOLF) and not Kept(ORE), Label("auction: or none"))
        iconConfig.AuctionTradeGoods = "skill"

        -- A known recipe that gives skill.
        local info = world.Info(WOLF)
        Check(info ~= nil and info.hasUse == true, Label("a green recipe is a use"))
        Equal(info and #info.recipes, 1, Label("one recipe takes the flank"))
        Equal(info and info.recipes[1].reading, "known, gives skill until rank 165", Label("and reads so, by the rank now"))
        Equal(info and info.recipes[1].difficultyName, "green", Label("with the colour it had"))
        Equal(info and info.recipes[1].quantity, 1, Label("with its quantity"))
        Equal(info and info.recipes[1].recordedRank, 150, Label("and the rank it was said at"))
        -- Every recipe gray.
        info = world.Info(BOAR)
        Check(info ~= nil and info.hasUse == false and info.undecided == 0, Label("two gray recipes are no use"))
        Equal(info and #info.recipes, 2, Label("both are listed"))
        Equal(info and info.recipes[1].reading, "known, gray from rank 120", Label("as gray"))
        Equal(info and info.recipes[1].name, "Boar Ribs", Label("sorted by name"))
        -- A recipe still to be learned.
        info = world.Info(SPIDER)
        Check(info ~= nil and info.hasUse == true, Label("a recipe not learned that would give skill is a use"))
        Equal(info and info.recipes[1].reading, "not learned, would give skill until rank 215", Label("and reads so"))
        Equal(info and info.recipes[1].quantity, 2, Label("with its quantity"))
        info = world.Info(SPICE)
        Equal(info and #info.recipes, 2, Label("an item two recipes take lists both"))
        -- No difficulty from the client: not counted either way.
        info = world.Info(CLAM)
        Check(info ~= nil and info.hasUse == false and info.undecided == 1, Label("a recipe without a difficulty is undecided"))
        Equal(world.Info(ORE), nil, Label("an item only an optional slot takes is no ingredient"))
        Equal(world.Info(CLOTH), nil, Label("an item of a profession that was not opened is not known"))

        -- The export.
        section = world.Section(BOAR)
        Check(Has(section, "  Has A Use: false (every recipe that takes it is gray)"), Label("export: all gray (" .. tostring(section) .. ")"))
        Check(Has(section, "    - Cooking: Boar Ribs (recipe 9004) x1: known, gray from rank 120"), Label("export: the recipe's line"))
        Check(Has(section, "      recorded: difficulty 3, canSkillUp false, numSkillUps 0, maxTrivialLevel 120, sourceType nil, " ..
            "said at rank 150; read by the rank now, 150"), Label("export: what was recorded, as the client said it"))
        Check(Has(section, "      client now: learned false, difficulty 0, canSkillUp false, numSkillUps 0, maxTrivialLevel 0, " ..
            "sourceType nil, disabled nil (nil); line: Cooking (2548) rank 150 of 225"),
            Label("export: and what the client says with the window closed, the recipe's skill line with it"))
        Check(Has(world.Section(SPIDER), "; source: no answer"), Label("export: a recipe not learned is asked where it comes from"))
        world.ready = true
        Check(Has(world.Section(SPIDER), "; source: Sold by: a cook"), Label("export: and the answer is on one line"))
        Check(not Has(world.Section(BOAR), "; source:"), Label("export: a known recipe is not asked"))
        world.ready = false
        Check(Has(section, "    - Cooking: 5 recipes, 4 known, the whole list, said at rank 150 of 225 (Cooking), rank now 150; " ..
            "this session: 5 recipes and 5 schematics read in "), Label("export: the recording"))
        Check(Has(section, "  Not Recorded (open the profession once): First Aid"), Label("export: the profession still to open"))
        section = world.Section(CLAM)
        Check(Has(section, "  Has A Use: not known (the client gave no difficulty for 1 of its recipes)"), Label("export: undecided"))
        Check(Has(world.Section(WOLF), "  Has A Use: true"), Label("export: a use"))

        -- The rank rises to the recipe's gray rank. The window stays closed: the refresh the
        -- skills watch asks for at a point gained is enough.
        world.rank = 164
        world.env.CaerdonWardrobe:RefreshItems("test")
        Check(world.Info(WOLF).hasUse == true, Label("a point below the gray rank: still a use"))
        world.rank = 165
        world.env.CaerdonWardrobe:RefreshItems("test")
        info = world.Info(WOLF)
        Check(info ~= nil and info.hasUse == false, Label("the gray rank reached: no use any more, with the window closed"))
        Equal(info and info.recipes[1].reading, "known, gray from rank 165", Label("and reads so"))
        Equal(info and info.recipes[1].recordedRank, 150, Label("on a recording as old as it was"))
        Equal(world.Status(WOLF), "sellable", Label("and it is one to sell"))

        -- Open again: the reagents are not read again, the difficulties are.
        world.rank = 166
        world.recipes[STEAK].difficulty = GRAY
        world.Open()
        Equal(world.schematicsAsked, 5, Label("opened again: no schematic is asked for a second time"))
        Equal(world.Saved().Cooking.recipes[STEAK].difficulty, GRAY, Label("opened again: the difficulty is read again"))
        info = world.Info(WOLF)
        Check(info ~= nil and info.hasUse == false, Label("opened again: a recipe gone gray is no use"))
        Equal(info and info.recipes[1].recordedRank, 166, Label("opened again: with the new rank"))
        Equal(world.reasons["recipes recorded"], nil, Label("opened again: the recording says nothing new, so nothing is judged again"))
        Equal(info and info.recipes[1].quantity, 1, Label("opened again: and the reagents it had"))

        -- A point gained by crafting, the window open. The client has the new rank when its
        -- event comes, and the watcher's frame hears the event before the recipe code's does:
        -- one refresh, made from the toon's rank and the rank saved for it alike.
        local function SkillRefreshes() return world.reasons.skills or 0 end
        local function SavedRank() return world.env.CaerdonRecipe:GetSavedRank("Cooking") end
        -- The window's events from before are a burst that is over, so the point is one of its own.
        world.client:Tick(20)
        local skillRefreshes = SkillRefreshes()
        world.ready = true
        world.rank = 167
        world.client:Fire("SKILL_LINES_CHANGED")
        world.client:Tick(20)
        Equal(SkillRefreshes() - skillRefreshes, 1, Label("a point with the window open: one refresh, not a second when the burst is over"))
        Check(Has(world.details.skills, "profession 185: 166 -> 167"), Label("a point with the window open: it names the toon's rank (" ..
            tostring(world.details.skills) .. ")"))
        Check(Has(world.details.skills, "saved Cooking: 166 -> 167"), Label("a point with the window open: and the saved rank with it"))
        Equal(SavedRank(), 167, Label("a point with the window open: the rank is saved"))
        world.ready = false

        -- The window closed, the client says nothing of the profession's own lines: the toon's
        -- rank refreshes, and the saved one follows when the window opens, at its event.
        skillRefreshes = SkillRefreshes()
        world.rank = 168
        world.client:Fire("SKILL_LINES_CHANGED")
        world.client:Tick(20)
        Equal(SkillRefreshes() - skillRefreshes, 1, Label("a point with the window closed: one refresh"))
        Equal(SavedRank(), 167, Label("a point with the window closed: the saved rank is as it was"))
        world.ready = true
        world.client:Fire("TRADE_SKILL_DATA_SOURCE_CHANGED")
        Equal(SkillRefreshes() - skillRefreshes, 2, Label("the window opened after it: the saved rank refreshes at the event"))
        Equal(world.details.skills, "saved Cooking: 167 -> 168", Label("the window opened after it: and is named"))
        world.client:Tick(20)
        Equal(SkillRefreshes() - skillRefreshes, 2, Label("the window opened after it: once"))
        world.ready = false

        -- A recipe learned between two openings.
        world.recipes[CAKE].learned = true
        world.client:Fire("NEW_RECIPE_LEARNED", CAKE)
        world.client:Tick(5)
        info = world.Info(SPIDER)
        Equal(info and info.recipes[1].reading, "known, gives skill until rank 215", Label("a recipe learned reads as known at once"))

        -- Another build: the client's data may have changed, so the reagents are read again.
        -- And a recipe's gray rank: what a recording says about an item is no longer what the
        -- last one said, with no event beside it, so the recording asks for the refresh.
        Equal(world.Status(BOAR), "sellable", Label("another build: before it, the boar meat is outgrown"))
        world.build = "70999"
        world.recipes[STEAK].slots = { Slot({ WOLF }, 2) }
        world.recipes[RIBS].trivial = 300
        world.Open()
        Equal(world.reasons["recipes recorded"], 1, Label("another build: a recording that changes an item's use judges the items again"))
        Equal(world.Status(BOAR), "", Label("another build: and the boar meat is kept"))
        Equal(world.schematicsAsked, 10, Label("another build: every schematic is read again"))
        info = world.Info(WOLF)
        Equal(info and info.recipes[1].quantity, 2, Label("another build: and the new reagents are the ones kept"))
        Equal(world.Info(SPICE) and #world.Info(SPICE).recipes, 1, Label("another build: a reagent a recipe dropped is gone"))

        -- Someone else's recipes say nothing about this toon.
        world.linked = true
        world.recipes[STEAK].difficulty = ORANGE
        world.Open()
        Equal(world.Saved().Cooking.recipes[STEAK].difficulty, GRAY, Label("a linked profession is not recorded"))
        world.linked = false

        -- A refresh about what is worn keeps the index; the profession dropped is found by the
        -- next refresh about anything, which is what the skills watch asks for.
        world.professions = { { "First Aid", FIRST_AID } }
        world.env.CaerdonWardrobe:RefreshItems("test", nil, "worn")
        Check(world.Info(WOLF) ~= nil, Label("a refresh about what is worn reads no profession again"))
        world.env.CaerdonWardrobe:RefreshItems("test")
        Equal(world.Info(WOLF), nil, Label("a profession dropped: its recipes no longer count"))
        section = world.Section(WOLF)
        Check(Has(section, "  Recorded But No Longer A Profession: Cooking"), Label("export: and the export says why"))
        world.professions = { { "Cooking", COOKING }, { "First Aid", FIRST_AID } }
        world.env.CaerdonWardrobe:RefreshItems("test")
        world.client:Tick(10)
        world.Errors(flavor)
    end

    ------------------------------------------------------------------------------------
    -- A client without the whole list, and another toon's recording
    ------------------------------------------------------------------------------------
    do
        local saved = {
            globalRecipeNameToID = {},
            Farrealm = {
                Dorn = {
                    knownRecipes = {}, scannedProfessions = {}, tools = {},
                    recipes = {
                        Cooking = { skillLine = COOKING, rank = 200, maxRank = 225, line = "Cooking", complete = true,
                            build = "70938", recipes = {
                                [STEAK] = { name = "Wolf Steak", learned = true, difficulty = GRAY, canSkillUp = false,
                                    skillUps = 0, maxTrivialLevel = 165, reagents = { [WOLF] = 1, [SPICE] = 1 } },
                            } },
                    },
                },
            },
        }
        local world = Start({ flavor = "forever", label = "filtered", fullList = false, saved = saved })

        -- The list as a filter left it.
        world.filtered = true
        world.listed = { STEAK }
        world.Open()
        local cooking = world.Saved().Cooking
        Equal(cooking and cooking.complete, false, "filtered: a filtered list is not the whole one")
        Check(world.Info(WOLF) ~= nil, "filtered: what it shows is recorded")
        Equal(world.Info(BOAR), nil, "filtered: what it hides is not")
        Check(Has(world.Section(WOLF), "    - Cooking: 1 recipes, 1 known, a filtered list, "), "filtered: and the export says so")

        -- The filter off: the whole list.
        world.filtered = false
        world.listed = { STEAK, ROAST, CAKE, RIBS, MYSTERY }
        world.Open()
        Equal(world.Saved().Cooking.complete, true, "unfiltered: the whole list")
        Check(world.Info(BOAR) ~= nil, "unfiltered: every recipe is recorded")

        -- Filtered again: the recipes it hides stay as they were recorded.
        world.filtered = true
        world.listed = { STEAK }
        world.recipes[STEAK].difficulty = GRAY
        world.Open()
        Equal(world.Saved().Cooking.complete, true, "filtered after the whole list: still the whole one")
        Check(world.Info(BOAR) ~= nil, "filtered after the whole list: a hidden recipe is kept")
        Equal(world.Saved().Cooking.recipes[STEAK].difficulty, GRAY, "filtered after the whole list: a shown one is read again")

        -- The other toon's recording is in the export, and is not this toon's use.
        local section = world.Section(WOLF)
        Check(Has(section, "  Other Toons' Recipes That Take It:"), "other toon: listed in the export (" .. tostring(section) .. ")")
        Check(Has(section, "    - Dorn, Cooking (rank 200): Wolf Steak (recipe 9001) x1: known, gray from rank 165"),
            "other toon: with its recipe and how it read there")
        Equal(#world.Info(WOLF).recipes, 1, "other toon: its recipe is not among this toon's")
        world.Errors("filtered")
    end

    ------------------------------------------------------------------------------------
    -- Other toons: what this toon has no use for and one of them does is one to send
    ------------------------------------------------------------------------------------
    do
        local function Recording(rank, recipes)
            return { skillLine = COOKING, rank = rank, maxRank = 225, line = "Cooking", complete = true, build = "70938",
                recipes = recipes }
        end
        local function Toon(recipes) return { knownRecipes = {}, scannedProfessions = {}, tools = {}, recipes = recipes } end
        local saved = {
            globalRecipeNameToID = {},
            Farrealm = {
                -- Still gets skill from the boar recipe; knows a wolf recipe that is gray to it.
                Dorn = Toon({ Cooking = Recording(90, {
                    [ROAST] = { name = "Roasted Boar", learned = true, difficulty = GREEN, maxTrivialLevel = 120,
                        reagents = { [BOAR] = 1, [SPICE] = 1 } },
                    [STEAK] = { name = "Wolf Steak", learned = true, difficulty = GRAY, maxTrivialLevel = 95,
                        reagents = { [WOLF] = 1 } },
                    -- In its list and not learned: what the recipe item PATTERN teaches.
                    [9401] = { name = "Clam Bake", learned = false, difficulty = ORANGE, maxTrivialLevel = 150,
                        reagents = {} },
                }) }),
                -- A profession this toon does not have, a recipe not learned yet.
                Mira = Toon({ Tailoring = { skillLine = 197, rank = 80, maxRank = 150, line = "Tailoring", complete = true,
                    build = "70938", recipes = {
                        [9101] = { name = "Linen Bag", learned = false, difficulty = ORANGE, maxTrivialLevel = 120,
                            reagents = { [CLOTH] = 3, [HIDE] = 1, [ARROW] = 100 } },
                    } } }),
                -- This toon's own recording of an earlier session.
                Zzyxa = Toon({ Cooking = Recording(150, {
                    [9301] = { name = "Old Stew", learned = true, difficulty = GREEN, maxTrivialLevel = 200,
                        reagents = { [CLAM] = 1 } },
                }) }),
                -- Dropped the profession since its recording.
                Olaf = Toon({ Cooking = Recording(40, {
                    [9201] = { name = "Ore Soup", learned = true, difficulty = ORANGE, maxTrivialLevel = 300,
                        reagents = { [ORE] = 1 } },
                }) }),
            },
        }
        -- Dorn has gained ten points since its recording; Olaf's profession reads 0.
        local professions = { Farrealm = {
            Dorn = { Cooking = { skillLevel = 100 } },
            Olaf = { Cooking = { skillLevel = 0 } },
        } }
        local world = Start({ flavor = "forever", label = "send", saved = saved, professions = professions, tooltip = true,
            vendors = true })
        local iconConfig = world.env.CaerdonWardrobeConfig.Icon
        Equal(iconConfig.ShowIngredientsForOtherToons, true, "send: on by default")
        Equal(iconConfig.IngredientsForOtherToons, "skill", "send: for what gives the other toon skill")

        -- What this toon recorded itself is its own and not another toon's.
        local own = world.Info(CLAM)
        Check(own ~= nil and own.hasUse and #own.recipes == 1 and #own.others == 0,
            "send: this toon's own recording is read as its own, from the session before")
        -- What it has no recipe for and another toon's recipes take is one to send.
        -- A recipe item another toon can learn has the same status (it had the icon for
        -- learning by another toon before): Dorn's list is recorded and lacks it.
        world.env.CaerdonRecipeData.Farrealm.Dorn.scannedProfessions.Cooking = true
        Equal(world.Item(PATTERN):GetUnneededRecipeStatus({ alreadyKnown = true }), "send",
            "send: a recipe this toon knows and another toon has not learned")
        iconConfig.ShowRecipesForOtherToons = false
        Equal(world.Item(PATTERN):GetUnneededRecipeStatus({ alreadyKnown = true }), "sellable", "send: sold with that option off")
        iconConfig.ShowRecipesForOtherToons = true
        -- A book that raises the profession's cap is of class Recipe and no recipe of any list
        -- (Expert Cookbook 16072 in a Forever client): the other toon's recorded whole list has
        -- no such name, before it learns the book or after, so nothing says it can learn it.
        do
            local lineTypes = world.env.Enum.TooltipDataLineType
            local SKILL = world.env.Enum.TooltipDataUsageRequirementType.Skill
            local REQUIRES = { text = "Requires Cooking (125)", type = lineTypes.UsageRequirement, requirementType = SKILL }
            local RAISES = { text = "Use: Teaches you how to be an Expert Cook, allowing a maximum of 225 cooking skill.",
                type = lineTypes.ItemSpellTriggerOnUse }
            local dornRecording = world.env.CaerdonRecipeData.Farrealm.Dorn.recipes.Cooking
            local dornRank = world.env.CaerdonProfessionData.Farrealm.Dorn.Cooking
            local book = world.Item(BOOK)
            local function Lists()
                local others = book:GetRecipeOtherToonInfo()
                return others and ("missing %d, too low %d, unknown %d, not in list %d"):format(#others.missing, #others.tooLow,
                    #others.unknown, #others.notInList), others
            end

            -- Nothing in its tooltip says what it gives: nothing is said about the toon.
            Equal(Lists(), "missing 0, too low 0, unknown 0, not in list 1",
                "book: a toon whose recorded list has no such recipe is not one that can learn it")
            Equal(book:GetUnneededRecipeStatus({ alreadyKnown = true }), nil,
                "book: so a book this toon knows is neither one to send nor one to sell")
            Equal(book:GetUnneededRecipeStatus({ alreadyKnown = false }), nil, "book: nor is one it does not know")
            Equal(world.TooltipLinesFor(BOOK, true), "", "book: and its tooltip names nobody")
            local recipeSection = world.Section(BOOK, "[Recipe]")
            Check(Has(recipeSection, "    Dorn (rank 100): not known (its recorded list has no recipe of this name: " ..
                "the item teaches no recipe of that list; its recorded cap 225, the cap the item gives nil)"),
                "book: the export says why (" .. tostring(recipeSection) .. ")")
            Check(Has(recipeSection, "  Toons Whose List Has No Such Recipe: 1"), "book: and counts the toon")

            -- The book as the client has it: the rank it asks for and the cap it gives.
            ITEMS[BOOK].tooltip = { RAISES, REQUIRES }
            local requirement = book:GetSkillRequirement()
            Check(requirement ~= nil and requirement.skillName == "Cooking" and requirement.rank == 125 and requirement.useNumber == 225,
                "caps: the tooltip's skill, rank and the one number of its use line are read")
            -- The other toon's cap is at the book's: it has learned it.
            Equal(Lists(), "missing 0, too low 0, unknown 0, not in list 0", "caps: a toon at the cap the book gives has learned it")
            Equal(book:GetUnneededRecipeStatus({ alreadyKnown = true }), "sellable",
                "caps: so a book this toon knows and nobody else wants is one to sell")
            Check(Has(world.Section(BOOK, "[Recipe]"), "    Dorn (rank 100): has learned it (its recorded cap 225 is at the cap " ..
                "the item gives, 225)"), "caps: and the export says so")
            -- Below the book's cap and below the rank the book asks for: not yet.
            dornRecording.maxRank = 150
            Equal(Lists(), "missing 0, too low 1, unknown 0, not in list 0",
                "caps: a toon below the cap lacks it, and below the rank the book asks for cannot learn it yet")
            Equal(book:GetUnneededRecipeStatus({ alreadyKnown = true }), nil, "caps: no mail icon, and not one to sell either")
            Equal(world.TooltipLinesFor(BOOK, true), "Needs Cooking 125 first: Dorn (Cooking 100)",
                "caps: the tooltip of a book this toon knows says what the other toon needs")
            Equal(world.TooltipLinesFor(BOOK, false), "", "caps: and nothing on one it does not know")
            recipeSection = world.Section(BOOK, "[Recipe]")
            Check(Has(recipeSection, "    Dorn (rank 100): lacks it (its recorded cap 150 is below the cap the item gives, 225): " ..
                "rank too low (Cooking 100, the item asks for 125)"), "caps: the export says both (" .. tostring(recipeSection) .. ")")
            Check(Has(recipeSection, "  Item Asks For: Cooking 125") and Has(recipeSection, "  Cap The Item Gives: 225") and
                Has(recipeSection, "  Toons Whose Rank Is Too Low: 1"), "caps: with what the item asks for and gives")
            -- At the rank the book asks for: one to send.
            dornRank.skillLevel = 125
            Equal(Lists(), "missing 1, too low 0, unknown 0, not in list 0", "caps: at the rank the book asks for it can learn it")
            Equal(book:GetUnneededRecipeStatus({ alreadyKnown = true }), "send", "caps: and the book is one to send")
            Equal(world.TooltipLinesFor(BOOK, true), "Could be learned by: Dorn (Cooking 125)", "caps: with the toon in the tooltip")
            -- A recording made on one of several skill lines says nothing about the profession's cap.
            dornRecording.line = "Outland Cooking"
            Equal(Lists(), "missing 0, too low 0, unknown 0, not in list 1", "caps: a cap of one skill line of several is not compared")
            dornRecording.line = "Cooking"
            -- A use line whose number is not above the rank asked for is no cap.
            ITEMS[BOOK].tooltip = { { text = "Use: Teaches you 5 ways to burn a steak.", type = lineTypes.ItemSpellTriggerOnUse }, REQUIRES }
            Equal(Lists(), "missing 0, too low 0, unknown 0, not in list 1", "caps: a number that is not above the rank asked for is no cap")
            -- Nor is one of two numbers.
            ITEMS[BOOK].tooltip = { { text = "Use: Teaches 2 ways to reach 225 cooking skill.", type = lineTypes.ItemSpellTriggerOnUse },
                REQUIRES }
            Equal(Lists(), "missing 0, too low 0, unknown 0, not in list 1", "caps: a use line with two numbers gives no cap")
            ITEMS[BOOK].tooltip = nil
            dornRecording.maxRank = 225

            -- A recipe of the list asks for a rank too.
            dornRank.skillLevel = 100
            local pattern = world.Item(PATTERN)
            Check(Has(world.Section(PATTERN, "[Recipe]"), "    Dorn (rank 100): lacks it (in its recorded list, not learned): " ..
                "can learn it (the item asks for no rank)"), "rank: a recipe that asks for no rank is one the toon can learn")
            ITEMS[PATTERN].tooltip = { { text = "Requires Cooking (120)", type = lineTypes.UsageRequirement, requirementType = SKILL } }
            Equal(pattern:GetUnneededRecipeStatus({ alreadyKnown = true }), nil,
                "rank: a recipe the other toon's rank is too low for is neither one to send nor one to sell")
            Equal(world.TooltipLinesFor(PATTERN, true), "Needs Cooking 120 first: Dorn (Cooking 100)", "rank: and its tooltip says so")
            dornRank.skillLevel = 120
            Equal(pattern:GetUnneededRecipeStatus({ alreadyKnown = true }), "send", "rank: at the rank it asks for it is one to send")
            -- A skill the toon has no saved rank for is not held against it.
            ITEMS[PATTERN].tooltip = { { text = "Requires Outland Cooking (50)", type = lineTypes.UsageRequirement, requirementType = SKILL } }
            Equal(pattern:GetUnneededRecipeStatus({ alreadyKnown = true }), "send",
                "rank: a skill line the toon has no saved rank for holds nothing back")
            Check(Has(world.Section(PATTERN, "[Recipe]"), ": can learn it (no rank saved for Outland Cooking, so none is held against 50)"),
                "rank: and the export says so")
            ITEMS[PATTERN].tooltip = nil
            dornRank.skillLevel = 100

            -- A toon whose recipes were read before whole lists were recorded: judged as
            -- before, by the recipes it knows, until its profession is opened again.
            world.env.CaerdonProfessionData.Farrealm.Bera = { Cooking = { skillLevel = 60 } }
            world.env.CaerdonRecipeData.Farrealm.Bera = { knownRecipes = {}, scannedProfessions = { Cooking = true }, tools = {} }
            local _, others = Lists()
            Check(others ~= nil and #others.missing == 1 and others.missing[1].name == "Bera" and #others.notInList == 1,
                "book: a toon with no recording of its whole list is judged by the recipes it knows")
            Check(Has(world.Section(BOOK, "[Recipe]"), "    Bera (rank 60): lacks it (not among the recipes it knows; " ..
                "its whole list is not recorded, open the profession on that toon)"), "book: and the export says which it was")
            world.env.CaerdonProfessionData.Farrealm.Bera = nil
            world.env.CaerdonRecipeData.Farrealm.Bera = nil
        end
        Equal(world.Status(CLOTH), "send", "send: an ingredient of a profession this toon lacks, for a recipe not learned there")
        Equal(world.Status(BOAR), "send", "send: an ingredient the other toon still gets skill from")
        Equal(world.Status(SPICE), "send", "send: and another one of the same recipe")
        Equal(world.Status(WOLF), "", "send: not one whose recipe is gray to the other toon")
        Equal(world.Status(ORE), "", "send: not for a toon that dropped the profession")
        Equal(world.Status(HIDE), "", "send: not one that binds when picked up")
        -- A hunter's arrows, which an engineer's recipe takes: seen in a Forever client.
        Check(world.Info(ARROW) ~= nil and #world.Info(ARROW).skillFor == 1, "arrows: another toon's recipe takes them")
        Equal(world.Status(ARROW), "", "arrows: an item that is no trade good and no crafting reagent is not one to send")
        Equal(world.TooltipLines(ARROW), "", "arrows: and its tooltip names nobody")
        -- What vendors everywhere sell, the other toon buys where it stands (Star Wood, which
        -- 75 vendors sell, had the mail icon in a Forever client). What a few vendors sell is
        -- still sent: their stock may be a handful.
        do
            local vendorInfo = world.Item(SPICE):GetVendorInfo()
            Check(vendorInfo ~= nil and vendorInfo.vendorCount == 0 and vendorInfo.isCommon == false,
                "vendors: with QuestieDB, an item no vendor sells reads as that")
            world.vendors[SPICE] = 19
            world.env.CaerdonWardrobe:RefreshItems("test")
            Equal(world.Status(SPICE), "send", "vendors: an ingredient a few vendors sell is still one to send")
            world.vendors[SPICE] = 20
            world.env.CaerdonWardrobe:RefreshItems("test")
            Equal(world.Status(SPICE), "", "vendors: one that vendors everywhere sell is not")
            Equal(world.TooltipLines(SPICE), "", "vendors: and its tooltip names nobody")
            Equal(world.Status(BOAR), "send", "vendors: the other ingredient of the same recipe still is")
            local section = world.Section(SPICE)
            Check(Has(section, "  Vendors That Sell It: 20 (QuestieDB)"), "vendors: the export says how many sell it (" ..
                tostring(section) .. ")")
            Check(Has(section, "  Common Vendor Good: true (from 20 vendors on; never one to send)"),
                "vendors: and what that makes it")
            Check(Has(section, "  Status From This Rule: none"), "vendors: and that the rule gave nothing")
            iconConfig.IngredientsForOtherToons = "any"
            world.env.CaerdonWardrobe:RefreshItems("test")
            Equal(world.Status(SPICE), "", "vendors: nor with any recipe of the other toon counting")
            iconConfig.IngredientsForOtherToons = "skill"
            world.vendors[SPICE] = nil
            world.env.CaerdonWardrobe:RefreshItems("test")
            Equal(world.Status(SPICE), "send", "vendors: without the vendors it is one to send again")
        end
        -- A quest of this toon's comes before another toon.
        do
            local getItemQuestInfo = world.env.CaerdonQuestItems.GetItemQuestInfo
            local questAnswer = { hasQuestValue = true, isActive = false, isUpcoming = true, quests = {} }
            world.env.CaerdonQuestItems.GetItemQuestInfo = function(_, itemID)
                return (itemID == BOAR or itemID == PATTERN) and questAnswer or nil
            end
            world.env.CaerdonWardrobe:RefreshItems("test")
            Equal(world.Status(BOAR), "quest", "send: an ingredient a quest still to come takes has the quest's icon")
            Equal(world.Status(PATTERN), "quest", "send: and so has a recipe another toon could learn")
            questAnswer = { hasQuestValue = false, isActive = false, isUpcoming = true, quests = {} }
            world.env.CaerdonWardrobe:RefreshItems("test")
            Equal(world.Status(BOAR), "", "send: and is not one to send with that icon switched off")
            world.env.CaerdonQuestItems.GetItemQuestInfo = getItemQuestInfo
            world.env.CaerdonWardrobe:RefreshItems("test")
            Equal(world.Status(BOAR), "send", "send: without the quest it is one to send again")
            Equal(world.Status(PATTERN), "send", "send: and so is the recipe")
        end
        Equal(world.TooltipLines(BOAR), "Gives skill to: Dorn (Cooking 100)", "send: the tooltip names the toon, with its saved rank")
        Equal(world.TooltipLines(WOLF), "", "send: and says nothing where nothing is to send")
        local info = world.Info(BOAR)
        Equal(info and info.others[1].reading, "known, gives skill until rank 120", "send: read by the other toon's saved rank")

        -- This toon's own recipes come first.
        world.Open()
        Equal(world.Status(SPICE), "", "own use: an ingredient this toon still gets skill from is kept, whoever else does")
        Equal(world.TooltipLines(SPICE), "", "own use: and its tooltip names nobody")
        Equal(#world.Info(WOLF).others, 1, "own use: this toon's own recording is not among the other toons'")
        Equal(world.Status(BOAR), "send", "outgrown here: sent rather than sold while another toon gets skill from it")
        local section = world.Section(BOAR)
        Check(Has(section, "  Status From This Rule: send"), "export: what the rule gave (" .. tostring(section) .. ")")
        Check(Has(section, "  Gives Skill To: Dorn (Cooking 100)"), "export: for whom")
        Check(Has(section, "    - Dorn, Cooking (rank 100): Roasted Boar (recipe 9002) x1: known, gives skill until rank 120"),
            "export: and by which recipe")
        -- Outgrown here and sold by vendors everywhere: not sent, so it is one to sell.
        world.vendors[BOAR] = 75
        world.env.CaerdonWardrobe:RefreshItems("test")
        Equal(world.Status(BOAR), "sellable", "vendors: an outgrown ingredient vendors everywhere sell is sold, not sent")
        world.vendors[BOAR] = nil
        world.env.CaerdonWardrobe:RefreshItems("test")
        Equal(world.Status(BOAR), "send", "vendors: and sent again without them")

        -- Outgrown here and gray there: sold, unless a recipe the other toon knows is enough.
        world.rank = 170
        world.env.CaerdonWardrobe:RefreshItems("test")
        Equal(world.Status(WOLF), "sellable", "gray there: an ingredient nobody gets skill from is one to sell")
        iconConfig.IngredientsForOtherToons = "any"
        world.env.CaerdonWardrobe:RefreshItems("test")
        Equal(world.Status(WOLF), "send", "any use: one the other toon knows a recipe for is one to send")
        Equal(world.TooltipLines(WOLF), "Used in recipes of: Dorn (Cooking 100)", "any use: and the tooltip says which kind of use")
        Equal(world.TooltipLines(BOAR), "Gives skill to: Dorn (Cooking 100)", "any use: a toon that gets skill is named once")
        iconConfig.IngredientsForOtherToons = "skill"

        -- The option off: other toons are not looked at.
        iconConfig.ShowIngredientsForOtherToons = false
        world.env.CaerdonWardrobe:RefreshItems("test")
        Equal(world.Status(BOAR), "sellable", "send off: an outgrown ingredient is one to sell")
        Equal(world.Status(CLOTH), "", "send off: one of another toon's profession is left alone")
        Equal(world.TooltipLines(BOAR), "", "send off: and the tooltip names nobody")
        world.Errors("send")
    end

    ------------------------------------------------------------------------------------
    -- A profession with a skill line per expansion: the recorded colour decides
    ------------------------------------------------------------------------------------
    do
        local world = Start({ flavor = "retail", label = "lines", line = "Outland Cooking" })
        world.Open()
        Equal(world.Saved().Cooking.line, "Outland Cooking", "lines: the open line is recorded by its name")
        local info = world.Info(WOLF)
        Equal(info and info.recipes[1].reading, "known, gives skill (green)", "lines: a recipe is read by its recorded colour")
        Equal(info and info.recipes[1].rankNow, nil, "lines: and no rank is held against it")
        info = world.Info(BOAR)
        Check(info ~= nil and info.hasUse == false and info.recipes[1].reading == "known, gray", "lines: gray is no use")
        info = world.Info(SPIDER)
        Equal(info and info.recipes[1].reading, "not learned, would give skill (orange)", "lines: a recipe not learned likewise")
        -- The profession's rank is not the rank of the recipe's line, so it changes nothing.
        world.rank = 300
        world.env.CaerdonWardrobe:RefreshItems("test")
        Check(world.Info(WOLF).hasUse == true, "lines: the profession's rank is not held against a recipe's gray rank")
        Check(Has(world.Section(WOLF), "said at rank 150; read by the recorded colour"), "lines: and the export says how it was read")
        world.Errors("lines")
    end
end
