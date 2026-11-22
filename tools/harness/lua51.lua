-- Makes LuaJIT as strict as the client's Lua 5.1 in the two ways that have bitten:
--   * the client cannot yield across pcall, xpcall or a secure hook; LuaJIT can;
--   * the client's %s takes strings and numbers only; LuaJIT formats anything.
-- Code that passes here can still fail in the client for other reasons. Code that fails here
-- would have failed there.
--
-- The guards replace pcall, xpcall, coroutine.yield and string.format for the whole process,
-- the harness included, so the harness keeps to the same two rules.

local H = ...

local Guards = { pcall = pcall, xpcall = xpcall, yield = coroutine.yield, format = string.format }
H.Guards = Guards

local depth = setmetatable({}, { __mode = "k" })
local installed = false

-- Runs f with yielding forbidden, as inside the client's pcall.
function Guards.Protected(f, ...)
    local thread = coroutine.running() or "main"
    depth[thread] = (depth[thread] or 0) + 1
    local results = { Guards.pcall(f, ...) }
    depth[thread] = depth[thread] - 1
    return unpack(results, 1, table.maxn(results))
end

-- The client's format takes an argument by its position ("%2$s de %1$d casillas"), which
-- every locale but enUS uses somewhere; Lua's own does not. The same format with its
-- arguments in the order of the text, for Lua's.
function Guards.Positional(fmt, ...)
    local arguments = { ... }
    local out, ordered, count = {}, {}, 0
    local from = 1
    while true do
        local at = fmt:find("%", from, true)
        if not at then
            out[#out + 1] = fmt:sub(from)
            break
        end
        out[#out + 1] = fmt:sub(from, at - 1)
        if fmt:sub(at + 1, at + 1) == "%" then
            out[#out + 1] = "%%"
            from = at + 2
        else
            count = count + 1
            local _, positionEnd, position = fmt:find("^(%d+)%$", at + 1)
            ordered[count] = arguments[position and tonumber(position) or count]
            out[#out + 1] = "%"
            from = (positionEnd or at) + 1
        end
    end
    return table.concat(out), unpack(ordered, 1, count)
end

function Guards.Install()
    if installed then
        return
    end
    installed = true

    pcall = Guards.Protected
    xpcall = function(f, handler, ...)
        local arguments = { n = select("#", ...), ... }
        local results = { Guards.Protected(function() return f(unpack(arguments, 1, arguments.n)) end) }
        if not results[1] then
            return false, handler(results[2])
        end
        return unpack(results, 1, table.maxn(results))
    end
    coroutine.yield = function(...)
        if (depth[coroutine.running()] or 0) > 0 then
            error("LUA 5.1: yield inside pcall, xpcall or a secure hook", 2)
        end
        return Guards.yield(...)
    end
    string.format = function(fmt, ...)
        if type(fmt) == "string" and fmt:find("%%%d+%$") then
            return string.format(Guards.Positional(fmt, ...))
        end
        local index = 0
        for spec in fmt:gmatch("%%[%-+ #0]*%d*%.?%d*([%a%%])") do
            if spec ~= "%" then
                index = index + 1
                local value = (select(index, ...))
                local kind = type(value)
                if kind == "string" and spec ~= "s" and spec ~= "q" and tonumber(value) then
                    kind = "number" -- Lua turns a string that reads as a number into one
                end
                if spec == "s" and kind ~= "string" and kind ~= "number" then
                    error("LUA 5.1: %s given a " .. kind .. " in: " .. fmt, 2)
                elseif spec == "q" and kind ~= "string" and kind ~= "number" then
                    error("LUA 5.1: %q given a " .. kind .. " in: " .. fmt, 2)
                elseif spec ~= "s" and spec ~= "q" and kind ~= "number" then
                    error("LUA 5.1: %" .. spec .. " given a " .. kind .. " in: " .. fmt, 2)
                end
            end
        end
        return Guards.format(fmt, ...)
    end
end
