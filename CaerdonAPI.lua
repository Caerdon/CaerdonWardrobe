local CaerdonAPIMixin = {}
CaerdonAPI = {}

local function SafeCallMethod(target, method, ...)
    if not target then
        return
    end

    local func = target[method]
    if type(func) ~= "function" then
        return
    end

    local ok, result, extra = pcall(func, target, ...)
    if ok then
        return result, extra
    end
end

local function IsItemLink(link)
    return type(link) == "string" and link ~= "" and link:find("item:")
end

local function GetItemIDFromLink(link)
    if not IsItemLink(link) then
        return
    end

    local itemID = tonumber(link:match("item:(%d+)"))
    if itemID and itemID > 0 then
        return itemID
    end
end

local function ExtractItemLocationBagAndSlot(itemLocation)
    if not itemLocation then
        return
    end

    if type(itemLocation.GetBagAndSlot) == "function" then
        local ok, bag, slot = pcall(itemLocation.GetBagAndSlot, itemLocation)
        if ok and bag ~= nil and slot ~= nil then
            return bag, slot
        end
    end
end

local function ExtractBagAndSlot(frame)
    if not frame then
        return
    end

    local originalFrame = frame
    local bag = frame.bagID or frame.bagId or frame.BagID or frame.BagId or frame.bag or frame.Bag
    local slot = frame.slot or frame.slotID or frame.slotId or frame.Slot or frame.SlotID or frame.slotIndex or frame.SlotIndex

    local function tryContainer(container)
        if type(container) ~= "table" then
            return
        end

        if bag == nil then
            local containerBag = container.bagID or container.bagId or container.BagID or container.BagId or container.bag or container.Bag or container.bagIndex or container.BagIndex
            if type(containerBag) == "number" then
                bag = containerBag
            else
                local value = SafeCallMethod(container, "GetBagID") or SafeCallMethod(container, "GetBag") or SafeCallMethod(container, "GetBagIndex")
                if type(value) == "number" then
                    bag = value
                end
            end
        end

        if slot == nil then
            local containerSlot = container.slot or container.slotID or container.slotId or container.Slot or container.SlotID or container.slotIndex or container.SlotIndex or container.index or container.itemIndex or container.itemSlot
            if type(containerSlot) == "number" then
                slot = containerSlot
            else
                local value = SafeCallMethod(container, "GetSlotIndex") or SafeCallMethod(container, "GetID") or SafeCallMethod(container, "GetSlot")
                if type(value) == "number" then
                    slot = value
                end
            end
        end

        if (bag == nil or slot == nil) and type(container.GetBagAndSlot) == "function" then
            local ok, containerBag, containerSlot = pcall(container.GetBagAndSlot, container)
            if ok then
                if bag == nil and type(containerBag) == "number" then
                    bag = containerBag
                end
                if slot == nil and type(containerSlot) == "number" then
                    slot = containerSlot
                end
            end
        end

        if bag ~= nil and slot ~= nil then
            return
        end

        local itemLocation = container.itemLocation
        if not itemLocation then
            itemLocation = SafeCallMethod(container, "GetItemLocation")
        end
        if itemLocation then
            local bagFromLocation, slotFromLocation = ExtractItemLocationBagAndSlot(itemLocation)
            if bag == nil and type(bagFromLocation) == "number" then
                bag = bagFromLocation
            end
            if slot == nil and type(slotFromLocation) == "number" then
                slot = slotFromLocation
            end
        end
    end

    if type(bag) ~= "number" then
        bag = nil
    end
    if type(slot) ~= "number" then
        slot = nil
    end

    if bag == nil or slot == nil then
        tryContainer(frame.elementData)
        tryContainer(frame.data)
        tryContainer(frame.info)
        tryContainer(frame.result)
    end

    if not bag then
        bag = SafeCallMethod(frame, "GetBagID") or SafeCallMethod(frame, "GetBag")
    end

    if not slot then
        slot = SafeCallMethod(frame, "GetSlotIndex")
    end

    if not slot then
        local id = SafeCallMethod(frame, "GetID")
        if type(id) == "number" then
            slot = id
        end
    end

    if bag ~= nil and slot ~= nil then
        return bag, slot
    end

    local location = frame.itemLocation
    if not location then
        location = SafeCallMethod(frame, "GetItemLocation")
    end

    if location and type(location.IsBagAndSlot) == "function" and location:IsBagAndSlot() then
        local bagFromLocation, slotFromLocation = ExtractItemLocationBagAndSlot(location)
        if bagFromLocation ~= nil and slotFromLocation ~= nil then
            return bagFromLocation, slotFromLocation
        end
    end

    if location then
        local bagFromLocation, slotFromLocation = ExtractItemLocationBagAndSlot(location)
        if bagFromLocation ~= nil and slotFromLocation ~= nil then
            return bagFromLocation, slotFromLocation
        end
    end

    if bag == nil and originalFrame and type(originalFrame.GetParent) == "function" then
        local parent = originalFrame:GetParent()
        local depth = 0
        while parent and depth < 3 do
            local parentBag = parent.bagID or parent.bagId or parent.BagID or parent.BagId or parent.bag or parent.Bag
            if type(parentBag) == "number" then
                bag = parentBag
                break
            end

            local parentID = SafeCallMethod(parent, "GetID")
            if type(parentID) == "number" then
                local name = type(parent.GetName) == "function" and parent:GetName() or ""
                if name and type(name) == "string" and name:find("ContainerFrame") then
                    bag = parentID - 1
                    break
                elseif name and type(name) == "string" and name:find("BankFrame") then
                    bag = parentID
                    break
                elseif name and type(name) == "string" and name:find("ReagentBankFrame") then
                    bag = parentID
                    break
                end
            end

            parent = SafeCallMethod(parent, "GetParent")
            depth = depth + 1
        end
    end

    if type(bag) == "number" and type(slot) == "number" then
        return bag, slot
    end

    if type(bag) == "number" then
        return bag, nil
    end

    if type(slot) == "number" then
        return nil, slot
    end
