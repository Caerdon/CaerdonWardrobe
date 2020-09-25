local ADDON_NAME, namespace = ...
local L = namespace.L

local cargBags = nil
local addonName = "cargBags_Nivaya"
local CargBagsMixin = {}

function CargBagsMixin:GetName()
    return addonName
end

function CargBagsMixin:Init()
	local cbNivaya = cargBags:GetImplementation("Nivaya")
	hooksecurefunc(cbNivaya, "UpdateSlot", function(...) self:UpdateSlot(...) end)
end

function CargBagsMixin:SetTooltipItem(tooltip, item, locationInfo)
	if locationInfo.bag == BANK_CONTAINER then
		local hasItem, hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
	else
		local hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetBagItem(locationInfo.bag, locationInfo.slot)
	end
end

function CargBagsMixin:Refresh()
	-- TODO: This was missing
end

function CargBagsMixin:UpdateSlot(frame, bagID, slotID)
	local itemLink = GetContainerItemLink(bagID, slotID)
	local button = frame:GetButton(bagID, slotID)
	local options = {
		showMogIcon=true, 
		showBindStatus=true,
		showSellables=true,
		iconPosition="TOPRIGHT" 
	}

	if button then
		CaerdonWardrobe:UpdateButtonLink(button, itemLink, self:GetName(), { bag = bagID, slot = slotID, isBankOrBags = true }, options)
	end
end

local Version = nil
if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		local global = GetAddOnMetadata(addonName, "X-cargBags")
		if global then
			cargBags = _G[global]
		end

		Version = GetAddOnMetadata(addonName, "Version")
		if not Version then
			Version = "Unknown"
		end
		if cargBags then
			CaerdonWardrobe:RegisterFeature(CargBagsMixin)
		end
	end
end
