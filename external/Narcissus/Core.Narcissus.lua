local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "Narcissus"
local NarcissusMixin = {}

function NarcissusMixin:GetName()
    return addonName
end

function NarcissusMixin:Init()
    self:TryHookNarcissus()
end

-- local dressingRoomFeature = CaerdonWardrobe and CaerdonWardrobe.GetFeature and CaerdonWardrobe:GetFeature("DressingRoom")
-- if not dressingRoomFeature or dressingRoomFeature._narcissusSupportInitialized then
--     return
-- end

local cachedNarcissusSetFrame

local function GetNarcissusSetFrame()
    if cachedNarcissusSetFrame and cachedNarcissusSetFrame.itemButtons then
        return cachedNarcissusSetFrame
    end

    local overlay = _G.NarciDressingRoomOverlay
    if overlay and overlay.SetFrame then
        cachedNarcissusSetFrame = overlay.SetFrame
        return cachedNarcissusSetFrame
    end

    local narci = _G.Narci
    if narci and narci.DressingRoomSystem and narci.DressingRoomSystem.TransmogSetFrame then
        cachedNarcissusSetFrame = narci.DressingRoomSystem.TransmogSetFrame
        if cachedNarcissusSetFrame and overlay then
            overlay.SetFrame = cachedNarcissusSetFrame
        end
        return cachedNarcissusSetFrame
    end

    local transmogSetFrame = _G.TransmogSetFrame
    if transmogSetFrame and transmogSetFrame.itemButtons then
        cachedNarcissusSetFrame = transmogSetFrame
        if overlay then
            overlay.SetFrame = cachedNarcissusSetFrame
        end
        return cachedNarcissusSetFrame
    end

    if overlay then
        for _, child in ipairs({ overlay:GetChildren() }) do
            if child and child.itemButtons and type(child.SetItemSet) == "function" then
                cachedNarcissusSetFrame = child
                overlay.SetFrame = cachedNarcissusSetFrame
                return cachedNarcissusSetFrame
            end
        end
    end

    if DressUpFrame and type(DressUpFrame.GetChildren) == "function" then
        for _, child in ipairs({ DressUpFrame:GetChildren() }) do
            if child and child.itemButtons and type(child.SetItemSet) == "function" then
                cachedNarcissusSetFrame = child
                if overlay then
                    overlay.SetFrame = cachedNarcissusSetFrame
                end
                return cachedNarcissusSetFrame
            end
        end
    end

    if type(EnumerateFrames) == "function" then
        local frame = EnumerateFrames()
        while frame do
            if frame ~= DressUpFrame and frame and frame.itemButtons and type(frame.SetItemSet) == "function" then
                cachedNarcissusSetFrame = frame
                if overlay then
                    overlay.SetFrame = cachedNarcissusSetFrame
                end
                return cachedNarcissusSetFrame
            end
            frame = EnumerateFrames(frame)
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
    -- self:TryHookNarcissusSlots()

    if self.narcissusHooked then
        return
    end

    local setFrame = GetNarcissusSetFrame()
    if not setFrame or type(setFrame) ~= "table" then
        return
    end

    if type(setFrame.SetItemSet) ~= "function" or not setFrame.itemButtons then
        return
    end

    self.narcissusSetFrame = setFrame
    local feature = self

    -- hooksecurefunc(setFrame, "SetItemSet", function(frame)
    --     frame.caerdonSetVersion = (frame.caerdonSetVersion or 0) + 1
    --     feature:RefreshNarcissusSetButtons(frame)
    -- end)

    hooksecurefunc(setFrame, "ReleaseItemButtons", function(frame)
        feature:ClearNarcissusSetButtons(frame)
    end)

    -- if type(setFrame.UpdateEquippedItems) == "function" then
    --     hooksecurefunc(setFrame, "UpdateEquippedItems", function(frame)
    --         feature:RefreshNarcissusSetButtons(frame)
    --     end)
    -- end

    if type(setFrame.AcquireItemButton) == "function" then
        hooksecurefunc(setFrame, "AcquireItemButton", function(frame)
            if frame.itemButtons then
                feature:PrepareNarcissusSetButton(frame.itemButtons[frame.numButtons])
            end
        end)
    end

    -- if type(setFrame.HookScript) == "function" then
    --     setFrame:HookScript("OnShow", function(frame)
    --         frame.caerdonSetVersion = (frame.caerdonSetVersion or 0) + 1
    --         feature:RefreshNarcissusSetButtons(frame)
    --     end)

    --     setFrame:HookScript("OnHide", function(frame)
    --         feature:ClearNarcissusSetButtons(frame)
    --     end)
    -- end

    self.narcissusHooked = true
    self:TryHookNarcissusSlots()

    -- if setFrame:IsShown() then
    --     setFrame.caerdonSetVersion = (setFrame.caerdonSetVersion or 0) + 1
    --     self:RefreshNarcissusSetButtons(setFrame)
    -- end
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

    -- if true then return end

    -- hooksecurefunc(NarciDressingRoomItemButtonMixin, "HideSlot", function(button, state)
    --     feature:EnsureNarcissusSlotButton(button)
    --     if state then
    --         feature:ClearNarcissusOutfitButton(button)
    --     else
    --         feature:UpdateNarcissusOutfitButton(button)
    --     end
    -- end)

    -- hooksecurefunc(NarciDressingRoomItemButtonMixin, "Desaturate", function(button, state)
    --     if state and (not button.sourceID or button.sourceID == 0) then
    --         feature:ClearNarcissusOutfitButton(button)
    --     end
    -- end)

    -- if type(NarciDressingRoomItemButtonMixin.SetSecondarySource) == "function" then
    --     hooksecurefunc(NarciDressingRoomItemButtonMixin, "SetSecondarySource", function(button)
    --         feature:UpdateNarcissusOutfitButton(button)
    --     end)
    -- end

    -- if NarciDressingRoomSlotFrameMixin then
    --     if type(NarciDressingRoomSlotFrameMixin.ShowPlayerTransmog) == "function" then
    --         hooksecurefunc(NarciDressingRoomSlotFrameMixin, "ShowPlayerTransmog", function()
    --             feature:RefreshNarcissusOutfitButtons()
    --         end)
    --     end

    --     if type(NarciDressingRoomSlotFrameMixin.FadeIn) == "function" then
    --         hooksecurefunc(NarciDressingRoomSlotFrameMixin, "FadeIn", function()
    --             feature:RefreshNarcissusOutfitButtons()
    --         end)
    --     end

    --     if type(NarciDressingRoomSlotFrameMixin.FadeOut) == "function" then
    --         hooksecurefunc(NarciDressingRoomSlotFrameMixin, "FadeOut", function()
    --             feature:RefreshNarcissusOutfitButtons()
    --         end)
    --     end
    -- end

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

    -- self:CollectNarcissusSlotButtons()
    -- self:RefreshNarcissusOutfitButtons()
