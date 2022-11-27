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
	if self.refreshTimer then
		self.refreshTimer:Cancel()
	end

	self.refreshTimer = C_Timer.NewTimer(0.1, function ()
		self:Refresh()
	end, 1)
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
		local isFiltered

		if C_Container and C_Container.GetContainerItemInfo then
			local itemInfo = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
			if itemInfo then
				isFiltered = itemInfo.isFiltered
			end
		else
			_, _, _, _, _, _, _, isFiltered = GetContainerItemInfo(button:GetBagID(), button:GetID())
		end

		CaerdonWardrobe:SetItemButtonMogStatusFilter(button, isFiltered)
	end
end

function BankMixin:OnUpdateItems(frame)
	local bag = frame:GetID()

	local size
	if C_Container and C_Container.GetContainerNumSlots then
		size = C_Container.GetContainerNumSlots(bag)
	else
		size = GetContainerNumSlots(bag)
	end

	for buttonIndex = 1, size do
		local button = _G[frame:GetName() .. "Item" .. buttonIndex]
		local slot = button:GetID()

		local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
		CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot }, { })
	end
end

function BankMixin:OnBankItemUpdate(button)
	local bag = button:GetParent():GetID();
    local slot = button:GetID();

    if bag ~= BANK_CONTAINER or not slot or button.isBag then
        return
	end

	local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
	CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot }, { })
end

CaerdonWardrobe:RegisterFeature(BankMixin)
