local ADDON_NAME, namespace = ...
local L = namespace.L
local Version = nil
local bagsEnabled = false
local addonName = 'ElvUI'

if select(4, GetAddOnInfo(addonName)) then
	Version = GetAddOnMetadata(addonName, 'Version')
	if ElvUI and ElvUI[1].private.bags.enable then
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

	local function OnEvent(self, event, ...)
		local handler = self[event]
		if(handler) then
			handler(self, ...)
		end
	end

	local function RefreshItems()
		ElvUIBags:UpdateAllBagSlots()
	end

	local eventFrame
	local function OnInitialize()
		if not eventFrame then
			eventFrame = CreateFrame("FRAME")
			eventFrame:RegisterEvent "TRANSMOG_COLLECTION_UPDATED"
			eventFrame:SetScript("OnEvent", OnEvent)
			-- Seem to need both?  Not sure.
			-- First one works if I do it outside OnInitialize.
			-- Second one works in OnIntialize.
			-- There's some branching logic in ElvUI that will call
			-- one or the other, so I probably need both just in case.
			hooksecurefunc(ElvUIBags, "UpdateSlot", OnUpdateSlot)
			hooksecurefunc(ElvUI_ContainerFrame, "UpdateSlot", OnUpdateSlot)

			function eventFrame:TRANSMOG_COLLECTION_UPDATED()
				RefreshItems()
			end
		end
	end

	hooksecurefunc(ElvUIBags, "Initialize", OnInitialize)
end