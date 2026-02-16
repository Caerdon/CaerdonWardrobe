local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "Narcissus"
local NarcissusMixin = {}

local DEBUG = false
local function dbg(...)
    if DEBUG then print("|cff00ccff[CW-Narci]|r", ...) end
end

function NarcissusMixin:GetName()
    return addonName
end

function NarcissusMixin:Init()
    dbg("Init called")
    self:TryHookNarcissus()
    self:TryHookNarcissusSlots()

    return {
        "ADDON_LOADED",
        "PLAYER_ENTERING_WORLD",
        "TRANSMOG_COLLECTION_UPDATED",
        "TRANSMOG_COLLECTION_SOURCE_REMOVED",
        "TRANSMOG_SOURCE_COLLECTABILITY_UPDATE"
    }
end

local cachedNarcissusSetFrame

local function GetNarcissusSetFrame()
    if cachedNarcissusSetFrame and type(cachedNarcissusSetFrame.SetItemSet) == "function" then
        return cachedNarcissusSetFrame
    end

    cachedNarcissusSetFrame = nil

    -- Narcissus stores TransmogSetFrame on its private addon namespace (not exposed
    -- globally).  During PLAYER_ENTERING_WORLD it re-parents the frame to DressUpFrame,
    -- so scanning DressUpFrame children is the only reliable discovery path.
    -- NOTE: ScrollView is created lazily inside TransmogSetFrame:Init() (called on
    -- first SetItemSet), so we cannot require it here.  SetItemSet + LoadItem are
    -- defined at file scope and uniquely identify the Narcissus frame.
    if DressUpFrame and type(DressUpFrame.GetChildren) == "function" then
        for _, child in ipairs({ DressUpFrame:GetChildren() }) do
            if child and type(child.SetItemSet) == "function" and type(child.LoadItem) == "function" then
                dbg("GetNarcissusSetFrame: found via DressUpFrame child scan")
                cachedNarcissusSetFrame = child
                return cachedNarcissusSetFrame
            end
        end
    end
end

local function GetNarcissusSlotContainer()
    local overlay = _G.NarciDressingRoomOverlay
    if not overlay then
        return
    end

    local slotFrame = overlay.SlotFrame
    if slotFrame and slotFrame.SlotContainer then
        return slotFrame.SlotContainer
    end
end

function NarcissusMixin:TryHookNarcissus()
    if self.narcissusHooked then
        dbg("TryHookNarcissus: already hooked")
        return
    end

    local setFrame = GetNarcissusSetFrame()
    if not setFrame or type(setFrame.SetItemSet) ~= "function" then
        local childCount = 0
        if DressUpFrame and type(DressUpFrame.GetChildren) == "function" then
            childCount = select("#", DressUpFrame:GetChildren())
        end
        dbg("TryHookNarcissus: setFrame not found.", "DressUpFrame=", DressUpFrame ~= nil, "children=", childCount)
        return
    end

    dbg("TryHookNarcissus: found setFrame, hooking.", "LoadItem=", type(setFrame.LoadItem), "ClearContent=", type(setFrame.ClearContent))

    self.narcissusSetFrame = setFrame
    local feature = self

    -- Hook SetItemSet: when an ensemble is displayed, schedule a delayed refresh
    -- to catch buttons that load quickly. The LoadItem hook below handles the
    -- per-button processing as each item is assigned.
    hooksecurefunc(setFrame, "SetItemSet", function(frame)
        dbg("SetItemSet hook fired")
        C_Timer.After(0.1, function()
            feature:RefreshNarcissusSetButtons(frame)
        end)
    end)

    -- Hook LoadItem: called for each button that receives an item assignment.
    -- This fires from setupFunc -> SetItem -> LoadItem when buttons are created
    -- or recycled by the ScrollView, and also when scrolling brings new items
    -- into view.
    if type(setFrame.LoadItem) == "function" then
        hooksecurefunc(setFrame, "LoadItem", function(frame, itemID, itemButton)
            dbg("LoadItem hook:", itemID, "button=", itemButton ~= nil)
            if itemButton then
                feature:ClearNarcissusSetButton(itemButton)
                feature:PrepareNarcissusSetButton(itemButton)
            end
        end)
    else
        dbg("WARNING: setFrame.LoadItem is not a function!")
    end

    -- Hook ClearContent: safety net for cleanup. In practice, the per-button
    -- ClearItem hook (installed by PrepareNarcissusSetButton) handles cleanup
    -- during ReleaseAll since ClearItem fires before activeObjects is emptied.
    -- This hook fires after ClearContent returns, so activeObjects may already
    -- be empty; it serves as a fallback for any buttons not yet prepared.
    if type(setFrame.ClearContent) == "function" then
        hooksecurefunc(setFrame, "ClearContent", function(frame)
            CaerdonWardrobeFeatureMixin:Refresh(feature)
        end)
    end

    self.narcissusHooked = true
    self:TryHookNarcissusSlots()

    -- Defer initial refresh: ContinueOnItemLoad can trigger synchronous
    -- ITEM_DATA_LOAD_RESULT callbacks during addon init, and processing all
    -- buttons in one go amplifies the issue.
    if setFrame:IsShown() then
        C_Timer.After(0.1, function()
            self:RefreshNarcissusSetButtons(setFrame)
        end)
    end
