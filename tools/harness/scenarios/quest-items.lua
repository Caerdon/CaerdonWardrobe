-- The quest icon for an item a quest hands over when it is accepted (QuestieDB's sourceItemId),
-- which is neither an objective nor a required item of that quest.
--
-- A Forever client showed the case: the Cursed Eye of Paleth (2944), given by "The Eye of
-- Paleth" (292) and still carried through "Cleansing the Eye" (293), had no quest icon. In
-- QuestieDB both quests name it only as their sourceItemId, and the index of which quests take
-- which item did not read that field. Here the game and the quest database are hand-made in
-- the same shape: an off-hand whose look is learned, a chain of two quests that hand it over.
--
-- Real code: the addon's item side, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 31 }

    local function Holdable(name, appearance)
        return { name = name, quality = 2, level = 31, minLevel = 26, type = "Armor", subType = "Miscellaneous",
            stack = 1, equipLoc = "INVTYPE_HOLDABLE", price = 0, classID = 4, subClassID = 0, bindType = 4,
            tooltip = { { text = "Quest Item", type = 20, bonding = 0 } }, appearance = appearance }
    end

    local ITEMS = {
        -- Handed over by both quests of the chain, and by nothing else.
        [950001] = Holdable("Cursed Eye", { appearanceID = 5201, sourceID = 7201, collected = true }),
        -- The same kind of item, which no quest names.
        [950002] = Holdable("Quiet Orb", { appearanceID = 5202, sourceID = 7202, collected = true }),
    }
    -- Worn in the off-hand and better than both, so neither is an upgrade.
    ITEMS[950003] = Holdable("Worn Lantern", { appearanceID = 5203, sourceID = 7203, collected = true })
    ITEMS[950003].level, ITEMS[950003].bindType, ITEMS[950003].tooltip = 45, 1, {}
    local OFFHAND = 17

    -- The fields QuestieDB has for the two quests, as it has them for 292 and 293.
    local QUESTS = {
        [8001] = { name = "The Eye", requiredLevel = 22, questLevel = 30, sourceItemId = 950001, startedBy = { { 5 } },
            nextQuestInChain = 8002 },
        [8002] = { name = "Cleansing the Eye", requiredLevel = 22, questLevel = 30, sourceItemId = 950001,
            startedBy = { { 6 } } },
    }

    local onQuest, completed = {}, {}

    local game = H.StockGame(TOON, ITEMS)
    game:Set("GetInventoryItemID", function(_, slot) return slot == OFFHAND and 950003 or nil end)
    game:Set("GetInventoryItemLink", function(_, slot) return slot == OFFHAND and game.Link(950003) or nil end)
    local function Worn(location)
        return type(location) == "table" and location.IsEquipmentSlot and location:IsEquipmentSlot() and
            location:GetEquipmentSlot() == OFFHAND
    end
    game:Set("C_Item.DoesItemExist", function(location) return Worn(location) == true end)
    game:Set("C_Item.GetItemLink", function(location) return Worn(location) and game.Link(950003) or nil end)
    game:Set("C_Item.GetItemID", function(location) return Worn(location) and 950003 or nil end)
    game:Set("C_Item.GetCurrentItemLevel", function(location) return Worn(location) and ITEMS[950003].level or nil end)
    game:Set("GetInstanceInfo", function() return "Wetlands", "none" end)
    game:Set("C_TooltipInfo.GetInventoryItem", function(_, slot)
        return slot == OFFHAND and game.client.env.C_TooltipInfo.GetHyperlink(game.Link(950003)) or nil
    end)
    game:Set("LibQuestieDB.RequireContract", function() return true end)
    game:Set("LibQuestieDB.Quest.GetAllIds", function() return { 8001, 8002 } end)
    game:Set("LibQuestieDB.Quest.Get", function(questID, field) return QUESTS[questID] and QUESTS[questID][field] end)
    game:Set("LibQuestieDB.Enum", { classKeys = { HUNTER = 4 }, raceMaskById = { [3] = 4 } })
    game:Set("C_QuestLog.IsOnQuest", function(questID) return onQuest[questID] == true end)
    game:Set("C_QuestLog.IsQuestFlaggedCompleted", function(questID) return completed[questID] == true end)
    game:Set("C_QuestLog.GetTitleForQuestID", function() return nil end)

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
    Equal(#client.errors, 0, "start: no error reached the error handler")

    -- The index is built after the first question, over the next frames.
    env.CaerdonQuestItems:GetItemQuestInfo(950001, "Cursed Eye")
    client:Tick(20)

    local function Load(itemID)
        local item = env.CaerdonItem:CreateFromItemID(itemID)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        client:TickUntil(function() return loaded end, 10)
        return item
    end

    local function Status(item)
        local ready, status
        client:TickUntil(function()
            ready, status = item:GetCaerdonStatus()
            return ready
        end, 10)
        return ready and (status or "") or "<not ready>"
    end

    -- A quest event, and the refresh it asks for half a second later.
    local function After(event)
        client:Fire(event)
        client:Tick(60)
    end

    local eye, orb = Load(950001), Load(950002)

    local indexed = env.CaerdonQuestItems:GetIndexedQuests(950001)
    Check(indexed and indexed[8001] == "provided" and indexed[8002] == "provided",
        "index: both quests that hand the eye over are in it, as the quests that provide it")

    -- Neither quest taken yet: the first one is for this toon's level.
    local info = eye:GetQuestItemInfo()
    Check(info and info.hasQuestValue and info.isUpcoming and not info.isActive,
        "upcoming: the eye is wanted by a quest the toon has not taken")
    Equal(Status(eye), "quest", "upcoming: the eye gets the quest icon over its learned look")
    local orbStatus = Status(orb)
    Check(orbStatus ~= "quest" and orbStatus ~= "<not ready>",
        "upcoming: the orb no quest names keeps its own status (" .. orbStatus .. ")")

    -- The first quest in the log.
    onQuest[8001] = true
    After("QUEST_ACCEPTED")
    info = eye:GetQuestItemInfo()
    Check(info and info.isActive, "active: the quest in the log takes the eye")
    Equal(Status(eye), "quest", "active: the quest icon")

    -- Turned in; the second quest of the chain still takes the eye.
    onQuest[8001], completed[8001] = nil, true
    After("QUEST_TURNED_IN")
    info = eye:GetQuestItemInfo()
    Check(info and info.isUpcoming and not info.isActive, "between: the next quest of the chain is still to take")
    Equal(Status(eye), "quest", "between: still the quest icon")

    -- Both done: nothing is left that takes it.
    completed[8002] = true
    After("QUEST_TURNED_IN")
    info = eye:GetQuestItemInfo()
    Check(info and not info.hasQuestValue, "done: no quest wants the eye any more")
    Equal(Status(eye), orbStatus, "done: the eye is back to the status the orb has")

    Equal(#client.errors, 0, "end: no error reached the error handler")
    for _, message in ipairs(client.errors) do
        Check(false, "error: " .. message)
    end
end
