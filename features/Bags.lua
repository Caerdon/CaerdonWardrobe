local BagMixin = {}

function BagMixin:GetName()
	return "Bags"
end

function BagMixin:Init()
end

function BagMixin:SetTooltipItem(tooltip, item, locationInfo)
end

function BagMixin:Refresh()
end

CaerdonWardrobe:RegisterFeature(BagMixin)
