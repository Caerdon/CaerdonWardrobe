local DEBUG_ENABLED = false
local ADDON_NAME, namespace = ...
local L = namespace.L
local eventFrame
local isBagUpdate = false

CaerdonWardrobe = {}

local bindTextTable = {
	[ITEM_ACCOUNTBOUND]        = L["BoA"],
	[ITEM_BNETACCOUNTBOUND]    = L["BoA"],
	[ITEM_BIND_TO_ACCOUNT]     = L["BoA"],
	[ITEM_BIND_TO_BNETACCOUNT] = L["BoA"],
	[ITEM_BIND_ON_EQUIP]       = L["BoE"],
	[ITEM_BIND_ON_USE]         = L["BoE"]
}

local InventorySlots = {
    ['INVTYPE_HEAD'] = INVSLOT_HEAD,
    ['INVTYPE_SHOULDER'] = INVSLOT_SHOULDER,
    ['INVTYPE_BODY'] = INVSLOT_BODY,
    ['INVTYPE_CHEST'] = INVSLOT_CHEST,
    ['INVTYPE_ROBE'] = INVSLOT_CHEST,
    ['INVTYPE_WAIST'] = INVSLOT_WAIST,
    ['INVTYPE_LEGS'] = INVSLOT_LEGS,
    ['INVTYPE_FEET'] = INVSLOT_FEET,
    ['INVTYPE_WRIST'] = INVSLOT_WRIST,
    ['INVTYPE_HAND'] = INVSLOT_HAND,
    ['INVTYPE_CLOAK'] = INVSLOT_BACK,
    ['INVTYPE_WEAPON'] = INVSLOT_MAINHAND,
    ['INVTYPE_SHIELD'] = INVSLOT_OFFHAND,
    ['INVTYPE_2HWEAPON'] = INVSLOT_MAINHAND,
    ['INVTYPE_WEAPONMAINHAND'] = INVSLOT_MAINHAND,
    ['INVTYPE_RANGED'] = INVSLOT_MAINHAND,
    ['INVTYPE_RANGEDRIGHT'] = INVSLOT_MAINHAND,
    ['INVTYPE_WEAPONOFFHAND'] = INVSLOT_OFFHAND,
    ['INVTYPE_HOLDABLE'] = INVSLOT_OFFHAND,
    ['INVTYPE_TABARD'] = INVSLOT_TABARD
}

local scanTip = CreateFrame( "GameTooltip", "CaerdonWardrobeGameTooltip", nil, "GameTooltipTemplate" )
local cachedBinding = {}

local model = CreateFrame('DressUpModel')

local function GetItemID(itemLink)
	return itemLink:match("item:(%d+)")
end

local cachedIsDressable = {}
local function IsDressableItemCheck(itemID, itemLink)
	local isDressable = true
	local shouldRetry = false
	local slot

	local dressableCache = cachedIsDressable[itemLink]
	if dressableCache then
		isDressable = dressableCache.isDressable
		slot = dressableCache.slot
	else
	    local _, _, _, slotName = GetItemInfoInstant(itemID)
	    if slotName and slotName ~= "" then -- make sure it's a supported slot
		    slot = InventorySlots[slotName]
		    if not slot then
				isDressable = false
		    elseif not IsDressableItem(itemLink) then
		    	-- IsDressableItem can return false instead of true for
		    	-- an item that is actually dressable (seems to happen
		    	-- most often during item caching).  Adding some
		    	-- retry tags to the cache if IsDressableItem says its
		    	-- not but transmog says it can be a source
				local canBeChanged, noChangeReason, canBeSource, noSourceReason = C_Transmog.GetItemInfo(itemID)
				isDressable = false
				if canBeSource then
					shouldRetry = true
				end
			end
		else
			isDressable = false
		end

		if not shouldRetry then
			cachedIsDressable[itemLink] = { isDressable = isDressable, slot = slot }
		end
	end
    return isDressable, shouldRetry, slot
end

local cachedItemSources = {}
local function GetItemSource(itemID, itemLink)
	local itemSources = cachedItemSources[itemLink]
	if itemSources == "NONE" then
		itemSources = nil
	elseif not itemSources then
		local isDressable, shouldRetry, slot = IsDressableItemCheck(itemID, itemLink)
		if not shouldRetry then
			if not isDressable then
		    	cachedItemSources[itemLink] = "NONE"
			else
			    model:SetUnit('player')
			    model:Undress()
			    model:TryOn(itemLink, slot)
			    itemSources = model:GetSlotTransmogSources(slot)
			    if itemSources then
					cachedItemSources[itemLink] = itemSources
				else
					cachedItemSources[itemLink] = "NONE"
				end
			end
		end
	end
    return itemSources, shouldRetry
end

local function GetItemAppearance(itemID, itemLink)
	local categoryID, appearanceID, canEnchant, texture, isCollected, sourceItemLink
	local sourceID, shouldRetry = GetItemSource(itemID, itemLink)

    if sourceID and sourceID ~= NO_TRANSMOG_SOURCE_ID then
        categoryID, appearanceID, canEnchant, texture, isCollected, sourceItemLink = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
        if sourceItemLink then
			local _, _, quality = GetItemInfo(sourceItemLink)
			-- Skip artifact weapons and common for now
			if quality == LE_ITEM_QUALITY_ARTIFACT or quality == LE_ITEM_QUALITY_COMMON then
	 			appearanceID = nil
	 			isCollected = false
	 			sourceID = NO_TRANSMOG_SOURCE_ID
			end
		end
    end

    return appearanceID, isCollected, sourceID, shouldRetry
