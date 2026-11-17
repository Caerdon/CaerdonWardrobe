-- The recorder: what the client answered while the addon decided about one item.
--
-- A recording is the input of an offline test. tools/harness runs the addon's real item code
-- under LuaJIT against it, and the status must come out as it did here. A recorded case keeps
-- the state it was taken in: learning the item later, levelling or a client patch does not
-- move it.
--
-- How the answers are caught. Every client function the addon names (ApiNames.lua, written
-- by the static check) gets a secure hook. A hook is told what a function was asked, not what
-- it answered, so the recorder asks the same question again right away and keeps that answer.
-- That is only done for functions that read (RecordKeys.lua says which). The hooks cannot be
-- taken off again: they stay until the next reload and do nothing while no recording runs,
-- but every call of a hooked function then costs one more call. Reload before a timing.
--
-- What makes a recording usable offline:
--   * the addon's caches are emptied first, so it asks the client for everything again;
--   * the recorded run is one call from start to end: the item is asked for twice, once to
--     get everything loaded and once, recorded, when nothing has to wait. So no other addon's
--     calls are in it, and it does not depend on what arrives later;
--   * what the addon reads without calling anything (global strings, enum values, whether a
--     table or another addon is there, its own saved variables) is captured once a session.
--
-- What it cannot catch: a method called on a frame or on another addon's object (Questie's
-- modules), and state the addon built before the recording from calls it does not repeat.
-- The harness says so when it imports a recording: it replays each one and lists the
-- questions the recording has no answer for.

local _, T = ...

local Keys = T.RecordKeys
local Recorder = {}
T.Recorder = Recorder

local KEEP_RECORDINGS = 60
local KEEP_ENVIRONMENTS = 6
local MAX_ITEMS = 20000 -- per table: a recipe list is long
local MAX_DEPTH = 10
local MAX_ANSWERS = 8 -- different answers kept for one question, in the order they came

local function IsFrame(value)
    return type(rawget(value, 0)) == "userdata"
end

-- A copy the saved variables can hold. Anything that cannot be kept becomes a "<kind>" marker
-- and is counted in notes.lossy, so an answer that lost something says so.
local function Copy(value, depth, notes)
    if issecretvalue(value) then
        notes.lossy = (notes.lossy or 0) + 1
        return "<secret>"
    end
    local kind = type(value)
    if kind == "string" or kind == "boolean" or kind == "nil" then
        return value
    elseif kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            notes.lossy = (notes.lossy or 0) + 1
            return "<" .. tostring(value) .. ">"
        end
        return value
    elseif kind ~= "table" then
        notes.lossy = (notes.lossy or 0) + 1
        return "<" .. kind .. ">"
    elseif IsFrame(value) then
        notes.lossy = (notes.lossy or 0) + 1
        return "<frame>"
    elseif depth <= 0 then
        notes.lossy = (notes.lossy or 0) + 1
        return "<table>"
    end
    local copy, count = {}, 0
    for key, item in pairs(value) do
        -- Methods are left out: a color or an item location is a mixin. The harness puts a
        -- color's methods back.
        if issecretvalue(item) or type(item) ~= "function" then
            count = count + 1
            if count > MAX_ITEMS then
                notes.lossy = (notes.lossy or 0) + 1
                break
            end
            local keyKind = type(key)
            if issecretvalue(key) or (keyKind ~= "string" and keyKind ~= "number") then
                notes.lossy = (notes.lossy or 0) + 1
            else
                copy[key] = Copy(item, depth - 1, notes)
            end
        end
    end
    return copy
end

local function ReadField(owner, key)
    return owner[key]
end

-- What a dotted name is in this client: the value, the table it was read off and the last
-- key. state is "frame" for a member of a frame, which is not recorded, and "orphan" for a
-- name below something that is not there or is no table: the entry of that parent says so.
local function Resolve(path)
    local owner, value, last = nil, _G, nil
    for key in path:gmatch("[^.]+") do
        if type(value) ~= "table" then
            return nil, "orphan"
        elseif value ~= _G and IsFrame(value) then
            return nil, "frame"
        end
        owner, last = value, key
        -- Another addon's table may raise an error for a key it does not know.
        local ok, field = pcall(ReadField, owner, key)
        if ok then
            value = field
        else
            value = nil
        end
    end
    return value, nil, owner, last
