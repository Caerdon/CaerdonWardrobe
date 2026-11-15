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
- **Talent trees:** each class has one trait tree split into three groups (hunter: Beast Mastery / Marksmanship / Survival). `CaerdonAPI:GetTalentTrees()` reads them the way Blizzard's Camelot talent pane does (`C_SpecializationInfo.GetCombatConfigIDForSpecGroup(GetActiveSpecGroup())` → `C_Traits.GetConfigInfo(configID).treeIDs[1]` → `C_Traits.GetGroupDisplayInfoByTreeID` for names and order, `C_Traits.GetGroupCurrencyInfo` for `currencyInfos[1].spent`; a group missing from the result means 0 points). `GetPrimaryTalentTree()` returns the index, name and points of the leader, nil on a tie or with nothing spent. Retail documents neither group function, so both return nil there; that API presence is the feature gate. Cached until `InvalidateTalentTrees()`; `CaerdonWardrobeMixin:OnTalentsChanged` (`TRAIT_CONFIG_UPDATED`, `TRAIT_CONFIG_LIST_UPDATED`, `ACTIVE_COMBAT_CONFIG_CHANGED`, `ACTIVE_TALENT_GROUP_CHANGED`, `PLAYER_TALENT_UPDATE`, coalesced over 0.5 s) calls `RefreshItems` only when the leading tree changed. Used for the Pawn scale filter (see `pawnOffTreeUpgrade` below).
- **Legacy globals in general:** many undocumented retail globals (merchant, loot, mail, quest and guild bank link getters, `PlayerHasToy`, EJ_* ) still exist on Forever, but confirm each one by finding a call in Blizzard's camelot-loaded Lua before relying on it; the generated API docs only list `C_*` namespaces and a subset of bare globals.
- **API coverage (verified against Forever 1.60.1 docs):** every documented API the addon uses exists; `TransmogUseErrorType` values match retail (Class=7, Race=8, Faction=9, ItemProficiency=10). Undocumented calls that Blizzard's own camelot-loaded code also uses (toy, heirloom, pet journal, black market, merchant/loot/quest link getters) are safe. `C_TradeSkillUI.GetAllRecipeIDs` and `GetRecipeFixedReagentItemLink` are not referenced anywhere in Forever's UI code, so they are guarded.
- **Armor proficiency:** classic-era rules apply (hunters/shamans get mail at 40, warriors/paladins plate at 40), yet `C_TransmogCollection` reports those sources as `isValidSourceForPlayer = true` with no `useErrorType`, and `C_Item.GetItemSpecInfo` is empty. The only in-game signal that the toon cannot wear a piece yet is the red right-column text on the tooltip's `EquipSlot` line; the upgrade logic relies on that scan (see "Red tooltip text is authoritative" above). Pawn works on Forever and its verdicts are honoured over plain item-level comparisons.
- **Unwearable armor with an uncollected appearance:** for mail on a hunter under 40, `PlayerCanCollectSource` *and* `AccountCanCollectSource` return false while `isValidSourceForPlayer` is true and `useErrorType` is nil. Neither `needsItem` nor `otherNeedsItem` gets set, which used to fall through to `collected` and then `sellable` (Soldier's Wristguards of the Whale 6550, source 158544, on a level 26 hunter). `GetTransmogInfo()` now exposes `validSourceNotCollectable` (and `validSourceNotCollectableKnownLook` when another source of the look is collected), set only when both collect verdicts are ready; `GetCaerdonStatus` turns it into `own` / `ownPlus`. Red tooltip text is **not** required: cloth on the same hunter (Spellbinder Vest 2969, source 157062) has the identical API shape with a fully white tooltip and `CanItemTransmogAppearance` true, showed `sellable`, and is also learned on sale (reported by the user, 2026-11-12). So far `PlayerCanCollectSource` has been false for every uncollected piece exported from this hunter (cloth, mail, wand); when it is ever true on Forever is unknown. It is `own`, not `lowSkill`, because selling such a piece to a vendor teaches the appearance straight away even though the toon cannot wear it (confirmed in game by the user, 2026-11-12).
- **Gear the class can never use, with an uncollected appearance:** a wand on a hunter (Blazing Wand 5212, source 158061, level 26 dwarf hunter) reports `isValidSourceForPlayer = false`, `useErrorType = 10` (ItemProficiency), and `PlayerCanCollectSource` / `AccountCanCollectSource` both false with info ready, so it also fell through to `collected` and then `sellable`. Selling it to a vendor teaches the appearance (reported by the user, 2026-11-12). `GetTransmogInfo()` exposes `proficiencySourceNotCollectable` (and `...KnownLook`), set only when both collect verdicts are ready; `GetCaerdonStatus` turns it into `other` / `otherPlus` with no red-text requirement, because the API names the reason itself. It is `other`, not `own`: `own` is strictly for appearances the toon can actually transmog into / use (user decision, 2026-11-12), which also matches what retail shows for proficiency-only sources. Retail answers "can collect" for those sources, so the flag does not fire there. Class / race / faction errors (7 / 8 / 9) are not covered: whether selling teaches those on Forever is unknown. Not yet confirmed in game.
- **Ranged slot:** Forever has the classic ranged slot (`INVSLOT_RANGED` 18, `C_PaperDollInfo.IsRangedSlotShown()` true); retail puts bows and guns in the main hand. `GetInventorySlotsForType` in `types/EquipmentMixin.lua` sends `INVTYPE_RANGED` / `RANGEDRIGHT` / `THROWN` / `RELIC` to slot 18 when the ranged slot is shown. Before that, bows were compared against the melee main-hand weapon: the equipped bow and the one just replaced both showed an upgrade arrow (deltas measured against the melee weapon's item level).
- **Professions:** every profession has exactly one child skill line named the same as its parent ("Cooking" > "Cooking" 2939, "Mining" 186 > "Mining" 2946), and the secondary professions (Cooking, Fishing, First Aid) cache no parent skill level, so `CaerdonProfessionData[realm][toon]["Cooking"]` is a bare `{ childSkillLines = ... }` container. `CaerdonRecipe:GetPlayerSkillInfo` therefore checks the top-level entry *and* every same-named child and keeps the highest level. Recipe tooltips read "Requires Cooking (40)" (`UsageRequirement`, `requirementType` Skill); a non-red line is the client's verdict that the rank is met and overrides the cached rank in `GetTooltipData`, while a red line still uses the cache to tell "rank too low" (`lowSkill`) from "no profession". `GetProfessions()` returns prim1, prim2, first aid, fishing, cooking (plus spare slots), not retail's layout. Recipe items report a generic "Learning" item spell (402265 seen on Recipe: Smoked Bear Meat), so `C_Item.GetItemSpell` does not identify the recipe; the name-based `GetRecipe` lookup does.
- **Collections behaviour:** Forever's wardrobe UI hides uncollected appearances (`Camelot/Blizzard_Wardrobe.lua` forces `SetUncollectedShown(false)`) and transmog is restricted to same-type items, but the `C_TransmogCollection` source/appearance APIs are unchanged, so the classification logic above applies as-is. In-game verification of `isValidSourceForPlayer` / `useErrorType` behaviour on Forever is still pending.

## Debugging and Data Capture

- When more context is required for investigating item identification, enhance the Debug Frame **Copy Details** export rather than sprinkling temporary print statements or logging.
- Keep new data additions structured so the clipboard output remains readable and easy to share with other agents.
- The export dialog uses a multi-line edit box with `SetMaxLetters(0)`, so large payloads (full ensemble breakdowns, etc.) can be included safely; focus is automatically placed on the text so `Ctrl/Cmd+C` works immediately.

- The export's `[Transmog Collection Events]` section lists the last 25 transmog collection events the main frame received this session (age, name, payload) plus the refresh generation and the age of the last `RefreshItems`. Use it for "appearance was learned but the icon did not change" reports: it shows whether an event arrived at all and whether a refresh followed. The log lives in `CaerdonWardrobe.lua` (`CaerdonWardrobe:GetTransmogEventLog()`).

- The export's `[Button Geometry]` section (`CaerdonButtonGeometry.lua`) answers "why does this window need its own icon size and offsets". While **Enable debug** is on, `ProcessItem` calls `CaerdonButtonGeometry:Note()` for every button it draws; one button per window and option set is measured 0.2 s later, once frames are laid out. Nothing is recorded with debug off, and nothing here changes drawing.
  - **Per window** (feature name) it keeps up to 6 "shapes" (distinct option set plus button size, with numbers rounded to whole units so a size computed from a pixel-snapped slot does not make a new shape each draw) and prints for each: the options passed, the button's size and scale, what the overlay sits on (the button, or `options.relativeFrame` with its offset inside the button), the button's own icon region when the overlay is not on it, shape hints (which masks cut the icon the overlay sits on, named by their art, how many of the button's own textures are masked, and the atlas names of its visible art), the status icon (size, its fraction of the overlay's short side, anchor, how far it sticks out on each side), the binding text, the stack count's reach, the item level gain, and the nearest parent that clips (`DoesClipChildren()` or a `ScrollFrame`, starting with the button itself) with the room left around the overlay and the least room seen.
  - **Rectangles are not shapes.** Sizes and positions cannot tell a round button from a square slot: the profession output button first read as a 47 px slot and was only recognised as round from a screenshot. The shape hints exist for that, and no placement rule should be proposed for a window from its numbers alone; look at a screenshot or its definition first. A mask does not mean round: in the first export with hints (2026-11-14) the round profession button (Blizzard's `CircularGiantItemButtonTemplate`, border atlas `auctionhouse-itemicon-border-*`) and BetterBags' square slots both reported a masked icon, which is why the mask's own art is printed. In game a file-based mask only reports a file ID (130924 on the round button, 2922105 on the BetterBags slot), so the two masks of Blizzard's `ItemButtonTemplate.xml`, `TempPortraitAlphaMask` (circle) and `common-iconmask` (every standard slot), are resolved with `GetFileIDFromPath` and named. Confirmed in game the same day: the BetterBags slot reads "standard item slot (common-iconmask)" and the round button "circle (TempPortraitAlphaMask)".
- `/cdebug geometry` opens the copy dialog with only the `[Button Geometry]` section, with no item selected. The copy dialog is a child of the Debug Frame, so anything that shows it has to open the Debug Frame first (the command does). The dialog's edit box sets no extra line spacing: with `SetSpacing(4)` the selection highlight did not line up with the text, so only "select all" was usable; removing it fixed selection (both confirmed in game by the author, 2026-11-14).
  - **Units** are the decorated button's own, so they compare directly with `statusProminentSize` and the offset options. "Outside" is positive when a part sticks out of the frame the overlay is on.
  - **Purpose (2026-11-14):** about 25 of the 40 windows and integrations pass hand-tuned sizes and insets. The starting guess was that most of that comes from two things, the size of the frame the icon sits on and clipping (the default placement hangs the icon about 6 px outside the corner), and that one rule could replace them. This section is how real numbers are collected to test that; no hard-coded value should be replaced for a window that has not been measured.
  - **Use:** enable debug, open each window so it draws at least one item with an icon, then Copy Details on any item. The section is session-wide (lost on `/reload`), not about the copied item.
  - **First measurements (WoW Forever, 2026-11-14, button units, important / minor icon):** Blizzard bags, bank, vendor, mail and loot are 37 px slots with a 20 / 16 px icon (54% / 43% of the slot) whose center sits a fifth of its size inside the corner, so it hangs 6 / 4.8 px outside. Quest rewards put the same 20 px on a 30 px icon (67%), the profession output slot on a 47 px button with 53 px art (43%). BetterBags slots are 43.9 px and had a fixed 16 px icon fully inside (36%). Auction and profession list rows are 20 px tall with a 13 px icon and have no icon region to sit on.
  - **What that showed:** the default is a fixed 20 px whatever the frame, so the icon's share of its frame varies even in windows nobody tuned; the size guess above is wrong as a description of today's values. Six of nine shapes sit inside a clipping frame, but every slot window had at least 10 px of room, more than the overhang; only the auction rows have none. So for slots the differences were choices (several made by eye), not constraints. Rows are the real special case.
  - **Reference look (author decision, 2026-11-14):** the default Blizzard slot. Important icon 20/37 of the short side of the frame it sits on, minor icon 0.8 of that, center a fifth of the icon's size in from the corner. BetterBags was moved to it (`GetSlotOptions` in `external/BetterBags/Core.BetterBags.lua`); its earlier 16 px / 7 px inset dated from when BetterBags clipped the icon. Confirmed in game by the author (2026-11-14) on the Next panels: no clipping, and the icon follows BetterBags' icon scale and theme changes without a reload. Quest rewards follow it too (`GetRewardOptions` in `features/QuestLog.lua`, 2026-11-14): 16.2 px on the 30 px icon of the map's quest details (`SmallItemButtonTemplate`), 21.1 px on the 39 px icon of the quest frame (`LargeItemButtonTemplate`); both icons are plain squares in Blizzard's XML. Not yet seen in game. Windows opt in by passing `statusProminentSize = CaerdonWardrobe:GetSlotStatusSize(width, height)` for the frame the overlay sits on; the core does not apply the rule by itself.
  - **Floor and ceiling (author decision, 2026-11-14):** the result is kept between 13 and 24 px. The second round of measurements (dressing room rows 14 px on a 20 px icon, Narcissus 14 on 22, auction sell slot 24 on 54, Auctionator an untuned 20 on 42 and 60) showed the hand-set sizes giving small frames a bigger share and large frames a smaller one; 54% clamped to 13..24 reproduces them (13 on the 20 px auction and profession rows and the 24 px set icons, 20 on 37, 24 on the sell slot). The explicit insets 3/3 (at 14 px) and 5/5 (at 24 px) are the default "a fifth of the icon" rounded, so windows moved to the helper drop them. Bag slots whose size the player sets in the bag addon are exempt from the ceiling (author decision the same day: someone who wants big slots should get big icons): BetterBags passes `noMaximum`, so at 150% icon scale its star is about 36 px. The floor still applies.
  - **Moved to the helper so far:** BetterBags, quest rewards, Auctionator (was an untuned 20 px with a 7/7 inset; now 22.7 px in the 42 px bag list and 24 px on the 60 px sale item, with `keepInsideWhenClipped`), the dressing room's outfit rows (14 px to 13). The Auctionator and dressing room changes were confirmed in game by the author (2026-11-14); a later export shows the outfit rows at 13 px, 3.9 px over the corner of the 20 px icon. **Already at the rule's value, left as is:** the auction sell slot. **Not moved, deliberately:** the round profession button, and Narcissus' dressing room slots (the row along the bottom of the dressing room; a screenshot showed them round, 14 px on a 22 px icon with the star on the ring, the same case as the profession button). **Not moved, not measured:** the dressing room's set buttons (no sets on Forever). The profession output button (the round one above the reagents) is deliberately left at the fixed 20 px (author decision, 2026-11-14): it is round, so the star sits on the ring where a square slot's corner would be and covers none of the item, and scaling it to 25 px would only push it further out.
  - **Clip-aware placement (`options.keepInsideWhenClipped`, opt-in, BetterBags only so far):** BetterBags' classic bags (profiles from before its Next panels keep them) are 37 px slots in a `BetterBagsScrollGrid` with no room at the left or top, so the overhang is cut off there (measured 2026-11-14: room L 0, T 0). With the option set, `SetStatusIconPosition` draws as usual and queues the button; a pass 0.1 s later (`RunClipPass` in `CaerdonWardrobe.lua`) finds the nearest clipping parent, records the least room seen to its left and right edges, and when that is less than the overhang on the anchor's side re-places every icon in that grid inside the corner, on both axes. The answer is per clipping frame, not per button, so one grid has one look, and later draws use it immediately.
    - **Inside means smaller too (author requirement, 2026-11-14):** an icon moved inside at full size would cover more of the item's art, which is why the old BetterBags values were small. Inside it is drawn at `CLIP_INSIDE_SCALE` (0.8) of its size and placed half that size plus 0.5 px in: 20 px becomes 16, minor 16 becomes 12.8, the sizes the BetterBags integration used before. Matching the overhanging icon's coverage exactly would be 0.7 (14 px); that was tried and read as too small in game. `SetItemButtonStatus` stores the full size on the icon (`caerdonBaseSize`, `caerdonBaseBackgroundSize`) so placing it again never shrinks it twice, and a button that moves to a roomy grid gets its full size back.
    - **The clipping frame is looked up on every draw** (a parent walk, opted-in buttons only). The first version cached it per button and keyed the cache on the button's own parent; switching BetterBags between its classic and Next designs moves the shared buttons under another grid without changing that parent, so the old answer stuck until a reload (seen in game, 2026-11-14).
    - Only horizontal room decides: in a vertically scrolling list it does not depend on the scroll position, while any row passing the top edge has no room above it. A grid with side padding but none at the top is therefore not caught.
    - A button is measured once per clipping frame (pooled buttons that move to another grid are measured again); hidden buttons and buttons without layout wait for a later draw. A button that is partly outside the clipping frame's width is not counted and is measured again later: the least room is remembered for the session, and BetterBags was seen (2026-11-14, in the recorder) with a slot 8 px past its scroll box's edge while the bag was being rescaled. Windows that do not pass the option are untouched.
    - In game (author, 2026-11-14): the first version kept the Next panels overhanging and put the classic bags' icons inside without clipping. The per-draw lookup (switching designs needs no reload) and the 0.8 inside size were then confirmed in game too. Only BetterBags' two designs have been seen; the right-hand corners and other grids are offline-tested only (LuaJIT, mocked regions).
  - **Also seen:** the stack count reaches 15.9 px up in bags and bank (the hard-coded `itemCountOffset` default is 15) but 10.2 px on vendor buyback; the draw code wrote `statusBackgroundOffsetX / Y = -0.5` into the caller's options table for `otherNoLoot`, so a window that shares one options table (Merchant) passed it to every later button. Fixed the same day: the nudge is kept on the icon texture (`caerdonBackgroundNudge`, reset on every draw).
  - The recorder is offline-tested under LuaJIT with mocked regions; the two exports above are its only in-game runs.

### Collection Refresh Triggers

- `RefreshItems` (cache wipe, generation bump, debounced feature refresh) runs on `TRANSMOG_COLLECTION_UPDATED` **and** on the per-source events `TRANSMOG_COLLECTION_SOURCE_ADDED`, `TRANSMOG_COLLECTION_SOURCE_REMOVED` and `TRANSMOG_COSMETIC_COLLECTION_SOURCE_ADDED`. Do not add `TRANSMOG_SOURCE_COLLECTABILITY_UPDATE` there: it reports per-source collectability becoming known, which the addon's own `PlayerCanCollectSource` queries can trigger, so refreshing on it risks a refresh loop.
- **Every feature's `Refresh()` must re-run `UpdateButton` for the buttons it already decorated.** `RefreshItems` only wipes the caches; the stale icon stays on screen until the feature redraws it. A no-op `Refresh()` is a bug: the Debug Frame then shows the right status (it recomputes) while the bag button keeps the old icon.
- **BetterBags** only sends `item/Updated` when a button's draw inputs (item, count, quality, ...) change, and reopening the bag does not redraw unchanged buttons. Its integration therefore tracks the buttons it has seen (`trackedBagItems`, weak keys, dropped on `item/Clearing`) and `Refresh()` re-runs them, skipping slots where `C_Container.GetContainerItemID` is nil (free slots, bank slots away from the bank). Found on WoW Forever: two identical crafted kilts showed the learnable star, selling one taught the appearance, the other kept its star.
- **BetterBags vendor window** (`next/vendor.lua`, `next/vendorbutton.lua` in BetterBags v0.9.x): BetterBags parks Blizzard's `MerchantFrame` under a hidden parent and draws its own cards, so `features/Merchant.lua` keeps decorating buttons nobody sees. The `BetterBagsVendor` feature in `external/BetterBags/Core.BetterBags.lua` decorates BetterBags' buttons instead. BetterBags sends `vendor/NewButton` once when a button is created and nothing when one is drawn, and the button prototype is private, so each button's own `SetBuy` / `SetBuyback` / `SetRepair` / `Release` is wrapped (pcall'd, so a Caerdon error cannot abort BetterBags' draw). The item comes from `button.item.link` / `button.buyback.link`; repair entries are cleared. Display rules are the Merchant feature's (`GetDisplayInfo` is delegated to it), and `GetStatusRuleName()` returns `"Merchant"` so `ProcessItem` applies the merchant exceptions. Any feature that redraws another feature's content should override `GetStatusRuleName()` the same way. Icon size and offsets reuse the bag buttons' values. Confirmed in game on WoW Forever (2026-11-11): the quest icon shows on the Buy tab; the Buyback tab was only tested offline with mocks.
- Still-empty `Refresh()` in other bag integrations (same latent bug, untested): BaudBag, Inventorian, CargBags, Sorted.
- On WoW Forever an appearance is also learned by selling the item to a vendor ("added to your appearance collection"), so a second copy in the bags needs a refresh with no equip or bind involved. Which events that path fires is still unverified in-game; check the event log above.

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
- Items that belong to a saved gear set suppress the upgrade arrow altogether; only the item-level delta text remains. It keeps its place and the gear-set label moves clear of it when the two would overlap (see "Text and a number on the same row" under Settings Pages; until 2026-11-14 the delta moved up instead).
- When Pawn is silent and the unique-upgrade heuristic doesn’t fire, `upgradeItemLevelDelta > 0` now serves as the fallback trigger for `isUpgrade` (unless the item is unique-blocked), so higher-ilvl uniques like rings still get the green arrow instead of falling back to “sellable.”
- Tabards (`INVTYPE_TABARD`) never surface as upgrades and never show delta callouts even if their comparison ilvl differs; `upgradeItemLevelDelta` is cleared so they stay visually quiet.
- Legendary-quality equipment is preserved automatically when it still exposes either an on-use spell or an equip effect in the tooltip; those items bypass the “redundant” sellable check so modern legendaries with gameplay hooks don’t get flagged as vendor trash.
- **Pawn vs. item level:** `betterItemEquipped` (equipped ilvl strictly higher) only overrides a Pawn upgrade verdict when PVP scaling took part in the comparison (`HasBetterOrEqualEquippedItem` returns that as its second value). On a plain ilvl comparison Pawn's stat weights win; a gray ilvl-7 dagger Pawn flags over an ilvl-9 axe must show the arrow, not sellable.
- **Pawn's "not better" also blocks the item-level fallback:** `transmogInfo.pawnPrefersEquipped` is true when the candidate has a higher item level than the equipped piece but Pawn scores the equipped piece at least as high on every visible scale; the `upgradeItemLevelDelta > 0` fallback then stays off. Found on WoW Forever: after equipping Midshipman's Worn Boots (270002, ilvl 15, +3 Agility, Pawn upgrade), the Bard's Boots of Intellect (6557, ilvl 16) just taken off got Caerdon's own arrow. `PawnShouldItemLinkHaveUpgradeArrowUnbudgeted` returns `false` for "scored, not better" *and* for "cannot judge" (trinkets, 1H vs 2H, no scales, data not loaded), so a bare `false` is not a verdict: `PawnPrefersEquipped` in `types/EquipmentMixin.lua` compares the scores itself the way Pawn does (`PawnGetSingleValueFromItem` unenchanted value, the weaker of two slots, 0.5% threshold) and gives no verdict for trinkets, an empty slot, missing data, or when no visible scale values the equipped piece. **Only applies while Pawn's "Show item level upgrades" option (`PawnCommon.ShowItemLevelUpgrades`) is off**, which is Pawn's default on classic-era clients including Forever and on by default on retail (build 70000+). The item-level fallback exists for two retail cases the user named (2026-11-12): power-building events where a higher item level is always better, and content with item level requirements, where a higher-ilvl piece helps qualify; with the option on, item level keeps the final say and nothing here changes. Without an arrow such an item falls through to the normal `collected` / `sellable` logic. The export's Debug Internals print `pawnComparison` (per-scale scores). Offline-tested with a mocked Pawn only.
- **Pawn upgrade for another talent tree (`transmogInfo.pawnOffTreeUpgrade`):** on a client without specializations Pawn has no automatic mode (`VgerCore.SpecsExist` false), so it shows one scale per talent tree of the class (`"Classic":HUNTER1` / `2` / `3`) and `PawnShouldItemLinkHaveUpgradeArrow` answers "an upgrade for any visible scale". Found on WoW Forever (2026-11-12, level 26 hunter with most points in Beast Mastery): Hammerfist Gloves 5629 (+3 Str, +3 Agi) score 4.14 vs 3.29 on Survival (Strength 0.3) but 3.39 vs 4.34 on Beast Mastery / Marksmanship (Spirit 0.7) against the equipped Inscribed Leather Gloves 2988 (+2 Agi, +3 Spi), so each pair showed the Pawn arrow while the other was worn. Now `CaerdonAPI:GetPrimaryTalentTree()` names the tree with the most points, `GetPawnOffTreeScales()` in `types/EquipmentMixin.lua` collects the visible scales of the player's class whose `SpecID` belongs to another tree, and `IsPawnUpgradeOffTreeOnly()` asks `PawnIsItemAnUpgrade` (what Pawn's tooltip uses) which scales the upgrade is for. When all of them are off-tree the arrow stays (`isUpgrade` true) but `pawnOffTreeUpgrade` is set, `pawnIdentifiedUpgrade` is false, and `ApplyUpgradeArrowColor` draws it in the off-spec red, with no dependency on `Icon.ShowMismatchedSpecUpgrades` (user decision, 2026-11-12: show it as an upgrade for a different spec rather than hide it). **Pawn's scale list is the setting:** a scale shown in Pawn is evaluated; hide another tree's scale in Pawn and its arrows go away. Nothing is ignored when no tree leads (no points, or a tie), when the own tree's scale is hidden, or when only one scale is visible; custom scales (no `SpecID`) always count as the toon's own. Pawn's druid numbering is 1 Balance, 2 Feral (Damage), 3 Feral (Tank), 4 Restoration over three trees (`PawnSpecIDsForTalentTree`). If such an arrow is blocked for another reason, the item-level fallback compares scores on the toon's own scales only (`PawnPrefersEquipped(item, ignoredScales)`). The export prints `Talent Trees` / `Primary Talent Tree` under `[Player]` and `pawnOffTreeUpgrade`, `pawnUpgradeScales`, `pawnComparison`, `pawnScaleFilter` under `[Transmog (Caerdon Processed)]`. Confirmed in game by the user (2026-11-13) for the gloves case above: the off-spec arrow showed correctly on the Beast Mastery hunter, which also means the trait groups came back in Pawn's tree order for hunters. Everything else (tie, no points, respec refresh, hidden or custom scales, the druid mapping, other classes' tree order) is only offline-tested under LuaJIT with mocked traits and Pawn; the export shows both the tree order and the scale filter, so a mismatch is visible.
- **Armor class guard:** the `upgradeItemLevelDelta > 0` fallback never fires when the candidate is a lower armor class (cloth < leather < mail < plate) than the piece equipped in that slot (`IsLowerArmorClassThanEquipped`). Pawn may still flag such an item. Classic-era itemization hands higher-ilvl cloth to leather/mail wearers constantly.
- **Red tooltip text is authoritative for equippability.** `CaerdonItem` scans *every* tooltip line, both columns, for `RED_FONT_COLOR` (`ffff2020`). Armor/weapon proficiency red lives in the right column of the `EquipSlot` line ("Wrist | Mail"), which is not type None, so the old None-only left-column scan missed it. `bindingResult.unusableItem` then forces `canEquipForPlayer = false` and, when the shortfall is not level-based, drops `isUpgrade` (level-based shortfalls keep `upgradeLowSkill`). Retail never hit this because every class has its final armor proficiency from level 1; on WoW Forever a hunter cannot wear mail until 40 while the transmog APIs still report the source as valid for the player.

- **Fishing poles are never sellable.** Weapon subclass `Fishingpole` is excluded from the equipment sellable check in `GetCaerdonStatus`: a pole loses every item level comparison to a real weapon and has no use or equip effect line, so it otherwise reads as a redundant duplicate.

### Equippable Junk

- `CaerdonItemMixin:IsEquippableJunk()` marks Miscellaneous / Junk items as `sellable` when they go in an equipment slot but have no use, no equip effect and no transmog appearance, and a vendor price. Built for the trophy fish (15 Pound Mud Snapper 6295, "Held In Off-hand"), which type detection calls `Unhandled`, so the equipment sellable logic never saw them. Keep it this narrow: non-equippable Miscellaneous / Junk includes plenty worth keeping. Quest value and the auction check still apply on top.

### Consumables for Another Class

- `CaerdonItemMixin:IsOtherClassConsumable()` marks a Consumable `sellable` when its tooltip has a red race / class requirement, which the toon can never meet (unlike level or skill). Built for the mage scrolls on WoW Forever (Scroll: STHENIC LUNATE 211855, "Classes: Mage" plus "Requires Comprehension (15)", on a hunter), which used to end on `collected` with no icon.
- **Signal:** a `UsageRequirement` tooltip line with `requirementType == Enum.TooltipDataUsageRequirementType.RaceClass` (0) in red sets `tooltipData.raceClassRestricted`, exposed as `bindingResult.raceClassRestricted`. No text matching.
- **Only replaces `""` / `collected`**, so an ensemble with something to learn keeps its icon. Needs a vendor price. Account-bound and warbound-until-equip items are skipped (an alt may use them). Equipment and recipes are not covered; they have their own logic.
- **Auction:** being `sellable`, the item then goes through the auction check. The scrolls do not stack, so the single-item rule applies to each one separately; a scroll that nets a few silver stays on the vendor coin even when a bag of different scrolls would be worth a trip together.
- No setting of its own; the sellable icon's existing options apply. Not yet confirmed in game.

### Recipes This Toon Has No Use For

A Recipe that this toon already knows, or cannot learn, used to end on `collected` with no icon. `CaerdonItemMixin:GetUnneededRecipeStatus()` now replaces that `collected` (built for Pattern: Woolen Reagent Bag 253668 on a tailor who knows it, WoW Forever, 2026-11-14):

- **`other` / `otherPlus`:** the recipe can still be handed over (not soulbound, not bind-on-pickup) and another toon on the same realm has the profession with the recipe absent from its *recorded* list. `other` (red) when no toon knows the recipe, `otherPlus` (green) when this toon or any other already does. Known somewhere, learnable elsewhere, which is what the Plus means for appearances too (user decisions, 2026-11-14). No vendor price needed. The status is not tied to the bags, so the icon also shows at a vendor or the auction house.
- **`sellable`:** this toon knows it and nobody else wants it. Needs a vendor price; account-bound and warbound-until-equip recipes are never called sellable. It then goes through the auction check under the single-item rule.
- **Left on `collected`:** a known recipe when another toon has the profession but its recipes were never recorded (it may need it; nothing can be claimed), and a recipe this toon cannot learn that no recorded toon wants.
- **"Known" for the sellable verdict** is `bindingResult.alreadyKnown`, i.e. `tooltipData.isKnownSpell` (a `UsageRequirement` line with `requirementType` `NotAlreadyKnown` (14), or the `ITEM_SPELL_KNOWN` text). The name-based `recipeInfo.learned` is deliberately not enough: recipe ranks that share a name look learned once any rank is, which is tolerable for hiding a star or picking the icon colour but not for saying "sell this".
- **Other-toon data:** `CaerdonItemMixin:GetRecipeOtherToonInfo()` (nil unless a Recipe that can be handed over) wraps `CaerdonRecipeMixin:GetOtherToonRecipeInfo()` / `CaerdonRecipe:GetOtherToonRecipeInfo(item)` in `types/RecipeMixin.lua`, which returns `{ professionName, recipeName, knownByPlayer, toons = { { name, rank, knowsRecipe, recipesRecorded } }, missing = { ... }, unknown = { ... } }` or nil when no other toon has the profession. `missing` = recorded list lacks the recipe (can learn it); `unknown` = never recorded. The icon and the tooltip both go through it; it is the only reader of another toon's saved data.
  - **Saved variables (account-wide):** `CaerdonProfessionData[realm][toon]` (ranks, refreshed at login and on skill changes) and `CaerdonRecipeData[realm][toon]` with `knownRecipes` (recipe name to ID) and `scannedProfessions` (profession name to true). The profession is matched by the recipe item's subtype name, the recipe by the item name without its "Pattern: " style prefix (English prefixes only, as in `GetRecipe`).
  - **Recording (`GatherRecipes`):** runs when the profession window's data is ready. `knownRecipes` is only written for the toon's own profession (not a linked, guild or NPC one; before 2026-11-14 a linked profession's recipes were saved as the toon's own). `scannedProfessions[name]` is set only when the list is complete: `GetAllRecipeIDs` exists, or the `GetFilteredRecipeIDs` fallback (Forever) ran with no "have materials" / "skill up" / "first craft" filter, learned recipes shown, no slot or category filter and no search text. `NEW_RECIPE_LEARNED` also adds to `knownRecipes` (the handler existed but the event was never registered on that frame).
  - **Existing data has no `scannedProfessions`,** so every other toon starts as `unknown` until it opens each profession window once with default filters.
  - **Not modelled:** faction, the other toon's rank against the recipe's requirement, other realms, and deleted toons (their saved entries stay and nothing prunes them).
- **Tooltip (`TooltipMixin:AddRecipeLearners` in `features/Tooltip.lua`):** the addon's only tooltip text outside debug mode. Green "Could be learned by: Kado (Engineering 68)" for the `missing` toons on any recipe that can be handed over; gray "Recipes not recorded yet (open the profession on that toon): ..." for the `unknown` toons, only when the tooltip says "Already known" (anywhere else it would nag on every recipe of that profession). The number is the toon's rank, to hold against the "Requires" line. The call is wrapped in `xpcall` because an error inside `OnTooltipSetItem` would leave `tooltip.caerdonProcessing` set and silence every later tooltip.
- **Settings (both default on):** `Icon.ShowRecipesForOtherToons` (Icons page, under "Learning for another toon"; off: other toons are ignored, a known recipe is `sellable`, nothing gets `other`) and `Tooltip.ShowRecipeLearners` (Display page). `Tooltip` is a new config section; readers treat a missing section as on. The icon is drawn through `otherIcon`, so the per-window "learning for another toon" toggles (`Icon.ShowLearnableByOther.*`) still hide it in that window.
- **Debugging:** the export's `[Recipe]` section lists every other toon with the profession and its verdict, the counts, whether the item can be handed over, and both settings.
- **Unverified:** whether the embedded tooltip of a created item the toon already owns (a toy or pet) can add its own "Already known" line to a recipe that is not known yet (the same line already hides the learnable star in that case); that `GetBaseProfessionInfo().professionName` / `parentProfessionName` matches the recipe item subtype name on Forever; the filter getters at runtime (each is called only if it exists).
- **In-game status:** nothing here has been seen in game. The real modules were run offline under LuaJIT against the author's saved variables with a mocked client.

### Outgrown Food and Drink

Consumables used to end on `collected` with no sellable step. `CaerdonFoodDrink.lua` marks food or drink `sellable` when the toon carries a better one of the same kind that it can use now; callers use `CaerdonItemMixin:GetFoodDrinkInfo()` (nil for anything that is not food or drink).

- **Compared against what is carried (bags only), not the toon's level**, so the last stack is never marked just because a better tier exists at a vendor.
- **Candidates:** item class Consumable, subclass Food & Drink (`Enum.ItemConsumableSubclass.Fooddrink`, 5). The subclass gate matters: a healing potion's "Restores 70 to 90 health" would otherwise read as food.
- **Food vs. drink:** no API field separates them, so the tooltip line that has a number and the localized `HEALTH` / `MANA` word decides (`food`, `drink`, or `both`, which is left alone). The first number is the restore amount. More numbers than "amount, duration" means an extra effect, i.e. buff food ("well fed"), which only competes with other buff food.
- **Better:** higher required level, or same required level and a larger restore amount, among carried items the toon can use.
- **Never marked:** crafting reagents (raw fish), items the toon cannot use yet, anything with quest value (quest status replaces `sellable`).
- **Hunters:** a pet eats food well below its level, so food must also be more than 20 item levels below the toon's level (`HUNTER_FOOD_LEVEL_GAP`). Drinks are judged normally. Whether WoW Forever keeps the classic pet-food level rule is unverified; the gap is deliberately cautious.
- **Refresh:** `RefreshItems` drops the carried index; `BAG_UPDATE_DELAYED` rebuilds it and calls `RefreshItems` only when the set of carried food and drink items changed.
- **Auction:** an outgrown item is `sellable`, so the auction check then runs on it (stackable rule).
- **Setting:** `Icon.ShowOutdatedFood` (default on), Icons page under "Sellable".
- **Debugging:** the Debug Frame export's `[Food and Drink]` section prints the kind, restore line, levels, verdict and the better item carried.
- **Tooltip shape on WoW Forever (confirmed 2026-11-12, Seasoned Wolf Kabob 1017):** class 0, subclass 5; one `Use:` line, `Restores 530 health over 24 sec.  Must remain seated while eating. If you spend at least 10 sec eating, you will become well fed and gain 5 Agility for 15 min. ... (1 |4Sec:Sec; Cooldown)`. The trailing cooldown note and the `|4` plural escape carry digits, so both are stripped before the numbers are counted; without that plain food reads as buff food.
- **In-game status:** the kabob classified correctly (food, buff, 530). A plain food, a drink, and an actual "outdated" verdict have only been run offline under LuaJIT with a mocked client.

## Quest Value (Items Needed by Quests)

The quest icon (`mogStatus = "quest"`) used to mean only "item class is Quest". It now also covers items of any class that an unfinished quest takes, e.g. a vendor drink bought ahead of a quest (Flagon of Dwarven Honeymead 2594 for "The Third Fleet" 288, the case this was built for). Logic lives in `CaerdonQuestItems.lua`; callers use `CaerdonItemMixin:GetQuestItemInfo()` (returns nil or `{ hasQuestValue, isActive, isUpcoming, quests = { ... } }`).

- **No client API maps an item to a quest.** `C_QuestLog.GetQuestObjectives` returns only `text` / `type` / counts (no item ID), and `C_Container.GetContainerItemQuestInfo` only knows Quest-class and quest-starter items. Nothing exists for quests that are not in the log.
- **Two sources:**
  1. *Quest log* (always on): item objectives (`type == "item"`) of the quests in the log, matched by item **name**. The objective text is parsed for both layouts, `"Name: 0/1"` and `"0/1 Name"`; which one WoW Forever uses is unverified in-game. Text can be empty until the item is cached, so the scan is retried on `QUEST_LOG_UPDATE` (throttled, capped) until names arrive.
  2. *QuestieDB* (`LibQuestieDB`, optional, detected at runtime, contract 2+): covers quests not accepted yet. Its `Item.relatedQuests` field is **not** a usable reverse index (it holds about 13% of the objective pairs in the Forever data), so `CaerdonQuestItems` builds its own from every quest's `objectives[3]`, `objectives[6]` (item that casts a spell objective), `requiredSourceItems` and `startedBy[3]`, in a coroutine sliced at 3 ms a frame. Lookups before the index is ready fall back to the quest log; `RefreshItems` runs when it completes.
- **QuestieDB data shape:** baked into the TOC as base64 CBOR, so `grep` for an ID finds nothing; read it through `LibQuestieDB.Quest.Get(id, "field")`. `objectives` is sparse (`{ [3] = { { itemID, nil, 0 } } }`), race masks exceed 2^32 (Skyborne are bits 32/33, so use arithmetic, not `bit.band`), and a bare classic faction mask (77 / 178) must be compared to the toon's faction. `LibQuestieDB.Enum.raceMaskById` / `classKeys` give the toon's bits.
- **Which not-yet-accepted quests count as "upcoming"** (`UpcomingBlocker`): not completed, not hidden by Questie's blacklist or event list (when Questie is loaded; `HIDE_ON_MAP` entries still count), not a holiday / war-effort quest sort, right race and class, not repeatable / daily, profession learned (profession skill lines only), no exclusive / later-chain / parent quest already done, takeable within `UPCOMING_LEVEL_WINDOW` (5) levels, not trivial (gray) for the toon, and a quest that only an item can start needs that item in the bags or bank. Without the trivial and level rules a level 23 toon gets the icon on roughly 400 different items (every skipped starter-zone quest); with them it is about 70, most of them single-purpose quest books; the commonly held ones are cooking ingredients and cloth donations.
- **Quests in the log always count**, whatever the rules above say (repeatables included), and a finished objective still counts: the item in the bag is what gets handed in.
- **Status priority:** quest value only replaces `""` / `collected` / `sellable` / `oldexpansion`. A learnable appearance, an upgrade, openable / readable items keep their icon. It is applied after the type-specific branch in `GetCaerdonStatus`, because that branch overwrites the early `"quest"` assignment (Consumables end on `"collected"`).
- **Refresh:** `QUEST_ACCEPTED`, `QUEST_REMOVED`, `QUEST_TURNED_IN` and `PLAYER_LEVEL_UP` call `RefreshItems` after 0.5 s (quest completion flags settle after `QUEST_TURNED_IN`). `QUEST_LOG_UPDATE` is ignored once the log has loaded; it fires on every objective tick. `RefreshItems` calls `CaerdonQuestItems:InvalidateCaches()`, which drops the per-quest verdict cache.
- **Settings:** `Icon.ShowQuestItems` gates everything, in every window (see "Settings Pages"); `Icon.ShowUpcomingQuestItems` (default on) gates the not-yet-accepted quests only.
- **Debugging:** the Debug Frame export's `[Quest Value]` section prints the quest log and QuestieDB index state and every candidate quest with the reason it was kept or skipped. Use it for both "why does this have a quest icon" and "why does it not".
- **In-game status (WoW Forever, 2026-11-11):** the flagon shows the quest icon in the bags and at the BetterBags vendor. Which source produced it (quest log name match or the QuestieDB index) was not checked, and everything else was tested offline only (the real module run under LuaJIT against the decoded QuestieDB Forever data with a mocked client). Still to confirm: the objective text layout, that `select(7, GetProfessionInfo(index))` returns classic profession skill lines (if it does not, the profession rule switches itself off), and the real index build time.

- **Parked idea (author, 2026-11-14): status icons on Questie's map pins,** so a pin for a quest that can be picked up shows when one of its rewards is learnable. Nothing is built. What was checked: QuestieDB (v1.1.1) has no item rewards, only `reputationReward`, so the rewards would have to come from the client for quests that are not in the log (`C_QuestLog.RequestLoadQuestByID` is documented on Forever; whether the server answers with rewards for a quest that was never accepted is unknown and is the first thing to probe). Questie's public API (`Questie/Public`: quest updates, on-ready, nameplate icon) has no hook for map pins, so its internal pin frames would have to be wrapped, as the BetterBags vendor buttons are.

## Auction Value (Sellable Items Worth Listing)

`mogStatus = "auction"` replaces `"sellable"` when the auction house pays enough more than a vendor. Logic lives in `CaerdonAuctionValue.lua`; callers use `CaerdonItemMixin:GetAuctionValueInfo()`, which always returns the full breakdown (`shouldAuction`, `reason`, `price`, `net`, `deposit`, `profit`, `required`, ...).

- **Two statuses.** `auction` replaces `sellable`. `auctionGoods` marks trade goods (item class Trade Goods or `isCraftingReagent`) whose status is otherwise empty. Both are applied after the quest-value step in `GetCaerdonStatus`, so learnable, upgrade and quest icons always win. Soulbound, bind-on-pickup, account-bound and quest items are never candidates.
- **Rule:** `profit = quantity * (price * 0.95 - vendorPrice) - deposit * depositRisk`, `required = clamp(vendorValue * margin, floor, 1g)`, auction when `profit >= required`. The floor is `Icon.AuctionMinProfit`: `"auto"` (25c per character level, minimum 1s) or a fixed copper amount stored as a string. The 1g cap stops the margin from hiding expensive items.
- **Two rule sets (`RULES`), chosen by max stack size:** a *single item* (gear, toys) is a slow one-off sale, so `depositRisk = 2` and `margin = 1` ("at least double the vendor value after costs"). A *stackable* item is fungible with a well-defined price, so `depositRisk = 1`, `margin = 0.25`, and `quantity` is everything the toon owns, bank included (`C_Item.GetItemCount(itemID, true)`): the floor is a per-trip amount, not per unit. Built for Spider's Silk 3182 on WoW Forever (vendor 3s 87c, AH 8s 10c, level 26): one unit clears 2s 82c against a 6s 50c floor, three clear it.
- **Quantity and caching:** the `GetCaerdonStatus` cache key gets `|n<owned>` for stackable items, and `BAG_UPDATE_DELAYED` re-judges the stackable items seen this session, calling `RefreshItems` only when a verdict flips (looting one more only redraws the slot it landed in).
- **Price source:** Auctionator's public API (`Auctionator.API.v1.GetAuctionPriceByItemLink` / `GetAuctionAgeByItemLink` / `RegisterForDBUpdate`), detected at runtime. The API returns the raw lowest listing from the last scan; the 5% cut is applied here. A price older than 7 days, or with no age, is ignored.
- **No sales data exists.** Auctionator records listings only (per day: lowest low, highest low, most listed), never what sold; its posting history is the player's own listings. Throughput is therefore not modelled per item. Instead the rule sets above carry a fixed assumption (single items: deposit counted twice, roughly "one listing in three sells") and the price used is the lower of the last seen price and the median daily low of the last 14 days (needs 3+ days). The daily history comes from `Auctionator.Database:GetPriceHistory` via `Auctionator.Utilities.DBKeyFromLink`, which are internal, so every call is checked and pcall'd and the verdict falls back to the last seen price.
- **Price keys on WoW Forever:** Auctionator treats Forever as the modern AH and keys gear by item ID alone below item level 168 (`ITEM_LEVEL_THRESHOLD`), so all random suffixes of an item share one price and `IsAuctionDataExactByItemLink` cannot tell them apart. The lowest across suffixes is what gets used.
- **Deposit:** unknown formula on Forever, so the model starts at the larger of 1s or 15% of vendor price. `features/Auction.lua` calls `CaerdonAuctionValue:RecordDepositSample` when an item goes into the sell slot (`C_AuctionHouse.CalculateItemDeposit`, duration 2), which stores the measured rate and minimum in the `CaerdonAuctionData` saved variable.
- **Icon:** shown only for items in the bags or bank (`displayInfo.auctionIcon`, set in `FeatureMixin`); everywhere else an `auction` status draws as `sellable` does and `auctionGoods` draws nothing. Uses the `Auctioneer` atlas when the client has it, otherwise the gold coin. Merchant fading and the CanIMogIt comparison treat `auction` like `sellable`.
- **Refresh:** a finished Auctionator scan calls `RefreshItems` (coalesced over 1 s), as does a changed deposit rate.
- **Settings:** `Icon.ShowAuctionValue` (default on) and `Icon.AuctionMinProfit`, both on the Icons page under "Worth auctioning".
- **Debugging:** the Debug Frame export's `[Auction Value]` section prints every number behind the verdict.
- **In-game status:** untested in game. The module was run offline under LuaJIT with a mocked client and Auctionator. Still to confirm on WoW Forever: that the `Auctioneer` atlas exists, the real deposit formula, and that the sell-slot hook records a sample.

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

## Settings Pages

Two sub-pages under "Caerdon Wardrobe": **Icons** (`config/Icons.lua`) and **Display** (`config/Display.lua`), built with the layout helpers in `config/ConfigPanel.lua`. They replaced seven tabs (General, Bank & Bags, Guild Bank, Merchant, Auction, Recipes, Encounter Journal) on 2026-11-14; no saved setting was renamed or dropped.

- **Organising rule (author decisions, 2026-11-14):** the Icons page has one block per icon the addon draws: the real texture, what it means, where it shows, then its rules. A window only gets a checkbox where the choice is real, meaning the icon can occur there and a player could reasonably not want it. Do not add a per-window toggle by reflex, and never put several windows behind one toggle. Everything that is not about an icon (corner, animation, text position, vendor gray-out, tooltip line, debug) is on the Display page.
- **"Learnable by this toon" (`ownIcon`):** toggles exist only for bags and bank, guild bank, vendor and auction house (`Icon.ShowLearnable.*`). Every other window always shows it, including the Black Market, Great Vault and item conversion, which used to follow `ShowLearnable.Auction`.
- **"Learning for another toon" (`otherIcon`):** the wording is the author's: with transmog, selling the item usually teaches the look whatever the class, so "learnable by another toon" would be wrong. One key per window in `Icon.ShowLearnableByOther`: `BankAndBags`, `GuildBank`, `Merchant`, `Auction`, `BlackMarket`, `CustomerOrders`, `Loot`, `GroupLoot`, `QuestLog`, `Mail`, `TradeSkill`, `DressingRoom`, `EncounterJournal`. Features read them with `~= false`. The world map, missions, Great Vault and item conversion have no option and always allow the icon: they only show items generated for the toon looking at them, so it should not occur there.
  - **Migration:** `BlackMarket` starts from the saved `Auction` value (it followed that toggle before); the other new keys start on, which is what those windows did when they were hard-coded.
- **Quest icon:** `Icon.ShowQuestItems` is one switch for every window. Loot, mail, quest rewards, world map, missions, dungeon journal, Black Market and Great Vault used to force `questIcon.shouldShow = true` and ignore it. Professions, crafting orders, auction house and item conversion never show the quest icon.
- **Windows a client does not have** are left out of the "another toon" list. `IsWindowAddOnAvailable` in `config/Icons.lua` asks `C_AddOns.GetAddOnInfo` (available = `loadable`, or reason `DEMAND_LOADED` / `DEP_DEMAND_LOADED`), with `Blizzard_GuildBankUI` as a canary: if that reads unavailable the answers are not trusted and every window is offered. On Forever only `Blizzard_EncounterJournal` is excluded by its TOC (`AllowLoadGameType: standard, classic`); the Black Market and crafting order addons have no game-type restriction. What the API reports for a game-type-excluded addon is unverified; the worst case is a row that shows and does nothing.
- **Layout helpers:** `AddTitle`, `AddIconHeader`, `AddSection`, `AddLabel`, `AddCheckbox`, `AddCheckboxGrid`, `AddAllNoneButtons`, `AddDropdown`, `AddButton`, `FinishLayout`. Widths are fixed pixels because the pages are built before the canvas has a size (it is about 640 wide at the default panel size).
  - An option is `{ key, text, tooltip, configSection, configSubsection, configValue }`. `key` becomes the global frame name `CaerdonWardrobe<key>` and must be unique across both pages.
  - Values are resolved from `CaerdonWardrobeConfig` on every read and write: the table is replaced wholesale on a settings version bump, a missing section is created on write, and a nil value reads as the `NS:GetDefaultConfig()` default. Every control is read again when its page is shown.
  - `dependsOn` grays a control out while its parent checkbox is off. The option's `tooltip` shows on hover; before this rewrite those texts were never displayed.
- **Adding a setting:** a default in `GetDefaultConfig`, a nil-migration in the `VARIABLES_LOADED` handler in `config/Config.lua`, and one option on a page.
- **Layout settings (2026-11-14; step 1 of a planned layout editor, requested in GitHub issues #20 and #25):** where the three things on a slot sit and how big they are.
  - **Keys:** status icon `Icon.Position`, `Icon.Scale`, `Icon.OffsetX / OffsetY`; binding text `Binding.Position`, `Binding.Scale`, `Binding.OffsetX / OffsetY`; a gear set's name, which is drawn in the binding text's place (a slot shows one or the other), `Binding.GearSet.Position / Scale / OffsetX / OffsetY`; item level gain `Icon.UpgradeDelta.Position / Scale / OffsetX / OffsetY`. Positions are any of the nine anchor names (the two old dropdowns only offered four corners and top / center / bottom). Scales are percentages. Offsets are a nudge to the right / upwards in pixels; for the icon they are pixels on a slot with a 20 px icon and scale with the icon. They are edited in the layout editor (below), not on a settings page.
  - **Everything is relative to the window's own values:** size is a factor on `statusProminentSize` / `bindingScale`, the nudge is added to the window's inset. `CaerdonWardrobeMixin:GetStatusBaseSize(options)` is the one place the icon size comes from.
  - **Hand-fitted windows are left alone:** a window that overrides the position (`overrideStatusPosition` / `overrideBindingPosition`) or passes `fixedLayout = true` gets no size factor and no nudge for that part. `fixedLayout` marks lists that fit the icon into a row without overriding the anchor (profession rows, Skillet, Angrier World Quests, World Quests List); those still follow the player's anchor, as they always did. Round buttons are not hand-fitted in this sense and do follow the player's size.
  - **Inset and anchor:** the inset from the anchor's edge only applies along an axis where the anchor is on an edge (none sideways for `TOP`, none at all for `CENTER`). A window's explicit `statusOffsetX / Y` follows the same rule, because it was made for a corner; before, it was applied even on a centered axis. Exception: where the window also overrides the anchor, its numbers are used as written (Sorted centers the icon with -0.6 / -0.6).
  - **Scaled text and offsets:** `SetPoint` offsets of a region with `SetScale` are in its own units, so the default spacing (and the stack count clearance) is divided by the player's scale to stay the same on screen. A window's own `bindingScale` is not compensated; its offsets were tuned in scaled units.
  - **Text against a side:** with a left or right anchor chosen by the player the text is justified to that side. Hand-fitted windows keep it centered in its box, which is how their offsets were tuned.
  - **Text and a number on the same row (author decision, 2026-11-14):** a part goes where the player puts it. The level gain never moves. Text (binding text or a gear set's name) that shares the gain's row (top, middle or bottom) and would run into it sideways moves away from the row's edge by the gain's height, the same thing it does for a stack count; BoE in the bottom left and "+5" in the bottom right fit side by side and are left alone. Spans are worked out from the measured string widths (`HorizontalSpan`, `GetLevelGainClearance` in `CaerdonWardrobe.lua`). Hand-fitted text is not moved. `bindingTextMovedFor` on the overlay says what moved the text (`"gain"`, `"count"` or nil).
    - **Before:** the gain was the one that moved, above any text on the bottom edge. The author placed the gain in the bottom right in the editor and it stayed part-way up the slot ("If I choose bottom right for item level, I'd expect it to move there and (if necessary) move something else out of the way"). He also wants the stacking kept, because the parts are optional and overlap looks wrong, so the rule keeps stacking but only when the two really collide and always moves the text.
    - **Visible change for existing setups:** with text at the bottom and the level gain on (it is off by default), "+5" now sits in the corner with the text above it; it used to be the other way round. The same applies to a gear set item, whose arrow is suppressed and whose name used to stay under the gain.
    - **Middle row:** text there has no vertical offset (it used to sit 2 px above center, which left it higher than a level gain beside it), except in hand-fitted windows. When it has to clear a gain on the middle row it moves away from the status icon: down when the icon is on the top row, otherwise up.
    - **Samples measure text at normal scale** (`MeasureStringWidth`). A string's width in its own units depends on the scale it is drawn at, because letters are fitted to whole pixels: in the editor's four-times slot "BoE" came to about 19 units against about 22 on a real slot. The large slot therefore showed binding text (middle left) and the level gain (middle right) fitting side by side while the true-size examples, and real slots, pushed the text out of the way (seen by the author, 2026-11-14). With `options.sample` the widths are taken from a hidden string at `UIParent` scale. On a 37 px slot those two do not fit on one row: 1 + 22 for BoE and 13 + 4 for "+5" come to 40.
    - **The gain's inset is 4 px from every edge it is anchored to** (`LEVEL_GAIN_INSET`; none along an axis it is centered on). It was 2 px, which the author found crammed against the edge once the gain sat in a corner by itself (2026-11-14).
    - **Not covered:** the stack count lift is still unconditional for bottom text (it does not check whether the two meet sideways), and nothing keeps text or the gain clear of the status icon.
  - **Layout editor (`config/LayoutEditor.lua`, global `CaerdonWardrobeLayoutEditor`, `/caerdonlayout`):** a floating window opened from the Display page's "Adjust layout..." button. A first version put these settings on the Display page as seven dropdowns; the author rejected that ("I expected we'd do something with more design behind it - like a representative button that showed as an example"), so placement is edited on an example slot instead and the Display page only shows the current look and the button.
    - **The examples are real.** Every sample is an `ItemButton` decorated by `SetupCaerdonButton` / `SetItemButtonStatus` / `SetItemButtonBindType` with a made-up status, so nothing is a mock-up that can drift from the drawing code. The large slot is a 37 px slot inside a frame with `SetScale(4)`; the row under it and the row on the Display page are the same at true size: All parts (star, BoE, +5), New look (star and BoE with no stack count or level gain, so the text shows exactly where its anchor puts it; the author asked for this one), Upgrade (arrow with +5), Stack (sellable, BoE over a stack count), Gear set (a name). Their pictures are classic starter items' icons (`C_Item.GetItemIconByID`); the item handed to the drawing code is Hearthstone 6948, which has no gear set or appearance to interfere.
    - **The editor mirrors the settings (author decision, 2026-11-14):** a part that is switched off everywhere is not drawn on the examples and has no button in the editor, and an example that is only about such a part is left out, with the rest of the row closing the gap. Parts are switched on and off on the Icons page, never in the editor. `EnabledParts()` reads `Icon.ShowUpgradeIcon` (arrow), `Icon.ShowUpgradeLevelDelta` (level gain), `Binding.ShowBoE` / `ShowBoA` (binding text; with only BoA on the examples read "BoA") and `Binding.ShowGearSets` (gear set name). Each entry of `TEMPLATES` names what it is about in `needs`: New look and Stack need the binding text, Upgrade the arrow or the level gain, Gear set the gear set name; All parts always shows, down to a bare star. `BuildSample(template, enabled)` gives the example as the settings draw it (`has` = the parts on it, `visible`), and `Editor:Normalize()` moves the large slot and the selection off anything that has gone away. "Reset everything" still resets the hidden parts.
      - The per-window choices (`Binding.ShowStatus.*`, `Icon.ShowSellable.*` and the like) do not hide anything here: the sample feature's `GetDisplayInfoInternal` shows every part, because an example slot belongs to no window.
      - **`options.sample = true` no longer lifts any setting** in the drawing code; it only makes text be measured at normal scale (see "Samples measure text at normal scale"). Until this change it bypassed the upgrade arrow and gear set name switches, and at first the level gain's too.
    - **Examples as a chooser:** the true-size row (All parts, New look, Upgrade, Stack, Gear set) is clickable in the editor and decides what the large slot shows. Each example lists the parts it has; selecting a part the large slot lacks goes back to "All parts", choosing an example without the selected part selects the first part it has, and selecting the Gear set part switches to the gear set example, the only one that shows a name.
    - **A gear set's name is a part of its own.** It first was a second "Gear set names" stepper under Binding text, a factor on the text's size. In game that read as a control that did nothing (the large slot showed BoE) and then as two controls for one size (on the gear set example both changed it); the author asked why it was not just "Size like the others". So it has its own full layout, edited with the same controls, and is independent of the binding text's. On migration it starts from the binding text's position, size and nudge, because that is where gear set names were drawn until then.
    - **The chosen example's outline is drawn under the addon's parts:** it is made of textures on the example's own slot, 3 px outside its edge, so the status icon (on the overlay frame above the slot) is drawn over it. A frame around the slot cut across an icon hanging over the corner, which the author pointed out; padding the frame out to enclose the icon would have broken again at a larger icon size or another corner.
    - **The level gain is off by default** (`Icon.ShowUpgradeLevelDelta`), so the author had never seen it on Forever and read the part's name, then "Item level", as an item level display; it is called "Level gain". The editor briefly had a checkbox for that setting next to the part. First the examples ignored it (ticking it changed nothing on screen), then they followed it with a note explaining an empty example, and the author's conclusion was that the checkbox did not belong there: "We already have a way to turn it on and off. Maybe if it is turned off in settings, it just shouldn't show up here at all?" That became the rule above for every part. Do not put on / off switches in the editor.
    - **Sample text cut to "B...":** the binding text is measured against its slot's width, and a slot drawn while its page is hidden (the Display page's row at registration) or only just shown has none yet. `RedrawSamples` therefore queues one more redraw 0.05 s later. That alone did not fix the first visit to the Display page: a page's frame is created shown, so the settings window putting it on screen is not an `OnShow`, and nothing redrew until the player left the page and came back. Pages now also set `frame.OnRefresh`, which the settings window calls every time it displays a canvas page (`SettingsPanelMixin:DisplayLayout`). The same gap meant no page re-read its settings on its first display. Not yet confirmed in game.
    - **Controls:** pick a part by clicking it on the large slot or with the three buttons (Icon, Binding text, Gear set, Level gain; the chosen one is underlined); nine squares laid out like the slot set the anchor; a stepper sets the size (5% steps, 50 to 300); four buttons in a cross nudge by a pixel (up to 40); "Reset this part" and "Reset everything" go back to `NS:GetDefaultConfig()`; "Undo changes" goes back to a snapshot taken when the editor opened, which for anyone who had moved things before is a different place.
    - **Done keeps; any other close asks (author decisions, 2026-11-14).** Changes are written as they are made so the real windows follow, which leaves no natural "cancel"; a reset is not one, because it goes to the addon's defaults. `Editor:Finish()` (the Done button) keeps without asking. The X, Escape and the slash command go through the frame's `OnHide` (`Editor:OnClosed`): with nothing changed since the snapshot the editor just closes; otherwise the `CAERDON_LAYOUT_KEEP_CHANGES` popup offers Keep, Discard and Keep editing. Only a click on Discard restores the snapshot; Escape on the popup (`OnEscape`), Keep editing, and the popup being cancelled for any other reason all reopen the editor with the original snapshot, so nothing is lost by accident. Reopening the editor while the popup is up takes the popup down and keeps the snapshot. A `/reload` or logout with the editor open keeps whatever is in the settings at that moment.
    - `OnEscape` and `noCancelOnEscape` exist in Forever's `Blizzard_StaticPopup/StaticPopup.lua` (`StaticPopup_CallEscapeHandler`); on a client without `OnEscape`, Escape on the popup falls through to `OnCancel` with reason "clicked", i.e. Discard.
    - **Moved text is explained.** When the drawing code moved the text clear of the level gain or a stack count (`bindingTextMovedFor`), the editor says so while the text or the gear set name is selected, because the text is then not where the lit anchor says. (A first version explained a raised level gain instead, from when the gain was the part that moved.)
    - **Live:** each change is written to the settings at once, the samples are redrawn, and one `RefreshItems` is queued (0.2 s) so open windows follow. Opening the editor hides the settings window, which covers most of the screen, and calls `OpenAllBags()`; closing it (Done, the close button, Escape) refreshes once more.
    - **Not built yet:** samples drawn on the player's real windows, and a stand-in for the player's own bag addon's slot (the editor shows a standard slot; other slot sizes scale from it).
    - **Status:** offline-tested with mocked frames (every control writing the right setting, limits, resets, selection, the queued redraw). Not seen in game: the whole window's layout, the scaled slot, clicking parts of it, and whether `OpenAllBags()` opens a third-party bag addon.
  - **Defaults reproduce the previous look,** checked offline for every old position value. Not yet seen in game: any non-default value, in particular text larger than 100% (the width handling for `SetScale` above 1 is new) and the item level gain away from the bottom right.
- **In-game status:** not seen in game. The pages were run offline under LuaJIT with a mocked frame API against the author's saved variables: the migration, every option resolving to a default and showing the saved value, every old setting still offered, clicks, dependents, All / None, each window feature's `GetDisplayInfo`, and an overlap check on estimated text widths. Unverified: real text widths and wrapping (`GetStringHeight` is read before the page is first shown), how the dropdowns line up next to their labels, and how the legend icons look at 24 pixels.

## Processing Pipeline Architecture

### Coroutine Processing
- `UpdateButton()` queues items into `waitingToProcess` keyed by `locationKey`
- `ProcessItem_Coroutine` (runs via `OnUpdate` every 50ms) moves items to `processQueue` and processes them
- Items where `IsItemDataCached()` is false go to a `ContinuableContainer` async path
- `IsItemDataCached()` requires BOTH `IsItemCached()` (WoW cache) AND `customDataLoaded` (CaerdonItem flag)
- Features MUST call `ContinueOnItemLoad` before `UpdateButton` so `customDataLoaded=true`; without this, items go to the ContinuableContainer path and may never process directly

### Not-Ready Retries
- When an item's tooltip still reads "Retrieving item information", `ProcessItem` stashes the request in `pendingTooltipRetries` and one 1 s timer runs all of them through `UpdateButton` again.
- The limit (`NOT_READY_MAX_RETRIES`, 10) is counted per button, in `buttonState` (`notReadyRetries`). A new `UpdateButton` request starts the count again; the timer marks its own call (`retryingNotReady`) so a retry keeps counting. Until 2026-11-14 the count lived in the caller's `options` table, which a window shares between its buttons and some integrations keep for the whole session (Baganator), so other items used the limit up.
- **Never write into `options`.** It belongs to the caller and is usually shared; per-button state goes in `buttonState` or on the overlay's own regions.
- The timer only retries while the button still belongs to the request: its location key must equal the stashed key, and its item ID must still be the request's. The key alone is not enough, because a vendor slot keeps its key when the page changes, and running the old request would clear the new item's icon.
- `GetRequestKey` builds the key (`<feature>-bag<b>-slot<s>`, or `<feature>-<locationInfo.locationKey>`) for both `UpdateButton` and the retry. Until 2026-11-14 the retry built it without the feature prefix except for bag and bank items, so the comparison always failed elsewhere and vendor, mail, loot and auction items that were not ready on the first draw were never tried again.

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
