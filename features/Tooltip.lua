local TooltipMixin, Tooltip = {}
-- local frame = CreateFrame("frame")
-- frame:RegisterEvent "ADDON_LOADED"
-- frame:SetScript("OnEvent", function(this, event, ...)
--     Tooltip[event](Quest, ...)
-- end)

local SpecMap = {
    [250] = "Blood Death Knight",
    [251] = "Frost Death Knight",
    [252] = "Unholy Death Knight",

    [577] = "Havoc Demon Hunter",
    [581] = "Vengeance Demon Hunter",

    [102] = "Balance Druid",
    [103] = "Feral Druid",
    [104] = "Guardian Druid",
    [105] = "Restoration Druid",

    [253] = "Beast Mastery Hunter",
    [254] = "Marksmanship Hunter",
    [255] = "Survival Hunter",

    [62] = "Arcane Mage",
    [63] = "Fire Mage",
    [64] = "Frost Mage",

    [268] = "Brewmaster Monk",
    [270] = "Mistweaver Monk",
    [269] = "Windwalker Monk",

    [65] = "Holy Paladin",
    [66] = "Protection Paladin",
    [70] = "Retribution Paladin",

    [256] = "Discipline Priest",
    [257] = "Holy Priest",
    [258] = "Shadow Priest",

    [259] = "Assassination Rogue",
    [260] = "Outlaw Rogue",
    [261] = "Subtlety Rogue",

    [262] = "Elemental Shaman",
    [263] = "Enhancement Shaman",
    [264] = "Restoration Shamana",

    [265] = "Affliction Warlock",
    [266] = "Demonology Warlock",
    [267] = "Destruction Warlock",

    [71] = "Arms Warrior",
    [72] = "Fury Warrior",
    [73] = "Protection Warrior"
}

function TooltipMixin:ADDON_LOADED(name)
    -- Disabling for now until I can get useful info from a Trainer API
    -- if name == "Blizzard_TrainerUI" then
    --     hooksecurefunc("ClassTrainerFrame_SetServiceButton", function(...) Tooltip:OnClassTrainerFrameSetServiceButton(...) end)
	-- end
end

function TooltipMixin:OnLoad()
    -- TODO: Add Debug enable option setting
    if C_TooltipInfo then
        hooksecurefunc(GameTooltip, "ProcessInfo", function (...) Tooltip:OnProcessInfo(...) end)
        hooksecurefunc(ItemRefTooltip, "ItemRefSetHyperlink", function (...) Tooltip:OnItemRefSetHyperlink(...) end)
        hooksecurefunc("BattlePetToolTip_Show", function (...) Tooltip:OnBattlePetTooltipShow(BattlePetTooltip, ...) end)
        hooksecurefunc("FloatingBattlePet_Show", function(...) Tooltip:OnBattlePetTooltipShow(FloatingBattlePetTooltip, ...) end)
        hooksecurefunc("EmbeddedItemTooltip_SetItemByQuestReward", function(...) Tooltip:OnEmbeddedItemTooltipSetItemByQuestReward(...) end)
    end

    -- TODO: Hack to ensure GameTooltip:SetPoint is called.  Otherwise, BattlePetTooltip can puke.
    -- Shouldn't need now that I switched to C_TooltipInfo...
    -- GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)

    -- hooksecurefunc("TaskPOI_OnEnter", function(...) Tooltip:OnTaskPOIOnEnter(...) end)
    
	-- Show missing info in tooltips
	-- NOTE: This causes a bug with tooltip scanning, so we disable
	--   briefly and turn it back on with each scan.
	-- C_TransmogCollection.SetShowMissingSourceInItemTooltips(true)
	-- SetCVar("missingTransmogSourceInItemTooltips", 1)

    -- May need this for inner items but has same item reference in current tests resulting in double
    -- ItemRefTooltip:HookScript("OnShow", function (tooltip, ...) Tooltip:OnTooltipSetItem(tooltip, ...) end)

    -- TODO: Can hook spell in same way if needed...
    -- GameTooltip:HookScript("OnTooltipSetSpell", OnTooltipSetSpell)
    -- ItemRefTooltip:HookScript("OnTooltipSetSpell", OnTooltipSetSpell)
end

-- function TooltipMixin:OnTaskPOIOnEnter(taskPOI, skipSetOwner)
--     if not HaveQuestData(taskPOI.questID) then
--         return -- retrieving item data
--     end

