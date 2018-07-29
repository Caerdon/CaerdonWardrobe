local DEBUG_ENABLED = false
local ADDON_NAME, NS = ...
local L = NS.L
local eventFrame
local isBagUpdate = false
local isBagAddon = false

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
	return tonumber(itemLink:match("item:(%d+)") or itemLink:match("battlepet:(%d+)"))
end

local function IsPetLink(itemLink)
	local isPet = false
	local itemName, itemLinkInfo, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
itemEquipLoc, iconFileDataID, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID, 
isCraftingReagent = GetItemInfo(itemLink)

	local itemID = GetItemID(itemLink)
	if itemID == 82800 then
		isPet = true -- probably at the guild bank
	elseif itemClassID == LE_ITEM_CLASS_MISCELLANEOUS and itemSubClassID == LE_ITEM_MISCELLANEOUS_COMPANION_PET then
		isPet = true
	elseif not itemClassID then
		local link, name = string.match(itemLink, "|H(.-)|h(.-)|h")
		isPet = strsub(link, 1, 9) == "battlepet"
	end

	return isPet
end

local function IsMountLink(itemLink)
	local isMount = false
	local itemName, itemLinkInfo, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
itemEquipLoc, iconFileDataID, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID, 
isCraftingReagent = GetItemInfo(itemLink)
	if itemClassID == LE_ITEM_CLASS_MISCELLANEOUS and itemSubClassID == LE_ITEM_MISCELLANEOUS_MOUNT then
		isMount = true
	end

	return isMount
end

local function IsToyLink(itemLink)
	local isToy = false
	local itemID = GetItemID(itemLink)
	if itemID then
		local itemIDInfo, toyName, icon = C_ToyBox.GetToyInfo(itemID)
	  	if (itemIDInfo and toyName) then
			isToy = true
		end
	end

	return isToy
end

local function IsCollectibleLink(itemLink)
	return IsPetLink(itemLink) or IsMountLink(itemLink) or IsToyLink(itemLink)
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
	local shouldRetry = false
	local isDressable = false
	if itemSources == "NONE" then
		itemSources = nil
	elseif not itemSources then
		isDressable, shouldRetry, slot = IsDressableItemCheck(itemID, itemLink)
		if not shouldRetry then
			if not isDressable then
		    	cachedItemSources[itemLink] = "NONE"
			else
				-- Looks like I can use this now.  Keeping the old code around for a bit just in case.
				-- Actually, still seeing problems with this...try it first but fallback to model
				local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemLink)
				if sourceID then
					itemSources = sourceID
				else
				    model:SetUnit('player')
				    model:Undress()
				    model:TryOn(itemLink, slot)
				    itemSources = model:GetSlotTransmogSources(slot)
				end

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
			if quality == LE_ITEM_QUALITY_COMMON then
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
			if MerchantFrame.selectedTab == 1 then
				name = GetMerchantItemInfo(slot)
			else
				name = GetBuybackItemInfo(slot)
			end
		end
	end

	return name
end

local function GetItemLinkLocal(bag, slot)
	if bag == "AuctionFrame" then
		local _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, hasAllInfo =  GetAuctionItemInfo("list", slot);
		return hasAllInfo and GetAuctionItemLink("list", slot)
	elseif bag == "MerchantFrame" then
		if MerchantFrame.selectedTab == 1 then
			return GetMerchantItemLink(slot)
		else
			return GetBuybackItemLink(slot)
		end
	elseif bag == "BankFrame" then
		return GetInventoryItemLink("player", slot)
	elseif bag == "GuildBankFrame" then
		return GetGuildBankItemLink(slot.tab, slot.index)
	elseif bag == "EncounterJournal" then
		-- local itemID, encounterID, name, icon, slotName, armorType, itemLink = EJ_GetLootInfoByIndex(slot)
		return slot.link
	elseif bag == "LootFrame" or bag == "GroupLootFrame" then
		return slot.link
	else
    if bag then
      return GetContainerItemLink(bag, slot)
    end
	end
end

local function GetItemKey(bag, slot, itemLink)
	local itemKey
	if bag == "AuctionFrame" or bag == "MerchantFrame" then
		itemKey = itemLink
	elseif bag == "GuildBankFrame" then
		itemKey = itemLink .. slot.tab .. slot.index
	elseif bag == "EncounterJournal" then
		itemKey = itemLink .. bag .. slot.index
	elseif bag == "LootFrame" or bag == "GroupLootFrame" then
		itemKey = itemLink
	else
		itemKey = itemLink .. bag .. slot
	end

	return itemKey
end

local equipLocations = {}

