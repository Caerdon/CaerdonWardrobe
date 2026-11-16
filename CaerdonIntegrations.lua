-- Integration report: whether each third-party integration found the places it attaches to.
--
-- An integration hooks functions of another addon, and that addon can rename or remove them in
-- any update. The feature then draws nothing, with no error to report. Each integration declares
-- its hook points and notes them as it attaches (FeatureMixin.lua: integration, NoteHookPoint);
-- this module reads the two and says, per integration, what was found.
--
-- Only integrations whose addon was loaded when this addon loaded are listed: the others never
-- register a feature. The Debug Frame export prints the result ("[Integrations]") through
-- GetReportLines(); the test addon stores GetReport() under the other addon's version.

local ADDON_NAME, NS = ...

CaerdonIntegrations = {}

local function AddonVersion(addon)
    local version = C_AddOns.GetAddOnMetadata(addon, "Version")
    if version == nil or version == "" then
        return "unknown version"
    end
    return version
end

-- One declared or noted hook point: { label, optional, state, found, missing }.
-- state: "found", "missing" (looked for and not there), "notReached" (the feature has not come
-- to the place where it attaches), "undeclared" (noted but not in the declaration).
local function DescribePoint(label, optional, noted)
    local point = { label = label, optional = optional, found = 0, missing = 0 }
    if noted then
        point.found, point.missing = noted.found, noted.missing
    end
    if point.found > 0 then
        point.state = "found"
    elseif point.missing > 0 then
        point.state = "missing"
    else
        point.state = "notReached"
    end
    return point
end

local function Labels(points, state, optional)
    local labels = {}
    for _, point in ipairs(points) do
        if point.state == state and (optional == nil or point.optional == optional) then
            labels[#labels + 1] = point.label
        end
    end
    return labels
end

-- "problem": a hook point the feature needs is gone, its Init did not finish, or its
-- declaration is out of step with its code. "waiting": nothing is wrong so far, but a needed
-- place has not been reached (a window that has not been opened). "ok": every needed place
-- was found.
local function Judge(entry)
    local needed, neededFound = 0, 0
    for _, point in ipairs(entry.points) do
        if not point.optional and point.state ~= "undeclared" then
            needed = needed + 1
            if point.state == "found" then
                neededFound = neededFound + 1
            end
        end
    end
    entry.needed, entry.neededFound = needed, neededFound

    local missing = Labels(entry.points, "missing", false)
    local undeclared = Labels(entry.points, "undeclared")
    local notReached = Labels(entry.points, "notReached", false)
    local optionalMissing = Labels(entry.points, "missing", true)

    local parts = { ("%d of %d hook points found"):format(neededFound, needed) }
    if #missing > 0 then
        parts[#parts + 1] = "missing: " .. table.concat(missing, ", ")
    end
    if not entry.initFinished then
        parts[#parts + 1] = "its Init did not finish"
    end
    if #notReached > 0 then
        parts[#parts + 1] = "not reached yet: " .. table.concat(notReached, ", ")
    end
    if #optionalMissing > 0 then
        parts[#parts + 1] = "optional, not there: " .. table.concat(optionalMissing, ", ")
    end
    if #undeclared > 0 then
        parts[#parts + 1] = "noted but not declared: " .. table.concat(undeclared, ", ")
    end

    if #missing > 0 or #undeclared > 0 or not entry.initFinished then
        entry.verdict = "problem"
    elseif #notReached > 0 then
        entry.verdict = "waiting"
    else
        entry.verdict = "ok"
    end
    entry.summary = table.concat(parts, "; ")
end

-- Every registered integration, sorted by feature name:
-- { feature, addon, version, initFinished, points, needed, neededFound, verdict, summary }.
function CaerdonIntegrations:GetReport()
    local report = {}
    for name, feature in pairs(CaerdonWardrobe:GetRegisteredFeatures()) do
        local declared = feature.integration
        if type(declared) == "table" then
            local addon = declared.addon or name
            local entry = {
                feature = name,
                addon = addon,
                version = AddonVersion(addon),
                initFinished = feature.initFinished == true,
                points = {},
            }
            local noted = feature.hookPointsNoted or {}
            local seen = {}
            for _, label in ipairs(declared.hookPoints or {}) do
                seen[label] = true
                entry.points[#entry.points + 1] = DescribePoint(label, false, noted[label])
            end
            for _, label in ipairs(declared.optionalHookPoints or {}) do
                seen[label] = true
                entry.points[#entry.points + 1] = DescribePoint(label, true, noted[label])
            end
            local extra = {}
            for label in pairs(noted) do
                if not seen[label] then
                    extra[#extra + 1] = label
                end
            end
            table.sort(extra)
            for _, label in ipairs(extra) do
                local point = DescribePoint(label, false, noted[label])
                point.state = "undeclared"
                entry.points[#entry.points + 1] = point
            end
            Judge(entry)
            report[#report + 1] = entry
        end
    end
    table.sort(report, function(a, b) return a.feature < b.feature end)
    return report
end

-- The report as { indent, text } lines for the Debug Frame export: one line per integration.
function CaerdonIntegrations:GetReportLines()
    local lines = {}
    local report = self:GetReport()
    if #report == 0 then
        lines[1] = { indent = 1, text = "none (no addon with an integration was loaded before this one)" }
        return lines
    end
    for _, entry in ipairs(report) do
        local who = entry.feature
        if entry.addon ~= entry.feature then
            who = who .. " (" .. entry.addon .. ")"
        end
        lines[#lines + 1] = {
            indent = 1,
            text = ("%s %s: %s, %s"):format(who, entry.version, entry.verdict, entry.summary),
        }
    end
    return lines
end
