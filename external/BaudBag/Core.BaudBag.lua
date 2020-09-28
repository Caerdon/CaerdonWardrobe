local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "BaudBag"
local BaudBagMixin = {}

function BaudBagMixin:GetName()
    return addonName
end

function BaudBagMixin:Init()
    hooksecurefunc(BaudBag, "ItemSlot_Updated", function(...) self:ItemSlotUpdated(...) end)
end

function BaudBagMixin:SetTooltipItem(tooltip, item, locationInfo)
	if locationInfo.isOffline then
		if not item:IsItemEmpty() then
			tooltip:SetHyperlink(item:GetItemLink())
		end
	elseif locationInfo.bag == BANK_CONTAINER then
		local hasItem, hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
	else
		local hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetBagItem(locationInfo.bag, locationInfo.slot)
	end
end

function BaudBagMixin:Refresh()
    BaudUpdateJoinedBags()
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
                    isOffline=true
                }, options)
            else
                CaerdonWardrobe:ClearButton(button)
            end
        else
            local options = {
                showMogIcon=true,
                showBindStatus=true,
                showSellables=true
            }

            local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
            CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot }, options)
        end
    end
end

function BaudBagMixin:ItemSlotUpdated(bb, bagSet, containerId, subContainerId, slotId, button)
    self:ProcessItem(subContainerId, slotId, button)
end

local Version = nil
if select(4, GetAddOnInfo(addonName)) then
    if IsAddOnLoaded(addonName) then
        Version = GetAddOnMetadata(addonName, "Version")
		CaerdonWardrobe:RegisterFeature(BaudBagMixin)
    end
end
