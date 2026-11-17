-- The refresh watcher: for an event of the client that also comes when nothing the icons were
-- made from has changed, it reads what the event stands for and asks for a full refresh only
-- when that reading differs from the last one. (docs/dev-notes.md, Refresh)
--
--   NS.Refresh:Watch({
--       name = "skills",                    -- the refresh's name in the counters
--       events = { "SKILL_LINES_CHANGED" }, -- a name, or { name, unit } for a unit event
--       read = function() return { ... } end,
--       delay = 0.5,
--       leading = true,
--   })
--
-- read: a flat table of key = string, number or boolean. A watch without one takes every event
--   for a change.
-- delay: events closer together than this are one burst, checked once when it is over. Without
--   a delay every event is checked as it comes.
-- leading: a burst's first event is checked at once as well, for a client that already has the
--   new state when it sends the event; the check after the burst is for one that has not.
--
-- A watch's first reading has nothing to be compared with and counts as a change: what was
-- judged before it was judged from a state nobody read.
local ADDON_NAME, NS = ...

local Refresh = {}
NS.Refresh = Refresh

local frame = CreateFrame("Frame")
local watches = {}   -- list, in the order they were added
local byEvent = {}   -- event -> list of watches

-- What differs between two readings, in words: three differences at most, in the order of
-- their keys, then how many more. nil when nothing does.
local MAX_DIFFERENCES = 3

