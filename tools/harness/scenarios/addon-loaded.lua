-- A window whose addon the client loads on demand, and when a feature attaches to it.
--
-- A feature used to wait for the window's ADDON_LOADED and compare names. Another addon can
-- load the window's addon before this one's features begin (the client loads addons in the
-- order of their names, and any of them may ask for a window's addon), and then that event
-- never comes again: the window had no icons for the session. A feature now says which addon
-- it waits for (WhenAddOnLoaded) and attaches at once where it is loaded already.
--
-- Three worlds: the window's addon loaded before the features begin, loaded after, and loaded
-- before with a window that is not what the feature expects (its error must stay its own).
--
-- Real code: the addon's core, FeatureMixin.lua and two features (the guild bank, the weekly
-- rewards). The windows are stand-ins with the one function each feature hooks; EventUtil is
-- the harness's stand-in for Blizzard's.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Rogue", classFile = "ROGUE", race = "Human",
        faction = "Alliance", level = 10 }

    local GUILD_BANK, WEEKLY = "Blizzard_GuildBankUI", "Blizzard_WeeklyRewards"

    -- loaded: which addons the client calls loaded when the features begin.
    -- windows: which windows are there by then, as the feature expects them.
    local function World(flavor, loaded, windows)
        local game = H.StockGame(TOON, {})
        game:Set("C_AddOns.IsAddOnLoaded", function(name)
            return loaded[name] == true, loaded[name] == true
        end)
        local client = H.Client.New({ flavor = flavor, provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "features/GuildBank.lua", namespace)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "features/WeeklyRewards.lua", namespace)
        local calls = { guildBank = 0, weekly = 0 }
        local function Open(name)
            if name == GUILD_BANK then
                rawset(client.env, "GuildBankFrame", { Update = function() calls.guildBank = calls.guildBank + 1 end })
            else
                rawset(client.env, "WeeklyRewardsFrame", { Refresh = function() calls.weekly = calls.weekly + 1 end,
                    IsShown = function() return false end })
            end
        end
        for name in pairs(windows) do
            Open(name)
        end
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(10)
        return client, calls, Open
    end

    -- Hooked is seen by the function in the window having been replaced: hooksecurefunc puts
    -- its own in its place.
    local function Hooked(client, frameName, key, original)
        local frame = rawget(client.env, frameName)
        return frame ~= nil and frame[key] ~= original
    end

    for _, flavor in ipairs({ "forever", "retail" }) do
        local label = flavor .. ": "

        -- 1. Loaded before the features begin: attached at once, with no event.
        local client = World(flavor, { [GUILD_BANK] = true, [WEEKLY] = true }, { [GUILD_BANK] = true, [WEEKLY] = true })
        Equal(#client.errors, 0, label .. "before: no error (" .. tostring(client.errors[1]) .. ")")
        local guildUpdate = rawget(client.env, "GuildBankFrame").Update
        local weeklyRefresh = rawget(client.env, "WeeklyRewardsFrame").Refresh
        -- The originals are gone from the windows by now, so the test is by a second hook's
        -- count: the feature's own handler is reached through the window's function.
        local feature = client.env.CaerdonWardrobe:GetFeature("GuildBank")
        local reached = 0
        if feature then
            feature.OnGuildBankFrameUpdate = function() reached = reached + 1 end
            guildUpdate()
        end
        Check(feature ~= nil, label .. "before: the guild bank's feature is registered")
        Equal(reached, 1, label .. "before: a window loaded before the features began is attached to")
        local weekly = client.env.CaerdonWardrobe:GetFeature("WeeklyRewards")
        local weeklyReached = 0
        if weekly then
            weekly.UpdateActivities = function() weeklyReached = weeklyReached + 1 end
            weeklyRefresh()
        end
        Equal(weeklyReached, 1, label .. "before: and so is the second window")
        -- Its ADDON_LOADED, should the client send one again, attaches nothing twice.
        client:Fire("ADDON_LOADED", GUILD_BANK)
        reached = 0
        rawget(client.env, "GuildBankFrame").Update()
        Equal(reached, 1, label .. "before: its ADDON_LOADED afterwards attaches nothing a second time")

        -- 2. Loaded after: nothing until its own event, then once.
        local calls, Open
        client, calls, Open = World(flavor, {}, {})
        Equal(#client.errors, 0, label .. "after: no error with no window there (" .. tostring(client.errors[1]) .. ")")
        Open(GUILD_BANK)
        local original = rawget(client.env, "GuildBankFrame").Update
        client:Fire("ADDON_LOADED", "Blizzard_SomethingElse")
        Check(not Hooked(client, "GuildBankFrame", "Update", original), label .. "after: another addon's loading attaches nothing")
        client:Fire("ADDON_LOADED", GUILD_BANK)
        Check(Hooked(client, "GuildBankFrame", "Update", original), label .. "after: the window's own does")
        local once = rawget(client.env, "GuildBankFrame").Update
        client:Fire("ADDON_LOADED", GUILD_BANK)
        Check(rawget(client.env, "GuildBankFrame").Update == once, label .. "after: and only once")
        Check(rawget(client.env, "WeeklyRewardsFrame") == nil, label .. "after: the other window is still not there")
        Equal(#client.errors, 0, label .. "after: no error (" .. tostring(client.errors[1]) .. ")")

        -- 3. Called loaded, and the window is not there: that feature's error is reported and
        --    the other attaches all the same.
        client = World(flavor, { [GUILD_BANK] = true, [WEEKLY] = true }, { [WEEKLY] = true })
        Equal(#client.errors, 1, label .. "broken: the missing window is one error for the error handler")
        weekly = client.env.CaerdonWardrobe:GetFeature("WeeklyRewards")
        weeklyReached = 0
        if weekly then
            weekly.UpdateActivities = function() weeklyReached = weeklyReached + 1 end
            rawget(client.env, "WeeklyRewardsFrame").Refresh()
        end
        Equal(weeklyReached, 1, label .. "broken: and the other window is attached to all the same")
        Check(client.env.CaerdonWardrobe:GetFeature("GuildBank").initFinished ~= false,
            label .. "broken: the feature's Init itself finished")
    end
end