end

function NarcissusMixin:TryHookNarcissusSlots()
    if self.narcissusSlotsHooked then
        return
    end

    if not NarciDressingRoomItemButtonMixin or type(NarciDressingRoomItemButtonMixin.SetItemSource) ~= "function" then
        return
    end

    self.narcissusSlotButtons = self.narcissusSlotButtons or {}
    local feature = self

    self.narcissusSlotsHooked = true

    local container = GetNarcissusSlotContainer()
    if container then
        local slotFrame = container:GetParent()
        if slotFrame and type(slotFrame.HookScript) == "function" and not slotFrame.caerdonNarcissusHooked then
            slotFrame.caerdonNarcissusHooked = true
            slotFrame:HookScript("OnShow", function()
                feature:CollectNarcissusSlotButtons()
                feature:RefreshNarcissusOutfitButtons()
            end)
            slotFrame:HookScript("OnHide", function()
                feature:RefreshNarcissusOutfitButtons()
            end)
        end
    end
end

function NarcissusMixin:PrepareNarcissusSetButton(button)
    if not button or button.caerdonNarcissusPrepared then
        return
    end

    button.caerdonNarcissusPrepared = true
    local feature = self

    -- Hook OnItemLoaded: fires after Narcissus sets the icon/name from
    -- ITEM_DATA_LOAD_RESULT. Deferred to the next frame because
    -- ContinueOnItemLoad -> LoadSources -> AddCallback can fire synchronous
    -- ITEM_DATA_LOAD_RESULT events that re-enter OnItemLoaded on other
    -- ensemble buttons, causing C stack overflow.
    hooksecurefunc(button, "OnItemLoaded", function(btn, itemID)
        -- Skip if we already processed this item on this button.
        -- ContinueOnItemLoad -> LoadSources fires ITEM_DATA_LOAD_RESULT which
        -- Narcissus interprets as a new OnItemLoaded, creating an infinite loop.
        if btn.caerdonProcessedItemID == itemID then
            return
        end
        C_Timer.After(0, function()
            if btn.caerdonProcessedItemID == itemID then
                return
            end
            if btn.itemID == itemID and btn:IsShown() then
                feature:UpdateNarcissusSetButton(btn)
            end
        end)
    end)

    -- Hook ClearItem: fires when the ScrollView recycles a button (pool
    -- onRemoved callback) or when ClearContent is called. Clean up the
    -- Caerdon overlay so recycled buttons start fresh.
    hooksecurefunc(button, "ClearItem", function(btn)
        feature:ClearNarcissusSetButton(btn)
    end)
end

function NarcissusMixin:ClearNarcissusSetButton(button)
    if not button then
        return
    end

    button.caerdonProcessedItemID = nil
    self:ClearDebugContext(button)
    CaerdonWardrobe:ClearButton(button)
end

function NarcissusMixin:EnsureNarcissusSlotButton(button)
    if not button then
        return
    end

    self.narcissusSlotButtons = self.narcissusSlotButtons or {}
    self.narcissusSlotButtons[button] = true
end

function NarcissusMixin:CollectNarcissusSlotButtons()
    local container = GetNarcissusSlotContainer()
    if not container then
        return
    end

    local children = { container:GetChildren() }
    if #children == 0 then
        return
    end

    for _, child in ipairs(children) do
        if child and child.slotID then
            self:EnsureNarcissusSlotButton(child)
            self:PrepareNarcissusOutfitButton(child)
        end
    end
end

function NarcissusMixin:PrepareNarcissusOutfitButton(button)
    if not button or button.caerdonNarcissusSlotPrepared then
        return
    end

    button.caerdonNarcissusSlotPrepared = true
    local feature = self

    hooksecurefunc(button, "SetItemSource", function(button)
        feature:UpdateNarcissusOutfitButton(button)
    end)

    if type(button.HookScript) == "function" then
        button:HookScript("OnHide", function(btn)
            feature:ClearNarcissusOutfitButton(btn)
        end)
    end
