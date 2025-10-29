local ADDON_NAME, NS = ...
local L = NS.L

local DebugFrameMixin = {}

local MAX_DEBUG_ENTRIES = 50
local cancelFuncs = {}

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
    self.frame:SetResizeBounds(450, 300) -- Set minimum width and height
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
    self.frame.resizeButton:SetScript("OnMouseUp", function()
        self.frame:StopMovingOrSizing()
        -- Update content width to match scroll frame (minus scrollbar width and padding)
        local contentWidth = self.scrollFrame:GetWidth() - 35
        self.content:SetWidth(contentWidth)
        -- Refresh layout after resize
        self:RefreshLayout()
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
        edgeFile = "Interface\Tooltips\UI-Tooltip-Border",
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
                    itemLink = select(2, GetItemInfo(itemID))
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
            PickupItem(self.currentItem)
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


    -- Register slash command
    SLASH_CAERDONDEBUG1 = "/cdebug"
    SlashCmdList["CAERDONDEBUG"] = function(msg)
        self:ToggleDebugFrame()
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

function DebugFrameMixin:SetCurrentItem(itemLink)
    if itemLink then
        self.currentItem = itemLink
        self.currentItemLocation = nil

        -- Create a fresh item object each time
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        if item then
            self:ProcessCurrentItem(item)
        end
    end
end

function DebugFrameMixin:SetCurrentItemFromBagAndSlot(bag, slot)
    if bag == nil or slot == nil then return end
    local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
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
end

function DebugFrameMixin:ClearDebugEntries()
    -- Remove all debug entries
    for _, entry in ipairs(self.debugEntries) do
        entry:Hide()
        entry:ClearAllPoints()
    end

    -- Reset debug entries count
    wipe(self.debugEntries)

    -- Reset content height
    self.infoFrame:SetHeight(1)
    self.content:SetHeight(self.infoFrame:GetHeight())
end

function DebugFrameMixin:RefreshLayout()
    -- Reposition all visible entries based on current frame width
    local numColumns, columnWidth = self:GetColumnLayout()

    for index, entry in ipairs(self.debugEntries) do
        if entry:IsShown() then
            -- Update entry width
            entry:SetWidth(columnWidth)
            entry.value:SetWidth(columnWidth - 170)

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

    -- Update total content height including ensemble container if present
    local totalHeight = self.infoFrame:GetHeight()
    if self.ensembleContainer and self.ensembleContainer:IsShown() then
        totalHeight = totalHeight + 10 + self.ensembleContainer:GetHeight()
    end
    self.content:SetHeight(totalHeight)
end

function DebugFrameMixin:GetColumnLayout()
    -- Determine if we should use two columns based on frame width
    local frameWidth = self.frame:GetWidth()
    local minWidthForTwoColumns = 600 -- Lowered threshold since we have minimum width of 450

    if frameWidth >= minWidthForTwoColumns then
        return 2, (frameWidth - 40) / 2 -- Two columns with some padding
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
        entry.label:SetPoint("TOPLEFT", entry, "TOPLEFT", 10, 0)
        entry.label:SetWidth(150)
        entry.label:SetJustifyH("LEFT")

        entry.value = entry:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        entry.value:SetPoint("TOPLEFT", entry.label, "TOPRIGHT", 10, 0)
        entry.value:SetJustifyH("LEFT")

        self.debugEntries[index] = entry
    end

    local entry = self.debugEntries[index]
    entry:Show()

    -- Get column layout
    local numColumns, columnWidth = self:GetColumnLayout()

    -- Set entry width based on column layout
    entry:SetWidth(columnWidth)
    entry.value:SetWidth(columnWidth - 170) -- Label width + padding

    -- Position entry based on column layout
    if numColumns == 2 then
        -- Two column layout
        local row = math.ceil(index / 2)
        local column = ((index - 1) % 2) + 1

        if index == 1 then
            -- First entry, top left
            entry:SetPoint("TOPLEFT", self.infoFrame, "TOPLEFT", 0, 0)
        elseif column == 1 then
            -- Left column, new row
            entry:SetPoint("TOPLEFT", self.debugEntries[index - 2], "BOTTOMLEFT", 0, -5)
        else
            -- Right column
            if index == 2 then
                -- First entry in right column
                entry:SetPoint("TOPLEFT", self.infoFrame, "TOPLEFT", columnWidth + 10, 0)
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
    self.content:SetHeight(self.infoFrame:GetHeight())

    return entry
end

-- Display only basic item info (icon, name, ID)
function DebugFrameMixin:ShowBasicItemInfo(item)
    -- Update player info display
    local level = UnitLevel("player")
    local specIndex = GetSpecialization()
    local specInfo = ""

    if specIndex then
        local specID, specName = GetSpecializationInfo(specIndex)
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
        self:AddDebugEntry("Item Type", item:GetItemType())
        self:AddDebugEntry("Item SubType", item:GetItemSubType())
        self:AddDebugEntry("Item Type ID", tostring(item:GetItemTypeID()))
        self:AddDebugEntry("Item SubType ID", tostring(item:GetItemSubTypeID()))
        self:AddDebugEntry("Binding", item:GetBinding())
        self:AddDebugEntry("Expansion ID", tostring(item:GetExpansionID()))
        self:AddDebugEntry("Is Crafting Reagent", tostring(item:GetIsCraftingReagent()))
    end

    -- Add specialized info based on item type
    if identifiedType == CaerdonItemType.BattlePet or identifiedType == CaerdonItemType.CompanionPet then
        self:AddPetInfo(item)
    elseif identifiedType == CaerdonItemType.Equipment then
        self:AddTransmogInfo(item)
        self:AddEquipmentInfo(item)
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
        performCopy()
        return
    end

    self.copyCancelFunc = item:ContinueWithCancelOnItemLoad(function()
        performCopy()
        self.copyCancelFunc = nil
    end)
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
    addKV(1, "Class", string.format("%s (%s, ID %s)", className or "Unknown", classFile or "?", tostring(classID or "nil")))

    local specIndex = GetSpecialization()
    local specName
    if specIndex then
        _, specName = GetSpecializationInfo(specIndex)
    end
    addKV(1, "Specialization", specName or "None")

    addKV(1, "Race", UnitRace("player"))
    addKV(1, "Faction", UnitFactionGroup("player"))
    local genderID = UnitSex("player")
    local genderText = genderID == 2 and "Male" or genderID == 3 and "Female" or "Unknown"
    addKV(1, "Gender", genderText .. " (" .. tostring(genderID or "nil") .. ")")

    addLine(0, "")
    addLine(0, "[Item]")
    local itemLink = item:GetItemLink() or self.currentItem
    addKV(1, "Link", itemLink or "Unavailable")
    local itemString = itemLink and itemLink:match("|H(.-)|h")
    addKV(1, "Item String", itemString or "Unavailable")
    addKV(1, "Item ID", item:GetItemID())
    addKV(1, "Item GUID", item:GetItemGUID())

    local infoLink = itemLink or item:GetItemID()
    local itemName, itemLinkFull, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
    itemEquipLoc, itemTexture, sellPrice, classIDInfo, subclassIDInfo, bindType, expansionID, setID, isCraftingReagent

    if infoLink then
        itemName, itemLinkFull, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
        itemEquipLoc, itemTexture, sellPrice, classIDInfo, subclassIDInfo, bindType, expansionID, setID, isCraftingReagent = C_Item.GetItemInfo(infoLink)
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

    addLine(0, "")
    addLine(0, "[Caerdon]")
    local identifiedType = item:GetCaerdonItemType()
    addKV(1, "Identified Type", identifiedType)

    local locationInfo = {
        locationKey = "debugframe-copy-" .. tostring(item:GetItemID() or "unknown"),
        isDebugFrame = true
    }
    local isReady, mogStatus, bindingStatus = item:GetCaerdonStatus(self, locationInfo)
    addKV(1, "Status Ready", isReady)
    addKV(1, "Mog Status", mogStatus)
    addKV(1, "Binding Status", bindingStatus)

    local forDebugUse = item:GetForDebugUse()
    if forDebugUse then
        addTable(1, "For Debug Use", forDebugUse)
    end

    local itemData = item:GetItemData()
    if itemData and itemData.GetTransmogInfo then
        local transmogInfo = itemData:GetTransmogInfo()
        if transmogInfo then
            addLine(0, "")
            addLine(0, "[Transmog Info]")
            addKV(1, "needsItem", transmogInfo.needsItem)
            addKV(1, "otherNeedsItem", transmogInfo.otherNeedsItem)
            addKV(1, "isCompletionistItem", transmogInfo.isCompletionistItem)
            addKV(1, "matchesLootSpec", transmogInfo.matchesLootSpec)
            addKV(1, "hasMetRequirements", transmogInfo.hasMetRequirements)
            addKV(1, "canEquip", transmogInfo.canEquip)
            addKV(1, "isTransmog", transmogInfo.isTransmog)
            addKV(1, "isUpgrade", transmogInfo.isUpgrade)
            addKV(1, "sourceID", transmogInfo.sourceID)
            addKV(1, "appearanceID", transmogInfo.appearanceID)

            if transmogInfo.forDebugUseOnly then
                addTable(1, "forDebugUseOnly", transmogInfo.forDebugUseOnly)
            end
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
                addKV(3, "Item Quality", info.itemQuality and _G[("ITEM_QUALITY%d_DESC"):format(info.itemQuality)] or info.itemQuality)
                addKV(3, "Item Min Level", info.itemMinLevel)
                addKV(3, "Item Type", info.itemType)
                addKV(3, "Item SubType", info.itemSubType)
                addKV(3, "Item Equip Loc", info.itemEquipLoc)
                addKV(3, "Class ID", info.classID)
                addKV(3, "Subclass ID", info.subclassID)

                if info.sources and #info.sources > 0 then
                    addLine(3, "Sources:")
                    for _, source in ipairs(info.sources) do
                        addLine(4, "* Source " .. tostring(source.sourceID) .. " (Visual " .. tostring(source.visualID) .. ", Mod " .. tostring(source.itemModID) .. ")")
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
                            addKV(5, "useErrorType", tostring(source.useErrorType) .. " (" .. self:GetTransmogUseErrorTypeName(source.useErrorType) .. ")")
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
    frame.instruction:SetText("Text is highlighted automatically. Press Ctrl-C (Cmd-C on Mac) to copy, then Ctrl-V to paste it into chat or a note.")

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
    frame.editBox:SetSpacing(4)
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
    frame.editBox:SetText(payload or "")
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

function DebugFrameMixin:AddTransmogInfo(item)
    if not item then
        self:AddDebugEntry("Transmog Info", "Item is nil")
        return
    end

    -- Get transmog info using the WoW API directly
    local itemLink = item:GetItemLink()
    if not itemLink then
        self:AddDebugEntry("Transmog Info", "No item link available")
        return
    end

    local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemLink)

    if not appearanceID then
        -- Try with item ID as fallback
        local itemID = item:GetItemID()
        if itemID then
            appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemID)
        end
    end

    if appearanceID then
        self:AddDebugEntry("Appearance ID", tostring(appearanceID))
        self:AddDebugEntry("Source ID", tostring(sourceID))

        -- Check if collected
        local isCollected = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID)
        self:AddDebugEntry("Is Collected", tostring(isCollected))

        -- Get source info
        local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
        if sourceInfo then
            self:AddDebugEntry("Is Known", tostring(sourceInfo.isCollected))
            self:AddDebugEntry("Item ID", tostring(sourceInfo.itemID))
            self:AddDebugEntry("Item Mod ID", tostring(sourceInfo.itemModID))
            self:AddDebugEntry("Visual ID", tostring(sourceInfo.visualID))
        end
    else
        self:AddDebugEntry("Transmog Info", "Not available for this item")
    end
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
    if itemData and itemData.GetTransmogInfo then
        local transmogInfo = itemData:GetTransmogInfo()
        if transmogInfo then
            -- Add detailed transmog information
            if transmogInfo.needsItem ~= nil then
                self:AddDebugEntry("Needs Item", tostring(transmogInfo.needsItem))
            end
            if transmogInfo.otherNeedsItem ~= nil then
                self:AddDebugEntry("Other Needs Item", tostring(transmogInfo.otherNeedsItem))
            end
            if transmogInfo.isCompletionistItem ~= nil then
                self:AddDebugEntry("Is Completionist Item", tostring(transmogInfo.isCompletionistItem))
            end
            if transmogInfo.matchesLootSpec ~= nil then
                self:AddDebugEntry("Matches Loot Spec", tostring(transmogInfo.matchesLootSpec))
            end
            if transmogInfo.hasMetRequirements ~= nil then
                self:AddDebugEntry("Has Met Requirements", tostring(transmogInfo.hasMetRequirements))
            end
            if transmogInfo.canEquip ~= nil then
                self:AddDebugEntry("Can Equip", tostring(transmogInfo.canEquip))
            end

            -- Add item min level
            local minLevel = item:GetMinLevel()
            if minLevel then
                self:AddDebugEntry("Item Min Level", tostring(minLevel))
            end

            -- Check for matched sources
            local matchedSources = transmogInfo.forDebugUseOnly and transmogInfo.forDebugUseOnly.matchedSources
            if matchedSources and #matchedSources > 0 then
                for k, v in pairs(matchedSources) do
                    self:AddDebugEntry("Matched Source", v.name)
                end
            else
                self:AddDebugEntry("Matched Source", "false")
            end

            -- Check appearance info from debug data
            local appearanceInfo = transmogInfo.forDebugUseOnly and transmogInfo.forDebugUseOnly.appearanceInfo
            if appearanceInfo then
                self:AddDebugEntry("Appearance Collected", tostring(appearanceInfo.appearanceIsCollected))
                self:AddDebugEntry("Source Collected", tostring(appearanceInfo.sourceIsCollected))
                self:AddDebugEntry("Is Conditionally Known", tostring(appearanceInfo.sourceIsCollectedConditional))
                self:AddDebugEntry("Is Permanently Known", tostring(appearanceInfo.sourceIsCollectedPermanent))
                self:AddDebugEntry("Has Non-level Reqs", tostring(appearanceInfo.appearanceHasAnyNonLevelRequirements))
                self:AddDebugEntry("Meets Non-level Reqs", tostring(appearanceInfo.appearanceMeetsNonLevelRequirements))
                self:AddDebugEntry("Appearance Is Usable", tostring(appearanceInfo.appearanceIsUsable))
                self:AddDebugEntry("Meets Condition", tostring(appearanceInfo.meetsTransmogPlayerCondition))
            end
        end
    end
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
    for _, itemInfo in ipairs(itemDetails) do
        for _, sourceID in ipairs(sourceIDs) do
            local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
            if sourceInfo and sourceInfo.itemID == itemInfo.itemID then
                local hasItemData, canCollect = C_TransmogCollection.PlayerCanCollectSource(sourceID)
                local accountHasItemData, accountCanCollect = C_TransmogCollection.AccountCanCollectSource(sourceID)
                local appearanceInfo = C_TransmogCollection.GetAppearanceInfoBySource(sourceID)

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
                    appearanceInfo = appearanceInfo and CopyTable(appearanceInfo) or nil
                }

                table.insert(itemInfo.sources, sourceDetail)
            end
        end
    end

    if self.currentEnsembleData then
        self.currentEnsembleData.items = itemDetails
        self.currentEnsembleData.totalItems = #itemDetails
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
    self.ensembleContainer:SetPoint("TOPLEFT", self.infoFrame, "BOTTOMLEFT", 0, -10)
    self.ensembleContainer:SetPoint("TOPRIGHT", self.infoFrame, "BOTTOMRIGHT", 0, -10)

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

    -- Update content height to include ensemble container
    local totalHeight = self.infoFrame:GetHeight() + 10 + self.ensembleContainer:GetHeight()
    self.content:SetHeight(totalHeight)
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

    local categoryID = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
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
                PickupItem(self.itemLink)
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
        local r, g, b = GetItemQualityColor(itemInfo.itemQuality)
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

    -- Update total content height
    local totalHeight = self.infoFrame:GetHeight() + 10 + self.ensembleContainer:GetHeight()
    self.content:SetHeight(totalHeight)
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

        if recipeInfo.spellID then
            self:AddDebugEntry("Recipe Spell ID", tostring(recipeInfo.spellID))
        end
        if recipeInfo.name then
            self:AddDebugEntry("Recipe Name", recipeInfo.name)
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

        -- Clear everything to force a complete refresh
        self.currentItem = nil
        self:ClearDebugDisplay()

        -- Set the item again to trigger a full reload
        self:SetCurrentItem(itemLink)
    end
end

function DebugFrameMixin:GetTooltipData(item, locationInfo)
    -- Not needed for debug frame
    return {}
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
