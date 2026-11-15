-- Layout editor: where the status icon, the binding text, a gear set's name and the level gain
-- sit on an item slot, and how big they are.
--
-- Everything shown here is drawn by the addon's real drawing code on real item buttons, with a
-- made-up status instead of an item's own: the large slot is an ordinary 37 px slot inside a
-- frame scaled four times, and the row under it is the same thing at its true size. Nothing is
-- a mock-up, so what the editor shows is what a standard slot gets. Windows with their own slot
-- size scale from this (see "Layout settings" in CLAUDE.md), and lists that fit the icon into a
-- row keep their own layout.
--
-- The editor mirrors the settings. A part the player has switched off (the level gain, gear set
-- names, binding text, the upgrade arrow) is not drawn on the examples and has no button here,
-- and an example that is only about such a part is left out: parts are turned on and off on the
-- Icons page, not in this window.
--
-- Changes are written to the settings as they are made and the open windows are redrawn, so the
-- player's real bags follow along next to the editor. Done keeps them; closing any other way
-- asks.

local ADDON_NAME, NS = ...
local L = NS.L

CaerdonWardrobeLayoutEditor = {}
local Editor = CaerdonWardrobeLayoutEditor

local SLOT_SIZE = 37
local PREVIEW_SCALE = 4
local SIZE_STEP, SIZE_MIN, SIZE_MAX = 5, 50, 300
local NUDGE_STEP, NUDGE_LIMIT = 1, 40
local STRIP_PITCH = 60 -- a slot plus room for an icon that hangs over the corner and a caption
local KEEP_DIALOG = "CAERDON_LAYOUT_KEEP_CHANGES"

local ANCHORS = {
    { value = "TOPLEFT",     name = "Top left" },
    { value = "TOP",         name = "Top" },
    { value = "TOPRIGHT",    name = "Top right" },
    { value = "LEFT",        name = "Left" },
    { value = "CENTER",      name = "Center" },
    { value = "RIGHT",       name = "Right" },
    { value = "BOTTOMLEFT",  name = "Bottom left" },
    { value = "BOTTOM",      name = "Bottom" },
    { value = "BOTTOMRIGHT", name = "Bottom right" },
}

-- Classic starter items: they exist in every client's item data, so their icons are always
-- there. They are only pictures; the status drawn on them is made up.
local ICON_SHIRT, ICON_SWORD, ICON_BOOTS, ICON_CLOTH, ICON_PANTS = 38, 25, 40, 2589, 39
-- The item the drawing code is handed. Any plain item does: no gear set, no appearance.
local SAMPLE_ITEM_ID = 6948

---------------------------------------------------------------------------------------------
-- Parts
---------------------------------------------------------------------------------------------

-- Which parts the player's settings show at all. The editor leaves the others out.
local function EnabledParts()
    local binding, icon = CaerdonWardrobeConfig.Binding, CaerdonWardrobeConfig.Icon
    local enabled = {
        icon = true,
        arrow = icon.ShowUpgradeIcon ~= false,
        text = (binding.ShowBoE or binding.ShowBoA) and true or false,
        gear = binding.ShowGearSets and true or false,
        delta = icon.ShowUpgradeLevelDelta and true or false,
    }
    -- The text the examples carry: whichever kind of binding text is switched on.
    enabled.textLabel = binding.ShowBoE and L["BoE"] or L["BoA"]
    return enabled
end

-- The things that can be moved. Each returns the settings table that holds its Position, Scale,
-- OffsetX and OffsetY, creating it if a saved configuration lacks it.
local PARTS = {
    {
        key = "icon",
        label = "Icon",
        width = 48,
        settings = function()
            return CaerdonWardrobeConfig.Icon
        end,
        defaults = function(defaults)
            return defaults.Icon
        end
    },
    {
        key = "text",
        label = "Binding text",
        width = 92,
        settings = function()
            return CaerdonWardrobeConfig.Binding
        end,
        defaults = function(defaults)
            return defaults.Binding
        end
    },
    {
        key = "gear",
        -- A gear set's name is drawn where the binding text would be; a slot never shows both.
        label = "Gear set",
        width = 70,
        settings = function()
            local binding = CaerdonWardrobeConfig.Binding
            if type(binding.GearSet) ~= "table" then
                binding.GearSet = {}
            end
            return binding.GearSet
        end,
        defaults = function(defaults)
            return defaults.Binding.GearSet
        end
    },
    {
        key = "delta",
        -- The "+5" on an upgrade: how many item levels it is above what is equipped. Not an
        -- item level display, and off until the player turns it on (Icons page, under Upgrade).
        label = "Level gain",
        width = 80,
        settings = function()
            local icon = CaerdonWardrobeConfig.Icon
            if type(icon.UpgradeDelta) ~= "table" then
                icon.UpgradeDelta = {}
            end
            return icon.UpgradeDelta
        end,
        defaults = function(defaults)
            return defaults.Icon.UpgradeDelta
        end
    },
}
local PART_BY_KEY = {}
for _, part in ipairs(PARTS) do
    PART_BY_KEY[part.key] = part