end

------------------------------------------------------------------------------------------
-- Hooks
------------------------------------------------------------------------------------------

local current        -- the recording in progress
local asking = false -- inside the recorder's own second call
local hooked = {}    -- name -> true
local hookCount = 0
local refused = {}   -- name -> what the client said when it would not let the function be hooked
local refusedCount = 0
local lastText = setmetatable({}, { __mode = "k" }) -- answer list -> text of its last answer

local function Pack(...)
    return { n = select("#", ...), ... }
end

local function Keep(recording, name, key, answer)
    local byKey = recording.calls[name]
    if not byKey then
        byKey = {}
        recording.calls[name] = byKey
    end
    local list = byKey[key]
    local text = Keys.Answer(answer) .. (answer.callback and ("^" .. Keys.Answer(answer.callback)) or "")
    if not list then
        byKey[key] = { answer }
        lastText[byKey[key]] = text
        recording.questions = recording.questions + 1
    elseif lastText[list] ~= text and #list < MAX_ANSWERS then
        -- The same question got another answer later in the run: both are kept, in order.
        list[#list + 1] = answer
        lastText[list] = text
    end
end

local function OnCall(name, original, owner, ...)
    local recording = current
    if not recording or asking then
        return
    end
    local count = select("#", ...)
    local results, handed
    asking = true
    if Keys.CALLBACKS[name] then
        -- Its answer goes to the function it is given: ask with one that keeps it.
        local arguments = Pack(...)
        for index = 1, arguments.n do
            if type(arguments[index]) == "function" then
                arguments[index] = function(...)
                    handed = handed or Pack(...)
                end
            end
        end
        results = Pack(pcall(original, unpack(arguments, 1, arguments.n)))
    else
        results = Pack(pcall(original, ...))
    end
    asking = false

    local key
    if owner and count > 0 and (...) == owner then
        -- Called as a method of another addon's table: the table is no part of the question.
        recording.methods[name] = true
        key = Keys.Args(count - 1, select(2, ...))
    else
        key = Keys.Args(count, ...)
    end

    local answer
    if results[1] then
        answer = { n = results.n - 1 }
        for index = 2, results.n do
            answer[index - 1] = Copy(results[index], MAX_DEPTH, recording.notes)
        end
    else
        answer = { n = 0, error = tostring(results[2]) }
    end
    if handed then
        answer.callback = { n = handed.n }
        for index = 1, handed.n do
            answer.callback[index] = Copy(handed[index], MAX_DEPTH, recording.notes)
        end
    end
    Keep(recording, name, key, answer)
end

-- Every name the recorder looks at: the static check's list and the ones built at run time.
local allNames
local function Names()
    if not allNames then
        allNames = {}
        for name, kind in pairs(T.ApiNames) do
            allNames[name] = kind
        end
        for _, name in ipairs(Keys.ALSO_NAMES) do
            allNames[name] = allNames[name] or "api"
        end
        -- The global strings the item code builds the names of (the stat lines among a
        -- tooltip's "Equip:" lines). The list is the addon's, so it cannot fall behind it.
        if CaerdonItem.GetEquipStatStringNames then
            for _, name in ipairs(CaerdonItem:GetEquipStatStringNames()) do
                allNames[name] = allNames[name] or ""
            end
        end
    end
    return allNames
end

local function ShouldHook(name)
    if hooked[name] or Keys.IsBasic(name) or not Keys.IsGetter(name) then
        return false
    end
    local root = name:match("^[^.]+")
    local kind = Names()[name]
    return kind == "api" or kind == "other" or Names()[root] == "other" or Keys.ALSO[name]
        or root:find("^C_") ~= nil
end

local function HookName(name)
    if not ShouldHook(name) then
        return
    end
    local value, state, owner, key = Resolve(name)
    if type(value) ~= "function" or state == "frame" then
        return
    end
    local root = name:match("^[^.]+")
    -- Only another addon's table is ever called with itself as the first argument.
    local methodOwner = (Names()[root] == "other" and owner ~= _G) and owner or nil
    local original = value
    -- The client does not let every function be hooked ("... is forbidden for hooking"). Such
    -- a function is left alone and listed: a recording has no answers of its own for it.
    local ok, problem = pcall(hooksecurefunc, owner, key, function(...)
        if current then
            OnCall(name, original, methodOwner, ...)
        end
    end)
    hooked[name] = true -- not tried again either way
    if ok then
        hookCount = hookCount + 1
    else
        refused[name] = tostring(problem)
        refusedCount = refusedCount + 1
    end
end

-- The addon finds the look of an item the collection does not list by trying it on a model
-- of its own (types/EquipmentMixin.lua). The model exists once that has happened.
local modelHooked = false
local function HookModel()
    local model = CaerdonWardrobe.dressUp
    if modelHooked or not model or type(model.GetItemTransmogInfo) ~= "function" then
        return
    end
    local original = model.GetItemTransmogInfo
    local ok, problem = pcall(hooksecurefunc, model, "GetItemTransmogInfo", function(_, ...)
        if current then
            OnCall("DressUpModel:GetItemTransmogInfo", function(...) return original(model, ...) end, nil, ...)
        end
    end)
    modelHooked = true -- not tried again either way
    if not ok then
        refused["DressUpModel:GetItemTransmogInfo"] = tostring(problem)
        refusedCount = refusedCount + 1
    end
end

-- A seam is a function of the addon itself (RecordKeys.lua says which, and why). It is
-- always called as a method, and the module is no part of the question.
local function HookSeam(name)
    if hooked[name] then
        return
    end
    hooked[name] = true
    local value, _, owner, key = Resolve(name)
    if type(value) ~= "function" then
        refused[name] = "the addon has no such function"
        refusedCount = refusedCount + 1
        return
    end
    hooksecurefunc(owner, key, function(...)
        if current then
            OnCall(name, value, owner, ...)
        end
    end)
    hookCount = hookCount + 1
end

function Recorder.EnsureHooks()
    if not T.ApiNames then
        return false
    end
    for name in pairs(Names()) do
        HookName(name)
    end
    for _, name in ipairs(Keys.SEAMS) do
        HookSeam(name)
    end
    HookModel()
    return true
end

function Recorder.HookCount()
    return hookCount, refusedCount
end

------------------------------------------------------------------------------------------
-- What the addon reads without calling anything
------------------------------------------------------------------------------------------

local MAX_OUTLINE = 4000

-- Another addon's table that the addon reads directly (Pawn's scales): its keys, with the
-- plain values one level down. nil when there is nothing plain in it or it is too large.
local function Outline(source)
    local outline, count = {}, 0
    local function plain(value)
        local kind = type(value)
        return not issecretvalue(value) and (kind == "string" or kind == "number" or kind == "boolean")
    end
    for key, value in pairs(source) do
        local keyKind = type(key)
        if not issecretvalue(key) and (keyKind == "string" or keyKind == "number") and not issecretvalue(value) then
            if plain(value) then
                outline[key] = value
                count = count + 1
            elseif type(value) == "table" and not IsFrame(value) then
                -- A table with nothing plain in it (a table of functions) is left out: its
                -- members are names of their own.
                local inner
                for innerKey, innerValue in pairs(value) do
                    local innerKind = type(innerKey)
                    if not issecretvalue(innerKey) and (innerKind == "string" or innerKind == "number")
                        and plain(innerValue) then
                        inner = inner or {}
                        inner[innerKey] = innerValue
                        count = count + 1
                    end
                end
                if inner then
                    outline[key] = inner
                    count = count + 1
                end
            end
            if count > MAX_OUTLINE then
                return nil
            end
        end
    end
    return count > 0 and outline or nil
end

local SAVED = { "CaerdonProfessionData", "CaerdonRecipeData", "CaerdonAuctionData" }

local environmentKey

-- Once a session: every name of ApiNames as it is in this client, and the saved variables
-- that do not change with a setting.
local function EnsureEnvironment()
    local store = T.db.recordings.environments
    if environmentKey and store[environmentKey] then
        return environmentKey
    end
    local client, toon = T.GetClient(), T.GetToon()
    local notes = {}
    local environment = {
        format = Keys.FORMAT,
        at = GetServerTime(),
        client = client,
        toon = {
            name = UnitName("player"),
            realm = GetRealmName(),
            class = toon.class,
            race = toon.race,
            faction = toon.faction,
            level = toon.level,
            signature = toon.signature,
        },
        addonVersion = C_AddOns.GetAddOnMetadata(T.SUBJECT, "Version"),
        values = {}, -- name -> a string, number or boolean
        kinds = {},  -- name -> "function", "table", "frame", "userdata" or "secret"
        absent = {}, -- name -> true: the client has no such thing
        notHooked = {}, -- name -> the client's words: a function it would not let be hooked
        tables = {}, -- name -> the outline of another addon's table that the addon reads directly
        saved = {},
        notes = notes,
    }
    for name in pairs(Names()) do
        if not Keys.IsBasic(name) then
            local value, state = Resolve(name)
            if state == "frame" or state == "orphan" then
                -- A frame's member (the harness has frames of its own), or a name below
                -- something that is not there.
            elseif value == nil then
                environment.absent[name] = true
            elseif issecretvalue(value) then
                environment.kinds[name] = "secret"
            else
                local kind = type(value)
                if kind == "string" or kind == "number" or kind == "boolean" then
                    environment.values[name] = value
                elseif kind == "table" then
                    environment.kinds[name] = IsFrame(value) and "frame" or "table"
                    local root = name:match("^[^.]+")
                    if root ~= name and Names()[root] == "other" and not IsFrame(value) then
                        environment.tables[name] = Outline(value)
                    end
                else
                    environment.kinds[name] = kind
                end
            end
        end
    end
    for name, problem in pairs(refused) do
        environment.notHooked[name] = problem
    end
    for _, name in ipairs(SAVED) do
        if _G[name] == nil then
            -- Not written yet (a first session): the addon finds nothing and makes its own.
            environment.absent[name] = true
        else
            environment.saved[name] = Copy(_G[name], MAX_DEPTH, notes)
        end
    end

    environmentKey = ("%s/%s/%d"):format(client.build, toon.key, environment.at)
    store[environmentKey] = environment
    return environmentKey
end

-- Environments no recording names any more are dropped, oldest first.
local function Prune()
    local recordings = T.db.recordings
    while #recordings.list > KEEP_RECORDINGS do
        table.remove(recordings.list, 1)
    end
    local used = {}
    for _, recording in ipairs(recordings.list) do
        used[recording.environment] = true
    end
    local keys = {}
    for key, environment in pairs(recordings.environments) do
        if not used[key] and key ~= environmentKey then
            recordings.environments[key] = nil
        else
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, function(a, b) return recordings.environments[a].at < recordings.environments[b].at end)
    for index = 1, #keys - KEEP_ENVIRONMENTS do
        local key = keys[index]
        recordings.environments[key] = nil
        for position = #recordings.list, 1, -1 do
            if recordings.list[position].environment == key then
                table.remove(recordings.list, position)
            end
        end
    end
