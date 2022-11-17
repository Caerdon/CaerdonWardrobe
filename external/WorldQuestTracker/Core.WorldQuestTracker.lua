local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "WorldQuestTracker"
local WorldQuestTracker = WorldQuestTrackerAddon
local WorldQuestTrackerMixin = {}

function WorldQuestTrackerMixin:GetName()
    return addonName
end

function WorldQuestTrackerMixin:Init()
    hooksecurefunc(WorldQuestTracker, "UpdateWorldWidget", function(...) self:OnUpdateWorldWidget(...) end)
    hooksecurefunc(WorldQuestTracker, "SetupWorldQuestButton", function(...) self:OnSetupWorldQuestButton(...) end)

    -- WorldQuestTracker.SetupWorldQuestButton(widget, worldQuestType, rarity, isElite, tradeskillLineIndex, inProgress, selected, isCriteria, isSpellTarget, mapID)
    -- WorldQuestTracker.UpdateWorldWidget (widget, questID, numObjectives, mapID, isCriteria, isNew, isUsingTracker, timeLeft, artifactPowerIcon)
end

function WorldQuestTrackerMixin:GetTooltipData(item, locationInfo)
	return C_TooltipInfo.GetHyperlink(item:GetItemLink())
end

function WorldQuestTrackerMixin:Refresh()
end

function WorldQuestTrackerMixin:IsSameItem(button, item, locationInfo)
	-- QuestId will be directly on world map pin but is on the grandparent for the quest log
	local isSame = button.questId == locationInfo.questID or button:GetParent():GetParent().questId == locationInfo.questID
	return isSame
end

function WorldQuestTrackerMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
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
			shouldShow = false
		},
        sellableIcon = {
            shouldShow = false
        }
	}
end

function WorldQuestTrackerMixin:IsValidItem(type)
  return 
	  type ~= WQT_REWARDTYPE.missing and
	  type ~= WQT_REWARDTYPE.artifact and
	  type ~= WQT_REWARDTYPE.gold and 
	  type ~= WQT_REWARDTYPE.currency and 
	  type ~= WQT_REWARDTYPE.honor and
	  type ~= WQT_REWARDTYPE.reputation and
	  type ~= WQT_REWARDTYPE.xp
end

function WorldQuestTrackerMixin:OnSetupWorldQuestButton(widget, worldQuestType, rarity, isElite, tradeskillLineIndex, inProgress, selected, isCriteria, isSpellTarget, mapID)
    local questID = widget.questID

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
            reward = rewardInfo,
            questID = questId
        }, options)
    else
        CaerdonWardrobe:ClearButton(widget)
    end
end

function WorldQuestTrackerMixin:OnUpdateWorldWidget(widget, questID, numObjectives, mapID, isCriteria, isNew, isUsingTracker, timeLeft, artifactPowerIcon)
    -- local itemLink = GetQuestLogItemLink("reward", k, questId)
    if (type (questID) == "boolean" and questID) then
		questID = widget.questID
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
            locationKey = format("widget-%s-index%d", widget:GetName(), itemID),
            reward = rewardInfo,
            questID = questId
        }, options)
    else
        CaerdonWardrobe:ClearButton(widget)
    end
end

function WorldQuestTrackerMixin:UpdateButton(button)
	local questInfo = button.questInfo

	for k, rewardButton in ipairs(button.Rewards.rewardFrames) do
		CaerdonWardrobe:ClearButton(rewardButton)
	end

	if questInfo and questInfo.isValid then
		for k, rewardInfo in questInfo:IterateRewards() do
			local rewardButton = button.Rewards.rewardFrames[k]
			if rewardInfo.id and self:IsValidItem(rewardInfo.type) then
				local itemLink = GetQuestLogItemLink("reward", k, button.questId)
				if itemLink then
					local options = {
						hasCount = rewardInfo.amount > 0,
						statusProminentSize = 16,
						itemCountOffset = 9
					}
					
					local item = CaerdonItem:CreateFromItemLink(itemLink)
					CaerdonWardrobe:UpdateButton(rewardButton, item, self, {
						locationKey = format("%s-index%d", button:GetName(), k),
						reward = rewardInfo,
						questID = button.questId
					}, options)
				end
			end
		end
	end
end

function WorldQuestTrackerMixin:UpdatePin(pin)
	local options = {
		statusProminentSize = 15
	}

	local questLink = GetQuestLink(pin.questId)
	if not questLink then 
		local questName = C_QuestLog.GetTitleForQuestID(pin.questId)
		local questLevel = C_QuestLog.GetQuestDifficultyLevel(pin.questId)
		questLink = format("|cff808080|Hquest:%d:%d|h[%s]|h|r", pin.questId, questLevel, questName)
	end

	local questItem = CaerdonItem:CreateFromItemLink(questLink)
	local itemData = questItem:GetItemData()
	if not itemData then
		CaerdonWardrobe:ClearButton(pin)
		return
	end
	
	local questInfo = itemData:GetQuestInfo()

	-- TODO: Review if necessary to iterate through rewards and find unknown ones...
	local bestIndex, bestType = QuestUtils_GetBestQualityItemRewardIndex(pin.questId)
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

	local itemLink = GetQuestLogItemLink(bestType, bestIndex, pin.questId)
	if not itemLink then
		CaerdonWardrobe:ClearButton(pin)
		return
	end

	local item = CaerdonItem:CreateFromItemLink(itemLink)
	CaerdonWardrobe:UpdateButton(pin, item, self, { 
		locationKey = format("wqtPin%d", pin.questId),
		questID = pin.questId,
		questItem
	}, options)
end

local Version = nil
local isActive = false

if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
	    Version = GetAddOnMetadata(addonName, "Version")
		CaerdonWardrobe:RegisterFeature(WorldQuestTrackerMixin)
		isActive = true
	end
end

WagoAnalytics:Switch(addonName, isActive)
