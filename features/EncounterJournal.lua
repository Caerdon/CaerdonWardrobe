local EncounterJournalMixin = {}

local version, build, date, tocversion = GetBuildInfo()
local EJ_NUM_SEARCH_PREVIEWS = 5;

function EncounterJournalMixin:GetName()
    return "EncounterJournal"
end

-- A drop is marked by the loot spec chosen, and as not to be had where this toon cannot collect
-- its source or the piece binds when picked up (FeatureMixin.lua, statusRules).
EncounterJournalMixin.statusRules = { otherSpec = true, noLoot = true, noLootBindOnPickup = true }

function EncounterJournalMixin:Init()
    self:WhenAddOnLoaded("Blizzard_EncounterJournal", self.OnEncounterJournalLoaded)
    return { "PLAYER_LOOT_SPEC_UPDATED", "LOOT_JOURNAL_ITEM_UPDATE" }
end

function EncounterJournalMixin:OnEncounterJournalLoaded()
    EncounterJournal.searchResults.ScrollBox:RegisterCallback("OnDataRangeChanged",
        self.OnSearchResultsScrollBoxRangeChanged, self);
    EncounterJournal.encounter.info.LootContainer.ScrollBox:RegisterCallback("OnDataRangeChanged",
        self.OnLootContainerScrollBoxRangeChanged, self);
    hooksecurefunc("EncounterJournal_UpdateSearchPreview",
        function(...) self:OnEncounterJournalUpdateSearchPreview(...) end)
    hooksecurefunc("EJSuggestFrame_UpdateRewards", function(...) self:OnEJSuggestFrame_UpdateRewards(...) end)
    ScrollUtil.AddInitializedFrameCallback(EncounterJournal.LootJournalItems.ItemSetsFrame.ScrollBox,
        function(...) self:OnItemSetsInitializedFrame(...) end, EncounterJournal.LootJournalItems.ItemSetsFrame,
        false)
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
        local itemID = items[j].itemID
        self:Decorate(frame.ItemButtons[j], itemID, {
            locationKey = format("itemset-" .. "%d-%d", elementData.setID, itemID)
        }, options)
    end
end

function EncounterJournalMixin:UpdateScrollBox(scrollBox, key, sortPending)
    local index = 1
    scrollBox:ForEachFrame(function(button)
        -- The list clips 2 px left of a loot row's 42 px icon, which is all this inset lets the
        -- 20 px icon hang out. One the player has made bigger goes inside the icon instead.
        local options = {
            relativeFrame = button.icon,
            statusOffsetX = 8,
            statusOffsetY = 7,
            keepInsideWhenClipped = true
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
        local spec = CaerdonAPI:GetPlayerSpecializationIndex();
        if (spec and classID == select(3, UnitClass("player"))) then
            specID = CaerdonAPI:GetSpecializationInfo(spec, nil, nil, nil, UnitSex("player"));
        else
            specID = -1;
        end
    end

    return C_TooltipInfo.GetHyperlink(item:GetItemLink(), classID, specID)
end

function EncounterJournalMixin:Refresh()
    CaerdonWardrobeFeatureMixin:Refresh(self)
    if EncounterJournal and EncounterJournal:IsShown() then
        -- Re-process visible buttons directly instead of calling EncounterJournal_LootUpdate()
        -- which taints the ScrollBox DataProvider when called from addon code, causing
        -- MoneyFrame arithmetic errors on tooltip hover.
        self:OnLootContainerScrollBoxRangeChanged()
    end
end

-- What this window shows of an item (FeatureMixin.lua, displayRules).
EncounterJournalMixin.displayRules = {
    bindingStatus = true,
    ownIcon = true,
    otherIcon = "EncounterJournal",
    sellableIcon = false,
}

function EncounterJournalMixin:OnEJSuggestFrame_UpdateRewards(suggestion)
    local button = suggestion.reward
    local rewardData = suggestion.reward.data;

    -- rewardData has an itemLink for an item reward (seen in game on retail 12.1.5), or
    -- currencyType / currencyQuantity / currencyIcon. The 30 px icon sits in a ring
    -- (adventureguide-rewardring), so the inset keeps the status icon on it.
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
            local spellID, name, icon, path, typeText, displayInfo, itemID, stype, itemLink =
                EncounterJournal_GetSearchDisplay(index);
            if itemLink then
                -- The default slot look on the preview's 19 px icon, which comes out at the smallest size.
                local options = {
                    relativeFrame = button.icon,
                    statusProminentSize = button.icon and CaerdonWardrobe:GetSlotStatusSize(button.icon:GetSize()) or 13
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
