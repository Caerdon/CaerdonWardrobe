-- The verdict tests themselves. Each expectation is written by hand from the rule in
-- docs/dev-notes.md; `confirmed` says where it was seen in game, or is false when it has
-- only been reasoned out.

local _, T = ...

-- WoW Forever: selling an item teaches its appearance whatever the class, and the collect
-- APIs do not say so (notes: Transmog on Forever).

T.Verdict({
    id = "forever.appearance.validSourceNotCollectable",
    version = 1,
    title = "A valid source that neither collect verdict claims is still learnable here",
    flavor = "forever",
    facts = "appearance",
    shape = {
        sourceCollected = false,
        sourceValid = true,
        useError = false,
        playerCanCollect = false,
        accountCanCollect = false,
        lookKnownElsewhere = false,
    },
    kinds = {
        {
            name = "hunter below 40",
            toon = { class = "HUNTER", maxLevel = 39 },
            -- Cloth with a white tooltip, mail with a red one: the two the rule was first seen
            -- on, learned since. Then a staff, polearms, crossbows, a fist weapon, a two-handed
            -- axe and leather, some above the toon's level.
            pool = { 2969, 6550, 215375, 13038, 1522, 13037, 2942, 6687, 15151, 5200 },
            expect = { status = "own" },
        },
        {
            name = "rogue",
            toon = { class = "ROGUE" },
            -- Leather, bows, a mace and a sword, several above the level they were found at:
            -- the level is no part of the shape.
            pool = { 7690, 18323, 2824, 15366, 279868, 15445, 9802, 5192 },
            expect = { status = "own" },
        },
    },
    confirmed = "Forever, hunter, 2026-11: Spellbinder Vest 2969 and Soldier's Wristguards 6550",
})

T.Verdict({
    id = "forever.appearance.proficiencySourceNotCollectable",
    version = 1,
    title = "A source the toon has no proficiency for is learnable for the collection only",
    flavor = "forever",
    facts = "appearance",
    shape = {
        sourceCollected = false,
        sourceValid = false,
        useError = 10,
        playerCanCollect = false,
        accountCanCollect = false,
        lookKnownElsewhere = false,
    },
    kinds = {
        {
            name = "hunter",
            toon = { class = "HUNTER" },
            -- Blazing Wand, learned since. Then a two-handed mace, a one-handed mace, plate
            -- and a shield.
            pool = { 5212, 279895, 15445, 14932, 282555 },
            expect = { status = "other" },
        },
        {
            name = "rogue",
            toon = { class = "ROGUE" },
            -- Staves, two-handed maces and axes, a polearm, a crossbow and fist weapons. Training
            -- a weapon skill retires the items of that kind.
            pool = { 215375, 15261, 13038, 1522, 2942, 6687, 273456, 18717 },
            expect = { status = "other" },
        },
    },
    confirmed = false,
})

-- Every status that says "there is something to learn here". A shape whose rule is "nothing
-- to learn" expects none of them; what the item shows instead is other rules' business.
local LEARN = { "own", "ownPlus", "other", "otherPlus", "otherNoLoot", "lowSkill", "lowSkillPlus" }

-- A learned source is account-wide, so the three items the tests above began with, which the
-- account has learned since, are the pool on any toon of it; then weapons, a held item and
-- boots from the search, bound in every way and one of them unusable to the hunter.
local COLLECTED = { 2969, 6550, 5212, 257283, 281306, 1416, 15224, 1804, 2781, 4568, 1812 }

T.Verdict({
    id = "forever.appearance.collected",
    version = 1,
    title = "A source that is learned leaves nothing to learn",
    flavor = "forever",
    facts = "appearance",
    shape = {
        sourceCollected = true,
    },
    kinds = {
        {
            name = "hunter",
            toon = { class = "HUNTER" },
            pool = COLLECTED,
            expect = { notStatus = LEARN },
        },
        {
            name = "rogue",
            toon = { class = "ROGUE" },
            pool = COLLECTED,
            expect = { notStatus = LEARN },
        },
    },
    confirmed = false,
})

