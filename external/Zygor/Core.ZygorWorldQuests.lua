local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = 'ZygorGuidesViewer'
local Version = nil
if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
	    Version = GetAddOnMetadata(addonName, 'Version')
	    CaerdonWardrobe:RegisterAddon(addonName, {
	    	isBag = false
	    })
	end
end

local function GetItemID(itemLink)
	-- local printable = gsub(itemLink, "\124", "\124\124");
	-- print(printable)
	return tonumber(itemLink:match("item:(%d+)") or itemLink:match("battlepet:(%d+)"))
end

if Version then

	local options = {
		iconOffset = 0,
		iconSize = 30,
		overridePosition = "TOPRIGHT",
        itemCountOffset = 0,
        bindingOffset = 67, -- Bit of a hack, but it works for now
        overrideBindingPosition = "BOTTOM",
		bindingScale = 0.9
	}

    local ZGV = ZygorGuidesViewer
    local WorldQuests = ZGV.WorldQuests

    local function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k,v in pairs(o) do
            if type(k) ~= 'number' then k = '"'..k..'"' end
            s = s .. '['..k..'] = ' .. tostring(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
    end

    local function RefreshButtons()
        if not ZGV.db.profile.worldquestenable then return end
        -- if not WorldQuests.needToUpdate then return end
        if not WorldQuests.QuestList then return end
        if not WorldMapFrame:IsVisible() then return end

        local WQ_RowNum=0
        local WQ_RowOff=WorldQuests.QuestsOffset
        local QuestList = WorldQuests.QuestList
        local ROW_COUNT = QuestList:CountRows()

        WQ_RowOff=WorldQuests.QuestsOffset
        for ii,questItem in ipairs(sh_display_quests) do 
            WQ_RowNum = ii-WQ_RowOff
            if WQ_RowNum>0 and WQ_RowNum<ROW_COUNT+1 then 
                local row = QuestList.rows[WQ_RowNum]
                local quest = row.quest
                local reward = quest.rewards

                -- if GetNumQuestLogRewards(quest.questID)>0 then
                --     WorldQuests.Scanner:SetQuestLogItem("reward", 1, quest.questID)
                --     local itemlink = select(2,WorldQuests.Scanner:GetItem())
                -- else
                --     print("NO REWARDS SORRY")
                -- end

                -- print(dump(row.quest))
                local button = _G["ZGVWQLISTRow" .. WQ_RowNum .. "Icon"]

                if reward.itemlink then -- item
                    CaerdonWardrobe:UpdateButton(GetItemID(reward.itemlink), "QuestButton", { itemLink = reward.itemlink, questID = quest.questID }, button, options)
                else
                    -- if row.rewardicon then
                        CaerdonWardrobe:ClearButton(button)
                    -- end
                end
            end
        end

		-- local buttons = WQT_WorldQuestFrame.ScrollFrame.buttons;
		-- for i = 1, #buttons do
		-- 	local button = buttons[i]
		-- 	local questInfo = button.info
		-- 	local rewardSlot = 1
		-- 	if questInfo then
		-- 		if questInfo.reward.id then
		-- 			button.Reward.count = questInfo.reward.amount
		-- 			CaerdonWardrobe:UpdateButton(questInfo.reward.id, "QuestButton", { itemID = questInfo.reward.id, questID = button.questId }, button.Reward, options)
		-- 		else
		-- 			button.Reward.count = 0
		-- 			CaerdonWardrobe:ClearButton(button.Reward)
		-- 		end
		-- 	else
		-- 		CaerdonWardrobe:ClearButton(button.Reward)
		-- 	end
		-- end
    end
    
    hooksecurefunc(WorldQuests, 'QueueDetailsLoad', RefreshButtons)
    -- RefreshButtons()
end