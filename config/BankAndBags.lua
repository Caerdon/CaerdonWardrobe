CaerdonWardrobeConfigBankAndBagsMixin = CreateFromMixins(CaerdonWardrobeConfigPanelMixin)

local ADDON_NAME, NS = ...
local L = NS.L

function CaerdonWardrobeConfigBankAndBagsMixin:GetTitle()
    return "Bank & Bags"
end

function CaerdonWardrobeConfigBankAndBagsMixin:Register()
    self:Init()

    self.options = {
        showLearnable = { key = "showLearnable", text = "Show items learnable for current toon", tooltip = "Highlights items that can be learned and used for transmog by your current toon.", configSection="Icon", configSubsection="ShowLearnable", configValue="BankAndBags" },
        showLearnableByOther = { key = "showLearnableByOther", text = "Show items learnable for a different toon", tooltip = "Highlights items that can be learned and used for transmog but not by your current toon.", configSection="Icon", configSubsection="ShowLearnableByOther", configValue="BankAndBags" },
        showSellable = { key = "showSellable", text = "Show items that can probably be sold", tooltip = "Highlights items that are bound to you but not usable and can probably be sold.", configSection="Icon", configSubsection="ShowSellable", configValue="BankAndBags" },
        showBindingText = { key = "showBindingText", text = "Show binding text", tooltip = "Show binding text on items based on General configuration.", configSection="Binding", configSubsection="ShowStatus", configValue="BankAndBags" },
        shownPawnUpgrade = { key = "showPawnUpgrade", text = "Show if Pawn identifies as an upgrade", tooltip = "Show upgrade arrow on items (requires Pawn addon).", configSection="Icon", configSubsection="ShowUpgrades", configValue="BankAndBags" },
	}

    self:ConfigureSection(self:GetTitle(), "BankAndBagsSection")

    self:ConfigureCheckboxNew(self.options["showLearnable"])
    self:ConfigureCheckboxNew(self.options["showLearnableByOther"])
    self:ConfigureCheckboxNew(self.options["showSellable"])
    self:ConfigureCheckboxNew(self.options["showBindingText"])
    self:ConfigureCheckboxNew(self.options["shownPawnUpgrade"])
end

SettingsRegistrar:AddRegistrant(function () CaerdonWardrobeConfigBankAndBagsMixin:Register() end)