--     if C_QuestLog.IsQuestReplayable(taskPOI.questID) then
--         itemLink = QuestUtils_GetReplayQuestDecoration(taskPOI.questID)
--     else
--         itemLink = GetQuestLink(taskPOI.questID)
--     end

--     local item = CaerdonItem:CreateFromItemLink(itemLink)
--     Tooltip:ProcessTooltip(GameTooltip, item)

--     GameTooltip.recalculatePadding = true;
--     -- GameTooltip:SetHeight(GameTooltip:GetHeight() + 2)
-- end

local tooltipItem

function TooltipMixin:OnBattlePetTooltipShow(tooltip, speciesID, level, quality, health, power, speed, customName, battlePetID)
    if not CaerdonWardrobeConfig.Debug.Enabled then
        -- Not doing anything other than debug for tooltips right now
        return
    end

    local ownedText = tooltip.Owned:GetText() or ""
    local origHeight = tooltip.Owned:GetHeight()

    tooltip.Owned:SetWordWrap(true)

    tooltip:AddLine("|nCaerdon Wardrobe", 0, 0.8, 0.8, true)

    local englishFaction = UnitFactionGroup("player")
    local specIndex = GetSpecialization()
    local specID, specName, specDescription, specIcon, specBackground, specRole, specPrimaryStat = GetSpecializationInfo(specIndex)

    tooltip:AddLine(format("|nSpec: %s", SpecMap[specID] or specID), 0, 0.8, 0.8, true)
    tooltip:AddLine(format("Level: %s", UnitLevel("player")), 0, 0.8, 0.8, true)
    tooltip:AddLine(format("Faction: %s", englishFaction), 0, 0.8, 0.8, true)

    local item = CaerdonItem:CreateFromSpeciesInfo(speciesID, level, quality, health, power, speed, customName, battlePetID)
    if item then
        local itemData = item:GetItemData()
        tooltip:AddLine(format("|nIdentified Type: %s", item:GetCaerdonItemType()), 0, 0.8, 0.8, true)

        local forDebugUse = item:GetForDebugUse()
        tooltip:AddLine(format("|nLink Type: %s", forDebugUse and forDebugUse.linkType or "Missing"), 0, 0.8, 0.8, true)
        tooltip:AddLine(format("Options: %s", forDebugUse and forDebugUse.linkOptions or "Missing"), 0, 0.8, 0.8, true)
        
        tooltip:AddLine(format("|nSpecies ID: %s", speciesID), 0, 0.8, 0.8, true)
        if item:GetCaerdonItemType() == CaerdonItemType.BattlePet then
            local petInfo = itemData and itemData:GetBattlePetInfo()
            if petInfo then
                tooltip:AddLine(format("Num Collected: %s", petInfo.numCollected), 0, 0.8, 0.8, true)
            end
        end
    end

    local owned = C_PetJournal.GetOwnedBattlePetString(speciesID);
    if(owned == nil) then
        FloatingBattlePetTooltip.Delimiter:ClearAllPoints();
        FloatingBattlePetTooltip.Delimiter:SetPoint("TOPLEFT",FloatingBattlePetTooltip.SpeedTexture,"BOTTOMLEFT",-6,-5);
    else
        FloatingBattlePetTooltip.Delimiter:ClearAllPoints();
        FloatingBattlePetTooltip.Delimiter:SetPoint("TOPLEFT",FloatingBattlePetTooltip.SpeedTexture,"BOTTOMLEFT",-6,-19);
    end
end

function TooltipMixin:OnItemRefSetHyperlink(tooltip, itemLink)
    local item = CaerdonItem:CreateFromItemLink(itemLink)
    Tooltip:ProcessTooltip(tooltip, item)
end

