-- What a tooltip line says the toon does not meet (CaerdonItem.lua, IsUnmet / IsMet and
-- GetTooltipData).
--
-- A requirement line (type 43) says it as a field, `usable`; the slot line (21) as two,
-- `isValidInvSlot` for the slot on the left and `isValidItemType` for the armor or weapon
-- type on the right. Those are read first, whatever the line's colour. A line of those types
-- without its field, and every other line, has its colour alone: red is unmet.
--
-- The game is hand-made. In the clients' recordings (the fixtures of both flavors) every
-- line of the two types carries its fields, and a field is false exactly where its column is
-- red; a field that contradicts its colour, as some lines here have it, has not been seen
-- and is here to show which of the two is read.
--
-- Real code: the addon's item side, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 33 }

    local PLAIN, SLOT, ERROR, REQUIREMENT = 0, 21, 41, 43
    local RACE_CLASS, SKILL, LEVEL = 0, 2, 5 -- requirement types
    local function Red(line)
        line.r, line.g, line.b = 1, 0.125, 0.125
        return line
    end
    local function Level(more)
        local line = { text = "Requires Level 40", type = REQUIREMENT, requirementType = LEVEL }
        for key, value in pairs(more or {}) do line[key] = value end
        return line
    end
    local function Slot(more)
        local line = { text = "Wrist", type = SLOT, right = "Mail" }
        for key, value in pairs(more or {}) do line[key] = value end
        return line
    end
    local function Classes(more)
        local line = { text = "Classes: Mage", type = REQUIREMENT, requirementType = RACE_CLASS }
        for key, value in pairs(more or {}) do line[key] = value end
        return line
    end
    local function Skill(more)
        local line = { text = "Requires Engineering (125)", type = REQUIREMENT, requirementType = SKILL }
        for key, value in pairs(more or {}) do line[key] = value end
        return line
    end

    -- label, the line, then what the binding result says: unusable, and where it is asked,
    -- restricted by race or class, the skill requirement met.
    local CASES = {
        { "a level, unmet by its field, in white", Level({ usable = false }), true },
        { "a level, met by its field, in red", Red(Level({ usable = true })), false },
        { "a level without the field, in red", Red(Level({ bare = true })), true },
        { "a level without the field, in white", Level({ bare = true }), false },
        { "the slot line, the item type invalid by its field, in white", Slot({ isValidItemType = false }), true },
        { "the slot line, the slot invalid by its field, in white", Slot({ isValidInvSlot = false }), true },
        { "the slot line, both valid by their fields, the right column red",
            Slot({ rightRed = true, isValidItemType = true }), false },
        { "the slot line without the fields, the right column red", Slot({ bare = true, rightRed = true }), true },
        { "the slot line without the fields, the left column red", Red(Slot({ bare = true })), true },
        { "the slot line without the fields, in white", Slot({ bare = true }), false },
        { "an error line in red", Red({ text = "Locked", type = ERROR }), true },
        { "a plain line in red", Red({ text = "Requires Friendly with the Farmers", type = PLAIN }), true },
        { "a plain line in white", { text = "Requires Friendly with the Farmers", type = PLAIN }, false },
        { "classes, unmet by the field, in white", Classes({ usable = false }), true, true },
        { "classes, met by the field, in red", Red(Classes({ usable = true })), false, false },
        { "classes without the field, in red", Red(Classes({ bare = true })), true, true },
        { "classes without the field, in white", Classes({ bare = true }), false, false },
        { "a skill, met by its field, in red", Red(Skill({ usable = true })), false, nil, true },
        { "a skill, unmet by its field, in white", Skill({ usable = false }), true, nil, false },
        { "a skill without the field, in white", Skill({ bare = true }), false, nil, true },
        { "a skill without the field, in red", Red(Skill({ bare = true })), true, nil, false },
    }

    local FIRST_ID, WORN_ID, MAIN_HAND = 991001, 991900, 16
    local function Items()
        local items = {}
        for index, case in ipairs(CASES) do
            items[FIRST_ID + index - 1] = { name = "Charm " .. index, quality = 2, level = 33, minLevel = 0,
                type = "Armor", subType = "Miscellaneous", stack = 1, equipLoc = "INVTYPE_HOLDABLE", price = 5000,
                classID = 4, subClassID = 0, bindType = 1, tooltip = { case[2] },
                appearance = { appearanceID = 5700 + index, sourceID = 7700 + index, collected = true } }
        end
        -- Worn: a two-handed sword of a lower level with nothing in the off-hand.
        items[WORN_ID] = { name = "Worn Greatsword", quality = 2, level = 25, minLevel = 20, type = "Weapon",
            subType = "Two-Handed Swords", stack = 1, equipLoc = "INVTYPE_2HWEAPON", price = 900, classID = 2,
            subClassID = 8, bindType = 1, tooltip = { { text = "+9 Stamina" } },
            appearance = { appearanceID = 5398, sourceID = 7498, collected = true } }
        return items
    end

    -- Two more charms for the client that has a red of its own (below): a level line without
    -- its field in that red, and one in the red every other line here has.
    local OWN_RED_ID, USUAL_RED_ID = 991101, 991102
    local OWN_RED = { r = 1, g = 0.25, b = 0.25 }

    -- red: the client's RED_FONT_COLOR. Both clients make that global from their colour
    -- table when Blizzard's Color.lua loads (C_UIColor.GetColors), which the mocked client
    -- answers with nothing: so without one the addon is left with the value it falls back on.
    local function Start(flavor, red)
        local items = Items()
        items[OWN_RED_ID] = H.DeepCopy(items[FIRST_ID])
        items[OWN_RED_ID].name = "Charm in another red"
        items[OWN_RED_ID].tooltip = { Level({ bare = true, r = OWN_RED.r, g = OWN_RED.g, b = OWN_RED.b }) }
        items[USUAL_RED_ID] = H.DeepCopy(items[FIRST_ID])
        items[USUAL_RED_ID].name = "Charm in the usual red"
        items[USUAL_RED_ID].tooltip = { Red(Level({ bare = true })) }
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
        Equal(rawget(client.env, "RED_FONT_COLOR"), nil, flavor .. ": the mocked client has no red of its own")
        if red then
            rawset(client.env, "RED_FONT_COLOR", client.env.CreateColor(red.r, red.g, red.b, 1))
        end
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)
        Equal(#client.errors, 0, flavor .. ": no error reached the error handler at the start")
        return client, game
    end

    local function Judge(client, itemID)
        local item = client.env.CaerdonItem:CreateFromItemID(itemID)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        client:TickUntil(function() return loaded end, 10)
        local ready, bindingResult
        client:TickUntil(function()
            local _
            ready, _, _, bindingResult = item:GetCaerdonStatus()
            return ready
        end, 10)
        return bindingResult or {}
    end

    for _, flavor in ipairs({ "forever", "retail" }) do
        local client, game = Start(flavor)
        local env = client.env
        Equal(env.Enum.TooltipDataLineType.EquipSlot, SLOT, flavor .. ": the slot line's type is the one the cases use")
        Equal(env.Enum.TooltipDataLineType.UsageRequirement, REQUIREMENT, flavor .. ": and the requirement line's")
        Equal(env.Enum.TooltipDataLineType.ErrorLine, ERROR, flavor .. ": and the error line's")
        local types = env.Enum.TooltipDataUsageRequirementType
        Equal(types.RaceClass, RACE_CLASS, flavor .. ": the requirement type for race and class")
        Equal(types.Skill, SKILL, flavor .. ": for a skill")
        Equal(types.Level, LEVEL, flavor .. ": for a level")

        -- The mock hands the lines over as the cases say: a field only where one is meant.
        do
            local hyperlink = game.names["C_TooltipInfo.GetHyperlink"]
            local line = hyperlink(game.Link(FIRST_ID)).lines[2]
            Equal(line.usable, false, flavor .. ": the first case's line carries its field")
            line = hyperlink(game.Link(FIRST_ID + 2)).lines[2]
            Equal(line.usable, nil, flavor .. ": a bare line carries none")
            line = hyperlink(game.Link(FIRST_ID + 7)).lines[2]
            Check(line.isValidInvSlot == nil and line.isValidItemType == nil and line.rightText == "Mail"
                and line.rightColor:GenerateHexColor() == "ffff2020", flavor .. ": a bare slot line has its red right column")
        end

        for index, case in ipairs(CASES) do
            local result = Judge(client, FIRST_ID + index - 1)
            local label = flavor .. ", " .. case[1]
            Equal(result.unusableItem, case[3], label .. ": unusable")
            if case[4] ~= nil then
                Equal(result.raceClassRestricted, case[4], label .. ": restricted by race or class")
            end
            if case[5] ~= nil then
                Equal(result.hasSkillRequirement, true, label .. ": it asks for a skill")
                Equal(result.skillRequirementMet, case[5], label .. ": the skill requirement met")
            end
        end
        Equal(Judge(client, OWN_RED_ID).unusableItem, false, flavor .. ": another red is no red without a client's word")
        Equal(Judge(client, USUAL_RED_ID).unusableItem, true, flavor .. ": the usual red is")
        Equal(#client.errors, 0, flavor .. ": no error reached the error handler")
    end

    -- Red is what the client calls red: with a RED_FONT_COLOR of its own, a line in that
    -- colour is unmet and one in the usual red is not.
    do
        local client = Start("forever", OWN_RED)
        Equal(Judge(client, OWN_RED_ID).unusableItem, true, "own red: a line in the client's red is unmet")
        Equal(Judge(client, USUAL_RED_ID).unusableItem, false, "own red: a line in another red is not")
        Equal(Judge(client, FIRST_ID).unusableItem, true, "own red: a field is read as before")
        Equal(#client.errors, 0, "own red: no error reached the error handler")
    end

    --------------------------------------------------------------------------------------
    -- The test addon's contract tooltip.unmetLines: the same asked of a client's bags
    --------------------------------------------------------------------------------------

    for _, flavor in ipairs({ "forever", "retail" }) do
        -- A client that has its red, as both clients do.
        local client, game = Start(flavor, { r = 1, g = 0.125, b = 0.125 })
        local hyperlink = game.names["C_TooltipInfo.GetHyperlink"]
        -- The backpack, by the lines of each item: mail the toon cannot wear yet and a level
        -- it has not reached, a lockbox, and a charm it meets everything of.
        local MAIL_ID, BOX_ID, MET_ID, DYE_ID = 991201, 991202, 991203, 991204
        local mailSlot = Slot({ rightRed = true })
        local mailLevel = Red(Level())
        local boxLine = Red({ text = "Locked", type = ERROR })
        local metLines = { Slot(), Level() }
        -- An item that goes in no slot: its slot line holds the type alone, on the left, with
        -- the one field (a Housing Dye, retail 12.1.5.70961).
        local dyeLine = { text = "Housing Dye", type = SLOT, bare = true, isValidItemType = true }
        local lines = {
            [MAIL_ID] = { mailSlot, mailLevel },
            [BOX_ID] = { boxLine },
            [MET_ID] = metLines,
            [DYE_ID] = { dyeLine },
        }
        for itemID, tooltip in pairs(lines) do
            game.items[itemID] = H.DeepCopy(game.items[FIRST_ID])
            game.items[itemID].name = "Bag item " .. itemID
            game.items[itemID].tooltip = tooltip
        end
        local bag = { MAIL_ID, BOX_ID, MET_ID, DYE_ID }
        game:Set("C_Container.GetContainerNumSlots", function(index) return index == 0 and #bag or 0 end)
        game:Set("C_Container.GetContainerItemID", function(index, slot) return index == 0 and bag[slot] or nil end)
        game:Set("C_Container.GetContainerItemLink", function(index, slot)
            return index == 0 and bag[slot] and game.Link(bag[slot]) or nil
        end)
        game:Set("C_TooltipInfo.GetBagItem", function(index, slot)
            return index == 0 and bag[slot] and hyperlink(game.Link(bag[slot])) or nil
        end)

        local wanted = { ["Core.lua"] = true, ["Runner.lua"] = true, ["Contracts.lua"] = true, ["Plan.lua"] = true }
        local T = H.LoadAddon(client, "CaerdonWardrobe_Tests", H.addonDir .. "/CaerdonWardrobe_Tests",
            function(relative) return not wanted[relative] end)
        client:Fire("ADDON_LOADED", "CaerdonWardrobe_Tests")
        client:Fire("PLAYER_LOGIN")
        local ID = "tooltip.unmetLines"
        local function Run()
            T.RunTests({ match = ID, force = true })
            Check(client:TickUntil(function() return not T.IsBusy() end, 120), flavor .. ", contract: the job ends")
            return (T.db.contracts[T.GetClient().build] or {})[ID] or {}
        end

        local result = Run()
        Equal(result.status, "pass", flavor .. ", contract: it passes on the bags (" .. tostring(result.message) .. ")")
        local detail = result.detail or {}
        Equal(detail.red, "ffff2020", flavor .. ", contract: the client's red is kept")
        Equal(detail.items, 4, flavor .. ", contract: four items")
        Equal(detail.requirementLines, 4, flavor .. ", contract: two requirement lines, in the slot's and the link's tooltip")
        Equal(detail.slotLines, 6, flavor .. ", contract: and three slot lines")
        local typeOnly = (detail.typeOnly or {})[tostring(SLOT)] or {}
        Equal(typeOnly.lines, 2, flavor .. ", contract: one of them holds a type alone, on both sides")
        Equal((typeOnly.examples or {})[1], "Housing Dye", flavor .. ", contract: kept with its text")
        Equal(detail.unmetByField, 4, flavor .. ", contract: the mail's type and its level, on both sides")
        -- Which field said so, on what text: a client's first unmet line is named, not counted.
        local unmet = detail.unmet or {}
        Equal((unmet.usable or {}).lines, 2, flavor .. ", contract: the level is unmet by usable, twice")
        Equal(((unmet.usable or {}).examples or {})[1], "slot: \"Requires Level 40\"", flavor .. ", contract: in the slot's tooltip")
        Equal(((unmet.usable or {}).examples or {})[2], "link: \"Requires Level 40\"", flavor .. ", contract: and in the link's")
        Equal((unmet.isValidItemType or {}).lines, 2, flavor .. ", contract: the mail by isValidItemType, twice")
        Equal(((unmet.isValidItemType or {}).examples or {})[1], "slot: \"Mail\"", flavor .. ", contract: with the right column's text")
        Equal(unmet.isValidInvSlot, nil, flavor .. ", contract: a field nothing was unmet by is not listed")
        local elsewhere = (detail.redElsewhere or {})[tostring(ERROR)] or {}
        Equal(elsewhere.lines, 2, flavor .. ", contract: the lockbox's red line is of a type with no field")
        Equal((elsewhere.examples or {})[1], "Locked", flavor .. ", contract: with its text, once")
        Equal((elsewhere.examples or {})[2], nil, flavor .. ", contract: and not twice")
        Equal(next(detail.fieldsElsewhere or {}), nil, flavor .. ", contract: no field on another line type")

        result = Run()
        Equal((result.detail or {}).requirementLines, 8, flavor .. ", contract: a second run adds to the first")
        Equal((((result.detail or {}).redElsewhere or {})[tostring(ERROR)] or {}).lines, 4,
            flavor .. ", contract: also to the red lines elsewhere")
        Equal((((result.detail or {}).unmet or {}).usable or {}).lines, 4, flavor .. ", contract: and to the unmet lines by field")
        Equal(#((((result.detail or {}).unmet or {}).usable or {}).examples or {}), 2,
            flavor .. ", contract: whose examples are kept once each")

        -- Bags whose lines are all met answer for those only.
        bag = { MET_ID, BOX_ID, DYE_ID }
        Equal(Run().status, "info", flavor .. ", contract: nothing unmet is no pass")
        bag = { MAIL_ID, BOX_ID, MET_ID, DYE_ID }

        -- Faults, one at a time.
        local function Fault(label, plant, undo, expected)
            plant()
            local faulty = Run()
            Equal(faulty.status, "fail", flavor .. ", fault, " .. label .. ": the contract fails")
            Check(tostring(faulty.message):find(expected, 1, true) ~= nil,
                flavor .. ", fault, " .. label .. ": and says why (" .. tostring(faulty.message) .. ")")
            undo()
        end
        Fault("a red requirement the field calls met", function() mailLevel.usable = true end,
            function() mailLevel.usable = nil end, "usable is true and the left column is red")
        Fault("a white requirement the field calls unmet", function() metLines[2].usable = false end,
            function() metLines[2].usable = nil end, "usable is false and the left column is not red")
        Fault("a red item type the field calls valid", function() mailSlot.isValidItemType = true end,
            function() mailSlot.isValidItemType = nil end, "isValidItemType is true and the right column is red")
        Fault("a white slot the field calls invalid", function() metLines[1].isValidInvSlot = false end,
            function() metLines[1].isValidInvSlot = nil end, "isValidInvSlot is false and the left column is not red")
        Fault("a type alone in red that the field calls valid", function() Red(dyeLine) end,
            function() dyeLine.r, dyeLine.g, dyeLine.b = nil, nil, nil end, "isValidItemType is true and the left column is red")
        Fault("a type alone in white that the field calls invalid", function() dyeLine.isValidItemType = false end,
            function() dyeLine.isValidItemType = true end, "isValidItemType is false and the left column is not red")
        Fault("a slot line with a right column and no slot field", function() metLines[1].bare, metLines[1].isValidItemType = true, true end,
            function() metLines[1].bare, metLines[1].isValidItemType = nil, nil end, "isValidInvSlot on a line of type 21 is a nil")
        Fault("a slot line with neither field", function() dyeLine.isValidItemType = nil end,
            function() dyeLine.isValidItemType = true end, "isValidInvSlot on a line of type 21 is a nil")
        Fault("a requirement line without its field", function() mailLevel.bare = true end,
            function() mailLevel.bare = nil end, "usable on a line of type 43 is a nil")
        local usual = client.env.RED_FONT_COLOR
        Fault("a client whose red is another", function() rawset(client.env, "RED_FONT_COLOR", client.env.CreateColor(1, 0, 0, 1)) end,
            function() rawset(client.env, "RED_FONT_COLOR", usual) end, "RED_FONT_COLOR is ffff0000, not ffff2020")
        Fault("a client with no red", function() rawset(client.env, "RED_FONT_COLOR", nil) end,
            function() rawset(client.env, "RED_FONT_COLOR", usual) end, "RED_FONT_COLOR is a nil")

        -- A field on a line of another type is kept, and fails nothing.
        boxLine.usable = false
        result = Run()
        Equal(result.status, "pass", flavor .. ", contract: a field on another line type is no failure")
        Equal((((result.detail or {}).fieldsElsewhere or {})[tostring(ERROR)] or {}).lines, 2,
            flavor .. ", contract: it is listed by its line type")
        boxLine.usable = nil
        Equal(#client.errors, 0, flavor .. ", contract: no error reached the error handler")
    end
end
