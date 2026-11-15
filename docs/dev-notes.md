# CaerdonWardrobe - Development Notes

Reference detail per area: the rule, why it is that way, and what has or has not been seen in game. Not loaded automatically; `CLAUDE.md` holds what every session needs and points here.

Keep entries short and factual. No session narration, quotes or test counts. "Offline" means run under LuaJIT with a mocked client, which checks logic and not the client. "Author" is the addon's author; a date is when something was decided or observed.

## WoW Forever Client

- **Identity:** game type `camelot` (alias `forever`), `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT` (18), `## Interface: 16001`. `CaerdonAPI:IsForeverClient()` / `GetClientFlavor()` are for reporting only.
- **Version gates:** `select(4, GetBuildInfo())` is `16001`, so `tocversion >= 110000` is false. Housing is correctly gated off this way (Blizzard_Housing* is `AllowLoadGameType: standard`).
- **TOC gating:** `## AllowLoadGameType` and per-file `[AllowLoadGameType camelot]`. `mainline` includes camelot, `standard` is retail only. Overrides live in `Camelot/` subfolders.
- **Not loaded:** Blizzard_EncounterJournal (standard / classic only), Blizzard_GarrisonUI, Blizzard_Housing*, Blizzard_ExpansionTrial. The EncounterJournal and Mission features wait for `ADDON_LOADED`, so they stay dormant.
- **Mail:** `InboxFrame:Update()` and `OpenMailFrame:UpdateButtonPositions()` replace the retail globals; `SendMailFrame_Update` is still global. `features/Mail.lua` hooks whichever exists.
- **Bank:** `CamelotBankPanelItemButtonMixin:Refresh()` calls through `BankPanelItemButtonMixin.Refresh(self)`, so the table hook still fires.
- **Events:** `UPDATE_EXPANSION_LEVEL` is undocumented and registered via `pcall`. All other registered events exist in Forever's event documentation.
- **Specializations:** none. `GetSpecialization`, `GetSpecializationInfo` and `GetSpecializationInfoByID` do not exist (only `C_SpecializationInfo.*`, `GetLootSpecialization`, `GetSpecializationInfoForSpecID`). Use `CaerdonAPI:GetPlayerSpecializationIndex()`, `GetSpecializationInfo(index, ...)`, `GetSpecializationInfoByID(specID)`, `GetLootSpecializationID()`; they return nil without a spec system.
- **Talent trees:** one trait tree per class in three groups. `CaerdonAPI:GetTalentTrees()` reads them as Blizzard's Camelot talent pane does: `C_SpecializationInfo.GetCombatConfigIDForSpecGroup(GetActiveSpecGroup())`, `C_Traits.GetConfigInfo(configID).treeIDs[1]`, `C_Traits.GetGroupDisplayInfoByTreeID` (names, order), `C_Traits.GetGroupCurrencyInfo` (`currencyInfos[1].spent`; a missing group is 0). `GetPrimaryTalentTree()` returns the leader, nil on a tie or with nothing spent. Retail has neither group function, which is the feature gate. Cached until `InvalidateTalentTrees()`; `CaerdonWardrobeMixin:OnTalentsChanged` (trait and talent events, coalesced over 0.5 s) refreshes only when the leading tree changed.
- **API coverage (Forever 1.60.1 docs):** every documented API the addon uses exists; `TransmogUseErrorType` values match retail. Undocumented calls that Blizzard's camelot-loaded code also uses (toy, heirloom, pet journal, black market, merchant / loot / quest link getters) are safe. `C_TradeSkillUI.GetAllRecipeIDs` and `GetRecipeFixedReagentItemLink` are not referenced in Forever's UI code, so they are guarded.
- **Ranged slot:** `GetInventorySlotsForType` in `types/EquipmentMixin.lua` sends `INVTYPE_RANGED` / `RANGEDRIGHT` / `THROWN` / `RELIC` to slot 18 when `C_PaperDollInfo.IsRangedSlotShown()`. Without it bows were compared against the melee weapon.
- **Professions:** every profession has one child skill line with the parent's name ("Mining" 186 > "Mining" 2946), and secondary professions cache no parent skill level, so `CaerdonProfessionData[realm][toon]["Cooking"]` can be a bare `{ childSkillLines = ... }`. `CaerdonRecipe:GetPlayerSkillInfo` checks the top-level entry and every same-named child and keeps the highest. `GetProfessions()` returns prim1, prim2, first aid, fishing, cooking. `select(7, GetProfessionInfo(index))` returns base skill lines (seen: Herbalism 182).
- **Recipe tooltips:** "Requires Cooking (40)" is a `UsageRequirement` line (`requirementType` Skill). A non-red line is the client's verdict that the rank is met and overrides the cached rank; a red line uses the cache to tell "rank too low" (`lowSkill`) from "no profession". Recipe items report a generic "Learning" spell, so the name-based `GetRecipe` lookup identifies the recipe.
- **Collections:** the wardrobe UI hides uncollected appearances and transmog is restricted to same-type items, but the `C_TransmogCollection` APIs are unchanged.

## Transmog on Forever

Selling an item to a vendor teaches its appearance ("added to your appearance collection"), with no equip or bind. The collect APIs do not model this, so three flags on `GetTransmogInfo()` cover it. All need both collect verdicts (`PlayerCanCollectSource`, `AccountCanCollectSource`) to be ready.

