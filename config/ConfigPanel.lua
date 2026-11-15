CaerdonWardrobeConfigPanelMixin = {}

local ADDON_NAME, NS = ...
local L = NS.L

-- Layout, in pixels. The settings canvas is about 640 wide at the default panel size and the
-- pages are built before it has a size, so the widths are fixed.
local LEFT_MARGIN = 16
local ICON_SIZE = 24
local ICON_BODY_X = LEFT_MARGIN + ICON_SIZE + 10 -- where an icon block's text and options start
local SECTION_BODY_X = LEFT_MARGIN + 4
local CONTENT_RIGHT = 610
local INDENT_STEP = 20
local ROW_HEIGHT = 26
local DROPDOWN_ROW_HEIGHT = 34
local BLOCK_GAP = 16
local GRID_COLUMN_WIDTH = 185
local CHECKBOX_INSET = 4 -- the template's box art starts a few pixels inside its frame

local defaultConfig

-- The saved table can be replaced wholesale (old settings version) and can lack newer sections,
-- so every read and write resolves it again instead of holding on to a sub-table.
local function GetSection(root, info, create)
    if not (root and info.configSection) then
        return nil
    end
    local section = root[info.configSection]
    if section == nil and create then
        section = {}
        root[info.configSection] = section
    end
    if section and info.configSubsection then
        local subsection = section[info.configSubsection]
        if subsection == nil and create then
            subsection = {}
            section[info.configSubsection] = subsection
        end
        section = subsection
    end
    return section
end

local function GetValue(info)
    local section = GetSection(CaerdonWardrobeConfig, info)
    local value = section and section[info.configValue]
    if value == nil then
        defaultConfig = defaultConfig or NS:GetDefaultConfig()
        local defaults = GetSection(defaultConfig, info)
        value = defaults and defaults[info.configValue]
    end
    return value
end

local function SetValue(info, value)
    CaerdonWardrobeConfig = CaerdonWardrobeConfig or {}
    GetSection(CaerdonWardrobeConfig, info, true)[info.configValue] = value
end

local function ApplyTexture(texture, spec)
    if spec.atlas and texture.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(spec.atlas) then
        texture:SetAtlas(spec.atlas, false)
    else
        texture:SetTexture(spec.texture)
        if spec.coords then
            texture:SetTexCoord(unpack(spec.coords))
        end
    end
    if spec.color then
        texture:SetVertexColor(unpack(spec.color))
    end
end

local function ShowOptionTooltip(owner, title, text)
    if not text then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    GameTooltip:AddLine(text, nil, nil, nil, true)
    GameTooltip:Show()
end

local function HideOptionTooltip(owner)
    if GameTooltip:GetOwner() == owner then
        GameTooltip:Hide()
    end
end

function CaerdonWardrobeConfigPanelMixin:GetTitle()
    error("GetTitle not implemented")
end

function CaerdonWardrobeConfigPanelMixin:Init()
    self.nextPoint = -16
    self.parent = "Caerdon Wardrobe"
    self.controls = {}
    self.hasBlock = false
    self.bodyX = SECTION_BODY_X

    local frame = CreateFrame("Frame")
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT")
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetPoint("TOPLEFT")
    scrollChild:SetWidth(1)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    scrollFrame:HookScript("OnSizeChanged", function(_, width)
        scrollChild:SetWidth(width)
    end)
    scrollChild:SetWidth(scrollFrame:GetWidth())

    -- The controls are built once; what they show is read again every time the page opens.
    -- OnRefresh is what the settings window calls each time it displays a page. OnShow alone
    -- misses the first time: the frame starts out shown, so putting it on screen is not a "show".
    frame.OnRefresh = function()
        self:RefreshControls()
    end
    frame:SetScript("OnShow", function()
        self:RefreshControls()
    end)

    self.frame = frame
    self.scrollChild = scrollChild
    self.scrollFrame = scrollFrame

    local category = Settings.GetCategory(self.parent);
    local subcategory, layout = Settings.RegisterCanvasLayoutSubcategory(category, frame, self:GetTitle());
end

-- Call after the last control: gives the scroll child its real height and loads the values.
function CaerdonWardrobeConfigPanelMixin:FinishLayout()
    self.scrollChild:SetHeight(-self.nextPoint + 24)
    self:RefreshControls()
end

function CaerdonWardrobeConfigPanelMixin:RefreshControls()
    for _, control in ipairs(self.controls) do
        control.caerdonRefresh()
    end
    self:UpdateDependents()
