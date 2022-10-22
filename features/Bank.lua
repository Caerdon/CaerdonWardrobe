local BankMixin = {}

function BankMixin:GetName()
	return "Bank"
end

function BankMixin:Init()
	hooksecurefunc("BankFrameItemButton_Update", function(...) self:OnBankItemUpdate(...) end)
	-- TODO: Review for better hooks
	hooksecurefunc(ContainerFrame7, "UpdateItems", function(...) self:OnUpdateItems(...) end)
	hooksecurefunc(ContainerFrame7, "UpdateSearchResults", function(...) self:OnUpdateSearchResults(...) end)
	hooksecurefunc(ContainerFrame8, "UpdateItems", function(...) self:OnUpdateItems(...) end)
	hooksecurefunc(ContainerFrame8, "UpdateSearchResults", function(...) self:OnUpdateSearchResults(...) end)
	hooksecurefunc(ContainerFrame9, "UpdateItems", function(...) self:OnUpdateItems(...) end)
	hooksecurefunc(ContainerFrame9, "UpdateSearchResults", function(...) self:OnUpdateSearchResults(...) end)
	hooksecurefunc(ContainerFrame10, "UpdateItems", function(...) self:OnUpdateItems(...) end)
	hooksecurefunc(ContainerFrame10, "UpdateSearchResults", function(...) self:OnUpdateSearchResults(...) end)
	hooksecurefunc(ContainerFrame11, "UpdateItems", function(...) self:OnUpdateItems(...) end)
	hooksecurefunc(ContainerFrame11, "UpdateSearchResults", function(...) self:OnUpdateSearchResults(...) end)
	hooksecurefunc(ContainerFrame12, "UpdateItems", function(...) self:OnUpdateItems(...) end)
	hooksecurefunc(ContainerFrame12, "UpdateSearchResults", function(...) self:OnUpdateSearchResults(...) end)
	hooksecurefunc(ContainerFrame13, "UpdateItems", function(...) self:OnUpdateItems(...) end)
	hooksecurefunc(ContainerFrame13, "UpdateSearchResults", function(...) self:OnUpdateSearchResults(...) end)

	return { "TOOLTIP_DATA_UPDATE" }
end

function BankMixin:TOOLTIP_DATA_UPDATE()
	self:Refresh()
end

function BankMixin:GetTooltipData(item, locationInfo)
	if locationInfo.bag == BANK_CONTAINER then
		return C_TooltipInfo.GetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
	else
		return C_TooltipInfo.GetBagItem(locationInfo.bag, locationInfo.slot)
	end
end

function BankMixin:Refresh()
	for i = NUM_TOTAL_BAG_FRAMES + 2, NUM_CONTAINER_FRAMES, 1 do -- Backpack + Bags + Reagant Bag + 1 gets us to the bank bags
		local frame = _G["ContainerFrame"..i]
		if ( frame:IsShown() ) then
			self:OnUpdateItems(frame)
		end
	end

	if BankFrame:IsShown() then
		BankFrame_UpdateItems(BankFrame);
	end
end

function BankMixin:OnUpdateSearchResults(frame)
	for i, button in frame:EnumerateValidItems() do
		local isFiltered = select(8, C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID()));
		-- local slot, bag = button:GetSlotAndBagID()
		-- local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
		if button.caerdonButton then
			if isFiltered then
				button.caerdonButton.mogStatus:Hide()
				if button.caerdonButton.bindsOnText then
					button.caerdonButton.bindsOnText:Hide()
				end
			else
				button.caerdonButton.mogStatus:Show()
				if button.caerdonButton.bindsOnText then
					button.caerdonButton.bindsOnText:Show()
				end
			end
		end
	end
end

function BankMixin:OnUpdateItems(frame)
	local bag = frame:GetID()
	local size = C_Container.GetContainerNumSlots(bag)

	for buttonIndex = 1, size do
		local button = _G[frame:GetName() .. "Item" .. buttonIndex]
		local slot = button:GetID()

		local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
		CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot }, { showMogIcon = true, showBindStatus = true, showSellables = true })
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
