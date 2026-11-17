-- Caerdon Wardrobe Tests: a development addon, never packaged.
--
-- It runs in the client next to the addon, proves what can only be proven there, and writes
-- what it found to its saved variables (CaerdonWardrobeTestsDB). That file is how a result
-- leaves the game: the client writes it on /reload and on logout, and tools/test-results.lua
-- reads it from the WTF folder.
--
-- This file: the shared table, who and where we are, the saved results, and the job runner.

local ADDON_NAME, T = ...

CaerdonWardrobeTests = T

T.NAME = ADDON_NAME
T.SUBJECT = "CaerdonWardrobe" -- the addon under test
T.SCHEMA = 1

------------------------------------------------------------------------------------------
-- Output
------------------------------------------------------------------------------------------

local PREFIX = "|cff33ccffCaerdon tests:|r "

-- The stopwatch, in milliseconds. Not debugprofilestop(): any addon can restart that timer
-- with debugprofilestart(), and a measurement that spans frames would then be wrong.
function T.Milliseconds()
    return GetTimePreciseSec() * 1000
end

function T.Print(message, ...)
    if select("#", ...) > 0 then
        message = message:format(...)
    end
    print(PREFIX .. message)
end

------------------------------------------------------------------------------------------
-- Plain data
------------------------------------------------------------------------------------------

local MAX_KEYS = 200

-- A copy that the saved variables can hold: strings, numbers, booleans and tables of them.
-- Anything else becomes a "<kind>" marker, so a result never drags a frame or a function
-- into the file. A secret value cannot be stored or compared, so it becomes "<secret>".
function T.Plain(value, depth)
    if issecretvalue(value) then
        return "<secret>"
    end
    local kind = type(value)
    if kind == "string" or kind == "boolean" or kind == "nil" then
        return value
    elseif kind == "number" then
        -- NaN and the infinities do not survive the file.
        if value ~= value or value == math.huge or value == -math.huge then
            return "<" .. tostring(value) .. ">"
        end
        return value
    elseif kind ~= "table" then
        return "<" .. kind .. ">"
    end
    if type(rawget(value, 0)) == "userdata" then
        return "<frame>"
    end
    depth = depth or 6
    if depth <= 0 then
        return "<table>"
    end
    local copy, count = {}, 0
    for key, item in pairs(value) do
        count = count + 1
        if count > MAX_KEYS then
            copy["<more>"] = true
            break
        end
        -- Methods are left out: a color or a location is a mixin, and its functions say nothing.
        if issecretvalue(item) or type(item) ~= "function" then
            local keyKind = type(key)
            if issecretvalue(key) then
                key = "<secret>"
            elseif keyKind ~= "string" and keyKind ~= "number" then
                key = "<" .. keyKind .. ">"
            end
            copy[key] = T.Plain(item, depth - 1)
        end
    end
    return copy
end

-- Appends to a list that keeps only its newest entries.
function T.Push(list, entry, limit)
    list[#list + 1] = entry
    while #list > limit do
        table.remove(list, 1)
    end
end

function T.SortedKeys(map)
    local keys = {}
    for key in pairs(map) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then
            return a < b
        end
        return tostring(a) < tostring(b)
    end)
    return keys
end

------------------------------------------------------------------------------------------
-- Client and toon
------------------------------------------------------------------------------------------

-- flavor is "retail" or "forever" (the names the static check uses); build is "1.60.1.70938".
function T.GetClient()
    if not T.client then
        local version, build, _, toc = GetBuildInfo()
        local flavor = CaerdonAPI:GetClientFlavor()
        T.client = {
            flavor = string.lower(flavor),
            version = version,
            build = version .. "." .. build,
            toc = toc,
            projectID = WOW_PROJECT_ID,
            locale = GetLocale(),
        }
    end
    return T.client
end

