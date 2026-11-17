-- EQUIPPED_LAST=500 -- TODO: Temp fix for bag opening

local DEBUG_ENABLED = false
-- local DEBUG_ITEM = 82800
local ADDON_NAME, NS = ...
local L = NS.L

BINDING_HEADER_CAERDON = L["Caerdon Addons"]
BINDING_NAME_COPYMOUSEOVERLINK = L["Copy Mouseover Link"]
BINDING_NAME_PRINTMOUSEOVERLINKDETAILS = L["Print Mouseover Link Details"]
BINDING_NAME_CAERDONDEBUGHOVER = L["Open Debug for Hovered Item"]

-- Counters for the Debug Frame export and the test addon (CaerdonCounters.lua).
local Counters = CaerdonCounters
local milestones = Counters.milestones

local availableFeatures = {}
local registeredFeatures = {}
local eventFeatureHandlers = {} -- event name -> list of {instance, handler}

-- One failure must not take its neighbours with it: a feature's Init, Refresh and event
-- handlers and the draw of each item run through this. The error still goes to the game's
-- error handler, so it is reported like any other. Returns false when the call raised one.
local function Contained(func, ...)
    return xpcall(func, geterrorhandler(), ...)
end

CaerdonWardrobeMixin = {}

local buttonState = setmetatable({}, { __mode = "k" })

local function GetButtonState(originalButton, create)
    if not originalButton then
        return nil
    end

    local state = buttonState[originalButton]
    if not state and create then
        state = {}
        buttonState[originalButton] = state
    end

    return state
end

function CaerdonWardrobeMixin:GetCaerdonButton(originalButton)
    local state = GetButtonState(originalButton)
    return state and state.caerdonButton
end

function CaerdonWardrobeMixin:EnsureCaerdonButton(originalButton)
    local state = GetButtonState(originalButton, true)
    if not state.caerdonButton then
        local frame = CreateFrame("Frame", nil, originalButton)
        frame:SetAllPoints(originalButton)
        frame.searchOverlay = originalButton.searchOverlay
        state.caerdonButton = frame
    end

    return state.caerdonButton
end

function CaerdonWardrobeMixin:SetButtonLocationKey(originalButton, locationKey)
    local state = GetButtonState(originalButton, locationKey ~= nil)
    if state then
        state.locationKey = locationKey
    end
end

function CaerdonWardrobeMixin:GetButtonLocationKey(originalButton)
    local state = GetButtonState(originalButton)
    return state and state.locationKey
end

function CaerdonWardrobeMixin:SetButtonItemID(originalButton, itemID)
    local state = GetButtonState(originalButton, itemID ~= nil)
    if state then
        state.itemID = itemID
    end
end

function CaerdonWardrobeMixin:GetButtonItemID(originalButton)
    local state = GetButtonState(originalButton)
    return state and state.itemID
end

function CaerdonWardrobeMixin:SetButtonStackCount(originalButton, stackCount)
    local state = GetButtonState(originalButton, stackCount ~= nil)
    if state then
        state.stackCount = stackCount
    end
end

function CaerdonWardrobeMixin:GetButtonStackCount(originalButton)
    local state = GetButtonState(originalButton)
    return state and state.stackCount
end

function CaerdonWardrobeMixin:ClearButtonState(originalButton)
    local state = GetButtonState(originalButton)
    if state then
        state.locationKey = nil
        state.itemID = nil
        state.stackCount = nil
        state.refreshGeneration = nil
        state.notReadyRetries = nil
        state.retryingNotReady = nil
    end
end

function CaerdonWardrobeMixin:SetButtonRefreshGeneration(originalButton, generation)
    local state = GetButtonState(originalButton, generation ~= nil)
    if state then
        state.refreshGeneration = generation
    end
end

function CaerdonWardrobeMixin:GetButtonRefreshGeneration(originalButton)
    local state = GetButtonState(originalButton)
    return state and state.refreshGeneration
end

function CaerdonWardrobeMixin:GetRefreshGeneration()
    return self.refreshGeneration
end

function CaerdonWardrobeMixin:OnLoad()
    -- AddonCompartmentFrame:RegisterAddon({
    -- 	text = 'Caerdon Wardrobe',
    -- 	func = function ()
    -- 		print("Do your thing here")
    -- 	end,
    -- 	icon = "Interface\\Store\\category-icon-featured"
    -- })

    self.waitingToProcess = {}
    self.processQueue = {}
    self.featureProcessContinuables = {}
    self.featureProcessItems = {}
    self.refreshGeneration = 0

    self:RegisterEvent "ADDON_LOADED"
    self:RegisterEvent "PLAYER_LOGOUT"
    self:RegisterEvent "PLAYER_ENTERING_WORLD"
    self:RegisterEvent "TRANSMOG_COLLECTION_UPDATED"
    -- The per-source events are the direct "this source was just learned / lost" signal,
    -- so refresh on them too rather than depending on TRANSMOG_COLLECTION_UPDATED always
    -- accompanying them (on WoW Forever an appearance is also learned by selling the item).
    self:RegisterEvent "TRANSMOG_COLLECTION_SOURCE_ADDED"
    self:RegisterEvent "TRANSMOG_COLLECTION_SOURCE_REMOVED"
    self:RegisterEvent "TRANSMOG_COSMETIC_COLLECTION_SOURCE_ADDED"
    self:RegisterEvent "EQUIPMENT_SETS_CHANGED"
    -- UPDATE_EXPANSION_LEVEL is undocumented and only used by retail-only Blizzard
    -- code; WoW Forever (Camelot) may not know it, and registering an unknown
    -- event raises an error that would abort OnLoad.
    pcall(self.RegisterEvent, self, "UPDATE_EXPANSION_LEVEL")
    self:RegisterEvent "VARIABLES_LOADED"
    self:RegisterEvent "NEW_RECIPE_LEARNED"
    -- Skill lines, the player's flags and the housing events are not here: each also comes
    -- when nothing changed, so the watcher compares before it refreshes (CaerdonRefresh.lua).
    self:RegisterEvent "PLAYER_EQUIPMENT_CHANGED"
    self:RegisterEvent "EQUIPMENT_SWAP_FINISHED"
    self:RegisterEvent "NEW_MOUNT_ADDED"
    self:RegisterEvent "NEW_TOY_ADDED"
    self:RegisterEvent "NEW_PET_ADDED"
    self:RegisterEvent "PLAYER_REGEN_ENABLED"
    -- Talent points decide which Pawn scale counts as the toon's own on clients without
    -- specializations (see OnTalentsChanged). pcall: not every client knows every event.
    for _, talentEvent in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED",
        "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE" }) do
        if pcall(self.RegisterEvent, self, talentEvent) then
            self[talentEvent] = self.OnTalentsChanged
        end
    end

    hooksecurefunc("EquipPendingItem", function(...) self:OnEquipPendingItem(...) end)
end

-- The binding text is one of these labels or an equipment set's name; anything else is a set.
-- Every label has to be listed: one that is missing is drawn with the gear set's layout, colour
-- and switches instead of the binding text's.
local BINDING_LABELS = {
    [L["BoA"]] = true,
    [L["BoE"]] = true,
    [L["WuE"]] = true,
}
local function IsGearSetStatus(status, item)
    return status and status ~= "" and not BINDING_LABELS[status]
end

local ICON_PROMINENT_SIZE = 20
local ICON_SIZE_DIFFERENTIAL = 0.8
-- The small upgrade arrow on another icon (an upgrade that also has a look to learn): its ring
-- as a share of that icon's size, the arrow as a share of the ring, and how far the ring's
-- center sits inside the icon's corner, as a share of the ring.
local UPGRADE_BADGE_SCALE = 0.65
local UPGRADE_BADGE_ARROW = 0.7
local UPGRADE_BADGE_OVERLAP = 0.4
-- The circle a ring icon is clipped to where its shadow would show (options.roundStatusIcon), as
-- a share of the icon's size. The ring measures 0.88 of it. Nothing of the shadow may be left:
-- it is a drop shadow, heavier below, and a rim of it swings around as the icon turns.
local RING_ICON_CLIP = 0.9
-- The slot the default sizes were made for: a Blizzard bag slot.
local REFERENCE_SLOT_SIZE = 37
-- Below the first the icon stops being readable (the 20 px rows of the auction and profession
-- lists), above the second it only gets in the way (the 54 px auction sell slot). Both are the
-- sizes that had been picked by eye for those windows.
local SLOT_STATUS_MIN_SIZE = 13
local SLOT_STATUS_MAX_SIZE = 24

-- The statusProminentSize that gives a square frame of this size the look of a default Blizzard
-- bag slot (a 20 px icon on 37 px), kept between the smallest readable and the largest useful
-- size. nil when the frame has no size yet, which leaves the default in place. For windows whose
-- slots are not 37 px; pass the size of the frame the overlay sits on.
--
-- noMaximum is for bag slots whose size the player sets in the bag addon: someone who asks for
-- big slots gets an icon to match, however big.
function CaerdonWardrobeMixin:GetSlotStatusSize(width, height, noMaximum)
    local side = math.min(width or 0, height or 0)
    if side < 1 then
        return nil
    end
    local size = ICON_PROMINENT_SIZE * side / REFERENCE_SLOT_SIZE
    if not noMaximum then
        size = math.min(SLOT_STATUS_MAX_SIZE, size)
    end
    return math.max(SLOT_STATUS_MIN_SIZE, size)
end

-- Clip-aware placement, for callers that pass options.keepInsideWhenClipped.
--
-- The default placement hangs the status icon over the slot's corner. In a scrolling grid with
-- no padding (the classic BetterBags bags) the first column's icons get that part cut off by the
-- scroll frame. Whether that happens cannot be known while the button is drawn: frames often have
-- no layout yet, and the answer has to be the same for every slot of the grid. So the button is
-- drawn as usual, a pass shortly after measures how much room its grid leaves to the left and
-- right, and when that is less than the overhang every icon in that grid is placed inside its
-- slot instead. Inside, the icon would cover more of the item than it does hanging over the
-- corner, so it is also drawn smaller (CLIP_INSIDE_SCALE).
--
-- Only horizontal room is used: in a list that scrolls vertically it does not change with the
-- scroll position, while a row passing the top edge has no room above it in any list.
local CLIP_PASS_DELAY = 0.1
local CLIP_MAX_PARENT_DEPTH = 40
local CLIP_INSIDE_MARGIN = 0.5
-- Size of an icon that had to move inside, as a fraction of its usual size. Covering exactly what
-- the overhanging icon covers would be 0.7 with the default inset (14 px for a 20 px icon), which
-- read as too small in game; 0.8 gives the 16 px that the BetterBags integration used for years.
local CLIP_INSIDE_SCALE = 0.8
-- [clipping frame] = { left = least room seen, right = least room seen, buttons = weak set of overlay frames }
local clipRoom = setmetatable({}, { __mode = "k" })
local clipPending = {}
local clipPassScheduled = false

-- The closest frame, starting with the button itself, that cuts off what is drawn outside it.
local function FindClippingParent(frame)
    local depth = 0
    while frame and depth < CLIP_MAX_PARENT_DEPTH do
        if (frame.DoesClipChildren and frame:DoesClipChildren()) or
            (frame.GetObjectType and frame:GetObjectType() == "ScrollFrame") then
            return frame
        end
        frame = frame.GetParent and frame:GetParent()
        depth = depth + 1
    end
    return nil
end

local function GetScreenEdges(region)
    local left, bottom, width, height = region:GetScaledRect()
    if not (left and bottom and width and height) or width <= 0 or height <= 0 then
        return nil
    end
    return left, left + width
end

-- Measures the room around one drawn button and files it under its clipping frame. Marks the
-- frame in "changed" when its least room went down.
local function MeasureClipRoom(caerdonButton, button, changed)
    caerdonButton.caerdonClipMeasured = true
    local clipper = FindClippingParent(button)
    caerdonButton.caerdonClipper = clipper
    if not clipper then
        return
    end

    local scale = caerdonButton:GetEffectiveScale()
    local overlayLeft, overlayRight = GetScreenEdges(caerdonButton)
    local clipLeft, clipRight = GetScreenEdges(clipper)
    if not (overlayLeft and clipLeft and scale and scale > 0) then
        caerdonButton.caerdonClipMeasured = nil -- no layout yet: measure on a later draw
        return
    end

    local info = clipRoom[clipper]
    if not info then
        info = { buttons = setmetatable({}, { __mode = "k" }) }
        clipRoom[clipper] = info
    end
    info.buttons[caerdonButton] = true

    local left = (overlayLeft - clipLeft) / scale
    local right = (clipRight - overlayRight) / scale
    if left < -0.5 or right < -0.5 then
        -- Partly outside the grid: caught mid-move or mid-resize, and cut off itself. The least
        -- room is remembered for the session, so a position like this must not set it.
        caerdonButton.caerdonClipMeasured = nil
        return
    end
    if info.left == nil or left < info.left - 0.25 then
        info.left = left
        changed[clipper] = true
    end
    if info.right == nil or right < info.right - 0.25 then
        info.right = right
        changed[clipper] = true
    end
end

local function RepositionForClip(caerdonButton)
    local args = caerdonButton.caerdonPositionArgs
    if args and args.icon then
        CaerdonWardrobe:SetStatusIconPosition(args.icon, args.button, args.item, args.feature, args.locationInfo,
            args.options, args.mogStatus, args.bindingStatus)
    end
end

