local MissionMixin = {}

function MissionMixin:GetName()
	return "Mission"
end

function MissionMixin:Init()
	return { "ADDON_LOADED" }
end

function MissionMixin:ADDON_LOADED(name)
	if name == "Blizzard_GarrisonUI" then
        hooksecurefunc("GarrisonMissionButton_SetRewards", function(...) self:OnGarrisonMissionButton_SetRewards(...) end)
        hooksecurefunc("GarrisonLandingPageReportList_UpdateAvailable", function(...) self:OnGarrisonLandingPageReportList_UpdateAvailable(...) end)
	end
end


function MissionMixin:SetTooltipItem(tooltip, item, locationInfo)
	tooltip:SetHyperlink(item:GetItemLink())
end

function MissionMixin:Refresh()
end

function MissionMixin:OnGarrisonMissionButton_SetRewards(button, rewards)
    local index = 1;
    for id, reward in pairs(rewards) do
        local Reward = button.Rewards[index];
                
        if (reward.itemLink) then
            local options = {
                relativeFrame = Reward.Icon,
                statusOffsetX = 3,
                statusOffsetY = 3
            }
    
            local item = CaerdonItem:CreateFromItemLink(reward.itemLink)
            CaerdonWardrobe:UpdateButton(Reward, item, self, { 
                locationKey = format("missionbutton-%d-%d", button.id, index)
            }, options)
        else
            CaerdonWardrobe:ClearButton(Reward)
        end

        index = index + 1;
    end
end

function MissionMixin:OnGarrisonLandingPageReportList_UpdateAvailable()
	local items = GarrisonLandingPageReport.List.AvailableItems;
	local numItems = #items;
	local scrollFrame = GarrisonLandingPageReport.List.listScroll;
	local offset = HybridScrollFrame_GetOffset(scrollFrame);
	local buttons = scrollFrame.buttons;
	local numButtons = #buttons;

	for i = 1, numButtons do
		local button = buttons[i];
		local index = offset + i; -- adjust index
		if ( index <= numItems ) then
            local item = items[index];
            local index = 1;
			for id, reward in pairs(item.rewards) do
                local Reward = button.Rewards[index];
                
                if (reward.itemLink) then
                    local options = {
                        relativeFrame = Reward.Icon,
                        statusOffsetX = 3,
                        statusOffsetY = 3
                    }
            
                    local item = CaerdonItem:CreateFromItemLink(reward.itemLink)
                    CaerdonWardrobe:UpdateButton(Reward, item, self, { 
                        locationKey = format("garrisonlandingbutton-%d-%d", button.id, index)
                    }, options)
                else
                    CaerdonWardrobe:ClearButton(Reward)
                end

                index = index + 1;
            end
        end
    end
end

CaerdonWardrobe:RegisterFeature(MissionMixin)
