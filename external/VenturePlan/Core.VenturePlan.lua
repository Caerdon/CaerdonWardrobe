local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "VenturePlan"
local VenturePlanMixin = {}

function VenturePlanMixin:GetName()
    return addonName
end

function VenturePlanMixin:Init()
    -- Have to expose this from VenturePlan by editing Widgets.lua in VenturePlan right now
    -- so just don't hook up if it's not available.  :(
    if RewardButton_SetReward then
        hooksecurefunc('RewardButton_SetReward', function(...) self:UpdateButton(...) end)
    end
end

function VenturePlanMixin:SetTooltipItem(tooltip, item, locationInfo)
	local itemLink = item:GetItemLink()

	if itemLink then
		tooltip:SetHyperlink(itemLink)
	end
end

function VenturePlanMixin:Refresh()
end

function VenturePlanMixin:UpdateButton(button, rew, isOvermax, pw)
	local options = {
		showMogIcon=true, 
		showBindStatus=true,
		showSellables=true,
        overrideStatusPosition = "TOPRIGHT",
        overrideBindingPosition = "CENTER"
	}

    if rew and rew.itemLink then
        local item = CaerdonItem:CreateFromItemLink(rew.itemLink)
        CaerdonWardrobe:UpdateButton(button, item, self, { reward = rew, locationKey = tostring(button) }, options)
    elseif rew and rew.itemID then
        local item = CaerdonItem:CreateFromItemID(rew.itemID)
        CaerdonWardrobe:UpdateButton(button, item, self, { reward = rew, locationKey = tostring(button) }, options)
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