end

local function ExtractItemLinkFromFrame(frame)
    if not frame then
        return
    end

    if IsItemLink(frame.caerdonDebugItemLink) then
        return frame.caerdonDebugItemLink
    end

    local _, link = SafeCallMethod(frame, "GetItem")
    if IsItemLink(link) then
        return link
    end

    link = SafeCallMethod(frame, "GetItemLink")
    if IsItemLink(link) then
        return link
    end

    link = SafeCallMethod(frame, "GetHyperlink")
    if IsItemLink(link) then
        return link
    end

    local directFields = { "itemLink", "hyperlink", "link" }
    for _, field in ipairs(directFields) do
        if IsItemLink(frame[field]) then
            return frame[field]
        end
    end

    local containers = { frame.result, frame.info, frame.data, frame.elementData }
    for _, container in ipairs(containers) do
        if type(container) == "table" then
            if IsItemLink(container.caerdonDebugItemLink) then
                return container.caerdonDebugItemLink
            end
            for _, field in ipairs(directFields) do
                if IsItemLink(container[field]) then
                    return container[field]
                end
                if field == "result" and type(container[field]) == "table" then
                    local link = ExtractItemLinkFromFrame(container[field])
                    if IsItemLink(link) then
                        return link
                    end
                end
            end
        end
    end

    if type(frame.item) == "table" then
        local itemLink = SafeCallMethod(frame.item, "GetItemLink")
        if IsItemLink(itemLink) then
            return itemLink
        end
    end
end

local function ExtractItemIDFromFrame(frame)
    if not frame then
        return
    end

    if type(frame.caerdonDebugItemID) == "number" and frame.caerdonDebugItemID > 0 then
        return frame.caerdonDebugItemID
    end

    local idFields = { "itemID", "itemId", "ItemID", "itemid" }
    for _, field in ipairs(idFields) do
        local value = frame[field]
        if type(value) == "number" and value > 0 then
            return value
        end
    end

    local containers = { frame.result, frame.info, frame.data, frame.elementData }
    for _, container in ipairs(containers) do
        if type(container) == "table" then
            if type(container.caerdonDebugItemID) == "number" and container.caerdonDebugItemID > 0 then
                return container.caerdonDebugItemID
            end
            for _, field in ipairs(idFields) do
                local value = container[field]
                if type(value) == "number" and value > 0 then
                    return value
                end
            end
            if type(container.result) == "table" then
                local nestedID = ExtractItemIDFromFrame(container.result)
                if type(nestedID) == "number" and nestedID > 0 then
                    return nestedID
                end
            end
        end
    end

    if type(frame.item) == "table" then
        local itemID = SafeCallMethod(frame.item, "GetItemID")
        if type(itemID) == "number" and itemID > 0 then
            return itemID
        end

        local itemLink = SafeCallMethod(frame.item, "GetItemLink")
        local itemIDFromLink = GetItemIDFromLink(itemLink)
        if itemIDFromLink then
            return itemIDFromLink
        end
    end

    local frameItemID = SafeCallMethod(frame, "GetItemID")
    if type(frameItemID) == "number" and frameItemID > 0 then
        return frameItemID
    end
end

