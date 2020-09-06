local DEBUG_ENABLED = false
-- local DEBUG_ITEM = 82800
local ADDON_NAME, NS = ...
local L = NS.L
local isBagUpdate = false
local ignoreDefaultBags = false

local version, build, date, tocversion = GetBuildInfo()
local isShadowlands = tonumber(build) > 35700

CaerdonWardrobe = {}

CaerdonWardrobeMixin = {}

function CaerdonWardrobeMixin:OnLoad()
	self:RegisterEvent "ADDON_LOADED"
	self:RegisterEvent "PLAYER_LOGOUT"
	self:RegisterEvent "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"
	self:RegisterEvent "AUCTION_HOUSE_SHOW"
	self:RegisterEvent "BAG_OPEN"
	self:RegisterEvent "BAG_UPDATE"
	self:RegisterEvent "UNIT_SPELLCAST_SUCCEEDED"
	self:RegisterEvent "BAG_UPDATE_DELAYED"
	self:RegisterEvent "BANKFRAME_OPENED"
	-- self:RegisterEvent "GET_ITEM_INFO_RECEIVED"
	self:RegisterEvent "TRANSMOG_COLLECTION_UPDATED"
	-- self:RegisterEvent "TRANSMOG_COLLECTION_ITEM_UPDATE"
	self:RegisterEvent "EQUIPMENT_SETS_CHANGED"
	self:RegisterEvent "UPDATE_EXPANSION_LEVEL"
	self:RegisterEvent "MERCHANT_UPDATE"
	self:RegisterEvent "PLAYER_LOOT_SPEC_UPDATED"
	self:RegisterEvent "PLAYER_LOGIN"
end

StaticPopupDialogs["CAERDON_WARDROBE_MULTIPLE_BAG_ADDONS"] = {
  text = "It looks like multiple bag addons are currently running (%s)! I can't guarantee Caerdon Wardrobe will work properly in this case.  You should only have one bag addon enabled!",
  button1 = "Got it!",
  OnAccept = function()
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
}		


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

local model = CreateFrame('DressUpModel')

local function GetItemID(itemLink)
	if not itemLink then
		return nil
	end

	return tonumber(itemLink:match("item:(%d+)") or itemLink:match("battlepet:(%d+)"))
end

local function IsPetLink(itemLink)
	-- TODO: This would be nice, but vendor pets don't seem to get recognized.
	-- local isPet = LinkUtil.IsLinkType(itemLink, "battlepet")
	-- return isPet
	
	local itemID = GetItemID(itemLink)
	if itemID == 82800 then
		return true -- It's showing up as [Pet Cage] for whatever reason
	elseif( itemLink ) then 
		local _, _, _, linkType, linkID, _, _, _, _, _, battlePetID, battlePetDisplayID = strsplit(":|H", itemLink);
		if ( linkType == "item") then
			local _, _, _, creatureID, _, _, _, _, _, _, _, displayID, speciesID = C_PetJournal.GetPetInfoByItemID(tonumber(linkID));
			if (creatureID and displayID) then
				return true;
			end
		elseif ( linkType == "battlepet" ) then
			if battlePetID and battlePetID ~= "" and battlePetID ~= "0" then
				local speciesID, _, _, _, _, displayID, _, _, _, _, creatureID = C_PetJournal.GetPetInfoByPetID(battlePetID);
				if ( speciesID == tonumber(linkID)) then
					if (creatureID and displayID) then
						return true;
					end	
				else
					speciesID = tonumber(linkID);
					local _, _, _, creatureID, _, _, _, _, _, _, _, displayID = C_PetJournal.GetPetInfoBySpeciesID(speciesID);
					displayID = (battlePetDisplayID and battlePetDisplayID ~= "0") and battlePetDisplayID or displayID;
					if (creatureID and displayID) then
						return true;
					end	
				end
			else
				-- Mostly in place as a hack for bad battlepet links from addons
				speciesID = tonumber(linkID);
				local _, _, _, creatureID, _, _, _, _, _, _, _, displayID = C_PetJournal.GetPetInfoBySpeciesID(speciesID);
				displayID = (battlePetDisplayID and battlePetDisplayID ~= "0") and battlePetDisplayID or displayID;
				if (creatureID and displayID) then
					return true;
				end	
			end
		end
	end

	return false
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

local function IsRecipeLink(itemLink)
	local isRecipe = false
	local itemName, itemLinkInfo, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
itemEquipLoc, iconFileDataID, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID, 
isCraftingReagent = GetItemInfo(itemLink)

	if itemClassID == LE_ITEM_CLASS_RECIPE then
		isRecipe = true
	end

	return isRecipe
end

local function IsCollectibleLink(itemLink)
	local itemID = GetItemID(itemLink)
	local isDebugItem = itemID and itemID == DEBUG_ITEM
	if isDebugItem then
		local isPet = IsPetLink(itemLink)
		local isMount = IsMountLink(itemLink)
		local isToy = IsToyLink(itemLink)
		local isRecipe = IsRecipeLink(itemLink)

		print("isPet: " .. tostring(isPet) .. ", isMount: " .. tostring(isMount) .. ", isToy: " .. tostring(isToy) .. ", isRecipe: " .. tostring(isRecipe))
	end

	return IsPetLink(itemLink) or IsMountLink(itemLink) or IsToyLink(itemLink) or IsRecipeLink(itemLink)
end

local function IsDressableItemCheck(itemID, itemLink)
	local isDressable = true
	local shouldRetry = false
	local slot

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

	return isDressable, shouldRetry, slot
end

local function GetItemSource(itemID, itemLink)
	local itemSources
	local isDressable, shouldRetry, slot = IsDressableItemCheck(itemID, itemLink)
	if not shouldRetry then
		if isDressable then
			-- Looks like I can use this now.  Keeping the old code around for a bit just in case.
			-- Actually, still seeing problems with this...try it first but fallback to model
			-- I've tried several times to remove this.  Seems to work at first.. but then...
			local appearanceID, sourceID, arg1, arg2 = C_TransmogCollection.GetItemInfo(itemLink)
			if sourceID then
				itemSources = sourceID
			else
			    model:SetUnit('player')
			    model:Undress()
			    model:TryOn(itemLink, slot)
			    itemSources = model:GetSlotTransmogSources(slot)
			end
		end
	end

	return itemSources, shouldRetry
end

