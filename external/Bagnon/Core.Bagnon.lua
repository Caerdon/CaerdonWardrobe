local isBagUpdateRequested = false
local waitingOnBagUpdate = {}

local addonName = 'Bagnon'
local Version = nil
if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		Version = GetAddOnMetadata(addonName, 'Version')
		CaerdonWardrobe:RegisterAddon(addonName)
	end
end

if Version then

	local function OnUpdateSlot(self)
		local bag, slot = self:GetBag(), self:GetID()

		if bag ~= "vault" then
			local tab = GetCurrentGuildBankTab()
			if Bagnon:InGuild() and tab == bag then
				local itemLink = GetGuildBankItemLink(tab, slot)
				bag = "GuildBankFrame"
				slot = { tab = tab, index = slot }
				CaerdonWardrobe:UpdateButtonLink(itemLink, bag, slot, self, { showMogIcon = true, showBindStatus = true, showSellables = true } )
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

	local function HookBagnon()
		hooksecurefunc(Bagnon.Item, "Update", OnUpdateSlot)
	end

	local eventFrame = CreateFrame("FRAME")
	eventFrame:SetScript("OnEvent", OnEvent)
	-- eventFrame:RegisterEvent("TRANSMOG_COLLECTION_ITEM_UPDATE")

	HookBagnon()

	function eventFrame:ADDON_LOADED(name)
	end

	function eventFrame:TRANSMOG_COLLECTION_ITEM_UPDATE()
	    if Bagnon.sets then
	        Bagnon:UpdateFrames()
	    end
	end
end
