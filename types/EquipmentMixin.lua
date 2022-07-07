CaerdonEquipment = {}
CaerdonEquipmentMixin = {}

--[[static]] function CaerdonEquipment:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonEquipment:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonWardrobeItemDataMixin, CaerdonEquipmentMixin)
    itemType.item = caerdonItem
    return itemType
end

function CaerdonEquipmentMixin:LoadSources(callbackFunction)
    local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(self.item:GetItemLink())
    if not sourceID then
        -- TODO: Not sure why this is the case?  EncounterJournal links aren't returning source info
        appearanceID, sourceID = C_TransmogCollection.GetItemInfo(self.item:GetItemID())
    end

    local continuableContainer = ContinuableContainer:Create();
    local cancelFunc = function() end;

    if not appearanceID then
        callbackFunction()
    else
        local appearanceSourceIDs = C_TransmogCollection.GetAllAppearanceSources(appearanceID)
        for appearanceSourceIndex, appearanceSourceID in pairs(appearanceSourceIDs) do
            local itemID = C_TransmogCollection.GetSourceItemID(appearanceSourceID);
            -- Using Item here to avoid recursively diving
            local item = Item:CreateFromItemID(itemID)
            if not item:IsItemEmpty() then
                continuableContainer:AddContinuable(item);
            end
        end

        cancelFunc = continuableContainer:ContinueOnLoad(callbackFunction);
    end

    return cancelFunc
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
        for setIndex=1, C_EquipmentSet.GetNumEquipmentSets() do
            local equipmentSetIDs = C_EquipmentSet.GetEquipmentSetIDs()
            local equipmentSetID = equipmentSetIDs[setIndex]
            local name, icon, setID, isEquipped, numItems, numEquipped, numInventory, numMissing, numIgnored = C_EquipmentSet.GetEquipmentSetInfo(equipmentSetID)

            local equipLocations = C_EquipmentSet.GetItemLocations(equipmentSetID)
            if equipLocations then
                local locationIndex
                for locationIndex=INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
                    local location = equipLocations[locationIndex]
                    if location ~= nil then
                        -- TODO: Keep an eye out for a new way to do this in the API
                        local isPlayer, isBank, isBags, isVoidStorage, equipSlot, equipBag, equipTab, equipVoidSlot = EquipmentManager_UnpackLocation(location)
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
    local itemParamType = type(item)
    if itemParamType == "string" then
        item = gsub(item, "\124\124", "\124")
        item = CaerdonItem:CreateFromItemLink(item)
    elseif itemParamType == "number" then
        item = CaerdonItem:CreateFromItemID(item)
    elseif itemParamType ~= "table" then
        error("Must specify itemLink, itemID, or CaerdonItem for GetTransmogInfo")
    end

    local itemLink = item:GetItemLink()
    if not itemLink then
        return
    end

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

    -- Keep available for debug info
    local appearanceInfo, sourceInfo
    local isInfoReady, canCollect, accountCanCollect
    local shouldSearchSources
    local appearanceSources
    local currentSourceFound
    local otherSourceFound
    local sourceSpecs
    local lowestLevelFound
    local matchedSources = {}

    -- Appearance is the visual look - can have many sources
    -- Sets can have multiple appearances (normal vs mythic, etc.)
    local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemLink)
    if not sourceID then
        -- TODO: Not sure why this is the case?  EncounterJournal links aren't returning source info
        appearanceID, sourceID = C_TransmogCollection.GetItemInfo(item:GetItemID())
    end

    if sourceID then
        -- TODO: Look into this more - doc indicates it's an itemModifiedAppearanceID returned from C_TransmogCollection.GetItemInfo (which may also be sourceID?)
        -- PlayerKnowsSource just seems broken if that's true, though.
        -- VisualID == AppearanceID, SourceID == ItemModifiedAppearanceID
        -- Also check PlayerHasTransmog with the following
        -- print(itemLink .. ",  PlayerHasTransmogItemModifiedAppearance: " .. tostring(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID)) .. ", PlayerKnowsSource: " .. tostring(C_TransmogCollection.PlayerKnowsSource(sourceID)))
    end

    if item:GetMinLevel() and item:GetMinLevel() > UnitLevel("player") then
        hasMetRequirements = false
    end

    if sourceID and sourceID ~= NO_TRANSMOG_SOURCE_ID then
        isTransmog = true

        -- If canCollect, then the current toon can learn it (but may already know it)
        isInfoReady, canCollect = C_TransmogCollection.PlayerCanCollectSource(sourceID)
        -- hasItemData, accountCanCollect = C_TransmogCollection.AccountCanCollectSource(sourceID)

        -- if not isInfoReady then
        --     print('Info not ready - source ID ' .. tostring(sourceID) .. ' for ' .. itemLink)
        -- end

         -- TODO: Forcing to always for now be true because a class could have an item it knows
         -- that no other class can use, so we actually need the item rather than just completionist
        shouldSearchSources = true

        sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)

        -- if sourceInfo and sourceInfo.quality then
        --     -- Item is ready
        -- else
        --     print('SourceInfo quality not available: ' .. itemLink)
        -- end
        
        sourceSpecs = GetItemSpecInfo(itemLink)

        -- If the source is already collected, we don't need to check anything else for the source / appearance
        if sourceInfo and not sourceInfo.isCollected then
            -- Only returns for sources that can be transmogged by current toon right now
            -- appearanceInfo = C_TransmogCollection.GetAppearanceInfoBySource(sourceID)
            -- if appearanceInfo then -- Toon can learn
            -- --     needsItem = not appearanceInfo.sourceIsCollected
            -- --     isCompletionistItem = needsItem and appearanceInfo.appearanceIsCollected

            -- --     print(itemLink .. ", " .. tostring(needsItem) .. ", " .. tostring(isCompletionistItem))
            --     -- TODO: I think this logic might help with appearances but not sources?
            --     -- What are appearance non-level requirements?
            --     if appearanceInfo.appearanceHasAnyNonLevelRequirements and not appearanceInfo.appearanceMeetsNonLevelRequirements then
            --         -- TODO: Do I want to separate out level vs other requirements?
            --         hasMetRequirements = false
            --     end
            -- -- else
            -- --     shouldSearchSources = true
            -- end

            if shouldSearchSources then
                local sourceIndex, source
                local appearanceSourceIDs = C_TransmogCollection.GetAllAppearanceSources(appearanceID)
                for sourceIndex, source in pairs(appearanceSourceIDs) do
                    local isInfoReadySearch, canCollectSearch = C_TransmogCollection.PlayerCanCollectSource(source)
                    -- if not isInfoReadySearch then
                    --     print('Search Info not ready - source ID ' .. tostring(source) .. ' for ' .. itemLink)
                    -- end

                    local info = C_TransmogCollection.GetSourceInfo(source)
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
                    end
                end

                -- appearanceSources = C_TransmogCollection.GetAppearanceSources(appearanceID)
                currentSourceFound = false
                otherSourceFound = false

                if appearanceSources then
                    local sourceIndex, source
                    for sourceIndex, source in pairs(appearanceSources) do
                        local _, sourceType, sourceSubType, sourceEquipLoc, _, sourceTypeID, sourceSubTypeID = GetItemInfoInstant(source.itemID)
                        -- SubTypeID is returned from GetAppearanceSourceInfo, but it seems to be tied to the appearance, since it was wrong for an item that crossed over.
                        source.itemSubTypeID = sourceSubTypeID -- stuff it in here (mostly for debug)
                        source.specs = GetItemSpecInfo(source.itemID) -- also this

                        if source.sourceID == sourceID and source.isCollected then
                            currentSourceFound = true
                            break -- found the current source so don't need to learn or continue the search
                        elseif source.isCollected and (item:GetItemSubTypeID() == source.itemSubTypeID or source.itemSubTypeID == Enum.ItemArmorSubclass.Cosmetic) then 
                            -- Make sure it's the same armor type and doesn't have spec reqs
                            -- (otherwise assume we need it since we can't check for specs outside our own)
                            -- TODO: Keep an eye out for a way to get spec reqs for an item not for that class
                            local sourceMinLevel = (select(5, GetItemInfo(source.itemID)))
                            if lowestLevelFound == nil or sourceMinLevel and sourceMinLevel < lowestLevelFound then
                                lowestLevelFound = sourceMinLevel
                            end

                            -- Log any matched sources even if they're treated as not found due to logic below (for debug)
                            table.insert(matchedSources, source)
                            otherSourceFound = true -- remove this and do something like below if I can ever find a way to get full spec / class reqs for an item

                            -- If this item covers classes that aren't already covered by another source, we want to learn it... 
                            -- EXCEPT TODO: This doesn't work because GetItemSpecInfo appears to at least sometimes return just your own class specs for an item...
                            -- Weapons may be accurate but also spec doesn't seem to matter for them to show up.
                            -- local sourceSpecIndex, sourceSpec
                            -- if sourceSpecs and #sourceSpecs > 0 and source.specs and #source.specs > 0 then
                            --     local itemClasses = {}
                            --     print("Checking classes for " .. itemLink)

                            --     for sourceSpecIndex, sourceSpec in pairs(source.specs) do
                            --         local id, name, description, icon, role, classFile, className = GetSpecializationInfoByID(sourceSpec)
                            --         print(itemLink .. source.name .. " found " .. className)
                            --         table.insert(itemClasses, className)
                            --     end

                            --     for sourceSpecIndex, sourceSpec in pairs(sourceSpecs) do
                            --         -- print(itemLink .. ": " .. sourceSpec)
                            --         local id, name, description, icon, role, classFile, className = GetSpecializationInfoByID(sourceSpec)
                            --         if not tContains(itemClasses, className) then
                            --             print(itemLink .. ": New Spec " .. sourceSpec .. " for " .. className .. " " .. source.itemID)
                            --             otherSourceFound = false
                            --             break
                            --         else
                            --             otherSourceFound = true
                            --         end
                            --     end
                            -- else
                            --     otherSourceFound = true
                            -- end
                        end
                    end

                    -- Ignore the other source if this item is lower level than what we know
                    -- TODO: Find an item to add to tests
                    local includeLevelDifferences = CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem and CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentLevel

                    local itemMinLevel = item:GetMinLevel()
                    if lowestLevelFound ~= nil and itemMinLevel ~= nil and itemMinLevel < lowestLevelFound and includeLevelDifferences then
                        -- This logic accounts for the changes to transmog that allow lower-level players to wear transmog up to a certain level.
                        -- This changes "completionist" slightly in that you will no longer collect every single level difference of an appearance as it's no longer needed.
                        if (lowestLevelFound > 9 and itemMinLevel <= 9) or (lowestLevelFound > 48 and itemMinLevel <= 48) or (lowestLevelFound > 60 and itemMinLevel <= 60) then
                            otherSourceFound = false
                        end
                    end
                end

                if not currentSourceFound then
                    if canCollect then
                        needsItem = true
                    else
                        otherNeedsItem = true
                    end
                    
                    isCompletionistItem = otherSourceFound
                end
            end

            if canCollect then
                local playerSpecID = -1
                local playerSpec = GetSpecialization();
                if (playerSpec) then
                    playerSpecID = GetSpecializationInfo(playerSpec, nil, nil, nil, UnitSex("player"));
                end
                local playerLootSpecID = GetLootSpecialization()
                if playerLootSpecID == 0 then
                    playerLootSpecID = playerSpecID
                end
            
                if sourceSpecs then
                    for specIndex = 1, #sourceSpecs do
                        matchesLootSpec = false
    
                        local validSpecID = GetSpecializationInfo(specIndex, nil, nil, nil, UnitSex("player"));
                        if validSpecID == playerLootSpecID then
                            matchesLootSpec = true
                            break
                        end
                    end
                end
            end    
        end
    end

    return {
        isTransmog = isTransmog,
        isBindOnPickup = isBindOnPickup,
        appearanceID = appearanceID,
        sourceID = sourceID,
        canEquip = canCollect,
        needsItem = needsItem,
        hasMetRequirements = hasMetRequirements,
        otherNeedsItem = otherNeedsItem,
        isCompletionistItem = isCompletionistItem,
        matchesLootSpec = matchesLootSpec,
        forDebugUseOnly = CaerdonWardrobeConfig.Debug.Enabled and {
            matchedSources = matchedSources,
            isInfoReady = isInfoReady,
            shouldSearchSources = shouldSearchSources,
            appearanceInfo = appearanceInfo,
            sourceInfo = sourceInfo,
            appearanceSources = appearanceSources,
            itemTypeData = itemTypeData,
            currentSourceFound = currentSourceFound,
            otherSourceFound = otherSourceFound,
            sourceSpecs = sourceSpecs,
            lowestLevelFound = lowestLevelFound
        }
    }
end
