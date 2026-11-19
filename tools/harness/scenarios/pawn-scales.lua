-- Which of Pawn's scales count as the toon's own on a client with specializations.
--
-- Pawn's arrow answers "an upgrade for any visible scale". A player who makes another spec's
-- scale visible beside the played one gets that spec's upgrades too, and the equipment code
-- tells the two apart (types/EquipmentMixin.lua, GetPawnOffTreeScales): an upgrade that only
-- another spec's scale sees is flagged (pawnOffTreeUpgrade), as it is per talent tree on a
-- client without specializations. Here:
--   1. An upgrade for the played spec's scale is Pawn's upgrade; one for another spec's alone
--      is flagged; one for both is Pawn's upgrade.
--   2. A custom scale and another class's scale are never ignored.
--   3. With the played spec's scale or a custom one shown alone, or no spec chosen, nothing is
--      ignored. Another spec's scale shown alone is still the other spec's (9).
--   4. A change of spec refreshes the icons, once, and so does a change of the loot spec; an
--      event with both as they were refreshes nothing.
--   5. A higher item level where Pawn calls the piece no upgrade: it counts where Pawn has no
--      verdict, not where Pawn's scores prefer the worn piece, whatever Pawn's own item level
--      switch says; the addon's two settings switch it off and let it stand against the scores.
--   6. A piece for another loot spec keeps Pawn's verdict and is marked as such.
--   7. An upgrade for another spec with Pawn showing the played spec's scale alone: scored on
--      the other spec's scale against the gear set assigned to that spec, or the worn gear.
--   8. Which specs that is for: a spec the player switched on or off on the Icons page is as
--      chosen. One nobody chose is wanted where a gear set is assigned to it, or where Pawn
--      shows its scale by the player's choice (not in Pawn's automatic mode).
--   9. The spec being played is judged on its own scale whatever Pawn shows. Where Pawn shows
--      no scale of the toon's own (the played spec's is hidden and no custom one is shown), the
--      addon scores the piece on the hidden scale against the worn gear: an upgrade is the
--      toon's own, a worn piece rated as high takes the item level's arrow, and a shown scale
--      of another spec is the other spec's.
--  10. Another spec with a gear set is measured against that set where Pawn shows its scale too:
--      Pawn's verdict for that scale, which is against the worn gear, does not count.
--  11. The gear set of the spec being played is measured on its own wherever its piece is not
--      the one worn, whatever is worn in its place.
--  12. What Pawn's own check refuses before it compares values is refused for a loadout too:
--      armor that is not the class's type, a one-hander against a two-hander and the reverse.
--  13. A unique-equipped piece that is an upgrade by its own rule is not drawn as another
--      spec's where Pawn's verdict for that spec does not stand.
--  14. The item tooltip names each loadout a piece is an upgrade for and by how much (with
--      the cases of 10 to 12): a line built like Pawn's own, with the gear set's icon and
--      name and the arrow of the piece's button, and with a setting that hides it. It is
--      added from Pawn's own tooltip step, after Pawn's lines, and Pawn's upgrade note gives
--      way there for every scale the addon has a line for and for a scale whose gear set
--      decides; by itself it is left out where Pawn's line says the same.
--  15. What is worn has a line of the addon's too, in the yellow of its arrow and named for the
--      gear set being worn, where the piece has that arrow. The set being worn is the one the
--      player last put on, checked against what the client says is on; a set with no spec, or
--      another spec's, gets no line of the addon's.
--  16. A comparison tooltip says what the piece looked at would do in the place of the worn
--      piece it shows, for each loadout that has that worn piece: which of two rings it is for.
--      Under the client's own stat changes, as the last of them.
--
-- Pawn here is the scenario's own: its tables and functions as the addon reads them. That a
-- scale's SpecID is the spec's index was read in Pawn's code (PawnGetDefaultScale) and is not
-- proven by this.
--
-- Real code: the whole addon, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Druid", classFile = "DRUID", race = "Tauren",
        faction = "Horde", level = 90 }
    local CLASS_ID = 3 -- what the stock game answers for the toon's class

    local function Items()
        return {
            [940001] = { name = "Scale Tester's Jerkin", quality = 3, level = 200, minLevel = 80, type = "Armor",
                subType = "Leather", stack = 1, equipLoc = "INVTYPE_CHEST", price = 900, classID = 4, subClassID = 2,
                bindType = 1, tooltip = { { text = "Binds when picked up", type = 20, bonding = 1 } },
                appearance = { appearanceID = 6401, sourceID = 8401, collected = true } },
            -- In the bags, for the other spec's gear set.
            [940003] = { name = "Prowler's Jerkin", quality = 3, level = 190, minLevel = 80, type = "Armor",
                subType = "Leather", stack = 1, equipLoc = "INVTYPE_CHEST", price = 800, classID = 4, subClassID = 2,
                bindType = 1, tooltip = { { text = "Binds when picked up", type = 20, bonding = 1 } },
                appearance = { appearanceID = 6403, sourceID = 8403, collected = true } },
            -- Worn, ten levels below it.
            [940002] = { name = "Worn Jerkin", quality = 3, level = 190, minLevel = 80, type = "Armor",
                subType = "Leather", stack = 1, equipLoc = "INVTYPE_CHEST", price = 800, classID = 4, subClassID = 2,
                bindType = 1, tooltip = { { text = "Binds when picked up", type = 20, bonding = 1 } },
                appearance = { appearanceID = 6402, sourceID = 8402, collected = true } },
            -- Four rings of one level, for a slot that comes twice (11).
            [940011] = { name = "Band of Both Sets", quality = 3, level = 190, minLevel = 80, type = "Armor",
                subType = "Miscellaneous", stack = 1, equipLoc = "INVTYPE_FINGER", price = 800, classID = 4, subClassID = 0,
                bindType = 1, tooltip = { { text = "Binds when picked up", type = 20, bonding = 1 } } },
            [940012] = { name = "Band Put Aside", quality = 3, level = 190, minLevel = 80, type = "Armor",
                subType = "Miscellaneous", stack = 1, equipLoc = "INVTYPE_FINGER", price = 800, classID = 4, subClassID = 0,
                bindType = 1, tooltip = { { text = "Binds when picked up", type = 20, bonding = 1 } } },
            [940013] = { name = "Band of the Other Set", quality = 3, level = 190, minLevel = 80, type = "Armor",
                subType = "Miscellaneous", stack = 1, equipLoc = "INVTYPE_FINGER", price = 800, classID = 4, subClassID = 0,
                bindType = 1, tooltip = { { text = "Binds when picked up", type = 20, bonding = 1 } } },
            [940014] = { name = "Scale Tester's Band", quality = 3, level = 190, minLevel = 80, type = "Armor",
                subType = "Miscellaneous", stack = 1, equipLoc = "INVTYPE_FINGER", price = 800, classID = 4, subClassID = 0,
                bindType = 1, tooltip = { { text = "Binds when picked up", type = 20, bonding = 1 } } },
            -- Ten levels above the others, for the unique-equipped rule (13).
            [940015] = { name = "Band of the One Family", quality = 3, level = 200, minLevel = 80, type = "Armor",
                subType = "Miscellaneous", stack = 1, equipLoc = "INVTYPE_FINGER", price = 800, classID = 4, subClassID = 0,
                bindType = 1, tooltip = { { text = "Binds when picked up", type = 20, bonding = 1 } } },
            -- Weapons of one level: two-handers and one-handers (12).
            [940021] = { name = "Scale Tester's Staff", quality = 3, level = 190, minLevel = 80, type = "Weapon",
                subType = "Staves", stack = 1, equipLoc = "INVTYPE_2HWEAPON", price = 800, classID = 2, subClassID = 10,
                bindType = 1, tooltip = { { text = "Binds when picked up", type = 20, bonding = 1 } } },
            [940022] = { name = "Set's Mace", quality = 3, level = 190, minLevel = 80, type = "Weapon",
                subType = "One-Handed Maces", stack = 1, equipLoc = "INVTYPE_WEAPON", price = 800, classID = 2, subClassID = 4,
                bindType = 1, tooltip = { { text = "Binds when picked up", type = 20, bonding = 1 } } },
            [940023] = { name = "Worn Staff", quality = 3, level = 190, minLevel = 80, type = "Weapon",
                subType = "Staves", stack = 1, equipLoc = "INVTYPE_2HWEAPON", price = 800, classID = 2, subClassID = 10,
                bindType = 1, tooltip = { { text = "Binds when picked up", type = 20, bonding = 1 } } },
            [940024] = { name = "Scale Tester's Mace", quality = 3, level = 190, minLevel = 80, type = "Weapon",
                subType = "One-Handed Maces", stack = 1, equipLoc = "INVTYPE_WEAPON", price = 800, classID = 2, subClassID = 4,
                bindType = 1, tooltip = { { text = "Binds when picked up", type = 20, bonding = 1 } } },
            [940025] = { name = "Set's Staff", quality = 3, level = 190, minLevel = 80, type = "Weapon",
                subType = "Staves", stack = 1, equipLoc = "INVTYPE_2HWEAPON", price = 800, classID = 2, subClassID = 10,
                bindType = 1, tooltip = { { text = "Binds when picked up", type = 20, bonding = 1 } } },
        }
    end

    -- A tooltip as the client has them, as far as the addon's comparison lines ask: its lines,
    -- whether it is shown, its owner, the scripts hooked on it. Update is a frame of the
    -- client going by for it: its OnUpdate runs. shows counts the times it was shown anew.
    local function Tip()
        local tip = { lines = {}, shows = 0, scripts = {}, shown = false }
        function tip:AddLine(line) self.lines[#self.lines + 1] = line end
        function tip:NumLines() return #self.lines end
        function tip:Show()
            self.shows = self.shows + 1
            self.shown = true
        end
        function tip:IsShown() return self.shown end
        function tip:GetOwner() return self.owner end
        function tip:IsTooltipType() return true end
        -- tip.info: how the client filled it ({ getterName, getterArgs }), where a check sets one.
        function tip:GetPrimaryTooltipInfo() return self.info end
        function tip:HookScript(script, handler)
            self.scripts[script] = self.scripts[script] or {}
            table.insert(self.scripts[script], handler)
        end
        function tip:Update()
            for _, handler in ipairs(self.scripts.OnUpdate or {}) do
                handler(self, 0.016)
            end
        end
        return tip
    end

    -- options.noPawnTooltipStep: a Pawn without the function its tooltip lines are added in.
    local function Start(options)
        local game = H.StockGame(TOON, Items())
        -- A retail client, with specializations: the stock game says it is WoW Forever.
        game:Set("GetBuildInfo", function() return "12.1.5", "70961", "Nov 1 2026", 120105 end)
        game:Set("WOW_PROJECT_ID", 1)
        local world = { game = game, spec = 3, lootSpec = 0, visible = {}, upgradeFor = {}, refreshes = {} }
        -- What is worn, by inventory slot (the chest slot holds the worn jerkin), and what lies
        -- in bag 0, by slot (the other spec's jerkin).
        world.worn = { [5] = 940002 }
        world.inBag = { [1] = 940003 }
        world.scales = {
            ["\"MrRobot\":DRUID2"] = { ClassID = CLASS_ID, SpecID = 2, Provider = "MrRobot", LocalizedName = "Druid: Feral" },
            ["\"MrRobot\":DRUID3"] = { ClassID = CLASS_ID, SpecID = 3, Provider = "MrRobot", LocalizedName = "Druid: Guardian" },
            ["\"MrRobot\":MAGE1"] = { ClassID = 8, SpecID = 1, Provider = "MrRobot", LocalizedName = "Mage: Arcane" },
            -- Another class's scale with the number of the spec the toon plays, never shown, and
            -- first by name: it must not be taken for the toon's own hidden scale.
            ["\"Classic\":MAGE3"] = { ClassID = 8, SpecID = 3, Provider = "Classic", LocalizedName = "Mage: Frost" },
            ["My own"] = { LocalizedName = "My own" },
        }
        game:Set("GetSpecialization", function() return world.spec end)
        game:Set("GetLootSpecialization", function() return world.lootSpec end)
        game:Set("PawnCommon.Scales", world.scales)
        game:Set("PawnCommon.ShowItemLevelUpgrades", false)
        game:Set("PawnIsScaleVisible", function(name) return world.visible[name] == true end)
        -- Pawn's item data: its stats table is there once Pawn has read the item (world.unread:
        -- item ID -> true for one it has not).
        game:Set("PawnGetItemData", function(link)
            -- world.onItemData: what happens while Pawn reads an item (it fills a tooltip of its own).
            if world.onItemData then
                world.onItemData()
            end
            local id = tonumber(link:match("item:(%d+)"))
            return { Link = link, UnenchantedStats = not (world.unread and world.unread[id]) and {} or nil }
        end)
        -- Pawn's armor rule (world.wrongArmor: item ID -> true for armor that is not the class's).
        game:Set("PawnIsArmorBestTypeForPlayer", function(itemData)
            if not itemData.UnenchantedStats then
                return false
            end
            local id = tonumber(itemData.Link:match("item:(%d+)"))
            return not (world.wrongArmor and world.wrongArmor[id])
        end)
        -- Unique-equipped families (world.unique: item ID -> the family's ID, one piece at a time).
        game:Set("C_Item.GetItemUniquenessByID", function(reference)
            local id = type(reference) == "number" and reference or tonumber(tostring(reference):match("item:(%d+)"))
            local family = world.unique and world.unique[id]
            if family then
                return true, "Family " .. family, 1, family
            end
            return false
        end)
        -- Pawn's values, where it has any (world.values: item ID -> value on every scale).
        game:Set("PawnGetSingleValueFromItem", function(itemData, scaleName)
            local id = tonumber(itemData.Link:match("item:(%d+)"))
            -- Counted for a scale that is not shown: those are the ones Pawn calculates anew.
            if not world.visible[scaleName] then
                world.valueCalls = (world.valueCalls or 0) + 1
            end
            -- world.scaleValues: a scale's own values, for one that is not shown.
            local own = world.scaleValues and world.scaleValues[scaleName]
            if own then
                return nil, own[id]
            end
            return nil, world.values and world.values[id] or nil
        end)
        -- Gear sets by spec, and where their pieces are.
        game:Set("C_EquipmentSet.GetEquipmentSetForSpec", function(specIndex)
            return world.setForSpec and world.setForSpec[specIndex] or nil
        end)
        game:Set("C_EquipmentSet.GetItemLocations", function(setID)
            return world.setLocations and world.setLocations[setID] or nil
        end)
        game:Set("EquipmentManager_GetLocationData", function(location)
            return world.locationData and world.locationData[location] or {}
        end)
        -- Every gear set the toon has saved, and their names.
        game:Set("C_EquipmentSet.GetEquipmentSetIDs", function() return world.setIDs or {} end)
        game:Set("C_EquipmentSet.GetEquipmentSetInfo", function(setID)
            -- world.setWorn: set ID -> { pieces, pieces worn }.
            local worn = world.setWorn and world.setWorn[setID]
            return world.setNames and world.setNames[setID] or ("Set " .. tostring(setID)),
                world.setIcons and world.setIcons[setID] or nil, setID, worn ~= nil and worn[1] == worn[2],
                worn and worn[1] or nil, worn and worn[2] or nil
        end)
        game:Set("PawnGetItemDataForInventorySlot", function(slot)
            if world.worn[slot] then
                return { Link = game.Link(world.worn[slot]) }, true
            end
            return nil, false
        end)
        local hyperlink = game.names["C_TooltipInfo.GetHyperlink"]
        game:Set("C_TooltipInfo.GetInventoryItem", function(_, slot)
            return world.worn[slot] and hyperlink(game.Link(world.worn[slot])) or nil
        end)
        local function Worn(location)
            if type(location) ~= "table" then
                return nil
            elseif location.IsEquipmentSlot and location:IsEquipmentSlot() then
                return world.worn[location:GetEquipmentSlot()]
            elseif location.IsBagAndSlot and location:IsBagAndSlot() then
                local bag, slot = location:GetBagAndSlot()
                return bag == 0 and world.inBag[slot] or nil
            end
        end
        game:Set("GetInventoryItemLink", function(_, slot)
            return world.worn[slot] and game.Link(world.worn[slot]) or nil
        end)
        game:Set("C_Item.DoesItemExist", function(location) return Worn(location) ~= nil end)
        game:Set("C_Item.GetItemLink", function(location) return Worn(location) and game.Link(Worn(location)) end)
        game:Set("C_Item.GetItemID", function(location) return Worn(location) end)
        game:Set("C_Item.GetCurrentItemLevel", function(location) return Worn(location) and 190 or nil end)
        game:Set("C_Item.IsBound", function() return false end)
        -- The loot spec an item is for (world.itemSpecs), and the spec IDs of this class.
        game:Set("C_Item.GetItemSpecInfo", function() return world.itemSpecs end)
        game:Set("GetSpecializationInfo", function(index) return 100 + index end)
        local specNames = { "Balance", "Feral", "Guardian", "Restoration" }
        game:Set("GetSpecializationInfoForClassID", function(_, index)
            return 100 + index, specNames[index], nil, world.specIcons and world.specIcons[index] or nil
        end)
        game:Set("C_SpecializationInfo.GetNumSpecializationsForClassID", function() return #specNames end)
        game:Set("GetSpecializationInfoByID", function(specID) return specID, specNames[specID - 100] end)
        game:Set("PawnIsItemAnUpgrade", function()
            local upgrades = {}
            for name in pairs(world.upgradeFor) do
                if world.visible[name] then
                    -- world.pawnPercent: what Pawn's own tooltip line would say, as a fraction.
                    upgrades[#upgrades + 1] = { ScaleName = name, LocalizedScaleName = world.scales[name].LocalizedName,
                        PercentUpgrade = world.pawnPercent and world.pawnPercent[name] or nil }
                end
            end
            table.sort(upgrades, function(a, b) return a.ScaleName < b.ScaleName end)
            return #upgrades > 0 and upgrades or nil
        end)
        game:Set("PawnShouldItemLinkHaveUpgradeArrowUnbudgeted", function()
            for name in pairs(world.upgradeFor) do
                if world.visible[name] then
                    return true
                end
            end
            return false
        end)
        game:Set("PawnResetTooltips", function() end)
        game:Set("PawnInvalidateBestItems", function() end)
        -- features/Tooltip.lua registers with it as it loads.
        game:Set("TooltipDataProcessor.AddTooltipPostCall", function() end)
        -- What the client says a tooltip shows (a tooltip here says it in shownLink).
        -- As the client's, it asks the tooltip its type first: a frame that is no tooltip
        -- has no such function, and fails.
        game:Set("TooltipUtil.GetDisplayedItem", function(tooltip)
            if tooltip:IsTooltipType() and tooltip.shownLink then
                return "its name", tooltip.shownLink
            end
        end)
        -- The client building a comparison tooltip for a worn piece, beside the tooltip of the
        -- piece looked at: it makes that tooltip the owner, clears the comparison tooltip,
        -- fills it with the worn piece (the addon's handler sees it, and Pawn's step runs),
        -- adds its own stat changes and has it shown. Twice in a row, as a bag button's
        -- tooltip was seen to in the retail client.
        function world.BuildComparison(primary, tip, wornPiece)
            for _ = 1, 2 do
                tip.owner = primary
                tip.lines = {}
                tip.shownLink = wornPiece:GetItemLink()
                world.namespace.Tooltip:OweUpgradeLines(tip, wornPiece)
                if world.env.PawnAddValuesToTooltip then
                    world.env.PawnAddValuesToTooltip(tip, "values", nil)
                end
                tip:AddLine("If you replace this item")
                tip:AddLine("+5 Stamina")
                tip.shown = true
            end
        end
        -- The function Pawn adds its tooltip lines in: a line per scale it was told is an
        -- upgrade, and a record of what it was told (world.pawnStep).
        if not (options and options.noPawnTooltipStep) then
            game:Set("PawnAddValuesToTooltip", function(tooltip, itemValues, upgradeInfo, ...)
                local names, extra = {}, {}
                for _, upgrade in ipairs(upgradeInfo or {}) do
                    names[#names + 1] = upgrade.ScaleName
                    tooltip:AddLine("pawn: " .. upgrade.ScaleName)
                end
                for index = 1, select("#", ...) do
                    extra[#extra + 1] = tostring((select(index, ...)))
                end
                world.pawnStep = { scales = table.concat(names, " "), given = upgradeInfo, values = itemValues,
                    extra = table.concat(extra, " "), best = (select(1, ...)), second = (select(2, ...)) }
            end)
        end

        local client = H.Client.New({ flavor = "retail", provider = game })
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
        -- For the lines it adds to a piece's tooltip (14).
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "features/Tooltip.lua", namespace)
        world.client, world.env, world.namespace = client, client.env, namespace

        local core = client.env.CaerdonWardrobe
        local refreshItems = core.RefreshItems
        function core:RefreshItems(reason, detail, changed)
            world.refreshes[#world.refreshes + 1] = { reason = reason, detail = detail }
            return refreshItems(self, reason, detail, changed)
        end
        return world
    end

    local FERAL, GUARDIAN, MAGE, OWN = "\"MrRobot\":DRUID2", "\"MrRobot\":DRUID3", "\"MrRobot\":MAGE1", "My own"

    -- The piece's transmog info with these scales visible and Pawn calling it an upgrade for those.
    -- noRefresh: asked again with what the addon has kept since the last refresh.
    local function Info(world, visible, upgradeFor, itemID, noRefresh)
        world.visible, world.upgradeFor = {}, {}
        for _, name in ipairs(visible) do world.visible[name] = true end
        for _, name in ipairs(upgradeFor) do world.upgradeFor[name] = true end
        if not noRefresh then
            world.env.CaerdonWardrobe:RefreshItems("test")
            world.client:Tick(10)
        end
        local item = world.env.CaerdonItem:CreateFromItemID(itemID or 940001)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        world.client:TickUntil(function() return loaded end, 10)
        return loaded and item:GetItemData():GetTransmogInfo() or {}, item
    end

    -- The lines the addon adds to the piece's tooltip about loadouts, as the world stands
    -- (after an Info(), which refreshes). The item is made as the tooltip makes its own: never
    -- loaded through the addon.
    local function TooltipLines(world, itemID)
        local tooltip = { lines = {} }
        function tooltip:AddLine(line, r, g, b)
            self.lines[#self.lines + 1] = line
            self.colour = string.format("%.2f %.2f %.2f", r, g, b)
        end
        world.namespace.Tooltip:AddLoadoutUpgrades(tooltip, world.env.CaerdonItem:CreateFromItemID(itemID or 940001))
        return table.concat(tooltip.lines, " | "), tooltip.colour
    end

    -- The line as it is expected: the name with its icon in a colour, the arrow, the gain.
    -- worn: the line for what is worn, in the yellow of its arrow.
    local function Line(colour, icon, name, gain, worn)
        return "|cff" .. colour .. (icon and ("|T" .. icon .. ":0|t ") or "") .. name ..
            ":|r  |TInterface\\Buttons\\JumpUpArrow:0:0:0:0:32:32:0:32:0:32:" ..
            (worn and "255:255:0|t|cffffff00" or "255:89:89|t|cffff5959") .. gain .. "|r"
    end

    -- Pawn's values changed (a weight was edited): Pawn says so, and the values kept are dropped.
    local function PawnChanged(world)
        world.env.PawnResetTooltips()
        world.client:Tick(10)
    end

    local world = Start()

    -- The toon's choice of specs (its own settings, CaerdonWardrobeCharacterConfig; nil: it never
    -- chose), and whether Pawn picks the scales it shows by itself (its automatic mode).
    local function Chosen(specs)
        rawset(world.env, "CaerdonWardrobeCharacterConfig", specs and { Icon = { OtherSpecs = specs } } or nil)
    end
    local function Automatic(on)
        rawset(world.env, "PawnOptions", { AutoSelectScales = on })
    end
    -- Two scales of the class shown at once is Pawn's manual mode.
    Automatic(false)
    Equal(#world.client.errors, 0, "start: no error reached the error handler")
    Check(world.env.CaerdonAPI:GetTalentTrees() == nil, "start: this client has no talent tree groups")
    Equal(world.env.CaerdonAPI:IsForeverClient(), false, "start: and is not WoW Forever")
    Equal(world.env.CaerdonAPI:GetPlayerSpecializationIndex(), 3, "start: and the toon plays its third spec")

    -- 1. Feral's and Guardian's scales both visible, playing Guardian.
    local info = Info(world, { FERAL, GUARDIAN }, { GUARDIAN })
    Equal(info.pawnIdentifiedUpgrade, true, "own spec: an upgrade for the played spec's scale is Pawn's upgrade")
    Equal(info.pawnOffTreeUpgrade, false, "own spec: and is not flagged")
    Equal(info.isUpgrade, true, "own spec: an upgrade")

    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.pawnOffTreeUpgrade, true, "other spec: an upgrade only another spec's scale sees is flagged")
    Equal(info.pawnIdentifiedUpgrade, false, "other spec: and is not Pawn's upgrade for this toon")
    Equal(info.isUpgrade, true, "other spec: it stays an upgrade, drawn as one for another spec")

    info = Info(world, { FERAL, GUARDIAN }, { FERAL, GUARDIAN })
    Equal(info.pawnIdentifiedUpgrade, true, "both: an upgrade for both is Pawn's upgrade")
    Equal(info.pawnOffTreeUpgrade, false, "both: not flagged")

    local filter = world.env.CaerdonEquipment:GetPawnScaleFilterDescription()
    Equal(filter, "ignored: Druid: Feral; kept: Druid: Guardian", "export: the filter names the scales")

    -- 2. A custom scale and another class's scale count whatever the spec.
    info = Info(world, { FERAL, GUARDIAN, OWN }, { OWN })
    Equal(info.pawnIdentifiedUpgrade, true, "custom: a scale of the player's own always counts")
    info = Info(world, { FERAL, GUARDIAN, MAGE }, { MAGE })
    Equal(info.pawnIdentifiedUpgrade, true, "other class: a scale for another class is not this rule's to ignore")

    -- 3. Nothing to ignore.
    info = Info(world, { GUARDIAN }, { GUARDIAN })
    Equal(info.pawnIdentifiedUpgrade, true, "one scale: the played spec's scale alone is the toon's own")
    Equal(world.env.CaerdonEquipment:GetPawnScaleFilterDescription(), nil, "one scale: and the filter is off")
    info = Info(world, { OWN }, { OWN })
    Equal(info.pawnIdentifiedUpgrade, true, "one scale: so is a custom scale shown alone")
    Equal(world.env.CaerdonEquipment:GetPawnScaleFilterDescription(), nil, "one scale: with the filter off")
    -- Another spec's scale shown alone, the played spec's hidden: still the other spec's.
    info = Info(world, { FERAL }, { FERAL })
    Equal(info.pawnIdentifiedUpgrade, false, "one scale: another spec's scale shown alone is not the toon's own")
    Equal(info.pawnOffTreeUpgrade, true, "one scale: its upgrade is one for another spec")
    Equal(world.env.CaerdonEquipment:GetPawnScaleFilterDescription(),
        "ignored: Druid: Feral; kept: none shown, so Druid: Guardian is scored though Pawn hides it",
        "one scale: and the export says what is scored in its place")
    world.spec = 5
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.pawnIdentifiedUpgrade, true, "no spec: a toon that has chosen none ignores no scale")
    world.spec = 3

    -- 4. A change of spec, and of the loot spec. Each is the session's first event of its kind.
    world.refreshes = {}
    world.lootSpec = 105
    world.client:Fire("PLAYER_LOOT_SPEC_UPDATED")
    world.client:Tick(20)
    Equal(#world.refreshes, 1, "loot spec: a change of it is one refresh, the session's first event or not")
    Equal(world.refreshes[1] and world.refreshes[1].reason, "loot spec", "loot spec: named for it")
    Equal(world.refreshes[1] and world.refreshes[1].detail, "loot specialization: 0 -> 105", "loot spec: and says which")
    world.refreshes = {}
    world.client:Fire("PLAYER_LOOT_SPEC_UPDATED")
    world.client:Fire("ACTIVE_TALENT_GROUP_CHANGED")
    world.client:Fire("PLAYER_SPECIALIZATION_CHANGED", "party1")
    world.client:Tick(20)
    Equal(#world.refreshes, 0, "spec: events with the spec and the loot spec as they were refresh nothing")
    world.spec = 2
    world.client:Fire("ACTIVE_TALENT_GROUP_CHANGED")
    world.client:Fire("PLAYER_TALENT_UPDATE")
    world.client:Tick(20)
    Equal(#world.refreshes, 1, "spec: a change of spec is one refresh")
    Equal(world.refreshes[1] and world.refreshes[1].reason, "talents", "spec: named for the talents")
    Equal(world.refreshes[1] and world.refreshes[1].detail, "specialization: 3 -> 2", "spec: and says which spec")
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.pawnIdentifiedUpgrade, true, "spec: Feral's scale is the toon's own now")
    info = Info(world, { FERAL, GUARDIAN }, { GUARDIAN })
    Equal(info.pawnOffTreeUpgrade, true, "spec: and Guardian's the other spec's")

    -- 5. Item level where Pawn calls the piece no upgrade: 200 against a worn 190.
    world.spec, world.lootSpec = 3, 0
    local icon = world.env.CaerdonWardrobeConfig.Icon
    world.values = nil
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, true, "item level: where Pawn has no values the higher level is the upgrade")
    Equal(info.upgradeItemLevelDelta, 10, "item level: with its gain")
    Equal(info.pawnIdentifiedUpgrade, false, "item level: and it is not Pawn's")
    icon.ShowItemLevelUpgrades = false
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "item level: none with the addon's setting off")
    Equal(info.upgradeItemLevelDelta, 10, "item level: the level gain is kept, which has a setting of its own")
    local _, jerkin = Info(world, { GUARDIAN }, {})
    local ready, status = jerkin:GetCaerdonStatus()
    Equal(ready and status, "sellable", "item level: no upgrade, so one to sell like any other, with its gain beside it")
    info = Info(world, { GUARDIAN }, { GUARDIAN })
    Equal(info.isUpgrade, true, "item level: Pawn's own upgrade does not depend on that setting")
    icon.ShowItemLevelUpgrades = true

    world.values = { [940001] = 10, [940002] = 12 }
    info = Info(world, { GUARDIAN }, {})
    Equal(info.pawnPrefersEquipped, true, "scores: Pawn rates the worn piece higher")
    Equal(info.isUpgrade, nil, "scores: so the higher level is no upgrade")
    world.env.PawnCommon.ShowItemLevelUpgrades = true
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "scores: whatever Pawn's own item level switch says")
    world.env.PawnCommon.ShowItemLevelUpgrades = false
    icon.ItemLevelOverPawn = true
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, true, "scores: with the addon's setting the higher level stands against them")
    Equal(info.upgradeItemLevelDelta, 10, "scores: with its gain")
    Equal(info.pawnIdentifiedUpgrade, false, "scores: as an item level upgrade, not Pawn's")
    icon.ShowItemLevelUpgrades = false
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "scores: not with item level upgrades switched off above it")
    Equal(info.upgradeItemLevelDelta, nil, "scores: nor a level gain, as there is none with them on")
    _, jerkin = Info(world, { GUARDIAN }, {})
    ready, status = jerkin:GetCaerdonStatus()
    Equal(ready and status, "sellable", "scores: a piece Pawn rates below the worn one is one to sell, higher level or not")
    icon.ShowItemLevelUpgrades, icon.ItemLevelOverPawn = true, false
    world.values = nil

    -- A piece known by a link that is not its own: the auction house names a row by its item
    -- key, and the link the client gives for that key is the plain item's (the jerkin, of level
    -- 200). The row's piece is of level 260. Pawn's scores are the plain item's, 10 against the
    -- worn piece's 12, and its arrow is the plain item's too: neither is asked.
    world.values = { [940001] = 10, [940002] = 12 }
    do
        local function Row(level, upgradeFor, suffix, name)
            world.visible, world.upgradeFor = { [GUARDIAN] = true }, {}
            for _, name in ipairs(upgradeFor or {}) do world.upgradeFor[name] = true end
            world.env.CaerdonWardrobe:RefreshItems("test")
            world.client:Tick(10)
            local item = world.env.CaerdonItem:CreateFromItemLink(world.game.Link(940001),
                { overrideItemLevel = level, keySuffix = suffix, keyName = name })
            local loaded = false
            item:ContinueOnItemLoad(function() loaded = true end)
            world.client:TickUntil(function() return loaded end, 10)
            return loaded and item:GetItemData():GetTransmogInfo() or {}, item
        end
        local row, rowItem = Row(260)
        Equal(row.isUpgrade, true, "row: a piece of a higher level than the worn one is an upgrade, whatever Pawn makes of the plain item")
        Equal(row.upgradeItemLevelDelta, 70, "row: with the gain of the row's own level")
        Equal(row.pawnPrefersEquipped, false, "row: Pawn's scores of the link are not asked")
        Equal(row.pawnIdentifiedUpgrade, false, "row: the upgrade is the item level's, not Pawn's")
        Check(tostring(row.pawnComparison):find("Pawn is not asked", 1, true) ~= nil,
            "row: and the export says so: " .. tostring(row.pawnComparison))
        local gains, why = world.env.CaerdonEquipment:GetReplacementGains(rowItem, world.env.CaerdonItem:CreateFromItemID(940002))
        Check(gains == nil and tostring(why):find("not the piece's", 1, true) ~= nil,
            "row: no scored line beside the worn piece, and why: " .. tostring(why))
        row = Row(260, { GUARDIAN })
        Equal(row.pawnIdentifiedUpgrade, false, "row: Pawn's arrow for the plain item is not the row's either")
        Equal(row.isUpgrade, true, "row: the item level still is")
        icon.ShowItemLevelUpgrades = false
        row = Row(260)
        Equal(row.isUpgrade, nil, "row: no arrow with item level upgrades switched off")
        Equal(row.upgradeItemLevelDelta, 70, "row: the level gain is kept")
        icon.ShowItemLevelUpgrades = true
        -- The row's level is the link's own: the link is the piece, and Pawn is asked as ever.
        row = Row(200)
        Equal(row.pawnPrefersEquipped, true, "row: a row at its link's own level is judged as its link is")
        Equal(row.isUpgrade, nil, "row: so Pawn's scores stand against the level")
        row = Row(150)
        Equal(row.isUpgrade, nil, "row: a row below the worn piece's level is no upgrade")

        -- A row whose key names a suffix ("of the Monkey"): the link the client gives for the
        -- key is the item's without it, at the piece's own level. By its name it is not the
        -- piece's: Pawn is not asked, and the level decides (200 against the worn 190).
        row, rowItem = Row(200)
        local linkName = rowItem:GetItemName()
        Check(type(linkName) == "string" and linkName ~= "", "suffix: the link has a name (" .. tostring(linkName) .. ")")
        row, rowItem = Row(200, nil, 12721, tostring(linkName) .. " of the Monkey")
        Equal(row.pawnPrefersEquipped, false, "suffix: Pawn's scores of the link are not asked for a row named with a suffix")
        Equal(row.isUpgrade, true, "suffix: its item level decides")
        Equal(row.upgradeItemLevelDelta, 10, "suffix: with the gain of the row's own level")
        Check(tostring(row.pawnComparison):find("without the suffix the row names", 1, true) ~= nil,
            "suffix: and the export says why: " .. tostring(row.pawnComparison))
        Equal(world.env.CaerdonEquipment:IsKnownByItsOwnLink(rowItem), false, "suffix: the row is not known by its own link")
        gains, why = world.env.CaerdonEquipment:GetReplacementGains(rowItem, world.env.CaerdonItem:CreateFromItemID(940002))
        Check(gains == nil and tostring(why):find("not the piece's", 1, true) ~= nil,
            "suffix: no scored line beside the worn piece: " .. tostring(why))
        row = Row(200, { GUARDIAN }, 12721, tostring(linkName) .. " of the Monkey")
        Equal(row.pawnIdentifiedUpgrade, false, "suffix: Pawn's arrow for the item without the suffix is not the row's")
        Equal(row.isUpgrade, true, "suffix: the item level still is")
        -- A name that is not known counts as another.
        row = Row(200, nil, 12721, nil)
        Equal(row.pawnPrefersEquipped, false, "suffix: nor is Pawn asked while the row's name is not known")
        Equal(row.isUpgrade, true, "suffix: the level decides then too")
        -- A link that carries the suffix has the row's name: it is the piece, and Pawn is asked.
        row, rowItem = Row(200, nil, 12721, linkName)
        Equal(row.pawnPrefersEquipped, true, "suffix: a link of the row's own name is judged as ever")
        Equal(world.env.CaerdonEquipment:IsKnownByItsOwnLink(rowItem), true, "suffix: and is known by its own link")
        -- A key that names no suffix (0) is judged by its level alone.
        row = Row(200, nil, 0, "another name")
        Equal(row.pawnPrefersEquipped, true, "suffix: a key that names none is not told apart by a name")
        -- The level still comes first, and says so.
        row = Row(260, nil, 12721, tostring(linkName) .. " of the Monkey")
        Check(tostring(row.pawnComparison):find("at another item level", 1, true) ~= nil,
            "suffix: a row at another level says the level: " .. tostring(row.pawnComparison))

        -- A client with talent trees (WoW Forever) has no spec to go by: the tree with the
        -- most points is taken for what the toon plays, and what is worn is scored on the
        -- scale Pawn ships for that tree. The druid's second tree has two scales, damage
        -- (Feral, 2) and tank (Guardian, 3): the one Pawn shows, then the lower number.
        local api = world.env.CaerdonAPI
        local hadTrees, hadPrimary = api.GetTalentTrees, api.GetPrimaryTalentTree
        local TREES = { "Balance", "Feral Combat", "Restoration" }
        local leading = 2
        api.GetTalentTrees = function()
            return { { index = 1, name = TREES[1], spent = 0 }, { index = 2, name = TREES[2], spent = 11 },
                { index = 3, name = TREES[3], spent = 0 } }
        end
        api.GetPrimaryTalentTree = function()
            if leading then
                return leading, TREES[leading], 11, 3
            end
        end
        local function Gain(visible)
            world.visible = {}
            for _, name in ipairs(visible) do world.visible[name] = true end
            PawnChanged(world)
            world.env.CaerdonWardrobe:RefreshItems("test")
            local item = world.env.CaerdonItem:CreateFromItemLink(world.game.Link(940001))
            local loaded = false
            item:ContinueOnItemLoad(function() loaded = true end)
            world.client:TickUntil(function() return loaded end, 10)
            local found, reason = world.env.CaerdonEquipment:GetReplacementGains(item, world.env.CaerdonItem:CreateFromItemID(940002))
            return found and found[1] or nil, reason
        end
        world.scaleValues = { [FERAL] = { [940001] = 30, [940002] = 12 }, [GUARDIAN] = { [940001] = 15, [940002] = 12 } }
        local gain
        gain, why = Gain({ GUARDIAN })
        Equal(world.env.CaerdonEquipment:CanScoreWornGear(), true, "trees: what is worn can be scored on a client with talent trees")
        Check(gain ~= nil and gain.worn == true and gain.percent == 25 and gain.name == "Feral Combat",
            "trees: on the leading tree's scale that Pawn shows, named by the tree (" ..
            tostring(gain and gain.percent) .. ", " .. tostring(gain and gain.name) .. ", " .. tostring(why) .. ")")
        gain = Gain({ FERAL, GUARDIAN })
        Check(gain ~= nil and gain.percent == 150, "trees: of two shown scales of the tree, the lower number's (" .. tostring(gain and gain.percent) .. ")")
        gain = Gain({})
        Check(gain ~= nil and gain.percent == 150, "trees: and so with neither shown (" .. tostring(gain and gain.percent) .. ")")
        gain = Gain({ FERAL })
        Check(gain ~= nil and gain.percent == 150, "trees: the one shown, where it is the lower number's too")
        -- The tooltip's own list has what is worn, where Pawn names the scale for the piece.
        world.visible, world.upgradeFor = { [GUARDIAN] = true }, { [GUARDIAN] = true }
        PawnChanged(world)
        world.env.CaerdonWardrobe:RefreshItems("test")
        local treeItem = world.env.CaerdonItem:CreateFromItemLink(world.game.Link(940001))
        local treeList = world.env.CaerdonEquipment:GetLoadoutUpgradeList(treeItem)
        Check(type(treeList) == "table" and #treeList == 1 and treeList[1].worn == true and treeList[1].percent == 25 and
            treeList[1].name == "Feral Combat", "trees: the item tooltip's list has what is worn, and nothing else")
        world.upgradeFor = {}
        -- A tree with no scale of Pawn's (Balance has none here): nothing, and why.
        leading = 1
        gain, why = Gain({ GUARDIAN })
        Check(gain == nil and tostring(why):find("no scale for the leading tree", 1, true) ~= nil,
            "trees: nothing where Pawn has no scale for the leading tree: " .. tostring(why))
        Equal(world.env.CaerdonEquipment:CanScoreWornGear(), false, "trees: and nothing can be scored then")
        -- No tree leads (no points spent, or a tie): nothing.
        leading = nil
        gain, why = Gain({ GUARDIAN })
        Check(gain == nil and tostring(why):find("no talent tree leads", 1, true) ~= nil,
            "trees: nothing where no tree leads: " .. tostring(why))
        -- Another class's scale for the same number is not the toon's.
        leading = 1
        world.visible = { [MAGE] = true }
        world.env.CaerdonWardrobe:RefreshItems("test")
        Equal(world.env.CaerdonEquipment:CanScoreWornGear(), false, "trees: a scale of another class is not the tree's")
        api.GetTalentTrees, api.GetPrimaryTalentTree = hadTrees, hadPrimary
        world.scaleValues = nil
        world.visible = { [GUARDIAN] = true }
        PawnChanged(world)
        world.env.CaerdonWardrobe:RefreshItems("test")
        gains, why = world.env.CaerdonEquipment:GetReplacementGains(rowItem, world.env.CaerdonItem:CreateFromItemID(940002))
        Check(not tostring(why):find("talent tree", 1, true), "trees: and a client with specializations is as it was: " .. tostring(why))
    end
    world.values = nil

    -- 6. A piece for another loot spec.
    world.itemSpecs = { 105 }
    info = Info(world, { GUARDIAN }, { GUARDIAN })
    Equal(info.upgradeMatchesSpec, false, "loot spec: the piece is for another loot spec")
    Equal(info.pawnIdentifiedUpgrade, true, "loot spec: Pawn's verdict is kept for it")
    Equal(info.isUpgrade, true, "loot spec: an upgrade, which the drawing shows or not")
    world.itemSpecs = { 103, 105 }
    info = Info(world, { GUARDIAN }, { GUARDIAN })
    Equal(info.upgradeMatchesSpec, true, "loot spec: a piece that names the toon's is its own")
    world.itemSpecs = nil

    -- 7. Another spec. Pawn shows Guardian's scale alone and rates the worn jerkin higher on it;
    -- on Feral's scale, which is not shown, the piece is worth 30 and the worn one 5.
    world.spec, world.lootSpec = 3, 0
    world.values = { [940001] = 10, [940002] = 12 }
    world.scaleValues = { [FERAL] = { [940001] = 30, [940002] = 5, [940003] = 20 } }
    -- One scale shown is Pawn's automatic mode, and Feral is a spec the player switched on:
    -- what a spec nobody chose is taken as comes after this (8).
    Automatic(true)
    Chosen({ DRUID2 = true })
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "other spec: nothing while the setting is off")
    icon.ShowOtherSpecUpgrades = true
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, true, "other spec: with no gear set for the spec, the worn piece is what it is compared with")
    Equal(info.pawnOffTreeUpgrade, true, "other spec: flagged as an upgrade for another spec")
    Equal(info.pawnIdentifiedUpgrade, false, "other spec: and not as one for the spec being played")
    Equal(info.pawnUpgradeScales, "Druid: Feral", "other spec: with the spec's name for the export")

    -- Feral has a gear set, whose jerkin is in the bags and worth 40 on Feral's scale.
    world.setForSpec = { [2] = 21 }
    world.setLocations = { [21] = { [5] = 9001 } }
    world.locationData = { [9001] = { isBags = true, bag = 0, slot = 1 } }
    world.scaleValues[FERAL][940003] = 40
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "gear set: the set's piece is what counts, and it is the better one")
    world.scaleValues[FERAL][940003] = 20
    PawnChanged(world)
    info = Info(world, { GUARDIAN }, {})
    Equal(info.pawnOffTreeUpgrade, true, "gear set: a piece that beats the set's piece is the upgrade")
    info = Info(world, { GUARDIAN }, {}, 940003)
    Equal(info.isUpgrade, nil, "gear set: the set's own piece is none")

    -- What the set says about the slot.
    world.setLocations[21][5] = 1
    world.scaleValues[FERAL][940003] = 40
    PawnChanged(world)
    info = Info(world, { GUARDIAN }, {})
    Equal(info.pawnOffTreeUpgrade, true, "gear set: a slot the set leaves alone is compared with the worn piece")
    world.setLocations[21][5] = 0
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "gear set: a slot the set has empty gives no verdict")
    world.setLocations[21][5] = -1
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "gear set: nor a piece that is missing")
    world.setForSpec, world.setLocations, world.locationData = nil, nil, nil

    -- A piece the client says is not for that spec (Guardian is 103 here, Feral 102).
    world.itemSpecs = { 103 }
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "other spec: not for a spec the piece is not for")
    world.itemSpecs = nil
    -- Pawn has no value for it on that scale.
    world.scaleValues[FERAL][940001] = nil
    PawnChanged(world)
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "other spec: nor without a value on the spec's scale")

    -- What it asks of Pawn. A value on a scale Pawn does not show is calculated by Pawn at every
    -- call, so it is kept across refreshes: the second refresh asks for none of them again.
    world.scaleValues[FERAL][940001] = 30
    PawnChanged(world)
    info = Info(world, { GUARDIAN }, {})
    Equal(info.pawnOffTreeUpgrade, true, "kept: the upgrade for the other spec is found")
    world.valueCalls = 0
    info = Info(world, { GUARDIAN }, {})
    Equal(info.pawnOffTreeUpgrade, true, "kept: and again after a refresh")
    Equal(world.valueCalls, 0, "kept: without asking Pawn for a value it gave before")
    -- Pawn says its scales changed: the values are asked for again.
    world.scaleValues[FERAL][940001] = 1
    info = Info(world, { GUARDIAN }, {})
    Equal(info.pawnOffTreeUpgrade, true, "kept: a value is not asked for again by a refresh alone")
    PawnChanged(world)
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "kept: until Pawn says its scales changed, and then the new value counts")

    -- 8. A spec the player switched off: no upgrade for it, by the addon's own scoring or by a
    -- scale of it that Pawn shows.
    world.scaleValues[FERAL][940001] = 30
    PawnChanged(world)
    info = Info(world, { GUARDIAN }, {})
    Equal(info.pawnOffTreeUpgrade, true, "chosen specs: a spec the player switched on counts")
    Chosen({ DRUID2 = false })
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "chosen specs: none for a spec that is switched off")
    Automatic(false)
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.isUpgrade, nil, "chosen specs: nor through its scale where Pawn shows that")
    Chosen({ DRUID2 = true })
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.pawnOffTreeUpgrade, true, "chosen specs: switched on again, it counts")

    -- A spec nobody chose follows the game and Pawn. First: no gear set for it, and Pawn in
    -- its automatic mode, showing the played spec's scale alone.
    local equipment = world.env.CaerdonEquipment
    Chosen(nil)
    Automatic(true)
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "never chosen: no upgrade for a spec with no gear set while Pawn picks its scales")
    Equal(equipment:IsOtherSpecWantedByDefault(2), false, "never chosen: and the page is told the same")
    Equal(world.env.CaerdonWardrobeCharacterConfig, nil, "never chosen: asking writes nothing for the toon")
    -- A gear set assigned to the spec, which leaves the chest alone: the worn piece is compared.
    world.setForSpec = { [2] = 21 }
    world.setLocations = { [21] = { [5] = 1 } }
    info = Info(world, { GUARDIAN }, {})
    Equal(info.pawnOffTreeUpgrade, true, "never chosen: a gear set assigned to the spec makes it wanted")
    Equal(equipment:IsOtherSpecWantedByDefault(2), true, "never chosen: for the page too")
    Equal(equipment:IsOtherSpecWantedByDefault(1), false, "never chosen: and for no other spec")
    -- A click stands against it.
    Chosen({ DRUID2 = false })
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "never chosen: a spec switched off stays off with a gear set assigned")
    Chosen(nil)
    world.setForSpec, world.setLocations = nil, nil
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "never chosen: with the set taken from the spec it is not wanted again")
    -- Pawn in its manual mode: a scale it shows is the player's choice.
    Automatic(false)
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.pawnOffTreeUpgrade, true, "never chosen: a scale the player has Pawn show makes its spec wanted")
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "never chosen: a scale Pawn does not show does not")
    -- The played spec's own switch: in automatic mode Pawn shows that scale by itself.
    Equal(equipment:IsOtherSpecWantedByDefault(3), true, "never chosen: the played spec's scale, shown by choice, counts")
    Automatic(true)
    Equal(equipment:IsOtherSpecWantedByDefault(3), false, "never chosen: shown by Pawn itself, it says nothing")
    -- A scale of another class is no sign for this one's spec of the same number.
    Automatic(false)
    world.visible = { [MAGE] = true, [OWN] = true }
    Equal(equipment:IsOtherSpecWantedByDefault(1), false, "never chosen: another class's scale and a custom one are no sign")
    -- The export's line: every spec with the reason.
    Chosen({ DRUID1 = false })
    world.setForSpec = { [2] = 21 }
    world.setLocations = { [21] = { [5] = 1 } }
    info = Info(world, { GUARDIAN }, {})
    Equal(equipment:GetOtherSpecChoiceDescription(),
        "Balance off (chosen); Feral on (a gear set is assigned to it); Guardian on (Pawn shows its scale); "
        .. "Restoration off (no gear set is assigned to it, and Pawn does not show its scale)",
        "export: each spec with whether it is wanted and why")
    Automatic(true)
    info = Info(world, { GUARDIAN }, {})
    Check(equipment:GetOtherSpecChoiceDescription():find(
        "Guardian off (no gear set is assigned to it, and Pawn picks its scales by itself)", 1, true) ~= nil,
        "export: Pawn's automatic mode is named: " .. tostring(equipment:GetOtherSpecChoiceDescription()))
    world.setForSpec, world.setLocations = nil, nil
    Chosen(nil)
    Automatic(false)
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.pawnOffTreeUpgrade, true, "never chosen: back with Feral's scale shown by choice, it counts")
    -- What the player's settings say about a spec is no longer read.
    Chosen(nil)
    icon.OtherSpecs = { DRUID2 = false }
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.pawnOffTreeUpgrade, true, "chosen specs: a choice left in the player's settings is not the toon's")
    -- Until the settings load: the toon takes what its class had there, once, and another
    -- class's choice stays for a toon of that class.
    icon.OtherSpecs = { DRUID2 = false, DRUID4 = true, MAGE1 = false, ROGUE3 = false, DRUIDIC1 = false }
    world.namespace:LoadCharacterConfig()
    local own = world.env.CaerdonWardrobeCharacterConfig
    Equal(own and own.Icon.OtherSpecs.DRUID2, false, "carried over: the class's choice is the toon's now")
    Equal(own and own.Icon.OtherSpecs.DRUID4, true, "carried over: a spec left on with it")
    Equal(own and own.Icon.OtherSpecs.MAGE1, nil, "carried over: not another class's")
    Equal(own and own.Icon.OtherSpecs.ROGUE3, nil, "carried over: nor one of a class whose name is as long")
    Equal(own and own.Icon.OtherSpecs.DRUIDIC1, nil, "carried over: nor one whose name only starts like the toon's")
    Equal(icon.OtherSpecs.DRUID2, nil, "carried over: and gone from the player's settings")
    Equal(icon.OtherSpecs.MAGE1, false, "carried over: where the other class's stays")
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.isUpgrade, nil, "carried over: the spec is off for the toon")
    -- A toon that has chosen keeps its choice against the class's.
    icon.OtherSpecs = { DRUID2 = true }
    world.namespace:LoadCharacterConfig()
    Equal(world.env.CaerdonWardrobeCharacterConfig.Icon.OtherSpecs.DRUID2, false, "carried over: a choice of the toon's own is kept")
    Equal(icon.OtherSpecs, nil, "carried over: with nothing left, the old table is gone")
    -- Nothing to carry over: nothing is made.
    Chosen(nil)
    world.namespace:LoadCharacterConfig()
    Equal(world.env.CaerdonWardrobeCharacterConfig, nil, "carried over: no settings are made for a toon with nothing to take")
    -- Saved data that is no table is no choice, and no error.
    rawset(world.env, "CaerdonWardrobeCharacterConfig", 7)
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.pawnOffTreeUpgrade, true, "chosen specs: saved data that is no table is no choice")
    rawset(world.env, "CaerdonWardrobeCharacterConfig", { Icon = "broken" })
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.pawnOffTreeUpgrade, true, "chosen specs: and so is a broken section")
    Chosen(nil)
    world.scaleValues, world.values = nil, nil
    icon.ShowOtherSpecUpgrades = false

    -- 9. The played spec's own scale, hidden in Pawn. Guardian is played, Pawn is in its manual
    -- mode, and the piece is ten item levels above the worn one.
    PawnChanged(world)
    -- Pawn shows nothing and has no values: no verdict, and the item level decides as before.
    info = Info(world, {}, {})
    Equal(info.isUpgrade, true, "hidden: with no value on the played spec's scale the higher item level is the upgrade")
    Equal(info.pawnIdentifiedUpgrade, false, "hidden: as an item level upgrade")
    Equal(world.env.CaerdonEquipment:GetPawnScaleFilterDescription(),
        "kept: none shown, so Druid: Guardian is scored though Pawn hides it", "hidden: the export names the scale")
    -- The hidden scale rates the worn piece higher: the higher item level is no upgrade. Before
    -- this rule every higher piece got an arrow here, with nothing of Pawn's to stand against it.
    world.scaleValues = { [GUARDIAN] = { [940001] = 10, [940002] = 12 } }
    PawnChanged(world)
    info = Info(world, {}, {})
    Equal(info.isUpgrade, nil, "hidden: the played spec's scale rates the worn piece higher, so the higher level is none")
    Equal(info.pawnPrefersEquipped, true, "hidden: said as Pawn preferring what is worn")
    Check(tostring(info.pawnComparison):find("Druid: Guardian (not shown in Pawn): 10.00 vs 12.00 equipped", 1, true) ~= nil,
        "hidden: with the numbers for the export: " .. tostring(info.pawnComparison))
    icon.ItemLevelOverPawn = true
    info = Info(world, {}, {})
    Equal(info.isUpgrade, true, "hidden: the addon's setting still lets the item level stand against the scores")
    icon.ItemLevelOverPawn = false
    -- The hidden scale rates the piece higher: the toon's own upgrade, Pawn's by its values.
    world.scaleValues[GUARDIAN][940001] = 30
    PawnChanged(world)
    info = Info(world, {}, {})
    Equal(info.isUpgrade, true, "hidden: a piece the played spec's scale rates higher is an upgrade")
    Equal(info.pawnIdentifiedUpgrade, true, "hidden: the toon's own, by Pawn's values")
    Equal(info.pawnOffTreeUpgrade, false, "hidden: and not one for another spec")
    Equal(info.pawnUpgradeScales, "Druid: Guardian", "hidden: named for the scale")
    Check(tostring(info.pawnComparison):find("Druid: Guardian (not shown in Pawn): 30.00 vs 12.00 equipped", 1, true) ~= nil,
        "hidden: with the numbers for the export: " .. tostring(info.pawnComparison))
    icon.ShowItemLevelUpgrades = false
    info = Info(world, {}, {})
    Equal(info.isUpgrade, true, "hidden: it does not depend on the item level setting")
    icon.ShowItemLevelUpgrades = true
    -- Pawn has no value for the piece on that scale: no verdict, and the item level decides.
    world.scaleValues[GUARDIAN][940001] = nil
    PawnChanged(world)
    info = Info(world, {}, {})
    Equal(info.isUpgrade, true, "hidden: a piece Pawn has no value for is not rated below the worn one")
    Equal(info.pawnIdentifiedUpgrade, false, "hidden: the item level's upgrade, not Pawn's")
    world.scaleValues[GUARDIAN][940001] = 30
    PawnChanged(world)
    -- Another spec's scale is shown beside the hidden one and likes the piece too: the toon's own.
    info = Info(world, { FERAL }, { FERAL })
    Equal(info.pawnIdentifiedUpgrade, true, "hidden: an upgrade for the played spec and a shown one is the toon's own")
    Equal(info.pawnOffTreeUpgrade, false, "hidden: not flagged")
    -- Only the shown scale of the other spec likes it: the other spec's, and the worn piece
    -- stays the better one for the spec being played.
    world.scaleValues[GUARDIAN][940001] = 10
    PawnChanged(world)
    info = Info(world, { FERAL }, { FERAL })
    Equal(info.pawnOffTreeUpgrade, true, "hidden: an upgrade only the other spec's shown scale sees is the other spec's")
    Equal(info.pawnIdentifiedUpgrade, false, "hidden: and not the toon's own")
    Chosen({ DRUID2 = false })
    info = Info(world, { FERAL }, { FERAL })
    Equal(info.isUpgrade, nil, "hidden: none at all with that spec switched off, the worn piece being better for this one")
    Chosen(nil)
    -- A custom scale shown in the hidden one's place is the player's choice: it is what counts.
    world.scaleValues[GUARDIAN][940001] = 30
    world.values = { [940001] = 10, [940002] = 12 }
    PawnChanged(world)
    info = Info(world, { OWN }, {})
    Equal(info.isUpgrade, nil, "hidden: with a custom scale shown the hidden one is not asked")
    Equal(info.pawnPrefersEquipped, true, "hidden: and the custom scale's scores stand")
    -- Shown again, the scale is Pawn's to judge on, as before.
    world.values = nil
    info = Info(world, { GUARDIAN }, { GUARDIAN })
    Equal(info.pawnIdentifiedUpgrade, true, "hidden: shown again, Pawn's verdict is the upgrade")
    Equal(world.env.CaerdonEquipment:GetPawnScaleFilterDescription(), nil, "hidden: and nothing is scored behind Pawn's back")
    -- A toon that has chosen no spec has no scale of its own to fall back on.
    world.spec = 5
    world.scaleValues[GUARDIAN][940001] = 10
    PawnChanged(world)
    info = Info(world, {}, {})
    Equal(info.isUpgrade, true, "hidden: with no spec chosen the item level decides, as before")
    world.spec = 3
    world.scaleValues, world.values = nil, nil
    PawnChanged(world)

    -- 10. Feral has a gear set and Pawn shows Feral's scale beside Guardian's. The set's jerkin
    -- lies in the bags. On Feral's scale the piece is worth 30, the worn jerkin 5; on Guardian's
    -- the worn one is the better.
    local RESTO = "\"MrRobot\":DRUID4"
    local function Comparison(comparison, text)
        return tostring(comparison):find(text, 1, true) ~= nil
    end
    world.setIDs, world.setNames = { 21 }, { [21] = "Cat" }
    world.setForSpec = { [2] = 21 }
    world.setLocations = { [21] = { [5] = 9001 } }
    world.locationData = { [9001] = { isPlayer = true, isBags = true, bag = 0, slot = 1 },
        [9002] = { isPlayer = true, slot = 5 } }
    world.scaleValues = { [FERAL] = { [940001] = 30, [940002] = 5, [940003] = 40 },
        [GUARDIAN] = { [940001] = 10, [940002] = 12, [940003] = 5 } }
    PawnChanged(world)
    icon.ShowOtherSpecUpgrades = true
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.isUpgrade, nil, "shown, with a set: Pawn's upgrade over the worn piece is none where the set's piece is better")
    world.scaleValues[FERAL][940003] = 20
    PawnChanged(world)
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.pawnOffTreeUpgrade, true, "shown, with a set: a piece that beats the set's piece is the other spec's upgrade")
    Equal(info.pawnIdentifiedUpgrade, false, "shown, with a set: and not the toon's own")
    Equal(info.pawnUpgradeScales, "Druid: Feral", "shown, with a set: named for the spec")
    Check(Comparison(info.pawnComparison, "Druid: Feral: 30.00 vs 20.00 in its gear set \"Cat\""),
        "shown, with a set: the export has the numbers and the set: " .. tostring(info.pawnComparison))
    -- The tooltip's line, built like the one Pawn adds for a scale it shows: the gear set's
    -- icon and name in the scale's colour, and the arrow of the piece's button with the gain as
    -- a whole number, both in that arrow's red.
    world.setIcons = { [21] = 132117 }
    world.scales[FERAL].Color = "ff7d0a"
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    local lines, colour = TooltipLines(world)
    Equal(lines, "|cffff7d0a|T132117:0|t Cat:|r  " ..
        "|TInterface\\Buttons\\JumpUpArrow:0:0:0:0:32:32:0:32:0:32:255:89:89|t|cffff5959+50% upgrade|r",
        "tooltip: the set's icon and name, the button's arrow and the gain")
    Equal(colour, "1.00 1.00 1.00", "tooltip: the colours are in the line's own text")
    Equal(TooltipLines(world, 940003), "", "tooltip: nothing on the set's own piece")
    -- A set the client names no icon for, and a scale with no colour of its own in Pawn.
    world.setIcons, world.scales[FERAL].Color = nil, nil
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(TooltipLines(world), Line("8ec3e6", 134400, "Cat", "+50% upgrade"),
        "tooltip: a set with no icon gets the question mark, a scale with no colour Pawn's default")
    -- The gain is rounded to the nearest whole number.
    world.scaleValues[FERAL][940001] = 23.25
    PawnChanged(world)
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(TooltipLines(world), Line("8ec3e6", 134400, "Cat", "+16% upgrade"), "tooltip: 16.25% is 16%")
    world.scaleValues[FERAL][940001] = 23.35
    PawnChanged(world)
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(TooltipLines(world), Line("8ec3e6", 134400, "Cat", "+17% upgrade"), "tooltip: 16.75% is 17%")
    world.scaleValues[FERAL][940001] = 30
    PawnChanged(world)
    -- A piece that is Pawn's upgrade over the worn gear says what it is for the set as well.
    info = Info(world, { FERAL, GUARDIAN }, { GUARDIAN })
    Equal(info.pawnIdentifiedUpgrade, true, "tooltip: the piece is the toon's own upgrade")
    Equal(TooltipLines(world), Line("8ec3e6", 134400, "Cat", "+50% upgrade"),
        "tooltip: and its tooltip still says it is one for the other spec's set")
    world.env.CaerdonWardrobeConfig.Tooltip.ShowLoadoutUpgrades = false
    Equal(TooltipLines(world), "", "tooltip: nothing with its own setting off")
    world.env.CaerdonWardrobeConfig.Tooltip.ShowLoadoutUpgrades = true
    icon.ShowOtherSpecUpgrades = false
    Equal(TooltipLines(world), "", "tooltip: nothing where the arrows for other gear are off")
    icon.ShowOtherSpecUpgrades = true
    -- A set's piece the scale gives no value: an upgrade, and no percentage to give.
    world.scaleValues[FERAL][940003] = 0
    PawnChanged(world)
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(TooltipLines(world), Line("8ec3e6", 134400, "Cat", "upgrade"), "tooltip: no percentage against a piece worth nothing")
    world.scaleValues[FERAL][940003] = 20
    PawnChanged(world)
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    -- Pawn adds a line of its own for a scale it shows, against the worn gear. Where that
    -- line has the same percentage (the set's piece is as good as the worn one), ours is left
    -- out; where it differs, or Pawn adds none, ours is there.
    world.env.PawnCommon.ShowUpgradesOnTooltips = true
    world.pawnPercent = { [FERAL] = 0.5 }
    Equal(TooltipLines(world), "", "tooltip: left out where Pawn's own line for the scale says the same percentage")
    world.pawnPercent = { [FERAL] = 0.496 }
    Equal(TooltipLines(world), "", "tooltip: the same as Pawn prints it, a whole number")
    world.pawnPercent = { [FERAL] = 5 }
    Equal(TooltipLines(world), Line("8ec3e6", 134400, "Cat", "+50% upgrade"),
        "tooltip: there where Pawn's line has another percentage, against the worn piece")
    world.pawnPercent = { [GUARDIAN] = 0.5 }
    Equal(TooltipLines(world), Line("8ec3e6", 134400, "Cat", "+50% upgrade"), "tooltip: another scale's line with that percentage is not this one's")
    world.pawnPercent = { [FERAL] = 0.5 }
    world.env.PawnCommon.ShowUpgradesOnTooltips = false
    Equal(TooltipLines(world), Line("8ec3e6", 134400, "Cat", "+50% upgrade"), "tooltip: there where Pawn's tooltips name no upgrades")
    world.env.PawnCommon.ShowUpgradesOnTooltips = true
    info = Info(world, { GUARDIAN }, {})
    Equal(TooltipLines(world), Line("8ec3e6", 134400, "Cat", "+50% upgrade"), "tooltip: and where Pawn does not show the scale")
    world.pawnPercent, world.env.PawnCommon.ShowUpgradesOnTooltips = nil, nil
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    -- Where the line goes, and what becomes of Pawn's note. Pawn adds its lines in one function
    -- after the client has filled the tooltip. The addon's handler only notes the item; that
    -- function, wrapped, adds the addon's line after Pawn's own, and is not told of an upgrade
    -- for a scale whose gear set decides: Pawn's note for it is against the worn gear.
    local shown = { lines = {} }
    function shown:AddLine(line) self.lines[#self.lines + 1] = line end
    local tooltipFeature = world.namespace.Tooltip
    local piece = world.env.CaerdonItem:CreateFromItemID(940001)
    local pawnInfo = { { ScaleName = FERAL, PercentUpgrade = 5 }, { ScaleName = GUARDIAN, PercentUpgrade = 0.1 } }
    local function PawnStep(tooltip, upgradeInfo, ...)
        world.pawnStep = nil
        tooltip.lines = {}
        world.env.PawnAddValuesToTooltip(tooltip, "values", upgradeInfo, ...)
        return world.pawnStep or {}
    end
    tooltipFeature:OweUpgradeLines(shown, piece)
    Equal(#shown.lines, 0, "placing: the addon's handler adds nothing by itself")
    Equal(rawget(shown, "ProcessInfo"), nil, "placing: and hooks nothing on the tooltip")
    local step = PawnStep(shown, pawnInfo, "best", "second", true)
    Equal(step.scales, GUARDIAN, "pawn's note: the scale whose gear set decides is not among what Pawn is told")
    Equal(#pawnInfo, 2, "pawn's note: Pawn's own table is left as it was")
    Equal(step.values, "values", "pawn's note: the item's values go through")
    Equal(step.extra, "best second true", "pawn's note: and so does everything after them")
    Equal(shown.lines[1], "pawn: " .. GUARDIAN, "placing: Pawn's own lines come first")
    Equal(shown.lines[2], Line("8ec3e6", 134400, "Cat", "+50% upgrade"), "placing: the addon's line follows them")
    Equal(#shown.lines, 2, "placing: and that is all")
    -- A filling the handler did not see (Pawn's own windows) is Pawn's alone.
    step = PawnStep(shown, pawnInfo)
    Equal(step.scales, FERAL .. " " .. GUARDIAN, "placing: what the handler noted is used once")
    Check(step.given == pawnInfo, "placing: and Pawn is then told what it said itself")
    Equal(#shown.lines, 2, "placing: with no line of the addon's")
    -- Pawn has the same percentage as the addon: the set's line still stands in its place.
    world.env.PawnCommon.ShowUpgradesOnTooltips = true
    world.pawnPercent = { [FERAL] = 0.5 }
    tooltipFeature:OweUpgradeLines(shown, piece)
    step = PawnStep(shown, pawnInfo)
    Equal(shown.lines[2], Line("8ec3e6", 134400, "Cat", "+50% upgrade"), "pawn's note: a set's line stands where Pawn's note is taken out, whatever it said")
    world.pawnPercent, world.env.PawnCommon.ShowUpgradesOnTooltips = nil, nil
    -- Pawn names that scale alone: it is told of no upgrade, as a table and not as nothing.
    tooltipFeature:OweUpgradeLines(shown, piece)
    step = PawnStep(shown, { { ScaleName = FERAL, PercentUpgrade = 5 } })
    Check(type(step.given) == "table" and #step.given == 0, "pawn's note: with nothing left Pawn is told of none, not of nothing")
    Equal(#shown.lines, 1, "placing: and the addon's line is the only one")
    -- Pawn names no upgrade at all: the addon's line is added all the same.
    tooltipFeature:OweUpgradeLines(shown, piece)
    step = PawnStep(shown, nil)
    Equal(step.given, nil, "pawn's note: nothing is made of nothing")
    Equal(#shown.lines, 1, "placing: the addon's line needs no line of Pawn's")
    -- A comparison tooltip (the worn piece beside the item looked at) gets no line of the
    -- addon's; Pawn's note for the scale whose set decides is left out there all the same.
    do
        local beside = Tip()
        tooltipFeature:NoteComparisonTooltips(beside)
        tooltipFeature:OweUpgradeLines(beside, piece)
        step = PawnStep(beside, pawnInfo)
        Equal(table.concat(beside.lines, " | "), "pawn: " .. GUARDIAN, "comparison: no line of the addon's in a comparison tooltip")
        Equal(step.scales, GUARDIAN, "comparison: Pawn's note for the scale whose set decides is out there too")
        tooltipFeature:OweUpgradeLines(shown, piece)
        step = PawnStep(shown, pawnInfo)
        Equal(#shown.lines, 2, "comparison: the tooltip of the item itself still has its line")
    end
    -- Pawn's "your best" and "your second best" marks, the two arguments after its upgrades:
    -- left out for the scales the addon judges itself (here the played spec's, with no gear
    -- set being worn, and Feral's, measured against its set), kept for a scale of the player's
    -- own making and another class's.
    local best, second = { [FERAL] = true, [GUARDIAN] = true, [OWN] = true }, { [FERAL] = true, [MAGE] = true }
    tooltipFeature:OweUpgradeLines(shown, piece)
    step = PawnStep(shown, nil, best, second, true)
    Check(type(step.best) == "table" and step.best[FERAL] == nil and step.best[GUARDIAN] == nil and step.best[OWN] == true,
        "pawn's marks: \"your best\" is left out for the scales the addon judges, and kept for a custom scale")
    Check(type(step.second) == "table" and step.second[FERAL] == nil and step.second[MAGE] == true,
        "pawn's marks: \"your second best\" the same way, another class's scale kept")
    Check(best[FERAL] == true and best[GUARDIAN] == true and second[FERAL] == true, "pawn's marks: Pawn's own tables are left as they were")
    Equal(step.extra:match("true$"), "true", "pawn's marks: what follows them goes through")
    -- Another class's scale that happens to carry the number of a spec the addon judges is
    -- that class's: its marks stay.
    do
        local MAGE3 = "\"Classic\":MAGE3"
        local marks = { [MAGE3] = true, [GUARDIAN] = true }
        info = Info(world, { FERAL, GUARDIAN, MAGE3 }, { FERAL })
        tooltipFeature:OweUpgradeLines(shown, piece)
        step = PawnStep(shown, nil, marks, nil)
        Check(type(step.best) == "table" and step.best[MAGE3] == true and step.best[GUARDIAN] == nil,
            "pawn's marks: another class's scale keeps its marks, whatever spec number it carries")
        info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    end
    -- With the arrows for other gear off the other spec's marks are Pawn's again; the played
    -- spec's are still the addon's to judge.
    icon.ShowOtherSpecUpgrades = false
    tooltipFeature:OweUpgradeLines(shown, piece)
    step = PawnStep(shown, nil, best, second)
    Check(step.best[FERAL] == true and step.best[GUARDIAN] == nil, "pawn's marks: with the arrows for other gear off only the played spec's are left out")
    icon.ShowOtherSpecUpgrades = true
    -- A spec that is switched off is not judged: its marks stay.
    Chosen({ DRUID2 = false })
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    tooltipFeature:OweUpgradeLines(shown, piece)
    step = PawnStep(shown, nil, best, second)
    Check(step.best[FERAL] == true and step.second[FERAL] == true, "pawn's marks: kept for a spec that is switched off")
    Chosen(nil)
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    -- The line's setting off, or a filling the handler did not see: Pawn's tables as they are.
    world.env.CaerdonWardrobeConfig.Tooltip.ShowLoadoutUpgrades = false
    tooltipFeature:OweUpgradeLines(shown, piece)
    step = PawnStep(shown, nil, best, second)
    Check(step.best == best and step.second == second, "pawn's marks: untouched with the line's setting off")
    world.env.CaerdonWardrobeConfig.Tooltip.ShowLoadoutUpgrades = true
    step = PawnStep(shown, nil, best, second)
    Check(step.best == best and step.second == second, "pawn's marks: untouched at a filling the handler did not see")
    -- While Pawn reads an item it fills a tooltip of its own, which the addon's handler sees
    -- like any other. Nothing is added to it and nothing started from it.
    local private = { lines = {} }
    function private:AddLine(line) self.lines[#self.lines + 1] = line end
    local reads = 0
    world.onItemData = function()
        reads = reads + 1
        tooltipFeature:OweUpgradeLines(private, piece)
    end
    PawnChanged(world)
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    tooltipFeature:OweUpgradeLines(shown, piece)
    step = PawnStep(shown, pawnInfo)
    world.onItemData = nil
    Check(reads > 0 and reads < 50, "pawn's tooltip: Pawn's reading of the item ends (" .. reads .. " readings)")
    Equal(#private.lines, 0, "pawn's tooltip: nothing is added to the tooltip Pawn reads from")
    Equal(#shown.lines, 2, "pawn's tooltip: and the shown tooltip has its lines")
    -- The piece is no upgrade for the set: Pawn's note is out all the same, and nothing is said.
    world.scaleValues[FERAL][940003] = 40
    PawnChanged(world)
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    tooltipFeature:OweUpgradeLines(shown, piece)
    step = PawnStep(shown, pawnInfo)
    Equal(step.scales, GUARDIAN, "pawn's note: taken out where the set's piece is the better one too")
    Equal(#shown.lines, 1, "placing: with no line of the addon's for a piece that is no upgrade for the set")
    world.scaleValues[FERAL][940003] = 20
    PawnChanged(world)
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    -- The line's setting off, or the arrows for other gear off: Pawn's lines are Pawn's.
    world.env.CaerdonWardrobeConfig.Tooltip.ShowLoadoutUpgrades = false
    tooltipFeature:OweUpgradeLines(shown, piece)
    step = PawnStep(shown, pawnInfo)
    Check(step.given == pawnInfo and #shown.lines == 2, "pawn's note: untouched with the line's setting off")
    world.env.CaerdonWardrobeConfig.Tooltip.ShowLoadoutUpgrades = true
    icon.ShowOtherSpecUpgrades = false
    tooltipFeature:OweUpgradeLines(shown, piece)
    step = PawnStep(shown, pawnInfo)
    Check(step.given == pawnInfo and #shown.lines == 2, "pawn's note: untouched with the arrows for other gear off")
    icon.ShowOtherSpecUpgrades = true
    -- The set's own piece: Pawn's note is out, and the piece is no upgrade for its own set.
    tooltipFeature:OweUpgradeLines(shown, world.env.CaerdonItem:CreateFromItemID(940003))
    step = PawnStep(shown, pawnInfo)
    Equal(step.scales, GUARDIAN, "pawn's note: the set's own piece is no upgrade for the set either")
    info = Info(world, { FERAL, GUARDIAN }, {})
    Equal(info.pawnOffTreeUpgrade, true, "shown, with a set: the set is asked whether or not Pawn calls it an upgrade over the worn piece")
    info = Info(world, { FERAL, GUARDIAN }, { FERAL }, 940003)
    Equal(info.isUpgrade, nil, "shown, with a set: the set's own piece is none, whatever Pawn says of it against the worn one")
    -- The setting off: a scale the player has Pawn show still says the spec is wanted, as it
    -- did for Pawn's verdict. The piece keeps its status; whether it is drawn is the drawing's.
    icon.ShowOtherSpecUpgrades = false
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.pawnOffTreeUpgrade, true, "shown, with a set: asked with the setting off too, where Pawn shows the scale")
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "shown, with a set: not with the setting off and the scale hidden, as before")
    world.scaleValues[FERAL][940003] = 40
    PawnChanged(world)
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.isUpgrade, nil, "shown, with a set: and the set's better piece stands with the setting off")
    -- Only the specs whose scale Pawn shows are asked then: a spec switched on whose scale is
    -- hidden, and for which the piece beats the worn one, waits for the setting.
    world.scales[RESTO] = { ClassID = CLASS_ID, SpecID = 4, Provider = "MrRobot", LocalizedName = "Druid: Restoration" }
    world.scaleValues[RESTO] = { [940001] = 30, [940002] = 5 }
    Chosen({ DRUID4 = true })
    PawnChanged(world)
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.isUpgrade, nil, "shown, with a set: with the setting off a spec whose scale is hidden is not asked")
    icon.ShowOtherSpecUpgrades = true
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.pawnUpgradeScales, "Druid: Restoration", "shown, with a set: and is with it on")
    world.scales[RESTO], world.scaleValues[RESTO] = nil, nil
    Chosen(nil)
    PawnChanged(world)
    -- A spec switched off is none either way.
    world.scaleValues[FERAL][940003] = 20
    PawnChanged(world)
    Chosen({ DRUID2 = false })
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.isUpgrade, nil, "shown, with a set: none for a spec that is switched off")
    Chosen(nil)
    -- A slot the set leaves alone is compared with the worn piece, which is Pawn's answer.
    world.setLocations[21][5] = 1
    world.scaleValues[FERAL][940003] = 40
    PawnChanged(world)
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.pawnOffTreeUpgrade, true, "shown, with a set: a slot the set leaves alone is compared with the worn piece")
    Check(Comparison(info.pawnComparison, "Druid: Feral: 30.00 vs 5.00 worn"),
        "shown, with a set: and the export says so: " .. tostring(info.pawnComparison))
    Equal(TooltipLines(world), Line("8ec3e6", nil, "Feral", "+500% upgrade"),
        "tooltip: where the worn piece stood in for the set's, the line is the spec's and not the set's")
    world.setLocations[21][5] = 9001
    -- Pawn names two other specs, one with a set and one without: its verdict stands for the
    -- one without, and the one with a set is its set's to say.
    world.scales[RESTO] = { ClassID = CLASS_ID, SpecID = 4, Provider = "MrRobot", LocalizedName = "Druid: Restoration" }
    info = Info(world, { FERAL, RESTO, GUARDIAN }, { FERAL, RESTO })
    Equal(info.pawnOffTreeUpgrade, true, "two specs: Pawn's verdict stands for the spec with no gear set")
    local given = equipment:GetPawnScalesGivenToSets() or {}
    Check(given[FERAL] == true and given[RESTO] == nil and given[GUARDIAN] == nil,
        "two specs: of the scales Pawn shows, the one with a gear set alone is its set's in the tooltip")
    Equal(info.pawnUpgradeScales, "Druid: Restoration", "two specs: and the spec whose set has the better piece is not named")
    world.scaleValues[FERAL][940003] = 20
    PawnChanged(world)
    info = Info(world, { FERAL, RESTO, GUARDIAN }, { FERAL, RESTO })
    Equal(info.pawnUpgradeScales, "Druid: Restoration, Druid: Feral", "two specs: it is named where the piece beats its set's")
    info = Info(world, { FERAL, RESTO, GUARDIAN }, { FERAL })
    Equal(info.pawnUpgradeScales, "Druid: Feral", "two specs: and alone where Pawn's verdict was for it alone")
    world.scales[RESTO] = nil
    world.setForSpec, world.setLocations, world.setIDs, world.setNames = nil, nil, nil, nil
    world.scaleValues = nil
    PawnChanged(world)

    -- 11. The played spec's own gear set. Guardian's set has its jerkin in the bags and another
    -- jerkin is worn (another set's: a PVP set put on). On Guardian's scale the piece is worth
    -- 10, the worn jerkin 12 and the set's 5.
    Automatic(true)
    world.setIDs, world.setNames = { 31, 41 }, { [31] = "Bear", [41] = "Arena" }
    world.setForSpec = { [3] = 31 }
    world.setLocations = { [31] = { [5] = 9001 }, [41] = { [5] = 9002 } }
    world.scaleValues = { [GUARDIAN] = { [940001] = 10, [940002] = 12, [940003] = 5 } }
    PawnChanged(world)
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, true, "own set: a piece that beats the set's piece is an upgrade while that piece is not worn")
    Equal(info.pawnOffTreeUpgrade, true, "own set: flagged, as one for gear that is not worn")
    Equal(info.pawnIdentifiedUpgrade, false, "own set: and not as one over the worn piece, which is the better")
    Equal(info.pawnUpgradeScales, "Druid: Guardian", "own set: named for the spec")
    Check(Comparison(info.pawnComparison,
        "Druid: Guardian (the spec being played, its set's piece not worn): 10.00 vs 5.00 in its gear set \"Bear\""),
        "own set: the export has the numbers and the set: " .. tostring(info.pawnComparison))
    Equal(equipment:GetLoadoutDescription(),
        "Druid: Guardian: gear set \"Bear\" (the spec being played: where its piece is not the one worn, slots 5)",
        "own set: the export lists what is compared")
    Equal(TooltipLines(world), Line("8ec3e6", 134400, "Bear", "+100% upgrade"), "own set: and the tooltip names the set")
    -- The played spec's switch is for when another spec is played: it does not take this away.
    Chosen({ DRUID3 = false })
    info = Info(world, { GUARDIAN }, {})
    Equal(info.pawnOffTreeUpgrade, true, "own set: the played spec is wanted whatever its switch says")
    Chosen(nil)
    info = Info(world, { GUARDIAN }, {}, 940003)
    Equal(info.isUpgrade, nil, "own set: the set's own piece is none")
    world.scaleValues[GUARDIAN][940003] = 20
    PawnChanged(world)
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "own set: nor a piece the set's piece is better than")
    world.scaleValues[GUARDIAN][940003] = 5
    PawnChanged(world)
    icon.ShowOtherSpecUpgrades = false
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "own set: nothing with the setting off")
    icon.ShowOtherSpecUpgrades = true
    -- The worn piece is in no gear set (a piece put on that the set was not saved with, gear
    -- never saved as a set): the set's piece is the one to beat all the same.
    world.setIDs = { 31 }
    info = Info(world, { GUARDIAN }, {})
    Equal(info.pawnOffTreeUpgrade, true, "own set: whatever is worn in its place, a piece of another set or of none")
    world.setIDs = { 31, 41 }
    -- From here Pawn's own verdict and the item level are out of the way, so that the piece
    -- can be worth more than the worn one on Guardian's scale and still be no upgrade over it.
    icon.ShowItemLevelUpgrades = false
    world.scaleValues[GUARDIAN][940001] = 30
    PawnChanged(world)
    info = Info(world, { GUARDIAN }, {})
    Equal(info.pawnOffTreeUpgrade, true, "own set: the set put aside is still measured")
    -- The set's piece is the worn one: it has been compared already, as the worn gear.
    world.setLocations[31][5] = 9002
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "own set: not while the set's own piece is worn")
    Equal(equipment:GetLoadoutDescription(),
        "Druid: Guardian: gear set \"Bear\" (the spec being played: where its piece is not the one worn, slots none)",
        "own set: and the export says no slot counts")
    world.setLocations[31][5] = 1
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "own set: a slot the set leaves alone is the worn piece's, which was compared already")
    world.setLocations[31][5] = -1
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "own set: nor a piece that is missing")
    world.setLocations[31][5] = 9001

    -- A slot that comes twice. Guardian's set has two rings: one is worn, the second lies in
    -- the bags with another ring worn in its place. On Guardian's scale the worn rings are
    -- worth 20 and 12, the one put aside 5, the piece 10.
    world.worn[11], world.worn[12] = 940011, 940013
    world.inBag[2] = 940012
    world.locationData[9011] = { isPlayer = true, slot = 11 }
    world.locationData[9012] = { isPlayer = true, slot = 12 }
    world.locationData[9003] = { isPlayer = true, isBags = true, bag = 0, slot = 2 }
    world.setLocations = { [31] = { [5] = 9001, [11] = 9011, [12] = 9003 }, [41] = { [5] = 9002, [11] = 9011, [12] = 9012 } }
    world.scaleValues[GUARDIAN][940011], world.scaleValues[GUARDIAN][940012] = 20, 5
    world.scaleValues[GUARDIAN][940013], world.scaleValues[GUARDIAN][940014] = 12, 10
    PawnChanged(world)
    info = Info(world, { GUARDIAN }, {}, 940014)
    Equal(info.pawnOffTreeUpgrade, true, "two rings: the weaker of the set's two is the one to beat, one of them being worn")
    Check(Comparison(info.pawnComparison, "10.00 vs 5.00 in its gear set \"Bear\""),
        "two rings: with the numbers: " .. tostring(info.pawnComparison))
    Equal(equipment:GetLoadoutDescription(),
        "Druid: Guardian: gear set \"Bear\" (the spec being played: where its piece is not the one worn, slots 5, 12)",
        "two rings: the export names the slot of the ring put aside and not the worn one's")
    world.scaleValues[GUARDIAN][940012] = 25
    PawnChanged(world)
    info = Info(world, { GUARDIAN }, {}, 940012)
    Equal(info.isUpgrade, nil, "two rings: the set's own ring is none, though it is worth more than the set's other one")
    world.scaleValues[GUARDIAN][940012] = 5
    -- Both of the set's rings are worn, one of them in the other slot than it was saved for:
    -- nothing is put aside, though the piece is worth more than the weaker of them.
    world.setLocations[31][11], world.setLocations[31][12] = 9012, 9011
    world.scaleValues[GUARDIAN][940014] = 30
    PawnChanged(world)
    info = Info(world, { GUARDIAN }, {}, 940014)
    Equal(info.isUpgrade, nil, "two rings: not while both of the set's rings are worn")
    -- The set has one ring, put aside, and leaves the other slot alone: the worn ring stands
    -- in there (12), and the set's ring (5) is the weaker one to beat.
    world.setLocations[31][11], world.setLocations[31][12] = 9003, 1
    info = Info(world, { GUARDIAN }, {}, 940014)
    Equal(info.pawnOffTreeUpgrade, true, "two rings: with one slot left alone the worn ring stands in for it")
    Check(Comparison(info.pawnComparison, "30.00 vs 5.00 in its gear set \"Bear\" and worn"),
        "two rings: and the export says both: " .. tostring(info.pawnComparison))
    world.worn[11], world.worn[12], world.inBag[2] = nil, nil, nil
    world.setLocations = { [31] = { [5] = 9001 }, [41] = { [5] = 9002 } }
    -- A toon that has chosen no spec has no set of its own to measure.
    world.spec = 5
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "own set: none with no spec chosen")
    world.spec = 3
    world.setForSpec, world.setLocations, world.setIDs, world.setNames = nil, nil, nil, nil
    world.scaleValues = nil
    PawnChanged(world)

    -- 12. What Pawn's own check refuses. Feral is switched on with its scale hidden; on its
    -- scale the piece is worth 30 and the worn jerkin 5. (The item level is still out of the way.)
    Chosen({ DRUID2 = true })
    world.scaleValues = { [FERAL] = { [940001] = 30, [940002] = 5 }, [GUARDIAN] = { [940001] = 10, [940002] = 12 } }
    PawnChanged(world)
    info = Info(world, { GUARDIAN }, {})
    Equal(info.pawnOffTreeUpgrade, true, "armor type: a piece of the class's own armor type is judged")
    Equal(TooltipLines(world), Line("8ec3e6", nil, "Feral", "+500% upgrade"),
        "tooltip: a spec with no gear set is named as Pawn names its scale, by the spec")
    world.specIcons = { [2] = 132115 }
    info = Info(world, { GUARDIAN }, {})
    Equal(TooltipLines(world), Line("8ec3e6", 132115, "Feral", "+500% upgrade"), "tooltip: with the spec's icon where the client has one")
    world.specIcons = nil
    -- Its scale shown in Pawn: Pawn's note is against the same worn gear, and gives way to the
    -- addon's line all the same, whatever percentage it had (the addon's comparison is the one
    -- shown wherever it has one).
    do
        local shown = { lines = {} }
        function shown:AddLine(line) self.lines[#self.lines + 1] = line end
        local piece = world.env.CaerdonItem:CreateFromItemID(940001)
        local pawnInfo = { { ScaleName = FERAL, PercentUpgrade = 5 } }
        world.env.PawnCommon.ShowUpgradesOnTooltips = true
        world.pawnPercent = { [FERAL] = 5 }
        info = Info(world, { FERAL, GUARDIAN }, { FERAL })
        world.pawnStep = nil
        world.namespace.Tooltip:OweUpgradeLines(shown, piece)
        world.env.PawnAddValuesToTooltip(shown, "values", pawnInfo)
        Equal(world.pawnStep.scales, "", "no set: Pawn's note for a scale the addon has a line for gives way")
        Equal(shown.lines[1], Line("8ec3e6", nil, "Feral", "+500% upgrade"), "no set: to the addon's line")
        Equal(#shown.lines, 1, "no set: and to that alone")
        world.pawnPercent = { [FERAL] = 1 }
        shown.lines = {}
        world.namespace.Tooltip:OweUpgradeLines(shown, piece)
        world.env.PawnAddValuesToTooltip(shown, "values", pawnInfo)
        Equal(shown.lines[1], Line("8ec3e6", nil, "Feral", "+500% upgrade"), "no set: whatever Pawn's percentage was")
        -- The piece is no upgrade for that spec by the addon's reckoning: Pawn's note stays.
        world.scaleValues[FERAL][940001] = 4
        PawnChanged(world)
        info = Info(world, { FERAL, GUARDIAN }, { FERAL })
        shown.lines = {}
        world.namespace.Tooltip:OweUpgradeLines(shown, piece)
        world.env.PawnAddValuesToTooltip(shown, "values", pawnInfo)
        Check(world.pawnStep.given == pawnInfo, "no set: a note of Pawn's the addon has no line for stays")
        world.scaleValues[FERAL][940001] = 30
        PawnChanged(world)
        world.pawnPercent, world.env.PawnCommon.ShowUpgradesOnTooltips = nil, nil
        info = Info(world, { GUARDIAN }, {})
    end
    world.wrongArmor = { [940001] = true }
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "armor type: none for armor Pawn calls the wrong type for the class")
    Equal(TooltipLines(world), "", "tooltip: and no line for it")
    world.wrongArmor = nil
    info = Info(world, { GUARDIAN }, {})
    Equal(info.pawnOffTreeUpgrade, true, "armor type: asked of Pawn again after a refresh")
    world.unread = { [940001] = true }
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "armor type: no verdict for a piece Pawn has not read yet")
    world.unread = nil
    info = Info(world, { GUARDIAN }, {}, nil, true)
    Equal(info.pawnOffTreeUpgrade, true, "armor type: and that is not kept against the piece, refresh or not")

    -- Weapons. A staff is worn; Feral's set has a one-handed mace for the main hand, in the
    -- bags. On Feral's scale the staff in question is worth 50 and the set's mace 20.
    world.worn[16] = 940023
    world.inBag[3], world.inBag[4] = 940022, 940025
    world.setIDs, world.setNames = { 21 }, { [21] = "Cat" }
    world.setForSpec = { [2] = 21 }
    world.locationData[9031] = { isPlayer = true, isBags = true, bag = 0, slot = 3 }
    world.locationData[9032] = { isPlayer = true, isBags = true, bag = 0, slot = 4 }
    world.setLocations = { [21] = { [16] = 9031 } }
    world.scaleValues = { [FERAL] = { [940021] = 50, [940022] = 20, [940023] = 5, [940024] = 60, [940025] = 40 },
        [GUARDIAN] = { [940021] = 10, [940023] = 12, [940024] = 10 } }
    PawnChanged(world)
    info = Info(world, { GUARDIAN }, {}, 940021)
    Equal(info.isUpgrade, nil, "weapons: a two-hander is not weighed against a set's one-hander alone")
    info = Info(world, { GUARDIAN }, {}, 940024)
    Equal(info.pawnOffTreeUpgrade, true, "weapons: a one-hander against the set's one-hander is")
    -- The set's main hand is a staff worth 40.
    world.setLocations[21][16] = 9032
    info = Info(world, { GUARDIAN }, {}, 940021)
    Equal(info.pawnOffTreeUpgrade, true, "weapons: a two-hander against the set's two-hander is weighed")
    info = Info(world, { GUARDIAN }, {}, 940024)
    Equal(info.isUpgrade, nil, "weapons: a one-hander is not weighed against a set's two-hander")
    -- What the scale is told not to show.
    world.scales[FERAL].DoNotShow2HUpgrades = true
    info = Info(world, { GUARDIAN }, {}, 940021)
    Equal(info.isUpgrade, nil, "weapons: nor a two-hander on a scale told not to show them")
    world.scales[FERAL].DoNotShow2HUpgrades = nil
    world.setLocations[21][16] = 9031
    world.scales[FERAL].DoNotShow1HUpgrades = true
    info = Info(world, { GUARDIAN }, {}, 940024)
    Equal(info.isUpgrade, nil, "weapons: nor a one-hander on a scale told not to show those")
    world.scales[FERAL].DoNotShow1HUpgrades = nil
    world.worn[16], world.inBag[3], world.inBag[4] = nil, nil, nil
    world.setForSpec, world.setLocations, world.setIDs, world.setNames = nil, nil, nil, nil
    world.scaleValues = nil
    Chosen(nil)
    PawnChanged(world)

    -- 13. Unique-equipped. A ring of a family the toon wears one of, ten levels above that one:
    -- an upgrade by the addon's own rule for such pieces. Pawn calls it an upgrade too, for
    -- Feral's shown scale alone.
    Automatic(false)
    world.worn[11], world.worn[12] = 940011, 940013
    world.unique = { [940011] = 77, [940015] = 77 }
    -- Feral has no gear set and is wanted: Pawn's verdict stands, and the arrow is Feral's.
    Chosen({ DRUID2 = true })
    info = Info(world, { FERAL, GUARDIAN }, { FERAL }, 940015)
    Equal(info.uniqueUpgradeCandidate, true, "unique: the ring would replace the lower one of its family")
    Equal(info.pawnOffTreeUpgrade, true, "unique: where Pawn's verdict for the other spec stands, the arrow is that spec's")
    -- Feral switched off: Pawn's verdict does not count, and the arrow is the ring's own.
    Chosen({ DRUID2 = false })
    info = Info(world, { FERAL, GUARDIAN }, { FERAL }, 940015)
    Equal(info.isUpgrade, true, "unique: with the spec switched off the ring is still an upgrade by its own rule")
    Equal(info.pawnOffTreeUpgrade, false, "unique: and not drawn as the upgrade of a spec that is switched off")
    Equal(info.pawnIdentifiedUpgrade, false, "unique: nor as Pawn's")
    -- Feral has a gear set: the set decides in Pawn's place, and the arrow is the ring's own.
    Chosen({ DRUID2 = true })
    world.setIDs, world.setNames = { 21 }, { [21] = "Cat" }
    world.setForSpec = { [2] = 21 }
    world.setLocations = { [21] = {} }
    info = Info(world, { FERAL, GUARDIAN }, { FERAL }, 940015)
    Equal(info.isUpgrade, true, "unique: with a gear set for the spec the ring is an upgrade by its own rule")
    Equal(info.pawnOffTreeUpgrade, false, "unique: and not drawn as the upgrade of a spec whose set decides")
    world.worn[11], world.worn[12], world.unique = nil, nil, nil
    world.setForSpec, world.setLocations, world.locationData, world.setIDs, world.setNames = nil, nil, nil, nil, nil
    Chosen(nil)
    icon.ShowItemLevelUpgrades = true
    icon.ShowOtherSpecUpgrades = false
    PawnChanged(world)

    -- 15. What is worn. Guardian is played and Pawn shows its scale; on it the piece is worth
    -- 30 and the worn jerkin 12. The arrows for other gear are off: this line is not theirs.
    do
        local shown = { lines = {} }
        function shown:AddLine(line) self.lines[#self.lines + 1] = line end
        local feature = world.namespace.Tooltip
        local piece = world.env.CaerdonItem:CreateFromItemID(940001)
        local pawnInfo = { { ScaleName = GUARDIAN, PercentUpgrade = 1.5 } }
        -- The tooltip as Pawn's step leaves it, and what Pawn was told.
        local function Shown(visible, upgradeFor)
            info = Info(world, visible, upgradeFor)
            world.pawnStep, shown.lines = nil, {}
            feature:OweUpgradeLines(shown, piece)
            world.env.PawnAddValuesToTooltip(shown, "values", pawnInfo)
            return world.pawnStep
        end
        world.scaleValues = { [GUARDIAN] = { [940001] = 30, [940002] = 12, [940003] = 5 } }
        world.locationData = { [9001] = { isPlayer = true, isBags = true, bag = 0, slot = 1 },
            [9002] = { isPlayer = true, slot = 5 } }
        PawnChanged(world)
        Equal(icon.ShowOtherSpecUpgrades, false, "worn: the arrows for other gear are off here")

        -- Pawn calls the piece an upgrade on the played spec's scale: the yellow arrow, and the
        -- addon's line in its place, in yellow, with the addon's own percentage.
        local step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(info.pawnIdentifiedUpgrade, true, "worn: the piece has the yellow arrow")
        Equal(step.scales, "", "worn: Pawn's note for the scale gives way")
        Equal(shown.lines[1], Line("8ec3e6", nil, "Guardian", "+150% upgrade", true),
            "worn: to the addon's line, named for the spec while no gear set is being worn")
        Equal(#shown.lines, 1, "worn: one line")

        -- A piece the toon has not the level for yet is an upgrade to come: the line stands,
        -- with the mark for "usable later" where the arrow would be and the level after the
        -- gain, and Pawn's note still gives way to it.
        local minLevel = piece:GetMinLevel()
        Check(type(minLevel) == "number" and minLevel > 1, "later: the piece asks for a level (" .. tostring(minLevel) .. ")")
        rawset(world.env, "UnitLevel", function() return 1 end)
        step = Shown({ GUARDIAN }, { GUARDIAN })
        local later = tostring(shown.lines[1])
        Check(#shown.lines == 1 and later:find("Gear_64Grey", 1, true) ~= nil and not later:find("JumpUpArrow", 1, true),
            "later: the line has the mark for later in the arrow's place (" .. later .. ")")
        Check(later:find("+150% upgrade", 1, true) ~= nil and
            later:find("(at level " .. tostring(minLevel) .. ")", 1, true) ~= nil, "later: with the gain, and the level after it")
        Equal(step.scales, "", "later: Pawn's note for the scale gives way to it as well")
        local laterList = world.env.CaerdonEquipment:GetLoadoutUpgradeList(piece)
        Equal(laterList and laterList[1].atLevel, minLevel, "later: the entry says the level")
        local laterGains = world.env.CaerdonEquipment:GetReplacementGains(piece, world.env.CaerdonItem:CreateFromItemID(940002))
        Equal(laterGains and laterGains[1].atLevel, minLevel, "later: and so does the one for a comparison")
        local short = tostring(feature:GetShortGainText({ upgrade = true, percent = 12, worn = true, atLevel = minLevel }))
        Check(short:find("Gear_64Grey", 1, true) ~= nil and short:find("+12%", 1, true) ~= nil and
            not short:find("JumpUpArrow", 1, true), "later: a listing's short text has the mark too (" .. short .. ")")
        rawset(world.env, "UnitLevel", nil)
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(shown.lines[1], Line("8ec3e6", nil, "Guardian", "+150% upgrade", true), "later: at its level the line is as it was")
        Equal(world.env.CaerdonEquipment:GetLoadoutUpgradeList(piece)[1].atLevel, nil, "later: and the entry says no level")

        -- Nothing is worn in the piece's slot: it fills the slot, and the line says "upgrade"
        -- with no percentage, in the place of Pawn's note.
        local wornChest = world.worn[5]
        Check(wornChest ~= nil, "empty: the jerkin's slot has a piece on")
        world.worn[5] = nil
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(shown.lines[1], Line("8ec3e6", nil, "Guardian", "upgrade", true), "empty: a piece for a slot with nothing on has the line, with no percentage")
        Equal(#shown.lines, 1, "empty: one line")
        Equal(step.scales, "", "empty: and Pawn's note gives way to it")
        local emptyList = world.env.CaerdonEquipment:GetLoadoutUpgradeList(piece)
        Check(emptyList ~= nil and emptyList[1].emptySlot == true and emptyList[1].percent == nil and emptyList[1].worn == true,
            "empty: the entry says the slot is empty")
        -- Not where Pawn does not call the piece an upgrade for the scale.
        step = Shown({ GUARDIAN }, {})
        Check(#shown.lines == 1 and shown.lines[1] == "pawn: " .. GUARDIAN and step.scales == GUARDIAN,
            "empty: where Pawn does not name the scale for the piece the addon has no line, and the note Pawn was handed stays")
        world.worn[5] = wornChest
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(shown.lines[1], Line("8ec3e6", nil, "Guardian", "+150% upgrade", true), "empty: with the slot filled the line is as it was")
        -- A slot with a piece on that Pawn has no value for is not an empty one: nothing is
        -- said of it, and Pawn's note stays.
        world.scaleValues[GUARDIAN][940002] = nil
        PawnChanged(world)
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Check(#shown.lines == 1 and shown.lines[1] == "pawn: " .. GUARDIAN and step.scales == GUARDIAN,
            "empty: a worn piece Pawn has no value for is not an empty slot (" .. tostring(shown.lines[1]) .. ")")
        world.scaleValues[GUARDIAN][940002] = 12
        PawnChanged(world)
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(shown.lines[1], Line("8ec3e6", nil, "Guardian", "+150% upgrade", true), "empty: and with its value back the line is too")
        -- The same link standing for a piece of another level (an auction row by item key):
        -- nothing is scored off it.
        Check(world.env.CaerdonEquipment:GetLoadoutUpgradeList(piece) ~= nil, "row: the piece itself has its line")
        Equal(world.env.CaerdonEquipment:GetLoadoutUpgradeList(
            world.env.CaerdonItem:CreateFromItemLink(piece:GetItemLink(), { overrideItemLevel = 260 })), nil,
            "row: the same link standing for a piece of another level has none")
        -- The gear set being worn names the line: the one with most of its pieces on.
        world.setIDs, world.setNames, world.setIcons = { 41, 31 }, { [31] = "Bear", [41] = "Arena" }, { [31] = 132276 }
        world.setForSpec = { [3] = 31 }
        world.setLocations = { [31] = { [5] = 9002 }, [41] = {} }
        world.setWorn = { [31] = { 10, 9 }, [41] = { 10, 2 } }
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(shown.lines[1], Line("8ec3e6", 132276, "Bear", "+150% upgrade", true), "worn: named for the gear set being worn, with its icon")
        world.setWorn = { [31] = { 10, 9 }, [41] = { 10, 6 } }
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(shown.lines[1], Line("8ec3e6", 132276, "Bear", "+150% upgrade", true), "worn: of two sets mostly on, the one with the larger share")
        world.setWorn = { [31] = { 10, 9 }, [41] = { 10, 9 } }
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(shown.lines[1], Line("8ec3e6", 132276, "Bear", "+150% upgrade", true), "worn: of two sets worn alike, the played spec's own")
        world.setWorn = { [31] = { 10, 10 }, [41] = { 10, 10 } }
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(shown.lines[1], Line("8ec3e6", 132276, "Bear", "+150% upgrade", true), "worn: and of two sets on in full")
        -- A set with no spec is the one on: the played spec's scale is not that gear's, so the
        -- addon has no line for what is worn and Pawn's note stands.
        world.setWorn = { [31] = { 10, 4 }, [41] = { 10, 10 } }
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Check(step.given == pawnInfo and table.concat(shown.lines, " | ") == "pawn: " .. GUARDIAN,
            "worn: no line of the addon's while a set with no spec is the one worn, and Pawn's note stays")
        do
            local best = { [GUARDIAN] = true }
            feature:OweUpgradeLines(shown, piece)
            world.env.PawnAddValuesToTooltip(shown, "values", nil, best, nil)
            Check(world.pawnStep.best == best, "worn: and so do Pawn's marks for the played spec's scale, which the addon does not judge then")
        end
        Equal(equipment:GetActiveSetDescription(),
            "\"Arena\" (on in full; the set last put on: none noted); the worn gear's own tooltip line: no, the set worn is not the played spec's",
            "worn: the export says which set is taken for the one worn, and why")
        -- The played spec's own set without an icon gets the question mark.
        world.setIcons = nil
        world.setWorn = { [31] = { 10, 9 } }
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(shown.lines[1], Line("8ec3e6", 134400, "Bear", "+150% upgrade", true), "worn: a set with no icon gets the question mark")
        world.setIcons = { [31] = 132276 }
        world.setWorn = { [31] = { 10, 5 }, [41] = { 10, 3 } }
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(shown.lines[1], Line("8ec3e6", nil, "Guardian", "+150% upgrade", true), "worn: no set with half its pieces on or fewer")

        -- Two sets of one toon often share most of their pieces, and shares then name the wrong
        -- one: Feral's set has nine of ten on, Guardian's eight. Until the player is seen to
        -- put a set on, Feral's is taken for the one worn, and it is another spec's: no line.
        world.setIDs, world.setNames = { 21, 41, 31 }, { [21] = "Cat", [31] = "Bear", [41] = "Arena" }
        world.setForSpec = { [2] = 21, [3] = 31 }
        world.setLocations[21] = {}
        world.setWorn = { [21] = { 10, 9 }, [31] = { 10, 8 }, [41] = { 10, 2 } }
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(table.concat(shown.lines, " | "), "pawn: " .. GUARDIAN, "chosen set: by shares alone the overlapping set is taken for the one worn")
        -- The player puts Guardian's set on: that is the set worn from then on.
        world.client:Fire("EQUIPMENT_SWAP_FINISHED", true, 31)
        world.client:Tick(10)
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(shown.lines[1], Line("8ec3e6", 132276, "Bear", "+150% upgrade", true), "chosen set: the set last put on is the one worn, though another has more of its pieces on")
        Equal(equipment:GetActiveSetDescription(),
            "\"Bear\" (the set last put on; the set last put on: 31); the worn gear's own tooltip line: yes",
            "chosen set: and the export says so")
        local saved = world.env.CaerdonRefreshData
        Equal(type(saved) == "table" and saved[TOON.realm] and saved[TOON.realm][TOON.name] and
            saved[TOON.realm][TOON.name].chosenGearSet, 31, "chosen set: kept for the toon between sessions")
        -- A swap the client says failed is no choice.
        world.client:Fire("EQUIPMENT_SWAP_FINISHED", false, 41)
        world.client:Tick(10)
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(shown.lines[1], Line("8ec3e6", 132276, "Bear", "+150% upgrade", true), "chosen set: a swap that failed changes nothing")
        -- Checked against the client: another set is on in full and the chosen one is not.
        world.setWorn[41] = { 10, 10 }
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(table.concat(shown.lines, " | "), "pawn: " .. GUARDIAN, "chosen set: another set on in full, where the chosen one is not, is the one worn")
        Check(tostring(equipment:GetActiveSetDescription()):find("\"Arena\" (on in full, where the set last put on is not;", 1, true) ~= nil,
            "chosen set: with the reason in the export: " .. tostring(equipment:GetActiveSetDescription()))
        -- The chosen one on in full as well: the choice stands.
        world.setWorn[31] = { 10, 10 }
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(shown.lines[1], Line("8ec3e6", 132276, "Bear", "+150% upgrade", true), "chosen set: on in full itself, the chosen set stands beside another")
        -- And the other way round: the set with no spec was the one put on, both are on in
        -- full, and the choice stands against the played spec's own.
        world.client:Fire("EQUIPMENT_SWAP_FINISHED", true, 41)
        world.client:Tick(10)
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(table.concat(shown.lines, " | "), "pawn: " .. GUARDIAN, "chosen set: the set put on stands, on in full, beside the played spec's own")
        world.client:Fire("EQUIPMENT_SWAP_FINISHED", true, 31)
        world.client:Tick(10)
        world.setWorn[41], world.setWorn[31] = { 10, 2 }, { 10, 8 }
        -- The chosen set no longer exists: the shares decide again.
        world.setIDs = { 21, 41 }
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(table.concat(shown.lines, " | "), "pawn: " .. GUARDIAN, "chosen set: a set that is gone is no longer the one worn")
        world.setIDs, world.setNames = { 41, 31 }, { [31] = "Bear", [41] = "Arena" }
        world.setForSpec = { [3] = 31 }
        world.setLocations[21] = nil
        world.setWorn = { [31] = { 10, 9 } }

        -- The piece worn in the slot was never saved into the set (the set's own lies in the
        -- bags): it is taken for the set's, and the piece that beats it has the one line.
        world.setLocations[31][5] = 9001
        icon.ShowOtherSpecUpgrades = true
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(#shown.lines, 1, "worn: a piece that beats the worn one has one line, not a second for the set's saved piece")
        Equal(shown.lines[1], Line("8ec3e6", 132276, "Bear", "+150% upgrade", true), "worn: the yellow one")
        -- A piece between the two: no upgrade over the worn one, one for the set's saved piece.
        world.scaleValues[GUARDIAN][940001] = 10
        PawnChanged(world)
        step = Shown({ GUARDIAN }, {})
        Equal(info.pawnOffTreeUpgrade, true, "worn: a piece between the worn one and the set's saved one has the red arrow")
        Equal(shown.lines[2], Line("8ec3e6", 132276, "Bear", "+100% upgrade"), "worn: and the set's line in red")
        Equal(step.scales, GUARDIAN, "worn: a note of Pawn's for the played spec's scale does not give way to the set's line, which is another comparison")
        Equal(#shown.lines, 2, "worn: so both are there")
        world.scaleValues[GUARDIAN][940001] = 30
        PawnChanged(world)
        icon.ShowOtherSpecUpgrades = false
        world.setLocations[31][5] = 9002

        -- A piece the client lists for other specs than the toon's loot spec (Guardian is 103),
        -- which Pawn calls an upgrade on the played spec's scale all the same: the worn gear's
        -- line, in the red its arrow has, with whose gear the piece is. Pawn's note for the
        -- scale gives way to it. The arrows for other gear are off: it is none of theirs.
        world.itemSpecs = { 101, 104 }
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(info.upgradeMatchesSpec, false, "off-spec: the piece is gear for another loot spec")
        Equal(info.pawnIdentifiedUpgrade, true, "off-spec: and an upgrade of Pawn's on the played spec's scale")
        Equal(shown.lines[1], Line("8ec3e6", 132276, "Bear", "+150% upgrade") .. "  |cff808080(Balance / Restoration gear)|r",
            "off-spec: the worn gear's line in red, with whose gear the piece is")
        Equal(#shown.lines, 1, "off-spec: one line")
        Equal(step.scales, "", "off-spec: Pawn's note for the scale gives way to it")
        -- Listed for the toon's loot spec among others: the yellow line, and no such note.
        world.itemSpecs = { 101, 103 }
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(shown.lines[1], Line("8ec3e6", 132276, "Bear", "+150% upgrade", true),
            "off-spec: a piece listed for the toon's loot spec has the yellow line")
        -- The loot spec is another than the spec played: the list is read against it, as the
        -- arrow's colour is.
        world.lootSpec = 104
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(info.upgradeMatchesSpec, false, "off-spec: the arrow goes by the loot spec")
        Equal(shown.lines[1], Line("8ec3e6", 132276, "Bear", "+150% upgrade") .. "  |cff808080(Balance / Guardian gear)|r",
            "off-spec: and so does the line")
        world.lootSpec = 0
        -- A spec the client has no name for is left out, and with no name at all there is no note.
        world.itemSpecs = { 199 }
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(shown.lines[1], Line("8ec3e6", 132276, "Bear", "+150% upgrade"), "off-spec: red without a note where the client names no spec")
        world.itemSpecs = nil

        -- Pawn does not call it an upgrade, though the numbers would: no yellow arrow, no line,
        -- and Pawn's notes are its own.
        step = Shown({ GUARDIAN }, {})
        Check(step.given == pawnInfo and #shown.lines == 1, "worn: no line of the addon's where the piece has no yellow arrow")
        -- Pawn shows no scale of the toon's own: the addon judges on the hidden one, and says so.
        step = Shown({}, {})
        Equal(info.pawnIdentifiedUpgrade, true, "worn: judged on the hidden scale, the piece has the yellow arrow")
        Equal(shown.lines[1], Line("8ec3e6", 132276, "Bear", "+150% upgrade", true), "worn: and its line")
        Equal(#shown.lines, 1, "worn: alone")
        -- A custom scale shown in the played spec's place is the player's choice: no line.
        world.values = { [940001] = 10, [940002] = 12 }
        step = Shown({ OWN }, {})
        Equal(table.concat(shown.lines, " | "), "pawn: " .. GUARDIAN, "worn: nothing where a custom scale stands for the played spec")
        world.values = nil
        -- The worn piece itself, and a tabard's kin: nothing to say.
        piece = world.env.CaerdonItem:CreateFromItemID(940002)
        step = Shown({ GUARDIAN }, { GUARDIAN })
        Equal(table.concat(shown.lines, " | "), "pawn: " .. GUARDIAN, "worn: nothing on the worn piece itself")

        world.setForSpec, world.setLocations, world.locationData = nil, nil, nil
        world.setIDs, world.setNames, world.setIcons, world.setWorn = nil, nil, nil, nil
        world.scaleValues = nil
        PawnChanged(world)
    end

    -- 16. The comparison tooltips. Two rings are worn; on Guardian's scale they are worth 20 and
    -- 12 and the ring looked at 15: better than one of them, worse than the other.
    do
        local function Loss(colour, icon, name, change)
            return "|cff" .. colour .. (icon and ("|T" .. icon .. ":0|t ") or "") .. name .. ":|r  |cff808080" .. change .. "|r"
        end
        local feature = world.namespace.Tooltip
        local primary, beside1, beside2 = Tip(), Tip(), Tip()
        feature:NoteComparisonTooltips(beside1, beside2)
        local looked = world.env.CaerdonItem:CreateFromItemID(940014)
        local ring1, ring2 = world.env.CaerdonItem:CreateFromItemID(940011), world.env.CaerdonItem:CreateFromItemID(940013)
        -- What the addon adds to a comparison tooltip the client builds for the worn piece,
        -- the piece looked at being in the tooltip that owns it: what follows the client's
        -- lines. Nothing while the client builds (it builds twice); the lines come when a
        -- frame goes by for the tooltip.
        local function Beside(tip, wornPiece, lookedAt)
            primary.shownLink = (lookedAt or looked):GetItemLink()
            world.BuildComparison(primary, tip, wornPiece)
            Equal(#tip.lines, 2, "replacing: nothing is added while the client builds")
            tip:Update()
            Check(tip.lines[1] == "If you replace this item" and tip.lines[2] == "+5 Stamina",
                "replacing: the client's own lines come first: " .. table.concat(tip.lines, " | "))
            return table.concat(tip.lines, " | ", 3)
        end
        world.worn[11], world.worn[12] = 940011, 940013
        world.inBag[2] = 940012
        world.scaleValues = { [GUARDIAN] = { [940014] = 15, [940011] = 20, [940013] = 12, [940001] = 40 },
            [FERAL] = { [940014] = 30, [940011] = 20, [940013] = 25, [940012] = 10 } }
        world.locationData = { [9011] = { isPlayer = true, slot = 11 }, [9003] = { isPlayer = true, isBags = true, bag = 0, slot = 2 } }
        PawnChanged(world)
        info = Info(world, { GUARDIAN }, {}, 940014)
        Equal(Beside(beside1, ring1), Loss("8ec3e6", nil, "Guardian", "-25%"), "replacing: the better ring's tooltip says what would be lost, in grey")
        Equal(Beside(beside2, ring2), Line("8ec3e6", nil, "Guardian", "+25% upgrade", true), "replacing: the weaker ring's says what would be gained, as the yellow line does")
        -- Another spec's gear set that has the first ring too, and a ring in the bags for the
        -- second slot. On Feral's scale the ring looked at is worth 30, the shared ring 20.
        world.setIDs, world.setNames = { 21 }, { [21] = "Cat" }
        world.setForSpec = { [2] = 21 }
        world.setLocations = { [21] = { [11] = 9011, [12] = 9003 } }
        info = Info(world, { GUARDIAN }, {}, 940014)
        Equal(Beside(beside1, ring1), Loss("8ec3e6", nil, "Guardian", "-25%"), "replacing: nothing for another spec's set with the arrows for other gear off")
        -- Nor with them on: that set is not the one on, and the comparison is about what is.
        -- What the ring would be for that set stays where it was, in the ring's own tooltip.
        icon.ShowOtherSpecUpgrades = true
        info = Info(world, { GUARDIAN }, {}, 940014)
        Equal(Beside(beside1, ring1), Loss("8ec3e6", nil, "Guardian", "-25%"),
            "replacing: a set that is not the one on has no line beside the worn gear's, though it has this worn ring too")
        Equal(Beside(beside2, ring2), Line("8ec3e6", nil, "Guardian", "+25% upgrade", true),
            "replacing: and none in the tooltip of the ring it does not have")
        local ownLines = world.env.CaerdonEquipment:GetLoadoutUpgradeList(looked) or {}
        Check(#ownLines == 1 and ownLines[1].name == "Cat" and ownLines[1].percent == 200,
            "replacing: what the ring would be for that set is in the ring's own tooltip")
        -- The played spec's own set has both worn rings: it is the worn gear over again, and
        -- has no second line beside the worn gear's, which is named for it.
        world.setIDs, world.setNames = { 21, 31 }, { [21] = "Cat", [31] = "Bear" }
        world.setForSpec = { [2] = 21, [3] = 31 }
        world.locationData[9012] = { isPlayer = true, slot = 12 }
        world.setLocations[31] = { [11] = 9011, [12] = 9012 }
        world.setWorn = { [31] = { 10, 10 } }
        info = Info(world, { GUARDIAN }, {}, 940014)
        Equal(Beside(beside2, ring2), Line("8ec3e6", 134400, "Bear", "+25% upgrade", true),
            "replacing: the played spec's own set has the one line, the worn gear's, named for it")
        world.setForSpec, world.setLocations[31], world.setWorn = { [2] = 21 }, nil, nil
        -- A set with no spec is the one worn: the worn gear has no line of the addon's, and
        -- no other set is the one on.
        world.setIDs, world.setNames, world.setWorn = { 21, 41 }, { [21] = "Cat", [41] = "Arena" }, { [41] = { 10, 10 } }
        info = Info(world, { GUARDIAN }, {}, 940014)
        Equal(Beside(beside2, ring2), "", "replacing: nothing for what is worn while a set with no spec is the one on")
        Equal(Beside(beside1, ring1), "", "replacing: nor for another spec's set that has the ring: it is not the one on either")
        -- Another spec's set is the one worn: it is the loadout that is on, and has its line
        -- beside the worn ring it has, where the arrows for other gear are asked for.
        world.setIDs, world.setNames, world.setWorn = { 21 }, { [21] = "Cat" }, { [21] = { 10, 10 } }
        info = Info(world, { GUARDIAN }, {}, 940014)
        Equal(Beside(beside1, ring1), Line("8ec3e6", 134400, "Cat", "+50% upgrade"),
            "replacing: another spec's set that is the one on has its line, in red")
        Equal(Beside(beside2, ring2), "", "replacing: and none beside the worn ring it does not have")
        world.itemSpecs = { 103 }
        Equal(Beside(beside1, ring1), "", "replacing: nor for a piece the client does not list for that set's spec")
        world.itemSpecs = nil
        icon.ShowOtherSpecUpgrades = false
        info = Info(world, { GUARDIAN }, {}, 940014)
        Equal(Beside(beside1, ring1), "", "replacing: nor any with the arrows for other gear off")
        icon.ShowOtherSpecUpgrades = true
        world.setIDs, world.setNames, world.setWorn = { 21 }, { [21] = "Cat" }, nil
        info = Info(world, { GUARDIAN }, {}, 940014)
        Equal(Beside(beside2, ring2), Line("8ec3e6", nil, "Guardian", "+25% upgrade", true),
            "replacing: a tooltip the addon had nothing for is asked anew when the client builds it again")
        -- The line's setting off: nothing.
        world.env.CaerdonWardrobeConfig.Tooltip.ShowLoadoutUpgrades = false
        Equal(Beside(beside2, ring2), "", "replacing: nothing with the line's setting off")
        world.env.CaerdonWardrobeConfig.Tooltip.ShowLoadoutUpgrades = true
        -- The piece looked at goes in another slot than the worn piece shown, or is that piece.
        Equal(Beside(beside2, ring2, world.env.CaerdonItem:CreateFromItemID(940001)), "", "replacing: nothing where the worn piece shown is not in a slot the piece would take")
        Equal(Beside(beside2, ring2, ring2), "", "replacing: nothing for the worn piece against itself")
        -- A piece the client lists for other specs than the toon's loot spec: what is worn is
        -- asked all the same. A gain is in red and says whose gear the piece is; a loss says
        -- no more than a loss does.
        world.itemSpecs = { 102 }
        Equal(Beside(beside2, ring2), Line("8ec3e6", nil, "Guardian", "+25% upgrade") .. "  |cff808080(Feral gear)|r",
            "replacing: gear for another loot spec has the worn gear's line in red, with whose gear it is")
        Equal(Beside(beside1, ring1), Loss("8ec3e6", nil, "Guardian", "-25%"), "replacing: and its loss is a loss like any other")
        world.itemSpecs = nil
        -- A list of pieces of one kind (the auction house's listings of an item): the gain is
        -- the one over the worn piece the piece gains most over, here the weaker ring.
        local YELLOW_ARROW = "|TInterface\\Buttons\\JumpUpArrow:0:0:0:0:32:32:0:32:0:32:255:255:0|t|cffffff00"
        local RED_ARROW = "|TInterface\\Buttons\\JumpUpArrow:0:0:0:0:32:32:0:32:0:32:255:89:89|t|cffff5959"
        local equipment = world.env.CaerdonEquipment
        local best = equipment:GetBestReplacementGain(looked)
        Check(best ~= nil and best.percent == 25 and best.upgrade == true and best.worn == true,
            "listing: the gain over the weaker of the two worn rings (" .. tostring(best and best.percent) .. ")")
        Equal(feature:GetShortGainText(best), YELLOW_ARROW .. "+25%|r", "listing: as the arrow and the percentage, in the arrow's colour")
        Equal(feature:GetShortGainText({ upgrade = false, percent = -25 }), nil, "listing: nothing for a piece that is no upgrade")
        world.itemSpecs = { 102 }
        Equal(feature:GetShortGainText(equipment:GetBestReplacementGain(looked)), RED_ARROW .. "+25%|r",
            "listing: in red for gear of another loot spec")
        world.itemSpecs = nil
        local none, noneWhy = equipment:GetBestReplacementGain(world.env.CaerdonItem:CreateFromItemID(940001))
        Check(none == nil and type(noneWhy) == "string", "listing: nothing, and why, for a piece the scale has no gain for (" .. tostring(noneWhy) .. ")")
        Equal(select(2, equipment:GetBestReplacementGain(world.env.CaerdonItem:CreateFromItemID(940021))),
            "nothing is worn where the piece would go", "listing: and for a piece with nothing worn in its slot")

        -- The auction feature's rows for those listings, and the page's button. The band put
        -- aside is worth 24 on Guardian's scale for this: twice the weaker worn ring.
        do
            world.scaleValues[GUARDIAN][940012] = 24
            PawnChanged(world)
            info = Info(world, { GUARDIAN }, {}, 940014)
            world.client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "features/Auction.lua", world.namespace)
            local core = world.env.CaerdonWardrobe
            local auction = core:GetFeature("Auction")
            local big = world.client:NewFrame("Button")
            local key = { itemID = 940014, itemLevel = 190, itemSuffix = 0 }
            local rows = {
                { auctionID = 1, itemKey = key, itemLink = world.game.Link(940001) },
                { auctionID = 2, itemKey = key, itemLink = world.game.Link(940014) },
                { auctionID = 3, itemKey = key, itemLink = world.game.Link(940012) },
                { auctionID = 4, itemKey = key },
            }
            local frames = {}
            local list = { tableBuilder = { GetDataProviderData = function(_, index) return rows[index] end },
                IsVisible = function() return true end }
            list.ScrollBox = { ForEachFrame = function(_, each)
                for index, frame in ipairs(frames) do each(frame, index) end
            end }
            rawset(world.env, "AuctionHouseFrame", { ItemBuyFrame = { ItemDisplay = { ItemButton = big }, ItemList = list } })
            -- A row as the table builder hands it to the feature: its cells made and filled
            -- from the row's data, the addon's own first.
            local cellMixin = world.env.CaerdonAuctionCellMixin
            local function Cell(row, index)
                local cell = world.client:NewFrame("Frame", nil, row)
                cell.Text = cell:CreateFontString()
                for key, value in pairs(cellMixin) do
                    cell[key] = value
                end
                cell:Init(nil, auction, "listing")
                cell:Populate(rows[index], 1)
                return cell
            end
            local function Shown(cell)
                local text = cell.Text:GetText()
                return text ~= nil and text ~= "" and text or nil
            end
            local function Row(index)
                local row = frames[index] or world.client:NewFrame("Button")
                frames[index] = row
                row.cells = { Cell(row, index) }
                for cell = 2, 6 do
                    row.cells[cell] = world.client:NewFrame("Frame", nil, row)
                end
                auction:OnItemBuyInitializedFrame(list, row, index)
                world.client:Tick(4)
                return Shown(row.cells[1])
            end
            -- What the page's button is asked for with: the core's drawing is not this
            -- scenario's, so the request is taken where it is made.
            local askedOfBig = nil
            function core:UpdateButton(button, item)
                if button == big then
                    askedOfBig = item
                end
            end
            local function Big()
                return askedOfBig and askedOfBig:GetItemLink() or nil
            end
            Equal(Row(1), nil, "rows: no percentage on a listing that gains nothing")
            Equal(Big(), world.game.Link(940001), "rows: the page's button is the first listing while none is an upgrade")
            Equal(Row(2), YELLOW_ARROW .. "+25%|r", "rows: the percentage of a listing that is an upgrade")
            Equal(Big(), world.game.Link(940014), "rows: and the page's button is that listing, so it has the arrow")
            Equal(Row(3), YELLOW_ARROW .. "+100%|r", "rows: each listing has its own")
            Equal(Big(), world.game.Link(940012), "rows: the page's button is the listing that gains most")
            Equal(Row(2), YELLOW_ARROW .. "+25%|r", "rows: a row filled again has its percentage again")
            -- A cell the builder fills for a listing already looked at has its text at once,
            -- from what the feature keeps for the page; one for a listing not yet looked at
            -- has none.
            Equal(Shown(Cell(frames[2], 3)), YELLOW_ARROW .. "+100%|r", "rows: a cell handed to another row fills itself from what is kept")
            Equal(Shown(Cell(frames[2], 1)), nil, "rows: and is empty for a listing that gains nothing")
            local reused = Cell(frames[2], 3)
            reused:Populate(rows[1], 1)
            Equal(Shown(reused), nil, "rows: a cell handed on to a listing that gains nothing loses the last one's text")
            -- A cell of the results' column is only room for what the core draws on the row.
            local room = world.client:NewFrame("Frame")
            room.Text = room:CreateFontString()
            for key, value in pairs(cellMixin) do
                room[key] = value
            end
            room:Init(nil, auction, "results")
            room:Populate(rows[3], 1)
            Equal(Shown(room), nil, "rows: a cell of the results' column has no text of a listing's")
            Equal(auction:GetListingText({ auctionID = 999 }), nil, "rows: nothing is kept for a listing not seen")
            cellMixin.OnLineEnter(frames[2].cells[1])
            cellMixin.OnLineLeave(frames[2].cells[1])
            Equal(Big(), world.game.Link(940012), "rows: and a lesser listing does not take the button back")
            -- A row handed a listing with no link yet loses its text.
            frames[5] = frames[3]
            rows[5] = rows[4]
            Equal(Row(5), nil, "rows: a row handed a listing without a link has no percentage left")
            frames[5], rows[5] = nil, nil
            -- A refresh walks the listings on screen, and the button is found again.
            Row(3)
            auction.listingPage.shownLink = "stale"
            auction:Refresh()
            world.client:Tick(4)
            Equal(Shown(frames[3].cells[1]), YELLOW_ARROW .. "+100%|r", "rows: a refresh draws the percentages again")
            Equal(auction.listingPage.shownLink, world.game.Link(940012), "rows: and names the best listing for the button again")
            -- The upgrade arrow switched off: no percentages.
            icon.ShowUpgradeIcon = false
            Equal(Row(2), nil, "rows: none with the upgrade arrow switched off")
            icon.ShowUpgradeIcon = true
            -- Another item's listings start the page anew.
            rows[6] = { auctionID = 6, itemKey = { itemID = 940001, itemLevel = 200, itemSuffix = 0 }, itemLink = world.game.Link(940001) }
            Row(6)
            Equal(Big(), world.game.Link(940001), "rows: a listing of another item key starts the page anew")

            -- The columns themselves: the client's layout, and the addon's put first, in the
            -- order named, each headed by an icon.
            local function Builder()
                local columns = { "price", "name" }
                local builder = { columns = columns, GetColumns = function() return columns end }
                function builder:AddUnsortableFixedWidthColumn(owner, padding, width, leftPadding, rightPadding, header, template, feature, kind)
                    local column = { owner = owner, width = width, header = header, template = template, feature = feature, kind = kind }
                    columns[#columns + 1] = column
                    return column
                end
                return builder
            end
            local function Kinds(columns)
                local kinds = {}
                for index, column in ipairs(columns) do
                    kinds[index] = type(column) == "table" and column.kind or column
                end
                return table.concat(kinds, " ")
            end
            local STAR = "|TInterface\\Store\\category-icon-featured:14:14:0:0:64:64:16:48:16:48|t"
            local ARROW = "|TInterface\\Buttons\\JumpUpArrow:14:14:0:0:32:32:0:32:0:32:102:255:51|t"
            local laidOut = 0
            local builder = Builder()
            auction:WithColumns(function() laidOut = laidOut + 1 end, "the page", { "icon", "results" })(builder)
            Equal(laidOut, 1, "column: the client's own columns are laid out")
            Equal(Kinds(builder.columns), "icon results price name", "column: the addon's columns come first, in their order")
            local first, second = builder.columns[1], builder.columns[2]
            Check(first.template == "CaerdonAuctionCellTemplate" and first.feature == auction and first.owner == "the page",
                "column: with the addon's own template for their cells")
            Check(first.header == STAR and first.width == 24, "column: the icon's column is narrow and headed by the star (" .. tostring(first.header) .. ")")
            Check(second.header == ARROW and second.width == 44, "column: the gain's is headed by the arrow (" .. tostring(second.header) .. ")")
            builder = Builder()
            auction:WithColumns(function() end, "the page", { "listing" })(builder)
            Check(Kinds(builder.columns) == "listing price name" and builder.columns[1].header == ARROW and builder.columns[1].width == 56,
                "column: an item's page has the one, headed by the arrow")

            -- An item's page has the column for a piece of equipment alone, and with the
            -- upgrade arrow on.
            local base = function() end
            rawset(world.env, "AuctionHouseTableBuilder", { GetItemBuyListLayout = function() return base end })
            local pageList = {}
            function pageList:SetTableBuilderLayout(layoutFunction) self.layout = layoutFunction end
            local page = { ItemList = pageList }
            auction.listingColumn = nil
            auction:OnItemBuySetItemKey(page, { itemID = 940014, itemLevel = 190, itemSuffix = 0 })
            Check(type(pageList.layout) == "function" and pageList.layout ~= base, "column: an item's page gets the column for a piece of equipment")
            local withColumn = pageList.layout
            auction:OnItemBuySetItemKey(page, { itemID = 940011, itemLevel = 190, itemSuffix = 0 })
            Check(pageList.layout == withColumn, "column: and keeps its layout for the next piece of equipment")
            auction:OnItemBuySetItemKey(page, { itemID = 123456789, itemLevel = 0, itemSuffix = 0 })
            Check(pageList.layout == base, "column: the client's own layout for an item that is no equipment")
            icon.ShowUpgradeIcon = false
            auction:OnItemBuySetItemKey(page, { itemID = 940014, itemLevel = 190, itemSuffix = 0 })
            Check(pageList.layout == base, "column: and for equipment with the upgrade arrow switched off")
            icon.ShowUpgradeIcon = true
            -- Nor with the column's own switch off.
            world.env.CaerdonWardrobeConfig.Auction.UpgradeColumn = false
            auction.listingColumn = true
            auction:OnItemBuySetItemKey(page, { itemID = 940014, itemLevel = 190, itemSuffix = 0 })
            Check(pageList.layout == base, "column: nor with the upgrade column switched off")
            world.env.CaerdonWardrobeConfig.Auction.UpgradeColumn = true
            -- Nor for gear the toon would not wear: the scale has no value for it.
            Equal(equipment:CanScorePieceForWorn(940014), true, "column: a piece of the band could be scored")
            Equal(equipment:CanScorePieceForWorn(940021), false, "column: a piece of the staff the scale has no value for could not")
            Equal(equipment:CanScorePieceForWorn(123456789), false, "column: nor a thing that is no piece for a slot")
            auction.listingColumn = true
            auction:OnItemBuySetItemKey(page, { itemID = 940021, itemLevel = 190, itemSuffix = 0 })
            Check(pageList.layout == base, "column: an item's page has the client's own layout for gear the toon would not wear")
            -- Nor where no piece can be scored (no Pawn, no specs): nothing would fill it.
            Equal(equipment:CanScoreWornGear(), true, "column: here a piece can be scored")
            local canScore = equipment.CanScoreWornGear
            equipment.CanScoreWornGear = function() return false end
            auction.listingColumn = nil
            pageList.layout = nil
            auction:OnItemBuySetItemKey(page, { itemID = 940014, itemLevel = 190, itemSuffix = 0 })
            Check(pageList.layout == nil, "column: an item's page is left as it is where no piece can be scored")
            equipment.CanScoreWornGear = canScore
            rawset(world.env, "AuctionHouseTableBuilder", nil)

            -- The list of results always has the icon's column, and the gain's while a gear
            -- category is selected.
            local selected = 2
            rawset(world.env, "AuctionCategories", { { name = world.env.AUCTION_CATEGORY_WEAPONS },
                { name = world.env.AUCTION_CATEGORY_ARMOR }, { name = "Recipes" } })
            world.env.AuctionHouseFrame.GetCategoriesList = function()
                return { GetSelectedCategory = function() return selected end }
            end
            local resultsList = { tableBuilderLayoutFunction = base }
            function resultsList:SetTableBuilderLayout(layoutFunction) self.tableBuilderLayoutFunction = layoutFunction end
            local results = { ItemList = resultsList }
            local function Results()
                auction:OnBrowseSetupTableBuilder(results)
                local made = Builder()
                resultsList.tableBuilderLayoutFunction(made)
                return Kinds(made.columns)
            end
            Equal(Results(), "icon results price name", "column: the results have both columns while armor is the category")
            Check(auction.resultsKinds == "icon results" and auction.resultsUpgradeLeft == 26,
                "column: and the rows are told where the upgrade's column begins (" .. tostring(auction.resultsUpgradeLeft) .. ")")
            selected = 1
            Equal(Results(), "icon results price name", "column: and for weapons; the addon's own layout is not wrapped a second time")
            selected = 3
            Equal(Results(), "icon price name", "column: the icon's alone for another category")
            Check(auction.resultsKinds == "icon" and auction.resultsUpgradeLeft == nil, "column: the upgrade then has no column to go in")
            selected = nil
            Equal(Results(), "icon price name", "column: and with no category selected")
            selected = 2
            icon.ShowUpgradeIcon = false
            Equal(Results(), "icon price name", "column: no gain column with the upgrade arrow switched off")
            icon.ShowUpgradeIcon = true
            -- The client gives the list a layout of its own again: wrapped anew.
            resultsList.tableBuilderLayoutFunction = base
            Equal(Results(), "icon results price name", "column: a fresh layout of the client's gets the columns again")
            -- Each column has its switch. Without the icon's the icon lies on the price column,
            -- which follows the gain's column where that is there.
            local auctionConfig = world.env.CaerdonWardrobeConfig.Auction
            Check(type(auctionConfig) == "table" and auctionConfig.IconColumn == true and auctionConfig.UpgradeColumn == true,
                "column: both switches are on by default")
            auctionConfig.IconColumn = false
            Equal(Results(), "results price name", "column: the icon's column switched off, the gain's stays")
            Check(auction.resultsKinds == "results" and auction.resultsUpgradeLeft == 2,
                "column: the upgrade's column begins at the row's edge then (" .. tostring(auction.resultsUpgradeLeft) .. ")")
            auctionConfig.IconColumn, auctionConfig.UpgradeColumn = true, false
            Equal(Results(), "icon price name", "column: the gain's column switched off, the icon's stays")
            auctionConfig.IconColumn = false
            auction:OnBrowseSetupTableBuilder(results)
            Check(resultsList.tableBuilderLayoutFunction == base, "column: with both off the list has the client's own layout back")
            Check(auction.resultsKinds == "" and auction.resultsUpgradeLeft == nil, "column: and the rows are told that neither column is there")
            -- A refresh lays the list out anew only where the columns wanted have changed.
            Equal(auction:OnBrowseSetupTableBuilder(results, true), false, "column: a refresh with nothing changed leaves the list alone")
            auctionConfig.IconColumn = true
            Equal(auction:OnBrowseSetupTableBuilder(results, true), true, "column: a switch changed since is seen by a refresh")
            Equal(auction:OnBrowseSetupTableBuilder(results, true), false, "column: and only once")
            resultsList.tableBuilderLayoutFunction = base
            Equal(auction:OnBrowseSetupTableBuilder(results, true), true, "column: so is a layout of the client's own where columns are wanted")
            auctionConfig.IconColumn, auctionConfig.UpgradeColumn = true, true
            -- A category of one kind the toon does not wear has no gain column: asked of the
            -- first row the search found. Armor here is of several kinds; its second part, of
            -- one (class 4, subclass 4), and so are that part's own parts.
            local plate = { name = "Plate", filters = { { classID = 4, subClassID = 4 }, { classID = 4, subClassID = 4, inventoryType = 1 } },
                subCategories = { { name = "Head", filters = { { classID = 4, subClassID = 4, inventoryType = 1 } } } } }
            world.env.AuctionCategories[2].filters = { { classID = 4, subClassID = 2 }, { classID = 4, subClassID = 4 } }
            world.env.AuctionCategories[2].subCategories = { { name = "Leather", filters = { { classID = 4, subClassID = 2 } } }, plate }
            local subSelected, subSubSelected = nil, nil
            world.env.AuctionHouseFrame.GetCategoriesList = function()
                return { GetSelectedCategory = function() return selected, subSelected, subSubSelected end }
            end
            local browse, worn, asked = { { itemKey = { itemID = 940014 } } }, false, {}
            rawset(world.env, "C_AuctionHouse", { GetBrowseResults = function() return browse end })
            local isKindWorn, instant = equipment.IsKindWorn, world.env.C_Item.GetItemInfoInstant
            equipment.IsKindWorn = function(_, itemID)
                asked[#asked + 1] = itemID
                return worn
            end
            local firstKind = { 4, 4 }
            world.env.C_Item.GetItemInfoInstant = function(itemID)
                return itemID, "Armor", "Plate", "INVTYPE_FINGER", 1, firstKind[1], firstKind[2]
            end
            selected, subSelected = 2, nil
            firstKind = { 4, 2 }
            Equal(Results(), "icon results price name", "worn: all armor is of several kinds, and has the gain column")
            Equal(#asked, 0, "worn: no row is asked for that, though the first is of the first kind named")
            firstKind = { 4, 4 }
            subSelected = 2
            Equal(Results(), "icon price name", "worn: a part of one kind the toon does not wear has none")
            Equal(asked[1], 940014, "worn: the first row found is what was asked")
            subSubSelected = 1
            Equal(Results(), "icon price name", "worn: nor has a part of that part")
            worn = true
            Equal(Results(), "icon results price name", "worn: a part of one kind the toon wears has it")
            worn = false
            firstKind = { 4, 2 }
            Equal(Results(), "icon results price name", "worn: results still of another kind (an earlier search) decide nothing")
            firstKind = { 4, 4 }
            browse = {}
            Equal(Results(), "icon results price name", "worn: nor does a search that found nothing")
            browse = { { itemKey = { itemID = 940014 } } }
            subSelected, subSubSelected = 1, nil
            asked = {}
            firstKind = { 4, 2 }
            worn = true
            Equal(Results(), "icon results price name", "worn: the part the toon wears has the column")
            equipment.IsKindWorn, world.env.C_Item.GetItemInfoInstant = isKindWorn, instant

            -- Whether a kind is worn, asked of an item: by the equip slot line of its tooltip,
            -- and not armor of a lower class than what is worn in its slot.
            local EQUIP_SLOT = world.env.Enum.TooltipDataLineType.EquipSlot
            local slotLine = { type = EQUIP_SLOT }
            local tooltipByID = world.env.C_TooltipInfo.GetItemByID
            local hasTooltip = true
            world.env.C_TooltipInfo.GetItemByID = function()
                return hasTooltip and { lines = { { type = 0, isValidItemType = false }, slotLine } } or nil
            end
            slotLine.isValidItemType = true
            Equal(equipment:IsKindWorn(940014), true, "kind: a type the client does not mark is worn")
            slotLine.isValidItemType = false
            Equal(equipment:IsKindWorn(940014), false, "kind: a type the client marks as one the toon cannot use is not")
            slotLine.isValidItemType = nil
            slotLine.rightColor = { GetRGB = function() return 1, 0.125, 0.125 end }
            Equal(equipment:IsKindWorn(940014), false, "kind: without the field, a type in red is not worn")
            slotLine.rightColor = { GetRGB = function() return 1, 1, 1 end }
            Equal(equipment:IsKindWorn(940014), true, "kind: and one in white is")
            hasTooltip = false
            Equal(equipment:IsKindWorn(940014), true, "kind: an item with no tooltip yet counts as worn")
            Equal(equipment:IsKindWorn(123456789), true, "kind: so does one the client knows nothing of")
            hasTooltip = true
            -- Armor of a lower class than the piece worn in its slot: cloth (1) for a chest
            -- slot that has leather (2) on.
            slotLine.rightColor = nil
            world.worn[5] = 940002
            local function Kind(reference)
                local id = tonumber(reference) or tonumber(tostring(reference):match("item:(%d+)"))
                return id, id == 940002 and 2 or 1
            end
            world.env.C_Item.GetItemInfoInstant = function(reference)
                local id, subClassID = Kind(reference)
                return id, "Armor", "x", "INVTYPE_CHEST", 1, 4, subClassID
            end
            local itemInfo = world.env.C_Item.GetItemInfo
            world.env.C_Item.GetItemInfo = function(reference)
                local _, subClassID = Kind(reference)
                local name, link = itemInfo(reference)
                return name, link, 3, 200, 80, "Armor", "x", 1, "INVTYPE_CHEST", 1, 1, 4, subClassID
            end
            info = Info(world, { GUARDIAN }, {}, 940014)
            -- Such armor is Pawn's to refuse: it does where the client has armor
            -- specializations (retail), and takes it where there are none (the classic rules,
            -- which Pawn gives WoW Forever). Without Pawn item level alone never calls it a gain.
            local pawnData, bestType, pawnArrow = world.env.PawnGetItemData, world.env.PawnIsArmorBestTypeForPlayer,
                world.env.PawnShouldItemLinkHaveUpgradeArrowUnbudgeted
            local pawnHasRead, pawnTakes = true, false
            rawset(world.env, "PawnGetItemData", function(link)
                return pawnHasRead and { Link = link, UnenchantedStats = {} } or { Link = link }
            end)
            rawset(world.env, "PawnIsArmorBestTypeForPlayer", function() return pawnTakes end)
            Equal(equipment:IsKindWorn(940001), false, "kind: armor of a lower class than what is worn, which Pawn refuses, is not worn")
            Equal(equipment:IsKindWorn(940002), true, "kind: armor of the class that is worn is, whatever Pawn says of the type")
            pawnTakes = true
            Equal(equipment:IsKindWorn(940001), true, "kind: armor of a lower class is worn where Pawn takes it for the class")
            pawnTakes, pawnHasRead = false, false
            Equal(equipment:IsKindWorn(940001), true, "kind: and counts as worn while Pawn has not read the item")
            pawnHasRead = true
            -- A global that is not there: false, since a name set to nothing is the client's again.
            rawset(world.env, "PawnIsArmorBestTypeForPlayer", false)
            Equal(equipment:IsKindWorn(940001), true, "kind: a Pawn with no rule for armor types takes it")
            rawset(world.env, "PawnIsArmorBestTypeForPlayer", function() return true end)
            rawset(world.env, "PawnShouldItemLinkHaveUpgradeArrowUnbudgeted", false)
            Equal(equipment:IsKindWorn(940001), false, "kind: without Pawn a lower class is not worn: item level alone never calls it a gain")
            rawset(world.env, "PawnGetItemData", pawnData)
            rawset(world.env, "PawnIsArmorBestTypeForPlayer", bestType)
            rawset(world.env, "PawnShouldItemLinkHaveUpgradeArrowUnbudgeted", pawnArrow)
            world.env.C_Item.GetItemInfoInstant, world.env.C_Item.GetItemInfo = instant, itemInfo
            world.env.C_TooltipInfo.GetItemByID = tooltipByID

            -- A piece with no look (the band) has no source to say whether the toon can use
            -- it: the equip slot line of its tooltip does. A type the client refuses is no
            -- upgrade and has no level gain, whatever Pawn says and whatever its level.
            local byLink = world.env.C_TooltipInfo.GetHyperlink
            local typeLine = { type = EQUIP_SLOT, isValidItemType = true }
            world.env.C_TooltipInfo.GetHyperlink = function(link)
                local data = byLink(link)
                local lines = { typeLine }
                for _, line in ipairs(type(data) == "table" and data.lines or {}) do lines[#lines + 1] = line end
                return { type = 0, lines = lines }
            end
            info = Info(world, { GUARDIAN }, { GUARDIAN }, 940014)
            Equal(info.isTransmog, false, "type: the band has no look")
            Equal(info.isUpgrade, true, "type: a piece with no look whose type the client accepts is the upgrade Pawn says it is")
            Equal(info.canEquipForPlayer, true, "type: and one the toon can use")
            Equal(info.typeRefused, nil, "type: and its type is not said to be refused")
            typeLine.isValidItemType = false
            info = Info(world, { GUARDIAN }, { GUARDIAN }, 940014)
            Equal(info.typeRefused, true, "type: a type the client refuses is said to be")
            Equal(info.isUpgrade, nil, "type: a type the client refuses is no upgrade (another class's relic)")
            Equal(info.canEquipForPlayer, false, "type: the toon cannot use it")
            Equal(info.upgradeItemLevelDelta, nil, "type: and it has no level gain")
            typeLine.isValidItemType = nil
            typeLine.rightColor = { GetRGB = function() return 1, 0.125, 0.125 end }
            info = Info(world, { GUARDIAN }, { GUARDIAN }, 940014)
            Equal(info.isUpgrade, nil, "type: so with the type in red, where the client has no field for it")
            typeLine.rightColor = { GetRGB = function() return 1, 1, 1 end }
            info = Info(world, { GUARDIAN }, { GUARDIAN }, 940014)
            Equal(info.isUpgrade, true, "type: and a type in white is the toon's")
            -- With its level not reached either, a piece of the toon's type is one for later,
            -- and one of a type the client refuses is not: no level makes it the toon's.
            local function StatusOf(itemID)
                world.env.CaerdonWardrobe:RefreshItems("test")
                local item = world.env.CaerdonItem:CreateFromItemID(itemID)
                local ready, status
                world.client:TickUntil(function()
                    ready, status = item:GetCaerdonStatus()
                    return ready
                end, 10)
                return ready and tostring(status) or "<not ready>"
            end
            rawset(world.env, "UnitLevel", function() return 1 end)
            world.visible, world.upgradeFor = { [GUARDIAN] = true }, {}
            typeLine.isValidItemType, typeLine.rightColor = true, nil
            local laterStatus = StatusOf(940014)
            Check(laterStatus == "lowSkill" or laterStatus == "upgradeLowSkill",
                "type: a piece of the toon's type, of a level to come, is one for later (" .. laterStatus .. ")")
            typeLine.isValidItemType = false
            local refusedStatus = StatusOf(940014)
            Check(refusedStatus ~= "lowSkill" and refusedStatus ~= "upgradeLowSkill" and refusedStatus ~= "upgrade" and
                refusedStatus ~= "<not ready>", "type: one of a type the client refuses is not (" .. refusedStatus .. ")")
            rawset(world.env, "UnitLevel", nil)
            world.env.C_TooltipInfo.GetHyperlink = byLink
            info = Info(world, { GUARDIAN }, {}, 940014)
            info = Info(world, { GUARDIAN }, {}, 940014)
            rawset(world.env, "C_AuctionHouse", nil)
            subSelected = nil

            -- A list with no layout is left alone.
            Equal(auction:OnBrowseSetupTableBuilder({ ItemList = {} }), false, "column: nothing for a list with no layout")
            Check(auction.resultsKinds == nil and auction.resultsUpgradeLeft == nil, "column: and the rows fall back")

            -- A row of the results is two parts, one for each column, and each is there only
            -- with its column: nothing of the addon's is put on the client's own columns.
            local asked, cleared = {}, {}
            function core:UpdateButton(button, item, feature, locationInfo, options)
                asked[button], cleared[button] = { item = item, feature = feature, locationInfo = locationInfo, options = options }, nil
            end
            function core:ClearButton(button)
                asked[button], cleared[button] = nil, true
            end
            local rowItem = world.env.CaerdonItem:CreateFromItemID(940014)
            local rowKey = { itemID = 940014, itemLevel = 190, itemSuffix = 0 }
            local resultRow = world.client:NewFrame("Button")
            auction.resultsKinds, auction.resultsUpgradeLeft = "icon results", 26
            auction:AskResultsRow(resultRow, rowItem, "key", rowKey)
            local upgradePart = resultRow.caerdonUpgradeFrame
            Check(asked[resultRow] ~= nil and asked[resultRow].item == rowItem and asked[resultRow].feature == auction and
                asked[resultRow].locationInfo.auctionPart == "icon" and asked[resultRow].locationInfo.locationKey == "key" and
                asked[resultRow].locationInfo.itemKey == rowKey and asked[resultRow].options.statusOffsetX == 12,
                "parts: the row is asked for as the icon's part, the icon in the middle of its column")
            Check(upgradePart ~= nil and asked[upgradePart] ~= nil and asked[upgradePart].item == rowItem and
                asked[upgradePart].locationInfo.auctionPart == "upgrade" and asked[upgradePart].locationInfo.locationKey == "key-upgrade" and
                asked[upgradePart].locationInfo.itemKey == rowKey and asked[upgradePart].options.fixedLayout == true,
                "parts: a frame of the row's own is asked for as the upgrade's part, under a key of its own")
            -- What each part shows: the icon's nothing of the upgrade, the upgrade's that alone.
            local iconInfo = auction:GetDisplayInfo(resultRow, rowItem, auction, asked[resultRow].locationInfo, {})
            Check(iconInfo.upgradeIcon.shouldShow == false and iconInfo.levelGain.shouldShow == false and iconInfo.statusIcon == nil,
                "parts: the icon's part has no arrow and no level gain")
            local upgradeInfo = auction:GetDisplayInfo(upgradePart, rowItem, auction, asked[upgradePart].locationInfo, {})
            Check(upgradeInfo.statusIcon.shouldShow == false and upgradeInfo.upgradeIcon == nil and upgradeInfo.levelGain == nil,
                "parts: the upgrade's part has the upgrade alone")
            local otherInfo = auction:GetDisplayInfo(big, rowItem, auction, { locationKey = "elsewhere" }, {})
            Check(otherInfo.statusIcon == nil and otherInfo.upgradeIcon == nil and otherInfo.levelGain == nil,
                "parts: a button that is no row of the results is as it was")
            -- No upgrade column (another category, a search across everything, gear not worn,
            -- its switch): no arrow and no gain anywhere on the row.
            auction.resultsKinds, auction.resultsUpgradeLeft = "icon", nil
            auction:AskResultsRow(resultRow, rowItem, "key", rowKey)
            Check(asked[resultRow] ~= nil and cleared[upgradePart] == true and asked[upgradePart] == nil,
                "parts: without the upgrade's column its part is cleared, and the icon's stays")
            -- The icon's column switched off: no icon of the addon's on the row.
            auctionConfig.IconColumn = false
            auction.resultsKinds, auction.resultsUpgradeLeft = "results", 2
            auction:AskResultsRow(resultRow, rowItem, "key", rowKey)
            Check(cleared[resultRow] == true and asked[resultRow] == nil and asked[upgradePart] ~= nil,
                "parts: without the icon's column the row has no icon, and the upgrade's part stays")
            auction.resultsKinds, auction.resultsUpgradeLeft = "", nil
            auction:AskResultsRow(resultRow, rowItem, "key", rowKey)
            Check(cleared[resultRow] == true and cleared[upgradePart] == true, "parts: with neither column the row has nothing of the addon's")
            -- Nor before the feature has laid the list out, with the switch off.
            auction.resultsKinds = nil
            auction:AskResultsRow(resultRow, rowItem, "key", rowKey)
            Check(cleared[resultRow] == true, "parts: the icon's switch holds before the list is laid out too")
            auctionConfig.IconColumn = true
            -- The switch on again and the list not laid out anew yet: no icon where the list
            -- has no column for it.
            auction.resultsKinds, auction.resultsUpgradeLeft = "results", 2
            auction:AskResultsRow(resultRow, rowItem, "key", rowKey)
            Check(cleared[resultRow] == true and asked[resultRow] == nil, "parts: no icon while the list has no column for it")
            auction.resultsKinds, auction.resultsUpgradeLeft = nil, nil
            -- With it on and no layout of the feature's yet, the icon is where it was before
            -- the columns, and there is no upgrade part.
            local early = world.client:NewFrame("Button")
            auction:AskResultsRow(early, rowItem, "key", rowKey)
            Check(asked[early] ~= nil and asked[early].options.statusOffsetX == 7 and early.caerdonUpgradeFrame == nil,
                "parts: before the list is laid out the icon is where it was, and nothing else")
            -- A pet has no upgrade part.
            auction.resultsKinds, auction.resultsUpgradeLeft = "icon results", 26
            auction:AskResultsRow(resultRow, rowItem, "pet", rowKey, true)
            Check(asked[resultRow] ~= nil and cleared[upgradePart] == true, "parts: a pet's row has the icon's part alone")
            -- A row the feature clears loses both parts.
            auction:AskResultsRow(resultRow, rowItem, "key", rowKey)
            auction:ClearResultsRow(resultRow)
            Check(cleared[resultRow] == true and cleared[upgradePart] == true, "parts: a row that is cleared loses both")
            auction:ClearResultsRow(early)
            Check(cleared[early] == true, "parts: and one with no upgrade part its one")

            -- The player's own settings can leave the upgrade's column nothing to hold: the
            -- arrow of a higher item level switched off, and the level gain not shown. Pawn's
            -- arrow is then all there could be, and Pawn is asked only about a row whose link
            -- is the piece's own. The column is held back until such a row has been drawn.
            local hadItemLevel, hadGain = icon.ShowItemLevelUpgrades, icon.ShowUpgradeLevelDelta
            icon.ShowItemLevelUpgrades, icon.ShowUpgradeLevelDelta = true, false
            local ownKey = { itemID = 940014, itemLevel = 190, itemSuffix = 0 }
            local otherKey = { itemID = 940014, itemLevel = 260, itemSuffix = 0 }
            local found = { { itemKey = otherKey } }
            rawset(world.env, "C_AuctionHouse", { GetBrowseResults = function() return found end })
            resultsList.tableBuilderLayoutFunction = base
            Equal(equipment:CountsItemLevel(), true, "held: a higher item level counts as the settings come")
            Equal(Results(), "icon results price name", "held: and the results have the upgrade's column")
            Check(auction.resultsUpgradeHeldBack == false, "held: which is not held back")
            icon.ShowItemLevelUpgrades = false
            Equal(equipment:CountsItemLevel(), false, "held: switched off with Pawn there, it does not")
            Equal(Results(), "icon price name", "held: the column is left out while nothing could be in it")
            Check(auction.resultsUpgradeHeldBack == true and auction.resultsUpgradeLeft == nil,
                "held: it is held back, and the rows have no upgrade part")
            icon.ShowUpgradeLevelDelta = true
            Equal(Results(), "icon results price name", "held: the level gain, where it is shown, is something to hold")
            icon.ShowUpgradeLevelDelta = false
            Equal(Results(), "icon price name", "held: and not where it is not shown")
            -- A column that is refused (its switch, another category) is not held back.
            auctionConfig.UpgradeColumn = false
            Results()
            Check(auction.resultsUpgradeHeldBack == false, "held: a column that is switched off is not held back")
            auctionConfig.UpgradeColumn = true
            Results()
            Check(auction.resultsUpgradeHeldBack == true, "held: switched on again, it is")

            local ownItem = world.env.CaerdonItem:CreateFromItemID(940014)
            ownItem.extraData = { overrideItemLevel = 190 }
            local otherItem = world.env.CaerdonItem:CreateFromItemID(940014)
            otherItem.extraData = { overrideItemLevel = 260 }
            Equal(equipment:IsKnownByItsOwnLink(ownItem), true, "held: a row at its link's own level is known by its own link")
            Equal(equipment:IsKnownByItsOwnLink(otherItem), false, "held: one at another level is not")

            local hadBrowseFrame = world.env.AuctionHouseFrame.BrowseResultsFrame
            world.env.AuctionHouseFrame.BrowseResultsFrame = results
            local heldRow = world.client:NewFrame("Button")
            local layouts, reAsked = 0, 0
            local layOut, onInitialized = auction.LayOutResultsAnew, auction.OnInitializedFrame
            auction.LayOutResultsAnew = function(self) layouts = layouts + 1 return layOut(self) end
            auction.OnInitializedFrame = function() reAsked = reAsked + 1 end
            resultsList.ScrollBox = { ForEachFrame = function(_, each) each(heldRow, {}) end }
            resultsList.IsVisible = function() return true end
            -- A row at another level than its link's is not Pawn's to judge: it brings nothing.
            auction:AskResultsRow(heldRow, otherItem, "other", otherKey)
            world.client:Tick(1)
            Equal(layouts, 0, "held: a row known by another link owes no layout")
            Check(auction.resultsKinds == "icon" and auction.resultsUpgradeHeldBack == true, "held: and the column stays out")
            -- A pet's row has no upgrade part, and is not looked at.
            auction:AskResultsRow(heldRow, ownItem, "pet", { itemID = 940014, itemLevel = 190, itemSuffix = 9 }, true)
            world.client:Tick(1)
            Check(layouts == 0 and auction.rowsOfOwnLink["940014-190-9"] == nil, "held: a pet's row is not looked at")
            -- A row whose link is its own could have Pawn's arrow: the column comes, on the
            -- next frame, and the rows on screen are asked for again.
            found = { { itemKey = otherKey }, { itemKey = ownKey } }
            auction:AskResultsRow(heldRow, ownItem, "own", ownKey)
            Check(layouts == 0 and auction.resultsKinds == "icon", "held: nothing is laid out from inside a row's own drawing")
            world.client:Tick(1)
            Equal(layouts, 1, "held: a row whose link is its own owes a layout, on the next frame")
            Check(auction.resultsKinds == "icon results" and auction.resultsUpgradeHeldBack == false and auction.resultsUpgradeLeft == 26,
                "held: which brings the column")
            Equal(reAsked, 1, "held: and the rows on screen are asked for again")
            -- The row is remembered by its key: laid out again, the list keeps the column.
            Equal(Results(), "icon results price name", "held: the row is remembered, and the column stays")
            -- With the column there, rows are not looked at.
            auction:AskResultsRow(heldRow, ownItem, "own", { itemID = 940014, itemLevel = 190, itemSuffix = 11 })
            Check(auction.rowsOfOwnLink["940014-190-11"] == nil, "held: with the column there a row is not looked at")
            -- Other results, with no such row: the column is out again. A row known for its own
            -- link that the results do not name owes nothing when it is drawn.
            found = { { itemKey = otherKey } }
            Equal(Results(), "icon price name", "held: other results, with no such row, have no column")
            auction:AskResultsRow(heldRow, ownItem, "own", ownKey)
            world.client:Tick(1)
            Equal(layouts, 1, "held: a row already known owes no layout a second time")
            -- Results that name a row known for its own link have the column at once.
            found = { { itemKey = ownKey } }
            Equal(Results(), "icon results price name", "held: results with a row known for its own link have the column at once")
            -- Rows drawn in one frame owe one layout between them, and it is owed again later.
            found = { { itemKey = otherKey } }
            Results()
            local second = { itemID = 940014, itemLevel = 190, itemSuffix = 7 }
            local third = { itemID = 940014, itemLevel = 190, itemSuffix = 8 }
            found = { { itemKey = second }, { itemKey = third } }
            auction:AskResultsRow(heldRow, ownItem, "second", second)
            auction:AskResultsRow(heldRow, ownItem, "third", third)
            world.client:Tick(1)
            Equal(layouts, 2, "held: rows drawn in one frame owe one layout between them")
            Check(auction.resultsKinds == "icon results", "held: and the column is there again")
            world.client:Tick(1)
            Equal(layouts, 2, "held: nothing is owed after that")
            auction.LayOutResultsAnew, auction.OnInitializedFrame = layOut, onInitialized
            resultsList.ScrollBox, resultsList.IsVisible = nil, nil
            world.env.AuctionHouseFrame.BrowseResultsFrame = hadBrowseFrame
            auction.rowsOfOwnLink, auction.resultsUpgradeHeldBack = nil, nil
            icon.ShowItemLevelUpgrades, icon.ShowUpgradeLevelDelta = hadItemLevel, hadGain

            -- A row's key names a suffix: the item made for the row is told, with the name the
            -- auction house has for the key, by each way a row's item is made.
            local keyInfo = { itemName = "The Band of the Monkey" }
            rawset(world.env, "C_AuctionHouse", {
                GetItemKeyInfo = function() return keyInfo end,
                GetItemKeyRequiredLevel = function() return 0 end,
            })
            local suffixKey = { itemID = 940014, itemLevel = 190, itemSuffix = 12721, battlePetSpeciesID = 0 }
            local made = auction:MakeItemForKey(suffixKey)
            Check(made.extraData.overrideItemLevel == 190 and made.extraData.keySuffix == 12721 and
                made.extraData.keyName == "The Band of the Monkey",
                "suffix: an item made for a key is told the key's suffix and the name it has with it")
            made = auction:MakeItemForKey({ itemID = 940014, itemLevel = 190, itemSuffix = 0 })
            Check(made.extraData.keySuffix == nil and made.extraData.keyName == nil, "suffix: a key that names none says nothing of one")
            -- A row of the results, whose item is made from the link of the key's tooltip.
            local keyTooltip = world.env.C_TooltipInfo.GetItemKey
            world.env.C_TooltipInfo.GetItemKey = function() return { hyperlink = world.game.Link(940014) } end
            local suffixRow = world.client:NewFrame("Button")
            suffixRow.rowData = { itemKey = suffixKey }
            auction.resultsKinds, auction.resultsUpgradeLeft = "icon", nil
            auction:ProcessItemKeyInfo(suffixKey, keyInfo, suffixRow)
            world.client:TickUntil(function() return asked[suffixRow] ~= nil end, 10)
            local rowAsked = asked[suffixRow] and asked[suffixRow].item
            Check(rowAsked ~= nil and rowAsked.extraData.keySuffix == 12721 and
                rowAsked.extraData.keyName == "The Band of the Monkey" and rowAsked.extraData.overrideItemLevel == 190,
                "suffix: a row of the results is asked for with its key's suffix and name")
            Equal(rowAsked ~= nil and equipment:IsKnownByItsOwnLink(rowAsked), false, "suffix: and its link is not taken for the piece's")
            local plainRow = world.client:NewFrame("Button")
            plainRow.rowData = { itemKey = rowKey }
            auction:ProcessItemKeyInfo(rowKey, { itemName = "another name" }, plainRow)
            world.client:TickUntil(function() return asked[plainRow] ~= nil end, 10)
            Check(asked[plainRow] ~= nil and asked[plainRow].item.extraData.keySuffix == nil and
                asked[plainRow].item.extraData.keyName == nil, "suffix: a row whose key names none is asked for without one")
            world.env.C_TooltipInfo.GetItemKey = keyTooltip
            auction.resultsKinds, auction.resultsUpgradeLeft = nil, nil
            rawset(world.env, "C_AuctionHouse", nil)
            core.ClearButton = nil
            auction.resultsKinds, auction.resultsUpgradeLeft = nil, nil
            rawset(world.env, "AuctionCategories", nil)

            rawset(world.env, "AuctionHouseFrame", nil)
            core.UpdateButton = nil
            world.scaleValues[GUARDIAN][940012] = nil
            PawnChanged(world)
            info = Info(world, { GUARDIAN }, {}, 940014)
        end

        -- The tooltip of an auction row is filled by item key, and the link it shows is the
        -- plain item's (the band, of level 190): at another level nothing is scored off it.
        primary.info = { getterName = "GetItemKey", getterArgs = { 940014, 260, 0, 80 } }
        Equal(Beside(beside2, ring2), "", "replacing: nothing beside a tooltip filled by item key at another level than its link's")
        primary.info = { getterName = "GetItemKey", getterArgs = { 940014, 190, 0, 80 } }
        Equal(Beside(beside2, ring2), Line("8ec3e6", nil, "Guardian", "+25% upgrade", true),
            "replacing: the line where the key's level is the link's own")
        -- A key that names a suffix: the link the tooltip shows is the item's without it, by
        -- its name, and nothing is scored off it. A link of the key's own name is the piece.
        local ringName = world.env.C_Item.GetItemInfo(world.game.Link(940014))
        local keyNamed = tostring(ringName) .. " of the Monkey"
        rawset(world.env, "C_AuctionHouse", { GetItemKeyInfo = function(key)
            return key.itemID == 940014 and key.itemLevel == 190 and key.itemSuffix == 12721 and { itemName = keyNamed } or nil
        end })
        primary.info = { getterName = "GetItemKey", getterArgs = { 940014, 190, 12721, 80 } }
        Equal(Beside(beside2, ring2), "", "replacing: nothing beside a tooltip filled by a key with a suffix its link does not carry")
        keyNamed = ringName
        Equal(Beside(beside2, ring2), Line("8ec3e6", nil, "Guardian", "+25% upgrade", true),
            "replacing: the line where the link has the name the key has")
        rawset(world.env, "C_AuctionHouse", nil)
        Equal(Beside(beside2, ring2), "", "replacing: nothing while the name the key has is not known")
        local keyAsks = 0
        rawset(world.env, "C_AuctionHouse", { GetItemKeyInfo = function()
            keyAsks = keyAsks + 1
            return { itemName = "another name" }
        end })
        primary.info = { getterName = "GetItemKey", getterArgs = { 940014, 190, 0, 80 } }
        Equal(Beside(beside2, ring2), Line("8ec3e6", nil, "Guardian", "+25% upgrade", true),
            "replacing: the line again for a key that names no suffix")
        Equal(keyAsks, 0, "replacing: and such a key is not asked for a name")
        rawset(world.env, "C_AuctionHouse", nil)
        primary.info = { getterName = "GetHyperlink", getterArgs = { "a link", 260 } }
        Equal(Beside(beside2, ring2), Line("8ec3e6", nil, "Guardian", "+25% upgrade", true),
            "replacing: and for a tooltip filled another way, whatever its second argument")
        primary.info = nil
        -- Frames go by with nothing built: nothing is added a second time. And the client
        -- built it twice before the frame: one line of the addon's, after the client's two.
        Equal(Beside(beside2, ring2), Line("8ec3e6", nil, "Guardian", "+25% upgrade", true), "replacing: the line again")
        beside2:Update()
        beside1:Update()
        Equal(#beside2.lines, 3, "replacing: one line for two buildings, and no second one for a tooltip the client did not build again")
        -- No item in the tooltip that owns the comparison tooltip, and an owner that is no
        -- tooltip.
        local alone, lonely = Tip(), Tip()
        feature:NoteComparisonTooltips(lonely)
        world.BuildComparison(alone, lonely, ring2)
        lonely:Update()
        Equal(#lonely.lines, 2, "replacing: nothing where the tooltip that owns it names no item")
        world.BuildComparison({}, lonely, ring2)
        lonely:Update()
        Equal(#lonely.lines, 2, "replacing: nothing where its owner is no tooltip")
        -- The piece looked at is the one in the tooltip that owns the comparison tooltip.
        local other = Tip()
        other.shownLink = world.game.Link(940001)
        world.BuildComparison(other, beside2, ring2)
        beside2:Update()
        Equal(#beside2.lines, 2, "replacing: the piece looked at is the one in the tooltip that owns the comparison tooltip")
        -- A tooltip the client has hidden since: nothing, and nothing later without another
        -- building.
        primary.shownLink = looked:GetItemLink()
        world.BuildComparison(primary, beside2, ring2)
        beside2.shown = false
        beside2:Update()
        beside2.shown = true
        beside2:Update()
        Equal(#beside2.lines, 2, "replacing: nothing for a tooltip that was hidden when its frame came")
        -- Any watched tooltip's frame adds what is owed to every one of them.
        world.BuildComparison(primary, beside2, ring2)
        beside1:Update()
        Equal(table.concat(beside2.lines, " | ", 3), Line("8ec3e6", nil, "Guardian", "+25% upgrade", true),
            "replacing: one tooltip's frame adds what another is owed")
        -- Two worn rings: the client builds both comparison tooltips before a frame goes by,
        -- and that one frame adds to both.
        world.BuildComparison(primary, beside1, ring1)
        world.BuildComparison(primary, beside2, ring2)
        beside1:Update()
        Check(#beside1.lines == 3 and #beside2.lines == 3,
            "replacing: one frame adds to every tooltip that is owed, not to the first alone (" .. #beside1.lines .. ", " .. #beside2.lines .. ")")
        -- The tooltip took its size before the line: it is shown anew, and only where a line
        -- was added.
        beside2.shows = 0
        Beside(beside2, ring2)
        Equal(beside2.shows, 1, "replacing: the tooltip is shown again for the added line")
        beside2.shows = 0
        Beside(beside2, ring2, world.env.CaerdonItem:CreateFromItemID(940001))
        Equal(beside2.shows, 0, "replacing: and not where nothing was added")
        -- What the addon last made of each comparison tooltip is kept for the export: the two
        -- pieces, the buildings, what was added or why nothing, how often in a row, and how
        -- the tooltip stood a moment after its lines.
        local idle = Tip()
        feature:NoteComparisonTooltips(idle)
        primary.shownLink = world.game.Link(940001)
        world.BuildComparison(primary, idle, ring2)
        idle:Update()
        Beside(beside2, ring2)
        Beside(beside2, ring2)
        world.client:Tick(120)
        local report = feature:GetComparisonReport()
        local all = {}
        for _, entry in ipairs(report) do
            all[#all + 1] = tostring(entry.state) .. " / " .. tostring(entry.last) .. " / " .. tostring(entry.sample)
        end
        all = table.concat(all, " | ")
        Check(#report == 5 and type(report[1].state) == "string", "replacing: each comparison tooltip as it stands now (" .. #report .. ")")
        Check(all:find(": built 2 times, added 1 (the tooltip had 2 lines, has 3)", 1, true) ~= nil,
            "replacing: the buildings since, the two pieces and what was added: " .. all)
        Check(all:find("(2 times in a row, over ", 1, true) ~= nil, "replacing: the same thing again is counted: " .. all)
        Check(all:find("it stands beside names no item", 1, true) ~= nil, "replacing: a tooltip beside none that names an item")
        Check(all:find("nothing added (the worn piece shown is in no slot the piece would take)", 1, true) ~= nil,
            "replacing: and why nothing was added: " .. all)
        Check(all:find("0.1 s after its lines were first added: shown, 3 lines; 3 when the addon last added to it (1 its own)", 1, true) ~= nil,
            "replacing: and how a tooltip stood a moment after its lines were added: " .. all)

        icon.ShowOtherSpecUpgrades = false
        world.worn[11], world.worn[12], world.inBag[2] = nil, nil, nil
        world.setForSpec, world.setLocations, world.locationData, world.setIDs, world.setNames = nil, nil, nil, nil, nil
        world.scaleValues = nil
        PawnChanged(world)
    end

    -- 14, the other way: a Pawn without the function its tooltip lines are added in. The
    -- addon's handler adds the lines itself, to the client's own item tooltips and no other
    -- (the tooltip Pawn reads from is filled like any tooltip).
    do
        local other = Start({ noPawnTooltipStep = true })
        Equal(#other.client.errors, 0, "no tooltip step: the addon loads without it")
        rawset(other.env, "CaerdonWardrobeCharacterConfig", { Icon = { OtherSpecs = { DRUID2 = true } } })
        rawset(other.env, "PawnOptions", { AutoSelectScales = true })
        other.env.CaerdonWardrobeConfig.Icon.ShowOtherSpecUpgrades = true
        other.scaleValues = { [FERAL] = { [940001] = 30, [940002] = 5 }, [GUARDIAN] = { [940001] = 10, [940002] = 12 } }
        local otherInfo = Info(other, { GUARDIAN }, {})
        Equal(otherInfo.pawnOffTreeUpgrade, true, "no tooltip step: the piece is an upgrade for the other spec")
        local clientTooltip, private = Tip(), Tip()
        local feature = other.namespace.Tooltip
        feature:PlaceUpgradeLines(clientTooltip)
        local piece = other.env.CaerdonItem:CreateFromItemID(940001)
        feature:OweUpgradeLines(clientTooltip, piece)
        Equal(clientTooltip.lines[1], Line("8ec3e6", nil, "Feral", "+500% upgrade"), "no tooltip step: a client tooltip gets its line from the handler")
        feature:OweUpgradeLines(private, piece)
        Equal(#private.lines, 0, "no tooltip step: any other tooltip gets none")
        feature:NoteComparisonTooltips(private)
        feature:OweUpgradeLines(private, piece)
        Equal(#private.lines, 0, "no tooltip step: nor a comparison tooltip")
        -- The comparison's own line does not need Pawn's step: the worn jerkin is worth 12 on
        -- Guardian's scale and the piece 10. Feral, with no gear set, goes by the worn one too,
        -- and is not what is on: its line is the item tooltip's, above, and not here.
        -- It is the item tooltip's own frame that adds the line here: where a bag button's
        -- tooltip is set again, which is what builds the comparison again.
        clientTooltip.shownLink = piece:GetItemLink()
        other.BuildComparison(clientTooltip, private, other.env.CaerdonItem:CreateFromItemID(940002))
        Equal(#private.lines, 2, "no tooltip step: nothing is added while the client builds")
        clientTooltip:Update()
        Equal(private.lines[3], "|cff8ec3e6Guardian:|r  |cff808080-17%|r", "no tooltip step: a comparison tooltip still says what the piece would do in the worn one's place")
        Equal(#private.lines, 3, "no tooltip step: and nothing for the other spec, which goes by the worn gear and is not the one played")
        Equal(#other.client.errors, 0, "no tooltip step: no error reached the error handler")
    end

    Equal(#world.client.errors, 0, "end: no error reached the error handler")
    for _, message in ipairs(world.client.errors) do
        Check(false, "end: " .. message)
    end
end
