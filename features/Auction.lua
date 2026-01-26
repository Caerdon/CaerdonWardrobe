local AuctionMixin = {}

function AuctionMixin:GetName()
	return "Auction"
end

-- TODO: Look into ScrollUtil.AddAcquiredFrameCallback and friends for all the ScrollBox integrations
function AuctionMixin:Init(frame)
	self.waitingForItemKeyInfo = {}
	self.auctionContinuableContainer = ContinuableContainer:Create()
	self.shouldHookAuction = true

	return {
		"AUCTION_HOUSE_SHOW",
		"ITEM_KEY_ITEM_INFO_RECEIVED",
		-- "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
		-- "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"
		-- "OWNED_AUCTIONS_UPDATED"
	}
end

-- function AuctionMixin:AUCTION_HOUSE_BROWSE_RESULTS_UPDATED()
-- 	print("Results Updated")
-- 	-- DevTools_Dump(C_AuctionHouse.GetBrowseResults())
-- end

-- function AuctionMixin:AUCTION_HOUSE_BROWSE_RESULTS_ADDED()
-- 	print("Results Added")
-- end

function AuctionMixin:AUCTION_HOUSE_SHOW()
	if (self.shouldHookAuction) then
		self.shouldHookAuction = false
		ScrollUtil.AddInitializedFrameCallback(AuctionHouseFrame.AuctionsFrame.AllAuctionsList.ScrollBox, function (...) self:OnAllAuctionsInitializedFrame(...) end, AuctionHouseFrame.AuctionsFrame.AllAuctionsList, false)
		ScrollUtil.AddInitializedFrameCallback(AuctionHouseFrame.BrowseResultsFrame.ItemList.ScrollBox, function (...) self:OnInitializedFrame(...) end, AuctionHouseFrame.BrowseResultsFrame.ItemList, false)
		if C_AddOns.IsAddOnLoaded("TradeSkillMaster") then
			 -- TSM breaks the normal AH scrollbox frame initialization, so we have to hook into scroll events to ensure we can still show icons
			 -- NOTE: This only ensures icons show up in the Blizzard AH interface.  TSM is unreasonably locked down, so I can't augment it at
			 -- all.
			AuctionHouseFrame.BrowseResultsFrame.ItemList.ScrollBox:RegisterCallback(BaseScrollBoxEvents.OnLayout, function (...) self.OnScrollBoxLayout(..., AuctionHouseFrame.BrowseResultsFrame.ItemList.ScrollBox) end, self);
			AuctionHouseFrame.BrowseResultsFrame.ItemList.ScrollBox:RegisterCallback(BaseScrollBoxEvents.OnScroll, function (...) self.OnScrollBoxScroll(..., AuctionHouseFrame.BrowseResultsFrame.ItemList.ScrollBox) end, self);
		end
		hooksecurefunc(AuctionHouseFrame, "SelectBrowseResult", function(...) self:OnSelectBrowseResult(...) end)
		hooksecurefunc(AuctionHouseFrame, "SetPostItem", function(...) self:OnSetPostItem(...) end)
		hooksecurefunc(AuctionHouseFrame.AuctionsFrame.ItemDisplay, "SetItemInternal", function(...) self:OnSetAuctionItemDisplay(...) end)
	end
end

function AuctionMixin:ITEM_KEY_ITEM_INFO_RECEIVED(itemID)
	local processQueue = self.waitingForItemKeyInfo[itemID]
	if processQueue then
		for locationKey, processInfo in pairs(processQueue) do
			local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(processInfo.itemKey)
			if itemKeyInfo then
				self:ProcessItemKeyInfo(processInfo.itemKey, itemKeyInfo, processInfo.frame)
			end
		end

		self.waitingForItemKeyInfo[itemID] = nil
	end
end

function AuctionMixin:OnScrollBoxLayout(scrollBox)
	scrollBox:ForEachFrame(function(frame, elementData)
		self:OnInitializedFrame(AuctionHouseFrame.BrowseResultsFrame, frame, elementData)
	end)
end

