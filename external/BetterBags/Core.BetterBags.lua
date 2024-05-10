local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "BetterBags"
local BetterBagsMixin = {}

function BetterBagsMixin:GetName()
    return addonName
end

function BetterBagsMixin:Init()
	local BetterBags = LibStub('AceAddon-3.0'):GetAddon('BetterBags')
  local events = BetterBags:GetModule("Events")
  events:RegisterMessage('item/Updated', function (_, bagItem)
    local button = bagItem.button
    local bag = bagItem.data.bagid
    local slot = bagItem.data.slotid
		local options = {
      statusProminentSize = 16,
      statusOffsetX = 7,
      statusOffsetY = 7
		}

		local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
		CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot }, options)
  end)

  -- self.mod = BetterBags:NewModule("CaerdonWardrobeBetterBagsUpdate", "ABEvent-1.0")
	-- self.mod.uiName = L["Caerdon Wardrobe"]
	-- self.mod.uiDesc= L["Identifies transmog appearances that still need to be learned"]

	-- self.mod.OnEnable = function(mod)
	-- 	mod:RegisterMessage('BetterBags_UpdateButton', 'UpdateButton')
	-- end

	-- self.mod.UpdateButton = function(mod, event, button)
	-- 	local bag = button.bag
	-- 	local slot = button.slot

	-- 	local options = {
	-- 	}

	-- 	local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
	-- 	CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot }, options)
	-- end
end

function BetterBagsMixin:GetTooltipData(item, locationInfo)
	if locationInfo.bag == BANK_CONTAINER then
		return C_TooltipInfo.GetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
	else
		return C_TooltipInfo.GetBagItem(locationInfo.bag, locationInfo.slot)
	end
end

function BetterBagsMixin:Refresh()
	-- self.mod:SendMessage('AdiBags_FiltersChanged')
end

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
	if C_AddOns.IsAddOnLoaded(addonName) then
		Version = C_AddOns.GetAddOnMetadata(addonName, 'Version')
		CaerdonWardrobe:RegisterFeature(BetterBagsMixin)
		isActive = true
	end
end

WagoAnalytics:Switch(addonName, isActive)
