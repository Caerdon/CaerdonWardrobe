local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "ElvUI"
local ElvUIMixin = {}

function ElvUIMixin:GetName()
    return addonName
end

function ElvUIMixin:Init()
    self.ElvUIBags = ElvUI[1]:GetModule("Bags")
    hooksecurefunc(self.ElvUIBags, "UpdateSlot", function(...) self:OnUpdateSlot(...) end)
end

function ElvUIMixin:GetTooltipData(item, locationInfo)
    if locationInfo.isOffline then
        if not item:IsItemEmpty() then
            return C_TooltipInfo.GetHyperlink(item:GetItemLink())
        end
    elseif locationInfo.bag == BANK_CONTAINER then
        return C_TooltipInfo.GetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
    else
        return C_TooltipInfo.GetBagItem(locationInfo.bag, locationInfo.slot)
    end
end

function ElvUIMixin:Refresh()
    self.ElvUIBags:UpdateAllBagSlots()
end

function ElvUIMixin:OnUpdateSlot(ee, frame, bagID, slotID)
    if C_Container and C_Container.GetContainerNumSlots then
        if (frame.Bags[bagID] and frame.Bags[bagID].numSlots ~= C_Container.GetContainerNumSlots(bagID)) or not frame.Bags[bagID] or not frame.Bags[bagID][slotID] then
            return
        end
    else
        if (frame.Bags[bagID] and frame.Bags[bagID].numSlots ~= GetContainerNumSlots(bagID)) or not frame.Bags[bagID] or not frame.Bags[bagID][slotID] then
            return
        end
    end

    local button = frame.Bags[bagID][slotID]
    local bagType = frame.Bags[bagID].type

    -- local uiScale = ElvUI[1].global.general.UIScale
    local isBank = bagID == BANK_CONTAINER or (bagID > NUM_BAG_SLOTS)
    local iconSize = ((isBank and self.ElvUIBags.db.bankSize) or (self.ElvUIBags.db.bagSize)) * 0.5
    local bindingScale = iconSize / 17 -- made things look decent at size 34 so use that as base

    local hasCount
    local numberFontSize = 0

    if button.Count and button.Count:GetText() then
        hasCount = true
        numberFontSize = ElvUI[1].db.bags.countFontSize
    elseif button.itemLevel and button.itemLevel:GetText() then
        hasCount = true
        numberFontSize = ElvUI[1].db.bags.itemLevelFontSize
    end

    local item = CaerdonItem:CreateFromBagAndSlot(bagID, slotID)
    CaerdonWardrobe:UpdateButton(button, item, self, {
        bag = bagID,
        slot = slotID,
    }, {
        hasCount = hasCount,
        relativeFrame = button.icon,
        statusProminentSize = iconSize,
        bindingScale = bindingScale,
        itemCountOffset = (12 * (numberFontSize / 14)) / bindingScale
    })
end

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
    if C_AddOns.IsAddOnLoaded(addonName) then
        if ElvUI[1].private.bags.enable then
            Version = C_AddOns.GetAddOnMetadata(addonName, 'Version')
            CaerdonWardrobe:RegisterFeature(ElvUIMixin)
            isActive = true
        end
    end
end

-- WagoAnalytics:Switch(addonName, isActive)
