-- The food a hunter keeps for the pet (CaerdonFoodDrink.lua).
--
-- A hunter's food used to be kept whenever it sat within 20 item levels of the toon, however
-- much of it there was and whatever the pet eats. On a client that says what the pet eats
-- (C_PetInfo.CanPetEatItem, WoW Forever) the kinds kept for it are chosen instead from all
-- that is carried and that it eats, raw meat included: the best 20 pieces that fit in one or
-- two kinds, a piece counting for the square of its item level. Any other food is judged as for another
-- class. Without the answer (retail, or no pet seen yet) the level gap still decides.
--
-- The game is hand-made. Seen in a Forever client (1.60.1.70959, a hunter with a level 32 pet
-- that eats meat and fish): that the client answers true for a raw meat, and the bags of the
-- last case below. Not seen: what it answers for bread, or with no pet out.
--
-- Real code: the addon's item side and core, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 33 }

    local ON_USE = 44
    local function Food(name, level, minLevel, amount)
        return { name = name, quality = 1, level = level, minLevel = minLevel, type = "Consumable",
            subType = "Food & Drink", stack = 20, price = 25, classID = 0, subClassID = 5,
            tooltip = { { text = ("Use: Restores %d health over 27 sec.  Must remain seated while eating."):format(amount),
                type = ON_USE, r = 0, g = 1, b = 0 } } }
    end
    local function Meat(name, level)
        return { name = name, quality = 1, level = level, minLevel = 0, type = "Tradeskill", subType = "Cooking",
            stack = 20, price = 10, classID = 7, subClassID = 8 }
    end

    local BREAD, OLD_BREAD, KABOB = 960001, 960002, 960003
    local LEG, CROC, BEAR, BOAR = 960011, 960012, 960013, 960014
    local TIGER, WOLF, SPIDER, CLAM = 960015, 960016, 960017, 960018
    local ITEMS = {
        [BREAD] = Food("Spice Bread", 35, 25, 841),
        [OLD_BREAD] = Food("Old Bread", 15, 5, 243),
        [KABOB] = Food("Rat Kabob", 15, 5, 234),
        [LEG] = Meat("Spider Leg", 25),
        [CROC] = Meat("Crocolisk Meat", 23),
        [BEAR] = Meat("Bear Meat", 21),
        [BOAR] = Meat("Boar Meat", 5),
        [TIGER] = Meat("Tiger Meat", 30),
        [WOLF] = Meat("Wolf Flank", 19),
        [SPIDER] = Meat("Spider Meat", 15),
        [CLAM] = Meat("Clam Meat", 14),
    }
    -- The pet eats meat: the kabob and the raw meats, not bread.
    local EATS = { [KABOB] = true, [LEG] = true, [CROC] = true, [BEAR] = true, [BOAR] = true, [TIGER] = true,
        [WOLF] = true, [SPIDER] = true, [CLAM] = true }

    local function Start(flavor)
        local bags, petOut, asked = {}, false, 0
        local game = H.StockGame(TOON, ITEMS)
        game:Set("C_Container.GetContainerNumSlots", function(bag) return bag == 0 and #bags or 0 end)
        game:Set("C_Container.GetContainerItemID", function(bag, slot) return bag == 0 and bags[slot] and bags[slot].id or nil end)
        game:Set("C_Container.GetContainerItemLink", function(bag, slot)
            return bag == 0 and bags[slot] and game.Link(bags[slot].id) or nil
        end)
        game:Set("C_Item.GetItemCount", function(itemID)
            local count = 0
            for _, stack in ipairs(bags) do
                count = count + (stack.id == itemID and stack.count or 0)
            end
            return count
        end)
        game:Set("UnitExists", function(unit) return unit ~= "pet" or petOut end)
        if flavor == "forever" then
            game:Set("C_PetInfo.CanPetEatItem", function(itemID)
                asked = asked + 1
                return petOut and EATS[itemID] == true
            end)
            game:Set("C_PetInfo.GetPetFoodTypes", function() return petOut and { "Meat" } or {} end)
            game:Set("C_PetInfo.GetPetHappiness", function()
                if petOut then
                    return 3, 125, 20
                end
            end)
        end

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
        Equal(#client.errors, 0, flavor .. ": no error reached the error handler at the start")

        local world = { client = client, refreshes = 0 }
        local core = client.env.CaerdonWardrobe
        local refreshItems = core.RefreshItems
        function core:RefreshItems(...)
            world.refreshes = world.refreshes + 1
            return refreshItems(self, ...)
        end

        -- bags: { { itemID, count }, ... }, as the toon carries them.
        function world.Carry(stacks)
            bags = {}
            for index, stack in ipairs(stacks) do
                bags[index] = { id = stack[1], count = stack[2] }
            end
            client:Fire("BAG_UPDATE_DELAYED")
            client:Tick(5)
        end
        function world.Pet(out)
            petOut = out
            client:Fire("UNIT_PET", "player")
            client:Tick(5)
        end
        function world.Asked() return asked end
        function world.Status(itemID)
            local item = client.env.CaerdonItem:CreateFromItemID(itemID)
            local loaded = false
            item:ContinueOnItemLoad(function() loaded = true end)
            client:TickUntil(function() return loaded end, 10)
            local ready, status
            client:TickUntil(function()
                ready, status = item:GetCaerdonStatus()
                return ready
            end, 10)
            return status, item:GetFoodDrinkInfo()
        end
        function world.Kept(itemID)
            local state = client.env.CaerdonFoodDrink:GetPetFoodDebugState(itemID)
            return state and state.judged and state.kept
        end
        return world
    end

    local BAGS = { { BREAD, 11 }, { OLD_BREAD, 4 }, { KABOB, 7 }, { LEG, 7 }, { CROC, 6 }, { BEAR, 2 }, { BOAR, 12 } }

    ------------------------------------------------------------------------------------
    -- Forever: the client says what the pet eats
    ------------------------------------------------------------------------------------
    do
        local world = Start("forever")
        world.Carry(BAGS)

        -- No pet has been out: the level gap decides, as before (15 is within 20 of 33).
        local status, info = world.Status(KABOB)
        Equal(status, "collected", "no pet seen: food within the level gap is kept")
        Check(info.reason:find("hunter's pet still eats this", 1, true) ~= nil, "no pet seen: and the level gap is the reason")
        Equal((world.Status(OLD_BREAD)), "collected", "no pet seen: bread within the gap is kept too")
        Equal(world.Asked(), 0, "no pet seen: the client is not asked what a pet eats")

        -- The pet comes out. The two best meats are kept; the kabob is no longer needed.
        local before = world.refreshes
        world.Pet(true)
        Check(world.refreshes > before, "pet out: the kinds kept for it are new, so the items are judged again")
        status, info = world.Status(KABOB)
        Equal(status, "sellable", "pet out: food the pet has better than is outdated")
        Equal(info.reason, "better one carried, and the pet has better food", "pet out: and says why")
        status, info = world.Status(OLD_BREAD)
        Equal(status, "sellable", "pet out: food the pet does not eat is judged as for another class")
        Equal(info.reason, "better one carried, and the pet does not eat it", "pet out: and says why")
        Equal((world.Status(BREAD)), "collected", "pet out: the toon's best food stays")
        Equal(world.Kept(LEG), true, "pet out: the highest meat is kept")
        Equal(world.Kept(CROC), true, "pet out: and the next one, since the first is not a stack")
        Equal(world.Kept(BEAR), false, "pet out: a third kind is not")
        Equal(world.Kept(BOAR), false, "pet out: twelve pieces far below do not beat six just below")
        -- The ingredient rule asks this before it calls a raw meat outgrown.
        local food = world.client.env.CaerdonFoodDrink
        Check(food:IsKeptForPet(LEG) == true and food:IsKeptForPet(BEAR) == false and food:IsKeptForPet(BREAD) == false,
            "pet out: the kept kinds are told to the ingredient rule")
        -- Raw meat is not food to this module and gets no verdict from it, kept or not.
        Check((world.Status(BEAR)) ~= "sellable", "pet out: raw meat that is not kept is not marked by this rule")

        -- The pet goes away (dismissed, or the toon mounts): nothing changes.
        before = world.refreshes
        world.Pet(false)
        Equal(world.refreshes, before, "pet away: what it eats is remembered, nothing is judged again")
        Equal((world.Status(KABOB)), "sellable", "pet away: the verdict stays")
        Equal(world.Kept(LEG), true, "pet away: and so do the kept kinds")
        world.Pet(true)
        Equal(world.refreshes, before, "pet back: the same kinds, nothing is judged again")

        -- The meats are used up: the kabob is the best the pet has, and is kept.
        before = world.refreshes
        world.Carry({ { BREAD, 11 }, { OLD_BREAD, 4 }, { KABOB, 7 }, { BOAR, 12 } })
        Check(world.refreshes > before, "meats gone: the kept kinds changed, so the items are judged again")
        status, info = world.Status(KABOB)
        Equal(status, "collected", "meats gone: the kabob is kept for the pet")
        Equal(info.reason, "better food carried, but this is kept for the pet", "meats gone: and says why")
        Equal(world.Kept(BOAR), true, "meats gone: the second kind fills out the stack")

        -- A full stack needs no second kind.
        world.Carry({ { BREAD, 11 }, { KABOB, 7 }, { LEG, 20 }, { CROC, 6 } })
        Equal(world.Kept(LEG), true, "a full stack: kept")
        Equal(world.Kept(CROC), false, "a full stack: and nothing beside it")
        Equal((world.Status(KABOB)), "sellable", "a full stack: the kabob is outdated")

        -- A piece or two of the best food does not cost a stack of good food its place.
        world.Carry({ { BREAD, 11 }, { LEG, 1 }, { CROC, 2 }, { BEAR, 20 } })
        Equal(world.Kept(LEG), true, "crumbs: the single best piece is kept")
        Equal(world.Kept(BEAR), true, "crumbs: with the stack below it")
        Equal(world.Kept(CROC), false, "crumbs: and not the two pieces between")

        -- A change in the bags that leaves the kept kinds as they are judges nothing again.
        before = world.refreshes
        world.Carry({ { BREAD, 11 }, { LEG, 1 }, { CROC, 2 }, { BEAR, 19 } })
        Equal(world.refreshes, before, "a piece fed: the same kinds, nothing is judged again")

        -- The level outweighs the count. These are a Forever hunter's bags, where a plain count
        -- of item levels kept ten pieces of level 14 and dropped the four of level 30.
        world.Carry({ { BREAD, 11 }, { TIGER, 4 }, { CROC, 6 }, { BEAR, 2 }, { WOLF, 5 }, { SPIDER, 9 }, { KABOB, 7 },
            { CLAM, 10 }, { BOAR, 12 } })
        Equal(world.Kept(TIGER), true, "level before count: four pieces of the best food are kept")
        Equal(world.Kept(CROC), true, "level before count: with the six of the next")
        Equal(world.Kept(CLAM), false, "level before count: ten pieces far below take no place")
        -- Between kinds of about one level the count still decides.
        world.Carry({ { BREAD, 11 }, { TIGER, 4 }, { CROC, 6 }, { BEAR, 20 } })
        Equal(world.Kept(TIGER), true, "near levels: the best food is kept")
        Equal(world.Kept(BEAR), true, "near levels: with the stack two levels below the six pieces")
        Equal(world.Kept(CROC), false, "near levels: and not the six")

        Equal(#world.client.errors, 0, "forever: no error reached the error handler")
        for _, message in ipairs(world.client.errors) do
            print("        error: " .. tostring(message))
        end
    end

    ------------------------------------------------------------------------------------
    -- Retail: the client cannot say, so the level gap decides whatever pet is out
    ------------------------------------------------------------------------------------
    do
        local world = Start("retail")
        world.Carry(BAGS)
        world.Pet(true)
        local status, info = world.Status(KABOB)
        Equal(status, "collected", "retail: food within the level gap is kept")
        Check(info.reason:find("hunter's pet still eats this", 1, true) ~= nil, "retail: and the level gap is the reason")
        Equal(world.client.env.CaerdonFoodDrink:GetPetFoodDebugState(KABOB), nil, "retail: the export has no pet food section")
        Equal(#world.client.errors, 0, "retail: no error reached the error handler")
        for _, message in ipairs(world.client.errors) do
            print("        error: " .. tostring(message))
        end
    end
end
