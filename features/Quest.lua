local QuestMixin, Quest = {}

local version, build, date, tocversion = GetBuildInfo()
local isShadowlands = tonumber(build) > 35700

-- TODO: Consider setting up a callback framework via RegisterAddon
local frame = CreateFrame("frame")
frame:RegisterEvent "QUEST_DATA_LOAD_RESULT"
frame:SetScript("OnEvent", function(this, event, ...)
    Quest[event](Quest, ...)
end)

function QuestMixin:OnLoad()
    self.latestDataRequestQuestID = nil

	-- self:RegisterEvent "QUEST_DATA_LOAD_RESULT"
    hooksecurefunc("QuestInfo_Display", function(...) Quest:OnQuestInfoDisplay(...) end)
end

function QuestMixin:OnQuestInfoDisplay(template, parentFrame)
	-- Hooking OnQuestInfoDisplay instead of OnQuestInfoShowRewards directly because it seems to work
	-- and I was having some problems.  :)
	local i = 1
	while template.elements[i] do
		if template.elements[i] == QuestInfo_ShowRewards then self:OnQuestInfoShowRewards(template, parentFrame) return end
		i = i + 3
	end
end

function QuestMixin:GetQuestID()
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

function QuestMixin:OnQuestInfoShowRewards(template, parentFrame)
	local numQuestRewards = 0;
	local numQuestChoices = 0;
	local rewardsFrame = QuestInfoFrame.rewardsFrame;
	local questID = self:GetQuestID()

	if questID == 0 then return end -- quest abandoned

	-- if ( template.canHaveSealMaterial ) then
	-- 	local questFrame = parentFrame:GetParent():GetParent();
	-- 	if ( template.questLog ) then
	-- 		questID = questFrame.questID;
	-- 	else
	-- 		questID = GetQuestID();
	-- 	end
	-- end

	local spellGetter;

	if ( QuestInfoFrame.questLog ) then
		if C_QuestLog.ShouldShowQuestRewards(questID) then
			numQuestRewards = GetNumQuestLogRewards();
			numQuestChoices = GetNumQuestLogChoices(questID, true);
			-- playerTitle = GetQuestLogRewardTitle();
			-- numSpellRewards = GetNumQuestLogRewardSpells();
			-- spellGetter = GetQuestLogRewardSpell;
		end
	else
		if ( QuestFrameRewardPanel:IsShown() or C_QuestLog.ShouldShowQuestRewards(questID) ) then
			numQuestRewards = GetNumQuestRewards();
			numQuestChoices = GetNumQuestChoices();
			-- playerTitle = GetRewardTitle();
			-- numSpellRewards = GetNumRewardSpells();
			-- spellGetter = GetRewardSpell;
		end
	end

	if not HaveQuestRewardData(questID) then
		-- HACK: Force load and handle in QUEST_DATA_LOAD_RESULT
		-- Not needed if Blizzard fixes showing of rewards in follow-up quests
		self.latestDataRequestQuestID = questID
		C_QuestLog.RequestLoadQuestByID(questID)
		return
	end

	local options = {
		iconOffset = 0,
		iconSize = 40,
		overridePosition = "TOPLEFT",
		overrideBindingPosition = "TOPLEFT",
		bindingOffsetX = -53,
		bindingOffsetY = -16
	}

	local questItem, name, texture, quality, isUsable, numItems, itemID;
	local rewardsCount = 0;
	if ( numQuestChoices > 0 ) then
		local index;
		local itemLink;
		local baseIndex = rewardsCount;
		for i = 1, numQuestChoices do
			index = i + baseIndex;
			questItem = QuestInfo_GetRewardButton(rewardsFrame, index);
			if ( QuestInfoFrame.questLog ) then
				name, texture, numItems, quality, isUsable, itemID = GetQuestLogChoiceInfo(i);

				if itemID then
					_, itemLink = GetItemInfo(itemID)
				end
			else
				name, texture, numItems, quality, isUsable = GetQuestItemInfo(questItem.type, i);
				itemLink = GetQuestItemLink(questItem.type, i);
			end
			rewardsCount = rewardsCount + 1;

			CaerdonWardrobe:UpdateButtonLink(itemLink, "QuestButton", { itemID = itemID, questID = questID, index = i, questItem = questItem }, questItem, options)
		end
	end

	if ( numQuestRewards > 0) then
		local index;
		local itemLink;
		local baseIndex = rewardsCount;
		local buttonIndex = 0;
		for i = 1, numQuestRewards, 1 do
			buttonIndex = buttonIndex + 1;
			index = i + baseIndex;
			questItem = QuestInfo_GetRewardButton(rewardsFrame, index);
			questItem.type = "reward";
			questItem.objectType = "item";
			if ( QuestInfoFrame.questLog ) then
				name, texture, numItems, quality, isUsable, itemID = GetQuestLogRewardInfo(i);
				if itemID then
					_, itemLink = GetItemInfo(itemID)
				end
			else
				name, texture, numItems, quality, isUsable = GetQuestItemInfo(questItem.type, i);
				itemLink = GetQuestItemLink(questItem.type, i);
			end
			rewardsCount = rewardsCount + 1;

			CaerdonWardrobe:UpdateButtonLink(itemLink, "QuestButton", { itemID = itemID, questID = questID, index = i, questItem = questItem }, questItem, options)
		end
	end
end

function QuestMixin:QUEST_DATA_LOAD_RESULT(questID, success)
	if success then
		-- Total hack until Blizzard fixes quest rewards not loading
		if questID == self.latestDataRequestQuestID then
			self.latestDataRequestQuestID = nil

			if QuestFrameDetailPanel:IsShown() then
				QuestFrameDetailPanel:Hide();
				QuestFrameDetailPanel:Show();
			end
		end
	end
end

Quest = CreateFromMixins(QuestMixin)
Quest:OnLoad()
