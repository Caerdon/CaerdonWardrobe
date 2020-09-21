local GuildBankMixin = {}

function GuildBankMixin:Init(frame)
	self.frame = frame
end

function GuildBankMixin:OnLoad()
	self.frame:RegisterEvent "ADDON_LOADED"
end

function GuildBankMixin:SetTooltipItem(tooltip, item, locationInfo)
end

function GuildBankMixin:ADDON_LOADED(name)
	-- if name == "" then
	-- 	self.frame:RegisterEvent ""
	-- end
end

CaerdonWardrobe:RegisterFeature("GuildBank", GuildBankMixin)
