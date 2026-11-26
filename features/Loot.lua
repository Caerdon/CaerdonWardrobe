local LootMixin = {}

-- What the loot list has handed over this session, for the export's [Loot Window] section. A
-- row is built once per slot when the window opens, with the slot's link where the client has
-- one by then, and the client says when it has changed a slot (LOOT_SLOT_CHANGED).
local built = { withLink = 0, withoutLink = 0 }
local changed = { withLink = 0, withoutLink = 0, noRow = 0 }
-- [row] = { builtWithLink, changes, events, ... }: how the row that is in the list now came to
-- its button.
local rowNotes = setmetatable({}, { __mode = "k" })
-- Rows whose fade-in is listened to (WatchFadeIn). A row is the list's and is used again.
local fadeWatched = setmetatable({}, { __mode = "k" })
-- Animation groups whose starts and stops are noted while debug is on (WatchAnimation).
local animationWatched = setmetatable({}, { __mode = "k" })

-- One more line of what happened to a row since it was built: when, and what.
local EVENTS_KEPT = 40
local function NoteEvent(note, what)
    if not note then
        return
    end
    note.eventCount = (note.eventCount or 0) + 1
    local events = note.events
    if not events then
        events = {}
        note.events = events
    end
    if #events < EVENTS_KEPT then
        events[#events + 1] = format("%.2f %s", GetTime() - (note.builtAt or GetTime()), what)
    end
end

function LootMixin:GetName()
    return "Loot"
end

-- Whether a fade-in is running (WatchFadeIn).
local function IsFading(fade)
    return (fade and fade.IsPlaying and fade:IsPlaying()) and true or false
end

function LootMixin:Init()
    -- The feature is the callback's owner. The list keeps one callback per owner, so one
    -- registered under the loot window itself is replaced by any addon that names it too.
    ScrollUtil.AddInitializedFrameCallback(LootFrame.ScrollBox, function(_, frame, elementData)
        local earlier = rowNotes[frame]
        if earlier and earlier.sampler then
            earlier.sampler:Cancel()
        end
        rowNotes[frame] = nil
        self:OnRowFilled(frame, elementData, built, "built")
    end, self, false)

    -- The window fades in as it opens, over its rows' own fade.
    local windowFade = LootFrame.ShowAnim
    if windowFade and windowFade.HookScript then
        windowFade:HookScript("OnFinished", function()
            LootFrame.ScrollBox:ForEachFrame(function(frame)
                self:OnFadedIn(frame, frame.ShowAnim)
            end)
        end)
    end

    return { "LOOT_SLOT_CHANGED" }
end

-- A row is drawn when it has faded in, never before.
--
-- The window fills a row with its Init, which plays the row's fade-in (ShowAnim, a tenth of a
-- second), and the window plays one of its own as it opens. What is drawn on a row while a
-- fade runs is not left as it was drawn (WoW Forever 1.60.1.71091): the icon came out with
-- alpha 0 where the draw had set 1, read at the end of each fade, and a star whose bounce was
-- started inside the fade moved far faster than it does anywhere else, with one animation
-- playing at the settings and the pace it was made with. The queue draws a frame after a
-- request, which is inside the fade. So a row that is filled is cleared and waits, and is
-- asked for when its own fade and the window's have both ended.
--
-- Returns whether the row's fade-in is listened to. A row is the list's and is used again.
function LootMixin:WatchFadeIn(frame)
    local fade = frame.ShowAnim
    if not (fade and fade.HookScript) then
        return false
    end
    if not fadeWatched[frame] then
        fadeWatched[frame] = true
        fade:HookScript("OnFinished", function()
            self:OnFadedIn(frame, LootFrame.ShowAnim)
        end)
    end
    return true
end

-- The window has filled a row: as the list builds it, or again for a slot the client changed.
-- `tally`: the count this belongs to.
function LootMixin:OnRowFilled(frame, elementData, tally, why)
    local button = frame.Item
    if not button then
        return
    end
    self:TallyRow(frame, elementData, tally)
    if self:WatchFadeIn(frame) then
        NoteEvent(rowNotes[frame], why .. ", waits for its fade-in")
        self:Decorate(button, nil)
    else
        self:AskForRow(frame, elementData, why)
    end
end