end

local function PlayerHasAppearance(appearanceID)
	local hasAppearance = false

    local sources = C_TransmogCollection.GetAppearanceSources(appearanceID)
    local matchedSource
    if sources then
        for i, source in pairs(sources) do
            if source.isCollected then
            	matchedSource = source
                hasAppearance = true
                break
            end
        end
    end

    return hasAppearance, matchedSource
end
 
local function PlayerCanCollectAppearance(appearanceID, itemID, itemLink)
	local _, _, quality, _, reqLevel, itemClass, itemSubClass, _, equipSlot, _, _, itemClassID, itemSubClassID = GetItemInfo(itemID)
	local playerLevel = UnitLevel("player")
	local canCollect = false
	local isInfoReady
	local matchedSource
	local shouldRetry

	local playerClass = select(2, UnitClass("player"))

	local classArmor;
	if playerClass == "MAGE" or 
		playerClass == "PRIEST" or 
		playerClass == "WARLOCK" then
		classArmor = LE_ITEM_ARMOR_CLOTH
	elseif playerClass == "DEMONHUNTER" or
		playerClass == "DRUID" or 
		playerClass == "MONK" or
		playerClass == "ROGUE" then
		classArmor = LE_ITEM_ARMOR_LEATHER
	elseif playerClass == "DEATHKNIGHT" or
		playerClass == "PALADIN" or
		playerClass == "WARRIOR" then
		classArmor = LE_ITEM_ARMOR_PLATE
	elseif playerClass == "HUNTER" or 
		playerClass == "SHAMAN" then
		classArmor = LE_ITEM_ARMOR_MAIL
	end

	if equipSlot ~= "INVTYPE_CLOAK"
		and itemClassID == LE_ITEM_CLASS_ARMOR and 
		(	itemSubClassID == LE_ITEM_ARMOR_CLOTH or 
			itemSubClassID == LE_ITEM_ARMOR_LEATHER or 
			itemSubClassID == LE_ITEM_ARMOR_MAIL or
			itemSubClassID == LE_ITEM_ARMOR_PLATE)
		and itemSubClassID ~= classArmor then 
			canCollect = false
			return
		end

	if playerLevel >= reqLevel then
	    local sources = C_TransmogCollection.GetAppearanceSources(appearanceID)
	    if sources then
	        for i, source in pairs(sources) do
		        isInfoReady, canCollect = C_TransmogCollection.PlayerCanCollectSource(source.sourceID)
	            if isInfoReady then
	            	if canCollect then
		            	matchedSource = source
		            end
	                break
	            else
	            	shouldRetry = true
	            end
	        end
	    end
	end

    return canCollect, matchedSource, shouldRetry
end

local function GetItemInfoLocal(itemID, bag, slot)
	local name = GetItemInfo(itemID)
	if name then
		if bag == "AuctionFrame" then
			name = GetAuctionItemInfo("list", slot)
		elseif bag == "MerchantFrame" then
			name = GetMerchantItemInfo(slot)
		end
	end

	return name
end

local function GetItemLinkLocal(bag, slot)
	if bag == "AuctionFrame" then
		return GetAuctionItemLink("list", slot)
	elseif bag == "MerchantFrame" then
		return GetMerchantItemLink(slot)
	elseif bag == "BankFrame" then
		return GetInventoryItemLink("player", slot)
	elseif bag == "GuildBankFrame" then
		return GetGuildBankItemLink(slot.tab, slot.index)
	else
		return GetContainerItemLink(bag, slot)
	end
end

local function GetItemKey(bag, slot, itemLink)
	local itemKey
	if bag == "AuctionFrame" or bag == "MerchantFrame" then
		itemKey = itemLink
	elseif bag == "GuildBankFrame" then
		itemKey = itemLink .. slot.tab .. slot.index
	else
		itemKey = itemLink .. bag .. slot
	end

	return itemKey
end

local equipLocations = {}

