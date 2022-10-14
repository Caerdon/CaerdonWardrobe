CaerdonWardrobeConfigGuildBankMixin = CreateFromMixins(CaerdonWardrobeConfigPanelMixin)

local ADDON_NAME, NS = ...
local L = NS.L

function CaerdonWardrobeConfigGuildBankMixin:GetTitle()
    return "Guild Bank"
end

function CaerdonWardrobeConfigGuildBankMixin:Register()
    self:Init()

    self.options = {
        showLearnable = { key = "guildShowLearnable", text = "Show items learnable for current toon", tooltip = "Highlights items that can be learned and used for transmog by your current toon.", configSection="Icon", configSubsection="ShowLearnable", configValue="GuildBank" },
        showLearnableByOther = { key = "guildShowLearnableByOther", text = "Show items learnable for a different toon", tooltip = "Highlights items that can be learned and used for transmog but not by your current toon.", configSection="Icon", configSubsection="ShowLearnableByOther", configValue="GuildBank" },
        showSellable = { key = "guildShowSellable", text = "Show items that can probably be sold", tooltip = "Highlights items that are bound to you but not usable and can probably be sold.", configSection="Icon", configSubsection="ShowSellable", configValue="GuildBank" },
        showBindingText = { key = "guildShowBindingText", text = "Show binding text", tooltip = "Show binding text on items based on General configuration.", configSection="Binding", configSubsection="ShowStatus", configValue="GuildBank" },
	}

    self:ConfigureSection(self:GetTitle(), "GuildBankSection")

    self:ConfigureCheckboxNew(self.options["showLearnable"])
    self:ConfigureCheckboxNew(self.options["showLearnableByOther"])
    self:ConfigureCheckboxNew(self.options["showSellable"])
    self:ConfigureCheckboxNew(self.options["showBindingText"])
end

SettingsRegistrar:AddRegistrant(function () CaerdonWardrobeConfigGuildBankMixin:Register() end)