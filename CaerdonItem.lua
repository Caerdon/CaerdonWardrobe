local ADDON_NAME, NS = ...
local L = NS.L

CaerdonItem = {}
CaerdonItemMixin = {}

local version, build, date, tocversion = GetBuildInfo()
local isWarWithin = select(4, GetBuildInfo()) >= 110000
local ITEM_CLASS_HOUSING = (Enum.ItemClass and Enum.ItemClass.Housing) or nil

-- Should not be translated - used to provide me with screenshots for debugging.
CaerdonItemType = {
    Empty = "Empty",
    Unknown = "Unknown",
    Unhandled = "Unhandled",
    BattlePet = "Battle Pet",       -- pets that have been caged
    CompanionPet = "Companion Pet", -- unlearned pets
    Conduit = "Conduit",
    Consumable = "Consumable",
    Currency = "Currency",
    Equipment = "Equipment",
    Miscellaneous = "Miscellaneous",
    Mount = "Mount",
    Housing = "Housing",
    Profession = "Profession",
    Recipe = "Recipe",
    Quest = "Quest",
    Toy = "Toy"
}

CaerdonItemBind = {
    None = "None",
    BindOnAccount = "Bind on Account",
    BindOnPickup = "Bind on Pickup",
    BindOnEquip = "Bind on Equip",
    BindOnUse = "Bind on Use",
    QuestItem = "Quest Item",
    Unknown = "Unknown",
    WarboundUntilEquip = "Warbound until Equip"
}

-- Static lookup table for binding text in tooltip parsing (constant, avoids per-call recreation)
local bindTextTable = {
    [ITEM_ACCOUNTBOUND]        = L["BoA"],
    [ITEM_BNETACCOUNTBOUND]    = L["BoA"],
    [ITEM_BIND_TO_ACCOUNT]     = L["BoA"],
    [ITEM_BIND_TO_BNETACCOUNT] = L["BoA"]
}

-- Module-level cache for GetCaerdonStatus results, keyed by itemLink (+ bound state, and what
-- else GetCaerdonStatus adds to the key). An entry is { isReady, mogStatus, bindingStatus,
-- bindingResult, transmogInfo }: the transmog info of a piece of equipment is kept with the
-- verdict made from it, so drawing reads the same table and it is computed once per entry.
-- Invalidated by CaerdonItem:InvalidateStatusCache() on transmog/equipment events
local statusCache = {}

-- The statuses that give way to the quest icon in GetCaerdonStatus, beside an empty one.
local QUEST_REPLACES = {
    collected = true, sellable = true, send = true, oldexpansion = true,
    own = true, ownPlus = true, other = true, otherPlus = true, otherNoLoot = true,
    lowSkill = true, lowSkillPlus = true, transform = true,
}
local copySpellCache = {} -- item link -> combine facts of its use spell, see GetCopySpellFacts
local copySpellLoads = {} -- spell ID -> "asked" or "answered": its data was asked for this session
function CaerdonItem:InvalidateStatusCache()
    wipe(statusCache)
    wipe(copySpellCache)
end

-- Whether the copy of an item in a bag slot is locked (a lockbox that has not been opened).
-- The lock belongs to the copy, so it is read from the slot's own tooltip: the tooltip of the
-- bare link cannot know whether this box has been unlocked. The text is compared on every
-- line, because which line type carries it is not the same in every client build.
-- Returns nil when the slot's tooltip cannot be read yet.
local function IsBagSlotLocked(bag, slot)
    local data = C_TooltipInfo and C_TooltipInfo.GetBagItem(bag, slot)
    if not data or not data.lines then
        return nil
    end
    for _, line in ipairs(data.lines) do
        local text = line.leftText and tostring(line.leftText) or nil
        if text == RETRIEVING_ITEM_INFO then
            return nil
        elseif text == LOCKED then
            return true
        end
    end
    return false
end

-- Reusable table for GetTooltipData output to avoid per-call allocation.
-- Safe because GetTooltipData is only called synchronously within GetCaerdonStatus.
-- ITEM_MIN_SKILL ("Requires %s (%d)") as a pattern that captures the skill's name and the rank.
-- Made at the first skill requirement line, since the locale's strings are there by then.
local skillRequirementPattern
local function SkillRequirementPattern()
    if not skillRequirementPattern then
        -- Remove 1$ and 2$ from ITEM_MIN_SKILL for German at least (probably all): Benötigt %1$s (%2$d)
        local skillCheck = string.gsub(ITEM_MIN_SKILL, "1%$", "")
        skillCheck = string.gsub(skillCheck, "2%$", "")
        skillCheck = string.gsub(skillCheck, "%%s", "%(.+%)")
        if GetLocale() == "zhCN" then
            skillCheck = string.gsub(skillCheck, "（%%d）", "（%(%%d+%)）")
        else
            skillCheck = string.gsub(skillCheck, "%(%%d%)", "%%%(%(%%d+%)%%%)")
        end
        skillRequirementPattern = skillCheck
    end
    return skillRequirementPattern
end