local function GetBindingStatus(bag, slot, itemID, itemLink)
	local itemKey = GetItemKey(bag, slot, itemLink)

	local binding = cachedBinding[itemKey]
	local bindingText, needsItem, hasUse

    local isInEquipmentSet = false
    local isDressable, shouldRetry = IsDressableItemCheck(itemID, itemLink)

	if binding then
		bindingText = binding.bindingText
		needsItem = binding.needsItem
		hasUse = binding.hasUse
		isInEquipmentSet = binding.isInEquipmentSet
	elseif not shouldRetry then
		needsItem = true
		scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
		if bag == "AuctionFrame" then
			scanTip:SetAuctionItem("list", slot)
		elseif bag == "MerchantFrame" then
			scanTip:SetMerchantItem(slot)
		elseif bag == "BankFrame" then
			scanTip:SetInventoryItem("player", slot)
		elseif bag == "GuildBankFrame" then
			scanTip:SetGuildBankItem(slot.tab, slot.index)
		else
			scanTip:SetBagItem(bag, slot)
		end

	    -- Use equipment set for binding text if it's assigned to one
		if isDressable and CanUseEquipmentSets() then
			-- Flag to ensure flagging multiple set membership
			local isBindingTextDone = false

			for setIndex=1, GetNumEquipmentSets() do

				name, icon, setID, isEquipped, numItems, numEquipped, numInventory, numMissing, numIgnored = GetEquipmentSetInfo(setIndex)

			    GetEquipmentSetLocations(name, equipLocations)

				for locationIndex=1, #equipLocations do
					local location = equipLocations[locationIndex]
					if location ~= nil then
					    local isPlayer, isBank, isBags, isVoidStorage, equipSlot, equipBag, equipTab, equipVoidSlot = EquipmentManager_UnpackLocation(location)
					    if isVoidStorage then
					    	-- Do nothing for now
					    elseif isBank and not isBags then -- player or bank
					    	if bag == "BankFrame" and slot == equipSlot then
					    		needsItem = false
								if bindingText then
									bindingText = "*" .. bindingText
									isBindingTextDone = true
									break
								else
									bindingText = name
									isInEquipmentSet = true
								end
					    	end
					    else
						    if equipSlot == slot and equipBag == bag then
								needsItem = false
								if bindingText then
									bindingText = "*" .. bindingText
									isBindingTextDone = true
									break
								else
									bindingText = name
									isInEquipmentSet = true
								end
							end
						end
					end
				end

				if isBindingTextDone then
					break
				end
			end
		end

		local canBeChanged, noChangeReason, canBeSource, noSourceReason = C_Transmog.GetItemInfo(itemID)
		if canBeSource then
	        local hasTransmog = C_TransmogCollection.PlayerHasTransmog(itemID)
	        if hasTransmog then
	        	needsItem = false
	        end
	    else
	    	needsItem = false
	    end

	    local tipLines = scanTip:NumLines()
	    if tipLines == 1 then
	    	-- Something with transmog is causing tooltips to retrieve additional info
	    	-- Checking for it here to flag for retry in a bit.
	    	shouldRetry = true
	    else
			for lineIndex = 1, scanTip:NumLines() do
				local lineText = _G["CaerdonWardrobeGameTooltipTextLeft" .. lineIndex]:GetText()
				if lineText then
					-- TODO: Look at switching to GetItemSpell
					-- TODO: Figure out if there's a constant for Equip: as well.
					if strmatch(lineText, USE_COLON) or strmatch(lineText, L["Equip:"]) then -- it's a recipe or has a "use" effect
						hasUse = true
						break
					end

					if not bindingText then
						bindingText = bindTextTable[lineText]
					end

					if lineText == TRANSMOGRIFY_TOOLTIP_ITEM_UNKNOWN_APPEARANCE_KNOWN then
						needsItem = false
						break
					end
				end
			end
		end

		if not shouldRetry then
			cachedBinding[itemKey] = {bindingText = bindingText, needsItem = needsItem, hasUse = hasUse, isDressable = isDressable, isInEquipmentSet = isInEquipmentSet }
		end
	end

	return bindingText, needsItem, hasUse, isDressable, isInEquipmentSet, shouldRetry
end

local function addDebugInfo(tooltip)
	local itemLink = select(2, tooltip:GetItem())
	if itemLink then
		local itemID = GetItemID(itemLink) or "not found"
		local _, _, quality, _, _, itemClass, itemSubClass, _, equipSlot = GetItemInfo(itemID)

		tooltip:AddDoubleLine("Item ID:", tostring(itemID))
		tooltip:AddDoubleLine("Item Class:", tostring(itemClass))
		tooltip:AddDoubleLine("Item SubClass:", tostring(itemSubClass))
		tooltip:AddDoubleLine("Item EquipSlot:", tostring(equipSlot))

		local playerClass = select(2, UnitClass("player"))
		local playerLevel = UnitLevel("player")
		local playerSpec = GetSpecialization()
		local playerSpecName = playerSpec and select(2, GetSpecializationInfo(playerSpec)) or "None"
		tooltip:AddDoubleLine("Player Class:", playerClass)
		tooltip:AddDoubleLine("Player Spec:", playerSpecName)
		tooltip:AddDoubleLine("Player Level:", playerLevel)

		local appearanceID, isCollected, sourceID, shouldRetry = GetItemAppearance(itemID, itemLink)

		tooltip:AddDoubleLine("Appearance ID:", tostring(appearanceID))
		tooltip:AddDoubleLine("Is Collected:", tostring(isCollected))
		tooltip:AddDoubleLine("Item Source:", sourceID and tostring(sourceID) or "none")

		if appearanceID then
			local hasAppearance, matchedSource = PlayerHasAppearance(appearanceID)
			tooltip:AddDoubleLine("PlayerHasAppearance:", tostring(hasAppearance))
			tooltip:AddDoubleLine("Has Matched Source:", matchedSource and matchedSource.name or "none")
			local canCollect, matchedSource = PlayerCanCollectAppearance(appearanceID, itemID, itemLink)
			tooltip:AddDoubleLine("PlayerCanCollectAppearance:", tostring(canCollect))
			tooltip:AddDoubleLine("Collect Matched Source:", matchedSource and matchedSource.name or "none")
		end

		tooltip:Show()
	end
end

local waitingOnItemData = {}

local function IsGearSetStatus(status)
	return status and status ~= L["BoA"] and status ~= L["BoE"]
end

local function SetIconPositionAndSize(icon, startingPoint, offset, size)
	if startingPoint == "TOPRIGHT" then
		icon:SetPoint("TOPRIGHT", offset, offset)
	else
		icon:SetPoint("TOPLEFT", offset * -1, offset)
	end

	icon:SetSize(size, size)
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

