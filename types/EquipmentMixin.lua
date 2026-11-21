local ADDON_NAME, NS = ...

CaerdonEquipment = {}
CaerdonEquipmentMixin = {}

local slotTable = {
    INVTYPE_HEAD = 1,
    INVTYPE_NECK = 2,
    INVTYPE_SHOULDER = 3,
    INVTYPE_BODY = 4,
    INVTYPE_CHEST = 5,
    INVTYPE_WAIST = 6,
    INVTYPE_LEGS = 7,
    INVTYPE_FEET = 8,
    INVTYPE_WRIST = 9,
    INVTYPE_HAND = 10,
    INVTYPE_FINGER = 11,
    INVTYPE_TRINKET = 13,
    INVTYPE_WEAPON = 16,
    INVTYPE_SHIELD = 17,
    INVTYPE_RANGED = 16,
    INVTYPE_CLOAK = 15,
    INVTYPE_2HWEAPON = 16,
    INVTYPE_BAG = 0,
    INVTYPE_TABARD = 19,
    INVTYPE_ROBE = 5,
    INVTYPE_WEAPONMAINHAND = 16,
    INVTYPE_WEAPONOFFHAND = 16,
    INVTYPE_HOLDABLE = 17,
    INVTYPE_AMMO = 0,
    INVTYPE_THROWN = 16,
    INVTYPE_RANGEDRIGHT = 16,
    INVTYPE_QUIVER = 0,
    INVTYPE_RELIC = 0
}

local dualSlotInventoryTypes = {
    INVTYPE_FINGER = { INVSLOT_FINGER1, INVSLOT_FINGER2 },
    INVTYPE_TRINKET = { INVSLOT_TRINKET1, INVSLOT_TRINKET2 }
}

-- Item types that go in the separate ranged slot on clients that have one (WoW Forever, classic
-- rules). Retail has no ranged slot: bows and guns are main-hand weapons there (slotTable).
local rangedSlotInventoryTypes = {
    INVTYPE_RANGED = true,
    INVTYPE_RANGEDRIGHT = true,
    INVTYPE_THROWN = true,
    INVTYPE_RELIC = true
}
local RANGED_SLOT = { INVSLOT_RANGED or 18 }

-- Asked on every lookup rather than once at load: the answer comes from the client's paper doll
-- state, which is not guaranteed to be ready while this file loads.
local function HasRangedSlot()
    return C_PaperDollInfo ~= nil and C_PaperDollInfo.IsRangedSlotShown ~= nil and
        C_PaperDollInfo.IsRangedSlotShown() == true
end

local singleSlotCache = {}
local offhandInventoryTypes = {
    INVTYPE_SHIELD = true,
    INVTYPE_HOLDABLE = true,
    INVTYPE_WEAPONOFFHAND = true
}

local twoHandedInventoryTypes = {
    [Enum.InventoryType.Index2HweaponType] = true,
    [Enum.InventoryType.IndexRangedType] = true,
    [Enum.InventoryType.IndexRangedrightType] = true,
    [Enum.InventoryType.IndexThrownType] = true
}

local twoHandedInventoryTypeNames = {
    INVTYPE_2HWEAPON = true,
    INVTYPE_RANGED = true,
    INVTYPE_RANGEDRIGHT = true,
    INVTYPE_THROWN = true
}

local GetEquippedGearSnapshot -- forward declaration; defined after NormalizeItemLevel/DetermineUniqueness

-- PVP item level floor extraction via tooltip text parsing.
-- PVP_ITEM_LEVEL_TOOLTIP is a Blizzard global format string for the
-- "Increases item level to a minimum of %d ..." tooltip line.
-- We build a locale-safe Lua pattern once at load time.
local pvpFloorPattern
if PVP_ITEM_LEVEL_TOOLTIP then
    local sample = PVP_ITEM_LEVEL_TOOLTIP:format(12345)
    sample = sample:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    pvpFloorPattern = sample:gsub("12345", "(%%d+)")
end

local function ExtractPvpFloorFromTooltip(tooltipData)
    if not pvpFloorPattern or not tooltipData or not tooltipData.lines then
        return nil
    end
    for _, line in ipairs(tooltipData.lines) do
        if line.leftText then
            local floor = line.leftText:match(pvpFloorPattern)
            if floor then
                return tonumber(floor)
            end
        end
    end
    return nil
end

local function GetPvpFloorForEquippedSlot(slotID)
    if not pvpFloorPattern or not C_TooltipInfo then
        return nil
    end
    local tooltipData = C_TooltipInfo.GetInventoryItem("player", slotID)
    return ExtractPvpFloorFromTooltip(tooltipData)
end

local function GetPvpFloorForItem(item)
    if not pvpFloorPattern or not C_TooltipInfo then
        return nil
    end
    local itemLocation = item:GetItemLocation()
    local tooltipData
    if itemLocation and itemLocation:HasAnyLocation() and itemLocation:IsValid() then
        if itemLocation:IsBagAndSlot() then
            local bag, slot = itemLocation:GetBagAndSlot()
            tooltipData = C_TooltipInfo.GetBagItem(bag, slot)
        elseif itemLocation:IsEquipmentSlot() then
            tooltipData = C_TooltipInfo.GetInventoryItem("player", itemLocation:GetEquipmentSlot())
        end
    end
    if not tooltipData then
        local itemLink = item:GetItemLink()
        if itemLink then
            tooltipData = C_TooltipInfo.GetHyperlink(itemLink)
        end
    end
    return ExtractPvpFloorFromTooltip(tooltipData)
end

-- PVP context detection (cached per invalidation cycle)
local cachedPvpContext = nil

local function ReadPvpContext()
    local _, instanceType = GetInstanceInfo()
    if instanceType == "pvp" or instanceType == "arena" then
        return true
    end
    if C_PvP and C_PvP.IsWarModeDesired and C_PvP.IsWarModeDesired() then
        return true
    end
    return false
end

local function IsInPvpContext()
    if cachedPvpContext == nil then
        cachedPvpContext = ReadPvpContext()
    end
    return cachedPvpContext
end

-- The answer as the client gives it now, not the one kept for the cycle: the refresh watcher
-- compares it to decide whether a change of the player's flags or of the world was one of this
-- (CaerdonRefresh.lua).
function CaerdonEquipment:ReadPvpContext()
    return ReadPvpContext()
end

-- Returns effective item levels for a candidate-vs-equipped comparison,
-- applying PVP scaling rules. When both pvpFloor args are nil, returns
-- base levels unchanged (backward compatible).
--
-- A floor counts only where the client applies it (IsInPvpContext). Two pieces that both
-- carry one used to be compared by their floors anywhere, which made a PVP ring of level 242
-- an upgrade of 13 over a worn PVP ring that is the higher of the two everywhere but in PVP.
local function GetEffectiveLevels(candidateBase, candidatePvpFloor, equippedBase, equippedPvpFloor)
    if IsInPvpContext() then
        local effCandidate = candidatePvpFloor and math.max(candidateBase or 0, candidatePvpFloor) or candidateBase
        local effEquipped = equippedPvpFloor and math.max(equippedBase or 0, equippedPvpFloor) or equippedBase
        return effCandidate, effEquipped
    else
        return candidateBase, equippedBase
    end
end

local function GetInventorySlotsForType(inventoryType)
    if not inventoryType then
        return nil
    end

    local dualSlots = dualSlotInventoryTypes[inventoryType]
    if dualSlots then
        return dualSlots
    end

    if rangedSlotInventoryTypes[inventoryType] and HasRangedSlot() then
        return RANGED_SLOT
    end

    local slotID = slotTable[inventoryType]
    if slotID then
        local cached = singleSlotCache[inventoryType]
        if not cached then
            cached = { slotID }
            singleSlotCache[inventoryType] = cached
        end
        return cached
    end
end

local function GetComparableItemLevel(itemLink, itemLocation)
    if not itemLink then
        return nil
    end

    local itemLevel
    if itemLocation and itemLocation:IsValid() and C_Item.DoesItemExist(itemLocation) then
        itemLevel = C_Item.GetCurrentItemLevel(itemLocation)
    end

    if not itemLevel or itemLevel <= 0 then
        itemLevel = select(1, C_Item.GetDetailedItemLevelInfo(itemLink))
        -- Guard against inflated item levels from old expansion items with
        -- scaling bonus IDs: C_Item.GetDetailedItemLevelInfo can return dramatically
        -- wrong values for these. Cross-check against GetItemInfo.
        if itemLevel then
            local baseItemLevel = select(4, C_Item.GetItemInfo(itemLink))
            if baseItemLevel and baseItemLevel > 0 and itemLevel > baseItemLevel * 2 then
                itemLevel = baseItemLevel
            end
        end
    end

    return itemLevel
end

-- Get the candidate item level for comparison, checking for override first (used by AH items)
local function GetCandidateItemLevel(item)
    -- Check for override first (set by Auction feature for correct AH item levels)
    if item.extraData and item.extraData.overrideItemLevel then
        return item.extraData.overrideItemLevel
    end

    return GetComparableItemLevel(item:GetItemLink(), item:GetItemLocation())
end

-- A piece known by a link that is not its own. The auction house's list of results names a
-- piece by its item key (item, level, suffix), and the link the client gives for that key is
-- the plain item's: at its own level, with the stats still to be rolled ("+55 Random Stat 1").
-- Whoever makes the item passes the level the piece has (extraData.overrideItemLevel: the
-- auction feature for a row, the tooltip code for a tooltip filled by item key). Where the
-- link's own level is another, nothing read off the link is the piece's, and Pawn's value of
-- it least of all: Pawn is not asked about such a piece, its item level decides, and it has no
-- scored line in a tooltip. Seen (retail 12.1.5.70961): a piece of 328 in the list, over a worn
-- 276, lost its arrow to Pawn's score of the plain item at 219.
--
-- A key's suffix is the same matter. Where the key names one ("of the Monkey") the row is that
-- one piece, with the suffix's stats, and the link the client gives for the key is the item's
-- without it: at the piece's own level, and with none of those stats. Whoever makes the item
-- passes the suffix and the name the piece has with it (extraData.keySuffix, keyName: the
-- auction house's own name for the key). A link of another name is not the piece's, and a
-- name that is not known counts as another. Seen (WoW Forever 1.60.1.70959): a leather helm
-- "of the Monkey", +17 Agility and +17 Stamina in its listing, was put to Pawn as the helm
-- with its armor alone, and leggings "of the Bandit" far above the worn pair had no arrow.
--
-- Returns whether, and by what: "level" or "suffix".
local function IsKnownByAnotherLink(item)
    local extraData = item.extraData
    if not extraData then
        return false
    end
    local pieceLevel = extraData.overrideItemLevel
    if pieceLevel then
        local linkLevel = GetComparableItemLevel(item:GetItemLink(), nil)
        if linkLevel ~= nil and linkLevel ~= pieceLevel then
            return true, "level"
        end
    end
    local suffix = extraData.keySuffix
    if type(suffix) == "number" and suffix ~= 0 then
        local keyName = extraData.keyName
        if type(keyName) ~= "string" or keyName == "" or keyName ~= item:GetItemName() then
            return true, "suffix"
        end
    end
    return false
end

-- Whether a higher item level alone makes a piece an upgrade: all there is without Pawn, and
-- the player's choice with it (Icon.ShowItemLevelUpgrades).
local function ItemLevelCounts()
    local iconConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon or nil
    return PawnShouldItemLinkHaveUpgradeArrowUnbudgeted == nil or not iconConfig or
        iconConfig.ShowItemLevelUpgrades ~= false
end

-- The level a piece asks for where the toon has not reached it, or nil: its upgrade is one to
-- come, and its tooltip lines say so (atLevel on an entry).
local function LevelToCome(item)
    local minLevel = item.GetMinLevel and item:GetMinLevel()
    local level = UnitLevel("player")
    if type(minLevel) == "number" and type(level) == "number" and minLevel > level then
        return minLevel
    end
    return nil
end

-- linkTooltip: the client's tooltip for the item's link, where the caller has it (the status
-- has just read it). The floor line is then taken from that answer and no tooltip is fetched:
-- a bag copy's slot and its link carry the same line. A worn piece is still asked by its slot.
local function GetCandidatePvpFloor(item, linkTooltip)
    if item.extraData and item.extraData.overrideItemLevel then
        return nil
    end
    if linkTooltip then
        local itemLocation = item:GetItemLocation()
        if not (itemLocation and itemLocation:IsEquipmentSlot()) then
            return ExtractPvpFloorFromTooltip(linkTooltip)
        end
    end
    return GetPvpFloorForItem(item)
end

local function IsTwoHandedMainHandEquipped()
    local snapshot = GetEquippedGearSnapshot()
    local mainHand = snapshot[INVSLOT_MAINHAND]
    if not mainHand then
        return false
    end

    if mainHand.inventoryType and twoHandedInventoryTypes[mainHand.inventoryType] then
        return true
    end

    if not mainHand.inventoryType and mainHand.link then
        local equipLoc = select(9, C_Item.GetItemInfo(mainHand.link))
        if equipLoc and twoHandedInventoryTypeNames[equipLoc] then
            return true
        end
    end

    return false
end

local function ShouldIgnoreEmptySlot(slotID, inventoryTypeName)
    if slotID ~= INVSLOT_OFFHAND then
        return false
    end

    if not offhandInventoryTypes[inventoryTypeName] then
        return false
    end

    if not IsTwoHandedMainHandEquipped() then
        return false
    end

    local snapshot = GetEquippedGearSnapshot()
    return not snapshot[INVSLOT_OFFHAND]
end

local function GetBlockedOffhandComparisonLevel()
    if not IsTwoHandedMainHandEquipped() then
        return nil, nil
    end

    local snapshot = GetEquippedGearSnapshot()
    local mainHand = snapshot[INVSLOT_MAINHAND]
    if not mainHand then
        return nil, nil
    end

    return mainHand.level, mainHand.pvpFloor
end

local function IsOffhandSlotBlocked(inventoryTypeName)
    return ShouldIgnoreEmptySlot(INVSLOT_OFFHAND, inventoryTypeName)
end

local function GetSlotUpgradeDiff(slotID, inventoryTypeName, candidateLevel, candidatePvpFloor)
    local snapshot = GetEquippedGearSnapshot()
    local equipped = snapshot[slotID]
    if equipped then
        if equipped.level then
            local effCandidate, effEquipped = GetEffectiveLevels(
                candidateLevel, candidatePvpFloor,
                equipped.level, equipped.pvpFloor
            )
            if effCandidate and effEquipped then
                return effCandidate - effEquipped
            end
        end
    else
        if ShouldIgnoreEmptySlot(slotID, inventoryTypeName) then
            local compLevel, compPvpFloor = GetBlockedOffhandComparisonLevel()
            if compLevel then
                local effCandidate, effEquipped = GetEffectiveLevels(
                    candidateLevel, candidatePvpFloor,
                    compLevel, compPvpFloor
                )
                if effCandidate and effEquipped then
                    return effCandidate - effEquipped
                end
            else
                return candidateLevel
            end
        else
            return candidateLevel
        end
    end
end

local function GetPlayerLootSpecID()
    -- Routed through CaerdonAPI: WoW Forever has no GetSpecialization global and no
    -- specializations, so this returns nil there and spec matching is skipped.
    local playerSpec = CaerdonAPI:GetPlayerSpecializationIndex()
    if not playerSpec then
        return nil
    end

    local playerSpecID = CaerdonAPI:GetSpecializationInfo(playerSpec, nil, nil, nil, UnitSex("player"))
    local lootSpecID = CaerdonAPI:GetLootSpecializationID()
    if lootSpecID == 0 or lootSpecID == nil then
        lootSpecID = playerSpecID
    end

    return lootSpecID
end

local function BuildUniqueCategoryKey(limitCategoryID, limitCategoryName, itemIDOrLink)
    if limitCategoryID and limitCategoryID ~= 0 then
        return "id:" .. limitCategoryID
    elseif limitCategoryName and limitCategoryName ~= "" then
        return "name:" .. limitCategoryName
    elseif itemIDOrLink then
        return "item:" .. tostring(itemIDOrLink)
    end
end

local function DetermineUniqueness(itemLinkOrID, itemID)
    local isUnique, limitCategoryName, limitCategoryCount, limitCategoryID = C_Item.GetItemUniquenessByID(itemLinkOrID)
    if not isUnique then
        return nil
    end

    local key = BuildUniqueCategoryKey(limitCategoryID, limitCategoryName, itemID or itemLinkOrID)
    if not key then
        return nil
    end

    return key, limitCategoryCount or 1
end

-- The item being judged, for the upgrade helpers below: its item level, its PVP floor (a line of
-- its tooltip) and its uniqueness. Each helper used to read these for itself, so one
-- GetTransmogInfo fetched the same tooltip up to four times. A candidate is made per call and
-- reads each of the three when a helper first asks, so what no helper asks about is never read.
-- linkTooltip: the tooltip of the item's link where the caller already has it, so the floor
-- costs no fetch (GetCandidatePvpFloor); without it one is fetched.
local function NewCandidate(item, linkTooltip)
    return { item = item, linkTooltip = linkTooltip }
end

local function CandidateLevel(candidate)
    if not candidate.levelRead then
        candidate.levelRead = true
        candidate.level = GetCandidateItemLevel(candidate.item)
    end
    return candidate.level
end

local function CandidatePvpFloor(candidate)
    if not candidate.pvpFloorRead then
        candidate.pvpFloorRead = true
        candidate.pvpFloor = GetCandidatePvpFloor(candidate.item, candidate.linkTooltip)
    end
    return candidate.pvpFloor
end

local function CandidateUniqueness(candidate)
    if not candidate.uniquenessRead then
        candidate.uniquenessRead = true
        local itemLink = candidate.item:GetItemLink()
        local itemID = candidate.item:GetItemID()
        if itemLink or itemID then
            candidate.uniqueCategoryKey, candidate.limitCategoryCount =
                DetermineUniqueness(itemLink or itemID, itemID)
        end
    end
    return candidate.uniqueCategoryKey, candidate.limitCategoryCount
end

local function GetUniqueUpgradeInfo(candidate)
    local item = candidate.item
    if not item or not item.GetItemID then
        return false, false, nil
    end

    local uniqueCategoryKey, limitCategoryCount = CandidateUniqueness(candidate)
    if not uniqueCategoryKey then
        return false, false, nil
    end

    limitCategoryCount = tonumber(limitCategoryCount) or 1
    local candidateLevel = CandidateLevel(candidate)
    local candidatePvpFloor = CandidatePvpFloor(candidate)
    local inventoryTypeName = item:GetInventoryTypeName()
    local inventorySlots = GetInventorySlotsForType(inventoryTypeName)
    local snapshot = GetEquippedGearSnapshot()
    local hasEmptyEquipSlot = false
    if inventorySlots then
        for _, equipSlotID in ipairs(inventorySlots) do
            if not snapshot[equipSlotID] then
                if not ShouldIgnoreEmptySlot(equipSlotID, inventoryTypeName) then
                    hasEmptyEquipSlot = true
                    break
                end
            end
        end
    end

    local equippedMatches = 0
    local equippedBetterOrEqual = 0
    local betterThanEquipped = false

    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local equipped = snapshot[slot]
        if equipped and equipped.categoryKey and equipped.categoryKey == uniqueCategoryKey then
            equippedMatches = equippedMatches + 1

            if equipped.level and candidateLevel then
                local effCandidate, effEquipped = GetEffectiveLevels(
                    candidateLevel, candidatePvpFloor,
                    equipped.level, equipped.pvpFloor
                )
                if effEquipped >= effCandidate then
                    equippedBetterOrEqual = equippedBetterOrEqual + 1
                else
                    betterThanEquipped = true
                end
            elseif equipped.level and not candidateLevel then
                equippedBetterOrEqual = equippedBetterOrEqual + 1
            end
        end
    end

    local minMatches = math.min(limitCategoryCount, equippedMatches)
    local uniqueUpgradeBlocked = equippedMatches >= limitCategoryCount and equippedBetterOrEqual >= minMatches
    local uniqueUpgradeCandidate = betterThanEquipped or (hasEmptyEquipSlot and equippedMatches < limitCategoryCount)

    return uniqueUpgradeBlocked, uniqueUpgradeCandidate, uniqueCategoryKey
end

local function NormalizeItemLevel(level)
    if not level then
        return nil
    end

    return math.floor(level + 0.5)
end

-- Transmog source API caches (invalidated via CaerdonEquipment:InvalidateCaches)
-- Exposed on CaerdonEquipment so ConsumableMixin can share them
local sourceInfoCache = {}
local appearanceSourcesCache = {}
CaerdonEquipment.sourceInfoCache = sourceInfoCache
CaerdonEquipment.appearanceSourcesCache = appearanceSourcesCache

-- Source item IDs whose ITEM_DATA_LOAD_RESULT came back as a failure this session
-- (e.g. unreleased variants sharing an appearance). Kept for the whole session and
-- deliberately not cleared by InvalidateCaches: the server won't start serving them.
local failedSourceItemLoads = {}
CaerdonEquipment.failedSourceItemLoads = failedSourceItemLoads

-- Item IDs the client answered "no such item" for (GET_ITEM_INFO_RECEIVED without success),
-- whoever asked. A look can list a source whose item this client cannot load, and the client does
-- not remember its own refusal: asked about such a source again it asks the server again, and the
-- refusal comes back as an event that other addons redraw on. So what the client said about such
-- a source the first time is kept across InvalidateCaches instead of being asked for after every
-- refresh. Kept for the session, like the table above, which holds the same finding made the other
-- way (a load that failed).
local refusedItems = {}
CaerdonEquipment.refusedItems = refusedItems

local function IsRefusedItem(itemID)
    return itemID ~= nil and (refusedItems[itemID] or failedSourceItemLoads[itemID]) or false
end

local refusalFrame = CreateFrame("Frame")
refusalFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
refusalFrame:SetScript("OnEvent", function(_, _, itemID, success)
    if itemID and not success then
        refusedItems[itemID] = true
    end
end)

-- Set when the collection changed: the next InvalidateCaches then keeps nothing, so a kept answer
-- never outlives a change of what is collected.
local collectionChanged = false

function CaerdonEquipment:NoteCollectionChanged()
    collectionChanged = true
end

-- Lazy-built snapshot of equipped gear data, shared by all upgrade helper functions.
-- Built once per invalidation cycle (equipment/transmog change), avoids repeated
-- ItemLocation creation and API calls across all bag items.
local equippedGearSnapshot = nil

-- Which equipment sets name which copy and which item link, and the GetTime() it was built at
-- (see BuildEquipmentSetIndex).
local equipmentSetIndex = nil
local equipmentSetIndexTime = nil

-- The toon's loadouts beside what it wears (its other specs, and the played spec's gear set),
-- with the Pawn scale and the gear each is compared against, built at the first piece that asks
-- and kept until the next refresh (GetLoadouts). What is in them follows from what is worn and
-- from the gear sets, so no refresh keeps them.
local loadoutCache = nil

-- What a spec nobody chose on the Icons page is taken as (ReadOtherSpecDefault), by spec index,
-- until the next refresh: it is asked for with every scale Pawn names for a piece. A gear set
-- assigned and a scale shown or hidden each bring a refresh.
local otherSpecDefaults = {}

-- Pawn's value of an item on a scale it does not show: scale name -> item link -> value (false:
-- Pawn had none). Pawn calculates such a value anew at every call, and a refresh asks for every
-- piece again, so it is kept here across refreshes. A link names the item with its enchant and
-- gems, and the value follows from those and the scale's weights alone, so it stands until Pawn
-- says its scales changed (OnPawnChanged).
local otherSpecValues = {}

-- Whether Pawn takes a piece's armor type for the class's own (IsArmorTypeRefused), by item
-- link. It follows from the item, the class and the level, so a refresh about the worn gear
-- keeps it.
local armorTypeVerdicts = {}

-- The icon of a gear set the client names none for (INV_Misc_QuestionMark).
local QUESTION_MARK_ICON = 134400

GetEquippedGearSnapshot = function()
    if equippedGearSnapshot then
        return equippedGearSnapshot
    end

    equippedGearSnapshot = {}
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local location = ItemLocation:CreateFromEquipmentSlot(slot)
        if location and location:IsValid() and C_Item.DoesItemExist(location) then
            local link = C_Item.GetItemLink(location)
            local id = C_Item.GetItemID(location)
            local level = GetComparableItemLevel(link, location)
            local categoryKey, limitCount = DetermineUniqueness(link or id, id)
            local pvpFloor = GetPvpFloorForEquippedSlot(slot)
            equippedGearSnapshot[slot] = {
                link = link,
                id = id,
                level = level,
                normalizedLevel = NormalizeItemLevel(level),
                pvpFloor = pvpFloor,
                categoryKey = categoryKey,
                limitCount = limitCount,
                inventoryType = C_Item.GetItemInventoryType(location),
            }
        end
    end

    return equippedGearSnapshot
end

-- For the test addon's recorder, which needs a run that asks the client for everything, as a
-- replay will. Nothing in play calls this.
function CaerdonEquipment:ForgetRefusedItems()
    wipe(refusedItems)
    wipe(sourceInfoCache)
end

-- changed: what the refresh is about (CaerdonWardrobe:RefreshItems), nil for anything.
--
-- "worn" (a piece put on or taken off, an equipment set, the PVP context): what is compared
-- with the worn gear is read again, and what the client said about the sources of a look
-- stands. A source's answer is about the collection and about what the toon is (class, race,
-- faction, level, skills), none of which a change of clothes is. A piece that is learned by
-- being put on sends a collection event, and that refresh keeps nothing. Unless the
-- collection has changed since the caches were last emptied: then this one keeps nothing.
function CaerdonEquipment:InvalidateCaches(changed)
    cachedPvpContext = nil
    equippedGearSnapshot = nil
    equipmentSetIndex = nil
    loadoutCache = nil
    wipe(otherSpecDefaults)
    if changed == "worn" and not collectionChanged then
        return
    end

    wipe(armorTypeVerdicts)
    if collectionChanged or not (next(refusedItems) or next(failedSourceItemLoads)) then
        wipe(sourceInfoCache)
    else
        for sourceID, info in pairs(sourceInfoCache) do
            if not IsRefusedItem(info.itemID) then
                sourceInfoCache[sourceID] = nil
            end
        end
    end
    collectionChanged = false
    wipe(appearanceSourcesCache)
end

local function HasBetterOrEqualEquippedItem(candidate)
    local inventoryType = candidate.item:GetInventoryTypeName()
    local inventorySlots = GetInventorySlotsForType(inventoryType)
    if not inventorySlots then
        return false
    end

    local candidateLevel = CandidateLevel(candidate)
    if not candidateLevel then
        return false
    end

    local candidatePvpFloor = CandidatePvpFloor(candidate)
    local snapshot = GetEquippedGearSnapshot()
    local filledSlots = 0
    local strictlyBetterCount = 0
    -- Second return value: whether PVP scaling took part in the comparison. Only then may the
    -- item-level verdict override Pawn, which does not know about PVP floors. It takes part
    -- where the client applies a floor and a piece has one; a floor on a piece worn outside
    -- PVP is a line of text.
    local floorsCount = IsInPvpContext()
    local pvpScalingInvolved = floorsCount and candidatePvpFloor ~= nil
    for _, slotID in ipairs(inventorySlots) do
        local equipped = snapshot[slotID]
        if equipped then
            filledSlots = filledSlots + 1
            if floorsCount and equipped.pvpFloor then
                pvpScalingInvolved = true
            end
            local effCandidate, effEquipped = GetEffectiveLevels(
                candidateLevel, candidatePvpFloor,
                equipped.level, equipped.pvpFloor
            )
            local normCandidate = NormalizeItemLevel(effCandidate)
            local normEquipped = NormalizeItemLevel(effEquipped)
            if normEquipped and normCandidate and normEquipped > normCandidate then
                strictlyBetterCount = strictlyBetterCount + 1
            end
        end
    end

    if filledSlots < #inventorySlots then
        return false, pvpScalingInvolved
    end

    return filledSlots > 0 and strictlyBetterCount == filledSlots, pvpScalingInvolved
end

