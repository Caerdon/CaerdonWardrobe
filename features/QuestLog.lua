local QuestLogMixin = {}

local isDragonflight = select(4, GetBuildInfo()) > 100000

function QuestLogMixin:GetName()
	return "QuestLog"
end

function QuestLogMixin:Init()
	hooksecurefunc("QuestInfo_Display", function(...) self:OnQuestInfoDisplay(...) end)

	if isDragonflight then
		return { "QUEST_ITEM_UPDATE", "QUEST_LOG_UPDATE", "TOOLTIP_DATA_UPDATE" }
	else
		return { "QUEST_ITEM_UPDATE", "QUEST_LOG_UPDATE" }
	end
end

function QuestLogMixin:TOOLTIP_DATA_UPDATE()
	if self.refreshTimer then
		self.refreshTimer:Cancel()
	end

	self.refreshTimer = C_Timer.NewTimer(0.1, function ()
		self:Refresh()
	end, 1)
end

function QuestLogMixin:GetTooltipData(item, locationInfo)
	local currentQuestID = self:GetQuestID()
	local tooltipInfo

	--Make sure it's still the expected quest (usually due to automatic turn-in addons)
	if currentQuestID == 0 or currentQuestID == nil then return end -- quest abandoned
	if currentQuestID ~= locationInfo.questID then return end

	if QuestInfoFrame.questLog then
		return C_TooltipInfo.GetQuestLogItem(locationInfo.type, locationInfo.index, locationInfo.questID)
	else
		return C_TooltipInfo.GetQuestItem(locationInfo.type, locationInfo.index, locationInfo.questID)
	end
end

function QuestLogMixin:Refresh()
	if QuestInfoFrame.rewardsFrame:IsShown() then
		self:OnQuestInfoShowRewards()
	end
end

function QuestLogMixin:QUEST_ITEM_UPDATE()
	self:OnQuestInfoShowRewards()
end

function QuestLogMixin:QUEST_LOG_UPDATE()
	self:OnQuestInfoShowRewards()
end

function QuestLogMixin:OnQuestInfoDisplay(template, parentFrame)
	local i = 1
	while template.elements[i] do
		if template.elements[i] == QuestInfo_ShowRewards then
			self:OnQuestInfoShowRewards()
			return
		end
		i = i + 3
	end
end

function QuestLogMixin:GetQuestID()
	if ( QuestInfoFrame.questLog ) then
		return C_QuestLog.GetSelectedQuest();
	else
		return GetQuestID();
	end
end

function QuestLogMixin:OnQuestInfoShowRewards()
	-- TODO: Need to look at majorFactionRepRewards... probably need to include. (Maybe QuestInfoReputationRewardButtonMixin:SetUpMajorFactionReputationReward?)
	local numQuestRewards = 0;
	local numQuestChoices = 0;
	local rewardsFrame = QuestInfoFrame.rewardsFrame;
	local questID = self:GetQuestID()

	if questID == 0 then return end -- quest abandoned

	QuestEventListener:AddCallback(questID, function()
		local questLink = GetQuestLink(questID)
		if not questLink then
			local questName = C_QuestLog.GetTitleForQuestID(questID)
			local questLevel = C_QuestLog.GetQuestDifficultyLevel(questID)
			questLink = format("|cff808080|Hquest:%d:%d|h[%s]|h|r", questID, questLevel, questName)
		end

		local item = CaerdonItem:CreateFromItemLink(questLink)
		item:ContinueOnItemLoad(function()
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
	end)
end

CaerdonWardrobe:RegisterFeature(QuestLogMixin)
