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

-- Whether the panel is on screen. Shown is not enough: a bag addon with a bank of its own
-- (BetterBags) moves the bank frame under a hidden parent and still shows the panel while the
-- bank is open, because the client's bank functions ask for that. Its buttons are then filled
-- and refreshed like any others, where nobody sees them, and since such a panel never gets
-- its OnHide it keeps its tab and its buttons after the bank is closed. The panel is asked,
-- not the button: a button is refreshed before it is shown.
local function IsPanelOnScreen()
    return BankPanel:IsVisible()
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
    -- Nothing is drawn or cleared where it cannot be seen. A panel that comes on screen fills
    -- its buttons again (BankPanelMixin:OnShow), which brings every one of them back here.
    if not IsPanelOnScreen() then
        return
    end
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
