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
        if CaerdonWardrobeConfig.Icon.ShowQuestItemsInAuction == nil then
            CaerdonWardrobeConfig.Icon.ShowQuestItemsInAuction = NS:GetDefaultConfig().Icon.ShowQuestItemsInAuction
        end
        if CaerdonWardrobeConfig.Icon.UpcomingQuestLevels == nil then
            CaerdonWardrobeConfig.Icon.UpcomingQuestLevels = NS:GetDefaultConfig().Icon.UpcomingQuestLevels
        end
        if CaerdonWardrobeConfig.Icon.IncludeTrivialQuests == nil then
            CaerdonWardrobeConfig.Icon.IncludeTrivialQuests = NS:GetDefaultConfig().Icon.IncludeTrivialQuests
        end
        if CaerdonWardrobeConfig.Icon.ShowAuctionValue == nil then
            CaerdonWardrobeConfig.Icon.ShowAuctionValue = NS:GetDefaultConfig().Icon.ShowAuctionValue
        end
        if CaerdonWardrobeConfig.Icon.ShowLooksAfterChange == nil then
            CaerdonWardrobeConfig.Icon.ShowLooksAfterChange = NS:GetDefaultConfig().Icon.ShowLooksAfterChange
        end
        if CaerdonWardrobeConfig.Icon.ShowOutdatedFood == nil then
            CaerdonWardrobeConfig.Icon.ShowOutdatedFood = NS:GetDefaultConfig().Icon.ShowOutdatedFood
        end
        if CaerdonWardrobeConfig.Icon.ShowRecipesForOtherToons == nil then
            CaerdonWardrobeConfig.Icon.ShowRecipesForOtherToons = NS:GetDefaultConfig().Icon.ShowRecipesForOtherToons
        end
        for _, key in ipairs({ "ShowIngredientsForOtherToons", "IngredientsForOtherToons", "ShowOutgrownIngredients",
            "AuctionTradeGoods" }) do
            if CaerdonWardrobeConfig.Icon[key] == nil then
                CaerdonWardrobeConfig.Icon[key] = NS:GetDefaultConfig().Icon[key]
            end
        end
        if CaerdonWardrobeConfig.Icon.ShowBagUpgrades == nil then
            CaerdonWardrobeConfig.Icon.ShowBagUpgrades = NS:GetDefaultConfig().Icon.ShowBagUpgrades
        end
        if CaerdonWardrobeConfig.Icon.ShowSpareBags == nil then
            CaerdonWardrobeConfig.Icon.ShowSpareBags = NS:GetDefaultConfig().Icon.ShowSpareBags
        end
        if CaerdonWardrobeConfig.Icon.ShowOnDialogueUI == nil then
            CaerdonWardrobeConfig.Icon.ShowOnDialogueUI = NS:GetDefaultConfig().Icon.ShowOnDialogueUI
        end
        if not CaerdonWardrobeConfig.Tooltip then
            CaerdonWardrobeConfig.Tooltip = {}
        end
        if CaerdonWardrobeConfig.Tooltip.ShowRecipeLearners == nil then
            CaerdonWardrobeConfig.Tooltip.ShowRecipeLearners = NS:GetDefaultConfig().Tooltip.ShowRecipeLearners
        end
        if CaerdonWardrobeConfig.Tooltip.ShowLoadoutUpgrades == nil then
            CaerdonWardrobeConfig.Tooltip.ShowLoadoutUpgrades = NS:GetDefaultConfig().Tooltip.ShowLoadoutUpgrades
        end
        if CaerdonWardrobeConfig.Tooltip.KeepPawnUpgradeNotes == nil then
            CaerdonWardrobeConfig.Tooltip.KeepPawnUpgradeNotes = NS:GetDefaultConfig().Tooltip.KeepPawnUpgradeNotes
        end
        if CaerdonWardrobeConfig.Tooltip.ShowSetBonusChanges == nil then
            CaerdonWardrobeConfig.Tooltip.ShowSetBonusChanges = NS:GetDefaultConfig().Tooltip.ShowSetBonusChanges
        end
        if not CaerdonWardrobeConfig.Auction then
            CaerdonWardrobeConfig.Auction = {}
        end
        if CaerdonWardrobeConfig.Auction.UpgradeColumn == nil then
            CaerdonWardrobeConfig.Auction.UpgradeColumn = NS:GetDefaultConfig().Auction.UpgradeColumn
        end
        if type(CaerdonWardrobeConfig.DaylightUI) ~= "table" then
            CaerdonWardrobeConfig.DaylightUI = {}
        end
        if CaerdonWardrobeConfig.DaylightUI.OwnLayoutInBags == nil then
            CaerdonWardrobeConfig.DaylightUI.OwnLayoutInBags = NS:GetDefaultConfig().DaylightUI.OwnLayoutInBags
        end
        if CaerdonWardrobeConfig.Binding.ShowWuE == nil then
            CaerdonWardrobeConfig.Binding.ShowWuE = NS:GetDefaultConfig().Binding.ShowWuE
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
        -- "Also for gear I am not wearing" took the place of the loot spec option, which a player
        -- may have switched on. Where it was not, the default says what the client showed
        -- before: the red arrows of the other talent trees on a client without specs.
        if CaerdonWardrobeConfig.Icon.ShowOtherSpecUpgrades == nil then
            CaerdonWardrobeConfig.Icon.ShowOtherSpecUpgrades =
                CaerdonWardrobeConfig.Icon.ShowMismatchedSpecUpgrades == true or
                NS:GetDefaultConfig().Icon.ShowOtherSpecUpgrades
        end
        if CaerdonWardrobeConfig.Icon.ShowUpgradeOnGearSets == nil then
            CaerdonWardrobeConfig.Icon.ShowUpgradeOnGearSets = NS:GetDefaultConfig().Icon.ShowUpgradeOnGearSets
        end
        if CaerdonWardrobeConfig.Icon.ShowItemLevelUpgrades == nil then
            CaerdonWardrobeConfig.Icon.ShowItemLevelUpgrades = NS:GetDefaultConfig().Icon.ShowItemLevelUpgrades
        end
        if CaerdonWardrobeConfig.Icon.ItemLevelOverPawn == nil then
            CaerdonWardrobeConfig.Icon.ItemLevelOverPawn = NS:GetDefaultConfig().Icon.ItemLevelOverPawn
        end
        NS:LoadCharacterConfig()

        CaerdonWardrobe:RefreshItems("settings", "the saved settings were loaded")
    end
