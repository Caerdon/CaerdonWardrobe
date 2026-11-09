# CaerdonWardrobe - Claude Documentation

This file contains important context and design decisions for the CaerdonWardrobe addon to help Claude understand the codebase better.

## Useful Paths

- **Blizzard Source Code:** `../../../BlizzardInterfaceCode/`
  - API Documentation: `../../../BlizzardInterfaceCode/Interface/AddOns/Blizzard_APIDocumentationGenerated/`
  - Transmog API Docs: `../../../BlizzardInterfaceCode/Interface/AddOns/Blizzard_APIDocumentationGenerated/Transmog*.lua`
  - Collections Utilities: `../../../BlizzardInterfaceCode/Interface/AddOns/Blizzard_FrameXMLUtil/CollectionsUtil.lua`
  - Wardrobe Sets: `../../../BlizzardInterfaceCode/Interface/AddOns/Blizzard_Collections/Shared/Blizzard_Wardrobe_Sets.lua`
- **WoW Forever Blizzard Source:** GitHub `Ketho/wow-ui-source-forever`, branch `forever` (shallow clone it when needed; retail mirror is `Gethe/wow-ui-source`, branch `live`)

## WoW Forever (Camelot) Support

WoW Forever is a *mainline-family* client: retail 12.x UI architecture (secrets, modern Collections / Auction House / Professions / Bank frames) running classic-era content. The addon supports it from the same code base and the same TOC.

