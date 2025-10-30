local DressingRoomMixin = {}

local function EnsureHoverHook(frame)
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

local function SetDebugContext(frame, item, transmogID)
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

    EnsureHoverHook(frame)
    if frame.Icon then
        EnsureHoverHook(frame.Icon)
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

local function ClearDebugContext(frame)
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

function DressingRoomMixin:GetName()
    return "DressingRoom"
end

function DressingRoomMixin:Init()
    self:TryHookDressUp()
    self:TryHookNarcissus()

    return {
        "ADDON_LOADED",
        "TRANSMOG_COLLECTION_UPDATED",
        "TRANSMOG_COLLECTION_SOURCE_REMOVED",
        "TRANSMOG_SOURCE_COLLECTABILITY_UPDATE"
    }
end

function DressingRoomMixin:TryHookDressUp()
    if self.hooked then
        return
    end

    if not DressUpFrame or not DressUpFrameTransmogSetButtonMixin or not DressUpOutfitDetailsSlotMixin then
        return
    end

    self.hooked = true
    local feature = self

    local function updateSetSelectionButton(button)
        feature:UpdateSetSelectionButton(button)
    end

    hooksecurefunc(DressUpFrameTransmogSetButtonMixin, "InitItem", updateSetSelectionButton)
    hooksecurefunc(DressUpFrameTransmogSetButtonMixin, "Refresh", updateSetSelectionButton)

    hooksecurefunc(DressUpOutfitDetailsSlotMixin, "SetItemInfo",
        function(slotFrame, transmogID, appearanceInfo, isSecondary)
            feature:UpdateOutfitSlot(slotFrame, transmogID)
        end)

    hooksecurefunc(DressUpOutfitDetailsSlotMixin, "SetDetails", function(slotFrame)
        if not slotFrame.item or not slotFrame.transmogID then
            feature:ClearOutfitSlot(slotFrame)
        end
    end)

    hooksecurefunc(DressUpOutfitDetailsSlotMixin, "SetIllusion", function(slotFrame)
        feature:ClearOutfitSlot(slotFrame)
    end)
end

function DressingRoomMixin:TryHookNarcissus()
    self:TryHookNarcissusSlots()

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

    hooksecurefunc(setFrame, "SetItemSet", function(frame)
        frame.caerdonSetVersion = (frame.caerdonSetVersion or 0) + 1
        feature:RefreshNarcissusSetButtons(frame)
    end)

    hooksecurefunc(setFrame, "ReleaseItemButtons", function(frame)
        feature:ClearNarcissusSetButtons(frame)
    end)

    if type(setFrame.UpdateEquippedItems) == "function" then
        hooksecurefunc(setFrame, "UpdateEquippedItems", function(frame)
            feature:RefreshNarcissusSetButtons(frame)
        end)
    end

    if type(setFrame.AcquireItemButton) == "function" then
        hooksecurefunc(setFrame, "AcquireItemButton", function(frame)
            if frame.itemButtons then
                feature:PrepareNarcissusSetButton(frame.itemButtons[frame.numButtons])
            end
        end)
    end

    if type(setFrame.HookScript) == "function" then
        setFrame:HookScript("OnShow", function(frame)
            frame.caerdonSetVersion = (frame.caerdonSetVersion or 0) + 1
            feature:RefreshNarcissusSetButtons(frame)
        end)

        setFrame:HookScript("OnHide", function(frame)
            feature:ClearNarcissusSetButtons(frame)
        end)
    end

    self.narcissusHooked = true
    self:TryHookNarcissusSlots()

    if setFrame:IsShown() then
        setFrame.caerdonSetVersion = (setFrame.caerdonSetVersion or 0) + 1
        self:RefreshNarcissusSetButtons(setFrame)
    end
end

