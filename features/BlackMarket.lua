local BlackMarketMixin = {}

function BlackMarketMixin:GetName()
	return "BlackMarket"
end

function BlackMarketMixin:Init()
	return { "BLACK_MARKET_ITEM_UPDATE" }
end

function BlackMarketMixin:SetTooltipItem(tooltip, item, locationInfo)
	tooltip:SetHyperlink(item:GetItemLink())
end

function BlackMarketMixin:Refresh()
end

function BlackMarketMixin:BLACK_MARKET_ITEM_UPDATE()
	if BlackMarketScrollFrame:IsShown() then
		self:UpdateBlackMarketItems()
		self:UpdateBlackMarketHotItem()
	end
end

function BlackMarketMixin:UpdateBlackMarketItems()
	-- Pump to ensure buttons are ready
	C_Timer.After(0, function ()
		local numItems = C_BlackMarket.GetNumItems();
		
		if (not numItems) then
			numItems = 0;
		end
		
		local scrollFrame = BlackMarketScrollFrame;
		local offset = HybridScrollFrame_GetOffset(scrollFrame);
		local buttons = scrollFrame.buttons;
		local numButtons = #buttons;

		for i = 1, numButtons do
			local button = buttons[i];
			local index = offset + i; -- adjust index

			local options = {
				relativeFrame = button.Item
			}
				
			if ( index <= numItems ) then
				local name, texture, quantity, itemType, usable, level, levelType, sellerName, minBid, minIncrement, currBid, youHaveHighBid, numBids, timeLeft, link, marketID, quality = C_BlackMarket.GetItemInfoByIndex(index);
				if link then
					local item = CaerdonItem:CreateFromItemLink(link)
					CaerdonWardrobe:UpdateButton(button, item, self, { 
						locationKey = format("%d", index),
						type = "listItem", 
						index = index 
					}, options)
				else
					CaerdonWardrobe:ClearButton(button)
				end
			else
				CaerdonWardrobe:ClearButton(button)
			end
		end
	end)
end

function BlackMarketMixin:UpdateBlackMarketHotItem()
	local button = BlackMarketFrame.HotDeal.Item
	local name, texture, quantity, itemType, usable, level, levelType, sellerName, minBid, minIncrement, currBid, youHaveHighBid, numBids, timeLeft, link, marketID, quality = C_BlackMarket.GetHotItem();
	if link then
		local item = CaerdonItem:CreateFromItemLink(link)
		CaerdonWardrobe:UpdateButton(button, item, self, {
			locationKey = format("hotItem"),
			type="hotItem"
		}, nil)
	else
		CaerdonWardrobe:ClearButton(button)
	end
end

CaerdonWardrobe:RegisterFeature(BlackMarketMixin)
