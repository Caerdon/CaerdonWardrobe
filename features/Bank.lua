local BankMixin = {}

function BankMixin:GetName()
	return "Bank"
end

function BankMixin:Init()
	hooksecurefunc("BankFrameItemButton_Update", function(...) self:OnBankItemUpdate(...) end)
	hooksecurefunc("ContainerFrame_Update", function(...) self:OnContainerFrame_Update(...) end)
end

function BankMixin:SetTooltipItem(tooltip, item, locationInfo)
	if locationInfo.bag == BANK_CONTAINER then
		local hasItem, hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
	else
		local hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetBagItem(locationInfo.bag, locationInfo.slot)
	end
end

function BankMixin:Refresh()
	for i = 1, NUM_CONTAINER_FRAMES, 1 do
		local frame = _G["ContainerFrame"..i]
		if ( frame:IsShown() ) then
			self:OnContainerFrame_Update(frame)
		end
	end

	if BankFrame:IsShown() then
		BankFrame_UpdateItems(BankFrame);
	end
end

function BankMixin:OnContainerFrame_Update(frame)
	local bag = frame:GetID()
	if bag > NUM_BAG_SLOTS and bag <= NUM_BAG_SLOTS + NUM_BANKBAGSLOTS then
		local size = ContainerFrame_GetContainerNumSlots(bag)

		for buttonIndex = 1, size do
			local button = _G[frame:GetName() .. "Item" .. buttonIndex]
			local slot = button:GetID()

			local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
			CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot }, { showMogIcon = true, showBindStatus = true, showSellables = true })
		end
	end
end

function BankMixin:OnBankItemUpdate(button)
	local bag = button:GetParent():GetID();
    local slot = button:GetID();

    if bag ~= BANK_CONTAINER or not slot or button.isBag then
        return
	end

	local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
	CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot }, { showMogIcon=true, showBindStatus=true, showSellables=true })
end

CaerdonWardrobe:RegisterFeature(BankMixin)