function TooltipMixin:OnProcessInfo(tooltip, tooltipInfo)
    if not CaerdonWardrobeConfig.Debug.Enabled then
        -- Not doing anything other than debug for tooltips right now
        return
    end

    if tooltipInfo.getterName == "GetAction" then
        local actionID = unpack(tooltipInfo.getterArgs)
        local actionType, id, actionSubType = GetActionInfo(actionID);
        if actionType == "item" then -- ignoring summonmount, spell, flyout, and any others for now
            local item = CaerdonItem:CreateFromItemID(id)
            Tooltip:ProcessTooltip(tooltip, item)
        end
    elseif tooltipInfo.getterName == "GetBackpackToken" then
        local currencyIndex = unpack(tooltipInfo.getterArgs)
        local currencyInfo = C_CurrencyInfo.GetBackpackCurrencyInfo(currencyIndex);
        local itemLink = C_CurrencyInfo.GetCurrencyLink(currencyInfo.currencyTypesID)
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        Tooltip:ProcessTooltip(tooltip, item)
    elseif tooltipInfo.getterName == "GetBagItem" then
        local bag, slot = unpack(tooltipInfo.getterArgs)
        if bag and slot then
            local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
            Tooltip:ProcessTooltip(tooltip, item)
        end
    elseif tooltipInfo.getterName == "GetBuybackItem" then
        local index = unpack(tooltipInfo.getterArgs)
        local itemLink = GetBuybackItemLink(index)
        if itemLink then
            local item = CaerdonItem:CreateFromItemLink(itemLink)
            Tooltip:ProcessTooltip(tooltip, item)
        end
    elseif tooltipInfo.getterName == "GetCompanionPet" then
        local petGUID = unpack(tooltipInfo.getterArgs)
        local itemLink = C_PetJournal.GetBattlePetLink(petGUID)
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        Tooltip:ProcessTooltip(tooltip, item)
    elseif tooltipInfo.getterName == "GetCurrencyByID" then
        local currencyID, amount = unpack(tooltipInfo.getterArgs)
        local itemLink = C_CurrencyInfo.GetCurrencyLink(currencyID)
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        Tooltip:ProcessTooltip(tooltip, item)
    elseif tooltipInfo.getterName == "GetCurrencyToken" then
        local tokenIndex = unpack(tooltipInfo.getterArgs)
        local itemLink = C_CurrencyInfo.GetCurrencyListLink(tokenIndex)
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        Tooltip:ProcessTooltip(tooltip, item)
    elseif tooltipInfo.getterName == "GetHeirloomByItemID" then
        local itemID = unpack(tooltipInfo.getterArgs)
        local itemLink = C_Heirloom.GetHeirloomLink(itemID)
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        Tooltip:ProcessTooltip(tooltip, item)
    elseif tooltipInfo.getterName == "GetHyperlink" then
        local itemLink, optionalArg1, optionalArg2, hideVendorPrice = unpack(tooltipInfo.getterArgs)
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        Tooltip:ProcessTooltip(tooltip, item)
    elseif tooltipInfo.getterName == "GetInboxItem" then
        local messageIndex, attachmentIndex = unpack(tooltipInfo.getterArgs)
        local itemLink = GetInboxItemLink(messageIndex, attachmentIndex or 1)
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        Tooltip:ProcessTooltip(tooltip, item)
    elseif tooltipInfo.getterName == "GetInventoryItem" then
        local target, slot, hideUselessStats = unpack(tooltipInfo.getterArgs)
        if slot then
            local item = CaerdonItem:CreateFromEquipmentSlot(slot)
            Tooltip:ProcessTooltip(tooltip, item)
        end
    elseif tooltipInfo.getterName == "GetItemByGUID" then
        local guid = unpack(tooltipInfo.getterArgs)
        local item = CaerdonItem:CreateFromItemGUID(guid)
        Tooltip:ProcessTooltip(tooltip, item)
    elseif tooltipInfo.getterName == "GetItemByID" then
        local itemID, quality = unpack(tooltipInfo.getterArgs) -- TODO: Do I need to include quality into CreateFromItemID somehow?
        local item = CaerdonItem:CreateFromItemID(itemID)
        Tooltip:ProcessTooltip(tooltip, item)
    elseif tooltipInfo.getterName == "GetItemKey" then
        local itemID, itemLevel, itemSuffix, requiredLevel = unpack(tooltipInfo.getterArgs)
        local itemKey = { itemID = itemID, itemLevel = itemLevel, itemSuffix = itemSuffix, requiredLevel = requiredLevel }
        local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(itemKey)
        if itemKeyInfo and itemKeyInfo.battlePetLink then
            item = CaerdonItem:CreateFromItemLink(itemKeyInfo.battlePetLink)
        else
            item = CaerdonItem:CreateFromItemID(itemKey.itemID)
        end
        Tooltip:ProcessTooltip(tooltip, item)
    elseif tooltipInfo.getterName == "GetLootCurrency" then
        local slot = unpack(tooltipInfo.getterArgs)
        local itemLink = GetLootSlotLink(slot);
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        Tooltip:ProcessTooltip(tooltip, item)
    elseif tooltipInfo.getterName == "GetLootItem" then
        local slot = unpack(tooltipInfo.getterArgs)
        local itemLink = GetLootSlotLink(slot);
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        Tooltip:ProcessTooltip(tooltip, item)
    elseif tooltipInfo.getterName == "GetMerchantCostItem" then
        local slot, costIndex = unpack(tooltipInfo.getterArgs)
        local itemTexture, itemValue, itemLink, currencyName = GetMerchantItemCostItem(slot, costIndex);
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        Tooltip:ProcessTooltip(tooltip, item)
    elseif tooltipInfo.getterName == "GetMerchantItem" then
        local slot = unpack(tooltipInfo.getterArgs)
        local itemLink = GetMerchantItemLink(slot);
        if itemLink then
            local item = CaerdonItem:CreateFromItemLink(itemLink)
            Tooltip:ProcessTooltip(tooltip, item)
        end
    elseif tooltipInfo.getterName == "GetMountBySpellID" then
        local spellID, checkIndoors = unpack(tooltipInfo.getterArgs)
        local itemLink = C_MountJournal.GetMountLink(spellID)
        if itemLink then
            local item = CaerdonItem:CreateFromItemLink(itemLink)
            Tooltip:ProcessTooltip(tooltip, item)
        end
    elseif tooltipInfo.getterName == "GetRecipeReagentItem" then
        local recipeSpellID, dataSlotIndex = unpack(tooltipInfo.getterArgs)
        local itemLink = C_TradeSkillUI.GetRecipeFixedReagentItemLink(recipeSpellID, dataSlotIndex)
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        Tooltip:ProcessTooltip(tooltip, item)
    elseif tooltipInfo.getterName == "GetRecipeResultItem" then
        local recipeID, craftingReagents, recraftItemGUID, recipeLevel, overrideQualityID = unpack(tooltipInfo.getterArgs)
        -- TODO: Not sure why this method is missing... but I'm not always get a full item back from GetRecipeOutputItemData so need to figure something out here. (See enchant Writ of Versatility)
        -- local resultItem = GetRecipeResultItem(recipeID, craftingReagents, recraftItemGUID, recipeLevel, overrideQualityID)
        local resultItem = C_TradeSkillUI.GetRecipeOutputItemData(recipeID, craftingReagents, recraftItemGUID)
        if resultItem.hyperlink then
            local item = CaerdonItem:CreateFromItemLink(resultItem.hyperlink)
            Tooltip:ProcessTooltip(tooltip, item)
        end
    elseif tooltipInfo.getterName == "GetSendMailItem" then
        local attachmentIndex = unpack(tooltipInfo.getterArgs)
        local itemLink = GetSendMailItemLink(attachmentIndex)
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        Tooltip:ProcessTooltip(tooltip, item)
    elseif tooltipInfo.getterName == "GetToyByItemID" then
        local itemID = unpack(tooltipInfo.getterArgs)
        local itemLink = C_ToyBox.GetToyLink(itemID)
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        Tooltip:ProcessTooltip(tooltip, item)
    elseif tooltipInfo.getterName == "GetQuestCurrency" then
        local itemType, currencyIndex = unpack(tooltipInfo.getterArgs)
        local currencyID = GetQuestCurrencyID(itemType, currencyIndex)
        local itemLink = C_CurrencyInfo.GetCurrencyLink(currencyID)
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        Tooltip:ProcessTooltip(tooltip, item)
    elseif tooltipInfo.getterName == "GetQuestItem" then
        local rewardType, index, allowCollectionText = unpack(tooltipInfo.getterArgs)
        local itemLink = GetQuestItemLink(rewardType, index)
        if itemLink then
            local item = CaerdonItem:CreateFromItemLink(itemLink)
            Tooltip:ProcessTooltip(tooltip, item)
        end
    elseif tooltipInfo.getterName == "GetQuestLogCurrency" then
        local itemType, currencyIndex, questID = unpack(tooltipInfo.getterArgs)
        local name, texture, amount, currencyID, quality = GetQuestLogRewardCurrencyInfo(currencyIndex, questID)
        local itemLink = C_CurrencyInfo.GetCurrencyLink(currencyID)
        local item = CaerdonItem:CreateFromItemLink(itemLink)
    elseif tooltipInfo.getterName == "GetQuestLogItem" then
        local rewardType, index, questID, showCollectionText = unpack(tooltipInfo.getterArgs)
        local itemLink = GetQuestLogItemLink(rewardType, index, questID)
        if itemLink then
            local item = CaerdonItem:CreateFromItemLink(itemLink)
            Tooltip:ProcessTooltip(tooltip, item)
        end
    elseif tooltipInfo.getterName == "GetQuestLogSpecialItem" then
        local questIndex = unpack(tooltipInfo.getterArgs)
        local itemLink, item, charges, showItemWhenComplete = GetQuestLogSpecialItemInfo(questIndex)
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        Tooltip:ProcessTooltip(tooltip, item)
    else -- try and cover anything else I haven't added
        -- TODO: Maybe add info to the debug tooltip, so I can see I'm missing something here?
        local tooltipData = tooltip:GetTooltipData();
        if tooltipData then
            if tooltipData.type == Enum.TooltipDataType.Item then
                print("MISSING HANDLER FOR " .. tooltipInfo.getterName)
                local item = CaerdonItem:CreateFromItemID(tooltipData.id)
                Tooltip:ProcessTooltip(tooltip, item)
            elseif tooltipData.type == Enum.TooltipDataType.Spell then
            elseif tooltipData.type == Enum.TooltipDataType.Unit then
            elseif tooltipData.type == Enum.TooltipDataType.Corpse then
            elseif tooltipData.type == Enum.TooltipDataType.Object then
            elseif tooltipData.type == Enum.TooltipDataType.UnitAura then
            elseif tooltipData.type == Enum.TooltipDataType.PetAction then
            elseif tooltipData.type == Enum.TooltipDataType.MinimapMouseover then
            elseif tooltipData.type == Enum.TooltipDataType.QuestPartyProgress then
            else
                print("MISSING HANDLER FOR " .. tooltipInfo.getterName .. ", type: " .. tostring(tooltipData.type))
            end
        end
    end
