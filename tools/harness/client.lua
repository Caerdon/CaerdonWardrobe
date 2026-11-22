-- A mocked client: enough of the game client for the addon's Lua to load and run in.
--
-- Each client is a world of its own. Everything loaded into it sees client.env as its
-- globals, so two clients in one process share nothing and the harness' own globals are not
-- touched. A client brings what every game client has and what says nothing about its state:
-- Lua's helpers under their global names, the clock, frames, events, timers, secure hooks and
-- the error handler (the list is RecordKeys.BASICS, which the recorder leaves alone for that
-- reason). Everything else, which is what the game knows, comes from the provider:
--
--   provider:Resolve(name)   -> kind, value for a global: "value", "function", "table",
--                               "absent" (the game has no such thing), or nil when the
--                               provider does not know the name
--   provider:FrameCall(frameType, method, ...) -> found, results...   (optional)
--
-- A name the provider does not know is looked up in the listings mirror of the client's
-- flavor (global strings, Enum, Constants and the LE_* numbers), and counted, because that
-- value is the mirror's and not the recording's. A name nobody knows reads as nil and is
-- listed in client.unknown.
--
-- Blizzard's own Lua (Mixin, Item, ItemLocation, ContinuableContainer, ...) is not mocked:
-- it is loaded from the source mirror of the flavor.

local H = ...

local Client = {}
Client.__index = Client
H.Client = Client

local Guards = H.Guards

------------------------------------------------------------------------------------------
-- The mirrors
------------------------------------------------------------------------------------------

function H.BuildsDir()
    if not H.buildsDir then
        local home = os.getenv("USERPROFILE") or os.getenv("HOME") or "."
        H.buildsDir = (os.getenv("CAERDON_BUILDS") or (home .. "/Projects/WoW/Builds")):gsub("\\", "/")
    end
    return H.buildsDir
end

function H.ReadFile(path)
    local handle = io.open(path, "rb")
    if not handle then
        return nil
    end
    local text = handle:read("*a")
    handle:close()
    if text:sub(1, 3) == "\239\187\191" then
        text = text:sub(4)
    end
    return (text:gsub("\r\n", "\n"))
end

local chunks = {} -- path -> compiled chunk, shared by every client

-- A file as a function that has not run yet. chunkName is what debugstack will call it.
function H.Compile(path, chunkName)
    local chunk = chunks[path]
    if chunk == nil then
        local text = H.ReadFile(path)
        if not text then
            return nil, "cannot read " .. path
        end
        local problem
        chunk, problem = loadstring(text, "@" .. chunkName)
        if not chunk then
            return nil, problem
        end
        chunks[path] = chunk
    end
    return chunk
end

local listings = {} -- flavor/locale -> { strings, enums }

local function LoadListing(flavor, locale)
    local key = flavor .. "/" .. locale
    local listing = listings[key]
    if listing then
        return listing
    end
    listing = { strings = {}, enums = {}, widgetMethods = {} }
    listings[key] = listing
    local dir = H.BuildsDir() .. "/resources/" .. flavor .. "/Resources/"

    local strings = loadfile(dir .. "GlobalStrings/" .. locale .. ".lua")
    if strings then
        -- Most lines assign a global; a name that is no Lua identifier is set through _G.
        listing.strings._G = listing.strings
        setfenv(strings, listing.strings)()
        listing.strings._G = nil
        listing.hasStrings = true
    end
    local enums = loadfile(dir .. "LuaEnum.lua")
    if enums then
        setfenv(enums, listing.enums)()
        listing.hasEnums = true
    end
    local widgets = loadfile(dir .. "WidgetAPI.lua")
    if widgets then
        for _, widget in pairs(widgets()) do
            for _, name in ipairs(widget.methods or {}) do
                listing.widgetMethods[name] = true
            end
        end
    end
    return listing
end

------------------------------------------------------------------------------------------
-- What every client has
------------------------------------------------------------------------------------------