local function HasEqualEquippedItemLevel(candidate)
    local inventoryType = candidate.item:GetInventoryTypeName()
    local inventorySlots = GetInventorySlotsForType(inventoryType)
    if not inventorySlots then
        return false
    end

    local candidateLevel = CandidateLevel(candidate)
    if not candidateLevel then
        return false
    end

    local candidatePvpFloor = CandidatePvpFloor(candidate)
    local snapshot = GetEquippedGearSnapshot()
    local uniqueCategoryKey, limitCategoryCount = CandidateUniqueness(candidate)
    local uniqueLimitedToOne = uniqueCategoryKey and (tonumber(limitCategoryCount) or 1) == 1
    local betterUniqueEquipped = false
    local hasEqualMatch = false
    -- Second return value: the slots whose piece ties, for IsIdenticalToTiedEquipped.
    local tiedSlots = nil
    for _, slotID in ipairs(inventorySlots) do
        local equipped = snapshot[slotID]
        if equipped and equipped.level then
            local effCandidate, effEquipped = GetEffectiveLevels(
                candidateLevel, candidatePvpFloor,
                equipped.level, equipped.pvpFloor
            )
            local normCandidate = NormalizeItemLevel(effCandidate)
            local normEquipped = NormalizeItemLevel(effEquipped)

            if normEquipped and normCandidate and normEquipped == normCandidate then
                hasEqualMatch = true
                tiedSlots = tiedSlots or {}
                tiedSlots[#tiedSlots + 1] = slotID
            end

            if uniqueLimitedToOne and not betterUniqueEquipped then
                if equipped.categoryKey and equipped.categoryKey == uniqueCategoryKey and
                    normEquipped and normCandidate and normEquipped > normCandidate then
                    betterUniqueEquipped = true
                end
            end
        end
    end

    if uniqueLimitedToOne and betterUniqueEquipped then
        return false
    end

    return hasEqualMatch, tiedSlots
end

-- "Same item level" only makes a piece worth keeping when it does something the equipped one
-- does not. Whether it does is read off the two tooltips: every line is compared as text except
-- the ones below, which say nothing about what a piece does when worn. That leaves armor, stats,
-- damage and speed, the slot and armor / weapon type, enchants, sockets, use / equip / proc
-- effects and set bonuses. An unknown line type is compared, so a doubt reads as "different" and
-- the piece keeps its protection.
local comparisonIgnoredLineTypes = {}
for _, lineTypeName in ipairs({ "Blank", "Separator", "ItemName", "ItemBinding", "SellPrice", "ItemLevel",
    "FlavorText", "UsageRequirement", "TradeTimeRemaining" }) do
    local lineType = Enum.TooltipDataLineType and Enum.TooltipDataLineType[lineTypeName]
    if lineType then
        comparisonIgnoredLineTypes[lineType] = true
    end
end
local comparisonEnchantLineType = Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemEnchantmentPermanent

-- "Durability 20 / 20" has no line type of its own and differs between armor types and
-- qualities without changing what the piece does.
local durabilityPattern
if DURABILITY_TEMPLATE then
    local sample = DURABILITY_TEMPLATE:format(12345, 67890)
    sample = sample:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    sample = sample:gsub("12345", "%%d+")
    sample = sample:gsub("67890", "%%d+")
    durabilityPattern = "^%s*" .. sample .. "%s*$"
end

-- The compared lines of an item link's tooltip, or nil when the tooltip has none (data not
-- loaded): two empty lists must never count as identical.
local function BuildComparisonLines(itemLink)
    if not itemLink or not C_TooltipInfo or not C_TooltipInfo.GetHyperlink then
        return nil
    end

    local data = C_TooltipInfo.GetHyperlink(itemLink)
    if not data or not data.lines then
        return nil
    end

    local lines = { hasEnchant = false }
    for _, line in ipairs(data.lines) do
        if not comparisonIgnoredLineTypes[line.type] then
            local left = line.leftText and tostring(line.leftText) or ""
            local right = line.rightText and tostring(line.rightText) or ""
            if (left ~= "" or right ~= "") and not (durabilityPattern and left:match(durabilityPattern)) then
                local isEnchant = comparisonEnchantLineType ~= nil and line.type == comparisonEnchantLineType
                if isEnchant then
                    lines.hasEnchant = true
                end
                lines[#lines + 1] = {
                    text = right ~= "" and (left .. " | " .. right) or left,
                    isEnchant = isEnchant,
                }
            end
        end
    end

    if #lines == 0 then
        return nil
    end
    return lines
end

-- True when the candidate's lines match the equipped piece's, in order. An enchant on the equipped
-- piece alone does not make the candidate worth keeping, so it is skipped when the candidate has
-- none; an enchant on the candidate always counts. Second return value: the first difference.
local function CompareComparisonLines(candidateLines, equippedLines)
    local skipEquippedEnchants = not candidateLines.hasEnchant
    local candidateIndex = 1
    for _, equippedLine in ipairs(equippedLines) do
        if not (skipEquippedEnchants and equippedLine.isEnchant) then
            local candidateLine = candidateLines[candidateIndex]
            if not candidateLine or candidateLine.text ~= equippedLine.text then
                return false, format('"%s" here, "%s" equipped',
                    candidateLine and candidateLine.text or "(no more lines)", equippedLine.text)
            end
            candidateIndex = candidateIndex + 1
        end
    end

    local extraLine = candidateLines[candidateIndex]
    if extraLine then
        return false, format('"%s" here, "(no more lines)" equipped', extraLine.text)
    end
    return true
end

-- The stat numbers themselves, from C_Item.GetItemStats (a table of stat key -> value). They are
-- checked next to the tooltip lines, not instead of them: the table has no weapon speed or damage
-- range, no use / equip / proc effect and no set bonus. False only when both items have a table
-- and the tables differ; no table for either leaves the verdict to the tooltip lines.
-- Second return value: the first difference, or what was compared.
local function GetItemStatTable(itemLink)
    if not itemLink or not C_Item.GetItemStats then
        return nil
    end
    local stats = C_Item.GetItemStats(itemLink)
    return type(stats) == "table" and stats or nil
end

local function CompareItemStatTables(candidateStats, equippedStats)
    if not candidateStats or not equippedStats then
        return true, "none from the API"
    end

    local count = 0
    for stat, value in pairs(candidateStats) do
        count = count + 1
        if equippedStats[stat] ~= value then
            return false, format("%s %s here, %s equipped", tostring(stat), tostring(value), tostring(equippedStats[stat]))
        end
    end
    for stat, value in pairs(equippedStats) do
        if candidateStats[stat] == nil then
            return false, format("%s nil here, %s equipped", tostring(stat), tostring(value))
        end
    end
    return true, format("%d the same", count)
end