local function SetItemButtonMogStatus(button, status, bindingStatus, options)
	local mogStatus = button.mogStatus
	local mogAnim = button.mogAnim
	local iconPosition, showSellables, isSellable
	if options then 
		showSellables = options.showSellables
		iconPosition = options.iconPosition
		isSellable = options.isSellable
	end
	if not status and not mogStatus and not mogAnim then return end
	if not status then
		if mogAnim and mogAnim:IsPlaying() then
			mogAnim:Stop()
		end
		mogStatus:SetTexture("")
		return
	end

	if not mogStatus then
		-- see ItemButtonTemplate.Count @ ItemButtonTemplate.xml#13
		mogStatus = button:CreateTexture(nil, "OVERLAY", nil, 2)
		SetIconPositionAndSize(mogStatus, iconPosition, 15, 40)
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

		if not mogAnim or not button.isWaitingIcon then
			mogAnim = mogStatus:CreateAnimationGroup()

			AddRotation(mogAnim, 1, 360, 0.5, "IN_OUT")

		    mogAnim:SetLooping("REPEAT")
			button.mogAnim = mogAnim
			button.isWaitingIcon = true
		end
	else
		if status == "own" then
			showAnim = true
			if mogAnim and button.isWaitingIcon then
				if mogAnim:IsPlaying() then
					mogAnim:Finish()
				end

				mogAnim = nil
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
			-- mogAnim = nil
			-- button.mogAnim = nil
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

	mogStatus:SetAlpha(1)

	if status == "own" then
		SetIconPositionAndSize(mogStatus, iconPosition, 15, 40)
		mogStatus:SetTexture("Interface\\Store\\category-icon-featured")
	elseif status == "other" then
		SetIconPositionAndSize(mogStatus, iconPosition, 15, 40)
		mogStatus:SetTexture("Interface\\Store\\category-icon-placeholder")
		-- showAnim = false
	elseif status == "collected" then
		-- showAnim = false
		if not IsGearSetStatus(bindingStatus) and showSellables and isSellable then -- it's known and can be sold
			SetIconPositionAndSize(mogStatus, iconPosition, 10, 30)
			mogStatus:SetAlpha(0.9)
			mogStatus:SetTexture("Interface\\Store\\category-icon-bag")
		else
			mogStatus:SetTexture("")
		end
	elseif status == "waiting" then
		mogStatus:SetAlpha(0.5)
		SetIconPositionAndSize(mogStatus, iconPosition, 10, 30)
		mogStatus:SetTexture("Interface\\Common\\StreamCircle")
		-- showAnim = false
	end

	if MailFrame:IsShown() or (AuctionFrame and AuctionFrame:IsShown()) then
		showAnim = false
	end

	if showAnim then
		-- mogFlash:Show()
		if mogAnim and not mogAnim:IsPlaying() then
			mogAnim:Play()
		end
	else
		if mogAnim and mogAnim:IsPlaying() then
			mogAnim:Finish()
		end
		-- mogFlash:Hide()
	end
end

local function SetItemButtonBindType(button, mogStatus, bindingStatus, options)
	local bindsOnText = button.bindsOnText
	if not bindingStatus and not bindsOnText then return end
	if not bindingStatus then
		bindsOnText:SetText("")
		return
	end
	if not bindsOnText then
		-- see ItemButtonTemplate.Count @ ItemButtonTemplate.xml#13
		bindsOnText = button:CreateFontString(nil, "BORDER", "SystemFont_Outline_Small") 
		bindsOnText:SetPoint("BOTTOMRIGHT", 0, 2)
		bindsOnText:SetWidth(button:GetWidth())
		button.bindsOnText = bindsOnText
	end

	local bindingText
	if IsGearSetStatus(bindingStatus) then -- is gear set
		bindingText = "|cFFFFFFFF" .. bindingStatus .. "|r"
	else
		if mogStatus == "own" then
			if bindingStatus == L["BoA"] then
				local color = BAG_ITEM_QUALITY_COLORS[LE_ITEM_QUALITY_HEIRLOOM]
				bindsOnText:SetTextColor(color.r, color.g, color.b, 1)
				bindingText = bindingStatus
			else
				bindingText = "|cFF00FF00" .. bindingStatus .. "|r"
			end
		elseif mogStatus == "other" then
			bindingText = "|cFFFF0000" .. bindingStatus .. "|r"
		elseif mogStatus == "collected" then
			if bindingStatus == L["BoA"] then
				local color = BAG_ITEM_QUALITY_COLORS[LE_ITEM_QUALITY_HEIRLOOM]
				bindsOnText:SetTextColor(color.r, color.g, color.b, 1)
				bindingText = bindingStatus
			elseif bindingStatus == L["BoE"] then
				bindingText = "|cFF00FF00" .. bindingStatus .. "|r"
			else
				bindingText = bindingStatus
			end
		else
			if bindingStatus == L["BoA"] then
				local color = BAG_ITEM_QUALITY_COLORS[LE_ITEM_QUALITY_HEIRLOOM]
				bindsOnText:SetTextColor(color.r, color.g, color.b, 1)
				bindingText = bindingStatus
			else
				bindingText = "|cFF00FF00" .. bindingStatus .. "|r"
			end
		end
	end

	bindsOnText:SetText(bindingText)
end

function CaerdonWardrobe:ResetButton(button)
	SetItemButtonMogStatus(button, nil)
	SetItemButtonBindType(button, nil)
end

local itemQueue = {}
local function QueueProcessItem(itemLink, itemID, bag, slot, button, options, itemProcessed)
	local itemKey = GetItemKey(bag, slot, itemLink)
	itemQueue[itemKey] = { itemID = itemID, bag = bag, slot = slot, button = button, options = options, itemProcessed = itemProcessed }
	SetItemButtonMogStatus(button, "waiting", nil, options)
	isItemUpdateRequested = true
