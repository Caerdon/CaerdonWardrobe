-- What wearing a piece would do to the bonuses of the item sets worn (CaerdonSetBonuses.lua),
-- and the tooltip lines that say so (features/Tooltip.lua, AddSetBonusChanges).
--
-- The client says nothing of this but on a piece's tooltip, and the lines here are made after
-- the recorded ones of both clients (tools/harness/fixtures: "Defias Leather (1/5)" with its
-- four bonuses on WoW Forever, "Sprouts of the Luminous Bloom (4/5)" on retail):
--   the set's line, type 0, written from ITEM_SET_NAME;
--   a piece under it, two blanks before its name, type 0 where it is worn, 42 where not;
--   a bonus the toon does not have, type 42, written from ITEM_SET_BONUS_GRAY, with its pieces;
--   a bonus it has, type 0, written from ITEM_SET_BONUS, without.
-- The sets, pieces and bonuses are invented. The game here writes a piece's set lines from what
-- is worn at the time, as a client does.
--
-- Real code: the addon, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Druid", classFile = "DRUID", race = "Tauren",
        faction = "Horde", level = 60 }

    local NONE, BLANK, DISABLED = 0, 1, 42

    -- The item sets: the pieces a bonus begins at, in the tooltip's order.
    local SETS = {
        bloom = { id = 7001, name = "Sprouts of the Test Bloom", total = 5, bonuses = { 2, 4 } },
        arena = { id = 7002, name = "Test Warmonger's Armor", total = 5, bonuses = { 2, 4 } },
        defias = { id = 7003, name = "Test Leather", total = 5, bonuses = { 2, 3, 4, 5 } },
        rings = { id = 7004, name = "Test Signets", total = 2, bonuses = { 2 } },
        blades = { id = 7005, name = "Test Arms", total = 2, bonuses = { 2 } },
        relic = { id = 7006, name = "Test Reliquary", total = 3, bonuses = { 2 } },
        old = { id = 7007, name = "Test Heirlooms of Old", total = 2, bonuses = { 2 }, legacy = true },
        nameless = { name = "Test Nameless Set", total = 2, bonuses = { 2 } },
        twins = { id = 7009, name = "Test Twin Bonuses", total = 5, bonuses = { 2, 4, 4 } },
    }

    local function Piece(name, equipLoc, set, extra)
        local item = { name = name, quality = 3, level = 60, minLevel = 50, type = "Armor", subType = "Leather", stack = 1,
            equipLoc = equipLoc, price = 900, classID = 4, subClassID = 2, bindType = 1, set = set,
            setID = set and SETS[set].id or nil,
            tooltip = { { text = "Binds when picked up", type = 20, bonding = 6 } } }
        for key, value in pairs(extra or {}) do
            item[key] = value
        end
        return item
    end

    local BLOOM_HEAD, BLOOM_SHOULDER, BLOOM_CHEST, BLOOM_HANDS, BLOOM_LEGS, BLOOM_HEAD_TWO = 950001, 950002, 950003, 950004, 950005, 950006
    local ARENA_HEAD, ARENA_SHOULDER, ARENA_CHEST, ARENA_HANDS, ARENA_LEGS = 950011, 950012, 950013, 950014, 950015
    local PLAIN_HEAD, PLAIN_CHEST, PLAIN_HANDS, PLAIN_LEGS, PLAIN_RING, OTHER_RING = 950021, 950022, 950023, 950024, 950025, 950026
    local DEFIAS_CHEST, DEFIAS_WAIST, DEFIAS_FEET, DEFIAS_HANDS, DEFIAS_LEGS = 950031, 950032, 950033, 950034, 950035
    local PLAIN_WAIST = 950036
    local RING_A, RING_B = 950041, 950042
    local BLADE_MAIN, BLADE_OFF, PLAIN_STAFF, PLAIN_SHIELD = 950051, 950052, 950053, 950054
    local RELIC_STAFF, RELIC_NECK, RELIC_ORB, PLAIN_SWORD, PLAIN_DAGGER = 950055, 950056, 950057, 950058, 950059
    local OLD_HEAD, OLD_CHEST = 950061, 950062
    local NAMELESS_HEAD, NAMELESS_CHEST, NAMELESS_HEAD_TWO = 950063, 950064, 950065
    local TWIN_HEAD, TWIN_SHOULDER, TWIN_CHEST, TWIN_HANDS, TWIN_LEGS = 950071, 950072, 950073, 950074, 950075
    local ODD_HEAD, POTION = 950081, 950082

    local function Items()
        return {
            [BLOOM_HEAD] = Piece("Bloom Helm", "INVTYPE_HEAD", "bloom"),
            [BLOOM_SHOULDER] = Piece("Bloom Shoulders", "INVTYPE_SHOULDER", "bloom"),
            [BLOOM_CHEST] = Piece("Bloom Tunic", "INVTYPE_CHEST", "bloom"),
            [BLOOM_HANDS] = Piece("Bloom Gloves", "INVTYPE_HAND", "bloom"),
            [BLOOM_LEGS] = Piece("Bloom Leggings", "INVTYPE_LEGS", "bloom"),
            -- A second helm of the same set (another difficulty's, or the PVP season's).
            [BLOOM_HEAD_TWO] = Piece("Bloom Helm of Another Sort", "INVTYPE_HEAD", "bloom"),
            [ARENA_HEAD] = Piece("Arena Helm", "INVTYPE_HEAD", "arena"),
            [ARENA_SHOULDER] = Piece("Arena Shoulders", "INVTYPE_SHOULDER", "arena"),
            [ARENA_CHEST] = Piece("Arena Tunic", "INVTYPE_CHEST", "arena"),
            [ARENA_HANDS] = Piece("Arena Gloves", "INVTYPE_HAND", "arena"),
            [ARENA_LEGS] = Piece("Arena Leggings", "INVTYPE_LEGS", "arena"),
            [PLAIN_HEAD] = Piece("Plain Helm", "INVTYPE_HEAD"),
            [PLAIN_CHEST] = Piece("Plain Tunic", "INVTYPE_CHEST"),
            [PLAIN_HANDS] = Piece("Plain Gloves", "INVTYPE_HAND"),
            [PLAIN_LEGS] = Piece("Plain Leggings", "INVTYPE_LEGS"),
            [PLAIN_RING] = Piece("Plain Band", "INVTYPE_FINGER", nil, { subType = "Miscellaneous", subClassID = 0 }),
            [OTHER_RING] = Piece("Other Band", "INVTYPE_FINGER", nil, { subType = "Miscellaneous", subClassID = 0 }),
            [DEFIAS_CHEST] = Piece("Test Leather Armor", "INVTYPE_CHEST", "defias"),
            [DEFIAS_WAIST] = Piece("Test Leather Belt", "INVTYPE_WAIST", "defias"),
            [DEFIAS_FEET] = Piece("Test Leather Boots", "INVTYPE_FEET", "defias"),
            [DEFIAS_HANDS] = Piece("Test Leather Gloves", "INVTYPE_HAND", "defias"),
            [DEFIAS_LEGS] = Piece("Test Leather Leggings", "INVTYPE_LEGS", "defias"),
            [PLAIN_WAIST] = Piece("Plain Belt", "INVTYPE_WAIST"),
            [RING_A] = Piece("Signet of Tests", "INVTYPE_FINGER", "rings", { subType = "Miscellaneous", subClassID = 0 }),
            [RING_B] = Piece("Seal of Tests", "INVTYPE_FINGER", "rings", { subType = "Miscellaneous", subClassID = 0 }),
            [BLADE_MAIN] = Piece("Test Blade", "INVTYPE_WEAPONMAINHAND", "blades",
                { type = "Weapon", subType = "One-Handed Swords", classID = 2, subClassID = 7 }),
            [BLADE_OFF] = Piece("Test Offblade", "INVTYPE_WEAPONOFFHAND", "blades",
                { type = "Weapon", subType = "One-Handed Swords", classID = 2, subClassID = 7 }),
            [PLAIN_STAFF] = Piece("Plain Staff", "INVTYPE_2HWEAPON", nil,
                { type = "Weapon", subType = "Staves", classID = 2, subClassID = 10 }),
            [PLAIN_SHIELD] = Piece("Plain Orb", "INVTYPE_HOLDABLE", nil, { subType = "Miscellaneous", subClassID = 0 }),
            [RELIC_STAFF] = Piece("Reliquary Staff", "INVTYPE_2HWEAPON", "relic",
                { type = "Weapon", subType = "Staves", classID = 2, subClassID = 10, twoHanded = true }),
            [RELIC_NECK] = Piece("Reliquary Chain", "INVTYPE_NECK", "relic", { subType = "Miscellaneous", subClassID = 0 }),
            [RELIC_ORB] = Piece("Reliquary Orb", "INVTYPE_HOLDABLE", "relic", { subType = "Miscellaneous", subClassID = 0 }),
            [PLAIN_SWORD] = Piece("Plain Sword", "INVTYPE_WEAPONMAINHAND", nil,
                { type = "Weapon", subType = "One-Handed Swords", classID = 2, subClassID = 7 }),
            -- A one-hander for either hand.
            [PLAIN_DAGGER] = Piece("Plain Dagger", "INVTYPE_WEAPON", nil,
                { type = "Weapon", subType = "Daggers", classID = 2, subClassID = 15 }),
            [OLD_HEAD] = Piece("Old Helm", "INVTYPE_HEAD", "old"),
            [OLD_CHEST] = Piece("Old Tunic", "INVTYPE_CHEST", "old"),
            -- A set the item info names no ID for.
            [NAMELESS_HEAD] = Piece("Nameless Helm", "INVTYPE_HEAD", "nameless"),
            [NAMELESS_CHEST] = Piece("Nameless Tunic", "INVTYPE_CHEST", "nameless"),
            [NAMELESS_HEAD_TWO] = Piece("Nameless Helm of Another Sort", "INVTYPE_HEAD", "nameless"),
            [TWIN_HEAD] = Piece("Twin Helm", "INVTYPE_HEAD", "twins"),
            [TWIN_SHOULDER] = Piece("Twin Shoulders", "INVTYPE_SHOULDER", "twins"),
            [TWIN_CHEST] = Piece("Twin Tunic", "INVTYPE_CHEST", "twins"),
            [TWIN_HANDS] = Piece("Twin Gloves", "INVTYPE_HAND", "twins"),
            [TWIN_LEGS] = Piece("Twin Leggings", "INVTYPE_LEGS", "twins"),
            -- A line of the set line's shape that is none, above the set's own.
            [ODD_HEAD] = Piece("Odd Helm", "INVTYPE_HEAD", "bloom", { oddLine = true }),
            [POTION] = { name = "Test Potion", quality = 1, level = 30, minLevel = 0, type = "Consumable", subType = "Potion",
                stack = 20, price = 50, classID = 0, subClassID = 1, bindType = 0, tooltip = {} },
        }
    end

    local function Start(flavor, saved)
        local items = Items()
        local world = { worn = {}, notThere = {} }
        local game = H.StockGame(TOON, items)
        local function Worn(location)
            if type(location) == "table" and location.IsEquipmentSlot and location:IsEquipmentSlot() then
                return world.worn[location:GetEquipmentSlot()]
            end
        end
        game:Set("GetInventoryItemLink", function(_, slot)
            return world.worn[slot] and game.Link(world.worn[slot]) or nil
        end)
        game:Set("GetInventoryItemID", function(_, slot) return world.worn[slot] end)
        game:Set("C_Item.DoesItemExist", function(location) return Worn(location) ~= nil end)
        game:Set("C_Item.GetItemLink", function(location) return Worn(location) and game.Link(Worn(location)) end)
        game:Set("C_Item.GetItemID", function(location) return Worn(location) end)
        game:Set("C_Item.GetCurrentItemLevel", function(location) return Worn(location) and 60 or nil end)
        game:Set("C_Item.IsBound", function() return false end)
        game:Set("C_TooltipInfo.GetInventoryItem", function(_, slot)
            return world.worn[slot] and game.names["C_TooltipInfo.GetHyperlink"](game.Link(world.worn[slot])) or nil
        end)
        game:Set("CanDualWield", function() return world.dualWield == true end)
        -- The backpack, for the test addon's contract. Set before the client reads any of it.
        world.bag = {}
        game:Set("C_Container.GetContainerNumSlots", function(index) return index == 0 and #world.bag or 0 end)
        game:Set("C_Container.GetContainerItemID", function(index, slot) return index == 0 and world.bag[slot] or nil end)
        game:Set("C_Container.GetContainerItemLink", function(index, slot)
            return index == 0 and world.bag[slot] and game.Link(world.bag[slot]) or nil
        end)
        game:Set("C_Item.GetItemSetInfo", function(setID)
            for _, set in pairs(SETS) do
                if set.id == setID then
                    return world.fault == "name" and "Another Name" or set.name
                end
            end
        end)
        game:Set("TooltipDataProcessor.AddTooltipPostCall", function() end)
        game:Set("TooltipDataProcessor.AddLinePreCall", function() end)

        local client = H.Client.New({ flavor = flavor, provider = game })
        game.client = client
        local env = client.env

        game:Set("C_Item.GetItemInventoryType", function(location)
            local id = Worn(location)
            return id and items[id].twoHanded and env.Enum.InventoryType.Index2HweaponType or 0
        end)

        -- A piece's tooltip: the stock one, and under it its set's lines as they stand with
        -- what is worn.
        local hyperlink = game.names["C_TooltipInfo.GetHyperlink"]
        world.asked = 0
        game:Set("C_TooltipInfo.GetHyperlink", function(link)
            world.asked = world.asked + 1
            local data = hyperlink(link)
            local item = data and items[data.id]
            if not item then
                return data
            end
            if world.notThere[data.id] then
                data.lines = { { type = NONE, leftText = env.RETRIEVING_ITEM_INFO, leftColor = env.CreateColor(1, 0.125, 0.125, 1) } }
                return data
            end
            local set = item.set and SETS[item.set]
            if not set or world.fault == "no lines" then
                return data
            end
            local lines = data.lines
            local function Line(text, kind, r, g, b)
                lines[#lines + 1] = { type = kind, leftText = text, leftColor = env.CreateColor(r, g, b, 1) }
            end
            if item.oddLine then
                Line(env.ITEM_SET_NAME:format("Charges of Oddity", 1, 3), NONE, 1, 1, 1)
                Line("Not a piece of anything.", NONE, 1, 1, 1)
            end
            local wornCount, pieceLines = 0, {}
            for id, other in pairs(items) do
                if other.set == item.set then
                    local isWorn = false
                    for _, wornID in pairs(world.worn) do
                        isWorn = isWorn or wornID == id
                    end
                    wornCount = wornCount + (isWorn and 1 or 0)
                    pieceLines[#pieceLines + 1] = { name = other.name, worn = isWorn }
                end
            end
            table.sort(pieceLines, function(a, b) return a.name < b.name end)
            Line(" ", BLANK, 1, 0.82, 0)
            Line(env.ITEM_SET_NAME:format(set.name, wornCount + (world.fault == "count" and 1 or 0), set.total), NONE, 1, 0.82, 0)
            for _, piece in ipairs(pieceLines) do
                if piece.worn then
                    Line("  " .. piece.name, NONE, 1, 1, 0.59)
                else
                    Line("  " .. piece.name, DISABLED, 0.5, 0.5, 0.5)
                end
            end
            Line(" ", BLANK, 1, 0.82, 0)
            if set.legacy then
                Line(env.ITEM_SET_LEGACY_INACTIVE_BONUS, NONE, 1, 0.125, 0.125)
            end
            for position, pieces in ipairs(world.bonusesOf and world.bonusesOf[item.set] or set.bonuses) do
                local text = ("Does test thing %d."):format(position)
                if wornCount >= pieces and not set.legacy then
                    Line(env.ITEM_SET_BONUS:format(text), world.fault == "had greyed" and DISABLED or NONE, 0, 1, 0)
                else
                    Line(env.ITEM_SET_BONUS_GRAY:format(pieces, text), world.fault == "not greyed" and NONE or DISABLED, 0.5, 0.5, 0.5)
                end
            end
            Line(" ", BLANK, 1, 0.82, 0)
            Line("Sell Price: 9", NONE, 1, 1, 1)
            return data
        end)

        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
        if saved then
            rawset(env, "CaerdonSetBonusData", H.DeepCopy(saved))
        end
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "features/Tooltip.lua", namespace)
        Equal(#client.errors, 0, flavor .. ": no error reached the error handler at the start (" .. tostring(client.errors[1]) .. ")")

        -- What is worn, slot -> item; everything kept from the gear before is dropped.
        function world.Wear(worn)
            world.worn = worn
            env.CaerdonEquipment:InvalidateCaches()
            env.CaerdonSetBonuses:ForgetAnswers()
        end
        function world.Forget()
            rawset(env, "CaerdonSetBonusData", nil)
            env.CaerdonSetBonuses:ForgetAnswers()
        end
        -- What wearing the item would do, as one text: "gain Set 2; loss Set 4; maybe Set".
        function world.Changes(itemID)
            local item = env.CaerdonItem:CreateFromItemID(itemID)
            local changes, why = item:GetSetBonusChanges()
            local texts = {}
            for index, change in ipairs(changes or {}) do
                texts[index] = change.kind .. " " .. tostring(change.set) .. (change.pieces and (" " .. change.pieces) or "") ..
                    (change.inPlaceOf and (" for " .. change.inPlaceOf) or change.emptySlot and " for the empty slot" or "")
            end
            return changes and table.concat(texts, "; ") or nil, why
        end
        function world.TooltipLines(itemID)
            local tooltip = { lines = {} }
            function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
            namespace.Tooltip:AddSetBonusChanges(tooltip, env.CaerdonItem:CreateFromItemID(itemID))
            return tooltip.lines
        end
        return client, world, namespace
    end

    local BLOOM, ARENA, DEFIAS = SETS.bloom.name, SETS.arena.name, SETS.defias.name

    for _, flavor in ipairs({ "forever", "retail" }) do
        local client, world, namespace = Start(flavor)
        local env = client.env
        local function Is(itemID, expected, label)
            Equal(world.Changes(itemID), expected, flavor .. ": " .. label)
        end

        ----------------------------------------------------------------------------------
        -- Reading a tooltip
        ----------------------------------------------------------------------------------
        world.Wear({ [5] = BLOOM_CHEST, [7] = BLOOM_LEGS })
        local reading = env.CaerdonSetBonuses:Read(env.C_TooltipInfo.GetHyperlink(env.CaerdonItem:CreateFromItemID(BLOOM_HEAD):GetItemLink()))
        Check(reading ~= nil, flavor .. ": a set piece's tooltip is read")
        if reading then
            Equal(reading.name, BLOOM, flavor .. ": the set's name")
            Equal(reading.worn, 2, flavor .. ": the pieces worn")
            Equal(reading.total, 5, flavor .. ": the pieces in all")
            Equal(#reading.bonuses, 2, flavor .. ": both bonuses")
            Equal(reading.bonuses[1].active, true, flavor .. ": the first is one the toon has")
            Equal(reading.bonuses[1].needs, nil, flavor .. ": and has no number")
            Equal(reading.bonuses[2].needs, 4, flavor .. ": the second begins at four")
            Equal(reading.bonuses[2].text, "Does test thing 2.", flavor .. ": with its text")
        end
        Equal(env.CaerdonSetBonuses:Read(env.C_TooltipInfo.GetHyperlink(env.CaerdonItem:CreateFromItemID(PLAIN_HEAD):GetItemLink())), nil,
            flavor .. ": a piece of no set has no set lines")
        local odd = env.CaerdonSetBonuses:Read(env.C_TooltipInfo.GetHyperlink(env.CaerdonItem:CreateFromItemID(ODD_HEAD):GetItemLink()))
        Equal(odd and odd.name, BLOOM, flavor .. ": a line of the set line's shape with no piece under it is passed over")
        Equal(env.CaerdonSetBonuses:Read(nil), nil, flavor .. ": no tooltip, nothing read")
        Equal(env.CaerdonSetBonuses:Read({ lines = {} }), nil, flavor .. ": nor of one without lines")

        ----------------------------------------------------------------------------------
        -- A bonus gained
        ----------------------------------------------------------------------------------
        world.Forget()
        world.Wear({})
        local nothing, why = world.Changes(BLOOM_HEAD)
        Equal(nothing, nil, flavor .. ": the first piece of a set brings no bonus")
        Equal(why, "no bonus begins or ends with it", flavor .. ": and the export is told why")
        world.Wear({ [5] = BLOOM_CHEST })
        Is(BLOOM_HEAD, "gain " .. BLOOM .. " 2", "the second piece brings the two-piece bonus")
        world.Wear({ [5] = BLOOM_CHEST, [1] = PLAIN_HEAD })
        Is(BLOOM_HEAD, "gain " .. BLOOM .. " 2", "also in the place of a piece of no set")
        world.Wear({ [5] = BLOOM_CHEST, [7] = BLOOM_LEGS })
        Is(BLOOM_HEAD, nil, "the third brings none")
        world.Wear({ [5] = BLOOM_CHEST, [7] = BLOOM_LEGS, [10] = BLOOM_HANDS })
        Is(BLOOM_HEAD, "gain " .. BLOOM .. " 4", "the fourth brings the four-piece bonus")
        world.Wear({ [5] = BLOOM_CHEST, [1] = BLOOM_HEAD_TWO })
        Is(BLOOM_HEAD, nil, "a piece in the place of another of its set changes nothing")
        local _, sameWhy = world.Changes(BLOOM_HEAD)
        Equal(sameWhy, "no bonus begins or ends with it", flavor .. ": and says so")

        ----------------------------------------------------------------------------------
        -- A bonus lost, with its pieces remembered
        ----------------------------------------------------------------------------------
        -- The tooltips above showed both bonuses while the toon had neither.
        local remembered = env.CaerdonSetBonusData and env.CaerdonSetBonusData[SETS.bloom.id]
        Check(remembered ~= nil, flavor .. ": what the tooltips showed of the set is kept under its ID")
        Equal(remembered and remembered.pieces[1], 2, flavor .. ": the first bonus begins at two")
        Equal(remembered and remembered.pieces[2], 4, flavor .. ": the second at four")
        Equal(remembered and remembered.bonuses, 2, flavor .. ": of two bonuses")
        world.Wear({ [5] = BLOOM_CHEST, [1] = BLOOM_HEAD })
        Is(PLAIN_HEAD, "loss " .. BLOOM .. " 2", "a plain piece in a set piece's place, two worn: the two-piece bonus ends")
        world.Wear({ [5] = BLOOM_CHEST, [1] = BLOOM_HEAD, [7] = BLOOM_LEGS })
        Is(PLAIN_HEAD, nil, "three worn: it stays")
        world.Wear({ [5] = BLOOM_CHEST, [1] = BLOOM_HEAD, [7] = BLOOM_LEGS, [10] = BLOOM_HANDS })
        Is(PLAIN_HEAD, "loss " .. BLOOM .. " 4", "four worn: the four-piece bonus ends, the two-piece one stays")
        world.Wear({ [5] = BLOOM_CHEST, [1] = BLOOM_HEAD, [7] = BLOOM_LEGS, [10] = BLOOM_HANDS, [3] = BLOOM_SHOULDER })
        Is(PLAIN_HEAD, nil, "five worn: both stay")
        Is(PLAIN_WAIST, nil, "a piece for a slot with no set piece changes nothing")
        local _, noSetWhy = world.Changes(PLAIN_WAIST)
        Equal(noSetWhy, "neither the piece nor what it would take off is of an item set", flavor .. ": and says so")

        ----------------------------------------------------------------------------------
        -- A bonus the toon has whose pieces nothing has shown
        ----------------------------------------------------------------------------------
        world.Forget()
        world.Wear({ [5] = BLOOM_CHEST, [1] = BLOOM_HEAD })
        Is(PLAIN_HEAD, "maybe " .. BLOOM, "two worn and nothing remembered: the bonus may end")
        Equal(env.CaerdonSetBonusData[SETS.bloom.id].pieces[1], nil, flavor .. ": a bonus the toon has teaches no number")
        Equal(env.CaerdonSetBonusData[SETS.bloom.id].pieces[2], 4, flavor .. ": the one it does not have does")
        world.Wear({ [5] = BLOOM_CHEST, [1] = BLOOM_HEAD, [7] = BLOOM_LEGS, [10] = BLOOM_HANDS })
        Is(PLAIN_HEAD, "loss " .. BLOOM .. " 4",
            "four worn, the second bonus's pieces remembered and the first's not: the first needs no more than the second, one line")
        world.Forget()
        Is(PLAIN_HEAD, "maybe " .. BLOOM, "four worn and nothing remembered: one line for the set")
        -- A piece taken off shows the bonus with its number, and the answer is asked again.
        world.Wear({ [5] = BLOOM_CHEST, [1] = BLOOM_HEAD, [7] = BLOOM_LEGS })
        Is(BLOOM_HANDS, "gain " .. BLOOM .. " 4", "the piece taken off: it would bring the bonus back")
        world.Wear({ [5] = BLOOM_CHEST, [1] = BLOOM_HEAD, [7] = BLOOM_LEGS, [10] = BLOOM_HANDS })
        Is(PLAIN_HEAD, "loss " .. BLOOM .. " 4", "and with it on again the loss is known")

        -- What the status code hands over teaches as well: a piece judged for its icon.
        world.Forget()
        world.Wear({ [5] = BLOOM_CHEST })
        local judged = env.CaerdonItem:CreateFromItemID(BLOOM_LEGS)
        local ready
        client:TickUntil(function()
            ready = judged:GetCaerdonStatus()
            return ready
        end, 10)
        Check(ready, flavor .. ": a set piece is judged for its icon")
        Equal(env.CaerdonSetBonusData and env.CaerdonSetBonusData[SETS.bloom.id] and env.CaerdonSetBonusData[SETS.bloom.id].pieces[1], 2,
            flavor .. ": and its tooltip's numbers are kept")
        world.Wear({ [5] = BLOOM_CHEST, [1] = BLOOM_HEAD })
        Is(PLAIN_HEAD, "loss " .. BLOOM .. " 2", "so the loss is known without the piece ever being hovered")

        ----------------------------------------------------------------------------------
        -- What is remembered is checked against what is shown
        ----------------------------------------------------------------------------------
        rawset(env, "CaerdonSetBonusData", { [SETS.bloom.id] = { name = BLOOM, bonuses = 2, pieces = { 3, 4 } } })
        world.Wear({ [5] = BLOOM_CHEST, [1] = BLOOM_HEAD })
        Is(PLAIN_HEAD, "maybe " .. BLOOM, "a remembered number above what is worn, for a bonus the toon has, is not believed")
        Equal(env.CaerdonSetBonusData[SETS.bloom.id].pieces[1], nil, flavor .. ": and is dropped")
        rawset(env, "CaerdonSetBonusData", { [SETS.bloom.id] = { name = BLOOM, bonuses = 3, pieces = { 2, 3, 4 } } })
        world.Wear({ [5] = BLOOM_CHEST, [1] = BLOOM_HEAD })
        Is(PLAIN_HEAD, "maybe " .. BLOOM, "numbers remembered of another count of bonuses are not used")
        Equal(env.CaerdonSetBonusData[SETS.bloom.id].bonuses, 2, flavor .. ": the set is begun anew")
        rawset(env, "CaerdonSetBonusData", "not a table")
        world.Wear({ [5] = BLOOM_CHEST })
        Is(BLOOM_HEAD, "gain " .. BLOOM .. " 2", "saved data that is no table is replaced")

        -- The order of the bonuses: a number not remembered is at most a later one's.
        world.Forget()
        world.bonusesOf = { defias = { 2, 3, 4 } }
        rawset(env, "CaerdonSetBonusData", { [SETS.defias.id] = { name = DEFIAS, bonuses = 3, pieces = { nil, 3, 4 } } })
        world.Wear({ [5] = DEFIAS_CHEST, [6] = DEFIAS_WAIST, [8] = DEFIAS_FEET, [10] = DEFIAS_HANDS, [7] = DEFIAS_LEGS })
        Is(PLAIN_WAIST, nil, "five worn, the later bonuses at three and four: the first cannot need five")
        rawset(env, "CaerdonSetBonusData", { [SETS.defias.id] = { name = DEFIAS, bonuses = 3, pieces = { nil, 4, 3 } } })
        world.Wear({ [5] = DEFIAS_CHEST, [6] = DEFIAS_WAIST, [8] = DEFIAS_FEET, [10] = DEFIAS_HANDS, [7] = DEFIAS_LEGS })
        Is(PLAIN_WAIST, "maybe " .. DEFIAS, "numbers that are not in ascending order say nothing of the one not remembered")
        world.bonusesOf = nil

        ----------------------------------------------------------------------------------
        -- A set with a bonus at every count, and two bonuses at one
        ----------------------------------------------------------------------------------
        world.Forget()
        world.Wear({ [5] = DEFIAS_CHEST })
        Is(DEFIAS_WAIST, "gain " .. DEFIAS .. " 2", "two of five: the two-piece bonus")
        world.Wear({ [5] = DEFIAS_CHEST, [6] = DEFIAS_WAIST })
        Is(DEFIAS_FEET, "gain " .. DEFIAS .. " 3", "three: the three-piece bonus")
        Is(PLAIN_WAIST, "loss " .. DEFIAS .. " 2", "a plain belt for the set's: the two-piece bonus ends")
        world.Wear({ [5] = DEFIAS_CHEST, [6] = DEFIAS_WAIST, [8] = DEFIAS_FEET, [10] = DEFIAS_HANDS })
        Is(DEFIAS_LEGS, "gain " .. DEFIAS .. " 5", "five: the five-piece bonus")
        Is(PLAIN_WAIST, "loss " .. DEFIAS .. " 4", "four worn and one off: the four-piece bonus ends, the others stay")

        world.Forget()
        world.Wear({ [1] = TWIN_HEAD, [3] = TWIN_SHOULDER, [5] = TWIN_CHEST })
        Is(TWIN_HANDS, "gain " .. SETS.twins.name .. " 4", "two bonuses that begin at four pieces have one line")
        world.Wear({ [1] = TWIN_HEAD, [3] = TWIN_SHOULDER, [5] = TWIN_CHEST, [10] = TWIN_HANDS })
        Is(PLAIN_HEAD, "loss " .. SETS.twins.name .. " 4", "and one where both end")

        ----------------------------------------------------------------------------------
        -- A gain and a loss at once
        ----------------------------------------------------------------------------------
        world.Forget()
        world.Wear({ [1] = ARENA_HEAD, [5] = BLOOM_CHEST })
        world.Changes(ARENA_HANDS) -- shows the arena set's two-piece bonus with its number
        world.Wear({ [1] = ARENA_HEAD, [10] = ARENA_HANDS, [5] = BLOOM_CHEST })
        Is(BLOOM_HANDS, "gain " .. BLOOM .. " 2; loss " .. ARENA .. " 2",
            "a piece of one set in the place of another's: one bonus begins, the other ends")
        world.Wear({ [1] = ARENA_HEAD, [10] = ARENA_HANDS, [7] = ARENA_LEGS, [5] = BLOOM_CHEST })
        Is(BLOOM_HANDS, "gain " .. BLOOM .. " 2", "with a third piece of the other set on, only the gain")

        ----------------------------------------------------------------------------------
        -- A piece that can go in two places
        ----------------------------------------------------------------------------------
        world.Forget()
        world.Wear({ [11] = RING_A })
        Is(RING_B, "gain " .. SETS.rings.name .. " 2 for the empty slot",
            "a ring beside its set's other: the bonus in the empty place, nothing in the other ring's")
        world.Wear({ [11] = RING_A, [12] = PLAIN_RING })
        Is(RING_B, "gain " .. SETS.rings.name .. " 2 for Plain Band", "with a plain ring in the second place: named")
        world.Wear({ [11] = PLAIN_RING, [12] = OTHER_RING })
        Is(RING_B, nil, "one ring of the set and none worn: nothing")
        world.Wear({ [11] = RING_A, [12] = RING_B })
        Is(PLAIN_RING, "loss " .. SETS.rings.name .. " 2", "a plain ring for either of the set's two: the same in both places, said once")
        world.Wear({ [11] = RING_A, [12] = OTHER_RING })
        Is(PLAIN_RING, nil, "one of the set's rings worn and no bonus: nothing in either place")

        ----------------------------------------------------------------------------------
        -- Weapons
        ----------------------------------------------------------------------------------
        world.Forget()
        world.Wear({ [16] = BLADE_MAIN })
        Is(BLADE_OFF, "gain " .. SETS.blades.name .. " 2", "the off hand's piece of a pair")
        world.Wear({ [16] = BLADE_MAIN, [17] = BLADE_OFF })
        Is(PLAIN_STAFF, "loss " .. SETS.blades.name .. " 2", "a two-hander takes both off")
        Is(PLAIN_SHIELD, "loss " .. SETS.blades.name .. " 2", "a held piece takes the off hand's")
        world.Wear({ [16] = RELIC_STAFF })
        world.Changes(RELIC_NECK)
        world.Wear({ [16] = RELIC_STAFF, [2] = RELIC_NECK })
        Is(PLAIN_SHIELD, "loss " .. SETS.relic.name .. " 2", "a held piece takes a two-hander off with it")
        world.Wear({ [16] = PLAIN_SWORD, [17] = RELIC_ORB, [2] = RELIC_NECK })
        Is(PLAIN_STAFF, "loss " .. SETS.relic.name .. " 2", "a two-hander takes the off hand's piece off as well as the main hand's")
        Is(PLAIN_DAGGER, nil, "a one-hander goes in the main hand of a toon that holds one weapon")
        world.dualWield = true
        world.Wear({ [16] = PLAIN_SWORD, [17] = RELIC_ORB, [2] = RELIC_NECK })
        Is(PLAIN_DAGGER, "loss " .. SETS.relic.name .. " 2 for Reliquary Orb", "and in either hand of one that holds two: said for the off hand's piece")
        world.dualWield = nil

        ----------------------------------------------------------------------------------
        -- What is not asked, or cannot be said
        ----------------------------------------------------------------------------------
        world.Forget()
        world.Wear({ [5] = BLOOM_CHEST, [1] = BLOOM_HEAD })
        local wornChanges, wornWhy = world.Changes(BLOOM_HEAD)
        Equal(wornChanges, nil, flavor .. ": a piece that is being worn has nothing")
        Equal(wornWhy, "the piece is being worn", flavor .. ": and says so")
        local potionChanges, potionWhy = world.Changes(POTION)
        Equal(potionChanges, nil, flavor .. ": nor has a potion")
        Equal(potionWhy, "not a piece of equipment", flavor .. ": which is said too")

        world.Wear({ [5] = OLD_CHEST })
        Is(OLD_HEAD, nil, "a set the client calls legacy, its bonuses not working: no gain")
        world.Wear({ [5] = OLD_CHEST, [1] = OLD_HEAD })
        Is(PLAIN_HEAD, nil, "and no loss")

        world.Forget()
        world.Wear({ [5] = NAMELESS_CHEST })
        Is(NAMELESS_HEAD, "gain " .. SETS.nameless.name .. " 2", "a set the item info names no ID for is known by its name")
        Check(env.CaerdonSetBonusData[SETS.nameless.name] ~= nil, flavor .. ": and filed under it")
        world.Wear({ [5] = NAMELESS_CHEST, [1] = NAMELESS_HEAD })
        Is(PLAIN_HEAD, "loss " .. SETS.nameless.name .. " 2", "with its numbers remembered there")
        Is(NAMELESS_HEAD_TWO, nil, "and a piece in the place of another of that set changes nothing")

        -- The worn piece's tooltip is not there yet: nothing is said, and nothing is kept.
        world.Forget()
        world.Wear({ [5] = BLOOM_CHEST })
        world.Changes(BLOOM_HEAD)
        world.Wear({ [5] = BLOOM_CHEST, [1] = BLOOM_HEAD })
        world.notThere[BLOOM_HEAD] = true
        local lateChanges, lateWhy = world.Changes(PLAIN_HEAD)
        Equal(lateChanges, nil, flavor .. ": the worn piece's tooltip not there yet: nothing")
        Equal(lateWhy, "a tooltip it is read from is not there yet", flavor .. ": with the reason")
        world.notThere[BLOOM_HEAD] = nil
        Is(PLAIN_HEAD, "loss " .. BLOOM .. " 2", "and the answer once it is")

        -- The last answer is kept for a tooltip that is filled again, until the gear changes.
        local askedBefore = world.asked
        Is(PLAIN_HEAD, "loss " .. BLOOM .. " 2", "asked again")
        Equal(world.asked, askedBefore, flavor .. ": no tooltip is read for the same piece twice in a row")
        world.worn = { [5] = BLOOM_CHEST, [1] = BLOOM_HEAD, [7] = BLOOM_LEGS }
        client:Fire("PLAYER_EQUIPMENT_CHANGED", 7, false)
        client:Tick(2)
        Is(PLAIN_HEAD, nil, "a change of the worn gear and the answer is made anew")

        ----------------------------------------------------------------------------------
        -- The tooltip's lines
        ----------------------------------------------------------------------------------
        world.Forget()
        world.Wear({ [1] = ARENA_HEAD, [5] = BLOOM_CHEST })
        world.Changes(ARENA_HANDS)
        world.Wear({ [1] = ARENA_HEAD, [10] = ARENA_HANDS, [5] = BLOOM_CHEST })
        local lines = world.TooltipLines(BLOOM_HANDS)
        Equal(#lines, 2, flavor .. ": a line for the bonus gained and one for the bonus lost")
        Equal(lines[1], "|cffffd100" .. BLOOM .. ":|r  |cff00ff00gains the 2-piece set bonus|r", flavor .. ": the gain, in green")
        Equal(lines[2], "|cffffd100" .. ARENA .. ":|r  |cffff2020loses the 2-piece set bonus|r", flavor .. ": the loss, in red")
        world.Forget()
        lines = world.TooltipLines(BLOOM_HANDS)
        Equal(lines[2], "|cffffd100" .. ARENA .. ":|r  |cffff2020may lose a set bonus|r", flavor .. ": a loss that is not certain")
        world.Wear({ [11] = RING_A, [12] = PLAIN_RING })
        lines = world.TooltipLines(RING_B)
        Equal(lines[1], "|cffffd100" .. SETS.rings.name .. ":|r  |cff00ff00gains the 2-piece set bonus|r  |cff808080(in place of Plain Band)|r",
            flavor .. ": which of two places a line is about")
        world.Wear({ [11] = RING_A })
        lines = world.TooltipLines(RING_B)
        Equal(lines[1], "|cffffd100" .. SETS.rings.name .. ":|r  |cff00ff00gains the 2-piece set bonus|r  |cff808080(in the empty slot)|r",
            flavor .. ": or that it is the empty one")
        Equal(#world.TooltipLines(PLAIN_WAIST), 0, flavor .. ": no line for a piece that changes nothing")
        Equal(#world.TooltipLines(POTION), 0, flavor .. ": none for a potion")
        env.CaerdonWardrobeConfig.Tooltip.ShowSetBonusChanges = false
        Equal(#world.TooltipLines(RING_B), 0, flavor .. ": the setting turns the lines off")
        env.CaerdonWardrobeConfig.Tooltip.ShowSetBonusChanges = true
        Equal(namespace:GetDefaultConfig().Tooltip.ShowSetBonusChanges, true, flavor .. ": which is on by default")

        -- Where the lines go: with the upgrade lines. Without Pawn, into the client's own item
        -- tooltip as it is filled; with Pawn, after Pawn's lines, from the function Pawn adds
        -- its own in; never into a comparison tooltip.
        do
            local function Tip()
                local tip = { lines = {} }
                function tip:AddLine(text) self.lines[#self.lines + 1] = text end
                function tip:HookScript() end
                return tip
            end
            world.Wear({ [11] = RING_A })
            local piece = env.CaerdonItem:CreateFromItemID(RING_B)
            local shown, another = Tip(), Tip()
            namespace.Tooltip:PlaceUpgradeLines(shown)
            namespace.Tooltip:OweUpgradeLines(shown, piece)
            Equal(#shown.lines, 1, flavor .. ": the client's item tooltip has the line as it is filled")
            Check(tostring(shown.lines[1]):find("gains the 2-piece set bonus", 1, true) ~= nil, flavor .. ": the set's line")
            namespace.Tooltip:OweUpgradeLines(another, piece)
            Equal(#another.lines, 0, flavor .. ": a tooltip that is not the client's item tooltip has none")

            rawset(env, "PawnAddValuesToTooltip", function(tooltip) tooltip:AddLine("pawn's line") end)
            namespace.Tooltip:PlaceUpgradeLines()
            shown.lines = {}
            namespace.Tooltip:OweUpgradeLines(shown, piece)
            Equal(#shown.lines, 0, flavor .. ": with Pawn the handler adds nothing by itself")
            env.PawnAddValuesToTooltip(shown, "values", nil)
            Equal(shown.lines[1], "pawn's line", flavor .. ": Pawn's own lines come first")
            Check(tostring(shown.lines[2]):find("gains the 2-piece set bonus", 1, true) ~= nil, flavor .. ": the set's line follows them")
            Equal(#shown.lines, 2, flavor .. ": and that is all")
            env.PawnAddValuesToTooltip(shown, "values", nil)
            Equal(#shown.lines, 3, flavor .. ": a filling the handler did not see is Pawn's alone")
            local beside = Tip()
            namespace.Tooltip:NoteComparisonTooltips(beside)
            namespace.Tooltip:OweUpgradeLines(beside, piece)
            env.PawnAddValuesToTooltip(beside, "values", nil)
            Equal(table.concat(beside.lines, " | "), "pawn's line", flavor .. ": a comparison tooltip has no line of the addon's")
        end

        -- The export's lines.
        world.Forget()
        world.Wear({ [1] = ARENA_HEAD, [10] = ARENA_HANDS, [5] = BLOOM_CHEST })
        local described = table.concat(env.CaerdonSetBonuses:Describe(env.CaerdonItem:CreateFromItemID(BLOOM_HANDS)), "\n")
        Check(described:find("Read Off Its Tooltip: \"" .. BLOOM .. "\" (filed under set 7001), 1 worn", 1, true) ~= nil,
            flavor .. ": the export says what was read off the piece (" .. described .. ")")
        Check(described:find("Worn In Slot 10: \"" .. ARENA .. "\"", 1, true) ~= nil, flavor .. ": and off the piece it would take off")
        Check(described:find("1: had, pieces not remembered", 1, true) ~= nil, flavor .. ": with what is not remembered")
        Check(described:find("Wearing It: \"" .. ARENA .. "\" may end a bonus", 1, true) ~= nil, flavor .. ": and what the line would say")

        ----------------------------------------------------------------------------------
        -- The test addon's contract: the same lines asked of what a toon wears and carries
        ----------------------------------------------------------------------------------
        do
            world.Forget()
            world.Wear({ [5] = BLOOM_CHEST, [1] = BLOOM_HEAD, [6] = DEFIAS_WAIST, [10] = PLAIN_HANDS })
            world.bag = { BLOOM_LEGS, DEFIAS_FEET, PLAIN_HEAD, POTION, NAMELESS_HEAD }
            local wanted = { ["Core.lua"] = true, ["Runner.lua"] = true, ["Contracts.lua"] = true, ["Plan.lua"] = true }
            local T = H.LoadAddon(client, "CaerdonWardrobe_Tests", H.addonDir .. "/CaerdonWardrobe_Tests",
                function(relative) return not wanted[relative] end)
            client:Fire("ADDON_LOADED", "CaerdonWardrobe_Tests")
            client:Fire("PLAYER_LOGIN")
            local ID = "tooltip.setBonuses"
            local function Contract()
                T.RunTests({ match = ID, force = true })
                Check(client:TickUntil(function() return not T.IsBusy() end, 120), flavor .. ", contract: the job ends")
                return (T.db.contracts[T.GetClient().build] or {})[ID] or {}
            end

            local result = Contract()
            Equal(result.status, "pass", flavor .. ", contract: it passes on what is worn and carried (" .. tostring(result.message) .. ")")
            local detail = result.detail or {}
            Equal(detail.pieces, 9, flavor .. ", contract: four worn and five carried")
            Equal(detail.ofSets, 6, flavor .. ", contract: six of them of a set")
            Equal(detail.withSetID, 5, flavor .. ", contract: five whose item info names the set")
            Equal(detail.withoutSetID, 1, flavor .. ", contract: one whose item info does not")
            Equal(detail.bonusesHad, 3, flavor .. ", contract: the two-piece bonus on each of three pieces")
            Equal(detail.bonusesNotHad, 12, flavor .. ", contract: the bonuses not had")
            Equal(detail.writtenBack, 15, flavor .. ", contract: every bonus line written back")
            local bloomStates = (detail.sets or {})[BLOOM .. " (set 7001)"] or {}
            Equal(bloomStates[1], "2 of 5 worn: had, (4)", flavor .. ", contract: the set as seen is kept")
            Equal(((detail.sets or {})[SETS.nameless.name .. " (no set ID)"] or {})[1], "0 of 2 worn: (2)",
                flavor .. ", contract: a set without an ID under its name")
            world.Wear({ [5] = BLOOM_CHEST, [6] = DEFIAS_WAIST })
            result = Contract()
            Equal(result.status, "pass", flavor .. ", contract: and with fewer worn")
            Equal(#(((result.detail or {}).sets or {})[BLOOM .. " (set 7001)"] or {}), 2,
                flavor .. ", contract: a second run adds the set as it then stands")
            Equal((((result.detail or {}).sets or {})[BLOOM .. " (set 7001)"] or {})[2], "1 of 5 worn: (2), (4)",
                flavor .. ", contract: with the number that was gone")

            -- A toon with no piece of a set answers nothing.
            world.Wear({ [10] = PLAIN_HANDS })
            world.bag = { PLAIN_HEAD, POTION }
            Equal(Contract().status, "info", flavor .. ", contract: no piece of a set is no pass")

            -- Faults, one at a time: a client that writes a set's lines another way.
            world.Wear({ [5] = BLOOM_CHEST, [1] = BLOOM_HEAD, [6] = DEFIAS_WAIST })
            world.bag = { BLOOM_LEGS, DEFIAS_FEET }
            local function Fault(label, plant, undo, expected)
                plant()
                local faulty = Contract()
                Equal(faulty.status, "fail", flavor .. ", fault, " .. label .. ": the contract fails")
                Check(tostring(faulty.message):find(expected, 1, true) ~= nil,
                    flavor .. ", fault, " .. label .. ": and says why (" .. tostring(faulty.message) .. ")")
                undo()
            end
            local function NoFault() world.fault = nil end
            Fault("a set piece without set lines", function() world.fault = "no lines" end, NoFault, "has no set lines the addon reads")
            Fault("a set's line that counts another number worn", function() world.fault = "count" end, NoFault, "worn pieces are of set")
            Fault("a set the client calls by another name", function() world.fault = "name" end, NoFault, "the client calls set")
            Fault("a bonus not had on a line that is not greyed out", function() world.fault = "not greyed" end, NoFault, "not greyed out")
            Fault("a bonus the toon has on a greyed-out line", function() world.fault = "had greyed" end, NoFault, "is greyed out")
            Fault("bonuses that are not in ascending order", function() world.bonusesOf = { defias = { 4, 2, 5 } } end,
                function() world.bonusesOf = nil end, "not in ascending order")
            Equal(Contract().status, "pass", flavor .. ", contract: and passes again without the faults")
        end

        Equal(#client.errors, 0, flavor .. ": no error reached the error handler (" .. tostring(client.errors[1]) .. ")")
    end

    --------------------------------------------------------------------------------------
    -- What one session remembered is there in the next
    --------------------------------------------------------------------------------------
    do
        local client, world = Start("forever", { [SETS.bloom.id] = { name = BLOOM, bonuses = 2, pieces = { 2, 4 } } })
        world.Wear({ [5] = BLOOM_CHEST, [1] = BLOOM_HEAD, [7] = BLOOM_LEGS, [10] = BLOOM_HANDS })
        Equal(world.Changes(PLAIN_HEAD), "loss " .. BLOOM .. " 4", "saved numbers are used by a session that has seen no tooltip of the set's")
        Equal(#client.errors, 0, "no error reached the error handler (" .. tostring(client.errors[1]) .. ")")
    end
end
