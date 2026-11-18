# CaerdonWardrobe - Claude Documentation

This file is loaded into every session, so it holds only what an agent needs before touching the code. Per-feature detail (design decisions, client findings, what is still unverified) lives in `docs/dev-notes.md`; read the section for the area you are working on.

**Keep it that way.** A new feature gets a line or two here (entry point, where it sits in the status order) and its detail in the notes file. In both files write the rule and the reason, not the story of how it was reached: no conversation quotes, no test counts, no status update after every exchange.

## Useful Paths

- **Local clones of both flavors (may be absent):** `~/Projects/WoW/Builds/`, with `source/retail`, `source/forever`, `resources/retail`, `resources/forever`. `update.sh` there creates or refreshes all four and prints each build; run it before trusting a clone after a client patch. It keeps every build it has fetched as a `build/<version>` tag, so two builds can be diffed (`update.sh changes`).
- **The client's own export** is a manual step only the author can do. The mirrors are the default; ask for an export only when a specific build is needed and no mirror has it, and file it under `Builds/exports/` (notes: Client Sources).
- **Blizzard source, both flavors:** GitHub `Gethe/wow-ui-source`, branch `live` (retail) and branch `forever` (also `ptr`, `ptr2`, `beta`). `version.txt` names the build.
  - API documentation: `Interface/AddOns/Blizzard_APIDocumentationGenerated/` (only `C_*` namespaces and a subset of bare globals)
  - Collections: `Blizzard_FrameXMLUtil/CollectionsUtil.lua`, `Blizzard_Collections/Shared/Blizzard_Wardrobe_Sets.lua`
- **Per-flavor listings:** GitHub `Ketho/BlizzardInterfaceResources`, branches `live` and `forever`. One file each for every global API, event, enum value and enUS global string (the source mirror has no global strings). Commands and pitfalls: notes, Client Sources.

## What the Addon Does

It draws a status icon, binding text and an item level gain on item buttons in about 40 windows and bag addons. Each item gets one status (`mogStatus`) from `CaerdonItemMixin:GetCaerdonStatus`.

| Status | Meaning |
|---|---|
| `own` / `ownPlus` | Learnable by this toon (star). Plus (green): the look is already known from another item, or an ensemble with only a few pieces for this toon. Also a bag that belongs in a bag slot. |
| `other` / `otherPlus` | This toon cannot use it, but it can be learned for the collection or by another toon. |
| `send` | This toon has no use for it and another of the player's toons does: a recipe it can learn, an ingredient its recipes take (mail icon). |
| `otherNoLoot` | Something to learn, but every remaining source needs another class, race or faction. |
| `lowSkill` / `lowSkillPlus` | Learnable once a level or skill requirement is met. |
| `transform` | A piece to keep: its own look is known, and raised on its upgrade track or converted at the Catalyst it would have one that is not (small, still icon that says which: the Catalyst's mark or the upgrade vendor's; retail). |
| `upgrade` / `upgradeLowSkill` | Better gear than what is equipped. |
| `sellable` | Nothing left to do with it here. `auction` replaces it, and `auctionGoods` marks trade goods, when the auction house pays enough more. |
| `quest` | Quest item, or anything an unfinished quest takes. |
| `collected`, `oldexpansion` | Nothing to learn; from an older expansion. |
| `openable`, `locked`, `readable`, `refundable`, `canCombine`, `readyToCombine` | State of an item in the bags. |

## Code Map

