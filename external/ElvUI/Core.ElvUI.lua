local isBagUpdateRequested = false
local waitingOnBagUpdate = {}

local ADDON_NAME, namespace = ...
local L = namespace.L
local Version = nil
local bagsEnabled = false
local addonName = 'ElvUI'

if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		if ElvUI[1].private.bags.enable then
			Version = GetAddOnMetadata(addonName, 'Version')
			CaerdonWardrobe:RegisterAddon(addonName)
			bagsEnabled = true
		end
	end
end

if Version then
	local ElvUIBags = ElvUI[1]:GetModule("Bags")

	local function OnUpdateSlot(self, frame, bagID, slotID)
		if (frame.Bags[bagID] and frame.Bags[bagID].numSlots ~= GetContainerNumSlots(bagID)) or not frame.Bags[bagID] or not frame.Bags[bagID][slotID] then
			return
		end

		local button = frame.Bags[bagID][slotID]
		local bagType = frame.Bags[bagID].type

		local itemLink = GetContainerItemLink(bagID, slotID)

		-- TODO: Add support for separate bank and bag sizes
		-- local iconSize = isBank and ElvUIBags.db.bankSize or ElvUIBags.db.bagSize
		-- local uiScale = ElvUI[1].global.general.UIScale
		local iconSize = ElvUIBags.db.bagSize
		CaerdonWardrobe:UpdateButtonLink(itemLink, bagID, slotID, button, {
			showMogIcon = true,
			showBindStatus = true,
			showSellables = true,
			iconSize = iconSize,
			otherIconSize = iconSize,
			-- TODO: These aren't correct but hopefully work for now
			iconOffset = math.abs(40 - iconSize) / 2,
			otherIconOffset = math.abs(40 - iconSize) / 2
		})
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
			hooksecurefunc(ElvUIBags, "UpdateSlot", OnUpdateSlot)

			function eventFrame:TRANSMOG_COLLECTION_UPDATED()
				RefreshItems()
			end
		end
	end

	hooksecurefunc(ElvUIBags, "Initialize", OnInitialize)
end
