local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = 'WorldQuestTab'
local Version = nil
if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
	    Version = GetAddOnMetadata(addonName, 'Version')
	    CaerdonWardrobe:RegisterAddon(addonName, {
	    	isBag = false
	    })
	end
end

if Version then

	local options = {
		iconOffset = 4,
		iconSize = 30,
		overridePosition = "TOPLEFT",
		overrideBindingPosition = "CENTER",
		bindingScale = 0.8
	}

	local function RefreshButtons()
		local buttons = WQT_WorldQuestFrame.ScrollFrame.buttons;
		for i = 1, #buttons do
			local button = buttons[i]
			UpdateButton(button)
		end
	end

	local function IsValidItem(type)
	  return
      type == WQT_REWARDTYPE.weapon or
      type == WQT_REWARDTYPE.equipment or 
      type == WQT_REWARDTYPE.spell or 
      type == WQT_REWARDTYPE.item
	end

	local function UpdateButton(button)
		local questInfo = button.questInfo

		if questInfo and questInfo.isValid then
			for k, rewardInfo in questInfo:IterateRewards() do
				local rewardButton = button.Rewards.rewardFrames[k]
				if rewardInfo.id and IsValidItem(rewardInfo.type) then
					CaerdonWardrobe:UpdateButton(rewardInfo.id, "QuestButton", { itemID = rewardInfo.id, questID = button.questId }, rewardButton, options)
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

	WQT_WorldQuestFrame:RegisterCallback('ListButtonUpdate', UpdateButton)
end
