-- Counters: what the addon costs and how often it does its work. They are read by the Debug
-- Frame export ([Counters]) and by the test addon; nothing a player sees depends on them.
--
-- Two parts:
--   * The ledger is always on: when each login milestone was reached, every item, quest or
--     spell the client was asked to load with the answer and who asked, and every full refresh
--     with what caused it. It is written at the few places those things happen.
--   * The profile runs only while it is switched on (SetProfile; the test addon does that):
--     calls, time and memory of the functions a draw goes through, the wait in the queue, and
--     each drain of the queue. Nothing is wrapped until it is first switched on, so until then
--     it costs nothing; after that a wrapped function costs one extra call while it is off.
--     It has a switch of its own and does not follow Enable debug: that setting adds work to
--     every draw, and a profile taken with it would describe an addon nobody plays.
--
-- This is the first file the addon loads, so "seconds since load" starts here.

local ADDON_NAME = ...

CaerdonCounters = {}
local Counters = CaerdonCounters

local now = GetTimePreciseSec
local loadedAt = now()

local function SinceLoad()
    return now() - loadedAt
end

local function Round(value, places)
    local factor = 10 ^ (places or 3)
    return math.floor(value * factor + 0.5) / factor
end

------------------------------------------------------------------------------------------
-- Who is calling
------------------------------------------------------------------------------------------

-- "features/Bags.lua" and "95" for a stack line of this addon; the folder is put in front for
-- the test addon's files. nil for a line of the client or of another addon.
local function AddonFrame(line)
    local folder, file, lineNumber = line:match("AddOns[/\\](CaerdonWardrobe[^/\\]*)[/\\]([^%]:]+%.lua)%]?:(%d+)")
    if not folder then
        return nil
    end
    file = file:gsub("\\", "/")
    if folder ~= ADDON_NAME then
        file = folder .. "/" .. file
    end
    return file, lineNumber
end

-- Files that pass a request on and never begin one.
local PLUMBING = {
    ["CaerdonCounters.lua"] = true,
    ["CaerdonAsyncCallbackSystem.lua"] = true,
}

-- The addon's code on the stack above `level`, as file and line: the nearest caller, or with
-- `outermost` the one furthest out, which is where the work began. nil when the stack holds
-- none of the addon's own code (a timer of the client, another addon's call).
local function Caller(level, outermost)
    local stack = debugstack(level + 1, 20, 0)
    if type(stack) ~= "string" then
        return nil
    end
    local foundFile, foundLine
    for line in stack:gmatch("[^\n]+") do
        local file, lineNumber = AddonFrame(line)
        if file and not PLUMBING[file] then
            foundFile, foundLine = file, lineNumber
            if not outermost then
                break
            end
        end
    end
    return foundFile, foundLine
end

------------------------------------------------------------------------------------------
-- Ledger: login milestones
------------------------------------------------------------------------------------------

-- name -> seconds since load, the first time each was reached. The core reads this table to
-- skip the call once a milestone is in.
local milestones = {}
local milestoneOrder = {}
Counters.milestones = milestones

function Counters:Milestone(name)
    if milestones[name] == nil then
        milestones[name] = SinceLoad()
        milestoneOrder[#milestoneOrder + 1] = name
    end
end

-- Before the toon is in the world the client may not be able to answer for an item, and
-- before the bags have reported once the bag windows have nothing to ask about.
local function PhaseAt(seconds)
    if not milestones.enteringWorld or seconds < milestones.enteringWorld then
        return "before the world"
    elseif not milestones.bagUpdate or seconds < milestones.bagUpdate then
        return "before the bags"
    end
    return "in play"
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON_NAME then
            self:UnregisterEvent(event)
            Counters:Milestone("addonLoaded")
        end
    elseif event == "PLAYER_LOGIN" then
        Counters:Milestone("playerLogin")
    elseif event == "PLAYER_ENTERING_WORLD" then
        Counters:Milestone("enteringWorld")
    elseif event == "BAG_UPDATE_DELAYED" then
        self:UnregisterEvent(event)
        Counters:Milestone("bagUpdate")
    end
end)