- **Identity:** game type `camelot` (alias `forever`), `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT` (18), `## Interface: 16001`. `CaerdonAPI:IsForeverClient()` / `GetClientFlavor()` exist for reporting (Debug Frame export), but code paths should rely on **feature detection**, not flavor checks.
- **Version gates:** `select(4, GetBuildInfo())` returns `16001` on Forever, so any `tocversion >= 110000`-style check evaluates false there. Only use such gates for features Forever genuinely lacks (housing is correctly gated off this way; Blizzard_Housing* is `AllowLoadGameType: standard`). Never use them to pick "modern vs. legacy" API paths.
- **Blizzard TOC gating:** Blizzard addons declare `## AllowLoadGameType` / per-file `[AllowLoadGameType camelot]`. `mainline` includes camelot; `standard` is retail only. Forever-specific overrides live in `Camelot/` subfolders.
- **Not loaded on Forever:** Blizzard_EncounterJournal (standard/classic only), Blizzard_GarrisonUI (camelot excluded), Blizzard_Housing*, Blizzard_ExpansionTrial. The EncounterJournal and Mission features wait for `ADDON_LOADED`, so they stay dormant without changes.
- **Mail frame:** Forever's `Blizzard_MailFrame` is mixin-based: `InboxFrame:Update()` and `OpenMailFrame:UpdateButtonPositions()` replace the retail globals `InboxFrame_Update` / `OpenMailFrame_UpdateButtonPositions` (`SendMailFrame_Update` is still global). `features/Mail.lua` hooks whichever exists.
- **Bank:** `CamelotBankPanelItemButtonMixin:Refresh()` calls through `BankPanelItemButtonMixin.Refresh(self)`, so the existing table hook still fires.
- **Events:** `UPDATE_EXPANSION_LEVEL` is undocumented and only used by retail-only Blizzard code; it is registered via `pcall` so an unknown-event error cannot abort `OnLoad`. All other registered events exist in Forever's event documentation.
- **Specializations:** Forever has none, and the legacy globals `GetSpecialization`, `GetSpecializationInfo` and `GetSpecializationInfoByID` do not exist at all (only `C_SpecializationInfo.*`, `GetLootSpecialization` and `GetSpecializationInfoForSpecID` do). Never call those globals directly; use `CaerdonAPI:GetPlayerSpecializationIndex()`, `GetSpecializationInfo(index, ...)`, `GetSpecializationInfoByID(specID)` and `GetLootSpecializationID()`, which resolve the namespace or global and return nil when no spec system exists.
- **Legacy globals in general:** many undocumented retail globals (merchant, loot, mail, quest and guild bank link getters, `PlayerHasToy`, EJ_* ) still exist on Forever, but confirm each one by finding a call in Blizzard's camelot-loaded Lua before relying on it; the generated API docs only list `C_*` namespaces and a subset of bare globals.
- **API coverage (verified against Forever 1.60.1 docs):** every documented API the addon uses exists; `TransmogUseErrorType` values match retail (Class=7, Race=8, Faction=9, ItemProficiency=10). Undocumented calls that Blizzard's own camelot-loaded code also uses (toy, heirloom, pet journal, black market, merchant/loot/quest link getters) are safe. `C_TradeSkillUI.GetAllRecipeIDs` and `GetRecipeFixedReagentItemLink` are not referenced anywhere in Forever's UI code, so they are guarded.
- **Armor proficiency:** classic-era rules apply (hunters/shamans get mail at 40, warriors/paladins plate at 40), yet `C_TransmogCollection` reports those sources as `isValidSourceForPlayer = true` with no `useErrorType`, and `C_Item.GetItemSpecInfo` is empty. The only in-game signal that the toon cannot wear a piece yet is the red right-column text on the tooltip's `EquipSlot` line; the upgrade logic relies on that scan (see "Red tooltip text is authoritative" above). Pawn works on Forever and its verdicts are honoured over plain item-level comparisons.
- **Professions:** every profession has exactly one child skill line named the same as its parent ("Cooking" > "Cooking" 2939, "Mining" 186 > "Mining" 2946), and the secondary professions (Cooking, Fishing, First Aid) cache no parent skill level, so `CaerdonProfessionData[realm][toon]["Cooking"]` is a bare `{ childSkillLines = ... }` container. `CaerdonRecipe:GetPlayerSkillInfo` therefore checks the top-level entry *and* every same-named child and keeps the highest level. Recipe tooltips read "Requires Cooking (40)" (`UsageRequirement`, `requirementType` Skill); a non-red line is the client's verdict that the rank is met and overrides the cached rank in `GetTooltipData`, while a red line still uses the cache to tell "rank too low" (`lowSkill`) from "no profession". `GetProfessions()` returns prim1, prim2, first aid, fishing, cooking (plus spare slots), not retail's layout. Recipe items report a generic "Learning" item spell (402265 seen on Recipe: Smoked Bear Meat), so `C_Item.GetItemSpell` does not identify the recipe; the name-based `GetRecipe` lookup does.
- **Collections behaviour:** Forever's wardrobe UI hides uncollected appearances (`Camelot/Blizzard_Wardrobe.lua` forces `SetUncollectedShown(false)`) and transmog is restricted to same-type items, but the `C_TransmogCollection` source/appearance APIs are unchanged, so the classification logic above applies as-is. In-game verification of `isValidSourceForPlayer` / `useErrorType` behaviour on Forever is still pending.

## Debugging and Data Capture

- When more context is required for investigating item identification, enhance the Debug Frame **Copy Details** export rather than sprinkling temporary print statements or logging.
- Keep new data additions structured so the clipboard output remains readable and easy to share with other agents.
- The export dialog uses a multi-line edit box with `SetMaxLetters(0)`, so large payloads (full ensemble breakdowns, etc.) can be included safely; focus is automatically placed on the text so `Ctrl/Cmd+C` works immediately.

### Adding New Item Signals

- Route new API-derived properties (artifact state, sellability, upgrade metadata, etc.) through the relevant Caerdon item data mixin (`CaerdonEquipmentMixin`, `CaerdonConsumableMixin`, etc.) so every caller consumes a single, well-typed source of truth.
- Avoid sprinkling ad‑hoc `C_ArtifactUI`/`C_Item` calls throughout `CaerdonItem` or feature files. Instead, have the mixin gather the data once while building its `Get*Info()` payload and expose a boolean/flag there.
- When multiple systems need the same flag (icons, tooltips, merchants), prefer extending the mixin return struct and documenting the new field in this file so future work reuses it instead of duplicating API calls.

