CaerdonWardrobeConfigMixin = {}

local ADDON_NAME, NS = ...
local L = NS.L
local components, pendingConfig

CAERDON_CONFIG_LABEL = L["Caerdon Wardrobe... and more!"]
CAERDON_CONFIG_SUBTEXT = L[ [[
Caerdon Wardrobe marks the items worth a second look: appearances, recipes, pets, mounts and toys you haven't learned, gear upgrades, quest items, things worth auctioning, and what's safe to sell.  You'll see its icons in your bags, bank, merchants, the auction house, loot windows and most popular bag addons.

It runs on both |cffffd100Retail|r and |cffffd100WoW Forever|r.

Choose what is shown on the Icons page and how it looks on the Display page.  If the addon ever slows your game down, please let me know!]] ]

local MESSAGE_PREFIX = "|cffffd100Caerdon Wardrobe:|r "
local SETTINGS_COMMAND = "|cffffd100/caerdon|r"

-- One-time messages, shown as a dialog with a button that opens the settings.
-- CaerdonWardrobeConfig.MessageSeen is the number of the last one this account was shown.
-- Settings saved before the field existed read as 0 and get the latest entry; a fresh install
-- starts at the latest number (GetDefaultConfig) and gets the welcome instead. Only the latest
-- entry is ever shown: add at the end, never renumber, and keep it to a sentence or two about
-- what looks or works differently.
local MESSAGES = {
    L["The settings have been rebuilt: two pages that explain every icon, and a layout editor to move and resize them."],
}
local WELCOME_MESSAGE =
    L["Thanks for installing! The icons on your items show what you can still learn, use, sell or auction. The settings explain each icon and let you choose what is shown."]
local RESET_MESSAGE = L["Your settings came from an older version and are back to the defaults."]
-- The command comes early in the sentence: at the end of a line the dialog wraps it after the
-- slash. Each stretch has its own color, so nothing depends on how a nested color ends.
local MESSAGE_FOOTER = "|cffb0b0b0" .. string.format(L["Type %s to open the settings at any time."],
    "|r" .. SETTINGS_COMMAND .. "|cffb0b0b0") .. "|r"
local MESSAGE_DIALOG = "CAERDON_WARDROBE_MESSAGE"
-- Seconds after login, so the dialog does not come up behind the loading screen.
local MESSAGE_DELAY = 3
local pendingMessage

function CaerdonWardrobeConfigMixin:OnLoad()
    self:RegisterEvent("VARIABLES_LOADED");
    self:RegisterEvent("PLAYER_LOGIN");

    self.name = "Caerdon Wardrobe"
    self.okay = self.OnSave

    self.OnCommit = self.okay;
    self.OnDefault = self.default;
    self.OnRefresh = self.refresh;

    local category, layout = Settings.RegisterCanvasLayoutCategory(self, self.name, self.name);
    -- The category keeps the numeric ID it was created with: Settings.OpenToCategory takes
    -- nothing else. The sub-pages and NS:OpenSettings get the category from here.
    NS.SettingsCategory = category
    Settings.RegisterAddOnCategory(category);

    -- Any anchors assigned to the frame will be disposed. Intended anchors need to be provided through
    -- the layout object. If no anchor points are provided, the frame will be anchored to TOPLEFT (0,0)
    -- and BOTTOMRIGHT (0,0).
    -- layout:AddAnchorPoint("TOPLEFT", 10, -10);
    -- layout:AddAnchorPoint("BOTTOMRIGHT", -10, 10);

    self:CreateSupportSection()
end

local SUPPORT_URL = "https://buymeacoffee.com/caerdon"
local SUPPORT_STAR = "|TInterface\\Store\\category-icon-featured:18:18:0:0:64:64:16:48:16:48|t "
local SUPPORT_GAP = 24     -- between the description and the box
local SUPPORT_PADDING = 14 -- inside the box

