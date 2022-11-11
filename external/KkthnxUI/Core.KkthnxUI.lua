local ADDON_NAME, namespace = ...
local L = namespace.L

local cargBags = nil
local addonName = "KkthnxUI"
local CargBagsMixin = {}

function CargBagsMixin:GetName()
	return addonName
end

function CargBagsMixin:Init()
	return {"PLAYER_LOGIN"}
end

function CargBagsMixin:PLAYER_LOGIN()
	local impl = cargBags:GetImplementation("KKUI_Backpack")
	if impl then
		hooksecurefunc(impl, "UpdateSlot", function(...) self:UpdateSlot(...) end)
	end
end

function CargBagsMixin:GetTooltipData(item, locationInfo)
	if locationInfo.bag == BANK_CONTAINER then
		return C_TooltipInfo.GetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
	else
		return C_TooltipInfo.GetBagItem(locationInfo.bag, locationInfo.slot)
	end
end

function CargBagsMixin:Refresh()
	KkthnxUI[1]:GetModule("Bags"):UpdateAllBags()
end

function CargBagsMixin:UpdateSlot(frame, bagID, slotID)
	local iconSize = KkthnxUI[2].Inventory.IconSize * 0.6
	local button = frame:GetButton(bagID, slotID)
	local options = {
		statusProminentSize = iconSize,
	}

	if button then
		local item = CaerdonItem:CreateFromBagAndSlot(bagID, slotID)
		CaerdonWardrobe:UpdateButton(button, item, self, {bag = bagID, slot = slotID}, options)
	end
end

local Version = nil
local isActive = false

if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		local global = _G[addonName]
		if global then
			cargBags = global.cargBags
		end

		Version = GetAddOnMetadata(addonName, "Version")
		if not Version then
			Version = "Unknown"
		end

		if cargBags then
			CaerdonWardrobe:RegisterFeature(CargBagsMixin)
			isActive = true
		end
	end
end

WagoAnalytics:Switch(addonName, isActive)
