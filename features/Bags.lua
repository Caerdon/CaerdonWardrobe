local BagsMixin = {}

function BagsMixin:GetName()
	return "Bags"
end

function BagsMixin:Init()
	-- TODO: Review for better hooks
	hooksecurefunc(ContainerFrame1, "UpdateItems", function(...) self:OnUpdateItems(...) end)
	hooksecurefunc(ContainerFrame1, "UpdateSearchResults", function(...) self:OnUpdateSearchResults(...) end)
	hooksecurefunc(ContainerFrame2, "UpdateItems", function(...) self:OnUpdateItems(...) end)
	hooksecurefunc(ContainerFrame2, "UpdateSearchResults", function(...) self:OnUpdateSearchResults(...) end)
	hooksecurefunc(ContainerFrame3, "UpdateItems", function(...) self:OnUpdateItems(...) end)
	hooksecurefunc(ContainerFrame3, "UpdateSearchResults", function(...) self:OnUpdateSearchResults(...) end)
	hooksecurefunc(ContainerFrame4, "UpdateItems", function(...) self:OnUpdateItems(...) end)
	hooksecurefunc(ContainerFrame4, "UpdateSearchResults", function(...) self:OnUpdateSearchResults(...) end)
	hooksecurefunc(ContainerFrame5, "UpdateItems", function(...) self:OnUpdateItems(...) end)
	hooksecurefunc(ContainerFrame5, "UpdateSearchResults", function(...) self:OnUpdateSearchResults(...) end)
	hooksecurefunc(ContainerFrame6, "UpdateItems", function(...) self:OnUpdateItems(...) end)
	hooksecurefunc(ContainerFrame6, "UpdateSearchResults", function(...) self:OnUpdateSearchResults(...) end)
	hooksecurefunc(ContainerFrameCombinedBags, "UpdateItems", function(...) self:OnUpdateItems(...) end)
	hooksecurefunc(ContainerFrameCombinedBags, "UpdateSearchResults", function(...) self:OnUpdateSearchResults(...) end)

	return { "UNIT_SPELLCAST_SUCCEEDED" }
end

function BagsMixin:UNIT_SPELLCAST_SUCCEEDED(unitTarget, castGUID, spellID)
	if unitTarget == "player" then
		-- Tracking unlock spells to know to refresh
		-- May have to add some other abilities but this is a good place to start.
		if spellID == 1804 then
			C_Timer.After(0.1, function()
				self:Refresh()
			end)
		end
	end
end

function BagsMixin:SetTooltipItem(tooltip, item, locationInfo)
	local hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetBagItem(locationInfo.bag, locationInfo.slot)
end

function BagsMixin:Refresh()
	for i = 1, NUM_TOTAL_BAG_FRAMES + 1, 1 do
		local frame = _G["ContainerFrame"..i]
		if ( frame:IsShown() ) then
			self:OnUpdateItems(frame)
		end
	end
end

function BagsMixin:OnUpdateSearchResults(frame)
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

function BagsMixin:OnUpdateItems(frame)
	if frame:IsCombinedBagContainer() then
		for i, button in frame:EnumerateValidItems() do
			-- local isFiltered = select(8, C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID()));
			-- button:SetMatchesSearch(not isFiltered);
			local slot, bag = button:GetSlotAndBagID()
			local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
			CaerdonWardrobe:UpdateButton(button, item, self, {
				bag = bag, 
				slot = slot
			}, { 
				showMogIcon = true, 
				showBindStatus = true, 
				showSellables = true
			})
		end
	else
		local bag = frame:GetID()
		local size = C_Container.GetContainerNumSlots(bag)
		for buttonIndex = 1, size do
			local button = _G[frame:GetName() .. "Item" .. buttonIndex]
			local slot = button:GetID()

			local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
			CaerdonWardrobe:UpdateButton(button, item, self, {
				bag = bag, 
				slot = slot
			}, { 
				showMogIcon = true, 
				showBindStatus = true, 
				showSellables = true
			})
		end
	end
end

CaerdonWardrobe:RegisterFeature(BagsMixin)
