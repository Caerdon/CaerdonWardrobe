-- Verdict tests: the addon's status for an item, on the kind of toon the test names.
--
-- A test targets a shape: the few raw facts that define the case ("valid source, no use
-- error, neither collect verdict true, look not known"), with a pool of items behind it.
-- Every run stores the facts next to the verdict, which is what tells the outcomes apart:
--   * verdict changed, facts unchanged: a regression;
--   * an item no longer fits the shape: drift (the toon learned it, levelled, trained).
--     The item is retired, not failed, the record says which fact moved, and the next item
--     of the pool that fits takes its place.
-- The expected status is written by hand and confirmed in game once. It must never be
-- worked out by the logic it tests.

local _, T = ...

-- def: id, version, title, facts ("appearance", "toy", "mount" or nil), shape, pool, and
--   kinds  a list of { name, toon = { class, race, faction, minLevel, maxLevel },
--          expect = { status, notStatus, binding }, pool (optional, instead of the test's) }
--   confirmed  where and when the expectation was seen in game, or false
--   flavor     "retail" or "forever"
-- expect.status is the one status the item must have. expect.notStatus is a list of statuses
-- it must not have, for a shape whose rule is "nothing to learn": what such an item shows
-- instead (collected, sellable, an upgrade, an auction price) is other rules' business.
function T.Verdict(def)
    assert(type(def.shape) == "table" and type(def.kinds) == "table", "a verdict test needs a shape and kinds")
    for _, kind in ipairs(def.kinds) do
        assert(type(kind.expect) == "table" and (kind.expect.status ~= nil or type(kind.expect.notStatus) == "table"),
            "a kind of toon needs an expected status, or a list of statuses that are wrong")
    end
    return T.RegisterVerdict(def)
end

------------------------------------------------------------------------------------------
-- Judging (no client calls)
------------------------------------------------------------------------------------------

-- An expectation in words.
function T.DescribeExpectation(expect)
    if expect.status ~= nil then
        return tostring(expect.status)
    end
    return "none of " .. table.concat(expect.notStatus, ", ")
end

local function StatusMeets(status, expect)
    if expect.status ~= nil then
        return status == expect.status
    end
    for _, wrong in ipairs(expect.notStatus) do
        if status == wrong then
            return false
        end
    end
    return true
end

-- What one pool item amounts to in this run.
--   facts, misses   the item's facts and where they miss the shape (nil: it fits)
--   verdict         { status, binding } from the addon, or nil when it could not be read
--   expect          the kind's expectation
--   prior           the case stored by the last run, or nil
-- Returns the case to store. case.result is "pass", "fail", "regression", "retired" (it
-- fitted before and no longer does), "unfit" (it never fitted) or "unread".
function T.JudgeCase(facts, misses, verdict, expect, prior, version)
    local case = { facts = facts }
    if misses then
        if prior and (prior.result == "pass" or prior.result == "fail" or prior.result == "regression") then
            case.result = "retired"
            case.moved = T.Facts.Diff(prior.facts or {}, facts)
            case.note = "no longer fits the shape: " .. T.Facts.DescribeMisses(misses)
        elseif prior and prior.result == "retired" then
            case.result = "retired"
            case.moved = prior.moved
            case.note = prior.note
        else
            case.result = "unfit"
            case.note = T.Facts.DescribeMisses(misses)
        end
        return case
    end
    if not verdict then
        case.result = "unread"
        case.note = "the addon had no verdict (item or tooltip not ready)"
        return case
    end

    case.status, case.binding = verdict.status, verdict.binding
    local matches = StatusMeets(verdict.status, expect)
        and (expect.binding == nil or expect.binding == verdict.binding)
    if matches then
        case.result = "pass"
        return case
    end

    case.result = "fail"
    case.note = ("expected %s, got %s"):format(T.DescribeExpectation(expect), tostring(verdict.status))
    if expect.binding ~= nil and expect.binding ~= verdict.binding then
        case.note = case.note .. (" (binding %s, expected %s)"):format(tostring(verdict.binding),
            tostring(expect.binding))
    end
    if prior and prior.result == "pass" and prior.v == version then
        local changed = T.Facts.Diff(prior.facts or {}, facts)
        if changed then
            -- Still the same shape, but something else about the item or the toon moved.
            case.note = case.note .. "; since it last passed: " .. T.Facts.DescribeDiff(changed)
            case.moved = changed
        else
            case.result = "regression"
            case.note = case.note .. "; it passed before with the same facts"
        end
    end
    return case
end

-- The state of a toon kind from its cases: the worst that happened, or "uncovered" when no
-- item of the pool fits the shape on this toon.
function T.JudgeKind(cases)
    local seen = {}
    for _, case in pairs(cases) do
        seen[case.result] = true
    end
    if seen.regression then return "regression" end
    if seen.fail then return "fail" end
    if seen.pass then return "pass" end
    return "uncovered"
end

------------------------------------------------------------------------------------------
-- Running
------------------------------------------------------------------------------------------

local RANK = { regression = 5, fail = 4, error = 4, uncovered = 3, pass = 1 }

local function RunKind(def, kind, toon)
    local record = T.db.verdicts[def.id][kind.name] or {}
    local priorCases = (record.v == def.version) and record.cases or {}
    local cases = {}
    for _, itemID in ipairs(kind.pool or def.pool or {}) do
        local prior = priorCases[itemID]
        local case
        local item, why = T.LoadItem(itemID)
        if not item then
            case = { result = "unread", note = why }
        else
            local facts = T.Facts.Read(def.facts, item)
            local misses = T.Facts.Mismatch(def.shape, facts)
            local verdict
            if not misses then
                local ready, status, binding = T.GetVerdict(item)
                if ready then
                    verdict = { status = status, binding = binding }
                end
            end
            case = T.JudgeCase(facts, misses, verdict, kind.expect, prior, def.version)
        end
        case.v, case.at = def.version, GetServerTime()
        cases[itemID] = case
        T.Yield()
    end

    local state = T.JudgeKind(cases)
    local client = T.GetClient()
    T.db.verdicts[def.id][kind.name] = {
        v = def.version,
        state = state,
        expect = kind.expect,
        confirmed = def.confirmed or false,
        cases = cases,
        at = GetServerTime(),
        toon = toon.key,
        sig = toon.signature,
        flavor = client.flavor,
        build = client.build,
    }
    return state
end

-- Called by the runner, inside a job. Runs every kind this toon is, returns { status }, or
-- nil when the toon is none of them.
function T.RunVerdict(def)
    local toon = T.GetToon()
    T.db.verdicts[def.id] = T.db.verdicts[def.id] or {}
    local worst
    for _, kind in ipairs(def.kinds) do
        if T.ToonMatches(toon, kind.toon) then
            local state = RunKind(def, kind, toon)
            if not worst or RANK[state] > RANK[worst] then
                worst = state
            end
        end
    end
    return worst and { status = worst } or nil
end

-- The stored state for the kinds this toon is: status, message, time. nil when it is none.
function T.VerdictStatus(def, toon)
    local records = T.db.verdicts[def.id] or {}
    local worst, message, at
    for _, kind in ipairs(def.kinds) do
        if T.ToonMatches(toon, kind.toon) then
            local record = records[kind.name]
            local state = "uncovered"
            local note = "not run yet"
            if record and record.v == def.version and record.sig == toon.signature then
                state, at = record.state, record.at
                note = nil
                for _, itemID in ipairs(T.SortedKeys(record.cases)) do
                    local case = record.cases[itemID]
                    if case.result ~= "pass" and case.note then
                        note = (note and (note .. " | ") or "") .. ("item %s %s: %s"):format(tostring(itemID),
                            case.result, case.note)
                    end
                end
            end
            if not worst or RANK[state] > RANK[worst] then
                worst, message = state, note and (kind.name .. ": " .. note) or nil
            end
        end
    end
    return worst, message, at
end

-- Every test and toon kind with what is known about it, for the coverage table: a cell
-- nobody has run on a fitting toon is unvalidated.
function T.GetCoverage()
    local rows = {}
    local flavor = T.GetClient().flavor
    for _, def in ipairs(T.tests) do
        if def.kind == "verdict" and (not def.flavor or def.flavor == flavor) then
            local records = T.db.verdicts[def.id] or {}
            for _, kind in ipairs(def.kinds) do
                local record = records[kind.name]
                local current = record and record.v == def.version
                rows[#rows + 1] = {
                    id = def.id,
                    kind = kind.name,
                    state = current and record.state or "unvalidated",
                    toon = current and record.toon or nil,
                    build = current and record.build or nil,
                    at = current and record.at or nil,
                }
            end
        end
    end
    return rows
end
