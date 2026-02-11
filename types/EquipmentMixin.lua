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

local function GetInventorySlotsForType(inventoryType)
    if not inventoryType then
        return nil
    end

    local dualSlots = dualSlotInventoryTypes[inventoryType]
    if dualSlots then
        return dualSlots
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
        itemLevel = select(1, GetDetailedItemLevelInfo(itemLink))
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
        local equipLoc = select(9, GetItemInfo(mainHand.link))
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
        return nil
    end

    local snapshot = GetEquippedGearSnapshot()
    local mainHand = snapshot[INVSLOT_MAINHAND]
    if not mainHand then
        return nil
    end

    return mainHand.level
end

local function IsOffhandSlotBlocked(inventoryTypeName)
    return ShouldIgnoreEmptySlot(INVSLOT_OFFHAND, inventoryTypeName)
end

local function GetSlotUpgradeDiff(slotID, inventoryTypeName, candidateLevel)
    local snapshot = GetEquippedGearSnapshot()
    local equipped = snapshot[slotID]
    if equipped then
        if equipped.level then
            return candidateLevel - equipped.level
        end

        -- NOTE: The following block references module-scope variables (appearanceID, playerClassID)
        -- that are always nil at this scope. Kept for historical reference but effectively dead code.
        if appearanceID and playerClassID and C_TransmogCollection.GetValidAppearanceSourcesForClass then
            local validSources = C_TransmogCollection.GetValidAppearanceSourcesForClass(appearanceID, playerClassID)
            if type(validSources) == "table" then
                for _, validSource in ipairs(validSources) do
                    if validSource.sourceID == sourceID then
                        validSourceInfoForPlayer = validSource
                        if not sourceUseErrorType and validSource.useErrorType then
                            sourceUseErrorType = validSource.useErrorType
                        end
                        if not sourceUseError and validSource.useError then
                            sourceUseError = validSource.useError
                        end

                        if validSource.playerCanCollect then
                            playerCanUseSource = true
                        elseif playerCanUseSource ~= true then
                            playerCanUseSource = validSource.isValidSourceForPlayer
                        end
                        break
                    end
                end
            end
        end
    else
        if ShouldIgnoreEmptySlot(slotID, inventoryTypeName) then
            local comparisonLevel = GetBlockedOffhandComparisonLevel()
            if comparisonLevel then
                return candidateLevel - comparisonLevel
            else
                return candidateLevel
            end
        else
            return candidateLevel
        end
    end
end

local function GetPlayerLootSpecID()
    local playerSpec = GetSpecialization();
    if not playerSpec then
        return nil
    end

    local playerSpecID = GetSpecializationInfo(playerSpec, nil, nil, nil, UnitSex("player"));
    local lootSpecID = GetLootSpecialization()
    if lootSpecID == 0 then
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

local function GetUniqueUpgradeInfo(item)
    if not item or not item.GetItemID then
        return false, false, nil
    end

    local itemLink = item:GetItemLink()
    local itemID = item:GetItemID()
    if not itemLink and not itemID then
        return false, false, nil
    end

    local uniqueCategoryKey, limitCategoryCount = DetermineUniqueness(itemLink or itemID, itemID)
    if not uniqueCategoryKey then
        return false, false, nil
    end

    limitCategoryCount = tonumber(limitCategoryCount) or 1
    local candidateLevel = GetCandidateItemLevel(item)
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
                if equipped.level >= candidateLevel then
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

-- Lazy-built snapshot of equipped gear data, shared by all upgrade helper functions.
-- Built once per invalidation cycle (equipment/transmog change), avoids repeated
-- ItemLocation creation and API calls across all bag items.
local equippedGearSnapshot = nil

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
            equippedGearSnapshot[slot] = {
                link = link,
                id = id,
                level = level,
                normalizedLevel = NormalizeItemLevel(level),
                categoryKey = categoryKey,
                limitCount = limitCount,
                inventoryType = C_Item.GetItemInventoryType(location),
            }
        end
    end

    return equippedGearSnapshot
end

function CaerdonEquipment:InvalidateCaches()
    wipe(sourceInfoCache)
    wipe(appearanceSourcesCache)
    equippedGearSnapshot = nil
end

local function HasBetterOrEqualEquippedItem(item)
    local inventoryType = item:GetInventoryTypeName()
    local inventorySlots = GetInventorySlotsForType(inventoryType)
    if not inventorySlots then
        return false
    end

    local candidateLevel = GetCandidateItemLevel(item)
    if not candidateLevel then
        return false
    end

    local snapshot = GetEquippedGearSnapshot()
    local normalizedCandidateLevel = NormalizeItemLevel(candidateLevel)
    local filledSlots = 0
    local strictlyBetterCount = 0
    for _, slotID in ipairs(inventorySlots) do
        local equipped = snapshot[slotID]
        if equipped then
            filledSlots = filledSlots + 1
            if equipped.normalizedLevel and equipped.normalizedLevel > normalizedCandidateLevel then
                strictlyBetterCount = strictlyBetterCount + 1
            end
        end
    end

    if filledSlots < #inventorySlots then
        return false
    end

    return filledSlots > 0 and strictlyBetterCount == filledSlots
