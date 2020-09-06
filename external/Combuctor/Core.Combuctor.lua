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

	local function OnUpdateSlot(self)
		local bag, slot = self:GetBag(), self:GetID()

		if bag ~= "vault" then
			local tab = GetCurrentGuildBankTab()
			if atGuild and tab == bag then
				local itemLink = GetGuildBankItemLink(tab, slot)
				bag = "GuildBankFrame"
				slot = { tab = tab, index = slot }
				CaerdonWardrobe:UpdateButtonLink(itemLink, bag, slot, self, { showMogIcon = true, showBindStatus = true, showSellables = true } )
				ScheduleItemUpdate(itemID, bag, slot, self)
			else
				local itemLink = GetContainerItemLink(bag, slot)
				CaerdonWardrobe:UpdateButtonLink(itemLink, bag, slot, self, { showMogIcon = true, showBindStatus = true, showSellables = true } )
			end
		end
	end

	local function OnEvent(self, event, ...)
		local handler = self[event]
		if(handler) then
			handler(self, ...)
		end
	end

	local function HookCombuctor()
		hooksecurefunc(Combuctor.Item, "Update", OnUpdateSlot)
	end

	local eventFrame = CreateFrame("FRAME")

	eventFrame:SetScript("OnEvent", OnEvent)
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
