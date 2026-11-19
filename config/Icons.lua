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
-- The two marks of a piece kept for a look it would gain, as they are drawn on a button.
local CATALYST_MARK = "|A:CreationCatalyst-32x32:14:14|a"
local VENDOR_MARK = "|A:Crosshair_Reforge_32:14:14|a"

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

-- A spec switch's tooltip: what it does, why it is on or off right now, and where it is kept.
-- reason: what CaerdonEquipment:GetOtherSpecChoice says (the equipment code's names).
local FOLLOWS = " Until you click it, it follows the gear sets you assign and the scales you have Pawn show."
local function OtherSpecTooltip(specName, wanted, reason)
    local why
    if reason == "chosen" then
        why = (wanted and "On" or "Off") .. " by your choice."
    elseif reason == "gearSet" then
        why = "On because a gear set is assigned to " .. specName .. "." .. FOLLOWS
    elseif reason == "pawnShown" then
        why = "On because Pawn is set to show the " .. specName .. " scale." .. FOLLOWS
    elseif reason == "pawnHidden" then
        why = "Off because no gear set is assigned to " .. specName .. " and Pawn is not set to show its scale." .. FOLLOWS
    else
        -- No gear set, and Pawn is not loaded or picks the scale it shows by itself.
        why = "Off because no gear set is assigned to " .. specName .. "." .. FOLLOWS
    end
    return "Show upgrades for " .. specName .. " while you play another specialization.\n\n" .. why ..
        "\n\nKept for this character only."
end

-- Under "Also for my other specs": one switch per spec of the toon's class, for a player who
-- only cares about some of them. Only where the client has specs (with talent trees in their
-- place, Pawn's own list of shown scales is the choice). Which specs a toon plays is a fact
-- about the toon, so this is the one choice on the page that is kept per character, and its
-- label says so.
function CaerdonWardrobeConfigIcons:AddOtherSpecChoices(dependsOn)
    if C_Traits ~= nil and C_Traits.GetGroupDisplayInfoByTreeID ~= nil then
        return
    end
    local countSpecs = C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID
    if not (countSpecs and GetSpecializationInfoForClassID) then
        return
    end
    local _, classFile, classID = UnitClass("player")
    local count = classID and countSpecs(classID) or 0
    if not classFile or count < 2 then
        return
    end

    local infos = {}
    for specIndex = 1, count do
        local _, specName = GetSpecializationInfoForClassID(classID, specIndex)
        if specName then
            infos[#infos + 1] = {
                key = "otherSpec" .. specIndex,
                text = specName,
                -- Built as the tooltip opens: it says why the switch is as it is, which for one
                -- never clicked is the game's or Pawn's doing and can change by itself.
                tooltip = function()
                    return OtherSpecTooltip(specName, CaerdonEquipment:GetOtherSpecChoice(specIndex))
                end,
                configSection = "Icon",
                configSubsection = "OtherSpecs",
                configValue = classFile .. specIndex,
                -- Never clicked: what the equipment code takes the spec as right now.
                default = function()
                    return CaerdonEquipment:IsOtherSpecWantedByDefault(specIndex)
                end,
                perCharacter = true,
            }
        end
    end
    if #infos > 0 then
        local name = UnitName("player")
        local whose = name and name ~= UNKNOWNOBJECT and (name .. "'s") or "this character's"
        self:AddLabel("Which of " .. whose .. " specs (kept per character):", { indent = 2 })
        self:AddCheckboxGrid(infos, { indent = 2, dependsOn = dependsOn })
    end
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
        title = "A look to gain later",
        description = "You know this piece's look, but upgraded or converted at the Catalyst it would have one you do not. " ..
            "A small mark to keep it by; it is not offered for sale. " ..
            CATALYST_MARK .. " Take it to the Catalyst. " .. VENDOR_MARK .. " Raise it at the item upgrade vendor. " ..
            "Both: the vendor's mark with a small Catalyst's mark on it.",
        atlas = "CreationCatalyst-32x32",
        texture = "Interface\\Buttons\\UI-RefreshButton"
    })
    self:AddCheckbox({ key = "showLooksAfterChange", text = "Mark gear that can become a look I do not have", tooltip = "Marks a piece of this season's gear whose own look you know when raising it on its upgrade track, or converting it at the Catalyst, would give a look you have not learned. The icon says where to take it: the Catalyst's mark, or the upgrade vendor's for a piece that has to be raised. The vendor's mark with a small Catalyst's mark on it means both have a part. An upgrade keeps its arrow, and shows the mark where the arrow is switched off. Not shown on a gear set's piece. Shown wherever the learnable icon is. With this off such a piece is judged like any other whose look you know, so it can get the sellable or auction icon.", configSection = "Icon", configValue = "ShowLooksAfterChange" })

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
    ---------------------------------------------------------------------------------------------
    self:AddIconHeader({
        title = "For another toon to use",
        description = "Something another of your toons on this realm has a use for and this one does not: mail it. Hover over it for the toon's name. Shown in the windows chosen above for \"Learning for another toon\". The other toon has to have opened its profession window once, so that its recipes are recorded.",
        atlas = "ui-hud-minimap-mail-up",
        texture = "Interface\\MailFrame\\Mail-Icon"
    })
    self:AddCheckbox({ key = "showRecipesForOtherToons", text = "Recipes they have not learned", tooltip = "Marks a recipe this toon already knows or cannot learn when another of your toons on this realm has the profession and has not learned it. With this off, other toons are ignored and a recipe this toon knows shows as sellable.", configSection = "Icon", configValue = "ShowRecipesForOtherToons" })
    local sendIngredients = self:AddCheckbox({ key = "showIngredientsForOtherToons", text = "Ingredients this toon has no use for", tooltip = "Marks an ingredient that a recipe of another of your toons takes, when no recipe of this toon's still gives skill for it. Never on something soulbound, something a quest of this toon's takes, or food kept for a hunter's pet.", configSection = "Icon", configValue = "ShowIngredientsForOtherToons" })
    self:AddDropdown({ key = "ingredientsForOtherToons", text = "That the other toon can:", configSection = "Icon", configValue = "IngredientsForOtherToons", width = 210 }, {
        { title = "Skill up with",           value = "skill", tooltip = "Only when a recipe of that toon's still gives skill for it, a recipe it has not learned yet included." },
        { title = "Use in a recipe it knows", value = "any",   tooltip = "Also when that toon knows a recipe that takes it, even one that no longer gives skill." }
    }, { indent = 1, dependsOn = sendIngredients })

    ---------------------------------------------------------------------------------------------
    self:AddIconHeader({
        title = "Upgrade",
        description = "Gear better than what is equipped. Yellow: Pawn says so. Green: higher item level. Red: for another spec or gear set. On an item that also has a look to learn, the arrow sits on that icon as a small badge.",
        texture = "Interface\\Buttons\\JumpUpArrow",
        coords = ARROW_COORDS,
        color = { 0.4, 1, 0.2 },
        inset = 4,
        background = CIRCLE
    })
    local showUpgrade = self:AddCheckbox({ key = "showUpgradeIcon", text = "Show the upgrade arrow", tooltip = "Shows the arrow when Pawn calls an item an upgrade or, without a Pawn verdict, when its item level is higher than what is equipped.", configSection = "Icon", configValue = "ShowUpgradeIcon" })
    self:AddCheckbox({ key = "showUpgradeInBankAndBags", text = "In bags and bank", tooltip = "Show the arrow on items in your bags and bank. Everywhere else it follows the option above.", configSection = "Icon", configSubsection = "ShowUpgrades", configValue = "BankAndBags" },
        { indent = 1, dependsOn = showUpgrade })
    -- Without Pawn the item level is all the arrow goes by: both are shown as they then are, on.
    local function WithoutPawn()
        return PawnShouldItemLinkHaveUpgradeArrowUnbudgeted == nil
    end
    local WITHOUT_PAWN = "Without the Pawn addon the arrow always goes by item level."
    local showItemLevel = self:AddCheckbox({ key = "showItemLevelUpgrades", text = "Also higher item level gear", tooltip = "With Pawn: also shows the arrow, in green, on gear with a higher item level than what is equipped when Pawn has no verdict on it (a trinket, a piece Pawn has no values for, a row of the auction house's list, whose stats the game does not give until it is opened).", forcedTooltip = WITHOUT_PAWN, configSection = "Icon", configValue = "ShowItemLevelUpgrades" },
        { indent = 1, dependsOn = showUpgrade, forcedOn = WithoutPawn })
    self:AddCheckbox({ key = "itemLevelOverPawn", text = "Even when Pawn rates the equipped piece higher", tooltip = "For when item level is what counts (a gear score to reach, a game mode that goes by item level): a higher item level is then always an upgrade.", forcedTooltip = WITHOUT_PAWN, configSection = "Icon", configValue = "ItemLevelOverPawn" },
        { indent = 2, dependsOn = showItemLevel, forcedOn = WithoutPawn })
    local showOtherSpecs = self:AddCheckbox({ key = "showOtherSpecUpgrades", text = "Also for my other specs", tooltip = "Shows the arrow, in red, on gear that is an upgrade for another of your specializations. With Pawn it is scored on that spec's scale against the gear set assigned to the spec, or against what you are wearing when none is. The gear set of the spec you are playing counts the same way for a slot where you are not wearing its piece.", configSection = "Icon", configValue = "ShowOtherSpecUpgrades" },
        { indent = 1, dependsOn = showUpgrade })
    self:AddOtherSpecChoices(showOtherSpecs)
    self:AddCheckbox({ key = "showUpgradeOnGearSets", text = "On gear set pieces", tooltip = "Show the arrow on items that belong to a saved gear set. With the gear set icon on, it sits on that icon as a small badge. Off: a gear set piece never shows the arrow.", configSection = "Icon", configValue = "ShowUpgradeOnGearSets" },
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
    local showQuest = self:AddCheckbox({ key = "showQuestItems", text = "Show the quest icon", tooltip = "Marks quest items and items that a quest in your log takes. It comes before the learnable icons, because the item has to be in your bags when you hand the quest in. One switch for every window.", configSection = "Icon", configValue = "ShowQuestItems" })
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
    self:AddDropdown({ key = "auctionTradeGoods", text = "On trade goods:", configSection = "Icon", configValue = "AuctionTradeGoods", width = 230 }, {
        { title = "Any worth listing",              value = "all",         tooltip = "Every trade good with no other icon that is worth listing." },
        { title = "Not ones I still skill up with", value = "skill",       tooltip = "Leaves out an ingredient while a recipe of this toon's that takes it still gives skill." },
        { title = "Not ones my professions use",    value = "professions", tooltip = "Leaves out every ingredient a recipe of this toon's takes, gray or not." },
        { title = "Never",                          value = "none",        tooltip = "No auction icon on trade goods. It still replaces the sellable icon where the auction house pays more." }
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
    self:AddCheckbox({ key = "showOutgrownIngredients", text = "Ingredients my recipes have outgrown", tooltip = "Shows the sellable icon on an ingredient when every recipe of this toon's that takes it has gone gray, the recipes it has not learned yet included. Each profession has to have been opened once so its recipes are recorded. Never on an ingredient no recipe of yours takes, one that another toon gets the mail icon for, or food kept for a hunter's pet.", configSection = "Icon", configValue = "ShowOutgrownIngredients" })
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
        { key = "showWuE", text = "Warbound until equipped", tooltip = "Shows WuE on items you can send to your other characters until one of them equips it (\"Account bound until equipped\" on WoW Forever).", configSection = "Binding", configValue = "ShowWuE" },
        { key = "showBoA", text = "Bind on account", tooltip = "Shows BoA on items that are bound to your account.", configSection = "Binding", configValue = "ShowBoA" },
        { key = "showBoARepItems", text = "Reputation items (BoA)", tooltip = "Shows BoA on account-bound reputation items.", configSection = "Binding", configValue = "ShowBoARepItems" },
        { key = "showGearSets", text = "Gear set names", tooltip = "Shows the gear set's name on items that belong to a saved gear set.", configSection = "Binding", configValue = "ShowGearSets" },
        { key = "showGearSetsAsIcon", text = "Gear set icon", tooltip = "Shows an icon on items that belong to a saved gear set.", configSection = "Binding", configValue = "ShowGearSetsAsIcon" },
    })

    self:FinishLayout()
end

SettingsRegistrar:AddRegistrant(function() CaerdonWardrobeConfigIcons:Register() end)
