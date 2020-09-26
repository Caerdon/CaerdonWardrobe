local EncounterJournalMixin = {}

local version, build, date, tocversion = GetBuildInfo()
local isShadowlands = tonumber(build) > 35700

function EncounterJournalMixin:GetName()
	return "EncounterJournal"
end

function EncounterJournalMixin:Init()
	return { "ADDON_LOADED", "PLAYER_LOOT_SPEC_UPDATED" }
end

function EncounterJournalMixin:ADDON_LOADED(name)
	if name == "Blizzard_EncounterJournal" then
		hooksecurefunc("EncounterJournal_SetLootButton", function (...) self:OnEncounterJournalSetLootButton(...) end)
	end
end

function EncounterJournalMixin:PLAYER_LOOT_SPEC_UPDATED()
	self:Refresh()
end

function EncounterJournalMixin:SetTooltipItem(tooltip, item, locationInfo)
	local classID, specID = EJ_GetLootFilter();

	if (specID == 0) then
		local spec = GetSpecialization();
		if (spec and classID == select(3, UnitClass("player"))) then
			specID = GetSpecializationInfo(spec, nil, nil, nil, UnitSex("player"));
		else
			specID = -1;
		end
	end

    tooltip:SetHyperlink(item:GetItemLink(), classID, specID)
end

function EncounterJournalMixin:Refresh()
	if EncounterJournal and EncounterJournal:IsShown() then
		EncounterJournal_LootUpdate()
	end
end

function EncounterJournalMixin:OnEncounterJournalSetLootButton(button)
	local itemID, encounterID, name, icon, slot, armorType, itemLink;
	if isShadowlands then
		-- local itemInfo = C_EncounterJournal.GetLootInfoByIndex(item.index);
		-- itemLink = itemInfo.link
		-- itemLink = item.link
		itemLink = select(2, GetItemInfo(button.itemID))
	else
		itemID, encounterID, name, icon, slot, armorType, itemLink = EJ_GetLootInfoByIndex(button.index);
	end
	
	local options = {
		relativeFrame = button.icon,
		statusOffsetX = 8,
		statusOffsetY = 7
	}

	if itemLink then
		local item = CaerdonItem:CreateFromItemLink(itemLink)
		CaerdonWardrobe:UpdateButton(button, item, self, { }, options)
	else
		CaerdonWardrobe:ClearButton(button)
	end
end

CaerdonWardrobe:RegisterFeature(EncounterJournalMixin)
