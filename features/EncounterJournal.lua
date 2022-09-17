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
		-- TODO: Probably the line below when item sets are enabled / working
		hooksecurefunc(EncounterJournal.LootJournalItems.ItemSetsFrame, "ConfigureItemButton", function (...) self:OnConfigureItemButton(...) end)
		EncounterJournal.searchResults.ScrollBox:RegisterCallback("OnDataRangeChanged", self.OnSearchResultsScrollBoxRangeChanged, self);
		EncounterJournal.encounter.info.LootContainer.ScrollBox:RegisterCallback("OnDataRangeChanged", self.OnLootContainerScrollBoxRangeChanged, self);
		hooksecurefunc("EncounterJournal_UpdateSearchPreview", function (...) self:OnEncounterJournalUpdateSearchPreview(...) end)
		hooksecurefunc("EJSuggestFrame_UpdateRewards", function (...) self:OnEJSuggestFrame_UpdateRewards(...) end)
	end
end

function EncounterJournalMixin:UpdateScrollBox(scrollBox, key, sortPending)
	local index = 1
	scrollBox:ForEachFrame(function(button)
		local options = {
			relativeFrame = button.icon,
			statusOffsetX = 8,
			statusOffsetY = 7
		}

		local itemLink = button.link
		if itemLink then
			local item = CaerdonItem:CreateFromItemLink(itemLink)
			CaerdonWardrobe:UpdateButton(button, item, self, { 
				locationKey = format(key .. "%d", index)
			}, options)
		else
			CaerdonWardrobe:ClearButton(button)
		end
		index = index + 1
	end)
end

function EncounterJournalMixin:OnLootContainerScrollBoxRangeChanged(sortPending)
	self:UpdateScrollBox(EncounterJournal.encounter.info.LootContainer.ScrollBox, "lootItems", sortPending)
end

function EncounterJournalMixin:OnSearchResultsScrollBoxRangeChanged(sortPending)
	self:UpdateScrollBox(EncounterJournal.searchResults.ScrollBox, "searchResults", sortPending)
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

function EncounterJournalMixin:OnEJSuggestFrame_UpdateRewards(suggestion)
	local button = suggestion.reward
	local rewardData = suggestion.reward.data;

	-- TODO: Check out rewardData content to determine if I can hook into this.
	-- Right now have only seen currency (currencyType, currencyQuantity, currencyIcon)
	-- Assuming I may have itemLink based on some other code for now.
	-- DevTools_Dump(rewardData)

	local options = {
		relativeFrame = button.icon,
		statusOffsetX = 8,
		statusOffsetY = 7
	}

	if rewardData then
		local itemLink = rewardData.itemLink
		if itemLink then
			local item = CaerdonItem:CreateFromItemLink(itemLink)
			CaerdonWardrobe:UpdateButton(button, item, self, { 
				locationKey = format("suggestion%d", suggestion.index)
			}, options)
		else
			CaerdonWardrobe:ClearButton(button)
		end
	else
		CaerdonWardrobe:ClearButton(button)
	end
end

function EncounterJournalMixin:OnConfigureItemButton(button)
	local options = {
		relativeFrame = button.icon,
		statusOffsetX = 8,
		statusOffsetY = 7
	}

	-- TODO: Confirm once this is turned on and check if button has an index instead.
	local itemLink = button.itemLink
	if itemLink then
		local item = CaerdonItem:CreateFromItemLink(itemLink)
		CaerdonWardrobe:UpdateButton(button, item, self, { 
			locationKey = format("itemSets%d", button.itemID)
		}, options)
	else
		CaerdonWardrobe:ClearButton(button)
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
