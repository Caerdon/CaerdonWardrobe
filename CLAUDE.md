# CaerdonWardrobe - Claude Documentation

This file is loaded into every session, so it holds only what an agent needs before touching the code. Per-feature detail (design decisions, client findings, what is still unverified) lives in `docs/dev-notes.md`; read the section for the area you are working on.

**Keep it that way.** A new feature gets a line or two here (entry point, where it sits in the status order) and its detail in the notes file. In both files write the rule and the reason, not the story of how it was reached: no conversation quotes, no test counts, no status update after every exchange.

## Useful Paths

- **Blizzard source (local copy, may be absent):** `../../../BlizzardInterfaceCode/`
- **WoW Forever Blizzard source:** GitHub `Ketho/wow-ui-source-forever`, branch `forever` (shallow clone it when needed). Retail mirror: `Gethe/wow-ui-source`, branch `live`.
  - API documentation: `Interface/AddOns/Blizzard_APIDocumentationGenerated/` (only `C_*` namespaces and a subset of bare globals)
  - Collections: `Blizzard_FrameXMLUtil/CollectionsUtil.lua`, `Blizzard_Collections/Shared/Blizzard_Wardrobe_Sets.lua`

## What the Addon Does

It draws a status icon, binding text and an item level gain on item buttons in about 40 windows and bag addons. Each item gets one status (`mogStatus`) from `CaerdonItemMixin:GetCaerdonStatus`.

| Status | Meaning |
|---|---|
| `own` / `ownPlus` | Learnable by this toon (star). Plus (green): the look is already known from another item, or an ensemble with only a few pieces for this toon. Also a bag that belongs in a bag slot. |
| `other` / `otherPlus` | This toon cannot use it, but it can be learned for the collection or by another toon. |
| `otherNoLoot` | Something to learn, but every remaining source needs another class, race or faction. |
| `lowSkill` / `lowSkillPlus` | Learnable once a level or skill requirement is met. |
| `upgrade` / `upgradeLowSkill` | Better gear than what is equipped. |
| `sellable` | Nothing left to do with it here. `auction` replaces it, and `auctionGoods` marks trade goods, when the auction house pays enough more. |
| `quest` | Quest item, or anything an unfinished quest takes. |
| `collected`, `oldexpansion` | Nothing to learn; from an older expansion. |
| `openable`, `locked`, `readable`, `refundable`, `canCombine`, `readyToCombine` | State of an item in the bags. |

## Code Map

- `CaerdonWardrobe.lua`: the queue (`UpdateButton`, `ProcessItem`), drawing (`SetItemButtonStatus`, `SetItemButtonBindType`, `SetStatusIconPosition`), `RefreshItems`.
- `CaerdonItem.lua`: `CaerdonItemMixin` with `GetCaerdonStatus`, the tooltip scan (`GetTooltipData`) and `GetBindingStatus`.
- `types/*Mixin.lua`: per item type data (`GetTransmogInfo()`, `GetRecipeInfo()`, ...).
- `FeatureMixin.lua`, `features/*.lua`: one feature per Blizzard window. `external/*`: one per third-party addon.
- Signal modules, each with a `CaerdonItemMixin` entry point: `CaerdonQuestItems` (`GetQuestItemInfo`), `CaerdonAuctionValue` (`GetAuctionValueInfo`), `CaerdonFoodDrink` (`GetFoodDrinkInfo`), `CaerdonProfessionTools` (`GetProfessionToolInfo`), `CaerdonBagSlots` (`GetBagSlotInfo`).
- `config/`: `Config.lua` (defaults, migrations), `Icons.lua` and `Display.lua` (the two settings pages), `ConfigPanel.lua` (layout helpers), `LayoutEditor.lua` (`/caerdonlayout`).
- `features/DebugFrame.lua`: the Debug Frame and its **Copy Details** export (`/cdebug`). `CaerdonButtonGeometry.lua`: the export's button measurements.

### Status order in `GetCaerdonStatus`

Each later step only replaces the statuses listed, so a learnable look or an upgrade keeps its icon.

1. Old expansion and Quest-class items (early; the type branch may overwrite them).
2. The branch for the item's type (equipment, consumable, recipe, pet, mount, toy, ...).
3. Equippable junk becomes `sellable` (replaces empty).
4. Bags against the bag slots: `own` / `lowSkill` or `sellable` (replaces empty, `oldexpansion`).
5. Consumables for another class become `sellable` (replaces empty, `collected`).
6. Recipes this toon has no use for: `other` / `otherPlus` / `sellable` (replaces `collected`).
7. Outgrown food and drink become `sellable` (replaces empty, `collected`).
8. Quest value becomes `quest` (replaces empty, `collected`, `sellable`, `oldexpansion`).
9. Auction value: `sellable` becomes `auction`; plain trade goods become `auctionGoods`.
10. Bag-location overrides: `openable`, `locked`, `readable`, `refundable`, combine spells.

