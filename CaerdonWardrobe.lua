-- EQUIPPED_LAST=500 -- TODO: Temp fix for bag opening

local DEBUG_ENABLED = false
-- local DEBUG_ITEM = 82800
local ADDON_NAME, NS = ...
local L = NS.L
local isHousingSupported = select(4, GetBuildInfo()) >= 110207 and Enum and Enum.ItemClass and
    Enum.ItemClass.Housing ~= nil

BINDING_HEADER_CAERDON = L["Caerdon Addons"]
BINDING_NAME_COPYMOUSEOVERLINK = L["Copy Mouseover Link"]
BINDING_NAME_PRINTMOUSEOVERLINKDETAILS = L["Print Mouseover Link Details"]
BINDING_NAME_CAERDONDEBUGHOVER = L["Open Debug for Hovered Item"]

local availableFeatures = {}
local registeredFeatures = {}

CaerdonWardrobeMixin = {}

local buttonState = setmetatable({}, { __mode = "k" })

local function GetButtonState(originalButton, create)
    if not originalButton then
        return nil
    end

    local state = buttonState[originalButton]
    if not state and create then
        state = {}
        buttonState[originalButton] = state
    end

    return state
end

function CaerdonWardrobeMixin:GetCaerdonButton(originalButton)
    local state = GetButtonState(originalButton)
    return state and state.caerdonButton
end

function CaerdonWardrobeMixin:EnsureCaerdonButton(originalButton)
    local state = GetButtonState(originalButton, true)
    if not state.caerdonButton then
        local frame = CreateFrame("Frame", nil, originalButton)
        frame.searchOverlay = originalButton.searchOverlay
        state.caerdonButton = frame
    end

    return state.caerdonButton
end

function CaerdonWardrobeMixin:SetButtonLocationKey(originalButton, locationKey)
    local state = GetButtonState(originalButton, locationKey ~= nil)
    if state then
        state.locationKey = locationKey
    end
end

function CaerdonWardrobeMixin:GetButtonLocationKey(originalButton)
    local state = GetButtonState(originalButton)
    return state and state.locationKey
end

function CaerdonWardrobeMixin:SetButtonItemID(originalButton, itemID)
    local state = GetButtonState(originalButton, itemID ~= nil)
    if state then
        state.itemID = itemID
    end
end

function CaerdonWardrobeMixin:GetButtonItemID(originalButton)
    local state = GetButtonState(originalButton)
    return state and state.itemID
end

function CaerdonWardrobeMixin:ClearButtonState(originalButton)
    local state = GetButtonState(originalButton)
    if state then
        state.locationKey = nil
        state.itemID = nil
    end
end

function CaerdonWardrobeMixin:OnLoad()
    -- AddonCompartmentFrame:RegisterAddon({
    -- 	text = 'Caerdon Wardrobe',
    -- 	func = function ()
    -- 		print("Do your thing here")
    -- 	end,
    -- 	icon = "Interface\\Store\\category-icon-featured"
    -- })

    self.waitingToProcess = {}
    self.featureProcessContinuables = {}
    self.featureProcessItems = {}

    self:RegisterEvent "ADDON_LOADED"
    self:RegisterEvent "PLAYER_LOGOUT"
    self:RegisterEvent "PLAYER_ENTERING_WORLD"
    self:RegisterEvent "TRANSMOG_COLLECTION_UPDATED"
    self:RegisterEvent "EQUIPMENT_SETS_CHANGED"
    self:RegisterEvent "UPDATE_EXPANSION_LEVEL"
    self:RegisterEvent "VARIABLES_LOADED"
    if isHousingSupported then
        self:RegisterEvent "HOUSING_STORAGE_ENTRY_UPDATED"
        self:RegisterEvent "HOUSING_STORAGE_UPDATED"
        self:RegisterEvent "HOUSE_DECOR_ADDED_TO_CHEST"
        self:RegisterEvent "DYE_COLOR_UPDATED"
        self:RegisterEvent "DYE_COLOR_CATEGORY_UPDATED"
    end

    hooksecurefunc("EquipPendingItem", function(...) self:OnEquipPendingItem(...) end)
end

-- TODO: Pretty sure I don't need to do this... get setID from GetItemInfo?
local function IsGearSetStatus(status, item)
    return status and status ~= "" and status ~= L["BoA"] and status ~= L["BoE"]
end

local ICON_PROMINENT_SIZE = 20
local ICON_SIZE_DIFFERENTIAL = 0.8

function CaerdonWardrobeMixin:SetStatusIconPosition(icon, button, item, feature, locationInfo, options, mogStatus,
                                                    bindingStatus)
    if not item then return end

    local caerdonButton = self:GetCaerdonButton(button)
    if not caerdonButton then
        return
    end

    -- Scaling values if the icon is different than prominent-sized
    local iconWidth, iconHeight = icon:GetSize()
    local xAdjust = iconWidth / ICON_PROMINENT_SIZE
    local yAdjust = iconHeight / ICON_PROMINENT_SIZE

    local statusScale = options.statusScale or 1
    local statusPosition = options.overrideStatusPosition or CaerdonWardrobeConfig.Icon.Position
    local xOffset = 4 * xAdjust
    if statusPosition == "TOP" or statusPosition == "BOTTOM" then
        xOffset = 0
    end

    if options.statusOffsetX ~= nil then
        xOffset = options.statusOffsetX
    end

    local yOffset = 4 * yAdjust
    if statusPosition == "LEFT" or statusPosition == "RIGHT" then
        yOffset = 0
    end

    if options.statusOffsetY ~= nil then
        yOffset = options.statusOffsetY
    end

    if string.find(statusPosition, "TOP") then
        yOffset = yOffset * -1
    end

    if string.find(statusPosition, "RIGHT") then
        xOffset = xOffset * -1
    end

    local xBackgroundOffset = 0
    if options.statusBackgroundOffsetX ~= nil then
        xBackgroundOffset = options.statusBackgroundOffsetX
    end

    local yBackgroundOffset = 0
    if options.statusBackgroundOffsetY ~= nil then
        yBackgroundOffset = options.statusBackgroundOffsetY
    end

    local background = icon.mogStatusBackground
    if background then
        local parent = icon:GetParent()
        if parent and background:GetParent() ~= parent then
            background:SetParent(parent)
        end
    end
    if not options.fixedStatusPosition then
        if background then
            background:ClearAllPoints()
            background:SetPoint("CENTER", caerdonButton, statusPosition, xOffset + xBackgroundOffset,
                yOffset + yBackgroundOffset)
        end

        icon:ClearAllPoints()
        icon:SetPoint("CENTER", caerdonButton, statusPosition, xOffset, yOffset)
    elseif background then
        background:ClearAllPoints()
        background:SetPoint("CENTER", icon)
    end
end

function CaerdonWardrobeMixin:AddRotation(group, order, degrees, duration, smoothing, startDelay, endDelay)
    local anim = group:CreateAnimation("Rotation")
    group["anim" .. order] = anim
    anim:SetDegrees(degrees)
    anim:SetDuration(duration)
    anim:SetOrder(order)
    anim:SetSmoothing(smoothing)

    if startDelay then
        anim:SetStartDelay(startDelay)
    end

    if endDelay then
        anim:SetEndDelay(endDelay)
    end
end

