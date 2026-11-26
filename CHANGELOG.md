# What's new in Caerdon Wardrobe v6.0.1

Fixes for the loot window, and for a hunter's pet food on WoW Forever.

- **Loot window:** every row has its icon again. Since v6.0.0 a quest item showed none there, and a piece of gear got its star only after a pause.
- **WoW Forever, hunters:** with plenty of your pet's best food in the bags, a second kind of food is no longer kept beside it. A second kind is kept only while the best one is down to its last few pieces.
- **WoW Forever, hunters:** food that another of your toons' recipes take is not kept as your pet's second kind, so it keeps its mail icon in your bags as it has in the bank. Your pet's best food always stays its food.

# What was new in v6.0.0

A big update for both World of Warcraft (Retail) and WoW Forever. The icons are right in more places, and there are several new things to see in your bags.

## Upgrades

- **The arrow knows your loadouts.** A piece is compared with what you are wearing, with each gear set you have saved and with your other specs. A yellow arrow is an upgrade for what you are wearing on your spec's Pawn scale, a green one is a higher item level alone, and a red one is an upgrade for gear you are not wearing or for another spec.
- **The tooltip says what an upgrade is for, and by how much.**
- **Set bonuses.** The tooltip tells you when wearing a piece would gain or lose a tier set bonus, so an arrow never quietly costs you one.
- **Weapons are compared by the hands they take:** a two-hander against both pieces it would replace, a one-hander together with the best partner in your bags.
- **Gear sets can have a Pawn scale of their own,** and a set can be marked as PvP gear so that it is compared at PvP item levels. A set you named after one of your specs (or talent trees on WoW Forever) is matched to it by its name.
- **An upgrade you cannot wear yet** shows the grey gear in place of the arrow, and its tooltip says at which level it becomes one.
- **WoW Forever has upgrades too.** There are no specs there, so the talent tree with the most points decides which Pawn scale is yours.
- Where Pawn and Caerdon Wardrobe would say different things in a tooltip, you see one answer. An option brings Pawn's own notes back.

Everything above is set in the Upgrade block of the Icons page.

## Gear worth keeping for its next look (Retail)

- A piece whose look you already have is no longer marked for sale when it would get a look you are missing by being upgraded on its track or converted at the Catalyst. It gets a small mark that says which of the two to do.

## Quests

- **The quest icon goes away when the quest is behind you.** A quest item you have no more use for is marked as safe to sell.
- **Items for quests you have not picked up yet** now work with AllTheThings as well as QuestieDB, which brings them to Retail. You choose how far ahead to look and whether gray quests count. Gray quests are left out unless you switch them on (Icons page, "Also quests that have turned gray for this character"): at the level cap that is most older quests, so their items show no quest icon until you do.
- **An item that starts a quest** you have not taken gets the star with a small quest mark: use it.
- **Something a quest needs is never marked as a look to learn.** The quest icon comes first, so you do not sell or mail away what you have to hand in.
- A quest item you can read keeps its quest icon, with a small mark for the reading.
- The quest icon shows on auction house listings, with its own switch.
- The quest icon's setting is now followed in Sorted's bags and in the world quest list addons.

## Your other toons

- **A new mail icon** marks what this toon has no use for and another of your toons does: a recipe it can learn, an ingredient its recipes take, or a spell book or rune for its class. The tooltip names the toon.
- The mail icon stays away when that toon already has a copy in its bags, bank or mailbox, and from ingredients that vendors sell everywhere. Once you have bought or picked up one for every toon that wants it, the icon leaves the other copies too.
- **Spell books and runes** that teach this toon a spell it does not know get the star, or the grey gear until it has the level.
- **Ingredients your recipes have outgrown** are marked as safe to sell. Open each profession window once so the addon can note your recipes.

## Safe to sell

- WoW Forever: gear with classic stats such as spell power or attack power is no longer held back from the sell icon once you have its look.
- A piece you cannot wear yet is no longer kept just because its item level matches what you have on.
- WoW Forever: a hunter's food is kept by what the pet actually eats.

## Other addons

- **Skillet:** its recipe list shows the icon of what each recipe makes, as the game's own profession window does.
- **World Quest Tab** (Retail) is supported again: reward icons in its list and on its map pins.
- **Angrier World Quests:** the item level gain is no longer drawn over the reward's icon.

## Fixes

- A locked lockbox is shown as locked, not as something to open.
- An item taken from the mail, a vendor or a loot window gets its bag icon right away.
- Icons in BaudBag and Inventorian update after you learn a look or swap gear.
- BetterBags: every button is drawn when two of them show the same item.
- The combine icon is there after logging in, not only after a reload.
- A crafted piece you can still recraft is no longer marked for sale now and then.
- Housing: an item that teaches something you already know no longer gets a star.
- Changing spec or loot spec updates the icons.
- A recipe item is matched to its recipe where the two are worded differently.
- An ensemble's tooltip no longer has an empty row where the "Already known" line was hidden.
- WoW Forever: what the addon remembers about your toons is kept again now that the client no longer gives a realm name.
- A problem with one item or one supported addon no longer stops the icons everywhere else.

## Tidied up

- The tooltip switches sit with the icon they belong to on the Icons page.
- A change in the settings applies as soon as you click it.

Something looks wrong? Type `/cdebug`, point the debug frame at the item, press **Copy Details** and paste the result into an issue at https://github.com/Caerdon/CaerdonWardrobe/issues. Thank you!
