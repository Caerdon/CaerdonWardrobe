local ADDON_NAME, namespace = ...
local L = namespace.L

-- NDui's bag module is a cargBags implementation with the same shape as
-- KkthnxUI's: a single "NDui_Backpack" implementation created in the Bags
-- module's OnLogin (PLAYER_LOGIN) that holds the bag, bank, and warband
-- containers. NDui exposes its namespace as _G.NDui with [1] = B (API),
-- [2] = C (config), and .cargBags.
local cargBags = nil
local addonName = "NDui"
local NDuiMixin = {}

function NDuiMixin:GetName()
	return addonName
end

function NDuiMixin:Init()
	return {"PLAYER_LOGIN"}
end

function NDuiMixin:PLAYER_LOGIN()
	-- The implementation only exists if NDui's Bags module is enabled.
	local impl = cargBags:GetImplementation("NDui_Backpack")
	if impl then
		hooksecurefunc(impl, "UpdateSlot", function(...) self:UpdateSlot(...) end)
	end
end

function NDuiMixin:GetTooltipData(item, locationInfo)
	if locationInfo.bag == BANK_CONTAINER then
		return C_TooltipInfo.GetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
	else
		return C_TooltipInfo.GetBagItem(locationInfo.bag, locationInfo.slot)
	end
end

function NDuiMixin:Refresh()
	local bags = NDui[1].GetModule and NDui[1]:GetModule("Bags")
	if bags and bags.UpdateAllBags then
		bags:UpdateAllBags()
	end
end

function NDuiMixin:UpdateSlot(frame, bagID, slotID)
	local button = frame:GetButton(bagID, slotID)
	if not button then
		return
	end

	local db = NDui[2].db
	local iconSize = (db and db["Bags"] and db["Bags"]["IconSize"] or 34) * 0.6
	local options = {
		statusProminentSize = iconSize,
	}

	local item = CaerdonItem:CreateFromBagAndSlot(bagID, slotID)
	CaerdonWardrobe:UpdateButton(button, item, self, {bag = bagID, slot = slotID}, options)
end

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
	if C_AddOns.IsAddOnLoaded(addonName) then
		local global = _G[addonName]
		if global then
			cargBags = global.cargBags
		end

		Version = C_AddOns.GetAddOnMetadata(addonName, "Version")
		if not Version then
			Version = "Unknown"
		end

		if cargBags then
			CaerdonWardrobe:RegisterFeature(NDuiMixin)
			isActive = true
		end
	end
end

-- WagoAnalytics:Switch(addonName, isActive)