local function ExtractTransmogSourceID(frame)
    if not frame then
        return
    end

    local sourceFields = { "itemModifiedAppearanceID", "secondaryAppearanceID", "transmogID", "itemSourceID" }
    if type(frame.caerdonDebugTransmogID) == "number" and frame.caerdonDebugTransmogID > 0 then
        return frame.caerdonDebugTransmogID
    end
    if type(frame.transmogID) == "number" and frame.transmogID > 0 then
        return frame.transmogID
    end
    for _, field in ipairs(sourceFields) do
        local value = frame[field]
        if type(value) == "number" and value > 0 then
            return value
        end
    end

    if type(frame.elementData) == "table" then
        if type(frame.elementData.caerdonDebugTransmogID) == "number" and frame.elementData.caerdonDebugTransmogID > 0 then
            return frame.elementData.caerdonDebugTransmogID
        end
        if type(frame.elementData.transmogID) == "number" and frame.elementData.transmogID > 0 then
            return frame.elementData.transmogID
        end
        for _, field in ipairs(sourceFields) do
            local value = frame.elementData[field]
            if type(value) == "number" and value > 0 then
                return value
            end
        end
    end
end

local function GetTooltipFrames(focus)
    local frames = {}

    if not focus and type(GetMouseFocus) == "function" then
        focus = GetMouseFocus()
    end

    local tooltipCandidates = {
        ItemRefTooltip,
        ItemRefShoppingTooltip1,
        ItemRefShoppingTooltip2,
        ItemRefShoppingTooltip3,
        GameTooltip,
        ShoppingTooltip1,
        ShoppingTooltip2,
        ShoppingTooltip3,
    }

    local tooltipLookup = {}
    for _, tooltip in ipairs(tooltipCandidates) do
        if tooltip then
            tooltipLookup[tooltip] = true
        end
    end

    if focus then
        table.insert(frames, { frame = focus, isTooltip = tooltipLookup[focus] == true })
    end

    for _, tooltip in ipairs(tooltipCandidates) do
        if tooltip then
            table.insert(frames, { frame = tooltip, isTooltip = true })
        end
    end

    return frames
end

local function CopyTooltipContext(context)
    if not context then
        return
    end

    local copy = {}
    for k, v in pairs(context) do
        copy[k] = v
    end
    return copy
end

local function HasContextData(context)
    if not context then
        return false
    end

    if context.itemLink then
        return true
    end

    if type(context.itemID) == "number" and context.itemID > 0 then
        return true
    end

    if context.transmogSourceID then
        return true
    end

    if context.bag ~= nil and context.slot ~= nil then
        return true
    end

    return false
end

function CaerdonAPIMixin:SetManualHoverContext(frame, context)
    if not frame then
        return
    end

    local finalContext = context or self:GetFrameItemContext(frame)
    if not HasContextData(finalContext) then
        if self.manualHoverContext and self.manualHoverContext.owner == frame then
            self.manualHoverContext = nil
        end
        return
    end

    local newContext = {}
    for k, v in pairs(finalContext) do
        if k ~= "owner" and k ~= "timestamp" then
            newContext[k] = v
        end
    end
    newContext.owner = frame
    newContext.timestamp = GetTime()
    self.manualHoverContext = newContext
end

function CaerdonAPIMixin:ClearManualHoverContext(frame)
    if not self.manualHoverContext then
        return
    end

    if frame == nil or self.manualHoverContext.owner == frame then
        self.manualHoverContext = nil
    end
end

function CaerdonAPIMixin:UpdateManualHoverContext(frame)
    if not self.manualHoverContext then
        return
    end

    frame = frame or self.manualHoverContext.owner
    if not frame or self.manualHoverContext.owner ~= frame then
        return
    end

    self:SetManualHoverContext(frame)
end

function CaerdonAPIMixin:InitTooltipTracking()
    if self.tooltipHooked then
        return
    end

    if not TooltipDataProcessor or not Enum or not Enum.TooltipDataType or not Enum.TooltipDataType.Item then
        return
    end

    self.tooltipHooked = true
    local api = self
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, tooltipData)
        api:OnTooltipItem(tooltip, tooltipData)
    end)
end

