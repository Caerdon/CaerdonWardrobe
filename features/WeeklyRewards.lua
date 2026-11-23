local WeeklyRewardsMixin_Feature = {}

function WeeklyRewardsMixin_Feature:GetName()
	return "WeeklyRewards"
end

function WeeklyRewardsMixin_Feature:Init()
	self:WhenAddOnLoaded("Blizzard_WeeklyRewards", self.OnWeeklyRewardsLoaded)
	return {}
end

function WeeklyRewardsMixin_Feature:OnWeeklyRewardsLoaded()
	hooksecurefunc(WeeklyRewardsFrame, "Refresh", function()
		self:UpdateActivities()
	end)
end

function WeeklyRewardsMixin_Feature:GetTooltipData(item, locationInfo)
	return C_TooltipInfo.GetWeeklyReward(locationInfo.itemDBID)
end

function WeeklyRewardsMixin_Feature:Refresh()
	if WeeklyRewardsFrame and WeeklyRewardsFrame:IsShown() then
		self:UpdateActivities()
	end
end

function WeeklyRewardsMixin_Feature:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	return {
		bindingStatus = {
			shouldShow = true
		},
		ownIcon = {
			shouldShow = true
		},
		otherIcon = {
			shouldShow = true
		},
		questIcon = {
			shouldShow = CaerdonWardrobeConfig.Icon.ShowQuestItems
		},
		oldExpansionIcon = {
			shouldShow = false
		},
		sellableIcon = {
			shouldShow = false
		}
	}
end

function WeeklyRewardsMixin_Feature:UpdateActivities()
	for i, activityFrame in ipairs(WeeklyRewardsFrame.Activities) do
		local itemFrame = activityFrame.ItemFrame
		if itemFrame and itemFrame.displayedItemDBID then
			local hyperlink = C_WeeklyRewards.GetItemHyperlink(itemFrame.displayedItemDBID)
			if hyperlink then
				local item = CaerdonItem:CreateFromItemLink(hyperlink)
				local options = {
					relativeFrame = itemFrame.Icon
				}
				CaerdonWardrobe:UpdateButton(itemFrame, item, self, {
					locationKey = format("weeklyReward-%d", i),
					type = "weeklyReward",
					index = i,
					itemDBID = itemFrame.displayedItemDBID
				}, options)
			else
				CaerdonWardrobe:ClearButton(itemFrame)
			end
		else
			if itemFrame then
				CaerdonWardrobe:ClearButton(itemFrame)
			end
		end
	end
end

CaerdonWardrobe:RegisterFeature(WeeklyRewardsMixin_Feature)
