-- The test addon's bag addon rotation against a mocked client under LuaJIT.
--   luajit tools/harness/standalone/rotation.lua [repo dir]
-- tools/harness/run.lua runs it with the scenarios. It is older than the harness' shared
-- client and brings a small one of its own, which can simulate a reload.
-- Two guards make LuaJIT as strict as the client's Lua 5.1: no yield inside pcall or a secure
-- hook, and %s only for strings and numbers.

local ROOT = (arg[1] or ".") .. "/CaerdonWardrobe_Tests"
local realPcall, realYield, realFormat, realPrint = pcall, coroutine.yield, string.format, print

------------------------------------------------------------------------------------------
-- Guards
------------------------------------------------------------------------------------------

local depth = setmetatable({}, { __mode = "k" })
local function Guarded(f, ...)
    local co = coroutine.running() or "main"
    depth[co] = (depth[co] or 0) + 1
    local results = { realPcall(f, ...) }
    depth[co] = depth[co] - 1
    return unpack(results, 1, table.maxn(results))
end
pcall = Guarded
xpcall = function(f, handler, ...)
    local args = { n = select("#", ...), ... }
    local results = { Guarded(function() return f(unpack(args, 1, args.n)) end) }
    if not results[1] then
        handler(results[2])
    end
    return unpack(results, 1, table.maxn(results))
end
coroutine.yield = function(...)
    if (depth[coroutine.running()] or 0) > 0 then
        error("GUARD: yield inside pcall or a secure hook", 2)
    end
    return realYield(...)
end
string.format = function(fmt, ...)
    local index = 0
    for spec in fmt:gmatch("%%[%-+ #0]*%d*%.?%d*([%a%%])") do
        if spec ~= "%" then
            index = index + 1
            if spec == "s" then
                local kind = type((select(index, ...)))
                if kind ~= "string" and kind ~= "number" then
                    error("GUARD: %s given a " .. kind .. " in: " .. fmt, 2)
                end
            end
        end
    end
    return realFormat(fmt, ...)
end

------------------------------------------------------------------------------------------
-- Checks
------------------------------------------------------------------------------------------

local checks, failures = 0, 0
local output = {}
local function Check(condition, label)
    checks = checks + 1
    if not condition then
        failures = failures + 1
        realPrint("  FAILED: " .. label)
    end
end
local function Said(text)
    for _, line in ipairs(output) do
        if line:find(text, 1, true) then return true end
    end
    return false
