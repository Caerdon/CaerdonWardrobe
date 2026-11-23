-- An item that starts a quest the toon has neither done nor taken.
--
-- The rule (author decision): such an item is one to act on, so it has the star, or the grey
-- gear while the quest or the item asks for a level the toon has not, with the quest icon as
-- the small mark on it. That holds where every quest that is not behind the toon is one the
-- item starts and that is not in the log. Once the quest is in the log, or where another
-- quest takes the item, it has the quest icon as any quest's item has.
--
-- Which quest an item starts is the client's word for a copy in a bag slot
-- (C_Container.GetContainerItemQuestInfo) and the quest data's anywhere. Whether the quest
-- can be started is one rule for every copy: neither in the log nor done, not behind the
-- toon, and kept out by nothing but that it can be done again or that the toon has no item
-- that starts it. The player's range of levels and trivial quests left out hold as they do
-- for a quest still to come.
--
-- The game and the quest database are hand-made. The writ's values are those a Forever client
-- answered for a Craftsman's Writ (a fixture: class 0, subclass 8, quality 3, level 10 asked
-- for, the lines "This Item Begins a Quest" of type 0 and "Requires Level 10" of type 43; the
-- quest data names its quest as started by it and as taking it); the quest items' are a
-- letter's as in scenarios/spent-quest-items.lua. That a writ's quest can be done again is
-- this scenario's, and so is every answer of GetContainerItemQuestInfo but the shape.
--
-- Real code: the addon's item side and features/DebugFrame.lua, Blizzard's base files from
-- the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 33 }

    local QUEST_LINE = { text = "Quest Item", type = 20, bonding = 0 }
    local BEGINS_LINE = { text = "This Item Begins a Quest", type = 0 }
    local READ_LINE = { text = "<This item can be read>", type = 0, r = 0, g = 1, b = 0 }

    local function QuestItem(name, fields)
        local item = { name = name, quality = 1, level = 1, minLevel = 0, type = "Quest", subType = "Quest", stack = 1,
            equipLoc = "INVTYPE_NON_EQUIP_IGNORE", price = 0, classID = 12, subClassID = 0, bindType = 4,
            tooltip = { QUEST_LINE, BEGINS_LINE } }
        for key, value in pairs(fields or {}) do
            item[key] = value
        end
        return item
    end

    local WRIT, LETTER, MAP, CHART, NOTE, SEAL, DEED, BANNER, TWIN, FLYER, ORDERS, TOME, DIARY, SCRAP = 994001, 994002,
        994003, 994004, 994005, 994006, 994007, 994008, 994009, 994010, 994011, 994012, 994013, 994014
    local PAIR, RELIC, CHOICE, ELIXIR = 994015, 994016, 994017, 994018
    local ITEMS = {
        -- A writ: no quest's item by its class. Its quest can be done again and takes it back.
        [WRIT] = { name = "Craftsman's Writ", quality = 3, level = 1, minLevel = 10, type = "Consumable", subType = "Other",
            stack = 1, equipLoc = "INVTYPE_NON_EQUIP_IGNORE", price = 1, classID = 0, subClassID = 8, bindType = 0,
            tooltip = { BEGINS_LINE, { text = "Requires Level 10", type = 43, requirementType = 5 } } },
        -- A letter that starts a quest the toon is of a level for, and that can be read.
        [LETTER] = QuestItem("Torn Letter", { tooltip = { QUEST_LINE, BEGINS_LINE, READ_LINE }, readable = true }),
        -- Starts a quest three levels above the toon: within the range, and not yet to be had.
        [MAP] = QuestItem("Smudged Map"),
        -- Starts a quest twelve levels above the toon: beyond the range.
        [CHART] = QuestItem("Sea Chart"),
        -- Starts a quest that is trivial by now.
        [NOTE] = QuestItem("Faded Note"),
        -- Junk by its class, with nothing in the quest data: only the client names its quest.
        [SEAL] = { name = "Broken Seal", quality = 1, level = 1, minLevel = 0, type = "Miscellaneous", subType = "Junk",
            stack = 1, equipLoc = "INVTYPE_NON_EQUIP_IGNORE", price = 25, classID = 15, subClassID = 0, bindType = 0,
            tooltip = { BEGINS_LINE } },
        -- Starts one quest and is taken by another that is still to come.
        [DEED] = QuestItem("Old Deed"),
        -- Starts a quest of the other faction alone.
        [BANNER] = QuestItem("Warsong Banner"),
        -- Starts a quest for each faction.
        [TWIN] = QuestItem("Twin Seal"),
        -- Starts a quest that is offered during an event alone.
        [FLYER] = QuestItem("Festival Flyer"),
        -- Starts a quest that is in the log.
        [ORDERS] = QuestItem("Sealed Orders"),
        -- Starts a quest the toon is of a level for, and asks for level 40 itself.
        [TOME] = QuestItem("Heavy Tome", { minLevel = 40, bindType = 0,
            tooltip = { QUEST_LINE, BEGINS_LINE, { text = "Requires Level 40", type = 43, requirementType = 5, r = 1, g = 0.125, b = 0.125 } } }),
        -- Starts a quest that is done and cannot be done again.
        [DIARY] = QuestItem("Finished Diary"),
        -- Starts nothing: an objective of a quest still to come.
        [SCRAP] = QuestItem("Plain Scrap", { tooltip = { QUEST_LINE } }),
        -- Starts two quests, one of them in the log.
        [PAIR] = QuestItem("Paired Orders"),
        -- Starts a quest, and was taken by another that is done.
        [RELIC] = QuestItem("Returned Relic"),
        -- Starts two quests: one three levels above the toon, one it is of a level for.
        [CHOICE] = QuestItem("Two-Sided Token"),
        -- A writ as the client answered for it, whose quest the quest data has as another
        -- race's.
        [ELIXIR] = { name = "Craftsman's Writ: Elixir", quality = 3, level = 1, minLevel = 10, type = "Consumable",
            subType = "Other", stack = 1, equipLoc = "INVTYPE_NON_EQUIP_IGNORE", price = 1, classID = 0, subClassID = 8,
            bindType = 0,
            tooltip = { { text = "Journeyman", type = 0 }, BEGINS_LINE,
                { text = "Requires Level 10", type = 43, requirementType = 5 } } },
    }
    local BAG = { WRIT, LETTER, MAP, CHART, NOTE, SEAL, DEED, BANNER, TWIN, FLYER, ORDERS, TOME, DIARY, SCRAP, PAIR, RELIC,
        CHOICE, ELIXIR }
    local SLOT = {}
    for slot, id in ipairs(BAG) do
        SLOT[id] = slot
    end

    local function Started(item, fields)
        fields.startedBy = { nil, nil, { item } }
        fields.requiredLevel = fields.requiredLevel or 28
        fields.questLevel = fields.questLevel or 33
        return fields
    end
    local QUESTS = {
        -- Scales with the toon (level 0), can be done again, and takes the writ back.
        [8301] = Started(WRIT, { name = "A Writ to Fill", requiredLevel = 10, questLevel = 0, specialFlags = 1,
            objectives = { [3] = { { WRIT } } } }),
        [8302] = Started(LETTER, { name = "The Torn Letter" }),
        [8303] = Started(MAP, { name = "Where the Map Leads", requiredLevel = 36, questLevel = 38 }),
        [8304] = Started(CHART, { name = "Across the Sea", requiredLevel = 45, questLevel = 47 }),
        [8305] = Started(NOTE, { name = "An Old Favour", requiredLevel = 5, questLevel = 10 }),
        [8306] = Started(DEED, { name = "The Deed's Owner" }),
        [8307] = { name = "Deeds for the Clerk", requiredLevel = 28, questLevel = 33, startedBy = { { 5 } },
            objectives = { [3] = { { DEED }, { SCRAP } } } },
        [8308] = Started(BANNER, { name = "For the Horde", requiredRaces = 178 }),
        [8309] = Started(TWIN, { name = "The Seal (Alliance)", requiredRaces = 77 }),
        [8310] = Started(TWIN, { name = "The Seal (Horde)", requiredRaces = 178 }),
        [8311] = Started(FLYER, { name = "To the Festival", zoneOrSort = -22 }),
        [8312] = Started(ORDERS, { name = "Orders From Above" }),
        [8313] = Started(TOME, { name = "The Tome's Reader" }),
        [8314] = Started(DIARY, { name = "The Diary's End" }),
        [8315] = Started(PAIR, { name = "Orders, First Half" }),
        [8316] = Started(PAIR, { name = "Orders, Second Half" }),
        [8317] = { name = "Find the Relic", requiredLevel = 28, questLevel = 33, startedBy = { { 5 } },
            objectives = { [3] = { { RELIC } } } },
        [8318] = Started(RELIC, { name = "What the Relic Says" }),
        [8319] = Started(CHOICE, { name = "The Far Side", requiredLevel = 36, questLevel = 38 }),
        [8320] = Started(CHOICE, { name = "The Near Side" }),
        -- QuestieDB's record of quest 94216, but for the item: the Horde's races with the bit
        -- of WoW Forever's own, level 60, asks for level 1, no flag.
        [8321] = Started(ELIXIR, { name = "Craftsman's Writ: Elixir", requiredLevel = 1, questLevel = 60,
            requiredRaces = 8589934770, objectives = { [3] = { { ELIXIR } } } }),
    }
    local ALL_QUESTS = { 8301, 8302, 8303, 8304, 8305, 8306, 8307, 8308, 8309, 8310, 8311, 8312, 8313, 8314, 8315, 8316,
        8317, 8318, 8319, 8320, 8321 }
    -- What the client says each copy in the bags starts. The seal's quest is in no quest data.
    local STARTS = { [WRIT] = 8301, [LETTER] = 8302, [MAP] = 8303, [CHART] = 8304, [NOTE] = 8305, [SEAL] = 8399,
        [DEED] = 8306, [BANNER] = 8308, [TWIN] = 8309, [FLYER] = 8311, [ORDERS] = 8312, [TOME] = 8313, [DIARY] = 8314,
        [PAIR] = 8315, [RELIC] = 8318, [CHOICE] = 8319, [ELIXIR] = 8321 }
    local onQuest = { [8312] = true, [8315] = true }
    local completed = { [8314] = true, [8317] = true }
    local owned = {}
    for _, id in ipairs(BAG) do
        owned[id] = 1
    end

    local game = H.StockGame(TOON, ITEMS)
    local function Place(location)
        if type(location) == "table" and location.IsBagAndSlot and location:IsBagAndSlot() then
            local bag, slot = location:GetBagAndSlot()
            return bag == 0 and BAG[slot] or nil
        end
    end
    local hyperlink = game.names["C_TooltipInfo.GetHyperlink"]
    game:Set("C_Item.DoesItemExist", function(location) return Place(location) ~= nil end)
    game:Set("C_Item.GetItemLink", function(location) return Place(location) and game.Link(Place(location)) end)
    game:Set("C_Item.GetItemID", function(location) return Place(location) end)
    game:Set("C_Item.GetItemQuality", function(location) return Place(location) and ITEMS[Place(location)].quality end)
    game:Set("C_Item.GetItemName", function(location) return Place(location) and ITEMS[Place(location)].name end)
    game:Set("C_Item.IsBound", function() return false end)
    game:Set("C_Item.GetItemGUID", function(location)
        return Place(location) and ("Item-1-0-00000000" .. select(2, location:GetBagAndSlot())) or nil
    end)
    game:Set("C_Item.GetStackCount", function() return 1 end)
    game:Set("C_Item.GetItemCount", function(itemID) return type(itemID) == "number" and owned[itemID] or 0 end)
    game:Set("C_Container.GetContainerNumSlots", function(bag) return bag == 0 and #BAG or 0 end)
    game:Set("C_Container.GetContainerItemID", function(bag, slot) return bag == 0 and BAG[slot] or nil end)
    game:Set("C_Container.GetContainerItemLink", function(bag, slot)
        return bag == 0 and BAG[slot] and game.Link(BAG[slot]) or nil
    end)
    game:Set("C_Container.GetContainerItemInfo", function(bag, slot)
        local id = bag == 0 and BAG[slot]
        return id and { itemID = id, stackCount = 1, hyperlink = game.Link(id), isLocked = false, quality = 1,
            isReadable = ITEMS[id].readable == true, hasLoot = false } or nil
    end)
    game:Set("C_Container.GetContainerItemPurchaseInfo", function() return nil end)
    local slotAsked = 0
    game:Set("C_Container.GetContainerItemQuestInfo", function(bag, slot)
        slotAsked = slotAsked + 1
        local id = bag == 0 and BAG[slot]
        if not id then
            return { isQuestItem = false, isActive = false }
        end
        local questID = STARTS[id]
        return { isQuestItem = ITEMS[id].classID == 12, questID = questID, isActive = questID ~= nil and onQuest[questID] == true }
    end)
    game:Set("C_TooltipInfo.GetBagItem", function(bag, slot) return BAG[slot] and hyperlink(game.Link(BAG[slot])) end)
    game:Set("LibQuestieDB.RequireContract", function() return true end)
    game:Set("LibQuestieDB.Quest.GetAllIds", function() return ALL_QUESTS end)
    game:Set("LibQuestieDB.Quest.Get", function(questID, field) return QUESTS[questID] and QUESTS[questID][field] end)
    game:Set("LibQuestieDB.Enum", { classKeys = { HUNTER = 4 }, raceMaskById = { [3] = 4 } })
    game:Set("C_QuestLog.IsOnQuest", function(questID) return onQuest[questID] == true end)
    game:Set("C_QuestLog.IsQuestFlaggedCompleted", function(questID) return completed[questID] == true end)
    game:Set("C_QuestLog.GetTitleForQuestID", function() return nil end)
    -- What an item of the Quest type asks as it loads (types/QuestMixin.lua).
    game:Set("C_QuestLog.IsWorldQuest", function() return false end)
    game:Set("QuestInfoFrame", {})
    game:Set("GetNumQuestRewards", function() return 0 end)
    game:Set("GetNumQuestChoices", function() return 0 end)
    game:Set("GetInstanceInfo", function() return "Elsewhere", "none" end)
    -- What the whole export asks beyond the item.
    game:Set("C_AddOns.GetAddOnInfo", function(name) return name, name, "", true, nil, "INSECURE" end)
    game:Set("PLAYER_FACTION_GROUP", { [0] = "Horde", [1] = "Alliance" })

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
    client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "features/DebugFrame.lua", namespace)
    local env = client.env
    Equal(#client.errors, 0, "start: no error reached the error handler")

    -- The index is built after the first question, over the next frames.
    env.CaerdonQuestItems:GetItemQuestInfo(LETTER, ITEMS[LETTER].name)
    client:Tick(20)

    local function Loaded(item)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        client:TickUntil(function() return loaded end, 10)
        return item
    end
    -- The status and the small mark beside it, as "status" or "status+mark".
    local function Verdict(item, slot)
        local ready, status, mark, _
        client:TickUntil(function()
            ready, status, _, _, _, mark = item:GetCaerdonStatus(nil, slot and { bag = 0, slot = slot } or nil)
            return ready
        end, 10)
        if not ready then
            return "<not ready>"
        end
        return (status or "") .. (mark and ("+" .. mark) or "")
    end
    -- The copy in its bag slot, and the bare link (a mail, a loot window, an auction).
    local function InBag(id)
        return Verdict(Loaded(env.CaerdonItem:CreateFromBagAndSlot(0, SLOT[id])), SLOT[id])
    end
    local function ByLink(id)
        return Verdict(Loaded(env.CaerdonItem:CreateFromItemID(id)))
    end
    local function Info(id, inBag)
        local item = inBag and env.CaerdonItem:CreateFromBagAndSlot(0, SLOT[id]) or env.CaerdonItem:CreateFromItemID(id)
        return Loaded(item):GetQuestItemInfo()
    end
    local function Refresh()
        env.CaerdonWardrobe:RefreshItems()
    end
    local function Refreshes()
        return env.CaerdonCounters:GetReport().refreshes
    end
    local function LastRefresh()
        local recent = Refreshes().recent
        local entry = recent[#recent]
        return entry and entry.trigger, entry and entry.detail
    end
    -- A quest event, the half second the watch waits, and the refresh's own tenth.
    local function After(event, ...)
        client:Fire(event, ...)
        client:Tick(60)
    end

    -- A letter that starts a quest: the star with the quest's mark, wherever it is seen.
    do
        local info = Info(LETTER, true)
        Check(info and info.starts and info.starts.questID == 8302, "letter: its quest info says which quest it starts")
        Equal(info and info.starts and info.starts.belowLevel, false, "letter: and that the toon is of a level for it")
        Check(info and info.isUpcoming and info.hasQuestValue, "letter: the quest is one still to come as well")
        Equal(InBag(LETTER), "own+quest", "letter: the star with the quest icon as the small mark, though it can be read")
        Equal(InBag(LETTER), "own+quest", "letter: the same from the kept verdict")
        Equal(ByLink(LETTER), "own+quest", "letter: by its bare link too, from the quest data")
        -- A quest's plain item is as it was.
        Equal(Info(SCRAP, true).starts, nil, "scrap: an objective of a quest still to come starts nothing")
        Equal(InBag(SCRAP), "quest", "scrap: and has the quest icon")
    end

    -- A writ: no quest's item by its class, and its quest can be done again, which keeps a
    -- quest from being one still to come.
    do
        local info = Info(WRIT, true)
        local quest = info and info.quests[1] or {}
        Equal(quest.reason, "repeatable", "writ: its quest is none still to come, since it can be done again")
        Check(not info.hasQuestValue and quest.startable == true, "writ: and one the writ can start all the same")
        Equal(quest.role, "objective, starts quest", "writ: the quest it starts takes it back")
        Equal(quest.startsByClient, true, "writ: the client names the quest for the copy in the bags")
        Equal(InBag(WRIT), "own+quest", "writ: the star with the quest's mark")
        Equal(ByLink(WRIT), "own+quest", "writ: by its bare link too")
        Equal(Info(WRIT).quests[1].startsByClient, nil, "writ: where the quest data alone names the quest")
    end

    -- The level the quest asks for, and the level the item asks for.
    do
        local info = Info(MAP, true)
        Check(info and info.starts and info.starts.belowLevel == true and info.starts.requiredLevel == 36,
            "map: its quest asks for level 36, three above the toon")
        Equal(InBag(MAP), "lowSkill+quest", "map: the grey gear with the quest's mark until then")
        Equal(ByLink(MAP), "lowSkill+quest", "map: by its bare link too")
        Equal(Info(TOME, true).starts.belowLevel, false, "tome: the toon is of a level for its quest")
        Equal(InBag(TOME), "lowSkill+quest", "tome: the item asks for level 40 itself, so the grey gear")
        TOON.level = 36
        Refresh()
        env.CaerdonQuestItems:InvalidateCaches()
        Equal(InBag(MAP), "own+quest", "map: the star once the toon is of the level")
        TOON.level = 33
        Refresh()
        env.CaerdonQuestItems:InvalidateCaches()
        Equal(InBag(MAP), "lowSkill+quest", "map: and the gear again below it")
    end

    -- The player's range of levels and trivial quests left out hold, in the bags as anywhere.
    do
        local config = env.CaerdonWardrobeConfig.Icon
        local info = Info(CHART, true)
        Equal(info.quests[1].reason, "needs level 45", "chart: its quest is twelve levels away")
        Equal(info.starts, nil, "chart: beyond the range it is no quest to start")
        Equal(info.keptOutByOptions, true, "chart: and kept out by the player's options")
        Equal(InBag(CHART), "", "chart: no icon in the bags")
        Equal(ByLink(CHART), "", "chart: nor by its link")
        config.UpcomingQuestLevels = "any"
        Refresh()
        Equal(InBag(CHART), "lowSkill+quest", "chart: with any level wanted, the grey gear with the quest's mark")
        config.UpcomingQuestLevels = "5"
        Refresh()

        info = Info(NOTE, true)
        Equal(info.quests[1].reason, "trivial at this level", "note: its quest is trivial by now")
        Equal(info.starts, nil, "note: so it is no quest to start")
        Equal(InBag(NOTE), "", "note: no icon")
        config.IncludeTrivialQuests = true
        Refresh()
        Equal(InBag(NOTE), "own+quest", "note: with trivial quests wanted, the star with the quest's mark")
        config.IncludeTrivialQuests = false
        Refresh()

        -- Not under the option for quests not picked up yet: that is about what a quest takes.
        config.ShowUpcomingQuestItems = false
        Refresh()
        Equal(InBag(LETTER), "own+quest", "options: a starter keeps its star with upcoming quests' items switched off")
        Equal(InBag(WRIT), "own+quest", "options: the writ too")
        Equal(InBag(SCRAP), "quest", "options: a quest's own item keeps the icon its class gives")
        config.ShowUpcomingQuestItems = true
        -- With the quest icon switched off nothing is told of a quest.
        config.ShowQuestItems = false
        Refresh()
        Check(not InBag(LETTER):find("quest", 1, true) and not InBag(LETTER):find("own", 1, true),
            "options: with the quest icon switched off the letter is no starter (" .. InBag(LETTER) .. ")")
        Check(not InBag(WRIT):find("own", 1, true), "options: nor the writ (" .. InBag(WRIT) .. ")")
        config.ShowQuestItems = true
        Refresh()
    end

    -- Only the client names the quest: the copy in the bags is a starter, the bare link is not.
    do
        Equal(Info(SEAL), nil, "seal: no quest is known for the item by its link")
        local plain = ByLink(SEAL)
        Check(not plain:find("quest", 1, true) and not plain:find("own", 1, true),
            "seal: by its link it is what it was (" .. plain .. ")")
        local info = Info(SEAL, true)
        Check(info and info.starts and info.starts.questID == 8399, "seal: the copy in the bags starts the quest the client names")
        Equal(info.quests[1].reason, "no quest data", "seal: a quest the quest data does not have")
        Equal(info.quests[1].startsByClient, true, "seal: by the client's word")
        Equal(InBag(SEAL), "own+quest", "seal: the star with the quest's mark in the bags")
        -- The two do not share a kept verdict, whichever is asked first.
        Equal(ByLink(SEAL), plain, "seal: the bare link is still what it was")
        Equal(InBag(SEAL), "own+quest", "seal: and the copy still the starter")
        local copy = Loaded(env.CaerdonItem:CreateFromBagAndSlot(0, SLOT[SEAL]))
        local bare = Loaded(env.CaerdonItem:CreateFromItemID(SEAL))
        Check(copy:GetStatusCacheKey() ~= bare:GetStatusCacheKey(), "seal: the copy the client names a quest for has an entry of its own")
        Check(copy:GetStatusCacheKey():find("|q8399", 1, true) ~= nil, "seal: named by the quest (" .. copy:GetStatusCacheKey() .. ")")
        local before = slotAsked
        ByLink(SEAL)
        Equal(slotAsked, before, "seal: an item that lies in no bag slot asks the client nothing")
    end

    -- Another quest takes it, the quest is in the log, or no quest is left to start.
    do
        local info = Info(DEED, true)
        Equal(info.starts, nil, "deed: taken by another quest still to come, it is a quest's item first")
        Equal(InBag(DEED), "quest", "deed: the quest icon alone")
        info = Info(ORDERS, true)
        Check(info.isActive and info.starts == nil, "orders: their quest is in the log")
        Equal(InBag(ORDERS), "quest", "orders: the quest icon alone")
        -- Who can take a quest and when it is offered is the quest data's word alone, which
        -- stands for a copy the toon does not hold and not against the client for one it
        -- holds (below, "the client's word stands").
        info = Info(BANNER)
        Check(info.isOver and info.starts == nil, "banner: the other faction's quest is behind the toon by the quest data")
        Equal(ByLink(BANNER), "sellable", "banner: by its link, what is left of it is one to get rid of, as before")
        info = Info(TWIN, true)
        Check(info.starts and info.starts.questID == 8309, "twin: of a quest for each faction, the toon's own is the one to start")
        Equal(InBag(TWIN), "own+quest", "twin: the star with the quest's mark")
        info = Info(FLYER)
        Equal(info.quests[1].reason, "event quest", "flyer: its quest is offered during an event alone")
        Equal(info.starts, nil, "flyer: so by the quest data it is none to start now")
        Equal(ByLink(FLYER), "quest", "flyer: by its link, the quest icon its class gives, as before")
        info = Info(DIARY, true)
        Check(info.isOver and info.starts == nil, "diary: its quest is done")
        Equal(InBag(DIARY), "sellable", "diary: one to get rid of, as before")
        info = Info(PAIR, true)
        Check(info.isActive and info.starts == nil, "pair: of two quests it starts, one is in the log, which comes first")
        Equal(InBag(PAIR), "quest", "pair: the quest icon alone")
        info = Info(RELIC, true)
        Check(info.starts and info.starts.questID == 8318, "relic: a quest that took it and is done is behind the toon, the one it starts is not")
        Equal(InBag(RELIC), "own+quest", "relic: the star with the quest's mark")
        info = Info(CHOICE, true)
        Check(info.starts and info.starts.questID == 8320 and info.starts.belowLevel == false,
            "choice: of two quests it starts, the one the toon is of a level for is the one to start")
        Equal(InBag(CHOICE), "own+quest", "choice: the star, not the gear")
    end

    -- The client's word stands for the copy in a bag slot: the quest it names is one to start
    -- unless it is in the log, done or kept out by the player's options, whatever the quest
    -- data says of who can take it or of when it is offered. As a Forever client showed it: a
    -- writ whose quest QuestieDB has as the other faction's (races 0x2000000B2, level 60,
    -- asks for level 1, not one to do again), in the bank of a toon that had had the quest
    -- in its log.
    do
        local info = Info(ELIXIR, true)
        local quest = info.quests[1]
        Equal(quest.reason, "other race", "elixir writ: the quest data has its quest as another race's")
        Check(quest.over == true and quest.startable == false, "elixir writ: behind the toon, and none to start, by that data")
        Equal(quest.role, "objective, starts quest", "elixir writ: named by the data and by the client")
        Check(info.starts and info.starts.questID == 8321, "elixir writ: the copy in the bags starts it by the client's word")
        Equal(quest.canStart, true, "elixir writ: and the quest says the copy would start it")
        Equal(InBag(ELIXIR), "own+quest", "elixir writ: the star with the quest's mark")
        Equal(Info(ELIXIR).starts, nil, "elixir writ: by its link the quest data is all there is")
        Check(not ByLink(ELIXIR):find("own", 1, true), "elixir writ: and it has no star (" .. ByLink(ELIXIR) .. ")")
        Equal(InBag(ELIXIR), "own+quest", "elixir writ: the copy in the bags still has")
        -- The other faction's banner and an event's flyer, held: the same.
        Check(Info(BANNER, true).starts ~= nil and Info(BANNER, true).isOver == true,
            "banner: held, the client's word stands against the quest data's faction")
        Equal(InBag(BANNER), "own+quest", "banner: the star with the quest's mark in the bags")
        Equal(InBag(FLYER), "own+quest", "flyer: held, an event's quest is one to start by the client's word")
        -- Not against the client itself, nor against the player's options.
        Equal(InBag(DIARY), "sellable", "diary: a quest the client flags as done is none to start")
        Equal(InBag(ORDERS), "quest", "orders: nor one that is in the log")
        Equal(InBag(CHART), "", "chart: nor one beyond the player's range")
        -- The export says whose word it is.
        local payload = env.CaerdonWardrobe:GetFeature("DebugFrame"):BuildClipboardPayload(
            Loaded(env.CaerdonItem:CreateFromBagAndSlot(0, SLOT[ELIXIR])))
        Check(payload:find("skipped, other race (behind the toon) (so says the quest data; the client names the quest for this copy, which can still start it)", 1, true) ~= nil,
            "elixir writ: the export's line says the quest data's word and the client's")
        Check(payload:find("Starts A Quest Not Taken Yet: quest 8321", 1, true) ~= nil, "elixir writ: and names the quest to start")

        -- Taken and done within one run of events: a change, though the quest data has it
        -- behind the toon before and after.
        InBag(ELIXIR)
        local total = Refreshes().total
        completed[8321] = true
        client:Fire("QUEST_ACCEPTED", 8321)
        client:Fire("QUEST_TURNED_IN", 8321)
        client:Tick(60)
        Equal(Refreshes().total, total + 1, "elixir writ: its quest taken and done in one run of events refreshes the icons")
        Equal(select(2, LastRefresh()), "quest 8321: to be started -> behind it", "elixir writ: and says so")
        Check(not InBag(ELIXIR):find("own", 1, true), "elixir writ: a second copy has no star then (" .. InBag(ELIXIR) .. ")")
        completed[8321] = nil
        Refresh()
        Equal(InBag(ELIXIR), "own+quest", "elixir writ: and has it again where the client does not flag the quest")
    end

    -- Taking the quest, and handing it in.
    do
        -- Asked about as a redraw asks, so the quests are held as answered.
        InBag(LETTER)
        InBag(WRIT)
        InBag(SEAL)
        local total = Refreshes().total
        onQuest[8302] = true
        After("QUEST_ACCEPTED", 8302)
        Equal(Refreshes().total, total + 1, "taken: the letter's quest is accepted and the icons are refreshed")
        Equal(select(2, LastRefresh()), "quest 8302: upcoming -> in the log", "taken: for that quest")
        Equal(InBag(LETTER), "quest+readable", "taken: the letter has the quest icon now, with the mark of a copy that can be read")
        Equal(ByLink(LETTER), "quest", "taken: by its link the quest icon")

        -- A quest that can be done again: taken, handed in, and the writ is one to start again.
        InBag(WRIT)
        total = Refreshes().total
        onQuest[8301] = true
        After("QUEST_ACCEPTED", 8301)
        Equal(Refreshes().total, total + 1, "again: the writ's quest is accepted and the icons are refreshed")
        Equal(select(2, LastRefresh()), "quest 8301: to be started -> in the log", "again: from one to be started")
        Equal(InBag(WRIT), "quest", "again: the writ has the quest icon while its quest is in the log")
        onQuest[8301] = nil
        After("QUEST_TURNED_IN", 8301)
        Equal(select(2, LastRefresh()), "quest 8301: in the log -> to be started", "again: handed in, it is one to start again")
        Equal(InBag(WRIT), "own+quest", "again: and a second writ has the star")
        -- Done for today: the client flags it, and nothing is left to start.
        InBag(WRIT)
        completed[8301] = true
        After("QUEST_TURNED_IN", 8301)
        Equal(select(2, LastRefresh()), "quest 8301: to be started -> not wanted", "again: flagged as done, it is none to start")
        Check(not InBag(WRIT):find("own", 1, true), "again: the writ has no star then (" .. InBag(WRIT) .. ")")
        completed[8301] = nil

        -- The same for a writ the toon does not hold (a loot window, the mail), where the
        -- quest data alone names the quest: one to be started, and a change when it is taken.
        Refresh()
        Equal(ByLink(WRIT), "own+quest", "again: by its link the writ is one to start")
        onQuest[8301] = true
        After("QUEST_ACCEPTED", 8301)
        Equal(select(2, LastRefresh()), "quest 8301: to be started -> in the log", "again: taken, a change by the quest data's word alone")
        onQuest[8301] = nil
        After("QUEST_REMOVED", 8301)

        -- A quest only the client names, taken and done within one run of events.
        Refresh()
        Equal(InBag(SEAL), "own+quest", "unknown: the seal is one to start")
        total = Refreshes().total
        completed[8399] = true
        client:Fire("QUEST_ACCEPTED", 8399)
        client:Fire("QUEST_TURNED_IN", 8399)
        client:Tick(60)
        Equal(Refreshes().total, total + 1, "unknown: its quest taken and done in one run of events refreshes the icons")
        Equal(select(2, LastRefresh()), "quest 8399: to be started -> not wanted", "unknown: and says so")
        Check(not InBag(SEAL):find("own", 1, true), "unknown: a second seal has no star (" .. InBag(SEAL) .. ")")
    end

    -- The export's rows.
    do
        local feature = env.CaerdonWardrobe:GetFeature("DebugFrame")
        local function Rows(item)
            return feature:BuildClipboardPayload(item)
        end
        local payload = Rows(Loaded(env.CaerdonItem:CreateFromBagAndSlot(0, SLOT[MAP])))
        Check(payload:find("Starts A Quest Not Taken Yet: quest 8303, which asks for level 36 (the star, with the quest icon as the small mark; the grey gear until the toon is of that level)", 1, true) ~= nil,
            "export: the map's row names the quest and the level")
        Check(payload:find("Small Mark On The Icon: quest", 1, true) ~= nil, "export: and the small mark")
        Check(payload:find("(starts quest, by the client's word for its bag slot)", 1, true) ~= nil,
            "export: the quest's line says who named it")
        payload = Rows(Loaded(env.CaerdonItem:CreateFromItemID(WRIT)))
        Check(payload:find("skipped, repeatable (the item can still start it)", 1, true) ~= nil,
            "export: a quest that can be done again says the item can still start it")
        payload = Rows(Loaded(env.CaerdonItem:CreateFromBagAndSlot(0, SLOT[SCRAP])))
        Check(payload:find("Starts A Quest Not Taken Yet: false", 1, true) ~= nil, "export: an item that starts nothing says so")
        Equal(#client.errors, 0, "export: no error reached the error handler")
    end
end
