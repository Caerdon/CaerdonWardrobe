CaerdonWardrobeConfigMerchantMixin = CreateFromMixins(CaerdonWardrobeConfigPanelMixin)

local ADDON_NAME, NS = ...
local L = NS.L

function CaerdonWardrobeConfigMerchantMixin:GetTitle()
    return "Merchant"
end

function CaerdonWardrobeConfigMerchantMixin:Register()
    self:Init()

    self.options = {
        showLearnable = { key = "merchantShowLearnable", text = "Show items learnable for current toon", tooltip = "Highlights items that can be learned and used for transmog by your current toon.", configSection="Icon", configSubsection="ShowLearnable", configValue="Merchant" },
        showLearnableByOther = { key = "merchantShowLearnableByOther", text = "Show items learnable for a different toon", tooltip = "Highlights items that can be learned and used for transmog but not by your current toon.", configSection="Icon", configSubsection="ShowLearnableByOther", configValue="Merchant" },
        showBindingText = { key = "merchantShowBindingText", text = "Show binding text", tooltip = "Show binding text on items based on General configuration.", configSection="Binding", configSubsection="ShowStatus", configValue="Merchant" },
	}

    self:ConfigureSection(self:GetTitle(), "MerchantSection")

    self:ConfigureCheckboxNew(self.options["showLearnable"])
    self:ConfigureCheckboxNew(self.options["showLearnableByOther"])
    self:ConfigureCheckboxNew(self.options["showBindingText"])
end

SettingsRegistrar:AddRegistrant(function () CaerdonWardrobeConfigMerchantMixin:Register() end)