local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "BaudBag"
local BaudBagMixin = {}

function BaudBagMixin:GetName()
    return addonName
end

-- Where this feature attaches to BaudBag (the integration report; see FeatureMixin.lua).
BaudBagMixin.integration = {
    addon = addonName,
    hookPoints = { "BaudBag.ItemSlot_Updated" },
}

function BaudBagMixin:Init()
    self:NoteHookPoint("BaudBag.ItemSlot_Updated", BaudBag, "ItemSlot_Updated")
    hooksecurefunc(BaudBag, "ItemSlot_Updated", function(...) self:ItemSlotUpdated(...) end)
end

function BaudBagMixin:GetTooltipData(item, locationInfo)
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

-- The item buttons BaudBag has had drawn, each with the slot it was last drawn for, so Refresh()
-- can draw them again: BaudBag only reports a slot when its content changes, which a newly
-- learned appearance or a gear swap does not do. Weak keys: BaudBag owns the buttons.
local trackedButtons = setmetatable({}, { __mode = "k" })

function BaudBagMixin:Refresh()
    CaerdonWardrobeFeatureMixin:Refresh(self)

    for button, where in pairs(trackedButtons) do
        self:ProcessItem(where.bag, where.slot, button)
    end
end

function BaudBagMixin:ProcessItem(bag, slot, button)
    if bag and slot then
        if BaudBag.Cache:UsesCache(bag) then
            local bagCache = BaudBag.Cache:GetBagCache(bag)
            local slotCache = bagCache[slot]
            if slotCache and slotCache.Link then
                local item = CaerdonItem:CreateFromItemLink(slotCache.Link)
                CaerdonWardrobe:UpdateButton(button, item, self, {
                    locationKey = format("bag%d-slot%d", bag, slot),
                    isOffline = true
                }, options)
            else
                CaerdonWardrobe:ClearButton(button)
            end
        else
            local options = {
            }

            local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
            CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot }, options)
        end
    end
end

function BaudBagMixin:ItemSlotUpdated(bb, bagSet, containerId, subContainerId, slotId, button)
    if button and subContainerId and slotId then
        local where = trackedButtons[button]
        if not where then
            where = {}
            trackedButtons[button] = where
        end
        where.bag, where.slot = subContainerId, slotId
    end
    self:ProcessItem(subContainerId, slotId, button)
end

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
    if C_AddOns.IsAddOnLoaded(addonName) then
        Version = C_AddOns.GetAddOnMetadata(addonName, "Version")
        CaerdonWardrobe:RegisterFeature(BaudBagMixin)
        isActive = true
    end
end

-- WagoAnalytics:Switch(addonName, isActive)
