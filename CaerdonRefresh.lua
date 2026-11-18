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
-- compare: in place of read, for a watch whose owner keeps what the icons were made from
--   itself: it returns what differs from that, in words (Refresh:Difference), or nil when
--   nothing does. Such a watch has no first reading.
-- changed: what a change of the reading is about, for a refresh that need not ask for
--   everything again (CaerdonWardrobe:RefreshItems). Without it anything may have changed.
-- delay: events closer together than this are one burst, checked once when it is over. Without
--   a delay every event is checked as it comes.
-- leading: a burst's first event is checked at once as well, for a client that already has the
--   new state when it sends the event; the check after the burst is for one that has not.
--
-- A watch's first reading has nothing to be compared with and counts as a change: what was
-- judged before it was judged from a state nobody read. It is a refresh about everything,
-- whatever the watch's `changed`: nothing says what differs from a state nobody read.
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

-- For a watch that compares by itself, and for a module that names its own refresh.
function Refresh:Difference(before, after)
    return Difference(before, after)
end

-- Reads the watch's state and refreshes when it is not what the last check read.
local function Check(watch)
    watch.checks = watch.checks + 1

    local what
    local changed = watch.changed
    if watch.compare then
        what = watch.compare()
        if not what then
            return
        end
    elseif watch.read then
        local reading = watch.read()
        local previous = watch.reading
        watch.reading = reading
        if previous == nil then
            what = "first reading"
            changed = nil
        else
            what = Difference(previous, reading)
            if not what then
                return
            end
        end
    end

    watch.changes = watch.changes + 1
    if CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
        CaerdonWardrobe:RefreshItems(watch.name, what, changed)
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
        compare = spec.compare,
        changed = spec.changed,
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
-- (tools, bags, profession quests), a profession's rank (a recipe's requirement), its cap (a
-- book that raises it is "Already known" once it has), and through the tooltip's red text any
-- other skill an item asks for. So the reading is every skill line the client lists, with its
-- rank, and a profession's cap.
--
-- But for the lines that go up by use in a fight, a point with every few swings: the weapon
-- skills and Defense, by the IDs under which Blizzard's Forever skills frame knows them
-- (Blizzard_UIPanels_Game/Camelot/SkillsFrame.lua: WEAPON_SKILL_LINES, DEFENSE_SKILL_ID). An
-- item asks for such a skill by wanting the toon to have it, which is the line being there.
-- Whether one also asks for a rank of it is a server's rule, so the item code says when a
-- tooltip does (NoteSkillRequirement), and from then on that line is read with its rank too.
local RAISED_BY_USE = {
    [43] = true,   -- Swords
    [44] = true,   -- Axes
    [45] = true,   -- Bows
    [46] = true,   -- Guns
    [54] = true,   -- Maces
    [55] = true,   -- Two-Handed Swords
    [95] = true,   -- Defense
    [136] = true,  -- Staves
    [160] = true,  -- Two-Handed Maces
    [162] = true,  -- Fist Weapons / Unarmed
    [172] = true,  -- Two-Handed Axes
    [173] = true,  -- Daggers
    [176] = true,  -- Thrown
    [226] = true,  -- Crossbows
    [228] = true,  -- Wands
    [229] = true,  -- Polearms
    [3014] = true, -- Feral Combat
}
local PRESENT = "present"

-- Skill name -> true: a tooltip asked for a rank of it ("Requires First Aid (50)"). Kept for
-- the session: it says something about the game's items, not about the toon.
local rankAsked = {}

function Refresh:NoteSkillRequirement(skillName)
    rankAsked[skillName] = true
end

-- For the export: the names, sorted.
function Refresh:GetSkillRequirementsNoted()
    local names = {}
    for name in pairs(rankAsked) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

local function ReadSkills()
    local reading = {}

    -- A profession is read with its cap as well as its rank. The cap is raised by a trainer or
    -- by a book (Expert Cookbook 16072: 150 to 225) with the rank as it was, and the book's
    -- tooltip says "Already known" from then on.
    local professionLines = {}
    if GetProfessions and GetProfessionInfo then
        for _, professionIndex in pairs({ GetProfessions() }) do
            local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(professionIndex)
            if skillLine or name then
                local key = "profession " .. tostring(skillLine or name)
                reading[key] = rank or 0
                if type(maxRank) == "number" then
                    reading[key .. " cap"] = maxRank
                end
            end
            if skillLine then
                professionLines[skillLine] = true
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
                local byRank = not RAISED_BY_USE[line.skillID] or rankAsked[line.name]
                reading["skill " .. tostring(line.skillID)] = byRank and (line.rank or 0) or PRESENT
                -- A profession's cap, from the list too: which of the two answers has it for
                -- a secondary profession is not on record. No other line's: a weapon skill's
                -- and Lockpicking's rise with the level, which is a refresh of its own.
                if professionLines[line.skillID] and type(line.maxRank) == "number" then
                    reading["skill " .. tostring(line.skillID) .. " cap"] = line.maxRank
                end
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

