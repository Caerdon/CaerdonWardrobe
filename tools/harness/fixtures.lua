-- Fixtures: recordings as files in the repository (tools/harness/fixtures/<flavor>/), and the
-- import that makes them from what the test addon's recorder saved in a client.
--
-- A fixture is two files: the recording of one item, and the environment of the session it
-- was taken in (what the addon reads without calling anything; one file for all recordings
-- of a session). Both are plain Lua tables with sorted keys, so a diff reads.
--
-- The import replays every recording before it writes it. One that does not come out as
-- recorded is not kept: the list of questions it has no answer for says what the recorder
-- missed. The repository is public, so toon and realm names are replaced on the way in.

local H = ...

local Guards = H.Guards

------------------------------------------------------------------------------------------
-- Files
------------------------------------------------------------------------------------------

local function SortedKeys(map)
    local keys = {}
    for key in pairs(map) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then
            return a < b
        end
        return type(a) == "number"
    end)
    return keys
end

local function Number(value)
    local text = Guards.format("%.14g", value)
    if tonumber(text) ~= value then
        text = Guards.format("%.17g", value)
    end
    return text
end

local function KeyText(key)
    if type(key) == "string" and key:find("^[%a_][%w_]*$") then
        return key
    elseif type(key) == "string" then
        return "[" .. Guards.format("%q", key) .. "]"
    end
    return "[" .. Number(key) .. "]"
end

local function Scalar(value)
    local kind = type(value)
    if kind == "string" then
        return (Guards.format("%q", value):gsub("\\\n", "\\n"))
    elseif kind == "number" then
        return Number(value)
    end
    return tostring(value)
end

