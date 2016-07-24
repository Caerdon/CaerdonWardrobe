local ADDON_NAME, namespace = ...
local L = namespace.L
local eventFrame

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
    ['INVTYPE_TABARD'] = INVSLOT_TABARD,
}

local scanTip = CreateFrame( "GameTooltip", "CaerdonWardrobeGameTooltip", nil, "GameTooltipTemplate" )
local cachedBinding = {}

local model = CreateFrame('DressUpModel')

local function GetItemID(itemLink)
	return itemLink:match("item:(%d+)")
end

local function CanTransmogItem(itemLink)
	local itemID = GetItemID(itemLink)
	local canBeChanged, noChangeReason, canBeSource, noSourceReason = C_Transmog.GetItemInfo(itemID)
	return canBeSource, noSourceReason
end

local function GetItemSource(itemID)
	local itemLink = 'item:' .. itemID
    local _, _, _, slotName = GetItemInfoInstant(itemID)

    local slot = InventorySlots[slotName]
    if not slot or not IsDressableItem(itemLink) then
    	return 
    end

    model:SetUnit('player')
    model:Undress()
    model:TryOn(itemLink, slot)
    return model:GetSlotTransmogSources(slot)
end

local function GetItemAppearance(itemID)
	local categoryID, appearanceID, canEnchant, texture, isCollected, sourceItemLink
	local sourceID = GetItemSource(itemID)
    if sourceID and sourceID ~= NO_TRANSMOG_SOURCE_ID then
        categoryID, appearanceID, canEnchant, texture, isCollected, sourceItemLink = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
    end

    return appearanceID, isCollected, sourceID
end

local function PlayerNeedsTransmogMissingAppearance(itemLink)
	-- Tabards (at the least) don't return in an appearance lookup, but this seems to work
	local needsItem = false
    local itemID, _, _, slotName = GetItemInfoInstant(itemLink)

    local slot = InventorySlots[slotName]
    if slot and IsDressableItem(itemLink) then

		local canBeSource, noSourceReason = CanTransmogItem(itemLink)
		if canBeSource then
			needsItem = not C_TransmogCollection.PlayerHasTransmog(itemID)
			if needsItem then

				scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
				scanTip:SetItemByID(GetItemID(itemLink))

				for lineIndex = 1, scanTip:NumLines() do
					local lineText = _G["CaerdonWardrobeGameTooltipTextLeft" .. lineIndex]:GetText()
					if lineText then
						if strmatch(lineText, USE_COLON) then -- it's a recipe
							break
						end
					end

					if lineText == TRANSMOGRIFY_TOOLTIP_ITEM_UNKNOWN_APPEARANCE_KNOWN then
						needsItem = false
					end
				end
			end
		end
	end

	return needsItem
end

local function PlayerHasAppearance(appearanceID, itemLink)
	local hasAppearance = false
	local itemID = GetItemID(itemLink)

    local sources = C_TransmogCollection.GetAppearanceSources(appearanceID)
    if sources then
        for i, source in pairs(sources) do
            if source.isCollected then
                hasAppearance = true
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

    return hasAppearance
end
 
local function PlayerCanCollectAppearance(appearanceID)
    local sources = C_TransmogCollection.GetAppearanceSources(appearanceID)
    if sources then
        for i, source in pairs(sources) do
            if C_TransmogCollection.PlayerCanCollectSource(source.sourceID) then
                return true
            end
        end
    end

    return false
end

local function IsSourceArtifact(sourceID)
	local link = select(6, C_TransmogCollection.GetAppearanceSourceInfo(sourceID));
	local _, _, quality = GetItemInfo(link);
	return quality == LE_ITEM_QUALITY_ARTIFACT;
end

local function GetBindingStatus(bag, slot, itemLink)
	local itemKey
	-- TODO: Clean this up
	if bag == "GuildBankFrame" then
		itemKey = bag .. slot.tab .. slot.index .. itemLink
	else
		itemKey = bag .. slot .. itemLink
	end
	local bindingText = nil --cachedBinding[itemKey]

	if not bindingText then
		scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
		scanTip:SetItemByID(GetItemID(itemLink))

		for lineIndex = 1, 5 do
			local lineText = _G["CaerdonWardrobeGameTooltipTextLeft" .. lineIndex]:GetText()
			if lineText then
				if strmatch(lineText, USE_COLON) then -- it's a recipe
					break
				end

				bindingText = bindTextTable[lineText]
				if bindingText then
					cachedBinding[itemKey] = bindingText
					break
				end
			end
		end
	end

	return bindingText
