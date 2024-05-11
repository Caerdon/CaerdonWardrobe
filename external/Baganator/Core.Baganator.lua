local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "Baganator"
local BaganatorMixin = {}

function BaganatorMixin:GetName()
    return addonName
end

local options = {
  fixedStatusPosition = true,
  statusProminentSize = 16,
  -- forceGearSetsAsIcon = false
}

function BaganatorMixin:Init()
  Baganator.API.RegisterCornerWidget("Caerdon Status", "caerdon_wardrobe_status", function(caerdonButton, details)
      local shouldShow = false
  
      local itemButton = caerdonButton:GetParent():GetParent()
      local bag = itemButton:GetBagID()
      local slot = itemButton:GetID()
      if bag and slot then
        local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
        if item then
          shouldShow = true
        end
        CaerdonWardrobe:UpdateButton(itemButton, item, self, { bag = bag, slot = slot }, options)
      else
        local item = CaerdonItem:CreateFromItemLink(details.itemLink)
        if item then
          shouldShow = true
        end
        CaerdonWardrobe:UpdateButton(itemButton, item, self, { locationKey = details.itemLink }, options)
      end
    
      return shouldShow
  end, function(itemButton)
    -- Create Caerdon Button with nil item to create caerdonButton ahead of time for all slots
    CaerdonWardrobe:UpdateButton(itemButton, nil, self, nil, options)
    return itemButton.caerdonButton.mogStatus
  end, {corner = "top_right", priority = 1})

  Baganator.API.RegisterCornerWidget("Caerdon Binding", "caerdon_wardrobe_binding", function(bindsOnText, details)
    local shouldShow = false
  
    local itemButton = bindsOnText:GetParent():GetParent()
    local bag = itemButton:GetBagID()
    local slot = itemButton:GetID()
    if bag and slot then
      local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
      if item then
        shouldShow = true
      end
      CaerdonWardrobe:UpdateButton(itemButton, item, self, { bag = bag, slot = slot }, options)
    else
      local item = CaerdonItem:CreateFromItemLink(details.itemLink)
      if item then
        shouldShow = true
      end
      CaerdonWardrobe:UpdateButton(itemButton, item, self, { locationKey = details.itemLink }, options)
    end
  
    -- if shouldShow and (bindsOnText:GetText() == "" or bindsOnText:GetText() == nil) then
    --   shouldShow = false
    -- end

    -- return shouldShow
    return true
  end, function(itemButton)
    CaerdonWardrobe:UpdateButton(itemButton, nil, self, nil, options)
    return itemButton.caerdonButton.bindsOnText
  end, {corner = "bottom_right", priority = 2})
end

function BaganatorMixin:GetTooltipData(item, locationInfo)
	-- if locationInfo.bag == BANK_CONTAINER then
	-- 	return C_TooltipInfo.GetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
	-- else
	-- 	return C_TooltipInfo.GetBagItem(locationInfo.bag, locationInfo.slot)
	-- end
end

function BaganatorMixin:Refresh()
    if Baganator.API.IsCornerWidgetActive("caerdon_wardrobe_status") or Baganator.API.IsCornerWidgetActive("caerdon_wardrobe_binding") then
      Baganator.API.RequestItemButtonsRefresh()
    end
end

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
	if C_AddOns.IsAddOnLoaded(addonName) then
		Version = C_AddOns.GetAddOnMetadata(addonName, 'Version')
		CaerdonWardrobe:RegisterFeature(BaganatorMixin)
		isActive = true
	end
end

-- WagoAnalytics:Switch(addonName, isActive)
