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

function DressingRoomMixin:GetName()
    return "DressingRoom"
end

function DressingRoomMixin:Init()
    self:TryHookDressUp()

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

function DressingRoomMixin:ADDON_LOADED(name)
    if name == "Blizzard_UIPanels_Game" or name == "Blizzard_SharedXMLGame" then
        self:TryHookDressUp()
    end
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

function DressingRoomMixin:UpdateOutfitSlot(slotFrame, transmogIDOverride)
    if not slotFrame then
        return
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
        slotFrame.caerdonDebugItemID = nil
        slotFrame.caerdonDebugItemLink = nil
        slotFrame.caerdonDebugTransmogID = nil
        if slotFrame.Icon then
            slotFrame.Icon.caerdonDebugItemID = nil
            slotFrame.Icon.caerdonDebugItemLink = nil
            slotFrame.Icon.caerdonDebugTransmogID = nil
            if CaerdonAPI and CaerdonAPI.ClearManualHoverContext then
                CaerdonAPI:ClearManualHoverContext(slotFrame.Icon)
            end
        end
        CaerdonWardrobe:ClearButton(slotFrame)
        if CaerdonAPI and CaerdonAPI.ClearManualHoverContext then
            CaerdonAPI:ClearManualHoverContext(slotFrame)
        end
    end
end

function DressingRoomMixin:GetTooltipData(item, locationInfo)
    local itemLink = item and item:GetItemLink()
    if itemLink then
        return C_TooltipInfo.GetHyperlink(itemLink)
    end
end

function DressingRoomMixin:Refresh()
    CaerdonWardrobeFeatureMixin:Refresh(self)

    if not DressUpFrame or not DressUpFrame:IsShown() then
        return
    end

    local setPanel = DressUpFrame.SetSelectionPanel
    if setPanel and setPanel:IsShown() and setPanel.RefreshItems then
        setPanel:RefreshItems()
    end

    local outfitPanel = DressUpFrame.OutfitDetailsPanel
    if outfitPanel and outfitPanel:IsShown() then
        outfitPanel:Refresh()
    end
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

CaerdonWardrobe:RegisterFeature(DressingRoomMixin)