local function RunClipPass()
    clipPassScheduled = false
    local batch = clipPending
    clipPending = {}

    local changed, reposition = {}, {}
    for caerdonButton in pairs(batch) do
        local args = caerdonButton.caerdonPositionArgs
        local button = args and args.button
        -- A hidden button can sit anywhere (pooled frames); it is measured when it is drawn visible.
        if button and button.IsVisible and button:IsVisible() then
            local ok, err = pcall(MeasureClipRoom, caerdonButton, button, changed)
            if not ok then
                caerdonButton.caerdonClipMeasured = nil
                geterrorhandler()(err)
            elseif caerdonButton.caerdonClipper then
                reposition[caerdonButton] = true
            end
        end
    end

    -- Less room than before changes the answer for every icon already placed in that grid.
    for clipper in pairs(changed) do
        for caerdonButton in pairs(clipRoom[clipper].buttons) do
            if caerdonButton.caerdonClipper == clipper then
                reposition[caerdonButton] = true
            end
        end
    end
    for caerdonButton in pairs(reposition) do
        local ok, err = pcall(RepositionForClip, caerdonButton)
        if not ok then
            geterrorhandler()(err)
        end
    end
end

-- Keeps what is needed to place this icon again, and has the button measured unless it already
-- was under this clipping frame. The frame is looked up on every draw: buttons are pooled, and a
-- bag addon can move a whole grid's worth of them under another frame without touching the
-- button's own parent.
local function QueueClipPass(caerdonButton, clipper, icon, button, item, feature, locationInfo, options, mogStatus,
                             bindingStatus)
    local args = caerdonButton.caerdonPositionArgs
    if not args then
        args = {}
        caerdonButton.caerdonPositionArgs = args
    end
    args.icon, args.button, args.item, args.feature = icon, button, item, feature
    args.locationInfo, args.options, args.mogStatus, args.bindingStatus = locationInfo, options, mogStatus, bindingStatus

    if caerdonButton.caerdonClipMeasured and caerdonButton.caerdonClipper == clipper then
        return
    end

    clipPending[caerdonButton] = true
    if not clipPassScheduled then
        clipPassScheduled = true
        C_Timer.After(CLIP_PASS_DELAY, RunClipPass)
    end
end

-- nil while this icon can hang over its corner (the grid leaves room, has not been measured, or
-- the icon does not overhang). Otherwise the icon goes inside the slot, and this is the fraction
-- of its size to draw it at.
local function GetClipInsideScale(clipper, statusPosition, extent, xOffset)
    local info = clipper and clipRoom[clipper]
    if not info then
        return nil
    end

    local room
    if string.find(statusPosition, "LEFT") then
        room = info.left
    elseif string.find(statusPosition, "RIGHT") then
        room = info.right
    end
    if not room then
        return nil
    end

    local overhang = extent / 2 - xOffset
    if overhang > 0.5 and room < overhang - 0.5 then
        return CLIP_INSIDE_SCALE
    end
    return nil
end

-- The player's own layout (Display settings): where the status icon and the texts sit on a slot,
-- how big they are, and a nudge. It applies on top of each window's own values, and not at all
-- where a window fits them by hand into a row: options.fixedLayout, or an overridden position.
local function PercentToScale(value)
    local percent = tonumber(value)
    if not percent or percent <= 0 then
        return 1
    end
    return percent / 100
end

-- Returns the anchor, the size factor, the nudge to the right and upwards (in pixels on a slot
-- with a 20 px icon), and whether the window fits the icon by hand.
local function GetIconLayout(options)
    local config = CaerdonWardrobeConfig.Icon
    if options.fixedLayout or options.overrideStatusPosition then
        return options.overrideStatusPosition or config.Position or "TOPLEFT", 1, 0, 0, true
    end
    return config.Position or "TOPLEFT", PercentToScale(config.Scale), tonumber(config.OffsetX) or 0,
        tonumber(config.OffsetY) or 0, false
end

-- The same for the text on a slot. A slot shows either the binding text or a gear set's name,
-- never both, and each has its own layout (Binding and Binding.GearSet).
local function GetTextLayout(options, isGearSet)
    local config = CaerdonWardrobeConfig.Binding
    if options.fixedLayout or options.overrideBindingPosition then
        return options.overrideBindingPosition or config.Position or "BOTTOM", 1, 0, 0, true
    end
    local layout = config
    if isGearSet and type(config.GearSet) == "table" then
        layout = config.GearSet
    end
    return layout.Position or config.Position or "BOTTOM", PercentToScale(layout.Scale),
        tonumber(layout.OffsetX) or 0, tonumber(layout.OffsetY) or 0, false
end

-- The status icon's size before a minor icon is reduced: the window's own, times the player's.
function CaerdonWardrobeMixin:GetStatusBaseSize(options)
    local _, scale = GetIconLayout(options)
    return (options.statusProminentSize or ICON_PROMINENT_SIZE) * scale
end

function CaerdonWardrobeMixin:SetStatusIconPosition(icon, button, item, feature, locationInfo, options, mogStatus,
                                                    bindingStatus)
    if not item then return end

    local caerdonButton = self:GetCaerdonButton(button)
    if not caerdonButton then
        return
    end

    local statusScale = options.statusScale or 1
    local statusPosition, _, nudgeX, nudgeY, handFitted = GetIconLayout(options)
    local onSide = string.find(statusPosition, "LEFT") or string.find(statusPosition, "RIGHT")
    local onTopOrBottom = string.find(statusPosition, "TOP") or string.find(statusPosition, "BOTTOM")

    -- Clip-aware callers: decide from the icon's full size whether it has to go inside the slot,
    -- and size it for that before anything below reads its size. The full size is kept on the
    -- icon so placing it again (the pass after drawing) never shrinks it twice.
    local clipInsideScale
    if options.keepInsideWhenClipped and not options.fixedStatusPosition then
        local clipBackground = icon.mogStatusBackground
        local baseSize = icon.caerdonBaseSize or icon:GetSize()
        local baseBackgroundSize = icon.caerdonBaseBackgroundSize or (clipBackground and clipBackground:GetSize()) or baseSize
        icon.caerdonBaseSize, icon.caerdonBaseBackgroundSize = baseSize, baseBackgroundSize

        local clipper = FindClippingParent(button)
        local baseXOffset = options.statusOffsetX or (4 * baseSize / ICON_PROMINENT_SIZE)
        clipInsideScale = GetClipInsideScale(clipper, statusPosition, math.max(baseSize, baseBackgroundSize), baseXOffset)

        local sizeScale = clipInsideScale or 1
        icon:SetSize(baseSize * sizeScale, baseSize * sizeScale)
        if clipBackground then
            clipBackground:SetSize(baseBackgroundSize * sizeScale, baseBackgroundSize * sizeScale)
        end

        QueueClipPass(caerdonButton, clipper, icon, button, item, feature, locationInfo, options, mogStatus, bindingStatus)
    end

    -- Scaling values if the icon is different than prominent-sized
    local iconWidth, iconHeight = icon:GetSize()

    if icon.caerdonRingMask then
        icon.caerdonRingMask:SetSize(iconWidth * RING_ICON_CLIP, iconHeight * RING_ICON_CLIP)
    end
    local xAdjust = iconWidth / ICON_PROMINENT_SIZE
    local yAdjust = iconHeight / ICON_PROMINENT_SIZE

    -- The inset from the anchor's edge: none along an axis the anchor is centered on. A window's
    -- own inset is made for a corner, so it follows the same rule, except where the window also
    -- chose the anchor itself and its numbers mean exactly what they say.
    local xOffset = onSide and 4 * xAdjust or 0
    if options.statusOffsetX ~= nil and (onSide or handFitted) then
        xOffset = options.statusOffsetX
    end

    local yOffset = onTopOrBottom and 4 * yAdjust or 0
    if options.statusOffsetY ~= nil and (onTopOrBottom or handFitted) then
        yOffset = options.statusOffsetY
    end

    if clipInsideScale then
        -- Fully inside: the (now smaller) icon and its background end just short of the slot's edges.
        local insideWidth, insideHeight = iconWidth, iconHeight
        local clipBackground = icon.mogStatusBackground
        if clipBackground then
            local backgroundWidth, backgroundHeight = clipBackground:GetSize()
            insideWidth = math.max(insideWidth, backgroundWidth or 0)
            insideHeight = math.max(insideHeight, backgroundHeight or 0)
        end
        xOffset = insideWidth / 2 + CLIP_INSIDE_MARGIN
        if string.find(statusPosition, "TOP") or string.find(statusPosition, "BOTTOM") then
            yOffset = insideHeight / 2 + CLIP_INSIDE_MARGIN
        end
    end

    if string.find(statusPosition, "TOP") then
        yOffset = yOffset * -1
    end

    if string.find(statusPosition, "RIGHT") then
        xOffset = xOffset * -1
    end

    -- The player's nudge: in the directions of the screen, and in step with the icon's size so
    -- it is the same share of a small slot as of a large one.
    xOffset = xOffset + nudgeX * xAdjust
    yOffset = yOffset + nudgeY * yAdjust

    local xBackgroundOffset = icon.caerdonBackgroundNudge or 0
    if options.statusBackgroundOffsetX ~= nil then
        xBackgroundOffset = options.statusBackgroundOffsetX
    end

    local yBackgroundOffset = icon.caerdonBackgroundNudge or 0
    if options.statusBackgroundOffsetY ~= nil then
        yBackgroundOffset = options.statusBackgroundOffsetY
    end

    local background = icon.mogStatusBackground
    if background then
        local parent = icon:GetParent()
        if parent and background:GetParent() ~= parent then
            background:SetParent(parent)
        end

    end
    if not options.fixedStatusPosition then
        if background then
            background:ClearAllPoints()
            background:SetPoint("CENTER", caerdonButton, statusPosition, xOffset + xBackgroundOffset,
                yOffset + yBackgroundOffset)
        end

        icon:ClearAllPoints()
        icon:SetPoint("CENTER", caerdonButton, statusPosition, xOffset, yOffset)
    elseif background then
        background:ClearAllPoints()
        background:SetPoint("CENTER", icon)
    end

    -- The upgrade badge sits on the icon's corner that points into the slot, overlapping it a
    -- little, and is sized from the icon as it is now (smaller where the icon was moved inside).
    -- The corner comes from where the icon is really anchored, which in a host addon's bags is
    -- the host's choice, not the player's setting.
    local badge, ring = icon.upgradeBadge, icon.upgradeBadgeRing
    if badge and ring and icon.caerdonBadgeActive then
        local parent = icon:GetParent()
        if parent and badge:GetParent() ~= parent then
            ring:SetParent(parent)
            badge:SetParent(parent)
        end
        local _, _, anchoredTo = icon:GetPoint(1)
        anchoredTo = anchoredTo or statusPosition
        local size = (icon:GetWidth() or 0) * UPGRADE_BADGE_SCALE
        local towardsRight = not string.find(anchoredTo, "RIGHT")
        local towardsBottom = not string.find(anchoredTo, "BOTTOM")
        local overlap = size * UPGRADE_BADGE_OVERLAP
        ring:SetSize(size, size)
        badge:SetSize(size * UPGRADE_BADGE_ARROW, size * UPGRADE_BADGE_ARROW)
        ring:ClearAllPoints()
        ring:SetPoint("CENTER", icon, (towardsBottom and "BOTTOM" or "TOP") .. (towardsRight and "RIGHT" or "LEFT"),
            towardsRight and -overlap or overlap, towardsBottom and overlap or -overlap)
        badge:ClearAllPoints()
        badge:SetPoint("CENTER", ring, "CENTER", 0, 0)
    end
end

function CaerdonWardrobeMixin:AddRotation(group, order, degrees, duration, smoothing, startDelay, endDelay)
    local anim = group:CreateAnimation("Rotation")
    group["anim" .. order] = anim
    anim:SetDegrees(degrees)
    anim:SetDuration(duration)
    anim:SetOrder(order)
    anim:SetSmoothing(smoothing)

    if startDelay then
        anim:SetStartDelay(startDelay)
    end

    if endDelay then
        anim:SetEndDelay(endDelay)
    end
end

function CaerdonWardrobeMixin:SetItemButtonMogStatusFilter(originalButton, isFiltered)
    local caerdonButton = self:GetCaerdonButton(originalButton)
    if caerdonButton then
        local mogStatus = caerdonButton.mogStatus
        if mogStatus then
            local mogStatusBackground = mogStatus.mogStatusBackground
            -- A hidden icon has nothing to show, except where a host addon shows it later: there
            -- it is always hidden while it is drawn (Baganator shows it once it has heard that
            -- there is something to show), and it must keep the alpha it was drawn with. Clearing
            -- it here left the upgrade arrow invisible on a visible ring.
            if not mogStatus:IsShown() and not caerdonButton.caerdonHostPlacesParts then
                if mogStatusBackground then
                    mogStatusBackground:SetAlpha(0)
                end
                mogStatus:SetAlpha(0)
                mogStatus:SetDesaturated(false)
                return
            end

            local assignedAlpha = mogStatus.assignedAlpha or 1.0

            if isFiltered then
                mogStatusBackground:SetAlpha(0.3)
                mogStatus:SetAlpha(0.3)
            else
                mogStatusBackground:SetAlpha(assignedAlpha)
                mogStatus:SetAlpha(assignedAlpha)
            end
            if mogStatus.upgradeBadge then
                mogStatus.upgradeBadge:SetAlpha(isFiltered and 0.3 or assignedAlpha)
                mogStatus.upgradeBadgeRing:SetAlpha(isFiltered and 0.3 or assignedAlpha)
            end
        end

        local bindsOnText = caerdonButton.bindsOnText
        if bindsOnText then
            if isFiltered then
                bindsOnText:SetAlpha(0.3)
            else
                bindsOnText:SetAlpha(1.0)
            end
        end

        local upgradeDeltaText = caerdonButton.upgradeDeltaText
        if upgradeDeltaText then
            if isFiltered then
                upgradeDeltaText:SetAlpha(0.3)
            else
                upgradeDeltaText:SetAlpha(1.0)
            end
        end
    end
