local BagsMixin = {}

local BAGUPDATE_INTERVAL = 0.1

function BagsMixin:GetName()
	return "Bags"
end

function BagsMixin:Init()
	self.waitingOnBagUpdate = {}
	self.waitingOnBagUpdate[tostring(BACKPACK_CONTAINER)] = true -- backpack doesn't fire BAG_UPDATE initially

	return { "BAG_UPDATE", "BAG_UPDATE_DELAYED" }
end

function BagsMixin:BAG_UPDATE(bagID)
	if bagID >= 0 and bagID <= NUM_BAG_SLOTS then
		self:AddBagUpdateRequest(bagID)
	end
end

function BagsMixin:BAG_UPDATE_DELAYED()
	self.isBagUpdateRequested = true
end

function BagsMixin:SetTooltipItem(tooltip, item, locationInfo)
	local hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetBagItem(locationInfo.bag, locationInfo.slot)
end

function BagsMixin:Refresh()
	-- TODO: Will we get a BAG_UPDATE event for transmog?
	-- If so, may not need this for that, at least (maybe still binding text)
	for i=0, NUM_BAG_SLOTS do
		self.waitingOnBagUpdate[tostring(i)] = true
		self.isBagUpdateRequested = true
	end
end

function BagsMixin:OnUpdate(elapsed)
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

-- TODO: Shouldn't need OnUpdate - can fire coroutine from BAG_UPDATE_DELAYED and Refresh
function BagsMixin:OnBagUpdate_Coroutine()
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

function BagsMixin:AddBagUpdateRequest(bagID)
	self.waitingOnBagUpdate[tostring(bagID)] = true
end

function BagsMixin:OnContainerUpdate(frame, asyncUpdate)
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

CaerdonWardrobe:RegisterFeature(BagsMixin)
