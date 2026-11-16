-- The core's own counters (CaerdonCounters.lua in the addon), read from here.
--
-- The addon counts from its first line: when each login milestone was reached, what the client
-- was asked to load and what it answered, what caused each full refresh. And, while its
-- profile is on, the calls, time and memory of the functions a draw goes through. The tests
-- store those figures with their own records and switch the profile on for a counted pass.
--
-- The functions are wrapped as soon as this addon loads (Core.lua), before the tests put their
-- own hooks on the same functions, so a hook's time is never part of a figure. The profile
-- itself stays off unless a test or /cwtest counters switches it on.
--
-- Nothing here needs a setting changed by hand. A timing switches the profile and the addon's
-- Enable debug setting to what it needs and puts both back.

local _, T = ...

-- nil when the addon under test has no counters (a version from before them).
function T.ReadCounters()
    local core = CaerdonCounters
    if type(core) ~= "table" or type(core.GetReport) ~= "function" then
        return nil
    end
    return T.Plain(core:GetReport(), 8)
end

-- The always-on part alone, for a login record.
function T.ReadLedger()
    local report = T.ReadCounters()
    if not report then
        return nil
    end
    return {
        secondsSinceLoad = report.secondsSinceLoad,
        milestones = report.milestones,
        itemLoads = report.itemLoads,
        refreshes = report.refreshes,
    }
end

-- Full refreshes by what caused them, as the core has counted them so far.
function T.RefreshTriggers()
    local core = CaerdonCounters
    if type(core) ~= "table" or type(core.GetReport) ~= "function" then
        return nil
    end
    return core:GetReport().refreshes.by
end

-- Pure: what was added between two readings of RefreshTriggers.
function T.DiffTriggers(before, after)
    if not before or not after then
        return nil
    end
    local added = {}
    for trigger, count in pairs(after) do
        local more = count - (before[trigger] or 0)
        if more > 0 then
            added[trigger] = more
        end
    end
    return added
end

------------------------------------------------------------------------------------------
-- What a measurement needs switched
------------------------------------------------------------------------------------------

-- Enable debug makes the addon do more on every draw (it records each button's geometry,
-- adds lines to tooltips), and the profile times every call. A measurement runs without
-- either, whatever they were, and puts them back. What was changed is kept in the saved
-- results, so a reload in the middle of a run still puts it back, at the next load.

local function DebugSetting()
    local config = CaerdonWardrobeConfig
    return type(config) == "table" and type(config.Debug) == "table" and config.Debug or nil
end

-- Returns a function that puts back what this call changed.
function T.MeasureUndisturbed()
    local core = CaerdonCounters
    local hasProfile = type(core) == "table" and type(core.SetProfile) == "function"
    local profileWasOn = hasProfile and core.on == true
    if profileWasOn then
        core:SetProfile(false)
    end
    local debug = DebugSetting()
    if debug and debug.Enabled then
        debug.Enabled = false
        T.db.switches.debugSuspended = true
    end
    return function()
        if profileWasOn then
            core:SetProfile(true)
        end
        T.RestoreSwitches()
    end
end

function T.RestoreSwitches()
    if T.db.switches.debugSuspended then
        T.db.switches.debugSuspended = nil
        local debug = DebugSetting()
        if debug then
            debug.Enabled = true
        end
    end
end

-- Whether Enable debug is on, for a record that cannot be taken without it (a login).
function T.DebugIsOn()
    local debug = DebugSetting()
    return debug ~= nil and debug.Enabled == true
end

-- A profile of the next login: armed by /cwtest counters login, switched on here as the tests
-- load, which is before anything is drawn, and taken off again with the login record.
local profilingLogin = false

T.OnInit(function()
    T.RestoreSwitches() -- left over from a run that a reload cut short
    local core = CaerdonCounters
    if T.db.switches.profileLogin and type(core) == "table" and type(core.SetProfile) == "function" then
        T.db.switches.profileLogin = nil
        core:SetProfile(true)
        core:Reset()
        profilingLogin = true
    end
end)