end

-- A slot that a bag search has dimmed gets its icon dimmed with it. The bag's own code can put
-- the search overlay on after the draw, in the same frame, so the overlay is looked at a frame
-- later: by one timer for every button drawn in that frame, where each draw used to start a
-- timer of its own. Only buttons that have a search overlay are noted.
local searchDimPending = {}
local searchDimScheduled = false

local function RunSearchDimPass()
    searchDimScheduled = false
    for caerdonButton in pairs(searchDimPending) do
        local mogStatus = caerdonButton.mogStatus
        if mogStatus and caerdonButton.searchOverlay:IsShown() then
            mogStatus.mogStatusBackground:SetAlpha(0.3)
            mogStatus:SetAlpha(0.3)
            if mogStatus.upgradeBadge then
                mogStatus.upgradeBadge:SetAlpha(0.3)
                mogStatus.upgradeBadgeRing:SetAlpha(0.3)
            end
        end
    end
    wipe(searchDimPending)
end

local function QueueSearchDim(caerdonButton)
    searchDimPending[caerdonButton] = true
    if not searchDimScheduled then
        searchDimScheduled = true
        C_Timer.After(0, RunSearchDimPass)
    end
end

-- options.hostPlacesParts: the addon whose buttons these are anchors the status icon, the binding
-- text and the level gain itself and decides which of them is visible (Baganator's corner
-- widgets). The drawing code then only fills them and sets their size: it never anchors, shows
-- or hides them. Noted on the overlay because a button is also cleared without options.
local function SetPartShown(caerdonButton, region, shown)
    if region and not (caerdonButton and caerdonButton.caerdonHostPlacesParts) then
        region:SetShown(shown)
    end
end

-- The helpers of SetItemButtonStatus. They are plain functions that are handed what they
-- need: as functions made inside it they were four new closures for every draw.

-- The store's category icons: a ring in the middle half of a 64 px texture. The crop is the
-- ring's square, which also cuts the shadow around it off square (see roundStatusIcon).
-- Returns true, for the caller's "this is a ring icon".
local function SetRingIcon(mogStatus, texture)
    mogStatus:SetTexCoord(16 / 64, 48 / 64, 16 / 64, 48 / 64)
    mogStatus:SetTexture(texture)
    return true
end

local function ApplyUpgradeArrowColor(arrow, transmogInfo, allowMismatchedSpecUpgrades, defaultR, defaultG, defaultB)
    if transmogInfo and transmogInfo.pawnOffTreeUpgrade then
        -- Pawn only rates it higher for another talent tree's scale: same "usable but
        -- off-spec" red as a loot spec mismatch. Hiding that scale in Pawn removes the arrow.
        arrow:SetVertexColor(1, 0.35, 0.35)
    elseif transmogInfo and transmogInfo.upgradeMatchesSpec == false and allowMismatchedSpecUpgrades then
        arrow:SetVertexColor(1, 0.35, 0.35)
    elseif transmogInfo and transmogInfo.pawnIdentifiedUpgrade then
        arrow:SetVertexColor(1, 1, 0)
    else
        arrow:SetVertexColor(defaultR, defaultG, defaultB)
    end
end

-- The level gain a piece's transmog info holds, when the setting and the window show one.
local function GetShownLevelGain(transmogInfo, levelGainAllowed)
    if not transmogInfo or not levelGainAllowed or not CaerdonWardrobeConfig.Icon.ShowUpgradeLevelDelta then
        return nil
    end
    local delta = transmogInfo.upgradeItemLevelDelta
    if delta and delta > 0 then
        return delta
    end
    return nil
end

-- Puts a gain ("+5") on the button, in this colour.
local function ShowLevelGain(core, originalButton, caerdonButton, anchorFrame, gain, r, g, b)
    local upgradeDeltaText = caerdonButton.upgradeDeltaText
    caerdonButton.upgradeDeltaAnchor = anchorFrame
    upgradeDeltaText:SetFormattedText("+%d", gain)
    upgradeDeltaText:SetTextColor(r, g, b)
    upgradeDeltaText:SetAlpha(1.0)
    SetPartShown(caerdonButton, upgradeDeltaText, true)
    core:UpdateUpgradeDeltaPosition(originalButton)
end

-- The upgrade icon: an arrow on a ring, with the level gain when there is one to show (gain).
-- lowSkill: the toon's level is not there yet. Returns whether the gain went on the button.
local function DrawUpgradeIcon(core, originalButton, caerdonButton, anchorFrame, lowSkill, transmogInfo,
                               allowMismatchedSpecUpgrades, gain)
    local mogStatus = caerdonButton.mogStatus
    local mogStatusBackground = mogStatus.mogStatusBackground
    mogStatusBackground:SetTexCoord((512 - 46 - 31) / 512, (512 - 31) / 512, 5 / 512, (5 + 46) / 512)
    mogStatusBackground:SetTexture("Interface\\HUD\\UIUnitFrameBoss2x")
    if lowSkill then
        mogStatusBackground:SetVertexColor(0.4, 1, 0)
    else
        mogStatusBackground:SetVertexColor(0, 1, 1)
    end

    mogStatus:SetTexCoord(-1 / 32, 33 / 32, -1 / 32, 33 / 32)
    mogStatus:SetTexture("Interface\\Buttons\\JumpUpArrow")
    ApplyUpgradeArrowColor(mogStatus, transmogInfo, allowMismatchedSpecUpgrades, 0.4, 1, 0.2)
    if not gain then
        return false
    end
    if lowSkill then
        ShowLevelGain(core, originalButton, caerdonButton, anchorFrame, gain, 0.9, 0.82, 0.1)
    else
        ShowLevelGain(core, originalButton, caerdonButton, anchorFrame, gain, 0.2, 1.0, 0.2)
    end
    return true
end

function CaerdonWardrobeMixin:SetupCaerdonButton(originalButton, item, feature, locationInfo, options)
    if not originalButton then
        return
    end

    local button = self:GetCaerdonButton(originalButton)
    local createdNew = false
    if not button then
        button = self:EnsureCaerdonButton(originalButton)
        createdNew = true
    end
    if options then
        button.caerdonHostPlacesParts = options.hostPlacesParts and true or false
    end

    if not button.mogStatus then
        local mogStatusBackground = button:CreateTexture(nil, "ARTWORK", nil, 1)
        local mogStatus = button:CreateTexture(nil, "ARTWORK", nil, 2)
        mogStatus.mogStatusBackground = mogStatusBackground
        button.mogStatus = mogStatus

        mogStatusBackground:SetAlpha(0)
        mogStatusBackground:Hide()
        mogStatus:SetAlpha(0)
        mogStatus:Hide()

        if not mogStatus._caerdonBackgroundHooked then
            mogStatus:HookScript("OnHide", function(statusTexture)
                local background = statusTexture.mogStatusBackground
                if background then
                    background._caerdonPrevAlpha = background:GetAlpha()
                    background:SetAlpha(0)
                    background:Hide()
                end
                if statusTexture.upgradeBadge then
                    statusTexture.upgradeBadge:Hide()
                    statusTexture.upgradeBadgeRing:Hide()
                end
            end)
            mogStatus:HookScript("OnShow", function(statusTexture)
                local background = statusTexture.mogStatusBackground
                if background then
                    background:Show()
                    local alpha = background._caerdonPrevAlpha
                    if alpha == nil or alpha == 0 then
                        alpha = statusTexture:GetAlpha()
                    end
                    if (alpha == nil or alpha == 0) then
                        alpha = statusTexture.assignedAlpha or 1
                    end
                    background:SetAlpha(alpha)
                    background._caerdonPrevAlpha = nil
                end
                if statusTexture.upgradeBadge and statusTexture.caerdonBadgeActive then
                    statusTexture.upgradeBadge:Show()
                    statusTexture.upgradeBadgeRing:Show()
                end
            end)
            mogStatus._caerdonBackgroundHooked = true
        end
    end

    if not button.bindsOnText then
        button.bindsOnText = button:CreateFontString(nil, "ARTWORK", "SystemFont_Outline_Small") -- TODO: Note: placing directly on button to enable search fade - need to check on other addons
    end

    if not button.upgradeDeltaText then
        button.upgradeDeltaText = button:CreateFontString(nil, "ARTWORK", "NumberFontNormalSmall")
        button.upgradeDeltaText:SetPoint("BOTTOMRIGHT", originalButton, "BOTTOMRIGHT", -2, 2)
        button.upgradeDeltaText:SetText("")
        button.upgradeDeltaText:Hide()
    end

    return button, createdNew
end

