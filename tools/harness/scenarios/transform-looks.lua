-- A piece whose own look is known, and which would have a look the collection lacks once it
-- is raised on its upgrade track or converted at the Catalyst (CaerdonTransformLooks.lua and
-- the equipment branch of GetCaerdonStatus).
--
-- Such a piece read "collected" and from there "sellable" or an auction icon. It is one to
-- keep: "transform", a quiet mark of its own in place of "collected". An upgrade keeps its
-- arrow, a gear set's piece its set's mark, and with the setting off
-- (Icon.ShowLooksAfterChange) nothing is asked.
--
-- The game is hand-made, after how the client is understood to answer; no client has been
-- asked. What it models:
--   - an item has a source per difficulty (itemModID 4, 0, 1, 3), their IDs side by side;
--   - C_Item.GetItemUpgradeInfo names the track by trackStringID 972 / 973 / 974 / 978, and a
--     past season's piece keeps a track with no ranks;
--   - the Catalyst's answer is asked of a copy, and the converted piece's icon may come later;
--   - a link with another item's ID in it gets that item's source for the link's bonuses
--     (told here by the name in the link, since the stock link has no bonus IDs).
--
-- Real code: the addon's item side, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Druid", classFile = "DRUID", race = "Tauren",
        faction = "Horde", level = 90 }
    local DRUID, DRUID_MASK = 11, 2 ^ 10
    local UPGRADE_LINE = 32

    local ITEMS, SOURCES, BY_ITEM = {}, {}, {}
    -- sources: { [itemModID] = { sourceID, appearanceID, collected } }
    local function Piece(id, name, slot, mod, sources, more)
        local item = { name = name, quality = 4, level = 250, minLevel = 80, type = "Armor", subType = "Leather",
            stack = 1, equipLoc = slot, price = 90000, classID = 4, subClassID = 2, bindType = 1, mod = mod,
            icon = id - 400000, tooltip = { { text = "+40 Agility" } } }
        for key, value in pairs(more or {}) do
            item[key] = value
        end
        ITEMS[id] = item
        BY_ITEM[id] = {}
        for sourceMod, source in pairs(sources) do
            SOURCES[source[1]] = { item = id, mod = sourceMod, look = source[2], collected = source[3] == true,
                valid = not (more and more.unusable) }
            BY_ITEM[id][sourceMod] = source[1]
        end
        -- The stock game takes an item with this field for one that can be worn for its look.
        local own = SOURCES[BY_ITEM[id][mod]]
        item.appearance = { appearanceID = own.look, sourceID = BY_ITEM[id][mod], collected = own.collected }
        return item
    end
    local function Track(id, level, highest) return { trackStringID = id, level = level, max = highest } end
    local VETERAN, CHAMPION, HERO, MYTH = 972, 973, 974, 978

    -- Pieces in the bags. Every look of their own is known.
    Piece(930001, "Champion Bracers", "INVTYPE_WRIST", 0,
        { [4] = { 5001, 801, true }, [0] = { 5002, 802, true }, [1] = { 5003, 803 }, [3] = { 5004, 804 } },
        { track = Track(CHAMPION, 2, 6) })
    Piece(930002, "Hero Belt", "INVTYPE_WAIST", 1,
        { [0] = { 5006, 806, true }, [1] = { 5007, 807, true }, [3] = { 5008, 808 } },
        { track = Track(HERO, 6, 6) })
    Piece(930003, "Veteran Cloak", "INVTYPE_CLOAK", 4,
        { [4] = { 5011, 811, true }, [0] = { 5012, 812 } }, { track = Track(VETERAN, 3, 8) })
    Piece(930004, "Myth Helm", "INVTYPE_HEAD", 3, { [1] = { 5015, 815 }, [3] = { 5016, 816, true } },
        { track = Track(MYTH, 1, 6) })
    Piece(930005, "Champion Vest", "INVTYPE_ROBE", 0, { [0] = { 5021, 821, true } },
        { track = Track(CHAMPION, 2, 6) })
    Piece(930006, "Champion Legs", "INVTYPE_LEGS", 0, { [0] = { 5026, 826, true } },
        { track = Track(CHAMPION, 2, 6) })
    Piece(930007, "Hero Gloves", "INVTYPE_HAND", 1, { [1] = { 5031, 831, true } }, { track = Track(HERO, 6, 6) })
    Piece(930008, "Champion Boots", "INVTYPE_FEET", 0, { [0] = { 5036, 836, true } },
        { track = Track(CHAMPION, 6, 6) })
    Piece(930009, "Old Shoulders", "INVTYPE_SHOULDER", 0, { [0] = { 5041, 841, true } },
        { track = Track(CHAMPION, 0, 0) })
    Piece(930010, "Faded Bracers", "INVTYPE_WRIST", 0, { [0] = { 5046, 846, true }, [1] = { 5047, 847 } },
        { track = Track(CHAMPION, 2, 6),
            tooltip = { { text = "Upgrade Level: Champion 2/6", type = UPGRADE_LINE, r = 0.5, g = 0.5, b = 0.5 } } })
    Piece(930011, "Champion Mantle", "INVTYPE_SHOULDER", 0, { [0] = { 5051, 851, true } },
        { track = Track(CHAMPION, 6, 6) })
    -- Its own look is not known: a look to learn before anything here is asked.
    Piece(930012, "New Hood", "INVTYPE_HEAD", 0, { [0] = { 5056, 856 }, [1] = { 5057, 857 } },
        { track = Track(CHAMPION, 2, 6) })
    -- Better than what is worn, with a look to gain by raising it.
    Piece(930013, "Champion Girdle", "INVTYPE_WAIST", 0, { [0] = { 5061, 861, true }, [1] = { 5062, 862 } },
        { track = Track(CHAMPION, 2, 6), level = 400 })
    -- A piece the toon's class cannot use, with a look to gain by raising it.
    Piece(930015, "Plate Bracers", "INVTYPE_WRIST", 0, { [0] = { 5071, 871, true }, [1] = { 5072, 872 } },
        { track = Track(CHAMPION, 2, 6), unusable = true })
    -- No season's piece: no upgrade info at all.
    Piece(930014, "Plain Bracers", "INVTYPE_WRIST", 0, { [0] = { 5066, 866, true } })
    -- Another item with the cloak's Normal look, which is known from it.
    Piece(930090, "Other Cloak", "INVTYPE_CLOAK", 0, { [0] = { 5090, 812, true } })

    -- The class set of the season being played, and the one before it: a piece per slot, a
    -- source per difficulty. Collected marks which of the four are known.
    local function SetPiece(id, name, slot, firstSource, firstLook, known)
        return Piece(id, name, slot, 0, {
            [4] = { firstSource, firstLook, known[4] }, [0] = { firstSource + 1, firstLook + 1, known[0] },
            [1] = { firstSource + 2, firstLook + 2, known[1] }, [3] = { firstSource + 3, firstLook + 3, known[3] },
        })
    end
    SetPiece(940005, "Set Vest", "INVTYPE_CHEST", 6001, 901, {})
    SetPiece(940006, "Set Legs", "INVTYPE_LEGS", 6011, 911, { [0] = true })
    SetPiece(940007, "Set Gloves", "INVTYPE_HAND", 6021, 921, { [1] = true })
    SetPiece(940008, "Set Boots", "INVTYPE_FEET", 6031, 931, {})
    SetPiece(940011, "Set Mantle", "INVTYPE_SHOULDER", 6041, 941, {})
    SetPiece(941008, "Old Set Boots", "INVTYPE_FEET", 6131, 961, { [0] = true, [1] = true })
    SetPiece(941011, "Old Set Mantle", "INVTYPE_SHOULDER", 6141, 971, {})
    local NEW_SET, OLD_SET = { 940005, 940006, 940007, 940008, 940011 }, { 941008, 941011 }
    local SET_MODS = { 4, 0, 1, 3 }
    local SETS = {}
    for index, mod in ipairs(SET_MODS) do
        SETS[#SETS + 1] = { setID = 7000 + index, baseSetID = index > 1 and 7001 or nil, classMask = DRUID_MASK,
            patchID = 120100, name = "New Set", pieces = NEW_SET, mod = mod }
        SETS[#SETS + 1] = { setID = 6900 + index, baseSetID = index > 1 and 6901 or nil, classMask = DRUID_MASK,
            patchID = 120000, name = "Old Set", pieces = OLD_SET, mod = mod }
    end
    -- A set of the class with one source per piece, newer than both, and another class's set.
    Piece(942008, "Shop Boots", "INVTYPE_FEET", 0, { [0] = { 6201, 981 } })
    SETS[#SETS + 1] = { setID = 7100, classMask = DRUID_MASK, patchID = 120105, name = "Shop Set", pieces = { 942008 },
        mod = 0 }
    SETS[#SETS + 1] = { setID = 7200, classMask = 2 ^ 3, patchID = 120105, name = "Rogue Set", pieces = NEW_SET, mod = 0 }
    -- A set of the class with two items for the feet, the newest of all. Each has an icon of
    -- its own, which tells them apart.
    SETS[#SETS + 1] = { setID = 7300, classMask = DRUID_MASK, patchID = 120110, name = "Twin Set",
        pieces = { 940008, 941008 }, mod = 0 }
    -- A set that lists a second item with the set gloves' icon and one of their looks: the
    -- gloves with a source per difficulty are the set's piece.
    Piece(943007, "Echo Gloves", "INVTYPE_HAND", 0, { [0] = { 6221, 922 } }, { icon = ITEMS[940007].icon })
    SETS[#SETS + 1] = { setID = 7400, classMask = DRUID_MASK, patchID = 120120, name = "Echo Set",
        pieces = { 943007, 940007 }, mod = 0 }
    -- Two cloaks with one icon and a look each, and two with one icon and the same look.
    Piece(944015, "Split Cloak A", "INVTYPE_CLOAK", 4, { [4] = { 6301, 991 } }, { icon = 77 })
    Piece(944016, "Split Cloak B", "INVTYPE_CLOAK", 4, { [4] = { 6302, 992 } }, { icon = 77 })
    SETS[#SETS + 1] = { setID = 7500, classMask = DRUID_MASK, patchID = 120000, name = "Split Set",
        pieces = { 944015, 944016 }, mod = 4 }
    Piece(944017, "Pair Cloak A", "INVTYPE_CLOAK", 4, { [4] = { 6311, 993 } }, { icon = 78 })
    Piece(944018, "Pair Cloak B", "INVTYPE_CLOAK", 4, { [4] = { 6312, 993 } }, { icon = 78 })
    SETS[#SETS + 1] = { setID = 7600, classMask = DRUID_MASK, patchID = 120000, name = "Pair Set",
        pieces = { 944018, 944017 }, mod = 4 }

    -- Worn: a better piece in every slot, so a piece with nothing to learn is junk.
    local WORN = {}
    for slot, equipLoc in pairs({ [1] = "INVTYPE_HEAD", [3] = "INVTYPE_SHOULDER", [5] = "INVTYPE_CHEST",
        [6] = "INVTYPE_WAIST", [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET", [9] = "INVTYPE_WRIST",
        [10] = "INVTYPE_HAND", [15] = "INVTYPE_CLOAK" }) do
        local id = 939000 + slot
        Piece(id, "Worn " .. slot, equipLoc, 0, { [0] = { 5900 + slot, 890 + slot, true } },
            { level = 300, tooltip = { { text = "+90 Stamina" } } })
        WORN[slot] = id
    end
    local BAG = { 930001, 930002, 930003, 930004, 930005, 930006, 930007, 930008, 930009, 930010, 930011, 930012,
        930013, 930014, 930015 }
    local SLOT_OF = {}
    for slot, id in ipairs(BAG) do SLOT_OF[id] = slot end

    local function ItemIDOf(reference)
        if type(reference) == "number" then return reference end
        return type(reference) == "string" and tonumber(reference:match("item:(%d+)")) or nil
    end

    local function Start(flavor, sameLook, marked)
        local game = H.StockGame(TOON, ITEMS)
        -- world.convertible: item -> the Catalyst takes its copies. world.icons: item -> the
        -- icon the client names for its converted piece. world.unloaded: items without data.
        local world = { game = game, asked = {}, unloaded = { [940011] = true },
            convertible = { [930005] = true, [930006] = true, [930007] = true, [930008] = true, [930009] = true,
                [930011] = true },
            icons = { [930005] = ITEMS[940005].icon, [930006] = ITEMS[940006].icon, [930007] = ITEMS[940007].icon,
                [930009] = ITEMS[941011].icon, [930011] = ITEMS[940011].icon } }
        local function Asked(what, id)
            world.asked[what .. " " .. tostring(id)] = (world.asked[what .. " " .. tostring(id)] or 0) + 1
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
        game:Set("UnitClass", function() return TOON.class, TOON.classFile, DRUID end)
        game:Set("GetInventoryItemID", function(_, slot) return WORN[slot] end)
        game:Set("GetInventoryItemLink", function(_, slot) return WORN[slot] and game.Link(WORN[slot]) or nil end)
        game:Set("C_Item.DoesItemExist", function(location) return Place(location) ~= nil end)
        game:Set("C_Item.GetItemLink", function(location) return Place(location) and game.Link(Place(location)) end)
        game:Set("C_Item.GetItemID", function(location) return Place(location) end)
        game:Set("C_Item.GetItemQuality", function(location) return Place(location) and ITEMS[Place(location)].quality end)
        game:Set("C_Item.GetItemName", function(location) return Place(location) and ITEMS[Place(location)].name end)
        game:Set("C_Item.IsBound", function() return false end)
        -- The client names a copy by its GUID when its conversion data has come.
        game:Set("C_Item.GetItemGUID", function(location) return Place(location) and ("Item-0-" .. Place(location)) or nil end)
        game:Set("C_Item.GetCurrentItemLevel", function(location) return Place(location) and ITEMS[Place(location)].level end)
        game:Set("C_Item.GetStackCount", function() return 1 end)
        game:Set("C_Container.GetContainerNumSlots", function(bag) return bag == 0 and #BAG or 0 end)
        game:Set("C_Container.GetContainerItemID", function(bag, slot) return bag == 0 and BAG[slot] or nil end)
        game:Set("C_Container.GetContainerItemLink", function(bag, slot)
            return bag == 0 and BAG[slot] and game.Link(BAG[slot]) or nil
        end)
        game:Set("C_Container.GetContainerItemInfo", function(bag, slot)
            local id = bag == 0 and BAG[slot]
            return id and { itemID = id, stackCount = 1, hyperlink = game.Link(id), isLocked = false, quality = 4,
                isReadable = false, hasLoot = false } or nil
        end)
        game:Set("C_Container.GetContainerItemPurchaseInfo", function() return nil end)
        game:Set("C_TooltipInfo.GetInventoryItem", function(_, slot) return WORN[slot] and hyperlink(game.Link(WORN[slot])) end)
        game:Set("C_TooltipInfo.GetBagItem", function(_, slot) return BAG[slot] and hyperlink(game.Link(BAG[slot])) end)
        game:Set("GetInstanceInfo", function() return "Elsewhere", "none" end)
        game:Set("C_Item.IsItemDataCachedByID", function(id) return ITEMS[ItemIDOf(id)] ~= nil and not world.unloaded[ItemIDOf(id)] end)
        game:Set("C_Item.RequestLoadItemDataByID", function(id)
            local client = game.client
            Asked("load", ItemIDOf(id))
            client.env.C_Timer.After(0, function()
                -- world.never: items the client says it has no data to give for.
                if world.never and world.never[ItemIDOf(id)] then
                    client:Fire("ITEM_DATA_LOAD_RESULT", ItemIDOf(id), false)
                    return
                end
                world.unloaded[ItemIDOf(id)] = nil
                client:Fire("ITEM_DATA_LOAD_RESULT", ItemIDOf(id), ITEMS[ItemIDOf(id)] ~= nil)
            end)
        end)

        -- Upgrade tracks and the Catalyst. WoW Forever has the calls and no item they know.
        game:Set("C_Item.GetItemUpgradeInfo", function(reference)
            local id = ItemIDOf(reference)
            Asked("track", id)
            local track = flavor == "retail" and ITEMS[id] and ITEMS[id].track
            return track and { currentLevel = track.level, maxLevel = track.max, maxItemLevel = 300,
                trackString = "Track " .. track.trackStringID, trackStringID = track.trackStringID } or nil
        end)
        game:Set("C_Item.IsItemConvertibleAndValidForPlayer", function(location)
            Asked("convertible", Place(location))
            return world.convertible[Place(location)] == true
        end)
        game:Set("C_Item.GetItemConversionOutputIcon", function(location) return world.icons[Place(location)] end)
        -- The piece the client names as the converted one, while a copy lies in the Catalyst.
        game:Set("C_TooltipInfo.GetItemInteractionItem", function()
            return world.clientsPiece and { hyperlink = world.clientsPiece } or nil
        end)

        -- Gear sets. world.gearSets: { { id, name, pieces = { [inventory slot] = item } } }, each
        -- piece in its bag slot.
        game:Set("C_EquipmentSet.CanUseEquipmentSets", function() return true end)
        game:Set("C_EquipmentSet.GetEquipmentSetIDs", function()
            local ids = {}
            for index, set in ipairs(world.gearSets or {}) do ids[index] = set.id end
            return ids
        end)
        local function GearSet(id)
            for _, set in ipairs(world.gearSets or {}) do
                if set.id == id then return set end
            end
        end
        game:Set("C_EquipmentSet.GetEquipmentSetInfo", function(id) return GearSet(id).name, 134400, id, false, 1, 0, 1, 0, 0 end)
        game:Set("C_EquipmentSet.GetItemLocations", function(id)
            local locations = {}
            for inventorySlot, itemID in pairs(GearSet(id).pieces) do locations[inventorySlot] = 1000 + SLOT_OF[itemID] end
            return locations
        end)
        game:Set("EquipmentManager_GetLocationData", function(location)
            return { isBags = true, bag = 0, slot = location - 1000 }
        end)

        -- Sources. A link's look is that of the item named in its text (the piece whose
        -- bonuses the link has), on the item whose ID it carries.
        local function Bearer(reference)
            local name = type(reference) == "string" and reference:match("%[(.-)%]")
            for _, item in pairs(ITEMS) do
                if item.name == name then return item end
            end
        end
        local function Info(sourceID)
            local source = SOURCES[sourceID]
            return source and { sourceID = sourceID, visualID = source.look, itemID = source.item,
                name = ITEMS[source.item].name, isCollected = source.collected, isValidSourceForPlayer = source.valid,
                categoryID = 5, invType = 5, quality = 4, itemModID = source.mod, playerCanCollect = true,
                -- Retail says "can collect" for armor the class has no proficiency for, and
                -- names the reason on the source (ItemProficiency).
                useErrorType = not source.valid and 10 or nil } or nil
        end
        game:Set("C_TransmogCollection.GetItemInfo", function(reference)
            local id = ItemIDOf(reference)
            if not BY_ITEM[id] or world.unloaded[id] then return nil end
            -- world.noSource: set pieces the client names no source for by a converted link.
            if world.noSource and world.noSource[id] and reference ~= world.game.Link(id) then return nil end
            -- world.otherSource: set pieces the client names another item's source for.
            if world.otherSource and world.otherSource[id] and reference ~= world.game.Link(id) then
                local sourceID = world.otherSource[id]
                return SOURCES[sourceID].look, sourceID
            end
            local bearer = Bearer(reference) or ITEMS[id]
            local sourceID = BY_ITEM[id][bearer.mod or 0]
            if sourceID then return SOURCES[sourceID].look, sourceID end
        end)
        game:Set("C_TransmogCollection.GetSourceInfo", function(sourceID)
            Asked("source", sourceID)
            return Info(sourceID)
        end)
        game:Set("C_TransmogCollection.GetSourceItemID", function(sourceID) return SOURCES[sourceID] and SOURCES[sourceID].item end)
        -- A source has its item's icon, unless its look was given one of its own.
        game:Set("C_TransmogCollection.GetSourceIcon", function(sourceID)
            local source = SOURCES[sourceID]
            return source and (source.icon or ITEMS[source.item].icon) or nil
        end)
        game:Set("C_TransmogCollection.GetAppearanceInfoBySource", function(sourceID)
            local source = SOURCES[sourceID]
            return source and { appearanceID = source.look, appearanceIsCollected = source.collected,
                sourceIsCollected = source.collected } or nil
        end)
        game:Set("C_TransmogCollection.GetAllAppearanceSources", function(appearanceID)
            local sources = {}
            for sourceID, source in pairs(SOURCES) do
                if source.look == appearanceID then sources[#sources + 1] = sourceID end
            end
            table.sort(sources)
            return sources
        end)
        game:Set("C_TransmogCollection.PlayerCanCollectSource", function(sourceID) return SOURCES[sourceID] ~= nil, true end)
        game:Set("C_TransmogCollection.AccountCanCollectSource", function(sourceID) return SOURCES[sourceID] ~= nil, true end)
        local function Has(sourceID) return SOURCES[sourceID] ~= nil and SOURCES[sourceID].collected end
        game:Set("C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance", Has)
        game:Set("C_TransmogCollection.PlayerKnowsSource", Has)
        game:Set("C_TransmogSets.GetAllSets", function()
            world.asked.sets = (world.asked.sets or 0) + 1
            local sets = {}
            for index, set in ipairs(SETS) do
                sets[index] = { setID = set.setID, baseSetID = set.baseSetID, classMask = set.classMask,
                    patchID = set.patchID, name = set.name }
            end
            return sets
        end)
        game:Set("C_TransmogSets.GetAllSourceIDs", function(setID)
            local sources = {}
            for _, set in ipairs(SETS) do
                if set.setID == setID then
                    for _, itemID in ipairs(set.pieces) do
                        sources[#sources + 1] = BY_ITEM[itemID][set.mod]
                    end
                end
            end
            return sources
        end)

        local client = H.Client.New({ flavor = flavor, provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        local config = H.DeepCopy(namespace:GetDefaultConfig())
        config.Icon.SameLevelBehavior = "sellable"
        config.Icon.ShowLearnable.SameLookDifferentItem = sameLook
        if marked == false then
            config.Icon.ShowLooksAfterChange = false
        end
        rawset(client.env, "CaerdonWardrobeConfig", config)
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)
        Equal(#client.errors, 0, flavor .. ": no error reached the error handler at the start")
        world.client, world.env = client, client.env
        return world
    end

    local function Loaded(world, item)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        world.client:TickUntil(function() return loaded end, 10)
        return item
    end
    -- status, bindingResult, transmogInfo, the item
    local function Judge(world, item)
        Loaded(world, item)
        local ready, status, bindingResult, info
        world.client:TickUntil(function()
            local _
            ready, status, _, bindingResult, info = item:GetCaerdonStatus()
            return ready
        end, 10)
        return status, bindingResult or {}, info or {}, item
    end
    local function InBag(world, id) return world.env.CaerdonItem:CreateFromBagAndSlot(0, SLOT_OF[id]) end
    local function ByLink(world, id) return world.env.CaerdonItem:CreateFromItemLink(world.game.Link(id)) end
    local function Look(info, how)
        for _, look in ipairs(info.transformLook and info.transformLook.looks or {}) do
            if look.how == how then return look end
        end
    end
    local function Explained(world, id)
        local lines = world.env.CaerdonTransformLooks:Explain(Loaded(world, InBag(world, id)), nil, false)
        return table.concat(lines, "\n")
    end
    local function NoErrors(world, label)
        Equal(#world.client.errors, 0, label .. ": no error reached the error handler")
        for _, message in ipairs(world.client.errors) do
            print("        error: " .. tostring(message))
        end
    end

    --------------------------------------------------------------------------------------
    -- 1. Raised on its track
    --------------------------------------------------------------------------------------
    do
        local world = Start("retail", true)
        local status, _, info = Judge(world, InBag(world, 930001))
        Equal(status, "transform", "bracers on the Champion track: the Heroic look is not known, a piece to keep")
        Equal(Look(info, "upgrade") and Look(info, "upgrade").sourceID, 5003, "bracers: the look is the item's Heroic source")
        Equal(info.transformLook.needsLook, "upgrade", "bracers: and it is gained by raising the piece")
        Equal(info.transformLook.route, "upgrade", "bracers: taken to the upgrade vendor")
        Equal(info.transformLook.secondRoute, nil, "bracers: and nowhere else")

        Equal((Judge(world, InBag(world, 930002))), "sellable", "belt at its track's last rank: nothing to gain, junk as before")
        Equal((Judge(world, InBag(world, 930004))), "sellable", "helm on the Myth track: no track above it")
        Equal((Judge(world, InBag(world, 930010))), "sellable", "bracers whose upgrade line is greyed out: cannot be raised")
        Equal((Judge(world, InBag(world, 930014))), "sellable", "a piece of no season: junk as before")
        Equal(world.asked["source 5066"], 1, "a piece of no season: its source is asked about by the equipment code alone")

        status, _, info = Judge(world, InBag(world, 930003))
        Equal(status, "transform", "cloak on the Veteran track: the Normal look is known from another item, kept for its source")
        Equal(info.transformLook.needsSource, "upgrade", "cloak: a source to gain, not a look")
        Equal(info.transformLook.route, "upgrade", "cloak: taken to the upgrade vendor for it")

        status, _, info = Judge(world, InBag(world, 930013))
        Equal(status, "upgrade", "girdle better than the worn one: an upgrade stays an upgrade")
        Equal(info.transformLook and info.transformLook.route, "upgrade",
            "girdle: where it is taken for its look is kept, for a window that draws no arrow")

        status, _, info = Judge(world, InBag(world, 930015))
        Check(status ~= "transform", "bracers the class cannot use: raising them is not this toon's to do (" .. tostring(status) .. ")")
        Equal(Look(info, "upgrade") and Look(info, "upgrade").state, "missing", "plate bracers: though the look is there to gain")
        Equal(info.transformLook.route, nil, "plate bracers: and they are taken nowhere")

        status, _, info = Judge(world, InBag(world, 930012))
        Equal(status, "own", "hood whose own look is not known: a look to learn as it always was")
        Equal(info.transformLook, nil, "hood: nothing is asked about what it would become")
        Equal(world.asked["track 930012"], 1, "hood: its track is asked once, for the cache key alone")
        NoErrors(world, "raised")

        -- "Same look, different item" off: the cloak shows nothing to learn.
        local off = Start("retail", false)
        Equal((Judge(off, InBag(off, 930003))), "sellable", "setting off: a look known from another item is nothing to learn")
        Equal((Judge(off, InBag(off, 930001))), "transform", "setting off: a look nothing has is still one")
        NoErrors(off, "setting off")

        -- Not marked at all (Icon.ShowLooksAfterChange off): judged as before, and not asked.
        local unmarked = Start("retail", true, false)
        Equal((Judge(unmarked, InBag(unmarked, 930001))), "sellable", "not marked: the bracers are junk as before")
        Equal((Judge(unmarked, InBag(unmarked, 930005))), "sellable", "not marked: so is the vest the Catalyst takes")
        Equal(unmarked.asked["convertible 930005"], nil, "not marked: and the Catalyst is not asked")
        Equal(unmarked.asked.sets, nil, "not marked: nor are the sets read")
        NoErrors(unmarked, "not marked")
    end

    --------------------------------------------------------------------------------------
    -- 2. Converted at the Catalyst
    --------------------------------------------------------------------------------------
    do
        local world = Start("retail", true)
        local status, _, info = Judge(world, InBag(world, 930005))
        Equal(status, "transform", "vest the Catalyst takes: the set's Normal look is not known")
        Equal(Look(info, "catalyst") and Look(info, "catalyst").sourceID, 6002, "vest: the set chest's source for this piece's bonuses")
        Equal(Look(info, "catalyst").itemID, 940005, "vest: a robe becomes the set's chest piece")
        Equal(Look(info, "catalystUpgrade") and Look(info, "catalystUpgrade").sourceID, 6003, "vest: converted and raised, the Heroic one")
        Equal(Look(info, "upgrade"), nil, "vest: the piece itself has one look, nothing to gain by raising it alone")
        Equal(info.transformLook.route, "upgrade", "vest: converted and raised, the vendor's mark is the icon")
        Equal(info.transformLook.secondRoute, "catalyst", "vest: with the Catalyst's as the small one on it")
        Equal(world.asked.sets, 1, "the client's sets are read once")

        status, _, info = Judge(world, InBag(world, 930006))
        Equal(status, "transform", "legs: the set's Normal look is known, the Heroic one is not")
        Equal(info.transformLook.needsLook, "catalystUpgrade", "legs: gained by converting and raising")
        Equal(info.transformLook.route, "upgrade", "legs: a look that takes both has the vendor's mark")
        Equal(info.transformLook.secondRoute, "catalyst", "legs: with the Catalyst's on it")

        Equal((Judge(world, InBag(world, 930007))), "sellable", "gloves at their last rank: the set's Heroic look is known, junk")
        Equal(world.asked.sets, 1, "the sets are not read again for a second and third piece")

        -- The set of a season past, told by the icon alone: the piece has no ranks.
        status, _, info = Judge(world, InBag(world, 930009))
        Equal(status, "transform", "a past season's shoulders: converted they have a look of that season's set")
        Equal(Look(info, "catalyst") and Look(info, "catalyst").itemID, 941011, "old shoulders: the older set's piece, by its icon")
        Equal(Look(info, "catalystUpgrade"), nil, "old shoulders: and nothing by raising, which they cannot be")
        Equal(info.transformLook.route, "catalyst", "old shoulders: taken to the Catalyst")
        Equal(info.transformLook.secondRoute, nil, "old shoulders: and nowhere else")

        -- A copy is asked, a link is not, and neither is served the other's verdict.
        Equal((Judge(world, ByLink(world, 930005))), "sellable", "vest by its link alone: no copy to ask the Catalyst about")
        Equal((Judge(world, InBag(world, 930005))), "transform", "vest in the bag: still its own verdict")
        world.env.CaerdonWardrobe:RefreshItems()
        world.client:Tick(20)
        Equal((Judge(world, ByLink(world, 930005))), "sellable", "link first: junk by its link")
        Equal((Judge(world, InBag(world, 930005))), "transform", "link first: and the copy in the bag one to keep")
        Check(InBag(world, 930005):GetStatusCacheKey() ~= ByLink(world, 930005):GetStatusCacheKey(),
            "the copy and its link have a cache entry each")
        Equal(InBag(world, 930014):GetStatusCacheKey(), ByLink(world, 930014):GetStatusCacheKey(),
            "a piece of no season shares its entry with its link, as before")
        local before = world.asked["convertible 930005"]
        Judge(world, InBag(world, 930005))
        Equal(world.asked["convertible 930005"], before, "the Catalyst is asked once per refresh, not per draw")
        Equal(world.asked["convertible 930012"], nil, "and not at all about a piece whose own look is still to learn")
        NoErrors(world, "converted")
    end

    --------------------------------------------------------------------------------------
    -- 3. Answers that come later
    --------------------------------------------------------------------------------------
    do
        local world = Start("retail", true)
        local GUID = "Item-0-930008"
        local function Again()
            world.env.CaerdonWardrobe:RefreshItems()
            world.client:Tick(20)
        end
        -- No icon yet: nothing is said, and the set is not guessed at.
        local status, _, info = Judge(world, InBag(world, 930008))
        Equal(status, "sellable", "boots, no icon yet: nothing is said about the Catalyst")
        Equal(Look(info, "catalyst"), nil, "boots: no set is guessed at")
        Equal(world.asked.sets, nil, "boots: and the client's sets are not read for it")

        -- The client's word about another copy changes nothing; its word about this one
        -- draws the icons again, and the boots are judged by the set the icon names.
        world.icons[930008] = ITEMS[940008].icon
        world.client:Fire("ITEM_CONVERSION_DATA_READY", "Item-0-930005")
        world.client:Tick(40, 1)
        Equal((Judge(world, InBag(world, 930008))), "sellable", "boots: another copy's data is not theirs")
        world.client:Fire("ITEM_CONVERSION_DATA_READY", GUID)
        world.client:Tick(40, 1)
        status, _, info = Judge(world, InBag(world, 930008))
        Equal(status, "transform", "boots, icon here: the verdict follows without a refresh from outside")
        Equal(Look(info, "catalyst") and Look(info, "catalyst").itemID, 940008,
            "boots: the set's piece, in a set that lists two items for the feet")
        Equal(Look(info, "catalyst").sourceID, 6032, "boots: the source is the client's answer for their link")

        -- The icon of the older set's boots, whose look is known: junk.
        world.icons[930008] = ITEMS[941008].icon
        Again()
        Equal((Judge(world, InBag(world, 930008))), "sellable", "boots, the older set's icon: that look is known")

        -- A copy the client keeps having no icon for is drawn again twice in all, not for ever.
        world.icons[930008] = nil
        Again()
        Equal((Judge(world, InBag(world, 930008))), "sellable", "boots, no icon again: nothing is said")
        world.icons[930008] = ITEMS[940008].icon
        world.client:Fire("ITEM_CONVERSION_DATA_READY", GUID)
        world.client:Tick(40, 1)
        Equal((Judge(world, InBag(world, 930008))), "transform", "boots: the second word of the client's draws again")
        world.icons[930008] = nil
        Again()
        Judge(world, InBag(world, 930008))
        world.icons[930008] = ITEMS[940008].icon
        world.client:Fire("ITEM_CONVERSION_DATA_READY", GUID)
        world.client:Tick(40, 1)
        Equal((Judge(world, InBag(world, 930008))), "sellable", "boots: the third does not, until something else refreshes")
        Again()
        Equal((Judge(world, InBag(world, 930008))), "transform", "boots: which finds the icon there")

        -- A set piece the client has no data for: asked for, no verdict made meanwhile, and
        -- the piece judged when the data is here. It is not offered for sale in between.
        local mantle = Loaded(world, InBag(world, 930011))
        Equal((mantle:GetCaerdonStatus()), false, "mantle: no verdict while the set piece has no data")
        Equal(select(3, mantle:GetCaerdonStatus()), "item:940011", "mantle: the status names the set piece it waits for, for the queue")
        Equal(world.asked["load 940011"], 1, "mantle: the set piece's data is asked for")
        Equal((mantle:GetCaerdonStatus()), false, "mantle: still none while it is on its way")
        Equal(world.asked["load 940011"], 1, "mantle: and it is asked for once while it is")
        local queue = world.env.CaerdonWardrobe
        local came, retryFor = {}, queue.RetryWaitingFor
        function queue:RetryWaitingFor(key, ...)
            came[#came + 1] = tostring(key)
            return retryFor(self, key, ...)
        end
        status, _, info = Judge(world, InBag(world, 930011))
        queue.RetryWaitingFor = retryFor
        Equal(came[1], "item:940011", "mantle: the set piece's coming asks the buttons again that wait for it, by the name the status gave")
        Equal(status, "transform", "mantle: with the data here it is one to keep")
        Equal(Look(info, "catalyst") and Look(info, "catalyst").sourceID, 6042, "mantle: the set shoulders' Normal source")
        local refreshes = world.env.CaerdonCounters:GetReport().refreshes.total
        world.client:Tick(40, 1)
        Equal(world.env.CaerdonCounters:GetReport().refreshes.total, refreshes, "mantle: the data's coming draws nothing again by itself")

        -- The client drops the data again (it keeps about two thousand items). What the
        -- piece converts to was worked out and is kept for the session: the piece is judged
        -- at once, with no wait and no asking, and whether its look is collected is still
        -- asked of the client.
        local looks = world.env.CaerdonTransformLooks
        local keptLinks, keptUsed = looks:GetKeptAnswers()
        Check(keptLinks >= 1, "mantle: what the piece converts to is kept once it is worked out")
        world.unloaded[940011] = true
        Again()
        mantle = Loaded(world, InBag(world, 930011))
        local keptStatus
        _, keptStatus = mantle:GetCaerdonStatus()
        Equal(keptStatus, "transform", "mantle, the data gone again: judged at once from what was worked out")
        Equal(world.asked["load 940011"], 1, "mantle, the data gone again: and the set piece is not asked for again")
        Check(select(2, looks:GetKeptAnswers()) > keptUsed, "mantle, the data gone again: the kept answer was the one used")
        Equal((looks:GetKeptAnswers()), keptLinks, "mantle, the data gone again: and nothing was worked out anew")
        Check(Explained(world, 930011):find("the set's piece is item 940011 and the converted piece has source 6042, as worked out earlier this session", 1, true) ~= nil,
            "mantle, the data gone again: the export says the answer was kept: " .. Explained(world, 930011))
        -- The look learned meanwhile: the kept answer names the source, and its state is the client's now.
        SOURCES[6042].collected = true
        Again()
        Equal((Judge(world, InBag(world, 930011))), "sellable", "mantle, the data gone again: a look learned since is seen, the state being asked each time")
        SOURCES[6042].collected = false
        Again()
        Equal((Judge(world, InBag(world, 930011))), "transform", "mantle, the data gone again: and not learned, it is one to keep")
        world.unloaded[940011] = nil

        -- What follows is the first time a link is asked about, so what was kept is forgotten
        -- before each (as a replay does).
        -- A set piece the client has no data to give for: judged without, as before, and
        -- not asked about again.
        looks:ForgetEverything()
        world.unloaded[940011], world.never = true, { [940011] = true }
        Again()
        mantle = Loaded(world, InBag(world, 930011))
        Equal((mantle:GetCaerdonStatus()), false, "mantle, no data to be had: no verdict while it is asked for")
        status = Judge(world, InBag(world, 930011))
        Equal(status, "sellable", "mantle, no data to be had: judged without it once the client has said so")
        local asked = world.asked["load 940011"]
        Again()
        Equal((Judge(world, InBag(world, 930011))), "sellable", "mantle, no data to be had: and so the next time")
        Equal(world.asked["load 940011"], asked, "mantle, no data to be had: not asked for again")
        world.never = nil

        -- The data is here and the client names no source of the set piece for the converted
        -- link: this set's piece is not the one the Catalyst gives. With no other set that
        -- has the icon, nothing is said, whatever the set piece's looks are.
        looks:ForgetEverything()
        world.unloaded[940011], world.noSource = nil, { [940011] = true }
        Again()
        status, _, info = Judge(world, InBag(world, 930011))
        Equal(status, "sellable", "mantle, no source named: nothing is said")
        Equal(Look(info, "catalyst"), nil, "mantle, no source named: and no look is made up from the set piece's own")
        local text = Explained(world, 930011)
        Check(text:find("the client names no source of item 940011 for the converted piece's link: not this set's piece", 1, true) ~= nil and
            text:find("no other set of this class has a shoulder piece with the icon, so nothing is said", 1, true) ~= nil,
            "mantle, no source named: the export says why: " .. text)
        world.noSource = nil
        -- Nor is a source of another item taken for the set piece's.
        looks:ForgetEverything()
        world.otherSource = { [940011] = 6142 }
        Again()
        status, _, info = Judge(world, InBag(world, 930011))
        Equal(status, "sellable", "mantle, another item's source named: nothing is said")
        Equal(Look(info, "catalyst"), nil, "mantle, another item's source named: and it is not taken for the piece's look")
        world.otherSource = nil
        NoErrors(world, "later answers")
    end

    --------------------------------------------------------------------------------------
    -- 3a. The client's word on a copy comes while its verdict waits
    --------------------------------------------------------------------------------------
    -- The first time a copy is asked about, the client has no icon for its converted piece
    -- and sends for it. The verdict waits a few seconds for that: when the word comes the
    -- queue asks again and the piece is judged, with no redraw of everything.
    do
        local world = Start("retail", true)
        local GUID = "Item-0-930008"
        world.icons[930008] = nil
        local boots = Loaded(world, InBag(world, 930008))
        local ready, why, waitsFor = boots:GetCaerdonStatus()
        Equal(ready, false, "word awaited: no verdict while the client has no icon for the copy")
        Equal(why, "the Catalyst's answer", "word awaited: and the status says what it waits for")
        Equal(waitsFor, "conversion:" .. GUID, "word awaited: by the name the client's word will come under, for the queue")
        local refreshes = world.env.CaerdonCounters:GetReport().refreshes.total
        -- The queue is told to ask again for the buttons that wait for this copy's word,
        -- and not for every button that waits.
        local core, again, all = world.env.CaerdonWardrobe, {}, 0
        local retryFor, retrySoon = core.RetryWaitingFor, core.RetryNotReadySoon
        function core:RetryWaitingFor(key, ...)
            again[#again + 1] = tostring(key)
            return retryFor(self, key, ...)
        end
        function core:RetryNotReadySoon(...)
            all = all + 1
            return retrySoon(self, ...)
        end
        world.icons[930008] = ITEMS[940008].icon
        world.client:Fire("ITEM_CONVERSION_DATA_READY", GUID)
        Equal(table.concat(again, " "), "conversion:" .. GUID, "word awaited: the client's word has the buttons asked again that wait for it")
        Equal(all, 0, "word awaited: and not every button that waits")
        world.client:Tick(10)
        core.RetryWaitingFor, core.RetryNotReadySoon = retryFor, retrySoon
        local status = boots:GetCaerdonStatus() and select(2, boots:GetCaerdonStatus())
        Equal(status, "transform", "word awaited: with the client's word the piece is judged")
        Equal(world.env.CaerdonCounters:GetReport().refreshes.total, refreshes, "word awaited: and nothing was drawn again for it")
        local lines = {}
        for _, line in ipairs(world.env.CaerdonCounters:GetReportLines()) do
            lines[#lines + 1] = tostring(line.text)
        end
        Check(table.concat(lines, " / "):find("the Catalyst's word on a copy: asked for, the verdict put off: 1 times", 1, true) ~= nil,
            "word awaited: the counters say that a verdict waited for it")
        NoErrors(world, "word awaited")
    end

    --------------------------------------------------------------------------------------
    -- 3b. Two sets with the converted piece's icon
    --------------------------------------------------------------------------------------
    -- A season's PVP set has the class set's icons, with looks of its own that the piece's
    -- bonuses name none of. The set listed first is then not the one: the client names no
    -- source of its piece for the converted link, and the next set with the icon is asked.
    do
        local oldIcon = ITEMS[941011].icon
        ITEMS[941011].icon = ITEMS[940011].icon
        local world = Start("retail", true)
        world.unloaded[940011], world.noSource = nil, { [940011] = true }
        local status, _, info = Judge(world, InBag(world, 930011))
        Equal(status, "transform", "two sets with the icon: the piece is one to keep, by the second set's look")
        Equal(Look(info, "catalyst") and Look(info, "catalyst").itemID, 941011, "two sets with the icon: the set piece is the one the client names a source of")
        Equal(Look(info, "catalyst") and Look(info, "catalyst").sourceID, 6142, "two sets with the icon: and the look is that source")
        local text = Explained(world, 930011)
        Check(text:find("the client names no source of item 940011 for the converted piece's link: not this set's piece", 1, true) ~= nil and
            text:find("shoulder piece is item 941011 with 4 sources", 1, true) ~= nil and
            text:find("converted, it has source 6142", 1, true) ~= nil,
            "two sets with the icon: the export names the set passed over and the one taken: " .. text)
        -- Where the first set's piece is the one the client names a source of, it is taken
        -- and the second is not asked. (Another client's answers for the same link: what
        -- was worked out is forgotten first, as it is kept for the session.)
        world.env.CaerdonTransformLooks:ForgetEverything()
        world.noSource = nil
        world.env.CaerdonWardrobe:RefreshItems()
        world.client:Tick(20)
        status, _, info = Judge(world, InBag(world, 930011))
        Equal(Look(info, "catalyst") and Look(info, "catalyst").itemID, 940011, "two sets with the icon: the first set's piece where the client names its source")
        NoErrors(world, "two sets with the icon")
        ITEMS[941011].icon = oldIcon
    end

    --------------------------------------------------------------------------------------
    -- 4. The export's lines, and a client without any of it
    --------------------------------------------------------------------------------------
    do
        local world = Start("retail", true)
        local text = Explained(world, 930005)
        Check(text:find("upgrade track: Track 973 (973), rank 2 of 6, Normal look", 1, true) ~= nil, "export: the track")
        Check(text:find("by the converted piece's icon", 1, true) ~= nil, "export: how the set was told")
        Check(text:find("source 6002", 1, true) ~= nil, "export: the converted piece's source")
        Check(text:find("a look to gain: catalyst", 1, true) ~= nil, "export: the verdict")
        Check(text:find("its own source: 5021 (modifier 0, Normal look)", 1, true) ~= nil, "export: the piece's own source and its look")
        Check(text:find("the set piece's source 6001 (modifier 4, Raid Finder look) of appearance 901: missing", 1, true) ~= nil,
            "export: every look of the set piece, the lowest")
        Check(text:find("the set piece's source 6004 (modifier 3, Mythic look) of appearance 904: missing", 1, true) ~= nil,
            "export: and the highest")
        Check(text:find("catalyst window: not open", 1, true) ~= nil, "export: no word of the client's own while the Catalyst is shut")
        text = Explained(world, 930014)
        Check(text:find("upgrade track: none", 1, true) ~= nil, "export: a piece of no season says so")
        -- No icon for the boots: said, with no guess at the set.
        text = Explained(world, 930008)
        Check(text:find("no icon yet (the client has been asked; the verdict waits for it)", 1, true) ~= nil and
            text:find("a look to gain: not known just now", 1, true) ~= nil, "export: no icon yet says so, and that the verdict waits")
        -- After a few seconds without the client's word the copy is judged without it.
        world.client:Tick(80)
        text = Explained(world, 930008)
        Check(text:find("no icon yet, so nothing is said", 1, true) ~= nil, "export: and that nothing is said once it has waited long enough")
        Check(text:find("feet piece is item", 1, true) == nil, "export: and names no set")
        -- An icon no set has a piece with: the newest sets' items for the slot are described.
        world.icons[930008] = 1
        text = Explained(world, 930008)
        Check(text:find("no set of this class has a feet piece with the icon 1", 1, true) ~= nil, "export: an icon of no set says so")
        Check(text:find("set 7300 (patch 120110) has for the feet slot: item 940008 (4 sources; icons " .. ITEMS[940008].icon
            .. "); item 941008 (4 sources; icons " .. ITEMS[941008].icon .. ")", 1, true) ~= nil,
            "export: and describes the newest set's items for the slot, with their icons")
        world.icons[930008] = nil

        -- The Catalyst's window with the vest in it: the client names the converted piece, and
        -- the export says whether that is the source worked out.
        local slotted = SLOT_OF[930005]
        rawset(world.env, "ItemInteractionFrame", {
            IsShown = function() return true end,
            GetItemLocation = function() return world.env.ItemLocation:CreateFromBagAndSlot(0, slotted) end,
        })
        world.clientsPiece = world.game.Link(930005):gsub("item:%d+", "item:940005", 1)
        text = Explained(world, 930005)
        Check(text:find("the client's converted piece is item:940005", 1, true) ~= nil, "catalyst window: the client's piece is named")
        Check(text:find("source 6002 (modifier 0) of appearance 902: missing", 1, true) ~= nil, "catalyst window: with its source")
        Check(text:find("the source worked out above is the client's", 1, true) ~= nil, "catalyst window: the same source is said to be")
        -- The client gives the set piece another difficulty's look than the link made up says.
        world.clientsPiece = world.game.Link(930003):gsub("item:%d+", "item:940005", 1)
        text = Explained(world, 930005)
        Check(text:find("NOT the source worked out above (6002)", 1, true) ~= nil, "catalyst window: another source is said not to be")
        Check(text:find("source 6001 (modifier 4)", 1, true) ~= nil, "catalyst window: and named")
        text = Explained(world, 930006)
        Check(text:find("catalyst window: open, with another piece or none in it", 1, true) ~= nil,
            "catalyst window: a piece that is not the one in it gets no answer")
        world.clientsPiece = nil
        text = Explained(world, 930005)
        Check(text:find("the client names no converted piece yet", 1, true) ~= nil, "catalyst window: no answer yet is said")
        rawset(world.env, "ItemInteractionFrame", nil)
        NoErrors(world, "export")

        local forever = Start("forever", true)
        for _, id in ipairs({ 930001, 930003, 930005, 930008 }) do
            Equal((Judge(forever, InBag(forever, id))), "sellable", "no upgrade info on this client: item " .. id .. " is junk as before")
            Equal(forever.asked["convertible " .. id], nil, "and the Catalyst is not asked about " .. id)
            Equal(InBag(forever, id):GetStatusCacheKey(), ByLink(forever, id):GetStatusCacheKey(),
                "and " .. id .. " shares its cache entry with its link")
        end
        Equal(forever.asked.sets, nil, "and the sets are never read")
        NoErrors(forever, "no upgrade info")
    end

    --------------------------------------------------------------------------------------
    -- 6. A set with more than one item for a slot, and a look with an icon of its own
    --------------------------------------------------------------------------------------
    do
        local world = Start("retail", true)
        -- Two items with the icon: the one with a source per difficulty is the set's piece.
        local text = Explained(world, 930007)
        Check(text:find("hand piece is item 940007 with 4 sources, found by the converted piece's icon, among 2 items of the set that have it (the others: item 943007 with 1 sources)",
            1, true) ~= nil, "two items with the icon: the one with the most sources is the set's piece")
        Equal((Judge(world, InBag(world, 930007))), "sellable", "gloves: judged by that piece, whose Heroic look is known")

        -- Two items with the icon, as many sources and a look each: nothing says which.
        world.convertible[930003] = true
        world.icons[930003] = 77
        local status, _, info = Judge(world, InBag(world, 930003))
        Equal(Look(info, "catalyst"), nil, "two items with other looks: nothing is said about the Catalyst")
        Equal(info.transformLook and info.transformLook.route, "upgrade", "cloak: it is still taken to be raised")
        Check(Explained(world, 930003):find("has 2 items for the cloak slot with the icon 77, and not the same looks", 1, true) ~= nil,
            "two items with other looks: the export says so")

        -- Two items with the icon, as many sources and the same look: one is as good as the other.
        world.icons[930003] = 78
        world.env.CaerdonWardrobe:RefreshItems()
        world.client:Tick(20)
        status, _, info = Judge(world, InBag(world, 930003))
        Equal(Look(info, "catalyst") and Look(info, "catalyst").itemID, 944017, "two items with the same look: the first of them")
        Equal(Look(info, "catalyst").sourceID, 6311, "same look: its source for the cloak's bonuses")
        Equal(info.transformLook.route, "upgrade", "cloak: a look at each, the vendor's mark")
        Equal(info.transformLook.secondRoute, "catalyst", "cloak: with the Catalyst's on it")
        NoErrors(world, "several items")

        -- A difficulty's look with an icon of its own. The client's icon for the converted
        -- piece is that one's alone: it tells the set, and it is the look, whatever the link
        -- made up from the piece says.
        SOURCES[6013].icon = 555
        local tinted = Start("retail", true)
        tinted.icons[930006] = 555
        status, _, info = Judge(tinted, InBag(tinted, 930006))
        Equal(status, "transform", "legs, the Heroic look's own icon: the set is found by a source's icon")
        Equal(Look(info, "catalyst") and Look(info, "catalyst").sourceID, 6013, "legs: and the look is the one with that icon")
        Equal(info.transformLook.needsLook, "catalyst", "legs: gained by converting alone")
        Check(Explained(tinted, 930006):find("has the icon " .. ITEMS[940006].icon .. "; 1 of the set piece's sources have the client's", 1, true) ~= nil,
            "legs: the export says the link's source had another icon")
        NoErrors(tinted, "a look's own icon")

        -- Two looks share that icon: it tells the set and not the look, so the link's answer stands.
        SOURCES[6014].icon = 555
        local shared = Start("retail", true)
        shared.icons[930006] = 555
        status, _, info = Judge(shared, InBag(shared, 930006))
        Equal(Look(info, "catalyst") and Look(info, "catalyst").sourceID, 6012, "legs, an icon two looks have: the link's source stands")
        Equal(info.transformLook.needsLook, "catalystUpgrade", "legs: so the look to gain is the one after raising")
        NoErrors(shared, "an icon two looks have")
        SOURCES[6014].icon = nil
        SOURCES[6013].icon = nil
    end

    --------------------------------------------------------------------------------------
    -- 5. A gear set's piece
    --------------------------------------------------------------------------------------
    do
        -- The set keeps the piece and has a mark of its own: no mark for a look to gain, and
        -- nothing asked. An upgrade is an upgrade in a set or out of one.
        local world = Start("retail", true)
        world.gearSets = { { id = 1, name = "Alpha", pieces = { [5] = 930005, [9] = 930001, [6] = 930013 } } }
        local function Judged(id)
            local item = Loaded(world, InBag(world, id))
            local ready, status, binding, _, info
            world.client:TickUntil(function()
                ready, status, binding, _, info = item:GetCaerdonStatus()
                return ready
            end, 10)
            return status, binding, info or {}
        end
        local status, binding, info = Judged(930005)
        Equal(status, "collected", "set piece the Catalyst takes: not marked, and not for sale")
        Equal(binding, "Alpha", "set piece: it has the set's name")
        Equal(info.transformLook, nil, "set piece: nothing is worked out for it")
        Equal(world.asked["convertible 930005"], nil, "set piece: the Catalyst is not asked")
        Equal(world.asked.sets, nil, "set piece: and the client's sets are not read")
        Equal((Judged(930001)), "collected", "set piece on a track with a look above it: not marked either")
        status, binding, info = Judged(930013)
        Equal(status, "upgrade", "set piece that is better than the worn one: an upgrade")
        Equal(info.transformLook, nil, "set piece that is an upgrade: nothing is worked out for it either")
        Equal((Judged(930006)), "transform", "a piece of no set beside them: marked as before")
        Check(Explained(world, 930005):find("a look to gain: catalyst", 1, true) ~= nil,
            "set piece: the export still says what it would gain")

        -- Out of the set: the mark is back with the refresh a set's change brings.
        world.gearSets = {}
        world.client:Fire("EQUIPMENT_SETS_CHANGED")
        world.client:Tick(20)
        status, binding = Judged(930005)
        Equal(status, "transform", "taken out of the set: one to keep for its look again")
        Equal(binding, nil, "taken out of the set: and no set's name")
        Equal((Judged(930001)), "transform", "taken out of the set: the bracers too")
        NoErrors(world, "gear set")
    end
end
