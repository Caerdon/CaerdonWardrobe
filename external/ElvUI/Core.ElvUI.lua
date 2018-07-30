local isBagUpdateRequested = false
local waitingOnBagUpdate = {}

local ADDON_NAME, namespace = ...
local L = namespace.L
local Version = nil
local bagsEnabled = false
local addonName = 'ElvUI'

if select(4, GetAddOnInfo(addonName)) then
	Version = GetAddOnMetadata(addonName, 'Version')
	if ElvUI and ElvUI[1].private.bags.enable then
		CaerdonWardrobe:RegisterAddon(addonName)
		bagsEnabled = true
	end
end

if Version and bagsEnabled then
	local function OnBagUpdate_Coroutine()
	    for bag, bagData in pairs(waitingOnBagUpdate) do
	    	for slot, slotData in pairs(bagData) do
	    		for itemID, itemData in pairs(slotData) do
					CaerdonWardrobe:UpdateButton(itemData.itemID, itemData.bag, itemData.slot, itemData.button, { showMogIcon = true, showBindStatus = true, showSellables = true } )
	    		end
	    	end

			waitingOnBagUpdate[bag] = nil
	    end

		coroutine.yield()
		waitingOnBagUpdate = {}
	end

	local function ScheduleItemUpdate(itemID, bag, slot, button)
		local waitBag = waitingOnBagUpdate[tostring(bag)]
		if not waitBag then
			waitBag = {}
			waitingOnBagUpdate[tostring(bag)] = waitBag
		end

		local waitSlot = waitBag[tostring(slot)]
		if not waitSlot then
			waitSlot = {}
			waitBag[tostring(slot)] = waitSlot
		end

		waitSlot[tostring(itemID)] = { itemID = itemID, bag = bag, slot = slot, button = button }
		isBagUpdateRequested = true
	end

	local ElvUIBags = ElvUI[1]:GetModule("Bags")

	local function OnUpdateSlot(self, bagID, slotID)
		if (self.Bags[bagID] and self.Bags[bagID].numSlots ~= GetContainerNumSlots(bagID)) or not self.Bags[bagID] or not self.Bags[bagID][slotID] then
			return
		end

		local button = self.Bags[bagID][slotID]
		local bagType = self.Bags[bagID].type

		local itemID
		itemID = GetContainerItemID(bagID, slotID)
		if itemID then
			local options = {
				showMogIcon=true, 
				showBindStatus=true,
				showSellables=true
			}

			ScheduleItemUpdate(itemID, bagID, slotID, button)
			-- CaerdonWardrobe:UpdateButton(itemID, bagID, slotID, button, options)
		else
			CaerdonWardrobe:ClearButton(button)
			-- CaerdonWardrobe:UpdateButton(nil, bagID, slotID, button, nil)
		end
		

	end

	local function OnEvent(self, event, ...)
		local handler = self[event]
		if(handler) then
			handler(self, ...)
		end
	end

	local timeSinceLastBagUpdate = nil
	local BAGUPDATE_INTERVAL = 0.3

	local function OnUpdate(self, elapsed)
		if(self.bagUpdateCoroutine) then
			if coroutine.status(self.bagUpdateCoroutine) ~= "dead" then
				local ok, result = coroutine.resume(self.bagUpdateCoroutine)
				if not ok then
					error(result)
				end
			else
				self.bagUpdateCoroutine = nil
			end
			return
		end

		if isBagUpdateRequested then
			isBagUpdateRequested = false
			timeSinceLastBagUpdate = 0
		elseif timeSinceLastBagUpdate then
			timeSinceLastBagUpdate = timeSinceLastBagUpdate + elapsed
		end

		if( timeSinceLastBagUpdate ~= nil and (timeSinceLastBagUpdate > BAGUPDATE_INTERVAL) ) then
			timeSinceLastBagUpdate = nil
			self.bagUpdateCoroutine = coroutine.create(OnBagUpdate_Coroutine)
		end
	end

	local function RefreshItems()
		ElvUIBags:UpdateAllBagSlots()
	end

	local eventFrame
	local function OnInitialize()
		if not eventFrame then
			eventFrame = CreateFrame("FRAME")
			eventFrame:RegisterEvent "TRANSMOG_COLLECTION_UPDATED"
			eventFrame:SetScript("OnEvent", OnEvent)
			eventFrame:SetScript("OnUpdate", OnUpdate)
			-- Seem to need both?  Not sure.
			-- First one works if I do it outside OnInitialize.
			-- Second one works in OnIntialize.
			-- There's some branching logic in ElvUI that will call
			-- one or the other, so I probably need both just in case.
			hooksecurefunc(ElvUIBags, "UpdateSlot", OnUpdateSlot)
			hooksecurefunc(ElvUI_ContainerFrame, "UpdateSlot", OnUpdateSlot)

			function eventFrame:TRANSMOG_COLLECTION_UPDATED()
				RefreshItems()
			end
		end
	end

	hooksecurefunc(ElvUIBags, "Initialize", OnInitialize)
end