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

-- Shown in the layout editor (see "Layout editor" in CLAUDE.md).
function VenturePlanMixin:GetLayoutNote()
    return "Venture Plan: the icon and the text keep their own places and sizes on a reward."
end

-- Where this feature attaches to Venture Plan (the integration report; see FeatureMixin.lua).
-- Venture Plan looks the global VPEX_OnUIObjectCreated up by name and calls it for every widget
-- it creates, so there is nothing to find beforehand: its call for a reward frame is the evidence.
VenturePlanMixin.integration = {
	addon = addonName,
	hookPoints = { "VPEX_OnUIObjectCreated for a reward frame" },
}

function VenturePlanMixin:Init()
	local function OnSetReward(...)
		self:UpdateButton(...)
	end
	hookOrAssign(_G, "VPEX_OnUIObjectCreated", function(objectType, widget)
		if objectType == "RewardFrame" or objectType == "InlineRewardFrame" then
			self:NoteHookCalled("VPEX_OnUIObjectCreated for a reward frame")
			hookOrAssign(widget, "OnSetReward", OnSetReward)
		end
	end)
end

-- What this window shows of an item (FeatureMixin.lua, displayRules).
VenturePlanMixin.displayRules = {
	bindingStatus = true,
	ownIcon = true,
	otherIcon = true,
	oldExpansionIcon = false,
	sellableIcon = false,
}

function VenturePlanMixin:UpdateButton(button)
	local options = {
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

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
	if C_AddOns.IsAddOnLoaded(addonName) then
		Version = C_AddOns.GetAddOnMetadata(addonName, "Version")
		CaerdonWardrobe:RegisterFeature(VenturePlanMixin)
        isActive = true
	end
end

-- WagoAnalytics:Switch(addonName, isActive)
