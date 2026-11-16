-- Reads a saved variables file without compiling it.
--
-- A saved variables file is Lua, and loadfile reads a small one. But the client writes each
-- variable as one table constructor, and Lua compiles a file into one function, which holds
-- at most 65536 constants: a file with more distinct strings and numbers than that does not
-- load ("main function has more than 65536 constants"). The test addon's file on a toon with
-- several hundred items is past it. So this parses the text instead: assignments of tables,
-- strings, numbers, booleans and nil, with the client's "-- [1]" comments, which is all the
-- client ever writes.
--
--   local SavedVars = dofile("tools/savedvars.lua")
--   local globals, problem = SavedVars.Read(path)     -- { VariableName = value, ... }
--   local globals, problem = SavedVars.Parse(text, nameForMessages)

local SavedVars = {}

local find, sub, byte = string.find, string.sub, string.byte

function SavedVars.Parse(text, name)
    local pos = 1
    local length = #text

    local function fail(message)
        local line = 1
        for _ in text:sub(1, pos):gmatch("\n") do
            line = line + 1
        end
        error(("%s:%d: %s"):format(name or "saved variables", line, message), 0)
    end

    -- Past blanks and comments.
    local function skip()
        while true do
            local _, finish = find(text, "^[ \t\r\n]*", pos)
            pos = finish + 1
            if byte(text, pos) == 45 and byte(text, pos + 1) == 45 then
                local lineEnd = find(text, "\n", pos, true)
                pos = lineEnd and lineEnd + 1 or length + 1
            else
                return
            end
        end
    end

    local value

    local function str()
        local start, at, escaped = pos, pos + 1, false
        while true do
            local hit = find(text, '["\\]', at)
            if not hit then
                fail("a string that does not end")
            end
            if byte(text, hit) == 92 then
                escaped = true
                at = hit + 2
            else
                pos = hit + 1
                if not escaped then
                    return sub(text, start + 1, hit - 1)
                end
                -- Escapes are Lua's own: let Lua read this one literal.
                local chunk = loadstring("return " .. sub(text, start, hit))
                if not chunk then
                    pos = start
                    fail("a string Lua cannot read")
                end
                return chunk()
            end
        end
    end

    local function tbl()
        pos = pos + 1
        local result, count = {}, 0
        while true do
            skip()
            local c = byte(text, pos)
            if c == 125 then
                pos = pos + 1
                return result
            elseif c == nil then
                fail("a table that does not end")
            elseif c == 91 then
                pos = pos + 1
                skip()
                local key = value()
                skip()
                if byte(text, pos) ~= 93 then
                    fail("']' expected")
                end
                pos = pos + 1
                skip()
                if byte(text, pos) ~= 61 then
                    fail("'=' expected")
                end
                pos = pos + 1
                skip()
                local item = value()
                if key == nil then
                    fail("nil as a key")
                end
                result[key] = item
            else
                local nameStart, nameEnd = find(text, "^[%a_][%w_]*", pos)
                local afterName = nameEnd and find(text, "^%s*=[^=]", nameEnd + 1)
                if afterName then
                    local key = sub(text, nameStart, nameEnd)
                    pos = find(text, "=", nameEnd + 1, true) + 1
                    skip()
                    result[key] = value()
                else
                    count = count + 1
                    result[count] = value()
                end
            end
            skip()
            c = byte(text, pos)
            if c == 44 or c == 59 then
                pos = pos + 1
            end
        end
    end

    function value()
        local c = byte(text, pos)
        if c == 123 then
            return tbl()
        elseif c == 34 then
            return str()
        elseif c == 116 and sub(text, pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif c == 102 and sub(text, pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif c == 110 and sub(text, pos, pos + 2) == "nil" then
            pos = pos + 3
            return nil
        end
        local start, finish = find(text, "^-?%d*%.?%d+[eE][-+]?%d+", pos)
        if not start then
            start, finish = find(text, "^-?0[xX]%x+", pos)
        end
        if not start then
            start, finish = find(text, "^-?%d*%.?%d*", pos)
        end
        local number = start and finish >= start and tonumber(sub(text, start, finish))
        if not number then
            -- The client writes these two for numbers a literal cannot hold.
            local word = text:match("^-?[%a_][%w_.]*", pos)
            if word == "inf" or word == "math.huge" then
                pos = pos + #word
                return math.huge
            elseif word == "-inf" or word == "-math.huge" then
                pos = pos + #word
                return -math.huge
            elseif word == "nan" or word == "-nan" then
                pos = pos + #word
                return 0 / 0
            end
            fail("a value expected")
        end
        pos = finish + 1
        return number
    end

    local globals = {}
    while true do
        skip()
        if pos > length then
            return globals
        end
        local nameStart, nameEnd = find(text, "^[%a_][%w_]*", pos)
        if not nameStart then
            fail("a variable name expected")
        end
        local variable = sub(text, nameStart, nameEnd)
        pos = nameEnd + 1
        skip()
        if byte(text, pos) ~= 61 then
            fail("'=' expected after " .. variable)
        end
        pos = pos + 1
        skip()
        globals[variable] = value()
        skip()
        if byte(text, pos) == 59 then
            pos = pos + 1
        end
    end
end

-- The globals a saved variables file sets, or nil and why not.
function SavedVars.Read(path)
    local file, problem = io.open(path, "rb")
    if not file then
        return nil, problem
    end
    local text = file:read("*a")
    file:close()
    if text:sub(1, 3) == "\239\187\191" then
        text = text:sub(4)
    end
    local ok, result = pcall(SavedVars.Parse, text, path)
    if not ok then
        return nil, result
    end
    return result
end

return SavedVars
