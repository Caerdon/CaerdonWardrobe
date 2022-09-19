local QuestLogMixin = {}

local version, build, date, tocversion = GetBuildInfo()
local isShadowlands = tonumber(build) > 35700

function QuestLogMixin:GetName()
	return "QuestLog"
end

function QuestLogMixin:Init()
	hooksecurefunc("QuestInfo_Display", function(...) self:OnQuestInfoDisplay(...) end)

	return { "QUEST_ITEM_UPDATE" }
end

function QuestLogMixin:SetTooltipItem(tooltip, item, locationInfo)
	local currentQuestID = self:GetQuestID()

	--Make sure it's still the expected quest (usually due to automatic turn-in addons)
	if currentQuestID == 0 or currentQuestID == nil then return end -- quest abandoned
	if currentQuestID ~= locationInfo.questID then return end

	if QuestInfoFrame.questLog then
		tooltip:SetQuestLogItem(locationInfo.type, locationInfo.index, locationInfo.questID)
	else
		tooltip:SetQuestItem(locationInfo.type, locationInfo.index, locationInfo.questID)
	end
end

function QuestLogMixin:Refresh()
end

function QuestLogMixin:QUEST_ITEM_UPDATE()
	self:OnQuestInfoShowRewards()
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
		if not itemData then
			CaerdonWardrobe:ClearButton(pin)
			return
		end

		local questInfo = itemData:GetQuestInfo()

		local choiceCount = #questInfo.choices
		for i = 1, choiceCount do
			local questLogIndex = i
			local reward = questInfo.choices[i]
			local questItem = QuestInfo_GetRewardButton(rewardsFrame, questLogIndex);

			local options = {
				relativeFrame = questItem.Icon
			}	

			local rewardItem
			if reward.itemLink then
				rewardItem = CaerdonItem:CreateFromItemLink(reward.itemLink)
			end
			-- if reward.itemLink then
			-- 	rewardItem = CaerdonItem:CreateFromItemLink(reward.itemLink)
			-- elseif reward.itemID then
			-- 	rewardItem = CaerdonItem:CreateFromItemID(reward.itemID)
			-- end
			
			if questItem and rewardItem then
				CaerdonWardrobe:UpdateButton(questItem, rewardItem, self, { 
					locationKey = format("%s-index%d", "choice", questLogIndex),
					questID = questID, 
					index = i, 
					type = "choice" 
				}, options)
			else
				CaerdonWardrobe:ClearButton(questItem)
			end
		end

		for i = 1, #questInfo.rewards do
			local questLogIndex = choiceCount + i
			local reward = questInfo.rewards[i]
			local questItem = QuestInfo_GetRewardButton(rewardsFrame, questLogIndex);

			local options = {
				relativeFrame = questItem.Icon
			}	

			local rewardItem
			if reward.itemLink then
				rewardItem = CaerdonItem:CreateFromItemLink(reward.itemLink)
			end
			-- if reward.itemLink then
			-- 	rewardItem = CaerdonItem:CreateFromItemLink(reward.itemLink)
			-- elseif reward.itemID then
			-- 	rewardItem = CaerdonItem:CreateFromItemID(reward.itemID)
			-- end

			if questItem and rewardItem then
				CaerdonWardrobe:UpdateButton(questItem, rewardItem, self, {
					locationKey = format("%s-index%d", "reward", i, questID),
					questID = questID,
					index = i,
					type = "reward"
				}, options)
			else
				CaerdonWardrobe:ClearButton(questItem)
			end
		end

		for i = 1, #questInfo.currencyRewards do
			local questLogIndex = #questInfo.rewards + choiceCount + i
			local reward = questInfo.currencyRewards[i]
			local questItem = QuestInfo_GetRewardButton(rewardsFrame, questLogIndex);

			local options = {
				relativeFrame = questItem.Icon
			}	

			local rewardItem
			if reward.itemLink then
				rewardItem = CaerdonItem:CreateFromItemLink(reward.itemLink)
			end

			-- local name, texture, quality, amount, currencyID;
			-- if ( QuestInfoFrame.questLog ) then
			-- 	name, texture, amount, currencyID, quality = GetQuestLogRewardCurrencyInfo(index, questItem.questID, isChoice);
			-- else
			-- 	name, texture, amount, quality = GetQuestCurrencyInfo(questItem.type, index);
			-- 	currencyID = GetQuestCurrencyID(questItem.type, index);
			-- end
			-- name, texture, amount, quality = CurrencyContainerUtil.GetCurrencyContainerInfo(currencyID, amount, name, texture, quality);

			if questItem and rewardItem then
				CaerdonWardrobe:UpdateButton(questItem, rewardItem, self, {
					locationKey = format("%s-index%d", "currency", i, questID),
					questID = questID,
					index = i,
					type = "currency"
				}, options)
			else
				CaerdonWardrobe:ClearButton(questItem)
			end
		end
	end)
end

CaerdonWardrobe:RegisterFeature(QuestLogMixin)
