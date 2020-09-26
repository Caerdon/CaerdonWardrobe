local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "Inventorian"
local InventorianMixin = {}

function InventorianMixin:GetName()
    return addonName
end

function InventorianMixin:Init()
	self.Inventorian = LibStub('AceAddon-3.0'):GetAddon('Inventorian')
	self.mod = self.Inventorian:NewModule("CaerdonWardrobeInventorianUpdate")
	self.mod.uiName = L["Caerdon Wardrobe Inventorian"]
	self.mod.uiDesc= L["Identifies transmog appearances that still need to be learned"]

	self.mod.OnEnable = function(mod)
		hooksecurefunc(self.Inventorian.bag.itemContainer, "UpdateSlot", function(...) self:UpdateBagSlot(...) end)
		hooksecurefunc(self.Inventorian.bank.itemContainer, "UpdateSlot", function(...) self:UpdateBankSlot(...) end)
	end
end

function InventorianMixin:SetTooltipItem(tooltip, item, locationInfo)
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

function InventorianMixin:Refresh()
	-- TODO: Was missing
end

local function ToIndex(bag, slot)
	return (bag < 0 and bag * 100 - slot) or (bag * 100 + slot)
end

function InventorianMixin:UpdateBagSlot(event, bag, slot)
	local button = self.Inventorian.bag.itemContainer.items[ToIndex(bag, slot)]
	self:UpdateSlot(button, bag, slot)
end

function InventorianMixin:UpdateBankSlot(event, bag, slot)
	local button = self.Inventorian.bank.itemContainer.items[ToIndex(bag, slot)]
	self:UpdateSlot(button, bag, slot)
end

function InventorianMixin:UpdateSlot(button, bag, slot)
	if button then
		local icon, count, locked, quality, readable, lootable, itemLink, noValue, itemID = button:GetInfo()
		if itemLink then
			local options = {
				showMogIcon=true, 
				showBindStatus=true,
				showSellables=true,
				iconPosition="TOPRIGHT" 
			}

			local item = CaerdonItem:CreateFromItemLink(itemLink)
			if button:IsCached() then
				CaerdonWardrobe:UpdateButton(button, item, self, { isOffline = true }, options)
			else
				CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot, isBankOrBags = true }, options)
			end
		else
			CaerdonWardrobe:ClearButton(button)
		end
	end
end

local Version = nil
if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		Version = GetAddOnMetadata(addonName, 'Version')
		CaerdonWardrobe:RegisterFeature(InventorianMixin)
	end
end
