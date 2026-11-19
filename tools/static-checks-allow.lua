-- Allowlist for tools/static-checks.lua.
--
-- Every entry is a claim about the code, and the check reports an entry that no longer
-- applies, so this file cannot quietly go stale. Add a name here only after reading the code
-- that uses it: an unguarded call to something a client lacks is a bug, not an entry.
return {
    -- Globals the addon writes on purpose. Everything else it writes is a leak.
    writePatterns = {
        "^Caerdon",              -- the addon's tables, mixins and saved variables
        "^CAERDON_",             -- its strings for XML
        "^SLASH_CAERDON%u*%d$",  -- its slash commands
    },
    writes = {
        -- Key binding labels; the names are fixed by Bindings.xml.
        "BINDING_HEADER_CAERDON",
        "BINDING_NAME_CAERDONDEBUGHOVER",
        "BINDING_NAME_COPYMOUSEOVERLINK",
        "BINDING_NAME_PRINTMOUSEOVERLINKDETAILS",
        -- Blizzard's /dump limit, raised around one dump and put back (CaerdonAPI).
        "DEVTOOLS_MAX_ENTRY_CUTOFF",
        -- Pawn's tooltip step, wrapped so that the addon's upgrade lines follow Pawn's and
        -- Pawn's note for a scale whose gear set decides is left out (features/Tooltip.lua).
        "PawnAddValuesToTooltip",
    },

    -- Globals of other addons and of the embedded libraries. Not checked against a client.
    thirdParty = {
        AngrierWorldQuests = "Angrier World Quests",
        AngrierWorldQuestsHeader = "Angrier World Quests",
        ArkInventory = "ArkInventory",
        Auctionator = "Auctionator",
        AuctionatorGroupsViewItemMixin = "Auctionator",
        Baganator = "Baganator",
        Bagnon = "Bagnon",
        Bagnonium = "Bagnonium",
        BaudBag = "BaudBag",
        CanIMogIt = "Can I Mog It",
        DUIDialogItemButtonMixin = "Dialogue UI",
        ElvUI = "ElvUI",
        KkthnxUI = "KkthnxUI",
        LegionRemixHelperDB = "Legion Remix Helper",
        LibQuestieDB = "Questie",
        LibStub = "LibStub (libs/)",
        LiteBag_AddPluginEvent = "LiteBag",
        LiteBag_RegisterHook = "LiteBag",
        NDui = "NDui",
        NarciDressingRoomItemButtonMixin = "Narcissus",
        NarciDressingRoomOverlay = "Narcissus",
        PawnAddValuesToTooltip = "Pawn",
        PawnCommon = "Pawn",
        PawnGetItemData = "Pawn",
        PawnGetItemDataForInventorySlot = "Pawn",
        PawnGetSingleValueFromItem = "Pawn",
        PawnInvalidateBestItems = "Pawn",
        PawnIsArmorBestTypeForPlayer = "Pawn",
        PawnIsItemAnUpgrade = "Pawn",
        PawnIsScaleVisible = "Pawn",
        PawnOptions = "Pawn",
        PawnResetBags = "Pawn",
        PawnResetTooltips = "Pawn",
        PawnShouldItemLinkHaveUpgradeArrowUnbudgeted = "Pawn",
        Questie = "Questie",
        QuestieLoader = "Questie",
        Skillet = "Skillet",
        VWQL = "World Quests List",
        WQT_REWARDTYPE = "World Quest Tracker",
        WorldQuestList = "World Quests List",
        WorldQuestTrackerAddon = "World Quest Tracker",
        ZygorGuidesViewer = "Zygor Guides Viewer",
    },

    -- Globals both clients have although no listing names them and no loaded Blizzard file
    -- defines them by name. Accepted only while Blizzard's own loaded code reads the name.
    unlisted = {
        -- Blizzard_SharedXMLBase/Color.lua creates one global per row of the client's color
        -- table (and a _CODE twin), so the names are data.
        GREEN_FONT_COLOR = "color table",
        HIGHLIGHT_FONT_COLOR = "color table",
        LIGHTBLUE_FONT_COLOR = "color table",
        RED_FONT_COLOR = "color table",
        YELLOW_FONT_COLOR = "color table",
        YELLOW_FONT_COLOR_CODE = "color table",
    },

    -- Names that Blizzard_Deprecated defines or wraps, which the addon may keep using: each
    -- with the reason (the addon reads no field the wrapper adds, a fallback covers its
    -- removal). Without an entry such a name is a finding: move to the new API.
    deprecated = {
        -- The housing catalog since 12.0.5. Blizzard's fallback wraps these two only to put the
        -- old fields back on the answer (entryID, quantity, numPlaced, showQuantity).
        ["C_HousingCatalog.GetCatalogEntryInfoByItem"] = "types/HousingMixin.lua reads only the new fields (recordID, entryType, totalNumStored, totalNumPlaced) and passes no second argument",
        ["C_HousingCatalog.GetCatalogEntryInfoByRecordID"] = "as above, with no third argument",
    },

    -- Names one client has and the other lacks ("retail", "forever"), or that neither has
    -- any more ("neither"), each with the guard that keeps the code off the missing one.
    clientSpecific = {
        -- Forever does not load Blizzard_EncounterJournal. Everything here runs from the
        -- ADDON_LOADED of that addon or from a hook installed there.
        ["EncounterJournal"] = { "retail", "used after Blizzard_EncounterJournal loads; Refresh tests it for nil" },
        ["EncounterJournal.IsShown"] = { "retail", "behind `if EncounterJournal`" },
        ["EncounterJournal_GetSearchDisplay"] = { "retail", "called from the search preview hook" },
        ["EncounterJournal_UpdateSearchPreview"] = { "retail", "hooked when Blizzard_EncounterJournal loads" },
        ["EJSuggestFrame_UpdateRewards"] = { "retail", "hooked when Blizzard_EncounterJournal loads" },
        ["SortItemSetItems"] = { "retail", "called from a callback registered when Blizzard_EncounterJournal loads" },

        -- Forever does not load Blizzard_GarrisonUI.
        ["CovenantMissionFrameMissions"] = { "retail", "used after Blizzard_GarrisonUI loads" },
        ["GarrisonLandingPageReportList"] = { "retail", "used after Blizzard_GarrisonUI loads" },

        -- Mail: retail has global update functions, Forever has methods on the frames.
        -- features/Mail.lua tests each with type() and hooks the one that exists.
        ["InboxFrame_Update"] = { "retail", "type() test in MailMixin:Init" },
        ["OpenMailFrame_UpdateButtonPositions"] = { "retail", "type() test in MailMixin:Init" },
        ["InboxFrame.Update"] = { "forever", "type() test in MailMixin:Init" },
        ["OpenMailFrame.UpdateButtonPositions"] = { "forever", "type() test in MailMixin:Init" },
        ["SendMailFrame.Update"] = { "neither", "fallback in MailMixin:Init; both clients have SendMailFrame_Update" },

        -- Forever's game type, talent groups and classic bag kinds.
        ["WOW_PROJECT_CAMELOT"] = { "forever", "`or 18` in CaerdonAPI" },
        ["C_Traits.GetGroupDisplayInfoByTreeID"] = { "forever", "ReadTalentTrees returns early without it" },
        ["C_Traits.GetGroupCurrencyInfo"] = { "forever", "ReadTalentTrees returns early without it" },
        ["C_SpecializationInfo.GetCombatConfigIDForSpecGroup"] = { "forever", "tested before the call in ReadTalentTrees" },
        ["Enum.ItemContainerSubclass"] = { "forever", "`and ... or <number>` in CaerdonBagSlots" },
        ["Enum.ItemQuiverSubclass"] = { "forever", "`and ... or <number>` in CaerdonBagSlots" },

        -- Forever's skill list (weapon skills, proficiencies). Retail has no such table.
        ["C_SkillInfo"] = { "forever", "read into a local and tested before use in CaerdonRefresh's ReadSkills" },
        ["C_SkillInfo.GetNumSkillLines"] = { "forever", "tested with the table in ReadSkills" },
        ["C_SkillInfo.GetSkillLineInfo"] = { "forever", "tested with the table in ReadSkills" },

        -- Forever's hunter pets eat (classic happiness). Retail has none of the three.
        ["C_PetInfo.CanPetEatItem"] = { "forever", "tested with the other two before the call in GetPetFoodDebugState" },
        ["C_PetInfo.GetPetFoodTypes"] = { "forever", "tested with the other two before the call in GetPetFoodDebugState" },
        ["C_PetInfo.GetPetHappiness"] = { "forever", "tested with the other two before the call in GetPetFoodDebugState" },

        -- Fallbacks for clients older than either supported one. Each sits behind a test for
        -- the current API or for the name itself, so it is never reached; deleting the
        -- fallback deletes the entry.
        ["GetAddOnMetadata"] = { "neither", "`elseif GetAddOnMetadata` after C_AddOns.GetAddOnMetadata" },
        ["GetContainerItemPurchaseInfo"] = { "neither", "else branch after C_Container.GetContainerItemPurchaseInfo" },
        ["GetContainerNumSlots"] = { "neither", "else branch after C_Container.GetContainerNumSlots" },
        ["GetItemCount"] = { "neither", "`C_Item.GetItemCount or GetItemCount`; the result is tested before the call" },
        ["GetItemFamily"] = { "neither", "`C_Item.GetItemFamily or GetItemFamily`, then `if not getter`" },
        ["GetQuestGreenRange"] = { "neither", "`GetQuestGreenRange and GetQuestGreenRange() or <number>`" },
        ["IsAddOnLoaded"] = { "neither", "`or (IsAddOnLoaded and ...)` after C_AddOns.IsAddOnLoaded" },
        ["IsUsableSpell"] = { "neither", "`C_Spell.IsSpellUsable or IsUsableSpell`" },
        ["UIParentLoadAddOn"] = { "neither", "else branch after CollectionsJournal_LoadUI" },
    },
}