function CaerdonWardrobeMixin:SetItemButtonMogStatusFilter(originalButton, isFiltered)
    local caerdonButton = self:GetCaerdonButton(originalButton)
    if caerdonButton then
        local mogStatus = caerdonButton.mogStatus
        if mogStatus then
            local mogStatusBackground = mogStatus.mogStatusBackground
            if not mogStatus:IsShown() then
                if mogStatusBackground then
                    mogStatusBackground:SetAlpha(0)
                end
                mogStatus:SetAlpha(0)
                mogStatus:SetDesaturated(false)
                return
            end

            local assignedAlpha = mogStatus.assignedAlpha or 1.0

            if isFiltered then
                mogStatusBackground:SetAlpha(0.3)
                mogStatus:SetAlpha(0.3)
            else
                mogStatusBackground:SetAlpha(assignedAlpha)
                mogStatus:SetAlpha(assignedAlpha)
            end
        end

        local bindsOnText = caerdonButton.bindsOnText
        if bindsOnText then
            if isFiltered then
                bindsOnText:SetAlpha(0.3)
            else
                bindsOnText:SetAlpha(1.0)
            end
        end

        local upgradeDeltaText = caerdonButton.upgradeDeltaText
        if upgradeDeltaText then
            if isFiltered then
                upgradeDeltaText:SetAlpha(0.3)
            else
                upgradeDeltaText:SetAlpha(1.0)
            end
        end
    end
end

function CaerdonWardrobeMixin:SetupCaerdonButton(originalButton, item, feature, locationInfo, options)
    if not originalButton then
        return
    end

    local button = self:GetCaerdonButton(originalButton)
    local createdNew = false
    if not button then
        button = self:EnsureCaerdonButton(originalButton)
        createdNew = true
    end

    if not button.mogStatus then
        local mogStatusBackground = button:CreateTexture(nil, "ARTWORK", nil, 1)
        local mogStatus = button:CreateTexture(nil, "ARTWORK", nil, 2)
        mogStatus.mogStatusBackground = mogStatusBackground
        button.mogStatus = mogStatus

        mogStatusBackground:SetAlpha(0)
        mogStatusBackground:Hide()
        mogStatus:SetAlpha(0)
        mogStatus:Hide()

        if not mogStatus._caerdonBackgroundHooked then
            mogStatus:HookScript("OnHide", function(statusTexture)
                local background = statusTexture.mogStatusBackground
                if background then
                    background._caerdonPrevAlpha = background:GetAlpha()
                    background:SetAlpha(0)
                    background:Hide()
                end
            end)
            mogStatus:HookScript("OnShow", function(statusTexture)
                local background = statusTexture.mogStatusBackground
                if background then
                    background:Show()
                    local alpha = background._caerdonPrevAlpha
                    if alpha == nil or alpha == 0 then
                        alpha = statusTexture:GetAlpha()
                    end
                    if (alpha == nil or alpha == 0) then
                        alpha = statusTexture.assignedAlpha or 1
                    end
                    background:SetAlpha(alpha)
                    background._caerdonPrevAlpha = nil
                end
            end)
            mogStatus._caerdonBackgroundHooked = true
        end
    end

    if not button.bindsOnText then
        button.bindsOnText = button:CreateFontString(nil, "ARTWORK", "SystemFont_Outline_Small") -- TODO: Note: placing directly on button to enable search fade - need to check on other addons
    end

    if not button.upgradeDeltaText then
        button.upgradeDeltaText = button:CreateFontString(nil, "ARTWORK", "NumberFontNormalSmall")
        button.upgradeDeltaText:SetPoint("BOTTOMRIGHT", originalButton, "BOTTOMRIGHT", -2, 2)
        button.upgradeDeltaText:SetText("")
        button.upgradeDeltaText:Hide()
    end

    if not button.housingCountText then
        button.housingCountText = button:CreateFontString(nil, "ARTWORK", "NumberFontNormalSmall")
        button.housingCountText:SetText("")
        button.housingCountText:Hide()
    end

    return button, createdNew
end