local function GetBindingStatus(bag, slot, itemID, itemLink)
	-- local isDebugItem = itemID == 82800

	-- if isDebugItem then print ("GetBindingStatus (" .. itemLink .. "): bag = " .. bag .. ", slot = " .. slot) end

	local itemKey = GetItemKey(bag, slot, itemLink)

	local binding = cachedBinding[itemKey]
	local bindingText, needsItem, hasUse

    local isInEquipmentSet = false
    local isBindOnPickup = false
    local isCompletionistItem = false
    local isDressable, shouldRetry

    local isCollectionItem = IsCollectibleLink(itemLink)

    local shouldCheckEquipmentSet = false

   	if isCollectionItem then
		isDressable = false
		shouldRetry = false
	else
	    isDressable, shouldRetry = IsDressableItemCheck(itemID, itemLink)
	end


	if binding then
		if isDebugItem then print("Using cached binding: " .. tostring(binding.bindingText)) end
		bindingText = binding.bindingText
		needsItem = binding.needsItem
		hasUse = binding.hasUse
		isInEquipmentSet = binding.isInEquipmentSet
		isBindOnPickup = binding.isBindOnPickup
		isCompletionistItem = binding.isCompletionistItem
	elseif not shouldRetry then
		if isDebugItem then print("Processing binding") end
		needsItem = true
		scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
		if isDebugItem then print("scanTip bag: " .. bag .. ", slot: " .. tostring(slot)) end
		if bag == "AuctionFrame" then
			scanTip:SetAuctionItem("list", slot)
		elseif bag == "MerchantFrame" then
			if MerchantFrame.selectedTab == 1 then
				scanTip:SetMerchantItem(slot)
			else
				scanTip:SetBuybackItem(slot)
			end
		elseif bag == BANK_CONTAINER then
			scanTip:SetInventoryItem("player", BankButtonIDToInvSlotID(slot))
		   	if not isCollectionItem then
				shouldCheckEquipmentSet = true
			end
		elseif bag == "GuildBankFrame" then
			scanTip:SetGuildBankItem(slot.tab, slot.index)
		elseif bag == "LootFrame" then
			scanTip:SetLootItem(slot.index)
		elseif bag == "GroupLootFrame" then
			scanTip:SetLootRollItem(slot.index)
		else
			scanTip:SetBagItem(bag, slot)
		   	if not isCollectionItem then
				shouldCheckEquipmentSet = true
			end
		end

		if shouldCheckEquipmentSet then
	 		local _, _, _, _, reqLevel, class, subclass, _, equipSlot = GetItemInfo(itemID)
			if isDebugItem then print("equipSlot: " .. tostring(equipSlot)) end

		   -- Use equipment set for binding text if it's assigned to one
			if equipSlot ~= "" and C_EquipmentSet.CanUseEquipmentSets() then

				-- Flag to ensure flagging multiple set membership
				local isBindingTextDone = false

				for setIndex=1, C_EquipmentSet.GetNumEquipmentSets() do
			        local equipmentSetIDs = C_EquipmentSet.GetEquipmentSetIDs()
			        local equipmentSetID = equipmentSetIDs[setIndex]
							name, icon, setID, isEquipped, numItems, numEquipped, numInventory, numMissing, numIgnored = C_EquipmentSet.GetEquipmentSetInfo(equipmentSetID)

			        local equipLocations = C_EquipmentSet.GetItemLocations(equipmentSetID)

							for locationIndex=INVSLOT_FIRST_EQUIPPED , INVSLOT_LAST_EQUIPPED do
								local location = equipLocations[locationIndex]
								if location ~= nil then
								    local isPlayer, isBank, isBags, isVoidStorage, equipSlot, equipBag, equipTab, equipVoidSlot = EquipmentManager_UnpackLocation(location)
								    if isDebugItem then
								    	print("isPlayer: " .. tostring(isPlayer) .. ", isBank: " .. tostring(isBank) .. ", isBags: " .. tostring(isBags) .. ", isVoidStorage: " .. tostring(isVoidStorage) .. ", equipSlot: " .. tostring(equipSlot) .. ", equipBag: " .. tostring(equipBag) .. ", equipTab: " .. tostring(equipTab) .. ", equipVoidSlot: " .. tostring(equipVoidSlot))
								    end
								    equipSlot = tonumber(equipSlot)
								    equipBag = tonumber(equipBag)

								    if isVoidStorage then
								    	-- Do nothing for now
								    elseif isBank and not isBags then -- player or bank
								    	if bag == BANK_CONTAINER and BankButtonIDToInvSlotID(slot) == equipSlot then
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

	  	local PET_KNOWN = strmatch(ITEM_PET_KNOWN, "[^%(]+")
	  	local needsCollectionItem = true
	  	local numLines = scanTip:NumLines()
	    if isDebugItem then print('Scan Tip Lines: ' .. tostring(numLines)) end
		for lineIndex = 1, numLines do
			local lineText = _G["CaerdonWardrobeGameTooltipTextLeft" .. lineIndex]:GetText()
			if lineText then
				-- TODO: Look at switching to GetItemSpell
				if isDebugItem then print ("Tip: " .. lineText) end
				if strmatch(lineText, USE_COLON) or strmatch(lineText, ITEM_SPELL_TRIGGER_ONEQUIP) or strmatch(lineText, string.format(ITEM_SET_BONUS, "")) then -- it's a recipe or has a "use" effect or belongs to a set
					hasUse = true
					-- break
				end

				if not bindingText then
					bindingText = bindTextTable[lineText]
				end

				if lineText == RETRIEVING_ITEM_INFO then
					shouldRetry = true
					break
				elseif lineText == ITEM_BIND_ON_PICKUP then
					isBindOnPickup = true
				elseif lineText == TRANSMOGRIFY_TOOLTIP_ITEM_UNKNOWN_APPEARANCE_KNOWN then
					if CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem then
						isCompletionistItem = true
					else
						needsItem = false
					end
					break
				elseif lineText == ITEM_SPELL_KNOWN or strmatch(lineText, PET_KNOWN) then
					needsCollectionItem = false
				end
			end
		end


		if not shouldRetry then
			if isDebugItem then print("Is Collection Item: " .. tostring(isCollectionItem)) end

			if isCollectionItem then
				if numLines == 0 and IsPetLink(itemLink) then
					local petID = GetItemID(itemLink)
					if petID then
						if petID ~= 82800 then -- generic pet cage
							local numCollected = C_PetJournal.GetNumCollectedInfo(petID)
							if numCollected and numCollected > 0 then				
								if isDebugItem then print("Already have it: " .. itemLink .. "- " .. numCollected) end
								needsItem = false
							else
								if isDebugItem then print("Need: " .. itemLink .. ", " .. tostring(numCollected)) end
								needsItem = true
							end
						else
							-- TODO: Can we do something here?
							needsItem = false
						end
					end
				elseif needsCollectionItem then
					if isDebugItem then print("Collection Item Needed: " .. itemLink .. ", " .. tostring(owned) .. ", " .. tostring(numCollected)) end
					needsItem = true
				else
					if isDebugItem then print("Not needed collection: " .. itemLink) end
				end
			end

			cachedBinding[itemKey] = {bindingText = bindingText, needsItem = needsItem, hasUse = hasUse, isDressable = isDressable, isInEquipmentSet = isInEquipmentSet, isBindOnPickup = isBindOnPickup, isCompletionistItem = isCompletionistItem }
		end
	end

	return bindingText, needsItem, hasUse, isDressable, isInEquipmentSet, isBindOnPickup, isCompletionistItem, shouldRetry
