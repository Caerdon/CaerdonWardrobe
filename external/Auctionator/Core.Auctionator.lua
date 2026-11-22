local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "Auctionator"
local AuctionatorMixin = {}

function AuctionatorMixin:GetName()
    return addonName
end

-- Where this feature attaches to Auctionator (the integration report; see FeatureMixin.lua).
AuctionatorMixin.integration = {
  addon = addonName,
  hookPoints = { "AuctionatorGroupsViewItemMixin.SetItemInfo" },
}

function AuctionatorMixin:Init()
  self:NoteHookPoint("AuctionatorGroupsViewItemMixin.SetItemInfo", AuctionatorGroupsViewItemMixin, "SetItemInfo")
  hooksecurefunc(AuctionatorGroupsViewItemMixin, "SetItemInfo", function(...) self:OnSetItemInfo(...) end)
end

function AuctionatorMixin:OnSetItemInfo(button)
  -- The default slot look, sized to the button (42 px in the bag list, 60 px for the item being
  -- sold). The bag list scrolls, so the icon moves inside if the list ever leaves it no room.
  local options = {
    statusProminentSize = CaerdonWardrobe:GetSlotStatusSize(button:GetSize()),
    keepInsideWhenClipped = true
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