end

function TooltipMixin:OnEmbeddedItemTooltipSetItemByQuestReward(tooltip, questLogIndex, questID, rewardType, showCollectionText)
    rewardType = rewardType or "reward";
    local itemLink = GetQuestLogItemLink(rewardType, questLogIndex, questID)
    local item = CaerdonItem:CreateFromItemLink(itemLink)
    Tooltip:ProcessTooltip(tooltip.Tooltip, item, true)
end

-- function TooltipMixin:OnTooltipSetItem(tooltip)
--     local itemName, itemLink = tooltip:GetItem()
--     if itemLink and itemName then
--         local id = string.match(itemLink, "item:(%d*)")
--         if (id == "" or id == "0") and TradeSkillFrame ~= nil and TradeSkillFrame:IsVisible() and GetMouseFocus().reagentIndex then
--             local selectedRecipe = TradeSkillFrame.RecipeList:GetSelectedRecipeID()
--             for i = 1, 8 do
--                 if GetMouseFocus().reagentIndex == i then
--                     itemLink = C_TradeSkillUI.GetRecipeReagentItemLink(selectedRecipe, i)
--                     break
--                 end
--             end
--         end

--         if not tooltipItem or tooltipItem:GetItemLink() ~= itemLink then
--             tooltipItem = CaerdonItem:CreateFromItemLink(itemLink)
--         end

