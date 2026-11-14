-- Button geometry recorder (debug only).
--
-- Every window and bag addon integration passes its own size and offsets for the status icon and
-- the binding text. To find out which of those differences are forced by the button itself
-- (its size, what the overlay sits on, a parent that clips) this records, for each window drawn
-- while debug is enabled, what the last decorated button really looked like. Nothing here
-- changes how anything is drawn.
--
-- CaerdonWardrobeMixin:ProcessItem calls Note() after a button is drawn. Note() only remembers
-- the button; the measuring happens a moment later, once the client has laid the frames out,
-- and at most one button per window and option set is measured each time. The Debug Frame
-- export prints the result ("[Button Geometry]") through GetReportLines().
--
-- All sizes are in the decorated button's own units, so they compare directly with the numbers
-- the integrations pass. "Outside" is how far a part sticks out of the frame the overlay is laid
-- over (negative: that far inside).

local ADDON_NAME, NS = ...

CaerdonButtonGeometry = {}

local MAX_SHAPES_PER_WINDOW = 6
local MEASURE_DELAY = 0.2
local MAX_PARENT_DEPTH = 40

-- The display options an integration can pass. hasCount depends on the item, so it is reported
-- but does not make a different shape.
local OPTION_KEYS = {
    "statusProminentSize", "statusOffsetX", "statusOffsetY", "statusScale",
    "statusBackgroundOffsetX", "statusBackgroundOffsetY", "overrideStatusPosition", "fixedStatusPosition",
    "bindingScale", "bindingOffsetX", "bindingOffsetY", "overrideBindingPosition", "itemCountOffset",
    "keepInsideWhenClipped"
}
-- Where a button usually keeps its own item icon, to see whether the overlay could sit on it.
local ICON_KEYS = { "icon", "Icon", "IconTexture", "ItemIcon", "Item", "NormalTexture", "TagTexture", "rewardicon" }
-- NormalTexture and the like are valid things to lay the overlay on, but they are not an item icon.
local OWN_ICON_KEYS = { "icon", "Icon", "IconTexture", "ItemIcon", "Item" }
local COUNT_KEYS = { "Count", "count" }

local windows = {}      -- [windowName] = { shapes = { [signature] = sample }, order = { signature, ... }, dropped = n }
local windowOrder = {}
local pending = {}      -- [windowName .. signature] = { window, signature, button, options, ... }
local measureScheduled = false
local lastError

local function IsRecording()
    return CaerdonWardrobeConfig and CaerdonWardrobeConfig.Debug and CaerdonWardrobeConfig.Debug.Enabled and true or false
end

local function FormatOption(value)
    if type(value) == "number" then
        return (string.format("%.2f", value):gsub("%.?0+$", ""))
    end
    return tostring(value)
end