end

-- The toon's own settings (CaerdonWardrobeCharacterConfig, saved per character), for the few
-- that describe the toon and not the player's taste. Today that is the one list of the Icons
-- page's upgrade block:
--   Icon.OtherSpecs: class file and spec index ("DRUID2") = false for a spec whose upgrades
--   the player does not want shown while the toon plays another. Nothing there: every spec.
--   Icon.OtherSets: gear set ID = false, the same for a set tied to a scale that no spec owns.
--   Icon.GearSetScales: gear set ID = the Pawn scale the set is scored on.
--   Icon.PvpSets: gear set ID = true for a set that is scored at PVP levels.
-- The table has no defaults, no version and no migrations: it is made by the first choice on a
-- page, and a reader takes a missing table or key as "never chosen".
function NS:LoadCharacterConfig()
    -- The spec choice was kept by class with the player's settings before (in no release).
    -- The first toon of a class to log in takes what its class had.
    local icon = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon
    local byClass = type(icon) == "table" and icon.OtherSpecs
    if type(byClass) ~= "table" then
        return
    end
    local _, classFile = UnitClass("player")
    if classFile then
        for key, value in pairs(byClass) do
            if type(key) == "string" and key:sub(1, #classFile) == classFile and
                key:sub(#classFile + 1):match("^%d+$") then
                if type(CaerdonWardrobeCharacterConfig) ~= "table" then
                    CaerdonWardrobeCharacterConfig = {}
                end
                local own = CaerdonWardrobeCharacterConfig
                if type(own.Icon) ~= "table" then
                    own.Icon = {}
                end
                if type(own.Icon.OtherSpecs) ~= "table" then
                    own.Icon.OtherSpecs = {}
                end
                if own.Icon.OtherSpecs[key] == nil then
                    own.Icon.OtherSpecs[key] = value
                end
                byClass[key] = nil
            end
        end
    end
    if next(byClass) == nil then
        icon.OtherSpecs = nil
    end
end

function CaerdonWardrobeConfigMixin:OnSave()
    -- Make sure that errors aren't swallowed for InterfaceOption callbacks
    -- A click has refreshed already (the page's own, which names the value it wrote); this one
    -- is the settings window's own commit, which comes as it shuts, and says so: a session's record
    -- tells the two apart.
    xpcall(function()
        CaerdonWardrobe:RefreshItems("settings", "the settings window's commit")
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
    -- The sell icon on an outgrown ingredient starts on where bag space is short (WoW Forever)
    -- and off on retail, where a finished expansion's recipes are all gray and its reagents are
    -- kept all the same. A starting value, not a code path: the rule is the same on both.
    local outgrownIngredients = CaerdonAPI ~= nil and CaerdonAPI.IsForeverClient ~= nil and
        CaerdonAPI:IsForeverClient() == true

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
            -- The quest icon on auction house listings: where an item for a quest still to
            -- come is bought.
            ShowQuestItemsInAuction = true,
            -- How many levels ahead a quest the toon cannot take yet still counts as coming
            -- ("2", "5", "10", "20", "any": a dropdown's values are text), and whether a quest
            -- that is trivial for the toon counts.
            UpcomingQuestLevels = "5",
            IncludeTrivialQuests = false,
            ShowAuctionValue = true,
            -- A piece whose own look is known and which would have an unknown one raised on
            -- its upgrade track or converted at the Catalyst (CaerdonTransformLooks.lua).
            ShowLooksAfterChange = true,
            ShowOutdatedFood = true,
            ShowRecipesForOtherToons = true,
            -- Ingredients (CaerdonIngredients.lua): the mail icon on one another toon's recipes
            -- take ("skill": that still give it skill; "any": that it knows at all), the sell
            -- icon on one this toon's recipes have outgrown, and which trade goods the auction
            -- icon leaves alone ("all" none, "skill", "professions", "none" every one).
            ShowIngredientsForOtherToons = true,
            IngredientsForOtherToons = "skill",
            ShowOutgrownIngredients = outgrownIngredients,
            AuctionTradeGoods = "skill",
            ShowBagUpgrades = true,
            ShowSpareBags = true,
            -- The Dialogue UI addon's quest rewards (external/DialogueUI).
            ShowOnDialogueUI = true,
            AuctionMinProfit = "auto",
            ShowUpgradeLevelDelta = false,
            SameLevelBehavior = "none",
            ShowUpgradeIcon = true,
            -- The red arrow: an upgrade for another of the toon's specs. On where the client has
            -- talent trees in place of specs (Pawn shows a scale per tree there, and those
            -- arrows were always shown), off where it has specs.
            ShowOtherSpecUpgrades = C_Traits ~= nil and C_Traits.GetGroupDisplayInfoByTreeID ~= nil,
            -- Which of the toon's specs that is for is the toon's own setting
            -- (CaerdonWardrobeCharacterConfig.Icon.OtherSpecs, NS:LoadCharacterConfig).
            -- The arrow on a piece of a saved gear set. Off: such a piece never gets it.
            ShowUpgradeOnGearSets = true,
            -- With Pawn loaded: a higher item level than the worn piece is an upgrade where Pawn
            -- has no verdict, and (the second) even where Pawn's scores prefer the worn piece.
            ShowItemLevelUpgrades = true,
            ItemLevelOverPawn = false,
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
            ShowWuE = true,
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

        -- The addon's own columns in the auction house's lists (features/Auction.lua). The
        -- icon's has no setting: it is there while an icon is switched on for the auction house.
        Auction = {
            UpgradeColumn = true
        },

        -- Daylight UI's bags and bank put the status icon in a corner of their own, at their
        -- own size. On: by the player's layout, as everywhere else (the layout editor's box;
        -- external/DaylightUI).
        DaylightUI = {
            OwnLayoutInBags = false
        },

        Tooltip = {
            ShowRecipeLearners = true,
            -- The line under a piece that is an upgrade for a gear set or another spec.
            ShowLoadoutUpgrades = true,
            -- Pawn's own upgrade notes and "your best" marks beside those lines, as Pawn
            -- makes them. Off: they give way where the addon has a verdict of its own.
            KeepPawnUpgradeNotes = false,
            -- The line under a piece that would bring or end a set bonus of what is worn.
            ShowSetBonusChanges = true
        }
    }
end
