-- What the addon's own code makes of an item's answers: the item's getters, the transmog
-- info of a piece of equipment, and the status that comes of it.
--
-- These are the expectations of the WoWUnit tests the addon used to ship (tests/*.lua), as
-- far as they were about the addon's code and not about one account's collection. Those
-- tests asked a live client about real items; here the same questions are put to a hand-made
-- game (tools/harness/game.lua), one item per case. So this proves what the code decides
-- from a given set of answers, and nothing about what a client answers: the expectations
-- that need a client are verdict tests and a contract in the test addon.
--
-- Real code: the addon's item side, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 29 }

    local function Armor(name, slot, appearance, more)
        local item = { name = name, quality = 2, level = 25, minLevel = 20, type = "Armor", subType = "Leather",
            stack = 1, equipLoc = slot, price = 500, classID = 4, subClassID = 2, bindType = 2,
            tooltip = { { text = "Binds when equipped", type = 20, bonding = 2 } }, appearance = appearance }
        for key, value in pairs(more or {}) do
            item[key] = value
        end
        return item
    end

    local function Items()
        return {
            -- A shirt nobody has learned, as the old canary's Brawler's Harness was.
            [910001] = Armor("Canary Harness", "INVTYPE_BODY", { appearanceID = 5101, sourceID = 7101 },
                { subType = "Miscellaneous", subClassID = 0, minLevel = 0, level = 10 }),
            -- A look the toon knows from another item it can use.
            [910002] = Armor("Twin Gloves", "INVTYPE_HAND", { appearanceID = 5102, sourceID = 7102 }),
            [910003] = Armor("Elder Gloves", "INVTYPE_HAND", { appearanceID = 5102, sourceID = 7103, collected = true }),
            -- A source that is learned.
            [910004] = Armor("Learned Boots", "INVTYPE_FEET", { appearanceID = 5104, sourceID = 7104, collected = true }),
            -- A source this toon cannot collect and the account can.
            [910005] = Armor("Stranger's Helm", "INVTYPE_HEAD",
                { appearanceID = 5105, sourceID = 7105, valid = false, canCollect = false, account = true },
                { subType = "Plate", subClassID = 4 }),
            -- A piece above the toon's level: the client writes the requirement in red.
            [910006] = Armor("Lofty Vest", "INVTYPE_CHEST", { appearanceID = 5106, sourceID = 7106 }, { minLevel = 40,
                tooltip = { { text = "Binds when equipped", type = 20, bonding = 2 },
                    { text = "Requires Level 40", type = 0, r = 1, g = 0.125, b = 0.125 } } }),
            -- Something that is no equipment at all.
            [910007] = { name = "Cracked Fang", quality = 0, level = 5, minLevel = 0, type = "Miscellaneous",
                subType = "Junk", stack = 20, price = 12, classID = 15, subClassID = 0 },
            -- A look known from another item, by who can learn this source and who can use the
            -- known one (the gloves above are the first of four cases).
            -- This toon learns it; the look is known only from a source it cannot use.
            [910010] = Armor("Odd Bracers", "INVTYPE_WRIST", { appearanceID = 5110, sourceID = 7110 }),
            [910011] = Armor("Alien Bracers", "INVTYPE_WRIST", { appearanceID = 5110, sourceID = 7111, collected = true, valid = false }),
            -- Another toon learns it; known from a source this toon cannot use. This toon could
            -- wear the belt, and could not wear the shield.
            [910012] = Armor("Shared Belt", "INVTYPE_WAIST",
                { appearanceID = 5112, sourceID = 7112, canCollect = false, account = true }),
            [910013] = Armor("Alien Belt", "INVTYPE_WAIST", { appearanceID = 5112, sourceID = 7113, collected = true, valid = false }),
            [910014] = Armor("Far Shield", "INVTYPE_SHIELD",
                { appearanceID = 5114, sourceID = 7114, valid = false, canCollect = false, account = true },
                { subType = "Shields", subClassID = 6 }),
            [910015] = Armor("Alien Shield", "INVTYPE_SHIELD", { appearanceID = 5114, sourceID = 7115, collected = true, valid = false },
                { subType = "Shields", subClassID = 6 }),
            -- Another toon learns it; known only from a source this toon can use.
            [910016] = Armor("Lent Cloak", "INVTYPE_CLOAK",
                { appearanceID = 5116, sourceID = 7116, valid = false, canCollect = false, account = true }),
            [910017] = Armor("Own Cloak", "INVTYPE_CLOAK", { appearanceID = 5116, sourceID = 7117, collected = true }),
            -- Bound to the account (Enum.ItemBind.ToWoWAccount).
            [910008] = { name = "Family Crest", quality = 7, level = 1, minLevel = 0, type = "Miscellaneous",
                subType = "Other", stack = 1, price = 0, classID = 15, subClassID = 4, bindType = 7 },
        }
    end

    -- A client that plays the game with the addon's item side in it. configure(config) changes
    -- the settings a new install starts with.
    local function Start(configure)
        local items = Items()
        local game = H.StockGame(TOON, items)
        -- The stock game has one answer for the toon and the account; here they can differ.
        game:Set("C_TransmogCollection.AccountCanCollectSource", function(sourceID)
            for _, item in pairs(items) do
                local appearance = item.appearance
                if appearance and appearance.sourceID == sourceID then
                    return true, appearance.account == true or appearance.canCollect ~= false
                end
            end
            return false, false
        end)
        local client = H.Client.New({ flavor = "forever", provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        local config = H.DeepCopy(namespace:GetDefaultConfig())
        if configure then
            configure(config)
        end
        rawset(client.env, "CaerdonWardrobeConfig", config)
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)
        return client
    end

    local function Load(client, itemID)
        local item = client.env.CaerdonItem:CreateFromItemID(itemID)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        client:TickUntil(function() return loaded end, 10)
        return loaded and item or nil
    end

    local function Status(client, item)
        local ready, status, binding
        client:TickUntil(function()
            ready, status, binding = item:GetCaerdonStatus()
            return ready
        end, 10)
        return ready and status or "<not ready>", binding
    end

    local function NoErrors(client, label)
        Equal(#client.errors, 0, label .. ": no error reached the error handler")
        for _, message in ipairs(client.errors) do
            Check(false, label .. ": " .. message)
        end
    end

    --------------------------------------------------------------------------------------
    -- The settings of a new install, with debug on for what the old canary read
    --------------------------------------------------------------------------------------

    local client = Start(function(config) config.Debug.Enabled = true end)
    NoErrors(client, "start")
    local env = client.env

    -- The item's own getters (CaerdonItemTests: DataChangeCanary).
    do
        local item = Load(client, 910001)
        Check(item ~= nil, "getters: the shirt loads")
        if item then
            Equal(item:GetItemType(), "Armor", "getters: item type")
            Equal(item:GetItemSubType(), "Miscellaneous", "getters: item subtype")
            Equal(item:GetItemTypeID(), 4, "getters: item type ID")
            Equal(item:GetItemSubTypeID(), 0, "getters: item subtype ID")
            Equal(item:GetEquipLocation(), "INVTYPE_BODY", "getters: equip location")
            Equal(item:GetMinLevel(), 0, "getters: minimum level")
            Equal(item:GetItemQuality(), 2, "getters: quality")
            Equal(item:GetBinding(), "Bind on Equip", "getters: bind type 2 is bind on equip")
            Equal(item:GetBinding(), env.CaerdonItemBind.BindOnEquip, "getters: which is the addon's own name for it")
            Equal(item:GetExpansionID(), 0, "getters: expansion")
            Equal(item:GetIsCraftingReagent(), false, "getters: not a crafting reagent")
            Equal(item:GetHasUse(), false, "getters: no use effect")
            Equal(item:GetCaerdonItemType(), env.CaerdonItemType.Equipment, "getters: it is equipment to the addon")

            local forDebugUse = item:GetForDebugUse()
            Check(type(forDebugUse) == "table", "getters: the link's parts are there with debug on")
            if type(forDebugUse) == "table" then
                Equal(forDebugUse.linkType, "item", "getters: the link's type")
                Equal(forDebugUse.linkDisplayText, "[Canary Harness]", "getters: the link's text")
                Check(tostring(forDebugUse.linkOptions):find("^910001:") ~= nil, "getters: the link's options start with the item")
            end
        end
        local fang = Load(client, 910007)
        Check(fang ~= nil and fang:GetEquipLocation() == nil, "getters: no equip location for what is not worn")
        Check(fang ~= nil and fang:GetBinding() == env.CaerdonItemBind.None, "getters: bind type 0 is no binding")
        local crest = Load(client, 910008)
        Check(crest ~= nil and crest:GetBinding() == env.CaerdonItemBind.BindOnAccount,
            "getters: bind type 7 is bound to the account")
        Check(fang ~= nil and fang:GetItemData() == nil or fang:GetItemData().GetTransmogInfo == nil,
            "getters: junk has no transmog info")
    end

    -- An unlearned source the toon can collect, of a look nobody knows (DataChangeCanary and
    -- the "Need" tests): needed by this toon, by nobody else, not for completion only.
    do
        local item = Load(client, 910001)
        local info = item and item:GetItemData():GetTransmogInfo() or {}
        Equal(info.isTransmog, true, "need: it has an appearance")
        Equal(info.isBindOnPickup, false, "need: it does not bind on pickup")
        Equal(info.appearanceID, 5101, "need: the appearance")
        Equal(info.sourceID, 7101, "need: the source")
        Equal(info.needsItem, true, "need: this toon needs it")
        Equal(info.otherNeedsItem, false, "need: so nobody else is named")
        Equal(info.isCompletionistItem, false, "need: the look is new")
        Equal(info.hasMetRequirements, true, "need: the toon has the level")
        Equal(info.matchesLootSpec, true, "need: no specialization rules it out")
        Equal(info.canEquip, true, "need: the toon can use it")

        local debugUse = info.forDebugUseOnly
        Check(type(debugUse) == "table", "need: the debug details are there with debug on")
        if type(debugUse) == "table" then
            Equal(debugUse.currentSourceFound, false, "need: its own source is not collected")
            Equal(debugUse.otherSourceFound, false, "need: no other source is collected")
            Equal(debugUse.otherSourceFoundForPlayer, false, "need: for this toon either")
            Equal(#(debugUse.appearanceSources or {}), 1, "need: the look has this one source")
            local source = (debugUse.appearanceSources or {})[1] or {}
            Equal(source.sourceID, 7101, "need: which is the item's own")
            Equal(source.visualID, 5101, "need: with the look's ID")
            Equal(source.itemID, 910001, "need: and the item's")
            Equal(source.itemSubTypeID, 0, "need: the addon adds the item's subtype to what the client says of a source")
        end
        Equal((Status(client, item)), "own", "need: the status is own")
    end

    -- The level (hasMetRequirements was "the toon's level is at least the item's" in every
    -- old test).
    do
        local item = Load(client, 910006)
        local info = item and item:GetItemData():GetTransmogInfo() or {}
        Equal(info.needsItem, true, "level: a piece above the toon's level is still needed")
        Equal(info.hasMetRequirements, false, "level: and its requirement is not met")
        Equal((Status(client, item)), "lowSkill", "level: the status is lowSkill")
    end

    -- Another toon's (the "Need" tests on a toon that cannot equip the piece).
    do
        local item = Load(client, 910005)
        local info = item and item:GetItemData():GetTransmogInfo() or {}
        Equal(info.isTransmog, true, "other: it has an appearance")
        Equal(info.needsItem, false, "other: this toon cannot collect it")
        Equal(info.otherNeedsItem, true, "other: the account can")
        Equal(info.isCompletionistItem, false, "other: the look is new")
        Equal(info.canEquip, false, "other: the toon cannot use it")
        Equal((Status(client, item)), "other", "other: the status is other")
    end

    -- A learned source (LeatherTests: CorruptedAspirantGlovesKnown).
    local LEARN = { own = true, ownPlus = true, other = true, otherPlus = true, otherNoLoot = true, lowSkill = true,
        lowSkillPlus = true }
    do
        local item = Load(client, 910004)
        local info = item and item:GetItemData():GetTransmogInfo() or {}
        Equal(info.isTransmog, true, "known: it has an appearance")
        Equal(info.needsItem, false, "known: this toon does not need it")
        Equal(info.otherNeedsItem, false, "known: nobody else does")
        Equal(info.isCompletionistItem, false, "known: nor for completion")
        local status = Status(client, item)
        Check(not LEARN[status], "known: the status names nothing to learn (" .. tostring(status) .. ")")
    end

    -- A look known from another item (the "Completionist" tests), with the setting as a new
    -- install has it: off, so no icon says "learnable".
    do
        local item = Load(client, 910002)
        local info = item and item:GetItemData():GetTransmogInfo() or {}
        Equal(env.CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem, false,
            "completion: a new install does not show looks known from another item")
        Equal(info.needsItem, true, "completion: the source is still to learn")
        Equal(info.isCompletionistItem, true, "completion: the look is known from another item")
        Equal(info.otherNeedsItem, false, "completion: nobody else is named")
        local debugUse = info.forDebugUseOnly or {}
        Equal(debugUse.otherSourceFoundForPlayer, true, "completion: from a source this toon can use")
        Equal(#(debugUse.appearanceSources or {}), 2, "completion: the look has two sources")
        local status = Status(client, item)
        Check(not LEARN[status], "completion: with the setting off the status names nothing to learn ("
            .. tostring(status) .. ")")
    end
    -- The other three cases of a known look. What the transmog info says of each is the same
    -- with either setting; with the setting off a Plus case shows nothing to learn.
    local KNOWN_LOOKS = {
        { id = 910010, label = "this toon's, known from a source it cannot use",
            needs = true, other = false, completionist = false, canEquip = true, off = "own", on = "own" },
        { id = 910012, label = "another toon's, known from a source this toon cannot use, wearable here",
            needs = false, other = true, completionist = true, canEquip = true, on = "otherPlus" },
        { id = 910014, label = "another toon's, known from a source this toon cannot use, not wearable here",
            needs = false, other = true, completionist = true, canEquip = false, on = "otherPlus" },
        { id = 910016, label = "another toon's, known only from a source this toon can use",
            needs = false, other = true, completionist = false, off = "other", on = "other" },
    }
    local function CheckKnownLooks(which, settingOn)
        for _, case in ipairs(KNOWN_LOOKS) do
            local item = Load(which, case.id)
            local info = item and item:GetItemData():GetTransmogInfo() or {}
            Equal(info.needsItem, case.needs, "known look, " .. case.label .. ": needed by this toon")
            Equal(info.otherNeedsItem, case.other, "known look, " .. case.label .. ": needed by another")
            Equal(info.isCompletionistItem, case.completionist, "known look, " .. case.label .. ": counts as known")
            if case.canEquip ~= nil then
                Equal(info.canEquip, case.canEquip, "known look, " .. case.label .. ": whether the toon can use it")
            end
            local status = item and Status(which, item)
            local want = settingOn and case.on or case.off
            if want then
                Equal(status, want, "known look, " .. case.label .. ": the status with the setting " .. (settingOn and "on" or "off"))
            else
                Check(not LEARN[status], "known look, " .. case.label .. ": with the setting off nothing to learn is shown ("
                    .. tostring(status) .. ")")
            end
        end
    end
    CheckKnownLooks(client, false)
    NoErrors(client, "new install")

    --------------------------------------------------------------------------------------
    -- The same look with the setting on, as the old tests switched it
    --------------------------------------------------------------------------------------

    do
        local shown = Start(function(config) config.Icon.ShowLearnable.SameLookDifferentItem = true end)
        NoErrors(shown, "setting on")
        local item = Load(shown, 910002)
        Check(item ~= nil, "completion: the gloves load")
        if item then
            Equal((Status(shown, item)), "ownPlus", "completion: with the setting on the status is ownPlus")
            Check(item:GetItemData():GetTransmogInfo().forDebugUseOnly == false or
                item:GetItemData():GetTransmogInfo().forDebugUseOnly == nil,
                "completion: without debug the transmog info carries no debug details")
            Equal(item:GetForDebugUse(), false, "completion: nor does the item")
        end
        local shirt = Load(shown, 910001)
        Equal(shirt and (Status(shown, shirt)), "own", "completion: a new look is own with either setting")
        CheckKnownLooks(shown, true)
        NoErrors(shown, "setting on, after")
    end

    --------------------------------------------------------------------------------------
    -- Housing: when the data counts as still on its way
    --------------------------------------------------------------------------------------

    -- (CaerdonItemTests: HousingPendingRequiresMissingDataOnly.) No client is asked.
    do
        local pending = env.CaerdonHousingMixin and env.CaerdonHousingMixin.DebugIsHousingDataPending
        Check(type(pending) == "function", "housing: the gate can be asked")
        if type(pending) == "function" then
            Equal(pending(nil), true, "housing: nothing known is pending")
            Equal(pending({ hasCatalogEntry = false, hasTooltipCounts = false, hasDyeInfo = false }), true,
                "housing: no catalog entry, no tooltip counts and no dye is pending")
            Equal(pending({ hasCatalogEntry = true, hasTooltipCounts = false, hasDyeInfo = false }), false,
                "housing: a catalog entry alone is enough, owned or not")
            Equal(pending({ hasCatalogEntry = false, hasTooltipCounts = true, hasDyeInfo = false }), false,
                "housing: so are the tooltip's counts")
            Equal(pending({ hasCatalogEntry = false, hasTooltipCounts = false, hasDyeInfo = true }), false,
                "housing: and a dye")
        end
    end
end
