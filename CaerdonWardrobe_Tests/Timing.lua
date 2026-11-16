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

-- Inside a job: one forced refresh, measured until the queue has drained.
local function MeasureRefresh()
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
    CaerdonWardrobe:RefreshItems()

    local cpu, frames, idleSince, worstFrame = 0, 0, nil, 0
    while true do
        T.Yield()
        frames = frames + 1
        local last = LastFrameMs()
        cpu = cpu + last
        if last > worstFrame then
            worstFrame = last
        end
        local now = GetTime()
        if now - startedAt >= MIN_RUN_SECONDS and T.CoreIsIdle() then
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
    T.timingRun = nil

    local byFeature, events
    for name, entry in pairs(run.byFeature) do
        byFeature = byFeature or {}
        byFeature[name] = { draws = entry.draws, firstMs = Round(entry.first - started, 1), lastMs = Round(entry.last - started, 1) }
    end
    for event, entry in pairs(run.events) do
        events = events or {}
        events[event] = { count = entry.count, firstMs = Round(entry.first - started, 1), items = entry.items }
    end

    return {
        byFeature = byFeature,
        events = events,
        tooltip = tooltip,
        cpuMs = Round(cpu),
        frames = frames,
        worstFrameMs = Round(worstFrame),
        draws = T.counters.processItem - drawsBefore,
        firstDrawMs = run.firstDraw and Round(run.firstDraw - started, 1) or nil,
        lastDrawMs = run.lastDraw and Round(run.lastDraw - started, 1) or nil,
        memoryKB = Round(AddonMemory() - memoryBefore, 1),
        timedOut = run.timedOut,
    }
end

-- label: what is open ("bags", "bank", "vendor", ...). It only names the record; open the
-- windows before running it.
function T.RunRefreshTiming(label, count)
    count = count or T.GetPlan().timing.runs
    T.Start("timing", function()
        if not T.WaitForIdle(0.5, 20) then
            T.Print("the addon's queue did not go idle, so nothing was timed.")
            return
        end
        local record = BaseRecord("refresh", label)
        record.profilerBefore = T.ReadProfiler(T.SUBJECT)
        local refreshBefore = T.counters.refreshItems
        record.runs = {}
        for index = 1, count do
            record.runs[index] = MeasureRefresh()
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
        T.Push(T.db.timing, record, 40)
        T.Print("%s x%d: %s draws per refresh, addon time median %s ms, worst %s ms; last icon after %s ms; memory +%s KB.",
            tostring(label), count, tostring(record.medianDraws or 0), tostring(record.medianCpuMs or "-"),
            tostring(record.worstCpuMs or "-"), tostring(record.medianLastDrawMs or "-"),
            tostring(record.medianMemoryKB or "-"))
        if (record.medianDraws or 0) == 0 then
            T.Print("nothing was drawn: no window the addon decorates was open.")
        elseif record.fewestDraws ~= record.mostDraws then
            T.Print("|cffffcc00the refreshes drew between %d and %d items, so something else was drawing too|r (a window opened, a page changed, an item moved). Run it again with nothing changing.",
                record.fewestDraws, record.mostDraws)
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
        record.profilerBefore = T.ReadProfiler(T.SUBJECT)
        local countsBefore = T.GetSessionCounts()
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
-- queue is empty after entering the world.
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
        T.Push(T.db.logins, record, 20)
        if T.AfterLogin then
            T.AfterLogin()
        end
    end)
end)
