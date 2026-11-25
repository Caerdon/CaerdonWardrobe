local LootMixin = {}

-- What the loot list has handed over this session, for the export's [Loot Window] section. A
-- row is built once per slot when the window opens, with the slot's link where the client has
-- one by then, and the client says when it has changed a slot (LOOT_SLOT_CHANGED).
local built = { withLink = 0, withoutLink = 0 }
local changed = { withLink = 0, withoutLink = 0, noRow = 0 }
-- [row] = { builtWithLink, changes, fadeReadings }: how the row that is in the list now came
-- to its button.
local rowNotes = setmetatable({}, { __mode = "k" })
-- Rows whose fade-in is listened to (WatchFadeIn). A row is the list's and is used again.
local fadeWatched = setmetatable({}, { __mode = "k" })

function LootMixin:GetName()
    return "Loot"
end

function LootMixin:Init()
    -- The feature is the callback's owner. The list keeps one callback per owner, so one
    -- registered under the loot window itself is replaced by any addon that names it too.
    ScrollUtil.AddInitializedFrameCallback(LootFrame.ScrollBox, function(_, frame, elementData)
        rowNotes[frame] = nil
        self:WatchFadeIn(frame)
        self:AskForRow(frame, elementData, built)
    end, self, false)

    -- The window fades in as it opens, over its rows' own fade (WatchFadeIn).
    local windowFade = LootFrame.ShowAnim
    if windowFade and windowFade.HookScript then
        windowFade:HookScript("OnFinished", function()
            LootFrame.ScrollBox:ForEachFrame(function(frame)
                self:OnFadedIn(frame)
            end)
        end)
    end

    return { "LOOT_SLOT_CHANGED" }
end