end

function NarcissusMixin:UpdateNarcissusSetButton(button)
    if not button then
        dbg("UpdateSetButton: nil button")
        return
    end

    if not button:IsShown() or not button.itemID or button.itemID == 0 then
        dbg("UpdateSetButton: skip - shown=", button:IsShown(), "itemID=", button.itemID)
        self:ClearNarcissusSetButton(button)
        return
    end

    local itemID = button.itemID
    button.caerdonProcessedItemID = itemID

    local item = CaerdonItem:CreateFromItemID(itemID)
    if not item then
        dbg("UpdateSetButton: CaerdonItem nil for", itemID)
        self:ClearNarcissusSetButton(button)
        return
    end

    local appearanceID = button.itemModifiedAppearanceID or itemID
    dbg("UpdateSetButton:", itemID, "appearance=", appearanceID, "cached=", item:IsItemDataCached())

    -- Pass the sourceID so the Equipment pipeline can identify the transmog
    -- source without relying on C_TransmogCollection.GetItemInfo, which often
    -- returns nil for items created from a bare itemID.
    if button.itemModifiedAppearanceID then
        item.extraData = {
            appearanceSourceID = button.itemModifiedAppearanceID
        }
    end

    local locationInfo = {
        locationKey = format("narcissus-set-%s-%s", itemID, appearanceID)
    }

    local options = {
        relativeFrame = button.Icon,
        bindingScale = 0.8,
        statusProminentSize = 15,
        statusOffsetX = 1,
        statusOffsetY = 1
    }

    local feature = self
    local function doUpdate()
        -- Guard: button may have been recycled while waiting for item data
        if button.itemID == itemID then
            dbg("doUpdate: calling UpdateButton for", itemID)
            CaerdonWardrobe:UpdateButton(button, item, feature, locationInfo, options)
            feature:SetDebugContext(button, item, appearanceID)
        else
            dbg("doUpdate: button recycled, skip. current=", button.itemID, "expected=", itemID)
        end
    end

    -- Ensure item data (including Equipment source loading) is fully cached
    -- before entering the coroutine pipeline. Without this, customDataLoaded
    -- stays false and items are never processed by ProcessItem.
    if item:IsItemDataCached() then
        dbg("UpdateSetButton: item cached, calling doUpdate directly")
        doUpdate()
    else
        dbg("UpdateSetButton: item not cached, deferring via ContinueOnItemLoad")
        item:ContinueOnItemLoad(doUpdate)
    end
end

function NarcissusMixin:RefreshNarcissusSetButtons(setFrame)
    setFrame = setFrame or self.narcissusSetFrame or GetNarcissusSetFrame()
    if not setFrame or not setFrame.ScrollView then
        dbg("RefreshSetButtons: no setFrame or ScrollView")
        return
    end

    if type(setFrame.IsShown) == "function" and not setFrame:IsShown() then
        dbg("RefreshSetButtons: frame not shown")
        return
    end

    if type(setFrame.ScrollView.ProcessActiveObjects) == "function" then
        local feature = self
        local count = 0
        setFrame.ScrollView:ProcessActiveObjects("ItemButton", function(button)
            count = count + 1
            if button and button:IsShown() and button.itemID then
                dbg("RefreshSetButtons: processing button", count, "itemID=", button.itemID)
                feature:PrepareNarcissusSetButton(button)
                feature:UpdateNarcissusSetButton(button)
            else
                dbg("RefreshSetButtons: skip button", count, "shown=", button and button:IsShown(), "itemID=", button and button.itemID)
            end
        end)
        dbg("RefreshSetButtons: processed", count, "buttons")
    else
        dbg("RefreshSetButtons: ProcessActiveObjects not available")
    end
end

function NarcissusMixin:ClearNarcissusSetButtons(setFrame)
    setFrame = setFrame or self.narcissusSetFrame or GetNarcissusSetFrame()
    if not setFrame or not setFrame.ScrollView then
        return
    end

    if type(setFrame.ScrollView.ProcessActiveObjects) == "function" then
        local feature = self
        setFrame.ScrollView:ProcessActiveObjects("ItemButton", function(button)
            feature:ClearNarcissusSetButton(button)
        end)
    end
end

