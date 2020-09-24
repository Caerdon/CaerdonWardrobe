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
				bindingOffsetY = 7,
				overrideWidth = button.Item:GetWidth()
			}
				
			if ( index <= numItems ) then
				local name, texture, quantity, itemType, usable, level, levelType, sellerName, minBid, minIncrement, currBid, youHaveHighBid, numBids, timeLeft, link, marketID, quality = C_BlackMarket.GetItemInfoByIndex(index);
				CaerdonWardrobe:UpdateButtonLink(link, self:GetName(), { type="listItem", index = index }, button, options)
			else
				CaerdonWardrobe:ClearButton(button)
			end
		end
	end)
end

function BlackMarketMixin:UpdateBlackMarketHotItem()
	local button = BlackMarketFrame.HotDeal.Item
	local name, texture, quantity, itemType, usable, level, levelType, sellerName, minBid, minIncrement, currBid, youHaveHighBid, numBids, timeLeft, link, marketID, quality = C_BlackMarket.GetHotItem();
	CaerdonWardrobe:UpdateButtonLink(link, self:GetName(), { type="hotItem" }, button, nil)
end

CaerdonWardrobe:RegisterFeature(BlackMarketMixin)
