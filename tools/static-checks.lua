-- Static checks for CaerdonWardrobe. Offline: this reads code, it does not run a client.
--
--   luajit tools/static-checks.lua [--builds DIR] [--verbose] [--emit-facts]
--
-- It reads the addon and the test addon (CaerdonWardrobe_Tests), which runs in the same
-- clients. --emit-facts writes two generated files into CaerdonWardrobe_Tests (not tracked):
-- StaticFacts.lua, what the check concluded, which the test addon compares with the client,
-- and ApiNames.lua, every name of the client the addon reads, which the test addon's recorder
-- hooks and captures. A run without the option reports either file when it is out of date.
--
-- What it checks, for retail and for Forever separately:
--   * every global the addon reads, every C_* function, namespace function and Enum value it
--     names, every event it registers or compares against and every global string it reads
--     exists in that client;
--   * every literal hooksecurefunc target exists in the Blizzard code that client loads;
--   * every global the addon writes is on the allowlist.
-- A name missing from one client or from both is a finding unless static-checks-allow.lua
-- lists it with the client it belongs to. Exit code 1 when anything is left.
--
-- It needs the mirrors described in docs/dev-notes.md (Client Sources): DIR/source/<flavor>
-- and DIR/resources/<flavor>. DIR defaults to $CAERDON_BUILDS, then ~/Projects/WoW/Builds.
--
-- How names are found:
--   * The addon's files are compiled with LuaJIT and the bytecode is read, so a global is a
--     global (scope is the compiler's verdict, comments and strings cannot confuse it).
--   * Each client's Blizzard code is treated the same way, but only the files that client
--     loads: the TOC conditions (AllowLoadGameType and friends) are evaluated per flavor.
--   * Events, hook targets and string literals come from a small lexer over the addon's source.
--
-- What it cannot see: names built at run time (_G["MerchantItem" .. i]), methods called on a
-- local or on a child reached through parentKeys, fields of a frame that are not methods,
-- other addons' code, and any locale but enUS. A clean run is evidence, not a client test.

local bit = require("bit")
local jutil = require("jit.util")
local vmdef = require("jit.vmdef")

------------------------------------------------------------------------------------------
-- Options and paths
------------------------------------------------------------------------------------------

local scriptDir = (arg[0] or ""):gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
local addonDir = scriptDir .. "/.."
local buildsDir = os.getenv("CAERDON_BUILDS")
local verbose = false
local emitFacts = false

-- The addons to read, as folders below the repository's root. The first is the addon itself.
local ADDON_ROOTS = { "", "CaerdonWardrobe_Tests/" }
local FACTS_FILE = "CaerdonWardrobe_Tests/StaticFacts.lua"
local NAMES_FILE = "CaerdonWardrobe_Tests/ApiNames.lua"

do
    local i = 1
    while arg[i] do
        if arg[i] == "--builds" then
            buildsDir = arg[i + 1]
            i = i + 1
        elseif arg[i] == "--verbose" then
            verbose = true
        elseif arg[i] == "--emit-facts" then
            emitFacts = true
        else
            io.stderr:write("usage: luajit tools/static-checks.lua [--builds DIR] [--verbose] [--emit-facts]\n")
            os.exit(2)
        end
        i = i + 1
    end
end

if not buildsDir then
    local home = os.getenv("HOME") or os.getenv("USERPROFILE") or "."
    buildsDir = home .. "/Projects/WoW/Builds"
end
buildsDir = buildsDir:gsub("\\", "/")

-- Game types a TOC condition can name, and the folder "[Game]" stands for. "[Family]" is
-- Mainline for both. A TOC with another family's suffix (_Classic, _Wrath, ...) is not read.
local FLAVORS = {
    { key = "retail", gameTypes = { mainline = true, standard = true }, gameFolder = "Standard" },
    { key = "forever", gameTypes = { mainline = true, camelot = true }, gameFolder = "Camelot" },
}
local OTHER_TOC_SUFFIXES = {
    classic = true, vanilla = true, tbc = true, wrath = true, cata = true, mists = true,
    standard = true, camelot = true, -- unless it is this flavor's own, handled below
}

------------------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------------------

-- A problem with the setup rather than with the addon: say so and stop with exit code 2.
local function fail(message)
    io.stderr:write("static-checks: " .. message .. "\n")
    os.exit(2)
end

local function readFile(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    if text:sub(1, 3) == "\239\187\191" then text = text:sub(4) end
    return (text:gsub("\r\n", "\n"))
end

local function runLines(command)
    local lines = {}
    local pipe = io.popen(command)
    if not pipe then return lines end
    for line in pipe:lines() do
        lines[#lines + 1] = (line:gsub("\r$", ""))
    end
    pipe:close()
    return lines
end

local function gitLines(dir, args)
    local null = package.config:sub(1, 1) == "\\" and "NUL" or "/dev/null"
    return runLines(('git -C "%s" %s 2>%s'):format(dir, args, null))
end

local function normalizePath(path)
    local parts = {}
    for part in path:gsub("\\", "/"):gmatch("[^/]+") do
        if part == ".." then
            parts[#parts] = nil
        elseif part ~= "." then
            parts[#parts + 1] = part
        end
    end
    return table.concat(parts, "/")
end

local function dirOf(path)
    return path:match("^(.*)/[^/]*$") or ""
end

local function trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function setOf(list)
    local set = {}
    for _, value in ipairs(list or {}) do set[value] = true end
    return set
end

------------------------------------------------------------------------------------------
-- Bytecode: the globals a chunk reads and writes, and the fields it reads off a global
------------------------------------------------------------------------------------------

local bcnames = vmdef.bcnames
local opcodeNames = {}
local function opcodeName(op)
    local name = opcodeNames[op]
    if not name then
        name = bcnames:sub(op * 6 + 1, op * 6 + 6):gsub("%s+$", "")
        opcodeNames[op] = name
    end
    return name
end

-- Operand modes of an instruction's A slot (lj_bc.h): it names a register the instruction
-- writes, or the first of a run of registers it writes.
local MODE_DST, MODE_BASE, MODE_RBASE = 1, 2, 4

-- visit(kind, name, line) with kind "read", "write" or "member". A member is a constant
-- field read off a global ("C_Item.GetItemInfo", "Enum.ItemBind.Quest", and "Frame.Method"
-- for Frame:Method()), also through a local that holds the global. Reads and writes through
-- _G count as reads and writes of the name itself.
--
-- The registers that hold a global are followed in instruction order, not along branches.
-- That is exact for the common shapes and can only misname a field in code that assigns
-- different globals to one local on different paths.
local function walkBytecode(func, visit)
    local info = jutil.funcinfo(func)
    local held = {} -- register -> the global (or global.field) it holds
    for pc = 1, info.bytecodes - 1 do
        local ins, mode = jutil.funcbc(func, pc)
        local op = opcodeName(bit.band(ins, 0xff))
        local a = bit.band(bit.rshift(ins, 8), 0xff)
        local d = bit.rshift(ins, 16)
        if op == "GGET" then
            local name = jutil.funck(func, -d - 1)
            held[a] = name
            if name ~= "_G" then visit("read", name, jutil.funcinfo(func, pc).currentline) end
        elseif op == "GSET" then
            visit("write", jutil.funck(func, -d - 1), jutil.funcinfo(func, pc).currentline)
        elseif op == "TGETS" then
            local owner = held[bit.rshift(ins, 24)]
            local name
            if owner then
                local key = jutil.funck(func, -bit.band(d, 0xff) - 1)
                local line = jutil.funcinfo(func, pc).currentline
                if owner == "_G" then
                    name = key
                    visit("read", key, line)
                else
                    name = owner .. "." .. key
                    visit("member", name, line)
                end
            end
            held[a] = name
        elseif op == "TSETS" then
            if held[bit.rshift(ins, 24)] == "_G" then
                visit("write", jutil.funck(func, -bit.band(d, 0xff) - 1), jutil.funcinfo(func, pc).currentline)
            end
        elseif op == "MOV" then
            held[a] = held[d]
        else
            local modeA = bit.band(mode, 7)
            if modeA == MODE_DST then
                held[a] = nil
            elseif modeA == MODE_BASE or modeA == MODE_RBASE then
                for register in pairs(held) do
                    if register >= a then held[register] = nil end
                end
            end
        end
    end
    for index = -1, -1000000000, -1 do
        local constant = jutil.funck(func, index)
        if constant == nil then break end
        if type(constant) == "proto" then walkBytecode(constant, visit) end
    end
end

------------------------------------------------------------------------------------------
-- Lexer: names, strings and symbols of a Lua source, comments dropped
------------------------------------------------------------------------------------------

local function countNewlines(text)
    local _, count = text:gsub("\n", "")
    return count
end

local function lex(text)
    local tokens, pos, line, length = {}, 1, 1, #text
    while pos <= length do
        local spaceStart, spaceEnd = text:find("^%s+", pos)
        if spaceStart then
            line = line + countNewlines(text:sub(spaceStart, spaceEnd))
            pos = spaceEnd + 1
        end
        if pos > length then break end
        local char = text:sub(pos, pos)
        if text:sub(pos, pos + 1) == "--" then
            local level = text:match("^%-%-%[(=*)%[", pos)
            if level then
                local _, close = text:find("]" .. level .. "]", pos, true)
                close = close or length
                line = line + countNewlines(text:sub(pos, close))
                pos = close + 1
            else
                pos = text:find("\n", pos, true) or (length + 1)
            end
        elseif char == '"' or char == "'" then
            local index = pos + 1
            while index <= length do
                local current = text:sub(index, index)
                if current == "\\" then
                    index = index + 2
                elseif current == char or current == "\n" then
                    break
                else
                    index = index + 1
                end
            end
            tokens[#tokens + 1] = { "string", text:sub(pos + 1, index - 1), line }
            pos = index + 1
        elseif text:find("^%[=*%[", pos) then
            local level = text:match("^%[(=*)%[", pos)
            local _, close = text:find("]" .. level .. "]", pos, true)
            close = close or length
            tokens[#tokens + 1] = { "string", text:sub(pos + #level + 2, close - #level - 2), line }
            line = line + countNewlines(text:sub(pos, close))
            pos = close + 1
        elseif char:find("[%a_]") then
            local _, finish = text:find("^[%w_]+", pos)
            tokens[#tokens + 1] = { "name", text:sub(pos, finish), line }
            pos = finish + 1
        elseif char:find("%d") then
            local _, finish = text:find("^[%w_]+%.?[%w_]*", pos)
            tokens[#tokens + 1] = { "number", text:sub(pos, finish), line }
            pos = finish + 1
        else
            local symbol = text:match("^%.%.%.", pos) or text:match("^[=~<>]=", pos)
                or text:match("^%.%.", pos) or char
            tokens[#tokens + 1] = { "symbol", symbol, line }
            pos = pos + #symbol
        end
    end
    return tokens
end

------------------------------------------------------------------------------------------
-- A client: its listings and the Blizzard code it loads
------------------------------------------------------------------------------------------

local function buildFromSubject(subject)
    local version, build = (subject or ""):match("^([%d%.]+) %((%d+)%)")
    return version and (version .. "." .. build) or "unknown"
end

local function loadListings(client, dir)
    local function load(name)
        local chunk, err = loadfile(dir .. "/Resources/" .. name)
        if not chunk then
            fail(("cannot read the listing %s for %s (%s). update.sh in the builds folder fetches it.")
                :format(name, client.key, tostring(err)))
        end
        return chunk
    end

    -- Functions: "Name" and "Namespace.Name".
    client.api, client.namespaces = {}, {}
    local function addNames(list)
        for _, name in ipairs(list) do
            client.api[name] = true
            local namespace = name:match("^([^.]+)%.")
            if namespace then client.namespaces[namespace] = true end
        end
    end
    -- The client's own functions, apart from the ones Blizzard's Lua defines.
    client.clientApi = {}
    for _, list in ipairs(load("GlobalAPI.lua")()) do
        addNames(list)
        for _, name in ipairs(list) do client.clientApi[name] = true end
    end
    for _, list in ipairs(load("FrameXML.lua")()) do addNames(list) end

    client.mixins = setOf(load("Mixins.lua")())

    -- Global frames, including the ones the client creates itself (UIParent, WorldFrame).
    client.frames = {}
    for _, list in ipairs(load("Frames.lua")()) do
        for _, name in ipairs(list) do client.frames[name] = true end
    end

    -- Methods the client gives a widget (Show, SetPoint, ...): no Lua file defines those.
    client.widgetMethods = {}
    for _, widget in pairs(load("WidgetAPI.lua")()) do
        for _, name in ipairs(widget.methods or {}) do client.widgetMethods[name] = true end
    end

    client.events = {}
    for _, group in pairs(load("Events.lua")()) do
        for _, event in ipairs(group) do client.events[event] = true end
    end

    -- Enum, Constants and the LE_* numbers are assigned as globals by the listing.
    client.enumEnv = {}
    setfenv(load("LuaEnum.lua"), client.enumEnv)()

    client.strings = {}
    local text = readFile(dir .. "/Resources/GlobalStrings/enUS.lua")
    if not text then fail("cannot read the listing GlobalStrings/enUS.lua for " .. client.key) end
    for line in text:gmatch("[^\n]+") do
        local name = line:match('^_G%["(.-)"%] = ') or line:match("^([%w_]+) = ")
        if name then client.strings[name] = true end
    end
end

local function tokensMatch(list, gameTypes)
    for token in list:lower():gmatch("[%a]+") do
        if gameTypes[token] then return true end
    end
    return false
end

-- Evaluates the [Condition ...] groups of a TOC line. Unknown conditions do not exclude.
-- side is "game" for the files loaded in the world and "glue" for the login screens.
local function conditionsHold(text, flavor, side)
    for condition in text:gmatch("%[([^%]]+)%]") do
        local key, rest = condition:match("^(%S+)%s*(.*)$")
        key = key:lower():gsub(":$", "")
        if key == "allowloadgametype" then
            if not tokensMatch(rest, flavor.gameTypes) then return false end
        elseif key == "excludeloadgametype" then
            if tokensMatch(rest, flavor.gameTypes) then return false end
        elseif key == "allowload" then
            rest = rest:lower()
            if rest ~= "both" and rest ~= side then return false end
        end
    end
    return true
end

-- Returns the files a TOC loads for this flavor on that side, or nil when the addon does not
-- load there at all.
local function readToc(text, flavor, side)
    local files = {}
    for line in text:gmatch("[^\n]+") do
        line = trim(line)
        local key, value = line:match("^##%s*([%w%-]+)%s*:%s*(.-)$")
        if key then
            if conditionsHold(value, flavor, side) then
                key = key:lower()
                local plain = trim(value:gsub("%[[^%]]*%]", "")):lower()
                if key == "allowloadgametype" and not tokensMatch(plain, flavor.gameTypes) then return nil end
                if key == "excludeloadgametype" and tokensMatch(plain, flavor.gameTypes) then return nil end
                if key == "allowload" and plain ~= "both" and plain ~= side then return nil end
                if key == "onlybetaandptr" and plain == "1" then return nil end
            end
        elseif line ~= "" and line:sub(1, 1) ~= "#" then
            line = line:gsub("%[[Ff]amily%]", "Mainline"):gsub("%[[Gg]ame%]", flavor.gameFolder)
            if conditionsHold(line, flavor, side) then
                local path = trim(line:gsub("%[[^%]]*%]", ""))
                if path ~= "" then files[#files + 1] = path end
            end
        end
    end
    return files
end

-- Tags whose name attribute does not name a global.
local XML_NAME_IS_NOT_A_GLOBAL = { Attribute = true, Binding = true, ModifiedClick = true }

-- Reads the named elements of an XML file. "$parent" is replaced by the name of the nearest
-- named ancestor. Inside a virtual template that ancestor is the template, so its children
-- are kept per template and get their real names when a frame inherits it (xmlNameSource).
local function readXml(client, text)
    text = text:gsub("<!%-%-.-%-%->", "")
    local includes, stack = {}, {}
    for closing, tag, attributes in text:gmatch("<(/?)(%a+)([^>]*)>") do
        if closing == "/" then
            for depth = #stack, 1, -1 do
                if stack[depth].tag == tag then
                    for index = #stack, depth, -1 do stack[index] = nil end
                    break
                end
            end
        elseif tag == "Script" or tag == "Include" then
            local file = attributes:match('file%s*=%s*"([^"]+)"')
            if file then includes[#includes + 1] = file end
        else
            local entry = { tag = tag }
            local raw = not XML_NAME_IS_NOT_A_GLOBAL[tag] and attributes:match('%f[%w]name%s*=%s*"([^"]+)"')
            if raw and raw:find("$parent", 1, true) then
                for depth = #stack, 1, -1 do
                    local owner = stack[depth]
                    if owner.name then
                        entry.name = raw:gsub("%$parent", function() return owner.name end)
                        entry.template = owner.template
                        break
                    end
                end
            elseif raw then
                entry.name = raw
                if attributes:match('%f[%w]virtual%s*=%s*"true"') then entry.template = raw end
            end
            if entry.name then
                local name, template = entry.name, entry.template
                if not template then
                    client.xmlNames[name] = true
                elseif name ~= template and name:sub(1, #template) == template then
                    local children = client.templateChildren[template] or {}
                    children[name:sub(#template + 1)] = name
                    client.templateChildren[template] = children
                end
                local parents = client.parents[name] or {}
                for _, attribute in ipairs({ "mixin", "secureMixin", "inherits" }) do
                    local list = attributes:match("%f[%w]" .. attribute .. '%s*=%s*"([^"]+)"')
                    for parent in (list or ""):gmatch("[%w_]+") do parents[#parents + 1] = parent end
                end
                if #parents > 0 then client.parents[name] = parents end
            end
            if attributes:sub(-1) ~= "/" then stack[#stack + 1] = entry end
        end
    end
    return includes
end

-- The events listing covers the documented events only. An event Blizzard's own code
-- registers by name is one the client knows as well.
local function readRegisteredEvents(client, text)
    for name in text:gmatch('Register%a*Event%a*%(%s*"([A-Z0-9_]+)"') do client.events[name] = true end
end

local function readBlizzardLua(client, path, text)
    readRegisteredEvents(client, text)
    local chunk = loadstring(text, "@" .. path)
    if not chunk then
        client.uncompiled[#client.uncompiled + 1] = path
        return
    end
    -- Blizzard_Deprecated holds the old names of changed APIs, as Lua. They are there while
    -- the CVar loadDeprecationFallbacks is on and until Blizzard deletes the file, so a name
    -- that file defines or wraps is noted apart.
    local deprecatedFile = path:find("/Blizzard_Deprecated/", 1, true) ~= nil
    local globalsRead = {}
    walkBytecode(chunk, function(kind, name)
        if kind == "read" then
            client.reads[name] = true
            globalsRead[name] = true
        elseif kind == "write" then
            client.writes[name] = true
            if deprecatedFile then client.deprecated[name] = path end
        end
    end)
    if deprecatedFile then
        -- Fields the file sets on a global: "function C_X.Name(", "C_X.Name = ...",
        -- "Enum.Name = { Value = 0, ... }". A local's field is not a global's.
        local function field(owner, name)
            if globalsRead[owner] then client.deprecated[owner .. "." .. name] = path end
        end
        for owner, name in text:gmatch("function%s+([%w_]+)[:%.]([%w_]+)%s*%(") do field(owner, name) end
        for owner, name in text:gmatch("%f[%w_]([%w_]+)%.([%w_]+)%s*=%f[^=]") do field(owner, name) end
        for owner, name, body in text:gmatch("%f[%w_]([%w_]+)%.([%w_]+)%s*=%s*(%b{})") do
            if owner == "Enum" or owner == "Constants" then
                for value in body:gmatch("([%w_]+)%s*=%f[^=]") do
                    client.deprecated[owner .. "." .. name .. "." .. value] = path
                end
            end
        end
    end
    -- Who defines which method: "function Owner:Name(", "function Owner.Name(", "Owner.Name = function".
    local function define(owner, name)
        client.members[owner .. "." .. name] = true
        local owners = client.methodOwners[name]
        if not owners then
            owners = {}
            client.methodOwners[name] = owners
        end
        owners[owner] = true
    end
    for owner, name in text:gmatch("function%s+([%w_]+)[:%.]([%w_]+)%s*%(") do define(owner, name) end
    for owner, name in text:gmatch("([%w_]+)%.([%w_]+)%s*=%s*function") do define(owner, name) end
    -- Mixin inheritance: X = CreateFromMixins(A, B), Mixin(X, A, B).
    for name, list in text:gmatch("([%w_]+)%s*=%s*CreateFromMixins%(([^)]*)%)") do
        local parents = client.parents[name] or {}
        for parent in list:gmatch("[%w_]+") do parents[#parents + 1] = parent end
        client.parents[name] = parents
    end
    for name, list in text:gmatch("%f[%w_]Mixin%(([%w_]+)%s*,([^)]*)%)") do
        local parents = client.parents[name] or {}
        for parent in list:gmatch("[%w_]+") do parents[#parents + 1] = parent end
        client.parents[name] = parents
    end
    -- Frames created with a literal name.
    for name in text:gmatch('CreateFrame%(%s*"[^"]*"%s*,%s*"([%w_]+)"') do client.xmlNames[name] = true end
end

local function loadClient(flavor)
    local client = {
        key = flavor.key,
        reads = {}, writes = {}, xmlNames = {}, templateChildren = {}, xmlSources = {},
        members = {}, methodOwners = {}, parents = {}, deprecated = {},
        uncompiled = {}, missingFiles = {}, skippedAddons = {}, loadedAddons = {}, luaFiles = 0, addons = 0,
    }

    local resources = buildsDir .. "/resources/" .. flavor.key
    local source = buildsDir .. "/source/" .. flavor.key
    loadListings(client, resources)
    client.listingBuild = buildFromSubject(gitLines(resources, "log -1 --format=%s")[1])
    client.sourceBuild = trim(readFile(source .. "/version.txt") or "unknown")

    -- The TOC paths are Windows paths; match them without regard to case.
    local actualPath, tocs = {}, {}
    for _, path in ipairs(gitLines(source, "ls-files")) do
        actualPath[path:lower()] = path
        local folder, name = path:match("^Interface/AddOns/([^/]+)/([^/]+)%.toc$")
        if folder then
            local suffix = (name:match("_(%a+)$") or ""):lower()
            local rank
            if suffix == flavor.gameFolder:lower() then
                rank = 3
            elseif suffix == "mainline" then
                rank = 2
            elseif not OTHER_TOC_SUFFIXES[suffix] then
                rank = 1
            end
            if rank and (not tocs[folder] or tocs[folder].rank < rank) then
                tocs[folder] = { rank = rank, path = path }
            end
        end
    end
    if not next(tocs) then fail("no Blizzard TOC files under " .. source .. " (is it a git clone of the source mirror?)") end

    local seen = {}
    local function loadFile(path)
        local actual = actualPath[normalizePath(path):lower()]
        if not actual then
            client.missingFiles[#client.missingFiles + 1] = path
            return
        end
        if seen[actual] then return end
        seen[actual] = true
        local text = readFile(source .. "/" .. actual)
        if actual:lower():match("%.xml$") then
            for _, include in ipairs(readXml(client, text)) do
                loadFile(dirOf(actual) .. "/" .. include)
            end
        elseif actual:lower():match("%.lua$") then
            client.luaFiles = client.luaFiles + 1
            readBlizzardLua(client, actual, text)
        end
    end

    -- The login screens run in the same client, so they are read for the events they
    -- register and for nothing else: their globals do not exist in the world.
    local seenGlue = {}
    local function loadGlueFile(path)
        local actual = actualPath[normalizePath(path):lower()]
        if not actual or seen[actual] or seenGlue[actual] then return end
        seenGlue[actual] = true
        local text = readFile(source .. "/" .. actual)
        if actual:lower():match("%.xml$") then
            for tag, file in text:gsub("<!%-%-.-%-%->", ""):gmatch('<(%a+)%s+file%s*=%s*"([^"]+)"') do
                if tag == "Script" or tag == "Include" then loadGlueFile(dirOf(actual) .. "/" .. file) end
            end
        elseif actual:lower():match("%.lua$") then
            readRegisteredEvents(client, text)
        end
    end

    for _, folder in ipairs(sortedKeys(tocs)) do
        local toc = tocs[folder]
        local tocText = readFile(source .. "/" .. toc.path)
        local files = readToc(tocText, flavor, "game")
        if files then
            client.addons = client.addons + 1
            client.loadedAddons[#client.loadedAddons + 1] = folder
            for _, file in ipairs(files) do loadFile(dirOf(toc.path) .. "/" .. file) end
        else
            client.skippedAddons[#client.skippedAddons + 1] = folder
        end
        for _, file in ipairs(readToc(tocText, flavor, "glue") or {}) do
            loadGlueFile(dirOf(toc.path) .. "/" .. file)
        end
    end
    return client
end

-- Calls visit(name) for a frame, template or mixin and everything it inherits from, until
-- visit returns something.
local function eachAncestor(client, root, visit)
    local seen, queue = {}, { root }
    while #queue > 0 do
        local name = table.remove(queue)
        if not seen[name] then
            seen[name] = true
            local result = visit(name)
            if result then return result end
            for _, parent in ipairs(client.parents[name] or {}) do queue[#queue + 1] = parent end
        end
    end
    return nil
end

-- The XML element behind a frame name: the name itself when an element or a listing carries
-- it, otherwise the template child it was generated from. MerchantItem1ItemButton is
-- MerchantItem1 (inherits MerchantItemTemplate) plus that template's "$parentItemButton".
local function xmlNameSource(client, name, depth)
    if client.xmlNames[name] or client.frames[name] then return name end
    local known = client.xmlSources[name]
    if known ~= nil then return known or nil end
    depth = depth or 0
    local source = false
    if depth < 4 then
        for split = #name - 1, 1, -1 do
            local owner = xmlNameSource(client, name:sub(1, split), depth + 1)
            if owner then
                local suffix = name:sub(split + 1)
                source = eachAncestor(client, owner, function(ancestor)
                    local children = client.templateChildren[ancestor]
                    return children and children[suffix]
                end) or false
                if source then break end
            end
        end
    end
    client.xmlSources[name] = source
    return source or nil
end

-- Whether a listing names the global or the client's loaded code defines it. That Blizzard's
-- code merely reads a name proves nothing: it reads globals of other game types behind guards.
local function definesGlobal(client, name)
    return (client.api[name] or client.namespaces[name] or client.mixins[name]
        or client.strings[name] or client.enumEnv[name] ~= nil
        or client.writes[name] or xmlNameSource(client, name)) and true or false
end

-- Whether a global frame or mixin has the method: defined on it, on one of its mixins or
-- templates (followed through XML and CreateFromMixins), or given to every widget by the client.
local function definesMethod(client, root, method)
    local frame = xmlNameSource(client, root)
    local defined = eachAncestor(client, frame or root, function(ancestor)
        return client.members[ancestor .. "." .. method]
    end)
    return (defined or (frame and client.widgetMethods[method])) and true or false
end

------------------------------------------------------------------------------------------
-- The addon
------------------------------------------------------------------------------------------

local function loadAddon()
    local addon = {
        files = {}, reads = {}, writes = {}, members = {}, ownNames = {},
        events = {}, literals = {}, hooks = {}, dynamicHooks = {},
    }

    local function note(map, name, file, line)
        local places = map[name]
        if not places then
            places = {}
            map[name] = places
        end
        places[#places + 1] = file .. ":" .. line
    end

    local function scanLua(file, text)
        local chunk, err = loadstring(text, "@" .. file)
        if not chunk then fail("cannot compile " .. file .. ": " .. tostring(err)) end
        local fileReads = {}
        walkBytecode(chunk, function(kind, name, line)
            if kind == "read" then
                fileReads[name] = true
                note(addon.reads, name, file, line)
            elseif kind == "write" then
                note(addon.writes, name, file, line)
            else
                note(addon.members, name, file, line)
            end
        end)

        local tokens = lex(text)
        local function isSymbol(token, symbol) return token and token[1] == "symbol" and token[2] == symbol end
        for index, token in ipairs(tokens) do
            local kind, value, line = token[1], token[2], token[3]
            local nextToken, afterNext = tokens[index + 1], tokens[index + 2]
            if kind == "string" then
                if value:match("^[A-Z][A-Z0-9_]+$") then note(addon.literals, value, file, line) end
            elseif kind == "name" then
                if value:match("^Register%a*Event$") or value == "UnregisterEvent" or value == "IsEventRegistered" then
                    -- f:RegisterEvent("X"), f:RegisterEvent "X", pcall(f.RegisterEvent, f, "X")
                    for ahead = index + 1, index + 4 do
                        local candidate = tokens[ahead]
                        if not candidate or isSymbol(candidate, ")") then break end
                        if candidate[1] == "string" then
                            note(addon.events, candidate[2], file, line)
                            break
                        end
                    end
                elseif value == "event" and isSymbol(nextToken, "==") and afterNext and afterNext[1] == "string"
                    and afterNext[2]:match("^[A-Z][A-Z0-9_]+$") then
                    note(addon.events, afterNext[2], file, line)
                elseif value == "function" and nextToken and nextToken[1] == "name" then
                    -- function SomeMixin:SOME_EVENT(...): the features name a handler after its event.
                    local cursor = index + 2
                    while isSymbol(tokens[cursor], ".") do cursor = cursor + 2 end
                    local method = isSymbol(tokens[cursor], ":") and tokens[cursor + 1]
                    if method and method[1] == "name" and method[2]:match("^[A-Z][A-Z0-9]*_[A-Z0-9_]+$") then
                        note(addon.events, method[2], file, line)
                    end
                elseif value == "hooksecurefunc" and isSymbol(nextToken, "(") and afterNext then
                    if afterNext[1] == "string" then
                        addon.hooks[#addon.hooks + 1] = { name = afterNext[2], place = file .. ":" .. line }
                    else
                        -- hooksecurefunc(Some.Global.Path, "Method", ...)
                        local path, cursor = {}, index + 2
                        while tokens[cursor] and tokens[cursor][1] == "name" do
                            path[#path + 1] = tokens[cursor][2]
                            if isSymbol(tokens[cursor + 1], ".") then cursor = cursor + 2 else cursor = cursor + 1; break end
                        end
                        local method = tokens[cursor + 1]
                        if #path > 0 and fileReads[path[1]] and isSymbol(tokens[cursor], ",")
                            and method and method[1] == "string" then
                            addon.hooks[#addon.hooks + 1] = {
                                path = table.concat(path, "."), root = path[1], method = method[2],
                                place = file .. ":" .. line,
                            }
                        else
                            addon.dynamicHooks[#addon.dynamicHooks + 1] = file .. ":" .. line
                        end
                    end
                end
            end
        end
    end

    local seen = {}
    local function loadFile(path)
        path = normalizePath(path)
        if seen[path] or path:lower():match("^libs/") then return end
        seen[path] = true
        local text = readFile(addonDir .. "/" .. path)
        if not text then
            -- A "*.local.lua" file is one machine's own and is not tracked.
            if path:lower():match("%.local%.lua$") then return end
            -- Generated and not tracked: its absence is noted in the report.
            if path == FACTS_FILE or path == NAMES_FILE then return end
            fail("the addon loads " .. path .. ", which is missing")
        end
        if path:lower():match("%.xml$") then
            text = text:gsub("<!%-%-.-%-%->", "")
            for name in text:gmatch('%f[%w]name%s*=%s*"([^"$]+)"') do addon.ownNames[name] = true end
            for tag, file in text:gmatch('<(%a+)%s+file%s*=%s*"([^"]+)"') do
                if tag == "Script" or tag == "Include" then loadFile(dirOf(path) .. "/" .. file) end
            end
        elseif path:lower():match("%.lua$") then
            addon.files[#addon.files + 1] = path
            scanLua(path, text)
        end
    end

    -- Untracked files count too, so a new file is checked before its first commit.
    local files = gitLines(addonDir, "ls-files --cached --others --exclude-standard")
    for index, root in ipairs(ADDON_ROOTS) do
        local tocText
        for _, file in ipairs(files) do
            if file:sub(1, #root) == root and file:sub(#root + 1):match("^[^/]+%.toc$") then
                tocText = readFile(addonDir .. "/" .. file)
                break
            end
        end
        if tocText then
            for line in tocText:gmatch("[^\n]+") do
                line = trim(line)
                local savedVariables = line:match("^##%s*SavedVariables%a*%s*:%s*(.+)$")
                if savedVariables then
                    for name in savedVariables:gmatch("[%w_]+") do addon.ownNames[name] = true end
                elseif line ~= "" and line:sub(1, 1) ~= "#" then
                    loadFile(root .. line)
                end
            end
        elseif index == 1 then
            fail("no TOC file in " .. addonDir)
        end
    end

    addon.notLoaded = {}
    for _, file in ipairs(files) do
        local lower = file:lower()
        if (lower:match("%.lua$") or lower:match("%.xml$")) and not seen[file]
            and not lower:match("^tools/") and not lower:match("^libs/") and lower ~= "bindings.xml" then
            addon.notLoaded[#addon.notLoaded + 1] = file
        end
    end
    for name in pairs(addon.writes) do addon.ownNames[name] = true end
    return addon
end

------------------------------------------------------------------------------------------
-- Checks
------------------------------------------------------------------------------------------

local allow = dofile(scriptDir .. "/static-checks-allow.lua")
local clients = {}
for index, flavor in ipairs(FLAVORS) do clients[index] = loadClient(flavor) end
local retail, forever = clients[1], clients[2]
local addon = loadAddon()

local findings = {}       -- section -> list of lines
local sectionOrder = {}
local findingCount, allowedCount = 0, 0
local allowUsed = {}

local function places(list)
    local seen, unique = {}, {}
    for _, place in ipairs(list) do
        if not seen[place] then
            seen[place] = true
            unique[#unique + 1] = place
        end
    end
    local shown = table.concat(unique, ", ", 1, math.min(#unique, 3))
    if #unique > 3 then shown = shown .. (", +%d more"):format(#unique - 3) end
    return shown
end

local function report(section, line)
    if not findings[section] then
        findings[section] = {}
        sectionOrder[#sectionOrder + 1] = section
    end
    table.insert(findings[section], line)
    findingCount = findingCount + 1
end

-- What the check concluded, for the test addon to compare with the client (--emit-facts):
-- names and events that are not in both clients, and every hook target with its state.
local staticFacts = { names = {}, events = {}, hooks = {}, deprecated = {} }

-- inRetail / inForever: whether each client has the name. Both true is the normal case.
-- factKind files the conclusion under staticFacts.
local function compare(section, name, inRetail, inForever, where, factKind)
    local state = (inRetail and inForever) and "both" or inRetail and "retail" or inForever and "forever" or "neither"
    if factKind and (state ~= "both" or factKind == "hooks") then staticFacts[factKind][name] = state end
    if state == "both" then return end
    local entry = allow.clientSpecific[name]
    if entry then
        allowUsed[name] = true
        if entry[1] == state then
            allowedCount = allowedCount + 1
            return
        end
        report(section, ("%-52s %-8s %s   (the allowlist says: %s)"):format(name, state, where, entry[1]))
        return
    end
    report(section, ("%-52s %-8s %s"):format(name, state, where))
end

local function isThirdParty(name)
    return allow.thirdParty[name] ~= nil
end

-- A global exists when the client defines it, or when the allowlist vouches for it and
-- Blizzard's own loaded code reads it as a global too.
local function hasGlobal(client, name)
    if definesGlobal(client, name) then return true end
    if allow.unlisted[name] and client.reads[name] then
        allowUsed["unlisted:" .. name] = true
        return true
    end
    return false
end

-- 1. Global writes.
do
    local section = "Global writes that are not on the allowlist"
    local allowed = setOf(allow.writes)
    for _, name in ipairs(sortedKeys(addon.writes)) do
        local ok = allowed[name]
        for _, pattern in ipairs(allow.writePatterns) do
            if name:match(pattern) then ok = true end
        end
        if not ok then report(section, ("%-52s %s"):format(name, places(addon.writes[name]))) end
    end
    for _, name in ipairs(allow.writes) do
        if not addon.writes[name] then
            report("Allowlist entries that no longer apply", ("%-52s writes: the addon does not write it"):format(name))
        end
    end
end

-- 2. Global reads.
do
    local section = "Globals the addon reads (client that has it, where it is read)"
    for _, name in ipairs(sortedKeys(addon.reads)) do
        if not addon.ownNames[name] and not isThirdParty(name) then
            local kind = (retail.strings[name] or forever.strings[name]) and "Global strings the addon reads" or section
            compare(kind, name, hasGlobal(retail, name), hasGlobal(forever, name), places(addon.reads[name]), "names")
        elseif isThirdParty(name) then
            allowUsed["thirdParty:" .. name] = true
        end
    end
end

-- 3. Fields read off a global: C_* functions, namespace functions, Enum and Constants values.
local unresolvedMembers = {}
do
    local functions = "Functions the addon names (client that has it, where it is named)"
    local enums = "Enum and Constants values the addon names"
    local function enumValue(client, path)
        local value = client.enumEnv
        for part in path:gmatch("[^.]+") do
            if type(value) ~= "table" then return client.deprecated[path] ~= nil end
            value = value[part]
        end
        return value ~= nil or client.deprecated[path] ~= nil
    end
    for _, name in ipairs(sortedKeys(addon.members)) do
        local root, first, deeper = name:match("^([^.]+)%.([^.]+)(.*)$")
        local where = places(addon.members[name])
        if addon.ownNames[root] or isThirdParty(root) then
            -- the addon's own tables and other addons' are not the client's business
        elseif root == "Enum" or root == "Constants" then
            -- A value of an enum that is itself missing is not a second finding.
            local parent = name:match("^(.*)%.[^.]+$")
            local inRetail, inForever = enumValue(retail, name), enumValue(forever, name)
            if parent == root or inRetail ~= enumValue(retail, parent) or inForever ~= enumValue(forever, parent) then
                compare(enums, name, inRetail, inForever, where, "names")
            end
        elseif deeper == "" then
            -- A function of a namespace, or a method of a global frame or mixin.
            local function has(client)
                return (client.api[name] or definesMethod(client, root, first)) and true or false
            end
            if root:match("^C_") then
                compare(functions, name, (retail.api[name] or retail.deprecated[name]) and true or false,
                    (forever.api[name] or forever.deprecated[name]) and true or false, where, "names")
            elseif has(retail) or has(forever) then
                compare(functions, name, has(retail), has(forever), where, "names")
            elseif retail.namespaces[root] or forever.namespaces[root] then
                unresolvedMembers[#unresolvedMembers + 1] = ("%-52s %s"):format(name, where)
            end
        end
    end
end

-- 4. Events.
do
    local section = "Events the addon registers or handles (client that has it, where)"
    local seen = {}
    for _, name in ipairs(sortedKeys(addon.events)) do
        seen[name] = true
        compare(section, name, retail.events[name] or false, forever.events[name] or false, places(addon.events[name]),
            "events")
    end
    -- A string that is an event (or a global string) in one client only is worth a look
    -- wherever it appears: a table of event names, a name passed to _G[...].
    for _, name in ipairs(sortedKeys(addon.literals)) do
        if not seen[name] and retail.events[name] ~= forever.events[name] then
            compare("String literals that are an event in one client only", name,
                retail.events[name] or false, forever.events[name] or false, places(addon.literals[name]))
        elseif not addon.reads[name] and retail.strings[name] ~= forever.strings[name] then
            compare("String literals that are a global string in one client only", name,
                retail.strings[name] or false, forever.strings[name] or false, places(addon.literals[name]))
        end
    end
end

-- 5. Hook targets.
local thirdPartyHooks = {}
do
    local section = "hooksecurefunc targets"
    local function hasMethod(client, hook)
        -- A function of one of the client's namespaces (C_EquipmentSet.DeleteEquipmentSet) is
        -- no Lua of Blizzard's: the listing names it.
        if client.api[hook.path .. "." .. hook.method] then return true end
        if not definesGlobal(client, hook.root) then return false end
        if hook.path ~= hook.root then
            -- A child reached through parentKeys: the frame tree is not resolved, so any
            -- loaded definition of the method name has to do.
            return (client.methodOwners[hook.method] ~= nil or client.widgetMethods[hook.method]) and true or false
        end
        return definesMethod(client, hook.root, hook.method)
    end
    for _, hook in ipairs(addon.hooks) do
        if hook.name and isThirdParty(hook.name) then
            -- Another addon's global function, hooked by its name: no client has it.
            allowUsed["thirdParty:" .. hook.name] = true
            thirdPartyHooks[#thirdPartyHooks + 1] = ("%s  %s"):format(hook.name, hook.place)
        elseif hook.name then
            local function has(client) return (client.api[hook.name] or client.writes[hook.name]) and true or false end
            compare(section, hook.name, has(retail), has(forever), hook.place, "hooks")
        elseif addon.ownNames[hook.root] then
            -- The test addon hooks the addon's own frame, which is not the client's business.
        elseif isThirdParty(hook.root) then
            allowUsed["thirdParty:" .. hook.root] = true
            thirdPartyHooks[#thirdPartyHooks + 1] = ("%s.%s  %s"):format(hook.path, hook.method, hook.place)
        else
            compare(section, hook.path .. "." .. hook.method, hasMethod(retail, hook), hasMethod(forever, hook),
                hook.place, "hooks")
        end
    end
end

-- 6. Names that come from Blizzard's deprecation fallbacks.
do
    local section = "Names Blizzard's deprecation fallbacks define or wrap (there while the CVar loadDeprecationFallbacks is on, until Blizzard deletes them)"
    local used = {}
    for name, list in pairs(addon.reads) do used[name] = list end
    for name, list in pairs(addon.members) do used[name] = list end
    for _, hook in ipairs(addon.hooks) do
        if hook.name then used[hook.name] = used[hook.name] or { hook.place } end
    end
    for _, name in ipairs(sortedKeys(used)) do
        local inRetail, inForever = retail.deprecated[name], forever.deprecated[name]
        -- A value of a deprecated enum is not a second finding.
        local parent = name:match("^(.*)%.[^.]+$")
        local parentToo = parent and (retail.deprecated[parent] or forever.deprecated[parent])
        if (inRetail or inForever) and not parentToo then
            local state = (inRetail and inForever) and "both" or inRetail and "retail" or "forever"
            staticFacts.deprecated[name] = state
            if allow.deprecated[name] then
                allowUsed["deprecated:" .. name] = true
                allowedCount = allowedCount + 1
            else
                report(section, ("%-52s %-8s %s   (%s)"):format(name, state, places(used[name]),
                    (inRetail or inForever):match("[^/]+$")))
            end
        end
    end
end

-- 7. Allowlist entries nothing needed.
do
    local section = "Allowlist entries that no longer apply"
    for _, name in ipairs(sortedKeys(allow.deprecated)) do
        if not allowUsed["deprecated:" .. name] then
            report(section, ("%-52s deprecated: no deprecation fallback defines it, or the addon no longer names it"):format(name))
        end
    end
    for _, name in ipairs(sortedKeys(allow.clientSpecific)) do
        if not allowUsed[name] then
            report(section, ("%-52s clientSpecific: both clients have it, or the addon no longer names it"):format(name))
        end
    end
    for _, name in ipairs(sortedKeys(allow.unlisted)) do
        if not allowUsed["unlisted:" .. name] then
            report(section, ("%-52s unlisted: a listing or definition covers it now, or the addon no longer reads it"):format(name))
        end
    end
    for _, name in ipairs(sortedKeys(allow.thirdParty)) do
        if not allowUsed["thirdParty:" .. name] then
            report(section, ("%-52s thirdParty: the addon no longer reads it"):format(name))
        end
    end
end

------------------------------------------------------------------------------------------
-- Facts for the test addon
------------------------------------------------------------------------------------------

-- The file is generated, so it is compared as text: the same conclusions give the same bytes.
local function factsText()
    local out = {
        "-- Generated by `luajit tools/static-checks.lua --emit-facts`. Do not edit.",
        "--",
        "-- What the static check concluded about each client from Blizzard's code and listings.",
        "-- The \"static.*\" contracts compare it with the client itself.",
        "",
        "local _, T = ...",
        "",
        "T.StaticFacts = {",
        "    -- The builds of Blizzard's code the conclusions were drawn from.",
        ("    builds = { retail = %q, forever = %q },"):format(retail.sourceBuild, forever.sourceBuild),
    }
    local function map(name, comment, values)
        out[#out + 1] = ""
        out[#out + 1] = "    -- " .. comment
        out[#out + 1] = "    " .. name .. " = {"
        for _, key in ipairs(sortedKeys(values)) do
            out[#out + 1] = ("        [%q] = %q,"):format(key, values[key])
        end
        out[#out + 1] = "    },"
    end
    local function lists(name, comment, field)
        out[#out + 1] = ""
        out[#out + 1] = "    -- " .. comment
        out[#out + 1] = "    " .. name .. " = {"
        for _, client in ipairs(clients) do
            local names = {}
            for index, value in ipairs(client[field]) do names[index] = value end
            table.sort(names)
            out[#out + 1] = "        " .. client.key .. " = {"
            for _, value in ipairs(names) do out[#out + 1] = ("            %q,"):format(value) end
            out[#out + 1] = "        },"
        end
        out[#out + 1] = "    },"
    end
    map("names", "Names the addon uses that one client lacks, or both: name -> the client that has it.",
        staticFacts.names)
    map("deprecated", "Names the addon uses that a deprecation fallback defines or wraps: name -> the clients whose fallbacks do.",
        staticFacts.deprecated)
    map("events", "Events the addon uses that one client lacks, or both.", staticFacts.events)
    map("hooks", "Literal hooksecurefunc targets on Blizzard names: target -> the clients that have it.",
        staticFacts.hooks)
    lists("notLoaded", "Blizzard addons the check says a client never loads.", "skippedAddons")
    lists("loads", "Blizzard addons the check says a client loads, at login or on demand.", "loadedAddons")
    out[#out + 1] = "}"
    out[#out + 1] = ""
    return table.concat(out, "\n")
end

-- Every name of the client the addon itself reads, for the test addon's recorder: a global,
-- or a field read off one by its full path. The kind says what the recorder may do with it:
-- "api" is a function of the client's own (the GlobalAPI listing of either client), "other"
-- belongs to another addon, "" is anything else (a string, a number, a frame, Blizzard's Lua).
-- The addon's own names and Lua's are left out, and so is what only the test addon reads.
local function namesText()
    local function inAddon(placeList)
        for _, place in ipairs(placeList) do
            if place:sub(1, #ADDON_ROOTS[2]) ~= ADDON_ROOTS[2] then return true end
        end
        return false
    end
    local names = {}
    local function add(name, placeList)
        local root = name:match("^[^.]+")
        if addon.ownNames[root] or _G[root] ~= nil or not inAddon(placeList) then return end
        if allow.thirdParty[root] then
            names[name] = "other"
        elseif retail.clientApi[name] or forever.clientApi[name] then
            names[name] = "api"
        else
            names[name] = ""
        end
    end
    for name, placeList in pairs(addon.reads) do add(name, placeList) end
    for name, placeList in pairs(addon.members) do add(name, placeList) end
    -- A hook target is named in a string, so it is no read: hooksecurefunc("EquipPendingItem", ...).
    for _, hook in ipairs(addon.hooks) do
        add(hook.name or (hook.path .. "." .. hook.method), { hook.place })
    end
    -- A global string looked up by its name: _G[globalName], with the name a literal elsewhere.
    for name, placeList in pairs(addon.literals) do
        if retail.strings[name] or forever.strings[name] then add(name, placeList) end
    end

    -- The offline harness runs some of Blizzard's own Lua under the addon (Item.lua and the
    -- like) instead of mocking it. What those files ask the client has to be recorded as well.
    local baseFiles = dofile(scriptDir .. "/harness/blizzard-base.lua")
    for _, flavor in ipairs(FLAVORS) do
        for _, relative in ipairs(baseFiles) do
            local text = readFile(buildsDir .. "/source/" .. flavor.key .. "/Interface/AddOns/" .. relative)
            local chunk = text and loadstring(text, "@" .. relative)
            if not chunk then fail("cannot read " .. relative .. " in the " .. flavor.key .. " source mirror") end
            walkBytecode(chunk, function(kind, name)
                if kind ~= "write" then add(name, { relative }) end
            end)
        end
    end

    local out = {
        "-- Generated by `luajit tools/static-checks.lua --emit-facts`. Do not edit.",
        "--",
        "-- Every name of the client the addon reads: a global, or a field read off one. The",
        "-- recorder (Recorder.lua) captures what each is in this client and hooks the functions.",
        "-- \"api\" is a function of the client's own, \"other\" another addon's, \"\" anything else.",
        "",
        "local _, T = ...",
        "",
        "T.ApiNames = {",
    }
    for _, name in ipairs(sortedKeys(names)) do
        out[#out + 1] = ("    [%q] = %q,"):format(name, names[name])
    end
    out[#out + 1] = "}"
    out[#out + 1] = ""
    return table.concat(out, "\n")
end

-- The generated files are compared as text. Neither is tracked, so a clone without one is
-- not at fault; a stale one is, because the test addon would work from yesterday's code.
local generatedMissing = {}
for _, generated in ipairs({ { FACTS_FILE, factsText() }, { NAMES_FILE, namesText() } }) do
    local file, text = generated[1], generated[2]
    local path = addonDir .. "/" .. file
    if emitFacts then
        local handle = io.open(path, "wb")
        if not handle then fail("cannot write " .. path) end
        handle:write(text)
        handle:close()
    else
        local existing = readFile(path)
        if existing == nil then
            generatedMissing[#generatedMissing + 1] = file
        elseif existing ~= text then
            report("Generated files that are out of date",
                ("%-52s run the check with --emit-facts"):format(file))
        end
    end
end

------------------------------------------------------------------------------------------
-- Report
------------------------------------------------------------------------------------------

print("CaerdonWardrobe static checks (offline: Blizzard's code and listings, no client)")
for _, client in ipairs(clients) do
    print(("  %-8s source %s, listings %s%s; %d Blizzard addons loaded (%d Lua files), %d not loaded"):format(
        client.key, client.sourceBuild, client.listingBuild,
        client.sourceBuild ~= client.listingBuild and " (the listings are a different build)" or "",
        client.addons, client.luaFiles, #client.skippedAddons))
end
do
    local reads, writes, members = #sortedKeys(addon.reads), #sortedKeys(addon.writes), #sortedKeys(addon.members)
    print(("  addon    %d Lua files; %d globals read, %d written, %d fields read off globals, %d events, %d literal hook targets"):format(
        #addon.files, reads, writes, members, #sortedKeys(addon.events), #addon.hooks))
end

for _, section in ipairs(sectionOrder) do
    print("")
    print(("== %s (%d)"):format(section, #findings[section]))
    for _, line in ipairs(findings[section]) do print("  " .. line) end
end

print("")
print("== Not checked")
print(("  %d hooksecurefunc calls on another addon's table or function (their source is not read):"):format(#thirdPartyHooks))
for _, line in ipairs(thirdPartyHooks) do print("    " .. line) end
print(("  %d hooksecurefunc calls on a local value: %s"):format(#addon.dynamicHooks, table.concat(addon.dynamicHooks, ", ")))
if #unresolvedMembers > 0 then
    print(("  fields of a Blizzard namespace that no listing or function definition names (%d):"):format(#unresolvedMembers))
    for _, line in ipairs(unresolvedMembers) do print("    " .. line) end
end
if #addon.notLoaded > 0 then
    print(("  %d tracked files the TOC never reaches: %s"):format(#addon.notLoaded, table.concat(addon.notLoaded, ", ")))
end
for _, file in ipairs(generatedMissing) do
    print(("  %s is not there: --emit-facts writes it, and what the test addon does with it is skipped without it"):format(file))
end
for _, client in ipairs(clients) do
    if #client.uncompiled > 0 or #client.missingFiles > 0 then
        print(("  %s: %d Blizzard files did not compile, %d named by a TOC or XML file are not in the mirror"):format(
            client.key, #client.uncompiled, #client.missingFiles))
    end
end

if verbose then
    print("")
    print("== Verbose")
    for _, client in ipairs(clients) do
        print(("  %s does not load: %s"):format(client.key, table.concat(client.skippedAddons, ", ")))
        for _, path in ipairs(client.uncompiled) do print("  " .. client.key .. " did not compile: " .. path) end
        for _, path in ipairs(client.missingFiles) do print("  " .. client.key .. " is missing a named file: " .. path) end
    end
end

print("")
print(("Result: %d finding%s, %d name%s accepted by the allowlist."):format(
    findingCount, findingCount == 1 and "" or "s", allowedCount, allowedCount == 1 and "" or "s"))
os.exit(findingCount == 0 and 0 or 1)
