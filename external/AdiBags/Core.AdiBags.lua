local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = 'AdiBags'
local Version = nil
if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		Version = GetAddOnMetadata(addonName, 'Version')
		CaerdonWardrobe:RegisterAddon(addonName)
	end
end

if Version then
	local AdiBags = LibStub('AceAddon-3.0'):GetAddon('AdiBags')
	local mod = AdiBags:NewModule("CaerdonWardrobeAdiBagsUpdate", "ABEvent-1.0")
	mod.uiName = L["Caerdon Wardrobe"]
	mod.uiDesc= L["Identifies transmog appearances that still need to be learned"]

	function mod:OnEnable()
		self:RegisterMessage('AdiBags_UpdateButton', 'UpdateButton')
	end

	function mod:UpdateButton(event, button)
		local itemLink = button.itemLink
		local bag = button.bag
		local slot = button.slot

		local options = {
			showMogIcon=true, 
			showBindStatus=true,
			showSellables=true,
			iconPosition="TOPRIGHT" 
		}

		CaerdonWardrobe:UpdateButtonLink(itemLink, bag, slot, button, options)
	end

	local function OnEvent(self, event, ...)
		local handler = self[event]
		if(handler) then
			handler(self, ...)
		end
	end

	local eventFrame = CreateFrame("FRAME")
	eventFrame:RegisterEvent "ADDON_LOADED"
	eventFrame:RegisterEvent "TRANSMOG_COLLECTION_UPDATED"
	eventFrame:SetScript("OnEvent", OnEvent)

	local function RefreshItems()
		mod:SendMessage('AdiBags_FiltersChanged')
	end

	function eventFrame:ADDON_LOADED(name)
	end

	function eventFrame:TRANSMOG_COLLECTION_UPDATED()
		RefreshItems()
	end
end

