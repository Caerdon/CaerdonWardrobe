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
    ['INVTYPE_HEAD'] = 1,
    ['INVTYPE_SHOULDER'] = 3,
    ['INVTYPE_BODY'] = 4,
    ['INVTYPE_CHEST'] = 5,
    ['INVTYPE_ROBE'] = 5,
    ['INVTYPE_WAIST'] = 6,
    ['INVTYPE_LEGS'] = 7,
    ['INVTYPE_FEET'] = 8,
    ['INVTYPE_WRIST'] = 9,
    ['INVTYPE_HAND'] = 10,
    ['INVTYPE_CLOAK'] = 15,
    ['INVTYPE_WEAPON'] = 16,
    ['INVTYPE_SHIELD'] = 17,
    ['INVTYPE_2HWEAPON'] = 16,
    ['INVTYPE_WEAPONMAINHAND'] = 16,
    ['INVTYPE_RANGED'] = 16,
    ['INVTYPE_RANGEDRIGHT'] = 16,
    ['INVTYPE_WEAPONOFFHAND'] = 17,
    ['INVTYPE_HOLDABLE'] = 17,
    ['INVTYPE_TABARD'] = 19,
}

local model = CreateFrame('DressUpModel')

local function CanTransmogItem(itemID)
	local canBeChanged, noChangeReason, canBeSource, noSourceReason = C_Transmog.GetItemInfo(itemID)
	return canBeSource, noSourceReason
end

local function GetItemAppearance(itemLink)
    local itemID, _, _, slotName = GetItemInfoInstant(itemLink)
    if itemLink == itemID then
        itemLink = 'item:' .. itemID
    end
    local slot = InventorySlots[slotName]
    if not slot or not IsDressableItem(itemLink) then return end

    model:SetUnit('player')
    model:Undress()
    model:TryOn(itemLink, slot)
    local sourceID = model:GetSlotTransmogSources(slot)
    if sourceID then
        local categoryID, appearanceID, canEnchant, texture, isCollected, sourceItemLink = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
        return appearanceID, isCollected, sourceID, canBeSource
    end
end

local function PlayerNeedsTransmogMissingAppearance(itemLink)
	-- Tabards (at the least) don't return in an appearance lookup, but this seems to work
	local needsItem = false
    local itemID, _, _, slotName = GetItemInfoInstant(itemLink)
    if itemLink == itemID then
        itemLink = 'item:' .. itemID
    end

    local slot = InventorySlots[slotName]
    if slot and IsDressableItem(itemLink) then

		local canBeSource, noSourceReason = CanTransmogItem(itemID)
		if canBeSource then
			needsItem = not C_TransmogCollection.PlayerHasTransmog(itemID)
		end
	end

	return needsItem
end

local function PlayerHasAppearance(appearanceID)
    local sources = C_TransmogCollection.GetAppearanceSources(appearanceID)
    if sources then
        for i, source in pairs(sources) do
            if source.isCollected then
                return true
            end
        end
    end
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
end

local function IsSourceArtifact(sourceID)
	local link = select(6, C_TransmogCollection.GetAppearanceSourceInfo(sourceID));
	local _, _, quality = GetItemInfo(link);
	return quality == LE_ITEM_QUALITY_ARTIFACT;
end

local scanTip = CreateFrame("GameTooltip", "CaerdonWardrobeGameTooltip")
for lineIndex = 1, 5 do
	scanTip[lineIndex] = scanTip:CreateFontString()
	scanTip:AddFontStrings(scanTip[lineIndex], scanTip:CreateFontString())
end

local cachedBinding = {}

local function GetBindingStatus(bag, slot, itemLink)
	local itemKey = bag .. slot .. itemLink
	local bindingText = cachedBinding[itemKey]

	if not bindingText then
		scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
		if bag == "AuctionFrame" then
			scanTip:SetAuctionItem("list", slot)
		elseif bag == "MerchantFrame" then
			scanTip:SetMerchantItem(slot)
		else
			scanTip:SetBagItem(bag, slot)
		end

		for lineIndex = 1, 5 do
			local lineText = scanTip[lineIndex]:GetText()
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

local waitingOnItemData = {}