end

-- A control with dependsOn is only usable while that checkbox is checked and usable itself.
-- Controls are kept in creation order, so a parent is always settled before its children.
function CaerdonWardrobeConfigPanelMixin:UpdateDependents()
    for _, control in ipairs(self.controls) do
        if control.caerdonDependsOn then
            control.caerdonSetEnabled(control.caerdonDependsOn.caerdonIsOn())
        end
    end
end

function CaerdonWardrobeConfigPanelMixin:RegisterControl(control)
    table.insert(self.controls, control)
    control.caerdonRefresh()
end

function CaerdonWardrobeConfigPanelMixin:CreateText(font, text, x, y, width)
    local parent = self.scrollChild
    local fontString = parent:CreateFontString(nil, "OVERLAY", font)
    fontString:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fontString:SetJustifyH("LEFT")
    fontString:SetJustifyV("TOP")
    if width then
        fontString:SetWidth(width)
        fontString:SetWordWrap(true)
    end
    fontString:SetText(text)
    return fontString
end

local function TextHeight(fontString, minimum)
    local height = fontString:GetStringHeight()
    if not height or height < minimum then
        height = minimum
    end
    return height
end

-- Page title with a line of explanation under it.
function CaerdonWardrobeConfigPanelMixin:AddTitle(title, intro)
    self:CreateText("GameFontNormalLarge", title, LEFT_MARGIN, self.nextPoint)
    self.nextPoint = self.nextPoint - 22
    if intro then
        local introText = self:CreateText("GameFontHighlightSmall", intro, LEFT_MARGIN, self.nextPoint,
            CONTENT_RIGHT - LEFT_MARGIN)
        self.nextPoint = self.nextPoint - TextHeight(introText, 10) - 6
    end
end

function CaerdonWardrobeConfigPanelMixin:StartBlock()
    local parent = self.scrollChild
    if self.hasBlock then
        self.nextPoint = self.nextPoint - BLOCK_GAP / 2
        local line = parent:CreateTexture(nil, "BACKGROUND")
        line:SetColorTexture(1, 1, 1, 0.12)
        line:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_MARGIN, self.nextPoint)
        line:SetSize(CONTENT_RIGHT - LEFT_MARGIN, 1)
        self.nextPoint = self.nextPoint - BLOCK_GAP / 2
    else
        self.nextPoint = self.nextPoint - 6
    end
    self.hasBlock = true
end

