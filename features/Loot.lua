local LootMixin = {}

function LootMixin:GetName()
	return "Loot"
end

function LootMixin:Init()
	LootFrame.ScrollBox:RegisterCallback("OnDataRangeChanged", self.OnScrollBoxRangeChanged, self)
end

function LootMixin:GetTooltipInfo(tooltip, item, locationInfo)
	local tooltipInfo = MakeBaseTooltipInfo("GetLootItem", locationInfo.elementData.slotIndex);
	return tooltipInfo
end

function LootMixin:Refresh()
end

function LootMixin:OnScrollBoxRangeChanged(sortPending)
	local scrollBox = LootFrame.ScrollBox
	scrollBox:ForEachFrame(function(button, elementData)
		-- elementData: slotIndex, group (coin = 1 else 0), quality
		local link = GetLootSlotLink(elementData.slotIndex);
		if link then
			local item = CaerdonItem:CreateFromItemLink(link)
			CaerdonWardrobe:UpdateButton(button, item, self, {
				locationKey = format("%d", elementData.slotIndex),
				elementData = elementData
			}, nil)
		else
			CaerdonWardrobe:ClearButton(button)
		end
	end)
end

CaerdonWardrobe:RegisterFeature(LootMixin)
