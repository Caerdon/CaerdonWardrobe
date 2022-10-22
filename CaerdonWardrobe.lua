local DEBUG_ENABLED = false
-- local DEBUG_ITEM = 82800
local ADDON_NAME, NS = ...
local L = NS.L

BINDING_HEADER_CAERDON = L["Caerdon Addons"]
BINDING_NAME_COPYMOUSEOVERLINK = L["Copy Mouseover Link"]
BINDING_NAME_PRINTMOUSEOVERLINKDETAILS = L["Print Mouseover Link Details"]

local availableFeatures = {}
local registeredFeatures = {}

CaerdonWardrobeMixin = {}

function CaerdonWardrobeMixin:OnLoad()
	AddonCompartmentFrame:RegisterAddon({
		text = 'Caerdon Wardrobe',
		func = function ()
			print("Do your thing here")
		end,
		icon = "Interface\\Store\\category-icon-featured"
	})

	self.waitingToProcess = {}

	self:RegisterEvent "ADDON_LOADED"
	self:RegisterEvent "PLAYER_LOGOUT"
	self:RegisterEvent "TRANSMOG_COLLECTION_UPDATED"
	self:RegisterEvent "EQUIPMENT_SETS_CHANGED"
	self:RegisterEvent "UPDATE_EXPANSION_LEVEL"

	hooksecurefunc("EquipPendingItem", function(...) self:OnEquipPendingItem(...) end)
	hooksecurefunc(BankFrame, "UpdateSearchResults", function(...) self:OnContainerFrameUpdateSearchResults(...) end)
end

local bindTextTable = {
	[ITEM_ACCOUNTBOUND]        = L["BoA"],
	[ITEM_BNETACCOUNTBOUND]    = L["BoA"],
	[ITEM_BIND_TO_ACCOUNT]     = L["BoA"],
	[ITEM_BIND_TO_BNETACCOUNT] = L["BoA"],
	-- [ITEM_BIND_ON_EQUIP]       = L["BoE"],
	-- [ITEM_BIND_ON_USE]         = L["BoE"]
}

local function IsCollectibleLink(item)
	local caerdonType = item:GetCaerdonItemType()
	return caerdonType == CaerdonItemType.BattlePet or
		caerdonType == CaerdonItemType.CompanionPet or
		caerdonType == CaerdonItemType.Mount or
		caerdonType == CaerdonItemType.Recipe or
		caerdonType == CaerdonItemType.Toy
end

local equipLocations = {}

function CaerdonWardrobeMixin:GetBindingStatus(item, feature, locationInfo, button, options, tooltipData)
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
	local isOpenable = false
	
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

	if item:IsSoulbound() then
		isBindOnPickup = true
		bindingStatus = nil
	end

	if tooltipData then
		hasEquipEffect = tooltipData.hasEquipEffect

		if tooltipData.isRelearn then
			needsItem = false
		end

		if not bindingStatus then
			bindingStatus = tooltipData.bindingStatus
		end

		if tooltipData.isKnownSpell then
			needsItem = false
		end

		isLocked = tooltipData.isLocked
		isOpenable = tooltipData.isOpenable

		if tooltipData.supercedingSpellNotKnown then
			unusableItem = true
			skillTooLow = true
		end

		if tooltipData.foundRedRequirements then
			unusableItem = true
			skillTooLow = true
		end

		-- TODO: Can we scan the embedded item tooltip? Probably need to do something like EmbeddedItemTooltip_SetItemByID
		-- This may only matter for recipes, so I may have to use LibRecipes if I can't get the recipe info for the created item.
		if tooltipData.requiredTradeSkillMissingOrUnleveled then
			unusableItem = true
			-- if isBindOnPickup then -- assume all unknown not needed for now
				needsItem = false
			-- end
		else
			if tooltipData.requiredTradeSkillTooLow then
				unusableItem = true
				skillTooLow = true
				needsItem = true -- still need this but need to rank up
			else
				needsItem = true
			end
		end
	end

	if not bindingStatus and (isCollectionItem or isLocked or isOpenable) then
		-- TODO: This can be useful on everything but needs to be configurable per type before doing so
		if not isBindOnPickup then
			bindingStatus = "BoE"
		end
	end

	if caerdonType == CaerdonItemType.Conduit then
		local conduitInfo = itemData:GetConduitInfo()
		needsItem = conduitInfo.needsItem
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

local ICON_PROMINENT_SIZE = 20
local ICON_SIZE_DIFFERENTIAL = 0.8