end
local LAYOUT_KEYS = { "Position", "Scale", "OffsetX", "OffsetY" }

---------------------------------------------------------------------------------------------
-- Examples
---------------------------------------------------------------------------------------------

-- The combinations that matter for placement. What each one carries is cut down to what the
-- player's settings show (BuildSample). "needs" names what the example is about: with all of
-- those switched off it has nothing to say that "All parts" does not, and is left out.
local TEMPLATES = {
    { name = "All parts", icon = ICON_SHIRT, status = "own", text = true, delta = true },
    -- Binding text with nothing to move it: no stack count, no level gain. The only example
    -- that shows the text exactly where its anchor puts it.
    { name = "New look", icon = ICON_BOOTS, status = "own", text = true, needs = { "text" } },
    { name = "Upgrade", icon = ICON_SWORD, status = "upgrade", arrow = true, delta = true,
        needs = { "arrow", "delta" } },
    -- Binding text above a stack count.
    { name = "Stack", icon = ICON_CLOTH, status = "sellable", text = true, count = 20, needs = { "text" } },
    { name = "Gear set", icon = ICON_PANTS, status = "collected", gear = true, noIcon = true,
        needs = { "gear" } },
}
local ALL_PARTS_SAMPLE, GEAR_SET_SAMPLE = 1, 5

-- One example as the settings draw it. "has" says which parts it shows, so the editor can switch
-- the large slot to one that shows the part being edited.
local function BuildSample(template, enabled)
    local has = {}
    local sample = {
        name = template.name,
        icon = template.icon,
        count = template.count,
        status = template.status,
        has = has
    }
    if template.arrow then
        has.icon = enabled.arrow
    elseif not template.noIcon then
        has.icon = true
    end
    if template.text and enabled.text then
        sample.binding = enabled.textLabel
        has.text = true
    end
    if template.gear and enabled.gear then
        sample.binding = "Tank"
        has.gear = true
    end
    if template.delta then
        -- The drawing code only shows it when the level gain is switched on. An example with a
        -- gain and an icon that is not the arrow is an upgrade with a look to learn, which carries
        -- the arrow as a small badge (when the arrow is switched on).
        sample.transmogInfo = {
            upgradeItemLevelDelta = 5,
            isUpgrade = template.arrow or nil,
            upgradeStatus = (not template.arrow and enabled.arrow) and "upgrade" or nil
        }
        has.delta = enabled.delta
    end

    local relevant = not template.needs
    for _, key in ipairs(template.needs or {}) do
        relevant = relevant or enabled[key]
    end
    sample.visible = (relevant and (has.icon or has.text or has.gear or has.delta)) and true or false
    return sample
end

local sampleFeature, sampleItem
local sampleButtons = {} -- every sample button made, with the example it shows now
local strips = {}        -- every row of examples made
local sampleCount = 0

-- A feature that shows everything a window could hide: the per-window choices do not apply to
-- an example slot. The settings that switch a part off everywhere do (see EnabledParts).
local function GetSampleFeature()
    if not sampleFeature then
        sampleFeature = CreateFromMixins(CaerdonWardrobeFeatureMixin, {})
        function sampleFeature:GetName()
            return "LayoutSample"
        end

        function sampleFeature:GetDisplayInfoInternal()
            local show = { shouldShow = true }
            return {
                upgradeIcon = show, bindingStatus = show, ownIcon = show, otherIcon = show,
                questIcon = show, oldExpansionIcon = show, sellableIcon = show, auctionIcon = show
            }
        end
    end
    return sampleFeature
end

local function DrawSample(button, sample)
    -- options.sample makes the drawing code measure text at normal size (the large slot is
    -- scaled up, and text measures narrower there than on a real slot).
    local options = { sample = true }
    local feature = GetSampleFeature()
    local locationInfo = { locationKey = "layout-sample" }
    CaerdonWardrobe:SetupCaerdonButton(button, sampleItem, feature, locationInfo, options)
    CaerdonWardrobe:SetItemButtonStatus(button, sampleItem, feature, locationInfo, options, sample.status,
        sample.binding, sample.transmogInfo)
    CaerdonWardrobe:SetItemButtonBindType(button, sampleItem, feature, locationInfo, options, sample.status,
        sample.binding)
end

-- Gives a sample button the picture, stack count and made-up status of an example.
function Editor:SetSample(button, sample)
    local texture = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(sample.icon) or 134400
    if SetItemButtonTexture then
        SetItemButtonTexture(button, texture)
    elseif button.icon then
        button.icon:SetTexture(texture)
    end
    if SetItemButtonCount then
        SetItemButtonCount(button, sample.count or 0)
    end
    button.count = sample.count
    sampleButtons[button] = sample
end