The result is cached by item link (plus `|B` when soulbound and `|n<owned>` for stackable items) until `RefreshItems`.

## Rules

- **WoW Forever is not retail.** Its server rules differ (what a bag slot accepts, when an appearance is learned, armor proficiency). Do not write a rule from retail knowledge; get a Copy Details export that shows it.
- **Feature detection, not flavor checks.** `CaerdonAPI:IsForeverClient()` is for reporting. `select(4, GetBuildInfo())` is `16001` on Forever, so a `>= 110000` gate is false there: use one only for features Forever really lacks (housing), never to pick an API path.
- **Legacy globals:** many undocumented ones still exist on Forever, but confirm each by finding a call in Blizzard's camelot-loaded Lua. Never call `GetSpecialization`, `GetSpecializationInfo` or `GetSpecializationInfoByID` directly; use the `CaerdonAPI` wrappers.
- **Investigating an item:** extend the Copy Details export instead of adding prints. Keep additions structured and readable.
- **New item signals** go through the item's data mixin or a signal module with a `CaerdonItemMixin` entry point, never ad-hoc API calls in feature files.
- **Never write into `options`.** It belongs to the caller and is usually shared between buttons. Per-button state goes in `buttonState` or on the overlay's regions.
- **Every feature's `Refresh()` must re-run `UpdateButton`** for the buttons it decorated. `RefreshItems` only wipes caches.
- **Features call `ContinueOnItemLoad` before `UpdateButton`**, so `customDataLoaded` is true.
- **A verdict that depends on game state needs its own refresh:** the status cache is keyed by item link, so the module must call `RefreshItems` when that state changes. The signal modules show the pattern: compare a signature, refresh only on a change.
- **Do not refresh on `TRANSMOG_SOURCE_COLLECTABILITY_UPDATE`:** the addon's own queries trigger it, which risks a loop.
- **Do not change `LoadSources`' `#waitingForItems == 0` check** or remove the once-guard in `ContinueWithCancelOnItemLoad` (notes: LoadSources).
- **Settings:** an option only where the choice is real. One block per icon on the Icons page; no per-window toggle by reflex; no on / off switches in the layout editor. A new setting needs a default in `GetDefaultConfig`, a nil-migration in `config/Config.lua` and one option on a page.
- **Placement:** a window opts in to the standard icon size with `GetSlotStatusSize`. Do not replace a hand-tuned value for a window that has not been measured, and do not judge a button's shape from its numbers alone.
- **Tests:** the modules can be run offline under LuaJIT with a mocked client. That checks logic, not the client; say which of the two a claim rests on.

## WoW Forever Essentials

A mainline-family client: retail 12.x UI architecture running classic-era content, supported from the same code base and TOC. Game type `camelot`, `WOW_PROJECT_ID` 18, `## Interface: 16001`.

- **Not loaded:** Blizzard_EncounterJournal, Blizzard_GarrisonUI, Blizzard_Housing*, Blizzard_ExpansionTrial. Blizzard TOCs gate with `AllowLoadGameType` (`mainline` includes camelot, `standard` is retail only); Forever overrides live in `Camelot/` folders.
- **No specializations.** One trait tree per class in three groups; `CaerdonAPI:GetTalentTrees()` / `GetPrimaryTalentTree()`.
- **Selling an item to a vendor teaches its appearance,** whatever the class. The transmog collect APIs do not reflect that.
- **Classic armor proficiency** (mail and plate at 40) is invisible to the transmog APIs. Red tooltip text is the authority for "can equip now".
- **Classic ranged slot** (`INVSLOT_RANGED`, `C_PaperDollInfo.IsRangedSlotShown()` true) and no profession gear slots: tools are carried in the bags.
- **Bag slots:** four normal slots plus a reagent slot that also takes profession bags.
- **Mixin-based mail frame** (`InboxFrame:Update()`), camelot bank panel, a wardrobe UI that hides uncollected appearances. The `C_TransmogCollection` APIs are unchanged.

## Notes Index (`docs/dev-notes.md`)

| Working on | Section |
|---|---|
| Anything Forever-specific | WoW Forever Client |
| Appearances, `own` vs. `other`, selling teaches | Transmog on Forever |
| Ensembles | Ensembles |
| Upgrade arrow, Pawn, equal item level, badge | Upgrades |
| What is and is not `sellable` | Sellable Rules |
| Tools, bags, recipes, food and drink | Profession Tools; Bags for the Bag Slots; Recipes This Toon Has No Use For; Outgrown Food and Drink |
| Quest icon on non-quest items | Quest Value |
| Auction icon | Auction Value |
| Stale icons, refresh events | Refresh |
| Baganator, BetterBags | Bag Addon Integrations |
| Icon size, clipping, measuring a window | Icon Size and Placement |
| Settings pages, layout settings | Settings |
| Layout editor | Layout Editor |
| Queue, retries, overlay | Processing Pipeline |
| Dressing room | Dressing Room |
| Item load callbacks | LoadSources |
