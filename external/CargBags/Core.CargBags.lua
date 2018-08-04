local ADDON_NAME, namespace = ...
local L = namespace.L

StaticPopupDialogs["CAERDON_WARDROBE_CARGBAGS_NOT_SUPPORTED"] = {
  text = "cargBags requires a change in cargBags_Nivaya.toc that I've asked the author to make.\n\nUntil it appears in a release, you can add the following to the TOC file manually to get things working: \n\n## X-cargBags: cargBags\n\nYou'll need to exit the game fully (not just logout), make the change, and then re-enter.",
  button1 = "Got it!",
  OnAccept = function()
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
}		

local addonName = 'cargBags_Nivaya'
local cargBags = nil
local Version = nil
if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		local global = GetAddOnMetadata(addonName, 'X-cargBags')
		if global then
			cargBags = _G[global]
		end

		Version = GetAddOnMetadata(addonName, 'Version')
		if not Version then
			Version = 'Unknown'
		end
		if not cargBags then
			StaticPopup_Show("CAERDON_WARDROBE_CARGBAGS_NOT_SUPPORTED")
		else
			CaerdonWardrobe:RegisterAddon(addonName)
		end
	end
end

if Version and cargBags then
	local cbNivaya = cargBags:GetImplementation("Nivaya")

	local function UpdateSlot(self, bagID, slotID)
		local itemID = GetContainerItemID(bagID, slotID)
		local button = self:GetButton(bagID, slotID)
		local options = {
			showMogIcon=true, 
			showBindStatus=true,
			showSellables=true,
			iconPosition="TOPRIGHT" 
		}

		if button then
			CaerdonWardrobe:UpdateButton(itemID, bagID, slotID, button, options)
		end
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
	hooksecurefunc(cbNivaya, 'UpdateSlot', UpdateSlot)

	local function RefreshItems()
	end

	function eventFrame:ADDON_LOADED(name)
	end

	function eventFrame:TRANSMOG_COLLECTION_UPDATED()
		RefreshItems()
	end

end