local LUA_GLOBALS = {
    "assert", "error", "getfenv", "getmetatable", "ipairs", "next", "newproxy", "pairs", "pcall", "rawequal",
    "rawget", "rawset", "select", "setfenv", "setmetatable", "tonumber", "tostring", "type", "unpack", "xpcall",
    "collectgarbage", "string", "table", "math", "coroutine", "bit",
}

local function EscapeClass(characters)
    return (characters:gsub("[%]%^%-%%]", "%%%0"))
end

local function strsplit(delimiters, text, pieces)
    local class = "[" .. EscapeClass(delimiters) .. "]"
    local results, start = {}, 1
    while true do
        local at = (not pieces or #results < pieces - 1) and text:find(class, start)
        if not at then
            results[#results + 1] = text:sub(start)
            break
        end
        results[#results + 1] = text:sub(start, at - 1)
        start = at + 1
    end
    return unpack(results)
end

local function strtrim(text, characters)
    if characters then
        local class = "[" .. EscapeClass(characters) .. "]*"
        return (text:gsub("^" .. class, ""):gsub(class .. "$", ""))
    end
    return (text:match("^%s*(.-)%s*$"))
end

local function strjoin(delimiter, ...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[index] = tostring((select(index, ...)))
    end
    return table.concat(parts, delimiter)
end

local function wipe(target)
    for key in pairs(target) do
        target[key] = nil
    end
    return target
end

-- The same additions the client makes to Lua's own tables. They are shared by the process.
string.split, string.trim, string.join = strsplit, strtrim, strjoin
table.wipe = wipe

local function InstallBasics(client, env)
    for _, name in ipairs(LUA_GLOBALS) do
        env[name] = _G[name]
    end
    env._G = env

    env.print = function(...)
        client.printed[#client.printed + 1] = strjoin(" ", ...)
    end
    env.loadstring = function(text, name)
        local chunk, problem = loadstring(text, name)
        if chunk then
            setfenv(chunk, env)
        end
        return chunk, problem
    end

    -- Lua's helpers under the client's global names.
    env.strsplit, env.strtrim, env.strjoin, env.wipe = strsplit, strtrim, strjoin, wipe
    env.strconcat = function(...) return strjoin("", ...) end
    env.tostringall = function(...)
        local results = {}
        for index = 1, select("#", ...) do
            results[index] = tostring((select(index, ...)))
        end
        return unpack(results, 1, select("#", ...))
    end
    env.format, env.gsub, env.gmatch, env.strmatch = string.format, string.gsub, string.gmatch, string.match
    env.strfind, env.strsub, env.strlen, env.strrep = string.find, string.sub, string.len, string.rep
    env.strlower, env.strupper, env.strbyte, env.strchar = string.lower, string.upper, string.byte, string.char
    env.strrev = string.reverse
    env.tinsert, env.tremove, env.sort = table.insert, table.remove, table.sort
    env.getn = function(list) return #list end
    env.foreach = function(map, fn) for key, value in pairs(map) do fn(key, value) end end
    env.foreachi = function(list, fn) for index, value in ipairs(list) do fn(index, value) end end
    env.abs, env.ceil, env.floor, env.max, env.min = math.abs, math.ceil, math.floor, math.max, math.min
    env.mod, env.random = math.fmod, math.random
    env.date, env.difftime = os.date, os.difftime
    env.time = function(when)
        if when then
            return os.time(when)
        end
        return client:ServerTime()
    end

    -- The clock.
    env.GetTime = function() return client.clock end
    env.GetTimePreciseSec = function() return client.clock end
    env.GetServerTime = function() return client:ServerTime() end
    env.debugprofilestop = function() return (client.clock - client.profileStart) * 1000 end
    env.debugprofilestart = function() client.profileStart = client.clock end

    -- Errors.
    env.geterrorhandler = function() return client.errorHandler end
    env.seterrorhandler = function(handler) client.errorHandler = handler end
    env.CallErrorHandler = function(...) return client.errorHandler(...) end
    env.securecallfunction = function(fn, ...)
        local results = { pcall(fn, ...) }
        if not results[1] then
            client.errorHandler(results[2])
            return
        end
        return unpack(results, 2, table.maxn(results))
    end
    env.issecretvalue = function() return false end
    env.issecurevariable = function() return true end

    -- Mixins, as the client does them.
    env.Mixin = function(object, ...)
        for index = 1, select("#", ...) do
            for key, value in pairs((select(index, ...))) do
                object[key] = value
            end
        end
        return object
    end
    env.CreateFromMixins = function(...)
        return env.Mixin({}, ...)
    end

    -- A stack in the client's form, with the chunk names the files were loaded under.
    env.debugstack = function(start, count)
        if type(start) == "thread" then
            return debug.traceback(start)
        end
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
                lines[#lines + 1] = Guards.format("[%s]:%d: in function <%s:%d>", source, info.currentline, source,
                    info.linedefined)
            end
            level = level + 1
        end
        return table.concat(lines, "\n")
    end

    -- A secure hook: the hook runs after the function, cannot yield, and its errors go to the
    -- error handler instead of the caller.
    env.hooksecurefunc = function(owner, name, hook)
        if type(owner) ~= "table" then
            owner, name, hook = env, owner, name
        end
        local original = owner[name]
        if type(original) ~= "function" then
            error("hooksecurefunc(): " .. tostring(name) .. " is not a function", 2)
        elseif owner == env and client.forbiddenHooks[name] then
            error("hooksecurefunc(): " .. tostring(name) .. " is forbidden for hooking", 2)
        end
        local replacement = function(...)
            local results = { original(...) }
            local ok, problem = pcall(hook, ...)
            if not ok then
                client.errorHandler(problem)
            end
            return unpack(results, 1, table.maxn(results))
        end
        if owner == env then
            rawset(env, name, replacement)
        else
            owner[name] = replacement
        end
    end

    env.CreateFrame = function(frameType, name, parent, template)
        return client:NewFrame(frameType, name, parent, template)
    end

    local function NewTimer(seconds, fn, repeats)
        local timer = { at = client.clock + seconds, fn = fn, every = repeats and seconds or nil }
        function timer:Cancel() self.cancelled = true end
        function timer:IsCancelled() return self.cancelled == true end
        client.timers[#client.timers + 1] = timer
        return timer
    end
    env.C_Timer = {
        After = function(seconds, fn) NewTimer(seconds, fn) end,
        NewTimer = function(seconds, fn) return NewTimer(seconds, fn) end,
        NewTicker = function(seconds, fn) return NewTimer(seconds, fn, true) end,
    }
end

-- What Blizzard's own Lua needs while it loads, which is before anything is recorded, and
-- which does not depend on the game's state. These are the client's, whatever the provider
-- knows.
H.CLIENT_DEFAULTS = {
    GetCurrentEnvironment = function(client) return function() return client.env end end,
    -- The client's table of named colors: Color.lua makes a global of each.
    C_UIColor = function() return { GetColors = function() return {} end } end,
    issecure = function() return function() return false end end,
    -- Colors are text in the client's own code since 12.0; Color.lua calls these.
    C_ColorUtil = function()
        local function Byte(value) return math.floor((value or 1) * 255 + 0.5) end
        local function Code(color)
            return Guards.format("%02x%02x%02x%02x", Byte(color.a), Byte(color.r), Byte(color.g), Byte(color.b))
        end
        return {
            GenerateTextColorCode = Code,
            WrapTextInColorCode = function(text, code) return "|c" .. code .. text .. "|r" end,
            WrapTextInColor = function(text, color) return "|c" .. Code(color) .. text .. "|r" end,
        }
    end,
}

------------------------------------------------------------------------------------------
-- Frames
------------------------------------------------------------------------------------------

-- A frame is a table the addon may put fields on, as in the client, with a userdata at [0].
-- A method the listings name for some widget exists on every frame and does nothing, unless
-- it is one of the few below that the addon's logic depends on.
local FrameMethods = {}

local function State(frame)
    return frame[0] and H.frameState[frame]
end

H.frameState = setmetatable({}, { __mode = "k" })

function FrameMethods:RegisterEvent(event) State(self).events[event] = true return true end
function FrameMethods:RegisterUnitEvent(event) State(self).events[event] = true return true end
function FrameMethods:UnregisterEvent(event) State(self).events[event] = nil end
function FrameMethods:UnregisterAllEvents() State(self).events = {} end
function FrameMethods:IsEventRegistered(event) return State(self).events[event] == true end
function FrameMethods:SetScript(name, fn) State(self).scripts[name] = fn end
function FrameMethods:GetScript(name) return State(self).scripts[name] end
function FrameMethods:HasScript() return true end
function FrameMethods:HookScript(name, hook)
    local scripts = State(self).scripts
    local original = scripts[name]
    scripts[name] = function(...)
        if original then
            original(...)
        end
        hook(...)
    end
end
function FrameMethods:Show() State(self).shown = true end
function FrameMethods:Hide() State(self).shown = false end
function FrameMethods:SetShown(shown) State(self).shown = shown and true or false end
function FrameMethods:IsShown() return State(self).shown end
function FrameMethods:IsVisible()
    local state = State(self)
    if not state.shown then
        return false
    end
    return state.parent == nil or state.parent:IsVisible()
end
function FrameMethods:GetName() return State(self).name end
function FrameMethods:GetDebugName() return State(self).name or State(self).type end
function FrameMethods:GetParent() return State(self).parent end
function FrameMethods:SetParent(parent) State(self).parent = parent end
function FrameMethods:GetObjectType() return State(self).type end
function FrameMethods:IsObjectType(frameType) return State(self).type == frameType end
function FrameMethods:IsForbidden() return false end
function FrameMethods:SetText(text) State(self).text = text end
function FrameMethods:GetText() return State(self).text end
function FrameMethods:SetID(id) State(self).id = id end
function FrameMethods:GetID() return State(self).id or 0 end
function FrameMethods:SetSize(width, height) State(self).width, State(self).height = width, height end
function FrameMethods:SetWidth(width) State(self).width = width end
function FrameMethods:SetHeight(height) State(self).height = height end
function FrameMethods:GetWidth() return State(self).width or 0 end
function FrameMethods:GetHeight() return State(self).height or 0 end
function FrameMethods:GetSize() return State(self).width or 0, State(self).height or 0 end
-- As in the client, the frame's OnAttributeChanged runs at once, inside the call. Blizzard's
-- tooltip code passes its callbacks through one (TooltipDataHandler.lua, AttributeDelegate).
function FrameMethods:SetAttribute(name, value)
    local state = State(self)
    state.attributes[name] = value
    local script = state.scripts.OnAttributeChanged
    if script then
        script(self, name, value)
    end
end
function FrameMethods:GetAttribute(name) return State(self).attributes[name] end
function FrameMethods:GetChildren() return unpack(State(self).children) end
function FrameMethods:GetNumChildren() return #State(self).children end

-- The frame and everything under it that is on screen. Nothing under a frame that is not on
-- screen is, so the walk ends there.
local function CollectOnScreen(frame, found)
    if frame:IsVisible() then
        found[frame] = true
        found[#found + 1] = frame
        for _, child in ipairs(State(frame).children) do
            CollectOnScreen(child, found)
        end
    end
    return found
end

-- Coming on screen and leaving it. In the client a frame's OnShow runs when it comes on
-- screen, whether it was shown itself or a parent of it was, and OnHide when it leaves; a
-- frame shown under a hidden parent gets neither. frame:Show() and frame:Hide() above only
-- set the state, which is all the scenarios written before this needed. A scenario that
-- depends on those scripts shows and hides through this. A script's error goes to the error
-- handler and the others still run.
function Client:SetFrameShown(frame, shown)
    local before = CollectOnScreen(frame, {})
    State(frame).shown = shown and true or false
    local after = CollectOnScreen(frame, {})
    local script, changed, unchanged = "OnShow", after, before
    if not shown then
        script, changed, unchanged = "OnHide", before, after
    end
    for _, each in ipairs(changed) do
        local handler = not unchanged[each] and State(each).scripts[script]
        if handler then
            local ok, problem = pcall(handler, each)
            if not ok then
                self.errorHandler(problem)
            end
        end
    end
end

local READS = { "^Get%u", "^Is%u", "^Has%u", "^Can%u", "^Does%u" }

function Client:NewFrame(frameType, name, parent, template)
    local client = self
    local frame = setmetatable({ [0] = newproxy(false) }, self.frameMeta)
    H.frameState[frame] = {
        type = frameType or "Frame", name = name, parent = parent, template = template,
        events = {}, scripts = {}, attributes = {}, children = {}, shown = true,
    }
    if parent and H.frameState[parent] then
        table.insert(H.frameState[parent].children, frame)
    end
    self.frames[#self.frames + 1] = frame
    if name then
        rawset(self.env, name, frame)
    end
    return frame
end

local function MakeFrameMeta(client)
    local generic = {}
    return {
        __index = function(frame, key)
            local method = FrameMethods[key]
            if method then
                return method
            end
            if type(key) ~= "string" or not client.listing.widgetMethods[key] then
                return nil
            end
            method = generic[key]
            if not method then
                local reads = false
                for _, pattern in ipairs(READS) do
                    reads = reads or key:find(pattern) ~= nil
                end
                if key:find("^Create%u") then
                    method = function(self) return client:NewFrame(key:sub(7), nil, self) end
                elseif reads then
                    -- What a frame answers is the game's to know.
                    method = function(self, ...)
                        local provider = client.provider
                        if provider and provider.FrameCall then
                            local results = { provider:FrameCall(State(self).type, key, ...) }
                            if results[1] then
                                return unpack(results, 2, table.maxn(results))
                            end
                        end
                        return nil
                    end
                else
                    method = function() end
                end
                generic[key] = method
            end
            return method
        end,
    }
end

------------------------------------------------------------------------------------------
-- A client
------------------------------------------------------------------------------------------

-- options: flavor ("forever" or "retail"), locale, provider, serverTime
function Client.New(options)
    local self = setmetatable({}, Client)
    self.flavor = options.flavor or "forever"
    self.locale = options.locale or "enUS"
    self.provider = options.provider
    self.clock, self.clockStart, self.profileStart = 1000, 1000, 1000
    self.serverTime = options.serverTime or 1700000000
    self.frames, self.timers = {}, {}
    self.printed, self.errors = {}, {}
    -- Functions the client refuses a secure hook on. GetCurrentEnvironment is one (Forever
    -- client, 1.60.1.70938); which others there are is not known, so code that hooks by a list
    -- has to survive a refusal. A scenario adds names to see that it does.
    self.forbiddenHooks = { GetCurrentEnvironment = true }
    self.unknown = {}    -- names nobody knows, in the order they were first read
    self.fromMirror = {} -- names answered by the listings mirror
    self.listing = LoadListing(self.flavor, self.locale)
    self.frameMeta = MakeFrameMeta(self)
    self.errorHandler = function(message)
        self.errors[#self.errors + 1] = tostring(message)
    end

    local seenUnknown, seenMirror = {}, {}
    -- Starts the list of unknown names again: a name read before is listed again when read.
    function self:ForgetUnknown()
        self.unknown, seenUnknown = {}, {}
    end
    local env = {}
    self.env = env
    InstallBasics(self, env)
    setmetatable(env, {
        __index = function(_, name)
            local default = H.CLIENT_DEFAULTS[name]
            if default ~= nil then
                local value = default(self)
                rawset(env, name, value)
                return value
            end
            local provider = self.provider
            if provider then
                local kind, value = provider:Resolve(name)
                if kind == "absent" then
                    return nil
                elseif kind then
                    rawset(env, name, value)
                    return value
                end
            end
            local mirrored = self.listing.strings[name]
            if mirrored == nil then
                mirrored = self.listing.enums[name]
            end
            if mirrored ~= nil then
                if not seenMirror[name] then
                    seenMirror[name] = true
                    self.fromMirror[#self.fromMirror + 1] = name
                end
                rawset(env, name, mirrored)
                return mirrored
            end
            if type(name) == "string" and not seenUnknown[name] then
                seenUnknown[name] = true
                self.unknown[#self.unknown + 1] = name
            end
            return nil
        end,
    })
    return self
end

function Client:ServerTime()
    return math.floor(self.serverTime + (self.clock - self.clockStart))
end

-- Runs a compiled file in this client, as the client runs an addon's file: with the addon's
-- name and its private table.
function Client:Run(chunk, ...)
    setfenv(chunk, self.env)
    return chunk(...)
end

-- One of Blizzard's files, by its path under Interface/AddOns in the source mirror.
function Client:LoadBlizzard(relative)
    local path = H.BuildsDir() .. "/source/" .. self.flavor .. "/Interface/AddOns/" .. relative
    local chunk, problem = H.Compile(path, "Interface/AddOns/" .. relative)
    if not chunk then
        error("the source mirror is needed for " .. relative .. ": " .. tostring(problem), 0)
    end
    return self:Run(chunk, relative:match("^[^/]+"), {})
end

-- A file of an addon in the repository. folder is the addon's folder on disk.
function Client:LoadAddonFile(addonName, folder, relative, namespace)
    relative = relative:gsub("\\", "/")
    local chunk, problem = H.Compile(folder .. "/" .. relative, "Interface/AddOns/" .. addonName .. "/" .. relative)
    if not chunk then
        error(tostring(problem), 0)
    end
    return self:Run(chunk, addonName, namespace)
end

function Client:Fire(event, ...)
    -- A handler may create a frame; that frame hears the next event, not this one.
    for index = 1, #self.frames do
        local frame = self.frames[index]
        local state = H.frameState[frame]
        if state.events[event] and state.scripts.OnEvent then
            local ok, problem = Guards.pcall(state.scripts.OnEvent, frame, event, ...)
            if not ok then
                self.errorHandler(problem)
            end
        end
    end
end

local function RunTimers(self)
    local due = {}
    for index = #self.timers, 1, -1 do
        local timer = self.timers[index]
        if timer.cancelled then
            table.remove(self.timers, index)
        elseif timer.at <= self.clock then
            if timer.every then
                timer.at = timer.at + timer.every
            else
                table.remove(self.timers, index)
            end
            table.insert(due, 1, timer)
        end
    end
    for _, timer in ipairs(due) do
        if not timer.cancelled then
            local ok, problem = Guards.pcall(timer.fn, timer)
            if not ok then
                self.errorHandler(problem)
            end
        end
    end
end

-- Frames of the client: the clock moves on, timers that are due run, then every OnUpdate.
function Client:Tick(count, seconds)
    seconds = seconds or 0.05
    for _ = 1, count or 1 do
        self.clock = self.clock + seconds
        RunTimers(self)
        for index = 1, #self.frames do
            local frame = self.frames[index]
            local state = H.frameState[frame]
            if state.scripts.OnUpdate and frame:IsVisible() then
                local ok, problem = Guards.pcall(state.scripts.OnUpdate, frame, seconds)
                if not ok then
                    self.errorHandler(problem)
                end
            end
        end
    end
end

-- Ticks until predicate() holds. False when the seconds ran out first.
function Client:TickUntil(predicate, seconds)
    local deadline = self.clock + (seconds or 10)
    while not predicate() do
        if self.clock >= deadline then
            return false
        end
        self:Tick(1)
    end
    return true
end
