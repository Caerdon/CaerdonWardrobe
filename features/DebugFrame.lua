local ADDON_NAME, NS = ...
local L = NS.L

local DebugFrameMixin = {}

local MAX_DEBUG_ENTRIES = 50
local MAX_SHARED_APPEARANCE_DEBUG_ENTRIES = 15
local MAX_SHARED_APPEARANCE_UI_ENTRIES = 12
local APPEARANCE_ITEM_COLLAPSED_HEIGHT = 68
local DETAIL_SECTION_RIGHT_PADDING = 10
local MIN_APPEARANCE_SECTION_WIDTH = 520
local BuildSharedStatusParts
local cancelFuncs = {}

local DEBUG_ENTRY_LABEL_WIDTH = 300
local DEBUG_ENTRY_LABEL_LEFT_PADDING = 12
local DEBUG_ENTRY_VALUE_GAP = 12

local TRANSMOG_USE_ERROR_LABELS = {
    [Enum.TransmogUseErrorType.None] = "None",
    [Enum.TransmogUseErrorType.PlayerCondition] = "Player Condition",
    [Enum.TransmogUseErrorType.Skill] = "Skill",
    [Enum.TransmogUseErrorType.Ability] = "Ability",
    [Enum.TransmogUseErrorType.Reputation] = "Reputation",
    [Enum.TransmogUseErrorType.Holiday] = "Holiday",
    [Enum.TransmogUseErrorType.HotRecheckFailed] = "Hot Recheck Failed",
    [Enum.TransmogUseErrorType.Class] = "Class Restriction",
    [Enum.TransmogUseErrorType.Race] = "Race Restriction",
    [Enum.TransmogUseErrorType.Faction] = "Faction Restriction",
    [Enum.TransmogUseErrorType.ItemProficiency] = "Item Proficiency"
}

local function FormatItemLinkForDebug(itemID, overrideLink)
    if overrideLink then
        return overrideLink
    end

    if not itemID then
        return "Unknown Item"
    end

    local itemName, itemLink = C_Item.GetItemInfo(itemID)
    if itemLink then
        return itemLink
    end

    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end

    if itemName then
        return string.format("[%s] (ItemID %d)", itemName, itemID)
    end

    return string.format("item:%d", itemID)
end

local function FormatSpecIDText(specID)
    if specID == nil then
        return "nil"
    end

    if specID == 0 then
        return "0 (Follow Current Specialization)"
    end

    if type(specID) ~= "number" then
        return tostring(specID)
    end

    local id, name, _, _, _, role, classFile, className = CaerdonAPI:GetSpecializationInfoByID(specID)
    if not id then
        return tostring(specID)
    end

    local roleText = role or "UNKNOWN_ROLE"
    local classText = className or classFile or "Unknown Class"
    return string.format("%s (%s, %s, ID %d)", name or "Unknown Spec", classText, roleText, specID)
end

local function BuildSpecDescriptions(specIDs)
    if type(specIDs) ~= "table" or #specIDs == 0 then
        return nil
    end

    local descriptions = {}
    for _, specID in ipairs(specIDs) do
        table.insert(descriptions, FormatSpecIDText(specID))
    end

    if #descriptions == 0 then
        return nil
    end

    return descriptions
end

local function CopySpecIDs(specIDs)
    if type(specIDs) ~= "table" or #specIDs == 0 then
        return nil
    end

    local copy = {}
    for _, specID in ipairs(specIDs) do
        table.insert(copy, specID)
    end

    if #copy == 0 then
        return nil
    end

    return copy
end

local function CopySourceInfoFields(sourceInfo)
    if type(sourceInfo) ~= "table" then
        return nil
    end

    local copy = {}
    for key, value in pairs(sourceInfo) do
        if type(value) == "table" then
            if key == "relicSlotTypeNames" or key == "drops" then
                copy[key] = #value
            else
                copy[key] = CopySourceInfoFields(value)
            end
        else
            copy[key] = value
        end
    end

    return copy
end

local function EnsureSourceItemLink(sourceID, itemID)
    if not sourceID then
        return nil
    end

    local appearanceSourceInfo = CaerdonAPI and CaerdonAPI.GetAppearanceSourceInfo and
        CaerdonAPI:GetAppearanceSourceInfo(sourceID)
    local itemLink = appearanceSourceInfo and appearanceSourceInfo.itemLink
    if itemLink then
        return itemLink
    end

    if itemID then
        itemLink = select(2, C_Item.GetItemInfo(itemID))
        if itemLink then
            return itemLink
        end

        if C_Item and C_Item.RequestLoadItemDataByID and itemID then
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end

    if CaerdonAPI and CaerdonAPI.GetAppearanceSourceInfo then
        local refreshed = CaerdonAPI:GetAppearanceSourceInfo(sourceID)
        return refreshed and refreshed.itemLink or nil
    end

    return nil
end

local function BuildVariantDescriptorText(data)
    if not data then
        return ""
    end

    local descriptorParts = {}
    if data.itemLevel then
        table.insert(descriptorParts, ("ilvl %d"):format(data.itemLevel))
    end
    if data.variantDifficultyText then
        table.insert(descriptorParts, data.variantDifficultyText)
    end
    if data.variantTierText then
        table.insert(descriptorParts, data.variantTierText)
    end

    if #descriptorParts == 0 then
        return ""
    end

    return " [" .. table.concat(descriptorParts, " - ") .. "]"
end

local function GetDetailedLevelFromLink(itemLink, itemID, sourceInfo, encounterJournalFallback)
    local function GetLinkQuality(link)
        if type(link) ~= "string" then
            return 1
        end

        if link:find("|Hitem:") then
            return 3
        elseif link:find("|Htransmog") then
            return 1
        end

        return 2
    end

    local function TryDetailedLevelWithLink(link, label)
        if not link then
            return nil
        end

        local detailedLevel = C_Item.GetDetailedItemLevelInfo(link)

        if detailedLevel then
            return detailedLevel, GetLinkQuality(link), label or "Linked Item"
        end

        return nil
    end

    if sourceInfo and encounterJournalFallback then
        local ejLink = encounterJournalFallback(sourceInfo)
        if ejLink then
            local ejLevel, ejQuality = TryDetailedLevelWithLink(ejLink, "Encounter Journal")
            if ejLevel then
                return ejLevel, ejQuality, ejLink, "Encounter Journal"
            end
        end
    end

    local detailedLevel, quality = TryDetailedLevelWithLink(itemLink, "Transmog Link")
    if detailedLevel then
        return detailedLevel, quality, itemLink, "Transmog Link"
    end

    if (itemLink or itemID) and C_Item and C_Item.GetItemInfo then
        local baseName, baseLink, _, baseLevel = C_Item.GetItemInfo(itemLink or itemID)
        if baseLevel then
            return baseLevel, 3, baseLink, "C_Item.GetItemInfo"
        end

        if C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end

        if baseLink then
            local fallbackLevel, fallbackQuality = TryDetailedLevelWithLink(baseLink, "C_Item.GetItemInfo Link")
            if fallbackLevel then
                return fallbackLevel, fallbackQuality, baseLink, "C_Item.GetItemInfo Link"
            end
        end
    end

    return nil, 0, nil, nil
end

local function UpdateVariantMetadata(target, sourceInfo, sourceLink, metadataCache, encounterJournalFallback)
    if not target or not sourceInfo then
        return
    end

    local itemLevel, levelQuality, resolvedLink, levelSource = GetDetailedLevelFromLink(sourceLink, sourceInfo.itemID, sourceInfo, encounterJournalFallback)
    if itemLevel then
        local existingQuality = target.itemLevelQuality or 0
        if not target.itemLevel or levelQuality > existingQuality or
            (levelQuality == existingQuality and itemLevel ~= target.itemLevel) then
            target.itemLevel = itemLevel
            target.itemLevelQuality = levelQuality
            target.itemLevelSource = levelSource
        end
    end

    if metadataCache and sourceInfo.sourceID then
        local cacheEntry = metadataCache[sourceInfo.sourceID] or {}
        metadataCache[sourceInfo.sourceID] = cacheEntry
        if target.itemLevel then
            cacheEntry.itemLevel = target.itemLevel
            cacheEntry.itemLevelQuality = target.itemLevelQuality
        end
        if target.itemLevelSource then
            cacheEntry.itemLevelSource = target.itemLevelSource
        end
        if resolvedLink or sourceLink then
            cacheEntry.preferredLink = resolvedLink or sourceLink
        end
    end

    if C_TransmogCollection and C_TransmogCollection.GetAppearanceSourceDrops and sourceInfo.sourceID then
        local needsDifficulty = not target.variantDifficultyText
        local needsTier = not target.variantTierText
        local needsInstance = not target.variantInstanceText
        local needsEncounter = not target.variantEncounterText
        if needsDifficulty or needsTier or needsInstance or needsEncounter then
            local drops = C_TransmogCollection.GetAppearanceSourceDrops(sourceInfo.sourceID)
            if drops then
                for _, dropInfo in ipairs(drops) do
                    if needsDifficulty and dropInfo.difficulties and #dropInfo.difficulties > 0 then
                        target.variantDifficultyText = table.concat(dropInfo.difficulties, " / ")
                        needsDifficulty = false
                    end
                    if needsTier and dropInfo.tiers and #dropInfo.tiers > 0 then
                        target.variantTierText = table.concat(dropInfo.tiers, " / ")
                        needsTier = false
                    end
                    if needsInstance and dropInfo.instance and dropInfo.instance ~= "" then
                        target.variantInstanceText = dropInfo.instance
                        needsInstance = false
                    end
                    if needsEncounter and dropInfo.encounter and dropInfo.encounter ~= "" then
                        target.variantEncounterText = dropInfo.encounter
                        needsEncounter = false
                    end

                    if not needsDifficulty and not needsTier and not needsInstance and not needsEncounter then
                        break
                    end
                end
            end
        end
    end

    if metadataCache and sourceInfo.sourceID then
        local cacheEntry = metadataCache[sourceInfo.sourceID] or {}
        metadataCache[sourceInfo.sourceID] = cacheEntry
        if target.variantDifficultyText then
            cacheEntry.variantDifficultyText = target.variantDifficultyText
        end
        if target.variantTierText then
            cacheEntry.variantTierText = target.variantTierText
        end
        if target.variantInstanceText then
            cacheEntry.variantInstanceText = target.variantInstanceText
        end
        if target.variantEncounterText then
            cacheEntry.variantEncounterText = target.variantEncounterText
        end
    end
end

local function EnsureEncounterJournalLoaded()
    if not (C_EncounterJournal and EJ_GetNumTiers) then
        if not C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then
            C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
        end
    end
end

local EJ_DIFFICULTY_NAME_TO_ID = {
    ["Looking For Raid"] = 17,
    ["Raid Finder"] = 17,
    ["LFR"] = 17,
    ["Normal"] = 14,
    ["Heroic"] = 15,
    ["Mythic"] = 16
}

local function FindEncounterJournalInstanceID(instanceName)
    if not instanceName or instanceName == "" then
        return nil
    end

    EnsureEncounterJournalLoaded()
    if not (C_EncounterJournal and EJ_GetNumTiers) then
        return nil
    end

    local numTiers = EJ_GetNumTiers and EJ_GetNumTiers() or 0
    for tier = 1, numTiers do
        EJ_SelectTier(tier)
        for _, isRaid in ipairs({ true, false }) do
            local index = 1
            while true do
                local instanceID, name = EJ_GetInstanceByIndex(index, isRaid)
                if not instanceID then
                    break
                end
                if name == instanceName then
                    return instanceID
                end
                index = index + 1
            end
        end
    end

    return nil
end

local function FindEncounterJournalEncounterID(instanceID, encounterName)
    if not instanceID or not encounterName or encounterName == "" then
        return nil
    end

    EnsureEncounterJournalLoaded()
    if not EJ_GetEncounterInfoByIndex then
        return nil
    end

    EJ_SelectInstance(instanceID)
    local index = 1
    while true do
        local name, _, encounterID = EJ_GetEncounterInfoByIndex(index)
        if not name then
            break
        end
        if name == encounterName then
            return encounterID
        end
        index = index + 1
    end

    return nil
end

local variantEJDiagnostics = {}

local function RecordEJDiagnostic(sourceID, data)
    if sourceID then
        variantEJDiagnostics[sourceID] = data
    end
end

local function GetEncounterJournalLinkByItemID(sourceInfo, diag)
    if not sourceInfo or not sourceInfo.itemID then
        return nil
    end

    EnsureEncounterJournalLoaded()
    if not C_EncounterJournal or not C_EncounterJournal.GetLootInfo then
        diag.failureReason = "EJUnavailable"
        return nil
    end

    local lootInfo = C_EncounterJournal.GetLootInfo(sourceInfo.itemID)
    if lootInfo and lootInfo.link then
        diag.lootInfoLink = lootInfo.link
        diag.finalLinkSource = "EncounterJournal.GetLootInfo"
        diag.finalLink = lootInfo.link
        return lootInfo.link
    end

    diag.lootInfoLink = lootInfo and lootInfo.link
    return nil
end

local function GetEncounterJournalLinkForSource(sourceInfo)
    if not sourceInfo or not sourceInfo.sourceID then
        return nil
    end

    local diag = {
        itemID = sourceInfo.itemID,
        sourceType = sourceInfo.sourceType,
        sourceID = sourceInfo.sourceID
    }

    if sourceInfo.sourceType ~= Enum.TransmogSource.JournalEncounter then
        diag.note = "NonBossDrop"
    end

    local directLink = GetEncounterJournalLinkByItemID(sourceInfo, diag)
    if directLink then
        RecordEJDiagnostic(sourceInfo.sourceID, diag)
        return directLink
    end

    local drops = C_TransmogCollection.GetAppearanceSourceDrops and
        C_TransmogCollection.GetAppearanceSourceDrops(sourceInfo.sourceID)
    local dropInfo = drops and drops[1]
    if dropInfo then
        diag.dropInstanceName = dropInfo.instance
        diag.dropEncounterName = dropInfo.encounter
        diag.dropDifficultyName = dropInfo.difficulties and dropInfo.difficulties[1]
    end

    if diag.dropDifficultyName then
        diag.difficultyID = EJ_DIFFICULTY_NAME_TO_ID[diag.dropDifficultyName]
    end

    if not dropInfo then
        diag.failureReason = diag.failureReason or "NoDropInfo"
        RecordEJDiagnostic(sourceInfo.sourceID, diag)
        return nil
    end

    local difficultyID = diag.difficultyID
    if not difficultyID then
        diag.failureReason = "UnknownDifficulty"
        RecordEJDiagnostic(sourceInfo.sourceID, diag)
        return nil
    end

    local instanceID = FindEncounterJournalInstanceID(dropInfo.instance)
    if not instanceID then
        diag.failureReason = "InstanceNotFound"
        RecordEJDiagnostic(sourceInfo.sourceID, diag)
        return nil
    end
    diag.instanceID = instanceID

    local encounterID = FindEncounterJournalEncounterID(instanceID, dropInfo.encounter)
    if not encounterID then
        diag.failureReason = "EncounterNotFound"
        RecordEJDiagnostic(sourceInfo.sourceID, diag)
        return nil
    end
    diag.encounterID = encounterID

    EnsureEncounterJournalLoaded()
    if not C_EncounterJournal or not C_EncounterJournal.GetLootInfoByIndex then
        diag.failureReason = "EJUnavailable"
        RecordEJDiagnostic(sourceInfo.sourceID, diag)
        return nil
    end

    EJ_SelectInstance(instanceID)
    EJ_SetDifficulty(difficultyID)
    EJ_SelectEncounter(encounterID)

    local index = 1
    while true do
        local itemInfo = C_EncounterJournal.GetLootInfoByIndex(index)
        if not itemInfo then
            break
        end

        if itemInfo.itemID == sourceInfo.itemID and itemInfo.link then
            diag.finalLink = itemInfo.link
            diag.finalLinkSource = "EncounterJournal.GetLootInfoByIndex"
            RecordEJDiagnostic(sourceInfo.sourceID, diag)
            return itemInfo.link
        end

        index = index + 1
    end

    diag.failureReason = "LinkNotFound"
    RecordEJDiagnostic(sourceInfo.sourceID, diag)
    return nil
end

local function ApplyCachedVariantMetadata(target, metadataCache, sourceID)
    if not target or not metadataCache or not sourceID then
        return
    end

    local cached = metadataCache[sourceID]
    if not cached then
        return
    end

    if cached.itemLevel then
        target.itemLevel = cached.itemLevel
        target.itemLevelQuality = cached.itemLevelQuality
    end
    if cached.itemLevelSource then
        target.itemLevelSource = cached.itemLevelSource
    end
    if cached.variantDifficultyText then
        target.variantDifficultyText = cached.variantDifficultyText
    end
    if cached.variantTierText then
        target.variantTierText = cached.variantTierText
    end
    if cached.variantInstanceText then
        target.variantInstanceText = cached.variantInstanceText
    end
    if cached.variantEncounterText then
        target.variantEncounterText = cached.variantEncounterText
    end
end

local function SetWardrobeCollectionSearchText(searchText)
    if not WardrobeCollectionFrame then
        return
    end

    local searchBox = WardrobeCollectionFrame.SearchBox
        or (WardrobeCollectionFrame.ItemsCollectionFrame and WardrobeCollectionFrame.ItemsCollectionFrame.SearchBox)
        or _G.WardrobeCollectionFrameSearchBox

    if searchBox and searchBox.SetText then
        searchBox:SetText(searchText or "")
        return
    end

    if searchText and WardrobeCollectionFrame.SetSearch then
        WardrobeCollectionFrame:SetSearch(searchText)
    end
end

function DebugFrameMixin:GetName()
    return "DebugFrame"
end

function DebugFrameMixin:Init()
    -- Create the main debug frame
    self.frame = CreateFrame("Frame", "CaerdonDebugFrame", UIParent, "BasicFrameTemplate")
    self.frame:SetSize(500, 400)
    self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    self.frame:SetFrameStrata("HIGH")
    self.frame:SetClampedToScreen(true)
    self.frame:SetMovable(true)
    self.frame:SetResizable(true)
    self.frame:EnableMouse(true)
    self.frame:SetResizeBounds(620, 300) -- Set minimum width and height
    self.frame:Hide()

    -- Set the title in the header
    self.frame.TitleText:SetText("Caerdon Wardrobe Debug")
    self.frame.TitleText:SetPoint("TOP", self.frame, "TOP", 0, -5)

    -- Make frame movable
    self.frame:SetScript("OnMouseDown", function(frame, button)
        if button == "LeftButton" then
            frame:StartMoving()
        end
    end)
    self.frame:SetScript("OnMouseUp", function(frame, button)
        frame:StopMovingOrSizing()
    end)

    -- Add resizing capabilities
    self.frame.resizeButton = CreateFrame("Button", nil, self.frame)
    self.frame.resizeButton:SetSize(16, 16)
    self.frame.resizeButton:SetPoint("BOTTOMRIGHT", -5, 5)
    self.frame.resizeButton:EnableMouse(true)
    self.frame.resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    self.frame.resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    self.frame.resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    self.frame.resizeButton:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            self.frame:StartSizing("BOTTOMRIGHT")
        end
    end)
    -- Setup item frame for displaying item info (fixed header, doesn't scroll)
    self.itemFrame = CreateFrame("Frame", "CaerdonDebugItemFrame", self.frame)
    self.itemFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 10, -30)
    self.itemFrame:SetPoint("RIGHT", self.frame, "RIGHT", -10, 0)
    self.itemFrame:SetHeight(90) -- Increased height to accommodate new layout

    -- Create scroll frame for content
    self.scrollFrame = CreateFrame("ScrollFrame", "CaerdonDebugScrollFrame", self.frame, "UIPanelScrollFrameTemplate")
    self.scrollFrame:SetPoint("TOPLEFT", self.itemFrame, "BOTTOMLEFT", 0, -10)
    self.scrollFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -30, 40)

    -- Create content frame for scroll frame
    self.content = CreateFrame("Frame", "CaerdonDebugContent", self.scrollFrame)
    -- Width needs to account for scrollbar from UIPanelScrollFrameTemplate
    -- The scrollbar is typically 18-20px wide, but we also need to account for frame insets
    -- Using a more conservative 35px to ensure no clipping
    local contentWidth = self.scrollFrame:GetWidth() - 35
    self.content:SetSize(contentWidth, 1) -- Height will be adjusted as content is added
    self.scrollFrame:SetScrollChild(self.content)

    local function RefreshSectionSizing()
        if self.sharedAppearanceContainer then
            if self.sharedAppearanceContainer:IsShown() then
                self:RefreshSharedAppearanceLayout()
            else
                self.sharedAppearanceContainer:SetWidth(self:GetDetailSectionWidth())
            end
        end

        if self.appearanceVariationContainer then
            if self.appearanceVariationContainer:IsShown() then
                self:RefreshAppearanceVariationLayout()
            else
                self.appearanceVariationContainer:SetWidth(self:GetDetailSectionWidth())
            end
        end

        if self.ensembleContainer then
            if self.ensembleContainer:IsShown() then
                self:RefreshEnsembleLayout()
            else
                self.ensembleContainer:SetWidth(self:GetDetailSectionWidth())
            end
        end
    end

    self.scrollFrame:HookScript("OnSizeChanged", function(_, width)
        local contentWidth = (width or 0) - 35
        if contentWidth > 0 then
            self.content:SetWidth(contentWidth)
        end
        RefreshSectionSizing()
    end)

    self.frame:HookScript("OnSizeChanged", function()
        local scrollWidth = self.scrollFrame:GetWidth()
        if scrollWidth and scrollWidth > 0 then
            self.content:SetWidth(scrollWidth - 35)
        end
        RefreshSectionSizing()
    end)

    self.frame.resizeButton:SetScript("OnMouseUp", function()
        self.frame:StopMovingOrSizing()
        local contentWidth = self.scrollFrame:GetWidth() - 35
        if contentWidth > 0 then
            self.content:SetWidth(contentWidth)
        end
        self:RefreshLayout()
        RefreshSectionSizing()
    end)

    -- Ensure section widths are initialized when the frame is first built
    RefreshSectionSizing()

    -- Clear and Refresh buttons
    self.clearButton = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
    self.clearButton:SetSize(80, 22)
    self.clearButton:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 10, 10)
    self.clearButton:SetText("Clear")
    self.clearButton:SetScript("OnClick", function()
        self:ClearDebugDisplay()
    end)

    self.refreshButton = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
    self.refreshButton:SetSize(80, 22)
    self.refreshButton:SetPoint("LEFT", self.clearButton, "RIGHT", 10, 0)
    self.refreshButton:SetText("Refresh")
    self.refreshButton:SetScript("OnClick", function()
        self:RefreshCurrentItem()
    end)

    -- Add checkbox for tooltip processing
    self.tooltipCheckbox = CreateFrame("CheckButton", "CaerdonDebugTooltipCheckbox", self.frame, "UICheckButtonTemplate")
    self.tooltipCheckbox:SetSize(24, 24)
    self.tooltipCheckbox:SetPoint("LEFT", self.refreshButton, "RIGHT", 10, 0)
    self.tooltipCheckbox.text = self.tooltipCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.tooltipCheckbox.text:SetPoint("LEFT", self.tooltipCheckbox, "RIGHT", 5, 0)
    self.tooltipCheckbox.text:SetText("Update from Tooltip")
    self.tooltipCheckbox:SetChecked(false) -- Off by default

    -- Copy to clipboard button
    self.copyButton = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
    self.copyButton:SetSize(120, 22)
    self.copyButton:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -10, 10)
    self.copyButton:SetText("Copy Details")
    self.copyButton:SetScript("OnClick", function()
        self:CopyCurrentItemDetails()
    end)

    -- Create item button that can accept drops
    self.itemButton = CreateFrame("ItemButton", "CaerdonDebugItemButton", self.itemFrame)
    self.itemButton:SetSize(50, 50)
    self.itemButton:SetPoint("TOPLEFT", self.itemFrame, "TOPLEFT", 10, -10)
    self.itemButton:RegisterForDrag("LeftButton")
    self.itemButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Clear the normal texture
    self.itemButton:SetNormalTexture("")
    -- After setting it to empty, hide it
    local normalTexture = self.itemButton:GetNormalTexture()
    if normalTexture then
        normalTexture:Hide()
        normalTexture:SetAlpha(0)
    end

    -- Hide the icon border
    if self.itemButton.IconBorder then
        self.itemButton.IconBorder:Hide()
    end

    -- Create a better empty slot background using standard UI textures
    local slotBG = self.itemButton:CreateTexture(nil, "BACKGROUND")
    slotBG:SetAllPoints()
    slotBG:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
    slotBG:SetTexCoord(0.1, 0.9, 0.1, 0.9) -- Trim edges slightly
    slotBG:SetAlpha(0.5)
    self.itemButton.slotBackground = slotBG

    -- Simple highlight on hover
    self.itemButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    -- Add subtle text to the right of the empty slot
    self.slotHelpText = self.itemFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.slotHelpText:SetPoint("TOPLEFT", self.itemButton, "TOPRIGHT", 8, 0)
    self.slotHelpText:SetText("Drag item here\nRight-click to clear")
    self.slotHelpText:SetTextColor(0.5, 0.5, 0.5)
    self.slotHelpText:SetJustifyH("LEFT")
    self.slotHelpText:SetSpacing(3) -- Add spacing between lines

    -- Add "or show item with ID/link:" text below the help text
    self.orText = self.itemFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.orText:SetPoint("TOPLEFT", self.slotHelpText, "BOTTOMLEFT", 0, -8)
    self.orText:SetText("or show item ID/link:")
    self.orText:SetTextColor(0.5, 0.5, 0.5)
    self.orText:SetJustifyH("LEFT")

    -- Create input box for item ID or link below the "or" text
    self.itemIDInput = CreateFrame("EditBox", "CaerdonDebugItemIDInput", self.itemFrame)
    self.itemIDInput:SetSize(150, 20)
    self.itemIDInput:SetPoint("LEFT", self.orText, "RIGHT", 5, 0)
    self.itemIDInput:SetFontObject("GameFontHighlight")
    self.itemIDInput:SetAutoFocus(false)
    self.itemIDInput:SetMaxLetters(255)
    self.itemIDInput:SetNumeric(false)

    -- Create background for the edit box
    local bg = self.itemIDInput:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(self.itemIDInput)
    bg:SetColorTexture(0, 0, 0, 0.5)

    -- Create border for the edit box
    local border = CreateFrame("Frame", nil, self.itemIDInput, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -3, 3)
    border:SetPoint("BOTTOMRIGHT", 3, -3)
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    border:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    -- Create Show button
    self.showButton = CreateFrame("Button", nil, self.itemFrame, "UIPanelButtonTemplate")
    self.showButton:SetSize(50, 22)
    self.showButton:SetPoint("LEFT", self.itemIDInput, "RIGHT", 5, 0)
    self.showButton:SetText("Show")
    self.showButton:SetScript("OnClick", function()
        local inputText = self.itemIDInput:GetText()
        if inputText and inputText ~= "" then
            local itemLink

            -- Check if it's already an item link
            if string.match(inputText, "|c%x+|Hitem:.-|h%[.-%]|h|r") then
                itemLink = inputText
            else
                -- Assume it's an item ID
                local itemID = tonumber(inputText)
                if itemID then
                    itemLink = select(2, C_Item.GetItemInfo(itemID))
                    if not itemLink then
                        -- Try to create a basic item link and let the item loading handle it
                        itemLink = format("|cff9d9d9d|Hitem:%d:::::::::::::::::|h[Item:%d]|h|r", itemID, itemID)
                    end
                end
            end

            if itemLink then
                self:SetCurrentItem(itemLink)
                self.itemIDInput:SetText("")
                self.itemIDInput:ClearFocus()
            end
        end
    end)

    -- Handle Enter key in the input box
    self.itemIDInput:SetScript("OnEnterPressed", function()
        self.showButton:Click()
    end)

    -- Clear focus on Escape
    self.itemIDInput:SetScript("OnEscapePressed", function(editBox)
        editBox:ClearFocus()
    end)

    -- Set up drag and drop
    self.itemButton:SetScript("OnDragStart", function(button)
        if self.currentItem then
            C_Item.PickupItem(self.currentItem)
        end
    end)

    self.itemButton:SetScript("OnReceiveDrag", function(button)
        -- Prefer using the actual ItemLocation from the cursor if available so we retain bag/slot context
        local cursorItem = C_Cursor and C_Cursor.GetCursorItem and C_Cursor.GetCursorItem()
        if cursorItem and cursorItem.HasAnyLocation and cursorItem:HasAnyLocation() and cursorItem.IsBagAndSlot and cursorItem:IsBagAndSlot() then
            local bag, slot = cursorItem:GetBagAndSlot()
            ClearCursor()
            if bag ~= nil and slot ~= nil then
                self:SetCurrentItemFromBagAndSlot(bag, slot)
                return
            end
        end

        -- Fallback to classic GetCursorInfo hyperlink
        local infoType, info1, info2 = GetCursorInfo()
        if infoType == "merchant" then
            -- Dragging from merchant frame - info1 is the merchant slot index
            local itemLink = GetMerchantItemLink(info1)
            ClearCursor()
            if itemLink then
                self:SetCurrentItem(itemLink)
            end
        elseif infoType == "item" then
            ClearCursor()
            self:SetCurrentItem(info2) -- info2 is the item link
        end
    end)

    self.itemButton:SetScript("OnClick", function(button, buttonType)
        if buttonType == "RightButton" then
            self:ClearDebugDisplay()
            self.currentItem = nil
            self.currentItemLocation = nil
            self.currentCaerdonItem = nil
            self.currentEnsembleData = nil
        else
            -- Handle modified clicks first (ctrl/shift/alt)
            if self.currentItem and IsModifiedClick() then
                HandleModifiedItemClick(self.currentItem)
                return
            end

            -- Prefer ItemLocation if available
            local cursorItem = C_Cursor and C_Cursor.GetCursorItem and C_Cursor.GetCursorItem()
            if cursorItem and cursorItem.HasAnyLocation and cursorItem:HasAnyLocation() and cursorItem.IsBagAndSlot and cursorItem:IsBagAndSlot() then
                local bag, slot = cursorItem:GetBagAndSlot()
                ClearCursor()
                if bag ~= nil and slot ~= nil then
                    self:SetCurrentItemFromBagAndSlot(bag, slot)
                    return
                end
            end

            local infoType, info1, info2 = GetCursorInfo()
            if infoType == "merchant" then
                -- Clicking with merchant item on cursor - info1 is the merchant slot index
                local itemLink = GetMerchantItemLink(info1)
                ClearCursor()
                if itemLink then
                    self:SetCurrentItem(itemLink)
                end
            elseif infoType == "item" then
                ClearCursor()
                self:SetCurrentItem(info2)
            end
        end
    end)

    -- Enable highlight on hover with item
    self.itemButton:SetScript("OnEnter", function(button)
        if GetCursorInfo() == "item" then
            button:LockHighlight()
        end
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        if self.currentItem then
            if self.currentItemLocation and self.currentItemLocation.bag ~= nil and self.currentItemLocation.slot ~= nil then
                if C_Container and C_Container.GetContainerItemInfo then
                    GameTooltip:SetBagItem(self.currentItemLocation.bag, self.currentItemLocation.slot)
                else
                    GameTooltip:SetBagItem(self.currentItemLocation.bag, self.currentItemLocation.slot)
                end
            else
                GameTooltip:SetHyperlink(self.currentItem)
            end
            GameTooltip:Show()
        end
    end)

    self.itemButton:SetScript("OnLeave", function(button)
        button:UnlockHighlight()
        GameTooltip:Hide()
    end)

    self.itemName = self.itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self.itemName:SetPoint("TOPLEFT", self.itemButton, "TOPRIGHT", 10, 0)
    self.itemName:SetPoint("RIGHT", self.itemFrame, "RIGHT", -10, 0)
    self.itemName:SetJustifyH("LEFT")

    -- Make the item name clickable for item links
    self.itemNameButton = CreateFrame("Button", nil, self.itemFrame)
    self.itemNameButton:SetAllPoints(self.itemName)
    self.itemNameButton:SetScript("OnClick", function()
        if not self.currentItem then
            return
        end

        if IsModifiedClick("CHATLINK") then
            ChatEdit_InsertLink(self.currentItem)
            return
        end

        if IsModifiedClick("DRESSUP") then
            if self:TryOpenCurrentEnsembleInWardrobe() then
                return
            end
        end

        -- Show floating item tooltip like clicking items in chat
        if ItemRefTooltip:IsShown() and ItemRefTooltip.itemLink == self.currentItem then
            ItemRefTooltip:Hide()
        else
            ShowUIPanel(ItemRefTooltip)
            if not ItemRefTooltip:IsShown() then
                ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE")
            end
            ItemRefTooltip:SetHyperlink(self.currentItem)
            ItemRefTooltip.itemLink = self.currentItem
        end
    end)

    self.itemID = self.itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.itemID:SetPoint("TOPLEFT", self.itemName, "BOTTOMLEFT", 0, -5)
    self.itemID:SetPoint("RIGHT", self.itemFrame, "RIGHT", -10, 0)
    self.itemID:SetJustifyH("LEFT")
    self.itemID:SetTextColor(0.6, 0.6, 0.6)

    -- Add player info (spec, level, faction)
    self.playerInfo = self.itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.playerInfo:SetPoint("TOPLEFT", self.itemID, "BOTTOMLEFT", 0, -5)
    self.playerInfo:SetPoint("RIGHT", self.itemFrame, "RIGHT", -10, 0)
    self.playerInfo:SetJustifyH("LEFT")
    self.playerInfo:SetTextColor(0.6, 0.6, 0.6)

    -- Debug info section (scrollable content)
    self.infoFrame = CreateFrame("Frame", "CaerdonDebugInfoFrame", self.content)
    self.infoFrame:SetSize(self.content:GetWidth(), 1) -- Will expand as content is added
    self.infoFrame:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, 0)

    self.debugEntries = {}
    self.currentItem = nil
    self.currentCaerdonItem = nil
    self.currentEnsembleData = nil
    self.copyCancelFunc = nil
    self.variantMetadataCache = {}


    -- Register slash command
    SLASH_CAERDONDEBUG1 = "/cdebug"
    SlashCmdList["CAERDONDEBUG"] = function(msg)
        local command = (msg or ""):lower():match("^%s*(.-)%s*$")
        if command == "geometry" then
            self:ShowGeometryExport()
        else
            self:ToggleDebugFrame()
        end
    end

    -- Hook for current item detection from tooltip
    if TooltipDataProcessor then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            -- Only process tooltips if checkbox is checked and frame is shown
            if self.frame:IsShown() and self.tooltipCheckbox:GetChecked() and tooltip == GameTooltip then
                local _, link = tooltip:GetItem()
                if link then
                    local owner = tooltip:GetOwner()
                    local bag, slot

                    -- Try to detect bag/slot from various bag UIs
                    if owner then
                        -- Blizzard default: ContainerFrameItemButton, parent frame often has bagID or GetID returns bag
                        if owner.GetBagID and type(owner.GetBagID) == "function" then
                            local ok, b = pcall(function() return owner:GetBagID() end)
                            if ok then bag = b end
                        end
                        if not bag and owner.GetBag and type(owner.GetBag) == "function" then
                            local ok, b = pcall(function() return owner:GetBag() end)
                            if ok then bag = b end
                        end
                        if not bag and owner.GetParent and owner:GetParent() and owner:GetParent().bagID then
                            bag = owner:GetParent().bagID
                        end
                        if not bag and owner.GetParent and owner:GetParent() and type(owner:GetParent().GetID) == "function" then
                            local ok, b = pcall(function() return owner:GetParent():GetID() end)
                            if ok then bag = b end
                        end

                        -- Slot is commonly the button ID
                        if owner.GetID and type(owner.GetID) == "function" then
                            local ok, s = pcall(function() return owner:GetID() end)
                            if ok then slot = s end
                        end
                        if not slot and owner.slot then slot = owner.slot end
                    end

                    -- The guess above fits a bag button only. Any other button with an ID
                    -- passes it too: a vendor row's ID is its merchant index and its parent's
                    -- ID is 0, which named a backpack slot. Keep the slot only when it holds
                    -- the item the tooltip shows, else take the tooltip's link.
                    if bag ~= nil and slot ~= nil and
                        C_Container.GetContainerItemID(bag, slot) ~= C_Item.GetItemInfoInstant(link) then
                        bag, slot = nil, nil
                    end

                    -- Not opened by the keystroke: what that found last is not this item's.
                    self.openedFrom = nil
                    if bag ~= nil and slot ~= nil then
                        self:SetCurrentItemFromBagAndSlot(bag, slot)
                    else
                        self.currentItem = nil
                        self:SetCurrentItem(link)
                    end
                end
            end
        end)
    end

    return {}
