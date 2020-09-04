local LootMixin, Loot = {}

function LootMixin:OnLoad()
    hooksecurefunc("LootFrame_UpdateButton", function(...) Loot:OnLootFrameUpdateButton(...) end)
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

	local isProcessing = false
	
	local button = _G["LootButton"..index];
	local slot = (numLootToShow * (LootFrame.page - 1)) + index;
	if slot <= numLootItems then
		if ((LootSlotHasItem(slot) or (LootFrame.AutoLootTable and LootFrame.AutoLootTable[slot])) and index <= numLootToShow) then
			-- texture, item, quantity, quality, locked, isQuestItem, questId, isActive = GetLootSlotInfo(slot)
			link = GetLootSlotLink(slot)
			if link then
				local itemID = CaerdonWardrobe:GetItemID(link)
				if itemID then
					isProcessing = true
					CaerdonWardrobe:UpdateButton(itemID, "LootFrame", { index = slot, link = link }, button, nil)
				end
			end
		end
	end

    if not isProcessing then
        CaerdonWardrobe:ClearButton(button)
	end
end


Loot = CreateFromMixins(LootMixin)
Loot:OnLoad()
