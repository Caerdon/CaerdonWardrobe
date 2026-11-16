-- What the equipment path asks the client, and how often.
--
-- A piece of equipment is the most expensive thing the addon draws, and most of that was the
-- same work done again: the transmog info computed for the status and once more for the draw,
-- the item's level, PVP floor and uniqueness read by every upgrade helper for itself, every
-- equipment set walked for every button, and a source whose item the client refuses asked
-- about after every refresh. This scenario counts the questions, and checks that the answers
-- are still used: a count that drops because a helper stopped looking would pass a count alone.
--
-- The game is hand-made (tools/harness/game.lua) with worn pieces, a bag and equipment sets
-- added here. It proves what the code asks and decides, and nothing about a client.
--
-- Real code: the addon's item side and its core's ProcessItem, Blizzard's base files from the
-- mirror. The drawing is replaced.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 29 }

    local PVP_FLOOR = "Equip: Increases item level to a minimum of %d in Arenas and Battlegrounds."

    local function Armor(name, slot, level, appearance, more)
        local item = { name = name, quality = 2, level = level, minLevel = 20, type = "Armor", subType = "Leather",
            stack = 1, equipLoc = slot, price = 500, classID = 4, subClassID = 2, bindType = 2,
            tooltip = { { text = "Binds when equipped", type = 20, bonding = 2 } }, appearance = appearance }
        for key, value in pairs(more or {}) do
            item[key] = value
        end
        return item
    end

    local function Items()
        return {
            -- Judged against the worn gloves. Both carry a PVP floor, and only with the floors
            -- is the lower piece the better one (30 against 25, where the levels say 15 and 20).
            [920001] = Armor("Field Gloves", "INVTYPE_HAND", 15, { appearanceID = 5201, sourceID = 7201, collected = true },
                { tooltip = { { text = "Binds when equipped", type = 20, bonding = 2 }, { text = PVP_FLOOR:format(30) } } }),
            [920002] = Armor("Worn Gloves", "INVTYPE_HAND", 20, { appearanceID = 5202, sourceID = 7202, collected = true },
                { tooltip = { { text = PVP_FLOOR:format(25) } } }),
            -- An auction row's item: its link says level 10, the row says otherwise.
            [920003] = Armor("Listed Boots", "INVTYPE_FEET", 10, { appearanceID = 5203, sourceID = 7203, collected = true }),
            [920004] = Armor("Worn Boots", "INVTYPE_FEET", 20, { appearanceID = 5204, sourceID = 7204, collected = true }),
            -- In the bag: two copies of a helm that equipment sets name, and one they do not.
            [920005] = Armor("Set Helm", "INVTYPE_HEAD", 20, { appearanceID = 5205, sourceID = 7205, collected = true }),
            [920006] = Armor("Spare Helm", "INVTYPE_HEAD", 20, { appearanceID = 5206, sourceID = 7206, collected = true }),
            -- A look with two more sources, whose items this client cannot load.
            [920010] = Armor("Shared Vest", "INVTYPE_CHEST", 20, { appearanceID = 5210, sourceID = 7210 }),
            [920011] = Armor("Ghost Vest", "INVTYPE_CHEST", 20, { appearanceID = 5210, sourceID = 7211 }),
            [920012] = Armor("Lost Vest", "INVTYPE_CHEST", 20, { appearanceID = 5210, sourceID = 7212 }),
        }
    end

    local WORN = { [10] = 920002, [8] = 920004 }
    local BAG = { [1] = 920005, [2] = 920005, [3] = 920006 }
    -- Set 11 names both copies of the helm and a worn piece, set 12 one copy, set 13 has no
    -- locations to give.
    local SETS = {
        { id = 11, name = "Alpha", locations = { [1] = "bag1", [11] = "bag2", [10] = "worn10" } },
        { id = 12, name = "Beta", locations = { [1] = "bag1" } },
        { id = 13, name = "Gamma" },
    }
    local LOCATIONS = {
        bag1 = { isBags = true, bag = 0, slot = 1 },
        bag2 = { isBags = true, bag = 0, slot = 2 },
        worn10 = { isPlayer = true, slot = 10 },
    }

    local function ItemIDOf(reference)
        if type(reference) == "number" then
            return reference
        elseif type(reference) == "string" then
            return tonumber(reference:match("item:(%d+)")) or tonumber(reference)
        end
    end

    -- A client that plays the game. debug: the addon's Enable debug setting.
    local function Start(debug)
        local items = Items()
        local game = H.StockGame(TOON, items)
        local world = { game = game, counts = {} }

        -- Every call of a game function, counted under its name and its first argument (an
        -- item's ID for a link). numbersOnly: only calls made with a bare number.
        local function Counted(name, numbersOnly)
            local original = game.names[name]
            game:Set(name, function(first, ...)
                if not numbersOnly or type(first) == "number" then
                    local key = name .. " " .. tostring(ItemIDOf(first) or first)
                    world.counts[key] = (world.counts[key] or 0) + 1
                end
                return original(first, ...)
            end)
        end

        local function Place(location)
            if type(location) ~= "table" then
                return nil
            elseif location.IsEquipmentSlot and location:IsEquipmentSlot() then
                return WORN[location:GetEquipmentSlot()]
            elseif location.IsBagAndSlot and location:IsBagAndSlot() then
                local bag, slot = location:GetBagAndSlot()
                return bag == 0 and BAG[slot] or nil
            end
        end
        local hyperlink = game.names["C_TooltipInfo.GetHyperlink"]
        game:Set("C_Item.DoesItemExist", function(location) return Place(location) ~= nil end)
        game:Set("C_Item.GetItemLink", function(location) return Place(location) and game.Link(Place(location)) end)
        game:Set("C_Item.GetItemID", function(location) return Place(location) end)
        game:Set("C_Item.GetItemQuality", function(location) return Place(location) and items[Place(location)].quality end)
        game:Set("C_Item.GetItemName", function(location) return Place(location) and items[Place(location)].name end)
        game:Set("C_Item.IsBound", function() return false end)
        -- world.levelInSlot: a bag slot whose copy has another level than its link says.
        game:Set("C_Item.GetCurrentItemLevel", function(location)
            local id = Place(location)
            if id and world.levelInSlot and location:IsBagAndSlot() then
                local _, slot = location:GetBagAndSlot()
                if world.levelInSlot[slot] then
                    return world.levelInSlot[slot]
                end
            end
            return id and items[id].level
        end)
        game:Set("C_Container.GetContainerNumSlots", function(bag) return bag == 0 and 4 or 0 end)
        game:Set("C_Container.GetContainerItemID", function(bag, slot) return bag == 0 and BAG[slot] or nil end)
        game:Set("C_Container.GetContainerItemLink", function(bag, slot)
            return bag == 0 and BAG[slot] and game.Link(BAG[slot]) or nil
        end)
        game:Set("C_TooltipInfo.GetInventoryItem", function(_, slot) return WORN[slot] and hyperlink(game.Link(WORN[slot])) end)
        game:Set("C_TooltipInfo.GetBagItem", function(bag, slot) return BAG[slot] and hyperlink(game.Link(BAG[slot])) end)

        -- Asked when only one of two pieces has a PVP floor: the toon is in no PVP place.
        game:Set("GetInstanceInfo", function() return "Elsewhere", "none" end)
        game:Set("C_PvP.IsWarModeDesired", function() return false end)

        game:Set("C_EquipmentSet.CanUseEquipmentSets", function() return true end)
        game:Set("C_EquipmentSet.GetEquipmentSetIDs", function()
            local ids = {}
            for index, set in ipairs(SETS) do ids[index] = set.id end
            return ids
        end)
        local function Set(id)
            for _, set in ipairs(SETS) do
                if set.id == id then return set end
            end
        end
        game:Set("C_EquipmentSet.GetEquipmentSetInfo", function(id) return Set(id).name, 134400, id, false, 3, 0, 3, 0, 0 end)
        game:Set("C_EquipmentSet.GetItemLocations", function(id) return Set(id).locations end)
        game:Set("EquipmentManager_GetLocationData", function(location) return LOCATIONS[location] end)

        -- The lost vest cannot be loaded; the ghost loads here and is refused when asked about
        -- (the scenario fires that event itself).
        game:Set("C_Item.RequestLoadItemDataByID", function(id)
            local client = game.client
            client.env.C_Timer.After(0, function()
                client:Fire("ITEM_DATA_LOAD_RESULT", ItemIDOf(id), items[ItemIDOf(id)] ~= nil and ItemIDOf(id) ~= 920012)
            end)
        end)

        Counted("C_TooltipInfo.GetHyperlink")
        Counted("C_Item.GetDetailedItemLevelInfo")
        Counted("C_Item.GetItemUniquenessByID")
        Counted("C_EquipmentSet.GetItemLocations")
        Counted("C_TransmogCollection.GetSourceInfo")
        Counted("C_Item.GetItemInfo", true)
        Counted("C_Item.GetItemInfoInstant", true)
        Counted("C_Item.GetItemSpecInfo", true)

        local client = H.Client.New({ flavor = "forever", provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        local config = H.DeepCopy(namespace:GetDefaultConfig())
        config.Debug.Enabled = debug and true or false
        rawset(client.env, "CaerdonWardrobeConfig", config)
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)
        world.client, world.env = client, client.env

        -- Every GetTransmogInfo from here on. Item data copies its methods when it is made,
        -- so the count is put in before any item is.
        world.transmogInfos = 0
        local getTransmogInfo = client.env.CaerdonEquipmentMixin.GetTransmogInfo
        client.env.CaerdonEquipmentMixin.GetTransmogInfo = function(...)
            world.transmogInfos = world.transmogInfos + 1
            return getTransmogInfo(...)
        end
        return world
    end

    local function Count(world, name, key)
        return world.counts[name .. " " .. tostring(key)] or 0
    end

    local function Loaded(world, item)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        world.client:TickUntil(function() return loaded end, 10)
        return loaded and item or nil
    end

    local function Load(world, itemID)
        return Loaded(world, world.env.CaerdonItem:CreateFromItemID(itemID))
    end

    -- ready, status, binding text, binding result, transmog info
    local function Status(world, item)
        local ready, status, binding, result, info
        world.client:TickUntil(function()
            ready, status, binding, result, info = item:GetCaerdonStatus()
            return ready
        end, 10)
        return ready and status or "<not ready>", binding, info
    end

    local function NoErrors(world, label)
        Equal(#world.client.errors, 0, label .. ": no error reached the error handler")
        for _, message in ipairs(world.client.errors) do
            Check(false, label .. ": " .. message)
        end
    end

    local world = Start(false)
    local env, client = world.env, world.client
    NoErrors(world, "start")
    Equal(env.PVP_ITEM_LEVEL_TOOLTIP, PVP_FLOOR, "start: the PVP floor line is the one this client's listing has")
    local core = env.CaerdonWardrobe
    Check(type(core) == "table" and type(core.ProcessItem) == "function", "start: the core is there")

    --------------------------------------------------------------------------------------
    -- 1. The item's own facts are read once, and each helper still uses them
    --------------------------------------------------------------------------------------

    do
        local gloves = Load(world, 920001)
        Check(gloves ~= nil, "once: the gloves load")
        world.counts = {}
        local info = gloves and gloves:GetItemData():GetTransmogInfo() or {}
        Equal(Count(world, "C_TooltipInfo.GetHyperlink", 920001), 1, "once: the item's tooltip is fetched once for its PVP floor")
        Equal(Count(world, "C_Item.GetDetailedItemLevelInfo", 920001), 1, "once: its item level is read once")
        Equal(Count(world, "C_Item.GetItemUniquenessByID", 920001), 1, "once: its uniqueness is read once")
        -- Level 15 against a worn 20: only the floors (30 against 25) make it the better piece.
        Equal(info.betterItemEquipped, false, "once: the comparison with the worn piece used the floor")
        Equal(info.equalItemLevelEquipped, false, "once: so did the test for a tie")
        Equal(info.upgradeItemLevelDelta, 5, "once: and the level gain")
        Equal(info.isUpgrade, true, "once: which makes it an upgrade")
    end

    --------------------------------------------------------------------------------------
    -- 2. One transmog info per item and refresh, shared by the status and the draw
    --------------------------------------------------------------------------------------

    do
        local drawn
        function core:SetItemButtonStatus(button, item, feature, locationInfo, options, status, bindingStatus, transmogInfo)
            drawn = { status = status, transmogInfo = transmogInfo }
        end
        function core:SetItemButtonMogStatusFilter() end
        function core:SetItemButtonBindType() end
        function core:SetButtonRefreshGeneration() end

        world.transmogInfos = 0
        local first = Load(world, 920001)
        local status, _, info = Status(world, first)
        Equal(status, "upgrade", "memo: the gloves are an upgrade")
        Equal(world.transmogInfos, 1, "memo: the status computed the transmog info once")
        Check(type(info) == "table" and info.upgradeItemLevelDelta == 5, "memo: and hands it back with the verdict")

        -- Another copy of the same link, as a second button would hold.
        local second = Load(world, 920001)
        local secondStatus, _, secondInfo = Status(world, second)
        Equal(secondStatus, "upgrade", "memo: a second copy gets the same verdict")
        Equal(world.transmogInfos, 1, "memo: without computing the transmog info again")
        Check(secondInfo == info, "memo: it is handed the same table")

        core:ProcessItem({}, second, nil, nil, {})
        Check(drawn ~= nil, "memo: the draw reached the drawing")
        Equal(world.transmogInfos, 1, "memo: a draw computes no transmog info of its own")
        Check(drawn ~= nil and drawn.transmogInfo == info, "memo: the drawing is given the table the verdict was made from")
        Equal(drawn and drawn.status, "upgrade", "memo: with that verdict")
        Equal(drawn and drawn.transmogInfo and drawn.transmogInfo.upgradeStatus, "upgrade",
            "memo: and the upgrade verdict for the badge on it")

        core:RefreshItems()
        local third = Load(world, 920001)
        local _, _, thirdInfo = Status(world, third)
        Equal(world.transmogInfos, 2, "memo: after a refresh it is computed again")
        Check(type(thirdInfo) == "table" and thirdInfo ~= info, "memo: into a table of its own")
        NoErrors(world, "memo")
    end

    --------------------------------------------------------------------------------------
    -- 3. What a window says about a row beyond its link is part of the verdict's key
    --------------------------------------------------------------------------------------

    do
        local link = world.game.Link(920003)
        local low = Loaded(world, env.CaerdonItem:CreateFromItemLink(link, { overrideItemLevel = 10 }))
        local high = Loaded(world, env.CaerdonItem:CreateFromItemLink(link, { overrideItemLevel = 40 }))
        Check(low ~= nil and high ~= nil, "row: both rows load")
        local lowStatus, _, lowInfo = Status(world, low)
        local highStatus, _, highInfo = Status(world, high)
        Check(lowStatus ~= "upgrade", "row: level 10 against a worn 20 is no upgrade (" .. tostring(lowStatus) .. ")")
        Equal(highStatus, "upgrade", "row: the same link listed at level 40 is one")
        Equal(highInfo and highInfo.upgradeItemLevelDelta, 20, "row: with its own level gain")
        Check(lowInfo ~= highInfo, "row: the two rows do not share a transmog info")
        local again = Loaded(world, env.CaerdonItem:CreateFromItemLink(link, { overrideItemLevel = 40 }))
        local _, _, againInfo = Status(world, again)
        Check(againInfo == highInfo, "row: a second row at the same level does")
        NoErrors(world, "row")
    end

    --------------------------------------------------------------------------------------
    -- 4. Equipment sets: one walk per frame, the answers as before
    --------------------------------------------------------------------------------------

    do
        local function SetWalks()
            return Count(world, "C_EquipmentSet.GetItemLocations", 11) + Count(world, "C_EquipmentSet.GetItemLocations", 12)
                + Count(world, "C_EquipmentSet.GetItemLocations", 13)
        end
        local helm, spare, worn = Load(world, 920005), Load(world, 920006), Load(world, 920002)
        client:Tick(1)
        world.counts = {}

        local names = helm:GetItemData():GetEquipmentSets()
        Check(type(names) == "table", "sets: the helm is in sets")
        Equal(names and #names, 2, "sets: in two of them, the one that names both copies counted once")
        Equal(names and names[1], "Alpha", "sets: in the order of the client's list")
        Equal(names and names[2], "Beta", "sets: the second")
        Equal(spare:GetItemData():GetEquipmentSets(), nil, "sets: a piece no set names has none")
        Equal(worn:GetItemData():GetEquipmentSets(), nil, "sets: a set's worn piece is not listed, as before")
        Equal(SetWalks(), 3, "sets: three items asked in one frame, every set walked once")

        local _, binding = Status(world, Load(world, 920005))
        Equal(binding, "*Alpha", "sets: the binding text is the first set's name, starred for more than one")

        client:Tick(1)
        world.counts = {}
        helm:GetItemData():GetEquipmentSets()
        Equal(SetWalks(), 3, "sets: the next frame walks them again")
        spare:GetItemData():GetEquipmentSets()
        Equal(SetWalks(), 3, "sets: once")
        env.CaerdonEquipment:InvalidateCaches()
        helm:GetItemData():GetEquipmentSets()
        Equal(SetWalks(), 6, "sets: emptying the caches drops the index within a frame")
        NoErrors(world, "sets")
    end

    --------------------------------------------------------------------------------------
    -- 5. A source whose item the client refuses is asked about once, not after every refresh
    --------------------------------------------------------------------------------------

    local function Asked(which, sourceID)
        return Count(which, "C_TransmogCollection.GetSourceInfo", sourceID)
    end

    do
        local function VestStatus()
            return (Status(world, Load(world, 920010)))
        end
        world.counts = {}
        Equal(VestStatus(), "own", "refused: the vest is a look to learn")
        Check(Asked(world, 7210) >= 1 and Asked(world, 7211) == 1 and Asked(world, 7212) == 1,
            "refused: the first verdict asks about every source of the look")
        -- With debug off that is all: nothing is asked about the sources' items.
        local aboutItems = 0
        for _, itemID in ipairs({ 920011, 920012 }) do
            aboutItems = aboutItems + Count(world, "C_Item.GetItemInfo", itemID)
                + Count(world, "C_Item.GetItemInfoInstant", itemID) + Count(world, "C_Item.GetItemSpecInfo", itemID)
        end
        Equal(aboutItems, 0, "refused: without debug no question is put about a source's item")
        -- The verdict does not wait for the sources' items; the failed load comes a frame later.
        client:Tick(2)
        Equal(env.CaerdonEquipment.failedSourceItemLoads[920012], true, "refused: the item that failed to load is on record")

        -- The item that failed to load is known at once; the other is not known yet.
        world.counts = {}
        core:RefreshItems()
        Equal(VestStatus(), "own", "refused: the same verdict after a refresh")
        Equal(Asked(world, 7212), 0, "refused: the source of the item that failed to load is not asked about again")
        Equal(Asked(world, 7211), 1, "refused: a source nothing was said about is")
        Check(Asked(world, 7210) >= 1, "refused: and so is the item's own")

        -- The client says it has no such item.
        client:Fire("GET_ITEM_INFO_RECEIVED", 920011, false)
        Equal(env.CaerdonEquipment.refusedItems[920011], true, "refused: the refusal is on record")
        client:Fire("GET_ITEM_INFO_RECEIVED", 920010, true)
        Equal(env.CaerdonEquipment.refusedItems[920010], nil, "refused: an item that was answered is not")
        world.counts = {}
        core:RefreshItems()
        Equal(VestStatus(), "own", "refused: the same verdict once the refusal is known")
        Equal(Asked(world, 7211), 0, "refused: the refused item's source is not asked about again")
        Equal(Asked(world, 7212), 0, "refused: nor the other")
        Check(Asked(world, 7210) >= 1, "refused: the item's own still is")

        -- A change of the collection: everything is asked for once more, then kept again.
        world.counts = {}
        client:Fire("TRANSMOG_COLLECTION_UPDATED")
        Equal(VestStatus(), "own", "refused: the same verdict after the collection changed")
        Equal(Asked(world, 7211), 1, "refused: a collection change asks about the refused source again")
        Equal(Asked(world, 7212), 1, "refused: and the other")
        world.counts = {}
        core:RefreshItems()
        VestStatus()
        Equal(Asked(world, 7211) + Asked(world, 7212), 0, "refused: the refresh after it keeps them again")

        -- The recorder's way to a run that asks for everything.
        world.counts = {}
        env.CaerdonItem:InvalidateStatusCache()
        env.CaerdonEquipment:InvalidateCaches()
        env.CaerdonEquipment:ForgetRefusedItems()
        VestStatus()
        Equal(Asked(world, 7211), 1, "refused: forgetting them asks about the refused source again")
        Equal(Asked(world, 7212), 1, "refused: and the other")
        Equal(env.CaerdonEquipment.refusedItems[920011], nil, "refused: and the refusal is off the record")
        NoErrors(world, "refused")
    end

    --------------------------------------------------------------------------------------
    -- 6. With debug on the details ask about each source's item, but not a refused one twice
    --------------------------------------------------------------------------------------

    do
        local debug = Start(true)
        NoErrors(debug, "debug: start")
        local function VestInfo()
            local _, _, info = Status(debug, Load(debug, 920010))
            return info or {}
        end
        debug.counts = {}
        local info = VestInfo()
        local details = info.forDebugUseOnly
        Check(type(details) == "table", "debug: the details are there")
        Equal(details and #(details.appearanceSources or {}), 3, "debug: with the look's three sources")
        Equal(details and details.lowestLevelFound, 20, "debug: and the lowest level among them")
        Equal(Count(debug, "C_Item.GetItemInfo", 920011), 1, "debug: a source's item is asked for its level")
        Equal(Count(debug, "C_Item.GetItemSpecInfo", 920011), 0, "debug: nothing asks for a source item's specializations")

        debug.client:Fire("GET_ITEM_INFO_RECEIVED", 920011, false)
        debug.counts = {}
        debug.env.CaerdonWardrobe:RefreshItems()
        VestInfo()
        Equal(Count(debug, "C_Item.GetItemInfo", 920011), 0, "debug: a refused item is not asked for its level again")
        Equal(Asked(debug, 7211), 0, "debug: nor is its source asked about")

        -- After a collection change the source is asked about again, its item still is not.
        debug.counts = {}
        debug.client:Fire("TRANSMOG_COLLECTION_UPDATED")
        local after = VestInfo().forDebugUseOnly
        Equal(Asked(debug, 7211), 1, "debug: a collection change asks about the source again")
        Equal(Count(debug, "C_Item.GetItemInfo", 920011), 0, "debug: and still not about the refused item's level")
        Equal(after and #(after.appearanceSources or {}), 3, "debug: the details still list every source")
        NoErrors(debug, "debug")
    end

    --------------------------------------------------------------------------------------
    -- 7. The test addon's two contracts for what this path takes for granted in a client
    --------------------------------------------------------------------------------------

    do
        local third = Start(false)
        local wanted = { ["Core.lua"] = true, ["Runner.lua"] = true, ["Contracts.lua"] = true, ["Plan.lua"] = true,
            ["Facts.lua"] = true }
        local T = H.LoadAddon(third.client, "CaerdonWardrobe_Tests", H.addonDir .. "/CaerdonWardrobe_Tests",
            function(relative) return not wanted[relative] end)
        third.client:Fire("ADDON_LOADED", "CaerdonWardrobe_Tests")
        third.client:Fire("PLAYER_LOGIN")

        local function Run(id)
            T.RunTests({ match = id, force = true })
            Check(third.client:TickUntil(function() return not T.IsBusy() end, 120), "contract: the job ends (" .. id .. ")")
            return (T.db.contracts["1.60.1.70938"] or {})[id] or {}
        end

        -- A piece's transmog info for its bag slot and for its bare link.
        local kept = Run("equipment.keptInfo")
        Equal(kept.status, "pass", "contract: slot and link agree for every piece in the bag (" .. tostring(kept.message) .. ")")
        Equal(kept.detail and kept.detail.pieces, 3, "contract: three pieces in the bag")
        Equal(kept.detail and kept.detail.differing, 0, "contract: none differs")

        -- The copy in slot 3 is five levels above what its link says.
        third.levelInSlot = { [3] = 25 }
        local differs = Run("equipment.keptInfo")
        Equal(differs.status, "fail", "contract: a copy whose slot says another level fails it")
        Equal(differs.detail and differs.detail.differing, 1, "contract: that one piece")
        local example = differs.detail and differs.detail.examples and differs.detail.examples[1] or {}
        Equal(example.slot, 3, "contract: named by its slot")
        Check(table.concat(example.fields or {}, "; "):find("upgradeItemLevelDelta: 25 in the slot, 20 for the link", 1, true) ~= nil,
            "contract: with the field and both values (" .. table.concat(example.fields or {}, "; ") .. ")")
        third.levelInSlot = nil

        -- GetTime() within a frame. The mocked clock stands still, stopwatch included.
        local frame = Run("client.frameTime")
        Equal(frame.status, "skip", "contract: a stopwatch that does not move is no answer (" .. tostring(frame.message) .. ")")
        local env = third.env
        local getTime, getPrecise = env.GetTime, env.GetTimePreciseSec
        local stopwatch = third.client.clock
        rawset(env, "GetTimePreciseSec", function()
            stopwatch = stopwatch + 0.0005
            return stopwatch
        end)
        frame = Run("client.frameTime")
        Equal(frame.status, "pass", "contract: a clock that stands still while the stopwatch runs passes (" .. tostring(frame.message) .. ")")
        local moving = third.client.clock
        rawset(env, "GetTime", function()
            moving = moving + 0.001
            return moving
        end)
        frame = Run("client.frameTime")
        Equal(frame.status, "fail", "contract: a clock that moves within the frame fails")
        rawset(env, "GetTime", getTime)
        rawset(env, "GetTimePreciseSec", getPrecise)
        NoErrors(third, "contracts")
    end
end
