-- The offline harness: the addon's real Lua under LuaJIT, in a mocked client.
--
--   luajit tools/harness/run.lua                     every scenario, then every fixture
--   luajit tools/harness/run.lua scenarios [name ...]
--   luajit tools/harness/run.lua replay [name ...]   fixtures whose name contains one of these
--   luajit tools/harness/run.lua import              recordings from the clients' saved variables
--
--   --verbose        everything a replay noticed, not only what failed
--   --wow DIR        the folder that holds _retail_ and _forever_ (default $CAERDON_WOW, then
--                    the usual install folders); --file PATH reads one saved variables file
--   --replace        import: overwrite a fixture that is already there
--   --keep-names     import: leave toon and realm names as they are
--   --builds DIR     the mirrors (default $CAERDON_BUILDS, then ~/Projects/WoW/Builds)
--
-- This is offline evidence. A scenario tests the harness and the recorder against a
-- hand-made game. A fixture is what a client answered once: replaying it shows that the
-- addon's code still decides the same from the same answers, not that the client still gives
-- them. Exit code 1 when something failed, 2 for a problem with the setup.
--
-- It needs the source and listings mirrors (docs/dev-notes.md, Client Sources).

local scriptDir = (arg[0] or ""):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."

local command, names, options = nil, {}, { files = {} }
do
    local index = 1
    while arg[index] do
        local word = arg[index]
        if word == "--verbose" then
            options.verbose = true
        elseif word == "--replace" then
            options.replace = true
        elseif word == "--keep-names" then
            options.keepNames = true
        elseif word == "--wow" or word == "--file" or word == "--builds" then
            index = index + 1
            if not arg[index] then
                io.stderr:write(word .. " needs a value\n")
                os.exit(2)
            end
            if word == "--wow" then
                options.wow = arg[index]
            elseif word == "--builds" then
                options.builds = arg[index]
            else
                options.files[#options.files + 1] = arg[index]
            end
        elseif word:sub(1, 2) == "--" then
            io.stderr:write("unknown option " .. word .. "; the head of tools/harness/run.lua lists them\n")
            os.exit(2)
        elseif not command then
            command = word
        else
            names[#names + 1] = word
        end
        index = index + 1
    end
end

local H = dofile(scriptDir .. "/init.lua")
if options.builds then
    H.buildsDir = options.builds:gsub("\\", "/")
end

local function Exists(path)
    local handle = io.open(path, "rb")
    if handle then
        handle:close()
    end
    return handle ~= nil
end

for _, flavor in ipairs({ "forever", "retail" }) do
    if not Exists(H.BuildsDir() .. "/source/" .. flavor .. "/version.txt") then
        io.stderr:write(("harness: no source mirror for %s under %s (update.sh there fetches it; --builds DIR names another)\n")
            :format(flavor, H.BuildsDir()))
        os.exit(2)
    end
end

local function Wanted(name)
    if #names == 0 then
        return true
    end
    for _, part in ipairs(names) do
        if name:find(part, 1, true) then
            return true
        end
    end
    return false
end

local failed = 0

------------------------------------------------------------------------------------------
-- Scenarios
------------------------------------------------------------------------------------------

local function RunScenarios()
    print("Scenarios (the addon's and the test addon's code against a hand-made client)")
    for _, file in ipairs(H.ListDir(H.dir .. "/scenarios")) do
        local name = file:match("^(.*)%.lua$")
        if name and Wanted(name) then
            local checks, failures = 0, {}
            local S = {}
            function S.Check(condition, label)
                checks = checks + 1
                if not condition then
                    failures[#failures + 1] = label
                end
            end
            function S.Equal(actual, expected, label)
                S.Check(actual == expected, ("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)))
            end
            local chunk, problem = loadfile(H.dir .. "/scenarios/" .. file)
            local ok = chunk ~= nil
            if ok then
                ok, problem = H.Guards.pcall(function() chunk()(H, S) end)
            end
            if not ok then
                failures[#failures + 1] = "the scenario stopped: " .. tostring(problem)
            end
            print(("  %s  %s: %d checks%s"):format(#failures == 0 and "pass" or "FAIL", name, checks,
                #failures > 0 and (", %d failed"):format(#failures) or ""))
            for _, label in ipairs(failures) do
                print("        " .. label)
            end
            if #failures > 0 then
                failed = failed + 1
            end
        end
    end
end

-- The tests that are older than the shared client: each is a script of its own with a small
-- client of its own, run in a process of its own. Its last line is "N checks, M failed".
local function RunStandalone()
    local interpreter = arg[-1] or "luajit"
    local windows = package.config:sub(1, 1) == "\\"
    for _, file in ipairs(H.ListDir(H.dir .. "/standalone")) do
        local name = file:match("^(.*)%.lua$")
        if name and Wanted(name) then
            local line = ('"%s" "%s" "%s" 2>&1'):format(interpreter, H.dir .. "/standalone/" .. file, H.addonDir)
            if windows then
                line = '"' .. line .. '"' -- cmd takes the outer pair off
            end
            local checks, failures, complaints = nil, nil, {}
            local pipe = io.popen(line)
            if pipe then
                for output in pipe:lines() do
                    output = output:gsub("\r$", "")
                    local counted, bad = output:match("^(%d+) checks, (%d+) failed$")
                    if counted then
                        checks, failures = tonumber(counted), tonumber(bad)
                    elseif output:find("^%s*FAIL") or output:find("luajit", 1, true) then
                        complaints[#complaints + 1] = output
                    end
                end
                pipe:close()
            end
            local ok = checks ~= nil and failures == 0
            print(("  %s  %s: %s"):format(ok and "pass" or "FAIL", name,
                checks and ("%d checks%s"):format(checks, failures > 0 and (", %d failed"):format(failures) or "")
                    or "it did not finish"))
            for _, complaint in ipairs(complaints) do
                print("        " .. complaint)
            end
            if not ok then
                failed = failed + 1
            end
        end
    end
end

------------------------------------------------------------------------------------------
-- Fixtures
------------------------------------------------------------------------------------------

local function RunFixtures()
    local fixtures = H.ListFixtures()
    print(("Fixtures (%d recordings of a client's answers, replayed)"):format(#fixtures))
    local counts = {}
    for _, fixture in ipairs(fixtures) do
        if Wanted(fixture.name) then
            local recording, environment, problem = H.LoadFixture(fixture.path)
            local result
            if not recording then
                result = { state = "error", error = "cannot read it: " .. tostring(problem), expected = {} }
            else
                result = H.Replay(environment, recording)
            end
            counts[result.state] = (counts[result.state] or 0) + 1
            local lines = H.DescribeReplay(result, options.verbose)
            local expected = result.expected
            print(("  %-7s %s  (%s%s)"):format(result.state == "pass" and "pass" or result.state:upper(), fixture.name,
                tostring(expected.status), expected.binding and (" / " .. tostring(expected.binding)) or ""))
            for _, line in ipairs(lines) do
                print("          " .. line)
            end
            if result.state ~= "pass" then
                failed = failed + 1
            end
        end
    end
    local parts = {}
    for _, state in ipairs({ "pass", "differs", "stale", "error" }) do
        if counts[state] then
            parts[#parts + 1] = ("%d %s"):format(counts[state], state)
        end
    end
    if #parts > 0 then
        print("  " .. table.concat(parts, ", "))
    end
end

------------------------------------------------------------------------------------------
-- Import
------------------------------------------------------------------------------------------

local function SavedVariablesFiles()
    if #options.files > 0 then
        return options.files
    end
    local wow
    for _, dir in ipairs({ options.wow or false, os.getenv("CAERDON_WOW") or false, "C:/Program Files (x86)/World of Warcraft",
        "C:/Program Files/World of Warcraft", "/Applications/World of Warcraft" }) do
        if dir and (#H.ListDir(dir .. "/_retail_/WTF/Account", true) > 0
                or #H.ListDir(dir .. "/_forever_/WTF/Account", true) > 0) then
            wow = dir:gsub("\\", "/")
            break
        end
    end
    if not wow then
        io.stderr:write("harness: no World of Warcraft folder found; pass --wow DIR or set CAERDON_WOW\n")
        os.exit(2)
    end
    local files = {}
    for _, flavor in ipairs({ "_retail_", "_forever_" }) do
        local accounts = wow .. "/" .. flavor .. "/WTF/Account"
        for _, account in ipairs(H.ListDir(accounts, true)) do
            local path = accounts .. "/" .. account .. "/SavedVariables/CaerdonWardrobe_Tests.lua"
            if Exists(path) then
                files[#files + 1] = path
            end
        end
    end
    return files
end

local function RunImport()
    local total = { written = 0, same = 0, exists = 0, rejected = 0, unusable = 0 }
    local seen = 0
    for index, path in ipairs(SavedVariablesFiles()) do
        local globals, problem = H.ReadSavedVariables(path)
        if not globals then
            io.stderr:write("harness: cannot read " .. path .. ": " .. tostring(problem) .. "\n")
            os.exit(2)
        end
        local db = globals.CaerdonWardrobeTestsDB
        local count = db and db.recordings and #(db.recordings.list or {}) or 0
        -- The account's folder name is no part of the output.
        print(("Saved variables %d (%s): %d recordings"):format(index, path:match("(_%a+_)") or "a file", count))
        seen = seen + count
        local counts = H.Import(db, options)
        for key, value in pairs(counts) do
            total[key] = total[key] + value
        end
    end
    if seen == 0 then
        print("Nothing to import: /cwtest record <item> in a client, /reload, then run this again.")
        return
    end
    print(("%d written, %d the same as before, %d already there, %d rejected, %d unusable"):format(total.written,
        total.same, total.exists, total.rejected, total.unusable))
    if total.rejected > 0 then
        print("A rejected recording is not kept. What it lists is what the recorder missed (docs/dev-notes.md, Offline Harness).")
        failed = failed + 1
    end
end

------------------------------------------------------------------------------------------

print("CaerdonWardrobe offline harness (LuaJIT, mocked client: logic, not the client)")
if command == nil then
    RunScenarios()
    RunStandalone()
    RunFixtures()
elseif command == "scenarios" then
    RunScenarios()
    RunStandalone()
elseif command == "replay" then
    RunFixtures()
elseif command == "import" then
    RunImport()
else
    io.stderr:write("unknown command " .. command .. "; the head of tools/harness/run.lua lists them\n")
    os.exit(2)
end

print("")
print(failed == 0 and "Result: nothing failed." or ("Result: %d failed."):format(failed))
os.exit(failed == 0 and 0 or 1)
