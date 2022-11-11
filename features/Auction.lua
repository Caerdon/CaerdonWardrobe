local AuctionMixin = {}

function AuctionMixin:GetName()
	return "Auction"
end

-- TODO: Look into ScrollUtil.AddAcquiredFrameCallback and friends for all the ScrollBox integrations
function AuctionMixin:Init(frame)
	self.auctionContinuableContainer = ContinuableContainer:Create()
	self.shouldHookAuction = true

	return {
		"AUCTION_HOUSE_SHOW",
		-- "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
		-- "OWNED_AUCTIONS_UPDATED"
	}
end

-- function AuctionMixin:AUCTION_HOUSE_BROWSE_RESULTS_UPDATED()
-- end

function AuctionMixin:AUCTION_HOUSE_SHOW()
	if (self.shouldHookAuction) then
		self.shouldHookAuction = false
		ScrollUtil.AddInitializedFrameCallback(AuctionHouseFrame.AuctionsFrame.AllAuctionsList.ScrollBox, function (...) self:OnAllAuctionsInitializedFrame(...) end, AuctionHouseFrame.AuctionsFrame.AllAuctionsList, false)
        ScrollUtil.AddInitializedFrameCallback(AuctionHouseFrame.BrowseResultsFrame.ItemList.ScrollBox, function (...) self:OnInitializedFrame(...) end, AuctionHouseFrame.BrowseResultsFrame.ItemList, false)
		hooksecurefunc(AuctionHouseFrame, "SelectBrowseResult", function(...) self:OnSelectBrowseResult(...) end)
		hooksecurefunc(AuctionHouseFrame, "SetPostItem", function(...) self:OnSetPostItem(...) end)
		hooksecurefunc(AuctionHouseFrame.AuctionsFrame.ItemDisplay, "SetItemInternal", function(...) self:OnSetAuctionItemDisplay(...) end)
	end
end

function AuctionMixin:OnAllAuctionsInitializedFrame(auctionFrame, frame, elementData)
	local button = frame
	local item

	if not elementData then return end

	local browseResult = auctionFrame.tableBuilder:GetDataProviderData(elementData)
	
	if not browseResult.itemLink then
		CaerdonWardrobe:ClearButton(button)
		return
	end

	local item = CaerdonItem:CreateFromItemLink(browseResult.itemLink)
	local itemKey = browseResult.itemKey

	CaerdonWardrobe:UpdateButton(button, item, self, {
		locationKey = format("allAuctions%d-%d-%d-%d", itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix, ((itemKeyInfo and itemKeyInfo.quality) or 0)),
		itemKey = itemKey
	},  
	{
		overrideStatusPosition = "LEFT",
		statusProminentSize = 13,
		statusOffsetX = 7,
		statusOffsetY = 0
	})
end

function AuctionMixin:OnInitializedFrame(auctionFrame, frame, elementData)
	local button = frame
	local item

	if not elementData then return end
	if not frame.rowData then return end

	local itemKey = frame.rowData.itemKey
	local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(itemKey)

	if itemKeyInfo and itemKeyInfo.battlePetLink then
		item = CaerdonItem:CreateFromItemLink(itemKeyInfo.battlePetLink)
	else
		item = CaerdonItem:CreateFromItemID(itemKey.itemID)
	end

	CaerdonWardrobe:UpdateButton(button, item, self, {
		locationKey = format("%d-%d-%d-%d", itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix, ((itemKeyInfo and itemKeyInfo.quality) or 0)),
		itemKey = itemKey
	},  
	{
		overrideStatusPosition = "LEFT",
		statusProminentSize = 13,
		statusOffsetX = 7,
		statusOffsetY = 0,
		-- relativeFrame=cell.Icon
	})
end

function AuctionMixin:GetTooltipData(item, locationInfo)
	local itemKey = locationInfo.itemKey
	if itemKey and itemKey.itemID and itemKey.itemLevel and itemKey.itemSuffix then
		local requiredLevel = C_AuctionHouse.GetItemKeyRequiredLevel(itemKey)
		return C_TooltipInfo.GetItemKey(itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix, requiredLevel)
	else
		return C_TooltipInfo.GetHyperlink(item:GetItemLink())
	end
