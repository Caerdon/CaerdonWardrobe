CaerdonConsumable = {}
CaerdonConsumableMixin = {}

local ADDON_NAME, NS = ...
local L = NS.L

local bit_band = bit.band
local bit_lshift = bit.lshift

local ITEM_CLASS_ARMOR = Enum and Enum.ItemClass and Enum.ItemClass.Armor or 4

local requestItemDataByID
do
    if C_Item and C_Item.RequestLoadItemDataByID then
        requestItemDataByID = C_Item.RequestLoadItemDataByID
    else
        local noop = function() end
        requestItemDataByID = function(itemID)
            if not itemID or not Item or not Item.CreateFromItemID then
                return
            end

            local item = Item:CreateFromItemID(itemID)
            if item and item.ContinueOnItemLoad then
                item:ContinueOnItemLoad(noop)
            end
        end
    end
end

-- Shared transmog source API caches (created by EquipmentMixin, referenced lazily here)
local sourceInfoCache
local appearanceSourcesCache

local function GetCachedSourceInfo(sourceID)
    if not sourceInfoCache then
        sourceInfoCache = CaerdonEquipment and CaerdonEquipment.sourceInfoCache
    end
    if sourceInfoCache then
        local info = sourceInfoCache[sourceID]
        if not info then
            info = C_TransmogCollection.GetSourceInfo(sourceID)
            if info then sourceInfoCache[sourceID] = info end
        end
        return info
    end
    return C_TransmogCollection.GetSourceInfo(sourceID)
end

local function GetCachedAppearanceSources(appearanceID)
    if not appearanceSourcesCache then
        appearanceSourcesCache = CaerdonEquipment and CaerdonEquipment.appearanceSourcesCache
    end
    if appearanceSourcesCache then
        local sources = appearanceSourcesCache[appearanceID]
        if not sources then
            sources = C_TransmogCollection.GetAllAppearanceSources(appearanceID)
            if sources then appearanceSourcesCache[appearanceID] = sources end
        end
        return sources
    end
    return C_TransmogCollection.GetAllAppearanceSources(appearanceID)
end

local function GetDebugItemLink(itemID)
    if not itemID then
        return nil
    end

    local _, itemLink = C_Item.GetItemInfo(itemID)
    if itemLink then
        return itemLink
    end

    return "item:" .. tostring(itemID)
end

--[[static]]
function CaerdonConsumable:CreateFromCaerdonItem(caerdonItem)
    if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
        error("Usage: CaerdonConsumable:CreateFromCaerdonItem(caerdonItem)", 2)
    end

    local itemType = CreateFromMixins(CaerdonWardrobeItemDataMixin, CaerdonConsumableMixin)
    itemType.item = caerdonItem

    return itemType
end

