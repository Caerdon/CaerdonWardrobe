local QuestLogMixin = {}

function QuestLogMixin:GetName()
	return "QuestLog"
end

function QuestLogMixin:Init()
	hooksecurefunc("QuestInfo_Display", function(...) self:OnQuestInfoDisplay(...) end)
	hooksecurefunc("QuestInfo_ShowRewards", function(...) self:OnQuestInfoShowRewards(...) end)

	return { "QUEST_ITEM_UPDATE", "QUEST_LOG_UPDATE", "TOOLTIP_DATA_UPDATE" }
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

function QuestLogMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	return {
		bindingStatus = {
			shouldShow = true
		},
		ownIcon = {
			shouldShow = true
		},
		otherIcon = {
			shouldShow = true
		},
		questIcon = {
			shouldShow = true
		},
		oldExpansionIcon = {
			shouldShow = true
		},
        sellableIcon = {
            shouldShow = false
        }
	}
end

function QuestLogMixin:QUEST_ITEM_UPDATE()
	self:OnQuestInfoShowRewards()
end

function QuestLogMixin:QUEST_LOG_UPDATE()
	-- self:OnQuestInfoShowRewards()
end

function QuestLogMixin:OnQuestInfoDisplay(template, parentFrame)
	-- function getFuncName(funct)
	-- 	for i,v in pairs(getfenv()) do
	-- 		if v == funct then
	-- 			return i
	-- 		end
	-- 	end
	-- end

	-- print("DO THE DISPLAY")
	local elementsTable = template.elements;
	local i = 1
	for i = 1, #elementsTable, 3 do
		-- print(getFuncName(elementsTable[i]))
		if elementsTable[i] == QuestInfo_ShowAccountCompletedNotice then -- can't do because it's blank for some reason: QuestInfo_ShowRewards then
			self:OnQuestInfoShowRewards()
			return
		end
	end

	-- DevTools_Dump(template)
	if template.questLog then
		self:OnQuestInfoShowRewards()
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
	local rewardsFrame = QuestInfoFrame.rewardsFrame;
	local questID = self:GetQuestID()

	if questID == 0 then return end -- quest abandoned

	CaerdonQuestEventListener:AddCallback(questID, function()
		local questLink = GetQuestLink(questID)
		if not questLink then
			local questName = C_QuestLog.GetTitleForQuestID(questID)
			local questLevel = C_QuestLog.GetQuestDifficultyLevel(questID)
			questLink = format("|cff808080|Hquest:%d:%d|h[%s]|h|r", questID, questLevel, questName)
		end

		local item = CaerdonItem:CreateFromItemLink(questLink)
		if item:IsItemDataCached() then
			self:ProcessItem(item, questID)
		else 
			item:ContinueOnItemLoad(function ()
				self:ProcessItem(item, questID)
			end)
		end
	end, function ()
		print('Failed to load quest data for ' .. questID)
	end)
end

function QuestLogMixin:ProcessItem(item, questID)
	local rewardsFrame = QuestInfoFrame.rewardsFrame;
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
end

CaerdonWardrobe:RegisterFeature(QuestLogMixin)