function CaerdonWardrobeMixin:SetStatusIconPosition(icon, button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	if not item then return end

	-- Scaling values if the icon is different than prominent-sized
	local iconWidth, iconHeight = icon:GetSize()
	local xAdjust = iconWidth / ICON_PROMINENT_SIZE
	local yAdjust = iconHeight / ICON_PROMINENT_SIZE

	local statusScale = options.statusScale or 1
	local statusPosition = options.overrideStatusPosition or CaerdonWardrobeConfig.Icon.Position
	local xOffset =  4 * xAdjust
	if statusPosition == "TOP" or statusPosition == "BOTTOM" then
		xOffset = 0
	end

	if options.statusOffsetX ~= nil then
		xOffset = options.statusOffsetX
	end

	local yOffset = 4 * yAdjust
	if statusPosition == "LEFT" or statusPosition == "RIGHT" then
		yOffset = 0
	end

	if options.statusOffsetY ~= nil then
		yOffset = options.statusOffsetY
	end

	if string.find(statusPosition, "TOP") then
		yOffset = yOffset * -1
	end

	if string.find(statusPosition, "RIGHT") then
		xOffset = xOffset * -1
	end

	icon:ClearAllPoints()
	icon:SetPoint("CENTER", button.caerdonButton, statusPosition, xOffset, yOffset)
end

function CaerdonWardrobeMixin:AddRotation(group, order, degrees, duration, smoothing, startDelay, endDelay)
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

function CaerdonWardrobeMixin:SetItemButtonMogStatusFilter(originalButton, isFiltered)
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

		local bindsOnText = button.bindsOnText
		if bindsOnText then
			if isFiltered then
				bindsOnText:SetAlpha(0.3)
			else
				bindsOnText:SetAlpha(1.0)
			end
		end
	end
end

function CaerdonWardrobeMixin:SetItemButtonStatus(originalButton, item, feature, locationInfo, options, status, bindingStatus)
	local button = originalButton.caerdonButton

	if not button then
		button = CreateFrame("Frame", nil, originalButton)
		button.searchOverlay = originalButton.searchOverlay
		originalButton.caerdonButton = button
	end

	-- Make sure it's sitting in front of the frame it's going to overlay
	local levelCheckFrame = originalButton
	if options and options.relativeFrame then
		if options.relativeFrame:GetObjectType() == "Texture" then
			levelCheckFrame = options.relativeFrame:GetParent()
		else
			levelCheckFrame = options.relativeFrame
		end
	end

	if levelCheckFrame then
		button:SetFrameStrata(levelCheckFrame:GetFrameStrata())
		button:SetFrameLevel(levelCheckFrame:GetFrameLevel() + 1)
	end

	button:ClearAllPoints()
	button:SetSize(0,0)

	if options and options.relativeFrame then
		button:SetAllPoints(options.relativeFrame)
	else
		button:SetAllPoints(originalButton)
	end

	-- Had some addons messing with frame level resulting in this getting covered by the parent button.
	-- Haven't seen any negative issues with bumping it up, yet, but keep an eye on it if
	-- the status icon overlaps something it shouldn't.
	-- NOTE: Added logic above that hopefully addresses this more sanely...
	-- button:SetFrameLevel(originalButton:GetFrameLevel() + 100)

	local mogStatus = button.mogStatus
	local mogAnim = button.mogAnim
	local iconPosition, showSellables, isSellable

	if options then 
		showSellables = options.showSellables
		isSellable = options.isSellable
	else
		options = {}
	end

	if not status then
		if mogAnim and mogAnim:IsPlaying() then
			mogAnim:Stop()
		end
	end

	if not mogStatus then
		mogStatus = button:CreateTexture(nil, "ARTWORK", nil, 1)
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

			self:AddRotation(mogAnim, 1, 360, 0.5, "IN_OUT")

		    mogAnim:SetLooping("REPEAT")
			button.mogAnim = mogAnim
			button.isWaitingIcon = true
		end
	else
		if status == "own" or status == "ownPlus" or status == "otherSpec" or status == "otherSpecPlus" or status == "refundable" or status == "openable" or status == "locked" or status == "upgrade" or status == "readyToCombine" then
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

				self:AddRotation(mogAnim, 1, 110, 0.2, "OUT")
				self:AddRotation(mogAnim, 2, -155, 0.2, "OUT")
				self:AddRotation(mogAnim, 3, 60, 0.2, "OUT")
				self:AddRotation(mogAnim, 4, -15, 0.1, "OUT", 0, 2)

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

	local displayInfo
	if feature then
		displayInfo = feature:GetDisplayInfoInternal(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	end

	local alpha = 1
	mogStatus:SetVertexColor(1, 1, 1)
	mogStatus:SetTexture("")
	mogStatus:SetTexCoord(0, 1, 0, 1)

	local isProminent = false

	-- TODO: Possible gear set indicators
	-- MINIMAP / TempleofKotmogu_ball_cyan.PNG
	-- TempleofKotmogu_ball_green.PNG
	-- TempleofKotmogu_ball_orange.PNG
	-- TempleofKotmogu_ball_purple.PNG
	-- MINIMAP/TRACKING/OBJECTICONS.PNG

	-- TODO: Add options to hide these statuses
	if status == "refundable" then
		alpha = 0.9
		mogStatus:SetTexture("Interface\\COMMON\\mini-hourglass")
	elseif status == "openable" then
		isProminent = true
		mogStatus:SetTexCoord(16/64, 48/64, 16/64, 48/64)
		mogStatus:SetTexture("Interface\\Store\\category-icon-free")
	elseif status == "readable" then
		mogStatus:SetTexCoord(16/64, 48/64, 16/64, 48/64)
		mogStatus:SetTexture("Interface\\Store\\category-icon-services")
	elseif status == "lowSkill" or status == "lowSkillPlus" then
		mogStatus:SetTexCoord(6/64, 58/64, 6/64, 58/64)
		mogStatus:SetTexture("Interface\\WorldMap\\Gear_64Grey")
		if status == "lowSkillPlus" then
			mogStatus:SetVertexColor(0.4, 1, 0)
		end
		-- mogStatus:SetTexture("Interface\\QUESTFRAME\\SkillUp-BG")
		-- mogStatus:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
		-- mogStatus:SetTexture("Interface\\Buttons\\JumpUpArrow")
	elseif status == "upgrade" then
		isProminent = false
		mogStatus:SetTexCoord(-1/32, 33/32, -1/32, 33/32)
		mogStatus:SetTexture("Interface\\Buttons\\JumpUpArrow")
	elseif status == "locked" then
		isProminent = true
		mogStatus:SetTexCoord(16/64, 48/64, 16/64, 48/64)
		mogStatus:SetTexture("Interface\\Store\\category-icon-key")
	elseif status == "oldexpansion" and displayInfo and displayInfo.oldExpansionIcon.shouldShow then
		alpha = 0.9
		mogStatus:SetTexCoord(16/64, 48/64, 16/64, 48/64)
		mogStatus:SetTexture("Interface\\Store\\category-icon-wow")
	elseif status == "needForProfession" then
		-- TODO: Need to improve to pass data for icon determination.
		isProminent = true
		if displayInfo and displayInfo.ownIcon.shouldShow then
			mogStatus:SetTexCoord(16/64, 48/64, 16/64, 48/64)
			mogStatus:SetTexture("Interface\\Store\\category-icon-featured")
			-- mogStatus:SetTexture("Interface\\WorldMap\\worldquest-icon-enchanting")
			if status == "ownPlus" then
				mogStatus:SetVertexColor(0.4, 1, 0)
			end
		end
	elseif status == "canCombine" then
		isProminent = true
		if displayInfo and displayInfo.ownIcon.shouldShow then -- TODO: Add separate config for combine icon
			-- mogStatus:SetTexCoord(16/64, 48/64, 16/64, 48/64)
			-- mogStatus:SetTexture("Interface\\PaperDollInfoFrame\\Character-Plus")
			mogStatus:SetTexture("Interface\\BUTTONS\\UI-PlusButton-Up")
			-- if status == "ownPlus" then
			-- 	mogStatus:SetVertexColor(0.4, 1, 0)
			-- end
		end
	elseif status == "readyToCombine" then
		-- isProminent = true
		if displayInfo and displayInfo.ownIcon.shouldShow then -- TODO: Add separate config for combine icon
			alpha = 0.9
			mogStatus:SetTexCoord(16/64, 48/64, 16/64, 48/64)
			mogStatus:SetTexture("Interface\\HELPFRAME\\ReportLagIcon-AuctionHouse")
			-- if status == "ownPlus" then
			-- 	mogStatus:SetVertexColor(0.4, 1, 0)
			-- end
		end
	elseif status == "own" or status == "ownPlus" then
		isProminent = true
		if displayInfo and displayInfo.ownIcon.shouldShow then
			mogStatus:SetTexCoord(16/64, 48/64, 16/64, 48/64)
			mogStatus:SetTexture("Interface\\Store\\category-icon-featured")
			if status == "ownPlus" then
				mogStatus:SetVertexColor(0.4, 1, 0)
			end
		end
	elseif status == "other" or status == "otherPlus" then
		isProminent = true
		if displayInfo and displayInfo.otherIcon.shouldShow then
			mogStatus:SetTexCoord(16/64, 48/64, 16/64, 48/64)
			mogStatus:SetTexture("Interface\\Store\\category-icon-placeholder")
			if status == "otherPlus" then
				mogStatus:SetVertexColor(0.4, 1, 0)
			end
		end
	elseif status == "otherNoLoot" or status == "otherPlusNoLoot" then
		if displayInfo and displayInfo.otherIcon.shouldShow then
			mogStatus:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
			if status == "otherPlus" then
				mogStatus:SetVertexColor(0.4, 1, 0)
			end
		end
	elseif status == "otherSpec" or status == "otherSpecPlus" then
		isProminent = true
		if displayInfo and displayInfo.otherIcon.shouldShow then
			mogStatus:SetTexture("Interface\\COMMON\\icon-noloot")
			if status == "otherSpecPlus" then
				mogStatus:SetVertexColor(0.4, 1, 0)
			end
		end
	elseif status == "quest" and displayInfo and displayInfo.questIcon.shouldShow then
		mogStatus:SetTexCoord(-1/32, 33/32, -1/32, 33/32)
		mogStatus:SetTexture("Interface\\MINIMAP\\MapQuestHub_Icon32")
	elseif status == "collected" then
		if not IsGearSetStatus(bindingStatus, item) and showSellables and isSellable and displayInfo and displayInfo.sellableIcon.shouldShow then -- it's known and can be sold
			alpha = 0.9
			mogStatus:SetTexCoord(16/64, 48/64, 16/64, 48/64)
			mogStatus:SetTexture("Interface\\Store\\category-icon-bag")
		elseif IsGearSetStatus(bindingStatus, item) and CaerdonWardrobeConfig.Binding.ShowGearSetsAsIcon then
			mogStatus:SetTexCoord(16/64, 48/64, 16/64, 48/64)
			mogStatus:SetTexture("Interface\\Store\\category-icon-clothes")
		end
	elseif status == "waiting" then
		alpha = 0.5
		mogStatus:SetTexCoord(16/64, 48/64, 16/64, 48/64)
		mogStatus:SetTexture("Interface\\Common\\StreamCircle")
	elseif IsGearSetStatus(bindingStatus, item) and CaerdonWardrobeConfig.Binding.ShowGearSetsAsIcon then
		mogStatus:SetTexCoord(16/64, 48/64, 16/64, 48/64)
		mogStatus:SetTexture("Interface\\Store\\category-icon-clothes")
	end

	local iconSize = ICON_PROMINENT_SIZE
	if options.statusProminentSize then
		iconSize = options.statusProminentSize
	end

	if isProminent then
		mogStatus:SetSize(iconSize, iconSize)
	else
		iconSize = iconSize * ICON_SIZE_DIFFERENTIAL
		mogStatus:SetSize(iconSize, iconSize)
	end

	self:SetStatusIconPosition(mogStatus, originalButton, item, feature, locationInfo, options, status, bindingStatus)

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

function CaerdonWardrobeMixin:SetItemButtonBindType(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	local caerdonButton = button.caerdonButton

	local bindsOnText = caerdonButton and caerdonButton.bindsOnText
	if bindsOnText then
		bindsOnText:SetText("")
	end

	if not feature then return end

	local displayInfo = feature:GetDisplayInfoInternal(button, item, feature, locationInfo, options, mogStatus, bindingStatus)

	if not bindingStatus or not displayInfo.bindingStatus.shouldShow then
		return
	end

	if not bindsOnText then
		bindsOnText = caerdonButton:CreateFontString(nil, "ARTWORK", "SystemFont_Outline_Small")
		caerdonButton.bindsOnText = bindsOnText
	end

	local bindingText = ""
	if IsGearSetStatus(bindingStatus) then -- is gear set
		if CaerdonWardrobeConfig.Binding.ShowGearSets then
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

	local bindingScale = options.bindingScale or 1
	local bindingPosition = options.overrideBindingPosition or CaerdonWardrobeConfig.Binding.Position
	local xOffset = 1
	if options.bindingOffsetX ~= nil then
		xOffset = options.bindingOffsetX
	end

	local yOffset = 2
	if options.bindingOffsetY ~= nil then
		yOffset = options.bindingOffsetY
	end

	local hasCount = (button.count and button.count > 1) or options.hasCount
	
	if string.find(bindingPosition, "BOTTOM") then
		if hasCount then
			yOffset = options.itemCountOffset or 15
		end
	end

	if string.find(bindingPosition, "TOP") then
		yOffset = yOffset * -1
	end

	if string.find(bindingPosition, "RIGHT") then
		xOffset = xOffset * -1
	end

	bindsOnText:SetPoint(bindingPosition, xOffset, yOffset)

	if(options.bindingScale) then
		bindsOnText:SetScale(options.bindingScale)
	end
end

function CaerdonWardrobeMixin:ItemIsSellable(itemID, itemLink)
	local isSellable = itemID ~= nil
	if itemID == 23192 then -- Tabard of the Scarlet Crusade needs to be worn for a vendor at Darkmoon Faire
		isSellable = false
	elseif itemID == 116916 then -- Gorepetal's Gentle Grasp allows faster herbalism in Draenor
		isSellable = false
	end
	return isSellable
end

function CaerdonWardrobeMixin:ProcessItem(button, item, feature, locationInfo, options, tooltipData)
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

	local bindingResult = self:GetBindingStatus(item, feature, locationInfo, button, options, tooltipData)
	local bindingStatus = bindingResult.bindingStatus

	local itemName, itemLinkInfo, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
	itemEquipLoc, iconFileDataID, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID, 
	isCraftingReagent = GetItemInfo(itemLink)

	local playerLevel = UnitLevel("player")

	if not IsCollectibleLink(item) and caerdonType ~= CaerdonItemType.Conduit then
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

	local isQuestItem = itemClassID == Enum.ItemClass.Questitem
	if isQuestItem and CaerdonWardrobeConfig.Icon.ShowQuestItems then
		mogStatus = "quest"
	end

	if caerdonType == CaerdonItemType.Equipment then
		local transmogInfo = itemData:GetTransmogInfo()
		if transmogInfo then
			if transmogInfo.isTransmog then
				if transmogInfo.needsItem then
					if not transmogInfo.isCompletionistItem then
						if transmogInfo.hasMetRequirements and not tooltipData.foundRedRequirements then
							mogStatus = "own"
						else
							mogStatus = "lowSkill"
						end
					else
						if CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem then
							if transmogInfo.hasMetRequirements and not tooltipData.foundRedRequirements then
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
					if transmogInfo.hasMetRequirements then
						mogStatus = "collected"
					-- Don't mark as lowSkill for equipment if it's known but not the right level... too much noise
					-- else
					-- 	mogStatus = "lowSkill"
					end
				end

				-- TODO: Exceptions need to be broken out
				-- TODO: Instead:  if plugin:ShouldShowNeedOtherAsInvalid() then
				if feature:GetName() == "EncounterJournal" or feature:GetName() == "Merchant" or feature:GetName() == "CustomerOrders" then
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
							if not transmogInfo.isCompletionistItem then
								mogStatus = "otherNoLoot"
							else
								mogStatus = "otherPlusNoLoot"
							end
						end
					end
				end
			else
				if not transmogInfo.hasMetRequirements then
					mogStatus = "lowSkill"
				else
					mogStatus = "collected"
				end
			end

			local equipmentSets = itemData:GetEquipmentSets()
			if equipmentSets then
				if #equipmentSets > 1 then
					bindingStatus = "*" .. equipmentSets[1]
				else
					bindingStatus = equipmentSets[1]
				end
			else
				if mogStatus == "collected" and 
				self:ItemIsSellable(itemID, itemLink) and 
				not item:GetHasUse() and
				not item:GetSetID() and
				not bindingResult.hasEquipEffect then
					-- Set up new options, so we don't change the shared one
					-- TODO: Should probably come up with a new way to pass in calculated data
					local newOptions = {}
					CaerdonAPI:MergeTable(newOptions, options)
					options = newOptions
					options.isSellable = true
				end
			end
		end
	elseif caerdonType == CaerdonItemType.CompanionPet or caerdonType == CaerdonItemType.BattlePet then
		local petInfo = 
			(caerdonType == CaerdonItemType.CompanionPet and itemData:GetCompanionPetInfo()) or
			(caerdonType == CaerdonItemType.BattlePet and itemData:GetBattlePetInfo())
		if petInfo.needsItem then
			if bindingResult.unusableItem then
				mogStatus = "other"
			else
				mogStatus = "own"
			end
		end
	elseif caerdonType == CaerdonItemType.Mount then
		local mountInfo = itemData:GetMountInfo()
		if mountInfo.needsItem then
			local factionGroup = nil
			local playerFactionGroup = nil
			if mountInfo.isFactionSpecific then
				factionGroup = PLAYER_FACTION_GROUP[mountInfo.factionID]
				playerFactionGroup = UnitFactionGroup("player")
			end

			if (not itemMinLevel or playerLevel >= itemMinLevel) and (factionGroup == playerFactionGroup) then
				mogStatus = "own"
			else
				mogStatus = "other"
			end
		end
	elseif caerdonType == CaerdonItemType.Toy then
		local toyInfo = itemData:GetToyInfo()
		if toyInfo.needsItem then
			mogStatus = "own"
		else
			mogStatus = "collected"
			-- TODO: This is used a few times... need to fix to pass in dynamic data
			local newOptions = {}
			CaerdonAPI:MergeTable(newOptions, options)
			options = newOptions
			options.isSellable = true
		end
	elseif caerdonType == CaerdonItemType.Profession then
		local professionInfo = itemData:GetProfessionInfo()
		if professionInfo.needsItem then
			mogStatus = "needForProfession"
		end
	elseif caerdonType == CaerdonItemType.Consumable then
		if tooltipData.canCombine then
			mogStatus = "canCombine"
			if tooltipData.readyToCombine then
				mogStatus = "readyToCombine"
			end
		elseif tooltipData.canLearn then
			if bindingResult.skillTooLow then
				mogStatus = "lowSkill"
			else
				mogStatus = "own"
			end
		end
	elseif tooltipData.canLearn then
		if bindingResult.skillTooLow then
			mogStatus = "lowSkill"
		else
			mogStatus = "own"
		end
	elseif bindingResult.needsItem then
		if caerdonType == CaerdonItemType.Recipe then
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
		elseif caerdonType == CaerdonItemType.Conduit then
			local conduitInfo = itemData:GetConduitInfo()
			if conduitInfo.isUpgrade then
				mogStatus = "upgrade"
			else
				mogStatus = "own"
			end
		end
	end

	if item:HasItemLocationBankOrBags() then
		local itemLocation = item:GetItemLocation()
		local bag, slot = itemLocation:GetBagAndSlot()
		
		local containerID = bag
		local containerSlot = slot

		local texture, itemCount, locked, quality, readable, lootable
		if C_Container and C_Container.GetContainerItemInfo then
			local containerItemInfo = C_Container.GetContainerItemInfo(containerID, containerSlot)
			itemCount = containerItemInfo.stackCount
			locked = containerItemInfo.isLocked
			quality = containerItemInfo.quality
			readable = containerItemInfo.isReadable
			lootable = containerItemInfo.hasLoot
		else 
			texture, itemCount, locked, quality, readable, lootable, _ = GetContainerItemInfo(containerID, containerSlot)
		end

		if lootable then
			local startTime, duration, isEnabled
			if C_Container and C_Container.GetContainerItemCooldown then
				startTime, duration, isEnabled = C_Container.GetContainerItemCooldown(containerID, containerSlot)
			else
				startTime, duration, isEnabled = GetContainerItemCooldown(containerID, containerSlot)
			end
			if duration > 0 and not isEnabled then
				mogStatus = "refundable" -- Can't open yet... show timer
			else
				if bindingResult.isLocked then
					mogStatus = "locked"
				else
					mogStatus = "openable"
				end
			end
		elseif readable then
			mogStatus = "readable"
		else
			local isEquipped = false
			local money, itemCount, refundSec, currencyCount, hasEnchants
			if C_Container and C_Container.GetContainerItemPurchaseInfo then
				money, itemCount, refundSec, currencyCount, hasEnchants = C_Container.GetContainerItemPurchaseInfo(bag, slot, isEquipped)
			else
				money, itemCount, refundSec, currencyCount, hasEnchants = GetContainerItemPurchaseInfo(bag, slot, isEquipped)
			end
			if refundSec then
				mogStatus = "refundable"
			end
		end
	end

	if button then
		self:SetItemButtonStatus(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
		self:SetItemButtonBindType(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	end
end

function CaerdonWardrobeMixin:RegisterFeature(mixin)
	local instance = CreateFromMixins(CaerdonWardrobeFeatureMixin, mixin)
	local name = instance:GetName()
	if not availableFeatures[name] then
		availableFeatures[name] = instance
	else
		error(format("Caerdon Wardrobe: Feature name collision: %s already exists", name))
	end
end

function CaerdonWardrobeMixin:GetTooltipData(item, feature, locationInfo)
	local tooltipData = {
		canLearn = false,
		canCombine = false,
		hasEquipEffect = false,
		isRelearn = false,
		bindingStatus = nil,
		isRetrieving = false,
		isSoulbound = false,
		isKnownSpell = false,
		isLocked = false,
		isOpenable = false,
		supercedingSpellNotKnown = false,
		foundRedRequirements = false,
		requiredTradeSkillMissingOrUnleveled = false,
		requiredTradeSkillTooLow = false
	}

	-- SetCVar("missingTransmogSourceInItemTooltips", 0)

	local data = C_TooltipInfo and feature:GetTooltipData(item, locationInfo) or nil
	if data then
		local isBattlePetShown = BattlePetTooltip:IsShown()
		local lines = data and data.lines or {}
		for lineIndex, line in ipairs(data.lines) do
			local args = {}
			for argIndex, arg in ipairs(line.args) do
				args[arg.field] = arg.stringVal or arg.intVal or arg.floatVal or arg.boolVal or arg.colorVal or arg.guidVal
			end

			if args.type == Enum.TooltipDataLineType.None then
				local lineText = args.leftText
				if lineText then
					-- TODO: Find a way to identify Equip Effects without tooltip scanning
					if strmatch(lineText, ITEM_SPELL_TRIGGER_ONEQUIP) then -- it has an equip effect
						tooltipData.hasEquipEffect = true
					end

					local isRecipe = item:GetCaerdonItemType() == CaerdonItemType.Recipe
					-- if isRecipe then
						-- TODO: Don't like matching this hard-coded string but not sure how else
						-- to prevent the expensive books from showing as learnable when I don't
						-- know how to tell if they have recipes you need.
						if strmatch(lineText, L["Use: Re%-learn .*"]) then
							tooltipData.isRelearn = true
						end
						

						-- TODO: Some day - look into saving toon skill lines / ranks into a DB and showing
						-- which toons could learn a recipe.

						local replaceSkill = "%w"
						
						-- Remove 1$ and 2$ from ITEM_MIN_SKILL for German at least (probably all): Benötigt %1$s (%2$d)
						local skillCheck = string.gsub(ITEM_MIN_SKILL, "1%$", "")
						skillCheck = string.gsub(skillCheck, "2%$", "")
						skillCheck = string.gsub(skillCheck, "%%s", "%(.+%)")
						if GetLocale() == "zhCN" then
							skillCheck = string.gsub(skillCheck, "（%%d）", "（%(%%d+%)）")
						else
							skillCheck = string.gsub(skillCheck, "%(%%d%)", "%%%(%(%%d+%)%%%)")
						end
						if strmatch(lineText, skillCheck) then
							local _, _, requiredSkill, requiredRank = string.find(lineText, skillCheck)

							local hasSkillLine, meetsMinRank = CaerdonRecipe:GetPlayerSkillInfo(requiredSkill, requiredRank)

							tooltipData.requiredTradeSkillMissingOrUnleveled = not hasSkillLine
							tooltipData.requiredTradeSkillTooLow = hasSkillLine and not meetsMinRank

							if not hasSkillLine then
								tooltipData.canLearn = false
							end
						end		
					-- end

					if item:GetCaerdonItemType() == CaerdonItemType.Consumable and item:HasItemLocation() then
						local location = item:GetItemLocation()
						local maxStackCount = C_Item.GetItemMaxStackSize(location)
						local currentStackCount = C_Item.GetStackCount(location)
				
						local combineCount = tonumber((strmatch(lineText, L["Use: Combine (%d+)"]) or 0))
						if combineCount > 1 then
							tooltipData.canCombine = true
							if combineCount <= currentStackCount then
								tooltipData.readyToCombine = true
							end
						end
					end

					if not tooltipData.bindingStatus then
						-- Check if account bound - TODO: Is there a non-scan way?
						tooltipData.bindingStatus = bindTextTable[lineText]
					end

					if strmatch(lineText, L["Use: Grants (%d+) reputation"]) then
						tooltipData.canLearn = true
					elseif strmatch(lineText, L["Use: Marks your map with the location"]) then
						tooltipData.canLearn = true
					elseif strmatch(lineText, L["Use: Unlocks this customization"]) then
						tooltipData.canLearn = true
					elseif strmatch(lineText, L["Use: Study to increase your"]) then
						tooltipData.canLearn = true
					elseif lineText == RETRIEVING_ITEM_INFO then
						tooltipData.isRetrieving = true
						break
					elseif lineText == ITEM_SOULBOUND then
						tooltipData.isSoulbound = true
					elseif lineText == ITEM_SPELL_KNOWN then
						tooltipData.isKnownSpell = true
					elseif lineText == LOCKED then
						tooltipData.isLocked = true
					elseif lineText == ITEM_OPENABLE then
						tooltipData.isOpenable = true
					elseif lineText == TOOLTIP_SUPERCEDING_SPELL_NOT_KNOWN then
						tooltipData.supercedingSpellNotKnown = true
					end
				end

					local hex = args.leftColor:GenerateHexColor()
					-- TODO: Generated hex color includes alpha value so need to check for full red.
					-- TODO: Provide option to show stars on BoE recipes that aren't for current toon
					-- TODO: Surely there's a better way than checking hard-coded color values for red-like things
					-- if hex == "fe1f1f" then -- TODO: this was old value... check to see if still needed for anything
					if hex == "ffff2020" then
						tooltipData.foundRedRequirements = true
					end
			elseif args.type == Enum.TooltipDataLineType.Blank then
			-- elseif args.type == Enum.TooltipDataLineType.UnitName then
			elseif args.type == Enum.TooltipDataLineType.GemSocket then
			elseif args.type == Enum.TooltipDataLineType.AzeriteEssenceSlot then
			-- elseif args.type == Enum.TooltipDataLineType.AzeriteEssencePower then
			-- elseif args.type == Enum.TooltipDataLineType.LearnableSpell then
			-- elseif args.type == Enum.TooltipDataLineType.UnitThreat then
			-- elseif args.type == Enum.TooltipDataLineType.QuestObjective then
			-- elseif args.type == Enum.TooltipDataLineType.AzeriteItemPowerDescription then
			-- elseif args.type == Enum.TooltipDataLineType.RuneforgeLegendaryPowerDescription then
			elseif args.type == Enum.TooltipDataLineType.SellPrice then
			elseif args.type == Enum.TooltipDataLineType.ProfessionCraftingQuality then
			-- elseif args.type == Enum.TooltipDataLineType.SpellName then
			else
				print("TOOLTIP PROCESSING NEEDED: " .. item:GetItemLink() .. ", type: " .. tostring(args.type))
				-- DevTools_Dump(args)
			end
		end
	end

	-- SetCVar("missingTransmogSourceInItemTooltips", 1)

	return tooltipData
end

function CaerdonWardrobeMixin:ClearButton(button)
	if button.caerdonButton then
		self:SetItemButtonStatus(button)
		self:SetItemButtonBindType(button)
	end
end

function CaerdonWardrobeMixin:UpdateButton(button, item, feature, locationInfo, options)
	if not item or (item:IsItemEmpty() and item:GetCaerdonItemType() == CaerdonItemType.Empty) then
		self:ClearButton(button)
		return
	end

	if not button.caerdonButton then
		self:SetItemButtonStatus(button, item, feature, locationInfo, options, "waiting", nil)
	end

	local locationKey = locationInfo.locationKey

	if item:HasItemLocationBankOrBags() then
		local itemLocation = item:GetItemLocation()
		local bag, slot = itemLocation:GetBagAndSlot()
		locationKey = format("bag%d-slot%d", bag, slot)
	end

	if locationKey then -- opt-in to coroutine-based update
		locationKey = format("%s-%s", feature:GetName(), locationKey)
		button.caerdonKey = locationKey

		if not item:IsItemEmpty() then
			local itemID = item:GetItemID()
			if not button.caerdonItemID or button.caerdonItemID ~= itemID then
				button.caerdonItemID = itemID
				self:ClearButton(button)
			end
		end

		self.waitingToProcess[locationKey] = {
			button = button,
			item = item,
			feature = feature,
			locationInfo = locationInfo,
			options = options
		}
		return
	end
end

function CaerdonWardrobeMixin:ProcessItem_Coroutine()
	if self.processQueue == nil then
		self.processQueue = {}

		local hasMore = true

		while hasMore do
			local isBatch = false
			local itemCount = 0
			for locationKey, processInfo in pairs(self.waitingToProcess) do
				-- Don't process item if the key is different than expected
				if processInfo.button.caerdonKey == locationKey then
					itemCount = itemCount + 1
					self.processQueue[locationKey] = processInfo
				end

				self.waitingToProcess[locationKey] = nil

				if itemCount > 12 then -- Process a small batch at a time
					isBatch = true
					break
				end
			end

			hasMore = isBatch

			for locationKey, processInfo in pairs(self.processQueue) do
				-- TODO: May have to look into cancelable continue to avoid timing issues
				-- Need to figure out how to key this correctly (could have multiple of item in bags, for instance)
				-- but in cases of rapid data update (AH scroll), we don't want to update an old button
				-- Look into ContinuableContainer
				local button = processInfo.button
				local item = processInfo.item
				local feature = processInfo.feature
				local locationInfo = processInfo.locationInfo
				local options = processInfo.options
				
				if feature:IsSameItem(button, item, locationInfo) and button.caerdonKey == locationKey then
					if item:IsItemEmpty() then -- BattlePet or something else - assuming item is ready.
						local tooltipData = self:GetTooltipData(item, feature, locationInfo)

						-- This is lame, but tooltips end up not having all of their data
						-- until a round of "Set*Item" has occurred in certain cases (usually right on login).
						-- Specifically, the Equip: line was missing on a fishing pole (and other items)
						-- TODO: Move tooltip into CaerdonItem and handle in ContinueOnItemLoad if possible
						-- Probably can't store the actual data there (need to retrieve live) due to changing info like locked status
						if tooltipData.isRetrieving then
							self:UpdateButton(button, item, feature, locationInfo, options)
						else
							self:ProcessItem(button, item, feature, locationInfo, options, tooltipData)
						end
					else
						item:ContinueOnItemLoad(function ()
							if button.caerdonKey == locationKey then
								local tooltipData = self:GetTooltipData(item, feature, locationInfo)
								if tooltipData and tooltipData.isRetrieving then
									self:UpdateButton(button, item, feature, locationInfo, options)
								else
									self:ProcessItem(button, item, feature, locationInfo, options, tooltipData)
								end
							else
								self:ClearButton(button)
							end
						end)
					end
				else
					self:ClearButton(button)
				end

				self.processQueue[locationKey] = nil
			end

			coroutine.yield()
		end

		self.processQueue = nil
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

local next = next -- faster lookup as a local apparently (haven't measured)

function CaerdonWardrobeMixin:OnUpdate(elapsed)
	self.timeSinceLastUpdate = (self.timeSinceLastUpdate or 0) + elapsed
	if (self.timeSinceLastUpdate > 0.1) then
		if self.processItemCoroutine then
			if coroutine.status(self.processItemCoroutine) ~= "dead" then
				local ok, result = coroutine.resume(self.processItemCoroutine)
				if not ok then
					error(result)
				end
			else
				self.processItemCoroutine = nil
			end
			return
		elseif next(self.waitingToProcess) ~= nil then
			self.processItemCoroutine = coroutine.create(function() self:ProcessItem_Coroutine() end)
		end

		self.timeSinceLastUpdate = 0
	end

	local name, instance
	for name, instance in pairs(registeredFeatures) do
		instance:OnUpdate(elapsed)
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
	-- elseif name == "TradeSkillMaster" then
	-- 	print("HOOKING TSM")
	-- 	hooksecurefunc (TSM.UI.AuctionScrollingTable, "_SetRowData", function (self, row, data)
	-- 		print("Row: " .. row:GetField("auctionId"))
	-- 	end)
	end
end

function CaerdonWardrobeMixin:RefreshItems()
	if self.refreshTimer then
		self.refreshTimer:Cancel()
	end

	self.refreshTimer = C_Timer.NewTimer(0.1, function ()
		local name, instance
		for name, instance in pairs(registeredFeatures) do
			instance:Refresh()
		end
	end, 1)
end

function CaerdonWardrobeMixin:OnContainerFrameUpdateSearchResults(frame)
	local id = frame:GetID();
	local name = frame:GetName().."Item";
	local itemButton;
	local _, isFiltered;
	
	for i=1, frame.size, 1 do
		itemButton = _G[name..i] or frame["Item"..i];
		_, _, _, _, _, _, _, isFiltered = C_Container.GetContainerItemInfo(id, itemButton:GetID())
		self:SetItemButtonMogStatusFilter(itemButton, isFiltered)
	end
end

function CaerdonWardrobeMixin:OnEquipPendingItem()
	-- TODO: Bit of a hack... wait a bit and then update...
	--       Need to figure out a better way.  Otherwise,
	--		 you end up with BoE markers on things you've put on.
	C_Timer.After(1, function() self:RefreshItems() end)
end

function CaerdonWardrobeMixin:TRANSMOG_COLLECTION_UPDATED()
	self:RefreshItems()
end

function CaerdonWardrobeMixin:EQUIPMENT_SETS_CHANGED()
	self:RefreshItems()
end

function CaerdonWardrobeMixin:UPDATE_EXPANSION_LEVEL()
	-- Can change while logged in!
	self:RefreshItems()
end
