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
--   3. With one visible scale, or no spec chosen, nothing is ignored.
--   4. A change of spec refreshes the icons, once, and so does a change of the loot spec; an
--      event with both as they were refreshes nothing.
--   5. A higher item level where Pawn calls the piece no upgrade: it counts where Pawn has no
--      verdict, not where Pawn's scores prefer the worn piece, whatever Pawn's own item level
--      switch says; the addon's two settings switch it off and let it stand against the scores.
--   6. A piece for another loot spec keeps Pawn's verdict and is marked as such.
--   7. An upgrade for another spec with Pawn showing the played spec's scale alone: scored on
--      the other spec's scale against the gear set assigned to that spec, or the worn gear.
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
        }
    end

    local function Start()
        local game = H.StockGame(TOON, Items())
        local world = { game = game, spec = 3, lootSpec = 0, visible = {}, upgradeFor = {}, refreshes = {} }
        world.scales = {
            ["\"MrRobot\":DRUID2"] = { ClassID = CLASS_ID, SpecID = 2, Provider = "MrRobot", LocalizedName = "Druid: Feral" },
            ["\"MrRobot\":DRUID3"] = { ClassID = CLASS_ID, SpecID = 3, Provider = "MrRobot", LocalizedName = "Druid: Guardian" },
            ["\"MrRobot\":MAGE1"] = { ClassID = 8, SpecID = 1, Provider = "MrRobot", LocalizedName = "Mage: Arcane" },
            ["My own"] = { LocalizedName = "My own" },
        }
        game:Set("GetSpecialization", function() return world.spec end)
        game:Set("GetLootSpecialization", function() return world.lootSpec end)
        game:Set("PawnCommon.Scales", world.scales)
        game:Set("PawnCommon.ShowItemLevelUpgrades", false)
        game:Set("PawnIsScaleVisible", function(name) return world.visible[name] == true end)
        game:Set("PawnGetItemData", function(link) return { Link = link } end)
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
        game:Set("PawnGetItemDataForInventorySlot", function(slot)
            if slot == 5 then
                return { Link = game.Link(940002) }, true
            end
            return nil, false
        end)
        -- The chest slot holds the worn jerkin.
        local hyperlink = game.names["C_TooltipInfo.GetHyperlink"]
        game:Set("C_TooltipInfo.GetInventoryItem", function(_, slot)
            return slot == 5 and hyperlink(game.Link(940002)) or nil
        end)
        local function Worn(location)
            if type(location) ~= "table" then
                return nil
            elseif location.IsEquipmentSlot and location:IsEquipmentSlot() then
                return location:GetEquipmentSlot() == 5 and 940002 or nil
            elseif location.IsBagAndSlot and location:IsBagAndSlot() then
                -- Bag 0, slot 1: the other spec's jerkin.
                local bag, slot = location:GetBagAndSlot()
                return bag == 0 and slot == 1 and 940003 or nil
            end
        end
        game:Set("GetInventoryItemLink", function(_, slot) return slot == 5 and game.Link(940002) or nil end)
        game:Set("C_Item.DoesItemExist", function(location) return Worn(location) ~= nil end)
        game:Set("C_Item.GetItemLink", function(location) return Worn(location) and game.Link(Worn(location)) end)
        game:Set("C_Item.GetItemID", function(location) return Worn(location) end)
        game:Set("C_Item.GetCurrentItemLevel", function(location) return Worn(location) and 190 or nil end)
        game:Set("C_Item.IsBound", function() return false end)
        -- The loot spec an item is for (world.itemSpecs), and the spec IDs of this class.
        game:Set("C_Item.GetItemSpecInfo", function() return world.itemSpecs end)
        game:Set("GetSpecializationInfo", function(index) return 100 + index end)
        game:Set("PawnIsItemAnUpgrade", function()
            local upgrades = {}
            for name in pairs(world.upgradeFor) do
                if world.visible[name] then
                    upgrades[#upgrades + 1] = { ScaleName = name, LocalizedScaleName = world.scales[name].LocalizedName }
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
        world.client, world.env = client, client.env

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
    local function Info(world, visible, upgradeFor, itemID)
        world.visible, world.upgradeFor = {}, {}
        for _, name in ipairs(visible) do world.visible[name] = true end
        for _, name in ipairs(upgradeFor) do world.upgradeFor[name] = true end
        world.env.CaerdonWardrobe:RefreshItems("test")
        world.client:Tick(10)
        local item = world.env.CaerdonItem:CreateFromItemID(itemID or 940001)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        world.client:TickUntil(function() return loaded end, 10)
        return loaded and item:GetItemData():GetTransmogInfo() or {}, item
    end

    -- Pawn's values changed (a weight was edited): Pawn says so, and the values kept are dropped.
    local function PawnChanged(world)
        world.env.PawnResetTooltips()
        world.client:Tick(10)
    end

    local world = Start()
    Equal(#world.client.errors, 0, "start: no error reached the error handler")
    Check(world.env.CaerdonAPI:GetTalentTrees() == nil, "start: this client has no talent tree groups")
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
    info = Info(world, { FERAL }, { FERAL })
    Equal(info.pawnIdentifiedUpgrade, true, "one scale: the only visible scale counts, whatever spec it names")
    Equal(world.env.CaerdonEquipment:GetPawnScaleFilterDescription(), nil, "one scale: and the filter is off")
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

    -- A spec the player switched off: no upgrade for it, by the addon's own scoring or by a
    -- scale of it that Pawn shows.
    world.scaleValues[FERAL][940001] = 30
    PawnChanged(world)
    info = Info(world, { GUARDIAN }, {})
    Equal(info.pawnOffTreeUpgrade, true, "chosen specs: a spec that was never switched off counts")
    icon.OtherSpecs = { DRUID2 = false }
    info = Info(world, { GUARDIAN }, {})
    Equal(info.isUpgrade, nil, "chosen specs: none for a spec that is switched off")
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.isUpgrade, nil, "chosen specs: nor through its scale where Pawn shows that")
    icon.OtherSpecs = { DRUID2 = true }
    info = Info(world, { FERAL, GUARDIAN }, { FERAL })
    Equal(info.pawnOffTreeUpgrade, true, "chosen specs: switched on again, it counts")
    icon.OtherSpecs = {}
    world.scaleValues, world.values = nil, nil
    icon.ShowOtherSpecUpgrades = false

    Equal(#world.client.errors, 0, "end: no error reached the error handler")
    for _, message in ipairs(world.client.errors) do
        Check(false, "end: " .. message)
    end
end
