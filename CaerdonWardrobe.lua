-- EQUIPPED_LAST=500 -- TODO: Temp fix for bag opening

local DEBUG_ENABLED = false
-- local DEBUG_ITEM = 82800
local ADDON_NAME, NS = ...
local L = NS.L

BINDING_HEADER_CAERDON = L["Caerdon Addons"]
BINDING_NAME_COPYMOUSEOVERLINK = L["Copy Mouseover Link"]
BINDING_NAME_PRINTMOUSEOVERLINKDETAILS = L["Print Mouseover Link Details"]

local availableFeatures = {}
local registeredFeatures = {}

CaerdonWardrobeMixin = {}

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

    if not options.fixedStatusPosition then
        local background = icon.mogStatusBackground
        if background then
            background:ClearAllPoints()
            background:SetPoint("CENTER", button.caerdonButton, statusPosition, xOffset + xBackgroundOffset,
                yOffset + yBackgroundOffset)
        end

        icon:ClearAllPoints()
        icon:SetPoint("CENTER", button.caerdonButton, statusPosition, xOffset, yOffset)
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
    local button = originalButton.caerdonButton
    if button then
        local mogStatus = button.mogStatus
        if mogStatus then
            local mogStatusBackground = mogStatus.mogStatusBackground

            if isFiltered then
                mogStatusBackground:SetAlpha(0.3)
                mogStatus:SetAlpha(0.3)
            else
                mogStatusBackground:SetAlpha(mogStatus.assignedAlpha)
                mogStatus:SetAlpha(mogStatus.assignedAlpha)
            end
        end

        local bindsOnText = button.bindsOnText
        if bindsOnText then
            if isFiltered then
                bindsOnText:SetAlpha(0.3)
            else
                bindsOnText:SetAlpha(1.0)
            end
        end
    end
end

function CaerdonWardrobeMixin:SetupCaerdonButton(originalButton, item, feature, locationInfo, options)
    local button = originalButton.caerdonButton
    if not button then
        button = CreateFrame("Frame", nil, originalButton)
        button.searchOverlay = originalButton.searchOverlay
        originalButton.caerdonButton = button
    end

    if not button.mogStatus then
        local mogStatusBackground = button:CreateTexture(nil, "ARTWORK", nil, 1)
        local mogStatus = button:CreateTexture(nil, "ARTWORK", nil, 2)
        mogStatus.mogStatusBackground = mogStatusBackground
        button.mogStatus = mogStatus
    end

    if not button.bindsOnText then
        button.bindsOnText = button:CreateFontString(nil, "ARTWORK", "SystemFont_Outline_Small") -- TODO: Note: placing directly on button to enable search fade - need to check on other addons
    end
end