end

local function ItemIsSellable(itemID, itemLink)
	local isSellable = true
	if itemID == 23192 then -- Tabard of the Scarlet Crusade needs to be worn for a vendor at Darkmoon Faire
		isSellable = false
	end

	return isSellable
end

local function ProcessItem(itemID, bag, slot, button, options, itemProcessed)
	local bindingText
	local mogStatus = nil

	local showMogIcon = options and options.showMogIcon
	local showBindStatus = options and options.showBindStatus
	local showSellables = options and options.showSellables

	local canBeChanged, noChangeReason, canBeSource, noSourceReason = C_Transmog.GetItemInfo(itemID)

	itemLink = GetItemLinkLocal(bag, slot)

	local bindingStatus, needsItem, hasUse, isDressable, isInEquipmentSet, shouldRetry = GetBindingStatus(bag, slot, itemID, itemLink)
	if shouldRetry then
		QueueProcessItem(itemLink, itemID, bag, slot, button, options, itemProcessed)
		return
	end

	local appearanceID, isCollected, sourceID, shouldRetry = GetItemAppearance(itemID, itemLink)
	if shouldRetry then
		QueueProcessItem(itemLink, itemID, bag, slot, button, options, itemProcessed)
		return
	end
	if appearanceID then
		if(needsItem and not isCollected and not PlayerHasAppearance(appearanceID)) then
			local canCollect, matchedSource, shouldRetry = PlayerCanCollectAppearance(appearanceID, itemID, itemLink)
			if shouldRetry then
				QueueProcessItem(itemLink, itemID, bag, slot, button, options, itemProcessed)
				return
			end

			if canCollect then
				mogStatus = "own"
			else
				if bindingStatus and needsItem then
					mogStatus = "other"
				end
			end
		else
			-- If an item isn't flagged as a source or has a usable effect,
			-- then don't mark it as sellable right now to avoid accidents.
			-- May need to expand this to account for other items, too, for now.
			if canBeSource and not isInEquipmentSet then
				if not hasUse and isDressable and not shouldRetry then -- don't flag items for sale that have use effects for now
					mogStatus = "collected"
				end
			end
			-- TODO: Decide how to expose this functionality
			-- Hide anything that doesn't match
			-- if button then
			-- 	--button.IconBorder:SetVertexColor(100, 255, 50)
			-- 	button.searchOverlay:Show()
			-- end

		end
	elseif needsItem then
		if canBeSource and isDressable and not shouldRetry then
			local _, _, _, _, reqLevel, class, subclass, _, equipSlot = GetItemInfo(itemID)
			local playerLevel = UnitLevel("player")

			if playerLevel >= reqLevel then
				mogStatus = "own"
			else
				mogStatus = "other"
			end
		end
	else
		if canBeSource then
	        local hasTransmog = C_TransmogCollection.PlayerHasTransmog(itemID)
	        if hasTransmog and not hasUse and isDressable then
	        	-- Tabards don't have an appearance ID and will end up here.
	        	mogStatus = "collected"
	        end
	    end

		-- Hide anything that doesn't match
		-- if button then
		-- 	--button.IconBorder:SetVertexColor(100, 255, 50)
		-- 	button.searchOverlay:Show()
		-- end
	end

	if mogStatus == "collected" and 
		ItemIsSellable(itemID, itemLink) and 
		not isInEquipmentSet then

       	-- Anything that reports as the player having should be safe to sell
       	-- unless it's in an equipment set or needs to be excluded for some
       	-- other reason
		options.isSellable = true
	end

	if button then
		SetItemButtonMogStatus(button, mogStatus, bindingStatus, options)

		-- TODO: Consider making this an option
		-- if bag ~= "GuildBankFrame" then
			if showBindStatus then
				SetItemButtonBindType(button, mogStatus, bindingStatus, options)
			end
		-- end
	end

	if itemProcessed then
		itemProcessed(mogStatus, bindingStatus)
	end
end

local function ProcessOrWaitItem(itemID, bag, slot, button, options, itemProcessed)
	if itemID then
		local waitItem = waitingOnItemData[tostring(itemID)]
		if not waitItem then
			waitItem = {}
			waitingOnItemData[tostring(itemID)] = waitItem
		end

		local waitBag = waitItem[tostring(bag)]
		if not waitBag then
			waitBag = {}
			waitItem[tostring(bag)] = waitBag
		end

		local itemName = GetItemInfoLocal(itemID, bag, slot)
		local itemLink = GetItemLinkLocal(bag, slot)

		if itemName == nil or itemLink == nil then
			SetItemButtonMogStatus(button, "waiting", nil, options)
			waitBag[tostring(slot)] = { slot = slot, button = button, options = options, itemProcessed = itemProcessed}
		else
			waitingOnItemData[tostring(itemID)][tostring(bag)][tostring(slot)] = nil
			ProcessItem(itemID, bag, slot, button, options, itemProcessed)
		end
	else
		SetItemButtonMogStatus(button, nil)
		SetItemButtonBindType(button, nil)
	end
end

function CaerdonWardrobe:ProcessItem(itemID, bag, slot, button, options, itemProcessed)
	ProcessOrWaitItem(itemID, bag, slot, button, options, itemProcessed)
end

