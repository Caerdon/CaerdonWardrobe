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

    WQ_RowOff=self.WorldQuests.QuestsOffset
    for ii,questItem in ipairs(sh_display_quests) do 
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
        
            CaerdonWardrobe:UpdateButtonLink(button, reward.itemlink, self:GetName(), { questID = quest.questID }, options)
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