end

function AuctionMixin:Refresh()
	if AuctionFrame and AuctionFrame:IsShown() then
		-- TODO: Could refresh here but probably don't need to?
	end
end

function AuctionMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	return {
		bindingStatus = {
			shouldShow = false
		},
		ownIcon = {
			shouldShow = CaerdonWardrobeConfig.Icon.ShowLearnable.Auction
		},
		otherIcon = {
			shouldShow = CaerdonWardrobeConfig.Icon.ShowLearnableByOther.Auction
		},
		questIcon = {
			shouldShow = false
		},
		oldExpansionIcon = {
			shouldShow = CaerdonWardrobeConfig.Icon.ShowOldExpansion.Auction
		},
        sellableIcon = {
            shouldShow = false
        }
	}
end

function AuctionMixin:OnSetAuctionItemDisplay(frame, itemDisplayItem)
	local itemDisplay = AuctionHouseFrame.AuctionsFrame.ItemDisplay
	local itemButton = itemDisplay.ItemButton

	if itemDisplay.itemValidationFunc and not itemDisplay.itemValidationFunc(itemDisplay) then
		return;
	end

	if not itemDisplayItem then
		CaerdonWardrobe:ClearButton(itemButton)
		return;
	end

	if itemDisplay.itemLink == nil then
		CaerdonWardrobe:ClearButton(itemButton)
		return;
	end

	local item = CaerdonItem:CreateFromItemLink(itemDisplay.itemLink)

	CaerdonWardrobe:UpdateButton(itemButton, item, self, {
		locationKey = "ItemAuctionItemDisplayButton",
		itemKey = itemDisplay.itemKey
	},  
	{
		statusProminentSize = 24,
		statusOffsetX = 5,
		statusOffsetY = 5
	})
end

-- function AuctionMixin:OWNED_AUCTIONS_UPDATED()
-- 	-- self:UpdateItemList(AuctionHouseFrame.AuctionsFrame.AllAuctionsList, 1)
-- end

-- function AuctionMixin:OnScrollBoxRangeChanged(sortPending)
-- 	self:UpdateItemList(AuctionHouseFrame.BrowseResultsFrame.ItemList, 2)
-- end

-- function AuctionMixin:UpdateItemList(itemList, buttonCellIndex)
-- 	if self.auctionTimer then
-- 		self.auctionTimer:Cancel()
-- 	end

-- 	-- TODO: Battle Pet scans are not clean, yet.
-- 	self.auctionContinuableContainer:Cancel()

-- 	self.auctionTimer = C_Timer.NewTimer(0.05, function() 
-- 		local index = itemList.ScrollBox:GetDataIndexBegin();
-- 		itemList.ScrollBox:ForEachFrame(function(button)
-- 			local browseResult = itemList.tableBuilder:GetDataProviderData(index)
-- 			if browseResult then
-- 				local item = CaerdonItem:CreateFromItemID(browseResult.itemKey.itemID)
-- 				if not item:IsItemEmpty() then
-- 					self.auctionContinuableContainer:AddContinuable(item)
-- 				end
-- 			end

-- 			index = index + 1;
-- 		end);

-- 		self.auctionContinuableContainer:ContinueOnLoad(function()
-- 			-- local checkOffset = itemList:GetScrollOffset();
-- 			-- -- TODO: Not sure if this is actually doing anything - hasn't been triggered, yet.
-- 			-- if checkOffset ~= offset then 
-- 			-- 	return
-- 			-- end

-- 			-- for i, button in ipairs(buttons) do
-- 			local dataIndex = itemList.ScrollBox:GetDataIndexBegin();
-- 			local dataIndexEnd = itemList.ScrollBox:GetDataIndexEnd();
-- 			local frameCount = itemList.ScrollBox:GetFrameCount()
-- 			local offset = 0
-- 			if frameCount < dataIndexEnd then
-- 				offset = frameCount - dataIndexEnd
-- 			end
-- 			itemList.ScrollBox:ForEachFrame(function(button)
-- 				local slot = dataIndex + offset
-- 				local browseResult = itemList.tableBuilder:GetDataProviderData(dataIndex)
-- 				if browseResult then
-- 					local row = itemList.tableBuilder.rows[slot] -- TODO: This is matching on the wrong row... probably unsorted?  Searching through for now.
-- 					for i, checkRow in ipairs(itemList.tableBuilder.rows) do
-- 						if checkRow.rowData == browseResult then
-- 							row = checkRow
-- 						end
-- 					end

-- 					local cell = row.cells[buttonCellIndex]
			
-- 					if button then
-- 						local item
-- 						local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(browseResult.itemKey)
		
-- 						if itemKeyInfo and itemKeyInfo.battlePetLink then
-- 							item = CaerdonItem:CreateFromItemLink(itemKeyInfo.battlePetLink)
-- 						else
-- 							item = CaerdonItem:CreateFromItemID(browseResult.itemKey.itemID)
-- 						end

-- 						CaerdonWardrobe:UpdateButton(button, item, self, {
-- 							locationKey = format("%d", slot),
-- 							index = slot,
-- 							itemKey = browseResult.itemKey
-- 						},  
-- 						{
-- 							overrideStatusPosition = "LEFT",
-- 							statusProminentSize = 13,
-- 							statusOffsetX = -4,
-- 							statusOffsetY = 0,
-- 							relativeFrame=cell.Icon
-- 						})
-- 					end
-- 				end
-- 				dataIndex = dataIndex + 1;
-- 			end)
-- 		end)
-- 	end, 1)
-- end

