local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "Auctionator"
local AuctionatorMixin = {}

function AuctionatorMixin:GetName()
    return addonName
end

function AuctionatorMixin:Init()
  hooksecurefunc(AuctionatorGroupsViewItemMixin, "SetItemInfo", function(...) self:OnSetItemInfo(...) end)
end

function AuctionatorMixin:GetTooltipData(item, locationInfo)
	return C_TooltipInfo.GetHyperlink(item:GetItemLink())
end

function AuctionatorMixin:Refresh()
end

function AuctionatorMixin:OnSetItemInfo(button)
  local options = {
    statusOffsetX = 7,
    statusOffsetY = 7
  }

  local itemInfo = button.itemInfo
  if itemInfo then
    local isSelected = itemInfo.location
    local location = itemInfo.location or itemInfo.locations[1]
    local item = CaerdonItem:CreateFromItemLocation(location)
    CaerdonWardrobe:UpdateButton(button, item, self, { locationKey = itemInfo.sortKey .. tostring(isSelected) }, options)
  else
    CaerdonWardrobe:ClearButton(button)
  end
end

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
	if C_AddOns.IsAddOnLoaded(addonName) then
		Version = C_AddOns.GetAddOnMetadata(addonName, 'Version')
		CaerdonWardrobe:RegisterFeature(AuctionatorMixin)
		isActive = true
	end
end

-- WagoAnalytics:Switch(addonName, isActive)
