local WeeklyRewardsMixin_Feature = {}

function WeeklyRewardsMixin_Feature:GetName()
	return "WeeklyRewards"
end

function WeeklyRewardsMixin_Feature:Init()
	return { "ADDON_LOADED" }
end

function WeeklyRewardsMixin_Feature:ADDON_LOADED(name)
	if name == "Blizzard_WeeklyRewards" then
		hooksecurefunc(WeeklyRewardsFrame, "Refresh", function()
			self:UpdateActivities()
		end)
	end
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
			shouldShow = CaerdonWardrobeConfig.Icon.ShowLearnable.Auction
		},
		otherIcon = {
			shouldShow = CaerdonWardrobeConfig.Icon.ShowLearnableByOther.Auction
		},
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