------------------------------------------------------------------------------------------
-- Ledger: what the client was asked to load
------------------------------------------------------------------------------------------

local LOAD_KINDS = {
    ITEM_DATA_LOAD_RESULT = "item",
    QUEST_DATA_LOAD_RESULT = "quest",
    SPELL_DATA_LOAD_RESULT = "spell",
}
local MAX_FAILURES = 100

local loads = { asked = 0, waiting = 0, loaded = 0, failed = 0, slowest = 0, answerSeconds = 0 }
local loadsBy = {}      -- who asked -> { asked, loaded, failed }
local openLoads = {}    -- "item:123" -> the request the client has not answered yet
local failures = {}     -- list, one entry per kind and ID
local failureIndex = {} -- "item:123" -> its entry in the list

-- Set by the queue while it hands a feature's items to the client, and while the callbacks of
-- an answer run (what they ask for next belongs to whoever asked for the first).
Counters.requester = nil

-- From the listener, before it asks the client. `first` is false when the ID is already being
-- waited for: one more caller, no new question.
function Counters:NoteLoadAsked(event, id, first)
    loads.waiting = loads.waiting + 1
    if not first then
        return
    end
    local kind = LOAD_KINDS[event] or tostring(event)
    local by, where = self.requester, nil
    if not by then
        local file, lineNumber = Caller(2, true)
        if file then
            by, where = file, file .. ":" .. lineNumber
        else
            by = "(not the addon's own code)"
        end
    end
    loads.asked = loads.asked + 1
    local entry = loadsBy[by]
    if not entry then
        entry = { asked = 0, loaded = 0, failed = 0 }
        loadsBy[by] = entry
    end
    entry.asked = entry.asked + 1
    openLoads[kind .. ":" .. tostring(id)] = { kind = kind, id = id, by = by, where = where, at = SinceLoad() }
end