local function GetItemAppearance(itemID, itemLink)
	local categoryID, appearanceID, canEnchant, texture, isCollected, sourceItemLink
	local sourceID, shouldRetry = GetItemSource(itemID, itemLink)

    if sourceID and sourceID ~= NO_TRANSMOG_SOURCE_ID then
        categoryID, appearanceID, canEnchant, texture, isCollected, sourceItemLink, _, _, appearanceSubclass = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
		if sourceItemLink then
			local _, _, quality = GetItemInfo(sourceItemLink)
			-- Skip artifact weapons and common for now
			if quality == Enum.ItemQuality.Common then
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

    local sources = C_TransmogCollection.GetAllAppearanceSources(appearanceID)
    local matchedSource
    if sources then
		for i, sourceID in pairs(sources) do
			if sourceID and sourceID ~= NO_TRANSMOG_SOURCE_ID then
				local categoryID, appearanceID, canEnchant, texture, isCollected, sourceItemLink = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)

				if isCollected then
					matchedSource = source
					hasAppearance = true
					break
				end
			end
        end
    end

    return hasAppearance, matchedSource
end
 
local function PlayerCanCollectAppearance(sourceID, appearanceID, itemID, itemLink)
	local isDebugItem = itemID and itemID == DEBUG_ITEM
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

	if playerLevel >= reqLevel then
		if isDebugItem then print("Player is high enough level to collect") end
		isInfoReady, canCollect = C_TransmogCollection.PlayerCanCollectSource(sourceID)
		matchedSource = source
	    -- local sources = C_TransmogCollection.GetAppearanceSources(appearanceID)
	    -- if sources then
	    --     for i, source in pairs(sources) do
		-- 		isInfoReady, canCollect = C_TransmogCollection.PlayerCanCollectSource(source.sourceID)
		-- 		if isDebugItem then print("Info Ready: " .. tostring(isInfoReady) .. ", Can Collect: " .. tostring(canCollect)) end
	    --         if isInfoReady then
	    --         	if canCollect then
		--             	matchedSource = source
		--             end
	    --             break
	    --         else
	    --         	shouldRetry = true
	    --         end
	    --     end
		-- else
		-- 	if isDebugItem then print("No sources found for item: " .. itemLink .. ", Appearance ID: " .. tostring(appearanceID)) end
		-- end
	end

	if equipSlot ~= "INVTYPE_CLOAK"
		and itemClassID == LE_ITEM_CLASS_ARMOR and 
		(	itemSubClassID == LE_ITEM_ARMOR_CLOTH or 
			itemSubClassID == LE_ITEM_ARMOR_LEATHER or 
			itemSubClassID == LE_ITEM_ARMOR_MAIL or
			itemSubClassID == LE_ITEM_ARMOR_PLATE)
		and itemSubClassID ~= classArmor then 
			if isDebugItem then print("Wrong armor. Can't collect: " .. itemLink) end
			canCollect = false
	end

    return canCollect, matchedSource, shouldRetry
end

local function GetItemLinkLocal(bag, slot)
	if bag == "AuctionFrame" then
		local _, itemLink = GetItemInfo(slot.itemKey.itemID);
		return itemLink
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
	elseif bag == "OpenMailFrame" then
		local name, itemID, itemTexture, count, quality, canUse = GetInboxItem(InboxFrame.openMailID, slot);
		local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
		itemEquipLoc, iconFileDataID, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID, 
		isCraftingReagent = GetItemInfo(itemID)
		return itemLink
	elseif bag == "SendMailFrame" then
		local itemName, itemID, itemTexture, stackCount, quality = GetSendMailItem(slot);
		local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
		itemEquipLoc, iconFileDataID, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID, 
		isCraftingReagent = GetItemInfo(itemID)
		return itemLink
	elseif bag == "InboxFrame" then
		local packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, itemCount, wasRead, x, y, z, isGM, firstItemQuantity, firstItemLink = GetInboxHeaderInfo(slot);
		return firstItemLink
	elseif bag == "BlackMarketScrollFrame" then
		if (slot == "HotItem") then
			local name, texture, quantity, itemType, usable, level, levelType, sellerName, minBid, minIncrement, currBid, youHaveHighBid, numBids, timeLeft, link, marketID, quality = C_BlackMarket.GetHotItem();
			return link
		else
			local name, texture, quantity, itemType, usable, level, levelType, sellerName, minBid, minIncrement, currBid, youHaveHighBid, numBids, timeLeft, link, marketID, quality = C_BlackMarket.GetItemInfoByIndex(slot);
			return link
		end
	elseif bag == "QuestButton" then
		if slot.itemLink then
			return slot.itemLink
		else
			local itemID = slot.itemID
			local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
			itemEquipLoc, iconFileDataID, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID, 
			isCraftingReagent = GetItemInfo(itemID)
			return itemLink
		end
	else
	    if bag then
	      return GetContainerItemLink(bag, slot)
	    end
	end
end

local function GetItemKey(bag, slot, itemLink)
	local itemKey
	if bag == "AuctionFrame" then
		itemKey = itemLink .. slot.index
	elseif bag == "MerchantFrame" then
		itemKey = itemLink .. slot
	elseif bag == "GuildBankFrame" then
		itemKey = itemLink .. slot.tab .. slot.index
	elseif bag == "EncounterJournal" then
		itemKey = itemLink .. bag .. slot.index
	elseif bag == "QuestButton" then
		itemKey = itemLink .. bag
	elseif bag == "LootFrame" or bag == "GroupLootFrame" then
		itemKey = itemLink
	elseif bag == "OpenMailFrame" or bag == "SendMailFrame" or bag == "InboxFrame" then
		itemKey = itemLink .. slot
	elseif bag == "BlackMarketScrollFrame" then
		itemKey = itemLink .. slot
	else
		itemKey = itemLink .. bag .. slot
	end

	return itemKey
end

local equipLocations = {}

