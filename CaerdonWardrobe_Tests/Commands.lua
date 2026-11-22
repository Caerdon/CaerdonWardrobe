-- /cwtest and its small window, and what happens by itself after login.

local _, T = ...

------------------------------------------------------------------------------------------
-- After login
------------------------------------------------------------------------------------------

-- Called once the login record is written, which is when the addon's queue is first empty.
function T.AfterLogin()
    local plan = T.GetPlan()
    for id, reason in pairs(plan.skip) do
        local def = T.GetTest(id)
        if def then
            def.auto = false
            def.skipReason = reason
        end
    end
    if #plan.probeItems > 0 then
        T.ProbeItems(plan.probeItems, true)
    end
    if plan.autoRun then
        T.RunTests({ quiet = true })
    end
    if #plan.recordItems > 0 then
        T.RecordPlanItems(plan.recordItems)
    end
    T.CheckIntegrations()
    -- From here on the bags are read whenever they change (Sightings.lua).
    T.ScanSightings()
    -- A rotation that this reload is a step of goes on (Rotation.lua).
    T.ResumeRotation()
    -- What the bags show now against the last session, and the bank when it is opened
    -- (Snapshot.lua). After the rotation has said whether a run is on: none is taken at a stop.
    T.StartAutoSnapshots()
end

------------------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------------------

local window

