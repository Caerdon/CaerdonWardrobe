-- Reads what the test addon (CaerdonWardrobe_Tests) saved in each client and prints it.
--
--   luajit tools/test-results.lua [--wow DIR] [--file PATH] [section ...]
--
-- The client writes the file on /reload and on logout, so reload before reading. DIR is the
-- folder that holds _retail_ and _forever_; it defaults to $CAERDON_WOW, then to the usual
-- install folders. --file reads one saved variables file instead.
--
-- Sections (all of them when none is named): sessions, contracts, verdicts, snapshot,
-- timing, counters, journal, probes, sources, search, traces, sightings, integrations, rotation, errors. "detail" adds
-- every contract's stored detail, and
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
    return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"))
end

local function figure(value)
    if type(value) == "number" and value ~= math.floor(value) then
        return (("%.3f"):format(value):gsub("0+$", ""):gsub("%.$", ""))
    end
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
            -- A reload writes this file before it can prove itself: the file then holds the
            -- request, and the result only arrives with the next reload or logout.
            local pending = db.pending and db.pending.reload
            local message = result.message and plainText(result.message) or ""
            local final = result.status == "pass" or result.status == "fail" or result.status == "info"
            if pending and not final and id == "reload." .. tostring(pending.how) then
                message = ("asked for at %s, and this file was written by that reload; the result comes with the next save")
                    :format(when(pending.at))
            end
            print(("    %-7s %-34s %s%s"):format(tostring(result.status), id,
                message, result.toon and ("  [" .. result.toon .. "]") or ""))
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
            -- The core's own count of what caused each RefreshItems. It starts with the first
            -- session that had counters, so its sum can be below the RefreshItems line above.
            if events.triggers then
                print("    RefreshItems by what caused it (an event, or the line that asked):")
                for _, name in ipairs(sortedKeys(events.triggers)) do
                    print(("      %-48s %6d  %.2f"):format(name, events.triggers[name], events.triggers[name] / math.max(events.minutes, 0.01)))
                end
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

