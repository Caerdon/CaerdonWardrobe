local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "WorldQuestTab"
local WorldQuestTabMixin = {}

function WorldQuestTabMixin:GetName()
    return addonName
end

function WorldQuestTabMixin:Init()
	WQT_WorldQuestFrame:RegisterCallback('ListButtonUpdate', function(...) self:UpdateButton(...) end)
	WQT_WorldQuestFrame:RegisterCallback('MapPinPlaced', function(...) self:UpdatePin(...) end)
end

function WorldQuestTabMixin:GetTooltipData(item, locationInfo)
	return C_TooltipInfo.GetHyperlink(item:GetItemLink())
end

function WorldQuestTabMixin:Refresh()
	-- local buttons = WQT_WorldQuestFrame.ScrollFrame.buttons;
	-- for i = 1, #buttons do
	-- 	local button = buttons[i]
	-- 	for rewardIndex = 1, #button.Rewards do
	-- 		self:UpdateButton(button.Rewards[rewardIndex])
	-- 	end
	-- end
end

function WorldQuestTabMixin:IsSameItem(button, item, locationInfo)
	-- QuestId will be directly on world map pin but is on the grandparent for the quest log
	local isSame = button.questId == locationInfo.questID or button:GetParent():GetParent().questId == locationInfo.questID
	return isSame
end

function WorldQuestTabMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
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

function WorldQuestTabMixin:IsValidItem(type)
  return 
	  type ~= WQT_REWARDTYPE.missing and
	  type ~= WQT_REWARDTYPE.artifact and
	  type ~= WQT_REWARDTYPE.gold and 
	  type ~= WQT_REWARDTYPE.currency and 
	  type ~= WQT_REWARDTYPE.honor and
	  type ~= WQT_REWARDTYPE.reputation and
	  type ~= WQT_REWARDTYPE.xp
end

function WorldQuestTabMixin:UpdateButton(button)
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

function WorldQuestTabMixin:UpdatePin(pin)
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
		CaerdonWardrobe:RegisterFeature(WorldQuestTabMixin)
		isActive = true
	end
end

WagoAnalytics:Switch(addonName, isActive)
