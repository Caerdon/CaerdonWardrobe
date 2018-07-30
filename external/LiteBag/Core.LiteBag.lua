local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = 'LiteBag'
local Version = nil
if select(4, GetAddOnInfo(addonName)) then
	Version = GetAddOnMetadata(addonName, 'Version')
	CaerdonWardrobe:RegisterAddon(addonName)
end

if Version then
	function UpdateButton(button)
	    local bag = button:GetParent():GetID()
	    local slot = button:GetID()
	    local _, _, _, _, _, _, _, _, _, itemID = GetContainerItemInfo(bag, slot)

		local options = {
			showMogIcon=true, 
			showBindStatus=true,
			showSellables=true,
			iconPosition="TOPRIGHT" 
		}

		CaerdonWardrobe:UpdateButton(itemID, bag, slot, button, options)
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
	    for i, b in ipairs(LiteBagInventoryPanel.itemButtons) do
	        if i > LiteBagInventoryPanel.size then return end
	        LiteBagItemButton_Update(b)
	    end

	end

	function eventFrame:ADDON_LOADED(name)
	end

	function eventFrame:TRANSMOG_COLLECTION_UPDATED()
		RefreshItems()
	end

	hooksecurefunc('LiteBagItemButton_Update', UpdateButton)
end