-- The look is already known from another item: ownPlus, and only for a player who asked to
-- see those (notes: Transmog on Forever, validSourceNotCollectable with KnownLook). The pools
-- are filled from /cwtest search. One pool serves both tests and both kinds: which test an
-- item is a case of follows the player's setting, and whether it fits a toon its class. A
-- dagger, a two-handed axe, two guns and a held item, two of them above the hunter's level.
local KNOWN_LOOK = { 284046, 1959, 279894, 282088, 9487 }

T.Verdict({
    id = "forever.appearance.knownLook",
    version = 1,
    title = "A valid source of a look known from another item is learnable as a second source",
    flavor = "forever",
    facts = "appearance",
    shape = {
        sourceCollected = false,
        sourceValid = true,
        useError = false,
        playerCanCollect = false,
        accountCanCollect = false,
        lookKnownElsewhere = true,
        sameLookShown = true,
    },
    kinds = {
        { name = "hunter", toon = { class = "HUNTER" }, pool = KNOWN_LOOK, expect = { status = "ownPlus" } },
        { name = "rogue", toon = { class = "ROGUE" }, pool = KNOWN_LOOK, expect = { status = "ownPlus" } },
    },
    confirmed = false,
})

T.Verdict({
    id = "forever.appearance.knownLookHidden",
    version = 1,
    title = "With looks known from another item not shown, such a source is nothing to learn",
    flavor = "forever",
    facts = "appearance",
    shape = {
        sourceCollected = false,
        sourceValid = true,
        useError = false,
        playerCanCollect = false,
        accountCanCollect = false,
        lookKnownElsewhere = true,
        sameLookShown = false,
    },
    kinds = {
        { name = "hunter", toon = { class = "HUNTER" }, pool = KNOWN_LOOK, expect = { notStatus = LEARN } },
        { name = "rogue", toon = { class = "ROGUE" }, pool = KNOWN_LOOK, expect = { notStatus = LEARN } },
    },
    confirmed = false,
})

-- Retail: the collect APIs answer for the toon and for the account. The pools are filled
-- from /cwtest search on a toon of the kind, since what fits depends on the class.

