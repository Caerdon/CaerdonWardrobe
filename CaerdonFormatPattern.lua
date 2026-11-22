-- A client format string as a Lua pattern.
--
-- Some facts are only on a tooltip as a line of text, written by the client from one of its
-- own format strings: the skill and rank an item asks for (ITEM_MIN_SKILL), a bag's size
-- (CONTAINER_SLOTS), the PVP floor (PVP_ITEM_LEVEL_TOOLTIP), the durability, the "Equip:"
-- stats of WoW Forever. Each is read back with a pattern made from that string, so that it is
-- read in every language the client comes in. This is the one place such a pattern is made.
--
-- What a format string can hold, across the eleven locales of both clients:
--   * arguments in order ("Requires %s (%d)") or by position ("%2$s de %1$d casillas"): what
--     Match returns is in the order of the arguments, whatever the order in the text;
--   * punctuation of the language, full-width included ("需要%s（%d）"): literal text is
--     matched as it stands, with only Lua's own pattern characters escaped;
--   * a grammar escape ("%d |4casilla:casillas;", "%d|1으로;로;"), which the client turns into
--     one of its forms when the text is drawn. Whether a tooltip line still holds the escape
--     or already the form is not the same question for every line, so either is matched.
--
--   local matcher = NS.FormatPattern.Compile(ITEM_MIN_SKILL)
--   local skillName, rank = matcher:Match("Requires Cooking (125)")   -- "Cooking", "125"
--
-- Options (all optional):
--   anywhere   the text may hold more than the line (no anchors); otherwise the whole line
--              has to be the format's, give or take spaces at its ends
--   capture    "all" (the default), "numbers" (text arguments are matched and not returned),
--              or false (nothing is returned but the match itself)
--   number     the pattern of a %d argument (default "%d+")
--   text       the pattern of a %s argument (default ".+")
--   every      one pattern for every argument, whatever its kind
--
-- Compile returns nil for anything that is not a text. A matcher is made once and kept by
-- its caller; nothing here is per line.

local ADDON_NAME, NS = ...

local FormatPattern = {}
NS.FormatPattern = FormatPattern

local MAGIC = "[%^%$%(%)%%%.%[%]%*%+%-%?]"

local function Literal(text)
    return (text:gsub(MAGIC, "%%%0"))
end

-- The pattern of one argument by its conversion letter.
local function ArgumentPattern(conversion, options)
    if options.every then
        return options.every, true
    elseif conversion == "s" or conversion == "q" then
        return options.text or ".+", false
    elseif conversion == "c" then
        return ".", false
    elseif conversion == "d" or conversion == "i" or conversion == "u" then
        return options.number or "%d+", true
    end
    -- %f, %g, %e and what else prints a number: digits with a locale's separators.
    return options.number or "[%d%.,]+", true
end

local Matcher = {}
Matcher.__index = Matcher

local function InOrder(order, count, first, ...)
    if first == nil then
        return nil
    end
    local values = { first, ... }
    local ordered = {}
    for index = 1, #order do
        ordered[order[index]] = values[index]
    end
    return unpack(ordered, 1, count)
end

-- The arguments the line was written with, as texts, in the order of the format's arguments;
-- nil for one that is not captured. Without captures, the matched text. nil when the line is
-- not the format's.
function Matcher:Match(text)
    if type(text) ~= "string" then
        return nil
    end
    if self.inTextOrder then
        return strmatch(text, self.pattern)
    end
    return InOrder(self.order, self.arguments, strmatch(text, self.pattern))
end

function FormatPattern.Compile(format, options)
    if type(format) ~= "string" then
        return nil
    end
    options = options or {}
    local capture = options.capture
    if capture == nil then
        capture = "all"
    end

    local parts, order = {}, {}
    local position, length, nextArgument, arguments = 1, #format, 0, 0
    local literalFrom = 1
    local function FlushLiteral(upTo)
        if upTo >= literalFrom then
            parts[#parts + 1] = Literal(format:sub(literalFrom, upTo))
        end
    end

    while position <= length do
        local character = format:sub(position, position)
        if character == "%" then
            if format:sub(position + 1, position + 1) == "%" then
                FlushLiteral(position - 1)
                parts[#parts + 1] = "%%"
                position = position + 2
                literalFrom = position
            else
                -- %[position$][flags][width][.precision]conversion
                local specEnd, explicit, conversion
                local _, afterPosition, number = format:find("^(%d+)%$", position + 1)
                local scanFrom = position + 1
                if afterPosition then
                    explicit = tonumber(number)
                    scanFrom = afterPosition + 1
                end
                _, specEnd, conversion = format:find("^[%-%+ #0]*%d*%.?%d*(%a)", scanFrom)
                if specEnd then
                    FlushLiteral(position - 1)
                    local argument = explicit
                    if not argument then
                        nextArgument = nextArgument + 1
                        argument = nextArgument
                    end
                    if argument > arguments then
                        arguments = argument
                    end
                    local pattern, isNumber = ArgumentPattern(conversion, options)
                    if capture == "all" or (capture == "numbers" and isNumber) then
                        parts[#parts + 1] = "(" .. pattern .. ")"
                        order[#order + 1] = argument
                    else
                        parts[#parts + 1] = pattern
                    end
                    position = specEnd + 1
                    literalFrom = position
                else
                    -- A lone percent sign: text like any other.
                    position = position + 1
                end
            end
        elseif character == "|" then
            -- |4singular:plural; and |1form;form; become one of their forms when drawn.
            local kind = format:sub(position + 1, position + 1)
            local escapeStart, escapeEnd
            if kind == "4" then
                escapeStart, escapeEnd = format:find("^|4[^;|]*;", position)
            elseif kind == "1" then
                escapeStart, escapeEnd = format:find("^|1[^;|]*;[^;|]*;", position)
            end
            if escapeEnd then
                FlushLiteral(position - 1)
                parts[#parts + 1] = ".-"
                position = escapeEnd + 1
                literalFrom = position
            else
                position = position + 1
            end
        else
            position = position + 1
        end
    end
    FlushLiteral(length)

    local pattern = table.concat(parts)
    if #order == 0 then
        -- Nothing to hand back but the match itself.
        pattern = "(" .. pattern .. ")"
    end
    if not options.anywhere then
        pattern = "^%s*" .. pattern .. "%s*$"
    end

    local inTextOrder = true
    for index = 1, #order do
        if order[index] ~= index then
            inTextOrder = false
        end
    end
    if #order ~= arguments and #order > 0 then
        inTextOrder = false
    end

    return setmetatable({
        format = format,
        pattern = pattern,
        order = order,
        arguments = arguments,
        inTextOrder = inTextOrder or #order == 0,
    }, Matcher)
end
