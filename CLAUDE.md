# CaerdonWardrobe - Claude Documentation

This file contains important context and design decisions for the CaerdonWardrobe addon to help Claude understand the codebase better.

## Useful Paths

- **Blizzard Source Code:** `../../../BlizzardInterfaceCode/`
  - API Documentation: `../../../BlizzardInterfaceCode/Interface/AddOns/Blizzard_APIDocumentationGenerated/`
  - Transmog API Docs: `../../../BlizzardInterfaceCode/Interface/AddOns/Blizzard_APIDocumentationGenerated/Transmog*.lua`
  - Collections Utilities: `../../../BlizzardInterfaceCode/Interface/AddOns/Blizzard_FrameXMLUtil/CollectionsUtil.lua`
  - Wardrobe Sets: `../../../BlizzardInterfaceCode/Interface/AddOns/Blizzard_Collections/Shared/Blizzard_Wardrobe_Sets.lua`

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

## Important Context

- The addon displays icons on various UI elements (bags, merchant frames, etc.) to show transmog collection status
- Ensembles are complex because they contain multiple items with different restrictions
- The classification must help players quickly understand if they should purchase/farm an ensemble
- "otherNoLoot" specifically means "yes there are sources to collect here, but you need a different character to learn them"
- This solution was discovered through extensive debugging and examination of Blizzard's API documentation and implementation
