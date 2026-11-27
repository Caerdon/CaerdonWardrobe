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
| `own` / `ownPlus` | Learnable by this toon (star). Plus (green): the look is already known from another item, or an ensemble with only a few pieces for this toon. Also a bag that belongs in a bag slot, and an item that starts a quest the toon has neither done nor taken (with the quest icon as the small mark; `lowSkill` below the quest's level). |
| `other` / `otherPlus` | This toon cannot use it, but it can be learned for the collection or by another toon. |
| `send` | This toon has no use for it and another of the player's toons does: a recipe, a spell book or a rune it can learn, an ingredient its recipes take (mail icon). |
| `otherNoLoot` | Something to learn, but every remaining source needs another class, race or faction. |
| `lowSkill` / `lowSkillPlus` | Learnable once a level or skill requirement is met. |
| `transform` | A piece to keep: its own look is known, and raised on its upgrade track or converted at the Catalyst it would have one that is not (small, still icon that says which: the Catalyst's mark or the upgrade vendor's; retail). |
| `upgrade` / `upgradeLowSkill` | Better gear than what is equipped. |
| `sellable` | Nothing left to do with it here. `auction` replaces it, and `auctionGoods` marks trade goods, when the auction house pays enough more. |
| `quest` | Quest item (until every quest known for it is behind the toon), or anything an unfinished quest takes. |
| `collected`, `oldexpansion` | Nothing to learn; from an older expansion. |
| `openable`, `locked`, `readable`, `refundable`, `canCombine`, `readyToCombine` | State of an item in the bags. |

## Code Map

- `CaerdonWardrobe.lua`: the queue (`UpdateButton`, `DrainQueue`, `ProcessItem`), drawing (`SetItemButtonStatus` with its table of icons `STATUS_ICONS`, `SetItemButtonBindType`, `SetStatusIconPosition`), `RefreshItems`, what each button was last asked to show (`AskAgain`).
- `CaerdonItem.lua`: `CaerdonItemMixin` with `GetCaerdonStatus`, the tooltip scan (`GetTooltipData`) and `GetBindingStatus`.
- `types/*Mixin.lua`: per item type data (`GetTransmogInfo()`, `GetRecipeInfo()`, ...).
- `FeatureMixin.lua`, `features/*.lua`: one feature per Blizzard window. `external/*`: one per third-party addon.
- Signal modules, each with a `CaerdonItemMixin` entry point: `CaerdonQuestItems` (`GetQuestItemInfo`; its quest data is QuestieDB's and AllTheThings', the second through `CaerdonQuestSourceATT.lua`; a quest's level and whether it is trivial are the client's own word where it has the quest's data, which `CaerdonQuestClient.lua` asks it to load; which quest a copy in a bag slot starts is the client's word too, `GetSlotQuestInfo`), `CaerdonAuctionValue` (`GetAuctionValueInfo`), `CaerdonFoodDrink` (`GetFoodDrinkInfo`), `CaerdonProfessionTools` (`GetProfessionToolInfo`), `CaerdonBagSlots` (`GetBagSlotInfo`), `CaerdonIngredients` (`GetIngredientInfo`: what the recorded recipes of this toon and its other toons take), `CaerdonVendorGoods` (`GetVendorInfo`: how many vendors sell it, from QuestieDB where that is loaded), `CaerdonLearners` (`GetLearnerInfo`: what each of the realm's other toons said of a spell book or rune, each by its own tooltip, saved per toon), `CaerdonLedger` (`CaerdonLedger:GetHeld`: where a copy of a recipe, book or rune was last seen with a toon: its bags, its bank, its mailbox, on its way there; `GetOwnCopies` for the toon that is played), `CaerdonTransformLooks` (`GetTransformLookInfo`: the look a season's piece gains by being raised on its upgrade track or converted at the Catalyst; retail), `CaerdonSetBonuses` (`GetSetBonusChanges`: the set bonuses a piece would bring or end by being worn; a tooltip line, no status).
- `CaerdonFormatPattern.lua`: a client format string as a pattern (`NS.FormatPattern`), for the facts that are only a line of tooltip text (notes: Text Read Off a Tooltip Line).
- `CaerdonLevelBonuses.lua`: which bonus IDs give an item which level (`NS.LevelBonuses`), asked of the client once a build in the background and saved; what a gear set marked for PVP is scored by (notes: Upgrades).
- `CaerdonRefresh.lua`: the refresh watcher (`NS.Refresh:Watch`). An event that also comes when nothing changed (skill lines, the player's flags, reputation, quest events, housing) is compared before it refreshes: with the last reading, with what was saved for the toon (reputation, `CaerdonRefreshData`), or by the module that owns it with what it answered (the quest module).
- `CaerdonIntegrations.lua`: whether each third-party integration found the functions it hooks (the export's `[Integrations]` section).
- `CaerdonCounters.lua`: loaded first. Login milestones, loads asked of the client and full refreshes by trigger, always; time and memory per function while its profile is switched on, which the test addon does (the export's `[Counters]` section).
- `config/`: `Config.lua` (defaults, migrations, the main page, `/caerdon`, the one-time message dialog), `Icons.lua` and `Display.lua` (the two settings pages), `ConfigPanel.lua` (layout helpers), `LayoutEditor.lua` (`/caerdonlayout`).
- `features/DebugFrame.lua`: the Debug Frame and its **Copy Details** export (`/cdebug`). `CaerdonButtonGeometry.lua`: the export's button measurements.
- `tools/`: development scripts, not packaged. `static-checks.lua` with its allowlist `static-checks-allow.lua`; `test-results.lua` prints what the test addon saved in each client; `harness/` runs the addon's real item code under LuaJIT in a mocked client (`luajit tools/harness/run.lua`): scenarios against a hand-made game, and fixtures, which are a client's recorded answers replayed.
- `CaerdonWardrobe_Tests/`: the test addon, a second addon for development that runs in both clients and is not packaged (`/cwtest`): client contracts, verdict tests, snapshot and diff, timing, a journal of what was learned, bag states checked when an item shows one, a record per integration, a rotation through the installed bag addons (`/cwtest rotation`), a recorder of the client's answers behind one verdict for the harness (`/cwtest record`).

### Status order in `GetCaerdonStatus`

Each later step only replaces the statuses listed, so an upgrade keeps its icon, and a learnable look keeps its own against everything but a quest.

1. Old expansion and Quest-class items (early; the type branch may overwrite them). A Quest-class item whose known quests are all behind the toon (done, or never to be taken) gets no `quest` here, and neither does one whose remaining quests the player's options keep out (the range of levels, trivial quests; notes: Quest Value).
2. The branch for the item's type (equipment, consumable, recipe, pet, mount, toy, ...). A piece of equipment that would be `collected` and would gain an unknown look by an upgrade or at the Catalyst is `transform` here instead, so it is never `sellable` or `auction`; an upgrade keeps its arrow and a gear set's piece stays `collected` with the set's mark (notes: Looks After a Change).
   A book or a rune that teaches this toon a spell it does not know (no profession's recipe: it asks for no skill) is `own`, `lowSkill` below its level, by the tooltip's own lines (notes: What an Item Teaches).
3. Equippable junk becomes `sellable` (replaces empty). So does such a spent Quest-class item with no use, no slot and no equip effect (replaces empty, `oldexpansion`); one that a repeatable quest can still take ends as `quest` with `sellable` or `auction` as its small mark (notes: Quest Value).
4. Bags against the bag slots: `own` / `lowSkill` or `sellable` (replaces empty, `oldexpansion`).
   A recipe, book or rune it could learn and already has a copy of (bags, bank, mailbox, bought and not fetched) is `collected` on a copy it does not hold, and keeps its icon on the one it holds (notes: What an Item Teaches). The same holds for `send` in steps 5 and 7: a copy it does not hold has no mail icon once the toon has one for each toon that wants it.
5. A book or a rune this toon has no use for (another class's, or learned) that can be handed over: `send` when another toon of the realm said it can learn it, now or at a later level, and has no copy the ledger knows of (replaces `collected`; notes: What an Item Teaches).
6. Consumables for another class become `sellable` (replaces empty, `collected`).
7. Recipes this toon has no use for: `send` / `sellable` (replaces `collected`).
8. Outgrown food and drink become `sellable` (replaces empty, `collected`).
9. Ingredients this toon has no use for: `send` when another toon's recipes take it and vendors everywhere do not sell it, `sellable` when its own have outgrown it (replaces empty).
10. Quest value becomes `quest` (replaces empty, `collected`, `sellable`, `send`, `oldexpansion`, `transform` and every learnable status: `own`, `other`, their Plus forms, `otherNoLoot`, `lowSkill`; not an upgrade).
    An item that starts a quest the toon has neither done nor taken, with no other quest left for it, is `own` here instead, `lowSkill` while the quest or the item asks for a level the toon has not, with `quest` as the status's sixth value (`smallMark`); it replaces the same statuses and the quest icon the item's class gave (notes: Quest Value).
11. Auction value: `sellable` becomes `auction`; plain trade goods become `auctionGoods`, unless kept as an ingredient.
12. Bag-location overrides: `openable`, `locked`, `readable`, `refundable`, combine spells. `readable` leaves `quest` alone: that the copy can be read is then the status's sixth value (`smallMark`), drawn as the small mark on the quest icon. It leaves a starter's star alone too.

The result is cached by item link (plus `|B` when soulbound, `|c` for a crafted piece that lies in a slot, `|x` for a season's armor that lies in a slot and may go to the Catalyst, `|f` for a recipe or consumable that is not a copy the toon holds, `|q<quest>` for a copy in a bag slot the client says starts a quest, `|e<sets>` for a piece equipment sets hold, `|n<owned>` for stackable items, and `|s<source>` / `|l<level>` / `|k<suffix>` for a row whose window passed a source, an item level or a key's suffix) until `RefreshItems`. A piece of equipment's transmog info is cached with it and returned fifth. Step 12 is not part of what is cached: it belongs to one copy in its bag slot and is added after the lookup, on every call (`GetCopyStatus`; notes: Refresh).

## Rules

- **WoW Forever is not retail.** Its server rules differ (what a bag slot accepts, when an appearance is learned, armor proficiency). Do not write a rule from retail knowledge; get a Copy Details export that shows it.
- **Retail and Forever share one code base and TOC.** Check an API, event, enum value, global string or hooked Blizzard function against both flavors' source before relying on it, then confirm in each client. Text differs between them (retail "Warbound", Forever "Account bound"), so a fixture or expected value belongs to one flavor.
- **Feature detection, not flavor checks.** `CaerdonAPI:IsForeverClient()` is for reporting. `select(4, GetBuildInfo())` is `16001` on Forever, so a `>= 110000` gate is false there: use one only for features Forever really lacks (housing), never to pick an API path.
- **Legacy globals:** many undocumented ones still exist on Forever, but confirm each by finding a call in Blizzard's camelot-loaded Lua. Never call `GetSpecialization`, `GetSpecializationInfo` or `GetSpecializationInfoByID` directly; use the `CaerdonAPI` wrappers.
- **A look the toon can collect is `own`, whatever the piece asks for** (a level, a standing): selling the piece teaches it, in both clients. `lowSkill` is not for looks (notes: Transmog on Forever).
- **Investigating an item:** extend the Copy Details export instead of adding prints. Keep additions structured and readable.
- **No text is read off a tooltip frame.** A status comes from `C_TooltipInfo`; a line that should not be on a tooltip is kept off before the client adds it (`TooltipDataProcessor.AddLinePreCall`, as for an ensemble's "Already known"; notes: Ensembles), never found by its text and blanked.
- **A line the client writes from a format string is read back with `NS.FormatPattern`,** never with a pattern made by hand from that string or from its English text: the strings hold positional arguments, full-width punctuation and grammar escapes in other languages. A change to text that is read runs `scenarios/locale-text.lua`, which has every locale of both clients (notes: Text Read Off a Tooltip Line).
- **New item signals** go through the item's data mixin or a signal module with a `CaerdonItemMixin` entry point, never ad-hoc API calls in feature files.
- **An integration is removed only when its addon is confirmed gone from both clients.** That the other addon is not installed here, or that the integration's code looks unfinished, is no reason: check the other addon's own releases for retail and for Forever first (its TOC's `## Interface` lines). An unfinished one is finished or left as it is.
- **An integration declares its hook points and notes each one** (`Mixin.integration`, `self:NoteHookPoint(label, owner, key)` on the line before it attaches). That is how a user's export says the other addon changed (notes: Integration Report).
- **Never write into `options`.** It belongs to the caller and is usually shared between buttons. Per-button state goes in `buttonState` or on the overlay's regions.
- **A feature's `Refresh()` must re-run `UpdateButton`** for the buttons it decorated, and is never left empty: `RefreshItems` only wipes caches. A feature with none inherits the default, which asks again for every button the feature last asked for (`CaerdonWardrobe:AskAgain`; notes: Processing Pipeline). Write one only where a window has to be walked. A feature another addon registers after the start is never started: the core asks again for its buttons itself (notes: Refresh).
- **A feature asks for a window's buttons only while the window is on screen** (`IsVisible`, not `IsShown`: a host addon parks Blizzard's window under a hidden parent and leaves it shown), and only where the window asks again when it comes on screen; where it does not and the cost is measured, the button is owed a draw for when it is (`AskWhenOnScreen`; notes: Processing Pipeline). The default `Refresh()` owes every button that is not on screen.
- **A button's item has its data before `UpdateButton`**, so `customDataLoaded` is true. A window that has a link, an ID or an item of its own for a button hands it over with `self:Decorate(button, source, locationInfo, options)`, which waits and does not draw a row that was asked for again or cleared while its item loaded. Where the answer does more than ask for one button, the wait is `CaerdonWardrobe:WhenItemLoaded(button, item, callback)`; no feature waits for a button with `ContinueOnItemLoad` itself. The core's own asks and clears (a refresh, a retry, the queue) go through `AskAsCore` / `ClearAsCore`, which leave a window's wait its own (notes: Processing Pipeline).
- **A feature waits for a window's load-on-demand addon with `self:WhenAddOnLoaded(addon, method)`** in its `Init`, not with an `ADDON_LOADED` handler that compares names: another addon may have loaded it before the features begin (notes: Processing Pipeline).
- **What one window does with a status is declared on its feature** (`statusRules`, applied at each draw by `ApplyStatusRules` in `FeatureMixin.lua`), never a check of the feature's name in the core (notes: Processing Pipeline).
- **What a window shows of a draw is declared on its feature too** (`displayRules`: per rule `true`, `false` or the window's key among that rule's settings; laid over the core's answers by `GetDisplayInfoInternal`). A window whose rules depend on the place or the item has a declaration for each case and chooses in `GetDisplayRules`, which is handed the draw; a `GetDisplayInfo` function is only for what a declaration cannot say (the auction house's row parts, an arrow the host addon drew). A feature that draws another's content passes that feature's rules on. A changed or new declaration runs `scenarios/display-rules.lua` (notes: Processing Pipeline).
- **A draw path does not call `GetTransmogInfo()`.** It reads the table `GetCaerdonStatus` returns, which is the one the verdict was made from and is shared by every button of that cache entry (notes: Processing Pipeline).
- **A change to the drawing code is compared with the code from before, call by call:** `scenarios/draw-path.lua` writes down every widget call of `SetItemButtonStatus` and `SetItemButtonBindType` (notes: Offline Harness, Scenarios).
- **An item's table holds only its data.** Its methods come through a metatable, so do not copy an item or walk it with `pairs` for them (notes: Processing Pipeline).
- **One failure stays alone:** the core calls each feature's `Init`, `Refresh` and event handlers and draws each queued item through `Contained`, which hands an error to the game's error handler and carries on. A new loop over features or items does the same (notes: Processing Pipeline).
- **What comes is matched to what waits for it:** a verdict that is put off names what for (the status's third value), and the event that brings it asks only the buttons that wait for that (`CaerdonWardrobe:RetryWaitingFor(key)`). A handler that asks every waiting button, or refreshes everything, for an event that names one item is work for nothing and hides which waits are slow (notes: Processing Pipeline).
- **A verdict that depends on game state needs its own refresh:** the status cache is keyed by item link, so the module must call `RefreshItems` when that state changes. The signal modules show the pattern: compare a signature, refresh only on a change. An event that also comes when nothing changed gets a watch instead of a handler, and a refresh says why (`RefreshItems(reason, detail)`; notes: Refresh).
- **A refresh that says what changed keeps the rest** (`RefreshItems(reason, detail, changed)`, `"worn"` or `"collection"`): the equipment code keeps what the client said about sources when only the worn gear changed, the quest module its answers in both cases. A new input to either that follows from what is worn or learned means it may no longer be kept (the comment on each module's `InvalidateCaches`; notes: Refresh).
- **The counters wrap functions by name** (`Counters:Attach`). Renaming or splitting one of them means changing its line there; the export says "not found" for one it missed (notes: Counters).
- **Do not refresh on `TRANSMOG_SOURCE_COLLECTABILITY_UPDATE`:** the addon's own queries trigger it, which risks a loop.
- **Do not change `LoadSources`' `#waitingForItems == 0` check** or remove the once-guard in `ContinueWithCancelOnItemLoad` (notes: LoadSources).
- **Settings:** an option only where the choice is real. One block per icon on the Icons page; no per-window toggle by reflex; no on / off switches for a part in the layout editor (a box in an addon's callout there says whether the layout holds in that addon's window, which is the one kind). A new setting needs a default in `GetDefaultConfig`, a nil-migration in `config/Config.lua` and one option on a page. A setting that describes the toon and not the player's taste (which specs it plays) is kept per character instead (`CaerdonWardrobeCharacterConfig`, `perCharacter = true` on the option, a label that says so; notes: Settings); keep that list short, and no profiles.
- **Placement:** a window opts in to the standard icon size with `GetSlotStatusSize`, and on a slot smaller than a bag's to texts of the same proportion with `GetSlotScale` (`options.slotScale`), which is what lets the player's layout hold there: a small slot is not a reason to fit a layout by hand. Do not replace a hand-tuned value for a window that has not been measured, and do not judge a button's shape from its numbers alone.
- **Tests:** `luajit tools/harness/run.lua` runs the item code offline under LuaJIT in a mocked client; run it before calling a change to that code done. That checks logic, not the client; say which of the two a claim rests on. A fixture that comes out `stale` asks for a new recording, not for an edit of the fixture (notes: Offline Harness). What the test addon recorded was seen in a client: read it with `luajit tools/test-results.lua` after the author has reloaded. A change that should leave every icon as it was is proven by its snapshot diff (notes: Test Addon).
- **The test addon's code runs in the client's Lua 5.1:** no `pcall` or `xpcall` around code that waits (use `T.Protected`), and `%s` only for strings and numbers.
- **Static check:** `luajit tools/static-checks.lua` reports every name the addon or the test addon uses that one client or neither has, and every global written that is not on the allowlist. Run it before calling a change done and after a client patch. A new flavor-specific name needs an allowlist entry naming its guard, and a change to the names the addon uses needs `--emit-facts`, which also rewrites the list the recorder hooks (notes: Static Check).

## WoW Forever Essentials

A mainline-family client: retail 12.x UI architecture running classic-era content, supported from the same code base and TOC. Game type `camelot`, `WOW_PROJECT_ID` 18, `## Interface: 16001`.

- **Not loaded:** Blizzard_EncounterJournal, Blizzard_GarrisonUI, Blizzard_Housing*, Blizzard_ExpansionTrial. Blizzard TOCs gate with `AllowLoadGameType` (`mainline` includes camelot, `standard` is retail only); Forever overrides live in `Camelot/` folders.
- **No specializations.** One trait tree per class in three groups; `CaerdonAPI:GetTalentTrees()` / `GetPrimaryTalentTree()`. Where a feature goes by the spec being played, the tree with the most points stands in for it, and a gear set the player tied to a Pawn scale, or named as the spec or tree is, comes before either in both clients (notes: Upgrades). The feature is not finished until Forever has it.
- **Selling an item to a vendor teaches its appearance,** whatever the class. The transmog collect APIs do not reflect that.
- **Classic armor proficiency** (mail and plate at 40) is invisible to the transmog APIs. The tooltip's slot line is the authority for "can equip now": its `isValidItemType` field, which is false where the armor type is red (notes: Tooltip Lines in the Export).
- **Classic stats are "Equip:" lines:** spell power, attack power, crit and the like come as green "Equip:" lines of type `None`, built from the client's `TOOLTIP_ITEM_STAT_*` strings. A real effect is typed `ItemSpellTriggerOnEquip` (notes: Sellable Rules).
- **Classic ranged slot** (`INVSLOT_RANGED`, `C_PaperDollInfo.IsRangedSlotShown()` true) and no profession gear slots: tools are carried in the bags.
- **Bag slots:** four normal slots plus a reagent slot that also takes profession bags.
- **No realm name:** `GetRealmName()` is an empty text there. Anything saved by realm and toon is filed under `CaerdonAPI:GetRealmKey()` (the realm's name, or the server number in the toon's GUID), never under `GetRealmName()` itself (notes: WoW Forever Client).
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
| Text read off a tooltip line, other languages | Text Read Off a Tooltip Line |
| Appearances, `own` vs. `other`, selling teaches | Transmog on Forever |
| A look known from another item, the Plus statuses | Known Looks |
| A look a piece gains by an upgrade or at the Catalyst | Looks After a Change |
| Ensembles | Ensembles |
| Upgrade arrow, Pawn, equal item level, badge | Upgrades |
| A tier set's bonus gained or lost by wearing a piece | Set Bonuses |
| What is and is not `sellable` | Sellable Rules |
| A class's spell book, a rune, anything with a teaching line; who else could learn it, the ledger | What an Item Teaches |
| Tools, bags, recipes, food and drink | Profession Tools; Bags for the Bag Slots; Recipes This Toon Has No Use For; Outgrown Food and Drink |
| Trade goods a recipe takes, recipes recorded with their difficulty | Ingredients |
| Quest icon on non-quest items | Quest Value |
| Auction icon | Auction Value |
| Housing items (retail only) | Housing |
| Stale icons, refresh events | Refresh |
| Baganator, BetterBags | Bag Addon Integrations |
| An integration that stopped drawing, hook points | Integration Report |
| Skillet's recipe list | Skillet |
| World Quest Tab's list and pins | World Quest Tab |
| Quest rewards in the Dialogue UI addon | Dialogue UI |
| Daylight UI's vendor, bags, auction house, mailbox, quest rewards, loot rolls, profession window and comparison tooltip, its public API | Daylight UI |
| Icon size, clipping, measuring a window | Icon Size and Placement |
| Settings pages, layout settings | Settings |
| Layout editor | Layout Editor |
| Queue, retries, overlay | Processing Pipeline |
| Dressing room | Dressing Room |
| Item load callbacks | LoadSources |
