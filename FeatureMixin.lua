CaerdonWardrobeFeatureMixin = {}
function CaerdonWardrobeFeatureMixin:GetName()
	-- Must be unique
	error("Caerdon Wardrobe: Must provide a feature name")
end

function CaerdonWardrobeFeatureMixin:Init()
	-- init and return array of frame events you'd like to receive
	error("Caerdon Wardrobe: Must provide Init implementation")
end

function CaerdonWardrobeFeatureMixin:SetTooltipItem(tooltip, item, locationInfo)
	error("Caerdon Wardrobe: Must provide SetTooltipItem implementation")
end

function CaerdonWardrobeFeatureMixin:Refresh()
	-- Primarily used for global transmog refresh when appearances learned right now
	error("Caerdon Wardrobe: Must provide Refresh implementation")
end

function CaerdonWardrobeFeatureMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	return {}
end

function CaerdonWardrobeFeatureMixin:GetDisplayInfoInternal(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	-- TODO: Temporary for merging - revisit after pushing everything into Mixins
	local showBindingStatus = not locationInfo.isBankOrBags or CaerdonWardrobeConfig.Binding.ShowStatus.BankAndBags
	local showOwnIcon = not locationInfo.isBankOrBags or CaerdonWardrobeConfig.Icon.ShowLearnable.BankAndBags
	local showOtherIcon = not locationInfo.isBankOrBags or CaerdonWardrobeConfig.Icon.ShowLearnableByOther.BankAndBags
	local showSellableIcon = not locationInfo.isBankOrBags or CaerdonWardrobeConfig.Icon.ShowSellable.BankAndBags

	local displayInfo = {
		bindingStatus = {
			shouldShow = showBindingStatus -- true
		},
		ownIcon = {
			shouldShow = showOwnIcon
		},
		otherIcon = {
			shouldShow = showOtherIcon
		},
		questIcon = {
			shouldShow = CaerdonWardrobeConfig.Icon.ShowQuestItems
		},
		oldExpansionIcon = {
			shouldShow = true
		},
		sellableIcon = {
			shouldShow = showSellableIcon
		}
	}

	CaerdonAPI:MergeTable(displayInfo, self:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus))

	-- TODO: BoA and BoE settings should be per feature
	if not CaerdonWardrobeConfig.Binding.ShowBoA and bindingStatus == L["BoA"] then
		displayInfo.bindingStatus.shouldShow = false
	end

	if not CaerdonWardrobeConfig.Binding.ShowBoE and bindingStatus == L["BoE"] then
		displayInfo.bindingStatus.shouldShow = false
	end

	return displayInfo
end

function CaerdonWardrobeFeatureMixin:OnUpdate()
	-- Called from the main frame's OnUpdate
end
