-- The account-bound label comes from what the tooltip's binding line says as a number
-- (CaerdonItem.lua, ACCOUNT_BONDING and GetTooltipData).
--
-- The binding line (type 20) carries `bonding`, a value of Enum.TooltipDataItemBinding, in
-- both clients. Four of its values say the item is or will be bound to the account, and they
-- give the label whatever the line's text is. A line without the field is still read by its
-- text, which is one of four global strings (two texts in each client, and not the same two:
-- "Warbound" on retail, "Account bound" on WoW Forever). The tooltip's label counts only
-- where the item's bind type gave none.
--
-- The game is hand-made. The values 0, 3, 6 and 7 are what the clients' recordings carry
-- (the fixtures of both flavors); retail has shown 1, 5, 9 and 10 in its bags, and no client
-- has shown 2, 4 or 8.
--
-- The second half is the test addon's contract tooltip.accountBonding, which asks a client
-- whether the number and the text say the same on every binding line in the bags: on bags
-- where they do, on bags with no account-bound item, and with faults planted one at a time.
--
-- Real code: the addon's item side, the test addon's runner and contracts, Blizzard's base
-- files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 33 }

    local BINDING_LINE = 20
    local ON_PICKUP, ON_EQUIP = 1, 2 -- bind types
    -- What the binding line says, by name, and whether that is the account.
    local BONDINGS = {
        { "Quest", 0, false }, { "Account", 1, true }, { "BnetAccount", 2, true }, { "Soulbound", 3, false },
        { "BindToAccount", 4, true }, { "BindToBnetAccount", 5, true }, { "BindOnPickup", 6, false },
        { "BindOnEquip", 7, false }, { "BindOnUse", 8, false }, { "AccountUntilEquipped", 9, false },
        { "BindToAccountUntilEquipped", 10, false },
    }
    -- The four strings a line without the field is read by, and three it is not.
    local ACCOUNT_STRINGS = { "ITEM_ACCOUNTBOUND", "ITEM_BNETACCOUNTBOUND", "ITEM_BIND_TO_ACCOUNT",
        "ITEM_BIND_TO_BNETACCOUNT" }
    local OTHER_STRINGS = { "ITEM_SOULBOUND", "ITEM_BIND_ON_PICKUP", "ITEM_ACCOUNTBOUND_UNTIL_EQUIP" }

    local FIELD_ID, TEXT_ID, OTHER_TEXT_ID, FIELD_FIRST_ID, BIND_TYPE_ID, NO_LINE_ID, WORN_ID =
        990100, 990200, 990300, 990400, 990500, 990600, 990900
    local BAG_ACCOUNT_ID, BAG_PLAIN_ID = 990701, 990702
    local MAIN_HAND = 16

    local nextSource = 7600
    local function Piece(name, bindType, line)
        nextSource = nextSource + 1
        return { name = name, quality = 2, level = 33, minLevel = 0, type = "Armor", subType = "Miscellaneous",
            stack = 1, equipLoc = "INVTYPE_HOLDABLE", price = 5000, classID = 4, subClassID = 0, bindType = bindType,
            tooltip = { line, { text = "+5 Spirit" } },
            appearance = { appearanceID = nextSource - 2000, sourceID = nextSource, collected = true } }
    end

    local function Start(flavor)
        local items = {}
        -- The field, with a text that is none of the client's.
        for _, bonding in ipairs(BONDINGS) do
            items[FIELD_ID + bonding[2]] = Piece("Orb of " .. bonding[1], ON_PICKUP,
                { text = "Bound in other words", type = BINDING_LINE, bonding = bonding[2] })
        end
        -- No field: the texts are the client's, set below once its strings are there.
        for index in ipairs(ACCOUNT_STRINGS) do
            items[TEXT_ID + index] = Piece("Old Orb " .. index, ON_PICKUP, { type = BINDING_LINE })
        end
        for index in ipairs(OTHER_STRINGS) do
            items[OTHER_TEXT_ID + index] = Piece("Plain Orb " .. index, ON_PICKUP, { type = BINDING_LINE })
        end
        -- The field says something else than the text.
        items[FIELD_FIRST_ID] = Piece("Odd Orb", ON_PICKUP, { type = BINDING_LINE, bonding = 6 })
        -- The bind type has a label of its own.
        items[BIND_TYPE_ID] = Piece("Traded Orb", ON_EQUIP,
            { text = "Bound in other words", type = BINDING_LINE, bonding = 5 })
        -- No binding line at all.
        items[NO_LINE_ID] = Piece("Bare Orb", ON_PICKUP, { text = "+1 Spirit" })
        -- In the bags, for the contract: the link's line here, the slot's where it is run.
        items[BAG_ACCOUNT_ID] = Piece("Shared Orb", ON_PICKUP, { type = BINDING_LINE, bonding = 5 })
        items[BAG_PLAIN_ID] = Piece("Kept Orb", ON_PICKUP, { type = BINDING_LINE, bonding = 6 })
        -- Worn: a two-handed sword of a lower level with nothing in the off-hand, so an
        -- off-hand piece is no upgrade, no tie and not outdone.
        items[WORN_ID] = { name = "Worn Greatsword", quality = 2, level = 25, minLevel = 20, type = "Weapon",
            subType = "Two-Handed Swords", stack = 1, equipLoc = "INVTYPE_2HWEAPON", price = 900, classID = 2,
            subClassID = 8, bindType = 1, tooltip = { { text = "+9 Stamina" } },
            appearance = { appearanceID = 5398, sourceID = 7498, collected = true } }

        local game = H.StockGame(TOON, items)
        local function Worn(location)
            return type(location) == "table" and location.IsEquipmentSlot and location:IsEquipmentSlot()
                and location:GetEquipmentSlot() == MAIN_HAND and WORN_ID or nil
        end
        local hyperlink = game.names["C_TooltipInfo.GetHyperlink"]
        game:Set("GetInventoryItemID", function(_, slot) return slot == MAIN_HAND and WORN_ID or nil end)
        game:Set("GetInventoryItemLink", function(_, slot) return slot == MAIN_HAND and game.Link(WORN_ID) or nil end)
        game:Set("C_Item.DoesItemExist", function(location) return Worn(location) ~= nil end)
        game:Set("C_Item.GetItemLink", function(location) return Worn(location) and game.Link(WORN_ID) end)
        game:Set("C_Item.GetItemID", function(location) return Worn(location) end)
        game:Set("C_Item.GetItemQuality", function(location) return Worn(location) and items[WORN_ID].quality end)
        game:Set("C_Item.GetItemName", function(location) return Worn(location) and items[WORN_ID].name end)
        game:Set("C_Item.IsBound", function() return false end)
        game:Set("C_Item.GetCurrentItemLevel", function(location) return Worn(location) and items[WORN_ID].level end)
        game:Set("C_TooltipInfo.GetInventoryItem", function(_, slot)
            return slot == MAIN_HAND and hyperlink(game.Link(WORN_ID)) or nil
        end)
        game:Set("C_Item.GetItemInventoryType", function(location)
            return Worn(location) and game.client.env.Enum.InventoryType.Index2HweaponType or 0
        end)
        game:Set("GetInstanceInfo", function() return "Elsewhere", "none" end)
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

        local strings = client.listing.strings
        for index, name in ipairs(ACCOUNT_STRINGS) do
            Check(type(strings[name]) == "string", flavor .. ": the client has " .. name)
            items[TEXT_ID + index].tooltip[1].text = strings[name]
        end
        for index, name in ipairs(OTHER_STRINGS) do
            Check(type(strings[name]) == "string", flavor .. ": the client has " .. name)
            items[OTHER_TEXT_ID + index].tooltip[1].text = strings[name]
        end
        items[FIELD_FIRST_ID].tooltip[1].text = strings.ITEM_ACCOUNTBOUND
        items[BAG_ACCOUNT_ID].tooltip[1].text = strings.ITEM_BIND_TO_BNETACCOUNT
        items[BAG_PLAIN_ID].tooltip[1].text = strings.ITEM_BIND_ON_PICKUP
        return client, game, items
    end

    -- The label the binding gave, and the one the status hands to the drawing.
    local function Label(client, itemID)
        local item = client.env.CaerdonItem:CreateFromItemID(itemID)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        client:TickUntil(function() return loaded end, 10)
        local ready, shown, bindingResult
        client:TickUntil(function()
            local _
            ready, _, shown, bindingResult = item:GetCaerdonStatus()
            return ready
        end, 10)
        return (bindingResult or {}).bindingStatus, shown
    end

    for _, flavor in ipairs({ "forever", "retail" }) do
        local client, game, items = Start(flavor)
        local enum = client.env.Enum.TooltipDataItemBinding
        Check(type(enum) == "table", flavor .. ": the client has the enum")
        for _, bonding in ipairs(BONDINGS) do
            local name, value, isAccount = bonding[1], bonding[2], bonding[3]
            Equal(enum[name], value, flavor .. ", " .. name .. ": the value the cases use is the client's")
            local label, shown = Label(client, FIELD_ID + value)
            Equal(label, isAccount and "BoA" or nil, flavor .. ", field " .. name .. ": the label")
            Equal(shown, isAccount and "BoA" or nil, flavor .. ", field " .. name .. ": and what the status hands on")
        end
        for index, name in ipairs(ACCOUNT_STRINGS) do
            Equal((Label(client, TEXT_ID + index)), "BoA", flavor .. ", no field, " .. name .. ": read by its text")
        end
        for index, name in ipairs(OTHER_STRINGS) do
            Equal((Label(client, OTHER_TEXT_ID + index)), nil, flavor .. ", no field, " .. name .. ": no label")
        end
        Equal((Label(client, FIELD_FIRST_ID)), nil, flavor .. ": a line with the field is not read by its text")
        Equal((Label(client, BIND_TYPE_ID)), "BoE", flavor .. ": the bind type's label comes before the tooltip's")
        Equal((Label(client, NO_LINE_ID)), nil, flavor .. ": no binding line, no label")

        -- The contract. Both orbs lie in the backpack and are bound there: the slot's tooltip
        -- says so where the link's says what the item will be bound to.
        do
            local strings = client.listing.strings
            local bag = { BAG_ACCOUNT_ID, BAG_PLAIN_ID }
            local slotLines = {
                [BAG_ACCOUNT_ID] = { text = strings.ITEM_ACCOUNTBOUND, bonding = 1 },
                [BAG_PLAIN_ID] = { text = strings.ITEM_SOULBOUND, bonding = 3 },
            }
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
                data.lines[2].leftText, data.lines[2].bonding = slotLines[itemID].text, slotLines[itemID].bonding
                data.hyperlink, data.guid = nil, "Item-1-0-" .. itemID
                return data
            end)

            local wanted = { ["Core.lua"] = true, ["Runner.lua"] = true, ["Contracts.lua"] = true, ["Plan.lua"] = true }
            local T = H.LoadAddon(client, "CaerdonWardrobe_Tests", H.addonDir .. "/CaerdonWardrobe_Tests",
                function(relative) return not wanted[relative] end)
            client:Fire("ADDON_LOADED", "CaerdonWardrobe_Tests")
            client:Fire("PLAYER_LOGIN")
            local ID = "tooltip.accountBonding"
            local function Run()
                T.RunTests({ match = ID, force = true })
                Check(client:TickUntil(function() return not T.IsBusy() end, 120), flavor .. ", contract: the job ends")
                return (T.db.contracts[T.GetClient().build] or {})[ID] or {}
            end

            local result = Run()
            Equal(result.status, "pass", flavor .. ", contract: it passes on the bags (" .. tostring(result.message) .. ")")
            local detail = result.detail or {}
            Equal(detail.items, 2, flavor .. ", contract: two items")
            Equal(detail.bindingLines, 4, flavor .. ", contract: a binding line in each of their two tooltips")
            Equal(detail.accountLines, 2, flavor .. ", contract: two of them account bound")
            Equal(detail.withoutField, 0, flavor .. ", contract: none without the field")
            local seen = detail.seen or {}
            Equal(seen[('slot: 1 (Account) "%s"'):format(strings.ITEM_ACCOUNTBOUND)], 1,
                flavor .. ", contract: the slot's line is kept with its value, the value's name and its text")
            Equal(seen[('link: 5 (BindToBnetAccount) "%s"'):format(strings.ITEM_BIND_TO_BNETACCOUNT)], 1,
                flavor .. ", contract: and the link's")
            Equal(seen[('slot: 3 (Soulbound) "%s"'):format(strings.ITEM_SOULBOUND)], 1,
                flavor .. ", contract: the other orb's slot")

            -- What was seen is added to what the run before saw.
            result = Run()
            Equal((result.detail or {}).bindingLines, 8, flavor .. ", contract: a second run adds its lines to the first's")

            -- Bags without an account-bound item answer for the other lines only.
            bag = { BAG_PLAIN_ID }
            result = Run()
            Equal(result.status, "info", flavor .. ", contract: no account-bound item is no pass")
            bag = { BAG_ACCOUNT_ID, BAG_PLAIN_ID }

            -- Faults, one at a time: an account text with another number, an account number
            -- with another text, a binding line without the field, the field on another line.
            local function Fault(label, plant, undo, expected)
                plant()
                local faulty = Run()
                Equal(faulty.status, "fail", flavor .. ", fault, " .. label .. ": the contract fails")
                Check(tostring(faulty.message):find(expected, 1, true) ~= nil,
                    flavor .. ", fault, " .. label .. ": and says why (" .. tostring(faulty.message) .. ")")
                undo()
            end
            local linkLine = items[BAG_ACCOUNT_ID].tooltip[1]
            Fault("the text alone says account", function() linkLine.bonding = 6 end, function() linkLine.bonding = 5 end,
                "the bonding and the text do not agree")
            Fault("the number alone says account", function() slotLines[BAG_PLAIN_ID].bonding = 2 end,
                function() slotLines[BAG_PLAIN_ID].bonding = 3 end, "the bonding and the text do not agree")
            Fault("no field", function() slotLines[BAG_PLAIN_ID].bonding = nil end,
                function() slotLines[BAG_PLAIN_ID].bonding = 3 end, "the binding line has no bonding")
            local plainLine = items[BAG_PLAIN_ID].tooltip[2]
            Fault("the field on a plain line", function() plainLine.bonding = 6 end, function() plainLine.bonding = nil end,
                "a line of type 0 carries a bonding")
            Equal(Run().status, "pass", flavor .. ", contract: and passes again with the faults gone")
        end
        Equal(#client.errors, 0, flavor .. ": no error reached the error handler")
    end
end
