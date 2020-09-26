local ADDON_NAME, namespace = ...
local L = namespace.L
local Version = nil

local addonName = "ElvUI"
local ElvUIMixin = {}

function ElvUIMixin:GetName()
    return addonName
end

function ElvUIMixin:Init()
	self.ElvUIBags = ElvUI[1]:GetModule("Bags")
	hooksecurefunc(self.ElvUIBags, "UpdateSlot", function(...) self:OnUpdateSlot(...) end)
end

function ElvUIMixin:SetTooltipItem(tooltip, item, locationInfo)
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

function ElvUIMixin:Refresh()
	self.ElvUIBags:UpdateAllBagSlots()
end

function ElvUIMixin:OnUpdateSlot(ee, frame, bagID, slotID)
	if (frame.Bags[bagID] and frame.Bags[bagID].numSlots ~= GetContainerNumSlots(bagID)) or not frame.Bags[bagID] or not frame.Bags[bagID][slotID] then
		return
	end

	local button = frame.Bags[bagID][slotID]
	local bagType = frame.Bags[bagID].type

	local itemLink = GetContainerItemLink(bagID, slotID)

	-- local uiScale = ElvUI[1].global.general.UIScale
	local isBank = bagID == BANK_CONTAINER or (bagID > NUM_BAG_SLOTS and bagID <= NUM_BAG_SLOTS + NUM_BANKBAGSLOTS)
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

	if itemLink then
		local item = CaerdonItem:CreateFromItemLink(itemLink)
		CaerdonWardrobe:UpdateButton(button, item, self, { bag = bagID, slot = slotID, isBankOrBags = true }, {
			hasCount = hasCount,
			relativeFrame = button.icon,
			showMogIcon = true,
			showBindStatus = true,
			showSellables = true,
			statusProminentSize = iconSize,
			bindingScale = bindingScale, 
			itemCountOffset = (12 * (numberFontSize / 14))  / bindingScale
		})
	else
		CaerdonWardrobe:ClearButton(button)
	end
end

if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		if ElvUI[1].private.bags.enable then
			Version = GetAddOnMetadata(addonName, 'Version')
			CaerdonWardrobe:RegisterFeature(ElvUIMixin)
		end
	end
end
