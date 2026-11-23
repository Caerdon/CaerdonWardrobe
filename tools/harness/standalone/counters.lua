-- The core's counters against a mocked client under LuaJIT.
--   luajit tools/harness/standalone/counters.lua [repo dir] [dump file]
-- tools/harness/run.lua runs it with the scenarios. It is older than the harness' shared
-- client and brings a small one of its own, with a clock and a memory figure it sets itself.
-- Real code: CaerdonCounters.lua, CaerdonAsyncCallbackSystem.lua, FeatureMixin.lua, the queue
-- of CaerdonWardrobe.lua, Blizzard's ContinuableContainer (from the Builds mirror when it is
-- there), and the test addon's Core, Plan, Counters and Timing files. Mocked: the client, the
-- drawing functions, the items and their status code. The clock and the memory figure are the
-- mock's own, so every expected number is exact.
-- Two guards make LuaJIT as strict as the client's Lua 5.1: no yield inside pcall, and %s only
-- for strings and numbers.

local ROOT = arg[1] or "."
local DUMP = arg[2]
local realPcall, realYield, realFormat = pcall, coroutine.yield, string.format

------------------------------------------------------------------------------------------
-- Guards
------------------------------------------------------------------------------------------

local guardDepth = setmetatable({}, { __mode = "k" })
local function Guarded(f, ...)
    local co = coroutine.running() or "main"
    guardDepth[co] = (guardDepth[co] or 0) + 1
    local results = { realPcall(f, ...) }
    guardDepth[co] = guardDepth[co] - 1
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
    if (guardDepth[coroutine.running()] or 0) > 0 then
        error("GUARD: yield inside pcall", 2)
    end
    return realYield(...)
end
string.format = function(fmt, ...)
    local index = 0
    for spec in fmt:gmatch("%%[%-+ #0]*%d*%.?%d*([%a%%])") do
        if spec ~= "%" then
            index = index + 1
            local kind = type((select(index, ...)))
            if spec == "s" and kind ~= "string" and kind ~= "number" then
                error("GUARD: %s given a " .. kind .. " in: " .. fmt, 2)
            elseif spec ~= "s" and kind ~= "number" then
                error("GUARD: %" .. spec .. " given a " .. kind .. " in: " .. fmt, 2)
            end
        end
    end
    return realFormat(fmt, ...)
end

------------------------------------------------------------------------------------------
-- Checks
------------------------------------------------------------------------------------------

local checks, failures = 0, 0
local function Check(condition, label)
    checks = checks + 1
    if not condition then
        failures = failures + 1
        print("FAIL: " .. label)
    end