-- Helper function to check if player can wear/transmog a specific armor subtype
-- Returns true if the player can actually USE this armor type for transmog (not just collect for cosmetic purposes)
local function CanPlayerWearArmorSubType(itemSubTypeID)
    -- itemSubTypeID values for armor:
    -- 0 = Miscellaneous (shirts, tabards, etc.) - everyone can wear
    -- 1 = Cloth - cloth classes only
    -- 2 = Leather - leather wearers only
    -- 3 = Mail - mail wearers only
    -- 4 = Plate - plate wearers only
    -- 5 = Cosmetic (some special cosmetic items) - everyone can wear
    -- 6 = Shields - classes with shield proficiency
    -- nil/other = Cloaks and other items - everyone can wear

    local _, playerClass = UnitClass("player")

    if not itemSubTypeID then
        return true -- If we can't determine type, allow it (cosmetic items, cloaks, etc.)
    end

    -- Everyone can wear: Miscellaneous (0), Cosmetic (5)
    if itemSubTypeID == 0 or itemSubTypeID == 5 then
        return true
    end

    if itemSubTypeID == 1 then
        -- Cloth ensembles should only count as wearable for cloth classes
        return playerClass == "PRIEST" or playerClass == "MAGE" or playerClass == "WARLOCK"
    end

    -- Leather wearers: Druid, Monk, Rogue, Demon Hunter
    if itemSubTypeID == 2 then
        return playerClass == "DRUID" or playerClass == "MONK" or playerClass == "ROGUE" or playerClass == "DEMONHUNTER"
    end

    -- Mail wearers: Hunter, Shaman, Evoker
    if itemSubTypeID == 3 then
        return playerClass == "HUNTER" or playerClass == "SHAMAN" or playerClass == "EVOKER"
    end

    -- Plate wearers: Warrior, Paladin, Death Knight
    if itemSubTypeID == 4 then
        return playerClass == "WARRIOR" or playerClass == "PALADIN" or playerClass == "DEATHKNIGHT"
    end

    -- For shields and other types, default to true (let the game's API decide)
    return true
end

function CaerdonConsumableMixin:GetConsumableInfo()
    local needsItem = false
    local otherNeedsItem = false
    local ownPlusItem = false      -- Completionist - has uncollected items for own class but not the primary purpose
    local lowSkillItem = false     -- Needs the item but requirements aren't met for this character
    local lowSkillPlusItem = false -- Completionist variant when requirements unmet for other characters
    local otherNoLootItem = false  -- Nothing here is learnable by the current character
    local validForCharacter = true
    local canEquipEnsemble = false -- Track if player can equip uncollected sources from ensemble
    local playerLevel = UnitLevel("player")
    local _, _, playerClassID = UnitClass("player")
    local playerClassMask = playerClassID and bit_lshift(1, playerClassID - 1) or nil

    -- Debug tracking
    local debugInfo = {
        itemID = self.item:GetItemID(),
        transmogSetID = nil,
        setInfo = nil,
        primaryAppearances = nil,
        appearances = {},
        hasUncollectedAppearances = false,
        hasUncollectedForPlayer = false,
        fallbackUsed = false
    }

    local itemLink = self.item:GetItemLink()
    local transmogSetID = C_Item.GetItemLearnTransmogSet(itemLink)
    debugInfo.transmogSetID = transmogSetID

    if transmogSetID then
        local transmogSetInfo = C_TransmogSets.GetSetInfo(transmogSetID)
        debugInfo.setInfo = transmogSetInfo

        if transmogSetInfo then
            local classMask = transmogSetInfo.classMask
            local isPlayerClassInSet = true

            if classMask and classMask ~= 0 and playerClassMask then
                isPlayerClassInSet = bit_band(classMask, playerClassMask) ~= 0
            end

            validForCharacter = transmogSetInfo.validForCharacter and isPlayerClassInSet
            debugInfo.classMask = classMask
            debugInfo.playerClassID = playerClassID
            debugInfo.isPlayerClassInSet = isPlayerClassInSet

            -- Check individual appearances in the set to determine if there are any uncollected
            -- Don't rely on transmogSetInfo.collected alone, as it only returns true when ALL appearances are collected
            local primaryAppearances = C_TransmogSets.GetSetPrimaryAppearances(transmogSetID)
            debugInfo.primaryAppearances = primaryAppearances

            if primaryAppearances then
                local hasUncollectedAppearances = false
                local hasUncollectedForPlayer = false
                local collectedAppearanceIDs = {}

                for _, appearanceInfo in ipairs(primaryAppearances) do
                    local appearanceDebug = {
                        appearanceID = appearanceInfo.appearanceID,
                        collected = appearanceInfo.collected,
                        sources = {}
                    }

                    -- Track collected appearances by their visualID (not appearanceID)
                    -- Need to get sources to find the visualID since appearanceID != visualID
                    if appearanceInfo.collected then
                        local sources = C_TransmogSets.GetSourcesForSlot(transmogSetID, appearanceInfo.appearanceID)
                        if sources and #sources > 0 then
                            -- Get the first source and extract its visualID
                            local sourceInfo = GetCachedSourceInfo(sources[1])
                            if sourceInfo and sourceInfo.visualID then
                                collectedAppearanceIDs[sourceInfo.visualID] = true
                            end
                        end
                    end

                    if not appearanceInfo.collected then
                        hasUncollectedAppearances = true

                        -- Get all sources for this appearance to check player eligibility
                        -- Note: GetAllAppearanceSources only returns sources valid for current class
                        -- So if validForCharacter is false, this will return empty
                        local appearanceSources = GetCachedAppearanceSources(appearanceInfo
                            .appearanceID)
                        appearanceDebug.sourceCount = appearanceSources and #appearanceSources or 0

                        if appearanceSources then
                            for _, sourceID in ipairs(appearanceSources) do
                                local sourceInfo = GetCachedSourceInfo(sourceID)
                                if sourceInfo then
                                    table.insert(appearanceDebug.sources, {
                                        sourceID = sourceID,
                                        isValidSourceForPlayer = sourceInfo.isValidSourceForPlayer,
                                        isCollected = sourceInfo.isCollected,
                                        playerCanCollect = sourceInfo.playerCanCollect
                                    })

                                    if sourceInfo.isValidSourceForPlayer then
                                        hasUncollectedForPlayer = true
                                        break
                                    end
                                end
                            end
                        end
                    end

                    table.insert(debugInfo.appearances, appearanceDebug)
                end

                debugInfo.hasUncollectedAppearances = hasUncollectedAppearances
                debugInfo.hasUncollectedForPlayer = hasUncollectedForPlayer

                -- Determine if current character or other characters need it
                -- For sets valid for this character, check if we found uncollected sources for player
                -- For sets NOT valid for this character, just check if there are uncollected appearances
                if validForCharacter then
                    -- ALWAYS check all sources for ensembles, even if primary appearances show as collected
                    -- Ensembles often teach multiple difficulty variants that aren't in the primary appearance list
                    local sourceIDs = C_TransmogSets.GetAllSourceIDs(transmogSetID)
                    debugInfo.setSourceCount = sourceIDs and #sourceIDs or 0

                    if sourceIDs then
                        local hasUncollectedSources = false
                        local hasUncollectedForPlayerInSet = false
                        local hasCollectibleNonArmorSources = false
                        local hasRequirementLockedSources = false
                        local hasPlayerCanCollectButRequirementsFail = false
                        local hasLevelLockedSources = false
                        local hasClassRestrictedSources = false
                        local hasArmorTypeRestrictedSources = false
                        local hasAccountCollectibleSources = false
                        local allSourcesClassRestricted = true
                        local allSourcesAccountLocked = true
                        local pendingItemDataLoad = false

                        for _, sourceID in ipairs(sourceIDs) do
                            local sourceInfo = GetCachedSourceInfo(sourceID)
                            if sourceInfo then
                                -- For ensembles, we care about the actual SOURCE being collected, not just the appearance
                                -- Even if you know the appearance from another difficulty/modifier, the ensemble will still
                                -- teach you this specific source, which counts toward set completion
                                if not sourceInfo.isCollected then
                                    local appearanceInfo = C_TransmogCollection.GetAppearanceInfoBySource(sourceID)
                                    local appearanceID = appearanceInfo and appearanceInfo.appearanceID or sourceInfo.visualID
                                    local isLegendary = (sourceInfo.quality == Enum.ItemQuality.Legendary)
                                    local legendaryAppearanceCollected = appearanceInfo and appearanceInfo.appearanceIsCollected
                                    local legendaryHasAltCollected = false

                                    if isLegendary and not legendaryAppearanceCollected and appearanceID then
                                        local appearanceSources = C_TransmogCollection.GetAppearanceSources(appearanceID,
                                            sourceInfo.categoryID)
                                        if appearanceSources then
                                            for _, appearanceSourceInfo in ipairs(appearanceSources) do
                                                if appearanceSourceInfo.sourceID ~= sourceID and appearanceSourceInfo.isCollected then
                                                    legendaryHasAltCollected = true
                                                    break
                                                end
                                            end
                                        end
                                    end

                                    local skipLegendaryDuplicate = isLegendary and (legendaryAppearanceCollected or
                                                                               legendaryHasAltCollected)

                                    if skipLegendaryDuplicate then
                                        if #debugInfo.appearances > 0 and #debugInfo.appearances[1].sources < 15 then
                                            table.insert(debugInfo.appearances[1].sources, {
                                                sourceID = sourceID,
                                                itemID = sourceInfo.itemID,
                                                itemLink = GetDebugItemLink(sourceInfo.itemID),
                                                isCollected = sourceInfo.isCollected,
                                                isLegendaryDuplicate = true,
                                                appearanceID = appearanceInfo and appearanceInfo.appearanceID or nil,
                                                appearanceIsCollected = appearanceInfo and appearanceInfo.appearanceIsCollected or nil,
                                                hasAlternateCollected = legendaryHasAltCollected
                                            })
                                        end
                                    else
                                        hasUncollectedSources = true

                                        local hasItemData, canCollect = C_TransmogCollection.PlayerCanCollectSource(sourceID)
                                        local collectibleByPlayer = hasItemData and canCollect or sourceInfo.playerCanCollect
                                        local accountHasItemData, accountCanCollect
                                        if C_TransmogCollection.AccountCanCollectSource then
                                            accountHasItemData, accountCanCollect = C_TransmogCollection
                                                .AccountCanCollectSource(sourceID)
                                        else
                                            accountHasItemData = hasItemData
                                            accountCanCollect = canCollect
                                        end
                                        local collectibleByAccount = (accountHasItemData and accountCanCollect) or collectibleByPlayer
                                        if collectibleByAccount then
                                            hasAccountCollectibleSources = true
                                            allSourcesAccountLocked = false
                                        end

                                        if sourceInfo._classID == nil then
                                            local _, _, _, equipLoc, _, cID, subTypeID = C_Item.GetItemInfoInstant(sourceInfo.itemID)
                                            sourceInfo._classID = cID
                                            sourceInfo._itemEquipLoc = equipLoc
                                            sourceInfo.itemSubTypeID = sourceInfo.itemSubTypeID or subTypeID
                                        end
                                        local classID = sourceInfo._classID
                                        local itemEquipLoc = sourceInfo._itemEquipLoc
                                        local itemSubTypeID = sourceInfo.itemSubTypeID
                                        local itemMinLevel = sourceInfo.cachedMinLevel
                                        if itemMinLevel == nil then
                                            itemMinLevel = select(5, C_Item.GetItemInfo(sourceInfo.itemID))
                                            if itemMinLevel then
                                                sourceInfo.cachedMinLevel = itemMinLevel
                                            end
                                        end
                                        if not itemMinLevel then
                                            requestItemDataByID(sourceInfo.itemID)
                                            pendingItemDataLoad = true
                                        end
                                        local isArmor = (classID == ITEM_CLASS_ARMOR)
                                        local isCloak = (itemEquipLoc == "INVTYPE_CLOAK")
                                        local canWearArmorType = CanPlayerWearArmorSubType(itemSubTypeID)
                                        if isCloak then
                                            canWearArmorType = true
                                        end
                                        local playerEligibleByClass = canWearArmorType and sourceInfo.playerCanCollect
                                        local levelLocked = itemMinLevel and playerLevel < itemMinLevel

                                        -- Check if this specific source has TRUE class restrictions (Paladin-only, etc.)
                                        -- This is different from armor type restrictions (cloth/leather/mail/plate)
                                        local classRestrictedForPlayer = false

                                        -- Method 1: Use useErrorType to distinguish true restrictions from armor type restrictions
                                        -- TransmogUseErrorType enum values:
                                        --   7 = Class (Paladin-only, etc.) - TRUE restriction
                                        --   8 = Race - TRUE restriction
                                        --   9 = Faction - TRUE restriction
                                        --  10 = ItemProficiency (plate on priest, etc.) - armor type only
                                        if not sourceInfo.isValidSourceForPlayer then
                                            local errorType = sourceInfo.useErrorType
                                            if errorType == 7 or errorType == 8 or errorType == 9 then
                                                -- Class, Race, or Faction restriction
                                                classRestrictedForPlayer = true
                                            end
                                        end

                                        -- Method 2: Check if source is invalid but armor type/weapon is wearable
                                        -- This catches Paladin-only items on Warriors/DKs who can wear plate
                                        -- Also verify canCollect=false to ensure it's truly a class restriction,
                                        -- not just a temporary validity issue (like level requirement)
                                        if not classRestrictedForPlayer and (not sourceInfo.isValidSourceForPlayer) and canWearArmorType and not canCollect then
                                            classRestrictedForPlayer = true
                                        end

                                        -- Method 3: For items where armor type isn't wearable, use canCollect
                                        -- If canCollect=false, the item has true class/race/faction restrictions
                                        -- If canCollect=true, it's just an armor type restriction (collectible account-wide)
                                        if not classRestrictedForPlayer and not sourceInfo.isValidSourceForPlayer and not canWearArmorType then
                                            if not canCollect then
                                                classRestrictedForPlayer = true
                                            end
                                        end

                                        if classRestrictedForPlayer then
                                            hasClassRestrictedSources = true
                                        else
                                            allSourcesClassRestricted = false
                                        end

                                        if not classRestrictedForPlayer and not canWearArmorType and collectibleByPlayer then
                                            hasArmorTypeRestrictedSources = true
                                        end

                                        if not canWearArmorType then
                                            collectibleByPlayer = false
                                        end

                                        if hasItemData and not canCollect and playerEligibleByClass then
                                            hasRequirementLockedSources = true
                                        end

                                        if levelLocked then
                                            hasRequirementLockedSources = true
                                            hasLevelLockedSources = true
                                            collectibleByPlayer = false
                                            -- Only set hasPlayerCanCollectButRequirementsFail if NOT class-restricted
                                            -- Class-restricted items should trigger otherNoLoot, not lowSkill
                                            if playerEligibleByClass and not classRestrictedForPlayer then
                                                hasPlayerCanCollectButRequirementsFail = true
                                            end
                                        end

                                        if isArmor and collectibleByPlayer and canWearArmorType and not classRestrictedForPlayer then
                                            hasUncollectedForPlayerInSet = true
                                        elseif collectibleByPlayer and not classRestrictedForPlayer then
                                            hasCollectibleNonArmorSources = true
                                        elseif playerEligibleByClass and not collectibleByPlayer and not classRestrictedForPlayer then
                                            -- Sometimes playerCanCollect is true but PlayerCanCollectSource returns false (level requirement, etc.)
                                            -- Only count this if NOT class-restricted (class-restricted should trigger otherNoLoot)
                                            hasRequirementLockedSources = true
                                            hasPlayerCanCollectButRequirementsFail = true
                                        end

                                        -- Store uncollected sources for debug (first 15)
                                        if #debugInfo.appearances > 0 and #debugInfo.appearances[1].sources < 15 then
                                            table.insert(debugInfo.appearances[1].sources, {
                                                sourceID = sourceID,
                                                itemID = sourceInfo.itemID,
                                                itemLink = GetDebugItemLink(sourceInfo.itemID),
                                                itemType = itemType,
                                                itemEquipLoc = itemEquipLoc,
                                                classID = classID,
                                                itemSubTypeID = itemSubTypeID,
                                                isArmor = isArmor,
                                                isCloak = isCloak,
                                                canWearArmorType = canWearArmorType,
                                                itemMinLevel = itemMinLevel,
                                                levelLocked = levelLocked,
                                                isValidSourceForPlayer = sourceInfo.isValidSourceForPlayer,
                                                isCollected = sourceInfo.isCollected,
                                                playerCanCollect = sourceInfo.playerCanCollect,
                                                playerEligibleByClass = playerEligibleByClass,
                                                collectibleByPlayer = collectibleByPlayer,
                                                hasItemDataAPI = hasItemData,
                                                canCollectAPI = canCollect,
                                                accountHasItemDataAPI = accountHasItemData,
                                                accountCanCollectAPI = accountCanCollect,
                                                requirementLocked = hasItemData and not canCollect,
                                                classRestrictedForPlayer = classRestrictedForPlayer,
                                                appearanceID = appearanceInfo and appearanceInfo.appearanceID or nil,
                                                appearanceIsCollected = appearanceInfo and appearanceInfo.appearanceIsCollected or nil,
                                                hasAlternateCollected = legendaryHasAltCollected
                                            })
                                        end
                                    end
                                end
                            end
                        end

                        debugInfo.hasUncollectedSourcesInSet = hasUncollectedSources
                        debugInfo.hasUncollectedForPlayerInSet = hasUncollectedForPlayerInSet
                        debugInfo.hasCollectibleNonArmorSources = hasCollectibleNonArmorSources
                        debugInfo.hasRequirementLockedSources = hasRequirementLockedSources
                        debugInfo.hasPlayerCanCollectButRequirementsFail = hasPlayerCanCollectButRequirementsFail
                        debugInfo.hasLevelLockedSources = hasLevelLockedSources
                        debugInfo.hasClassRestrictedSources = hasClassRestrictedSources
                        debugInfo.hasArmorTypeRestrictedSources = hasArmorTypeRestrictedSources
                        debugInfo.hasAccountCollectibleSources = hasAccountCollectibleSources
                        debugInfo.allSourcesAccountLocked = allSourcesAccountLocked
                        debugInfo.allSourcesClassRestricted = allSourcesClassRestricted
                        debugInfo.pendingItemDataLoad = pendingItemDataLoad

                        if hasUncollectedForPlayerInSet then
                            needsItem = true
                            canEquipEnsemble = true
                        elseif hasCollectibleNonArmorSources then
                            ownPlusItem = true
                        elseif hasRequirementLockedSources then
                            if allSourcesAccountLocked then
                                -- All remaining sources appear permanently restricted
                                otherNoLootItem = true
                            elseif hasLevelLockedSources and hasPlayerCanCollectButRequirementsFail then
                                -- Level-locked but otherwise learnable
                                lowSkillItem = true
                            else
                                needsItem = false
                            end
                        elseif hasUncollectedSources then
                            if allSourcesAccountLocked then
                                otherNoLootItem = true
                            else
                                otherNeedsItem = true
                            end
                        end
                    elseif hasUncollectedAppearances then
                        -- Fallback: if no sources but has uncollected appearances, mark as needed
                        needsItem = true
                    end
                else
                    -- Set is not for this character's class - use completionist indicator
                    -- But we still need to check the actual sources in the set, not just appearances
                    -- because GetSetPrimaryAppearances may show collected if you know the appearance from another source
                    local sourceIDs = C_TransmogSets.GetAllSourceIDs(transmogSetID)
                    debugInfo.setSourceCount = sourceIDs and #sourceIDs or 0

                    if sourceIDs then
                        local hasUncollectedSources = false
                        local hasUncollectedForPlayer = false

                        -- Track set pieces vs non-set pieces separately
                        local hasUncollectedSetArmor = false
                        local hasWearableSetArmor = false
                        local hasWearableNonSetItems = false
                        local hasClassRestrictedSources = false
                        local hasArmorTypeRestrictedSources = false
                        local hasAccountCollectibleSources = false
                        local allSourcesClassRestricted = true
                        local allSourcesAccountLocked = true
                        local allSourcesInvalidForPlayer = true

                        for _, sourceID in ipairs(sourceIDs) do
                            local sourceInfo = GetCachedSourceInfo(sourceID)
                            if sourceInfo then
                                -- Check if this uncollected source is valid for current player
                                -- Call PlayerCanCollectSource directly to verify (more reliable than sourceInfo fields)
                                local hasItemData, canCollect = C_TransmogCollection.PlayerCanCollectSource(sourceID)
                                local collectibleByPlayer = hasItemData and canCollect or sourceInfo.playerCanCollect
                                local accountHasItemData, accountCanCollect
                                if C_TransmogCollection.AccountCanCollectSource then
                                    accountHasItemData, accountCanCollect = C_TransmogCollection
                                        .AccountCanCollectSource(sourceID)
                                else
                                    accountHasItemData = hasItemData
                                    accountCanCollect = canCollect
                                end
                                local collectibleByAccount = (accountHasItemData and accountCanCollect) or collectibleByPlayer
                                if collectibleByAccount then
                                    hasAccountCollectibleSources = true
                                    allSourcesAccountLocked = false
                                end

                                -- Get item info to determine armor type
                                if sourceInfo._classID == nil then
                                    local _, _, _, equipLoc, _, cID, subTypeID = C_Item.GetItemInfoInstant(sourceInfo.itemID)
                                    sourceInfo._classID = cID
                                    sourceInfo._itemEquipLoc = equipLoc
                                    sourceInfo.itemSubTypeID = sourceInfo.itemSubTypeID or subTypeID
                                end
                                local classID = sourceInfo._classID
                                local itemEquipLoc = sourceInfo._itemEquipLoc
                                local itemSubTypeID = sourceInfo.itemSubTypeID
                                local canWearArmorType = CanPlayerWearArmorSubType(itemSubTypeID)
                                local isArmor = (classID == 4)

                                -- Cloaks have classID=4 (armor) but equipLoc="INVTYPE_CLOAK"
                                -- They're universal items, not part of the armor set's class restriction
                                local isCloak = (itemEquipLoc == "INVTYPE_CLOAK")
                                if isCloak then
                                    canWearArmorType = true
                                end

                                -- Determine if this source is part of the armor set or a universal bonus item
                                -- If it's armor but NOT a cloak, it's part of the set's armor type restriction
                                local isSetPiece = isArmor and not isCloak

                                -- For ensembles, we care about the actual SOURCE being collected, not just the appearance
                                -- Even if you know the appearance from another difficulty/modifier, the ensemble will still
                                -- teach you this specific source, which counts toward set completion
                                if not sourceInfo.isCollected then
                                    local appearanceInfo = C_TransmogCollection.GetAppearanceInfoBySource(sourceID)
                                    local appearanceID = appearanceInfo and appearanceInfo.appearanceID or sourceInfo.visualID
                                    local isLegendary = (sourceInfo.quality == Enum.ItemQuality.Legendary)
                                    local legendaryAppearanceCollected = appearanceInfo and appearanceInfo.appearanceIsCollected
                                    local legendaryHasAltCollected = false

                                    if isLegendary and not legendaryAppearanceCollected and appearanceID then
                                        local appearanceSources = C_TransmogCollection.GetAppearanceSources(appearanceID,
                                            sourceInfo.categoryID)
                                        if appearanceSources then
                                            for _, appearanceSourceInfo in ipairs(appearanceSources) do
                                                if appearanceSourceInfo.sourceID ~= sourceID and appearanceSourceInfo.isCollected then
                                                    legendaryHasAltCollected = true
                                                    break
                                                end
                                            end
                                        end
                                    end

                                    local skipLegendaryDuplicate = isLegendary and (legendaryAppearanceCollected or
                                                                               legendaryHasAltCollected)

                                    if skipLegendaryDuplicate then
                                        if #debugInfo.appearances > 0 and #debugInfo.appearances[1].sources < 15 then
                                            table.insert(debugInfo.appearances[1].sources, {
                                                sourceID = sourceID,
                                                itemID = sourceInfo.itemID,
                                                appearanceID = sourceInfo.visualID,
                                                isCollected = sourceInfo.isCollected,
                                                isLegendaryDuplicate = true,
                                                appearanceIsCollected = appearanceInfo and appearanceInfo.appearanceIsCollected or nil,
                                                hasAlternateCollected = legendaryHasAltCollected
                                            })
                                        end
                                    else
                                        hasUncollectedSources = true

                                        -- Track if ANY uncollected source is valid for the player
                                        if sourceInfo.isValidSourceForPlayer then
                                            allSourcesInvalidForPlayer = false
                                        end

                                        -- Check if this specific source has TRUE class restrictions (Paladin-only, etc.)
                                        -- This is different from armor type restrictions (cloth/leather/mail/plate)
                                        local classRestrictedForPlayer = false

                                        -- Method 1: Check if source is invalid but armor type is wearable
                                        -- This catches Paladin-only items on Warriors/DKs who can wear plate
                                        if (not sourceInfo.isValidSourceForPlayer) and canWearArmorType then
                                            classRestrictedForPlayer = true
                                        end

                                        -- Method 2: Use useErrorType to distinguish true restrictions from armor type restrictions
                                        -- TransmogUseErrorType enum values:
                                        --   7 = Class (Paladin-only, etc.) - TRUE restriction
                                        --   8 = Race - TRUE restriction
                                        --   9 = Faction - TRUE restriction
                                        --  10 = ItemProficiency (plate on priest, etc.) - armor type only
                                        if not classRestrictedForPlayer and not sourceInfo.isValidSourceForPlayer then
                                            local errorType = sourceInfo.useErrorType
                                            if errorType == 7 or errorType == 8 or errorType == 9 then
                                                -- Class, Race, or Faction restriction
                                                classRestrictedForPlayer = true
                                            end
                                        end

                                        if classRestrictedForPlayer then
                                            hasClassRestrictedSources = true
                                        else
                                            allSourcesClassRestricted = false
                                        end

                                if not classRestrictedForPlayer and not canWearArmorType and collectibleByPlayer then
                                    hasArmorTypeRestrictedSources = true
                                end

                                        -- Track uncollected set armor separately
                                        if isSetPiece and isArmor then
                                            hasUncollectedSetArmor = true
                                        end

                                        -- Track wearable items
                                        if hasItemData and canCollect and canWearArmorType then
                                            if isSetPiece and isArmor then
                                                -- Uncollected set armor piece that player can wear
                                                hasWearableSetArmor = true
                                            elseif not isSetPiece then
                                                -- Uncollected non-set item (like cloak) that player can wear
                                                hasWearableNonSetItems = true
                                            end
                                            hasUncollectedForPlayer = true
                                        end

                                        -- Store uncollected sources for debug (first 15)
                                        if #debugInfo.appearances > 0 and #debugInfo.appearances[1].sources < 15 then
                                            local hasItemDataAPI, canCollectAPI = C_TransmogCollection
                                                .PlayerCanCollectSource(sourceID)
                                            local accountHasItemDataAPI, accountCanCollectAPI
                                            if C_TransmogCollection.AccountCanCollectSource then
                                                accountHasItemDataAPI, accountCanCollectAPI = C_TransmogCollection
                                                    .AccountCanCollectSource(sourceID)
                                            end
                                            table.insert(debugInfo.appearances[1].sources, {
                                                sourceID = sourceID,
                                                itemID = sourceInfo.itemID,
                                                appearanceID = sourceInfo.visualID,
                                                itemType = itemType,
                                                itemEquipLoc = itemEquipLoc,
                                                classID = classID,
                                                isValidSourceForPlayer = sourceInfo.isValidSourceForPlayer,
                                                isCollected = sourceInfo.isCollected,
                                                playerCanCollect = sourceInfo.playerCanCollect,
                                                itemSubTypeID = itemSubTypeID,
                                                canCollectAPI = canCollectAPI,
                                                accountHasItemDataAPI = accountHasItemDataAPI,
                                                accountCanCollectAPI = accountCanCollectAPI,
                                                canWearArmorType = canWearArmorType,
                                                isArmor = isArmor,
                                                isCloak = isCloak,
                                                isSetPiece = isSetPiece,
                                                appearanceIsCollected = appearanceInfo and appearanceInfo.appearanceIsCollected or nil,
                                                hasAlternateCollected = legendaryHasAltCollected
                                            })
                                        end
                                    end
                                end
                            end
                        end

                        debugInfo.hasUncollectedSourcesInSet = hasUncollectedSources
                        debugInfo.hasUncollectedForPlayerInSet = hasUncollectedForPlayer
                        debugInfo.hasUncollectedSetArmor = hasUncollectedSetArmor
                        debugInfo.hasWearableSetArmor = hasWearableSetArmor
                        debugInfo.hasWearableNonSetItems = hasWearableNonSetItems
                        debugInfo.hasArmorTypeRestrictedSources = hasArmorTypeRestrictedSources
                        debugInfo.hasAccountCollectibleSources = hasAccountCollectibleSources
                        debugInfo.allSourcesAccountLocked = allSourcesAccountLocked

                        -- ENSEMBLE CLASSIFICATION LOGIC (Set-based approach):
                        -- Ensembles contain two types of items:
                        --   1. SET PIECES: The coordinated armor appearances that define the ensemble's purpose
                        --   2. NON-SET PIECES: Bonus items like cloaks that anyone can wear
                        --
                        -- Classification rules:
                        --   - If ANY set armor pieces are wearable → LEARNABLE (yellow star)
                        --   - If NO set armor is wearable BUT has wearable non-set items → COMPLETIONIST (green star)
                        --   - If nothing is wearable → COMPLETIONIST (green star)
                        --
                        -- Examples:
                        --   - Cloth set + cloak on Priest → Cloth is wearable → LEARNABLE
                        --   - Mail set + cloak on Priest → Mail not wearable, cloak is → COMPLETIONIST
                        --   - Mail set on Priest (no cloak) → Nothing wearable → COMPLETIONIST

                        debugInfo.approachUsed = "SetBasedClassification"

                        if hasWearableSetArmor then
                            -- Ensemble contains wearable set armor → this IS for the player's class
                            needsItem = true
                            canEquipEnsemble = true
                        elseif hasWearableNonSetItems then
                            -- Ensemble is NOT for player's class, but has wearable bonus items (like cloaks)
                            -- Show as completionist (green star) - collectible but not the main purpose
                            ownPlusItem = true
                        elseif hasUncollectedSources then
                            -- Has uncollected sources but player can't wear any of them
                            if allSourcesAccountLocked then
                                -- All remaining sources look permanently restricted
                                otherNoLootItem = true
                            else
                                otherNeedsItem = true
                            end
                        end
                    elseif hasUncollectedAppearances then
                        -- Fallback to appearance check if no sources found
                        otherNeedsItem = true
                    end
                end
            end
        else
            -- Fallback to old method if GetSetInfo returns nil
            debugInfo.fallbackUsed = true
            validForCharacter = false

            local sourceIDs = C_TransmogSets.GetAllSourceIDs(transmogSetID)
            for sourceIDIndex = 1, #sourceIDs do
                local sourceInfo = GetCachedSourceInfo(sourceIDs[sourceIDIndex])
                if sourceInfo and not sourceInfo.isCollected then
                    needsItem = true
                    -- Have to iterate through all sources provided in case some are not valid for the toon
                    if not validForCharacter then
                        validForCharacter = sourceInfo.isValidSourceForPlayer
                    end
                end
            end
        end
    end

    if lowSkillItem or lowSkillPlusItem then
        needsItem = false
    end

    -- Debug info available in debugInfo variable for troubleshooting
    -- Debug template for troubleshooting specific items:
    -- if debugInfo.itemID == ITEM_ID_HERE then
    --     print("=== CaerdonWardrobe Item Debug ===")
    --     print("Item ID: " .. debugInfo.itemID)
    --     print("Transmog Set ID: " .. tostring(debugInfo.transmogSetID))
    --     print("SetInfo.validForCharacter: " ..
    --         tostring(debugInfo.setInfo and debugInfo.setInfo.validForCharacter or "N/A"))
    --     print("SetInfo.collected: " .. tostring(debugInfo.setInfo and debugInfo.setInfo.collected or "N/A"))
    --     print("Result - needsItem: " .. tostring(needsItem))
    --     print("Result - otherNeedsItem: " .. tostring(otherNeedsItem))
    --     print("Result - otherNoLootItem: " .. tostring(otherNoLootItem))
    --     print("Result - canEquipEnsemble: " .. tostring(canEquipEnsemble))
    --     print("Result - validForCharacter: " .. tostring(validForCharacter))
    --     if debugInfo.hasClassRestrictedSources ~= nil then
    --         print("hasClassRestrictedSources: " .. tostring(debugInfo.hasClassRestrictedSources))
    --         print("allSourcesClassRestricted: " .. tostring(debugInfo.allSourcesClassRestricted))
    --     end
    --     print("=====================================")
    -- end

    local itemName = C_Item.GetItemInfo(self.item:GetItemLink())
    local factionName, changed = string.gsub(itemName, L["Contract: "], "")
    if changed > 0 then
        local expansionIndex = 0
        for expansionIndex = 0, LE_EXPANSION_LEVEL_CURRENT do
            local majorFactionIDs = C_MajorFactions.GetMajorFactionIDs(expansionIndex);
            for index, majorFactionID in ipairs(majorFactionIDs) do
                local factionData = C_MajorFactions.GetMajorFactionData(majorFactionID)
                if factionData.name == factionName or factionData.name == L["The "] .. factionName then -- Silly but "Contract: Assembly of the Deeps" needs to match "The Assembly of the Deeps"
                    local hasMaxRenown = C_MajorFactions.HasMaximumRenown(majorFactionID)
                    local isAccountWideRenown = C_Reputation.IsAccountWideReputation(majorFactionID)
                    if hasMaxRenown then
                        if not isAccountWideRenown then
                            needsItem = false
                            otherNeedsItem = true
                        end
                    else
                        needsItem = true
                    end
                end
            end
        end
    end

    -- May not need any of this for anything but keeping around
    -- local spellID = C_Item.GetFirstTriggeredSpellForItem(caerdonItem:GetItemID(), caerdonItem:GetItemQuality())
    -- if spellID then
    --     print("Spell ID: " .. spellID)
    --     print("Item ID: " .. caerdonItem:GetItemID())
    -- end
    -- local spellName, spellID = C_Item.GetItemSpell(caerdonItem:GetItemLink())
    -- print(spellName)

    return {
        needsItem = needsItem,
        otherNeedsItem = otherNeedsItem,
        ownPlusItem = ownPlusItem,
        lowSkillItem = lowSkillItem,
        lowSkillPlusItem = lowSkillPlusItem,
        otherNoLootItem = otherNoLootItem,
        validForCharacter = validForCharacter,
        -- For ensembles, canEquip should reflect if player can equip uncollected sources
        -- Not just if the set itself is marked as valid for character
        canEquip = validForCharacter or canEquipEnsemble,
        isEnsemble = transmogSetID ~= nil
    }
end
