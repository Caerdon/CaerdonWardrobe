local CaerdonWardrobeConfigIcons = CreateFromMixins(CaerdonWardrobeConfigPanelMixin)

local ADDON_NAME, NS = ...
local L = NS.L

-- One block per icon the addon draws: what it means, where it shows, and its rules. A window
-- only gets a checkbox where the choice is real: the icon can occur there and someone could
-- reasonably not want it.

local STORE_ICON_COORDS = { 16 / 64, 48 / 64, 16 / 64, 48 / 64 }
local ARROW_COORDS = { -1 / 32, 33 / 32, -1 / 32, 33 / 32 }
local CIRCLE = {
    texture = "Interface\\HUD\\UIUnitFrameBoss2x",
    coords = { (512 - 46 - 31) / 512, (512 - 31) / 512, 5 / 512, (5 + 46) / 512 },
    color = { 0, 1, 1 }
}
-- The green variants of the star and the question mark, to use inside a sentence.
local GREEN_STAR = "|TInterface\\Store\\category-icon-featured:14:14:0:0:64:64:16:48:16:48:102:255:0|t"
local GREEN_OTHER = "|TInterface\\Store\\category-icon-placeholder:14:14:0:0:64:64:16:48:16:48:102:255:0|t"

-- Windows that load on demand are missing on some clients (the dungeon journal on WoW Forever).
-- The guild bank exists on every client this addon supports, so it tells whether the answers
-- can be trusted at all; when they cannot, every window is offered.
local function IsWindowAddOnAvailable(addOnName)
    if not (C_AddOns and C_AddOns.GetAddOnInfo) then
        return true
    end
    local function available(name)
        local ok, _, _, _, loadable, reason = pcall(C_AddOns.GetAddOnInfo, name)
        if not ok then
            return nil
        end
        return (loadable or reason == "DEMAND_LOADED" or reason == "DEP_DEMAND_LOADED") and true or false
    end
    if not available("Blizzard_GuildBankUI") then
        return true
    end
    return available(addOnName) ~= false
end

-- Every window with its own "learning for another toon" choice. The world map, missions, the
-- Great Vault and item conversion only show items picked for this toon, so they have none.
local OTHER_TOON_WINDOWS = {
    { value = "BankAndBags",      text = "Bags and bank" },
    { value = "GuildBank",        text = "Guild bank" },
    { value = "Merchant",         text = "Vendor" },
    { value = "Auction",          text = "Auction house" },
    { value = "BlackMarket",      text = "Black Market",    addOn = "Blizzard_BlackMarketUI" },
    { value = "CustomerOrders",   text = "Crafting orders", addOn = "Blizzard_ProfessionsCustomerOrders" },
    { value = "Loot",             text = "Loot window" },
    { value = "GroupLoot",        text = "Loot rolls" },
    { value = "QuestLog",         text = "Quest rewards" },
    { value = "Mail",             text = "Mail" },
    { value = "TradeSkill",       text = "Professions",     addOn = "Blizzard_Professions" },
    { value = "DressingRoom",     text = "Dressing room" },
    { value = "EncounterJournal", text = "Dungeon journal", addOn = "Blizzard_EncounterJournal" },
}

function CaerdonWardrobeConfigIcons:GetTitle()
    return "Icons"
end