end

local function addDebugInfo(tooltip, itemLink)
	local itemID = GetItemID(itemLink)
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

	local appearanceID, isCollected, sourceID = GetItemAppearance(itemID)

	tooltip:AddDoubleLine("Appearance ID:", tostring(appearanceID))
	tooltip:AddDoubleLine("Is Collected:", tostring(isCollected))
	tooltip:AddDoubleLine("Item Source:", sourceID and tostring(sourceID) or "none")

	if appearanceID then
		local hasAppearance = PlayerHasAppearance(appearanceID, itemLink)
		tooltip:AddDoubleLine("PlayerHasAppearance:", tostring(hasAppearance))
		tooltip:AddDoubleLine("PlayerCanCollectAppearance:", tostring(PlayerCanCollectAppearance(appearanceID)))
	end

	tooltip:AddDoubleLine("CanTransmogItem:", tostring(CanTransmogItem(itemLink)))
	tooltip:AddDoubleLine("PlayerNeedsTransmogMissingAppearance:", tostring(PlayerNeedsTransmogMissingAppearance(itemLink)))

	tooltip:Show()
end

local waitingOnItemData = {}

local function ProcessItem(itemID, bag, slot, position, topText, bottomText, button)
	local ownIconString = "|TInterface\\Store\\category-icon-featured:" .. position .. "|t"
	local otherIconString = "|TInterface\\Store\\category-icon-placeholder:" .. position .. "|t"

	local name, itemLink, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture, vendorPrice = GetItemInfo(itemID)

	local appearanceID, isCollected, sourceID = GetItemAppearance(itemID)
	if(appearanceID and not IsSourceArtifact(sourceID)) then
		local bindingStatus = GetBindingStatus(bag, slot, itemLink)

		if(not isCollected and not PlayerHasAppearance(appearanceID, itemLink)) then -- and PlayerNeedsTransmogMissingAppearance(itemLink)) then
			if PlayerCanCollectAppearance(appearanceID) then
				topText:SetText(ownIconString)
				topText:Show()

				if bindingStatus and bottomText then
					bottomText:SetText(bindingStatus)
					bottomText:Show()
				end
			else
				if bindingStatus then
					if PlayerNeedsTransmogMissingAppearance(itemLink) then
						-- Can't equip on current toon but still need to learn
						topText:SetText(otherIconString)
						topText:Show()
					end

					if bottomText then 
						bottomText:SetText("|cFFFF0000" .. bindingStatus .. "|r")
						bottomText:Show()
					end
				end
			end
		else
			-- TODO: Decide how to expose this functionality
			-- Hide anything that doesn't match
			-- if button then
			-- 	--button.IconBorder:SetVertexColor(100, 255, 50)
			-- 	button.searchOverlay:Show()
			-- end

			topText:Hide()

			if bottomText then
				if bindingStatus then
					bottomText:SetText("|cFF00FF00" .. bindingStatus .. "|r")
					bottomText:Show()
				else
					bottomText:Hide()
				end
			end
		end
	elseif PlayerNeedsTransmogMissingAppearance(itemLink) then
	 	topText:SetText(ownIconString)
	 	topText:Show()
	else
		-- Hide anything that doesn't match
		-- if button then
		-- 	--button.IconBorder:SetVertexColor(100, 255, 50)
		-- 	button.searchOverlay:Show()
		-- end

	 	if topText:GetText() == otherIconString or topText:GetText() == ownIconString then
	 		topText:Hide()
	 	end
	end
end