-- displayInfo: the feature's display rules when the caller already has them (ProcessItem asks
-- once for both this and SetItemButtonBindType); asked for here otherwise.
function CaerdonWardrobeMixin:SetItemButtonStatus(originalButton, item, feature, locationInfo, options, status,
                                                  bindingStatus, transmogInfo, displayInfo)
    local caerdonButton = self:GetCaerdonButton(originalButton)
    if not caerdonButton then
        return
    end

    -- Make sure it's sitting in front of the frame it's going to overlay
    local levelCheckFrame = originalButton
    if options and options.relativeFrame then
        if options.relativeFrame:GetObjectType() == "Texture" then
            levelCheckFrame = options.relativeFrame:GetParent()
        else
            levelCheckFrame = options.relativeFrame
        end
    end
    if levelCheckFrame then
        caerdonButton:SetFrameStrata(levelCheckFrame:GetFrameStrata())
        caerdonButton:SetFrameLevel(levelCheckFrame:GetFrameLevel() + 1)
    end

    caerdonButton:ClearAllPoints()
    caerdonButton:SetSize(0, 0)

    if options and options.relativeFrame then
        caerdonButton:SetAllPoints(options.relativeFrame)
    else
        caerdonButton:SetAllPoints(originalButton)
    end

    -- Had some addons messing with frame level resulting in this getting covered by the parent button.
    -- Haven't seen any negative issues with bumping it up, yet, but keep an eye on it if
    -- the status icon overlaps something it shouldn't.
    -- NOTE: Added logic above that hopefully addresses this more sanely...
    -- button:SetFrameLevel(originalButton:GetFrameLevel() + 100)

    local iconBackgroundAdjustment = 0
    local mogStatus = caerdonButton.mogStatus
    local mogStatusBackground
    if mogStatus then
        mogStatusBackground = mogStatus.mogStatusBackground
    end
    local mogAnim = caerdonButton.mogAnim
    local upgradeDeltaText = caerdonButton.upgradeDeltaText
    if upgradeDeltaText then
        upgradeDeltaText:SetText("")
        SetPartShown(caerdonButton, upgradeDeltaText, false)
    end
    if not options then
        options = {}
    end
    -- What ends up on the button, for GetDrawnParts.
    caerdonButton.caerdonHasIcon = false
    caerdonButton.caerdonHasGain = false

    if not status then
        if mogAnim and mogAnim:IsPlaying() then
            mogAnim:Stop()
        end
        if mogStatusBackground then
            mogStatusBackground:SetVertexColor(1, 1, 1)
            mogStatusBackground:SetTexture(nil)
            mogStatusBackground:SetAlpha(0)
            SetPartShown(caerdonButton, mogStatusBackground, false)
        end
        if mogStatus then
            mogStatus:SetVertexColor(1, 1, 1)
            mogStatus:SetTexture(nil)
            mogStatus:SetAlpha(0)
            mogStatus:SetDesaturated(false)
            mogStatus.assignedAlpha = 0
            SetPartShown(caerdonButton, mogStatus, false)
        end
        SetPartShown(caerdonButton, upgradeDeltaText, false)
        if mogStatus and mogStatus.upgradeBadge then
            mogStatus.caerdonBadgeActive = false
            mogStatus.upgradeBadge:Hide()
            mogStatus.upgradeBadgeRing:Hide()
        end
        return
    end

    local itemData = item and item.GetItemData and item:GetItemData()
    local sameLevelBehavior = CaerdonWardrobeConfig.Icon.SameLevelBehavior or "none"
    local showNeutralSameLevel = sameLevelBehavior == "neutral"
    local allowMismatchedSpecUpgrades = CaerdonWardrobeConfig.Icon.ShowMismatchedSpecUpgrades == true
    local equipmentSets = itemData and itemData.GetEquipmentSets and itemData:GetEquipmentSets()
    local isEquipmentSetItem = equipmentSets and #equipmentSets > 0
    local showGearSetText = isEquipmentSetItem and bindingStatus and IsGearSetStatus(bindingStatus, item) and
        CaerdonWardrobeConfig.Binding.ShowGearSets
    local bindingAnchor = (options and options.overrideBindingPosition) or CaerdonWardrobeConfig.Binding.Position
    caerdonButton.bindingTextMovedFor = nil
    caerdonButton.caerdonFixedLayout = (options and options.fixedLayout) and true or false
    caerdonButton.caerdonSample = (options and options.sample) and true or false
    local deltaAnchorFrame = (options and options.relativeFrame) or originalButton

    -- local mogFlash = caerdonButton.mogFlash
    -- if not mogFlash then
    -- 	mogFlash = caerdonButton:CreateTexture(nil, "OVERLAY")
    -- 	mogFlash:SetAlpha(0)
    -- 	mogFlash:SetBlendMode("ADD")
    -- 	mogFlash:SetAtlas("bags-glow-flash", true)
    -- 	mogFlash:SetPoint("CENTER")

    -- 	caerdonButton.mogFlash = mogFlash
    -- end

    local upgradeDeltaShown = false

    local showAnim = false
    if status == "waiting" then
        showAnim = true

        if mogAnim and not caerdonButton.isWaitingIcon then
            if mogAnim:IsPlaying() then
                mogAnim:Finish()
            end

            mogAnim = nil
            caerdonButton.mogAnim = nil
            caerdonButton.isWaitingIcon = false
        end

        if not mogAnim or not caerdonButton.isWaitingIcon then
            mogAnim = mogStatus:CreateAnimationGroup()

            self:AddRotation(mogAnim, 1, 360, 0.5, "IN_OUT")

            mogAnim:SetLooping("REPEAT")
            caerdonButton.mogAnim = mogAnim
            caerdonButton.isWaitingIcon = true
        end
    else
        if status == "readyToCombine" or status == "own" or status == "ownPlus" or status == "otherSpec" or status == "otherSpecPlus" or status == "refundable" or status == "openable" or status == "locked" or status == "upgradeNonEquipment" or status == "readyToCombine" then
            showAnim = true

            if mogAnim and caerdonButton.isWaitingIcon then
                if mogAnim:IsPlaying() then
                    mogAnim:Finish()
                end

                mogAnim = nil
                caerdonButton.mogAnim = nil
                caerdonButton.isWaitingIcon = false
            end

            if not mogAnim then
                mogAnim = mogStatus:CreateAnimationGroup()

                if status == "readyToCombine" then
                    self:AddRotation(mogAnim, 1, 360, 0.75, "NONE")
                else
                    self:AddRotation(mogAnim, 1, 110, 0.2, "OUT")
                    self:AddRotation(mogAnim, 2, -155, 0.2, "OUT")
                    self:AddRotation(mogAnim, 3, 60, 0.2, "OUT")
                    self:AddRotation(mogAnim, 4, -15, 0.1, "OUT", 0, 2)
                end

                mogAnim:SetLooping("REPEAT")
                caerdonButton.mogAnim = mogAnim
                caerdonButton.isWaitingIcon = false
            end
        else
            showAnim = false
        end
    end

    -- 	if not mogAnim then
    -- 		mogAnim = button:CreateAnimationGroup()
    -- 		mogAnim:SetToFinalAlpha(true)
    -- 		mogAnim.alpha1 = mogAnim:CreateAnimation("Alpha")
    -- 		mogAnim.alpha1:SetChildKey("mogFlash")
    -- 		mogAnim.alpha1:SetSmoothing("OUT");
    -- 		mogAnim.alpha1:SetDuration(0.6)
    -- 		mogAnim.alpha1:SetOrder(1)
    -- 		mogAnim.alpha1:SetFromAlpha(1);
    -- 		mogAnim.alpha1:SetToAlpha(0);

    -- 		caerdonButton.mogAnim = mogAnim
    -- 	end

    SetPartShown(caerdonButton, mogStatusBackground, true)
    SetPartShown(caerdonButton, mogStatus, true)

    if not displayInfo and feature then
        displayInfo = feature:GetDisplayInfoInternal(originalButton, item, feature, locationInfo, options, status,
            bindingStatus)
    end
    -- A feature can leave the level gain out (levelGain = { shouldShow = false }), for a window
    -- that already shows the upgrade its own way. No other feature sets it.
    local levelGainAllowed = not (displayInfo and displayInfo.levelGain and displayInfo.levelGain.shouldShow == false)
    -- The piece's level gain, when one is to be shown at all.
    local levelGain = upgradeDeltaText and GetShownLevelGain(transmogInfo, levelGainAllowed) or nil
    local equipLocation = item and item.GetEquipLocation and item:GetEquipLocation()
    local isTabard = equipLocation == "INVTYPE_TABARD"
    local isShirt = equipLocation == "INVTYPE_BODY"
    local globalUpgradeEnabled = CaerdonWardrobeConfig.Icon.ShowUpgradeIcon ~= false
    local upgradeSlotAvailable = displayInfo and displayInfo.upgradeIcon.shouldShow and not isEquipmentSetItem and
        not isTabard
    local shouldShowUpgradeIcon = globalUpgradeEnabled and upgradeSlotAvailable
    -- unusableNow: the tooltip's red text says the toon cannot wear the piece now, so it gets no
    -- equal-level icon (the status code sets it, and gives such a piece no protection either).
    local canEquipForNeutral = transmogInfo and not transmogInfo.unusableNow and
        ((transmogInfo.canEquipForPlayer ~= nil and transmogInfo.canEquipForPlayer) or transmogInfo.canEquip)

    local alpha = 1

    mogStatusBackground:SetVertexColor(1, 1, 1)
    mogStatusBackground:SetTexCoord(0, 1, 0, 1)
    mogStatusBackground:SetTexture("")

    mogStatus:SetVertexColor(1, 1, 1)
    mogStatus:SetTexCoord(0, 1, 0, 1)
    mogStatus:SetTexture("")
    -- Set again below by the one status that needs it.
    mogStatus.caerdonBackgroundNudge = nil

    local isProminent = false

    -- Whether the icon is one of the store's ring icons (SetRingIcon).
    local isRingIcon = false
    local caerdonType = item and item.GetCaerdonItemType and item:GetCaerdonItemType()
    local housingInfo = (caerdonType == CaerdonItemType.Housing and item:GetItemData() and item:GetItemData():GetHousingInfo()) or
        nil

    -- TODO: Possible gear set indicators
    -- MINIMAP / TempleofKotmogu_ball_cyan.PNG
    -- TempleofKotmogu_ball_green.PNG
    -- TempleofKotmogu_ball_orange.PNG
    -- TempleofKotmogu_ball_purple.PNG
    -- MINIMAP/TRACKING/OBJECTICONS.PNG

    if item and item.extraData and item.extraData.recipeInfo then
        -- TODO: Marking recipe skill ups here for now... need to figure out how to refactor
        if item.extraData.recipeInfo.firstCraft then
            iconBackgroundAdjustment = 2
            mogStatusBackground:SetTexCoord(91 / 1024, (91 + 30) / 1024, 987 / 1024, (987 + 30) / 1024)
            mogStatusBackground:SetTexture("Interface\\Store\\ServicesAtlas")
        end
    end

    -- TODO: Add options to hide these statuses
    if status == "refundable" then
        alpha = 0.9
        mogStatus:SetTexture("Interface\\COMMON\\mini-hourglass")
    elseif status == "openable" then
        isProminent = true
        isRingIcon = SetRingIcon(mogStatus, "Interface\\Store\\category-icon-free")
    elseif status == "readable" then
        isRingIcon = SetRingIcon(mogStatus, "Interface\\Store\\category-icon-services")
    elseif status == "lowSkill" or status == "lowSkillPlus" then
        mogStatus:SetTexCoord(6 / 64, 58 / 64, 6 / 64, 58 / 64)
        mogStatus:SetTexture("Interface\\WorldMap\\Gear_64Grey")
        if status == "lowSkillPlus" then
            mogStatus:SetVertexColor(0.4, 1, 0)
        end
        -- mogStatus:SetTexture("Interface\\QUESTFRAME\\SkillUp-BG")
        -- mogStatus:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
        -- mogStatus:SetTexture("Interface\\Buttons\\JumpUpArrow")
    elseif status == "upgradeNonEquipment" then
        isProminent = false
        iconBackgroundAdjustment = 4
        mogStatusBackground:SetTexCoord((512 - 46 - 31) / 512, (512 - 31) / 512, 5 / 512, (5 + 46) / 512)
        mogStatusBackground:SetTexture("Interface\\HUD\\UIUnitFrameBoss2x")
        mogStatusBackground:SetVertexColor(0, 1, 1)

        mogStatus:SetTexCoord(-1 / 32, 33 / 32, -1 / 32, 33 / 32)
        mogStatus:SetTexture("Interface\\Buttons\\JumpUpArrow")
    elseif status == "upgrade" then
        isProminent = false
        if shouldShowUpgradeIcon then
            iconBackgroundAdjustment = 4
            upgradeDeltaShown = DrawUpgradeIcon(self, originalButton, caerdonButton, deltaAnchorFrame, false,
                transmogInfo, allowMismatchedSpecUpgrades, levelGain)
        end
    elseif status == "upgradeLowSkill" then
        isProminent = false
        if shouldShowUpgradeIcon then
            iconBackgroundAdjustment = 4
            upgradeDeltaShown = DrawUpgradeIcon(self, originalButton, caerdonButton, deltaAnchorFrame, true,
                transmogInfo, allowMismatchedSpecUpgrades, levelGain)
        end
    elseif status == "locked" then
        isProminent = true
        isRingIcon = SetRingIcon(mogStatus, "Interface\\Store\\category-icon-key")
    elseif status == "oldexpansion" and displayInfo and displayInfo.oldExpansionIcon.shouldShow then
        alpha = 0.9
        isRingIcon = SetRingIcon(mogStatus, "Interface\\Store\\category-icon-wow")
    elseif status == "needForProfession" then
        -- TODO: Need to improve to pass data for icon determination.
        isProminent = true
        if displayInfo and displayInfo.ownIcon.shouldShow then
            isRingIcon = SetRingIcon(mogStatus, "Interface\\Store\\category-icon-featured")
            -- mogStatus:SetTexture("Interface\\WorldMap\\worldquest-icon-enchanting")
        end
    elseif status == "canCombine" then
        -- isProminent = true
        if displayInfo and displayInfo.ownIcon.shouldShow then -- TODO: Add separate config for combine icon
            -- mogStatus:SetTexCoord(16/64, 48/64, 16/64, 48/64)
            -- mogStatus:SetTexture("Interface\\PaperDollInfoFrame\\Character-Plus")
            -- mogStatus:SetTexture("Interface\\BUTTONS\\UI-PlusButton-Up")

            -- options.statusProminentSize = 256

            -- mogStatus:SetTexCoord((512-23)/512, (512-7)/512, (172-18)/512, (172-3)/512)
            -- mogStatus:SetTexture("Interface\\QUESTFRAME\\WorldQuest")

            mogStatus:SetTexCoord(91 / 1024, (91 + 30) / 1024, 987 / 1024, (987 + 30) / 1024)
            mogStatus:SetTexture("Interface\\Store\\ServicesAtlas")

            -- if status == "ownPlus" then
            -- 	mogStatus:SetVertexColor(0.4, 1, 0)
            -- end
        end
    elseif status == "readyToCombine" then
        -- isProminent = true
        if displayInfo and displayInfo.ownIcon.shouldShow then -- TODO: Add separate config for combine icon
            -- alpha = 0.9

            -- mogStatus:SetTexCoord((512-23)/512, (512-7)/512, 172/512, (172+15)/512)
            -- mogStatus:SetTexture("Interface\\QUESTFRAME\\WorldQuest")

            iconBackgroundAdjustment = 4

            -- mogStatusBackground:SetTexCoord(455/512, (455+28)/512, 1/256, (1+28)/256)
            -- mogStatusBackground:SetTexture("Interface\\Store\\Shop")

            -- mogStatusBackground:SetTexCoord(180/512, (180+46)/512, 5/512, (5+46)/512)
            mogStatusBackground:SetTexCoord((512 - 46 - 31) / 512, (512 - 31) / 512, 5 / 512, (5 + 46) / 512)
            mogStatusBackground:SetTexture("Interface\\HUD\\UIUnitFrameBoss2x")
            -- mogStatusBackground:SetVertexColor(0, 1, 0)
            mogStatusBackground:SetVertexColor(80 / 256, 252 / 256, 80 / 256, 253 / 256)

            mogStatus:SetTexCoord(305 / 512, (305 + 116) / 512, 141 / 512, (141 + 116) / 512)
            mogStatus:SetTexture("Interface\\Animations\\PowerSwirlAnimation")
            -- mogStatus:SetVertexColor(0, 1, 0)
            mogStatus:SetVertexColor(80 / 256, 252 / 256, 80 / 256, 253 / 256)

            -- mogStatus:SetTexCoord(16/64, 48/64, 16/64, 48/64)
            -- mogStatus:SetTexture("Interface\\HELPFRAME\\ReportLagIcon-AuctionHouse")

            -- if status == "ownPlus" then
            -- 	mogStatus:SetVertexColor(0.4, 1, 0)
            -- end
        end
    elseif status == "housingOwned" then
        isProminent = true
        iconBackgroundAdjustment = 2

        local housingIconSet = false
        if housingInfo then
            if housingInfo.iconAtlas and mogStatus.SetAtlas then
                mogStatus:SetAtlas(housingInfo.iconAtlas, false)
                mogStatus:SetTexCoord(0, 1, 0, 1)
                housingIconSet = true
            elseif housingInfo.iconTexture then
                mogStatus:SetTexture(housingInfo.iconTexture)
                housingIconSet = true
            end
        end

        if not housingIconSet then
            isRingIcon = SetRingIcon(mogStatus, "Interface\\Store\\category-icon-featured")
        end
    elseif status == "own" or status == "ownPlus" then
        isProminent = true
        if displayInfo and displayInfo.ownIcon.shouldShow then
            isRingIcon = SetRingIcon(mogStatus, "Interface\\Store\\category-icon-featured")
            if status == "ownPlus" then
                mogStatus:SetVertexColor(0.4, 1, 0)
            end
        end
    elseif status == "other" or status == "otherPlus" then
        isProminent = true
        if displayInfo and displayInfo.otherIcon.shouldShow then
            isRingIcon = SetRingIcon(mogStatus, "Interface\\Store\\category-icon-placeholder")
            if status == "otherPlus" then
                mogStatus:SetVertexColor(0.4, 1, 0)
            end
        end
    elseif status == "otherNoLoot" or status == "otherPlusNoLoot" then
        if displayInfo and displayInfo.otherIcon.shouldShow then
            iconBackgroundAdjustment = 0
            -- Kept on the icon, not written into options: callers reuse one options table for a
            -- whole window, and the nudge used to leak onto every button drawn after this one.
            mogStatus.caerdonBackgroundNudge = -0.5
            mogStatusBackground:SetTexCoord((512 - 46 - 31) / 512, (512 - 31) / 512, 5 / 512, (5 + 46) / 512)
            mogStatusBackground:SetTexture("Interface\\HUD\\UIUnitFrameBoss2x")
            mogStatus:SetVertexColor(1, 1, 0)

            mogStatus:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")

            if status == "otherPlusNoLoot" then
                mogStatusBackground:SetVertexColor(0.4, 1, 0)
            end
        end
    elseif status == "otherSpec" or status == "otherSpecPlus" then
        isProminent = true
        if displayInfo and displayInfo.otherIcon.shouldShow then
            mogStatus:SetTexture("Interface\\COMMON\\icon-noloot")
            if status == "otherSpecPlus" then
                mogStatus:SetVertexColor(0.4, 1, 0)
            end
        end
    elseif status == "quest" and displayInfo and displayInfo.questIcon.shouldShow then
        mogStatus:SetTexCoord(-1 / 32, 33 / 32, -1 / 32, 33 / 32)
        mogStatus:SetTexture("Interface\\MINIMAP\\MapQuestHub_Icon32")
    elseif status == "collected" then
        local matchesCurrentSpec = transmogInfo and (transmogInfo.matchesLootSpec ~= false)
        if shouldShowUpgradeIcon and transmogInfo and transmogInfo.upgradeMatchesSpec == false and
            not allowMismatchedSpecUpgrades then
            shouldShowUpgradeIcon = false
        end
        local showEqualLevel = transmogInfo and
            showNeutralSameLevel and
            transmogInfo.equalItemLevelEquipped and
            not transmogInfo.identicalToEquipped and
            canEquipForNeutral and
            matchesCurrentSpec and
            transmogInfo.hasMetRequirements and
            not transmogInfo.isUpgrade and
            upgradeSlotAvailable and
            not isShirt

        if showEqualLevel and not isEquipmentSetItem then
            iconBackgroundAdjustment = 6
            mogStatusBackground:SetTexCoord((512 - 46 - 31) / 512, (512 - 31) / 512, 5 / 512, (5 + 46) / 512)
            mogStatusBackground:SetTexture("Interface\\HUD\\UIUnitFrameBoss2x")
            mogStatusBackground:SetVertexColor(0.85, 0.85, 0.85)

            mogStatus:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            mogStatus:SetTexture("Interface\\PaperDollInfoFrame\\StatSortArrows")
            mogStatus:SetVertexColor(1, 0.95, 0.75)
        elseif IsGearSetStatus(bindingStatus, item) and CaerdonWardrobeConfig.Binding.ShowGearSetsAsIcon then
            isRingIcon = SetRingIcon(mogStatus, "Interface\\Store\\category-icon-clothes")
        end
    elseif (status == "auction" or status == "auctionGoods") and displayInfo and displayInfo.auctionIcon and displayInfo.auctionIcon.shouldShow then
        -- The auction house pays enough more than a vendor to list it instead.
        alpha = 0.9
        if mogStatus.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Auctioneer") then
            mogStatus:SetAtlas("Auctioneer", false)
        else
            mogStatus:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
        end
    elseif status == "sellable" or status == "auction" then
        -- "auction" lands here where its own icon is off (anything but bags and bank).
        if displayInfo and displayInfo.sellableIcon.shouldShow then -- it's known and can be sold
            alpha = 0.9
            isRingIcon = SetRingIcon(mogStatus, "Interface\\Store\\category-icon-bag")
        end
    elseif status == "waiting" then
        alpha = 0.5
        isRingIcon = SetRingIcon(mogStatus, "Interface\\Common\\StreamCircle")
        -- elseif IsGearSetStatus(bindingStatus, item) and CaerdonWardrobeConfig.Binding.ShowGearSetsAsIcon then
        -- 	mogStatus:SetTexCoord(16/64, 48/64, 16/64, 48/64)
        -- 	mogStatus:SetTexture("Interface\\Store\\category-icon-clothes")
    end

    -- An upgrade whose status went to something else, in practice a look to learn
    -- (transmogInfo.upgradeStatus is the status logic's own verdict): the arrow rides on that
    -- icon as a small badge, so an upgrade always reads as one. Where the window does not show
    -- that icon at all, the item is drawn as the upgrade it is.
    local badgeStatus = transmogInfo and transmogInfo.upgradeStatus
    local showBadge = false
    if badgeStatus and shouldShowUpgradeIcon and status ~= "upgrade" and status ~= "upgradeLowSkill" and
        status ~= "waiting" then
        local statusTexture = (mogStatus.GetAtlas and mogStatus:GetAtlas()) or mogStatus:GetTexture()
        if statusTexture == nil or statusTexture == "" or statusTexture == 0 then
            isProminent = false
            iconBackgroundAdjustment = 4
            upgradeDeltaShown = DrawUpgradeIcon(self, originalButton, caerdonButton, deltaAnchorFrame,
                badgeStatus == "upgradeLowSkill", transmogInfo, allowMismatchedSpecUpgrades, levelGain)
        else
            showBadge = true
        end
    end

    local upgradeBadge, upgradeBadgeRing = mogStatus.upgradeBadge, mogStatus.upgradeBadgeRing
    if showBadge and not upgradeBadge then
        upgradeBadgeRing = caerdonButton:CreateTexture(nil, "ARTWORK", nil, 3)
        upgradeBadge = caerdonButton:CreateTexture(nil, "ARTWORK", nil, 4)
        upgradeBadgeRing:Hide()
        upgradeBadge:Hide()
        mogStatus.upgradeBadge, mogStatus.upgradeBadgeRing = upgradeBadge, upgradeBadgeRing
    end
    mogStatus.caerdonBadgeActive = showBadge
    caerdonButton.caerdonHasUpgradeBadge = showBadge
    if showBadge then
        upgradeBadgeRing:SetTexCoord((512 - 46 - 31) / 512, (512 - 31) / 512, 5 / 512, (5 + 46) / 512)
        upgradeBadgeRing:SetTexture("Interface\\HUD\\UIUnitFrameBoss2x")
        if badgeStatus == "upgradeLowSkill" then
            upgradeBadgeRing:SetVertexColor(0.4, 1, 0)
        else
            upgradeBadgeRing:SetVertexColor(0, 1, 1)
        end
        upgradeBadge:SetTexCoord(-1 / 32, 33 / 32, -1 / 32, 33 / 32)
        upgradeBadge:SetTexture("Interface\\Buttons\\JumpUpArrow")
        ApplyUpgradeArrowColor(upgradeBadge, transmogInfo, allowMismatchedSpecUpgrades, 0.4, 1, 0.2)
    end

    if not upgradeDeltaShown and levelGain then
        ShowLevelGain(self, originalButton, caerdonButton, deltaAnchorFrame, levelGain, 0.2, 1.0, 0.2)
        upgradeDeltaShown = true
    end

    -- Show house XP bonus as a delta indicator for unowned housing items
    if not upgradeDeltaShown and upgradeDeltaText and housingInfo and
        housingInfo.firstAcquisitionBonus and housingInfo.firstAcquisitionBonus > 0 and
        (status == "own") then
        -- Gold for house XP
        ShowLevelGain(self, originalButton, caerdonButton, deltaAnchorFrame, housingInfo.firstAcquisitionBonus, 1, 0.82, 0)
        upgradeDeltaShown = true
    end

    local iconSize = self:GetStatusBaseSize(options)

    if isProminent then
        mogStatusBackground:SetSize(iconSize, iconSize)
        mogStatus:SetSize(iconSize - iconBackgroundAdjustment, iconSize - iconBackgroundAdjustment)
    else
        iconSize = iconSize * ICON_SIZE_DIFFERENTIAL
        mogStatusBackground:SetSize(iconSize, iconSize)
        mogStatus:SetSize(iconSize - iconBackgroundAdjustment, iconSize - iconBackgroundAdjustment)
    end

    -- The full size, for the clip-aware placement to shrink from and return to.
    mogStatus.caerdonBaseSize = iconSize - iconBackgroundAdjustment
    mogStatus.caerdonBaseBackgroundSize = iconSize

    -- options.roundStatusIcon, for a window with a light background (parchment): a ring icon's
    -- square holds a piece of its shadow, which is lost on a dark slot but shows there and turns
    -- with the animation. The icon is clipped to the ring; SetStatusIconPosition sizes the mask.
    local ringMask = mogStatus.caerdonRingMask
    local wantRingMask = (isRingIcon and options.roundStatusIcon) and true or false
    if wantRingMask and not ringMask then
        ringMask = caerdonButton:CreateMaskTexture()
        ringMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE")
        ringMask:SetPoint("CENTER", mogStatus, "CENTER", 0, 0)
        mogStatus.caerdonRingMask = ringMask
    end
    if ringMask and wantRingMask ~= (mogStatus.caerdonRingMaskOn or false) then
        if wantRingMask then
            mogStatus:AddMaskTexture(ringMask)
        else
            mogStatus:RemoveMaskTexture(ringMask)
        end
        mogStatus.caerdonRingMaskOn = wantRingMask
    end

    self:SetStatusIconPosition(mogStatus, originalButton, item, feature, locationInfo, options, status, bindingStatus)

    mogStatusBackground:SetAlpha(alpha)

    mogStatus:SetAlpha(alpha)
    mogStatus.assignedAlpha = alpha

    -- A status with no icon of its own (or one this window does not show) leaves the texture empty.
    local drawnTexture = (mogStatus.GetAtlas and mogStatus:GetAtlas()) or mogStatus:GetTexture()
    caerdonButton.caerdonHasIcon = (drawnTexture ~= nil and drawnTexture ~= "" and drawnTexture ~= 0 and alpha > 0) and
        true or false
    caerdonButton.caerdonHasGain = upgradeDeltaShown

    -- The badge is on screen with its icon. Where a host addon shows the icon later, the icon's
    -- OnShow brings the badge along.
    if upgradeBadge then
        local badgeShown = showBadge and mogStatus:IsShown() and true or false
        upgradeBadge:SetShown(badgeShown)
        upgradeBadgeRing:SetShown(badgeShown)
        upgradeBadge:SetAlpha(alpha)
        upgradeBadgeRing:SetAlpha(alpha)
    end

    if caerdonButton.searchOverlay then
        QueueSearchDim(caerdonButton)
    end

    if options.isFiltered then
        if options.filterColor then
            mogStatus:SetDesaturated(true)
            mogStatus:SetVertexColor(options.filterColor:GetRGB())
        else
            mogStatusBackground:SetAlpha(0.3)
            mogStatus:SetAlpha(0.3)
        end
    else
        mogStatus:SetDesaturated(false)
    end

    if showAnim and CaerdonWardrobeConfig.Icon.EnableAnimation then
        if mogAnim and not mogAnim:IsPlaying() then
            mogAnim:Play()
        end
    else
        if mogAnim and mogAnim:IsPlaying() then
            mogAnim:Finish()
        end
    end
end

-- Text and the level gain ("+5") on one slot.
--
-- The level gain goes where it is put and stays there. Text on the same row moves clear of it,
-- away from the row's edge, but only when the two would really run into each other: BoE in the
-- bottom left and "+5" in the bottom right fit side by side and are left alone. This is the same
-- thing text does for a stack count, so a number in a corner always keeps its corner. (Until
-- 2026-11-14 it was the level gain that moved, above any text on the bottom edge, which left it
-- part-way up the slot when the player had asked for the corner.)
-- How far the level gain stays from any edge of the slot it is anchored to. It was 2, which
-- left the digits crammed against the edge once it sat in a corner by itself.
local LEVEL_GAIN_INSET = 4

-- The player's layout for the level gain; hand-fitted windows keep the bottom right.
local function GetLevelGainLayout(caerdonButton)
    local point, scale, nudgeX, nudgeY = "BOTTOMRIGHT", 1, 0, 0
    local layout = CaerdonWardrobeConfig.Icon.UpgradeDelta
    if layout and not caerdonButton.caerdonFixedLayout then
        point = layout.Position or point
        scale = PercentToScale(layout.Scale)
        nudgeX, nudgeY = tonumber(layout.OffsetX) or 0, tonumber(layout.OffsetY) or 0
    end
    return point, scale, nudgeX, nudgeY
end

local function RowOf(anchor)
    return (string.find(anchor, "TOP") and "TOP") or (string.find(anchor, "BOTTOM") and "BOTTOM") or "MIDDLE"
end

-- A string's width, in its own units, depends on the scale it is drawn at: letters are fitted to
-- whole pixels, so small text comes out wider for its size than large text. The layout editor's
-- large slot is a normal slot scaled up four times, where "BoE" measured about 19 units against
-- about 22 at normal size, and so it showed two parts fitting side by side that collide on a
-- real slot. A sample therefore measures its text on a string at normal scale instead.
local measureString
local function MeasureStringWidth(fontString, atNormalScale)
    if not atNormalScale then
        return fontString:GetStringWidth() or 0
    end
    if not measureString then
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:SetSize(1, 1)
        frame:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -100, 100) -- off screen
        frame:SetAlpha(0)
        measureString = frame:CreateFontString(nil, "ARTWORK")
    end
    local file, height, flags = fontString:GetFont()
    if not file then
        return fontString:GetStringWidth() or 0
    end
    measureString:SetFont(file, height, flags)
    measureString:SetText(fontString:GetText() or "")
    return measureString:GetStringWidth() or 0