function CaerdonAPIMixin:OnTooltipItem(tooltip, tooltipData)
    if not tooltipData then
        return
    end

    local context = self.lastTooltipContext or {}
    wipe(context)

    if tooltipData.hyperlink and IsItemLink(tooltipData.hyperlink) then
        context.itemLink = tooltipData.hyperlink
        context.itemID = context.itemID or GetItemIDFromLink(tooltipData.hyperlink)
    end

    local idKeys = { "itemID", "id", "itemId" }
    for _, key in ipairs(idKeys) do
        local value = tooltipData[key]
        if type(value) == "number" and value > 0 then
            context.itemID = value
            break
        end
    end

    local bagKeys = { "bagID", "bagIndex", "containerID", "containerIndex", "bag" }
    for _, key in ipairs(bagKeys) do
        local value = tooltipData[key]
        if type(value) == "number" then
            context.bag = value
            break
        end
    end

    local slotKeys = { "slotIndex", "slot", "slotID", "containerSlot" }
    for _, key in ipairs(slotKeys) do
        local value = tooltipData[key]
        if type(value) == "number" then
            context.slot = value
            break
        end
    end

    if tooltipData.guid and ItemLocation and ItemLocation.CreateFromGUID then
        local ok, itemLocation = pcall(ItemLocation.CreateFromGUID, ItemLocation, tooltipData.guid)
        if ok and itemLocation and itemLocation:IsValid() and itemLocation:IsBagAndSlot() then
            local bag, slot = itemLocation:GetBagAndSlot()
            context.bag = context.bag or bag
            context.slot = context.slot or slot
            context.itemLocation = itemLocation
        end
    end

    if tooltipData.guid then
        context.guid = tooltipData.guid
    end

    if not (context.itemLink or context.itemID or (context.bag ~= nil and context.slot ~= nil)) then
        return
    end

    context.tooltip = tooltip
    context.timestamp = GetTime()
    self.lastTooltipContext = context
end

StaticPopupDialogs.CopyLinkPopup = {
    text = "Item Link String",
	button1 = OKAY,
    OnAccept = function(self)
        local linkText = self.editBox:GetText()
        local selectedLink = gsub(linkText, "\124\124", "\124")
        print(selectedLink)
    end,
    hasEditBox = true,
    enterClicksFirstButton = true,  -- TODO: Not sure why these aren't working ... might need OnKeyDown?
	whileDead = true,
	hideOnEscape = true
}

function CaerdonAPIMixin:OnLoad()
    self:InitTooltipTracking()
end

function CaerdonAPIMixin:CopyMouseoverLink()
    local link = select(2, GameTooltip:GetItem())
    self:CopyLink(link)
end

function CaerdonAPIMixin:DumpLinkDetails(link)
    if link then
        local originalValue = CaerdonWardrobeConfig.Debug.Enabled
        CaerdonWardrobeConfig.Debug.Enabled = true

        local originalMax = DEVTOOLS_MAX_ENTRY_CUTOFF
        DEVTOOLS_MAX_ENTRY_CUTOFF = 300

        SlashCmdList.DUMP(format("CaerdonAPI:GetItemDetails(CaerdonItem:CreateFromItemLink(\"%s\"))", link))

        DEVTOOLS_MAX_ENTRY_CUTOFF = originalMax
        CaerdonWardrobeConfig.Debug.Enabled = originalValue
    end
end

function CaerdonAPIMixin:GetItemDetails(item)
    local itemData = item:GetItemData()
    local itemResults
    local caerdonType = item:GetCaerdonItemType()

    if caerdonType == CaerdonItemType.BattlePet then
        itemResults = itemData:GetBattlePetInfo()
    elseif caerdonType == CaerdonItemType.CompanionPet then
        itemResults = itemData:GetCompanionPetInfo()
    elseif caerdonType == CaerdonItemType.Conduit then
        itemResults = itemData:GetConduitInfo()
    elseif caerdonType == CaerdonItemType.Consumable then
        itemResults = itemData:GetConsumableInfo()
    elseif caerdonType == CaerdonItemType.Currency then
        itemResults = itemData:GetCurrencyInfo()
    elseif caerdonType == CaerdonItemType.Equipment then
        itemResults = itemData:GetTransmogInfo()
    elseif caerdonType == CaerdonItemType.Mount then
        itemResults = itemData:GetMountInfo()
    elseif caerdonType == CaerdonItemType.Profession then
        itemResults = itemData:GetProfessionInfo()
    elseif caerdonType == CaerdonItemType.Quest then
        itemResults = itemData:GetQuestInfo()
    elseif caerdonType == CaerdonItemType.Recipe then
        itemResults = itemData:GetRecipeInfo()
    elseif caerdonType == CaerdonItemType.Toy then
        itemResults = itemData:GetToyInfo()
    end

    return {
        caerdonType = caerdonType,
        forDebugUse = item:GetForDebugUse(),
        itemResults = itemResults
    }
end

function CaerdonAPIMixin:DumpMouseoverLinkDetails()
    local tooltipData = GameTooltip:GetPrimaryTooltipData()
    if tooltipData then
        if tooltipData.hyperlink then
            self:DumpLinkDetails(tooltipData.hyperlink)
        end

        if tooltipData.additionalHyperlink then
            self:DumpLinkDetails(tooltipData.additionalHyperlink)
        end
    end
end