end
local VERBOSE = os.getenv("MOCK_VERBOSE")
print = function(...)
    local parts = {}
    for index = 1, select("#", ...) do parts[index] = tostring((select(index, ...))) end
    local line = table.concat(parts, " ")
    output[#output + 1] = line
    if VERBOSE then realPrint("    | " .. line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
end

------------------------------------------------------------------------------------------
-- The world that survives a reload
------------------------------------------------------------------------------------------

local world = {
    now = 1000,
    guid = "Player-1",
    toon = "Tester",
    saved = nil, -- CaerdonWardrobeTestsDB
    addons = {
        -- name -> { deps, loads = function(world) }
        { name = "CaerdonWardrobe", version = "5.0.0" },
        { name = "CaerdonWardrobe_Tests", version = "1" },
        { name = "Pawn", version = "2.1" },
        { name = "BetterBags", version = "0.9.3" },
        { name = "LiteBag", version = "11", broken = "INTERFACE_VERSION" },
        { name = "Sorted", version = "3", deps = { "SortedLib" } },
        { name = "SortedLib", version = "1" },
    },
    enabled = { -- guid -> name -> bool
        ["Player-1"] = { CaerdonWardrobe = true, CaerdonWardrobe_Tests = true, Pawn = true, BetterBags = true },
        ["Player-2"] = { CaerdonWardrobe = true, CaerdonWardrobe_Tests = true, Pawn = true, BetterBags = true },
    },
    saves = 0,
    bags = {},
    sortedFaults = true,
}
local function AddonByName(name)
    for index, addon in ipairs(world.addons) do
        if addon.name == name or index == name then return addon end
    end
end
for bag = 0, 5 do world.bags[bag] = {} end
local function Put(bag, slot, itemID, status, binding, bound)
    world.bags[bag][slot] = {
        itemID = itemID, iconFileID = 130000 + itemID, stackCount = 1, isBound = bound or false,
        hyperlink = ("|cffffffff|Hitem:%d::::::::20:::::|h[Item %d]|h|r"):format(itemID, itemID),
        status = status, binding = binding,
    }
end
Put(0, 1, 101, "own", "BoE")
Put(0, 2, 102, "sellable")
Put(0, 4, 103, "collected")
Put(1, 1, 104, "other", "BoE")
Put(1, 3, 105, "quest", nil, true)
Put(5, 1, 106, "auctionGoods")
local SLOTS = { [0] = 4, 4, 0, 0, 0, 2 }

------------------------------------------------------------------------------------------
-- One session of the UI
------------------------------------------------------------------------------------------

local session

local function NewWidget(kind, parent)
    local widget = { kind = kind, parent = parent, shown = true, scripts = {}, events = {} }
    function widget:SetSize(w, h) self.width, self.height = w, h end
    function widget:GetWidth() return self.width or 0 end
    function widget:SetPoint() end
    function widget:SetAllPoints() end
    function widget:Hide() self.shown = false end
    function widget:Show() self.shown = true end
    function widget:SetShown(shown) self.shown = shown and true or false end
    function widget:IsShown() return self.shown end
    function widget:IsVisible()
        local current = self
        while current do
            if not current.shown then return false end
            current = current.parent
        end
        return true
    end
    function widget:SetScript(name, fn) self.scripts[name] = fn end
    function widget:GetScript(name) return self.scripts[name] end
    function widget:RegisterEvent(event) self.events[event] = true end
    function widget:CreateTexture() return NewWidget("Texture", self) end
    function widget:CreateFontString()
        local text = NewWidget("FontString", self)
        function text:SetText(value) self.text = value end
        function text:GetText() return self.text end
        function text:SetJustifyH() end
        function text:SetJustifyV() end
        return text
    end
    function widget:SetFrameStrata() end
    function widget:SetMovable() end
    function widget:EnableMouse() end
    function widget:RegisterForDrag() end
    function widget:SetText(value) self.text = value end
    function widget:GetText() return self.text end
    function widget:SetEnabled(enabled) self.enabled = enabled and true or false end
    function widget:IsEnabled() return self.enabled ~= false end
    session.widgets[#session.widgets + 1] = widget
    return widget
end

local function FireEvent(event, ...)
    for _, widget in ipairs(session.widgets) do
        if widget.events[event] and widget.scripts.OnEvent then
            widget.scripts.OnEvent(widget, event, ...)
        end
    end
end

-- The addon's core, as far as the tests touch it.
local function NewCore()
    local core = {
        waitingToProcess = {}, featureProcessItems = {}, pendingTooltipRetries = {},
        refreshGeneration = 1, features = {}, overlays = setmetatable({}, { __mode = "k" }),
        generations = setmetatable({}, { __mode = "k" }), draws = 0,
    }
    function core:GetFeature(name) return self.features[name] end
    function core:GetRegisteredFeatures() return self.features end
    function core:GetCaerdonButton(button) return self.overlays[button] end
    function core:GetRefreshGeneration() return self.refreshGeneration end
    function core:GetButtonRefreshGeneration(button) return self.generations[button] end
    function core:ClearButtonState(button) self.generations[button] = nil end
    function core:ClearButton(button)
        local overlay = self.overlays[button]
        if overlay then overlay.has = {} end
    end
    function core:GetDrawnParts(button)
        local overlay = self.overlays[button]
        if not overlay then return false, false, false end
        return overlay.has.icon == true, overlay.has.text == true, false
    end
    function core:UpdateButton(button, item, feature, locationInfo, options)
        assert(type(options) == "table", "options")
        local key = feature:GetName() .. "-" .. locationInfo.bag .. "-" .. locationInfo.slot
        self.waitingToProcess[key] = { button, item, feature, locationInfo, options }
    end
    function core:ProcessItem(button, item, feature, locationInfo, options)
        self.draws = self.draws + 1
        local _, status, binding = item:GetCaerdonStatus(feature, locationInfo)
        local overlay = self.overlays[button]
        if not overlay then
            overlay = { has = {} }
            local icon = {}
            function icon:GetAtlas() return overlay.atlas end
            function icon:GetTexture() return nil end
            function icon:GetVertexColor() return 1, 1, 1 end
            function icon:GetAlpha() return 1 end
            function icon:GetWidth() return options.statusProminentSize or 20 end
            function icon:GetPoint() return "TOPLEFT", nil, nil, 0, 0 end
            function icon:IsDesaturated() return false end
            overlay.mogStatus = icon
            overlay.bindsOnText = { GetText = function() return overlay.text end }
            self.overlays[button] = overlay
        end
        overlay.has = { icon = status ~= "collected", text = binding ~= nil }
        overlay.atlas = "icon-" .. tostring(status)
        overlay.text = binding
        self.generations[button] = self.refreshGeneration
        if feature.OnButtonDrawn then
            feature:OnButtonDrawn(button, item, locationInfo, options)
        end
    end
    function core:RefreshItems()
        self.refreshGeneration = self.refreshGeneration + 1
        session.After(0.1, function()
            for _, feature in pairs(self.features) do
                if feature.Refresh then feature:Refresh() end
            end
        end)
    end
    function core:Step()
        local waiting = self.waitingToProcess
        self.waitingToProcess = {}
        for _, request in pairs(waiting) do
            self:ProcessItem(unpack(request, 1, 5))
        end
    end
    return core
end

local function NewItem(bag, slot)
    local item = {}
    function item:ContinueOnItemLoad(fn)
        fn()
        if slot % 2 == 1 then fn() end -- the addon may call back twice
    end
    function item:GetCaerdonStatus()
        local data = world.bags[bag][slot]
        return true, data.status, data.binding, {}
    end
    function item:GetCaerdonItemType() return "Equipment" end
    function item:IsItemEmpty() return false end
    function item:GetItemData() return nil end
    return item
end

-- A bag window: one button per slot, drawn through a feature when it is opened.
local function NewBagWindow(featureName, integration, flaws)
    flaws = flaws or {}
    local window = { buttons = {}, holder = NewWidget("Frame") }
    window.holder.shown = false
    local feature = { integration = integration, initFinished = true }
    function feature:GetName() return featureName end
    function feature:GetStatusRuleName() return featureName end
    function feature:Draw()
        for bag = 0, 5 do
            for slot = 1, SLOTS[bag] do
                local key = bag .. "/" .. slot
                local button = window.buttons[key]
                if not button then
                    button = NewWidget("ItemButton", window.holder)
                    button.icon = NewWidget("Texture", button)
                    function button.icon:GetTexture()
                        local data = world.bags[bag][slot]
                        if flaws.wrongPicture == key then return 999 end
                        if flaws.noPicture then return "Interface\\Icons\\Thing" end
                        return data and data.iconFileID or nil
                    end
                    function button:GetSlotAndBagID() return slot, bag end
                    window.buttons[key] = button
                end
                if world.bags[bag][slot] then
                    CaerdonWardrobe:UpdateButton(button, NewItem(bag, slot), feature, { bag = bag, slot = slot },
                        { statusProminentSize = 24 })
                end
            end
        end
    end
    local function DrawTwin()
        local bag, slot = flaws.twin:match("(%d+)/(%d+)")
        bag, slot = tonumber(bag), tonumber(slot)
        if not window.twin then
            local away = NewWidget("Frame")
            away.shown = false
            window.twin = NewWidget("ItemButton", away)
        end
        CaerdonWardrobe:UpdateButton(window.twin, NewItem(bag, slot), feature, { bag = bag, slot = slot }, {})
    end
    function feature:Refresh()
        if not flaws.noRefresh and window.holder.shown then self:Draw() end
        if flaws.twin and window.holder.shown then DrawTwin() end
    end
    function window:Open()
        self.holder.shown = true
        if flaws.twin then
            DrawTwin()
            session.core:Step()
        end
        feature:Draw()
    end
    session.core.features[featureName] = feature
    session.windows[featureName] = window
    return window
end

local function Boot(isReload)
    session = { widgets = {}, timers = {}, windows = {}, reload = nil }
    output = {}
    function session.After(delay, fn)
        session.timers[#session.timers + 1] = { at = world.now + delay, fn = fn }
    end

    local enabled = world.enabled[world.guid]
    local loaded = {}
    local function Loads(addon)
        if not enabled[addon.name] or addon.broken then return false end
        for _, dep in ipairs(addon.deps or {}) do
            if not Loads(AddonByName(dep)) then return false end
        end
        return true
    end
    for _, addon in ipairs(world.addons) do loaded[addon.name] = Loads(addon) end
    session.loaded = loaded

    -- Globals of the client
    GetTime = function() return world.now end
    GetTimePreciseSec = GetTime
    GetServerTime = function() return 1700000000 + math.floor(world.now) end
    date = os.date
    format = string.format
    tinsert = table.insert
    issecretvalue = function() return false end
    geterrorhandler = function() return function(message) error(message, 0) end end
    debugstack = function() return "stack" end
    InCombatLockdown = function() return false end
    GetBuildInfo = function() return "1.60.1", "70938", "Nov 1 2026", 16001 end
    GetLocale = function() return "enUS" end
    WOW_PROJECT_ID = 18
    UnitGUID = function() return world.guid end
    UnitFullName = function() return world.toon, "Mockrealm" end
    UnitClass = function() return "Rogue", "ROGUE" end
    UnitRace = function() return "Human", "Human" end
    UnitFactionGroup = function() return "Alliance" end
    UnitLevel = function() return 20 end
    GetProfessions = function() return nil end
    GetRealmName = function() return "Mockrealm" end
    GetFramerate = function() return 60 end
    UISpecialFrames = {}
    ToggleAllBags = function()
        for _, window in pairs(session.windows) do window:Open() end
    end
    SlashCmdList = {}
    UIParent = NewWidget("Frame")
    CreateFrame = function(kind, name, parent) return NewWidget(kind, parent) end
    hooksecurefunc = function(owner, key, hook)
        local original = owner[key]
        owner[key] = function(...)
            local results = { original(...) }
            local co = coroutine.running() or "main"
            depth[co] = (depth[co] or 0) + 1
            hook(...)
            depth[co] = depth[co] - 1
            return unpack(results, 1, table.maxn(results))
        end
    end
    Enum = {
        BagIndex = { Backpack = 0, ReagentBag = 5 },
        AddOnEnableState = { None = 0, Some = 1, All = 2 },
        BankType = { Character = 0, Account = 2 },
        AddOnProfilerMetric = { LastTime = 1 },
    }
    C_Timer = {
        After = session.After,
        NewTicker = function(interval, fn)
            local ticker = { cancelled = false }
            function ticker:Cancel() self.cancelled = true end
            local function Tick()
                if ticker.cancelled then return end
                session.After(interval, Tick)
                fn(ticker)
            end
            session.After(interval, Tick)
            return ticker
        end,
    }
    C_Container = {
        GetContainerNumSlots = function(bag) return SLOTS[bag] or 0 end,
        GetContainerItemInfo = function(bag, slot) return world.bags[bag] and world.bags[bag][slot] end,
    }
    C_AddOns = {
        GetNumAddOns = function() return #world.addons end,
        GetAddOnInfo = function(index) local addon = AddonByName(index) return addon and addon.name end,
        GetAddOnMetadata = function(name, field) local addon = AddonByName(name) return field == "Version" and addon and addon.version or nil end,
        GetAddOnEnableState = function(name, guid)
            assert(guid == world.guid, "enable state asked for another character")
            assert(AddonByName(name), "enable state of an addon that does not exist: " .. tostring(name))
            return world.enabled[guid][name] and 2 or 0
        end,
        EnableAddOn = function(name, guid) assert(guid == world.guid) world.enabled[guid][name] = true end,
        DisableAddOn = function(name, guid) assert(guid == world.guid) world.enabled[guid][name] = nil end,
        SaveAddOns = function() world.saves = world.saves + 1 end,
        DoesAddOnExist = function(name) return AddonByName(name) ~= nil end,
        GetAddOnDependencies = function(name) return unpack(AddonByName(name).deps or {}) end,
        IsAddOnLoaded = function(name) return loaded[name] or false, loaded[name] or false end,
        IsAddOnLoadable = function(name) local addon = AddonByName(name) return false, addon.broken or "DISABLED" end,
    }
    C_Bank = { FetchPurchasedBankTabIDs = function() return {} end }
    C_AddOnProfiler = { GetAddOnMetric = function() return 0 end, IsEnabled = function() return true end }
    UpdateAddOnMemoryUsage = function() end
    GetAddOnMemoryUsage = function() return 1000 end
    CaerdonAPI = { GetClientFlavor = function() return "Forever" end }
    CaerdonWardrobeConfig = {}
    CaerdonItem = { CreateFromBagAndSlot = function(_, bag, slot) return NewItem(bag, slot) end }

    session.core = NewCore()
    CaerdonWardrobe = session.core
    -- Blizzard's own bags are only on screen when no bag addon took them over.
    local blizzard = NewBagWindow("Bags")
    if loaded.BetterBags then
        blizzard.Open = function() end
        NewBagWindow("BetterBags", { addon = "BetterBags" }, { twin = world.betterBagsTwin, noPicture = world.betterBagsTwin ~= nil })
        session.core.features.BetterBagsVendor = { integration = { addon = "BetterBags", waiting = true },
            GetName = function() return "BetterBagsVendor" end }
    end
    if loaded.Sorted then
        blizzard.Open = function() end
        NewBagWindow("Sorted", { addon = "Sorted" }, world.sortedFaults and { noRefresh = true, wrongPicture = "1/1" } or {})
    end
    CaerdonIntegrations = {
        GetReport = function()
            local report = {}
            for name, feature in pairs(session.core.features) do
                if feature.integration then
                    report[#report + 1] = { feature = name, addon = feature.integration.addon, version = "x",
                        initFinished = true, points = {}, verdict = feature.integration.waiting and "waiting" or "ok",
                        summary = feature.integration.waiting and "0 of 1 hook points found; not reached yet: vendor" or
                            "2 of 2 hook points found" }
                end
            end
            return report
        end,
    }

    -- The test addon's files
    CaerdonWardrobeTestsDB = world.saved
    local T = {}
    for _, file in ipairs({ "Core.lua", "Runner.lua", "Facts.lua", "Journal.lua", "Snapshot.lua", "Integrations.lua",
        "Rotation.lua", "RotationPanel.lua", "Plan.lua", "Commands.lua" }) do
        local chunk = assert(loadfile(ROOT .. "/" .. file))
        chunk("CaerdonWardrobe_Tests", T)
    end
    -- What the files left out here would have defined.
    T.NoteDrawn = function() end
    T.ScanSightings = function() end
    T.GetSightingRows = function() return {} end
    T.RefusedItems = function() return {} end
    T.ReadProfiler = function() return {} end
    T.RequestReload = function(how) session.reload = how end
    session.T = T

    FireEvent("ADDON_LOADED", "CaerdonWardrobe_Tests")
    FireEvent("PLAYER_LOGIN")
    -- Timing.lua writes the login record and then calls AfterLogin; it is not loaded here.
    T.Start("login", function()
        T.WaitForIdle(2, 90)
        T.AfterLogin()
    end)
end

local function Run(seconds)
    local finish = world.now + seconds
    while world.now < finish do
        world.now = world.now + 0.05
        local timers = session.timers
        session.timers = {}
        for _, timer in ipairs(timers) do
            if timer.at <= world.now then timer.fn() else session.timers[#session.timers + 1] = timer end
        end
        session.core:Step()
        for _, widget in ipairs(session.widgets) do
            if widget.scripts.OnUpdate then widget.scripts.OnUpdate(widget, 0.05) end
        end
        Check(#session.T.db.errors == 0, "no error of the tests' own: " .. tostring(session.T.db.errors[1] and session.T.db.errors[1].message))
        if #session.T.db.errors > 0 then session.T.db.errors = {} end
    end
end

-- What the client does on a reload: write the saved variables, start the UI again.
local function Reload()
    FireEvent("PLAYER_LOGOUT")
    world.saved = CaerdonWardrobeTestsDB
    Boot(true)
    Run(4)
end

local function Slash(text)
    SlashCmdList["CAERDONTESTS"](text)
end

local function EnabledList()
    local names = {}
    for name in pairs(world.enabled[world.guid]) do names[#names + 1] = name end
    table.sort(names)
    return table.concat(names, ",")
end

local function OpenBags()
    for _, window in pairs(session.windows) do window:Open() end
end

------------------------------------------------------------------------------------------
-- Scenarios
------------------------------------------------------------------------------------------

local ORIGINAL = "BetterBags,CaerdonWardrobe,CaerdonWardrobe_Tests,Pawn"

realPrint("1. pure functions")
Boot()
Run(4)
local T = session.T
do
    local list = { "A", "B", "C" }
    local stops, original = T.PlanRotation(list, { A = true, B = true }, { B = true })
    Check(table.concat(stops, ",") == "Blizzard,A,B" and original == "B", "plan: the played set last: " .. table.concat(stops, ","))
    stops, original = T.PlanRotation(list, { A = true, B = true }, {})
    Check(table.concat(stops, ",") == "A,B,Blizzard" and original == "Blizzard", "plan: Blizzard last when it is the played set: " .. table.concat(stops, ","))
    stops, original = T.PlanRotation(list, { A = true, B = true }, { A = true, B = true })
    Check(table.concat(stops, ",") == "Blizzard,A,B" and original == nil, "plan: two enabled, no original stop")
    stops = T.PlanRotation(list, { A = true, B = true }, { B = true }, { "blizzard", "b" })
    Check(table.concat(stops, ",") == "Blizzard,B", "plan: limited to the named stops")
    stops = T.PlanRotation(list, {}, {})
    Check(table.concat(stops, ",") == "Blizzard", "plan: nothing installed leaves Blizzard")
    local states = T.RotationStates("A", list, { A = true, B = true })
    Check(states.A == true and states.B == false and states.C == nil, "states: one on, installed others off")
    Check(T.CompareDrawn({ icon = "a", iconSize = 20 }, { icon = "a", iconSize = 37 }) == nil, "compare: size is not content")
    Check(T.CompareDrawn({ icon = "a" }, { icon = "b" }) ~= nil, "compare: another icon differs")
    Check(T.CompareDrawn({ icon = "a", text = "BoE" }, { icon = "a" }) ~= nil, "compare: a leftover text differs")
end

realPrint("2. a check outside a run, under the bag addon that is on")
OpenBags()
Run(1)
Slash("rotation check")
Run(6)
do
    local single = T.db.rotation.single
    Check(single and single.stop == "BetterBags" and single.verdict == "pass", "single check passes under BetterBags: " .. tostring(single and single.verdict))
    Check(single and single.checked == 6 and single.same == 6, "six buttons checked")
    Check(single and single.features.BetterBags and single.features.BetterBags.visible == 6, "drawn by BetterBags")
    Check(single and #single.notes == 1 and single.notes[1]:find("BetterBagsVendor", 1, true), "the vendor's waiting hook is a note")
    Check(single and single.shown["item:101::::::::|B"] == nil and single.shown["item:101"] ~= nil, "shown is keyed like the snapshot")
    Check(T.db.rotation.run == nil, "no run was started")
end

realPrint("2b. two buttons of one feature for one slot; a picture that is not a file ID")
world.betterBagsTwin = "0/2"
Reload()
T = session.T
OpenBags()
Run(1)
Slash("rotation check")
Run(6)
do
    local single = T.db.rotation.single
    Check(single.verdict == "fail" and single.notRedrawn == 1 and single.sharedSlot == 1, "the shared slot is found: " .. tostring(single.notRedrawn) .. " " .. tostring(single.sharedSlot))
    Check(single.problems[1] and single.problems[1].what:find("2 buttons of this feature were last drawn for this slot, 1 of them not on screen", 1, true), "and described: " .. tostring(single.problems[1] and single.problems[1].what))
    Check(single.picturesRead == 0 and tostring(single.pictureSample):find("icon:GetTexture() is a string", 1, true), "an unreadable picture is described: " .. tostring(single.pictureSample))
    Check(single.forced == true, "a check asked for is marked")
    Check(single.features.BetterBags.requests >= 12 and single.features.BetterBags.draws >= 12, "requests and draws are counted: " .. tostring(single.features.BetterBags.requests))
end
world.betterBagsTwin = nil
Reload()
T = session.T

realPrint("3. the run: Blizzard, LiteBag (does not load), Sorted (planted faults), BetterBags")
Slash("rotation status")
Check(Said("would visit, in this order: Blizzard, LiteBag, Sorted, BetterBags"), "status lists the stops")
Check(Said("not installed, so not visited: AdiBags"), "status lists what is not installed")
Slash("rotation start")
Check(session.reload == "slash", "start asks for a reload")
Check(EnabledList() == "CaerdonWardrobe,CaerdonWardrobe_Tests,Pawn", "stop 1: every listed addon off, the rest untouched: " .. EnabledList())
Check(world.saves == 1, "the addon list was saved")
Reload()
T = session.T
Check(Said("rotation stop 1 of 4: Blizzard"), "after the reload the stop is announced")
Run(5)
Check(T.db.rotation.run.results.Blizzard == nil, "no check while the bags are closed")
Slash("rotation next")
Check(session.reload == nil and Said("has not been checked"), "next without a check asks first")
OpenBags()
Run(8)
do
    local record = T.db.rotation.run.results.Blizzard
    Check(record and record.verdict == "pass" and record.checked == 6, "Blizzard's bags pass by themselves once opened: " .. tostring(record and record.verdict))
    Check(record and record.features.Bags.expected == true, "Bags is the stop's feature")
    Check(Said("next stop: LiteBag"), "the next stop is named")
end
Slash("rotation next")
Check(session.reload == "slash" and EnabledList() == "CaerdonWardrobe,CaerdonWardrobe_Tests,LiteBag,Pawn", "stop 2: LiteBag alone: " .. EnabledList())
Reload()
T = session.T
do
    local record = T.db.rotation.run.results.LiteBag
    Check(record and record.verdict == "skipped" and record.reasons[1]:find("INTERFACE_VERSION", 1, true), "an addon that does not load is skipped with the reason")
end
session.T.RotationCommand("next", "click")
Check(session.reload == "click", "the window's button reloads too")
Check(EnabledList() == "CaerdonWardrobe,CaerdonWardrobe_Tests,Pawn,Sorted,SortedLib", "stop 3: Sorted with what it depends on: " .. EnabledList())
Reload()
T = session.T
OpenBags()
Run(2)
world.bags[0][2].status = "auction" -- the verdict moves, and Sorted's Refresh() does nothing
Run(8)
do
    local record = T.db.rotation.run.results.Sorted
    Check(record and record.verdict == "fail", "Sorted fails: " .. tostring(record and record.verdict))
    Check(record and record.notRedrawn == 6, "no button was drawn again: " .. tostring(record and record.notRedrawn))
    Check(record and record.differ == 1, "one button shows the old verdict: " .. tostring(record and record.differ))
    Check(record and record.otherItem == 1, "one button carries another picture: " .. tostring(record and record.otherItem))
    Check(record and #record.problems == 6 and record.problems[2].what:find("icon is icon-sellable where the addon draws icon-auction", 1, true),
        "the stale button is described: " .. tostring(record and record.problems[2] and record.problems[2].what))
end
Slash("rotation next")
Check(EnabledList() == ORIGINAL, "last stop: the original set, the dependency off again: " .. EnabledList())
Reload()
T = session.T
OpenBags()
Run(8)
do
    Check(T.db.rotation.run == nil, "the run ended by itself at the last stop")
    local run = T.db.rotation.history[1]
    Check(run and not run.aborted and run.results.BetterBags.verdict == "pass", "BetterBags passed")
    Check(session.reload == nil, "no reload was needed to put things back")
    Check(Said("rotation finished: 4 stops, 2 pass, 1 fail, 1 skipped"), "the summary is printed")
    Check(EnabledList() == ORIGINAL, "the addons are as before")
end

realPrint("4. a second run after a change, limited to two stops: compared with the first")
world.bags[1][1].status = "otherPlus"
Slash("rotation start blizzard betterbags")
Reload()
T = session.T
OpenBags()
Run(8)
Slash("rotation next")
Reload()
T = session.T
OpenBags()
Run(8)
do
    local run = T.db.rotation.history[2]
    Check(run and run.changeCount == 3, "changes against the first run: " .. tostring(run and run.changeCount))
    Check(run and run.changes[1].summary:find("status", 1, true), "a change names the field: " .. tostring(run and run.changes[1] and run.changes[1].summary))
    Check(EnabledList() == ORIGINAL, "the addons are as before")
end
Slash("rotation start nosuchaddon")
Check(Said("nosuchaddon is not a stop") and T.db.rotation.run == nil, "an unknown stop starts nothing")

realPrint("5. abort in the middle")
Slash("rotation start")
Reload()
T = session.T
Slash("rotation abort")
Check(session.reload == "slash" and EnabledList() == ORIGINAL, "abort puts the set back and reloads: " .. EnabledList())
Reload()
T = session.T
do
    local run = T.db.rotation.history[#T.db.rotation.history]
    Check(T.db.rotation.run == nil and Said("rotation stopped"), "the aborted run is closed after the reload")
    Check(#T.db.rotation.history == 2, "an aborted run with no stop checked is not kept")
    Check(T.db.rotation.history[2].results.Blizzard.shown ~= nil, "the newest finished run keeps what was shown")
    Check(T.db.rotation.history[1].results.Blizzard.shown == nil, "the one before it does not")
end

realPrint("6. passing a stop over, and ending at a failed last stop")
world.sortedFaults = false
Slash("rotation start sorted betterbags")
Reload()
T = session.T
Slash("rotation next")
Slash("rotation next")
Check(session.reload == "slash", "the second next passes the stop over")
Reload()
T = session.T
Check(T.db.rotation.run.results.Sorted.verdict == "skipped", "the stop is recorded as skipped")
Slash("rotation check") -- the bags are closed: nothing on screen
Run(6)
Check(T.db.rotation.run and T.db.rotation.run.results.BetterBags.verdict == "fail", "a check with the bags closed fails and the run stays open")
OpenBags()
Run(1)
Slash("rotation check")
Run(6)
Check(T.db.rotation.run == nil, "checked again with the bags open, the run ends")

realPrint("7. another toon logs in during a run")
Slash("rotation start blizzard")
Reload()
world.guid, world.toon = "Player-2", "Other"
Reload()
T = session.T
Check(Said("a rotation is waiting on Tester-Mockrealm"), "the other toon is told")
Slash("rotation next")
Check(session.reload == nil and EnabledList() == ORIGINAL, "next does nothing on the other toon")
Slash("rotation abort")
Check(T.db.rotation.run ~= nil, "abort on the other toon asks first")
world.guid, world.toon = "Player-1", "Tester"
Reload()
T = session.T
Check(EnabledList() == "CaerdonWardrobe,CaerdonWardrobe_Tests,Pawn", "the run's toon is still at its stop")
Slash("rotation abort")
Reload()
Check(EnabledList() == ORIGINAL and session.T.db.rotation.run == nil, "and gets its addons back")

realPrint("8. the whole run by the panel's buttons")
world.sortedFaults = false
do
    local function Panel() return session.T.rotationPanel end
    local function Click(button)
        Check(button:IsShown() and button:IsEnabled(), "the button can be clicked: " .. tostring(button:GetText()))
        button.scripts.OnClick(button)
    end
    local function Label() return Panel().main:GetText() end

    Reload()
    Check(Panel() == nil, "no panel without a run after a plain reload")
    Slash("rotation")
    Check(Panel():IsShown() and Label() == "Start the rotation", "the panel offers to start: " .. tostring(Label()))
    Check(Panel().text:GetText():find("Stops: Blizzard, LiteBag, Sorted, BetterBags", 1, true), "and lists the stops")
    Check(Panel().check:IsShown() and not Panel().abort:IsShown() and not Panel().skip:IsShown(), "only Check now beside it")
    Click(Panel().main)
    Check(session.reload == "click", "start reloads from the click")
    Reload()
    Check(Panel() and Panel():IsShown(), "the panel is back by itself after the reload")
    Check(Label() == "Open the bags", "stop 1 asks for the bags: " .. tostring(Label()))
    Check(Panel().skip:IsShown() and Panel().abort:IsShown(), "skip and stop are offered")
    Click(Panel().main)
    Run(0.5)
    Check(Label() == "Checking in a moment..." and not Panel().main:IsEnabled(), "with the bags open the button waits: " .. tostring(Label()))
    Run(8)
    Check(Label() == "Next stop: LiteBag (reload)", "then it names the next stop: " .. tostring(Label()))
    Check(Panel().text:GetText():find("6 buttons checked, 6 as the addon draws them", 1, true), "with the result above it")
    Click(Panel().main)
    Reload()
    Check(Label() == "Next stop: Sorted (reload)", "a stop whose addon did not load goes straight on: " .. tostring(Label()))
    Click(Panel().main)
    Reload()
    Check(Label() == "Open the bags", "stop 3: " .. tostring(Label()))
    Click(Panel().skip)
    Check(session.reload == "click" and session.T.db.rotation.run.results.Sorted.verdict == "skipped", "Skip this stop passes it over at once")
    Reload()
    Click(Panel().main)
    Run(8)
    Check(session.T.db.rotation.run == nil, "the last stop passed and the run ended")
    Check(Label() == "Save the results (reload)", "the panel offers to save: " .. tostring(Label()))
    Check(Panel().text:GetText():find("The run is finished", 1, true), "and says it is finished")
    Click(Panel().main)
    Check(session.reload == "click", "saving reloads")
    Reload()
    Check(Panel() == nil, "after that the panel stays away")
    Check(EnabledList() == ORIGINAL, "the addons are as before")

    -- Stop the run from the panel; a check with nothing on screen.
    Slash("rotation")
    Click(Panel().check)
    Run(6)
    Check(session.T.db.rotation.single.verdict == "fail", "Check now with the bags closed records a failure")
    Click(Panel().main)
    Reload()
    Run(3)
    Check(Label() == "Open the bags", "at a stop: " .. tostring(Label()))
    ToggleAllBags = function() end -- a bag addon that does not answer
    Click(Panel().main)
    Run(4)
    Check(Panel().text:GetText():find("No bag button the addon drew is on screen", 1, true), "bags that did not open are said")
    Click(Panel().abort)
    Check(session.reload == "click" and EnabledList() == ORIGINAL, "Stop the run puts the addons back")
    Reload()
    Check(session.T.db.rotation.run == nil and Label() == "Save the results (reload)", "and the panel closes the run: " .. tostring(Label()))
end

realPrint("9. the window")
T = session.T
Slash("")
Check(true, "the window opens")
if os.getenv("MOCK_DUMP") then
    local function dump(value, indent)
        if type(value) == "table" then
            local parts = {}
            for key, item in pairs(value) do
                local name = type(key) == "number" and ("[" .. key .. "]") or ("[" .. realFormat("%q", tostring(key)) .. "]")
                parts[#parts + 1] = indent .. "  " .. name .. " = " .. dump(item, indent .. "  ")
            end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
        elseif type(value) == "string" then
            return realFormat("%q", value)
        end
        return tostring(value)
    end
    local file = io.open(os.getenv("MOCK_DUMP"), "w")
    file:write("CaerdonWardrobeTestsDB = " .. dump(CaerdonWardrobeTestsDB, "") .. "\n")
    file:close()
end
realPrint(("%d checks, %d failed"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