local function ReadProfessions()
    local found = {}
    local indexes = { GetProfessions() } -- nil where the toon has none: read by position
    for position = 1, 6 do
        local index = indexes[position]
        if index then
            local name, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
            found[#found + 1] = { name = name, rank = rank, skillLine = skillLine, primary = position <= 2 }
        end
    end
    return found
end

-- Read fresh on every call: level and professions change during a session.
--
-- signature is what a toon-dependent result is valid for: class, race, faction, level and
-- primary professions. A result recorded under another signature is stale.
function T.GetToon()
    local name, realm = UnitFullName("player")
    local _, class = UnitClass("player")
    local _, race = UnitRace("player")
    local faction = UnitFactionGroup("player")
    local level = UnitLevel("player")
    local professions = ReadProfessions()
    local primary = {}
    for _, profession in ipairs(professions) do
        if profession.primary then
            primary[#primary + 1] = tostring(profession.skillLine or profession.name)
        end
    end
    table.sort(primary)
    return {
        key = ("%s-%s"):format(name or "?", realm or GetRealmName() or "?"),
        class = class,
        race = race,
        faction = faction,
        level = level,
        professions = professions,
        signature = ("%s/%s/%s/%d/%s"):format(tostring(class), tostring(race), tostring(faction), level or 0,
            table.concat(primary, "+")),
    }
end

-- Whether the toon is of the kind a test asks for:
-- { class = "HUNTER", race = "Dwarf", faction = "Alliance", minLevel = 10, maxLevel = 39 }.
function T.ToonMatches(toon, want)
    if not want then
        return true
    end
    if want.class and want.class ~= toon.class then return false end
    if want.race and want.race ~= toon.race then return false end
    if want.faction and want.faction ~= toon.faction then return false end
    if want.minLevel and toon.level < want.minLevel then return false end
    if want.maxLevel and toon.level > want.maxLevel then return false end
    return true
end

------------------------------------------------------------------------------------------
-- Saved results
------------------------------------------------------------------------------------------

local KEEP_BUILDS = 3

local function NewDB()
    return {
        schema = T.SCHEMA,
        sessions = {},  -- the last logins: who, where, which build
        builds = {},    -- build -> when it was first seen
        contracts = {}, -- build -> test id -> result
        verdicts = {},  -- test id -> toon kind -> record
        journal = {},   -- learn events with what happened around them
        events = {},    -- build -> event -> how often it fired
        snapshots = {}, -- toon -> base / last / diff
        timing = {},    -- timing runs
        logins = {},    -- what each login and reload cost
        probes = {},    -- toon -> item ID -> what the client and the addon say about it
        sources = {},   -- toon -> appearance sources whose item the client does not have
        search = {},    -- toon -> items found for the verdict tests' pools
        traces = {},    -- the last session that traced who asks for the plan's items
        sightings = {}, -- case -> item -> a bag state checked when an item showed it
        integrations = {}, -- feature -> the other addon's version -> hook points found
        rotation = { history = {} }, -- the bag addon rotation: the run in progress, finished runs
        addonSets = {}, -- key -> the other addons that were enabled, with their versions
        errors = {},    -- errors in the tests themselves
        pending = {},   -- what a reload was asked to prove
        counters = {},  -- the core's own counters, as stored by /cwtest counters
        switches = {},  -- what the tests changed for a while and have to put back
        recordings = { list = {}, environments = {} }, -- the client's answers behind a verdict, for the offline harness
    }
end

local function OpenDB()
    local db = CaerdonWardrobeTestsDB
    if type(db) ~= "table" or db.schema ~= T.SCHEMA then
        db = NewDB()
        CaerdonWardrobeTestsDB = db
    end
    for key, value in pairs(NewDB()) do
        if db[key] == nil then
            db[key] = value
        end
    end
    T.db = db
end

-- Results are kept for the newest builds only: a contract is a fact about one build.
local function NoteBuild()
    local db, build = T.db, T.GetClient().build
    db.builds[build] = db.builds[build] or GetServerTime()
    local builds = T.SortedKeys(db.builds)
    table.sort(builds, function(a, b) return db.builds[a] > db.builds[b] end)
    for index = KEEP_BUILDS + 1, #builds do
        local old = builds[index]
        db.builds[old], db.contracts[old], db.events[old] = nil, nil, nil
    end
    db.contracts[build] = db.contracts[build] or {}
    db.events[build] = db.events[build] or {}
end

------------------------------------------------------------------------------------------
-- The other addons
------------------------------------------------------------------------------------------

-- Other addons feed the verdicts (Pawn the upgrade arrow, Auctionator the auction icon) and
-- decide which buttons get drawn (a bag addon), and the set changes over time. So every
-- snapshot, timing record and session names the set it was taken with, and a comparison can
-- say that the difference may not be the addon's.

local KEEP_ADDON_SETS = 30

-- Every addon enabled for this toon, with its version: enabled, not loaded, so an addon that
-- loads on demand halfway through a session does not make a new set.
local function ReadAddons()
    local addons = {}
    local character = UnitGUID("player")
    for index = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(index)
        if name and C_AddOns.GetAddOnEnableState(name, character) > Enum.AddOnEnableState.None then
            addons[name] = tostring(C_AddOns.GetAddOnMetadata(name, "Version") or "")
        end
    end
    return addons
end

-- Pure: a short key for a set, the same for the same addons and versions.
function T.AddonSetKey(addons)
    local hash = 5381
    for _, name in ipairs(T.SortedKeys(addons)) do
        local text = name .. "=" .. addons[name] .. ";"
        for index = 1, #text do
            hash = (hash * 33 + text:byte(index)) % 4294967296
        end
    end
    return tostring(hash)
end

-- Pure: what differs between two sets, as readable lines. nil when either set is unknown.
function T.DiffAddonSets(before, after)
    if not before or not after then
        return nil
    end
    local lines = {}
    for _, name in ipairs(T.SortedKeys(before)) do
        if after[name] == nil then
            lines[#lines + 1] = ("%s %s was removed"):format(name, before[name])
        elseif after[name] ~= before[name] then
            lines[#lines + 1] = ("%s %s -> %s"):format(name, before[name], after[name])
        end
    end
    for _, name in ipairs(T.SortedKeys(after)) do
        if before[name] == nil then
            lines[#lines + 1] = ("%s %s was added"):format(name, after[name])
        end
    end
    return lines
end

-- Stores the current set once and returns its key, which a record keeps.
function T.NoteAddons()
    local addons = ReadAddons()
    local key = T.AddonSetKey(addons)
    local sets = T.db.addonSets
    if not sets[key] then
        sets[key] = { addons = addons, firstSeen = GetServerTime() }
        local keys = T.SortedKeys(sets)
        table.sort(keys, function(a, b) return sets[a].firstSeen > sets[b].firstSeen end)
        for index = KEEP_ADDON_SETS + 1, #keys do
            sets[keys[index]] = nil
        end
    end
    return key
end

function T.GetAddonSet(key)
    local set = key and T.db.addonSets[key]
    return set and set.addons
end

function T.RecordError(where, message, stack)
    T.Push(T.db.errors, {
        at = GetServerTime(),
        where = where,
        message = tostring(message),
        stack = stack,
    }, 30)
    T.Print("|cffff4040error in %s:|r %s", tostring(where), tostring(message))
end

------------------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}

-- Returns false when the client does not know the event.
function T.RegisterEvent(event, handler)
    local list = handlers[event]
    if not list then
        if not pcall(frame.RegisterEvent, frame, event) then
            return false
        end
        list = {}
        handlers[event] = list
    end
    list[#list + 1] = handler
    return true
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    for index = 1, #list do
        xpcall(list[index], geterrorhandler(), event, ...)
    end
end)

local initializers, logins = {}, {}

-- fn runs once the saved results are loaded; a login function once the toon can be read.
function T.OnInit(fn) initializers[#initializers + 1] = fn end
function T.OnLogin(fn) logins[#logins + 1] = fn end

T.RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then
        return
    end
    T.loadedAt = GetTime()
    OpenDB()
    for _, fn in ipairs(initializers) do
        xpcall(fn, geterrorhandler())
    end
end)

T.RegisterEvent("PLAYER_LOGIN", function()
    T.loginTime = GetTime()
    NoteBuild()
    local client, toon = T.GetClient(), T.GetToon()
    -- Kept at hand: the session's own refresh figures are added to it on the way out
    -- (Counters.lua).
    T.session = {
        at = GetServerTime(),
        flavor = client.flavor,
        build = client.build,
        toc = client.toc,
        locale = client.locale,
        toon = toon.key,
        signature = toon.signature,
        subjectVersion = C_AddOns.GetAddOnMetadata(T.SUBJECT, "Version"),
        testsVersion = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version"),
        addons = T.NoteAddons(),
    }
    T.Push(T.db.sessions, T.session, 20)
    for _, fn in ipairs(logins) do
        xpcall(fn, geterrorhandler())
    end
end)

------------------------------------------------------------------------------------------
-- Jobs
------------------------------------------------------------------------------------------

-- A job is a function that runs in a coroutine, one job at a time, so a test can wait for
-- the client (an item to load, the queue to drain) and still read from top to bottom.
-- Nothing runs in combat.

local queue, active = {}, nil

local function Pack(...)
    return { n = select("#", ...), ... }
end

local function OnUpdate()
    if InCombatLockdown() then
        return
    end
    if not active then
        active = table.remove(queue, 1)
        if not active then
            frame:SetScript("OnUpdate", nil)
            return
        end
    end
    if active.wake and GetTime() < active.wake then
        return
    end
    local ok, wake = coroutine.resume(active.co)
    if not ok then
        T.RecordError(active.name, wake, debugstack(active.co))
        active = nil
    elseif coroutine.status(active.co) == "dead" then
        active = nil
    else
        active.wake = (type(wake) == "number" and wake > 0) and wake or nil
    end
end

function T.Start(name, body)
    queue[#queue + 1] = { name = name, co = coroutine.create(body) }
    frame:SetScript("OnUpdate", OnUpdate)
end

function T.IsBusy()
    return active ~= nil or #queue > 0
end

function T.ActiveJob()
    return active and active.name
end

-- Inside a job: come back next frame, or after some seconds.
function T.Yield()
    coroutine.yield(0)
end

function T.Sleep(seconds)
    coroutine.yield(GetTime() + seconds)
end

-- Inside a job: wait until predicate() holds. False when the timeout came first.
function T.WaitUntil(predicate, timeout)
    local deadline = GetTime() + timeout
    while not predicate() do
        if GetTime() >= deadline then
            return false
        end
        coroutine.yield(0)
    end
    return true
end

-- Inside a job: runs body(...) to its end and returns true plus its results, or false, the
-- error and a stack. Its waits are passed on to the job runner. This stands in for pcall,
-- which cannot be used around code that waits: the client's Lua cannot yield across it.
function T.Protected(body, ...)
    local co = coroutine.create(body)
    local results = Pack(coroutine.resume(co, ...))
    while results[1] and coroutine.status(co) ~= "dead" do
        coroutine.yield(results[2])
        results = Pack(coroutine.resume(co))
    end
    if not results[1] then
        return false, tostring(results[2]), debugstack(co)
    end
    return true, unpack(results, 2, results.n)
end

------------------------------------------------------------------------------------------
-- The addon under test
------------------------------------------------------------------------------------------

-- The core's counters wrap the functions they time, and the tests hook some of the same ones
-- (Journal.lua). Wrapped here, before any hook, the hooks sit outside and their time is not
-- counted. It switches nothing on (Counters.lua).
if CaerdonCounters and CaerdonCounters.Attach then
    CaerdonCounters:Attach()
end

-- Whether the addon has nothing queued: nothing waiting to be drawn, for an item to load or
-- for a tooltip. The core answers that itself.
function T.CoreIsIdle()
    return CaerdonWardrobe:IsQueueIdle()
end

-- Inside a job: wait until the queue has been empty for `settle` seconds in a row.
function T.WaitForIdle(settle, timeout)
    local idleSince
    return T.WaitUntil(function()
        if T.CoreIsIdle() then
            idleSince = idleSince or GetTime()
            return GetTime() - idleSince >= settle
        end
        idleSince = nil
        return false
    end, timeout)
end

-- Inside a job: a CaerdonItem for an item ID or link with its data loaded, or nil and why.
function T.LoadItem(itemRef, timeout)
    local item
    if type(itemRef) == "number" then
        if not C_Item.DoesItemExistByID(itemRef) then
            return nil, "the client has no item " .. itemRef
        end
        item = CaerdonItem:CreateFromItemID(itemRef)
    else
        item = CaerdonItem:CreateFromItemLink(itemRef)
    end
    local loaded = false
    item:ContinueOnItemLoad(function() loaded = true end)
    if not T.WaitUntil(function() return loaded end, timeout or 10) then
        return nil, "the item's data did not load"
    end
    if not item:GetItemLink() then
        return nil, "the item has no link"
    end
    return item
end

-- Inside a job: the addon's verdict for a loaded item. Returns true, status, binding text
-- and the binding result, or false when the tooltip never became ready.
function T.GetVerdict(item, feature, locationInfo, timeout)
    local deadline = GetTime() + (timeout or 12)
    while true do
        local isReady, status, bindingStatus, bindingResult = item:GetCaerdonStatus(feature, locationInfo)
        if isReady then
            return true, status, bindingStatus, bindingResult
        end
        if GetTime() >= deadline then
            return false
        end
        T.Sleep(0.5)
    end
end
