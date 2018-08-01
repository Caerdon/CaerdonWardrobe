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
		itemCountOffset = 10,
		bindingScale = 0.9
	}

	local function RefreshButtons()
		local buttons = WQT_WorldQuestFrame.scrollFrame.buttons;
		for i = 1, #buttons do
			local button = buttons[i]
			local questInfo = button.info
			local rewardSlot = 1
			if questInfo then
				local _, texture, numItems, quality, _, itemID = GetQuestLogRewardInfo(rewardSlot, questInfo.id);
				if itemID then
					button.reward.count = numItems
					CaerdonWardrobe:UpdateButton(itemID, "QuestButton", { itemID = itemID, questID = button.questId }, button.reward, options)
				else
					button.reward.count = 0
					CaerdonWardrobe:ClearButton(button)
				end
			else
				CaerdonWardrobe:ClearButton(button)
			end
		end
	end

	hooksecurefunc(WQT_QuestScrollFrame, 'DisplayQuestList', RefreshButtons)
end