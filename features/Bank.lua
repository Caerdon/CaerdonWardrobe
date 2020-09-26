local BankMixin = {}

function BankMixin:GetName()
	return "Bank"
end

function BankMixin:Init()
	self.waitingOnBagUpdate = {}

	hooksecurefunc("BankFrameItemButton_Update", function(...) self:OnBankItemUpdate(...) end)
	return { "BANKFRAME_OPENED", "BAG_UPDATE", "BAG_UPDATE_DELAYED" }
end

function BankMixin:BANKFRAME_OPENED()
	-- TODO: Review if needed
	-- self:Refresh()
end

function BankMixin:BAG_UPDATE(bagID)
	if bagID > NUM_BAG_SLOTS and bagID <= NUM_BAG_SLOTS + NUM_BANKBAGSLOTS then
		self:AddBagUpdateRequest(bagID)
	end
end

function BankMixin:BAG_UPDATE_DELAYED()
	self.isBagUpdateRequested = true
end

function BankMixin:SetTooltipItem(tooltip, item, locationInfo)
	if locationInfo.bag == BANK_CONTAINER then
		local hasItem, hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
	else
		local hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetBagItem(locationInfo.bag, locationInfo.slot)
	end
end

function BankMixin:Refresh()
	for i=NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do
		self.waitingOnBagUpdate[tostring(i)] = true
		self.isBagUpdateRequested = true
	end	
end

function BankMixin:OnUpdate(elapsed)
	if self.bagUpdateCoroutine then
		if coroutine.status(self.bagUpdateCoroutine) ~= "dead" then
			local ok, result = coroutine.resume(self.bagUpdateCoroutine)
			if not ok then
				error(result)
			end
		else
			self.bagUpdateCoroutine = nil
		end
		return
	elseif self.isBagUpdateRequested then
		self.isBagUpdateRequested = false
		self.bagUpdateCoroutine = coroutine.create(function() self:OnBagUpdate_Coroutine() end)
	end
end

function BankMixin:OnBagUpdate_Coroutine()
	if self.processQueue == nil then
		self.processQueue = {}

		local hasMore = true

		while hasMore do
			coroutine.yield()

			for bagID, shouldUpdate in pairs(self.waitingOnBagUpdate) do
				self.processQueue[bagID] = shouldUpdate
				self.waitingOnBagUpdate[bagID] = nil
			end

			hasMore = false

			for bagID, shouldUpdate in pairs(self.processQueue) do
				local frameID = IsBagOpen(tonumber(bagID))
				if frameID then
					self.processQueue[bagID] = nil
					local frame = _G["ContainerFrame".. frameID]
					self:OnContainerUpdate(frame, true)
					coroutine.yield()
				else -- not open, reschedule
					hasMore = true
					self.waitingOnBagUpdate[bagID] = true
				end
			end
		end

		self.processQueue = nil
	end
end

function BankMixin:AddBagUpdateRequest(bagID)
	self.waitingOnBagUpdate[tostring(bagID)] = true
end

function BankMixin:OnContainerUpdate(frame, asyncUpdate)
	local bag = frame:GetID()
	local size = ContainerFrame_GetContainerNumSlots(bag)

	for buttonIndex = 1, size do
		local button = _G[frame:GetName() .. "Item" .. buttonIndex]
		local slot = button:GetID()

		local itemLink = GetContainerItemLink(bag, slot)
		if itemLink then
			local item = CaerdonItem:CreateFromItemLink(itemLink)
			CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot, isBankOrBags = true }, { showMogIcon = true, showBindStatus = true, showSellables = true })
		else
			CaerdonWardrobe:ClearButton(button)
		end
	end
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
		local item = CaerdonItem:CreateFromItemLink(itemLink)
		CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot, isBankOrBags = true }, { showMogIcon=true, showBindStatus=true, showSellables=true })
	else
		CaerdonWardrobe:ClearButton(button)
	end
end

CaerdonWardrobe:RegisterFeature(BankMixin)