-- A fade-in has ended: the row's own or the window's. `other` is the other of the two; while
-- that one still runs the row goes on waiting, for its end.
function LootMixin:OnFadedIn(frame, other)
    -- A row given back to the list shows no slot.
    local elementData = frame.Item and frame.GetElementData and frame:GetElementData()
    if not elementData then
        return
    end
    if IsFading(other) then
        NoteEvent(rowNotes[frame], "a fade-in ended, the other still runs")
        return
    end
    self:AskForRow(frame, elementData, "asked (faded in)")
end

-- The core has drawn a row's button (ProcessItem calls this for a feature that has it). Kept
-- for the export: an icon that moves too fast may be one that is drawn over and over.
function LootMixin:OnButtonDrawn(button)
    local frame = button:GetParent()
    local note = frame and rowNotes[frame]
    if not note then
        return
    end
    note.draws = (note.draws or 0) + 1
    local overlay = CaerdonWardrobe:GetCaerdonButton(button)
    local group = overlay and overlay.mogAnim
    NoteEvent(note, format("drawn (its animation playing: %s)", group and (group:IsPlaying() and "yes" or "no") or "none"))
    if CaerdonWardrobeConfig.Debug.Enabled then
        self:WatchAnimation(note, button)
    end
end

-- While debug is on: every start and stop of the icon's animation is noted, whoever asks for
-- it, and the animation is read twenty times a second for four seconds after a draw: how far
-- through its loop it is and which of its turns is running. A loop that is started over, or
-- runs faster than it was made, shows there.
local SAMPLE_SECONDS, SAMPLE_COUNT = 0.05, 80
function LootMixin:WatchAnimation(note, button)
    local overlay = CaerdonWardrobe:GetCaerdonButton(button)
    local group = overlay and overlay.mogAnim
    if group and not animationWatched[group] then
        animationWatched[group] = true
        for _, method in ipairs({ "Play", "Stop", "Finish", "Restart", "Pause" }) do
            if group[method] then
                -- Not every object of the client's can be hooked this way; one that cannot
                -- is left unwatched.
                pcall(hooksecurefunc, group, method, function()
                    local row = button:GetParent()
                    NoteEvent(row and rowNotes[row], "animation " .. method)
                end)
            end
        end
    end
    if note.sampler then
        return
    end
    local samples = {}
    note.samples = samples
    note.sampler = C_Timer.NewTicker(SAMPLE_SECONDS, function()
        local current = CaerdonWardrobe:GetCaerdonButton(button)
        local playing = current and current.mogAnim
        if not playing then
            samples[#samples + 1] = "none"
        else
            local turn = "-"
            for index, part in ipairs({ playing:GetAnimations() }) do
                if part:IsPlaying() then
                    turn = (part.IsDelaying and part:IsDelaying()) and (index .. "d") or tostring(index)
                    break
                end
            end
            samples[#samples + 1] = format("%s%.2f/%s", playing:IsPlaying() and "" or "x", playing:GetProgress() or -1, turn)
        end
        if #samples >= SAMPLE_COUNT then
            note.sampler = nil
        end
    end, SAMPLE_COUNT)
end

function LootMixin:GetTooltipData(item, locationInfo)
    return C_TooltipInfo.GetLootItem(locationInfo.elementData.slotIndex)
end

-- Counts a row the window filled, for the export.
function LootMixin:TallyRow(frame, elementData, tally)
    local slotIndex = elementData.slotIndex
    if GetLootSlotType(slotIndex) ~= Enum.LootSlotType.Item then
        return
    end
    local hasLink = GetLootSlotLink(slotIndex) ~= nil
    local key = hasLink and "withLink" or "withoutLink"
    tally[key] = tally[key] + 1
    local note = rowNotes[frame]
    if not note then
        note = { changes = 0, builtAt = GetTime() }
        rowNotes[frame] = note
    end
    if tally == built then
        note.builtWithLink = hasLink
        note.builtOnScreen = frame:IsVisible() and true or false
        note.firstUse = CaerdonWardrobe:GetCaerdonButton(frame.Item) == nil
        note.fadingWhenBuilt = IsFading(frame.ShowAnim)
    else
        note.changes = note.changes + 1
    end
end

-- One row of the list, asked for as its slot is now.
--
-- A slot whose item the client has no data for yet has no link, and its button is cleared.
-- The row is not built again when the data comes: the window fills it in again from
-- LOOT_SLOT_CHANGED.
function LootMixin:AskForRow(frame, elementData, why)
    local button = frame.Item
    if not button then
        return
    end

    local slotIndex = elementData.slotIndex
    local link = GetLootSlotLink(slotIndex)
    NoteEvent(rowNotes[frame], format("%s%s", why or "asked", link and "" or ", no link"))

    self:Decorate(button, link, {
        locationKey = format("%d", slotIndex),
        elementData = elementData
    })
end

-- The client changed what a slot holds, or has its item's data now. The window fills that
-- slot's row in again without building it (so the list's callback does not come), which
-- plays the row's fade-in again.
function LootMixin:LOOT_SLOT_CHANGED(slotIndex)
    local frame = LootFrame.ScrollBox:FindFrameByPredicate(function(row)
        return row:GetSlotIndex() == slotIndex
    end)
    if frame then
        self:OnRowFilled(frame, frame:GetElementData(), changed, "the client changed the slot")
    else
        changed.noRow = changed.noRow + 1
    end
end

function LootMixin:Refresh()
    -- elementData: slotIndex, group (coin = 1 else 0), quality
    LootFrame.ScrollBox:ForEachFrame(function(frame, elementData)
        -- A row that is fading in is asked for when it has.
        if IsFading(frame.ShowAnim) or IsFading(LootFrame.ShowAnim) then
            NoteEvent(rowNotes[frame], "a full refresh, left to its fade-in")
        else
            self:AskForRow(frame, elementData, "asked (a full refresh)")
        end
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

    -- Every animation group the icon has, not only the one the overlay holds: an icon that
    -- moves too fast has more than one playing, or one playing faster than it was made.
    if icon and icon.GetAnimationGroups then
        local groups = { icon:GetAnimationGroups() }
        local held = overlay.mogAnim
        Add(3, format("icon's animations: %d groups; the overlay holds %s (as the waiting spinner: %s)", #groups,
            held and "one" or "none", YesNo(overlay.isWaitingIcon)))
        for index, group in ipairs(groups) do
            local parts = { group:GetAnimations() }
            local degrees = {}
            for partIndex, part in ipairs(parts) do
                degrees[partIndex] = part.GetDegrees and Number(part:GetDegrees()) or part:GetObjectType()
            end
            Add(4, format("%d: %s; playing %s, paused %s, done %s, to finish %s; loops %s (%s), %s s, speed %s; turns %s", index,
                group == held and "the overlay's" or "not the overlay's", YesNo(group:IsPlaying()), YesNo(group:IsPaused()),
                YesNo(group:IsDone()), YesNo(group:IsPendingFinish()), tostring(group:GetLooping()),
                tostring(group:GetLoopState()), Number(group:GetDuration()),
                Number(group.GetAnimationSpeedMultiplier and group:GetAnimationSpeedMultiplier() or 1),
                table.concat(degrees, " / ")))
        end
    end
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
            history = note and format("built %s (%s, %s, its fade-in running then: %s), changed by the client %d times",
                note.builtWithLink and "with a link" or "before the client had a link",
                note.builtOnScreen and "on screen" or "not on screen yet",
                note.firstUse and "its button's first use" or "its button used before",
                note.fadingWhenBuilt and "yes" or "no", note.changes) or
                "built before this feature heard of it"
        end
        local drawn
        if frame.Item then
            local _
            _, drawn = CaerdonWardrobe:GetAskedOf(frame.Item)
        end
        Add(2, format("- slot %d: %s; %s; its button: %s", slotIndex, link or "no link", history,
            drawn or "not asked for (nothing on it)"))
        if note then
            Add(3, format("since it was built %.1f s ago: drawn %d times; %d things noted (seconds after it was built): %s",
                GetTime() - (note.builtAt or GetTime()), note.draws or 0, note.eventCount or 0,
                note.events and table.concat(note.events, "; ") or "none"))
            Add(3, "its animation every " .. SAMPLE_SECONDS .. " s from the first draw (share of its loop / the turn running, d: in its pause, x: not playing): " ..
                (note.samples and table.concat(note.samples, " ") or "not read (turn on Enable debug, then loot again)"))
        end
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