end

function DebugFrameMixin:ToggleDebugFrame()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
        if self.currentItem then
            self:RefreshCurrentItem()
        end
    end
end

function DebugFrameMixin:ProcessCurrentItem(item, keySuffix)
    if not item then return end

    wipe(variantEJDiagnostics)

    self.currentEnsembleData = nil
    if self.copyCancelFunc then
        self.copyCancelFunc()
        self.copyCancelFunc = nil
    end

    -- Cancel any pending operations
    if cancelFuncs[self] then
        cancelFuncs[self]()
        cancelFuncs[self] = nil
    end

    self:ClearDebugDisplay()
    self.currentCaerdonItem = item

    -- Always show basic item information immediately
    self:ShowBasicItemInfo(item)

    -- Update the button through Caerdon's system to show overlays
    local options = {
        statusProminentSize = 24, -- Standard size for debug display
        bindingScale = 1.0
    }

    local locKey = "debugframe-" .. (keySuffix or (item:GetItemID() or "unknown"))

    CaerdonWardrobe:UpdateButton(self.itemButton, item, self, {
        locationKey = locKey,
        isDebugFrame = true
    }, options)

    if not item:IsItemEmpty() then
        cancelFuncs[self] = item:ContinueWithCancelOnItemLoad(function()
            self:ClearDebugEntries()
            self:DisplayItemInfo(item)

            -- Re-update button after item loads to ensure correct status
            CaerdonWardrobe:UpdateButton(self.itemButton, item, self, {
                locationKey = locKey,
                isDebugFrame = true
            }, options)
        end)
    else
        self:ClearDebugEntries()
        self:DisplayItemInfo(item)
    end
end

