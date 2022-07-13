CaerdonWardrobeConfigGuildBankMixin = CreateFromMixins(CaerdonWardrobeConfigPanelMixin)

local ADDON_NAME, NS = ...
local L = NS.L

CAERDON_GUILDBANK_LABEL = L["Guild Bank"]
CAERDON_GUILDBANK_SUBTEXT = L["These are settings that apply to your guild bank."]

function CaerdonWardrobeConfigGuildBankMixin:OnLoad()
    self.name = "Guild Bank"
    self.parent = "Caerdon Wardrobe"
	self.options = {
        showLearnable = { text = "Show items learnable for current toon", tooltip = "Highlights items that can be learned and used for transmog by your current toon.", default = NS:GetDefaultConfig().Icon.ShowLearnable.GuildBank and "1" or "0" },
        showLearnableByOther = { text = "Show items learnable for a different toon", tooltip = "Highlights items that can be learned and used for transmog but not by your current toon.", default = NS:GetDefaultConfig().Icon.ShowLearnableByOther.GuildBank and "1" or "0" },
        showSellable = { text = "Show items that can probably be sold", tooltip = "Highlights items that are bound to you but not usable and can probably be sold.", default = NS:GetDefaultConfig().Icon.ShowSellable.GuildBank and "1" or "0" },
        showBindingText = { text = "Show binding text", tooltip = "Show binding text on items based on General configuration.", default = NS:GetDefaultConfig().Binding.ShowStatus.GuildBank and "1" or "0" },
	}

	InterfaceOptionsPanel_OnLoad(self);
end