-- A small table on one line, or nil when it does not fit in `room` characters. The list part
-- comes first, without its keys.
local function Inline(value, room)
    if type(value) ~= "table" then
        local text = Scalar(value)
        return #text <= room and text or nil
    end
    local parts, used, listed = {}, 4, 0
    while value[listed + 1] ~= nil do
        listed = listed + 1
        local text = Inline(value[listed], room - used)
        if not text then
            return nil
        end
        parts[#parts + 1] = text
        used = used + #text + 2
    end
    for _, key in ipairs(SortedKeys(value)) do
        if not (type(key) == "number" and key >= 1 and key <= listed and key % 1 == 0) then
            local text = Inline(value[key], room - used)
            if not text then
                return nil
            end
            text = KeyText(key) .. " = " .. text
            parts[#parts + 1] = text
            used = used + #text + 2
        end
    end
    if used > room then
        return nil
    end
    return #parts == 0 and "{}" or ("{ " .. table.concat(parts, ", ") .. " }")
end

local LINE = 110

local function Write(out, value, indent)
    local kind = type(value)
    if kind == "table" then
        local inline = Inline(value, LINE - #indent)
        if inline then
            out[#out + 1] = inline
            return
        end
        out[#out + 1] = "{\n"
        local inner = indent .. "    "
        for _, key in ipairs(SortedKeys(value)) do
            out[#out + 1] = inner
            out[#out + 1] = KeyText(key)
            out[#out + 1] = " = "
            Write(out, value[key], inner)
            out[#out + 1] = ",\n"
        end
        out[#out + 1] = indent .. "}"
    else
        out[#out + 1] = Scalar(value)
    end
end

-- A table as Lua source: the same table gives the same text.
function H.Serialize(value)
    local out = {}
    Write(out, value, "")
    return table.concat(out)
end

function H.WriteFile(path, text)
    local handle, problem = io.open(path, "wb")
    if not handle then
        error("cannot write " .. path .. ": " .. tostring(problem), 0)
    end
    handle:write(text)
    handle:close()
end

local function IsWindows()
    return package.config:sub(1, 1) == "\\"
end

function H.ListDir(path, directories)
    local command
    if IsWindows() then
        command = Guards.format('dir /b %s "%s" 2>NUL', directories and "/ad" or "/a-d", (path:gsub("/", "\\")))
    else
        command = Guards.format('ls -1p "%s" 2>/dev/null', path)
    end
    local names = {}
    local pipe = io.popen(command)
    if pipe then
        for line in pipe:lines() do
            line = line:gsub("\r$", "")
            if IsWindows() then
                names[#names + 1] = line
            elseif (line:sub(-1) == "/") == (directories and true or false) then
                names[#names + 1] = (line:gsub("/$", ""))
            end
        end
        pipe:close()
    end
    table.sort(names)
    return names
end

function H.MakeDir(path)
    if IsWindows() then
        os.execute(Guards.format('if not exist "%s" mkdir "%s"', (path:gsub("/", "\\")), (path:gsub("/", "\\"))))
    else
        os.execute(Guards.format('mkdir -p "%s"', path))
    end
end

function H.FixturesDir()
    return H.fixturesDir or (H.dir .. "/fixtures")
end

-- The globals a saved variables file sets.
-- Parsed, not compiled: the test addon's file can hold more than a Lua chunk may
-- (tools/savedvars.lua).
function H.ReadSavedVariables(path)
    H.SavedVars = H.SavedVars or dofile(H.dir .. "/../savedvars.lua")
    return H.SavedVars.Read(path)
end

-- Every fixture: { path, flavor, name }.
function H.ListFixtures()
    local found = {}
    for _, flavor in ipairs(H.ListDir(H.FixturesDir(), true)) do
        for _, file in ipairs(H.ListDir(H.FixturesDir() .. "/" .. flavor)) do
            if file:find("%.lua$") and not file:find("^env%-") then
                found[#found + 1] = { path = H.FixturesDir() .. "/" .. flavor .. "/" .. file, flavor = flavor,
                    name = flavor .. "/" .. file:gsub("%.lua$", "") }
            end
        end
    end
    return found
end

-- The recording of a fixture file and its environment.
function H.LoadFixture(path)
    local chunk, problem = loadfile(path)
    if not chunk then
        return nil, nil, problem
    end
    local recording = chunk()
    local environmentPath = path:gsub("[^/\\]+$", "") .. recording.environment .. ".lua"
    local environmentChunk, environmentProblem = loadfile(environmentPath)
    if not environmentChunk then
        return nil, nil, environmentProblem
    end
    return recording, environmentChunk()
end

------------------------------------------------------------------------------------------
-- Names
------------------------------------------------------------------------------------------

local function EscapePattern(text)
    return (text:gsub("%p", "%%%0"))
end

local function WholeWord(name)
    return "%f[%w]" .. EscapePattern(name) .. "%f[%W]"
end

-- The client names a realm in more than one way (GetRealmName's is not the one UnitName
-- returns beside the name), so every form a recording holds is collected.
local REALM_ANSWERS = { GetRealmName = 1, GetNormalizedRealmName = 1, UnitName = 2, UnitFullName = 2 }
local TOON_ANSWERS = { UnitName = 1, UnitFullName = 1 }

-- What to replace: the toon's name and realm in every form, and every other toon the saved
-- data names (the keys below a key that holds the realm's name).
local function CollectNames(environment, recordings)
    local names, order = {}, {}
    local function add(name, replacement)
        if type(name) == "string" and #name >= 2 and not names[name] then
            names[name] = replacement
            order[#order + 1] = name
        end
    end
    local toon = environment.toon or {}
    local realms, seenRealm = {}, {}
    local function addRealm(realm)
        if type(realm) == "string" and #realm >= 2 and not seenRealm[realm] then
            seenRealm[realm] = true
            realms[#realms + 1] = realm
            -- The saved data also keys by the realm without its spaces.
            local squeezed = realm:gsub("[%s%-']", "")
            if #squeezed >= 2 and not seenRealm[squeezed] then
                seenRealm[squeezed] = true
                realms[#realms + 1] = squeezed
            end
        end
    end

    add(toon.name, "Toon1")
    addRealm(toon.realm)
    for _, recording in ipairs(recordings) do
        for name, byKey in pairs(recording.calls or {}) do
            for _, answers in pairs(byKey) do
                for _, answer in ipairs(answers) do
                    if TOON_ANSWERS[name] then
                        add(answer[TOON_ANSWERS[name]], "Toon1")
                    end
                    if REALM_ANSWERS[name] then
                        addRealm(answer[REALM_ANSWERS[name]])
                    end
                end
            end
        end
    end

    local others = 1
    for _, saved in pairs(environment.saved or {}) do
        if type(saved) == "table" then
            for realmKey, toons in pairs(saved) do
                local isRealm = false
                for _, realm in ipairs(realms) do
                    isRealm = isRealm or (type(realmKey) == "string" and realmKey:find(realm, 1, true) ~= nil)
                end
                if isRealm and type(toons) == "table" then
                    for toonKey in pairs(toons) do
                        if type(toonKey) == "string" and not names[toonKey] then
                            others = others + 1
                            add(toonKey, "Toon" .. others)
                        end
                    end
                end
            end
        end
    end
    for _, realm in ipairs(realms) do
        add(realm, "Realm")
    end
    -- Longest first, so a name that contains another is replaced whole.
    table.sort(order, function(a, b)
        if #a ~= #b then
            return #a > #b
        end
        return a < b
    end)
    return names, order
end

local function ScrubText(text, names, order)
    for _, name in ipairs(order) do
        if text:find(name, 1, true) then
            text = text:gsub(WholeWord(name), names[name])
        end
    end
    -- A toon's GUID.
    text = text:gsub("Player%-%d+%-%x+", "Player-0-00000001")
    return text
end

local function Scrub(value, names, order)
    local kind = type(value)
    if kind == "string" then
        return ScrubText(value, names, order)
    elseif kind ~= "table" then
        return value
    end
    local copy = {}
    for key, item in pairs(value) do
        if type(key) == "string" then
            key = ScrubText(key, names, order)
        end
        copy[key] = Scrub(item, names, order)
    end
    return copy
end

-- Arguments are stored as text with lengths in it, so a name inside one cannot be replaced.
local function NameInAKey(recording, order)
    for name, byKey in pairs(recording.calls or {}) do
        for key in pairs(byKey) do
            for _, text in ipairs(order) do
                if key:find(WholeWord(text)) then
                    return name
                end
            end
        end
    end
end

-- The last look before a file is written: none of the names may be left in its text.
local function NameLeft(text, order)
    for _, name in ipairs(order) do
        if text:find(WholeWord(name)) then
            return true
        end
    end
    return false
end

------------------------------------------------------------------------------------------
-- Import
------------------------------------------------------------------------------------------

local function Slug(text)
    return (tostring(text or ""):lower():gsub("[^%w]+", "-"):gsub("^%-", ""):gsub("%-$", ""))
end

local function EnvironmentName(environment)
    local toon = environment.toon or {}
    return Guards.format("env-%s%s-%s", Slug(toon.class), tostring(toon.level or ""),
        os.date("!%Y%m%d-%H%M%S", environment.at or 0))
end

local function FixtureName(environment, recording)
    local toon = environment.toon or {}
    local name = Guards.format("%s%s-%s-%s", Slug(toon.class), tostring(toon.level or ""),
        tostring(recording.itemID or "item"), Slug(recording.name))
    if recording.request and recording.request.bag then
        name = name .. "-in-bags"
    end
    return name
end

-- The client numbers every tooltip it hands out (dataInstanceID), so two answers to the same
-- question never compare equal and nothing about a tooltip could be shared. The number says
-- nothing about the item and the addon does not read it: it is set to 0.
local function DropSerials(value)
    if type(value) == "table" then
        if type(value.dataInstanceID) == "number" then
            value.dataInstanceID = 0
        end
        for _, item in pairs(value) do
            DropSerials(item)
        end
    end
end

local function AnswersText(answers)
    local parts = {}
    for index, answer in ipairs(answers) do
        parts[index] = H.Keys.Answer(answer) .. (answer.error and ("!" .. answer.error) or "")
            .. (answer.callback and ("^" .. H.Keys.Answer(answer.callback)) or "")
    end
    return table.concat(parts, "\n")
end

-- Most of what one recording holds, every other recording of the session holds too: the quest
-- log, what the toon wears, who it is. An answer that two recordings agree on moves into the
-- environment's file (`calls`), once, and a replay looks there after the recording itself.
-- An environment file that is already there keeps what it has, since fixtures written
-- earlier rely on it; it only grows.
local function ShareAnswers(environment, recordings)
    local shared = environment.calls or {}
    environment.calls = shared
    local seen = {} -- name -> key -> { text, count }
    for _, recording in ipairs(recordings) do
        for name, byKey in pairs(recording.calls or {}) do
            seen[name] = seen[name] or {}
            for key, answers in pairs(byKey) do
                local text = AnswersText(answers)
                local entry = seen[name][key]
                if not entry then
                    seen[name][key] = { text = text, count = 1 }
                elseif entry.text == text then
                    entry.count = entry.count + 1
                else
                    entry.count = -math.huge -- the recordings disagree: each keeps its own
                end
            end
        end
    end
    for _, recording in ipairs(recordings) do
        for name, byKey in pairs(recording.calls or {}) do
            for key, answers in pairs(byKey) do
                local existing = shared[name] and shared[name][key]
                if existing then
                    if AnswersText(existing) == AnswersText(answers) then
                        byKey[key] = nil
                    end
                elseif seen[name][key].count >= 2 then
                    shared[name] = shared[name] or {}
                    shared[name][key] = answers
                    byKey[key] = nil
                end
            end
            if next(byKey) == nil then
                recording.calls[name] = nil
            end
        end
    end
end

-- db is the test addon's saved table. options: replace (overwrite a fixture that is there),
-- keepNames (no replacing of names), verbose, dryRun, log (a function for lines).
-- Returns counts: { written, same, exists, rejected, unusable }.
function H.Import(db, options)
    options = options or {}
    local log = options.log or print
    local counts = { written = 0, same = 0, exists = 0, rejected = 0, unusable = 0 }
    local recordings = db and db.recordings
    if not recordings or #(recordings.list or {}) == 0 then
        return counts
    end
    local function unusable(label, why)
        counts.unusable = counts.unusable + 1
        log(Guards.format("  unusable  %s: %s", label, why))
    end

    -- The recordings that can be used, by the environment they were taken in.
    local sessions, order = {}, {}
    for _, raw in ipairs(recordings.list) do
        local label = tostring(raw.name or raw.itemID or (raw.request and (raw.request.link or raw.request.itemID)) or "?")
        local rawEnvironment = recordings.environments[raw.environment]
        if raw.error or not raw.complete then
            unusable(label, tostring(raw.error or "the run was not complete"))
        elseif not rawEnvironment then
            unusable(label, "its environment is no longer in the saved variables")
        elseif raw.format ~= H.Keys.FORMAT or rawEnvironment.format ~= H.Keys.FORMAT then
            unusable(label, Guards.format("recorded in format %s, the harness reads %d", tostring(raw.format), H.Keys.FORMAT))
        else
            local session = sessions[raw.environment]
            if not session then
                session = { raw = rawEnvironment, list = {} }
                sessions[raw.environment] = session
                order[#order + 1] = raw.environment
            end
            session.list[#session.list + 1] = { raw = raw, label = label }
        end
    end

    for _, key in ipairs(order) do
        local session = sessions[key]
        local names, nameOrder = {}, {}
        if not options.keepNames then
            local raws = {}
            for index, entry in ipairs(session.list) do
                raws[index] = entry.raw
            end
            names, nameOrder = CollectNames(session.raw, raws)
        end
        local environment = Scrub(session.raw, names, nameOrder)
        local environmentName = EnvironmentName(environment)
        local flavor = environment.client.flavor
        local dir = H.FixturesDir() .. "/" .. flavor
        local environmentPath = dir .. "/" .. environmentName .. ".lua"

        -- What an earlier import already moved into this environment's file stays there.
        local existingEnvironment = loadfile(environmentPath)
        if existingEnvironment then
            environment.calls = existingEnvironment().calls
        end

        local usable = {}
        for _, entry in ipairs(session.list) do
            local leaked = NameInAKey(entry.raw, nameOrder)
            if leaked then
                unusable(entry.label, Guards.format("a call of %s was made with a toon or realm name, which cannot be "
                    .. "replaced (--keep-names imports it as it is)", leaked))
            else
                local recording = Scrub(entry.raw, names, nameOrder)
                recording.environment = environmentName
                recording.questions, recording.attempts, recording.loaded, recording.complete = nil, nil, nil, nil
                DropSerials(recording.calls)
                usable[#usable + 1] = recording
            end
        end
        ShareAnswers(environment, usable)

        local environmentText = "return " .. H.Serialize(environment) .. "\n"
        local environmentWritten = false
        for _, recording in ipairs(usable) do
            local name = FixtureName(environment, recording)
            -- Replay it from text, as it will be read from the file.
            local recordingText = "return " .. H.Serialize(recording) .. "\n"
            local result = H.Replay(loadstring(environmentText)(), loadstring(recordingText)(), options)
            if NameLeft(recordingText, nameOrder) or NameLeft(environmentText, nameOrder) then
                counts.rejected = counts.rejected + 1
                log(Guards.format("  rejected  %s/%s: a toon or realm name is still in its text", flavor, name))
            elseif result.state ~= "pass" or result.unansweredInVerdict > 0 or #result.unknown > 0 then
                counts.rejected = counts.rejected + 1
                log(Guards.format("  rejected  %s/%s: %s", flavor, name, result.state == "pass"
                    and "the verdict is reproduced, but the recording does not hold everything the addon asked"
                    or ("the replay does not reproduce it (" .. result.state .. ")")))
                for _, line in ipairs(H.DescribeReplay(result, options.verbose)) do
                    log("            " .. line)
                end
            else
                local path = dir .. "/" .. name .. ".lua"
                local existing = H.ReadFile(path)
                if existing and existing == recordingText then
                    counts.same = counts.same + 1
                    log(Guards.format("  same      %s/%s", flavor, name))
                elseif existing and not options.replace then
                    counts.exists = counts.exists + 1
                    log(Guards.format("  exists    %s/%s: another recording of it is there (--replace overwrites it)",
                        flavor, name))
                else
                    if not options.dryRun then
                        H.MakeDir(dir)
                        if not environmentWritten then
                            H.WriteFile(environmentPath, environmentText)
                            environmentWritten = true
                        end
                        H.WriteFile(path, recordingText)
                    end
                    counts.written = counts.written + 1
                    log(Guards.format("  %s  %s/%s: %s%s, %d answers used", existing and "replaced" or "written ",
                        flavor, name, tostring(recording.verdict.status),
                        recording.verdict.binding and (" / " .. tostring(recording.verdict.binding)) or "",
                        result.answered))
                    if options.verbose then
                        for _, line in ipairs(H.DescribeReplay(result, true)) do
                            log("            " .. line)
                        end
                    end
                end
            end
        end
    end
    return counts
end
