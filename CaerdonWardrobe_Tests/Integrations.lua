-- Integrations: whether each one found the places it hooks, per version of the other addon.
--
-- The addon keeps the facts itself (CaerdonIntegrations: what each integration declared and
-- what it found when it attached), because a user's Copy Details export has to carry the same
-- line. This file only adds memory: one record per integration and version of the other
-- addon, added to at the end of every session, with how many items that integration drew.
-- A hook point that is only reached when a window is opened is "not reached" in a session
-- that never opened it, so the record counts sessions rather than trusting one.

local _, T = ...

local KEEP_VERSIONS = 4

-- Pure: adds one session's report entry (CaerdonIntegrations:GetReport) to a stored record
-- and judges the record as a whole. Counts are sessions, not calls.
--   ok       every needed hook point was found in some session
--   waiting  nothing is wrong, but a needed point has never been reached
--   problem  a needed point was looked for and never found, an Init did not finish in the
--            last session, or the code notes a point its declaration does not list
function T.MergeIntegration(record, entry, draws, now)
    record = record or { firstSeen = now, sessions = 0, draws = 0, points = {} }
    record.addon = entry.addon
    record.at = now
    record.sessions = record.sessions + 1
    record.draws = record.draws + (draws or 0)
    record.initFinished = entry.initFinished and true or false

    local current = {}
    for _, point in ipairs(entry.points) do
        current[point.label] = true
        local stored = record.points[point.label] or { found = 0, missing = 0, notReached = 0 }
        stored.optional = point.optional and true or nil
        stored.undeclared = point.state == "undeclared" and true or nil
        if point.found > 0 then
            stored.found = stored.found + 1
        elseif point.missing > 0 then
            stored.missing = stored.missing + 1
        else
            stored.notReached = stored.notReached + 1
        end
        record.points[point.label] = stored
    end
    -- A point the code no longer has.
    for label in pairs(record.points) do
        if not current[label] then
            record.points[label] = nil
        end
    end

    local missing, neverReached, undeclared = {}, {}, {}
    for _, label in ipairs(T.SortedKeys(record.points)) do
        local stored = record.points[label]
        if stored.undeclared then
            undeclared[#undeclared + 1] = label
        elseif not stored.optional and stored.found == 0 then
            if stored.missing > 0 then
                missing[#missing + 1] = label
            else
                neverReached[#neverReached + 1] = label
            end
        end
    end
    record.missing, record.neverReached, record.undeclared = missing, neverReached, undeclared
    if #missing > 0 or #undeclared > 0 or not record.initFinished then
        record.verdict = "problem"
    elseif #neverReached > 0 then
        record.verdict = "waiting"
    else
        record.verdict = "ok"
    end
    return record
end

local function GetReport()
    if not CaerdonIntegrations or not CaerdonIntegrations.GetReport then
        return nil -- an addon version from before the report
    end
    return CaerdonIntegrations:GetReport()
end

-- Adds this session to the stored records. Once per session, at its end, when every window
-- that was going to be opened has been.
local function RecordSession()
    local report = GetReport()
    if not report or not T.db then
        return
    end
    local now = GetServerTime()
    local build, toon = T.GetClient().build, T.GetToon().key
    local subjectVersion = C_AddOns.GetAddOnMetadata(T.SUBJECT, "Version")
    for _, entry in ipairs(report) do
        local versions = T.db.integrations[entry.feature] or {}
        T.db.integrations[entry.feature] = versions
        local record = T.MergeIntegration(versions[entry.version], entry, T.counters.byFeature[entry.feature], now)
        record.build, record.toon, record.subjectVersion = build, toon, subjectVersion
        versions[entry.version] = record

        local keys = T.SortedKeys(versions)
        table.sort(keys, function(a, b) return versions[a].at > versions[b].at end)
        for index = KEEP_VERSIONS + 1, #keys do
            versions[keys[index]] = nil
        end
    end
end

T.RegisterEvent("PLAYER_LOGOUT", RecordSession)

local VERDICT_COLOR = { ok = "|cff40ff40", waiting = "|cffffcc00", problem = "|cffff4040" }

local function EntryLine(entry)
    return ("  %s%s|r  %s (%s %s): %s"):format(VERDICT_COLOR[entry.verdict] or "", entry.verdict, entry.feature,
        entry.addon, entry.version, entry.summary)
end

-- After login: say so when an integration could not attach. Quiet otherwise.
function T.CheckIntegrations()
    for _, entry in ipairs(GetReport() or {}) do
        if entry.verdict == "problem" then
            T.Print("an integration could not attach:")
            print(EntryLine(entry))
        end
    end
end

-- /cwtest integrations: this session's report, with what earlier sessions add to it.
function T.PrintIntegrations()
    local report = GetReport()
    if not report then
        T.Print("this version of the addon has no integration report.")
        return
    end
    if #report == 0 then
        T.Print("no integration is active: none of the addons it has one for was loaded before it.")
        return
    end
    T.Print("integrations this session (a hook point is \"not reached\" until its window has been opened):")
    for _, entry in ipairs(report) do
        print(EntryLine(entry))
        local stored = T.db.integrations[entry.feature] and T.db.integrations[entry.feature][entry.version]
        local draws = T.counters.byFeature[entry.feature] or 0
        print(("      %d draws this session%s"):format(draws, stored
            and ("; %d earlier sessions with this version, %d draws, over all of them: %s"):format(stored.sessions,
                stored.draws, tostring(stored.verdict))
            or "; first session with this version"))
    end
end