end

-- Where something of this width ends up across the slot, as left and right edge from the
-- slot's left. offset is what SetPoint gets: positive to the right.
local function HorizontalSpan(anchor, width, offset, slotWidth)
    if string.find(anchor, "LEFT") then
        return offset, offset + width
    elseif string.find(anchor, "RIGHT") then
        return slotWidth - width + offset, slotWidth + offset
    end
    return (slotWidth - width) / 2 + offset, (slotWidth + width) / 2 + offset
end

-- How far from its row's edge text has to stay to clear a level gain on that row, or nil when
-- no level gain is showing there or the two do not meet sideways. On the middle row it is how
-- far up the text has to go.
local function GetLevelGainClearance(caerdonButton, slotWidth, textAnchor, textLeft, textRight, textHeight)
    local deltaText = caerdonButton.upgradeDeltaText
    if not (deltaText and deltaText:IsShown()) then
        return nil
    end
    local gain = deltaText:GetText()
    if not gain or gain == "" then
        return nil
    end

    local point, scale, nudgeX, nudgeY = GetLevelGainLayout(caerdonButton)
    local row = RowOf(point)
    if row ~= RowOf(textAnchor) then
        return nil
    end

    local inset = (string.find(point, "RIGHT") and -LEVEL_GAIN_INSET) or
        (string.find(point, "LEFT") and LEVEL_GAIN_INSET) or 0
    local gainWidth = MeasureStringWidth(deltaText, caerdonButton.caerdonSample) * scale
    local gainLeft, gainRight = HorizontalSpan(point, gainWidth, inset + nudgeX, slotWidth)
    if textRight <= gainLeft + 1 or textLeft >= gainRight - 1 then
        return nil -- side by side, with a pixel to spare
    end

    local _, fontHeight = deltaText:GetFont()
    local height = (fontHeight or 12) * scale
    if row == "BOTTOM" then
        return LEVEL_GAIN_INSET + nudgeY + height + 1
    elseif row == "TOP" then
        return LEVEL_GAIN_INSET - nudgeY + height + 1
    end
    return (height + textHeight) / 2 + 1
