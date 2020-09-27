local BagsMixin = {}

function BagsMixin:GetName()
	return "Bags"
end

function BagsMixin:Init()
	hooksecurefunc("ContainerFrame_Update", function(...) self:OnContainerFrame_Update(...) end)
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
	if ( IsAnyBagOpen() ) then
		ContainerFrame_UpdateAll();
	end
end

function BagsMixin:OnContainerFrame_Update(frame)
	local bag = frame:GetID()
	local size = ContainerFrame_GetContainerNumSlots(bag)
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

CaerdonWardrobe:RegisterFeature(BagsMixin)