function CaerdonWardrobeConfigIcons:Register()
    self:Init()

    self:AddTitle("Icons",
        "What each icon means, where it shows, and the rules behind it. Hover over an option for details.")

    ---------------------------------------------------------------------------------------------
    self:AddIconHeader({
        title = "Learnable by this toon",
        description = "An appearance, recipe, pet, mount or toy this toon can learn. " ..
            GREEN_STAR .. " Green: a look you already have from another item, or an ensemble with only a few pieces for this toon.",
        texture = "Interface\\Store\\category-icon-featured",
        coords = STORE_ICON_COORDS
    })
    self:AddLabel("Show in:")
    self:AddCheckboxGrid({
        { key = "learnableInBankAndBags", text = "Bags and bank", tooltip = "Show the icon on items in your bags and bank.", configSection = "Icon", configSubsection = "ShowLearnable", configValue = "BankAndBags" },
        { key = "learnableInGuildBank", text = "Guild bank", tooltip = "Show the icon on items in the guild bank.", configSection = "Icon", configSubsection = "ShowLearnable", configValue = "GuildBank" },
        { key = "learnableInMerchant", text = "Vendor", tooltip = "Show the icon on items a vendor sells. An item you already carry a copy of is not marked.", configSection = "Icon", configSubsection = "ShowLearnable", configValue = "Merchant" },
        { key = "learnableInAuction", text = "Auction house", tooltip = "Show the icon on auction house listings.", configSection = "Icon", configSubsection = "ShowLearnable", configValue = "Auction" },
    })
    self:AddLabel("Always shown everywhere else: loot, rolls, mail, quest rewards and the like.")
    local sameLook = self:AddCheckbox({ key = "sameLookDifferentItem", text = "Also items that share a look I already have (green star)", tooltip = "Marks every item that gives an appearance you already know from a different item, for collecting each source of a look. These get the green star.", configSection = "Icon", configSubsection = "ShowLearnable", configValue = "SameLookDifferentItem" })
    self:AddCheckbox({ key = "sameLookDifferentLevel", text = "Including when a lower-level toon could use this one", tooltip = "Also marks an item whose look you know when its level requirement is lower than the item you learned it from, so a lower-level toon could use it for transmog.", configSection = "Icon", configSubsection = "ShowLearnable", configValue = "SameLookDifferentLevel" },
        { indent = 1, dependsOn = sameLook })
    self:AddCheckbox({ key = "showBagUpgrades", text = "Bags for an empty bag slot, or bigger than one I have equipped", tooltip = "Marks a bag that fits one of your bag slots when that slot is empty or holds a bag it improves on: a smaller bag of the same kind, a profession bag no bigger than an ordinary bag, or a profession bag smaller than a reagent bag. A profession bag is only marked for an empty slot when you have a profession that uses it, a quiver or ammo pouch when you have a bow, crossbow or gun equipped. Quivers are only compared with their own kind.", configSection = "Icon", configValue = "ShowBagUpgrades" })

    ---------------------------------------------------------------------------------------------
    self:AddIconHeader({
        title = "Learning for another toon",
        description = "This toon cannot use it, but it can still be learned for your collection or by another toon. " ..
            GREEN_OTHER .. " Green: one of your toons already has it.",
        texture = "Interface\\Store\\category-icon-placeholder",
        coords = STORE_ICON_COORDS
    })
    local otherToonWindows = {}
    for _, window in ipairs(OTHER_TOON_WINDOWS) do
        if not window.addOn or IsWindowAddOnAvailable(window.addOn) then
            table.insert(otherToonWindows, {
                key = "otherToonIn" .. window.value,
                text = window.text,
                tooltip = "Show the icon in this window.",
                configSection = "Icon",
                configSubsection = "ShowLearnableByOther",
                configValue = window.value
            })
        end
    end
    local otherToonLabelY = self:AddLabel("Show in:")
    self:AddAllNoneButtons(otherToonLabelY, self:AddCheckboxGrid(otherToonWindows))
    self:AddCheckbox({ key = "showRecipesForOtherToons", text = "Recipes another of my toons can learn", tooltip = "Marks a recipe this toon already knows or cannot learn when another of your toons on this realm has the profession and has not learned it. That toon has to have opened its profession window once so its recipes are recorded. With this off, other toons are ignored and a recipe this toon knows shows as sellable.", configSection = "Icon", configValue = "ShowRecipesForOtherToons" })

    ---------------------------------------------------------------------------------------------
    self:AddIconHeader({
        title = "Upgrade",
        description = "Gear better than what is equipped. Yellow: Pawn says so. Green: higher item level. Red: for another spec. On an item that also has a look to learn, the arrow sits on that icon as a small badge.",
        texture = "Interface\\Buttons\\JumpUpArrow",
        coords = ARROW_COORDS,
        color = { 0.4, 1, 0.2 },
        inset = 4,
        background = CIRCLE
    })
    local showUpgrade = self:AddCheckbox({ key = "showUpgradeIcon", text = "Show the upgrade arrow", tooltip = "Shows the arrow when Pawn calls an item an upgrade or, without a Pawn verdict, when its item level is higher than what is equipped.", configSection = "Icon", configValue = "ShowUpgradeIcon" })
    self:AddCheckbox({ key = "showUpgradeInBankAndBags", text = "In bags and bank", tooltip = "Show the arrow on items in your bags and bank. Everywhere else it follows the option above.", configSection = "Icon", configSubsection = "ShowUpgrades", configValue = "BankAndBags" },
        { indent = 1, dependsOn = showUpgrade })
    self:AddCheckbox({ key = "showMismatchedSpecUpgrade", text = "Also higher item level gear for another loot spec", tooltip = "Keeps the arrow, tinted red, on an item with a higher item level that does not match your current loot specialization.", configSection = "Icon", configValue = "ShowMismatchedSpecUpgrades" },
        { indent = 1, dependsOn = showUpgrade })
    self:AddCheckbox({ key = "showUpgradeLevelDelta", text = "Show the item level gain", tooltip = "Displays the item level difference, such as +5, on an upgrade.", configSection = "Icon", configValue = "ShowUpgradeLevelDelta" })
    self:AddDropdown({ key = "sameLevelItems", text = "Same item level as equipped:", configSection = "Icon", configValue = "SameLevelBehavior" }, {
        { title = "No Icon", value = "none", tooltip = "Keep same-level pieces quiet (no neutral or sellable icons)." },
        { title = "Sellable", value = "sellable", tooltip = "Treat same-level pieces as sellable duplicates." },
        { title = "Neutral Balance", value = "neutral", tooltip = "Show the neutral balance icon so you can evaluate them manually." }
    })

    ---------------------------------------------------------------------------------------------
    self:AddIconHeader({
        title = "Needed for a quest",
        description = "A quest item, or anything a quest will ask you to hand in.",
        texture = "Interface\\MINIMAP\\MapQuestHub_Icon32",
        coords = ARROW_COORDS
    })
    local showQuest = self:AddCheckbox({ key = "showQuestItems", text = "Show the quest icon", tooltip = "Marks quest items and items that a quest in your log takes. One switch for every window.", configSection = "Icon", configValue = "ShowQuestItems" })
    self:AddCheckbox({ key = "showUpcomingQuestItems", text = "Also for quests I have not picked up yet (needs QuestieDB)", tooltip = "Also marks items that a quest you have not picked up yet will ask for, as long as you can take the quest within a few levels and it is not trivial for you. Uses the QuestieDB addon's data; without it only the quests in your log are checked.", configSection = "Icon", configValue = "ShowUpcomingQuestItems" },
        { indent = 1, dependsOn = showQuest })

    ---------------------------------------------------------------------------------------------
    self:AddIconHeader({
        title = "Worth auctioning",
        description = "Sells for enough more on the auction house than at a vendor to be worth the trip. Needs Auctionator.",
        atlas = "Auctioneer",
        texture = "Interface\\MoneyFrame\\UI-GoldIcon"
    })
    local showAuction = self:AddCheckbox({ key = "showAuctionValue", text = "Show in bags and bank", tooltip = "Shows an auction icon in place of the sellable icon, and on trade goods with no other icon, when Auctionator's price, after the auction house cut and a deposit allowance, beats the vendor price by enough to be worth the trip. Stackable goods are judged on everything you own. Learnable, upgrade and quest icons always come first.", configSection = "Icon", configValue = "ShowAuctionValue" })
    self:AddDropdown({ key = "auctionMinProfit", text = "Minimum profit:", configSection = "Icon", configValue = "AuctionMinProfit", width = 190 }, {
        { title = "Automatic (25c per level)", value = "auto",  tooltip = "Scales with your level: 2s 50c at level 10, 15s at level 60." },
        { title = "1 silver",                  value = "100",   tooltip = "List anything that clears 1 silver over vendoring." },
        { title = "5 silver",                  value = "500",   tooltip = "Require 5 silver over vendoring." },
        { title = "10 silver",                 value = "1000",  tooltip = "Require 10 silver over vendoring." },
        { title = "50 silver",                 value = "5000",  tooltip = "Require 50 silver over vendoring." },
        { title = "1 gold",                    value = "10000", tooltip = "Require 1 gold over vendoring." },
        { title = "5 gold",                    value = "50000", tooltip = "Require 5 gold over vendoring." }
    }, { indent = 1, dependsOn = showAuction })

    ---------------------------------------------------------------------------------------------
    self:AddIconHeader({
        title = "Sellable",
        description = "Something this toon has no further use for and can sell to a vendor.",
        texture = "Interface\\Store\\category-icon-bag",
        coords = STORE_ICON_COORDS
    })
    self:AddLabel("Show in:")
    self:AddCheckboxGrid({
        { key = "sellableInBankAndBags", text = "Bags and bank", tooltip = "Show the icon on items in your bags and bank.", configSection = "Icon", configSubsection = "ShowSellable", configValue = "BankAndBags" },
        { key = "sellableInGuildBank", text = "Guild bank", tooltip = "Show the icon on items in the guild bank.", configSection = "Icon", configSubsection = "ShowSellable", configValue = "GuildBank" },
    })
    self:AddCheckbox({ key = "showOutdatedFood", text = "Food and drink I have outgrown", tooltip = "Shows the sellable icon on food or drink when you carry a better one of the same kind that you can use. Your best food and best drink are never marked. Hunters keep food their pet still eats.", configSection = "Icon", configValue = "ShowOutdatedFood" })
    self:AddCheckbox({ key = "showSpareBags", text = "Bags no bigger than the ones I have equipped", tooltip = "Shows the sellable icon on a bag when every bag slot it fits is filled and it would improve none of them. Never while such a slot is empty, and never when the comparison is unclear, such as a herb bag against a reagent bag. A quiver is only marked when you have one of its kind equipped that is at least as big.", configSection = "Icon", configValue = "ShowSpareBags" })

    ---------------------------------------------------------------------------------------------
    self:AddIconHeader({
        title = "From an older expansion",
        description = "Left over from an earlier expansion, to help clear out the bags.",
        texture = "Interface\\Store\\category-icon-wow",
        coords = STORE_ICON_COORDS
    })
    self:AddLabel("Mark:")
    self:AddCheckboxGrid({
        { key = "showOldExpansionReagents", text = "Reagents", tooltip = "Add the icon to reagents from older expansions.", configSection = "Icon", configSubsection = "ShowOldExpansion", configValue = "Reagents" },
        { key = "showOldExpansionUsable", text = "Usable items", tooltip = "Add the icon to usable items from older expansions.", configSection = "Icon", configSubsection = "ShowOldExpansion", configValue = "Usable" },
        { key = "showOldExpansionOther", text = "Other items", tooltip = "Add the icon to any other items from older expansions.", configSection = "Icon", configSubsection = "ShowOldExpansion", configValue = "Other" },
        { key = "showOldExpansionUnknown", text = "Unknown expansion", tooltip = "Add the icon to items that do not say which expansion they are from. This happens more often than it should and is rarely useful.", configSection = "Icon", configSubsection = "ShowOldExpansion", configValue = "Unknown" },
    })
    self:AddCheckbox({ key = "showOldExpansionInAuction", text = "Show in the auction house", tooltip = "Also show the icon on auction house listings, for the kinds of item chosen above.", configSection = "Icon", configSubsection = "ShowOldExpansion", configValue = "Auction" })

    ---------------------------------------------------------------------------------------------
    self:AddIconHeader({
        title = "Binding text",
        description = "Text on the item saying how it binds or which gear set it belongs to.",
        label = "BoE"
    })
    self:AddLabel("Show in:")
    self:AddCheckboxGrid({
        { key = "bindingInBankAndBags", text = "Bags and bank", tooltip = "Show binding text on items in your bags and bank.", configSection = "Binding", configSubsection = "ShowStatus", configValue = "BankAndBags" },
        { key = "bindingInGuildBank", text = "Guild bank", tooltip = "Show binding text on items in the guild bank.", configSection = "Binding", configSubsection = "ShowStatus", configValue = "GuildBank" },
        { key = "bindingInMerchant", text = "Vendor", tooltip = "Show binding text on items a vendor sells.", configSection = "Binding", configSubsection = "ShowStatus", configValue = "Merchant" },
    })
    self:AddLabel("Show:")
    self:AddCheckboxGrid({
        { key = "showBoE", text = "Bind on equip", tooltip = "Shows BoE on items that bind when equipped.", configSection = "Binding", configValue = "ShowBoE" },
        { key = "showBoA", text = "Bind on account", tooltip = "Shows BoA on items that are bound to your account.", configSection = "Binding", configValue = "ShowBoA" },
        { key = "showBoARepItems", text = "Reputation items (BoA)", tooltip = "Shows BoA on account-bound reputation items.", configSection = "Binding", configValue = "ShowBoARepItems" },
        { key = "showGearSets", text = "Gear set names", tooltip = "Shows the gear set's name on items that belong to a saved gear set.", configSection = "Binding", configValue = "ShowGearSets" },
        { key = "showGearSetsAsIcon", text = "Gear set icon", tooltip = "Shows an icon on items that belong to a saved gear set.", configSection = "Binding", configValue = "ShowGearSetsAsIcon" },
    })

    self:FinishLayout()
end

SettingsRegistrar:AddRegistrant(function() CaerdonWardrobeConfigIcons:Register() end)