### Neutral Equal-Level Indicator

- `CaerdonEquipmentMixin:GetTransmogInfo()` exposes `equalItemLevelEquipped`, which is true when the candidate item matches the current equipped item level for the relevant slots and the toon can equip it.
- `transmogInfo.canEquipForPlayer` augments Blizzard’s `playerCanCollect` logic by falling back to the tooltip binding scan, so bank/bag logic can still consider an item equippable even when transmog APIs say otherwise; equal-ilvl protection only applies when this is true *and* `matchesLootSpec` isn’t false so off-spec gear remains sellable.
- `transmogInfo.upgradeMatchesSpec` indicates whether the upgrade aligns with the player’s loot spec. When the “mismatched spec” option is enabled, off-spec upgrades keep the arrow/delta but tint the arrow red to show “usable but off-spec.”
- Collected items with this flag skip the sellable icon and instead render a neutral balance indicator (unless Pawn/upgrades take priority or the item belongs to a saved equipment set) so players know to evaluate the piece manually.
- `pawnIdentifiedUpgrade` is true only when Pawn itself flagged the item as an upgrade; Caerdon’s own upgrade detection leaves this false so the UI can color the arrow green for “item level says it’s better” cases.
- Items that belong to a saved gear set suppress the upgrade arrow altogether; only the item-level delta text remains, and it automatically shifts upward when the gear-set label is visible so the strings do not overlap.
- When Pawn is silent and the unique-upgrade heuristic doesn’t fire, `upgradeItemLevelDelta > 0` now serves as the fallback trigger for `isUpgrade` (unless the item is unique-blocked), so higher-ilvl uniques like rings still get the green arrow instead of falling back to “sellable.”
- Tabards (`INVTYPE_TABARD`) never surface as upgrades and never show delta callouts even if their comparison ilvl differs; `upgradeItemLevelDelta` is cleared so they stay visually quiet.
- Legendary-quality equipment is preserved automatically when it still exposes either an on-use spell or an equip effect in the tooltip; those items bypass the “redundant” sellable check so modern legendaries with gameplay hooks don’t get flagged as vendor trash.
- **Pawn vs. item level:** `betterItemEquipped` (equipped ilvl strictly higher) only overrides a Pawn upgrade verdict when PVP scaling took part in the comparison (`HasBetterOrEqualEquippedItem` returns that as its second value). On a plain ilvl comparison Pawn's stat weights win; a gray ilvl-7 dagger Pawn flags over an ilvl-9 axe must show the arrow, not sellable.
- **Armor class guard:** the `upgradeItemLevelDelta > 0` fallback never fires when the candidate is a lower armor class (cloth < leather < mail < plate) than the piece equipped in that slot (`IsLowerArmorClassThanEquipped`). Pawn may still flag such an item. Classic-era itemization hands higher-ilvl cloth to leather/mail wearers constantly.
- **Red tooltip text is authoritative for equippability.** `CaerdonItem` scans *every* tooltip line, both columns, for `RED_FONT_COLOR` (`ffff2020`). Armor/weapon proficiency red lives in the right column of the `EquipSlot` line ("Wrist | Mail"), which is not type None, so the old None-only left-column scan missed it. `bindingResult.unusableItem` then forces `canEquipForPlayer = false` and, when the shortfall is not level-based, drops `isUpgrade` (level-based shortfalls keep `upgradeLowSkill`). Retail never hit this because every class has its final armor proficiency from level 1; on WoW Forever a hunter cannot wear mail until 40 while the transmog APIs still report the source as valid for the player.

## Ensemble Classification Logic

