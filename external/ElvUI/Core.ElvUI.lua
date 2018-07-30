local ADDON_NAME, namespace = ...
local L = namespace.L
local Version = nil
local bagsEnabled = false
local addonName = 'ElvUI'
if select(4, GetAddOnInfo(addonName)) then
	Version = GetAddOnMetadata(addonName, 'Version')
	if ElvUI[1].private.bags.enable then
		CaerdonWardrobe:RegisterAddon(addonName)
		bagsEnabled = true
	end
end

if Version and bagsEnabled then
	local ElvUIBags = ElvUI[1]:GetModule("Bags")

	local function OnUpdateSlot(self, bagID, slotID)
		if (self.Bags[bagID] and self.Bags[bagID].numSlots ~= GetContainerNumSlots(bagID)) or not self.Bags[bagID] or not self.Bags[bagID][slotID] then
			return
		end

		local button = self.Bags[bagID][slotID]
		local bagType = self.Bags[bagID].type

		local itemID
		itemID = GetContainerItemID(bagID, slotID)
		if itemID then
			local options = {
				showMogIcon=true, 
				showBindStatus=true,
				showSellables=true
			}

			CaerdonWardrobe:UpdateButton(itemID, bagID, slotID, button, options)
		else
			CaerdonWardrobe:UpdateButton(nil, bagID, slotID, button, nil)
		end
		

	end

	hooksecurefunc(ElvUIBags, "UpdateSlot", OnUpdateSlot)

	local function OnEvent(self, event, ...)
		local handler = self[event]
		if(handler) then
			handler(self, ...)
		end
	end

	local eventFrame = CreateFrame("FRAME")
	eventFrame:RegisterEvent "TRANSMOG_COLLECTION_UPDATED"
	eventFrame:SetScript("OnEvent", OnEvent)

	function eventFrame:TRANSMOG_COLLECTION_UPDATED()
		ElvUIBags:UpdateAllBagSlots()
	end
end