local function GetBindingStatus(bag, slot, itemID, itemLink)
	local isDebugItem = itemID and itemID == DEBUG_ITEM

	if isDebugItem then print ("GetBindingStatus (" .. itemLink .. "): bag = " .. bag .. ", slot = " .. tostring(slot)) end

	local scanTip = CaerdonWardrobeFrameTooltip
	scanTip:ClearLines()
	-- Weird bug with scanning tooltips - have to disable showing
	-- transmog info during the scan
	C_TransmogCollection.SetShowMissingSourceInItemTooltips(false)
	SetCVar("missingTransmogSourceInItemTooltips", 0)
	local originalAlwaysCompareItems = GetCVarBool("alwaysCompareItems")
	SetCVar("alwaysCompareItems", 0)

	local itemKey = GetItemKey(bag, slot, itemLink)

	local binding
	local bindingText, needsItem, hasUse

    local isInEquipmentSet = false
    local isBindOnPickup = false
	local isCompletionistItem = false
	local matchesLootSpec = true
	local unusableItem = false
	local isDressable, shouldRetry
	local isLocked = false
	
	local tooltipSpeciesID = 0

	local isCollectionItem = IsCollectibleLink(itemLink)
	local isRecipe = IsRecipeLink(itemLink)
	local isPetLink = IsPetLink(itemLink)

    local shouldCheckEquipmentSet = false

   	if isCollectionItem then
		isDressable = false
		shouldRetry = false
	else
		isDressable, shouldRetry = IsDressableItemCheck(itemID, itemLink)
		if isDebugItem then print ("IsDressable: " .. tostring(isDressable)) end
	end

	local playerSpec = GetSpecialization();
	local playerClassID = select(3, UnitClass("player")) 
	local playerSpecID = -1
	if (playerSpec) then
		playerSpecID = GetSpecializationInfo(playerSpec, nil, nil, nil, UnitSex("player"));
	end
	local playerLootSpecID = GetLootSpecialization()
	if playerLootSpecID == 0 then
		playerLootSpecID = playerSpecID
	end

	if not shouldRetry then
		if isDebugItem then print("Processing binding") end
		needsItem = true
		if isDebugItem then print("scanTip bag: " .. bag .. ", slot: " .. tostring(slot)) end
		if bag == "AuctionFrame" then
			local itemKey = slot.itemKey
			scanTip:SetItemKey(itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix)
			tooltipSpeciesID = itemKey.battlePetSpeciesID
		elseif bag == "MerchantFrame" then
			if MerchantFrame.selectedTab == 1 then
         		scanTip:SetMerchantItem(slot)
			else
         		scanTip:SetBuybackItem(slot)
			end
		elseif bag == BANK_CONTAINER then
			local hasItem, hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = scanTip:SetInventoryItem("player", BankButtonIDToInvSlotID(slot))
			tooltipSpeciesID = speciesID
		   	if not isCollectionItem then
				shouldCheckEquipmentSet = true
			end
		elseif bag == REAGENTBANK_CONTAINER then
			local hasItem, hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = scanTip:SetInventoryItem("player", ReagentBankButtonIDToInvSlotID(slot))
		elseif bag == "GuildBankFrame" then
			local speciesID, level, breedQuality, maxHealth, power, speed, name = scanTip:SetGuildBankItem(slot.tab, slot.index)
			tooltipSpeciesID = speciesID
		elseif bag == "LootFrame" then
			scanTip:SetLootItem(slot.index)
		elseif bag == "GroupLootFrame" then
			scanTip:SetLootRollItem(slot.index)
		elseif bag == "OpenMailFrame" then
			local hasCooldown, speciesID, level, breedQuality, maxHealth, power, speed, name = scanTip:SetInboxItem(InboxFrame.openMailID, slot)
			tooltipSpeciesID = speciesID
		elseif bag == "SendMailFrame" then
			local hasCooldown, speciesID, level, breedQuality, maxHealth, power, speed, name = scanTip:SetSendMailItem(slot)
			tooltipSpeciesID = speciesID
		elseif bag == "InboxFrame" then
			local hasCooldown, speciesID, level, breedQuality, maxHealth, power, speed, name = scanTip:SetInboxItem(slot);
			tooltipSpeciesID = speciesID
		elseif bag == "BlackMarketScrollFrame" then
			scanTip:SetHyperlink(itemLink)
		elseif bag == "EncounterJournal" then
			local classID, specID = EJ_GetLootFilter();
			if (specID == 0) then
				if (playerSpec and classID == playerClassID) then
					specID = playerSpecID
				else
					specID = -1;
				end
			end
			scanTip:SetHyperlink(itemLink, classID, specID)

			local specTable = GetItemSpecInfo(itemLink)
			if specTable then
				for specIndex = 1, #specTable do
					matchesLootSpec = false

					local validSpecID = GetSpecializationInfo(specIndex, nil, nil, nil, UnitSex("player"));
					if validSpecID == playerLootSpecID then
						matchesLootSpec = true
						break
					end
				end
			end
		elseif bag == "QuestButton" then
			if slot.questItem ~= nil and slot.questItem.type ~= nil then
				if QuestInfoFrame.questLog then
					scanTip:SetQuestLogItem(slot.questItem.type, slot.index, slot.questID)
				else
					scanTip:SetQuestItem(slot.questItem.type, slot.index, slot.questID)
				end
			else
				GameTooltip_AddQuestRewardsToTooltip(scanTip, slot.questID)
				scanTip = scanTip.ItemTooltip.Tooltip
			end
		else
			local hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = scanTip:SetBagItem(bag, slot)
			tooltipSpeciesID = speciesID
			if not isCollectionItem then
				shouldCheckEquipmentSet = true
			end
		end

		local itemName, itemLinkInfo, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
		itemEquipLoc, iconFileDataID, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID, 
		isCraftingReagent = GetItemInfo(itemLink)

		isBindOnPickup = bindType == 1
		
		if shouldCheckEquipmentSet then
			if isDebugItem then print("itemEquipLoc: " .. tostring(itemEquipLoc)) end

		   -- Use equipment set for binding text if it's assigned to one
			if itemEquipLoc ~= "" and C_EquipmentSet.CanUseEquipmentSets() then

				-- Flag to ensure flagging multiple set membership
				local isBindingTextDone = false

				for setIndex=1, C_EquipmentSet.GetNumEquipmentSets() do
			        local equipmentSetIDs = C_EquipmentSet.GetEquipmentSetIDs()
			        local equipmentSetID = equipmentSetIDs[setIndex]
							name, icon, setID, isEquipped, numItems, numEquipped, numInventory, numMissing, numIgnored = C_EquipmentSet.GetEquipmentSetInfo(equipmentSetID)

			        local equipLocations = C_EquipmentSet.GetItemLocations(equipmentSetID)
			        if equipLocations then
						for locationIndex=INVSLOT_FIRST_EQUIPPED , INVSLOT_LAST_EQUIPPED do
							local location = equipLocations[locationIndex]
							if location ~= nil then
							    local isPlayer, isBank, isBags, isVoidStorage, equipSlot, equipBag, equipTab, equipVoidSlot = EquipmentManager_UnpackLocation(location)
							    if isDebugItem then
							    	-- print("isPlayer: " .. tostring(isPlayer) .. ", isBank: " .. tostring(isBank) .. ", isBags: " .. tostring(isBags) .. ", isVoidStorage: " .. tostring(isVoidStorage) .. ", equipSlot: " .. tostring(equipSlot) .. ", equipBag: " .. tostring(equipBag) .. ", equipTab: " .. tostring(equipTab) .. ", equipVoidSlot: " .. tostring(equipVoidSlot))
							    end
							    equipSlot = tonumber(equipSlot)
							    equipBag = tonumber(equipBag)

							    if isVoidStorage then
							    	-- Do nothing for now
							    elseif isBank and not isBags then -- player or bank
									if bag == BANK_CONTAINER and BankButtonIDToInvSlotID(slot) == equipSlot then
										if isDebugItem then print("=== Setting needs item to false due to set") end
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
										if isDebugItem then print("=== Setting needs item to false due to set 2") end
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
		end

		local canBeChanged, noChangeReason, canBeSource, noSourceReason = C_Transmog.GetItemInfo(itemID)
		if not isCollectionItem and canBeSource then
			if isDebugItem then print(itemLink .. " can be source") end
			local appearanceID, isCollected, sourceID
			appearanceID, isCollected, sourceID, shouldRetry = GetItemAppearance(itemID, itemLink)

			if sourceID and sourceID ~= NO_TRANSMOG_SOURCE_ID then 
				local hasTransmog = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID)
				if hasTransmog then
					if isDebugItem then print("=== Setting needs item to false due to has transmog") end
					needsItem = false
				else
					if CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem then
						isCompletionistItem = true
					end
				end
			else
				if isDebugItem then print("Has no source: " .. tostring(noSourceReason)) end
				needsItem = false
			end
		elseif not isCollectionItem then
			if isDebugItem then print("Can't be source: " .. tostring(noSourceReason)) end
	    	needsItem = false
	    end

		local numLines = scanTip:NumLines()
		local isPetKnown = false
		local PET_KNOWN = strmatch(ITEM_PET_KNOWN, "[^%(]+")

		if isDebugItem then print('Scan Tip Lines: ' .. tostring(numLines)) end
		if not isCollectionItem and not noSourceReason and numLines == 0 then
			if isDebugItem then print("No scan lines... retrying") end
			shouldRetry = true
		end

		if not shouldRetry then
			for lineIndex = 1, numLines do
				local scanName = scanTip:GetName()
				local line = _G[scanName .. "TextLeft" .. lineIndex]
				local lineText = line:GetText()
				if lineText then
					-- TODO: Look at switching to GetItemSpell
					-- if isDebugItem then print ("Tip: " .. lineText) end
					if strmatch(lineText, USE_COLON) or strmatch(lineText, ITEM_SPELL_TRIGGER_ONEQUIP) or strmatch(lineText, string.format(ITEM_SET_BONUS, "")) then -- it's a recipe or has a "use" effect or belongs to a set
						if not isCollectionItem then
							hasUse = true
						end

						-- TODO: Don't like matching this hard-coded string but not sure how else
						-- to prevent the expensive books from showing as learnable when I don't
						-- know how to tell if they have recipes you need.
						if isRecipe and strmatch(lineText, "Use: Re%-learn .*") then
							needsItem = false
						end
					end

					if not bindingText then
						bindingText = bindTextTable[lineText]
					end

					if lineText == RETRIEVING_ITEM_INFO then
						shouldRetry = true
						break
					elseif lineText == ITEM_SOULBOUND then
						isBindOnPickup = true
					-- TODO: Don't think we need these anymore?
					-- elseif lineText == TRANSMOGRIFY_TOOLTIP_ITEM_UNKNOWN_APPEARANCE_KNOWN then
					-- 	if CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem then
					-- 		isCompletionistItem = true
					-- 		print("Completion 1: " .. itemLink .. lineText)
					-- 	else
					-- 		needsItem = false
					-- 	end
					-- 	break
					-- elseif lineText == TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN then
					-- 	if CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem then
					-- 		isCompletionistItem = true
					-- 		print("Completion 2: " .. itemLink .. lineText)
					-- 	end
					elseif lineText == ITEM_SPELL_KNOWN then
						needsItem = false
					elseif lineText == LOCKED then
						isLocked = true
					elseif isPetLink and strmatch(lineText, PET_KNOWN) then
						isPetKnown = true
					end 

					-- TODO: Should possibly only look for "Classes:" but could have other reasons for not being usable
					local r, g, b = line:GetTextColor()
					hex = string.format("%02x%02x%02x", r*255, g*255, b*255)
					-- if isDebugItem then print("Color: " .. hex) end
					-- TODO: Provide option to show stars on BoE recipes that aren't for current toon
					-- TODO: Surely there's a better way than checking hard-coded color values for red-like things
					if hex == "fe1f1f" then
						if isRecipe then
							-- TODO: Cooking and fishing are not represented in trade skill lines right now
							-- Assuming all toons have cooking for now.

							-- TODO: Some day - look into saving toon skill lines / ranks into a DB and showing
							-- which toons could learn a recipe.

							-- local prof1, prof2, archaeology, fishing, cooking, firstAid = GetProfessions()
							local replaceSkill = "%w"
							local skillCheck = string.gsub(ITEM_MIN_SKILL, "%%s", "%(.+%)")
							skillCheck = string.gsub(skillCheck, "%(%%d%)", "%%%(%(%%d+%)%%%)")
							if strmatch(lineText, skillCheck) then
								local _, _, requiredSkill, requiredRank = string.find(lineText, skillCheck)
								local skillLines = C_TradeSkillUI.GetAllProfessionTradeSkillLines()
								for skillLineIndex = 1, #skillLines do
									local skillLineID = skillLines[skillLineIndex]
									local name, rank, maxRank, modifier, parentSkillLineID = C_TradeSkillUI.GetTradeSkillLineInfoByID(skillLineID)
									if requiredSkill == name then
										if rank < tonumber(requiredRank) then
											-- Toon either doesn't have profession or isn't high enough level.
											unusableItem = true
											if isBindOnPickup then
												needsItem = false
											end
										else
											break
										end
									end
								end
							end		
						elseif isBindOnPickup then
							if isDebugItem then print("Red text in tooltip indicates item is soulbound and can't be used by this toon") end
							unusableItem = true
							if not bag == "EncounterJournal" then
								needsItem = false
								isCompletionistItem = false
							end
						end
					end
				end
			end

			if isDebugItem then print("Is Collection Item: " .. tostring(isCollectionItem)) end

			if isCollectionItem and not unusableItem then
				if isPetLink then
					if not tooltipSpeciesID then
						-- Attempt to grab it from itemLink
						local _, _, _, linkType, linkID, _, _, _, _, _, battlePetID, battlePetDisplayID = strsplit(":|H", itemLink)
						if linkID then
							tooltipSpeciesID = tonumber(linkID)
						end
					end

					if tooltipSpeciesID and tooltipSpeciesID > 0 then
						-- Pet cages have some magic info that comes back from tooltip setup
						local numCollected = C_PetJournal.GetNumCollectedInfo(tooltipSpeciesID)
						if numCollected == nil then
							needsItem = false
						elseif numCollected > 0 then
							if isDebugItem then print("Already have it: " .. itemLink .. "- " .. numCollected) end
							needsItem = false
						else
							if isDebugItem then print("Need: " .. itemLink .. ", " .. tostring(numCollected)) end
							needsItem = true
						end
					elseif isPetKnown then
						needsItem = false
					else
						needsItem = true
					end
				end
			elseif isCollectionItem then
				if not isRecipe then
					if isDebugItem then print("Not Usable Collection Item: " .. itemLink) end
					needsItem = false
				end
			end
		end

		C_TransmogCollection.SetShowMissingSourceInItemTooltips(true)
		SetCVar("missingTransmogSourceInItemTooltips", 1)
		SetCVar("alwaysCompareItems", originalAlwaysCompareItems)
	end

	return bindingText, needsItem, hasUse, isDressable, isInEquipmentSet, isBindOnPickup, isCompletionistItem, shouldRetry, unusableItem, matchesLootSpec, isLocked
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
	   bag ~= "QuestButton" and
	   bag ~= "LootFrame" and
	   bag ~= "GroupLootFrame" and
	   bag ~= "OpenMailFrame" and
	   bag ~= "SendMailFrame" and 
	   bag ~= "InboxFrame" and
	   bag ~= "BlackMarketScrollFrame" then
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

	local alpha = 1
	mogStatus:SetVertexColor(1, 1, 1)
	if status == "refundable" and not ShouldHideSellableIcon(bag) then
		SetIconPositionAndSize(mogStatus, iconPosition, 3, 15, iconOffset)
		alpha = 0.9
		mogStatus:SetTexture("Interface\\COMMON\\mini-hourglass")
	elseif status == "openable" and not ShouldHideSellableIcon(bag) then -- TODO: Add separate option for showing
			SetIconPositionAndSize(mogStatus, iconPosition, 15, iconSize, iconOffset)
			mogStatus:SetTexture("Interface\\Store\\category-icon-free")
	elseif status == "locked" and not ShouldHideSellableIcon(bag) then -- TODO: Add separate option for showing
			SetIconPositionAndSize(mogStatus, iconPosition, 15, iconSize, iconOffset)
			mogStatus:SetTexture("Interface\\Store\\category-icon-key")
	elseif status == "oldexpansion" and not ShouldHideSellableIcon(bag) then -- TODO: Add separate option for showing
		SetIconPositionAndSize(mogStatus, iconPosition, 10, 30, iconOffset)
		alpha = 0.9
		mogStatus:SetTexture("Interface\\Store\\category-icon-wow")
	elseif status == "own" or status == "ownPlus" then
		if not ShouldHideOwnIcon(bag) then
			SetIconPositionAndSize(mogStatus, iconPosition, 15, iconSize, iconOffset)
			mogStatus:SetTexture("Interface\\Store\\category-icon-featured")
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
			if status == "otherPlus" then
				mogStatus:SetVertexColor(0.4, 1, 0)
			end
		else
			mogStatus:SetTexture("")
		end
	elseif status == "otherSpec" or status == "otherSpecPlus" then
		if not ShouldHideOtherIcon(bag) then
			SetIconPositionAndSize(mogStatus, iconPosition, 15, otherIconSize, otherIconOffset)
			mogStatus:SetTexture("Interface\\COMMON\\icon-noloot")
			if status == "otherSpecPlus" then
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

	local bindingPosition = options.overrideBindingPosition or CaerdonWardrobeConfig.Binding.Position
	local bindingOffset = options.bindingOffset or 2

	if bindingPosition == "BOTTOM" then
		bindsOnText:SetPoint("BOTTOMRIGHT", bindingOffset, 2)
		if bindingStatus == L["BoA"] then
			local offset = options.itemCountOffset or 15
			if (button.count and button.count > 1) then
				bindsOnText:SetPoint("BOTTOMRIGHT", 0, offset)
			end
		end
	elseif bindingPosition == "CENTER" then
		bindsOnText:SetPoint("CENTER", 0, 0)
	elseif bindingPosition == "TOP" then
		bindsOnText:SetPoint("TOPRIGHT", 0, -2)
	else
		bindsOnText:SetPoint(bindingPosition, options.bindingOffsetX or 2, options.bindingOffsetY or 2)
	end
	if(options.bindingScale) then
		bindsOnText:SetScale(options.bindingScale)
	end

	local bindingText
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
			else
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
			else
				bindingText = "|cFF00FF00" .. bindingStatus .. "|r"
			end
		end
	end

	bindsOnText:SetText(bindingText)