function DressingRoomMixin:TryHookNarcissusSlots()
    if self.narcissusSlotsHooked then
        return
    end

    if not NarciDressingRoomItemButtonMixin or type(NarciDressingRoomItemButtonMixin.SetItemSource) ~= "function" then
        return
    end

    self.narcissusSlotButtons = self.narcissusSlotButtons or {}
    local feature = self

    hooksecurefunc(NarciDressingRoomItemButtonMixin, "SetItemSource", function(button)
        feature:UpdateNarcissusOutfitButton(button)
    end)

    hooksecurefunc(NarciDressingRoomItemButtonMixin, "HideSlot", function(button, state)
        feature:EnsureNarcissusSlotButton(button)
        if state then
            feature:ClearNarcissusOutfitButton(button)
        else
            feature:UpdateNarcissusOutfitButton(button)
        end
    end)

    hooksecurefunc(NarciDressingRoomItemButtonMixin, "Desaturate", function(button, state)
        if state and (not button.sourceID or button.sourceID == 0) then
            feature:ClearNarcissusOutfitButton(button)
        end
    end)

    if type(NarciDressingRoomItemButtonMixin.SetSecondarySource) == "function" then
        hooksecurefunc(NarciDressingRoomItemButtonMixin, "SetSecondarySource", function(button)
            feature:UpdateNarcissusOutfitButton(button)
        end)
    end

    if NarciDressingRoomSlotFrameMixin then
        if type(NarciDressingRoomSlotFrameMixin.ShowPlayerTransmog) == "function" then
            hooksecurefunc(NarciDressingRoomSlotFrameMixin, "ShowPlayerTransmog", function()
                feature:RefreshNarcissusOutfitButtons()
            end)
        end

        if type(NarciDressingRoomSlotFrameMixin.FadeIn) == "function" then
            hooksecurefunc(NarciDressingRoomSlotFrameMixin, "FadeIn", function()
                feature:RefreshNarcissusOutfitButtons()
            end)
        end

        if type(NarciDressingRoomSlotFrameMixin.FadeOut) == "function" then
            hooksecurefunc(NarciDressingRoomSlotFrameMixin, "FadeOut", function()
                feature:RefreshNarcissusOutfitButtons()
            end)
        end
    end

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

    self:CollectNarcissusSlotButtons()
    self:RefreshNarcissusOutfitButtons()
end

function DressingRoomMixin:ADDON_LOADED(name)
    if name == "Blizzard_UIPanels_Game" or name == "Blizzard_SharedXMLGame" then
        self:TryHookDressUp()
    end
    self:TryHookNarcissus()
end

function DressingRoomMixin:TRANSMOG_COLLECTION_UPDATED()
    self:Refresh()
end

function DressingRoomMixin:TRANSMOG_COLLECTION_SOURCE_REMOVED()
    self:Refresh()
end

function DressingRoomMixin:TRANSMOG_SOURCE_COLLECTABILITY_UPDATE()
    self:Refresh()
end

function DressingRoomMixin:UpdateSetSelectionButton(button)
    if not button or not button.elementData then
        if button then
            CaerdonWardrobe:ClearButton(button)
        end
        return
    end

    local elementData = button.elementData
    local itemID = elementData.itemID
    if not itemID then
        CaerdonWardrobe:ClearButton(button)
        return
    end

    local item = CaerdonItem:CreateFromItemID(itemID)
    local panel = DressUpFrame and DressUpFrame.SetSelectionPanel
    local setID = panel and panel.setID or 0
    local appearanceID = elementData.itemModifiedAppearanceID or itemID

    local locationInfo = {
        locationKey = format("dressup-set-%s-%s", setID, appearanceID)
    }

    local options = {
        relativeFrame = button.Icon,
        bindingScale = 0.8,
        statusProminentSize = 15,
        statusOffsetX = 1,
        statusOffsetY = 1
    }

    CaerdonWardrobe:UpdateButton(button, item, self, locationInfo, options)

    SetDebugContext(button, item, appearanceID)
end

function DressingRoomMixin:PrepareNarcissusSetButton(button)
    if not button or button.caerdonNarcissusPrepared then
        return
    end

    button.caerdonNarcissusPrepared = true
    local feature = self

    if type(button.HookScript) == "function" then
        button:HookScript("OnHide", function(btn)
            feature:ClearNarcissusSetButton(btn)
        end)
    end
end

function DressingRoomMixin:ClearNarcissusSetButton(button)
    if not button then
        return
    end

    ClearDebugContext(button)
    CaerdonWardrobe:ClearButton(button)
end

function DressingRoomMixin:EnsureNarcissusSlotButton(button)
    if not button then
        return
    end

    self.narcissusSlotButtons = self.narcissusSlotButtons or {}
    self.narcissusSlotButtons[button] = true
end

function DressingRoomMixin:CollectNarcissusSlotButtons()
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

