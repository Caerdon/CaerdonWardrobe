-- The plan: what the tests do by themselves, and what they are asked to look at.
--
-- This file is the way in, as the saved variables are the way out. It holds the standing
-- defaults. Plan.local.lua is loaded after it and is not tracked: put one-off requests there
-- (items to probe for a question, a test to skip while it is being worked on), for example
--
--     local plan = CaerdonWardrobeTestsPlan
--     plan.probeItems = { 2969, 6550 }
--     plan.skip["transmog.categoryAppearances"] = "slow on this toon"

local _, T = ...

CaerdonWardrobeTestsPlan = {
    -- After login, once the addon's queue is empty: run every test that has to run.
    autoRun = true,

    -- Test id -> reason. A skipped test is not run by itself; /cwtest run <id> still runs it.
    skip = {},

    -- Item IDs to look up after login: the client's facts, the tooltip's lines and the
    -- addon's verdict for each go into the results (probes).
    probeItems = {},

    timing = {
        runs = 10,         -- forced refreshes per /cwtest timing <label>
        idleSeconds = 180, -- /cwtest timing idle
    },
}

function T.GetPlan()
    return CaerdonWardrobeTestsPlan
end