function CaerdonWardrobeMixin:SetItemButtonStatus(originalButton, item, feature, locationInfo, options, status,
                                                  bindingStatus)
    local button = originalButton.caerdonButton
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
        button:SetFrameStrata(levelCheckFrame:GetFrameStrata())
        button:SetFrameLevel(levelCheckFrame:GetFrameLevel() + 1)
    end

    button:ClearAllPoints()
    button:SetSize(0, 0)

    if options and options.relativeFrame then
        button:SetAllPoints(options.relativeFrame)
    else
        button:SetAllPoints(originalButton)
    end

    -- Had some addons messing with frame level resulting in this getting covered by the parent button.
    -- Haven't seen any negative issues with bumping it up, yet, but keep an eye on it if
    -- the status icon overlaps something it shouldn't.
    -- NOTE: Added logic above that hopefully addresses this more sanely...
    -- button:SetFrameLevel(originalButton:GetFrameLevel() + 100)

    local iconBackgroundAdjustment = 0
    local mogStatus = button.mogStatus
    local mogStatusBackground
    if mogStatus then
        mogStatusBackground = mogStatus.mogStatusBackground
    end
    local mogAnim = button.mogAnim

    if not options then
        options = {}
    end

    if not status then
        if mogAnim and mogAnim:IsPlaying() then
            mogAnim:Stop()
        end
    end

    -- local mogFlash = button.mogFlash
    -- if not mogFlash then
    -- 	mogFlash = button:CreateTexture(nil, "OVERLAY")
    -- 	mogFlash:SetAlpha(0)
    -- 	mogFlash:SetBlendMode("ADD")
    -- 	mogFlash:SetAtlas("bags-glow-flash", true)
    -- 	mogFlash:SetPoint("CENTER")

    -- 	button.mogFlash = mogFlash
    -- end

    local showAnim = false
    if status == "waiting" then
        showAnim = true

        if mogAnim and not button.isWaitingIcon then
            if mogAnim:IsPlaying() then
                mogAnim:Finish()
            end

            mogAnim = nil
            button.mogAnim = nil
            button.isWaitingIcon = false
        end

        if not mogAnim or not button.isWaitingIcon then
            mogAnim = mogStatus:CreateAnimationGroup()

            self:AddRotation(mogAnim, 1, 360, 0.5, "IN_OUT")

            mogAnim:SetLooping("REPEAT")
            button.mogAnim = mogAnim
            button.isWaitingIcon = true
        end
    else
        if status == "readyToCombine" or status == "own" or status == "ownPlus" or status == "otherSpec" or status == "otherSpecPlus" or status == "refundable" or status == "openable" or status == "locked" or status == "upgradeNonEquipment" or status == "readyToCombine" then
            showAnim = true

            if mogAnim and button.isWaitingIcon then
                if mogAnim:IsPlaying() then
                    mogAnim:Finish()
                end

                mogAnim = nil
                button.mogAnim = nil
                button.isWaitingIcon = false
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
                button.mogAnim = mogAnim
                button.isWaitingIcon = false
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

    -- 		button.mogAnim = mogAnim
    -- 	end

    local displayInfo
    if feature then
        displayInfo = feature:GetDisplayInfoInternal(button, item, feature, locationInfo, options, mogStatus,
            bindingStatus)
    end

    local alpha = 1

    mogStatusBackground:SetVertexColor(1, 1, 1)
    mogStatusBackground:SetTexture("")
    mogStatusBackground:SetTexCoord(0, 1, 0, 1)

    mogStatus:SetVertexColor(1, 1, 1)
    mogStatus:SetTexture("")
    mogStatus:SetTexCoord(0, 1, 0, 1)

    local isProminent = false

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
        if displayInfo and displayInfo.upgradeIcon.shouldShow then
            iconBackgroundAdjustment = 4
            mogStatusBackground:SetTexCoord((512 - 46 - 31) / 512, (512 - 31) / 512, 5 / 512, (5 + 46) / 512)
            mogStatusBackground:SetTexture("Interface\\HUD\\UIUnitFrameBoss2x")
            mogStatusBackground:SetVertexColor(0, 1, 1)

            mogStatus:SetTexCoord(-1 / 32, 33 / 32, -1 / 32, 33 / 32)
            mogStatus:SetTexture("Interface\\Buttons\\JumpUpArrow")
        end
    elseif status == "upgradeLowSkill" then
        isProminent = false
        if displayInfo and displayInfo.upgradeIcon.shouldShow then
            iconBackgroundAdjustment = 4
            mogStatusBackground:SetTexCoord((512 - 46 - 31) / 512, (512 - 31) / 512, 5 / 512, (5 + 46) / 512)
            mogStatusBackground:SetTexture("Interface\\HUD\\UIUnitFrameBoss2x")
            mogStatusBackground:SetVertexColor(0.4, 1, 0)

            mogStatus:SetTexCoord(-1 / 32, 33 / 32, -1 / 32, 33 / 32)
            mogStatus:SetTexture("Interface\\Buttons\\JumpUpArrow")
            mogStatus:SetVertexColor(0.4, 1, 0)
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
        if IsGearSetStatus(bindingStatus, item) and CaerdonWardrobeConfig.Binding.ShowGearSetsAsIcon then
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
        if (button.searchOverlay and button.searchOverlay:IsShown()) then
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