local function ProcessItem(itemID, bag, slot, position, topText, bottomText)
	local itemLink = 'item:' .. itemID
	local bindingStatus = GetBindingStatus(bag, slot, itemLink)
	local ownIconString = "|TInterface\\Store\\category-icon-featured:" .. position .. "|t"
	local otherIconString = "|TInterface\\Store\\category-icon-placeholder:" .. position .. "|t"

	local appearanceID, isCollected, sourceID = GetItemAppearance(itemLink)
	if(appearanceID and not IsSourceArtifact(sourceID)) then
		if not PlayerHasAppearance(appearanceID) then
			if PlayerCanCollectAppearance(appearanceID) then
				topText:SetText(ownIconString)
				topText:Show()

				if bindingStatus and bottomText then
					bottomText:SetText(bindingStatus)
					bottomText:Show()
				end
			else
				if bindingStatus then
					if CanTransmogItem(itemID) then
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
			topText:SetText("")
			topText:Show()

			if bottomText then
				bottomText:SetText("")
				bottomText:Show()
			end
		end
	elseif PlayerNeedsTransmogMissingAppearance(itemLink) then
		topText:SetText(ownIconString)
		topText:Show()
	else
		if topText:GetText() == otherIconString or topText:GetText() == ownIconString then
			topText:SetText("")
			topText:Show()
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
				waitingOnItemData[itemID] = {bag = bag, slot = slot, position = position, topText = topText, bottomText = bottomText}
			else
				ProcessItem(itemID, bag, slot, position, topText, bottomText)
			end
		else
			topText:SetText("")
			topText:Show()

			bottomText:SetText("")
			bottomText:Show()
		end
	end
end

hooksecurefunc("ContainerFrame_Update", OnContainerUpdate)

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
		local name, texture, count, quality, canUse, level, levelColHeader, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemId, hasAllInfo =  GetAuctionItemInfo("list", auctionIndex);
		local buttonName = "BrowseButton"..i;
		local itemCount = _G[buttonName.."ItemCount"];

		local itemLink = GetAuctionItemLink("list", auctionIndex)
		if(itemLink) then
			local bindingStatus = GetBindingStatus("AuctionFrame", auctionIndex, itemLink)

			local appearanceID, isCollected, sourceID = GetItemAppearance(itemLink)
			if appearanceID then
				if not PlayerHasAppearance(appearanceID) and not IsSourceArtifact(sourceID) then
					if PlayerCanCollectAppearance(appearanceID) then
						itemCount:SetText("|TInterface\\Store\\category-icon-featured:" .. position .. "|t")
						itemCount:Show()
					else
						-- Can't equip on current toon but still need to learn
						itemCount:SetText("|TInterface\\Store\\category-icon-placeholder:" .. position .. "|t")
						itemCount:Show()
					end
				end
			elseif PlayerNeedsTransmogMissingAppearance(itemLink) then
				itemCount:SetText("|TInterface\\Store\\category-icon-featured:" .. position .. "|t")
				itemCount:Show()
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
			itemCount:SetText("")
			itemCount:Show()
		end
	end
end

hooksecurefunc("MerchantFrame_UpdateMerchantInfo", OnMerchantUpdate)

local function OnEvent(self, event, ...)
	local handler = self[event]
	if(handler) then
		handler(self, ...)
	end
end

eventFrame = CreateFrame("FRAME", "CaerdonWardrobeFrame")
eventFrame:RegisterEvent "ADDON_LOADED"
eventFrame:SetScript("OnEvent", OnEvent)

function eventFrame:ADDON_LOADED(name)
	if name == ADDON_NAME then
		if IsLoggedIn() then
			OnEvent(eventFrame, "PLAYER_LOGIN")
		else
			eventFrame:RegisterEvent "PLAYER_LOGIN"
		end
	elseif name == "Blizzard_AuctionUI" then
		hooksecurefunc("AuctionFrameBrowse_Update", OnAuctionBrowseUpdate)
	end
end

function eventFrame:PLAYER_LOGIN(...)
	eventFrame:RegisterEvent "BAG_UPDATE_DELAYED"
	eventFrame:RegisterEvent "GET_ITEM_INFO_RECEIVED"
	eventFrame:RegisterEvent "TRANSMOG_COLLECTION_UPDATED"
	C_TransmogCollection.SetShowMissingSourceInItemTooltips(true)
end

local function RefreshItems()
	if MerchantFrame:IsShown() then
		OnMerchantUpdate()
	end

	if AuctionFrame and AuctionFrame:IsShown() then
		OnAuctionBrowseUpdate()
	end

	ContainerFrame_UpdateAll()
end

function eventFrame:BAG_UPDATE_DELAYED()
	RefreshItems()
end

function eventFrame:GET_ITEM_INFO_RECEIVED(itemID)
	local itemInfo = waitingOnItemData[itemID]
	if itemInfo then
		local itemName, _, itemQuality, _, _, _, _, _, _, texture = GetItemInfo(itemID)
		if itemName then
			waitingOnItemData[itemID] = nil
			ProcessItem(itemID, itemInfo.bag, itemInfo.slot, itemInfo.position, itemInfo.topText, itemInfo.bottomText)
		end
	end
end

function eventFrame:TRANSMOG_COLLECTION_UPDATED()
	RefreshItems()
end
