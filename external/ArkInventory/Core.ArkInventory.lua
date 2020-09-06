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

	local function OnFrameItemUpdate(frame, loc_id, bag_id, slot_id)
		local bag = ArkInventory.API.InternalIdToBlizzardBagId(loc_id, bag_id)
		local slot = slot_id
		
		if not ArkInventory.API.LocationIsOffline(loc_id) then
			local itemDB = ArkInventory.API.ItemFrameItemTableGet(frame)
			local itemLink = itemDB and itemDB.h

			-- ArkInventory creates invalid hyperlinks for caged battle pets - fix 'em up for now
			if ( itemLink and strfind(itemLink, "battlepet:") ) then
				local _, speciesID, level, quality, health, power, speed, battlePetID = strsplit(":", itemLink);
				local name, icon, petType, creatureID, sourceText, description, isWild, canBattle, tradable, unique, _, displayID = C_PetJournal.GetPetInfoBySpeciesID(speciesID);
	
				if battlePetID == name then
					battlePetID = "0"
				end

				itemLink = string.format("%s|Hbattlepet:%s:%s:%s:%s:%s:%s:%s|h[%s]|h|r", YELLOW_FONT_COLOR_CODE, speciesID, level, quality, health, power, speed, battlePetID, name)
			end
	
			if loc_id == ArkInventory.Const.Location.Vault then
				local tab = ArkInventory.Global.Location[loc_id].view_tab
				bag = "GuildBankFrame"
				slot = {tab = tab, index = slot}
			end

			local options = {
				showMogIcon=true, 
				showBindStatus=true,
				showSellables=true
			}

			CaerdonWardrobe:UpdateButtonLink(itemLink, bag, slot, frame, options)
		else
			-- TODO: Add offline support?
			CaerdonWardrobe:ClearButton(frame)
		end
	end

	hooksecurefunc(ArkInventory.API, "ItemFrameUpdated", OnFrameItemUpdate)

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