function CaerdonWardrobeMixin:SetItemButtonStatus(originalButton, item, feature, locationInfo, options, status,
                                                  bindingStatus, transmogInfo)
    local caerdonButton = self:GetCaerdonButton(originalButton)
    if not caerdonButton then
        return
    end

    -- Make sure it's sitting in front of the frame it's going to overlay
    local levelCheckFrame = originalButton
    if options and options.relativeFrame then
        if options.relativeFrame:GetObjectType() == "Texture" then
            levelCheckFrame = options.relativeFrame:GetParent()
        else
            levelCheckFrame = options.relativeFrame
        end
    end
    if levelCheckFrame then
        caerdonButton:SetFrameStrata(levelCheckFrame:GetFrameStrata())
        caerdonButton:SetFrameLevel(levelCheckFrame:GetFrameLevel() + 1)
    end

    caerdonButton:ClearAllPoints()
    caerdonButton:SetSize(0, 0)

    if options and options.relativeFrame then
        caerdonButton:SetAllPoints(options.relativeFrame)
    else
        caerdonButton:SetAllPoints(originalButton)
    end

    -- Had some addons messing with frame level resulting in this getting covered by the parent button.
    -- Haven't seen any negative issues with bumping it up, yet, but keep an eye on it if
    -- the status icon overlaps something it shouldn't.
    -- NOTE: Added logic above that hopefully addresses this more sanely...
    -- button:SetFrameLevel(originalButton:GetFrameLevel() + 100)

    local iconBackgroundAdjustment = 0
    local mogStatus = caerdonButton.mogStatus
    local mogStatusBackground
    if mogStatus then
        mogStatusBackground = mogStatus.mogStatusBackground
    end
    local mogAnim = caerdonButton.mogAnim
    local upgradeDeltaText = caerdonButton.upgradeDeltaText
    if upgradeDeltaText then
        upgradeDeltaText:SetText("")
        upgradeDeltaText:Hide()
    end
    if caerdonButton.housingCountText then
        caerdonButton.housingCountText:SetText("")
        caerdonButton.housingCountText:Hide()
    end

    if not options then
        options = {}
    end

    if not status then
        if mogAnim and mogAnim:IsPlaying() then
            mogAnim:Stop()
        end
        if mogStatusBackground then
            mogStatusBackground:SetVertexColor(1, 1, 1)
            mogStatusBackground:SetTexture(nil)
            mogStatusBackground:SetAlpha(0)
            mogStatusBackground:Hide()
        end
        if mogStatus then
            mogStatus:SetVertexColor(1, 1, 1)
            mogStatus:SetTexture(nil)
            mogStatus:SetAlpha(0)
            mogStatus:SetDesaturated(false)
            mogStatus.assignedAlpha = 0
            mogStatus:Hide()
        end
        if upgradeDeltaText then
            upgradeDeltaText:Hide()
        end
        if caerdonButton.housingCountText then
            caerdonButton.housingCountText:SetText("")
            caerdonButton.housingCountText:Hide()
        end
        return
    end

    local itemData = item and item.GetItemData and item:GetItemData()
    local sameLevelBehavior = CaerdonWardrobeConfig.Icon.SameLevelBehavior or "none"
    local showNeutralSameLevel = sameLevelBehavior == "neutral"
    local allowMismatchedSpecUpgrades = CaerdonWardrobeConfig.Icon.ShowMismatchedSpecUpgrades == true
    local equipmentSets = itemData and itemData.GetEquipmentSets and itemData:GetEquipmentSets()
    local isEquipmentSetItem = equipmentSets and #equipmentSets > 0
    local showGearSetText = isEquipmentSetItem and bindingStatus and IsGearSetStatus(bindingStatus, item) and
        CaerdonWardrobeConfig.Binding.ShowGearSets
    local bindingAnchor = (options and options.overrideBindingPosition) or CaerdonWardrobeConfig.Binding.Position
    caerdonButton.bindingBottomPadding = 0
    local deltaAnchorFrame = (options and options.relativeFrame) or originalButton

    -- local mogFlash = caerdonButton.mogFlash
    -- if not mogFlash then
    -- 	mogFlash = caerdonButton:CreateTexture(nil, "OVERLAY")
    -- 	mogFlash:SetAlpha(0)
    -- 	mogFlash:SetBlendMode("ADD")
    -- 	mogFlash:SetAtlas("bags-glow-flash", true)
    -- 	mogFlash:SetPoint("CENTER")

    -- 	caerdonButton.mogFlash = mogFlash
    -- end

    local upgradeDeltaShown = false

    local function ShowUpgradeDeltaText(r, g, b)
        if not upgradeDeltaText or not transmogInfo or not CaerdonWardrobeConfig.Icon.ShowUpgradeLevelDelta then
            return
        end

        local delta = transmogInfo.upgradeItemLevelDelta
        if not delta or delta <= 0 then
            return
        end

        local baseYOffset = 2
        if caerdonButton then
            caerdonButton.upgradeDeltaBaseYOffset = baseYOffset
            caerdonButton.upgradeDeltaAnchor = deltaAnchorFrame
        end
        upgradeDeltaText:SetFormattedText("+%d", delta)
        if r then
            upgradeDeltaText:SetTextColor(r, g, b)
        else
            upgradeDeltaText:SetTextColor(0.2, 1.0, 0.2)
        end
        upgradeDeltaText:SetAlpha(1.0)
        upgradeDeltaText:Show()
        self:UpdateUpgradeDeltaPosition(originalButton)
        upgradeDeltaShown = true
    end

    local function ApplyUpgradeArrowColor(defaultR, defaultG, defaultB)
        if transmogInfo and transmogInfo.upgradeMatchesSpec == false and allowMismatchedSpecUpgrades then
            mogStatus:SetVertexColor(1, 0.35, 0.35)
        elseif transmogInfo and transmogInfo.pawnIdentifiedUpgrade then
            mogStatus:SetVertexColor(1, 1, 0)
        else
            mogStatus:SetVertexColor(defaultR, defaultG, defaultB)
        end
    end

    local showAnim = false
    if status == "waiting" then
        showAnim = true

        if mogAnim and not caerdonButton.isWaitingIcon then
            if mogAnim:IsPlaying() then
                mogAnim:Finish()
            end

            mogAnim = nil
            caerdonButton.mogAnim = nil
            caerdonButton.isWaitingIcon = false
        end

        if not mogAnim or not caerdonButton.isWaitingIcon then
            mogAnim = mogStatus:CreateAnimationGroup()

            self:AddRotation(mogAnim, 1, 360, 0.5, "IN_OUT")

            mogAnim:SetLooping("REPEAT")
            caerdonButton.mogAnim = mogAnim
            caerdonButton.isWaitingIcon = true
        end
    else
        if status == "readyToCombine" or status == "own" or status == "ownPlus" or status == "otherSpec" or status == "otherSpecPlus" or status == "refundable" or status == "openable" or status == "locked" or status == "upgradeNonEquipment" or status == "readyToCombine" then
            showAnim = true

            if mogAnim and caerdonButton.isWaitingIcon then
                if mogAnim:IsPlaying() then
                    mogAnim:Finish()
                end

                mogAnim = nil
                caerdonButton.mogAnim = nil
                caerdonButton.isWaitingIcon = false
            end

            if not mogAnim then
                mogAnim = mogStatus:CreateAnimationGroup()

                if status == "readyToCombine" then
                    self:AddRotation(mogAnim, 1, 360, 0.75, "NONE")
                else
                    self:AddRotation(mogAnim, 1, 110, 0.2, "OUT")
                    self:AddRotation(mogAnim, 2, -155, 0.2, "OUT")
                    self:AddRotation(mogAnim, 3, 60, 0.2, "OUT")
                    self:AddRotation(mogAnim, 4, -15, 0.1, "OUT", 0, 2)
                end

                mogAnim:SetLooping("REPEAT")
                caerdonButton.mogAnim = mogAnim
                caerdonButton.isWaitingIcon = false
            end
        else
            showAnim = false
        end
    end

    -- 	if not mogAnim then
    -- 		mogAnim = button:CreateAnimationGroup()
    -- 		mogAnim:SetToFinalAlpha(true)
    -- 		mogAnim.alpha1 = mogAnim:CreateAnimation("Alpha")
    -- 		mogAnim.alpha1:SetChildKey("mogFlash")
    -- 		mogAnim.alpha1:SetSmoothing("OUT");
    -- 		mogAnim.alpha1:SetDuration(0.6)
    -- 		mogAnim.alpha1:SetOrder(1)
    -- 		mogAnim.alpha1:SetFromAlpha(1);
    -- 		mogAnim.alpha1:SetToAlpha(0);

    -- 		caerdonButton.mogAnim = mogAnim
    -- 	end

    if mogStatusBackground then
        mogStatusBackground:Show()
    end
    if mogStatus then
        mogStatus:Show()
    end

    local displayInfo
    if feature then
        displayInfo = feature:GetDisplayInfoInternal(button, item, feature, locationInfo, options, mogStatus,
            bindingStatus)
    end
    local equipLocation = item and item.GetEquipLocation and item:GetEquipLocation()
    local isTabard = equipLocation == "INVTYPE_TABARD"
    local isShirt = equipLocation == "INVTYPE_BODY"
    local globalUpgradeEnabled = CaerdonWardrobeConfig.Icon.ShowUpgradeIcon ~= false
    local upgradeSlotAvailable = displayInfo and displayInfo.upgradeIcon.shouldShow and not isEquipmentSetItem and
        not isTabard
    local shouldShowUpgradeIcon = globalUpgradeEnabled and upgradeSlotAvailable
    local canEquipForNeutral = transmogInfo and
        ((transmogInfo.canEquipForPlayer ~= nil and transmogInfo.canEquipForPlayer) or transmogInfo.canEquip)

    local alpha = 1

    mogStatusBackground:SetVertexColor(1, 1, 1)
    mogStatusBackground:SetTexCoord(0, 1, 0, 1)
    mogStatusBackground:SetTexture("")

    mogStatus:SetVertexColor(1, 1, 1)
    mogStatus:SetTexCoord(0, 1, 0, 1)
    mogStatus:SetTexture("")

    local isProminent = false
    local caerdonType = item and item.GetCaerdonItemType and item:GetCaerdonItemType()
    local housingInfo = (caerdonType == CaerdonItemType.Housing and item:GetItemData() and item:GetItemData():GetHousingInfo()) or
        nil

    -- TODO: Possible gear set indicators
    -- MINIMAP / TempleofKotmogu_ball_cyan.PNG
    -- TempleofKotmogu_ball_green.PNG
    -- TempleofKotmogu_ball_orange.PNG
    -- TempleofKotmogu_ball_purple.PNG
    -- MINIMAP/TRACKING/OBJECTICONS.PNG

    if item and item.extraData and item.extraData.recipeInfo then
        -- TODO: Marking recipe skill ups here for now... need to figure out how to refactor
        if item.extraData.recipeInfo.firstCraft then
            iconBackgroundAdjustment = 2
            mogStatusBackground:SetTexCoord(91 / 1024, (91 + 30) / 1024, 987 / 1024, (987 + 30) / 1024)
            mogStatusBackground:SetTexture("Interface\\Store\\ServicesAtlas")
        end
    end

    -- TODO: Add options to hide these statuses
    if status == "refundable" then
        alpha = 0.9
        mogStatus:SetTexture("Interface\\COMMON\\mini-hourglass")
    elseif status == "openable" then
        isProminent = true
        mogStatus:SetTexCoord(16 / 64, 48 / 64, 16 / 64, 48 / 64)
        mogStatus:SetTexture("Interface\\Store\\category-icon-free")
    elseif status == "readable" then
        mogStatus:SetTexCoord(16 / 64, 48 / 64, 16 / 64, 48 / 64)
        mogStatus:SetTexture("Interface\\Store\\category-icon-services")
    elseif status == "lowSkill" or status == "lowSkillPlus" then
        mogStatus:SetTexCoord(6 / 64, 58 / 64, 6 / 64, 58 / 64)
        mogStatus:SetTexture("Interface\\WorldMap\\Gear_64Grey")
        if status == "lowSkillPlus" then
            mogStatus:SetVertexColor(0.4, 1, 0)
        end
        -- mogStatus:SetTexture("Interface\\QUESTFRAME\\SkillUp-BG")
        -- mogStatus:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
        -- mogStatus:SetTexture("Interface\\Buttons\\JumpUpArrow")
    elseif status == "upgradeNonEquipment" then
        isProminent = false
        iconBackgroundAdjustment = 4
        mogStatusBackground:SetTexCoord((512 - 46 - 31) / 512, (512 - 31) / 512, 5 / 512, (5 + 46) / 512)
        mogStatusBackground:SetTexture("Interface\\HUD\\UIUnitFrameBoss2x")
        mogStatusBackground:SetVertexColor(0, 1, 1)

        mogStatus:SetTexCoord(-1 / 32, 33 / 32, -1 / 32, 33 / 32)
        mogStatus:SetTexture("Interface\\Buttons\\JumpUpArrow")
    elseif status == "upgrade" then
        isProminent = false
        if shouldShowUpgradeIcon then
            iconBackgroundAdjustment = 4
            mogStatusBackground:SetTexCoord((512 - 46 - 31) / 512, (512 - 31) / 512, 5 / 512, (5 + 46) / 512)
            mogStatusBackground:SetTexture("Interface\\HUD\\UIUnitFrameBoss2x")
            mogStatusBackground:SetVertexColor(0, 1, 1)

            mogStatus:SetTexCoord(-1 / 32, 33 / 32, -1 / 32, 33 / 32)
            mogStatus:SetTexture("Interface\\Buttons\\JumpUpArrow")
            ApplyUpgradeArrowColor(0.4, 1, 0.2)
            ShowUpgradeDeltaText()
        end
    elseif status == "upgradeLowSkill" then
        isProminent = false
        if shouldShowUpgradeIcon then
            iconBackgroundAdjustment = 4
            mogStatusBackground:SetTexCoord((512 - 46 - 31) / 512, (512 - 31) / 512, 5 / 512, (5 + 46) / 512)
            mogStatusBackground:SetTexture("Interface\\HUD\\UIUnitFrameBoss2x")
            mogStatusBackground:SetVertexColor(0.4, 1, 0)

            mogStatus:SetTexCoord(-1 / 32, 33 / 32, -1 / 32, 33 / 32)
            mogStatus:SetTexture("Interface\\Buttons\\JumpUpArrow")
            ApplyUpgradeArrowColor(0.4, 1, 0.2)
            ShowUpgradeDeltaText(0.9, 0.82, 0.1)
        end
    elseif status == "locked" then
        isProminent = true
        mogStatus:SetTexCoord(16 / 64, 48 / 64, 16 / 64, 48 / 64)
        mogStatus:SetTexture("Interface\\Store\\category-icon-key")
    elseif status == "oldexpansion" and displayInfo and displayInfo.oldExpansionIcon.shouldShow then
        alpha = 0.9
        mogStatus:SetTexCoord(16 / 64, 48 / 64, 16 / 64, 48 / 64)
        mogStatus:SetTexture("Interface\\Store\\category-icon-wow")
    elseif status == "needForProfession" then
        -- TODO: Need to improve to pass data for icon determination.
        isProminent = true
        if displayInfo and displayInfo.ownIcon.shouldShow then
            mogStatus:SetTexCoord(16 / 64, 48 / 64, 16 / 64, 48 / 64)
            mogStatus:SetTexture("Interface\\Store\\category-icon-featured")
            -- mogStatus:SetTexture("Interface\\WorldMap\\worldquest-icon-enchanting")
        end
    elseif status == "canCombine" then
        -- isProminent = true
        if displayInfo and displayInfo.ownIcon.shouldShow then -- TODO: Add separate config for combine icon
            -- mogStatus:SetTexCoord(16/64, 48/64, 16/64, 48/64)
            -- mogStatus:SetTexture("Interface\\PaperDollInfoFrame\\Character-Plus")
            -- mogStatus:SetTexture("Interface\\BUTTONS\\UI-PlusButton-Up")

            -- options.statusProminentSize = 256

            -- mogStatus:SetTexCoord((512-23)/512, (512-7)/512, (172-18)/512, (172-3)/512)
            -- mogStatus:SetTexture("Interface\\QUESTFRAME\\WorldQuest")

            mogStatus:SetTexCoord(91 / 1024, (91 + 30) / 1024, 987 / 1024, (987 + 30) / 1024)
            mogStatus:SetTexture("Interface\\Store\\ServicesAtlas")

            -- if status == "ownPlus" then
            -- 	mogStatus:SetVertexColor(0.4, 1, 0)
            -- end
        end
    elseif status == "readyToCombine" then
        -- isProminent = true
        if displayInfo and displayInfo.ownIcon.shouldShow then -- TODO: Add separate config for combine icon
            -- alpha = 0.9

            -- mogStatus:SetTexCoord((512-23)/512, (512-7)/512, 172/512, (172+15)/512)
            -- mogStatus:SetTexture("Interface\\QUESTFRAME\\WorldQuest")

            iconBackgroundAdjustment = 4

            -- mogStatusBackground:SetTexCoord(455/512, (455+28)/512, 1/256, (1+28)/256)
            -- mogStatusBackground:SetTexture("Interface\\Store\\Shop")

            -- mogStatusBackground:SetTexCoord(180/512, (180+46)/512, 5/512, (5+46)/512)
            mogStatusBackground:SetTexCoord((512 - 46 - 31) / 512, (512 - 31) / 512, 5 / 512, (5 + 46) / 512)
            mogStatusBackground:SetTexture("Interface\\HUD\\UIUnitFrameBoss2x")
            -- mogStatusBackground:SetVertexColor(0, 1, 0)
            mogStatusBackground:SetVertexColor(80 / 256, 252 / 256, 80 / 256, 253 / 256)

            mogStatus:SetTexCoord(305 / 512, (305 + 116) / 512, 141 / 512, (141 + 116) / 512)
            mogStatus:SetTexture("Interface\\Animations\\PowerSwirlAnimation")
            -- mogStatus:SetVertexColor(0, 1, 0)
            mogStatus:SetVertexColor(80 / 256, 252 / 256, 80 / 256, 253 / 256)

            -- mogStatus:SetTexCoord(16/64, 48/64, 16/64, 48/64)
            -- mogStatus:SetTexture("Interface\\HELPFRAME\\ReportLagIcon-AuctionHouse")

            -- if status == "ownPlus" then
            -- 	mogStatus:SetVertexColor(0.4, 1, 0)
            -- end
        end
    elseif status == "housingOwned" then
        isProminent = true
        iconBackgroundAdjustment = 2

        local housingIconSet = false
        if housingInfo then
            if housingInfo.iconAtlas and mogStatus.SetAtlas then
                mogStatus:SetAtlas(housingInfo.iconAtlas, false)
                mogStatus:SetTexCoord(0, 1, 0, 1)
                housingIconSet = true
            elseif housingInfo.iconTexture then
                mogStatus:SetTexture(housingInfo.iconTexture)
                housingIconSet = true
            end
        end

        if not housingIconSet then
            mogStatus:SetTexCoord(16 / 64, 48 / 64, 16 / 64, 48 / 64)
            mogStatus:SetTexture("Interface\\Store\\category-icon-featured")
        end

        local countWidget = caerdonButton.housingCountText
        if countWidget and housingInfo then
            -- Always show total owned for housing, even if showQuantity is false.
            if housingInfo.totalOwned and housingInfo.totalOwned > 0 then
                countWidget:ClearAllPoints()
                countWidget:SetPoint("BOTTOMRIGHT", mogStatus, "BOTTOMRIGHT", -1, 1)
                countWidget:SetText(housingInfo.totalOwned)
                countWidget:SetTextColor(1, 1, 1, 1)
                countWidget:Show()
                options.hasCount = options.hasCount or true
            end
        end
    elseif status == "own" or status == "ownPlus" then
        isProminent = true
        if displayInfo and displayInfo.ownIcon.shouldShow then
            mogStatus:SetTexCoord(16 / 64, 48 / 64, 16 / 64, 48 / 64)
            mogStatus:SetTexture("Interface\\Store\\category-icon-featured")
            if status == "ownPlus" then
                mogStatus:SetVertexColor(0.4, 1, 0)
            end
        end
    elseif status == "other" or status == "otherPlus" then
        isProminent = true
        if displayInfo and displayInfo.otherIcon.shouldShow then
            mogStatus:SetTexCoord(16 / 64, 48 / 64, 16 / 64, 48 / 64)
            mogStatus:SetTexture("Interface\\Store\\category-icon-placeholder")
            if status == "otherPlus" then
                mogStatus:SetVertexColor(0.4, 1, 0)
            end
        end
    elseif status == "otherNoLoot" or status == "otherPlusNoLoot" then
        if displayInfo and displayInfo.otherIcon.shouldShow then
            iconBackgroundAdjustment = 0
            options.statusBackgroundOffsetX = -0.5
            options.statusBackgroundOffsetY = -0.5
            mogStatusBackground:SetTexCoord((512 - 46 - 31) / 512, (512 - 31) / 512, 5 / 512, (5 + 46) / 512)
            mogStatusBackground:SetTexture("Interface\\HUD\\UIUnitFrameBoss2x")
            mogStatus:SetVertexColor(1, 1, 0)

            mogStatus:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")

            if status == "otherPlusNoLoot" then
                mogStatusBackground:SetVertexColor(0.4, 1, 0)
            end
        end
    elseif status == "otherSpec" or status == "otherSpecPlus" then
        isProminent = true
        if displayInfo and displayInfo.otherIcon.shouldShow then
            mogStatus:SetTexture("Interface\\COMMON\\icon-noloot")
            if status == "otherSpecPlus" then
                mogStatus:SetVertexColor(0.4, 1, 0)
            end
        end
    elseif status == "quest" and displayInfo and displayInfo.questIcon.shouldShow then
        mogStatus:SetTexCoord(-1 / 32, 33 / 32, -1 / 32, 33 / 32)
        mogStatus:SetTexture("Interface\\MINIMAP\\MapQuestHub_Icon32")
    elseif status == "collected" then
        local matchesCurrentSpec = transmogInfo and (transmogInfo.matchesLootSpec ~= false)
        if shouldShowUpgradeIcon and transmogInfo and transmogInfo.upgradeMatchesSpec == false and
            not allowMismatchedSpecUpgrades then
            shouldShowUpgradeIcon = false
        end
        local showEqualLevel = transmogInfo and
            showNeutralSameLevel and
            transmogInfo.equalItemLevelEquipped and
            canEquipForNeutral and
            matchesCurrentSpec and
            transmogInfo.hasMetRequirements and
            not transmogInfo.isUpgrade and
            upgradeSlotAvailable and
            not isShirt

        if showEqualLevel and not isEquipmentSetItem then
            iconBackgroundAdjustment = 6
            mogStatusBackground:SetTexCoord((512 - 46 - 31) / 512, (512 - 31) / 512, 5 / 512, (5 + 46) / 512)
            mogStatusBackground:SetTexture("Interface\\HUD\\UIUnitFrameBoss2x")
            mogStatusBackground:SetVertexColor(0.85, 0.85, 0.85)

            mogStatus:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            mogStatus:SetTexture("Interface\\PaperDollInfoFrame\\StatSortArrows")
            mogStatus:SetVertexColor(1, 0.95, 0.75)
        elseif IsGearSetStatus(bindingStatus, item) and CaerdonWardrobeConfig.Binding.ShowGearSetsAsIcon then
            mogStatus:SetTexCoord(16 / 64, 48 / 64, 16 / 64, 48 / 64)
            mogStatus:SetTexture("Interface\\Store\\category-icon-clothes")
        end
    elseif status == "sellable" then
        if displayInfo and displayInfo.sellableIcon.shouldShow then -- it's known and can be sold
            alpha = 0.9
            mogStatus:SetTexCoord(16 / 64, 48 / 64, 16 / 64, 48 / 64)
            mogStatus:SetTexture("Interface\\Store\\category-icon-bag")
        end
    elseif status == "waiting" then
        alpha = 0.5
        mogStatus:SetTexCoord(16 / 64, 48 / 64, 16 / 64, 48 / 64)
        mogStatus:SetTexture("Interface\\Common\\StreamCircle")
        -- elseif IsGearSetStatus(bindingStatus, item) and CaerdonWardrobeConfig.Binding.ShowGearSetsAsIcon then
        -- 	mogStatus:SetTexCoord(16/64, 48/64, 16/64, 48/64)
        -- 	mogStatus:SetTexture("Interface\\Store\\category-icon-clothes")
    end

    if not upgradeDeltaShown and transmogInfo and transmogInfo.upgradeItemLevelDelta and transmogInfo.upgradeItemLevelDelta > 0 then
        ShowUpgradeDeltaText()
    end

    local iconSize = ICON_PROMINENT_SIZE
    if options.statusProminentSize then
        iconSize = options.statusProminentSize
    end

    if isProminent then
        mogStatusBackground:SetSize(iconSize, iconSize)
        mogStatus:SetSize(iconSize - iconBackgroundAdjustment, iconSize - iconBackgroundAdjustment)
    else
        iconSize = iconSize * ICON_SIZE_DIFFERENTIAL
        mogStatusBackground:SetSize(iconSize, iconSize)
        mogStatus:SetSize(iconSize - iconBackgroundAdjustment, iconSize - iconBackgroundAdjustment)
    end

    self:SetStatusIconPosition(mogStatus, originalButton, item, feature, locationInfo, options, status, bindingStatus)

    mogStatusBackground:SetAlpha(alpha)

    mogStatus:SetAlpha(alpha)
    mogStatus.assignedAlpha = alpha

    C_Timer.After(0, function()
        if (caerdonButton.searchOverlay and caerdonButton.searchOverlay:IsShown()) then
            mogStatusBackground:SetAlpha(0.3)
            mogStatus:SetAlpha(0.3)
        end
    end)

    if options.isFiltered then
        if options.filterColor then
            mogStatus:SetDesaturated(true)
            mogStatus:SetVertexColor(options.filterColor:GetRGB())
        else
            mogStatusBackground:SetAlpha(0.3)
            mogStatus:SetAlpha(0.3)
        end
    else
        mogStatus:SetDesaturated(false)
    end

    if showAnim and CaerdonWardrobeConfig.Icon.EnableAnimation then
        if mogAnim and not mogAnim:IsPlaying() then
            mogAnim:Play()
        end
    else
        if mogAnim and mogAnim:IsPlaying() then
            mogAnim:Finish()
        end
    end
