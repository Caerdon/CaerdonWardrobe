local EncounterJournalMixin = {}

local version, build, date, tocversion = GetBuildInfo()
local EJ_NUM_SEARCH_PREVIEWS = 5;

function EncounterJournalMixin:GetName()
	return "EncounterJournal"
end

function EncounterJournalMixin:Init()
	return { "ADDON_LOADED", "PLAYER_LOOT_SPEC_UPDATED", "LOOT_JOURNAL_ITEM_UPDATE" }
end

function EncounterJournalMixin:ADDON_LOADED(name)
	if name == "Blizzard_EncounterJournal" then
		EncounterJournal.searchResults.ScrollBox:RegisterCallback("OnDataRangeChanged", self.OnSearchResultsScrollBoxRangeChanged, self);
		EncounterJournal.encounter.info.LootContainer.ScrollBox:RegisterCallback("OnDataRangeChanged", self.OnLootContainerScrollBoxRangeChanged, self);
		hooksecurefunc("EncounterJournal_UpdateSearchPreview", function (...) self:OnEncounterJournalUpdateSearchPreview(...) end)
		hooksecurefunc("EJSuggestFrame_UpdateRewards", function (...) self:OnEJSuggestFrame_UpdateRewards(...) end)
		ScrollUtil.AddInitializedFrameCallback(EncounterJournal.LootJournalItems.ItemSetsFrame.ScrollBox, function (...) self:OnItemSetsInitializedFrame(...) end, EncounterJournal.LootJournalItems.ItemSetsFrame, false)
	end
end

function EncounterJournalMixin:LOOT_JOURNAL_ITEM_UPDATE()
	self:Refresh()
end

function EncounterJournalMixin:OnItemSetsInitializedFrame(listFrame, frame, elementData)
	local items = C_LootJournal.GetItemSetItems(elementData.setID)
	table.sort(items, SortItemSetItems);
	for j = #items + 1, #frame.ItemButtons do
		local itemButton = frame.ItemButtons[j];
		CaerdonWardrobe:ClearButton(itemButton)
	end

	local options = {
	}

	for j = 1, #items do
		local itemButton = frame.ItemButtons[j];
		local item = CaerdonItem:CreateFromItemID(items[j].itemID)
		if item:IsItemDataCached() then
			CaerdonWardrobe:UpdateButton(itemButton, item, self, { 
				locationKey = format("itemset-" .. "%d-%d", elementData.setID, item:GetItemID())
			}, options)
		else
			item:ContinueOnItemLoad(function()
				CaerdonWardrobe:UpdateButton(itemButton, item, self, { 
					locationKey = format("itemset-" .. "%d-%d", elementData.setID, item:GetItemID())
				}, options)
			end)
		end
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

-- function EncounterJournalMixin:PLAYER_LOOT_SPEC_UPDATED()
-- 	self:Refresh()
-- end

function EncounterJournalMixin:GetTooltipData(item, locationInfo)
	local classID, specID = EJ_GetLootFilter();

	if (specID == 0) then
		local spec = GetSpecialization();
		if (spec and classID == select(3, UnitClass("player"))) then
			specID = GetSpecializationInfo(spec, nil, nil, nil, UnitSex("player"));
		else
			specID = -1;
		end
	end

	return C_TooltipInfo.GetHyperlink(item:GetItemLink(), classID, specID)
end

function EncounterJournalMixin:Refresh()
	if EncounterJournal and EncounterJournal:IsShown() then
		EncounterJournal_LootUpdate()
	end
end

function EncounterJournalMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	return {
		bindingStatus = {
			shouldShow = true
		},
		ownIcon = {
			shouldShow = true
		},
		otherIcon = {
			shouldShow = true
		},
		questIcon = {
			shouldShow = true
		},
		oldExpansionIcon = {
			shouldShow = true
		},
        sellableIcon = {
            shouldShow = false
        }
	}
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
	-- local itemLink = button.itemLink
	if button.itemID then
		local _, itemLink, itemQuality = C_Item.GetItemInfo(button.itemID);
		-- print(itemLink)
		if itemLink then
			local item = CaerdonItem:CreateFromItemLink(itemLink)
			CaerdonWardrobe:UpdateButton(button, item, self, { 
				locationKey = format("itemSets%d", button.itemID)
			}, options)
		else
			CaerdonWardrobe:ClearButton(button)
		end
	end
end

function EncounterJournalMixin:OnEncounterJournalUpdateSearchPreview()
	if not EncounterJournal.searchBox:IsCurrentTextValidForSearch() then
		return;
	end

	local numResults = EJ_GetNumSearchResults();
	if numResults == 0 and EJ_IsSearchFinished() then
		return;
	end

	local lastShown = EncounterJournal.searchBox;
	for index, button in ipairs(EncounterJournal.searchBox:GetButtons()) do
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
