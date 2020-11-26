local WorldMapMixin = {}
local version, build, date, tocversion = GetBuildInfo()
local isShadowlands = tonumber(build) > 35700

function WorldMapMixin:GetName()
	return "WorldMap"
end

function WorldMapMixin:Init()
	hooksecurefunc (WorldMap_WorldQuestPinMixin, "RefreshVisuals", function (...)
		if not IsModifiedClick("COMPAREITEMS") and not ShoppingTooltip1:IsShown() then
			self:UpdatePin(...);
		end
	end)
end

function WorldMapMixin:SetTooltipItem(tooltip, item, locationInfo)
	local itemLink = item:GetItemLink()
	if itemLink then
		tooltip:SetHyperlink(itemLink)
	end
end

function WorldMapMixin:Refresh()
end

function WorldMapMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
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

function WorldMapMixin:UpdatePin(pin)
	QuestEventListener:AddCallback(pin.questID, function()
		local options = {
			statusProminentSize = 30
		}

		local questLink = GetQuestLink(pin.questID)
		if not questLink then 
			local questName
			if isShadowlands then
				questName = C_QuestLog.GetTitleForQuestID(pin.questID)
			else
				questName = C_QuestLog.GetQuestInfo(pin.questID)
			end

			local questLevel = C_QuestLog.GetQuestDifficultyLevel(pin.questID)
			questLink = format("|cff808080|Hquest:%d:%d|h[%s]|h|r", pin.questID, questLevel, questName)
		end

		local questItem = CaerdonItem:CreateFromItemLink(questLink)
		local itemData = questItem:GetItemData()
		if not itemData then
			CaerdonWardrobe:ClearButton(pin)
			return
		end
		
		local questInfo = itemData:GetQuestInfo()

		-- TODO: Review if necessary to iterate through rewards and find unknown ones...
		local bestIndex, bestType = QuestUtils_GetBestQualityItemRewardIndex(pin.questID)
		local reward
		if bestType == "reward" then
			reward = questInfo.rewards[bestIndex]
		elseif bestType == "choice" then
			reward = questInfo.choices[bestIndex]
		end

		if not bestType then 
			CaerdonWardrobe:ClearButton(pin)
			return
		end

		local itemLink = GetQuestLogItemLink(bestType, bestIndex, pin.questID)
		if not itemLink then
			CaerdonWardrobe:ClearButton(pin)
			return
		end

		local item = CaerdonItem:CreateFromItemLink(itemLink)
		CaerdonWardrobe:UpdateButton(pin, item, self, { 
			locationKey = format("%d", pin.questID),
			questID = pin.questID,
			questItem
		}, options)
	end)
end

CaerdonWardrobe:RegisterFeature(WorldMapMixin)
