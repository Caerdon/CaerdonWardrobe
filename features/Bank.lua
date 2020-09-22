local BankMixin = {}

function BankMixin:GetName()
	return "Bank"
end

function BankMixin:Init()
	hooksecurefunc("BankFrameItemButton_Update", function(...) self:OnBankItemUpdate(...) end)
	return { "BANKFRAME_OPENED" }
end

function BankMixin:SetTooltipItem(tooltip, item, locationInfo)
	local hasItem, hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
end

function BankMixin:Refresh()
	if BankFrame:IsShown() then
		-- TODO: Handle this
	-- 	if not ignoreDefaultBags then
		for i=1, NUM_BANKGENERIC_SLOTS, 1 do
			button = BankSlotsFrame["Item"..i];
			self:OnBankItemUpdate(button);
		end
	-- 	end
	end
end

function BankMixin:BANKFRAME_OPENED()
	-- TODO: Review if needed
	-- self:Refresh()
end

function BankMixin:OnBankItemUpdate(button)
	local bag = button:GetParent():GetID();
    local slot = button:GetID();

    if bag ~= BANK_CONTAINER or not slot or button.isBag then
        return
	end

	local item = Item:CreateFromBagAndSlot(bag, slot)
	local itemLink = item:GetItemLink()
	if itemLink then
		CaerdonWardrobe:UpdateButtonLink(itemLink, self:GetName(), { bag = bag, slot = slot }, button, { showMogIcon=true, showBindStatus=true, showSellables=true })
	else
		CaerdonWardrobe:ClearButton(button)
	end
end

CaerdonWardrobe:RegisterFeature(BankMixin)
