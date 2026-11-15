-- The test registry and the run loop.
--
-- Two kinds of test:
--   * A contract is a fact about the client (an API answers in a shape, a name is gone, a
--     tooltip line carries a field). It is the same for every toon unless it says otherwise,
--     so a result is kept per build and a contract with a final result is not run again.
--   * A verdict test (Verdicts.lua) checks the addon's answer for an item. It tests the
--     addon's code, which changes without the build changing, so it runs every time.
--
-- Statuses: pass, fail, info (answered, nothing was expected), skip (a precondition is not
-- met here, try again later), manual (needs the author to do something), error (the test
-- itself broke). pass, fail and info are final for a build.

local _, T = ...

T.tests = {}
local byId = {}

local FINAL = { pass = true, fail = true, info = true }

local function Register(kind, def)
    assert(type(def.id) == "string" and def.version, "a test needs an id and a version")
    assert(not byId[def.id], "duplicate test id " .. def.id)
    def.kind = kind
    byId[def.id] = def
    T.tests[#T.tests + 1] = def
    return def
end

-- def: id, version, title, run(context), and optionally
--   flavor      "retail" or "forever": the contract only exists there
--   perToon     the answer depends on the toon: stale when the toon's signature changes
--   accumulate  each run adds to the stored detail (what was seen so far), so it runs once
--               per session and merge(old, new) combines the two
--   auto        false: only run when asked for by id
-- run returns nothing (pass, unless a Check failed), "info", or "skip" / "manual" plus the
-- reason. Bump version when the test changes what it checks.
function T.Contract(def)
    assert(type(def.run) == "function", "a contract needs run")
    return Register("contract", def)
end

function T.RegisterVerdict(def)
    return Register("verdict", def)
end

function T.GetTest(id)
    return byId[id]
end

------------------------------------------------------------------------------------------
-- Contracts
------------------------------------------------------------------------------------------

local Context = {}
Context.__index = Context

-- Something worth reading later, stored with the result.
function Context:Note(key, value)
    self.detail[key] = T.Plain(value)
end

-- A failed check fails the contract; the run goes on, so one run reports every failure.
function Context:Check(condition, message, ...)
    if condition then
        return true
    end
    if select("#", ...) > 0 then
        message = message:format(...)
    end
    self.failures[#self.failures + 1] = message
    return false
end

local function StoredContract(def)
    local results = T.db.contracts[T.GetClient().build]
    return results and results[def.id]
end

-- Writes a contract's result. Also the way in for evidence that arrives outside a run, such
-- as "the UI came back after a reload".
function T.SetResult(id, status, detail, message)
    local def = byId[id]
    local toon = T.GetToon()
    local result = {
        v = def and def.version,
        status = status,
        message = message,
        detail = detail and T.Plain(detail) or nil,
        at = GetServerTime(),
        toon = toon.key,
        sig = toon.signature,
    }
    local build = T.GetClient().build
    T.db.contracts[build] = T.db.contracts[build] or {}
    T.db.contracts[build][id] = result
    return result
end

local function RunContract(def)
    local context = setmetatable({ detail = {}, failures = {} }, Context)
    local started = debugprofilestop()
    -- On an error, status is the message and reason the stack.
    local ok, status, reason = T.Protected(def.run, context)
    local previous = StoredContract(def)

    local detail = context.detail
    if def.accumulate and def.merge and previous and previous.v == def.version and previous.detail then
        detail = def.merge(previous.detail, detail)
    end

    local result
    if not ok then
        result = T.SetResult(def.id, "error", detail, status)
        result.stack = reason
        T.RecordError(def.id, status, reason)
    elseif status == "skip" or status == "manual" then
        -- Evidence that arrived earlier (a reload that worked) outlives a later "still waiting".
        if previous and previous.v == def.version and FINAL[previous.status] then
            return previous
        end
        result = T.SetResult(def.id, status, detail, reason)
    elseif #context.failures > 0 then
        result = T.SetResult(def.id, "fail", detail, context.failures[1])
        result.failures = context.failures
    else
        result = T.SetResult(def.id, status == "info" and "info" or "pass", detail, reason)
    end
    result.ms = math.floor((debugprofilestop() - started) * 10 + 0.5) / 10
    return result
end

-- Whether the test applies to this client, and whether it has to run (again).
function T.TestState(def)
    local client = T.GetClient()
    if def.flavor and def.flavor ~= client.flavor then
        return false, false
    end
    if def.kind == "verdict" then
        return true, true
    end
    local stored = StoredContract(def)
    if not stored or stored.v ~= def.version or not FINAL[stored.status] then
        return true, true
    end
    if def.perToon and stored.sig ~= T.GetToon().signature then
        return true, true
    end
    if def.accumulate and not def.ranThisSession then
        return true, true
    end
    return true, false
end

------------------------------------------------------------------------------------------
-- Running
------------------------------------------------------------------------------------------

local ORDER = { "pass", "info", "fail", "regression", "uncovered", "skip", "manual", "error" }
local COLOR = {
    pass = "|cff40ff40", info = "|cff9999ff", fail = "|cffff4040", regression = "|cffff4040",
    uncovered = "|cffffcc00", skip = "|cffaaaaaa", manual = "|cffffcc00", error = "|cffff4040",
}

function T.ColorStatus(status)
    return (COLOR[status] or "") .. status .. "|r"
end

local function CountsText(counts)
    local parts = {}
    for _, status in ipairs(ORDER) do
        if counts[status] then
            parts[#parts + 1] = ("%d %s"):format(counts[status], T.ColorStatus(status))
        end
    end
    return #parts > 0 and table.concat(parts, ", ") or "nothing to run"
end

-- options.force   run contracts that already have a final result too
-- options.match   only tests whose id contains this text (also runs auto = false tests)
-- options.kind    "contract" or "verdict"
-- options.quiet   say nothing when nothing ran and nothing needs attention
function T.RunTests(options)
    options = options or {}
    T.Start("tests", function()
        local counts, ran = {}, 0
        for _, def in ipairs(T.tests) do
            local applies, stale = T.TestState(def)
            local wanted = (not options.kind or options.kind == def.kind)
                and (not options.match or def.id:find(options.match, 1, true) ~= nil)
                and (def.auto ~= false or options.match ~= nil)
            if applies and wanted and (stale or options.force) then
                local result
                if def.kind == "contract" then
                    result = RunContract(def)
                    def.ranThisSession = true
                else
                    result = T.RunVerdict(def)
                end
                if result then
                    counts[result.status] = (counts[result.status] or 0) + 1
                    ran = ran + 1
                end
                T.Yield()
            end
        end
        T.lastRun = { at = GetServerTime(), counts = counts, ran = ran }
        local attention = counts.fail or counts.regression or counts.error or counts.manual
        if ran > 0 and (not options.quiet or attention) then
            T.Print("%d test%s run: %s. /cwtest status lists what needs a look.", ran, ran == 1 and "" or "s",
                CountsText(counts))
        elseif not options.quiet then
            T.Print("no test had to run. /cwtest run all runs every one again.")
        end
        if T.OnTestsFinished then
            T.OnTestsFinished()
        end
    end)
end

-- Every test with its stored result for this build and toon: { def, status, message, at }.
function T.GetStatusRows()
    local rows = {}
    local toon = T.GetToon()
    for _, def in ipairs(T.tests) do
        local applies = T.TestState(def)
        if applies then
            local row = { def = def }
            if def.kind == "contract" then
                local stored = StoredContract(def)
                if stored and stored.v == def.version then
                    row.status, row.message, row.at = stored.status, stored.message, stored.at
                else
                    row.status = "skip"
                    row.message = def.skipReason and ("skipped by the plan: " .. def.skipReason) or "not run yet"
                end
            else
                row.status, row.message, row.at = T.VerdictStatus(def, toon)
            end
            if row.status then
                rows[#rows + 1] = row
            end
        end
    end
    return rows
end

function T.PrintStatus(showAll)
    local counts, lines = {}, {}
    for _, row in ipairs(T.GetStatusRows()) do
        counts[row.status] = (counts[row.status] or 0) + 1
        if showAll or (row.status ~= "pass" and row.status ~= "info") then
            lines[#lines + 1] = ("  %s  %s%s"):format(T.ColorStatus(row.status), row.def.id,
                row.message and (": " .. row.message) or "")
        end
    end
    local client, toon = T.GetClient(), T.GetToon()
    T.Print("%s %s, %s (%s): %s", client.flavor, client.build, toon.key, toon.signature, CountsText(counts))
    for _, line in ipairs(lines) do
        print(line)
    end
end
