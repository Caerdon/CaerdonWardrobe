CaerdonWardrobeConfigMerchantMixin = CreateFromMixins(CaerdonWardrobeConfigPanelMixin)

local ADDON_NAME, NS = ...
local L = NS.L

CAERDON_MERCHANT_LABEL = L["Merchant"]
CAERDON_MERCHANT_SUBTEXT = L["These are settings that apply to vendors."]

function CaerdonWardrobeConfigMerchantMixin:OnLoad()
    self.name = "Merchant"
    self.parent = "Caerdon Wardrobe"
	self.options = {
        showLearnable = { text = "Show items learnable for current toon", tooltip = "Highlights items that can be learned and used for transmog by your current toon.", default = NS:GetDefaultConfig().Icon.ShowLearnable.Merchant and "1" or "0" },
        showLearnableByOther = { text = "Show items learnable for a different toon", tooltip = "Highlights items that can be learned and used for transmog but not by your current toon.", default = NS:GetDefaultConfig().Icon.ShowLearnableByOther.Merchant and "1" or "0" },
        showBindingText = { text = "Show binding text", tooltip = "Show binding text on items based on General configuration.", default = NS:GetDefaultConfig().Binding.ShowStatus.Merchant and "1" or "0" },
	}

	InterfaceOptionsPanel_OnLoad(self);
end
