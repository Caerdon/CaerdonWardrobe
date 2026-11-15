-- Reads what the test addon (CaerdonWardrobe_Tests) saved in each client and prints it.
--
--   luajit tools/test-results.lua [--wow DIR] [--file PATH] [section ...]
--
-- The client writes the file on /reload and on logout, so reload before reading. DIR is the
-- folder that holds _retail_ and _forever_; it defaults to $CAERDON_WOW, then to the usual
-- install folders. --file reads one saved variables file instead.
--
-- Sections (all of them when none is named): sessions, contracts, verdicts, snapshot,
-- timing, journal, probes, errors. "detail" adds every contract's stored detail, and
-- "contract:<id>" prints one contract in full.
--
-- This prints what the clients recorded. Whatever is listed here was seen in a client; what
-- is missing was not run there.

local wowDir = os.getenv("CAERDON_WOW")
local files, sections = {}, {}

do
    local i = 1
    while arg[i] do
        if arg[i] == "--wow" then
            wowDir = arg[i + 1]
            i = i + 1
        elseif arg[i] == "--file" then
            files[#files + 1] = { path = arg[i + 1], label = arg[i + 1] }
            i = i + 1
        elseif arg[i]:sub(1, 2) == "--" then
            io.stderr:write("usage: luajit tools/test-results.lua [--wow DIR] [--file PATH] [section ...]\n")
            os.exit(2)
        else
            sections[arg[i]] = true
        end
        i = i + 1
    end
end

-- "contract:<id>" names single contracts rather than a section.
local namedSection, singleContracts = false, false
for name in pairs(sections) do
    if name:find("^contract:") then singleContracts = true else namedSection = true end
end

local function wants(section)
    if section == "contracts" and singleContracts then return true end
    return (not namedSection and not singleContracts) or sections[section] or false
end

local function exists(path)
    local handle = io.open(path, "rb")
    if handle then handle:close() end
    return handle ~= nil
end

local function listDirs(path)
    local windows = package.config:sub(1, 1) == "\\"
    local command = windows and ('dir /b /ad "%s" 2>NUL'):format(path:gsub("/", "\\"))
        or ('ls -1 "%s" 2>/dev/null'):format(path)
    local names = {}
    local pipe = io.popen(command)
    if pipe then
        for line in pipe:lines() do names[#names + 1] = (line:gsub("\r$", "")) end
        pipe:close()
    end
    return names
end

if #files == 0 then
    local candidates = { wowDir, "C:/Program Files (x86)/World of Warcraft", "C:/Program Files/World of Warcraft",
        "/Applications/World of Warcraft" }
    for index = 1, 4 do
        local dir = candidates[index]
        if dir and (exists(dir .. "/_retail_/Wow.exe") or #listDirs(dir .. "/_retail_/WTF/Account") > 0
            or #listDirs(dir .. "/_forever_/WTF/Account") > 0) then
            wowDir = dir:gsub("\\", "/")
            break
        end
    end
    if not wowDir then
        io.stderr:write("test-results: no World of Warcraft folder found; pass --wow DIR or set CAERDON_WOW\n")
        os.exit(2)
    end
    for _, flavor in ipairs({ "_retail_", "_forever_" }) do
        local accounts = wowDir .. "/" .. flavor .. "/WTF/Account"
        for _, account in ipairs(listDirs(accounts)) do
            local path = accounts .. "/" .. account .. "/SavedVariables/CaerdonWardrobe_Tests.lua"
            if exists(path) then
                files[#files + 1] = { path = path, label = flavor .. " account " .. account }
            end
        end
    end
    if #files == 0 then
        print("No results yet under " .. wowDir .. ": enable Caerdon Wardrobe Tests, log in, then /reload.")
        os.exit(0)
    end
end

------------------------------------------------------------------------------------------

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return tostring(a) < tostring(b)
    end)
    return keys
end

local function when(stamp)
    return stamp and os.date("%Y-%m-%d %H:%M", stamp) or "?"
end

local function inline(value, depth)
    depth = depth or 0
    if type(value) ~= "table" then
        return tostring(value)
    end
    local parts, isList = {}, #value > 0
    for _, key in ipairs(sortedKeys(value)) do
        local text = depth < 3 and inline(value[key], depth + 1) or "..."
        parts[#parts + 1] = isList and type(key) == "number" and text or (tostring(key) .. "=" .. text)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function block(value, indent)
    for _, key in ipairs(sortedKeys(value)) do
        local item = value[key]
        if type(item) == "table" and next(item) ~= nil and #inline(item) > 100 then
            print(indent .. tostring(key) .. ":")
            block(item, indent .. "  ")
        else
            print(indent .. tostring(key) .. ": " .. inline(item))
        end
    end
end

local function plainText(text)
    return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"))
end

local function figure(value)
    return value == nil and "-" or tostring(value)
end

local function share(profiler, name)
    local value = profiler and profiler.share and profiler.share[name]
    return value and ("%.2f%%"):format(value * 100) or "-"
end

------------------------------------------------------------------------------------------

local function printSessions(db)
    print("  Sessions (newest last):")
    for _, session in ipairs(db.sessions or {}) do
        print(("    %s  %s %s  %s (%s)  addon %s"):format(when(session.at), tostring(session.flavor),
            tostring(session.build), tostring(session.toon), tostring(session.signature),
            tostring(session.subjectVersion)))
    end
end

local function printContracts(db, withDetail)
    for _, build in ipairs(sortedKeys(db.contracts)) do
        print("  Contracts, build " .. build .. ":")
        local results = db.contracts[build]
        for _, id in ipairs(sortedKeys(results)) do
            local result = results[id]
            local listed = sections.contracts or sections.detail or not singleContracts or sections["contract:" .. id]
            if listed then
            print(("    %-7s %-34s %s%s"):format(tostring(result.status), id,
                result.message and plainText(result.message) or "", result.toon and ("  [" .. result.toon .. "]") or ""))
            if result.failures and #result.failures > 1 then
                for index = 2, #result.failures do print("            also: " .. plainText(result.failures[index])) end
            end
            if (withDetail or sections["contract:" .. id]) and result.detail then
                block(result.detail, "            ")
            end
            end
        end
        local events = db.events and db.events[build]
        if events and events.minutes and (sections.contracts or not singleContracts) then
            print(("  Events over %.0f minutes of play, build %s (per minute):"):format(events.minutes, build))
            for _, name in ipairs(sortedKeys(events.counts)) do
                print(("    %-36s %6d  %.2f"):format(name, events.counts[name], events.counts[name] / math.max(events.minutes, 0.01)))
            end
        end
    end
end

local function printVerdicts(db)
    print("  Verdict tests (a kind of toon nobody has run is not listed):")
    for _, id in ipairs(sortedKeys(db.verdicts)) do
        for _, kind in ipairs(sortedKeys(db.verdicts[id])) do
            local record = db.verdicts[id][kind]
            print(("    %-10s %s [%s]  on %s, %s, %s%s"):format(tostring(record.state), id, kind, tostring(record.toon),
                tostring(record.build), when(record.at),
                record.confirmed and "" or "  (expectation not confirmed in game)"))
            for _, itemID in ipairs(sortedKeys(record.cases)) do
                local case = record.cases[itemID]
                print(("        item %-7s %-10s %s%s"):format(tostring(itemID), tostring(case.result),
                    case.status and ("status " .. tostring(case.status)) or "", case.note and ("  " .. case.note) or ""))
            end
        end
    end
end

local function printSnapshots(db)
    for _, toon in ipairs(sortedKeys(db.snapshots)) do
        local store = db.snapshots[toon]
        print("  Snapshot, " .. toon .. ":")
        if store.base then
            print(("    base   %s  %d items%s, bank %s, addon %s, build %s"):format(when(store.base.at),
                #store.base.entries, (store.base.notDrawn or 0) > 0 and (", %d never drawn"):format(store.base.notDrawn) or "",
                store.base.bank and "included" or "not open", tostring(store.base.subjectVersion), tostring(store.base.build)))
        end
        if store.last then
            print(("    latest %s  %d items%s, bank %s"):format(when(store.last.at), #store.last.entries,
                (store.last.notDrawn or 0) > 0 and (", %d never drawn"):format(store.last.notDrawn) or "",
                store.last.bank and "included" or "not open"))
        end
        local diff = store.diff
        if diff then
            print(("    diff: %d the same, %d changed, %d only in the base, %d only in the latest (containers %s)"):format(
                diff.same, #diff.changed, #diff.onlyInBase, #diff.onlyInAfter, inline(diff.containersCompared)))
            for _, change in ipairs(diff.changed) do
                print("      " .. plainText(change.link) .. ": " .. tostring(change.summary))
                if change.why then print("          binding result: " .. inline(change.why)) end
                if change.transmog then print("          transmog info:  " .. inline(change.transmog)) end
            end
            if #diff.settingsChanged > 0 then
                print("    the addon's settings differ from the base:")
                for _, line in ipairs(diff.settingsChanged) do print("      " .. line) end
            end
            if not diff.addonsChanged then
                print("    which other addons the base was taken with is not on record")
            elseif #diff.addonsChanged > 0 then
                print("    other addons differ from the base, so a change above may not be the addon's:")
                for _, line in ipairs(diff.addonsChanged) do print("      " .. line) end
            end
            for _, entry in ipairs(diff.onlyInBase) do print("      only in the base: " .. plainText(entry)) end
            for _, entry in ipairs(diff.onlyInAfter) do print("      only in the latest: " .. plainText(entry)) end
        elseif store.base then
            print("    nothing compared yet: /cwtest snapshot after the change")
        end
    end
end

-- What differs between two recorded sets of other addons, as lines; nil when one is unknown.
local function addonChanges(db, beforeKey, afterKey)
    local sets = db.addonSets or {}
    local before = beforeKey and sets[beforeKey] and sets[beforeKey].addons
    local after = afterKey and sets[afterKey] and sets[afterKey].addons
    if not before or not after then
        return nil
    end
    local lines = {}
    for _, name in ipairs(sortedKeys(before)) do
        if after[name] == nil then
            lines[#lines + 1] = name .. " " .. before[name] .. " was removed"
        elseif after[name] ~= before[name] then
            lines[#lines + 1] = name .. " " .. before[name] .. " -> " .. after[name]
        end
    end
    for _, name in ipairs(sortedKeys(after)) do
        if before[name] == nil then
            lines[#lines + 1] = name .. " " .. after[name] .. " was added"
        end
    end
    return lines
end

-- Says so when a record was taken with other addons than the one before it: the two are
-- then not a before and after of the addon alone.
local function printAddonChange(db, previous, record)
    if not previous or previous.addons == record.addons then
        return
    end
    local lines = addonChanges(db, previous.addons, record.addons)
    if not lines then
        print("      (which other addons were enabled is not on record for the next entry or the one above)")
    elseif #lines > 0 then
        print("      (other addons changed between the entry above and the next: " .. table.concat(lines, "; ") .. ")")
    end
end

local function printTiming(db)
    print("  Timing (addon time is the client profiler's, summed per frame):")
    local previous
    for _, record in ipairs(db.timing or {}) do
        printAddonChange(db, previous, record)
        previous = record
        if record.kind == "refresh" then
            print(("    %s  %-8s %-10s x%d  draws %s  addon ms median %s worst %s  last icon ms %s  first icon ms %s  memory KB %s  [%s, %s, addon %s]")
                :format(when(record.at), "refresh", tostring(record.label), #record.runs, figure(record.medianDraws),
                    figure(record.medianCpuMs), figure(record.worstCpuMs), figure(record.medianLastDrawMs),
                    figure(record.medianFirstDrawMs), figure(record.medianMemoryKB), tostring(record.toon),
                    tostring(record.build), tostring(record.subjectVersion)))
            print(("        profiler after: recent %s ms (%s), peak %s ms, session %s ms (%s)%s"):format(
                figure(record.profilerAfter and record.profilerAfter.RecentAverageTime), share(record.profilerAfter, "RecentAverageTime"),
                figure(record.profilerAfter and record.profilerAfter.PeakTime),
                figure(record.profilerAfter and record.profilerAfter.SessionAverageTime), share(record.profilerAfter, "SessionAverageTime"),
                record.refreshItemsCalls ~= #record.runs and ("; " .. tostring(record.refreshItemsCalls) .. " refreshes happened during the " .. #record.runs .. " runs") or ""))
        elseif record.kind == "idle" then
            print(("    %s  %-8s %ss  addon ms %s (%s per second, worst frame %s)  refreshes per minute %s  draws %s  memory KB %s  [%s, %s]")
                :format(when(record.at), "idle", figure(record.seconds), figure(record.cpuMs), figure(record.cpuMsPerSecond),
                    figure(record.worstFrameMs), figure(record.refreshItemsPerMinute), figure(record.draws),
                    figure(record.memoryKB), tostring(record.toon), tostring(record.build)))
            print("        events: " .. inline(record.counts))
        end
    end
    print("  Logins and reloads:")
    for _, record in ipairs(db.logins or {}) do
        print(("    %s  %-6s to world %ss, world to idle %ss%s  draws %s  refreshes %s  memory KB %s  profiler session %s ms (%s) peak %s ms  [%s, %s]")
            :format(when(record.at), tostring(record.label), figure(record.secondsFromLoadToWorld),
                figure(record.secondsFromWorldToIdle), record.drained and "" or " (never idle)", figure(record.draws),
                figure(record.refreshItemsCalls), figure(record.memoryKB),
                figure(record.profiler and record.profiler.SessionAverageTime), share(record.profiler, "SessionAverageTime"),
                figure(record.profiler and record.profiler.PeakTime), tostring(record.toon), tostring(record.build)))
    end
end

local function printJournal(db)
    local journal = db.journal or {}
    print(("  Journal (%d entries, the last 25):"):format(#journal))
    for index = math.max(1, #journal - 24), #journal do
        local entry = journal[index]
        local what = entry.what or {}
        print(("    %s  %-42s %s  %s level %s  likely: %s"):format(when(entry.at), tostring(entry.event),
            tostring(what.name or what.itemID or what.sourceID or what.recipeID or what.mountID or what.level or ""),
            tostring(entry.toon), tostring(entry.level), tostring(entry.likely)))
        for _, around in ipairs(entry.around or {}) do
            local offset, kind = around.offset, around.kind
            around.offset, around.kind = nil, nil
            print(("        %+6.2fs %s %s"):format(offset or 0, tostring(kind), next(around) and inline(around) or ""))
            around.offset, around.kind = offset, kind
        end
    end
end

local function printProbes(db)
    for _, toon in ipairs(sortedKeys(db.probes)) do
        print("  Probes, " .. toon .. ":")
        for _, itemID in ipairs(sortedKeys(db.probes[toon])) do
            local probe = db.probes[toon][itemID]
            print(("    item %s %s: %s  (%s)"):format(tostring(itemID), plainText(probe.link or ""),
                probe.note or ("status " .. tostring(probe.status) .. (probe.binding and (", binding " .. tostring(probe.binding)) or "")),
                when(probe.at)))
            if probe.facts then print("        facts:    " .. inline(probe.facts)) end
            if probe.why then print("        binding:  " .. inline(probe.why)) end
            if probe.transmog then print("        transmog: " .. inline(probe.transmog)) end
            for index, line in ipairs(probe.tooltip or {}) do
                print(("        line %2d:  %s"):format(index, inline(line)))
            end
        end
    end
end

local function printErrors(db)
    if #(db.errors or {}) == 0 then
        return
    end
    print("  Errors in the tests themselves:")
    for _, entry in ipairs(db.errors) do
        print(("    %s  %s: %s"):format(when(entry.at), tostring(entry.where), plainText(entry.message)))
        if entry.stack then
            for line in tostring(entry.stack):gmatch("[^\n]+") do print("        " .. line) end
        end
    end
end

------------------------------------------------------------------------------------------

for _, file in ipairs(files) do
    print("== " .. file.label)
    local env = {}
    local chunk, err = loadfile(file.path)
    if not chunk then
        print("  cannot read " .. file.path .. ": " .. tostring(err))
    else
        setfenv(chunk, env)
        local ok, runError = pcall(chunk)
        local db = env.CaerdonWardrobeTestsDB
        if not ok or type(db) ~= "table" then
            print("  no results in " .. file.path .. (runError and (": " .. tostring(runError)) or ""))
        else
            if wants("sessions") then printSessions(db) end
            if wants("contracts") or sections.detail then printContracts(db, sections.detail) end
            if wants("verdicts") then printVerdicts(db) end
            if wants("snapshot") then printSnapshots(db) end
            if wants("timing") then printTiming(db) end
            if wants("journal") then printJournal(db) end
            if wants("probes") then printProbes(db) end
            if wants("errors") then printErrors(db) end
        end
    end
    print("")
end
