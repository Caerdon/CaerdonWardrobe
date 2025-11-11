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
    INVTYPE_RANGEDRIGHT = 17,
    INVTYPE_QUIVER = 0,
    INVTYPE_RELIC = 0
}

local dualSlotInventoryTypes = {
    INVTYPE_FINGER = { INVSLOT_FINGER1, INVSLOT_FINGER2 },
    INVTYPE_TRINKET = { INVSLOT_TRINKET1, INVSLOT_TRINKET2 }
}

local singleSlotCache = {}

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
    local candidateLevel = GetComparableItemLevel(itemLink, item:GetItemLocation())
    local inventorySlots = GetInventorySlotsForType(item:GetInventoryTypeName())
    local hasEmptyEquipSlot = false
    if inventorySlots then
        for _, equipSlotID in ipairs(inventorySlots) do
            local equipLocation = ItemLocation:CreateFromEquipmentSlot(equipSlotID)
            if not (equipLocation and equipLocation:IsValid() and C_Item.DoesItemExist(equipLocation)) then
                hasEmptyEquipSlot = true
                break
            end
        end
    end

    local equippedMatches = 0
    local equippedBetterOrEqual = 0
    local betterThanEquipped = false

    local function EvaluateMatch(equippedLink, location, equippedCategoryKey)
        if equippedCategoryKey and equippedCategoryKey == uniqueCategoryKey then
            equippedMatches = equippedMatches + 1

            local equippedLevel = GetComparableItemLevel(equippedLink, location)
            if equippedLevel and candidateLevel then
                if equippedLevel >= candidateLevel then
                    equippedBetterOrEqual = equippedBetterOrEqual + 1
                else
                    betterThanEquipped = true
                end
            elseif equippedLevel and not candidateLevel then
                equippedBetterOrEqual = equippedBetterOrEqual + 1
            end
            return true
        end
        return false
    end

    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local location = ItemLocation:CreateFromEquipmentSlot(slot)
        if location and location:IsValid() and C_Item.DoesItemExist(location) then
            local equippedLink = C_Item.GetItemLink(location)
            local equippedID = C_Item.GetItemID(location)

            local equippedCategoryKey = select(1, DetermineUniqueness(equippedLink or equippedID, equippedID))
            EvaluateMatch(equippedLink, location, equippedCategoryKey)
        end
    end

    local minMatches = math.min(limitCategoryCount, equippedMatches)
    local uniqueUpgradeBlocked = equippedMatches >= limitCategoryCount and equippedBetterOrEqual >= minMatches
    local uniqueUpgradeCandidate = betterThanEquipped or (hasEmptyEquipSlot and equippedMatches < limitCategoryCount)

    return uniqueUpgradeBlocked, uniqueUpgradeCandidate, uniqueCategoryKey
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
                        -- TODO: Keep an eye out for a new way to do this in the API
                        local isPlayer, isBank, isBags, isVoidStorage, equipSlot, equipBag, equipTab, equipVoidSlot =
                            EquipmentManager_UnpackLocation(location)
                        equipSlot = tonumber(equipSlot)
                        equipBag = tonumber(equipBag)

                        local isFound = false

                        if isBank and not equipBag then -- main bank container
                            local foundLink = GetInventoryItemLink("player", equipSlot)
                            if foundLink == self.item:GetItemLink() then
                                isFound = true
                            end
                        elseif isBank or isBags then -- any other bag
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
    local playerLootSpecID
    local uniqueUpgradeBlocked, uniqueUpgradeCandidate, uniqueCategoryKey = GetUniqueUpgradeInfo(item)

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
                        appearanceID = select(2, C_TransmogCollection.GetAppearanceSourceInfo(sourceID))
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

        -- if not isInfoReady then
        --     print('Info not ready - source ID ' .. tostring(sourceID) .. ' for ' .. itemLink)
        -- end

        -- Only returns for sources that can be transmogged by current toon right now
        appearanceInfo = C_TransmogCollection.GetAppearanceInfoBySource(sourceID)

        local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
        -- TODO: If no appearance ID by now, might be able to use VisualID returned from here?  Not sure if needed...
        -- If the source is already collected, we don't need to check anything else for the source / appearance
        if sourceInfo and not sourceInfo.isCollected then
            canCollect = sourceInfo.playerCanCollect
            currentSourceFound = sourceInfo.isCollected

            local isValidSourceForPlayer = sourceInfo.isValidSourceForPlayer
            if appearanceID then
                local sourceIndex, source
                -- GetAllAppearanceSources includes hidden and otherwise unusable sources, so it's the most thorough
                local appearanceSourceIDs = C_TransmogCollection.GetAllAppearanceSources(appearanceID)
                for sourceIndex, source in pairs(appearanceSourceIDs) do
                    local isInfoReadySearch, canCollectSearch = C_TransmogCollection.PlayerCanCollectSource(source)
                    local info = C_TransmogCollection.GetSourceInfo(source)

                    -- TODO: This is how Blizz confirms data is loaded - need to look at CaerdonItem load handling and account for it
                    -- if info and info.quality then
                    --     -- Item is ready
                    -- else
                    --     print('Search SourceInfo quality not available: ' .. itemLink)
                    -- end

                    if info then
                        if not appearanceSources then
                            appearanceSources = {}
                        end

                        table.insert(appearanceSources, info)

                        -- Check if we've already collected it and if it works for the current toon
                        if info.sourceID ~= sourceID then -- already checked the current item's info
                            if info.isCollected then
                                if info.isValidSourceForPlayer then
                                    otherSourceFoundForPlayer = true
                                else
                                    otherSourceFound = true
                                end
                            end
                        end
                    end

                    local _, sourceType, sourceSubType, sourceEquipLoc, _, sourceTypeID, sourceSubTypeID = C_Item
                        .GetItemInfoInstant(info.itemID)
                    -- SubTypeID is returned from GetAppearanceSourceInfo, but it seems to be tied to the appearance, since it was wrong for an item that crossed over.
                    info.itemSubTypeID = sourceSubTypeID             -- stuff it in here (mostly for debug)
                    info.specs = C_Item.GetItemSpecInfo(info.itemID) -- also this

                    local sourceMinLevel = (select(5, C_Item.GetItemInfo(info.itemID)))
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
            end
        end
    else
        -- No source ID for some reason - last resort effort but assume another toon needs it.
        local itemLocation = item:GetItemLocation()
        needItem = false
        otherNeedsItem = not C_TransmogCollection.PlayerHasTransmogByItemInfo(C_Item.GetItemInfo(item:GetItemLink()))
        canCollect = true
    end

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
    if PawnShouldItemLinkHaveUpgradeArrowUnbudgeted then
        local pawnUpgrade = PawnShouldItemLinkHaveUpgradeArrowUnbudgeted(item:GetItemLink(), false)
        if pawnUpgrade then
            if playerLootSpecID == nil then
                playerLootSpecID = GetPlayerLootSpecID()
            end

            if (playerLootSpecID and playerLootSpecID > 0 and not matchesLootSpec) or uniqueUpgradeBlocked then
                pawnUpgrade = false
            end
        elseif uniqueUpgradeCandidate and not uniqueUpgradeBlocked then
            pawnUpgrade = true
        end

        shouldShowUpgrade = pawnUpgrade
    elseif uniqueUpgradeCandidate and not uniqueUpgradeBlocked then
        shouldShowUpgrade = true
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
        uniqueCategoryKey = uniqueCategoryKey,
        canEquip = canCollect,
        needsItem = needsItem,
        hasMetRequirements = hasMetRequirements,
        otherNeedsItem = otherNeedsItem,
        isCompletionistItem = isCompletionistItem,
        matchesLootSpec = matchesLootSpec,
        forDebugUseOnly = CaerdonWardrobeConfig.Debug.Enabled and {
            matchedSources = matchedSources,
            isInfoReady = isInfoReady,
            appearanceInfo = appearanceInfo,
            sourceInfo = sourceInfo,
            appearanceSources = appearanceSources,
            itemTypeData = itemTypeData,
            currentSourceFound = currentSourceFound,
            otherSourceFound = otherSourceFound,
            sourceSpecs = sourceSpecs,
            lowestLevelFound = lowestLevelFound,
            uniqueUpgradeBlocked = uniqueUpgradeBlocked,
            uniqueUpgradeCandidate = uniqueUpgradeCandidate,
            uniqueCategoryKey = uniqueCategoryKey
        }
    }
end
