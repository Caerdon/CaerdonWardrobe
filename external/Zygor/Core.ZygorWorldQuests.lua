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
                local button = _G["ZGVWQLISTRow" .. WQ_RowNum .. "Icon"]

                CaerdonWardrobe:UpdateButtonLink(reward.itemlink, "QuestButton", { itemLink = reward.itemlink, questID = quest.questID }, button, options)
            end
        end
    end
    
    hooksecurefunc(WorldQuests, 'QueueDetailsLoad', RefreshButtons)
end