-- A row fades in when the window fills it (its ShowAnim, a tenth of a second, played by the
-- row's Init), and the window fades in as it opens. An icon drawn while either runs comes out
-- of it with no alpha: seen on WoW Forever 1.60.1.71091, where a row's icon was in place,
-- shown, and had alpha 0 after a draw that had set 1. The queue draws a frame after the row is
-- built, which is inside the fade. So the row is asked for again when a fade has ended, and
-- that draw stays.
function LootMixin:WatchFadeIn(frame)
    local fade = frame.ShowAnim
    if fadeWatched[frame] or not (fade and fade.HookScript) then
        return
    end
    fadeWatched[frame] = true
    fade:HookScript("OnFinished", function()
        self:OnFadedIn(frame)
    end)
end

function LootMixin:OnFadedIn(frame)
    -- A row given back to the list shows no slot.
    local elementData = frame.Item and frame.GetElementData and frame:GetElementData()
    if not elementData then
        return
    end

    -- For the export: the icon's alpha as the fade left it, beside what the draw had set.
    local note = rowNotes[frame]
    local overlay = CaerdonWardrobe:GetCaerdonButton(frame.Item)
    local icon = overlay and overlay.mogStatus
    if note and icon then
        local readings = note.fadeReadings
        if not readings then
            readings = {}
            note.fadeReadings = readings
        end
        if #readings < 4 then
            readings[#readings + 1] = format("%.1f where the draw set %s", icon:GetAlpha() or -1,
                tostring(icon.assignedAlpha))
        end
    end

    self:AskForRow(frame, elementData)
end

function LootMixin:GetTooltipData(item, locationInfo)
    return C_TooltipInfo.GetLootItem(locationInfo.elementData.slotIndex)
end

-- One row of the list, asked for as its slot is now. `tally`: the count this ask belongs to.
--
-- A slot whose item the client has no data for yet has no link, and its button is cleared.
-- The row is not built again when the data comes: the window fills it in from
-- LOOT_SLOT_CHANGED, and so does this.
function LootMixin:AskForRow(frame, elementData, tally)
    local button = frame.Item
    if not button then
        return
    end

    local slotIndex = elementData.slotIndex
    local link = GetLootSlotLink(slotIndex)
    if tally and GetLootSlotType(slotIndex) == Enum.LootSlotType.Item then
        local key = link and "withLink" or "withoutLink"
        tally[key] = tally[key] + 1
        local note = rowNotes[frame]
        if not note then
            note = { changes = 0 }
            rowNotes[frame] = note
        end
        if tally == built then
            note.builtWithLink = link ~= nil
        else
            note.changes = note.changes + 1
        end
    end

    self:Decorate(button, link, {
        locationKey = format("%d", slotIndex),
        elementData = elementData
    })
end

-- The client changed what a slot holds, or has its item's data now. The window draws that
-- slot's row again without building it, so the list's callback does not come.
function LootMixin:LOOT_SLOT_CHANGED(slotIndex)
    local frame = LootFrame.ScrollBox:FindFrameByPredicate(function(row)
        return row:GetSlotIndex() == slotIndex
    end)
    if frame then
        self:AskForRow(frame, frame:GetElementData(), changed)
    else
        changed.noRow = changed.noRow + 1
    end
end

function LootMixin:Refresh()
    -- elementData: slotIndex, group (coin = 1 else 0), quality
    LootFrame.ScrollBox:ForEachFrame(function(frame, elementData)
        self:AskForRow(frame, elementData)
    end)
end

-- Where a frame is drawn among the others: its strata and level, and whether either is its
-- own (fixed) and so does not follow its parent's.
local function Stacking(frame)
    if type(frame) ~= "table" or not frame.GetFrameLevel then
        return "none"
    end
    local text = format("%s %s", tostring(frame:GetFrameStrata()), tostring(frame:GetFrameLevel()))
    local fixedStrata = frame.HasFixedFrameStrata and frame:HasFixedFrameStrata()
    local fixedLevel = frame.HasFixedFrameLevel and frame:HasFixedFrameLevel()
    if fixedStrata or fixedLevel then
        text = format("%s (own %s)", text, (fixedStrata and fixedLevel and "strata and level") or
            (fixedStrata and "strata") or "level")
    end
    return text
end

local function YesNo(value)
    return value and "yes" or "no"
end

local function Number(value)
    return type(value) == "number" and format("%.1f", value) or tostring(value)
end

-- How far a region's edges are inside another's, on screen, in units of `scale` (the
-- overlay's): left, top, right, bottom (negative: outside).
local function Inside(region, outer, scale)
    if not (region.GetScaledRect and outer.GetScaledRect) then
        return "not asked (the client has no rect for it)"
    end
    local left, bottom, width, height = region:GetScaledRect()
    local outerLeft, outerBottom, outerWidth, outerHeight = outer:GetScaledRect()
    if not (left and width and outerLeft and outerWidth and scale and scale > 0) then
        return "no place on screen"
    end
    return format("%s left, %s top, %s right, %s bottom", Number((left - outerLeft) / scale),
        Number(((outerBottom + outerHeight) - (bottom + height)) / scale),
        Number(((outerLeft + outerWidth) - (left + width)) / scale), Number((bottom - outerBottom) / scale))
end

-- A row's button as it is on screen: the frames it is stacked among, its overlay, and the
-- status icon on it. For an icon the addon drew that is not seen.
local function AddDrawnFacts(Add, frame)
    local button = frame.Item
    local overlay = button and CaerdonWardrobe:GetCaerdonButton(button)
    if not overlay then
        return
    end
    local list = LootFrame.ScrollBox
    local scale = overlay:GetEffectiveScale()
    Add(3, format("stacked: window %s, list %s, its shadows %s, row %s, button %s, overlay %s", Stacking(LootFrame),
        Stacking(list), Stacking(list.Shadows), Stacking(frame), Stacking(button), Stacking(overlay)))
    Add(3, format("overlay: shown %s, on screen %s, alpha %s (in effect %s), %s x %s, inside the list by %s",
        YesNo(overlay:IsShown()), YesNo(overlay:IsVisible()), Number(overlay:GetAlpha()), Number(overlay:GetEffectiveAlpha()),
        Number(overlay:GetWidth()), Number(overlay:GetHeight()), Inside(overlay, list, scale)))
    local icon = overlay.mogStatus
    if icon then
        local layer, sublayer = icon:GetDrawLayer()
        Add(3, format("icon: shown %s, on screen %s, alpha %s, texture %s, layer %s %s, %s x %s, inside the button by %s, inside the list by %s",
            YesNo(icon:IsShown()), YesNo(icon:IsVisible()), Number(icon:GetAlpha()),
            tostring((icon.GetAtlas and icon:GetAtlas()) or icon:GetTexture()), tostring(layer), tostring(sublayer),
            Number(icon:GetWidth()), Number(icon:GetHeight()), Inside(icon, button, scale), Inside(icon, list, scale)))
    end
    Add(3, format("row: shown %s, on screen %s, alpha %s (in effect %s); the client's quest mark on it: %s",
        YesNo(frame:IsShown()), YesNo(frame:IsVisible()), Number(frame:GetAlpha()), Number(frame:GetEffectiveAlpha()),
        YesNo(frame.IconQuestTexture and frame.IconQuestTexture:IsShown())))
end

-- For the export: what the list handed over this session and, while the window is open, each
-- slot as it is now with what is on its button. { indent, text } per line.
function LootMixin:GetReportLines()
    local lines = {}
    local function Add(indent, text)
        lines[#lines + 1] = { indent = indent, text = text }
    end

    Add(1, format("Item Rows Built: %d with a link, %d before the client had one", built.withLink, built.withoutLink))
    Add(1, format("Slots The Client Changed (LOOT_SLOT_CHANGED): %d with a link then, %d still without, %d with no row in the list",
        changed.withLink, changed.withoutLink, changed.noRow))

    if not LootFrame:IsShown() then
        Add(1, "Open Now: no")
        return lines
    end

    Add(1, "Open Now:")
    LootFrame.ScrollBox:ForEachFrame(function(frame, elementData)
        local slotIndex = elementData.slotIndex
        local isItem = GetLootSlotType(slotIndex) == Enum.LootSlotType.Item
        local link = GetLootSlotLink(slotIndex)
        local note = rowNotes[frame]
        local history = "holds no item now (money, a currency, or taken)"
        if isItem then
            history = note and format("built %s, changed by the client %d times; the icon's alpha as a fade-in ended: %s",
                note.builtWithLink and "with a link" or "before the client had a link", note.changes,
                note.fadeReadings and table.concat(note.fadeReadings, ", ") or "no fade-in ended with an icon on it") or
                "built before this feature heard of it"
        end
        local drawn
        if frame.Item then
            local _
            _, drawn = CaerdonWardrobe:GetAskedOf(frame.Item)
        end
        Add(2, format("- slot %d: %s; %s; its button: %s", slotIndex, link or "no link", history,
            drawn or "not asked for (nothing on it)"))
        if drawn then
            -- What the client says of a frame is asked for one row at a time: a failure
            -- costs that row's lines and not the section.
            local ok, problem = pcall(AddDrawnFacts, Add, frame)
            if not ok then
                Add(3, "its place on screen could not be read: " .. tostring(problem))
            end
        end
    end)
    return lines
end

-- What this window shows of an item (FeatureMixin.lua, displayRules).
LootMixin.displayRules = {
    bindingStatus = true,
    ownIcon = true,
    otherIcon = "Loot",
    sellableIcon = false,
}

CaerdonWardrobe:RegisterFeature(LootMixin)
