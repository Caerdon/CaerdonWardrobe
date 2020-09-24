local DEBUG_ENABLED = false
-- local DEBUG_ITEM = 82800
local ADDON_NAME, NS = ...
local L = NS.L

BINDING_HEADER_CAERDON = L["Caerdon Addons"]
BINDING_NAME_COPYMOUSEOVERLINK = L["Copy Mouseover Link"]
BINDING_NAME_PRINTMOUSEOVERLINKDETAILS = L["Print Mouseover Link Details"]

local availableFeatures = {}
local registeredFeatures = {}

local version, build, date, tocversion = GetBuildInfo()
local isShadowlands = tonumber(build) > 35700

CaerdonWardrobe = {}
CaerdonWardrobeMixin = {}

function CaerdonWardrobeMixin:OnLoad()
	self:RegisterEvent "ADDON_LOADED"
	self:RegisterEvent "PLAYER_LOGOUT"
	self:RegisterEvent "UNIT_SPELLCAST_SUCCEEDED"
	self:RegisterEvent "TRANSMOG_COLLECTION_UPDATED"
	self:RegisterEvent "EQUIPMENT_SETS_CHANGED"
	self:RegisterEvent "UPDATE_EXPANSION_LEVEL"
end

local bindTextTable = {
	[ITEM_ACCOUNTBOUND]        = L["BoA"],
	[ITEM_BNETACCOUNTBOUND]    = L["BoA"],
	[ITEM_BIND_TO_ACCOUNT]     = L["BoA"],
	[ITEM_BIND_TO_BNETACCOUNT] = L["BoA"],
	-- [ITEM_BIND_ON_EQUIP]       = L["BoE"],
	-- [ITEM_BIND_ON_USE]         = L["BoE"]
}

local function IsConduit(itemLink)
	return isShadowlands and C_Soulbinds.IsItemConduitByItemInfo(itemLink)
end

local function IsCollectibleLink(item)
	local caerdonType = item:GetCaerdonItemType()
	return caerdonType == CaerdonItemType.BattlePet or
		caerdonType == CaerdonItemType.CompanionPet or
		caerdonType == CaerdonItemType.Mount or
		caerdonType == CaerdonItemType.Recipe or
		caerdonType == CaerdonItemType.Toy
end

local equipLocations = {}

local function GetBindingStatus(item, feature, locationInfo, button, options, tooltipInfo)
	local itemID = item:GetItemID()
	local itemLink = item:GetItemLink()
	local itemData = item:GetItemData()
	local caerdonType = item:GetCaerdonItemType()

	local binding
	local bindingStatus
	local needsItem = true
	local hasEquipEffect = false

	local isBindOnPickup = false
	local isBindOnUse = false
	local unusableItem = false
	local skillTooLow = false
	local foundRedRequirements = false
	local isLocked = false
	
	local isCollectionItem = IsCollectibleLink(item)
	local isPetLink = caerdonType == CaerdonItemType.BattlePet or caerdonType == CaerdonItemType.CompanionPet

	local itemName, itemLinkInfo, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
	itemEquipLoc, iconFileDataID, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID, 
	isCraftingReagent = GetItemInfo(itemLink)

	isBindOnPickup = bindType == 1
	if bindType == 1 then -- BoP
		isBindOnPickup = true
	elseif bindType == 2 then -- BoE
		bindingStatus = "BoE"
	elseif bindType == 3 then -- BoU
		isBindOnUse = true
		bindingStatus = "BoE"
	elseif bindType == 4 then -- Quest
		bindingStatus = ""
	end

	local isConduit = false
	if IsConduit(itemLink) then
		isConduit = true

		local conduitTypes = { 
			Enum.SoulbindConduitType.Potency,
			Enum.SoulbindConduitType.Endurance,
			Enum.SoulbindConduitType.Finesse
		}

		local conduitKnown = false
		for conduitTypeIndex = 1, #conduitTypes do
			local conduitCollection = C_Soulbinds.GetConduitCollection(conduitTypes[conduitTypeIndex])
			for conduitCollectionIndex = 1, #conduitCollection do
				local conduitData = conduitCollection[conduitCollectionIndex]
				if conduitData.conduitItemID == itemID then
					conduitKnown = true
				end
			end
		end

		if not conduitKnown then
			-- TODO: May need to consider spec / class?  Not sure yet
			needsItem = true
		end
	end
	
	if tooltipInfo then
		hasEquipEffect = tooltipInfo.hasEquipEffect

		if tooltipInfo.isRelearn then
			needsItem = false
		end

		if not bindingStatus then
			bindingStatus = tooltipInfo.bindingStatus
		end

		if tooltipInfo.isKnownSpell then
			needsItem = false
		end

		isLocked = tooltipInfo.isLocked

		if tooltipInfo.supercedingSpellNotKnown then
			unusableItem = true
			skillTooLow = true
		end

		if tooltipInfo.foundRedRequirements then
			unusableItem = true
			skillTooLow = true
		end

		if tooltipInfo.isSoulbound then
			isBindOnPickup = true
		end

		-- TODO: Can we scan the embedded item tooltip? Probably need to do something like EmbeddedItemTooltip_SetItemByID
		-- This may only matter for recipes, so I may have to use LibRecipes if I can't get the recipe info for the created item.
		if tooltipInfo.isSoulbound and bindingStatus == "BoE" then  -- Equipment set binding status should go through still
			bindingStatus = nil
		end

		if tooltipInfo.requiredTradeSkillMissingOrUnleveled then
			unusableItem = true
			-- if isBindOnPickup then -- assume all unknown not needed for now
				needsItem = false
			-- end
		end

		if tooltipInfo.requiredTradeSkillTooLow then
			skillTooLow = true
			needsItem = true -- still need this but need to rank up
		end
	end

	if not bindingStatus and (isCollectionItem or isLocked or isOpenable) then
		-- TODO: This can be useful on everything but needs to be configurable per type before doing so
		if not isBindOnPickup then
			bindingStatus = "BoE"
		end
	end

	if caerdonType == CaerdonItemType.CompanionPet or caerdonType == CaerdonItemType.BattlePet then
		local petInfo = 
			(caerdonType == CaerdonItemType.CompanionPet and itemData:GetCompanionPetInfo()) or
			(caerdonType == CaerdonItemType.BattlePet and itemData:GetBattlePetInfo())
		needsItem = petInfo.needsItem
	end

	-- Haven't seen a reason for this, yet, and should be handled in each type
	-- if isCollectionItem and unusableItem then
	-- 	if not isRecipe then
	-- 		needsItem = false
	-- 	end
	-- end

	return { 
		bindingStatus = bindingStatus, 
		needsItem = needsItem, 
		hasEquipEffect = hasEquipEffect,
		isBindOnPickup = isBindOnPickup, 
		unusableItem = unusableItem, 
		isLocked = isLocked, 
		skillTooLow = skillTooLow
	}
