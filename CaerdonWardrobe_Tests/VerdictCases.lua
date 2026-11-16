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
            -- Cloth with a white tooltip, mail with a red one.
            pool = { 2969, 6550 },
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
            pool = { 5212 }, -- Blazing Wand
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

-- Retail: the collect APIs answer for the toon and for the account. The pools are filled
-- from /cwtest search on a toon of the kind, since what fits depends on the class.

T.Verdict({
    id = "retail.appearance.learnable",
    version = 1,
    title = "A source this toon can collect, of a look the account does not have, is learnable",
    flavor = "retail",
    facts = "appearance",
    shape = {
        sourceCollected = false,
        sourceValid = true,
        useError = false,
        playerCanCollect = true,
        lookKnownElsewhere = false,
    },
    kinds = {
        {
            name = "druid",
            toon = { class = "DRUID" },
            pool = {},
            expect = { status = "own" },
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
