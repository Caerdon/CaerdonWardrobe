local BlackMarketMixin = {}

function BlackMarketMixin:Init(frame)
	self.frame = frame
end

function BlackMarketMixin:OnLoad()
	self.frame:RegisterEvent "ADDON_LOADED"
end

function BlackMarketMixin:SetTooltipItem(tooltip, item, locationInfo)
	tooltip:SetHyperlink(item:GetItemLink())
end

function BlackMarketMixin:ADDON_LOADED(name)
	if name == "Blizzard_BlackMarketUI" then
		self.frame:RegisterEvent "BLACK_MARKET_ITEM_UPDATE"
	end
end

function BlackMarketMixin:UpdateBlackMarketItems()
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

		if ( index <= numItems ) then
			local name, texture, quantity, itemType, usable, level, levelType, sellerName, minBid, minIncrement, currBid, youHaveHighBid, numBids, timeLeft, link, marketID, quality = C_BlackMarket.GetItemInfoByIndex(index);
			CaerdonWardrobe:UpdateButtonLink(link, "BlackMarket", index, button, nil)
		else
            CaerdonWardrobe:ClearButton(button)
		end
	end
end

function BlackMarketMixin:UpdateBlackMarketHotItem()
	local button = BlackMarketFrame.HotDeal.Item
	local name, texture, quantity, itemType, usable, level, levelType, sellerName, minBid, minIncrement, currBid, youHaveHighBid, numBids, timeLeft, link, marketID, quality = C_BlackMarket.GetHotItem();
	CaerdonWardrobe:UpdateButtonLink(link, "BlackMarket", "HotItem", button, nil)
end

function BlackMarketMixin:BLACK_MARKET_ITEM_UPDATE()
	self:UpdateBlackMarketItems()
	self:UpdateBlackMarketHotItem()
end

CaerdonWardrobe:RegisterFeature("BlackMarket", BlackMarketMixin)
