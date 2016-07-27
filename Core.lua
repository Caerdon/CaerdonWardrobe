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

	if playerLevel > reqLevel then
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

local function ShouldIgnoreSource(sourceID)
	local link = select(6, C_TransmogCollection.GetAppearanceSourceInfo(sourceID));
	local _, _, quality = GetItemInfo(link);
	return quality == LE_ITEM_QUALITY_ARTIFACT or quality == LE_ITEM_QUALITY_COMMON
end

local function GetItemKey(bag, slot, itemLink)
	local itemKey
	-- TODO: Clean this up
	if bag == "GuildBankFrame" then
		itemKey = bag .. slot.tab .. slot.index .. itemLink
	else
		itemKey = bag .. slot .. itemLink
	end

	return itemKey
end

local function GetBindingStatus(bag, slot, itemLink)
	local itemKey = GetItemKey(bag, slot, itemLink)

	local bindingText = cachedBinding[itemKey]
	if not bindingText then
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

		local appearanceID, isCollected, sourceID = GetItemAppearance(itemID)

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
		tooltip:AddDoubleLine("PlayerNeedsTransmogMissingAppearance:", tostring(PlayerNeedsTransmogMissingAppearance(itemLink)))

		tooltip:Show()
	end
end

local waitingOnItemData = {}

local function SetItemButtonMogStatus(button, status)
	local mogStatus = button.mogStatus
	if not status and not mogStatus then return end
	if not status then
		mogStatus:SetTexture("")
		return
	end

	if not mogStatus then
		-- see ItemButtonTemplate.Count @ ItemButtonTemplate.xml#13
		mogStatus = button:CreateTexture(nil, "OVERLAY", nil, 1)
		mogStatus:SetPoint("TOPLEFT", -15, 15)
		mogStatus:SetSize(40, 40)
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

	if status == "own" then
		mogStatus:SetTexture("Interface\\Store\\category-icon-featured")
	else
		mogStatus:SetTexture("Interface\\Store\\category-icon-placeholder")
	end

	local showAnim = true
	if MailFrame:IsShown() or (AuctionFrame and AuctionFrame:IsShown()) then
		showAnim = false
	end

	if showAnim then
		mogAnim:Play()
	else
		mogAnim:Stop()
	end
end

local function SetItemButtonBindType(button, text)
	local bindsOnText = button.bindsOnText
	if not text and not bindsOnText then return end
	if not text then
		bindsOnText:SetText("")
		return
	end
	if not bindsOnText then
		-- see ItemButtonTemplate.Count @ ItemButtonTemplate.xml#13
		bindsOnText = button:CreateFontString(nil, "ARTWORK", "GameFontNormalOutline")
		bindsOnText:SetPoint("BOTTOMRIGHT", -5, 2)
		button.bindsOnText = bindsOnText
	end
	bindsOnText:SetText(text)
end

function CaerdonWardrobe:ResetButton(button)
	SetItemButtonMogStatus(button, nil)
	SetItemButtonBindType(button, nil)
end

local function ProcessItem(itemID, bag, slot, showMogIcon, showBindStatus, button, itemProcessed)
	local bindingText
	local mogStatus = nil

	local name, itemLink, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture, vendorPrice = GetItemInfo(itemID)

	local appearanceID, isCollected, sourceID = GetItemAppearance(itemID)
	if(appearanceID and not ShouldIgnoreSource(sourceID)) then
		local bindingStatus

		bindingStatus = GetBindingStatus(bag, slot, itemLink)

		if(not isCollected and not PlayerHasAppearance(appearanceID, itemLink)) then
			if PlayerCanCollectAppearance(appearanceID, itemLink) then
				mogStatus = "own"

				if bindingStatus and showBindStatus then
					bindingText = bindingStatus
				end
			else
				if bindingStatus then
					if PlayerNeedsTransmogMissingAppearance(itemLink) then
						-- Can't equip on current toon but still need to learn
						mogStatus = "other"
					end

					if showBindStatus then 
						bindingText = "|cFFFF0000" .. bindingStatus .. "|r"
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

			if showBindStatus then
				if bindingStatus then
					bindingText = "|cFF00FF00" .. bindingStatus .. "|r"
				else
					bindingText = nil
				end
			end
		end
	elseif PlayerNeedsTransmogMissingAppearance(itemLink) then
		mogStatus = "own"
	else
		-- Hide anything that doesn't match
		-- if button then
		-- 	--button.IconBorder:SetVertexColor(100, 255, 50)
		-- 	button.searchOverlay:Show()
		-- end
	end

	if button then
		SetItemButtonMogStatus(button, mogStatus)

		-- TODO: Consider making this an option
		-- if bag ~= "GuildBankFrame" then
			SetItemButtonBindType(button, bindingText)
		-- end
	end

	if itemProcessed then
		itemProcessed(mogStatus, bindingText)
	end
