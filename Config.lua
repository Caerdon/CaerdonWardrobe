local ADDON_NAME, NS = ...
local L = NS.L
local components, pendingConfig

local configFrame = CreateFrame("Frame", nil, InterfaceOptionsFramePanelContainer)

local function PropagateErrors(func)
	-- Make sure that errors aren't swallowed for InterfaceOption callbacks
	return function() xpcall(function () func(configFrame) end, geterrorhandler()) end
end

function configFrame:InitializeConfig()
	self:Hide()
	self:CreateComponents()
	NS:RegisterConfigFrame(self)
end

function configFrame:CreateComponents()
	components = {}
	components.title = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	components.title:SetText("Caerdon Wardrobe")
	components.title:SetPoint("TOPLEFT", 16, -16)

	components.titleSeparator = self:CreateTexture(nil, "ARTWORK")
	components.titleSeparator:SetColorTexture(0.25, 0.25, 0.25)
	components.titleSeparator:SetSize(600, 1)
	components.titleSeparator:SetPoint("LEFT", self, "TOPLEFT", 10, -40)

	components.showGearSets = CreateFrame("CheckButton", "CaerdonWardrobeConfig_ShowGearSets", self, "InterfaceOptionsCheckButtonTemplate")
	components.showGearSets:SetPoint("TOPLEFT", components.titleSeparator, "BOTTOMLEFT", 0, -5)
	components.showGearSetsLabel = _G[components.showGearSets:GetName() .. "Text"]
	components.showGearSetsLabel:SetText(L["Show Gear Sets"])

	components.mogIconPositionLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	components.mogIconPositionLabel:SetText(L["Icon Position:"])
	components.mogIconPositionLabel:SetPoint("TOPLEFT", components.showGearSets, "BOTTOMLEFT", 0, -15)
	components.mogIconPosition = CreateFrame("Button", "CaerdonWardrobeConfig_MogIconPosition", self, "UIDropDownMenuTemplate")
	components.mogIconPosition:SetPoint("TOPLEFT", components.mogIconPositionLabel, "TOPRIGHT", -9, 9)

	components.mogIconShowAnimation = CreateFrame("CheckButton", "CaerdonWardrobeConfig_MogIconShowAnimation", self, "InterfaceOptionsCheckButtonTemplate")
	components.mogIconShowAnimation:SetPoint("TOPLEFT", components.mogIconPositionLabel, "BOTTOMLEFT", 0, -15)
	components.mogIconShowAnimationLabel = _G[components.mogIconShowAnimation:GetName() .. "Text"]
	components.mogIconShowAnimationLabel:SetText(L["Show Icon Animation"])

end

function configFrame:InitializeMogIconPosition()
	self:AddDropDownItem("Top Left", "TOPLEFT")
	self:AddDropDownItem("Top Right", "TOPRIGHT")
	self:AddDropDownItem("Bottom Left", "BOTTOMLEFT")
	self:AddDropDownItem("Bottom Right", "BOTTOMRIGHT")

	UIDropDownMenu_SetSelectedValue(components.mogIconPosition, pendingConfig.Icon.Position)
end

function configFrame:AddDropDownItem(name, value)
	local info = UIDropDownMenu_CreateInfo()
	info.text = name
	info.value = value
	info.func = function(self, arg1, arg2, checked)
		UIDropDownMenu_SetSelectedValue(components.mogIconPosition, value)
		pendingConfig.Icon.Position = value
	end

	UIDropDownMenu_AddButton(info)
end

function configFrame:ApplyConfig(config)
	pendingConfig = CopyTable(config)
end

function configFrame:RefreshComponents()
	local config = pendingConfig

	components.showGearSets:SetChecked(config.ShowGearSets)
	UIDropDownMenu_Initialize(components.mogIconPosition, function() self:InitializeMogIconPosition() end)
	components.mogIconShowAnimation:SetChecked(config.Icon.EnableAnimation)
end

function configFrame:UpdatePendingValues()
	local config = pendingConfig

	config.ShowGearSets = components.showGearSets:GetChecked()
	config.Icon.Position = UIDropDownMenu_GetSelectedValue(components.mogIconPosition)
	config.Icon.EnableAnimation = components.mogIconShowAnimation:GetChecked()
end

function configFrame:OnConfigLoaded()
	self:ApplyConfig(CaerdonWardrobeConfig)

	self.name = "Caerdon Wardrobe"
	self.okay = PropagateErrors(self.OnSave)
	self.cancel = PropagateErrors(self.OnCancel)
	self.default = PropagateErrors(self.OnResetToDefaults)
	self.refresh = PropagateErrors(self.OnRefresh)

	InterfaceOptions_AddCategory(self)
end

function configFrame:OnSave()
	self:UpdatePendingValues()
	CaerdonWardrobeConfig = CopyTable(pendingConfig)
end

function configFrame:OnCancel()
	self:ApplyConfig(CaerdonWardrobeConfig)
end

function configFrame:OnResetToDefaults()
	self:ApplyConfig(NS:GetDefaultConfig())
end

function configFrame:OnRefresh()
	self:RefreshComponents()
end

configFrame:InitializeConfig()