local function Difference(before, after)
    local parts = {}
    for key, value in pairs(after) do
        local old = before[key]
        if old == nil then
            parts[#parts + 1] = ("%s: new, %s"):format(tostring(key), tostring(value))
        elseif old ~= value then
            parts[#parts + 1] = ("%s: %s -> %s"):format(tostring(key), tostring(old), tostring(value))
        end
    end
    for key, old in pairs(before) do
        if after[key] == nil then
            parts[#parts + 1] = ("%s: gone, was %s"):format(tostring(key), tostring(old))
        end
    end
    if #parts == 0 then
        return nil
    end
    table.sort(parts)
    local more = #parts - MAX_DIFFERENCES
    if more > 0 then
        for index = #parts, MAX_DIFFERENCES + 1, -1 do
            parts[index] = nil
        end
        parts[#parts + 1] = ("and %d more"):format(more)
    end
    return table.concat(parts, "; ")
end

-- Reads the watch's state and refreshes when it is not what the last check read.
local function Check(watch)
    watch.checks = watch.checks + 1

    local what
    if watch.read then
        local reading = watch.read()
        local previous = watch.reading
        watch.reading = reading
        if previous == nil then
            what = "first reading"
        else
            what = Difference(previous, reading)
            if not what then
                return
            end
        end
    end

    watch.changes = watch.changes + 1
    if CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
        CaerdonWardrobe:RefreshItems(watch.name, what)
    end
end

local function OnWatchEvent(watch)
    watch.events = watch.events + 1
    if not watch.delay then
        Check(watch)
        return
    end

    if watch.timer then
        watch.timer:Cancel()
    elseif watch.leading then
        Check(watch)
    end
    watch.timer = C_Timer.NewTimer(watch.delay, function()
        watch.timer = nil
        Check(watch)
    end)
end

-- One watch's error must not keep the event from the others.
frame:SetScript("OnEvent", function(_, event)
    local list = byEvent[event]
    if list then
        for index = 1, #list do
            xpcall(OnWatchEvent, geterrorhandler(), list[index])
        end
    end
end)

function Refresh:Watch(spec)
    local watch = {
        name = spec.name,
        read = spec.read,
        delay = spec.delay,
        leading = spec.leading and true or false,
        events = 0,
        checks = 0,
        changes = 0,
        notRegistered = {},
    }
    watches[#watches + 1] = watch

    for _, entry in ipairs(spec.events) do
        local event, unit = entry, nil
        if type(entry) == "table" then
            event, unit = entry[1], entry[2]
        end
        -- pcall: a client that does not know an event raises an error for it.
        local known
        if unit then
            known = pcall(frame.RegisterUnitEvent, frame, event, unit)
        else
            known = pcall(frame.RegisterEvent, frame, event)
        end
        if known then
            local list = byEvent[event]
            if not list then
                list = {}
                byEvent[event] = list
            end
            list[#list + 1] = watch
        else
            watch.notRegistered[#watch.notRegistered + 1] = event
        end
    end
    return watch
end

-- For the counters' report: per watch how many events came, how often its state was read and
-- how often that was a change, and the events this client refused.
function Refresh:GetReport()
    local report = {}
    for index, watch in ipairs(watches) do
        local entry = { name = watch.name, events = watch.events, checks = watch.checks, changes = watch.changes }
        if #watch.notRegistered > 0 then
            entry.notRegistered = table.concat(watch.notRegistered, ", ")
        end
        report[index] = entry
    end
    return report
end

------------------------------------------------------------------------------------------
-- What the core watches
------------------------------------------------------------------------------------------

-- Skills. SKILL_LINES_CHANGED comes for every skill point, a run of them at every login, and
-- for a skill learned or dropped. What the verdicts read of it: which professions the toon has
-- (tools, bags, profession quests), a profession's rank (a recipe's requirement), and through
-- the tooltip's red text any other skill an item asks for. So the reading is every skill line
-- the client lists, with its rank.
local function ReadSkills()
    local reading = {}

    if GetProfessions and GetProfessionInfo then
        for _, professionIndex in pairs({ GetProfessions() }) do
            local name, _, rank, _, _, _, skillLine = GetProfessionInfo(professionIndex)
            if skillLine or name then
                reading["profession " .. tostring(skillLine or name)] = rank or 0
            end
        end
    end

    -- The whole skill list, where the client has one (WoW Forever): weapon skills and armor
    -- proficiencies are lines of it.
    local skillInfo = C_SkillInfo
    if skillInfo and skillInfo.GetNumSkillLines and skillInfo.GetSkillLineInfo then
        for index = 1, skillInfo.GetNumSkillLines() do
            local line = skillInfo.GetSkillLineInfo(index)
            if line and not line.isHeader and line.skillID then
                reading["skill " .. tostring(line.skillID)] = line.rank or 0
            end
        end
    end

    -- The ranks saved for this toon, which a recipe's verdict reads (types/RecipeMixin.lua).
    if CaerdonRecipe and CaerdonRecipe.AddSkillReading then
        CaerdonRecipe:AddSkillReading(reading)
    end

    return reading
end

-- PVP. PLAYER_FLAGS_CHANGED was listened to for War Mode, which decides whether item levels
-- are compared as PVP scales them; it also comes for AFK, DND and every other flag, of any unit
-- in sight. The other half of the answer, a battleground or an arena, changes with the world.
local function ReadPvp()
    return { pvp = CaerdonEquipment and CaerdonEquipment.ReadPvpContext and CaerdonEquipment:ReadPvpContext() or false }
end

Refresh:Watch({
    name = "skills",
    events = { "SKILL_LINES_CHANGED" },
    read = ReadSkills,
    delay = 0.5,
    leading = true,
})

Refresh:Watch({
    name = "pvp",
    events = { { "PLAYER_FLAGS_CHANGED", "player" }, "PLAYER_ENTERING_WORLD" },
    read = ReadPvp,
    delay = 0.5,
    leading = true,
})

-- Housing: the catalog is not always through with a change when its event comes, and one
-- change sends several events. One refresh, when the run of them is over.
if select(4, GetBuildInfo()) >= 110207 and Enum and Enum.ItemClass and Enum.ItemClass.Housing ~= nil then
    Refresh:Watch({
        name = "housing",
        events = {
            "HOUSING_STORAGE_ENTRY_UPDATED",
            "HOUSING_STORAGE_UPDATED",
            "HOUSE_DECOR_ADDED_TO_CHEST",
            "DYE_COLOR_UPDATED",
            "DYE_COLOR_CATEGORY_UPDATED",
        },
        delay = 0.1,
    })
end