--         Tooltip:ProcessTooltip(tooltip, tooltipItem)
--     end
-- end

-- This works but can't seem to do anything useful to get item info with the index (yet)
-- function TooltipMixin:OnClassTrainerFrameSetServiceButton(skillButton, skillIndex, playerMoney, selected, isTradeSkill)
--     if not skillButton.caerdonTooltipHooked then
--         skillButton.caerdonTooltipHooked = true
--         skillButton:HookScript("OnEnter", function (button, ...) 
--             print(button:GetID())
--         end)
--     end
-- end

function TooltipMixin:AddTooltipData(tooltip, item, title, value, valueColor)
	local noWrap = false;
    local wrap = true;

    local identifiedType = item:GetCaerdonItemType()

    valueColor = valueColor or HIGHLIGHT_FONT_COLOR
    
    if not title then
        GameTooltip_AddErrorLine(tooltip, format("Dev Error", "Missing Title"));
        return
    end
   
    if title and value == nil then
        GameTooltip_AddErrorLine(tooltip, format("Missing %s", title));
    elseif tooltip == BattlePetTooltip or tooltip == FloatingBattlePetTooltip or identifiedType == CaerdonItemType.Currency then -- assuming this for now
        tooltip:ProcessLineData({
            type = 'Caerdon',
            leftText = format("%s: %s", title, value),
            leftColor = HIGHLIGHT_FONT_COLOR,
            wrapText = wrap,
            leftOffset = 0
        })
    else
        tooltip:ProcessLineData({
            type = 'Caerdon',
            leftText = format("%s:", title),
            leftColor = HIGHLIGHT_FONT_COLOR,
            rightText = tostring(value),
            rightColor = valueColor,
            wrapText = wrap,
            leftOffset = 0
        })
    end
