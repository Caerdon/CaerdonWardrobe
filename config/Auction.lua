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
        showAuctionValue = { key = "showAuctionValue", text = "Show auction icon on sellable items and trade goods worth listing (needs Auctionator)", tooltip = "Shows an auction icon in place of the sellable icon, and on trade goods with no other icon, when Auctionator's price, after the auction house cut and a deposit allowance, beats the vendor price by enough to be worth the trip. Stackable goods are judged on everything you own. Learnable, upgrade and quest icons always come first.", configSection = "Icon", configValue = "ShowAuctionValue" },
        auctionMinProfit = { key = "auctionMinProfit", text = "Minimum Profit", tooltip = "The least an auction has to earn over vendoring before the auction icon shows.", configSection = "Icon", configValue = "AuctionMinProfit", width = 190 },
	}

    self:ConfigureSection(self:GetTitle(), "AuctionSection")

    self:ConfigureCheckboxNew(self.options["showLearnable"])
    self:ConfigureCheckboxNew(self.options["showLearnableByOther"])
    self:ConfigureCheckboxNew(self.options["showOldExpansion"])

    -- These decide an icon in the bags and bank, not in the auction house window, but this is
    -- where someone looks for anything about auctions.
    self:ConfigureSection("Auction Value (Bags and Bank)", "AuctionValueSection")

    self:ConfigureCheckboxNew(self.options["showAuctionValue"])
    self:ConfigureDropdownNew(self.options["auctionMinProfit"], {
        { title = "Automatic (25c per level)", value = "auto",  tooltip = "Scales with your level: 2s 50c at level 10, 15s at level 60." },
        { title = "1 silver",                  value = "100",   tooltip = "List anything that clears 1 silver over vendoring." },
        { title = "5 silver",                  value = "500",   tooltip = "Require 5 silver over vendoring." },
        { title = "10 silver",                 value = "1000",  tooltip = "Require 10 silver over vendoring." },
        { title = "50 silver",                 value = "5000",  tooltip = "Require 50 silver over vendoring." },
        { title = "1 gold",                    value = "10000", tooltip = "Require 1 gold over vendoring." },
        { title = "5 gold",                    value = "50000", tooltip = "Require 5 gold over vendoring." }
    })
end

SettingsRegistrar:AddRegistrant(function () CaerdonWardrobeConfigAuctionMixin:Register() end)