end

------------------------------------------------------------------------------------------
-- Recording
------------------------------------------------------------------------------------------

-- What the addon keeps between two questions. RefreshItems empties the same caches; the
-- harness compares the two lists (tools/harness, the "recorder" scenario).
local function EmptyTheAddonsCaches()
    CaerdonItem:InvalidateStatusCache()
    CaerdonEquipment:InvalidateCaches()
    CaerdonQuestItems:InvalidateCaches()
    CaerdonFoodDrink:InvalidateCaches()
    CaerdonProfessionTools:InvalidateCaches()
    CaerdonBagSlots:InvalidateCaches()
    CaerdonAuctionValue:InvalidateCaches()
    if CaerdonAPI.InvalidateTalentTrees then
        CaerdonAPI:InvalidateTalentTrees()
    end
    -- What a module keeps for the whole session because it never changes, which a refresh
    -- rightly leaves alone. A replay starts without it, so a recorded run has to as well.
    if CaerdonFoodDrink.ForgetClassifications then
        CaerdonFoodDrink:ForgetClassifications()
    end
    -- Likewise what the equipment code keeps about a source whose item the client refused.
    if CaerdonEquipment.ForgetRefusedItems then
        CaerdonEquipment:ForgetRefusedItems()
    end
end

-- Asked at the end of every recorded run whether the addon asked or not: who the toon is and
-- what it wears. A later version of the addon that reads one of these at another moment
-- still finds its answer.
local function AskAboutTheToon()
    UnitLevel("player")
    UnitClass("player")
    UnitRace("player")
    UnitFactionGroup("player")
    UnitSex("player")
    UnitName("player")
    GetRealmName()
    GetLocale()
    GetBuildInfo()
    GetExpansionLevel()
    local indexes = { GetProfessions() }
    for position = 1, 6 do
        if indexes[position] then
            GetProfessionInfo(indexes[position])
        end
    end
    for slot = 0, 19 do
        GetInventoryItemID("player", slot)
        GetInventoryItemLink("player", slot)
    end
    -- And what the addon asked once, when the session began.
    for _, question in ipairs(Keys.ONCE_A_SESSION) do
        local ask = Resolve(question[1])
        if type(ask) == "function" then
            pcall(ask, unpack(question, 2))
        end
    end
