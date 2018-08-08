local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = 'ArkInventory'
local Version = nil
if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		Version = GetAddOnMetadata(addonName, 'Version')
		CaerdonWardrobe:RegisterAddon(addonName)
	end
end

if Version then

	local function GetItemID(itemLink)
		local itemID

		local petID = tonumber(itemLink:match("battlepet:(%d+)"))
		if petID then
			itemID = petID
		else
			itemID = tonumber(itemLink:match("item:(%d+)"))
		end
		return itemID
	end

	-- local function OnSetItemButtonTexture(frame, texture, r, g, b, a, c)
	-- 	if frame and frame.icon then
	-- 		local itemDB = ArkInventory.Frame_Item_GetDB(frame)
	-- 		if itemDB then
	-- 			if itemDB.h and itemDB.bag_id then
	-- 				local itemID = GetItemID(itemDB.h)
	-- 				local bag = ArkInventory.InternalIdToBlizzardBagId(itemDB.loc_id, itemDB.bag_id)
	-- 				local slot = itemDB.slot_id

	-- 				if slot then
	-- 					if itemDB.loc_id == ArkInventory.Const.Location.Vault then
	-- 						local tab = ArkInventory.Global.Location[itemDB.loc_id].current_tab
	-- 						bag = "GuildBankFrame"
	-- 						slot = {tab = tab, index = slot}
	-- 					end

	-- 					local options = {
	-- 						showMogIcon=true, 
	-- 						showBindStatus=true,
	-- 						showSellables=true
	-- 					}

	-- 					CaerdonWardrobe:UpdateButton(itemID, bag, slot, frame, options)
	-- 				end
	-- 			else
	-- 				CaerdonWardrobe:UpdateButton(nil, bag, slot, frame, options)
	-- 			end
	-- 		end
	-- 	end
	-- end

	-- Disabling in favor of Frame_Item_Update as it seems to happen less
	-- and appears to be working.  Keeping around in case it causes any
	-- side effects I'm unaware of.
	-- hooksecurefunc(ArkInventory, "SetItemButtonTexture", OnSetItemButtonTexture)

	local function OnFrameItemUpdate(loc_id, bag_id, slot_id)
		local framename = ArkInventory.ContainerItemNameGet(loc_id, bag_id, slot_id)
		local frame = _G[framename]
		if frame and not ArkInventory.Global.Location[loc_id].isOffline then
			local itemDB = ArkInventory.Frame_Item_GetDB(frame)	
			if itemDB then
				if itemDB.h and itemDB.bag_id then
					local itemID = GetItemID(itemDB.h)
					local bag = ArkInventory.InternalIdToBlizzardBagId(itemDB.loc_id, itemDB.bag_id)
					local slot = itemDB.slot_id

					if slot then
						if itemDB.loc_id == ArkInventory.Const.Location.Vault then
							local tab = ArkInventory.Global.Location[itemDB.loc_id].view_tab
							bag = "GuildBankFrame"
							slot = {tab = tab, index = slot}
						end

						local options = {
							showMogIcon=true, 
							showBindStatus=true,
							showSellables=true
						}

						CaerdonWardrobe:UpdateButton(itemID, bag, slot, frame, options)
					end
				else
					CaerdonWardrobe:UpdateButton(nil, bag, slot, frame, options)
				end
			end
		end
	end

	hooksecurefunc(ArkInventory, "Frame_Item_Update", OnFrameItemUpdate)


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
		ArkInventory.ItemCacheClear( )
		ArkInventory.Frame_Main_Generate( nil, ArkInventory.Const.Window.Draw.Recalculate )
	end

	function eventFrame:ADDON_LOADED(name)
	end

	function eventFrame:TRANSMOG_COLLECTION_UPDATED()
		RefreshItems()
	end
end