local function OnContainerUpdate(self, asyncUpdate)
	local bagID = self:GetID()

	for buttonIndex = 1, self.size do
		local button = _G[self:GetName() .. "Item" .. buttonIndex]
		local slot = button:GetID()

		local itemID = GetContainerItemID(bagID, slot)
		local texture, itemCount, locked = GetContainerItemInfo(bagID, slot)

		ProcessOrWaitItem(itemID, bagID, slot, button, { showMogIcon = true, showBindStatus = true, showSellables = true })
	end
end

local function OnItemUpdate_Coroutine()
	local processQueue = {}
	local itemCount = 0

	for itemKey, itemInfo in pairs(itemQueue) do
		itemQueue[itemKey] = nil
		itemCount = itemCount + 1

		ProcessOrWaitItem(itemInfo.itemID, itemInfo.bag, itemInfo.slot, itemInfo.button, itemInfo.options, itemInfo.itemProcessed)
		if itemCount % 8 == 0 then
			coroutine.yield()
		end
	end
end

local waitingOnBagUpdate = {}
local function OnBagUpdate_Coroutine()
    for frameID, shouldUpdate in pairs(waitingOnBagUpdate) do
		local frame = _G["ContainerFrame".. frameID]

		if frame:IsShown() then
			OnContainerUpdate(frame, true)
			waitingOnBagUpdate[frameID] = nil
		end
		coroutine.yield()
    end

	-- waitingOnBagUpdate = {}
end

local function AddBagUpdateRequest(bagID)
	local foundBag = false
	for i=1, NUM_CONTAINER_FRAMES, 1 do
		local frame = _G["ContainerFrame"..i];
		if ( frame:GetID() == bagID ) then
			waitingOnBagUpdate[tostring(i)] = true
			foundBag = true
		end
	end
end

local function ScheduleContainerUpdate(frame)
	local bagID = frame:GetID()
	AddBagUpdateRequest(bagID)
end

-- hooksecurefunc("ContainerFrame_Update", ScheduleContainerUpdate)

local function OnBankItemUpdate(button)
	local containerID = button:GetParent():GetID();
	if( button.isBag ) then
		containerID = -ITEM_INVENTORY_BANK_BAG_OFFSET;
		return
	end

	local buttonID = button:GetID()

	local bag = "BankFrame"
	local slot = button:GetInventorySlot();

	local itemID = GetContainerItemID(containerID, buttonID)
	ProcessOrWaitItem(itemID, bag, slot, button, { showMogIcon=true, showBindStatus=true, showSellables=true })
end

-- hooksecurefunc("BankFrameItemButton_Update", OnBankItemUpdate)

local isGuildBankFrameUpdateRequested = false

local function OnGuildBankFrameUpdate_Coroutine()
	if( GuildBankFrame.mode == "bank" ) then
		local tab = GetCurrentGuildBankTab();
		local button, index, column;
		local texture, itemCount, locked, isFiltered, quality;

		for i=1, MAX_GUILDBANK_SLOTS_PER_TAB do
			index = mod(i, NUM_SLOTS_PER_GUILDBANK_GROUP);
			if ( index == 0 ) then
				index = NUM_SLOTS_PER_GUILDBANK_GROUP;

				coroutine.yield()
			end

			if isGuildBankFrameUpdateRequested then
				return
			end

			column = ceil((i-0.5)/NUM_SLOTS_PER_GUILDBANK_GROUP);
			button = _G["GuildBankColumn"..column.."Button"..index];

			local bag = "GuildBankFrame"
			local slot = {tab = tab, index = i}

			local options = {
				showMogIcon = true,
				showBindStatus = true,
				showSellables = true
			}

			local itemLink = GetGuildBankItemLink(tab, i)
			if itemLink then
				local itemID = itemLink:match("item:(%d+)")
				ProcessOrWaitItem(itemID, bag, slot, button, options)
			else
				-- nil results in button icon / text reset
				ProcessOrWaitItem(nil, bag, slot, button, options)
			end
		end
	end
end

local function OnGuildBankFrameUpdate()
	isGuildBankFrameUpdateRequested = true
end

local function OnAuctionBrowseUpdate()
	local offset = FauxScrollFrame_GetOffset(BrowseScrollFrame);

	for i=1, NUM_BROWSE_TO_DISPLAY do
		local auctionIndex = offset + i
		local index = auctionIndex + (NUM_AUCTION_ITEMS_PER_PAGE * AuctionFrameBrowse.page);
		local buttonName = "BrowseButton"..i.."Item";
		local button = _G[buttonName];
		local name, texture, count, quality, canUse, level, levelColHeader, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemID, hasAllInfo =  GetAuctionItemInfo("list", auctionIndex);

		local bag = "AuctionFrame"
		local slot = auctionIndex

		local itemLink = GetAuctionItemLink("list", auctionIndex)
		if(itemLink) then
			local itemID = itemLink:match("item:(%d+)")
			if itemID then
				ProcessOrWaitItem(itemID, bag, slot, button, { showMogIcon=true, showBindStatus=false, showSellables=false })
			end
		end
	end
end

