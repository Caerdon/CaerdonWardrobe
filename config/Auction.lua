CaerdonWardrobeConfigAuctionMixin = CreateFromMixins(CaerdonWardrobeConfigPanelMixin)

local ADDON_NAME, NS = ...
local L = NS.L

CAERDON_AUCTION_LABEL = L["Auction"]
CAERDON_AUCTION_SUBTEXT = L["These are settings that apply to the auction house."]

function CaerdonWardrobeConfigAuctionMixin:OnLoad()
    self.name = "Auction"
    self.parent = "Caerdon Wardrobe"
	self.options = {
        showLearnable = { text = "Show items learnable for current toon", tooltip = "Highlights items that can be learned and used for transmog by your current toon.", default = NS:GetDefaultConfig().Icon.ShowLearnable.Auction and "1" or "0" },
        showLearnableByOther = { text = "Show items learnable for a different toon", tooltip = "Highlights items that can be learned and used for transmog but not by your current toon.", default = NS:GetDefaultConfig().Icon.ShowLearnableByOther.Auction and "1" or "0" },
        showOldExpansion = { text = "Show old expansion icon", tooltip = "Highlights items from older expansions based on your General config.", default = NS:GetDefaultConfig().Icon.ShowOldExpansion.Auction and "1" or "0" },
	}

	InterfaceOptionsPanel_OnLoad(self);
end
