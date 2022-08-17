CaerdonWardrobeConfigPanelMixin = {}

local ADDON_NAME, NS = ...
local L = NS.L

function CaerdonWardrobeConfigPanelMixin:ConfigureCheckbox(checkbox, label, configSection, configSubsection, configValue)
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

function CaerdonWardrobeConfigPanelMixin:ConfigureDropdown(dropdown, label, configSection, configSubsection, configValue, items)
    dropdown:SetScript("OnEvent", function (self, event, ...)
        if ( event == "FIRST_FRAME_RENDERED" ) then
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

    dropdown:RegisterEvent("FIRST_FRAME_RENDERED");
end

function CaerdonWardrobeConfigPanelMixin:InitializeDropdown(dropdown, label, configSection, configSubsection, configValue, items)
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

function CaerdonWardrobeConfigPanelMixin:AddDropDownItem(dropdown, name, value, tooltip)
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

function CaerdonWardrobeConfigPanelMixin:OnClickDropDownItem(dropdown)
    UIDropDownMenu_SetSelectedValue(dropdown, self.value);
    dropdown.newValue = self.value
end
