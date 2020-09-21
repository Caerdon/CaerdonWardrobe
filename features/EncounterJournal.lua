local EncounterJournalMixin = {}

local version, build, date, tocversion = GetBuildInfo()
local isShadowlands = tonumber(build) > 35700

function EncounterJournalMixin:Init(frame)
	self.frame = frame
end

function EncounterJournalMixin:OnLoad()
	self.frame:RegisterEvent "ADDON_LOADED"
end

function EncounterJournalMixin:SetTooltipItem(tooltip, item, locationInfo)
    -- TODO
    -- tooltip:SetHyperlink(itemLink, classID, specID)
end

function EncounterJournalMixin:ADDON_LOADED(name)
	if name == "Blizzard_EncounterJournal" then
		hooksecurefunc("EncounterJournal_SetLootButton", function (...) self:OnEncounterJournalSetLootButton(...) end)
		self.frame:RegisterEvent "PLAYER_LOOT_SPEC_UPDATED"
	end
end

function CaerdonWardrobeMixin:PLAYER_LOOT_SPEC_UPDATED()
	EncounterJournal_LootUpdate()
end

function EncounterJournalMixin:OnEncounterJournalSetLootButton(item)
	local itemID, encounterID, name, icon, slot, armorType, itemLink;
	if isShadowlands then
		-- local itemInfo = C_EncounterJournal.GetLootInfoByIndex(item.index);
		-- itemLink = itemInfo.link
		-- itemLink = item.link
		itemLink = select(2, GetItemInfo(item.itemID))
	else
		itemID, encounterID, name, icon, slot, armorType, itemLink = EJ_GetLootInfoByIndex(item.index);
	end
	
	local options = {
		iconOffset = 7,
		otherIcon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
		otherIconSize = 20,
		otherIconOffset = 15,
		overridePosition = "TOPLEFT",
		overrideBindingPosition = "LEFT"
	}

	if itemLink then
		CaerdonWardrobe:UpdateButtonLink(itemLink, "EncounterJournal", item, item, options)
	else
		CaerdonWardrobe:ClearButton(item)
	end
end

CaerdonWardrobe:RegisterFeature("EncounterJournal", EncounterJournalMixin)
