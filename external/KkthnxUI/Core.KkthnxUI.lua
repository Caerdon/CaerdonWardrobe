local ADDON_NAME, namespace = ...
local L = namespace.L
local Version = nil

local addonName = "KkthnxUI"
local KkthnxUIMixin = {}

function KkthnxUIMixin:GetName()
    return addonName
end

function KkthnxUIMixin:Init()
    return {"PLAYER_LOGIN"}
end

function KkthnxUIMixin:PLAYER_LOGIN()
    local KkthnxUIBags = KkthnxUI[1].cargBags:GetImplementation("KKUI_Backpack")
    if KkthnxUIBags then
        hooksecurefunc(KkthnxUIBags, "UpdateSlot", function(...) self:UpdateSlot(...) end)
    end
end

function KkthnxUIMixin:SetTooltipItem(tooltip, item, locationInfo)
	if locationInfo.bag == BANK_CONTAINER then
		local hasItem, hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
	else
		local hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetBagItem(locationInfo.bag, locationInfo.slot)
	end
end

function KkthnxUIMixin:Refresh()
	KkthnxUI[1]:GetModule("Bags"):UpdateAllBags()
end

function KkthnxUIMixin:UpdateSlot(frame, bagID, slotID)
	local iconSize = KkthnxUI[2].Inventory.IconSize * 0.6
	local button = frame:GetButton(bagID, slotID)
	local options = {
		showMogIcon = true,
		showBindStatus = true,
		showSellables = true,
		iconPosition = "TOPRIGHT",
		statusProminentSize = iconSize,
	}

	if button then
		local item = CaerdonItem:CreateFromBagAndSlot(bagID, slotID)
		CaerdonWardrobe:UpdateButton(button, item, self, {bag = bagID, slot = slotID}, options)
	end
end

if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		if KkthnxUI[2].Inventory.Enable then
			Version = GetAddOnMetadata(addonName, 'Version')
			CaerdonWardrobe:RegisterFeature(KkthnxUIMixin)
		end
	end
end