end

local function QueueProcessItem(itemLink, bag, slot, button, options)
	C_Timer.After(0.1, function()
		CaerdonWardrobe:UpdateButtonLink(itemLink, bag, slot, button, options)
	end)
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
	local bindingStatus, needsItem, hasUse, isDressable, isInEquipmentSet, isBindOnPickup, isCompletionistItem, shouldRetry, unusableItem, matchesLootSpec, isLocked = GetBindingStatus(bag, slot, itemID, itemLink)
	print ('Binding Status: ' .. tostring(bindingStatus) .. ', Needs Item: ' .. tostring(needsItem) .. ', HasUse: ' .. tostring(hasUse) .. ', Is Dressable: ' .. tostring(isDressable) .. ', Is In Equipment Set: ' .. tostring(isInEquipmentSet) .. ', Is BoP: ' .. tostring(isBindOnPickup) .. ', Is Completionist: ' .. tostring(isCompletionistItem) .. ', Should Retry: ' .. tostring(shouldRetry) .. ', Unusable: ' .. tostring(unusableItem) .. ', Matches Loot Spec: ' .. tostring(matchesLootSpec) .. ', Is Locked: ' .. tostring(isLocked))

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

local function ProcessItem(item, bag, slot, button, options)
	local bindingText
	local mogStatus = nil

   	if not options then
   		options = {}
   	end

	local showMogIcon = options.showMogIcon
	local showBindStatus = options.showBindStatus
	local showSellables = options.showSellables

	local itemID = item:GetItemID()
	local itemLink = item:GetItemLink()
	if not itemLink or not itemID then
		return
	end

	local canBeChanged, noChangeReason, canBeSource, noSourceReason = C_Transmog.GetItemInfo(itemLink)

	local isDebugItem = itemID and itemID == DEBUG_ITEM
  	if isDebugItem then
		local printable = gsub(itemLink, "\124", "\124\124");
		print(printable)
		-- DebugItem(itemID, itemLink, bag, slot)
   	end

	local appearanceID, isCollected, sourceID

	local bindingStatus, needsItem, hasUse, isDressable, isInEquipmentSet, isBindOnPickup, isCompletionistItem, shouldRetry, unusableItem, matchesLootSpec, isLocked = GetBindingStatus(bag, slot, itemID, itemLink)
	if shouldRetry then
		if isDebugItem then print("Retrying item: " .. itemLink) end
		QueueProcessItem(itemLink, bag, slot, button, options)
		return
	end

	local itemName, itemLinkInfo, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
	itemEquipLoc, iconFileDataID, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID, 
	isCraftingReagent = GetItemInfo(itemLink)

   	if IsCollectibleLink(itemLink) then
   		shouldRetry = false
	else
		local expansionID = expacID
		if expansionID and expansionID >= 0 and expansionID < GetExpansionLevel() then 
			if not hasUse then
				-- TODO: May want to separate reagents from everything else?
				-- mogStatus = "oldexpansion"
			end
		end
		
		appearanceID, isCollected, sourceID, shouldRetry = GetItemAppearance(itemID, itemLink)
		if shouldRetry then
			QueueProcessItem(itemLink, bag, slot, button, options)
			return
		end
	end

	if appearanceID then
		if isDebugItem then print("=== Has appearance ID") end
		local canCollect, matchedSource, shouldRetry = PlayerCanCollectAppearance(sourceID, appearanceID, itemID, itemLink)
		if shouldRetry then
			QueueProcessItem(itemLink, bag, slot, button, options)
			return
		end

		if isDebugItem then print("Needs Item: " .. tostring(needsItem)) end
		if isDebugItem then print("Is Collected: " .. tostring(isCollected)) end
		if isDebugItem then print("Player Has Appearance: " .. tostring(PlayerHasAppearance(appearanceID))) end

		if(needsItem and not isCollected and not PlayerHasAppearance(appearanceID)) then
			if isDebugItem then print("=== Has appearance, Processing needsItem") end
			if canCollect and not unusableItem then
				mogStatus = "own"
			else
				if bindingStatus then
					mogStatus = "other"
				elseif (bag == "EncounterJournal" or bag == "QuestButton") then
					mogStatus = "other"
				elseif (bag == "LootFrame" or bag == "GroupLootFrame") and not isBindOnPickup then
					mogStatus = "other"
				elseif unusableItem then
					mogStatus = "collected"
				end
			end

			if not matchesLootSpec and bag == "EncounterJournal" then
				mogStatus = "otherSpec"
			end
		else
			if isDebugItem then print("Is Completionist Item: " .. tostring(isCompletionistItem)) end

			if isCompletionistItem then
				if isDebugItem then print("=== Processing completionist item") end
				-- You have this, but you want them all.  Why?  Because.

				-- local playerLevel = UnitLevel("player")

				if canCollect then
					mogStatus = "ownPlus"
				else
					mogStatus = "otherPlus"
				end

				if not matchesLootSpec and bag == "EncounterJournal" then
					if isDebugItem then print("=== Doesn't match loot spec - flagging other") end
					mogStatus = "otherSpecPlus"
				end

				if unusableItem then
					if isDebugItem then print("=== Marked unusable for toon - flagging other") end
					mogStatus = "otherPlus"
				end

			-- If an item isn't flagged as a source or has a usable effect,
			-- then don't mark it as sellable right now to avoid accidents.
			-- May need to expand this to account for other items, too, for now.
			elseif canBeSource and not isInEquipmentSet then
				if isDressable and not shouldRetry then -- don't flag items for sale that have use effects for now
					if isDebugItem then print("canBeSource and isDressable processed for " ..itemLink) end
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
		if isDebugItem then print("=== No appearance, Processing needsItem") end

		if ((canBeSource and isDressable) or IsMountLink(itemLink)) and not shouldRetry then
			local playerLevel = UnitLevel("player")

			if not itemMinLevel or playerLevel >= itemMinLevel then
				mogStatus = "own"
			else
				mogStatus = "other"
			end
		elseif IsPetLink(itemLink) or IsToyLink(itemLink) or IsRecipeLink(itemLink) then
			if unusableItem then
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
				mogStatus = nil -- TODO: Maybe oldexpansion?
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

	    if(IsBankOrBags(bag)) then	    	
	    	local containerID = bag
	    	local containerSlot = slot

			local texture, itemCount, locked, quality, readable, lootable, _ = GetContainerItemInfo(containerID, containerSlot);
			if lootable then
				local startTime, duration, isEnabled = GetContainerItemCooldown(containerID, containerSlot)
				if duration > 0 and not isEnabled then
					mogStatus = "refundable" -- Can't open yet... show timer
				else
					if isLocked then
						mogStatus = "locked"
					else
						mogStatus = "openable"
					end
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
		ItemIsSellable(itemID, itemLink) and not isInEquipmentSet then
       	-- Anything that reports as the player having should be safe to sell
       	-- unless it's in an equipment set or needs to be excluded for some
       	-- other reason
		options.isSellable = true
	end

	if button then
		SetItemButtonMogStatus(button, mogStatus, bindingStatus, options, bag, slot, itemID)
		SetItemButtonBindType(button, mogStatus, bindingStatus, options, bag, itemID)
	end
