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

	-- TODO: Add support for separate bank and bag sizes
	-- local iconSize = isBank and self.ElvUIBags.db.bankSize or self.ElvUIBags.db.bagSize
	-- local uiScale = ElvUI[1].global.general.UIScale
	local iconSize = self.ElvUIBags.db.bagSize
	CaerdonWardrobe:UpdateButtonLink(itemLink, self:GetName(), { bag = bagID, slot = slotID, isBankOrBags = true }, button, {
		showMogIcon = true,
		showBindStatus = true,
		showSellables = true,
		iconSize = iconSize,
		otherIconSize = iconSize,
		-- TODO: These aren't correct but hopefully work for now
		iconOffset = math.abs(40 - iconSize) / 2,
		otherIconOffset = math.abs(40 - iconSize) / 2
	})
end

if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		if ElvUI[1].private.bags.enable then
			Version = GetAddOnMetadata(addonName, 'Version')
			CaerdonWardrobe:RegisterFeature(ElvUIMixin)
		end
	end
end
