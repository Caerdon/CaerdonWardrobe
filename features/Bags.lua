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

	EventRegistry:RegisterCallback("ContainerFrame.OpenBag", self.BagOpened, self)

	return { "UNIT_SPELLCAST_SUCCEEDED", "TOOLTIP_DATA_UPDATE" }
end

function BagsMixin:BagOpened(frame, too)
	for i, button in frame:EnumerateValidItems() do
		CaerdonWardrobe:SetItemButtonMogStatusFilter(button, false)
	end
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

function BagsMixin:TOOLTIP_DATA_UPDATE(dataInstanceID)
	if self.refreshTimer then
		self.refreshTimer:Cancel()
	end

	self.refreshTimer = C_Timer.NewTimer(0.1, function ()
		self:Refresh()
	end, 1)
end

function BagsMixin:GetTooltipData(item, locationInfo)
	local tooltipInfo = C_TooltipInfo.GetBagItem(locationInfo.bag, locationInfo.slot)
	return tooltipInfo
end

function BagsMixin:Refresh()
	for i = 1, NUM_TOTAL_BAG_FRAMES + 1, 1 do
		local frame = _G["ContainerFrame"..i]
		if ( frame:IsShown() ) then
			self:OnUpdateItems(frame)
		end
	end

	if ContainerFrameCombinedBags:IsShown() then
		self:OnUpdateItems(ContainerFrameCombinedBags)
	end
end

function BagsMixin:OnUpdateSearchResults(frame)
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

function BagsMixin:OnUpdateItems(frame)
	for i, button in frame:EnumerateValidItems() do
		-- local isFiltered = select(8, C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID()));
		-- button:SetMatchesSearch(not isFiltered);
		local slot, bag = button:GetSlotAndBagID()
		local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
		-- CaerdonAPI:CompareCIMI(self, item, bag, slot)
		CaerdonWardrobe:UpdateButton(button, item, self, {
			bag = bag, 
			slot = slot
		}, { 
		})
	end
end

CaerdonWardrobe:RegisterFeature(BagsMixin)
