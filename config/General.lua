CaerdonWardrobeConfigGeneralMixin = {}

local ADDON_NAME, namespace = ...
local L = namespace.L

CAERDON_GENERAL_LABEL = L["General"]
CAERDON_GENERAL_SUBTEXT = L["These are general settings that apply broadly to Caerdon Wardrobe."]

function CaerdonWardrobeConfigGeneralMixin:OnLoad()
    self.name = "General"
    self.parent = "Caerdon Wardrobe"
	InterfaceOptions_AddCategory(self)
end