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

function BaudBagMixin:ProcessItem(bagId, slotId, button)
    if bagId and slotId then
        if BaudBag.Cache:UsesCache(bagId) then
            local bagCache = BaudBag.Cache:GetBagCache(bagId)
            local slotCache = bagCache[slotId]
            if slotCache then
                local item = CaerdonItem:CreateFromItemLink(slotCache.Link)
                CaerdonWardrobe:UpdateButton(button, item, self, { isOffline=true, isBankOrBags = false }, options)
            else
                CaerdonWardrobe:ClearButton(button)
            end
        else
            local itemLink = GetContainerItemLink(bagId, slotId)
            local options = {
                showMogIcon=true,
                showBindStatus=true,
                showSellables=true
            }

            if itemLink then
                local item = CaerdonItem:CreateFromItemLink(itemLink)
                CaerdonWardrobe:UpdateButton(button, item, self, { bag = bagId, slot = slotId, isBankOrBags = true }, options)
            else
                CaerdonWardrobe:ClearButton(button)
            end
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
