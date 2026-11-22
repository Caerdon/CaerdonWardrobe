-- A small hand-made game: a provider for a mocked client that answers like a client, for the
-- scenarios. It stands in where a real client would be while the harness tests itself (the
-- recorder records this game, the replay must reproduce it).
--
-- It proves the machinery and nothing about the game: every answer here was written by hand
-- from what the addon's code asks, not copied from a client. What a client really answers is
-- in the recordings (tools/harness/fixtures).
--
-- A game is a flat table of names. A name may be dotted ("C_Item.GetItemInfo"); a value is a
-- function, a string, number or boolean, or a table handed over as it is. A name the game
-- does not have reads as nil, as in a client that lacks it, and is listed in game.missing.

local H = ...

local Game = {}
Game.__index = Game

function H.NewGame(names)
    local self = setmetatable({ names = {}, missing = {}, seenMissing = {}, tables = {}, parents = {} }, Game)
    for name, value in pairs(names or {}) do
        self:Set(name, value)
    end
    return self
end

function Game:Set(name, value)
    self.names[name] = value
    -- A namespace keeps what it has handed out (Game:Table), so a member that was asked for
    -- before is replaced there too: a scenario that sets its bags after the addon has read
    -- the stock ones would otherwise go unheard.
    local parent, key = name:match("^(.*)%.([^.]+)$")
    local proxy = parent and self.tables[parent]
    if proxy and rawget(proxy, key) ~= nil then
        rawset(proxy, key, value)
    end
    local at = 0
    while true do
        at = name:find(".", at + 1, true)
        if not at then
            break
        end
        self.parents[name:sub(1, at - 1)] = true
    end
end

function Game:Table(name)
    local proxy = self.tables[name]
    if not proxy then
        proxy = setmetatable({}, {
            __index = function(target, key)
                if type(key) ~= "string" then
                    return nil
                end
                local kind, value = self:Resolve(name .. "." .. key)
                if kind and kind ~= "absent" then
                    rawset(target, key, value)
                    return value
                end
                return nil
            end,
        })
        self.tables[name] = proxy
    end
    return proxy
end