end

local function addDebugInfo(tooltip)
	local itemLink = select(2, tooltip:GetItem())
	if itemLink then
		local playerClass = select(2, UnitClass("player"))
		local playerLevel = UnitLevel("player")
		local playerSpec = GetSpecialization()
		local playerSpecName = playerSpec and select(2, GetSpecializationInfo(playerSpec)) or "None"
		tooltip:AddDoubleLine("Player Class:", playerClass)
		tooltip:AddDoubleLine("Player Spec:", playerSpecName)
		tooltip:AddDoubleLine("Player Level:", playerLevel)

		local itemID = GetItemID(itemLink)
		tooltip:AddDoubleLine("Item ID:", tostring(itemID))

		if itemID then
			local _, _, quality, _, _, itemClass, itemSubClass, _, equipSlot = GetItemInfo(itemID)
			tooltip:AddDoubleLine("Item Class:", tostring(itemClass))
			tooltip:AddDoubleLine("Item SubClass:", tostring(itemSubClass))
			tooltip:AddDoubleLine("Item EquipSlot:", tostring(equipSlot))

			local appearanceID, isCollected, sourceID, shouldRetry = GetItemAppearance(itemID, itemLink)

			tooltip:AddDoubleLine("Appearance ID:", tostring(appearanceID))
			tooltip:AddDoubleLine("Is Collected:", tostring(isCollected))
			tooltip:AddDoubleLine("Item Source:", sourceID and tostring(sourceID) or "none")
			tooltip:AddDoubleLine("Should Retry:", tostring(shouldRetry))

			if appearanceID then
				local hasAppearance, matchedSource = PlayerHasAppearance(appearanceID)
				tooltip:AddDoubleLine("PlayerHasAppearance:", tostring(hasAppearance))
				tooltip:AddDoubleLine("Has Matched Source:", matchedSource and matchedSource.name or "none")
				local canCollect, matchedSource = PlayerCanCollectAppearance(appearanceID, itemID, itemLink)
				tooltip:AddDoubleLine("PlayerCanCollectAppearance:", tostring(canCollect))
				tooltip:AddDoubleLine("Collect Matched Source:", matchedSource and matchedSource.name or "none")
			end
		end

		tooltip:Show()
	end
end

local waitingOnItemData = {}

local function IsGearSetStatus(status)
	return status and status ~= L["BoA"] and status ~= L["BoE"]
end

local function SetIconPositionAndSize(icon, startingPoint, offset, size, iconOffset)
	icon:ClearAllPoints()

	local offsetSum = offset - iconOffset
	if startingPoint == "TOPRIGHT" then
		icon:SetPoint("TOPRIGHT", offsetSum, offsetSum)
	elseif startingPoint == "TOPLEFT" then
		icon:SetPoint("TOPLEFT", offsetSum * -1, offsetSum)
	elseif startingPoint == "BOTTOMRIGHT" then
		icon:SetPoint("BOTTOMRIGHT", offsetSum, offsetSum * -1)
	elseif startingPoint == "BOTTOMLEFT" then
		icon:SetPoint("BOTTOMLEFT", offsetSum * -1, offsetSum * -1)
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

local function IsBankOrBags(bag)
	local isBankOrBags = false

	if bag ~= "AuctionFrame" and 
	   bag ~= "MerchantFrame" and 
	   bag ~= "GuildBankFrame" and
	   bag ~= "EncounterJournal" and
	   bag ~= "LootFrame" and
	   bag ~= "GroupLootFrame" then
		isBankOrBags = true
	end

	return isBankOrBags
end

local function ShouldHideBindingStatus(bag, bindingStatus)
	local shouldHide = false

	if bag == "AuctionFrame" then
		shouldHide = true
	end

	if not CaerdonWardrobeConfig.Binding.ShowStatus.BankAndBags and IsBankOrBags(bag) then
		shouldHide = true
	end

	if not CaerdonWardrobeConfig.Binding.ShowStatus.GuildBank and bag == "GuildBankFrame" then
		shouldHide = true
	end

	if not CaerdonWardrobeConfig.Binding.ShowStatus.Merchant and bag == "MerchantFrame" then
		shouldHide = true
	end

	if not CaerdonWardrobeConfig.Binding.ShowBoA and bindingStatus == L["BoA"] then
		shouldHide = true
	end

	if not CaerdonWardrobeConfig.Binding.ShowBoE and bindingStatus == L["BoE"] then
		shouldHide = true
	end

	return shouldHide
end

local function ShouldHideOwnIcon(bag)
	local shouldHide = false

	if not CaerdonWardrobeConfig.Icon.ShowLearnable.BankAndBags and IsBankOrBags(bag) then
		shouldHide = true
	end

	if not CaerdonWardrobeConfig.Icon.ShowLearnable.GuildBank and bag == "GuildBankFrame" then
		shouldHide = true
	end

	if not CaerdonWardrobeConfig.Icon.ShowLearnable.Merchant and bag == "MerchantFrame" then
		shouldHide = true
	end

	if not CaerdonWardrobeConfig.Icon.ShowLearnable.Auction and bag == "AuctionFrame" then
		shouldHide = true
	end

	return shouldHide
end