Ensembles are collections of transmog items that typically include armor sets and sometimes bonus items like cloaks. The addon displays icons to indicate what the player can learn from each ensemble.

### Icon Types and Meanings

1. **"own" (yellow star):** Ensemble contains uncollected sources wearable by the current character
2. **"ownPlus" (green star):** Ensemble is for another class BUT contains wearable non-set items (cloaks, cosmetics) for current class
3. **"other" (red question mark):** Ensemble is for another class, nothing wearable by current class, but learnable for completionist purposes (armor type restriction only)
4. **"otherNoLoot" (red circle with slash):** Has uncollected sources, but ALL remaining sources require a different class/race/faction to learn

### Classification Rules

#### Armor Type Restrictions vs True Class/Race/Faction Restrictions

The key to proper ensemble classification is distinguishing between two types of restrictions:

**1. Armor Type Restrictions (Normal Cross-Class Learning)**
- Example: Regular plate armor set viewed on a Priest (who wears cloth)
- The Priest cannot wear plate armor, but can still collect the appearances for transmog
- **Icon:** "other" (red question mark) - learnable for completionist purposes
- **Indicator:** `useErrorType = 10` (ItemProficiency)

**2. True Class/Race/Faction Restrictions**
- Example: Paladin-only plate item viewed on a Priest, or Alliance-only item on Horde
- These items show RED requirements in the tooltip
- Only specific classes/races/factions can learn them
- **Icon:** "otherNoLoot" (red circle with slash) - requires a different character
- **Indicators:** `useErrorType = 7` (Class), `8` (Race), or `9` (Faction)

#### Mixed Restrictions

Ensembles often contain items with different restriction types:
- Some items may be truly restricted (faction/class/race)
- Other items are just armor-type restricted (learnable by the account)
- **Rule:** Show "other" if ANY sources have only armor-type restrictions
- **Rule:** Show "otherNoLoot" only when ALL remaining sources have true class/race/faction restrictions

### Detection Logic - The Solution

#### Using `sourceInfo.useErrorType`

The `useErrorType` field from `GetSourceInfo()` is the ONLY reliable way to distinguish restriction types.

**TransmogUseErrorType Enum Values:**
```lua
{ Name = "Class", Type = "TransmogUseErrorType", EnumValue = 7 },
{ Name = "Race", Type = "TransmogUseErrorType", EnumValue = 8 },
{ Name = "Faction", Type = "TransmogUseErrorType", EnumValue = 9 },
{ Name = "ItemProficiency", Type = "TransmogUseErrorType", EnumValue = 10 },
```

**Implementation:**
```lua
if not classRestrictedForPlayer and not sourceInfo.isValidSourceForPlayer then
    local errorType = sourceInfo.useErrorType
    if errorType == 7 or errorType == 8 or errorType == 9 then
        -- Class, Race, or Faction restriction - TRUE restriction
        classRestrictedForPlayer = true
    end
    -- errorType == 10 is ItemProficiency (armor type) - NOT a true restriction
end
```

#### Why Other Approaches Don't Work

The following fields **cannot** distinguish between armor-type and class restrictions:

1. **`PlayerCanCollectSource()`** - Returns the same value for both types when account has the required class
2. **`AccountCanCollectSource()`** - Returns the same value for both types when account has the required class
3. **`meetsTransmogPlayerCondition`** - Returns true for both restriction types
4. **`isAnySourceValidForPlayer`** - Returns false for both restriction types

When an account HAS a character of the required class, the API considers items "collectable" even though the current character can't use them. This makes standard collection APIs unreliable for this distinction.

### Source Collection vs Appearance Collection

**Critical Distinction:** Ensembles teach **sources**, not just **appearances**.

- **Appearance:** The visual look of an item
- **Source:** A specific item that provides an appearance (e.g., Normal/Heroic/Mythic versions)

