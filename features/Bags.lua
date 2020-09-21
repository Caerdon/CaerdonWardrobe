local BagMixin = {}

function BagMixin:Init(frame)
	self.frame = frame
end

function BagMixin:OnLoad()
	self.frame:RegisterEvent "ADDON_LOADED"
end

function BagMixin:SetTooltipItem(tooltip, item, locationInfo)
end

function BagMixin:ADDON_LOADED(name)
	-- if name == "" then
	-- 	self.frame:RegisterEvent ""
	-- end
end

CaerdonWardrobe:RegisterFeature("Bags", BagMixin)
