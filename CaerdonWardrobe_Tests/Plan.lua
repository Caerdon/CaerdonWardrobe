-- The plan: what the tests do by themselves, and what they are asked to look at.
--
-- This file is the way in, as the saved variables are the way out. It holds the standing
-- defaults. Plan.local.lua is loaded after it and is not tracked: put one-off requests there
-- (items to probe for a question, a test to skip while it is being worked on), for example
--
--     local plan = CaerdonWardrobeTestsPlan
--     plan.probeItems = { 2969, 6550 }
--     plan.traceItems = { 216679 }
--     plan.recordItems = { 6219 }
--     plan.skip["transmog.categoryAppearances"] = "slow on this toon"

local _, T = ...

CaerdonWardrobeTestsPlan = {
    -- After login, once the addon's queue is empty: run every test that has to run.
    autoRun = true,

    -- Once a session: record what the bags show (and the bank the first time it is opened) and
    -- compare it with the last session's record (Snapshot.lua). This draws every item once on
    -- hidden buttons; false leaves it out.
    autoSnapshot = true,

    -- Test id -> reason. A skipped test is not run by itself; /cwtest run <id> still runs it.
    skip = {},

    -- Item IDs to look up after login: the client's facts, the tooltip's lines and the
    -- addon's verdict for each go into the results (probes).
    probeItems = {},

    -- Item IDs to record after login for the offline harness: the client's answers behind the
    -- addon's verdict for each (Recorder.lua). This hooks every client function the addon
    -- names for the whole session, so leave it empty unless recordings are wanted.
    recordItems = {},

    -- Item IDs whose askers are wanted: every call of a C_Item or C_TooltipInfo function
    -- that names one is recorded with its stack (Sources.lua). This hooks those functions for
    -- the whole session, so leave it empty unless a question needs it.
    traceItems = {},

    timing = {
        runs = 10,         -- forced refreshes per /cwtest timing <label>
        countedRuns = 3,   -- more of them afterwards with the core's counters on; 0 for none
        idleSeconds = 180, -- /cwtest timing idle
    },

    -- The bag addons, and the UI suites with bags of their own, that the addon has an
    -- integration for, by the name of their folder (the integration's `addon`). /cwtest
    -- rotation visits the installed ones, one per reload, with only that one enabled
    -- (Rotation.lua). A new bag integration gets a line here.
    rotation = {
        addons = {
            "AdiBags", "ArkInventory", "Baganator", "Bagnon", "Bagnonium", "BaudBag", "BetterBags",
            "cargBags_Nivaya", "ElvUI", "Inventorian", "KkthnxUI", "LiteBag", "NDui", "Sorted",
        },
    },
}

function T.GetPlan()
    return CaerdonWardrobeTestsPlan
end
