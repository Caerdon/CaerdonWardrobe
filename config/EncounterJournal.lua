CaerdonWardrobeConfigEncounterJournalMixin = CreateFromMixins(CaerdonWardrobeConfigPanelMixin)

local ADDON_NAME, NS = ...
local L = NS.L

CAERDON_ENCOUNTERJOURNAL_LABEL = L["Encounter Journal"]
CAERDON_ENCOUNTERJOURNAL_SUBTEXT = L["These are settings that apply to the Encounter Journal."]

function CaerdonWardrobeConfigEncounterJournalMixin:OnLoad()
    self.name = "Encounter Journal"
    self.parent = "Caerdon Wardrobe"
	self.options = {
        -- TODO: Option was around, but it wasn't actually used so disabling panel for now
        -- showLearnableByOther = { text = "Show items learnable for a different toon", tooltip = "Highlights items that can be learned and used for transmog but not by your current toon.", default = NS:GetDefaultConfig().Icon.ShowLearnableByOther.EncounterJournal and "1" or "0" },
	}

	-- InterfaceOptionsPanel_OnLoad(self);
end