-- A standard item slot to draw an example on.
function Editor:CreateSampleButton(parent)
    sampleCount = sampleCount + 1
    local name = "CaerdonWardrobeLayoutSample" .. sampleCount

    -- The game's own item button, so the slot art and the stack count are the real ones.
    local ok, button = pcall(CreateFrame, "ItemButton", name, parent)
    if not ok or not button then
        button = CreateFrame("Button", name, parent)
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints()
    end
    button:SetSize(SLOT_SIZE, SLOT_SIZE)
    button:EnableMouse(false)
    return button
end

-- A thin gold frame around a region, hidden until shown. thickness is in the region's own units.
local function CreateOutline(parent, thickness)
    local outline = CreateFrame("Frame", nil, parent)
    outline:SetAllPoints()
    for _, edge in ipairs({
        { "TOPLEFT", "TOPRIGHT", nil, thickness },
        { "BOTTOMLEFT", "BOTTOMRIGHT", nil, thickness },
        { "TOPLEFT", "BOTTOMLEFT", thickness, nil },
        { "TOPRIGHT", "BOTTOMRIGHT", thickness, nil },
    }) do
        local line = outline:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(1, 0.82, 0, 1)
        line:SetPoint(edge[1], outline, edge[1], 0, 0)
        line:SetPoint(edge[2], outline, edge[2], 0, 0)
        if edge[3] then
            line:SetWidth(edge[3])
        else
            line:SetHeight(edge[4])
        end
    end
    outline:Hide()
    return outline
end