end

function CaerdonWardrobeMixin:UpdateUpgradeDeltaPosition(originalButton)
    if not originalButton then return end
    local caerdonButton = self:GetCaerdonButton(originalButton)
    if not caerdonButton then return end

    local deltaText = caerdonButton.upgradeDeltaText
    if caerdonButton.caerdonHostPlacesParts then
        -- The host addon anchors and shows it; only its size is the player's setting here.
        if deltaText then
            local _, hostScale = GetLevelGainLayout(caerdonButton)
            deltaText:SetScale(hostScale)
        end
        return
    end
    if not (deltaText and deltaText:IsShown()) then
        return
    end

    local anchorFrame = caerdonButton.upgradeDeltaAnchor or originalButton
    if not anchorFrame then
        anchorFrame = originalButton
    end
    -- The same space from every edge it touches; none along an axis it is centered on.
    local point, scale, nudgeX, nudgeY = GetLevelGainLayout(caerdonButton)
    local xOffset = (string.find(point, "RIGHT") and -LEVEL_GAIN_INSET) or
        (string.find(point, "LEFT") and LEVEL_GAIN_INSET) or 0
    local yOffset = (string.find(point, "BOTTOM") and LEVEL_GAIN_INSET) or
        (string.find(point, "TOP") and -LEVEL_GAIN_INSET) or 0

    deltaText:ClearAllPoints()
    deltaText:SetScale(scale)
    -- Offsets of a scaled region are in its own units; keep them the same size on screen.
    deltaText:SetPoint(point, anchorFrame, point, (xOffset + nudgeX) / scale, (yOffset + nudgeY) / scale)
end

function CaerdonWardrobeMixin:SetItemButtonBindType(button, item, feature, locationInfo, options, mogStatus,
                                                    bindingStatus, displayInfo)
    local caerdonButton = self:GetCaerdonButton(button)

    local bindsOnText = caerdonButton and caerdonButton.bindsOnText
    if bindsOnText then
        bindsOnText:SetText("")
    end
    if caerdonButton then
        caerdonButton.caerdonHasText = false
    end

    if not feature or not bindingStatus then return end

    if not displayInfo then
        displayInfo = feature:GetDisplayInfoInternal(button, item, feature, locationInfo, options, mogStatus,
            bindingStatus)
    end

    if not displayInfo.bindingStatus.shouldShow then
        return
    end

    local bindingText = ""
    if IsGearSetStatus(bindingStatus, item) then -- is gear set
        if CaerdonWardrobeConfig.Binding.ShowGearSets then
            bindingText = "|cFFFFFFFF" .. bindingStatus .. "|r"
        end
    else
        if mogStatus == "own" then
            if bindingStatus == L["BoA"] then
                local color = BAG_ITEM_QUALITY_COLORS[Enum.ItemQuality.Heirloom]
                bindsOnText:SetTextColor(color.r, color.g, color.b, 1)
                bindingText = bindingStatus
            elseif bindingStatus then
                bindingText = "|cFF00FF00" .. bindingStatus .. "|r"
            end
        elseif mogStatus == "other" then
            bindingText = "|cFFFF0000" .. bindingStatus .. "|r"
        elseif mogStatus == "collected" then
            if bindingStatus == L["BoA"] then
                local color = BAG_ITEM_QUALITY_COLORS[Enum.ItemQuality.Heirloom]
                bindsOnText:SetTextColor(color.r, color.g, color.b, 1)
                bindingText = bindingStatus
            elseif bindingStatus == L["BoE"] or bindingStatus == L["WuE"] then
                bindingText = "|cFF00FF00" .. bindingStatus .. "|r"
            else
                bindingText = bindingStatus
            end
        else
            if bindingStatus == L["BoA"] then
                local color = BAG_ITEM_QUALITY_COLORS[Enum.ItemQuality.Heirloom]
                bindsOnText:SetTextColor(color.r, color.g, color.b, 1)
                bindingText = bindingStatus
            elseif bindingStatus then
                bindingText = "|cFF00FF00" .. bindingStatus .. "|r"
            end
        end
    end

    bindsOnText:SetText(bindingText)
    bindsOnText:SetJustifyV("BOTTOM")
    if caerdonButton then
        caerdonButton.bindingTextMovedFor = nil
    end

    if caerdonButton then
        caerdonButton.caerdonHasText = bindingText ~= ""
    end

    if options and options.hostPlacesParts then
        -- The host addon anchors the text and shows it; here it only gets its size. Measured on a
        -- string of its own, because measuring in place would mean taking its anchors away.
        local _, hostUserScale = GetTextLayout(options, IsGearSetStatus(bindingStatus, item))
        local hostScale = (options.bindingScale or 1) * hostUserScale
        local _, hostFontHeight = bindsOnText:GetFont()
        local hostWidth = math.min(MeasureStringWidth(bindsOnText, true) + 1, button:GetWidth() / hostScale)
        bindsOnText:SetSize(hostWidth, hostFontHeight or bindsOnText:GetStringHeight() or 0)
        bindsOnText:SetScale(hostScale)
        if caerdonButton then
            self:UpdateUpgradeDeltaPosition(button)
        end
        return
    end

    -- Measure text and resize accordingly
    bindsOnText:ClearAllPoints()
    bindsOnText:SetScale(1) -- Reset scale before measuring so GetStringWidth is accurate
    bindsOnText:SetSize(0, 0)
    bindsOnText:SetPoint("LEFT")
    bindsOnText:SetPoint("RIGHT")

    local newWidth = MeasureStringWidth(bindsOnText, options and options.sample)
    if newWidth > button:GetWidth() then
        newWidth = button:GetWidth()
    end
    local _, fontHeight = bindsOnText:GetFont()
    local newHeight = fontHeight or bindsOnText:GetStringHeight() or bindsOnText:GetHeight()

    -- When bindingScale < 1, the font string needs extra logical width to prevent
    -- text truncation after SetScale shrinks the effective render area.
    local isGearSet = IsGearSetStatus(bindingStatus, item)
    local bindingPosition, userScale, nudgeX, nudgeY, handFitted = GetTextLayout(options, isGearSet)
    local bindingScale = (options.bindingScale or 1) * userScale
    local scaledWidth = (bindingScale < 1) and (newWidth / bindingScale) or newWidth
    if bindingScale > 1 then
        -- Enlarged text: what it covers on screen still has to fit the button.
        scaledWidth = math.min(newWidth, button:GetWidth() / bindingScale)
    end

    bindsOnText:ClearAllPoints()
    bindsOnText:SetSize(scaledWidth, newHeight)

    local xOffset = 1
    if options.bindingOffsetX ~= nil then
        xOffset = options.bindingOffsetX
    end

    -- Space from the top or bottom edge. None in the middle row, where there is no edge and the
    -- text should line up with a level gain beside it; it used to sit 2 higher there. Hand-fitted
    -- windows keep the 2, which their look was tuned with.
    local yOffset = 2
    if not handFitted and RowOf(bindingPosition) == "MIDDLE" then
        yOffset = 0
    end
    if options.bindingOffsetY ~= nil then
        yOffset = options.bindingOffsetY
    end

    local hasCount = (button.count and button.count > 1) or options.hasCount

    if string.find(bindingPosition, "BOTTOM") then
        bindsOnText:SetJustifyV("BOTTOM")
    elseif string.find(bindingPosition, "TOP") then
        bindsOnText:SetJustifyV("TOP")
    else
        bindsOnText:SetJustifyV("MIDDLE")
    end

    -- Text the player put on a side sits against that side. A hand-fitted window keeps it centered
    -- in its box, the way its offsets were tuned.
    if not handFitted and string.find(bindingPosition, "LEFT") then
        bindsOnText:SetJustifyH("LEFT")
    elseif not handFitted and string.find(bindingPosition, "RIGHT") then
        bindsOnText:SetJustifyH("RIGHT")
    else
        bindsOnText:SetJustifyH("CENTER")
    end

    if string.find(bindingPosition, "BOTTOM") then
        if hasCount then
            yOffset = options.itemCountOffset or 15
        else
            yOffset = yOffset - 2
        end
    end

    if string.find(bindingPosition, "TOP") then
        yOffset = yOffset * -1
    end

    if string.find(bindingPosition, "RIGHT") then
        xOffset = xOffset * -1
    end

    -- Offsets of a scaled font string are in its own units. Keep the usual spacing the same on
    -- screen whatever size the player picked, then add the player's nudge.
    if userScale ~= 1 then
        xOffset = xOffset / userScale
        yOffset = yOffset / userScale
    end
    xOffset = xOffset + nudgeX / bindingScale
    yOffset = yOffset + nudgeY / bindingScale

    -- A level gain on the same row keeps its place and the text moves clear of it, the way it
    -- already sits above a stack count. Hand-fitted windows stay as they were tuned. What moved
    -- the text is noted on the overlay, for the layout editor to explain.
    local movedFor = (hasCount and string.find(bindingPosition, "BOTTOM")) and "count" or nil
    if not handFitted and caerdonButton then
        local slotWidth = ((options and options.relativeFrame) or button):GetWidth()
        local textLeft, textRight = HorizontalSpan(bindingPosition, math.min(newWidth * bindingScale, slotWidth),
            xOffset * bindingScale, slotWidth)
        local clearance = GetLevelGainClearance(caerdonButton, slotWidth, bindingPosition, textLeft, textRight,
            newHeight * bindingScale)
        if clearance then
            local row = RowOf(bindingPosition)
            local onScreen = yOffset * bindingScale
            if row == "BOTTOM" then
                if onScreen < clearance then
                    onScreen = clearance
                    movedFor = "gain"
                end
            elseif row == "TOP" then
                if onScreen > -clearance then
                    onScreen = -clearance
                    movedFor = "gain"
                end
            else
                -- From the middle there are two ways out; take the one away from the status icon.
                local iconAnchor = GetIconLayout(options)
                onScreen = onScreen + ((RowOf(iconAnchor) == "TOP") and -clearance or clearance)
                movedFor = "gain"
            end
            yOffset = onScreen / bindingScale
        end
    end
    if caerdonButton then
        caerdonButton.bindingTextMovedFor = movedFor
    end

    if options and options.relativeFrame then
        bindsOnText:SetPoint(bindingPosition, options.relativeFrame, bindingPosition, xOffset, yOffset)
    else
        bindsOnText:SetPoint(bindingPosition, xOffset, yOffset)
    end

    if bindingScale ~= 1 then
        bindsOnText:SetScale(bindingScale)
    end

    if caerdonButton then
        self:UpdateUpgradeDeltaPosition(button)
    end
end

-- How often one request is tried again while its tooltip still says "Retrieving item information".
local NOT_READY_MAX_RETRIES = 10

