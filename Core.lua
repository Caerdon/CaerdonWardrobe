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

local function CanTransmogItem(itemLink)
	local canBeChanged = false
	local noChangeReason = nil
	local canBeSource = false
	local noSourceReason = nil

	local itemID = GetItemID(itemLink)
	if itemID then
		canBeChanged, noChangeReason, canBeSource, noSourceReason = C_Transmog.GetItemInfo(itemID)
	end
	return canBeSource, noSourceReason
end

local function GetItemSource(itemLink)
    local _, _, _, slotName = GetItemInfoInstant(itemLink)

    local slot = InventorySlots[slotName]
    if not slot or not IsDressableItem(itemLink) then
    	return 
    end

    model:SetUnit('player')
    model:Undress()
    model:TryOn(itemLink, slot)
    return model:GetSlotTransmogSources(slot)
end

local function GetItemAppearance(itemLink)
	local categoryID, appearanceID, canEnchant, texture, isCollected, sourceItemLink
	local sourceID = GetItemSource(itemLink)
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

    return appearanceID, isCollected, sourceID
end

local function PlayerHasAppearance(appearanceID, itemLink)
	local hasAppearance = false
	local itemID = GetItemID(itemLink)

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

    if not hasAppearance then
    	-- TODO: Do I need to worry about affixes?
		-- local itemString = string.match(itemLink, "item[%-?%d:]+") or ""
		-- local instaid, _, numBonuses, affixes = select(12, strsplit(":", itemString, 15))
		-- instaid=tonumber(instaid) or 7
		-- numBonuses=tonumber(numBonuses) or 0
		-- local upgradeID = nil
		-- if instaid >0 and (instaid-4)%8==0 then
		-- 	upgradeID = tonumber((select(numBonuses + 1, strsplit(":", affixes))))
		-- 	print("Upgrade ID: " .. upgradeID)
		-- end
    end

    return hasAppearance, matchedSource
end
 
local function PlayerCanCollectAppearance(appearanceID, itemLink)
	local itemID = GetItemID(itemLink)
	local name, _, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture, vendorPrice = GetItemInfo(itemID)
	local playerLevel = UnitLevel("player")
	local canCollect = false
	local matchedSource

	if playerLevel >= reqLevel then
	    local sources = C_TransmogCollection.GetAppearanceSources(appearanceID)
	    if sources then
	        for i, source in pairs(sources) do
	            if C_TransmogCollection.PlayerCanCollectSource(source.sourceID) then
	            	matchedSource = source
	                canCollect = true
	                break
	            end
	        end
	    end
	end

    return canCollect, matchedSource
end

local function GetItemLink(bag, slot)
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

local equipLocations = {}

local function GetBindingStatus(bag, slot, itemLink)
	local itemKey =  itemLink

	local binding = cachedBinding[itemKey]
	local bindingText, needsItem, hasUse

	if binding then
		bindingText = binding.bindingText
		needsItem = binding.needsItem
		hasUse = binding.hasUse
	end

	if needsItem == nil then
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

	    local itemID, _, _, slotName = GetItemInfoInstant(itemLink)

	    local isDressable = IsDressableItem(itemLink)
	    local inventorySlot = InventorySlots[slotName]
	    if not inventorySlot or not isDressable then
	    	needsItem = false
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
					    elseif isBank and not isBags then -- player or bank
					    	if bag == "BankFrame" and slot == equipSlot then
					    		needsItem = false
								if bindingText then
									bindingText = "*" .. bindingText
									isBindingTextDone = true
									break
								else
									bindingText = name
								end
					    	end
							-- inventoryItemID = GetInventoryItemID("player", slot)
							-- name, _, _, _, _, _, _, _, invType, textureName = GetItemInfo(id);
					    else
						    if equipSlot == slot and equipBag == bag then
								needsItem = false
								if bindingText then
									bindingText = "*" .. bindingText
									isBindingTextDone = true
									break
								else
									bindingText = name
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

		local canBeChanged, noChangeReason, canBeSource, noSourceReason, arg1, arg2 = C_Transmog.GetItemInfo(itemID)
		if canBeSource then
	        local hasTransmog = C_TransmogCollection.PlayerHasTransmog(itemID)
	        if hasTransmog then
	        	needsItem = false
	        end
	    else
	    	needsItem = false
	    end

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

		cachedBinding[itemKey] = {bindingText = bindingText, needsItem = needsItem, hasUse = hasUse}
	end

	return bindingText, needsItem, hasUse
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

		local appearanceID, isCollected, sourceID = GetItemAppearance(itemLink)

		tooltip:AddDoubleLine("Appearance ID:", tostring(appearanceID))
		tooltip:AddDoubleLine("Is Collected:", tostring(isCollected))
		tooltip:AddDoubleLine("Item Source:", sourceID and tostring(sourceID) or "none")

		if appearanceID then
			local hasAppearance, matchedSource = PlayerHasAppearance(appearanceID, itemLink)
			tooltip:AddDoubleLine("PlayerHasAppearance:", tostring(hasAppearance))
			tooltip:AddDoubleLine("Has Matched Source:", matchedSource and matchedSource.name or "none")
			local canCollect, matchedSource = PlayerCanCollectAppearance(appearanceID, itemLink)
			tooltip:AddDoubleLine("PlayerCanCollectAppearance:", tostring(canCollect))
			tooltip:AddDoubleLine("Collect Matched Source:", matchedSource and matchedSource.name or "none")
		end

		tooltip:AddDoubleLine("CanTransmogItem:", tostring(CanTransmogItem(itemLink)))

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