local scrollTimer
function AuctionMixin:OnScrollBoxScroll(scrollBox)
	if scrollTimer then
		scrollTimer:Cancel()
	end

	scrollBox:ForEachFrame(function(frame, elementData)
		CaerdonWardrobe:ClearButton(frame)
	end)

	scrollTimer = C_Timer.NewTimer(0.1, function ()
		scrollBox:ForEachFrame(function(frame, elementData)
			self:OnInitializedFrame(AuctionHouseFrame.BrowseResultsFrame, frame, elementData)
		end)
	end)
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

function AuctionMixin:ProcessItemKeyInfo(itemKey, itemKeyInfo, button)
	local item
	local rowData = button.rowData

	local options = {
		overrideStatusPosition = "LEFT",
		statusProminentSize = 13,
		statusOffsetX = 7,
		statusOffsetY = 0,
		-- relativeFrame=cell.Icon
	}

	if itemKeyInfo and itemKeyInfo.battlePetLink then
		item = CaerdonItem:CreateFromItemLink(itemKeyInfo.battlePetLink)
		CaerdonWardrobe:UpdateButton(button, item, self, {
			locationKey = format("pet-%s", itemKeyInfo.battlePetLink),
			itemKey = itemKey
		}, options)
	elseif rowData.appearanceLink then
		-- Using appearance link if it's available due to not getting full item link from AH in any other way right now.
		-- This fixes Nimble Hexweave Cloak, for example, but doesn't fix Ceremonious Greaves (which doesn't have appearanceLink)
		local appearanceSourceID = string.match(rowData.appearanceLink, ".*transmogappearance:(%d*)")
		local category, itemAppearanceID, canHaveIllusion, icon, isCollected, itemLink, transmoglink, sourceType, itemSubClass =
			C_TransmogCollection.GetAppearanceSourceInfo(appearanceSourceID)

		-- Pass itemKey.itemLevel directly as overrideItemLevel since item links from AH don't encode the actual listing's ilvl
		local extraData = {
			appearanceSourceID = appearanceSourceID,
			appearanceID = itemAppearanceID,
			overrideItemLevel = itemKey.itemLevel
		}

		if itemLink then
			item = CaerdonItem:CreateFromItemLink(itemLink, extraData)
		else
			item = CaerdonItem:CreateFromItemID(itemKey.itemID)
			item.extraData = extraData
		end

		CaerdonAPI:CompareCIMI(self, item)

		CaerdonWardrobe:UpdateButton(button, item, self, {
			locationKey = format("%d-%d-%d-%d", itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix, ((itemKeyInfo and itemKeyInfo.quality) or 0)),
			itemKey = itemKey
		}, options)
	else
		-- Pass itemKey.itemLevel directly as overrideItemLevel since item links from AH don't encode the actual listing's ilvl
		local extraData = { overrideItemLevel = itemKey.itemLevel }

		local requiredLevel = C_AuctionHouse.GetItemKeyRequiredLevel(itemKey)
		local tooltipData = C_TooltipInfo and C_TooltipInfo.GetItemKey(itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix, requiredLevel)

		if tooltipData and tooltipData.hyperlink then
			item = CaerdonItem:CreateFromItemLink(tooltipData.hyperlink, extraData)
		else
			-- Fall back to itemID if we can't get a proper link
			item = CaerdonItem:CreateFromItemID(itemKey.itemID)
			item.extraData = extraData
		end

		CaerdonAPI:CompareCIMI(self, item)

		CaerdonWardrobe:UpdateButton(button, item, self, {
			locationKey = format("%d-%d-%d-%d", itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix, ((itemKeyInfo and itemKeyInfo.quality) or 0)),
			itemKey = itemKey
		}, options)
	end
end

function AuctionMixin:OnInitializedFrame(auctionFrame, frame, elementData)
	if not elementData then return end
	if not frame.rowData then return end

	local itemKey = frame.rowData.itemKey
	local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(itemKey)
	if not itemKeyInfo then
		local processKey = format("%d-%d-%d-%d", itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix, itemKey.battlePetSpeciesID)
		self.waitingForItemKeyInfo[itemKey.itemID] = self.waitingForItemKeyInfo[itemKey.itemID] or {}
		self.waitingForItemKeyInfo[itemKey.itemID][processKey] = { itemKey = itemKey, frame = frame }
		CaerdonWardrobe:ClearButton(frame)
		return
	end

	self:ProcessItemKeyInfo(itemKey, itemKeyInfo, frame)
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
