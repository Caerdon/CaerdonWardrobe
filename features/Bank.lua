local BankMixin = {}
-- local isWarWithin = select(4, GetBuildInfo()) >= 110000

function BankMixin:GetName()
    return "Bank"
end

function BankMixin:Init()
    hooksecurefunc(BankPanelItemButtonMixin, "Refresh", function(...) self:OnBankButtonRefresh(...) end)
    hooksecurefunc(BankPanel, "UpdateSearchResults", function(...) self:OnUpdateSearchResults(...) end)
    hooksecurefunc(BankPanel, "RefreshBankPanel", function(...) self:Refresh(...) end)

    return {}
end

function BankMixin:GetTooltipData(item, locationInfo)
    return C_TooltipInfo.GetBagItem(locationInfo.bag, locationInfo.slot)
end

function BankMixin:Refresh()
    CaerdonWardrobeFeatureMixin:Refresh(self)
    local noTabSelected = BankPanel.selectedTabID == nil;
    if noTabSelected then
        return;
    end

    for button in BankPanel:EnumerateValidItems() do
        self:OnBankButtonRefresh(button)
    end
end

function BankMixin:OnUpdateSearchResults(frame)
    for itemButton in frame:EnumerateValidItems() do
        local itemInfo = C_Container.GetContainerItemInfo(itemButton:GetBankTabID(), itemButton:GetContainerSlotID());
        local isFiltered = itemInfo and itemInfo.isFiltered;
        CaerdonWardrobe:SetItemButtonMogStatusFilter(itemButton, isFiltered)
    end
end

function BankMixin:OnBankButtonRefresh(button)
    local itemInfo = button.itemInfo
    if not itemInfo then
        CaerdonWardrobe:ClearButton(button)
        return
    end
    local bag = button:GetBankTabID();
    local slot = button:GetContainerSlotID();
    local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
    CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot },
        { relativeFrame = button.icon, isFiltered = itemInfo and itemInfo.isFiltered })
end

CaerdonWardrobe:RegisterFeature(BankMixin)