function CaerdonAPIMixin:GetDebugFeature()
    if not CaerdonWardrobe or type(CaerdonWardrobe.GetFeature) ~= "function" then
        return
    end

    local feature = CaerdonWardrobe:GetFeature("DebugFrame")
    if feature and feature.frame then
        return feature
    end
end

function CaerdonAPIMixin:GetFrameItemContext(frame, isTooltipFrame)
    local visited = {}
    local bagCandidate, slotCandidate
    while frame and type(frame) == "table" and not visited[frame] do
        visited[frame] = true

        local bag, slot = ExtractBagAndSlot(frame)
        if bag ~= nil and bagCandidate == nil then
            bagCandidate = bag
        end
        if slot ~= nil and slotCandidate == nil then
            slotCandidate = slot
        end
        if bagCandidate ~= nil and slotCandidate ~= nil then
            local context = { bag = bagCandidate, slot = slotCandidate }
            if isTooltipFrame then
                context.fromTooltip = true
            end
            return context
        end

        local itemLink = ExtractItemLinkFromFrame(frame)
        if IsItemLink(itemLink) then
            local context = { itemLink = itemLink }
            if isTooltipFrame then
                context.fromTooltip = true
            end
            return context
        end

        local itemID = ExtractItemIDFromFrame(frame)
        if itemID then
            local context = { itemID = itemID }
            if isTooltipFrame then
                context.fromTooltip = true
            end
            return context
        end

        local sourceID = ExtractTransmogSourceID(frame)
        if sourceID and C_TransmogCollection and C_TransmogCollection.GetSourceItemID then
            local sourceItemID = C_TransmogCollection.GetSourceItemID(sourceID)
            if sourceItemID and sourceItemID > 0 then
                local context = { itemID = sourceItemID }
                if isTooltipFrame then
                    context.fromTooltip = true
                end
                return context
            end
        end

        frame = SafeCallMethod(frame, "GetParent")
    end

    if bagCandidate ~= nil and slotCandidate ~= nil then
        local context = { bag = bagCandidate, slot = slotCandidate }
        if isTooltipFrame then
            context.fromTooltip = true
        end
        return context
    end
end

function CaerdonAPIMixin:GetHoveredItemContext()
    self:InitTooltipTracking()

    local focus = nil
    if type(GetMouseFocus) == "function" then
        focus = GetMouseFocus()
    end

    if self.manualHoverContext then
        local ctx = self.manualHoverContext
        if ctx.timestamp and (GetTime() - ctx.timestamp > 10) then
            self.manualHoverContext = nil
        else
            local owner = ctx.owner
            local ownerMatches = not owner
            if owner then
                local isMouseOver = SafeCallMethod(owner, "IsMouseOver")
                if isMouseOver == true then
                    ownerMatches = true
                else
                    ownerMatches = focus == nil
                    if not ownerMatches and focus then
                        local ancestor = focus
                        local depth = 0
                        while ancestor and depth < 6 do
                            if ancestor == owner then
                                ownerMatches = true
                                break
                            end
                            ancestor = SafeCallMethod(ancestor, "GetParent")
                            depth = depth + 1
                        end
                    end
                end
            end

            if ownerMatches then
                local result = {}
                for k, v in pairs(ctx) do
                    if k ~= "owner" and k ~= "timestamp" then
                        result[k] = v
                    end
                end
                if HasContextData(result) then
                    return result
                end
            end
        end
    end

    for _, frameInfo in ipairs(GetTooltipFrames(focus)) do
        local frame = frameInfo.frame
        if frame and (type(frame.IsShown) ~= "function" or frame:IsShown()) then
            local context = self:GetFrameItemContext(frame, frameInfo.isTooltip)
            if context then
                return context
            end
        end
    end

    if GameTooltip and type(GameTooltip.GetPrimaryTooltipData) == "function" then
        local tooltip = GameTooltip
        local tooltipIsShown = type(tooltip.IsShown) ~= "function" or tooltip:IsShown()
        if tooltipIsShown then
            local tooltipData = tooltip:GetPrimaryTooltipData()
            if tooltipData then
                local tooltipLink = tooltipData.hyperlink
                local tooltipGuid = tooltipData.guid
                local currentTooltipLink = select(2, SafeCallMethod(tooltip, "GetItem"))

                if IsItemLink(tooltipLink) and IsItemLink(currentTooltipLink) and currentTooltipLink == tooltipLink then
                    return {
                        itemLink = tooltipLink,
                        fromTooltip = true
                    }
                end

                if tooltipGuid and tooltipGuid ~= "" then
                    return {
                        guid = tooltipGuid,
                        itemLink = IsItemLink(currentTooltipLink) and currentTooltipLink or (IsItemLink(tooltipLink) and tooltipLink or nil),
                        fromTooltip = true
                    }
                end
            end
        end
    end

    if self.lastTooltipContext then
        local context = self.lastTooltipContext
        local tooltip = context.tooltip

        if tooltip and type(tooltip.IsShown) == "function" and tooltip:IsShown() then
            local ageValid = not context.timestamp or (GetTime() - context.timestamp) <= 10
            if ageValid then
                local tooltipData = SafeCallMethod(tooltip, "GetPrimaryTooltipData")
                local tooltipLink = tooltipData and tooltipData.hyperlink
                local tooltipGuid = tooltipData and tooltipData.guid
                local tooltipHasItem = (tooltipGuid and tooltipGuid ~= "") or IsItemLink(tooltipLink)

                if not tooltipHasItem then
                    return
                end

                local currentTooltipLink = select(2, SafeCallMethod(tooltip, "GetItem"))
                if IsItemLink(context.itemLink) then
                    if IsItemLink(tooltipLink) then
                        if tooltipLink ~= context.itemLink then
                            return
                        end
                    elseif tooltipGuid and context.guid and tooltipGuid == context.guid then
                        -- ok, guid matches even if hyperlink missing
                    elseif IsItemLink(currentTooltipLink) and currentTooltipLink == context.itemLink then
                        -- ok, GetItem still matches
                    else
                        return
                    end
                elseif IsItemLink(currentTooltipLink) then
                    context.itemLink = currentTooltipLink
                elseif context.guid then
                    if not tooltipGuid or tooltipGuid ~= context.guid then
                        return
                    end
                    context.guid = tooltipGuid
                else
                    return
                end

                local copy = CopyTooltipContext(context)
                if copy then
                    if (copy.bag == nil or copy.slot == nil) and copy.itemLocation and type(copy.itemLocation.IsValid) == "function" then
                        if copy.itemLocation:IsValid() and copy.itemLocation:IsBagAndSlot() then
                            local bag, slot = copy.itemLocation:GetBagAndSlot()
                            copy.bag = copy.bag or bag
                            copy.slot = copy.slot or slot
                        end
                    end

                    copy.tooltip = nil
                    copy.itemLocation = nil
                    copy.fromTooltip = true
                    return copy
                end
            end
        end
    end