end

local function NewItem(request)
    if request.bag then
        return CaerdonItem:CreateFromBagAndSlot(request.bag, request.slot)
    elseif request.link then
        return CaerdonItem:CreateFromItemLink(request.link)
    end
    return CaerdonItem:CreateFromItemID(request.itemID)
end

-- One recorded run: a new item, its load and its status, in one call. Returns the recording
-- and whether the addon had its answer without waiting.
local function RecordedRun(request, keepCaches)
    local recording = { calls = {}, methods = {}, notes = {}, questions = 0 }
    if keepCaches then
        recording.cachesKept = true
    else
        EmptyTheAddonsCaches()
    end
    HookModel()

    current = recording
    local ok, problem = pcall(function()
        local item = NewItem(request)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        recording.loaded = loaded
        if loaded then
            local isReady, status, bindingStatus, bindingResult = item:GetCaerdonStatus()
            recording.link = item:GetItemLink()
            recording.itemID = item:GetItemID()
            recording.name = item:GetItemName()
            recording.verdict = {
                ready = isReady and true or false,
                status = status,
                binding = bindingStatus,
                itemType = tostring(item:GetCaerdonItemType()),
                bindingResult = Copy(bindingResult, 4, {}),
            }
        end
        AskAboutTheToon()
    end)
    current = nil

    if not ok then
        recording.error = tostring(problem)
    end
    return recording, ok and recording.loaded and recording.verdict and recording.verdict.ready
