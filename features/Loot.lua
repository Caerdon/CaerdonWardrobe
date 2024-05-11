local LootMixin = {}

function LootMixin:GetName()
	return "Loot"
end

function LootMixin:Init()
	-- LootFrame.ScrollBox:RegisterCallback("OnDataRangeChanged", self.OnScrollBoxRangeChanged, self)
	ScrollUtil.AddInitializedFrameCallback(LootFrame.ScrollBox, function (...) self:OnLootInitializedFrame(...) end, LootFrame, false)
end

function LootMixin:GetTooltipData(item, locationInfo)
	return C_TooltipInfo.GetLootItem(locationInfo.elementData.slotIndex)
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

function LootMixin:OnLootInitializedFrame(listFrame, frame, elementData)
	local button = frame.Item;
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
end

CaerdonWardrobe:RegisterFeature(LootMixin)
