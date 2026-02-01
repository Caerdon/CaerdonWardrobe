local MerchantMixin = {}

function MerchantMixin:GetName()
    return "Merchant"
end

function MerchantMixin:Init()
    hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function(...) self:OnMerchantUpdate(...) end)
    hooksecurefunc("MerchantFrame_UpdateBuybackInfo", function(...) self:OnBuybackUpdate(...) end)

    -- Check if Legion Remix Helper's filtering is enabled on load
    self.legionRemixHelperFilteringEnabled = false
    self.legionRemixHelperWarningShown = false
    if C_AddOns.IsAddOnLoaded("LegionRemixHelper") then
        -- Check their saved variable
        if LegionRemixHelperDB and LegionRemixHelperDB.merchant and LegionRemixHelperDB.merchant.hideCollectedItems then
            self.legionRemixHelperFilteringEnabled = true
        end
    end

    -- Store processed items for filtering
    self.merchantItems = {}

    self.bagCacheDirty = true

    return { "MERCHANT_UPDATE", "TOOLTIP_DATA_UPDATE", "BAG_UPDATE_DELAYED" }
end

function MerchantMixin:MERCHANT_UPDATE()
    self:Refresh()
end

function MerchantMixin:TOOLTIP_DATA_UPDATE()
    if not MerchantFrame:IsShown() then
        return
    end

    if self.refreshTimer then
        self.refreshTimer:Cancel()
    end

    self.refreshTimer = C_Timer.NewTimer(0.5, function()
        self:Refresh()
    end, 1)
end

function MerchantMixin:BAG_UPDATE_DELAYED()
    self.bagCacheDirty = true

    if MerchantFrame:IsShown() then
        self:Refresh()
    end
end

function MerchantMixin:GetTrackedBagIDs()
    local bagIDs = { BACKPACK_CONTAINER }
    local numBags = NUM_BAG_SLOTS or 4

    for bagIndex = 1, numBags do
        table.insert(bagIDs, bagIndex)
    end

    if REAGENTBAG_CONTAINER then
        table.insert(bagIDs, REAGENTBAG_CONTAINER)
    elseif Enum and Enum.BagIndex and Enum.BagIndex.Reagentbag then
        table.insert(bagIDs, Enum.BagIndex.Reagentbag)
    end

    return bagIDs
end

function MerchantMixin:RefreshBagCache()
    if not self.bagCacheDirty then
        return
    end

    self.bagCacheDirty = false
    self.bagItemIDs = wipe(self.bagItemIDs or {})

    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
        return
    end

    for _, bagID in ipairs(self:GetTrackedBagIDs()) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)

        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local containerItemInfo = C_Container.GetContainerItemInfo(bagID, slot)
                if containerItemInfo and containerItemInfo.itemID then
                    self.bagItemIDs[containerItemInfo.itemID] = true
                end
            end
        end
    end
end

function MerchantMixin:IsItemInBags(item)
    if not item then
        return false
    end

    self:RefreshBagCache()

    local itemID = item:GetItemID()
    if not itemID or not self.bagItemIDs then
        return false
    end

    return self.bagItemIDs[itemID] == true
end

function MerchantMixin:GetTooltipData(item, locationInfo)
    if MerchantFrame.selectedTab == 1 then
        if locationInfo.slot == "buybackbutton" then
            return C_TooltipInfo.GetBuybackItem(GetNumBuybackItems())
        else
            return C_TooltipInfo.GetMerchantItem(locationInfo.slot)
        end
    else
        return C_TooltipInfo.GetBuybackItem(locationInfo.slot)
    end
end

function MerchantMixin:SetTooltipItem(tooltip, item, locationInfo)
    if MerchantFrame.selectedTab == 1 then
        if locationInfo.slot == "buybackbutton" then
            tooltip:SetBuybackItem(GetNumBuybackItems())
        else
            tooltip:SetMerchantItem(locationInfo.slot)
        end
    else
        tooltip:SetBuybackItem(locationInfo.slot)
    end