end

local function OpenDebugFrameWithItem(debugFeature, item)
    if not debugFeature or not debugFeature.frame or not item then
        return false
    end

    debugFeature.frame:Show()

    local function onItemReady()
        local link = item:GetItemLink()
        if IsItemLink(link) then
            debugFeature:SetCurrentItem(link)
            debugFeature.frame:Show()
        end
    end

    if item:IsItemDataCached() then
        onItemReady()
        return true
    else
        item:ContinueWithCancelOnItemLoad(onItemReady)
        return true
    end
end

function CaerdonAPIMixin:OpenDebugFrameWithItemID(debugFeature, itemID)
    if not debugFeature or not itemID or itemID <= 0 then
        return false
    end

    if not Item or type(Item.CreateFromItemID) ~= "function" then
        return false
    end

    local item = Item:CreateFromItemID(itemID)
    if item then
        return OpenDebugFrameWithItem(debugFeature, item)
    end

    return false
end

function CaerdonAPIMixin:OpenDebugFrameWithItemGUID(debugFeature, itemGUID)
    if not debugFeature or not itemGUID or itemGUID == "" then
        return false
    end

    if not Item or type(Item.CreateFromItemGUID) ~= "function" then
        return false
    end

    local item = Item:CreateFromItemGUID(itemGUID)
    if item then
        return OpenDebugFrameWithItem(debugFeature, item)
    end

    return false
end