local function OnContainerUpdate(self)
	local bag = self:GetID()

	for buttonIndex = 1, self.size do
		local button = _G[self:GetName() .. "Item" .. buttonIndex]
		local slot = button:GetID()
		local scale = self:GetEffectiveScale()

		local topText = _G[button:GetName().."Stock"]
		local bottomText = _G[button:GetName().."Count"]

		local size = 40
		local xoffset = -15 * scale
		local yoffset = 17 * scale

		local position = size .. ":" .. size .. ":" .. xoffset .. ":" .. yoffset

		local itemID = GetContainerItemID(bag, slot)
		if itemID then
			local itemName = GetItemInfo(itemID)
			if itemName == nil then
				waitingOnItemData[itemID] = {bag = bag, slot = slot, position = position, topText = topText, bottomText = bottomText, button = button}
			else
				ProcessItem(itemID, bag, slot, position, topText, bottomText, button)
			end
		else
			topText:Hide()
			bottomText:Hide()
		end
	end
end

hooksecurefunc("ContainerFrame_Update", OnContainerUpdate)

local function OnBankItemUpdate(button)
	local bag = button:GetParent():GetID();
	if( button.isBag ) then
		bag = -ITEM_INVENTORY_BANK_BAG_OFFSET;
		return
	end

	local slot = button:GetID()

	local scale = button:GetEffectiveScale()

	local topText = _G[button:GetName().."Stock"]
	local bottomText = button.Count or _G[button:GetName().."Count"];

	local size = 40
	local xoffset = -15 * scale
	local yoffset = 17 * scale

	local position = size .. ":" .. size .. ":" .. xoffset .. ":" .. yoffset

	local inventoryID = button:GetInventorySlot();

	local itemID = GetContainerItemID(bag, slot)
	if itemID then
		local itemName = GetItemInfo(itemID)
		if itemName == nil then
			waitingOnItemData[itemID] = {bag = "BankFrame", slot = inventoryID, position = position, topText = topText, bottomText = bottomText}
		else
			ProcessItem(itemID, "BankFrame", inventoryID, position, topText, bottomText)
		end
	else
		topText:Hide()
		bottomText:Hide()
	end
end

hooksecurefunc("BankFrameItemButton_Update", OnBankItemUpdate)

local isGuildBankFrameUpdateRequested = false

local function OnGuildBankFrameUpdate_Coroutine()
	if( GuildBankFrame.mode == "bank" ) then
		local tab = GetCurrentGuildBankTab();
		-- if( tab <= GetNumGuildBankTabs() ) then
		-- end

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

			local scale = button:GetEffectiveScale()

			local topText = _G[button:GetName().."Stock"]
			local bottomText = button.Count or _G[button:GetName().."Count"];

			local size = 40
			local xoffset = -15 * scale
			local yoffset = 17 * scale

			local position = size .. ":" .. size .. ":" .. xoffset .. ":" .. yoffset

			local itemLink = GetGuildBankItemLink(tab, i)
			if itemLink then
				local itemID = itemLink:match("item:(%d+)")
				if itemID then
					local itemName = GetItemInfo(itemID)
					if itemName == nil then
						waitingOnItemData[itemID] = {bag = "GuildBankFrame", slot = {tab = tab, index = i}, position = position, topText = topText, bottomText = bottomText, button = button}
					else
						ProcessItem(itemID, "GuildBankFrame", {tab = tab, index = i}, position, topText, bottomText, button)
					end
				else
					topText:Hide()
					bottomText:Hide()
				end
			else
				topText:Hide()
				bottomText:Hide()
			end
		end
	end
end

local function OnGuildBankFrameUpdate()
	isGuildBankFrameUpdateRequested = true
end

local function OnAuctionBrowseUpdate()
	local scale = AuctionFrameBrowse:GetEffectiveScale()
	local size = 30
	local xoffset = 1 * scale
	local yoffset = 6 * scale

	local position = size .. ":" .. size .. ":" .. xoffset .. ":" .. yoffset

	local offset = FauxScrollFrame_GetOffset(BrowseScrollFrame);

	for i=1, NUM_BROWSE_TO_DISPLAY do
		local auctionIndex = offset + i
		local index = auctionIndex + (NUM_AUCTION_ITEMS_PER_PAGE * AuctionFrameBrowse.page);
		local button = _G["BrowseButton"..i];
		local name, texture, count, quality, canUse, level, levelColHeader, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemID, hasAllInfo =  GetAuctionItemInfo("list", auctionIndex);
		local buttonName = "BrowseButton"..i;
		local itemCount = _G[buttonName.."ItemCount"];

		local itemLink = GetAuctionItemLink("list", auctionIndex)
		if(itemLink) then
			local itemID = itemLink:match("item:(%d+)")
			if itemID then
				local itemName = GetItemInfo(itemID)
				if itemName == nil then
					waitingOnItemData[itemID] = {bag = "AuctionFrame", slot = auctionIndex, position = position, topText = itemCount, bottomText = nil, button = button}
				else
					ProcessItem(itemID, "AuctionFrame", auctionIndex, position, itemCount, nil, button)
				end
			end
		end
	end