end

local function HasEqualEquippedItemLevel(item)
    local itemLink = item:GetItemLink()
    local itemID = item:GetItemID()
    local inventoryType = item:GetInventoryTypeName()
    local inventorySlots = GetInventorySlotsForType(inventoryType)
    if not inventorySlots then
        return false
    end

    local candidateLevel = GetCandidateItemLevel(item)
    if not candidateLevel then
        return false
    end

    local snapshot = GetEquippedGearSnapshot()
    local uniqueCategoryKey, limitCategoryCount = DetermineUniqueness(itemLink or itemID, itemID)
    local uniqueLimitedToOne = uniqueCategoryKey and (tonumber(limitCategoryCount) or 1) == 1
    local normalizedCandidateLevel = NormalizeItemLevel(candidateLevel)
    local betterUniqueEquipped = false
    local hasEqualMatch = false
    for _, slotID in ipairs(inventorySlots) do
        local equipped = snapshot[slotID]
        if equipped and equipped.normalizedLevel then
            if equipped.normalizedLevel == normalizedCandidateLevel then
                hasEqualMatch = true
            end

            if uniqueLimitedToOne and not betterUniqueEquipped then
                if equipped.categoryKey and equipped.categoryKey == uniqueCategoryKey and
                    equipped.normalizedLevel > normalizedCandidateLevel then
                    betterUniqueEquipped = true
                end
            end
        end
    end

    if uniqueLimitedToOne and betterUniqueEquipped then
        return false
    end

    return hasEqualMatch
end

local function GetUpgradeItemLevelDelta(item)
    local inventoryType = item:GetInventoryTypeName()
    local inventorySlots = GetInventorySlotsForType(inventoryType)
    if not inventorySlots then
        return nil
    end

    local candidateLevel = GetCandidateItemLevel(item)
    if not candidateLevel then
        return nil
    end

    local snapshot = GetEquippedGearSnapshot()
    local itemLink = item:GetItemLink()
    local itemID = item:GetItemID()
    local uniqueCategoryKey, limitCategoryCount = DetermineUniqueness(itemLink or itemID, itemID)
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
            local diff = GetSlotUpgradeDiff(slotID, inventoryType, candidateLevel)
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

--[[static]]
function CaerdonEquipment:CreateFromCaerdonItem(caerdonItem)
    if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
        error("Usage: CaerdonEquipment:CreateFromCaerdonItem(caerdonItem)", 2)
    end

    local itemType = CreateFromMixins(CaerdonWardrobeItemDataMixin, CaerdonEquipmentMixin)
    itemType.item = caerdonItem
    return itemType
end

function CaerdonEquipmentMixin:LoadSources(callbackFunction)
    local hasItems = false
    local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(self.item:GetItemLink())
    if not sourceID then
        -- TODO: Not sure why this is the case?  EncounterJournal links aren't returning source info
        appearanceID, sourceID = C_TransmogCollection.GetItemInfo(self.item:GetItemID())
    end

    local waitingForItems = {}
    local continuableContainer = ContinuableContainer:Create();
    local cancelFunc = function() end;

    function ProcessTheItem(itemID)
        waitingForItems[itemID] = nil
        if not next(waitingForItems) then
            callbackFunction()
        end
    end

    function FailTheItem(itemID)
        waitingForItems[itemID] = nil
        print("Failed to load item " .. itemID)
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
            -- Using CaerdonItemEventListener instead of CaerdonItem here to avoid recursively diving
            if not waitingForItems[itemID] then
                waitingForItems[itemID] = true
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