function CaerdonWardrobeMixin:SetItemButtonBindType(button, item, feature, locationInfo, options, mogStatus,
                                                    bindingStatus)
    local caerdonButton = button.caerdonButton

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

    -- Measure text and resize accordingly
    bindsOnText:ClearAllPoints()
    bindsOnText:SetSize(0, 0)
    bindsOnText:SetPoint("LEFT")
    bindsOnText:SetPoint("RIGHT")

    local newWidth = bindsOnText:GetStringWidth()
    if newWidth > button:GetWidth() then
        newWidth = button:GetWidth()
    end
    local newHeight = bindsOnText:GetHeight()

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
        if hasCount then
            yOffset = options.itemCountOffset or 15
        end
    end

    if string.find(bindingPosition, "TOP") then
        yOffset = yOffset * -1
    end

    if string.find(bindingPosition, "RIGHT") then
        xOffset = xOffset * -1
    end

    if options and options.relativeFrame then
        bindsOnText:SetAllPoints(options.relativeFrame, xOffset, yOffset)
    else
        bindsOnText:SetPoint(bindingPosition, xOffset, yOffset)
    end

    if (options.bindingScale) then
        bindsOnText:SetScale(options.bindingScale)
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

    if caerdonType == CaerdonItemType.Equipment then
        local transmogInfo = itemData:GetTransmogInfo()
        if transmogInfo then
            if transmogInfo.isTransmog then
                -- TODO: Exceptions need to be broken out
                -- TODO: Instead maybe: mogStatus = feature:UpdateMogStatus(mogStatus)
                if feature:GetName() == "EncounterJournal" or feature:GetName() == "Merchant" or feature:GetName() == "CustomerOrders" then
                    if transmogInfo.needsItem and not feature:GetName() == "Merchant" then
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
                        if bindingResult and bindingResult.isBindOnPickup then
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
        self:SetItemButtonStatus(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
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

function CaerdonWardrobeMixin:ClearButton(button)
    if button.caerdonButton then
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
    self:SetupCaerdonButton(button, item, feature, locationInfo, options)

    if item == nil then
        self:ClearButton(button)
        return
    elseif item:IsItemEmpty() and item:GetCaerdonItemType() == CaerdonItemType.Empty then
        self:ClearButton(button)
        return
    end

    if not button.caerdonButton then
        self:SetItemButtonStatus(button, item, feature, locationInfo, options, "waiting", nil)
    end

    local locationKey = locationInfo.locationKey

    if item:HasItemLocationBankOrBags() then
        local itemLocation = item:GetItemLocation()
        local bag, slot = itemLocation:GetBagAndSlot()
        locationKey = format("bag%d-slot%d", bag, slot)
    end

    if locationKey then -- opt-in to coroutine-based update
        locationKey = format("%s-%s", feature:GetName(), locationKey)
        button.caerdonKey = locationKey

        if not item:IsItemEmpty() then
            local itemID = item:GetItemID()
            if not button.caerdonItemID or button.caerdonItemID ~= itemID then
                button.caerdonItemID = itemID
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

        local hasMore = true

        while true do
            local isBatch = false
            local itemCount = 0
            for locationKey, processInfo in pairs(self.waitingToProcess) do
                -- Don't process item if the key is different than expected
                if processInfo.button.caerdonKey == locationKey then
                    itemCount = itemCount + 1
                    self.processQueue[locationKey] = processInfo
                end

                self.waitingToProcess[locationKey] = nil

                -- if itemCount > 12 then -- Process a small batch at a time
                --     isBatch = true
                --     break
                -- end
            end

            hasMore = isBatch

            local itemsProcessedThisFrame = 0
            local maxItemsPerFrame = 3 -- Process only a few items per frame

            for locationKey, processInfo in pairs(self.processQueue) do
                -- TODO: May have to look into cancelable continue to avoid timing issues
                -- Need to figure out how to key this correctly (could have multiple of item in bags, for instance)
                -- but in cases of rapid data update (AH scroll), we don't want to update an old button
                -- Look into ContinuableContainer
                local button = processInfo.button
                local item = processInfo.item
                local feature = processInfo.feature
                local locationInfo = processInfo.locationInfo
                local options = processInfo.options

                if feature:IsSameItem(button, item, locationInfo) and button.caerdonKey == locationKey then
                    if item:IsItemEmpty() then -- BattlePet or something else - assuming item is ready.
                        self:ProcessItem(button, item, feature, locationInfo, options)
                        itemsProcessedThisFrame = itemsProcessedThisFrame + 1
                    else
                        -- Check if item is already cached to process immediately
                        if item:IsItemDataCached() then
                            if button.caerdonKey == locationKey then
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
                            -- if not self.processQueue then
                            --     self.processQueue = {}
                            -- end
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
