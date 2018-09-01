local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = 'LiteBag'
local Version = nil
if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		CaerdonWardrobe:RegisterAddon(addonName)
		Version = GetAddOnMetadata(addonName, 'Version')
	end
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

    LiteBagItemButton_RegisterHook('LiteBagItemButton_Update', UpdateButton)
    LiteBagPanel_AddUpdateEvent('TRANSMOG_COLLECTION_UPDATED')
end