-- Support link on the main settings page: a box of its own below the description.
function CaerdonWardrobeConfigMixin:CreateSupportSection()
    local subText = _G[self:GetName() .. "SubText"]
    if not subText then return end

    local card = CreateFrame("Frame", nil, self, "BackdropTemplate")
    card:SetPoint("TOPLEFT", subText, "BOTTOMLEFT", -8, -SUPPORT_GAP)
    card:SetPoint("TOPRIGHT", subText, "BOTTOMRIGHT", 8, -SUPPORT_GAP)
    card:SetHeight(110)
    if card.SetBackdrop then
        card:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        card:SetBackdropColor(1, 0.82, 0, 0.06)
        card:SetBackdropBorderColor(1, 0.82, 0, 0.6)
    end

    local header = card:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetJustifyH("LEFT")
    header:SetPoint("TOPLEFT", card, "TOPLEFT", SUPPORT_PADDING, -SUPPORT_PADDING)
    header:SetText(SUPPORT_STAR .. L["Support Caerdon Wardrobe"])

    local body = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    body:SetPoint("RIGHT", card, "RIGHT", -SUPPORT_PADDING, 0)
    body:SetText(L["If Caerdon Wardrobe has been useful to you and you'd like to buy me a drink, this is where to do it:"])

    -- The game cannot open a browser, so the link sits in a read-only box to copy from.
    local editBox = CreateFrame("EditBox", "CaerdonWardrobeConfigSupportLink", card, "InputBoxTemplate")
    editBox:SetAutoFocus(false)
    editBox:SetSize(250, 22)
    editBox:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 6, -10)
    editBox:SetText(SUPPORT_URL)
    editBox:SetCursorPosition(0)

    -- The sentence wraps with the page's width, so the box takes its height from what is in it.
    local function FitCard()
        card:SetHeight(SUPPORT_PADDING + header:GetStringHeight() + 8 + body:GetStringHeight() + 10 +
            editBox:GetHeight() + SUPPORT_PADDING)
    end
    card:SetScript("OnShow", FitCard)
    card:SetScript("OnSizeChanged", FitCard)

    local copyKey = (IsMacClient and IsMacClient()) and "Cmd+C" or "Ctrl+C"
    local hintText = string.format(L["Click the link, then press %s to copy it."], copyKey)
    local hint = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetJustifyH("LEFT")
    hint:SetPoint("LEFT", editBox, "RIGHT", 10, 0)
    hint:SetText(hintText)

    editBox:SetScript("OnTextChanged", function(box, userInput)
        if userInput then
            box:SetText(SUPPORT_URL)
            box:HighlightText()
        end
    end)
    editBox:SetScript("OnEditFocusGained", function(box)
        box:HighlightText()
    end)
    editBox:SetScript("OnMouseUp", function(box)
        -- A click inside a focused box places the cursor and drops the selection.
        box:HighlightText()
    end)
    editBox:SetScript("OnEditFocusLost", function(box)
        box:HighlightText(0, 0)
        box:SetCursorPosition(0)
        hint:SetText(hintText)
    end)
    editBox:SetScript("OnKeyDown", function(box, key)
        if key == "C" and (IsControlKeyDown() or (IsMetaKeyDown and IsMetaKeyDown())) then
            hint:SetText(L["Copied. Paste it into your browser. Thank you!"])
        end
    end)
    editBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    editBox:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    editBox:SetScript("OnHide", function(box) box:ClearFocus() end)

    self.supportLink = editBox
end

-- Opens the settings on the main page (/caerdon, and the button of the one-time dialog).
function NS:OpenSettings()
    if InCombatLockdown and InCombatLockdown() then
        print(MESSAGE_PREFIX .. L["The settings can't be opened in combat."])
        return
    end
    local category = NS.SettingsCategory
    local id = category and ((category.GetID and category:GetID()) or category.ID)
    if type(id) == "number" then
        Settings.OpenToCategory(id)
    end
end

SLASH_CAERDON1 = "/caerdon"
SlashCmdList["CAERDON"] = function()
    NS:OpenSettings()
end