function AuctionMixin:OnSelectBrowseResult(frame, browseResult)
	local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(browseResult.itemKey)

	local item
	if itemKeyInfo and itemKeyInfo.battlePetLink then
		item = CaerdonItem:CreateFromItemLink(itemKeyInfo.battlePetLink)
	else
		item = CaerdonItem:CreateFromItemID(browseResult.itemKey.itemID)
	end

	local button = AuctionHouseFrame.ItemBuyFrame.ItemDisplay.ItemButton
	CaerdonWardrobe:UpdateButton(button, item, self, {
		locationKey = "BrowseResultButton",
		itemKey = itemKeyInfo
	},  
	{
		statusProminentSize = 24,
		statusOffsetX = 5,
		statusOffsetY = 5
	})
end

function AuctionMixin:OnSetPostItem(frame, itemLocation)
	local displayMode = AuctionHouseFrame:GetDisplayMode()
	local item = CaerdonItem:CreateFromItemLocation(itemLocation)

	local itemSellButton = AuctionHouseFrame.ItemSellFrame.ItemDisplay.ItemButton
	local commoditiesSellButton = AuctionHouseFrame.CommoditiesSellFrame.ItemDisplay.ItemButton
	if displayMode == AuctionHouseFrameDisplayMode.ItemSell then
		CaerdonWardrobe:ClearButton(commoditiesSellButton)
		CaerdonWardrobe:UpdateButton(itemSellButton, item, self, {
			locationKey = "ItemSellFrameButton",
			itemKey = AuctionHouseFrame.ItemSellFrame.listDisplayedItemKey
		},  
		{
			statusProminentSize = 24,
			statusOffsetX = 5,
			statusOffsetY = 5
		})
	elseif displayMode == AuctionHouseFrameDisplayMode.CommoditiesSell then
		CaerdonWardrobe:ClearButton(itemSellButton)
		CaerdonWardrobe:UpdateButton(commoditiesSellButton, item, self, {
			locationKey = "ItemCommoditiesSellFrameButton"
		},  
		{
			statusProminentSize = 24,
			statusOffsetX = 5,
			statusOffsetY = 5
		})
	else
		CaerdonWardrobe:ClearButton(commoditiesSellButton)
		CaerdonWardrobe:ClearButton(itemSellButton)
	end
end

function AuctionMixin:OnClearPostItem(frame)
	local itemSellButton = AuctionHouseFrame.ItemSellFrame.ItemDisplay.ItemButton
	local commoditiesSellButton = AuctionHouseFrame.CommoditiesSellFrame.ItemDisplay.ItemButton

	CaerdonWardrobe:ClearButton(commoditiesSellButton)
	CaerdonWardrobe:ClearButton(itemSellButton)
end

CaerdonWardrobe:RegisterFeature(AuctionMixin)