end

local function OnMerchantUpdate()
	local scale = MerchantFrame:GetEffectiveScale()
	local size = 40
	local xoffset = -10 * scale
	local yoffset = 10 * scale

	local position = size .. ":" .. size .. ":" .. xoffset .. ":" .. yoffset

	for i=1, MERCHANT_ITEMS_PER_PAGE, 1 do
		local index = (((MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE) + i)
		local itemCount = _G["MerchantItem"..i.."ItemButtonCount"]

		local itemID = GetMerchantItemID(index)
		if itemID then
			local itemName = GetItemInfo(itemID)
			if itemName == nil then
				waitingOnItemData[itemID] = {bag = "MerchantFrame", slot = index, position = position, topText = itemCount, bottomText = nil}
			else
				ProcessItem(itemID, "MerchantFrame", index, position, itemCount, nil)
			end
		else
			itemCount:Hide()
		end
	end
end

hooksecurefunc("MerchantFrame_UpdateMerchantInfo", OnMerchantUpdate)

local function OnEvent(self, event, ...)
	local handler = self[event]
	if(handler) then
		handler(self, ...)
	-- else
	-- 	print(event .. " UNKNOWN")
	end
end

local timeSinceLastGuildBankUpdate = nil
local GUILDBANKFRAMEUPDATE_INTERVAL = 0.1

local function OnUpdate(self, elapsed)
	if(self.guildBankUpdateCoroutine) then
		if coroutine.status(self.guildBankUpdateCoroutine) ~= "dead" then
			coroutine.resume(self.guildBankUpdateCoroutine)
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

	if( timeSinceLastGuildBankUpdate ~= nil and (timeSinceLastGuildBankUpdate > GUILDBANKFRAMEUPDATE_INTERVAL) ) then
		timeSinceLastGuildBankUpdate = nil
		self.guildBankUpdateCoroutine = coroutine.create(OnGuildBankFrameUpdate_Coroutine)
	end
end

local function addDebugInfo(self)
	local link = select(2, self:GetItem())
	if link then
		addDebugInfo(self, link)
	end
end

eventFrame = CreateFrame("FRAME", "CaerdonWardrobeFrame")
eventFrame:RegisterEvent "ADDON_LOADED"
eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:SetScript("OnUpdate", OnUpdate)
--GameTooltip:HookScript("OnTooltipSetItem", attachDebugInfo)

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
	eventFrame:RegisterEvent "BAG_UPDATE_DELAYED"
	eventFrame:RegisterEvent "GET_ITEM_INFO_RECEIVED"
	eventFrame:RegisterEvent "TRANSMOG_COLLECTION_UPDATED"
	-- eventFrame:RegisterAllEvents()
	C_TransmogCollection.SetShowMissingSourceInItemTooltips(true)
end

local function RefreshItems()
	cachedBinding = {}

	if MerchantFrame:IsShown() then
		OnMerchantUpdate()
	end

	if AuctionFrame and AuctionFrame:IsShown() then
		OnAuctionBrowseUpdate()
	end

	ContainerFrame_UpdateAll()
end

function eventFrame:BAG_UPDATE_DELAYED()
	-- RefreshItems()
end

function eventFrame:GET_ITEM_INFO_RECEIVED(itemID)
	local itemInfo = waitingOnItemData[itemID]
	if itemInfo then
		local itemName, _, itemQuality, _, _, _, _, _, _, texture = GetItemInfo(itemID)
		if itemName then
			waitingOnItemData[itemID] = nil
			ProcessItem(itemID, itemInfo.bag, itemInfo.slot, itemInfo.position, itemInfo.topText, itemInfo.bottomText, itemInfo.button)
		end
	end
end

function eventFrame:TRANSMOG_COLLECTION_UPDATED()
	RefreshItems()
end