end

local function IsGearSetStatus(status, item)
	return status and status ~= L["BoA"] and status ~= L["BoE"]
end

-- TODO: Fix this to make more flexible and consistent - getting crazy and wrong I'm sure
local function SetIconPositionAndSize(icon, startingPoint, offset, size, iconOffset, scaleAdjustment)
	scaleAdjustment = scaleAdjustment or 1
	sizeAdjustment = size - (size * scaleAdjustment)
	offset = offset - (sizeAdjustment / 2)
	iconOffset = iconOffset + (sizeAdjustment / 2)

	icon:ClearAllPoints()

	icon:SetSize(size - sizeAdjustment, size - sizeAdjustment)

	local offsetSum = (offset - iconOffset) * scaleAdjustment
	if startingPoint == "TOPRIGHT" then
		icon:SetPoint("TOPRIGHT", offsetSum, offsetSum)
	elseif startingPoint == "TOPLEFT" then
		icon:SetPoint("TOPLEFT", offsetSum * -1, offsetSum)
	elseif startingPoint == "BOTTOMRIGHT" then
		icon:SetPoint("BOTTOMRIGHT", offsetSum, offsetSum * -1)
	elseif startingPoint == "BOTTOMLEFT" then
		icon:SetPoint("BOTTOMLEFT", offsetSum * -1, offsetSum * -1)
	elseif startingPoint == "RIGHT" then
		icon:SetPoint("RIGHT", iconOffset, 0)
	elseif startingPoint == "LEFT" then
		icon:SetPoint("LEFT", iconOffset, 0)
	end

end

local function AddRotation(group, order, degrees, duration, smoothing, startDelay, endDelay)
	local anim = group:CreateAnimation("Rotation")
	group["anim" .. order] = anim
	anim:SetDegrees(degrees)
    anim:SetDuration(duration)
	anim:SetOrder(order)
	anim:SetSmoothing(smoothing)

	if startDelay then
		anim:SetStartDelay(startDelay)
	end

	if endDelay then
		anim:SetEndDelay(endDelay)
	end
end

local function SetItemButtonMogStatusFilter(originalButton, isFiltered)
	local button = originalButton.caerdonButton
	if button then
		local mogStatus = button.mogStatus
		if mogStatus then
			if isFiltered then
				mogStatus:SetAlpha(0.3)
			else
				mogStatus:SetAlpha(mogStatus.assignedAlpha)
			end
		end
	end
end

