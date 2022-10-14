CaerdonWardrobeConfigEncounterJournalMixin = CreateFromMixins(CaerdonWardrobeConfigPanelMixin)

local ADDON_NAME, NS = ...
local L = NS.L

function CaerdonWardrobeConfigEncounterJournalMixin:GetTitle()
    return "Encounter Journal"
end

function CaerdonWardrobeConfigEncounterJournalMixin:Register()
    self:Init()

    -- TODO: These aren't implemented right now.
    -- self.options = {
    --     showLearnable = { key = "showLearnable", text = "Show items learnable for current toon", tooltip = "Highlights items that can be learned and used for transmog by your current toon.", configSection="Icon", configSubsection="ShowLearnable", configValue="EncounterJournal" },
    --     showLearnableByOther = { key = "showLearnableByOther", text = "Show items learnable for a different toon", tooltip = "Highlights items that can be learned and used for transmog but not by your current toon.", configSection="Icon", configSubsection="ShowLearnableByOther", configValue="EncounterJournal" },
    --     showBindingText = { key = "showBindingText", text = "Show binding text", tooltip = "Show binding text on items based on General configuration.", configSection="Binding", configSubsection="ShowStatus", configValue="EncounterJournal" },
	-- }

    -- self:ConfigureSection(self:GetTitle(), "EncounterJournalSection")

    -- self:ConfigureCheckboxNew(self.options["showLearnable"])
    -- self:ConfigureCheckboxNew(self.options["showLearnableByOther"])
    -- self:ConfigureCheckboxNew(self.options["showBindingText"])
end

-- SettingsRegistrar:AddRegistrant(function () CaerdonWardrobeConfigBankAndBagsMixin:Register() end)