- `CaerdonWardrobe.lua`: the queue (`UpdateButton`, `DrainQueue`, `ProcessItem`), drawing (`SetItemButtonStatus`, `SetItemButtonBindType`, `SetStatusIconPosition`), `RefreshItems`, what each button was last asked to show (`AskAgain`).
- `CaerdonItem.lua`: `CaerdonItemMixin` with `GetCaerdonStatus`, the tooltip scan (`GetTooltipData`) and `GetBindingStatus`.
- `types/*Mixin.lua`: per item type data (`GetTransmogInfo()`, `GetRecipeInfo()`, ...).
- `FeatureMixin.lua`, `features/*.lua`: one feature per Blizzard window. `external/*`: one per third-party addon.
- Signal modules, each with a `CaerdonItemMixin` entry point: `CaerdonQuestItems` (`GetQuestItemInfo`), `CaerdonAuctionValue` (`GetAuctionValueInfo`), `CaerdonFoodDrink` (`GetFoodDrinkInfo`), `CaerdonProfessionTools` (`GetProfessionToolInfo`), `CaerdonBagSlots` (`GetBagSlotInfo`), `CaerdonIngredients` (`GetIngredientInfo`: what the recorded recipes of this toon and its other toons take), `CaerdonVendorGoods` (`GetVendorInfo`: how many vendors sell it, from QuestieDB where that is loaded), `CaerdonTransformLooks` (`GetTransformLookInfo`: the look a season's piece gains by being raised on its upgrade track or converted at the Catalyst; retail).
- `CaerdonRefresh.lua`: the refresh watcher (`NS.Refresh:Watch`). An event that also comes when nothing changed (skill lines, the player's flags, reputation, quest events, housing) is compared before it refreshes: with the last reading, with what was saved for the toon (reputation, `CaerdonRefreshData`), or by the module that owns it with what it answered (the quest module).
- `CaerdonIntegrations.lua`: whether each third-party integration found the functions it hooks (the export's `[Integrations]` section).
- `CaerdonCounters.lua`: loaded first. Login milestones, loads asked of the client and full refreshes by trigger, always; time and memory per function while its profile is switched on, which the test addon does (the export's `[Counters]` section).
- `config/`: `Config.lua` (defaults, migrations, the main page, `/caerdon`, the one-time message dialog), `Icons.lua` and `Display.lua` (the two settings pages), `ConfigPanel.lua` (layout helpers), `LayoutEditor.lua` (`/caerdonlayout`).
- `features/DebugFrame.lua`: the Debug Frame and its **Copy Details** export (`/cdebug`). `CaerdonButtonGeometry.lua`: the export's button measurements.
- `tools/`: development scripts, not packaged. `static-checks.lua` with its allowlist `static-checks-allow.lua`; `test-results.lua` prints what the test addon saved in each client; `harness/` runs the addon's real item code under LuaJIT in a mocked client (`luajit tools/harness/run.lua`): scenarios against a hand-made game, and fixtures, which are a client's recorded answers replayed.
- `CaerdonWardrobe_Tests/`: the test addon, a second addon for development that runs in both clients and is not packaged (`/cwtest`): client contracts, verdict tests, snapshot and diff, timing, a journal of what was learned, bag states checked when an item shows one, a record per integration, a rotation through the installed bag addons (`/cwtest rotation`), a recorder of the client's answers behind one verdict for the harness (`/cwtest record`).

### Status order in `GetCaerdonStatus`

Each later step only replaces the statuses listed, so an upgrade keeps its icon, and a learnable look keeps its own against everything but a quest.

1. Old expansion and Quest-class items (early; the type branch may overwrite them).
2. The branch for the item's type (equipment, consumable, recipe, pet, mount, toy, ...). A piece of equipment that would be `collected` and would gain an unknown look by an upgrade or at the Catalyst is `transform` here instead, so it is never `sellable` or `auction`; an upgrade keeps its arrow and a gear set's piece stays `collected` with the set's mark (notes: Looks After a Change).
3. Equippable junk becomes `sellable` (replaces empty).
4. Bags against the bag slots: `own` / `lowSkill` or `sellable` (replaces empty, `oldexpansion`).
5. Consumables for another class become `sellable` (replaces empty, `collected`).
6. Recipes this toon has no use for: `send` / `sellable` (replaces `collected`).
7. Outgrown food and drink become `sellable` (replaces empty, `collected`).
8. Ingredients this toon has no use for: `send` when another toon's recipes take it and vendors everywhere do not sell it, `sellable` when its own have outgrown it (replaces empty).
9. Quest value becomes `quest` (replaces empty, `collected`, `sellable`, `send`, `oldexpansion`, `transform` and every learnable status: `own`, `other`, their Plus forms, `otherNoLoot`, `lowSkill`; not an upgrade).
10. Auction value: `sellable` becomes `auction`; plain trade goods become `auctionGoods`, unless kept as an ingredient.
11. Bag-location overrides: `openable`, `locked`, `readable`, `refundable`, combine spells.

The result is cached by item link (plus `|B` when soulbound, `|c` for a crafted piece that lies in a slot, `|x` for a season's armor that lies in a slot and may go to the Catalyst, `|n<owned>` for stackable items, and `|s<source>` / `|l<level>` for a row whose window passed a source or an item level) until `RefreshItems`. A piece of equipment's transmog info is cached with it and returned fifth. Step 11 is not part of what is cached: it belongs to one copy in its bag slot and is added after the lookup, on every call (`GetCopyStatus`; notes: Refresh).

## Rules

- **WoW Forever is not retail.** Its server rules differ (what a bag slot accepts, when an appearance is learned, armor proficiency). Do not write a rule from retail knowledge; get a Copy Details export that shows it.
- **Retail and Forever share one code base and TOC.** Check an API, event, enum value, global string or hooked Blizzard function against both flavors' source before relying on it, then confirm in each client. Text differs between them (retail "Warbound", Forever "Account bound"), so a fixture or expected value belongs to one flavor.
- **Feature detection, not flavor checks.** `CaerdonAPI:IsForeverClient()` is for reporting. `select(4, GetBuildInfo())` is `16001` on Forever, so a `>= 110000` gate is false there: use one only for features Forever really lacks (housing), never to pick an API path.
- **Legacy globals:** many undocumented ones still exist on Forever, but confirm each by finding a call in Blizzard's camelot-loaded Lua. Never call `GetSpecialization`, `GetSpecializationInfo` or `GetSpecializationInfoByID` directly; use the `CaerdonAPI` wrappers.
- **Investigating an item:** extend the Copy Details export instead of adding prints. Keep additions structured and readable.
- **New item signals** go through the item's data mixin or a signal module with a `CaerdonItemMixin` entry point, never ad-hoc API calls in feature files.
- **An integration declares its hook points and notes each one** (`Mixin.integration`, `self:NoteHookPoint(label, owner, key)` on the line before it attaches). That is how a user's export says the other addon changed (notes: Integration Report).
- **Never write into `options`.** It belongs to the caller and is usually shared between buttons. Per-button state goes in `buttonState` or on the overlay's regions.
- **A feature's `Refresh()` must re-run `UpdateButton`** for the buttons it decorated, and is never left empty: `RefreshItems` only wipes caches. A feature with none inherits the default, which asks again for every button the feature last asked for (`CaerdonWardrobe:AskAgain`; notes: Processing Pipeline). Write one only where a window has to be walked.
- **A feature asks for a window's buttons only while the window is on screen** (`IsVisible`, not `IsShown`: a host addon parks Blizzard's window under a hidden parent and leaves it shown), and only where the window asks again when it comes on screen; where it does not and the cost is measured, the button is owed a draw for when it is (`AskWhenOnScreen`; notes: Processing Pipeline). The default `Refresh()` owes every button that is not on screen.
- **Features call `ContinueOnItemLoad` before `UpdateButton`**, so `customDataLoaded` is true.
- **A draw path does not call `GetTransmogInfo()`.** It reads the table `GetCaerdonStatus` returns, which is the one the verdict was made from and is shared by every button of that cache entry (notes: Processing Pipeline).
- **A change to the drawing code is compared with the code from before, call by call:** `scenarios/draw-path.lua` writes down every widget call of `SetItemButtonStatus` and `SetItemButtonBindType` (notes: Offline Harness, Scenarios).
- **An item's table holds only its data.** Its methods come through a metatable, so do not copy an item or walk it with `pairs` for them (notes: Processing Pipeline).
- **One failure stays alone:** the core calls each feature's `Init`, `Refresh` and event handlers and draws each queued item through `Contained`, which hands an error to the game's error handler and carries on. A new loop over features or items does the same (notes: Processing Pipeline).
- **A verdict that depends on game state needs its own refresh:** the status cache is keyed by item link, so the module must call `RefreshItems` when that state changes. The signal modules show the pattern: compare a signature, refresh only on a change. An event that also comes when nothing changed gets a watch instead of a handler, and a refresh says why (`RefreshItems(reason, detail)`; notes: Refresh).
- **A refresh that says what changed keeps the rest** (`RefreshItems(reason, detail, changed)`, `"worn"` or `"collection"`): the equipment code keeps what the client said about sources when only the worn gear changed, the quest module its answers in both cases. A new input to either that follows from what is worn or learned means it may no longer be kept (the comment on each module's `InvalidateCaches`; notes: Refresh).
- **The counters wrap functions by name** (`Counters:Attach`). Renaming or splitting one of them means changing its line there; the export says "not found" for one it missed (notes: Counters).
- **Do not refresh on `TRANSMOG_SOURCE_COLLECTABILITY_UPDATE`:** the addon's own queries trigger it, which risks a loop.
- **Do not change `LoadSources`' `#waitingForItems == 0` check** or remove the once-guard in `ContinueWithCancelOnItemLoad` (notes: LoadSources).
- **Settings:** an option only where the choice is real. One block per icon on the Icons page; no per-window toggle by reflex; no on / off switches in the layout editor. A new setting needs a default in `GetDefaultConfig`, a nil-migration in `config/Config.lua` and one option on a page. A setting that describes the toon and not the player's taste (which specs it plays) is kept per character instead (`CaerdonWardrobeCharacterConfig`, `perCharacter = true` on the option, a label that says so; notes: Settings); keep that list short, and no profiles.
- **Placement:** a window opts in to the standard icon size with `GetSlotStatusSize`. Do not replace a hand-tuned value for a window that has not been measured, and do not judge a button's shape from its numbers alone.
- **Tests:** `luajit tools/harness/run.lua` runs the item code offline under LuaJIT in a mocked client; run it before calling a change to that code done. That checks logic, not the client; say which of the two a claim rests on. A fixture that comes out `stale` asks for a new recording, not for an edit of the fixture (notes: Offline Harness). What the test addon recorded was seen in a client: read it with `luajit tools/test-results.lua` after the author has reloaded. A change that should leave every icon as it was is proven by its snapshot diff (notes: Test Addon).
- **The test addon's code runs in the client's Lua 5.1:** no `pcall` or `xpcall` around code that waits (use `T.Protected`), and `%s` only for strings and numbers.
- **Static check:** `luajit tools/static-checks.lua` reports every name the addon or the test addon uses that one client or neither has, and every global written that is not on the allowlist. Run it before calling a change done and after a client patch. A new flavor-specific name needs an allowlist entry naming its guard, and a change to the names the addon uses needs `--emit-facts`, which also rewrites the list the recorder hooks (notes: Static Check).

## WoW Forever Essentials

A mainline-family client: retail 12.x UI architecture running classic-era content, supported from the same code base and TOC. Game type `camelot`, `WOW_PROJECT_ID` 18, `## Interface: 16001`.

- **Not loaded:** Blizzard_EncounterJournal, Blizzard_GarrisonUI, Blizzard_Housing*, Blizzard_ExpansionTrial. Blizzard TOCs gate with `AllowLoadGameType` (`mainline` includes camelot, `standard` is retail only); Forever overrides live in `Camelot/` folders.
- **No specializations.** One trait tree per class in three groups; `CaerdonAPI:GetTalentTrees()` / `GetPrimaryTalentTree()`.
- **Selling an item to a vendor teaches its appearance,** whatever the class. The transmog collect APIs do not reflect that.
- **Classic armor proficiency** (mail and plate at 40) is invisible to the transmog APIs. Red tooltip text is the authority for "can equip now".
- **Classic stats are "Equip:" lines:** spell power, attack power, crit and the like come as green "Equip:" lines of type `None`, built from the client's `TOOLTIP_ITEM_STAT_*` strings. A real effect is typed `ItemSpellTriggerOnEquip` (notes: Sellable Rules).
- **Classic ranged slot** (`INVSLOT_RANGED`, `C_PaperDollInfo.IsRangedSlotShown()` true) and no profession gear slots: tools are carried in the bags.
- **Bag slots:** four normal slots plus a reagent slot that also takes profession bags.
- **Mixin-based mail frame** (`InboxFrame:Update()`), camelot bank panel, a wardrobe UI that hides uncollected appearances. The `C_TransmogCollection` APIs are unchanged.

## Notes Index (`docs/dev-notes.md`)

| Working on | Section |
|---|---|
| Anything Forever-specific | WoW Forever Client |
| Getting Blizzard's code or listings for either flavor | Client Sources |
| Checking names against both clients, the allowlist | Static Check |
| The test addon, `/cwtest`, reading its results | Test Addon |
| Running the item code offline, recording an item, fixtures | Offline Harness |
| What a draw or a refresh costs, who asked the client for an item | Counters |
| What a tooltip line carries, the export's tooltip sections | Tooltip Lines in the Export |
| Appearances, `own` vs. `other`, selling teaches | Transmog on Forever |
| A look known from another item, the Plus statuses | Known Looks |
| A look a piece gains by an upgrade or at the Catalyst | Looks After a Change |
| Ensembles | Ensembles |
| Upgrade arrow, Pawn, equal item level, badge | Upgrades |
| What is and is not `sellable` | Sellable Rules |
| Tools, bags, recipes, food and drink | Profession Tools; Bags for the Bag Slots; Recipes This Toon Has No Use For; Outgrown Food and Drink |
| Trade goods a recipe takes, recipes recorded with their difficulty | Ingredients |
| Quest icon on non-quest items | Quest Value |
| Auction icon | Auction Value |
| Housing items (retail only) | Housing |
| Stale icons, refresh events | Refresh |
| Baganator, BetterBags | Bag Addon Integrations |
| An integration that stopped drawing, hook points | Integration Report |
| Quest rewards in the Dialogue UI addon | Dialogue UI |
| Icon size, clipping, measuring a window | Icon Size and Placement |
| Settings pages, layout settings | Settings |
| Layout editor | Layout Editor |
| Queue, retries, overlay | Processing Pipeline |
| Dressing room | Dressing Room |
| Item load callbacks | LoadSources |