-- The dialog waits for the end of combat, because its button cannot open the settings during it.
-- An entry of MESSAGES counts as seen once it is on screen, so one that never got there comes
-- back at the next login.
function CaerdonWardrobeConfigMixin:ShowPendingMessage()
    if not pendingMessage then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    local message = pendingMessage
    pendingMessage = nil
    if (tonumber(CaerdonWardrobeConfig.MessageSeen) or 0) < #MESSAGES then
        CaerdonWardrobeConfig.MessageSeen = #MESSAGES
    end

    local shown
    if StaticPopupDialogs and StaticPopup_Show then
        if not StaticPopupDialogs[MESSAGE_DIALOG] then
            StaticPopupDialogs[MESSAGE_DIALOG] = {
                text = "|cffffd100Caerdon Wardrobe|r\n\n%s\n\n%s",
                button1 = L["Open Settings"],
                button2 = CLOSE or L["Close"],
                OnAccept = function() NS:OpenSettings() end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
        end
        shown = StaticPopup_Show(MESSAGE_DIALOG, message, MESSAGE_FOOTER)
    end
    if not shown then
        print(MESSAGE_PREFIX .. message .. " " .. MESSAGE_FOOTER)
    end
end

function CaerdonWardrobeConfigMixin:OnEvent(event, ...)
    -- BlizzardOptionsPanel_OnEvent(self, event, ...);

    if (event == "PLAYER_LOGIN") then
        self:UnregisterEvent(event);
        C_Timer.After(MESSAGE_DELAY, function() self:ShowPendingMessage() end)
    elseif (event == "PLAYER_REGEN_ENABLED") then
        self:UnregisterEvent(event);
        self:ShowPendingMessage()
    elseif (event == "VARIABLES_LOADED") then
        self.variablesLoaded = true;
        self:UnregisterEvent(event);

        if not CaerdonWardrobeConfig then
            CaerdonWardrobeConfig = CopyTable(NS:GetDefaultConfig())
            pendingMessage = WELCOME_MESSAGE
        elseif CaerdonWardrobeConfig.Version ~= NS:GetDefaultConfig().Version then
            CaerdonWardrobeConfig = CopyTable(NS:GetDefaultConfig())
            pendingMessage = RESET_MESSAGE
        elseif (tonumber(CaerdonWardrobeConfig.MessageSeen) or 0) < #MESSAGES then
            pendingMessage = MESSAGES[#MESSAGES]
        end
        if IsLoggedIn() then
            C_Timer.After(MESSAGE_DELAY, function() self:ShowPendingMessage() end)
        end

        -- Ensure new config sections exist for users with existing configs
        if not CaerdonWardrobeConfig.Merchant then
            CaerdonWardrobeConfig.Merchant = CopyTable(NS:GetDefaultConfig().Merchant)
        end
        if not CaerdonWardrobeConfig.Merchant.Filter then
            CaerdonWardrobeConfig.Merchant.Filter = CopyTable(NS:GetDefaultConfig().Merchant.Filter)
        end
        if CaerdonWardrobeConfig.Icon.ShowUpgradeLevelDelta == nil then
            CaerdonWardrobeConfig.Icon.ShowUpgradeLevelDelta = NS:GetDefaultConfig().Icon.ShowUpgradeLevelDelta
        end
        if not CaerdonWardrobeConfig.Icon.SameLevelBehavior then
            CaerdonWardrobeConfig.Icon.SameLevelBehavior = NS:GetDefaultConfig().Icon.SameLevelBehavior
        end
        if CaerdonWardrobeConfig.Icon.ShowUpcomingQuestItems == nil then
            CaerdonWardrobeConfig.Icon.ShowUpcomingQuestItems = NS:GetDefaultConfig().Icon.ShowUpcomingQuestItems
        end
        if CaerdonWardrobeConfig.Icon.ShowAuctionValue == nil then
            CaerdonWardrobeConfig.Icon.ShowAuctionValue = NS:GetDefaultConfig().Icon.ShowAuctionValue
        end
        if CaerdonWardrobeConfig.Icon.ShowOutdatedFood == nil then
            CaerdonWardrobeConfig.Icon.ShowOutdatedFood = NS:GetDefaultConfig().Icon.ShowOutdatedFood
        end
        if CaerdonWardrobeConfig.Icon.ShowRecipesForOtherToons == nil then
            CaerdonWardrobeConfig.Icon.ShowRecipesForOtherToons = NS:GetDefaultConfig().Icon.ShowRecipesForOtherToons
        end
        if CaerdonWardrobeConfig.Icon.ShowBagUpgrades == nil then
            CaerdonWardrobeConfig.Icon.ShowBagUpgrades = NS:GetDefaultConfig().Icon.ShowBagUpgrades
        end
        if CaerdonWardrobeConfig.Icon.ShowSpareBags == nil then
            CaerdonWardrobeConfig.Icon.ShowSpareBags = NS:GetDefaultConfig().Icon.ShowSpareBags
        end
        if not CaerdonWardrobeConfig.Tooltip then
            CaerdonWardrobeConfig.Tooltip = {}
        end
        if CaerdonWardrobeConfig.Tooltip.ShowRecipeLearners == nil then
            CaerdonWardrobeConfig.Tooltip.ShowRecipeLearners = NS:GetDefaultConfig().Tooltip.ShowRecipeLearners
        end
        if CaerdonWardrobeConfig.Icon.AuctionMinProfit == nil then
            CaerdonWardrobeConfig.Icon.AuctionMinProfit = NS:GetDefaultConfig().Icon.AuctionMinProfit
        end
        -- Windows that gained their own "learning for another toon" toggle. The Black Market used
        -- to follow the auction house setting, so it starts from that; the rest were always on.
        local byOther = CaerdonWardrobeConfig.Icon.ShowLearnableByOther
        if byOther.BlackMarket == nil then
            byOther.BlackMarket = byOther.Auction
        end
        for key, value in pairs(NS:GetDefaultConfig().Icon.ShowLearnableByOther) do
            if byOther[key] == nil then
                byOther[key] = value
            end
        end
        -- Layout settings (size and nudge of the icon and the texts): fill in what is missing.
        local defaultConfig = NS:GetDefaultConfig()
        for _, key in ipairs({ "Scale", "OffsetX", "OffsetY" }) do
            if CaerdonWardrobeConfig.Icon[key] == nil then
                CaerdonWardrobeConfig.Icon[key] = defaultConfig.Icon[key]
            end
            if CaerdonWardrobeConfig.Binding[key] == nil then
                CaerdonWardrobeConfig.Binding[key] = defaultConfig.Binding[key]
            end
        end
        -- A gear set's name used to share the binding text's position, so it starts from
        -- wherever that is now.
        local binding = CaerdonWardrobeConfig.Binding
        if type(binding.GearSet) ~= "table" then
            binding.GearSet = {
                Position = binding.Position,
                Scale = binding.Scale,
                OffsetX = binding.OffsetX,
                OffsetY = binding.OffsetY
            }
        end
        for key, value in pairs(defaultConfig.Binding.GearSet) do
            if binding.GearSet[key] == nil then
                binding.GearSet[key] = value
            end
        end
        binding.GearSetScale = nil -- a factor on the text's size, from before it had its own layout
        if type(CaerdonWardrobeConfig.Icon.UpgradeDelta) ~= "table" then
            CaerdonWardrobeConfig.Icon.UpgradeDelta = {}
        end
        for key, value in pairs(defaultConfig.Icon.UpgradeDelta) do
            if CaerdonWardrobeConfig.Icon.UpgradeDelta[key] == nil then
                CaerdonWardrobeConfig.Icon.UpgradeDelta[key] = value
            end
        end
        if CaerdonWardrobeConfig.Icon.ShowUpgradeIcon == nil then
            CaerdonWardrobeConfig.Icon.ShowUpgradeIcon = NS:GetDefaultConfig().Icon.ShowUpgradeIcon
        end
        if CaerdonWardrobeConfig.Icon.ShowMismatchedSpecUpgrades == nil then
            CaerdonWardrobeConfig.Icon.ShowMismatchedSpecUpgrades =
                NS:GetDefaultConfig().Icon.ShowMismatchedSpecUpgrades
        end

        CaerdonWardrobe:RefreshItems()
    end
end

function CaerdonWardrobeConfigMixin:OnSave()
    -- Make sure that errors aren't swallowed for InterfaceOption callbacks
    xpcall(function()
        CaerdonWardrobe:RefreshItems()
    end, geterrorhandler())
end

function CaerdonWardrobeConfigMixin:OpenDebugFrame()
    -- Find and open our Debug Frame feature
    local frame = _G["CaerdonWardrobe"]
    local features = frame:GetRegisteredFeatures()
    for _, feature in pairs(features) do
        if feature:GetName() == "DebugFrame" then
            feature:ToggleDebugFrame()
            return
        end
    end
end

function NS:GetDefaultConfig()
    return {
        Version = 25,
        -- The last one-time chat message shown. A fresh install has nothing to catch up on.
        MessageSeen = #MESSAGES,

        Debug = {
            Enabled = false,
            ShowDebugFrame = false
        },

        Icon = {
            EnableAnimation = true,
            Position = "TOPLEFT",
            -- Size in percent of each window's own icon size, and a nudge to the right / upwards in
            -- pixels on a standard slot.
            Scale = 100,
            OffsetX = 0,
            OffsetY = 0,
            -- The item level gain ("+5") on an upgrade.
            UpgradeDelta = {
                Position = "BOTTOMRIGHT",
                Scale = 100,
                OffsetX = 0,
                OffsetY = 0
            },

            ShowLearnable = {
                BankAndBags = true,
                GuildBank = true,
                Merchant = true,
                Auction = true,
                SameLookDifferentItem = false,
                SameLookDifferentLevel = true
            },

            ShowUpgrades = {
                BankAndBags = true
            },

            ShowLearnableByOther = {
                BankAndBags = true,
                GuildBank = true,
                Merchant = true,
                Auction = true,
                BlackMarket = true,
                CustomerOrders = true,
                Loot = true,
                GroupLoot = true,
                QuestLog = true,
                Mail = true,
                TradeSkill = true,
                DressingRoom = true,
                EncounterJournal = true
            },

            ShowSellable = {
                BankAndBags = true,
                GuildBank = false
            },

            ShowOldExpansion = {
                Unknown = false,
                Reagents = true,
                Usable = false,
                Other = false,
                Auction = true
            },

            ShowQuestItems = true,
            ShowUpcomingQuestItems = true,
            ShowAuctionValue = true,
            ShowOutdatedFood = true,
            ShowRecipesForOtherToons = true,
            ShowBagUpgrades = true,
            ShowSpareBags = true,
            AuctionMinProfit = "auto",
            ShowUpgradeLevelDelta = false,
            SameLevelBehavior = "none",
            ShowUpgradeIcon = true,
            ShowMismatchedSpecUpgrades = false,
        },

        Binding = {
            ShowStatus = {
                BankAndBags = true,
                GuildBank = true,
                Merchant = true
            },

            ShowBoA = true,
            ShowBoARepItems = false,
            ShowBoE = true,
            ShowGearSets = true,
            ShowGearSetsAsIcon = false,
            Position = "BOTTOM",
            Scale = 100,
            OffsetX = 0,
            OffsetY = 0,
            -- A gear set's name is drawn in the binding text's place and has its own layout.
            GearSet = {
                Position = "BOTTOM",
                Scale = 100,
                OffsetX = 0,
                OffsetY = 0
            }
        },

        Merchant = {
            Filter = {
                HideCollected = false,
                SuppressLegionRemixHelperWarning = false
            }
        },

        Tooltip = {
            ShowRecipeLearners = true
        }
    }
end