local function ShouldHideOtherIcon(bag)
	local shouldHide = false

	if not CaerdonWardrobeConfig.Icon.ShowLearnableByOther.BankAndBags and IsBankOrBags(bag) then
		shouldHide = true
	end

	if not CaerdonWardrobeConfig.Icon.ShowLearnableByOther.GuildBank and bag == "GuildBankFrame" then
		shouldHide = true
	end

	if not CaerdonWardrobeConfig.Icon.ShowLearnableByOther.Merchant and bag == "MerchantFrame" then
		shouldHide = true
	end

	if not CaerdonWardrobeConfig.Icon.ShowLearnableByOther.Auction and bag == "AuctionFrame" then
		shouldHide = true
	end

	return shouldHide
end

local function ShouldHideSellableIcon(bag)
	local shouldHide = false

	if not CaerdonWardrobeConfig.Icon.ShowSellable.BankAndBags and IsBankOrBags(bag) then
		shouldHide = true
	end

	if not CaerdonWardrobeConfig.Icon.ShowSellable.GuildBank and bag == "GuildBankFrame" then
		shouldHide = true
	end

	if bag == "MerchantFrame" then
		shouldHide = true
	end

	if bag == "AuctionFrame" then
		shouldHide = true
	end

	return shouldHide
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

local function SetItemButtonMogStatus(originalButton, status, bindingStatus, options, bag, slot, itemID)
	local button = originalButton.caerdonButton
	if not button then
		button = CreateFrame("Frame", nil, originalButton)
		button:SetAllPoints()
		button.searchOverlay = originalButton.searchOverlay
		originalButton.caerdonButton = button
	end

	local mogStatus = button.mogStatus
	local mogAnim = button.mogAnim
	local iconPosition, showSellables, isSellable
	local otherIcon = "Interface\\Store\\category-icon-placeholder"
	local otherIconSize = 40
	local otherIconOffset = 0
	local iconOffset = 0

	if options then 
		showSellables = options.showSellables
		isSellable = options.isSellable
		if options.iconOffset then
			iconOffset = options.iconOffset
			otherIconOffset = iconOffset
		end

		if options.otherIcon then
			otherIcon = options.otherIcon
		end

		if options.otherIconSize then
			otherIconSize = options.otherIconSize
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
		SetIconPositionAndSize(mogStatus, iconPosition, 15, 40, iconOffset)
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
		if status == "own" or status == "ownPlus" or status == "otherPlus" or status == "refundable" or status == "openable" then
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

	local alpha = 1
	if status == "refundable" and not ShouldHideSellableIcon(bag) then
		SetIconPositionAndSize(mogStatus, iconPosition, 3, 15, iconOffset)
		alpha = 0.9
		mogStatus:SetTexture("Interface\\COMMON\\mini-hourglass")
	elseif status == "openable" and not ShouldHideSellableIcon(bag) then -- TODO: Add separate option for showing
			SetIconPositionAndSize(mogStatus, iconPosition, 15, 40, iconOffset)
			mogStatus:SetTexture("Interface\\Store\\category-icon-free")
			mogStatus:SetVertexColor(1, 1, 1)
	elseif status == "own" or status == "ownPlus" then
		if not ShouldHideOwnIcon(bag) then
			SetIconPositionAndSize(mogStatus, iconPosition, 15, 40, iconOffset)
			mogStatus:SetTexture("Interface\\Store\\category-icon-featured")
			mogStatus:SetVertexColor(1, 1, 1)
			if status == "ownPlus" then
				mogStatus:SetVertexColor(0.4, 1, 0)
			end
		else
			mogStatus:SetTexture("")
		end
	elseif status == "other" or status == "otherPlus" then
		if not ShouldHideOtherIcon(bag) then
			SetIconPositionAndSize(mogStatus, iconPosition, 15, otherIconSize, otherIconOffset)
			mogStatus:SetTexture(otherIcon)
			mogStatus:SetVertexColor(1, 1, 1)
			if status == "otherPlus" then
				mogStatus:SetVertexColor(0.4, 1, 0)
			end
		else
			mogStatus:SetTexture("")
		end
	elseif status == "collected" then
		if not IsGearSetStatus(bindingStatus) and showSellables and isSellable and not ShouldHideSellableIcon(bag) then -- it's known and can be sold
			SetIconPositionAndSize(mogStatus, iconPosition, 10, 30, iconOffset)
			alpha = 0.9
			mogStatus:SetTexture("Interface\\Store\\category-icon-bag")
		elseif IsGearSetStatus(bindingStatus) and CaerdonWardrobeConfig.Binding.ShowGearSetsAsIcon then
			SetIconPositionAndSize(mogStatus, iconPosition, 10, 30, iconOffset)
			mogStatus:SetTexture("Interface\\Store\\category-icon-clothes")
		else
			mogStatus:SetTexture("")
		end
	elseif status == "waiting" then
		alpha = 0.5
		SetIconPositionAndSize(mogStatus, iconPosition, 10, 30, iconOffset)
		mogStatus:SetTexture("Interface\\Common\\StreamCircle")
	elseif IsGearSetStatus(bindingStatus) and CaerdonWardrobeConfig.Binding.ShowGearSetsAsIcon then
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

