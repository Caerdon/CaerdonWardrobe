local ADDON_NAME, namespace = ...
local L = namespace.L

local cargBags = nil
local addonName = "cargBags_Nivaya"
local CargBagsMixin = {}

function CargBagsMixin:GetName()
    return addonName
end

-- Where this feature attaches to cargBags Nivaya (the integration report; see FeatureMixin.lua).
CargBagsMixin.integration = {
	addon = addonName,
	hookPoints = { "cargBags Nivaya.UpdateSlot" },
}

function CargBagsMixin:Init()
	local cbNivaya = cargBags:GetImplementation("Nivaya")
	self:NoteHookPoint("cargBags Nivaya.UpdateSlot", cbNivaya, "UpdateSlot")
	hooksecurefunc(cbNivaya, "UpdateSlot", function(...) self:UpdateSlot(...) end)
end

function CargBagsMixin:GetTooltipData(item, locationInfo)
	return C_TooltipInfo.GetBagItem(locationInfo.bag, locationInfo.slot)
end

function CargBagsMixin:UpdateSlot(frame, bagID, slotID)
	local button = frame:GetButton(bagID, slotID)
	local options = {
	}

	if button then
		local item = CaerdonItem:CreateFromBagAndSlot(bagID, slotID)
		CaerdonWardrobe:UpdateButton(button, item, self, { bag = bagID, slot = slotID }, options)
	end
end

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
	if C_AddOns.IsAddOnLoaded(addonName) then
		local global = C_AddOns.GetAddOnMetadata(addonName, "X-cargBags")
		if global then
			cargBags = _G[global]
		end

		Version = C_AddOns.GetAddOnMetadata(addonName, "Version")
		if not Version then
			Version = "Unknown"
		end
		if cargBags then
			CaerdonWardrobe:RegisterFeature(CargBagsMixin)
			isActive = true
		end
	end
end

-- WagoAnalytics:Switch(addonName, isActive)
