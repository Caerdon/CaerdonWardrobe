CaerdonWardrobeConfigGeneralMixin = {}

local ADDON_NAME, NS = ...
local L = NS.L
local components, pendingConfig

CAERDON_GENERAL_LABEL = L["General"]
CAERDON_GENERAL_SUBTEXT = L["These are general settings that apply broadly to Caerdon Wardrobe."]

CAERDON_GENERAL_ICON_CONFIG = L["Icon Configuration"]
CAERDON_GENERAL_ICON_CONFIG_POSITION = L["Icon Position:"]

function CaerdonWardrobeConfigGeneralMixin:UpdatePendingValues()
	local config = pendingConfig

	-- config.Debug.Enabled = components.enableDebug:GetChecked()
	-- config.Icon.EnableAnimation = components.mogIconShowAnimation:GetChecked()
	-- config.ShowBoA = components.showBoA:GetChecked()
	-- config.ShowBoE = components.showBoE:GetChecked()
end

function CaerdonWardrobeConfigGeneralMixin:OnLoad()
    self.name = "General"
    self.parent = "Caerdon Wardrobe"
	self.options = {
        enableDebug = { text = "Enable Debug", tooltip = "Enables debugging info in tooltips", default = NS:GetDefaultConfig().Debug.Enabled and "1" or "0" },
        enableIconAnimation = { text = "Show Icon Animation", tooltip = "Turns icon animation on / off (largely in unlearned and openable items)", default = NS:GetDefaultConfig().Icon.EnableAnimation and "1" or "0" },
        iconPosition = { text = "Select Icon Position", tooltip = "Configures placement of the primary collectible icon", default = "TOPLEFT" }
	}

	InterfaceOptionsPanel_OnLoad(self);
end

function CaerdonWardrobeConfigGeneralMixin:ConfigureCheckbox(checkbox, label, configSection, configSubsection, configValue)
    checkbox.type = CONTROLTYPE_CHECKBOX;
    checkbox.label = label;

    checkbox.GetValue = function (self)
        local section = configSection and configSubsection and CaerdonWardrobeConfig[configSection][configSubsection] or configSection and CaerdonWardrobeConfig[configSection]
        return self.value or section[configValue] and "1" or "0";
    end
    checkbox.setFunc = function (value)
        local section = configSection and configSubsection and CaerdonWardrobeConfig[configSection][configSubsection] or configSection and CaerdonWardrobeConfig[configSection]
        section[configValue] = value == "1"
    end

    BlizzardOptionsPanel_RegisterControl(checkbox, self);
end

function CaerdonWardrobeConfigGeneralMixin:ConfigureDropdown(dropdown, label, configSection, configSubsection, configValue)
    dropdown:SetScript("OnEvent", function (self, event, ...)
        if ( event == "PLAYER_ENTERING_WORLD" ) then
            self:GetParent():InitializeDropdown(dropdown, label, configSection, configSubsection, configValue)
            self:UnregisterEvent(event)
        end
    end)
    dropdown:RegisterEvent("PLAYER_ENTERING_WORLD");
end

function CaerdonWardrobeConfigGeneralMixin:InitializeDropdown(dropdown, label, configSection, configSubsection, configValue)
    dropdown.type = CONTROLTYPE_DROPDOWN;
    dropdown.label = label

    dropdown.defaultValue = self.options[label].default
    local section = configSection and configSubsection and CaerdonWardrobeConfig[configSection][configSubsection] or configSection and CaerdonWardrobeConfig[configSection]
    dropdown.value = section[configValue] or dropdown.defaultValue;

    dropdown.SetValue =
        function (self, value)
            self.value = value
            section[configValue] = value
    end

    dropdown.GetValue =
        function (self)
            return self.newValue or self.value;
        end

    dropdown.RefreshValue =
        function (self)
            UIDropDownMenu_SetSelectedValue(self, self.value);
            UIDropDownMenu_Initialize(self, self:GetParent().AddSelections);
        end

    BlizzardOptionsPanel_RegisterControl(dropdown, self);

    UIDropDownMenu_SetWidth(dropdown, 136);
    UIDropDownMenu_SetSelectedValue(dropdown, dropdown.value);
    UIDropDownMenu_Initialize(dropdown, self.AddSelections);
end

function CaerdonWardrobeConfigGeneralMixin:AddSelections()
	self:GetParent():AddDropDownItem(self, "Top Left", "TOPLEFT", "Show the primary icon in the top left")
	self:GetParent():AddDropDownItem(self, "Top Right", "TOPRIGHT", "Show the primary icon in the top right")
	self:GetParent():AddDropDownItem(self, "Bottom Left", "BOTTOMLEFT", "Show the primary icon in the bottom left")
	self:GetParent():AddDropDownItem(self, "Bottom Right", "BOTTOMRIGHT", "Show the primary icon in the bottom right")
end

function CaerdonWardrobeConfigGeneralMixin:AddDropDownItem(dropdown, name, value, tooltip)
	local selectedValue = UIDropDownMenu_GetSelectedValue(dropdown);

    local info = UIDropDownMenu_CreateInfo()
	info.text = name
	info.value = value
    info.func = self.OnClickDropDownItem
    info.arg1 = dropdown;
	info.tooltipText = tooltip;
    if ( info.value == selectedValue ) then
		info.checked = 1;
	else
		info.checked = nil;
	end

	UIDropDownMenu_AddButton(info)

    if info.checked then
        dropdown.tooltipText = info.tooltipText
    	UIDropDownMenu_SetSelectedValue(dropdown, info.value)
    end
end

function CaerdonWardrobeConfigGeneralMixin:OnClickDropDownItem(dropdown)
    UIDropDownMenu_SetSelectedValue(dropdown, self.value);
    dropdown.newValue = self.value
end