end

-- Inside a job. request: { itemID = } or { link = } or { bag =, slot = }, with an optional
-- note. Returns the stored recording, or nil and why.
function Recorder.Record(request)
    if not Recorder.EnsureHooks() then
        return nil, "ApiNames.lua is not there: run `luajit tools/static-checks.lua --emit-facts`, then /reload"
    end
    if InCombatLockdown() then
        return nil, "in combat"
    end

    -- First everything is loaded, however long that takes.
    local item, why
    if request.bag then
        item = NewItem(request)
        if item:IsItemEmpty() then
            return nil, ("bag %d slot %d is empty"):format(request.bag, request.slot)
        end
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        if not T.WaitUntil(function() return loaded end, 10) then
            return nil, "the item's data did not load"
        end
    else
        item, why = T.LoadItem(request.link or request.itemID)
        if not item then
            return nil, why
        end
        -- An ID becomes the link the client makes for it, so the recording names one item.
        request = { link = item:GetItemLink(), itemID = request.itemID, note = request.note }
    end
    if not T.GetVerdict(item) then
        return nil, "the addon had no verdict (item or tooltip not ready)"
    end

    -- Then the recorded run, until one went through without waiting. Emptying the caches can
    -- itself make the addon wait (a module that fills its cache over several frames), so the
    -- last two tries leave them as they are: such a recording misses the answers the addon
    -- still had, and the harness will say which.
    local recording, complete
    for attempt = 1, 4 do
        recording, complete = RecordedRun(request, attempt > 2)
        recording.attempts = attempt
        if complete or recording.error then
            break
        end
        T.Sleep(0.5)
    end

    recording.at = GetServerTime()
    recording.format = Keys.FORMAT
    recording.environment = EnsureEnvironment()
    recording.request = { itemID = request.itemID, link = request.link, bag = request.bag, slot = request.slot }
    recording.note = request.note
    recording.config = Copy(CaerdonWardrobeConfig, MAX_DEPTH, recording.notes)
    recording.complete = complete and true or false
    if not complete and not recording.error then
        recording.error = recording.loaded and "the addon's status was never ready within one call"
            or "the item never loaded within one call"
    end

    table.insert(T.db.recordings.list, recording)
    Prune()
    return recording
