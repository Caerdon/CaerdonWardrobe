-- An "Equip:" line that is a plain stat does not keep a learned piece (CaerdonItem.lua,
-- IsEquipStatLine).
--
-- WoW Forever writes spell power, attack power and the like as green "Equip:" lines of type
-- None, built from its TOOLTIP_ITEM_STAT_* strings; an effect that is a spell comes as
-- ItemSpellTriggerOnEquip. Any "Equip:" line used to keep a learned piece from "sellable".
--
-- The stat lines below marked "recorded" are the text a Forever client gave (the fixtures of
-- build 1.60.1, and two Copy Details exports); the strings they are matched against are the
-- listings mirror's. The items around them are hand-made. Whether the client writes a
-- percentage as its format says ("1.0%") has not been seen.
--
-- Real code: the addon's item side, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 33 }

    local NONE, ON_EQUIP = 0, 45
    -- label, the line (or lines), its type, whether it is more than a stat on Forever.
    local CASES = {
        { "healing and damage (recorded)",
            "Equip: Increases healing done by up to 13 and damage done by up to 4 for all magical spells and effects.",
            NONE, false },
        { "spell power (recorded)",
            "Equip: Increases damage and healing done by magical spells and effects by up to 2.", NONE, false },
        { "attack power (recorded)", "Equip: +12 Attack Power.", NONE, false },
        { "shadow damage (recorded)", "Equip: Increases damage done by Shadow spells and effects by up to 10.", NONE,
            false },
        { "fire damage (recorded)", "Equip: Increases damage done by Fire spells and effects by up to 1.", NONE, false },
        { "a percentage", "Equip: Improves your chance to get a critical strike by 1.0%.", NONE, false },
        { "mana per 5 sec", "Equip: Restores 4 Mana per 5 sec.", NONE, false },
        { "against a creature", "Equip: +30 Attack Power against Beasts.", NONE, false },
        { "a spell's effect (recorded)", "Equip: Increases ranged attack speed by 10%.", ON_EQUIP, true },
        { "a stat's text on a spell's line", "Equip: +12 Attack Power.", ON_EQUIP, true },
        { "a skill bonus (recorded)", "Equip: Increased Fishing +3.", NONE, true },
        { "an untyped line that is no stat string", "Equip: Increases swim speed by 15%.", NONE, true },
        { "a stat line with more text behind it", "Equip: +12 Attack Power. And then some.", NONE, true },
        { "a stat and an effect",
            { { "Equip: +12 Attack Power.", NONE }, { "Equip: Increases ranged attack speed by 10%.", ON_EQUIP } }, nil,
            true },
        { "two stats", { { "Equip: +12 Attack Power.", NONE }, { "Equip: Restores 4 Mana per 5 sec.", NONE } }, nil,
            false },
    }

    local FIRST_ID, NO_PRICE_ID, WORN_ID, MAIN_HAND = 970001, 970800, 970900, 16
    local MIDDLE_ID, USE_LINE_ID, FLOOR_ID, ON_USE = 970801, 970802, 970803, 44
    local function Items()
        local items = {}
        for index, case in ipairs(CASES) do
            local tooltip = { { text = "Binds when equipped", type = 20, bonding = 7 } }
            local lines = type(case[2]) == "table" and case[2] or { { case[2], case[3] } }
            for _, line in ipairs(lines) do
                tooltip[#tooltip + 1] = { text = line[1], type = line[2], r = 0, g = 1, b = 0 }
            end
            items[FIRST_ID + index - 1] = { name = "Charm " .. index, quality = 2, level = 31, minLevel = 26,
                type = "Armor", subType = "Miscellaneous", stack = 1, equipLoc = "INVTYPE_HOLDABLE", price = 537,
                classID = 4, subClassID = 0, bindType = 2, tooltip = tooltip,
                appearance = { appearanceID = 5300 + index, sourceID = 7400 + index, collected = true } }
        end
        -- No "Equip:" line at all.
        items[FIRST_ID + #CASES] = { name = "Plain Charm", quality = 2, level = 31, minLevel = 26, type = "Armor",
            subType = "Miscellaneous", stack = 1, equipLoc = "INVTYPE_HOLDABLE", price = 537, classID = 4,
            subClassID = 0, bindType = 2, tooltip = { { text = "+3 Stamina" } },
            appearance = { appearanceID = 5399, sourceID = 7499, collected = true } }
        -- A stat line on a piece no vendor pays for (a quest's piece, traded in later).
        items[NO_PRICE_ID] = { name = "Cursed Charm", quality = 2, level = 31, minLevel = 26, type = "Armor",
            subType = "Miscellaneous", stack = 1, equipLoc = "INVTYPE_HOLDABLE", price = 0, classID = 4,
            subClassID = 0, bindType = 1,
            tooltip = { { text = "Equip: Increases damage done by Shadow spells and effects by up to 10.", type = NONE,
                r = 0, g = 1, b = 0 } },
            appearance = { appearanceID = 5397, sourceID = 7497, collected = true } }
        -- The word for an equip line where it does not start an untyped line: in the middle of
        -- one, and on a line the client types as a use. Neither is an equip line. And retail's
        -- PVP floor (recorded: the text of a retail fixture), an untyped line that is one.
        items[MIDDLE_ID] = { name = "Wordy Charm", quality = 2, level = 31, minLevel = 26, type = "Armor",
            subType = "Miscellaneous", stack = 1, equipLoc = "INVTYPE_HOLDABLE", price = 537, classID = 4,
            subClassID = 0, bindType = 2, tooltip = { { text = "Set: As if by Equip: nothing at all.", type = NONE } },
            appearance = { appearanceID = 5396, sourceID = 7496, collected = true } }
        items[USE_LINE_ID] = { name = "Used Charm", quality = 2, level = 31, minLevel = 26, type = "Armor",
            subType = "Miscellaneous", stack = 1, equipLoc = "INVTYPE_HOLDABLE", price = 537, classID = 4,
            subClassID = 0, bindType = 2, tooltip = { { text = "Equip: this line is typed as a use.", type = ON_USE } },
            appearance = { appearanceID = 5395, sourceID = 7495, collected = true } }
        items[FLOOR_ID] = { name = "Arena Charm", quality = 2, level = 31, minLevel = 26, type = "Armor",
            subType = "Miscellaneous", stack = 1, equipLoc = "INVTYPE_HOLDABLE", price = 537, classID = 4,
            subClassID = 0, bindType = 2,
            tooltip = { { text = "Equip: Increases item level to a minimum of 285 in Arenas, Battlegrounds, and War Mode.",
                type = NONE } },
            appearance = { appearanceID = 5394, sourceID = 7494, collected = true } }
        -- What the toon wields, as the hunter of the exports did: a two-handed sword of a lower
        -- level and nothing in the off-hand. A charm is then no upgrade (the slot is taken),
        -- no tie and not outdone by a better piece, so only its own lines decide.
        items[WORN_ID] = { name = "Worn Greatsword", quality = 2, level = 25, minLevel = 20, type = "Weapon",
            subType = "Two-Handed Swords", stack = 1, equipLoc = "INVTYPE_2HWEAPON", price = 900, classID = 2,
            subClassID = 8, bindType = 1, tooltip = { { text = "+9 Stamina" } },
            appearance = { appearanceID = 5398, sourceID = 7498, collected = true } }
        return items
    end

    local function Start(flavor)
        local items = Items()
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
        return client
    end

    local function Judge(client, itemID)
        local item = client.env.CaerdonItem:CreateFromItemID(itemID)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        client:TickUntil(function() return loaded end, 10)
        local ready, status, bindingResult
        client:TickUntil(function()
            local _
            ready, status, _, bindingResult = item:GetCaerdonStatus()
            return ready
        end, 10)
        return status, bindingResult or {}
    end

    -- Forever: a stat line no longer keeps the piece; everything else does as before.
    local forever = Start("forever")
    Equal(forever.env.Enum.TooltipDataLineType.ItemSpellTriggerOnEquip, ON_EQUIP,
        "forever: the type of a spell's equip line is the one the cases use")
    for index, case in ipairs(CASES) do
        local status, result = Judge(forever, FIRST_ID + index - 1)
        local label = "forever, " .. case[1]
        Equal(result.hasEquipEffect, true, label .. ": it has an equip line")
        Equal(result.hasEquipEffectBeyondStats, case[4], label .. ": more than a stat")
        Equal(status, case[4] and "collected" or "sellable", label .. ": its status")
    end
    do
        local status, result = Judge(forever, FIRST_ID + #CASES)
        Equal(result.hasEquipEffect, false, "forever, no equip line: none found")
        Equal(result.hasEquipEffectBeyondStats, false, "forever, no equip line: and nothing beyond a stat")
        Equal(status, "sellable", "forever, no equip line: sellable, as before")
    end
    do
        local status, result = Judge(forever, NO_PRICE_ID)
        Equal(result.hasEquipEffectBeyondStats, false, "forever, no vendor price: its line is a stat")
        Equal(status, "collected", "forever, no vendor price: kept all the same, as before")
    end

    -- The list the code builds its names from, against the client's strings: every name is
    -- one the Forever client has, and every "Equip:" stat string it has is named, except the
    -- skill bonuses. A build that adds a family fails here.
    do
        local strings = forever.listing.strings
        local named, missing, unnamed = {}, {}, {}
        for _, name in ipairs(forever.env.CaerdonItem:GetEquipStatStringNames()) do
            named[name] = true
            if type(strings[name]) ~= "string" then
                missing[#missing + 1] = name
            end
        end
        local trigger = strings.ITEM_SPELL_TRIGGER_ONEQUIP
        for name, text in pairs(strings) do
            if type(name) == "string" and name:find("^TOOLTIP_ITEM_STAT_") and not name:find("_SKILL_", 1, true)
                and type(text) == "string" and text:sub(1, #trigger) == trigger and not named[name] then
                unnamed[#unnamed + 1] = name
            end
        end
        table.sort(missing)
        table.sort(unnamed)
        Check(next(named) ~= nil, "names: the list is not empty")
        Equal(table.concat(missing, ", "), "", "names: each one is a string of the Forever client")
        Equal(table.concat(unnamed, ", "), "", "names: every equip stat string of the Forever client is named")
    end
    Equal(#forever.errors, 0, "forever: no error reached the error handler")

    -- Retail has none of the strings, so every "Equip:" line is an effect there, as it was.
    local retail = Start("retail")
    local retailStrings = 0
    for _, name in ipairs(retail.env.CaerdonItem:GetEquipStatStringNames()) do
        if retail.listing.strings[name] ~= nil then
            retailStrings = retailStrings + 1
        end
    end
    Equal(retailStrings, 0, "retail: the client has none of the stat strings")
    for index, case in ipairs(CASES) do
        local status, result = Judge(retail, FIRST_ID + index - 1)
        local label = "retail, " .. case[1]
        Equal(result.hasEquipEffectBeyondStats, true, label .. ": an effect")
        Equal(status, "collected", label .. ": kept")
    end

    -- Which line is an equip line at all, the same in both clients.
    for _, pair in ipairs({ { "forever", forever }, { "retail", retail } }) do
        local flavor, client = pair[1], pair[2]
        Equal(client.env.Enum.TooltipDataLineType.ItemSpellTriggerOnUse, ON_USE,
            flavor .. ": the type of a use line is the one the cases use")
        Equal(client.listing.strings.ITEM_SPELL_TRIGGER_ONEQUIP, "Equip:", flavor .. ": the client's word for an equip line")
        local _, result = Judge(client, MIDDLE_ID)
        Equal(result.hasEquipEffect, false, flavor .. ", the word in the middle of a line: no equip line")
        Equal(result.hasEquipEffectBeyondStats, false, flavor .. ", the word in the middle of a line: and no effect")
        _, result = Judge(client, USE_LINE_ID)
        Equal(result.hasEquipEffect, false, flavor .. ", the word on a line typed as a use: no equip line")
        _, result = Judge(client, FLOOR_ID)
        Equal(result.hasEquipEffect, true, flavor .. ", the PVP floor: an untyped equip line")
        Equal(result.hasEquipEffectBeyondStats, true, flavor .. ", the PVP floor: and more than a stat, as before")
    end
    Equal(#retail.errors, 0, "retail: no error reached the error handler")

    for _, client in ipairs({ forever, retail }) do
        for _, message in ipairs(client.errors) do
            print("        error: " .. tostring(message))
        end
    end
end
