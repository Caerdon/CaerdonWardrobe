local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = 'Inventorian'
local Version = nil
if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		Version = GetAddOnMetadata(addonName, 'Version')
		CaerdonWardrobe:RegisterAddon(addonName)
	end
end

if Version then
	local Inventorian = LibStub('AceAddon-3.0'):GetAddon('Inventorian')
	local mod = Inventorian:NewModule("CaerdonWardrobeInventorianUpdate")
	mod.uiName = L["Caerdon Wardrobe Inventorian"]
	mod.uiDesc= L["Identifies transmog appearances that still need to be learned"]

	function mod:OnEnable()
		hooksecurefunc(Inventorian.bag.itemContainer, "UpdateSlot", UpdateBagSlot)
		hooksecurefunc(Inventorian.bank.itemContainer, "UpdateSlot", UpdateBankSlot)
	end

	local function ToIndex(bag, slot)
		return (bag < 0 and bag * 100 - slot) or (bag * 100 + slot)
	end

	function UpdateBagSlot(event, bag, slot)
		local button = Inventorian.bag.itemContainer.items[ToIndex(bag, slot)]
		if button then
			local itemLink = GetContainerItemLink(bag, slot)

			local options = {
				showMogIcon=true, 
				showBindStatus=true,
				showSellables=true,
				iconPosition="TOPRIGHT" 
			}

			if Inventorian.bag:IsCached() then
				-- TODO: Support cache?
				CaerdonWardrobe:ClearButton(button)
			else
				CaerdonWardrobe:UpdateButtonLink(itemLink, bag, slot, button, options)
			end
		end
	end

	function UpdateBankSlot(event, bag, slot)
		local button = Inventorian.bank.itemContainer.items[ToIndex(bag, slot)]
		if button then
			local itemLink = GetContainerItemLink(bag, slot)

			local options = {
				showMogIcon=true, 
				showBindStatus=true,
				showSellables=true,
				iconPosition="TOPRIGHT" 
			}

			if Inventorian.bank:IsCached() then
				-- TODO: Support cache?
				CaerdonWardrobe:ClearButton(button)
			else
				CaerdonWardrobe:UpdateButtonLink(itemLink, bag, slot, button, options)
			end
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

	local function RefreshItems()
	end

	function eventFrame:ADDON_LOADED(name)
	end

	function eventFrame:TRANSMOG_COLLECTION_UPDATED()
		RefreshItems()
	end
end