function Game:Resolve(name)
    local value = self.names[name]
    if value ~= nil then
        local kind = type(value)
        return kind == "function" and "function" or kind == "table" and "table" or "value", value
    elseif self.parents[name] then
        return "table", self:Table(name)
    end
    -- Enum, Constants and the global strings are the listings mirror's.
    local root = name:match("^[^.]+")
    if root == "Enum" or root == "Constants" then
        local mirrored = self.client.listing.enums
        for part in name:gmatch("[^.]+") do
            mirrored = type(mirrored) == "table" and mirrored[part] or nil
        end
        if mirrored ~= nil then
            return type(mirrored) == "table" and "table" or "value", mirrored
        end
    elseif not name:find(".", 1, true) and (self.client.listing.strings[name] ~= nil
            or self.client.listing.enums[name] ~= nil) then
        return nil
    end
    if not self.seenMissing[name] then
        self.seenMissing[name] = true
        self.missing[#self.missing + 1] = name
    end
    return "absent"
end

------------------------------------------------------------------------------------------
-- The stock game: one toon and a few items
------------------------------------------------------------------------------------------

local function ItemID(reference)
    if type(reference) == "number" then
        return reference
    elseif type(reference) == "string" then
        return tonumber(reference:match("item:(%d+)")) or tonumber(reference)
    end
end

-- toon: { name, realm, class, classFile, race, faction, level }
-- An item with bonuses = { "12782", ... } has them in its link, and its level is then what its
-- link's bonus IDs say (game.levelBonuses: bonus ID -> the level it gives; the first of the
-- link's that gives one counts, and baseLevel where none does), as the client has it for a
-- season's gear. bonusLevels = { ["12831"] = 300 } is what an ID gives this one item, where
-- that is not what it gives the others.
-- items: id -> { name, quality, level, minLevel, type, subType, stack, equipLoc, icon, price,
--                classID, subClassID, bindType, expansion, tooltip = { { text, type, r, g, b } },
--                appearance = { appearanceID, sourceID, collected, valid, canCollect } }
function H.StockGame(toon, items)
    local game = H.NewGame()
    local function Client() return game.client end
    local function Item(reference)
        return items[ItemID(reference)]
    end
    local function Link(id)
        local item = items[id]
        -- A crafted piece's link ends in its maker's GUID (item.crafter).
        local bonuses = item.bonuses and #item.bonuses > 0 and (#item.bonuses .. ":" .. table.concat(item.bonuses, ":")) or ""
        return ("|cffffffff|Hitem:%d::::::::%d::::%s::::%s:|h[%s]|h|r"):format(id, toon.level, bonuses, item.crafter or "",
            item.name)
    end
    game.Link = Link
    game.items = items
    game.levelBonuses = {}
    -- The level a link's bonus IDs give an item that has them, or nil for any other reference.
    local function LevelByBonus(reference)
        local item = Item(reference)
        if not (item and item.bonuses and type(reference) == "string") then
            return nil
        end
        local fields = {}
        for field in (reference:match("|H(item:[^|]*)|h") or reference):gmatch("([^:]*):?") do
            fields[#fields + 1] = field
        end
        for index = 1, tonumber(fields[14]) or 0 do
            local level = (item.bonusLevels and item.bonusLevels[fields[14 + index]]) or game.levelBonuses[fields[14 + index]]
            if level then
                return level
            end
        end
        return item.baseLevel or 1
    end
    game.LevelByBonus = LevelByBonus

    local function Set(name, value) game:Set(name, value) end

    -- The client and the toon.
    Set("GetBuildInfo", function() return "1.60.1", "70938", "Nov 1 2026", 16001 end)
    Set("WOW_PROJECT_ID", 18)
    Set("WOW_PROJECT_MAINLINE", 1)
    Set("WOW_PROJECT_CAMELOT", 18)
    Set("LE_EXPANSION_LEVEL_CURRENT", 0)
    Set("GetLocale", function() return "enUS" end)
    Set("GetRealmName", function() return toon.realm end)
    Set("GetExpansionLevel", function() return 0 end)
    Set("InCombatLockdown", function() return false end)
    -- Read by the refresh watcher as the world comes (CaerdonRefresh.lua, the PVP watch).
    Set("GetInstanceInfo", function() return "Elsewhere", "none" end)
    Set("UnitName", function() return toon.name end)
    Set("UnitFullName", function() return toon.name, toon.realm end)
    Set("UnitGUID", function() return "Player-1-00000001" end)
    Set("UnitClass", function() return toon.class, toon.classFile, 3 end)
    Set("UnitRace", function() return toon.race, toon.race, 3 end)
    Set("UnitSex", function() return 2 end)
    Set("UnitLevel", function() return toon.level end)
    Set("UnitFactionGroup", function() return toon.faction, toon.faction end)
    Set("GetProfessions", function() return nil end)
    Set("GetProfessionInfo", function() return nil end)
    Set("GetInventoryItemID", function() return nil end)
    Set("GetInventoryItemLink", function() return nil end)
    Set("EquipPendingItem", function() end)
    for name, slot in pairs({ FIRST_EQUIPPED = 1, LAST_EQUIPPED = 19, FINGER1 = 11, FINGER2 = 12, TRINKET1 = 13,
        TRINKET2 = 14, MAINHAND = 16, OFFHAND = 17, RANGED = 18 }) do
        Set("INVSLOT_" .. name, slot)
    end
    Set("NUM_BAG_SLOTS", 4)
    Set("NUM_REAGENTBAG_SLOTS", 1)
    Set("NUM_TOTAL_EQUIPPED_BAG_SLOTS", 5)
    Set("C_TradeSkillUI.GetAllProfessionTradeSkillLines", function() return {} end)
    Set("C_TradeSkillUI.IsTradeSkillReady", function() return false end)
    Set("C_TradeSkillUI.GetProfessionInfoBySkillLineID", function() return nil end)
    Set("C_TradeSkillUI.GetChildProfessionInfos", function() return {} end)
    Set("StaticPopupDialogs", {})
    Set("SlashCmdList", {})
    Set("C_ToyBox.GetToyLink", function() return nil end)
    Set("HaveQuestData", function() return false end)
    Set("C_AddOns.IsAddOnLoaded", function() return false end)
    Set("C_AddOns.GetAddOnMetadata", function() return "v0.0.0" end)
    Set("C_AddOns.GetNumAddOns", function() return 0 end)
    Set("C_PaperDollInfo.IsRangedSlotShown", function() return true end)
    Set("C_QuestLog.GetNumQuestLogEntries", function() return 0 end)
    Set("C_QuestLog.IsQuestFlaggedCompleted", function() return false end)
    Set("C_QuestLog.RequestLoadQuestByID", function() end)
    Set("C_Spell.RequestLoadSpellData", function() end)
    Set("C_Container.GetContainerNumSlots", function() return 0 end)
    Set("C_Container.GetContainerItemID", function() return nil end)
    Set("C_Container.GetContainerNumFreeSlots", function() return 0, 0 end)
    Set("C_Container.ContainerIDToInventoryID", function(bag) return 30 + bag end)
    Set("C_EquipmentSet.CanUseEquipmentSets", function() return false end)
    Set("C_EquipmentSet.GetEquipmentSetIDs", function() return {} end)
    Set("C_PlayerInfo.CanUseItem", function(id) return Item(id) ~= nil and Item(id).usable ~= false end)

    -- Items.
    Set("C_Item.DoesItemExistByID", function(id) return Item(id) ~= nil end)
    Set("C_Item.IsItemDataCachedByID", function(id) return Item(id) ~= nil end)
    Set("C_Item.RequestLoadItemDataByID", function(id)
        local client = Client()
        client.env.C_Timer.After(0, function()
            client:Fire("ITEM_DATA_LOAD_RESULT", ItemID(id), Item(id) ~= nil)
        end)
    end)
    Set("C_Item.GetItemInfo", function(reference)
        local id, item = ItemID(reference), Item(reference)
        if not item then
            return nil
        end
        return item.name, Link(id), item.quality, item.level, item.minLevel, item.type, item.subType, item.stack,
            item.equipLoc or "", item.icon or 134400, item.price or 0, item.classID, item.subClassID,
            item.bindType or 0, item.expansion or 0, nil, false
    end)
    Set("C_Item.GetItemInfoInstant", function(reference)
        local id, item = ItemID(reference), Item(reference)
        if not item then
            return nil
        end
        return id, item.type, item.subType, item.equipLoc or "", item.icon or 134400, item.classID, item.subClassID
    end)
    Set("C_Item.GetItemNameByID", function(reference) return Item(reference) and Item(reference).name end)
    Set("C_Item.GetItemSpell", function(reference)
        local item = Item(reference)
        if item and item.spell then
            return item.spell.name, item.spell.id
        end
    end)
    Set("C_Item.DoesItemExist", function() return false end)
    Set("C_Item.GetItemIDForItemInfo", function(reference) return Item(reference) and ItemID(reference) end)
    Set("C_Item.GetItemQualityByID", function(reference) return Item(reference) and Item(reference).quality end)
    Set("C_Item.GetItemIconByID", function(reference) return Item(reference) and (Item(reference).icon or 134400) end)
    Set("C_Item.GetItemInventoryTypeByID", function() return 0 end)
    Set("C_Item.GetItemMaxStackSizeByID", function(reference) return Item(reference) and Item(reference).stack end)
    Set("C_TradeSkillUI.GetOriginalCraftRecipeID", function() return nil end)
    Set("C_Item.GetItemCount", function() return 0 end)
    Set("C_Item.GetItemMaxStackSize", function(reference) return Item(reference) and Item(reference).stack end)
    Set("C_Item.GetItemInventoryType", function() return 0 end)
    Set("C_Item.GetDetailedItemLevelInfo", function(reference)
        local byBonus = LevelByBonus(reference)
        if byBonus then
            return byBonus, false, byBonus
        end
        return Item(reference) and Item(reference).level, false, Item(reference) and Item(reference).level
    end)
    Set("C_Item.GetItemStats", function() return {} end)
    Set("C_Item.GetItemSpecInfo", function() return nil end)
    Set("C_Item.GetItemLearnTransmogSet", function() return nil end)
    Set("C_Item.IsDressableItemByID", function(id) return Item(id) ~= nil and Item(id).appearance ~= nil end)
    Set("C_Item.IsItemBindToAccountUntilEquip", function() return false end)
    Set("C_Item.GetItemUniquenessByID", function() return false end)
    Set("C_Item.IsUsableItem", function() return true, false end)
    -- spell.hostile / spell.friendly: what the item's use has to be aimed at.
    Set("C_Item.IsHarmfulItem", function(reference)
        local item = Item(reference)
        return item ~= nil and item.spell ~= nil and item.spell.hostile == true
    end)
    Set("C_Item.IsHelpfulItem", function(reference)
        local item = Item(reference)
        return item ~= nil and item.spell ~= nil and item.spell.friendly == true
    end)
    Set("C_Item.GetFirstTriggeredSpellForItem", function() return nil end)
    Set("C_ArtifactUI.IsArtifactItem", function() return false end)
    Set("C_ToyBox.GetToyInfo", function() return nil end)
    Set("C_MountJournal.GetMountFromItem", function() return nil end)
    Set("C_PetJournal.GetPetInfoByItemID", function() return nil end)
    Set("C_Soulbinds.IsItemConduitByItemInfo", function() return false end)

    -- Tooltips: plain lines, a red one where the item says so. A line may have a right column
    -- (right, and rightRed for its colour). A requirement line (type 43) and a slot line (21)
    -- carry what the clients' recordings show on every one of them: `usable`, and
    -- `isValidInvSlot` / `isValidItemType`, false exactly where the column is red. A scenario
    -- gives a field itself to say otherwise, or bare = true for a line without them.
    local function IsRed(r, g, b)
        return r == 1 and g == 0.125 and b == 0.125
    end
    Set("C_TooltipInfo.GetHyperlink", function(link)
        local item = Item(link)
        if not item then
            return nil
        end
        local env = Client().env
        local lines = { { type = 0, leftText = item.name, leftColor = env.CreateColor(1, 1, 1, 1) } }
        for _, line in ipairs(item.tooltip or {}) do
            local made = {
                type = line.type or 0,
                leftText = line.text,
                leftColor = env.CreateColor(line.r or 1, line.g or 1, line.b or 1, 1),
                bonding = line.bonding,
                requirementType = line.requirementType,
            }
            if line.right ~= nil then
                made.rightText = line.right
                made.rightColor = line.rightRed and env.CreateColor(1, 0.125, 0.125, 1) or env.CreateColor(1, 1, 1, 1)
            end
            if not line.bare then
                local leftRed = IsRed(line.r, line.g, line.b)
                if made.type == 43 then
                    made.usable = not leftRed
                elseif made.type == 21 then
                    made.isValidInvSlot, made.isValidItemType = not leftRed, not line.rightRed
                end
            end
            for _, field in ipairs({ "usable", "isValidInvSlot", "isValidItemType", "spellID" }) do
                if line[field] ~= nil then
                    made[field] = line[field]
                end
            end
            lines[#lines + 1] = made
        end
        return { type = 0, id = ItemID(link), hyperlink = link, lines = lines }
    end)

    -- Appearances.
    local function BySource(sourceID)
        for id, item in pairs(items) do
            if item.appearance and item.appearance.sourceID == sourceID then
                return id, item
            end
        end
    end
    Set("C_TransmogCollection.GetItemInfo", function(reference)
        local item = Item(reference)
        if item and item.appearance then
            return item.appearance.appearanceID, item.appearance.sourceID
        end
    end)
    Set("C_TransmogCollection.GetSourceInfo", function(sourceID)
        local id, item = BySource(sourceID)
        if not item then
            return nil
        end
        local appearance = item.appearance
        return {
            sourceID = sourceID, visualID = appearance.appearanceID, itemID = id, name = item.name,
            isCollected = appearance.collected == true, isValidSourceForPlayer = appearance.valid ~= false,
            categoryID = appearance.category or 5, invType = 5, quality = item.quality, itemModID = 0,
            useErrorType = appearance.useError, playerCanCollect = appearance.canCollect ~= false,
        }
    end)
    Set("C_TransmogCollection.GetSourceItemID", function(sourceID) return (BySource(sourceID)) end)
    Set("C_TransmogCollection.GetAppearanceInfoBySource", function(sourceID)
        local _, item = BySource(sourceID)
        if item then
            return { appearanceID = item.appearance.appearanceID, appearanceIsCollected = item.appearance.collected == true,
                sourceIsCollected = item.appearance.collected == true }
        end
    end)
    Set("C_TransmogCollection.GetAllAppearanceSources", function(appearanceID)
        local sources = {}
        for _, item in pairs(items) do
            if item.appearance and item.appearance.appearanceID == appearanceID then
                sources[#sources + 1] = item.appearance.sourceID
            end
        end
        table.sort(sources)
        return sources
    end)
    Set("C_TransmogCollection.GetAppearanceSources", function() return nil end)
    Set("C_TransmogCollection.PlayerCanCollectSource", function(sourceID)
        local _, item = BySource(sourceID)
        return item ~= nil, item ~= nil and item.appearance.canCollect ~= false
    end)
    Set("C_TransmogCollection.AccountCanCollectSource", function(sourceID)
        local _, item = BySource(sourceID)
        return item ~= nil, item ~= nil and item.appearance.canCollect ~= false
    end)
    Set("C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance", function(sourceID)
        local _, item = BySource(sourceID)
        return item ~= nil and item.appearance.collected == true
    end)
    Set("C_TransmogCollection.PlayerHasTransmogByItemInfo", function(reference)
        local item = Item(reference)
        return item ~= nil and item.appearance ~= nil and item.appearance.collected == true
    end)
    Set("C_TransmogCollection.PlayerKnowsSource", function(sourceID)
        local _, item = BySource(sourceID)
        return item ~= nil and item.appearance.collected == true
    end)
    Set("C_TransmogSets.GetAllSourceIDs", function() return {} end)
    return game
end
