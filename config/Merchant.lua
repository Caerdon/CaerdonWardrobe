CaerdonWardrobeConfigMerchantMixin = CreateFromMixins(CaerdonWardrobeConfigPanelMixin)

local ADDON_NAME, NS = ...
local L = NS.L

-- Ensure config structure exists early (before settings panel registration)
if not CaerdonWardrobeConfig then
    CaerdonWardrobeConfig = {}
end
if not CaerdonWardrobeConfig.Merchant then
    CaerdonWardrobeConfig.Merchant = {}
end
if not CaerdonWardrobeConfig.Merchant.Filter then
    CaerdonWardrobeConfig.Merchant.Filter = {}
end

function CaerdonWardrobeConfigMerchantMixin:GetTitle()
    return "Merchant"
end

function CaerdonWardrobeConfigMerchantMixin:Register()
    self:Init()

    self.options = {
        showLearnable = { key = "merchantShowLearnable", text = "Show items learnable for current toon", tooltip = "Highlights items that can be learned and used for transmog by your current toon.", configSection = "Icon", configSubsection = "ShowLearnable", configValue = "Merchant" },
        showLearnableByOther = { key = "merchantShowLearnableByOther", text = "Show items learnable for a different toon", tooltip = "Highlights items that can be learned and used for transmog but not by your current toon.", configSection = "Icon", configSubsection = "ShowLearnableByOther", configValue = "Merchant" },
        showBindingText = { key = "merchantShowBindingText", text = "Show binding text", tooltip = "Show binding text on items based on General configuration.", configSection = "Binding", configSubsection = "ShowStatus", configValue = "Merchant" },
        hideCollectedItems = { key = "merchantHideCollectedItems", text = "Gray out collected/known items", tooltip = "Grays out and fades merchant items that you have already learned or collected.", configSection = "Merchant", configSubsection = "Filter", configValue = "HideCollected" },
        suppressLegionRemixHelperWarning = { key = "merchantSuppressLegionRemixHelperWarning", text = "Suppress Legion Remix Helper conflict warning", tooltip = "Don't show the warning about Legion Remix Helper's merchant filtering being enabled.", configSection = "Merchant", configSubsection = "Filter", configValue = "SuppressLegionRemixHelperWarning" },
    }

    self:ConfigureSection(self:GetTitle(), "MerchantSection")

    self:ConfigureCheckboxNew(self.options["showLearnable"])
    self:ConfigureCheckboxNew(self.options["showLearnableByOther"])
    self:ConfigureCheckboxNew(self.options["showBindingText"])
    self:ConfigureCheckboxNew(self.options["hideCollectedItems"])
    self:ConfigureCheckboxNew(self.options["suppressLegionRemixHelperWarning"])
end

SettingsRegistrar:AddRegistrant(function() CaerdonWardrobeConfigMerchantMixin:Register() end)
