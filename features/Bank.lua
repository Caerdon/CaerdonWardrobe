local BankMixin = {}

function BankMixin:Init(frame)
	self.frame = frame
end

function BankMixin:OnLoad()
	self.frame:RegisterEvent "ADDON_LOADED"
end

function BankMixin:SetTooltipItem(tooltip, item, locationInfo)
end

function BankMixin:ADDON_LOADED(name)
	-- if name == "" then
	-- 	self.frame:RegisterEvent ""
	-- end
end

CaerdonWardrobe:RegisterFeature("Bank", BankMixin)
