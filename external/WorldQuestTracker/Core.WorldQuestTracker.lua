local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "WorldQuestTracker"
local WorldQuestTracker = WorldQuestTrackerAddon
local WorldQuestTrackerMixin = {}

function WorldQuestTrackerMixin:GetName()
    return addonName
end

-- Where this feature attaches to World Quest Tracker (the integration report; see FeatureMixin.lua).
WorldQuestTrackerMixin.integration = {
    addon = addonName,
    hookPoints = { "WorldQuestTrackerAddon.UpdateSquareWidget", "WorldQuestTrackerAddon.SetupWorldQuestButton" },
}

function WorldQuestTrackerMixin:Init()
    self:NoteHookPoint("WorldQuestTrackerAddon.UpdateSquareWidget", WorldQuestTracker, "UpdateSquareWidget")
    self:NoteHookPoint("WorldQuestTrackerAddon.SetupWorldQuestButton", WorldQuestTracker, "SetupWorldQuestButton")
    hooksecurefunc(WorldQuestTracker, "UpdateSquareWidget", function(...) self:OnUpdateWorldWidget(...) end)
    hooksecurefunc(WorldQuestTracker, "SetupWorldQuestButton", function(...) self:OnSetupWorldQuestButton(...) end)
end

function WorldQuestTrackerMixin:IsSameItem(button, item, locationInfo)
	-- QuestId will be directly on world map pin but is on the grandparent for the quest log
	local isSame = button.questId == locationInfo.questID or button:GetParent():GetParent().questId == locationInfo.questID
	return isSame
end

-- What this window shows of an item (FeatureMixin.lua, displayRules).
WorldQuestTrackerMixin.displayRules = {
	bindingStatus = true,
	ownIcon = true,
	otherIcon = true,
	oldExpansionIcon = false,
	sellableIcon = false,
}

function WorldQuestTrackerMixin:OnSetupWorldQuestButton(widget, questData)
    local questID = widget.questID
		if (not questID) then
			CaerdonWardrobe:ClearButton(widget)
			return
		end
	
    local haveQuestData = HaveQuestData (questID)
		local haveQuestRewardData = HaveQuestRewardData (questID)

    if not haveQuestData or not haveQuestRewardData then
        CaerdonWardrobe:ClearButton(widget)
        return
    end

    local itemName, itemTexture, itemLevel, itemQuantity, itemQuality, isUsable, itemID, isArtifact, artifactPower, isStackable, stackAmount, conduitType, borderTexture, borderColor, itemLink = WorldQuestTracker.GetQuestReward_Item (questID)

    if itemLink then
        local options = {
            hasCount = itemQuantity > 0,
            statusProminentSize = 16,
            itemCountOffset = 9
        }
        
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        CaerdonWardrobe:UpdateButton(widget, item, self, {
            locationKey = format("questbutton-%s-index%d", widget:GetName(), itemID),
            questID = questID
        }, options)
    else
        CaerdonWardrobe:ClearButton(widget)
    end
end

function WorldQuestTrackerMixin:OnUpdateWorldWidget(widget, questData, bIsUsingTracker)
	local questID = questData.questID

	local haveQuestData = HaveQuestData (questID)
	local haveQuestRewardData = HaveQuestRewardData (questID)

    if not haveQuestData or not haveQuestRewardData then
        CaerdonWardrobe:ClearButton(widget)
        return
    end

    local itemName, itemTexture, itemLevel, itemQuantity, itemQuality, isUsable, itemID, isArtifact, artifactPower, isStackable, stackAmount, conduitType, borderTexture, borderColor, itemLink = WorldQuestTracker.GetQuestReward_Item (questID)

    if itemLink then
        local options = {
            hasCount = itemQuantity > 0,
            statusProminentSize = 16,
            itemCountOffset = 9
        }
        
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        CaerdonWardrobe:UpdateButton(widget, item, self, {
            locationKey = format("widget-%s-index%d", widget:GetName(), itemID),
            questID = questID
        }, options)
    else
        CaerdonWardrobe:ClearButton(widget)
    end
end

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
	if C_AddOns.IsAddOnLoaded(addonName) then
	    Version = C_AddOns.GetAddOnMetadata(addonName, "Version")
		CaerdonWardrobe:RegisterFeature(WorldQuestTrackerMixin)
		isActive = true
	end
end

-- WagoAnalytics:Switch(addonName, isActive)