-- Starts a block for one icon: the icon as the addon draws it, its name, and what it means.
--   spec = { title, description, texture | atlas (texture is the fallback), coords, color,
--            inset (pixels the icon is smaller than its background), background = { same fields },
--            label (text in the icon's place, for things that are drawn as text) }
function CaerdonWardrobeConfigPanelMixin:AddIconHeader(spec)
    local parent = self.scrollChild
    self:StartBlock()

    local top = self.nextPoint
    local centerX, centerY = LEFT_MARGIN + ICON_SIZE / 2, top - ICON_SIZE / 2

    if spec.label then
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER", parent, "TOPLEFT", centerX, centerY)
        label:SetText(spec.label)
        if spec.color then
            label:SetTextColor(unpack(spec.color))
        end
    else
        if spec.background then
            local background = parent:CreateTexture(nil, "ARTWORK", nil, 1)
            background:SetSize(ICON_SIZE, ICON_SIZE)
            background:SetPoint("CENTER", parent, "TOPLEFT", centerX, centerY)
            ApplyTexture(background, spec.background)
        end
        local icon = parent:CreateTexture(nil, "ARTWORK", nil, 2)
        local size = ICON_SIZE - (spec.inset or 0)
        icon:SetSize(size, size)
        icon:SetPoint("CENTER", parent, "TOPLEFT", centerX, centerY)
        ApplyTexture(icon, spec)
    end

    self:CreateText("GameFontNormal", spec.title, ICON_BODY_X, top - 1)
    local height = 16
    if spec.description then
        local description = self:CreateText("GameFontHighlightSmall", spec.description, ICON_BODY_X, top - 17,
            CONTENT_RIGHT - ICON_BODY_X)
        height = 17 + TextHeight(description, 10)
    end

    self.nextPoint = top - math.max(ICON_SIZE, height) - 6
    self.bodyX = ICON_BODY_X
end

-- Starts a block with a plain heading, for pages that are not about one icon.
function CaerdonWardrobeConfigPanelMixin:AddSection(title)
    self:StartBlock()
    self:CreateText("GameFontNormal", title, LEFT_MARGIN, self.nextPoint)
    self.nextPoint = self.nextPoint - 20
    self.bodyX = SECTION_BODY_X
end

-- A small line such as "Show in:", white like the descriptions: the gray "disabled" font was too
-- faint on the see-through settings panel. Returns the y it was placed at, for AddAllNoneButtons.
function CaerdonWardrobeConfigPanelMixin:AddLabel(text, opts)
    opts = opts or {}
    local x = self.bodyX + (opts.indent or 0) * INDENT_STEP
    local y = self.nextPoint - 3
    local label = self:CreateText("GameFontHighlightSmall", text, x, y, CONTENT_RIGHT - x)
    self.nextPoint = y - TextHeight(label, 10) - 3
    return y
end

function CaerdonWardrobeConfigPanelMixin:CreateCheckbox(info, x, y, opts)
    opts = opts or {}
    local parent = self.scrollChild

    local checkbox = CreateFrame("CheckButton", "CaerdonWardrobe" .. info.key, parent,
        "InterfaceOptionsCheckButtonTemplate")
    checkbox.key = info.key
    checkbox.caerdonInfo = info
    checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", x - CHECKBOX_INSET, y)

    checkbox.label = checkbox.Text or _G[checkbox:GetName() .. "Text"]
    checkbox.label:SetText(info.text)
    local labelR, labelG, labelB = checkbox.label:GetTextColor()
    -- Let a click on the label count too, without reaching into the next grid column.
    local labelWidth = checkbox.label:GetStringWidth()
    if labelWidth and labelWidth > 0 then
        checkbox:SetHitRectInsets(0, -math.min(labelWidth, opts.maxLabelWidth or labelWidth), 0, 0)
    end

    checkbox:SetScript("OnClick", function(button)
        local checked = button:GetChecked() and true or false
        SetValue(info, checked)
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        self:UpdateDependents()
    end)
    checkbox:SetScript("OnEnter", function(button)
        ShowOptionTooltip(button, info.text, info.tooltip)
    end)
    checkbox:SetScript("OnLeave", HideOptionTooltip)

    checkbox.caerdonDependsOn = opts.dependsOn
    checkbox.caerdonRefresh = function()
        checkbox:SetChecked(GetValue(info) and true or false)
    end
    checkbox.caerdonSetEnabled = function(enabled)
        checkbox:SetEnabled(enabled)
        if enabled then
            checkbox.label:SetTextColor(labelR or 1, labelG or 1, labelB or 1)
        else
            checkbox.label:SetTextColor(0.5, 0.5, 0.5)
        end
    end
    checkbox.caerdonIsOn = function()
        return (checkbox:GetChecked() and checkbox:IsEnabled()) and true or false
    end

    self:RegisterControl(checkbox)
    return checkbox
end

-- One checkbox on its own row. opts = { indent = levels, dependsOn = checkbox }
function CaerdonWardrobeConfigPanelMixin:AddCheckbox(info, opts)
    opts = opts or {}
    local x = self.bodyX + (opts.indent or 0) * INDENT_STEP
    local checkbox = self:CreateCheckbox(info, x, self.nextPoint, opts)
    self.nextPoint = self.nextPoint - ROW_HEIGHT
    return checkbox
end

-- Several short checkboxes in columns. opts = { indent = levels, columns = count, dependsOn = checkbox }
function CaerdonWardrobeConfigPanelMixin:AddCheckboxGrid(infos, opts)
    opts = opts or {}
    local columns = opts.columns or 3
    local baseX = self.bodyX + (opts.indent or 0) * INDENT_STEP
    local checkboxes = {}
    for index, info in ipairs(infos) do
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        checkboxes[index] = self:CreateCheckbox(info, baseX + column * GRID_COLUMN_WIDTH,
            self.nextPoint - row * ROW_HEIGHT, {
                dependsOn = opts.dependsOn,
                maxLabelWidth = GRID_COLUMN_WIDTH - 32
            })
    end
    self.nextPoint = self.nextPoint - math.ceil(#infos / columns) * ROW_HEIGHT
    return checkboxes
end

-- "All" and "None" at the right end of a label row, for a grid that is one decision per window.
function CaerdonWardrobeConfigPanelMixin:AddAllNoneButtons(y, checkboxes)
    local parent = self.scrollChild

    local function createButton(text, value, right)
        local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetSize(54, 20)
        button:SetPoint("TOPRIGHT", parent, "TOPLEFT", right, y + 5)
        button:SetText(text)
        button:SetScript("OnClick", function()
            for _, checkbox in ipairs(checkboxes) do
                SetValue(checkbox.caerdonInfo, value)
                checkbox:SetChecked(value)
            end
            PlaySound(value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
            self:UpdateDependents()
        end)
        return button
    end

    createButton("None", false, CONTENT_RIGHT)
    createButton("All", true, CONTENT_RIGHT - 58)
end

-- A label with a dropdown to its right. values = { { title, value, tooltip } ... }
-- opts = { indent = levels, dependsOn = checkbox }; info.width sets the dropdown's width, and
-- info.formatUnknown(value) gives the text for a saved value that is not one of the entries.
function CaerdonWardrobeConfigPanelMixin:AddDropdown(info, values, opts)
    opts = opts or {}
    local parent = self.scrollChild
    local x = self.bodyX + (opts.indent or 0) * INDENT_STEP

    local label = self:CreateText("GameFontHighlight", info.text, x, self.nextPoint - 9)

    local dropdown = CreateFrame("Frame", "CaerdonWardrobe" .. info.key, parent, "UIDropDownMenuTemplate")
    dropdown.key = info.key
    dropdown.caerdonInfo = info
    dropdown:SetPoint("LEFT", label, "RIGHT", -8, -2)
    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(dropdown, info.width or 150)
    end

    local text = dropdown.Text or _G[dropdown:GetName() .. "Text"]

    dropdown.initialize = function()
        local current = GetValue(info)
        for _, entry in ipairs(values) do
            local menuInfo = UIDropDownMenu_CreateInfo and UIDropDownMenu_CreateInfo() or {}
            menuInfo.text = entry.title
            menuInfo.value = entry.value
            menuInfo.checked = entry.value == current
            if entry.tooltip then
                menuInfo.tooltipTitle = entry.title
                menuInfo.tooltipText = entry.tooltip
                menuInfo.tooltipOnButton = true
            end
            menuInfo.func = function()
                SetValue(info, entry.value)
                text:SetText(entry.title)
            end
            UIDropDownMenu_AddButton(menuInfo)
        end
    end

    dropdown.caerdonDependsOn = opts.dependsOn
    dropdown.caerdonRefresh = function()
        local current = GetValue(info)
        local title
        for _, entry in ipairs(values) do
            if entry.value == current then
                title = entry.title
            end
        end
        -- A value that is not in the list (set by something other than this dropdown) still shows.
        if not title and current ~= nil and info.formatUnknown then
            title = info.formatUnknown(current)
        end
        text:SetText(title or "")
    end
    dropdown.caerdonSetEnabled = function(enabled)
        if enabled then
            if UIDropDownMenu_EnableDropDown then
                UIDropDownMenu_EnableDropDown(dropdown)
            end
            label:SetTextColor(1, 1, 1)
        else
            if UIDropDownMenu_DisableDropDown then
                UIDropDownMenu_DisableDropDown(dropdown)
            end
            label:SetTextColor(0.5, 0.5, 0.5)
        end
    end
    dropdown.caerdonIsOn = function()
        return true
    end

    self:RegisterControl(dropdown)
    self.nextPoint = self.nextPoint - DROPDOWN_ROW_HEIGHT
    return dropdown
end

-- A frame built elsewhere, placed in the flow of the page. opts = { indent = levels }
function CaerdonWardrobeConfigPanelMixin:AddFrame(frame, height, opts)
    opts = opts or {}
    local parent = self.scrollChild
    local x = self.bodyX + (opts.indent or 0) * INDENT_STEP
    frame:SetParent(parent)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, self.nextPoint - 2)
    self.nextPoint = self.nextPoint - height - 6
    return frame
end

-- A button on its own row. opts = { indent = levels, width = pixels, tooltip = text }
function CaerdonWardrobeConfigPanelMixin:AddButton(text, onClick, opts)
    opts = opts or {}
    local parent = self.scrollChild
    local x = self.bodyX + (opts.indent or 0) * INDENT_STEP

    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(opts.width or 140, 22)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, self.nextPoint - 2)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    if opts.tooltip then
        button:SetScript("OnEnter", function(owner)
            ShowOptionTooltip(owner, text, opts.tooltip)
        end)
        button:SetScript("OnLeave", HideOptionTooltip)
    end

    self.nextPoint = self.nextPoint - ROW_HEIGHT - 2
    return button
end