end

local function ProcessOrWaitItemLink(itemLink, bag, slot, button, options)
	CaerdonWardrobe:UpdateButtonLink(itemLink, bag, slot, button, options)
end

local registeredAddons = {}
local registeredBagAddons = {}
local bagAddonCount = 0

function CaerdonWardrobe:GetItemID(itemLink)
	return GetItemID(itemLink)
end

function CaerdonWardrobe:RegisterAddon(name, addonOptions)
	local options = {
		isBag = true	
	}

	if addonOptions then
		for key, value in pairs(addonOptions) do
			options[key] = value
		end
	end

	registeredAddons[name] = options

	if options.isBag then
		registeredBagAddons[name] = options
		bagAddonCount = bagAddonCount + 1
		if bagAddonCount > 1 then
			for key in pairs(registeredBagAddons) do
				if addonList then
					addonList = addonList .. ", " .. key
				else
					addonList = key
				end	
			end
			StaticPopup_Show("CAERDON_WARDROBE_MULTIPLE_BAG_ADDONS", addonList)
		end
		if not options.hookDefaultBags then
			ignoreDefaultBags = true
		end
	end
end

function CaerdonWardrobe:ClearButton(button)
	SetItemButtonMogStatus(button, nil)
	SetItemButtonBindType(button, nil)