end

function CaerdonWardrobeMixin:UpdateUpgradeDeltaPosition(originalButton)
    if not originalButton then return end
    local caerdonButton = self:GetCaerdonButton(originalButton)
    if not caerdonButton then return end

    local deltaText = caerdonButton.upgradeDeltaText
    if not (deltaText and deltaText:IsShown()) then
        return
    end

    local anchorFrame = caerdonButton.upgradeDeltaAnchor or originalButton
    if not anchorFrame then
        anchorFrame = originalButton
    end
    local baseYOffset = caerdonButton.upgradeDeltaBaseYOffset or 0
    local padding = caerdonButton.bindingBottomPadding or 0

    deltaText:ClearAllPoints()
    deltaText:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", -2, baseYOffset + padding)
end

function CaerdonWardrobeMixin:SetItemButtonBindType(button, item, feature, locationInfo, options, mogStatus,
                                                    bindingStatus)
    local caerdonButton = self:GetCaerdonButton(button)

    local bindsOnText = caerdonButton and caerdonButton.bindsOnText
    if bindsOnText then
        bindsOnText:SetText("")
    end

    if not feature then return end

    local displayInfo = feature:GetDisplayInfoInternal(button, item, feature, locationInfo, options, mogStatus,
        bindingStatus)

    if not bindingStatus or not displayInfo.bindingStatus.shouldShow then
        return
    end

    local bindingText = ""
    if IsGearSetStatus(bindingStatus, item) then -- is gear set
        if CaerdonWardrobeConfig.Binding.ShowGearSets then
            bindingText = "|cFFFFFFFF" .. bindingStatus .. "|r"
        end
    else
        if mogStatus == "own" then
            if bindingStatus == L["BoA"] then
                local color = BAG_ITEM_QUALITY_COLORS[Enum.ItemQuality.Heirloom]
                bindsOnText:SetTextColor(color.r, color.g, color.b, 1)
                bindingText = bindingStatus
            elseif bindingStatus then
                bindingText = "|cFF00FF00" .. bindingStatus .. "|r"
            end
        elseif mogStatus == "other" then
            bindingText = "|cFFFF0000" .. bindingStatus .. "|r"
        elseif mogStatus == "collected" then
            if bindingStatus == L["BoA"] then
                local color = BAG_ITEM_QUALITY_COLORS[Enum.ItemQuality.Heirloom]
                bindsOnText:SetTextColor(color.r, color.g, color.b, 1)
                bindingText = bindingStatus
            elseif bindingStatus == L["BoE"] then
                bindingText = "|cFF00FF00" .. bindingStatus .. "|r"
            else
                bindingText = bindingStatus
            end
        else
            if bindingStatus == L["BoA"] then
                local color = BAG_ITEM_QUALITY_COLORS[Enum.ItemQuality.Heirloom]
                bindsOnText:SetTextColor(color.r, color.g, color.b, 1)
                bindingText = bindingStatus
            elseif bindingStatus then
                bindingText = "|cFF00FF00" .. bindingStatus .. "|r"
            end
        end
    end

    bindsOnText:SetText(bindingText)
    bindsOnText:SetJustifyV("BOTTOM")
    if caerdonButton then
        caerdonButton.bindingBottomPadding = 0
    end

    -- Measure text and resize accordingly
    bindsOnText:ClearAllPoints()
    bindsOnText:SetSize(0, 0)
    bindsOnText:SetPoint("LEFT")
    bindsOnText:SetPoint("RIGHT")

    local newWidth = bindsOnText:GetStringWidth()
    if newWidth > button:GetWidth() then
        newWidth = button:GetWidth()
    end
    local _, fontHeight = bindsOnText:GetFont()
    local newHeight = fontHeight or bindsOnText:GetStringHeight() or bindsOnText:GetHeight()

    bindsOnText:ClearAllPoints()
    bindsOnText:SetSize(newWidth, newHeight)

    local bindingScale = options.bindingScale or 1
    local bindingPosition = options.overrideBindingPosition or CaerdonWardrobeConfig.Binding.Position
    local xOffset = 1
    if options.bindingOffsetX ~= nil then
        xOffset = options.bindingOffsetX
    end

    local yOffset = 2
    if options.bindingOffsetY ~= nil then
        yOffset = options.bindingOffsetY
    end

    local hasCount = (button.count and button.count > 1) or options.hasCount

    if string.find(bindingPosition, "BOTTOM") then
        bindsOnText:SetJustifyV("BOTTOM")
    elseif string.find(bindingPosition, "TOP") then
        bindsOnText:SetJustifyV("TOP")
    else
        bindsOnText:SetJustifyV("MIDDLE")
    end

    if string.find(bindingPosition, "BOTTOM") then
        if hasCount then
            yOffset = options.itemCountOffset or 15
        else
            yOffset = yOffset - 2
        end
    end

    if string.find(bindingPosition, "TOP") then
        yOffset = yOffset * -1
    end

    if string.find(bindingPosition, "RIGHT") then
        xOffset = xOffset * -1
    end

    if options and options.relativeFrame then
        bindsOnText:SetPoint(bindingPosition, options.relativeFrame, bindingPosition, xOffset, yOffset)
    else
        bindsOnText:SetPoint(bindingPosition, xOffset, yOffset)
    end

    if (options.bindingScale) then
        bindsOnText:SetScale(options.bindingScale)
    end

    if caerdonButton then
        local hasBindingText = bindingText ~= nil and bindingText ~= ""
        if hasBindingText and bindingPosition and string.find(bindingPosition, "BOTTOM") then
            local _, fontHeight = bindsOnText:GetFont()
            local scale = bindsOnText:GetScale() or 1
            local bindingHeight = (fontHeight or bindsOnText:GetHeight() or 0) * scale
            caerdonButton.bindingBottomPadding = bindingHeight + 2
        else
            caerdonButton.bindingBottomPadding = 0
        end
        self:UpdateUpgradeDeltaPosition(button)
    end