local function SetItemButtonMogStatus(originalButton, item, feature, locationInfo, options, status, bindingStatus)
	local button = originalButton.caerdonButton

	if not button then
		button = CreateFrame("Frame", nil, originalButton)
		button:SetPoint("TOPLEFT")
		button:SetPoint("BOTTOM")

		if options and options.overrideWidth then
			button:SetWidth(options.overrideWidth)
		else
			button:SetWidth(originalButton:GetWidth())
		end
		button.searchOverlay = originalButton.searchOverlay
		originalButton.caerdonButton = button
	end

	-- Had some addons messing with frame level resulting in this getting covered by the parent button.
	-- Haven't seen any negative issues with bumping it up, yet, but keep an eye on it if
	-- the status icon overlaps something it shouldn't.
	button:SetFrameLevel(originalButton:GetFrameLevel() + 100)

	local mogStatus = button.mogStatus
	local mogAnim = button.mogAnim
	local iconPosition, showSellables, isSellable
	local iconSize = 40
	local otherIcon = "Interface\\Store\\category-icon-placeholder"
	local otherIconSize = 40
	local otherIconOffset = 0
	local iconOffset = 0

	if options then 
		showSellables = options.showSellables
		isSellable = options.isSellable
		if options.iconSize then
			iconSize = options.iconSize
		end
		if options.iconOffset then
			iconOffset = options.iconOffset
			otherIconOffset = iconOffset
		end

		if options.otherIcon then
			otherIcon = options.otherIcon
		end

		if options.otherIconSize then
			otherIconSize = options.otherIconSize
		else
			otherIconSize = iconSize
		end

		if options.otherIconOffset then
			otherIconOffset = options.otherIconOffset
		end
	else
		options = {}
	end

	if options.overridePosition then -- for Encounter Journal so far
		iconPosition = options.overridePosition
	else
		iconPosition = CaerdonWardrobeConfig.Icon.Position
	end

	if not status then
		if mogAnim and mogAnim:IsPlaying() then
			mogAnim:Stop()
		end
		if mogStatus then
			mogStatus:SetTexture("")
		end

		-- Keep processing to handle gear set icon
		-- return
	end

	if not mogStatus then
		mogStatus = button:CreateTexture(nil, "OVERLAY", nil, 2)
		SetIconPositionAndSize(mogStatus, iconPosition, 15, iconSize, iconOffset)
		button.mogStatus = mogStatus
	end

	-- local mogFlash = button.mogFlash
	-- if not mogFlash then
	-- 	mogFlash = button:CreateTexture(nil, "OVERLAY")
	-- 	mogFlash:SetAlpha(0)
	-- 	mogFlash:SetBlendMode("ADD")
	-- 	mogFlash:SetAtlas("bags-glow-flash", true)
	-- 	mogFlash:SetPoint("CENTER")

	-- 	button.mogFlash = mogFlash
	-- end

	local showAnim = false
	if status == "waiting" then
		showAnim = true

		if mogAnim and not button.isWaitingIcon then
			if mogAnim:IsPlaying() then
				mogAnim:Finish()
			end

			mogAnim = nil
			button.mogAnim = nil
			button.isWaitingIcon = false
		end

		if not mogAnim or not button.isWaitingIcon then
			mogAnim = mogStatus:CreateAnimationGroup()

			AddRotation(mogAnim, 1, 360, 0.5, "IN_OUT")

		    mogAnim:SetLooping("REPEAT")
			button.mogAnim = mogAnim
			button.isWaitingIcon = true
		end
	else
		if status == "own" or status == "ownPlus" or status == "otherSpec" or status == "otherSpecPlus" or status == "refundable" or status == "openable" or status == "locked" then
			showAnim = true

			if mogAnim and button.isWaitingIcon then
				if mogAnim:IsPlaying() then
					mogAnim:Finish()
				end

				mogAnim = nil
				button.mogAnim = nil
				button.isWaitingIcon = false
			end

			if not mogAnim then
				mogAnim = mogStatus:CreateAnimationGroup()

				AddRotation(mogAnim, 1, 110, 0.2, "OUT")
				AddRotation(mogAnim, 2, -155, 0.2, "OUT")
				AddRotation(mogAnim, 3, 60, 0.2, "OUT")
				AddRotation(mogAnim, 4, -15, 0.1, "OUT", 0, 2)

			    mogAnim:SetLooping("REPEAT")
				button.mogAnim = mogAnim
				button.isWaitingIcon = false
			end
		else
			showAnim = false
		end
	end

	-- 	if not mogAnim then
	-- 		mogAnim = button:CreateAnimationGroup()
	-- 		mogAnim:SetToFinalAlpha(true)
	-- 		mogAnim.alpha1 = mogAnim:CreateAnimation("Alpha")
	-- 		mogAnim.alpha1:SetChildKey("mogFlash")
	-- 		mogAnim.alpha1:SetSmoothing("OUT");
	-- 		mogAnim.alpha1:SetDuration(0.6)
	-- 		mogAnim.alpha1:SetOrder(1)
	-- 		mogAnim.alpha1:SetFromAlpha(1);
	-- 		mogAnim.alpha1:SetToAlpha(0);

	-- 		button.mogAnim = mogAnim
	-- 	end

	local featureInstance
	local displayInfo
	if feature then
		featureInstance = registeredFeatures[feature]
		displayInfo = featureInstance:GetDisplayInfoInternal(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	end

	local alpha = 1
	mogStatus:SetVertexColor(1, 1, 1)
	-- TODO: Add options to hide these statuses
	if status == "refundable" then
		SetIconPositionAndSize(mogStatus, iconPosition, 3, 15, iconOffset)
		alpha = 0.9
		mogStatus:SetTexture("Interface\\COMMON\\mini-hourglass")
	elseif status == "openable" then
		SetIconPositionAndSize(mogStatus, iconPosition, 15, iconSize, iconOffset)
		mogStatus:SetTexture("Interface\\Store\\category-icon-free")
	elseif status == "lowSkill" or status == "lowSkillPlus" then
		mogStatus:SetTexture("Interface\\WorldMap\\Gear_64Grey")
		SetIconPositionAndSize(mogStatus, iconPosition, 15, 30, iconOffset, 0.7)
		if status == "lowSkillPlus" then
			mogStatus:SetVertexColor(0.4, 1, 0)
		end
		-- mogStatus:SetTexture("Interface\\QUESTFRAME\\SkillUp-BG")
		-- mogStatus:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
		-- mogStatus:SetTexture("Interface\\Buttons\\JumpUpArrow")
	elseif status == "locked" then
		SetIconPositionAndSize(mogStatus, iconPosition, 15, iconSize, iconOffset)
		mogStatus:SetTexture("Interface\\Store\\category-icon-key")
	elseif status == "oldexpansion" and displayInfo and displayInfo.oldExpansionIcon.shouldShow then
		SetIconPositionAndSize(mogStatus, iconPosition, 10, 30, iconOffset)
		alpha = 0.9
		mogStatus:SetTexture("Interface\\Store\\category-icon-wow")
	elseif status == "own" or status == "ownPlus" then
		if displayInfo and displayInfo.ownIcon.shouldShow then
			SetIconPositionAndSize(mogStatus, iconPosition, 15, iconSize, iconOffset)
			mogStatus:SetTexture("Interface\\Store\\category-icon-featured")
			if status == "ownPlus" then
				mogStatus:SetVertexColor(0.4, 1, 0)
			end
		else
			mogStatus:SetTexture("")
		end
	elseif status == "other" or status == "otherPlus" then
		if displayInfo and displayInfo.otherIcon.shouldShow then
			SetIconPositionAndSize(mogStatus, iconPosition, 15, otherIconSize, otherIconOffset)
			mogStatus:SetTexture(otherIcon)
			if status == "otherPlus" then
				mogStatus:SetVertexColor(0.4, 1, 0)
			end
		else
			mogStatus:SetTexture("")
		end
	elseif status == "otherSpec" or status == "otherSpecPlus" then
		if displayInfo and displayInfo.otherIcon.shouldShow then
			SetIconPositionAndSize(mogStatus, iconPosition, 15, otherIconSize, otherIconOffset)
			mogStatus:SetTexture("Interface\\COMMON\\icon-noloot")
			if status == "otherSpecPlus" then
				mogStatus:SetVertexColor(0.4, 1, 0)
			end
		else
			mogStatus:SetTexture("")
		end
	elseif status == "quest" and displayInfo and displayInfo.questIcon.shouldShow then
		SetIconPositionAndSize(mogStatus, iconPosition, 2, 15, iconOffset)
		mogStatus:SetTexture("Interface\\MINIMAP\\MapQuestHub_Icon32")
	elseif status == "collected" then
		if not IsGearSetStatus(bindingStatus, item) and showSellables and isSellable and displayInfo and displayInfo.sellableIcon.shouldShow then -- it's known and can be sold
			SetIconPositionAndSize(mogStatus, iconPosition, 10, 30, iconOffset)
			alpha = 0.9
			mogStatus:SetTexture("Interface\\Store\\category-icon-bag")
		elseif IsGearSetStatus(bindingStatus, item) and CaerdonWardrobeConfig.Binding.ShowGearSetsAsIcon then
			SetIconPositionAndSize(mogStatus, iconPosition, 10, 30, iconOffset)
			mogStatus:SetTexture("Interface\\Store\\category-icon-clothes")
		else
			mogStatus:SetTexture("")
		end
	elseif status == "waiting" then
		alpha = 0.5
		SetIconPositionAndSize(mogStatus, iconPosition, 10, 30, iconOffset)
		mogStatus:SetTexture("Interface\\Common\\StreamCircle")
	elseif IsGearSetStatus(bindingStatus, item) and CaerdonWardrobeConfig.Binding.ShowGearSetsAsIcon then
		SetIconPositionAndSize(mogStatus, iconPosition, 10, 30, iconOffset)
		mogStatus:SetTexture("Interface\\Store\\category-icon-clothes")
	end

	mogStatus:SetAlpha(alpha)
	mogStatus.assignedAlpha = alpha

	C_Timer.After(0, function() 
		if(button.searchOverlay and button.searchOverlay:IsShown()) then
			mogStatus:SetAlpha(0.3)
		end
	end)

	if showAnim and CaerdonWardrobeConfig.Icon.EnableAnimation then
		if mogAnim and not mogAnim:IsPlaying() then
			mogAnim:Play()
		end
	else
		if mogAnim and mogAnim:IsPlaying() then
			mogAnim:Finish()
		end
	end
end

local function SetItemButtonBindType(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	local caerdonButton = button.caerdonButton

	local bindsOnText = caerdonButton and caerdonButton.bindsOnText
	if bindsOnText then
		bindsOnText:SetText("")
	end

	if not feature then return end

	local featureInstance = registeredFeatures[feature]
	local displayInfo = featureInstance:GetDisplayInfoInternal(button, item, feature, locationInfo, options, mogStatus, bindingStatus)

	if not bindingStatus or not displayInfo.bindingStatus.shouldShow then
		return
	end

	if not bindsOnText then
		bindsOnText = caerdonButton:CreateFontString(nil, "ARTWORK", "SystemFont_Outline_Small") 
		caerdonButton.bindsOnText = bindsOnText
	end

	local bindingText = ""
	if IsGearSetStatus(bindingStatus) then -- is gear set
		if CaerdonWardrobeConfig.Binding.ShowGearSets and not CaerdonWardrobeConfig.Binding.ShowGearSetsAsIcon then
			bindingText = "|cFFFFFFFF" .. bindingStatus .. "|r"
		end
	else
		if mogStatus == "own" then
			if bindingStatus == L["BoA"] then
				local color = BAG_ITEM_QUALITY_COLORS[Enum.ItemQuality.Heirloom]
				bindsOnText:SetTextColor(color.r, color.g, color.b, 1)
				bindingText = bindingStatus
			elseif bindingStatus then
				bindingText = "|cFF00FF00" .. bindingStatus .. "|r"
			end
		elseif mogStatus == "other" then
			bindingText = "|cFFFF0000" .. bindingStatus .. "|r"
		elseif mogStatus == "collected" then
			if bindingStatus == L["BoA"] then
				local color = BAG_ITEM_QUALITY_COLORS[Enum.ItemQuality.Heirloom]
				bindsOnText:SetTextColor(color.r, color.g, color.b, 1)
				bindingText = bindingStatus
			elseif bindingStatus == L["BoE"] then
				bindingText = "|cFF00FF00" .. bindingStatus .. "|r"
			else
				bindingText = bindingStatus
			end
		else
			if bindingStatus == L["BoA"] then
				local color = BAG_ITEM_QUALITY_COLORS[Enum.ItemQuality.Heirloom]
				bindsOnText:SetTextColor(color.r, color.g, color.b, 1)
				bindingText = bindingStatus
			elseif bindingStatus then
				bindingText = "|cFF00FF00" .. bindingStatus .. "|r"
			end
		end
	end

	bindsOnText:SetText(bindingText)

	-- Measure text and resize accordingly
	bindsOnText:ClearAllPoints()
	bindsOnText:SetSize(0,0)
	bindsOnText:SetPoint("LEFT")
	bindsOnText:SetPoint("RIGHT")

	local newWidth = bindsOnText:GetStringWidth()
	if newWidth > button:GetWidth() then
		newWidth = button:GetWidth()
	end
	local newHeight = bindsOnText:GetHeight()

	bindsOnText:ClearAllPoints()
	bindsOnText:SetSize(newWidth, newHeight)

	local bindingPosition = options.overrideBindingPosition or CaerdonWardrobeConfig.Binding.Position
	local xOffset = options.bindingOffsetX or options.bindingOffset or 0
	local yOffset = options.bindingOffsetY or xOffset

	if string.find(bindingPosition, "BOTTOM") then
		if (button.count and button.count > 1) then
			yOffset = options.itemCountOffset or 15
		elseif yOffset == 0 then
			yOffset = 2
		end
	end

	if string.find(bindingPosition, "TOP") then
		if yOffset == 0 then
			yOffset = -3
		end
	end

	if string.find(bindingPosition, "LEFT") then
		if xOffset == 0 then
			xOffset = 3
		end
	end

	if string.find(bindingPosition, "RIGHT") then
		if xOffset == 0 then
			xOffset = -3
		end
	end

	bindsOnText:SetPoint(bindingPosition, xOffset, yOffset)

	if(options.bindingScale) then
		bindsOnText:SetScale(options.bindingScale)
	end
end

local function QueueProcessItem(itemLink, feature, locationInfo, button, options)
	C_Timer.After(0, function()
		CaerdonWardrobe:UpdateButtonLink(itemLink, feature, locationInfo, button, options)
	end)
end

local function ItemIsSellable(itemID, itemLink)
	local isSellable = itemID ~= nil
	if itemID == 23192 then -- Tabard of the Scarlet Crusade needs to be worn for a vendor at Darkmoon Faire
		isSellable = false
	elseif itemID == 116916 then -- Gorepetal's Gentle Grasp allows faster herbalism in Draenor
		isSellable = false
	end
	return isSellable
end

local function ProcessItem(item, feature, locationInfo, button, options, tooltipInfo)
	local mogStatus = nil

   	if not options then
   		options = {}
   	end

	local showMogIcon = options.showMogIcon
	local showBindStatus = options.showBindStatus
	local showSellables = options.showSellables

	local itemLink = item:GetItemLink()
	if not itemLink then
		-- Requiring an itemLink for now unless I find a reason not to
		return
	end

	-- local printable = gsub(itemLink, "\124", "\124\124");
	-- print(printable)

	local itemID = item:GetItemID()
	local caerdonType = item:GetCaerdonItemType()
	local itemData = item:GetItemData()
	local transmogInfo = item:GetCaerdonItemType() == CaerdonItemType.Equipment and itemData:GetTransmogInfo()

	local bindingResult = GetBindingStatus(item, feature, locationInfo, button, options, tooltipInfo)
	local bindingStatus = bindingResult.bindingStatus

	local itemName, itemLinkInfo, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
	itemEquipLoc, iconFileDataID, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID, 
	isCraftingReagent = GetItemInfo(itemLink)

	local playerLevel = UnitLevel("player")

	if not IsCollectibleLink(item) and not IsConduit(itemLink) then
		local expansionID = expacID
		if expansionID and expansionID >= 0 and expansionID < GetExpansionLevel() then 
			local shouldShowExpansion = false

			if expansionID > 0 or CaerdonWardrobeConfig.Icon.ShowOldExpansion.Unknown then
				if isCraftingReagent and CaerdonWardrobeConfig.Icon.ShowOldExpansion.Reagents then
					shouldShowExpansion = true
				elseif item:GetHasUse() and CaerdonWardrobeConfig.Icon.ShowOldExpansion.Usable then
					shouldShowExpansion = true
				elseif not isCraftingReagent and not item:GetHasUse() and CaerdonWardrobeConfig.Icon.ShowOldExpansion.Other then
					shouldShowExpansion = true
				end
			end

			if shouldShowExpansion then
				mogStatus = "oldexpansion"
			end
		end
	end

	local isQuestItem = itemClassID == LE_ITEM_CLASS_QUESTITEM
	if isQuestItem and CaerdonWardrobeConfig.Icon.ShowQuestItems then
		mogStatus = "quest"
	end

	if transmogInfo then
		if transmogInfo.isTransmog then
			if transmogInfo.needsItem then
				if not transmogInfo.isCompletionistItem then
					if transmogInfo.hasMetRequirements then
						mogStatus = "own"
					else
						mogStatus = "lowSkill"
					end
				else
					if CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem then
						if transmogInfo.hasMetRequirements then
							mogStatus = "ownPlus"
						else
							mogStatus = "lowSkillPlus"
						end
					end
				end
			elseif transmogInfo.otherNeedsItem then
				if not transmogInfo.isBindOnPickup then
					if not transmogInfo.isCompletionistItem then
						mogStatus = "other"
					else
						if CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem then
							mogStatus = "otherPlus"
						end
					end
				else
					mogStatus = "collected"
				end
			else
				mogStatus = "collected"
			end

			-- TODO: Exceptions need to be broken out
			-- TODO: Instead:  if plugin:ShouldShowNeedOtherAsInvalid() then
			if feature == "EncounterJournal" or feature == "Merchant" then
				if transmogInfo.needsItem then
					if transmogInfo.matchesLootSpec then
						if not transmogInfo.isCompletionistItem then
							mogStatus = "own"
						else
							if CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem then
								mogStatus = "ownPlus"
							end
						end
					else
						if not transmogInfo.isCompletionistItem then
							mogStatus = "otherSpecPlus"
						else
							if CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem then
								mogStatus = "otherSpec"
							end
						end
					end
				elseif transmogInfo.otherNeedsItem then
					if transmogInfo.isBindOnPickup then
						-- TODO: This leverages otherIcon.  Clean up.
						if not transmogInfo.isCompletionistItem then
							mogStatus = "other"
						else
							mogStatus = "otherPlus"
						end
					end
				end
			end
		-- else
		-- 	mogStatus = "collected"
		end

		local equipmentSets = itemData:GetEquipmentSets()
		if equipmentSets then
			if #equipmentSets > 1 then
				bindingStatus = "*" .. equipmentSets[1]
			else
				bindingStatus = equipmentSets[1]
			end
		end
	elseif bindingResult.needsItem then
		if caerdonType == CaerdonItemType.Mount then
			if not itemMinLevel or playerLevel >= itemMinLevel then
				mogStatus = "own"
			else
				mogStatus = "other"
			end
		elseif caerdonType == CaerdonItemType.BattlePet or caerdonType == CaerdonItemType.CompanionPet or caerdonType == CaerdonItemType.Toy then
			if bindingResult.unusableItem then
				mogStatus = "other"
			else
				mogStatus = "own"
			end
		elseif caerdonType == CaerdonItemType.Recipe then
			if bindingResult.unusableItem then
				if bindingResult.skillTooLow then
					mogStatus = "lowSkill"
				end
				-- Don't show these for now
				-- mogStatus = "other"
			else
				mogStatus = "own"
			end

			-- Let's just ignore the Librams for now until I decide what to do about them
			if itemID == 11732 or 
			   itemID == 11733 or
			   itemID == 11734 or 
			   itemID == 11736 or 
			   itemID == 11737 or
			   itemID == 18332 or
			   itemID == 18333 or
			   itemID == 18334 or
			   itemID == 21288 then
				if CaerdonWardrobeConfig.Icon.ShowOldExpansion.Usable then
					mogStatus = "oldexpansion"
				else
					mogStatus = nil
				end
			end
		elseif IsConduit(itemLink) then
			mogStatus = "own"
		end
	end

	if locationInfo.isBankOrBags then
		-- TODO: This is very specific to bank and bags features and addons (locationInfo) and needs pushed into those
		local bag = locationInfo.bag
		local slot = locationInfo.slot
		
		local containerID = bag
		local containerSlot = slot

		local texture, itemCount, locked, quality, readable, lootable, _ = GetContainerItemInfo(containerID, containerSlot);
		if lootable then
			local startTime, duration, isEnabled = GetContainerItemCooldown(containerID, containerSlot)
			if duration > 0 and not isEnabled then
				mogStatus = "refundable" -- Can't open yet... show timer
			else
				if bindingResult.isLocked then
					mogStatus = "locked"
				else
					mogStatus = "openable"
				end
			end
		else
			local money, itemCount, refundSec, currencyCount, hasEnchants = GetContainerItemPurchaseInfo(bag, slot, isEquipped);
			if refundSec then
				mogStatus = "refundable"
			-- elseif not bindingResult.needsItem and not transmogInfo then
			-- 	mogStatus = "collected"
			end
		end
	end

	-- TODO: Clean up - if I break item handling out to individual plugins, they can decide if it's sellable
	-- If every plugin says yes, then it is.
	if mogStatus == "collected" and 
	   item:GetCaerdonItemType() == CaerdonItemType.Equipment and
	   ItemIsSellable(itemID, itemLink) and 
	   not itemData:GetEquipmentSets() and
	   not item:GetHasUse() and
	   not item:GetSetID() and
	   not bindingResult.hasEquipEffect then
       	-- Anything that reports as the player having should be safe to sell
       	-- unless it's in an equipment set or needs to be excluded for some
		-- other reason

		-- Set up new options, so we don't change the shared one
		-- TODO: Should probably come up with a new way to pass in calculated data
		local newOptions = {}
		CaerdonAPI:MergeTable(newOptions, options)
		options = newOptions
		options.isSellable = true
	end

	if button then
		SetItemButtonMogStatus(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
		SetItemButtonBindType(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	end
end

local function ProcessOrWaitItemLink(itemLink, feature, locationInfo, button, options)
	CaerdonWardrobe:UpdateButtonLink(itemLink, feature, locationInfo, button, options)
end

CaerdonWardrobeFeatureMixin = {}
function CaerdonWardrobeFeatureMixin:GetName()
	-- Must be unique
	error("Caerdon Wardrobe: Must provide a feature name")
end

function CaerdonWardrobeFeatureMixin:Init()
	-- init and return array of frame events you'd like to receive
	error("Caerdon Wardrobe: Must provide Init implementation")
end

function CaerdonWardrobeFeatureMixin:SetTooltipItem(tooltip, item, locationInfo)
	error("Caerdon Wardrobe: Must provide SetTooltipItem implementation")
end

function CaerdonWardrobeFeatureMixin:Refresh()
	-- Primarily used for global transmog refresh when appearances learned right now
	error("Caerdon Wardrobe: Must provide Refresh implementation")
end

function CaerdonWardrobeFeatureMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	return {}
end

function CaerdonWardrobeFeatureMixin:GetDisplayInfoInternal(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	-- TODO: Temporary for merging - revisit after pushing everything into Mixins
	local showBindingStatus = not locationInfo.isBankOrBags or CaerdonWardrobeConfig.Binding.ShowStatus.BankAndBags
	local showOwnIcon = not locationInfo.isBankOrBags or CaerdonWardrobeConfig.Icon.ShowLearnable.BankAndBags
	local showOtherIcon = not locationInfo.isBankOrBags or CaerdonWardrobeConfig.Icon.ShowLearnableByOther.BankAndBags
	local showSellableIcon = not locationInfo.isBankOrBags or CaerdonWardrobeConfig.Icon.ShowSellable.BankAndBags

	local displayInfo = {
		bindingStatus = {
			shouldShow = showBindingStatus -- true
		},
		ownIcon = {
			shouldShow = showOwnIcon
		},
		otherIcon = {
			shouldShow = showOtherIcon
		},
		questIcon = {
			shouldShow = CaerdonWardrobeConfig.Icon.ShowQuestItems
		},
		oldExpansionIcon = {
			shouldShow = true
		},
		sellableIcon = {
			shouldShow = showSellableIcon
		}
	}

	CaerdonAPI:MergeTable(displayInfo, self:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus))

	-- TODO: BoA and BoE settings should be per feature
	if not CaerdonWardrobeConfig.Binding.ShowBoA and bindingStatus == L["BoA"] then
		displayInfo.bindingStatus.shouldShow = false
	end

	if not CaerdonWardrobeConfig.Binding.ShowBoE and bindingStatus == L["BoE"] then
		displayInfo.bindingStatus.shouldShow = false
	end

	return displayInfo
end

function CaerdonWardrobeFeatureMixin:OnUpdate()
	-- Called from the main frame's OnUpdate
end

function CaerdonWardrobe:RegisterFeature(mixin)
	local instance = CreateFromMixins(CaerdonWardrobeFeatureMixin, mixin)
	local name = instance:GetName()
	if not availableFeatures[name] then
		availableFeatures[name] = instance
	else
		error(format("Caerdon Wardrobe: Feature name collision: %s already exists", name))
	end
end

local function GetTooltipInfo(item)
	local tooltipInfo = {
		hasEquipEffect = false,
		isRelearn = false,
		bindingStatus = nil,
		isRetrieving = false,
		isSoulbound = false,
		isKnownSpell = false,
		isLocked = false,
		supercedingSpellNotKnown = false,
		foundRedRequirements = false,
		requiredTradeSkillMissingOrUnleveled = false,
		requiredTradeSkillTooLow = false
	}

	-- Weird bug with scanning tooltips - have to disable showing
	-- transmog info during the scan
	C_TransmogCollection.SetShowMissingSourceInItemTooltips(false)
	SetCVar("missingTransmogSourceInItemTooltips", 0)
	local originalAlwaysCompareItems = GetCVarBool("alwaysCompareItems")
	SetCVar("alwaysCompareItems", 0)

	local scanTip = CaerdonWardrobeFrameTooltip
	local numLines = scanTip:NumLines()
	for lineIndex = 1, numLines do
		local scanName = scanTip:GetName()
		local line = _G[scanName .. "TextLeft" .. lineIndex]
		local lineText = line:GetText()
		if lineText then
			-- TODO: Find a way to identify Equip Effects without tooltip scanning
			if strmatch(lineText, ITEM_SPELL_TRIGGER_ONEQUIP) then -- it has an equip effect
				tooltipInfo.hasEquipEffect = true
			end

			-- TODO: Don't like matching this hard-coded string but not sure how else
			-- to prevent the expensive books from showing as learnable when I don't
			-- know how to tell if they have recipes you need.
			local isRecipe = item:GetCaerdonItemType() == CaerdonItemType.Recipe
			if isRecipe and strmatch(lineText, L["Use: Re%-learn .*"]) then
				tooltipInfo.isRelearn = true
			end

			if not tooltipInfo.bindingStatus then
				-- Check if account bound - TODO: Is there a non-scan way?
				tooltipInfo.bindingStatus = bindTextTable[lineText]
			end

			if lineText == RETRIEVING_ITEM_INFO then
				tooltipInfo.isRetrieving = true
				break
			elseif lineText == ITEM_SOULBOUND then
				tooltipInfo.isSoulbound = true
			elseif lineText == ITEM_SPELL_KNOWN then
				tooltipInfo.isKnownSpell = true
			elseif lineText == LOCKED then
				tooltipInfo.isLocked = true
			elseif lineText == TOOLTIP_SUPERCEDING_SPELL_NOT_KNOWN then
				tooltipInfo.supercedingSpellNotKnown = true
			end

			-- TODO: Should possibly only look for "Classes:" but could have other reasons for not being usable
			local r, g, b = line:GetTextColor()
			local hex = string.format("%02x%02x%02x", r*255, g*255, b*255)
			-- TODO: Provide option to show stars on BoE recipes that aren't for current toon
			-- TODO: Surely there's a better way than checking hard-coded color values for red-like things
			if isRecipe then
				if hex == "fe1f1f" then
					tooltipInfo.foundRedRequirements = true
				end

				-- TODO: Cooking and fishing are not represented in trade skill lines right now
				-- Assuming all toons have cooking for now.

				-- TODO: Some day - look into saving toon skill lines / ranks into a DB and showing
				-- which toons could learn a recipe.

				local replaceSkill = "%w"
				
				-- Remove 1$ and 2$ from ITEM_MIN_SKILL for German at least (probably all): Benötigt %1$s (%2$d)
				local skillCheck = string.gsub(ITEM_MIN_SKILL, "1%$", "")
				skillCheck = string.gsub(skillCheck, "2%$", "")
				skillCheck = string.gsub(skillCheck, "%%s", "%(.+%)")
				skillCheck = string.gsub(skillCheck, "%(%%d%)", "%%%(%(%%d+%)%%%)")
				if strmatch(lineText, skillCheck) then
					local _, _, requiredSkill, requiredRank = string.find(lineText, skillCheck)
					local skillLines = C_TradeSkillUI.GetAllProfessionTradeSkillLines()
					for skillLineIndex = 1, #skillLines do
						local skillLineID = skillLines[skillLineIndex]
						local name, rank, maxRank, modifier, parentSkillLineID = C_TradeSkillUI.GetTradeSkillLineInfoByID(skillLineID)
						if requiredSkill == name then
							if not rank or rank < tonumber(requiredRank) then
								if not rank or rank == 0 then
									-- Toon either doesn't have profession or isn't high enough level.
									tooltipInfo.requiredTradeSkillMissingOrUnleveled = true
								elseif rank and rank > 0 then -- has skill but isn't high enough
									tooltipInfo.requiredTradeSkillTooLow = true
								end
							else
								break
							end
						end
					end
				end		
			end
		end
	end

	C_TransmogCollection.SetShowMissingSourceInItemTooltips(true)
	SetCVar("missingTransmogSourceInItemTooltips", 1)
	SetCVar("alwaysCompareItems", originalAlwaysCompareItems)

	return tooltipInfo
end

function CaerdonWardrobe:ClearButton(button)
	SetItemButtonMogStatus(button)
	SetItemButtonBindType(button)
end

function CaerdonWardrobe:UpdateButtonLink(itemLink, feature, locationInfo, button, options)
	if not itemLink then
		CaerdonWardrobe:ClearButton(button)
		return
	end

	local item = CaerdonItem:CreateFromItemLink(itemLink)
	SetItemButtonMogStatus(button, item, feature, locationInfo, options, "waiting", nil)

	local scanTip = CaerdonWardrobeFrameTooltip
	scanTip:ClearLines()
	if registeredFeatures[feature] then
		registeredFeatures[feature]:SetTooltipItem(scanTip, item, locationInfo)
	end

	-- TODO: May have to look into cancelable continue to avoid timing issues
	-- Need to figure out how to key this correctly (could have multiple of item in bags, for instance)
	-- but in cases of rapid data update (AH scroll), we don't want to update an old button
	-- Look into ContinuableContainer
	if item:IsItemEmpty() then -- BattlePet or something else - assuming item is ready.
		local tooltipInfo = GetTooltipInfo(item)

		-- This is lame, but tooltips end up not having all of their data
		-- until a round of "Set*Item" has occurred in certain cases (usually right on login).
		-- Specifically, the Equip: line was missing on a fishing pole (and other items)
		-- TODO: Move tooltip into CaerdonItem and handle in ContinueOnItemLoad if possible
		-- Probably can't store the actual data there (need to retrieve live) due to changing info like locked status

		-- Trying without the retry if possible...
		-- if not button.isCaerdonRetry or tooltipInfo.isRetrieving then
		-- 	button.isCaerdonRetry = true
		-- 	QueueProcessItem(itemLink, feature, locationInfo, button, options)
		-- 	return
		-- end	
		if tooltipInfo.isRetrieving then
			QueueProcessItem(itemLink, feature, locationInfo, button, options)
			return
		end	
	
		SetItemButtonMogStatus(button)
		ProcessItem(item, feature, locationInfo, button, options, tooltipInfo)
	else
		item:ContinueOnItemLoad(function ()
			local tooltipInfo = GetTooltipInfo(item)
			-- Trying without the retry if possible...
			-- if not button.isCaerdonRetry or tooltipInfo.isRetrieving then
			-- 	button.isCaerdonRetry = true
			-- 	QueueProcessItem(itemLink, feature, locationInfo, button, options)
			-- 	return
			-- end	
			if tooltipInfo.isRetrieving then
				QueueProcessItem(itemLink, feature, locationInfo, button, options)
				return
			end	
	
			SetItemButtonMogStatus(button)
			ProcessItem(item, feature, locationInfo, button, options, tooltipInfo)
		end)
	end
end

function CaerdonWardrobeMixin:OnEvent(event, ...)
	local handler = self[event]
	if(handler) then
		handler(self, ...)
	end

	for name, instance in pairs(registeredFeatures) do
		handler = instance[event]
		if(handler) then
			handler(instance, ...)
		end
	end
end

function CaerdonWardrobeMixin:OnUpdate(elapsed)
	local name, instance
	for name, instance in pairs(registeredFeatures) do
		instance:OnUpdate(elapsed)
	end
end

function NS:GetDefaultConfig()
	return {
		Version = 8,
		
		Icon = {
			EnableAnimation = true,
			Position = "TOPLEFT",

			ShowLearnable = {
				BankAndBags = true,
				GuildBank = true,
				Merchant = true,
				Auction = true,
				SameLookDifferentItem = false
			},

			ShowLearnableByOther = {
				BankAndBags = true,
				GuildBank = true,
				Merchant = true,
				Auction = true,
				EncounterJournal = true,
				SameLookDifferentItem = false
			},

			ShowSellable = {
				BankAndBags = true,
				GuildBank = false
			},

			ShowOldExpansion = {
				Unknown = false,
				Reagents = true,
				Usable = false,
				Other = false,
				Auction = true
			},

			ShowQuestItems = true
		},

		Binding = {
			ShowStatus = {
				BankAndBags = true,
				GuildBank = true,
				Merchant = true
			},

			ShowBoA = true,
			ShowBoE = true,
			ShowGearSets = true,
			ShowGearSetsAsIcon = false,
			Position = "BOTTOM"
		}
	}
end

local function ProcessSettings()
	if not CaerdonWardrobeConfig or CaerdonWardrobeConfig.Version ~= NS:GetDefaultConfig().Version then
		CaerdonWardrobeConfig = NS:GetDefaultConfig()
	else
		-- TODO: Upgrade handling needs to be smarter - coordinate with config update
		CaerdonWardrobeConfig.Debug = CaerdonWardrobeConfig.Debug or { Enabled = false }
	end
end

function CaerdonWardrobeMixin:PLAYER_LOGOUT()
end

function CaerdonWardrobeMixin:ADDON_LOADED(name)
	if name == ADDON_NAME then
		local name, instance
		for name, instance in pairs(availableFeatures) do
			registeredFeatures[name] = instance
			local instanceEvents = instance:Init(self)
			if instanceEvents then
				for i = 1, #instanceEvents do
					-- TODO: Hook up to debugging
					self:RegisterEvent(instanceEvents[i])
				end
			end
		end
	
		ProcessSettings()
		NS:FireConfigLoaded()
	-- elseif name == "TradeSkillMaster" then
	-- 	print("HOOKING TSM")
	-- 	hooksecurefunc (TSM.UI.AuctionScrollingTable, "_SetRowData", function (self, row, data)
	-- 		print("Row: " .. row:GetField("auctionId"))
	-- 	end)
	end
end

local refreshTimer
function CaerdonWardrobe:RefreshItems()
	if refreshTimer then
		refreshTimer:Cancel()
	end

	refreshTimer = C_Timer.NewTimer(0.1, function ()
		local name, instance
		for name, instance in pairs(registeredFeatures) do
			instance:Refresh()
		end
	end, 1)
end

local function OnContainerFrameUpdateSearchResults(frame)
	local id = frame:GetID();
	local name = frame:GetName().."Item";
	local itemButton;
	local _, isFiltered;
	
	for i=1, frame.size, 1 do
		itemButton = _G[name..i] or frame["Item"..i];
		_, _, _, _, _, _, _, isFiltered = GetContainerItemInfo(id, itemButton:GetID())
		SetItemButtonMogStatusFilter(itemButton, isFiltered)
	end
end

hooksecurefunc("ContainerFrame_UpdateSearchResults", OnContainerFrameUpdateSearchResults)

local function OnEquipPendingItem()
	-- TODO: Bit of a hack... wait a bit and then update...
	--       Need to figure out a better way.  Otherwise,
	--		 you end up with BoE markers on things you've put on.
	C_Timer.After(1, function() CaerdonWardrobe:RefreshItems() end)
end

hooksecurefunc("EquipPendingItem", OnEquipPendingItem)

function CaerdonWardrobeMixin:UNIT_SPELLCAST_SUCCEEDED(unitTarget, castGUID, spellID)
	if unitTarget == "player" then
		-- Tracking unlock spells to know to refresh
		-- May have to add some other abilities but this is a good place to start.
		if spellID == 1804 then
			CaerdonWardrobe:RefreshItems(true)
		end
	end
end

function CaerdonWardrobeMixin:TRANSMOG_COLLECTION_UPDATED()
	CaerdonWardrobe:RefreshItems()
end

function CaerdonWardrobeMixin:EQUIPMENT_SETS_CHANGED()
	CaerdonWardrobe:RefreshItems()
end

function CaerdonWardrobeMixin:UPDATE_EXPANSION_LEVEL()
	-- Can change while logged in!
	CaerdonWardrobe:RefreshItems()
end

local configFrame
local isConfigLoaded = false

function NS:RegisterConfigFrame(frame)
	configFrame = frame
	if isConfigLoaded then
		NS:FireConfigLoaded()
	end
end

function NS:FireConfigLoaded()
	isConfigLoaded = true
	if configFrame then
		configFrame:OnConfigLoaded()
	end
end
