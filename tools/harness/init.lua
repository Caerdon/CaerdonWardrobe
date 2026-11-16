-- The harness: the addon's real Lua run under LuaJIT in a mocked client. Offline evidence:
-- it checks the addon's logic against what a client once answered, never the client itself.
--
--   local H = dofile("tools/harness/init.lua")
--
-- loads every part and returns the shared table. tools/harness/run.lua is the command line.

local source = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
local dir = source:match("^(.*)/[^/]*$") or "."

local H = { dir = dir, addonDir = dir .. "/../.." }

local function Part(name)
    local chunk, problem = loadfile(dir .. "/" .. name .. ".lua")
    if not chunk then
        error(problem, 0)
    end
    chunk(H)
end

Part("lua51")
H.Guards.Install()

-- What the recorder and the harness must agree on is the test addon's own file.
do
    local chunk, problem = loadfile(H.addonDir .. "/CaerdonWardrobe_Tests/RecordKeys.lua")
    if not chunk then
        error(problem, 0)
    end
    local T = {}
    chunk("CaerdonWardrobe_Tests", T)
    H.Keys = T.RecordKeys
end

Part("client")
Part("addon")
Part("replay")
Part("fixtures")
Part("game")

return H
