local isBagUpdateRequested = false
local waitingOnBagUpdate = {}

local ADDON_NAME, namespace = ...
local L = namespace.L
local Version = nil
local bagsEnabled = false
local addonName = 'ElvUI'
local ElvUIBags = ElvUI[1]:GetModule("Bags")

if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		if ElvUI[1].private.bags.enable then
			Version = GetAddOnMetadata(addonName, 'Version')
			CaerdonWardrobe:RegisterAddon(addonName)
			bagsEnabled = true
		end
	end
end

if Version then
	local function OnBagUpdate_Coroutine()
			-- TODO: Add support for separate bank and bag sizes
			-- local iconSize = isBank and ElvUIBags.db.bankSize or ElvUIBags.db.bagSize
			-- local uiScale = ElvUI[1].global.general.UIScale
			local iconSize = ElvUIBags.db.bagSize
	    for bag, bagData in pairs(waitingOnBagUpdate) do
	    	for slot, slotData in pairs(bagData) do
	    		for itemID, itemData in pairs(slotData) do
						CaerdonWardrobe:UpdateButton(itemData.itemID, itemData.bag, itemData.slot, itemData.button, {
							showMogIcon = true,
							showBindStatus = true,
							showSellables = true,
							iconSize = iconSize,
							otherIconSize = iconSize,
							-- TODO: These aren't correct but hopefully work for now
							iconOffset = math.abs(40 - iconSize) / 2,
							otherIconOffset = math.abs(40 - iconSize) / 2
						})
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

	local function OnUpdateSlot(self, frame, bagID, slotID)
		if (frame.Bags[bagID] and frame.Bags[bagID].numSlots ~= GetContainerNumSlots(bagID)) or not frame.Bags[bagID] or not frame.Bags[bagID][slotID] then
			return
		end

		local button = frame.Bags[bagID][slotID]
		local bagType = frame.Bags[bagID].type

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
			local waitBag = waitingOnBagUpdate[tostring(bagID)]
			if waitBag then
				-- Clear out in case we had scheduled an update
				-- (Mostly an issue during sorting)
				waitBag[tostring(slotID)] = nil
			end
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
			hooksecurefunc(ElvUIBags, "UpdateSlot", OnUpdateSlot)
			-- Causing issues in 11.20 - might not need anymore but leaving as a reminder
			-- if new issues crop up
			-- hooksecurefunc(ElvUI_ContainerFrame, "UpdateSlot", OnUpdateSlot)

			function eventFrame:TRANSMOG_COLLECTION_UPDATED()
				RefreshItems()
			end
		end
	end

	hooksecurefunc(ElvUIBags, "Initialize", OnInitialize)
end