function CaerdonAPIMixin:OpenDebugForHoveredItem()
    local debugFeature = self:GetDebugFeature()
    if not debugFeature then
        print("Caerdon Wardrobe: Debug frame is not ready yet.")
        return
    end

    local context = self:GetHoveredItemContext()
    if context and context.fromTooltip then
        local tooltipLink = select(2, SafeCallMethod(GameTooltip, "GetItem"))
        local tooltipData = nil
        if GameTooltip and type(GameTooltip.GetPrimaryTooltipData) == "function" then
            tooltipData = GameTooltip:GetPrimaryTooltipData()
        end
        local tooltipGuid = tooltipData and tooltipData.guid
        local linkMatches = IsItemLink(context.itemLink) and IsItemLink(tooltipLink) and tooltipLink == context.itemLink
        local guidMatches = context.guid and tooltipGuid and tooltipGuid ~= "" and tooltipGuid == context.guid

        if not linkMatches and IsItemLink(tooltipLink) and not IsItemLink(context.itemLink) then
            context.itemLink = tooltipLink
            linkMatches = true
        end

        if not linkMatches and not guidMatches and context.bag == nil and context.slot == nil and not context.itemID and not context.transmogSourceID then
            context = nil
        end
    end

    if not context then
        print("Caerdon Wardrobe: No hovered item found to debug.")
        return
    end

    if context.bag ~= nil and context.slot ~= nil then
        debugFeature.frame:Show()
        debugFeature:SetCurrentItemFromBagAndSlot(context.bag, context.slot)
        return
    end

    if context.guid then
        local handled = false

        if C_Item and type(C_Item.GetItemLinkByGUID) == "function" then
            local guidLink = C_Item.GetItemLinkByGUID(context.guid)
            if IsItemLink(guidLink) then
                debugFeature.frame:Show()
                debugFeature:SetCurrentItem(guidLink)
                handled = true
            end
        end

        if not handled then
            handled = self:OpenDebugFrameWithItemGUID(debugFeature, context.guid)
        end

        if handled then
            return
        end
    end

    if IsItemLink(context.itemLink) then
        debugFeature.frame:Show()
        debugFeature:SetCurrentItem(context.itemLink)
        return
    end

    if context.itemID then
        local _, tooltipLink = SafeCallMethod(GameTooltip, "GetItem")
        local tooltipItemID = GetItemIDFromLink(tooltipLink)
        if IsItemLink(tooltipLink) and tooltipItemID and tooltipItemID ~= context.itemID then
            debugFeature.frame:Show()
            debugFeature:SetCurrentItem(tooltipLink)
            return
        end

        self:OpenDebugFrameWithItemID(debugFeature, context.itemID)
        return
    end

    if context.transmogSourceID then
        local sourceID = context.transmogSourceID
        if C_TransmogCollection then
            if C_TransmogCollection.GetSourceItemID then
                local sourceItemID = C_TransmogCollection.GetSourceItemID(sourceID)
                if sourceItemID and sourceItemID > 0 then
                    self:OpenDebugFrameWithItemID(debugFeature, sourceItemID)
                    return
                end
            end

            local sourceInfo = self:GetAppearanceSourceInfo(sourceID)
            if sourceInfo then
                local infoItemID = sourceInfo.itemID or sourceInfo.itemId
                if infoItemID and infoItemID > 0 then
                    self:OpenDebugFrameWithItemID(debugFeature, infoItemID)
                    return
                end

                local infoLink = sourceInfo.hyperlink or sourceInfo.link or sourceInfo.itemLink
                if IsItemLink(infoLink) then
                    debugFeature.frame:Show()
                    debugFeature:SetCurrentItem(infoLink)
                    return
                end
            end

            if C_TransmogCollection.GetSourceInfo then
                local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
                if sourceInfo then
                    local infoItemID = sourceInfo.itemID or sourceInfo.itemId
                    if infoItemID and infoItemID > 0 then
                        self:OpenDebugFrameWithItemID(debugFeature, infoItemID)
                        return
                    end
                end
            end
        end
    end

    print("Caerdon Wardrobe: Unable to determine an item link for the hovered element.")
end

function CaerdonAPIMixin:CopyLink(itemLink)
    if not itemLink then return end

    local dialog = StaticPopup_Show("CopyLinkPopup")
    dialog.editBox:SetText(gsub(itemLink, "\124", "\124\124"))
    dialog.editBox:HighlightText()
end

function CaerdonAPIMixin:GetAppearanceSourceInfo(sourceID)
    if not (sourceID and C_TransmogCollection and C_TransmogCollection.GetAppearanceSourceInfo) then
        return nil
    end

    local categoryID, itemAppearanceID, canHaveIllusion, icon, isCollected, itemLink, transmogLink, sourceType, itemSubClass =
        C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
    if not categoryID then
        return nil
    end

    return {
        category = categoryID,
        categoryID = categoryID,
        appearanceID = itemAppearanceID,
        itemAppearanceID = itemAppearanceID,
        canHaveIllusion = canHaveIllusion,
        icon = icon,
        isCollected = isCollected,
        itemLink = itemLink,
        link = itemLink,
        transmoglink = transmogLink,
        hyperlink = transmogLink,
        sourceType = sourceType,
        itemSubClass = itemSubClass,
        sourceID = sourceID
    }
end

function CaerdonAPIMixin:MergeTable(destination, source)
    for k,v in pairs(source) do destination[k] = v end
    return destination
end