-- True when every equipped piece that ties the candidate's item level (tiedSlots, from
-- HasEqualEquippedItemLevel) also does exactly what the candidate does: the same stat table and
-- the same tooltip lines. With two slots, a tie against a different piece in the other slot keeps
-- it a real choice. The equipped piece itself is never its own duplicate.
-- Second return value: the verdict per slot, for the Debug Frame export.
local function IsIdenticalToTiedEquipped(item, tiedSlots)
    if not tiedSlots then
        return false, nil
    end

    local itemLocation = item:GetItemLocation()
    if itemLocation and itemLocation:HasAnyLocation() and itemLocation:IsEquipmentSlot() then
        return false, "the item is the equipped piece"
    end

    local candidateLink = item:GetItemLink()
    local candidateLines = BuildComparisonLines(candidateLink)
    if not candidateLines then
        return false, "no tooltip lines for the item"
    end
    local candidateStats = GetItemStatTable(candidateLink)

    local snapshot = GetEquippedGearSnapshot()
    local identical = true
    local detail = nil
    for _, slotID in ipairs(tiedSlots) do
        local equipped = snapshot[slotID]
        if equipped and not equipped.comparisonLines then
            equipped.comparisonLines = BuildComparisonLines(equipped.link)
            equipped.comparisonStats = GetItemStatTable(equipped.link)
        end

        local slotDetail
        if not (equipped and equipped.comparisonLines) then
            identical = false
            slotDetail = "no tooltip lines for the equipped piece"
        else
            local sameStats, statDetail = CompareItemStatTables(candidateStats, equipped.comparisonStats)
            local sameLines, lineDifference = CompareComparisonLines(candidateLines, equipped.comparisonLines)
            if sameStats and sameLines then
                slotDetail = format("identical (stats: %s; tooltip lines: %d the same)", statDetail, #candidateLines)
            else
                identical = false
                slotDetail = "differs ("
                if not sameStats then
                    slotDetail = slotDetail .. "stats: " .. statDetail
                end
                if not sameLines then
                    slotDetail = slotDetail .. (sameStats and "" or "; ") .. "tooltip lines: " .. lineDifference
                end
                slotDetail = slotDetail .. ")"
            end
        end

        slotDetail = format("slot%d: %s", slotID, slotDetail)
        detail = detail and (detail .. "; " .. slotDetail) or slotDetail
    end

    return identical, detail
end

local function GetUpgradeItemLevelDelta(candidate)
    local inventoryType = candidate.item:GetInventoryTypeName()
    local inventorySlots = GetInventorySlotsForType(inventoryType)
    if not inventorySlots then
        return nil
    end

    local candidateLevel = CandidateLevel(candidate)
    if not candidateLevel then
        return nil
    end

    local candidatePvpFloor = CandidatePvpFloor(candidate)
    local snapshot = GetEquippedGearSnapshot()
    local uniqueCategoryKey, limitCategoryCount = CandidateUniqueness(candidate)
    local restrictToMatchingUnique = uniqueCategoryKey and (tonumber(limitCategoryCount) or 1) == 1
    local matchingUniqueSlots = nil
    if restrictToMatchingUnique then
        for _, slotID in ipairs(inventorySlots) do
            local equipped = snapshot[slotID]
            if equipped and equipped.categoryKey and equipped.categoryKey == uniqueCategoryKey then
                if not matchingUniqueSlots then
                    matchingUniqueSlots = {}
                end
                matchingUniqueSlots[slotID] = true
            end
        end
        if not matchingUniqueSlots then
            restrictToMatchingUnique = false
        end
    end

    local maxPositiveDiff = nil
    for _, slotID in ipairs(inventorySlots) do
        if not restrictToMatchingUnique or (matchingUniqueSlots and matchingUniqueSlots[slotID]) then
            local diff = GetSlotUpgradeDiff(slotID, inventoryType, candidateLevel, candidatePvpFloor)
            if diff and diff > 0 then
                if not maxPositiveDiff or diff > maxPositiveDiff then
                    maxPositiveDiff = diff
                end
            end
        end
    end

    if maxPositiveDiff then
        return math.floor(maxPositiveDiff + 0.5)
    end
end

-- Debug-only: what the upgrade helpers compared the candidate against, per equip slot.
local function BuildEquippedComparisonDebug(item)
    local inventoryTypeName = item:GetInventoryTypeName()
    local inventorySlots = GetInventorySlotsForType(inventoryTypeName)
    if not inventorySlots then
        return nil
    end

    local snapshot = GetEquippedGearSnapshot()
    local result = {}
    for _, slotID in ipairs(inventorySlots) do
        local equipped = snapshot[slotID]
        if equipped then
            result["slot" .. slotID] = format("%s (ilvl %s)", tostring(equipped.link), tostring(equipped.level))
        elseif ShouldIgnoreEmptySlot(slotID, inventoryTypeName) then
            result["slot" .. slotID] = "empty (ignored: two-hander equipped)"
        else
            result["slot" .. slotID] = "empty"
        end
    end
    return result
end

-- True when the candidate is a lower armor class (cloth < leather < mail < plate) than the piece
-- equipped in the slot it would replace. A lower armor class is never an upgrade on item level
-- alone; classic-era itemization in particular hands higher-ilvl cloth to leather and mail wearers.
local armorClassRank = {
    [Enum.ItemArmorSubclass.Cloth] = 1,
    [Enum.ItemArmorSubclass.Leather] = 2,
    [Enum.ItemArmorSubclass.Mail] = 3,
    [Enum.ItemArmorSubclass.Plate] = 4,
}

local function GetArmorClassRank(itemLink)
    if not itemLink then
        return nil
    end
    local classID, subclassID = select(12, C_Item.GetItemInfo(itemLink))
    if classID ~= Enum.ItemClass.Armor then
        return nil
    end
    return armorClassRank[subclassID]
end

local function IsLowerArmorClassThanEquipped(item)
    local candidateRank = GetArmorClassRank(item:GetItemLink())
    if not candidateRank then
        return false
    end

    local inventorySlots = GetInventorySlotsForType(item:GetInventoryTypeName())
    if not inventorySlots then
        return false
    end

    local snapshot = GetEquippedGearSnapshot()
    for _, slotID in ipairs(inventorySlots) do
        local equipped = snapshot[slotID]
        local equippedRank = equipped and GetArmorClassRank(equipped.link)
        if equippedRank and equippedRank > candidateRank then
            return true
        end
    end
    return false
end

-- Pawn changed what its verdicts are made from. The upgrade verdicts here read Pawn's scales,
-- their weights, which of them are shown and its record of the best items, and they are kept
-- with the status until the next refresh. Pawn sends no event for a change of those, but it
-- throws its own calculated values away: every function that edits a scale or switches one on
-- or off calls PawnResetTooltips, and a change of spec or a reset of its upgrade tracking
-- calls PawnInvalidateBestItems (read in Pawn 2.14.3). So those two are hooked. An import or
-- a reset calls them several times in a row, hence one refresh when the run is over.
local PAWN_CHANGE_DELAY = 0.2
local pawnChangeTimer
local function OnPawnChanged()
    if pawnChangeTimer then
        wipe(otherSpecValues)
        return
    end
    wipe(otherSpecValues)
    pawnChangeTimer = C_Timer.NewTimer(PAWN_CHANGE_DELAY, function()
        pawnChangeTimer = nil
        if CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
            CaerdonWardrobe:RefreshItems("pawn")
        end
    end)
end

-- Pawn's "Show item level upgrades" is read by the verdicts too, and its checkbox calls neither
-- of the two: it sets the value and calls PawnResetBags (read in Pawn 2.14.4). That function
-- also runs after every change of the worn gear, so it is no change by itself: the value is
-- compared with the one last seen, here and as a verdict reads it (NotePawnItemLevelOption).
local pawnItemLevelOption = nil
local function ReadPawnItemLevelOption()
    return PawnCommon ~= nil and PawnCommon.ShowItemLevelUpgrades and true or false
end
local function NotePawnItemLevelOption()
    if pawnItemLevelOption == nil and PawnCommon ~= nil then
        pawnItemLevelOption = ReadPawnItemLevelOption()
    end
end
local function OnPawnBagsReset()
    local now = ReadPawnItemLevelOption()
    if pawnItemLevelOption == nil then
        pawnItemLevelOption = now
    elseif pawnItemLevelOption ~= now then
        pawnItemLevelOption = now
        OnPawnChanged()
    end
end
-- Pawn is an optional dependency, so it has loaded before this file when it is installed.
if type(PawnResetTooltips) == "function" then
    hooksecurefunc("PawnResetTooltips", OnPawnChanged)
end
if type(PawnInvalidateBestItems) == "function" then
    hooksecurefunc("PawnInvalidateBestItems", OnPawnChanged)
end
if type(PawnResetBags) == "function" then
    hooksecurefunc("PawnResetBags", OnPawnBagsReset)
end

-- Pawn only counts a score at least 0.5% higher as an upgrade (PawnIsItemAnUpgrade).
local PAWN_UPGRADE_THRESHOLD = 1.005

-- True when Pawn has scored the candidate and every equipped piece it would replace, and no
-- visible scale rates the candidate higher. PawnShouldItemLinkHaveUpgradeArrow returns false both
-- for "scored, not better" and for "cannot judge" (trinkets, no scales, data not loaded), so the
-- scores are compared here the way Pawn does (unenchanted values, the weaker of two slots).
-- Anything short of a clear "not better" returns false, which leaves the item-level fallback on.
-- "Not better" includes "equal at nothing": when every visible scale scores both the candidate
-- and the equipped piece at zero, Pawn is saying neither has anything this toon's scales weigh
-- (two plain maces on a priest), and a higher item level in a stat the class does not use is not
-- an upgrade. Until 2026-11-14 that case counted as "no verdict" and item level decided.
-- ignoredScales (optional, scale name -> true) are left out: see GetPawnOffTreeScales.
-- Second return value: the per-scale numbers, for the Debug Frame export.
local function PawnPrefersEquipped(item, ignoredScales)
    if not (PawnGetItemData and PawnGetSingleValueFromItem and PawnIsScaleVisible and
        PawnGetItemDataForInventorySlot and PawnCommon and PawnCommon.Scales) then
        return false, "Pawn comparison API missing"
    end

    -- Pawn's own "Show item level upgrades" is not asked here: whether a higher item level
    -- outweighs Pawn's scores is the addon's setting (Icon.ItemLevelOverPawn, read by the caller).
    -- That option still changes what Pawn's arrow answers, which is Pawn's verdict.

    local inventoryTypeName = item:GetInventoryTypeName()
    if inventoryTypeName == "INVTYPE_TRINKET" then
        return false, "trinket (Pawn does not score trinkets)"
    end

    local inventorySlots = GetInventorySlotsForType(inventoryTypeName)
    if not inventorySlots then
        return false, "no equipment slot"
    end

    local ok, verdict, detail = pcall(function()
        local candidate = PawnGetItemData(item:GetItemLink())
        if not candidate or not candidate.Link then
            return false, "Pawn has no data for the item"
        end

        local equippedItems = {}
        for _, slotID in ipairs(inventorySlots) do
            local equipped, slotHadItem = PawnGetItemDataForInventorySlot(slotID, true)
            if equipped and equipped.Link then
                equippedItems[#equippedItems + 1] = equipped
            elseif slotHadItem then
                return false, "Pawn has no data for slot " .. slotID
            elseif not ShouldIgnoreEmptySlot(slotID, inventoryTypeName) then
                return false, "slot " .. slotID .. " is empty"
            end
        end
        if #equippedItems == 0 then
            return false, "nothing equipped to compare"
        end

        local scalesSeen, scalesCompared = 0, 0
        local parts = {}
        for scaleName in pairs(PawnCommon.Scales) do
            if PawnIsScaleVisible(scaleName) and not (ignoredScales and ignoredScales[scaleName]) then
                scalesSeen = scalesSeen + 1
                local _, candidateValue = PawnGetSingleValueFromItem(candidate, scaleName)
                if not candidateValue then
                    return false, "no candidate value for " .. scaleName
                end

                local lowestEquipped
                for _, equipped in ipairs(equippedItems) do
                    local _, equippedValue = PawnGetSingleValueFromItem(equipped, scaleName)
                    if not equippedValue then
                        return false, "no equipped value for " .. scaleName
                    end
                    if not lowestEquipped or equippedValue < lowestEquipped then
                        lowestEquipped = equippedValue
                    end
                end

                parts[#parts + 1] = format("%s: %.2f vs %.2f equipped", scaleName, candidateValue, lowestEquipped)
                if candidateValue > lowestEquipped * PAWN_UPGRADE_THRESHOLD then
                    return false, table.concat(parts, "; ")
                end
                -- Counted apart: a scale that values the equipped piece, and rates the candidate
                -- no higher, prefers what is equipped. One that values neither calls them equal.
                if lowestEquipped > 0 then
                    scalesCompared = scalesCompared + 1
                end
            end
        end

        if scalesSeen == 0 then
            return false, "no visible Pawn scale to compare on"
        end
        if scalesCompared == 0 then
            -- Reaching here means no scale rated the candidate above the equipped piece, and
            -- none rated the equipped piece above zero: both score nothing everywhere.
            return true, table.concat(parts, "; ") .. " (no visible scale values either item: equal for Pawn)"
        end
        return true, table.concat(parts, "; ")
    end)

    if not ok then
        return false, "error: " .. tostring(verdict)
    end
    return verdict == true, detail
end

-- Pawn numbers the scales it ships for clients without specializations by talent tree
-- ("Classic":HUNTER1 = Beast Mastery, 2 = Marksmanship, 3 = Survival). Druids are the exception:
-- 1 Balance, 2 Feral (Damage), 3 Feral (Tank), 4 Restoration over three trees.
local function PawnSpecIDsForTalentTree(classFile, treeIndex, treeCount)
    if classFile == "DRUID" and treeCount == 3 then
        if treeIndex == 2 then
            return { [2] = true, [3] = true }
        elseif treeIndex == 3 then
            return { [4] = true }
        end
    end
    return { [treeIndex] = true }
end

-- The visible Pawn scales written for a talent tree other than the one holding most of the toon's
-- points. Without specializations Pawn has no automatic mode: it shows a scale for every tree of
-- the class and its arrow API answers "an upgrade for any of them", so a Beast Mastery hunter gets
-- an arrow on gloves that only Survival's strength weight likes, and the pair the hunter is wearing
-- gets one right back once they are swapped.
--
-- With specializations (retail) Pawn shows the scale of the spec being played by itself, and a
-- player can make another spec's visible beside it. Then the same holds: the scales of the other
-- specs are the ones ignored. A scale's SpecID is the spec's index there, which is what
-- GetSpecialization answers (Pawn's own PawnGetDefaultScale fills it from that).
--
-- Returns nil (nothing to ignore) when no tree leads, no spec is chosen, or ignoring would leave
-- no visible scale. Only scales for the player's class that name a spec are ever ignored; custom
-- scales always count.
-- Second return value: the names of the scales ignored and kept, for the Debug Frame export.
--
-- With specializations, the spec being played is judged on its own scale whatever Pawn shows
-- (author decision). Pawn has a scale for every spec, shown or not, and scores an item on any
-- of them by name. So where no scale of the toon's own is shown (the played spec's is hidden in
-- Pawn, and no custom one is shown in its place), that hidden scale is the third return value,
-- { name, label }, for the worn gear's judge (GetWornJudge), and every other spec's shown scale is ignored
-- even though that leaves none. Without it a piece was judged by item level alone, or by the
-- other specs' scales as if they were the toon's own.
--
-- A gear set tied to a Pawn scale by the player (TiedSetScale, below) comes before spec and
-- tree: while that set is the one worn, its scale is the toon's own, shown in Pawn or not, and
-- every other scale of the class is another's. A scale tied to a gear set that is not the one
-- worn is that set's, whatever kind of scale it is, unless it is the toon's own as well: the
-- scale Pawn ships for the spec being played or the leading tree, not a copy of it.
local GetTiedScales

local function GetPawnOffTreeScales()
    if not (PawnCommon and PawnCommon.Scales and PawnIsScaleVisible) then
        return nil
    end

    -- The scale the worn gear set is tied to, and the scales tied to the toon's other sets.
    local tiedOwn, tiedElsewhere = GetTiedScales()
    local treeIndex, treeCount, specIndex
    if CaerdonAPI:GetTalentTrees() then
        local _
        treeIndex, _, _, treeCount = CaerdonAPI:GetPrimaryTalentTree()
    else
        -- 5 is the spec of a toon that has not chosen one.
        specIndex = CaerdonAPI:GetPlayerSpecializationIndex()
        if specIndex and (specIndex < 1 or specIndex > 4) then
            specIndex = nil
        end
    end
    if not treeIndex and not specIndex and not tiedOwn and not tiedElsewhere then
        return nil
    end

    local ok, offTree, detail, hiddenOwn = pcall(function()
        local _, classFile, classID = UnitClass("player")
        local specIDs = treeIndex and PawnSpecIDsForTalentTree(classFile, treeIndex, treeCount) or
            (specIndex and { [specIndex] = true }) or {}
        local ignored, ignoredNames, keptNames = {}, {}, {}
        -- The played spec's scale that Pawn ships (a provider's), where Pawn does not show it.
        local hidden
        for scaleName, scale in pairs(PawnCommon.Scales) do
            local label = scale.LocalizedName or scaleName
            local classScale = scale.ClassID == classID and type(scale.SpecID) == "number"
            -- The toon's own: the scale its worn gear set is tied to, where it is tied to one;
            -- else a scale of the spec being played or of the leading tree.
            local own
            if tiedOwn then
                own = scaleName == tiedOwn
            else
                own = classScale and specIDs[scale.SpecID] == true
                -- A scale tied to a gear set that is not the one worn is that set's. Pawn's
                -- own scale for the spec played or the leading tree stays the toon's, since
                -- the worn gear is judged on it whatever else is tied to it. A copy of it the
                -- player made keeps its class and spec in Pawn (Provider is what it loses),
                -- and is the set's. Seen (retail 12.1.5.70961): a copy of a druid's Guardian
                -- scale tied to a PVP set, and Pawn's verdict on it, against the worn gear,
                -- gave two rings in the bank the yellow arrow of an upgrade for what is worn.
                if own and scale.Provider == nil and tiedElsewhere ~= nil and tiedElsewhere[scaleName] == true then
                    own = false
                end
            end
            if PawnIsScaleVisible(scaleName) then
                if not own and (classScale or (tiedElsewhere ~= nil and tiedElsewhere[scaleName] == true)) then
                    ignored[scaleName] = true
                    ignoredNames[#ignoredNames + 1] = label
                else
                    keptNames[#keptNames + 1] = label
                end
            elseif tiedOwn then
                if own then
                    hidden = { name = scaleName, label = label, tied = true }
                end
            elseif specIndex and scale.ClassID == classID and scale.SpecID == specIndex and scale.Provider ~= nil and
                (not hidden or scaleName < hidden.name) then
                hidden = { name = scaleName, label = label }
            end
        end
        table.sort(ignoredNames)
        table.sort(keptNames)
        if hidden and hidden.tied then
            -- The player's own choice for the gear worn: scored beside whatever else counts.
            local scored = format("kept: %s; and %s is scored though Pawn hides it (the worn gear set is tied to it)",
                #keptNames > 0 and table.concat(keptNames, ", ") or "none shown", hidden.label)
            if #ignoredNames == 0 then
                return nil, scored, hidden
            end
            return ignored, format("ignored: %s; %s", table.concat(ignoredNames, ", "), scored), hidden
        end
        if #keptNames == 0 and hidden then
            local scored = format("kept: none shown, so %s is scored though Pawn hides it", hidden.label)
            if #ignoredNames == 0 then
                return nil, scored, hidden
            end
            return ignored, format("ignored: %s; %s", table.concat(ignoredNames, ", "), scored), hidden
        end
        if #ignoredNames == 0 or #keptNames == 0 then
            return nil
        end
        return ignored, format("ignored: %s; kept: %s", table.concat(ignoredNames, ", "), table.concat(keptNames, ", "))
    end)

    if not ok then
        return nil
    end
    return offTree, detail, hiddenOwn
end

-- Why a spec's upgrades are wanted or not while another is played, as the Debug Frame export
-- words it. The Icons page words the same reasons for the player (its switches' tooltips).
local OTHER_SPEC_REASONS = {
    chosen = "chosen",
    gearSet = "a gear set is assigned to it",
    pawnShown = "Pawn shows its scale",
    noGearSet = "no gear set is assigned to it",
    pawnAutomatic = "no gear set is assigned to it, and Pawn picks its scales by itself",
    pawnHidden = "no gear set is assigned to it, and Pawn does not show its scale",
    talentTrees = "no specs on this client",
}

-- What a spec nobody chose is taken as: wanted where the game or Pawn says the toon plays it.
--   A gear set is assigned to the spec. That is the clearest sign there is, and the set is what
--   a piece is scored against; without one the worn gear stands in, poorly.
--   Pawn shows the spec's scale and what it shows is the player's choice, which it is in its
--   manual mode. In its automatic mode Pawn shows the scale of the spec being played and hides
--   every other one by itself (PawnOnSpecChanged, read in Pawn 2.14.4), which says nothing about
--   what the player wants while another spec is played.
-- Second return value: why, as a key of OTHER_SPEC_REASONS.
local function ReadOtherSpecDefault(classID, specIndex)
    if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetForSpec and
        C_EquipmentSet.GetEquipmentSetForSpec(specIndex) ~= nil then
        return true, "gearSet"
    end
    if not (PawnCommon and PawnCommon.Scales and PawnIsScaleVisible) then
        return false, "noGearSet"
    end
    if type(PawnOptions) == "table" and PawnOptions.AutoSelectScales == true then
        return false, "pawnAutomatic"
    end
    local ok, shown = pcall(function()
        for scaleName, scale in pairs(PawnCommon.Scales) do
            if scale.ClassID == classID and scale.SpecID == specIndex and PawnIsScaleVisible(scaleName) then
                return true
            end
        end
        return false
    end)
    if ok and shown then
        return true, "pawnShown"
    end
    return false, "pawnHidden"
end

-- The spec's switch as the player left it: true, false, or nil for one never clicked.
local function ReadOtherSpecChoice(classFile, specIndex)
    local icon = type(CaerdonWardrobeCharacterConfig) == "table" and CaerdonWardrobeCharacterConfig.Icon
    local chosen = type(icon) == "table" and icon.OtherSpecs
    if type(chosen) == "table" then
        local choice = chosen[tostring(classFile) .. tostring(specIndex)]
        if choice == true or choice == false then
            return choice
        end
    end
    return nil
end

-- Whether the player wants upgrades for this spec of the toon's shown while another is played
-- (Icon.OtherSpecs in the toon's own settings, CaerdonWardrobeCharacterConfig: one switch per
-- spec of its class on the Icons page). A switch that was clicked stands. One that never was
-- follows the game and Pawn (ReadOtherSpecDefault). A client with talent trees in place of
-- specs has no such switches, and every scale Pawn shows there counts.
-- Second return value: why, as a key of OTHER_SPEC_REASONS.
local function IsOtherSpecWanted(classFile, specIndex)
    if CaerdonAPI:GetTalentTrees() then
        return true, "talentTrees"
    end
    local choice = ReadOtherSpecChoice(classFile, specIndex)
    if choice ~= nil then
        return choice, "chosen"
    end
    local default = otherSpecDefaults[specIndex]
    if not default then
        local _, _, classID = UnitClass("player")
        default = { ReadOtherSpecDefault(classID, specIndex) }
        otherSpecDefaults[specIndex] = default
    end
    return default[1], default[2]
end

-- For the Icons page: what a spec's switch shows until the player clicks it. Read anew, since
-- the page can be open with no refresh since a gear set was assigned.
function CaerdonEquipment:IsOtherSpecWantedByDefault(specIndex)
    local _, _, classID = UnitClass("player")
    return (ReadOtherSpecDefault(classID, specIndex))
end

-- For the Icons page's tooltips: whether the spec's switch is on, and why, as a key of
-- OTHER_SPEC_REASONS ("chosen" for a switch the player clicked). Read anew, like the default.
function CaerdonEquipment:GetOtherSpecChoice(specIndex)
    local _, classFile, classID = UnitClass("player")
    local choice = ReadOtherSpecChoice(classFile, specIndex)
    if choice ~= nil then
        return choice, "chosen"
    end
    return ReadOtherSpecDefault(classID, specIndex)
end

-- For the Debug Frame export: each spec of the toon's class, whether its upgrades are wanted
-- while another is played, and why. nil on a client without specs.
function CaerdonEquipment:GetOtherSpecChoiceDescription()
    if CaerdonAPI:GetTalentTrees() then
        return nil
    end
    local countSpecs = C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID
    local _, classFile, classID = UnitClass("player")
    local count = countSpecs and classID and countSpecs(classID) or 0
    if not classFile or count < 2 then
        return nil
    end
    local parts = {}
    for specIndex = 1, count do
        local wanted, why = IsOtherSpecWanted(classFile, specIndex)
        local _, name
        if GetSpecializationInfoForClassID then
            _, name = GetSpecializationInfoForClassID(classID, specIndex)
        end
        parts[#parts + 1] = format("%s %s (%s)", tostring(name or specIndex), wanted and "on" or "off",
            tostring(OTHER_SPEC_REASONS[why] or why))
    end
    return table.concat(parts, "; ")
end

-- True when Pawn calls the item an upgrade only for scales in offTreeScales, i.e. for a talent
-- tree the toon is not using. PawnIsItemAnUpgrade is what Pawn's arrow API and tooltip both use,
-- and it names the scales. Anything unclear returns false, which keeps Pawn's verdict.
-- Second return value: what Pawn said, for the Debug Frame export.
-- Third: the verdict stands for none of the scales named. Each is for a spec the player switched
-- off, or for one whose gear set decides in Pawn's place (setSpecs, from GetShownSetSpecs).
-- Fourth: the names of the scales it does stand for.
-- judgedScales (scale name -> true): the worn gear's own scale, and its scale for the off
-- hand's weapon, each where the addon has a verdict of its own for the piece (JudgeWorn);
-- and every scale that weighs ranged damage, for a ranged weapon of another kind than the
-- one worn (UnlikeRangedScales).
-- Pawn's word for such a scale is then left out: it is neither the toon's own upgrade nor
-- another spec's, and where Pawn named no other scale its verdict stands for none.
local NO_SCALES = {}
local function IsPawnUpgradeOffTreeOnly(item, offTreeScales, setSpecs, judgedScales)
    if not (PawnGetItemData and PawnIsItemAnUpgrade and PawnCommon) then
        return false, "Pawn upgrade API missing"
    end

    local ok, verdict, detail, noneStands, standing = pcall(function()
        local candidate = PawnGetItemData(item:GetItemLink())
        if not candidate or not candidate.Link then
            return false, "Pawn has no data for the item"
        end

        local upgradeInfo, itemLevelIncrease = PawnIsItemAnUpgrade(candidate)
        if PawnCommon.ShowItemLevelUpgrades and itemLevelIncrease ~= nil then
            return false, "item level upgrade (ShowItemLevelUpgrades on)"
        end
        if type(upgradeInfo) ~= "table" or #upgradeInfo == 0 then
            return false, "Pawn named no scale"
        end

        local names, standingNames = {}, {}
        local offTreeOnly = true
        -- Pawn named a scale that is not one the addon judged.
        local others = false
        local _, classFile = UnitClass("player")
        for _, upgrade in ipairs(upgradeInfo) do
            local name = upgrade.LocalizedScaleName or tostring(upgrade.ScaleName)
            names[#names + 1] = name
            if not (judgedScales and judgedScales[upgrade.ScaleName]) then
                others = true
                local offTree = offTreeScales[upgrade.ScaleName]
                if not offTree then
                    offTreeOnly = false
                end
                local scale = PawnCommon.Scales and PawnCommon.Scales[upgrade.ScaleName]
                local specIndex = scale and scale.SpecID
                -- A gear set decides in Pawn's place for the scale: by the scale's spec, or by
                -- its name where the player tied a set to it (a scale of the player's own has
                -- no spec).
                local decided = offTree and setSpecs ~= nil and (setSpecs[upgrade.ScaleName] == true or
                    (type(specIndex) == "number" and setSpecs[specIndex] == true))
                if not decided and (type(specIndex) ~= "number" or IsOtherSpecWanted(classFile, specIndex)) then
                    standingNames[#standingNames + 1] = name
                end
            end
        end
        if not others then
            return false, table.concat(names, ", "), true, ""
        end
        return offTreeOnly, table.concat(names, ", "), offTreeOnly and #standingNames == 0,
            table.concat(standingNames, ", ")
    end)

    if not ok then
        return false, "error: " .. tostring(verdict)
    end
    return verdict == true, detail, noneStands == true, standing
end

-- An upgrade for gear the toon keeps beside what it is wearing (Icon.ShowOtherSpecUpgrades).
--
-- What is worn is measured first, by everything above this. Beside it the toon has loadouts
-- (the author's word), each measured on its own:
--   Another of its specs. Pawn's own verdict is over the scales it shows, and in its automatic
--   mode that is the played spec's alone. Its values are not: PawnGetSingleValueFromItem scores
--   an item on any scale by name, shown or not (read in Pawn 2.14.4). So a piece is scored on
--   the other spec's scale and compared with what that spec wears: the gear set assigned to
--   the spec, or the worn gear where none is assigned or the set leaves the slot alone. Worn
--   gear is a poor stand-in (a tank's ring against a healer's scale), which is why the set
--   comes first, and why it also comes before Pawn's verdict where Pawn shows that spec's
--   scale: that verdict is against the worn gear (GetShownSetSpecs).
--   The spec being played, where a gear set is assigned to it and the set's piece is not the
--   one worn (a PVP set put on, or a piece put on that the set was not saved with): the set's
--   piece is then what a piece has to beat for that spec, whatever is worn in its place
--   (author decision: a piece that beats the set's is one to save into the set, or to buy).
--   Where the set's piece is the worn one it has been compared already.
--
-- No verdict for a loadout: a trinket (Pawn does not score them), a slot its set has empty or
-- whose piece is not to be found (the bank), a piece Pawn has no values for, the piece that is
-- the set's own, and what Pawn's own check refuses (IsArmorTypeRefused, IsWeaponKindRefused).
-- With two slots the weaker one is the one to beat, as Pawn has it.

-- The link of the piece at a gear set's location, as C_EquipmentSet.GetItemLocations gives it
-- (0: nothing in the slot, 1: the set leaves the slot alone, -1: the piece is missing).
-- Second return value: the piece is being worn.
local function LinkAtSetLocation(location)
    if type(location) ~= "number" or location <= 1 then
        return nil
    end
    local data = EquipmentManager_GetLocationData(location)
    if not data then
        return nil
    end
    local slot, bag = tonumber(data.slot), tonumber(data.bag)
    if data.isBank and not bag then
        return slot and GetInventoryItemLink("player", slot) or nil
    elseif data.isBank or data.isBags then
        if bag and slot then
            local itemLocation = ItemLocation:CreateFromBagAndSlot(bag, slot)
            if itemLocation:HasAnyLocation() and itemLocation:IsValid() then
                return C_Item.GetItemLink(itemLocation)
            end
        end
        return nil
    elseif data.isPlayer then
        return slot and GetInventoryItemLink("player", slot) or nil, true
    end
    return nil
end

-- The gear set the toon last put on, by the client's set ID, kept for the toon between sessions
-- (CaerdonRefreshData[realm][toon].chosenGearSet, beside what the refresh watcher keeps there).
-- nil for a toon the client has no name for yet. set: the ID to keep.
local function ChosenGearSet(set)
    local realm, toon = GetRealmName(), UnitName("player")
    if not realm or not toon or toon == UNKNOWNOBJECT then
        return nil
    end
    if set == nil then
        local byToon = type(CaerdonRefreshData) == "table" and CaerdonRefreshData[realm]
        local saved = type(byToon) == "table" and byToon[toon]
        return type(saved) == "table" and saved.chosenGearSet or nil
    end
    if type(CaerdonRefreshData) ~= "table" then
        CaerdonRefreshData = {}
    end
    if type(CaerdonRefreshData[realm]) ~= "table" then
        CaerdonRefreshData[realm] = {}
    end
    if type(CaerdonRefreshData[realm][toon]) ~= "table" then
        CaerdonRefreshData[realm][toon] = {}
    end
    CaerdonRefreshData[realm][toon].chosenGearSet = set
    return set
end

-- The client has put a gear set on (EQUIPMENT_SWAP_FINISHED, from the core): that set is the
-- one the player chose, until another is.
--[[static]]
function CaerdonEquipment:NoteGearSetPutOn(succeeded, setID)
    if succeeded and type(setID) == "number" then
        ChosenGearSet(setID)
    end
end

-- The gear set being worn (the author's "active set"), or nil: { id, name, icon }, and why.
-- The client keeps no such thing, and what is worn does not say: two sets of one toon often
-- share most of their pieces. So it is the set the player last put on (ChosenGearSet), which
-- stands while pieces are changed by hand: a piece put on that the set was not saved with
-- does not change which set that is. It is checked against the client at every reading:
--   The set chosen no longer exists, or none was ever noted (the addon was not running): the
--   set that is on in full, else the one with the largest share of its pieces on, above half.
--   The set chosen is not on in full and another one is: that one (the sets were changed
--   where the addon did not see it, or by hand, piece by piece).
-- Of equals the one named first counts (preferSetID: the played spec's own), then the first in
-- the client's list.
local function ReadActiveSet(preferSetID)
    if not (C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs and C_EquipmentSet.GetEquipmentSetInfo) then
        return nil
    end
    local chosenID = ChosenGearSet()
    local chosen, chosenInFull, inFull, most, mostShare
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
        local name, icon, _, isEquipped, numItems, numEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if name ~= nil then
            local set = { id = setID, name = name, icon = icon }
            if setID == chosenID then
                chosen, chosenInFull = set, isEquipped == true
            end
            if isEquipped == true and (not inFull or setID == preferSetID) then
                inFull = set
            end
            if type(numItems) == "number" and numItems > 0 and type(numEquipped) == "number" then
                local share = numEquipped / numItems
                if share > 0.5 and (not most or share > mostShare or (share == mostShare and setID == preferSetID)) then
                    most, mostShare = set, share
                end
            end
        end
    end
    if chosen and (chosenInFull or not inFull) then
        return chosen, "the set last put on"
    elseif inFull then
        return inFull, chosen and "on in full, where the set last put on is not" or "on in full"
    elseif most then
        return most, "most of its pieces are on"
    end
    return nil, "no gear set is mostly on"
end

-- The Pawn scale the player tied a gear set to (author decision). Gear sets are the one thing
-- both clients have: retail can tie a set to a specialization and WoW Forever to nothing, and
-- in neither can a set say which weights it is for (a PVP set, a set for the other half of a
-- toon that plays two trees). So a set is tied to a scale by the player, set by set, and that
-- is kept with the toon (CaerdonWardrobeCharacterConfig.Icon.GearSetScales: set ID -> scale
-- name). A set nobody tied is as it was: the scale of the spec the client ties it to, or none.
-- nil for a set nobody tied, and for a scale Pawn no longer has (second return value: that
-- scale's name, for the export).
local function TiedSetScale(setID)
    local icon = type(CaerdonWardrobeCharacterConfig) == "table" and CaerdonWardrobeCharacterConfig.Icon
    local tied = type(icon) == "table" and type(icon.GearSetScales) == "table" and icon.GearSetScales[setID]
    if type(tied) ~= "string" or tied == "" then
        return nil
    end
    if not (PawnCommon and PawnCommon.Scales and PawnCommon.Scales[tied]) then
        return nil, tied
    end
    return tied
end

-- Whether the player marked the gear set as one for PVP (the Icons page's row for it;
-- CaerdonWardrobeCharacterConfig.Icon.PvpSets: set ID -> true). Such a set is scored at PVP
-- levels in every context (author decision): it is kept for PVP, where its pieces count at
-- their floors, and outside PVP the client gives their own levels' stats, which made a piece
-- for the open world look like an upgrade over a set piece that is the higher one in PVP.
local function IsPvpSet(setID)
    local icon = type(CaerdonWardrobeCharacterConfig) == "table" and CaerdonWardrobeCharacterConfig.Icon
    local marked = type(icon) == "table" and icon.PvpSets
    return type(marked) == "table" and marked[setID] == true
end

-- Whether the player wants upgrades for a gear set shown while another is worn: the set's
-- switch on the Icons page (CaerdonWardrobeCharacterConfig.Icon.OtherSets: set ID -> false for
-- one switched off). It is for a set tied to a scale that no spec owns; a set the client ties
-- to a spec goes by that spec's switch (IsOtherSpecWanted). One never clicked is wanted: tying
-- the set to a scale is the sign.
local function IsOtherSetWanted(setID)
    local icon = type(CaerdonWardrobeCharacterConfig) == "table" and CaerdonWardrobeCharacterConfig.Icon
    local chosen = type(icon) == "table" and icon.OtherSets
    return not (type(chosen) == "table" and chosen[setID] == false)
end

-- A gear set that is deleted takes its tie and its switch with it: the client gives a deleted
-- set's ID to the next set made, which would come by a scale nobody chose for it. Both clients delete through
-- this one function (the confirm dialog's OnAccept). A set deleted where the addon was not
-- running keeps its tie, and the settings page shows it on the set that has the ID now.
-- The client refuses a secure hook on some functions and does not say which, so it is tried
-- protected: a refusal must not stop this file, and the export says how it went.
local deleteHooked = false
if C_EquipmentSet and type(C_EquipmentSet.DeleteEquipmentSet) == "function" then
    deleteHooked = pcall(hooksecurefunc, C_EquipmentSet, "DeleteEquipmentSet", function(setID)
        local icon = type(CaerdonWardrobeCharacterConfig) == "table" and CaerdonWardrobeCharacterConfig.Icon
        local ties = type(icon) == "table" and icon.GearSetScales
        if type(ties) == "table" and setID ~= nil then
            ties[setID] = nil
        end
        local wanted = type(icon) == "table" and icon.OtherSets
        if type(wanted) == "table" and setID ~= nil then
            wanted[setID] = nil
        end
        local marked = type(icon) == "table" and icon.PvpSets
        if type(marked) == "table" and setID ~= nil then
            marked[setID] = nil
        end
    end)
end

-- The gear sets tied to a scale, as loadouts (both clients; after the client's own ties have
-- been read, and what the set worn is).
--   The set being worn (loadouts.activeSet): what is worn is its loadout, on its scale, named
--   for the set. It is then not also a loadout kept beside what is worn; the played spec's own
--   set stays listed, since that one is only asked where its piece is not the one worn.
--   Any other set that no spec is tied to (specSets: set ID -> true): a loadout of its own,
--   measured against the set's pieces, unless the player switched it off (IsOtherSetWanted).
--   Its scale is the set's all the same (tiedScales, and tiedUnwanted for one switched off):
--   Pawn's verdict for it, which is against the worn gear, is not the worn gear's and does not
--   stand in the set's place. A set a spec is tied to is that spec's loadout already,
--   on the tied scale (GetLoadouts), and the spec's switch still says whether it is wanted.
--   A spec with no set of its own, whose scale a set is tied to, is no loadout beside that set.
-- wornScaleTied and tiedScales are for Pawn's verdict (GetPawnOffTreeScales).
local function AddTiedSets(loadouts, specSets)
    if not (C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs and C_EquipmentSet.GetEquipmentSetInfo) then
        return
    end
    local active = loadouts.activeSet
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
        local scaleName = TiedSetScale(setID)
        if scaleName then
            local scale = PawnCommon.Scales[scaleName]
            local colour = type(scale.Color) == "string" and #scale.Color == 6 and scale.Color or nil
            if active and active.id == setID then
                local was = loadouts.worn
                loadouts.wornRead = true
                loadouts.wornScaleTied = scaleName
                loadouts.worn = {
                    isWorn = true,
                    index = was and was.index or (100 + setID),
                    id = was and was.id or nil,
                    scale = scaleName,
                    label = scale.LocalizedName or scaleName,
                    activeName = active.name,
                    activeIcon = active.icon or QUESTION_MARK_ICON,
                    colour = colour,
                    own = false,
                    tied = true,
                    baseline = {},
                }
                for index = #loadouts, 1, -1 do
                    local other = loadouts[index]
                    if other.setID == setID and not other.own then
                        table.remove(loadouts, index)
                        if loadouts.bySpec[other.index] == other then
                            loadouts.bySpec[other.index] = nil
                        end
                    end
                end
            elseif not (specSets and specSets[setID]) and not IsOtherSetWanted(setID) then
                loadouts.tiedUnwanted = loadouts.tiedUnwanted or {}
                loadouts.tiedUnwanted[scaleName] = true
            elseif not (specSets and specSets[setID]) then
                local setName, setIcon = C_EquipmentSet.GetEquipmentSetInfo(setID)
                loadouts[#loadouts + 1] = {
                    index = 100 + setID,
                    scale = scaleName,
                    label = scale.LocalizedName or scaleName,
                    setID = setID,
                    setName = setName,
                    setIcon = setIcon,
                    colour = colour,
                    own = false,
                    tied = true,
                    baseline = {},
                }
            end
        end
    end
    local tiedScales
    for _, loadout in ipairs(loadouts) do
        if loadout.tied and loadout.setID then
            tiedScales = tiedScales or {}
            tiedScales[loadout.scale] = true
        end
    end
    for scaleName in pairs(loadouts.tiedUnwanted or {}) do
        tiedScales = tiedScales or {}
        tiedScales[scaleName] = true
    end
    loadouts.tiedScales = tiedScales
    -- A set tied to a scale speaks for that scale. A spec with no set of its own, whose scale
    -- it is, was measured against the worn gear for want of anything better: not beside the
    -- set, which would say the same piece twice, by two measures.
    local wornTied = loadouts.wornScaleTied
    for index = #loadouts, 1, -1 do
        local other = loadouts[index]
        if not other.setID and not other.tied and
            (other.scale == wornTied or (tiedScales ~= nil and tiedScales[other.scale] == true)) then
            table.remove(loadouts, index)
            if loadouts.bySpec[other.index] == other then
                loadouts.bySpec[other.index] = nil
            end
        end
    end
end

-- What is worn, as a loadout, on a client with talent trees (WoW Forever), which has no
-- specialization to go by. The tree with the most points is taken for what the toon plays
-- (author decision, for a start: a toon that plays two trees is not told, and a gear set
-- cannot be tied to a tree there; tying a gear set to a Pawn scale is to settle both, on both
-- clients). Its scale is the one Pawn ships for the class and that tree
-- (PawnSpecIDsForTalentTree). A feral druid's tree has two, damage and tank: of several the
-- one Pawn shows, then the lower number.
-- The worn gear is that tree's whatever gear set is on, unless the player tied that set to a
-- scale (AddTiedSets, which GetLoadouts calls next), and there is no other loadout but the
-- sets so tied: another tree's scale that Pawn shows colours the arrow as it did
-- (GetPawnOffTreeScales). Nothing where no tree leads (no points spent, or two trees tie) or
-- Pawn has no such scale.
local function ReadTalentTreeLoadout(loadouts, classFile, classID)
    loadouts.activeSet, loadouts.activeWhy = ReadActiveSet(nil)
    local treeIndex, treeName, _, treeCount = CaerdonAPI:GetPrimaryTalentTree()
    if not treeIndex then
        return
    end
    local specIDs = PawnSpecIDsForTalentTree(classFile, treeIndex, treeCount)
    local chosenName, chosen, chosenShown
    for scaleName, scale in pairs(PawnCommon.Scales) do
        if scale.ClassID == classID and scale.Provider ~= nil and type(scale.SpecID) == "number" and specIDs[scale.SpecID] then
            local shown = PawnIsScaleVisible ~= nil and PawnIsScaleVisible(scaleName) == true
            local better
            if not chosen then
                better = true
            elseif shown ~= chosenShown then
                better = shown
            elseif scale.SpecID ~= chosen.SpecID then
                better = scale.SpecID < chosen.SpecID
            else
                better = scaleName < chosenName
            end
            if better then
                chosenName, chosen, chosenShown = scaleName, scale, shown
            end
        end
    end
    if not chosen then
        return
    end
    loadouts.wornRead = true
    loadouts.worn = {
        isWorn = true,
        index = treeIndex,
        scale = chosenName,
        label = chosen.LocalizedName or chosenName,
        specName = treeName,
        colour = type(chosen.Color) == "string" and #chosen.Color == 6 and chosen.Color or nil,
        own = false,
        baseline = {},
    }
end

-- The toon's loadouts beside what it wears (see above):
-- { { index, id, scale, label, setID, setName, own, baseline = {} } ... }, by spec index, and
-- bySpec for the same by that index. own: the spec being played, which is listed only with a
-- gear set. For the item tooltip each also has its set's icon, its spec's name and icon and
-- its scale's colour in Pawn. Empty without Pawn, for a toon with no spec chosen, and on a
-- client with talent trees, which has what is worn alone (ReadTalentTreeLoadout).
--
-- worn (a field, not in the list): what is worn, as a loadout of the same shape, for the item
-- tooltip alone. Its scale is the played spec's, it has no set, so each slot's piece is the
-- worn one. It is there where the gear set being worn is the played spec's own, and carries
-- that set's name and icon (the worn gear is taken for the set, also where a piece of it was
-- never saved into the set), and where no gear set is being worn. Not where the set being
-- worn has no spec or another spec's: the played spec's scale is not that gear's, the addon
-- has no scale for it, and Pawn's own lines stand (author decision).
-- activeSet, activeWhy: what ReadActiveSet said, for the export.
local function GetLoadouts()
    if loadoutCache then
        return loadoutCache
    end
    local loadouts = { bySpec = {} }
    loadoutCache = loadouts
    if not (PawnCommon and PawnCommon.Scales and PawnGetItemData and PawnGetSingleValueFromItem) then
        return loadouts
    end
    local _, classFile, classID = UnitClass("player")
    if CaerdonAPI:GetTalentTrees() then
        ReadTalentTreeLoadout(loadouts, classFile, classID)
        AddTiedSets(loadouts, nil)
        table.sort(loadouts, function(a, b) return a.index < b.index end)
        return loadouts
    end
    local current = CaerdonAPI:GetPlayerSpecializationIndex()
    if not current or current < 1 or current > 4 then
        return loadouts
    end

    local setForSpec = C_EquipmentSet and C_EquipmentSet.GetEquipmentSetForSpec
    -- The sets the client ties to a spec: each is that spec's loadout and no other.
    local specSets = {}
    for specIndex = 1, 4 do
        local specSet = setForSpec and setForSpec(specIndex) or nil
        if specSet then
            specSets[specSet] = true
        end
    end
    for scaleName, scale in pairs(PawnCommon.Scales) do
        local specIndex = scale.SpecID
        if scale.ClassID == classID and scale.Provider ~= nil and type(specIndex) == "number" and
            specIndex == current and not loadouts.wornRead then
            loadouts.wornRead = true
            local ownSetID = setForSpec and setForSpec(specIndex) or nil
            local active, why = ReadActiveSet(ownSetID)
            loadouts.activeSet, loadouts.activeWhy = active, why
            if not active or active.id == ownSetID then
                local _, specName, specIcon
                if GetSpecializationInfoForClassID then
                    _, specName, _, specIcon = GetSpecializationInfoForClassID(classID, specIndex)
                end
                loadouts.worn = {
                    isWorn = true,
                    index = specIndex,
                    id = (CaerdonAPI:GetSpecializationInfo(specIndex)),
                    scale = scaleName,
                    label = scale.LocalizedName or scaleName,
                    specName = specName,
                    specIcon = specIcon,
                    activeName = active and active.name or nil,
                    activeIcon = active and (active.icon or QUESTION_MARK_ICON) or nil,
                    colour = type(scale.Color) == "string" and #scale.Color == 6 and scale.Color or nil,
                    own = false,
                    baseline = {},
                }
            end
        end
        if scale.ClassID == classID and scale.Provider ~= nil and type(specIndex) == "number" and
            not loadouts.bySpec[specIndex] then
            -- The spec being played is always wanted, and is a loadout only through its set.
            local own = specIndex == current
            local wanted = own or IsOtherSpecWanted(classFile, specIndex)
            local setID = wanted and setForSpec and setForSpec(specIndex) or nil
            if wanted and (not own or setID ~= nil) then
                local setName, setIcon
                if setID and C_EquipmentSet.GetEquipmentSetInfo then
                    setName, setIcon = C_EquipmentSet.GetEquipmentSetInfo(setID)
                end
                local _, specName, specIcon
                if GetSpecializationInfoForClassID then
                    _, specName, _, specIcon = GetSpecializationInfoForClassID(classID, specIndex)
                end
                local loadout = {
                    index = specIndex,
                    id = (CaerdonAPI:GetSpecializationInfo(specIndex)),
                    scale = scaleName,
                    label = scale.LocalizedName or scaleName,
                    setID = setID,
                    setName = setName,
                    setIcon = setIcon,
                    specName = specName,
                    specIcon = specIcon,
                    colour = type(scale.Color) == "string" and #scale.Color == 6 and scale.Color or nil,
                    own = own,
                    baseline = {},
                }
                -- The spec's set is tied to a scale by the player: that scale, and not the
                -- one Pawn ships for the spec.
                local tiedName = setID and TiedSetScale(setID) or nil
                if tiedName then
                    local tiedScale = PawnCommon.Scales[tiedName]
                    loadout.scale, loadout.label = tiedName, tiedScale.LocalizedName or tiedName
                    loadout.colour = type(tiedScale.Color) == "string" and #tiedScale.Color == 6 and tiedScale.Color or nil
                    loadout.tied = true
                end
                loadouts.bySpec[specIndex] = loadout
                loadouts[#loadouts + 1] = loadout
            end
        end
    end
    -- No scale of Pawn's for the spec being played: the set worn has not been read yet.
    if not loadouts.wornRead then
        loadouts.activeSet, loadouts.activeWhy = ReadActiveSet(setForSpec and setForSpec(current) or nil)
    end
    AddTiedSets(loadouts, specSets)
    -- A set marked for PVP: its loadout, and what is worn while it is the set worn.
    for _, loadout in ipairs(loadouts) do
        if loadout.setID and IsPvpSet(loadout.setID) then
            loadout.pvp = true
        end
    end
    if loadouts.worn and loadouts.activeSet and IsPvpSet(loadouts.activeSet.id) then
        loadouts.worn.pvp = true
    end
    table.sort(loadouts, function(a, b) return a.index < b.index end)
    return loadouts
end

GetTiedScales = function()
    local loadouts = GetLoadouts()
    local own, tied = loadouts.wornScaleTied, loadouts.tiedScales
    -- A scale that is the worn set's own is not another set's for Pawn's verdict.
    if own and tied and tied[own] then
        local others
        for scaleName in pairs(tied) do
            if scaleName ~= own then
                others = others or {}
                others[scaleName] = true
            end
        end
        tied = others
    end
    return own, tied
end

-- The other specs with a gear set whose scale Pawn shows (offTreeScales, the shown scales of
-- the toon's other specs): spec index -> true, or nil. For those the set decides and Pawn's
-- verdict, which is against the worn gear, does not (author decision): the arrow for a spec is
-- "better than what that spec has", and with a set assigned the worn gear is not that. Showing
-- the scale is still the player's sign that the spec is wanted, so the set is asked for it
-- whatever Icon.ShowOtherSpecUpgrades says, as Pawn's verdict was.
--
-- A gear set tied to such a scale by the player decides in the same way: by its own index
-- for the loadouts asked, and by the scale's name for Pawn's verdict (IsPawnUpgradeOffTreeOnly).
local function GetShownSetSpecs(offTreeScales)
    local loadouts = GetLoadouts()
    local bySpec = loadouts.bySpec
    local found
    for scaleName in pairs(offTreeScales) do
        local scale = PawnCommon.Scales[scaleName]
        local loadout = scale and bySpec[scale.SpecID]
        if loadout and loadout.setID and not loadout.own then
            found = found or {}
            found[loadout.index] = true
        end
    end
    for _, loadout in ipairs(loadouts) do
        if loadout.tied and loadout.setID and not loadout.own and offTreeScales[loadout.scale] then
            found = found or {}
            found[loadout.index] = true
            found[loadout.scale] = true
        end
    end
    -- A set the player switched off: its scale is still the set's, so Pawn's verdict for it
    -- stands for nothing, and no loadout is asked in its place.
    for scaleName in pairs(loadouts.tiedUnwanted or {}) do
        if offTreeScales[scaleName] then
            found = found or {}
            found[scaleName] = true
        end
    end
    return found
end

-- Pawn's value of the item on the scale, from the values kept (otherSpecValues), or nil.
local function OtherSpecValue(scaleName, link)
    local values = otherSpecValues[scaleName]
    if not values then
        values = {}
        otherSpecValues[scaleName] = values
    end
    local value = values[link]
    if value == nil then
        value = false
        local data = PawnGetItemData(link)
        if data and data.Link then
            local _, unenchanted = PawnGetSingleValueFromItem(data, scaleName)
            if unenchanted then
                value = unenchanted
            end
        else
            -- Pawn has nothing for the item yet: asked again the next time, not kept.
            CaerdonCounters:NoteWithoutData("Pawn's value of a piece", link, C_Item.GetItemInfo(link) == nil)
            return nil
        end
        values[link] = value
    end
    return value or nil
end

-- A piece at the level its PVP floor raises it to, as a link Pawn can score.
--
-- The client gives a piece's stats for its link, and those are its own level's in every
-- context: nothing it reports for a piece changes in War Mode. But one of a seasonal piece's
-- bonus IDs carries its level (left out, the piece answers with its base level), the IDs near
-- it are the season's other levels, and the piece's link with one of those in its place is the
-- piece at that level, stats and all. The client answers the level of any link at once
-- (C_Item.GetDetailedItemLevelInfo) and ignores a bonus it does not know, so the ID for a
-- level is found by asking, with no table of seasons. The level an ID gives is the same on
-- every item seen, so what one piece taught is tried first on the next, and checked.
-- Seen (retail 12.1.5.70961): a head piece of level 276 with a floor of 298, bonus 12798
-- (44 without it), is 298 with 12831 in its place, Agility 110 to 135; an honor belt of level
-- 250 with a floor of 285, bonus 12782, is 285 with 12805. A crafted piece carries its level
-- in two IDs; both go, and one of the season's takes their place.
-- Not known: that the game's raising of a piece in a battleground or an arena is the piece at
-- that level (expected). The character sheet in War Mode does not show it either way: the
-- secondary ratings are those of War Mode off, and the primary stat is higher by one factor
-- for all of the gear (notes: Upgrades).
--
-- A season has more than one run of such IDs, and an ID of one run can be wrong for a piece
-- of another: a rare honor ring of level 263 with a floor of 331 has 13650, no ID within 120
-- of that gives 331, and the one that does elsewhere (12853) makes the ring epic. So which
-- IDs give which level is the client's whole table, asked once a build in the background and
-- saved (CaerdonLevelBonuses.lua), and every ID it has for the floor is tried on the piece,
-- the nearest to the piece's own first. A link is used only where the client answers the
-- floor for it. One that leaves the piece its own quality comes first; where none does (that
-- ring: 12853 is the client's one ID for 331), one of another quality is taken, because
-- quality does not move a piece's stats and the link is only ever scored: the ring at its own
-- level by an ID that makes it epic has the stats it has as a rare, to the point, and at 331
-- by 12853 its stats lie on the line of the season's other levels.
--
-- PvpLinkOf(link): the link at its floor, and what was done ({ link, level, from, bonus, own,
-- quality and ownQuality where the link is of another quality });
-- the link itself where it has no floor above its level or no such link was found (pvpLinkWhy
-- says which; pvpLinkStuck for a piece that has a floor to reach and no link for it, which a
-- comparison must not then make with the other piece raised: SetPvpMode). Kept for the
-- session: all of it follows from the link and the client's data. A piece that found no link,
-- or one of another quality only, is asked again when the table has changed.
--
-- A piece the client cannot say enough about right now (no level or no item info for its
-- link, which happens for worn pieces too: seen, every worn piece at once, some seconds after
-- all of them had it) is neither: nothing is kept, it is asked again the next time, and until
-- then it counts as one with no link for its floor (pvpLinkUnready), because whether it has a
-- floor is not known. Taken for a piece without one, it would be scored as it is beside a
-- piece that was raised.
local pvpLinks, pvpLinkWhy, pvpLinkStuck, pvpLinkAt, pvpLinkNotes = {}, {}, {}, {}, {}
local pvpLinkUnready = {}
-- How many IDs of the table are tried on one piece before it is left as it is.
local MAX_LEVEL_BONUS_TRIES = 60

-- item:ID:enchant:gem:gem:gem:gem:suffix:unique:level:spec:modifiers:context:count:bonus...
local function ReadItemString(link)
    local itemString = type(link) == "string" and link:match("|H(item:[^|]*)|h") or nil
    if not itemString then
        return nil
    end
    local parts = { strsplit(":", itemString) }
    local count = tonumber(parts[14]) or 0
    local bonuses = {}
    for index = 1, count do
        bonuses[index] = parts[14 + index]
    end
    return parts, count, bonuses
end

local function LinkWithBonuses(link, parts, count, bonuses)
    local forged = {}
    for index = 1, 13 do
        forged[index] = parts[index] or ""
    end
    forged[14] = #bonuses > 0 and tostring(#bonuses) or ""
    for _, bonus in ipairs(bonuses) do
        forged[#forged + 1] = bonus
    end
    for index = 15 + count, #parts do
        forged[#forged + 1] = parts[index]
    end
    local forgedString = table.concat(forged, ":")
    return (link:gsub("|H(item:[^|]*)|h", function() return "|H" .. forgedString .. "|h" end, 1))
end

-- A link taken apart: its level, the bonus IDs that carry it (left out one at a time, the
-- level moves), the rest, and a function that makes the link with another ID in the carriers'
-- place. nil where the client has no level for the link, or it has no item string.
local function ReadLevelBonuses(link)
    local level = C_Item.GetDetailedItemLevelInfo(link)
    local parts, count, bonuses = ReadItemString(link)
    if not (level and parts) then
        return nil
    end
    local carriers, rest, place, said = {}, {}, nil, {}
    for index, bonus in ipairs(bonuses) do
        local others = {}
        for other, otherBonus in ipairs(bonuses) do
            if other ~= index then
                others[#others + 1] = otherBonus
            end
        end
        local without = C_Item.GetDetailedItemLevelInfo(LinkWithBonuses(link, parts, count, others))
        said[#said + 1] = format("%s -> %s", tostring(bonus), tostring(without))
        if without ~= level then
            carriers[#carriers + 1] = bonus
            place = place or (#rest + 1)
        else
            rest[#rest + 1] = bonus
        end
    end
    local read = { link = link, level = level, carriers = carriers, said = table.concat(said, ", ") }
    function read.With(bonus)
        local swapped = {}
        for index, restBonus in ipairs(rest) do
            if index == place then
                swapped[#swapped + 1] = tostring(bonus)
            end
            swapped[#swapped + 1] = restBonus
        end
        if not place or place > #rest then
            swapped[#swapped + 1] = tostring(bonus)
        end
        return LinkWithBonuses(link, parts, count, swapped)
    end
    read.without = C_Item.GetDetailedItemLevelInfo(LinkWithBonuses(link, parts, count, rest))
    return read
end

local function PvpLinkOf(link)
    local known = NS.LevelBonuses
    local kept = pvpLinks[link]
    if kept and (not kept.quality or pvpLinkAt[link] == (known and known:Version())) then
        return kept.link, kept
    elseif kept == false and (not pvpLinkStuck[link] or pvpLinkAt[link] == (known and known:Version())) then
        return link
    end
    if not (known and pvpFloorPattern and C_TooltipInfo and C_TooltipInfo.GetHyperlink and C_Item.GetDetailedItemLevelInfo) then
        return link
    end
    local level = C_Item.GetDetailedItemLevelInfo(link)
    if not (level and C_Item.GetItemInfo(link)) then
        -- The client does not have the item yet: asked again the next time.
        pvpLinkUnready[link] = true
        CaerdonCounters:NoteWithoutData("a piece's PVP floor", link, true)
        return link
    end
    pvpLinkUnready[link] = nil
    local floor = ExtractPvpFloorFromTooltip(C_TooltipInfo.GetHyperlink(link))
    local function No(why, stuck)
        pvpLinks[link], pvpLinkWhy[link], pvpLinkStuck[link], pvpLinkAt[link] = false, why, stuck or nil, known:Version()
        return link
    end
    if not floor or floor <= level then
        return No(floor and "its floor is not above its level" or "no floor")
    end
    local read = ReadLevelBonuses(link)
    if not read then
        return No("the link has no item string", true)
    end
    local notes = { format("its bonus IDs, and its level without each: %s", read.said ~= "" and read.said or "none") }
    pvpLinkNotes[link] = notes
    if #read.carriers == 0 then
        return No("none of its bonus IDs carries its level", true)
    end
    local own = tonumber(read.carriers[1])
    -- The piece to ask the client with, should the table have to be made or carried on.
    local probe = { carrier = own, level = level, without = read.without, ask = function(id)
        return (C_Item.GetDetailedItemLevelInfo(read.With(id)))
    end }
    if known:IsScanning() then
        known:Need(probe)
        return No("the table of level IDs is being made", true)
    end
    -- A piece whose one level ID the table does not have: the client's data is not the table's.
    if own and #read.carriers == 1 and known:LevelOf(own) ~= level and known:Need(probe, "carrier") then
        return No("the table of level IDs is being made", true)
    end

    -- A link is one for the floor where the client answers the floor for it. The first that
    -- leaves the piece its own quality is taken; failing that, the first of another.
    local _, _, quality = C_Item.GetItemInfo(link)
    local candidates = known:IdsFor(floor, own) or {}
    local forged, found
    local other, otherBonus, otherQuality
    local passed = 0
    for index, bonus in ipairs(candidates) do
        if index > MAX_LEVEL_BONUS_TRIES then
            break
        end
        local tried = read.With(bonus)
        local triedLevel = C_Item.GetDetailedItemLevelInfo(tried)
        local _, _, triedQuality = C_Item.GetItemInfo(tried)
        if triedLevel == floor and (quality == nil or triedQuality == nil or triedQuality == quality) then
            forged, found = tried, bonus
            break
        end
        if triedLevel == floor and not other then
            other, otherBonus, otherQuality = tried, bonus, triedQuality
        end
        passed = passed + 1
        if passed <= 8 then
            notes[#notes + 1] = format("bonus %d, in the table for level %d, gives this piece level %s, quality %s (its own: %s)",
                bonus, floor, tostring(triedLevel), tostring(triedQuality), tostring(quality))
        end
    end
    if passed > 8 then
        notes[#notes + 1] = format("and %d more IDs of the table for that level, none of which did", passed - 8)
    end
    local asQuality
    if not forged and other then
        forged, found, asQuality = other, otherBonus, otherQuality
    end
    if not forged then
        if #candidates == 0 and known:Need(probe, "level", floor) then
            return No("the table of level IDs is being carried on", true)
        end
        return No(#candidates == 0 and format("no bonus ID in the table gives level %d", floor) or
            format("none of the %d bonus IDs in the table for level %d gives it that level", #candidates, floor), true)
    end
    kept = { link = forged, level = floor, from = level, bonus = found, own = table.concat(read.carriers, ", "),
        quality = asQuality, ownQuality = asQuality and quality or nil }
    pvpLinks[link], pvpLinkStuck[link], pvpLinkAt[link] = kept, nil, known:Version()
    return forged, kept
end

-- A piece that has a floor to reach and no link for it, or that the client cannot say enough
-- about to know.
local function IsPvpStuck(link)
    PvpLinkOf(link)
    return pvpLinkUnready[link] == true or (pvpLinks[link] == false and pvpLinkStuck[link] == true)
end

-- Pawn's value of a piece for the loadout: at its PVP floor where the loadout is a set marked
-- for PVP (loadout.pvp), the piece looked at and the set's own alike. A piece with no floor,
-- or none that a link can be made for, is valued as it is.
-- loadout.plain: for the comparison being made, every piece at its own level after all
-- (SetPvpMode).
local function LoadoutValue(loadout, scaleName, link)
    if loadout.pvp and not loadout.plain then
        link = PvpLinkOf(link)
    end
    return OtherSpecValue(scaleName, link)
end

-- What the loadout has in the slot and Pawn's value of it on its scale, or nil: { link, value,
-- fromSet (the set's piece, not the worn gear standing in), worn (it is being worn) }. Found
-- once per refresh. The set is asked where its pieces are as the slot is first needed, not when
-- the loadouts were listed: a piece moves in the bags without a refresh. For a slot the set
-- leaves alone the worn piece stands in.
-- offScale: the piece's value on the loadout's scale for the off hand's weapon instead
-- (OffHandScale), kept apart.
local function LoadoutBaseline(loadout, slotID, offScale)
    -- A set marked for PVP has its pieces' values twice: at their floors, and as they are
    -- (loadout.plain, for a comparison that cannot be made at the floors).
    local name = offScale and "offBaseline" or "baseline"
    if loadout.pvp and loadout.plain then
        name = offScale and "plainOffBaseline" or "plainBaseline"
    end
    local kept = loadout[name]
    if not kept then
        kept = {}
        loadout[name] = kept
    end
    local entry = kept[slotID]
    if entry == nil then
        entry = false
        local link, worn, fromSet
        local locations = loadout.setID and C_EquipmentSet.GetItemLocations(loadout.setID) or nil
        local location = locations and locations[slotID]
        if loadout.setID and location ~= 1 then
            link, worn = LinkAtSetLocation(location)
            fromSet = true
        else
            link, worn = GetInventoryItemLink("player", slotID), true
        end
        if link then
            local value = LoadoutValue(loadout, offScale or loadout.scale, link)
            if value then
                entry = { link = link, value = value, fromSet = fromSet or false, worn = worn or false }
            end
            -- A value at the floors is one only where the client could say what the piece's
            -- floor is: otherwise it is the piece as it is, and is not kept as the other.
            if loadout.pvp and not loadout.plain and pvpLinkUnready[link] then
                return entry or nil
            end
            -- The loadout's piece for the slot is there and has no value: kept so for the
            -- refresh, which leaves every piece for the slot without a verdict until the
            -- next. Counted where the reason is that the client has no item info for it.
            if not value and C_Item.GetItemInfo(link) == nil then
                CaerdonCounters:NoteWithoutData(worn and "a loadout's worn piece, kept as none for the refresh" or
                    "a gear set's piece, kept as none for the refresh", link, true)
            end
        end
        kept[slotID] = entry
    end
    return entry or nil
end

-- A comparison for a set marked for PVP is made at the floors only where every piece in it
-- that has a floor to reach has a link for it: the piece looked at and the loadout's pieces
-- for the slots. One raised and the other not is worse than neither (seen, retail
-- 12.1.5.70961: a ring of level 263 with a floor of 331 that no link was found for, scored at
-- 263 against a worn ring scored at its floor, came out as no upgrade). Where one of them is
-- stuck, the comparison is the one of every other set: each piece at its own level
-- (loadout.plain, until the next comparison sets it anew).
local function SetPvpMode(loadout, link, slots)
    if not loadout.pvp then
        return
    end
    local stuck = IsPvpStuck(link)
    for _, slotID in ipairs(slots or {}) do
        local entry = LoadoutBaseline(loadout, slotID)
        stuck = stuck or (entry ~= nil and IsPvpStuck(entry.link))
    end
    loadout.plain = stuck or nil
end

-- Two things Pawn's own upgrade check refuses before it compares a value (PawnIsItemAnUpgrade,
-- read in Pawn 2.14.4). The loadout scoring asks Pawn for values alone, so it applies them
-- itself; for a spec whose scale Pawn shows they were Pawn's until the spec's gear set took
-- that verdict's place.

-- Armor that is not the class's type (PawnIsArmorBestTypeForPlayer: cloth on a leather wearer
-- from the level the client penalises it). Asked of Pawn, whose rule it is, and kept by link
-- until a refresh that is not about the worn gear: it follows from the item, the class and the
-- level. No answer where Pawn has not read the item yet, and none is kept then.
local function IsArmorTypeRefused(link)
    if not PawnIsArmorBestTypeForPlayer then
        return false
    end
    local verdict = armorTypeVerdicts[link]
    if verdict == nil then
        local data = PawnGetItemData(link)
        if not (data and data.Link and data.UnenchantedStats) then
            return true
        end
        verdict = PawnIsArmorBestTypeForPlayer(data) and true or false
        armorTypeVerdicts[link] = verdict
    end
    return not verdict
end

-- Weapons, by the hands they take. The slot the client names for a type is one slot (slotTable
-- has the main hand for every one-hander, an off-hand weapon among them: right for an item
-- level, wrong for a toon that holds a weapon in each hand), so the scoring has its own model.
--   two:    both hands.
--   main:   the main hand.
--   either: the main hand, and the off hand as well for a toon that can hold a weapon in each
--           (CanDualWield, in both clients' listings).
--   off:    the off hand: a shield, a held item, an off-hand weapon.
-- The ranged weapons a client without a ranged slot puts in the main hand are none of these: a
-- bow is compared with what is in its slot, and not with a two-hander, as Pawn has it.
local HAND_KINDS = {
    INVTYPE_2HWEAPON = "two",
    INVTYPE_WEAPONMAINHAND = "main",
    INVTYPE_WEAPON = "either",
    INVTYPE_WEAPONOFFHAND = "off",
    INVTYPE_SHIELD = "off",
    INVTYPE_HOLDABLE = "off",
}
local MAIN_HAND, OFF_HAND = { INVSLOT_MAINHAND }, { INVSLOT_OFFHAND }
local BOTH_HANDS = { INVSLOT_MAINHAND, INVSLOT_OFFHAND }

local function CanWieldTwoWeapons()
    return CanDualWield ~= nil and CanDualWield() == true
end

-- Whether the scale puts a weapon in the off hand. A scale of Pawn's can leave that out: its
-- IsOffHand is set to "ignore" (PawnIgnoreStatValue). Its classic scales for a rogue's three
-- trees do, and come with a fourth scale for the off hand's weapon; so do those for a
-- protection warrior and paladin, who hold a shield there. Pawn then measures a one-hander
-- against the main hand's piece only (PawnIsItemAnUpgrade, read in Pawn 2.14.4), and so does
-- the addon: the off hand's weapon has a value on such a scale, as a main hand's, which says
-- nothing. A shield or a held item is another matter: the scale gives it a value or does not.
-- Seen (WoW Forever 1.60.1.70959, a rogue with two weapons): a dagger worth less than the main
-- hand's sword on the tree's scale was called an upgrade against the off hand's blade.
local function IsWeightIgnored(weight)
    return type(weight) == "number" and type(PawnIgnoreStatValue) == "number" and weight <= PawnIgnoreStatValue
end

local function ScaleTakesOffHand(scaleName)
    local scale = PawnCommon.Scales[scaleName]
    local values = scale and scale.Values
    return not IsWeightIgnored(type(values) == "table" and values.IsOffHand or nil)
end

-- What the scale is told not to show (its DoNotShow1HUpgrades / DoNotShow2HUpgrades, the
-- player's choice in Pawn), which Pawn's own check refuses before it compares a value.
local function IsWeaponKindRefused(loadout, inventoryTypeName)
    local kind = HAND_KINDS[inventoryTypeName]
    local scale = kind and PawnCommon.Scales[loadout.scale]
    if not scale then
        return false
    end
    if kind == "two" then
        return scale.DoNotShow2HUpgrades and true or false
    end
    return scale.DoNotShow1HUpgrades and true or false
end

-- The scale for the off hand's weapon that goes with a loadout's scale, or nil: { name, label,
-- refuses (it is told not to show one-handers) }. Pawn's classic scales for a rogue's three
-- trees put no weapon in the off hand (ScaleTakesOffHand) and come with a fourth for it,
-- "Rogue: Off Hand": a scale Pawn ships for the class and for no tree, which leaves out the
-- main hand's weapons (its MainHandDps is "ignore") as the trees' leave out the off hand's.
-- The two are one set of weights in two halves, a scale having one weight for a stat. So the
-- off hand's weapon is the addon's to score on that scale (author decision), and whether Pawn
-- shows it or not: a value is asked by the scale's name.
-- Found by that shape and not by a name, among whatever Pawn ships for the toon's class. Of
-- several the one from the provider of the loadout's own scale, then the first by name. Read
-- once for a loadout.
local function OffHandScale(loadout)
    local found = loadout.offScale
    if found == nil then
        found = false
        local own = PawnCommon.Scales[loadout.scale]
        local _, _, classID = UnitClass("player")
        if own and not ScaleTakesOffHand(loadout.scale) then
            local foundSame = false
            for scaleName, scale in pairs(PawnCommon.Scales) do
                local values = scale.Values
                if scaleName ~= loadout.scale and scale.ClassID == classID and scale.SpecID == nil and
                    scale.Provider ~= nil and type(values) == "table" and IsWeightIgnored(values.MainHandDps) and
                    ScaleTakesOffHand(scaleName) then
                    local same = scale.Provider == own.Provider
                    if not found or (same and not foundSame) or (same == foundSame and scaleName < found.name) then
                        found, foundSame = { name = scaleName, label = scale.LocalizedName or scaleName,
                            refuses = scale.DoNotShow1HUpgrades and true or false }, same
                    end
                end
            end
        end
        loadout.offScale = found
    end
    return found or nil
end

-- Whether a weapon is judged hand by hand for the loadout, each hand on its own scale: the
-- off hand's scale (OffHandScale), or nil. That is a one-hander for either hand and a weapon
-- for the off hand alone, for a toon that holds a weapon in each hand. Not where either scale
-- is told not to show one-handers.
local function HandsApart(loadout, inventoryTypeName)
    if inventoryTypeName ~= "INVTYPE_WEAPON" and inventoryTypeName ~= "INVTYPE_WEAPONOFFHAND" then
        return nil
    end
    if not CanWieldTwoWeapons() then
        return nil
    end
    local offScale = OffHandScale(loadout)
    if not offScale or offScale.refuses or IsWeaponKindRefused(loadout, inventoryTypeName) then
        return nil
    end
    return offScale
end

-- The one-handed pieces in the bags that the toon could hold, and their links as one text
-- (what the watch below compares). Pawn says whether the toon can equip a piece (CanEquip, from
-- its tooltip's red text); one it has not read yet is left out, and counts once it has. The
-- bags alone: what lies in the bank is not at hand.
local function ScanOneHanders()
    local list, links = {}, {}
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemLink and PawnGetItemData) then
        return list, ""
    end
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link then
                local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
                local kind = equipLoc and HAND_KINDS[equipLoc]
                if kind and kind ~= "two" then
                    local data = PawnGetItemData(link)
                    if data and data.Link and data.CanEquip ~= false then
                        list[#list + 1] = { link = link, kind = kind, offWeapon = equipLoc == "INVTYPE_WEAPONOFFHAND" }
                        links[#links + 1] = link
                    end
                end
            end
        end
    end
    table.sort(links)
    return list, table.concat(links, "\n")
end

-- Read once per refresh, and only when a piece is first weighed with a partner.
local function CarriedOneHanders()
    local loadouts = GetLoadouts()
    if not loadouts.oneHanders then
        loadouts.oneHanders, loadouts.oneHandersSignature = ScanOneHanders()
    end
    return loadouts.oneHanders
end

-- The best piece carried for the hand a one-hander leaves free, by its value on the loadout's
-- scale, and that value; nil where there is none. kind: the hands the piece itself takes.
-- Two weapons go together only for a toon that holds one in each hand, on a scale that puts a
-- weapon in the off hand (takesOff), and then one of them has to be for either hand; a shield
-- or a held item goes beside any main hand's weapon, where the scale gives it a value.
local function BestPartner(loadout, kind, link, takesOff)
    local dual = CanWieldTwoWeapons()
    local best, bestValue
    for _, carried in ipairs(CarriedOneHanders()) do
        if carried.link ~= link then
            local fits
            if kind == "off" then
                fits = carried.kind ~= "off"
            elseif carried.kind == "off" then
                fits = not carried.offWeapon or (dual and takesOff)
            else
                fits = dual and takesOff and (kind == "either" or carried.kind == "either")
            end
            if fits then
                local value = LoadoutValue(loadout, loadout.scale, carried.link)
                if value and value > 0 and (not bestValue or value > bestValue) then
                    best, bestValue = carried, value
                end
            end
        end
    end
    return best, bestValue
end

-- A one-hander's verdict against a two-hander goes by what else is carried, and when a bag
-- changes only the slot that changed is drawn again: where the one-handers carried are not the
-- ones read, everything is.
local partnerFrame = CreateFrame("Frame")
partnerFrame:RegisterEvent("BAG_UPDATE_DELAYED")
partnerFrame:SetScript("OnEvent", function()
    local loadouts = loadoutCache
    if not (loadouts and loadouts.oneHanders) then
        -- No piece was weighed with a partner since the last refresh: nothing can be stale.
        return
    end
    local _, signature = ScanOneHanders()
    if signature ~= loadouts.oneHandersSignature and CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
        CaerdonWardrobe:RefreshItems("weapons carried", nil, "worn")
    end
end)

-- How a weapon is weighed against what a loadout holds in its hands (author decision: a pair
-- of one-handers is weighed against a two-hander, which Pawn refuses to compare).
--   "slots", the slots: like against like, slot by slot, the weaker of two.
--   "pair", what the hands would be worth with the piece, what they are worth, and a note:
--       a two-hander against both the pieces it would replace ("both");
--       a one-hander against a two-hander, together with the best piece carried for the
--       other hand (that piece's link), or by itself where none is carried ("alone").
--     Then whether what is to beat is the gear set's (fromSet) or the worn gear standing in
--     (fromWorn), and whether a piece of the set's is not the one worn (setAside).
--   nil: nothing in the hands to compare with, or a two-hander against a ranged weapon.
-- On a scale that puts no weapon in the off hand (ScaleTakesOffHand) a one-hander is the main
-- hand's alone, a second weapon is no partner for it, and neither a weapon for the off hand
-- nor a two-hander against two weapons is weighed. A shield or a held item is weighed there
-- as anywhere: a tank's weapon and shield against a two-hander. offWeapon: the piece is a
-- weapon for the off hand alone. Where such a scale has a half for the off hand's weapon, that
-- hand has a verdict of its own beside this one (JudgeOffHand).
local function WeaponComparison(loadout, link, value, kind, offWeapon)
    local takesOff = ScaleTakesOffHand(loadout.scale)
    if offWeapon and not takesOff then
        return nil
    end
    local main = LoadoutBaseline(loadout, INVSLOT_MAINHAND)
    local off = LoadoutBaseline(loadout, INVSLOT_OFFHAND)
    local mainKind
    if main then
        local _, _, _, mainType = C_Item.GetItemInfoInstant(main.link)
        mainKind = HAND_KINDS[mainType]
    end
    if kind == "two" then
        if mainKind == "two" then
            return "slots", MAIN_HAND
        end
        if (main and mainKind == nil) or not (main or off) then
            return nil
        end
        if off and not takesOff then
            local _, _, _, offType = C_Item.GetItemInfoInstant(off.link)
            if offType == "INVTYPE_WEAPON" or offType == "INVTYPE_WEAPONOFFHAND" then
                return nil
            end
        end
        return "pair", value, (main and main.value or 0) + (off and off.value or 0), "both",
            (main ~= nil and main.fromSet) or (off ~= nil and off.fromSet) or false,
            (main ~= nil and not main.fromSet) or (off ~= nil and not off.fromSet) or false,
            (main ~= nil and main.fromSet and not main.worn) or (off ~= nil and off.fromSet and not off.worn) or false
    end
    if mainKind == "two" then
        local partner, partnerValue = BestPartner(loadout, kind, link, takesOff)
        return "pair", value + (partnerValue or 0), main.value, partner and partner.link or "alone",
            main.fromSet, not main.fromSet, main.fromSet and not main.worn
    end
    if kind == "off" then
        return "slots", OFF_HAND
    elseif kind == "either" and takesOff and CanWieldTwoWeapons() then
        return "slots", BOTH_HANDS
    end
    return "slots", MAIN_HAND
end

-- A thrown weapon and a weapon that shoots (a bow, a gun, a crossbow; a wand has their equip
-- location) are not weighed against each other on a scale that gives a ranged weapon's damage
-- a weight, which is a hunter's (author decision). With a thrown weapon in the slot the
-- class's shots cannot be used (seen, WoW Forever 1.60.1.70959: they ask for a ranged
-- weapon), and what a bow shoots adds damage that is in no weapon's value (an arrow's "Adds
-- 7.5 damage per second"). Pawn compares the two as any two pieces for the slot and has no
-- slot for ammunition (read in Pawn 2.14.4). Seen: a thrown weapon worth 78.00 against a bow
-- worth 74.61 on a hunter's scale was Pawn's upgrade and had the yellow arrow.
-- On a scale that gives that damage no weight the slot carries stats, a warrior's or a
-- rogue's, and the two are compared as any pieces.
local RANGED_KINDS = {
    INVTYPE_RANGED = "shot",
    INVTYPE_RANGEDRIGHT = "shot",
    INVTYPE_THROWN = "thrown",
}
local RANGED_DAMAGE_WEIGHTS = { "RangedDps", "RangedMinDamage", "RangedMaxDamage" }
local UNLIKE_RANGED = "a thrown weapon and a weapon that shoots are not weighed against each other"

local function ScaleWeighsRangedDamage(scaleName)
    local scale = PawnCommon.Scales[scaleName]
    local values = scale and scale.Values
    if type(values) ~= "table" then
        return false
    end
    for _, stat in ipairs(RANGED_DAMAGE_WEIGHTS) do
        local weight = values[stat]
        if type(weight) == "number" and weight > 0 then
            return true
        end
    end
    return false
end

-- Whether the piece at the link is a ranged weapon of another kind than kind.
local function IsOtherRangedKind(kind, link)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
    local other = equipLoc and RANGED_KINDS[equipLoc]
    return other ~= nil and other ~= kind
end

-- The loadout's piece that a ranged weapon is not weighed against, in a slot it would take:
-- its entry (LoadoutBaseline), or nil.
local function UnlikeRangedPiece(loadout, inventoryTypeName, inventorySlots)
    local kind = RANGED_KINDS[inventoryTypeName]
    if not kind or not ScaleWeighsRangedDamage(loadout.scale) then
        return nil
    end
    for _, slotID in ipairs(inventorySlots) do
        local baseline = LoadoutBaseline(loadout, slotID)
        if baseline and IsOtherRangedKind(kind, baseline.link) then
            return baseline
        end
    end
    return nil
end

-- The scales on which Pawn's own word for a piece does not count for that reason (scale name
-- -> true), or nil: every scale it shows that weighs ranged damage, where the piece is a
-- ranged weapon and the one worn in its slot is of the other kind. Pawn's verdict is against
-- what is worn, on each scale it shows.
local function UnlikeRangedScales(inventoryTypeName)
    local kind = inventoryTypeName and RANGED_KINDS[inventoryTypeName]
    local inventorySlots = kind and GetInventorySlotsForType(inventoryTypeName)
    if not inventorySlots or not (PawnCommon and PawnCommon.Scales and PawnIsScaleVisible) then
        return nil
    end
    local unlike = false
    for _, slotID in ipairs(inventorySlots) do
        local link = GetInventoryItemLink("player", slotID)
        if link and IsOtherRangedKind(kind, link) then
            unlike = true
        end
    end
    if not unlike then
        return nil
    end
    local found
    for scaleName in pairs(PawnCommon.Scales) do
        if PawnIsScaleVisible(scaleName) and ScaleWeighsRangedDamage(scaleName) then
            found = found or {}
            found[scaleName] = true
        end
    end
    return found
end

-- One loadout's verdict on a piece, by Pawn's values on the loadout's scale: the piece against
-- what the loadout has in the slots it would take, the weaker of two as Pawn has it. For what
-- is worn this is the yellow arrow's comparison, for the other loadouts the red one's, and the
-- lines of the tooltips are made from the same numbers.
--   "upgrade": worth more, by Pawn's threshold; or it fills a slot with nothing worn in it
--              (emptySlot). That is for what is worn alone (a gear set that has nothing for a
--              slot is not asking for a piece), and not for a weapon's hands, where an empty
--              off hand is not every class's to fill. Seen (WoW Forever 1.60.1.70959):
--              shoulders for a rogue with none on had Pawn's note and no line of the addon's.
--   "equipped": scored, and worth no more than what it would replace. Or a ranged weapon
--               of another kind than the loadout's (UnlikeRangedPiece): not weighed, and no
--               upgrade by anyone's word; the note is then "unlike", and the value to beat
--               that piece's.
--   nil: no verdict. Pawn has no value for the piece, the loadout has nothing in a slot or
--        has the piece itself, the scale is told not to show the kind of weapon
--        (IsWeaponKindRefused), the hands hold nothing to compare a weapon with, or it is the
--        played spec's set with its own pieces worn, or with the worn gear standing in for
--        every slot: compared already, as the worn gear.
-- Then: the piece's value, the value to beat, emptySlot, whether a piece to beat was the
-- gear set's (fromSet) or the worn gear standing in (fromWorn), and for a weapon weighed for
-- both hands WeaponComparison's note; the values are then the hands'.
local function JudgeLoadout(loadout, link, inventoryTypeName, inventorySlots)
    SetPvpMode(loadout, link, HAND_KINDS[inventoryTypeName] and BOTH_HANDS or inventorySlots)
    local value = LoadoutValue(loadout, loadout.scale, link)
    if value == nil or IsWeaponKindRefused(loadout, inventoryTypeName) then
        return nil
    end
    local unlike = UnlikeRangedPiece(loadout, inventoryTypeName, inventorySlots)
    if unlike then
        return "equipped", value, unlike.value, false, unlike.fromSet, not unlike.fromSet, "unlike"
    end
    local kind = HAND_KINDS[inventoryTypeName]
    if kind then
        local how, total, toBeat, note, pairFromSet, pairFromWorn, pairSetAside = WeaponComparison(loadout, link, value, kind,
            inventoryTypeName == "INVTYPE_WEAPONOFFHAND")
        if how == "pair" then
            if loadout.own and not pairSetAside then
                return nil
            end
            if total > 0 and total > toBeat * PAWN_UPGRADE_THRESHOLD then
                return "upgrade", total, toBeat, false, pairFromSet, pairFromWorn, note
            end
            return "equipped", total, toBeat, false, pairFromSet, pairFromWorn, note
        elseif how ~= "slots" then
            return nil
        end
        inventorySlots = total
    end
    local fillsEmptySlots = kind == nil
    local lowest
    local fromSet, fromWorn = false, false
    -- One of the set's pieces for these slots is not the one worn.
    local setAside = false
    local emptySlot = false
    for _, slotID in ipairs(inventorySlots) do
        local baseline = LoadoutBaseline(loadout, slotID)
        if not baseline and loadout.isWorn and fillsEmptySlots and not GetInventoryItemLink("player", slotID) then
            emptySlot = true
        elseif not baseline or baseline.link == link then
            return nil
        else
            if baseline.fromSet then
                fromSet = true
                if not baseline.worn then
                    setAside = true
                end
            else
                fromWorn = true
            end
            if not lowest or baseline.value < lowest then
                lowest = baseline.value
            end
        end
    end
    if loadout.own and not setAside then
        return nil
    end
    -- A piece the scale gives nothing is no upgrade, for an empty slot either.
    if value > 0 and (emptySlot or (lowest ~= nil and value > lowest * PAWN_UPGRADE_THRESHOLD)) then
        return "upgrade", value, lowest, emptySlot, fromSet, fromWorn
    end
    if lowest ~= nil and not emptySlot then
        return "equipped", value, lowest, false, fromSet, fromWorn
    end
    return nil
end

-- The off hand's own verdict on a weapon, where the hands are judged apart (HandsApart): the
-- piece's value on the scale for the off hand's weapon against the off hand's piece, and that
-- piece alone. Beside JudgeLoadout's, which on such a scale is the main hand's: a one-hander
-- has up to two verdicts, one a hand. Pawn's own verdict on the off hand's scale is against
-- the weaker of both weapons, the main hand's valued as an off hand's would be.
--   { verdict, value, toBeat, emptySlot, scale, label, fromSet, fromWorn }
--   "upgrade": worth more, by Pawn's threshold. Or, for what is worn, it fills an off hand
--              with nothing in it beside a one-handed weapon in the main hand (emptySlot): a
--              toon whose scale has a half for the off hand's weapon has that hand to fill.
--   "equipped": scored, and worth no more than the off hand's piece.
-- nil, and why for the export: the hands are not judged apart, Pawn has no value for the
-- piece, it is the loadout's own piece for either hand (a link does not tell a second copy
-- from the piece worn), a gear set has nothing in the off hand, or it is the played spec's
-- set with its own piece worn there.
local function JudgeOffHand(loadout, link, inventoryTypeName)
    local offScale = HandsApart(loadout, inventoryTypeName)
    if not offScale then
        return nil
    end
    SetPvpMode(loadout, link, BOTH_HANDS)
    local value = LoadoutValue(loadout, offScale.name, link)
    if value == nil then
        return nil, "Pawn has no value for the piece"
    end
    local main = LoadoutBaseline(loadout, INVSLOT_MAINHAND)
    local mainLink = main and main.link or (loadout.isWorn and GetInventoryItemLink("player", INVSLOT_MAINHAND)) or nil
    if mainLink == link then
        return nil, "the main hand's piece itself"
    end
    local baseline = LoadoutBaseline(loadout, INVSLOT_OFFHAND, offScale.name)
    if baseline then
        if baseline.link == link then
            return nil, "the off hand's piece itself"
        end
        if loadout.own and not (baseline.fromSet and not baseline.worn) then
            return nil, "the set's piece for the off hand is the one worn"
        end
        return { verdict = (value > 0 and value > baseline.value * PAWN_UPGRADE_THRESHOLD) and "upgrade" or "equipped",
            value = value, toBeat = baseline.value, scale = offScale.name, label = offScale.label,
            fromSet = baseline.fromSet, fromWorn = not baseline.fromSet }
    end
    if not loadout.isWorn or GetInventoryItemLink("player", INVSLOT_OFFHAND) then
        return nil, "nothing in the off hand that Pawn has a value for"
    end
    local mainType
    if mainLink then
        mainType = select(4, C_Item.GetItemInfoInstant(mainLink))
    end
    local mainKind = mainType and HAND_KINDS[mainType]
    if mainKind ~= "main" and mainKind ~= "either" then
        return nil, "nothing in the off hand, and no one-handed weapon in the main hand"
    end
    if value <= 0 then
        return nil, "nothing in the off hand, and the scale gives the piece no value"
    end
    return { verdict = "upgrade", value = value, emptySlot = true, scale = offScale.name, label = offScale.label,
        fromSet = false, fromWorn = false }
end

-- A piece's verdict over both hands, where the off hand has one of its own (JudgeOffHand): an
-- upgrade where either hand's is.
local function EitherHand(verdict, off)
    if off == nil then
        return verdict
    end
    if verdict == "upgrade" or off.verdict == "upgrade" then
        return "upgrade"
    end
    return verdict or off.verdict
end

-- The loadout whose verdict on a piece is the yellow arrow's: what is worn, on the one scale
-- that is the worn gear's (author decision: the arrow for what is worn is the addon's own
-- comparison, as the arrows for the other loadouts are; Pawn gives the values, and its own
-- verdict stays for whatever the addon has no verdict on, and for every other scale that
-- counts as the toon's own).
--   The worn loadout (loadouts.worn), where Pawn shows its scale, or hides it and the scale is
--   scored all the same (GetPawnOffTreeScales' third return value: the scale a worn gear set is
--   tied to, or the played spec's where no scale of the toon's own is shown).
--   Where that hidden scale is scored and there is no worn loadout (the gear set worn is no
--   spec's or another spec's): the worn gear on that scale, a loadout made for this alone. It
--   has no line in the tooltip.
-- nil elsewhere, and Pawn's verdict stands alone: no scale of Pawn's for the spec, a gear set
-- of no spec worn while Pawn shows the spec's scale, and on a client with talent trees a toon
-- that shows another tree's scale and not its leading tree's (the one scale it shows is a
-- better sign of what it plays than its points are).
-- Second: Pawn hides the scale.
local function GetWornJudge()
    local loadouts = GetLoadouts()
    if loadouts.judgeRead then
        return loadouts.judge, loadouts.judgeHidden
    end
    loadouts.judgeRead = true
    if not (PawnIsScaleVisible and PawnGetItemData and PawnGetSingleValueFromItem) then
        return nil
    end
    local worn = loadouts.worn
    local _, _, hiddenOwn = GetPawnOffTreeScales()
    if hiddenOwn then
        loadouts.judgeHidden = true
        if worn and worn.scale == hiddenOwn.name then
            loadouts.judge = worn
        else
            loadouts.judge = { isWorn = true, scale = hiddenOwn.name, label = hiddenOwn.label, own = false,
                baseline = {}, pvp = loadouts.activeSet ~= nil and IsPvpSet(loadouts.activeSet.id) or nil }
        end
    elseif worn and PawnIsScaleVisible(worn.scale) then
        loadouts.judge, loadouts.judgeHidden = worn, false
    end
    return loadouts.judge, loadouts.judgeHidden
end

local function JudgeWornUnprotected(item, judge, inventoryTypeName, inventorySlots)
    local link = item:GetItemLink()
    -- Armor that is not the class's type is not Pawn's to call an upgrade, nor the addon's.
    if not link or IsArmorTypeRefused(link) then
        return nil
    end
    local verdict, value, lowest, emptySlot, _, _, pair = JudgeLoadout(judge, link, inventoryTypeName, inventorySlots)
    local off, offWhy = JudgeOffHand(judge, link, inventoryTypeName)
    return verdict, value, lowest, emptySlot, pair, off, offWhy
end

-- The worn gear's judge on a piece (JudgeLoadout's verdict and numbers). No verdict for a
-- trinket, which Pawn does not score, and where anything fails.
-- Then the off hand's own verdict, for a weapon whose hands are judged apart (JudgeOffHand's
-- table, or nil and why): the first verdict is then the main hand's, and the piece's is
-- EitherHand of the two.
local function JudgeWorn(item, judge)
    local inventoryTypeName = item:GetInventoryTypeName()
    if inventoryTypeName == "INVTYPE_TRINKET" then
        return nil
    end
    local inventorySlots = GetInventorySlotsForType(inventoryTypeName)
    if not inventorySlots then
        return nil
    end
    local ok, verdict, value, lowest, emptySlot, pair, off, offWhy = pcall(JudgeWornUnprotected, item, judge,
        inventoryTypeName, inventorySlots)
    if not ok then
        return nil
    end
    return verdict, value, lowest, emptySlot, pair, off, offWhy
end

-- The off hand's numbers (JudgeOffHand's table), for the Debug Frame export.
local function OffHandDetail(off)
    local name = off.label .. (PawnIsScaleVisible and not PawnIsScaleVisible(off.scale) and " (not shown in Pawn)" or "")
    if off.emptySlot then
        return format("for the off hand, %s: %.2f into a hand with nothing in it", name, off.value)
    end
    return format("for the off hand, %s: %.2f vs %.2f equipped", name, off.value, off.toBeat)
end

-- The worn judge's numbers, for the Debug Frame export. pair: a weapon weighed for both hands
-- (WeaponComparison's note), or "unlike" for a ranged weapon of another kind than the one
-- worn, which is not weighed. off: the off hand's own verdict (JudgeOffHand), said after the
-- numbers of the worn gear's own scale, or alone where that scale had no verdict (value nil).
local function WornDetail(judge, hidden, value, lowest, emptySlot, pair, off)
    local own
    if value ~= nil then
        local name = judge.label .. (hidden and " (not shown in Pawn)" or "")
        if pair == "unlike" then
            own = format("%s: not weighed, %s (%.2f, and %.2f equipped)", name, UNLIKE_RANGED, value, lowest)
        elseif emptySlot or lowest == nil then
            own = format("%s: %.2f into a slot with nothing worn in it", name, value)
        else
            local hands = ""
            if pair == "both" then
                hands = " in both hands"
            elseif pair == "alone" then
                hands = " in both hands, the piece with nothing carried for the other hand"
            elseif pair then
                hands = format(" in both hands, the piece with %s", tostring(pair))
            end
            own = format("%s: %.2f vs %.2f equipped%s", name, value, lowest, hands)
        end
    end
    if off then
        return own and (own .. "; " .. OffHandDetail(off)) or OffHandDetail(off)
    end
    return own
end

-- The names of the specs the client lists the piece for, where the toon's loot spec is not
-- among them, or nil: gear for another loot spec, as the upgrade arrow has it (matchesLootSpec
-- in GetTransmogInfo), and as the client's own group loot has it, which calls a Need for such
-- a piece "Need (Off-Spec)". The line for what is worn says so (features/Tooltip.lua). A spec
-- the client has no name for is left out of the names.
local function OtherLootSpecsOf(itemSpecs)
    local lootSpecID = itemSpecs and #itemSpecs > 0 and GetPlayerLootSpecID() or nil
    if not lootSpecID or lootSpecID <= 0 then
        return nil
    end
    local names = {}
    for _, specID in ipairs(itemSpecs) do
        if specID == lootSpecID then
            return nil
        end
        local _, name = CaerdonAPI:GetSpecializationInfoByID(specID)
        if name then
            names[#names + 1] = name
        end
    end
    return names
end

-- The loadouts the piece is an upgrade for, or nil: their names, the numbers for the Debug
-- Frame export, and the same as a list for the item tooltip ({ scale, label, name and icon
-- (the gear set's where its piece was the one to beat, else the spec's; the active set's for
-- what is worn, with worn = true), colour, own, value, baseline } per loadout). A weapon whose
-- hands are judged apart (HandsApart) has an entry for each hand it is an upgrade in, with
-- hand ("main", "off"); the off hand's is on that hand's own scale (scale), and names the
-- loadout's (loadoutScale). itemSpecs: the specs the
-- client says the piece is for (C_Item.GetItemSpecInfo), which a loadout's spec has to be among
-- when the list is not empty. onlySpecs (spec index -> true): asked for these alone.
-- withWorn: what is worn is asked too, first, and whatever onlySpecs says (the item tooltip).
-- It is asked whatever itemSpecs says as well (author decision): the played spec's scale has
-- weighed the piece, with a stat that does nothing for the spec at nothing, so an upgrade on it
-- is one for what is worn. Its entry then has otherSpecs (OtherLootSpecsOf), and the line says
-- whose gear the piece is.
local function GetLoadoutUpgrades(item, itemSpecs, onlySpecs, withWorn)
    local inventoryTypeName = item:GetInventoryTypeName()
    if inventoryTypeName == "INVTYPE_TRINKET" then
        return nil
    end
    local inventorySlots = GetInventorySlotsForType(inventoryTypeName)
    if not inventorySlots then
        return nil
    end
    local loadouts = GetLoadouts()
    if withWorn and loadouts.worn then
        local withIt = { loadouts.worn }
        for _, loadout in ipairs(loadouts) do
            withIt[#withIt + 1] = loadout
        end
        loadouts = withIt
    end
    if #loadouts == 0 then
        return nil
    end

    local ok, names, numbers, list = pcall(function()
        local link = item:GetItemLink()
        if not link or IsArmorTypeRefused(link) then
            return nil
        end

        local found, details, entries
        -- The loadouts named so far: one with an upgrade for each hand is named once.
        local named = {}
        -- One verdict of a loadout's that is an upgrade: its entry and its numbers. scaleName:
        -- the scale it was made on. hand: for a weapon whose hands are judged apart, which
        -- hand's it is ("main", "off"), and for the off hand that scale's label.
        local function Add(loadout, scaleName, value, lowest, emptySlot, fromSet, fromWorn, pair, hand, handLabel)
            found = found or {}
            details = details or {}
            entries = entries or {}
            if not named[loadout] then
                named[loadout] = true
                found[#found + 1] = loadout.label
            end
            local entry = { scale = scaleName, label = loadout.label, colour = loadout.colour,
                own = loadout.own, value = value, baseline = not emptySlot and lowest or nil,
                emptySlot = emptySlot or nil, hand = hand, pvp = loadout.pvp and not loadout.plain or nil }
            if scaleName ~= loadout.scale then
                -- The loadout's own scale, where the verdict was made on its other one.
                entry.loadoutScale = loadout.scale
            end
            if pair then
                -- A weapon weighed for both hands, and the piece carried it was
                -- weighed with (partner, a link).
                entry.pair = (pair == "both" or pair == "alone") and pair or "partner"
                entry.partner = entry.pair == "partner" and pair or nil
            end
            if loadout.isWorn then
                entry.worn = true
                entry.otherSpecs = OtherLootSpecsOf(itemSpecs)
                entry.name = loadout.activeName or loadout.specName or loadout.label
                entry.icon = loadout.activeName and loadout.activeIcon or loadout.specIcon
            elseif fromSet then
                entry.name = loadout.setName or loadout.label
                entry.icon = loadout.setIcon or QUESTION_MARK_ICON
            else
                entry.name = loadout.specName or loadout.label
                entry.icon = loadout.specIcon
            end
            entries[#entries + 1] = entry
            local against
            if fromSet then
                against = format("in its gear set \"%s\"%s", tostring(loadout.setName or loadout.setID),
                    fromWorn and " and worn" or "")
            else
                against = "worn (no gear set has the slot for it)"
            end
            local label = loadout.label
            if hand == "off" then
                label = format("%s, for the off hand on %s", label, tostring(handLabel))
            end
            if emptySlot then
                details[#details + 1] = format("%s: %.2f into a slot with nothing worn in it", label, value)
            else
                details[#details + 1] = format("%s%s: %.2f vs %.2f %s", label,
                    loadout.own and " (the spec being played, its set's piece not worn)" or "",
                    value, lowest, against)
            end
        end
        for _, loadout in ipairs(loadouts) do
            local forSpec = loadout.isWorn or not onlySpecs or onlySpecs[loadout.index] == true
            if forSpec and not loadout.isWorn and itemSpecs and #itemSpecs > 0 and loadout.id then
                forSpec = false
                for _, specID in ipairs(itemSpecs) do
                    if specID == loadout.id then
                        forSpec = true
                        break
                    end
                end
            end
            if forSpec then
                local verdict, value, lowest, emptySlot, fromSet, fromWorn, pair =
                    JudgeLoadout(loadout, link, inventoryTypeName, inventorySlots)
                -- A weapon whose hands are judged apart: the first verdict is the main hand's,
                -- and the off hand has its own, on its own scale (JudgeOffHand).
                local apart = HandsApart(loadout, inventoryTypeName) ~= nil
                if verdict == "upgrade" then
                    Add(loadout, loadout.scale, value, lowest, emptySlot, fromSet, fromWorn, pair,
                        apart and not pair and "main" or nil)
                end
                local off = apart and JudgeOffHand(loadout, link, inventoryTypeName) or nil
                if off and off.verdict == "upgrade" then
                    Add(loadout, off.scale, off.value, off.toBeat, off.emptySlot, off.fromSet, off.fromWorn, nil,
                        "off", off.label)
                end
            end
        end
        if not found then
            return nil
        end
        return table.concat(found, ", "), table.concat(details, "; "), entries
    end)
    if not ok or not names then
        return nil
    end
    return names, numbers, list
end

-- What Pawn itself says of the piece, for the scales it shows and against the worn gear
-- (PawnIsItemAnUpgrade, which its arrow and its tooltip lines both use; read in Pawn 2.14.4):
-- the scales it calls it an upgrade for (scale name -> true), the percentage for each as Pawn
-- prints it, a whole number, and whether Pawn adds upgrade notes to tooltips at all. nil where
-- Pawn has nothing for the piece.
local function ReadPawnUpgrades(link)
    if not (PawnCommon and PawnGetItemData and PawnIsItemAnUpgrade) then
        return nil
    end
    local ok, named, percents = pcall(function()
        local data = PawnGetItemData(link)
        local upgrades = data and data.Link and PawnIsItemAnUpgrade(data)
        if type(upgrades) ~= "table" then
            return nil
        end
        local scales, rounded = {}, {}
        for _, upgrade in ipairs(upgrades) do
            if upgrade.ScaleName then
                scales[upgrade.ScaleName] = true
                if type(upgrade.PercentUpgrade) == "number" then
                    rounded[upgrade.ScaleName] = math.floor(upgrade.PercentUpgrade * 100 + 0.5)
                end
            end
        end
        return scales, rounded
    end)
    if not ok or not named then
        return nil
    end
    return named, percents, PawnCommon.ShowUpgradesOnTooltips == true
end

-- For the item tooltip: the scales Pawn shows whose gear set decides in Pawn's place
-- (GetShownSetSpecs), by name, or nil. Pawn's upgrade note for such a scale is against the worn
-- gear, and the tooltip leaves it out for the addon's own line (features/Tooltip.lua). Only
-- where the player asked for the arrows for other gear (Icon.ShowOtherSpecUpgrades).
--[[static]]
function CaerdonEquipment:GetPawnScalesGivenToSets()
    local iconConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon
    if not (iconConfig and iconConfig.ShowOtherSpecUpgrades == true) then
        return nil
    end
    local offTreeScales = GetPawnOffTreeScales()
    local setSpecs = offTreeScales and GetShownSetSpecs(offTreeScales) or nil
    if not setSpecs then
        return nil
    end
    local names = {}
    for scaleName in pairs(offTreeScales) do
        local scale = PawnCommon.Scales[scaleName]
        if scale and setSpecs[scale.SpecID] then
            names[scaleName] = true
        end
    end
    return names
end

-- For the item tooltip: the scales Pawn shows that the addon judges itself, by name, or nil.
-- Pawn marks a piece as "your best" or "your second best" for a scale from the pieces it has
-- seen worn; for these scales what the toon's best piece is, is what its gear set holds or
-- what it wears, so the tooltip leaves those marks out (features/Tooltip.lua; author decision).
--   The played spec's scale, where what is worn has a line of the addon's (loadouts.worn).
--   The other specs' scales the addon measures, where the player asked for the arrows for
--   other gear (Icon.ShowOtherSpecUpgrades).
--   The scale for the off hand's weapon (OffHandScale), where what is worn is judged on it
--   hand by hand (HandsApart): it is the other half of the scale the worn gear is judged on,
--   and the toon's best piece for that hand is the one in it. Seen (WoW Forever
--   1.60.1.70959): "Rogue: Off Hand: your best" on the off hand's worn piece, above the
--   addon's "+10% upgrade" for the piece looked at.
-- A scale of the player's own making, another class's, and a spec that is switched off stay
-- Pawn's.
--[[static]]
function CaerdonEquipment:GetPawnScalesJudged()
    if not (PawnCommon and PawnCommon.Scales and PawnIsScaleVisible) then
        return nil
    end
    local loadouts = GetLoadouts()
    if not loadouts.wornRead then
        return nil
    end
    local iconConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon
    local others = iconConfig ~= nil and iconConfig.ShowOtherSpecUpgrades == true
    local _, _, classID = UnitClass("player")
    local ok, names = pcall(function()
        local found
        for scaleName, scale in pairs(PawnCommon.Scales) do
            local specIndex = scale.SpecID
            if scale.ClassID == classID and type(specIndex) == "number" and PawnIsScaleVisible(scaleName) then
                local loadout = loadouts.bySpec[specIndex]
                local judged
                if loadouts.worn and loadouts.worn.index == specIndex then
                    judged = true
                else
                    judged = others and loadout ~= nil and not loadout.own
                end
                if judged then
                    found = found or {}
                    found[scaleName] = true
                end
            end
        end
        local judge = GetWornJudge()
        local half = judge and HandsApart(judge, "INVTYPE_WEAPON")
        if half and PawnIsScaleVisible(half.name) then
            found = found or {}
            found[half.name] = true
        end
        return found
    end)
    return ok and names or nil
end

-- For the item tooltip: what the piece would be an upgrade for (GetLoadoutUpgrades' list), or
-- nil. Asked of the piece by itself, whatever its icon says: a piece with the yellow arrow can
-- be an upgrade for a gear set as well. Never for a tabard or a shirt, as the arrow.
--   What is worn (worn = true), first: on the played spec's scale against the worn pieces,
--   named for the active set where there is one. Only where that comparison is the yellow
--   arrow's as well (GetWornJudge): Pawn shows the scale, or hides it and it is scored all the
--   same. Elsewhere the arrow is Pawn's alone, and the line would stand beside an icon that
--   says something else.
--   The loadouts, only where the player asked for those arrows (Icon.ShowOtherSpecUpgrades).
--   The played spec's own set is left out where the worn entry stands: the worn piece is
--   taken for the set's, saved into it or not (author decision).
-- Each entry also has percent (the gain, rounded to a whole number; nil against a piece the
-- scale gives no value, and for a slot with nothing worn in it, emptySlot), saidByPawn (Pawn's
-- own tooltip note for that scale has the same percentage) and atLevel (LevelToCome).
--[[static]]
function CaerdonEquipment:GetLoadoutUpgradeList(item)
    local link = item and item:GetItemLink()
    if not link then
        return nil
    end
    local inventoryTypeName = item:GetInventoryTypeName()
    if inventoryTypeName == "INVTYPE_TABARD" or inventoryTypeName == "INVTYPE_BODY" then
        return nil
    end
    -- The link is not the piece's own: no value of it is the piece's.
    if IsKnownByAnotherLink(item) then
        return nil
    end
    local iconConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon
    local wantsLoadouts = iconConfig ~= nil and iconConfig.ShowOtherSpecUpgrades == true
    local _, _, list = GetLoadoutUpgrades(item, C_Item.GetItemSpecInfo(link), not wantsLoadouts and {} or nil, true)
    if not list then
        return nil
    end

    local _, percents, inTooltip = ReadPawnUpgrades(link)
    local judge = GetWornJudge()
    local kept, wornStands = {}, false
    local atLevel = LevelToCome(item)
    for _, entry in ipairs(list) do
        local keep = true
        if entry.worn then
            -- The arrow's own comparison, where the arrow is the addon's to give. The off
            -- hand's line is on that hand's scale, and goes by the loadout's.
            keep = judge ~= nil and judge.scale == (entry.loadoutScale or entry.scale)
            wornStands = wornStands or keep
        elseif entry.own and wornStands then
            keep = false
        end
        if keep then
            entry.percent = entry.baseline and entry.baseline > 0 and
                math.floor((entry.value / entry.baseline - 1) * 100 + 0.5) or nil
            entry.atLevel = atLevel
            entry.saidByPawn = inTooltip == true and entry.percent ~= nil and percents[entry.scale] == entry.percent
            kept[#kept + 1] = entry
        end
    end
    return #kept > 0 and kept or nil
end

-- For the Debug Frame export: who gives the piece the arrow for what is worn, and what the
-- addon's own comparison and Pawn's verdict each say for the worn gear's scale. Asked anew, so
-- that the two can be read side by side: where they differ the arrow is the addon's.
--[[static]]
function CaerdonEquipment:GetWornVerdictDescription(item)
    local link = item and item:GetItemLink()
    if not link or not (PawnCommon and PawnCommon.Scales and PawnIsScaleVisible) then
        return nil
    end
    -- A row known by a link that is not its own: the status asks neither judge, and what was
    -- printed here was the comparison of another piece (the item without the row's suffix).
    local anotherLink, anotherLinkBy = IsKnownByAnotherLink(item)
    if anotherLink then
        return format("not made: the link %s (a row named by item key), so neither the addon nor Pawn is asked and the item level decides",
            anotherLinkBy == "suffix" and "is the item's without the suffix the row names" or
            "is the plain item's, at another item level than the piece")
    end
    local judge, hidden = GetWornJudge()
    -- A ranged weapon of another kind than the one worn: the scales Pawn's word is left out on.
    local unlike = UnlikeRangedScales(item:GetInventoryTypeName())
    if not judge then
        return "Pawn's verdict alone (the addon scores no scale for what is worn)" ..
            (unlike and format("; not on a scale that weighs ranged damage: %s", UNLIKE_RANGED) or "")
    end
    local verdict, value, lowest, emptySlot, pair, off, offWhy = JudgeWorn(item, judge)
    local own
    if verdict then
        own = format("%s, %s", verdict == "upgrade" and "an upgrade" or "no upgrade",
            WornDetail(judge, hidden, value, lowest, emptySlot, pair))
    else
        own = format("no verdict on %s%s, so Pawn's stands", tostring(judge.label), hidden and " (not shown in Pawn)" or "")
    end
    local named = ReadPawnUpgrades(link)
    local pawn
    if hidden then
        pawn = "not asked, it does not show the scale"
    else
        pawn = named and named[judge.scale] and "an upgrade" or "no upgrade"
    end
    -- The off hand's own verdict, for a weapon whose hands are judged apart, with Pawn's word
    -- for that hand's scale beside it; or why there is none.
    local offScale = judge.offScale or nil
    local offHand = ""
    if off then
        offHand = format("; %s: %s; Pawn for that scale: %s", OffHandDetail(off),
            off.verdict == "upgrade" and "an upgrade" or "no upgrade",
            not PawnIsScaleVisible(off.scale) and "not asked, it does not show the scale" or
            (named and named[off.scale] and "an upgrade" or "no upgrade"))
    elseif offWhy and offScale then
        offHand = format("; for the off hand, %s: no verdict (%s), so Pawn's stands", tostring(offScale.label), tostring(offWhy))
    end
    -- The other scales Pawn calls it an upgrade for: its verdict stands for those that count
    -- as the toon's own (a scale of the player's making; a rogue's scale for the off hand,
    -- where the addon has no verdict of its own for that hand).
    local others, notCounted = {}, {}
    for scaleName in pairs(named or {}) do
        if scaleName ~= judge.scale and not (off and scaleName == off.scale) then
            local scale = PawnCommon.Scales[scaleName]
            local list = unlike and unlike[scaleName] and notCounted or others
            list[#list + 1] = tostring(scale and scale.LocalizedName or scaleName)
        end
    end
    table.sort(others)
    table.sort(notCounted)
    -- A set marked for PVP: how this comparison was scored (SetPvpMode, as the judge left it).
    local pvp = ""
    if judge.pvp then
        pvp = judge.plain and "; a PVP set, scored at the pieces' own levels here: one of them has a floor and no link for it, or the client is without its item just now" or
            "; a PVP set, scored at PVP levels"
    end
    return format("the addon's own comparison: %s; Pawn for that scale: %s%s; an upgrade of Pawn's on its other scales: %s%s%s",
        own, pawn, offHand, #others > 0 and table.concat(others, ", ") or "none",
        #notCounted > 0 and format("; not counted, %s: %s", UNLIKE_RANGED, table.concat(notCounted, ", ")) or "", pvp)
end

-- For the item tooltip: the scale for the off hand's weapon on which the addon has a verdict
-- of its own for the piece, as what is worn (JudgeOffHand), by name, or nil. Pawn's upgrade
-- note for that scale is against the weaker of both weapons, the main hand's valued as an off
-- hand's, and gives way whether the addon's verdict is an upgrade, with its line, or none:
-- left in, it said "upgrade" under an icon with no arrow.
--[[static]]
function CaerdonEquipment:GetOffHandScaleJudged(item)
    local link = item and item:GetItemLink()
    if not link or not (PawnCommon and PawnCommon.Scales and PawnIsScaleVisible) or IsKnownByAnotherLink(item) then
        return nil
    end
    local judge = GetWornJudge()
    if not judge then
        return nil
    end
    local _, _, _, _, _, off = JudgeWorn(item, judge)
    return off and off.scale or nil
end

-- For the item tooltip: the scales Pawn shows on which the piece is not weighed against
-- what is worn (UnlikeRangedScales), by name, or nil. Pawn's upgrade note for such a scale
-- gives way: left in, it says "upgrade" under an icon with no arrow.
--[[static]]
function CaerdonEquipment:GetScalesNotWeighed(item)
    local link = item and item:GetItemLink()
    if not link or IsKnownByAnotherLink(item) then
        return nil
    end
    return UnlikeRangedScales(item:GetInventoryTypeName())
end

-- For the Debug Frame export: the gear set taken for the one being worn and why, and whether
-- what is worn has a line of the addon's in the tooltip. nil where nothing was read (no Pawn,
-- no specs, no spec chosen, no scale for the played spec).
--[[static]]
function CaerdonEquipment:GetActiveSetDescription()
    local loadouts = GetLoadouts()
    if not loadouts.wornRead then
        return nil
    end
    local active = loadouts.activeSet
    local chosenID = ChosenGearSet()
    return format("%s (%s; the set last put on: %s); the worn gear's own tooltip line: %s",
        active and format("\"%s\"", tostring(active.name)) or "none", tostring(loadouts.activeWhy),
        chosenID and tostring(chosenID) or "none noted",
        loadouts.worn and "yes" or "no, the set worn is not the played spec's")
end

-- For the Debug Frame export: each gear set of the toon's with the scale the player tied it
-- to, or nil where the toon has no sets or Pawn is not there.
--[[static]]
function CaerdonEquipment:GetGearSetScaleDescription()
    if not (PawnCommon and PawnCommon.Scales and C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs and
        C_EquipmentSet.GetEquipmentSetInfo) then
        return nil
    end
    local parts = {}
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
        local name = C_EquipmentSet.GetEquipmentSetInfo(setID)
        local tied, lost = TiedSetScale(setID)
        local scale = tied and PawnCommon.Scales[tied]
        local what
        if tied then
            what = format("tied to %s", tostring(scale.LocalizedName or tied))
            if not IsOtherSetWanted(setID) then
                what = what .. ", its upgrades switched off while another set is worn"
            end
        elseif lost then
            what = format("tied to \"%s\", which Pawn no longer has: not tied", tostring(lost))
        else
            what = "not tied"
        end
        if IsPvpSet(setID) then
            what = what .. ", marked as a PVP set"
        end
        parts[#parts + 1] = format("\"%s\" (%s) %s", tostring(name), tostring(setID), what)
    end
    if #parts == 0 then
        return nil
    end
    return format("%s (a deleted set's tie goes with it: %s)", table.concat(parts, "; "),
        deleteHooked and "yes" or "no, the client's delete function could not be hooked")
end

-- For the settings page: the toon's gear sets in the client's order, each with the scale the
-- player tied it to, or nil where the client has no gear sets to ask for.
--   { id, name, icon, tied = the scale's name, tiedLabel, lost = a tied scale Pawn no longer
--     has, specName, specIndex = the spec the client ties the set to }
-- Second: whether the client has talent trees in the place of specs.
--[[static]]
function CaerdonEquipment:GetGearSets()
    if not (C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs and C_EquipmentSet.GetEquipmentSetInfo) then
        return nil
    end
    local byTree = CaerdonAPI:GetTalentTrees() and true or false
    local specNames, specIndexes = {}, {}
    if not byTree and C_EquipmentSet.GetEquipmentSetForSpec and GetSpecializationInfoForClassID then
        local _, _, classID = UnitClass("player")
        for specIndex = 1, 4 do
            local setID = C_EquipmentSet.GetEquipmentSetForSpec(specIndex)
            if setID then
                local _, specName = GetSpecializationInfoForClassID(classID, specIndex)
                specNames[setID] = specName
                specIndexes[setID] = specIndex
            end
        end
    end
    local sets = {}
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
        local name, icon = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if name ~= nil then
            local tied, lost = TiedSetScale(setID)
            local scale = tied and PawnCommon.Scales[tied]
            sets[#sets + 1] = {
                id = setID,
                name = name,
                icon = icon or QUESTION_MARK_ICON,
                tied = tied,
                tiedLabel = scale and (scale.LocalizedName or tied) or nil,
                lost = lost,
                specName = specNames[setID],
                specIndex = specIndexes[setID],
            }
        end
    end
    return sets, byTree
end

-- For the settings page: a gear set's own switch (IsOtherSetWanted), which is for a set tied to
-- a scale that no spec owns.
--[[static]]
function CaerdonEquipment:IsGearSetWanted(setID)
    return IsOtherSetWanted(setID)
end

-- For the settings page: whether the gear set is marked as one for PVP (IsPvpSet), and whether
-- it holds a piece with a PVP floor, which is what the mark is offered for.
--[[static]]
function CaerdonEquipment:IsPvpGearSet(setID)
    return IsPvpSet(setID)
end

--[[static]]
function CaerdonEquipment:GearSetHasPvpFloor(setID)
    if not (pvpFloorPattern and C_TooltipInfo and C_TooltipInfo.GetHyperlink and C_EquipmentSet and
        C_EquipmentSet.GetItemLocations) then
        return false
    end
    for _, location in pairs(C_EquipmentSet.GetItemLocations(setID) or {}) do
        local link = LinkAtSetLocation(location)
        if link and ExtractPvpFloorFromTooltip(C_TooltipInfo.GetHyperlink(link)) then
            return true
        end
    end
    return false
end

-- For the settings page: the specs of the toon's class that no gear set speaks for, in their
-- order, or nil on a client without specs and where Pawn is not there. Such a spec is a
-- loadout by itself: what is worn, on the scale Pawn ships for the spec (GetLoadouts).
--   { index, name, icon, scaleLabel }
-- Not a spec the client ties a gear set to, nor one whose scale the player tied a set to:
-- that set is the loadout then, and has the row (AddTiedSets drops the spec beside it).
--[[static]]
function CaerdonEquipment:GetSpecsWithoutGearSet()
    if CaerdonAPI:GetTalentTrees() then
        return nil
    end
    local countSpecs = C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID
    if not (PawnCommon and PawnCommon.Scales and PawnGetItemData and PawnGetSingleValueFromItem and
        countSpecs and GetSpecializationInfoForClassID) then
        return nil
    end
    local _, _, classID = UnitClass("player")
    local setForSpec = C_EquipmentSet and C_EquipmentSet.GetEquipmentSetForSpec
    local tiedTo = {}
    if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs then
        for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
            local tied = TiedSetScale(setID)
            if tied then
                tiedTo[tied] = true
            end
        end
    end
    local specs = {}
    for specIndex = 1, classID and countSpecs(classID) or 0 do
        if not (setForSpec and setForSpec(specIndex)) then
            -- The spec's scale, and whether a set has it. Several of one spec: the first by name.
            local scaleName, taken
            for name, scale in pairs(PawnCommon.Scales) do
                if type(name) == "string" and type(scale) == "table" and scale.ClassID == classID and
                    scale.Provider ~= nil and scale.SpecID == specIndex then
                    taken = taken or tiedTo[name] == true
                    if not scaleName or name < scaleName then
                        scaleName = name
                    end
                end
            end
            if scaleName and not taken then
                local _, specName, _, specIcon = GetSpecializationInfoForClassID(classID, specIndex)
                if specName then
                    specs[#specs + 1] = {
                        index = specIndex,
                        name = specName,
                        icon = specIcon or QUESTION_MARK_ICON,
                        scaleLabel = PawnCommon.Scales[scaleName].LocalizedName or scaleName,
                    }
                end
            end
        end
    end
    return specs
end

-- For the settings page: the Pawn scales a gear set of this toon can be tied to, or nil where
-- Pawn is not there to score on one. The scales Pawn ships for the toon's class, in the order
-- of their specs; then every other scale that is not another class's, by name (the player's
-- own: one made from nothing is for no class, a copy of a class's scale keeps its class).
--   { name, label, spec }
-- A scale is one gear set's (author decision), as a spec is one set's in the client. Asked
-- for a set (its ID), a scale another set is scored on says so: takenBy is that set's name,
-- by the player's tie or, for a set nobody tied, through the spec the client ties it to
-- (takenBySpec, that spec's name). The page does not offer those. This is the page's rule and
-- not the scoring's: two sets still come by one scale where a spec is assigned in the
-- character window after a tie was made, and each is then scored on it (AddTiedSets).
--[[static]]
function CaerdonEquipment:GetGearSetScaleChoices(forSetID)
    if not (PawnCommon and PawnCommon.Scales and PawnGetItemData and PawnGetSingleValueFromItem) then
        return nil
    end
    local _, _, classID = UnitClass("player")
    local choices = {}
    local takenByScale, takenBySpec = {}, {}
    if forSetID ~= nil then
        for _, set in ipairs(CaerdonEquipment:GetGearSets() or {}) do
            if set.id ~= forSetID then
                if set.tied then
                    takenByScale[set.tied] = takenByScale[set.tied] or set
                elseif set.specIndex then
                    takenBySpec[set.specIndex] = takenBySpec[set.specIndex] or set
                end
            end
        end
    end
    for scaleName, scale in pairs(PawnCommon.Scales) do
        if type(scaleName) == "string" and type(scale) == "table" and
            (scale.ClassID == nil or scale.ClassID == classID) then
            local spec = scale.ClassID == classID and scale.Provider ~= nil and type(scale.SpecID) == "number" and
                scale.SpecID or nil
            local tied = takenByScale[scaleName]
            local bySpec = not tied and spec and takenBySpec[spec] or nil
            local holder = tied or bySpec
            choices[#choices + 1] = {
                name = scaleName,
                label = scale.LocalizedName or scaleName,
                spec = spec,
                takenBy = holder and holder.name or nil,
                takenBySpec = bySpec and bySpec.specName or nil,
            }
        end
    end
    table.sort(choices, function(a, b)
        if (a.spec ~= nil) ~= (b.spec ~= nil) then
            return a.spec ~= nil
        elseif a.spec ~= b.spec then
            return a.spec < b.spec
        elseif a.label ~= b.label then
            return a.label < b.label
        end
        return a.name < b.name
    end)
    return choices
end

-- For the Debug Frame export: each loadout with what a piece is measured against for it, or
-- nil where there is none.
--[[static]]
function CaerdonEquipment:GetLoadoutDescription()
    local loadouts = GetLoadouts()
    if #loadouts == 0 then
        return nil
    end
    local parts = {}
    for _, loadout in ipairs(loadouts) do
        local against = loadout.setID and format("gear set \"%s\"", tostring(loadout.setName or loadout.setID)) or
            "the worn gear (no gear set)"
        if loadout.own then
            -- The slots whose piece the set has and that piece is not the one worn.
            local slots = {}
            local locations = C_EquipmentSet.GetItemLocations(loadout.setID)
            for slotID = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
                local link, worn = LinkAtSetLocation(locations and locations[slotID])
                if link and not worn then
                    slots[#slots + 1] = slotID
                end
            end
            against = against .. format(" (the spec being played: where its piece is not the one worn, slots %s)",
                #slots > 0 and table.concat(slots, ", ") or "none")
        end
        if loadout.pvp then
            against = against .. ", scored at PVP levels"
        end
        parts[#parts + 1] = format("%s: %s", loadout.label, against)
    end
    return table.concat(parts, "; ")
end

-- For the Debug Frame export ("[PVP Item Level]"): the piece's PVP floor beside its level,
-- whether the floor counts right now (GetEffectiveLevels), and the piece at its floor as a set
-- marked for PVP scores it (PvpLinkOf): the bonus ID swapped, the link, its stats and Pawn's
-- values on the scales shown; or why there is no such link.
--[[static]]
function CaerdonEquipment:ExplainPvpLevel(item)
    local ok, lines = pcall(function()
        local link = item and item:GetItemLink()
        if not link then
            return { "no link" }
        end
        local floor = GetCandidatePvpFloor(item)
        local level = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link) or nil
        local out = {}
        out[#out + 1] = format("floor: %s; the piece's level: %s; in a PVP context now: %s",
            floor and tostring(floor) or "none (no floor line in the tooltip)", tostring(level), tostring(IsInPvpContext()))
        -- The worn gear's average level as it is and with every piece at its floor, beside the
        -- client's own averages (overall, equipped, PVP). The first meets the client's equipped
        -- figure where the counting is the client's: sixteen slots, a two-hander with nothing
        -- in the off hand twice. The second is NOT the client's PVP figure: that one counts
        -- gear in the bags as its overall figure does (a piece taken off leaves it as it was),
        -- so the two only lie near each other. Each piece is read by its slot: by its link the
        -- client is at times without a worn piece's level, which the line then says.
        if floor and GetAverageItemLevel then
            local own, raised, counted, linkless, said, without = 0, 0, 0, 0, {}, {}
            for slotID = INVSLOT_FIRST_EQUIPPED, INVSLOT_OFFHAND do
                local location = slotID ~= 4 and ItemLocation:CreateFromEquipmentSlot(slotID) or nil
                if location and location:IsValid() and C_Item.DoesItemExist(location) then
                    local wornLevel = C_Item.GetCurrentItemLevel(location)
                    local wornLink = GetInventoryItemLink("player", slotID)
                    if not (wornLink and C_Item.GetDetailedItemLevelInfo(wornLink)) then
                        linkless = linkless + 1
                        -- What the client does have of such a piece: by its ID, and by its link.
                        if #without < 3 then
                            local wornID = C_Item.GetItemID(location)
                            without[#without + 1] = format("slot %d: %s; item info by its ID %s, by its link %s; data cached by ID %s; its tooltip by the link %s lines",
                                slotID, wornLink and tostring(wornLink:match("|H(item:[^|]*)|h")) or "no link",
                                tostring(wornID and C_Item.GetItemInfo(wornID) ~= nil), tostring(wornLink and C_Item.GetItemInfo(wornLink) ~= nil),
                                tostring(wornID and C_Item.IsItemDataCachedByID and C_Item.IsItemDataCachedByID(wornID)),
                                tostring(wornLink and C_TooltipInfo and C_TooltipInfo.GetHyperlink and
                                    #((C_TooltipInfo.GetHyperlink(wornLink) or {}).lines or {})))
                        end
                    end
                    if wornLevel then
                        local wornFloor = C_TooltipInfo and C_TooltipInfo.GetInventoryItem and
                            ExtractPvpFloorFromTooltip(C_TooltipInfo.GetInventoryItem("player", slotID)) or nil
                        local atFloor = wornFloor and wornFloor > wornLevel and wornFloor or wornLevel
                        local wornID = C_Item.GetItemID(location)
                        local _, _, _, wornLoc = C_Item.GetItemInfoInstant(wornID)
                        local twice = slotID == INVSLOT_MAINHAND and
                            not C_Item.DoesItemExist(ItemLocation:CreateFromEquipmentSlot(INVSLOT_OFFHAND)) and
                            (wornLoc == "INVTYPE_2HWEAPON" or wornLoc == "INVTYPE_RANGED" or wornLoc == "INVTYPE_RANGEDRIGHT")
                        local weight = twice and 2 or 1
                        own, raised, counted = own + wornLevel * weight, raised + atFloor * weight, counted + weight
                        said[#said + 1] = format("%d: %d%s%s", slotID, wornLevel, atFloor ~= wornLevel and format(">%d", atFloor) or "",
                            twice and " (twice)" or "")
                    end
                end
            end
            local overall, equipped, pvp = GetAverageItemLevel()
            out[#out + 1] = format("worn gear: average of the pieces' own levels %.2f, with each at its floor %.2f (%d of 16 slots filled%s); the client's averages: overall %s, equipped %s, PVP %s (the last counts gear in the bags too)",
                own / 16, raised / 16, counted, linkless > 0 and format("; %d pieces the client has no level for by their links just now", linkless) or "",
                tostring(overall and format("%.2f", overall)), tostring(equipped and format("%.2f", equipped)),
                tostring(pvp and format("%.2f", pvp)))
            out[#out + 1] = "    by slot, level>floor: " .. table.concat(said, ", ")
            for _, line in ipairs(without) do
                out[#out + 1] = "    no level by its link: " .. line
            end
        end
        if not (floor and level and floor > level) then
            return out
        end
        local raised, how = PvpLinkOf(link)
        if NS.LevelBonuses then
            out[#out + 1] = "the table of level IDs: " .. NS.LevelBonuses:Describe()
        end
        for _, note in ipairs(pvpLinkNotes[link] or {}) do
            out[#out + 1] = note
        end
        local function StatsOf(of)
            local stats = C_Item.GetItemStats and C_Item.GetItemStats(of)
            local statParts = {}
            for key, value in pairs(type(stats) == "table" and stats or {}) do
                statParts[#statParts + 1] = format("%s %s", tostring(key), tostring(value))
            end
            table.sort(statParts)
            return #statParts > 0 and table.concat(statParts, ", ") or "none"
        end
        -- Pawn's values of another link of the piece on the scales shown, beside the piece's own.
        local function PawnOf(other)
            local pawnParts = {}
            if PawnGetItemData and PawnGetSingleValueFromItem and PawnCommon and PawnCommon.Scales and PawnIsScaleVisible then
                local own, forged = PawnGetItemData(link), PawnGetItemData(other)
                if own and own.Link and forged and forged.Link then
                    for scaleName, scale in pairs(PawnCommon.Scales) do
                        if PawnIsScaleVisible(scaleName) then
                            local _, ownValue = PawnGetSingleValueFromItem(own, scaleName)
                            local _, forgedValue = PawnGetSingleValueFromItem(forged, scaleName)
                            pawnParts[#pawnParts + 1] = format("%s %s (%s as it is)", tostring(scale.LocalizedName or scaleName),
                                forgedValue and format("%.2f", forgedValue) or "no value",
                                ownValue and format("%.2f", ownValue) or "no value")
                        end
                    end
                    table.sort(pawnParts)
                else
                    pawnParts[1] = "Pawn has no data for it yet (copy again)"
                end
            end
            return #pawnParts > 0 and table.concat(pawnParts, ", ") or "not there"
        end
        if not how then
            out[#out + 1] = format("at its floor: no link (%s); a set marked for PVP then compares it, and the piece it is compared with, at their own levels",
                tostring(pvpLinkWhy[link] or "the client does not have the item yet"))
            return out
        end
        out[#out + 1] = format("at its floor: item level %d, by bonus %s in the place of %s%s", how.level, tostring(how.bonus),
            tostring(how.own), how.quality and format(", at quality %s where its own is %s (no ID gives the floor at its own)",
                tostring(how.quality), tostring(how.ownQuality)) or "")
        out[#out + 1] = "    " .. tostring(raised:match("|H(item:[^|]*)|h"))
        out[#out + 1] = "    stats: " .. StatsOf(raised)
        out[#out + 1] = "    Pawn: " .. PawnOf(raised)
        -- A link of another quality stands on quality not moving a piece's stats. What shows
        -- that for this piece: its own level by the table's other IDs for that level, by
        -- quality, and how many of them leave its stats as they are.
        local read = how.quality and ReadLevelBonuses(link) or nil
        local known = NS.LevelBonuses
        if read and known and #read.carriers > 0 then
            local own = tonumber(read.carriers[1])
            local ownStats = StatsOf(link)
            local same, sameAlike, other, otherAlike, unknown = 0, 0, 0, 0, 0
            for index, bonus in ipairs(known:IdsFor(level, own) or {}) do
                if index > MAX_LEVEL_BONUS_TRIES then
                    break
                end
                local tried = bonus ~= own and read.With(bonus) or nil
                if tried and C_Item.GetDetailedItemLevelInfo(tried) == level then
                    local _, _, triedQuality = C_Item.GetItemInfo(tried)
                    local alike = StatsOf(tried) == ownStats and 1 or 0
                    if triedQuality == nil then
                        unknown = unknown + 1
                    elseif triedQuality == how.ownQuality then
                        same, sameAlike = same + 1, sameAlike + alike
                    else
                        other, otherAlike = other + 1, otherAlike + alike
                    end
                end
            end
            out[#out + 1] = format("    as it is: stats: %s", ownStats)
            out[#out + 1] = format("    its own level by other IDs of the table: %d at its own quality (%d with its stats), %d at another quality (%d with its stats), %d the client has no quality for yet",
                same, sameAlike, other, otherAlike, unknown)
        end
        return out
    end)
    if not ok then
        return { "error: " .. tostring(lines) }
    end
    return lines
end

-- For the Debug Frame export: which visible Pawn scales are being ignored for this toon, or nil.
--[[static]]
function CaerdonEquipment:GetPawnScaleFilterDescription()
    local _, detail = GetPawnOffTreeScales()
    return detail
end

-- For the Debug Frame export: the scales Pawn shows, by their names. Pawn's own verdict is over
-- these and no others, and with the filter off the export did not say which they are (whether
-- a rogue's scale for the off hand is among them, where an off-hand upgrade is Pawn's to call).
--[[static]]
function CaerdonEquipment:GetShownPawnScalesDescription()
    if not (PawnCommon and PawnCommon.Scales and PawnIsScaleVisible) then
        return nil
    end
    local ok, names = pcall(function()
        local shown = {}
        for scaleName, scale in pairs(PawnCommon.Scales) do
            if PawnIsScaleVisible(scaleName) then
                shown[#shown + 1] = tostring(type(scale) == "table" and scale.LocalizedName or scaleName)
            end
        end
        table.sort(shown)
        return shown
    end)
    if not ok then
        return nil
    end
    return #names > 0 and table.concat(names, ", ") or "none"
end

-- For the Debug Frame export: the scale the off hand's weapon is scored on for what is worn
-- (OffHandScale), whether Pawn shows it, and whether the toon holds a weapon in each hand,
-- without which no hand is judged apart. Where there is none, why.
--[[static]]
function CaerdonEquipment:GetOffHandScaleDescription()
    if not (PawnCommon and PawnCommon.Scales and PawnIsScaleVisible) then
        return nil
    end
    local judge = GetWornJudge()
    if not judge then
        return "none (the addon scores no scale for what is worn)"
    end
    local ok, text = pcall(function()
        if ScaleTakesOffHand(judge.scale) then
            return format("none: %s puts a weapon in the off hand itself", tostring(judge.label))
        end
        local offScale = OffHandScale(judge)
        if not offScale then
            return format("none: %s puts no weapon in the off hand, and Pawn has no scale of the class for that hand's weapon",
                tostring(judge.label))
        end
        return format("%s, beside %s (%s; the toon holds a weapon in each hand: %s%s)", tostring(offScale.label),
            tostring(judge.label), PawnIsScaleVisible(offScale.name) and "shown in Pawn" or "not shown in Pawn",
            CanWieldTwoWeapons() and "yes" or "no, so no hand is judged apart",
            offScale.refuses and "; the scale is told not to show one-handers" or "")
    end)
    return ok and text or nil
end

--[[static]]
function CaerdonEquipment:CreateFromCaerdonItem(caerdonItem)
    if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
        error("Usage: CaerdonEquipment:CreateFromCaerdonItem(caerdonItem)", 2)
    end

    local itemType = CaerdonWardrobeItemDataMixin.CreateItemData(CaerdonEquipmentMixin, caerdonItem)
    return itemType
end

function CaerdonEquipmentMixin:LoadSources(callbackFunction)
    local hasItems = false
    local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(self.item:GetItemLink())
    if not sourceID then
        -- TODO: Not sure why this is the case?  EncounterJournal links aren't returning source info
        appearanceID, sourceID = C_TransmogCollection.GetItemInfo(self.item:GetItemID())
    end
    -- Fallback to extraData for items from SetSelectionPanel etc. where GetItemInfo may return nil
    if not sourceID and self.item.extraData and self.item.extraData.appearanceSourceID then
        sourceID = self.item.extraData.appearanceSourceID
        appearanceID = self.item.extraData.appearanceID
    end
    if not appearanceID and sourceID then
        local info = C_TransmogCollection.GetAppearanceInfoBySource(sourceID)
        if info then
            appearanceID = info.appearanceID
        end
    end

    local waitingForItems = {}
    local continuableContainer = ContinuableContainer:Create();
    local cancelFunc = function() end;

    local function ProcessTheItem(itemID)
        waitingForItems[itemID] = nil
        if not next(waitingForItems) then
            callbackFunction()
        end
    end

    local function IsDebugEnabled()
        return CaerdonWardrobeConfig and CaerdonWardrobeConfig.Debug and CaerdonWardrobeConfig.Debug.Enabled
    end

    local function FailTheItem(itemID)
        local failedSourceID = waitingForItems[itemID]
        waitingForItems[itemID] = nil
        -- Remember the failure for the session so later refreshes don't re-request
        -- an item the server already refused, and only report it the first time.
        local alreadyReported = failedSourceItemLoads[itemID]
        failedSourceItemLoads[itemID] = true
        if not alreadyReported and IsDebugEnabled() then
            print(format(
                "CaerdonWardrobe: ITEM_DATA_LOAD_RESULT failed for source item %s (%s, exists=%s), source %s of appearance %s, while loading sources for %s (item %s)",
                tostring(itemID),
                tostring(C_Item.GetItemNameByID(itemID) or "unknown name"),
                tostring(C_Item.DoesItemExistByID(itemID)),
                tostring(failedSourceID),
                tostring(appearanceID),
                tostring(self.item:GetItemLink()),
                tostring(self.item:GetItemID())))
        end
        if not next(waitingForItems) then
            callbackFunction()
        end
    end

    if not appearanceID then
        callbackFunction()
    else
        local appearanceSourceIDs = C_TransmogCollection.GetAllAppearanceSources(appearanceID)
        for appearanceSourceIndex, appearanceSourceID in pairs(appearanceSourceIDs) do
            local itemID = C_TransmogCollection.GetSourceItemID(appearanceSourceID);
            if not itemID or itemID == 0 then
                if IsDebugEnabled() then
                    print(format(
                        "CaerdonWardrobe: source %s of appearance %s has no item ID (got %s); skipping it while loading sources for %s",
                        tostring(appearanceSourceID), tostring(appearanceID), tostring(itemID), tostring(self.item:GetItemLink())))
                end
            elseif failedSourceItemLoads[itemID] then
                -- Server already refused this item this session; don't ask again
            -- Using CaerdonItemEventListener instead of CaerdonItem here to avoid recursively diving
            elseif not waitingForItems[itemID] then
                -- Remember which source produced this item ID so load failures can report it
                waitingForItems[itemID] = appearanceSourceID
                CaerdonItemEventListener:AddCallback(itemID, GenerateClosure(ProcessTheItem, itemID),
                    GenerateClosure(FailTheItem, itemID))
            end
        end

        if #waitingForItems == 0 then
            callbackFunction()
        end
    end

    return function() end -- No cancel function for now
end

-- Allows for override of continue return if additional data needs to get loaded from a specific mixin (i.e. equipment sources)
function CaerdonEquipmentMixin:ContinueOnItemDataLoad(callbackFunction)
    if type(callbackFunction) ~= "function" or self.item:IsItemEmpty() then
        error("Usage: NonEmptyItem:ContinueOnLoad(callbackFunction)", 2);
    end

    self:LoadSources(callbackFunction)
end

-- Allows for override of continue return if additional data needs to get loaded from a specific mixin (i.e. equipment sources)
function CaerdonEquipmentMixin:ContinueWithCancelOnItemDataLoad(callbackFunction)
    if type(callbackFunction) ~= "function" or self.item:IsItemEmpty() then
        error("Usage: NonEmptyItem:ContinueOnLoad(callbackFunction)", 2);
    end

    return self:LoadSources(callbackFunction)
end

-- A bag slot as one number, the key of a copy in the index below. A piece outside the bags is
-- under its inventory slot, which is below every bag slot's number.
local function SetPlace(bag, slot)
    return (bag + 100) * 1000 + slot
end

local function ListSetName(names, key, name)
    local list = names[key]
    if not list then
        list = {}
        names[key] = list
    end
    list[#list + 1] = name
end

-- The names of the equipment sets that hold a piece in the bags or the bank, in the order of the
-- client's set list, asked two ways. byPlace: the copy at a place, which is the game's own answer,
-- since a set names where each of its pieces lies. Of two copies with one link, only the one a
-- set names is in it, and each of two sets' copies is in its own. byLink: a piece with that link,
-- for an item that lies nowhere (GetEquipmentSetsOf); a set names a link once. A piece that is
-- worn is in neither, as before the index.
--
-- Walking every set's every slot is the same work whichever item asks, and every equipment button
-- asks, twice on its first draw. So the walk is done once and kept for the rest of the frame
-- (GetTime() does not move within one): the draws of a frame share it, and nothing has to tell it
-- that a piece moved, a set changed or the bank opened. (equipmentSetIndex is declared with the
-- other caches, above InvalidateCaches.)
local function BuildEquipmentSetIndex()
    local index = { byPlace = {}, byLink = {} }
    if not C_EquipmentSet.CanUseEquipmentSets() then
        return index
    end

    local equipmentSetIDs = C_EquipmentSet.GetEquipmentSetIDs()
    for setIndex = 1, #equipmentSetIDs do
        local equipmentSetID = equipmentSetIDs[setIndex]
        local name = C_EquipmentSet.GetEquipmentSetInfo(equipmentSetID)
        local equipLocations = C_EquipmentSet.GetItemLocations(equipmentSetID)
        if equipLocations then
            local listedLinks = nil
            for locationIndex = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
                local location = equipLocations[locationIndex]
                if location ~= nil then
                    local locationData = EquipmentManager_GetLocationData(location)
                    local equipSlot = tonumber(locationData.slot)
                    local equipBag = tonumber(locationData.bag)

                    local place = nil
                    local foundLink = nil
                    if locationData.isBank and not locationData.bag then -- main bank container
                        place = equipSlot
                        foundLink = GetInventoryItemLink("player", equipSlot)
                    elseif locationData.isBank or locationData.isBags then -- any other bag
                        place = SetPlace(equipBag, equipSlot)
                        local itemLocation = ItemLocation:CreateFromBagAndSlot(equipBag, equipSlot)
                        if itemLocation:HasAnyLocation() and itemLocation:IsValid() then
                            foundLink = C_Item.GetItemLink(itemLocation)
                        end
                    end

                    if place then
                        ListSetName(index.byPlace, place, name)
                    end
                    if foundLink and not (listedLinks and listedLinks[foundLink]) then
                        listedLinks = listedLinks or {}
                        listedLinks[foundLink] = true
                        ListSetName(index.byLink, foundLink, name)
                    end
                end
            end
        end
    end

    return index
end

-- The names of the equipment sets an item is part of, or nil. An item that lies somewhere is
-- asked as that copy. One known only by its link (the mail, a merchant's row, the bags a bag
-- addon remembers) has no copy to ask about and is in the sets of a piece with its link. The
-- list belongs to the index: read it, do not change it.
function CaerdonEquipment:GetEquipmentSetsOf(item)
    local now = GetTime()
    if not equipmentSetIndex or equipmentSetIndexTime ~= now then
        equipmentSetIndex = BuildEquipmentSetIndex()
        equipmentSetIndexTime = now
    end

    local itemLocation = item:GetItemLocation()
    if itemLocation and itemLocation:HasAnyLocation() then
        if itemLocation:IsBagAndSlot() then
            return equipmentSetIndex.byPlace[SetPlace(itemLocation:GetBagAndSlot())]
        end
        return equipmentSetIndex.byPlace[itemLocation:GetEquipmentSlot()]
    end

    local itemLink = item:GetItemLink()
    return itemLink and equipmentSetIndex.byLink[itemLink] or nil
end

function CaerdonEquipmentMixin:GetEquipmentSets()
    return CaerdonEquipment:GetEquipmentSetsOf(self.item)
end

-- The loadout that is on: what is worn, as the addon judges it (loadouts.worn); else the
-- loadout of the gear set being worn, another spec's, where the player asked for the arrows for
-- other gear. nil where neither is there.
local function GetLoadoutThatIsOn()
    local loadouts = GetLoadouts()
    if loadouts.worn then
        return loadouts.worn
    end
    if loadouts.activeSet then
        local iconConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon
        if iconConfig ~= nil and iconConfig.ShowOtherSpecUpgrades == true then
            for _, other in ipairs(loadouts) do
                if other.setID == loadouts.activeSet.id then
                    return other
                end
            end
        end
    end
    return nil
end

-- For a comparison tooltip: what putting the piece in the place of one worn piece would do for
-- the loadout that is on, or nil. A piece for a slot that comes twice (rings, weapons) is judged
-- against the weaker of the two; which of them it would replace, and what it would do to the
-- other, is what this says, one worn piece at a time.
--   The loadout that is on is what is worn (worn = true), on the played spec's scale, where the
--   worn gear is the addon's to judge (loadouts.worn). Where the gear set being worn is another
--   spec's it is that set's loadout, if the player asked for the arrows for other gear and the
--   set has this worn piece in the slot.
--   No other loadout, though its set has this worn piece too (author decision): the client's
--   comparison is about what is on, and what the piece would be for the other loadouts is in
--   its own tooltip, beside this one.
--   What is worn is asked whatever specs the client lists the piece for, as in the item's
--   own tooltip (GetLoadoutUpgrades); another spec's set only for a piece listed for its spec.
-- A list of that one entry: { name, icon, colour, worn, percent (rounded, signed; nil against a
-- piece the scale gives no value), upgrade (more than Pawn's threshold above it), otherSpecs
-- (for what is worn: the piece is gear for another loot spec, OtherLootSpecsOf), atLevel
-- (LevelToCome) }. What Pawn's
-- check refuses is refused here, and a trinket has no value to go by. With nil comes why
-- there is nothing, for the export.
--[[static]]
function CaerdonEquipment:GetReplacementGains(item, wornItem)
    local link = item and item:GetItemLink()
    local wornLink = wornItem and wornItem:GetItemLink()
    if not link or not wornLink then
        return nil, "a piece without a link"
    end
    if link == wornLink then
        return nil, "the worn piece itself"
    end
    if IsKnownByAnotherLink(item) then
        return nil, "the link shown is the plain item's, not the piece's (a row the auction house names by item key): no value of it is the piece's"
    end
    local inventoryTypeName = item:GetInventoryTypeName()
    if inventoryTypeName == "INVTYPE_TRINKET" or inventoryTypeName == "INVTYPE_TABARD" or
        inventoryTypeName == "INVTYPE_BODY" then
        return nil, "a trinket, a tabard or a shirt has no value to go by"
    end
    local inventorySlots = GetInventorySlotsForType(inventoryTypeName)
    if not inventorySlots then
        return nil, "not a piece for a slot"
    end
    -- The slot the worn piece is in, among those the piece would go in: by its link, else by
    -- its item (a tooltip's link can differ from the slot's in the fields that are not the item).
    -- A weapon is looked for in both hands: a two-hander stands against the off hand's piece
    -- as well, and a one-hander for the off hand against a two-hander in the main hand.
    local handKind = HAND_KINDS[inventoryTypeName]
    if handKind then
        inventorySlots = BOTH_HANDS
    end
    local wornSlot
    for _, slotID in ipairs(inventorySlots) do
        if GetInventoryItemLink("player", slotID) == wornLink then
            wornSlot = slotID
            break
        end
    end
    if not wornSlot then
        local wornID = wornItem:GetItemID()
        for _, slotID in ipairs(inventorySlots) do
            if wornID and GetInventoryItemID("player", slotID) == wornID then
                wornSlot = slotID
                break
            end
        end
    end
    if not wornSlot then
        return nil, "the worn piece shown is in no slot the piece would take"
    end

    local loadout = GetLoadoutThatIsOn()
    if not loadout then
        if CaerdonAPI:GetTalentTrees() then
            return nil, "no loadout the addon scores is on (no talent tree leads, or Pawn has no scale for the leading tree)"
        end
        return nil, "no loadout the addon scores is on (no Pawn scale for the played spec, or the gear set worn is not that spec's)"
    end

    local ok, gains, why = pcall(function()
        if IsArmorTypeRefused(link) then
            return nil, "not the class's armor type, or Pawn has not read the piece yet"
        end
        local itemSpecs = C_Item.GetItemSpecInfo(link)
        if not loadout.isWorn and itemSpecs and #itemSpecs > 0 and loadout.id then
            local forSpec = false
            for _, specID in ipairs(itemSpecs) do
                if specID == loadout.id then
                    forSpec = true
                    break
                end
            end
            if not forSpec then
                return nil, "the client does not list the piece for the spec of the set that is on"
            end
        end
        if IsWeaponKindRefused(loadout, inventoryTypeName) then
            return nil, "a kind of weapon the scale is told not to show"
        end
        if UnlikeRangedPiece(loadout, inventoryTypeName, inventorySlots) then
            return nil, UNLIKE_RANGED .. " on a scale that weighs ranged damage"
        end
        -- The off hand's piece, for a weapon whose hands are judged apart: on that hand's own
        -- scale, and against that piece alone (JudgeOffHand).
        local offScale = handKind and wornSlot == INVSLOT_OFFHAND and HandsApart(loadout, inventoryTypeName) or nil
        SetPvpMode(loadout, link, handKind and BOTH_HANDS or { wornSlot })
        local baseline = LoadoutBaseline(loadout, wornSlot, offScale and offScale.name or nil)
        local value = baseline and LoadoutValue(loadout, offScale and offScale.name or loadout.scale, link)
        if not value then
            return nil, "Pawn has no value on the scale for one of the two pieces"
        end
        -- What the piece would be worth in the worn piece's place, and what is there now: for
        -- a weapon weighed for both hands, the hands'.
        local total, toBeat, pair = value, baseline.value, nil
        if handKind and not offScale then
            local how, pairTotal, pairToBeat, note = WeaponComparison(loadout, link, value, handKind,
                inventoryTypeName == "INVTYPE_WEAPONOFFHAND")
            if how == "pair" then
                total, toBeat, pair = pairTotal, pairToBeat, note
            elseif how == "slots" then
                local among = false
                for _, slotID in ipairs(pairTotal) do
                    among = among or slotID == wornSlot
                end
                if not among then
                    return nil, "the worn piece shown is in a hand the piece would not take"
                end
            else
                return nil, "nothing in the hands to compare the weapon with, or a two-hander against a ranged weapon"
            end
        end
        -- Only where the loadout has this worn piece in the slot: a set that is on with another
        -- piece of its own for the slot is measured against that one, in the item's own tooltip.
        if GetInventoryItemLink("player", wornSlot) ~= baseline.link then
            return nil, "the set that is on has another piece for the slot than the one worn"
        end
        local entry = { colour = loadout.colour, worn = loadout.isWorn or nil, pvp = loadout.pvp and not loadout.plain or nil,
            upgrade = total > toBeat * PAWN_UPGRADE_THRESHOLD,
            percent = toBeat > 0 and math.floor((total / toBeat - 1) * 100 + 0.5) or nil,
            atLevel = LevelToCome(item) }
        if pair then
            entry.pair = (pair == "both" or pair == "alone") and pair or "partner"
            entry.partner = entry.pair == "partner" and pair or nil
        end
        if loadout.isWorn then
            entry.otherSpecs = OtherLootSpecsOf(itemSpecs)
            entry.name = loadout.activeName or loadout.specName or loadout.label
            entry.icon = loadout.activeName and loadout.activeIcon or loadout.specIcon
        elseif baseline.fromSet then
            entry.name = loadout.setName or loadout.label
            entry.icon = loadout.setIcon or QUESTION_MARK_ICON
        else
            entry.name = loadout.specName or loadout.label
            entry.icon = loadout.specIcon
        end
        return { entry }
    end)
    if not ok then
        return nil, "an error: " .. tostring(gains)
    end
    return gains, why
end

-- Whether a piece can be scored for what is worn at all: Pawn is there, and it has a scale
-- for the spec being played, or for the leading talent tree on a client with those
-- (GetLoadouts found it). For a window that would make room for such a score.
--[[static]]
function CaerdonEquipment:CanScoreWornGear()
    return GetLoadouts().wornRead == true
end

-- Whether a higher item level alone gets a piece the upgrade arrow (ItemLevelCounts). For a
-- window that makes room for upgrades only where some could be shown.
--[[static]]
function CaerdonEquipment:CountsItemLevel()
    return ItemLevelCounts()
end

-- Whether the link a piece is known by is its own, so that Pawn is asked about it: not a row
-- named by item key at another level than its link's, or with a suffix its link does not
-- carry (IsKnownByAnotherLink).
--[[static]]
function CaerdonEquipment:IsKnownByItsOwnLink(item)
    return not IsKnownByAnotherLink(item)
end

-- Whether Pawn takes armor of this piece's type for the class, so that a piece of a lower
-- class than what is worn can still be an upgrade of Pawn's (PawnIsArmorBestTypeForPlayer,
-- read in Pawn 2.14.4). Pawn refuses the wrong type where the client has armor
-- specializations and the toon is of their level (retail, from 27). It takes cloth and leather
-- for any class that can wear them where there are none: Pawn's library knows WoW Forever for
-- a client of its own and gives it the classic rules, no specialization and mail and plate
-- from 40. Without Pawn nothing does: a lower class is no gain by item level alone. What
-- Pawn has not read yet counts as taken.
local function PawnTakesArmorType(link)
    if not (PawnGetItemData and PawnShouldItemLinkHaveUpgradeArrowUnbudgeted) then
        return false
    end
    if not PawnIsArmorBestTypeForPlayer then
        return true
    end
    local ok, takes = pcall(function()
        local data = PawnGetItemData(link)
        if not (data and data.Link and data.UnenchantedStats) then
            return true
        end
        return PawnIsArmorBestTypeForPlayer(data) and true or false
    end)
    return not ok or takes == true
end

-- Whether the client marks a piece's type as one the toon cannot use: the equip slot line of
-- its tooltip ("Relic | Idol" on a rogue), by isValidItemType, and by its right text in red
-- where a client has no such field. false where the tooltip has no such line or is not there.
local function IsTypeRefusedInTooltip(tooltip)
    for _, line in ipairs(type(tooltip) == "table" and tooltip.lines or {}) do
        if line.type == Enum.TooltipDataLineType.EquipSlot then
            if line.isValidItemType == false then
                return true
            end
            local color = line.rightColor
            if line.isValidItemType == nil and type(color) == "table" and color.GetRGB then
                local r, g, b = color:GetRGB()
                if r > 0.9 and g < 0.25 and b < 0.25 then
                    return true
                end
            end
        end
    end
    return false
end

-- Whether pieces of this item are of a kind the toon wears, as far as the item alone says. For
-- a window that would make room for what a list of such pieces has to say (the auction house's
-- results under a category of one kind: plate, one-handed axes).
--   The client does not mark the kind as one the toon cannot use: the equip slot line of the
--   item's tooltip (isValidItemType; its right text in red where a client has no such field).
--   That is also mail on a hunter under 40 where the classic rules hold.
--   It is not armor of a lower class than what is worn in its slot that Pawn would refuse
--   (IsLowerArmorClassThanEquipped, PawnTakesArmorType): by item level alone such a piece is
--   never a gain, so it is Pawn's to say, and Pawn's answer differs by client.
-- What cannot be told (no tooltip for the item yet) counts as worn.
--[[static]]
function CaerdonEquipment:IsKindWorn(itemID)
    local _, _, _, inventoryTypeName = C_Item.GetItemInfoInstant(itemID)
    if not inventoryTypeName then
        return true
    end
    local link = select(2, C_Item.GetItemInfo(itemID)) or ("item:" .. tostring(itemID))
    local piece = {
        GetItemLink = function() return link end,
        GetInventoryTypeName = function() return inventoryTypeName end,
    }
    if IsLowerArmorClassThanEquipped(piece) and not PawnTakesArmorType(link) then
        return false
    end
    local tooltip = C_TooltipInfo and C_TooltipInfo.GetItemByID and C_TooltipInfo.GetItemByID(itemID)
    return not IsTypeRefusedInTooltip(tooltip)
end

-- Whether a piece of this item could have a score for what is worn, as far as the item alone
-- says. For a window that would make room for one (the auction house's page of one item's
-- listings): no room for gear the toon cannot wear or would not (plate on a druid, cloth on a
-- leather wearer, a kind of weapon the scale has no value for or is told not to show, a
-- thrown weapon for a toon that shoots).
-- What cannot be told yet (the client or Pawn has not read the item) counts as it could.
--[[static]]
function CaerdonEquipment:CanScorePieceForWorn(itemID)
    if not self:CanScoreWornGear() then
        return false
    end
    local _, _, _, inventoryTypeName = C_Item.GetItemInfoInstant(itemID)
    if not inventoryTypeName or inventoryTypeName == "INVTYPE_TRINKET" or inventoryTypeName == "INVTYPE_TABARD" or
        inventoryTypeName == "INVTYPE_BODY" or not GetInventorySlotsForType(inventoryTypeName) then
        return false
    end
    local loadout = GetLoadoutThatIsOn()
    if not loadout then
        return false
    end
    local _, link = C_Item.GetItemInfo(itemID)
    if not link then
        return true
    end
    local ok, can = pcall(function()
        local data = PawnGetItemData(link)
        if not (data and data.Link) then
            return true
        end
        if PawnIsArmorBestTypeForPlayer and data.UnenchantedStats and not PawnIsArmorBestTypeForPlayer(data) then
            return false
        end
        if IsWeaponKindRefused(loadout, inventoryTypeName) or
            UnlikeRangedPiece(loadout, inventoryTypeName, GetInventorySlotsForType(inventoryTypeName)) then
            return false
        end
        local value = OtherSpecValue(loadout.scale, link)
        if value ~= nil and value > 0 then
            return true
        end
        -- A weapon the loadout's scale gives nothing, and its scale for the off hand does.
        local offScale = HandsApart(loadout, inventoryTypeName)
        local offValue = offScale and OtherSpecValue(offScale.name, link) or nil
        return offValue ~= nil and offValue > 0
    end)
    return not ok or can == true
end

-- For a row in a list of pieces of one kind (the auction house's listings of an item, which
-- differ in the stats they rolled): what the piece would do for the loadout that is on, in the
-- place of the worn piece it gains most over (the weaker of two rings). The entry
-- GetReplacementGains has for that worn piece, or nil and why.
--[[static]]
function CaerdonEquipment:GetBestReplacementGain(item)
    local inventorySlots = item and GetInventorySlotsForType(item:GetInventoryTypeName())
    if not inventorySlots then
        return nil, "not a piece for a slot"
    end
    -- A weapon: whichever hand holds what it is weighed against.
    if HAND_KINDS[item:GetInventoryTypeName()] then
        inventorySlots = BOTH_HANDS
    end
    local best, why
    for _, slotID in ipairs(inventorySlots) do
        local wornLink = GetInventoryItemLink("player", slotID)
        if wornLink then
            local worn = {
                GetItemLink = function() return wornLink end,
                GetItemID = function() return GetInventoryItemID("player", slotID) end,
            }
            local gains, reason = self:GetReplacementGains(item, worn)
            local gain = gains and gains[1]
            if gain and gain.percent and (not best or gain.percent > best.percent) then
                best = gain
            end
            why = why or reason
        end
    end
    if best then
        return best
    end
    return nil, why or "nothing is worn where the piece would go"
end

local ITEM_PROFICIENCY_USE_ERROR = Enum.TransmogUseErrorType and Enum.TransmogUseErrorType.ItemProficiency or 10
-- A source in no wardrobe category (Weapon / Miscellaneous such as the Arclight Spanner 6219):
-- the collection has nowhere to put it, so the item teaches nothing.
local NO_COLLECTION_CATEGORY = Enum.TransmogCollectionType and Enum.TransmogCollectionType.None or 0

-- Wowhead Transmog Guide - https://www.wowhead.com/transmogrification-overview-frequently-asked-questions
-- linkTooltip: what C_TooltipInfo.GetHyperlink said for the item's link, from a caller that has
-- just asked (the status). The PVP floor is read from it; without it the tooltip is fetched.
function CaerdonEquipmentMixin:GetTransmogInfo(linkTooltip)
    local item = self.item
    local itemLink = item:GetItemLink()
    local inventoryTypeName = item:GetInventoryTypeName()
    local isTabard = inventoryTypeName == "INVTYPE_TABARD"
    local isShirt = inventoryTypeName == "INVTYPE_BODY"
    local itemLocation = item:GetItemLocation()

    if item:GetCaerdonItemType() ~= CaerdonItemType.Equipment then
        return
    end

    local debugEnabled = CaerdonWardrobeConfig.Debug.Enabled
    local isBindOnPickup = item:GetBinding() == CaerdonItemBind.BindOnPickup
    local isCompletionistItem = false
    -- Uncollected source that is valid for this class with no class / race / faction error, yet
    -- neither this toon nor the account can collect it right now (see the return struct).
    local validSourceNotCollectable = false
    local validSourceNotCollectableKnownLook = false
    -- Uncollected source the class has no proficiency for (useErrorType ItemProficiency), and
    -- neither this toon nor the account can collect it (see the return struct).
    local proficiencySourceNotCollectable = false
    local proficiencySourceNotCollectableKnownLook = false
    -- The item's source is in no wardrobe category, so neither flag above may be set for it.
    local noCollectionCategory = false
    local hasMetRequirements = true
    local needsItem = false
    local otherNeedsItem = false
    local matchesLootSpec = true
    local isTransmog = false
    local otherSourceFound = false
    local otherSourceFoundForPlayer = false
    local canCollect = false
    local playerCanUseSource = nil
    local playerCanCollectSource = false
    local playerCollectInfoReady = false
    local playerLootSpecID
    local _, _, playerClassID = UnitClass("player")
    local sourceUseErrorType
    local sourceUseError
    local validSourceInfoForPlayer
    local candidate = NewCandidate(item, linkTooltip)
    local uniqueUpgradeBlocked, uniqueUpgradeCandidate, uniqueCategoryKey = GetUniqueUpgradeInfo(candidate)
    local betterItemEquipped, betterItemEquippedViaPvp = HasBetterOrEqualEquippedItem(candidate)
    local equalItemLevelEquipped, tiedEquippedSlots = HasEqualEquippedItemLevel(candidate)
    local identicalToEquipped, equippedLineComparison = IsIdenticalToTiedEquipped(item, tiedEquippedSlots)
    local upgradeItemLevelDelta = GetUpgradeItemLevelDelta(candidate)
    local lowerArmorClassThanEquipped = IsLowerArmorClassThanEquipped(item)
    local isArtifactItem = false
    local blockedOffhandSlot = IsOffhandSlotBlocked(inventoryTypeName)
    local isRecraftable = item:IsRecraftable()
    if itemLocation and itemLocation:IsValid() and C_ArtifactUI and C_ArtifactUI.IsArtifactItem then
        isArtifactItem = C_ArtifactUI.IsArtifactItem(itemLocation)
    end
    if not isArtifactItem then
        local itemQuality = item:GetItemQuality()
        if itemQuality and itemQuality == Enum.ItemQuality.Artifact then
            isArtifactItem = true
        end
    end

    -- Keep available for debug info
    local appearanceInfo, sourceInfo
    local isInfoReady, accountCanCollect
    local appearanceSources
    local currentSourceFound
    local sourceSpecs
    local lowestLevelFound
    local isNotReady = false
    local matchedSources = {}

    -- Appearance is the visual look - can have many sources
    -- Sets can have multiple appearances (normal vs mythic, etc.)
    local appearanceID, sourceID
    sourceSpecs = C_Item.GetItemSpecInfo(itemLink)
    if playerLootSpecID == nil then
        playerLootSpecID = GetPlayerLootSpecID()
    end

    if sourceSpecs and #sourceSpecs > 0 and playerLootSpecID and playerLootSpecID > 0 then
        matchesLootSpec = false
        for _, validSpecID in ipairs(sourceSpecs) do
            if validSpecID == playerLootSpecID then
                matchesLootSpec = true
                break
            end
        end
    end

    if item.extraData and item.extraData.appearanceSourceID then
        sourceID = item.extraData.appearanceSourceID
        appearanceID = item.extraData.appearanceID
        if not appearanceID then
            local extraInfo = C_TransmogCollection.GetAppearanceInfoBySource(sourceID)
            if extraInfo then
                appearanceID = extraInfo.appearanceID
            end
        end
    else
        appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemLink)
        if not sourceID or not appearanceID then
            -- Fallback: try with just the itemID (handles world quest items with bonus IDs
            -- that GetItemInfo(itemLink) doesn't recognize)
            local itemID = item:GetItemID()
            if itemID then
                appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemID)
            end
        end
        if (not sourceID or not appearanceID) and C_Item.IsDressableItemByID(item:GetItemID()) then -- not finding via transmog collection so need to do the DressUp hack
            local inventoryType = item:GetInventoryTypeName()
            local slotID = slotTable[inventoryType]

            -- print(item:GetItemLink() .. " is dressable")

            if not CaerdonWardrobe.dressUp then
                CaerdonWardrobe.dressUp = CreateFrame("DressUpModel")
                CaerdonWardrobe.dressUp:SetUnit('player')
            end

            if slotID and slotID > 0 then
                isTransmog = true
                -- Don't think I need to do this unless weapons cause some sort of problem?
                -- CaerdonWardrobe.dressUp:Undress()
                CaerdonWardrobe.dressUp:TryOn(itemLink, slotID)
                local transmogInfo = CaerdonWardrobe.dressUp:GetItemTransmogInfo(slotID)
                if transmogInfo then
                    sourceID = transmogInfo.appearanceID -- I don't know why, but it is.
                    if sourceID and sourceID ~= Constants.Transmog.NoTransmogID then
                        local appearanceSourceInfo = CaerdonAPI and CaerdonAPI.GetAppearanceSourceInfo and
                            CaerdonAPI:GetAppearanceSourceInfo(sourceID)
                        if appearanceSourceInfo and appearanceSourceInfo.appearanceID then
                            appearanceID = appearanceSourceInfo.appearanceID
                        end
                    end
                end
            end
        end
    end

    -- if sourceID then
    -- TODO: Look into this more - doc indicates it's an itemModifiedAppearanceID returned from C_TransmogCollection.GetItemInfo (which may also be sourceID?)
    -- PlayerKnowsSource just seems broken if that's true, though.
    -- VisualID == AppearanceID, SourceID == ItemModifiedAppearanceID
    -- Also check PlayerHasTransmog with the following
    -- print(itemLink .. ",  PlayerHasTransmogItemModifiedAppearance: " .. tostring(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID)) .. ", PlayerKnowsSource: " .. tostring(C_TransmogCollection.PlayerKnowsSource(sourceID)))
    -- end

    if item:GetMinLevel() and item:GetMinLevel() > UnitLevel("player") then
        hasMetRequirements = false
    end

    if sourceID and sourceID ~= Constants.Transmog.NoTransmogID then
        isTransmog = true

        local hasItemData
        hasItemData, accountCanCollect = C_TransmogCollection.AccountCanCollectSource(sourceID)
        playerCollectInfoReady, playerCanCollectSource = C_TransmogCollection.PlayerCanCollectSource(sourceID)

        -- if not isInfoReady then
        --     print('Info not ready - source ID ' .. tostring(sourceID) .. ' for ' .. itemLink)
        -- end

        -- Only returns for sources that can be transmogged by current toon right now
        appearanceInfo = C_TransmogCollection.GetAppearanceInfoBySource(sourceID)
        if not appearanceID and appearanceInfo and appearanceInfo.appearanceID then
            appearanceID = appearanceInfo.appearanceID
        end

        sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
        if sourceInfo then
            noCollectionCategory = sourceInfo.categoryID == NO_COLLECTION_CATEGORY
            if not sourceUseErrorType and sourceInfo.useErrorType then
                sourceUseErrorType = sourceInfo.useErrorType
            end
            if not sourceUseError and sourceInfo.useError then
                sourceUseError = sourceInfo.useError
            end

            if (playerCollectInfoReady and playerCanCollectSource) or sourceInfo.playerCanCollect or sourceInfo.isValidSourceForPlayer then
                playerCanUseSource = true
            elseif playerCanUseSource ~= true then
                playerCanUseSource = false
            end
        end
        -- TODO: If no appearance ID by now, might be able to use VisualID returned from here?  Not sure if needed...
        -- If the source is already collected, we don't need to check anything else for the source / appearance
        if sourceInfo and not sourceInfo.isCollected then
            -- Cross-check: if another API confirms this source IS collected, sourceInfo is stale
            if (appearanceInfo and appearanceInfo.sourceIsCollected) or
               C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID) then
                isNotReady = true
            end
            if playerCollectInfoReady then
                canCollect = playerCanCollectSource
            else
                isNotReady = true
                canCollect = sourceInfo.playerCanCollect
            end
            currentSourceFound = sourceInfo.isCollected
            -- Both collect verdicts are final (not "false because the data is still loading").
            local collectInfoReady = playerCollectInfoReady and hasItemData

            local isValidSourceForPlayer = sourceInfo.isValidSourceForPlayer
            if appearanceID then
                local sourceIndex, source
                -- GetAllAppearanceSources includes hidden and otherwise unusable sources, so it's the most thorough
                local appearanceSourceIDs = appearanceSourcesCache[appearanceID]
                if not appearanceSourceIDs then
                    appearanceSourceIDs = C_TransmogCollection.GetAllAppearanceSources(appearanceID)
                    appearanceSourcesCache[appearanceID] = appearanceSourceIDs
                end
                for sourceIndex, source in pairs(appearanceSourceIDs) do
                    local info = sourceInfoCache[source]
                    if not info then
                        info = C_TransmogCollection.GetSourceInfo(source)
                        if info then
                            sourceInfoCache[source] = info
                        end
                    end

                    if info then
                        if not appearanceSources then
                            appearanceSources = {}
                        end

                        table.insert(appearanceSources, info)

                        -- Check if we've already collected it and if it works for the current toon
                        if info.sourceID == sourceID then
                            if not sourceUseErrorType and info.useErrorType then
                                sourceUseErrorType = info.useErrorType
                            end
                            if not sourceUseError and info.useError then
                                sourceUseError = info.useError
                            end
                        end

                        if info.sourceID ~= sourceID then -- already checked the current item's info
                            if info.isCollected then
                                if info.isValidSourceForPlayer then
                                    otherSourceFoundForPlayer = true
                                    playerCanUseSource = true
                                else
                                    otherSourceFound = true
                                    if playerCanUseSource ~= true then
                                        playerCanUseSource = false
                                    end
                                end
                            end
                        elseif info.isValidSourceForPlayer then
                            playerCanUseSource = true
                        elseif playerCanUseSource ~= true then
                            playerCanUseSource = false
                        end
                    end

                    -- What follows only feeds the debug details (matchedSources, lowestLevelFound),
                    -- so the client is asked about each source's item only with debug on. The
                    -- answers are kept on the cached info.
                    if info and debugEnabled then
                        if not info.itemSubTypeID then
                            local _, sourceType, sourceSubType, sourceEquipLoc, _, sourceTypeID, sourceSubTypeID = C_Item
                                .GetItemInfoInstant(info.itemID)
                            -- SubTypeID is returned from GetAppearanceSourceInfo, but it seems to be tied to the appearance, since it was wrong for an item that crossed over.
                            info.itemSubTypeID = sourceSubTypeID
                        end

                        -- Not for an item the client refuses: this question draws another refusal.
                        if info.cachedMinLevel == nil and not refusedItems[info.itemID] then
                            info.cachedMinLevel = (select(5, C_Item.GetItemInfo(info.itemID))) or false
                        end
                        local sourceMinLevel = info.cachedMinLevel or nil
                        if lowestLevelFound == nil or sourceMinLevel and sourceMinLevel < lowestLevelFound then
                            lowestLevelFound = sourceMinLevel
                        end

                        if info.isCollected and (item:GetItemSubTypeID() == info.itemSubTypeID or info.itemSubTypeID == Enum.ItemArmorSubclass.Cosmetic) then
                            -- Log any matched sources even if they're treated as not found due to other logic below
                            table.insert(matchedSources, info)
                        end
                    end
                end

                if not currentSourceFound then
                    if canCollect and isValidSourceForPlayer then
                        needsItem = true
                        isCompletionistItem = otherSourceFoundForPlayer
                    elseif accountCanCollect then
                        otherNeedsItem = true
                        isCompletionistItem = otherSourceFound
                    elseif noCollectionCategory then
                        -- Nothing to learn: the "selling it teaches the look" cases below are
                        -- all sources the wardrobe has a category for.
                    elseif collectInfoReady and isValidSourceForPlayer and not sourceInfo.useErrorType then
                        validSourceNotCollectable = true
                        validSourceNotCollectableKnownLook = otherSourceFoundForPlayer or otherSourceFound
                    elseif collectInfoReady and not isValidSourceForPlayer and
                        sourceInfo.useErrorType == ITEM_PROFICIENCY_USE_ERROR then
                        proficiencySourceNotCollectable = true
                        proficiencySourceNotCollectableKnownLook = otherSourceFoundForPlayer or otherSourceFound
                    end
                end
            else
                -- No appearance ID means we can't enumerate alternates, but we still know the source is collectible.
                if canCollect and isValidSourceForPlayer then
                    needsItem = true
                elseif accountCanCollect then
                    otherNeedsItem = true
                elseif noCollectionCategory then
                    -- Nothing to learn (see above).
                elseif collectInfoReady and isValidSourceForPlayer and not sourceInfo.useErrorType then
                    validSourceNotCollectable = true
                elseif collectInfoReady and not isValidSourceForPlayer and
                    sourceInfo.useErrorType == ITEM_PROFICIENCY_USE_ERROR then
                    proficiencySourceNotCollectable = true
                end
            end
        end
    else
        -- No source ID for some reason - last resort effort but assume another toon needs it.
        local itemLocation = item:GetItemLocation()
        needsItem = false
        local itemInfoName = C_Item.GetItemInfo(item:GetItemLink())
        if itemInfoName then
            otherNeedsItem = not C_TransmogCollection.PlayerHasTransmogByItemInfo(itemInfoName)
        else
            -- Item not cached yet; defer so we don't pass nil into the API and so
            -- the retry mechanism re-evaluates once the item data is available.
            isNotReady = true
        end
        canCollect = true
        playerCanCollectSource = true
        playerCollectInfoReady = true
        if playerCanUseSource == nil then
            playerCanUseSource = true
        end
    end

    local sourceUseErrorBlocks = sourceUseErrorType and sourceUseErrorType ~= Enum.TransmogUseErrorType.None
    if sourceUseErrorBlocks then
        playerCanUseSource = false
    end

    if playerCanUseSource == nil then
        playerCanUseSource = true
    end

    -- The type of a piece with no look is not the toon's, at any level: the status does not
    -- take such a piece for one to use later.
    local typeRefused = false
    if not isTransmog then
        -- A piece with no look has no source to say whether the toon can use it (a relic, a
        -- thrown weapon; a ring or a trinket has no type to refuse). The equip slot line of its
        -- tooltip says it, and another class's relic is no upgrade at any level. Seen (WoW
        -- Forever 1.60.1.70959): an idol on a rogue, "Relic | Idol" with the type in red and
        -- isValidItemType false, had the arrow of an upgrade to come, because its level was
        -- too high as well and red text was read as that alone.
        local tooltip = linkTooltip
        if tooltip == nil and itemLink and C_TooltipInfo and C_TooltipInfo.GetHyperlink then
            tooltip = C_TooltipInfo.GetHyperlink(itemLink)
        end
        typeRefused = IsTypeRefusedInTooltip(tooltip)
        playerCanUseSource = not typeRefused
    end

    local upgradeMatchesSpec = matchesLootSpec ~= false

    local isUpgrade = nil

    -- Whether raising the piece on its upgrade track gives a look that is not known is not
    -- asked here: CaerdonTransformLooks.lua, from the status code.

    local shouldShowUpgrade = false
    local pawnIdentifiedUpgrade = false
    local pawnAvailable = PawnShouldItemLinkHaveUpgradeArrowUnbudgeted ~= nil
    local pawnRecommended -- raw Pawn verdict: true / false / nil (nil = Pawn has no data yet)
    -- Pawn's verdict covers every visible scale. On a client without specializations that is one
    -- scale per talent tree, so an upgrade that only another tree's scale sees keeps its arrow
    -- but is flagged (pawnOffTreeUpgrade) and drawn as an off-spec upgrade.
    local pawnOffTreeScales = nil
    local pawnOffTreeOnly = false
    local pawnOffTreeUpgrade = false
    local pawnUpgradeScales = nil
    -- The addon's own verdict for what is worn, on the worn gear's scale (GetWornJudge,
    -- JudgeWorn): "upgrade", "equipped" or nil, with its numbers. Where there is one it is the
    -- yellow arrow's, and Pawn's word for that scale does not count.
    local wornJudge, wornJudgeHidden = nil, nil
    local ownVerdict, ownValue, ownLowest, ownEmptySlot, ownPair = nil, nil, nil, nil, nil
    -- A weapon whose hands are judged apart: the off hand's own verdict, on its own scale
    -- (JudgeOffHand's table). The verdict on the worn gear's scale is then the main hand's
    -- (ownMain), and the piece's is an upgrade where either hand's is.
    local ownMain, ownOff = nil, nil
    -- The scales the addon had a verdict of its own on (scale name -> true), and those on
    -- which Pawn's word is left out for a ranged weapon of another kind than the one worn
    -- (unlikeScales, UnlikeRangedScales).
    local ownJudgedScales = nil
    local unlikeScales = nil
    -- The other specs whose scale Pawn shows and whose gear set decides in Pawn's place
    -- (GetShownSetSpecs), whether Pawn's verdict stands for any scale it named, and for which.
    local pawnSetSpecs, pawnStands, pawnStandingScales = nil, nil, nil
    -- The link is not the piece's own (IsKnownByAnotherLink): Pawn would be judging another
    -- piece, so it is not asked, by its arrow, its scores or the loadouts, and item level decides.
    local knownByAnotherLink, anotherLinkBy = IsKnownByAnotherLink(item)
    if PawnShouldItemLinkHaveUpgradeArrowUnbudgeted and not knownByAnotherLink then
        NotePawnItemLevelOption()
        pawnRecommended = PawnShouldItemLinkHaveUpgradeArrowUnbudgeted(item:GetItemLink(), false)
        pawnOffTreeScales = GetPawnOffTreeScales()
        wornJudge, wornJudgeHidden = GetWornJudge()
        if wornJudge then
            ownMain, ownValue, ownLowest, ownEmptySlot, ownPair, ownOff = JudgeWorn(item, wornJudge)
            ownVerdict = EitherHand(ownMain, ownOff)
            if ownVerdict then
                ownJudgedScales = {}
                if ownMain then
                    ownJudgedScales[wornJudge.scale] = true
                end
                if ownOff then
                    ownJudgedScales[ownOff.scale] = true
                end
            end
        end
        unlikeScales = UnlikeRangedScales(inventoryTypeName)
        if unlikeScales then
            ownJudgedScales = ownJudgedScales or {}
            for scaleName in pairs(unlikeScales) do
                ownJudgedScales[scaleName] = true
            end
        end
        -- Another spec with a gear set is measured against that set, further down, and not by
        -- Pawn's verdict for its shown scale, which is against the worn gear.
        pawnSetSpecs = pawnOffTreeScales and GetShownSetSpecs(pawnOffTreeScales) or nil
        -- Pawn's verdict as far as it counts: not where it is only for specs the player
        -- switched off or specs whose gear set decides.
        pawnStands = pawnRecommended
        if pawnRecommended and (pawnOffTreeScales or ownJudgedScales) then
            local noneStands
            pawnOffTreeOnly, pawnUpgradeScales, noneStands, pawnStandingScales =
                IsPawnUpgradeOffTreeOnly(item, pawnOffTreeScales or NO_SCALES, pawnSetSpecs, ownJudgedScales)
            if noneStands then
                pawnStands = false
            end
        end
        local pawnUpgrade = pawnStands
        -- An upgrade on the worn gear's own scale: the toon's own, whatever Pawn says of the
        -- piece on that scale, or the shown scales of its other specs.
        if ownVerdict == "upgrade" then
            pawnUpgrade = true
            pawnOffTreeOnly = false
            -- The scale of each hand the piece is an upgrade in.
            pawnUpgradeScales = ownMain == "upgrade" and wornJudge.label or nil
            if ownOff and ownOff.verdict == "upgrade" then
                pawnUpgradeScales = (pawnUpgradeScales and pawnUpgradeScales .. ", " or "") .. ownOff.label
            end
        end
        if pawnUpgrade then
            -- Not where the addon weighed the piece with one for the main hand against the
            -- two-hander that is worn, and the two are the better.
            if blockedOffhandSlot and ownVerdict ~= "upgrade" then
                pawnUpgrade = false
            end
            if playerLootSpecID == nil then
                playerLootSpecID = GetPlayerLootSpecID()
            end

            -- A piece for another loot spec keeps Pawn's verdict: the played spec's scale has
            -- weighed it, so it is an upgrade for what is worn, and is drawn as one whatever
            -- Icon.ShowOtherSpecUpgrades says, in the other spec's red (the drawing reads
            -- upgradeMatchesSpec with pawnIdentifiedUpgrade).
            if uniqueUpgradeBlocked then
                pawnUpgrade = false
            end
        elseif uniqueUpgradeCandidate and not uniqueUpgradeBlocked then
            pawnUpgrade = true
        end

        -- Suppress Pawn upgrades when our PVP-aware comparison shows the
        -- equipped item is actually better. Pawn compares against base ilvl
        -- and doesn't know about PVP scaling, so it over-identifies upgrades
        -- when PVP gear is equipped. Only PVP scaling justifies overriding
        -- Pawn: on a plain item-level comparison Pawn's stat weights win
        -- (a lower-ilvl dagger can be a real upgrade over a higher-ilvl axe).
        if pawnUpgrade and betterItemEquipped and betterItemEquippedViaPvp then
            pawnUpgrade = false
        end

        if pawnUpgrade and (pawnStands or ownVerdict == "upgrade") then
            if pawnOffTreeOnly then
                pawnOffTreeUpgrade = true
            else
                pawnIdentifiedUpgrade = true
            end
        end

        shouldShowUpgrade = pawnUpgrade
    elseif uniqueUpgradeCandidate and not uniqueUpgradeBlocked then
        shouldShowUpgrade = true
    end

    -- Item-level fallback: never fires for a lower armor class than what is equipped
    -- (Pawn may still flag such an item above if its stat weights say so). It also stands down
    -- when Pawn scored both items and rates the equipped one at least as high: after equipping a
    -- lower-ilvl piece Pawn recommended, the higher-ilvl piece just taken off is not an upgrade.
    -- When a Pawn upgrade for another talent tree only was blocked above, it counts as "not
    -- recommended" here and the scores are compared on the toon's own scales alone.
    --
    -- With Pawn loaded the fallback is the player's choice: Icon.ShowItemLevelUpgrades switches
    -- it off altogether, and Icon.ItemLevelOverPawn lets it stand against Pawn's scores (a gear
    -- score to reach, a game mode that goes by item level). Without Pawn it is all there is.
    local pawnPrefersEquipped = false
    local pawnComparison = ownVerdict == "upgrade" and
        WornDetail(wornJudge, wornJudgeHidden, ownValue, ownLowest, ownEmptySlot, ownPair, ownOff) or nil
    -- A higher item level that would be the upgrade, with the arrow for it switched off.
    local levelGainOnly = false
    local iconConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon or nil
    local itemLevelCounts = ItemLevelCounts()
    local itemLevelOverPawn = pawnAvailable and itemLevelCounts and iconConfig ~= nil and
        iconConfig.ItemLevelOverPawn == true
    if not shouldShowUpgrade and upgradeItemLevelDelta and upgradeItemLevelDelta > 0 and not uniqueUpgradeBlocked and
        not isTabard and not lowerArmorClassThanEquipped then
        if itemLevelOverPawn then
            pawnComparison = "a higher item level counts whatever Pawn's scores say (the addon's setting)"
        elseif ownVerdict == "equipped" then
            -- The worn gear's own scale rates the worn piece at least as high.
            pawnPrefersEquipped, pawnComparison = true,
                WornDetail(wornJudge, wornJudgeHidden, ownValue, ownLowest, ownEmptySlot, ownPair, ownOff)
        elseif unlikeScales then
            -- A ranged weapon of another kind than the one worn, with no verdict of the
            -- addon's: a higher item level says no more than Pawn's values did.
            pawnPrefersEquipped, pawnComparison = true, UNLIKE_RANGED .. " (a scale Pawn shows weighs ranged damage)"
        elseif pawnRecommended == false or pawnOffTreeOnly then
            pawnPrefersEquipped, pawnComparison = PawnPrefersEquipped(item, pawnOffTreeScales)
        end
        if not pawnPrefersEquipped then
            if itemLevelCounts then
                shouldShowUpgrade = true
            else
                -- The setting takes the arrow, not the level gain, which has a setting of its
                -- own: the piece is no upgrade and keeps its gain for the drawing.
                levelGainOnly = true
                pawnComparison = "a higher item level alone gets no arrow (the addon's setting)"
            end
        end
    end

    -- No upgrade over what is worn: one for a loadout the toon keeps beside it (another spec,
    -- the played spec's gear set while another set's pieces are worn), where the player asked
    -- for those. Flagged like an upgrade that only another spec's visible Pawn scale sees, and
    -- drawn the same way. A spec with a gear set whose scale Pawn shows is asked whatever the
    -- setting says, as Pawn's verdict for that scale was; the drawing reads the setting.
    local wantsLoadouts = iconConfig ~= nil and iconConfig.ShowOtherSpecUpgrades == true
    if knownByAnotherLink then
        pawnComparison = pawnComparison or (anotherLinkBy == "suffix" and
            "Pawn is not asked: the link is the item's without the suffix the row names (a row named by item key)" or
            "Pawn is not asked: the link is the plain item's, at another item level than the piece (a row named by item key)")
    elseif not shouldShowUpgrade and (wantsLoadouts or pawnSetSpecs) and
        not uniqueUpgradeBlocked and not isTabard and not isShirt then
        local loadoutNames, loadoutNumbers = GetLoadoutUpgrades(item, sourceSpecs,
            not wantsLoadouts and pawnSetSpecs or nil)
        if loadoutNames then
            shouldShowUpgrade = true
            pawnOffTreeUpgrade = true
            pawnUpgradeScales = loadoutNames
            pawnComparison = "an upgrade for gear kept beside what is worn: " .. loadoutNumbers
        end
    elseif pawnOffTreeUpgrade and pawnSetSpecs then
        -- Pawn's verdict stands for a spec with no gear set, and it named specs with one too:
        -- those are the sets' to say, so the names are the ones that hold.
        local loadoutNames, loadoutNumbers = GetLoadoutUpgrades(item, sourceSpecs, pawnSetSpecs)
        pawnUpgradeScales = pawnStandingScales
        if loadoutNames then
            pawnUpgradeScales = (pawnUpgradeScales and pawnUpgradeScales .. ", " or "") .. loadoutNames
            pawnComparison = "also an upgrade for gear kept beside what is worn: " .. loadoutNumbers
        end
    end

    if shouldShowUpgrade and not playerCanUseSource then
        shouldShowUpgrade = false
    end

    if shouldShowUpgrade and blockedOffhandSlot and not pawnIdentifiedUpgrade then
        shouldShowUpgrade = false
    end

    if levelGainOnly and (not playerCanUseSource or blockedOffhandSlot) then
        levelGainOnly = false
    end

    if isTabard or isShirt then
        shouldShowUpgrade = false
        upgradeItemLevelDelta = nil
    end

    if not playerCanUseSource then
        upgradeItemLevelDelta = nil
    end

    if shouldShowUpgrade then
        isUpgrade = true
    else
        pawnOffTreeUpgrade = false
    end

    return {
        isUpgrade = isUpgrade,
        isTransmog = isTransmog,
        isBindOnPickup = isBindOnPickup,
        appearanceID = appearanceID,
        sourceID = sourceID,
        uniqueUpgradeBlocked = uniqueUpgradeBlocked,
        uniqueUpgradeCandidate = uniqueUpgradeCandidate,
        betterItemEquipped = betterItemEquipped,
        equalItemLevelEquipped = equalItemLevelEquipped,
        -- Every equipped piece that ties the item level has the same tooltip lines apart from the
        -- name: a duplicate, not a sidegrade, so the equal-level protection does not apply.
        -- equippedLineComparison is the per-slot verdict, for the Debug Frame export.
        identicalToEquipped = identicalToEquipped,
        equippedLineComparison = equippedLineComparison,
        upgradeItemLevelDelta = (shouldShowUpgrade or levelGainOnly) and upgradeItemLevelDelta or nil,
        pawnIdentifiedUpgrade = pawnIdentifiedUpgrade,
        -- Higher item level than the equipped piece, but Pawn scores the equipped piece at least
        -- as high on every visible scale, so the item-level upgrade arrow was withheld.
        pawnPrefersEquipped = pawnPrefersEquipped,
        -- The upgrade arrow comes from Pawn, but only for scales of a talent tree the toon has not
        -- specialised in (WoW Forever: every tree's scale is visible by default). isUpgrade stays
        -- true and pawnIdentifiedUpgrade false; the arrow is drawn in the off-spec colour.
        pawnOffTreeUpgrade = pawnOffTreeUpgrade,
        -- Debug Frame export text: the scales Pawn named for the upgrade (only looked up while
        -- off-tree scales are being ignored) and the per-scale scores behind pawnPrefersEquipped.
        pawnUpgradeScales = pawnUpgradeScales,
        pawnComparison = pawnComparison,
        upgradeMatchesSpec = upgradeMatchesSpec,
        isArtifactItem = isArtifactItem,
        uniqueCategoryKey = uniqueCategoryKey,
        canEquip = playerCanUseSource or canCollect,
        canEquipForPlayer = playerCanUseSource,
        typeRefused = typeRefused or nil,
        needsItem = needsItem,
        hasMetRequirements = hasMetRequirements,
        otherNeedsItem = otherNeedsItem,
        playerCanCollectSource = playerCollectInfoReady and playerCanCollectSource or canCollect,
        isCompletionistItem = isCompletionistItem,
        -- The class can use this uncollected source, yet both collect APIs say no (verdicts
        -- ready). Seen on WoW Forever for armor below the class's own type (cloth on a hunter)
        -- and armor the toon gains proficiency for later (mail on a hunter under 40); selling
        -- the item to a vendor teaches the appearance there, so CaerdonItem shows it as "own"
        -- instead of "collected". KnownLook: another source of the appearance is collected.
        validSourceNotCollectable = validSourceNotCollectable,
        validSourceNotCollectableKnownLook = validSourceNotCollectableKnownLook,
        -- The class has no proficiency for this uncollected source (useErrorType ItemProficiency,
        -- e.g. a wand on a hunter) and both collect APIs say no. Retail answers "can collect" for
        -- such a source, so this only shows up on WoW Forever, where selling the item to a vendor
        -- teaches the appearance anyway. CaerdonItem shows it as "other" instead of sellable.
        proficiencySourceNotCollectable = proficiencySourceNotCollectable,
        proficiencySourceNotCollectableKnownLook = proficiencySourceNotCollectableKnownLook,
        -- The source's categoryID is TransmogCollectionType.None: the wardrobe has no place for
        -- it, so it is never reported through the two "not collectable" flags above. Seen on
        -- WoW Forever for the Arclight Spanner 6219 (Weapon / Miscellaneous), whose source only
        -- turns up through the dress-up fallback; C_TransmogCollection.GetItemInfo is nil for it.
        noCollectionCategory = noCollectionCategory,
        isNotReady = isNotReady,
        matchesLootSpec = matchesLootSpec,
        isRecraftable = isRecraftable,
        forDebugUseOnly = debugEnabled and {
            matchedSources = matchedSources,
            isInfoReady = isInfoReady,
            appearanceInfo = appearanceInfo,
            sourceInfo = sourceInfo,
            appearanceSources = appearanceSources,
            currentSourceFound = currentSourceFound,
            otherSourceFound = otherSourceFound,
            otherSourceFoundForPlayer = otherSourceFoundForPlayer,
            sourceSpecs = sourceSpecs,
            lowestLevelFound = lowestLevelFound,
            uniqueUpgradeBlocked = uniqueUpgradeBlocked,
            uniqueUpgradeCandidate = uniqueUpgradeCandidate,
            betterItemEquipped = betterItemEquipped,
            equalItemLevelEquipped = equalItemLevelEquipped,
            pawnIdentifiedUpgrade = pawnIdentifiedUpgrade,
            upgradeItemLevelDelta = upgradeItemLevelDelta,
            isArtifactItem = isArtifactItem,
            uniqueCategoryKey = uniqueCategoryKey,
            playerCanUseSource = playerCanUseSource,
            canCollect = canCollect,
            playerCanCollectSource = playerCollectInfoReady and playerCanCollectSource or canCollect,
            accountCanCollect = accountCanCollect,
            matchesLootSpecRaw = matchesLootSpec,
            playerLootSpecID = playerLootSpecID,
            shouldShowUpgrade = shouldShowUpgrade,
            pawnAvailable = pawnAvailable,
            pawnRecommended = tostring(pawnRecommended),
            pawnPrefersEquipped = pawnPrefersEquipped,
            pawnComparison = pawnComparison,
            betterItemEquippedViaPvp = betterItemEquippedViaPvp,
            lowerArmorClassThanEquipped = lowerArmorClassThanEquipped,
            C_PlayerInfo_CanUseItem = C_PlayerInfo and C_PlayerInfo.CanUseItem and item:GetItemID() and
                select(2, pcall(function() return tostring(C_PlayerInfo.CanUseItem(item:GetItemID())) end)),
            C_Item_IsUsableItem = C_Item.IsUsableItem and item:GetItemID() and
                select(2, pcall(function() return tostring((C_Item.IsUsableItem(item:GetItemID()))) end)),
            candidateItemLevel = CandidateLevel(candidate),
            equippedComparison = BuildEquippedComparisonDebug(item),
            playerLevel = UnitLevel("player"),
            itemMinLevel = item:GetMinLevel(),
            blockedOffhandSlot = blockedOffhandSlot,
            isTabard = isTabard,
            isShirt = isShirt,
            validSourceInfoForPlayer = validSourceInfoForPlayer,
            sourceUseErrorType = sourceUseErrorType,
            sourceUseError = sourceUseError,
            sourceUseErrorBlocks = sourceUseErrorBlocks
        }
    }
end