end

function CaerdonWardrobeMixin:ProcessItem(button, item, feature, locationInfo, options)
    local mogStatus = nil
    local bindingStatus = nil
    local bindingResult = nil

    if not options then
        options = {}
    end

    local caerdonType = item:GetCaerdonItemType()
    local itemData = item:GetItemData()

    isReady, mogStatus, bindingStatus, bindingResult = item:GetCaerdonStatus(feature, locationInfo)
    if not isReady then
        self:UpdateButton(button, item, feature, locationInfo, options)
        return
    end

    local transmogInfo

    if caerdonType == CaerdonItemType.Equipment then
        transmogInfo = itemData:GetTransmogInfo()
        if transmogInfo then
            if transmogInfo.isTransmog then
                -- TODO: Exceptions need to be broken out
                -- TODO: Instead maybe: mogStatus = feature:UpdateMogStatus(mogStatus)
                local featureName = feature and feature:GetName()
                if featureName == "EncounterJournal" or featureName == "Merchant" or featureName == "CustomerOrders" then
                    if transmogInfo.needsItem and featureName ~= "Merchant" then
                        if not transmogInfo.matchesLootSpec then
                            if mogStatus == "own" or mogStatus == "lowSkill" then
                                mogStatus = "otherSpecPlus"
                            else
                                if CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem then
                                    mogStatus = "otherSpec"
                                end
                            end
                        end
                    elseif transmogInfo.otherNeedsItem then
                        local playerCanCollectSource = transmogInfo.playerCanCollectSource
                        local isBindOnPickup = bindingResult and bindingResult.isBindOnPickup
                        local playerCollectRestricted = playerCanCollectSource == false
                        local shouldShowNoLoot

                        if featureName == "EncounterJournal" then
                            -- Encounter Journal entries should flag as no-loot when the source is
                            -- class/faction locked or when the drop itself is BoP (old behavior).
                            shouldShowNoLoot = playerCollectRestricted or isBindOnPickup
                        elseif featureName == "Merchant" then
                            -- Merchant ensembles often surface as consumables, so fall back to the
                            -- pre-commit behavior of only suppressing icons when the item is BoP.
                            shouldShowNoLoot = isBindOnPickup
                        else
                            -- Customer Orders (and any other features that land here) still benefit
                            -- from the new player-can-collect signal so completionists can see when
                            -- the recipe truly cannot be learned.
                            shouldShowNoLoot = playerCollectRestricted
                        end

                        if shouldShowNoLoot then
                            if not transmogInfo.isCompletionistItem then
                                mogStatus = "otherNoLoot"
                            else
                                mogStatus = "otherPlusNoLoot"
                            end
                        end
                    end
                end
            end
        end
    end

    if button then
        self:SetItemButtonStatus(button, item, feature, locationInfo, options, mogStatus, bindingStatus, transmogInfo)
        self:SetItemButtonMogStatusFilter(button, options.isFiltered)
        self:SetItemButtonBindType(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
    end
end

function CaerdonWardrobeMixin:RegisterFeature(mixin)
    local instance = CreateFromMixins(CaerdonWardrobeFeatureMixin, mixin)
    local name = instance:GetName()
    if not availableFeatures[name] then
        availableFeatures[name] = instance
    else
        error(format("Caerdon Wardrobe: Feature name collision: %s already exists", name))
    end
end

function CaerdonWardrobeMixin:GetRegisteredFeatures()
    return availableFeatures
end

function CaerdonWardrobeMixin:GetFeature(name)
    return registeredFeatures[name] or availableFeatures[name]
end

function CaerdonWardrobeMixin:ClearButton(button)
    local caerdonButton = self:GetCaerdonButton(button)
    if caerdonButton then
        if self.waitingToProcess then
            for locationKey, processInfo in pairs(self.waitingToProcess) do
                if processInfo.button == button then
                    self.waitingToProcess[locationKey] = nil
                end
            end
        end

        if self.processQueue then
            for locationKey, processInfo in pairs(self.processQueue) do
                if processInfo.button == button then
                    self.processQueue[locationKey] = nil
                end
            end
        end

        if self.featureProcessItems then
            for feature, items in pairs(self.featureProcessItems) do
                if items then
                    for locationKey, processInfo in pairs(items) do
                        if processInfo.button == button then
                            items[locationKey] = nil
                        end
                    end
                end
            end
        end

        self:SetItemButtonStatus(button)
        self:SetItemButtonBindType(button)
    end
end

function CaerdonWardrobeMixin:CancelPending(feature)
    for locationKey, processInfo in pairs(self.waitingToProcess) do
        if processInfo.feature == feature then
            self.waitingToProcess[locationKey] = nil
        end
    end
    if self.processQueue then
        for locationKey, processInfo in pairs(self.processQueue) do
            if processInfo.feature == feature then
                self.processQueue[locationKey] = nil
            end
        end
    end
    if self.featureProcessContinuables[feature] then
        self.featureProcessContinuables[feature]:Cancel()
    end
    self.featureProcessItems[feature] = nil
end

function CaerdonWardrobeMixin:UpdateButton(button, item, feature, locationInfo, options)
    local _, createdNew = self:SetupCaerdonButton(button, item, feature, locationInfo, options)

    if item == nil then
        self:ClearButton(button)
        return
    elseif item:IsItemEmpty() and item:GetCaerdonItemType() == CaerdonItemType.Empty then
        self:ClearButton(button)
        return
    end

    if createdNew then
        self:SetItemButtonStatus(button, item, feature, locationInfo, options, "waiting", nil, nil)
    end

    local locationKey = locationInfo.locationKey

    if item:HasItemLocationBankOrBags() then
        local itemLocation = item:GetItemLocation()
        local bag, slot = itemLocation:GetBagAndSlot()
        locationKey = format("bag%d-slot%d", bag, slot)
    end

    if locationKey then -- opt-in to coroutine-based update
        locationKey = format("%s-%s", feature:GetName(), locationKey)
        self:SetButtonLocationKey(button, locationKey)

        if not item:IsItemEmpty() then
            local itemID = item:GetItemID()
            if self:GetButtonItemID(button) ~= itemID then
                self:SetButtonItemID(button, itemID)
                self:ClearButton(button)
            end
        end

        self.waitingToProcess[locationKey] = {
            button = button,
            item = item,
            feature = feature,
            locationInfo = locationInfo,
            options = options
        }
        return
    end
end

function CaerdonWardrobeMixin:ProcessItem_Coroutine()
    if self.processQueue == nil then
        self.processQueue = {}

        while true do
            local itemCount = 0
            for locationKey, processInfo in pairs(self.waitingToProcess) do
                -- Don't process item if the key is different than expected
                if self:GetButtonLocationKey(processInfo.button) == locationKey then
                    itemCount = itemCount + 1
                    self.processQueue[locationKey] = processInfo
                end

                self.waitingToProcess[locationKey] = nil
            end

            local itemsProcessedThisFrame = 0
            local maxItemsPerFrame = 12 -- Process only a few items per frame

            for locationKey, processInfo in pairs(self.processQueue) do
                local button = processInfo.button
                local item = processInfo.item
                local feature = processInfo.feature
                local locationInfo = processInfo.locationInfo
                local options = processInfo.options

                if feature:IsSameItem(button, item, locationInfo) and self:GetButtonLocationKey(button) == locationKey then
                    if item:IsItemEmpty() then -- BattlePet or something else - assuming item is ready.
                        self:ProcessItem(button, item, feature, locationInfo, options)
                        itemsProcessedThisFrame = itemsProcessedThisFrame + 1
                    else
                        -- Check if item is already cached to process immediately
                        if item:IsItemDataCached() then
                            if self:GetButtonLocationKey(button) == locationKey then
                                self:ProcessItem(button, item, feature, locationInfo, options)
                                itemsProcessedThisFrame = itemsProcessedThisFrame + 1
                            else
                                self:ClearButton(button)
                            end
                        else
                            -- Item not cached, add to continuable container
                            self.featureProcessContinuables[feature] = self.featureProcessContinuables[feature] or
                                ContinuableContainer:Create();
                            self.featureProcessContinuables[feature]:AddContinuable(item);
                            self.featureProcessItems[feature] = self.featureProcessItems[feature] or {}
                            self.featureProcessItems[feature][locationKey] = processInfo
                        end
                    end
                else
                    self:ClearButton(button)
                end

                self.processQueue[locationKey] = nil

                -- Yield after processing a few items to maintain frame rate
                if itemsProcessedThisFrame >= maxItemsPerFrame then
                    coroutine.yield()
                    itemsProcessedThisFrame = 0
                end
            end

            for feature, continuableContainer in pairs(self.featureProcessContinuables) do
                continuableContainer:ContinueOnLoad(function()
                    local items = self.featureProcessItems[feature]
                    -- Store items that need processing back into the queue
                    if items then
                        for locationKey, processInfo in pairs(items) do
                            if not self.processQueue then
                                self.processQueue = {}
                            end
                            self.processQueue[locationKey] = processInfo
                        end
                        self.featureProcessItems[feature] = nil
                    end
                end)
                self.featureProcessContinuables[feature] = nil
            end

            if itemCount == 0 and itemsProcessedThisFrame == 0 then
                break
            end

            coroutine.yield()
        end

        self.processQueue = nil
    end
end

function CaerdonWardrobeMixin:OnEvent(event, ...)
    local handler = self[event]
    if (handler) then
        handler(self, ...)
    end

    for name, instance in pairs(registeredFeatures) do
        handler = instance[event]
        if (handler) then
            handler(instance, ...)
        end
    end
end

local next = next -- faster lookup as a local apparently (haven't measured)

function CaerdonWardrobeMixin:OnUpdate(elapsed)
    self.timeSinceLastUpdate = (self.timeSinceLastUpdate or 0) + elapsed
    if (self.timeSinceLastUpdate > 0.1) then
        if self.processItemCoroutine then
            if coroutine.status(self.processItemCoroutine) ~= "dead" then
                local ok, result = coroutine.resume(self.processItemCoroutine)
                if not ok then
                    error(result)
                end
            else
                self.processItemCoroutine = nil
            end
            return
        elseif next(self.waitingToProcess) ~= nil then
            self.processItemCoroutine = coroutine.create(function() self:ProcessItem_Coroutine() end)
        end

        self.timeSinceLastUpdate = 0
    end

    local name, instance
    for name, instance in pairs(registeredFeatures) do
        instance:OnUpdate(elapsed)
    end
end

function CaerdonWardrobeMixin:PLAYER_ENTERING_WORLD()
    if isHousingSupported then
        self:WarmHousingData()
    end
end

function CaerdonWardrobeMixin:PLAYER_LOGOUT()
end

function CaerdonWardrobeMixin:VARIABLES_LOADED()
end

function CaerdonWardrobeMixin:ADDON_LOADED(name)
    if name == ADDON_NAME then
        local name, instance
        for name, instance in pairs(availableFeatures) do
            registeredFeatures[name] = instance
            local instanceEvents = instance:Init(self)
            if instanceEvents then
                for i = 1, #instanceEvents do
                    -- TODO: Hook up to debugging
                    self:RegisterEvent(instanceEvents[i])
                end
            end
        end
        -- elseif name == "TradeSkillMaster" then
        -- 	print("HOOKING TSM")
        -- 	hooksecurefunc (TSM.UI.AuctionScrollingTable, "_SetRowData", function (self, row, data)
        -- 		print("Row: " .. row:GetField("auctionId"))
        -- 	end)
    end
end

function CaerdonWardrobeMixin:RefreshItems()
    if self.refreshTimer then
        self.refreshTimer:Cancel()
    end

    self.refreshTimer = C_Timer.NewTimer(0.1, function()
        local name, instance
        for name, instance in pairs(registeredFeatures) do
            instance:Refresh()
        end
    end, 1)
end

function CaerdonWardrobeMixin:OnEquipPendingItem()
    -- TODO: Bit of a hack... wait a bit and then update...
    --       Need to figure out a better way.  Otherwise,
    --		 you end up with BoE markers on things you've put on.
    C_Timer.After(1, function() self:RefreshItems() end)
end

function CaerdonWardrobeMixin:TRANSMOG_COLLECTION_UPDATED()
    self:RefreshItems()
end

function CaerdonWardrobeMixin:EQUIPMENT_SETS_CHANGED()
    self:RefreshItems()
end

function CaerdonWardrobeMixin:UPDATE_EXPANSION_LEVEL()
    -- Can change while logged in!
    self:RefreshItems()
end

function CaerdonWardrobeMixin:WarmHousingData()
    if self.hasWarmedHousing or not isHousingSupported then
        return
    end

    -- Load lightweight housing event handler to ensure housing events are wired even outside the housing UI.
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_HousingEventHandler")
    elseif LoadAddOn then
        pcall(LoadAddOn, "Blizzard_HousingEventHandler")
    end

    if C_HousingCatalog then
        -- Trigger backend to populate storage/market info.
        if C_HousingCatalog.RequestHousingMarketInfoRefresh then
            pcall(C_HousingCatalog.RequestHousingMarketInfoRefresh)
        end
        if C_HousingCatalog.GetDecorTotalOwnedCount then
            pcall(C_HousingCatalog.GetDecorTotalOwnedCount)
        end
        if C_HousingCatalog.SearchCatalogCategories then
            pcall(C_HousingCatalog.SearchCatalogCategories,
                { withOwnedEntriesOnly = true, includeFeaturedCategory = false })
        end
        if C_HousingCatalog.SearchCatalogSubcategories then
            pcall(C_HousingCatalog.SearchCatalogSubcategories,
                { withOwnedEntriesOnly = true, includeFeaturedCategory = false })
        end
    end

    self.hasWarmedHousing = true
end

function CaerdonWardrobeMixin:HOUSING_STORAGE_ENTRY_UPDATED()
    if isHousingSupported then
        self:RefreshItems()
        C_Timer.After(0.5, function() self:RefreshItems() end)
    end
end

function CaerdonWardrobeMixin:HOUSING_STORAGE_UPDATED()
    if isHousingSupported then
        self:RefreshItems()
        C_Timer.After(0.5, function() self:RefreshItems() end)
    end
end

function CaerdonWardrobeMixin:HOUSE_DECOR_ADDED_TO_CHEST()
    if isHousingSupported then
        self:RefreshItems()
        C_Timer.After(0.5, function() self:RefreshItems() end)
    end
end

function CaerdonWardrobeMixin:DYE_COLOR_UPDATED()
    if isHousingSupported then
        self:RefreshItems()
        C_Timer.After(0.5, function() self:RefreshItems() end)
    end
end

function CaerdonWardrobeMixin:DYE_COLOR_CATEGORY_UPDATED()
    if isHousingSupported then
        self:RefreshItems()
        C_Timer.After(0.5, function() self:RefreshItems() end)
    end
end
