local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "AngrierWorldQuests"
local AngrierWorldQuestsMixin = {}

function AngrierWorldQuestsMixin:GetName()
    return addonName
end

local isHooked = false

-- Where this feature attaches to Angrier World Quests (the integration report; see FeatureMixin.lua).
AngrierWorldQuestsMixin.integration = {
	addon = addonName,
	hookPoints = { "QuestFrameModule.QuestLog_Update" },
}

function AngrierWorldQuestsMixin:Init()
	local questFrame = AngrierWorldQuests:GetModule("QuestFrameModule")
	self:NoteHookPoint("QuestFrameModule.QuestLog_Update", questFrame, "QuestLog_Update")
	hooksecurefunc(questFrame, "QuestLog_Update", function(...) self:OnQuestLog_Update(...) end)
end

function AngrierWorldQuestsMixin:IsSameItem(button, item, locationInfo)
	local isSame = button.questID == locationInfo.questID
	return isSame
end

-- What this window shows of an item (FeatureMixin.lua, displayRules).
AngrierWorldQuestsMixin.displayRules = {
	bindingStatus = true,
	ownIcon = true,
	otherIcon = true,
	sellableIcon = false,
}

function AngrierWorldQuestsMixin:OnQuestLog_Update()
	if self.questTimer then
		self.questTimer:Cancel()
	end

	self.questTimer = C_Timer.NewTimer(0.2, function ()
		local headerButton = AngrierWorldQuestsHeader
		if not headerButton then return end
	
		local pool = headerButton.titleFramePool

		for button in pool:EnumerateActive() do
			local options = {
				fixedLayout = true,
				relativeFrame = button.TagTexture,
				statusProminentSize = 13,
				statusOffsetX = 3,
				statusOffsetY = 3
			}

			local title, factionID, capped = C_TaskQuest.GetQuestInfoByQuestID(button.questID)

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
			else
				local bestIndex, bestType = QuestUtils_GetBestQualityItemRewardIndex(questID)

				if not bestType then 
					CaerdonWardrobe:ClearButton(button)
				else
					local itemLink = GetQuestLogItemLink(bestType, bestIndex, questID)
					if not itemLink then
						CaerdonWardrobe:ClearButton(button)
					else
						local item = CaerdonItem:CreateFromItemLink(itemLink)
						CaerdonWardrobe:UpdateButton(button, item, self, { 
							locationKey = format("quest%d", questID),
							questID = questID,
							questItem
						}, options)
					end
				end
			end
		end
	end, 1)
end

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
	if C_AddOns.IsAddOnLoaded(addonName) then
	    Version = C_AddOns.GetAddOnMetadata(addonName, "Version")
		CaerdonWardrobe:RegisterFeature(AngrierWorldQuestsMixin)
		isActive = true
	end
end

-- WagoAnalytics:Switch(addonName, isActive)