local function SetItemButtonBindType(button, mogStatus, bindingStatus, options, bag, itemID)
	local bindsOnText = button.bindsOnText

	if not bindingStatus and not bindsOnText then return end
	if not bindingStatus or ShouldHideBindingStatus(bag, bindingStatus) then
		if bindsOnText then
			bindsOnText:SetText("")
		end
		return
	end

	if not bindsOnText then
		bindsOnText = button:CreateFontString(nil, "BORDER", "SystemFont_Outline_Small") 
		button.bindsOnText = bindsOnText
	end

	bindsOnText:ClearAllPoints()
	bindsOnText:SetWidth(button:GetWidth())

	if CaerdonWardrobeConfig.Binding.Position == "BOTTOM" then
		bindsOnText:SetPoint("BOTTOMRIGHT", 0, 2)
		if bindingStatus == L["BoA"] then
			if button.count and button.count > 1 then
				bindsOnText:SetPoint("BOTTOMRIGHT", 0, 15)
			end
		end
	elseif CaerdonWardrobeConfig.Binding.Position == "CENTER" then
		bindsOnText:SetPoint("CENTER", 0, 0)
	elseif CaerdonWardrobeConfig.Binding.Position == "TOP" then
		bindsOnText:SetPoint("TOPRIGHT", 0, -2)
	end

	local bindingText
	if IsGearSetStatus(bindingStatus) then -- is gear set
		if CaerdonWardrobeConfig.Binding.ShowGearSets and not CaerdonWardrobeConfig.Binding.ShowGearSetsAsIcon then
			bindingText = "|cFFFFFFFF" .. bindingStatus .. "|r"
		end
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
	SetItemButtonMogStatus(button, "waiting", nil, options, bag, slot, itemID)
	isItemUpdateRequested = true
end

local function ItemIsSellable(itemID, itemLink)
	local isSellable = true
	if itemID == 23192 then -- Tabard of the Scarlet Crusade needs to be worn for a vendor at Darkmoon Faire
		isSellable = false
	elseif itemID == 116916 then -- Gorepetal's Gentle Grasp allows faster herbalism in Draenor
		isSellable = false
	end
	return isSellable
end

local function DebugItem(itemID, itemLink, bag, slot)

	if itemLink then
		local testID = GetItemID(itemLink)
		if testID ~= itemID then
			DebugItem(testID, itemLink, bag, slot)
		end
	end

	print ('=============================================')
	print ('Item: ' .. itemID, ' ItemLink: ' .. itemLink)

	print ( '---- Blizzard API')
	local canBeChanged, noChangeReason, canBeSource, noSourceReason = C_Transmog.GetItemInfo(itemID)
	print ('Can Be Changed: ' .. tostring(canBeChanged) .. ', No Change Reason: ' .. tostring(noChangeReason) .. ', Can Be Source: ' .. tostring(canBeSource) .. ', No Source Reason: ' .. tostring(noSourceReason))

    local hasTransmog = C_TransmogCollection.PlayerHasTransmog(itemID)
	print ('Has Transmog: ' .. tostring(hasTransmog))

	local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemLink)
	print ('Appearance ID: ' .. tostring(appearanceID) .. ', Source ID: ' .. tostring(sourceID))

    if sourceID and sourceID ~= NO_TRANSMOG_SOURCE_ID then
        categoryID, appearanceID, canEnchant, texture, isCollected, sourceItemLink = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
        print ('Category ID: ' .. tostring(categoryID) .. ', Appearance ID: ' .. tostring(appearanceID) .. ', Can Enchant: ' .. tostring(canEnchant) .. ', Texture: ' .. tostring(texture) .. ', Is Collected: ' .. tostring(isCollected) .. ', Source Item Link: ' .. sourceItemLink)

        if sourceItemLink then
			local _, _, quality = GetItemInfo(sourceItemLink)
			print ('Source Quality: ' .. tostring(quality))
		else
			print ('No Source Item Link!')
		end
	else
		print ('No Transmog Source ID!')
	end

	if IsBankOrBags(bag) then
	 	local money, itemCount, refundSec, currencyCount, hasEnchants = GetContainerItemPurchaseInfo(bag, slot, isEquipped);
	 	print ('Money: ' .. tostring(money) .. ', Item Count: ' .. tostring(itemCount) .. ', Refund Sec: ' .. tostring(refundSec) .. ', Currency Count: ' .. tostring(currencyCount) .. ', Has Enchants: ' .. tostring(hasEnchants))
	end

	print ( '---- Addon API')
	local bindingStatus, needsItem, hasUse, isDressable, isInEquipmentSet, isBindOnPickup, isCompletionistItem, shouldRetry = GetBindingStatus(bag, slot, itemID, itemLink)
	print ('Binding Status: ' .. tostring(bindingStatus) .. ', Needs Item: ' .. tostring(needsItem) .. ', HasUse: ' .. tostring(hasUse) .. ', Is Dressable: ' .. tostring(isDressable) .. ', Is In Equipment Set: ' .. tostring(isInEquipmentSet) .. ', Is BoP: ' .. tostring(isBindOnPickup) .. ', Is Completionist: ' .. tostring(isCompletionistItem) .. ', Should Retry: ' .. tostring(shouldRetry))

	local appearanceID, isCollected, sourceID, shouldRetry = GetItemAppearance(itemID, itemLink)
	print ('Appearance ID: ' .. tostring(appearanceID) .. ', Is Collected: ' .. tostring(isCollected) .. ', Source ID: ' .. tostring(sourceID) .. ', Should Retry: ' .. tostring(shouldRetry))

	local sourceID, shouldRetry = GetItemSource(itemID, itemLink)
	print ('Source ID: ' .. tostring(sourceID) .. ', Should Retry: ' .. tostring(shouldRetry))

	if appearanceID then
		local canCollect, matchedSource, shouldRetry = PlayerCanCollectAppearance(appearanceID, itemID, itemLink)
		print ('canCollect: ' .. tostring(canCollect) .. ', matchedSource: ' .. tostring(matchedSource) .. ', shouldRetry: ' .. tostring(shouldRetry))
	end
end

local function GetBankContainer(button)
	local containerID = button:GetParent():GetID();
	if( button.isBag ) then
		containerID = -ITEM_INVENTORY_BANK_BAG_OFFSET;
		return
	end

	return containerID
end

