-- A refresh that says what changed keeps what does not follow from it.
--
-- Every refresh used to empty everything: the verdicts, what the client had said about the
-- sources of every look, the quest module's answers and its reading of the log. Now a caller
-- that knows what changed says so (CaerdonWardrobe:RefreshItems, `changed`):
--   "worn":       the equipment code keeps the sources, the quest module everything
--   "collection": the equipment code keeps nothing, the quest module everything
-- Here: which questions the client is asked again after each kind of refresh, and that the
-- verdicts still follow what did change. A count that dropped because the code stopped
-- looking would pass a count alone, so each part changes the game and reads the icon.
--
-- The game is hand-made. It proves what the code asks and decides, and nothing about which
-- events a client sends when, or whether a client ever changes a source's answer without a
-- collection event.
--
-- Real code: the whole addon, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 31 }

    local PVP_FLOOR = "Equip: Increases item level to a minimum of %d in Arenas and Battlegrounds."

    local function Armor(name, slot, level, appearance, tooltip)
        local lines = { { text = "Binds when equipped", type = 20, bonding = 7 } }
        for _, line in ipairs(tooltip or {}) do
            lines[#lines + 1] = line
        end
        return { name = name, quality = 2, level = level, minLevel = 20, type = "Armor", subType = "Leather",
            stack = 1, equipLoc = slot, price = 500, classID = 4, subClassID = 2, bindType = 2,
            tooltip = lines, appearance = appearance }
    end
    local function Holdable(name, number)
        return { name = name, quality = 2, level = 31, minLevel = 26, type = "Armor", subType = "Miscellaneous",
            stack = 1, equipLoc = "INVTYPE_HOLDABLE", price = 0, classID = 4, subClassID = 0, bindType = 4,
            tooltip = { { text = "Quest Item", type = 20, bonding = 0 } },
            appearance = { appearanceID = 5340 + number, sourceID = 7340 + number, collected = true } }
    end

    local NEW_LOOK, TWIN, THIRD = 930001, 930002, 930003
    local SPARE, THIN, THICK = 930004, 930010, 930011
    local ARENA_BOOTS, WORN_BOOTS = 930005, 930012
    local EYE, TUSK, LANTERN = 930020, 930021, 930022
    local ITEMS = {
        -- A look nobody has, with three sources. The first is the piece that is judged.
        [NEW_LOOK] = Armor("Field Gloves", "INVTYPE_HAND", 18, { appearanceID = 5301, sourceID = 7301 }),
        [TWIN] = Armor("Twin Gloves", "INVTYPE_HAND", 18, { appearanceID = 5301, sourceID = 7302 }),
        [THIRD] = Armor("Third Gloves", "INVTYPE_HAND", 18, { appearanceID = 5301, sourceID = 7303 }),
        -- A learned piece between the two pairs the toon wears in turn.
        [SPARE] = Armor("Spare Gloves", "INVTYPE_HAND", 25, { appearanceID = 5304, sourceID = 7304, collected = true }),
        [THIN] = Armor("Thin Gloves", "INVTYPE_HAND", 20, { appearanceID = 5310, sourceID = 7310, collected = true }),
        [THICK] = Armor("Thick Gloves", "INVTYPE_HAND", 30, { appearanceID = 5311, sourceID = 7311, collected = true }),
        -- Better than the worn boots only where its PVP floor counts.
        [ARENA_BOOTS] = Armor("Arena Boots", "INVTYPE_FEET", 15, { appearanceID = 5305, sourceID = 7305, collected = true },
            { { text = PVP_FLOOR:format(30) } }),
        [WORN_BOOTS] = Armor("Worn Boots", "INVTYPE_FEET", 20, { appearanceID = 5312, sourceID = 7312, collected = true }),
        -- Taken by a quest of the quest database, and named by an objective of the log.
        [EYE] = Holdable("Cursed Eye", 1),
        [TUSK] = Holdable("Boar Tusk", 2),
    }
    ITEMS[LANTERN] = Holdable("Worn Lantern", 3)
    ITEMS[LANTERN].level, ITEMS[LANTERN].bindType, ITEMS[LANTERN].tooltip = 45, 1, {}

    local HAND, FEET, OFFHAND = 10, 8, 17
    local worn = { [HAND] = THIN, [FEET] = WORN_BOOTS, [OFFHAND] = LANTERN }
    local instanceType = "none"
    local inCombat = false
    local onQuest, completed = { [8010] = true }, {}
    local log = { { questID = 8010, objectives = { { type = "item", text = "Boar Tusk: 0/10" } } } }
    local QUESTS = {
        [8001] = { name = "The Eye", sourceItemId = EYE, requiredLevel = 22, questLevel = 30, startedBy = { { 5 } } },
    }

    local game = H.StockGame(TOON, ITEMS)
    local function Place(location)
        if type(location) == "table" and location.IsEquipmentSlot and location:IsEquipmentSlot() then
            return worn[location:GetEquipmentSlot()]
        end
    end
    local hyperlink = game.names["C_TooltipInfo.GetHyperlink"]
    game:Set("GetInventoryItemID", function(_, slot) return worn[slot] end)
    game:Set("GetInventoryItemLink", function(_, slot) return worn[slot] and game.Link(worn[slot]) or nil end)
    game:Set("C_Item.DoesItemExist", function(location) return Place(location) ~= nil end)
    game:Set("C_Item.GetItemLink", function(location) return Place(location) and game.Link(Place(location)) or nil end)
    game:Set("C_Item.GetItemID", function(location) return Place(location) end)
    game:Set("C_Item.GetCurrentItemLevel", function(location) return Place(location) and ITEMS[Place(location)].level or nil end)
    game:Set("C_Item.GetItemCount", function() return 0 end)
    game:Set("C_TooltipInfo.GetInventoryItem", function(_, slot) return worn[slot] and hyperlink(game.Link(worn[slot])) or nil end)
    game:Set("GetInstanceInfo", function() return "Elsewhere", instanceType end)
    game:Set("C_PvP.IsWarModeDesired", function() return false end)
    game:Set("InCombatLockdown", function() return inCombat end)
    -- The recipe code looks a learned recipe up by its ID.
    game:Set("C_TradeSkillUI.GetRecipeInfo", function() return nil end)
    game:Set("LibQuestieDB.RequireContract", function() return true end)
    game:Set("LibQuestieDB.Quest.GetAllIds", function() return { 8001 } end)
    game:Set("LibQuestieDB.Quest.Get", function(questID, field) return QUESTS[questID] and QUESTS[questID][field] end)
    game:Set("LibQuestieDB.Enum", { classKeys = { HUNTER = 4 }, raceMaskById = { [3] = 4 } })
    game:Set("C_QuestLog.IsOnQuest", function(questID) return onQuest[questID] == true end)
    game:Set("C_QuestLog.IsQuestFlaggedCompleted", function(questID) return completed[questID] == true end)
    game:Set("C_QuestLog.GetTitleForQuestID", function() return nil end)
    game:Set("C_QuestLog.GetNumQuestLogEntries", function() return #log end)
    game:Set("C_QuestLog.GetInfo", function(index)
        return log[index] and { questID = log[index].questID, isHeader = false } or nil
    end)
    game:Set("C_QuestLog.GetQuestObjectives", function(questID)
        for _, entry in ipairs(log) do
            if entry.questID == questID then
                return entry.objectives
            end
        end
    end)

    -- Every call of a game function, under its name and its first argument.
    local counts = {}
    local function Counted(name)
        local original = game.names[name]
        game:Set(name, function(first, ...)
            local key = first == nil and name or (name .. " " .. tostring(first))
            counts[key] = (counts[key] or 0) + 1
            return original(first, ...)
        end)
    end
    Counted("C_TransmogCollection.GetSourceInfo")
    Counted("C_TransmogCollection.GetAllAppearanceSources")
    Counted("C_QuestLog.GetNumQuestLogEntries")
    Counted("C_QuestLog.IsOnQuest")
    local function Asked(name, key)
        return counts[key == nil and name or (name .. " " .. tostring(key))] or 0
    end
    -- The sources of the new look that are not the judged piece's own (that one is asked
    -- about directly on every verdict), and the list of them.
    local function SourcesAsked()
        return Asked("C_TransmogCollection.GetSourceInfo", 7302) + Asked("C_TransmogCollection.GetSourceInfo", 7303)
            + Asked("C_TransmogCollection.GetAllAppearanceSources", 5301)
    end
    local function LogRead()
        return Asked("C_QuestLog.GetNumQuestLogEntries")
    end
    local function QuestJudged()
        return Asked("C_QuestLog.IsOnQuest", 8001)
    end

    local client = H.Client.New({ flavor = "forever", provider = game })
    game.client = client
    H.LoadBlizzardBase(client)
    local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
    client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
    rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
    client:Fire("ADDON_LOADED", "CaerdonWardrobe")
    client:Fire("VARIABLES_LOADED")
    client:Fire("PLAYER_LOGIN")
    client:Fire("PLAYER_ENTERING_WORLD", true, false)
    client:Tick(40)
    local env = client.env
    local core = env.CaerdonWardrobe

    local function NoErrors(label)
        Equal(#client.errors, 0, label .. ": no error reached the error handler")
        for _, message in ipairs(client.errors) do
            Check(false, label .. ": " .. message)
        end
    end
    NoErrors("start")
    Equal(env.PVP_ITEM_LEVEL_TOOLTIP, PVP_FLOOR, "start: the PVP floor line is the one this client's listing has")

    local function Report()
        return env.CaerdonCounters:GetReport().refreshes
    end
    -- trigger, what it said it was about, detail
    local function Last()
        local recent = Report().recent
        local entry = recent[#recent] or {}
        return entry.trigger, entry.about, entry.detail
    end
    local function About(name)
        return Report().about[name] or 0
    end

    -- The quest database's index is built over the frames after the first question.
    env.CaerdonQuestItems:GetItemQuestInfo(EYE, "Cursed Eye")
    client:Tick(20)
    client:Fire("QUEST_LOG_UPDATE")
    client:Tick(20)

    local items = {}
    for _, itemID in ipairs({ NEW_LOOK, SPARE, ARENA_BOOTS, EYE, TUSK }) do
        local item = env.CaerdonItem:CreateFromItemID(itemID)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        client:TickUntil(function() return loaded end, 10)
        items[itemID] = item
    end

    -- Every item asked for its status, as a redraw does.
    local function Draw()
        local statuses = {}
        for itemID, item in pairs(items) do
            local ready, status
            client:TickUntil(function()
                ready, status = item:GetCaerdonStatus()
                return ready
            end, 10)
            Check(ready, "draw: the status of " .. ITEMS[itemID].name .. " is ready")
            statuses[itemID] = status
        end
        return statuses
    end

    -- An event, then the watcher's half second and the refresh's own tenth; the counts are of
    -- what the redraw after it asks.
    local function After(event, ...)
        counts = {}
        client:Fire(event, ...)
        client:Tick(20)
        return Draw()
    end

    --------------------------------------------------------------------------------------
    -- 1. The first draw, and a refresh about everything
    --------------------------------------------------------------------------------------

    counts = {}
    core:RefreshItems("scenario")
    client:Tick(5)
    local shown = Draw()
    Equal(shown[NEW_LOOK], "own", "first: the gloves with the look nobody has are a look to learn")
    Equal(shown[SPARE], "upgrade", "first: the spare gloves are better than the thin ones worn")
    Check(shown[ARENA_BOOTS] ~= "upgrade", "first: the arena boots are no upgrade outside PVP (" .. tostring(shown[ARENA_BOOTS]) .. ")")
    Equal(shown[EYE], "quest", "first: the eye is taken by a quest still to come")
    Equal(shown[TUSK], "quest", "first: the tusk is named by an objective of the log")
    local spareWithout, bootsWithout = nil, shown[ARENA_BOOTS]
    Check(SourcesAsked() >= 3, "first: the look's other sources and their list are asked for (" .. SourcesAsked() .. ")")
    Check(LogRead() >= 1, "first: the quest log is read")
    Check(QuestJudged() >= 1, "first: the eye's quest is judged")
    Equal(select(2, Last()), nil, "first: a refresh that names nothing is about everything")

    counts = {}
    core:RefreshItems("scenario")
    client:Tick(5)
    Draw()
    Check(SourcesAsked() >= 3, "everything: a refresh about everything asks for the sources again")
    Check(LogRead() >= 1 and QuestJudged() >= 1, "everything: and reads the log and judges the quest again")

    -- The watcher's first reading of the PVP context came at the start, and was about everything.
    do
        local first
        for _, entry in ipairs(Report().recent) do
            if entry.trigger == "pvp" then
                first = first or entry
            end
        end
        Check(first ~= nil and first.detail == "first reading", "first reading: the PVP watch read its state at the start")
        Equal(first and first.about, nil, "first reading: and that refresh was about everything")
    end

    --------------------------------------------------------------------------------------
    -- 2. What is worn: the worn gear is read again, the sources and the quests are not
    --------------------------------------------------------------------------------------

    worn[HAND] = THICK
    shown = After("PLAYER_EQUIPMENT_CHANGED", HAND, false)
    local trigger, about = Last()
    Equal(trigger, "PLAYER_EQUIPMENT_CHANGED", "worn: the refresh is the event's")
    Equal(about, "worn", "worn: and says it is about what is worn")
    Check(shown[SPARE] ~= "upgrade", "worn: the spare gloves are no upgrade against the thick ones (" .. tostring(shown[SPARE]) .. ")")
    spareWithout = shown[SPARE]
    Equal(shown[NEW_LOOK], "own", "worn: the look to learn is one still")
    Equal(SourcesAsked(), 0, "worn: nothing is asked about the look's other sources again")
    Check(Asked("C_TransmogCollection.GetSourceInfo", 7301) >= 1, "worn: the piece's own source is asked about, so its verdict was made again")
    Equal(LogRead(), 0, "worn: the quest log is not read again")
    Equal(QuestJudged(), 0, "worn: the eye's quest is not judged again")
    Equal(shown[EYE], "quest", "worn: the eye keeps its quest icon")
    Equal(shown[TUSK], "quest", "worn: so does the tusk")

    worn[HAND] = THIN
    shown = After("EQUIPMENT_SWAP_FINISHED", true, 11)
    Equal(select(2, Last()), "worn", "swap: an equipment set put on is about what is worn")
    Equal(shown[SPARE], "upgrade", "swap: the spare gloves are an upgrade again")
    Equal(SourcesAsked(), 0, "swap: with nothing asked about the sources")

    shown = After("EQUIPMENT_SETS_CHANGED")
    Equal(select(2, Last()), "worn", "sets: a changed equipment set is about what is worn")
    Equal(SourcesAsked() + LogRead() + QuestJudged(), 0, "sets: with nothing asked about sources or quests")
    Equal(shown[SPARE], "upgrade", "sets: and the verdicts as they were")

    -- The hook on EquipPendingItem: a piece that binds as it is put on.
    counts = {}
    core:OnEquipPendingItem()
    client:Tick(30)
    Draw()
    trigger, about = Last()
    Equal(trigger, "equip pending", "pending: the refresh a second after a binding piece is put on")
    Equal(about, "worn", "pending: is about what is worn")
    Equal(SourcesAsked(), 0, "pending: with nothing asked about the sources")

    --------------------------------------------------------------------------------------
    -- 3. The PVP context: a watch that says what its change is about
    --------------------------------------------------------------------------------------

    instanceType = "pvp"
    shown = After("PLAYER_ENTERING_WORLD", false, false)
    trigger, about = Last()
    Equal(trigger, "pvp", "pvp: entering a battleground is the PVP watch's refresh")
    Equal(about, "worn", "pvp: about what is worn")
    Equal(shown[ARENA_BOOTS], "upgrade", "pvp: the arena boots' floor counts there, and they are an upgrade")
    -- The quest module reads the log again whenever the world arrives, which is its own doing.
    Equal(SourcesAsked() + QuestJudged(), 0, "pvp: with nothing asked about the sources and no quest judged again")
    Equal(shown[TUSK], "quest", "pvp: the tusk keeps its quest icon")

    instanceType = "none"
    shown = After("PLAYER_ENTERING_WORLD", false, false)
    Equal(shown[ARENA_BOOTS], bootsWithout, "pvp: and outside again they are what they were")

    --------------------------------------------------------------------------------------
    -- 4. Something learned: the sources are asked for again, the quests are not
    --------------------------------------------------------------------------------------

    local aboutCollection = About("collection")
    ITEMS[TWIN].appearance.collected = true
    shown = After("TRANSMOG_COLLECTION_SOURCE_ADDED", 7302)
    trigger, about = Last()
    Equal(trigger, "TRANSMOG_COLLECTION_SOURCE_ADDED", "learned: the refresh is the event's")
    Equal(about, "collection", "learned: and says it is about the collection")
    Check(shown[NEW_LOOK] ~= "own", "learned: the look is known from the twin now, and the gloves are no new look ("
        .. tostring(shown[NEW_LOOK]) .. ")")
    Check(Asked("C_TransmogCollection.GetSourceInfo", 7302) >= 1 and Asked("C_TransmogCollection.GetSourceInfo", 7303) >= 1
        and Asked("C_TransmogCollection.GetAllAppearanceSources", 5301) >= 1, "learned: every source of the look is asked about again")
    Equal(LogRead(), 0, "learned: the quest log is not read again")
    Equal(QuestJudged(), 0, "learned: the eye's quest is not judged again")
    Equal(shown[EYE], "quest", "learned: the eye keeps its quest icon")
    Equal(shown[TUSK], "quest", "learned: so does the tusk")
    local knownLook = shown[NEW_LOOK]

    -- A worn change right after it keeps the new answers, not the ones from before.
    shown = After("PLAYER_EQUIPMENT_CHANGED", HAND, false)
    Equal(shown[NEW_LOOK], knownLook, "learned: a refresh about what is worn keeps the answer the collection change brought")
    Equal(SourcesAsked(), 0, "learned: without asking")

    for _, event in ipairs({ "TRANSMOG_COLLECTION_UPDATED", "TRANSMOG_COLLECTION_SOURCE_REMOVED",
        "TRANSMOG_COSMETIC_COLLECTION_SOURCE_ADDED", "NEW_MOUNT_ADDED", "NEW_TOY_ADDED", "NEW_PET_ADDED", "NEW_RECIPE_LEARNED" }) do
        After(event, 1)
        trigger, about = Last()
        Equal(trigger, event, event .. ": the refresh is the event's")
        Equal(about, "collection", event .. ": about the collection")
        Check(SourcesAsked() >= 3, event .. ": the sources are asked for again")
        Equal(LogRead() + QuestJudged(), 0, event .. ": the quests are not")
    end
    Equal(About("collection") - aboutCollection, 8, "learned: the counters have the eight refreshes about the collection")

    -- The collection changed and the refresh that follows is, by another caller, about what is
    -- worn: the sources are not kept past the change.
    env.CaerdonEquipment:NoteCollectionChanged()
    counts = {}
    core:RefreshItems("scenario", nil, "worn")
    client:Tick(5)
    Draw()
    Check(SourcesAsked() >= 3, "flag: a refresh about what is worn that comes after a change of the collection keeps no source")
    counts = {}
    core:RefreshItems("scenario", nil, "worn")
    client:Tick(5)
    Draw()
    Equal(SourcesAsked(), 0, "flag: the one after it keeps them again")

    --------------------------------------------------------------------------------------
    -- 5. A name the core does not know is a refresh about everything
    --------------------------------------------------------------------------------------

    counts = {}
    core:RefreshItems("scenario", nil, "bags")
    client:Tick(5)
    Draw()
    Equal(select(2, Last()), nil, "unknown: a refresh about something the core has no name for is about everything")
    Check(SourcesAsked() >= 3 and LogRead() >= 1 and QuestJudged() >= 1, "unknown: and everything is asked for again")

    --------------------------------------------------------------------------------------
    -- 6. The answers kept through such refreshes are the ones a quest event is compared with
    --------------------------------------------------------------------------------------

    After("PLAYER_EQUIPMENT_CHANGED", HAND, false)
    After("TRANSMOG_COLLECTION_UPDATED")
    Check(env.CaerdonQuestItems:GetDebugState().answeredCount >= 1, "quests: the answers are still held after the two refreshes")
    local total = Report().total
    completed[8001] = true
    shown = After("QUEST_TURNED_IN", 8001, 0, 0)
    trigger, about = Last()
    Equal(Report().total, total + 1, "quests: the eye's quest done elsewhere is a change, found against the kept answers")
    Equal(trigger, "quests", "quests: the refresh is the quest watch's")
    Equal(about, nil, "quests: and about everything")
    Check(shown[EYE] ~= "quest", "quests: the eye has lost its quest icon (" .. tostring(shown[EYE]) .. ")")
    Equal(shown[TUSK], "quest", "quests: the tusk has not")
    Check(LogRead() >= 1, "quests: the log was read again")

    --------------------------------------------------------------------------------------
    -- 7. A refresh put off by a fight is about what the ones put off were about
    --------------------------------------------------------------------------------------

    local function Fight(events)
        local generation = core.refreshGeneration
        inCombat = true
        for _, event in ipairs(events) do
            client:Fire(event, 1)
        end
        client:Tick(5)
        inCombat = false
        counts = {}
        client:Fire("PLAYER_REGEN_ENABLED")
        client:Tick(5)
        local statuses = Draw()
        return statuses, core.refreshGeneration - generation
    end

    local _, refreshes = Fight({ "PLAYER_EQUIPMENT_CHANGED" })
    trigger, about = Last()
    Equal(trigger, "after combat", "fight: a refresh put off by a fight comes when it is over")
    Equal(about, "worn", "fight: about what is worn, as the one put off was")
    Equal(refreshes, 2, "fight: the caches were emptied at the event and when the fight ended")
    Equal(SourcesAsked() + LogRead() + QuestJudged(), 0, "fight: with nothing asked about sources or quests")

    Fight({ "PLAYER_EQUIPMENT_CHANGED", "EQUIPMENT_SETS_CHANGED" })
    Equal(select(2, Last()), "worn", "fight: two about what is worn are one about what is worn")

    Fight({ "PLAYER_EQUIPMENT_CHANGED", "NEW_TOY_ADDED" })
    trigger, about = Last()
    Equal(trigger, "after combat", "fight: two about different things are one refresh after the fight")
    Equal(about, nil, "fight: about everything")
    Check(SourcesAsked() >= 3 and LogRead() >= 1, "fight: which asks for everything again")

    Fight({ "NEW_TOY_ADDED", "PLAYER_EQUIPMENT_CHANGED" })
    Equal(select(2, Last()), nil, "fight: in the other order too")

    Fight({ "UPDATE_EXPANSION_LEVEL", "PLAYER_EQUIPMENT_CHANGED" })
    Equal(select(2, Last()), nil, "fight: one about everything and one about what is worn are about everything")

    Fight({ "PLAYER_EQUIPMENT_CHANGED" })
    Equal(select(2, Last()), "worn", "fight: and the fight after that starts from nothing")

    -- With no fight there is no refresh when one ends.
    total = Report().total
    client:Fire("PLAYER_REGEN_ENABLED")
    client:Tick(5)
    Equal(Report().total, total, "fight: the end of a fight that put nothing off refreshes nothing")

    Check(spareWithout ~= nil, "end: the worn part ran")
    NoErrors("end")
end