end

------------------------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------------------------

local function Describe(recording)
    if recording.error then
        return ("|cffff4040not usable:|r %s"):format(recording.error)
    end
    return ("%s%s, %d questions answered"):format(tostring(recording.verdict.status),
        recording.verdict.binding and (" / " .. tostring(recording.verdict.binding)) or "", recording.questions)
end

-- requests: a list of { itemID = } / { link = } / { bag =, slot = }.
function T.RecordItems(requests, quiet)
    T.Start("record", function()
        local done = 0
        for _, request in ipairs(requests) do
            local recording, why = Recorder.Record(request)
            if recording then
                done = done + 1
                if not quiet then
                    T.Print("recorded %s: %s", tostring(recording.link or recording.request.itemID), Describe(recording))
                end
            else
                T.Print("not recorded (%s): %s", tostring(request.link or request.itemID or
                    ("bag " .. tostring(request.bag) .. " slot " .. tostring(request.slot))), tostring(why))
            end
            T.Yield()
        end
        -- A recording empties the addon's caches behind the icons on screen, and with them
        -- what the quest module compares a quest event with. A refresh makes both anew.
        if done > 0 and not InCombatLockdown() then
            CaerdonWardrobe:RefreshItems()
        end
        T.Print("%d of %d recorded (%d functions hooked until the next reload%s). /reload writes them to disk; "
            .. "then `luajit tools/harness/run.lua import`.", done, #requests, hookCount,
            refusedCount > 0 and (", %d the client would not let be hooked"):format(refusedCount) or "")
    end)
end

-- Every different item in the bags, one copy each.
local function BagRequests()
    local requests, seen = {}, {}
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link and not seen[link] then
                seen[link] = true
                requests[#requests + 1] = { bag = bag, slot = slot }
            end
        end
    end
    return requests
end

-- /cwtest record <item ID or link> ... | <bag> <slot> | bags | list | clear
function T.RecordCommand(rest)
    local recordings = T.db.recordings
    if rest == "list" or rest == "" then
        T.Print("%d recordings waiting for `luajit tools/harness/run.lua import`:", #recordings.list)
        for index, recording in ipairs(recordings.list) do
            print(("  %d. %s  %s"):format(index, tostring(recording.link or recording.request.itemID),
                Describe(recording)))
        end
        if rest == "" then
            print("  /cwtest record <item ID or link> ... | slot <bag> <slot> | bags | list | clear")
        end
        return
    elseif rest == "clear" then
        recordings.list, recordings.environments = {}, {}
        T.Print("the recordings are forgotten.")
        return
    elseif rest == "bags" then
        T.RecordItems(BagRequests())
        return
    end

    local bag, slot = rest:match("^slot%s+(%d+)%s+(%d+)$")
    if bag then
        T.RecordItems({ { bag = tonumber(bag), slot = tonumber(slot) } })
        return
    end
    local requests = {}
    for link in rest:gmatch("|c.-|h|r") do
        requests[#requests + 1] = { link = link }
    end
    if #requests == 0 then
        for itemID in rest:gmatch("%d+") do
            requests[#requests + 1] = { itemID = tonumber(itemID) }
        end
    end
    if #requests == 0 then
        T.Print("give item IDs or links, `slot <bag> <slot>`, or `bags`: /cwtest record 2969 6550")
    else
        T.RecordItems(requests)
    end
end

-- Called after login with the plan's recordItems (item IDs).
function T.RecordPlanItems(itemIDs)
    local requests = {}
    for _, itemID in ipairs(itemIDs) do
        requests[#requests + 1] = { itemID = itemID }
    end
    T.RecordItems(requests, true)
end
