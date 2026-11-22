-- A Quest-class item once its quests are behind the toon, and the quest icon on a page that
-- can be read.
--
-- A Forever client showed both: a quest's item kept the quest icon after its quest was turned
-- in, since the icon came from the item's class alone; and the pages of a book a quest in the
-- log asks for showed the readable icon, which is added per bag slot after the verdict and
-- stood in place of the quest icon.
--
-- The rule: a Quest-class item has the quest icon until every quest known for it is behind
-- the toon (done, or never to be taken). Then it is one to get rid of where it has no use, is
-- worn nowhere and has no equip effect, and is left unmarked otherwise. A copy that can be
-- read keeps the quest icon for as long as the item has it, and shows the readable icon once
-- it does not.
--
-- The game and the quest database are hand-made. The items' values are those of a letter and
-- a page as a Forever client answered for them (a fixture and an export: class 12, subclass 0,
-- "INVTYPE_NON_EQUIP_IGNORE", the binding line of type 20).
--
-- Real code: the addon's item side and features/DebugFrame.lua, Blizzard's base files from
-- the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 33 }

    local READ_LINE = { text = "<This item can be read>", type = 0, r = 0, g = 1, b = 0 }
    local QUEST_LINE = { text = "Quest Item", type = 20, bonding = 0 }
    local ON_EQUIP = 45 -- Enum.TooltipDataLineType.ItemSpellTriggerOnEquip

    local function QuestItem(name, fields)
        local item = { name = name, quality = 1, level = 1, minLevel = 0, type = "Quest", subType = "Quest", stack = 1,
            equipLoc = "INVTYPE_NON_EQUIP_IGNORE", price = 0, classID = 12, subClassID = 0, bindType = 4,
            tooltip = { QUEST_LINE } }
        for key, value in pairs(fields or {}) do
            item[key] = value
        end
        return item
    end

    local PAGE, LETTER, TOOTH, HORN, BADGE, STONE, RELIC, SCRAP, TOKEN, COIN, SLIP, KEY, HALF, ORB = 993001, 993002,
        993003, 993004, 993005, 993006, 993007, 993008, 993009, 993010, 993011, 993012, 993013, 993014
    local ITEMS = {
        -- A page of a book: no binding, a vendor price, stacks. A quest in the log asks for it.
        [PAGE] = QuestItem("Hill Page 25", { stack = 10, price = 375, bindType = 0, tooltip = { READ_LINE }, readable = true }),
        -- A letter no quest is known for.
        [LETTER] = QuestItem("Old Letter", { tooltip = { QUEST_LINE, READ_LINE }, readable = true }),
        -- Three things a finished quest asked for: one that does nothing, one with a use, one
        -- with an equip effect.
        [TOOTH] = QuestItem("Troll Tooth", { stack = 20 }),
        [HORN] = QuestItem("Signal Horn", { spell = { name = "Blow the Horn", id = 990001 } }),
        [BADGE] = QuestItem("Lucky Badge", { tooltip = { QUEST_LINE,
            { text = "Equip: Luck comes to those who wait.", type = ON_EQUIP, r = 0, g = 1, b = 0, spellID = 990002 } } }),
        -- For a quest twelve levels away.
        [STONE] = QuestItem("Far Stone"),
        -- For a quest of another class.
        [RELIC] = QuestItem("Priest's Relic"),
        -- For a quest that is done and can be done again.
        [SCRAP] = QuestItem("Daily Scrap", { stack = 20 }),
        -- For a quest still to come, which another quest excludes once that one is done.
        [TOKEN] = QuestItem("Left Token"),
        -- For a quest that is trivial by now, which another quest excludes once that one is done.
        [COIN] = QuestItem("Old Coin"),
        -- Handed over by one quest, and taken by a second that can be done again and that the
        -- quest data does not tie to the first (a scrip to exchange for a book).
        [SLIP] = QuestItem("Reading Slip"),
        -- For a quest twelve levels away that follows on another.
        [KEY] = QuestItem("Vault Key"),
        -- No quest is known for it, and the item itself asks for level 50.
        [HALF] = QuestItem("Top Half of a Manual", { minLevel = 50, bindType = 0 }),
        -- For a quest of level 55 whose data has no level it asks for.
        [ORB] = QuestItem("Flawless Orb", { stack = 20, bindType = 0 }),
    }
    local BAG = { PAGE, LETTER, TOOTH, HORN, BADGE, STONE, RELIC, SCRAP, TOKEN, COIN, SLIP }
    local SLOT = {}
    for slot, id in ipairs(BAG) do
        SLOT[id] = slot
    end

    local QUESTS = {
        [8201] = { name = "Chapter IV", requiredLevel = 28, questLevel = 33, startedBy = { { 5 } },
            objectives = { [3] = { { PAGE } } } },
        [8202] = { name = "Teeth for the Chief", requiredLevel = 28, questLevel = 33, startedBy = { { 5 } },
            objectives = { [3] = { { TOOTH }, { HORN }, { BADGE } } } },
        [8203] = { name = "A Later Errand", requiredLevel = 45, questLevel = 47, startedBy = { { 5 } },
            objectives = { [3] = { { STONE } } } },
        [8204] = { name = "The Priest's Task", requiredLevel = 28, questLevel = 33, requiredClasses = 16,
            startedBy = { { 5 } }, objectives = { [3] = { { RELIC } } } },
        [8205] = { name = "Scraps Again", requiredLevel = 28, questLevel = 33, specialFlags = 1, startedBy = { { 5 } },
            objectives = { [3] = { { SCRAP } } } },
        [8206] = { name = "The Left Hand", requiredLevel = 28, questLevel = 33, exclusiveTo = { 8207 },
            startedBy = { { 5 } }, objectives = { [3] = { { TOKEN } } } },
        [8207] = { name = "The Right Hand", requiredLevel = 28, questLevel = 33, exclusiveTo = { 8206 },
            startedBy = { { 5 } } },
        [8208] = { name = "An Old Debt", requiredLevel = 5, questLevel = 10, exclusiveTo = { 8209 },
            startedBy = { { 5 } }, objectives = { [3] = { { COIN } } } },
        [8209] = { name = "A Debt Forgiven", requiredLevel = 5, questLevel = 10, exclusiveTo = { 8208 },
            startedBy = { { 5 } } },
        [8210] = { name = "The Stone in the Book", requiredLevel = 28, questLevel = 33, sourceItemId = SLIP,
            startedBy = { { 5 } } },
        [8211] = { name = "The Reading Room", requiredLevel = 1, questLevel = 1, specialFlags = 1, startedBy = { { 5 } },
            objectives = { [3] = { { SLIP } } } },
        [8212] = { name = "The Vault", requiredLevel = 45, questLevel = 47, preQuestSingle = { 8213 },
            startedBy = { { 5 } }, objectives = { [3] = { { KEY } } } },
        [8213] = { name = "Word of the Vault", requiredLevel = 28, questLevel = 33, startedBy = { { 5 } } },
        [8214] = { name = "To Serve the Orb", requiredLevel = 0, questLevel = 55, startedBy = { { 5 } },
            objectives = { [3] = { { ORB } } } },
    }
    local ALL_QUESTS = { 8201, 8202, 8203, 8204, 8205, 8206, 8207, 8208, 8209, 8210, 8211, 8212, 8213, 8214 }
    local onQuest = { [8201] = true, [8210] = true }
    local completed = { [8202] = true, [8205] = true }

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
    game:Set("C_Container.GetContainerItemQuestInfo", function() return { isQuestItem = true, isActive = false } end)
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
    -- What a copy with a use is asked in its bag slot (the combine statuses).
    game:Set("C_Spell.GetSpellDescription", function() return "Calls the others to the hill." end)
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
    env.CaerdonQuestItems:GetItemQuestInfo(PAGE, ITEMS[PAGE].name)
    client:Tick(20)

    local function Loaded(item)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        client:TickUntil(function() return loaded end, 10)
        return item
    end
    local function StatusOf(item, slot)
        local ready, status
        client:TickUntil(function()
            ready, status = item:GetCaerdonStatus(nil, slot and { bag = 0, slot = slot } or nil)
            return ready
        end, 10)
        return ready and (status or "") or "<not ready>"
    end
    -- The copy in its bag slot, and the bare link (a mail, a loot window).
    local function InBag(id)
        return StatusOf(Loaded(env.CaerdonItem:CreateFromBagAndSlot(0, SLOT[id])), SLOT[id])
    end
    local function ByLink(id)
        return StatusOf(Loaded(env.CaerdonItem:CreateFromItemID(id)))
    end
    -- What the copy in its bag slot is beside its status (the status's sixth value).
    local function MarkInBag(id)
        local item = Loaded(env.CaerdonItem:CreateFromBagAndSlot(0, SLOT[id]))
        StatusOf(item, SLOT[id])
        return (select(6, item:GetCaerdonStatus(nil, { bag = 0, slot = SLOT[id] })))
    end
    local function Info(id)
        return Loaded(env.CaerdonItem:CreateFromItemID(id)):GetQuestItemInfo()
    end
    -- A quest event, and the refresh it asks for half a second later.
    local function After(event)
        client:Fire(event)
        client:Tick(60)
    end

    -- A page a quest in the log asks for: the quest icon, in the bags too.
    do
        local info = Info(PAGE)
        Check(info and info.isActive and info.hasQuestValue and not info.isOver, "page: a quest in the log takes it")
        Equal(ByLink(PAGE), "quest", "page: the quest icon by its link")
        Equal(InBag(PAGE), "quest", "page: and on the copy in the bags, which can be read")
        -- Asked a second time, from the kept verdict.
        Equal(InBag(PAGE), "quest", "page: the same from the kept verdict")
        -- That it can be read is said beside the status, for the small mark on the quest icon.
        Equal(MarkInBag(PAGE), "readable", "page: and the copy is said to be one that can be read")
        Equal(select(6, Loaded(env.CaerdonItem:CreateFromItemID(PAGE)):GetCaerdonStatus()), nil,
            "page: which its bare link is not")
        Equal(MarkInBag(TOOTH), nil, "page: nor a copy that cannot be read")
    end

    -- A letter no quest is known for: the quest icon by its class, in the bags too. What can
    -- be read is what gets sold or deleted unread.
    do
        Equal(Info(LETTER), nil, "letter: no quest is known for it")
        Equal(ByLink(LETTER), "quest", "letter: the quest icon by its class")
        Equal(InBag(LETTER), "quest", "letter: and in the bags, though it can be read")
        Equal(InBag(LETTER), "quest", "letter: the same from the kept verdict")
        Equal(MarkInBag(LETTER), "readable", "letter: said to be one that can be read")
    end

    -- A finished quest's items.
    do
        local info = Info(TOOTH)
        Check(info and info.isOver and not info.hasQuestValue, "done: the tooth's one quest is behind the toon")
        Equal(info and info.quests[1] and info.quests[1].over, true, "done: and the quest says so itself")
        Equal(InBag(TOOTH), "sellable", "done: a tooth that does nothing is one to get rid of")
        Equal(ByLink(TOOTH), "sellable", "done: by its link as well")
        Equal(InBag(HORN), "", "done: a horn with a use is left unmarked")
        Equal(InBag(BADGE), "", "done: a badge with an equip effect is left unmarked")
    end

    -- Quests that are not behind the toon keep the icon.
    do
        local info = Info(STONE)
        Check(info and not info.isOver and not info.hasQuestValue, "later: a quest twelve levels away is not behind the toon")
        Check(info and info.keptOutByOptions == true, "later: it is the player's range that keeps it out")
        Equal(InBag(STONE), "", "later: its stone has no icon while its quest is beyond the range, and is not one to get rid of")
        info = Info(SCRAP)
        Check(info and not info.isOver, "again: a quest that is done and can be done again is not behind the toon")
        Equal(InBag(SCRAP), "quest", "again: its scrap keeps the quest icon")
    end

    -- The player's settings for quests not picked up yet, and a chain the toon is on.
    do
        local config = env.CaerdonWardrobeConfig.Icon
        local function Refresh()
            env.CaerdonWardrobe:RefreshItems()
        end
        Check(not Info(STONE).hasQuestValue, "range: twelve levels away is beyond the default's five")
        -- The copy in the bags has the quest icon by its class all the same; a copy the toon
        -- does not hold (an auction's) has it only within the range.
        Equal(InBag(STONE), "", "range: the stone in the bags has no quest icon then")
        -- A quest whose data has no level it asks for goes by its own level.
        local orb = Info(ORB)
        Check(orb and not orb.hasQuestValue and orb.keptOutByOptions == true,
            "range: a quest of level 55 with no level it asks for is beyond the range")
        Equal(orb and orb.quests[1] and orb.quests[1].reason, "of level 55, and the level it asks for is not known",
            "range: and says why")
        Equal(ByLink(ORB), "", "range: its orb has no quest icon")
        Equal(Info(HALF), nil, "range: no quest is known for the half of a manual")
        Equal(ByLink(HALF), "", "range: its own level of 50 is beyond the range, so it has no quest icon")
        Equal(ByLink(LETTER), "quest", "range: a letter that asks for no level keeps the icon its class gives")
        Equal(ByLink(STONE), "", "range: nor has one the toon does not hold")
        config.UpcomingQuestLevels = "20"
        Refresh()
        Check(Info(STONE).hasQuestValue and Info(STONE).isUpcoming, "range: and within twenty")
        Equal(ByLink(STONE), "quest", "range: and the stone has the icon then")
        -- An item no quest is known for goes by the level it asks for itself (17 above the toon).
        Equal(ByLink(HALF), "quest", "range: an item no quest is known for, of level 50, is within twenty too")
        Check(not Info(ORB).hasQuestValue, "range: the quest of level 55 is beyond twenty as well")
        local row = Loaded(env.CaerdonItem:CreateFromItemID(HALF))
        Equal(select(2, row:IsQuestItemBeyondRange()), 50, "range: the level it asks for is read")
        Equal(InBag(STONE), "quest", "range: in the bags too")
        config.UpcomingQuestLevels = "2"
        Refresh()
        Check(not Info(STONE).hasQuestValue, "range: not within two")
        config.UpcomingQuestLevels = "any"
        Refresh()
        Check(Info(STONE).hasQuestValue, "range: and within any")
        Check(Info(ORB).hasQuestValue, "range: so is the quest of level 55")
        config.UpcomingQuestLevels = "5"
        Refresh()

        Check(not Info(COIN).hasQuestValue, "trivial: a quest that is trivial for the toon does not count")
        config.IncludeTrivialQuests = true
        Refresh()
        Check(Info(COIN).hasQuestValue, "trivial: and does where the player asks for those")
        Equal(InBag(COIN), "quest", "trivial: its coin has the quest icon then")
        config.IncludeTrivialQuests = false
        Refresh()

        local info = Info(KEY)
        Equal(info and info.quests[1] and info.quests[1].reason, "needs level 45",
            "chain: a quest twelve levels away does not count while the one before it is not begun")
        onQuest[8213] = true
        After("QUEST_ACCEPTED")
        info = Info(KEY)
        Check(info and info.hasQuestValue and info.quests[1].eligible == true,
            "chain: on the quest before it, it is still to come whatever its level")
        Equal(ByLink(KEY), "quest", "chain: and its key has the quest icon")
        onQuest[8213] = nil
        After("QUEST_REMOVED")
        Check(not Info(KEY).hasQuestValue, "chain: and not once that quest is dropped")
    end

    -- A quest of another class is.
    do
        local info = Info(RELIC)
        Check(info and info.isOver, "class: another class's quest is behind the toon")
        Equal(InBag(RELIC), "sellable", "class: its relic is one to get rid of")
    end

    -- A quest event that puts a quest behind the toon is a change, from "still to come" and
    -- from "not wanted" alike.
    do
        Equal(InBag(TOKEN), "quest", "excluded: the token of a quest still to come has the quest icon")
        Equal(InBag(COIN), "", "excluded: the coin of a trivial quest has no icon while those are left out")
        Check(Info(COIN) and not Info(COIN).isOver, "excluded: a trivial quest is not behind the toon")
        completed[8207], completed[8209] = true, true
        After("QUEST_TURNED_IN")
        Check(Info(TOKEN) and Info(TOKEN).isOver, "excluded: the quest that excludes it done, the token's is behind the toon")
        Equal(InBag(TOKEN), "sellable", "excluded: and the token is one to get rid of")
        Equal(InBag(COIN), "sellable", "excluded: so is the coin")
    end

    -- What a quest handed over, taken by a quest that can be done again: wanted while the
    -- first is in the log, and no longer once it is done, though the second still stands.
    do
        local info = Info(SLIP)
        Check(info and info.isActive and info.hasQuestValue and not info.isOver, "slip: the quest that handed it over is in the log")
        Equal(InBag(SLIP), "quest", "slip: the quest icon")
        onQuest[8210], completed[8210] = nil, true
        After("QUEST_TURNED_IN")
        info = Info(SLIP)
        Check(info and info.isOver and not info.hasQuestValue, "slip: that quest done, the one left can be done again and does not count")
        for _, quest in ipairs(info and info.quests or {}) do
            if quest.questID == 8211 then
                Equal(quest.over, false, "slip: the quest left is not behind the toon itself")
                Equal(quest.setAside, true, "slip: it is set aside")
            end
        end
        -- The second quest can still take it: the quest icon stays, and that nothing else
        -- is to the slip is the small mark on it.
        Equal(InBag(SLIP), "quest", "slip: the quest icon stays")
        Equal(MarkInBag(SLIP), "sellable", "slip: with the mark of one to get rid of")
        Equal(select(6, Loaded(env.CaerdonItem:CreateFromItemID(SLIP)):GetCaerdonStatus()), "sellable",
            "slip: by its link as well")
        Equal(MarkInBag(SLIP), "sellable", "slip: the same from the kept verdict")
        Equal(info and info.repeatableLeft, true, "slip: the quest module says a quest that can be done again is left")
        -- The quest that can be done again in the log: wanted again.
        onQuest[8211] = true
        After("QUEST_ACCEPTED")
        Equal(InBag(SLIP), "quest", "slip: the quest icon while the second quest is in the log")
        Equal(MarkInBag(SLIP), nil, "slip: with no small mark")
        onQuest[8211] = nil
        After("QUEST_REMOVED")
        Equal(InBag(SLIP), "quest", "slip: the quest icon when it is dropped")
        Equal(MarkInBag(SLIP), "sellable", "slip: with the mark again")
        -- A tooth whose one quest is done has no quest left to take it: no quest icon.
        Equal(MarkInBag(TOOTH), nil, "slip: an item no quest is left for has the sell icon itself")
        -- The scrap of a quest that can be done again and was handed over by none keeps it.
        Equal(InBag(SCRAP), "quest", "slip: a scrap no quest handed over keeps the quest icon")
    end

    -- The export's rows.
    do
        local feature = env.CaerdonWardrobe:GetFeature("DebugFrame")
        local function Row(item, label)
            local payload = feature:BuildClipboardPayload(item)
            for line in (payload .. "\n"):gmatch("(.-)\n") do
                if line:find(label, 1, true) then
                    return line
                end
            end
        end
        local tooth = Loaded(env.CaerdonItem:CreateFromBagAndSlot(0, SLOT[TOOTH]))
        local row = Row(tooth, "Every Known Quest Behind The Toon") or ""
        Check(row:find("true", 1, true) ~= nil, "export: the tooth's quests are said to be behind the toon (" .. row .. ")")
        row = Row(tooth, "Nothing Else To It") or ""
        Check(row:find("true", 1, true) ~= nil, "export: and that nothing else is to it (" .. row .. ")")
        row = Row(tooth, "8202") or ""
        Check(row:find("completed (behind the toon)", 1, true) ~= nil, "export: its quest's line says so (" .. row .. ")")
        row = Row(Loaded(env.CaerdonItem:CreateFromBagAndSlot(0, SLOT[HORN])), "Nothing Else To It") or ""
        Check(row:find("false", 1, true) ~= nil, "export: the horn has something else to it (" .. row .. ")")
        row = Row(Loaded(env.CaerdonItem:CreateFromBagAndSlot(0, SLOT[LETTER])), "Every Known Quest Behind The Toon") or ""
        Check(row:find("no quest is known for it", 1, true) ~= nil, "export: the letter has no known quest (" .. row .. ")")
        local slip = Loaded(env.CaerdonItem:CreateFromBagAndSlot(0, SLOT[SLIP]))
        row = Row(slip, "8211 The Reading Room") or ""
        Check(row:find("not counted", 1, true) ~= nil, "export: the slip's second quest is said not to count (" .. row .. ")")
        row = Row(slip, "Every Known Quest Behind The Toon") or ""
        Check(row:find("true", 1, true) ~= nil, "export: and its quests to be behind the toon (" .. row .. ")")
        row = Row(slip, "A Quest That Can Be Done Again Still Takes It") or ""
        Check(row:find("true", 1, true) ~= nil, "export: that a quest can still take it (" .. row .. ")")
        row = Row(slip, "Small Mark On The Icon") or ""
        Check(row:find("sellable", 1, true) ~= nil, "export: and the small mark (" .. row .. ")")
        Equal(Row(tooth, "A Quest That Can Be Done Again Still Takes It"), nil, "export: which the tooth has no line for")
        Equal(#client.errors, 0, "export: no error reached the error handler")
    end

    -- The quest icon switched off: what is behind the toon is still one to get rid of, and
    -- what is not has no icon.
    do
        env.CaerdonWardrobeConfig.Icon.ShowQuestItems = false
        env.CaerdonWardrobe:RefreshItems()
        Equal(InBag(TOOTH), "sellable", "off: the tooth is still one to get rid of")
        Equal(InBag(SLIP), "sellable", "off: so is the slip, with no quest icon to stay")
        Equal(MarkInBag(SLIP), nil, "off: and nothing beside it")
        Equal(InBag(STONE), "", "off: the stone has no icon")
        Equal(InBag(PAGE), "readable", "off: the page shows that it can be read")
        Equal(MarkInBag(PAGE), nil, "off: as its status, with nothing beside it")
        env.CaerdonWardrobeConfig.Icon.ShowQuestItems = true
        env.CaerdonWardrobe:RefreshItems()
        Equal(InBag(PAGE), "quest", "on again: the page has the quest icon")
    end

    -- The page's quest turned in: the readable icon in the bags, and by its link a page
    -- that is one to get rid of.
    do
        onQuest[8201], completed[8201] = nil, true
        After("QUEST_TURNED_IN")
        local info = Info(PAGE)
        Check(info and info.isOver and not info.hasQuestValue, "turned in: the page's quest is behind the toon")
        Equal(InBag(PAGE), "readable", "turned in: the page in the bags shows that it can be read")
        Equal(ByLink(PAGE), "sellable", "turned in: by its link it is one to get rid of")
    end

    Equal(#client.errors, 0, "end: no error reached the error handler")
    for _, message in ipairs(client.errors) do
        Check(false, "error: " .. message)
    end
end
