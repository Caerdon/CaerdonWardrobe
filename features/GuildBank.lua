local GuildBankMixin = {}

function GuildBankMixin:GetName()
	return "GuildBank"
end

function GuildBankMixin:Init()
end

function GuildBankMixin:SetTooltipItem(tooltip, item, locationInfo)
end

function GuildBankMixin:Refresh()
end

CaerdonWardrobe:RegisterFeature(GuildBankMixin)
