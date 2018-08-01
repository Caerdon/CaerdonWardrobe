local ADDON_NAME, namespace = ...
local L = namespace.L

StaticPopupDialogs["CAERDON_WARDROBE_CARGBAGS_NOT_SUPPORTED"] = {
  text = "I'd love to add support for Caerdon Wardrobe to cargBags, but I need some assistance identifying how to do so.  If you can help, please reach out to me!",
  button1 = "Got it!",
  OnAccept = function()
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
}		

local addonName = 'cargBags_Nivaya'
local Version = nil
if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		Version = GetAddOnMetadata(addonName, 'Version')
		if not Version then
			Version = 'Unknown'
		end
		StaticPopup_Show("CAERDON_WARDROBE_CARGBAGS_NOT_SUPPORTED")
		-- CaerdonWardrobe:RegisterAddon(addonName)
	end
end

if Version then
	local function UpdateSlot(bagID, slotID)
		local item = Nivaya:GetItemInfo(bagID, slotID)
		local button = Nivaya:GetButton(bagID, slotID)
		local options = {
			showMogIcon=true, 
			showBindStatus=true,
			showSellables=true,
			iconPosition="TOPRIGHT" 
		}

		-- CaerdonWardrobe:UpdateButton(itemID, bagID, slotID, button, options)
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
	-- hooksecurefunc(Nivaya, 'UpdateSlot', UpdateSlot)

	local function RefreshItems()
	end

	function eventFrame:ADDON_LOADED(name)
	end

	function eventFrame:TRANSMOG_COLLECTION_UPDATED()
		RefreshItems()
	end

end

