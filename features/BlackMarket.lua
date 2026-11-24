local BlackMarketMixin = {}

function BlackMarketMixin:GetName()
	return "BlackMarket"
end

function BlackMarketMixin:Init()
	self:WhenAddOnLoaded("Blizzard_BlackMarketUI", self.OnBlackMarketLoaded)
	return { "BLACK_MARKET_ITEM_UPDATE" }
end

function BlackMarketMixin:OnBlackMarketLoaded()
	BlackMarketFrame.ScrollBox:RegisterCallback("OnDataRangeChanged", self.OnScrollBoxRangeChanged, self);
end

-- What this window shows of an item (FeatureMixin.lua, displayRules).
BlackMarketMixin.displayRules = {
	bindingStatus = true,
	ownIcon = true,
	otherIcon = "BlackMarket",
	oldExpansionIcon = false,
	sellableIcon = false,
}

function BlackMarketMixin:BLACK_MARKET_ITEM_UPDATE()
	if BlackMarketFrame:IsShown() then
		self:UpdateBlackMarketHotItem()
	end
end

function BlackMarketMixin:OnScrollBoxRangeChanged(sortPending)
	local scrollBox = BlackMarketFrame.ScrollBox
	local index = scrollBox:GetDataIndexBegin();
	scrollBox:ForEachFrame(function(button)
		local options = {
			relativeFrame = button.Item
		}
			
		local itemLink = button.itemLink
		if itemLink then
			local item = CaerdonItem:CreateFromItemLink(itemLink)
			CaerdonWardrobe:UpdateButton(button, item, self, { 
				locationKey = format("%d", index),
				type = "listItem", 
				index = index 
			}, options)
		else
			CaerdonWardrobe:ClearButton(button)
		end

		index = index + 1;
	end);
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
