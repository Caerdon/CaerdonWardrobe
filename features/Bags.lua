local BagsMixin = {}

function BagsMixin:GetName()
    return "Bags"
end

function BagsMixin:Init()
    for i = 1, NUM_TOTAL_BAG_FRAMES + 1 do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            hooksecurefunc(frame, "UpdateItems", function(...) self:OnUpdateItems(...) end)
            hooksecurefunc(frame, "UpdateSearchResults", function(...) self:OnUpdateSearchResults(...) end)
        end
    end
    hooksecurefunc(ContainerFrameCombinedBags, "UpdateItems", function(...) self:OnUpdateItems(...) end)
    hooksecurefunc(ContainerFrameCombinedBags, "UpdateSearchResults", function(...) self:OnUpdateSearchResults(...) end)

    EventRegistry:RegisterCallback("ContainerFrame.OpenBag", self.BagOpened, self)

    return { "UNIT_SPELLCAST_SUCCEEDED" }
end

function BagsMixin:BagOpened(frame, too)
    for i, button in frame:EnumerateValidItems() do
        CaerdonWardrobe:SetItemButtonMogStatusFilter(button, false)
    end
end

function BagsMixin:UNIT_SPELLCAST_SUCCEEDED(unitTarget, castGUID, spellID)
    if unitTarget == "player" then
        -- Tracking unlock spells to know to refresh
        -- May have to add some other abilities but this is a good place to start.
        if spellID == 1804 then
            C_Timer.After(0.1, function()
                self:Refresh()
            end)
        end
    end
end


function BagsMixin:GetTooltipData(item, locationInfo)
    local tooltipInfo = C_TooltipInfo.GetBagItem(locationInfo.bag, locationInfo.slot)
    return tooltipInfo
end

function BagsMixin:Refresh()
    CaerdonWardrobeFeatureMixin:Refresh(self)
    self.forceFullUpdate = true
    for i = 1, NUM_TOTAL_BAG_FRAMES + 1, 1 do
        local frame = _G["ContainerFrame" .. i]
        if (frame:IsShown()) then
            self:OnUpdateItems(frame)
        end
    end

    if ContainerFrameCombinedBags:IsShown() then
        self:OnUpdateItems(ContainerFrameCombinedBags)
    end
    self.forceFullUpdate = false
end

function BagsMixin:OnUpdateSearchResults(frame)
    for i, button in frame:EnumerateValidItems() do
        local isFiltered

        if C_Container and C_Container.GetContainerItemInfo then
            local itemInfo = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
            if itemInfo then
                isFiltered = itemInfo.isFiltered
            end
        else
            _, _, _, _, _, _, _, isFiltered = GetContainerItemInfo(button:GetBagID(), button:GetID())
        end

        CaerdonWardrobe:SetItemButtonMogStatusFilter(button, isFiltered)
    end
end

function BagsMixin:OnUpdateItems(frame)
    for i, button in frame:EnumerateValidItems() do
        local slot, bag = button:GetSlotAndBagID()
        local shouldUpdate = true

        -- Skip slots whose item hasn't changed since last processing,
        -- unless a full refresh was requested (e.g. transmog collection update).
        -- When the item ID and location key both match, the slot is either
        -- already fully processed or already queued — either way, skip it.
        if not self.forceFullUpdate then
            local itemID = C_Container.GetContainerItemID(bag, slot)
            local cachedID = CaerdonWardrobe:GetButtonItemID(button)
            if itemID == nil and cachedID ~= nil then
                -- Slot was emptied — clear cached state so the item is
                -- properly re-processed if it returns to this slot.
                CaerdonWardrobe:ClearButtonState(button)
            elseif itemID == cachedID and itemID ~= nil then
                local locationKey = format("Bags-bag%d-slot%d", bag, slot)
                if CaerdonWardrobe:GetButtonLocationKey(button) == locationKey then
                    shouldUpdate = false
                end
            end
        end

        if shouldUpdate then
            local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
            CaerdonWardrobe:UpdateButton(button, item, self, {
                bag = bag,
                slot = slot
            }, {
            })
        end
    end
end

CaerdonWardrobe:RegisterFeature(BagsMixin)
