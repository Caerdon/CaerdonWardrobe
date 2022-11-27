CaerdonWardrobeConfigPanelMixin = {}

local ADDON_NAME, NS = ...
local L = NS.L

local DEPENDS_ADJUSTMENT = 16
local LINE_HEIGHT = 36

function CaerdonWardrobeConfigPanelMixin:GetTitle()
    error("GetTitle not implemented")
end

function CaerdonWardrobeConfigPanelMixin:Init()
    self.nextPoint = -16
    self.parent = "Caerdon Wardrobe"

    -- TODO: Review using VerticalLayoutFrame: https://discord.com/channels/168296152670797824/218957301111848962/1021406980029550642

    local frame = CreateFrame("Frame")
    -- self.scrollChild = CreateFrame("Frame")
    self.scrollChild = frame

    local category = Settings.GetCategory(self.parent);
    local subcategory, layout = Settings.RegisterCanvasLayoutSubcategory(category, frame, self:GetTitle());

    -- local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate");
    -- local scrollFrame = CreateFrame("ScrollFrame", "CaerdonConfigGeneralFrame", frame, "UIPanelScrollFrameTemplate2")
    -- scrollFrame:SetPoint("TOPLEFT", 8, -4)
    -- scrollFrame:SetPoint("BOTTOMRIGHT", -27, 4)
    -- scrollFrame:SetScrollChild(scrollChild)
    -- scrollChild:SetPoint("LEFT", 0)
    -- scrollChild:SetPoint("RIGHT", 0)
    -- scrollChild:SetHeight(1) 
   
end

function CaerdonWardrobeConfigPanelMixin:ConfigureSection(title, key)
    local frame = self.scrollChild

    local sectionFrame = CreateFrame("Frame", "CaerdonWardrobe" .. key, frame)
    sectionFrame.key = key
    local titleString = sectionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleString:SetText(title)
	sectionFrame:SetPoint("LEFT", 16)
    sectionFrame:SetPoint("TOP", 0, self.nextPoint)
	titleString:SetPoint("LEFT", 16)
    titleString:SetPoint("TOP", 0, 0)
    self.nextPoint = self.nextPoint - LINE_HEIGHT
end

function CaerdonWardrobeConfigPanelMixin:ConfigureCheckboxNew(info)
    local frame = self.scrollChild

    local section = info.configSection and info.configSubsection and CaerdonWardrobeConfig[info.configSection][info.configSubsection] or info.configSection and CaerdonWardrobeConfig[info.configSection]
    local defaultSection = info.configSection and info.configSubsection and NS:GetDefaultConfig()[info.configSection][info.configSubsection] or info.configSection and NS:GetDefaultConfig()[info.configSection]

    local checkbox = CreateFrame("CheckButton", "CaerdonWardrobe" .. info.key, frame, "InterfaceOptionsCheckButtonTemplate")
    checkbox.key = info.key

    local dependsOn = nil
    if info.dependsOn then
        dependsOn = _G["CaerdonWardrobe" .. info.dependsOn]
    end

    if dependsOn then
        checkbox:SetPoint("LEFT", dependsOn, "LEFT", 16, 0)
        self.nextPoint = self.nextPoint + DEPENDS_ADJUSTMENT
        checkbox:SetPoint("TOP", 0, self.nextPoint)
        self.nextPoint = self.nextPoint - LINE_HEIGHT
    else
        checkbox:SetPoint("LEFT", 16)
        checkbox:SetPoint("TOP", 0, self.nextPoint)
        self.nextPoint = self.nextPoint - LINE_HEIGHT
    end

    checkbox:SetScript("OnClick", function(checkbox)
        local checked = checkbox:GetChecked()
        section[info.configValue] = checked

        if checked then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        else
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        end
    end)
    checkbox.label = _G[checkbox:GetName() .. "Text"]
    checkbox.label:SetText(info.text)

    local isChecked = section[info.configValue]
    if isChecked == nil then
        isChecked = defaultSection[info.configValue]
    end

    checkbox:SetChecked(isChecked)
end

function CaerdonWardrobeConfigPanelMixin:ConfigureDropdownNew(info, dropdownValues)
    local frame = self.scrollChild

    local section = info.configSection and info.configSubsection and CaerdonWardrobeConfig[info.configSection][info.configSubsection] or info.configSection and CaerdonWardrobeConfig[info.configSection]
    local defaultSection = info.configSection and info.configSubsection and NS:GetDefaultConfig()[info.configSection][info.configSubsection] or info.configSection and NS:GetDefaultConfig()[info.configSection]

	local dropdown = CreateFrame("Frame", "CaerdonWardrobe" .. info.key, frame, "UIDropDownMenuTemplate")
    dropdown.key = info.key

    local label = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", 5, 12)
	label:SetJustifyH("LEFT")
	label:SetText(info.text)

    local dependsOn = nil
    if info.dependsOn then
        dependsOn = _G["CaerdonWardrobe" .. info.dependsOn]
    end

    if dependsOn then
        dropdown:SetPoint("LEFT", dependsOn, "LEFT", 16, 0)
        self.nextPoint = self.nextPoint - 16 + DEPENDS_ADJUSTMENT
        checkbox:SetPoint("TOP", 0, self.nextPoint)
        self.nextPoint = self.nextPoint - LINE_HEIGHT
    else
        dropdown:SetPoint("LEFT", 16)
        self.nextPoint = self.nextPoint - 16
        dropdown:SetPoint("TOP", 0, self.nextPoint)
        self.nextPoint = self.nextPoint - LINE_HEIGHT
    end

    local selectedTitle = nil
    local text =  _G[dropdown:GetName() .. "Text"]
    text:SetText(info.text)

    for _, dropdownValue in ipairs(dropdownValues) do
        if dropdownValue.value == section[info.configValue] then
            text:SetText(dropdownValue.title)
        end
    end

    dropdown.initialize = function(dropdown)
        local dropdownInfo = {}
		for _, dropdownValue in ipairs(dropdownValues) do
			dropdownInfo.text = dropdownValue.title
			dropdownInfo.value = dropdownValue.value
            dropdownInfo.checked = function() return dropdownValue.value == section[info.configValue] end

            dropdownInfo.func = function(dropdown)
                section[info.configValue] = dropdown.value
				text:SetText(dropdown:GetText())
			end
			UIDropDownMenu_AddButton(dropdownInfo)
		end
	end
end

function CaerdonWardrobeConfigPanelMixin:ConfigureCheckbox(checkbox, label, configSection, configSubsection, configValue)
    checkbox.type = CONTROLTYPE_CHECKBOX;

    checkbox.label = _G[checkbox:GetName() .. "Text"]
    if checkbox.label then
        checkbox.label:SetText(label)
    end
    -- checkbox.Text:SetText(label)
    -- checkbox.Text:SetWidth(230)

    -- check.tooltipText = label
    -- check.tooltipRequirement = description

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

    -- BlizzardOptionsPanel_RegisterControl(checkbox, self);
    if dependsOnControl then
        -- BlizzardOptionsPanel_SetupDependentControl(dependsOnControl, checkbox)
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

    -- BlizzardOptionsPanel_RegisterControl(dropdown, self);

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
