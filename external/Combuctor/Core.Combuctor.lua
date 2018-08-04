local isBagUpdateRequested = false
local waitingOnBagUpdate = {}
local atGuild = false

local addonName = 'Combuctor'
local Version = nil
if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		Version = GetAddOnMetadata(addonName, 'Version')
		-- Go ahead and hook into the default bags as well since Combuctor allows a mix.
		CaerdonWardrobe:RegisterAddon(addonName, { isBags = true, hookDefaultBags = true })
	end
end

if Version then

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

	local function OnUpdateSlot(self)
		-- if not self:IsCached() then
			local bag, slot = self:GetBag(), self:GetID()

			if bag ~= "vault" then
				local tab = GetCurrentGuildBankTab()
				if atGuild and tab == bag then
					local itemLink = GetGuildBankItemLink(tab, slot)
					if itemLink then
						local itemID = tonumber(itemLink:match("item:(%d+)"))
						bag = "GuildBankFrame"
						slot = { tab = tab, index = slot }
						ScheduleItemUpdate(itemID, bag, slot, self)
					else
						CaerdonWardrobe:ClearButton(self)
					end
				else
					local itemID = GetContainerItemID(bag, slot)
					if itemID then
						ScheduleItemUpdate(itemID, bag, slot, self)
					else
						CaerdonWardrobe:ClearButton(self)
					end
				end
			end
		-- end
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


	local function HookCombuctor()
		hooksecurefunc(Combuctor.ItemSlot, "Update", OnUpdateSlot)
	end

	local eventFrame = CreateFrame("FRAME")

	eventFrame:SetScript("OnEvent", OnEvent)
	eventFrame:SetScript("OnUpdate", OnUpdate)
	-- eventFrame:RegisterEvent("TRANSMOG_COLLECTION_ITEM_UPDATE")

	HookCombuctor()

	function eventFrame:ADDON_LOADED(name)
	end

	function eventFrame:TRANSMOG_COLLECTION_ITEM_UPDATE()
	    if Combuctor.sets then
	        Combuctor:UpdateFrames()
	    end
	end

	function eventFrame:GUILDBANKFRAME_OPENED()
		atGuild = true
	end

	function eventFrame:GUILDBANKFRAME_CLOSED()
		atGuild = false
	end

end