**Key Implementation Detail:**
```lua
-- CORRECT: Check if SOURCE is collected
if not sourceInfo.isCollected then
    hasUncollectedSources = true
    -- Process this source...
end

-- WRONG: Don't skip sources where appearance is known from another source
-- if not sourceInfo.isCollected and not sourceIsKnown then
```

**Why this matters:**
- An ensemble may teach the same appearance at different difficulty levels
- Each difficulty is a separate **source**
- `sourceIsKnown=true` means you have the appearance from a different source
- But the ensemble will still teach you the NEW source, which:
  - Counts toward set completion in the transmog UI
  - Is valuable for completionists
  - Actually does something when you use the ensemble

**Example:** Ensemble 241426
- Contains Normal, Heroic, and Mythic versions of the same appearance
- If you have Normal, `appearanceInfo.collected=true` and `sourceIsKnown=true` for Heroic
- But `sourceInfo.isCollected=false` for Heroic
- The ensemble WILL teach you the Heroic source
- **Must show as learnable!**

### Merchant Fading Logic

Items in the merchant window are faded (grayed out) when fully collected, with exceptions for learnable items.

**Items that should NOT be faded:**
- `own` - Learnable by current character
- `ownPlus` - Has learnable bonus items for current character
- `other` - Learnable for completionist purposes
- `otherPlus` - Has learnable bonus items
- `lowSkill` - Level-locked but learnable
- `lowSkillPlus` - Level-locked with bonus items
- `otherNoLoot` - Has appearances to learn but requires different character

All of these indicate the item will teach you something if used, so they should be visually prominent.

## Outstanding Questions

### useErrorType=7 and Ensemble Learning (NEEDS TESTING)

**Issue discovered:** Ensemble 241380 contained item 137073 with multiple sources:
- Source 78758 has `useErrorType=7` (Class restriction - Monk-only) and `isValidSourceForPlayer=false` for Druid
- 6 other sources have `useErrorType=nil` and `isValidSourceForPlayer=true` for Druid

**Finding:** The ensemble was purchasable and learnable on a Druid, and it taught ALL sources including the Monk-only one (78758).

**Question:** Does `useErrorType=7` (Class restriction) prevent learning transmog via ensemble, or only prevent equipping the actual item?

**Current Theory:** 
- `useErrorType=7` may only restrict *equipping* the item for stats
- Ensembles may be able to teach the transmog appearance regardless of class restrictions
- This would mean our current "otherNoLoot" logic is overly restrictive

**Test Needed:** 
- Ensemble 139167 contains item 144275 (Paladin-only legendary, level 45+, `useErrorType=7`)
- Test on a level 45+ Warrior or Death Knight (non-Paladin plate wearer)
- Can the ensemble be purchased? Can it be learned? Does it teach the Paladin-only source?
- If YES, then `useErrorType=7` does NOT prevent ensemble learning
- If NO, determine what IS preventing it (maybe legendaries have special rules?)

**Impact:** If ensembles can teach class-restricted sources, we need to revise our classification logic to not show "otherNoLoot" based solely on `useErrorType=7/8/9`. We may need to find a different API indicator for truly unlearnable sources, or accept that all ensemble sources are learnable.

## Processing Pipeline Architecture

### Coroutine Processing
- `UpdateButton()` queues items into `waitingToProcess` keyed by `locationKey`
- `ProcessItem_Coroutine` (runs via `OnUpdate` every 50ms) moves items to `processQueue` and processes them
- Items where `IsItemDataCached()` is false go to a `ContinuableContainer` async path
- `IsItemDataCached()` requires BOTH `IsItemCached()` (WoW cache) AND `customDataLoaded` (CaerdonItem flag)
- Features MUST call `ContinueOnItemLoad` before `UpdateButton` so `customDataLoaded=true`; without this, items go to the ContinuableContainer path and may never process directly

