-- The refresh watcher (CaerdonRefresh.lua) against a mocked client: an event that comes when
-- nothing changed refreshes nothing, a change refreshes once and says what changed.
--   luajit tools/harness/standalone/refresh-watcher.lua [repo dir]
-- tools/harness/run.lua runs it with the scenarios. The client is a mock, so this checks the
-- watcher's logic: when each client sends these events, and whether its answers are already
-- the new ones when it does, only a client shows.
local ROOT = arg[1] or "."
local checks, failures = 0, 0
local function Check(condition, label)
    checks = checks + 1
    if not condition then failures = failures + 1 print("FAIL: " .. label) end
end
local function Equal(actual, expected, label)
    Check(actual == expected, ("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)))
end

-- As strict as the client's Lua 5.1: %s only for strings and numbers.
local realFormat = string.format
string.format = function(fmt, ...)
    local index = 0
    for spec in fmt:gmatch("%%[%-+ #0]*%d*%.?%d*([%a%%])") do
        if spec ~= "%" then
            index = index + 1
            local kind = type((select(index, ...)))
            if spec == "s" and kind ~= "string" and kind ~= "number" then
                error("GUARD: %s given a " .. kind .. " in: " .. fmt, 2)
            end
        end
    end
    return realFormat(fmt, ...)
end

------------------------------------------------------------------------------------------
-- The client
------------------------------------------------------------------------------------------

local clock, timers, errors, frame, refreshes, unknownEvents
local state -- what the mocked client answers

local function Advance(seconds)
    local target = clock + seconds
    while true do
        local nextTimer
        for _, timer in ipairs(timers) do
            if not timer.cancelled and not timer.done and timer.at <= target and
                (not nextTimer or timer.at < nextTimer.at) then
                nextTimer = timer
            end
        end
        if not nextTimer then
            break
        end
        clock = nextTimer.at
        nextTimer.done = true
        nextTimer.fn()
    end
    clock = target
end

local function Fire(event, ...)
    local unit = frame.unitEvents[event]
    if frame.events[event] or (unit and unit == (...)) then
        frame.onEvent(frame, event, ...)
    end
end

-- Loads the real file into a client of one flavor. Both clients have a faction list; the mock
-- has one only where a section asks for it (withFactions), so that the sections about another
-- watch count that watch's refreshes alone. A start is a session: what the addon saved is gone
-- with it unless the section keeps it (keepSaved), as a reload or a login does.
local function Start(flavor, withFactions, keepSaved)
    if not keepSaved then CaerdonRefreshData = nil end
    clock, timers, errors, refreshes, unknownEvents = 100, {}, {}, {}, { NO_SUCH_EVENT = true }
    frame = { events = {}, unitEvents = {} }
    function frame:RegisterEvent(event)
        if unknownEvents[event] then error("Attempt to register unknown event \"" .. event .. "\"") end
        self.events[event] = true
    end
    function frame:RegisterUnitEvent(event, unit)
        if unknownEvents[event] then error("Attempt to register unknown event \"" .. event .. "\"") end
        self.unitEvents[event] = unit
    end
    function frame:SetScript(name, fn)
        assert(name == "OnEvent")
        self.onEvent = fn
    end

    CreateFrame = function() return frame end
    geterrorhandler = function() return function(message) errors[#errors + 1] = tostring(message) end end
    C_Timer = {
        NewTimer = function(seconds, fn)
            local timer = { at = clock + seconds, fn = fn }
            function timer:Cancel() self.cancelled = true end
            timers[#timers + 1] = timer
            return timer
        end,
    }

    state = {
        professions = { { name = "Blacksmithing", rank = 50, line = 164 }, { name = "Cooking", rank = 12, line = 185 } },
        lines = {},
        saved = { Blacksmithing = { skillLevel = 50 } },
        warMode = false,
        instanceType = "none",
        realm = "Farrealm",
        toon = "Zzyxa",
    }
    UNKNOWNOBJECT = "Unknown"
    GetRealmName = function() return state.realm end
    UnitName = function(unit)
        assert(unit == "player")
        return state.toon
    end
    GetProfessions = function()
        local indexes = {}
        for index in ipairs(state.professions) do indexes[index] = index end
        return unpack(indexes)
    end
    GetProfessionInfo = function(index)
        local profession = state.professions[index]
        return profession.name, nil, profession.rank, 300, 0, 0, profession.line
    end
    CaerdonRecipe = {
        -- As types/RecipeMixin.lua's, on the mock's saved ranks.
        AddSkillReading = function(_, reading)
            if state.savedRaises then error("the saved ranks could not be read") end
            for name, entry in pairs(state.saved) do
                if entry.skillLevel then reading["saved " .. name] = entry.skillLevel end
                for childName, child in pairs(entry.childSkillLines or {}) do
                    reading["saved " .. name .. " > " .. childName] = child.skillLevel
                end
            end
        end,
    }
    CaerdonEquipment = {
        ReadPvpContext = function()
            return state.instanceType == "pvp" or state.instanceType == "arena" or state.warMode
        end,
    }
    CaerdonWardrobe = {
        RefreshItems = function(_, reason, detail, changed)
            refreshes[#refreshes + 1] = { reason = reason, detail = detail, about = changed, at = clock }
        end,
    }

    if flavor == "forever" then
        GetBuildInfo = function() return "1.60.1", "70938", "Nov 1 2026", 16001 end
        Enum = { ItemClass = {} }
        state.lines = {
            { skillID = 6, name = "Weapon Skills", isHeader = true, rank = 0 },
            { skillID = 43, name = "Swords", isHeader = false, rank = 97 },
            { skillID = 95, name = "Defense", isHeader = false, rank = 100 },
            { skillID = 164, name = "Blacksmithing", isHeader = false, rank = 50 },
            -- A line no fight raises and no profession either.
            { skillID = 633, name = "Lockpicking", isHeader = false, rank = 20 },
        }
        C_SkillInfo = {
            GetNumSkillLines = function() return #state.lines end,
            GetSkillLineInfo = function(index) return state.lines[index] or nil end,
        }
    else
        GetBuildInfo = function() return "12.1.5", "70783", "Nov 1 2026", 120105 end
        Enum = { ItemClass = { Housing = 20 } }
        -- Retail has the namespace and none of the list's functions.
        C_SkillInfo = {}
    end

    -- The reputation window's list, as both clients' C_Reputation gives it: a header that only
    -- groups others, one with a standing of its own, and factions. `points` is the bar.
    C_Reputation, C_GossipInfo, C_MajorFactions = {}, nil, nil
    if withFactions then
        state.factions = {
            { factionID = 1118, name = "Classic", isHeader = true, isHeaderWithRep = false, reaction = 4, points = 0 },
            { factionID = 72, name = "Stormwind", isHeader = false, isHeaderWithRep = false, reaction = 5, points = 3200 },
            { factionID = 576, name = "Timbermaw Hold", isHeader = false, isHeaderWithRep = false, reaction = 3, points = -2900 },
            { factionID = 169, name = "Steamwheedle Cartel", isHeader = true, isHeaderWithRep = true, reaction = 4, points = 500 },
            { factionID = 21, name = "Booty Bay", isHeader = false, isHeaderWithRep = false, reaction = 4, points = 500 },
        }
        state.friendships, state.renown = {}, {}
        C_Reputation = {
            GetNumFactions = function() return #state.factions end,
            GetFactionDataByIndex = function(index)
                local faction = state.factions[index]
                if not faction then return nil end
                -- A new table at every call, as the client's.
                return { factionID = faction.factionID, name = faction.name, isHeader = faction.isHeader,
                    isHeaderWithRep = faction.isHeaderWithRep, reaction = faction.reaction, currentStanding = faction.points }
            end,
            IsMajorFaction = function(factionID) return state.renown[factionID] ~= nil end,
        }
        -- Both clients have these two as well (Forever's reputation window calls them).
        C_GossipInfo = {
            GetFriendshipReputation = function(factionID)
                local rank = state.friendships[factionID]
                return { friendshipFactionID = rank and factionID or 0, reaction = rank or "" }
            end,
        }
        C_MajorFactions = {
            GetMajorFactionData = function(factionID)
                local level = state.renown[factionID]
                -- false: a renown faction the toon has not unlocked.
                return level and { factionID = factionID, renownLevel = level } or nil
            end,
        }
    end

    local namespace = {}
    assert(loadfile(ROOT .. "/CaerdonRefresh.lua"))("CaerdonWardrobe", namespace)
    return namespace.Refresh
end

local function Watched(watcher, name)
    for _, watch in ipairs(watcher:GetReport()) do
        if watch.name == name then return watch end
    end
end

------------------------------------------------------------------------------------------
print("Forever: skills")
------------------------------------------------------------------------------------------
do
    local watcher = Start("forever")
    Check(frame.events.SKILL_LINES_CHANGED == true, "the skill line event is registered")
    Equal(frame.unitEvents.PLAYER_FLAGS_CHANGED, "player", "the flags event is registered for the player alone")
    Check(frame.events.PLAYER_FLAGS_CHANGED == nil, "and not for every unit")
    Check(Watched(watcher, "housing") == nil, "no housing watch on a client without housing")
    Check(frame.events.HOUSING_STORAGE_UPDATED == nil, "and none of its events is registered")

    -- The first reading has nothing to be compared with.
    Fire("SKILL_LINES_CHANGED")
    Equal(#refreshes, 1, "the first event refreshes")
    Equal(refreshes[1].reason, "skills", "under the watch's name")
    Equal(refreshes[1].detail, "first reading", "and says it was the first reading")
    Advance(1)
    Equal(#refreshes, 1, "the check after the burst finds the same and refreshes nothing")

    -- A login's run of events with nothing changed.
    for _ = 1, 18 do
        Fire("SKILL_LINES_CHANGED")
        Advance(0.1)
    end
    Advance(1)
    Equal(#refreshes, 1, "eighteen events with the same skills refresh nothing")
    local skills = Watched(watcher, "skills")
    Equal(skills.events, 19, "the report counts the events")
    Equal(skills.checks, 4, "one read as a burst starts and one when it is over, for both bursts")
    Equal(skills.changes, 1, "and one change")

    -- A rank the client already has when it sends the event.
    state.lines[5].rank = 21
    Fire("SKILL_LINES_CHANGED")
    Equal(#refreshes, 2, "a rank that went up refreshes at once")
    Equal(refreshes[2].detail, "skill 633: 20 -> 21", "and names the line and both ranks")
    Advance(1)
    Equal(#refreshes, 2, "once")

    -- A point of a weapon skill or of Defense, as a fight brings them: no item asked for a
    -- rank of either, so the line being there is all that is read.
    state.lines[2].rank = 98
    state.lines[3].rank = 101
    Fire("SKILL_LINES_CHANGED")
    Advance(1)
    Equal(#refreshes, 2, "a weapon skill's point and one of Defense refresh nothing")
    Equal(#watcher:GetSkillRequirementsNoted(), 0, "no skill's rank was asked for yet")

    -- A client that sends the event before its answers change.
    Fire("SKILL_LINES_CHANGED")
    Equal(#refreshes, 2, "an event with the old answers refreshes nothing")
    state.lines[#state.lines + 1] = { skillID = 44, name = "Axes", isHeader = false, rank = 1 }
    Advance(0.4)
    Equal(#refreshes, 2, "nor does anything before the burst is over")
    Advance(0.2)
    Equal(#refreshes, 3, "the check after the burst finds the new skill, a weapon skill too")
    Equal(refreshes[3].detail, "skill 44: new, present", "and names it")

    -- A header is no skill, and an index the client has nothing for is passed over.
    state.lines[1].rank = 5
    state.lines[#state.lines + 1] = false
    Fire("SKILL_LINES_CHANGED")
    Advance(1)
    Equal(#refreshes, 3, "a header's figure and an empty index change nothing")
    Equal(#errors, 0, "and raise nothing")
    state.lines[#state.lines] = nil

    -- An item's tooltip asked for a rank of a weapon skill: from then on its rank is read.
    watcher:NoteSkillRequirement("Swords")
    watcher:NoteSkillRequirement("Swords")
    watcher:NoteSkillRequirement("Tailoring")
    Equal(table.concat(watcher:GetSkillRequirementsNoted(), ", "), "Swords, Tailoring", "the skills asked for are kept, each once, sorted")
    Fire("SKILL_LINES_CHANGED")
    Equal(#refreshes, 4, "the next event reads the rank where it read the line being there")
    Equal(refreshes[4].detail, "skill 43: present -> 98", "and says so")
    Advance(1)
    state.lines[2].rank = 99
    state.lines[3].rank = 102
    Fire("SKILL_LINES_CHANGED")
    Equal(#refreshes, 5, "a point of the skill that was asked for refreshes")
    Equal(refreshes[5].detail, "skill 43: 98 -> 99", "and Defense, which nothing asked for, is not in it")
    Advance(1)
    Equal(#refreshes, 5, "once")

    -- A profession dropped: gone from the professions and from the list, its saved rank stays.
    table.remove(state.professions, 1)
    table.remove(state.lines, 4)
    Fire("SKILL_LINES_CHANGED")
    Equal(#refreshes, 6, "a dropped profession refreshes")
    Equal(refreshes[6].detail, "profession 164: gone, was 50; skill 164: gone, was 50", "and says what is gone, in the order of the keys")
    Advance(1)

    -- More differences than the detail lists.
    for _, line in ipairs(state.lines) do
        if not line.isHeader then line.rank = line.rank + 1 end
    end
    state.professions[1].rank = 13
    state.saved.Blacksmithing.skillLevel = 51
    Fire("SKILL_LINES_CHANGED")
    Equal(#refreshes, 7, "several ranks at once are one refresh")
    Equal(refreshes[7].detail, "profession 185: 12 -> 13; saved Blacksmithing: 50 -> 51; skill 43: 99 -> 100; and 1 more",
        "with three of them named and the rest counted")
    Advance(1)

    -- One watch's error stays its own: a second watch on the same event still runs.
    watcher:Watch({ name = "probe", events = { "SKILL_LINES_CHANGED", "NO_SUCH_EVENT" } })
    state.savedRaises = true
    Fire("SKILL_LINES_CHANGED")
    Equal(#errors, 1, "a reading that raises goes to the error handler")
    Check(errors[1] and errors[1]:find("the saved ranks could not be read", 1, true) ~= nil, "with its message")
    Equal(#refreshes, 8, "and the other watch of the event still refreshes")
    Equal(refreshes[8].reason, "probe", "under its own name")
    Equal(refreshes[8].detail, nil, "a watch that reads nothing has nothing to say about what changed")
    state.savedRaises = nil
    Advance(1)
    Fire("SKILL_LINES_CHANGED")
    Equal(#refreshes, 9, "a watch without a reading and without a delay refreshes at every event")
    Equal(Watched(watcher, "probe").notRegistered, "NO_SUCH_EVENT", "an event the client refused is in the report")
    Equal(Watched(watcher, "skills").notRegistered, nil, "and nothing is for a watch whose events it took")
    Advance(1)
end

------------------------------------------------------------------------------------------
print("Forever: the player's flags and the world")
------------------------------------------------------------------------------------------
do
    local watcher = Start("forever")
    Fire("PLAYER_ENTERING_WORLD", true, false)
    Equal(#refreshes, 1, "the world's first arrival is the first reading")
    Equal(refreshes[1].reason, "pvp", "under the watch's name")
    Advance(1)

    -- AFK, DND and the like, and the flags of everyone else in sight.
    for _ = 1, 5 do
        Fire("PLAYER_FLAGS_CHANGED", "player")
        Advance(1)
    end
    Fire("PLAYER_FLAGS_CHANGED", "nameplate3")
    Advance(1)
    Equal(#refreshes, 1, "flags that are not War Mode refresh nothing")
    Equal(Watched(watcher, "pvp").events, 6, "and another unit's do not reach the watch at all")

    state.warMode = true
    Fire("PLAYER_FLAGS_CHANGED", "player")
    Equal(#refreshes, 2, "War Mode switched on refreshes")
    Equal(refreshes[2].detail, "pvp: false -> true", "and says so")
    Equal(refreshes[2].about, "worn", "as a change of what is worn")
    Advance(1)

    state.warMode, state.instanceType = false, "pvp"
    Fire("PLAYER_ENTERING_WORLD", false, false)
    Advance(1)
    Equal(#refreshes, 2, "a battleground entered with War Mode off is the same answer")
    state.instanceType = "none"
    Fire("PLAYER_ENTERING_WORLD", false, false)
    Equal(#refreshes, 3, "leaving it is a change")
    Equal(refreshes[3].detail, "pvp: true -> false", "the other way")
    Advance(1)
    Equal(#errors, 0, "nothing raised")
end

------------------------------------------------------------------------------------------
print("Forever: a level gained, and a watch that compares by itself")
------------------------------------------------------------------------------------------
do
    local watcher = Start("forever")
    Check(frame.events.PLAYER_LEVEL_UP == true, "the level event is registered")
    Fire("PLAYER_LEVEL_UP", 32)
    Advance(0.4)
    Equal(#refreshes, 0, "a level gained refreshes nothing before the client has had half a second")
    Advance(0.2)
    Equal(#refreshes, 1, "then once")
    Equal(refreshes[1].reason, "level", "under the watch's name")
    Equal(refreshes[1].detail, nil, "with nothing read")
    Fire("PLAYER_LEVEL_UP", 33)
    Advance(1)
    Equal(#refreshes, 2, "every level is a change")

    -- The owner keeps what the icons were made from and says what differs from it.
    local calls, answer = 0, nil
    watcher:Watch({
        name = "own",
        events = { "QUEST_ACCEPTED", "QUEST_REMOVED" },
        compare = function()
            calls = calls + 1
            return answer
        end,
        delay = 0.5,
    })
    Fire("QUEST_ACCEPTED", 5)
    Equal(calls, 0, "a watch with a delay and no leading check compares nothing as the run starts")
    Advance(1)
    Equal(calls, 1, "it compares once when the run is over")
    Equal(#refreshes, 2, "and refreshes nothing when its owner finds no difference, the first time included")
    answer = "quest 5: upcoming -> in the log"
    Fire("QUEST_ACCEPTED", 5)
    Advance(0.2)
    Fire("QUEST_REMOVED", 6)
    Advance(0.2)
    Fire("QUEST_ACCEPTED", 7)
    Advance(0.4)
    Equal(calls, 1, "events closer together than the delay are one run")
    Advance(0.2)
    Equal(calls, 2, "compared once, half a second after its last event")
    Equal(#refreshes, 3, "a difference refreshes")
    Equal(refreshes[3].reason, "own", "under the watch's name")
    Equal(refreshes[3].detail, "quest 5: upcoming -> in the log", "with the owner's words for what differs")
    local own = Watched(watcher, "own")
    Check(own.events == 4 and own.checks == 2 and own.changes == 1, "the report counts its events, its compares and its changes")

    -- The owner's words are made the way a reading's are.
    Equal(watcher:Difference({ a = 1, b = 2, d = "x" }, { a = 1, b = 3, c = true }), "b: 2 -> 3; c: new, true; d: gone, was x",
        "two flat tables are compared key by key")
    Equal(watcher:Difference({ a = 1 }, { a = 1 }), nil, "and the same tables are no difference")
    Equal(#errors, 0, "nothing raised")
end

------------------------------------------------------------------------------------------
print("Retail: skills without the skill list, housing")
------------------------------------------------------------------------------------------
do
    local watcher = Start("retail")
    state.saved = { Tailoring = { childSkillLines = { ["Khaz Algar Tailoring"] = { skillLevel = 20 } } } }
    Fire("SKILL_LINES_CHANGED")
    Advance(1)
    Equal(#refreshes, 1, "the first reading")
    Fire("SKILL_LINES_CHANGED")
    Advance(1)
    Equal(#refreshes, 1, "the same professions and saved ranks refresh nothing")
    state.saved.Tailoring.childSkillLines["Khaz Algar Tailoring"].skillLevel = 25
    Fire("SKILL_LINES_CHANGED")
    Advance(1)
    Equal(#refreshes, 2, "a saved rank of an expansion's line refreshes")
    Equal(refreshes[2].detail, "saved Tailoring > Khaz Algar Tailoring: 20 -> 25", "and names it")

    -- Housing: one change sends several events, and the catalog may not be through with it.
    local housing = Watched(watcher, "housing")
    Check(housing ~= nil, "a housing watch on a client with housing")
    Fire("HOUSING_STORAGE_UPDATED")
    Fire("HOUSING_STORAGE_ENTRY_UPDATED")
    Advance(0.05)
    Fire("DYE_COLOR_UPDATED")
    Equal(#refreshes, 2, "nothing is refreshed while the run of events lasts")
    Advance(0.09)
    Equal(#refreshes, 2, "nor before a tenth of a second after the last")
    Advance(0.02)
    Equal(#refreshes, 3, "then once")
    Equal(refreshes[3].reason, "housing", "under the watch's name")
    Advance(1)
    Equal(#refreshes, 3, "and not again")
    housing = Watched(watcher, "housing")
    Check(housing.events == 3 and housing.checks == 1 and housing.changes == 1, "three events, one refresh")

    -- Before the core is there an event does no harm.
    CaerdonWardrobe = nil
    Fire("HOUSE_DECOR_ADDED_TO_CHEST")
    Advance(1)
    Equal(#errors, 0, "an event before the core exists raises nothing")
end

------------------------------------------------------------------------------------------
print("The profession window opens")
------------------------------------------------------------------------------------------
for _, flavor in ipairs({ "retail", "forever" }) do
    local watcher = Start(flavor)
    Check(frame.events.TRADE_SKILL_DATA_SOURCE_CHANGED == true, flavor .. ": the profession window's event is registered")
    Fire("SKILL_LINES_CHANGED")
    Advance(1)
    Equal(#refreshes, 1, flavor .. ": the first reading")

    -- Opened on a profession whose ranks are saved as they are.
    Fire("TRADE_SKILL_DATA_SOURCE_CHANGED")
    Advance(1)
    Equal(#refreshes, 1, flavor .. ": the window opening on ranks already saved refreshes nothing")
    Equal(Watched(watcher, "skills").events, 2, flavor .. ": the event is counted with the skill line events")

    -- The recipe code has saved a new rank by the time the watch reads.
    state.saved.Blacksmithing.skillLevel = 55
    Fire("TRADE_SKILL_DATA_SOURCE_CHANGED")
    Equal(#refreshes, 2, flavor .. ": a rank saved before the watch reads refreshes at the event")
    Equal(refreshes[2].reason, "skills", flavor .. ": under the skills watch's name")
    Equal(refreshes[2].detail, "saved Blacksmithing: 50 -> 55", flavor .. ": and names the saved rank")
    Advance(1)
    Equal(#refreshes, 2, flavor .. ": and not again when the burst is over")

    -- The recipe code's own handler runs after the watch's: the check after the burst has it.
    Fire("TRADE_SKILL_DATA_SOURCE_CHANGED")
    Equal(#refreshes, 2, flavor .. ": nothing is saved yet when the event comes")
    state.saved.Blacksmithing.skillLevel = 60
    Advance(1)
    Equal(#refreshes, 3, flavor .. ": a rank saved after the event refreshes when the burst is over")
    Equal(refreshes[3].detail, "saved Blacksmithing: 55 -> 60", flavor .. ": and names it")
    Equal(#errors, 0, flavor .. ": no error")
end

------------------------------------------------------------------------------------------
print("Reputation")
------------------------------------------------------------------------------------------
local function Named(reason)
    local list = {}
    for _, refresh in ipairs(refreshes) do
        if refresh.reason == reason then list[#list + 1] = refresh end
    end
    return list
end
local function Faction(factionID)
    for index, faction in ipairs(state.factions) do
        if faction.factionID == factionID then return faction, index end
    end
end

-- The mock's list as the addon remembers it for the first toon: a session that follows another.
local function AsRemembered()
    for _, faction in ipairs(state.factions) do
        local standing = CaerdonRefreshData.Farrealm.Zzyxa.standings[faction.factionID]
        if type(standing) == "number" then faction.reaction = standing end
    end
end

for _, flavor in ipairs({ "forever", "retail" }) do
    -- The first session of all: nothing is remembered of this toon.
    local watcher = Start(flavor, true)
    Check(frame.events.UPDATE_FACTION == true, flavor .. ": the faction event is registered")
    Check(frame.events.MAJOR_FACTION_RENOWN_LEVEL_CHANGED == true and frame.events.MAJOR_FACTION_UNLOCKED == true,
        flavor .. ": and the two renown events")

    Fire("UPDATE_FACTION")
    Equal(#Named("reputation"), 1, flavor .. ": with nothing remembered the list is a change")
    Equal(Named("reputation")[1].detail,
        "faction 169 (Steamwheedle Cartel): new, 4; faction 21 (Booty Bay): new, 4; faction 576 (Timbermaw Hold): new, 3; and 1 more",
        flavor .. ": every faction of it new")
    Advance(1)
    Fire("PLAYER_ENTERING_WORLD", true, false)
    Advance(1)
    Equal(#Named("reputation"), 1, flavor .. ": the world's arrival finds the same and refreshes nothing")
    local saved = CaerdonRefreshData.Farrealm.Zzyxa.standings
    Check(saved[72] == 5 and saved[576] == 3 and saved[169] == 4 and saved[21] == 4, flavor .. ": the standings are remembered by faction ID, under realm and toon")
    Equal(saved[1118], nil, flavor .. ": a header that only groups others is not")

    -- Points: every kill and every quest turned in.
    for _ = 1, 5 do
        Faction(72).points = Faction(72).points + 25
        Fire("UPDATE_FACTION")
        Advance(1)
    end
    Equal(#Named("reputation"), 1, flavor .. ": points gained within a standing refresh nothing")
    local watch = Watched(watcher, "reputation")
    Check(watch.events == 7 and watch.checks == 14 and watch.changes == 1, flavor .. ": seven events, read as each burst starts and ends, one change")

    -- A standing reached, on a client that has it when the event comes.
    Faction(576).reaction = 4
    Fire("UPDATE_FACTION")
    Equal(#Named("reputation"), 2, flavor .. ": a standing reached refreshes at the event")
    Equal(Named("reputation")[2].detail, "faction 576 (Timbermaw Hold): 3 -> 4", flavor .. ": and names the faction and both standings")
    Equal(Named("reputation")[2].about, nil, flavor .. ": as a change about everything")
    Equal(saved[576], 4, flavor .. ": and is the standing remembered from then on")
    Advance(1)
    Equal(#Named("reputation"), 2, flavor .. ": and not again when the burst is over")

    -- And on one that still answers with the old standing then.
    Fire("UPDATE_FACTION")
    Equal(#Named("reputation"), 2, flavor .. ": the old standing at the event refreshes nothing")
    Faction(72).reaction = 6
    Advance(0.4)
    Equal(#Named("reputation"), 2, flavor .. ": nor before half a second is over")
    Advance(0.2)
    Equal(#Named("reputation"), 3, flavor .. ": the check after the burst has it")
    Equal(Named("reputation")[3].detail, "faction 72 (Stormwind): 5 -> 6", flavor .. ": and names it")

    -- A standing lost is a change like one reached.
    Faction(72).reaction = 5
    Fire("UPDATE_FACTION")
    Equal(Named("reputation")[4] and Named("reputation")[4].detail, "faction 72 (Stormwind): 6 -> 5", flavor .. ": a standing lost refreshes too")
    Advance(1)

    -- Headers: one that only groups is not read, one with a standing of its own is.
    Faction(1118).reaction = 5
    Fire("UPDATE_FACTION")
    Advance(1)
    Equal(#Named("reputation"), 4, flavor .. ": a header that only groups others is not read")
    Faction(169).reaction = 5
    Fire("UPDATE_FACTION")
    Advance(1)
    Equal(Named("reputation")[5] and Named("reputation")[5].detail, "faction 169 (Steamwheedle Cartel): 4 -> 5", flavor .. ": a header with a standing of its own is")

    -- A faction met for the first time: nothing is remembered of it.
    table.insert(state.factions, { factionID = 59, name = "Thorium Brotherhood", isHeader = false, isHeaderWithRep = false, reaction = 4, points = 0 })
    Fire("UPDATE_FACTION")
    Advance(1)
    Equal(Named("reputation")[6] and Named("reputation")[6].detail, "faction 59 (Thorium Brotherhood): new, 4", flavor .. ": a faction met is a change")

    -- The list is the reputation window's: a collapsed header takes its factions out of it.
    -- What was last read of them stays remembered.
    local _, bootyBay = Faction(21)
    local hidden = table.remove(state.factions, bootyBay)
    Fire("UPDATE_FACTION")
    Advance(1)
    Equal(#Named("reputation"), 6, flavor .. ": a header collapsed is no change")
    Equal(saved[21], 4, flavor .. ": what is below it stays remembered")
    table.insert(state.factions, hidden)
    Fire("UPDATE_FACTION")
    Advance(1)
    Equal(#Named("reputation"), 6, flavor .. ": nor is one opened with the standings below it as they were")
    _, bootyBay = Faction(21)
    hidden = table.remove(state.factions, bootyBay)
    Fire("UPDATE_FACTION")
    Advance(1)
    hidden.reaction = 5
    Fire("UPDATE_FACTION")
    Advance(1)
    Equal(#Named("reputation"), 6, flavor .. ": a standing reached below a collapsed header is not seen")
    table.insert(state.factions, hidden)
    Fire("UPDATE_FACTION")
    Equal(Named("reputation")[7] and Named("reputation")[7].detail, "faction 21 (Booty Bay): 4 -> 5", flavor .. ": until the header is opened, and then with both standings")
    Advance(1)

    -- Another world entered (an instance, a boat) reads again and finds the same.
    Fire("PLAYER_ENTERING_WORLD", false, false)
    Advance(1)
    Equal(#Named("reputation"), 7, flavor .. ": the world's arrival later on refreshes nothing by itself")
    Equal(#errors, 0, flavor .. ": no error")

    -- A reload: the list is whole when the faction events of the loading screen come.
    watcher = Start(flavor, true, true)
    AsRemembered()
    for _ = 1, 5 do Fire("UPDATE_FACTION") end
    Advance(2)
    Fire("PLAYER_ENTERING_WORLD", false, true)
    Advance(1)
    Equal(#Named("reputation"), 0, flavor .. ": a session that finds the standings as the last one left them refreshes nothing")
    watch = Watched(watcher, "reputation")
    Check(watch.events == 6 and watch.checks == 4 and watch.changes == 0, flavor .. ": six events, two bursts read, no change and no first reading")

    -- A login: the client fills the list in two pieces, the second after the world is there.
    watcher = Start(flavor, true, true)
    AsRemembered()
    local late = { table.remove(state.factions), table.remove(state.factions) }
    Fire("UPDATE_FACTION")
    Advance(1)
    Fire("PLAYER_ENTERING_WORLD", true, false)
    Advance(2)
    table.insert(state.factions, late[2])
    table.insert(state.factions, late[1])
    Fire("UPDATE_FACTION")
    Advance(1)
    Equal(#Named("reputation"), 0, flavor .. ": the rest of the list coming after the world is no change")
    Equal(Watched(watcher, "reputation").changes, 0, flavor .. ": for the watch either")

    -- A standing that changed where the addon did not see it (another machine, the addon off).
    watcher = Start(flavor, true, true)
    AsRemembered()
    Faction(72).reaction = 6
    Fire("UPDATE_FACTION")
    Equal(Named("reputation")[1] and Named("reputation")[1].detail, "faction 72 (Stormwind): 5 -> 6",
        flavor .. ": a standing that is not the one remembered is a change at the session's first check")
    Advance(1)
    -- A faction met in a later session has still never been read.
    table.insert(state.factions, { factionID = 910, name = "Brood of Nozdormu", isHeader = false, isHeaderWithRep = false, reaction = 1, points = 0 })
    Fire("UPDATE_FACTION")
    Equal(Named("reputation")[2] and Named("reputation")[2].detail, "faction 910 (Brood of Nozdormu): new, 1", flavor .. ": a faction met in a later session is new")
    Advance(1)

    -- Another toon of the account has standings of its own.
    watcher = Start(flavor, true, true)
    state.toon = "Otherone"
    Fire("UPDATE_FACTION")
    Advance(1)
    Equal(#Named("reputation"), 1, flavor .. ": another toon has nothing remembered, and its list is a change")
    Equal(CaerdonRefreshData.Farrealm.Otherone.standings[576], 3, flavor .. ": its standings are remembered under its name")
    Equal(CaerdonRefreshData.Farrealm.Zzyxa.standings[576], 4, flavor .. ": and the first toon's are as they were")
    -- And so has a toon of the same name on another realm.
    state.realm, state.toon = "Nearrealm", "Zzyxa"
    Fire("UPDATE_FACTION")
    Advance(1)
    Equal(#Named("reputation"), 2, flavor .. ": a toon of the same name on another realm is another toon")
    Equal(CaerdonRefreshData.Nearrealm.Zzyxa.standings[576], 3, flavor .. ": remembered under its realm")
    Equal(CaerdonRefreshData.Farrealm.Zzyxa.standings[576], 4, flavor .. ": with the first toon's as they were")

    -- A toon the client has no name for yet: nothing remembered can be asked for.
    watcher = Start(flavor, true, true)
    AsRemembered()
    state.toon = nil
    Fire("UPDATE_FACTION")
    Advance(1)
    Equal(#Named("reputation"), 1, flavor .. ": without a name every faction is new: a refresh too many, not one too few")
    state.toon = "Unknown"
    Fire("UPDATE_FACTION")
    Advance(1)
    Equal(#Named("reputation"), 1, flavor .. ": and once only, while the name is the client's word for none")
    Equal(CaerdonRefreshData.Farrealm.Unknown, nil, flavor .. ": nothing is saved under that word")
    state.toon = "Zzyxa"
    Fire("UPDATE_FACTION")
    Advance(1)
    Equal(#Named("reputation"), 1, flavor .. ": with the name there the remembered standings are the ones compared")
    Equal(#errors, 0, flavor .. ": no error without a name")

    -- Saved data that is not what the addon wrote is replaced, not read.
    watcher = Start(flavor, true, true)
    CaerdonRefreshData.Farrealm.Zzyxa = "broken"
    Fire("UPDATE_FACTION")
    Advance(1)
    Equal(#Named("reputation"), 1, flavor .. ": a toon's entry that is no table is as nothing remembered")
    Equal(CaerdonRefreshData.Farrealm.Zzyxa.standings[576], 3, flavor .. ": and is made anew")
    Equal(CaerdonRefreshData.Farrealm.Otherone.standings[576], 3, flavor .. ": with the other toon's left alone")
    watcher = Start(flavor, true, true)
    CaerdonRefreshData = 7
    Fire("UPDATE_FACTION")
    Advance(1)
    Equal(type(CaerdonRefreshData), "table", flavor .. ": saved data that is no table is made anew")
    Equal(#errors, 0, flavor .. ": no error for either")

    -- The saved table is looked up at every check: one loaded after a check replaces the one
    -- that check made.
    watcher = Start(flavor, true)
    Fire("UPDATE_FACTION")
    Advance(1)
    CaerdonRefreshData = { Farrealm = { Zzyxa = { standings = { [72] = 5, [576] = 3, [169] = 4, [21] = 3 } } } }
    Fire("UPDATE_FACTION")
    Equal(Named("reputation")[2] and Named("reputation")[2].detail, "faction 21 (Booty Bay): 3 -> 4", flavor .. ": the saved table is looked up at every check")
    Advance(1)
    Equal(CaerdonRefreshData.Farrealm.Zzyxa.standings[21], 4, flavor .. ": and written to")
end

-- Friendships and renown, which the standing's number does not tell.
do
    local function AddRetailFactions()
        table.insert(state.factions, { factionID = 1358, name = "Nat Pagle", isHeader = false, isHeaderWithRep = false, reaction = 5, points = 8400 })
        table.insert(state.factions, { factionID = 2507, name = "Dragonscale Expedition", isHeader = false, isHeaderWithRep = false, reaction = 5, points = 0 })
    end
    local watcher = Start("retail", true)
    AddRetailFactions()
    state.friendships[1358] = "Buddy"
    state.renown[2507] = 11
    Fire("PLAYER_ENTERING_WORLD", true, false)
    Advance(1)
    Equal(#Named("reputation"), 1, "retail: with nothing remembered the list is a change, at the world's arrival where no faction event came before")

    state.friendships[1358] = "Friend"
    Fire("UPDATE_FACTION")
    Equal(Named("reputation")[2] and Named("reputation")[2].detail, "faction 1358 (Nat Pagle): Buddy -> Friend", "a friendship's rank is read by its name, with the standing's number as it was")
    Advance(1)

    -- The renown event alone: Blizzard's window listens for it besides the faction event.
    state.renown[2507] = 12
    Fire("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 2507, 12, 11)
    Equal(Named("reputation")[3] and Named("reputation")[3].detail, "faction 2507 (Dragonscale Expedition): renown 11 -> renown 12", "a renown level is read, at its own event")
    Advance(1)

    -- A renown faction the toon has not unlocked has no data; unlocking it is a change.
    table.insert(state.factions, { factionID = 2600, name = "The Severed Threads", isHeader = false, isHeaderWithRep = false, reaction = 4, points = 0 })
    state.renown[2600] = false
    Fire("UPDATE_FACTION")
    Advance(1)
    Equal(Named("reputation")[4] and Named("reputation")[4].detail, "faction 2600 (The Severed Threads): new, renown 0", "a renown faction with no data yet is read as level 0")
    state.renown[2600] = 1
    Fire("MAJOR_FACTION_UNLOCKED", 2600)
    Equal(Named("reputation")[5] and Named("reputation")[5].detail, "faction 2600 (The Severed Threads): renown 0 -> renown 1", "and unlocked at its own event")
    Advance(1)
    Equal(Watched(watcher, "reputation").changes, 5, "five changes in all")
    Equal(#errors, 0, "nothing raised")

    -- A rank's name and a renown level are remembered as they were read.
    local saved = CaerdonRefreshData.Farrealm.Zzyxa.standings
    Check(saved[1358] == "Friend" and saved[2507] == "renown 12" and saved[2600] == "renown 1", "a rank's name and a renown level are remembered as read")
    watcher = Start("retail", true, true)
    AddRetailFactions()
    table.insert(state.factions, { factionID = 2600, name = "The Severed Threads", isHeader = false, isHeaderWithRep = false, reaction = 4, points = 0 })
    state.friendships[1358], state.renown[2507], state.renown[2600] = "Friend", 12, 1
    Fire("UPDATE_FACTION")
    Advance(1)
    Fire("PLAYER_ENTERING_WORLD", true, false)
    Advance(1)
    Equal(#Named("reputation"), 0, "and the next session that finds them so refreshes nothing")
    state.renown[2507] = 13
    Fire("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 2507, 13, 12)
    Equal(Named("reputation")[1] and Named("reputation")[1].detail, "faction 2507 (Dragonscale Expedition): renown 12 -> renown 13", "a level reached in it is compared with the one remembered")
    Advance(1)
end

-- A client with the list and neither of the other two namespaces reads standings alone.
do
    local watcher = Start("forever", true)
    C_GossipInfo, C_MajorFactions = nil, nil
    Fire("PLAYER_ENTERING_WORLD", true, false)
    Advance(1)
    Faction(576).reaction = 4
    Fire("UPDATE_FACTION")
    Equal(Named("reputation")[2] and Named("reputation")[2].detail, "faction 576 (Timbermaw Hold): 3 -> 4", "without the friendship and renown functions the standings are read")
    Advance(1)
    Equal(#errors, 0, "and nothing raised")
    Check(watcher ~= nil, "the watcher is there")
end

-- Without the list's functions there is no watch, and nothing is saved.
do
    local watcher = Start("forever")
    Check(Watched(watcher, "reputation") == nil, "a client with no faction list has no reputation watch")
    Check(frame.events.UPDATE_FACTION == nil, "and the faction event is not asked for")
    Fire("PLAYER_ENTERING_WORLD", true, false)
    Advance(1)
    Equal(CaerdonRefreshData, nil, "and nothing is saved")
end

print(("%d checks, %d failed"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