-- Leveraging canEquip for now
-- function CaerdonAPIMixin:GetClassArmor()
--     local playerClass, englishClass = UnitClass("player");
--     if (englishClass == "ROGUE" or englishClass == "DRUID" or englishClass == "MONK" or englishClass == "DEMONHUNTER") then
--         classArmor = Enum.ItemArmorSubclass.Leather;
--     elseif (englishClass == "WARRIOR" or englishClass == "PALADIN" or englishClass == "DEATHKNIGHT") then
--         classArmor = Enum.ItemArmorSubclass.Plate;
--     elseif (englishClass == "MAGE" or englishClass == "PRIEST" or englishClass == "WARLOCK") then
--         classArmor = Enum.ItemArmorSubclass.Cloth;
--     elseif (englishClass == "SHAMAN" or englishClass == "HUNTER") then
--         classArmor = Enum.ItemArmorSubclass.Mail;
--     end

--     return classArmor
-- end

function CaerdonAPIMixin:CompareCIMI(feature, item, bag, slot)
    if CaerdonWardrobeConfig.Debug.Enabled and CanIMogIt and not item:IsItemEmpty() and item:GetCaerdonItemType() == CaerdonItemType.Equipment then
        item:ContinueOnItemLoad(function ()
            local itemData = item:GetItemData()
            local transmogInfo = itemData:GetTransmogInfo()
            local isReady, mogStatus, bindingStatus, bindingResult = item:GetCaerdonStatus(feature, { bag = bag, slot = slot })

            local mismatch = true

            local modifiedText, compareText = CanIMogIt:GetTooltipText(item:GetItemLink(), bag, slot)
            if compareText == CanIMogIt.KNOWN or compareText == CanIMogIt.KNOWN_BOE or compareText == CanIMogIt.KNOWN_BY_ANOTHER_CHARACTER or compareText == CanIMogIt.KNOWN_BY_ANOTHER_CHARACTER_BOE or
            compareText == CanIMogIt.KNOWN_BUT_TOO_LOW_LEVEL or compareText == CanIMogIt.KNOWN_BUT_TOO_LOW_LEVEL_BOE then
                if mogStatus == "collected" or mogStatus == "sellable" or mogStatus == "upgrade" or mogStatus == "" then
                    mismatch = false
                end
            elseif compareText == CanIMogIt.KNOWN_FROM_ANOTHER_ITEM_BUT_TOO_LOW_LEVEL or compareText == CanIMogIt.KNOWN_FROM_ANOTHER_ITEM_BUT_TOO_LOW_LEVEL_BOE then
                if mogStatus == "lowSkillPlus" then
                    mismatch = false
                end
            elseif compareText == CanIMogIt.NOT_TRANSMOGABLE or compareText == CanIMogIt.NOT_TRANSMOGABLE_BOE then
                if mogStatus == "collected" or mogStatus == "sellable" or mogStatus == "upgrade" then
                    mismatch = false
                end
            elseif compareText == CanIMogIt.UNKNOWABLE_SOULBOUND then
                if not transmogInfo.needsItem and transmogInfo.otherNeedsItem then
                    if mogStatus == "collected" or mogStatus == "sellable" or mogStatus == "upgrade" then
                        mismatch = false
                    end
                end
            elseif compareText == CanIMogIt.UNKNOWABLE_BY_CHARACTER then
                if mogStatus == "other" or mogStatus == "otherPlus" then
                    mismatch = false
                end
            elseif compareText == CanIMogIt.KNOWN_FROM_ANOTHER_ITEM_AND_CHARACTER or compareText == CanIMogIt.KNOWN_FROM_ANOTHER_ITEM_AND_CHARACTER_BOE then
                if mogStatus == "otherPlus" then
                    mismatch = false
                end
            elseif compareText == CanIMogIt.KNOWN_FROM_ANOTHER_ITEM or compareText == CanIMogIt.KNOWN_FROM_ANOTHER_ITEM_BOE then
                if mogStatus == "ownPlus" or mogStatus == "lowSkill" then
                    mismatch = false
                end
            elseif compareText == CanIMogIt.UNKNOWN then
                if mogStatus == "lowSkill" or mogStatus == "own" then
                    mismatch = false
                end
            elseif compareText == nil then
                print("Caerdon (Debug Mode): Close and reopen bags. CIMI data not yet ready: " .. item:GetItemLink())
                mismatch = false
            else
                print("Caerdon (Debug Mode): CIMI Unknown - " .. item:GetItemLink() .. ": " .. tostring(compareText) .. " vs. " .. mogStatus)
            end

            if mismatch then
                print("Caerdon (Debug Mode): CIMI Mismatch - " .. item:GetItemLink() .. " " .. tostring(compareText) .. " vs. " .. mogStatus)
            end
        end)
    end
end

CaerdonAPI = CreateFromMixins(CaerdonAPIMixin)
CaerdonAPI:OnLoad()