local function DescribeOptions(options, includeCount)
    local parts = {}
    for _, key in ipairs(OPTION_KEYS) do
        if options[key] ~= nil then
            parts[#parts + 1] = key .. "=" .. FormatOption(options[key])
        end
    end
    if includeCount and options.hasCount ~= nil then
        parts[#parts + 1] = "hasCount=" .. tostring(options.hasCount)
    end
    return table.concat(parts, ", ")
end

local function ShortName(region)
    local name = region and region.GetDebugName and region:GetDebugName() or "?"
    if #name > 70 then
        name = "..." .. name:sub(-67)
    end
    return name
end

-- Screen rectangle of a region, or nil while it has no layout yet.
local function GetRectOf(region)
    if not (region and region.GetScaledRect) then
        return nil
    end
    local left, bottom, width, height = region:GetScaledRect()
    if not (left and bottom and width and height) or width <= 0 or height <= 0 then
        return nil
    end
    return { left = left, bottom = bottom, right = left + width, top = bottom + height, width = width, height = height }
end

-- How far "inner" sticks out of "outer" on each side, in button units (negative: inside).
local function Outside(inner, outer, scale)
    return {
        left = (outer.left - inner.left) / scale,
        top = (inner.top - outer.top) / scale,
        right = (inner.right - outer.right) / scale,
        bottom = (outer.bottom - inner.bottom) / scale
    }
end

local function GetFirstPoint(region)
    if not (region and region.GetNumPoints and region:GetNumPoints() > 0) then
        return nil
    end
    local point, _, relativePoint, x, y = region:GetPoint(1)
    return { point = point, relativePoint = relativePoint, x = x or 0, y = y or 0 }
end

-- The closest frame, starting with the button itself, that cuts off anything drawn outside it.
local function FindClippingParent(frame)
    local depth = 0
    while frame and depth < MAX_PARENT_DEPTH do
        if (frame.DoesClipChildren and frame:DoesClipChildren()) or
            (frame.GetObjectType and frame:GetObjectType() == "ScrollFrame") then
            return frame, depth
        end
        frame = frame.GetParent and frame:GetParent()
        depth = depth + 1
    end
    return nil
end

local function FindKeyFor(button, region)
    for _, key in ipairs(ICON_KEYS) do
        if button[key] == region then
            return key
        end
    end
    return nil
end

-- Sizes and positions cannot tell a round or framed button from a plain square slot; the art can.
-- A mask is how the client cuts an icon to a shape, and the atlas names of the button's own
-- textures usually say what frames it. A mask alone does not mean round: rounded corners are a
-- mask too (BetterBags' slots), so the mask's own art is named as well.
local MAX_SHAPE_REGIONS = 40
local MAX_SHAPE_ATLASES = 6
local MAX_MASK_NAMES = 3

-- The two masks Blizzard's item button template uses (Blizzard_ItemButton/ItemButtonTemplate.xml).
-- In game a mask set from a file reports only its file ID, so these are resolved to IDs once and
-- matched, to say what the mask is instead of printing a number.
local KNOWN_MASKS = {
    { path = "Interface\\CharacterFrame\\TempPortraitAlphaMask", label = "circle (TempPortraitAlphaMask)" },
    { path = "Interface\\Common\\common-iconmask", label = "standard item slot (common-iconmask)" },
}
local knownMaskLabels

local function LabelMask(name)
    if not knownMaskLabels then
        knownMaskLabels = {}
        for _, known in ipairs(KNOWN_MASKS) do
            knownMaskLabels[known.path:lower()] = known.label
            if GetFileIDFromPath then
                local ok, fileID = pcall(GetFileIDFromPath, known.path)
                if ok and fileID then
                    knownMaskLabels[tostring(fileID)] = known.label
                end
            end
        end
    end

    name = tostring(name)
    local fileID = name:match("^file (%-?%d+)$") or name:match("^(%-?%d+)$")
    if fileID then
        if fileID:sub(1, 1) == "-" then
            -- The client numbers files that ship with an addon from -1 downwards, per session.
            return "an addon's own mask (file " .. fileID .. ")"
        end
        return knownMaskLabels[fileID] or ("file " .. fileID .. " (not a known mask)")
    end
    return knownMaskLabels[(name:lower():gsub("/", "\\"))] or name
end

-- The art of each mask on a region: its atlas, else its file path, else its file ID.
local function DescribeMasks(region)
    local count = 0
    if type(region) == "table" and region.GetNumMaskTextures then
        count = region:GetNumMaskTextures() or 0
    end
    if count == 0 or not region.GetMaskTexture then
        return nil
    end
    local names = {}
    for index = 1, math.min(count, MAX_MASK_NAMES) do
        local ok, mask = pcall(region.GetMaskTexture, region, index)
        local name
        if ok and type(mask) == "table" then
            local okName, found = pcall(function()
                local atlas = mask.GetAtlas and mask:GetAtlas()
                if atlas and atlas ~= "" then
                    return atlas
                end
                local path = mask.GetTextureFilePath and mask:GetTextureFilePath()
                if path and path ~= "" then
                    return tostring(path)
                end
                local fileID = mask.GetTextureFileID and mask:GetTextureFileID()
                return fileID and ("file " .. tostring(fileID)) or nil
            end)
            name = okName and found or nil
        end
        names[#names + 1] = name and LabelMask(name) or "unnamed mask"
    end
    return table.concat(names, ", ")
end

local function MaskCount(region)
    if type(region) == "table" and region.GetNumMaskTextures then
        return region:GetNumMaskTextures() or 0
    end
    return 0
end

local function GetShapeHints(button)
    local hints = { masked = 0, atlases = {} }
    if not button.GetRegions then
        return hints
    end
    local regions = { button:GetRegions() }
    local seen = {}
    for index = 1, math.min(#regions, MAX_SHAPE_REGIONS) do
        local region = regions[index]
        if region.GetObjectType and region:GetObjectType() == "Texture" and region:IsShown() then
            if MaskCount(region) > 0 then
                hints.masked = hints.masked + 1
            end
            local atlas = region.GetAtlas and region:GetAtlas()
            if atlas and atlas ~= "" and not seen[atlas] and #hints.atlases < MAX_SHAPE_ATLASES then
                seen[atlas] = true
                hints.atlases[#hints.atlases + 1] = atlas
            end
        end
    end
    return hints
end

local function StripColors(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function IsDrawn(region)
    return region and region:IsShown() and (region:GetAlpha() or 0) > 0
end

local function HasTexture(texture)
    local file = texture and texture.GetTexture and texture:GetTexture()
    if file ~= nil and file ~= "" then
        return true
    end
    local atlas = texture and texture.GetAtlas and texture:GetAtlas()
    return atlas ~= nil and atlas ~= ""
end

-- Measures one remembered button. Returns the sample, or nil when the button has no layout
-- right now (hidden, recycled, not placed yet).
local function Measure(entry)
    local button = entry.button
    local caerdonButton = CaerdonWardrobe:GetCaerdonButton(button)
    if not (caerdonButton and button.IsVisible and button:IsVisible()) then
        return nil
    end

    local buttonRect = GetRectOf(button)
    local scale = button:GetEffectiveScale()
    if not (buttonRect and scale and scale > 0) then
        return nil
    end

    local overlayOn = entry.relativeFrame or button
    local overlayRect = GetRectOf(overlayOn)
    if not overlayRect then
        return nil
    end

    local sample = {
        time = GetTime(),
        status = entry.status,
        options = entry.optionsText,
        button = {
            name = ShortName(button),
            type = button:GetObjectType(),
            width = buttonRect.width / scale,
            height = buttonRect.height / scale,
            scale = scale
        },
        shape = GetShapeHints(button),
        overlay = {
            isButton = overlayOn == button,
            key = overlayOn ~= button and FindKeyFor(button, overlayOn) or nil,
            name = overlayOn ~= button and ShortName(overlayOn) or nil,
            type = overlayOn.GetObjectType and overlayOn:GetObjectType() or "?",
            width = overlayRect.width / scale,
            height = overlayRect.height / scale,
            masks = DescribeMasks(overlayOn),
            -- from the button's top left corner, positive right / down
            x = (overlayRect.left - buttonRect.left) / scale,
            y = (buttonRect.top - overlayRect.top) / scale
        }
    }

    -- The button's own icon, when the overlay is not already sitting on it.
    if overlayOn == button then
        for _, key in ipairs(OWN_ICON_KEYS) do
            local region = button[key]
            local rect = type(region) == "table" and region ~= button and GetRectOf(region)
            if rect then
                sample.ownIcon = {
                    key = key,
                    masks = DescribeMasks(region),
                    width = rect.width / scale,
                    height = rect.height / scale,
                    x = (rect.left - buttonRect.left) / scale,
                    y = (buttonRect.top - rect.top) / scale
                }
                break
            end
        end
    end

    local mogStatus = caerdonButton.mogStatus
    local iconRect = IsDrawn(mogStatus) and GetRectOf(mogStatus)
    if iconRect then
        local background = mogStatus.mogStatusBackground
        local backgroundRect = IsDrawn(background) and GetRectOf(background)
        sample.icon = {
            status = entry.status,
            empty = not HasTexture(mogStatus),
            width = iconRect.width / scale,
            height = iconRect.height / scale,
            ratio = (iconRect.width / scale) / math.min(overlayRect.width / scale, overlayRect.height / scale),
            point = GetFirstPoint(mogStatus),
            outside = Outside(iconRect, overlayRect, scale),
            backgroundWidth = backgroundRect and backgroundRect.width / scale or nil,
            backgroundOutside = backgroundRect and Outside(backgroundRect, overlayRect, scale) or nil
        }
    end

    local bindsOnText = caerdonButton.bindsOnText
    local text = bindsOnText and StripColors(bindsOnText:GetText())
    local textRect = text and text ~= "" and IsDrawn(bindsOnText) and GetRectOf(bindsOnText)
    if textRect then
        local _, fontHeight = bindsOnText:GetFont()
        sample.text = {
            text = text,
            fontHeight = fontHeight,
            scale = bindsOnText:GetScale(),
            stringWidth = bindsOnText:GetStringWidth(),
            width = textRect.width / scale,
            height = textRect.height / scale,
            point = GetFirstPoint(bindsOnText),
            outside = Outside(textRect, overlayRect, scale)
        }
    end

    local deltaText = caerdonButton.upgradeDeltaText
    local delta = deltaText and deltaText:GetText()
    local deltaRect = delta and delta ~= "" and IsDrawn(deltaText) and GetRectOf(deltaText)
    if deltaRect then
        sample.delta = {
            text = delta,
            point = GetFirstPoint(deltaText),
            outside = Outside(deltaRect, overlayRect, scale)
        }
    end

    for _, key in ipairs(COUNT_KEYS) do
        local region = button[key]
        if type(region) == "table" and region.GetText then
            local countText = region:GetText()
            local rect = countText and countText ~= "" and IsDrawn(region) and GetRectOf(region)
            if rect then
                sample.count = {
                    text = countText,
                    -- how far up from the overlay's bottom edge the stack count reaches
                    reach = (rect.top - overlayRect.bottom) / scale,
                    left = (rect.left - overlayRect.left) / scale
                }
            end
            break
        end
    end

    local clipper, depth = FindClippingParent(button)
    local clipperRect = clipper and GetRectOf(clipper)
    if clipper then
        sample.clip = {
            name = ShortName(clipper),
            type = clipper:GetObjectType(),
            depth = depth
        }
        if clipperRect then
            -- room between the overlay's edges and the clipping frame's edges
            local outside = Outside(overlayRect, clipperRect, scale)
            sample.clip.room = { left = -outside.left, top = -outside.top, right = -outside.right, bottom = -outside.bottom }
        end
    end

    return sample
end

-- Keeps the newest measurement of each part; a draw without an icon must not erase the icon
-- numbers a previous draw gave.
local function Store(entry, sample)
    local window = windows[entry.window]
    local previous = window.shapes[entry.signature]
    if previous then
        -- a placed but empty icon region never replaces the numbers of a visible icon
        if not sample.icon or (sample.icon.empty and previous.icon and not previous.icon.empty) then
            sample.icon = previous.icon
        end
        sample.text = sample.text or previous.text
        sample.delta = sample.delta or previous.delta
        sample.count = sample.count or previous.count
        if sample.clip and sample.clip.room and previous.leastRoom then
            local room, least = sample.clip.room, previous.leastRoom
            sample.leastRoom = {
                left = math.min(room.left, least.left), top = math.min(room.top, least.top),
                right = math.min(room.right, least.right), bottom = math.min(room.bottom, least.bottom)
            }
        else
            sample.leastRoom = previous.leastRoom
        end
        sample.measured = (previous.measured or 0) + 1
    else
        sample.measured = 1
    end
    if not sample.leastRoom and sample.clip and sample.clip.room then
        local room = sample.clip.room
        sample.leastRoom = { left = room.left, top = room.top, right = room.right, bottom = room.bottom }
    end
    window.shapes[entry.signature] = sample
end

local function MeasurePending()
    measureScheduled = false
    local batch = pending
    pending = {}
    for _, entry in pairs(batch) do
        local ok, result = pcall(Measure, entry)
        if ok then
            if result then
                Store(entry, result)
            end
        else
            lastError = tostring(result)
        end
    end
end

-- Remembers a button that was just drawn. Cheap on purpose: this runs for every decorated
-- button while debug is enabled.
function CaerdonButtonGeometry:Note(feature, button, options, mogStatus, bindingStatus)
    if not (feature and button and button.GetSize) then
        return
    end
    local windowName = feature:GetName()
    if windowName == "DebugFrame" then
        return
    end
    options = options or {}

    local width, height = button:GetSize()
    if not (width and height) or width < 1 or height < 1 then
        return -- not laid out yet; it is drawn again once it is
    end
    -- No "|" in here: the export is read in an edit box, where "|r" and friends are escapes.
    local signature = string.format("%s ; overlay on %s ; %dx%d", DescribeOptions(options, false),
        options.relativeFrame and "relativeFrame" or "button", math.floor(width + 0.5), math.floor(height + 0.5))

    local window = windows[windowName]
    if not window then
        window = { shapes = {}, order = {}, seen = {}, dropped = 0 }
        windows[windowName] = window
        windowOrder[#windowOrder + 1] = windowName
    end
    if not window.seen[signature] then
        if #window.order >= MAX_SHAPES_PER_WINDOW then
            window.dropped = window.dropped + 1
            return
        end
        window.seen[signature] = 0
        window.order[#window.order + 1] = signature
    end
    window.seen[signature] = window.seen[signature] + 1

    local caerdonButton = CaerdonWardrobe:GetCaerdonButton(button)
    local hasIcon = caerdonButton and IsDrawn(caerdonButton.mogStatus) and HasTexture(caerdonButton.mogStatus) or false
    local key = windowName .. "\n" .. signature
    local existing = pending[key]
    -- One button per shape is measured each time; prefer one that actually shows an icon.
    if not existing or hasIcon or not existing.hasIcon then
        pending[key] = {
            window = windowName,
            signature = signature,
            button = button,
            relativeFrame = options.relativeFrame,
            -- described now: the draw code can write into this table for later buttons
            optionsText = DescribeOptions(options, true),
            status = mogStatus,
            hasIcon = hasIcon
        }
    end

    if not measureScheduled then
        measureScheduled = true
        C_Timer.After(MEASURE_DELAY, MeasurePending)
    end
end

local function Num(value)
    if value == nil then
        return "?"
    end
    return string.format("%.1f", value)
end

local function Sides(sides)
    return string.format("L %s  T %s  R %s  B %s", Num(sides.left), Num(sides.top), Num(sides.right), Num(sides.bottom))
end

local function Point(point)
    if not point then
        return "no anchor"
    end
    return string.format("%s to %s, %s / %s", tostring(point.point), tostring(point.relativePoint), Num(point.x), Num(point.y))
end

-- The export text, as { indent, text } rows.
function CaerdonButtonGeometry:GetReportLines()
    local lines = {}
    local function add(indent, text)
        lines[#lines + 1] = { indent = indent, text = text }
    end

    add(1, "Recording: " .. (IsRecording() and "on" or "off (turn on Enable debug, then open the windows to measure)"))
    add(1, "Units: the decorated button's own. Outside = how far a part sticks out of the frame the overlay is on (negative = inside).")
    if UIParent and UIParent.GetEffectiveScale then
        add(1, "UI scale: " .. string.format("%.3f", UIParent:GetEffectiveScale()))
    end
    if lastError then
        add(1, "Last measuring error: " .. lastError)
    end
    if #windowOrder == 0 then
        add(1, "Windows: none recorded this session")
        return lines
    end

    local now = GetTime()
    for _, windowName in ipairs(windowOrder) do
        local window = windows[windowName]
        add(1, windowName)
        if window.dropped > 0 then
            add(2, string.format("(%d draws with further option sets not recorded)", window.dropped))
        end
        for index, signature in ipairs(window.order) do
            local sample = window.shapes[signature]
            local seen = window.seen[signature] or 0
            if not sample then
                add(2, string.format("Shape %d: drawn %d times, never measurable (hidden or not laid out)", index, seen))
                add(3, "Signature: " .. signature)
            else
                add(2, string.format("Shape %d: drawn %d times, measured %d, last %.1fs ago", index, seen,
                    sample.measured or 0, now - sample.time))
                add(3, "Options: " .. (sample.options ~= "" and sample.options or "none (defaults)"))
                add(3, string.format("Button: %s x %s  %s  scale %.3f  %s", Num(sample.button.width),
                    Num(sample.button.height), sample.button.type, sample.button.scale, sample.button.name))
                if sample.overlay.isButton then
                    add(3, "Overlay on: the button itself")
                else
                    add(3, string.format("Overlay on: %s (%s) %s x %s, at %s / %s from the button's top left%s",
                        sample.overlay.key and ("button." .. sample.overlay.key) or sample.overlay.name,
                        sample.overlay.type, Num(sample.overlay.width), Num(sample.overlay.height),
                        Num(sample.overlay.x), Num(sample.overlay.y),
                        sample.overlay.masks and (", masked by: " .. sample.overlay.masks) or ""))
                end
                if sample.ownIcon then
                    add(3, string.format("Button's own icon: button.%s %s x %s, at %s / %s from the button's top left%s",
                        sample.ownIcon.key, Num(sample.ownIcon.width), Num(sample.ownIcon.height),
                        Num(sample.ownIcon.x), Num(sample.ownIcon.y),
                        sample.ownIcon.masks and (", masked by: " .. sample.ownIcon.masks) or ""))
                end
                if sample.shape then
                    local atlases = #sample.shape.atlases > 0 and table.concat(sample.shape.atlases, ", ") or "none"
                    add(3, string.format("Shape hints: %d masked texture%s among the button's own regions; atlases shown: %s",
                        sample.shape.masked, sample.shape.masked == 1 and "" or "s", atlases))
                end
                if sample.icon then
                    add(3, string.format("Icon (%s%s): %s x %s, %.2f of the overlay's short side, anchored %s",
                        tostring(sample.icon.status), sample.icon.empty and ", placed but no texture" or "",
                        Num(sample.icon.width), Num(sample.icon.height),
                        sample.icon.ratio, Point(sample.icon.point)))
                    add(4, "Outside: " .. Sides(sample.icon.outside))
                    if sample.icon.backgroundOutside then
                        add(4, string.format("Background: %s wide, outside: %s", Num(sample.icon.backgroundWidth),
                            Sides(sample.icon.backgroundOutside)))
                    end
                else
                    add(3, "Icon: none seen yet in this shape")
                end
                if sample.text then
                    add(3, string.format("Text \"%s\": font %s, scale %.2f, string width %s, box %s x %s, anchored %s",
                        sample.text.text, Num(sample.text.fontHeight), sample.text.scale or 1,
                        Num(sample.text.stringWidth), Num(sample.text.width), Num(sample.text.height),
                        Point(sample.text.point)))
                    add(4, "Outside: " .. Sides(sample.text.outside))
                else
                    add(3, "Text: none seen yet in this shape")
                end
                if sample.count then
                    add(3, string.format("Stack count \"%s\": reaches %s above the overlay's bottom, starts %s from its left",
                        tostring(sample.count.text), Num(sample.count.reach), Num(sample.count.left)))
                end
                if sample.delta then
                    add(3, string.format("Item level gain \"%s\": anchored %s, outside: %s", tostring(sample.delta.text),
                        Point(sample.delta.point), Sides(sample.delta.outside)))
                end
                if sample.clip then
                    local where = sample.clip.depth == 0 and "the button itself" or
                        string.format("%d level%s up", sample.clip.depth, sample.clip.depth == 1 and "" or "s")
                    add(3, string.format("Clipping parent: %s, %s, %s", sample.clip.type, where, sample.clip.name))
                    if sample.clip.room then
                        add(4, "Room around the overlay: " .. Sides(sample.clip.room))
                    end
                    if sample.leastRoom then
                        add(4, "Least room seen:         " .. Sides(sample.leastRoom))
                    end
                else
                    add(3, string.format("Clipping parent: none within %d levels", MAX_PARENT_DEPTH))
                end
            end
        end
    end

    return lines
end
