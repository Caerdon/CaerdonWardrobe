local LootMixin = {}

function LootMixin:GetName()
	return "Loot"
end

function LootMixin:Init()
    hooksecurefunc("LootFrame_UpdateButton", function(...) self:OnLootFrameUpdateButton(...) end)
end

function LootMixin:SetTooltipItem(tooltip, item, locationInfo)
	tooltip:SetLootItem(locationInfo.index)
end

function LootMixin:Refresh()
end

function LootMixin:OnLootFrameUpdateButton(index)
	local numLootItems = LootFrame.numLootItems;
	local numLootToShow = LOOTFRAME_NUMBUTTONS;

	if LootFrame.AutoLootTable then
		numLootItems = #LootFrame.AutoLootTable
	end

	if numLootItems > LOOTFRAME_NUMBUTTONS then
		numLootToShow = numLootToShow - 1
	end

	local button = _G["LootButton"..index];
	local slot = (numLootToShow * (LootFrame.page - 1)) + index;
	if slot <= numLootItems then
		if ((LootSlotHasItem(slot) or (LootFrame.AutoLootTable and LootFrame.AutoLootTable[slot])) and index <= numLootToShow) then
			local link = GetLootSlotLink(slot)
			if link then
				local item = CaerdonItem:CreateFromItemLink(link)
				CaerdonWardrobe:UpdateButton(button, item, self, {
					locationKey = format("%d", slot),
					index = slot
				}, nil)
			else
				CaerdonWardrobe:ClearButton(button)
			end
		end
	end
end

CaerdonWardrobe:RegisterFeature(LootMixin)
