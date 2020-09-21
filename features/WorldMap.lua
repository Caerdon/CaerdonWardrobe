local WorldMapMixin, WorldMap = {}

function WorldMapMixin:OnLoad()
	hooksecurefunc (WorldMap_WorldQuestPinMixin, "RefreshVisuals", function (self)
		if not IsModifiedClick("COMPAREITEMS") and not ShoppingTooltip1:IsShown() then
			WorldMap:UpdatePin(self);
		end
	end)
end

function WorldMapMixin:UpdatePin(pin)
	QuestEventListener:AddCallback(pin.questID, function()
		local options = {
			iconOffset = -5,
			iconSize = 60,
			overridePosition = "TOPRIGHT",
			-- itemCountOffset = 10,
			-- bindingScale = 0.9
		}

		local questLink = GetQuestLink(pin.questID)
		if not questLink then 
			local questName = C_QuestLog.GetQuestInfo(questID)
			local questLevel = C_QuestLog.GetQuestDifficultyLevel(questID)
			questLink = format("|cff808080|Hquest:%d:%d|h[%s]|h|r", questID, questLevel, questName)
		end

		local item = CaerdonItem:CreateFromItemLink(questLink)
		local itemData = item:GetItemData()
		local questInfo = itemData:GetQuestInfo()

		-- TODO: Review if necessary to iterate through rewards and find unknown ones...
		local bestIndex, bestType = QuestUtils_GetBestQualityItemRewardIndex(pin.questID)
		local reward
		if bestType == "reward" then
			reward = questInfo.rewards[bestIndex]
		elseif bestType == "choice" then
			reward = questInfo.choices[bestIndex]
		end

		if reward and reward.itemID then
			local _, itemLink = GetItemInfo(reward.itemID)
			CaerdonWardrobe:UpdateButtonLink(itemLink, "QuestButton", { itemID = reward.itemID, questID = pin.questID }, pin, options)
		else
			CaerdonWardrobe:ClearButton(pin)
		end
	end)
end

WorldMap = CreateFromMixins(WorldMapMixin)
WorldMap:OnLoad()
