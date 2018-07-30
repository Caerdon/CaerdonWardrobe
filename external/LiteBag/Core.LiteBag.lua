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

	hooksecurefunc('LiteBagItemButton_Update', UpdateButton)
    hooksecurefunc('LiteBagPanel_OnShow',
            function (f) f:RegisterEvent("TRANSMOG_COLLECTION_UPDATED") end
        )
    hooksecurefunc('LiteBagPanel_OnHide',
            function (f) f:UnregisterEvent("TRANSMOG_COLLECTION_UPDATED") end
        )
end
