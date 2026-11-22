-- What the client says about a quest's item in a bag slot (CaerdonQuestItems:GetSlotQuestInfo,
-- the item's GetSlotQuestInfo), where it is shown (the export's [Quest Value]) and collected
-- (the test addon's contract quest.slotInfo).
--
-- No status is made from the answer. The addon's quest icon comes from the quest log and
-- from QuestieDB, and this is the measurement that says where the client's own answer
-- differs: a letter that starts a quest the addon knows nothing of.
--
-- The game is hand-made, and so are the answers: what a client says for a starter item (is
-- it a quest item for it, does a finished quest still have its ID) has not been seen.
--
-- Real code: the addon's item side and features/DebugFrame.lua, the test addon's runner and
-- contracts, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 33 }

    local LETTER, ORDERS, EAR, PEBBLE = 992001, 992002, 992003, 992004
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
    local BAG = { LETTER, ORDERS, EAR, PEBBLE }
    local ANSWERS = {
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
    game:Set("C_TooltipInfo.GetBagItem", function(bag, slot) return BAG[slot] and hyperlink(game.Link(BAG[slot])) end)
    local asked = 0
    game:Set("C_Container.GetContainerItemQuestInfo", function(bag, slot)
        asked = asked + 1
        return bag == 0 and ANSWERS[BAG[slot]] or { isQuestItem = false, isActive = false }
    end)
    game:Set("C_QuestLog.GetTitleForQuestID", function(questID) return TITLES[questID] end)
    game:Set("C_QuestLog.IsOnQuest", function(questID) return questID == 8102 end)
    game:Set("C_QuestLog.IsQuestFlaggedCompleted", function() return false end)
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
    local function Status(item, slot)
        local ready, status
        client:TickUntil(function()
            ready, status = item:GetCaerdonStatus(nil, slot and { bag = 0, slot = slot } or nil)
            return ready
        end, 10)
        return ready and (status or "") or "<not ready>"
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

        -- No status is made from it: the letter is what it was, the client asked or not.
        local letterStatus = Status(letter, 1)
        Check(letterStatus ~= "quest" and letterStatus ~= "<not ready>",
            "status: the letter has no quest icon from the client's answer (" .. letterStatus .. ")")
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
        local wanted = { ["Core.lua"] = true, ["Runner.lua"] = true, ["Contracts.lua"] = true, ["Plan.lua"] = true }
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
        Equal(detail.startersTheAddonDoesNotName, 2, "contract: the addon names neither quest for its item")
        local seen = detail.seen or {}
        local letter, orders = seen[tostring(LETTER)] or {}, seen[tostring(ORDERS)] or {}
        Equal(letter.questID, 8101, "contract: the letter is kept with its quest")
        Equal(letter.name, "Torn Letter", "contract: with its name")
        Equal(letter.classID, 15, "contract: with its class")
        Check(letter.status ~= nil and letter.status ~= "quest" and letter.status ~= "not ready",
            "contract: and with the addon's status, which is no quest icon (" .. tostring(letter.status) .. ")")
        Equal(orders.isActive, true, "contract: the orders' quest is in the log")
        Equal(detail.startersWithoutQuestIcon, orders.status == "quest" and 1 or 2,
            "contract: the starters without the addon's quest icon are counted (" .. tostring(orders.status) .. ")")
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
        Equal(#client.errors, 0, "contract: no error reached the error handler")
    end
end
