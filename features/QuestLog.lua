local QuestLogMixin = {}

local version, build, date, tocversion = GetBuildInfo()
local isShadowlands = tonumber(build) > 35700

function QuestLogMixin:Init(frame)
	self.frame = frame
end

function QuestLogMixin:OnLoad()
	hooksecurefunc("QuestInfo_Display", function(...) self:OnQuestInfoDisplay(...) end)
end

function QuestLogMixin:SetTooltipItem(tooltip, item, locationInfo)
	if QuestInfoFrame.questLog then
		tooltip:SetQuestLogItem(locationInfo.questItem.type, locationInfo.index, locationInfo.questID)
	else
		tooltip:SetQuestItem(locationInfo.questItem.type, locationInfo.index, locationInfo.questID)
	end
end

function QuestLogMixin:OnQuestInfoDisplay(template, parentFrame)
	local i = 1
	while template.elements[i] do
		if template.elements[i] == QuestInfo_ShowRewards then self:OnQuestInfoShowRewards() return end
		i = i + 3
	end
end

function QuestLogMixin:GetQuestID()
	if ( QuestInfoFrame.questLog ) then
		if (isShadowlands) then
			return C_QuestLog.GetSelectedQuest();
		else
			return select(8, GetQuestLogTitle(GetQuestLogSelection()));
		end
	else
		return GetQuestID();
	end
end

function QuestLogMixin:OnQuestInfoShowRewards()
	local numQuestRewards = 0;
	local numQuestChoices = 0;
	local rewardsFrame = QuestInfoFrame.rewardsFrame;
	local questID = self:GetQuestID()

	if questID == 0 then return end -- quest abandoned

	QuestEventListener:AddCallback(questID, function()
		local options = {
			iconOffset = 0,
			iconSize = 40,
			overridePosition = "TOPLEFT",
			overrideBindingPosition = "TOPLEFT",
			bindingOffsetX = -53,
			bindingOffsetY = -16
		}

		local questLink = GetQuestLink(questID)
		if not questLink then 
			local questName
			if isShadowlands then
				questName = C_QuestLog.GetTitleForQuestID(questID)
			else
				questName = C_QuestLog.GetQuestInfo(questID)
			end
		
			local questLevel = C_QuestLog.GetQuestDifficultyLevel(questID)
			questLink = format("|cff808080|Hquest:%d:%d|h[%s]|h|r", questID, questLevel, questName)
		end

		local item = CaerdonItem:CreateFromItemLink(questLink)
		local itemData = item:GetItemData()
		local questInfo = itemData:GetQuestInfo()

		local choiceCount = #questInfo.choices
		for i = 1, choiceCount do
			local questLogIndex = i
			local reward = questInfo.choices[i]
			local questItem = QuestInfo_GetRewardButton(rewardsFrame, questLogIndex);

			if reward.itemLink then
				CaerdonWardrobe:UpdateButtonLink(reward.itemLink, "QuestLog", { questID = questID, index = questLogIndex, questItem = questItem }, questItem, options)
			elseif reward.itemID then
				-- TODO: Do I need to load the data here first?  Keep an eye out
				local _, itemLink = GetItemInfo(reward.itemID)
				CaerdonWardrobe:UpdateButtonLink(itemLink, "QuestLog", { questID = questID, index = questLogIndex, questItem = questItem }, questItem, options)
			else
				CaerdonWardrobe:ClearButton(questItem)
			end
		end

		for i = 1, #questInfo.rewards do
			local questLogIndex = choiceCount + i
			local reward = questInfo.rewards[i]
			local questItem = QuestInfo_GetRewardButton(rewardsFrame, questLogIndex);

			if reward.itemLink then
				CaerdonWardrobe:UpdateButtonLink(reward.itemLink, "QuestLog", { questID = questID, index = questLogIndex, questItem = questItem }, questItem, options)
			elseif reward.itemID then
				local _, itemLink = GetItemInfo(reward.itemID)
				CaerdonWardrobe:UpdateButtonLink(itemLink, "QuestLog", { questID = questID, index = questLogIndex, questItem = questItem }, questItem, options)
			else
				CaerdonWardrobe:ClearButton(questItem)
			end
		end
	end)
end

CaerdonWardrobe:RegisterFeature("QuestLog", QuestLogMixin)