local function ProcessItem(itemID, bag, slot, button, options, itemProcessed)
	local bindingText
	local mogStatus = nil

   	if not options then
   		options = {}
   	end

	local showMogIcon = options.showMogIcon
	local showBindStatus = options.showBindStatus
	local showSellables = options.showSellables

	local canBeChanged, noChangeReason, canBeSource, noSourceReason = C_Transmog.GetItemInfo(itemID)

	local itemLink = GetItemLinkLocal(bag, slot)
	if bag == "EncounterJournal" and not itemLink then
		return
	end

	-- print(itemLink .. ": " .. itemID)

 		-- local printable = gsub(itemLink, "\124", "\124\124");
 		-- print(printable)
		-- local itemString = string.match(itemLink, "item[%-?%d:]+")
		-- print(itemLink .. ": " .. itemID .. ", printable: " .. tostring(printable))

  	-- if itemID == 82800 then
   		-- DebugItem(itemID, itemLink, bag, slot)
   	-- end
	local bindingStatus, needsItem, hasUse, isDressable, isInEquipmentSet, isBindOnPickup, isCompletionistItem, shouldRetry
	local appearanceID, isCollected, sourceID

	bindingStatus, needsItem, hasUse, isDressable, isInEquipmentSet, isBindOnPickup, isCompletionistItem, shouldRetry = GetBindingStatus(bag, slot, itemID, itemLink)
	if shouldRetry then
		QueueProcessItem(itemLink, itemID, bag, slot, button, options, itemProcessed)
		return
	end

   	if IsCollectibleLink(itemLink) then
   		shouldRetry = false
   	else
		appearanceID, isCollected, sourceID, shouldRetry = GetItemAppearance(itemID, itemLink)
		if shouldRetry then
			QueueProcessItem(itemLink, itemID, bag, slot, button, options, itemProcessed)
			return
		end
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
				elseif bag == "EncounterJournal" and needsItem then
					mogStatus = "other"
				elseif (bag == "LootFrame" or bag == "GroupLootFrame") and needsItem and not isBindOnPickup then
					mogStatus = "other"
				end
			end
		else

			if isCompletionistItem then
				-- You have this, but you want them all.  Why?  Because.
				local _, _, _, _, reqLevel, class, subclass, _, equipSlot = GetItemInfo(itemID)
				local playerLevel = UnitLevel("player")

				if playerLevel >= reqLevel then
					mogStatus = "ownPlus"
				else
					mogStatus = "otherPlus"
				end
			-- If an item isn't flagged as a source or has a usable effect,
			-- then don't mark it as sellable right now to avoid accidents.
			-- May need to expand this to account for other items, too, for now.
			elseif canBeSource and not isInEquipmentSet then
				if isDressable and not shouldRetry then -- don't flag items for sale that have use effects for now
					if IsBankOrBags(bag) then
					 	local money, itemCount, refundSec, currencyCount, hasEnchants = GetContainerItemPurchaseInfo(bag, slot, isEquipped);
						if hasUse and refundSec then
							mogStatus = "refundable"
						elseif not hasUse then
							mogStatus = "collected"
						end
					else 
						mogStatus = "collected"
					end
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
		if ((canBeSource and isDressable) or IsMountLink(itemLink)) and not shouldRetry then
			local _, _, _, _, reqLevel, class, subclass, _, equipSlot = GetItemInfo(itemID)
			local playerLevel = UnitLevel("player")

			if not reqLevel or playerLevel >= reqLevel then
				mogStatus = "own"
			else
				print(itemLink .. ": " .. tostring(reqLevel))
				mogStatus = "other"
			end
		elseif IsPetLink(itemLink) or IsToyLink(itemLink) then
			mogStatus = "own"
		end
	else
		if canBeSource then
	        local hasTransmog = C_TransmogCollection.PlayerHasTransmog(itemID)
	        if hasTransmog and not hasUse and isDressable then
	        	-- Tabards don't have an appearance ID and will end up here.
	        	mogStatus = "collected"
	        end
	    end

	    if(IsBankOrBags(bag)) then	    	
	    	local containerID = bag
	    	local containerSlot = slot

			local texture, itemCount, locked, quality, readable, lootable, _ = GetContainerItemInfo(containerID, containerSlot);
			if lootable then
				local startTime, duration, isEnabled = GetContainerItemCooldown(containerID, containerSlot)
				if duration > 0 and not isEnabled then
					mogStatus = "refundable" -- Can't open yet... show timer
				else
					mogStatus = "openable"
				end
			end

		elseif bag == "MerchantFrame" then
			if (MerchantFrame.selectedTab == 1) then
				-- TODO: If I can ever figure out how to process pets in the MerchantFrame
			else
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
		SetItemButtonMogStatus(button, mogStatus, bindingStatus, options, bag, slot, itemID)
		SetItemButtonBindType(button, mogStatus, bindingStatus, options, bag, itemID)
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

		-- Turning off item name check for now as it seems unnecessary - revisit if problems
		-- local itemName = GetItemInfoLocal(itemID, bag, slot)
		local itemLink = GetItemLinkLocal(bag, slot)
		if itemLink == nil then
		-- if itemName == nil or itemLink == nil then
			SetItemButtonMogStatus(button, "waiting", nil, options, bag, slot, itemID)
			waitBag[tostring(slot)] = { itemID = itemID, bag = bag, slot = slot, button = button, options = options, itemProcessed = itemProcessed}
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

function CaerdonWardrobe:RegisterBagAddon(options)
	isBagAddon = true
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
	-- local containerID = GetBankContainer(button)
	-- local buttonID = button:GetID()

	-- local bag = "BankFrame"
	-- local slot = button:GetInventorySlot();
	local bag = GetBankContainer(button)
	local slot = button:GetID()

	-- local itemID = GetContainerItemID(containerID, buttonID)
	if bag and slot then
		local itemID = GetContainerItemID(bag, slot)
		ProcessOrWaitItem(itemID, bag, slot, button, { showMogIcon=true, showBindStatus=true, showSellables=true })
	end