end

function TooltipMixin:AddTooltipDoubleData(tooltip, item, title, value, title2, value2, valueColor)
	local noWrap = false;
    local wrap = true;

    local identifiedType = item:GetCaerdonItemType()

    valueColor = valueColor or HIGHLIGHT_FONT_COLOR

    if not title or not title2 then
        GameTooltip_AddErrorLine(tooltip, format("Dev Error", "Missing Title"));
        return
    end
    
    if value == nil then
        GameTooltip_AddErrorLine(tooltip, format("Missing %s", title));
    end

    if value2 == nil then
        GameTooltip_AddErrorLine(tooltip, format("Missing %s", title2));
    end

    if value ~= nil and value2 ~= nil then
        if tooltip == BattlePetTooltip or tooltip == FloatingBattlePetTooltip or identifiedType == CaerdonItemType.Currency then -- assuming this for now
            GameTooltip_AddColoredLine(tooltip, format("%s: %s", title, value), HIGHLIGHT_FONT_COLOR, wrap)
            GameTooltip_AddColoredLine(tooltip, format("%s: %s", title2, value2), HIGHLIGHT_FONT_COLOR, wrap)
        else
            GameTooltip_AddColoredDoubleLine(tooltip, format("%s / %s:", title, title2), format("%s / %s", value, value2), HIGHLIGHT_FONT_COLOR, valueColor, wrap);
        end
    elseif value ~= nil then
        if tooltip == BattlePetTooltip or tooltip == FloatingBattlePetTooltip then -- assuming this for now
            GameTooltip_AddColoredLine(tooltip, format("%s: %s", title, value), HIGHLIGHT_FONT_COLOR, wrap)
        else
            GameTooltip_AddColoredDoubleLine(tooltip, format("%s:", title), tostring(value), HIGHLIGHT_FONT_COLOR, valueColor, wrap);
        end
    elseif value2 ~= nil then
        if tooltip == BattlePetTooltip or tooltip == FloatingBattlePetTooltip then -- assuming this for now
            GameTooltip_AddColoredLine(tooltip, format("%s: %s", title, value2), HIGHLIGHT_FONT_COLOR, wrap)
        else
            GameTooltip_AddColoredDoubleLine(tooltip, format("%s:", title), tostring(value2), HIGHLIGHT_FONT_COLOR, valueColor, wrap);
        end
    end
end