end

function CaerdonWardrobe:UpdateButtonLink(itemLink, bag, slot, button, options)
	if not itemLink then
		CaerdonWardrobe:ClearButton(button)
		return
	end

	local item = Item:CreateFromItemLink(itemLink)
	SetItemButtonMogStatus(button, "waiting", nil, options, bag, slot, item:GetItemID())

	-- TODO: May have to look into cancelable continue to avoid timing issues
	-- Need to figure out how to key this correctly (could have multiple of item in bags, for instance)
	-- but in cases of rapid data update (AH scroll), we don't want to update an old button
	-- Look into ContinuableContainer
	if item:IsItemEmpty() then -- not sure what this represents?  Seems to happen for caged pet - assuming item is ready.
		SetItemButtonMogStatus(button, nil)
		ProcessItem(item, bag, slot, button, options)
	else
		item:ContinueOnItemLoad(function ()
			SetItemButtonMogStatus(button, nil)
			ProcessItem(item, bag, slot, button, options)
		end)
	end
end

local function OnContainerUpdate(self, asyncUpdate)
	local bagID = self:GetID()

	for buttonIndex = 1, self.size do
		local button = _G[self:GetName() .. "Item" .. buttonIndex]
		local slot = button:GetID()

		local itemLink = GetContainerItemLink(bagID, slot)
		CaerdonWardrobe:UpdateButtonLink(itemLink, bagID, slot, button, { showMogIcon = true, showBindStatus = true, showSellables = true })
	end
