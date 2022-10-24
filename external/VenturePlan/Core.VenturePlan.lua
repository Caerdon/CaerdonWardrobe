local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "VenturePlan"
local VenturePlanMixin = {}

function VenturePlanMixin:GetName()
    return addonName
end

local function hookOrAssign(t, key, hookFunc)
	if type(t[key]) == "function" then
		hooksecurefunc(t, key, hookFunc)
	else
		t[key] = hookFunc
	end
end

function VenturePlanMixin:Init()
	local function OnSetReward(...)
		self:UpdateButton(...)
	end
	hookOrAssign(_G, "VPEX_OnUIObjectCreated", function(objectType, widget)
		if objectType == "RewardFrame" or objectType == "InlineRewardFrame" then
			hookOrAssign(widget, "OnSetReward", OnSetReward)
		end
	end)
end

function VenturePlanMixin:GetTooltipData(item, locationInfo)
	return C_TooltipInfo.GetHyperlink(item:GetItemLink())
end

function VenturePlanMixin:Refresh()
end

function VenturePlanMixin:UpdateButton(button)
	local options = {
		showMogIcon=true, 
		showBindStatus=true,
		showSellables=true,
        overrideStatusPosition = "TOPRIGHT",
        overrideBindingPosition = "CENTER"
	}

	if button.itemLink then
		local item = CaerdonItem:CreateFromItemLink(button.itemLink)
		CaerdonWardrobe:UpdateButton(button, item, self, { locationKey = tostring(button) }, options)
	elseif button.itemID then
		local item = CaerdonItem:CreateFromItemID(button.itemID)
		CaerdonWardrobe:UpdateButton(button, item, self, { locationKey = tostring(button) }, options)
    else
        CaerdonWardrobe:ClearButton(button)
    end
end

local Version = nil
local isActive = false

if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		Version = GetAddOnMetadata(addonName, "Version")
		CaerdonWardrobe:RegisterFeature(VenturePlanMixin)
        isActive = true
	end
end

WagoAnalytics:Switch(addonName, isActive)