-- The key a button is filed under while a request for it is being worked on: the feature's name
-- plus the bag slot, or the key the feature passed. nil when the feature passed none. UpdateButton
-- stores it on the button and the retry compares against it, so both must build it here.
local function GetRequestKey(item, feature, locationInfo)
    if item:HasItemLocationBankOrBags() then
        local bag, slot = item:GetItemLocation():GetBagAndSlot()
        return format("%s-bag%d-slot%d", feature:GetName(), bag, slot)
    end
    local locationKey = locationInfo.locationKey
    if not locationKey then
        return nil
    end
    return format("%s-%s", feature:GetName(), locationKey)
end

function CaerdonWardrobeMixin:ProcessItem(button, item, feature, locationInfo, options)
    local mogStatus = nil
    local bindingStatus = nil
    local bindingResult = nil

    if not options then
        options = {}
    end

    local caerdonType = item:GetCaerdonItemType()

    -- The transmog info comes with the status: it is the table the verdict was made from, kept
    -- with it, so a draw never computes it again.
    local isReady, transmogInfo
    isReady, mogStatus, bindingStatus, bindingResult, transmogInfo = item:GetCaerdonStatus(feature, locationInfo)
    if not isReady then
        -- Tooltip data shows "Retrieving item information". Instead of
        -- polling through the queue, stash the item and let a single
        -- deferred timer batch-retry all pending items once.
        local locationKey = GetRequestKey(item, feature, locationInfo)

        -- Counted per button. It used to be kept in the caller's options table, which a window
        -- shares between its buttons (and some integrations keep for the whole session), so the
        -- limit was used up by other items.
        local state = GetButtonState(button, true)
        local retries = ((state and state.notReadyRetries) or 0) + 1
        if state then
            state.notReadyRetries = retries
        end
        if state and locationKey and retries <= NOT_READY_MAX_RETRIES then
            self.pendingTooltipRetries = self.pendingTooltipRetries or {}
            -- Per button, like the queue (see UpdateButton).
            self.pendingTooltipRetries[button or locationKey] = {
                button = button,
                item = item,
                feature = feature,
                locationInfo = locationInfo,
                options = options,
                expectedKey = locationKey,
            }
            if not self.tooltipRetryTimer then
                self.tooltipRetryTimer = C_Timer.NewTimer(1.0, function()
                    self.tooltipRetryTimer = nil
                    local pending = self.pendingTooltipRetries
                    self.pendingTooltipRetries = nil
                    if pending then
                        for key, info in pairs(pending) do
                            -- Only while the button still shows this item: the same key can stand for
                            -- another item by now (the next vendor page), and running the old request
                            -- again would clear that item's icon.
                            local itemID = not info.item:IsItemEmpty() and info.item:GetItemID() or nil
                            if self:GetButtonLocationKey(info.button) == info.expectedKey and
                                (itemID == nil or self:GetButtonItemID(info.button) == itemID) then
                                -- Tells UpdateButton this is the same request again, not a new one.
                                local retryState = GetButtonState(info.button)
                                if retryState then
                                    retryState.retryingNotReady = true
                                end
                                self:UpdateButton(info.button, info.item, info.feature, info.locationInfo, info.options)
                            end
                        end
                    end
                end)
            end
        end
        return
    end

    if caerdonType == CaerdonItemType.Equipment then
        if transmogInfo then
            if transmogInfo.isTransmog then
                -- TODO: Exceptions need to be broken out
                -- TODO: Instead maybe: mogStatus = feature:UpdateMogStatus(mogStatus)
                local featureName = feature and feature:GetStatusRuleName()
                if featureName == "EncounterJournal" or featureName == "Merchant" or featureName == "CustomerOrders" then
                    if transmogInfo.needsItem and featureName ~= "Merchant" then
                        if not transmogInfo.matchesLootSpec then
                            if mogStatus == "own" or mogStatus == "lowSkill" then
                                mogStatus = "otherSpecPlus"
                            else
                                if CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem then
                                    mogStatus = "otherSpec"
                                end
                            end
                        end
                    elseif transmogInfo.otherNeedsItem then
                        local playerCanCollectSource = transmogInfo.playerCanCollectSource
                        local isBindOnPickup = bindingResult and bindingResult.isBindOnPickup
                        local playerCollectRestricted = playerCanCollectSource == false
                        local shouldShowNoLoot

                        if featureName == "EncounterJournal" then
                            -- Encounter Journal entries should flag as no-loot when the source is
                            -- class/faction locked or when the drop itself is BoP (old behavior).
                            shouldShowNoLoot = playerCollectRestricted or isBindOnPickup
                        elseif featureName == "Merchant" then
                            -- Merchant items should only show no-loot when this character truly can't
                            -- collect the source (class/race/faction restriction). BoP cosmetics and
                            -- cross-armor pieces remain completionist-learnable, so keep them visible.
                            shouldShowNoLoot = playerCollectRestricted
                        else
                            -- Customer Orders (and any other features that land here) still benefit
                            -- from the new player-can-collect signal so completionists can see when
                            -- the recipe truly cannot be learned.
                            shouldShowNoLoot = playerCollectRestricted
                        end

                        if shouldShowNoLoot then
                            if not transmogInfo.isCompletionistItem then
                                mogStatus = "otherNoLoot"
                            else
                                mogStatus = "otherPlusNoLoot"
                            end
                        end
                    end
                end
            end
        end
    end

    -- The status logic's own upgrade verdict, for the badge on an icon that is not the arrow.
    if transmogInfo and bindingResult then
        transmogInfo.upgradeStatus = bindingResult.upgradeStatus
    end

    if button then
        -- The window's display rules, asked for once and handed to both halves of the draw.
        -- With no status and no text neither half reads them.
        local displayInfo
        if feature and (mogStatus or bindingStatus) then
            displayInfo = feature:GetDisplayInfoInternal(button, item, feature, locationInfo, options, mogStatus,
                bindingStatus)
        end
        self:SetItemButtonStatus(button, item, feature, locationInfo, options, mogStatus, bindingStatus, transmogInfo,
            displayInfo)
        self:SetItemButtonMogStatusFilter(button, options.isFiltered)
        self:SetItemButtonBindType(button, item, feature, locationInfo, options, mogStatus, bindingStatus,
            displayInfo)
        self:SetButtonRefreshGeneration(button, self.refreshGeneration)
        if not milestones.firstDraw then
            Counters:Milestone("firstDraw")
        end

        -- For a feature that has to know when its button was drawn and what is on it (Baganator
        -- decides per corner which widget shows). An error there must not stop the other items.
        if feature and feature.OnButtonDrawn then
            Contained(feature.OnButtonDrawn, feature, button, item, locationInfo, options)
        end

        -- Debug only: remember what was drawn where, for the export's [Button Geometry] section.
        if CaerdonWardrobeConfig.Debug.Enabled and CaerdonButtonGeometry then
            CaerdonButtonGeometry:Note(feature, button, options, mogStatus, bindingStatus)
        end
    end
end

-- Whether the last draw left a status icon, a binding text (or gear set name) and a level gain
-- on the button.
function CaerdonWardrobeMixin:GetDrawnParts(originalButton)
    local caerdonButton = self:GetCaerdonButton(originalButton)
    if not caerdonButton then
        return false, false, false
    end
    return caerdonButton.caerdonHasIcon == true, caerdonButton.caerdonHasText == true,
        caerdonButton.caerdonHasGain == true
end

function CaerdonWardrobeMixin:RegisterFeature(mixin)
    local instance = CreateFromMixins(CaerdonWardrobeFeatureMixin, mixin)
    local name = instance:GetName()
    if not availableFeatures[name] then
        availableFeatures[name] = instance
    else
        error(format("Caerdon Wardrobe: Feature name collision: %s already exists", name))
    end
end

function CaerdonWardrobeMixin:GetRegisteredFeatures()
    return availableFeatures
end

function CaerdonWardrobeMixin:GetFeature(name)
    return registeredFeatures[name] or availableFeatures[name]
end

-- A draw owed to a button that is not on screen.
--
-- For a window that does not ask for its buttons again when it comes on screen (BetterBags'
-- bags: an unchanged button is not drawn again when its bag opens). Such a window's Refresh()
-- cannot simply skip what nobody sees, and asking for it anyway makes every full refresh cost
-- the whole closed bag. So it hands the button over here: the icon drawn before stays, and
-- feature:OnButtonOnScreen(context) is called once when the button next comes on screen, from
-- where the feature asks for it. The overlay is a shown child of the button, so the client
-- runs its OnShow whenever the button comes on screen, whichever parent was hidden.
--
-- A request or a clear for the button in between settles the debt. The script is only set
-- while something is owed, so a window that opens with nothing owed runs no code here.
local function SettleOwedDraw(caerdonButton)
    caerdonButton.caerdonOwedTo, caerdonButton.caerdonOwedContext = nil, nil
    caerdonButton:SetScript("OnShow", nil)
end

local function PayOwedDraw(caerdonButton)
    local feature, context = caerdonButton.caerdonOwedTo, caerdonButton.caerdonOwedContext
    SettleOwedDraw(caerdonButton)
    if feature then
        Contained(feature.OnButtonOnScreen, feature, context)
    end
end

-- Returns false when nothing was noted, and the caller asks for the button as usual: it is on
-- screen after all, or it has never been asked for and so has no overlay to tell of its coming.
function CaerdonWardrobeMixin:AskWhenOnScreen(button, feature, context)
    local caerdonButton = self:GetCaerdonButton(button)
    if not caerdonButton or caerdonButton:IsVisible() then
        return false
    end
    caerdonButton.caerdonOwedTo, caerdonButton.caerdonOwedContext = feature, context
    caerdonButton:SetScript("OnShow", PayOwedDraw)
    return true
end

function CaerdonWardrobeMixin:ClearButton(button)
    local caerdonButton = self:GetCaerdonButton(button)
    if caerdonButton then
        if caerdonButton.caerdonOwedTo then
            SettleOwedDraw(caerdonButton)
        end

        -- Every list of requests is kept by button (see UpdateButton), so nothing is searched.
        self.waitingToProcess[button] = nil
        self.processQueue[button] = nil
        for _, items in pairs(self.featureProcessItems) do
            items[button] = nil
        end

        self:SetItemButtonStatus(button)
        self:SetItemButtonBindType(button)
    end
end

function CaerdonWardrobeMixin:CancelPending(feature)
    for queueKey, request in pairs(self.waitingToProcess) do
        if request.feature == feature then
            self.waitingToProcess[queueKey] = nil
        end
    end
    for queueKey, request in pairs(self.processQueue) do
        if request.feature == feature then
            self.processQueue[queueKey] = nil
        end
    end
    if self.featureProcessContinuables[feature] then
        self.featureProcessContinuables[feature]:Cancel()
    end
    self.featureProcessItems[feature] = nil
end