function DressingRoomMixin:PrepareNarcissusOutfitButton(button)
    if not button or button.caerdonNarcissusSlotPrepared then
        return
    end

    button.caerdonNarcissusSlotPrepared = true
    local feature = self

    if type(button.HookScript) == "function" then
        button:HookScript("OnHide", function(btn)
            feature:ClearNarcissusOutfitButton(btn)
        end)
    end
end

function DressingRoomMixin:UpdateNarcissusSetButton(setFrame, button)
    if not setFrame or not button then
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
    local version = setFrame.caerdonSetVersion or 0

    local locationInfo = {
        locationKey = format("narcissus-set-%s-%s-%s", version, itemID, appearanceID)
    }

    local options = {
        relativeFrame = button.Icon,
        bindingScale = 0.8,
        statusProminentSize = 15,
        statusOffsetX = 1,
        statusOffsetY = 1
    }

    CaerdonWardrobe:UpdateButton(button, item, self, locationInfo, options)
    SetDebugContext(button, item, appearanceID)
end

function DressingRoomMixin:RefreshNarcissusSetButtons(setFrame)
    setFrame = setFrame or self.narcissusSetFrame or GetNarcissusSetFrame()
    if not setFrame or not setFrame.itemButtons then
        return
    end

    for _, button in ipairs(setFrame.itemButtons) do
        self:PrepareNarcissusSetButton(button)
        if button and button:IsShown() and button.itemID then
            self:UpdateNarcissusSetButton(setFrame, button)
        else
            self:ClearNarcissusSetButton(button)
        end
    end
end

function DressingRoomMixin:ClearNarcissusSetButtons(setFrame)
    setFrame = setFrame or self.narcissusSetFrame or GetNarcissusSetFrame()
    if not setFrame or not setFrame.itemButtons then
        return
    end

    for _, button in ipairs(setFrame.itemButtons) do
        self:ClearNarcissusSetButton(button)
    end
end

function DressingRoomMixin:UpdateNarcissusOutfitButton(button)
    if not button then
        return
    end

    self:EnsureNarcissusSlotButton(button)
    self:PrepareNarcissusOutfitButton(button)

    if not button:IsShown() or button.isSlotHidden then
        self:ClearNarcissusOutfitButton(button)
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

    local sourceInfo = C_TransmogCollection and C_TransmogCollection.GetSourceInfo and C_TransmogCollection.GetSourceInfo(sourceID)
    local itemLink = sourceInfo and sourceInfo.itemLink
    local itemID = sourceInfo and sourceInfo.itemID or (C_TransmogCollection and C_TransmogCollection.GetSourceItemID and C_TransmogCollection.GetSourceItemID(sourceID))

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
    SetDebugContext(button, item, sourceID)
end

function DressingRoomMixin:ClearNarcissusOutfitButton(button)
    if not button then
        return
    end

    if button.caerdonNarcissusSlotPrepared and button.caerdonButton then
        local mogStatus = button.caerdonButton.mogStatus
        if mogStatus then
            mogStatus:SetTexture("")
        end
    end

    ClearDebugContext(button)
    CaerdonWardrobe:ClearButton(button)
end

function DressingRoomMixin:RefreshNarcissusOutfitButtons()
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

