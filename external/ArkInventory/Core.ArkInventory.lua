local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "ArkInventory"
local ArkInventoryMixin = {}

function ArkInventoryMixin:GetName()
    return addonName
end

function ArkInventoryMixin:Init()
	hooksecurefunc(ArkInventory.API, "ItemFrameUpdated", function(...) self:OnFrameItemUpdate(...) end)
end

function ArkInventoryMixin:GetTooltipInfo(tooltip, item, locationInfo)
	local tooltipInfo
	if locationInfo.isOffline then
		if not item:IsItemEmpty() then
			tooltipInfo = MakeBaseTooltipInfo("GetHyperlink", item:GetItemLink());
		end
	elseif not item:HasItemLocationBankOrBags() then
		tooltipInfo = MakeBaseTooltipInfo("GetGuildBankItem", locationInfo.tab, locationInfo.index);
	elseif locationInfo.bag == BANK_CONTAINER then
		tooltipInfo = MakeBaseTooltipInfo("GetInventoryItem", "player", BankButtonIDToInvSlotID(locationInfo.slot));
	else
		tooltipInfo = MakeBaseTooltipInfo("GetBagItem", locationInfo.bag, locationInfo.slot);
	end

	return tooltipInfo
end

function ArkInventoryMixin:Refresh()
	ArkInventory.ItemCacheClear( )
	ArkInventory.Frame_Main_Generate( nil, ArkInventory.Const.Window.Draw.Recalculate )
end

function ArkInventoryMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	if locationInfo.isOffline then
		local showBindingStatus = CaerdonWardrobeConfig.Binding.ShowStatus.BankAndBags
		local showOwnIcon = CaerdonWardrobeConfig.Icon.ShowLearnable.BankAndBags
		local showOtherIcon = CaerdonWardrobeConfig.Icon.ShowLearnableByOther.BankAndBags
		local showSellableIcon = CaerdonWardrobeConfig.Icon.ShowSellable.BankAndBags
	
		return {
			bindingStatus = {
				shouldShow = showBindingStatus
			},
			ownIcon = {
				shouldShow = showOwnIcon
			},
			otherIcon = {
				shouldShow = showOtherIcon
			},
			sellableIcon = {
				shouldShow = showSellableIcon
			}
		}
	elseif not item:HasItemLocationBankOrBags() then
		return {
			bindingStatus = {
				shouldShow = CaerdonWardrobeConfig.Binding.ShowStatus.GuildBank
			},
			ownIcon = {
				shouldShow = CaerdonWardrobeConfig.Icon.ShowLearnable.GuildBank
			},
			otherIcon = {
				shouldShow = CaerdonWardrobeConfig.Icon.ShowLearnableByOther.GuildBank
			},
			sellableIcon = {
				shouldShow = CaerdonWardrobeConfig.Icon.ShowSellable.GuildBank
			}
		}
	else
		return {}
	end
end

function ArkInventoryMixin:OnFrameItemUpdate(frame, loc_id, bag_id, slot_id)
	C_Timer.After(0.2, function () -- ArkInventory is slow compared to some - doing this until I find a better way - may need tweaked higher
		local bag = ArkInventory.API.InternalIdToBlizzardBagId(loc_id, bag_id)
		local slot = slot_id

		local options = {
			showMogIcon=true, 
			showBindStatus=true,
			showSellables=true
		}
		
		if not ArkInventory.API.LocationIsOffline(loc_id) then
			if loc_id == ArkInventory.Const.Location.Vault then
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
	
				local tab = ArkInventory.Global.Location[loc_id].view_tab
				if itemLink then
					local item = CaerdonItem:CreateFromItemLink(itemLink)
					CaerdonWardrobe:UpdateButton(frame, item, self, {
						locationKey = format("tab%d-index%d", tab, slot),
						tab = tab,
						index = slot
					}, options)
				else
					CaerdonWardrobe:ClearButton(frame)
				end
			else
				local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
				CaerdonWardrobe:UpdateButton(frame, item, self, { bag = bag, slot = slot }, options)
			end
		else
			local itemLink
			local i = ArkInventory.API.ItemFrameItemTableGet( frame )
			if i and i.h then
				itemLink = i.h
			end

			if itemLink then
				local item = CaerdonItem:CreateFromItemLink(itemLink)
				CaerdonWardrobe:UpdateButton(frame, item, self, {
					locationKey = format("bag%d-slot%d", bag, slot),
					isOffline = true
				}, options)
			else
				CaerdonWardrobe:ClearButton(frame)
			end
		end
	end)
end


local Version = nil
local isActive = false

if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		Version = GetAddOnMetadata(addonName, 'Version')
		CaerdonWardrobe:RegisterFeature(ArkInventoryMixin)
		isActive = true
	end
end

WagoAnalytics:Switch(addonName, isActive)