function NarcissusMixin:UpdateNarcissusOutfitButton(button)
    if not button then
        return
    end

    self:EnsureNarcissusSlotButton(button)
    self:PrepareNarcissusOutfitButton(button)

    if type(button.IsShown) == "function" and not button:IsShown() then
        self:ClearNarcissusOutfitButton(button)
        return
    end

    if type(button.IsForbidden) == "function" and button:IsForbidden() then
        return
    end

    if type(button.HasItem) == "function" and not button:HasItem() then
        self:ClearNarcissusOutfitButton(button)
        return
    end

    local sourceID = button.sourceID
    if not sourceID or sourceID == 0 then
        self:ClearNarcissusOutfitButton(button)
        return
    end

    local sourceInfo = C_TransmogCollection and C_TransmogCollection.GetSourceInfo and
        C_TransmogCollection.GetSourceInfo(sourceID)
    local itemLink = sourceInfo and sourceInfo.itemLink
    local itemID = sourceInfo and sourceInfo.itemID or
        (C_TransmogCollection and C_TransmogCollection.GetSourceItemID and C_TransmogCollection.GetSourceItemID(sourceID))

    local item
    if itemLink and itemLink ~= "" then
        item = CaerdonItem:CreateFromItemLink(itemLink)
    elseif itemID and itemID > 0 then
        item = CaerdonItem:CreateFromItemID(itemID)
    else
        local fallbackLink = button.hyperlink
        if fallbackLink and fallbackLink ~= "" then
            item = CaerdonItem:CreateFromItemLink(fallbackLink)
        end
    end

    if not item then
        self:ClearNarcissusOutfitButton(button)
        return
    end

    local slotID = button.slotID or 0
    local secondarySourceID = button.secondarySourceID or 0

    local locationInfo = {
        locationKey = format("narcissus-outfit-%s-%s-%s", slotID, sourceID, secondarySourceID)
    }

    local options = {
        relativeFrame = button.ItemIcon or button.Icon or button,
        bindingScale = 0.7,
        statusProminentSize = 14,
        statusOffsetX = 3,
        statusOffsetY = 3
    }

    local feature = self
    local function doUpdate()
        CaerdonWardrobe:UpdateButton(button, item, feature, locationInfo, options)
        feature:SetDebugContext(button, item, sourceID)
    end

    if item:IsItemDataCached() then
        doUpdate()
    else
        item:ContinueOnItemLoad(doUpdate)
    end
end

function NarcissusMixin:EnsureHoverHook(frame)
    if not frame or type(frame.HookScript) ~= "function" or frame.caerdonDebugHoverHooked then
        return
    end

    frame.caerdonDebugHoverHooked = true

    frame:HookScript("OnEnter", function(self)
        if CaerdonAPI and CaerdonAPI.SetManualHoverContext then
            local context = {
                itemLink = self.caerdonDebugItemLink,
                itemID = self.caerdonDebugItemID,
                transmogSourceID = self.caerdonDebugTransmogID,
            }
            CaerdonAPI:SetManualHoverContext(self, context)
        end
    end)

    frame:HookScript("OnLeave", function(self)
        if CaerdonAPI and CaerdonAPI.ClearManualHoverContext then
            CaerdonAPI:ClearManualHoverContext(self)
        end
    end)
end

function NarcissusMixin:SetDebugContext(frame, item, transmogID)
    if not frame or not item then
        return
    end

    local itemID = nil
    if type(item.GetItemID) == "function" then
        itemID = item:GetItemID()
    end

    frame.caerdonDebugItemID = (itemID and itemID > 0) and itemID or nil

    if transmogID then
        frame.caerdonDebugTransmogID = transmogID
    else
        frame.caerdonDebugTransmogID = nil
    end

    frame.caerdonDebugItemLink = nil

    if frame.Icon then
        frame.Icon.caerdonDebugItemID = frame.caerdonDebugItemID
        frame.Icon.caerdonDebugTransmogID = frame.caerdonDebugTransmogID
        frame.Icon.caerdonDebugItemLink = nil
    end

    if frame.elementData then
        frame.elementData.caerdonDebugItemID = frame.caerdonDebugItemID
        frame.elementData.caerdonDebugTransmogID = frame.caerdonDebugTransmogID
        frame.elementData.caerdonDebugItemLink = nil
    end

    self:EnsureHoverHook(frame)
    if frame.Icon then
        self:EnsureHoverHook(frame.Icon)
    end

    if CaerdonAPI and CaerdonAPI.SetManualHoverContext then
        CaerdonAPI:SetManualHoverContext(frame, {
            itemLink = frame.caerdonDebugItemLink,
            itemID = frame.caerdonDebugItemID,
            transmogSourceID = frame.caerdonDebugTransmogID,
        })
    end

    local function finalize()
        if type(item.GetItemLink) == "function" then
            local link = item:GetItemLink()
            if link and link ~= "" then
                frame.caerdonDebugItemLink = link
                if frame.Icon then
                    frame.Icon.caerdonDebugItemLink = link
                end
                if frame.elementData then
                    frame.elementData.caerdonDebugItemLink = link
                end

                if CaerdonAPI and CaerdonAPI.SetManualHoverContext then
                    CaerdonAPI:SetManualHoverContext(frame, {
                        itemLink = frame.caerdonDebugItemLink,
                        itemID = frame.caerdonDebugItemID,
                        transmogSourceID = frame.caerdonDebugTransmogID,
                    })
                end
            end
        end
    end

    if type(item.IsItemCached) == "function" and item:IsItemCached() then
        finalize()
    elseif type(item.ContinueOnItemLoad) == "function" then
        item:ContinueOnItemLoad(finalize)
    else
        finalize()
    end
