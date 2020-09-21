local AuctionMixin = {}

function AuctionMixin:GetName()
	return "Auction"
end

function AuctionMixin:Init(frame)
	self.auctionContinuableContainer = ContinuableContainer:Create()
	self.shouldHookAuction = true

	return {
		"AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
		"AUCTION_HOUSE_SHOW"
	}
end

function AuctionMixin:SetTooltipItem(tooltip, item, locationInfo)
	local itemKey = locationInfo.itemKey
	tooltip:SetItemKey(itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix)
end

function AuctionMixin:Refresh()
	if AuctionFrame and AuctionFrame:IsShown() then
		self:OnAuctionBrowseUpdate()
	end
end

function AuctionMixin:AUCTION_HOUSE_BROWSE_RESULTS_UPDATED()
	self:OnAuctionBrowseUpdate()
end

function AuctionMixin:AUCTION_HOUSE_SHOW()
	if (self.shouldHookAuction) then
		self.shouldHookAuction = false
		AuctionHouseFrame.BrowseResultsFrame.ItemList.ScrollFrame.scrollBar:HookScript("OnValueChanged", function(...) self:OnAuctionBrowseUpdate(...) end)
		hooksecurefunc(AuctionHouseFrame, "SelectBrowseResult", function(...) self:OnSelectBrowseResult(...) end)
	end
end

function AuctionMixin:OnAuctionBrowseUpdate()
	-- Event pump since first load won't have UI ready
	if not AuctionHouseFrame:IsVisible() then
		return
	end

	if self.auctionTimer then
		self.auctionTimer:Cancel()
	end

	-- TODO: Battle Pet scans are not clean, yet.
	self.auctionContinuableContainer:Cancel()

	local buttons = HybridScrollFrame_GetButtons(AuctionHouseFrame.BrowseResultsFrame.ItemList.ScrollFrame);
	for i, button in ipairs(buttons) do
		CaerdonWardrobe:ClearButton(button)
	end

	self.auctionTimer = C_Timer.NewTimer(0.1, function() 
		local browseResults = C_AuctionHouse.GetBrowseResults()
		local offset = AuctionHouseFrame.BrowseResultsFrame.ItemList:GetScrollOffset();

		local buttons = HybridScrollFrame_GetButtons(AuctionHouseFrame.BrowseResultsFrame.ItemList.ScrollFrame);
		for i, button in ipairs(buttons) do
			local bag = self:GetName()
			local slot = i + offset

			local _, itemLink

			local browseResult = browseResults[slot]
			if browseResult then
				local item = CaerdonItem:CreateFromItemID(browseResult.itemKey.itemID)
				-- TODO: Do we need to check if slot has changed for buttons?  Could do something here...
				-- item:ContinueOnItemLoad(function ()
				-- 	print(item:GetItemLink())
				-- end)
				if not item:IsItemEmpty() then
					self.auctionContinuableContainer:AddContinuable(item)
				end
			end
		end

		self.auctionContinuableContainer:ContinueOnLoad(function()
			local checkOffset = AuctionHouseFrame.BrowseResultsFrame.ItemList:GetScrollOffset();
			-- TODO: Not sure if this is actually doing anything - hasn't been triggered, yet.
			if checkOffset ~= offset then 
				return
			end

			for i, button in ipairs(buttons) do
				local bag = self:GetName()
				local slot = i + offset
	
				local _, itemLink
	
				local browseResult = browseResults[slot]
				if browseResult then
					local item = CaerdonItem:CreateFromItemID(browseResult.itemKey.itemID, bag, slot)
					local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(browseResult.itemKey)
	
					if itemKeyInfo and itemKeyInfo.battlePetLink then
						itemLink = itemKeyInfo.battlePetLink
					else
						itemLink = item:GetItemLink()
					end
	
					-- From AuctionHouseTableBuilder
					local PRICE_DISPLAY_WIDTH = 120;
					local PRICE_DISPLAY_WITH_CHECKMARK_WIDTH = 140;
					local PRICE_DISPLAY_PADDING = 0;
					local BUYOUT_DISPLAY_PADDING = 0;
					local STANDARD_PADDING = 10;

					local iconSize = 30
					-- From AuctionHouseTableBuilder.GetBrowseListLayout
					local iconOffset = 
						PRICE_DISPLAY_PADDING + 146 - (iconSize / 2)
					if itemLink and button then
						CaerdonWardrobe:UpdateButtonLink(itemLink, bag, { index = slot, itemKey = browseResult.itemKey }, button,  
						{
							overridePosition = "LEFT",
							iconOffset = iconOffset,
							iconSize = iconSize,				
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

function AuctionMixin:OnAuctionBrowseClick(frame, buttonName, isDown)
	if (buttonName == "LeftButton" and isDown) then
		self:OnAuctionBrowseUpdate()
	end
end

function AuctionMixin:OnSelectBrowseResult(frame, browseResult)
	local itemLink
	local item = CaerdonItem:CreateFromItemID(browseResult.itemKey.itemID)
	local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(browseResult.itemKey)

	if itemKeyInfo and itemKeyInfo.battlePetLink then
		itemLink = itemKeyInfo.battlePetLink
	else
		itemLink = item:GetItemLink()
	end

	CaerdonWardrobe:UpdateButtonLink(itemLink, "ItemLink", nil, AuctionHouseFrame.ItemBuyFrame.ItemDisplay.ItemButton,  
	{
		overridePosition = "TOPLEFT",
		iconOffset = -5,
		iconSize = 50,				
		showMogIcon=true, 
		showBindStatus=false, 
		showSellables=false
	})
end

CaerdonWardrobe:RegisterFeature(AuctionMixin)