function CaerdonEquipmentMixin:GetEquipmentSets()
    local equipmentSets

    -- Use equipment set for binding text if it's assigned to one
    if C_EquipmentSet.CanUseEquipmentSets() then
        local setIndex
        for setIndex = 1, C_EquipmentSet.GetNumEquipmentSets() do
            local equipmentSetIDs = C_EquipmentSet.GetEquipmentSetIDs()
            local equipmentSetID = equipmentSetIDs[setIndex]
            local name, icon, setID, isEquipped, numItems, numEquipped, numInventory, numMissing, numIgnored =
                C_EquipmentSet.GetEquipmentSetInfo(equipmentSetID)

            local equipLocations = C_EquipmentSet.GetItemLocations(equipmentSetID)
            if equipLocations then
                local locationIndex
                for locationIndex = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
                    local location = equipLocations[locationIndex]
                    if location ~= nil then
                        local locationData = EquipmentManager_GetLocationData(location)
                        local equipSlot = tonumber(locationData.slot)
                        local equipBag = tonumber(locationData.bag)

                        local isFound = false

                        if locationData.isBank and not locationData.bag then -- main bank container
                            local foundLink = GetInventoryItemLink("player", equipSlot)
                            if foundLink == self.item:GetItemLink() then
                                isFound = true
                            end
                        elseif locationData.isBank or locationData.isBags then -- any other bag
                            local itemLocation = ItemLocation:CreateFromBagAndSlot(equipBag, equipSlot)
                            if itemLocation:HasAnyLocation() and itemLocation:IsValid() then
                                local foundLink = C_Item.GetItemLink(itemLocation)
                                if foundLink == self.item:GetItemLink() then
                                    isFound = true
                                end
                            end
                        end

                        if isFound then
                            if not equipmentSets then
                                equipmentSets = {}
                            end

                            table.insert(equipmentSets, name)

                            break
                        end
                    end
                end
            end
        end
    end

    return equipmentSets
end

