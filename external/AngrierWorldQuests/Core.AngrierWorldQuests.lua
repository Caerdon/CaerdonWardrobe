local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "AngrierWorldQuests"
-- local AngrierWorldQuests = AngrierWorldQuestsAddon
local AngrierWorldQuestsMixin = {}

function AngrierWorldQuestsMixin:GetName()
    return addonName
end

local isHooked = false

function AngrierWorldQuestsMixin:Init()
	-- TODO: Disabling for now until I can figure out how to enumerate the acquired frames successfully.

	-- local addon = _G[addonName]
	-- local questFrame = addon.Modules["QuestFrame"]

	-- hooksecurefunc(questFrame, "Startup", function(...) 
	-- 	if not isHooked then
	-- 		isHooked = true
	-- 		hooksecurefunc("QuestLogQuests_Update", function(...) self:OnQuestLogQuests_Update(...) end)
	-- 	end
	-- end)
end

function AngrierWorldQuestsMixin:GetTooltipData(item, locationInfo)
	return C_TooltipInfo.GetHyperlink(item:GetItemLink())
end

function AngrierWorldQuestsMixin:Refresh()
end

function AngrierWorldQuestsMixin:IsSameItem(button, item, locationInfo)
	-- TODO: Review (if I get this module working)
	-- QuestId will be directly on world map pin but is on the grandparent for the quest log
	local isSame = button.questId == locationInfo.questID or button:GetParent():GetParent().questId == locationInfo.questID
	return isSame
end

function AngrierWorldQuestsMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	return {
		questIcon = {
			shouldShow = true
		},
		oldExpansionIcon = {
			shouldShow = false
		},
        sellableIcon = {
            shouldShow = false
        }
	}
end

function AngrierWorldQuestsMixin:OnQuestLogQuests_Update()
	local headerButton = AngrierWorldQuestsHeader
	local pool = headerButton.titleFramePool

	-- TODO: Figure out how to make this work.  GetNumActive will return a large number of items but EnumerateActive won't iterate through them all.
	-- print("NUM ACTIVE: " .. tostring(pool:GetNumActive()))
	for button in pool:EnumerateActive() do
		if button then
			local title, factionID, capped = C_TaskQuest.GetQuestInfoByQuestID(button.questID)
			-- print("Active: " ..title)

			local questID = button.questID
			local questLink = GetQuestLink(questID)
			if not questLink then 
				local questName = C_QuestLog.GetTitleForQuestID(questID)
				local questLevel = C_QuestLog.GetQuestDifficultyLevel(questID)
				questLink = format("|cff808080|Hquest:%d:%d|h[%s]|h|r", questID, questLevel, questName)
			end

			local questItem = CaerdonItem:CreateFromItemLink(questLink)
			local itemData = questItem:GetItemData()
			if not itemData then
				CaerdonWardrobe:ClearButton(button)
				return
			end

			local bestIndex, bestType = QuestUtils_GetBestQualityItemRewardIndex(questID)

			if not bestType then 
				CaerdonWardrobe:ClearButton(button)
				return
			end

			local itemLink = GetQuestLogItemLink(bestType, bestIndex, questID)
			if not itemLink then
				CaerdonWardrobe:ClearButton(button)
				return
			end

			local item = CaerdonItem:CreateFromItemLink(itemLink)
			CaerdonWardrobe:UpdateButton(button, item, self, { 
				locationKey = format("%d", questID),
				questID = questID,
				questItem
			}, options)
		end
	end
end

local Version = nil
local isActive = false

if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
	    Version = GetAddOnMetadata(addonName, "Version")
		CaerdonWardrobe:RegisterFeature(AngrierWorldQuestsMixin)
		isActive = true
	end
end

WagoAnalytics:Switch(addonName, isActive)
