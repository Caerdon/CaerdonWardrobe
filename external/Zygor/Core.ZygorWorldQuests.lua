local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "ZygorGuidesViewer"
local ZygorMixin = {}

function ZygorMixin:GetName()
    return addonName
end

function ZygorMixin:Init()
    self.WorldQuests = ZygorGuidesViewer.WorldQuests
    hooksecurefunc(self.WorldQuests, 'QueueDetailsLoad', function(...) self:RefreshButtons(...) end)
end

function ZygorMixin:SetTooltipItem(tooltip, item, locationInfo)
	tooltip:SetHyperlink(item:GetItemLink())
end

function ZygorMixin:Refresh()
    self:RefreshButtons()
end

function ZygorMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
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

function ZygorMixin:RefreshButtons()
    if not ZygorGuidesViewer.db.profile.worldquestenable then return end
    -- if not WorldQuests.needToUpdate then return end
    if not self.WorldQuests.QuestList then return end
    if not WorldMapFrame:IsVisible() then return end

    local WQ_RowNum=0
    local WQ_RowOff=self.WorldQuests.QuestsOffset
    local QuestList = self.WorldQuests.QuestList
    local ROW_COUNT = QuestList:CountRows()
	local Quests = self.WorldQuests.Quests

	if #self.WorldQuests.Quests==0 or not self.WorldQuests.DisplayAll then
		Quests = self.WorldQuests.QuestQueueDetails
	end

    local display_quests = {}
	for ii,questItem in ipairs(Quests) do 
		if self.WorldQuests:IsValidQuest(questItem) then
			table.insert(display_quests,questItem)
		end
	end
	-- sort data
	local sorting_mode, sorting_dir = ZygorGuidesViewer.db.profile.WQSorting[1], ZygorGuidesViewer.db.profile.WQSorting[2]

	table.sort(display_quests,function(a,b)
		local a_value, b_value

		if sorting_mode=="name" then
			a_value = a.title
			b_value = b.title
		elseif sorting_mode=="faction" then
			a_value = a.reputationName
			b_value = b.reputationName
		elseif sorting_mode=="time" then
			a_value = a.time
			b_value = b.time
		elseif sorting_mode=="zone" then
			a_value = a.mapName
			b_value = b.mapName
		elseif sorting_mode=="rewards" then
			a_value = a.currencies.name or a.rewards.itemname or (a.gold and tostring("gold "..a.gold))
			b_value = b.currencies.name or b.rewards.itemname or (b.gold and tostring("gold "..b.gold))
		end

		if a_value and b_value and a_value~=b_value then
			if sorting_dir=="asc" then 
				return a_value<b_value 
			else 
				return a_value>b_value
			end
		else
			return a.title<b.title
		end
	end)

    WQ_RowOff=self.WorldQuests.QuestsOffset
    for ii,questItem in ipairs(display_quests) do 
        WQ_RowNum = ii-WQ_RowOff
        if WQ_RowNum>0 and WQ_RowNum<ROW_COUNT+1 then 
            local row = QuestList.rows[WQ_RowNum]
            local quest = row.quest
            local reward = quest.rewards
            local button =  _G["ZGVWQLISTRow" .. WQ_RowNum .. "Icon"]

            local options = {
                statusProminentSize = 14,
                relativeFrame = row.rewardicon,
                bindingScale = 0.9,
                bindingOffsetY = -3
            }
        
            if reward.itemlink then
                local item = CaerdonItem:CreateFromItemLink(reward.itemlink)
                CaerdonWardrobe:UpdateButton(button, item, self, {
                    locationKey = format("%d", WQ_RowNum),
                    questID = quest.questID
                }, options)
            else
                CaerdonWardrobe:ClearButton(button)
            end
        end
    end
end

local Version = nil
if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
	    Version = GetAddOnMetadata(addonName, "Version")
		CaerdonWardrobe:RegisterFeature(ZygorMixin)
	end
end
