-- The bonus IDs that give an item a level, as the client has them: a table made by asking.
--
-- A piece of a season's gear carries its item level in one of its link's bonus IDs, and the
-- client answers the level of any link at once (C_Item.GetDetailedItemLevelInfo), a bonus ID
-- it does not know being ignored. No function of the client's names a bonus ID. So which IDs
-- give which level is found by asking: one piece's link, with each ID in turn in the place of
-- its own, from 1 to well past the last ID that gave a level. The level an ID gives is the
-- same on every item seen, so one piece's answers stand for all; whoever uses an ID checks
-- what it gives the piece at hand (types/EquipmentMixin.lua, PvpLinkOf, which is what the
-- table is for: a piece at the level its PVP floor raises it to).
--
-- The table is made once for a build of the client, in the background (a few hundred
-- questions a frame), and saved (CaerdonLevelBonusData), so a later session asks nothing. It
-- is made only when something needs it. It is made anew, or carried on past its end, where
-- the client's data has moved on, which is found out three ways:
--   the client's build is another than the saved table's;
--   a piece's own level ID is not in the table (LevelBonuses:Need, "carrier");
--   a level is asked for that no ID in the table gives ("level"): the IDs after the table's
--   end are asked, once a session for each such level.
-- While the table is being made nothing is known, and a caller goes without (IsScanning).
-- When it is done the icons are asked again, if anybody went without.
--
-- One level a making cannot show: the level the piece asked with has with none of these IDs
-- (its `without`). An ID that gives exactly that level reads as one that gives none. For a
-- piece that only has a level through such an ID that is a level nobody wants (44), but a
-- piece can have a level of its own beside it (seen: a ring of level 292 by its ID, 298
-- without), and 298 is a level pieces are raised to. So the table keeps which level it is
-- blind to, and when that level is asked for by a piece that is not blind to it, every ID is
-- asked once more with that piece.
--
-- What the making cost is kept with the table (how long, how many frames, the slowest
-- frame's share), for the export.
local ADDON_NAME, NS = ...

local LevelBonuses = {}
NS.LevelBonuses = LevelBonuses

-- How many IDs past the last one that gave a level are asked before the table ends: bonus
-- IDs of every kind share one numbering, and the level IDs seen lie up to 800 apart.
local MARGIN = 3000
-- Questions a frame.
local BATCH = 250

local loaded = false
local levelOf = {}      -- bonus ID -> the level it gives, or false for one asked that gives none
local idsOf = {}        -- level -> { bonus IDs, ascending }
local scannedTo = 0     -- every ID up to this has been asked
local last = 0          -- the highest ID that gave a level
local version = 0       -- grows when the table has changed
local scan = nil        -- { probe, next, found, from, why }
local waiting = false   -- somebody went without while the table was made
local remade, extended = false, {}
local source = "not made"
local blind = nil       -- the level this table cannot show (see above), or nil
local made = nil        -- { seconds, frames, slowest (ms), asked } of the last making

local function Now()
    return GetTimePreciseSec and GetTimePreciseSec() or GetTime()
end

local function Build()
    local _, build = GetBuildInfo()
    return tostring(build)
end

local function Note(id, level)
    levelOf[id] = level
    if level then
        local ids = idsOf[level]
        if not ids then
            ids = {}
            idsOf[level] = ids
        end
        ids[#ids + 1] = id
        if id > last then
            last = id
        end
    end
end

local function Wipe()
    levelOf, idsOf, scannedTo, last, blind = {}, {}, 0, 0, nil
end

-- The saved table, where it is this build's.
local function Load()
    if loaded then
        return
    end
    loaded = true
    local saved = CaerdonLevelBonusData
    if type(saved) == "table" and saved.build == Build() and type(saved.ids) == "table" and
        type(saved.scannedTo) == "number" then
        local ids = {}
        for id, level in pairs(saved.ids) do
            if type(id) == "number" and type(level) == "number" then
                ids[#ids + 1] = id
            end
        end
        table.sort(ids)
        for _, id in ipairs(ids) do
            Note(id, saved.ids[id])
        end
        scannedTo = saved.scannedTo
        blind = type(saved.blind) == "number" and saved.blind or nil
        made = type(saved.made) == "table" and saved.made or nil
        source = "the saved table"
    end
end

local function Save()
    local ids = {}
    for id, level in pairs(levelOf) do
        if level then
            ids[id] = level
        end
    end
    CaerdonLevelBonusData = { build = Build(), scannedTo = scannedTo, ids = ids, blind = blind, made = made }
end

local function Step()
    local running = scan
    if not running then
        return
    end
    local probe = running.probe
    -- The piece asked with must still answer as it did: a client that has let go of the item
    -- answers nothing, and that is not "this ID gives no level".
    if probe.ask(probe.carrier) ~= probe.level then
        scan = nil
        return
    end
    local stop = running.next + BATCH - 1
    local began = Now()
    for id = running.next, stop do
        if levelOf[id] == nil then
            local level = probe.ask(id)
            running.asked = running.asked + 1
            if level and level ~= probe.without then
                Note(id, level)
                running.found = running.found + 1
            else
                levelOf[id] = false
            end
        end
    end
    running.frames = running.frames + 1
    running.slowest = math.max(running.slowest, (Now() - began) * 1000)
    scannedTo = math.max(scannedTo, stop)
    running.next = stop + 1
    if running.next > math.max(last, running.past or 0) + MARGIN then
        scan = nil
        -- The false answers are only there to be skipped while asking: what is kept is what
        -- gives a level, and how far was asked.
        for id, level in pairs(levelOf) do
            if level == false and id <= scannedTo then
                levelOf[id] = nil
            end
        end
        version = version + 1
        source = "asked this session"
        -- A making from the first ID on is blind to its piece's own level; a second one, with
        -- a piece that is not, has filled that in.
        if running.from == 1 then
            blind = not running.second and probe.without or nil
        end
        made = { seconds = Now() - running.began, frames = running.frames, slowest = running.slowest, asked = running.asked }
        Save()
        if waiting then
            waiting = false
            if CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
                CaerdonWardrobe:RefreshItems("level bonus IDs", format("%d found (%s)", running.found, running.why))
            end
        end
        return
    end
    C_Timer.After(0, Step)
end

local function Start(probe, from, why, second)
    -- Asked to MARGIN past the last ID that gives a level, the piece's own and where it began.
    scan = { probe = probe, next = from, from = from, found = 0, why = why, second = second,
        past = math.max(probe.carrier, from - 1, second and scannedTo - MARGIN or 0),
        began = Now(), frames = 0, slowest = 0, asked = 0 }
    C_Timer.After(0, Step)
end

-- The IDs that give the level, the nearest to `near` first (a piece's own level ID: the IDs
-- of its own run are the likeliest to leave the rest of it as it is). nil where none does.
function LevelBonuses:IdsFor(level, near)
    Load()
    local ids = idsOf[level]
    if not ids then
        return nil
    end
    local sorted = {}
    for index, id in ipairs(ids) do
        sorted[index] = id
    end
    if near then
        table.sort(sorted, function(a, b)
            local da, db = math.abs(a - near), math.abs(b - near)
            if da ~= db then
                return da < db
            end
            return a < b
        end)
    end
    return sorted
end

-- The level the ID gives, or nil where it gives none or has not been asked.
function LevelBonuses:LevelOf(id)
    Load()
    return levelOf[id] or nil
end

function LevelBonuses:Version()
    return version
end

function LevelBonuses:IsScanning()
    return scan ~= nil
end

-- A caller has no ID for what it wants. probe: one piece to ask with, { ask = function(id) ->
-- the level the piece's link answers with that ID in the place of its own, without = its level
-- with no such ID, carrier = its own level ID (a number), level = its own level }.
-- why: "carrier", the piece's own level ID is not in the table; "level", no ID in the table
-- gives the level wanted (wanted). Starts what is due and says whether the table is being
-- made; the caller is told when it is done by the icons being asked again.
function LevelBonuses:Need(probe, why, wanted)
    Load()
    if scan then
        waiting = true
        return true
    end
    if not (probe and type(probe.carrier) == "number" and probe.ask(probe.carrier) == probe.level) then
        return false
    end
    if scannedTo == 0 then
        Wipe()
        Start(probe, 1, "no table for this build")
    elseif why == "carrier" and not remade then
        -- The client's data is another than the table's: all of it is asked again.
        remade = true
        Wipe()
        Start(probe, 1, format("a level ID the table does not have, %d", probe.carrier))
    elseif why == "level" and wanted and wanted == blind and probe.without ~= blind and not idsOf[wanted] then
        -- The one level the table could not show, asked for by a piece that can show it.
        Start(probe, 1, format("level %d is the one the first piece could not show", wanted), true)
    elseif why == "level" and wanted and not extended[wanted] and not idsOf[wanted] then
        extended[wanted] = true
        Start(probe, scannedTo + 1, format("no ID for level %d", wanted))
    else
        return false
    end
    waiting = true
    return true
end

-- For the Debug Frame export: how the table stands.
function LevelBonuses:Describe()
    Load()
    local count, levels = 0, 0
    for _ in pairs(idsOf) do
        levels = levels + 1
    end
    for _, level in pairs(levelOf) do
        if level then
            count = count + 1
        end
    end
    return format("%d IDs for %d levels, asked up to ID %d, the last that gave a level %d; build %s; %s%s%s%s", count, levels,
        scannedTo, last, Build(), source,
        made and format("; its last making: %d questions in %.1f s over %d frames, the slowest frame's share %.1f ms",
            made.asked or 0, made.seconds or 0, made.frames or 0, made.slowest or 0) or "",
        blind and format("; cannot show level %d (the level of the piece it was asked with)", blind) or "",
        scan and format("; being made now (at ID %d, %s)", scan.next, scan.why) or "")
end

-- For the harness: what is held is dropped, so that the saved table is read again as a new
-- session reads it.
function LevelBonuses:Forget()
    loaded, scan, waiting, remade, extended, version, source = false, nil, false, false, {}, version + 1, "not made"
    made = nil
    Wipe()
end
