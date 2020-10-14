local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "LiteBag"
local LiteBagMixin = {}

function LiteBagMixin:GetName()
    return addonName
end

function LiteBagMixin:Init()
    LiteBag_RegisterHook('LiteBagItemButton_Update', function(...) self:UpdateButton(...) end)
    LiteBag_AddUpdateEvent('TRANSMOG_COLLECTION_UPDATED')
end

function LiteBagMixin:SetTooltipItem(tooltip, item, locationInfo)
	if locationInfo.bag == BANK_CONTAINER then
		local hasItem, hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
	else
		local hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetBagItem(locationInfo.bag, locationInfo.slot)
	end
end

function LiteBagMixin:Refresh()
	-- Handled via LiteBagPanel_AddUpdateEvent right now (for transmog at least)
end

function LiteBagMixin:UpdateButton(button)
	local bag = button:GetParent():GetID()
	local slot = button:GetID()

	local options = {
		showMogIcon=true, 
		showBindStatus=true,
		showSellables=true,
		iconPosition="TOPRIGHT" 
	}

	local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
	CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot }, options)
end

local Version = nil
if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		Version = GetAddOnMetadata(addonName, "Version")
		CaerdonWardrobe:RegisterFeature(LiteBagMixin)
	end
end
