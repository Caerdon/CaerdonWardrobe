-- Replays a recording: the addon's real item code decides about the recorded item again, in
-- a mocked client that answers every question from the recording.
--
-- The outcomes:
--   pass      the status and the binding text came out as recorded
--   differs   every question had its recorded answer and the outcome is another: the addon's
--             code decides differently than it did (a regression, or a change that was meant)
--   stale     the outcome is another and the addon asked something the recording has no
--             answer for, so the recording cannot judge this code any more: record it again
--   error     the addon's code raised an error
-- A pass with unanswered questions is still a pass and says how many: the code has started
-- to ask more than the recording holds.

local H = ...

local Keys = H.Keys

------------------------------------------------------------------------------------------
-- Answers
------------------------------------------------------------------------------------------

local Provider = {}
Provider.__index = Provider

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, item in pairs(value) do
        copy[key] = DeepCopy(item)
    end
    return copy
end
H.DeepCopy = DeepCopy

-- An answer as the code may keep and change it. A color lost its methods on the way into the
-- saved variables; it gets them back here.
local function Revive(value, env)
    if type(value) ~= "table" then
        return value
    end
    local copy, count, isColor = {}, 0, type(value.r) == "number" and type(value.g) == "number"
        and type(value.b) == "number"
    for key, item in pairs(value) do
        count = count + 1
        if key ~= "r" and key ~= "g" and key ~= "b" and key ~= "a" then
            isColor = false
        end
        copy[key] = Revive(item, env)
    end
    if isColor and count <= 4 and rawget(env, "CreateColor") then
        return env.CreateColor(value.r, value.g, value.b, value.a)
    end
    return copy
end

function H.NewProvider(environment, recording)
    local self = setmetatable({}, Provider)
    self.values = environment.values or {}
    self.kinds = environment.kinds or {}
    self.absent = environment.absent or {}
    self.outlines = environment.tables or {}
    self.calls = recording.calls or {}
    self.shared = environment.calls or {} -- answers every recording of the session agrees on
    self.methods = recording.methods or {}
    self.phase = "startup"
    self.answered = 0
    self.unanswered = {} -- { name, key, phase }: a question the recording has no answer for
    self.passed = {}     -- name -> times: a call that only asks the client to do something
    self.unknownMembers = {}
    self.cursor = {}
    self.tables = {}

    -- Every name that has something recorded below it is a table.
    self.parents = {}
    local function note(name)
        local at = 0
        while true do
            at = name:find(".", at + 1, true)
            if not at then
                break
            end
            self.parents[name:sub(1, at - 1)] = true
        end
    end
    for name in pairs(self.values) do note(name) end
    for name in pairs(self.kinds) do note(name) end
    for name in pairs(self.absent) do note(name) end
    for _, calls in ipairs({ self.calls, self.shared }) do
        for name in pairs(calls) do
            if not name:find(":", 1, true) then
                note(name)
            end
        end
    end
    return self
end

function Provider:Answer(name, owner, ...)
    local count = select("#", ...)
    local key
    if owner and self.methods[name] and count > 0 and (...) == owner then
        key = Keys.Args(count - 1, select(2, ...))
    else
        key = Keys.Args(count, ...)
    end
    local list = (self.calls[name] and self.calls[name][key]) or (self.shared[name] and self.shared[name][key])
    if not list then
        return false, key
    end
    local cursor = self.cursor[list] or 0
    if cursor < #list then
        cursor = cursor + 1
    end
    self.cursor[list] = cursor
    self.answered = self.answered + 1
    return true, list[cursor]
end

