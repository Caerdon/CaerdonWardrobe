local ItemConversionMixin = {}

function ItemConversionMixin:GetName()
	return "ItemConversion"
end

function ItemConversionMixin:Init()
	self:WhenAddOnLoaded("Blizzard_ItemInteractionUI", self.OnItemInteractionLoaded)
	return {}
end

function ItemConversionMixin:OnItemInteractionLoaded()
	local outputSlot = ItemInteractionFrame and ItemInteractionFrame.ItemConversionFrame
		and ItemInteractionFrame.ItemConversionFrame.ItemConversionOutputSlot
	if outputSlot and outputSlot.RefreshIcon then
		local feature = self
		hooksecurefunc(outputSlot, "RefreshIcon", function(slot)
			feature:OnOutputSlotRefreshIcon(slot)
		end)
	end
end

function ItemConversionMixin:OnOutputSlotRefreshIcon(outputSlot)
	local itemInteractionFrame = outputSlot:GetParent():GetParent()
	if not itemInteractionFrame or not itemInteractionFrame.GetItemLocation then
		return
	end

	local itemLocation = itemInteractionFrame:GetItemLocation()
	if not itemLocation then
		CaerdonWardrobe:ClearButton(outputSlot)
		return
	end

	-- Same readiness guard Blizzard uses — nil means conversion data hasn't arrived yet
	local icon = C_Item.GetItemConversionOutputIcon(itemLocation)
	if not icon then
		CaerdonWardrobe:ClearButton(outputSlot)
		return
	end

	local tooltipData = C_TooltipInfo.GetItemInteractionItem()
	if not tooltipData or not tooltipData.hyperlink then
		CaerdonWardrobe:ClearButton(outputSlot)
		return
	end

	local item = CaerdonItem:CreateFromItemLink(tooltipData.hyperlink)
	local locationInfo = {
		locationKey = "itemConversion-output"
	}

	-- The default slot look on the 48 px output slot: a square, unmasked icon with nothing clipping it.
	local options = {
		statusProminentSize = CaerdonWardrobe:GetSlotStatusSize(outputSlot:GetSize())
	}

	local function doUpdate()
		CaerdonWardrobe:UpdateButton(outputSlot, item, self, locationInfo, options)
	end

	if item:IsItemDataCached() then
		doUpdate()
	else
		item:ContinueOnItemLoad(doUpdate)
	end
end

function ItemConversionMixin:GetTooltipData(item, locationInfo)
	return C_TooltipInfo.GetItemInteractionItem()
end

function ItemConversionMixin:Refresh()
	CaerdonWardrobeFeatureMixin:Refresh(self)

	if not ItemInteractionFrame or not ItemInteractionFrame:IsShown() then
		return
	end

	if ItemInteractionFrame:GetInteractionType() ~= Enum.UIItemInteractionType.ItemConversion then
		return
	end

	local outputSlot = ItemInteractionFrame.ItemConversionFrame and
		ItemInteractionFrame.ItemConversionFrame.ItemConversionOutputSlot
	if outputSlot then
		self:OnOutputSlotRefreshIcon(outputSlot)
	end
end

function ItemConversionMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	return {
		bindingStatus = {
			shouldShow = false
		},
		ownIcon = {
			shouldShow = true
		},
		otherIcon = {
			shouldShow = true
		},
		questIcon = {
			shouldShow = false
		},
		oldExpansionIcon = {
			shouldShow = false
		},
		sellableIcon = {
			shouldShow = false
		}
	}
end

CaerdonWardrobe:RegisterFeature(ItemConversionMixin)
