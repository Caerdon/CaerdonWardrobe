CaerdonWardrobeConfigBankAndBagsMixin = CreateFromMixins(CaerdonWardrobeConfigPanelMixin)

local ADDON_NAME, NS = ...
local L = NS.L

CAERDON_BANKANDBAGS_LABEL = L["Bank & Bags"]
CAERDON_BANKANDBAGS_SUBTEXT = L["These are settings that apply to your bank and bags."]

function CaerdonWardrobeConfigBankAndBagsMixin:OnLoad()
    self.name = "Bank & Bags"
    self.parent = "Caerdon Wardrobe"
	self.options = {
        showLearnable = { text = "Show items learnable for current toon", tooltip = "Highlights items that can be learned and used for transmog by your current toon.", default = NS:GetDefaultConfig().Icon.ShowLearnable.BankAndBags and "1" or "0" },
        showLearnableByOther = { text = "Show items learnable for a different toon", tooltip = "Highlights items that can be learned and used for transmog but not by your current toon.", default = NS:GetDefaultConfig().Icon.ShowLearnableByOther.BankAndBags and "1" or "0" },
        showSellable = { text = "Show items that can probably be sold", tooltip = "Highlights items that are bound to you but not usable and can probably be sold.", default = NS:GetDefaultConfig().Icon.ShowSellable.BankAndBags and "1" or "0" },
        showBindingText = { text = "Show binding text", tooltip = "Show binding text on items based on General configuration.", default = NS:GetDefaultConfig().Binding.ShowStatus.BankAndBags and "1" or "0" },
	}

	InterfaceOptionsPanel_OnLoad(self);
end