end

function NarcissusMixin:PrepareNarcissusSetButton(button)
    if not button or button.caerdonNarcissusPrepared then
        return
    end

    button.caerdonNarcissusPrepared = true
    local feature = self

    -- if type(button.HookScript) == "function" then
    --     button:HookScript("OnHide", function(btn)
    --         feature:ClearNarcissusSetButton(btn)
    --     end)
    -- end

    hooksecurefunc(button, "OnItemLoaded", function(button, itemID)
        if button.caerdonItemLoaded then return end;
        button.caerdonItemLoaded = true

        self:UpdateNarcissusSetButton(button)
    end)
end

function NarcissusMixin:ClearNarcissusSetButton(button)
    if not button then
        return
    end

    self:ClearDebugContext(button)
    CaerdonWardrobe:ClearButton(button)
    button.caerdonItemLoaded = false
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
        return
    end

    if not button:IsShown() or not button.itemID or button.itemID == 0 then
        self:ClearNarcissusSetButton(button)
        return
    end

    local itemID = button.itemID
    local item = CaerdonItem:CreateFromItemID(itemID)
    if not item then
        self:ClearNarcissusSetButton(button)
        return
    end

    local appearanceID = button.itemModifiedAppearanceID or itemID

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

    CaerdonWardrobe:UpdateButton(button, item, self, locationInfo, options)
    self:SetDebugContext(button, item, appearanceID)
end

function NarcissusMixin:RefreshNarcissusSetButtons(setFrame)
    setFrame = setFrame or self.narcissusSetFrame or GetNarcissusSetFrame()
    if not setFrame or not setFrame.itemButtons then
        return
    end

    -- for _, button in ipairs(setFrame.itemButtons) do
    --     self:PrepareNarcissusSetButton(button)
    --     if button and button:IsShown() and button.itemID then
    --         self:UpdateNarcissusSetButton(button)
    --     else
    --         self:ClearNarcissusSetButton(button)
    --     end
    -- end
end

function NarcissusMixin:ClearNarcissusSetButtons(setFrame)
    setFrame = setFrame or self.narcissusSetFrame or GetNarcissusSetFrame()
    if not setFrame or not setFrame.itemButtons then
        return
    end

    for _, button in ipairs(setFrame.itemButtons) do
        self:ClearNarcissusSetButton(button)
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

    CaerdonWardrobe:UpdateButton(button, item, self, locationInfo, options)
    self:SetDebugContext(button, item, sourceID)
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

-- local originalInit = dressingRoomFeature.Init
-- function dressingRoomFeature:Init(...)
--     local events = originalInit(self, ...)
--     self:TryHookNarcissus()
--     return events
-- end

-- local originalAddonLoaded = dressingRoomFeature.ADDON_LOADED
-- function dressingRoomFeature:ADDON_LOADED(name, ...)
--     if originalAddonLoaded then
--         originalAddonLoaded(self, name, ...)
--     end

--     if name == "Blizzard_UIPanels_Game" or name == "Blizzard_SharedXMLGame" or name == addonName then
--         self:TryHookNarcissus()
--     end
-- end

function NarcissusMixin:Refresh()
    -- CaerdonWardrobeFeatureMixin:Refresh(self)
    -- self:TryHookNarcissus()
    -- self:CollectNarcissusSlotButtons()
    -- self:RefreshNarcissusOutfitButtons()
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

-- dressingRoomFeature._narcissusSupportInitialized = true

-- if C_AddOns.IsAddOnLoaded(addonName) then
--     dressingRoomFeature:TryHookNarcissus()
-- else
--     local loader = CreateFrame("Frame")
--     loader:RegisterEvent("ADDON_LOADED")
--     loader:SetScript("OnEvent", function(self, event, name)
--         if name == addonName then
--             dressingRoomFeature:TryHookNarcissus()
--             self:UnregisterAllEvents()
--         end
--     end)
-- end