end

local waitingOnBagUpdate = {}
local function OnBagUpdate_Coroutine()
    local processQueue = {}
    for frameID, shouldUpdate in pairs(waitingOnBagUpdate) do
      processQueue[frameID] = shouldUpdate
      waitingOnBagUpdate[frameID] = nil
    end

    for frameID, shouldUpdate in pairs(processQueue) do
      local frame = _G["ContainerFrame".. frameID]

      if frame:IsShown() then
        OnContainerUpdate(frame, true)
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

local function OnBankItemUpdate(button)
	local bag = GetBankContainer(button)
	local slot = button:GetID()

	if bag and slot then
		local itemLink = GetContainerItemLink(bag, slot)
		CaerdonWardrobe:UpdateButtonLink(itemLink, bag, slot, button, { showMogIcon=true, showBindStatus=true, showSellables=true })
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
			CaerdonWardrobe:UpdateButtonLink(itemLink, bag, slot, button, options)
		end
	end
end

local function OnGuildBankFrameUpdate()
	isGuildBankFrameUpdateRequested = true
end

local auctionTimer
local auctionContinuableContainer = ContinuableContainer:Create();

local function OnAuctionBrowseUpdate()
	-- Event pump since first load won't have UI ready
	if not AuctionHouseFrame:IsVisible() then
		return
	end

	if auctionTimer then
		auctionTimer:Cancel()
	end

	-- TODO: Battle Pet scans are not clean, yet.
	auctionContinuableContainer:Cancel()

	local buttons = HybridScrollFrame_GetButtons(AuctionHouseFrame.BrowseResultsFrame.ItemList.ScrollFrame);
	for i, button in ipairs(buttons) do
		CaerdonWardrobe:ClearButton(button)
	end

	auctionTimer = C_Timer.NewTimer(0.1, function() 
		local browseResults = C_AuctionHouse.GetBrowseResults()
		local offset = AuctionHouseFrame.BrowseResultsFrame.ItemList:GetScrollOffset();

		local buttons = HybridScrollFrame_GetButtons(AuctionHouseFrame.BrowseResultsFrame.ItemList.ScrollFrame);
		for i, button in ipairs(buttons) do
			local bag = "AuctionFrame"
			local slot = i + offset

			local _, itemLink

			local browseResult = browseResults[slot]
			if browseResult then
				local item = Item:CreateFromItemID(browseResult.itemKey.itemID)
				-- TODO: Do we need to check if slot has changed for buttons?  Could do something here...
				-- item:ContinueOnItemLoad(function ()
				-- 	print(item:GetItemLink())
				-- end)
				auctionContinuableContainer:AddContinuable(item)
			end
		end

		auctionContinuableContainer:ContinueOnLoad(function()
			local checkOffset = AuctionHouseFrame.BrowseResultsFrame.ItemList:GetScrollOffset();
			-- TODO: Not sure if this is actually doing anything - hasn't been triggered, yet.
			if checkOffset ~= offset then 
				return
			end

			for i, button in ipairs(buttons) do
				local bag = "AuctionFrame"
				local slot = i + offset
	
				local _, itemLink
	
				local browseResult = browseResults[slot]
				if browseResult then
					local item = Item:CreateFromItemID(browseResult.itemKey.itemID)
					local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(browseResult.itemKey)
	
					if itemKeyInfo and itemKeyInfo.battlePetLink then
						itemLink = itemKeyInfo.battlePetLink
					else
						itemLink = item:GetItemLink()
					end
	
					if itemLink and button then
						CaerdonWardrobe:UpdateButtonLink(itemLink, bag, { index = slot, itemKey = browseResult.itemKey }, button,  
						{
							iconOffset = 10,
							iconSize = 30,				
							showMogIcon=true, 
							showBindStatus=false, 
							showSellables=false
						})
					end
				end
			end
		end)
	end, 1)
end

local function OnAuctionBrowseClick(self, buttonName, isDown)
	if (buttonName == "LeftButton" and isDown) then
		OnAuctionBrowseUpdate()
	end
end

