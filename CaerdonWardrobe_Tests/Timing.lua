-- Timing scenarios: what the addon costs, in the figures the client itself reports.
--
-- Three kinds of record:
--   * login    written by itself after every login and reload, once the queue has drained;
--   * refresh  the addon's full refresh, forced a number of times with whatever windows are
--              open (bags, bank, vendor: the label says which);
--   * idle     standing still for a while.
--
-- The addon's time comes from the client's addon profiler (C_AddOnProfiler), the same source
-- as the figures in the addon list, by adding up its "last frame" value every frame. Whether
-- that value is what its name says is the "profiler.metrics" contract's question. Memory is
-- the client's per-addon figure; a garbage collection during a run makes it too low, and a
-- negative value is left out of the median.

local _, T = ...

local LAST_TIME = Enum.AddOnProfilerMetric.LastTime

local function Median(values)
    if #values == 0 then
        return nil
    end
    local sorted = {}
    for index, value in ipairs(values) do sorted[index] = value end
    table.sort(sorted)
    local middle = math.floor((#sorted + 1) / 2)
    if #sorted % 2 == 1 then
        return sorted[middle]
    end
    return (sorted[middle] + sorted[middle + 1]) / 2
end
T.Median = Median

local function Round(value, places)
    if value == nil then
        return nil
    end
    local factor = 10 ^ (places or 2)
    return math.floor(value * factor + 0.5) / factor
end

-- Pure: median and worst of one field over the runs. Negative values are dropped when asked.
function T.Summarize(runs, field, dropNegative)
    local values, worst = {}, nil
    for _, run in ipairs(runs) do
        local value = run[field]
        if value ~= nil and not (dropNegative and value < 0) then
            values[#values + 1] = value
            if not worst or value > worst then
                worst = value
            end
        end
    end
    return Round(Median(values)), Round(worst), #values
end

local function AddonMemory()
    UpdateAddOnMemoryUsage()
    return GetAddOnMemoryUsage(T.SUBJECT)
end

local function LastFrameMs()
    return C_AddOnProfiler.GetAddOnMetric(T.SUBJECT, LAST_TIME)
end

local function BaseRecord(kind, label)
    local toon, client = T.GetToon(), T.GetClient()
    return {
        kind = kind,
        label = label,
        at = GetServerTime(),
        toon = toon.key,
        sig = toon.signature,
        flavor = client.flavor,
        build = client.build,
        subjectVersion = C_AddOns.GetAddOnMetadata(T.SUBJECT, "Version"),
        addons = T.NoteAddons(),
        profilerOn = C_AddOnProfiler.IsEnabled(),
        open = { merchant = T.IsOpen("merchant"), bank = T.IsOpen("bank"), mail = T.IsOpen("mail") },
        framerate = Round(GetFramerate(), 1),
    }
end

------------------------------------------------------------------------------------------
-- Forced refresh
------------------------------------------------------------------------------------------

local RUN_TIMEOUT = 30
local MIN_RUN_SECONDS = 0.25 -- the addon's refresh starts its redraw 0.1 s after the call
local SETTLE_SECONDS = 0.3

-- What the game tooltip is showing for, or nil when it is hidden.
local function TooltipOwner()
    if not (GameTooltip and GameTooltip:IsShown()) then
        return nil
    end
    local owner = GameTooltip:GetOwner()
    local name = owner and owner.GetName and owner:GetName()
    return type(name) == "string" and name or "(unnamed)"
end

-- One window's part of a refresh that is being timed.
local function RunFeature(run, name)
    local entry = run.byFeature[name]
    if not entry then
        entry = { draws = 0, requests = 0, empty = 0, unseen = 0 }
        run.byFeature[name] = entry
    end
    return entry
end

-- A request for a button while a refresh is timed (the hook on UpdateButton, Journal.lua).
-- Requests against draws say whether a window asks more often than it is drawn.
function T.NoteTimedRequest(name, isEmpty)
    local run = T.timingRun
    if not run then
        return
    end
    run.firstRequest = run.firstRequest or T.Milliseconds()
    local entry = RunFeature(run, name)
    entry.requests = entry.requests + 1
    if isEmpty then
        entry.empty = entry.empty + 1
    end
end

-- A draw while a refresh is timed (the hook on ProcessItem). Which window drew, and when: two
-- refreshes that drew a different number of items differ in one of these. A draw on a button
-- nobody can see is counted too: a host addon that parks a window under a hidden parent
-- leaves it shown, and its feature goes on drawing it.
function T.NoteTimedDraw(name, button)
    local run = T.timingRun
    if not run then
        return
    end
    local now = T.Milliseconds()
    run.firstDraw = run.firstDraw or now
    run.lastDraw = now
    local entry = RunFeature(run, name)
    entry.draws = entry.draws + 1
    entry.first = entry.first or now
    entry.last = now
    if type(button) == "table" and type(button.IsVisible) == "function" then
        -- Nothing waits in here, so a pcall is safe: a forbidden frame raises on any call.
        local ok, visible = pcall(button.IsVisible, button)
        if ok and not visible then
            entry.unseen = entry.unseen + 1
        end
    end
end

-- Inside a job: the frames of a run that has started, until the queue has been idle for a
-- while and at least minSeconds are over. cpu: addon time already counted for the run.
-- Returns the addon's time, the frames and the longest one.
local function FollowRun(run, startedAt, minSeconds, cpu)
    local frames, idleSince, worstFrame = 0, nil, 0
    while true do
        T.Yield()
        frames = frames + 1
        local last = LastFrameMs()
        cpu = cpu + last
        if last > worstFrame then
            worstFrame = last
        end
        local now = GetTime()
        if now - startedAt >= minSeconds and T.CoreIsIdle() then
            idleSince = idleSince or now
            if now - idleSince >= SETTLE_SECONDS then
                break
            end
        else
            idleSince = nil
        end
        if now - startedAt > RUN_TIMEOUT then
            run.timedOut = true
            break
        end
    end
    return cpu, frames, worstFrame
end

-- What a run noted per window and per event, as plain data with times from `started`.
local function PlainRun(run, started)
    local byFeature, events
    for name, entry in pairs(run.byFeature) do
        byFeature = byFeature or {}
        byFeature[name] = {
            draws = entry.draws,
            requests = entry.requests,
            empty = entry.empty > 0 and entry.empty or nil,
            unseen = entry.unseen > 0 and entry.unseen or nil,
            -- A window can ask without being drawn (every request for an empty slot).
            firstMs = entry.first and Round(entry.first - started, 1) or nil,
            lastMs = entry.last and Round(entry.last - started, 1) or nil,
        }
    end
    for event, entry in pairs(run.events) do
        events = events or {}
        events[event] = { count = entry.count, firstMs = Round(entry.first - started, 1), items = entry.items }
    end
    -- The refreshes that came during the run (Journal.lua), the run's own first.
    local refreshes
    for index, entry in ipairs(run.refreshes or {}) do
        refreshes = refreshes or {}
        refreshes[index] = { ms = Round(entry.at - started, 1), who = entry.who, detail = entry.detail, about = entry.about }
    end
    -- The draws that had waited for data, by what they waited for (Journal.lua).
    local waits
    for why, entry in pairs(run.waits or {}) do
        waits = waits or {}
        waits[why] = { count = entry.count, longestMs = Round(entry.longest * 1000, 1) }
    end
    return byFeature, events, refreshes, waits
end

-- The draws of a run that had waited for data, in words: "2 for the Catalyst's answer".
local function Waits(run)
    local parts = {}
    for why, entry in pairs(run.waits or {}) do
        parts[#parts + 1] = ("%s for %s"):format(tostring(entry.count), tostring(why))
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ", ") or nil
end

-- The refreshes of a run that were not its own, in words: "quest log (objective ...) after 165.3 ms".
local function OtherRefreshes(run)
    local parts = {}
    for index, entry in ipairs(run.refreshes or {}) do
        if index > 1 then
            parts[#parts + 1] = ("%s%s after %s ms"):format(tostring(entry.who),
                entry.detail and (" (" .. tostring(entry.detail) .. ")") or "", tostring(entry.ms))
        end
    end
    return #parts > 0 and table.concat(parts, "; ") or nil
end

-- Inside a job: one forced refresh, measured until the queue has drained. changed: what the
-- refresh says it is about ("worn", "collection"), as the core's own callers do; nil for a
-- refresh about everything.
local function MeasureRefresh(changed)
    local memoryBefore = AddonMemory()
    -- Start on a fresh frame. The memory reading takes a while and the client's timers may
    -- count from the start of the frame they are set in; measured in the same frame, the
    -- first draw came before the refresh's own 0.1 s delay could have been over.
    T.Yield()
    local drawsBefore = T.counters.processItem
    local run = { byFeature = {}, events = {} }
    -- A tooltip on screen is refreshed by the client and announces it with an event some
    -- windows redraw on, so a resting mouse can change the run.
    local tooltip = TooltipOwner()
    T.timingRun = run
    local started = T.Milliseconds()
    local startedAt = GetTime()
    CaerdonWardrobe:RefreshItems(nil, nil, changed)

    local cpu, frames, worstFrame = FollowRun(run, startedAt, MIN_RUN_SECONDS, 0)
    T.timingRun = nil
    local byFeature, events, refreshes, waits = PlainRun(run, started)

    return {
        byFeature = byFeature,
        events = events,
        refreshes = refreshes,
        waits = waits,
        tooltip = tooltip,
        cpuMs = Round(cpu),
        frames = frames,
        -- With the frames, the frame rate of this run: the queue works by the frame, so a
        -- run at 30 frames a second (a client in the background) has later icons.
        seconds = Round(GetTime() - startedAt, 2),
        worstFrameMs = Round(worstFrame),
        draws = T.counters.processItem - drawsBefore,
        firstDrawMs = run.firstDraw and Round(run.firstDraw - started, 1) or nil,
        lastDrawMs = run.lastDraw and Round(run.lastDraw - started, 1) or nil,
        memoryKB = Round(AddonMemory() - memoryBefore, 1),
        timedOut = run.timedOut,
    }
end

-- label: what is open ("bags", "bank", "vendor", ...). It only names the record; open the
-- windows before running it. changed: what each refresh says it is about, for the cost of a
-- refresh that keeps what does not follow from that; the same windows timed with and without
-- it are the comparison.
function T.RunRefreshTiming(label, count, changed)
    count = count or T.GetPlan().timing.runs
    local function Measure()
        return MeasureRefresh(changed)
    end
    T.Start("timing", function()
        if not T.WaitForIdle(0.5, 20) then
            T.Print("the addon's queue did not go idle, so nothing was timed.")
            return
        end
        local record = BaseRecord("refresh", label)
        record.changed = changed
        -- Without the core's profile and without Enable debug, whatever they are set to.
        local restore = T.MeasureUndisturbed()
        -- The first refresh that says what changed still finds empty whatever the refresh
        -- before it emptied, and fills it. One run that is not measured, so that every
        -- measured one starts from what such a refresh keeps.
        if changed then
            MeasureRefresh(changed)
        end
        record.profilerBefore = T.ReadProfiler(T.SUBJECT)
        local refreshBefore = T.counters.refreshItems
        record.runs = {}
        for index = 1, count do
            record.runs[index] = Measure()
        end
        record.profilerAfter = T.ReadProfiler(T.SUBJECT)
        -- More than one call per run means something else refreshed the addon meanwhile.
        record.refreshItemsCalls = T.counters.refreshItems - refreshBefore
        record.medianCpuMs, record.worstCpuMs = T.Summarize(record.runs, "cpuMs")
        -- The longest single frame of a refresh is what a player feels.
        record.medianWorstFrameMs, record.worstFrameMs = T.Summarize(record.runs, "worstFrameMs")
        record.medianLastDrawMs, record.worstLastDrawMs = T.Summarize(record.runs, "lastDrawMs")
        record.medianFirstDrawMs = T.Summarize(record.runs, "firstDrawMs")
        record.medianDraws = T.Summarize(record.runs, "draws")
        -- The same windows give the same number of draws every time. A run that drew more or
        -- fewer had something else going on, and the record is not a clean measurement.
        record.fewestDraws, record.mostDraws = record.runs[1].draws, record.runs[1].draws
        for _, run in ipairs(record.runs) do
            record.fewestDraws = math.min(record.fewestDraws, run.draws)
            record.mostDraws = math.max(record.mostDraws, run.draws)
        end
        record.medianMemoryKB, record.worstMemoryKB, record.memoryRunsUsed = T.Summarize(record.runs, "memoryKB", true)
        -- The same refresh a few more times with the core's counters on: where the time and
        -- the memory go. Not part of the figures above.
        record.counted = T.CountRefreshes(Measure, T.GetPlan().timing.countedRuns)
        restore()
        T.Push(T.db.timing, record, 40)
        T.Print("%s x%d: %s draws per refresh, addon time median %s ms, worst %s ms; last icon after %s ms; memory +%s KB.",
            changed and (tostring(label) .. ", refreshes about " .. changed) or tostring(label), count, tostring(record.medianDraws or 0), tostring(record.medianCpuMs or "-"),
            tostring(record.worstCpuMs or "-"), tostring(record.medianLastDrawMs or "-"),
            tostring(record.medianMemoryKB or "-"))
        if (record.medianDraws or 0) == 0 then
            T.Print("nothing was drawn: no window the addon decorates was open.")
        elseif record.fewestDraws ~= record.mostDraws then
            -- A refresh that drew another number of items than most says why where the addon
            -- knows: it was asked to refresh again (by whom), or items waited for data and
            -- were asked for again when it came. Both are the addon's own doing and the
            -- medians stand; only a refresh with neither had something else drawing.
            local explained, unexplained = {}, 0
            for index, run in ipairs(record.runs) do
                if run.draws ~= record.medianDraws then
                    local others, waited = OtherRefreshes(run), Waits(run)
                    if others or waited then
                        explained[#explained + 1] = ("refresh %d drew %s: %s%s%s"):format(index, tostring(run.draws),
                            others and ("asked to refresh again by " .. others) or "",
                            others and waited and "; " or "",
                            waited and ("items that waited for data and were drawn when it came: " .. waited) or "")
                    else
                        unexplained = unexplained + 1
                    end
                end
            end
            if #explained > 0 then
                T.Print("the refreshes drew between %d and %d items, by the addon's own doing: %s. The medians stand; the worst figures are that refresh's.",
                    record.fewestDraws, record.mostDraws, table.concat(explained, "; "))
            end
            if unexplained > 0 then
                T.Print("|cffffcc00%d of the refreshes drew another number of items with no cause the addon knows, so something else was drawing too|r (a window opened, a page changed, an item moved). Run it again with nothing changing.",
                    unexplained)
            end
        end
        if T.OnTestsFinished then
            T.OnTestsFinished()
        end
    end)
end

------------------------------------------------------------------------------------------
-- A window opened after a refresh it was closed for
------------------------------------------------------------------------------------------

local OPEN_WAIT_SECONDS = 30

-- A window that leaves its buttons alone while it is not on screen owes them a draw when it
-- opens (BetterBags' bags). Two figures come of that: what a refresh still costs with the
-- window closed, and what the opening costs, from the first request it makes to the last
-- icon. The job refreshes once with everything closed, then waits for the window to be
-- opened by hand. Afterwards every bag button on screen must carry the refresh's generation.
function T.RunOpenTiming(label)
    T.Start("timing", function()
        if not T.WaitForIdle(0.5, 20) then
            T.Print("the addon's queue did not go idle, so nothing was timed.")
            return
        end
        local record = BaseRecord("open", label)
        local restore = T.MeasureUndisturbed()

        local closed = MeasureRefresh()
        record.closed = closed
        T.Print("a refresh with the windows as they are: %d draws, addon time %s ms. |cffffcc00Open the bags now|r (within %d seconds).",
            closed.draws, tostring(closed.cpuMs), OPEN_WAIT_SECONDS)

        local memoryBefore = AddonMemory()
        T.Yield()
        local drawsBefore = T.counters.processItem
        local run = { byFeature = {}, events = {} }
        T.timingRun = run
        local waitingSince = GetTime()
        while not run.firstRequest and GetTime() - waitingSince < OPEN_WAIT_SECONDS do
            T.Yield()
        end
        if not run.firstRequest then
            T.timingRun = nil
            restore()
            record.nothingAsked = true
            T.Push(T.db.timing, record, 40)
            T.Print("nothing was asked for in %d seconds: no window opened, or the one that did owed nothing and asked for nothing.",
                OPEN_WAIT_SECONDS)
            if T.OnTestsFinished then
                T.OnTestsFinished()
            end
            return
        end

        -- The requests were made in this frame or the one before, depending on whether the
        -- window's code or this job ran first: the frame before this one is counted, which is
        -- either theirs or an idle one.
        local started, startedAt = run.firstRequest, GetTime()
        local cpu, frames, worstFrame = FollowRun(run, startedAt, 0, LastFrameMs())
        T.timingRun = nil
        record.byFeature = PlainRun(run, started)
        record.cpuMs = Round(cpu)
        record.frames = frames
        record.seconds = Round(GetTime() - startedAt, 2)
        record.worstFrameMs = Round(worstFrame)
        record.draws = T.counters.processItem - drawsBefore
        record.firstDrawMs = run.firstDraw and Round(run.firstDraw - started, 1) or nil
        record.lastDrawMs = run.lastDraw and Round(run.lastDraw - started, 1) or nil
        -- Whatever else the addon allocated while the job waited for the window is in it.
        record.memoryKB = Round(AddonMemory() - memoryBefore, 1)
        record.timedOut = run.timedOut
        if T.StaleBagButtons then
            local checked, stale = T.StaleBagButtons()
            record.bagButtonsOnScreen = checked
            record.staleCount = #stale
            -- Enough to find them; a bag that was not redrawn at all would be hundreds.
            for index = #stale, 13, -1 do
                stale[index] = nil
            end
            record.stale = stale
        end
        restore()
        T.Push(T.db.timing, record, 40)
        T.Print("%s, opened: %d draws, addon time %s ms, first icon after %s ms, last after %s ms, longest frame %s ms.",
            tostring(label), record.draws, tostring(record.cpuMs), tostring(record.firstDrawMs or "-"),
            tostring(record.lastDrawMs or "-"), tostring(record.worstFrameMs))
        if record.staleCount and record.staleCount > 0 then
            T.Print("|cffff4040%d of %d bag buttons on screen were not drawn since the refresh|r: their icons are the old ones.",
                record.staleCount, record.bagButtonsOnScreen)
        elseif record.staleCount then
            T.Print("all %d bag buttons on screen were drawn since the refresh.", record.bagButtonsOnScreen)
        end
        if T.OnTestsFinished then
            T.OnTestsFinished()
        end
    end)
end

------------------------------------------------------------------------------------------
-- Idle
------------------------------------------------------------------------------------------

function T.RunIdleTiming(seconds)
    seconds = seconds or T.GetPlan().timing.idleSeconds
    T.Start("timing", function()
        T.Print("idle for %d seconds: stand still, windows closed.", seconds)
        local record = BaseRecord("idle", "idle")
        local restore = T.MeasureUndisturbed()
        record.profilerBefore = T.ReadProfiler(T.SUBJECT)
        local countsBefore = T.GetSessionCounts()
        local triggersBefore = T.RefreshTriggers()
        local drawsBefore = T.counters.processItem
        local memoryBefore = AddonMemory()
        local cpu, frames, worstFrame = 0, 0, 0
        local startedAt = GetTime()
        while GetTime() - startedAt < seconds do
            T.Yield()
            frames = frames + 1
            local last = LastFrameMs()
            cpu = cpu + last
            if last > worstFrame then
                worstFrame = last
            end
        end
        local elapsed = GetTime() - startedAt
        record.seconds = Round(elapsed, 1)
        record.frames = frames
        record.cpuMs = Round(cpu)
        record.cpuMsPerSecond = Round(cpu / elapsed, 3)
        record.worstFrameMs = Round(worstFrame, 3)
        record.draws = T.counters.processItem - drawsBefore
        record.memoryKB = Round(AddonMemory() - memoryBefore, 1)
        record.profilerAfter = T.ReadProfiler(T.SUBJECT)
        record.counts = {}
        for name, count in pairs(T.GetSessionCounts()) do
            record.counts[name] = count - (countsBefore[name] or 0)
        end
        record.refreshItemsPerMinute = Round(record.counts.RefreshItems / (elapsed / 60), 2)
        -- What caused each full refresh, as the core names it.
        record.refreshTriggers = T.DiffTriggers(triggersBefore, T.RefreshTriggers())
        restore()
        T.Push(T.db.timing, record, 40)
        T.Print("idle %d s: addon time %s ms (%s ms per second), %d full refreshes, %d draws.", record.seconds,
            tostring(record.cpuMs), tostring(record.cpuMsPerSecond), record.counts.RefreshItems, record.draws)
        if T.OnTestsFinished then
            T.OnTestsFinished()
        end
    end)
end

------------------------------------------------------------------------------------------
-- Login
------------------------------------------------------------------------------------------

-- The tests load after the addon, so the addon's first line is out of reach from here: this
-- records what can be seen from outside, from this addon's own load to the first time the
-- queue is empty after entering the world. What the addon counted itself from its first line
-- on is stored with it (`core`: milestones, loads asked of the client, refreshes by trigger).
local loginRecorded = false

T.RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
    if loginRecorded or not (isInitialLogin or isReloadingUi) then
        return
    end
    loginRecorded = true
    local enteredAt = GetTime()
    T.Start("login", function()
        local drained = T.WaitForIdle(2, 90)
        local record = BaseRecord("login", isReloadingUi and "reload" or "login")
        record.secondsFromLoadToWorld = Round(enteredAt - (T.loadedAt or enteredAt), 2)
        record.secondsFromWorldToIdle = Round(GetTime() - enteredAt - 2, 2)
        record.drained = drained
        record.draws = T.counters.processItem
        record.refreshItemsCalls = T.counters.refreshItems
        record.memoryKB = Round(AddonMemory(), 1)
        record.profiler = T.ReadProfiler(T.SUBJECT)
        -- Items the client refused so far, whoever asked. `first` counts from the tests' load,
        -- as secondsFromLoadToWorld does.
        record.refusedItems = T.RefusedItems(30)
        record.core = T.ReadLedger()
        -- A login cannot be taken again without the setting, so the record says how it was.
        record.debugOn = T.DebugIsOn() or nil
        record.profile = T.TakeLoginProfile()
        T.Push(T.db.logins, record, 20)
        if T.AfterLogin then
            T.AfterLogin()
        end
    end)
end)
