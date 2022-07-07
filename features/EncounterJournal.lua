local EncounterJournalMixin = {}

local version, build, date, tocversion = GetBuildInfo()
local EJ_NUM_SEARCH_PREVIEWS = 5;

function EncounterJournalMixin:GetName()
	return "EncounterJournal"
end

function EncounterJournalMixin:Init()
	return { "ADDON_LOADED", "PLAYER_LOOT_SPEC_UPDATED" }
end

function EncounterJournalMixin:ADDON_LOADED(name)
	if name == "Blizzard_EncounterJournal" then
		hooksecurefunc("EncounterJournal_SetLootButton", function (...) self:OnEncounterJournalSetLootButton(...) end)
		hooksecurefunc("EncounterJournal_BuildLootItemList", function (...) self:OnEncounterJournalBuildLootItemList(...) end)
		hooksecurefunc("EncounterJournal_SearchUpdate", function (...) self:OnEncounterJournalSearchUpdate(...) end)
		EncounterJournal.searchResults.scrollFrame.scrollBar:HookScript("OnValueChanged", function(...) self:OnEncounterJournalSearchUpdate(...) end)
		hooksecurefunc("EncounterJournal_UpdateSearchPreview", function (...) self:OnEncounterJournalUpdateSearchPreview(...) end)
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


local itemLootCount;

local itemInfoList = {};

-- function EncounterJournalMixin:OnEncounterJournalLootUpdate()
function EncounterJournalMixin:OnEncounterJournalBuildLootItemList()
	itemLootCount = EJ_GetNumLoot()
	itemInfoList = {}
	local bonusItemInfoList = {};

	for i = 1, itemLootCount do
		local itemInfo = C_EncounterJournal.GetLootInfoByIndex(i);
		itemInfo.lootIndex = i;
		if itemInfo.displayAsPerPlayerLoot then
			tinsert(bonusItemInfoList, itemInfo);
		else
			tinsert(itemInfoList, itemInfo);
		end
	end

	local lootDividerItem = {
		name = BONUS_LOOT_TOOLTIP_TITLE,
		icon = nil,
		slot = nil,
		armorType = nil,
		boss = nil,
		type = "divider",
	}

	local lootDividerIndex

	if #bonusItemInfoList > 0 then
		tinsert(itemInfoList, lootDividerItem);

		itemLootCount = itemLootCount + 1;

		lootDividerIndex = #itemInfoList;

		tAppendAll(itemInfoList, bonusItemInfoList);
	else
		lootDividerIndex = nil;
	end
end

function EncounterJournalMixin:OnEncounterJournalSetLootButton(button)
	-- C_Timer.After(0, function ()
		local itemID, encounterID, name, icon, slot, armorType, itemLink;
		local itemInfo = itemInfoList[button.index];
		-- local itemInfo = C_EncounterJournal.GetLootInfoByIndex(button.index)
		if itemInfo.type and itemInfo.type == "divider" then
			-- Ignore, so it will clear
		elseif itemInfo and itemInfo.name then
			-- TODO: There are a few more here if they matter once in Shadowlands
			itemID = itemInfo.itemID
			encounterID = itemInfo.encounterID
			name = itemInfo.name
			icon = itemInfo.icon
			slot = itemInfo.slot
			armorType = itemInfo.armorType
			itemLink = itemInfo.link
		end
		
		local options = {
			relativeFrame = button.icon,
			statusOffsetX = 8,
			statusOffsetY = 7
		}

		if itemLink then
			local item = CaerdonItem:CreateFromItemLink(itemLink)
			CaerdonWardrobe:UpdateButton(button, item, self, { 
				locationKey = format("%d", button.index)
			}, options)
		else
			CaerdonWardrobe:ClearButton(button)
		end
	-- end)
end

function EncounterJournalMixin:OnEncounterJournalSearchUpdate()
	local scrollFrame = EncounterJournal.searchResults.scrollFrame;
	local offset = HybridScrollFrame_GetOffset(scrollFrame);
	local results = scrollFrame.buttons;
	local result, index;


	local numResults = EJ_GetNumSearchResults();

	for i = 1,#results do
		result = results[i];
		index = offset + i;
		if index <= numResults then
			local spellID, name, icon, path, typeText, displayInfo, itemID, stype, itemLink = EncounterJournal_GetSearchDisplay(index);
			if itemLink then
				local options = {
					relativeFrame = result.icon,
					statusOffsetX = 5,
					statusOffsetY = 5
				}
			
				local item = CaerdonItem:CreateFromItemLink(itemLink)
				CaerdonWardrobe:UpdateButton(result, item, self, { 
					locationKey = format("search%d", index)
				}, options)
			else
				CaerdonWardrobe:ClearButton(result)
			end
		else
			CaerdonWardrobe:ClearButton(result)
		end
	end
end

function EncounterJournalMixin:OnEncounterJournalUpdateSearchPreview()
	if strlen(EncounterJournal.searchBox:GetText()) < MIN_CHARACTER_SEARCH then
		return;
	end

	local numResults = EJ_GetNumSearchResults();

	if numResults == 0 and EJ_IsSearchFinished() then
		return;
	end

	local lastShown = EncounterJournal.searchBox;
	for index = 1, EJ_NUM_SEARCH_PREVIEWS do
		local button = EncounterJournal.searchBox.searchPreview[index];
		if index <= numResults then
			local spellID, name, icon, path, typeText, displayInfo, itemID, stype, itemLink = EncounterJournal_GetSearchDisplay(index);
			if itemLink then
				local options = {
					statusProminentSize = 13,
					relativeFrame = button.icon,
					statusOffsetX = 2,
					statusOffsetY = 2
				}
			
				local item = CaerdonItem:CreateFromItemLink(itemLink)
				CaerdonWardrobe:UpdateButton(button, item, self, { 
					locationKey = format("searchPreview%d", index)
				}, options)
			else
				CaerdonWardrobe:ClearButton(button)
			end
		else
			CaerdonWardrobe:ClearButton(button)
		end
	end
end

CaerdonWardrobe:RegisterFeature(EncounterJournalMixin)
