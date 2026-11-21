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
local LIST_ICON_SIZE = 18
local LIST_NAME_WIDTH = 150
local CHECKBOX_INSET = 4 -- the template's box art starts a few pixels inside its frame

local defaultConfig

-- The saved table can be replaced wholesale (old settings version) and can lack newer sections,
-- so every read and write resolves it again instead of holding on to a sub-table.
-- Saved data that is not a table where one belongs reads as nothing and is replaced on a write.
local function GetSection(root, info, create)
    if type(root) ~= "table" or not info.configSection then
        return nil
    end
    local section = root[info.configSection]
    if type(section) ~= "table" then
        section = nil
    end
    if section == nil and create then
        section = {}
        root[info.configSection] = section
    end
    if section and info.configSubsection then
        local subsection = section[info.configSubsection]
        if type(subsection) ~= "table" then
            subsection = nil
        end
        if subsection == nil and create then
            subsection = {}
            section[info.configSubsection] = subsection
        end
        section = subsection
    end
    return section
end

-- Where an option's value is kept. The player's settings are one table for every toon
-- (CaerdonWardrobeConfig). An option that describes the toon and not the player's taste
-- (info.perCharacter: which of its specs it plays) is kept with the toon
-- (CaerdonWardrobeCharacterConfig, saved per character). That table has no defaults and is
-- not there until the toon's first choice: a value it does not hold reads as info.default.
-- A click writes what the control then shows, so a default that was only shown becomes a choice
-- with the first click on that control and on no other.
local function GetValue(info)
    local value
    if info.perCharacter then
        local section = GetSection(CaerdonWardrobeCharacterConfig, info)
        value = section and section[info.configValue]
    else
        local section = GetSection(CaerdonWardrobeConfig, info)
        value = section and section[info.configValue]
        if value == nil then
            defaultConfig = defaultConfig or NS:GetDefaultConfig()
            local defaults = GetSection(defaultConfig, info)
            value = defaults and defaults[info.configValue]
        end
    end
    -- info.default: for a key made at run time (one per spec of the toon's class), which the
    -- defaults cannot list. A function where the default follows the game: it is asked each
    -- time the page shows, and the control shows what is in effect until the player clicks.
    if value == nil then
        value = info.default
        if type(value) == "function" then
            value = value()
        end
    end
    return value
end

local function SetValue(info, value)
    local root
    if info.perCharacter then
        if type(CaerdonWardrobeCharacterConfig) ~= "table" then
            CaerdonWardrobeCharacterConfig = {}
        end
        root = CaerdonWardrobeCharacterConfig
    else
        CaerdonWardrobeConfig = CaerdonWardrobeConfig or {}
        root = CaerdonWardrobeConfig
    end
    GetSection(root, info, true)[info.configValue] = value
end

-- The player changed something on a page: the icons follow at once, with the windows that are
-- open behind the settings. Once per click, whatever number of values the click wrote. (The
-- settings window's own "commit" comes only as it closes.)
local function Changed()
    if CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
        CaerdonWardrobe:RefreshItems("settings")
    end
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
    self.controls = {}
    self.hasBlock = false
    self.bodyX = SECTION_BODY_X
    -- A page is laid out once, from the top down, at fixed places. Where a part of it changes
    -- its height while the game runs (AddDropdownList), what comes after is laid out on a
    -- frame that hangs below that part (self.flow) and moves with it: nextPoint counts from
    -- that frame's top, heightAbove is what was laid out before it.
    self.heightAbove = 0
    self.flexible = {}

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
    self.flow = scrollChild
    self.scrollFrame = scrollFrame

    -- The main page's category, registered by CaerdonWardrobeConfigMixin:OnLoad before any page.
    local category = NS.SettingsCategory
    local subcategory, layout = Settings.RegisterCanvasLayoutSubcategory(category, frame, self:GetTitle());
end

-- Call after the last control: loads the values and gives the scroll child its real height.
function CaerdonWardrobeConfigPanelMixin:FinishLayout()
    self:RefreshControls()
end

function CaerdonWardrobeConfigPanelMixin:RefreshControls()
    for _, control in ipairs(self.controls) do
        control.caerdonRefresh()
    end
    self:UpdateDependents()
    self:UpdateHeight()
end

-- The scroll child's height: what was laid out, and each part whose height changes as it is
-- now.
function CaerdonWardrobeConfigPanelMixin:UpdateHeight()
    local height = self.heightAbove - self.nextPoint + 24
    for _, part in ipairs(self.flexible) do
        height = height + part:GetHeight()
    end
    self.scrollChild:SetHeight(height)
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
    local parent = self.flow
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
    local parent = self.flow
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
    local parent = self.flow
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
    local parent = self.flow

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
        Changed()
    end)
    -- opts.forcedOn(): the option is on whatever was chosen, because the choice does not exist
    -- right now (an option about another addon that is not loaded). It is then shown checked
    -- and not to be changed, with info.forcedTooltip as its explanation; the stored value stays.
    local function Forced()
        return opts.forcedOn ~= nil and opts.forcedOn() and true or false
    end
    -- info.tooltip can be a function, for a text that depends on what the option shows now.
    checkbox:SetScript("OnEnter", function(button)
        local tooltip = Forced() and info.forcedTooltip or info.tooltip
        if type(tooltip) == "function" then
            tooltip = tooltip()
        end
        ShowOptionTooltip(button, info.text, tooltip)
    end)
    checkbox:SetScript("OnLeave", HideOptionTooltip)
    if opts.forcedOn and checkbox.SetMotionScriptsWhileDisabled then
        checkbox:SetMotionScriptsWhileDisabled(true)
    end

    checkbox.caerdonDependsOn = opts.dependsOn
    checkbox.caerdonRefresh = function()
        checkbox:SetChecked(Forced() or (GetValue(info) and true or false))
    end
    checkbox.caerdonSetEnabled = function(enabled)
        enabled = enabled and not Forced()
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
    local parent = self.flow

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
            Changed()
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
    local parent = self.flow
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
                Changed()
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

-- A list that is not known until the page shows and changes while the game runs (a row per
-- gear set of the toon): one small line of text, then a row per entry with its icon, its name
-- and a dropdown. What comes after it on the page hangs below it and moves as it grows.
--   spec = { key, width (of the dropdowns),
--            rows = function() -> { { icon, text, value, title (what the dropdown shows),
--                   note (a line of text in the dropdown's place, for a row with nothing to
--                   choose) } ... },
--                   or nil where there is nothing to choose from: the list then takes no room
--            header = function(count, rows) -> the line above the rows; with no rows, what the
--                   list is for
--            choices = function(row) -> { { title, value, tooltip, disabled } ... }, as a
--                   dropdown opens. disabled: greyed and not to be clicked, and its tooltip,
--                   which says why, still shows
--            choose = function(row, value): the player's click
--            check = a switch at the head of each row (optional):
--                   { get = function(row) -> true, false, or nil for a row whose switch is not
--                           to be clicked (shown empty and greyed; its tooltip still shows),
--                     set = function(row, checked): the player's click,
--                     tooltip = function(row) -> text } }
--            mark = a second, labelled switch at the end of a row (optional), which hangs on
--                   nothing: { text, get = function(row) -> true, false, or nil for a row that
--                   has none, set = function(row, checked), tooltip = function(row) -> text } }
-- opts = { indent = levels, dependsOn = checkbox (for the rows' switches alone: a dropdown is
--          usable whatever that checkbox says) }
function CaerdonWardrobeConfigPanelMixin:AddDropdownList(spec, opts)
    opts = opts or {}
    local parent = self.flow
    local x = self.bodyX + (opts.indent or 0) * INDENT_STEP
    local width = CONTENT_RIGHT - x

    local list = CreateFrame("Frame", "CaerdonWardrobe" .. spec.key, parent)
    list.key = spec.key
    list:SetPoint("TOPLEFT", parent, "TOPLEFT", x, self.nextPoint)
    list:SetSize(width, 1)

    local header = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -3)
    header:SetJustifyH("LEFT")
    header:SetJustifyV("TOP")
    header:SetWidth(width)
    header:SetWordWrap(true)
    list.header = header
    list.rows = {}

    local function Row(index)
        local row = list.rows[index]
        if row then
            return row
        end
        row = CreateFrame("Frame", nil, list)
        row:SetSize(width, DROPDOWN_ROW_HEIGHT)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(LIST_ICON_SIZE, LIST_ICON_SIZE)
        if spec.check then
            local check = CreateFrame("CheckButton", "CaerdonWardrobe" .. spec.key .. "Check" .. index, row,
                "InterfaceOptionsCheckButtonTemplate")
            check:SetPoint("LEFT", row, "LEFT", -CHECKBOX_INSET, 0)
            -- The template's text is not used: the row has its name beside the icon.
            local label = check.Text or (check:GetName() and _G[check:GetName() .. "Text"])
            if label then
                label:SetText("")
            end
            check:SetScript("OnClick", function(button)
                local checked = button:GetChecked() and true or false
                PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
                if row.entry then
                    spec.check.set(row.entry, checked)
                end
            end)
            check:SetScript("OnEnter", function(button)
                if row.entry and spec.check.tooltip then
                    ShowOptionTooltip(button, row.entry.text, spec.check.tooltip(row.entry))
                end
            end)
            check:SetScript("OnLeave", HideOptionTooltip)
            if check.SetMotionScriptsWhileDisabled then
                check:SetMotionScriptsWhileDisabled(true)
            end
            row.check = check
            row.icon:SetPoint("LEFT", row, "LEFT", ROW_HEIGHT + 2, 0)
        else
            row.icon:SetPoint("LEFT", row, "LEFT", INDENT_STEP, 0)
        end
        -- One width for every name, so that the dropdowns stand in a column.
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetWidth(LIST_NAME_WIDTH)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        local dropdown = CreateFrame("Frame", "CaerdonWardrobe" .. spec.key .. index, row, "UIDropDownMenuTemplate")
        dropdown:SetPoint("LEFT", row.name, "RIGHT", -8, -2)
        if UIDropDownMenu_SetWidth then
            UIDropDownMenu_SetWidth(dropdown, spec.width or 150)
        end
        row.dropdown = dropdown
        row.text = dropdown.Text or _G[dropdown:GetName() .. "Text"]
        if spec.mark then
            local mark = CreateFrame("CheckButton", "CaerdonWardrobe" .. spec.key .. "Mark" .. index, row,
                "InterfaceOptionsCheckButtonTemplate")
            mark:SetPoint("LEFT", dropdown, "RIGHT", -14, 2)
            local label = mark.Text or (mark:GetName() and _G[mark:GetName() .. "Text"])
            if label then
                label:SetText(spec.mark.text)
            end
            mark:SetScript("OnClick", function(button)
                local checked = button:GetChecked() and true or false
                PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
                if row.entry then
                    spec.mark.set(row.entry, checked)
                end
            end)
            mark:SetScript("OnEnter", function(button)
                if row.entry and spec.mark.tooltip then
                    ShowOptionTooltip(button, spec.mark.text, spec.mark.tooltip(row.entry))
                end
            end)
            mark:SetScript("OnLeave", HideOptionTooltip)
            row.mark = mark
        end
        -- In the dropdown's place, for a row with nothing to choose.
        row.note = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.note:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
        row.note:SetJustifyH("LEFT")
        row.note:SetWordWrap(false)
        dropdown.initialize = function()
            local entry = row.entry
            for _, choice in ipairs(entry and spec.choices(entry) or {}) do
                local menuInfo = UIDropDownMenu_CreateInfo and UIDropDownMenu_CreateInfo() or {}
                menuInfo.text = choice.title
                menuInfo.value = choice.value
                menuInfo.checked = choice.value == entry.value
                if choice.tooltip then
                    menuInfo.tooltipTitle = choice.title
                    menuInfo.tooltipText = choice.tooltip
                    menuInfo.tooltipOnButton = true
                end
                if choice.disabled then
                    menuInfo.disabled = true
                    menuInfo.tooltipWhileDisabled = true
                else
                    menuInfo.func = function()
                        spec.choose(entry, choice.value)
                        -- A choice can change the rows themselves (a spec is listed until a
                        -- gear set is given its scale), and with them the page's height.
                        list.caerdonRefresh()
                        self:UpdateHeight()
                    end
                end
                UIDropDownMenu_AddButton(menuInfo)
            end
        end
        list.rows[index] = row
        return row
    end

    -- A row's switch is usable where the option above the list is on and the row has one to
    -- click.
    local function EnableChecks()
        for _, row in ipairs(list.rows) do
            if row.check then
                row.check:SetEnabled(list.checksEnabled ~= false and row.checkUsable == true)
            end
        end
    end

    list.caerdonRefresh = function()
        local entries = spec.rows()
        local y = 0
        if entries then
            header:SetText(spec.header(#entries, entries))
            header:Show()
            y = -3 - TextHeight(header, 10) - 3
        else
            header:Hide()
        end
        local count = entries and #entries or 0
        for index = 1, count do
            local entry = entries[index]
            local row = Row(index)
            row.entry = entry
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, y)
            row.icon:SetTexture(entry.icon)
            row.name:SetText(entry.text)
            row.text:SetText(entry.title or "")
            row.dropdown:SetShown(entry.note == nil)
            row.note:SetText(entry.note or "")
            row.note:SetShown(entry.note ~= nil)
            if row.check then
                local checked = spec.check.get(entry)
                row.checkUsable = checked ~= nil
                row.check:SetChecked(checked == true)
            end
            if row.mark then
                local marked = spec.mark.get(entry)
                row.mark:SetShown(marked ~= nil)
                row.mark:SetChecked(marked == true)
            end
            row:Show()
            y = y - DROPDOWN_ROW_HEIGHT
        end
        for index = count + 1, #list.rows do
            list.rows[index].entry = nil
            list.rows[index]:Hide()
        end
        -- Never no height at all: a frame without one has no place, and what hangs below
        -- is placed by this one's lower edge.
        list:SetHeight(math.max(1, -y))
        EnableChecks()
    end
    if spec.check then
        list.caerdonDependsOn = opts.dependsOn
        list.caerdonSetEnabled = function(enabled)
            list.checksEnabled = enabled and true or false
            EnableChecks()
        end
    end

    local rest = CreateFrame("Frame", nil, parent)
    rest:SetPoint("TOPLEFT", list, "BOTTOMLEFT", -x, 0)
    rest:SetSize(CONTENT_RIGHT, 1)
    self.heightAbove = self.heightAbove - self.nextPoint
    table.insert(self.flexible, list)
    self.flow = rest
    self.nextPoint = 0

    self:RegisterControl(list)
    return list
end

-- For a control a page builds from parts of its own: the player's click on it, written as a
-- checkbox's or a dropdown's is, with the one refresh a click brings.
function CaerdonWardrobeConfigPanelMixin:SetOption(info, value)
    SetValue(info, value)
    Changed()
end

-- A frame built elsewhere, placed in the flow of the page. opts = { indent = levels }
function CaerdonWardrobeConfigPanelMixin:AddFrame(frame, height, opts)
    opts = opts or {}
    local parent = self.flow
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
    local parent = self.flow
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