function Provider:Function(name, owner)
    return function(...)
        local found, answer = self:Answer(name, owner, ...)
        if not found then
            if self.calls[name] == nil and self.shared[name] == nil
                and (Keys.IsRequest(name) or not Keys.IsGetter(name)) then
                -- Not a function the recorder asks: it does something, or its name does not
                -- say that it reads.
                self.passed[name] = (self.passed[name] or 0) + 1
            else
                self.unanswered[#self.unanswered + 1] = { name = name, key = answer, phase = self.phase }
            end
            return nil
        end
        if answer.error then
            error(answer.error, 2)
        end
        if answer.callback then
            -- The client handed this answer to the function it was given.
            for index = 1, select("#", ...) do
                local callback = (select(index, ...))
                if type(callback) == "function" then
                    local handed = {}
                    for position = 1, answer.callback.n or #answer.callback do
                        handed[position] = Revive(answer.callback[position], self.client.env)
                    end
                    callback(unpack(handed, 1, answer.callback.n or #answer.callback))
                    break
                end
            end
        end
        local results = {}
        for index = 1, answer.n or #answer do
            results[index] = Revive(answer[index], self.client.env)
        end
        return unpack(results, 1, answer.n or #answer)
    end
end

function Provider:Table(name)
    local existing = self.tables[name]
    if existing then
        return existing
    end
    local proxy = {}
    self.tables[name] = proxy
    -- Another addon's table the addon walks through: what the recording kept of it is there
    -- to be found by pairs.
    for key, value in pairs(self.outlines[name] or {}) do
        -- Not where the recording knows the member by its own name: that one is resolved.
        local path = name .. "." .. tostring(key)
        if self.values[path] == nil and not self.kinds[path] and not self.absent[path] and not self.parents[path] then
            proxy[key] = DeepCopy(value)
        end
    end
    setmetatable(proxy, {
        __index = function(_, key)
            if type(key) ~= "string" then
                return nil
            end
            local path = name .. "." .. key
            local kind, value = self:Resolve(path, proxy)
            if kind == "absent" then
                return nil
            elseif kind then
                rawset(proxy, key, value)
                return value
            end
            -- Enum and Constants values the recording does not name: the listings mirror's.
            local mirrored = self.client.listing.enums
            for part in path:gmatch("[^.]+") do
                mirrored = type(mirrored) == "table" and mirrored[part] or nil
            end
            if mirrored ~= nil then
                self.client.fromMirror[#self.client.fromMirror + 1] = path
                rawset(proxy, key, mirrored)
                return mirrored
            end
            if not self.unknownMembers[path] then
                self.unknownMembers[path] = true
                self.client.unknown[#self.client.unknown + 1] = path
            end
            return nil
        end,
    })
    return proxy
end

function Provider:Resolve(name, owner)
    local value = self.values[name]
    if value ~= nil then
        return "value", value
    elseif self.absent[name] then
        return "absent"
    end
    local kind = self.kinds[name]
    if kind == "function" or (kind == nil and (self.calls[name] or self.shared[name])) then
        return "function", self:Function(name, owner)
    elseif kind == "table" or (kind == nil and self.parents[name]) then
        return "table", self:Table(name)
    elseif kind == "frame" then
        return "table", self.client:NewFrame("Frame", name)
    elseif kind then
        return "absent" -- a userdata or a secret value: nothing a recording can hold
    end
    return nil
end

function Provider:FrameCall(frameType, method, ...)
    local found, answer = self:Answer(frameType .. ":" .. method, nil, ...)
    if not found then
        return false
    end
    local results = {}
    for index = 1, answer.n or #answer do
        results[index] = Revive(answer[index], self.client.env)
    end
    return true, unpack(results, 1, answer.n or #answer)
end

------------------------------------------------------------------------------------------
-- Replay
------------------------------------------------------------------------------------------

local function Count(list, phase)
    local count = 0
    for _, entry in ipairs(list) do
        if entry.phase == phase then
            count = count + 1
        end
    end
    return count
end

-- A client with the addon's item side loaded, as it stands after login in the recorded
-- environment. Returns the client and the provider.
function H.StartRecordedClient(environment, recording, options)
    options = options or {}
    local provider = H.NewProvider(environment, recording)
    local client = H.Client.New({
        flavor = environment.client.flavor,
        locale = environment.client.locale,
        provider = provider,
        serverTime = recording.at or environment.at,
    })
    provider.client = client

    for name, value in pairs(environment.saved or {}) do
        rawset(client.env, name, DeepCopy(value))
    end
    rawset(client.env, "CaerdonWardrobeConfig", DeepCopy(recording.config))

    H.LoadBlizzardBase(client)
    H.LoadAddon(client, "CaerdonWardrobe", options.addonDir or H.addonDir, options.skip)

    -- The addon's modules set themselves up on these. What they ask the client meanwhile is
    -- no part of the recording (it was made long after login), so it is counted apart.
    client:Fire("ADDON_LOADED", "CaerdonWardrobe")
    client:Fire("VARIABLES_LOADED")
    client:Fire("PLAYER_LOGIN")
    client:Fire("PLAYER_ENTERING_WORLD", false, true)
    client:Tick(40)
    return client, provider
end

-- recording and environment are the tables of a fixture. Returns the result.
function H.Replay(environment, recording, options)
    local result = { expected = recording.verdict or {} }
    local startOk, client, provider = H.Guards.pcall(H.StartRecordedClient, environment, recording, options)
    if not startOk then
        result.state = "error"
        result.error = "while loading the addon: " .. tostring(client)
        return result
    end
    result.client, result.provider = client, provider
    -- What happened while the addon set itself up is kept apart: no recording covers it.
    result.startupErrors, result.unknownAtStartup = client.errors, client.unknown
    client.errors = {}
    client:ForgetUnknown()
    provider.unknownMembers = {}
    provider.phase = "verdict"

    local env = client.env
    local request = recording.request or {}
    local ok, problem = H.Guards.pcall(function()
        local item
        if request.bag then
            item = env.CaerdonItem:CreateFromBagAndSlot(request.bag, request.slot)
        elseif request.link or recording.link then
            item = env.CaerdonItem:CreateFromItemLink(request.link or recording.link)
        else
            item = env.CaerdonItem:CreateFromItemID(request.itemID)
        end
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        result.loaded = loaded
        if loaded then
            local isReady, status, binding = item:GetCaerdonStatus()
            result.ready, result.status, result.binding = isReady and true or false, status, binding
            result.itemType = tostring(item:GetCaerdonItemType())
        end
    end)

    result.unanswered = provider.unanswered
    result.unansweredInVerdict = Count(provider.unanswered, "verdict")
    result.unansweredAtStartup = Count(provider.unanswered, "startup")
    result.answered = provider.answered
    result.passed = provider.passed
    result.unknown = client.unknown
    result.fromMirror = client.fromMirror
    result.errors = client.errors

    if not ok then
        result.state = "error"
        result.error = tostring(problem)
    elseif #client.errors > 0 then
        result.state = "error"
        result.error = client.errors[1]
    else
        local expected = result.expected
        local same = result.loaded and result.ready == (expected.ready and true or false)
            and result.status == expected.status and result.binding == expected.binding
        if same then
            result.state = "pass"
        elseif result.unansweredInVerdict > 0 or #client.unknown > 0 then
            result.state = "stale"
        else
            result.state = "differs"
        end
    end
    return result
end

local function Show(value)
    if value == nil then
        return "nil"
    elseif value == "" then
        return '""'
    end
    return tostring(value)
end

-- The lines that say what a replay found, for the runner and the importer.
function H.DescribeReplay(result, verbose)
    local lines = {}
    local expected = result.expected
    if result.state == "error" then
        lines[#lines + 1] = "error: " .. tostring(result.error)
    elseif result.state ~= "pass" then
        lines[#lines + 1] = ("recorded %s / %s, now %s / %s%s"):format(Show(expected.status), Show(expected.binding),
            Show(result.status), Show(result.binding),
            result.loaded and (result.ready and "" or " (the status was not ready)") or " (the item did not load)")
    end
    if result.unansweredInVerdict and result.unansweredInVerdict > 0 then
        lines[#lines + 1] = ("%d questions the recording has no answer for:"):format(result.unansweredInVerdict)
        local shown, seen = 0, {}
        for _, entry in ipairs(result.unanswered) do
            local text = entry.name .. "(" .. entry.key .. ")"
            if entry.phase == "verdict" and not seen[text] then
                seen[text] = true
                shown = shown + 1
                if shown <= (verbose and 200 or 8) then
                    lines[#lines + 1] = "  " .. (#text > 150 and (text:sub(1, 150) .. "...") or text)
                end
            end
        end
        if shown > (verbose and 200 or 8) then
            lines[#lines + 1] = ("  and %d more (--verbose lists them)"):format(shown - 8)
        end
    end
    if result.unknown and #result.unknown > 0 then
        lines[#lines + 1] = ("names the recording does not have: %s"):format(table.concat(result.unknown, ", ",
            1, math.min(#result.unknown, verbose and #result.unknown or 12)))
    end
    if verbose then
        if result.unansweredAtStartup and result.unansweredAtStartup > 0 then
            lines[#lines + 1] = ("%d questions while the addon set itself up, which no recording answers"):format(
                result.unansweredAtStartup)
            local seen = {}
            for _, entry in ipairs(result.unanswered) do
                if entry.phase == "startup" and not seen[entry.name] then
                    seen[entry.name] = true
                    lines[#lines + 1] = "  " .. entry.name
                end
            end
        end
        for name, times in pairs(result.passed or {}) do
            lines[#lines + 1] = ("called without an answer, as recorded: %s (%d)"):format(name, times)
        end
        if result.fromMirror and #result.fromMirror > 0 then
            lines[#lines + 1] = ("from the listings mirror, not the recording: %s"):format(
                table.concat(result.fromMirror, ", "))
        end
        if result.unknownAtStartup and #result.unknownAtStartup > 0 then
            lines[#lines + 1] = ("names the recording does not have, read while the addon set itself up: %s"):format(
                table.concat(result.unknownAtStartup, ", "))
        end
        for _, message in ipairs(result.startupErrors or {}) do
            lines[#lines + 1] = "error while the addon set itself up: " .. message
        end
    end
    return lines
end
