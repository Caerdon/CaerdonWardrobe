CaerdonWardrobeConfigAuctionMixin = CreateFromMixins(CaerdonWardrobeConfigPanelMixin)

local ADDON_NAME, NS = ...
local L = NS.L

function CaerdonWardrobeConfigAuctionMixin:OnLoad()
    self.name = "Auction"
    self.parent = "Caerdon Wardrobe"
	self.options = {
        showLearnable = { text = "Show items learnable for current toon", tooltip = "Highlights items that can be learned and used for transmog by your current toon.", default = NS:GetDefaultConfig().Icon.ShowLearnable.Auction and "1" or "0" },
        showLearnableByOther = { text = "Show items learnable for a different toon", tooltip = "Highlights items that can be learned and used for transmog but not by your current toon.", default = NS:GetDefaultConfig().Icon.ShowLearnableByOther.Auction and "1" or "0" },
	}

	InterfaceOptionsPanel_OnLoad(self);
end

function CaerdonWardrobeConfigAuctionMixin:GetTitle()
    return "Auction"
end

function CaerdonWardrobeConfigAuctionMixin:Register()
    self:Init()

    self.options = {
        showLearnable = { key = "auctionShowLearnable", text = "Show items learnable for current toon", tooltip = "Highlights items that can be learned and used for transmog by your current toon.", configSection="Icon", configSubsection="ShowLearnable", configValue="Auction" },
        showLearnableByOther = { key = "auctionShowLearnableByOther", text = "Show items learnable for a different toon", tooltip = "Highlights items that can be learned and used for transmog but not by your current toon.", configSection="Icon", configSubsection="ShowLearnableByOther", configValue="Auction" },
        showOldExpansion = { key = "showOldExpansion", text = "Show old expansion icon", tooltip = "Highlights items from older expansions based on your General config.", configSection="Icon", configSubsection="ShowOldExpansion", configValue="Auction" },
	}

    self:ConfigureSection(self:GetTitle(), "AuctionSection")

    self:ConfigureCheckboxNew(self.options["showLearnable"])
    self:ConfigureCheckboxNew(self.options["showLearnableByOther"])
    self:ConfigureCheckboxNew(self.options["showOldExpansion"])
end

SettingsRegistrar:AddRegistrant(function () CaerdonWardrobeConfigAuctionMixin:Register() end)