-- Wowhead Transmog Guide - https://www.wowhead.com/transmogrification-overview-frequently-asked-questions
function CaerdonEquipmentMixin:GetTransmogInfo()
    local item = self.item
    local itemLink = item:GetItemLink()
    local inventoryTypeName = item:GetInventoryTypeName()
    local isTabard = inventoryTypeName == "INVTYPE_TABARD"
    local isShirt = inventoryTypeName == "INVTYPE_BODY"
    local itemLocation = item:GetItemLocation()

    if item:GetCaerdonItemType() ~= CaerdonItemType.Equipment then
        return
    end

    local isBindOnPickup = item:GetBinding() == CaerdonItemBind.BindOnPickup
    local isCompletionistItem = false
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
    local uniqueUpgradeBlocked, uniqueUpgradeCandidate, uniqueCategoryKey = GetUniqueUpgradeInfo(item)
    local betterItemEquipped = HasBetterOrEqualEquippedItem(item)
    local equalItemLevelEquipped = HasEqualEquippedItemLevel(item)
    local upgradeItemLevelDelta = GetUpgradeItemLevelDelta(item)
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

    if item.extraData and item.extraData.appearanceID and item.extraData.appearanceSourceID then
        appearanceID = item.extraData.appearanceID
        sourceID = item.extraData.appearanceSourceID
    else
        appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemLink)
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
                    if sourceID and sourceID ~= NO_TRANSMOG_SOURCE_ID then
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

    if sourceID and sourceID ~= NO_TRANSMOG_SOURCE_ID then
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
            if playerCollectInfoReady then
                canCollect = playerCanCollectSource
            else
                canCollect = sourceInfo.playerCanCollect
            end
            currentSourceFound = sourceInfo.isCollected

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

                    -- Populate derived fields on cached info only once
                    if not info.itemSubTypeID then
                        local _, sourceType, sourceSubType, sourceEquipLoc, _, sourceTypeID, sourceSubTypeID = C_Item
                            .GetItemInfoInstant(info.itemID)
                        -- SubTypeID is returned from GetAppearanceSourceInfo, but it seems to be tied to the appearance, since it was wrong for an item that crossed over.
                        info.itemSubTypeID = sourceSubTypeID             -- stuff it in here (mostly for debug)
                    end
                    if not info.specs then
                        info.specs = C_Item.GetItemSpecInfo(info.itemID) -- also this
                    end

                    if info.cachedMinLevel == nil then
                        info.cachedMinLevel = (select(5, C_Item.GetItemInfo(info.itemID))) or false
                    end
                    local sourceMinLevel = info.cachedMinLevel or nil
                    if lowestLevelFound == nil or sourceMinLevel and sourceMinLevel < lowestLevelFound then
                        lowestLevelFound = sourceMinLevel
                    end

                    if info.isCollected and (item:GetItemSubTypeID() == info.itemSubTypeID or info.itemSubTypeID == Enum.ItemArmorSubclass.Cosmetic) then
                        -- Log any matched sources even if they're treated as not found due to other logic below (for debug)
                        table.insert(matchedSources, info)
                    end
                end

                if currentSourceFound then
                    -- Ignore the other source if this item is lower level than what we know
                    -- TODO: Find an item to add to tests
                    -- local includeLevelDifferences = CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem and CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentLevel

                    local itemMinLevel = item:GetMinLevel()
                    if lowestLevelFound ~= nil and itemMinLevel ~= nil and itemMinLevel < lowestLevelFound and includeLevelDifferences then
                        -- This logic accounts for the changes to transmog that allow lower-level players to wear transmog up to a certain level.
                        -- This changes "completionist" slightly in that you will no longer collect every single level difference of an appearance as it's no longer needed.
                        -- Supposedly just need to check if lower than level 10 now. TODO: Verify
                        -- if (lowestLevelFound > 9 and itemMinLevel <= 9) or (lowestLevelFound > 48 and itemMinLevel <= 48) or (lowestLevelFound > 60 and itemMinLevel <= 60) then
                        if lowestLevelFound > 9 and itemMinLevel <= 9 then
                            currentSourceFound = false
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
                    end
                end
            else
                -- No appearance ID means we can't enumerate alternates, but we still know the source is collectible.
                if canCollect and isValidSourceForPlayer then
                    needsItem = true
                elseif accountCanCollect then
                    otherNeedsItem = true
                end
            end
        end
    else
        -- No source ID for some reason - last resort effort but assume another toon needs it.
        local itemLocation = item:GetItemLocation()
        needItem = false
        otherNeedsItem = not C_TransmogCollection.PlayerHasTransmogByItemInfo(C_Item.GetItemInfo(item:GetItemLink()))
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

    if not isTransmog then
        playerCanUseSource = true
    end

    local upgradeMatchesSpec = matchesLootSpec ~= false

    local isUpgrade = nil

    -- TODO: Add check if upgrading item will result in an unlearned appearance.
    -- if item:GetItemID() == 199446 then
    -- local itemLocation = item:GetItemLocation()
    -- if itemLocation and C_ItemUpgrade.CanUpgradeItem(itemLocation) then
    --     C_ItemUpgrade.SetItemUpgradeFromLocation(item:GetItemLocation())
    --     local upgradeInfo = C_ItemUpgrade.GetItemUpgradeItemInfo()
    --     if upgradeInfo and upgradeInfo.currUpgrade < upgradeInfo.maxUpgrade then
    --         -- print("Item can be upgraded: " .. item:GetItemLink() .. " to " .. upgradeInfo.upgradedItemLink)
    --         DevTools_Dump(upgradeInfo)
    --     end
    -- end

    local shouldShowUpgrade = false
    local pawnIdentifiedUpgrade = false
    if PawnShouldItemLinkHaveUpgradeArrowUnbudgeted then
        local pawnRecommended = PawnShouldItemLinkHaveUpgradeArrowUnbudgeted(item:GetItemLink(), false)
        local pawnUpgrade = pawnRecommended
        if pawnUpgrade then
            if blockedOffhandSlot then
                pawnUpgrade = false
            end
            if playerLootSpecID == nil then
                playerLootSpecID = GetPlayerLootSpecID()
            end

            if (playerLootSpecID and playerLootSpecID > 0 and not matchesLootSpec) or uniqueUpgradeBlocked then
                pawnUpgrade = false
            end
        elseif uniqueUpgradeCandidate and not uniqueUpgradeBlocked then
            pawnUpgrade = true
        end

        if pawnUpgrade and pawnRecommended then
            pawnIdentifiedUpgrade = true
        end

        shouldShowUpgrade = pawnUpgrade
    elseif uniqueUpgradeCandidate and not uniqueUpgradeBlocked then
        shouldShowUpgrade = true
    end

    if not shouldShowUpgrade and upgradeItemLevelDelta and upgradeItemLevelDelta > 0 and not uniqueUpgradeBlocked and
        not isTabard then
        shouldShowUpgrade = true
    end

    if shouldShowUpgrade and not playerCanUseSource then
        shouldShowUpgrade = false
    end

    if shouldShowUpgrade and blockedOffhandSlot then
        shouldShowUpgrade = false
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
        upgradeItemLevelDelta = shouldShowUpgrade and upgradeItemLevelDelta or nil,
        pawnIdentifiedUpgrade = pawnIdentifiedUpgrade,
        upgradeMatchesSpec = upgradeMatchesSpec,
        isArtifactItem = isArtifactItem,
        uniqueCategoryKey = uniqueCategoryKey,
        canEquip = playerCanUseSource or canCollect,
        canEquipForPlayer = playerCanUseSource,
        needsItem = needsItem,
        hasMetRequirements = hasMetRequirements,
        otherNeedsItem = otherNeedsItem,
        playerCanCollectSource = playerCollectInfoReady and playerCanCollectSource or canCollect,
        isCompletionistItem = isCompletionistItem,
        matchesLootSpec = matchesLootSpec,
        isRecraftable = isRecraftable,
        forDebugUseOnly = CaerdonWardrobeConfig.Debug.Enabled and {
            matchedSources = matchedSources,
            isInfoReady = isInfoReady,
            appearanceInfo = appearanceInfo,
            sourceInfo = sourceInfo,
            appearanceSources = appearanceSources,
            itemTypeData = itemTypeData,
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