-- The items of the WoWUnit tests the addon used to ship (tests/*.lua, 2020 to 2021). Each of
-- those tests expected one account's state of that day: needed, known, or known from another
-- item. Here every item is in the pool of every shape below, and its facts on the toon at
-- hand say which shape it is a case of today. The old links carried bonus IDs; these are the
-- plain items.
local WOWUNIT_ITEMS = {
    6125,   -- Brawler's Harness (shirt)
    93607,  -- Crafted Dreadful Gladiator's Cloak of Alacrity
    68751,  -- Imbued Pioneer Bracers (leather)
    172790, -- Corrupted Aspirant's Leather Gloves
    154820, -- Festerroot Jerkin (leather)
    106552, -- Warpscale Legguards (mail)
    36445,  -- Riveted Shield
    25114,  -- Doomsayer's Mace
    116550, -- Auchenai Mace
    36495,  -- Ferrous Hammer
    -- Found by /cwtest search on a druid (2026-11-16) for the shape the old items have no
    -- case of: a look another toon needs, known from a source this toon cannot use.
    164760, -- Illidari Warglaive
    168100, -- Alliance Tabard
    -- A cloak that asks for a reputation (Sporeggar, Honored), which the search found on a
    -- druid without it.
    25827,  -- Muck-Covered Drape
}

T.Verdict({
    id = "retail.appearance.learnable",
    version = 3,
    title = "A source this toon can collect, of a look the account does not have, is learnable",
    flavor = "retail",
    facts = "appearance",
    shape = {
        sourceCollected = false,
        sourceValid = true,
        useError = false,
        playerCanCollect = true,
        lookKnownElsewhere = false,
        levelMet = true,
        canUse = true,
    },
    kinds = {
        {
            name = "druid",
            toon = { class = "DRUID" },
            pool = WOWUNIT_ITEMS,
            expect = { status = "own" },
        },
    },
    confirmed = false,
})

-- Selling a piece teaches its look, so what the piece asks of the toon that wears it is no
-- bar to learning it (author decision, 2026-11-19): the three tests below expected the gear
-- of something for later until then.
T.Verdict({
    id = "retail.appearance.belowLevel",
    version = 2,
    title = "The same below the item's level is learnable now all the same",
    flavor = "retail",
    facts = "appearance",
    shape = {
        sourceCollected = false,
        sourceValid = true,
        useError = false,
        playerCanCollect = true,
        lookKnownElsewhere = false,
        levelMet = false,
    },
    kinds = {
        {
            name = "druid",
            toon = { class = "DRUID" },
            pool = WOWUNIT_ITEMS,
            expect = { status = "own" },
        },
    },
    confirmed = false,
})

-- The level is not the only thing a piece can ask for. A reputation the toon lacks is a red
-- requirement line in the tooltip and no use error in the transmog answers; the client's
-- "can this toon use the item" is what tells it from a piece that is learnable now, which is
-- why the tests for those ask for canUse. Muck-Covered Drape showed it (retail, a druid,
-- 2026-11-16): the search took it for a second source to learn, the addon said lowSkill.
T.Verdict({
    id = "retail.appearance.requirementNotMet",
    version = 2,
    title = "A source this toon could collect, on a piece with a requirement it has not met, is learnable now",
    flavor = "retail",
    facts = "appearance",
    shape = {
        sourceCollected = false,
        sourceValid = true,
        useError = false,
        playerCanCollect = true,
        lookKnownUsable = false,
        levelMet = true,
        canUse = false,
    },
    kinds = {
        {
            name = "druid",
            toon = { class = "DRUID" },
            pool = WOWUNIT_ITEMS,
            expect = { status = "own" },
        },
    },
    confirmed = false,
})

-- The same piece when its look is known from a source this toon can use. The cloak is a case
-- of this test or of the one above from one login to the next: whether the look's other
-- source counts as usable is the client's answer about that source, and it has read both
-- ways within minutes with nothing learned in between (most likely before and after the
-- other source's item was loaded; not settled).
T.Verdict({
    id = "retail.appearance.requirementNotMetKnownLook",
    version = 2,
    title = "The same of a look this toon knows from another item is a second source to learn now",
    flavor = "retail",
    facts = "appearance",
    shape = {
        sourceCollected = false,
        sourceValid = true,
        useError = false,
        playerCanCollect = true,
        lookKnownUsable = true,
        levelMet = true,
        canUse = false,
        sameLookShown = true,
    },
    kinds = {
        {
            name = "druid",
            toon = { class = "DRUID" },
            pool = WOWUNIT_ITEMS,
            expect = { status = "ownPlus" },
        },
    },
    confirmed = false,
})

T.Verdict({
    id = "retail.appearance.otherToon",
    version = 1,
    title = "A source only another toon of the account can collect is learnable for the collection",
    flavor = "retail",
    facts = "appearance",
    shape = {
        sourceCollected = false,
        playerCanCollect = false,
        accountCanCollect = true,
        lookKnownElsewhere = false,
    },
    kinds = {
        {
            name = "druid",
            toon = { class = "DRUID" },
            pool = WOWUNIT_ITEMS,
            expect = { status = "other" },
        },
    },
    confirmed = false,
})

T.Verdict({
    id = "retail.appearance.knownLook",
    version = 2,
    title = "A source this toon can collect, of a look it knows from another item, is a second source",
    flavor = "retail",
    facts = "appearance",
    shape = {
        sourceCollected = false,
        sourceValid = true,
        useError = false,
        playerCanCollect = true,
        lookKnownUsable = true,
        levelMet = true,
        canUse = true,
        sameLookShown = true,
    },
    kinds = {
        {
            name = "druid",
            toon = { class = "DRUID" },
            pool = WOWUNIT_ITEMS,
            expect = { status = "ownPlus" },
        },
    },
    confirmed = false,
})

T.Verdict({
    id = "retail.appearance.knownLookHidden",
    version = 2,
    title = "With looks known from another item not shown, such a source is nothing to learn",
    flavor = "retail",
    facts = "appearance",
    shape = {
        sourceCollected = false,
        sourceValid = true,
        useError = false,
        playerCanCollect = true,
        lookKnownUsable = true,
        levelMet = true,
        canUse = true,
        sameLookShown = false,
    },
    kinds = {
        {
            name = "druid",
            toon = { class = "DRUID" },
            pool = WOWUNIT_ITEMS,
            expect = { notStatus = LEARN },
        },
    },
    confirmed = false,
})

-- The other three cases of a look known from another item, by who can learn this source and
-- who can use the known one (the two tests above are "this toon, from a source it can use").

T.Verdict({
    id = "retail.appearance.knownLookUnusable",
    version = 2,
    title = "A source this toon can collect, of a look known only from a source it cannot use, is a look to learn",
    flavor = "retail",
    facts = "appearance",
    shape = {
        sourceCollected = false,
        sourceValid = true,
        useError = false,
        playerCanCollect = true,
        lookKnownUsable = false,
        lookKnownUnusable = true,
        levelMet = true,
        canUse = true,
    },
    kinds = {
        {
            name = "druid",
            toon = { class = "DRUID" },
            pool = WOWUNIT_ITEMS,
            expect = { status = "own" },
        },
    },
    confirmed = false,
})

T.Verdict({
    id = "retail.appearance.otherToonKnownLook",
    version = 1,
    title = "A source only another toon can collect, of a look known from a source this toon cannot use, is a second source for the collection",
    flavor = "retail",
    facts = "appearance",
    shape = {
        sourceCollected = false,
        playerCanCollect = false,
        accountCanCollect = true,
        lookKnownUnusable = true,
        sameLookShown = true,
    },
    kinds = {
        {
            name = "druid",
            toon = { class = "DRUID" },
            pool = WOWUNIT_ITEMS,
            expect = { status = "otherPlus" },
        },
    },
    confirmed = false,
})

T.Verdict({
    id = "retail.appearance.otherToonKnownLookHidden",
    version = 1,
    title = "With looks known from another item not shown, such a source is nothing to learn",
    flavor = "retail",
    facts = "appearance",
    shape = {
        sourceCollected = false,
        playerCanCollect = false,
        accountCanCollect = true,
        lookKnownUnusable = true,
        sameLookShown = false,
    },
    kinds = {
        {
            name = "druid",
            toon = { class = "DRUID" },
            pool = WOWUNIT_ITEMS,
            expect = { notStatus = LEARN },
        },
    },
    confirmed = false,
})

T.Verdict({
    id = "retail.appearance.otherToonKnownLookUsable",
    version = 1,
    title = "A source only another toon can collect, of a look known only from a source this toon can use, is still a look to learn for the collection",
    flavor = "retail",
    facts = "appearance",
    shape = {
        sourceCollected = false,
        playerCanCollect = false,
        accountCanCollect = true,
        lookKnownUsable = true,
        lookKnownUnusable = false,
    },
    kinds = {
        {
            name = "druid",
            toon = { class = "DRUID" },
            pool = WOWUNIT_ITEMS,
            expect = { status = "other" },
        },
    },
    confirmed = false,
})

T.Verdict({
    id = "retail.appearance.collected",
    version = 1,
    title = "A source that is learned leaves nothing to learn",
    flavor = "retail",
    facts = "appearance",
    shape = {
        sourceCollected = true,
    },
    kinds = {
        {
            name = "druid",
            toon = { class = "DRUID" },
            pool = WOWUNIT_ITEMS,
            expect = { notStatus = LEARN },
        },
    },
    confirmed = false,
})

T.Verdict({
    id = "retail.appearance.noProficiency",
    version = 1,
    title = "A source the toon has no proficiency for is learnable for the collection only",
    flavor = "retail",
    facts = "appearance",
    shape = {
        sourceCollected = false,
        sourceValid = false,
        useError = 10, -- Enum.TransmogUseErrorType.ItemProficiency
        accountCanCollect = true,
        lookKnownElsewhere = false,
    },
    kinds = {
        {
            name = "druid",
            toon = { class = "DRUID" },
            pool = { 5212 }, -- Blazing Wand
            expect = { status = "other" },
        },
    },
    confirmed = false,
})
