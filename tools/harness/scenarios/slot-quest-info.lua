-- What the client says about a quest's item in a bag slot (CaerdonQuestItems:GetSlotQuestInfo,
-- the item's GetSlotQuestInfo), where it is shown (the export's [Quest Value]) and collected
-- (the test addon's contract quest.slotInfo).
--
-- The quest the client names is one of the item's quests for the addon, here with no quest
-- data loaded at all: a letter that starts a quest nothing else knows of is one to act on in
-- the bags (the star with the quest icon as its small mark), and what it was by its bare
-- link. The rule itself, with quest data, is scenarios/quest-starters.lua.
--
-- The game is hand-made, and so are the answers. A Forever client has shown one starter (a
-- writ whose quest was in the log: no quest item for the client, the quest's ID kept); what
-- a client says for a starter whose quest is done has not been seen.
--
-- Real code: the addon's item side and features/DebugFrame.lua, the test addon's runner and
-- contracts, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 33 }

    local LETTER, ORDERS, EAR, PEBBLE, TOKEN = 992001, 992002, 992003, 992004, 992005
    local ITEMS = {
        -- Starts a quest that is not in the log. Nothing else says it is a quest's.
        [LETTER] = { name = "Torn Letter", quality = 1, level = 1, minLevel = 0, type = "Miscellaneous", subType = "Junk",
            stack = 1, price = 25, classID = 15, subClassID = 0 },
        -- A quest's item for the client, and starts a quest that is in the log.
        [ORDERS] = { name = "Sealed Orders", quality = 1, level = 1, minLevel = 0, type = "Miscellaneous",
            subType = "Junk", stack = 1, price = 0, classID = 15, subClassID = 0, bindType = 4 },
        -- A quest's item for the client, and starts nothing.
        [EAR] = { name = "Bandit Ear", quality = 1, level = 1, minLevel = 0, type = "Miscellaneous", subType = "Junk",
            stack = 20, price = 0, classID = 15, subClassID = 0, bindType = 4 },
        -- Nothing to do with a quest.
        [PEBBLE] = { name = "Pebble", quality = 0, level = 1, minLevel = 0, type = "Miscellaneous", subType = "Junk",
            stack = 20, price = 1, classID = 15, subClassID = 0 },
    }
    -- Another class's token: the client names the quest it starts whoever holds the copy, and
    -- its own class line is red for this toon (type 43, requirement type 0, as the clients'
    -- recordings have it). Only in the bag for the bag states.
    ITEMS[TOKEN] = { name = "Essence of a Stranger", quality = 4, level = 16, minLevel = 0, type = "Miscellaneous",
        subType = "Junk", stack = 1, price = 500000, classID = 15, subClassID = 0,
        tooltip = { { text = "This Item Begins a Quest", type = 0 },
            { text = "Classes: Warrior", type = 43, requirementType = 0, r = 1, g = 0.125, b = 0.125 } } }
    local BAG = { LETTER, ORDERS, EAR, PEBBLE }
    local ANSWERS = {
        [TOKEN] = { isQuestItem = false, questID = 8103, isActive = false },
        [LETTER] = { isQuestItem = false, questID = 8101, isActive = false },
        [ORDERS] = { isQuestItem = true, questID = 8102, isActive = true },
        [EAR] = { isQuestItem = true, isActive = false },
        [PEBBLE] = { isQuestItem = false, isActive = false },
    }
    local TITLES = { [8101] = "A Torn Letter", [8102] = "Orders From Above" }

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
            isReadable = false, hasLoot = false } or nil
    end)
    game:Set("C_Container.GetContainerItemPurchaseInfo", function() return nil end)
    -- What the test addon's bag states ask of a slot.
    game:Set("C_Container.GetContainerItemCooldown", function() return 0, 0, 1 end)
    game:Set("C_TooltipInfo.GetBagItem", function(bag, slot) return BAG[slot] and hyperlink(game.Link(BAG[slot])) end)
    local asked = 0
    game:Set("C_Container.GetContainerItemQuestInfo", function(bag, slot)
        asked = asked + 1
        return bag == 0 and ANSWERS[BAG[slot]] or { isQuestItem = false, isActive = false }
    end)
    game:Set("C_QuestLog.GetTitleForQuestID", function(questID) return TITLES[questID] end)
    local completed = {}
    game:Set("C_QuestLog.IsOnQuest", function(questID) return questID == 8102 end)
    game:Set("C_QuestLog.IsQuestFlaggedCompleted", function(questID) return completed[questID] == true end)
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

    local function Loaded(item)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        client:TickUntil(function() return loaded end, 10)
        return item
    end
    -- The status, and the small mark beside it.
    local function Status(item, slot)
        local ready, status, mark, _
        client:TickUntil(function()
            ready, status, _, _, _, mark = item:GetCaerdonStatus(nil, slot and { bag = 0, slot = slot } or nil)
            return ready
        end, 10)
        return ready and (status or "") or "<not ready>", mark
    end

    -- The module and the item's entry point.
    do
        local info = env.CaerdonQuestItems:GetSlotQuestInfo(0, 1)
        Check(info and info.questID == 8101 and info.isActive == false and info.isQuestItem == false,
            "module: the client's answer for the slot is handed on as it is")
        Equal(env.CaerdonQuestItems:GetSlotQuestInfo(nil, 1), nil, "module: no slot, no answer")
        local letter = Loaded(env.CaerdonItem:CreateFromBagAndSlot(0, 1))
        Equal((letter:GetSlotQuestInfo() or {}).questID, 8101, "item: a copy in a bag slot has its slot's answer")
        local before = asked
        Equal(Loaded(env.CaerdonItem:CreateFromItemID(LETTER)):GetSlotQuestInfo(), nil, "item: an item that lies nowhere has none")
        Equal(asked, before, "item: and the client is not asked for it")

        -- The bare link first: nothing names a quest for it, and it is what it was.
        local bare = Loaded(env.CaerdonItem:CreateFromItemID(LETTER))
        Equal(bare:GetQuestItemInfo(), nil, "status: no quest is known for the letter by its link")
        local bareStatus, bareMark = Status(bare)
        Check(bareStatus ~= "quest" and bareStatus ~= "own" and bareStatus ~= "<not ready>" and bareMark == nil,
            "status: by its link the letter is no quest's item and none to start (" .. bareStatus .. ")")
        -- The copy in the bags starts a quest by the client's word, with no quest data loaded.
        local info = letter:GetQuestItemInfo()
        Check(info and info.starts and info.starts.questID == 8101, "status: the copy in the bags starts the quest the client names")
        local letterStatus, letterMark = Status(letter, 1)
        Equal(letterStatus, "own", "status: the letter in the bags has the star")
        Equal(letterMark, "quest", "status: with the quest icon as its small mark")
        Equal((Status(bare)), bareStatus, "status: and the bare link is still what it was")
        -- A quest that is in the log, and an item that starts nothing.
        local orders = Loaded(env.CaerdonItem:CreateFromBagAndSlot(0, 2))
        local ordersStatus, ordersMark = Status(orders, 2)
        Equal(ordersStatus, "quest", "status: orders whose quest is in the log have the quest icon")
        Equal(ordersMark, nil, "status: alone")
        local pebble = Loaded(env.CaerdonItem:CreateFromBagAndSlot(0, 4))
        Check((Status(pebble, 4)) ~= "own" and select(2, Status(pebble, 4)) == nil, "status: a pebble starts nothing")
    end

    -- The export's row.
    do
        local feature = env.CaerdonWardrobe:GetFeature("DebugFrame")
        local function Row(item)
            local payload = feature:BuildClipboardPayload(item)
            for line in (payload .. "\n"):gmatch("(.-)\n") do
                if line:find("The Client, For Its Bag Slot", 1, true) then
                    return line
                end
            end
        end
        local row = Row(Loaded(env.CaerdonItem:CreateFromBagAndSlot(0, 1))) or ""
        Check(row:find("no quest item, starts quest 8101 (A Torn Letter), which is not in the log", 1, true) ~= nil,
            "export: the letter's row names the quest it starts (" .. row .. ")")
        row = Row(Loaded(env.CaerdonItem:CreateFromBagAndSlot(0, 2))) or ""
        Check(row:find("a quest item, starts quest 8102 (Orders From Above), which is in the log", 1, true) ~= nil,
            "export: the orders' row says their quest is in the log (" .. row .. ")")
        row = Row(Loaded(env.CaerdonItem:CreateFromBagAndSlot(0, 3))) or ""
        Check(row:find("a quest item, starts no quest", 1, true) ~= nil, "export: the ear starts nothing (" .. row .. ")")
        row = Row(Loaded(env.CaerdonItem:CreateFromItemID(LETTER))) or ""
        Check(row:find("not asked", 1, true) ~= nil, "export: an item in no bag slot says it was not asked (" .. row .. ")")
        Equal(#client.errors, 0, "export: no error reached the error handler")
    end

    -- The contract.
    do
        local wanted = { ["Core.lua"] = true, ["Runner.lua"] = true, ["Contracts.lua"] = true, ["Plan.lua"] = true,
            ["Facts.lua"] = true, ["Snapshot.lua"] = true, ["Sightings.lua"] = true }
        local T = H.LoadAddon(client, "CaerdonWardrobe_Tests", H.addonDir .. "/CaerdonWardrobe_Tests",
            function(relative) return not wanted[relative] end)
        client:Fire("ADDON_LOADED", "CaerdonWardrobe_Tests")
        client:Fire("PLAYER_LOGIN")
        local ID = "quest.slotInfo"
        local function Run()
            T.RunTests({ match = ID, force = true })
            Check(client:TickUntil(function() return not T.IsBusy() end, 240), "contract: the job ends")
            return (T.db.contracts[T.GetClient().build] or {})[ID] or {}
        end

        local result = Run()
        Equal(result.status, "info", "contract: a collection, so info (" .. tostring(result.message) .. ")")
        local detail = result.detail or {}
        Equal(detail.items, 4, "contract: four items")
        Equal(detail.questItems, 2, "contract: two the client calls a quest's")
        Equal(detail.starters, 2, "contract: two that start a quest")
        Equal(detail.startersTheQuestDataDoesNotName, 2, "contract: no quest data names either quest for its item")
        Equal(detail.startersShownAsStarters, 1, "contract: one is drawn as one to start")
        Equal(detail.startersWithQuestIcon, 1, "contract: one has the quest icon")
        Equal(detail.startersWithNeither, 0, "contract: none has neither")
        local seen = detail.seen or {}
        local letter, orders = seen[tostring(LETTER)] or {}, seen[tostring(ORDERS)] or {}
        Equal(letter.questID, 8101, "contract: the letter is kept with its quest")
        Equal(letter.name, "Torn Letter", "contract: with its name")
        Equal(letter.classID, 15, "contract: with its class")
        Equal(letter.status, "own", "contract: with the addon's status, the star")
        Equal(letter.mark, "quest", "contract: and its small mark")
        Equal(letter.addonStarts, 8101, "contract: and the quest the addon calls one to start")
        Equal(letter.questReason, "no quest data", "contract: which no quest data knows")
        Equal(letter.completed, false, "contract: and the client does not flag as done")
        Equal(orders.isActive, true, "contract: the orders' quest is in the log")
        Equal(orders.status, "quest", "contract: so they have the quest icon")
        Equal(orders.addonStarts, nil, "contract: and are none to start")
        Check(seen[tostring(EAR)] ~= nil and seen[tostring(PEBBLE)] == nil,
            "contract: a quest item that starts nothing is kept, an item that is neither is not")

        -- An item that left the bags stays in what was seen.
        BAG = { PEBBLE, ORDERS }
        result = Run()
        Equal((result.detail or {}).starters, 1, "contract: the counts are the last run's")
        Check(((result.detail or {}).seen or {})[tostring(LETTER)] ~= nil, "contract: what an earlier run saw is kept")
        BAG = { LETTER, ORDERS, EAR, PEBBLE }

        -- An answer in another shape fails it.
        local usual = ANSWERS[EAR]
        ANSWERS[EAR] = { isQuestItem = true }
        result = Run()
        Equal(result.status, "fail", "fault: an answer without isActive fails the contract")
        Check(tostring(result.message):find("isActive a nil", 1, true) ~= nil, "fault: and says so (" .. tostring(result.message) .. ")")
        ANSWERS[EAR] = usual
        Equal(Run().status, "info", "contract: and is info again with the fault gone")

        -- A client that hands out the ID of a finished quest: the letter is none to start, and
        -- is counted with neither icon.
        completed[8101] = true
        env.CaerdonWardrobe:RefreshItems()
        result = Run()
        Equal((result.detail or {}).startersShownAsStarters, 0, "done: a letter whose quest is flagged as done is none to start")
        Equal((result.detail or {}).startersWithNeither, 1, "done: and is counted with neither icon")
        Equal(((result.detail or {}).seen or {})[tostring(LETTER)].completed, true, "done: kept with the client's flag")
        completed[8101] = nil
        env.CaerdonWardrobe:RefreshItems()

        -- The rule's premise, broken: the addon calls a quest one to start that the client
        -- says is in the log. (The log's own answer is left as it was.)
        ANSWERS[LETTER] = { isQuestItem = false, questID = 8101, isActive = true }
        result = Run()
        Equal(result.status, "fail", "fault: a quest called one to start that the client says is in the log fails the contract")
        Check(tostring(result.message):find("one to start, and the client says it is in the log", 1, true) ~= nil,
            "fault: and says so (" .. tostring(result.message) .. ")")
        ANSWERS[LETTER] = { isQuestItem = false, questID = 8101, isActive = false }
        Equal(Run().status, "info", "contract: info again")

        -- The bag states (Sightings.lua): a copy that starts a quest not taken yet is a case
        -- of its own, checked against the star or the grey gear. Whether the bank is open is
        -- asked of a file that is not loaded here.
        T.IsOpen = T.IsOpen or function() return false end
        BAG = { LETTER, ORDERS, EAR, PEBBLE, TOKEN }
        -- A record of the starter case as it was before its rule took the class line in.
        T.db.sightings.starter = { ["item:1"] = { result = "mismatch", status = "", at = 1 } }
        T.ScanSightings()
        client:Tick(5)
        Check(client:TickUntil(function() return not T.IsBusy() end, 240), "bag states: the scan ends")
        local records = T.db.sightings.starter or {}
        local count, record = 0, nil
        for _, entry in pairs(records) do
            count, record = count + 1, entry
        end
        Equal(count, 1, "bag states: one copy is a starter, the letter; the token is none, and the record of the rule from before is gone")
        local tokenCount, tokenRecord = 0, nil
        for _, entry in pairs(T.db.sightings.starterNotForThisToon or {}) do
            tokenCount, tokenRecord = tokenCount + 1, entry
        end
        Equal(tokenCount, 1, "bag states: another class's token is a case of its own")
        Equal(tokenRecord and tokenRecord.result, "pass", "bag states: and the addon agrees (" .. tostring(tokenRecord and tokenRecord.message) .. ")")
        Check(tokenRecord ~= nil and tokenRecord.status ~= "own" and tokenRecord.status ~= "lowSkill",
            "bag states: with no star and no grey gear (" .. tostring(tokenRecord and tokenRecord.status) .. ")")
        Equal(tokenRecord and tokenRecord.facts and tokenRecord.facts.classLineUnmet, true, "bag states: kept with its class line unmet")
        Equal(record and record.result, "pass", "bag states: and the addon agrees (" .. tostring(record and record.message) .. ")")
        Equal(record and record.status, "own", "bag states: with the star")
        Equal(record and record.facts and record.facts.clientStartsQuest, 8101, "bag states: kept with the quest the client names")
        Equal(record and record.linkStatus ~= "own", true, "bag states: and with what the bare link is, which is no starter")
        -- The judging itself: the gear passes too, the quest icon does not.
        local starterCase
        for _, case in ipairs(T.SightingCases) do
            if case.id == "starter" then
                starterCase = case
            end
        end
        Equal((T.JudgeSighting(starterCase, "lowSkill")), "pass", "bag states: the grey gear is a starter's icon too")
        local verdict, why = T.JudgeSighting(starterCase, "quest")
        Equal(verdict, "mismatch", "bag states: the quest icon is not")
        Equal(why, "status is quest, expected one of lowSkill, own", "bag states: and the record says what was expected")
        local tokenCase
        for _, case in ipairs(T.SightingCases) do
            if case.id == "starterNotForThisToon" then
                tokenCase = case
            end
        end
        verdict, why = T.JudgeSighting(tokenCase, "own")
        Equal(verdict, "mismatch", "bag states: a star on another class's token is a fault")
        Equal(why, "status is own, expected none of lowSkill, own", "bag states: and the record says so")
        Equal((T.JudgeSighting(tokenCase, "")), "pass", "bag states: no icon on it passes")
        Equal(#client.errors, 0, "bag states: no error reached the error handler")
        Equal(#client.errors, 0, "contract: no error reached the error handler")
    end
end