end

hooksecurefunc("BankFrameItemButton_Update", OnBankItemUpdate)

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
				local itemID = GetItemID(itemLink)
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

		local numBatchAuctions, totalAuctions = GetNumAuctionItems("list");
		local shouldHide = index > (numBatchAuctions + (NUM_AUCTION_ITEMS_PER_PAGE * AuctionFrameBrowse.page));
		if ( not shouldHide ) then
			name, texture, count, quality, canUse, level, levelColHeader, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemId, hasAllInfo =  GetAuctionItemInfo("list", auctionIndex);
			
			if ( not hasAllInfo ) then --Bug  145328
				shouldHide = true;
			end
		end

		if not shouldHide then
			local bag = "AuctionFrame"
			local slot = auctionIndex

			local itemLink = GetAuctionItemLink("list", auctionIndex)
			if(itemLink) then
				local itemID = GetItemID(itemLink)
				if itemID and button then
					ProcessOrWaitItem(itemID, bag, slot, button, { showMogIcon=true, showBindStatus=false, showSellables=false })
				end
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

local function OnBuybackUpdate()
	local numBuybackItems = GetNumBuybackItems();

	for index=1, BUYBACK_ITEMS_PER_PAGE, 1 do -- Only 1 actual page for buyback right now
		if index <= numBuybackItems then
			local button = _G["MerchantItem"..index.."ItemButton"];

			local bag = "MerchantFrame"
			local slot = index

			local itemID = C_MerchantFrame.GetBuybackItemID(index)
			ProcessOrWaitItem(itemID, bag, slot, button, { showMogIcon=true, showBindStatus=true, showSellables=false})
		end
	end
end

hooksecurefunc("MerchantFrame_UpdateMerchantInfo", OnMerchantUpdate)
hooksecurefunc("MerchantFrame_UpdateBuybackInfo", OnBuybackUpdate)

