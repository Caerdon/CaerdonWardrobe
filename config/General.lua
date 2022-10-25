local CaerdonWardrobeConfigGeneral = CreateFromMixins(CaerdonWardrobeConfigPanelMixin)

local ADDON_NAME, NS = ...
local L = NS.L

function CaerdonWardrobeConfigGeneral:GetTitle()
    return "General"
end

function CaerdonWardrobeConfigGeneral:Register()
    self:Init()

	self.options = {
        enableDebug = { key = "enableDebug", text = "Enable Debug", tooltip = "Enables debugging info in tooltips", configSection="Debug", configSubsection=nil, configValue="Enabled" },
        enableIconAnimation = { key = "enableIconAnimation", text = "Show Icon Animation", tooltip = "Turns icon animation on / off (largely in unlearned and openable items)", configSection="Icon", configValue="EnableAnimation"},
        iconPosition = { key = "iconPosition", text = "Select Icon Position", tooltip = "Configures placement of the primary collectible icon", configSection="Icon", configValue="Position"},
        sameLookDifferentItem = { key = "sameLookDifferentItem", text = "Include different items w/ the same look (you completionist, you)", tooltip = "Ensures that you learn every single item that provides the same exact appearance for no other reason than you know you don't have that one.",  configSection="Icon", configSubsection="ShowLearnable", configValue="SameLookDifferentItem"},
        sameLookDifferentLevel = { key = "sameLookDifferentLevel", text = "Including identical items w/ lower levels", tooltip = "Enable this to ensure that an item will show as learnable if the item's level would allow a lower level toon to use it for transmog than the one you already know.", configSection="Icon", configSubsection="ShowLearnable", configValue="SameLookDifferentLevel", dependsOn="sameLookDifferentItem"},
        showOldExpansionReagents = { key = "showOldExpansionReagents", text = "Reagents", tooltip = "Add an icon to reagents from older expansions", configSection="Icon", configSubsection="ShowOldExpansion", configValue="Reagents", dependsOn="OldExpansionSection"},
        showOldExpansionUsable = { key = "showOldExpansionUsable", text = "Usable Items", tooltip = "Add an icon to usable items from older expansions", configSection="Icon", configSubsection="ShowOldExpansion", configValue="Usable", dependsOn="OldExpansionSection"},
        showOldExpansionOther = { key = "showOldExpansionOther", text = "Other Items", tooltip = "Add an icon to any other items from older expansions", configSection="Icon", configSubsection="ShowOldExpansion", configValue="Other", dependsOn="OldExpansionSection"},
        showOldExpansionUnknown = { key = "showOldExpansionUnknown", text = "Unknown Expansion", tooltip = "Add an icon to items that didn't indicate what expansion they were from.  This happens more often than I'd like to see, and it's probably not a super useful option (other than maybe for WoW devs that need to fix this.)", configSection="Icon", configSubsection="ShowOldExpansion", configValue="Unknown", dependsOn="OldExpansionSection"},
        showQuestItems = { key = "showQuestItems", text = "Show Quest Items", tooltip = "Adds an icon to any items that are tied to a quest", configSection="Icon", configValue="ShowQuestItems"},
        showGearSetsAsIcon = { key = "showGearSetsAsIcon", text = "Show Gear Set Icon", tooltip = "Show an icon on items associated with a gear set", configSection="Binding", configValue="ShowGearSetsAsIcon"},
        showBoA = { key = "showBoA", text = "Show Bind on Account", tooltip = "Shows BoA on items that are bind on account", configSection="Binding", configValue="ShowBoA"},
        showBoE = { key = "showBoE", text = "Show Bind on Equip", tooltip = "Shows BoE on items that are bind on equip", configSection="Binding", configValue="ShowBoE"},
        showGearSets = { key = "showGearSets", text = "Show Gear Sets", tooltip = "Shows gear set text on items associated with a gear set", configSection="Binding", configValue="ShowGearSets"},
        bindingPosition = { key = "bindingPosition", text = "Select Binding Position", tooltip = "Configures placement of the binding text", configSection="Binding", configValue="Position"},
	}

    self:ConfigureSection(self:GetTitle(), "GeneralSection")

    self:ConfigureCheckboxNew(self.options["enableDebug"])
    self:ConfigureCheckboxNew(self.options["enableIconAnimation"])
    self:ConfigureDropdownNew(self.options["iconPosition"], { 
        { title = "Top Left", value = "TOPLEFT", tooltip = "Show the primary icon in the top left" },
        { title = "Top Right", value = "TOPRIGHT", tooltip = "Show the primary icon in the top right" },
        { title = "Bottom Left", value = "BOTTOMLEFT", tooltip = "Show the primary icon in the bottom left" },
        { title = "Bottom Right", value = "BOTTOMRIGHT", tooltip = "Show the primary icon in the bottom right" }
    })
    self:ConfigureCheckboxNew(self.options["sameLookDifferentItem"])
    self:ConfigureCheckboxNew(self.options["sameLookDifferentLevel"])

    self:ConfigureSection(L["Show Old Expansion Items"], "OldExpansionSection")
    self:ConfigureCheckboxNew(self.options["showOldExpansionReagents"])
    self:ConfigureCheckboxNew(self.options["showOldExpansionUsable"])
    self:ConfigureCheckboxNew(self.options["showOldExpansionOther"])
    self:ConfigureCheckboxNew(self.options["showOldExpansionUnknown"])
    self:ConfigureCheckboxNew(self.options["showQuestItems"])
    self:ConfigureCheckboxNew(self.options["showGearSetsAsIcon"])
    self:ConfigureCheckboxNew(self.options["showBoA"])
    self:ConfigureCheckboxNew(self.options["showBoE"])
    self:ConfigureCheckboxNew(self.options["showGearSets"])
    self:ConfigureDropdownNew(self.options["bindingPosition"], { 
        { title = "Top", value = "TOP", tooltip = "Show the binding text on the top of the item" },
        { title = "Center", value = "CENTER", tooltip = "Show the binding text on the center of the item" },
        { title = "Bottom", value = "BOTTOM", tooltip = "Show the binding text on the bottom of the item" }
    })

    -- local footer = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- footer:SetPoint("TOP", 0, -5000)
    -- footer:SetText("This is 5000 below the top, so the scrollChild automatically expanded.")
    
end

SettingsRegistrar:AddRegistrant(function () CaerdonWardrobeConfigGeneral:Register() end)