-- The items of a snapshot that were never drawn, with how far each got.
local function printNeverDrawn(snapshot)
    for _, entry in ipairs(snapshot.entries) do
        if entry.note then
            print(("        never drawn: %s (item %s, container %s slot %s)%s"):format(plainText(entry.link), tostring(entry.itemID),
                tostring(entry.bag), tostring(entry.slot), entry.stuck and (": " .. inline(entry.stuck)) or ""))
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
            printNeverDrawn(store.base)
        end
        if store.last then
            print(("    latest %s  %d items%s, bank %s"):format(when(store.last.at), #store.last.entries,
                (store.last.notDrawn or 0) > 0 and (", %d never drawn"):format(store.last.notDrawn) or "",
                store.last.bank and "included" or "not open"))
            printNeverDrawn(store.last)
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

        -- What every session recorded by itself, each against the session before it.
        local auto = store.auto
        if auto then
            for _, part in ipairs({ "bags", "bank" }) do
                local latest = auto[part]
                if latest then
                    print(("    by itself, %s: last recorded %s, %d items%s"):format(part, when(latest.at), #latest.entries,
                        (latest.notDrawn or 0) > 0 and (", %d never drawn"):format(latest.notDrawn) or ""))
                    printNeverDrawn(latest)
                end
            end
            for _, entry in ipairs(auto.history or {}) do
                local changed = entry.changedCount or #entry.changed
                print(("      %s %s against %s: %d the same, %d changed, %d gone, %d new%s%s"):format(tostring(entry.part),
                    when(entry.after.at), when(entry.base.at), entry.same, changed, #entry.onlyInBase, #entry.onlyInAfter,
                    #entry.settingsChanged > 0 and (", %d settings differ"):format(#entry.settingsChanged) or "",
                    not entry.addonsChanged and ", other addons unknown"
                        or #entry.addonsChanged > 0 and (", %d other addons differ"):format(#entry.addonsChanged) or ""))
                for _, change in ipairs(entry.changed) do
                    print("          " .. plainText(change.link) .. ": " .. tostring(change.summary))
                    if change.why then print("              binding result: " .. inline(change.why)) end
                    if change.transmog then print("              transmog info:  " .. inline(change.transmog)) end
                end
                if changed > #entry.changed then
                    print(("          and %d more"):format(changed - #entry.changed))
                end
                -- What else differs is only worth reading when something changed.
                if changed > 0 then
                    for _, line in ipairs(entry.settingsChanged) do print("          setting: " .. line) end
                    for _, line in ipairs(entry.addonsChanged or {}) do print("          addon: " .. line) end
                end
            end
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

-- The events that came during one timed refresh, with the items an item-data event named.
local function describeEvents(run)
    local events = {}
    for _, name in ipairs(sortedKeys(run.events or {})) do
        local entry = run.events[name]
        local text = ("%s x%d from %s ms"):format(name, entry.count, figure(entry.firstMs))
        if entry.items then
            local items = {}
            for _, item in ipairs(entry.items) do
                items[#items + 1] = tostring(item.id) .. (item.ok == true and "" or (" (" .. tostring(item.ok) .. ")"))
            end
            text = text .. " [items " .. table.concat(items, ", ") .. "]"
        end
        events[#events + 1] = text
    end
    return events
end

-- Refused items as "216679 x4 at 12.3 s": how often the client said no, and when first.
local function describeRefused(items)
    local parts = {}
    for _, item in ipairs(items or {}) do
        local times = (item.info or 0) + (item.load or 0)
        parts[#parts + 1] = ("%s x%d at %s s%s"):format(tostring(item.id), times, figure(item.first),
            (item.duringTests or 0) > 0 and (" (+%d while a test was asking)"):format(item.duringTests) or "")
    end
    return parts
end

-- The core's profile: one line per function, then the queue.
local function printProfile(profile, indent, perRun)
    if type(profile) ~= "table" then
        return
    end
    local divide = perRun and perRun > 0 and perRun or 1
    local unit = divide > 1 and " per refresh" or ""
    print(indent .. ("function: calls%s, ms%s (own: without the listed functions it calls), ms per call, worst call, KB%s (own)")
        :format(unit, unit, unit))
    for _, entry in ipairs(profile.functions or {}) do
        if (entry.calls or 0) > 0 then
            print(indent .. ("  %-36s %7s  %9s (own %9s)  %7s each  worst %7s  %9s KB (own %9s)%s"):format(tostring(entry.label),
                figure(entry.calls / divide), figure(entry.ms / divide), figure(entry.ownMs / divide),
                figure(entry.ms / entry.calls), figure(entry.worstMs), figure(entry.kb / divide), figure(entry.ownKB / divide),
                (entry.collected or 0) > 0 and ("  collector ran in " .. tostring(entry.collected)) or ""))
        end
    end
    for _, name in ipairs(profile.missing or {}) do
        print(indent .. "  NOT FOUND, so not counted: " .. tostring(name))
    end
    local wait = profile.queueWait
    if wait then
        print(indent .. ("wait in the queue: %s draws, mean %s ms, longest %s ms"):format(figure(wait.count), figure(wait.meanMs), figure(wait.worstMs)))
    end
    local drains = profile.drains
    if drains then
        print(indent .. ("drains of the queue: %s, %s passes, %s ms, longest pass %s ms, %s KB"):format(figure(drains.count),
            figure(drains.passes), figure(drains.ms), figure(drains.worstPassMs), figure(drains.kb)))
        for _, done in ipairs(drains.recent or {}) do
            print(indent .. ("  at %s s: %s draws in %s s, %s passes, %s ms, longest pass %s ms, %s KB%s"):format(figure(done.at),
                figure(done.draws), figure(done.seconds), figure(done.passes), figure(done.ms), figure(done.worstPassMs),
                figure(done.kb), (done.collected or 0) > 0 and ("  collector ran in " .. tostring(done.collected) .. " passes") or ""))
        end
    end
end

-- The core's ledger: milestones, what the client was asked to load, refreshes by trigger.
local function printLedger(ledger, indent)
    if type(ledger) ~= "table" then
        return
    end
    local parts = {}
    for _, milestone in ipairs(ledger.milestones or {}) do
        parts[#parts + 1] = ("%s %s"):format(tostring(milestone.name), figure(milestone.seconds))
    end
    print(indent .. "from the addon's first line (s): " .. (#parts > 0 and table.concat(parts, ", ") or "no milestone")
        .. ("; read at %s"):format(figure(ledger.secondsSinceLoad)))
    local refreshes = ledger.refreshes
    if refreshes then
        parts = {}
        for _, name in ipairs(sortedKeys(refreshes.by)) do
            parts[#parts + 1] = ("%s %d"):format(tostring(name), refreshes.by[name])
        end
        print(indent .. ("full refreshes: %s%s"):format(figure(refreshes.total), #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""))
    end
    local loads = ledger.itemLoads
    if loads then
        print(indent .. ("loads asked of the client: %s (%s loaded, %s failed, %s not answered), mean answer %s s, slowest %s s"):format(
            figure(loads.asked), figure(loads.loaded), figure(loads.failed), #(loads.unanswered or {}),
            figure(loads.meanSeconds), figure(loads.slowestSeconds)))
        for _, by in ipairs(sortedKeys(loads.by)) do
            local entry = loads.by[by]
            print(indent .. ("  asked by %s: %s, failed %s"):format(tostring(by), figure(entry.asked), figure(entry.failed)))
        end
        for _, failure in ipairs(loads.failures or {}) do
            print(indent .. ("  FAILED: %s %s x%s, first asked at %s s (%s) by %s, answered after %s s"):format(tostring(failure.kind),
                tostring(failure.id), figure(failure.times), figure(failure.at), tostring(failure.phase),
                tostring(failure.where or failure.by), figure(failure.after)))
        end
        for _, request in ipairs(loads.unanswered or {}) do
            print(indent .. ("  not answered: %s %s, asked at %s s (%s) by %s, %s s before the reading"):format(tostring(request.kind),
                tostring(request.id), figure(request.at), tostring(request.phase), tostring(request.where or request.by),
                figure(request.waiting)))
        end
    end
end

local function printCounters(db)
    if #(db.counters or {}) == 0 then
        return
    end
    print("  The core's counters, as stored by /cwtest counters (newest last):")
    for _, record in ipairs(db.counters) do
        print(("    %s  [%s, %s, addon %s]"):format(when(record.at), tostring(record.toon), tostring(record.build),
            tostring(record.subjectVersion)))
        local report = record.report or {}
        printLedger(report, "      ")
        local profile = report.profile
        if profile and profile.attached then
            print(("      profile %s, figures since %s s:"):format(profile.on and "on" or "off", figure(profile.since)))
            printProfile(profile, "        ")
        else
            print("      profile: never switched on")
        end
    end
end

local function printTiming(db)
    print("  Timing (addon time is the client profiler's, summed per frame):")
    local previous
    for _, record in ipairs(db.timing or {}) do
        printAddonChange(db, previous, record)
        previous = record
        if record.kind == "refresh" then
            print(("    %s  %-8s %-10s x%d  draws %s  addon ms median %s worst %s, longest frame %s  last icon ms %s  first icon ms %s  memory KB %s  [%s, %s, addon %s]")
                :format(when(record.at), "refresh", tostring(record.label), #record.runs, figure(record.medianDraws),
                    figure(record.medianCpuMs), figure(record.worstCpuMs), figure(record.worstFrameMs),
                    figure(record.medianLastDrawMs),
                    figure(record.medianFirstDrawMs), figure(record.medianMemoryKB), tostring(record.toon),
                    tostring(record.build), tostring(record.subjectVersion)))
            local fewest, most = record.fewestDraws, record.mostDraws
            if not fewest then
                for _, run in ipairs(record.runs) do
                    fewest = math.min(fewest or run.draws, run.draws)
                    most = math.max(most or run.draws, run.draws)
                end
            end
            if fewest == most and record.runs[1] and record.runs[1].byFeature then
                local parts = {}
                for _, name in ipairs(sortedKeys(record.runs[1].byFeature)) do
                    parts[#parts + 1] = name .. " " .. record.runs[1].byFeature[name].draws
                end
                local events = describeEvents(record.runs[1])
                print("        drawn per refresh: " .. table.concat(parts, ", ")
                    .. (#events > 0 and ("; events in the first: " .. table.concat(events, ", ")) or ""))
            end
            if fewest ~= most then
                print(("        NOT A CLEAN RUN: the refreshes drew between %d and %d items, so something else was drawing too")
                    :format(fewest, most))
                -- Per refresh: which window drew how much and from when, and which events came.
                for index, run in ipairs(record.runs) do
                    local parts = {}
                    for _, name in ipairs(sortedKeys(run.byFeature or {})) do
                        local entry = run.byFeature[name]
                        parts[#parts + 1] = ("%s %d (%s-%s ms)"):format(name, entry.draws, figure(entry.firstMs), figure(entry.lastMs))
                    end
                    local events = describeEvents(run)
                    print(("          %2d: %d draws%s%s%s"):format(index, run.draws,
                        #parts > 0 and (": " .. table.concat(parts, ", ")) or "",
                        #events > 0 and ("; events: " .. table.concat(events, ", ")) or "",
                        run.tooltip and ("; tooltip on " .. tostring(run.tooltip)) or ""))
                end
            end
            print(("        profiler after: recent %s ms (%s), peak %s ms, session %s ms (%s)%s"):format(
                figure(record.profilerAfter and record.profilerAfter.RecentAverageTime), share(record.profilerAfter, "RecentAverageTime"),
                figure(record.profilerAfter and record.profilerAfter.PeakTime),
                figure(record.profilerAfter and record.profilerAfter.SessionAverageTime), share(record.profilerAfter, "SessionAverageTime"),
                record.refreshItemsCalls ~= #record.runs and ("; " .. tostring(record.refreshItemsCalls) .. " refreshes happened during the " .. #record.runs .. " runs") or ""))
            local counted = record.counted
            if counted then
                print(("        counted, %s more refreshes with the core's profile on (addon ms median %s against %s without, draws %s):")
                    :format(figure(counted.runs), figure(counted.medianCpuMs), figure(record.medianCpuMs), figure(counted.medianDraws)))
                printProfile(counted.profile, "          ", counted.runs)
            end
        elseif record.kind == "idle" then
            print(("    %s  %-8s %ss  addon ms %s (%s per second, worst frame %s)  refreshes per minute %s  draws %s  memory KB %s  [%s, %s]")
                :format(when(record.at), "idle", figure(record.seconds), figure(record.cpuMs), figure(record.cpuMsPerSecond),
                    figure(record.worstFrameMs), figure(record.refreshItemsPerMinute), figure(record.draws),
                    figure(record.memoryKB), tostring(record.toon), tostring(record.build)))
            print("        events: " .. inline(record.counts))
            if record.refreshTriggers and next(record.refreshTriggers) then
                print("        refreshes by what caused them: " .. inline(record.refreshTriggers))
            end
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
        local refused = record.refusedItems
        if refused and refused.distinct > 0 then
            print(("        the client refused %d item%s by then (seconds after the tests' load; any addon may have asked): %s%s")
                :format(refused.distinct, refused.distinct == 1 and "" or "s", table.concat(describeRefused(refused.items), ", "),
                    refused.distinct > #refused.items and ", ..." or ""))
        end
        printLedger(record.core, "        ")
        if record.debugOn then
            print("        Enable debug was on during this login: it adds work to every draw")
        end
        if record.profile then
            print("        profiled from the tests' load (asked for with /cwtest counters login):")
            printProfile(record.profile, "          ")
        end
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

local function printSources(db)
    for _, toon in ipairs(sortedKeys(db.sources)) do
        local record = db.sources[toon]
        print(("  Appearance sources, %s (%s, build %s):"):format(toon, when(record.at), tostring(record.build)))
        print(("    %s items looked at (drawn this session or equipped), %s with an appearance (%s of them found by trying the item on); %s appearances, %s sources from %s items")
            :format(figure(record.itemsLooked), figure(record.itemsWithAppearance), figure(record.itemsTriedOn),
                figure(record.appearances), figure(record.sources), figure(record.sourceItems)))
        local refused = record.refused
        if refused and refused.distinct > 0 then
            print(("    refused by the client before the probe (seconds after the tests' load): %s%s"):format(
                table.concat(describeRefused(refused.items), ", "), refused.distinct > #refused.items and ", ..." or ""))
        else
            print("    the client had refused no item before the probe")
        end
        if #(record.unexplained or {}) > 0 then
            print("    refused, and no drawn item's appearance leads there: " .. inline(record.unexplained))
        end
        if #(record.sourcesWithoutItem or {}) > 0 then
            print("    sources without an item ID: " .. inline(record.sourcesWithoutItem))
        end
        print(("    source items the client has no data for: %s%s"):format(figure(record.missingCount),
            (record.missingCount or 0) > #(record.missing or {}) and (", the first %d listed"):format(#record.missing) or ""))
        for _, entry in ipairs(record.missing or {}) do
            local sources = {}
            for _, sourceID in ipairs(sortedKeys(entry.sources)) do
                sources[#sources + 1] = ("%s of appearance %s"):format(tostring(sourceID), tostring(entry.sources[sourceID]))
            end
            print(("      item %s: exists %s, cached %s, refused %s times before, the addon %s; source %s"):format(
                tostring(entry.itemID), tostring(entry.exists), tostring(entry.cached), figure(entry.refusedBefore),
                entry.addonGaveUp and "stopped loading it" or "has not marked it as failed", table.concat(sources, ", ")))
            for _, owner in ipairs(entry.owners or {}) do
                print(("          reached from %s (item %s), drawn by %s%s"):format(plainText(owner.link), tostring(owner.itemID),
                    tostring(owner.drawnBy), owner.triedOn and "; its look is not in the collection, the addon found it by trying the item on" or ""))
            end
            if (entry.ownerCount or 0) > #(entry.owners or {}) then
                print(("          and %d more"):format(entry.ownerCount - #entry.owners))
            end
            for _, step in ipairs(entry.steps or {}) do
                local events = {}
                for _, name in ipairs(sortedKeys(step.events or {})) do
                    local seen = step.events[name]
                    events[#events + 1] = ("%s x%d (%s) after %s ms"):format(name, seen.count,
                        seen.ok and "loaded" or "refused", figure(seen.afterMs))
                end
                print(("          %-36s returned %-28s %s%s"):format(step.call, plainText(step.returned),
                    #events > 0 and ("then " .. table.concat(events, ", ")) or "no answer",
                    ((step.draws or 0) > 0 or (step.refreshes or 0) > 0)
                        and (" [the addon drew %d and refreshed %d meanwhile: not clean]"):format(step.draws, step.refreshes) or ""))
            end
            if entry.steps then
                print(("          asked for by: %s; cached afterwards: %s"):format(
                    #entry.askedBy > 0 and table.concat(entry.askedBy, ", ") or "none of the calls tried", tostring(entry.cachedAfter)))
            end
        end
    end
end

local function printSearch(db)
    for _, toon in ipairs(sortedKeys(db.search)) do
        local record = db.search[toon]
        print(("  Items found for the verdict tests, %s (%s; %s, build %s):"):format(toon, tostring(record.sig), when(record.at),
            tostring(record.build)))
        print(("    %s of %s appearances looked at, %s items asked for, %s did not load, %s s; stopped because: %s"):format(
            figure(record.appearancesLooked), figure(record.appearancesKnown), figure(record.itemsAsked),
            figure(record.itemsNotLoaded), figure(record.seconds), tostring(record.stoppedBy)))
        for _, id in ipairs(sortedKeys(record.tests)) do
            local test = record.tests[id]
            print(("    %s: %d items; the test expects %s"):format(id, #test.found,
                #test.expected > 0 and table.concat(test.expected, " / ") or "nothing yet (no kind of toon defined)"))
            print("        shape: " .. inline(test.shape))
            for _, found in ipairs(test.found) do
                local facts = found.facts or {}
                print(("        item %-7s %-34s addon says %-10s %s, class %s/%s, level %s, item level %s, bind %s, appearance %s, usable %s"):format(
                    tostring(found.itemID), "[" .. tostring(facts.name) .. "]", tostring(found.status), tostring(facts.equipLoc),
                    tostring(facts.classID), tostring(facts.subClassID), tostring(facts.minLevel), tostring(facts.itemLevel),
                    tostring(facts.bindType), tostring(facts.appearanceID), tostring(facts.canUse)))
            end
        end
    end
end

local function printTraces(db)
    local traces = db.traces
    if not traces or not traces.ids then
        return
    end
    print(("  Who asked for items %s (%s, %s, build %s; %s functions hooked for %s s):"):format(inline(traces.ids),
        tostring(traces.toon), when(traces.started), tostring(traces.build), figure(traces.hooked), figure(traces.seconds)))
    local refusedBy = {}
    for _, item in ipairs(traces.refused and traces.refused.items or {}) do refusedBy[item.id] = item end
    for _, itemID in ipairs(traces.ids) do
        local item = refusedBy[itemID]
        local calls = 0
        for _, call in ipairs(traces.calls or {}) do
            if call.id == itemID then calls = calls + call.count end
        end
        print(("    item %s: %s; %d calls seen that name it"):format(tostring(itemID),
            item and ("refused %d times (item info %d, load %d), first %s s after the tests' load"):format(
                item.info + item.load + item.duringTests, item.info, item.load, figure(item.first)) or "not refused this session",
            calls))
        for _, call in ipairs(traces.calls or {}) do
            if call.id == itemID then
                print(("        x%d %s at %s s, called from: %s%s"):format(call.count, tostring(call.fn), figure(call.first),
                    #(call.addons or {}) > 0 and table.concat(call.addons, " < ") or "(no addon on the stack)",
                    call.during and (", while drawing %s for %s"):format(plainText(call.during), tostring(call.drawnBy)) or ""))
                local shown = 0
                for line in tostring(call.stack):gmatch("[^\n]+") do
                    if shown < 7 and not line:find("CaerdonWardrobe_Tests", 1, true) then
                        shown = shown + 1
                        print("            " .. line:sub(1, 150))
                    end
                end
            end
        end
    end
    if traces.more then
        print(("    and %d more distinct calls than are kept"):format(traces.more))
    end
end

-- Bag states that were checked when an item showed one. A case nobody has carried an item for
-- is listed as not seen: that is the coverage.
local SIGHTING_CASES = { "openable", "locked", "readable", "refundable", "soulbound", "bindOnEquip", "accountBindType" }

local function printSightings(db)
    local sightings = db.sightings or {}
    print("  Bag states (checked when an item showed one):")
    local listed = {}
    local function printCase(case)
        listed[case] = true
        local records = sightings[case] or {}
        local keys = sortedKeys(records)
        if #keys == 0 then
            print(("    %-16s not seen yet"):format(case))
            return
        end
        local counts = {}
        for _, key in ipairs(keys) do
            counts[records[key].result] = (counts[records[key].result] or 0) + 1
        end
        print(("    %-16s %d items: %s"):format(case, #keys, inline(counts)))
        table.sort(keys, function(a, b) return (records[a].at or 0) > (records[b].at or 0) end)
        for _, key in ipairs(keys) do
            local record = records[key]
            print(("      %-8s %s  status %s, binding %s  (%s, %s, bag %s slot %s, addon %s)%s"):format(
                tostring(record.result), plainText(record.link or key), tostring(record.status),
                tostring(record.binding), when(record.at), tostring(record.toon), tostring(record.bag),
                tostring(record.slot), tostring(record.subjectVersion),
                record.message and ("\n          " .. record.message) or ""))
            if record.linkStatus ~= nil then
                print(("          the bare link alone, asked first: status %s"):format(
                    record.linkStatus == "" and "(none)" or tostring(record.linkStatus)))
            end
            if record.result ~= "pass" or sections.sightings then
                print("          facts:   " .. inline(record.facts or {}))
                if record.why then print("          binding: " .. inline(record.why)) end
            end
            if record.previous then
                print(("          before:  %s, status %s, binding %s (%s, addon %s)"):format(
                    tostring(record.previous.result), tostring(record.previous.status),
                    tostring(record.previous.binding), when(record.previous.at),
                    tostring(record.previous.subjectVersion)))
            end
            for index, line in ipairs(record.tooltip or {}) do
                print(("          line %2d: %s"):format(index, inline(line)))
            end
        end
    end
    for _, case in ipairs(SIGHTING_CASES) do
        printCase(case)
    end
    for _, case in ipairs(sortedKeys(sightings)) do
        if not listed[case] then
            printCase(case)
        end
    end
end

-- Per integration and version of the other addon: whether its hook points were found, over
-- every session recorded with that version.
local function printIntegrations(db)
    local integrations = db.integrations or {}
    local features = sortedKeys(integrations)
    if #features == 0 then
        print("  Integrations: none recorded (a record is written at the end of a session)")
        return
    end
    print("  Integrations (hook points over the sessions recorded per version of the other addon):")
    for _, feature in ipairs(features) do
        local versions = integrations[feature]
        local keys = sortedKeys(versions)
        table.sort(keys, function(a, b) return (versions[a].at or 0) > (versions[b].at or 0) end)
        for _, version in ipairs(keys) do
            local record = versions[version]
            local found, needed = 0, 0
            for _, label in ipairs(sortedKeys(record.points)) do
                local point = record.points[label]
                if not point.optional and not point.undeclared then
                    needed = needed + 1
                    if point.found > 0 then found = found + 1 end
                end
            end
            print(("    %-8s %s (%s %s): %d of %d hook points found, %d draws in %d sessions  (last %s, %s, addon %s)"):format(
                tostring(record.verdict), feature, tostring(record.addon), tostring(version), found, needed,
                record.draws or 0, record.sessions or 0, when(record.at), tostring(record.toon),
                tostring(record.subjectVersion)))
            if not record.initFinished then
                print("        its Init did not finish in the last session")
            end
            for _, label in ipairs(sortedKeys(record.points)) do
                local point = record.points[label]
                if point.found == 0 or point.undeclared or sections.integrations then
                    print(("        %s%s%s: found in %d sessions, missing in %d, not reached in %d"):format(label,
                        point.optional and " (optional)" or "", point.undeclared and " (not declared)" or "",
                        point.found, point.missing, point.notReached))
                end
            end
        end
    end
end

-- The bag addon rotation: the run in progress, the finished runs, the last check outside a run.
local function printRotationStop(record, indent)
    local title = tostring(record.stop)
    if record.isAddon and record.version and record.version ~= "" then
        title = title .. " " .. record.version
    end
    print(("%s%-8s %s: %d buttons checked, %d as the addon draws them  (%s%s)"):format(indent, tostring(record.verdict),
        title, record.checked or 0, record.same or 0, when(record.at), record.forced and ", asked for with Check now" or ""))
    if (record.checked or 0) > 0 then
        print(("%s    drawn again by the refresh: %d, picture read on %d, slot named by %d buttons; %d of %d filled slots on screen"):format(
            indent, (record.checked or 0) - (record.notRedrawn or 0), record.picturesRead or 0, record.slotsNamed or 0,
            (record.slotsFilled or 0) - (record.notShownCount or 0), record.slotsFilled or 0))
    end
    for _, name in ipairs(sortedKeys(record.features)) do
        local feature = record.features[name]
        print(("%s    drawn by %s%s: %d visible buttons, %d not visible%s"):format(indent, name,
            feature.expected and "" or " (not this stop's feature)", feature.visible or 0, feature.hidden or 0,
            feature.requests and ("; this session %d requests (%d for an empty slot), %d draws"):format(feature.requests,
                feature.emptyRequests or 0, feature.draws or 0) or ""))
    end
    for _, entry in ipairs(record.integrations or {}) do
        print(("%s    integration %s: %s, %s"):format(indent, tostring(entry.feature), tostring(entry.verdict),
            tostring(entry.summary)))
    end
    for _, reason in ipairs(record.reasons or {}) do
        print(indent .. (record.verdict == "fail" and "    FAIL: " or "    ") .. plainText(reason))
    end
    for _, problem in ipairs(record.problems or {}) do
        print(("%s      %s (bag %s slot %s, %s): %s"):format(indent, plainText(problem.link), tostring(problem.bag),
            tostring(problem.slot), tostring(problem.feature), plainText(problem.what)))
    end
    for _, note in ipairs(record.notes or {}) do
        -- An integration that is waiting has its own line above.
        if not note:find("^integration ") then
            print(indent .. "    note: " .. plainText(note))
        end
    end
    if sections.rotation and record.notShown and #record.notShown > 0 then
        local links = {}
        for index, link in ipairs(record.notShown) do links[index] = plainText(link) end
        print(indent .. "    no visible button for: " .. table.concat(links, ", "))
    end
end

local function printRotationRun(run, indent)
    for index, stop in ipairs(run.stops or {}) do
        local record = run.results and run.results[stop]
        if record then
            printRotationStop(record, indent)
        else
            print(("%s%-8s %s"):format(indent, index == run.index and "here" or "to come", tostring(stop)))
        end
    end
end

local function printRotation(db)
    local rotation = db.rotation or {}
    local history = rotation.history or {}
    if not rotation.run and #history == 0 and not rotation.single then
        print("  Rotation: never run (/cwtest rotation start)")
        return
    end
    print("  Rotation (every installed bag addon in turn; each visible bag button against what the addon draws for its slot):")
    if rotation.run then
        local run = rotation.run
        print(("    In progress on %s since %s, addon %s: stop %s of %d, phase %s"):format(tostring(run.toon),
            when(run.startedAt), tostring(run.subjectVersion), tostring(run.index), #(run.stops or {}), tostring(run.phase)))
        printRotationRun(run, "      ")
    end
    for index = #history, 1, -1 do
        local run = history[index]
        print(("    %s %s on %s, addon %s, build %s, started %s"):format(run.aborted and "Stopped early" or "Finished",
            when(run.finishedAt), tostring(run.toon), tostring(run.subjectVersion), tostring(run.build), when(run.startedAt)))
        printRotationRun(run, "      ")
        if run.comparedWith then
            print(("      against the run of %s (addon %s): %d things shown differently"):format(when(run.comparedWith.at),
                tostring(run.comparedWith.subjectVersion), run.changeCount or 0))
            for _, change in ipairs(run.changes or {}) do
                print(("        %s: %s %s"):format(tostring(change.stop), plainText(change.link or ""), plainText(change.summary)))
            end
        end
    end
    if rotation.single then
        print("    Last check outside a run:")
        printRotationStop(rotation.single, "      ")
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
            if wants("counters") then printCounters(db) end
            if wants("journal") then printJournal(db) end
            if wants("probes") then printProbes(db) end
            if wants("sources") then printSources(db) end
            if wants("search") then printSearch(db) end
            if wants("traces") then printTraces(db) end
            if wants("sightings") then printSightings(db) end
            if wants("integrations") then printIntegrations(db) end
            if wants("rotation") then printRotation(db) end
            if wants("errors") then printErrors(db) end
        end
    end
    print("")
end
