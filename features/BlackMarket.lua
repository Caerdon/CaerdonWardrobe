local BlackMarketMixin, BlackMarket = {}

local frame = CreateFrame("frame")
frame:RegisterEvent "ADDON_LOADED"
frame:SetScript("OnEvent", function(this, event, ...)
    BlackMarket[event](Quest, ...)
end)

function BlackMarketMixin:OnLoad()
end

function BlackMarketMixin:ADDON_LOADED(name)
	if name == "Blizzard_BlackMarketUI" then
		frame:RegisterEvent "BLACK_MARKET_ITEM_UPDATE"
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
			local itemID = CaerdonWardrobe:GetItemID(link)
			if ( itemID ) then
				CaerdonWardrobe:UpdateButton(itemID, "BlackMarketScrollFrame", index, button, nil)
			else
				CaerdonWardrobe:ClearButton(button)
			end
		else
            CaerdonWardrobe:ClearButton(button)
		end
	end
end

function BlackMarketMixin:UpdateBlackMarketHotItem()
	local button = BlackMarketFrame.HotDeal.Item
	local name, texture, quantity, itemType, usable, level, levelType, sellerName, minBid, minIncrement, currBid, youHaveHighBid, numBids, timeLeft, link, marketID, quality = C_BlackMarket.GetHotItem();
	local itemID = CaerdonWardrobe:GetItemID(link)
	if ( itemID ) then
		CaerdonWardrobe:UpdateButton(itemID, "BlackMarketScrollFrame", "HotItem", button, nil)
	else
        CaerdonWardrobe:ClearButton(button)
	end
end

function BlackMarketMixin:BLACK_MARKET_ITEM_UPDATE()
	BlackMarket:UpdateBlackMarketItems()
	BlackMarket:UpdateBlackMarketHotItem()
end

BlackMarket = CreateFromMixins(BlackMarketMixin)
BlackMarket:OnLoad()