- **`validSourceNotCollectable`** (and `...KnownLook`): `isValidSourceForPlayer` true, no `useErrorType`, both collect verdicts false. Becomes `own` / `ownPlus`. Red tooltip text is not required: cloth on a hunter (Spellbinder Vest 2969) has this shape with a white tooltip, as does mail under level 40 (Soldier's Wristguards 6550) with a red one. It is `own`, not `lowSkill`, because selling teaches it at once (confirmed in game).
- **`proficiencySourceNotCollectable`** (and `...KnownLook`): `isValidSourceForPlayer` false, `useErrorType` 10, both collect verdicts false (Blazing Wand 5212 on a hunter). Becomes `other` / `otherPlus`: `own` is strictly for appearances the toon can transmog into (author decision). Retail answers "can collect" for such sources, so the flag does not fire there. Errors 7 / 8 / 9 are not covered. Not confirmed in game.
- **`noCollectionCategory`:** both flags are skipped when the item's own `sourceInfo.categoryID` is `Enum.TransmogCollectionType.None`. Arclight Spanner 6219: `C_TransmogCollection.GetItemInfo` is nil, the dress-up fallback still yields a source, and `CanItemTransmogAppearance` is false. Such a source teaches nothing (inferred, not tried in game). `needsItem` / `otherNeedsItem` still follow the collect APIs.
- **Unknown:** when `PlayerCanCollectSource` is ever true on Forever; it was false for every uncollected piece exported from one hunter.
- **Unconfirmed, on Forever and on retail:** completing a quest seems to teach the look of every reward choice, whichever one is taken; a class-specific exception may exist (author observation, no export). If it holds, a learnable icon on a choice is no reason to pick it, and the order for choices would be upgrade, then sell value.
- **Red tooltip text is authoritative for equippability.** `CaerdonItem` scans every tooltip line, both columns, for `RED_FONT_COLOR`. Armor proficiency red sits in the right column of the `EquipSlot` line. `bindingResult.unusableItem` forces `canEquipForPlayer = false` and drops `isUpgrade` unless the shortfall is level-based (`upgradeLowSkill`).

## Ensembles

Ensembles teach **sources**, not appearances. Check `sourceInfo.isCollected`; do not skip a source because the appearance is known from another one (difficulty variants are separate sources and count toward set completion).

- **`own`:** uncollected sources wearable by this toon. **`ownPlus`:** an ensemble for another class with wearable extras (cloak, cosmetics). **`other`:** nothing wearable, but learnable for the collection. **`otherNoLoot`:** every remaining source needs another class, race or faction.
- **`sourceInfo.useErrorType` is the only reliable discriminator:** 7 Class, 8 Race, 9 Faction are true restrictions; 10 ItemProficiency (armor type) is not. `PlayerCanCollectSource`, `AccountCanCollectSource`, `meetsTransmogPlayerCondition` and `isAnySourceValidForPlayer` answer the same for both kinds once the account has a toon of the required class.
- **Mixed:** `other` if any remaining source is only armor-type restricted; `otherNoLoot` only when all are truly restricted.
- **Vendor gray-out:** never fade `own`, `ownPlus`, `other`, `otherPlus`, `lowSkill`, `lowSkillPlus`, `otherNoLoot`.
- **Open question:** ensemble 241380 taught a Monk-only source (78758, `useErrorType` 7) to a Druid, so error 7 may only block equipping and `otherNoLoot` may be too strict. Test: ensemble 139167 (Paladin-only item 144275) on a level 45+ non-Paladin plate wearer.

## Upgrades

`CaerdonEquipmentMixin:GetTransmogInfo()` carries the upgrade verdict and its inputs.

- **`isUpgrade`:** Pawn's verdict, else the unique-upgrade heuristic, else `upgradeItemLevelDelta > 0` (unless unique-blocked). `pawnIdentifiedUpgrade` is true only for Pawn's own verdict (yellow arrow; green means item level).
- **`equalItemLevelEquipped`:** same item level as equipped and equippable. Such a collected item is not `sellable`; it shows the neutral balance icon (`Icon.SameLevelBehavior`) unless it is off-spec, a tabard / shirt, or in a gear set.
- **`identicalToEquipped`:** the exception to the line above. A tie is only worth keeping when the piece does something the equipped one does not, so a piece that matches every equipped piece it ties is a duplicate: no protection and no balance icon under any `SameLevelBehavior`, and it counts as redundant (its use or equip effect is one the toon already has). Two checks, both must pass (`IsIdenticalToTiedEquipped`):
  - `C_Item.GetItemStats` tables equal. The table has no weapon speed or damage range, no effects and no set bonus, so it cannot decide alone; when either item has no table the lines decide.
  - `C_TooltipInfo.GetHyperlink` lines equal as text, in order. Ignored: name, binding, sell price, item level, flavor text, usage requirements, blank lines and the durability line. Everything else counts, including the slot line's armor / weapon type and any line type not listed, so a doubt reads as "different".
  - An enchant on the equipped piece alone is skipped; one on the candidate counts. With two slots, a tie against a different piece in the other slot keeps the protection. Empty line lists (data not loaded) never match.
  - A different item level with the same stats needs no rule here: the upgrade verdict or `betterItemEquipped` already decides it.
  - **Export:** `identicalToEquipped` and `equippedLineComparison` (per slot: what matched, or the first difference). Confirmed in game for two plain cloaks with the same armor; the rest is offline, and what `GetItemStats` returns on Forever (armor, enchants) has not been recorded.
- **`canEquipForPlayer`:** Blizzard's collect logic plus the tooltip scan. **`upgradeMatchesSpec`:** off-spec upgrades keep the arrow, tinted red, when "mismatched spec" is on.
- **Gear set items** suppress the arrow; only the level gain text remains. **Tabards** never show as upgrades.
- **Legendaries** with a use or equip effect are never `sellable`.
- **Pawn vs. item level:** `betterItemEquipped` only overrides a Pawn upgrade when PVP scaling took part (`HasBetterOrEqualEquippedItem`'s second value). Otherwise Pawn's stat weights win.
- **`pawnPrefersEquipped`** blocks the item-level fallback when Pawn scores the equipped piece at least as high on every visible scale. `PawnShouldItemLinkHaveUpgradeArrowUnbudgeted` returns false for both "not better" and "cannot judge", so `PawnPrefersEquipped` compares scores itself (`PawnGetSingleValueFromItem`, the weaker of two slots, 0.5% threshold) and gives no verdict for trinkets, an empty slot, missing data or no visible scale. Equal at zero on every scale counts as "not better" (author decision; the cost is that gear a class's scales ignore never gets an item-level arrow). Only applies while `PawnCommon.ShowItemLevelUpgrades` is off (Pawn's default on classic-era clients, on by default on retail).
- **`pawnOffTreeUpgrade`:** without specializations Pawn shows one scale per talent tree and answers "an upgrade for any visible scale". When every scale the upgrade is for belongs to a tree other than `GetPrimaryTalentTree()`, the arrow stays but is drawn in the off-spec red (author decision), independent of `Icon.ShowMismatchedSpecUpgrades`. Pawn's scale list is the setting: hide a scale in Pawn and its arrows go. Nothing is ignored when no tree leads, the own tree's scale is hidden, or one scale is visible; custom scales count as the toon's own. Pawn's druid numbering is 1 Balance, 2 Feral (Damage), 3 Feral (Tank), 4 Restoration. Confirmed in game for a Beast Mastery hunter; the rest is offline.
- **Armor class guard:** the item-level fallback never fires for a lower armor class than the piece equipped (`IsLowerArmorClassThanEquipped`). Pawn may still flag it.
- **Upgrade badge:** an upgrade whose status became something else (a look to learn) keeps `bindingResult.upgradeStatus` (`"upgrade"` / `"upgradeLowSkill"`), taken after the red-text correction. `SetItemButtonStatus` then draws a small ring and arrow on the icon's corner (`UPGRADE_BADGE_SCALE` 65% of the icon, moved `UPGRADE_BADGE_OVERLAP` 40% in), at the corner taken from `icon:GetPoint(1)`. It follows the upgrade arrow's settings, has none of its own, and shows and hides with the icon through its `OnShow` / `OnHide` hooks. Where a window does not show the status' own icon, the item draws as a plain upgrade. Confirmed in game, including Baganator and auction rows.
- **Export:** `pawnComparison`, `pawnUpgradeScales`, `pawnScaleFilter`, `pawnOffTreeUpgrade` under `[Transmog (Caerdon Processed)]`; `Talent Trees` under `[Player]`.

## Sellable Rules

Equipment is `sellable` when it is `collected`, redundant or without use / equip effect / set, and not protected. Never sellable:

- **Fishing poles** (weapon subclass `Fishingpole`).
- **Profession tools:** a Weapon with a met skill requirement line (`bindingResult.skillRequirementMet`; armor with a profession requirement is judged normally), or anything `GetProfessionToolInfo()` names.
- **Equal item level** unless the piece is `identicalToEquipped` (see Upgrades), recraftable items, legendaries and cosmetics with an effect, tabards with a use, teleport items, artifacts.

Other sources of `sellable`:

- **Equippable junk** (`IsEquippableJunk`): Miscellaneous / Junk that goes in an equipment slot with no use, no equip effect, no appearance, and a vendor price. Built for the trophy fish (15 Pound Mud Snapper 6295). Keep it this narrow.
- **Consumables for another class** (`IsOtherClassConsumable`): a red `UsageRequirement` line of type `RaceClass` (`bindingResult.raceClassRestricted`). Needs a vendor price; account-bound and warbound-until-equip are skipped. Built for mage scrolls on a hunter. Not confirmed in game.
- Recipes, food and drink, bags: their own sections.

## Profession Tools

`CaerdonProfessionTools.lua` says which items are tools of a profession the toon has; `GetProfessionToolInfo()` returns nil or `{ isTool, professions, toolName, source, match }`. A tool is never `sellable` or `auctionGoods`; nothing else changes.

- **Known items** (`KNOWN_TOOLS`): Mining Pick, Skinning Knife, Blacksmith Hammer, Arclight Spanner, Gyromatic Micro-Adjustor. Gathering has no recipe that names its tool. Gated on `C_PaperDollInfo.IsRangedSlotShown()` as a stand-in for "tools are carried in the bags".
- **Recipe tools:** `RecordRecipeTools` in `types/RecipeMixin.lua` saves every `Enum.RecipeRequirementType.Totem` name from `C_TradeSkillUI.GetRecipeRequirements` into `CaerdonRecipeData[realm][toon].tools[professionName] = { skillLine, names }`, for the toon's own profession only. A dropped profession's entry stays and is ignored.
- **Matching:** a known item, a name equal to a tool name, or, for equippable items, a name containing a tool name of 8+ characters ("Keen Skinning Knife"). The last is a guess.
- **Refresh:** new tool names and a changed set of professions (`SKILL_LINES_CHANGED`) call `RefreshItems`.
- **Not covered:** stand-ins under an unrelated name (Finkle's Skinner). Unverified: that `GetRecipeRequirements` names tools by the item's name, and that Forever-only hammers and knives work as tools.
- **Export:** `[Profession Tools]`. **In game:** the author's miner / engineer no longer sees the coin on his tools; a Skinning Knife on a toon without Skinning correctly does.

## Bags for the Bag Slots

`CaerdonBagSlots.lua` holds a bag item against every bag slot it fits; `GetBagSlotInfo()` is nil for anything that is not a bag or quiver (fields are documented above `GetItemInfo`).

- **Verdicts:** `isUpgrade` (a slot it fits is empty, or it beats the bag in one) becomes `own`, or `lowSkill` with red tooltip text. `isSpare` (every slot it fits is filled and it beats none) becomes `sellable` when it has a vendor price. Neither when a comparison cannot be decided.
- **Slots are read, not assumed.** `ReadSlot` classifies the item that is really there.
- **Kinds and the slots they fit** (confirmed in game on Forever unless noted):
  - `bag` (Container / Bag): normal slots, containers 1 to `NUM_BAG_SLOTS`.
  - `reagent` (Container / Reagent): the reagent slot, container 5. Assumed not to fit a normal slot.
  - `profession` (any other Container subclass): normal slots and, on Forever, the reagent slot. Retail's reagent slot is believed not to take them, so it only counts where `IsRangedSlotShown()` is true or once one has been seen in it.
  - `quiver` (item class Quiver; quiver and ammo pouch): normal slots only.
- **Better than the bag in a slot (`Compare`):**
  - Same kind and subclass: more slots. Equal is a spare.
  - Ordinary bag vs. profession or reagent bag: at least as many slots, since it holds anything.
  - Reagent bag vs. profession bag: more slots.
  - Undecidable, so no verdict either way: reagent bag vs. a profession bag with as much room or more; profession bag vs. a reagent bag, another profession's bag, or a smaller ordinary bag. What a reagent bag holds compared with a profession bag is unknown.
  - Quivers are only compared with their own subclass; against any bag the pair is skipped.
- **An empty slot only counts when the toon has a use for the bag (`hasUse`):** a quiver needs a bow or crossbow equipped, an ammo pouch a gun (`ReadAmmoWeapons`); a profession bag needs a profession in `PROFESSION_BAG_USERS` (the one its subclass is named after plus the crafting professions that use the same materials; a soul bag needs a warlock). One of the same kind already equipped also counts.
- **Size of an unequipped bag:** no API; the tooltip's "6 Slot Bag" line is read through the `CONTAINER_SLOTS` format.
- **Refresh:** `BAG_UPDATE_DELAYED`, `BAG_CONTAINER_UPDATE` and `SKILL_LINES_CHANGED` compare a signature of the slots and professions.
- **Settings:** `Icon.ShowBagUpgrades`, `Icon.ShowSpareBags`. **Export:** `[Bag Slots]`, printed for every item.
- **In game:** seen working on Forever (2026-11-14). Not individually confirmed: quivers, the retail gate, a profession bag on a toon without the profession.

## Recipes This Toon Has No Use For

`GetUnneededRecipeStatus()` replaces `collected` on a Recipe the toon knows or cannot learn.

- **`other` / `otherPlus`:** the recipe can be handed over (not soulbound, not bind on pickup) and another toon on the realm has the profession without the recipe in its recorded list. Plus when some toon already knows it. No vendor price needed.
- **`sellable`:** this toon knows it and nobody else wants it. Needs a vendor price; never for account-bound or warbound-until-equip.
- **Left on `collected`:** a known recipe when another toon has the profession but its recipes were never recorded.
- **"Known" for `sellable`** is `bindingResult.alreadyKnown` (the client's tooltip line) only. The name-based `recipeInfo.learned` cannot tell recipe ranks that share a name apart.
- **Data:** `GetRecipeOtherToonInfo()` wraps `CaerdonRecipe:GetOtherToonRecipeInfo(item)`, which returns `{ professionName, recipeName, knownByPlayer, toons, missing, unknown }`. Saved variables: `CaerdonProfessionData[realm][toon]` (ranks) and `CaerdonRecipeData[realm][toon]` with `knownRecipes` and `scannedProfessions`.
- **Recording (`GatherRecipes`):** only the toon's own profession (not linked, guild or NPC). `scannedProfessions[name]` is set only when the list is complete: `GetAllRecipeIDs` exists, or the `GetFilteredRecipeIDs` fallback ran with default filters and no search. Older data has no `scannedProfessions`, so other toons start as `unknown` until they open each profession once.
- **Tooltip (`TooltipMixin:AddRecipeLearners`):** green "Could be learned by: ..." for `missing` toons; gray "Recipes not recorded yet ..." only when the tooltip says "Already known". Wrapped in `xpcall`, because an error would leave `tooltip.caerdonProcessing` set.
- **Settings:** `Icon.ShowRecipesForOtherToons`, `Tooltip.ShowRecipeLearners` (a missing `Tooltip` section reads as on). The icon goes through `otherIcon`, so the per-window toggles apply.
- **Not modelled:** faction, the other toon's rank, other realms, deleted toons.
- **In game:** not seen. Export: `[Recipe]`.

## Outgrown Food and Drink

`CaerdonFoodDrink.lua` marks food or drink `sellable` when the toon carries a better one of the same kind it can use now; `GetFoodDrinkInfo()` is nil for anything else.

- **Compared with what is carried (bags only),** so the last stack is never marked.
- **Candidates:** Consumable / Food & Drink (subclass 5). The gate matters: a healing potion would otherwise read as food.
- **Food vs. drink:** no API; the tooltip line with a number and the localized `HEALTH` / `MANA` word decides (`both` is left alone). The first number is the amount. More numbers than "amount, duration" means buff food, which only competes with other buff food. The trailing cooldown note and `|4` plural escapes are stripped before counting.
- **Better:** higher required level, or the same level and a larger amount.
- **Never marked:** crafting reagents, items not usable yet, anything with quest value.
- **Hunters:** food must also be more than 20 item levels below the toon (`HUNTER_FOOD_LEVEL_GAP`), since a pet eats low food. Unverified on Forever.
- **Setting:** `Icon.ShowOutdatedFood`. **Export:** `[Food and Drink]`. **In game:** one buff food classified correctly; an "outdated" verdict is offline only.

## Quest Value

`CaerdonQuestItems.lua` gives the `quest` status to items of any class that an unfinished quest takes; `GetQuestItemInfo()` returns nil or `{ hasQuestValue, isActive, isUpcoming, quests }`.

- **No client API maps an item to a quest.** `C_QuestLog.GetQuestObjectives` has no item ID.
- **Quest log** (always on): item objectives matched by item **name**, parsed for both "Name: 0/1" and "0/1 Name" (which Forever uses is unverified). Retried on `QUEST_LOG_UPDATE` until names arrive. Quests in the log always count, finished objectives included.
- **QuestieDB** (`LibQuestieDB`, optional, contract 2+): quests not accepted yet. Its `Item.relatedQuests` holds about 13% of the pairs, so the module builds its own index from `objectives[3]`, `objectives[6]`, `requiredSourceItems` and `startedBy[3]`, in a coroutine at 3 ms a frame.
- **QuestieDB data shape:** baked into the TOC as base64 CBOR (grep finds nothing; use `LibQuestieDB.Quest.Get(id, "field")`). `objectives` is sparse, race masks exceed 2^32 (use arithmetic, not `bit.band`), and a bare classic faction mask (77 / 178) is compared with the toon's faction.
- **Upcoming quests (`UpcomingBlocker`):** not completed or hidden by Questie, not a holiday sort, right race and class, not repeatable, profession learned, no exclusive / later-chain quest done, takeable within `UPCOMING_LEVEL_WINDOW` (5) levels, not trivial, and an item-started quest needs that item. Without the level and trivial rules a level 23 toon gets the icon on about 400 items instead of 70.
- **Refresh:** `QUEST_ACCEPTED`, `QUEST_REMOVED`, `QUEST_TURNED_IN`, `PLAYER_LEVEL_UP`, 0.5 s later.
- **Settings:** `Icon.ShowQuestItems` (every window), `Icon.ShowUpcomingQuestItems`. **Export:** `[Quest Value]`.
- **In game:** one drink showed the icon in bags and at the BetterBags vendor; the rest is offline. Unverified: the objective text layout and the index build time.
- **Parked idea:** status icons on Questie's map pins. QuestieDB has no item rewards, and Questie has no public hook for pins.

## Auction Value

`CaerdonAuctionValue.lua`; `GetAuctionValueInfo()` always returns the full breakdown.

- **Statuses:** `auction` replaces `sellable`; `auctionGoods` marks trade goods with no status. Soulbound, bind-on-pickup, account-bound and quest items are never candidates.
- **Rule:** `profit = quantity * (price * 0.95 - vendorPrice) - deposit * depositRisk`; `required = clamp(vendorValue * margin, floor, 1g)`. Floor: `Icon.AuctionMinProfit`, `"auto"` (25c per level, minimum 1s) or copper as a string.
- **Rule sets by max stack size:** single item `depositRisk = 2`, `margin = 1`; stackable `depositRisk = 1`, `margin = 0.25`, and quantity is everything owned including the bank. `BAG_UPDATE_DELAYED` re-judges stackables and refreshes only when a verdict flips.
- **Price:** Auctionator's public API (`GetAuctionPriceByItemLink`, `GetAuctionAgeByItemLink`, `RegisterForDBUpdate`); older than 7 days is ignored. No sales data exists, so the price used is the lower of the last seen price and the 14-day median daily low (3+ days; from internal `Auctionator.Database:GetPriceHistory`, pcall'd).
- **Forever price keys:** gear below item level 168 is keyed by item ID alone, so random suffixes share one price.
- **Deposit:** unknown formula; starts at the larger of 1s or 15% of vendor price. `features/Auction.lua` records a sample when an item goes into the sell slot (`CaerdonAuctionData`).
- **Icon:** only in bags and bank (`displayInfo.auctionIcon`); elsewhere `auction` draws as `sellable` and `auctionGoods` draws nothing. `Auctioneer` atlas, else the gold coin.
- **Settings:** `Icon.ShowAuctionValue`, `Icon.AuctionMinProfit`. **Export:** `[Auction Value]`. **In game:** untested.

## Refresh

- `RefreshItems` (cache wipe, generation bump, debounced feature refresh) runs on `TRANSMOG_COLLECTION_UPDATED`, `TRANSMOG_COLLECTION_SOURCE_ADDED`, `..._SOURCE_REMOVED`, `TRANSMOG_COSMETIC_COLLECTION_SOURCE_ADDED`, and on equipment, equipment set and expansion changes.
- The export's `[Transmog Collection Events]` section lists the last 25 such events with the refresh generation. Use it for "the appearance was learned but the icon did not change".
- A no-op `Refresh()` leaves the stale icon while the Debug Frame shows the right status. Still empty, untested: BaudBag, Inventorian, CargBags, Sorted.

## Bag Addon Integrations

- **BetterBags** only sends `item/Updated` when a button's draw inputs change, so the integration tracks its buttons (`trackedBagItems`, weak keys, dropped on `item/Clearing`) and `Refresh()` re-runs them, skipping slots with no item.
- **BetterBags vendor** (`next/vendor.lua`): BetterBags hides Blizzard's `MerchantFrame`, so the `BetterBagsVendor` feature decorates BetterBags' cards. Each button's `SetBuy` / `SetBuyback` / `SetRepair` / `Release` is wrapped (pcall'd). `GetStatusRuleName()` returns `"Merchant"` so the merchant exceptions apply; any feature that redraws another feature's content should do the same. Buy tab confirmed in game; buyback is offline only.
- **BetterBags guild bank** (`next/guildbank.lua`, `next/guildbutton.lua`): Blizzard's `GuildBankFrame` stays hidden while it is open, so the `BetterBagsGuildBank` feature decorates BetterBags' buttons, with the GuildBank rules and display settings. BetterBags sends `guild/Updated` after every draw, for an item and for a free slot; a released button sends nothing and is hidden. The button's `tab` and `data.slotid` are the item's real tab and slot, also in the view of all tabs, so the link and the tooltip are read the way the GuildBank feature reads them. Icons confirmed in game (retail); the refresh path and a late-loading item are offline only.
- **Baganator places, this addon sizes.** Three corner widgets (`caerdon_wardrobe_status`, `..._binding`, `..._level_gain`) are the overlay's own regions, which Baganator re-parents, anchors and shows.
  - `options.hostPlacesParts = true`: the drawing code only fills and sizes the parts; it never anchors, shows or hides them.
  - `onUpdate` answers true, false, or nil for "not known yet". `BaganatorMixin:Ask` requests one draw per item and answers nil until `OnButtonDrawn` has the result (`CaerdonWardrobe:GetDrawnParts`). An item not drawn within `PENDING_LIMIT` (3 s) is answered false; a later draw calls `RequestItemButtonsRefresh`.
  - `feature:OnButtonDrawn(button, item, locationInfo, options)` is an optional hook called after every draw.
  - The upgrade arrow is not hidden for Baganator's own Pawn widget; both may show.
  - `SetItemButtonMogStatusFilter` is skipped for host-placed parts: the icon is hidden at that moment and would be left at alpha 0.
  - Confirmed in game: icon, level gain and binding text following their corners and the layout sizes. Unverified: a widget removed from every corner, the first bag open while answers are pending.

## Dialogue UI

`external/DialogueUI/Core.DialogueUI.lua`. Dialogue UI shows a quest at an NPC in its own window (`DUIQuestFrame`) in place of Blizzard's quest frame; the quest log and the map's quest details stay with the QuestLog feature.

- **Hooks:** `hooksecurefunc` on the global `DUIDialogItemButtonMixin`, for `SetItem` (every item draw) and `OnRelease` (back to the pool). The button template copies the mixin when a button is created, and the first button is created for the first quest shown, so the table hook reaches all of them. That needs Dialogue UI loaded first: it is in `OptionalDeps`.
- **What a button shows** is in Dialogue UI's own fields: `objectType` ("item", "currency", "spell", ...), `type` ("reward", "choice", "required") and `index`. The link is `GetQuestItemLink(type, index)`, the tooltip `C_TooltipInfo.GetQuestItem`.
- **Drawn:** reward and choice items. Not drawn: required items (handed in, not received) and currencies (only retail renown currencies have a status, and that path is unverified).
- **Tracking (`trackedButtons`):** what was last sent to the core per button: the link, plus whether Dialogue UI's own upgrade arrow was on the button. Dialogue UI sets a button again every 0.05 s while it waits for the item's name, so an unchanged draw is skipped; `Refresh()` forgets the links and re-runs every tracked button. A released button also loses its button state (`ClearButtonState`), so a request still on its way for it is dropped instead of drawn on a pooled button.
- **Display rules** are the QuestLog feature's (`GetDisplayInfo` is passed on), so "Quest rewards" on the Icons page covers both.
- **Placement (author decision, fixed layout):** Dialogue UI has a marker of its own for three corners of the icon: its upgrade arrow at the bottom left, the highest sell price coin at the top left (its option, off by default), and a red "!" at the top right for an item the toon cannot use (part of its `ItemOverlay` texture, no option, about 15 px, centered 6.8 / 7 px in from the top right corner of `AreaDefinitionItemBorder`). The overlay sits on that 36 px frame and the icon goes exactly over the "!" (`overrideStatusPosition` TOPRIGHT, `ALERT_INSET_X` / `_Y`), for every status: an icon only shows on an unusable item when there is still something to learn, which says more than "cannot use", and two markers side by side read as a disagreement. Size is `GetSlotStatusSize`; the ring of an important icon covers the "!", a minor icon (0.8 of it) may leave a rim. Text is fixed at the bottom, the level gain at the bottom right. The player's layout does not apply (`GetLayoutNote` says so in the layout editor).
- **One upgrade arrow (author decision):** where Dialogue UI has put its arrow on a button (`button:DoesButtonHaveMarker("upgrade")`; its "Evaluate Item Rewards" option, Pawn's verdict where Pawn is installed), `GetDisplayInfo` switches `upgradeIcon` and `levelGain` off, so this addon draws no arrow, no badge and no level gain there. Any other icon stays. The arrow can arrive 0.33 s after the item, so `ShowUpgradeIcon` is hooked too and draws the button again. An upgrade only this addon sees keeps its arrow and gain. `displayInfo.levelGain` exists for this; no other feature sets it.
- **Light background:** parchment shows beside the icon, so the buttons pass `roundStatusIcon` (see Icon Size and Placement).
- **Planned sell icon:** a sell icon on the best paying choice would mean what Dialogue UI's coin means, so it has to yield to the coin the way the arrow does. The coin sets no marker on the button; its frame would have to be found among the button's children.
- **No setting (author decision, open):** a Dialogue UI switch is only added if something still shows twice with this layout.
- **Debug keybind:** the button carries `caerdonDebugItemLink`; Dialogue UI's own tooltip is not one `GetHoveredItemContext` knows.
- **Tooltip line:** only with Dialogue UI's "Use Blizzard Tooltip" on; its own tooltip gets none.
- **Not covered:** the reward popup after a turn-in (`QuestFlyout`) and the looted quest item popup.
- **In game:** confirmed for reward choices: the icons, the circle clip and the upgrade arrow standing down. Not seen yet: the fixed layout over the "!", the level gain standing down, text on a reward, a minor icon over the "!".

## Icon Size and Placement

- **Reference look (author decision):** the default Blizzard slot. Important icon 20/37 of the short side of the frame it sits on, minor icon 0.8 of that, center a fifth of the icon's size in from the corner. `GetSlotStatusSize(width, height, noMaximum)` returns it, clamped to 13..24 px. Bag addons whose slot size the player sets pass `noMaximum`.
- **Windows opt in** by passing `statusProminentSize`; the core does not apply the rule by itself. Moved: BetterBags, quest rewards, Dialogue UI's reward buttons, Auctionator, dressing room outfit rows and set buttons, the item conversion output slot, the dungeon journal's search preview. Already at the value: the auction sell slot, crafting order browse rows. Deliberately not moved: the round output button of the profession window and of the crafting order form (fixed 20 px), Narcissus' round dressing room slots, world quest pins and the dungeon journal's lists and suggested reward (below).
- **Not measured, so still on their old values:** loot rolls, and what needs retail content: the dungeon journal's item sets (the tab was disabled in 12.1.5), mission rewards (covenant table, landing page report), Great Vault, Black Market (rows, hot deal). They follow the player's layout; the mission inset was made for the top left corner. Blizzard's guild bank is a 37 px slot with no options of its own, so it is the reference look; only its room has not been measured (BetterBags hides that window).
- **Measured (retail 12.1.5, default icon layout):**
  - World quest pin: a 20 px button whose art (`NormalTexture`) is a 32 px circle around it. The 15 px icon, 10 px in, lies inside the circle. The slot look would put the icon's center outside it, so the inset stays.
  - Dungeon journal loot row: a 42 px icon 2 px in from the list's clipping edge. The 8 / 7 inset lets a 20 px icon hang out by exactly those 2 px, and on a right-hand anchor keeps it off the item's name; the slot look would hang 6.8 px. The rows pass `keepInsideWhenClipped` for an icon the player has made bigger: at 100% the icon stays where it was (seen in game), the move inside has not been seen.
  - Dungeon journal search result row: a 36 x 35 px icon with 11 px of room, so the slot look would fit. It shares the loot rows' inset so both lists of the journal look alike (open: author's call).
  - Dungeon journal search preview: a 19 x 18 px icon, nothing clipping it. It had 13 px at 2 / 2 and now gets the slot look, which is the same size 0.6 px further in.
  - Dungeon journal suggested reward: a 30 px icon in a ring (`adventureguide-rewardring`), no mask reported, taken as round. The 8 / 7 inset keeps the 20 px icon's center on it.
  - Dressing room set button: a 24 px icon in a 32 px row with 16 px of room. It had 13 px at 1 / 1 and now gets the slot look, the same size 1.6 px further in.
  - Crafting order form output: 47 px with a circle mask, the profession window's output button. Left on the 20 px default like that one.
  - Item conversion output: a 48 px square slot, unmasked, nothing clipping it. It had the 20 px default and now gets 24.
  - Crafting order browse row: 20 px tall, 13 px icon anchored LEFT hanging 3.5 px into 5 px of room.
- **Measured (Forever, button units, important / minor):** Blizzard bags, bank, vendor, mail and loot are 37 px slots with a 20 / 16 px icon that hangs 6 / 4.8 px outside the corner. Auction and profession rows are 20 px tall with a 13 px icon and no icon region. Every slot window had at least 10 px of room around it; only auction rows have none.
- **Clip-aware placement (`options.keepInsideWhenClipped`; BetterBags, Auctionator, dungeon journal lists):** `RunClipPass` (0.1 s after the draw) finds the nearest clipping parent and, when its room on the anchor's side is less than the overhang, re-places every icon in that frame inside the corner at `CLIP_INSIDE_SCALE` (0.8). The answer is per clipping frame and looked up on every draw, because pooled buttons move between grids. Only horizontal room decides. The full size is kept on the icon (`caerdonBaseSize`) so it never shrinks twice. Confirmed in game for BetterBags' two designs.
- **Button geometry recorder (`CaerdonButtonGeometry.lua`):** with **Enable debug** on, `ProcessItem` notes every button it draws and one per window and option set is measured 0.2 s later (up to 6 shapes per window, session-wide; a button whose width follows its text makes a shape per width). A button with no layout is looked at again three times, a second apart, and the export then says why a shape was never measured. The export's `[Button Geometry]` section prints the player's layout (and whether it is the default: it is part of every number in a window that is not hand-fitted), then per shape options, size, what the overlay sits on, masks, the icon's size and overhang, text, stack count reach, and the nearest clipping parent with its room. `/cdebug geometry` shows only that section.
- **Ring icons on a light background (`options.roundStatusIcon`; Dialogue UI):** the store's category icons (`SetRingIcon`: star, "?", bag, key, ...) are a ring in the middle half of a 64 px texture with a dark shadow around it. The crop to the ring's square keeps the shadow in the corners: lost on a dark slot, a square that turns with the animation on parchment. The option clips the icon to the ring (`TempPortraitAlphaMask` on `mogStatus`, `RING_ICON_CLIP` = 0.9 of its size; the ring measures 0.88, and `SetStatusIconPosition` sizes the mask). No rim of shadow may be left: it is a drop shadow, heavier below, so a rim swings around as the icon turns. Opt-in because the mask's fit is only seen in game and Baganator re-parents the icon. Blizzard's quest frame is parchment too and has not been looked at.
- **Rectangles are not shapes.** The round profession button read as a 47 px slot. A mask does not mean round either: the two masks of `ItemButtonTemplate.xml` are named in the export (`TempPortraitAlphaMask` is the circle, `common-iconmask` every standard slot).
- The copy dialog is a child of the Debug Frame, so anything that shows it opens the Debug Frame first. Its edit box must not use `SetSpacing`; that broke the selection highlight.

## Settings

Two sub-pages under "Caerdon Wardrobe": **Icons** (`config/Icons.lua`) and **Display** (`config/Display.lua`), built with the helpers in `config/ConfigPanel.lua`.

- **Icons page:** one block per icon: the real texture, what it means, where it shows, then its rules. Everything not about an icon (corner, animation, text, vendor gray-out, tooltip line, debug) is on Display.
- **Learnable by this toon (`ownIcon`):** toggles only for bags and bank, guild bank, vendor and auction house (`Icon.ShowLearnable.*`). Every other window always shows it.
- **Learning for another toon (`otherIcon`):** one key per window in `Icon.ShowLearnableByOther`, read with `~= false`. World map, missions, Great Vault and item conversion have no option. Windows a client does not have are left out (`IsWindowAddOnAvailable`, with `Blizzard_GuildBankUI` as a canary).
- **Quest icon:** `Icon.ShowQuestItems` is one switch for every window.
- **Helpers:** `AddTitle`, `AddIconHeader`, `AddSection`, `AddLabel`, `AddCheckbox`, `AddCheckboxGrid`, `AddAllNoneButtons`, `AddDropdown`, `AddButton`, `FinishLayout`. Widths are fixed pixels (the canvas is about 640 wide). An option is `{ key, text, tooltip, configSection, configSubsection, configValue }`; `key` becomes the global `CaerdonWardrobe<key>` and must be unique across both pages. `dependsOn` grays a control out.
- **Values** are resolved from `CaerdonWardrobeConfig` on every read and write: the table is replaced on a version bump, a missing section is created on write, nil reads as the default. Pages set `frame.OnRefresh`, which the settings window calls on every display; a page's first display is not an `OnShow`.
- **Main page** (`config/Config.lua`, `Config.xml`): a short description and the support box, no options. The box sizes itself from its text (`FitCard`), because the sentence wraps with the page's width.
- **`/caerdon`** (`NS:OpenSettings`) opens the main page, as does the dialog's button (author decision). It does nothing in combat.
- **Category ID:** the main category keeps the numeric ID it was created with and is kept in `NS.SettingsCategory`, which the sub-pages register under. Do not set `category.ID` to the addon's name (the old way to make `Settings.GetCategory(name)` work): `Settings.OpenToCategory` hands the ID to `C_SettingsUtil.OpenSettingsPanel`, which raises an error for anything but a number (seen on Forever).
- **Dialog text:** a slash command at the end of a line is wrapped after the slash (seen on Forever), so the footer starts with it.
- **One-time message dialog** (`MESSAGES` in `config/Config.lua`): a `StaticPopup` with **Open Settings** (`NS:OpenSettings`) and **Close**. `CaerdonWardrobeConfig.MessageSeen` is the number of the last entry shown.
  - Settings saved before the field existed read as 0 and get the latest entry. A fresh install starts at the latest number and gets the welcome text; settings reset by a `Version` bump get the reset text.
  - Only the latest entry is shown, once per account. It comes up a few seconds after login, waits for the end of combat (the button cannot open the settings during it), and counts as seen once it is on screen. Add an entry at the end and never renumber.
  - A dialog interrupts, so add an entry only when players will see different icons or need to revisit their settings (author decision): a sentence or two, not release notes.
- **In game:** the pages were built against mocked frames; real text widths and wrapping are unverified. The main page's box and the dialog (its look, its timing after login) are offline only.

### Layout settings

Where the icon, the binding text, a gear set's name and the level gain sit, and how big they are.

- **Keys:** `Icon.Position / Scale / OffsetX / OffsetY`; `Binding.*`; `Binding.GearSet.*`; `Icon.UpgradeDelta.*`. Positions are the nine anchor names, scales are percentages, offsets a nudge right / up in pixels.
- **Relative to the window's own values:** size is a factor on `statusProminentSize` / `bindingScale`, the nudge is added to the window's inset. `GetStatusBaseSize(options)` is the one place the icon size comes from.
- **Hand-fitted windows** (`overrideStatusPosition` / `overrideBindingPosition`, or `fixedLayout = true`) get no size factor and no nudge. `fixedLayout` rows still follow the player's anchor.
- **Inset** only applies along an axis where the anchor is on an edge.
- **Scaled text:** `SetPoint` offsets of a region with `SetScale` are in its own units, so default spacing is divided by the player's scale.
- **Text and the level gain on one row (author decision):** a part goes where the player puts it and the gain never moves. Text that would run into the gain moves away by the gain's height, as it does for a stack count (`bindingTextMovedFor` says which). The gain's inset is `LEVEL_GAIN_INSET` (4 px).
- **Samples measure text at normal scale** (`options.sample`), because a string's width in its own units depends on the scale it is drawn at.
- **Defaults reproduce the previous look.** The binding text's default position stays Bottom (author decision).

## Layout Editor

`config/LayoutEditor.lua` (`CaerdonWardrobeLayoutEditor`, `/caerdonlayout`), opened from the Display page.

- **The examples are real** `ItemButton`s decorated by the drawing code with a made-up status (item: Hearthstone 6948), so they cannot drift from it. The large slot is a 37 px slot in a frame with `SetScale(4)`.
- **The editor mirrors the settings (author decision):** a part switched off everywhere is not drawn and has no button; an example only about such a part is left out (`EnabledParts()`, `TEMPLATES[...].needs`). Parts are switched on and off on the Icons page, never in the editor.
- **A gear set's name is a part of its own** with a full layout, independent of the binding text's.
- **Controls:** pick a part, nine anchor squares, a size stepper (5% steps, 50 to 300), a one-pixel nudge cross (up to 40), "Reset this part", "Reset everything", "Undo changes" (back to the snapshot taken on open).
- **Changes are written live.** Done keeps. Any other close with changes shows `CAERDON_LAYOUT_KEEP_CHANGES` (Keep, Discard, Keep editing); only a click on Discard restores the snapshot.
- **Samples cut to "B...":** a slot drawn while its page is hidden has no width yet, so `RedrawSamples` queues one more redraw 0.05 s later.
- **Addons that place things themselves:** a feature may define `GetLayoutNote()` returning a sentence that starts with the addon's name and a colon, plus an optional button. They show as a callout at the top of the editor; a note leads with what does not work there. Baganator's button opens its settings on the Icons tab (`OpenBaganatorIconSettings`: its `ShowCustomise` event toggles the window and always selects Theme, so the tab is set on the dialog itself).
- **Not built:** samples on the player's real windows; a stand-in for the player's own bag addon's slot.
- **In game:** the callout and Baganator's button are confirmed; the window's overall layout was built against mocked frames.

## Processing Pipeline

- `UpdateButton()` queues items into `waitingToProcess` by location key. `ProcessItem_Coroutine` (via `OnUpdate` every 50 ms) moves them to `processQueue`, which is reset at coroutine start.
- Items where `IsItemDataCached()` is false (it needs `IsItemCached()` and `customDataLoaded`) take a `ContinuableContainer` path, whose callbacks route back through `waitingToProcess`.
- **Not-ready retries:** when the tooltip still reads "Retrieving item information", `ProcessItem` stashes the request in `pendingTooltipRetries` and one 1 s timer re-runs them. The limit (`NOT_READY_MAX_RETRIES`, 10) is counted per button in `buttonState`. The timer only retries while the button still has the same location key and item ID. `GetRequestKey` builds the key for both paths.
- **`GetDisplayInfo` gets the host's button** in both draws (status icon and binding text), for a feature whose answer depends on what the host addon has put on it.
- **Overlay:** `EnsureCaerdonButton()` creates a child frame with `SetAllPoints`, holding `mogStatus` textures, `bindsOnText` and `upgradeDeltaText`. `buttonState` has weak keys.
- **Binding text:** with `bindingScale < 1` the font string width is divided by the scale; scale is reset to 1 before `GetStringWidth()`.

## Dressing Room

- `TryHookDressUp()` installs hooks in independent groups, because the globals load from different addons (`DressUpFrameTransmogSetButtonMixin`, `DressUpFrame`, `DressUpOutfitDetailsSlotMixin`); `ADDON_LOADED` retries until all are in. `hooksecurefunc` on a mixin table works for ScrollBox buttons, since `Mixin()` copies the hooked function.
- Items in the SetSelectionPanel are Equipment. `UpdateSetSelectionButton` sets `extraData.appearanceSourceID` from `elementData.itemModifiedAppearanceID`.

## LoadSources

`waitingForItems` is keyed by item ID, so `#waitingForItems == 0` is always true and `callbackFunction()` fires immediately; real completion is handled by `ProcessTheItem` / `FailTheItem` with `not next(waitingForItems)`.

- **Leave it.** Switching to `not next(...)` makes `LoadSources` block the whole `ContinuableContainer`, and every ensemble in the batch then shows as unlearnable.
- **Consequence:** completion is reported twice, so `CaerdonItemMixin:ContinueWithCancelOnItemLoad` wraps its callback to fire once. Blizzard's `ContinuableContainer` crashes on a late duplicate (`bad argument #1 to 'ipairs'`), which surfaced on a fresh Forever install. `ContinueOnItemLoad` is deliberately unguarded: features rely on the re-run.