-- From the listener, when the client's answer arrives and before the callbacks run. Returns
-- who had asked, which the listener sets as the requester for the callbacks.
function Counters:NoteLoadAnswered(event, id, success)
    local kind = LOAD_KINDS[event] or tostring(event)
    local key = kind .. ":" .. tostring(id)
    local request = openLoads[key]
    if not request then
        return nil
    end
    openLoads[key] = nil
    local after = SinceLoad() - request.at
    local entry = loadsBy[request.by]
    if success then
        loads.loaded = loads.loaded + 1
        entry.loaded = entry.loaded + 1
        loads.answerSeconds = loads.answerSeconds + after
        if after > loads.slowest then
            loads.slowest = after
        end
    else
        loads.failed = loads.failed + 1
        entry.failed = entry.failed + 1
        local failure = failureIndex[key]
        if failure then
            failure.times = failure.times + 1
            failure.lastAt = Round(request.at, 2)
        elseif #failures < MAX_FAILURES then
            failure = {
                kind = kind,
                id = id,
                by = request.by,
                where = request.where,
                at = Round(request.at, 2),
                after = Round(after, 3),
                phase = PhaseAt(request.at),
                times = 1,
            }
            failures[#failures + 1] = failure
            failureIndex[key] = failure
        end
    end
    return request.by
end

------------------------------------------------------------------------------------------
-- Ledger: full refreshes and what caused them
------------------------------------------------------------------------------------------

local RECENT_REFRESHES = 30

local refreshes = { total = 0 }
local refreshesBy = {}   -- trigger -> count
local recentRefreshes = {}

-- The event the addon's frame is handling, set by its OnEvent. A refresh asked for from inside
-- a handler is that event's; any other one is named by the line that asked.
Counters.event = nil

-- From RefreshItems, on every call.
function Counters:NoteRefresh()
    local trigger = self.event
    if not trigger then
        -- Above this function sits RefreshItems itself, then whoever called it.
        local file, lineNumber = Caller(3, false)
        trigger = file and (file .. ":" .. lineNumber) or "(not the addon's own code)"
    end
    refreshes.total = refreshes.total + 1
    refreshesBy[trigger] = (refreshesBy[trigger] or 0) + 1
    recentRefreshes[#recentRefreshes + 1] = { at = Round(SinceLoad(), 2), trigger = trigger }
    if #recentRefreshes > RECENT_REFRESHES then
        table.remove(recentRefreshes, 1)
    end
end

------------------------------------------------------------------------------------------
-- Profile: the functions a draw goes through
------------------------------------------------------------------------------------------

local profiling = false -- the wrappers' own copy of Counters.on
local attached = false
local profileSince = nil -- seconds since load when the figures below last started from zero
local missing = {}       -- probes whose function was not there to wrap

Counters.on = false

local counters = {}      -- label -> counter
local counterOrder = {}

local function NewCounter(label)
    local counter = { label = label, calls = 0, seconds = 0, own = 0, worst = 0, kb = 0, ownKB = 0, collected = 0 }
    counters[label] = counter
    counterOrder[#counterOrder + 1] = label
    return counter
end

local function ZeroCounter(counter)
    counter.calls, counter.seconds, counter.own, counter.worst = 0, 0, 0, 0
    counter.kb, counter.ownKB, counter.collected = 0, 0, 0
end

-- One entry per wrapped call that has not returned yet: what its own callees took, so that a
-- function's own time and memory can be told from what it spent in the wrapped ones below it.
-- An error that unwinds through a wrapper leaves its entry behind; the queue resets the depth
-- before each of its passes.
local depth = 0
local calleeSeconds, calleeKB, outcomes = {}, {}, {}

local function Leave(counter, startedAt, startedKB, ...)
    local seconds = now() - startedAt
    local kb = collectgarbage("count") - startedKB
    local level = depth
    if level < 1 then
        -- The depth was reset while this call ran: nothing to file it under.
        depth = 0
        return ...
    end
    depth = level - 1

    local outcome = outcomes[level]
    if outcome then
        outcomes[level] = nil
        counter = counter.byOutcome and counter.byOutcome[outcome] or counter
    end

    counter.calls = counter.calls + 1
    counter.seconds = counter.seconds + seconds
    counter.own = counter.own + (seconds - calleeSeconds[level])
    if seconds > counter.worst then
        counter.worst = seconds
    end
    if kb < 0 then
        -- The collector ran inside the call: this sample says nothing about what it allocated.
        counter.collected = counter.collected + 1
        kb = 0
    else
        counter.kb = counter.kb + kb
        local ownKB = kb - calleeKB[level]
        if ownKB > 0 then
            counter.ownKB = counter.ownKB + ownKB
        end
    end
    if level > 1 then
        calleeSeconds[level - 1] = calleeSeconds[level - 1] + seconds
        calleeKB[level - 1] = calleeKB[level - 1] + kb
    end
    return ...
end

local function Enter()
    depth = depth + 1
    calleeSeconds[depth], calleeKB[depth] = 0, 0
    return now(), collectgarbage("count")
end

-- Says how the wrapped call that is running ended, for a function counted per outcome
-- (GetCaerdonStatus: answered from the cache, tooltip not ready, no link). Called from inside
-- that function, with no wrapped call of its own still running.
function Counters:Mark(outcome)
    if depth > 0 then
        outcomes[depth] = outcome
    end
end

-- The queue caught an error in a draw: the wrapped calls it unwound through left their
-- entries behind, and the next draw of the same pass starts from none again. A mark such a
-- call had set goes too, or the next call at its depth would be filed under it.
function Counters:Unwound()
    depth = 0
    wipe(outcomes)
end

local function Wrap(owner, key, counter)
    local original = owner[key]
    owner[key] = function(...)
        if not profiling then
            return original(...)
        end
        local startedAt, startedKB = Enter()
        return Leave(counter, startedAt, startedKB, original(...))
    end
end

-- The wait in the queue: from the first time a button is asked for until it is drawn.
local queuedAt = setmetatable({}, { __mode = "k" })
local queueWait = { count = 0, seconds = 0, worst = 0 }

local function LeaveUpdateButton(counter, core, button, startedAt, startedKB, ...)
    if button then
        -- Still queued after the call: the wait runs from the first request that is not yet
        -- drawn. Not queued: the call cleared the button, or drew nothing.
        if core.waitingToProcess and core.waitingToProcess[button] then
            queuedAt[button] = queuedAt[button] or now()
        else
            queuedAt[button] = nil
        end
    end
    return Leave(counter, startedAt, startedKB, ...)
end

local function WrapUpdateButton(owner, key, counter)
    local original = owner[key]
    owner[key] = function(core, button, ...)
        if not profiling then
            return original(core, button, ...)
        end
        local startedAt, startedKB = Enter()
        return LeaveUpdateButton(counter, core, button, startedAt, startedKB, original(core, button, ...))
    end
end

local function WrapProcessItem(owner, key, counter)
    local original = owner[key]
    owner[key] = function(core, button, ...)
        if not profiling then
            return original(core, button, ...)
        end
        local startedAt, startedKB = Enter()
        local asked = button and queuedAt[button]
        if asked then
            queuedAt[button] = nil
            local waited = startedAt - asked
            queueWait.count = queueWait.count + 1
            queueWait.seconds = queueWait.seconds + waited
            if waited > queueWait.worst then
                queueWait.worst = waited
            end
        end
        return Leave(counter, startedAt, startedKB, original(core, button, ...))
    end
end

local function WrapClearButton(owner, key, counter)
    local original = owner[key]
    owner[key] = function(core, button, ...)
        if not profiling then
            return original(core, button, ...)
        end
        if button then
            queuedAt[button] = nil
        end
        local startedAt, startedKB = Enter()
        return Leave(counter, startedAt, startedKB, original(core, button, ...))
    end
end

local function Probe(ownerName, owner, key, wrap, outcomeNames)
    local label = key
    if type(owner) ~= "table" or type(owner[key]) ~= "function" then
        missing[#missing + 1] = ownerName .. "." .. key
        return
    end
    local counter = counters[label] or NewCounter(label)
    if outcomeNames then
        counter.byOutcome = {}
        counter.label = label .. " (computed)"
        for _, outcome in ipairs(outcomeNames) do
            local split = NewCounter(label .. "." .. outcome)
            split.label = ("%s (%s)"):format(label, outcome)
            counter.byOutcome[outcome] = split
        end
    end
    local install = wrap or Wrap
    install(owner, key, counter)
end

-- Wraps the functions, once. Items and item data copy their methods when they are created, so
-- only those created afterwards are counted. The test addon calls this as it loads, before it
-- hooks the same functions, which keeps its hooks' time out of the figures and reaches every
-- item made from then on.
function Counters:Attach()
    if attached then
        return
    end
    attached = true

    local core = CaerdonWardrobe
    Probe("CaerdonWardrobe", core, "UpdateButton", WrapUpdateButton)
    Probe("CaerdonWardrobe", core, "ClearButton", WrapClearButton)
    Probe("CaerdonWardrobe", core, "ProcessItem", WrapProcessItem)
    Probe("CaerdonItemMixin", CaerdonItemMixin, "GetCaerdonStatus", nil, { "cache hit", "tooltip not ready", "no link" })
    Probe("CaerdonItemMixin", CaerdonItemMixin, "GetTooltipData")
    Probe("CaerdonItemMixin", CaerdonItemMixin, "GetBindingStatus")
    Probe("CaerdonItemMixin", CaerdonItemMixin, "GetCopyStatus")
    Probe("CaerdonEquipmentMixin", CaerdonEquipmentMixin, "GetTransmogInfo")
    Probe("CaerdonEquipmentMixin", CaerdonEquipmentMixin, "GetEquipmentSets")
    Probe("CaerdonWardrobe", core, "SetItemButtonStatus")
    Probe("CaerdonWardrobe", core, "SetItemButtonBindType")

    -- Each feature holds its own copy of the display rules, made when it registered.
    local features = type(core) == "table" and core.GetRegisteredFeatures and core:GetRegisteredFeatures()
    local wrappedAny = false
    for _, feature in pairs(features or {}) do
        if type(feature.GetDisplayInfoInternal) == "function" then
            Wrap(feature, "GetDisplayInfoInternal", counters.GetDisplayInfoInternal or NewCounter("GetDisplayInfoInternal"))
            wrappedAny = true
        end
    end
    if not wrappedAny then
        missing[#missing + 1] = "feature.GetDisplayInfoInternal"
    end
end

------------------------------------------------------------------------------------------
-- Profile: drains of the queue
------------------------------------------------------------------------------------------

-- A drain is one run of the queue's coroutine, from its first pass to the pass that finds
-- nothing left. Time and memory are taken around each pass, so the frames in between, which
-- belong to the rest of the client, are not in them.
local RECENT_DRAINS = 10

local drains = { count = 0, passes = 0, seconds = 0, worstPass = 0, kb = 0, collected = 0 }
local recentDrains = {}
local drain, passStartedAt, passStartedKB

function Counters:BeginPass()
    depth = 0
    if not drain then
        local draws = counters.ProcessItem
        drain = { at = SinceLoad(), passes = 0, seconds = 0, worstPass = 0, kb = 0, collected = 0,
            drawsBefore = draws and draws.calls or 0 }
    end
    passStartedAt, passStartedKB = now(), collectgarbage("count")
end

function Counters:EndPass(finished)
    if not drain or not passStartedAt then
        return
    end
    local seconds = now() - passStartedAt
    local kb = collectgarbage("count") - passStartedKB
    passStartedAt = nil
    drain.passes = drain.passes + 1
    drain.seconds = drain.seconds + seconds
    if seconds > drain.worstPass then
        drain.worstPass = seconds
    end
    if kb < 0 then
        drain.collected = drain.collected + 1
    else
        drain.kb = drain.kb + kb
    end
    if not finished then
        return
    end

    local draws = counters.ProcessItem
    local done = {
        at = Round(drain.at, 2),
        seconds = Round(SinceLoad() - drain.at, 3),
        passes = drain.passes,
        ms = Round(drain.seconds * 1000),
        worstPassMs = Round(drain.worstPass * 1000),
        kb = Round(drain.kb, 1),
        collected = drain.collected,
        draws = (draws and draws.calls or 0) - drain.drawsBefore,
    }
    drains.count = drains.count + 1
    drains.passes = drains.passes + drain.passes
    drains.seconds = drains.seconds + drain.seconds
    drains.kb = drains.kb + drain.kb
    drains.collected = drains.collected + drain.collected
    if drain.worstPass > drains.worstPass then
        drains.worstPass = drain.worstPass
    end
    recentDrains[#recentDrains + 1] = done
    if #recentDrains > RECENT_DRAINS then
        table.remove(recentDrains, 1)
    end
    drain = nil
end

------------------------------------------------------------------------------------------
-- Switching the profile
------------------------------------------------------------------------------------------

-- Starts the profile's figures from zero. The ledger is left alone.
function Counters:Reset()
    for _, counter in pairs(counters) do
        ZeroCounter(counter)
    end
    queueWait.count, queueWait.seconds, queueWait.worst = 0, 0, 0
    drains.count, drains.passes, drains.seconds, drains.worstPass, drains.kb, drains.collected = 0, 0, 0, 0, 0, 0
    wipe(recentDrains)
    wipe(queuedAt)
    drain, passStartedAt = nil, nil
    profileSince = SinceLoad()
end

-- The profile's switch. Off, the figures stay as they are.
function Counters:SetProfile(on)
    local want = on and true or false
    if want == profiling then
        return
    end
    if want then
        self:Attach()
        wipe(queuedAt)
        depth = 0
        if not profileSince then
            profileSince = SinceLoad()
        end
    else
        drain, passStartedAt = nil, nil
    end
    profiling = want
    self.on = want
end

------------------------------------------------------------------------------------------
-- Reading
------------------------------------------------------------------------------------------

local function ReadCounter(counter)
    return {
        label = counter.label,
        calls = counter.calls,
        ms = Round(counter.seconds * 1000),
        ownMs = Round(counter.own * 1000),
        worstMs = Round(counter.worst * 1000),
        kb = Round(counter.kb, 1),
        ownKB = Round(counter.ownKB, 1),
        collected = counter.collected,
    }
end

-- Everything as plain data: numbers, strings, booleans and tables of them.
--   ledger:  milestones (list of { name, seconds }), itemLoads, refreshes
--   profile: on, attached, since, functions (list, in the order a draw reaches them),
--            queueWait, drains
-- Times of the profile are in milliseconds, memory in KB, everything of the ledger in seconds
-- since the addon's first line.
function Counters:GetReport()
    local report = { secondsSinceLoad = Round(SinceLoad(), 2) }

    report.milestones = {}
    for index, name in ipairs(milestoneOrder) do
        report.milestones[index] = { name = name, seconds = Round(milestones[name], 3) }
    end

    local itemLoads = {
        asked = loads.asked,
        callers = loads.waiting,
        loaded = loads.loaded,
        failed = loads.failed,
        slowestSeconds = Round(loads.slowest, 3),
        meanSeconds = loads.loaded > 0 and Round(loads.answerSeconds / loads.loaded, 3) or nil,
        by = {},
        failures = {},
        unanswered = {},
    }
    for by, entry in pairs(loadsBy) do
        itemLoads.by[by] = { asked = entry.asked, loaded = entry.loaded, failed = entry.failed }
    end
    for index, failure in ipairs(failures) do
        local copy = {}
        for key, value in pairs(failure) do
            copy[key] = value
        end
        itemLoads.failures[index] = copy
    end
    local sinceLoad = SinceLoad()
    for _, request in pairs(openLoads) do
        itemLoads.unanswered[#itemLoads.unanswered + 1] = {
            kind = request.kind,
            id = request.id,
            by = request.by,
            where = request.where,
            at = Round(request.at, 2),
            waiting = Round(sinceLoad - request.at, 1),
            phase = PhaseAt(request.at),
        }
    end
    table.sort(itemLoads.unanswered, function(a, b) return a.at < b.at end)
    report.itemLoads = itemLoads

    report.refreshes = { total = refreshes.total, by = {}, recent = {} }
    for trigger, count in pairs(refreshesBy) do
        report.refreshes.by[trigger] = count
    end
    for index, entry in ipairs(recentRefreshes) do
        report.refreshes.recent[index] = { at = entry.at, trigger = entry.trigger }
    end

    local profile = {
        on = profiling,
        attached = attached,
        since = profileSince and Round(profileSince, 2) or nil,
        functions = {},
        missing = {},
    }
    for _, label in ipairs(counterOrder) do
        profile.functions[#profile.functions + 1] = ReadCounter(counters[label])
    end
    for index, name in ipairs(missing) do
        profile.missing[index] = name
    end
    profile.queueWait = {
        count = queueWait.count,
        meanMs = queueWait.count > 0 and Round(queueWait.seconds / queueWait.count * 1000) or nil,
        worstMs = Round(queueWait.worst * 1000),
    }
    profile.drains = {
        count = drains.count,
        passes = drains.passes,
        ms = Round(drains.seconds * 1000),
        worstPassMs = Round(drains.worstPass * 1000),
        kb = Round(drains.kb, 1),
        collected = drains.collected,
        recent = {},
    }
    for index, done in ipairs(recentDrains) do
        local copy = {}
        for key, value in pairs(done) do
            copy[key] = value
        end
        profile.drains.recent[index] = copy
    end
    report.profile = profile

    return report
end

local function SortedByCount(map, field)
    local keys = {}
    for key in pairs(map) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        local countA = field and map[a][field] or map[a]
        local countB = field and map[b][field] or map[b]
        if countA ~= countB then
            return countA > countB
        end
        return a < b
    end)
    return keys
end

local function Figure(value, places)
    if value == nil then
        return "-"
    end
    return (("%." .. (places or 1) .. "f"):format(value))
end

-- The report as { indent, text } lines for the Debug Frame export.
function Counters:GetReportLines()
    local report = self:GetReport()
    local lines = {}
    local function add(indent, text)
        lines[#lines + 1] = { indent = indent, text = text }
    end

    local parts = {}
    for _, milestone in ipairs(report.milestones) do
        parts[#parts + 1] = ("%s %s"):format(milestone.name, Figure(milestone.seconds, 2))
    end
    add(1, ("Seconds since the addon's first line: %s"):format(Figure(report.secondsSinceLoad)))
    add(1, "Milestones (s): " .. (#parts > 0 and table.concat(parts, ", ") or "none yet"))

    local refreshReport = report.refreshes
    parts = {}
    for _, trigger in ipairs(SortedByCount(refreshReport.by)) do
        parts[#parts + 1] = ("%s %d"):format(trigger, refreshReport.by[trigger])
    end
    add(1, ("Full refreshes: %d%s"):format(refreshReport.total,
        #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""))

    local itemLoads = report.itemLoads
    add(1, ("Loads asked of the client: %d (%d loaded, %d failed, %d not answered), mean answer %s s, slowest %s s")
        :format(itemLoads.asked, itemLoads.loaded, itemLoads.failed, #itemLoads.unanswered,
            Figure(itemLoads.meanSeconds, 3), Figure(itemLoads.slowestSeconds, 3)))
    for _, by in ipairs(SortedByCount(itemLoads.by, "asked")) do
        local entry = itemLoads.by[by]
        add(2, ("asked by %s: %d, failed %d"):format(by, entry.asked, entry.failed))
    end
    for _, failure in ipairs(itemLoads.failures) do
        add(2, ("failed: %s %s x%d, first asked at %s s (%s) by %s, answered after %s s"):format(failure.kind,
            tostring(failure.id), failure.times, Figure(failure.at, 2), failure.phase,
            tostring(failure.where or failure.by), Figure(failure.after, 3)))
    end
    for index, request in ipairs(itemLoads.unanswered) do
        if index > 20 then
            add(2, ("... and %d more not answered"):format(#itemLoads.unanswered - 20))
            break
        end
        add(2, ("not answered: %s %s, asked at %s s (%s) by %s, %s s ago"):format(request.kind, tostring(request.id),
            Figure(request.at, 2), request.phase, tostring(request.where or request.by), Figure(request.waiting)))
    end

    local profile = report.profile
    if not profile.attached then
        add(1, "Profile: not run this session")
        return lines
    end
    add(1, ("Profile: %s, figures since %s s"):format(profile.on and "on" or "off", Figure(profile.since)))
    add(2, "per function: calls, ms in all (own: without the listed functions it calls), ms per call, worst call, KB allocated (own)")
    for _, entry in ipairs(profile.functions) do
        if entry.calls > 0 then
            add(2, ("%s: %d calls, %s ms (own %s), %s each, worst %s, %s KB (own %s)%s"):format(entry.label,
                entry.calls, Figure(entry.ms), Figure(entry.ownMs), Figure(entry.ms / entry.calls, 3),
                Figure(entry.worstMs, 2), Figure(entry.kb, 0), Figure(entry.ownKB, 0),
                entry.collected > 0 and (", collector ran in %d"):format(entry.collected) or ""))
        end
    end
    for _, name in ipairs(profile.missing) do
        add(2, "not found, so not counted: " .. name)
    end
    local wait = profile.queueWait
    add(2, ("Wait in the queue: %d draws, mean %s ms, longest %s ms"):format(wait.count, Figure(wait.meanMs),
        Figure(wait.worstMs)))
    local drainReport = profile.drains
    add(2, ("Drains of the queue: %d, %d passes, %s ms, longest pass %s ms, %s KB"):format(drainReport.count,
        drainReport.passes, Figure(drainReport.ms), Figure(drainReport.worstPassMs, 2), Figure(drainReport.kb, 0)))
    for _, done in ipairs(drainReport.recent) do
        add(3, ("at %s s: %d draws in %s s, %d passes, %s ms, longest pass %s ms, %s KB%s"):format(Figure(done.at),
            done.draws, Figure(done.seconds, 2), done.passes, Figure(done.ms), Figure(done.worstPassMs, 2),
            Figure(done.kb, 0), done.collected > 0 and (", collector ran in %d passes"):format(done.collected) or ""))
    end
    return lines
end