### ContinuableContainer Callback Routing
- ContinuableContainer callbacks route items back through `waitingToProcess` (not `processQueue`) and re-register `OnUpdate` if needed
- This ensures items are picked up even if the callback fires after the current coroutine has exited
- `processQueue` is always reset to `{}` at coroutine start to prevent stale state from blocking processing

### Caerdon Button Overlay
- `EnsureCaerdonButton()` creates a child `Frame` of the original button with `SetAllPoints(originalButton)`
- Holds `mogStatus` textures, `bindsOnText` FontString, and `upgradeDeltaText` FontString
- `buttonState` uses weak keys (`__mode="k"`); entries auto-GC when button frames are collected

### Binding Text and SetScale
- When `bindingScale < 1`, the font string width must be divided by the scale factor (`SetSize(width / scale, height)`) to prevent text truncation after `SetScale` shrinks the render area
- Scale is reset to 1.0 before measuring with `GetStringWidth()` to ensure accurate measurement

## DressingRoom Feature

### Hook Setup
- `TryHookDressUp()` installs hooks in independent groups because required Blizzard globals load from different addons:
  - `DressUpFrameTransmogSetButtonMixin` → `Blizzard_SharedXMLGame`
  - `DressUpFrame` → `Blizzard_UIPanels_Game`
  - `DressUpOutfitDetailsSlotMixin` → Not in public source code; loads later from an unknown addon
- `ADDON_LOADED` retries `TryHookDressUp()` on every addon load until both hook groups are installed
- `hooksecurefunc` on mixin tables works with ScrollBox buttons because `Mixin()` copies the already-hooked function to new instances

### SetSelectionPanel Items
- Individual ensemble items in the SetSelectionPanel are Equipment type (not Consumable)
- `UpdateSetSelectionButton` sets `extraData.appearanceSourceID` from `elementData.itemModifiedAppearanceID` so the Equipment pipeline can identify the transmog source
- Uses `ContinueOnItemLoad` → `doUpdate` pattern to ensure `customDataLoaded=true` before calling `UpdateButton`
- Display options use smaller sizes for the 24×24 icons: `statusProminentSize=13`, `bindingScale=0.7`

## LoadSources `#waitingForItems` — Known Quirk (Do NOT Change)

- `waitingForItems` uses item IDs (large numbers) as keys, not sequential integers
- Lua's `#` operator returns 0 for non-sequential keys, so `#waitingForItems == 0` always evaluates true immediately after the loop
- This is **intentionally left as-is**: the immediate `callbackFunction()` is harmless because `ProcessTheItem`/`FailTheItem` handle real completion using `not next(waitingForItems)`
- Changing to `not next(waitingForItems)` causes `LoadSources` to actually wait for all source items to load, which blocks the entire `ContinuableContainer` including Consumable/ensemble items from the same batch — this caused a regression where all ensembles showed as unlearnable
- **Consequence:** `LoadSources` reports completion twice (immediately, then again when the last source item loads). `CaerdonItemMixin:ContinueWithCancelOnItemLoad` therefore wraps its callback so it fires at most once. Blizzard's `ContinuableContainer` decrements `numOutstanding` on every callback and clears its state after firing, so a late duplicate crashed with `ContinuableContainer.lua: bad argument #1 to 'ipairs' (table expected, got nil)`. It surfaced immediately on a fresh WoW Forever install (empty item cache, every source loads asynchronously) but is a latent retail issue too. Do not remove the once-guard; `ContinueOnItemLoad` (the non-cancel variant) is intentionally left unguarded because features rely on the re-run to refresh with complete source data.

## Important Context

- The addon displays icons on various UI elements (bags, merchant frames, etc.) to show transmog collection status
- Ensembles are complex because they contain multiple items with different restrictions
- The classification must help players quickly understand if they should purchase/farm an ensemble
- "otherNoLoot" specifically means "yes there are sources to collect here, but you need a different character to learn them"
- This solution was discovered through extensive debugging and examination of Blizzard's API documentation and implementation
