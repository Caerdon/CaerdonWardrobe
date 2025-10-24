CaerdonConsumable = {}
CaerdonConsumableMixin = {}

local ADDON_NAME, NS = ...
local L = NS.L

local bit_band = bit.band
local bit_lshift = bit.lshift

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
    -- 2 = Leather - leather/mail/plate wearers only
    -- 3 = Mail - mail/plate wearers only
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

    -- Leather wearers: Druid, Monk, Rogue, Demon Hunter, and all mail/plate wearers
    if itemSubTypeID == 2 then
        return playerClass == "DRUID" or playerClass == "MONK" or playerClass == "ROGUE" or playerClass == "DEMONHUNTER"
            or playerClass == "HUNTER" or playerClass == "SHAMAN" or playerClass == "EVOKER"
            or playerClass == "WARRIOR" or playerClass == "PALADIN" or playerClass == "DEATHKNIGHT"
    end

    -- Mail wearers: Hunter, Shaman, Evoker, and plate wearers
    if itemSubTypeID == 3 then
        return playerClass == "HUNTER" or playerClass == "SHAMAN" or playerClass == "EVOKER"
            or playerClass == "WARRIOR" or playerClass == "PALADIN" or playerClass == "DEATHKNIGHT"
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
    local validForCharacter = true
    local canEquipEnsemble = false -- Track if player can equip uncollected sources from ensemble

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
            local _, _, playerClassID = UnitClass("player")
            local isPlayerClassInSet = true

            if classMask and classMask ~= 0 and playerClassID then
                local playerClassMask = bit_lshift(1, playerClassID - 1)
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

                for _, appearanceInfo in ipairs(primaryAppearances) do
                    local appearanceDebug = {
                        appearanceID = appearanceInfo.appearanceID,
                        collected = appearanceInfo.collected,
                        sources = {}
                    }

                    if not appearanceInfo.collected then
                        hasUncollectedAppearances = true

                        -- Get all sources for this appearance to check player eligibility
                        -- Note: GetAllAppearanceSources only returns sources valid for current class
                        -- So if validForCharacter is false, this will return empty
                        local appearanceSources = C_TransmogCollection.GetAllAppearanceSources(appearanceInfo
                            .appearanceID)
                        appearanceDebug.sourceCount = appearanceSources and #appearanceSources or 0

                        if appearanceSources then
                            for _, sourceID in ipairs(appearanceSources) do
                                local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
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
                        for _, sourceID in ipairs(sourceIDs) do
                            local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
                            if sourceInfo then
                                if not sourceInfo.isCollected then
                                    hasUncollectedSources = true

                                    -- Store uncollected sources for debug (first 15)
                                    if #debugInfo.appearances > 0 and #debugInfo.appearances[1].sources < 15 then
                                        table.insert(debugInfo.appearances[1].sources, {
                                            sourceID = sourceID,
                                            isValidSourceForPlayer = sourceInfo.isValidSourceForPlayer,
                                            isCollected = sourceInfo.isCollected,
                                            playerCanCollect = sourceInfo.playerCanCollect
                                        })
                                    end
                                end
                            end
                        end

                        debugInfo.hasUncollectedSourcesInSet = hasUncollectedSources

                        if hasUncollectedSources then
                            needsItem = true
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

                        for _, sourceID in ipairs(sourceIDs) do
                            local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
                            if sourceInfo then
                                -- Check if this uncollected source is valid for current player
                                -- Call PlayerCanCollectSource directly to verify (more reliable than sourceInfo fields)
                                local hasItemData, canCollect = C_TransmogCollection.PlayerCanCollectSource(sourceID)

                                -- Get item info to determine armor type
                                local _, itemType, _, itemEquipLoc, _, classID, itemSubTypeID = C_Item
                                    .GetItemInfoInstant(
                                        sourceInfo.itemID)
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

                                if not sourceInfo.isCollected then
                                    hasUncollectedSources = true

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
                                            canWearArmorType = canWearArmorType,
                                            isArmor = isArmor,
                                            isCloak = isCloak,
                                            isSetPiece = isSetPiece
                                        })
                                    end
                                end
                            end
                        end

                        debugInfo.hasUncollectedSourcesInSet = hasUncollectedSources
                        debugInfo.hasUncollectedForPlayerInSet = hasUncollectedForPlayer
                        debugInfo.hasUncollectedSetArmor = hasUncollectedSetArmor
                        debugInfo.hasWearableSetArmor = hasWearableSetArmor
                        debugInfo.hasWearableNonSetItems = hasWearableNonSetItems

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
                            otherNeedsItem = true
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
                local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceIDs[sourceIDIndex])
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

    -- Print debug info for specific items (add item IDs to debug specific items)
    -- Example: if debugInfo.itemID == 241481 or debugInfo.itemID == 241420 then
    if false then -- Set to true and add item IDs above to enable debug output
        print("=== CaerdonWardrobe Ensemble Debug ===")
        print("Item ID: " .. debugInfo.itemID)
        print("Transmog Set ID: " .. tostring(debugInfo.transmogSetID))
        print("Has SetInfo: " .. tostring(debugInfo.setInfo ~= nil))
        if debugInfo.setInfo then
            print("  SetInfo.collected: " .. tostring(debugInfo.setInfo.collected))
            print("  SetInfo.validForCharacter: " .. tostring(debugInfo.setInfo.validForCharacter))
        end
        print("Has PrimaryAppearances: " .. tostring(debugInfo.primaryAppearances ~= nil))
        if debugInfo.primaryAppearances then
            print("  Appearance Count: " .. #debugInfo.primaryAppearances)
            for i, app in ipairs(debugInfo.appearances) do
                print("  Appearance " .. i .. ":")
                print("    ID: " .. app.appearanceID)
                print("    Collected: " .. tostring(app.collected))
                print("    Source Count: " .. (app.sourceCount or 0))
                if #app.sources > 0 then
                    for j, src in ipairs(app.sources) do
                        print("      Source " .. j .. ": ID=" .. src.sourceID ..
                            ", itemID=" .. tostring(src.itemID) ..
                            ", equipLoc=" .. tostring(src.itemEquipLoc) ..
                            ", classID=" .. tostring(src.classID) ..
                            ", subTypeID=" .. tostring(src.itemSubTypeID) ..
                            ", isArmor=" .. tostring(src.isArmor) ..
                            ", isCloak=" .. tostring(src.isCloak) ..
                            ", isSetPiece=" .. tostring(src.isSetPiece) ..
                            ", canWearArmorType=" .. tostring(src.canWearArmorType) ..
                            ", isCollected=" .. tostring(src.isCollected))
                    end
                end
            end
        end
        print("Set Source Count: " .. tostring(debugInfo.setSourceCount or "N/A"))
        print("Has Uncollected Sources In Set: " .. tostring(debugInfo.hasUncollectedSourcesInSet or "N/A"))
        print("Has Uncollected For Player In Set: " .. tostring(debugInfo.hasUncollectedForPlayerInSet or "N/A"))
        print("Has Uncollected Set Armor: " .. tostring(debugInfo.hasUncollectedSetArmor or "N/A"))
        print("Has Wearable Set Armor: " .. tostring(debugInfo.hasWearableSetArmor or "N/A"))
        print("Has Wearable Non-Set Items: " .. tostring(debugInfo.hasWearableNonSetItems or "N/A"))
        print("Class Mask (Primary Set): " .. tostring(debugInfo.classMask or "N/A"))
        print("Approach Used: " .. tostring(debugInfo.approachUsed or "N/A"))
        print("Fallback Used: " .. tostring(debugInfo.fallbackUsed))
        print("Result - needsItem: " .. tostring(needsItem) .. ", otherNeedsItem: " .. tostring(otherNeedsItem))
        print("validForCharacter: " .. tostring(validForCharacter))
        print("canEquipEnsemble: " .. tostring(canEquipEnsemble))
        print("canEquip (final): " .. tostring(validForCharacter or canEquipEnsemble))
        print("Config - ShowLearnableByOther.Merchant: " ..
            tostring(CaerdonWardrobeConfig.Icon.ShowLearnableByOther.Merchant))
        print("=====================================")
    end

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
        validForCharacter = validForCharacter,
        -- For ensembles, canEquip should reflect if player can equip uncollected sources
        -- Not just if the set itself is marked as valid for character
        canEquip = validForCharacter or canEquipEnsemble,
        isEnsemble = transmogSetID ~= nil
    }
end