-- Marks an example slot as the chosen one: a gold line just outside the slot, made of textures
-- on the slot itself. The addon's icon and texts live on a frame above the slot, so they are
-- drawn over the line wherever the player has put them, at whatever size; a frame around the
-- slot would have cut across an icon that hangs over the corner.
local function CreateSlotOutline(button, thickness, padding)
    local lines = {}
    for _, edge in ipairs({
        { "TOPLEFT", "TOPRIGHT", -padding, padding, padding, padding, nil, thickness },
        { "BOTTOMLEFT", "BOTTOMRIGHT", -padding, -padding, padding, -padding, nil, thickness },
        { "TOPLEFT", "BOTTOMLEFT", -padding, padding, -padding, -padding, thickness, nil },
        { "TOPRIGHT", "BOTTOMRIGHT", padding, padding, padding, -padding, thickness, nil },
    }) do
        local line = button:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(1, 0.82, 0, 1)
        line:SetPoint(edge[1], button, edge[1], edge[3], edge[4])
        line:SetPoint(edge[2], button, edge[2], edge[5], edge[6])
        if edge[7] then
            line:SetWidth(edge[7])
        else
            line:SetHeight(edge[8])
        end
        line:Hide()
        lines[#lines + 1] = line
    end
    local outline = { shown = false }
    function outline:SetShown(shown)
        self.shown = shown and true or false
        for _, line in ipairs(lines) do
            line:SetShown(self.shown)
        end
    end
    return outline
end

-- Gives every slot of a row its example as the settings draw it now, and closes the gaps left by
-- the examples that are left out (the gear set example with gear set names switched off).
local function LayOutStrip(strip, enabled)
    local x = 10
    for index, template in ipairs(TEMPLATES) do
        local slot = strip.slots[index]
        local sample = BuildSample(template, enabled)
        Editor:SetSample(slot.button, sample)
        slot.button:SetShown(sample.visible)
        if slot.caption then
            slot.caption:SetShown(sample.visible)
        end
        if slot.picker then
            slot.picker:SetShown(sample.visible)
        end
        if sample.visible then
            slot.button:ClearAllPoints()
            slot.button:SetPoint("TOPLEFT", strip.frame, "TOPLEFT", x, -10)
            x = x + STRIP_PITCH
        end
    end
end

-- A row of true-size example slots. Returns its frame, its height, and the row itself.
--   opts.captions: the example's name under each slot
--   opts.onClick(index): makes the slots clickable; strip.outlines[index] marks the chosen one
function Editor:CreateSampleStrip(parent, opts)
    opts = opts or {}
    local height = SLOT_SIZE + 16 + (opts.captions and 14 or 0)
    local strip = { frame = CreateFrame("Frame", nil, parent), slots = {}, outlines = {}, pickers = {} }
    strip.frame:SetSize(#TEMPLATES * STRIP_PITCH, height)

    for index, template in ipairs(TEMPLATES) do
        local slot = { button = self:CreateSampleButton(strip.frame) }
        slot.button:SetPoint("TOPLEFT", strip.frame, "TOPLEFT", 10 + (index - 1) * STRIP_PITCH, -10)
        if opts.captions then
            slot.caption = strip.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            slot.caption:SetPoint("TOP", slot.button, "BOTTOM", 0, -4)
            slot.caption:SetText(template.name)
        end
        if opts.onClick then
            -- The slot itself takes no clicks; a plain button over it does.
            local picker = CreateFrame("Button", nil, strip.frame)
            picker:SetAllPoints(slot.button)
            picker:SetFrameLevel(slot.button:GetFrameLevel() + 20)
            local hover = picker:CreateTexture(nil, "HIGHLIGHT")
            hover:SetAllPoints()
            hover:SetColorTexture(1, 1, 1, 0.2)
            picker:SetScript("OnClick", function()
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                opts.onClick(index)
            end)
            slot.picker = picker
            strip.pickers[index] = picker
            strip.outlines[index] = CreateSlotOutline(slot.button, 1, 3)
        end
        strip.slots[index] = slot
    end

    strips[#strips + 1] = strip
    if CaerdonWardrobeConfig then
        LayOutStrip(strip, EnabledParts())
    end
    return strip.frame, height, strip
end

-- Draws every sample again, as the settings stand now. Safe to call at any time: before the
-- sample item's data is there it waits for it, and an error in the drawing code is reported
-- without breaking the caller.
--
-- The binding text is measured against its slot. A slot that was only just shown, or drawn while
-- its page was still hidden, has no width yet and its text comes out cut short ("B..."), so
-- every redraw is followed by one more a moment later, when the frames have been laid out.
function Editor:RedrawSamples(isFollowUp)
    if not (CaerdonItem and CaerdonWardrobe and CaerdonWardrobeConfig) then
        return
    end
    if not isFollowUp and not self.followUpQueued then
        self.followUpQueued = true
        C_Timer.After(0.05, function()
            self.followUpQueued = false
            self:RedrawSamples(true)
        end)
    end

    -- A part can have been switched on or off on the Icons page since the last draw.
    local enabled = EnabledParts()
    for _, strip in ipairs(strips) do
        LayOutStrip(strip, enabled)
    end
    if self.bigButton then
        self:SetSample(self.bigButton, self:GetLargeSample())
    end

    local function draw()
        self.sampleItemReady = true
        for button, sample in pairs(sampleButtons) do
            if sample.visible then
                local ok, err = pcall(DrawSample, button, sample)
                if not ok then
                    geterrorhandler()(err)
                end
            end
        end
        if self.OnSamplesDrawn then
            self:OnSamplesDrawn()
        end
    end
    if not sampleItem then
        sampleItem = CaerdonItem:CreateFromItemID(SAMPLE_ITEM_ID)
    end
    if self.sampleItemReady then
        draw()
    else
        sampleItem:ContinueOnItemLoad(draw)
    end
end

---------------------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------------------

local function Clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

function Editor:GetPart()
    return PART_BY_KEY[self.selected or "icon"]
end

-- The example on the large slot, as the settings draw it now.
function Editor:GetLargeSample()
    return BuildSample(TEMPLATES[self.large or ALL_PARTS_SAMPLE], EnabledParts())
end

-- Keeps the selection possible: the large slot shows an example that is not left out, and the
-- selected part is one that example has. Settings can change between two visits to the editor.
function Editor:Normalize()
    local enabled = EnabledParts()
    local sample = BuildSample(TEMPLATES[self.large or ALL_PARTS_SAMPLE], enabled)
    if not sample.visible then
        self.large = ALL_PARTS_SAMPLE
        sample = BuildSample(TEMPLATES[ALL_PARTS_SAMPLE], enabled)
    end
    if not sample.has[self:GetPart().key] then
        for _, part in ipairs(PARTS) do
            if sample.has[part.key] then
                self.selected = part.key
                break
            end
        end
    end
end

function Editor:SelectPart(key)
    self.selected = key
    -- Editing a part the large slot does not show would change nothing visible.
    if not self:GetLargeSample().has[key] then
        self.large = (key == "gear") and GEAR_SET_SAMPLE or ALL_PARTS_SAMPLE
    end
    self:Refresh()
end

-- Shows one of the examples on the large slot. If it lacks the part being edited, the first
-- part it does show is selected instead (Normalize).
function Editor:ShowLarge(index)
    self.large = index
    self:Refresh()
end

function Editor:SetPosition(anchor)
    self:GetPart().settings().Position = anchor
    self:Changed()
end

function Editor:StepSize(direction)
    local settings = self:GetPart().settings()
    local current = tonumber(settings.Scale) or 100
    settings.Scale = Clamp(current + direction * SIZE_STEP, SIZE_MIN, SIZE_MAX)
    self:Changed()
end

-- right and up are +1, left and down -1
function Editor:Nudge(right, up)
    local settings = self:GetPart().settings()
    settings.OffsetX = Clamp((tonumber(settings.OffsetX) or 0) + right * NUDGE_STEP, -NUDGE_LIMIT, NUDGE_LIMIT)
    settings.OffsetY = Clamp((tonumber(settings.OffsetY) or 0) + up * NUDGE_STEP, -NUDGE_LIMIT, NUDGE_LIMIT)
    self:Changed()
end

function Editor:ClearNudge()
    local settings = self:GetPart().settings()
    settings.OffsetX, settings.OffsetY = 0, 0
    self:Changed()
end

local function ResetPart(part, defaults)
    local settings, defaultSettings = part.settings(), part.defaults(defaults)
    for _, key in ipairs(LAYOUT_KEYS) do
        settings[key] = defaultSettings[key]
    end
end

function Editor:ResetSelected()
    ResetPart(self:GetPart(), NS:GetDefaultConfig())
    self:Changed()
end

-- Every part, including the ones that are switched off and not shown here: "everything" means
-- the layout is back at the addon's defaults whatever is turned on later.
function Editor:ResetAll()
    local defaults = NS:GetDefaultConfig()
    for _, part in ipairs(PARTS) do
        ResetPart(part, defaults)
    end
    self:Changed()
end

-- What every part was set to when the editor was opened, to go back to. Resetting puts the
-- addon's defaults in place, which for someone who had moved things before is not "undo".
function Editor:TakeSnapshot()
    local snapshot = { parts = {} }
    for _, part in ipairs(PARTS) do
        local settings, saved = part.settings(), {}
        for _, key in ipairs(LAYOUT_KEYS) do
            saved[key] = settings[key]
        end
        snapshot.parts[part.key] = saved
    end
    self.snapshot = snapshot
end

-- Puts the settings back to the snapshot. Does not redraw anything.
function Editor:RestoreSnapshot()
    local snapshot = self.snapshot
    if not snapshot then
        return
    end
    for _, part in ipairs(PARTS) do
        local settings, saved = part.settings(), snapshot.parts[part.key]
        for _, key in ipairs(LAYOUT_KEYS) do
            settings[key] = saved[key]
        end
    end
end

function Editor:HasChanges()
    local snapshot = self.snapshot
    if not snapshot then
        return false
    end
    for _, part in ipairs(PARTS) do
        local settings, saved = part.settings(), snapshot.parts[part.key]
        for _, key in ipairs(LAYOUT_KEYS) do
            if settings[key] ~= saved[key] then
                return true
            end
        end
    end
    return false
end

function Editor:UndoChanges()
    self:RestoreSnapshot()
    self:Changed()
end

-- After a setting changed: show it here, and have the open windows redrawn shortly (one redraw
-- for a burst of clicks).
function Editor:Changed()
    self:Refresh()
    if not self.redrawQueued then
        self.redrawQueued = true
        C_Timer.After(0.2, function()
            self.redrawQueued = false
            CaerdonWardrobe:RefreshItems()
        end)
    end
end

---------------------------------------------------------------------------------------------
-- Closing
---------------------------------------------------------------------------------------------

-- Done keeps what was changed. Closing any other way (the X, Escape, the slash command) asks,
-- if anything was changed: changes show on the real windows as they are made, so there has to be
-- a way to back out that is not a reset to the addon's defaults, and an Escape pressed by
-- accident must not throw the work away.
function Editor:Finish()
    self.keepChanges = true
    self.frame:Hide()
end

-- What the examples on the Display page and the open windows show once the editor is gone.
function Editor:AfterClose()
    self:RedrawSamples()
    if CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
        CaerdonWardrobe:RefreshItems()
    end
end

-- The answer to "keep the changes?": "keep", "discard", or "edit" to go back into the editor
-- with nothing decided.
function Editor:ResolveClose(choice)
    if not self.pendingClose then
        return
    end
    self.pendingClose = nil
    if choice == "edit" then
        self.frame:Show()
        self:Refresh()
        return
    end
    if choice == "discard" then
        self:RestoreSnapshot()
    end
    self:AfterClose()
end

function Editor:OnClosed()
    if self.keepChanges then
        self.keepChanges = nil
    elseif self:HasChanges() then
        if StaticPopupDialogs and StaticPopup_Show then
            if not StaticPopupDialogs[KEEP_DIALOG] then
                StaticPopupDialogs[KEEP_DIALOG] = {
                    text = "Keep the changes you made to the layout?",
                    button1 = "Keep",
                    button2 = "Discard",
                    button3 = "Keep editing",
                    OnAccept = function() Editor:ResolveClose("keep") end,
                    -- Only a click on Discard discards. Anything else that cancels the question
                    -- (another dialog taking its place, say) goes back to the editor.
                    OnCancel = function(_, _, reason)
                        Editor:ResolveClose(reason == "clicked" and "discard" or "edit")
                    end,
                    OnAlt = function() Editor:ResolveClose("edit") end,
                    OnEscape = function() Editor:ResolveClose("edit") end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                    preferredIndex = 3,
                }
            end
            -- Nothing is put back yet: the windows keep showing the changes behind the question.
            self.pendingClose = true
            StaticPopup_Show(KEEP_DIALOG)
            return
        end
        self:RestoreSnapshot()
    end
    self:AfterClose()
end

---------------------------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------------------------

local function CreateLabel(parent, font, text, x, y, width)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    if width then
        label:SetWidth(width)
        label:SetWordWrap(true)
    end
    label:SetText(text)
    return label
end

local function CreateTextButton(parent, text, width, x, y, onClick, tooltip)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(text)
    button:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        onClick()
    end)
    if tooltip then
        button:SetScript("OnEnter", function(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_TOP")
            GameTooltip:SetText(text, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return button
end

-- "-  100%  +"
local function CreateStepper(parent, x, y, onStep)
    local stepper = {}
    stepper.minus = CreateTextButton(parent, "-", 24, x, y, function() onStep(-1) end)
    stepper.value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    stepper.value:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 28, y - 5)
    stepper.value:SetWidth(52)
    stepper.value:SetJustifyH("CENTER")
    stepper.plus = CreateTextButton(parent, "+", 24, x + 84, y, function() onStep(1) end)
    return stepper
end

local function DescribeNudge(x, y)
    if x == 0 and y == 0 then
        return "Not moved"
    end
    local parts = {}
    if x ~= 0 then
        parts[#parts + 1] = string.format("%d %s", math.abs(x), x > 0 and "right" or "left")
    end
    if y ~= 0 then
        parts[#parts + 1] = string.format("%d %s", math.abs(y), y > 0 and "up" or "down")
    end
    return table.concat(parts, ", ")
end

local TABS_LEFT, TABS_TOP = 240, -44
local BASE_HEIGHT = 458

-- What the installed addons do differently from what this window shows, a sentence each. An
-- integration says it itself (GetLayoutNote on its feature), and integrations only register
-- when their addon is loaded, so a player only reads about addons they have.
local function IntegrationNotes()
    local notes = {}
    local features = CaerdonWardrobe.GetRegisteredFeatures and CaerdonWardrobe:GetRegisteredFeatures()
    for _, feature in pairs(features or {}) do
        if type(feature.GetLayoutNote) == "function" then
            local ok, note = pcall(feature.GetLayoutNote, feature)
            if ok and type(note) == "string" and note ~= "" then
                notes[#notes + 1] = note
            end
        end
    end
    table.sort(notes)
    return notes
end

function Editor:GetFrame()
    if self.frame then
        return self.frame
    end

    local frame = CreateFrame("Frame", "CaerdonWardrobeLayoutEditorFrame", UIParent, "BackdropTemplate")
    frame:SetSize(548, BASE_HEIGHT)
    -- Left of center, so bags on the right of the screen stay in view.
    frame:SetPoint("CENTER", UIParent, "CENTER", -300, 60)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.07, 0.07, 0.1, 0.95)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(dragged) dragged:StartMoving() end)
    frame:SetScript("OnDragStop", function(dragged) dragged:StopMovingOrSizing() end)
    frame:SetScript("OnHide", function()
        self:OnClosed()
    end)
    frame:Hide()
    -- Escape closes it.
    if UISpecialFrames then
        table.insert(UISpecialFrames, frame:GetName())
    end
    self.frame = frame

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -14)
    title:SetText("Caerdon Wardrobe: Layout")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    close:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        GameTooltip:SetText("Close", 1, 1, 1)
        GameTooltip:AddLine("Closes the editor. If you changed anything, you are asked whether to keep it.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    close:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.close = close

    -- The large slot: a real 37 px slot in a frame scaled up, with room around it for an icon
    -- that hangs over the corner.
    local box = CreateFrame("Frame", nil, frame)
    box:SetSize(200, 200)
    box:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -44)
    local boxBackground = box:CreateTexture(nil, "BACKGROUND")
    boxBackground:SetAllPoints()
    boxBackground:SetColorTexture(0, 0, 0, 0.45)

    local holder = CreateFrame("Frame", nil, box)
    holder:SetSize(SLOT_SIZE, SLOT_SIZE)
    holder:SetScale(PREVIEW_SCALE)
    holder:SetPoint("CENTER", box, "CENTER", 0, 0)
    self.bigButton = self:CreateSampleButton(holder)
    self.bigButton:SetPoint("CENTER", holder, "CENTER", 0, 0)
    self:SetSample(self.bigButton, self:GetLargeSample())

    CreateLabel(frame, "GameFontHighlightSmall", "Click a part of the slot, or pick it on the right.", 20, -250, 200)

    -- Which part is being edited: a button each, the chosen one underlined. Placed by
    -- RefreshSelection, which leaves out the parts that are switched off.
    self.tabs = {}
    for _, part in ipairs(PARTS) do
        local tab = CreateTextButton(frame, part.label, part.width, TABS_LEFT, TABS_TOP, function()
            self:SelectPart(part.key)
        end)
        tab.underline = frame:CreateTexture(nil, "OVERLAY")
        tab.underline:SetColorTexture(1, 0.82, 0, 1)
        tab.underline:SetPoint("TOPLEFT", tab, "BOTTOMLEFT", 4, -1)
        tab.underline:SetPoint("TOPRIGHT", tab, "BOTTOMRIGHT", -4, -1)
        tab.underline:SetHeight(2)
        tab.underline:Hide()
        self.tabs[part.key] = tab
    end

    -- Position: nine squares laid out like the slot.
    CreateLabel(frame, "GameFontNormal", "Position", 240, -80)
    self.cells = {}
    for index, anchor in ipairs(ANCHORS) do
        local column, row = (index - 1) % 3, math.floor((index - 1) / 3)
        local cell = CreateFrame("Button", nil, frame)
        cell:SetSize(22, 22)
        cell:SetPoint("TOPLEFT", frame, "TOPLEFT", 240 + column * 24, -100 - row * 24)
        cell.fill = cell:CreateTexture(nil, "BACKGROUND")
        cell.fill:SetAllPoints()
        local hover = cell:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.25)
        cell:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            self:SetPosition(anchor.value)
        end)
        cell:SetScript("OnEnter", function(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetText(anchor.name, 1, 1, 1)
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.cells[anchor.value] = cell
    end

    -- Size
    CreateLabel(frame, "GameFontNormal", "Size", 336, -80)
    self.size = CreateStepper(frame, 336, -100, function(direction) self:StepSize(direction) end)

    -- Why the text is not exactly where its anchor says.
    self.movedNote = CreateLabel(frame, "GameFontHighlightSmall", "", 336, -132, 196)
    self.movedNote:Hide()

    -- Nudge: four buttons in a cross.
    CreateLabel(frame, "GameFontNormal", "Nudge", 240, -184)
    self.nudge = {
        up = CreateTextButton(frame, "^", 24, 264, -204, function() self:Nudge(0, 1) end),
        left = CreateTextButton(frame, "<", 24, 240, -228, function() self:Nudge(-1, 0) end),
        right = CreateTextButton(frame, ">", 24, 288, -228, function() self:Nudge(1, 0) end),
        down = CreateTextButton(frame, "v", 24, 264, -252, function() self:Nudge(0, -1) end),
    }
    self.nudgeValue = CreateLabel(frame, "GameFontHighlight", "", 336, -209, 190)
    self.nudgeClear = CreateTextButton(frame, "Clear", 60, 336, -228, function() self:ClearNudge() end)

    -- True-size examples, which also choose what the large slot shows.
    CreateLabel(frame, "GameFontNormal", "Actual size, in a standard slot. Click one to see it large.", 20, -288)
    local stripFrame, _, strip = self:CreateSampleStrip(frame, {
        captions = true,
        onClick = function(index) self:ShowLarge(index) end
    })
    stripFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -304)
    self.strip = strip

    CreateLabel(frame, "GameFontHighlightSmall",
        "Lists that fit the icon into a row, such as auction results and recipes, keep their own layout. " ..
        "Parts you have switched off on the Icons page are left out here.",
        20, -380, 508)

    self.resetPart = CreateTextButton(frame, "Reset this part", 126, 20, -422, function() self:ResetSelected() end,
        "Puts the selected part back to the addon's default position and size, with no nudge.")
    self.resetAll = CreateTextButton(frame, "Reset everything", 126, 150, -422, function() self:ResetAll() end,
        "Puts every part back to the addon's defaults: icon top left, texts at the bottom, level gain bottom right, all at 100%.")
    self.undo = CreateTextButton(frame, "Undo changes", 116, 280, -422, function() self:UndoChanges() end,
        "Puts every part back to how it was when you opened this window.")
    self.done = CreateTextButton(frame, "Done", 90, 438, -422, function() self:Finish() end,
        "Keeps your changes and closes the editor.")

    -- The notes of installed addons go under the hint and the window grows by their height
    -- (RefreshIntegrationNotes), so the buttons hang from its bottom edge.
    self.integrationNotes = CreateLabel(frame, "GameFontHighlightSmall", "", 20, -410, 508)
    self.integrationNotes:Hide()
    for button, x in pairs({ [self.resetPart] = 20, [self.resetAll] = 150, [self.undo] = 280, [self.done] = 438 }) do
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, 14)
    end

    return frame
end

function Editor:OnSamplesDrawn()
    self:EnsureCatchers()
    self:RefreshNotes()
end

-- Text moves clear of a number that shares its row (the level gain, or a stack count). Say so,
-- or its place looks wrong for the anchor that is lit. Only known once the slot has been drawn.
local MOVED_NOTES = {
    gain = "Moved clear of the level gain, which is on the same row and keeps its place.",
    count = "Raised above the stack count.",
}

function Editor:RefreshNotes()
    if not (self.movedNote and self.bigButton) then
        return
    end
    local key = self:GetPart().key
    local overlay = CaerdonWardrobe:GetCaerdonButton(self.bigButton)
    local note = (key == "text" or key == "gear") and overlay and MOVED_NOTES[overlay.bindingTextMovedFor or ""]
    if note then
        self.movedNote:SetText(note)
    end
    self.movedNote:SetShown(note and true or false)
end

function Editor:RefreshIntegrationNotes()
    local notes = IntegrationNotes()
    local label = self.integrationNotes
    label:SetText(table.concat(notes, "\n"))
    label:SetShown(#notes > 0)
    local extra = 0
    if #notes > 0 then
        -- A string that has never been on screen can report no height; a line each is the least.
        extra = math.max(label:GetStringHeight() or 0, #notes * 11) + 8
    end
    self.frame:SetHeight(BASE_HEIGHT + extra)
end

-- Makes the parts of the large slot clickable. They exist once the slot has been drawn.
function Editor:EnsureCatchers()
    if self.catchers or not self.bigButton then
        return
    end
    local overlay = CaerdonWardrobe:GetCaerdonButton(self.bigButton)
    if not (overlay and overlay.mogStatus and overlay.bindsOnText and overlay.upgradeDeltaText) then
        return
    end

    -- The text region carries the binding text or a gear set's name, whichever the example shows.
    self.catchers = {}
    local regions = { icon = overlay.mogStatus, text = overlay.bindsOnText, delta = overlay.upgradeDeltaText }
    for key, region in pairs(regions) do
        local catcher = CreateFrame("Button", nil, self.bigButton)
        catcher:SetAllPoints(region)
        catcher:SetFrameLevel(overlay:GetFrameLevel() + 10)
        -- An outline, not a fill: the part has to keep looking the way it will on a slot. The
        -- catcher sits inside the scaled-up slot, so half a unit is two pixels on screen.
        catcher.selected = CreateOutline(catcher, 0.5)
        local hover = catcher:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.25)
        catcher:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            if key == "text" and self:GetLargeSample().has.gear then
                self:SelectPart("gear")
            else
                self:SelectPart(key)
            end
        end)
        self.catchers[key] = catcher
    end
    self:RefreshSelection()
end

function Editor:RefreshSelection()
    local selected = self:GetPart().key
    local enabled = EnabledParts()

    -- A button for each part that is switched on, packed from the left.
    if self.tabs then
        local x = TABS_LEFT
        for _, part in ipairs(PARTS) do
            local tab = self.tabs[part.key]
            local shown = enabled[part.key] and true or false
            tab:SetShown(shown)
            if shown then
                tab:ClearAllPoints()
                tab:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, TABS_TOP)
                x = x + part.width + 2
            end
            if part.key == selected then
                tab:LockHighlight()
            else
                tab:UnlockHighlight()
            end
            tab.underline:SetShown(shown and part.key == selected)
        end
    end

    local sample = self:GetLargeSample()
    if self.catchers then
        for key, catcher in pairs(self.catchers) do
            -- Only the parts this example shows can be clicked on it. Its text is the gear set's
            -- name on the gear set example.
            local part = (key == "text" and sample.has.gear) and "gear" or key
            catcher:SetShown(sample.has[part] and true or false)
            catcher.selected:SetShown(part == selected)
        end
    end
    if self.strip then
        for index, outline in pairs(self.strip.outlines) do
            outline:SetShown(index == (self.large or ALL_PARTS_SAMPLE))
        end
    end
end

-- Shows the selected part's settings and draws the samples again.
function Editor:Refresh()
    if not self.frame then
        self:RedrawSamples()
        return
    end

    self:Normalize()
    local settings = self:GetPart().settings()

    for anchor, cell in pairs(self.cells) do
        if anchor == settings.Position then
            cell.fill:SetColorTexture(1, 0.82, 0, 1)
        else
            cell.fill:SetColorTexture(0.28, 0.28, 0.3, 0.95)
        end
    end

    self.size.value:SetText(string.format("%d%%", tonumber(settings.Scale) or 100))
    self.nudgeValue:SetText(DescribeNudge(tonumber(settings.OffsetX) or 0, tonumber(settings.OffsetY) or 0))

    self:RefreshSelection()
    self:RefreshIntegrationNotes()
    self:RedrawSamples()
end

function Editor:Open()
    if not CaerdonWardrobeConfig then
        return
    end
    local frame = self:GetFrame()
    if self.pendingClose then
        -- Reopened while "keep the changes?" was still up: back to editing, same starting point.
        self.pendingClose = nil
        if StaticPopup_Hide then
            StaticPopup_Hide(KEEP_DIALOG)
        end
    else
        self:TakeSnapshot()
    end
    -- The settings window covers most of the screen; step out of it so the bags can be seen.
    pcall(function()
        if SettingsPanel and SettingsPanel:IsShown() then
            HideUIPanel(SettingsPanel)
        end
    end)
    frame:Show()
    pcall(function()
        if OpenAllBags then
            OpenAllBags()
        end
    end)
    self:Refresh()
end

function Editor:Toggle()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Open()
    end
end

SLASH_CAERDONLAYOUT1 = "/caerdonlayout"
SlashCmdList["CAERDONLAYOUT"] = function()
    Editor:Toggle()
end