end
local function Near(actual, expected, label)
    local ok = type(actual) == "number" and math.abs(actual - expected) < 0.002
    Check(ok, ("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)))
end
local function Equal(actual, expected, label)
    Check(actual == expected, ("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)))
end

------------------------------------------------------------------------------------------
-- The client
------------------------------------------------------------------------------------------

local clock, memory = 100, 50000
local function Spend(ms, kb)
    clock = clock + ms / 1000
    memory = memory + (kb or 0)
end

local frames, timers, errors

local function ReadFile(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

-- A chunk that looks to debugstack like a file of the named addon.
local function AddonChunk(addon, rel, source)
    return assert(loadstring(source, "@Interface/AddOns/" .. addon .. "/" .. rel))
end
local function LoadAddonFile(addon, rel, ...)
    local folder = addon == "CaerdonWardrobe" and ROOT or (ROOT .. "/" .. addon)
    return AddonChunk(addon, rel, ReadFile(folder .. "/" .. rel))(...)
end

local function NewFrame()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    function frame:GetScript(name) return self.scripts[name] end
    function frame:SetAllPoints() end
    frames[#frames + 1] = frame
    return frame
end

local function Fire(event, ...)
    for index = 1, #frames do
        local frame = frames[index]
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

local function RunTimers()
    local due = {}
    for index = #timers, 1, -1 do
        if timers[index].cancelled then
            table.remove(timers, index)
        elseif timers[index].at <= clock then
            table.insert(due, 1, table.remove(timers, index))
        end
    end
    for _, timer in ipairs(due) do
        timer.fn()
    end
end

-- One frame of the client: 60 ms on, timers, then every OnUpdate.
local function Tick(count)
    for _ = 1, count or 1 do
        clock = clock + 0.06
        RunTimers()
        for index = 1, #frames do
            local frame = frames[index]
            if frame.scripts.OnUpdate then
                frame.scripts.OnUpdate(frame, 0.06)
            end
        end
    end
end

local pendingLoads, answerAtOnce

local function InstallClient()
    frames, timers, errors, pendingLoads, answerAtOnce = {}, {}, {}, {}, {}

    GetTimePreciseSec = function() return clock end
    GetTime = function() return clock end
    GetServerTime = function() return 1700000000 + math.floor(clock) end
    collectgarbage = function(what)
        assert(what == "count", "only collectgarbage('count') is expected")
        return memory
    end
    debugstack = function(start, count)
        local lines, level = {}, (start or 1) + 1
        while #lines < (count or 12) do
            local info = debug.getinfo(level, "Sl")
            if not info then
                break
            end
            if info.what == "C" then
                lines[#lines + 1] = "[C]: in function <?>"
            else
                local source = info.source:gsub("^@", "")
                lines[#lines + 1] = ("[%s]:%d: in function <%s:%d>"):format(source, info.currentline, source,
                    info.linedefined)
            end
            level = level + 1
        end
        return table.concat(lines, "\n")
    end
    wipe = function(t) for key in pairs(t) do t[key] = nil end return t end
    tinsert = table.insert
    format, strmatch = string.format, string.match
    issecretvalue = function() return false end
    geterrorhandler = function() return function(message) errors[#errors + 1] = tostring(message) end end
    CallErrorHandler = function(message) errors[#errors + 1] = tostring(message) end
    CreateFrame = function() return NewFrame() end
    Mixin = function(object, ...)
        for index = 1, select("#", ...) do
            for key, value in pairs((select(index, ...))) do object[key] = value end
        end
        return object
    end
    CreateFromMixins = function(...) return Mixin({}, ...) end
    hooksecurefunc = function(owner, name, hook)
        if type(owner) == "string" then
            owner, name, hook = _G, owner, name
        end
        local original = owner[name]
        owner[name] = function(...)
            local results = { original(...) }
            hook(...)
            return unpack(results, 1, table.maxn(results))
        end
    end
    InCombatLockdown = function() return false end
    GetBuildInfo = function() return "1.60.1", "70938", "Nov 1 2026", 16001 end
    EquipPendingItem = function() end
    C_Timer = {
        After = function(seconds, fn) timers[#timers + 1] = { at = clock + seconds, fn = fn } end,
        NewTimer = function(seconds, fn)
            local timer = { at = clock + seconds, fn = fn }
            function timer:Cancel() self.cancelled = true end
            timers[#timers + 1] = timer
            return timer
        end,
    }
    Enum = { ItemClass = {}, AddOnProfilerMetric = { LastTime = 1 }, AddOnEnableState = { None = 0 } }
    AsyncCallbackAPIType = { ASYNC_QUEST = 1, ASYNC_ITEM = 2, ASYNC_SPELL = 3 }
    C_QuestLog = { RequestLoadQuestByID = function() end }
    C_Spell = { RequestLoadSpellData = function() end }
    C_Item = {
        RequestLoadItemDataByID = function(id)
            if answerAtOnce[id] ~= nil then
                Fire("ITEM_DATA_LOAD_RESULT", id, answerAtOnce[id])
            else
                pendingLoads[id] = true
            end
        end,
    }
end

local function Answer(id, success)
    assert(pendingLoads[id], "nobody asked for item " .. id)
    pendingLoads[id] = nil
    Fire("ITEM_DATA_LOAD_RESULT", id, success)
end

------------------------------------------------------------------------------------------
-- The addon: real counters, listener, feature mixin and queue; mocked items and drawing
------------------------------------------------------------------------------------------

local statusCache
local Session = {}

-- options: debug (Enable debug as saved), dropEquipmentSets (a probe target that is gone),
-- features (mixins registered beside the bags)
local function StartSession(options)
    InstallClient()
    statusCache = {}
    local NS = { L = setmetatable({}, { __index = function(_, key) return key end }) }

    LoadAddonFile("CaerdonWardrobe", "CaerdonCounters.lua", "CaerdonWardrobe", NS)
    LoadAddonFile("CaerdonWardrobe", "CaerdonAsyncCallbackSystem.lua", "CaerdonWardrobe", NS)
    LoadAddonFile("CaerdonWardrobe", "FeatureMixin.lua", "CaerdonWardrobe", NS)
    local home = os.getenv("USERPROFILE") or os.getenv("HOME") or ""
    local builds = os.getenv("CAERDON_BUILDS") or (home .. "/Projects/WoW/Builds")
    local blizzard = io.open(builds .. "/source/forever/Interface/AddOns/Blizzard_ObjectAPI/Mainline/ContinuableContainer.lua", "rb")
    assert(blizzard, "the Builds mirror is needed for Blizzard's ContinuableContainer")
    assert(loadstring(blizzard:read("*a"), "@Interface/AddOns/Blizzard_ObjectAPI/Mainline/ContinuableContainer.lua"))()
    blizzard:close()
    LoadAddonFile("CaerdonWardrobe", "CaerdonRefresh.lua", "CaerdonWardrobe", NS)
    LoadAddonFile("CaerdonWardrobe", "CaerdonWardrobe.lua", "CaerdonWardrobe", NS)

    CaerdonItemType = { Equipment = "Equipment", Empty = "Empty" }
    CaerdonItem = { InvalidateStatusCache = function() statusCache = {} end }
    local invalidate = { InvalidateCaches = function() end, NoteCollectionChanged = function() end }
    CaerdonFoodDrink, CaerdonProfessionTools, CaerdonBagSlots, CaerdonIngredients =
        invalidate, invalidate, invalidate, invalidate
    -- The equipment code, with the one function of its own that the counters wrap.
    CaerdonEquipment = { InvalidateCaches = function() end, NoteCollectionChanged = function() end,
        GetEquipmentSetsOf = function() end }
    CaerdonTransformLooks = { MayBeConverted = function() end, GetRoute = function() end }
    CaerdonSetBonuses = { NoteTooltip = function() end, GetChanges = function() end }
    -- The data of each kind of item that is not equipment: there to be found, and not asked here.
    CaerdonConsumableMixin, CaerdonRecipeMixin, CaerdonProfessionMixin = { GetConsumableInfo = function() end },
        { GetRecipeInfo = function() end }, { GetProfessionInfo = function() end }
    CaerdonToyMixin, CaerdonMountMixin, CaerdonCompanionPetMixin, CaerdonBattlePetMixin = { GetToyInfo = function() end },
        { GetMountInfo = function() end }, { GetCompanionPetInfo = function() end }, { GetBattlePetInfo = function() end }
    CaerdonHousingMixin, CaerdonCurrencyMixin, CaerdonConduitMixin = { GetHousingInfo = function() end },
        { GetCurrencyInfo = function() end }, { GetConduitInfo = function() end }
    -- The quest module's check after a run of quest events is one of the profile's functions.
    CaerdonQuestItems = { InvalidateCaches = function() end, CompareWithAnswers = function() end,
        CompareWithClient = function() end }
    CaerdonWardrobeConfig = nil -- saved variables arrive after the files
    -- What the addon runs with no window open, as far as the counters time it: the two
    -- handlers of an item tooltip and the auction module's look at the bags.
    -- The core notes the spec as the world comes: a client without specializations here.
    CaerdonAPI = { OnTooltipItem = function() Spend(0.25, 1) end,
        GetPlayerSpecializationIndex = function() return nil end }
    NS.Tooltip = { OnTooltipSetItem = function() Spend(0.5, 2) end, OnRequirementLine = function() end }
    NS.QuestClient = { GetFacts = function() end, Pump = function() end }
    CaerdonAuctionValue = { OnBagsChanged = function() Spend(0.125, 0) end, InvalidateCaches = function() end,
        GetOwnedQuantity = function() end }
    Session.outside = { api = CaerdonAPI, tooltip = NS.Tooltip }

    -- The item side, in the shape of the real one: a cache per link, the tooltip, the binding,
    -- the transmog info (kept with the verdict and returned fifth, which is where a draw takes
    -- it from), then what belongs to the copy.
    CaerdonItemMixin = {}
    function CaerdonItemMixin:GetCaerdonStatus()
        if self.noLink then
            if CaerdonCounters.on then CaerdonCounters:Mark("no link") end
            return
        end
        local cached = statusCache[self.id]
        if cached then
            if CaerdonCounters.on then CaerdonCounters:Mark("cache hit") end
            Spend(0.1)
            return true, self:GetCopyStatus(cached[1]), nil, {}, cached[2]
        end
        Spend(1, 2)
        self:GetTooltipData()
        if (self.notReady or 0) > 0 then
            self.notReady = self.notReady - 1
            if CaerdonCounters.on then CaerdonCounters:Mark("tooltip not ready") end
            return false
        end
        if self.raises then
            error("the status code raised an error")
        end
        self:GetBindingStatus()
        local transmogInfo = self.data:GetTransmogInfo()
        statusCache[self.id] = { "own", transmogInfo }
        return true, self:GetCopyStatus("own"), nil, {}, transmogInfo
    end
    function CaerdonItemMixin:GetTooltipData()
        Spend(2, 8)
        if self.collectorRuns then
            self.collectorRuns = nil
            memory = memory - 500
        end
    end
    function CaerdonItemMixin:GetBindingStatus() Spend(0.5, 1) end
    function CaerdonItemMixin:GetCopyStatus(status)
        Spend(0.25)
        if self.raisesInCopy then
            error("the copy's state raised an error")
        end
        return status
    end
    -- What else a verdict asks, which the counters wrap by name (the link's tooltip, the item's
    -- data, each signal's entry point): there to be found, and not called by this stand-in.
    for _, name in ipairs({ "GetLinkTooltip", "GetItemData", "GetTransformLookInfo", "GetQuestItemInfo", "GetAuctionValueInfo",
        "GetIngredientStatus", "GetFoodDrinkInfo", "GetProfessionToolInfo", "GetBagSlotInfo", "GetUnneededRecipeStatus", "GetLearnerStatus",
        "IsSellable", "IsEquippableJunk", "IsCollectible", "GetHasUse", "IsOtherClassConsumable" }) do
        CaerdonItemMixin[name] = function() end
    end
    CaerdonEquipmentMixin = {}
    function CaerdonEquipmentMixin:GetTransmogInfo()
        Spend(3, 20)
        self:GetEquipmentSets()
        return { isTransmog = false }
    end
    function CaerdonEquipmentMixin:GetEquipmentSets() Spend(1, 5) end
    if options.dropEquipmentSets then
        CaerdonEquipmentMixin.GetEquipmentSets = nil
        CaerdonEquipmentMixin.GetTransmogInfo = function() Spend(3, 20) return { isTransmog = false } end
    end

    -- The frame, as the XML makes it, with the drawing replaced.
    CaerdonWardrobe = NewFrame()
    Mixin(CaerdonWardrobe, CaerdonWardrobeMixin)
    CaerdonWardrobe:SetScript("OnEvent", CaerdonWardrobe.OnEvent)
    CaerdonWardrobe:SetScript("OnUpdate", CaerdonWardrobe.OnUpdate)
    function CaerdonWardrobe:SetupCaerdonButton(button)
        local had = self:GetCaerdonButton(button)
        self:EnsureCaerdonButton(button)
        return nil, not had
    end
    -- As the real ones: the display rules are asked for only when the caller did not hand
    -- them over, which ProcessItem does for a draw.
    function CaerdonWardrobe:SetItemButtonStatus(button, item, feature, locationInfo, drawOptions, status,
                                                 bindingStatus, transmogInfo, displayInfo)
        Spend(1.5, 4)
        if feature and status ~= "waiting" and not displayInfo then
            feature:GetDisplayInfoInternal()
        end
    end
    function CaerdonWardrobe:SetItemButtonMogStatusFilter() end
    function CaerdonWardrobe:SetItemButtonBindType(button, item, feature, locationInfo, drawOptions, status,
                                                   bindingStatus, displayInfo)
        Spend(0.5, 1)
        if feature and bindingStatus and not displayInfo then
            feature:GetDisplayInfoInternal()
        end
    end
    CaerdonWardrobe:OnLoad()

    local BagsMixin = {}
    function BagsMixin:GetName() return "Bags" end
    function BagsMixin:Init() return {} end
    function BagsMixin:GetDisplayInfoInternal() Spend(0.25, 3) return {} end
    function BagsMixin:Refresh() end
    CaerdonWardrobe:RegisterFeature(BagsMixin)
    for _, mixin in ipairs(options.features or {}) do
        CaerdonWardrobe:RegisterFeature(mixin)
    end

    CaerdonWardrobeConfig = { Debug = { Enabled = options.debug and true or false }, Icon = {} }
    Fire("ADDON_LOADED", "CaerdonWardrobe")
    Session.feature = CaerdonWardrobe:GetFeature("Bags")
    Session.buttons = {}
end

local nextSlot = 0
local function NewItem(id, fields)
    nextSlot = nextSlot + 1
    local bag, slot = 0, nextSlot
    local item = CreateFromMixins(CaerdonItemMixin)
    item.id, item.cached = id, true
    item.data = CreateFromMixins(CaerdonEquipmentMixin)
    function item:IsItemEmpty() return false end
    function item:GetCaerdonItemType() return "Equipment" end
    function item:HasItemLocationBankOrBags() return true end
    function item:GetItemLocation() return { GetBagAndSlot = function() return bag, slot end } end
    function item:GetItemID() return self.id end
    function item:IsItemDataCached() return self.cached end
    function item:GetItemData() return self.data end
    function item:IsDataEvictable() return true end
    function item:IsRecordDataCached() return self.cached end
    function item:ContinueWithCancelOnRecordLoad(callback)
        return CaerdonItemEventListener:AddCancelableCallback(self.id, function()
            self.cached = true
            callback(self.id, true)
        end, function()
            callback(self.id, false)
        end)
    end
    for key, value in pairs(fields or {}) do
        item[key] = value
    end
    return item
end

-- Feature code asking for a draw, from a file of the addon.
local Ask = AddonChunk("CaerdonWardrobe", "features/Bags.lua", [[
local button, item, feature = ...
CaerdonWardrobe:UpdateButton(button, item, feature, {}, {})
]])
local function AskFor(items)
    for index, item in ipairs(items) do
        Session.buttons[index] = Session.buttons[index] or {}
        Ask(Session.buttons[index], item, Session.feature)
    end
end

local function Function(report, label)
    for _, entry in ipairs(report.profile.functions) do
        if entry.label == label then
            return entry
        end
    end
    return { calls = -1 }
end

local function IsPlain(value, seen)
    local kind = type(value)
    if kind == "table" then
        for key, item in pairs(value) do
            if (type(key) ~= "string" and type(key) ~= "number") or not IsPlain(item) then
                return false
            end
        end
        return true
    end
    return kind == "string" or kind == "number" or kind == "boolean"
end

------------------------------------------------------------------------------------------
-- 1. The profile never switched on: nothing is wrapped, the ledger still counts
------------------------------------------------------------------------------------------

StartSession({ debug = true })
do
    local core = CaerdonWardrobe
    local before = { core.UpdateButton, core.ProcessItem, core.ClearButton, core.SetItemButtonStatus,
        CaerdonItemMixin.GetCaerdonStatus, CaerdonEquipmentMixin.GetTransmogInfo, Session.feature.GetDisplayInfoInternal }
    Check(CaerdonCounters.on == false, "off: Enable debug alone does not switch the profile on")
    Check(CaerdonCounters.milestones.addonLoaded ~= nil, "off: the addonLoaded milestone is in")

    clock = clock + 1
    Fire("PLAYER_LOGIN")
    clock = clock + 1
    Fire("PLAYER_ENTERING_WORLD", true, false)
    Fire("PLAYER_ENTERING_WORLD", false, false)

    local items = {}
    for index = 1, 5 do items[index] = NewItem(1000 + index) end
    AskFor(items)
    Tick(8)
    clock = clock + 1
    Fire("BAG_UPDATE_DELAYED")
    Fire("BAG_UPDATE_DELAYED")

    local after = { core.UpdateButton, core.ProcessItem, core.ClearButton, core.SetItemButtonStatus,
        CaerdonItemMixin.GetCaerdonStatus, CaerdonEquipmentMixin.GetTransmogInfo, Session.feature.GetDisplayInfoInternal }
    for index = 1, #before do
        Check(before[index] == after[index], "off: function " .. index .. " is the one the addon defined, not a wrapper")
    end

    local report = CaerdonCounters:GetReport()
    Check(report.profile.attached == false and #report.profile.functions == 0, "off: nothing attached, no function counted")
    local names = {}
    for _, milestone in ipairs(report.milestones) do names[#names + 1] = milestone.name end
    Equal(table.concat(names, ","), "addonLoaded,playerLogin,enteringWorld,firstRequest,firstDraw,queueIdle,bagUpdate",
        "off: milestones in the order they were reached")
    Near(report.milestones[2].seconds, 1, "off: playerLogin a second after load")
    Near(report.milestones[3].seconds, 2, "off: enteringWorld two seconds after load")
    Check(IsPlain(report), "off: the report is plain data")
    local lines = CaerdonCounters:GetReportLines()
    Check(lines[#lines].text:find("Profile: not run this session", 1, true) ~= nil, "off: the export says the profile did not run")
    CaerdonWardrobe:RefreshItems()
    Check(CaerdonCounters.on == false, "off: a refresh with Enable debug on leaves it off too")
    Equal(#errors, 0, "off: no error reached the error handler")
end

------------------------------------------------------------------------------------------
-- 2. Full refreshes by what caused them
------------------------------------------------------------------------------------------

do
    Fire("NEW_TOY_ADDED")
    Fire("NEW_TOY_ADDED")
    Fire("PLAYER_EQUIPMENT_CHANGED")
    AddonChunk("CaerdonWardrobe", "CaerdonQuestItems.lua", "\n\nCaerdonWardrobe:RefreshItems()")()
    -- A timer of the core says why: its reason, not the event that set it.
    EquipPendingItem()
    clock = clock + 1.01
    RunTimers()
    -- The watcher (the real CaerdonRefresh.lua): the first event is its first reading, which
    -- counts as a change; the second reads the same skills and refreshes nothing.
    Fire("SKILL_LINES_CHANGED")
    clock = clock + 1
    RunTimers()
    Fire("SKILL_LINES_CHANGED")
    clock = clock + 1
    RunTimers()
    -- The test addon, through a hook on RefreshItems as it has one.
    hooksecurefunc(CaerdonWardrobe, "RefreshItems", function() end)
    AddonChunk("CaerdonWardrobe_Tests", "Timing.lua", "CaerdonWardrobe:RefreshItems()")()
    -- Another addon.
    assert(loadstring("CaerdonWardrobe:RefreshItems()", "@Interface/AddOns/Other/Other.lua"))()

    local refreshes = CaerdonCounters:GetReport().refreshes
    Equal(refreshes.total, 10, "refresh: ten calls counted, with the two of section 1")
    Equal(refreshes.by.pvp, 1, "refresh: one of those two was the watcher's first reading as the world came")
    Equal(refreshes.by.NEW_TOY_ADDED, 2, "refresh: an event of the core is named by the event")
    Equal(refreshes.by.skills, 1, "refresh: two skill line events with the same skills are one refresh, named by its watch")
    Equal(refreshes.by.SKILL_LINES_CHANGED, nil, "refresh: and none is filed under the event")
    Equal(refreshes.by.PLAYER_EQUIPMENT_CHANGED, 1, "refresh: a second event")
    Equal(refreshes.by["CaerdonQuestItems.lua:3"], 1, "refresh: a signal module is named by its line")
    Equal(refreshes.by["CaerdonWardrobe_Tests/Timing.lua:1"], 1, "refresh: the test addon is named with its folder, through a hook")
    Equal(refreshes.by["(not the addon's own code)"], 2, "refresh: another addon's call, and the mock's own in section 1")
    Equal(refreshes.by["equip pending"], 1, "refresh: the core's own timer is named by the reason it gives")
    Equal(#refreshes.recent, 10, "refresh: the recent list holds them")
    local skillsEntry
    for _, entry in ipairs(refreshes.recent) do
        if entry.trigger == "skills" then skillsEntry = entry end
    end
    Equal(skillsEntry and skillsEntry.detail, "first reading", "refresh: the watcher's entry says what had changed")
    local skills
    for _, watch in ipairs(refreshes.watched) do
        if watch.name == "skills" then skills = watch end
    end
    Check(skills ~= nil and skills.events == 2 and skills.checks == 4 and skills.changes == 1,
        "refresh: the report says how many events the watch saw, how often it read and how often that was a change")
    local watchedLine, recentLine
    for _, line in ipairs(CaerdonCounters:GetReportLines()) do
        if line.text == "watched skills: 2 events, read 4 times, 1 changes" then watchedLine = true end
        if line.text:find("s: skills (first reading)", 1, true) then recentLine = true end
    end
    Check(watchedLine, "refresh: the export has a line per watch")
    Check(recentLine, "refresh: and the newest refreshes with their reasons")
    Check(CaerdonCounters.event == nil, "refresh: no event is left set after the handlers")

    -- Redraws: the windows' Refresh() runs a tenth of a second after the last refresh of a
    -- run, so the two are not the same count.
    local function Redraws(trigger)
        local redraws = CaerdonCounters:GetReport().refreshes.redraws
        return trigger and (redraws.by[trigger] or 0) or redraws.total
    end
    local function Refreshes()
        return CaerdonCounters:GetReport().refreshes.total
    end
    clock = clock + 1
    RunTimers()
    local drawn, asked = Redraws(), Refreshes()
    local drawnForGear, drawnForToy = Redraws("PLAYER_EQUIPMENT_CHANGED"), Redraws("NEW_TOY_ADDED")
    Check(drawn > 0 and drawn < asked, "redraw: the windows had drawn less often than there were refreshes: " .. drawn .. " of " .. asked)

    Fire("NEW_TOY_ADDED")
    Fire("NEW_TOY_ADDED")
    Fire("PLAYER_EQUIPMENT_CHANGED")
    Equal(Refreshes() - asked, 3, "redraw: three refreshes in a run")
    Equal(Redraws() - drawn, 0, "redraw: draw nothing in the calls themselves")
    clock = clock + 0.09
    RunTimers()
    Equal(Redraws() - drawn, 0, "redraw: nor before a tenth of a second is over")
    clock = clock + 0.02
    RunTimers()
    Equal(Redraws() - drawn, 1, "redraw: and are one redraw")
    Equal(Redraws("PLAYER_EQUIPMENT_CHANGED") - drawnForGear, 1, "redraw: filed under the newest refresh before it")
    Equal(Redraws("NEW_TOY_ADDED") - drawnForToy, 0, "redraw: and not under the ones it was started over by")
    clock = clock + 1
    RunTimers()
    Equal(Redraws() - drawn, 1, "redraw: once")

    Fire("NEW_TOY_ADDED")
    clock = clock + 0.11
    RunTimers()
    Fire("NEW_TOY_ADDED")
    clock = clock + 0.11
    RunTimers()
    Equal(Redraws() - drawn, 3, "redraw: two refreshes apart are two redraws")
    Equal(Redraws("NEW_TOY_ADDED") - drawnForToy, 2, "redraw: each under its own")

    -- In a fight the caches are emptied and the windows wait for its end.
    local notInCombat = InCombatLockdown
    InCombatLockdown = function() return true end
    Fire("NEW_TOY_ADDED")
    Fire("NEW_TOY_ADDED")
    clock = clock + 1
    RunTimers()
    Equal(Redraws() - drawn, 3, "redraw: a refresh in a fight draws nothing")
    InCombatLockdown = notInCombat
    Fire("PLAYER_REGEN_ENABLED")
    clock = clock + 0.11
    RunTimers()
    Equal(Redraws() - drawn, 4, "redraw: the fight's end is one redraw for all of them")
    Equal(Redraws("after combat"), 1, "redraw: under the refresh that the fight's end makes")
    Equal(Refreshes() - asked, 8, "redraw: eight refreshes were four redraws")

    local redrawLine
    for _, line in ipairs(CaerdonCounters:GetReportLines()) do
        if line.text == ("the windows drew again %d times"):format(Redraws()) then redrawLine = true end
    end
    Check(redrawLine, "redraw: the export says how often the windows drew")
    Equal(#errors, 0, "redraw: no error reached the error handler")
end

------------------------------------------------------------------------------------------
-- 3. What the client was asked to load
------------------------------------------------------------------------------------------

do
    local listener = CaerdonItemEventListener
    local order = {}
    local AskLoad = AddonChunk("CaerdonWardrobe", "features/Merchant.lua", [[
local listener, id, onLoad, onFail = ...
listener:AddCallback(id, onLoad, onFail)
]])
    -- Two callers for one item: one question.
    AskLoad(listener, 501, function() order[#order + 1] = "501a" end, function() end)
    AskLoad(listener, 501, function()
        order[#order + 1] = "501b"
        -- What an answer makes the addon ask for next belongs to the first asker, although
        -- this stack holds none of its code.
        listener:AddCallback(502, function() order[#order + 1] = "502" end, function() end)
    end, function() end)
    clock = clock + 0.4
    Answer(501, true)
    clock = clock + 0.2
    Answer(502, true)
    -- Refused, twice.
    AskLoad(listener, 216679, function() end, function() order[#order + 1] = "refused" end)
    clock = clock + 0.3
    Answer(216679, false)
    AskLoad(listener, 216679, function() end, function() order[#order + 1] = "refused" end)
    Answer(216679, false)
    -- Answered from inside the question.
    answerAtOnce[503] = true
    AskLoad(listener, 503, function() order[#order + 1] = "503" end, function() end)
    -- Never answered.
    AskLoad(listener, 504, function() end, function() end)
    clock = clock + 5
    -- Through the queue: the feature's name.
    AskFor({ NewItem(505, { cached = false }) })
    Tick(3)

    Equal(table.concat(order, ","), "501a,501b,502,refused,refused,503", "loads: every callback ran, in order")
    local loads = CaerdonCounters:GetReport().itemLoads
    Equal(loads.asked, 7, "loads: seven questions put to the client")
    Equal(loads.callers, 8, "loads: eight callers waited for them")
    Equal(loads.loaded, 3, "loads: three loaded")
    Equal(loads.failed, 2, "loads: two refused")
    Equal(#loads.unanswered, 2, "loads: two not answered")
    Near(loads.slowestSeconds, 0.4, "loads: the slowest answer")
    local merchant = loads.by["features/Merchant.lua"] or {}
    Equal(merchant.asked, 6, "loads: the feature file asked six times, the chained one included")
    Equal(merchant.failed, 2, "loads: both refusals are the feature file's")
    Equal(loads.by.Bags and loads.by.Bags.asked, 1, "loads: the queue's question is filed under the feature")
    Equal(#loads.failures, 1, "loads: one entry for the item refused twice")
    local failure = loads.failures[1] or {}
    Equal(failure.id, 216679, "loads: the refused item")
    Equal(failure.times, 2, "loads: refused twice")
    Equal(failure.where, "features/Merchant.lua:2", "loads: the line that asked")
    Equal(failure.phase, "in play", "loads: asked after the bags had reported")
    Near(failure.after, 0.3, "loads: the refusal came after 0.3 s")
    Equal(loads.unanswered[1].id, 504, "loads: the unanswered item")
    Equal(loads.unanswered[2].id, 505, "loads: the queue's item is still waiting")
    Check(CaerdonCounters.requester == nil, "loads: no requester is left set")

    Answer(505, true)
    Tick(6)
    Equal(#CaerdonCounters:GetReport().itemLoads.unanswered, 1, "loads: the queue's item was answered")
    Check(IsPlain(CaerdonCounters:GetReport()), "loads: the report is plain data")
    Check(#CaerdonCounters:GetReportLines() > 6, "loads: the export lines are built")
    Equal(#errors, 0, "loads: no error reached the error handler")
    for _, message in ipairs(errors) do print("  error: " .. message) end
end

-- A load asked before the toon is in the world.
StartSession({ debug = false })
do
    AddonChunk("CaerdonWardrobe", "features/Bank.lua", "CaerdonItemEventListener:AddCallback(77, function() end, function() end)")()
    Answer(77, false)
    Fire("PLAYER_ENTERING_WORLD", true, false)
    AddonChunk("CaerdonWardrobe", "features/Bank.lua", "CaerdonItemEventListener:AddCallback(78, function() end, function() end)")()
    Answer(78, false)
    local failed = CaerdonCounters:GetReport().itemLoads.failures
    Equal(failed[1].phase, "before the world", "phase: refused before the world")
    Equal(failed[2].phase, "before the bags", "phase: refused before the bags reported")
end

------------------------------------------------------------------------------------------
-- 4. The profile switched on: exact figures
------------------------------------------------------------------------------------------

StartSession({ debug = false })
do
    CaerdonCounters:SetProfile(true)
    Check(CaerdonCounters.on == true, "profile: on by its own switch")
    -- The test addon hooks the same function later; its time must stay out.
    hooksecurefunc(CaerdonWardrobe, "ProcessItem", function() Spend(10, 100) end)

    local items = {}
    for index = 1, 45 do items[index] = NewItem(2000 + index) end
    AskFor(items)
    Tick(50)

    local report = CaerdonCounters:GetReport()
    local profile = report.profile
    Check(profile.attached and profile.on, "profile: attached and on")
    Equal(#profile.missing, 0, "profile: every function was found")

    local function Expect(label, calls, ms, ownMs, kb, ownKB)
        local entry = Function(report, label)
        Equal(entry.calls, calls, "profile: " .. label .. " calls")
        Near(entry.ms, ms, "profile: " .. label .. " ms")
        Near(entry.ownMs, ownMs, "profile: " .. label .. " own ms")
        Near(entry.kb, kb, "profile: " .. label .. " KB")
        Near(entry.ownKB, ownKB, "profile: " .. label .. " own KB")
        Equal(entry.collected, 0, "profile: " .. label .. " collector")
    end
    Expect("UpdateButton", 45, 157.5, 0, 405, 0)
    Expect("ClearButton", 45, 90, 0, 225, 0)
    -- A draw: the status 7.75 ms and 36 KB, the display rules once 0.25 and 3, the two halves
    -- of the drawing 1.5 and 4, 0.5 and 1.
    Expect("ProcessItem", 45, 450, 0, 1980, 0)
    Expect("GetCaerdonStatus (computed)", 45, 348.75, 45, 1620, 90)
    Expect("GetTooltipData", 45, 90, 90, 360, 360)
    Expect("GetBindingStatus", 45, 22.5, 22.5, 45, 45)
    Expect("GetCopyStatus", 45, 11.25, 11.25, 0, 0)
    -- Once per item: the status computes it, and the draw reads what the status hands back.
    Expect("GetTransmogInfo", 45, 180, 135, 1125, 900)
    Expect("GetEquipmentSets", 45, 45, 45, 225, 225)
    Expect("SetItemButtonStatus", 135, 202.5, 202.5, 540, 540)
    Expect("SetItemButtonBindType", 90, 45, 45, 90, 90)
    -- Once per draw: ProcessItem asks and hands the answer to both halves.
    Expect("GetDisplayInfoInternal", 45, 11.25, 11.25, 135, 135)
    Equal(Function(report, "GetCaerdonStatus (cache hit)").calls, 0, "profile: no cache hit yet")
    Near(Function(report, "ProcessItem").worstMs, 10, "profile: the worst draw")

    Equal(profile.queueWait.count, 45, "profile: every draw had waited in the queue")
    Check(profile.queueWait.meanMs > 100 and profile.queueWait.worstMs >= profile.queueWait.meanMs,
        "profile: the wait runs from the request to the draw, frames later for the last ones")
    Equal(profile.drains.count, 1, "profile: one drain")
    -- A pass also holds the test addon's hook: a draw of 10 ms plus 10 ms, which is more than
    -- a frame's budget, so every pass draws one item and the last pass is the last draw.
    Equal(profile.drains.passes, 45, "profile: a pass per draw, and none that finds nothing")
    Near(profile.drains.ms, 450 + 450, "profile: the drain's time is the passes' own")
    Near(profile.drains.worstPassMs, 20, "profile: the longest pass drew one")
    Near(profile.drains.kb, 1980 + 4500, "profile: the drain's memory")
    Equal(profile.drains.recent[1].draws, 45, "profile: the drain's draws")

    -- Outside a draw: three item tooltips and two changes in the bags, called the way the
    -- addon calls them (looked up on their table at each call).
    Equal(Function(report, "OnTooltipItem").calls, 0, "outside: nothing counted before a tooltip")
    for _ = 1, 3 do
        Session.outside.api:OnTooltipItem()
        Session.outside.tooltip:OnTooltipSetItem()
    end
    CaerdonAuctionValue:OnBagsChanged()
    CaerdonAuctionValue:OnBagsChanged()
    report = CaerdonCounters:GetReport()
    Expect("OnTooltipItem", 3, 0.75, 0.75, 3, 3)
    Expect("OnTooltipSetItem", 3, 1.5, 1.5, 6, 6)
    Expect("OnBagsChanged", 2, 0.25, 0.25, 0, 0)

    -- The same items again without a refresh: answered from the cache.
    AskFor(items)
    Tick(50)
    report = CaerdonCounters:GetReport()
    local hit = Function(report, "GetCaerdonStatus (cache hit)")
    Equal(hit.calls, 45, "profile: 45 cache hits")
    Near(hit.ms, 45 * 0.35, "profile: a cache hit with its copy status")
    Near(hit.ownMs, 4.5, "profile: a cache hit's own time")
    Equal(Function(report, "GetCaerdonStatus (computed)").calls, 45, "profile: computed stays at 45")
    Equal(Function(report, "UpdateButton").calls, 90, "profile: 90 requests")
    Equal(Function(report, "ClearButton").calls, 45, "profile: the same item is not cleared again")
    Equal(report.profile.drains.count, 2, "profile: a second drain")

    -- Tooltip not ready once, then drawn by the retry timer; an item with no link.
    CaerdonCounters:Reset()
    local slow, bare = NewItem(3001, { notReady = 1 }), NewItem(3002, { noLink = true })
    Session.buttons = {}
    AskFor({ slow, bare })
    Tick(30)
    report = CaerdonCounters:GetReport()
    Equal(Function(report, "GetCaerdonStatus (tooltip not ready)").calls, 1, "outcomes: one not ready")
    Equal(Function(report, "GetCaerdonStatus (no link)").calls >= 1, true, "outcomes: no link counted apart")
    Equal(Function(report, "GetCaerdonStatus (computed)").calls, 1, "outcomes: computed once, on the retry")
    Equal(Function(report, "GetCaerdonStatus (cache hit)").calls, 0, "outcomes: Reset started from zero")

    -- The collector running inside a call.
    CaerdonCounters:Reset()
    Session.buttons = {}
    AskFor({ NewItem(3003, { collectorRuns = true }) })
    Tick(8)
    report = CaerdonCounters:GetReport()
    Equal(Function(report, "GetTooltipData").collected, 1, "collector: the call it ran in is marked")
    Equal(Function(report, "GetTooltipData").kb, 0, "collector: that sample adds no memory")
    Equal(Function(report, "ProcessItem").collected, 1, "collector: so is its caller")
    Equal(report.profile.drains.collected, 1, "collector: and the pass")
    Check(Function(report, "GetTransmogInfo").kb == 25, "collector: the calls beside it still count")

    -- An error inside a wrapped function: the queue hands it to the error handler and goes
    -- on, and so does the counting.
    CaerdonCounters:Reset()
    Session.buttons = {}
    AskFor({ NewItem(3004, { raises = true }) })
    local ok = realPcall(Tick, 8)
    Check(ok, "error: the queue does not raise it")
    Equal(#errors, 1, "error: it went to the error handler")
    Check(tostring(errors[1]):find("the status code raised an error", 1, true) ~= nil, "error: with its message")
    errors = {}
    Session.buttons = {}
    AskFor({ NewItem(3005) })
    Tick(8)
    report = CaerdonCounters:GetReport()
    Near(Function(report, "ProcessItem").ms, 10, "error: the next draw is timed right")
    Near(Function(report, "ProcessItem").ownMs, 0, "error: with nothing left over from the failed call")

    -- An error after the call had said how it ended (a cache hit whose copy raises): what the
    -- queue does about a caught error must take that mark away too, or the next call at the
    -- same depth is filed under it. Asked directly, since in the queue another wrapped call
    -- usually comes between and uses the mark up.
    CaerdonCounters:Reset()
    Equal(statusCache[3005] and statusCache[3005][1], "own", "mark: the item's status is in the cache (control)")
    local failing = NewItem(3005, { raisesInCopy = true })
    Check(not realPcall(failing.GetCaerdonStatus, failing), "mark: the cache hit raises (control)")
    CaerdonCounters:Unwound()
    local fresh = NewItem(3007)
    fresh:GetCaerdonStatus()
    report = CaerdonCounters:GetReport()
    Equal(Function(report, "GetCaerdonStatus (computed)").calls, 1, "mark: the next computed status is counted as computed")
    Equal(Function(report, "GetCaerdonStatus (cache hit)").calls, 0, "mark: and not as the failed call's cache hit")

    -- And the queue does that: the same item on the same button, computed anew after the
    -- failed cache hit, with no other wrapped call at that depth in between.
    CaerdonCounters:Reset()
    Session.buttons = {}
    AskFor({ NewItem(3005, { raisesInCopy = true }) })
    Tick(8)
    Equal(#errors, 1, "mark, queue: the failed cache hit went to the error handler")
    errors = {}
    statusCache = {}
    AskFor({ NewItem(3005) })
    Tick(8)
    report = CaerdonCounters:GetReport()
    Equal(Function(report, "GetCaerdonStatus (computed)").calls, 1, "mark, queue: the next computed status is counted as computed")
    Equal(Function(report, "GetCaerdonStatus (cache hit)").calls, 0, "mark, queue: and not as a cache hit")

    -- Switched off: the figures stay, nothing is added.
    CaerdonCounters:SetProfile(false)
    Check(CaerdonCounters.on == false, "switch: off")
    local calls = Function(CaerdonCounters:GetReport(), "UpdateButton").calls
    Session.buttons = {}
    AskFor({ NewItem(3006) })
    Tick(8)
    Equal(Function(CaerdonCounters:GetReport(), "UpdateButton").calls, calls, "switch: nothing counted while off")
    Check(IsPlain(CaerdonCounters:GetReport()), "profile: the report is plain data")
    local lines = CaerdonCounters:GetReportLines()
    Check(#lines > 10, "profile: the export lines are built")
    Equal(#errors, 0, "profile: no error reached the error handler")
end

-- A function the counters name that is gone (renamed in a refactor).
StartSession({ debug = false })
do
    CaerdonCounters:SetProfile(true)
    local profile = CaerdonCounters:GetReport().profile
    Equal(#profile.missing, 0, "missing: nothing is missing while every function is there (control)")
end
StartSession({ debug = false, dropEquipmentSets = true })
do
    CaerdonCounters:SetProfile(true)
    local profile = CaerdonCounters:GetReport().profile
    Equal(profile.missing[1], "CaerdonEquipmentMixin.GetEquipmentSets", "missing: the function that is gone is named")
    AskFor({ NewItem(4001) })
    Tick(8)
    Equal(Function(CaerdonCounters:GetReport(), "ProcessItem").calls, 1, "missing: the others are counted")
    local found = false
    for _, line in ipairs(CaerdonCounters:GetReportLines()) do
        found = found or line.text:find("not found, so not counted: CaerdonEquipmentMixin.GetEquipmentSets", 1, true) ~= nil
    end
    Check(found, "missing: the export says so")
end

------------------------------------------------------------------------------------------
-- 5. The test addon: attach before its hooks, a counted pass, the login record, the reader
------------------------------------------------------------------------------------------

StartSession({ debug = false })
do
    local T = {}
    UnitFullName = function() return "Mock", "Realm" end
    UnitClass = function() return "Hunter", "HUNTER" end
    UnitRace = function() return "Dwarf", "Dwarf" end
    UnitFactionGroup = function() return "Alliance" end
    UnitLevel = function() return 29 end
    UnitGUID = function() return "Player-1-1" end
    GetProfessions = function() end
    GetRealmName = function() return "Realm" end
    GetLocale = function() return "enUS" end
    GetFramerate = function() return 60 end
    WOW_PROJECT_ID = 18
    CaerdonAPI.GetClientFlavor = function() return "Forever" end
    C_AddOns = {
        GetNumAddOns = function() return 0 end,
        GetAddOnMetadata = function() return "v5.0.0" end,
    }
    C_AddOnProfiler = { GetAddOnMetric = function() return 0.5 end, IsEnabled = function() return true end }
    UpdateAddOnMemoryUsage = function() end
    GetAddOnMemoryUsage = function() return memory end

    local untouched = CaerdonWardrobe.ProcessItem
    LoadAddonFile("CaerdonWardrobe_Tests", "Core.lua", "CaerdonWardrobe_Tests", T)
    Check(CaerdonWardrobe.ProcessItem ~= untouched, "tests: loading the test addon wraps the functions")
    Check(CaerdonCounters.on == false, "tests: and leaves the profile off")
    T.counters = { refreshItems = 0, processItem = 0 }
    hooksecurefunc(CaerdonWardrobe, "RefreshItems", function() T.counters.refreshItems = T.counters.refreshItems + 1 end)
    -- The two hooks of the tests' Journal.lua, as far as a timing reads them.
    hooksecurefunc(CaerdonWardrobe, "UpdateButton", function(_, _, item)
        if T.NoteTimedRequest then
            T.NoteTimedRequest("Bags", item == nil or item:IsItemEmpty())
        end
    end)
    hooksecurefunc(CaerdonWardrobe, "ProcessItem", function(_, button)
        T.counters.processItem = T.counters.processItem + 1
        if T.NoteTimedDraw then
            T.NoteTimedDraw("Bags", button)
        end
        Spend(10)
    end)
    T.IsOpen = function() return false end
    T.ReadProfiler = function() return {} end
    T.RefusedItems = function() return { distinct = 0, items = {} } end
    LoadAddonFile("CaerdonWardrobe_Tests", "Plan.lua", "CaerdonWardrobe_Tests", T)
    LoadAddonFile("CaerdonWardrobe_Tests", "Counters.lua", "CaerdonWardrobe_Tests", T)
    LoadAddonFile("CaerdonWardrobe_Tests", "Timing.lua", "CaerdonWardrobe_Tests", T)
    -- As saved by a session that asked for this login to be profiled, and that a reload cut
    -- short in the middle of a timing with Enable debug suspended.
    CaerdonWardrobeTestsDB = { schema = 1, switches = { profileLogin = true, debugSuspended = true } }
    Fire("ADDON_LOADED", "CaerdonWardrobe_Tests")
    Check(CaerdonCounters.on == true, "tests: a login asked for is profiled from the tests' load")
    Check(CaerdonWardrobeConfig.Debug.Enabled == true, "tests: a suspended Enable debug is put back at the next load")
    Check(T.db.switches.debugSuspended == nil and T.db.switches.profileLogin == nil, "tests: both notes are cleared")
    Fire("PLAYER_LOGIN")

    -- A feature that draws its buttons again on a refresh, as the rule asks.
    local items = {}
    for index = 1, 12 do items[index] = NewItem(5000 + index) end
    Session.feature.Refresh = function() AskFor(items) end
    AskFor(items)
    Fire("PLAYER_ENTERING_WORLD", true, false)
    Tick(60)
    local login = T.db.logins[1]
    Check(login ~= nil and login.core ~= nil, "tests: the login record holds the core's ledger")
    Check(login and login.core.milestones[1].name == "addonLoaded", "tests: with its milestones")
    Check(login and login.debugOn == true, "tests: the login record says Enable debug was on")
    local loginDraws
    for _, entry in ipairs(login and login.profile and login.profile.functions or {}) do
        if entry.label == "ProcessItem" then loginDraws = entry.calls end
    end
    -- Twelve asked for, and the twelve again when the watcher takes its first reading of the
    -- world (CaerdonRefresh.lua), which counts as a change.
    Equal(loginDraws, 24, "tests: the login's profile holds its draws")
    Check(CaerdonCounters.on == false, "tests: the profile is off once the login record is written")

    -- A timing with Enable debug and the profile both on: it runs without either and puts
    -- both back.
    CaerdonCounters:SetProfile(true)
    local seen = {}
    -- Four of the twelve buttons are where nobody sees them (a window parked under a hidden
    -- parent), and the window also asks for a slot with nothing in it.
    for index = 1, 12 do
        Session.buttons[index].IsVisible = function() return index > 4 end
    end
    local emptySlot = {}
    Session.feature.Refresh = function()
        seen[#seen + 1] = { debug = CaerdonWardrobeConfig.Debug.Enabled, profile = CaerdonCounters.on }
        AskFor(items)
        Ask(emptySlot, nil, Session.feature)
    end
    T.GetPlan().timing.countedRuns = 2
    T.RunRefreshTiming("bags", 2)
    Tick(200)
    local record = T.db.timing[1]
    Check(record ~= nil, "tests: a timing record was written")
    Equal(record and record.medianDraws, 12, "tests: twelve draws per refresh")
    local window = record and record.runs[1].byFeature and record.runs[1].byFeature.Bags or {}
    Equal(window.draws, 12, "tests: the window's draws in a timed refresh")
    Equal(window.requests, 13, "tests: its requests, the one for the empty slot among them")
    Equal(window.empty, 1, "tests: the request for an empty slot is named")
    Equal(window.unseen, 4, "tests: the draws on buttons nobody sees are counted")
    Check(window.firstMs ~= nil and window.lastMs ~= nil and window.lastMs >= window.firstMs,
        "tests: with the times of its first and last draw")
    Check(record and record.runs[1].seconds and record.runs[1].seconds > 0 and record.runs[1].frames > 0,
        "tests: a run says how long it took and in how many frames")
    Equal(#seen, 4, "tests: four refreshes ran")
    Check(seen[1] and not seen[1].debug and not seen[1].profile and not seen[2].debug and not seen[2].profile,
        "tests: the measured refreshes ran without Enable debug and without the profile")
    Check(seen[3] and not seen[3].debug and seen[3].profile and seen[4].profile,
        "tests: the counted ones with the profile, still without Enable debug")
    Check(CaerdonWardrobeConfig.Debug.Enabled == true, "tests: Enable debug is back on afterwards")
    Check(CaerdonCounters.on == true, "tests: and the profile is as it was")
    CaerdonCounters:SetProfile(false)
    local counted = record and record.counted
    Check(counted ~= nil and counted.runs == 2, "tests: two counted refreshes")
    if counted then
        local draws
        for _, entry in ipairs(counted.profile.functions) do
            if entry.label == "ProcessItem" then draws = entry end
        end
        Equal(draws and draws.calls, 24, "tests: 24 draws counted in the two")
        -- Each refresh computes afresh: 10 ms a draw, without the 10 ms of the tests' hook.
        Near(draws and draws.ms, 24 * 10, "tests: the tests' own hook is not in the figure")
        Equal(counted.profile.drains.count, 2, "tests: two drains")
    end
    local triggers = T.RefreshTriggers()
    local forcedLabel
    for trigger in pairs(triggers or {}) do
        if trigger:find("^CaerdonWardrobe_Tests/Timing%.lua:%d+$") then forcedLabel = trigger end
    end
    Equal(forcedLabel and triggers[forcedLabel], 4, "tests: the forced refreshes are named by the tests' line")
    local diff = T.DiffTriggers({ a = 1, b = 2 }, { a = 1, b = 5, c = 1 })
    Check(diff.a == nil and diff.b == 3 and diff.c == 1, "tests: DiffTriggers")

    -- A window opened after a refresh it was closed for: the refresh asks for nothing, the
    -- opening (by hand in the client, here between two frames) asks for all twelve.
    Session.feature.Refresh = function() end
    T.StaleBagButtons = function() return 12, { { feature = "Bags", bag = 0, slot = 3 } } end
    local timings = #T.db.timing
    T.RunOpenTiming("bags")
    Tick(40)
    Equal(#T.db.timing, timings, "open: the job waits for the window")
    AskFor(items)
    Tick(40)
    local opened = T.db.timing[timings + 1]
    Check(opened ~= nil and opened.kind == "open", "open: a record of its own kind is written")
    if opened then
        Equal(opened.closed and opened.closed.draws, 0, "open: the refresh with the window closed drew nothing")
        Equal(opened.draws, 12, "open: the opening drew the twelve")
        Equal(opened.byFeature and opened.byFeature.Bags and opened.byFeature.Bags.requests, 12, "open: after twelve requests")
        Check(opened.firstDrawMs ~= nil and opened.firstDrawMs > 0 and opened.lastDrawMs >= opened.firstDrawMs,
            "open: with the icon times counted from the first request")
        Check(opened.frames > 0 and not opened.timedOut, "open: it ends when the queue is idle")
        Equal(opened.staleCount, 1, "open: buttons the refresh did not reach are counted")
        Check(IsPlain(opened), "open: the record is plain data")
    end
    Check(CaerdonWardrobeConfig.Debug.Enabled == true, "open: Enable debug is back on afterwards")
    -- Nobody opens anything.
    T.RunOpenTiming("bags")
    Tick(600)
    local unopened = T.db.timing[timings + 2]
    Check(unopened ~= nil and unopened.nothingAsked == true and unopened.draws == nil,
        "open: a window that is never opened is recorded as that")
    Check(T.timingRun == nil, "open: and the run is closed")

    T.CountersCommand("")
    Equal(#T.db.counters, 1, "tests: /cwtest counters stores a report")
    T.CountersCommand("on")
    Check(CaerdonCounters.on == true, "tests: /cwtest counters on")
    T.CountersCommand("reset")
    T.CountersCommand("off")
    Check(CaerdonCounters.on == false, "tests: /cwtest counters off")
    T.CountersCommand("login")
    Check(T.db.switches.profileLogin == true, "tests: /cwtest counters login arms the next login")

    Fire("PLAYER_LOGOUT")
    local totals = T.db.events["1.60.1.70938"]
    -- The four of the refresh timing and one for each of the two open timings.
    Check(totals and totals.triggers and totals.triggers[forcedLabel] == 6,
        "tests: the triggers are added to the build's totals on logout")
    -- The session's own record: the build's totals run over every version of the addon.
    local session = T.db.sessions[#T.db.sessions]
    Check(session and type(session.minutes) == "number" and session.minutes > 0, "tests: the session's record holds its minutes on logout")
    Check(session and session.refreshes and session.refreshes.by[forcedLabel] == 6, "tests: and its refreshes by trigger")
    Check(session and session.refreshes and session.refreshes.by.pvp == 1, "tests: the watcher's among them, by its name")
    -- The core's watches on a client without housing: skills, pvp, level.
    Check(session and session.refreshes and #session.refreshes.watched == 3 and session.refreshes.watched[2].name == "pvp"
        and session.refreshes.watched[2].changes == 1, "tests: with what each watch saw")
    Equal(#T.db.errors, 0, "tests: no error of the tests' own")
    Equal(#errors, 0, "tests: no error reached the error handler")

    if DUMP then
        local function Serialize(value, indent)
            if type(value) ~= "table" then
                return type(value) == "string" and realFormat("%q", value) or tostring(value)
            end
            local parts = {}
            for key, item in pairs(value) do
                local name = type(key) == "string" and realFormat("[%q]", key) or ("[" .. tostring(key) .. "]")
                parts[#parts + 1] = indent .. "  " .. name .. " = " .. Serialize(item, indent .. "  ") .. ","
            end
            return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent .. "}"
        end
        totals.minutes = 10
        totals.counts = { RefreshItems = 4 }
        local file = assert(io.open(DUMP, "wb"))
        file:write("CaerdonWardrobeTestsDB = " .. Serialize(T.db, "") .. "\n")
        file:close()
    end
end

------------------------------------------------------------------------------------------
-- 6. Containment: one failure leaves its neighbours working
------------------------------------------------------------------------------------------

do
    local inits, heard, refreshed = {}, {}, {}
    local function Feature(name, fields)
        local mixin = {}
        function mixin:GetName() return name end
        function mixin:Init()
            inits[name] = (inits[name] or 0) + 1
            return { "CONTAINMENT_TEST" }
        end
        function mixin:CONTAINMENT_TEST(value)
            heard[name] = value
        end
        function mixin:Refresh() refreshed[name] = (refreshed[name] or 0) + 1 end
        function mixin:GetDisplayInfoInternal() return {} end
        for key, value in pairs(fields or {}) do mixin[key] = value end
        return mixin
    end
    local good = { "GoodA", "GoodB", "GoodC", "GoodD", "GoodE", "GoodF" }
    local features = {
        Feature("BrokenInit", { Init = function() error("the Init of BrokenInit raised an error") end }),
        Feature("BrokenRefresh", { Refresh = function() error("the Refresh of BrokenRefresh raised an error") end }),
        Feature("BrokenHandler", { CONTAINMENT_TEST = function() error("the handler of BrokenHandler raised an error") end }),
    }
    for _, name in ipairs(good) do features[#features + 1] = Feature(name) end

    local function Reached(message)
        for _, text in ipairs(errors) do
            if text:find(message, 1, true) then
                return true
            end
        end
        return false
    end

    -- A feature's Init raises while the addon starts.
    local started, startError = realPcall(StartSession, { debug = false, features = features })
    Check(started, "containment: the addon starts although one feature's Init raises (" .. tostring(startError) .. ")")
    if started then
        Equal(#errors, 1, "containment, Init: one error went to the error handler")
        Check(Reached("the Init of BrokenInit raised an error"), "containment, Init: with its message")
        Check(CaerdonWardrobe:GetFeature("BrokenInit").initFinished == false, "containment, Init: the report can tell which one it was")
        for _, name in ipairs(good) do
            Check(inits[name] == 1 and CaerdonWardrobe:GetFeature(name).initFinished == true,
                "containment, Init: " .. name .. " started")
        end
        Check(CaerdonWardrobe:GetFeature("Bags").initFinished == true, "containment, Init: so did the bags")
        Check(CaerdonWardrobe.events.CONTAINMENT_TEST == true, "containment, Init: the others' event is registered")

        -- A feature's event handler raises.
        errors = {}
        local fired = realPcall(Fire, "CONTAINMENT_TEST", 7)
        Check(fired, "containment, event: the event does not raise")
        Equal(#errors, 1, "containment, event: one error went to the error handler")
        Check(Reached("the handler of BrokenHandler raised an error"), "containment, event: with its message")
        for _, name in ipairs(good) do
            Equal(heard[name], 7, "containment, event: " .. name .. " heard it")
        end
        Check(heard.BrokenInit == nil, "containment, event: a feature whose Init raised gets no events")

        -- A feature's Refresh raises.
        errors = {}
        CaerdonWardrobe:RefreshItems()
        local ticked = realPcall(Tick, 3)
        Check(ticked, "containment, refresh: the refresh does not raise")
        Equal(#errors, 1, "containment, refresh: one error went to the error handler")
        Check(Reached("the Refresh of BrokenRefresh raised an error"), "containment, refresh: with its message")
        for _, name in ipairs(good) do
            Equal(refreshed[name], 1, "containment, refresh: " .. name .. " was refreshed")
        end

        -- One item of a batch raises while it is drawn: the others are drawn, the queue lives.
        errors = {}
        local drawn, clearedButtons = {}, {}
        local setStatus, clearButton = CaerdonWardrobe.SetItemButtonStatus, CaerdonWardrobe.ClearButton
        function CaerdonWardrobe:SetItemButtonStatus(button, item, feature, locationInfo, drawOptions, status, ...)
            if item and status ~= "waiting" then
                drawn[item.id] = (drawn[item.id] or 0) + 1
            end
            return setStatus(self, button, item, feature, locationInfo, drawOptions, status, ...)
        end
        function CaerdonWardrobe:ClearButton(button)
            clearedButtons[button] = (clearedButtons[button] or 0) + 1
            return clearButton(self, button)
        end
        local batch = {}
        for index = 1, 9 do
            batch[index] = NewItem(6000 + index, { raises = (index == 2 or index == 5 or index == 9) })
        end
        Session.buttons = {}
        AskFor(batch)
        for _, button in pairs(Session.buttons) do clearedButtons[button] = nil end
        local drained = realPcall(Tick, 8)
        Check(drained, "containment, draw: the queue does not raise")
        Equal(#errors, 3, "containment, draw: each failed item's error went to the error handler")
        for index = 1, 9 do
            if batch[index].raises then
                Check(drawn[6000 + index] == nil, "containment, draw: failed item " .. index .. " drew nothing")
                Equal(clearedButtons[Session.buttons[index]], 1, "containment, draw: and its button was cleared")
            else
                Equal(drawn[6000 + index], 1, "containment, draw: item " .. index .. " was drawn")
                Check(clearedButtons[Session.buttons[index]] == nil, "containment, draw: and its button left alone")
            end
        end
        errors = {}
        Session.buttons = {}
        AskFor({ NewItem(6100) })
        Tick(8)
        Equal(drawn[6100], 1, "containment, draw: the queue draws the next request")
        Equal(#errors, 0, "containment, draw: with no error")
    end
end

print(("%d checks, %d failed"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
