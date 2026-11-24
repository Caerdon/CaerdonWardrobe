-- Rotation: every installed bag addon in turn, one per reload, with one check for all of them.
--
-- A bag addon replaces Blizzard's bag window, so only one can be looked at in a session, and
-- the client switches addons on a reload. A run walks through the stops (Blizzard's own bags,
-- then each installed addon of the plan's list): at a stop that addon alone is enabled for
-- this toon, every other addon stays as it is, and at the end the original set is put back.
-- The client refuses a reload with no click or key press behind it, so each step forward is a
-- command or a button: /cwtest rotation next.
--
-- The check is the same at every stop and knows nothing about the bag addon. For every
-- visible button the addon drew for a bag slot:
--   * it shows what the addon draws for that slot now (the same item drawn on a hidden button
--     under a stand-in for the same feature): which icon, its tint, the text, the level gain;
--   * it was drawn again by a full refresh, which is each feature's Refresh() doing its job;
--   * the picture on the button is the picture of the item in the slot it was drawn for.
-- What each button showed is kept per item, so a run after a change to the addon's code can
-- be compared with the run before it.

local _, T = ...

local BLIZZARD = "Blizzard" -- the stop with every listed addon off: Blizzard's own bags
local KEEP_RUNS = 6
local MAX_PROBLEMS = 25
local MAX_CHANGES = 40
local REFERENCE_TIMEOUT = 30
local FIRST_BAG, LAST_BAG = Enum.BagIndex.Backpack, Enum.BagIndex.ReagentBag

-- What a player sees of a draw that does not depend on the window it is in. Size and position
-- belong to the window, and a hidden 37 px button cannot stand for them.
local CONTENT_FIELDS = { "icon", "iconColor", "desaturated", "badge", "text", "gain" }
-- What is kept per item, to compare one run with the next: here size and position count.
local SHOWN_FIELDS = { "status", "binding", "icon", "iconColor", "iconAlpha", "iconSize", "iconPoint", "desaturated",
    "badge", "text", "gain" }

------------------------------------------------------------------------------------------
-- Planning and judging (no client calls)
------------------------------------------------------------------------------------------

-- Pure: the stops of a run, in order. candidates is the plan's list; installed and enabled
-- are sets of names. The stop the toon plays with comes last, so the run ends where it began
-- and needs no reload to put things back; with two of the listed addons enabled at once no
-- stop is that set, and the run ends with a reload of its own. `only` limits the run to the
-- stops named (any case). Returns the stops and the stop that is the original set, or nil.
function T.PlanRotation(candidates, installed, enabled, only)
    local wanted
    if only and #only > 0 then
        wanted = {}
        for _, name in ipairs(only) do
            wanted[name:lower()] = true
        end
    end
    local original, enabledCount = BLIZZARD, 0
    for _, name in ipairs(candidates) do
        if installed[name] and enabled[name] then
            enabledCount = enabledCount + 1
            original = name
        end
    end
    if enabledCount > 1 then
        original = nil
    end

    local stops = {}
    local function Add(name)
        if not wanted or wanted[name:lower()] then
            stops[#stops + 1] = name
        end
    end
    if original ~= BLIZZARD then
        Add(BLIZZARD)
    end
    for _, name in ipairs(candidates) do
        if installed[name] and name ~= original then
            Add(name)
        end
    end
    if original then
        Add(original)
    end
    return stops, original
end

-- Pure: which of the listed addons are on at a stop: that one alone.
function T.RotationStates(stop, candidates, installed)
    local states = {}
    for _, name in ipairs(candidates) do
        if installed[name] then
            states[name] = (name == stop)
        end
    end
    return states
end

-- Pure: how what a button shows differs from what the addon draws for its slot, as text, or
-- nil when a player would see the same.
function T.CompareDrawn(real, reference)
    local parts = {}
    for _, field in ipairs(CONTENT_FIELDS) do
        if real[field] ~= reference[field] then
            parts[#parts + 1] = ("%s is %s where the addon draws %s"):format(field, tostring(real[field]),
                tostring(reference[field]))
        end
    end
    return #parts > 0 and table.concat(parts, "; ") or nil
end

-- Pure: the verdict of one stop, from its counts.
--   pass     buttons were checked and nothing is wrong
--   fail     see record.reasons
--   skipped  the stop's addon did not load, or the stop was passed over
-- record.notes holds what is worth knowing and is not a failure.
function T.JudgeRotationStop(record)
    local reasons, notes = {}, {}
    if record.loaded == false then
        record.verdict = "skipped"
        record.reasons = { ("%s did not load: %s"):format(record.stop, tostring(record.loadReason or "no reason given")) }
        record.notes = notes
        return record.verdict, record.reasons
    end

    if record.isAddon and #record.integrations == 0 then
        reasons[#reasons + 1] = ("no integration registered for %s: it loaded after the addon, or its own bags are switched off")
            :format(record.stop)
    end
    for _, entry in ipairs(record.integrations) do
        if entry.verdict == "problem" then
            reasons[#reasons + 1] = ("integration %s: %s"):format(entry.feature, tostring(entry.summary))
        elseif entry.verdict == "waiting" then
            notes[#notes + 1] = ("integration %s: %s"):format(entry.feature, tostring(entry.summary))
        end
    end
    if record.checked == 0 then
        reasons[#reasons + 1] = "no visible bag button was drawn by the addon"
        -- Whether the stop's features were asked for anything says where it stops.
        for _, name in ipairs(T.SortedKeys(record.features)) do
            local feature = record.features[name]
            if feature.expected and feature.requests then
                notes[#notes + 1] = ("%s asked for %d draws this session (%d of them for an empty slot) and %d were made")
                    :format(name, feature.requests, feature.emptyRequests or 0, feature.draws or 0)
            end
        end
        if record.forced then
            notes[#notes + 1] = "checked on request while no bag button the addon drew was on screen"
        end
    end
    if (record.sharedSlot or 0) > 0 then
        notes[#notes + 1] = ("%d of the buttons not drawn again share their slot with another button of the same feature: the addon keeps one request per feature and slot")
            :format(record.sharedSlot)
    end
    if record.differ > 0 then
        reasons[#reasons + 1] = ("%d of %d buttons do not show what the addon draws for their slot"):format(record.differ,
            record.checked)
    end
    if record.otherItem > 0 then
        reasons[#reasons + 1] = ("%d buttons carry another item's picture than the slot they were drawn for holds")
            :format(record.otherItem)
    end
    if record.notRedrawn > 0 then
        reasons[#reasons + 1] = ("%d of %d buttons were not drawn again by a full refresh"):format(record.notRedrawn,
            record.checked)
    end

    if record.checked > 0 and (record.picturesRead or 0) == 0 then
        notes[#notes + 1] = "no button's picture could be read, so none was compared with its slot's item: "
            .. tostring(record.pictureSample or "nothing found")
    end
    if record.settled == false then
        notes[#notes + 1] = "the addon's queue did not go idle after the refresh, so buttons may have been read too early"
    end
    if record.unexpected > 0 then
        local names = {}
        for _, name in ipairs(T.SortedKeys(record.features)) do
            local feature = record.features[name]
            if not feature.expected and feature.visible > 0 then
                names[#names + 1] = ("%s %d"):format(name, feature.visible)
            end
        end
        notes[#notes + 1] = "visible bag buttons drawn by a feature that is not this stop's: " .. table.concat(names, ", ")
    end
    if record.elsewhere > 0 then
        notes[#notes + 1] = ("%d buttons say they belong to another slot than the one they were drawn for")
            :format(record.elsewhere)
    end
    if record.noReference > 0 then
        notes[#notes + 1] = ("%d buttons not judged: the addon did not draw their slot on a hidden button in time")
            :format(record.noReference)
    end
    if record.filtered > 0 then
        notes[#notes + 1] = ("%d buttons not judged: dimmed by a bag search"):format(record.filtered)
    end
    if (record.notShownCount or 0) > 0 then
        notes[#notes + 1] = ("%d of %d filled bag slots have no visible button the addon drew (a closed bag, a collapsed group, a merged stack)")
            :format(record.notShownCount, record.slotsFilled or 0)
    end

    record.verdict = #reasons > 0 and "fail" or "pass"
    record.reasons, record.notes = reasons, notes
    return record.verdict, reasons
end

-- Pure: what a later run shows differently from an earlier one, stop by stop, for the items
-- both of them saw: { stop, link, summary }, and a stop whose verdict changed.
function T.DiffRotationRuns(previous, run)
    local changes = {}
    for _, stop in ipairs(run.stops) do
        local before, after = previous.results[stop], run.results[stop]
        if before and after then
            if before.verdict ~= after.verdict then
                changes[#changes + 1] = { stop = stop, summary = ("verdict %s -> %s"):format(tostring(before.verdict),
                    tostring(after.verdict)) }
            end
            if before.shown and after.shown then
                for _, key in ipairs(T.SortedKeys(after.shown)) do
                    local old, new = before.shown[key], after.shown[key]
                    if old then
                        local parts = {}
                        for _, field in ipairs(SHOWN_FIELDS) do
                            if old[field] ~= new[field] then
                                parts[#parts + 1] = ("%s %s -> %s"):format(field, tostring(old[field]), tostring(new[field]))
                            end
                        end
                        if #parts > 0 then
                            changes[#changes + 1] = { stop = stop, link = new.link, summary = table.concat(parts, "; ") }
                        end
                    end
                end
            end
        end
    end
    return changes
end

------------------------------------------------------------------------------------------
-- The buttons the addon drew for bag slots
------------------------------------------------------------------------------------------

-- button -> { bag, slot, feature }: the last draw the addon made on it for a slot of the
-- bags. Weak keys: the buttons belong to whichever addon made them.
local bagButtons = setmetatable({}, { __mode = "k" })

-- Called from the counting hook on ProcessItem (Journal.lua) for every draw, so it stays
-- cheap. The tests' own hidden buttons are left out, and so is another toon's bag.
function T.NoteBagButton(button, featureName, locationInfo)
    if type(button) ~= "table" or type(locationInfo) ~= "table" or locationInfo.isOffline then
        return
    end
    local bag, slot = locationInfo.bag, locationInfo.slot
    if type(bag) ~= "number" or type(slot) ~= "number" or bag < FIRST_BAG or bag > LAST_BAG then
        return
    end
    if featureName:sub(1, 6) == "Tests:" then
        return
    end
    local note = bagButtons[button]
    if not note then
        note = {}
        bagButtons[button] = note
    end
    note.bag, note.slot, note.feature = bag, slot, featureName
end

-- Bag buttons on screen that the last full refresh has not reached: drawn this session for a
-- slot that still holds an item, and not since that refresh. A window that leaves its buttons
-- alone while it is closed owes them a draw when it opens; one left here was never paid.
-- Returns how many were looked at and the ones found.
function T.StaleBagButtons()
    local generation = CaerdonWardrobe:GetRefreshGeneration()
    local checked, stale = 0, {}
    for button, note in pairs(bagButtons) do
        if button:IsVisible() and C_Container.GetContainerItemID(note.bag, note.slot) then
            checked = checked + 1
            if CaerdonWardrobe:GetButtonRefreshGeneration(button) ~= generation then
                stale[#stale + 1] = { feature = note.feature, bag = note.bag, slot = note.slot }
            end
        end
    end
    return checked, stale
end

local function CountVisible()
    local count = 0
    for button in pairs(bagButtons) do
        if button:IsVisible() then
            count = count + 1
        end
    end
    return count
end

-- The file ID of the picture an item button shows, read off the button itself.
-- Returns nil and what was found instead where it cannot be read.
local function OwnIcon(button)
    local found
    for _, key in ipairs({ "icon", "Icon", "IconTexture" }) do
        local region = button[key]
        if type(region) == "table" and type(region.GetTexture) == "function" then
            local texture = region:GetTexture()
            if issecretvalue(texture) then
                found = found or (key .. ":GetTexture() is a secret value")
            elseif type(texture) == "number" then
                return texture
            else
                -- An addon that draws the picture on a frame of its own leaves this one empty.
                found = found or ("%s:GetTexture() is a %s (%s)"):format(key, type(texture), tostring(texture))
            end
        end
    end
    return nil, found or "no icon, Icon or IconTexture texture on the button"
end

-- The slot a button says it is, where it is built on Blizzard's bag item button.
local function OwnSlot(button)
    if type(button.GetSlotAndBagID) ~= "function" then
        return nil
    end
    local ok, slot, bag = pcall(button.GetSlotAndBagID, button)
    if ok and type(slot) == "number" and type(bag) == "number" then
        return bag, slot
    end
    return nil
end

------------------------------------------------------------------------------------------
-- The check at one stop
------------------------------------------------------------------------------------------

local function IsLoaded(name)
    local _, loaded = C_AddOns.IsAddOnLoaded(name)
    return loaded and true or false
end

local function GetReport()
    if not CaerdonIntegrations or not CaerdonIntegrations.GetReport then
        return {}
    end
    return CaerdonIntegrations:GetReport()
end

-- Inside a job. The bags have to be open; returns the stop's record.
local function CheckStop(stop, forced)
    local toon, client = T.GetToon(), T.GetClient()
    local record = {
        stop = stop,
        forced = forced or nil,
        isAddon = stop ~= BLIZZARD,
        at = GetServerTime(),
        toon = toon.key,
        sig = toon.signature,
        flavor = client.flavor,
        build = client.build,
        subjectVersion = C_AddOns.GetAddOnMetadata(T.SUBJECT, "Version"),
        addons = T.NoteAddons(),
        integrations = {},
        features = {},
        problems = {},
        shown = {},
        checked = 0, same = 0, differ = 0, otherItem = 0, notRedrawn = 0,
        elsewhere = 0, unexpected = 0, noReference = 0, filtered = 0,
        picturesRead = 0, slotsNamed = 0, -- how many buttons the last two checks could be made on
    }

    -- Which features are this stop's: the integrations of its addon, or Blizzard's bags.
    local expected = {}
    if record.isAddon then
        record.version = tostring(C_AddOns.GetAddOnMetadata(stop, "Version") or "")
        record.loaded = IsLoaded(stop)
        if not record.loaded then
            local _, reason = C_AddOns.IsAddOnLoadable(stop, UnitGUID("player"))
            record.loadReason = reason
            T.JudgeRotationStop(record)
            return record
        end
        for _, entry in ipairs(GetReport()) do
            if entry.addon == stop then
                expected[entry.feature] = true
                record.integrations[#record.integrations + 1] = { feature = entry.feature, verdict = entry.verdict,
                    summary = entry.summary }
            end
        end
    else
        expected.Bags = true
    end

    -- A full refresh first: afterwards every button a feature still looks after carries the
    -- new generation, and one that does not was left out by that feature's Refresh().
    T.WaitForIdle(0.5, 20)
    CaerdonWardrobe:RefreshItems()
    T.Sleep(0.3)
    record.settled = T.WaitForIdle(1, 30)
    local generation = CaerdonWardrobe:GetRefreshGeneration()

    -- The stop's own features are listed even when they drew nothing: how often each asked
    -- for a draw this session says whether its hooks deliver at all.
    for name in pairs(expected) do
        record.features[name] = { visible = 0, hidden = 0, expected = true }
    end

    -- Read every visible button before anything else is drawn.
    local entries, slotsShown = {}, {}
    local sameSlot = {} -- feature|bag|slot -> how many buttons were last drawn for it, how many of them hidden
    for button, note in pairs(bagButtons) do
        local feature = record.features[note.feature]
        if not feature then
            feature = { visible = 0, hidden = 0, expected = expected[note.feature] and true or false }
            record.features[note.feature] = feature
        end
        local slotKey = ("%s|%d|%d"):format(note.feature, note.bag, note.slot)
        local shared = sameSlot[slotKey]
        if not shared then
            shared = { buttons = 0, hidden = 0 }
            sameSlot[slotKey] = shared
        end
        shared.buttons = shared.buttons + 1
        if not button:IsVisible() then
            shared.hidden = shared.hidden + 1
        end
        if not button:IsVisible() then
            feature.hidden = feature.hidden + 1
        else
            feature.visible = feature.visible + 1
            if not feature.expected then
                record.unexpected = record.unexpected + 1
            end
            slotsShown[note.bag .. "/" .. note.slot] = true
            local info = C_Container.GetContainerItemInfo(note.bag, note.slot)
            if info and info.isFiltered then
                record.filtered = record.filtered + 1
            else
                local entry = {
                    bag = note.bag,
                    slot = note.slot,
                    feature = note.feature,
                    info = info,
                    real = T.ReadDrawn(button),
                    redrawn = CaerdonWardrobe:GetButtonRefreshGeneration(button) == generation,
                }
                entry.ownIcon, entry.noIcon = OwnIcon(button)
                entry.ownBag, entry.ownSlot = OwnSlot(button)
                entries[#entries + 1] = entry
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.bag ~= b.bag then return a.bag < b.bag end
        if a.slot ~= b.slot then return a.slot < b.slot end
        return a.feature < b.feature
    end)
    for name, feature in pairs(record.features) do
        local requests = T.counters.requests[name]
        feature.requests = requests and requests.calls or 0
        feature.emptyRequests = requests and requests.empty or 0
        feature.draws = T.counters.byFeature[name] or 0
    end

    -- What the addon draws for each of those slots now, on hidden buttons, under a stand-in
    -- for the feature that drew the visible one.
    local references, waiting, used = {}, 0, 0
    local cancelled = false
    for _, entry in ipairs(entries) do
        local key = ("%s|%d|%d"):format(entry.feature, entry.bag, entry.slot)
        entry.key = key
        if entry.info and entry.info.hyperlink and references[key] == nil then
            local proxy = T.FeatureProxy(entry.feature)
            if not proxy then
                references[key] = false
            else
                used = used + 1
                local hidden = T.HiddenButton(used)
                local reference = {}
                references[key] = reference
                local item = CaerdonItem:CreateFromBagAndSlot(entry.bag, entry.slot)
                local locationInfo = { bag = entry.bag, slot = entry.slot }
                waiting = waiting + 1
                T.AwaitDraw(hidden, function()
                    waiting = waiting - 1
                    reference.drawn = T.ReadDrawn(hidden)
                    -- The verdict behind the draw; the addon has it cached by now.
                    local _, status, binding = item:GetCaerdonStatus(proxy, locationInfo)
                    reference.status, reference.binding = status, binding
                end)
                local requested = false
                item:ContinueOnItemLoad(function()
                    -- The addon may call back twice (notes: LoadSources).
                    if not requested and not cancelled then
                        requested = true
                        CaerdonWardrobe:UpdateButton(hidden, item, proxy, locationInfo, {})
                    end
                end)
                if used % 25 == 0 then
                    T.Yield()
                end
            end
        end
    end
    T.WaitUntil(function() return waiting == 0 end, REFERENCE_TIMEOUT)
    cancelled = true
    for index = 1, used do
        local hidden = T.HiddenButton(index)
        T.AwaitDraw(hidden, nil)
        CaerdonWardrobe:ClearButton(hidden)
        CaerdonWardrobe:ClearButtonState(hidden)
    end

    local NOTHING = { drawn = {} } -- an empty slot: the addon draws nothing
    for _, entry in ipairs(entries) do
        local info = entry.info
        local hasItem = info and info.hyperlink
        local reference = hasItem and references[entry.key] or NOTHING
        if not reference or not reference.drawn then
            record.noReference = record.noReference + 1
        else
            record.checked = record.checked + 1
            local wrong = {}
            local difference = T.CompareDrawn(entry.real, reference.drawn)
            if difference then
                record.differ = record.differ + 1
                wrong[#wrong + 1] = difference
            end
            if hasItem and not entry.redrawn then
                record.notRedrawn = record.notRedrawn + 1
                local shared = sameSlot[entry.key]
                if shared and shared.buttons > 1 then
                    -- The addon keeps one request per feature and slot, so of two buttons for
                    -- one slot only the one asked for last is drawn.
                    record.sharedSlot = (record.sharedSlot or 0) + 1
                    wrong[#wrong + 1] = ("not drawn again by a full refresh; %d buttons of this feature were last drawn for this slot, %d of them not on screen")
                        :format(shared.buttons, shared.hidden)
                else
                    wrong[#wrong + 1] = "not drawn again by a full refresh"
                end
            end
            if hasItem and not entry.ownIcon and not record.pictureSample then
                record.pictureSample = entry.noIcon
            end
            if hasItem and entry.ownIcon and type(info.iconFileID) == "number" then
                record.picturesRead = record.picturesRead + 1
            end
            if entry.ownBag then
                record.slotsNamed = record.slotsNamed + 1
            end
            if hasItem and entry.ownIcon and type(info.iconFileID) == "number" and entry.ownIcon ~= info.iconFileID then
                record.otherItem = record.otherItem + 1
                wrong[#wrong + 1] = ("the button's picture is %d, the item in its slot has %d"):format(entry.ownIcon,
                    info.iconFileID)
            end
            if entry.ownBag and (entry.ownBag ~= entry.bag or entry.ownSlot ~= entry.slot) then
                record.elsewhere = record.elsewhere + 1
            end
            if #wrong == 0 then
                record.same = record.same + 1
            elseif #record.problems < MAX_PROBLEMS then
                record.problems[#record.problems + 1] = {
                    link = hasItem and info.hyperlink or "(empty slot)",
                    bag = entry.bag,
                    slot = entry.slot,
                    feature = entry.feature,
                    what = table.concat(wrong, "; "),
                }
            end
            if hasItem then
                local itemKey = T.ItemKey(info.hyperlink) .. (info.isBound and "|B" or "")
                if not record.shown[itemKey] then
                    local shown = { link = info.hyperlink, status = reference.status, binding = reference.binding }
                    for field, value in pairs(entry.real) do
                        shown[field] = value
                    end
                    record.shown[itemKey] = shown
                end
            end
        end
    end

    -- Filled slots nobody showed: a closed bag, a collapsed group, a merged stack.
    record.slotsFilled, record.notShownCount, record.notShown = 0, 0, {}
    for bag = FIRST_BAG, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink then
                record.slotsFilled = record.slotsFilled + 1
                if not slotsShown[bag .. "/" .. slot] then
                    record.notShownCount = record.notShownCount + 1
                    if #record.notShown < 10 then
                        record.notShown[#record.notShown + 1] = info.hyperlink
                    end
                end
            end
        end
    end

    T.JudgeRotationStop(record)
    return record
end

local VERDICT_COLOR = { pass = "|cff40ff40", fail = "|cffff4040", skipped = "|cffffcc00" }

local function StopTitle(record)
    if record.isAddon and record.version and record.version ~= "" then
        return record.stop .. " " .. record.version
    end
    return record.stop
end

local function PrintRecord(record)
    print(("  %s%s|r  %s: %d buttons checked, %d as the addon draws them"):format(VERDICT_COLOR[record.verdict] or "",
        tostring(record.verdict), StopTitle(record), record.checked, record.same))
    for _, reason in ipairs(record.reasons or {}) do
        print("      |cffff4040" .. reason .. "|r")
    end
    for index = 1, math.min(#record.problems, 6) do
        local problem = record.problems[index]
        print(("      %s (bag %d slot %d, %s): %s"):format(problem.link, problem.bag, problem.slot, problem.feature,
            problem.what))
    end
    for _, note in ipairs(record.notes or {}) do
        print("      |cffaaaaaa" .. note .. "|r")
    end
end

------------------------------------------------------------------------------------------
-- Enabling and disabling
------------------------------------------------------------------------------------------

-- For this toon only, as the client's own addon list does it in game.
local function IsEnabled(name)
    return C_AddOns.GetAddOnEnableState(name, UnitGUID("player")) > Enum.AddOnEnableState.None
end

local function ReadCandidates()
    local candidates = T.GetPlan().rotation.addons
    local installed, enabled = {}, {}
    for _, name in ipairs(candidates) do
        if C_AddOns.DoesAddOnExist(name) then
            installed[name] = true
            enabled[name] = IsEnabled(name)
        end
    end
    return candidates, installed, enabled
end

-- Every change goes through here, so the run knows what the toon started with (original)
-- and what this session of the UI was loaded with (loaded).
local function SetEnabled(run, name, enabled)
    local now = IsEnabled(name)
    if run.original[name] == nil then
        run.original[name] = now
        run.loaded[name] = now
    end
    if now == enabled then
        return false
    end
    if enabled then
        C_AddOns.EnableAddOn(name, UnitGUID("player"))
    else
        C_AddOns.DisableAddOn(name, UnitGUID("player"))
    end
    return true
end

-- An addon that was off may need others that are off too (a library, a core part).
local function EnableDependencies(run, name, seen)
    if seen[name] then
        return
    end
    seen[name] = true
    for _, dependency in ipairs({ C_AddOns.GetAddOnDependencies(name) }) do
        if C_AddOns.DoesAddOnExist(dependency) then
            SetEnabled(run, dependency, true)
            EnableDependencies(run, dependency, seen)
        end
    end
end

local function ApplyStop(run, stop)
    local candidates, installed = ReadCandidates()
    local states = T.RotationStates(stop, candidates, installed)
    -- What an earlier stop needed besides its own addon goes back to what it was first, so
    -- the last stop is the original set again.
    for name, enabled in pairs(run.original) do
        if states[name] == nil and C_AddOns.DoesAddOnExist(name) then
            SetEnabled(run, name, enabled)
        end
    end
    for name, enabled in pairs(states) do
        SetEnabled(run, name, enabled)
    end
    if stop ~= BLIZZARD then
        EnableDependencies(run, stop, {})
    end
    C_AddOns.SaveAddOns()
end

local function Restore(run)
    for name, enabled in pairs(run.original) do
        if C_AddOns.DoesAddOnExist(name) then
            SetEnabled(run, name, enabled)
        end
    end
    C_AddOns.SaveAddOns()
end

-- Whether the addons this session was loaded with are still the ones enabled: if not, only
-- a reload makes the change real.
local function NeedsReload(run)
    for name, loaded in pairs(run.loaded) do
        if C_AddOns.DoesAddOnExist(name) and IsEnabled(name) ~= loaded then
            return true
        end
    end
    return false
end

local function NoteLoaded(run)
    run.loaded = {}
    for name in pairs(run.original) do
        if C_AddOns.DoesAddOnExist(name) then
            run.loaded[name] = IsEnabled(name)
        end
    end
end

------------------------------------------------------------------------------------------
-- The run
------------------------------------------------------------------------------------------

-- T.db.rotation: run (the one in progress, kept across its reloads), history (finished runs,
-- newest last) and single (the last check made outside a run).
--
-- run.phase is "check" at a stop and "restore" while the reload that puts the original set
-- back is under way. run.original is what each addon the run touched was before it;
-- run.loaded what this session of the UI was loaded with.

local toonKey          -- set at login
local checking = false -- a check is queued or running
local ticker           -- watches for the bags being opened

local function GetRun()
    return T.db.rotation.run
end

local function CurrentStop(run)
    return run.stops[run.index]
end

local function NeedsRestore(run)
    for name, enabled in pairs(run.original) do
        if C_AddOns.DoesAddOnExist(name) and IsEnabled(name) ~= enabled then
            return true
        end
    end
    return false
end

local function Finish(run, aborted)
    local store = T.db.rotation
    run.finishedAt = GetServerTime()
    run.aborted = aborted and true or nil
    run.phase = "done"
    store.run = nil

    local counts = {}
    for _, stop in ipairs(run.stops) do
        local verdict = run.results[stop] and run.results[stop].verdict or "skipped"
        counts[verdict] = (counts[verdict] or 0) + 1
    end

    -- Against the run before it on this toon: the same stops, the same items.
    local previous
    for index = #store.history, 1, -1 do
        local earlier = store.history[index]
        if earlier.toon == run.toon and not earlier.aborted then
            previous = earlier
            break
        end
    end
    if previous and not aborted then
        local changes = T.DiffRotationRuns(previous, run)
        run.comparedWith = { at = previous.finishedAt, subjectVersion = previous.subjectVersion }
        run.changeCount = #changes
        run.changes = {}
        for index = 1, math.min(#changes, MAX_CHANGES) do
            run.changes[index] = changes[index]
        end
    end

    -- A run that was stopped before any stop was checked has nothing to keep.
    if not aborted or next(run.results) ~= nil then
        T.Push(store.history, run, KEEP_RUNS)
    end
    -- What every button showed is kept only where a later run will be compared with it: in
    -- the newest finished run of each toon.
    local newest = {}
    for index = #store.history, 1, -1 do
        local earlier = store.history[index]
        if earlier.aborted or newest[earlier.toon] then
            for _, record in pairs(earlier.results) do
                record.shown = nil
            end
        else
            newest[earlier.toon] = true
        end
    end

    T.Print("rotation %s: %d stops, %d pass, %d fail, %d skipped. The addons are enabled as they were before it.",
        aborted and "stopped" or "finished", #run.stops, counts.pass or 0, counts.fail or 0, counts.skipped or 0)
    if run.changes then
        T.Print("against the run of %s: %s%d things are shown differently|r.", date("%m-%d %H:%M", previous.finishedAt),
            run.changeCount > 0 and "|cffff4040" or "|cff40ff40", run.changeCount)
        for index = 1, math.min(#run.changes, 8) do
            local change = run.changes[index]
            print(("  %s: %s %s"):format(change.stop, change.link or "", change.summary))
        end
    end
    T.Print("the results reach the disk on the next reload or logout.")
    T.rotationFinished = run -- for the panel, this session
    if T.OnTestsFinished then
        T.OnTestsFinished()
    end
end

local function SayNext(run)
    if run.index < #run.stops then
        T.Print("next stop: %s. /cwtest rotation next (or the window's button) enables it and reloads.",
            run.stops[run.index + 1])
    elseif NeedsRestore(run) then
        T.Print("that was the last stop. /cwtest rotation next puts the original addons back and reloads.")
    else
        T.Print("that was the last stop. /cwtest rotation check checks it again, /cwtest rotation next ends the run.")
    end
end

local function AfterCheck(run)
    local record = run.results[CurrentStop(run)]
    -- The last stop is the set the toon plays with: nothing is left to put back.
    if run.index == #run.stops and record.verdict == "pass" and not NeedsRestore(run) then
        Finish(run)
    else
        SayNext(run)
    end
end

-- The stop of a check made outside a run: whichever listed addon is loaded.
local function PresentStop()
    local candidates, installed = ReadCandidates()
    for _, name in ipairs(candidates) do
        if installed[name] and IsLoaded(name) then
            return name
        end
    end
    return BLIZZARD
end

-- forced: asked for with "Check now", not started by bag buttons coming on screen.
local function StartCheck(run, forced)
    if checking then
        return
    end
    checking = true
    T.Start("rotation", function()
        local stop = run and CurrentStop(run) or PresentStop()
        T.Print("rotation: checking the bag buttons under %s...", stop)
        -- Protected, so the flag is put back whatever happens in there.
        local ok, record, stack = T.Protected(CheckStop, stop, forced)
        checking = false
        if not ok then
            T.RecordError("rotation", record, stack)
            return
        end
        if run then
            if GetRun() ~= run or run.phase ~= "check" or CurrentStop(run) ~= stop then
                return -- stopped meanwhile
            end
            run.results[stop] = record
        else
            T.db.rotation.single = record
        end
        PrintRecord(record)
        if run then
            AfterCheck(run)
        end
        if T.OnTestsFinished then
            T.OnTestsFinished()
        end
    end)
end

-- At a stop that has not been checked: start the check once bag buttons are on screen.
local function Watch()
    if ticker then
        return
    end
    local seen = 0
    ticker = C_Timer.NewTicker(1, function()
        local run = GetRun()
        if not run or run.phase ~= "check" or run.toon ~= toonKey or run.results[CurrentStop(run)] then
            ticker:Cancel()
            ticker = nil
            return
        end
        if checking or InCombatLockdown() or T.timingRun or T.IsBusy() then
            seen = 0
            return
        end
        -- Two looks in a row, so a window that is still filling is not read half drawn.
        seen = CountVisible() > 0 and seen + 1 or 0
        if seen >= 2 then
            ticker:Cancel()
            ticker = nil
            StartCheck(run)
        end
    end)
end

-- The stop this session of the UI was loaded for: say what to do next.
local function BeginStop(run)
    local stop = CurrentStop(run)
    run.phase = "check"
    local record = run.results[stop]
    if not record and stop ~= BLIZZARD and not IsLoaded(stop) then
        -- CheckStop returns before its first wait when the addon is not loaded, so it can be
        -- called outside a job here.
        record = CheckStop(stop)
        run.results[stop] = record
    end
    if record then
        T.Print("rotation stop %d of %d:", run.index, #run.stops)
        PrintRecord(record)
        SayNext(run)
        return
    end
    T.Print("rotation stop %d of %d: %s. Open every bag; the check starts by itself (/cwtest rotation check forces it).",
        run.index, #run.stops, stop)
    Watch()
end

local function GoToStop(run, index, how)
    run.index = index
    run.phase = "check"
    run.skipAsked = nil
    ApplyStop(run, run.stops[index])
    if NeedsReload(run) then
        T.Print("rotation: reloading for stop %d of %d, %s...", index, #run.stops, run.stops[index])
        T.RequestReload(how)
    else
        BeginStop(run)
    end
end

local function EndRun(run, how, aborted)
    Restore(run)
    if NeedsReload(run) then
        run.phase = "restore"
        run.aborted = aborted and true or nil
        T.Print("rotation: putting the original addons back and reloading...")
        T.RequestReload(how)
    else
        Finish(run, aborted)
    end
end

local function OtherToon(run)
    T.Print("a rotation is waiting on %s (stop %d of %d). The addons enabled for this toon were not touched.", run.toon,
        run.index, #run.stops)
end

local function Start(names, how)
    local running = GetRun()
    if running then
        if running.toon ~= toonKey then
            OtherToon(running)
        else
            T.Print("a rotation is already running (stop %d of %d). /cwtest rotation next goes on, /cwtest rotation abort stops it.",
                running.index, #running.stops)
        end
        return
    end
    local candidates, installed, enabled = ReadCandidates()
    local stops, original = T.PlanRotation(candidates, installed, enabled, names)
    local known = {}
    for _, stop in ipairs(stops) do
        known[stop:lower()] = true
    end
    for _, name in ipairs(names) do
        if not known[name:lower()] then
            T.Print("%s is not a stop: not installed, or not in the plan's list (Plan.lua, rotation.addons).", name)
            return
        end
    end
    if #stops == 0 then
        T.Print("no stop to visit.")
        return
    end

    local toon, client = T.GetToon(), T.GetClient()
    local run = {
        toon = toon.key,
        sig = toon.signature,
        flavor = client.flavor,
        build = client.build,
        subjectVersion = C_AddOns.GetAddOnMetadata(T.SUBJECT, "Version"),
        startedAt = GetServerTime(),
        stops = stops,
        originalStop = original,
        index = 0,
        phase = "check",
        original = {},
        loaded = {},
        results = {},
    }
    for name in pairs(installed) do
        run.original[name] = enabled[name]
        run.loaded[name] = enabled[name]
    end
    T.db.rotation.run = run
    T.rotationFinished = nil
    T.Print("rotation over these stops: %s. One reload per stop; /cwtest rotation abort puts the addons back at any point.",
        table.concat(stops, ", "))
    if not original then
        T.Print("more than one of the listed addons is enabled, so no stop is the set you play with: the run ends with a reload that puts them back.")
    end
    GoToStop(run, 1, how)
end

-- skip: pass a stop over that has not been checked, without asking first.
local function Next(how, skip)
    local run = GetRun()
    if not run then
        T.Print("no rotation is running. /cwtest rotation start begins one.")
        return
    end
    if run.toon ~= toonKey then
        OtherToon(run)
        return
    end
    if checking then
        T.Print("the check of this stop is still running.")
        return
    end
    local stop = CurrentStop(run)
    if not run.results[stop] then
        if not skip and run.skipAsked ~= run.index then
            run.skipAsked = run.index
            T.Print("%s has not been checked: open every bag, or /cwtest rotation check. /cwtest rotation next once more passes it over.",
                stop)
            return
        end
        run.results[stop] = {
            stop = stop, isAddon = stop ~= BLIZZARD, at = GetServerTime(), verdict = "skipped",
            reasons = { "passed over without a check" }, notes = {}, problems = {}, checked = 0, same = 0,
        }
    end
    if run.index < #run.stops then
        GoToStop(run, run.index + 1, how)
    else
        EndRun(run, how)
    end
end

local function CheckNow()
    if checking then
        T.Print("a check is already running.")
        return
    end
    local run = GetRun()
    if run and run.toon == toonKey and run.phase == "check" then
        StartCheck(run, true)
    else
        StartCheck(nil, true)
    end
end

local function Abort(how)
    local run = GetRun()
    if not run then
        T.Print("no rotation is running.")
        return
    end
    if run.toon ~= toonKey then
        -- The enabled set is kept per toon, so there is nothing to put back from here.
        if not run.forgetAsked then
            run.forgetAsked = true
            OtherToon(run)
            T.Print("log in there and /cwtest rotation abort to put its addons back. Typed here once more, the run is dropped and that toon's addons stay as the run left them.")
            return
        end
        T.db.rotation.run = nil
        T.Print("the rotation of %s was dropped. Its addons were not put back.", run.toon)
        return
    end
    EndRun(run, how, true)
end

local function PrintStatus()
    local run = GetRun()
    if run then
        T.Print("rotation on %s, started %s: stop %d of %d.", run.toon, date("%m-%d %H:%M", run.startedAt), run.index,
            #run.stops)
        for index, stop in ipairs(run.stops) do
            local record = run.results[stop]
            local state = record and ((VERDICT_COLOR[record.verdict] or "") .. tostring(record.verdict) .. "|r")
                or (index == run.index and "here, not checked yet" or "to come")
            print(("  %d. %s: %s"):format(index, stop, state))
        end
        if run.toon ~= toonKey then
            OtherToon(run)
        elseif run.results[CurrentStop(run)] then
            SayNext(run)
        else
            T.Print("open every bag for the check, or /cwtest rotation check.")
        end
        return
    end

    local store = T.db.rotation
    local last = store.history[#store.history]
    if last then
        T.Print("last rotation, %s on %s%s:", date("%m-%d %H:%M", last.finishedAt), last.toon,
            last.aborted and " (stopped early)" or "")
        for _, stop in ipairs(last.stops) do
            if last.results[stop] then
                PrintRecord(last.results[stop])
            end
        end
        if last.changeCount then
            T.Print("against the run before it: %d things shown differently.", last.changeCount)
        end
    end
    local candidates, installed, enabled = ReadCandidates()
    local stops = T.PlanRotation(candidates, installed, enabled)
    local missing = {}
    for _, name in ipairs(candidates) do
        if not installed[name] then
            missing[#missing + 1] = name
        end
    end
    T.Print("/cwtest rotation start would visit, in this order: %s.", table.concat(stops, ", "))
    if #missing > 0 then
        T.Print("not installed, so not visited: %s.", table.concat(missing, ", "))
    end
    T.Print("/cwtest rotation check checks the bag buttons as they are now, without a run.")
end

-- /cwtest rotation [status | start [addon ...] | next | skip | check | abort]; with nothing after
-- it, the panel that does the same with buttons (RotationPanel.lua). how is what stands behind
-- the call ("slash" or "click"): the reload needs one of the two.
function T.RotationCommand(rest, how)
    local command, arguments = (rest or ""):match("^(%S*)%s*(.-)$")
    command = command:lower()
    if command ~= "" and command ~= "status" and InCombatLockdown() then
        T.Print("not in combat.")
        return
    end
    if command == "" then
        T.ShowRotationPanel()
    elseif command == "status" then
        PrintStatus()
    elseif command == "skip" then
        Next(how, true)
    elseif command == "start" then
        local names = {}
        for name in arguments:gmatch("%S+") do
            names[#names + 1] = name
        end
        Start(names, how)
    elseif command == "next" then
        Next(how)
    elseif command == "check" then
        CheckNow()
    elseif command == "abort" then
        Abort(how)
    else
        T.Print("/cwtest rotation [status | start [addon ...] | next | skip | check | abort]")
    end
end

-- Where a run stands, for the panel:
--   none       no run; stops is what a new one would visit, finished the run that ended this
--              session
--   otherToon  a run is waiting on another toon
--   open       at a stop that has not been checked: the bags have to be opened
--   checking   the check is running
--   next       checked; nextStop comes after a reload
--   restore    the last stop is checked and the original addons need a reload to come back
--   last       the last stop is checked and did not pass; nothing is left to put back
--   restoring  the reload that puts the addons back is under way
-- visible is how many bag buttons the addon drew are on screen now.
function T.GetRotationState()
    local run = GetRun()
    local state = { visible = CountVisible() }
    if not run then
        local candidates, installed, enabled = ReadCandidates()
        state.kind = "none"
        state.stops = T.PlanRotation(candidates, installed, enabled)
        state.finished = T.rotationFinished
        state.checking = checking
        state.single = T.db.rotation.single
        return state
    end
    state.run = run
    state.stop = CurrentStop(run)
    state.record = run.results[state.stop]
    if run.toon ~= toonKey then
        state.kind = "otherToon"
    elseif run.phase == "restore" then
        state.kind = "restoring"
    elseif checking then
        state.kind = "checking"
    elseif not state.record then
        state.kind = "open"
    elseif run.index < #run.stops then
        state.kind = "next"
        state.nextStop = run.stops[run.index + 1]
    elseif NeedsRestore(run) then
        state.kind = "restore"
    else
        state.kind = "last"
    end
    return state
end

-- One line for the window, or nil when no run is in progress.
function T.RotationStatusLine()
    local run = T.db.rotation.run
    if not run then
        return nil
    end
    local stop = CurrentStop(run)
    local record = stop and run.results[stop]
    return ("Rotation: stop %d of %d, %s: %s"):format(run.index, #run.stops, tostring(stop),
        record and tostring(record.verdict) or (run.phase == "restore" and "putting the addons back" or "not checked yet"))
end

T.OnLogin(function()
    toonKey = T.GetToon().key
    local run = GetRun()
    if run and run.toon == toonKey then
        NoteLoaded(run)
    end
end)

-- Called once the login record is written (Commands.lua): go on where the reload left off.
function T.ResumeRotation()
    local run = GetRun()
    if not run then
        return
    end
    if run.toon ~= toonKey then
        OtherToon(run)
        return
    end
    if run.phase == "restore" then
        if NeedsRestore(run) then
            T.Print("rotation: the original addons are not all enabled again. /cwtest rotation abort tries once more.")
            return
        end
        Finish(run, run.aborted)
    else
        BeginStop(run)
    end
end