local cancelFuncs = {}
function TooltipMixin:ProcessTooltip(tooltip, item, isEmbedded)
    if not tooltip.info then return end -- tooltip needs access to tooltipInfo or things just break

    if not CaerdonWardrobeConfig.Debug.Enabled then
        -- Not doing anything other than debug for tooltips right now
        return
    end

    if cancelFuncs[tooltip] then
         cancelFuncs[tooltip]()
         cancelFuncs[tooltip] = nil
     end

    function continueLoad()
        if not tooltip.info then return end -- tooltip needs access to tooltipInfo or things just break

        GameTooltip_AddBlankLineToTooltip(tooltip);
        GameTooltip_AddColoredLine(tooltip, "Caerdon Wardrobe", LIGHTBLUE_FONT_COLOR);

        local forDebugUse = item:GetForDebugUse()
        local identifiedType = item:GetCaerdonItemType()

        local identifiedColor = GREEN_FONT_COLOR
        if identifiedType == CaerdonItemType.Unknown then
            identifiedColor = RED_FONT_COLOR
        end
            
        if not isEmbedded and identifiedType ~= CaerdonItemType.Currency then
            local specIndex = GetSpecialization()
            local specID, specName, specDescription, specIcon, specBackground, specRole, specPrimaryStat = GetSpecializationInfo(specIndex)
            self:AddTooltipData(tooltip, item, "Spec", SpecMap[specID] or specID)
            self:AddTooltipData(tooltip, item, "Level", UnitLevel("player"))

            local englishFaction = UnitFactionGroup("player")
            self:AddTooltipData(tooltip, item, "Faction", englishFaction)

            GameTooltip_AddBlankLineToTooltip(tooltip);
        end

        self:AddTooltipData(tooltip, item, "Identified Type", identifiedType, identifiedColor)
        if forDebugUse then
            local optionsLength = strlen(forDebugUse.linkOptions or "")
            local optionsEnd = ""
            if optionsLength > 30 then
                optionsEnd = "..."
            end

            self:AddTooltipDoubleData(tooltip, item, "Link Type", forDebugUse.linkType or "Missing", "Options", (strsub(forDebugUse.linkOptions or "", 1, 30) .. optionsEnd) or "Missing")
        end

        if item:GetItemQuality() then
            self:AddTooltipData(tooltip, item, "Quality", _G[format("ITEM_QUALITY%d_DESC", item:GetItemQuality())], item:GetItemQualityColor().color)
        end

        local itemLocation = item:GetItemLocation()
        if itemLocation and itemLocation:HasAnyLocation() then
            if itemLocation:IsEquipmentSlot() then
                self:AddTooltipData(tooltip, item, "Equipment Slot", tostring(itemLocation:GetEquipmentSlot()))
            end

            if itemLocation:IsBagAndSlot() and not item:IsItemEmpty() then
                local bag, slot = itemLocation:GetBagAndSlot();
                self:AddTooltipDoubleData(tooltip, item, "Bag", bag, "Slot", slot)

                local canTransmog, error = C_Item.CanItemTransmogAppearance(itemLocation)
                self:AddTooltipData(tooltip, item, "Can Item Transmog Appearance", tostring(canTransmog))    
            end
        end

        if identifiedType ~= CaerdonItemType.BattlePet and identifiedType ~= CaerdonItemType.Quest and identifiedType ~= CaerdonItemType.Currency then
            GameTooltip_AddBlankLineToTooltip(tooltip);

            self:AddTooltipData(tooltip, item, "Item ID", item:GetItemID())
            self:AddTooltipDoubleData(tooltip, item, "Item Type", item:GetItemType(), "SubType", item:GetItemSubType())
            self:AddTooltipDoubleData(tooltip, item, "Item Type ID", item:GetItemTypeID(), "SubType ID", item:GetItemSubTypeID())
            self:AddTooltipData(tooltip, item, "Binding", item:GetBinding())

            GameTooltip_AddBlankLineToTooltip(tooltip);

            self:AddTooltipData(tooltip, item, "Expansion ID", item:GetExpansionID())
            self:AddTooltipData(tooltip, item, "Is Crafting Reagent", tostring(item:GetIsCraftingReagent()))
        end
        

        -- All data from here on out should come from the API
        -- TODO: Add additional option to show item link since it's so large?
        -- self:AddTooltipData(tooltip, item, "Item Link", gsub(item:GetItemLink(), "\124", "\124\124"))

        if identifiedType == CaerdonItemType.BattlePet or identifiedType == CaerdonItemType.CompanionPet then
            self:AddPetInfoToTooltip(tooltip, item)
        elseif identifiedType == CaerdonItemType.Equipment then
            self:AddTransmogInfoToTooltip(tooltip, item)
        end

        GameTooltip_CalculatePadding(tooltip)
    end

    if not item:IsItemEmpty() then
        cancelFuncs[tooltip] = item:ContinueWithCancelOnItemLoad(continueLoad)
    else
        continueLoad()
    end
end


