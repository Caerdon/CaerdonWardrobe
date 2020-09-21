local BankMixin = {}

function BankMixin:GetName()
	return "Bank"
end

function BankMixin:Init()
end

function BankMixin:SetTooltipItem(tooltip, item, locationInfo)
end

function BankMixin:Refresh()
end

CaerdonWardrobe:RegisterFeature(BankMixin)
