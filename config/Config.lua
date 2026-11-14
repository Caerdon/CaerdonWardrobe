CaerdonWardrobeConfigMixin = {}

local ADDON_NAME, NS = ...
local L = NS.L
local components, pendingConfig

CAERDON_CONFIG_LABEL = L["Caerdon Wardrobe... and more!"]
CAERDON_CONFIG_SUBTEXT = L[ [[
This addon started as a simple way for me to track unlearned transmog appearances.  Over the years, it has grown into so much more!

Caerdon Wardrobe now provides tracking of unlearned recipes, pets, mounts, toys, and transmog appearances.  It shows locked and openable containers.  It tracks BoE and BoA bindings, equipment sets, and can highlight gear to sell that is not tradeable, not part of a set, and has no other potentially interesting use.

New for Shadowlands, it also tracks unlearned conduits, and I've even added an old expansion indicator that can help you clean out your bags for your new journey!

Caerdon Wardrobe leverages a set of icons and text where appropriate to call out all of the above items in the following locations: Bank & Bags, Guild Banks, Auction House, Merchants, Dungeon and Raid Journal, Loot Pickup, Group Loot Roll, and the World Map.

It also provides integration for your favorite bag add-ons: AdiBags, ArkInventory, Bagnon, Bagnonium, Baud Bag, cargBags_Nivaya, ElvUI, Inventorian, and LiteBag.  Additionally it supports a few other World Quest addons: World Quest Tab and Zygor World Quest Planner.

I don't like slow addons and try my best to keep this addon from impacting your fun.  If Caerdon Wardrobe is causing a performance impact on your game, please let me know!
]] ]

function CaerdonWardrobeConfigMixin:OnLoad()
    self:RegisterEvent("VARIABLES_LOADED");

    self.name = "Caerdon Wardrobe"
    self.okay = self.OnSave

    self.OnCommit = self.okay;
    self.OnDefault = self.default;
    self.OnRefresh = self.refresh;

    local category, layout = Settings.RegisterCanvasLayoutCategory(self, self.name, self.name);
    category.ID = self.name;
    Settings.RegisterAddOnCategory(category);

    -- Any anchors assigned to the frame will be disposed. Intended anchors need to be provided through
    -- the layout object. If no anchor points are provided, the frame will be anchored to TOPLEFT (0,0)
    -- and BOTTOMRIGHT (0,0).
    -- layout:AddAnchorPoint("TOPLEFT", 10, -10);
    -- layout:AddAnchorPoint("BOTTOMRIGHT", -10, 10);

    self:CreateSupportSection()
end

local SUPPORT_URL = "https://buymeacoffee.com/caerdon"

-- Support link at the bottom of the main settings page.
function CaerdonWardrobeConfigMixin:CreateSupportSection()
    local subText = _G[self:GetName() .. "SubText"]
    if not subText then return end

    local header = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetJustifyH("LEFT")
    header:SetPoint("TOPLEFT", subText, "BOTTOMLEFT", 0, -8)
    header:SetText(L["Support Caerdon Wardrobe"])

    local body = self:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    body:SetPoint("RIGHT", self, "RIGHT", -32, 0)
    body:SetText(L["If Caerdon Wardrobe has been useful to you and you'd like to buy me a drink, this is where to do it:"])

    -- The game cannot open a browser, so the link sits in a read-only box to copy from.
    local editBox = CreateFrame("EditBox", "CaerdonWardrobeConfigSupportLink", self, "InputBoxTemplate")
    editBox:SetAutoFocus(false)
    editBox:SetSize(250, 22)
    editBox:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 6, -8)
    editBox:SetText(SUPPORT_URL)
    editBox:SetCursorPosition(0)

    local copyKey = (IsMacClient and IsMacClient()) and "Cmd+C" or "Ctrl+C"
    local hintText = string.format(L["Click the link, then press %s to copy it."], copyKey)
    local hint = self:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
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

function CaerdonWardrobeConfigMixin:OnEvent(event, ...)
    -- BlizzardOptionsPanel_OnEvent(self, event, ...);

    if (event == "VARIABLES_LOADED") then
        self.variablesLoaded = true;
        self:UnregisterEvent(event);

        if not CaerdonWardrobeConfig or CaerdonWardrobeConfig.Version ~= NS:GetDefaultConfig().Version then
            print("Caerdon: Old settings detected - updating to defaults.  Please check your settings!")
            CaerdonWardrobeConfig = CopyTable(NS:GetDefaultConfig())
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
        if CaerdonWardrobeConfig.Icon.AuctionMinProfit == nil then
            CaerdonWardrobeConfig.Icon.AuctionMinProfit = NS:GetDefaultConfig().Icon.AuctionMinProfit
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

        Debug = {
            Enabled = false,
            ShowDebugFrame = false
        },

        Icon = {
            EnableAnimation = true,
            Position = "TOPLEFT",

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
            Position = "BOTTOM"
        },

        Merchant = {
            Filter = {
                HideCollected = false,
                SuppressLegionRemixHelperWarning = false
            }
        }
    }
end
