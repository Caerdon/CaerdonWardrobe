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

function InventorianMixin:GetTooltipData(item, locationInfo)
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
		local options = {
		}

		if button:IsCached() then
			if itemLink then
				local item = CaerdonItem:CreateFromItemLink(itemLink)
				CaerdonWardrobe:UpdateButton(button, item, self, {
					locationKey = format("bag%d-slot%d", bag, slot),
					isOffline = true
				}, options)
			else
				CaerdonWardrobe:ClearButton(button)
			end
		else
			local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
			CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot }, options)
		end
	end
end

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
	if C_AddOns.IsAddOnLoaded(addonName) then
		Version = C_AddOns.GetAddOnMetadata(addonName, 'Version')
		CaerdonWardrobe:RegisterFeature(InventorianMixin)
		isActive = true
	end
end

WagoAnalytics:Switch(addonName, isActive)
