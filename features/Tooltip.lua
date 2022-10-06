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

    -- GameTooltip:HookScript("OnTooltipSetItem", function (...) Tooltip:OnTooltipSetItem(...) end)
    -- ItemRefTooltip:HookScript("OnTooltipSetItem", function(...) Tooltip:OnTooltipSetItem(...) end)

    hooksecurefunc(GameTooltip, "ProcessInfo", function (...) Tooltip:OnProcessInfo(...) end)
    hooksecurefunc(ItemRefTooltip, "ItemRefSetHyperlink", function (...) Tooltip:OnItemRefSetHyperlink(...) end)
    -- TODO (Check this): hooksecurefunc(GameTooltip, "SetQuestCurrency", function (...) Tooltip:OnTooltipSetQuestCurrency(...) end)
    hooksecurefunc("BattlePetToolTip_Show", function (...) Tooltip:OnBattlePetTooltipShow(BattlePetTooltip, ...) end)
    hooksecurefunc("FloatingBattlePet_Show", function(...) Tooltip:OnBattlePetTooltipShow(FloatingBattlePetTooltip, ...) end)
    -- hooksecurefunc("GameTooltip_AddQuestRewardsToTooltip", function(...) Tooltip:OnGameTooltipAddQuestRewardsToTooltip(...) end)
    -- For embedded items (for quests, at least)
    -- hooksecurefunc("EmbeddedItemTooltip_OnTooltipSetItem", function(...) Tooltip:OnEmbeddedItemTooltipSetItem(...) end)

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
    if tooltipInfo.getterName == "GetBagItem" then
        local bag, slot = unpack(tooltipInfo.getterArgs)
        if bag and slot then
            local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
            Tooltip:ProcessTooltip(tooltip, item)
        end
    elseif tooltipInfo.getterName == "GetInventoryItem" then
        local target, slot = unpack(tooltipInfo.getterArgs)
        if slot then
            local item = CaerdonItem:CreateFromEquipmentSlot(slot)
            Tooltip:ProcessTooltip(tooltip, item)
        end
    elseif tooltipInfo.getterName == "GetCurrencyByID" then
        local currencyID = unpack(tooltipInfo.getterArgs)
        local itemLink = C_CurrencyInfo.GetCurrencyLink(currencyID)
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        Tooltip:ProcessTooltip(tooltip, item)
    elseif tooltipInfo.getterName == "GetCurrencyToken" then
        local tokenIndex = unpack(tooltipInfo.getterArgs)
        local itemLink = C_CurrencyInfo.GetCurrencyListLink(tokenIndex)
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        Tooltip:ProcessTooltip(tooltip, item)
    elseif tooltipInfo.getterName == "GetBackpackToken" then
        local currencyIndex = unpack(tooltipInfo.getterArgs)
        local currencyInfo = C_CurrencyInfo.GetBackpackCurrencyInfo(currencyIndex);
        local itemLink = C_CurrencyInfo.GetCurrencyLink(currencyInfo.currencyTypesID)
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
            end
        end
    end
end

-- function TooltipMixin:OnGameTooltipAddQuestRewardsToTooltip(tooltip, questID, style)
--     local itemLink = GetQuestLink(questID)
--     -- TODO: This happens with assault quests, at least... need to look into more
--     if itemLink then
--         local item = CaerdonItem:CreateFromItemLink(itemLink)
--         Tooltip:ProcessTooltip(tooltip, item)
--     end
-- end

-- function TooltipMixin:OnEmbeddedItemTooltipSetItem(tooltip)
--     if tooltip.itemID then
--         local item = CaerdonItem:CreateFromItemID(tooltip.itemID)
--         Tooltip:ProcessTooltip(tooltip.Tooltip, item, true)
--     end
-- end

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

-- function TooltipMixin:OnBattlePetTooltipShow(speciesID, level, quality, health, power, speed, customName)
    -- if BattlePetTooltip:IsShown() then
    --     local item = CaerdonItem:CreateFromSpeciesInfo(speciesID, level, quality, health, power, speed, customName)
    --     Tooltip:ProcessTooltip(BattlePetTooltip, item)
    -- end
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
        self:AddTooltipDoubleData(tooltip, item, "Link Type", forDebugUse and forDebugUse.linkType or "Missing", "Options", forDebugUse and forDebugUse.linkOptions or "Missing")
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