local function SetItemButtonMogStatus(button, status, bindingStatus, options)
	local mogStatus = button.mogStatus
	local iconPosition, showSellables
	if options then 
		showSellables = options.showSellables
		iconPosition = options.iconPosition
	end
	if not status and not mogStatus then return end
	if not status then
		mogStatus:SetTexture("")
		return
	end

	if not mogStatus then
		-- see ItemButtonTemplate.Count @ ItemButtonTemplate.xml#13
		mogStatus = button:CreateTexture(nil, "OVERLAY", nil, 2)
		SetIconPositionAndSize(mogStatus, iconPosition, 15, 40)
		button.mogStatus = mogStatus
	end

	local mogFlash = button.mogFlash
	if not mogFlash then
		mogFlash = button:CreateTexture(nil, "OVERLAY")
		mogFlash:SetAlpha(0)
		mogFlash:SetBlendMode("ADD")
		mogFlash:SetAtlas("bags-glow-flash", true)
		mogFlash:SetPoint("CENTER")

		button.mogFlash = mogFlash
	end

	local mogAnim = button.mogAnim
	if not mogAnim then
		mogAnim = button:CreateAnimationGroup()
		mogAnim:SetToFinalAlpha(true)
		mogAnim.alpha1 = mogAnim:CreateAnimation("Alpha")
		mogAnim.alpha1:SetChildKey("mogFlash")
		mogAnim.alpha1:SetSmoothing("OUT");
		mogAnim.alpha1:SetDuration(0.6)
		mogAnim.alpha1:SetOrder(1)
		mogAnim.alpha1:SetFromAlpha(1);
		mogAnim.alpha1:SetToAlpha(0);

		button.mogAnim = mogAnim
	end

	local showAnim = true

	mogStatus:SetAlpha(1)

	if status == "own" then
		SetIconPositionAndSize(mogStatus, iconPosition, 15, 40)
		mogStatus:SetTexture("Interface\\Store\\category-icon-featured")
	elseif status == "other" then
		SetIconPositionAndSize(mogStatus, iconPosition, 15, 40)
		mogStatus:SetTexture("Interface\\Store\\category-icon-placeholder")
	elseif status == "collected" then
		showAnim = false
		if not IsGearSetStatus(bindingStatus) and showSellables then -- it's known and can be sold
			SetIconPositionAndSize(mogStatus, iconPosition, 10, 30)
			mogStatus:SetAlpha(0.9)
			mogStatus:SetTexture("Interface\\Store\\category-icon-bag")
		else
			mogStatus:SetTexture("")
		end
	end

	if MailFrame:IsShown() or (AuctionFrame and AuctionFrame:IsShown()) then
		showAnim = false
	end

	if showAnim then
		mogFlash:Show()
		mogAnim:Play()
	else
		mogFlash:Hide()
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

local function ProcessItem(itemID, bag, slot, button, options, itemProcessed)
	local bindingText
	local mogStatus = nil

	local showMogIcon = options and options.showMogIcon
	local showBindStatus = options and options.showBindStatus
	local showSellables = options and options.showSellables

	local name, itemLink, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture, vendorPrice = GetItemInfo(itemID)
	itemLink = GetItemLink(bag, slot)

	local bindingStatus, needsItem, hasUse = GetBindingStatus(bag, slot, itemLink)

	local appearanceID, isCollected, sourceID = GetItemAppearance(itemLink)
	if appearanceID then
		if(needsItem and not isCollected and not PlayerHasAppearance(appearanceID, itemLink)) then

			if PlayerCanCollectAppearance(appearanceID, itemLink) then
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
			local canBeChanged, noChangeReason, canBeSource, noSourceReason, arg1, arg2 = C_Transmog.GetItemInfo(itemID)
			if canBeSource then
				if not hasUse then -- don't flag items for sale that have use effects for now
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
		local canBeChanged, noChangeReason, canBeSource, noSourceReason, arg1, arg2 = C_Transmog.GetItemInfo(itemID)
		if canBeSource then
			mogStatus = "own"
		end
	else
		local canBeChanged, noChangeReason, canBeSource, noSourceReason, arg1, arg2 = C_Transmog.GetItemInfo(itemID)
		if canBeSource then
	        local hasTransmog = C_TransmogCollection.PlayerHasTransmog(itemID)
	        if hasTransmog and not hasUse then
	        	-- Tabards don't have an appearance ID and will end up here.
	        	-- Anything that reports as the player having should be safe to sell.
	        	mogStatus = "collected"
	        end
	    end

		-- Hide anything that doesn't match
		-- if button then
		-- 	--button.IconBorder:SetVertexColor(100, 255, 50)
		-- 	button.searchOverlay:Show()
		-- end
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

		local itemName = GetItemInfo(itemID)
		local itemLink = GetItemLink(bag, slot)
		if itemName == nil or itemLink == nil then
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
	-- if isBagUpdate and not asyncUpdate then
	-- 	return
	-- end

	if not self:IsShown() then
		return
	end

	local bagID = self:GetID()

	for buttonIndex = 1, self.size do
		local button = _G[self:GetName() .. "Item" .. buttonIndex]
		local slot = button:GetID()

		local itemID = GetContainerItemID(bagID, slot)
		local texture, itemCount, locked = GetContainerItemInfo(bagID, slot)

		ProcessOrWaitItem(itemID, bagID, slot, button, { showMogIcon = true, showBindStatus = true, showSellables = true })
	end