local ignoreEvents = {
	["APPEARANCE_SEARCH_UPDATED"] = {},
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
	["RECEIVED_ACHIEVEMENT_LIST"] = {},
	["QUEST_LOG_UPDATE"] = {},
	["SPELL_UPDATE_COOLDOWN"] = {},
	["SPELL_UPDATE_USABLE"] = {},
	["UNIT_ABSORBE_AMOUNT_CHANGED"] = {},
	["UNIT_AURA"] = {},
	["UNIT_POWER"] = {},
	["UNIT_POWER_FREQUENT"] = {},
	["UPDATE_INVENTORY_DURABILITY"] = {},
	["UPDATE_MOUSEOVER_UNIT"] = {},
	["UPDATE_PENDING_MAIL"] = {},
	["UPDATE_WORLD_STATES"] = {},
	["QUESTLINE_UPDATE"] = {},
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

local function OnEncounterJournalSetLootButton(item)
	local itemID, encounterID, name, icon, slot, armorType, itemLink = EJ_GetLootInfoByIndex(item.index);
	local options = {
		iconOffset = 7,
		otherIcon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
		otherIconSize = 20,
		otherIconOffset = 15,
		overridePosition = "TOPLEFT"
	}

	if name then
		ProcessItem(itemID, "EncounterJournal", item, item, options)
	end
end

eventFrame = CreateFrame("FRAME", "CaerdonWardrobeFrame")
eventFrame:RegisterEvent "ADDON_LOADED"
eventFrame:RegisterEvent "PLAYER_LOGOUT"
eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:SetScript("OnUpdate", OnUpdate)
if DEBUG_ENABLED then
	GameTooltip:HookScript("OnTooltipSetItem", addDebugInfo)
end

C_TransmogCollection.SetShowMissingSourceInItemTooltips(true)
SetCVar("missingTransmogSourceInItemTooltips", 1)

function NS:GetDefaultConfig()
	return {
		Version = 7,
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
			}
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
	end
end

function eventFrame:PLAYER_LOGOUT()
end

function eventFrame:ADDON_LOADED(name)
	if name == ADDON_NAME then
		ProcessSettings()
		NS:FireConfigLoaded()

		if IsLoggedIn() then
			OnEvent(eventFrame, "PLAYER_LOGIN")
		else
			eventFrame:RegisterEvent "PLAYER_LOGIN"
		end
	elseif name == "Blizzard_AuctionUI" then
		hooksecurefunc("AuctionFrameBrowse_Update", OnAuctionBrowseUpdate)
	elseif name == "Blizzard_GuildBankUI" then
		hooksecurefunc("GuildBankFrame_Update", OnGuildBankFrameUpdate)
	elseif name == "Blizzard_EncounterJournal" then
		hooksecurefunc("EncounterJournal_SetLootButton", OnEncounterJournalSetLootButton)
	end
end

function eventFrame:PLAYER_LOGIN(...)
	if DEBUG_ENABLED then
		eventFrame:RegisterAllEvents()
	else
		-- eventFrame:RegisterEvent "PLAYERBANKSLOTS_CHANGED"
		eventFrame:RegisterEvent "BAG_OPEN"
		eventFrame:RegisterEvent "BAG_UPDATE"
		eventFrame:RegisterEvent "BAG_UPDATE_DELAYED"
		eventFrame:RegisterEvent "BANKFRAME_OPENED"
		eventFrame:RegisterEvent "GET_ITEM_INFO_RECEIVED"
		eventFrame:RegisterEvent "TRANSMOG_COLLECTION_UPDATED"
		-- eventFrame:RegisterEvent "TRANSMOG_COLLECTION_ITEM_UPDATE"
		eventFrame:RegisterEvent "EQUIPMENT_SETS_CHANGED"
		eventFrame:RegisterEvent "MERCHANT_UPDATE"
	end
	C_TransmogCollection.SetShowMissingSourceInItemTooltips(true)
end

function RefreshMainBank()
	if not isBagAddon then
		for i=1, NUM_BANKGENERIC_SLOTS, 1 do
			button = BankSlotsFrame["Item"..i];
			OnBankItemUpdate(button);
		end
	end
end

local function RefreshItems()
	-- TODO: Add debounce to prevent excessive refresh
	if DEBUG_ENABLED then
		print("=== Refreshing Transmog Items")
	end
	cachedBinding = {}
	cachedIsDressable = {}

	if MerchantFrame:IsShown() then 
		if MerchantFrame.selectedTab == 1 then
			OnMerchantUpdate()
		else
			OnBuybackUpdate()
		end
	end

	if AuctionFrame and AuctionFrame:IsShown() then
		OnAuctionBrowseUpdate()
	end

	if BankFrame:IsShown() then
		RefreshMainBank()
	end

	for i=1, NUM_CONTAINER_FRAMES, 1 do
		local frame = _G["ContainerFrame"..i];
		waitingOnBagUpdate[tostring(i)] = true
		isBagUpdateRequested = true
	end
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
	C_Timer.After(1, function() RefreshItems() end)
end

hooksecurefunc("EquipPendingItem", OnEquipPendingItem)

local function OnOpenBag(bagID)
	if not isBagAddon then
		for i=1, NUM_CONTAINER_FRAMES, 1 do
			local frame = _G["ContainerFrame"..i];
			if ( frame:IsShown() and frame:GetID() == bagID ) then
				waitingOnBagUpdate[tostring(i)] = true
				isBagUpdateRequested = true
				break
			end
		end
	end
end

local function OnOpenBackpack()
	if not isBagAddon then
		isBagUpdateRequested = true
	end
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
				-- Turning off item name check for now as it seems unnecessary - revisit if problems
				-- local itemName = GetItemInfoLocal(itemID, slotData.bag, slotData.slot)
				local itemLink = GetItemLinkLocal(slotData.bag, slotData.slot)

				if itemLink then
				-- if itemLink and itemName then
					ProcessItem(itemID, slotData.bag, slotData.slot, slotData.button, slotData.options, slotData.itemProcessed)
				else
					ProcessOrWaitItem(itemID, slotData.bag, slotData.slot, slotData.button, slotData.options, slotData.itemProcessed)
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

function eventFrame:MERCHANT_UPDATE()
	RefreshItems()
end

function eventFrame:EQUIPMENT_SETS_CHANGED()
	RefreshItems()
end

function eventFrame:BANKFRAME_OPENED()
	-- RefreshMainBank()
end

-- Turning this off for now as I made fixes for the container hook and don't
-- need to do this twice.  Keeping around for a bit just in case.
-- function eventFrame:PLAYERBANKSLOTS_CHANGED(slot, arg2)
-- 	if ( slot <= NUM_BANKGENERIC_SLOTS ) then
-- 		OnBankItemUpdate(BankSlotsFrame["Item"..slot]);
-- 	else
-- 		OnBankItemUpdate(BankSlotsFrame["Bag"..(slot-NUM_BANKGENERIC_SLOTS)]);
-- 	end
-- end

local function OnLootFrameUpdateButton(index)
	local numLootItems = LootFrame.numLootItems;
	local numLootToShow = LOOTFRAME_NUMBUTTONS;

	if LootFrame.AutoLootTable then
		numLootItems = #LootFrame.AutoLootTable
	end

	if numLootItems > LOOTFRAME_NUMBUTTONS then
		numLootToShow = numLootToShow - 1
	end

	local isProcessing = false
	
	local button = _G["LootButton"..index];
	local slot = (numLootToShow * (LootFrame.page - 1)) + index;
	if slot <= numLootItems then
		if ((LootSlotHasItem(slot) or (LootFrame.AutoLootTable and LootFrame.AutoLootTable[slot])) and index <= numLootToShow) then
			-- texture, item, quantity, quality, locked, isQuestItem, questId, isActive = GetLootSlotInfo(slot)
			link = GetLootSlotLink(slot)
			if link then
				local itemID = GetItemID(link)
				if itemID then
					isProcessing = true
					ProcessOrWaitItem(itemID, "LootFrame", { index = slot, link = link }, button, nil)
				end
			end
		end
	end

	if not isProcessing then
		SetItemButtonMogStatus(button, nil)
		SetItemButtonBindType(button, nil)
	end
end

function OnGroupLootFrameShow(frame)
	-- local texture, name, count, quality, bindOnPickUp, canNeed, canGreed, canDisenchant, reasonNeed, reasonGreed, reasonDisenchant, deSkillRequired = GetLootRollItemInfo(frame.rollID)
	-- if name == nil then
	-- 	return
	-- end

	local itemLink = GetLootRollItemLink(frame.rollID)
	if itemLink == nil then
		return
	end

	local itemID = GetItemID(itemLink)
	if itemID then
		ProcessOrWaitItem(itemID, "GroupLootFrame", { index = frame.rollID, link = itemLink}, frame.IconFrame, nil)
	end
end

hooksecurefunc("LootFrame_UpdateButton", OnLootFrameUpdateButton)

GroupLootFrame1:HookScript("OnShow", OnGroupLootFrameShow)
GroupLootFrame2:HookScript("OnShow", OnGroupLootFrameShow)
GroupLootFrame3:HookScript("OnShow", OnGroupLootFrameShow)
GroupLootFrame4:HookScript("OnShow", OnGroupLootFrameShow)

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

-- BAG_OPEN
-- GUILDBANKBAGSLOTS_CHANGED
-- GUILDBANKFRAME_OPENED
