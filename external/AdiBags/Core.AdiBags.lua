local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "AdiBags"
local AdiBagsMixin = {}

function AdiBagsMixin:GetName()
    return addonName
end

function AdiBagsMixin:Init()
	local AdiBags = LibStub('AceAddon-3.0'):GetAddon('AdiBags')
	self.mod = AdiBags:NewModule("CaerdonWardrobeAdiBagsUpdate", "ABEvent-1.0")
	self.mod.uiName = L["Caerdon Wardrobe"]
	self.mod.uiDesc= L["Identifies transmog appearances that still need to be learned"]

	self.mod.OnEnable = function(mod)
		mod:RegisterMessage('AdiBags_UpdateButton', 'UpdateButton')
	end

	self.mod.UpdateButton = function(mod, event, button)
		local itemLink = button.itemLink
		local bag = button.bag
		local slot = button.slot

		local options = {
			showMogIcon=true, 
			showBindStatus=true,
			showSellables=true,
			iconPosition="TOPRIGHT" 
		}

		CaerdonWardrobe:UpdateButtonLink(button, itemLink, self:GetName(), { bag = bag, slot = slot, isBankOrBags = true }, options)
	end
end

function AdiBagsMixin:SetTooltipItem(tooltip, item, locationInfo)
	if locationInfo.bag == BANK_CONTAINER then
		local hasItem, hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
	else
		local hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetBagItem(locationInfo.bag, locationInfo.slot)
	end
end

function AdiBagsMixin:Refresh()
	self.mod:SendMessage('AdiBags_FiltersChanged')
end

local Version = nil
if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		Version = GetAddOnMetadata(addonName, 'Version')
		CaerdonWardrobe:RegisterFeature(AdiBagsMixin)
	end
end
