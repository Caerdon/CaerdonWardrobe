local MissionMixin = {}

function MissionMixin:GetName()
	return "Mission"
end

function MissionMixin:Init()
	return { "ADDON_LOADED" }
end

function MissionMixin:ADDON_LOADED(name)
	if name == "Blizzard_GarrisonUI" then
		CovenantMissionFrameMissions.ScrollBox:RegisterCallback("OnDataRangeChanged", self.OnCovenantMissionScrollBoxRangeChanged, self);
		GarrisonLandingPageReportList.ScrollBox:RegisterCallback("OnDataRangeChanged", self.OnGarrisonLandingScrollBoxRangeChanged, self);
	end
end


function MissionMixin:SetTooltipItem(tooltip, item, locationInfo)
	tooltip:SetHyperlink(item:GetItemLink())
end

function MissionMixin:Refresh()
end

function MissionMixin:OnCovenantMissionScrollBoxRangeChanged(sortPending)
	local scrollBox = CovenantMissionFrameMissions.ScrollBox
	scrollBox:ForEachFrame(function(missionButton, elementData)
        local missionIndex = scrollBox:FindIndex(elementData)

        local index = 1;
        for id, reward in pairs(elementData.rewards) do
            local button = missionButton.Rewards[index];
            if button.itemLink and button.itemID and button.itemID > 0 then
                local options = {
                    relativeFrame = button.Icon,
                    statusOffsetX = 3,
                    statusOffsetY = 3
                }
    
                local item = CaerdonItem:CreateFromItemLink(button.itemLink)
                CaerdonWardrobe:UpdateButton(button, item, self, { 
                    locationKey = format("covenantmissionbutton-%d-%d", button.itemID, id)
                }, options)
            else
                CaerdonWardrobe:ClearButton(button)
            end
    
            index = index + 1
        end
    
        for index = (#elementData.rewards + 1), #missionButton.Rewards do
            CaerdonWardrobe:ClearButton(missionButton.Rewards[index])
        end
    end)
end

function MissionMixin:OnGarrisonLandingScrollBoxRangeChanged(sortPending)
	local scrollBox = GarrisonLandingPageReportList.ScrollBox
	scrollBox:ForEachFrame(function(missionButton, elementData)
        local missionIndex = scrollBox:FindIndex(elementData)

        local index = 1;
        for id, reward in pairs(elementData.rewards) do
            local button = missionButton.Rewards[index];
            if button.itemLink and button.itemID and button.itemID > 0 then
                local options = {
                    relativeFrame = button.Icon,
                    statusOffsetX = 3,
                    statusOffsetY = 3
                }
    
                local item = CaerdonItem:CreateFromItemLink(button.itemLink)
                CaerdonWardrobe:UpdateButton(button, item, self, { 
                    locationKey = format("garrisonlandingbutton-%d-%d", button.itemID, id)
                }, options)
            else
                CaerdonWardrobe:ClearButton(button)
            end
    
            index = index + 1
        end
    
        for index = (#elementData.rewards + 1), #missionButton.Rewards do
            CaerdonWardrobe:ClearButton(missionButton.Rewards[index])
        end
    end)
end

CaerdonWardrobe:RegisterFeature(MissionMixin)