function TooltipMixin:AddPetInfoToTooltip(tooltip, item)
    local itemType = item:GetCaerdonItemType()

    if itemType ~= CaerdonItemType.BattlePet and itemType ~= CaerdonItemType.CompanionPet then
        return
    end

    local itemData = item:GetItemData()

    if itemType == CaerdonItemType.CompanionPet then
        GameTooltip_AddBlankLineToTooltip(tooltip);

        local petInfo = itemData:GetCompanionPetInfo()
        local speciesID = petInfo.speciesID
        self:AddTooltipData(tooltip, item, "Species ID", speciesID)
        self:AddTooltipData(tooltip, item, "Num Collected", petInfo.numCollected or 0)
        self:AddTooltipData(tooltip, item, "Pet Type", petInfo.petType)
        self:AddTooltipData(tooltip, item, "Source", petInfo.sourceText)
    elseif itemType == CaerdonItemType.BattlePet then
        local petInfo = itemData:GetBattlePetInfo()
        local speciesID = petInfo.speciesID
        self:AddTooltipData(tooltip, item, "Species ID", petInfo.speciesID)
        self:AddTooltipData(tooltip, item, "Num Collected", petInfo.numCollected or 0)
    end
end

function TooltipMixin:AddTransmogInfoToTooltip(tooltip, item)
    local itemData = item:GetItemData()
    local transmogInfo = itemData:GetTransmogInfo()

    self:AddTooltipData(tooltip, item, "Item Equip Location", item:GetEquipLocation())

    if item:GetSetID() then
        self:AddTooltipData(tooltip, item, "Item Set ID", item:GetSetID())
    end

    local equipmentSets = itemData:GetEquipmentSets()
    if equipmentSets then
        local setNames = equipmentSets[1]
        for setIndex = 2, #equipmentSets do
            setNames = setNames .. ", " .. equipmentSets[setIndex]
        end

        self:AddTooltipData(tooltip, item, "Equipment Sets", setNames)
    end

	if transmogInfo.isTransmog then
		self:AddTooltipData(tooltip, item, "Appearance ID", transmogInfo.appearanceID)
        self:AddTooltipData(tooltip, item, "Source ID", transmogInfo.sourceID)

        GameTooltip_AddBlankLineToTooltip(tooltip);

        self:AddTooltipData(tooltip, item, "Needs Item", transmogInfo.needsItem)
        self:AddTooltipData(tooltip, item, "Other Needs Item", transmogInfo.otherNeedsItem)
        self:AddTooltipData(tooltip, item, "Is Completionist Item", transmogInfo.isCompletionistItem)
        self:AddTooltipData(tooltip, item, "Matches Loot Spec", transmogInfo.matchesLootSpec)

        local requirementsColor = (transmogInfo.hasMetRequirements == false and RED_FONT_COLOR) or nil
        self:AddTooltipData(tooltip, item, "Has Met Requirements", transmogInfo.hasMetRequirements, requirementsColor)
        self:AddTooltipData(tooltip, item, "Item Min Level", item:GetMinLevel())
        self:AddTooltipData(tooltip, item, "Can Equip", transmogInfo.canEquip)

        local matchedSources = transmogInfo.forDebugUseOnly.matchedSources
        if matchedSources and #matchedSources > 0 then
            for k,v in pairs(matchedSources) do
                self:AddTooltipData(tooltip, item, "Matched Source", v.name)
            end
        else
            self:AddTooltipData(tooltip, item, "Matched Source", false)
        end

        local appearanceInfo = transmogInfo.forDebugUseOnly.appearanceInfo
        if appearanceInfo then
            GameTooltip_AddBlankLineToTooltip(tooltip);

            self:AddTooltipData(tooltip, item, "Appearance Collected", appearanceInfo.appearanceIsCollected)
            self:AddTooltipData(tooltip, item, "Source Collected", appearanceInfo.sourceIsCollected)
            self:AddTooltipData(tooltip, item, "Is Conditionally Known", appearanceInfo.sourceIsCollectedConditional)
            self:AddTooltipData(tooltip, item, "Is Permanently Known", appearanceInfo.sourceIsCollectedPermanent)
            self:AddTooltipData(tooltip, item, "Has Non-level Reqs", appearanceInfo.appearanceHasAnyNonLevelRequirements)
            self:AddTooltipData(tooltip, item, "Meets Non-level Reqs", appearanceInfo.appearanceMeetsNonLevelRequirements)
            self:AddTooltipData(tooltip, item, "Appearance Is Usable", appearanceInfo.appearanceIsUsable)
            self:AddTooltipData(tooltip, item, "Meets Condition", appearanceInfo.meetsTransmogPlayerCondition)
        else
        end
	end
end

Tooltip = CreateFromMixins(TooltipMixin)
Tooltip:OnLoad()