local function StatusText()
    local counts = {}
    for _, row in ipairs(T.GetStatusRows()) do
        counts[row.status] = (counts[row.status] or 0) + 1
    end
    local client, toon = T.GetClient(), T.GetToon()
    local lines = {
        ("%s %s"):format(client.flavor, client.build),
        ("%s (%s)"):format(toon.key, toon.signature),
        "",
    }
    local parts = {}
    for _, status in ipairs({ "pass", "info", "fail", "regression", "uncovered", "skip", "manual", "error" }) do
        if counts[status] then
            parts[#parts + 1] = ("%d %s"):format(counts[status], T.ColorStatus(status))
        end
    end
    lines[#lines + 1] = "Tests: " .. (#parts > 0 and table.concat(parts, ", ") or "none")

    local store = T.db.snapshots[toon.key]
    if store and store.diff then
        lines[#lines + 1] = ("Snapshot against the base: %d the same, %d changed"):format(store.diff.same,
            #store.diff.changed)
    elseif store and store.base then
        lines[#lines + 1] = ("Snapshot: base of %d items, nothing compared yet"):format(#store.base.entries)
    else
        lines[#lines + 1] = "Snapshot: no base yet"
    end

    local seen, disagree = 0, 0
    local sightingRows = T.GetSightingRows()
    for _, row in ipairs(sightingRows) do
        seen = seen + (row.items > 0 and 1 or 0)
        disagree = disagree + row.mismatch
    end
    lines[#lines + 1] = ("Bag states: %d of %d seen%s"):format(seen, #sightingRows,
        disagree > 0 and (", |cffff4040%d items disagree|r"):format(disagree) or "")

    local rotation = T.RotationStatusLine()
    if rotation then
        lines[#lines + 1] = rotation
    end

    local last = T.db.timing[#T.db.timing]
    if last then
        lines[#lines + 1] = ("Last timing: %s, addon time %s ms"):format(tostring(last.label),
            tostring(last.medianCpuMs or last.cpuMs))
    end
    if T.IsBusy() then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Working: " .. tostring(T.ActiveJob() or "queued")
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cffaaaaaaResults are written to disk on a reload or logout.|r"
    return table.concat(lines, "\n")
end

local function AddButton(parent, text, column, row, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(190, 24)
    button:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 16 + (column - 1) * 198, 14 + (row - 1) * 28)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function CreateWindow()
    window = CreateFrame("Frame", "CaerdonWardrobeTestsWindow", UIParent, "BasicFrameTemplateWithInset")
    window:SetSize(428, 388)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    if window.TitleText then
        window.TitleText:SetText("Caerdon Wardrobe Tests")
    end
    tinsert(UISpecialFrames, "CaerdonWardrobeTestsWindow")

    window.status = window:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    window.status:SetPoint("TOPLEFT", 18, -36)
    window.status:SetPoint("RIGHT", -18, 0)
    window.status:SetJustifyH("LEFT")
    window.status:SetJustifyV("TOP")

    AddButton(window, "Bag addon rotation...", 1, 5, function() T.ShowRotationPanel() end)
    AddButton(window, "Run tests", 1, 4, function() T.RunTests() end)
    AddButton(window, "Run every test again", 2, 4, function() T.RunTests({ force = true }) end)
    AddButton(window, "Snapshot: set the base", 1, 3, function() T.TakeSnapshot(true) end)
    AddButton(window, "Snapshot: compare", 2, 3, function() T.TakeSnapshot(false) end)
    AddButton(window, "Time a refresh", 1, 2, function() T.RunRefreshTiming("refresh") end)
    AddButton(window, "Time standing idle", 2, 2, function() T.RunIdleTiming() end)
    AddButton(window, "List what needs a look", 1, 1, function() T.PrintStatus() end)
    -- The click behind this call is the point: it is the "reload.click" contract.
    AddButton(window, "Save results (reload)", 2, 1, function() T.RequestReload("click") end)

    window:SetScript("OnShow", function() window.status:SetText(StatusText()) end)
    window:Hide()
end

local function RefreshWindow()
    if window and window:IsShown() then
        window.status:SetText(StatusText())
    end
end

T.OnTestsFinished = RefreshWindow

local function ToggleWindow()
    if not window then
        CreateWindow()
    end
    window:SetShown(not window:IsShown())
end

------------------------------------------------------------------------------------------
-- /cwtest
------------------------------------------------------------------------------------------

local HELP = {
    "/cwtest - the window",
    "/cwtest status - every test with its result",
    "/cwtest run [all | text] - run what has to run; all of them again; or those whose id contains the text",
    "/cwtest snapshot [base] - record what is drawn for the bags (and the bank when open); compare with the base",
    "/cwtest timing <label> [runs] - time forced refreshes with the windows that are open now",
    "/cwtest timing <label> worn | collection - the same, each refresh saying that only this changed",
    "/cwtest timing idle [seconds] - time standing still",
    "/cwtest timing open - with the bags closed: one refresh, then open the bags when told; times what the opening draws",
    "/cwtest probe <item ID> ... - record everything about some items",
    "/cwtest cache - measure what makes item data leave the client's cache (a minute and a half, standing still, bags closed)",
    "/cwtest cache evict - load other items until the worn pieces' data has left the cache, and leave it so",
    "/cwtest record <item ID or link> ... | slot <bag> <slot> | bags | list | clear - record the client's answers behind a verdict, for the offline harness",
    "/cwtest sources - appearance sources of what was drawn this session whose item the client does not have",
    "/cwtest search [count] - find items that fit the verdict tests on this toon, for their pools",
    "/cwtest teaches [restart] - what every Consumable and Recipe teaches by its tooltip (four minutes a run, standing still, bags closed; again to go on)",
    "/cwtest sightings - bag states (openable, locked, refundable, bound) checked when an item showed one",
    "/cwtest integrations - whether each integration found the places it hooks in the other addon",
    "/cwtest counters [on | off | reset | login] - the core's own counters: print and store them; its profile on or off; profile the next login",
    "/cwtest rotation - the panel that takes every installed bag addon in turn, one per reload",
    "/cwtest rotation status | start [addon ...] | next | skip | check | abort - the same, typed",
    "/cwtest coverage - verdict tests per kind of toon",
    "/cwtest journal [count] - the last things this account learned",
    "/cwtest reload [timer] - save the results by reloading",
    "/cwtest reset - forget every result",
}

local function PrintCoverage()
    T.Print("verdict tests per kind of toon:")
    for _, row in ipairs(T.GetCoverage()) do
        print(("  %s  %s [%s]%s"):format(T.ColorStatus(row.state), row.id, row.kind,
            row.toon and (" on " .. row.toon) or ""))
    end
end

local function PrintJournal(count)
    local journal = T.db.journal
    T.Print("%d journal entries; the last %d:", #journal, math.min(count, #journal))
    for index = math.max(1, #journal - count + 1), #journal do
        local entry = journal[index]
        local what = entry.what or {}
        print(("  %s %s %s (%s): %s"):format(date("%m-%d %H:%M", entry.at), entry.event,
            tostring(what.name or what.itemID or what.sourceID or what.recipeID or what.mountID or what.level or ""),
            entry.toon, tostring(entry.likely or "...")))
    end
end

local COMMANDS = {}

COMMANDS[""] = function()
    ToggleWindow()
end

COMMANDS.status = function()
    T.PrintStatus(true)
end

COMMANDS.run = function(rest)
    if rest == "all" then
        T.RunTests({ force = true })
    elseif rest ~= "" then
        T.RunTests({ force = true, match = rest })
    else
        T.RunTests()
    end
end

COMMANDS.snapshot = function(rest)
    T.TakeSnapshot(rest == "base")
end

COMMANDS.timing = function(rest)
    local label, amount = rest:match("^(%S+)%s*(%d*)$")
    -- A refresh that says what changed: /cwtest timing bags worn
    local changed
    if not label then
        label, changed = rest:match("^(%S+)%s+(%a+)$")
        if changed ~= "worn" and changed ~= "collection" then
            label, changed = nil, nil
        end
    end
    if not label then
        T.Print("say what is open: /cwtest timing bags, /cwtest timing bank, /cwtest timing vendor, /cwtest timing idle; or /cwtest timing open with the bags closed")
    elseif label == "idle" then
        T.RunIdleTiming(tonumber(amount))
    elseif label == "open" then
        T.RunOpenTiming("bags")
    else
        T.RunRefreshTiming(label, tonumber(amount), changed)
    end
end

COMMANDS.probe = function(rest)
    local itemIDs = {}
    for itemID in rest:gmatch("item:(%d+)") do
        itemIDs[#itemIDs + 1] = tonumber(itemID)
    end
    if #itemIDs == 0 then
        for itemID in rest:gmatch("%d+") do
            itemIDs[#itemIDs + 1] = tonumber(itemID)
        end
    end
    if #itemIDs == 0 then
        T.Print("give item IDs or links: /cwtest probe 2969 6550")
    else
        T.ProbeItems(itemIDs)
    end
end

COMMANDS.cache = function(rest)
    T.ItemCacheCommand(rest)
end

COMMANDS.record = function(rest)
    T.RecordCommand(rest)
end

COMMANDS.sources = function()
    T.ProbeSources()
end

COMMANDS.search = function(rest)
    T.SearchPoolItems(tonumber(rest))
end

COMMANDS.teaches = function(rest)
    T.TeachesCommand(rest)
end

COMMANDS.sightings = function()
    T.PrintSightings()
    T.ScanSightings()
end

COMMANDS.integrations = function()
    T.PrintIntegrations()
end

COMMANDS.counters = function(rest)
    T.CountersCommand(rest)
end

COMMANDS.rotation = function(rest)
    T.RotationCommand(rest, "slash")
end

COMMANDS.coverage = PrintCoverage

COMMANDS.journal = function(rest)
    PrintJournal(tonumber(rest) or 10)
end

COMMANDS.reload = function(rest)
    if rest == "timer" then
        T.Print("reloading in a second, with no click or key press behind the call...")
        C_Timer.After(1, function() T.RequestReload("timer") end)
    else
        T.RequestReload("slash")
    end
end

COMMANDS.reset = function()
    CaerdonWardrobeTestsDB = nil
    T.Print("every result will be forgotten at the next reload.")
end

COMMANDS.help = function()
    for _, line in ipairs(HELP) do
        print(line)
    end
end

SLASH_CAERDONTESTS1 = "/cwtest"
SlashCmdList["CAERDONTESTS"] = function(message)
    local command, rest = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local handler = COMMANDS[string.lower(command)]
    if not handler then
        handler = COMMANDS.help
    end
    handler(rest)
    RefreshWindow()
end