end

local function ProcessOrWaitItem(itemID, bag, slot, showMogIcon, showBindStatus, button, itemProcessed)
	if itemID then
		local waitItem = waitingOnItemData[itemID]
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
		if itemName == nil then
			waitBag[tostring(slot)] = { slot = slot, showMogIcon = showMogIcon, showBindStatus = showBindStatus, button = button, itemProcessed = itemProcessed}
		else
			waitingOnItemData[tostring(itemID)][tostring(bag)][tostring(slot)] = nil
			ProcessItem(itemID, bag, slot, showMogIcon, showBindStatus, button, itemProcessed)
		end
	else
		SetItemButtonMogStatus(button, nil)
		SetItemButtonBindType(button, nil)
	end
end

function CaerdonWardrobe:ProcessItem(itemID, bag, slot, showMogIcon, showBindStatus, button, itemProcessed)
	ProcessOrWaitItem(itemID, bag, slot, showMogIcon, showBindStatus, button, itemProcessed)
end

local function OnContainerUpdate(self, asyncUpdate)
	-- if isBagUpdate and not asyncUpdate then
	-- 	return
	-- end

	if not self:IsShown() then
		return
	end

	local bag = self:GetID()

	for buttonIndex = 1, self.size do
		local button = _G[self:GetName() .. "Item" .. buttonIndex]
		local slot = button:GetID()

		local showMogIcon = true
		local showBindStatus = true

		local itemID = GetContainerItemID(bag, slot)
		local texture, itemCount, locked = GetContainerItemInfo(bag, slot)

		ProcessOrWaitItem(itemID, bag, slot, showMogIcon, showBindStatus, button)
	end
end

local waitingOnBagUpdate = {}
local function OnBagUpdate_Coroutine()
    for bagID, shouldUpdate in pairs(waitingOnBagUpdate) do
		local frame = _G["ContainerFrame".. bagID]
		OnContainerUpdate(frame, true)
		coroutine.yield()
    end

	waitingOnBagUpdate = {}
end

local function ScheduleContainerUpdate(bag)
	local bagID = bag:GetID()
	waitingOnBagUpdate[tostring(tonumber(bagID) + 1)] = true
	isBagUpdateRequested = true
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

	local showMogIcon = true
	local showBindStatus = true

	local itemID = GetContainerItemID(containerID, buttonID)
	ProcessOrWaitItem(itemID, bag, slot, showMogIcon, showBindStatus, button)
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

			local showMogIcon = true
			local showBindStatus = true

			local itemLink = GetGuildBankItemLink(tab, i)
			if itemLink then
				local itemID = itemLink:match("item:(%d+)")
				ProcessOrWaitItem(itemID, bag, slot, showMogIcon, showBindStatus, button)
			else
				-- nil results in button icon / text reset
				ProcessOrWaitItem(nil, bag, slot, showMogIcon, showBindStatus, button)
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

		local showMogIcon = true
		local showBindStatus = false

		local itemLink = GetAuctionItemLink("list", auctionIndex)
		if(itemLink) then
			local itemID = itemLink:match("item:(%d+)")
			if itemID then
				ProcessOrWaitItem(itemID, bag, slot, showMogIcon, showBindStatus, button)
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

		local showMogIcon = true
		local showBindStatus = true

		local itemID = GetMerchantItemID(index)
		ProcessOrWaitItem(itemID, bag, slot, showMogIcon, showBindStatus, button)
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
	["GET_ITEM_INFO_RECEIVED"] = {},
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
				ProcessOrWaitItem(itemID, bag, slotData.slot, slotData.showMogIcon, slotData.showBindStatus, slotData.button, slotData.itemProcessed)
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