end

local waitingOnBagUpdate = {}
local function OnBagUpdate_Coroutine()
    for frameID, shouldUpdate in pairs(waitingOnBagUpdate) do
		local frame = _G["ContainerFrame".. frameID]
		OnContainerUpdate(frame, true)
		coroutine.yield()
    end

	waitingOnBagUpdate = {}
end

local function AddBagUpdateRequest(bagID)
	for i=1, NUM_CONTAINER_FRAMES, 1 do
		local frame = _G["ContainerFrame"..i];
		if ( frame:IsShown() and frame:GetID() == bagID ) then
			waitingOnBagUpdate[tostring(i)] = true
			isBagUpdateRequested = true
		end
	end
end

local function ScheduleContainerUpdate(frame)
	local bagID = frame:GetID()
	AddBagUpdateRequest(bagID)
end

hooksecurefunc("ContainerFrame_Update", ScheduleContainerUpdate)

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
	["BN_FRIEND_INFO_CHANGED"] = {},
	["CHAT_MSG_BN_WHISPER"] = {},
	["CHAT_MSG_BN_WHISPER_INFORM"] = {},
	["CHAT_MSG_CHANNEL"] = {},
	["CHAT_MSG_SYSTEM"] = {},
	["CHAT_MSG_TRADESKILLS"] = {},
	["COMBAT_LOG_EVENT_UNFILTERED"] = {},
	["COMPANION_UPDATE"] = {},
	["CURSOR_UPDATE"] = {},
	-- ["GET_ITEM_INFO_RECEIVED"] = {},
	["GUILDBANKBAGSLOTS_CHANGED"] = {},
	["GUILD_ROSTER_UPDATE"] = {},
	["ITEM_LOCK_CHANGED"] = {},
	["ITEM_LOCKED"] = {},
	["ITEM_UNLOCKED"] = {},
	["MODIFIER_STATE_CHANGED"] = {},
	["QUEST_LOG_UPDATE"] = {},
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

local function OnUpdate(self, elapsed)
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

eventFrame = CreateFrame("FRAME", "CaerdonWardrobeFrame")
eventFrame:RegisterEvent "ADDON_LOADED"
eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:SetScript("OnUpdate", OnUpdate)
if DEBUG_ENABLED then
	GameTooltip:HookScript("OnTooltipSetItem", addDebugInfo)
end

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
		eventFrame:RegisterEvent "BAG_UPDATE"
		eventFrame:RegisterEvent "BAG_UPDATE_DELAYED"
		eventFrame:RegisterEvent "GET_ITEM_INFO_RECEIVED"
		eventFrame:RegisterEvent "TRANSMOG_COLLECTION_UPDATED"
		eventFrame:RegisterEvent "TRANSMOG_COLLECTION_ITEM_UPDATE"
	end
	C_TransmogCollection.SetShowMissingSourceInItemTooltips(true)
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
		for i=1, NUM_BANKBAGSLOTS, 1 do
			local button = BankSlotsFrame["Bag"..i];
			OnBankItemUpdate(button);
		end
	end

	ContainerFrame_UpdateAll()
end

function eventFrame:BAG_UPDATE(bagID)
	-- isBagUpdate = true
	-- waitingOnBagUpdate[tostring(tonumber(bagID) + 1)] = true
end

function eventFrame:BAG_UPDATE_DELAYED()
	-- isBagUpdate = false
	-- isBagUpdateRequested = true
end

function eventFrame:GET_ITEM_INFO_RECEIVED(itemID)
	local itemData = waitingOnItemData[tostring(itemID)]
	if itemData then
        for bag, bagData in pairs(itemData) do
        	for slot, slotData in pairs(bagData) do
				ProcessOrWaitItem(itemID, bag, slotData.slot, slotData.button, slotData.options, slotData.itemProcessed)
        	end
        end
	end
end

function eventFrame:TRANSMOG_COLLECTION_ITEM_UPDATE()
	RefreshItems()
end

function eventFrame:TRANSMOG_COLLECTION_UPDATED()
	RefreshItems()
end
