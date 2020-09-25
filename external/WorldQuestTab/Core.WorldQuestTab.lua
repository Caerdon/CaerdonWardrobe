local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "WorldQuestTab"
local WorldQuestTabMixin = {}

function WorldQuestTabMixin:GetName()
    return addonName
end

function WorldQuestTabMixin:Init()
	WQT_WorldQuestFrame:RegisterCallback('ListButtonUpdate', function(...) self:UpdateButton(...) end)
end

function WorldQuestTabMixin:SetTooltipItem(tooltip, item, locationInfo)
	tooltip:SetHyperlink(item:GetItemLink())
end

function WorldQuestTabMixin:Refresh()
	local buttons = WQT_WorldQuestFrame.ScrollFrame.buttons;
	for i = 1, #buttons do
		local button = buttons[i]
		for rewardIndex = 1, #button.Rewards do
			self:UpdateButton(button.Rewards[rewardIndex])
		end
	end
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
  type == WQT_REWARDTYPE.weapon or
  type == WQT_REWARDTYPE.equipment or 
  type == WQT_REWARDTYPE.spell or 
  type == WQT_REWARDTYPE.item
end

function WorldQuestTabMixin:UpdateButton(button)
	local questInfo = button.questInfo

	if questInfo and questInfo.isValid then
		for k, rewardInfo in questInfo:IterateRewards() do
			local rewardButton = button.Rewards.rewardFrames[k]
			if rewardInfo.id and self:IsValidItem(rewardInfo.type) then
				local options = {
					hasCount = rewardInfo.amount > 0,
					statusProminentSize = 16,
					itemCountOffset = 9
				}
				
				local item = Item:CreateFromItemID(rewardInfo.id)
				CaerdonWardrobe:UpdateButtonLink(rewardButton, item:GetItemLink(), self:GetName(), { reward = rewardInfo, questID = button.questId }, options)
			else
				CaerdonWardrobe:ClearButton(rewardButton)
			end
		end
	else
		for rewardButton in button.Rewards.rewardFrames do
			CaerdonWardrobe:ClearButton(rewardButton)
		end
	end
end


local Version = nil
if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
	    Version = GetAddOnMetadata(addonName, "Version")
		CaerdonWardrobe:RegisterFeature(WorldQuestTabMixin)
	end
end