local function OnMerchantUpdate()
	for i=1, MERCHANT_ITEMS_PER_PAGE, 1 do
		local index = (((MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE) + i)

		local button = _G["MerchantItem"..i.."ItemButton"];

		local bag = "MerchantFrame"
		local slot = index

		local itemID = GetMerchantItemID(index)
		ProcessOrWaitItem(itemID, bag, slot, button, { showMogIcon=true, showBindStatus=true, showSellables=false})
	end
end

hooksecurefunc("MerchantFrame_UpdateMerchantInfo", OnMerchantUpdate)

local ignoreEvents = {
	["ACTIONBAR_UPDATE_COOLDOWN"] = {},
	["BAG_UPDATE_COOLDOWN"] = {},
	["BN_FRIEND_INFO_CHANGED"] = {},
	["CHAT_MSG_BN_WHISPER"] = {},
	["CHAT_MSG_BN_WHISPER_INFORM"] = {},
	["CHAT_MSG_CHANNEL"] = {},
	["CHAT_MSG_SYSTEM"] = {},
	["CHAT_MSG_TRADESKILLS"] = {},
	["COMBAT_LOG_EVENT_UNFILTERED"] = {},
	["COMPANION_UPDATE"] = {},
	["CRITERIA_UPDATE"] = {},
	["CURSOR_UPDATE"] = {},
	["GET_ITEM_INFO_RECEIVED"] = {},
	["GUILDBANKBAGSLOTS_CHANGED"] = {},
	["GUILD_ROSTER_UPDATE"] = {},
	["ITEM_LOCK_CHANGED"] = {},
	["ITEM_LOCKED"] = {},
	["ITEM_UNLOCKED"] = {},
	["MODIFIER_STATE_CHANGED"] = {},
	["NAME_PLATE_UNIT_REMOVED"] = {},
	["QUEST_LOG_UPDATE"] = {},
	["SPELL_UPDATE_COOLDOWN"] = {},
	["SPELL_UPDATE_USABLE"] = {},
	["UNIT_ABSORBE_AMOUNT_CHANGED"] = {},
	["UNIT_AURA"] = {},
	["UPDATE_INVENTORY_DURABILITY"] = {},
	["UPDATE_MOUSEOVER_UNIT"] = {},
	["UPDATE_PENDING_MAIL"] = {},
	["UPDATE_WORLD_STATES"] = {},
	["WORLD_MAP_UPDATE"] = {}
}

local function OnEvent(self, event, ...)
	if DEBUG_ENABLED then
		if not ignoreEvents[event] then
			local arg1, arg2 = ...
			print(event .. ": " .. tostring(arg1) .. ", " .. tostring(arg2))
		end
	end

	local handler = self[event]
	if(handler) then
		handler(self, ...)
	end
end

local timeSinceLastGuildBankUpdate = nil
local timeSinceLastBagUpdate = nil
local GUILDBANKFRAMEUPDATE_INTERVAL = 0.1
local BAGUPDATE_INTERVAL = 0.1
local ITEMUPDATE_INTERVAL = 0.1
local timeSinceLastItemUpdate = nil

local function OnUpdate(self, elapsed)
	if self.itemUpdateCoroutine then
		if coroutine.status(self.itemUpdateCoroutine) ~= "dead" then
			local ok, result = coroutine.resume(self.itemUpdateCoroutine)
			if not ok then
				error(result)
			end
		else
			self.itemUpdateCoroutine = nil
		end
		return
	end

	if(self.bagUpdateCoroutine) then
		if coroutine.status(self.bagUpdateCoroutine) ~= "dead" then
			local ok, result = coroutine.resume(self.bagUpdateCoroutine)
			if not ok then
				error(result)
			end
		else
			self.bagUpdateCoroutine = nil
		end
		return
	end

	if(self.guildBankUpdateCoroutine) then
		if coroutine.status(self.guildBankUpdateCoroutine) ~= "dead" then
			local ok, result = coroutine.resume(self.guildBankUpdateCoroutine)
			if not ok then
				error(result)
			end
		else
			self.guildBankUpdateCoroutine = nil
		end
		return
	end

	if isGuildBankFrameUpdateRequested then
		isGuildBankFrameUpdateRequested = false
		timeSinceLastGuildBankUpdate = 0
	elseif timeSinceLastGuildBankUpdate then
		timeSinceLastGuildBankUpdate = timeSinceLastGuildBankUpdate + elapsed
	end

	if isBagUpdateRequested then
		isBagUpdateRequested = false
		timeSinceLastBagUpdate = 0
	elseif timeSinceLastBagUpdate then
		timeSinceLastBagUpdate = timeSinceLastBagUpdate + elapsed
	end

	if isItemUpdateRequested then
		isItemUpdateRequested = false
		timeSinceLastItemUpdate = 0
	elseif timeSinceLastItemUpdate then
		timeSinceLastItemUpdate = timeSinceLastItemUpdate + elapsed
	end

	if( timeSinceLastGuildBankUpdate ~= nil and (timeSinceLastGuildBankUpdate > GUILDBANKFRAMEUPDATE_INTERVAL) ) then
		timeSinceLastGuildBankUpdate = nil
		self.guildBankUpdateCoroutine = coroutine.create(OnGuildBankFrameUpdate_Coroutine)
	end

	if( timeSinceLastBagUpdate ~= nil and (timeSinceLastBagUpdate > BAGUPDATE_INTERVAL) ) then
		timeSinceLastBagUpdate = nil
		self.bagUpdateCoroutine = coroutine.create(OnBagUpdate_Coroutine)
	end

	if( timeSinceLastItemUpdate ~= nil and (timeSinceLastItemUpdate > ITEMUPDATE_INTERVAL) ) then
		timeSinceLastItemUpdate = nil
		self.itemUpdateCoroutine = coroutine.create(OnItemUpdate_Coroutine)
	end
end

eventFrame = CreateFrame("FRAME", "CaerdonWardrobeFrame")
eventFrame:RegisterEvent "ADDON_LOADED"
eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:SetScript("OnUpdate", OnUpdate)
if DEBUG_ENABLED then
	GameTooltip:HookScript("OnTooltipSetItem", addDebugInfo)
end

C_TransmogCollection.SetShowMissingSourceInItemTooltips(true)

function eventFrame:ADDON_LOADED(name)
	if name == ADDON_NAME then
		if IsLoggedIn() then
			OnEvent(eventFrame, "PLAYER_LOGIN")
		else
			eventFrame:RegisterEvent "PLAYER_LOGIN"
		end
	elseif name == "Blizzard_AuctionUI" then
		hooksecurefunc("AuctionFrameBrowse_Update", OnAuctionBrowseUpdate)
	elseif name == "Blizzard_GuildBankUI" then
		hooksecurefunc("GuildBankFrame_Update", OnGuildBankFrameUpdate)
	end
end

function eventFrame:PLAYER_LOGIN(...)
	if DEBUG_ENABLED then
		eventFrame:RegisterAllEvents()
	else
		eventFrame:RegisterEvent "PLAYERBANKSLOTS_CHANGED"
		eventFrame:RegisterEvent "BAG_OPEN"
		eventFrame:RegisterEvent "BAG_UPDATE"
		eventFrame:RegisterEvent "BAG_UPDATE_DELAYED"
		eventFrame:RegisterEvent "BANKFRAME_OPENED"
		eventFrame:RegisterEvent "GET_ITEM_INFO_RECEIVED"
		eventFrame:RegisterEvent "TRANSMOG_COLLECTION_UPDATED"
	end
	C_TransmogCollection.SetShowMissingSourceInItemTooltips(true)
end

function RefreshMainBank()
	for i=1, NUM_BANKGENERIC_SLOTS, 1 do
		button = BankSlotsFrame["Item"..i];
		OnBankItemUpdate(button);
	end
end

local function RefreshItems()
	if DEBUG_ENABLED then
		print("=== Refreshing Transmog Items")
	end
	cachedBinding = {}

	if MerchantFrame:IsShown() then
		OnMerchantUpdate()
	end

	if AuctionFrame and AuctionFrame:IsShown() then
		OnAuctionBrowseUpdate()
	end

	if BankFrame:IsShown() then
		RefreshMainBank()
	end

	for i=1, NUM_CONTAINER_FRAMES, 1 do
		local frame = _G["ContainerFrame"..i];
		-- if ( frame:IsShown() and frame:GetID() == bagID ) then
		-- print("Updating bag " .. i)
		waitingOnBagUpdate[tostring(i)] = true
		isBagUpdateRequested = true
	end
end

local function OnEquipPendingItem()
	-- TODO: Bit of a hack... wait a bit and then update...
	--       Need to figure out a better way.  Otherwise,
	--		 you end up with BoE markers on things you've put on.
	C_Timer.After(1, function() RefreshItems() end)
end

hooksecurefunc("EquipPendingItem", OnEquipPendingItem)

local function OnOpenBag(bagID)
	for i=1, NUM_CONTAINER_FRAMES, 1 do
		local frame = _G["ContainerFrame"..i];
		if ( frame:IsShown() and frame:GetID() == bagID ) then
			waitingOnBagUpdate[tostring(i)] = true
			isBagUpdateRequested = true
			break
		end
	end
end

local function OnOpenBackpack()
	isBagUpdateRequested = true
end

hooksecurefunc("OpenBag", OnOpenBag)
hooksecurefunc("OpenBackpack", OnOpenBackpack)
hooksecurefunc("ToggleBag", OnOpenBag)

function eventFrame:BAG_UPDATE(bagID)
	AddBagUpdateRequest(bagID)
end

function eventFrame:BAG_UPDATE_DELAYED()
	local count = 0
	for _ in pairs(waitingOnBagUpdate) do 
		count = count + 1
	end

	if count == 0 then
		RefreshItems()
	else
		isBagUpdateRequested = true
	end
end

function eventFrame:GET_ITEM_INFO_RECEIVED(itemID)
	local itemData = waitingOnItemData[tostring(itemID)]
	if itemData then
        for bag, bagData in pairs(itemData) do
        	for slot, slotData in pairs(bagData) do
        		-- Checking item info before continuing.  In certain cases,
        		-- the name / link are still nil here for some reason.
        		-- I've seen it at merchants so far.  I'm assuming that
        		-- these requests will ultimately result in yet another
        		-- GET_ITEM_INFO_RECEIVED event as that seems to be the case.
				local itemName = GetItemInfoLocal(bag, slotData.slot)
				local itemLink = GetItemLinkLocal(bag, slotData.slot)

				if itemLink and itemName then
					ProcessItem(itemID, bag, slotData.slot, slotData.button, slotData.options, slotData.itemProcessed)
				else
					ProcessOrWaitItem(itemID, bag, slotData.slot, slotData.button, slotData.options, slotData.itemProcessed)
				end
        	end
        end
	end
end

function eventFrame:TRANSMOG_COLLECTION_ITEM_UPDATE()
	-- RefreshItems()
end

function eventFrame:TRANSMOG_COLLECTION_UPDATED()
	RefreshItems()
end

function eventFrame:BANKFRAME_OPENED()
	RefreshMainBank()
end

function eventFrame:PLAYERBANKSLOTS_CHANGED(slot)
	button = BankSlotsFrame["Item" .. slot]
	OnBankItemUpdate(button)
end

-- BAG_OPEN
-- GUILDBANKBAGSLOTS_CHANGED
-- GUILDBANKFRAME_OPENED
