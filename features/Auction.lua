local AuctionMixin = {}

function AuctionMixin:Init(frame)
	self.frame = frame
end

function AuctionMixin:OnLoad()
	self.frame:RegisterEvent "ADDON_LOADED"
end

function AuctionMixin:SetTooltipItem(tooltip, item, locationInfo)
end

function AuctionMixin:ADDON_LOADED(name)
	-- if name == "" then
	-- 	self.frame:RegisterEvent ""
	-- end
end

CaerdonWardrobe:RegisterFeature("Auction", AuctionMixin)
