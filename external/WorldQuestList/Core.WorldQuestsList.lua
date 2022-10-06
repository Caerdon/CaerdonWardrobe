local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "WorldQuestsList"
local WorldQuestsListMixin = {}

function WorldQuestsListMixin:GetName()
    return addonName
end

function WorldQuestsListMixin:Init()
    self.WorldQuestList = _G["WorldQuestList"]
    -- hooksecurefunc(self.WorldQuestList, 'UpdateList', function(...) self:RefreshButtons(...) end)

    hooksecurefunc (WorldMap_WorldQuestPinMixin, "RefreshVisuals", function (...)
		if not IsModifiedClick("COMPAREITEMS") and not ShoppingTooltip1:IsShown() then
			self:RefreshButtons(...);
		end
	end)

    C_Timer.NewTicker(.5,function()
        -- Horrible refresh hack for now
        if WorldMapFrame:IsVisible() then
            self:Refresh()
        end
    end)
    
    -- return { "QUEST_LOG_UPDATE" }
end

-- This works, but it doesn't account for sort so doing a ticker for now until I figure out a way to hook sort
-- function WorldQuestsListMixin:QUEST_LOG_UPDATE()
--     C_Timer.After(0, function() 
--         self:Refresh()
--     end)
-- end

function WorldQuestsListMixin:GetTooltipInfo(tooltip, item, locationInfo)
	local tooltipInfo = MakeBaseTooltipInfo("GetHyperlink", item:GetItemLink());
	return tooltipInfo
end

function WorldQuestsListMixin:Refresh()
    self:RefreshButtons()
end

function WorldQuestsListMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
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

function WorldQuestsListMixin:RefreshButtons()
    local charKey = (UnitName'player' or "").."-"..(GetRealmName() or ""):gsub(" ","")

    if not self.WorldQuestList:IsVisible() and not _G.VWQL[charKey].HideMap then return end

    local result = self.WorldQuestList.currentResult
    if not result then return end

	for i=1,#result do
		local data = result[i]
		local line = self.WorldQuestList.l[i]

        local options = {
            statusProminentSize = 10,
            statusOffsetX = 0,
            statusOffsetY = 8,
            -- relativeFrame = line.reward.f.icon,
            bindingScale = 0.5,
            overrideBindingPosition = "LEFT"
            -- bindingOffsetY = -3
        }
    
        if line.rewardLink then
            local item = CaerdonItem:CreateFromItemLink(line.rewardLink)
            CaerdonWardrobe:UpdateButton(line.reward.f, item, self, {
                locationKey = format("wqlPin%d", line.questID),
                questID = line.questID
            }, options)
        else
            CaerdonWardrobe:ClearButton(line.reward.f)
        end
    end
end

local Version = nil
local isActive = false

if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
	    Version = GetAddOnMetadata(addonName, "Version")
		CaerdonWardrobe:RegisterFeature(WorldQuestsListMixin)
        isActive = true
	end
end

WagoAnalytics:Switch(addonName, isActive)