-- An "Equip:" line that is a plain stat, not an effect. WoW Forever writes what classic gear
-- gives beyond the primary stats (spell power, attack power, crit, mana per 5 sec) as green
-- "Equip:" lines. It builds them from its own TOOLTIP_ITEM_STAT_* strings and hands them out
-- as type None, while an effect that is a spell (a quiver's attack speed) comes as
-- ItemSpellTriggerOnEquip with a spell ID. A stat is weighed like any other stat (item level,
-- Pawn) and is no reason to keep a piece; an effect is.
--   * Skill bonuses (TOOLTIP_ITEM_STAT_SKILL_*, "Increased Fishing +3") are left out on
--     purpose: they stay an effect.
--   * A line is only a stat when it matches one of these strings in full, so a family the
--     list lacks, and every "Equip:" line of a client without the strings (retail), stays an
--     effect.
--   * The names are built here, which the static check cannot see: the recorder gets them
--     from CaerdonItem:GetEquipStatStringNames().
local EQUIP_STAT_PREFIX = "TOOLTIP_ITEM_STAT_"
local EQUIP_STAT_FAMILIES = {
    "ATTACK_POWER", "RANGED_ATTACK_POWER", "WEAPON_DAMAGE", "ARMOR_PENETRATION",
    "CRIT_PERCENT", "HIT_PERCENT", "HASTE_PCT", "EXPERTISE_PCT",
    "DEFENSE", "DODGE_PCT", "PARRY_PCT", "BLOCK_CHANCE", "BLOCK_VALUE",
    "HEALTH_REGEN", "MANA_REGEN",
    "SPELL_POWER", "SPELL_DAMAGE", "SPELL_HEALING", "SPELL_PENETRATION",
    "ARCANE_DAMAGE", "FIRE_DAMAGE", "FROST_DAMAGE", "HOLY_DAMAGE", "NATURE_DAMAGE", "SHADOW_DAMAGE",
    "ARCANE_PENETRATION", "FIRE_PENETRATION", "FROST_PENETRATION", "NATURE_PENETRATION", "SHADOW_PENETRATION",
}
-- Attack power and spell damage against one kind of creature: AP_VS_BEAST, SD_VS_UNDEAD.
local EQUIP_STAT_CREATURES = { "BEAST", "DEMON", "DRAGONKIN", "ELEMENTAL", "GIANT", "HUMANOID", "MECHANICAL", "UNDEAD" }
-- Healing and damage in one line, each with its own direction.
local EQUIP_STAT_OTHERS = {
    "SPELL_HEALING_INCREASE_DAMAGE_INCREASE", "SPELL_HEALING_INCREASE_DAMAGE_DECREASE",
    "SPELL_HEALING_DECREASE_DAMAGE_INCREASE", "SPELL_HEALING_DECREASE_DAMAGE_DECREASE",
}

local equipStatStringNames
function CaerdonItem:GetEquipStatStringNames()
    if not equipStatStringNames then
        local names = {}
        local function AddFamily(family)
            names[#names + 1] = EQUIP_STAT_PREFIX .. family .. "_INCREASE"
            names[#names + 1] = EQUIP_STAT_PREFIX .. family .. "_DECREASE"
        end
        for _, family in ipairs(EQUIP_STAT_FAMILIES) do
            AddFamily(family)
        end
        for _, creature in ipairs(EQUIP_STAT_CREATURES) do
            AddFamily("AP_VS_" .. creature)
            AddFamily("SD_VS_" .. creature)
        end
        for _, name in ipairs(EQUIP_STAT_OTHERS) do
            names[#names + 1] = EQUIP_STAT_PREFIX .. name
        end
        equipStatStringNames = names
    end
    return equipStatStringNames
end

-- "Equip: Improves your chance to hit by %1$.1f%%." as a pattern for the whole line. A number
-- is matched loosely (digits and separators), since how a locale writes one is not known.
local function EquipStatPattern(format)
    local pattern = format:gsub("%%%%", "\2"):gsub("%%[%d%$%.]*%a", "\1")
    pattern = pattern:gsub("%p", "%%%0"):gsub("\1", "[%%d%%.,]+"):gsub("\2", "%%%%")
    return "^" .. pattern .. "$"
end

local equipStatPatterns
local equipStatLines = {} -- line text -> whether it is a stat line; a tooltip's lines repeat
local function IsEquipStatLine(lineText)
    local isStat = equipStatLines[lineText]
    if isStat == nil then
        if not equipStatPatterns then
            equipStatPatterns = {}
            for _, name in ipairs(CaerdonItem:GetEquipStatStringNames()) do
                local format = _G[name]
                if type(format) == "string" then
                    equipStatPatterns[#equipStatPatterns + 1] = EquipStatPattern(format)
                end
            end
        end
        isStat = false
        for index = 1, #equipStatPatterns do
            if strfind(lineText, equipStatPatterns[index]) then
                isStat = true
                break
            end
        end
        equipStatLines[lineText] = isStat
    end
    return isStat
end

local recycledTooltipData = {}
local function ResetTooltipData(embeddedLink)
    local t = recycledTooltipData
    t.canLearn = false
    t.canCombine = false
    t.hasEquipEffect = false
    t.hasEquipEffectBeyondStats = false
    t.isRelearn = false
    t.bindingStatus = nil
    t.isRetrieving = false
    t.isSoulbound = false
    t.isKnownSpell = false
    t.isLocked = false
    t.isOpenable = false
    t.supercedingSpellNotKnown = false
    t.foundRedRequirements = false
    t.requiredTradeSkillMissingOrUnleveled = false
    t.requiredTradeSkillTooLow = false
    t.raceClassRestricted = false
    t.skillRequirementMet = false
    t.hasSkillRequirement = false
    t.upgradeLevelDisabled = false
    t.embeddedLink = embeddedLink
    return t
end

local function EnsureProfessionsFrameLoaded()
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Professions"))
        or (IsAddOnLoaded and IsAddOnLoaded("Blizzard_Professions"))
    if (not isLoaded) and ProfessionsFrame_LoadUI then
        ProfessionsFrame_LoadUI()
    end
end

-- An item finds its methods through its metatable: CaerdonItemMixin first, then Blizzard's
-- ItemMixin. Every window makes a new item per button and request, and copying both mixins
-- into each one (CreateFromMixins) was 76 fields a time. The lookup is live: a method added to
-- or replaced on CaerdonItemMixin later (the signal modules' entry points, the counters'
-- wrappers) is there for every item, made before or after. An item's own table holds only
-- its data.
setmetatable(CaerdonItemMixin, { __index = ItemMixin })
local itemMetatable = { __index = CaerdonItemMixin }

local function CreateItem()
    return setmetatable({ customDataLoaded = false }, itemMetatable)
end

--[[static]]
function CaerdonItem:CreateFromItemLink(itemLink, extraData)
    if type(itemLink) ~= "string" then
        error("Usage: CaerdonItem:CreateFromItemLink(itemLinkString)", 2);
    end

    local item = CreateItem()
    item:SetItemLink(itemLink)
    item.extraData = extraData

    return item;
end

--[[static]]
function CaerdonItem:CreateFromItemID(itemIDCheck)
    local itemID = tonumber(itemIDCheck)
    if type(itemID) ~= "number" then
        error("Usage: CaerdonItem:CreateFromItemID(itemID)", 2);
    end

    local item = CreateItem()
    item:SetItemID(itemID)
    return item;
end

--[[static]]
function CaerdonItem:CreateFromItemLocation(itemLocation)
    if type(itemLocation) ~= "table" or type(itemLocation.HasAnyLocation) ~= "function" or not itemLocation:HasAnyLocation() then
        error("Usage: Item:CreateFromItemLocation(notEmptyItemLocation)", 2);
    end
    local item = CreateItem()
    item:SetItemLocation(itemLocation);
    return item;
end

--[[static]]
function CaerdonItem:CreateFromBagAndSlot(bagID, slotIndex)
    if type(bagID) ~= "number" or type(slotIndex) ~= "number" then
        error("Usage: Item:CreateFromBagAndSlot(bagID, slotIndex)", 2);
    end
    local item = CreateItem()
    item:SetItemLocation(ItemLocation:CreateFromBagAndSlot(bagID, slotIndex));
    return item;
end

--[[static]]
function CaerdonItem:CreateFromEquipmentSlot(equipmentSlotIndex)
    if type(equipmentSlotIndex) ~= "number" then
        error("Usage: Item:CreateFromEquipmentSlot(equipmentSlotIndex)", 2);
    end
    local item = CreateItem()
    item:SetItemLocation(ItemLocation:CreateFromEquipmentSlot(equipmentSlotIndex));
    return item;
end

--[[static]]
function CaerdonItem:CreateFromSpeciesInfo(speciesID, level, quality, health, power, speed, customName, petID)
    -- TODO: This is a terrible hack until Blizzard gives me more to work with (mostly for tooltips where I don't have an itemLink).
    if type(speciesID) ~= "number" then
        error(
            "Usage: CaerdonItem:CreateFromSpeciesInfo(speciesID, level, quality, health, power, speed, customName, petID)",
            2);
    end

    local name, _, _, _, _, _, _, _, _, _, _, displayID = C_PetJournal.GetPetInfoBySpeciesID(speciesID);
    local itemLink = format("|cff0070dd|Hbattlepet:%d:%d:%d:%d:%d:%d:%x:%d|h[%s]|h|r", speciesID, level, quality, health,
        power, speed, petID or 0, displayID, customName or name)
    return CaerdonItem:CreateFromItemLink(itemLink)
end

--[[static]]
function CaerdonItem:CreateFromItemGUID(itemGUID)
    if type(itemGUID) ~= "string" then
        error("Usage: CaerdonItem:CreateFromItemGUID(itemGUIDString)", 2);
    end

    local item = CreateItem();
    item:SetItemGUID(itemGUID);
    return item;
end

function CaerdonItemMixin:Clear()
    ItemMixin.Clear(self)
    self.caerdonItemType = nil
    self.caerdonItemData = nil
    self.customDataLoaded = false
end

function CaerdonItemMixin:IsItemDataCached() -- Checks for both item and any custom data
    return self:IsItemCached() and self.customDataLoaded;
end

function CaerdonItemMixin:IsItemCached()
    local isItemCached = true

    if self:GetStaticBackingItem() then
        isItemCached = C_Item.IsItemDataCachedByID(self:GetStaticBackingItem());
    end

    if not isItemCached and not self:IsItemEmpty() then
        if self:HasItemLocation() then
            isItemCached = C_Item.IsItemDataCached(self:GetItemLocation());
        else
            isItemCached = false
        end
    end

    -- print("Item ID: " .. self:GetItemID() .. " IsItemCached: " .. tostring(isItemCached))
    return isItemCached;
end

-- Add a callback to be executed when item data is loaded, if the item data is already loaded then execute it immediately
function CaerdonItemMixin:ContinueOnItemLoad(callbackFunction)
    if type(callbackFunction) ~= "function" then
        error("Usage: ContinueOnLoad(callbackFunction)", 2);
    end

    local function ProcessTheItem()
        -- TODO: Update things and delay callback if needed for tooltip data
        -- Make sure any dependent data is loaded
        local itemData = self:GetItemData()

        -- Allows for override of continue return if additional data needs to get loaded from a specific mixin (i.e. equipment sources)
        if itemData then
            itemData:ContinueOnItemDataLoad(GenerateClosure(function()
                self.customDataLoaded = true
                callbackFunction()
            end))
        else
            self.customDataLoaded = true
            callbackFunction()
        end
    end

    local function FailTheItem()
        self.customDataLoaded = false
        -- TODO: Should I provide an errorCallback in this case?
        if CaerdonWardrobeConfig and CaerdonWardrobeConfig.Debug and CaerdonWardrobeConfig.Debug.Enabled then print("ITEM LOAD FAILED: " .. self:GetItemID()) end
        callbackFunction()
    end

    if not self:IsItemCached() then
        if not self:IsItemEmpty() then
            CaerdonItemEventListener:AddCallback(self:GetItemID(), GenerateClosure(ProcessTheItem), FailTheItem)
        elseif self:GetCaerdonItemType() == CaerdonItemType.Quest then
            local linkType, linkOptions, name = LinkUtil.ExtractLink(self:GetItemLink());
            local questID = tonumber(strsplit(":", linkOptions), 10)
            -- If quest data is already cached, process directly. AddCallback calls
            -- RequestLoadQuestByID which fires QUEST_DATA_LOAD_RESULT synchronously
            -- for cached quests, running Blizzard's own QuestEventListener callbacks
            -- under addon taint.
            if HaveQuestData and HaveQuestData(questID) then
                ProcessTheItem()
            else
                CaerdonQuestEventListener:AddCallback(questID, GenerateClosure(ProcessTheItem), FailTheItem)
            end
        else
            -- Item is empty and not cached - nothing to load, just call callback
            self.customDataLoaded = true
            callbackFunction()
        end
    else
        ProcessTheItem()
    end
end

-- Same as ContinueOnItemLoad, except it returns a function that when called will cancel the continue
function CaerdonItemMixin:ContinueWithCancelOnItemLoad(callbackFunction)
    if type(callbackFunction) ~= "function" then
        error("Usage: ContinueWithCancelOnItemLoad(callbackFunction)", 2);
    end

    -- Callers (Blizzard's ContinuableContainer in particular) expect exactly one
    -- completion per registration. CaerdonEquipmentMixin:LoadSources deliberately
    -- reports completion immediately and then again once its source items arrive
    -- (see the `#waitingForItems` note in CLAUDE.md). Collapse that into a single
    -- call: a late duplicate decrements a container that has already fired and
    -- cleared its state, which crashes in ContinuableContainer:CheckIfSatisfied.
    -- This shows up readily on a fresh client cache such as a new WoW Forever install.
    local originalCallback = callbackFunction
    local completed = false
    callbackFunction = function(...)
        if completed then
            return
        end
        completed = true
        return originalCallback(...)
    end

    if not self:IsItemEmpty() then
        -- If WoW item data is already cached, process directly instead of going
        -- through the event listener. AddCancelableCallback calls
        -- RequestLoadItemDataByID which can fire ITEM_DATA_LOAD_RESULT
        -- synchronously for cached items, tainting Blizzard's event handlers.
        if self:IsItemCached() then
            local itemDataCancel
            local itemData = self:GetItemData()
            if itemData then
                itemDataCancel = itemData:ContinueWithCancelOnItemDataLoad(function()
                    self.customDataLoaded = true
                    callbackFunction()
                end)
            else
                self.customDataLoaded = true
                callbackFunction()
            end
            return function()
                if type(itemDataCancel) == "function" then
                    itemDataCancel()
                end
            end
        end

        local itemDataCancel
        local itemCancel = CaerdonItemEventListener:AddCancelableCallback(self:GetItemID(), function()
            -- TODO: Update things and delay callback if needed for tooltip data
            local itemData = self:GetItemData()
            if itemData then
                itemDataCancel = itemData:ContinueWithCancelOnItemDataLoad(function()
                    self.customDataLoaded = true
                    callbackFunction()
                end)
            else
                self.customDataLoaded = true
                callbackFunction()
            end
        end, function()
            self.customDataLoaded = false
            -- TODO: Should I provide an errorCallback in this case?
            if CaerdonWardrobeConfig and CaerdonWardrobeConfig.Debug and CaerdonWardrobeConfig.Debug.Enabled then print("ITEM LOAD FAILED: " .. self:GetItemID()) end
            callbackFunction()
        end);

        return function()
            if type(itemDataCancel) == "function" then
                itemDataCancel()
            end

            itemCancel()
        end;
    elseif self:GetCaerdonItemType() == CaerdonItemType.Quest then
        local linkType, linkOptions, name = LinkUtil.ExtractLink(self:GetItemLink());
        local questID = tonumber(strsplit(":", linkOptions), 10);

        -- Same as the item path above: skip the listener when quest data is already
        -- cached so RequestLoadQuestByID doesn't fire QUEST_DATA_LOAD_RESULT
        -- synchronously under addon taint.
        if HaveQuestData and HaveQuestData(questID) then
            local itemDataCancel
            local itemData = self:GetItemData()
            if itemData then
                itemDataCancel = itemData:ContinueWithCancelOnItemDataLoad(function()
                    self.customDataLoaded = true
                    callbackFunction()
                end)
            else
                self.customDataLoaded = true
                callbackFunction()
            end
            return function()
                if type(itemDataCancel) == "function" then
                    itemDataCancel()
                end
            end
        end

        local itemDataCancel
        local itemCancel = CaerdonQuestEventListener:AddCancelableCallback(questID, function()
            -- TODO: Update things and delay callback if needed for tooltip data
            local itemData = self:GetItemData()
            if itemData then
                itemDataCancel = itemData:ContinueWithCancelOnItemDataLoad(function()
                    self.customDataLoaded = true
                    callbackFunction()
                end)
            else
                self.customDataLoaded = true
                callbackFunction()
            end
        end, function()
            self.customDataLoaded = false
            -- TODO: Should I provide an errorCallback in this case?
            if CaerdonWardrobeConfig and CaerdonWardrobeConfig.Debug and CaerdonWardrobeConfig.Debug.Enabled then print("QUEST ITEM LOAD FAILED: " .. self:GetItemID()) end
            callbackFunction()
        end);

        return function()
            if type(itemDataCancel) == "function" then
                itemDataCancel()
            end

            itemCancel()
        end;
    else
        self.customDataLoaded = true
        callbackFunction()
        return function() end
    end
end

function CaerdonItemMixin:SetItemLink(itemLink)
    ItemMixin.SetItemLink(self, itemLink)
    self.cachedTeleportUse = nil
    self.cachedIsRecraftable = nil
end

function CaerdonItemMixin:SetItemID(itemID)
    -- Used for embedded item tooltip rewards
    ItemMixin.SetItemID(self, itemID)
    self.cachedTeleportUse = nil
    self.cachedIsRecraftable = nil
end

function CaerdonItemMixin:SetItemLocation(itemLocation)
    ItemMixin.SetItemLocation(self, itemLocation)
    self.cachedTeleportUse = nil
    self.cachedIsRecraftable = nil
end

-- local itemID, itemType, itemSubType, itemEquipLoc, icon, itemTypeID, itemSubClassID = C_Item.GetItemInfoInstant(self:GetStaticBackingItem())

-- TODO: Find lint rule - always need parens around select to reduce to single value
function CaerdonItemMixin:GetItemType()
    if not self:IsItemEmpty() then
        return (select(2, C_Item.GetItemInfoInstant(self:GetItemID())))
    end
end

function CaerdonItemMixin:GetItemSubType()
    if not self:IsItemEmpty() then
        return (select(3, C_Item.GetItemInfoInstant(self:GetItemID())))
    end
end

function CaerdonItemMixin:GetEquipLocation()
    if not self:IsItemEmpty() then
        local equipLocation = (select(4, C_Item.GetItemInfoInstant(self:GetItemID())))
        if equipLocation == "" then
            return nil
        end
        return equipLocation
    end

    return nil
end

function CaerdonItemMixin:GetItemTypeID()
    if not self:IsItemEmpty() then
        return (select(6, C_Item.GetItemInfoInstant(self:GetItemID())))
    end
end

function CaerdonItemMixin:GetItemSubTypeID()
    if not self:IsItemEmpty() then
        return (select(7, C_Item.GetItemInfoInstant(self:GetItemID())))
    end
end

function CaerdonItemMixin:GetHasUse() -- requires item data to be loaded
    if not self:IsItemEmpty() then
        local spellName, spellID = C_Item.GetItemSpell(self:GetItemID())
        return spellID ~= nil
    end
end

local teleportKeywords = {
    string.lower(L["teleport"]),
    string.lower(L["portal"]),
    string.lower(L["waygate"]),
    string.lower(L["waystone"]),
    string.lower(L["gateway"])
}

local function MatchesTeleportKeyword(text)
    if not text or text == "" then
        return false
    end

    local lowerText = string.lower(text)
    for _, keyword in ipairs(teleportKeywords) do
        if keyword ~= "" and string.find(lowerText, keyword, 1, true) then
            return true
        end
    end

    return false
end

-- The item's use has to be aimed at an enemy: the client's own answer, the one it takes to
-- colour an action button out of range. Such a use is a combat effect (Torch of Holy Flame
-- 7344, "Decrease the armor of target by 50"), while what is fun or special about an item is
-- mostly cast on oneself, on a friend or on nothing at all.
function CaerdonItemMixin:HasHostileUse() -- requires item data to be loaded
    if self:IsItemEmpty() or not self:GetHasUse() then
        return false
    end
    return C_Item.IsHarmfulItem(self:GetItemID()) == true
end

function CaerdonItemMixin:HasTeleportUse()
    if self.cachedTeleportUse ~= nil then
        return self.cachedTeleportUse
    end

    self.cachedTeleportUse = false
    if not self:GetHasUse() or self:IsItemEmpty() then
        return false
    end

    local spellName, spellID = C_Item.GetItemSpell(self:GetItemID())
    if MatchesTeleportKeyword(spellName) then
        self.cachedTeleportUse = true
        return true
    end

    if spellID then
        local description = C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(spellID)
        if MatchesTeleportKeyword(description) then
            self.cachedTeleportUse = true
        end
    end

    return self.cachedTeleportUse
end

function CaerdonItemMixin:IsRecraftable()
    if self.cachedIsRecraftable ~= nil then
        return self.cachedIsRecraftable
    end

    self.cachedIsRecraftable = false

    if not (C_TradeSkillUI and C_TradeSkillUI.GetOriginalCraftRecipeID) then
        return false
    end

    EnsureProfessionsFrameLoaded()

    local itemLocation = self:GetItemLocation()
    if not (itemLocation and itemLocation:IsValid() and C_Item and C_Item.DoesItemExist(itemLocation)) then
        return false
    end

    local itemGUID = C_Item.GetItemGUID and C_Item.GetItemGUID(itemLocation)
    if not itemGUID then
        return false
    end

    local recipeID = select(1, C_TradeSkillUI.GetOriginalCraftRecipeID(itemGUID))
    if recipeID then
        self.cachedIsRecraftable = true
        return true
    end

    return false
end

-- local itemName, itemLinkInfo, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
-- itemEquipLoc, iconFileDataID, itemSellPrice, itemTypeID, itemSubTypeID, bindType, expacID, itemSetID,
-- isCraftingReagent = C_Item.GetItemInfo(self:GetItemLink())
function CaerdonItemMixin:GetMinLevel() -- requires item data to be loaded
    if not self:IsItemEmpty() then
        return (select(5, C_Item.GetItemInfo(self:GetItemLink())))
    end
end

function CaerdonItemMixin:GetBinding() -- requires item data to be loaded
    local caerdonType = self:GetCaerdonItemType()
    local binding = CaerdonItemBind.Unknown

    if not self:IsItemEmpty() then
        local bindType = (select(14, C_Item.GetItemInfo(self:GetItemLink())))
        if bindType == 0 then
            binding = CaerdonItemBind.None
        elseif bindType == 1 then        -- BoP
            binding = CaerdonItemBind.BindOnPickup
        elseif bindType == 2 then        -- BoE
            local isWarboundUntilEquip = C_Item.IsItemBindToAccountUntilEquip(self:GetItemLink())
            if isWarboundUntilEquip then -- WuE
                if caerdonType == CaerdonItemType.Currency then
                    binding = CaerdonItemBind.None
                else
                    binding = CaerdonItemBind.WarboundUntilEquip
                end
            else
                binding = CaerdonItemBind.BindOnEquip
            end
        elseif bindType == 3 then -- BoU
            binding = CaerdonItemBind.BindOnUse
        elseif bindType == 4 then -- Quest
            binding = CaerdonItemBind.QuestItem
        elseif bindType == 7 then -- Enum.ItemBind.ToWoWAccount
            binding = CaerdonItemBind.BindOnAccount
        elseif bindType == 8 then -- BoA, apparently
            -- TODO: This was working... and then seemingly not... keep an eye out.
            binding = CaerdonItemBind.BindOnAccount
        elseif bindType == 9 then -- WuE
            binding = CaerdonItemBind.WarboundUntilEquip
        elseif bindType ~= nil then
            print("Caerdon: " .. self:GetItemLink() .. ": Please report - Unknown binding type " .. tostring(bindType))
        end
    else
        binding = CaerdonItemBind.None
    end

    return binding
end

function CaerdonItemMixin:HasItemLocationBankOrBags()
    local itemLocation = self:GetItemLocation()
    if itemLocation and itemLocation:IsBagAndSlot() then
        return true
    else
        return false
    end
end

function CaerdonItemMixin:IsSoulbound()
    if self:IsItemInPlayersControl() then
        return C_Item.IsBound(self:GetItemLocation())
    else
        return false
    end
end

function CaerdonItemMixin:GetExpansionID() -- requires item data to be loaded
    if not self:IsItemEmpty() then
        return (select(15, C_Item.GetItemInfo(self:GetItemLink())))
    end
end

function CaerdonItemMixin:GetSetID()
    if not self:IsItemEmpty() then
        return (select(16, C_Item.GetItemInfo(self:GetItemLink())))
    end
end

function CaerdonItemMixin:GetIsCraftingReagent() -- requires item data to be loaded
    if not self:IsItemEmpty() then
        return (select(17, C_Item.GetItemInfo(self:GetItemLink())))
    else
        return false
    end
end

local function IsUnhandledType(typeID, subTypeID)
    return typeID == Enum.ItemClass.Container or
        typeID == Enum.ItemClass.Gem or
        typeID == Enum.ItemClass.Reagent or
        typeID == Enum.ItemClass.Projectile or
        typeID == Enum.ItemClass.Tradegoods or
        typeID == Enum.ItemClass.ItemEnhancement or
        typeID == Enum.ItemClass.Quiver or
        typeID == Enum.ItemClass.Key or
        typeID == Enum.ItemClass.Glyph or
        typeID == Enum.ItemClass.WoWToken or
        typeID == nil
end

function CaerdonItemMixin:GetCaerdonItemType()
    local itemLink = self:GetItemLink()
    if not itemLink then
        return CaerdonItemType.Empty
    end

    -- TODO: Keep an eye on this - caching type now that I'm handling ItemLocation may not be a good idea
    -- if I want to support swapping the item out
    if not self.caerdonItemType then
        local caerdonType = CaerdonItemType.Unknown
        local tempLink = itemLink:gsub(" |A:.*|a]", "]") -- TODO: Temp hack to remove quality from link that breaks ExtractLink

        local linkType, linkOptions, displayText = LinkUtil.ExtractLink(tempLink)
        local typeID = self:GetItemTypeID()
        local subTypeID = self:GetItemSubTypeID()

        local toylink = typeID and C_ToyBox.GetToyLink(self:GetItemID())
        local isConduit = C_Soulbinds.IsItemConduitByItemInfo(itemLink)

        if toylink then
            caerdonType = CaerdonItemType.Toy
        elseif isConduit then
            caerdonType = CaerdonItemType.Conduit
        elseif linkType == "battlepet" then
            caerdonType = CaerdonItemType.BattlePet
        elseif linkType == "quest" then
            caerdonType = CaerdonItemType.Quest
        elseif linkType == "currency" then
            caerdonType = CaerdonItemType.Currency
        elseif linkType == "mount" then
            caerdonType = CaerdonItemType.Mount
        elseif linkType == "item" or linkType == nil then -- Assuming item if we don't have a linkType
            -- TODO: Switching to just checking type for equipment
            -- instead of using GetEquipLocation (since containers are equippable)
            -- Keep an eye on this
            if IsUnhandledType(typeID, subTypeID) then
                caerdonType = CaerdonItemType.Unhandled
            elseif typeID == Enum.ItemClass.Armor or typeID == Enum.ItemClass.Weapon then
                caerdonType = CaerdonItemType.Equipment
            elseif typeID == Enum.ItemClass.Battlepet then
                caerdonType = CaerdonItemType.BattlePet
            elseif typeID == Enum.ItemClass.Consumable then
                -- Some recipes (e.g. Engineering schematics) have itemClassID=0
                -- (Consumable) instead of 9 (Recipe). Detect them by name prefix.
                local itemName = self:GetItemName()
                if itemName and (
                    strmatch(itemName, "^Recipe: ") or
                    strmatch(itemName, "^Schematic: ") or
                    strmatch(itemName, "^Design: ") or
                    strmatch(itemName, "^Plans: ") or
                    strmatch(itemName, "^Pattern: ") or
                    strmatch(itemName, "^Technique: ") or
                    strmatch(itemName, "^Formula: ")
                ) then
                    caerdonType = CaerdonItemType.Recipe
                else
                    caerdonType = CaerdonItemType.Consumable
                end
            elseif typeID == Enum.ItemClass.Miscellaneous then
                if subTypeID == Enum.ItemMiscellaneousSubclass.CompanionPet then
                    local name, icon, petType, creatureID, sourceText, description, isWild, canBattle, isTradeable, isUnique, isObtainable, displayID, speciesID =
                        C_PetJournal.GetPetInfoByItemID(self:GetItemID());
                    if creatureID and displayID then
                        caerdonType = CaerdonItemType.CompanionPet
                    else
                        caerdonType = CaerdonItemType.Unhandled
                    end
                elseif subTypeID == Enum.ItemMiscellaneousSubclass.Mount or subTypeID == Enum.ItemMiscellaneousSubclass.MountEquipment then
                    caerdonType = CaerdonItemType.Mount
                elseif subTypeID == Enum.ItemMiscellaneousSubclass.Other then
                    caerdonType = CaerdonItemType.Miscellaneous
                else
                    caerdonType = CaerdonItemType.Unhandled
                end
            elseif typeID == Enum.ItemClass.Questitem then
                caerdonType = CaerdonItemType.Quest
            elseif typeID == Enum.ItemClass.Recipe then
                caerdonType = CaerdonItemType.Recipe
            elseif typeID == Enum.ItemClass.Profession then
                caerdonType = CaerdonItemType.Profession
            elseif ITEM_CLASS_HOUSING and typeID == ITEM_CLASS_HOUSING then
                caerdonType = CaerdonItemType.Housing
            else
                print("Caerdon: Unknown item type " ..
                    tostring(typeID) .. ", " .. tostring(linkType) .. " (unknown): " .. itemLink)
            end
        elseif linkType == "achievement" then
            caerdonType = CaerdonItemType.Unhandled
        elseif linkType == "journal" then
            caerdonType = CaerdonItemType.Unhandled
        elseif linkType == "keystone" then
            caerdonType = CaerdonItemType.Unhandled
        elseif linkType == "spell" then
            caerdonType = CaerdonItemType.Unhandled
        else
            print("Caerdon: Unknown type " ..
                tostring(typeID) .. ", " .. tostring(linkType) .. " (unknown): " .. itemLink)
        end

        self.caerdonItemType = caerdonType
    end

    return self.caerdonItemType
end

function CaerdonItemMixin:GetTooltipData(data)
    if not data then
        data = C_TooltipInfo and C_TooltipInfo.GetHyperlink(self:GetItemLink()) or nil
    end

    if not data then return ResetTooltipData(nil) end

    -- bindTextTable is now module-level (constant)
    -- tooltipData is recycled to avoid per-call allocation
    local tooltipData = ResetTooltipData(data.hyperlink)

    -- TODO: Hack to handle Pet Cage - need to move down into BattlePetMixin and get CaerdonItem to handle it upfront if needed.
    local isBattlePet = self:GetCaerdonItemType() == CaerdonItemType.BattlePet
    if isBattlePet then
        if data.battlePetSpeciesID then
            -- local item = CaerdonItem:CreateFromSpeciesInfo(data.battlePetSpeciesID, data.battlePetLevel, data.battlePetBreedQuality, data.battlePetMaxHealth, data.battlePetPower, data.battlePetSpeed, data.battlePetName, battlePetID)
            local numCollected = C_PetJournal.GetNumCollectedInfo(data.battlePetSpeciesID)
            if numCollected == 0 then
                tooltipData.canLearn = true
            end
        end
    end

    local itemSpellName, itemSpellID = C_Item.GetItemSpell(self:GetItemLink())
    local isStudyItem = itemSpellName ==
        L
        ["Studying"] -- A bunch of these so working off name for now: itemSpellID == 450824 or itemSpellID == 462909 --Spell: "Studying"
    local isRecipe = self:GetCaerdonItemType() == CaerdonItemType.Recipe
    local isMiscellaneousStudy = self:GetCaerdonItemType() == CaerdonItemType.Miscellaneous and isStudyItem
    local lines = data.lines or {}

    for lineIndex, line in ipairs(data.lines) do
        local lineText = line.leftText and tostring(line.leftText) or nil

        -- The client has no tooltip for the item yet. Asked of every line, before anything is read
        -- from one: the line's type is not the same in every build (an ErrorLine in retail 12.1.5,
        -- which the text checks below never see), and it is red, which would read as a requirement
        -- the toon does not meet.
        if lineText == RETRIEVING_ITEM_INFO then
            tooltipData.isRetrieving = true
            break
        end

        -- Red text (RED_FONT_COLOR, "ffff2020") on any line marks a requirement this toon does not
        -- meet right now: level (UsageRequirement), armor/weapon proficiency (the RIGHT column of the
        -- EquipSlot line, e.g. "Wrist | Mail" on a hunter below 40 on WoW Forever), class, skill,
        -- reputation, "Already known". Those lines are not type None, so scan every line and both
        -- columns here rather than inside the type-filtered branch below.
        -- TODO: Provide option to show stars on BoE recipes that aren't for current toon
        local leftHex = line.leftColor and line.leftColor.GenerateHexColor and line.leftColor:GenerateHexColor()
        local rightHex = line.rightColor and line.rightColor.GenerateHexColor and line.rightColor:GenerateHexColor()
        if leftHex == "ffff2020" or rightHex == "ffff2020" then
            tooltipData.foundRedRequirements = true
        end
        -- Since 12.0 the "Use:" / "Equip:" / "Use: Teaches you" lines carry their own
        -- types instead of None, so they must be included here or the text checks
        -- below (equip effects, re-learn, reputation, customization unlocks) never run.
        -- The ItemSpellTrigger* enum entries are nil on 11.x clients, which is harmless.
        if line.type == Enum.TooltipDataLineType.None or
            line.type == Enum.TooltipDataLineType.ItemEnchantmentPermanent or
            line.type == Enum.TooltipDataLineType.ItemBinding or
            line.type == Enum.TooltipDataLineType.ItemSpellTriggerLearn or
            line.type == Enum.TooltipDataLineType.ItemSpellTriggerOnUse or
            line.type == Enum.TooltipDataLineType.ItemSpellTriggerOnEquip then
            if line.type == Enum.TooltipDataLineType.ItemSpellTriggerOnEquip then
                tooltipData.hasEquipEffect = true
                tooltipData.hasEquipEffectBeyondStats = true
            end

            if lineText then
                -- Text fallback for clients that don't type the equip line
                if strmatch(lineText, ITEM_SPELL_TRIGGER_ONEQUIP) then -- it has an equip effect
                    tooltipData.hasEquipEffect = true
                    -- Only an untyped line can be a plain stat (see IsEquipStatLine).
                    if line.type ~= Enum.TooltipDataLineType.None or not IsEquipStatLine(lineText) then
                        tooltipData.hasEquipEffectBeyondStats = true
                    end
                end

                -- NOTE: I had removed the check for isRecipe for some reason... but then things like Reaves would get flagged as canLearn.
                -- Keep an eye out and figure out what to do if needed
                if isRecipe or isMiscellaneousStudy then
                    -- TODO: Don't like matching this hard-coded string but not sure how else
                    -- to prevent the expensive books from showing as learnable when I don't
                    -- know how to tell if they have recipes you need.
                    if strmatch(lineText, L["Use: Re%-learn .*"]) then
                        tooltipData.isRelearn = true
                    end

                    -- TODO: Not tagging a few items like this - GetItemSpell returns nil
                    -- if self:GetItemID() == 224423 then
                    -- 	DevTools_Dump(data)
                    -- end

                    if data.hyperlink and C_Item.GetItemInfoInstant(data.hyperlink) ~= self:GetItemID() then -- Skip self-referential items for now
                        local spellName, spellID = C_Item.GetItemSpell(data.hyperlink)
                        if spellID then
                            -- local isUsable = C_Spell.IsSpellUsable(spellID)
                            -- print(tostring(spellName) .. tostring(spellID) .. self:GetItemLink())
                            local recipeInfo = C_TradeSkillUI.GetRecipeInfo(spellID)
                            if not recipeInfo then
                                -- The client knows no recipe for this spell: nothing to add here.
                            elseif recipeInfo.learned then
                                tooltipData.canLearn = false
                                -- print(self:GetItemLink() .. " already learned")
                            else
                                -- Also verify the player has the required profession - old recipes
                                -- may lack a RestrictedSkill tooltip line so the profession check
                                -- in that handler never fires.
                                tooltipData.canLearn = C_TradeSkillUI.IsRecipeProfessionLearned(recipeInfo.recipeID)
                                -- print("Can learn " .. self:GetItemLink() .. " creates " .. data.hyperlink)
                            end
                            -- TODO: Likely don't need this now that profession data load is handled upfront.
                            -- else
                            -- 	-- TODO: Assume it's learnable for the moment since some items don't give the data
                            -- 	tooltipData.canLearn = true
                        end
                    else
                        -- No related item so do checks on known learnables
                        if strmatch(lineText, L["Use: Study to increase your .*"]) then -- reward from Artisans
                            -- TODO: Could validate profession in lineText but I think you only receive these items if you have the profession
                            tooltipData.canLearn = true
                        end
                    end
                end

                -- TODO: Keeping for a bit but I have this handled at my overrides at the end that check usable spells from items
                -- if (self:GetCaerdonItemType() == CaerdonItemType.Consumable or self:GetCaerdonItemType() == CaerdonItemType.Quest) and self:HasItemLocation() then
                -- 	local location = self:GetItemLocation()
                -- 	local maxStackCount = C_Item.GetItemMaxStackSize(location)
                -- 	local currentStackCount = C_Item.GetStackCount(location)

                -- 	local combineCount = tonumber((strmatch(lineText, L["Use: Combine (%d+)"]) or 0))
                -- 	if combineCount > 1 then
                -- 		tooltipData.canCombine = true
                -- 		if combineCount <= currentStackCount then
                -- 			tooltipData.readyToCombine = true
                -- 		end
                -- 	end
                -- end

                if not tooltipData.bindingStatus then
                    -- Check binding status - TODO: Is there a non-scan way?
                    tooltipData.bindingStatus = bindTextTable[lineText]
                end

                if strmatch(lineText, L["Use: .* ([%d,]+) reputation"]) then
                    if CaerdonWardrobeConfig.Binding.ShowBoARepItems then
                        tooltipData.canLearn = true
                    end
                elseif strmatch(lineText, L["Use: Marks your map with the location"]) then
                    tooltipData.canLearn = true
                elseif strmatch(lineText, L["Use: Unlocks this customization"]) then
                    tooltipData.canLearn = true
                    -- TODO: Review - removed because I think this is handled by recipe management
                    -- elseif strmatch(lineText, L["Use: Study to increase your"]) then
                    -- 	tooltipData.canLearn = true
                elseif lineText == ITEM_SOULBOUND then
                    tooltipData.isSoulbound = true
                elseif lineText == ITEM_SPELL_KNOWN then
                    tooltipData.isKnownSpell = true
                elseif lineText == LOCKED then
                    tooltipData.isLocked = true
                elseif lineText == ITEM_OPENABLE then
                    tooltipData.isOpenable = true
                elseif lineText == TOOLTIP_SUPERCEDING_SPELL_NOT_KNOWN then
                    tooltipData.supercedingSpellNotKnown = true
                end
            end
        elseif line.type == Enum.TooltipDataLineType.Blank then
        elseif line.type == Enum.TooltipDataLineType.UnitName then
        elseif line.type == Enum.TooltipDataLineType.GemSocket then
        elseif line.type == Enum.TooltipDataLineType.AzeriteEssenceSlot then
        elseif line.type == Enum.TooltipDataLineType.AzeriteEssencePower then
            -- elseif line.type == Enum.TooltipDataLineType.LearnableSpell then
        elseif line.type == Enum.TooltipDataLineType.UnitThreat then
        elseif line.type == Enum.TooltipDataLineType.QuestObjective then
        elseif line.type == Enum.TooltipDataLineType.AzeriteItemPowerDescription then
        elseif line.type == Enum.TooltipDataLineType.RuneforgeLegendaryPowerDescription then
        elseif line.type == Enum.TooltipDataLineType.SellPrice then
        elseif line.type == Enum.TooltipDataLineType.ProfessionCraftingQuality then
        elseif line.type == Enum.TooltipDataLineType.SpellName then
        elseif line.type == Enum.TooltipDataLineType.CurrencyTotal then
        elseif line.type == Enum.TooltipDataLineType.ItemEnchantmentPermanent then
        elseif line.type == Enum.TooltipDataLineType.UnitOwner then
        elseif line.type == Enum.TooltipDataLineType.QuestTitle then
        elseif line.type == Enum.TooltipDataLineType.QuestPlayer then
        elseif line.type == Enum.TooltipDataLineType.NestedBlock then
        elseif line.type == Enum.TooltipDataLineType.UsageRequirement then
            -- UsageRequirement (type 43) consolidates the old Restricted* line types.
            -- line.requirementType maps to Enum.TooltipDataUsageRequirementType.
            -- line.usable is false when the requirement text is red (not met).
            local reqType = line.requirementType
            if reqType == Enum.TooltipDataUsageRequirementType.NotAlreadyKnown then
                tooltipData.canLearn = false
                tooltipData.isKnownSpell = true
            elseif reqType == Enum.TooltipDataUsageRequirementType.RaceClass then
                -- "Classes: Mage" / "Races: ..." in red: unlike a level or skill shortfall this
                -- never changes for the toon, so the item is permanently unusable here.
                if leftHex == "ffff2020" then
                    tooltipData.raceClassRestricted = true
                end
            elseif reqType == Enum.TooltipDataUsageRequirementType.Skill then
                tooltipData.hasSkillRequirement = true
                -- "Requires Engineering (50)" not in red: the client's own verdict that this
                -- toon has the skill at that rank.
                if leftHex and leftHex ~= "ffff2020" then
                    tooltipData.skillRequirementMet = true
                end
                local requiredSkill, requiredRank
                if lineText then
                    requiredSkill, requiredRank = strmatch(lineText, SkillRequirementPattern())
                end
                if requiredSkill then
                    -- An item asks for a rank of this skill, so its rank is one to watch
                    -- (CaerdonRefresh.lua: a weapon skill is otherwise read as there or not).
                    NS.Refresh:NoteSkillRequirement(requiredSkill)
                end
                if isRecipe or isMiscellaneousStudy then
                    if requiredSkill then
                        local hasSkillLine, meetsMinRank, rank, maxRank = CaerdonRecipe:GetPlayerSkillInfo(self,
                            requiredSkill, requiredRank)
                        -- print(self:GetItemLink() .. "hasSkillLine: " .. tostring(hasSkillLine) .. ", meetsMinRank: " .. tostring(meetsMinRank))

                        -- The client only colors this line red while the requirement is unmet, so a
                        -- non-red line is its own verdict that the toon has the skill at the required
                        -- rank. Trust it over the cached profession data, which is only refreshed
                        -- while trade skill data is ready and can lag behind skill-ups. A red line
                        -- still goes through the cache to tell "rank too low" from "no profession".
                        if leftHex and leftHex ~= "ffff2020" then
                            hasSkillLine = true
                            meetsMinRank = true
                        end

                        tooltipData.requiredTradeSkillMissingOrUnleveled = not hasSkillLine
                        tooltipData.requiredTradeSkillTooLow = hasSkillLine and not meetsMinRank
                        tooltipData.canLearn = hasSkillLine
                    end
                end
            end
        elseif line.type == Enum.TooltipDataLineType.EquipSlot then
        elseif line.type == Enum.TooltipDataLineType.ItemName then
        elseif line.type == Enum.TooltipDataLineType.ItemLevel then
        elseif line.type == Enum.TooltipDataLineType.ItemUpgradeLevel then
            -- Greyed out: a track the game no longer raises (a past season's piece).
            if leftHex == "ff808080" or (lineText and lineText:find("|c[fF][fF]808080")) then
                tooltipData.upgradeLevelDisabled = true
            end
        elseif line.type == Enum.TooltipDataLineType.FlavorText then
        elseif line.type == Enum.TooltipDataLineType.ErrorLine then
        elseif line.type == Enum.TooltipDataLineType.DisabledLine then
        else
            if CaerdonWardrobeConfig.Debug.Enabled then
                print("Caerdon: TOOLTIP PROCESSING NEEDED: " .. self:GetItemLink() .. ", type: " .. tostring(line.type))
                -- DevTools_Dump(line)
            end
        end
    end

    -- if self:GetItemID() == 224418 then
    -- 	DevTools_Dump(tooltipData)
    -- end
    -- DevTools_Dump(tooltipData)
    return tooltipData
end

-- { Name = "None", Type = "TooltipDataLineType", EnumValue = 0 },
-- { Name = "Blank", Type = "TooltipDataLineType", EnumValue = 1 },
-- { Name = "UnitName", Type = "TooltipDataLineType", EnumValue = 2 },
-- { Name = "GemSocket", Type = "TooltipDataLineType", EnumValue = 3 },
-- { Name = "AzeriteEssenceSlot", Type = "TooltipDataLineType", EnumValue = 4 },
-- { Name = "AzeriteEssencePower", Type = "TooltipDataLineType", EnumValue = 5 },
-- { Name = "LearnableSpell", Type = "TooltipDataLineType", EnumValue = 6 },
-- { Name = "UnitThreat", Type = "TooltipDataLineType", EnumValue = 7 },
-- { Name = "QuestObjective", Type = "TooltipDataLineType", EnumValue = 8 },
-- { Name = "AzeriteItemPowerDescription", Type = "TooltipDataLineType", EnumValue = 9 },
-- { Name = "RuneforgeLegendaryPowerDescription", Type = "TooltipDataLineType", EnumValue = 10 },
-- { Name = "SellPrice", Type = "TooltipDataLineType", EnumValue = 11 },
-- { Name = "ProfessionCraftingQuality", Type = "TooltipDataLineType", EnumValue = 12 },
-- { Name = "SpellName", Type = "TooltipDataLineType", EnumValue = 13 },
-- { Name = "CurrencyTotal", Type = "TooltipDataLineType", EnumValue = 14 },
-- { Name = "ItemEnchantmentPermanent", Type = "TooltipDataLineType", EnumValue = 15 },
-- { Name = "UnitOwner", Type = "TooltipDataLineType", EnumValue = 16 },
-- { Name = "QuestTitle", Type = "TooltipDataLineType", EnumValue = 17 },
-- { Name = "QuestPlayer", Type = "TooltipDataLineType", EnumValue = 18 },
-- { Name = "NestedBlock", Type = "TooltipDataLineType", EnumValue = 19 },
-- { Name = "ItemBinding", Type = "TooltipDataLineType", EnumValue = 20 },

function CaerdonItemMixin:IsSellable()
    local itemID = self:GetItemID()
    local isSellable = itemID ~= nil
    if itemID == 23192 then      -- Tabard of the Scarlet Crusade needs to be worn for a vendor at Darkmoon Faire
        isSellable = false
    elseif itemID == 116916 then -- Gorepetal's Gentle Grasp allows faster herbalism in Draenor
        isSellable = false
    end
    return isSellable
end

-- Quests that take this item even though it is not a Quest-class item: the ones in the quest log
-- and, when QuestieDB is loaded, the ones this toon has not accepted yet. nil when there are none.
-- See CaerdonQuestItems:GetItemQuestInfo for the fields.
function CaerdonItemMixin:GetQuestItemInfo()
    local itemID = self:GetItemID()
    if not itemID then
        return nil
    end
    return CaerdonQuestItems:GetItemQuestInfo(itemID, self:GetItemName())
end

-- Food and drink: what kind it is and whether a better one is carried. nil for anything else.
-- See CaerdonFoodDrink:GetItemInfo for the fields.
function CaerdonItemMixin:GetFoodDrinkInfo()
    local itemID = self:GetItemID()
    if not itemID then
        return nil
    end
    return CaerdonFoodDrink:GetItemInfo(itemID, self:GetItemLink())
end

-- A tool of a profession this toon has (Mining Pick, Blacksmith Hammer, Arclight Spanner):
-- nil for anything else. See CaerdonProfessionTools:GetItemInfo for the fields.
function CaerdonItemMixin:GetProfessionToolInfo()
    local itemID = self:GetItemID()
    if not itemID then
        return nil
    end
    return CaerdonProfessionTools:GetItemInfo(itemID, self:GetItemName())
end

-- A bag (ordinary, reagent or profession bag) held against the bag slots it fits: whether it
-- belongs in one now (a slot is empty or holds a bag it improves on) or is a spare. nil for
-- anything else. Quivers are bags here too. See CaerdonBagSlots:GetItemInfo for the fields.
function CaerdonItemMixin:GetBagSlotInfo()
    local itemID = self:GetItemID()
    if not itemID then
        return nil
    end
    return CaerdonBagSlots:GetItemInfo(itemID, self:GetItemLink())
end

-- An ingredient of a recipe, as recorded when the profession windows were open: this toon's
-- recipes that take it and whether one still gives skill, and the other toons whose recipes
-- do. nil when no recorded recipe takes it. See CaerdonIngredients:GetItemInfo for the fields.
function CaerdonItemMixin:GetIngredientInfo()
    local itemID = self:GetItemID()
    if not itemID then
        return nil
    end
    return CaerdonIngredients:GetItemInfo(itemID)
end

-- A look the piece would gain by being raised on its upgrade track or converted at the
-- Catalyst: nil when there is none. sourceID: the piece's own source, where the caller has
-- it. upgradeDisabled: its tooltip's upgrade line is greyed out. See
-- CaerdonTransformLooks:GetItemInfo for the fields.
-- trace: a list the answers behind it are written to, a line each (for the export).
function CaerdonItemMixin:GetTransformLookInfo(sourceID, upgradeDisabled, trace)
    if self:IsItemEmpty() then
        return nil
    end
    return CaerdonTransformLooks:GetItemInfo(self, sourceID, upgradeDisabled, trace)
end

-- Whether vendors sell the item, as far as anything says: nil when nothing does (QuestieDB is
-- not loaded). See CaerdonVendorGoods:GetItemInfo for the fields.
function CaerdonItemMixin:GetVendorInfo()
    local itemID = self:GetItemID()
    if not itemID then
        return nil
    end
    return CaerdonVendorGoods:GetItemInfo(itemID)
end

-- The skill and rank the item's tooltip asks for, to hold another toon's saved rank against
-- (CaerdonRecipe:GetOtherToonRecipeInfo). nil when it names no skill with a rank, otherwise
--   { skillName, rank = the "Requires Cooking (125)" line,
--     useNumber = the number in its "Use:" line, where that line has exactly one }
-- A book that raises a profession's cap says the new cap in its use line and nowhere else
-- ("... allowing a maximum of 225 cooking skill", Expert Cookbook 16072). What the number
-- means is the caller's to say; a line with a colour or plural escape has more than one run
-- of digits and gives none.
function CaerdonItemMixin:GetSkillRequirement()
    local itemLink = self:GetItemLink()
    local data = itemLink and C_TooltipInfo and C_TooltipInfo.GetHyperlink(itemLink)
    if type(data) ~= "table" or type(data.lines) ~= "table" then
        return nil
    end
    local lineTypes, requirementTypes = Enum.TooltipDataLineType, Enum.TooltipDataUsageRequirementType
    local skillName, rank, useNumber
    for _, line in ipairs(data.lines) do
        local lineText = line.leftText and tostring(line.leftText) or nil
        if not lineText then
            -- Nothing to read.
        elseif line.type == lineTypes.UsageRequirement then
            if not rank and requirementTypes and line.requirementType == requirementTypes.Skill then
                local name, number = strmatch(lineText, SkillRequirementPattern())
                if name and tonumber(number) then
                    skillName, rank = name, tonumber(number)
                end
            end
        elseif lineTypes.ItemSpellTriggerOnUse and line.type == lineTypes.ItemSpellTriggerOnUse and not useNumber then
            local count, found = 0, nil
            for number in lineText:gmatch("%d+") do
                count, found = count + 1, number
            end
            if count == 1 then
                useNumber = tonumber(found)
            end
        end
    end
    if not rank then
        return nil
    end
    return { skillName = skillName, rank = rank, useNumber = useNumber }
end

-- What to do with an ingredient this toon has no use for. Returns the status that replaces an
-- empty one, or nil, and the ingredient info where it was read:
--   "send":     another toon of the realm has a recipe that takes it (which recipes count is
--               the setting Icon.IngredientsForOtherToons: one that still gives it skill, or
--               any it knows), and the item can be handed over. Not what vendors everywhere
--               sell (thread, spices, a vial): the other toon buys that where it stands.
--   "sellable": this toon's own recipes take it, every one of them is gray, and a vendor pays.
-- Only for an item that is a material and nothing else: a trade good, or what the client
-- itself calls a crafting reagent. A recipe can take anything, and an item of another class
-- has a use of its own that no recipe says anything about: a hunter's arrows are what an
-- engineer's Explosive Arrow is made of (Razor Arrow 3030, class Projectile).
-- Neither for an ingredient this toon still gets skill from, one a recipe of its own could
-- not be read for, a profession tool, or food kept for a hunter's pet. And neither for one a
-- quest takes, one in the log or one still to come: a quest comes before another toon. The
-- quest module is asked itself, since "has quest value" in GetCaerdonStatus follows the quest
-- icon's settings and this must hold with that icon switched off too.
function CaerdonItemMixin:GetIngredientStatus()
    local iconConfig = CaerdonWardrobeConfig.Icon
    local showSend = iconConfig.ShowIngredientsForOtherToons == true
    local showOutgrown = iconConfig.ShowOutgrownIngredients == true
    if not (showSend or showOutgrown) then
        return nil, nil
    end
    local info = self:GetIngredientInfo()
    if not info then
        return nil, nil
    end
    if info.hasUse or info.undecided > 0 then
        return nil, info
    end
    local _, _, _, _, _, itemClassID = C_Item.GetItemInfoInstant(self:GetItemID())
    if itemClassID ~= Enum.ItemClass.Tradegoods and not self:GetIsCraftingReagent() then
        return nil, info
    end
    local questInfo = self:GetQuestItemInfo()
    if questInfo and (questInfo.isActive or questInfo.isUpcoming) then
        return nil, info
    end
    local itemID = self:GetItemID()
    if self:GetProfessionToolInfo() ~= nil or CaerdonFoodDrink:IsKeptForPet(itemID) then
        return nil, info
    end

    if showSend and not self:IsSoulbound() and self:GetBinding() ~= CaerdonItemBind.BindOnPickup then
        local toons = iconConfig.IngredientsForOtherToons == "any" and info.usedBy or info.skillFor
        if #toons > 0 then
            -- Asked last: it is the one question here that goes to another addon's data.
            local vendorInfo = self:GetVendorInfo()
            if not (vendorInfo and vendorInfo.isCommon) then
                return "send", info
            end
        end
    end
    if showOutgrown and info.isOutgrown then
        local itemLink = self:GetItemLink()
        local sellPrice = itemLink and select(11, C_Item.GetItemInfo(itemLink))
        if sellPrice and sellPrice > 0 then
            return "sellable", info
        end
    end
    return nil, info
end

-- Whether the auction icon stays off a trade good because the toon keeps it as an ingredient
-- (the setting Icon.AuctionTradeGoods):
--   "all":         never: any trade good that pays is marked.
--   "skill":       one a recipe of this toon's still gives skill for.
--   "professions": one any recorded recipe of this toon's takes.
--   "none":        every one: no trade good is marked for its price alone.
function CaerdonItemMixin:IsIngredientKeptFromAuction()
    local setting = CaerdonWardrobeConfig.Icon.AuctionTradeGoods
    if setting == "none" then
        return true
    elseif setting ~= "skill" and setting ~= "professions" then
        return false
    end
    local info = self:GetIngredientInfo()
    if not info or #info.recipes == 0 then
        return false
    end
    return setting == "professions" or info.hasUse or info.undecided > 0
end

-- Miscellaneous / Junk items that go in an equipment slot but do nothing there: no stats shown
-- as an equip effect, no use, no appearance to learn. The trophy fish are the classic case
-- (15 Pound Mud Snapper 6295, "Held In Off-hand", vendors for 15s). Not Equipment as far as the
-- type detection goes, so the collected / sellable logic never sees them. Deliberately narrow:
-- plenty of Miscellaneous / Junk items that are not equippable are worth keeping.
function CaerdonItemMixin:IsEquippableJunk(bindingResult)
    local itemLink = self:GetItemLink()
    if not itemLink or self:GetCaerdonItemType() ~= CaerdonItemType.Unhandled then
        return false
    end

    local _, _, _, _, _, _, _, _, equipLoc, _, sellPrice, classID, subClassID = C_Item.GetItemInfo(itemLink)
    if classID ~= Enum.ItemClass.Miscellaneous or subClassID ~= Enum.ItemMiscellaneousSubclass.Junk then
        return false
    end
    if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" then
        return false
    end
    if not sellPrice or sellPrice <= 0 then
        return false
    end
    if self:GetHasUse() or (bindingResult and bindingResult.hasEquipEffect) then
        return false
    end
    -- Something with an appearance may still be worth learning; leave it unmarked.
    local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemLink)
    if appearanceID or sourceID then
        return false
    end
    return self:IsSellable()
end

-- Consumables whose tooltip carries a red race / class requirement ("Classes: Mage" on a hunter).
-- A level or skill shortfall can be fixed; this cannot, so the item is only worth selling. Kept
-- to Consumables: class-restricted equipment has its own appearance logic, and recipes have
-- theirs. Account-bound items are left alone because another toon on the account may use them.
function CaerdonItemMixin:IsOtherClassConsumable(bindingResult)
    if not (bindingResult and bindingResult.raceClassRestricted) then
        return false
    end
    if self:GetCaerdonItemType() ~= CaerdonItemType.Consumable then
        return false
    end
    local binding = self:GetBinding()
    if binding == CaerdonItemBind.BindOnAccount or binding == CaerdonItemBind.WarboundUntilEquip then
        return false
    end
    local itemLink = self:GetItemLink()
    local sellPrice = itemLink and select(11, C_Item.GetItemInfo(itemLink))
    if not sellPrice or sellPrice <= 0 then
        return false
    end
    return self:IsSellable()
end

-- The player's other toons on this realm that have this recipe item's profession and whether
-- they know the recipe (see CaerdonRecipe:GetOtherToonRecipeInfo for the fields). nil for
-- anything that is not a recipe, for a recipe that cannot be handed over (soulbound or bind on
-- pickup), and when no other toon has the profession. The icon and the tooltip both use this.
function CaerdonItemMixin:GetRecipeOtherToonInfo()
    if self:GetCaerdonItemType() ~= CaerdonItemType.Recipe then
        return nil
    end
    if self:IsSoulbound() or self:GetBinding() == CaerdonItemBind.BindOnPickup then
        return nil
    end
    local itemData = self:GetItemData()
    if not (itemData and itemData.GetOtherToonRecipeInfo) then
        return nil
    end
    return itemData:GetOtherToonRecipeInfo()
end

-- A recipe item this toon has no use for: it already knows the recipe (Pattern: Woolen Reagent
-- Bag 253668 on a tailor who knows it) or cannot learn it. Returns the status that replaces
-- "collected", or nil to leave it:
--   "send":      it can still be handed over and another toon on the realm has the profession
--                at the rank the item asks for, and the recipe in its recorded list as one
--                not learned (CaerdonRecipe:GetOtherToonRecipeInfo): mail it. The same
--                status an ingredient another toon can use gets.
--   "sellable":  this toon knows it and nobody else wants it; needs a vendor price.
-- For "sellable" only the client's own tooltip verdict counts as known; the name-based recipe
-- lookup cannot tell recipe ranks that share a name apart, which is fine for hiding a star or
-- picking the icon colour but not for saying "sell this". Account-bound recipes are never
-- called sellable: another toon on the account may learn them, and the saved data only covers
-- this realm.
function CaerdonItemMixin:GetUnneededRecipeStatus(bindingResult)
    if self:GetCaerdonItemType() ~= CaerdonItemType.Recipe then
        return nil
    end
    local alreadyKnown = (bindingResult and bindingResult.alreadyKnown) or false
    if CaerdonWardrobeConfig.Icon.ShowRecipesForOtherToons ~= false then
        local otherToons = self:GetRecipeOtherToonInfo()
        if otherToons then
            if #otherToons.missing > 0 then
                return "send"
            end
            if alreadyKnown and (#otherToons.unknown > 0 or #otherToons.notInList > 0 or #otherToons.tooLow > 0) then
                -- A toon with the profession whose recipes were never recorded, whose
                -- recorded list has no such recipe and nothing else says whether it has what
                -- the item teaches, or whose rank is below what the item asks for: it may
                -- need this one, so do not call it sellable, but there is nothing to claim
                -- either.
                return nil
            end
        end
    end
    if not alreadyKnown then
        return nil
    end
    local binding = self:GetBinding()
    if binding == CaerdonItemBind.BindOnAccount or binding == CaerdonItemBind.WarboundUntilEquip then
        return nil
    end
    local itemLink = self:GetItemLink()
    local sellPrice = itemLink and select(11, C_Item.GetItemInfo(itemLink))
    if not sellPrice or sellPrice <= 0 then
        return nil
    end
    return self:IsSellable() and "sellable" or nil
end

-- Whether listing this item on the auction house beats vendoring it. Always returns the full
-- breakdown (see CaerdonAuctionValue:GetItemAuctionInfo); `shouldAuction` is the verdict.
function CaerdonItemMixin:GetAuctionValueInfo()
    local itemLink = self:GetItemLink()
    if not itemLink then
        return nil
    end

    local blockedReason
    local binding = self:GetBinding()
    if self:IsSoulbound() then
        blockedReason = "soulbound"
    elseif binding == CaerdonItemBind.BindOnPickup then
        blockedReason = "binds on pickup"
    elseif binding == CaerdonItemBind.BindOnAccount then
        blockedReason = "account bound"
    elseif binding == CaerdonItemBind.QuestItem then
        blockedReason = "quest item"
    end

    local _, _, _, _, _, _, _, maxStack, _, _, vendorPrice = C_Item.GetItemInfo(itemLink)
    local options
    if maxStack and maxStack > 1 then
        -- Stackable goods are judged on everything owned: that is what one trip would list.
        local itemID = self:GetItemID()
        options = {
            stackable = true,
            itemID = itemID,
            quantity = CaerdonAuctionValue:GetOwnedQuantity(itemID)
        }
    end
    return CaerdonAuctionValue:GetItemAuctionInfo(itemLink, vendorPrice, blockedReason, options)
end

function CaerdonItemMixin:IsCollectible()
    local caerdonType = self:GetCaerdonItemType()
    return caerdonType == CaerdonItemType.BattlePet or
        caerdonType == CaerdonItemType.CompanionPet or
        caerdonType == CaerdonItemType.Mount or
        caerdonType == CaerdonItemType.Housing or
        caerdonType == CaerdonItemType.Recipe or
        caerdonType == CaerdonItemType.Toy
end

function CaerdonItemMixin:GetBindingStatus(tooltipData)
    local itemID = self:GetItemID()
    local itemLink = self:GetItemLink()
    local itemData = self:GetItemData()
    local caerdonType = self:GetCaerdonItemType()

    local bindingStatus
    local needsItem = true
    local hasEquipEffect = false

    local isBindOnPickup = false
    local isBindOnUse = false
    local unusableItem = false
    local skillTooLow = false
    local foundRedRequirements = false
    local isLocked = false
    local isOpenable = false
    local raceClassRestricted = false

    local isCollectionItem = self:IsCollectible()

    local itemName, itemLinkInfo, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
    itemEquipLoc, iconFileDataID, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID,
    isCraftingReagent = C_Item.GetItemInfo(itemLink)

    local binding = self:GetBinding()

    if binding == CaerdonItemBind.None then
        bindingStatus = ""
    elseif binding == CaerdonItemBind.BindOnPickup then
        isBindOnPickup = true
    elseif binding == CaerdonItemBind.BindOnEquip then
        bindingStatus = L["BoE"]
    elseif binding == CaerdonItemBind.WarboundUntilEquip then
        bindingStatus = L["WuE"]
    elseif binding == CaerdonItemBind.BindOnUse then
        isBindOnUse = true
        bindingStatus = L["BoE"]
    elseif binding == CaerdonItemBind.QuestItem then
        bindingStatus = ""
    elseif binding == CaerdonItemBind.BindOnAccount then
        bindingStatus = L["BoA"]
    end

    if self:IsSoulbound() then
        isBindOnPickup = true
        bindingStatus = nil
    end

    if tooltipData then
        hasEquipEffect = tooltipData.hasEquipEffect

        if tooltipData.isRelearn then
            needsItem = false
        end

        if not bindingStatus then
            bindingStatus = tooltipData.bindingStatus
        end

        if caerdonType ~= CaerdonItemType.Recipe then -- ignore red on recipes for now... should be handling correctly through the recipe checks
            if tooltipData.foundRedRequirements then  -- TODO: See about getting rid of this eventually and having specific checks (if possible)
                unusableItem = true
                if caerdonType ~= CaerdonItemType.Recipe then
                    skillTooLow = true
                end
            end
        end

        if tooltipData.isKnownSpell then
            needsItem = false
            unusableItem = true
            skillTooLow = false
        end

        isLocked = tooltipData.isLocked
        isOpenable = tooltipData.isOpenable
        raceClassRestricted = tooltipData.raceClassRestricted

        if tooltipData.supercedingSpellNotKnown then
            unusableItem = true
            skillTooLow = true
        end

        if tooltipData.requiredTradeSkillMissingOrUnleveled then
            unusableItem = true
            -- if isBindOnPickup then -- assume all unknown not needed for now
            needsItem = false
            -- end
        else
            if tooltipData.requiredTradeSkillTooLow then
                unusableItem = true
                skillTooLow = true
                needsItem = true -- still need this but need to rank up
            else
                needsItem = true
            end
        end
    end

    if not bindingStatus and (isCollectionItem or isLocked or isOpenable) then
        -- TODO: This can be useful on everything but needs to be configurable per type before doing so
        if not isBindOnPickup then
            bindingStatus = L["BoE"]
        end
    end

    if caerdonType == CaerdonItemType.Conduit then
        local conduitInfo = itemData:GetConduitInfo()
        if conduitInfo then
            needsItem = conduitInfo.needsItem
        end
    elseif caerdonType == CaerdonItemType.CompanionPet or caerdonType == CaerdonItemType.BattlePet then
        local petInfo =
            (caerdonType == CaerdonItemType.CompanionPet and itemData:GetCompanionPetInfo()) or
            (caerdonType == CaerdonItemType.BattlePet and itemData:GetBattlePetInfo())
        if petInfo then
            needsItem = petInfo.needsItem
        end
    elseif caerdonType == CaerdonItemType.Recipe then
        local recipeInfo = itemData:GetRecipeInfo()
        -- DevTools_Dump(recipeInfo)
        if (recipeInfo and recipeInfo.learned) or tooltipData.isKnownSpell then
            needsItem = false
        elseif tooltipData.canLearn or (recipeInfo and recipeInfo.canLearn) then
            -- tooltipData.canLearn is set by RestrictedSkill tooltip lines (modern recipes).
            -- recipeInfo.canLearn is from the RecipeMixin's name-based lookup and handles
            -- old-world recipes that lack RestrictedSkill lines in their tooltip data.
            needsItem = true
        else
            needsItem = false
        end
    end

    -- Haven't seen a reason for this, yet, and should be handled in each type
    -- if isCollectionItem and unusableItem then
    -- 	if not isRecipe then
    -- 		needsItem = false
    -- 	end
    -- end

    return {
        bindingStatus = bindingStatus,
        needsItem = needsItem,
        -- Any "Equip:" line, and whether one of them is more than a plain stat (spell power and
        -- the like on WoW Forever, see IsEquipStatLine). Only the second keeps a piece.
        hasEquipEffect = hasEquipEffect,
        hasEquipEffectBeyondStats = (tooltipData and tooltipData.hasEquipEffectBeyondStats) or false,
        isBindOnPickup = isBindOnPickup,
        unusableItem = unusableItem,
        isLocked = isLocked,
        skillTooLow = skillTooLow,
        -- Red race / class requirement line: this toon can never use the item.
        raceClassRestricted = raceClassRestricted,
        -- The tooltip has a skill requirement line ("Requires Engineering (50)") that is met.
        skillRequirementMet = (tooltipData and tooltipData.skillRequirementMet) or false,
        -- The tooltip has a skill requirement line at all, met or not.
        hasSkillRequirement = (tooltipData and tooltipData.hasSkillRequirement) or false,
        -- The tooltip's upgrade line is greyed out: the piece can no longer be raised.
        upgradeLevelDisabled = (tooltipData and tooltipData.upgradeLevelDisabled) or false,
        -- The tooltip carries the client's "Already known" line.
        alreadyKnown = (tooltipData and tooltipData.isKnownSpell) or false
    }
end

-- A use spell whose text the client has not loaded reads as an empty description, which is the
-- answer for a spell with nothing to combine. Kept, that answer left the item without its icon
-- until something else refreshed (retail client: after a login the combine icon was missing on
-- whichever bank items' spells had not been loaded, and there after a reload). So such an
-- answer is not kept: the spell's data is asked for, once a session, and the items are drawn
-- again when it is here. True while the answer is still on its way.
local function IsCopySpellLoading(spellID)
    if C_Spell.IsSpellDataCached(spellID) then
        return false
    end
    local state = copySpellLoads[spellID]
    if state == nil then
        copySpellLoads[spellID] = "asked"
        CaerdonSpellEventListener:AddCallback(spellID, function()
            copySpellLoads[spellID] = "answered"
            -- Only for a text that came: many use spells have none (a recipe's).
            if (C_Spell.GetSpellDescription(spellID) or "") ~= "" then
                CaerdonWardrobe:RefreshItems("spell text")
            end
        end, function()
            -- The client has no data for it: the empty description is the answer after all.
            copySpellLoads[spellID] = "answered"
        end)
        -- The client may have answered from inside the call.
        state = copySpellLoads[spellID]
    end
    return state == "asked"
end

-- What an item's use spell says about combining, which follows from the link: false for an item
-- with no such spell. Kept until the status cache is wiped (copySpellCache, at the top).
local function GetCopySpellFacts(itemLink)
    local facts = copySpellCache[itemLink]
    if facts == nil then
        facts = false
        local spellName, spellID = C_Item.GetItemSpell(itemLink)
        if spellID then
            if spellID == 433080 or spellID == 439058 then -- Breaking Down / Attuning Stone Wing (if in bags)
                -- TODO: Better to figure out a way to identify spells that create currency if possible
                facts = { spellID = spellID, makesCurrency = true }
            else
                local spellDescription = C_Spell.GetSpellDescription(spellID) or ""
                if spellDescription == "" and IsCopySpellLoading(spellID) then
                    return false
                end
                -- local isCollectDescription = string.find(spellDescription, L["^Collect .* appearances.*"]) ~= nil
                local isCombineDescription = string.find(spellDescription, L["^Combine"]) ~= nil
                local isArrangeDescription = string.find(spellDescription, L["^Arrange %d+"]) ~= nil
                if isCombineDescription or isArrangeDescription then
                    facts = {
                        spellID = spellID,
                        combineCount = tonumber((strmatch(spellDescription, L["Combine (%d+)"]) or strmatch(spellDescription, L["Arrange (%d+)"]) or 0)),
                    }
                end
            end
        end
        copySpellCache[itemLink] = facts
    end
    return facts
end

-- The part of the status that belongs to one copy of an item in its bag slot: something to
-- open, locked, readable, refundable, or a stack that can be combined. GetCaerdonStatus keeps
-- its verdict per link, and none of this follows from the link, so it is added here, after the
-- cache lookup, on every call. Otherwise a verdict first asked for outside the bags (the mail,
-- a loot window, a vendor) would stand for the copy in the bags, and two copies in different
-- states would share one.
function CaerdonItemMixin:GetCopyStatus(mogStatus, bindingResult)
    if not self:HasItemLocationBankOrBags() then
        return mogStatus
    end

    local itemLocation = self:GetItemLocation()

    local bag, slot = itemLocation:GetBagAndSlot()

    local containerID = bag
    local containerSlot = slot

    local itemCount, locked, quality, readable, lootable
    local containerItemInfo = C_Container.GetContainerItemInfo(containerID, containerSlot)
    if containerItemInfo then
        itemCount = containerItemInfo.stackCount
        locked = containerItemInfo.isLocked
        quality = containerItemInfo.quality
        readable = containerItemInfo.isReadable
        lootable = containerItemInfo.hasLoot
    end

    if lootable then
        -- A cooldown on the container is not looked at: the client draws its own spiral on the
        -- button. (A test for one stood here since 2018 and could never be true.)
        local isLocked = IsBagSlotLocked(containerID, containerSlot)
        if isLocked == nil then
            isLocked = bindingResult.isLocked
        end
        if isLocked then
            mogStatus = "locked"
        else
            mogStatus = "openable"
        end
    elseif readable then
        mogStatus = "readable"
    else
        local isEquipped = false
        local money, itemCount, refundSec, currencyCount, hasEnchants
        if C_Container and C_Container.GetContainerItemPurchaseInfo then
            local info = C_Container.GetContainerItemPurchaseInfo(bag, slot, isEquipped)
            money = info and info.money
            itemCount = info and info.itemCount
            refundSec = info and info.refundSeconds
            currencyCount = info and info.currencyCount
            hasEnchants = info and info.hasEnchants
        else
            money, itemCount, refundSec, currencyCount, hasEnchants = GetContainerItemPurchaseInfo(bag, slot,
                isEquipped)
        end
        if refundSec then
            mogStatus = "refundable"
        end
    end

    -- TODO: C_Item.GetItemLearnTransmogSet

    local spellFacts = GetCopySpellFacts(self:GetItemLink())
    if spellFacts then
        if spellFacts.makesCurrency then
            mogStatus = "own"
        else
            local CheckUsable = C_Spell and C_Spell.IsSpellUsable or IsUsableSpell
            local currentStackCount = C_Item.GetStackCount(itemLocation)
            local combineCount = spellFacts.combineCount
            if combineCount > 1 then
                mogStatus = "canCombine"
                if combineCount <= currentStackCount then
                    mogStatus = "readyToCombine"
                end
            elseif CheckUsable(spellFacts.spellID) then
                mogStatus = "readyToCombine"
            else
                mogStatus = "canCombine"
            end
        end
    end

    return mogStatus
end

-- The key of an item's entry in the status cache: its link, and whatever else about this copy
-- changes the verdict or the transmog info kept with it. Copies with one key are served one
-- entry, whichever of them was judged first.
local function StatusCacheKey(item, itemLink)
    local key = item:IsSoulbound() and (itemLink .. "|B") or itemLink
    -- Whether a piece can be recrafted is asked of the copy (its GUID), and that keeps it from
    -- being called junk. A bare link has no copy to ask, so a crafted piece that lies somewhere
    -- does not share an entry with its link (the mail, a buyback row, a chat link). A crafted
    -- piece's link ends in its maker's GUID.
    if itemLink:find(":Player-", 1, true) and item:IsItemInPlayersControl() then
        key = key .. "|c"
    end
    -- Whether the Catalyst takes a piece is asked of the copy as well, and it decides whether
    -- the piece is a look to learn. Only a season's armor in a slot the Catalyst takes.
    if CaerdonTransformLooks:MayBeConverted(item, itemLink) then
        key = key .. "|x"
    end
    -- Which equipment sets hold a piece is asked of the copy too, and it decides the binding
    -- text and whether the piece is judged a spare. So of two copies with one link, the one a
    -- set names has an entry of its own, and so has each of two sets' copies.
    -- Only of something that can be worn: nothing else is in a set, and the asking is not
    -- free (the sets are walked once for every frame in which anything asks). It was asked of
    -- every item, a bank's 213 for its 60 pieces of equipment. Both clients answer
    -- "INVTYPE_NON_EQUIP_IGNORE" for what cannot be worn, and not an empty text (seen in the
    -- recordings of both; a first try that went by the empty text asked of everything still).
    local equipLocation = item:GetEquipLocation()
    local equipmentSets = equipLocation ~= nil and equipLocation ~= "INVTYPE_NON_EQUIP_IGNORE" and
        CaerdonEquipment:GetEquipmentSetsOf(item) or nil
    if equipmentSets then
        key = key .. "|e" .. table.concat(equipmentSets, "\1")
    end
    -- A stackable item's auction verdict depends on how many are owned.
    if CaerdonWardrobeConfig.Icon.ShowAuctionValue then
        local maxStack = select(8, C_Item.GetItemInfo(itemLink))
        if maxStack and maxStack > 1 then
            key = key .. "|n" .. CaerdonAuctionValue:GetOwnedQuantity(item:GetItemID())
        end
    end
    -- What a window knows about this copy beyond its link and passes in (an auction row's
    -- item level and suffix, the source a set or dressing room entry stands for) decides the transmog
    -- info, so two rows that share a link do not share an entry.
    local extraData = item.extraData
    if extraData then
        if extraData.appearanceSourceID then
            key = key .. "|s" .. tostring(extraData.appearanceSourceID)
        end
        if extraData.overrideItemLevel then
            key = key .. "|l" .. tostring(extraData.overrideItemLevel)
        end
        if extraData.keySuffix then
            key = key .. "|k" .. tostring(extraData.keySuffix)
        end
    end
    return key
end

-- nil for an item with no link and for a Pet Cage, which is judged anew every time. For the
-- test addon, whose contract compares the copies that share an entry.
function CaerdonItemMixin:GetStatusCacheKey()
    local itemLink = self:GetItemLink()
    if not itemLink or self:GetItemName() == L["Pet Cage"] then
        return nil
    end
    return StatusCacheKey(self, itemLink)
end

-- The link's tooltip, asked of the client. A method of its own so that the counters can say
-- what the asking costs apart from the rest of a verdict (CaerdonCounters:Attach): it was
-- counted with GetTooltipData before the status took it over, and with nothing after.
function CaerdonItemMixin:GetLinkTooltip(itemLink)
    return C_TooltipInfo and C_TooltipInfo.GetHyperlink(itemLink) or nil
end

-- Where it is not ready, the second value says what it waits for in words (for the counters),
-- and the third names it for the queue, which asks this button again when that has come and
-- not when anything has (CaerdonWardrobe:RetryWaitingFor): a tooltip's instance as a number,
-- "item:<ID>" for a set piece's data, "conversion:<GUID>" for the client's word on a copy,
-- "gear" for the pieces it is compared with. nil where nothing says when (the timer asks).
-- Returns isReady, mogStatus, bindingStatus, bindingResult, transmogInfo. transmogInfo is what
-- GetTransmogInfo() said when the verdict was made (equipment only, otherwise nil); it is shared
-- by every copy the cache entry stands for, so read it and do not ask the item data again.
function CaerdonItemMixin:GetCaerdonStatus(feature, locationInfo) -- TODO: Need to remove feature/locationInfo but keeping it for now in case refactor to GetHyperlink causes any issues - also need to remove the GetTooltipData calls
    local itemLink = self:GetItemLink()
    if not itemLink then
        -- Requiring an itemLink for now unless I find a reason not to
        if CaerdonCounters.on then CaerdonCounters:Mark("no link") end
        return
    end

    -- Pet Cage results depend on feature/location so they can't be cached by itemLink alone
    local isPetCage = self:GetItemName() == L["Pet Cage"]
    local statusCacheKey
    if not isPetCage then
        statusCacheKey = StatusCacheKey(self, itemLink)
        local cached = statusCache[statusCacheKey]
        if cached then
            if CaerdonCounters.on then CaerdonCounters:Mark("cache hit") end
            return cached[1], self:GetCopyStatus(cached[2], cached[4]), cached[3], cached[4], cached[5]
        end
    end

    local data = nil
    if isPetCage then
        -- Was hoping to just use the item link but battlepets in particular cause issues showing up as Pet Cage.
        -- Could check CaerdonItemType for BattlePet, but just going to do this for now.
        data = C_TooltipInfo and feature and feature:GetTooltipData(self, locationInfo) or nil
    end

    -- The link's tooltip is asked for here and not inside GetTooltipData, so that the one answer
    -- also serves the equipment code, which reads the PVP floor from it (GetTransmogInfo).
    local linkTooltip = nil
    if not data then
        linkTooltip = self:GetLinkTooltip(itemLink)
        data = linkTooltip
    end

    local tooltipData = self:GetTooltipData(data)

    if tooltipData and tooltipData.isRetrieving then -- Tooltip data isn't loaded yet....
        if CaerdonCounters.on then CaerdonCounters:Mark("tooltip not ready") end
        -- Don't cache: result will change once tooltip data loads. Third: the tooltip's
        -- instance, by which the client says that what it was looking up is there
        -- (TOOLTIP_DATA_UPDATE; CaerdonWardrobe:RetryWhenTooltipComes).
        return false, "its tooltip", type(data) == "table" and data.dataInstanceID or nil
    end

    local itemID = self:GetItemID()
    local caerdonType = self:GetCaerdonItemType()
    local itemData = self:GetItemData()
    local itemLocation = self:GetItemLocation()
    local isArtifactItem = false

    local bindingResult = self:GetBindingStatus(tooltipData)
    local bindingStatus = bindingResult.bindingStatus
    local playerCanEquipItem = not bindingResult.unusableItem
    local playerCanEquipItem = not bindingResult.unusableItem

    local itemName, itemLinkInfo, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
    itemEquipLoc, iconFileDataID, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID,
    isCraftingReagent = C_Item.GetItemInfo(itemLink)

    local playerLevel = UnitLevel("player")

    local mogStatus = ""
    local isReady = true
    -- The look a piece gains at the Catalyst could not be told: the data of the set's piece is
    -- not in the client's cache just now (CaerdonTransformLooks, pending). No verdict then.
    local lookPending = false
    -- The equipment branch's transmog info, kept with the verdict and returned.
    local statusTransmogInfo = nil

    if not self:IsCollectible() and caerdonType ~= CaerdonItemType.Conduit and caerdonType ~= CaerdonItemType.Equipment then
        local expansionID = expacID
        if expansionID and expansionID >= 0 and expansionID < GetExpansionLevel() then
            local shouldShowExpansion = false

            if expansionID > 0 or CaerdonWardrobeConfig.Icon.ShowOldExpansion.Unknown then
                if isCraftingReagent and CaerdonWardrobeConfig.Icon.ShowOldExpansion.Reagents then
                    shouldShowExpansion = true
                elseif self:GetHasUse() and CaerdonWardrobeConfig.Icon.ShowOldExpansion.Usable then
                    shouldShowExpansion = true
                elseif not isCraftingReagent and not self:GetHasUse() and CaerdonWardrobeConfig.Icon.ShowOldExpansion.Other then
                    shouldShowExpansion = true
                end
            end

            if shouldShowExpansion then
                mogStatus = "oldexpansion"
            end
        end
    end

    local isQuestItem = itemClassID == Enum.ItemClass.Questitem
    -- Items of any other class that an unfinished quest takes (a vendor drink, cloth, a crafted
    -- weapon). Applied after the type-specific status below, which would otherwise overwrite it.
    local hasQuestValue = false
    if CaerdonWardrobeConfig.Icon.ShowQuestItems then
        if isQuestItem then
            mogStatus = "quest"
        else
            local questItemInfo = self:GetQuestItemInfo()
            hasQuestValue = questItemInfo ~= nil and questItemInfo.hasQuestValue
        end
    end

    if caerdonType == CaerdonItemType.CompanionPet or caerdonType == CaerdonItemType.BattlePet then
        local petInfo =
            (caerdonType == CaerdonItemType.CompanionPet and itemData:GetCompanionPetInfo()) or
            (caerdonType == CaerdonItemType.BattlePet and itemData:GetBattlePetInfo())
        if (petInfo and petInfo.needsItem) or tooltipData.canLearn then
            if bindingResult.unusableItem then
                mogStatus = "other"
            else
                mogStatus = "own"
            end
        end
    elseif caerdonType == CaerdonItemType.Conduit then
        if bindingResult.needsItem then
            local conduitInfo = itemData:GetConduitInfo()
            if conduitInfo and conduitInfo.isUpgrade then
                mogStatus = "upgradeNonEquipment"
            else
                mogStatus = "own"
            end
        elseif tooltipData.canLearn then
            if bindingResult.skillTooLow then
                mogStatus = "lowSkill"
            else
                mogStatus = "own"
            end
        end
    elseif caerdonType == CaerdonItemType.Consumable then
        local consumableInfo = itemData:GetConsumableInfo()
        if consumableInfo.isNotReady then
            -- Transmog source data not yet available; defer to avoid caching a wrong result.
            isReady = false
            return isReady, "the collection's answer"
        end
        if consumableInfo.needsItem then
            -- Use canEquip instead of validForCharacter to handle ensembles with cross-class sources
            if consumableInfo.canEquip then
                mogStatus = "own"
            else
                mogStatus = "other"
            end
        elseif consumableInfo.lowSkillItem then
            mogStatus = "lowSkill"
        elseif consumableInfo.lowSkillPlusItem then
            mogStatus = "lowSkillPlus"
        elseif consumableInfo.otherNoLootItem then
            mogStatus = "otherNoLoot"
        elseif consumableInfo.ownPlusItem then
            -- Completionist - has collectible items for own class but not the primary purpose
            -- Example: Mail ensemble with cloak for a cloth wearer
            mogStatus = "ownPlus"
        elseif consumableInfo.otherNeedsItem then
            mogStatus = "other"
        elseif tooltipData.canCombine then
            mogStatus = "canCombine"
            if tooltipData.readyToCombine then
                mogStatus = "readyToCombine"
            end
            -- TODO: Keep an eye on this - should be able to incorporate info GetConsumableInfo as needed
            -- elseif tooltipData.canLearn then
            -- 	if bindingResult.skillTooLow then
            -- 		mogStatus = "lowSkill"
            -- 	else
            -- 		mogStatus = "own"
            -- 	end
        else
            mogStatus = "collected"
        end
    elseif caerdonType == CaerdonItemType.Currency then
        local currencyInfo = itemData:GetCurrencyInfo()
        if currencyInfo.needsItem then
            mogStatus = "own"
        elseif currencyInfo.otherNeedsItem then
            mogStatus = "other"
        end
    elseif caerdonType == CaerdonItemType.Housing then
        local housingInfo = itemData and itemData.GetHousingInfo and itemData:GetHousingInfo()
        if housingInfo then
            if housingInfo.isPending then
                -- Defer icon decisions until housing data finishes loading so we don't show locks erroneously.
                isReady = false
                return isReady, "housing data"
            end

            local isServiceItem = housingInfo.isServiceItem
            local isDye = housingInfo.isDye

            -- Dyes are one-time-use consumables, not collectible — skip icon entirely.
            if not isDye then
                local treatAsUnowned = housingInfo.isUnowned
                if isServiceItem and bindingResult and bindingResult.alreadyKnown then
                    -- A service item that teaches something (the Harvesting Hatchet's "Find
                    -- Lumber") and whose tooltip says the toon knows it: nothing to get from it,
                    -- wherever the copy lies. The counts cannot say that; a copy in the warband
                    -- bank is not even counted.
                elseif treatAsUnowned then
                    mogStatus = "own"
                else
                    local atCap = housingInfo.maxStack and housingInfo.maxStack > 0 and
                        housingInfo.totalOwned >= housingInfo.maxStack
                    if not atCap or housingInfo.totalOwned == 0 then
                        mogStatus = "housingOwned"
                    end
                end
            end
        end
    elseif caerdonType == CaerdonItemType.Equipment then
        local sameLevelBehavior = CaerdonWardrobeConfig.Icon.SameLevelBehavior or "none"
        local transmogInfo = itemData:GetTransmogInfo(linkTooltip)
        if transmogInfo then
            if transmogInfo.isNotReady then
                isReady = false
                if transmogInfo.comparedGearMissing then
                    -- "gear": what the equipment code asks the queue to listen for (ComparedPieceThere).
                    return isReady, "the data of gear it is compared with", "gear"
                end
                return isReady, "the collection's answer"
            end
            statusTransmogInfo = transmogInfo
            if transmogInfo.canEquipForPlayer == nil then
                transmogInfo.canEquipForPlayer = playerCanEquipItem
            end
            -- The red-text tooltip scan is authoritative for "can this toon equip it right now".
            -- The transmog source APIs report mail as usable for a low-level hunter (the class can
            -- eventually collect the appearance), so without this an unequippable piece gets an
            -- upgrade arrow. Level-only shortfalls keep the upgradeLowSkill path via hasMetRequirements.
            local isUpgrade = transmogInfo.isUpgrade
            if bindingResult.unusableItem then
                transmogInfo.canEquipForPlayer = false
                -- Said in its own field for the equal-level test here and in the drawing:
                -- canEquipForPlayer is read there with canEquip as its fallback, which is true
                -- for such a piece (the class can use it one day).
                transmogInfo.unusableNow = true
                if transmogInfo.hasMetRequirements then
                    isUpgrade = nil
                end
            end
            -- The upgrade verdict as it is used below, kept for the caller: when a look to learn
            -- ends up as the status, the icon still gets a small upgrade arrow on it.
            bindingResult.upgradeStatus = isUpgrade and
                (transmogInfo.hasMetRequirements and "upgrade" or "upgradeLowSkill") or nil
            if transmogInfo.isArtifactItem then
                isArtifactItem = true
            end
            -- An uncollected appearance the class can use while the collect APIs say "nobody can
            -- collect this": on WoW Forever, cloth on a hunter (Spellbinder Vest 2969, wearable,
            -- nothing red in the tooltip) and mail on a hunter under 40 (red armor type). That
            -- used to read as "collected" and then "sellable". Selling the piece to a vendor
            -- teaches the appearance straight away (confirmed in game on WoW Forever), so it is
            -- learnable now, whether or not the toon can wear it yet.
            --
            -- A piece the class has no proficiency for at all (a wand on a hunter, Blazing Wand
            -- 5212) is also learned by selling it: the source reports ItemProficiency and both
            -- collect APIs say no. The API names the reason itself, so no red text is required.
            -- It is "other", not "own": "own" is strictly for appearances this toon can transmog
            -- into, and a hunter never can use a wand's.
            local learnableLaterStatus
            if transmogInfo.validSourceNotCollectable then
                if not transmogInfo.validSourceNotCollectableKnownLook then
                    learnableLaterStatus = "own"
                elseif CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem then
                    learnableLaterStatus = "ownPlus"
                end
            elseif transmogInfo.proficiencySourceNotCollectable then
                if not transmogInfo.proficiencySourceNotCollectableKnownLook then
                    learnableLaterStatus = "other"
                elseif CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem then
                    learnableLaterStatus = "otherPlus"
                end
            end
            -- Where a piece whose own look is known is taken for a look it would gain: raised
            -- on its upgrade track, or converted at the Catalyst (CaerdonTransformLooks). nil
            -- where there is none. Kept on the transmog info (transformLook, with route and
            -- secondRoute) for the drawing, which has an icon for each of the two places,
            -- and for the export.
            --
            -- Where the player does not want these marked (Icon.ShowLooksAfterChange), nothing
            -- is asked. Nor for a gear set's piece: the set keeps it from being sold and it
            -- shows the set's own mark. It is marked once it is out of every set (a set's
            -- change refreshes the icons).
            local function FindLookRoute()
                if CaerdonWardrobeConfig.Icon.ShowLooksAfterChange == false or itemData:GetEquipmentSets() then
                    return nil
                end
                -- What the client answered is kept with the verdict (transformLookWhy, and
                -- when): the export asks afresh, and what the client says then is not what
                -- it said when the verdict was made.
                local why = {}
                local transformLook = self:GetTransformLookInfo(transmogInfo.sourceID,
                    bindingResult.upgradeLevelDisabled, why)
                transmogInfo.transformLook = transformLook
                transmogInfo.transformLookWhy, transmogInfo.transformLookAt = why, GetTime()
                if transformLook and transformLook.pending then
                    -- What it waits for, where the look's code names it (a key), else true.
                    lookPending = transformLook.pending
                    return nil
                end
                -- The Catalyst's answer is for this toon. A look gained by raising the piece
                -- counts where the toon's class can use it.
                local route, secondRoute = CaerdonTransformLooks:GetRoute(transformLook,
                    CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem, transmogInfo.canEquip)
                if route then
                    transformLook.route, transformLook.secondRoute = route, secondRoute
                end
                return route
            end
            if transmogInfo.isTransmog then
                if transmogInfo.needsItem then
                    -- A look the toon can collect is one to learn now, whatever the piece asks
                    -- for (a level, a standing): selling the piece to a vendor teaches its look,
                    -- with nothing put on, in both clients (author decision, 2026-11-19, from
                    -- play; no export shows a sale of a piece above the toon's level, and one
                    -- that taught nothing would bring "lowSkill" back here). Until then such a
                    -- look was one for later, the gear, by its level or any red line.
                    if not transmogInfo.isCompletionistItem then
                        mogStatus = "own"
                    elseif CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem then
                        mogStatus = "ownPlus"
                    end
                elseif transmogInfo.otherNeedsItem then
                    -- Another toon can learn it. isCompletionistItem here: the look is already
                    -- known from a source this toon cannot use, which is the best sign there is
                    -- that the toon who would learn this one has the look. That makes it a Plus
                    -- whether or not this toon could wear the piece (a shield on a mage used to
                    -- read "other" whatever was known). Known only from a source this toon can
                    -- use, it stays "other": the other toon may well not have the look.
                    if not transmogInfo.isCompletionistItem then
                        mogStatus = "other"
                    elseif CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem then
                        mogStatus = "otherPlus"
                    end
                elseif learnableLaterStatus then
                    mogStatus = learnableLaterStatus
                elseif isUpgrade then
                    if transmogInfo.hasMetRequirements then
                        mogStatus = "upgrade"
                    else
                        mogStatus = "upgradeLowSkill"
                    end
                    -- An upgrade stays one, and its arrow stands. Where the arrow is not
                    -- drawn (switched off, or not shown by a window) the drawing puts the
                    -- mark for a look to gain in its place, so that is worked out here too.
                    FindLookRoute()
                else
                    -- Not "lowSkill" for a known piece of a level the toon has not reached:
                    -- too much noise.
                    mogStatus = "collected"
                    -- The piece's own look is known. Raised on its upgrade track or converted
                    -- at the Catalyst it has another one, and where the collection lacks that
                    -- the piece is marked to be kept for it: "transform", a quiet mark, since
                    -- the look takes crests or a charge and may be a while off. Not "own",
                    -- which says "learn it now". It stands in place of "collected", so the
                    -- piece is not offered for sale.
                    if FindLookRoute() then
                        mogStatus = "transform"
                    end
                end
            elseif isUpgrade then
                if transmogInfo.hasMetRequirements then
                    mogStatus = "upgrade"
                else
                    mogStatus = "upgradeLowSkill"
                end
            else
                -- A piece with no look (a ring, a trinket, a relic, a thrown weapon) that is no
                -- upgrade: nothing to learn and nothing to gain. Not "lowSkill" where the toon
                -- has not its level yet (author decision): the gear is the star's stand-in for
                -- what can be learned later, and this piece has nothing to learn at any level.
                -- One that would be an upgrade then has the status above. A piece with a look
                -- that is known has no gear in that state either.
                mogStatus = "collected"
            end

            local equipmentSets = itemData:GetEquipmentSets()
            if equipmentSets then
                if #equipmentSets > 1 then
                    bindingStatus = "*" .. equipmentSets[1]
                else
                    bindingStatus = equipmentSets[1]
                end
            else
                -- A piece that does exactly what the equipped one does (same tooltip lines) is a
                -- duplicate: nothing to weigh, whatever the same-level setting says, and its use
                -- or equip effect is one the toon already has.
                local identicalToEquipped = transmogInfo and transmogInfo.identicalToEquipped
                local redundantForPlayer = transmogInfo and
                    (transmogInfo.uniqueUpgradeBlocked or transmogInfo.betterItemEquipped or identicalToEquipped)
                -- A piece the toon cannot wear now (red text: mail before the proficiency) is not
                -- kept for its equal item level: by the time it can be worn it has been outgrown.
                local canEquipEqualItem = transmogInfo and not transmogInfo.unusableNow and
                    (transmogInfo.canEquipForPlayer or transmogInfo.canEquip)
                local matchesCurrentSpec = transmogInfo and (transmogInfo.matchesLootSpec ~= false)
                local protectEqualItemLevel = false
                if sameLevelBehavior ~= "sellable" and transmogInfo and transmogInfo.equalItemLevelEquipped and
                    not identicalToEquipped and
                    canEquipEqualItem and
                    matchesCurrentSpec and
                    transmogInfo.hasMetRequirements then
                    protectEqualItemLevel = true
                end
                local equipLocation = self:GetEquipLocation()
                if equipLocation == "INVTYPE_TABARD" or equipLocation == "INVTYPE_BODY" then
                    protectEqualItemLevel = false
                end

                local hasUseEffect = self:GetHasUse()
                local preserveUtility = equipLocation == "INVTYPE_TABARD" and hasUseEffect
                local isLegendaryItem = itemRarity == Enum.ItemQuality.Legendary
                local preserveLegendary = isLegendaryItem and (hasUseEffect or bindingResult.hasEquipEffect)
                local hasTeleportUse = self:HasTeleportUse()
                local isCosmeticArmor = itemClassID == Enum.ItemClass.Armor and
                    itemSubClassID == Enum.ItemArmorSubclass.Cosmetic
                local preserveCosmeticEquipEffect = isCosmeticArmor and bindingResult.hasEquipEffect
                -- A fishing pole is a tool: it loses every item level comparison against a real
                -- weapon and has no use or equip effect line, yet fishing needs it.
                local isFishingPole = itemClassID == Enum.ItemClass.Weapon and
                    itemSubClassID == Enum.ItemWeaponSubclass.Fishingpole
                -- So is a tool of one of the toon's professions, which lives in the bags on a
                -- client without profession gear slots: a known tool or one the toon's recipes
                -- name (Mining Pick, Blacksmith Hammer), or a weapon that needs a profession
                -- skill the toon has (Arclight Spanner 6219, "Requires Engineering (50)").
                local isProfessionTool = (itemClassID == Enum.ItemClass.Weapon and
                    bindingResult.skillRequirementMet) or self:GetProfessionToolInfo() ~= nil
                local protectRecraftPotential = transmogInfo and transmogInfo.isRecraftable
                if protectRecraftPotential then
                    redundantForPlayer = false
                end
                -- An equip effect keeps a piece; an "Equip:" line that is only a stat (spell
                -- power on WoW Forever) does not, where a vendor pays for the piece. Without a
                -- vendor price it is kept as before: a quest's piece (Cursed Eye of Paleth
                -- 2944, traded in for the cleansed one) has none.
                local keptForEquipEffect = bindingResult.hasEquipEffectBeyondStats or
                    (bindingResult.hasEquipEffect and not (itemSellPrice and itemSellPrice > 0))
                -- A use keeps a piece, so that nothing fun or special is marked for sale. A use
                -- that has to be aimed at an enemy is a combat effect, outgrown like a stat,
                -- and does not. Kept whatever the use: a trinket and a piece that asks for a
                -- skill (an engineer's gadgets are aimed at enemies too), and a piece no vendor
                -- pays for (a quest's tool: Morbent's Bane 7297). The client is asked last.
                local keptForUseEffect = hasUseEffect and not (
                    equipLocation ~= "INVTYPE_TRINKET" and
                    not bindingResult.hasSkillRequirement and
                    itemSellPrice and itemSellPrice > 0 and
                    self:HasHostileUse())

                -- No exception for a piece that only has a level gain to show (the arrow for a
                -- higher item level switched off): the player said item level alone is no
                -- upgrade, so the piece is judged like any other that is none.
                if mogStatus == "collected" and
                    self:IsSellable() and
                    not isArtifactItem and
                    not isFishingPole and
                    not isProfessionTool and
                    not preserveLegendary and
                    not preserveUtility and
                    not preserveCosmeticEquipEffect and
                    not hasTeleportUse and
                    not protectEqualItemLevel and
                    not protectRecraftPotential and
                    (redundantForPlayer or (not keptForUseEffect and
                        not self:GetSetID() and
                        not keptForEquipEffect)) then
                    mogStatus = "sellable"
                end
            end
        end
    elseif caerdonType == CaerdonItemType.Mount then
        local mountInfo = itemData:GetMountInfo()
        if mountInfo.needsItem then
            local factionGroup = nil
            local playerFactionGroup = nil
            if mountInfo.isFactionSpecific then
                factionGroup = PLAYER_FACTION_GROUP[mountInfo.factionID]
                playerFactionGroup = UnitFactionGroup("player")
            end

            if (not itemMinLevel or playerLevel >= itemMinLevel) and (factionGroup == playerFactionGroup) then
                mogStatus = "own"
            else
                mogStatus = "other"
            end
        end
    elseif caerdonType == CaerdonItemType.Profession then
        local professionInfo = itemData:GetProfessionInfo()
        if professionInfo.needsItem then
            mogStatus = "needForProfession"
        end
    elseif caerdonType == CaerdonItemType.Quest then
        if tooltipData.canCombine then
            mogStatus = "canCombine"
            if tooltipData.readyToCombine then
                mogStatus = "readyToCombine"
            end
        end
    elseif caerdonType == CaerdonItemType.Recipe then
        if tooltipData.canCombine then
            mogStatus = "canCombine"
            if tooltipData.readyToCombine then
                mogStatus = "readyToCombine"
            end
        elseif bindingResult.needsItem then
            if bindingResult.unusableItem then
                if bindingResult.skillTooLow then
                    mogStatus = "lowSkill"
                end
                -- Don't show these for now
                -- mogStatus = "other"
            else
                mogStatus = "own"
            end

            -- Let's just ignore the Librams for now until I decide what to do about them
            if itemID == 11732 or
                itemID == 11733 or
                itemID == 11734 or
                itemID == 11736 or
                itemID == 11737 or
                itemID == 18332 or
                itemID == 18333 or
                itemID == 18334 or
                itemID == 21288 then
                if CaerdonWardrobeConfig.Icon.ShowOldExpansion.Usable then
                    mogStatus = "oldexpansion"
                else
                    mogStatus = nil
                end
            end
            -- else
            -- 	local recipeInfo = itemData:GetRecipeInfo()

            -- 	if tooltipData.canLearn then
            -- 		if bindingResult.skillTooLow then
            -- 			mogStatus = "lowSkill"
            -- 		else
            -- 			mogStatus = "own"
            -- 		end
            -- 	end
        else
            mogStatus = "collected"
        end
    elseif caerdonType == CaerdonItemType.Toy then
        local toyInfo = itemData:GetToyInfo()
        if toyInfo.needsItem then
            mogStatus = "own"
        else
            mogStatus = "sellable"
        end
    elseif tooltipData and tooltipData.canLearn then
        if bindingResult.skillTooLow then
            mogStatus = "lowSkill"
        else
            mogStatus = "own"
        end
    end

    if (mogStatus == nil or mogStatus == "") and self:IsEquippableJunk(bindingResult) then
        mogStatus = "sellable"
    end

    -- Bags (ordinary, reagent and profession bags, quivers) against the toon's own bag slots: one that
    -- belongs in a slot now (a slot it fits is empty or holds a bag it improves on) gets the
    -- learnable icon, wherever it is seen; one that would improve none of them, with every
    -- slot filled, is a spare to sell (the auction step below decides between the vendor and
    -- the auction house).
    if (mogStatus == nil or mogStatus == "" or mogStatus == "oldexpansion") and
        (itemClassID == Enum.ItemClass.Container or itemClassID == Enum.ItemClass.Quiver) then
        local bagInfo = self:GetBagSlotInfo()
        if bagInfo then
            if bagInfo.isUpgrade then
                -- A red class line (a soul bag on a priest) means this toon can never equip it.
                if CaerdonWardrobeConfig.Icon.ShowBagUpgrades ~= false and
                    not bindingResult.raceClassRestricted then
                    -- Any other red text in the tooltip: a level this toon has not reached yet.
                    mogStatus = bindingResult.unusableItem and "lowSkill" or "own"
                end
            elseif bagInfo.isSpare and CaerdonWardrobeConfig.Icon.ShowSpareBags ~= false and
                itemSellPrice and itemSellPrice > 0 and self:IsSellable() then
                mogStatus = "sellable"
            end
        end
    end

    -- Consumables this toon's class or race can never use (Scroll: STHENIC LUNATE 211855,
    -- "Classes: Mage" on a hunter): nothing to do with them here but sell, and the auction step
    -- below decides between the vendor and the auction house.
    if (mogStatus == nil or mogStatus == "" or mogStatus == "collected") and
        self:IsOtherClassConsumable(bindingResult) then
        mogStatus = "sellable"
    end

    -- Recipes this toon has no use for: one another toon can still learn gets the "send"
    -- icon, a known one nobody wants is sold or listed.
    if mogStatus == "collected" then
        mogStatus = self:GetUnneededRecipeStatus(bindingResult) or mogStatus
    end

    -- Food and drink the toon has outgrown: a better one of the same kind is in the bags.
    if caerdonType == CaerdonItemType.Consumable and CaerdonWardrobeConfig.Icon.ShowOutdatedFood and
        (mogStatus == nil or mogStatus == "" or mogStatus == "collected") then
        local foodDrinkInfo = self:GetFoodDrinkInfo()
        if foodDrinkInfo and foodDrinkInfo.isOutdated then
            mogStatus = "sellable"
        end
    end

    -- Ingredients this toon has no use for: one another toon's recipes take is one to send,
    -- one its own recipes have outgrown is sold or listed (docs/dev-notes.md, Ingredients).
    if mogStatus == nil or mogStatus == "" then
        mogStatus = self:GetIngredientStatus() or mogStatus
    end

    -- Quest value replaces the "nothing left to do with this" results, something to send to
    -- another toon, and anything to learn: the item has to be there at the turn-in, and the
    -- learnable icon is read as "sell it, use it or send it". An upgrade keeps its arrow; one
    -- that was also a look to learn gets the arrow as a badge on the quest icon (the drawing
    -- reads bindingResult.upgradeStatus).
    if hasQuestValue and (not mogStatus or mogStatus == "" or QUEST_REPLACES[mogStatus]) then
        mogStatus = "quest"
    end

    -- Auction value replaces "sellable" (the item is still one to get rid of, the icon just says
    -- the auction house pays enough more than a vendor to list it) and marks trade goods that
    -- have no status of their own. Anything with another status keeps it.
    if CaerdonWardrobeConfig.Icon.ShowAuctionValue then
        local isSellable = mogStatus == "sellable"
        -- A tool the toon's own recipes name (an enchanting rod) is not stock to list.
        -- Nor is an ingredient the toon keeps for its own recipes.
        local isPlainTradeGood = (mogStatus == nil or mogStatus == "") and
            (itemClassID == Enum.ItemClass.Tradegoods or isCraftingReagent) and
            self:GetProfessionToolInfo() == nil and not self:IsIngredientKeptFromAuction()
        if isSellable or isPlainTradeGood then
            local auctionInfo = self:GetAuctionValueInfo()
            if auctionInfo and auctionInfo.shouldAuction then
                -- "auction" still draws as sellable where the auction icon is off;
                -- "auctionGoods" draws nothing there.
                mogStatus = isSellable and "auction" or "auctionGoods"
            end
        end
    end

    if lookPending then
        -- Not ready, and nothing kept: the queue asks again, and the data is here by then.
        if CaerdonCounters.on then CaerdonCounters:Mark("look data not ready") end
        return false, "the Catalyst's answer", type(lookPending) == "string" and lookPending or nil
    end

    -- Everything up to here follows from the link and the toon, and is kept per link. What
    -- belongs to this copy in its bag slot is added after the lookup (GetCopyStatus).
    if statusCacheKey then
        statusCache[statusCacheKey] = {isReady, mogStatus, bindingStatus, bindingResult, statusTransmogInfo}
    end

    return isReady, self:GetCopyStatus(mogStatus, bindingResult), bindingStatus, bindingResult, statusTransmogInfo
end

function CaerdonItemMixin:GetItemData()
    if not self.caerdonItemData then
        local caerdonType = self:GetCaerdonItemType()

        if caerdonType == CaerdonItemType.BattlePet then
            self.caerdonItemData = CaerdonBattlePet:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.CompanionPet then
            self.caerdonItemData = CaerdonCompanionPet:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Conduit then
            self.caerdonItemData = CaerdonConduit:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Consumable then
            self.caerdonItemData = CaerdonConsumable:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Currency then
            self.caerdonItemData = CaerdonCurrency:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Housing then
            self.caerdonItemData = CaerdonHousing:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Equipment then
            self.caerdonItemData = CaerdonEquipment:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Mount then
            self.caerdonItemData = CaerdonMount:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Profession then
            self.caerdonItemData = CaerdonProfession:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Quest then
            self.caerdonItemData = CaerdonQuest:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Recipe then
            self.caerdonItemData = CaerdonRecipe:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Toy then
            self.caerdonItemData = CaerdonToy:CreateFromCaerdonItem(self)
        end
    end

    return self.caerdonItemData
end

function CaerdonItemMixin:GetForDebugUse()
    if self:GetItemLink() then
        local linkType, linkOptions, displayText = LinkUtil.ExtractLink(self:GetItemLink())
        local forDebugUse = CaerdonWardrobeConfig.Debug.Enabled and {
            linkType = linkType,
            linkOptions = linkOptions,
            linkDisplayText = displayText
        }

        return forDebugUse
    end
end