end

function NarcissusMixin:ClearDebugContext(frame)
    if not frame then
        return
    end

    frame.caerdonDebugItemID = nil
    frame.caerdonDebugItemLink = nil
    frame.caerdonDebugTransmogID = nil

    if frame.Icon then
        frame.Icon.caerdonDebugItemID = nil
        frame.Icon.caerdonDebugItemLink = nil
        frame.Icon.caerdonDebugTransmogID = nil
        if CaerdonAPI and CaerdonAPI.ClearManualHoverContext then
            CaerdonAPI:ClearManualHoverContext(frame.Icon)
        end
    end

    if frame.elementData then
        frame.elementData.caerdonDebugItemID = nil
        frame.elementData.caerdonDebugTransmogID = nil
        frame.elementData.caerdonDebugItemLink = nil
    end

    if CaerdonAPI and CaerdonAPI.ClearManualHoverContext then
        CaerdonAPI:ClearManualHoverContext(frame)
    end
end

function NarcissusMixin:ClearNarcissusOutfitButton(button)
    if not button then
        return
    end

    self:ClearDebugContext(button)
    CaerdonWardrobe:ClearButton(button)
end

function NarcissusMixin:RefreshNarcissusOutfitButtons()
    if not self.narcissusSlotButtons or next(self.narcissusSlotButtons) == nil then
        self:CollectNarcissusSlotButtons()
    end

    if not self.narcissusSlotButtons then
        return
    end

    for button in pairs(self.narcissusSlotButtons) do
        if button and not button:IsForbidden() then
            if button:IsShown() and not button.isSlotHidden then
                self:UpdateNarcissusOutfitButton(button)
            else
                self:ClearNarcissusOutfitButton(button)
            end
        else
            self.narcissusSlotButtons[button] = nil
        end
    end
end

function NarcissusMixin:ADDON_LOADED(name)
    -- TransmogSetFrame discovery requires PLAYER_ENTERING_WORLD (when Narcissus
    -- re-parents it to DressUpFrame), so we only retry slot hooks here.
    if not self.narcissusSlotsHooked then
        self:TryHookNarcissusSlots()
    end
end

function NarcissusMixin:PLAYER_ENTERING_WORLD()
    -- Narcissus re-parents TransmogSetFrame from UIParent to DressUpFrame during
    -- its own PLAYER_ENTERING_WORLD handler.  Defer so our scan runs after Narcissus
    -- has finished the re-parent.
    if not self.narcissusHooked then
        local feature = self
        C_Timer.After(0, function()
            dbg("PLAYER_ENTERING_WORLD deferred: retrying TryHookNarcissus")
            feature:TryHookNarcissus()
        end)
    end
end

function NarcissusMixin:TRANSMOG_COLLECTION_UPDATED()
    self:Refresh()
end

function NarcissusMixin:TRANSMOG_COLLECTION_SOURCE_REMOVED()
    self:Refresh()
end

function NarcissusMixin:TRANSMOG_SOURCE_COLLECTABILITY_UPDATE()
    self:Refresh()
end

function NarcissusMixin:Refresh()
    CaerdonWardrobeFeatureMixin:Refresh(self)
    self:RefreshNarcissusSetButtons()
    self:RefreshNarcissusOutfitButtons()
end

function NarcissusMixin:GetTooltipData(item, locationInfo)
    local itemLink = item and item:GetItemLink()
    if itemLink then
        return C_TooltipInfo.GetHyperlink(itemLink)
    end
end

function NarcissusMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
    return {
        bindingStatus = {
            shouldShow = false
        },
        ownIcon = {
            shouldShow = true
        },
        otherIcon = {
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

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
    if C_AddOns.IsAddOnLoaded(addonName) then
        Version = C_AddOns.GetAddOnMetadata(addonName, "Version")
        CaerdonWardrobe:RegisterFeature(NarcissusMixin)
        isActive = true
    end
end