end

function MerchantMixin:Refresh()
    self:RefreshBagCache()
    CaerdonWardrobeFeatureMixin:Refresh(self)
    if MerchantFrame:IsShown() then
        if MerchantFrame.selectedTab == 1 then
            self:OnMerchantUpdate()
        else
            self:OnBuybackUpdate()
        end
    end
end

function MerchantMixin:GetDisplayInfo(button, item)
    local hasBagCopy = self:IsItemInBags(item)

    return {
        bindingStatus = {
            shouldShow = CaerdonWardrobeConfig.Binding.ShowStatus.Merchant
        },
        ownIcon = {
            shouldShow = CaerdonWardrobeConfig.Icon.ShowLearnable.Merchant and not hasBagCopy
        },
        otherIcon = {
            shouldShow = CaerdonWardrobeConfig.Icon.ShowLearnableByOther.Merchant and not hasBagCopy
        },
        oldExpansionIcon = {
            shouldShow = false
        },
        sellableIcon = {
            shouldShow = false
        }
    }
end

function MerchantMixin:ShowLegionRemixHelperWarning()
    -- Check if user has suppressed the warning
    local suppressWarning = CaerdonWardrobeConfig and
        CaerdonWardrobeConfig.Merchant and
        CaerdonWardrobeConfig.Merchant.Filter and
        CaerdonWardrobeConfig.Merchant.Filter.SuppressLegionRemixHelperWarning

    if self.legionRemixHelperWarningShown or suppressWarning then
        return
    end

    self.legionRemixHelperWarningShown = true

    StaticPopupDialogs["CAERDON_LEGION_REMIX_HELPER_WARNING"] = {
        text = "CaerdonWardrobe has detected that Legion Remix Helper's merchant filtering is enabled.\n\n" ..
            "We recommend disabling Legion Remix Helper's 'Hide Collected Items' setting and using CaerdonWardrobe's " ..
            "'Gray out collected/known items' feature instead, as it has better detection for learnable items.\n\n" ..
            "IMPORTANT: YOU WILL MISS ITEMS THAT ARE NOT IN YOUR COLLECTION WITH LEGION REMIX HELPER'S FILTERING.\n\n" ..
            "CaerdonWardrobe's filtering has been disabled to avoid conflicts.\n\n" ..
            "You can suppress this warning in CaerdonWardrobe's Merchant settings.",
        button1 = "OK",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("CAERDON_LEGION_REMIX_HELPER_WARNING")
end

function MerchantMixin:ShouldFilterItems()
    -- Check if Legion Remix Helper's filtering is enabled (checked on load)
    if self.legionRemixHelperFilteringEnabled then
        self:ShowLegionRemixHelperWarning()
        return false -- Disable our filtering to avoid conflicts
    end

    -- Check if filtering is enabled in config (with safe navigation)
    local merchantConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Merchant
    if not merchantConfig then
        return false
    end

    local filterConfig = merchantConfig.Filter
    if not filterConfig then
        return false
    end

    return filterConfig.HideCollected == true
end

function MerchantMixin:IsItemCollected(item)
    if not item then
        return false
    end

    -- Get the item's Caerdon status (this is what your addon calculates)
    local isReady, mogStatus, bindingStatus, bindingResult = item:GetCaerdonStatus(self, {})

    if not isReady then
        -- Item isn't ready yet, don't hide it
        return false
    end

    local caerdonType = item:GetCaerdonItemType()

    -- Handle different item types differently
    if caerdonType == "Equipment" then
        -- Equipment: gray out if collected or sellable
        if mogStatus == "collected" or mogStatus == "sellable" then
            return true
        end
    elseif caerdonType == "Mount" or caerdonType == "BattlePet" then
        -- Mounts/BattlePets: gray out if collected or no status (empty means already have it)
        if mogStatus == "collected" or mogStatus == "" then
            return true
        end
    elseif caerdonType == "Companion Pet" then
        -- Companion Pets: Check if we have the maximum allowed
        local itemData = item:GetItemData()
        if itemData then
            local petInfo = itemData:GetCompanionPetInfo()
            if petInfo and petInfo.numCollected and petInfo.limit then
                if petInfo.numCollected >= petInfo.limit then
                    return true
                end
            end
        end
        return false
    elseif caerdonType == "Toy" then
        -- Toys: gray out if sellable (already owned) or collected
        -- Don't gray out if showing "own" (learnable)
        if mogStatus == "sellable" or mogStatus == "collected" then
            return true
        end
        return false
    elseif caerdonType == "Consumable" then
        -- Consumables include: ensembles (transmog sets), toys, food, potions, quest items, etc.
        -- Only gray out if it's an ensemble (has a transmog set) that's already fully collected
        -- Don't gray out regular consumables, quest items, or food/potions

        -- Don't gray out items with learnable status
        if mogStatus == "own" or mogStatus == "ownPlus" or mogStatus == "other" or mogStatus == "otherPlus"
            or mogStatus == "lowSkill" or mogStatus == "lowSkillPlus" or mogStatus == "otherNoLoot" then
            return false
        end

        -- Check consumable info to see if it's an ensemble
        local itemData = item:GetItemData()
        if itemData and itemData.GetConsumableInfo then
            local consumableInfo = itemData:GetConsumableInfo()
            if consumableInfo and consumableInfo.isEnsemble and consumableInfo.needsItem == false then
                -- Ensemble is fully collected
                return true
            end
        end
        -- Not an ensemble, or still has items to collect
        return false
    end

    -- For any other types or statuses, don't gray out
    return false
end

function MerchantMixin:IsAnotherAddonFiltering()
    -- Better detection: check if visible buttons have non-sequential IDs or gaps
    local visibleButtons = {}

    for i = 1, MERCHANT_ITEMS_PER_PAGE do
        local button = _G["MerchantItem" .. i .. "ItemButton"]
        if button and button:IsShown() then
            table.insert(visibleButtons, { slot = i, id = button:GetID() })
        end
    end

    -- If no buttons are visible, can't determine
    if #visibleButtons == 0 then
        return false
    end

    -- Check for non-sequential button IDs (indicating remapping)
    for i = 2, #visibleButtons do
        local prevID = visibleButtons[i - 1].id
        local currentID = visibleButtons[i].id

        -- If IDs aren't sequential, another addon is remapping
        if currentID ~= prevID + 1 then
            return true
        end
    end

    -- Also check: if there are hidden buttons between visible ones, likely filtered
    local firstVisibleSlot = visibleButtons[1].slot
    local lastVisibleSlot = visibleButtons[#visibleButtons].slot

    if lastVisibleSlot - firstVisibleSlot + 1 ~= #visibleButtons then
        -- There are gaps in visible buttons, likely another addon is filtering
        return true
    end

    return false
end

function MerchantMixin:OnMerchantUpdate()
    self:ProcessMerchantButtons()
end

function MerchantMixin:ApplySimpleFiltering()
    -- Gray out and fade collected items instead of hiding them
    -- Use the already-processed CaerdonItem objects
    for i, itemInfo in pairs(self.merchantItems) do
        local merchantItem = _G["MerchantItem" .. i]
        local itemButton = _G["MerchantItem" .. i .. "ItemButton"]
        local itemName = _G["MerchantItem" .. i .. "Name"]
        local item = itemInfo.item

        if merchantItem and itemButton and item then
            local isCollected = self:IsItemCollected(item)

            if isCollected then
                -- Gray out and fade the item
                merchantItem:SetAlpha(0.4)
                SetItemButtonDesaturated(itemButton, true)
                SetItemButtonTextureVertexColor(itemButton, 0.5, 0.5, 0.5)
                if itemName then
                    itemName:SetTextColor(0.5, 0.5, 0.5)
                end
            else
                -- Reset to normal appearance
                merchantItem:SetAlpha(1.0)
                SetItemButtonDesaturated(itemButton, false)
                SetItemButtonTextureVertexColor(itemButton, 1.0, 1.0, 1.0)
                if itemName then
                    itemName:SetTextColor(1.0, 0.82, 0) -- Normal gold color
                end
            end
        end
    end
end

function MerchantMixin:ProcessMerchantButtons()
    local options = {}

    -- Clear merchant items table for this update
    self.merchantItems = {}

    for i = 1, MERCHANT_ITEMS_PER_PAGE, 1 do
        local button = _G["MerchantItem" .. i .. "ItemButton"]

        -- When Legion Remix Helper is active, use the button's actual ID instead of calculating index
        -- This handles their dynamic item filtering and remapping
        local slot
        local itemLink

        if self.legionRemixHelperFilteringEnabled and button:IsShown() then
            -- Legion Remix Helper sets the button's ID to the actual merchant index
            slot = button:GetID()
            itemLink = button.link or GetMerchantItemLink(slot)
        else
            -- Normal behavior: calculate index from page and position
            local index = (((MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE) + i)
            slot = index
            itemLink = GetMerchantItemLink(index)
        end

        if itemLink and button:IsShown() then
            local item = CaerdonItem:CreateFromItemLink(itemLink)

            -- Store the item for filtering
            self.merchantItems[i] = {
                button = button,
                item = item,
                slot = i
            }

            CaerdonWardrobe:UpdateButton(button, item, self, {
                locationKey = format("merchantitem-%d", slot),
                slot = slot
            }, options)
        else
            CaerdonWardrobe:ClearButton(button)
        end
    end

    -- Apply filtering using the stored CaerdonItem objects
    -- Check multiple times to catch items as they finish processing
    if self:ShouldFilterItems() and not self:IsAnotherAddonFiltering() then
        -- Initial check
        self:ApplySimpleFiltering()

        -- Retry a few times as items process
        C_Timer.After(0.1, function() if MerchantFrame:IsShown() then self:ApplySimpleFiltering() end end)
        C_Timer.After(0.3, function() if MerchantFrame:IsShown() then self:ApplySimpleFiltering() end end)
        C_Timer.After(0.6, function() if MerchantFrame:IsShown() then self:ApplySimpleFiltering() end end)
    end

    local numBuybackItems = GetNumBuybackItems()
    local buybackName, buybackTexture, buybackPrice, buybackQuantity, buybackNumAvailable, buybackIsUsable =
        GetBuybackItemInfo(numBuybackItems)
    if buybackName then
        local itemLink = GetBuybackItemLink(numBuybackItems)
        local slot = "buybackbutton"
        if itemLink then
            local item = CaerdonItem:CreateFromItemLink(itemLink)
            CaerdonWardrobe:UpdateButton(MerchantBuyBackItemItemButton, item, self, {
                locationKey = format("buybackbutton"),
                slot = slot
            }, options)
        else
            CaerdonWardrobe:ClearButton(MerchantBuyBackItemItemButton)
        end
    else
        CaerdonWardrobe:ClearButton(MerchantBuyBackItemItemButton)
    end
end

function MerchantMixin:OnBuybackUpdate()
    local numBuybackItems = GetNumBuybackItems();

    for index = 1, BUYBACK_ITEMS_PER_PAGE, 1 do -- Only 1 actual page for buyback right now
        if index <= numBuybackItems then
            local button = _G["MerchantItem" .. index .. "ItemButton"];

            local slot = index

            local itemLink = GetBuybackItemLink(index)
            if itemLink then
                local item = CaerdonItem:CreateFromItemLink(itemLink)
                CaerdonWardrobe:UpdateButton(button, item, self, {
                    locationKey = format("buybackitem-%d", slot),
                    slot = slot
                }, {})
            else
                CaerdonWardrobe:ClearButton(button)
            end
        end
    end
end

CaerdonWardrobe:RegisterFeature(MerchantMixin)
