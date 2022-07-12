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

	-- config.ShowBoA = components.showBoA:GetChecked()
	-- config.ShowBoE = components.showBoE:GetChecked()
end

function CaerdonWardrobeConfigGeneralMixin:OnLoad()
    self.name = "General"
    self.parent = "Caerdon Wardrobe"
	self.options = {
        enableDebug = { text = "Enable Debug", tooltip = "Enables debugging info in tooltips", default = NS:GetDefaultConfig().Debug.Enabled and "1" or "0" },
        enableIconAnimation = { text = "Show Icon Animation", tooltip = "Turns icon animation on / off (largely in unlearned and openable items)", default = NS:GetDefaultConfig().Icon.EnableAnimation and "1" or "0" },
        iconPosition = { text = "Select Icon Position", tooltip = "Configures placement of the primary collectible icon", default = "TOPLEFT" },
        sameLookDifferentItem = { text = "Include different items w/ the same look (you completionist, you)", tooltip = "Ensures that you learn every single item that provides the same exact appearance for no other reason than you know you don't have that one.", default = NS:GetDefaultConfig().Icon.ShowLearnable.SameLookDifferentItem and "1" or "0" },
        sameLookDifferentLevel = { text = "Including identical items w/ lower levels", tooltip = "Enable this to ensure that an item will show as learnable if the item's level would allow a lower level toon to use it for transmog than the one you already know.", default = NS:GetDefaultConfig().Icon.ShowLearnable.SameLookDifferentLevel and "1" or "0" }
	}

	InterfaceOptionsPanel_OnLoad(self);
end

function CaerdonWardrobeConfigGeneralMixin:ConfigureCheckbox(checkbox, label, configSection, configSubsection, configValue)
    checkbox.type = CONTROLTYPE_CHECKBOX;
    checkbox.label = label;
    checkbox.Text:SetWidth(230)

    local dependsOn, dependsOnControl
    if checkbox.dependentOn then
        dependsOn = checkbox.dependentOn:gsub( "$parent", checkbox:GetParent():GetName())
        dependsOnControl = _G[dependsOn]
    end

    checkbox.GetValue = function (self)
        local section = configSection and configSubsection and CaerdonWardrobeConfig[configSection][configSubsection] or configSection and CaerdonWardrobeConfig[configSection]
        return self.value or section[configValue] and "1" or "0";
    end
    checkbox.setFunc = function (value)
        local section = configSection and configSubsection and CaerdonWardrobeConfig[configSection][configSubsection] or configSection and CaerdonWardrobeConfig[configSection]
        section[configValue] = value == "1"
    end

    BlizzardOptionsPanel_RegisterControl(checkbox, self);
    if dependsOnControl then
        BlizzardOptionsPanel_SetupDependentControl(dependsOnControl, checkbox)
    end
end

function CaerdonWardrobeConfigGeneralMixin:ConfigureDropdown(dropdown, label, configSection, configSubsection, configValue, items)
    dropdown:SetScript("OnEvent", function (self, event, ...)
        if ( event == "PLAYER_ENTERING_WORLD" ) then
            self:GetParent():InitializeDropdown(dropdown, label, configSection, configSubsection, configValue, items)
            self:UnregisterEvent(event)
        end
    end)

    dropdown:SetScript("OnEnter", function (self)
        if ( not self.isDisabled ) then
            GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT");
            GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true);
        end
    end)

    dropdown:SetScript("OnLeave", function (self)
        if ( GameTooltip:GetOwner() == self ) then
            GameTooltip:Hide();
        end
    end)

    dropdown:RegisterEvent("PLAYER_ENTERING_WORLD");
end

function CaerdonWardrobeConfigGeneralMixin:InitializeDropdown(dropdown, label, configSection, configSubsection, configValue, items)
    dropdown.type = CONTROLTYPE_DROPDOWN;
    dropdown.label = label
    dropdown.items = items

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
            UIDropDownMenu_Initialize(self, function ()
                for itemIndex = 1, #self.items do
                    local item = self.items[itemIndex]
                    self:GetParent():AddDropDownItem(self, item.title, item.value, item.tooltip)
                end
            end);
        end

    BlizzardOptionsPanel_RegisterControl(dropdown, self);

    UIDropDownMenu_SetWidth(dropdown, 136);
    dropdown:RefreshValue()
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
