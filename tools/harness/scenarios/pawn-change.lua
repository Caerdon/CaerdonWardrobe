-- Pawn changed what its verdicts are made from.
--
-- The upgrade verdicts read Pawn and are kept until the next refresh. Pawn has no event for a
-- change of its scales; it calls PawnResetTooltips or PawnInvalidateBestItems, and the
-- equipment code hooks both (types/EquipmentMixin.lua):
--   1. A run of such calls is one refresh, named "pawn", about everything.
--   2. Pawn's functions still run, with their arguments.
--   3. Without Pawn the addon loads and nothing is hooked.
--
-- Pawn here is two functions of the scenario's own. That Pawn calls them when a scale changes
-- was read in Pawn's code and is not proven by this.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 29 }

    local function Start(withPawn)
        local game = H.StockGame(TOON, {})
        local world = { refreshes = {}, pawnCalls = {} }
        if withPawn then
            game:Set("PawnResetTooltips", function(...) world.pawnCalls[#world.pawnCalls + 1] = { "reset", ... } end)
            game:Set("PawnInvalidateBestItems", function(...) world.pawnCalls[#world.pawnCalls + 1] = { "best", ... } end)
        end
        local client = H.Client.New({ flavor = "forever", provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)

        local core = client.env.CaerdonWardrobe
        local refreshItems = core.RefreshItems
        function core:RefreshItems(reason, detail, changed)
            world.refreshes[#world.refreshes + 1] = { reason = reason, detail = detail, changed = changed }
            return refreshItems(self, reason, detail, changed)
        end
        world.client, world.env = client, client.env
        return world
    end

    local function Named(world, reason)
        local count, last = 0, nil
        for _, refresh in ipairs(world.refreshes) do
            if refresh.reason == reason then
                count, last = count + 1, refresh
            end
        end
        return count, last
    end

    do
        local world = Start(true)
        local client, env = world.client, world.env
        Equal(#client.errors, 0, "with Pawn: the addon loads with no error")
        Equal((Named(world, "pawn")), 0, "with Pawn: nothing refreshes before Pawn says anything")

        -- A scale's weight is edited: Pawn resets its values once.
        env.PawnResetTooltips()
        Equal((Named(world, "pawn")), 0, "edit: no refresh in the call itself")
        client:Tick(10)
        local count, last = Named(world, "pawn")
        Equal(count, 1, "edit: one refresh once Pawn has reset its values")
        Check(last and last.changed == nil, "edit: about everything")
        Equal(#world.refreshes, 1, "edit: and no other refresh comes of it")

        -- An import: several calls of both in one go.
        world.refreshes = {}
        for _ = 1, 4 do
            env.PawnInvalidateBestItems()
            env.PawnResetTooltips()
        end
        client:Tick(10)
        Equal((Named(world, "pawn")), 1, "import: a run of calls of both is one refresh")

        -- The best items alone (a spec change, a reset of the upgrade tracking).
        world.refreshes = {}
        env.PawnInvalidateBestItems()
        client:Tick(10)
        Equal((Named(world, "pawn")), 1, "best items: their invalidation alone refreshes too")

        -- A later change is a refresh of its own.
        world.refreshes = {}
        env.PawnResetTooltips()
        client:Tick(10)
        env.PawnResetTooltips()
        client:Tick(10)
        Equal((Named(world, "pawn")), 2, "later: two changes apart are two refreshes")

        -- Pawn's own functions are still what runs, with what they were given.
        world.pawnCalls = {}
        env.PawnResetTooltips("a", 2)
        Check(#world.pawnCalls == 1 and world.pawnCalls[1][1] == "reset" and world.pawnCalls[1][2] == "a" and world.pawnCalls[1][3] == 2,
            "hook: Pawn's function runs with its arguments")
        client:Tick(10)
        Equal(#client.errors, 0, "with Pawn: no error reached the error handler")
    end

    do
        local world = Start(false)
        local client = world.client
        Equal(#client.errors, 0, "without Pawn: the addon loads with no error")
        Check(rawget(client.env, "PawnResetTooltips") == nil, "without Pawn: nothing stands in for its function")
        client:Tick(10)
        Equal((Named(world, "pawn")), 0, "without Pawn: and nothing refreshes in its name")
    end
end
