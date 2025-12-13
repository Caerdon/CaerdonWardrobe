CaerdonHousing = {}
CaerdonHousingMixin = {}

local ADDON_NAME, NS = ...

local interfaceVersion = select(4, GetBuildInfo())
local hasHousingSupport = interfaceVersion >= 110207 and Enum and Enum.ItemClass and Enum.ItemClass.Housing ~= nil
local lastHousingWarmupRequest = 0
local pendingRetryCounts = {}

local function IsHousingDataPending(flags)
    -- Treat data as pending only when we have no concrete signals from catalog, tooltip, or dye APIs.
    if not flags then
        return true
    end

    return not (flags.hasCatalogEntry or flags.hasTooltipCounts or flags.hasDyeInfo)
end

-- Expose a narrow test hook so we can assert the pending gate without live API calls.
CaerdonHousingMixin.DebugIsHousingDataPending = function(flags)
    return IsHousingDataPending(flags)
end

local function ParseTooltipCounts(itemLink)
    if not C_TooltipInfo or not itemLink then
        return nil
    end

    local tooltipData = C_TooltipInfo.GetHyperlink(itemLink)
    if not tooltipData or not tooltipData.lines then
        return nil
    end

    local function ToNumber(text)
        if not text then return nil end
        local cleaned = tostring(text):gsub("%D", "")
        return tonumber(cleaned)
    end

    for _, line in ipairs(tooltipData.lines) do
        local text = line.leftText
        if text and text:find("Owned") then -- coarse gate to avoid extra work
            local owned = ToNumber(text:match("Owned:%s*([%d,]+)"))
            local placed = ToNumber(text:match("Placed:%s*([%d,]+)"))
            local stored = ToNumber(text:match("Storage:%s*([%d,]+)")) or ToNumber(text:match("Stored:%s*([%d,]+)"))

            if owned or placed or stored then
                return {
                    owned = owned,
                    placed = placed,
                    stored = stored
                }
            end
        end
    end

    return nil
end

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
        ownedStored = catalogEntryInfo.quantity or 0
        remainingRedeemable = catalogEntryInfo.remainingRedeemable or 0
        placedCount = catalogEntryInfo.numPlaced or 0
        totalOwned = math.max(ownedStored, remainingRedeemable) + placedCount
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
                local q = info.quantity or 0
                local p = info.numPlaced or 0
                local r = info.remainingRedeemable or 0
                local total = math.max(q, r) + p
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
            totalOwned = math.max(ownedStored, remainingRedeemable) + placedCount
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
                ownedStored = fallbackInfo.quantity or 0
                remainingRedeemable = fallbackInfo.remainingRedeemable or remainingRedeemable
                placedCount = fallbackInfo.numPlaced or 0
                totalOwned = math.max(ownedStored, remainingRedeemable) + placedCount
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

    local tooltipOwnedTotal
    local isPending

    if not catalogEntryInfo then
        local tooltipCounts = ParseTooltipCounts(itemLink)
        if tooltipCounts then
            ownedStored = tooltipCounts.stored or ownedStored
            placedCount = tooltipCounts.placed or placedCount
            tooltipOwnedTotal = tooltipCounts.owned
            totalOwned = tooltipCounts.owned or (ownedStored + placedCount) or totalOwned
            showQuantity = true
            isPending = false
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
        -- Decor items frequently report both quantity and remainingRedeemable for the same stack; prefer the larger of the two to avoid double-counting.
        local catalogOwned = placedCount + math.max(ownedStored, remainingRedeemable)
        if tooltipOwnedTotal and tooltipOwnedTotal > 0 then
            totalOwned = math.max(tooltipOwnedTotal, catalogOwned)
        else
            totalOwned = catalogOwned
        end

    end

    local hasTooltipCounts = tooltipOwnedTotal ~= nil
    isPending = IsHousingDataPending({
        hasCatalogEntry = catalogEntryInfo ~= nil,
        hasTooltipCounts = hasTooltipCounts,
        hasDyeInfo = dyeColorID ~= nil
    })

    if totalOwned > 0 then
        isPending = false
    end

    if itemID and not isPending then
        pendingRetryCounts[itemID] = 0
    end

    if isPending then
        local now = GetTime and GetTime() or 0
        local retries = itemID and (pendingRetryCounts[itemID] or 0) or 0
        if (now - lastHousingWarmupRequest) >= 2 or now == 0 then
            if retries >= 6 then
                -- Avoid spinning forever if the API never returns data.
                pendingRetryCounts[itemID or 0] = retries
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

            lastHousingWarmupRequest = now
            pendingRetryCounts[itemID or 0] = retries + 1

            if CaerdonWardrobe and CaerdonWardrobe.WarmHousingData then
                pcall(CaerdonWardrobe.WarmHousingData, CaerdonWardrobe, true)
            elseif C_HousingCatalog and C_HousingCatalog.RequestHousingMarketInfoRefresh then
                pcall(C_HousingCatalog.RequestHousingMarketInfoRefresh)
            end

            if C_Timer and CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
                local delay = math.min(1 + retries * 0.5, 3)
                C_Timer.After(delay, function()
                    CaerdonWardrobe:RefreshItems()
                end)
            end
        end
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