local function OnMerchantUpdate()
	for i=1, MERCHANT_ITEMS_PER_PAGE, 1 do
		local index = (((MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE) + i)

		local button = _G["MerchantItem"..i.."ItemButton"];

		local bag = "MerchantFrame"
		local slot = index

		local itemLink = GetMerchantItemLink(index)
		CaerdonWardrobe:UpdateButtonLink(itemLink, bag, slot, button, { showMogIcon=true, showBindStatus=true, showSellables=false})
	end
end

local function OnBuybackUpdate()
	local numBuybackItems = GetNumBuybackItems();

	for index=1, BUYBACK_ITEMS_PER_PAGE, 1 do -- Only 1 actual page for buyback right now
		if index <= numBuybackItems then
			local button = _G["MerchantItem"..index.."ItemButton"];

			local bag = "MerchantFrame"
			local slot = index

			local itemLink = GetBuybackItemLink(index)
			CaerdonWardrobe:UpdateButtonLink(itemLink, bag, slot, button, { showMogIcon=true, showBindStatus=true, showSellables=false})
		end
	end
end

hooksecurefunc("MerchantFrame_UpdateMerchantInfo", OnMerchantUpdate)
hooksecurefunc("MerchantFrame_UpdateBuybackInfo", OnBuybackUpdate)

function CaerdonWardrobeMixin:OnEvent(event, ...)
	if DEBUG_ENABLED then
		local arg1, arg2 = ...
		-- print("Caerdon Wardrobe: " .. event .. ": " .. tostring(arg1) .. ", " .. tostring(arg2))
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

function CaerdonWardrobeMixin:OnUpdate(elapsed)
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

	if( timeSinceLastGuildBankUpdate ~= nil and (timeSinceLastGuildBankUpdate > GUILDBANKFRAMEUPDATE_INTERVAL) ) then
		timeSinceLastGuildBankUpdate = nil
		self.guildBankUpdateCoroutine = coroutine.create(OnGuildBankFrameUpdate_Coroutine)
	end

	if( timeSinceLastBagUpdate ~= nil and (timeSinceLastBagUpdate > BAGUPDATE_INTERVAL) ) then
		timeSinceLastBagUpdate = nil
		self.bagUpdateCoroutine = coroutine.create(OnBagUpdate_Coroutine)
	end
end

local function OnEncounterJournalSetLootButton(item)
	local itemID, encounterID, name, icon, slot, armorType, itemLink;
	if isShadowlands then
		local itemInfo = C_EncounterJournal.GetLootInfoByIndex(item.index);
		itemLink = itemInfo.link
	else
		itemID, encounterID, name, icon, slot, armorType, itemLink = EJ_GetLootInfoByIndex(item.index);
	end
	
	local options = {
		iconOffset = 7,
		otherIcon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
		otherIconSize = 20,
		otherIconOffset = 15,
		overridePosition = "TOPLEFT"
	}

	CaerdonWardrobe:UpdateButtonLink(itemLink, "EncounterJournal", item, item, options)
end

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

function CaerdonWardrobeMixin:PLAYER_LOGOUT()
end

function CaerdonWardrobeMixin:ADDON_LOADED(name)
	if name == ADDON_NAME then
		ProcessSettings()
		NS:FireConfigLoaded()
	elseif name == "Blizzard_GuildBankUI" then
		hooksecurefunc("GuildBankFrame_Update", OnGuildBankFrameUpdate)
	elseif name == "Blizzard_EncounterJournal" then
		hooksecurefunc("EncounterJournal_SetLootButton", OnEncounterJournalSetLootButton)
	-- elseif name == "TradeSkillMaster" then
	-- 	print("HOOKING TSM")
	-- 	hooksecurefunc (TSM.UI.AuctionScrollingTable, "_SetRowData", function (self, row, data)
	-- 		print("Row: " .. row:GetField("auctionId"))
	-- 	end)
	end
end

function CaerdonWardrobeMixin:PLAYER_LOGIN(...)
	if DEBUG_ENABLED then
		GameTooltip:HookScript("OnTooltipSetItem", addDebugInfo)
	end

	-- Show missing info in tooltips
	-- NOTE: This causes a bug with tooltip scanning, so we disable
	--   briefly and turn it back on with each scan.
	C_TransmogCollection.SetShowMissingSourceInItemTooltips(true)
	SetCVar("missingTransmogSourceInItemTooltips", 1)
end

function CaerdonWardrobeMixin:AUCTION_HOUSE_BROWSE_RESULTS_UPDATED()
	OnAuctionBrowseUpdate()
end

local hookAuction = true
function CaerdonWardrobeMixin:AUCTION_HOUSE_SHOW()
	if (hookAuction) then
		hookAuction = false
		AuctionHouseFrame.BrowseResultsFrame.ItemList.ScrollFrame.scrollBar:HookScript("OnValueChanged", OnAuctionBrowseUpdate)
	end
end

function RefreshMainBank()
	if not ignoreDefaultBags then
		for i=1, NUM_BANKGENERIC_SLOTS, 1 do
			button = BankSlotsFrame["Item"..i];
			OnBankItemUpdate(button);
		end
	end
end

local refreshTimer
local function RefreshItems()
	if refreshTimer then
		refreshTimer:Cancel()
	end

	refreshTimer = C_Timer.NewTimer(0.1, function ()
		if DEBUG_ENABLED then
			print("=== Refreshing Transmog Items")
		end

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
	C_Timer.After(1, function() RefreshItems() end)
end

hooksecurefunc("EquipPendingItem", OnEquipPendingItem)

local function OnOpenBag(bagID)
	if not ignoreDefaultBags then
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
	if not ignoreDefaultBags then
		isBagUpdateRequested = true
	end
end

hooksecurefunc("OpenBag", OnOpenBag)
hooksecurefunc("OpenBackpack", OnOpenBackpack)
hooksecurefunc("ToggleBag", OnOpenBag)

function CaerdonWardrobeMixin:BAG_UPDATE(bagID)
	AddBagUpdateRequest(bagID)
end

function CaerdonWardrobeMixin:BAG_UPDATE_DELAYED()
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

function CaerdonWardrobeMixin:PLAYER_LOOT_SPEC_UPDATED()
	if EncounterJournal then
		EncounterJournal_LootUpdate()
	end
end

function CaerdonWardrobeMixin:TRANSMOG_COLLECTION_ITEM_UPDATE()
	-- RefreshItems()
end

function CaerdonWardrobeMixin:UNIT_SPELLCAST_SUCCEEDED(unitTarget, castGUID, spellID)
	if unitTarget == "player" then
		-- Tracking unlock spells to know to refresh
		-- May have to add some other abilities but this is a good place to start.
		if spellID == 1804 then
			RefreshItems(true)
		end
	end
end

function CaerdonWardrobeMixin:TRANSMOG_COLLECTION_UPDATED()
	RefreshItems()
end

function CaerdonWardrobeMixin:MERCHANT_UPDATE()
	RefreshItems()
end

function CaerdonWardrobeMixin:EQUIPMENT_SETS_CHANGED()
	RefreshItems()
end

function CaerdonWardrobeMixin:UPDATE_EXPANSION_LEVEL()
	-- Can change while logged in!
	RefreshItems()
end

function CaerdonWardrobeMixin:BANKFRAME_OPENED()
	-- RefreshMainBank()
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

-- BAG_OPEN
-- GUILDBANKBAGSLOTS_CHANGED
-- GUILDBANKFRAME_OPENED