function CaerdonWardrobeMixin:UpdateButton(button, item, feature, locationInfo, options)
    local caerdonButton, createdNew = self:SetupCaerdonButton(button, item, feature, locationInfo, options)

    -- Whatever was owed to the button (AskWhenOnScreen) is asked for now.
    if caerdonButton and caerdonButton.caerdonOwedTo then
        SettleOwedDraw(caerdonButton)
    end

    -- A new request gets its own set of "not ready yet" retries; a retry keeps counting.
    local retryState = GetButtonState(button)
    if retryState then
        if retryState.retryingNotReady then
            retryState.retryingNotReady = nil
        else
            retryState.notReadyRetries = nil
        end
    end

    if item == nil then
        self:ClearButton(button)
        return
    elseif item:IsItemEmpty() and item:GetCaerdonItemType() == CaerdonItemType.Empty then
        self:ClearButton(button)
        return
    end

    if createdNew then
        self:SetItemButtonStatus(button, item, feature, locationInfo, options, "waiting", nil, nil)
    end

    local locationKey = GetRequestKey(item, feature, locationInfo)

    if locationKey then -- a request with no place of its own is not queued
        self:SetButtonLocationKey(button, locationKey)

        if not item:IsItemEmpty() then
            local itemID = item:GetItemID()
            if self:GetButtonItemID(button) ~= itemID then
                self:SetButtonItemID(button, itemID)
                self:ClearButton(button)
            end
        end

        -- One pending request per button, not per location. Two buttons of a feature can show
        -- the same slot (BetterBags' food and drink bar beside its bag), and kept per location
        -- the later request replaced the earlier one, whose button was then not drawn.
        -- A window often asks for a button more than once before it is drawn; the request that
        -- is still waiting is the one that gets the new answer.
        local queueKey = button or locationKey
        local request = self.waitingToProcess[queueKey]
        if not request then
            request = {}
            self.waitingToProcess[queueKey] = request
        end
        request.button, request.item, request.feature = button, item, feature
        request.locationInfo, request.options, request.locationKey = locationInfo, options, locationKey
        if not milestones.firstRequest then
            Counters:Milestone("firstRequest")
        end

        self:WakeQueue()

        return
    end
end

-- How long one frame's pass over the queue may take, in seconds. The queue used to draw twenty
-- items a frame whatever they cost: where a draw is cheap (a status already worked out) that
-- spread a window over more frames than it needed, and where it is dear (a first look at a bag
-- of equipment) twenty were a frame of 35 ms and more. One item is always drawn, however long
-- it takes.
local QUEUE_FRAME_BUDGET = 0.008

-- Starts the queue's passes when it was idle. The first pass is in a later frame than the
-- request, never the same one: a window asks for its buttons from inside its own update, and
-- what it does to them after that call is then done. GetTime() is the frame's time, the same
-- for every call in a frame.
function CaerdonWardrobeMixin:WakeQueue()
    if not self:GetScript("OnUpdate") then
        self.queueWokenAt = GetTime()
        self:SetScript("OnUpdate", self.OnUpdate)
    end
end

-- Whether nothing is asked for that has not been drawn: nothing in the queue, nothing waiting
-- for an item to load or for its tooltip.
function CaerdonWardrobeMixin:IsQueueIdle()
    if next(self.waitingToProcess) ~= nil or next(self.processQueue) ~= nil then
        return false
    end
    if self.pendingTooltipRetries and next(self.pendingTooltipRetries) ~= nil then
        return false
    end
    for _, items in pairs(self.featureProcessItems) do
        if next(items) ~= nil then
            return false
        end
    end
    return true
end

-- The draw of one queued item. An error in it costs this button its icon (none is better than
-- a stale one) and the rest of the batch goes on.
function CaerdonWardrobeMixin:ProcessQueuedItem(button, item, feature, locationInfo, options)
    if not Contained(self.ProcessItem, self, button, item, feature, locationInfo, options) then
        Counters:Unwound()
        Contained(self.ClearButton, self, button)
    end
end

-- One request off the queue: drawn, set aside until its item has loaded, or dropped.
function CaerdonWardrobeMixin:ProcessRequest(queueKey, request)
    local button, item, feature = request.button, request.item, request.feature
    local locationInfo = request.locationInfo

    -- The button has since been asked for another place, or was given up (ClearButtonState).
    -- Whatever was asked last stands: this request is not drawn, and it clears nothing either,
    -- since a newer request for the button may be waiting.
    if self:GetButtonLocationKey(button) ~= request.locationKey then
        return
    end
    if not feature:IsSameItem(button, item, locationInfo) then
        self:ClearButton(button)
        return
    end

    -- An empty item is a battle pet or the like: nothing to load.
    if item:IsItemEmpty() or item:IsItemDataCached() then
        self:ProcessQueuedItem(button, item, feature, locationInfo, request.options)
        return
    end

    -- Its data has to come from the client first. A feature's items wait together in one
    -- container, which DrainQueue sends off once the batch is through.
    local container = self.featureProcessContinuables[feature]
    if not container then
        container = ContinuableContainer:Create()
        self.featureProcessContinuables[feature] = container
    end
    -- The container asks the client for the item here; the counters file the question under
    -- the feature.
    Counters.requester = feature:GetName()
    container:AddContinuable(item)
    Counters.requester = nil
    local items = self.featureProcessItems[feature]
    if not items then
        items = {}
        self.featureProcessItems[feature] = items
    end
    items[queueKey] = request
end

-- One frame's work on the queue, until the time is up. Returns true when nothing is left to
-- draw (items still loading are not the queue's: they wake it when they arrive).
function CaerdonWardrobeMixin:DrainQueue(deadline)
    -- What was asked for before a batch is started is that batch. A request made while it is
    -- worked on (a draw that makes its window ask again, an item that came back unloaded)
    -- waits for the next batch, a frame later at the earliest, so nothing can keep one pass
    -- going in circles.
    local queue = self.processQueue
    if next(queue) == nil then
        queue = self.waitingToProcess
        self.waitingToProcess = self.processQueue
        self.processQueue = queue
    end

    local queueKey, request = next(queue)
    while queueKey ~= nil do
        queue[queueKey] = nil
        self:ProcessRequest(queueKey, request)
        if GetTimePreciseSec() >= deadline then
            break
        end
        queueKey, request = next(queue)
    end
    if next(queue) ~= nil then
        return false
    end

    -- The batch is through: what it found unloaded is asked for now. The requests come back
    -- through waitingToProcess, so they are picked up whenever the answer arrives.
    for feature, container in pairs(self.featureProcessContinuables) do
        self.featureProcessContinuables[feature] = nil
        container:ContinueOnLoad(function()
            local items = self.featureProcessItems[feature]
            if items then
                self.featureProcessItems[feature] = nil
                for itemKey, itemRequest in pairs(items) do
                    -- A newer request for the same button stands: this one is the older.
                    if self.waitingToProcess[itemKey] == nil then
                        self.waitingToProcess[itemKey] = itemRequest
                    end
                end
                self:WakeQueue()
            end
        end)
    end

    return next(self.waitingToProcess) == nil
end

function CaerdonWardrobeMixin:OnEvent(event, ...)
    -- For the counters: a full refresh asked for from inside a handler is this event's.
    local outerEvent = Counters.event
    Counters.event = event

    local handler = self[event]
    if (handler) then
        handler(self, ...)
    end

    local handlers = eventFeatureHandlers[event]
    if handlers then
        for i = 1, #handlers do
            local entry = handlers[i]
            Contained(entry.handler, entry.instance, ...)
        end
    end

    Counters.event = outerEvent
end

function CaerdonWardrobeMixin:OnUpdate()
    -- Pause processing during combat to avoid tainting Blizzard's secure
    -- frame operations (GetWidth, etc.) which cause errors in 12.0.1+.
    if InCombatLockdown() then
        return
    end

    -- Not in the frame the work arrived in (see WakeQueue).
    if self.queueWokenAt == GetTime() then
        return
    end
    self.queueWokenAt = nil

    if Counters.on then
        Counters:BeginPass()
    end
    local finished = self:DrainQueue(GetTimePreciseSec() + QUEUE_FRAME_BUDGET)
    if Counters.on then
        Counters:EndPass(finished)
    end

    if finished then
        -- Nothing to process - unregister until new work arrives
        self:SetScript("OnUpdate", nil)
        if milestones.firstDraw and not milestones.queueIdle then
            Counters:Milestone("queueIdle")
        end
    end
end

function CaerdonWardrobeMixin:PLAYER_ENTERING_WORLD()
end

function CaerdonWardrobeMixin:PLAYER_LOGOUT()
end

function CaerdonWardrobeMixin:VARIABLES_LOADED()
end

function CaerdonWardrobeMixin:ADDON_LOADED(name)
    if name == ADDON_NAME then
        local name, instance
        for name, instance in pairs(availableFeatures) do
            registeredFeatures[name] = instance
            local finished, instanceEvents = Contained(instance.Init, instance, self)
            -- Read by the integration report: false for an Init that raised an error. Such a
            -- feature gets no events; the features after it start as usual.
            instance.initFinished = finished
            if finished and instanceEvents then
                for i = 1, #instanceEvents do
                    -- An event name, or { name, unit } for a unit event wanted for one unit only.
                    local eventName, unit = instanceEvents[i], nil
                    if type(eventName) == "table" then
                        eventName, unit = eventName[1], eventName[2]
                    end
                    if unit then
                        self:RegisterUnitEvent(eventName, unit)
                    else
                        self:RegisterEvent(eventName)
                    end
                    if not eventFeatureHandlers[eventName] then
                        eventFeatureHandlers[eventName] = {}
                    end
                    local handler = instance[eventName]
                    if handler then
                        eventFeatureHandlers[eventName][#eventFeatureHandlers[eventName] + 1] = {
                            instance = instance,
                            handler = handler,
                        }
                    end
                end
            end
        end
        -- elseif name == "TradeSkillMaster" then
        -- 	print("HOOKING TSM")
        -- 	hooksecurefunc (TSM.UI.AuctionScrollingTable, "_SetRowData", function (self, row, data)
        -- 		print("Row: " .. row:GetField("auctionId"))
        -- 	end)
    end
end

-- Every verdict is thrown away and every window asked to draw again. `reason` is the refresh's
-- name in the counters ("skills", "quests") and `detail` what changed, in words; without a
-- reason it is filed under the event the frame is handling, or the line that asked.
function CaerdonWardrobeMixin:RefreshItems(reason, detail)
    Counters:NoteRefresh(type(reason) == "string" and reason or nil, type(detail) == "string" and detail or nil)

    if self.refreshTimer then
        self.refreshTimer:Cancel()
    end

    -- Invalidate cached status results since game state has changed
    CaerdonItem:InvalidateStatusCache()
    CaerdonEquipment:InvalidateCaches()
    CaerdonQuestItems:InvalidateCaches()
    CaerdonFoodDrink:InvalidateCaches()
    CaerdonProfessionTools:InvalidateCaches()
    CaerdonBagSlots:InvalidateCaches()
    CaerdonAuctionValue:InvalidateCaches()
    self.refreshGeneration = self.refreshGeneration + 1
    self.lastRefreshTime = GetTime()

    -- Defer the actual feature refresh during combat to avoid tainting
    -- Blizzard's secure frame operations. The cache invalidation above
    -- still happens immediately so stale data is cleared.
    if InCombatLockdown() then
        self.refreshPendingAfterCombat = true
        return
    end

    self.refreshTimer = C_Timer.NewTimer(0.1, function()
        local name, instance
        for name, instance in pairs(registeredFeatures) do
            Contained(instance.Refresh, instance)
        end
    end, 1)
end

-- Talent points were spent, reset or swapped. Only a change of the leading talent tree matters
-- (it picks which Pawn scales count as the toon's own), so the icons are refreshed only then.
-- Retail has no talent tree groups: the lookup is nil before and after and nothing happens.
function CaerdonWardrobeMixin:OnTalentsChanged()
    if self.talentChangeTimer then
        return
    end

    self.talentChangeTimer = C_Timer.NewTimer(0.5, function()
        self.talentChangeTimer = nil
        local before = CaerdonAPI:GetPrimaryTalentTree()
        CaerdonAPI:InvalidateTalentTrees()
        local after = CaerdonAPI:GetPrimaryTalentTree()
        if before ~= after then
            self:RefreshItems("talents", ("leading tree: %s -> %s"):format(tostring(before), tostring(after)))
        end
    end)
end

function CaerdonWardrobeMixin:OnEquipPendingItem()
    -- TODO: Bit of a hack... wait a bit and then update...
    --       Need to figure out a better way.  Otherwise,
    --		 you end up with BoE markers on things you've put on.
    C_Timer.After(1, function() self:RefreshItems("equip pending") end)
end

-- Session log of the transmog collection events this frame received (oldest first).
-- Surfaced by the Debug Frame "Copy Details" export so "which events fired when that
-- appearance was learned, and did we refresh afterwards" can be answered from a paste.
local TRANSMOG_EVENT_LOG_MAX = 25
local transmogEventLog = {}

local function LogTransmogEvent(event, ...)
    local argCount = select("#", ...)
    local args = {}
    for index = 1, argCount do
        args[index] = tostring((select(index, ...)))
    end

    transmogEventLog[#transmogEventLog + 1] = {
        time = GetTime(),
        event = event,
        args = table.concat(args, ", "),
    }
    if #transmogEventLog > TRANSMOG_EVENT_LOG_MAX then
        table.remove(transmogEventLog, 1)
    end
end

-- Returns the event log (entries: time, event, args) and the GetTime() of the last RefreshItems.
function CaerdonWardrobeMixin:GetTransmogEventLog()
    return transmogEventLog, self.lastRefreshTime
end

-- The four collection events also tell the equipment code that what is collected changed, so the
-- refresh keeps nothing it was told about a source before (CaerdonEquipment:InvalidateCaches).
function CaerdonWardrobeMixin:TRANSMOG_COLLECTION_UPDATED(...)
    LogTransmogEvent("TRANSMOG_COLLECTION_UPDATED", ...)
    CaerdonEquipment:NoteCollectionChanged()
    self:RefreshItems()
end

function CaerdonWardrobeMixin:TRANSMOG_COLLECTION_SOURCE_ADDED(...)
    LogTransmogEvent("TRANSMOG_COLLECTION_SOURCE_ADDED", ...)
    CaerdonEquipment:NoteCollectionChanged()
    self:RefreshItems()
end

function CaerdonWardrobeMixin:TRANSMOG_COLLECTION_SOURCE_REMOVED(...)
    LogTransmogEvent("TRANSMOG_COLLECTION_SOURCE_REMOVED", ...)
    CaerdonEquipment:NoteCollectionChanged()
    self:RefreshItems()
end

function CaerdonWardrobeMixin:TRANSMOG_COSMETIC_COLLECTION_SOURCE_ADDED(...)
    LogTransmogEvent("TRANSMOG_COSMETIC_COLLECTION_SOURCE_ADDED", ...)
    CaerdonEquipment:NoteCollectionChanged()
    self:RefreshItems()
end

function CaerdonWardrobeMixin:EQUIPMENT_SETS_CHANGED()
    self:RefreshItems()
end

function CaerdonWardrobeMixin:PLAYER_EQUIPMENT_CHANGED()
    self:RefreshItems()
end

function CaerdonWardrobeMixin:EQUIPMENT_SWAP_FINISHED()
    self:RefreshItems()
end

function CaerdonWardrobeMixin:UPDATE_EXPANSION_LEVEL()
    -- Can change while logged in!
    self:RefreshItems()
end

function CaerdonWardrobeMixin:NEW_RECIPE_LEARNED()
    self:RefreshItems()
end

function CaerdonWardrobeMixin:PLAYER_REGEN_ENABLED()
    -- Combat ended: process any deferred refresh. The queue's passes go on by themselves.
    if self.refreshPendingAfterCombat then
        self.refreshPendingAfterCombat = nil
        self:RefreshItems("after combat")
    end
end

function CaerdonWardrobeMixin:NEW_MOUNT_ADDED()
    self:RefreshItems()
end

function CaerdonWardrobeMixin:NEW_TOY_ADDED()
    self:RefreshItems()
end

function CaerdonWardrobeMixin:NEW_PET_ADDED()
    self:RefreshItems()
end