-- What the window under the pointer asked the addon to judge for this item, where the button
-- the tooltip belongs to is one the addon decorates: { link, extraData, drawn }. A window can
-- pass more than a link (an auction row its item level, since the link the client gives for a
-- row is the plain item's): the export is then of the piece as the window gave it, the one
-- the icon was made for, and not of the link alone.
local function AskedUnderPointer(itemLink)
    local tooltip = GameTooltip
    if not (tooltip and tooltip.IsShown and tooltip:IsShown() and tooltip.GetOwner and CaerdonWardrobe.GetAskedOf) then
        return nil
    end
    local asked, drawn = CaerdonWardrobe:GetAskedOf(tooltip:GetOwner())
    if not asked or type(asked.GetItemID) ~= "function" or
        asked:GetItemID() ~= C_Item.GetItemInfoInstant(itemLink) then
        return nil
    end
    return { link = asked.extraData and asked:GetItemLink() or nil, extraData = asked.extraData, drawn = drawn }
end

-- kept: what AskedUnderPointer said when the item was first taken, for a refresh of it (the
-- pointer is somewhere else by then).
function DebugFrameMixin:SetCurrentItem(itemLink, kept)
    if itemLink then
        self.currentItem = itemLink
        self.currentItemLocation = nil
        local ask = kept
        if not ask then
            local ok, found = pcall(AskedUnderPointer, itemLink)
            ask = ok and found or nil
        end
        self.currentAsk = ask

        -- Create a fresh item object each time
        local item = CaerdonItem:CreateFromItemLink(ask and ask.link or itemLink, ask and ask.extraData or nil)
        if item then
            self:ProcessCurrentItem(item)
        end
    end
end

function DebugFrameMixin:SetCurrentItemFromBagAndSlot(bag, slot)
    if bag == nil or slot == nil then return end
    local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
    -- A slot with nothing in it is no item to show: the frame keeps what it had.
    if item and item:IsItemEmpty() then
        print(("Caerdon Wardrobe Debug: bag %s slot %s holds no item."):format(tostring(bag), tostring(slot)))
        return
    end
    if item then
        -- Prefer showing the hyperlink if available; otherwise show a placeholder until load completes
        self.currentItem = item:GetItemLink() or ("Bag " .. tostring(bag) .. ", Slot " .. tostring(slot))
        self.currentItemLocation = { bag = bag, slot = slot }
        self:ProcessCurrentItem(item, ("bag%d-slot%d"):format(bag, slot))
    end
end

function DebugFrameMixin:ClearDebugDisplay()
    -- Clear the item button icon
    self.itemButton.icon:SetTexture(nil)
    self.itemButton.icon:Hide()
    self.itemName:SetText("")
    self.itemID:SetText("")
    self.playerInfo:SetText("")
    self.currentEnsembleSetID = nil
    self.currentEnsembleSetInfo = nil
    self.currentEnsembleClassCandidates = nil
    self.currentCaerdonItem = nil
    self.currentEnsembleData = nil
    self.currentSharedAppearanceItems = nil
    self.currentAppearanceVariations = nil
    if self.copyCancelFunc then
        self.copyCancelFunc()
        self.copyCancelFunc = nil
    end

    if self.slotHelpText then
        self.slotHelpText:Show()
    end

    if self.orText then
        self.orText:Show()
    end

    if self.itemIDInput then
        self.itemIDInput:Show()
        self.itemIDInput:SetText("")
    end

    if self.showButton then
        self.showButton:Show()
    end

    if self.playerInfo then
        self.playerInfo:Show()
    end

    -- Clear Caerdon overlay
    CaerdonWardrobe:ClearButton(self.itemButton)

    -- Clear debug entries
    self:ClearDebugEntries()

    -- Clear recipe created item container
    if self.recipeCreatedItemContainer then
        self.recipeCreatedItemContainer:Hide()
        if self.recipeCreatedItemFrames then
            for _, frame in ipairs(self.recipeCreatedItemFrames) do
                if frame.itemButton then
                    CaerdonWardrobe:ClearButton(frame.itemButton)
                end
                frame:Hide()
                if frame.detailsFrame then
                    frame.detailsFrame:Hide()
                end
            end
        end
    end

    -- Clear ensemble container
    if self.ensembleContainer then
        self.ensembleContainer:Hide()
        if self.ensembleItemFrames then
            for _, frame in ipairs(self.ensembleItemFrames) do
                -- Clear Caerdon overlay
                if frame.itemButton then
                    CaerdonWardrobe:ClearButton(frame.itemButton)
                end
                frame:Hide()
                frame:ClearAllPoints()
            end
        end
    end

    if self.sharedAppearanceContainer then
        self.sharedAppearanceContainer:Hide()
        if self.sharedAppearanceItemFrames then
            for _, frame in ipairs(self.sharedAppearanceItemFrames) do
                if frame.itemButton then
                    CaerdonWardrobe:ClearButton(frame.itemButton)
                end
                frame:Hide()
                if frame.detailsFrame then
                    frame.detailsFrame:Hide()
                end
            end
        end
        if self.sharedAppearanceOverflowText then
            self.sharedAppearanceOverflowText:Hide()
        end
    end

    if self.appearanceVariationContainer then
        self.appearanceVariationContainer:Hide()
        if self.appearanceVariationItemFrames then
            for _, frame in ipairs(self.appearanceVariationItemFrames) do
                if frame.itemButton then
                    CaerdonWardrobe:ClearButton(frame.itemButton)
                end
                frame:Hide()
                if frame.detailsFrame then
                    frame.detailsFrame:Hide()
                end
            end
        end
        if self.appearanceVariationOverflowText then
            self.appearanceVariationOverflowText:Hide()
        end
    end

    self:UpdateContentHeight()
end

function DebugFrameMixin:ClearDebugEntries()
    -- Remove all debug entries
    for _, entry in ipairs(self.debugEntries) do
        entry:Hide()
        entry:ClearAllPoints()
        if entry.itemButton then
            entry.itemButton:Hide()
        end
    end

    -- Reset debug entries count
    wipe(self.debugEntries)

    -- Reset content height
    self.infoFrame:SetHeight(1)
    self:UpdateContentHeight()
end

function DebugFrameMixin:UpdateContentHeight()
    local totalHeight = self.infoFrame:GetHeight()

    if self.recipeCreatedItemContainer and self.recipeCreatedItemContainer:IsShown() then
        totalHeight = totalHeight + 10 + self.recipeCreatedItemContainer:GetHeight()
    end

    if self.sharedAppearanceContainer and self.sharedAppearanceContainer:IsShown() then
        totalHeight = totalHeight + 10 + self.sharedAppearanceContainer:GetHeight()
    end

    if self.appearanceVariationContainer and self.appearanceVariationContainer:IsShown() then
        totalHeight = totalHeight + 10 + self.appearanceVariationContainer:GetHeight()
    end

    if self.ensembleContainer and self.ensembleContainer:IsShown() then
        totalHeight = totalHeight + 10 + self.ensembleContainer:GetHeight()
    end

    self.content:SetHeight(math.max(totalHeight, 1))
end

function DebugFrameMixin:RefreshLayout()
    -- Reposition all visible entries based on current frame width
    local numColumns, columnWidth = self:GetColumnLayout()

    for index, entry in ipairs(self.debugEntries) do
        if entry:IsShown() then
            -- Update entry width
            entry:SetWidth(columnWidth)
            local paddingAdjustment = DEBUG_ENTRY_LABEL_LEFT_PADDING + DEBUG_ENTRY_LABEL_WIDTH + DEBUG_ENTRY_VALUE_GAP
            local valueWidth = columnWidth - paddingAdjustment
            if numColumns == 2 then
                valueWidth = math.max(220, valueWidth)
            else
                valueWidth = math.max(260, valueWidth)
            end
            entry.value:SetWidth(valueWidth)

            -- Clear existing points
            entry:ClearAllPoints()

            -- Reposition based on column layout
            if numColumns == 2 then
                local row = math.ceil(index / 2)
                local column = ((index - 1) % 2) + 1

                if index == 1 then
                    entry:SetPoint("TOPLEFT", self.infoFrame, "TOPLEFT", 0, 0)
                elseif column == 1 then
                    entry:SetPoint("TOPLEFT", self.debugEntries[index - 2], "BOTTOMLEFT", 0, -5)
                else
                    if index == 2 then
                        entry:SetPoint("TOPLEFT", self.infoFrame, "TOPLEFT", columnWidth + 10, 0)
                    else
                        entry:SetPoint("TOPLEFT", self.debugEntries[index - 2], "BOTTOMLEFT", 0, -5)
                    end
                end
            else
                if index == 1 then
                    entry:SetPoint("TOPLEFT", self.infoFrame, "TOPLEFT", 0, 0)
                else
                    entry:SetPoint("TOPLEFT", self.debugEntries[index - 1], "BOTTOMLEFT", 0, -5)
                end
            end
        end
    end

    -- Update frame heights
    local visibleCount = 0
    for _, entry in ipairs(self.debugEntries) do
        if entry:IsShown() then
            visibleCount = visibleCount + 1
        end
    end

    local numRows = numColumns == 2 and math.ceil(visibleCount / 2) or visibleCount
    self.infoFrame:SetHeight((numRows * 25) + 10)

    self:UpdateContentHeight()
end

function DebugFrameMixin:GetColumnLayout()
    -- Determine if we should use two columns based on frame width
    local frameWidth = self.frame:GetWidth()
    local minWidthForTwoColumns = 1175

    if frameWidth >= minWidthForTwoColumns then
        return 2, (frameWidth - 80) / 2 -- account for extra gutter
    else
        return 1, frameWidth - 40       -- Single column
    end
end

function DebugFrameMixin:AddDebugEntry(label, value, color)
    local index = #self.debugEntries + 1

    -- Create new entry if needed
    if not self.debugEntries[index] then
        local entry = CreateFrame("Frame", "CaerdonDebugEntry" .. index, self.infoFrame)
        entry:SetHeight(20)

        entry.label = entry:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        entry.label:SetPoint("TOPLEFT", entry, "TOPLEFT", DEBUG_ENTRY_LABEL_LEFT_PADDING, 0)
        entry.label:SetWidth(DEBUG_ENTRY_LABEL_WIDTH)
        entry.label:SetJustifyH("LEFT")

        entry.value = entry:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        entry.value:SetPoint("TOPLEFT", entry.label, "TOPRIGHT", DEBUG_ENTRY_VALUE_GAP, 0)
        entry.value:SetJustifyH("LEFT")

        self.debugEntries[index] = entry
    end

    local entry = self.debugEntries[index]
    entry:Show()

    -- Get column layout
    local numColumns, columnWidth = self:GetColumnLayout()

    -- Set entry width based on column layout
    entry:SetWidth(columnWidth)
    local paddingAdjustment = DEBUG_ENTRY_LABEL_LEFT_PADDING + DEBUG_ENTRY_LABEL_WIDTH + DEBUG_ENTRY_VALUE_GAP
    local valueWidth = columnWidth - paddingAdjustment
    if numColumns == 2 then
        valueWidth = math.max(220, valueWidth)
    else
        valueWidth = math.max(260, valueWidth)
    end
    entry.value:SetWidth(valueWidth)

    -- Position entry based on column layout
    if numColumns == 2 then
        -- Two column layout
        local row = math.ceil(index / 2)
        local column = ((index - 1) % 2) + 1

        local columnSpacing = 30
        if index == 1 then
            entry:SetPoint("TOPLEFT", self.infoFrame, "TOPLEFT", 0, 0)
        elseif column == 1 then
            entry:SetPoint("TOPLEFT", self.debugEntries[index - 2], "BOTTOMLEFT", 0, -5)
        else
            if index == 2 then
                entry:SetPoint("TOPLEFT", self.infoFrame, "TOPLEFT", columnWidth + columnSpacing, 0)
            else
                entry:SetPoint("TOPLEFT", self.debugEntries[index - 2], "BOTTOMLEFT", 0, -5)
            end
        end
    else
        -- Single column layout
        if index == 1 then
            entry:SetPoint("TOPLEFT", self.infoFrame, "TOPLEFT", 0, 0)
        else
            entry:SetPoint("TOPLEFT", self.debugEntries[index - 1], "BOTTOMLEFT", 0, -5)
        end
    end

    entry.label:SetText(label .. ":")
    entry.value:SetText(value or "nil")

    if color then
        entry.value:SetTextColor(color.r, color.g, color.b, 1)
    else
        entry.value:SetTextColor(1, 1, 1, 1)
    end

    -- Update frame heights based on column layout
    local numRows = numColumns == 2 and math.ceil(index / 2) or index
    self.infoFrame:SetHeight((numRows * 25) + 10)
    self:UpdateContentHeight()

    return entry
end

-- Display only basic item info (icon, name, ID)
function DebugFrameMixin:ShowBasicItemInfo(item)
    -- Update player info display
    local level = UnitLevel("player")
    local specIndex = CaerdonAPI:GetPlayerSpecializationIndex()
    local specInfo = ""

    if specIndex then
        local specID, specName = CaerdonAPI:GetSpecializationInfo(specIndex)
        if specName then
            specInfo = specName .. " "
        end
    end

    local className = UnitClass("player")
    local faction = UnitFactionGroup("player")
    local factionIcon = ""

    if faction == "Alliance" then
        factionIcon = "|TInterface\\FriendsFrame\\PlusManz-Alliance:16|t"
    elseif faction == "Horde" then
        factionIcon = "|TInterface\\FriendsFrame\\PlusManz-Horde:16|t"
    end

    self.playerInfo:SetText(format("Level %d %s%s %s", level, specInfo, className or "", factionIcon))

    -- Set item icon and name
    local icon = item:GetItemIcon()
    if icon then
        self.itemButton.icon:SetTexture(icon)
        self.itemButton.icon:Show()
        if self.slotHelpText then
            self.slotHelpText:Hide()
        end

        if self.orText then
            self.orText:Hide()
        end

        if self.itemIDInput then
            self.itemIDInput:Hide()
        end

        if self.showButton then
            self.showButton:Hide()
        end

        if self.playerInfo then
            self.playerInfo:Hide()
        end
    end

    if self.playerInfo then
        self.playerInfo:Show()
    end

    -- Set the item name as a hyperlink
    if self.currentItem then
        self.itemName:SetText(self.currentItem)
    else
        self.itemName:SetText(item:GetItemName())
    end
    self.itemID:SetText("Item ID: " .. (item:GetItemID() or "unknown"))
end

function DebugFrameMixin:DisplayItemInfo(item)
    -- Set item icon and name (already set in ShowBasicItemInfo, but setting again for clarity)
    local icon = item:GetItemIcon()
    if icon then
        self.itemButton.icon:SetTexture(icon)
        self.itemButton.icon:Show()
    end
    -- Set the item name as a hyperlink
    if self.currentItem then
        self.itemName:SetText(self.currentItem)
    else
        self.itemName:SetText(item:GetItemName())
    end
    self.itemID:SetText("Item ID: " .. (item:GetItemID() or "unknown"))

    -- Add basic item info
    local identifiedType = item:GetCaerdonItemType()
    local identifiedColor = GREEN_FONT_COLOR
    if identifiedType == CaerdonItemType.Unknown then
        identifiedColor = RED_FONT_COLOR
    end

    self:AddDebugEntry("Identified Type", identifiedType, identifiedColor)

    -- Get Caerdon status info
    local locationInfo = {
        locationKey = "debugframe-" .. (item:GetItemID() or "unknown"),
        isDebugFrame = true
    }
    local isReady, mogStatus, bindingStatus = item:GetCaerdonStatus(self, locationInfo)
    if isReady then
        if mogStatus then
            self:AddDebugEntry("Caerdon Mog Status", mogStatus, GREEN_FONT_COLOR)
        end
        if bindingStatus then
            self:AddDebugEntry("Caerdon Binding Status", bindingStatus, YELLOW_FONT_COLOR)
        end
    end

    local forDebugUse = item:GetForDebugUse()
    if forDebugUse then
        local optionsLength = strlen(forDebugUse.linkOptions or "")
        local optionsEnd = ""
        if optionsLength > 30 then
            optionsEnd = "..."
        end

        self:AddDebugEntry("Link Type", forDebugUse.linkType or "Missing")
        self:AddDebugEntry("Link Options", (strsub(forDebugUse.linkOptions or "", 1, 30) .. optionsEnd) or "Missing")
    end

    if item:GetItemQuality() then
        local qualityColor = item:GetItemQualityColor()
        self:AddDebugEntry("Quality", _G[format("ITEM_QUALITY%d_DESC", item:GetItemQuality())], qualityColor.color)
    end

    local itemLocation = item:GetItemLocation()
    if itemLocation and itemLocation:HasAnyLocation() then
        if itemLocation:IsEquipmentSlot() then
            self:AddDebugEntry("Equipment Slot", tostring(itemLocation:GetEquipmentSlot()))
        end

        if itemLocation:IsBagAndSlot() and not item:IsItemEmpty() then
            local bag, slot = itemLocation:GetBagAndSlot()
            self:AddDebugEntry("Bag", tostring(bag))
            self:AddDebugEntry("Slot", tostring(slot))

            local canTransmog, error = C_Item.CanItemTransmogAppearance(itemLocation)
            self:AddDebugEntry("Can Item Transmog Appearance", tostring(canTransmog))
        end
    end

    if identifiedType ~= CaerdonItemType.BattlePet and
        identifiedType ~= CaerdonItemType.Quest and
        identifiedType ~= CaerdonItemType.Currency then
        -- In parentheses: an empty slot's item answers with no value at all, which tostring refuses.
        self:AddDebugEntry("Item Type", item:GetItemType())
        self:AddDebugEntry("Item SubType", item:GetItemSubType())
        self:AddDebugEntry("Item Type ID", tostring((item:GetItemTypeID())))
        self:AddDebugEntry("Item SubType ID", tostring((item:GetItemSubTypeID())))
        self:AddDebugEntry("Binding", item:GetBinding())
        self:AddDebugEntry("Expansion ID", tostring((item:GetExpansionID())))
        self:AddDebugEntry("Is Crafting Reagent", tostring((item:GetIsCraftingReagent())))
    end

    -- Add specialized info based on item type
    if identifiedType == CaerdonItemType.BattlePet or identifiedType == CaerdonItemType.CompanionPet then
        self:AddPetInfo(item)
    elseif identifiedType == CaerdonItemType.Equipment then
        self:AddTransmogInfo(item)
        self:AddEquipmentInfo(item)
    elseif identifiedType == CaerdonItemType.Housing then
        self:AddHousingInfo(item)
    elseif identifiedType == CaerdonItemType.Conduit then
        self:AddConduitInfo(item)
    elseif identifiedType == CaerdonItemType.Consumable then
        self:AddConsumableInfo(item)
    elseif identifiedType == CaerdonItemType.Currency then
        self:AddCurrencyInfo(item)
    elseif identifiedType == CaerdonItemType.Mount then
        self:AddMountInfo(item)
    elseif identifiedType == CaerdonItemType.Recipe then
        self:AddRecipeInfo(item)
    elseif identifiedType == CaerdonItemType.Toy then
        self:AddToyInfo(item)
    end
end

function DebugFrameMixin:CopyCurrentItemDetails()
    if self.copyCancelFunc then
        self.copyCancelFunc()
        self.copyCancelFunc = nil
    end

    if not self.currentCaerdonItem then
        print("Caerdon Wardrobe Debug: No item selected to copy.")
        return
    end

    local item = self.currentCaerdonItem

    local function performCopy()
        local payload = self:BuildClipboardPayload(item)
        if not payload or payload == "" then
            print("Caerdon Wardrobe Debug: Unable to build clipboard payload for current item.")
            return
        end

        self:ShowCopyOutput(payload)
    end

    if item:IsItemEmpty() then
        -- Nothing to describe: the frame holds a slot with no item in it.
        print("Caerdon Wardrobe Debug: there is no item to copy (" .. tostring(self.openedFrom or "an empty slot") .. ").")
        return
    end

    -- An item given by its bag or equipment slot counts as loaded for the item's own wait
    -- whether or not the client has its data (CaerdonItemMixin:IsItemCached), and the wait
    -- reports once at the start, before the sources' items have come. An export built while the
    -- client has nothing for the item is one line, "Retrieving item information". So the copy
    -- asks for the data itself and waits for it, a few seconds at most, and the export says so.
    local location = item:HasItemLocation() and item:GetItemLocation() or nil
    local function DataMissing()
        return location ~= nil and C_Item.DoesItemExist(location) and not C_Item.IsItemDataCached(location)
    end
    local tries = 0
    local cancelled = false
    local function Continue()
        if cancelled then
            return
        end
        if DataMissing() and tries < 15 then
            tries = tries + 1
            C_Timer.After(0.2, Continue)
            return
        end
        self.copyWaitNote = tries > 0 and
            (DataMissing() and "the client had no data for the item after 3 s; exported without"
                or ("the client had no data for the item at first; it came within %.1f s"):format(tries * 0.2)) or nil
        self.copyCancelFunc = item:ContinueWithCancelOnItemLoad(function()
            performCopy()
            self.copyCancelFunc = nil
        end)
    end
    if DataMissing() then
        C_Item.RequestLoadItemData(location)
        self.copyCancelFunc = function() cancelled = true end
    end
    Continue()
end

-- "/cdebug geometry": the [Button Geometry] section on its own, for when that is all that is being
-- collected. Needs no selected item.
function DebugFrameMixin:ShowGeometryExport()
    local version, build, _, tocVersion = GetBuildInfo()
    local lines = {
        "=== CaerdonWardrobe Button Geometry ===",
        "Generated: " .. date("%Y-%m-%d %H:%M:%S"),
        string.format("Game Build: %s (%s), TOC %s", tostring(version), tostring(build), tostring(tocVersion)),
        "",
        "[Button Geometry]"
    }
    if CaerdonButtonGeometry and CaerdonButtonGeometry.GetReportLines then
        local ok, geometryLines = pcall(CaerdonButtonGeometry.GetReportLines, CaerdonButtonGeometry)
        if ok then
            for _, geometryLine in ipairs(geometryLines) do
                lines[#lines + 1] = string.rep("  ", geometryLine.indent or 0) .. geometryLine.text
            end
        else
            lines[#lines + 1] = "  Report failed: " .. tostring(geometryLines)
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "=== End CaerdonWardrobe Button Geometry ==="

    -- The copy dialog is a child of the Debug Frame, so it is only visible while that is open.
    if self.frame and not self.frame:IsShown() then
        self.frame:Show()
    end
    self:ShowCopyOutput(table.concat(lines, "\n"))
end

------------------------------------------------------------------------------------------
-- The export's tooltip sections
------------------------------------------------------------------------------------------

-- Nothing documents what a tooltip line carries besides its texts, so the export prints every
-- field of every line: that is how a field is found, and seen in both clients, before the
-- item code relies on it.

-- What a line's own row of the export already shows.
local TOOLTIP_LINE_ROW_FIELDS = { type = true, leftText = true, rightText = true, leftColor = true, rightColor = true }
local TOOLTIP_DATA_ROW_FIELDS = { lines = true }

-- Fields whose number is an enum value: the export names it.
local tooltipValueNames
local function GetTooltipValueName(scope, field, value)
    if not tooltipValueNames then
        tooltipValueNames = { line = {}, data = {} }
        local enums = {
            line = {
                type = Enum.TooltipDataLineType,
                bonding = Enum.TooltipDataItemBinding,
                requirementType = Enum.TooltipDataUsageRequirementType,
            },
            data = { type = Enum.TooltipDataType },
        }
        for enumScope, fields in pairs(enums) do
            for enumField, enum in pairs(fields) do
                local names = {}
                for name, number in pairs(enum) do
                    names[number] = name
                end
                tooltipValueNames[enumScope][enumField] = names
            end
        end
    end
    local names = tooltipValueNames[scope][field]
    return names and names[value] or nil
end

local function SortedTooltipKeys(source, skip)
    local keys = {}
    for key, value in pairs(source) do
        if not (skip and skip[key]) and type(value) ~= "function" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function FormatTooltipValue(value, depth)
    if type(value) ~= "table" then
        return tostring(value)
    end
    if depth <= 0 then
        return "{...}"
    end
    local parts = {}
    for _, key in ipairs(SortedTooltipKeys(value)) do
        parts[#parts + 1] = tostring(key) .. "=" .. FormatTooltipValue(value[key], depth - 1)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- "key=value, key=value (EnumName)" for every field of source that skip does not name.
local function FormatTooltipFields(source, skip, scope)
    local parts = {}
    for _, key in ipairs(SortedTooltipKeys(source, skip)) do
        local value = source[key]
        local text = tostring(key) .. "=" .. FormatTooltipValue(value, 2)
        local name = GetTooltipValueName(scope, key, value)
        if name then
            text = text .. " (" .. name .. ")"
        end
        parts[#parts + 1] = text
    end
    return table.concat(parts, ", ")
end

-- The lines of one tooltip as rows of the export: each line's type, colors and texts, and
-- below it every other field the line carries.
local function BuildTooltipLineRows(data)
    local rows = {}
    for index, line in ipairs(data.lines or {}) do
        local lineType = line.type
        local typeName = GetTooltipValueName("line", "type", lineType)
        local prefix = format("[%d] type=%s", index, tostring(lineType))
        if typeName then
            prefix = prefix .. " (" .. typeName .. ")"
        end
        local leftText = line.leftText and tostring(line.leftText) or ""
        local rightText = line.rightText and tostring(line.rightText) or ""
        -- Both colors, so a red (unmet requirement) line can be told in the export: the armor
        -- and weapon proficiency red sits in the right column of the EquipSlot line.
        if line.leftColor and line.leftColor.GenerateHexColor then
            prefix = prefix .. " color=" .. line.leftColor:GenerateHexColor()
        end
        if rightText ~= "" and line.rightColor and line.rightColor.GenerateHexColor then
            prefix = prefix .. " rcolor=" .. line.rightColor:GenerateHexColor()
        end
        if rightText ~= "" then
            rows[#rows + 1] = { indent = 1, text = format("%s  L: %s  |  R: %s", prefix, leftText, rightText) }
        else
            rows[#rows + 1] = { indent = 1, text = format("%s  L: %s", prefix, leftText) }
        end
        local fields = FormatTooltipFields(line, TOOLTIP_LINE_ROW_FIELDS, "line")
        if fields ~= "" then
            rows[#rows + 1] = { indent = 3, text = fields }
        end
    end
    return rows
end

local function TooltipLineRowsMatch(rows, otherRows)
    if #rows ~= #otherRows then
        return false
    end
    for index, row in ipairs(rows) do
        if row.text ~= otherRows[index].text then
            return false
        end
    end
    return true
end

-- The tooltip sections of the export as rows ({ indent, text }; an empty text is a blank row).
-- An item in a bag or equipment slot has two tooltips: the slot's, which knows that copy
-- (bound, locked, durability), and the bare link's, which is the one the status is computed
-- from. The link's lines are printed only where they differ from the slot's.
--
-- itemKey: a row the auction house names by item key ({ itemID, itemLevel, itemSuffix }). Its
-- tooltip is filled by the key and is the piece's, which the link the client gives for the
-- key is not always (another level, a suffix the link lacks): the key's lines are printed
-- beside the link's, with the link the key's tooltip names.
function DebugFrameMixin:GetTooltipReportRows(itemLink, itemLocation, itemKey)
    local rows = {}
    if not C_TooltipInfo then
        return rows
    end

    local function addSection(title, asked, data, sameAsRows)
        rows[#rows + 1] = { indent = 0, text = "" }
        rows[#rows + 1] = { indent = 0, text = title }
        rows[#rows + 1] = { indent = 1, text = "Asked: " .. asked }
        if type(data) ~= "table" then
            rows[#rows + 1] = { indent = 1, text = "Answer: " .. tostring(data) }
            return nil
        end
        rows[#rows + 1] = { indent = 1, text = "Data: " .. FormatTooltipFields(data, TOOLTIP_DATA_ROW_FIELDS, "data") }
        local lineRows = BuildTooltipLineRows(data)
        if sameAsRows and TooltipLineRowsMatch(lineRows, sameAsRows) then
            rows[#rows + 1] = { indent = 1, text = format("Lines: %d, each the same as the slot's", #(data.lines or {})) }
        else
            for _, row in ipairs(lineRows) do
                rows[#rows + 1] = row
            end
        end
        return lineRows
    end

    local slotData, slotAsked
    if itemLocation and itemLocation:HasAnyLocation() then
        if itemLocation:IsBagAndSlot() then
            local bag, slot = itemLocation:GetBagAndSlot()
            slotData = C_TooltipInfo.GetBagItem(bag, slot)
            slotAsked = format("C_TooltipInfo.GetBagItem(%s, %s)", tostring(bag), tostring(slot))
        elseif itemLocation:IsEquipmentSlot() then
            local equipmentSlot = itemLocation:GetEquipmentSlot()
            slotData = C_TooltipInfo.GetInventoryItem("player", equipmentSlot)
            slotAsked = format("C_TooltipInfo.GetInventoryItem(\"player\", %s)", tostring(equipmentSlot))
        end
    end

    local slotRows
    if slotAsked then
        slotRows = addSection("[Tooltip Lines (Raw)]", slotAsked, slotData)
    end
    if itemLink then
        addSection(slotAsked and "[Tooltip Lines (Link)]" or "[Tooltip Lines (Raw)]",
            "C_TooltipInfo.GetHyperlink(link), which the status is computed from", C_TooltipInfo.GetHyperlink(itemLink),
            slotRows)
    end
    if type(itemKey) == "table" and C_TooltipInfo.GetItemKey then
        local requiredLevel
        if C_AuctionHouse and C_AuctionHouse.GetItemKeyRequiredLevel then
            local ok, answer = pcall(C_AuctionHouse.GetItemKeyRequiredLevel, itemKey)
            requiredLevel = ok and answer or nil
        end
        local ok, data = pcall(C_TooltipInfo.GetItemKey, itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix, requiredLevel)
        addSection("[Tooltip Lines (Item Key)]", format("C_TooltipInfo.GetItemKey(%s, %s, %s, %s), what the auction house shows for the row",
            tostring(itemKey.itemID), tostring(itemKey.itemLevel), tostring(itemKey.itemSuffix), tostring(requiredLevel)),
            ok and data or ("an error: " .. tostring(data)))
        local keyLink = ok and type(data) == "table" and data.hyperlink
        rows[#rows + 1] = { indent = 1, text = "Its Link: " .. tostring(type(keyLink) == "string" and
            (keyLink:match("|H(.-)|h") or keyLink) or "none") }
    end
    return rows
end

-- A client format string ("%s (%d/%d)") as a matcher that finds its values in a tooltip line.
local function TextPattern(formatString)
    return NS.FormatPattern.Compile(formatString)
end

local function ItemSetOf(link)
    local setID = link and select(16, C_Item.GetItemInfo(link)) or nil
    if not setID then
        return nil
    end
    return setID, C_Item.GetItemSetInfo and C_Item.GetItemSetInfo(setID) or nil
end

-- The export's "[Set Bonuses]": what the client says about the item set of a piece (a tier set
-- and the like, not a saved equipment set), which of the worn pieces belong to item sets, and
-- what the piece's tooltip says about the set's bonuses. Readings only: no verdict is made from
-- any of it. The tooltip names the piece count of a bonus the toon does not have and not of one
-- it has, which is what a rule about losing a bonus would have to get around.
local function ExplainSetBonuses(item)
    local lines = {}
    local function add(indent, text, ...)
        lines[#lines + 1] = string.rep("  ", indent) .. (select("#", ...) > 0 and text:format(...) or text)
    end
    local link = item:GetItemLink()
    if not link then
        return lines
    end

    local setID, setName = ItemSetOf(link)
    add(0, "Item Set: %s", setID and ("%d \"%s\""):format(setID, tostring(setName)) or "none (the item info names no set)")

    local specIndex = CaerdonAPI:GetPlayerSpecializationIndex()
    local specID = specIndex and CaerdonAPI:GetSpecializationInfo(specIndex) or nil
    if not C_Item.GetSetBonusesForSpecializationByItemID then
        add(0, "Bonus Spells For The Played Spec: the client has no such function")
    elseif not specID then
        add(0, "Bonus Spells For The Played Spec: not asked (no specialization)")
    else
        local spells = C_Item.GetSetBonusesForSpecializationByItemID(specID, item:GetItemID())
        local texts = {}
        for index, spellID in ipairs(spells or {}) do
            texts[index] = ("%s \"%s\""):format(tostring(spellID),
                tostring(C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID) or "?"))
        end
        add(0, "Bonus Spells For The Played Spec (spec %s): %s", tostring(specID),
            #texts > 0 and table.concat(texts, "; ") or (spells and "none" or "no answer"))
    end

    -- The tooltip: the set's line with its count, its pieces, its bonuses.
    local namePattern = TextPattern(ITEM_SET_NAME)
    local needsPattern = TextPattern(ITEM_SET_BONUS_GRAY)
    local hasPattern = TextPattern(ITEM_SET_BONUS)
    local disabledLine = Enum.TooltipDataLineType and Enum.TooltipDataLineType.DisabledLine
    local data = C_TooltipInfo and C_TooltipInfo.GetHyperlink(link) or nil
    local inPieces = false
    local found = false
    add(0, "Tooltip (the link's):")
    for _, line in ipairs(data and data.lines or {}) do
        local text = line.leftText and tostring(line.leftText) or ""
        local color = line.leftColor and line.leftColor.GenerateHexColor and line.leftColor:GenerateHexColor() or "?"
        local name, worn, total
        if namePattern then
            name, worn, total = namePattern:Match(text)
        end
        local needs, needsText
        if needsPattern then
            needs, needsText = needsPattern:Match(text)
        end
        local hasText = not needs and hasPattern and hasPattern:Match(text) or nil
        if name and tonumber(worn) and tonumber(total) then
            found, inPieces = true, true
            add(1, "set line: \"%s\", %s of %s worn", name, worn, total)
        elseif needs then
            found, inPieces = true, false
            add(1, "bonus the toon does not have, at %s pieces: \"%s\"", needs, tostring(needsText):sub(1, 90))
        elseif hasText then
            found, inPieces = true, false
            add(1, "bonus the toon has (no piece count in the line): \"%s\"", tostring(hasText):sub(1, 90))
        elseif inPieces and text:match("%S") then
            add(1, "piece: \"%s\", %s (type %s, color %s)", (text:gsub("^%s+", "")),
                line.type == disabledLine and "not worn" or "worn", tostring(line.type), color)
        else
            inPieces = false
        end
    end
    if not found then
        add(1, data and "no line about an item set" or "no tooltip")
    end

    -- The worn pieces, by the item set each belongs to, and what is worn where this piece goes.
    local equipLoc = select(9, C_Item.GetItemInfo(link))
    local bySet, order, sameKind, unknown = {}, {}, {}, {}
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local wornLink = GetInventoryItemLink("player", slot)
        if wornLink then
            local wornSetID, wornSetName = ItemSetOf(wornLink)
            local wornName, _, _, _, _, _, _, _, wornEquipLoc = C_Item.GetItemInfo(wornLink)
            local label = ("slot %d [%s]"):format(slot, tostring(wornName))
            if not wornName then
                -- The client can be without the item info of a worn piece; its set is then
                -- not known here, and the list below is short of it.
                unknown[#unknown + 1] = tostring(slot)
                C_Item.RequestLoadItemDataByID(wornLink)
            end
            if wornSetID then
                if not bySet[wornSetID] then
                    bySet[wornSetID] = { name = wornSetName, pieces = {} }
                    order[#order + 1] = wornSetID
                end
                table.insert(bySet[wornSetID].pieces, label)
            end
            if equipLoc and equipLoc ~= "" and wornEquipLoc == equipLoc then
                sameKind[#sameKind + 1] = ("%s, item set %s"):format(label,
                    wornSetID and ("%d \"%s\""):format(wornSetID, tostring(wornSetName)) or "none")
            end
        end
    end
    if #unknown > 0 then
        add(0, "Worn Pieces The Client Has No Item Info For (asked for; copy again): slots %s", table.concat(unknown, ", "))
    end
    add(0, "Worn Pieces Of Item Sets:%s", #order == 0 and " none" or "")
    for _, wornSetID in ipairs(order) do
        local entry = bySet[wornSetID]
        add(1, "%d \"%s\": %d worn: %s", wornSetID, tostring(entry.name), #entry.pieces, table.concat(entry.pieces, "; "))
    end
    add(0, "Worn With The Same Equip Location (%s): %s", tostring(equipLoc),
        #sameKind > 0 and table.concat(sameKind, "; ") or "none")
    return lines
end

function DebugFrameMixin:BuildClipboardPayload(item)
    local lines = {}

    local function formatValue(value)
        local valueType = type(value)
        if valueType == "boolean" then
            return value and "true" or "false"
        elseif valueType == "number" then
            return tostring(value)
        elseif valueType == "string" then
            return value
        elseif value == nil then
            return "nil"
        else
            return tostring(value)
        end
    end

    local function addLine(indent, text)
        table.insert(lines, (string.rep("  ", indent or 0) .. text))
    end

    local function addKV(indent, label, value)
        addLine(indent, label .. ": " .. formatValue(value))
    end

    local function appendTable(tbl, indent)
        if type(tbl) ~= "table" then
            addLine(indent, formatValue(tbl))
            return
        end

        if next(tbl) == nil then
            addLine(indent, "{}")
            return
        end

        local isArray = true
        local count = 0
        for key in pairs(tbl) do
            count = count + 1
            if type(key) ~= "number" then
                isArray = false
                break
            end
        end

        if isArray then
            for index = 1, #tbl do
                local value = tbl[index]
                if type(value) == "table" then
                    addLine(indent, "-")
                    appendTable(value, indent + 1)
                else
                    addLine(indent, "- " .. formatValue(value))
                end
            end
        else
            local keys = {}
            for key in pairs(tbl) do
                table.insert(keys, key)
            end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

            for _, key in ipairs(keys) do
                local value = tbl[key]
                if type(value) == "table" then
                    addLine(indent, tostring(key) .. ":")
                    appendTable(value, indent + 1)
                else
                    addLine(indent, tostring(key) .. ": " .. formatValue(value))
                end
            end
        end
    end

    local function addTable(indent, label, tbl)
        if not tbl or (type(tbl) == "table" and next(tbl) == nil) then
            addLine(indent, label .. ": {}")
            return
        end
        addLine(indent, label .. ":")
        appendTable(tbl, indent + 1)
    end

    local function AddEJDiagnostics(indent, sources)
        if not sources then
            return
        end

        for _, sourceID in ipairs(sources) do
            local diag = variantEJDiagnostics[sourceID]
            if diag then
                local finalSource = diag.finalLinkSource or diag.failureReason or "none"
                local linkSummary = diag.finalLink or diag.lootInfoLink or "nil"
                addLine(indent, string.format("EJ Source %s: final=%s, link=%s",
                    tostring(sourceID), finalSource, linkSummary))

                if diag.dropInstanceName or diag.dropEncounterName or diag.dropDifficultyName then
                    addLine(indent + 1, string.format("Drop: %s - %s (%s)",
                        tostring(diag.dropInstanceName or "unknown"),
                        tostring(diag.dropEncounterName or "unknown"),
                        tostring(diag.dropDifficultyName or "unknown")))
                end

                if diag.instanceID or diag.encounterID or diag.difficultyID then
                    addLine(indent + 1, string.format("IDs: instance=%s encounter=%s difficulty=%s",
                        tostring(diag.instanceID or "nil"),
                        tostring(diag.encounterID or "nil"),
                        tostring(diag.difficultyID or "nil")))
                end
            end
        end
    end

    addLine(0, "=== CaerdonWardrobe Debug Export ===")
    addKV(0, "Generated", date("%Y-%m-%d %H:%M:%S"))

    local addonVersion
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        addonVersion = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
    elseif GetAddOnMetadata then
        addonVersion = GetAddOnMetadata(ADDON_NAME, "Version")
    end
    if addonVersion then
        addKV(0, "Addon Version", addonVersion)
    end

    local buildVersion, buildNumber, _, tocVersion = GetBuildInfo()
    if buildVersion and buildNumber then
        addKV(0, "Game Build", buildVersion .. " (" .. buildNumber .. ")")
    end
    if tocVersion then
        addKV(0, "Client TOC", tocVersion)
    end
    if CaerdonAPI and CaerdonAPI.GetClientFlavor then
        local flavorName, projectID = CaerdonAPI:GetClientFlavor()
        addKV(0, "Client Flavor", flavorName .. " (WOW_PROJECT_ID " .. tostring(projectID) .. ")")
    end

    if C_AddOns then
        local numAddOns = C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns() or 0
        local loadedAddOns = {}

        if numAddOns and numAddOns > 0 then
            for index = 1, numAddOns do
                local addOnName = C_AddOns.GetAddOnName and C_AddOns.GetAddOnName(index)
                if addOnName then
                    local loaded = C_AddOns.IsAddOnLoaded and select(1, C_AddOns.IsAddOnLoaded(addOnName))
                    if loaded then
                        local version = C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addOnName, "Version")
                        table.insert(loadedAddOns, {
                            name = addOnName,
                            version = version
                        })
                    end
                end
            end

            table.sort(loadedAddOns, function(a, b)
                return a.name < b.name
            end)
        end

        addLine(0, "")
        addLine(0, "[Addon]")

        local stateName, stateRealm = UnitName("player")
        local playerNameForState = stateName or "0"
        if stateName and stateRealm and stateRealm ~= "" then
            playerNameForState = stateName .. "-" .. stateRealm
        end
        local _, addOnTitle, addOnNotes, addOnLoadable, addOnReason, addOnSecurity = C_AddOns.GetAddOnInfo(ADDON_NAME)
        local addOnInterface = C_AddOns.GetAddOnInterfaceVersion and C_AddOns.GetAddOnInterfaceVersion(ADDON_NAME)
        local loadedOrLoading, loaded = C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(ADDON_NAME)
        local loadOnDemand = C_AddOns.IsAddOnLoadOnDemand and C_AddOns.IsAddOnLoadOnDemand(ADDON_NAME)
        local defaultEnabled = C_AddOns.IsAddOnDefaultEnabled and C_AddOns.IsAddOnDefaultEnabled(ADDON_NAME)
        local hadLoadError = C_AddOns.DoesAddOnHaveLoadError and C_AddOns.DoesAddOnHaveLoadError(ADDON_NAME)
        local enableState = C_AddOns.GetAddOnEnableState and C_AddOns.GetAddOnEnableState(ADDON_NAME, playerNameForState)
        local loadableState
        local loadableReason
        if C_AddOns.IsAddOnLoadable then
            loadableState, loadableReason = C_AddOns.IsAddOnLoadable(ADDON_NAME, playerNameForState)
        end

        local function captureVarArgs(getter)
            if not getter then
                return {}
            end

            local values = { getter(ADDON_NAME) }
            local result = {}
            for _, value in ipairs(values) do
                if value and value ~= "" then
                    table.insert(result, value)
                end
            end
            return result
        end

        local dependencies = captureVarArgs(C_AddOns.GetAddOnDependencies)
        local optionalDependencies = captureVarArgs(C_AddOns.GetAddOnOptionalDependencies)

        addKV(1, "Title", addOnTitle)
        addKV(1, "Notes", addOnNotes)
        addKV(1, "Interface Version", addOnInterface)
        addKV(1, "Loadable", addOnLoadable)
        addKV(1, "Load Reason", addOnReason)
        addKV(1, "Security", addOnSecurity)
        addKV(1, "Load On Demand", loadOnDemand)
        addKV(1, "Default Enabled", defaultEnabled)
        addKV(1, "Had Load Error", hadLoadError)
        addKV(1, "Enable State", enableState)
        addKV(1, "Is Loaded Or Loading", loadedOrLoading)
        addKV(1, "Is Fully Loaded", loaded)
        addKV(1, "Is AddOn Loadable", loadableState)
        addKV(1, "Loadable Reason", loadableReason)

        if #dependencies > 0 then
            addLine(1, "Dependencies:")
            for _, dependency in ipairs(dependencies) do
                addLine(2, "- " .. dependency)
            end
        else
            addLine(1, "Dependencies: none")
        end

        if #optionalDependencies > 0 then
            addLine(1, "Optional Dependencies:")
            for _, dependency in ipairs(optionalDependencies) do
                addLine(2, "- " .. dependency)
            end
        end

        if #loadedAddOns > 0 then
            addLine(1, "Loaded AddOns:")
            for _, addonEntry in ipairs(loadedAddOns) do
                local entryText = addonEntry.name
                if addonEntry.version and addonEntry.version ~= "" then
                    if addonEntry.version:match("^[vV]") then
                        entryText = entryText .. " (" .. addonEntry.version .. ")"
                    else
                        entryText = entryText .. " (v" .. addonEntry.version .. ")"
                    end
                end
                addLine(2, "- " .. entryText)
            end
        end
    end

    addLine(0, "")
    addLine(0, "[Player]")
    addKV(1, "Level", UnitLevel("player"))

    local className, classFile, classID = UnitClass("player")
    addKV(1, "Class",
        string.format("%s (%s, ID %s)", className or "Unknown", classFile or "?", tostring(classID or "nil")))

    local specIndex = CaerdonAPI:GetPlayerSpecializationIndex()
    local specName
    if specIndex then
        _, specName = CaerdonAPI:GetSpecializationInfo(specIndex)
    end
    addKV(1, "Specialization", specName or "None")

    -- Clients without specializations (WoW Forever): points per talent tree, and the tree the
    -- Pawn scale filter treats as the toon's spec.
    local talentTrees, talentTreeReason = CaerdonAPI:GetTalentTrees()
    if talentTrees then
        local treeParts = {}
        for _, tree in ipairs(talentTrees) do
            treeParts[#treeParts + 1] = string.format("%d %s (%d)", tree.index, tostring(tree.name), tree.spent)
        end
        addKV(1, "Talent Trees", table.concat(treeParts, ", "))
        local primaryIndex, primaryName = CaerdonAPI:GetPrimaryTalentTree()
        addKV(1, "Primary Talent Tree", primaryIndex and string.format("%d %s", primaryIndex, tostring(primaryName)) or
            "none (no points spent, or a tie)")
    else
        addKV(1, "Talent Trees", "unavailable (" .. tostring(talentTreeReason) .. ")")
    end

    addKV(1, "Race", UnitRace("player"))
    addKV(1, "Faction", UnitFactionGroup("player"))
    local genderID = UnitSex("player")
    local genderText = genderID == 2 and "Male" or genderID == 3 and "Female" or "Unknown"
    addKV(1, "Gender", genderText .. " (" .. tostring(genderID or "nil") .. ")")
    -- What the toon's saved data is filed under, and what its first use took over.
    do
        local key, from = CaerdonAPI:GetRealmKey()
        addKV(1, "Saved Under", string.format("%s (%s)", key and ("\"" .. tostring(key) .. "\"") or "nothing yet", tostring(from)))
        local taken = CaerdonAPI:GetRealmTakeOver()
        if taken then
            if taken.problem then
                addKV(1, "Saved Data Taken Over", "failed: " .. tostring(taken.problem))
            else
                addKV(1, "Saved Data Taken Over", string.format("%s; this toon's record under the empty key: %s",
                    taken.from and string.format("%d toons from the realm's old key \"%s\"", taken.toons, tostring(taken.from)) or
                        string.format("none from an old realm key (%d hold a toon of this name)", taken.candidates),
                    taken.fromEmpty and "taken" or "none"))
            end
        end
    end

    addLine(0, "")
    addLine(0, "[Item]")
    if self.copyWaitNote then
        addKV(1, "Waited For Its Data", self.copyWaitNote)
    end
    local itemLink = item:GetItemLink() or self.currentItem
    addKV(1, "Link", itemLink or "Unavailable")
    local itemString = itemLink and itemLink:match("|H(.-)|h")
    addKV(1, "Item String", itemString or "Unavailable")
    -- What the window passed beside the link, and what is on its button: the verdict below is
    -- of the piece as the window gave it.
    do
        local ask = self.currentAsk
        local extraData = item.extraData
        if extraData then
            local parts = {}
            if extraData.overrideItemLevel then
                parts[#parts + 1] = format("item level %s (the link's own: %s)", tostring(extraData.overrideItemLevel),
                    tostring(itemLink and C_Item.GetDetailedItemLevelInfo(itemLink) or "?"))
            end
            if extraData.keySuffix then
                parts[#parts + 1] = format("suffix %s, named \"%s\" (the link's name: \"%s\")", tostring(extraData.keySuffix),
                    tostring(extraData.keyName), tostring(item:GetItemName()))
            end
            if extraData.appearanceSourceID then
                parts[#parts + 1] = "appearance source " .. tostring(extraData.appearanceSourceID)
            end
            addKV(1, "Passed By The Window", #parts > 0 and table.concat(parts, ", ") or "nothing the export names")
        end
        if ask and ask.drawn then
            addKV(1, "Its Button", ask.drawn)
        end
    end
    if self.openedFrom then
        addKV(1, "Opened From", self.openedFrom)
    end
    addKV(1, "Item ID", item:GetItemID())
    addKV(1, "Item GUID", item:GetItemGUID())

    local infoLink = itemLink or item:GetItemID()
    local itemName, itemLinkFull, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
    itemEquipLoc, itemTexture, sellPrice, classIDInfo, subclassIDInfo, bindType, expansionID, setID, isCraftingReagent

    if infoLink then
        itemName, itemLinkFull, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
        itemEquipLoc, itemTexture, sellPrice, classIDInfo, subclassIDInfo, bindType, expansionID, setID, isCraftingReagent =
            C_Item.GetItemInfo(infoLink)
    end

    addKV(1, "Name", itemName)
    addKV(1, "Quality", itemQuality and _G[("ITEM_QUALITY%d_DESC"):format(itemQuality)] or itemQuality)
    addKV(1, "Item Level", itemLevel)
    addKV(1, "Required Level", itemMinLevel)
    addKV(1, "Type", itemType)
    addKV(1, "SubType", itemSubType)
    addKV(1, "Equip Location", itemEquipLoc)
    addKV(1, "Class ID", classIDInfo)
    addKV(1, "Subclass ID", subclassIDInfo)
    addKV(1, "Bind Type", bindType)
    addKV(1, "Expansion ID", expansionID)
    addKV(1, "Set ID", setID)
    addKV(1, "Is Crafting Reagent", isCraftingReagent)
    addKV(1, "Stack Count", itemStackCount)
    addKV(1, "Texture ID", itemTexture)
    addKV(1, "Sell Price", sellPrice)
    addKV(1, "Inventory Type Name", item:GetInventoryTypeName() or "None")
    addKV(1, "Min Level (API)", item:GetMinLevel())
    -- The stats the client has for the link, by their keys: a link whose stats are still to be
    -- rolled (a plain item the auction house names a row by) has placeholders among them.
    do
        local stats = itemLink and C_Item.GetItemStats and C_Item.GetItemStats(itemLink)
        local parts = {}
        for key, value in pairs(type(stats) == "table" and stats or {}) do
            parts[#parts + 1] = format("%s %s", tostring(key), tostring(value))
        end
        table.sort(parts)
        addKV(1, "Link Stats (API)", #parts > 0 and table.concat(parts, ", ") or "none")
    end
    addKV(1, "Binding", item:GetBinding())

    local itemLocation = item:GetItemLocation()
    if itemLocation and itemLocation:HasAnyLocation() then
        if itemLocation:IsBagAndSlot() then
            local bag, slot = itemLocation:GetBagAndSlot()
            addKV(1, "Bag Slot", bag .. ":" .. slot)
        end

        if itemLocation:IsEquipmentSlot() then
            addKV(1, "Equipment Slot", itemLocation:GetEquipmentSlot())
        end
    end

    -- Every tooltip line with every field it carries, for troubleshooting and feature development.
    local rowKey = nil
    do
        -- A level beside the link is passed for a piece named by item key, and by nothing else.
        local extraData = item.extraData
        if extraData and extraData.overrideItemLevel and item:GetItemID() then
            rowKey = { itemID = item:GetItemID(), itemLevel = extraData.overrideItemLevel, itemSuffix = extraData.keySuffix or 0 }
        end
    end
    for _, row in ipairs(self:GetTooltipReportRows(itemLink, itemLocation, rowKey)) do
        addLine(row.indent, row.text)
    end

    -- Which transmog collection events arrived this session and whether a refresh followed.
    -- Answers "the appearance was learned but the icon did not update" without /etrace.
    if CaerdonWardrobe and CaerdonWardrobe.GetTransmogEventLog then
        local eventLog, lastRefreshTime = CaerdonWardrobe:GetTransmogEventLog()
        local now = GetTime()
        addLine(0, "")
        addLine(0, "[Transmog Collection Events]")
        addKV(1, "Refresh Generation", CaerdonWardrobe:GetRefreshGeneration())
        addKV(1, "Last Refresh",
            lastRefreshTime and string.format("%.1fs ago", now - lastRefreshTime) or "none this session")
        -- The skills an item's tooltip asked a rank of: a weapon skill or Defense among them
        -- refreshes with every point from then on (CaerdonRefresh.lua).
        local skillsAsked = NS.Refresh:GetSkillRequirementsNoted()
        addKV(1, "Skill Ranks A Tooltip Asked For",
            #skillsAsked > 0 and table.concat(skillsAsked, ", ") or "none this session")
        if eventLog and #eventLog > 0 then
            addLine(1, "Events (oldest first):")
            for _, entry in ipairs(eventLog) do
                addLine(2, string.format("- %.1fs ago %s(%s)", now - entry.time, entry.event, entry.args))
            end
        else
            addLine(1, "Events: none this session")
        end
    end

    -- What the last decorated button in each window measured (recorded while debug is enabled).
    -- Session-wide, not about this item: it is here to compare the windows' hard-coded sizes.
    if CaerdonButtonGeometry and CaerdonButtonGeometry.GetReportLines then
        addLine(0, "")
        addLine(0, "[Button Geometry]")
        local ok, geometryLines = pcall(CaerdonButtonGeometry.GetReportLines, CaerdonButtonGeometry)
        if ok then
            for _, geometryLine in ipairs(geometryLines) do
                addLine(geometryLine.indent, geometryLine.text)
            end
        else
            addKV(1, "Report failed", tostring(geometryLines))
        end
    end

    -- Whether each bag addon or other integration found the functions it hooks in that addon's
    -- current version. Session-wide, not about this item: an integration that stopped drawing
    -- after the other addon updated shows here as "missing".
    if CaerdonIntegrations and CaerdonIntegrations.GetReportLines then
        addLine(0, "")
        addLine(0, "[Integrations]")
        local ok, integrationLines = pcall(CaerdonIntegrations.GetReportLines, CaerdonIntegrations)
        if ok then
            for _, integrationLine in ipairs(integrationLines) do
                addLine(integrationLine.indent, integrationLine.text)
            end
        else
            addKV(1, "Report failed", tostring(integrationLines))
        end
    end

    -- What the addon has cost this session: login milestones, what the client was asked to
    -- load, what caused each full refresh and, when its profile has run, the time and memory
    -- of the functions a draw goes through. Session-wide, not about this item.
    if CaerdonCounters and CaerdonCounters.GetReportLines then
        addLine(0, "")
        addLine(0, "[Counters]")
        local ok, counterLines = pcall(CaerdonCounters.GetReportLines, CaerdonCounters)
        if ok then
            for _, counterLine in ipairs(counterLines) do
                addLine(counterLine.indent, counterLine.text)
            end
        else
            addKV(1, "Report failed", tostring(counterLines))
        end
    end

    addLine(0, "")
    addLine(0, "[Caerdon]")
    local identifiedType = item:GetCaerdonItemType()
    addKV(1, "Identified Type", identifiedType)

    local locationInfo = {
        locationKey = "debugframe-copy-" .. tostring(item:GetItemID() or "unknown"),
        isDebugFrame = true
    }
    local isReady, mogStatus, bindingStatus, bindingResult, statusTransmogInfo = item:GetCaerdonStatus(self, locationInfo)
    addKV(1, "Status Ready", isReady)
    addKV(1, "Mog Status", mogStatus)
    addKV(1, "Binding Status", bindingStatus)
    if bindingResult then
        -- unusableItem / skillTooLow come from the red-text tooltip scan and drive canEquipForPlayer
        addTable(1, "Binding Result", bindingResult)
    end
    -- What the client says the item's use is aimed at: a use that needs an enemy does not keep
    -- a learned piece from "sellable" (CaerdonItemMixin:HasHostileUse).
    local useSpellName, useSpellID = C_Item.GetItemSpell(item:GetItemID())
    if useSpellID then
        addLine(1, "Use Spell:")
        addKV(2, "Name", useSpellName)
        addKV(2, "Spell ID", useSpellID)
        addKV(2, "C_Item.IsHarmfulItem", C_Item.IsHarmfulItem(item:GetItemID()))
        addKV(2, "C_Item.IsHelpfulItem", C_Item.IsHelpfulItem(item:GetItemID()))
        addKV(2, "Hostile Use", item:HasHostileUse())
        addKV(2, "Teleport Use", item:HasTeleportUse())
    else
        addKV(1, "Use Spell", "none")
    end

    local forDebugUse = item:GetForDebugUse()
    if forDebugUse then
        addTable(1, "For Debug Use", forDebugUse)
    end

    local itemData = item:GetItemData()
    local transmogInfo
    if itemData and itemData.GetTransmogInfo then
        transmogInfo = itemData:GetTransmogInfo()
    end

    local transmogDebugData
    if identifiedType == CaerdonItemType.Equipment then
        transmogDebugData = self:CollectTransmogDebugData(item, transmogInfo)
    end

    if transmogDebugData and transmogDebugData.api then
        local api = transmogDebugData.api

        local hasAPIInfo = (api.itemInfo and (api.itemInfo.appearanceID or api.itemInfo.sourceID))
            or api.playerHasTransmog ~= nil
            or (api.playerSpecs and (api.playerSpecs.lootSpecID or api.playerSpecs.activeSpecID))
            or (api.itemSpecs and api.itemSpecs.descriptions)
            or (api.sourceSpecs and api.sourceSpecs.descriptions)
            or api.playerCanCollectSource or api.accountCanCollectSource
            or api.sourceInfo or api.appearanceInfo or api.canItemTransmog
            or api.doesItemContainSpec or api.detailedItemLevelInfo or api.setBonusesForSpec
            or (api.validSourcesForClass and #api.validSourcesForClass > 0)
            or api.appearanceSourceInfo or api.artifactInfo

        if hasAPIInfo then
            addLine(0, "")
            addLine(0, "[Transmog (API Responses)]")

            if api.itemInfo then
                local appearanceValue = tostring(api.itemInfo.appearanceID)
                if api.itemInfo.requestSource then
                    appearanceValue = appearanceValue .. " (via " .. api.itemInfo.requestSource .. ")"
                end
                addKV(1, "C_TransmogCollection.GetItemInfo.appearanceID", appearanceValue)
                addKV(1, "C_TransmogCollection.GetItemInfo.sourceID", api.itemInfo.sourceID)
            end

            if api.playerHasTransmog ~= nil then
                addKV(1, "PlayerHasTransmogItemModifiedAppearance", api.playerHasTransmog)
            end

            if api.playerSpecs then
                if api.playerSpecs.lootSpecID ~= nil then
                    addKV(1, "GetLootSpecialization", api.playerSpecs.lootSpecID)
                    if api.playerSpecs.lootSpecLabel and api.playerSpecs.lootSpecLabel ~= tostring(api.playerSpecs.lootSpecID) then
                        addKV(1, "GetLootSpecialization (Label)", api.playerSpecs.lootSpecLabel)
                    end
                end
                if api.playerSpecs.activeSpecID then
                    addKV(1, "GetSpecializationInfo (Active Spec ID)", api.playerSpecs.activeSpecID)
                    if api.playerSpecs.activeSpecLabel and
                        api.playerSpecs.activeSpecLabel ~= tostring(api.playerSpecs.activeSpecID) then
                        addKV(1, "GetSpecializationInfo (Active Spec Label)", api.playerSpecs.activeSpecLabel)
                    end
                end
            end

            if api.playerClass then
                addKV(1, "Player Class ID", api.playerClass.classID)
                if api.playerClass.className then
                    addKV(2, "Class Name", api.playerClass.className)
                end
                if api.playerClass.classFile then
                    addKV(2, "Class File", api.playerClass.classFile)
                end
            end

            if api.itemSpecs and api.itemSpecs.descriptions then
                addKV(1, "C_Item.GetItemSpecInfo (Item)", table.concat(api.itemSpecs.descriptions, "; "))
            end

            if api.sourceSpecs and api.sourceSpecs.descriptions then
                addKV(1, "C_Item.GetItemSpecInfo (Source Item)", table.concat(api.sourceSpecs.descriptions, "; "))
            end

            if api.doesItemContainSpec then
                if api.doesItemContainSpec.playerResult ~= nil then
                    addLine(1, "C_Item.DoesItemContainSpec (Player Spec):")
                    addKV(2, "Spec ID", api.doesItemContainSpec.playerSpecID)
                    addKV(2, "Result", api.doesItemContainSpec.playerResult)
                end
                if api.doesItemContainSpec.specResults and #api.doesItemContainSpec.specResults > 0 then
                    addLine(1, "C_Item.DoesItemContainSpec (Per Item Spec):")
                    for _, specResult in ipairs(api.doesItemContainSpec.specResults) do
                        addKV(2, FormatSpecIDText(specResult.specID) or tostring(specResult.specID), specResult.result)
                    end
                end
            end

            if api.detailedItemLevelInfo then
                addLine(1, "C_Item.GetDetailedItemLevelInfo:")
                addKV(2, "actualItemLevel", api.detailedItemLevelInfo.actualItemLevel)
                addKV(2, "previewItemLevel", api.detailedItemLevelInfo.previewItemLevel)
                addKV(2, "sparseItemLevel", api.detailedItemLevelInfo.sparseItemLevel)
            end

            if api.setBonusesForSpec then
                addLine(1, "C_Item.GetSetBonusesForSpecializationByItemID:")
                addKV(2, "specID", api.setBonusesForSpec.specID)
                if api.setBonusesForSpec.setBonusSpellIDs then
                    addKV(2, "spellIDs", table.concat(api.setBonusesForSpec.setBonusSpellIDs, ", "))
                end
            end

            if api.playerCanCollectSource then
                addLine(1, "C_TransmogCollection.PlayerCanCollectSource:")
                addKV(2, "isInfoReady", api.playerCanCollectSource.isInfoReady)
                addKV(2, "canCollect", api.playerCanCollectSource.canCollect)
            end

            if api.accountCanCollectSource then
                addLine(1, "C_TransmogCollection.AccountCanCollectSource:")
                addKV(2, "isInfoReady", api.accountCanCollectSource.isInfoReady)
                addKV(2, "canCollect", api.accountCanCollectSource.canCollect)
            end

            if api.canItemTransmog then
                addLine(1, "C_Item.CanItemTransmogAppearance:")
                addKV(2, "canTransmog", api.canItemTransmog.canTransmog)
                addKV(2, "failureReason", api.canItemTransmog.failureReason)
                addKV(2, "failureArg", api.canItemTransmog.failureArg)
            end

            if api.artifactInfo then
                addLine(1, "C_ArtifactUI:")
                addKV(2, "IsArtifactItem", api.artifactInfo.isArtifactItem)
                if api.artifactInfo.isArtifactDisabled ~= nil then
                    addKV(2, "IsArtifactDisabled", api.artifactInfo.isArtifactDisabled)
                end
                if api.artifactInfo.isEquippedArtifactDisabled ~= nil then
                    addKV(2, "IsEquippedArtifactDisabled", api.artifactInfo.isEquippedArtifactDisabled)
                end
            end

            if api.sourceInfo then
                addTable(1, "C_TransmogCollection.GetSourceInfo", api.sourceInfo)
                if api.sourceInfo.useErrorType then
                    addKV(1, "Source useErrorType Label (Derived)",
                        TRANSMOG_USE_ERROR_LABELS[api.sourceInfo.useErrorType] or "Unknown")
                end
            end

            if api.appearanceInfo then
                addTable(1, "C_TransmogCollection.GetAppearanceInfoBySource", api.appearanceInfo)
            end

            if api.appearanceSourceInfo then
                addTable(1, "C_TransmogCollection.GetAppearanceSourceInfo", api.appearanceSourceInfo)
            end

            if api.validSourcesForClass and #api.validSourcesForClass > 0 then
                addLine(1, "C_TransmogCollection.GetValidAppearanceSourcesForClass:")
                for _, sourceInfo in ipairs(api.validSourcesForClass) do
                    addLine(2, string.format("Source %s (item %s)", tostring(sourceInfo.sourceID),
                        tostring(sourceInfo.itemID)))
                    addKV(3, "playerCanCollect", sourceInfo.playerCanCollect)
                    addKV(3, "isValidSourceForPlayer", sourceInfo.isValidSourceForPlayer)
                    addKV(3, "useErrorType", sourceInfo.useErrorType)
                    if sourceInfo.useError then
                        addKV(3, "useError", sourceInfo.useError)
                    end
                end
            end
        end
    end

    if transmogInfo then
        addLine(0, "")
        addLine(0, "[Transmog (Caerdon Processed)]")
        if transmogInfo.comparedGearMissing then
            -- Asked afresh for the export, and put off: every line below is empty for that reason.
            addLine(1, "not ready: the data of the gear it is compared with is not in the client's cache just now (asked for; copy again)")
        end
        addKV(1, "needsItem", transmogInfo.needsItem)
        addKV(1, "otherNeedsItem", transmogInfo.otherNeedsItem)
        addKV(1, "isCompletionistItem", transmogInfo.isCompletionistItem)
        addKV(1, "matchesLootSpec", transmogInfo.matchesLootSpec)
        addKV(1, "hasMetRequirements", transmogInfo.hasMetRequirements)
        addKV(1, "canEquip", transmogInfo.canEquip)
        addKV(1, "canEquipForPlayer", transmogInfo.canEquipForPlayer)
        addKV(1, "typeRefused", transmogInfo.typeRefused and
            "true (a piece with no look, of a type the client's tooltip marks as not the toon's)" or "false")
        addKV(1, "playerCanCollectSource", transmogInfo.playerCanCollectSource)
        addKV(1, "isTransmog", transmogInfo.isTransmog)
        addKV(1, "isUpgrade", transmogInfo.isUpgrade)
        addKV(1, "uniqueUpgradeBlocked", transmogInfo.uniqueUpgradeBlocked)
        addKV(1, "uniqueUpgradeCandidate", transmogInfo.uniqueUpgradeCandidate)
        addKV(1, "betterItemEquipped", transmogInfo.betterItemEquipped)
        addKV(1, "equalItemLevelEquipped", transmogInfo.equalItemLevelEquipped)
        addKV(1, "identicalToEquipped", transmogInfo.identicalToEquipped)
        addKV(1, "equippedLineComparison", transmogInfo.equippedLineComparison)
        addKV(1, "upgradeItemLevelDelta", transmogInfo.upgradeItemLevelDelta)
        addKV(1, "pawnIdentifiedUpgrade", transmogInfo.pawnIdentifiedUpgrade)
        addKV(1, "pawnPrefersEquipped", transmogInfo.pawnPrefersEquipped)
        addKV(1, "pawnOffTreeUpgrade", transmogInfo.pawnOffTreeUpgrade)
        addKV(1, "pawnUpgradeScales", transmogInfo.pawnUpgradeScales)
        addKV(1, "pawnComparison", transmogInfo.pawnComparison)
        addKV(1, "wornVerdict", CaerdonEquipment.GetWornVerdictDescription and
            CaerdonEquipment:GetWornVerdictDescription(item) or "not asked (no Pawn)")
        addKV(1, "pawnScaleFilter", CaerdonEquipment.GetPawnScaleFilterDescription and
            CaerdonEquipment:GetPawnScaleFilterDescription() or "none (every visible Pawn scale counts)")
        addKV(1, "pawnScalesShown", CaerdonEquipment.GetShownPawnScalesDescription and
            CaerdonEquipment:GetShownPawnScalesDescription() or "not asked (no Pawn)")
        addKV(1, "offHandScale", CaerdonEquipment.GetOffHandScaleDescription and
            CaerdonEquipment:GetOffHandScaleDescription() or "not asked (no Pawn)")
        addKV(1, "otherSpecsWanted", CaerdonEquipment.GetOtherSpecChoiceDescription and
            CaerdonEquipment:GetOtherSpecChoiceDescription() or "no choice (no specs on this client)")
        addKV(1, "loadoutsCompared", CaerdonEquipment.GetLoadoutDescription and
            CaerdonEquipment:GetLoadoutDescription() or "none (only the worn gear)")
        addKV(1, "gearSetWorn", CaerdonEquipment.GetActiveSetDescription and
            CaerdonEquipment:GetActiveSetDescription() or "not read")
        addKV(1, "gearSetScales", CaerdonEquipment.GetGearSetScaleDescription and
            CaerdonEquipment:GetGearSetScaleDescription() or "none (no gear sets, or no Pawn)")
        addKV(1, "upgradeMatchesSpec", transmogInfo.upgradeMatchesSpec)
        do
            local icon = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon or {}
            addKV(1, "upgradeSettings", format("arrow %s; a higher item level counts %s; and against Pawn's scores %s; also for gear not worn %s; on gear set pieces %s; level gain %s",
                icon.ShowUpgradeIcon ~= false and "on" or "off",
                icon.ShowItemLevelUpgrades ~= false and "on" or "off",
                icon.ItemLevelOverPawn == true and "on" or "off",
                icon.ShowOtherSpecUpgrades == true and "on" or "off",
                icon.ShowUpgradeOnGearSets ~= false and "on" or "off",
                icon.ShowUpgradeLevelDelta and "on" or "off"))
        end
        addKV(1, "uniqueCategoryKey", transmogInfo.uniqueCategoryKey)
        addKV(1, "sourceID", transmogInfo.sourceID)
        addKV(1, "appearanceID", transmogInfo.appearanceID)
        addKV(1, "isRecraftable", transmogInfo.isRecraftable)
        addKV(1, "validSourceNotCollectable", transmogInfo.validSourceNotCollectable)
        addKV(1, "validSourceNotCollectableKnownLook", transmogInfo.validSourceNotCollectableKnownLook)
        addKV(1, "proficiencySourceNotCollectable", transmogInfo.proficiencySourceNotCollectable)
        addKV(1, "proficiencySourceNotCollectableKnownLook", transmogInfo.proficiencySourceNotCollectableKnownLook)
        addKV(1, "noCollectionCategory", transmogInfo.noCollectionCategory)
    end

    -- What the piece would look like raised on its upgrade track or converted at the Catalyst,
    -- with every answer of the client's behind it. Asked afresh for this copy, whatever the
    -- verdict above was made from.
    if identifiedType == CaerdonItemType.Equipment and CaerdonTransformLooks then
        local upgradeDisabled = bindingResult and bindingResult.upgradeLevelDisabled or false
        local lookLines, lookInfo = CaerdonTransformLooks:Explain(item, transmogInfo and transmogInfo.sourceID or nil,
            upgradeDisabled)
        addLine(0, "")
        addLine(0, "[Looks After a Change]")
        addKV(1, "marked (the setting)", CaerdonWardrobeConfig.Icon.ShowLooksAfterChange ~= false)
        addKV(1, "cache entry of its own", CaerdonTransformLooks:MayBeConverted(item, item:GetItemLink()))
        -- A gear set's piece is not marked, whatever the lines below find for it.
        local lookSets = itemData and itemData.GetEquipmentSets and itemData:GetEquipmentSets()
        addKV(1, "in a gear set (not marked while it is)", lookSets and table.concat(lookSets, ", ") or false)
        -- What a link converts to is worked out once and kept for the session.
        if CaerdonTransformLooks.GetKeptAnswers then
            local keptLinks, keptUsed = CaerdonTransformLooks:GetKeptAnswers()
            addKV(1, "the Catalyst's piece kept this session", string.format("for %d links, used %d times in the place of asking again",
                keptLinks or 0, keptUsed or 0))
        end
        -- What the client answered when the verdict above was made, which may be a while ago
        -- and other than what it answers now.
        local verdictWhy = statusTransmogInfo and statusTransmogInfo.transformLookWhy
        if verdictWhy then
            addLine(1, ("when the verdict above was made (%.1f s ago):"):format(GetTime() - (statusTransmogInfo.transformLookAt or GetTime())))
            for _, lookLine in ipairs(verdictWhy) do
                addLine(2, lookLine)
            end
            if #verdictWhy == 0 then
                addLine(2, "nothing was noted")
            end
            addLine(1, "asked afresh now:")
        else
            addLine(1, "when the verdict above was made: nothing was asked about a look (or the verdict is not ready)")
        end
        for _, lookLine in ipairs(lookLines) do
            addLine(1, lookLine)
        end
        -- Where the piece is taken, which is what the icon says.
        local lookRoute, lookSecondRoute = CaerdonTransformLooks:GetRoute(lookInfo,
            CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem, transmogInfo and transmogInfo.canEquip)
        addKV(1, "taken to (the icon)", lookRoute or "nowhere")
        addKV(1, "and to (the small mark on it)", lookSecondRoute or "nowhere else")
    end

    -- A piece's PVP floor beside its level, whether the floor counts now, and the piece at its
    -- floor as a set marked for PVP scores it.
    if identifiedType == CaerdonItemType.Equipment and CaerdonEquipment.ExplainPvpLevel then
        addLine(0, "")
        addLine(0, "[PVP Item Level]")
        for _, pvpLine in ipairs(CaerdonEquipment:ExplainPvpLevel(item)) do
            addLine(1, pvpLine)
        end
    end

    -- Each comparison tooltip the client puts beside an item's, as it stands, and what the
    -- addon last made of it (features/Tooltip.lua).
    if identifiedType == CaerdonItemType.Equipment and NS.Tooltip and NS.Tooltip.GetComparisonReport then
        addLine(0, "")
        addLine(0, "[Comparison Tooltips]")
        for _, entry in ipairs(NS.Tooltip:GetComparisonReport()) do
            addLine(1, entry.state)
            if entry.last then
                addLine(2, entry.last)
            end
            if entry.sample then
                addLine(2, entry.sample)
            end
        end
    end

    -- Item sets (tier bonuses): what there is to tell whether putting a piece on would cost or
    -- gain a bonus. Nothing is judged by it yet.
    if identifiedType == CaerdonItemType.Equipment then
        addLine(0, "")
        addLine(0, "[Set Bonuses]")
        for _, setLine in ipairs(ExplainSetBonuses(item)) do
            addLine(1, setLine)
        end
    end

    if transmogDebugData and transmogDebugData.processed and transmogDebugData.processed.debugExtras then
        addLine(0, "")
        addLine(0, "[Transmog (Caerdon Debug Internals)]")
        addTable(1, "Debug Data", transmogDebugData.processed.debugExtras)
    end

    if identifiedType == CaerdonItemType.Housing then
        local housingInfo = itemData and itemData.GetHousingInfo and itemData:GetHousingInfo()
        if housingInfo then
            addLine(0, "")
            addLine(0, "[Housing]")
            addKV(1, "Entry Type", housingInfo.entryType)
            addKV(1, "Record ID", housingInfo.recordID)
            addKV(1, "Record ID From Item", housingInfo.recordFromItem)
            addKV(1, "Found By Item ID As Record", housingInfo.usedRecordFallback)
            addKV(1, "Subclass ID", housingInfo.subClassID)
            addKV(1, "Owned Stored", housingInfo.ownedStored)
            addKV(1, "Remaining Redeemable", housingInfo.entryInfo and housingInfo.entryInfo.remainingRedeemable)
            addKV(1, "Placed Count", housingInfo.placedCount)
            addKV(1, "Bag Count", housingInfo.bagCount)
            addKV(1, "Total Owned", housingInfo.totalOwned)
            addKV(1, "First Acquisition Bonus", housingInfo.firstAcquisitionBonus)
            addKV(1, "Show Quantity", housingInfo.showQuantity)
            addKV(1, "Max Stack", housingInfo.maxStack)
            addKV(1, "Icon Atlas", housingInfo.iconAtlas)
            addKV(1, "Icon Texture", housingInfo.iconTexture)
            addKV(1, "Source Text", housingInfo.sourceText)
            addKV(1, "Is Pending", housingInfo.isPending)
        end
    end

    -- The journal's own answers, which decide the verdict: a mount is learnable while the
    -- journal calls it uncollected, a pet while none of its species is collected.
    if identifiedType == CaerdonItemType.Mount then
        local mountInfo = itemData and itemData.GetMountInfo and itemData:GetMountInfo()
        if mountInfo then
            addLine(0, "")
            addLine(0, "[Mount]")
            addKV(1, "Mount ID", mountInfo.mountID)
            addKV(1, "Spell ID", mountInfo.spellID)
            addKV(1, "Name", mountInfo.name)
            addKV(1, "Is Collected", mountInfo.isCollected)
            addKV(1, "Is Usable", mountInfo.isUsable)
            addKV(1, "Is Faction Specific", mountInfo.isFactionSpecific)
            addKV(1, "Faction ID", mountInfo.factionID)
            addKV(1, "Hidden On Character", mountInfo.shouldHideOnChar)
            addKV(1, "Is Equipment", mountInfo.isEquipment)
            addKV(1, "Equipment Applied", mountInfo.isEquipmentApplied)
            addKV(1, "Needs Item", mountInfo.needsItem)
        end
    elseif identifiedType == CaerdonItemType.CompanionPet or identifiedType == CaerdonItemType.BattlePet then
        local petInfo
        if identifiedType == CaerdonItemType.CompanionPet then
            petInfo = itemData and itemData.GetCompanionPetInfo and itemData:GetCompanionPetInfo()
        else
            petInfo = itemData and itemData.GetBattlePetInfo and itemData:GetBattlePetInfo()
        end
        addLine(0, "")
        addLine(0, "[Pet]")
        if petInfo then
            addKV(1, "Species ID", petInfo.speciesID)
            addKV(1, "Name", petInfo.name)
            addKV(1, "Num Collected", petInfo.numCollected)
            addKV(1, "Limit", petInfo.limit)
            addKV(1, "Is Unique", petInfo.isUnique)
            addKV(1, "Is Tradeable", petInfo.isTradeable)
            addKV(1, "Is Obtainable", petInfo.isObtainable)
            addKV(1, "Can Battle", petInfo.canBattle)
            addKV(1, "Needs Item", petInfo.needsItem)
        else
            addLine(1, "The pet journal has no pet for this item.")
        end
    end

    if identifiedType == CaerdonItemType.Recipe then
        addLine(0, "")
        addLine(0, "[Recipe]")
        -- The item's use spell is the client's "Learning"; what it teaches is on its tooltip's
        -- teaching line, and that spell is the recipe's ID in the profession's list.
        local recipeSpellName, recipeSpellID = C_Item.GetItemSpell(item:GetItemLink())
        addKV(1, "Use Spell ID", recipeSpellID)
        addKV(1, "Use Spell Name", recipeSpellName)
        local taughtSpellID = item.GetTaughtSpellID and item:GetTaughtSpellID() or nil
        addKV(1, "Taught Spell ID", taughtSpellID or "none (no teaching line on its tooltip)")
        if CaerdonRecipe and CaerdonRecipe.FindRecipeID then
            local foundID, foundBy = CaerdonRecipe:FindRecipeID(item)
            addKV(1, "Recipe ID", foundID or "none (no list has shown its spell or its name)")
            if foundBy == "spell" then
                addKV(1, "Recipe Found By", "the spell its tooltip says it teaches")
            elseif foundBy == "name" then
                addKV(1, "Recipe Found By", taughtSpellID and "its name (no list has shown the taught spell)" or "its name")
            end
        end

        -- What Caerdon believes about the toon's rank in the recipe's profession (cached skill lines,
        -- then the live profession slots). Compare against the "Requires <skill> (<rank>)" tooltip line.
        local professionName = item:GetItemSubType()
        if professionName and CaerdonRecipe and CaerdonRecipe.GetPlayerSkillInfo then
            local hasSkillLine, _, knownRank = CaerdonRecipe:GetPlayerSkillInfo(item, professionName, 0)
            addKV(1, "Profession", professionName)
            addKV(1, "Has Skill Line", hasSkillLine)
            addKV(1, "Cached Skill Rank", knownRank)
        end

        if taughtSpellID then
            local tradeSkillRecipeInfo = C_TradeSkillUI.GetRecipeInfo(taughtSpellID)
            if tradeSkillRecipeInfo then
                addKV(1, "TradeSkill Learned", tradeSkillRecipeInfo.learned)
                addKV(1, "TradeSkill Recipe ID", tradeSkillRecipeInfo.recipeID)
                addKV(1, "TradeSkill Recipe Name", tradeSkillRecipeInfo.name)
            else
                addKV(1, "TradeSkill Recipe Info", "nil")
            end
        end

        if itemData and itemData.GetRecipeInfo then
            local recipeInfo = itemData:GetRecipeInfo()
            if recipeInfo then
                addKV(1, "Mixin Learned", recipeInfo.learned)
                addKV(1, "Can Learn", recipeInfo.canLearn)
                addKV(1, "First Craft", recipeInfo.firstCraft)

                if recipeInfo.createdItem then
                    addKV(1, "Created Item", recipeInfo.createdItem:GetItemName() or recipeInfo.createdItem:GetItemLink())
                    addKV(1, "Created Item ID", recipeInfo.createdItem:GetItemID())
                end

                if recipeInfo.schematic and recipeInfo.schematic.outputItemID then
                    addKV(1, "Schematic Output Item ID", recipeInfo.schematic.outputItemID)
                end
            else
                addKV(1, "Mixin Recipe Data", "nil (not in trade skill cache)")
            end
        end

        -- Why a known recipe is (or is not) kept for another toon: every other toon on the realm
        -- with the profession, from the saved per-toon data, and whether its list has the recipe.
        if itemData and itemData.GetOtherToonRecipeInfo then
            local otherToons = itemData:GetOtherToonRecipeInfo()
            if otherToons then
                addKV(1, "Saved Recipe Name", otherToons.recipeName)
                addKV(1, "In This Toon's Saved List", otherToons.knownByPlayer)
                addLine(1, "Other Toons With " .. tostring(otherToons.professionName) .. ":")
                for _, toon in ipairs(otherToons.toons) do
                    local reading
                    if toon.knowsRecipe then
                        reading = "knows it"
                    elseif not toon.recipesRecorded then
                        reading = "unknown (its recipes for this profession were never recorded)"
                    elseif toon.hasCap then
                        reading = string.format("has learned it (its recorded cap %s is at the cap the item gives, %s)",
                            tostring(toon.cap), tostring(otherToons.capTaught))
                    elseif toon.inRecordedList == false and toon.hasCap == nil then
                        reading = string.format("not known (its recorded list has no recipe of this name: the item teaches " ..
                            "no recipe of that list; its recorded cap %s, the cap the item gives %s)",
                            tostring(toon.cap), tostring(otherToons.capTaught))
                    else
                        if toon.hasCap == false then
                            reading = string.format("lacks it (its recorded cap %s is below the cap the item gives, %s)",
                                tostring(toon.cap), tostring(otherToons.capTaught))
                        elseif toon.inRecordedList then
                            reading = "lacks it (in its recorded list, not learned)"
                        else
                            reading = "lacks it (not among the recipes it knows; its whole list is not recorded, " ..
                                "open the profession on that toon)"
                        end
                        local asked = otherToons.requirement
                        if not asked then
                            reading = reading .. ": can learn it (the item asks for no rank)"
                        elseif not toon.skillRank then
                            reading = reading .. string.format(": can learn it (no rank saved for %s, so none is held against %d)",
                                tostring(asked.skillName), asked.rank)
                        elseif toon.skillRank < asked.rank then
                            reading = reading .. string.format(": rank too low (%s %d, the item asks for %d)",
                                tostring(asked.skillName), toon.skillRank, asked.rank)
                        else
                            reading = reading .. string.format(": can learn it (%s %d, the item asks for %d)",
                                tostring(asked.skillName), toon.skillRank, asked.rank)
                        end
                    end
                    addLine(2, string.format("%s (rank %s): %s", tostring(toon.name), tostring(toon.rank), reading))
                end
                addKV(1, "Toons That Can Learn It", #otherToons.missing)
                addKV(1, "Toons Whose Rank Is Too Low", #otherToons.tooLow)
                addKV(1, "Toons Not Recorded", #otherToons.unknown)
                addKV(1, "Toons Whose List Has No Such Recipe", #otherToons.notInList)
                if otherToons.requirement then
                    addKV(1, "Item Asks For", string.format("%s %d", tostring(otherToons.requirement.skillName),
                        otherToons.requirement.rank))
                    addKV(1, "Number In Its Use Line", otherToons.requirement.useNumber or "none, or more than one")
                    addKV(1, "Cap The Item Gives", otherToons.capTaught or "none (no number above the rank it asks for)")
                end
            else
                addKV(1, "Other Toons With Profession", "none")
            end
            addKV(1, "Can Be Handed Over", not item:IsSoulbound() and item:GetBinding() ~= CaerdonItemBind.BindOnPickup)
            addKV(1, "Show Recipes For Other Toons", CaerdonWardrobeConfig.Icon.ShowRecipesForOtherToons ~= false)
            addKV(1, "Show Recipe Learners In Tooltip",
                not (CaerdonWardrobeConfig.Tooltip and CaerdonWardrobeConfig.Tooltip.ShowRecipeLearners == false))
        end
    end

    if itemData and itemData.GetConsumableInfo then
        local consumableInfo = itemData:GetConsumableInfo()
        if consumableInfo then
            addLine(0, "")
            addLine(0, "[Consumable Info]")
            addKV(1, "needsItem", consumableInfo.needsItem)
            addKV(1, "otherNeedsItem", consumableInfo.otherNeedsItem)
            addKV(1, "ownPlusItem", consumableInfo.ownPlusItem)
            addKV(1, "lowSkillItem", consumableInfo.lowSkillItem)
            addKV(1, "lowSkillPlusItem", consumableInfo.lowSkillPlusItem)
            addKV(1, "otherNoLootItem", consumableInfo.otherNoLootItem)
            addKV(1, "validForCharacter", consumableInfo.validForCharacter)
            addKV(1, "canEquip", consumableInfo.canEquip)
            addKV(1, "isEnsemble", consumableInfo.isEnsemble)
        end
    end

    -- Why an item does (or does not) carry the quest icon without being a Quest-class item:
    -- the data sources' state plus every candidate quest and the reason it was kept or dropped.
    if CaerdonQuestItems and item.GetQuestItemInfo then
        local questState = CaerdonQuestItems:GetDebugState()
        local questItemInfo = item:GetQuestItemInfo()
        local now = GetTime()

        addLine(0, "")
        addLine(0, "[Quest Value]")
        addKV(1, "Has Quest Value", questItemInfo ~= nil and questItemInfo.hasQuestValue or false)
        addKV(1, "Active Quest", questItemInfo ~= nil and questItemInfo.isActive or false)
        addKV(1, "Upcoming Quest", questItemInfo ~= nil and questItemInfo.isUpcoming or false)
        -- The client's own word for the copy in its bag slot, which no status is made from.
        local slotQuestInfo = item.GetSlotQuestInfo and item:GetSlotQuestInfo()
        if slotQuestInfo then
            local startsText = "starts no quest"
            if slotQuestInfo.questID then
                local title = C_QuestLog.GetTitleForQuestID(slotQuestInfo.questID)
                startsText = string.format("starts quest %s%s, which is %s", tostring(slotQuestInfo.questID),
                    title and (" (" .. tostring(title) .. ")") or "", slotQuestInfo.isActive and "in the log" or "not in the log")
            end
            addKV(1, "The Client, For Its Bag Slot", string.format("%s, %s",
                slotQuestInfo.isQuestItem and "a quest item" or "no quest item", startsText))
        else
            addKV(1, "The Client, For Its Bag Slot", "not asked (the item lies in no bag slot)")
        end
        addKV(1, "Show Quest Items", CaerdonWardrobeConfig.Icon.ShowQuestItems)
        addKV(1, "Show Upcoming Quest Items", CaerdonWardrobeConfig.Icon.ShowUpcomingQuestItems)
        addKV(1, "Upcoming Level Window", questState.upcomingLevelWindow)
        addKV(1, "Trivial Range", questState.trivialRange)
        addKV(1, "Profession Skill Lines", questState.professions or "not recognised (check skipped)")

        local logState = questState.questLog
        addKV(1, "Quest Log", string.format("%d quests, %d item objectives, %s%s%s",
            logState.questCount or 0,
            logState.objectiveCount or 0,
            logState.lastScan and string.format("scanned %.1fs ago", now - logState.lastScan) or "not scanned",
            logState.incomplete and ", objective names still loading" or "",
            logState.awaitingData and ", waiting for QUEST_LOG_UPDATE" or ""))
        if logState.error then
            addKV(1, "Quest Log Error", logState.error)
        end
        -- An objective's text names its item only while the client has the item's data.
        addKV(1, "Quest Log Names", string.format("%d of the last scan's objectives had no text and kept the name they had; %d scans kept one%s; %d rechecks by the clock, %d rescans for a missing name counted",
            logState.keptNames or 0, logState.scansThatKept or 0,
            logState.lastKept and string.format(", the last %.1fs ago", now - logState.lastKept) or "",
            logState.rechecks or 0, logState.rescanAttempts or 0))

        local providerState = questState.provider
        local providerText = "QuestieDB " .. tostring(providerState.state)
        if providerState.contractVersion then
            providerText = providerText .. string.format(" (contract %s, %s)",
                tostring(providerState.contractVersion), tostring(providerState.readMode))
        end
        if providerState.state == "ready" then
            providerText = providerText .. string.format(", %d items across %d quests indexed in %.0fms",
                providerState.itemCount or 0, providerState.questCount or 0, providerState.buildMs or 0)
        end
        addKV(1, "Quest Database", providerText)
        if providerState.error then
            addKV(1, "Quest Database Error", providerState.error)
        end
        addKV(1, "Questie Policy", questState.questie.loaded and
            ("loaded, ready=" .. tostring(questState.questie.isReady)) or "not loaded")
        addKV(1, "Quests Answered Since The Last Refresh", questState.answeredCount)

        if questItemInfo and #questItemInfo.quests > 0 then
            addLine(1, "Quests:")
            for _, quest in ipairs(questItemInfo.quests) do
                local levelText = ""
                if quest.questLevel or quest.requiredLevel then
                    levelText = string.format(" [level %s, requires %s]",
                        tostring(quest.questLevel or "?"), tostring(quest.requiredLevel or "?"))
                end
                addLine(2, string.format("- %d %s%s (%s): %s%s",
                    quest.questID,
                    tostring(quest.name or "unknown"),
                    levelText,
                    tostring(quest.role),
                    quest.eligible and "" or "skipped, ",
                    tostring(quest.reason)))
            end
        else
            addLine(1, "Quests: none")
        end
    end

    -- Food and drink: how the item was read and whether a better one is carried.
    if CaerdonFoodDrink and item.GetFoodDrinkInfo then
        local foodDrinkInfo = item:GetFoodDrinkInfo()
        local foodState = CaerdonFoodDrink.GetDebugState and CaerdonFoodDrink:GetDebugState(item:GetItemID())
        if not foodDrinkInfo and foodState and foodState.isFoodDrink then
            -- Food or drink by its class, and no restore line was found on its tooltip.
            addLine(0, "")
            addLine(0, "[Food and Drink]")
            addKV(1, "Kind", "not read (no tooltip line has a number and one of the words below)")
            addKV(1, "Health Words", foodState.healthWords)
            addKV(1, "Mana Words", foodState.manaWords)
        end
        if foodDrinkInfo then
            addLine(0, "")
            addLine(0, "[Food and Drink]")
            addKV(1, "Show Outdated Food", CaerdonWardrobeConfig.Icon.ShowOutdatedFood)
            if foodState then
                addKV(1, "Health Words", foodState.healthWords)
                addKV(1, "Mana Words", foodState.manaWords)
            end
            addKV(1, "Kind", foodDrinkInfo.kind)
            addKV(1, "Buff Food", foodDrinkInfo.isBuff)
            addKV(1, "Restore Amount", foodDrinkInfo.amount)
            addKV(1, "Restore Line", foodDrinkInfo.text)
            addKV(1, "Required Level", foodDrinkInfo.requiredLevel)
            addKV(1, "Item Level", foodDrinkInfo.itemLevel)
            addKV(1, "Outdated", foodDrinkInfo.isOutdated)
            addKV(1, "Reason", foodDrinkInfo.reason)
            if foodDrinkInfo.betterItem then
                addKV(1, "Better Item Carried", string.format("%s (item %d, requires %d, restores %d)",
                    tostring(foodDrinkInfo.betterItem.name), foodDrinkInfo.betterItem.itemID,
                    foodDrinkInfo.betterItem.requiredLevel, foodDrinkInfo.betterItem.amount))
            end
        end
    end

    -- Pet food: what the client says a hunter's pet eats, for every item (raw meat is a trade
    -- good). Nothing is judged from it yet.
    if CaerdonFoodDrink and CaerdonFoodDrink.GetPetFoodDebugState then
        local petFood = CaerdonFoodDrink:GetPetFoodDebugState(item:GetItemID(), item:GetItemLink())
        if petFood then
            addLine(0, "")
            addLine(0, "[Pet Food]")
            if petFood.hasPet then
                addKV(1, "Pet", string.format("%s, level %s", tostring(petFood.petName), tostring(petFood.petLevel)))
            else
                addKV(1, "Pet", "none out (the answers below are the client's without one)")
            end
            addKV(1, "Diet", #petFood.diet > 0 and table.concat(petFood.diet, ", ") or "none")
            if petFood.happiness ~= nil then
                addKV(1, "Happiness", string.format("%s (damage %s%%, loyalty rate %s)", tostring(petFood.happiness),
                    tostring(petFood.damagePercentage), tostring(petFood.loyaltyRate)))
            else
                addKV(1, "Happiness", "no answer")
            end
            addKV(1, "C_PetInfo.CanPetEatItem", petFood.canEat)
            addKV(1, "Item Level", petFood.itemLevel)
            if petFood.petLevel and petFood.itemLevel then
                addKV(1, "Item Levels Below The Pet", petFood.petLevel - petFood.itemLevel)
            end
            addKV(1, "Remembered Answer", petFood.remembered == nil and "none" or petFood.remembered)
            if petFood.judged then
                addKV(1, "Rule", string.format("the best %d pieces in one or two kinds, a piece counting for the square of its item level",
                    petFood.pieces))
                addKV(1, "Kept For The Pet", petFood.kept)
                if #petFood.carried > 0 then
                    addLine(1, "Carried That The Pet Eats:")
                    for _, line in ipairs(petFood.carried) do
                        addLine(2, "- " .. line)
                    end
                else
                    addLine(1, "Carried That The Pet Eats: nothing")
                end
            else
                addKV(1, "Rule", "no pet has answered this session; the level gap decides")
            end
        end
    end

    -- Profession tools: what counts as a tool for this toon and whether this item is one.
    if CaerdonProfessionTools and item.GetProfessionToolInfo then
        local toolState = CaerdonProfessionTools:GetDebugState()
        local toolInfo = item:GetProfessionToolInfo()
        local function listOrNone(list)
            return (list and #list > 0) and table.concat(list, "; ") or "none"
        end

        addLine(0, "")
        addLine(0, "[Profession Tools]")
        addKV(1, "Is Tool", toolInfo ~= nil)
        if toolInfo then
            addKV(1, "Tool", toolInfo.toolName)
            addKV(1, "For", listOrNone(toolInfo.professions))
            addKV(1, "Source", toolInfo.source)
            addKV(1, "Matched By", toolInfo.match)
        end
        addKV(1, "Known Tool Items Apply", toolState.carriedInBags)
        addKV(1, "Tool Names Pending", toolState.namesPending)
        addKV(1, "Professions", listOrNone(toolState.professions))
        addKV(1, "Tools", listOrNone(toolState.tools))
        addKV(1, "Recipe Tools Recorded", listOrNone(toolState.recordedProfessions))
        -- Whether this client has profession gear slots at all, for a better gate than the
        -- ranged slot some day. Printed, not used.
        if C_TradeSkillUI and C_TradeSkillUI.GetProfessionSlots and Enum.Profession and Enum.Profession.Mining then
            local ok, slots = pcall(C_TradeSkillUI.GetProfessionSlots, Enum.Profession.Mining)
            addKV(1, "GetProfessionSlots (Mining)", ok and type(slots) == "table" and
                (#slots .. " slots") or tostring(slots))
        end
    end

    -- Ingredients: the recorded recipes that take the item, this toon's and other toons', and
    -- what the rule makes of them. Printed for every item, since "no recipe takes it" is only
    -- worth as much as the list of professions that were recorded.
    if CaerdonIngredients and item.GetIngredientInfo then
        local ingredientInfo = item:GetIngredientInfo()
        local ingredientState = CaerdonIngredients:GetDebugState(item:GetItemID())

        addLine(0, "")
        addLine(0, "[Ingredients]")
        addKV(1, "Rule", "a use while a recipe that takes it gives skill (the toon's rank is below the rank the recipe is gray from), learned or not")
        addKV(1, "Show Ingredients For Other Toons", string.format("%s (%s)",
            tostring(CaerdonWardrobeConfig.Icon.ShowIngredientsForOtherToons),
            tostring(CaerdonWardrobeConfig.Icon.IngredientsForOtherToons)))
        addKV(1, "Show Outgrown Ingredients", CaerdonWardrobeConfig.Icon.ShowOutgrownIngredients)
        addKV(1, "Auction Icon On Trade Goods", CaerdonWardrobeConfig.Icon.AuctionTradeGoods)
        if item.GetIngredientStatus then
            -- As the status logic asks it. It only stands where nothing before it gave the
            -- item a status, and a quest's item gets none (see [Quest Value]).
            addKV(1, "Status From This Rule", (item:GetIngredientStatus()) or "none")
            addKV(1, "Kept From The Auction Icon", item:IsIngredientKeptFromAuction())
        end
        -- Who sells it, which keeps the mail icon off what any toon buys for itself.
        if CaerdonVendorGoods and item.GetVendorInfo then
            local vendorInfo = item:GetVendorInfo()
            if vendorInfo then
                addKV(1, "Vendors That Sell It", string.format("%d (%s)", vendorInfo.vendorCount, vendorInfo.source))
                addKV(1, "Common Vendor Good", string.format("%s (from %d vendors on; never one to send)",
                    tostring(vendorInfo.isCommon), vendorInfo.commonFrom))
            else
                addKV(1, "Vendors That Sell It", string.format("not known (%s)",
                    tostring(CaerdonVendorGoods:GetDebugState(item:GetItemID()).unknownReason)))
            end
        end
        if not ingredientInfo or #ingredientInfo.recipes == 0 then
            addKV(1, "Has A Use", "no recorded recipe takes it")
        elseif ingredientInfo.hasUse then
            addKV(1, "Has A Use", true)
        elseif ingredientInfo.undecided > 0 then
            addKV(1, "Has A Use", string.format("not known (the client gave no difficulty for %d of its recipes)",
                ingredientInfo.undecided))
        else
            addKV(1, "Has A Use", "false (every recipe that takes it is gray)")
        end
        if ingredientInfo and #ingredientInfo.recipes > 0 then
            addLine(1, "Recipes That Take It:")
            for _, recipe in ipairs(ingredientInfo.recipes) do
                addLine(2, string.format("- %s: %s (recipe %d) x%d: %s", tostring(recipe.professionName),
                    tostring(recipe.name), recipe.recipeID, recipe.quantity or 0, tostring(recipe.reading)))
                addLine(3, string.format("recorded: difficulty %s, canSkillUp %s, numSkillUps %s, maxTrivialLevel %s, sourceType %s, said at rank %s; read %s",
                    tostring(recipe.difficulty), tostring(recipe.canSkillUp), tostring(recipe.skillUps),
                    tostring(recipe.maxTrivialLevel), tostring(recipe.sourceType), tostring(recipe.recordedRank),
                    recipe.rankNow and ("by the rank now, " .. tostring(recipe.rankNow)) or "by the recorded colour"))
                addLine(3, "client now: " .. tostring(ingredientState.clientNow[recipe.recipeID]))
            end
        end
        if #ingredientState.recorded > 0 then
            addLine(1, "Recorded Professions:")
            for _, line in ipairs(ingredientState.recorded) do
                addLine(2, "- " .. line)
            end
        else
            addLine(1, "Recorded Professions: none")
        end
        if #ingredientState.notRecorded > 0 then
            addKV(1, "Not Recorded (open the profession once)", table.concat(ingredientState.notRecorded, ", "))
        end
        if #ingredientState.dropped > 0 then
            addKV(1, "Recorded But No Longer A Profession", table.concat(ingredientState.dropped, ", "))
        end
        if ingredientInfo and #ingredientInfo.others > 0 then
            local function Names(toons)
                local names = {}
                for _, toon in ipairs(toons) do
                    names[#names + 1] = string.format("%s (%s %s)", toon.name, toon.professionName, tostring(toon.rank))
                end
                return #names > 0 and table.concat(names, ", ") or "none"
            end
            addKV(1, "Gives Skill To", Names(ingredientInfo.skillFor))
            addKV(1, "Used By", Names(ingredientInfo.usedBy))
            addLine(1, "Other Toons' Recipes That Take It:")
            for _, other in ipairs(ingredientInfo.others) do
                addLine(2, string.format("- %s, %s (rank %s): %s (recipe %d) x%d: %s", tostring(other.toon),
                    tostring(other.professionName), tostring(other.toonRank), tostring(other.name), other.recipeID,
                    other.quantity or 0, tostring(other.reading)))
            end
        end
    end

    -- Bags: what is in each bag slot right now, and, for a bag, how it compares with them.
    -- Printed for every item: which bags a slot accepts and what a bag holds is not documented,
    -- so the slots and the item's bag family are how that gets found out.
    if CaerdonBagSlots and item.GetBagSlotInfo then
        local bagInfo = item:GetBagSlotInfo()
        local bagState = CaerdonBagSlots:GetDebugState()
        addLine(0, "")
        addLine(0, "[Bag Slots]")
        addKV(1, "Show Bag Upgrades", CaerdonWardrobeConfig.Icon.ShowBagUpgrades ~= false)
        addKV(1, "Show Spare Bags", CaerdonWardrobeConfig.Icon.ShowSpareBags ~= false)
        -- For a bag: the kind of bag it is. For anything else: the kinds of bag that take it.
        addKV(1, "Item Bag Family", CaerdonBagSlots:GetItemFamily(item:GetItemLink() or item:GetItemID()))
        if bagInfo then
            addKV(1, "Judged As", bagInfo.kind == "reagent" and "reagent bag" or
                bagInfo.kind == "profession" and string.format("profession bag (subclass %s \"%s\")",
                    tostring(bagInfo.subClassID), tostring(bagInfo.subTypeName)) or
                bagInfo.kind == "quiver" and string.format("quiver (subclass %s \"%s\")",
                    tostring(bagInfo.subClassID), tostring(bagInfo.subTypeName)) or "bag")
            addKV(1, "Size", bagInfo.size and
                string.format("%d (tooltip line \"%s\", matched by %s)", bagInfo.size,
                    tostring(bagInfo.sizeText), tostring(bagInfo.sizeMatchedBy)) or "not read")
            addKV(1, "Belongs In A Slot Now", bagInfo.isUpgrade)
            addKV(1, "Spare", bagInfo.isSpare)
            addKV(1, "Reason", bagInfo.reason)
            if bagInfo.replacesBag then
                addKV(1, "Would Replace Container", bagInfo.replacesBag)
            end
            if bagInfo.hasUse ~= nil then
                addKV(1, "Toon Has A Use For It", string.format("%s (takes %s; %s)", tostring(bagInfo.hasUse),
                    tostring(bagInfo.usedBy), tostring(bagInfo.usedByHave)))
            end
            addLine(1, string.format("Slots It Fits: %d, %d empty", bagInfo.slotCount, bagInfo.emptySlots))
            for _, comparison in ipairs(bagInfo.comparisons) do
                addLine(2, string.format("- container %d (%s slot): %s%s", comparison.bag,
                    comparison.group == "reagent" and "reagent bag" or "bag",
                    tostring(comparison.result),
                    comparison.label and string.format(" against the %s there, %d slots", comparison.label,
                        comparison.size or 0) or ""))
            end
        else
            addKV(1, "Judged As", "not judged (not a bag or a quiver)")
        end
        addKV(1, "Reagent Bag Slot Takes Profession Bags", string.format("%s (%s)",
            tostring(bagState.reagentTakesProfession), tostring(bagState.reagentTakesProfessionWhy)))
        addKV(1, "Ammo Weapons Equipped", bagState.ammoWeapons)
        addKV(1, "Professions", bagState.professions)
        for _, kind in ipairs({ "bag", "reagent" }) do
            local group = bagState.groups[kind]
            addLine(1, (kind == "reagent" and "Reagent Bag Slots" or "Bag Slots") ..
                (#group.slots == 0 and ": none on this client" or (group.pending and " (contents pending):" or ":")))
            for _, slotText in ipairs(group.slots) do
                addLine(2, "- " .. slotText)
            end
        end
        addKV(1, "Slot Count Format", string.format("\"%s\"%s, pattern \"%s\"", tostring(bagState.format),
            bagState.formatIsDefault and " (built-in; CONTAINER_SLOTS is not set)" or " (CONTAINER_SLOTS)",
            tostring(bagState.pattern)))
    end

    -- Why a sellable item does (or does not) carry the auction icon: every number in the verdict.
    if CaerdonAuctionValue and item.GetAuctionValueInfo then
        local auctionState = CaerdonAuctionValue:GetDebugState()
        local auctionInfo = item:GetAuctionValueInfo()
        local function money(copper)
            if type(copper) ~= "number" then
                return "nil"
            end
            local sign = copper < 0 and "-" or ""
            copper = math.abs(copper)
            return string.format("%s%dg %ds %dc", sign, math.floor(copper / 10000),
                math.floor(copper / 100) % 100, copper % 100)
        end

        addLine(0, "")
        addLine(0, "[Auction Value]")
        addKV(1, "Show Auction Value", CaerdonWardrobeConfig.Icon.ShowAuctionValue)
        addKV(1, "Minimum Profit Setting", CaerdonWardrobeConfig.Icon.AuctionMinProfit)
        addKV(1, "Price Source", auctionState.available and
            ("Auctionator, scan updates " .. (auctionState.registered and "registered" or "not registered") ..
                string.format(", %d this session", auctionState.updateCount or 0)) or "none (Auctionator not loaded)")
        if auctionState.error then
            addKV(1, "Price Source Error", auctionState.error)
        end
        addKV(1, "Deposit Model", auctionState.depositRate and
            string.format("measured: %.1f%% of vendor price, minimum %s",
                auctionState.depositRate * 100, money(auctionState.minDeposit)) or
            string.format("default: %.0f%% of vendor price, minimum %s (place an item in the auction sell slot to measure it)",
                auctionState.defaultDepositRate * 100, money(auctionState.minDeposit or auctionState.defaultMinDeposit)))
        if auctionState.lastSample then
            addKV(1, "Last Deposit Sample", string.format("item %s, vendor %s, deposit %s",
                tostring(auctionState.lastSample.itemID), money(auctionState.lastSample.vendorPrice),
                money(auctionState.lastSample.deposit)))
        end
        if auctionInfo then
            addKV(1, "Should Auction", auctionInfo.shouldAuction)
            addKV(1, "Reason", auctionInfo.reason)
            addKV(1, "Rule", string.format("%s (margin %d%% of vendor value)", tostring(auctionInfo.rule),
                (auctionInfo.margin or 0) * 100))
            addKV(1, "Quantity Owned", auctionInfo.quantity)
            addKV(1, "Vendor Price", money(auctionInfo.vendorPrice))
            addKV(1, "Vendor Value", money(auctionInfo.vendorValue))
            addKV(1, "Last Seen Price", money(auctionInfo.lastPrice))
            addKV(1, "Price Age (days)", auctionInfo.ageDays)
            addKV(1, "Median Daily Low", auctionInfo.medianLow and money(auctionInfo.medianLow) or "not enough history")
            addKV(1, "Days Seen", auctionInfo.daysSeen)
            addKV(1, "Most Listed In A Day", auctionInfo.maxAvailable)
            addKV(1, "Price Key", auctionInfo.dbKey)
            addKV(1, "Random Suffix In Link", auctionInfo.randomSuffix)
            addKV(1, "Price Used", money(auctionInfo.price))
            addKV(1, "After Cut", money(auctionInfo.net))
            addKV(1, "Deposit", string.format("%s x%d (%s)", money(auctionInfo.deposit),
                auctionInfo.depositRiskMultiplier or 1, tostring(auctionInfo.depositSource)))
            addKV(1, "Profit", money(auctionInfo.profit))
            addKV(1, "Required", string.format("%s (floor %s, %s)", money(auctionInfo.required),
                money(auctionInfo.floor), tostring(auctionInfo.floorSource)))
        end
    end

    local sharedItems = self.currentSharedAppearanceItems
    addLine(0, "")
    addLine(0, "[Shared Appearance Items]")
    if sharedItems and #sharedItems > 0 then
        addKV(1, "count", #sharedItems)
        for _, info in ipairs(sharedItems) do
            local itemLink = FormatItemLinkForDebug(info.itemID, info.itemLink)
            local prefix = info.isCurrentItem and "[Current] " or ""
            local descriptorText = BuildVariantDescriptorText(info)
            addLine(1, prefix .. (itemLink or ("Item " .. tostring(info.itemID))) .. descriptorText)
            if info.sources and #info.sources > 0 then
                addLine(2, "Source IDs: " .. table.concat(info.sources, ", "))
            end
            if info.variantInstanceText or info.variantEncounterText then
                local sourceParts = {}
                if info.variantInstanceText then
                    table.insert(sourceParts, info.variantInstanceText)
                end
                if info.variantEncounterText then
                    table.insert(sourceParts, info.variantEncounterText)
                end
                addLine(2, "Source: " .. table.concat(sourceParts, " - "))
            end
            if info.itemLevelSource then
                addLine(2, "Item Level Source: " .. tostring(info.itemLevelSource))
            end
            AddEJDiagnostics(2, info.sources)

            local statusParts = BuildSharedStatusParts(info, true)
            local statusLine = statusParts
            if info.isCollected ~= nil then
                statusLine = statusLine or {}
                table.insert(statusLine, 1, info.isCollected and "collected" or "uncollected")
            end
            if #statusParts > 0 then
                addLine(2, "Status: " .. table.concat(statusParts, ", "))
            end
        end
    else
        addLine(1, "None")
    end

    local variationItems = self.currentAppearanceVariations
    addLine(0, "")
    addLine(0, "[Appearance Variation Items]")
    if variationItems and #variationItems > 0 then
        addKV(1, "count", #variationItems)
        for _, info in ipairs(variationItems) do
            local itemText = FormatItemLinkForDebug(info.itemID, info.itemLink)
            local descriptorText = BuildVariantDescriptorText(info)
            addLine(1, string.format("%s%s (mod %s, visual %s, appearance %s)", itemText, descriptorText,
                tostring(info.itemModID or 0),
                tostring(info.visualID or "nil"), tostring(info.appearanceID or "nil")))
            if info.sources and #info.sources > 0 then
                addLine(2, "Source IDs: " .. table.concat(info.sources, ", "))
            end
            if info.variantInstanceText or info.variantEncounterText then
                local sourceParts = {}
                if info.variantInstanceText then
                    table.insert(sourceParts, info.variantInstanceText)
                end
                if info.variantEncounterText then
                    table.insert(sourceParts, info.variantEncounterText)
                end
                addLine(2, "Source: " .. table.concat(sourceParts, " - "))
            end
            if info.itemLevelSource then
                addLine(2, "Item Level Source: " .. tostring(info.itemLevelSource))
            end
            AddEJDiagnostics(2, info.sources)
            local statusParts = BuildSharedStatusParts(info, true)
            if #statusParts > 0 then
                addLine(2, "Status: " .. table.concat(statusParts, ", "))
            end
        end
    else
        addLine(1, "None")
    end

    local ensembleData = self.currentEnsembleData
    if ensembleData and ensembleData.setID then
        addLine(0, "")
        addLine(0, "[Ensemble]")
        addKV(1, "Set ID", ensembleData.setID)

        if ensembleData.setInfo then
            addKV(1, "Set Name", ensembleData.setInfo.name)
            addKV(1, "Set Collected", ensembleData.setInfo.collected)
            addKV(1, "Set Valid For Character", ensembleData.setInfo.validForCharacter)
            addKV(1, "Set Class Mask", ensembleData.setInfo.classMask)
            addKV(1, "Set Label", ensembleData.setInfo.label)
            addKV(1, "Set Description", ensembleData.setInfo.description)
        end

        if ensembleData.classCandidates and #ensembleData.classCandidates > 0 then
            addLine(1, "Class Candidates:")
            for _, classCandidate in ipairs(ensembleData.classCandidates) do
                local candidateName = GetClassInfo(classCandidate)
                addLine(2, "- " .. tostring(classCandidate) .. " (" .. (candidateName or "Unknown") .. ")")
            end
        end

        addKV(1, "Total Sources", ensembleData.totalSources)
        addKV(1, "Total Unique Items", ensembleData.totalItems)

        if ensembleData.sourceSummary then
            addLine(1, "Source Summary:")
            addKV(2, "Uncollected Sources", ensembleData.sourceSummary.uncollectedSources)
            addKV(2, "- New Appearances", ensembleData.sourceSummary.uncollectedAppearanceSources)
            addKV(2, "- Duplicate Appearances", ensembleData.sourceSummary.uncollectedDuplicateSources)
            addKV(2, "- Known via Other Source", ensembleData.sourceSummary.uncollectedKnownViaAltSources)
            addKV(2, "- Legendary Duplicate Skip", ensembleData.sourceSummary.uncollectedLegendaryDuplicateSources)
        end

        if ensembleData.sourceIDs and #ensembleData.sourceIDs > 0 then
            addLine(1, "Source IDs:")
            for _, sourceID in ipairs(ensembleData.sourceIDs) do
                addLine(2, "- " .. tostring(sourceID))
            end
        end

        if ensembleData.items and #ensembleData.items > 0 then
            addLine(1, "Items:")
            for _, info in ipairs(ensembleData.items) do
                addLine(2, "- Item " .. tostring(info.itemID))
                if info.itemLink then
                    addLine(3, "Link: " .. info.itemLink)
                    local itemString = info.itemLink:match("|H(.-)|h")
                    if itemString then
                        addLine(4, "Item String: " .. itemString)
                    end
                else
                    addLine(3, "Name: " .. (info.itemName or "Unknown"))
                end
                addKV(3, "Item Quality",
                    info.itemQuality and _G[("ITEM_QUALITY%d_DESC"):format(info.itemQuality)] or info.itemQuality)
                addKV(3, "Item Min Level", info.itemMinLevel)
                addKV(3, "Item Type", info.itemType)
                addKV(3, "Item SubType", info.itemSubType)
                addKV(3, "Item Equip Loc", info.itemEquipLoc)
                addKV(3, "Class ID", info.classID)
                addKV(3, "Subclass ID", info.subclassID)

                if info.sources and #info.sources > 0 then
                    addLine(3, "Sources:")
                    for _, source in ipairs(info.sources) do
                        addLine(4,
                            "* Source " ..
                            tostring(source.sourceID) ..
                            " (Visual " .. tostring(source.visualID) .. ", Mod " .. tostring(source.itemModID) .. ")")
                        addKV(5, "isCollected", source.isCollected)
                        addKV(5, "playerCanCollect", source.playerCanCollect)
                        addKV(5, "isValidSourceForPlayer", source.isValidSourceForPlayer)
                        addKV(5, "hasItemDataAPI", source.hasItemDataAPI)
                        addKV(5, "canCollectAPI", source.canCollectAPI)
                        addKV(5, "accountHasItemDataAPI", source.accountHasItemDataAPI)
                        addKV(5, "accountCanCollectAPI", source.accountCanCollectAPI)
                        addKV(5, "canDisplayOnPlayer", source.canDisplayOnPlayer)
                        addKV(5, "meetsTransmogPlayerCondition", source.meetsTransmogPlayerCondition)
                        addKV(5, "isHideVisual", source.isHideVisual)
                        addKV(5, "sourceType", source.sourceType)
                        addKV(5, "categoryID", source.categoryID)
                        addKV(5, "invType", source.invType)
                        addKV(5, "quality", source.quality)
                        if source.name then
                            addKV(5, "name", source.name)
                        end
                        if source.useErrorType then
                            addKV(5, "useErrorType",
                                tostring(source.useErrorType) ..
                                " (" .. self:GetTransmogUseErrorTypeName(source.useErrorType) .. ")")
                        end
                        if source.useError then
                            addKV(5, "useError", source.useError)
                        end
                        if source.appearanceInfo then
                            addTable(5, "appearanceInfo", source.appearanceInfo)
                        end
                    end
                else
                    addLine(3, "Sources: none")
                end
            end
        end
    end

    addLine(0, "")
    addLine(0, "=== End CaerdonWardrobe Debug Export ===")

    return table.concat(lines, "\n")
end

function DebugFrameMixin:EnsureCopyOutputFrame()
    if self.copyOutputFrame then
        return self.copyOutputFrame
    end

    local frame = CreateFrame("Frame", "CaerdonDebugCopyFrame", self.frame, "BackdropTemplate")
    frame:SetSize(560, 380)
    frame:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.07, 0.07, 0.1, 0.95)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -12)
    frame.title:SetText("Caerdon Wardrobe Debug Export")

    frame.instruction = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.instruction:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -36)
    frame.instruction:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    frame.instruction:SetJustifyH("LEFT")
    frame.instruction:SetText(
        "Text is highlighted automatically. Press Ctrl-C (Cmd-C on Mac) to copy, then Ctrl-V to paste it into chat or a note.")

    frame.scrollFrame = CreateFrame("ScrollFrame", "CaerdonDebugCopyScrollFrame", frame, "UIPanelScrollFrameTemplate")
    frame.scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -64)
    frame.scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 48)

    frame.editBox = CreateFrame("EditBox", "CaerdonDebugCopyEditBox", frame.scrollFrame)
    frame.editBox:SetMultiLine(true)
    frame.editBox:SetFontObject("ChatFontNormal")
    frame.editBox:SetAutoFocus(false)
    frame.editBox:SetWidth(frame.scrollFrame:GetWidth())
    if frame.editBox.SetMaxLetters then
        frame.editBox:SetMaxLetters(0)
    end
    -- No extra line spacing here: with it, the selection highlight drifted away from the text it
    -- covers, so only "select all" was usable.
    frame.editBox:SetScript("OnEscapePressed", function(editBox)
        editBox:ClearFocus()
        frame:Hide()
    end)
    frame.editBox:SetScript("OnEditFocusLost", function(editBox)
        editBox:HighlightText(0, 0)
    end)

    frame.scrollFrame:SetScrollChild(frame.editBox)
    frame.scrollFrame:HookScript("OnSizeChanged", function(_, width)
        frame.editBox:SetWidth(width or frame.editBox:GetWidth())
    end)

    frame:SetScript("OnShow", function()
        frame.editBox:SetWidth(frame.scrollFrame:GetWidth())
    end)

    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.closeButton:SetSize(80, 22)
    frame.closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    frame.closeButton:SetText(CLOSE)
    frame.closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    self.copyOutputFrame = frame
    return frame
end

function DebugFrameMixin:ShowCopyOutput(payload)
    local frame = self:EnsureCopyOutputFrame()
    -- An inline texture or atlas in the text (the crafting quality mark in an enchant's tooltip
    -- line) is drawn in the box and makes its line taller than the others; from there on the
    -- selection highlight does not lie on the text. It is shown as the text it is instead.
    payload = (payload or ""):gsub("||", "\1"):gsub("|([TtAa])", "||%1"):gsub("\1", "||")
    frame.editBox:SetText(payload)
    frame:Show()
    frame.editBox:HighlightText()
    frame.editBox:SetFocus()
end

function DebugFrameMixin:AddPetInfo(item)
    local petInfo = item:GetPetInfo()
    if not petInfo then return end

    self:AddDebugEntry("Pet ID", tostring(petInfo.speciesID))
    self:AddDebugEntry("Pet Name", petInfo.name)
    self:AddDebugEntry("Pet Level", tostring(petInfo.level))
    self:AddDebugEntry("Pet Quality", _G["BATTLE_PET_BREED_QUALITY" .. petInfo.breedQuality])
    self:AddDebugEntry("Is Wild Pet", tostring(petInfo.isWild))
    self:AddDebugEntry("Can Battle", tostring(petInfo.canBattle))

    -- Add collect info
    local collectInfo = item:GetPetCollectInfo()
    if collectInfo then
        self:AddDebugEntry("Is Collected", tostring(collectInfo.isCollected))
        if collectInfo.maxAllowedCount then
            self:AddDebugEntry("Max Allowed", tostring(collectInfo.maxAllowedCount))
            self:AddDebugEntry("Num Collected", tostring(collectInfo.numCollected))
        end
    end
end

function DebugFrameMixin:CollectTransmogDebugData(item, overrideTransmogInfo)
    local data = {
        api = {},
        processed = {}
    }

    if not item then
        return data
    end

    local itemLink = item:GetItemLink()
    local itemID = item:GetItemID()
    local appearanceID, sourceID, requestSource

    if itemLink then
        appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemLink)
        if appearanceID then
            requestSource = "itemLink"
        end
    end

    if not appearanceID and itemID then
        local fallbackAppearanceID, fallbackSourceID = C_TransmogCollection.GetItemInfo(itemID)
        if fallbackAppearanceID then
            appearanceID = fallbackAppearanceID
            sourceID = fallbackSourceID
            requestSource = "itemID"
        end
    end

    data.api.itemInfo = {
        appearanceID = appearanceID,
        sourceID = sourceID,
        requestSource = requestSource
    }

    local itemSpecIDs
    if itemLink then
        itemSpecIDs = CopySpecIDs(C_Item.GetItemSpecInfo(itemLink))
    end
    if not itemSpecIDs and itemID then
        itemSpecIDs = CopySpecIDs(C_Item.GetItemSpecInfo(itemID))
    end
    data.api.itemSpecs = {
        ids = itemSpecIDs,
        descriptions = BuildSpecDescriptions(itemSpecIDs)
    }

    local lootSpecID = CaerdonAPI:GetLootSpecializationID()
    local activeSpecID
    local specIndex = CaerdonAPI:GetPlayerSpecializationIndex()
    if specIndex then
        activeSpecID = select(1, CaerdonAPI:GetSpecializationInfo(specIndex))
    end

    data.api.playerSpecs = {
        lootSpecID = lootSpecID,
        lootSpecLabel = FormatSpecIDText(lootSpecID),
        activeSpecID = activeSpecID,
        activeSpecLabel = FormatSpecIDText(activeSpecID)
    }

    local className, classFile, classID = UnitClass("player")
    data.api.playerClass = {
        className = className,
        classFile = classFile,
        classID = classID
    }

    local itemInfoToken = itemLink or itemID

    if itemInfoToken and classID and C_Item.DoesItemContainSpec then
        local specResults = {}
        if itemSpecIDs then
            for _, specID in ipairs(itemSpecIDs) do
                local result = C_Item.DoesItemContainSpec(itemInfoToken, classID, specID)
                table.insert(specResults, {
                    specID = specID,
                    result = result
                })
            end
        end

        local playerSpecResult
        if activeSpecID then
            playerSpecResult = C_Item.DoesItemContainSpec(itemInfoToken, classID, activeSpecID)
        end

        data.api.doesItemContainSpec = {
            classID = classID,
            playerSpecID = activeSpecID,
            playerResult = playerSpecResult,
            specResults = specResults
        }
    end

    if itemInfoToken and C_Item.GetDetailedItemLevelInfo then
        local actualItemLevel, previewItemLevel, sparseItemLevel = C_Item.GetDetailedItemLevelInfo(itemInfoToken)
        if actualItemLevel then
            data.api.detailedItemLevelInfo = {
                actualItemLevel = actualItemLevel,
                previewItemLevel = previewItemLevel,
                sparseItemLevel = sparseItemLevel
            }
        end
    end

    local itemLocation = item:GetItemLocation()

    if itemID and activeSpecID and C_Item.GetSetBonusesForSpecializationByItemID then
        local setBonuses = C_Item.GetSetBonusesForSpecializationByItemID(activeSpecID, itemID)
        if setBonuses then
            data.api.setBonusesForSpec = {
                specID = activeSpecID,
                setBonusSpellIDs = CopyTable(setBonuses)
            }
        end
    end

    if itemLocation and itemLocation:HasAnyLocation() and C_Item.CanItemTransmogAppearance then
        local canTransmog, failureReason, failureArg = C_Item.CanItemTransmogAppearance(itemLocation)
        data.api.canItemTransmog = {
            canTransmog = canTransmog,
            failureReason = failureReason,
            failureArg = failureArg
        }

        if C_ArtifactUI and C_ArtifactUI.IsArtifactItem then
            local isArtifactItem = C_ArtifactUI.IsArtifactItem(itemLocation)
            data.api.artifactInfo = {
                isArtifactItem = isArtifactItem
            }
            if C_ArtifactUI.IsArtifactDisabled then
                data.api.artifactInfo.isArtifactDisabled = C_ArtifactUI.IsArtifactDisabled()
            end
            if C_ArtifactUI.IsEquippedArtifactDisabled then
                data.api.artifactInfo.isEquippedArtifactDisabled = C_ArtifactUI.IsEquippedArtifactDisabled()
            end
        end
    end

    if sourceID then
        data.api.playerHasTransmog = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID)

        local playerReady, playerCanCollect = C_TransmogCollection.PlayerCanCollectSource(sourceID)
        data.api.playerCanCollectSource = {
            isInfoReady = playerReady,
            canCollect = playerCanCollect
        }

        local accountReady, accountCanCollect = C_TransmogCollection.AccountCanCollectSource(sourceID)
        data.api.accountCanCollectSource = {
            isInfoReady = accountReady,
            canCollect = accountCanCollect
        }

        data.api.sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
        data.api.appearanceInfo = C_TransmogCollection.GetAppearanceInfoBySource(sourceID)
        local appearanceSourceInfo = CaerdonAPI and CaerdonAPI.GetAppearanceSourceInfo and
            CaerdonAPI:GetAppearanceSourceInfo(sourceID)
        if appearanceSourceInfo then
            data.api.appearanceSourceInfo = CopySourceInfoFields(appearanceSourceInfo)
        end

        if data.api.sourceInfo and data.api.sourceInfo.itemID then
            local sourceSpecIDs = CopySpecIDs(C_Item.GetItemSpecInfo(data.api.sourceInfo.itemID))
            data.api.sourceSpecs = {
                ids = sourceSpecIDs,
                descriptions = BuildSpecDescriptions(sourceSpecIDs)
            }
        end
    end

    local resolvedAppearanceID = (data.api.itemInfo and data.api.itemInfo.appearanceID)
        or (overrideTransmogInfo and overrideTransmogInfo.appearanceID)
    if resolvedAppearanceID and classID and C_TransmogCollection.GetValidAppearanceSourcesForClass then
        local validSources = C_TransmogCollection.GetValidAppearanceSourcesForClass(resolvedAppearanceID, classID)
        if validSources then
            local simplifiedSources = {}
            for _, sourceInfo in ipairs(validSources) do
                table.insert(simplifiedSources, {
                    sourceID = sourceInfo.sourceID,
                    itemID = sourceInfo.itemID,
                    playerCanCollect = sourceInfo.playerCanCollect,
                    isValidSourceForPlayer = sourceInfo.isValidSourceForPlayer,
                    useErrorType = sourceInfo.useErrorType,
                    useError = sourceInfo.useError,
                    name = sourceInfo.name,
                    invType = sourceInfo.invType
                })
            end
            data.api.validSourcesForClass = simplifiedSources
        end
    end

    local transmogInfo = overrideTransmogInfo
    if not transmogInfo then
        local itemData = item:GetItemData()
        if itemData and itemData.GetTransmogInfo then
            transmogInfo = itemData:GetTransmogInfo()
        end
    end

    data.processed.transmogInfo = transmogInfo
    data.processed.resolvedAppearanceID = resolvedAppearanceID
    if transmogInfo then
        data.processed.debugExtras = transmogInfo.forDebugUseOnly
    end

    return data
end

function DebugFrameMixin:AddTransmogInfo(item)
    if not item then
        self:AddDebugEntry("Transmog Info", "Item is nil")
        return
    end

    local transmogData = self:CollectTransmogDebugData(item)
    local api = transmogData.api or {}
    local processed = transmogData.processed or {}
    local transmogInfo = processed.transmogInfo
    local debugExtras = processed.debugExtras

    if api.itemInfo then
        local appearanceValue = tostring(api.itemInfo.appearanceID)
        if api.itemInfo.requestSource then
            appearanceValue = appearanceValue .. " (via " .. api.itemInfo.requestSource .. ")"
        end
        self:AddDebugEntry("API Appearance ID", appearanceValue)
        self:AddDebugEntry("API Source ID", tostring(api.itemInfo.sourceID))
    else
        self:AddDebugEntry("API Appearance ID", "Not available for this item")
    end

    if api.playerHasTransmog ~= nil then
        self:AddDebugEntry("API PlayerHasTransmogItemModifiedAppearance", tostring(api.playerHasTransmog))
    end

    if api.playerSpecs then
        if api.playerSpecs.lootSpecID ~= nil then
            local lootSpecText = tostring(api.playerSpecs.lootSpecID)
            if api.playerSpecs.lootSpecLabel and api.playerSpecs.lootSpecLabel ~= lootSpecText then
                lootSpecText = lootSpecText .. " [" .. api.playerSpecs.lootSpecLabel .. "]"
            end
            self:AddDebugEntry("API Loot Spec", lootSpecText)
        end

        if api.playerSpecs.activeSpecID then
            local activeSpecText = tostring(api.playerSpecs.activeSpecID)
            if api.playerSpecs.activeSpecLabel and api.playerSpecs.activeSpecLabel ~= activeSpecText then
                activeSpecText = activeSpecText .. " [" .. api.playerSpecs.activeSpecLabel .. "]"
            end
            self:AddDebugEntry("API Active Spec", activeSpecText)
        end
    end

    if api.playerClass and api.playerClass.classID then
        local classText = tostring(api.playerClass.classID)
        if api.playerClass.classFile or api.playerClass.className then
            classText = classText .. " [" ..
                (api.playerClass.className or api.playerClass.classFile or "Unknown Class") .. "]"
        end
        self:AddDebugEntry("API Player Class ID", classText)
    end

    if api.itemSpecs and api.itemSpecs.descriptions then
        self:AddDebugEntry("API Item Spec IDs", table.concat(api.itemSpecs.descriptions, ", "))
    end

    if api.sourceSpecs and api.sourceSpecs.descriptions then
        self:AddDebugEntry("API Source Spec IDs", table.concat(api.sourceSpecs.descriptions, ", "))
    end

    if api.doesItemContainSpec then
        if api.doesItemContainSpec.playerResult ~= nil then
            local specText = FormatSpecIDText(api.doesItemContainSpec.playerSpecID)
            self:AddDebugEntry("API DoesItemContainSpec (Player Spec)",
                tostring(api.doesItemContainSpec.playerResult) ..
                (specText and (" [" .. specText .. "]") or ""))
        end

        if api.doesItemContainSpec.specResults and #api.doesItemContainSpec.specResults > 0 then
            for _, specData in ipairs(api.doesItemContainSpec.specResults) do
                local specText = FormatSpecIDText(specData.specID)
                self:AddDebugEntry("API DoesItemContainSpec (Spec " .. tostring(specData.specID) .. ")",
                    tostring(specData.result) .. (specText and (" [" .. specText .. "]") or ""))
            end
        end
    end

    if api.detailedItemLevelInfo then
        self:AddDebugEntry("API GetDetailedItemLevelInfo.actual", tostring(api.detailedItemLevelInfo.actualItemLevel))
        self:AddDebugEntry("API GetDetailedItemLevelInfo.preview", tostring(api.detailedItemLevelInfo.previewItemLevel))
        self:AddDebugEntry("API GetDetailedItemLevelInfo.sparse", tostring(api.detailedItemLevelInfo.sparseItemLevel))
    end

    if api.setBonusesForSpec then
        local specText = FormatSpecIDText(api.setBonusesForSpec.specID)
        local entryLabel = "API GetSetBonusesForSpecializationByItemID (" ..
            tostring(api.setBonusesForSpec.specID) .. ")"
        if specText and specText ~= tostring(api.setBonusesForSpec.specID) then
            entryLabel = entryLabel .. " [" .. specText .. "]"
        end
        local bonuses = api.setBonusesForSpec.setBonusSpellIDs or {}
        self:AddDebugEntry(entryLabel, (#bonuses > 0) and table.concat(bonuses, ", ") or "none")
    end

    if api.playerCanCollectSource then
        local value = tostring(api.playerCanCollectSource.canCollect) ..
            " (Ready: " .. tostring(api.playerCanCollectSource.isInfoReady) .. ")"
        self:AddDebugEntry("API PlayerCanCollectSource", value)
    end

    if api.accountCanCollectSource then
        local value = tostring(api.accountCanCollectSource.canCollect) ..
            " (Ready: " .. tostring(api.accountCanCollectSource.isInfoReady) .. ")"
        self:AddDebugEntry("API AccountCanCollectSource", value)
    end

    if api.canItemTransmog then
        local value = tostring(api.canItemTransmog.canTransmog)
        if api.canItemTransmog.failureReason then
            value = value .. " (Reason: " .. tostring(api.canItemTransmog.failureReason) .. ")"
        end
        if api.canItemTransmog.failureArg then
            value = value .. " (Arg: " .. tostring(api.canItemTransmog.failureArg) .. ")"
        end
        self:AddDebugEntry("API CanItemTransmogAppearance", value)
    end

    if api.artifactInfo then
        self:AddDebugEntry("API Artifact IsArtifactItem", tostring(api.artifactInfo.isArtifactItem))
        if api.artifactInfo.isArtifactDisabled ~= nil then
            self:AddDebugEntry("API Artifact IsArtifactDisabled", tostring(api.artifactInfo.isArtifactDisabled))
        end
        if api.artifactInfo.isEquippedArtifactDisabled ~= nil then
            self:AddDebugEntry("API Artifact IsEquippedArtifactDisabled",
                tostring(api.artifactInfo.isEquippedArtifactDisabled))
        end
    end

    if api.sourceInfo then
        self:AddDebugEntry("API Source Item ID", tostring(api.sourceInfo.itemID))
        self:AddDebugEntry("API Source InvType", tostring(api.sourceInfo.invType))
        self:AddDebugEntry("API Source IsCollected", tostring(api.sourceInfo.isCollected))
        self:AddDebugEntry("API Source ValidForPlayer", tostring(api.sourceInfo.isValidSourceForPlayer))
        self:AddDebugEntry("API Source useErrorType", tostring(api.sourceInfo.useErrorType))
        if api.sourceInfo.useErrorType then
            self:AddDebugEntry("Derived useError Label",
                TRANSMOG_USE_ERROR_LABELS[api.sourceInfo.useErrorType] or "Unknown")
        end
        if api.sourceInfo.useErrorData then
            self:AddDebugEntry("API Source useErrorData", tostring(api.sourceInfo.useErrorData))
        end
    end

    if api.appearanceInfo then
        self:AddDebugEntry("API Appearance Collected", tostring(api.appearanceInfo.appearanceIsCollected))
        self:AddDebugEntry("API Source Collected", tostring(api.appearanceInfo.sourceIsCollected))
        self:AddDebugEntry("API Appearance Has Non-Level Req",
            tostring(api.appearanceInfo.appearanceHasAnyNonLevelRequirements))
        self:AddDebugEntry("API Appearance Meets Non-Level Req",
            tostring(api.appearanceInfo.appearanceMeetsNonLevelRequirements))
        self:AddDebugEntry("API Meets Player Condition",
            tostring(api.appearanceInfo.meetsTransmogPlayerCondition))
    end

    if api.appearanceSourceInfo then
        self:AddDebugEntry("API AppearanceSourceInfo ItemLink", tostring(api.appearanceSourceInfo.itemLink))
        self:AddDebugEntry("API AppearanceSourceInfo TransmogLink", tostring(api.appearanceSourceInfo.transmoglink))
        self:AddDebugEntry("API AppearanceSourceInfo SourceType", tostring(api.appearanceSourceInfo.sourceType))
    end

    if api.validSourcesForClass and #api.validSourcesForClass > 0 then
        self:AddDebugEntry("API Valid Sources For Class", tostring(#api.validSourcesForClass))
        for _, sourceInfo in ipairs(api.validSourcesForClass) do
            local label = string.format("  Source %s (Item %s)", tostring(sourceInfo.sourceID),
                tostring(sourceInfo.itemID))
            local details = string.format("playerCanCollect=%s, validForPlayer=%s, useErrorType=%s",
                tostring(sourceInfo.playerCanCollect),
                tostring(sourceInfo.isValidSourceForPlayer),
                tostring(sourceInfo.useErrorType))
            if sourceInfo.useError then
                details = details .. ", useError=" .. tostring(sourceInfo.useError)
            end
            self:AddDebugEntry(label, details)
        end
    end

    if transmogInfo then
        self:AddDebugEntry("Processed isTransmog", tostring(transmogInfo.isTransmog))
        self:AddDebugEntry("Processed isUpgrade", tostring(transmogInfo.isUpgrade))
        self:AddDebugEntry("Processed upgradeItemLevelDelta", tostring(transmogInfo.upgradeItemLevelDelta))
        self:AddDebugEntry("Processed upgradeMatchesSpec", tostring(transmogInfo.upgradeMatchesSpec))
        self:AddDebugEntry("Processed pawnIdentifiedUpgrade", tostring(transmogInfo.pawnIdentifiedUpgrade))
        self:AddDebugEntry("Processed pawnPrefersEquipped", tostring(transmogInfo.pawnPrefersEquipped))
        self:AddDebugEntry("Processed needsItem", tostring(transmogInfo.needsItem))
        self:AddDebugEntry("Processed otherNeedsItem", tostring(transmogInfo.otherNeedsItem))
        self:AddDebugEntry("Processed isCompletionistItem", tostring(transmogInfo.isCompletionistItem))
        self:AddDebugEntry("Processed matchesLootSpec", tostring(transmogInfo.matchesLootSpec))
        self:AddDebugEntry("Processed hasMetRequirements", tostring(transmogInfo.hasMetRequirements))
        self:AddDebugEntry("Processed canEquip", tostring(transmogInfo.canEquip))
        self:AddDebugEntry("Processed canEquipForPlayer", tostring(transmogInfo.canEquipForPlayer))
        self:AddDebugEntry("Processed playerCanCollectSource", tostring(transmogInfo.playerCanCollectSource))
        self:AddDebugEntry("Processed uniqueUpgradeBlocked", tostring(transmogInfo.uniqueUpgradeBlocked))
        self:AddDebugEntry("Processed uniqueUpgradeCandidate", tostring(transmogInfo.uniqueUpgradeCandidate))
        self:AddDebugEntry("Processed betterItemEquipped", tostring(transmogInfo.betterItemEquipped))
        self:AddDebugEntry("Processed equalItemLevelEquipped", tostring(transmogInfo.equalItemLevelEquipped))
        self:AddDebugEntry("Processed uniqueCategoryKey", tostring(transmogInfo.uniqueCategoryKey))
    end

    if debugExtras then
        if debugExtras.playerLootSpecID then
            local label = tostring(debugExtras.playerLootSpecID)
            local formatted = FormatSpecIDText(debugExtras.playerLootSpecID)
            if formatted and formatted ~= label then
                label = label .. " [" .. formatted .. "]"
            end
            self:AddDebugEntry("Debug Player Loot Spec", label)
        end
        if debugExtras.matchedSources then
            self:AddDebugEntry("Debug Matched Sources", tostring(#debugExtras.matchedSources))
            local matchedNames = {}
            for _, info in ipairs(debugExtras.matchedSources) do
                if info and info.name then
                    table.insert(matchedNames, info.name)
                end
            end
            if #matchedNames > 0 then
                self:AddDebugEntry("Debug Matched Source Names", table.concat(matchedNames, ", "))
            end
        end
        if debugExtras.appearanceSources then
            self:AddDebugEntry("Debug Appearance Sources", tostring(#debugExtras.appearanceSources))
        end
        self:AddDebugEntry("Debug playerCanUseSource", tostring(debugExtras.playerCanUseSource))
        self:AddDebugEntry("Debug canCollect", tostring(debugExtras.canCollect))
        self:AddDebugEntry("Debug accountCanCollect", tostring(debugExtras.accountCanCollect))
        self:AddDebugEntry("Debug otherSourceFound", tostring(debugExtras.otherSourceFound))
        self:AddDebugEntry("Debug otherSourceFoundForPlayer", tostring(debugExtras.otherSourceFoundForPlayer))
        self:AddDebugEntry("Debug currentSourceFound", tostring(debugExtras.currentSourceFound))
        self:AddDebugEntry("Debug lowestLevelFound", tostring(debugExtras.lowestLevelFound))
        self:AddDebugEntry("Debug shouldShowUpgrade", tostring(debugExtras.shouldShowUpgrade))
        self:AddDebugEntry("Debug blockedOffhandSlot", tostring(debugExtras.blockedOffhandSlot))
        self:AddDebugEntry("Debug isArtifactItem", tostring(debugExtras.isArtifactItem))
        if debugExtras.matchesLootSpecRaw ~= nil then
            self:AddDebugEntry("Debug matchesLootSpecRaw", tostring(debugExtras.matchesLootSpecRaw))
        end
        if debugExtras.isTabard ~= nil then
            self:AddDebugEntry("Debug isTabard", tostring(debugExtras.isTabard))
        end
    end

    local resolvedAppearanceID = processed.resolvedAppearanceID
        or (transmogInfo and transmogInfo.appearanceID)
        or (api.itemInfo and api.itemInfo.appearanceID)

    if not resolvedAppearanceID and api.itemInfo and api.itemInfo.sourceID then
        local appearanceInfo = C_TransmogCollection.GetAppearanceInfoBySource(api.itemInfo.sourceID)
        resolvedAppearanceID = appearanceInfo and appearanceInfo.appearanceID
    end

    local appearanceSources = (debugExtras and debugExtras.appearanceSources) or
        self:GetAppearanceSourcesForItem(resolvedAppearanceID)

    local currentItemID = item and item:GetItemID()
    local categoryID = api.sourceInfo and api.sourceInfo.categoryID
    if currentItemID and categoryID then
        local variantSources = self:GetVariantAppearanceSourcesForItem(currentItemID, resolvedAppearanceID, categoryID)
        if variantSources and #variantSources > 0 then
            local existing = {}
            if appearanceSources then
                for _, sourceInfo in ipairs(appearanceSources) do
                    if sourceInfo.sourceID then
                        existing[sourceInfo.sourceID] = true
                    end
                end
            else
                appearanceSources = {}
            end

            for _, sourceInfo in ipairs(variantSources) do
                if not existing[sourceInfo.sourceID] then
                    table.insert(appearanceSources, sourceInfo)
                    if sourceInfo.sourceID then
                        existing[sourceInfo.sourceID] = true
                    end
                end
            end
        end
    end

    self:AddSharedAppearanceInfo(item, appearanceSources, api.sourceInfo and api.sourceInfo.sourceID,
        api.sourceInfo)
end

function DebugFrameMixin:GetAppearanceSourcesForItem(appearanceID)
    if not appearanceID then
        return nil
    end

    local sourceIDs = C_TransmogCollection.GetAllAppearanceSources and
        C_TransmogCollection.GetAllAppearanceSources(appearanceID)
    if not sourceIDs or #sourceIDs == 0 then
        return nil
    end

    local sources = {}
    for _, sourceID in ipairs(sourceIDs) do
        local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
        if sourceInfo then
            EnsureSourceItemLink(sourceInfo.sourceID, sourceInfo.itemID)
            table.insert(sources, sourceInfo)
        end
    end

    if #sources == 0 then
        return nil
    end

    return sources
end

function DebugFrameMixin:GetVariantAppearanceSourcesForItem(itemID, currentAppearanceID, categoryID)
    if not itemID or not categoryID or not C_TransmogCollection.GetCategoryAppearances then
        return nil
    end

    local categoryAppearances = C_TransmogCollection.GetCategoryAppearances(categoryID)
    if not categoryAppearances or #categoryAppearances == 0 then
        return nil
    end

    local variantSources
    for _, appearanceInfo in ipairs(categoryAppearances) do
        local appearanceID = appearanceInfo.visualID
        if appearanceID and appearanceID ~= currentAppearanceID then
            local sources = C_TransmogCollection.GetAppearanceSources(appearanceID)
            if sources then
                for _, source in ipairs(sources) do
                    if source.itemID == itemID then
                        local detailedSource = C_TransmogCollection.GetSourceInfo(source.sourceID)
                        if detailedSource then
                            EnsureSourceItemLink(detailedSource.sourceID, detailedSource.itemID)
                            variantSources = variantSources or {}
                            table.insert(variantSources, detailedSource)
                        end
                    end
                end
            end
        end
    end

    return variantSources
end

BuildSharedStatusParts = function(grouped, includeUseError)
    local statusParts = {}

    local isCollected = grouped.isCollected
    if (isCollected == nil or isCollected == false) and grouped.sources and #grouped.sources > 0 then
        for _, sourceID in ipairs(grouped.sources) do
            local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
            if sourceInfo and sourceInfo.isCollected then
                isCollected = true
                break
            end
        end

        if not isCollected then
            for _, sourceID in ipairs(grouped.sources) do
                if C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID) then
                    isCollected = true
                    break
                end
            end
        end
    end

    if isCollected ~= nil then
        table.insert(statusParts, isCollected and "collected" or "uncollected")
    end
    if grouped.playerCanCollect ~= nil then
        table.insert(statusParts, grouped.playerCanCollect and "playerCanCollect" or "playerCannotCollect")
    end
    if grouped.isValidSourceForPlayer ~= nil then
        table.insert(statusParts, grouped.isValidSourceForPlayer and "validForPlayer" or "invalidForPlayer")
    end
    if includeUseError and grouped.useErrorType and grouped.useErrorType ~= Enum.TransmogUseErrorType.None then
        table.insert(statusParts, TRANSMOG_USE_ERROR_LABELS[grouped.useErrorType] or
            ("useErrorType " .. tostring(grouped.useErrorType)))
    end

    return statusParts
end

function DebugFrameMixin:BuildSharedAppearanceItems(item, appearanceSources, currentSourceID, currentSourceInfo)
    if not item or type(appearanceSources) ~= "table" or #appearanceSources == 0 then
        return nil, nil
    end

    local currentItemID = item:GetItemID()
    local normalizedCurrentMod
    if currentSourceInfo and currentSourceInfo.itemModID ~= nil then
        normalizedCurrentMod = currentSourceInfo.itemModID
    elseif currentSourceInfo then
        normalizedCurrentMod = 0
    end
    local currentVisualID = currentSourceInfo and currentSourceInfo.visualID
    local metadataCache = self.variantMetadataCache

    local sourceAppearanceCache = {}
    local sourceLinkCache = {}
    local function GetSourceAppearanceID(sourceID)
        if not sourceID then
            return nil
        end

        if sourceAppearanceCache[sourceID] ~= nil then
            return sourceAppearanceCache[sourceID] or nil
        end

        local appearanceInfo = C_TransmogCollection.GetAppearanceInfoBySource(sourceID)
        local appearanceID = appearanceInfo and appearanceInfo.appearanceID
        sourceAppearanceCache[sourceID] = appearanceID or false
        return appearanceID
    end

    local function GetSourceItemLink(sourceID, itemID)
        if not sourceID then
            return nil
        end

        if sourceLinkCache[sourceID] ~= nil then
            return sourceLinkCache[sourceID] or nil
        end

        local itemLink = EnsureSourceItemLink(sourceID, itemID)
        sourceLinkCache[sourceID] = itemLink or false
        return itemLink
    end

    local currentAppearanceID = currentSourceID and GetSourceAppearanceID(currentSourceID)

    local function NormalizeModID(modID)
        return modID or 0
    end

    local function IsSameVariant(sourceInfo, sourceAppearanceID)
        if currentAppearanceID and sourceAppearanceID then
            if sourceAppearanceID ~= currentAppearanceID then
                return false
            end
        elseif normalizedCurrentMod and NormalizeModID(sourceInfo.itemModID) ~= normalizedCurrentMod then
            return false
        end

        if currentVisualID and sourceInfo.visualID and sourceInfo.visualID ~= currentVisualID then
            return false
        end

        return true
    end

    local sharedByItem = {}
    local sharedOrdered = {}
    local variationsByKey = {}
    local variationOrdered = {}

    local function BuildKey(itemID, itemModID, visualID, appearanceID, isVariation)
        if not isVariation then
            return itemID
        end

        local modKey = NormalizeModID(itemModID)
        local visualKey = visualID or "novisual"
        local appearanceKey = appearanceID or "noappearance"
        if itemID then
            return string.format("%d:%d:%s:%s", itemID, modKey, tostring(visualKey), tostring(appearanceKey))
        end

        return string.format("unknown:%d:%s:%s", modKey, tostring(visualKey), tostring(appearanceKey))
    end

    local function InsertEntry(container, ordered, key, sourceInfo, appearanceID)
        local grouped = container[key]
        local cachedEntry = metadataCache and sourceInfo.sourceID and metadataCache[sourceInfo.sourceID]
        local preferredLink = cachedEntry and cachedEntry.preferredLink
        local sourceLink = preferredLink or GetSourceItemLink(sourceInfo.sourceID, sourceInfo.itemID)
        if not grouped then
            grouped = {
                itemID = sourceInfo.itemID,
                itemModID = sourceInfo.itemModID,
                sources = {},
                visualID = sourceInfo.visualID,
                appearanceID = appearanceID,
                itemLink = sourceLink,
                isCollected = sourceInfo.isCollected,
                playerCanCollect = sourceInfo.playerCanCollect,
                isValidSourceForPlayer = sourceInfo.isValidSourceForPlayer,
                useErrorType = sourceInfo.useErrorType
            }
            container[key] = grouped
            table.insert(ordered, grouped)
        else
            if sourceInfo.isCollected then
                grouped.isCollected = true
            end
            if sourceInfo.playerCanCollect then
                grouped.playerCanCollect = true
            end
            if sourceInfo.isValidSourceForPlayer then
                grouped.isValidSourceForPlayer = true
            end
            if not grouped.useErrorType and sourceInfo.useErrorType then
                grouped.useErrorType = sourceInfo.useErrorType
            end
            if not grouped.appearanceID and appearanceID then
                grouped.appearanceID = appearanceID
            end
            if not grouped.itemLink and sourceLink then
                grouped.itemLink = sourceLink
            end
        end

        if sourceInfo.sourceID then
            table.insert(grouped.sources, sourceInfo.sourceID)
        end

        if sourceInfo.sourceID then
            ApplyCachedVariantMetadata(grouped, metadataCache, sourceInfo.sourceID)
        end

        UpdateVariantMetadata(grouped, sourceInfo, sourceLink, metadataCache, GetEncounterJournalLinkForSource)
    end

    for _, sourceInfo in ipairs(appearanceSources) do
        local sourceItemID = sourceInfo.itemID
        local isCurrentSource = currentSourceID and sourceInfo.sourceID == currentSourceID
        local sourceAppearanceID = GetSourceAppearanceID(sourceInfo.sourceID)
        local sameVariant = IsSameVariant(sourceInfo, sourceAppearanceID)

        if sourceItemID and sourceItemID ~= currentItemID and sameVariant then
            local key = BuildKey(sourceItemID, sourceInfo.itemModID, sourceInfo.visualID, sourceAppearanceID, false)
            InsertEntry(sharedByItem, sharedOrdered, key, sourceInfo, sourceAppearanceID)
        elseif not isCurrentSource and not sameVariant then
            local key = BuildKey(sourceItemID, sourceInfo.itemModID, sourceInfo.visualID, sourceAppearanceID, true)
            InsertEntry(variationsByKey, variationOrdered, key, sourceInfo, sourceAppearanceID)
        elseif not sourceItemID and not isCurrentSource and not sameVariant then
            local key = BuildKey(nil, sourceInfo.itemModID, sourceInfo.visualID, sourceAppearanceID, true)
            InsertEntry(variationsByKey, variationOrdered, key, sourceInfo, sourceAppearanceID)
        end
    end

    if #sharedOrdered == 0 then
        sharedOrdered = nil
    else
        table.sort(sharedOrdered, function(a, b)
            if a.itemID and b.itemID then
                return a.itemID < b.itemID
            end
            return tostring(a.itemID) < tostring(b.itemID)
        end)
    end

    if variationOrdered and #variationOrdered == 0 then
        variationOrdered = nil
    elseif variationOrdered then
        table.sort(variationOrdered, function(a, b)
            local aQuality = a.itemLevelQuality or 0
            local bQuality = b.itemLevelQuality or 0
            if aQuality ~= bQuality then
                return aQuality > bQuality
            end

            local aLevel = a.itemLevel or -1
            local bLevel = b.itemLevel or -1
            if aLevel ~= bLevel then
                return aLevel > bLevel
            end

            local aDifficulty = a.variantDifficultyText or ""
            local bDifficulty = b.variantDifficultyText or ""
            if aDifficulty ~= bDifficulty then
                return aDifficulty < bDifficulty
            end

            local aTier = a.variantTierText or ""
            local bTier = b.variantTierText or ""
            if aTier ~= bTier then
                return aTier < bTier
            end

            local aID = a.itemID or math.huge
            local bID = b.itemID or math.huge
            if aID == bID then
                local aMod = NormalizeModID(a.itemModID)
                local bMod = NormalizeModID(b.itemModID)
                if aMod == bMod then
                    local aAppearance = a.appearanceID or 0
                    local bAppearance = b.appearanceID or 0
                    if aAppearance == bAppearance then
                        return (a.visualID or 0) < (b.visualID or 0)
                    end
                    return aAppearance < bAppearance
                end
                return aMod < bMod
            end
            return aID < bID
        end)
    end

    return sharedOrdered, variationOrdered
end

function DebugFrameMixin:AddSharedAppearanceInfo(item, appearanceSources, currentSourceID, currentSourceInfo)
    local sharedItems, variationItems = self:BuildSharedAppearanceItems(item, appearanceSources, currentSourceID,
        currentSourceInfo)

    if currentSourceInfo and currentSourceID then
        local currentIsCollected = currentSourceInfo.isCollected
        if currentIsCollected == nil then
            currentIsCollected = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(currentSourceID)
        end
        local currentAppearanceInfo = C_TransmogCollection.GetAppearanceInfoBySource(currentSourceID)
        local currentSourceAppearanceInfo = CaerdonAPI and CaerdonAPI.GetAppearanceSourceInfo and
            CaerdonAPI:GetAppearanceSourceInfo(currentSourceID)
        local currentSourceLink = currentSourceAppearanceInfo and currentSourceAppearanceInfo.itemLink

        local currentItemLink = item:GetItemLink() or currentSourceLink

        local currentEntry = {
            itemID = currentSourceInfo.itemID or item:GetItemID(),
            sources = { currentSourceID },
            isCollected = currentIsCollected,
            playerCanCollect = currentSourceInfo.playerCanCollect,
            isValidSourceForPlayer = currentSourceInfo.isValidSourceForPlayer,
            useErrorType = currentSourceInfo.useErrorType,
            isCurrentItem = true,
            itemModID = currentSourceInfo.itemModID,
            visualID = currentSourceInfo.visualID,
            appearanceID = currentAppearanceInfo and currentAppearanceInfo.appearanceID,
            itemLink = currentItemLink
        }
        ApplyCachedVariantMetadata(currentEntry, self.variantMetadataCache, currentSourceID)
        UpdateVariantMetadata(currentEntry, currentSourceInfo, currentItemLink, self.variantMetadataCache, GetEncounterJournalLinkForSource)
        if sharedItems then
            table.insert(sharedItems, 1, currentEntry)
        else
            sharedItems = { currentEntry }
        end
    end
    self.currentSharedAppearanceItems = sharedItems

    self.currentAppearanceVariations = variationItems

    self:UpdateSharedAppearanceUI(sharedItems)
    self:UpdateAppearanceVariationsUI(variationItems)
end

function DebugFrameMixin:GetDetailSectionWidth()
    local infoWidth = (self.infoFrame and self.infoFrame:GetWidth()) or 0
    local contentWidth = (self.content and self.content:GetWidth()) or infoWidth
    local scrollWidth = (self.scrollFrame and self.scrollFrame:GetWidth()) or contentWidth
    local frameWidth = (self.frame and self.frame:GetWidth()) or scrollWidth

    if contentWidth > 0 then
        contentWidth = contentWidth - DETAIL_SECTION_RIGHT_PADDING
    end
    if scrollWidth > 0 then
        scrollWidth = scrollWidth - 25
    end
    if frameWidth > 0 then
        frameWidth = frameWidth - 60
    end

    local targetWidth = math.max(infoWidth, contentWidth, scrollWidth, frameWidth)
    if targetWidth <= 0 then
        return MIN_APPEARANCE_SECTION_WIDTH
    end

    return targetWidth
end

function DebugFrameMixin:AcquireAppearanceItemFrame(frameTable, container, prefix, index, layoutRefreshFunc)
    local frame = frameTable[index]
    if not frame then
        local frameName = prefix .. index
        frame = CreateFrame("Frame", frameName, container, "BackdropTemplate")
        frame:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        frame.defaultBgColor = { 0.05, 0.05, 0.05, 0.8 }
        frame.defaultBorderColor = { 0.3, 0.3, 0.3, 1 }
        frame.hoverBgColor = { 0.1, 0.1, 0.15, 0.9 }
        frame.hoverBorderColor = { 0.5, 0.5, 0.6, 1 }
        frame:SetBackdropColor(unpack(frame.defaultBgColor))
        frame:SetBackdropBorderColor(unpack(frame.defaultBorderColor))

        frame.itemButton = CreateFrame("ItemButton", frameName .. "Button", frame)
        frame.itemButton:SetSize(40, 40)
        frame.itemButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
        frame.itemButton:RegisterForDrag("LeftButton")
        frame.itemButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        frame.itemButton:SetScript("OnEnter", function(button)
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            if button.itemLink then
                GameTooltip:SetHyperlink(button.itemLink)
            elseif button.itemID then
                GameTooltip:SetItemByID(button.itemID)
            end
            GameTooltip:Show()
        end)
        frame.itemButton:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        frame.itemButton:SetScript("OnClick", function(button)
            local link = button.itemLink
            if not link and button.itemID then
                link = select(2, C_Item.GetItemInfo(button.itemID))
            end

            if link and IsModifiedClick() then
                HandleModifiedItemClick(link)
            end
        end)
        frame.itemButton:SetScript("OnDragStart", function(button)
            if button.itemLink then
                C_Item.PickupItem(button.itemLink)
            elseif button.itemID then
                C_Item.PickupItem(button.itemID)
            end
        end)

        frame.itemNameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.itemNameText:SetPoint("TOPLEFT", frame.itemButton, "TOPRIGHT", 8, 0)
        frame.itemNameText:SetJustifyH("LEFT")
        frame.itemNameText:SetWordWrap(false)

        frame.descriptorText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame.descriptorText:SetPoint("TOPLEFT", frame.itemNameText, "BOTTOMLEFT", 0, -2)
        frame.descriptorText:SetJustifyH("LEFT")
        frame.descriptorText:SetTextColor(0.8, 0.8, 0.8)

        frame.statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame.statusText:SetPoint("TOPLEFT", frame.descriptorText, "BOTTOMLEFT", 0, -2)
        frame.statusText:SetJustifyH("LEFT")
        frame.statusText:SetTextColor(0.7, 0.9, 0.7)

        frame.itemNameButton = CreateFrame("Button", nil, frame)
        frame.itemNameButton:SetScript("OnClick", function(button)
            local link = button.itemLink
            if not link then
                local parentFrame = button:GetParent()
                if parentFrame and parentFrame.itemButton then
                    link = parentFrame.itemButton.itemLink
                    if not link and parentFrame.itemButton.itemID then
                        link = select(2, C_Item.GetItemInfo(parentFrame.itemButton.itemID))
                    end
                    button.itemLink = link
                end
            end
            if not link then
                local parentFrame = button:GetParent()
                if parentFrame and parentFrame.itemButton and parentFrame.itemButton.itemID and
                    C_Item and C_Item.RequestLoadItemDataByID then
                    C_Item.RequestLoadItemDataByID(parentFrame.itemButton.itemID)
                    print("Caerdon Wardrobe Debug: Item data not ready yet.")
                end
                return
            end

            if IsModifiedClick("CHATLINK") then
                ChatEdit_InsertLink(link)
                return
            end

            if IsControlKeyDown() then
                local owner = frame.debugOwner
                if owner and owner.HandleAppearanceLink then
                    owner:HandleAppearanceLink(link)
                else
                    DressUpLink(link)
                end
                return
            end

            if ItemRefTooltip:IsShown() and ItemRefTooltip.itemLink == link then
                ItemRefTooltip:Hide()
            else
                ShowUIPanel(ItemRefTooltip)
                if not ItemRefTooltip:IsShown() then
                    ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE")
                end
                ItemRefTooltip:SetHyperlink(link)
                ItemRefTooltip.itemLink = link
            end
        end)

        frame.expandButton = CreateFrame("Button", nil, frame)
        frame.expandButton:SetSize(20, 20)
        frame.expandButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
        frame.expandButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
        frame.expandButton:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
        frame.expandButton:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")

        frame.detailsFrame = CreateFrame("Frame", nil, frame)
        frame.detailsFrame:SetPoint("TOPLEFT", frame.itemButton, "BOTTOMLEFT", 0, -5)
        frame.detailsFrame:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
        frame.detailsFrame:Hide()
        frame.detailTexts = {}

        frame.ToggleDetails = function(entryFrame, desiredState)
            local shouldShow = desiredState
            if shouldShow == nil then
                shouldShow = not entryFrame.detailsFrame:IsShown()
            end

            if shouldShow then
                entryFrame.detailsFrame:Show()
                entryFrame.expandButton:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
                entryFrame.expandButton:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
                local detailsHeight = entryFrame.detailsFrame:GetHeight()
                entryFrame:SetHeight(APPEARANCE_ITEM_COLLAPSED_HEIGHT + detailsHeight + 5)
                entryFrame.isExpanded = true
            else
                entryFrame.detailsFrame:Hide()
                entryFrame.expandButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
                entryFrame.expandButton:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
                entryFrame:SetHeight(APPEARANCE_ITEM_COLLAPSED_HEIGHT)
                entryFrame.isExpanded = false
            end

            if entryFrame.layoutRefreshFunc then
                entryFrame.layoutRefreshFunc()
            end
        end

        frame.expandButton:SetScript("OnClick", function()
            frame:ToggleDetails()
        end)

        frame:EnableMouse(true)
        frame:SetScript("OnEnter", function(selfFrame)
            selfFrame:SetBackdropColor(unpack(selfFrame.hoverBgColor))
            selfFrame:SetBackdropBorderColor(unpack(selfFrame.hoverBorderColor))
        end)
        frame:SetScript("OnLeave", function(selfFrame)
            selfFrame:SetBackdropColor(unpack(selfFrame.defaultBgColor))
            selfFrame:SetBackdropBorderColor(unpack(selfFrame.defaultBorderColor))
        end)
        frame:SetScript("OnMouseDown", function(selfFrame, button)
            if button ~= "LeftButton" then
                return
            end

            local foci = GetMouseFoci() or {}

            for _, focus in ipairs(foci) do
                if focus == selfFrame.itemButton or focus == selfFrame.itemNameButton or focus == selfFrame.expandButton then
                    return
                end
            end

            selfFrame:ToggleDetails()
        end)

        frameTable[index] = frame
    end

    frame.layoutRefreshFunc = layoutRefreshFunc
    frame.debugOwner = self
    frame:SetHeight(APPEARANCE_ITEM_COLLAPSED_HEIGHT)
    frame.detailsFrame:Hide()
    frame.expandButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
    frame.expandButton:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
    frame.isExpanded = false

    return frame
end

function DebugFrameMixin:ResetAppearanceFrameDetails(frame)
    if frame.detailTexts then
        for _, region in ipairs(frame.detailTexts) do
            if region.Hide then
                region:Hide()
            end
            if region.ClearAllPoints then
                region:ClearAllPoints()
            end
        end
        wipe(frame.detailTexts)
    else
        frame.detailTexts = {}
    end
end

function DebugFrameMixin:CreateAppearanceDetailBuilder(frame)
    local detailY = 0
    local function AddLine(text, color, indent)
        local fontString = frame.detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fontString:SetPoint("TOPLEFT", frame.detailsFrame, "TOPLEFT", indent or 8, -detailY)
        fontString:SetJustifyH("LEFT")
        fontString:SetText(text)
        local r, g, b = 0.9, 0.9, 0.9
        if color then
            r, g, b = color[1], color[2], color[3]
        end
        fontString:SetTextColor(r, g, b)
        table.insert(frame.detailTexts, fontString)
        detailY = detailY + 16
    end

    local function AddSpacer(amount)
        detailY = detailY + (amount or 4)
    end

    local function GetHeight()
        return detailY
    end

    return AddLine, AddSpacer, GetHeight
end

function DebugFrameMixin:AddVariantDiagnosticDetailLines(addLine, addSpacer, sources)
    if not sources then
        return
    end

    for _, sourceID in ipairs(sources) do
        local diag = variantEJDiagnostics[sourceID]
        if diag then
            addLine(string.format("EJ Source %s: final=%s, link=%s",
                tostring(sourceID),
                diag.finalLinkSource or diag.failureReason or "none",
                diag.finalLink or diag.lootInfoLink or "nil"), { 0.8, 0.8, 1 }, 8)

            if diag.dropInstanceName or diag.dropEncounterName or diag.dropDifficultyName then
                addLine(string.format("Drop: %s - %s (%s)",
                    tostring(diag.dropInstanceName or "unknown"),
                    tostring(diag.dropEncounterName or "unknown"),
                    tostring(diag.dropDifficultyName or "unknown")), { 0.7, 0.7, 0.7 }, 16)
            end

            if diag.instanceID or diag.encounterID or diag.difficultyID then
                addLine(string.format("IDs: instance=%s encounter=%s difficulty=%s",
                    tostring(diag.instanceID or "nil"),
                    tostring(diag.encounterID or "nil"),
                    tostring(diag.difficultyID or "nil")), { 0.7, 0.7, 0.7 }, 16)
            end

            addSpacer(2)
        end
    end
end

local function GetDebugItemDisplayInfo(data)
    local itemID = data and data.itemID
    local lookupItem = data and (data.itemLink or itemID)
    local itemName, resolvedLink, itemQuality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(lookupItem)
    return {
        itemID = itemID,
        itemLink = data and data.itemLink or resolvedLink,
        icon = icon,
        quality = itemQuality,
        fallbackName = itemName
    }
end

local function ApplyItemButtonState(button, displayInfo)
    button.itemID = displayInfo.itemID
    button.itemLink = displayInfo.itemLink
    if button.icon then
        button.icon:SetTexture(displayInfo.icon or 134400)
        button.icon:Show()
    end

    if button.IconBorder then
        if displayInfo.quality then
            local r, g, b = C_Item.GetItemQualityColor(displayInfo.quality)
            button.IconBorder:SetVertexColor(r, g, b)
            button.IconBorder:Show()
        else
            button.IconBorder:Hide()
        end
    end
end

local function SetAppearanceName(frame, displayInfo, descriptorText, isCurrent)
    local linkText = displayInfo.itemLink or FormatItemLinkForDebug(displayInfo.itemID, displayInfo.itemLink)
    if not linkText and displayInfo.fallbackName then
        linkText = string.format("[%s] (ItemID %d)", displayInfo.fallbackName, displayInfo.itemID or 0)
    end
    if not linkText then
        linkText = "Unknown Item"
    end

    local prefix = isCurrent and "|cff00ff00[Current]|r " or ""
    frame.itemNameText:SetText(prefix .. linkText .. (descriptorText or ""))
    frame.itemNameButton:ClearAllPoints()
    frame.itemNameButton:SetPoint("TOPLEFT", frame.itemNameText, "TOPLEFT", 0, 0)
    frame.itemNameButton:SetPoint("BOTTOMRIGHT", frame.itemNameText, "BOTTOMRIGHT", 0, 0)
    frame.itemNameButton.itemLink = displayInfo.itemLink
end

function DebugFrameMixin:PopulateSharedAppearanceFrame(frame, data, index)
    local displayInfo = GetDebugItemDisplayInfo(data)
    ApplyItemButtonState(frame.itemButton, displayInfo)
    SetAppearanceName(frame, displayInfo, BuildVariantDescriptorText(data), data.isCurrentItem)

    local statusParts = BuildSharedStatusParts(data, true)
    if #statusParts > 0 then
        frame.statusText:SetText("Status: " .. table.concat(statusParts, ", "))
    else
        frame.statusText:SetText("Status: none")
    end

    if data.variantInstanceText or data.variantEncounterText then
        local pieces = {}
        if data.variantInstanceText then
            table.insert(pieces, data.variantInstanceText)
        end
        if data.variantEncounterText then
            table.insert(pieces, data.variantEncounterText)
        end
        frame.descriptorText:SetText(table.concat(pieces, " - "))
    else
        frame.descriptorText:SetText("")
    end

    CaerdonWardrobe:ClearButton(frame.itemButton)
    local caerdonItem
    if displayInfo.itemLink then
        caerdonItem = CaerdonItem:CreateFromItemLink(displayInfo.itemLink)
    elseif displayInfo.itemID then
        caerdonItem = CaerdonItem:CreateFromItemID(displayInfo.itemID)
    end

    if caerdonItem then
        CaerdonWardrobe:UpdateButton(frame.itemButton, caerdonItem, self, {
            locationKey = string.format("shared-item-%s-%d", tostring(displayInfo.itemID or "unknown"), index),
            isDebugFrame = true
        }, {
            statusProminentSize = 20,
            bindingScale = 1.0
        })
    end

    self:ResetAppearanceFrameDetails(frame)
    local addLine, addSpacer, getHeight = self:CreateAppearanceDetailBuilder(frame)

    if data.sources and #data.sources > 0 then
        addLine("Source IDs: " .. table.concat(data.sources, ", "), { 1, 0.82, 0 })
    end

    if data.variantDifficultyText or data.variantTierText then
        local variants = {}
        if data.variantDifficultyText then
            table.insert(variants, data.variantDifficultyText)
        end
        if data.variantTierText then
            table.insert(variants, data.variantTierText)
        end
        addLine("Variant: " .. table.concat(variants, " - "), { 0.7, 0.7, 0.7 })
    end

    if data.itemLevel then
        addLine("Item Level: " .. tostring(data.itemLevel), { 0.7, 0.7, 0.7 })
    end

    if data.itemLevelSource then
        addLine("Item Level Source: " .. tostring(data.itemLevelSource), { 0.7, 0.7, 0.7 })
    end

    if data.playerCanCollect ~= nil or data.isValidSourceForPlayer ~= nil then
        addLine(string.format("playerCanCollect=%s | isValidForPlayer=%s",
            tostring(data.playerCanCollect), tostring(data.isValidSourceForPlayer)), { 0.7, 0.7, 0.7 })
    end

    if data.useErrorType and data.useErrorType ~= Enum.TransmogUseErrorType.None then
        local label = TRANSMOG_USE_ERROR_LABELS[data.useErrorType] or ("Use Error " .. tostring(data.useErrorType))
        addLine("useErrorType: " .. label, { 1, 0.4, 0.4 })
    end

    self:AddVariantDiagnosticDetailLines(addLine, addSpacer, data.sources)

    frame.detailsFrame:SetHeight(getHeight() + 8)
    frame:SetHeight(APPEARANCE_ITEM_COLLAPSED_HEIGHT)
    frame.detailsFrame:Hide()
    frame.isExpanded = false
    frame:Show()
end

function DebugFrameMixin:PopulateAppearanceVariationFrame(frame, data, index)
    local displayInfo = GetDebugItemDisplayInfo(data)
    ApplyItemButtonState(frame.itemButton, displayInfo)
    local modSummary = string.format("Mod %s | Visual %s | Appearance %s",
        tostring(data.itemModID or 0),
        tostring(data.visualID or "nil"),
        tostring(data.appearanceID or "nil"))
    local descriptorText = BuildVariantDescriptorText(data)
    SetAppearanceName(frame, displayInfo, descriptorText ~= "" and descriptorText or "", false)
    frame.descriptorText:SetText(modSummary)

    local statusParts = BuildSharedStatusParts(data, true)
    if #statusParts > 0 then
        frame.statusText:SetText("Status: " .. table.concat(statusParts, ", "))
    else
        frame.statusText:SetText("Status: none")
    end

    CaerdonWardrobe:ClearButton(frame.itemButton)
    local caerdonItem
    if displayInfo.itemLink then
        caerdonItem = CaerdonItem:CreateFromItemLink(displayInfo.itemLink)
    elseif displayInfo.itemID then
        caerdonItem = CaerdonItem:CreateFromItemID(displayInfo.itemID)
    end

    if caerdonItem then
        CaerdonWardrobe:UpdateButton(frame.itemButton, caerdonItem, self, {
            locationKey = string.format("variation-item-%s-%d", tostring(displayInfo.itemID or "unknown"), index),
            isDebugFrame = true
        }, {
            statusProminentSize = 20,
            bindingScale = 1.0
        })
    end

    self:ResetAppearanceFrameDetails(frame)
    local addLine, addSpacer, getHeight = self:CreateAppearanceDetailBuilder(frame)

    if data.sources and #data.sources > 0 then
        addLine("Source IDs: " .. table.concat(data.sources, ", "), { 1, 0.82, 0 })
    end

    addLine("Visual ID: " .. tostring(data.visualID or "nil"), { 0.7, 0.7, 0.7 })
    addLine("Appearance ID: " .. tostring(data.appearanceID or "nil"), { 0.7, 0.7, 0.7 })
    addLine("Item Mod ID: " .. tostring(data.itemModID or 0), { 0.7, 0.7, 0.7 })

    if data.itemLevel then
        addLine("Item Level: " .. tostring(data.itemLevel), { 0.7, 0.7, 0.7 })
    end

    addLine(string.format("playerCanCollect=%s | isValidForPlayer=%s",
        tostring(data.playerCanCollect), tostring(data.isValidSourceForPlayer)), { 0.7, 0.7, 0.7 })

    if data.useErrorType and data.useErrorType ~= Enum.TransmogUseErrorType.None then
        local label = TRANSMOG_USE_ERROR_LABELS[data.useErrorType] or ("Use Error " .. tostring(data.useErrorType))
        addLine("useErrorType: " .. label, { 1, 0.4, 0.4 })
    end

    if data.variantInstanceText or data.variantEncounterText then
        local pieces = {}
        if data.variantInstanceText then
            table.insert(pieces, data.variantInstanceText)
        end
        if data.variantEncounterText then
            table.insert(pieces, data.variantEncounterText)
        end
        addLine("Source: " .. table.concat(pieces, " - "), { 0.8, 0.8, 0.8 })
    end

    self:AddVariantDiagnosticDetailLines(addLine, addSpacer, data.sources)

    frame.detailsFrame:SetHeight(getHeight() + 8)
    frame:SetHeight(APPEARANCE_ITEM_COLLAPSED_HEIGHT)
    frame.detailsFrame:Hide()
    frame.isExpanded = false
    frame:Show()
end

function DebugFrameMixin:RefreshSharedAppearanceLayout()
    if not self.sharedAppearanceContainer or not self.sharedAppearanceContainer:IsShown() then
        return
    end

    self.sharedAppearanceContainer:ClearAllPoints()
    local sharedAnchor = self.recipeCreatedItemContainer and self.recipeCreatedItemContainer:IsShown()
        and self.recipeCreatedItemContainer or self.infoFrame
    self.sharedAppearanceContainer:SetPoint("TOPLEFT", sharedAnchor, "BOTTOMLEFT", 0, -10)
    self.sharedAppearanceContainer:SetWidth(self:GetDetailSectionWidth())

    local headerHeight = 25
    local yOffset = headerHeight
    if self.sharedAppearanceItemFrames then
        for _, frame in ipairs(self.sharedAppearanceItemFrames) do
            if frame:IsShown() then
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", self.sharedAppearanceContainer, "TOPLEFT", 0, -yOffset)
                frame:SetPoint("TOPRIGHT", self.sharedAppearanceContainer, "TOPRIGHT", -15, -yOffset)
                yOffset = yOffset + frame:GetHeight() + 5
            end
        end
    end

    if self.sharedAppearanceOverflowText and self.sharedAppearanceOverflowText:IsShown() then
        self.sharedAppearanceOverflowText:ClearAllPoints()
        self.sharedAppearanceOverflowText:SetPoint("TOPLEFT", self.sharedAppearanceContainer, "TOPLEFT", 8, -yOffset)
        yOffset = yOffset + 16
    end

    self.sharedAppearanceContainer:SetHeight(math.max(yOffset, headerHeight))
    self:UpdateContentHeight()
end

function DebugFrameMixin:UpdateRecipeCreatedItemUI(recipeInfo)
    if not self.recipeCreatedItemContainer then
        self.recipeCreatedItemContainer = CreateFrame("Frame", "CaerdonDebugRecipeCreatedItemContainer", self.content)
        self.recipeCreatedItemHeader = self.recipeCreatedItemContainer:CreateFontString(nil, "OVERLAY",
            "GameFontNormalLarge")
        self.recipeCreatedItemHeader:SetPoint("TOPLEFT", self.recipeCreatedItemContainer, "TOPLEFT", 0, 0)
        self.recipeCreatedItemHeader:SetTextColor(0.5, 0.8, 1)
        self.recipeCreatedItemFrames = {}
    end

    if not recipeInfo or not recipeInfo.createdItem then
        self.recipeCreatedItemContainer:Hide()
        if self.recipeCreatedItemFrames then
            for _, frame in ipairs(self.recipeCreatedItemFrames) do
                if frame.itemButton then
                    CaerdonWardrobe:ClearButton(frame.itemButton)
                end
                frame:Hide()
                if frame.detailsFrame then
                    frame.detailsFrame:Hide()
                end
            end
        end
        self:UpdateContentHeight()
        return
    end

    self.recipeCreatedItemContainer:Show()
    self.recipeCreatedItemHeader:SetText("Created Item")

    local frame = self:AcquireAppearanceItemFrame(self.recipeCreatedItemFrames, self.recipeCreatedItemContainer,
        "CaerdonDebugRecipeCreatedItem", 1, function()
            self:RefreshRecipeCreatedItemLayout()
        end)

    local createdItem = recipeInfo.createdItem
    local createdLink = createdItem:GetItemLink()
    local createdID = createdItem:GetItemID()
    local itemName, resolvedLink, itemQuality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(createdLink or createdID)

    local displayInfo = {
        itemID = createdID,
        itemLink = createdLink or resolvedLink,
        icon = icon,
        quality = itemQuality,
        fallbackName = itemName
    }

    ApplyItemButtonState(frame.itemButton, displayInfo)
    SetAppearanceName(frame, displayInfo, "", false)

    -- Show recipe-specific status
    local statusParts = {}
    if recipeInfo.learned then
        table.insert(statusParts, "|cff888888Learned|r")
    else
        table.insert(statusParts, "|cff00ff00Not Learned|r")
    end
    if recipeInfo.canLearn then
        table.insert(statusParts, "|cff00ff00Can Learn|r")
    end
    if recipeInfo.firstCraft then
        table.insert(statusParts, "|cffffff00First Craft|r")
    end
    frame.statusText:SetText(table.concat(statusParts, ", "))

    -- Show item type info as descriptor
    local caerdonCreatedItem
    if createdLink then
        caerdonCreatedItem = CaerdonItem:CreateFromItemLink(createdLink)
    elseif createdID then
        caerdonCreatedItem = CaerdonItem:CreateFromItemID(createdID)
    end
    local createdType = ""
    if caerdonCreatedItem and not caerdonCreatedItem:IsItemEmpty() then
        createdType = caerdonCreatedItem:GetCaerdonItemType() or ""
    end
    if recipeInfo.schematic and recipeInfo.schematic.outputItemID then
        frame.descriptorText:SetText(createdType .. " (Output ID: " .. tostring(recipeInfo.schematic.outputItemID) .. ")")
    else
        frame.descriptorText:SetText(createdType)
    end

    -- Update Caerdon overlay on the card's item button
    CaerdonWardrobe:ClearButton(frame.itemButton)
    if caerdonCreatedItem and not caerdonCreatedItem:IsItemEmpty() then
        CaerdonWardrobe:UpdateButton(frame.itemButton, caerdonCreatedItem, self, {
            locationKey = "recipe-created-" .. tostring(createdID or "unknown"),
            isDebugFrame = true
        }, {
            statusProminentSize = 20,
            bindingScale = 1.0
        })
    end

    -- Build expandable detail lines for the created item
    self:ResetAppearanceFrameDetails(frame)
    local addLine, addSpacer, getHeight = self:CreateAppearanceDetailBuilder(frame)

    -- Basic item info
    if createdID then
        addLine("Item ID: " .. tostring(createdID), { 1, 0.82, 0 })
    end

    local createdItemName, _, createdItemQuality, createdItemLevel, createdMinLevel, createdItemType,
        createdItemSubType, _, createdEquipLoc, _, createdSellPrice, createdClassID, createdSubClassID =
        C_Item.GetItemInfo(createdLink or createdID)

    if createdItemType then
        local typeStr = createdItemType
        if createdItemSubType and createdItemSubType ~= createdItemType then
            typeStr = typeStr .. " - " .. createdItemSubType
        end
        addLine("Type: " .. typeStr, { 0.7, 0.7, 0.7 })
    end

    if createdItemLevel and createdItemLevel > 1 then
        addLine("Item Level: " .. tostring(createdItemLevel), { 0.7, 0.7, 0.7 })
    end

    if createdEquipLoc and createdEquipLoc ~= "" then
        local slotName = _G[createdEquipLoc] or createdEquipLoc
        addLine("Equip Slot: " .. slotName, { 0.7, 0.7, 0.7 })
    end

    if createdMinLevel and createdMinLevel > 0 then
        addLine("Required Level: " .. tostring(createdMinLevel), { 0.7, 0.7, 0.7 })
    end

    -- Caerdon status of the created item
    if caerdonCreatedItem and not caerdonCreatedItem:IsItemEmpty() then
        addSpacer()
        local caerdonCreatedType = caerdonCreatedItem:GetCaerdonItemType()
        addLine("Caerdon Type: " .. tostring(caerdonCreatedType), { 0.5, 0.8, 1 })

        local createdLocationInfo = {
            locationKey = "recipe-created-detail-" .. tostring(createdID or "unknown"),
            isDebugFrame = true
        }
        local isReady, mogStatus, bindingStatus = caerdonCreatedItem:GetCaerdonStatus(self, createdLocationInfo)
        if isReady then
            if mogStatus and mogStatus ~= "" then
                addLine("Mog Status: " .. mogStatus, { 0.7, 0.9, 0.7 })
            end
            if bindingStatus and bindingStatus ~= "" then
                addLine("Binding: " .. tostring(bindingStatus), { 0.7, 0.7, 0.7 })
            end
        end

        -- For equipment, show transmog source info
        if caerdonCreatedType == "Equipment" then
            local createdItemData = caerdonCreatedItem:GetItemData()
            if createdItemData and createdItemData.GetTransmogInfo then
                local transmogInfo = createdItemData:GetTransmogInfo()
                if transmogInfo then
                    if transmogInfo.appearanceID then
                        addLine("Appearance ID: " .. tostring(transmogInfo.appearanceID), { 0.7, 0.7, 0.7 })
                    end
                    if transmogInfo.sourceID then
                        addLine("Source ID: " .. tostring(transmogInfo.sourceID), { 0.7, 0.7, 0.7 })
                    end
                    if transmogInfo.isCollected ~= nil then
                        local collectedColor = transmogInfo.isCollected and { 0.5, 0.5, 0.5 } or { 0.3, 1, 0.3 }
                        addLine("Collected: " .. tostring(transmogInfo.isCollected), collectedColor)
                    end
                    if transmogInfo.canCollect ~= nil then
                        addLine("Can Collect: " .. tostring(transmogInfo.canCollect), { 0.7, 0.7, 0.7 })
                    end
                end
            end
        end
    end

    frame.detailsFrame:SetHeight(getHeight() + 8)
    frame:SetHeight(APPEARANCE_ITEM_COLLAPSED_HEIGHT)
    frame.detailsFrame:Hide()
    frame.isExpanded = false
    frame:Show()

    -- Hide any extra frames beyond index 1
    for index = 2, #self.recipeCreatedItemFrames do
        local extra = self.recipeCreatedItemFrames[index]
        if extra then
            if extra.itemButton then
                CaerdonWardrobe:ClearButton(extra.itemButton)
            end
            extra:Hide()
        end
    end

    self:RefreshRecipeCreatedItemLayout()
end

function DebugFrameMixin:RefreshRecipeCreatedItemLayout()
    if not self.recipeCreatedItemContainer or not self.recipeCreatedItemContainer:IsShown() then
        return
    end

    self.recipeCreatedItemContainer:ClearAllPoints()
    self.recipeCreatedItemContainer:SetPoint("TOPLEFT", self.infoFrame, "BOTTOMLEFT", 0, -10)
    self.recipeCreatedItemContainer:SetWidth(self:GetDetailSectionWidth())

    local headerHeight = 25
    local yOffset = headerHeight
    if self.recipeCreatedItemFrames then
        for _, frame in ipairs(self.recipeCreatedItemFrames) do
            if frame:IsShown() then
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", self.recipeCreatedItemContainer, "TOPLEFT", 0, -yOffset)
                frame:SetPoint("TOPRIGHT", self.recipeCreatedItemContainer, "TOPRIGHT", -15, -yOffset)
                yOffset = yOffset + frame:GetHeight() + 5
            end
        end
    end

    self.recipeCreatedItemContainer:SetHeight(math.max(yOffset, headerHeight))
    self:UpdateContentHeight()

    -- Refresh downstream containers that anchor relative to us
    if self.sharedAppearanceContainer and self.sharedAppearanceContainer:IsShown() then
        self:RefreshSharedAppearanceLayout()
    end
end

function DebugFrameMixin:RefreshAppearanceVariationLayout()
    if not self.appearanceVariationContainer or not self.appearanceVariationContainer:IsShown() then
        return
    end

    local anchor = self.sharedAppearanceContainer and self.sharedAppearanceContainer:IsShown() and
        self.sharedAppearanceContainer
        or (self.recipeCreatedItemContainer and self.recipeCreatedItemContainer:IsShown() and self.recipeCreatedItemContainer)
        or self.infoFrame
    self.appearanceVariationContainer:ClearAllPoints()
    self.appearanceVariationContainer:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
    self.appearanceVariationContainer:SetWidth(self:GetDetailSectionWidth())

    local headerHeight = 25
    local yOffset = headerHeight
    if self.appearanceVariationItemFrames then
        for _, frame in ipairs(self.appearanceVariationItemFrames) do
            if frame:IsShown() then
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", self.appearanceVariationContainer, "TOPLEFT", 0, -yOffset)
                frame:SetPoint("TOPRIGHT", self.appearanceVariationContainer, "TOPRIGHT", -15, -yOffset)
                yOffset = yOffset + frame:GetHeight() + 5
            end
        end
    end

    if self.appearanceVariationOverflowText and self.appearanceVariationOverflowText:IsShown() then
        self.appearanceVariationOverflowText:ClearAllPoints()
        self.appearanceVariationOverflowText:SetPoint("TOPLEFT", self.appearanceVariationContainer, "TOPLEFT", 8,
            -yOffset)
        yOffset = yOffset + 16
    end

    self.appearanceVariationContainer:SetHeight(math.max(yOffset, headerHeight))
    self:UpdateContentHeight()
end

function DebugFrameMixin:AddEquipmentInfo(item)
    -- Get equip location for all equipment items, not just equipped ones
    local equipLocation = item:GetEquipLocation()
    if equipLocation then
        self:AddDebugEntry("Item Equip Location", equipLocation)
    end

    -- Also show the inventory type name if available
    local inventoryTypeName = item:GetInventoryTypeName()
    if inventoryTypeName then
        self:AddDebugEntry("Inventory Type Name", inventoryTypeName)
    end

    -- Get item location info for equipped items
    local itemLocation = item:GetItemLocation()
    if itemLocation and itemLocation:HasAnyLocation() then
        if itemLocation:IsEquipmentSlot() then
            self:AddDebugEntry("Equipment Slot", tostring(itemLocation:GetEquipmentSlot()))
        end
    end

    -- Get transmog info from the equipment type
    local itemData = CaerdonEquipment:CreateFromCaerdonItem(item)

    -- Get equipment set info
    if itemData and itemData.GetEquipmentSets then
        local equipmentSets = itemData:GetEquipmentSets()
        if equipmentSets and #equipmentSets > 0 then
            self:AddDebugEntry("Equipment Sets", table.concat(equipmentSets, ", "))
        end
    end
end

function DebugFrameMixin:UpdateSharedAppearanceUI(sharedItems)
    if not self.sharedAppearanceContainer then
        self.sharedAppearanceContainer = CreateFrame("Frame", "CaerdonDebugSharedAppearanceContainer", self.content)
        self.sharedAppearanceHeader = self.sharedAppearanceContainer:CreateFontString(nil, "OVERLAY",
            "GameFontNormalLarge")
        self.sharedAppearanceHeader:SetPoint("TOPLEFT", self.sharedAppearanceContainer, "TOPLEFT", 0, 0)
        self.sharedAppearanceHeader:SetTextColor(0.5, 0.8, 1)
        self.sharedAppearanceItemFrames = {}
    end

    if not sharedItems or #sharedItems == 0 then
        self.sharedAppearanceContainer:Hide()
        if self.sharedAppearanceItemFrames then
            for _, frame in ipairs(self.sharedAppearanceItemFrames) do
                if frame.itemButton then
                    CaerdonWardrobe:ClearButton(frame.itemButton)
                end
                frame:Hide()
                if frame.detailsFrame then
                    frame.detailsFrame:Hide()
                end
            end
        end
        if self.sharedAppearanceOverflowText then
            self.sharedAppearanceOverflowText:Hide()
        end
        self:UpdateContentHeight()
        if self.ensembleContainer and self.ensembleContainer:IsShown() then
            self:RefreshEnsembleLayout()
        end
        return
    end

    self.sharedAppearanceContainer:Show()
    local headerText = string.format("Shared Appearance Items (%d)", #sharedItems)
    self.sharedAppearanceHeader:SetText(headerText)

    if not self.sharedAppearanceItemFrames then
        self.sharedAppearanceItemFrames = {}
    end

    local displayed = math.min(#sharedItems, MAX_SHARED_APPEARANCE_UI_ENTRIES)
    for index = 1, displayed do
        local data = sharedItems[index]
        local frame = self:AcquireAppearanceItemFrame(self.sharedAppearanceItemFrames, self.sharedAppearanceContainer,
            "CaerdonDebugSharedAppearanceItem", index, function()
                self:RefreshSharedAppearanceLayout()
            end)
        self:PopulateSharedAppearanceFrame(frame, data, index)
    end

    if self.sharedAppearanceItemFrames then
        for index = displayed + 1, #self.sharedAppearanceItemFrames do
            local frame = self.sharedAppearanceItemFrames[index]
            if frame then
                if frame.itemButton then
                    CaerdonWardrobe:ClearButton(frame.itemButton)
                end
                frame:Hide()
                if frame.detailsFrame then
                    frame.detailsFrame:Hide()
                end
            end
        end
    end

    if #sharedItems > displayed then
        if not self.sharedAppearanceOverflowText then
            self.sharedAppearanceOverflowText = self.sharedAppearanceContainer:CreateFontString(nil, "OVERLAY",
                "GameFontNormalSmall")
            self.sharedAppearanceOverflowText:SetTextColor(0.7, 0.7, 0.7)
        end
        self.sharedAppearanceOverflowText:SetText(string.format("...and %d more", #sharedItems - displayed))
        self.sharedAppearanceOverflowText:Show()
    elseif self.sharedAppearanceOverflowText then
        self.sharedAppearanceOverflowText:Hide()
    end

    self:RefreshSharedAppearanceLayout()
end

function DebugFrameMixin:UpdateAppearanceVariationsUI(variationItems)
    if not self.appearanceVariationContainer then
        self.appearanceVariationContainer = CreateFrame("Frame", "CaerdonDebugAppearanceVariations", self.content)
        self.appearanceVariationHeader = self.appearanceVariationContainer:CreateFontString(nil, "OVERLAY",
            "GameFontNormalLarge")
        self.appearanceVariationHeader:SetPoint("TOPLEFT", self.appearanceVariationContainer, "TOPLEFT", 0, 0)
        self.appearanceVariationHeader:SetTextColor(0.5, 0.8, 1)
        self.appearanceVariationItemFrames = {}
    end

    if not variationItems or #variationItems == 0 then
        self.appearanceVariationContainer:Hide()
        if self.appearanceVariationItemFrames then
            for _, frame in ipairs(self.appearanceVariationItemFrames) do
                if frame.itemButton then
                    CaerdonWardrobe:ClearButton(frame.itemButton)
                end
                frame:Hide()
                if frame.detailsFrame then
                    frame.detailsFrame:Hide()
                end
            end
        end
        if self.appearanceVariationOverflowText then
            self.appearanceVariationOverflowText:Hide()
        end
        self:UpdateContentHeight()
        if self.ensembleContainer and self.ensembleContainer:IsShown() then
            self:RefreshEnsembleLayout()
        end
        return
    end

    self.appearanceVariationContainer:Show()

    local headerText = string.format("Appearance Variations (%d)", #variationItems)
    self.appearanceVariationHeader:SetText(headerText)

    local displayed = math.min(#variationItems, MAX_SHARED_APPEARANCE_UI_ENTRIES)
    if not self.appearanceVariationItemFrames then
        self.appearanceVariationItemFrames = {}
    end

    for index = 1, displayed do
        local data = variationItems[index]
        local frame = self:AcquireAppearanceItemFrame(self.appearanceVariationItemFrames,
            self.appearanceVariationContainer, "CaerdonDebugAppearanceVariationItem", index, function()
                self:RefreshAppearanceVariationLayout()
            end)
        self:PopulateAppearanceVariationFrame(frame, data, index)
    end

    if self.appearanceVariationItemFrames then
        for index = displayed + 1, #self.appearanceVariationItemFrames do
            local frame = self.appearanceVariationItemFrames[index]
            if frame then
                if frame.itemButton then
                    CaerdonWardrobe:ClearButton(frame.itemButton)
                end
                frame:Hide()
                if frame.detailsFrame then
                    frame.detailsFrame:Hide()
                end
            end
        end
    end

    if #variationItems > displayed then
        if not self.appearanceVariationOverflowText then
            self.appearanceVariationOverflowText = self.appearanceVariationContainer:CreateFontString(nil, "OVERLAY",
                "GameFontNormalSmall")
            self.appearanceVariationOverflowText:SetTextColor(0.7, 0.7, 0.7)
        end
        self.appearanceVariationOverflowText:SetText(string.format("...and %d more", #variationItems - displayed))
        self.appearanceVariationOverflowText:Show()
    elseif self.appearanceVariationOverflowText then
        self.appearanceVariationOverflowText:Hide()
    end

    self:RefreshAppearanceVariationLayout()
end

function DebugFrameMixin:AddConduitInfo(item)
    local itemData = item:GetItemData()
    if not itemData then return end

    local conduitInfo = itemData:GetConduitInfo()
    if conduitInfo then
        self:AddDebugEntry("Needs Item", tostring(conduitInfo.needsItem))
        self:AddDebugEntry("Is Upgrade", tostring(conduitInfo.isUpgrade))
    end
end

function DebugFrameMixin:AddConsumableInfo(item)
    local itemData = item:GetItemData()
    if not itemData then return end

    local consumableInfo = itemData:GetConsumableInfo()
    if consumableInfo then
        self:AddDebugEntry("Needs Item", tostring(consumableInfo.needsItem))
        self:AddDebugEntry("Other Needs Item", tostring(consumableInfo.otherNeedsItem))
        self:AddDebugEntry("Own Plus Item", tostring(consumableInfo.ownPlusItem))
        self:AddDebugEntry("Low Skill Item", tostring(consumableInfo.lowSkillItem))
        self:AddDebugEntry("Low Skill Plus Item", tostring(consumableInfo.lowSkillPlusItem))
        self:AddDebugEntry("Other No Loot Item", tostring(consumableInfo.otherNoLootItem))
        self:AddDebugEntry("Valid For Character", tostring(consumableInfo.validForCharacter))
        self:AddDebugEntry("Can Equip", tostring(consumableInfo.canEquip))
        self:AddDebugEntry("Is Ensemble", tostring(consumableInfo.isEnsemble))

        -- Add detailed ensemble information if this is an ensemble
        if consumableInfo.isEnsemble then
            self:AddEnsembleInfo(item)
        end
    end
end

function DebugFrameMixin:AddHousingInfo(item)
    local itemData = item:GetItemData()
    if not itemData or not itemData.GetHousingInfo then return end

    local info = itemData:GetHousingInfo()
    if not info then return end

    self:AddDebugEntry("Entry Type", tostring(info.entryType))
    self:AddDebugEntry("Record ID", tostring(info.recordID))
    self:AddDebugEntry("Subclass ID", tostring(info.subClassID))
    self:AddDebugEntry("Owned Stored", tostring(info.ownedStored))
    self:AddDebugEntry("Remaining Redeemable", info.entryInfo and tostring(info.entryInfo.remainingRedeemable) or "nil")
    self:AddDebugEntry("Placed Count", tostring(info.placedCount))
    self:AddDebugEntry("Bag Count", tostring(info.bagCount))
    self:AddDebugEntry("Total Owned", tostring(info.totalOwned))
    self:AddDebugEntry("First Acquisition Bonus", tostring(info.firstAcquisitionBonus))
    self:AddDebugEntry("Show Quantity", tostring(info.showQuantity))
    self:AddDebugEntry("Max Stack", tostring(info.maxStack))
    self:AddDebugEntry("Icon Atlas", tostring(info.iconAtlas))
    self:AddDebugEntry("Icon Texture", tostring(info.iconTexture))
    self:AddDebugEntry("Source Text", tostring(info.sourceText))
end

function DebugFrameMixin:AddEnsembleInfo(item)
    local itemLink = item:GetItemLink()
    if not itemLink then return end

    local transmogSetID = C_Item.GetItemLearnTransmogSet(itemLink)
    if not transmogSetID then return end
    self.currentEnsembleSetID = transmogSetID
    self.currentEnsembleSetInfo = nil
    self.currentEnsembleClassCandidates = nil

    -- Add ensemble header section
    local transmogSetInfo = C_TransmogSets.GetSetInfo(transmogSetID)
    self.currentEnsembleData = {
        setID = transmogSetID
    }

    if transmogSetInfo then
        self.currentEnsembleSetInfo = transmogSetInfo
        self.currentEnsembleClassCandidates = self:GetClassCandidatesForSet(transmogSetInfo)
        self.currentEnsembleData.setInfo = CopyTable(transmogSetInfo)
        if self.currentEnsembleClassCandidates then
            self.currentEnsembleData.classCandidates = CopyTable(self.currentEnsembleClassCandidates)
        end
        self:AddDebugEntry("Set Name", transmogSetInfo.name or "Unknown")
        self:AddDebugEntry("Set ID", tostring(transmogSetID))
        self:AddDebugEntry("Set Collected", tostring(transmogSetInfo.collected))
        self:AddDebugEntry("Set Valid For Character", tostring(transmogSetInfo.validForCharacter))

        if transmogSetInfo.classMask then
            self:AddDebugEntry("Set Class Mask", tostring(transmogSetInfo.classMask))
        end
    end

    -- Get all sources in the ensemble
    local sourceIDs = C_TransmogSets.GetAllSourceIDs(transmogSetID)
    if not sourceIDs or #sourceIDs == 0 then
        if self.currentEnsembleData then
            self.currentEnsembleData.totalSources = 0
            self.currentEnsembleData.sourceIDs = {}
            self.currentEnsembleData.items = {}
        end
        return
    end

    if self.currentEnsembleData then
        self.currentEnsembleData.totalSources = #sourceIDs
        self.currentEnsembleData.sourceIDs = CopyTable(sourceIDs)
    end
    self:AddDebugEntry("Total Sources", tostring(#sourceIDs))

    -- Track unique items (multiple sources can have same itemID)
    local processedItems = {}
    local itemDetails = {}

    -- Collect all item information
    for _, sourceID in ipairs(sourceIDs) do
        local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
        if sourceInfo and sourceInfo.itemID then
            if not processedItems[sourceInfo.itemID] then
                processedItems[sourceInfo.itemID] = true

                local itemInfo = {
                    itemID = sourceInfo.itemID,
                    sources = {}
                }

                -- Get item details
                local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType,
                itemStackCount, itemEquipLoc, icon, sellPrice, classID, subclassID =
                    C_Item.GetItemInfo(sourceInfo.itemID)

                itemInfo.itemName = itemName or ("Item " .. sourceInfo.itemID)
                itemInfo.itemLink = itemLink
                itemInfo.itemQuality = itemQuality
                itemInfo.icon = icon
                itemInfo.itemMinLevel = itemMinLevel
                itemInfo.itemType = itemType
                itemInfo.itemSubType = itemSubType
                itemInfo.classID = classID
                itemInfo.subclassID = subclassID
                itemInfo.itemEquipLoc = itemEquipLoc

                table.insert(itemDetails, itemInfo)
            end
        end
    end

    -- Now collect source information for each item
    local sourceSummary = {
        uncollectedSources = 0,
        uncollectedAppearanceSources = 0,
        uncollectedDuplicateSources = 0,
        uncollectedLegendaryDuplicateSources = 0,
        uncollectedKnownViaAltSources = 0
    }

    for _, itemInfo in ipairs(itemDetails) do
        for _, sourceID in ipairs(sourceIDs) do
            local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
            if sourceInfo and sourceInfo.itemID == itemInfo.itemID then
                local hasItemData, canCollect = C_TransmogCollection.PlayerCanCollectSource(sourceID)
                local accountHasItemData, accountCanCollect = C_TransmogCollection.AccountCanCollectSource(sourceID)
                local appearanceInfo = C_TransmogCollection.GetAppearanceInfoBySource(sourceID)
                local appearanceID = appearanceInfo and appearanceInfo.appearanceID
                local appearanceIsCollected = appearanceInfo and appearanceInfo.appearanceIsCollected
                local isLegendary = sourceInfo.quality == Enum.ItemQuality.Legendary
                local legendaryHasAltCollected = false
                local appearanceHasAltCollected = false

                if appearanceID then
                    local appearanceSources = C_TransmogCollection.GetAppearanceSources(appearanceID, sourceInfo.categoryID)
                    if appearanceSources then
                        for _, appearanceSourceInfo in ipairs(appearanceSources) do
                            if appearanceSourceInfo.sourceID ~= sourceID and appearanceSourceInfo.isCollected then
                                appearanceHasAltCollected = true
                                if isLegendary then
                                    legendaryHasAltCollected = true
                                end
                                break
                            end
                        end
                    end
                end

                local sourceDetail = {
                    sourceID = sourceID,
                    visualID = sourceInfo.visualID,
                    isCollected = sourceInfo.isCollected,
                    isValidSourceForPlayer = sourceInfo.isValidSourceForPlayer,
                    playerCanCollect = sourceInfo.playerCanCollect,
                    useErrorType = sourceInfo.useErrorType,
                    hasItemDataAPI = hasItemData,
                    canCollectAPI = canCollect,
                    itemModID = sourceInfo.itemModID,
                    invType = sourceInfo.invType,
                    categoryID = sourceInfo.categoryID,
                    sourceType = sourceInfo.sourceType,
                    useError = sourceInfo.useError,
                    canDisplayOnPlayer = sourceInfo.canDisplayOnPlayer,
                    meetsTransmogPlayerCondition = sourceInfo.meetsTransmogPlayerCondition,
                    isHideVisual = sourceInfo.isHideVisual,
                    name = sourceInfo.name,
                    quality = sourceInfo.quality,
                    accountHasItemDataAPI = accountHasItemData,
                    accountCanCollectAPI = accountCanCollect,
                    appearanceInfo = appearanceInfo and CopyTable(appearanceInfo) or nil,
                    hasAlternateCollected = legendaryHasAltCollected or appearanceHasAltCollected,
                    appearanceHasAltCollected = appearanceHasAltCollected
                }

                table.insert(itemInfo.sources, sourceDetail)

                if not sourceInfo.isCollected then
                    sourceSummary.uncollectedSources = sourceSummary.uncollectedSources + 1

                    if isLegendary and (appearanceIsCollected or legendaryHasAltCollected) then
                        sourceSummary.uncollectedLegendaryDuplicateSources = sourceSummary.uncollectedLegendaryDuplicateSources + 1
                    elseif appearanceIsCollected then
                        sourceSummary.uncollectedDuplicateSources = sourceSummary.uncollectedDuplicateSources + 1
                    elseif appearanceHasAltCollected then
                        sourceSummary.uncollectedKnownViaAltSources = sourceSummary.uncollectedKnownViaAltSources + 1
                    else
                        sourceSummary.uncollectedAppearanceSources = sourceSummary.uncollectedAppearanceSources + 1
                    end
                end
            end
        end
    end

    if self.currentEnsembleData then
        self.currentEnsembleData.items = itemDetails
        self.currentEnsembleData.totalItems = #itemDetails
        self.currentEnsembleData.sourceSummary = sourceSummary
    end

    -- Create an ensemble items container if it doesn't exist
    if not self.ensembleContainer then
        self.ensembleContainer = CreateFrame("Frame", "CaerdonDebugEnsembleContainer", self.content)
        self.ensembleItemFrames = {}

        -- Create header for ensemble section
        self.ensembleHeader = self.ensembleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        self.ensembleHeader:SetPoint("TOPLEFT", self.ensembleContainer, "TOPLEFT", 0, 0)
        self.ensembleHeader:SetText("Ensemble Items")
        self.ensembleHeader:SetTextColor(1, 0.82, 0) -- Gold color
    end

    -- Update container position and width to match content area
    self.ensembleContainer:ClearAllPoints()
    local ensembleAnchor = self.appearanceVariationContainer and self.appearanceVariationContainer:IsShown() and
        self.appearanceVariationContainer
        or (self.sharedAppearanceContainer and self.sharedAppearanceContainer:IsShown() and self.sharedAppearanceContainer)
        or (self.recipeCreatedItemContainer and self.recipeCreatedItemContainer:IsShown() and self.recipeCreatedItemContainer)
        or self.infoFrame
    self.ensembleContainer:SetPoint("TOPLEFT", ensembleAnchor, "BOTTOMLEFT", 0, -10)
    self.ensembleContainer:SetPoint("TOPRIGHT", ensembleAnchor, "BOTTOMRIGHT", 0, -10)

    -- Clear existing ensemble item frames
    for _, frame in ipairs(self.ensembleItemFrames) do
        -- Clear Caerdon overlay before hiding
        if frame.itemButton then
            CaerdonWardrobe:ClearButton(frame.itemButton)
        end
        frame:Hide()
        frame:ClearAllPoints()
    end
    wipe(self.ensembleItemFrames)

    -- Create item frames for each item
    local headerHeight = 25 -- Height for the "Ensemble Items" header
    local yOffset = headerHeight
    for index, itemInfo in ipairs(itemDetails) do
        local itemFrame = self:CreateEnsembleItemFrame(index, itemInfo)

        if index == 1 then
            -- Position first frame below the header
            itemFrame:SetPoint("TOPLEFT", self.ensembleContainer, "TOPLEFT", 0, -headerHeight)
        else
            itemFrame:SetPoint("TOPLEFT", self.ensembleItemFrames[index - 1], "BOTTOMLEFT", 0, -5)
        end

        table.insert(self.ensembleItemFrames, itemFrame)
        yOffset = yOffset + itemFrame:GetHeight() + 5
    end

    -- Update container height (include header height)
    self.ensembleContainer:SetHeight(math.max(yOffset, headerHeight))
    self.ensembleContainer:Show()
    self:UpdateContentHeight()
end

function DebugFrameMixin:GetClassCandidatesForSet(setInfo)
    local candidates = {}
    local playerClassID = select(3, UnitClass("player"))

    if setInfo and setInfo.classMask and setInfo.classMask ~= 0 then
        local playerBit = bit.lshift(1, playerClassID - 1)
        if bit.band(setInfo.classMask, playerBit) ~= 0 then
            table.insert(candidates, playerClassID)
        end

        for classID = 1, GetNumClasses() do
            if classID ~= playerClassID then
                local classBit = bit.lshift(1, classID - 1)
                if bit.band(setInfo.classMask, classBit) ~= 0 then
                    table.insert(candidates, classID)
                end
            end
        end
    else
        table.insert(candidates, playerClassID)
    end

    if #candidates == 0 then
        table.insert(candidates, playerClassID)
    end

    return candidates
end

function DebugFrameMixin:SelectWardrobeSet(setID)
    if not (WardrobeCollectionFrame and WardrobeCollectionFrame.SetsCollectionFrame) then
        return false
    end

    local setsFrame = WardrobeCollectionFrame.SetsCollectionFrame
    if not setsFrame.SelectSet then
        return false
    end

    setsFrame:SelectSet(setID)

    if setsFrame.ScrollToSet then
        local alignment = ScrollBoxConstants and ScrollBoxConstants.AlignCenter or nil
        setsFrame:ScrollToSet(setID, alignment)
    end

    return true
end

function DebugFrameMixin:TryOpenCurrentEnsembleInWardrobe()
    local setID = self.currentEnsembleSetID
    if not setID then
        return false
    end

    if not CollectionsJournal then
        if CollectionsJournal_LoadUI then
            CollectionsJournal_LoadUI()
        else
            UIParentLoadAddOn("Blizzard_Collections")
        end
    end

    if not CollectionsJournal then
        return false
    end

    ShowUIPanel(CollectionsJournal)

    if CollectionsJournal_SetTab then
        CollectionsJournal_SetTab(CollectionsJournal, 5)
    end

    if not WardrobeCollectionFrame then
        return false
    end

    if WardrobeCollectionFrame.SetTab then
        WardrobeCollectionFrame:SetTab(WARDROBE_TAB_SETS)
    end

    local setInfo = self.currentEnsembleSetInfo or C_TransmogSets.GetSetInfo(setID)
    if setInfo then
        self.currentEnsembleSetInfo = setInfo
    end

    local classCandidates = self.currentEnsembleClassCandidates
    if not classCandidates or #classCandidates == 0 then
        classCandidates = self:GetClassCandidatesForSet(setInfo)
        self.currentEnsembleClassCandidates = classCandidates
    end

    if not classCandidates or #classCandidates == 0 then
        return false
    end

    local function AttemptClass(index)
        if index > #classCandidates then
            return
        end

        local classID = classCandidates[index]
        if classID then
            C_TransmogSets.SetTransmogSetsClassFilter(classID)
            if WardrobeCollectionFrame.ClassDropdown and WardrobeCollectionFrame.ClassDropdown.Refresh then
                WardrobeCollectionFrame.ClassDropdown:Refresh()
            end
        end

        C_Timer.After(0.1, function()
            if C_TransmogSets.IsSetVisible and not C_TransmogSets.IsSetVisible(setID) and index < #classCandidates then
                AttemptClass(index + 1)
                return
            end

            local attempts = 0
            local function TrySelect()
                attempts = attempts + 1
                if not self:SelectWardrobeSet(setID) and attempts < 3 then
                    C_Timer.After(0.1, TrySelect)
                end
            end
            TrySelect()
        end)
    end

    AttemptClass(1)

    return true
end

function DebugFrameMixin:GetRequiredClassForSource(appearanceID, sourceID, categoryID, transmogLocation, sourceInfo)
    local playerClassID = select(3, UnitClass("player"))

    if sourceInfo and sourceInfo.isValidSourceForPlayer then
        return playerClassID
    end

    for classID = 1, GetNumClasses() do
        local sources = C_TransmogCollection.GetValidAppearanceSourcesForClass(appearanceID, classID, categoryID,
            transmogLocation)
        if sources and #sources > 0 then
            for _, source in ipairs(sources) do
                if source.sourceID == sourceID then
                    return classID
                end
            end
        end
    end

    return playerClassID
end

function DebugFrameMixin:GetTransmogUseErrorTypeName(errorType)
    if not errorType then
        return "None"
    end

    return TRANSMOG_USE_ERROR_LABELS[errorType] or tostring(errorType)
end

function DebugFrameMixin:OpenAppearanceSourceInWardrobe(appearanceID, sourceID, sourceInfo, categoryID, transmogLocation)
    if not appearanceID or not sourceID or not transmogLocation then
        return
    end

    if not CollectionsJournal then
        if CollectionsJournal_LoadUI then
            CollectionsJournal_LoadUI()
        else
            UIParentLoadAddOn("Blizzard_Collections")
        end
    end

    if not CollectionsJournal then
        return
    end

    ShowUIPanel(CollectionsJournal)

    if CollectionsJournal_SetTab then
        CollectionsJournal_SetTab(CollectionsJournal, 5)
    end

    local requiredClassID = self:GetRequiredClassForSource(appearanceID, sourceID, categoryID, transmogLocation,
        sourceInfo)

    C_Timer.After(0.3, function()
        if not WardrobeCollectionFrame then
            return
        end

        if WardrobeCollectionFrame.SetTab then
            WardrobeCollectionFrame:SetTab(WARDROBE_TAB_ITEMS)
        end

        local itemsFrame = WardrobeCollectionFrame.ItemsCollectionFrame
        if not itemsFrame then
            return
        end

        if requiredClassID then
            C_TransmogCollection.SetClassFilter(requiredClassID)
            if WardrobeCollectionFrame.ClassDropdown and WardrobeCollectionFrame.ClassDropdown.Refresh then
                WardrobeCollectionFrame.ClassDropdown:Refresh()
            end
        end

        if itemsFrame.GoToSourceID then
            itemsFrame:GoToSourceID(sourceID, transmogLocation, true, false, categoryID)

            if sourceInfo and sourceInfo.itemID then
                C_Timer.After(0.1, function()
                    local itemName = C_Item.GetItemNameByID(sourceInfo.itemID)
                    if itemName then
                        SetWardrobeCollectionSearchText(itemName)
                    end
                end)
            end
        end
    end)
end

function DebugFrameMixin:HandleAppearanceLink(link)
    if not link then
        return
    end

    local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(link)
    if not (appearanceID and sourceID) then
        return
    end

    local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
    if not (sourceInfo and sourceInfo.invType) then
        return
    end

    local slotID = C_Transmog.GetSlotForInventoryType(sourceInfo.invType)
    if not slotID then
        return
    end

    local appearanceSourceInfo = CaerdonAPI and CaerdonAPI.GetAppearanceSourceInfo and
        CaerdonAPI:GetAppearanceSourceInfo(sourceID)
    local categoryID = appearanceSourceInfo and appearanceSourceInfo.categoryID
    local transmogLocation = TransmogUtil.GetTransmogLocation(slotID, Enum.TransmogType.Appearance,
        Enum.TransmogModification.Main)

    self:OpenAppearanceSourceInWardrobe(appearanceID, sourceID, sourceInfo, categoryID, transmogLocation)
end

function DebugFrameMixin:CreateEnsembleItemFrame(index, itemInfo)
    local frameName = "CaerdonDebugEnsembleItem" .. index
    local frame = _G[frameName] or CreateFrame("Frame", frameName, self.ensembleContainer, "BackdropTemplate")

    frame:SetHeight(100) -- Will adjust based on content
    -- Use anchors to ensure width updates on resize
    -- Add padding on right to account for backdrop border (edgeSize=12) and prevent clipping
    frame:ClearAllPoints()
    frame:SetPoint("LEFT", self.ensembleContainer, "LEFT", 0, 0)
    frame:SetPoint("RIGHT", self.ensembleContainer, "RIGHT", -15, 0)

    -- Set up backdrop for visual separation
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.8)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    -- Store default colors for hover effect
    frame.defaultBgColor = { 0.05, 0.05, 0.05, 0.8 }
    frame.defaultBorderColor = { 0.3, 0.3, 0.3, 1 }
    frame.hoverBgColor = { 0.1, 0.1, 0.15, 0.9 }
    frame.hoverBorderColor = { 0.5, 0.5, 0.6, 1 }

    -- Create item button
    if not frame.itemButton then
        frame.itemButton = CreateFrame("ItemButton", frameName .. "Button", frame)
        frame.itemButton:SetSize(40, 40)
        frame.itemButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
        frame.itemButton:RegisterForDrag("LeftButton")

        -- Set up item button scripts
        frame.itemButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.itemLink then
                GameTooltip:SetHyperlink(self.itemLink)
            elseif self.itemID then
                GameTooltip:SetItemByID(self.itemID)
            end
            GameTooltip:Show()
        end)

        frame.itemButton:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)

        frame.itemButton:SetScript("OnClick", function(self, button)
            if self.itemLink then
                -- Handle all modified clicks (ctrl for dressing room, shift for chat link, etc.)
                if IsModifiedClick() then
                    HandleModifiedItemClick(self.itemLink)
                end
            end
        end)

        frame.itemButton:SetScript("OnDragStart", function(self)
            if self.itemLink then
                -- Put the item on the cursor using the same method as the main debug frame
                C_Item.PickupItem(self.itemLink)
            end
        end)

        frame.itemButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end

    -- Update item button
    frame.itemButton.itemID = itemInfo.itemID
    frame.itemButton.itemLink = itemInfo.itemLink

    if itemInfo.icon then
        frame.itemButton.icon:SetTexture(itemInfo.icon)
        frame.itemButton.icon:Show()
    end

    -- Set quality border if available
    if itemInfo.itemQuality and frame.itemButton.IconBorder then
        local r, g, b = C_Item.GetItemQualityColor(itemInfo.itemQuality)
        frame.itemButton.IconBorder:SetVertexColor(r, g, b)
        frame.itemButton.IconBorder:Show()
    end

    -- Add Caerdon overlay to show collection status
    if itemInfo.itemLink then
        local item = CaerdonItem:CreateFromItemLink(itemInfo.itemLink)
        if item then
            local options = {
                statusProminentSize = 20,
                bindingScale = 1.0
            }

            local locKey = "ensemble-item-" .. itemInfo.itemID .. "-" .. index

            -- Update button with Caerdon system - use isEnsembleItem flag instead of isDebugFrame
            CaerdonWardrobe:UpdateButton(frame.itemButton, item, self, {
                locationKey = locKey,
                isEnsembleItem = true
            }, options)
        end
    end

    -- Create or update item name label
    if not frame.itemNameText then
        frame.itemNameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.itemNameText:SetPoint("TOPLEFT", frame.itemButton, "TOPRIGHT", 8, 0)
        frame.itemNameText:SetJustifyH("LEFT")
        frame.itemNameText:SetWordWrap(false)
        frame.itemNameText:SetWidth(0) -- Will auto-size to text
    end

    if itemInfo.itemLink then
        frame.itemNameText:SetText(itemInfo.itemLink)
    else
        frame.itemNameText:SetText(itemInfo.itemName or ("Item " .. itemInfo.itemID))
    end

    -- Make the item name clickable for item links (like chat links)
    -- Button should only cover the text, not the entire line
    if not frame.itemNameButton then
        frame.itemNameButton = CreateFrame("Button", nil, frame)
        frame.itemNameButton:SetScript("OnClick", function(button)
            local link = button.itemLink
            if not link then
                return
            end

            if IsModifiedClick("CHATLINK") then
                ChatEdit_InsertLink(link)
                return
            end

            if IsControlKeyDown() then
                self:HandleAppearanceLink(link)
                return
            end

            if ItemRefTooltip:IsShown() and ItemRefTooltip.itemLink == link then
                ItemRefTooltip:Hide()
            else
                ShowUIPanel(ItemRefTooltip)
                if not ItemRefTooltip:IsShown() then
                    ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE")
                end
                ItemRefTooltip:SetHyperlink(link)
                ItemRefTooltip.itemLink = link
            end
        end)
    end

    -- Size button to match text width only
    frame.itemNameButton:ClearAllPoints()
    frame.itemNameButton:SetPoint("TOPLEFT", frame.itemNameText, "TOPLEFT", 0, 0)
    frame.itemNameButton:SetPoint("BOTTOMRIGHT", frame.itemNameText, "BOTTOMRIGHT", 0, 0)
    frame.itemNameButton.itemLink = itemInfo.itemLink

    -- Create or update item ID label
    if not frame.itemIDText then
        frame.itemIDText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame.itemIDText:SetPoint("TOPLEFT", frame.itemNameText, "BOTTOMLEFT", 0, -2)
        frame.itemIDText:SetJustifyH("LEFT")
        frame.itemIDText:SetTextColor(0.7, 0.7, 0.7)
    end
    frame.itemIDText:SetText("Item ID: " .. itemInfo.itemID)

    -- Create or update item type info
    if not frame.itemTypeText then
        frame.itemTypeText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame.itemTypeText:SetPoint("TOPLEFT", frame.itemIDText, "BOTTOMLEFT", 0, -2)
        frame.itemTypeText:SetJustifyH("LEFT")
        frame.itemTypeText:SetTextColor(0.7, 0.7, 0.7)
    end

    local typeInfo = ""
    if itemInfo.itemType then
        typeInfo = itemInfo.itemType
        if itemInfo.itemSubType then
            typeInfo = typeInfo .. " - " .. itemInfo.itemSubType
        end
    end
    if itemInfo.itemEquipLoc then
        typeInfo = typeInfo .. " (" .. itemInfo.itemEquipLoc .. ")"
    end
    frame.itemTypeText:SetText(typeInfo)

    -- Create expand/collapse button
    if not frame.expandButton then
        frame.expandButton = CreateFrame("Button", nil, frame)
        frame.expandButton:SetSize(20, 20)
        frame.expandButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
        frame.expandButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
        frame.expandButton:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
        frame.expandButton:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")

        frame.expandButton:SetScript("OnClick", function(self)
            local parent = self:GetParent()
            if parent.detailsFrame:IsShown() then
                parent.detailsFrame:Hide()
                self:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
                self:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
                parent:SetHeight(60)
            else
                parent.detailsFrame:Show()
                self:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
                self:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
                local detailsHeight = parent.detailsFrame:GetHeight()
                parent:SetHeight(60 + detailsHeight + 5)
            end

            -- Refresh layout after expanding/collapsing
            local debugFrame = self:GetParent():GetParent():GetParent():GetParent()
            if debugFrame.RefreshEnsembleLayout then
                debugFrame:RefreshEnsembleLayout()
            end
        end)
    end

    -- Create details frame for source information
    if not frame.detailsFrame then
        frame.detailsFrame = CreateFrame("Frame", nil, frame)
        frame.detailsFrame:SetPoint("TOPLEFT", frame.itemButton, "BOTTOMLEFT", 0, -5)
        frame.detailsFrame:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
        frame.detailsFrame:Hide() -- Collapsed by default
    end

    -- Clear existing detail texts and buttons
    if frame.detailTexts then
        for _, element in ipairs(frame.detailTexts) do
            -- Element could be a font string or a button
            if element.SetText then
                -- It's a font string
                element:SetText("")
                element:Hide()
                element:ClearAllPoints()
            elseif element.SetScript then
                -- It's a button
                element:SetScript("OnClick", nil)
                element:Hide()
                element:ClearAllPoints()
            end
        end
        wipe(frame.detailTexts)
    else
        frame.detailTexts = {}
    end

    -- Add source information
    local detailY = 0
    local lineHeight = 16

    -- Header for sources
    local sourceHeader = frame.detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sourceHeader:SetPoint("TOPLEFT", frame.detailsFrame, "TOPLEFT", 8, -detailY)
    sourceHeader:SetText(format("Sources (%d):", #itemInfo.sources))
    sourceHeader:SetTextColor(1, 0.82, 0)
    table.insert(frame.detailTexts, sourceHeader)
    detailY = detailY + lineHeight

    for sourceIndex, source in ipairs(itemInfo.sources) do
        -- Source ID and collection status
        local statusText = source.isCollected and "|cff00ff00Collected|r" or "|cffff0000Uncollected|r"
        local sourceText = frame.detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sourceText:SetPoint("TOPLEFT", frame.detailsFrame, "TOPLEFT", 16, -detailY)
        sourceText:SetText(format("Source %d (ID: %d) - %s", sourceIndex, source.sourceID, statusText))
        sourceText:SetTextColor(0.9, 0.9, 0.9)
        sourceText:SetJustifyH("LEFT")
        table.insert(frame.detailTexts, sourceText)
        detailY = detailY + lineHeight

        -- Visual/Appearance ID
        local visualText = frame.detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        visualText:SetPoint("TOPLEFT", frame.detailsFrame, "TOPLEFT", 24, -detailY)
        visualText:SetText(format("Visual ID: %d | Item Mod: %d", source.visualID or 0, source.itemModID or 0))
        visualText:SetTextColor(0.7, 0.7, 0.7)
        visualText:SetJustifyH("LEFT")
        table.insert(frame.detailTexts, visualText)
        detailY = detailY + lineHeight

        -- Player eligibility
        local eligText = frame.detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        eligText:SetPoint("TOPLEFT", frame.detailsFrame, "TOPLEFT", 24, -detailY)
        local eligInfo = format("Valid: %s | CanCollect: %s | API CanCollect: %s",
            tostring(source.isValidSourceForPlayer),
            tostring(source.playerCanCollect),
            source.hasItemDataAPI and tostring(source.canCollectAPI) or "pending")
        eligText:SetText(eligInfo)
        eligText:SetTextColor(0.7, 0.7, 0.7)
        eligText:SetJustifyH("LEFT")
        table.insert(frame.detailTexts, eligText)
        detailY = detailY + lineHeight

        -- Use error type (restriction type)
        if source.useErrorType then
            local errorTypeText = frame.detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            errorTypeText:SetPoint("TOPLEFT", frame.detailsFrame, "TOPLEFT", 24, -detailY)
            local errorTypeName = "Unknown"
            local errorColor = { 0.7, 0.7, 0.7 }

            if source.useErrorType == 7 then
                errorTypeName = "Class Restriction"
                errorColor = { 1, 0.3, 0.3 }
            elseif source.useErrorType == 8 then
                errorTypeName = "Race Restriction"
                errorColor = { 1, 0.3, 0.3 }
            elseif source.useErrorType == 9 then
                errorTypeName = "Faction Restriction"
                errorColor = { 1, 0.3, 0.3 }
            elseif source.useErrorType == 10 then
                errorTypeName = "Armor Type Restriction"
                errorColor = { 1, 0.82, 0 }
            end

            errorTypeText:SetText(format("useErrorType: %d (%s)", source.useErrorType, errorTypeName))
            errorTypeText:SetTextColor(errorColor[1], errorColor[2], errorColor[3])
            errorTypeText:SetJustifyH("LEFT")
            table.insert(frame.detailTexts, errorTypeText)
            detailY = detailY + lineHeight
        end

        -- Add spacing between sources
        if sourceIndex < #itemInfo.sources then
            detailY = detailY + 4
        end
    end

    -- Add section for items sharing the same appearance
    if itemInfo.sources and #itemInfo.sources > 0 then
        detailY = detailY + 8 -- Extra spacing before new section

        -- Get all sources for the first appearance (they should all share the same appearance)
        local firstSource = itemInfo.sources[1]
        if firstSource and firstSource.visualID then
            local allSources = C_TransmogCollection.GetAllAppearanceSources(firstSource.visualID)

            if allSources and #allSources > 0 then
                -- Build a list of unique item IDs that share this appearance (excluding current item)
                local sharedItems = {}
                local seenItems = {}

                for _, sourceID in ipairs(allSources) do
                    local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
                    if sourceInfo and sourceInfo.itemID and sourceInfo.itemID ~= itemInfo.itemID then
                        if not seenItems[sourceInfo.itemID] then
                            seenItems[sourceInfo.itemID] = true
                            local itemName, itemLink = C_Item.GetItemInfo(sourceInfo.itemID)
                            if itemLink then
                                table.insert(sharedItems, {
                                    itemID = sourceInfo.itemID,
                                    itemLink = itemLink,
                                    itemName = itemName or ("Item " .. sourceInfo.itemID)
                                })
                            end
                        end
                    end
                end

                -- Only show section if there are other items with same appearance
                if #sharedItems > 0 then
                    local sharedHeader = frame.detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    sharedHeader:SetPoint("TOPLEFT", frame.detailsFrame, "TOPLEFT", 8, -detailY)
                    sharedHeader:SetText(format("Items Sharing Same Appearance (%d):", #sharedItems))
                    sharedHeader:SetTextColor(0.5, 0.8, 1) -- Light blue color
                    table.insert(frame.detailTexts, sharedHeader)
                    detailY = detailY + lineHeight

                    -- List up to 10 items
                    local maxToShow = math.min(#sharedItems, 10)
                    for i = 1, maxToShow do
                        local sharedItem = sharedItems[i]
                        local itemText = frame.detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        itemText:SetPoint("TOPLEFT", frame.detailsFrame, "TOPLEFT", 16, -detailY)
                        itemText:SetText(sharedItem.itemLink)
                        itemText:SetJustifyH("LEFT")
                        itemText:SetWidth(0) -- Auto-size to text
                        table.insert(frame.detailTexts, itemText)

                        -- Create clickable button over the item link text
                        local itemButton = CreateFrame("Button", nil, frame.detailsFrame)
                        itemButton:SetPoint("TOPLEFT", itemText, "TOPLEFT", 0, 0)
                        itemButton:SetPoint("BOTTOMRIGHT", itemText, "BOTTOMRIGHT", 0, 0)
                        itemButton.itemLink = sharedItem.itemLink
                        itemButton:SetScript("OnClick", function(button)
                            local link = button.itemLink
                            if not link then
                                return
                            end

                            if IsModifiedClick("CHATLINK") then
                                ChatEdit_InsertLink(link)
                                return
                            end

                            if IsControlKeyDown() then
                                self:HandleAppearanceLink(link)
                                return
                            end

                            if ItemRefTooltip:IsShown() and ItemRefTooltip.itemLink == link then
                                ItemRefTooltip:Hide()
                            else
                                ShowUIPanel(ItemRefTooltip)
                                if not ItemRefTooltip:IsShown() then
                                    ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE")
                                end
                                ItemRefTooltip:SetHyperlink(link)
                                ItemRefTooltip.itemLink = link
                            end
                        end)
                        table.insert(frame.detailTexts, itemButton)

                        detailY = detailY + lineHeight
                    end

                    -- Show count if there are more
                    if #sharedItems > maxToShow then
                        local moreText = frame.detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        moreText:SetPoint("TOPLEFT", frame.detailsFrame, "TOPLEFT", 16, -detailY)
                        moreText:SetText(format("... and %d more", #sharedItems - maxToShow))
                        moreText:SetTextColor(0.7, 0.7, 0.7)
                        moreText:SetJustifyH("LEFT")
                        table.insert(frame.detailTexts, moreText)
                        detailY = detailY + lineHeight
                    end
                end
            end
        end
    end

    frame.detailsFrame:SetHeight(detailY + 8)

    -- Always start collapsed when creating/updating the frame
    frame.detailsFrame:Hide()
    frame:SetHeight(60) -- Collapsed height

    -- Update expand button to show collapsed state
    if frame.expandButton then
        frame.expandButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
        frame.expandButton:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
    end

    -- Make the frame interactive with hover and click
    frame:EnableMouse(true)

    -- Add hover effect
    frame:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(self.hoverBgColor))
        self:SetBackdropBorderColor(unpack(self.hoverBorderColor))
    end)

    frame:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(self.defaultBgColor))
        self:SetBackdropBorderColor(unpack(self.defaultBorderColor))
    end)

    -- Make entire frame clickable to expand/collapse (excluding item button and item name button)
    frame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            -- Check if we clicked on the item button or item name button by checking mouse focus
            -- GetMouseFoci returns a table in modern WoW
            local foci = GetMouseFoci and GetMouseFoci() or {}
            local clickedButton = false
            for _, focus in ipairs(foci) do
                if focus == self.itemButton or focus == self.itemNameButton then
                    clickedButton = true
                    break
                end
            end

            if clickedButton then
                return -- Let those buttons handle the click
            end

            -- Toggle expand/collapse
            if self.detailsFrame:IsShown() then
                self.detailsFrame:Hide()
                self.expandButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
                self.expandButton:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
                self:SetHeight(60)
            else
                self.detailsFrame:Show()
                self.expandButton:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
                self.expandButton:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
                local detailsHeight = self.detailsFrame:GetHeight()
                self:SetHeight(60 + detailsHeight + 5)
            end

            -- Refresh layout after expanding/collapsing
            local debugFrame = self:GetParent():GetParent():GetParent()
            if debugFrame.RefreshEnsembleLayout then
                debugFrame:RefreshEnsembleLayout()
            end
        end
    end)

    frame:Show()

    return frame
end

function DebugFrameMixin:RefreshEnsembleLayout()
    if not self.ensembleContainer or not self.ensembleContainer:IsShown() then
        return
    end

    self.ensembleContainer:ClearAllPoints()
    local ensembleAnchor = (self.appearanceVariationContainer and self.appearanceVariationContainer:IsShown() and
        self.appearanceVariationContainer) or
        (self.sharedAppearanceContainer and self.sharedAppearanceContainer:IsShown() and self.sharedAppearanceContainer) or
        (self.recipeCreatedItemContainer and self.recipeCreatedItemContainer:IsShown() and self.recipeCreatedItemContainer) or
        self.infoFrame
    self.ensembleContainer:SetPoint("TOPLEFT", ensembleAnchor, "BOTTOMLEFT", 0, -10)
    self.ensembleContainer:SetWidth(self:GetDetailSectionWidth())

    -- Recalculate positions and heights
    local headerHeight = 25
    local yOffset = headerHeight
    for index, itemFrame in ipairs(self.ensembleItemFrames) do
        if index == 1 then
            itemFrame:SetPoint("TOPLEFT", self.ensembleContainer, "TOPLEFT", 0, -headerHeight)
        else
            itemFrame:SetPoint("TOPLEFT", self.ensembleItemFrames[index - 1], "BOTTOMLEFT", 0, -5)
        end
        yOffset = yOffset + itemFrame:GetHeight() + 5
    end

    self.ensembleContainer:SetHeight(math.max(yOffset, headerHeight))
    self:UpdateContentHeight()
end

function DebugFrameMixin:AddCurrencyInfo(item)
    local itemData = item:GetItemData()
    if not itemData then return end

    local currencyInfo = itemData:GetCurrencyInfo()
    if currencyInfo then
        self:AddDebugEntry("Needs Item", tostring(currencyInfo.needsItem))
        self:AddDebugEntry("Other Needs Item", tostring(currencyInfo.otherNeedsItem))

        if currencyInfo.currencyID then
            self:AddDebugEntry("Currency ID", tostring(currencyInfo.currencyID))
        end
    end
end

function DebugFrameMixin:AddMountInfo(item)
    local itemData = item:GetItemData()
    if not itemData then return end

    local mountInfo = itemData:GetMountInfo()
    if mountInfo then
        if mountInfo.name then
            self:AddDebugEntry("Mount Name", mountInfo.name)
        end
        if mountInfo.isEquipment ~= nil then
            self:AddDebugEntry("Is Equipment", tostring(mountInfo.isEquipment))
        end
        self:AddDebugEntry("Needs Item", tostring(mountInfo.needsItem))
        if mountInfo.isUsable ~= nil then
            self:AddDebugEntry("Is Usable", tostring(mountInfo.isUsable))
        end
        if mountInfo.isFactionSpecific ~= nil then
            self:AddDebugEntry("Is Faction Specific", tostring(mountInfo.isFactionSpecific))
            if mountInfo.factionID then
                self:AddDebugEntry("Faction ID", tostring(mountInfo.factionID))
            end
        end
    end
end

function DebugFrameMixin:AddRecipeInfo(item)
    local itemData = item:GetItemData()
    if not itemData then return end

    local recipeInfo = itemData:GetRecipeInfo()
    if recipeInfo then
        self:AddDebugEntry("Learned", tostring(recipeInfo.learned))
        self:AddDebugEntry("Can Learn", tostring(recipeInfo.canLearn))
        self:AddDebugEntry("First Craft", tostring(recipeInfo.firstCraft))

        if not recipeInfo.createdItem then
            self:AddDebugEntry("Creates Item", "none (self-referential or no output)")
        end

        if recipeInfo.schematic and recipeInfo.schematic.outputItemID then
            self:AddDebugEntry("Schematic Output Item ID", tostring(recipeInfo.schematic.outputItemID))
        end

        -- Show created item as a card below the debug entries
        self:UpdateRecipeCreatedItemUI(recipeInfo)
    else
        self:AddDebugEntry("Recipe Data", "nil (recipe not found in trade skill cache)")
        self:UpdateRecipeCreatedItemUI(nil)
    end

    -- Show the recipe's own spell info
    local itemSpellName, itemSpellID = C_Item.GetItemSpell(item:GetItemLink())
    if itemSpellID then
        self:AddDebugEntry("Recipe Spell ID", tostring(itemSpellID))
        self:AddDebugEntry("Recipe Spell Name", tostring(itemSpellName))

        local tradeSkillRecipeInfo = C_TradeSkillUI.GetRecipeInfo(itemSpellID)
        if tradeSkillRecipeInfo then
            self:AddDebugEntry("TradeSkill Learned", tostring(tradeSkillRecipeInfo.learned))
            self:AddDebugEntry("TradeSkill Recipe ID", tostring(tradeSkillRecipeInfo.recipeID))
            if tradeSkillRecipeInfo.name then
                self:AddDebugEntry("TradeSkill Recipe Name", tradeSkillRecipeInfo.name)
            end
        else
            self:AddDebugEntry("TradeSkill Info", "nil (spell not in trade skill data)")
        end
    end
end

function DebugFrameMixin:AddToyInfo(item)
    local itemData = item:GetItemData()
    if not itemData then return end

    local toyInfo = itemData:GetToyInfo()
    if toyInfo then
        if toyInfo.name then
            self:AddDebugEntry("Toy Name", toyInfo.name)
        end
        self:AddDebugEntry("Needs Item", tostring(toyInfo.needsItem))
        if toyInfo.isFavorite ~= nil then
            self:AddDebugEntry("Is Favorite", tostring(toyInfo.isFavorite))
        end
    end
end

function DebugFrameMixin:RefreshCurrentItem()
    -- Prefer bag/slot refresh when available to preserve location-based tooltip and status
    if self.currentItemLocation and self.currentItemLocation.bag ~= nil and self.currentItemLocation.slot ~= nil then
        local bag, slot = self.currentItemLocation.bag, self.currentItemLocation.slot
        self:ClearDebugDisplay()
        self:SetCurrentItemFromBagAndSlot(bag, slot)
        return
    end

    if self.currentItem then
        -- Re-create the item to ensure we get fresh data
        local itemLink = self.currentItem
        local ask = self.currentAsk

        -- Clear everything to force a complete refresh
        self.currentItem = nil
        self:ClearDebugDisplay()

        -- Set the item again to trigger a full reload
        self:SetCurrentItem(itemLink, ask)
    end
end

function DebugFrameMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
    -- For ensemble items, show all relevant icons (learnable, completionist, restrictions, etc.)
    -- but hide binding and sellable icons
    if locationInfo and locationInfo.isEnsembleItem then
        return {
            bindingStatus = { shouldShow = false },
            ownIcon = { shouldShow = true },
            otherIcon = { shouldShow = true },
            questIcon = { shouldShow = true },
            oldExpansionIcon = { shouldShow = true },
            upgradeIcon = { shouldShow = true },
            sellableIcon = { shouldShow = false }
        }
    end

    -- For main debug frame item, show everything for debugging
    return {
        bindingStatus = { shouldShow = true },
        upgradeIcon = { shouldShow = true },
        oldExpansionIcon = { shouldShow = true },
        ownIcon = { shouldShow = true },
        otherIcon = { shouldShow = true },
        questIcon = { shouldShow = true },
        sellableIcon = { shouldShow = true }
    }
end

function DebugFrameMixin:GetDisplayInfoInternal(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
    -- Fallback for internal display info - delegate to GetDisplayInfo
    return self:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
end

function DebugFrameMixin:IsSameItem(button, item, locationInfo)
    -- For debug frame items (both main and ensemble), always treat as same item
    return locationInfo and (locationInfo.isDebugFrame or locationInfo.isEnsembleItem)
end

function DebugFrameMixin:Refresh(feature)
    CaerdonWardrobeFeatureMixin.Refresh(self, feature)
    if self.frame:IsShown() and self.currentItem then
        self:RefreshCurrentItem()
    end
end

CaerdonWardrobe:RegisterFeature(Mixin(CreateFrame("Frame"), CaerdonWardrobeFeatureMixin, DebugFrameMixin))
