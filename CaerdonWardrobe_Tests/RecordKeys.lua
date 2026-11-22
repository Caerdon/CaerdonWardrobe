-- The part of a recording that the recorder (in the client) and the offline harness (under
-- LuaJIT, tools/harness) must agree on to the letter: how a call's arguments become the key
-- its answer is stored under, which functions are asked again for their answer, and which
-- names are never recorded because every client has them and the harness brings its own.
--
-- No client calls in this file: the harness loads it as it is.

local _, T = ...

local Keys = {}
T.RecordKeys = Keys

Keys.FORMAT = 1

local IsSecret = issecretvalue or function() return false end

------------------------------------------------------------------------------------------
-- Keys
------------------------------------------------------------------------------------------

local MAX_DEPTH = 4
local MAX_KEY = 400

local function IsFrame(value)
    return type(rawget(value, 0)) == "userdata"
end

local function SortedKeys(map)
    local keys = {}
    for key, value in pairs(map) do
        local kind = type(key)
        -- A mixin's methods say nothing about the value (an item location is a table of them).
        if (kind == "string" or kind == "number") and type(value) ~= "function" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then
            return a < b
        end
        return type(a) == "number"
    end)
    return keys
end

-- One value as text: the same text for the same value in the client's Lua 5.1 and in LuaJIT.
local function Text(value, depth)
    if IsSecret(value) then
        return "<secret>"
    end
    local kind = type(value)
    if kind == "nil" then
        return "nil"
    elseif kind == "boolean" then
        return value and "true" or "false"
    elseif kind == "number" then
        if value ~= value then
            return "nan"
        end
        return ("%.14g"):format(value)
    elseif kind == "string" then
        return ("%d:%s"):format(#value, value)
    elseif kind ~= "table" then
        return "<" .. kind .. ">"
    elseif IsFrame(value) then
        return "<frame>"
    elseif depth >= MAX_DEPTH then
        return "<table>"
    end
    local parts = {}
    for _, key in ipairs(SortedKeys(value)) do
        parts[#parts + 1] = Text(key, depth + 1) .. "=" .. Text(value[key], depth + 1)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- The key for a call's arguments. Trailing nils are dropped, so f(a) and f(a, nil) are one
-- question.
function Keys.Args(count, ...)
    while count > 0 and select(count, ...) == nil do
        count = count - 1
    end
    local parts = {}
    for index = 1, count do
        parts[index] = Text((select(index, ...)), 0)
    end
    local key = table.concat(parts, "|")
    if #key > MAX_KEY then
        -- A table handed over as an argument can be long. Its start stays readable and the
        -- rest becomes a number.
        local hash = 5381
        for index = 1, #key do
            hash = (hash * 33 + key:byte(index)) % 4294967296
        end
        key = key:sub(1, MAX_KEY - 40) .. ("#%d:%.14g"):format(#key, hash)
    end
    return key
end

-- The text of a stored answer ({ n = count, ... }), to tell whether a later one differs.
function Keys.Answer(packed)
    local parts = {}
    for index = 1, packed.n or #packed do
        parts[index] = Text(packed[index], 0)
    end
    return table.concat(parts, "|")
end

------------------------------------------------------------------------------------------
-- What is recorded
------------------------------------------------------------------------------------------

-- Every client has these and they say nothing about its state: Lua's helpers under their
-- global names, the clock, frames, timers, hooks, the error handler. The recorder leaves them
-- alone and the harness implements each one itself.
local BASICS = {
    "abs", "ceil", "date", "debugprofilestart", "debugprofilestop", "debugstack", "difftime", "floor",
    "foreach", "foreachi", "format", "getn", "gmatch", "gsub", "max", "min", "mod", "random", "sort", "strbyte",
    "strchar", "strconcat", "strfind", "strjoin", "strlen", "strlower", "strmatch", "strrep", "strrev",
    "strsplit", "strsub", "strtrim", "strupper", "time", "tinsert", "tostringall", "tremove", "wipe",
    "CallErrorHandler", "CreateFrame", "CreateFromMixins", "GetServerTime", "GetTime", "GetTimePreciseSec",
    "Mixin", "geterrorhandler", "hooksecurefunc", "issecretvalue", "issecurevariable", "securecallfunction",
    "seterrorhandler", "C_Timer",
    -- Only Blizzard's own Lua asks for these, while it loads (Color.lua), and the client
    -- forbids a hook on the first.
    "GetCurrentEnvironment", "issecure", "C_UIColor", "C_ColorUtil",
}
Keys.BASICS = {}
for _, name in ipairs(BASICS) do
    Keys.BASICS[name] = true
end

function Keys.IsBasic(path)
    return Keys.BASICS[path:match("^[^.]+")] == true
end

-- Names the addon builds at run time, which the static check cannot see in its code and
-- ApiNames.lua therefore lacks. The recorder treats them like the names in that file. The
-- harness lists a name it was asked for and no recording has: that is how one gets here.
Keys.ALSO_NAMES = {
    -- CaerdonAPI's ResolveSpecFunction looks each up in C_SpecializationInfo, then in _G.
    "GetSpecialization", "GetSpecializationInfo", "GetSpecializationInfoByID", "GetSpecializationInfoForSpecID",
    "GetLootSpecialization",
    "C_SpecializationInfo.GetSpecialization", "C_SpecializationInfo.GetSpecializationInfo",
    "C_SpecializationInfo.GetSpecializationInfoByID", "C_SpecializationInfo.GetSpecializationInfoForSpecID",
    "C_SpecializationInfo.GetLootSpecialization",
    -- CaerdonAuctionValue keeps Auctionator's API table in a local and calls these off it.
    "Auctionator.API.v1.GetAuctionAgeByItemLink", "Auctionator.API.v1.RegisterForDBUpdate",
    -- CaerdonQuestItems does the same with QuestieDB and Questie.
    "LibQuestieDB.RequireContract", "LibQuestieDB.Quest", "LibQuestieDB.Quest.Get", "LibQuestieDB.Quest.GetAllIds",
    "LibQuestieDB.Enum", "Questie.API.RegisterOnReady", "QuestieLoader.ImportModule",
    -- CaerdonVendorGoods reads who sells an item off the same library.
    "LibQuestieDB.Item", "LibQuestieDB.Item.Get",
}

-- A hooked function tells the recorder what it was asked, not what it answered, so the
-- recorder asks again. That is only safe for a function that reads, and a function is taken
-- to read when its name says so. A name that reads without saying so is listed in ALSO.
local GETTER_PREFIXES = {
    "Get", "Is", "Has", "Have", "Can", "Does", "Should", "Are", "Was", "Unit", "Player", "Account", "Calculate",
    "InCombat", "QuestCan", "ContainerIDTo", "Pawn",
}
Keys.ALSO = {
    EquipmentManager_GetLocationData = true,
    -- Answers whether QuestieDB keeps the contract the addon was written for.
    ["LibQuestieDB.RequireContract"] = true,
}

-- What the addon asks once a session and never again, with the arguments it asks with. A
-- replay starts a session of its own and asks again, so the recorder puts these questions at
-- the end of every run. When the addon changes what it asks, a replay names the new question.
Keys.ONCE_A_SESSION = {
    -- CaerdonQuestItems: QUESTIEDB_CONTRACT, the version of QuestieDB's contract it was written for.
    { "LibQuestieDB.RequireContract", 2 },
}

-- Seams: functions of the addon itself whose answer for one item stands in for data that
-- cannot be asked for one item at a time. The quest module builds an index over every quest
-- in QuestieDB, over several frames, once a session, and reads Questie's own tables; neither
-- fits into a recording of one call. So the recorder keeps what these answered, and a replay
-- puts that in the function's place: the code that judges runs for real on recorded facts,
-- the code that gathers them does not run. A seam the recording has nothing for is left as
-- it is.
Keys.SEAMS = {
    "CaerdonQuestItems.GetIndexedQuests",
    "CaerdonQuestItems.GetQuestieHiddenReason",
    -- What the saved recordings of every toon's recipes say about one item: saved variables,
    -- which no recording of a client's answers holds.
    "CaerdonIngredients.GetRecordedUses",
    -- What each other toon of the realm said of an item that teaches: saved variables too.
    "CaerdonLearners.GetSavedAnswers",
}

-- Functions that hand their answer to a function they are given, at once. The recorder asks
-- again with a function of its own and keeps what that was called with; a replay calls the
-- addon's function with it.
Keys.CALLBACKS = {
    ["Auctionator.Utilities.DBKeyFromLink"] = true,
}

function Keys.IsGetter(path)
    if Keys.ALSO[path] or Keys.CALLBACKS[path] then
        return true
    end
    local name = path:match("([^.]+)$")
    for _, prefix in ipairs(GETTER_PREFIXES) do
        if name:sub(1, #prefix) == prefix then
            -- "Getter" must not pass for "Get" followed by lower case ("Getaway").
            local after = name:sub(#prefix + 1, #prefix + 1)
            if after == "" or after:match("[%u%d_]") then
                return true
            end
        end
    end
    return false
end

-- Answers that only ask the client to do something. The recorder never asks these again; the
-- harness lets them pass and counts them.
function Keys.IsRequest(path)
    local name = path:match("([^.]+)$")
    return name:find("^Request") ~= nil or name:find("^Set%u") ~= nil or name:find("_LoadUI$") ~= nil
end
