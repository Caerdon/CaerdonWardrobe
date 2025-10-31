local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "Baganator"
local BaganatorMixin = {}

function BaganatorMixin:GetName()
    return addonName
end

function BaganatorMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
    if not Baganator or not Baganator.API or not Baganator.API.IsCornerWidgetActive then
        return {}
    end

    if not Baganator.API.IsCornerWidgetActive("pawn") then
        return {}
    end

    if not PawnShouldItemLinkHaveUpgradeArrow then
        return {}
    end

    if item and item.GetCaerdonItemType and item:GetCaerdonItemType() == CaerdonItemType.Equipment then
        local itemLink = item:GetItemLink()
        if itemLink and PawnShouldItemLinkHaveUpgradeArrow(itemLink, false) then
            return {
                upgradeIcon = {
                    shouldShow = false
                }
            }
        end
    end

    return {}
end

local options = {
    fixedStatusPosition = true,
    statusProminentSize = 16,
}

function BaganatorMixin:Init()
    Baganator.API.RegisterCornerWidget("Caerdon Status", "caerdon_wardrobe_status", function(caerdonButton, details)
        local shouldShow = false

        local itemButton = caerdonButton:GetParent():GetParent()
        local bag = itemButton:GetBagID()
        local slot = itemButton:GetID()
        if bag and slot then
            local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
            if item then
                shouldShow = true
            end
            CaerdonWardrobe:UpdateButton(itemButton, item, self, { bag = bag, slot = slot }, options)
        else
            local item = CaerdonItem:CreateFromItemLink(details.itemLink)
            if item then
                shouldShow = true
            end
            CaerdonWardrobe:UpdateButton(itemButton, item, self, { locationKey = details.itemLink }, options)
        end

        -- Ideally, we'd only show if we have a status to show, but UpdateButton is running asynchronously, so we can't account for it here.
        -- This keeps the widget hidden on empty slots so the background can clear cleanly.
        return shouldShow
    end, function(itemButton)
        -- Create Caerdon Button with nil item to create caerdonButton ahead of time for all slots
        CaerdonWardrobe:UpdateButton(itemButton, nil, self, nil, options)
        return itemButton.caerdonButton.mogStatus
    end, { corner = "top_right", priority = 1 })

    Baganator.API.RegisterCornerWidget("Caerdon Binding", "caerdon_wardrobe_binding", function(bindsOnText, details)
        local shouldShow = false

        local itemButton = bindsOnText:GetParent():GetParent()
        local bag = itemButton:GetBagID()
        local slot = itemButton:GetID()
        if bag and slot then
            local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
            if item then
                shouldShow = true
            end
            CaerdonWardrobe:UpdateButton(itemButton, item, self, { bag = bag, slot = slot }, options)
        else
            local item = CaerdonItem:CreateFromItemLink(details.itemLink)
            if item then
                shouldShow = true
            end
            CaerdonWardrobe:UpdateButton(itemButton, item, self, { locationKey = details.itemLink }, options)
        end

        -- This keeps the widget hidden on empty slots so the background clears correctly.
        return shouldShow
    end, function(itemButton)
        CaerdonWardrobe:UpdateButton(itemButton, nil, self, nil, options)
        return itemButton.caerdonButton.bindsOnText
    end, { corner = "bottom_left", priority = 2 })
end

function BaganatorMixin:GetTooltipData(item, locationInfo)
    -- if locationInfo.bag == BANK_CONTAINER then
    -- 	return C_TooltipInfo.GetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
    -- else
    -- 	return C_TooltipInfo.GetBagItem(locationInfo.bag, locationInfo.slot)
    -- end
end

function BaganatorMixin:Refresh()
    if Baganator.API.IsCornerWidgetActive("caerdon_wardrobe_status") or Baganator.API.IsCornerWidgetActive("caerdon_wardrobe_binding") then
        Baganator.API.RequestItemButtonsRefresh()
    end
end

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
    if C_AddOns.IsAddOnLoaded(addonName) then
        Version = C_AddOns.GetAddOnMetadata(addonName, 'Version')
        CaerdonWardrobe:RegisterFeature(BaganatorMixin)
        isActive = true
    end
end

-- WagoAnalytics:Switch(addonName, isActive)
