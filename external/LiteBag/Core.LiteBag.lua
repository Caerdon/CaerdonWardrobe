local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "LiteBag"
local LiteBagMixin = {}

function LiteBagMixin:GetName()
    return addonName
end

function LiteBagMixin:Init()
    LiteBag_RegisterHook('LiteBagItemButton_Update', function(...) self:UpdateButton(...) end)
    LiteBag_AddPluginEvent('TRANSMOG_COLLECTION_UPDATED')
end

function LiteBagMixin:GetTooltipData(item, locationInfo)
	if locationInfo.bag == BANK_CONTAINER then
		return C_TooltipInfo.GetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
	else
		return C_TooltipInfo.GetBagItem(locationInfo.bag, locationInfo.slot)
	end
end

function LiteBagMixin:Refresh()
	-- Handled via LiteBagPanel_AddUpdateEvent right now (for transmog at least)
end

function LiteBagMixin:UpdateButton(button)
	local bag = button:GetParent():GetID()
	local slot = button:GetID()

	local options = {
	}

	local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
	CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot }, options)
end

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
	if C_AddOns.IsAddOnLoaded(addonName) then
		Version = C_AddOns.GetAddOnMetadata(addonName, "Version")
		CaerdonWardrobe:RegisterFeature(LiteBagMixin)
		isActive = true
	end
end

-- WagoAnalytics:Switch(addonName, isActive)
