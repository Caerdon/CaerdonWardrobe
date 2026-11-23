-- What a window that offers items does with a look to learn (a feature's statusRules).
--
-- The verdict is one per item link, for every window. Three windows show some looks otherwise
-- once it is made: the journal and crafting orders mark a look this toon needs by the loot
-- spec chosen, and all three mark a look only another toon could learn as not to be had where
-- this toon cannot collect the source (the journal also where the piece binds when picked up).
-- The core used to know these windows by name; each now declares its rules, and a feature that
-- draws another's content answers with that feature's rules.
--
--   1. The rules, case by case, of the three windows' own files and of BetterBags' vendor.
--   2. Every combination of what the rules read, against the rules as the core had them by
--      window name (Reference below).
--   3. Through ProcessItem: the drawing is handed the status the window's rules gave, a window
--      with no rules the verdict, and a draw with no window raises nothing.
--
-- Real code: the core, FeatureMixin.lua and the four feature files, whose Init is not run (the
-- declaration is on the mixin). The items are plain tables with what the rules read.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Druid", classFile = "DRUID", race = "Night Elf",
        faction = "Alliance", level = 60 }

    local function Start(flavor)
        local game = H.StockGame(TOON, {})
        local world = {}
        game:Set("C_AddOns.GetAddOnInfo", function(name) return name, name, "", world.otherAddons and world.otherAddons[name] or false end)
        game:Set("C_AddOns.IsAddOnLoaded", function(name) return world.otherAddons and world.otherAddons[name] or false end)
        game:Set("C_AddOns.GetAddOnMetadata", function() return "1" end)
        local client = H.Client.New({ flavor = flavor, provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))

        -- Two windows of the scenario's own, for the draw: one that offers and one that holds.
        local OffersMixin = { statusRules = { otherSpec = true, noLoot = true } }
        function OffersMixin:GetName() return "Offers" end
        function OffersMixin:Init() end
        client.env.CaerdonWardrobe:RegisterFeature(OffersMixin)
        -- And one that declares the one rule only, which no shipped window does.
        local SpecOnlyMixin = { statusRules = { otherSpec = true } }
        function SpecOnlyMixin:GetName() return "SpecOnly" end
        function SpecOnlyMixin:Init() end
        client.env.CaerdonWardrobe:RegisterFeature(SpecOnlyMixin)
        local HoldsMixin = {}
        function HoldsMixin:GetName() return "Holds" end
        function HoldsMixin:Init() end
        client.env.CaerdonWardrobe:RegisterFeature(HoldsMixin)

        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(10)

        -- The shipped windows' files, loaded as the game loads them. Loading registers the
        -- feature; its Init, which hooks the window, is not run.
        world.otherAddons = { BetterBags = true }
        for _, file in ipairs({ "features/Merchant.lua", "features/CustomerOrders.lua", "features/EncounterJournal.lua",
            "external/BetterBags/Core.BetterBags.lua" }) do
            client:LoadAddonFile("CaerdonWardrobe", H.addonDir, file, namespace)
        end
        world.client, world.env, world.core = client, client.env, client.env.CaerdonWardrobe
        return world
    end

    local function Item(itemType)
        local item = {}
        function item:GetCaerdonItemType() return itemType or "Equipment" end
        function item:HasItemLocationBankOrBags() return false end
        return item
    end

    -- The rules as the core had them, by the window's name.
    local function Reference(window, itemType, status, smallMark, info, binding, sameLook)
        if itemType ~= "Equipment" or not info or not info.isTransmog then
            return status
        end
        if status == "quest" or smallMark == "quest" then
            return status
        end
        if not (window == "EncounterJournal" or window == "Merchant" or window == "CustomerOrders") then
            return status
        end
        if info.needsItem and window ~= "Merchant" then
            if not info.matchesLootSpec then
                if status == "own" or status == "lowSkill" then
                    return "otherSpecPlus"
                elseif sameLook then
                    return "otherSpec"
                end
            end
        elseif info.otherNeedsItem then
            local show = info.playerCanCollectSource == false
            if window == "EncounterJournal" then
                show = show or (binding and binding.isBindOnPickup)
            end
            if show then
                return info.isCompletionistItem and "otherPlusNoLoot" or "otherNoLoot"
            end
        end
        return status
    end

    -- Which window's rules each feature goes by.
    local WINDOWS = {
        { feature = "EncounterJournal", rulesOf = "EncounterJournal" },
        { feature = "Merchant", rulesOf = "Merchant" },
        { feature = "CustomerOrders", rulesOf = "CustomerOrders" },
        { feature = "BetterBagsVendor", rulesOf = "Merchant" },
        { feature = "BetterBagsGuildBank", rulesOf = "none" },
        { feature = "Holds", rulesOf = "none" },
    }

    for _, flavor in ipairs({ "forever", "retail" }) do
        local label = flavor .. ": "
        local world = Start(flavor)
        local core, client = world.core, world.client
        local config = world.env.CaerdonWardrobeConfig
        Equal(#client.errors, 0, label .. "the files load with no error (" .. tostring(client.errors[1]) .. ")")

        local features = {}
        for _, window in ipairs(WINDOWS) do
            features[window.feature] = core:GetFeature(window.feature)
            Check(features[window.feature] ~= nil, label .. window.feature .. ": the file registers its feature")
        end
        local journal, vendor, orders = features.EncounterJournal, features.Merchant, features.CustomerOrders
        local bagsVendor, holds = features.BetterBagsVendor, features.Holds

        ----------------------------------------------------------------------------------
        -- 1. Case by case
        ----------------------------------------------------------------------------------

        if journal and vendor and orders and bagsVendor and holds then
            local piece = Item()
            local function Shown(feature, status, info, binding, smallMark)
                info.isTransmog = info.isTransmog ~= false
                return feature:ApplyStatusRules(piece, status, smallMark, info, binding)
            end
            config.Icon.ShowLearnable.SameLookDifferentItem = true

            -- A look this toon needs, on a piece the loot spec chosen does not bring.
            local needed = { needsItem = true, matchesLootSpec = false }
            Equal(Shown(journal, "own", needed), "otherSpecPlus", label .. "journal: a look to learn of another loot spec is that spec's")
            Equal(Shown(journal, "lowSkill", needed), "otherSpecPlus", label .. "journal: below its level too")
            Equal(Shown(journal, "ownPlus", needed), "otherSpec", label .. "journal: a look known from another item is the plain one")
            Equal(Shown(orders, "own", needed), "otherSpecPlus", label .. "orders: the same as the journal")
            Equal(Shown(vendor, "own", needed), "own", label .. "vendor: a vendor's piece is not marked by the loot spec")
            Equal(Shown(bagsVendor, "own", needed), "own", label .. "BetterBags' vendor: nor is it there")
            Equal(Shown(holds, "own", needed), "own", label .. "a window that holds items changes nothing")
            Equal(Shown(journal, "own", { needsItem = true, matchesLootSpec = true }), "own",
                label .. "journal: a look the loot spec brings stays the star")
            config.Icon.ShowLearnable.SameLookDifferentItem = false
            Equal(Shown(journal, "ownPlus", needed), "ownPlus", label .. "journal: with known looks switched off the plain one is not marked")
            Equal(Shown(journal, "own", needed), "otherSpecPlus", label .. "journal: the look to learn still is")
            config.Icon.ShowLearnable.SameLookDifferentItem = true

            -- A look only another toon could learn.
            local restricted = { otherNeedsItem = true, playerCanCollectSource = false }
            local open = { otherNeedsItem = true, playerCanCollectSource = true }
            local pickup = { isBindOnPickup = true }
            for name, feature in pairs({ journal = journal, vendor = vendor, orders = orders, ["BetterBags' vendor"] = bagsVendor }) do
                Equal(Shown(feature, "other", restricted), "otherNoLoot", label .. name .. ": a source this toon cannot collect is not to be had")
                Equal(Shown(feature, "other", open), "other", label .. name .. ": one it can collect stays learnable")
            end
            Equal(Shown(journal, "other", { otherNeedsItem = true, playerCanCollectSource = false, isCompletionistItem = true }),
                "otherPlusNoLoot", label .. "journal: a look known from another item has the Plus form")
            Equal(Shown(journal, "other", open, pickup), "otherNoLoot", label .. "journal: a drop that binds when picked up is not to be had")
            Equal(Shown(vendor, "other", open, pickup), "other", label .. "vendor: a piece that binds when picked up stays learnable")
            Equal(Shown(bagsVendor, "other", open, pickup), "other", label .. "BetterBags' vendor: and there")
            Equal(Shown(orders, "other", open, pickup), "other", label .. "orders: and there")
            Equal(Shown(holds, "other", restricted, pickup), "other", label .. "a window that holds items changes nothing here either")
            Equal(Shown(core:GetFeature("SpecOnly"), "other", restricted, pickup), "other",
                label .. "a window that declares the loot spec's rule alone marks nothing as not to be had")
            Equal(Shown(core:GetFeature("SpecOnly"), "own", needed), "otherSpecPlus", label .. "and has the rule it declares")
            -- A vendor's piece this toon needs and another toon too is judged by the source.
            Equal(Shown(vendor, "own", { needsItem = true, otherNeedsItem = true, playerCanCollectSource = false }), "otherNoLoot",
                label .. "vendor: a piece both need goes by whether the source can be collected")
            Equal(Shown(journal, "own", { needsItem = true, matchesLootSpec = true, otherNeedsItem = true,
                playerCanCollectSource = false }), "own", label .. "journal: there the toon's own need comes first")

            -- A quest's item and one that starts a quest are left alone.
            Equal(Shown(journal, "quest", needed), "quest", label .. "journal: an item a quest takes keeps the quest icon")
            Equal(Shown(journal, "own", needed, nil, "quest"), "own", label .. "journal: one that starts a quest keeps its star")
            Equal(Shown(journal, "own", needed, nil, "readable"), "otherSpecPlus", label .. "journal: another small mark holds nothing back")
            -- Not a look, not a piece of equipment, nothing known of it.
            Equal(Shown(journal, "own", { isTransmog = false, needsItem = true, matchesLootSpec = false }), "own",
                label .. "journal: a piece with no look is left alone")
            Equal(journal:ApplyStatusRules(Item("Consumable"), "own", nil, { isTransmog = true, needsItem = true }, nil), "own",
                label .. "journal: so is what is not equipment")
            Equal(journal:ApplyStatusRules(piece, "own", nil, nil, nil), "own", label .. "journal: and a piece nothing is known of")
            Equal(journal:ApplyStatusRules(piece, nil, nil, nil, nil), nil, label .. "journal: no status stays none")

            -- BetterBags' vendor has the vendor's own table, not a copy of it.
            Check(bagsVendor:GetStatusRules() == vendor:GetStatusRules() and vendor:GetStatusRules() ~= nil,
                label .. "BetterBags' vendor answers with the vendor's rules themselves")
            Equal(features.BetterBagsGuildBank:GetStatusRules(), nil, label .. "BetterBags' guild bank has none")
        end

        ----------------------------------------------------------------------------------
        -- 2. Every combination, against the rules by window name
        ----------------------------------------------------------------------------------

        do
            local BOOL, THREE = { true, false }, { true, false, "nil" }
            local STATUSES = { "own", "ownPlus", "lowSkill", "lowSkillPlus", "other", "otherPlus", "upgrade", "collected",
                "sellable", "quest", "nil" }
            local MARKS = { "nil", "quest", "readable" }
            local BINDINGS = { "nil", { isBindOnPickup = true }, { isBindOnPickup = false }, {} }
            local function Value(v)
                if v == "nil" then
                    return nil
                end
                return v
            end
            local compared, differing, first = 0, 0, nil
            for _, window in ipairs(WINDOWS) do
                local feature = features[window.feature]
                for _, itemType in ipairs({ "Equipment", "Consumable" }) do
                    local item = Item(itemType)
                    for _, sameLook in ipairs(BOOL) do
                        config.Icon.ShowLearnable.SameLookDifferentItem = sameLook
                        for _, isTransmog in ipairs(BOOL) do
                            for _, needsItem in ipairs(BOOL) do
                                for _, otherNeedsItem in ipairs(BOOL) do
                                    for _, matches in ipairs(BOOL) do
                                        for _, canCollect in ipairs(THREE) do
                                            for _, completionist in ipairs(BOOL) do
                                                local info = { isTransmog = isTransmog, needsItem = needsItem,
                                                    otherNeedsItem = otherNeedsItem, matchesLootSpec = matches,
                                                    playerCanCollectSource = Value(canCollect), isCompletionistItem = completionist }
                                                for _, binding in ipairs(BINDINGS) do
                                                    for _, status in ipairs(STATUSES) do
                                                        for _, mark in ipairs(MARKS) do
                                                            local want = Reference(window.rulesOf, itemType, Value(status), Value(mark),
                                                                info, Value(binding), sameLook)
                                                            local got = feature and feature:ApplyStatusRules(item, Value(status),
                                                                Value(mark), info, Value(binding))
                                                            compared = compared + 1
                                                            if got ~= want then
                                                                differing = differing + 1
                                                                first = first or format("%s, %s, status %s, mark %s: %s, by name %s",
                                                                    window.feature, itemType, status, mark, tostring(got), tostring(want))
                                                            end
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            config.Icon.ShowLearnable.SameLookDifferentItem = true
            Check(compared > 100000, label .. "every combination was compared (" .. compared .. ")")
            Equal(differing, 0, label .. "the declared rules give what the rules by window name gave (first: " .. tostring(first) .. ")")
        end

        ----------------------------------------------------------------------------------
        -- 3. Through ProcessItem
        ----------------------------------------------------------------------------------

        do
            local handed
            function core:SetItemButtonStatus(button, item, feature, locationInfo, options, status)
                handed = status
            end
            function core:SetItemButtonMogStatusFilter() end
            function core:SetItemButtonBindType() end
            local info = { isTransmog = true, needsItem = true, matchesLootSpec = false }
            local function Drawn(feature, status)
                local button = client:NewFrame("Button")
                button:SetSize(37, 37)
                local item = Item()
                function item:GetCaerdonStatus() return true, status, nil, {}, info, nil end
                if feature then
                    core:SetupCaerdonButton(button, item, feature, nil, {})
                end
                handed = "nothing"
                core:ProcessItem(button, item, feature, nil, {})
                return handed
            end
            Equal(Drawn(core:GetFeature("Offers"), "own"), "otherSpecPlus", label .. "draw: the drawing is handed the status the window's rules gave")
            Equal(Drawn(core:GetFeature("Holds"), "own"), "own", label .. "draw: and the verdict where the window has none")
            Equal(Drawn(nil, "own"), "own", label .. "draw: a draw with no window has the verdict")
            Equal(info.needsItem, true, label .. "draw: the transmog info is read and not changed")
            Equal(#client.errors, 0, label .. "draw: no error (" .. tostring(client.errors[1]) .. ")")
        end
    end
end