function DressingRoomMixin:UpdateOutfitSlot(slotFrame, transmogIDOverride)
    if not slotFrame then
        return
    end

    if not slotFrame.caerdonOutfitHooksApplied and type(slotFrame.HookScript) == "function" then
        slotFrame.caerdonOutfitHooksApplied = true
        local feature = self
        slotFrame:HookScript("OnHide", function(frame)
            feature:ClearOutfitSlot(frame)
        end)
    end

    local transmogLocation = slotFrame.transmogLocation
    if transmogLocation and type(transmogLocation.modification) == "boolean" then
        local transmogModEnum = Enum and Enum.TransmogModification
        local secondaryMod = (transmogModEnum and transmogModEnum.Secondary) or 1
        local mainMod = (transmogModEnum and transmogModEnum.Main) or 0
        -- Use numeric enums so C_TransmogCollection APIs accept the location (fixes bad argument #3 errors).
        transmogLocation.modification = transmogLocation.modification and secondaryMod or mainMod
    end

    local itemObject = slotFrame.item
    if not itemObject then
        self:ClearOutfitSlot(slotFrame)
        return
    end

    local itemLink = itemObject:GetItemLink()
    local item
    if itemLink then
        item = CaerdonItem:CreateFromItemLink(itemLink)
    else
        local itemID = itemObject:GetItemID()
        if not itemID then
            self:ClearOutfitSlot(slotFrame)
            return
        end

        item = CaerdonItem:CreateFromItemID(itemID)
    end

    if not item then
        self:ClearOutfitSlot(slotFrame)
        return
    end

    local transmogID = transmogIDOverride or slotFrame.transmogID or slotFrame.caerdonDebugTransmogID
    if not transmogID or transmogID == 0 then
        self:ClearOutfitSlot(slotFrame)
        return
    end

    local locationInfo = {
        locationKey = format("dressup-outfit-%s-%s", slotFrame.slotID or 0, transmogID or 0)
    }

    local options = {
        relativeFrame = slotFrame.Icon,
        bindingScale = 0.7,
        statusProminentSize = 14,
        statusOffsetX = 3,
        statusOffsetY = 3
    }

    CaerdonWardrobe:UpdateButton(slotFrame, item, self, locationInfo, options)

    SetDebugContext(slotFrame, item, transmogID)
end

function DressingRoomMixin:ClearOutfitSlot(slotFrame)
    if slotFrame then
        ClearDebugContext(slotFrame)
        CaerdonWardrobe:ClearButton(slotFrame)
    end
end

function DressingRoomMixin:GetTooltipData(item, locationInfo)
    local itemLink = item and item:GetItemLink()
    if itemLink then
        return C_TooltipInfo.GetHyperlink(itemLink)
    end
end

function DressingRoomMixin:Refresh()
    self:TryHookNarcissus()
    self:CollectNarcissusSlotButtons()
    CaerdonWardrobeFeatureMixin:Refresh(self)

    if not DressUpFrame or not DressUpFrame:IsShown() then
        self:RefreshNarcissusOutfitButtons()
        return
    end

    local setPanel = DressUpFrame.SetSelectionPanel
    if setPanel and setPanel:IsShown() and setPanel.RefreshItems then
        setPanel:RefreshItems()
    end

    local outfitPanel = DressUpFrame.OutfitDetailsPanel
    if outfitPanel and outfitPanel:IsShown() then
        outfitPanel:Refresh()

        for _, slot in ipairs(CollectOutfitSlots(outfitPanel)) do
            self:UpdateOutfitSlot(slot)
        end
    end

    self:RefreshNarcissusOutfitButtons()
end

function DressingRoomMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
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
        oldExpansionIcon = {
            shouldShow = true
        },
        sellableIcon = {
            shouldShow = false
        }
    }
end

local function CollectOutfitSlots(outfitPanel)
    local slots = {}

    if not outfitPanel then
        return slots
    end

    if outfitPanel.slotPool and outfitPanel.slotPool.EnumerateActive then
        for slot in outfitPanel.slotPool:EnumerateActive() do
            table.insert(slots, slot)
        end
    end

    if #slots == 0 then
        local storedSlots = outfitPanel.slots or outfitPanel.Slots
        if storedSlots then
            for _, slot in ipairs(storedSlots) do
                table.insert(slots, slot)
            end
        end
    end

    if #slots == 0 and type(outfitPanel.GetChildren) == "function" then
        local children = { outfitPanel:GetChildren() }
        for _, child in ipairs(children) do
            if child and child.transmogLocation then
                table.insert(slots, child)
            end
        end
    end

    return slots
end

