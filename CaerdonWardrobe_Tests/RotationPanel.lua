-- The rotation's panel: the run by buttons instead of typed commands.
--
-- One large button always names the next step and does it: start, open the bags, go to the
-- next stop, put the addons back, save the results. It comes up by itself after every reload
-- that is a step of a run, so nothing has to be remembered between reloads. The small buttons
-- are for the exceptions: check again, pass a stop over, stop the run.

local _, T = ...

local panel
local openAskedAt -- when the button asked the client to open the bags

local COLOR = { pass = "|cff40ff40", fail = "|cffff4040", skipped = "|cffffcc00" }
local GREY = "|cffaaaaaa"

local function Verdict(record)
    return (COLOR[record.verdict] or "") .. tostring(record.verdict) .. "|r"
end

local function StopName(record)
    if record.isAddon and record.version and record.version ~= "" then
        return record.stop .. " " .. record.version
    end
    return record.stop
end

-- Every stop of a run with how it went.
local function AddStops(lines, run, here)
    for index, stop in ipairs(run.stops) do
        local record = run.results[stop]
        local state
        if record then
            state = Verdict(record)
        elseif index == here then
            state = "|cffffffffhere|r"
        else
            state = GREY .. "to come|r"
        end
        lines[#lines + 1] = ("%d. %s: %s"):format(index, record and StopName(record) or stop, state)
    end
end

local function AddRecord(lines, record)
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("%s: %s, %d buttons checked, %d as the addon draws them."):format(StopName(record),
        Verdict(record), record.checked or 0, record.same or 0)
    for index = 1, math.min(#(record.reasons or {}), 4) do
        lines[#lines + 1] = "|cffff8080" .. record.reasons[index] .. "|r"
    end
end

-- The bags are opened the way the B key opens them, which is the one function every bag addon
-- answers to. Only called while no bag button is on screen, so it opens and never closes.
local function OpenBags()
    if InCombatLockdown() then
        T.Print("not in combat.")
        return
    end
    openAskedAt = GetTime()
    ToggleAllBags()
end

-- What the panel shows for a state: the text, the large button's label and action (no action:
-- the button is greyed out), and which of the small buttons are offered.
local function Describe(state)
    local lines = {}
    local view = { lines = lines }
    local kind, run = state.kind, state.run

    if kind == "none" then
        local finished = state.finished
        if finished then
            lines[#lines + 1] = finished.aborted and "The run was stopped. The addons are enabled as before."
                or "The run is finished. The addons are enabled as before."
            lines[#lines + 1] = ""
            AddStops(lines, finished)
            if finished.changeCount then
                lines[#lines + 1] = ""
                lines[#lines + 1] = ("Against the run before it: %s%d things are shown differently|r."):format(
                    finished.changeCount > 0 and "|cffff4040" or "|cff40ff40", finished.changeCount)
            end
            lines[#lines + 1] = ""
            lines[#lines + 1] = GREY .. "The results reach the disk on a reload.|r"
            view.label = "Save the results (reload)"
            view.action = function() T.RequestReload("click") end
        else
            lines[#lines + 1] = "Every installed bag addon in turn, with only that one enabled, and the bag buttons checked at each stop. One reload per stop; the addons are put back at the end."
            lines[#lines + 1] = ""
            lines[#lines + 1] = "Stops: " .. table.concat(state.stops, ", ")
            if state.single and not state.checking then
                AddRecord(lines, state.single)
            end
            view.label = #state.stops > 0 and "Start the rotation" or nil
            view.action = #state.stops > 0 and function() T.RotationCommand("start", "click") end or nil
        end
        if state.checking then
            view.label, view.action = "Checking the bags...", nil
        end
        view.check = not state.checking
        return view
    end

    lines[#lines + 1] = ("Stop %d of %d: |cffffffff%s|r"):format(run.index, #run.stops, tostring(state.stop))
    lines[#lines + 1] = ""
    AddStops(lines, run, run.index)

    if kind == "otherToon" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("This run belongs to %s. The addons enabled for this toon were not touched."):format(run.toon)
        view.label = "Waiting on " .. run.toon
        view.abort = true
    elseif kind == "restoring" then
        view.label = "Putting the addons back..."
    elseif kind == "checking" then
        view.label = "Checking the bags..."
    elseif kind == "open" then
        lines[#lines + 1] = ""
        if state.visible > 0 then
            lines[#lines + 1] = "The bags are open. The check starts in a moment."
            view.label = "Checking in a moment..."
        else
            lines[#lines + 1] = "Open every bag. The check starts by itself."
            -- Asked, and nothing the addon drew came on screen.
            if openAskedAt and GetTime() - openAskedAt > 2.5 then
                lines[#lines + 1] = "|cffffcc00No bag button the addon drew is on screen. Open the bags yourself, or record that with \"Check now\".|r"
            end
            view.label = "Open the bags"
            view.action = OpenBags
        end
        view.check, view.skip, view.abort = true, true, true
    else
        AddRecord(lines, state.record)
        if kind == "next" then
            view.label = ("Next stop: %s (reload)"):format(state.nextStop)
        elseif kind == "restore" then
            view.label = "Put the addons back (reload)"
        else
            view.label = "End the run"
        end
        view.action = function() T.RotationCommand("next", "click") end
        view.check, view.abort = true, true
    end
    return view
end
T.DescribeRotation = Describe

local function Refresh()
    if not panel or not panel:IsShown() then
        return
    end
    local view = Describe(T.GetRotationState())
    panel.text:SetText(table.concat(view.lines, "\n"))
    panel.main:SetText(view.label or "Nothing to do")
    panel.main:SetEnabled(view.action ~= nil)
    panel.main.action = view.action
    panel.check:SetShown(view.check and true or false)
    panel.skip:SetShown(view.skip and true or false)
    panel.abort:SetShown(view.abort and true or false)
end

local function SmallButton(text, column, onClick)
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(112, 22)
    button:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16 + (column - 1) * 118, 14)
    button:SetText(text)
    button:SetScript("OnClick", function()
        onClick()
        Refresh()
    end)
    return button
end

local function CreatePanel()
    panel = CreateFrame("Frame", "CaerdonWardrobeTestsRotation", UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(384, 330)
    -- Away from where bag windows open.
    panel:SetPoint("TOP", UIParent, "TOP", 0, -110)
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    if panel.TitleText then
        panel.TitleText:SetText("Caerdon Wardrobe Tests: bag addon rotation")
    end

    panel.text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    panel.text:SetPoint("TOPLEFT", 18, -36)
    panel.text:SetPoint("RIGHT", -18, 0)
    panel.text:SetJustifyH("LEFT")
    panel.text:SetJustifyV("TOP")

    -- The click behind this button is what lets a step reload the UI.
    panel.main = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.main:SetSize(352, 30)
    panel.main:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 44)
    panel.main:SetScript("OnClick", function(self)
        if self.action then
            self.action()
            Refresh()
        end
    end)

    panel.check = SmallButton("Check now", 1, function() T.RotationCommand("check", "click") end)
    panel.skip = SmallButton("Skip this stop", 2, function() T.RotationCommand("skip", "click") end)
    panel.abort = SmallButton("Stop the run", 3, function() T.RotationCommand("abort", "click") end)

    -- The state moves by itself (the bags open, the check ends), so the panel follows it.
    local sinceRefresh = 0
    panel:SetScript("OnUpdate", function(_, elapsed)
        sinceRefresh = sinceRefresh + elapsed
        if sinceRefresh >= 0.25 then
            sinceRefresh = 0
            Refresh()
        end
    end)
    panel:SetScript("OnShow", Refresh)
    panel:Hide()
    T.rotationPanel = panel
end

function T.ShowRotationPanel()
    if not panel then
        CreatePanel()
    end
    openAskedAt = nil
    panel:Show()
    Refresh()
end

-- After a reload that is a step of a run, the panel is there again with the next step.
T.OnLogin(function()
    if T.db.rotation.run then
        T.ShowRotationPanel()
    end
end)
