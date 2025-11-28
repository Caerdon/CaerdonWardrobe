CaerdonHousing = {}
CaerdonHousingMixin = {}

local ADDON_NAME, NS = ...

local interfaceVersion = select(4, GetBuildInfo())
local hasHousingSupport = interfaceVersion >= 110207 and Enum and Enum.ItemClass and Enum.ItemClass.Housing ~= nil

--[[static]]
function CaerdonHousing:CreateFromCaerdonItem(caerdonItem)
    if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
        error("Usage: CaerdonHousing:CreateFromCaerdonItem(caerdonItem)", 2)
    end

    local itemType = CreateFromMixins(CaerdonWardrobeItemDataMixin, CaerdonHousingMixin)
    itemType.item = caerdonItem
    return itemType
end

function CaerdonHousingMixin:GetHousingInfo()
    if not hasHousingSupport or not C_HousingCatalog then
        return nil
    end

    local item = self.item
    if not item then
        return nil
    end

    local itemLink = item:GetItemLink()
    if not itemLink then
        return nil
    end

    local catalogEntryInfo = C_HousingCatalog.GetCatalogEntryInfoByItem and
    C_HousingCatalog.GetCatalogEntryInfoByItem(itemLink, true) or nil

    local ownedStored = 0
    local placedCount = 0
    local bagCount = 0
    local totalOwned = 0
    local remainingRedeemable = 0
    local firstAcquisitionBonus = 0
    local showQuantity = true
    local maxStack = 0
    local entryType, entrySubtype, recordID
    local iconTexture, iconAtlas, sourceText
    local subClassID = item:GetItemSubTypeID()
    local itemID = item:GetItemID()
    local entrySubtypeOwned = Enum and Enum.HousingCatalogEntrySubtype
    local isServiceItem = subClassID and Enum and Enum.ItemHousingSubclass and Enum.ItemHousingSubclass.ServiceItem and
    subClassID == Enum.ItemHousingSubclass.ServiceItem

    local isOwnedSubtype = false

    if catalogEntryInfo then
        ownedStored = (catalogEntryInfo.quantity or 0) + (catalogEntryInfo.remainingRedeemable or 0)
        remainingRedeemable = catalogEntryInfo.remainingRedeemable or 0
        placedCount = catalogEntryInfo.numPlaced or 0
        totalOwned = ownedStored + placedCount
        firstAcquisitionBonus = catalogEntryInfo.firstAcquisitionBonus or 0
        showQuantity = catalogEntryInfo.showQuantity ~= false
        iconTexture = catalogEntryInfo.iconTexture
        iconAtlas = catalogEntryInfo.iconAtlas
        sourceText = catalogEntryInfo.sourceText

        entryType = catalogEntryInfo.entryID and catalogEntryInfo.entryID.entryType
        entrySubtype = catalogEntryInfo.entryID and catalogEntryInfo.entryID.entrySubtype
        recordID = catalogEntryInfo.entryID and catalogEntryInfo.entryID.recordID

        local ownedSubtype = Enum and Enum.HousingCatalogEntrySubtype
        if ownedSubtype and entrySubtype then
            if entrySubtype == ownedSubtype.OwnedModifiedStack or entrySubtype == ownedSubtype.OwnedUnmodifiedStack then
                isOwnedSubtype = true
            end
        end
    end

    -- If base lookup returned unowned with zero counts, try explicit owned entryID variants with subtypeIdentifier=0.
    if entryType and recordID and totalOwned == 0 and Enum and Enum.HousingCatalogEntrySubtype and C_HousingCatalog.GetCatalogEntryInfo then
        local function TryOwnedEntry(ownedSubtype)
            local entryID = {
                entryType = entryType,
                entrySubtype = ownedSubtype,
                recordID = recordID,
                subtypeIdentifier = 0
            }
            local info = C_HousingCatalog.GetCatalogEntryInfo(entryID)
            if info then
                local q = (info.quantity or 0) + (info.remainingRedeemable or 0)
                local p = info.numPlaced or 0
                local r = info.remainingRedeemable or 0
                local total = q + p
                if total > 0 then
                    return info, q, p, r
                end
            end
        end

        local ownedInfo, q, p, r = TryOwnedEntry(Enum.HousingCatalogEntrySubtype.OwnedUnmodifiedStack)
        if not ownedInfo then
            ownedInfo, q, p, r = TryOwnedEntry(Enum.HousingCatalogEntrySubtype.OwnedModifiedStack)
        end

        if ownedInfo then
            catalogEntryInfo = ownedInfo
            ownedStored = q
            remainingRedeemable = r or remainingRedeemable
            placedCount = p
            totalOwned = q + p
            firstAcquisitionBonus = ownedInfo.firstAcquisitionBonus or firstAcquisitionBonus
            showQuantity = ownedInfo.showQuantity ~= false
            iconTexture = ownedInfo.iconTexture or iconTexture
            iconAtlas = ownedInfo.iconAtlas or iconAtlas
            sourceText = ownedInfo.sourceText or sourceText
            entrySubtype = ownedInfo.entryID and ownedInfo.entryID.entrySubtype or
            Enum.HousingCatalogEntrySubtype.OwnedUnmodifiedStack
            isOwnedSubtype = true
        end
    end

    -- Fallback: try fetching by recordID when the item -> entry lookup doesn't return owned data yet.
    if (not catalogEntryInfo or (totalOwned == 0 and not dyeColorID)) and C_HousingCatalog.GetCatalogEntryInfoByRecordID and itemID then
        local fallbackEntryType = Enum and Enum.HousingCatalogEntryType
        local guessEntryType = fallbackEntryType and fallbackEntryType.Decor or nil
        if subClassID and Enum and Enum.ItemHousingSubclass and Enum.ItemHousingSubclass.Room and subClassID == Enum.ItemHousingSubclass.Room then
            guessEntryType = fallbackEntryType and fallbackEntryType.Room or guessEntryType
        end

        if guessEntryType then
            local fallbackInfo = C_HousingCatalog.GetCatalogEntryInfoByRecordID(guessEntryType, itemID, true)
            if fallbackInfo then
                catalogEntryInfo = fallbackInfo
                ownedStored = (fallbackInfo.quantity or 0) + (fallbackInfo.remainingRedeemable or 0)
                placedCount = fallbackInfo.numPlaced or 0
                totalOwned = ownedStored + placedCount
                firstAcquisitionBonus = fallbackInfo.firstAcquisitionBonus or 0
                showQuantity = fallbackInfo.showQuantity ~= false
                iconTexture = fallbackInfo.iconTexture
                iconAtlas = fallbackInfo.iconAtlas
                sourceText = fallbackInfo.sourceText

                entryType = fallbackInfo.entryID and fallbackInfo.entryID.entryType or guessEntryType
                entrySubtype = fallbackInfo.entryID and fallbackInfo.entryID.entrySubtype
                recordID = fallbackInfo.entryID and fallbackInfo.entryID.recordID or itemID

                local ownedSubtype = Enum and Enum.HousingCatalogEntrySubtype
                if ownedSubtype and entrySubtype then
                    if entrySubtype == ownedSubtype.OwnedModifiedStack or entrySubtype == ownedSubtype.OwnedUnmodifiedStack then
                        isOwnedSubtype = true
                    end
                end
            end
        end
    end

    if itemID then
        bagCount = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID, true, true)) or bagCount
        maxStack = (C_Item and C_Item.GetItemMaxStack and C_Item.GetItemMaxStack(itemID)) or maxStack
        if maxStack == 0 then
            local _, _, _, _, _, _, _, stackSize = C_Item.GetItemInfo(itemID)
            if stackSize then
                maxStack = stackSize
            end
        end
    end

    local dyeColorID, isDyeOwned
    if not catalogEntryInfo and C_DyeColor then
        dyeColorID = C_DyeColor.GetDyeColorForItem and C_DyeColor.GetDyeColorForItem(itemLink)
        if dyeColorID then
            isDyeOwned = C_DyeColor.IsDyeColorOwned and C_DyeColor.IsDyeColorOwned(dyeColorID) or false
            totalOwned = isDyeOwned and 1 or 0
            ownedStored = totalOwned
            showQuantity = true
        end
    end

    -- Only treat bag copies as owned for service items (consumable-use items). For decor, we want bag copies to stay unowned until redeemed.
    if isServiceItem then
        totalOwned = totalOwned + bagCount
        ownedStored = ownedStored + bagCount
    end

    -- If the catalog marks this as an owned stack, ensure we don't treat it as unowned even if counts are zero (some service/decor items may be auto-stored).
    if isOwnedSubtype then
        totalOwned = math.max(totalOwned, 1)
    end

    -- Consider the info pending when no catalog data OR when owned state may lag (zero totals for non-service items).
    local isPending = (catalogEntryInfo == nil and not dyeColorID)
        or (not isServiceItem and catalogEntryInfo ~= nil and ownedStored == 0 and remainingRedeemable == 0 and placedCount == 0)

    local function SanitizeCount(value)
        if not value or value < 0 then
            return 0
        end
        if value > 1000000 then
            return 0
        end
        return value
    end

    ownedStored = SanitizeCount(ownedStored)
    remainingRedeemable = SanitizeCount(remainingRedeemable)
    placedCount = SanitizeCount(placedCount)
    bagCount = SanitizeCount(bagCount)
    maxStack = SanitizeCount(maxStack)

    if maxStack > 0 then
        ownedStored = math.min(ownedStored, maxStack)
        remainingRedeemable = math.min(remainingRedeemable, maxStack)
    end

    if isServiceItem then
        -- For service items, treat any count anywhere as owned; avoid double-counting by taking the max.
        totalOwned = math.max(placedCount, ownedStored, remainingRedeemable, bagCount)
    else
        totalOwned = placedCount + ownedStored + remainingRedeemable
    end

    if totalOwned > 0 then
        isPending = false
    end

    return {
        entryInfo = catalogEntryInfo,
        entryType = entryType,
        entrySubtype = entrySubtype,
        recordID = recordID,
        subClassID = subClassID,
        maxStack = maxStack,
        bagCount = bagCount,
        remainingRedeemable = remainingRedeemable,
        isServiceItem = isServiceItem,
        ownedStored = ownedStored,
        placedCount = placedCount,
        totalOwned = totalOwned,
        isUnowned = totalOwned == 0,
        firstAcquisitionBonus = firstAcquisitionBonus,
        showQuantity = showQuantity,
        iconTexture = iconTexture,
        iconAtlas = iconAtlas,
        sourceText = sourceText,
        dyeColorID = dyeColorID,
        isDyeOwned = isDyeOwned,
        isPending = isPending
    }
end