function CaerdonWardrobe_DebugNarcissus()
    if not (CaerdonWardrobeConfig and CaerdonWardrobeConfig.Debug and CaerdonWardrobeConfig.Debug.Enabled) then
        print("Caerdon Wardrobe: Enable debug in options to use CaerdonWardrobe_DebugNarcissus().")
        return
    end

    local dressingRoomFeature = CaerdonWardrobe and CaerdonWardrobe.GetFeature and CaerdonWardrobe:GetFeature("DressingRoom")
    if dressingRoomFeature and dressingRoomFeature.TryHookNarcissus then
        dressingRoomFeature:TryHookNarcissus()
        dressingRoomFeature:RefreshNarcissusOutfitButtons()
    end

    print("Caerdon Wardrobe Narcissus Debug")

    local setFrame = GetNarcissusSetFrame()
    if setFrame then
        local version = setFrame.caerdonSetVersion or 0
        local buttonCount = setFrame.itemButtons and #setFrame.itemButtons or 0
        print(("  SetFrame shown=%s version=%d buttons=%d"):format(setFrame:IsShown() and "true" or "false", version,
            buttonCount))

        if setFrame.itemButtons then
            for index, button in ipairs(setFrame.itemButtons) do
                local overlay = button and button.caerdonButton
                local mogStatus = overlay and overlay.mogStatus
                local texture = mogStatus and (mogStatus:GetTexture() or "nil") or "nil"
                local alpha = mogStatus and (mogStatus:GetAlpha() or 0) or 0

                print(("    Row %d shown=%s itemID=%s modID=%s caerdonKey=%s texture=%s alpha=%.2f link=%s"):format(
                    index,
                    button and button:IsShown() and "true" or "false",
                    tostring(button and (button.caerdonDebugItemID or button.itemID) or "nil"),
                    tostring(button and button.itemModifiedAppearanceID or "nil"),
                    tostring(button and button.caerdonKey or ""),
                    texture,
                    alpha,
                    tostring(button and (button.caerdonDebugItemLink or button.hyperlink) or "nil")
                ))
            end
        end
    else
        print("  Narcissus set frame not available.")
    end

    local outfitPanel = DressUpFrame and DressUpFrame.OutfitDetailsPanel
    if not outfitPanel then
        print("  OutfitDetailsPanel not available.")
        return
    end

    print(("  OutfitDetailsPanel shown=%s"):format(outfitPanel:IsShown() and "true" or "false"))

    local slots = CollectOutfitSlots(outfitPanel)
    if #slots == 0 then
        print("    No outfit slots found.")
    else
        for _, slot in ipairs(slots) do
            local overlay = slot and slot.caerdonButton
            local mogStatus = overlay and overlay.mogStatus
            local texture = mogStatus and (mogStatus:GetTexture() or "nil") or "nil"
            local alpha = mogStatus and (mogStatus:GetAlpha() or 0) or 0
            local transmogID = slot and (slot.caerdonDebugTransmogID or slot.transmogID) or nil
            local slotLabel = slot and (slot.slotName or slot.slotID or (slot.transmogLocation and slot.transmogLocation.slotID)) or "?"

            print(("    Slot %s shown=%s transmogID=%s caerdonKey=%s texture=%s alpha=%.2f link=%s"):format(
                tostring(slotLabel),
                slot and slot:IsShown() and "true" or "false",
                tostring(transmogID or "nil"),
                tostring(slot and slot.caerdonKey or ""),
                texture,
                alpha,
                tostring(slot and (slot.caerdonDebugItemLink or (slot.GetItemLink and slot:GetItemLink())) or "nil")
            ))
        end
    end

    if dressingRoomFeature and dressingRoomFeature.narcissusSlotButtons then
        local count = 0
        for button in pairs(dressingRoomFeature.narcissusSlotButtons) do
            if button and not button:IsForbidden() then
                count = count + 1
            end
        end
        print(("  Narcissus slot buttons tracked=%d"):format(count))

        for button in pairs(dressingRoomFeature.narcissusSlotButtons) do
            if button and not button:IsForbidden() then
                local overlay = button.caerdonButton
                local mogStatus = overlay and overlay.mogStatus
                local texture = mogStatus and (mogStatus:GetTexture() or "nil") or "nil"
                local alpha = mogStatus and (mogStatus:GetAlpha() or 0) or 0
                print(("    Slot %s shown=%s hidden=%s sourceID=%s secondary=%s caerdonKey=%s texture=%s alpha=%.2f link=%s"):format(
                    tostring(button.slotID or "?"),
                    button:IsShown() and "true" or "false",
                    tostring(button.isSlotHidden and "true" or "false"),
                    tostring(button.sourceID or "nil"),
                    tostring(button.secondarySourceID or "nil"),
                    tostring(button.caerdonKey or ""),
                    texture,
                    alpha,
                    tostring(button.caerdonDebugItemLink or button.hyperlink or "nil")
                ))
            end
        end
    end
end

CaerdonWardrobe:RegisterFeature(DressingRoomMixin)
