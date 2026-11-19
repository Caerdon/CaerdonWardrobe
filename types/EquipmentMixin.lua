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
-- { name, label }, for JudgeOnHiddenOwnScale, and every other spec's shown scale is ignored
-- even though that leaves none. Without it a piece was judged by item level alone, or by the
-- other specs' scales as if they were the toon's own.
local function GetPawnOffTreeScales()
    if not (PawnCommon and PawnCommon.Scales and PawnIsScaleVisible) then
        return nil
    end

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
    if not treeIndex and not specIndex then
        return nil
    end

    local ok, offTree, detail, hiddenOwn = pcall(function()
        local _, classFile, classID = UnitClass("player")
        local specIDs = treeIndex and PawnSpecIDsForTalentTree(classFile, treeIndex, treeCount) or
            { [specIndex] = true }
        local ignored, ignoredNames, keptNames = {}, {}, {}
        -- The played spec's scale that Pawn ships (a provider's), where Pawn does not show it.
        local hidden
        for scaleName, scale in pairs(PawnCommon.Scales) do
            local label = scale.LocalizedName or scaleName
            if PawnIsScaleVisible(scaleName) then
                if scale.ClassID == classID and type(scale.SpecID) == "number" and not specIDs[scale.SpecID] then
                    ignored[scaleName] = true
                    ignoredNames[#ignoredNames + 1] = label
                else
                    keptNames[#keptNames + 1] = label
                end
            elseif specIndex and scale.ClassID == classID and scale.SpecID == specIndex and scale.Provider ~= nil and
                (not hidden or scaleName < hidden.name) then
                hidden = { name = scaleName, label = label }
            end
        end
        table.sort(ignoredNames)
        table.sort(keptNames)
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
local function IsPawnUpgradeOffTreeOnly(item, offTreeScales, setSpecs)
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
        local _, classFile = UnitClass("player")
        for _, upgrade in ipairs(upgradeInfo) do
            local name = upgrade.LocalizedScaleName or tostring(upgrade.ScaleName)
            names[#names + 1] = name
            local offTree = offTreeScales[upgrade.ScaleName]
            if not offTree then
                offTreeOnly = false
            end
            local scale = PawnCommon.Scales and PawnCommon.Scales[upgrade.ScaleName]
            local specIndex = scale and scale.SpecID
            if type(specIndex) ~= "number" or (IsOtherSpecWanted(classFile, specIndex) and
                not (offTree and setSpecs and setSpecs[specIndex])) then
                standingNames[#standingNames + 1] = name
            end
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

-- What is worn, as a loadout, on a client with talent trees (WoW Forever), which has no
-- specialization to go by. The tree with the most points is taken for what the toon plays
-- (author decision, for a start: a toon that plays two trees is not told, and a gear set
-- cannot be tied to a tree there; tying a gear set to a Pawn scale is to settle both, on both
-- clients). Its scale is the one Pawn ships for the class and that tree
-- (PawnSpecIDsForTalentTree). A feral druid's tree has two, damage and tank: of several the
-- one Pawn shows, then the lower number.
-- The worn gear is that tree's whatever gear set is on, and there is no other loadout:
-- another tree's scale that Pawn shows colours the arrow as it did (GetPawnOffTreeScales).
-- Nothing where no tree leads (no points spent, or two trees tie) or Pawn has no such scale.
local function ReadTalentTreeLoadout(loadouts, classFile, classID)
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
    loadouts.activeSet, loadouts.activeWhy = ReadActiveSet(nil)
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
        return loadouts
    end
    local current = CaerdonAPI:GetPlayerSpecializationIndex()
    if not current or current < 1 or current > 4 then
        return loadouts
    end

    local setForSpec = C_EquipmentSet and C_EquipmentSet.GetEquipmentSetForSpec
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
                loadouts.bySpec[specIndex] = loadout
                loadouts[#loadouts + 1] = loadout
            end
        end
    end
    table.sort(loadouts, function(a, b) return a.index < b.index end)
    return loadouts
end

-- The other specs with a gear set whose scale Pawn shows (offTreeScales, the shown scales of
-- the toon's other specs): spec index -> true, or nil. For those the set decides and Pawn's
-- verdict, which is against the worn gear, does not (author decision): the arrow for a spec is
-- "better than what that spec has", and with a set assigned the worn gear is not that. Showing
-- the scale is still the player's sign that the spec is wanted, so the set is asked for it
-- whatever Icon.ShowOtherSpecUpgrades says, as Pawn's verdict was.
local function GetShownSetSpecs(offTreeScales)
    local bySpec = GetLoadouts().bySpec
    local found
    for scaleName in pairs(offTreeScales) do
        local scale = PawnCommon.Scales[scaleName]
        local loadout = scale and bySpec[scale.SpecID]
        if loadout and loadout.setID and not loadout.own then
            found = found or {}
            found[loadout.index] = true
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
            return nil
        end
        values[link] = value
    end
    return value or nil
end

-- The piece against the worn gear on the played spec's own scale, where Pawn does not show that
-- scale (GetPawnOffTreeScales' third return value). Compared the way Pawn compares on a scale
-- it shows: unenchanted values, the weaker of two slots, Pawn's threshold.
--   "upgrade": worth more than what is worn.
--   "equipped": scored, and not worth more. A higher item level is then no upgrade either.
--   nil: no verdict (a trinket, an empty slot, a piece Pawn has no value for), which leaves the
--        item level to decide, as it does where a shown scale has no verdict.
-- Second return value: the numbers, for the Debug Frame export.
local function JudgeOnHiddenOwnScale(item, scale)
    if not (PawnGetItemData and PawnGetSingleValueFromItem) then
        return nil
    end
    local inventoryTypeName = item:GetInventoryTypeName()
    if inventoryTypeName == "INVTYPE_TRINKET" then
        return nil
    end
    local inventorySlots = GetInventorySlotsForType(inventoryTypeName)
    if not inventorySlots then
        return nil
    end

    local ok, verdict, detail = pcall(function()
        local link = item:GetItemLink()
        local value = link and OtherSpecValue(scale.name, link)
        if not value then
            return nil
        end
        local lowest
        for _, slotID in ipairs(inventorySlots) do
            local worn = GetInventoryItemLink("player", slotID)
            if worn then
                local wornValue = OtherSpecValue(scale.name, worn)
                if not wornValue then
                    return nil
                end
                if not lowest or wornValue < lowest then
                    lowest = wornValue
                end
            elseif not ShouldIgnoreEmptySlot(slotID, inventoryTypeName) then
                return nil
            end
        end
        if not lowest then
            return nil
        end
        local numbers = format("%s (not shown in Pawn): %.2f vs %.2f equipped", scale.label, value, lowest)
        if value > lowest * PAWN_UPGRADE_THRESHOLD then
            return "upgrade", numbers
        end
        return "equipped", numbers
    end)
    if not ok then
        return nil
    end
    return verdict, detail
end

-- What the loadout has in the slot and Pawn's value of it on its scale, or nil: { link, value,
-- fromSet (the set's piece, not the worn gear standing in), worn (it is being worn) }. Found
-- once per refresh. The set is asked where its pieces are as the slot is first needed, not when
-- the loadouts were listed: a piece moves in the bags without a refresh. For a slot the set
-- leaves alone the worn piece stands in.
local function LoadoutBaseline(loadout, slotID)
    local entry = loadout.baseline[slotID]
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
            local value = OtherSpecValue(loadout.scale, link)
            if value then
                entry = { link = link, value = value, fromSet = fromSet or false, worn = worn or false }
            end
        end
        loadout.baseline[slotID] = entry
    end
    return entry or nil
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

-- A one-hander (or what goes in the off hand) against a two-hander and the other way round,
-- and what the scale is told not to show (its DoNotShow1HUpgrades / DoNotShow2HUpgrades). Pawn
-- goes by the worn weapon; here it is the loadout's. Without this a two-hander was compared
-- with a main hand alone. A pair of one-handers against a two-hander is not weighed by Pawn or
-- here: a piece is judged alone.
local ONE_HANDED_TYPES = {
    INVTYPE_WEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_SHIELD = true,
    INVTYPE_HOLDABLE = true,
}
local function IsWeaponKindRefused(loadout, inventoryTypeName)
    local oneHanded = ONE_HANDED_TYPES[inventoryTypeName] == true
    local twoHanded = inventoryTypeName == "INVTYPE_2HWEAPON"
    if not oneHanded and not twoHanded then
        return false
    end
    local scale = PawnCommon.Scales[loadout.scale]
    if scale and ((oneHanded and scale.DoNotShow1HUpgrades) or (twoHanded and scale.DoNotShow2HUpgrades)) then
        return true
    end
    local wielded = LoadoutBaseline(loadout, INVSLOT_MAINHAND) or LoadoutBaseline(loadout, INVSLOT_OFFHAND)
    if not wielded then
        return false
    end
    local _, _, _, wieldedType = C_Item.GetItemInfoInstant(wielded.link)
    if wieldedType == "INVTYPE_2HWEAPON" then
        return oneHanded
    end
    return twoHanded
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
-- what is worn, with worn = true), colour, own, value, baseline } per loadout). itemSpecs: the
-- specs the
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
    local fillsEmptySlots = not ONE_HANDED_TYPES[inventoryTypeName] and inventoryTypeName ~= "INVTYPE_2HWEAPON"
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
                local value = OtherSpecValue(loadout.scale, link)
                local lowest
                local fromSet, fromWorn = false, false
                -- One of the set's pieces for these slots is not the one worn.
                local setAside = false
                -- Nothing is worn in a slot the piece would take: it fills the slot, and there
                -- is no piece to say by how much. For what is worn alone (a gear set that has
                -- nothing for a slot is not asking for a piece), and not for a weapon's hands,
                -- where an empty off hand is not every class's to fill. Seen (WoW Forever
                -- 1.60.1.70959): shoulders for a rogue with none on had Pawn's note and no
                -- line of the addon's.
                local emptySlot = false
                local judged = value ~= nil and value > 0 and not IsWeaponKindRefused(loadout, inventoryTypeName)
                if judged then
                    for _, slotID in ipairs(inventorySlots) do
                        local baseline = LoadoutBaseline(loadout, slotID)
                        if not baseline and loadout.isWorn and fillsEmptySlots and
                            not GetInventoryItemLink("player", slotID) then
                            emptySlot = true
                        elseif not baseline or baseline.link == link then
                            judged = false
                            break
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
                end
                -- The played spec's set with its own pieces worn, or with the worn gear
                -- standing in for every slot: compared already, as the worn gear.
                if judged and loadout.own and not setAside then
                    judged = false
                end
                if judged and (emptySlot or (lowest and value > lowest * PAWN_UPGRADE_THRESHOLD)) then
                    found = found or {}
                    details = details or {}
                    entries = entries or {}
                    found[#found + 1] = loadout.label
                    local entry = { scale = loadout.scale, label = loadout.label, colour = loadout.colour,
                        own = loadout.own, value = value, baseline = not emptySlot and lowest or nil,
                        emptySlot = emptySlot or nil }
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
                    if emptySlot then
                        details[#details + 1] = format("%s: %.2f into a slot with nothing worn in it", loadout.label, value)
                    else
                        details[#details + 1] = format("%s%s: %.2f vs %.2f %s", loadout.label,
                            loadout.own and " (the spec being played, its set's piece not worn)" or "",
                            value, lowest, against)
                    end
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
        return found
    end)
    return ok and names or nil
end

-- For the item tooltip: what the piece would be an upgrade for (GetLoadoutUpgrades' list), or
-- nil. Asked of the piece by itself, whatever its icon says: a piece with the yellow arrow can
-- be an upgrade for a gear set as well. Never for a tabard or a shirt, as the arrow.
--   What is worn (worn = true), first: on the played spec's scale against the worn pieces,
--   named for the active set where there is one. Only where the piece has the yellow arrow for
--   it: Pawn shows that scale and calls the piece an upgrade on it, or Pawn shows no scale of
--   the toon's own and the addon judges on the hidden one (JudgeOnHiddenOwnScale). Elsewhere
--   the line would stand beside an icon that says something else.
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

    local named, percents, inTooltip = ReadPawnUpgrades(link)
    local _, _, hiddenOwn = GetPawnOffTreeScales()
    local kept, wornStands = {}, false
    local atLevel = LevelToCome(item)
    for _, entry in ipairs(list) do
        local keep = true
        if entry.worn then
            if PawnIsScaleVisible and PawnIsScaleVisible(entry.scale) then
                keep = named ~= nil and named[entry.scale] == true
            else
                keep = hiddenOwn ~= nil and hiddenOwn.name == entry.scale
            end
            wornStands = keep
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
        parts[#parts + 1] = format("%s: %s", loadout.label, against)
    end
    return table.concat(parts, "; ")
end

-- For the Debug Frame export: which visible Pawn scales are being ignored for this toon, or nil.
--[[static]]
function CaerdonEquipment:GetPawnScaleFilterDescription()
    local _, detail = GetPawnOffTreeScales()
    return detail
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
            return nil, "a one-hander against a two-hander or the other way round, or a kind the scale is told not to show"
        end
        local baseline = LoadoutBaseline(loadout, wornSlot)
        local value = baseline and OtherSpecValue(loadout.scale, link)
        if not value then
            return nil, "Pawn has no value on the scale for one of the two pieces"
        end
        -- Only where the loadout has this worn piece in the slot: a set that is on with another
        -- piece of its own for the slot is measured against that one, in the item's own tooltip.
        if GetInventoryItemLink("player", wornSlot) ~= baseline.link then
            return nil, "the set that is on has another piece for the slot than the one worn"
        end
        local entry = { colour = loadout.colour, worn = loadout.isWorn or nil,
            upgrade = value > baseline.value * PAWN_UPGRADE_THRESHOLD,
            percent = baseline.value > 0 and math.floor((value / baseline.value - 1) * 100 + 0.5) or nil,
            atLevel = LevelToCome(item) }
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
-- leather wearer, a kind of weapon the scale has no value for or is told not to show).
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
        if IsWeaponKindRefused(loadout, inventoryTypeName) then
            return false
        end
        local value = OtherSpecValue(loadout.scale, link)
        return value ~= nil and value > 0
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
    -- The verdict on the played spec's own scale where Pawn does not show it
    -- (JudgeOnHiddenOwnScale): "upgrade", "equipped" or nil, and its numbers.
    local hiddenOwnVerdict, hiddenOwnDetail = nil, nil
    -- The other specs whose scale Pawn shows and whose gear set decides in Pawn's place
    -- (GetShownSetSpecs), whether Pawn's verdict stands for any scale it named, and for which.
    local pawnSetSpecs, pawnStands, pawnStandingScales = nil, nil, nil
    -- The link is not the piece's own (IsKnownByAnotherLink): Pawn would be judging another
    -- piece, so it is not asked, by its arrow, its scores or the loadouts, and item level decides.
    local knownByAnotherLink, anotherLinkBy = IsKnownByAnotherLink(item)
    if PawnShouldItemLinkHaveUpgradeArrowUnbudgeted and not knownByAnotherLink then
        NotePawnItemLevelOption()
        pawnRecommended = PawnShouldItemLinkHaveUpgradeArrowUnbudgeted(item:GetItemLink(), false)
        local _, hiddenOwnScale
        pawnOffTreeScales, _, hiddenOwnScale = GetPawnOffTreeScales()
        if hiddenOwnScale then
            hiddenOwnVerdict, hiddenOwnDetail = JudgeOnHiddenOwnScale(item, hiddenOwnScale)
        end
        -- Another spec with a gear set is measured against that set, further down, and not by
        -- Pawn's verdict for its shown scale, which is against the worn gear.
        pawnSetSpecs = pawnOffTreeScales and GetShownSetSpecs(pawnOffTreeScales) or nil
        -- Pawn's verdict as far as it counts: not where it is only for specs the player
        -- switched off or specs whose gear set decides.
        pawnStands = pawnRecommended
        if pawnRecommended and pawnOffTreeScales then
            local noneStands
            pawnOffTreeOnly, pawnUpgradeScales, noneStands, pawnStandingScales =
                IsPawnUpgradeOffTreeOnly(item, pawnOffTreeScales, pawnSetSpecs)
            if noneStands then
                pawnStands = false
            end
        end
        local pawnUpgrade = pawnStands
        -- An upgrade on the played spec's own scale, which Pawn does not show: the toon's own,
        -- whatever the shown scales of its other specs say about the piece.
        if hiddenOwnVerdict == "upgrade" then
            pawnUpgrade = true
            pawnOffTreeOnly = false
            pawnUpgradeScales = hiddenOwnScale.label
        end
        if pawnUpgrade then
            if blockedOffhandSlot then
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

        if pawnUpgrade and (pawnStands or hiddenOwnVerdict == "upgrade") then
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
    local pawnComparison = hiddenOwnVerdict == "upgrade" and hiddenOwnDetail or nil
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
        elseif hiddenOwnVerdict == "equipped" then
            -- The played spec's own scale, hidden in Pawn, rates the worn piece at least as high.
            pawnPrefersEquipped, pawnComparison = true, hiddenOwnDetail
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

    if shouldShowUpgrade and blockedOffhandSlot then
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