-- For the login record: the profile of this login when it was asked for, otherwise nil.
function T.TakeLoginProfile()
    if not profilingLogin then
        return nil
    end
    profilingLogin = false
    local core = CaerdonCounters
    local profile = T.Plain(core:GetReport().profile, 8)
    core:SetProfile(false)
    return profile
end

-- Inside a job: `count` more refreshes with the profile on and its figures started from zero,
-- each measured by `measure` like the runs before them. Returns what the core counted, or nil
-- without counters. Counting takes time itself, so these runs are kept apart from the
-- measurement: their addon time is stored only to show how much the counting adds.
function T.CountRefreshes(measure, count)
    local core = CaerdonCounters
    if type(core) ~= "table" or type(core.SetProfile) ~= "function" or not count or count < 1 then
        return nil
    end
    core:SetProfile(true)
    core:Reset()
    local runs = {}
    for index = 1, count do
        runs[index] = measure()
    end
    local report = core:GetReport()
    core:SetProfile(false)
    local counted = { runs = count, profile = T.Plain(report.profile, 8) }
    counted.medianCpuMs = T.Summarize(runs, "cpuMs")
    counted.medianDraws = T.Summarize(runs, "draws")
    counted.medianMemoryKB = T.Summarize(runs, "memoryKB", true)
    return counted
end

------------------------------------------------------------------------------------------
-- /cwtest counters
------------------------------------------------------------------------------------------

local KEEP_REPORTS = 10

-- Prints the core's report and stores it, so it can be read outside the game.
local function StoreReport()
    local core = CaerdonCounters
    local report = T.ReadCounters()
    if not report then
        T.Print("this version of the addon has no counters.")
        return
    end
    local toon, client = T.GetToon(), T.GetClient()
    T.Push(T.db.counters, {
        at = GetServerTime(),
        toon = toon.key,
        flavor = client.flavor,
        build = client.build,
        subjectVersion = C_AddOns.GetAddOnMetadata(T.SUBJECT, "Version"),
        addons = T.NoteAddons(),
        report = report,
    }, KEEP_REPORTS)
    T.Print("the core's counters (stored; a reload writes them to disk):")
    for _, line in ipairs(core:GetReportLines()) do
        print(string.rep("  ", line.indent) .. line.text)
    end
end

function T.CountersCommand(rest)
    local core = CaerdonCounters
    if type(core) ~= "table" or type(core.SetProfile) ~= "function" then
        T.Print("this version of the addon has no counters.")
        return
    end
    if rest == "on" then
        core:SetProfile(true)
        T.Print("the profile is on until /cwtest counters off or a reload.")
    elseif rest == "off" then
        core:SetProfile(false)
        T.Print("the profile is off.")
    elseif rest == "login" then
        T.db.switches.profileLogin = true
        T.Print("the next login or reload is profiled from the moment the tests load; its record holds the result.")
    elseif rest == "reset" then
        core:Reset()
        T.Print("the profile's figures start from zero.")
    else
        StoreReport()
    end
end

------------------------------------------------------------------------------------------
-- Refreshes by trigger, per minute of play
------------------------------------------------------------------------------------------

-- Added to the build's totals beside the event counts (Journal.lua), at the same moment: on
-- logout and on a reload. A refresh the tests forced is in there under the line that forced it.
T.RegisterEvent("PLAYER_LOGOUT", function()
    if not T.db or not T.loginTime then
        return
    end
    local totals = T.db.events[T.GetClient().build]
    local triggers = T.RefreshTriggers()
    if not totals or not triggers then
        return
    end
    totals.triggers = totals.triggers or {}
    for trigger, count in pairs(triggers) do
        totals.triggers[trigger] = (totals.triggers[trigger] or 0) + count
    end
end)
