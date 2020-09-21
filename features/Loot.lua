local LootMixin = {}

function LootMixin:Init(frame)
	self.frame = frame
end

function LootMixin:OnLoad()
    hooksecurefunc("LootFrame_UpdateButton", function(...) self:OnLootFrameUpdateButton(...) end)
end

function LootMixin:SetTooltipItem(tooltip, item, locationInfo)
	tooltip:SetLootItem(locationInfo.index)
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
			link = GetLootSlotLink(slot)
			CaerdonWardrobe:UpdateButtonLink(link, "LootFrame", { index = slot, link = link }, button, nil)
		end
	end
end

CaerdonWardrobe:RegisterFeature("Loot", LootMixin)