-- The second event is the profession window opening on a profession: the recipe code saves
-- that profession's ranks then (types/RecipeMixin.lua), which are part of the reading, and no
-- skill line event need follow.
Refresh:Watch({
    name = "skills",
    events = { "SKILL_LINES_CHANGED", "TRADE_SKILL_DATA_SOURCE_CHANGED" },
    read = ReadSkills,
    delay = 0.5,
    leading = true,
})

Refresh:Watch({
    name = "pvp",
    events = { { "PLAYER_FLAGS_CHANGED", "player" }, "PLAYER_ENTERING_WORLD" },
    read = ReadPvp,
    -- Only how item levels are compared with the worn gear's follows from it.
    changed = "worn",
    delay = 0.5,
    leading = true,
})

-- Level. Always a change: level requirements, outgrown food and drink, the quests still to
-- come, the auction floor. No reading, and half a second's wait for a client that still
-- answers with the old level while it sends the event.
Refresh:Watch({
    name = "level",
    events = { "PLAYER_LEVEL_UP" },
    delay = 0.5,
})

-- Reputation. UPDATE_FACTION comes for every point gained (a kill, a quest turned in) and for
-- a click in the reputation window. What a verdict reads of it is a requirement in red that a
-- standing meets ("Requires Timbermaw Hold - Friendly"), through the tooltip. So what is read
-- is where the toon stands with every faction of the client's list, not its points: the
-- standing's number, for a friendship its rank's name, for a renown faction its level.
--
-- The list is the reputation window's: a faction under a collapsed header is not in it, and at
-- a login it is empty until after the world is there (WoW Forever).
local function ReadReputation()
    local standings, names = {}, {}
    local friendshipOf = C_GossipInfo and C_GossipInfo.GetFriendshipReputation
    local isRenown = C_Reputation.IsMajorFaction
    local renownOf = C_MajorFactions and C_MajorFactions.GetMajorFactionData

    for index = 1, C_Reputation.GetNumFactions() do
        local faction = C_Reputation.GetFactionDataByIndex(index)
        -- A header that only groups others has no standing of its own.
        if faction and faction.factionID and faction.factionID > 0 and (not faction.isHeader or faction.isHeaderWithRep) then
            local factionID = faction.factionID
            local standing = faction.reaction or 0
            -- Told apart as Blizzard's reputation window does it.
            local friendship = friendshipOf and friendshipOf(factionID)
            if friendship and (friendship.friendshipFactionID or 0) > 0 then
                standing = friendship.reaction or standing
            elseif isRenown and renownOf and isRenown(factionID) then
                local renown = renownOf(factionID)
                standing = "renown " .. tostring(renown and renown.renownLevel or 0)
            end
            standings[factionID] = standing
            names[factionID] = faction.name
        end
    end

    return standings, names
end

-- Where the toon stood with each faction when it was last in the list, by faction ID, kept
-- between sessions (CaerdonRefreshData[realm][toon].standings). A faction that is not in the
-- list keeps what was last read of it, so one that comes into the list (the login's second
-- piece, a header opened) is compared with that, and only one never read before is new.
local unnamedStandings = {}

local function KnownStandings()
    local realm, toon = GetRealmName(), UnitName("player")
    -- A toon the client has no name for yet has nothing saved to be compared with: every
    -- faction is new to it, which is a refresh too many and not one too few.
    if not realm or not toon or toon == UNKNOWNOBJECT then
        return unnamedStandings
    end

    -- Looked up at every check and not kept: the saved table replaces one made before it loaded.
    if type(CaerdonRefreshData) ~= "table" then
        CaerdonRefreshData = {}
    end
    local byToon = CaerdonRefreshData[realm]
    if type(byToon) ~= "table" then
        byToon = {}
        CaerdonRefreshData[realm] = byToon
    end
    local saved = byToon[toon]
    if type(saved) ~= "table" then
        saved = {}
        byToon[toon] = saved
    end
    if type(saved.standings) ~= "table" then
        saved.standings = {}
    end
    return saved.standings
end

-- What differs from the standings remembered, which are then the ones read. No first reading:
-- what was judged before the session's first check was judged from the standings the last
-- session left, unless they differ, and then that is the change.
local function CompareReputation()
    local known = KnownStandings()
    local standings, names = ReadReputation()
    local before, after
    for factionID, standing in pairs(standings) do
        if known[factionID] ~= standing then
            before, after = before or {}, after or {}
            local key = ("faction %d (%s)"):format(factionID, tostring(names[factionID]))
            before[key], after[key] = known[factionID], standing
            known[factionID] = standing
        end
    end
    return after and Difference(before, after) or nil
end

-- The renown events are the ones Blizzard's reputation window listens for besides the first.
-- The world's arrival is there for a client that sends no faction event while it loads: a
-- standing that is not the one remembered is then found as the world comes. Forever sends one
-- before the world is there (notes: Refresh).
if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
    Refresh:Watch({
        name = "reputation",
        events = { "UPDATE_FACTION", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "MAJOR_FACTION_UNLOCKED", "PLAYER_ENTERING_WORLD" },
        compare = CompareReputation,
        delay = 0.5,
        leading = true,
    })
end

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
