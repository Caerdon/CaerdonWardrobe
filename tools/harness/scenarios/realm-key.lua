-- What a toon's saved data is filed under: the realm's name, and the server's number where
-- the client gives no name (CaerdonAPI:GetRealmKey).
--
-- WoW Forever stopped giving addons the realm's name in November 2026: GetRealmName is an
-- empty text there. The addon filed everything under "" from then on, so each toon's recorded
-- recipes, standings and chosen gear set began again, and all of an account's toons were one
-- realm. A client's saved variables showed it: the old realm key with three toons, and beside
-- it a key "" with the toon played that day.
--
-- The game is hand-made, so this checks the logic. That a toon's GUID carries the server's
-- number on a client without the name was read off an item's GUID in an export, and is not
-- shown here.
--
-- Real code: the whole addon, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 31 }

    -- A client, with what was saved before it started, the realm's name it gives and the
    -- toon's GUID. Returns the addon's API table and the client's globals.
    local function Start(saved, realmName, guid)
        local game = H.StockGame(TOON, {})
        game:Set("GetRealmName", function() return realmName end)
        game:Set("UnitGUID", function() return guid end)
        -- A faction in the reputation window, so that the standings are read and kept.
        game:Set("C_Reputation.GetNumFactions", function() return 1 end)
        game:Set("C_Reputation.GetFactionDataByIndex", function(index)
            return index == 1 and { factionID = 72, name = "Stormwind", reaction = 6, isHeader = false } or nil
        end)
        local client = H.Client.New({ flavor = "forever", provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
        for name, value in pairs(saved or {}) do
            rawset(client.env, name, H.DeepCopy(value))
        end
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)
        Equal(#client.errors, 0, "start: no error reached the error handler (" .. tostring(client.errors[1]) .. ")")
        return client.env.CaerdonAPI, client.env, client
    end

    -- A client that gives the realm's name: filed under it, and nothing is moved.
    do
        local api, env = Start({ CaerdonRecipeData = { Farrealm = { Zzyxa = { knownRecipes = { Bolt = 7 } }, Other = { knownRecipes = { Ore = 3 } } } } },
            "Farrealm", "Player-77-0000ABCD")
        local key, from = api:GetRealmKey()
        Equal(key, "Farrealm", "named: a realm with a name is filed under it")
        Equal(from, "the realm's name", "named: and says so")
        Equal(api:GetRealmTakeOver(), nil, "named: nothing is taken over")
        Equal(env.CaerdonRecipeData.Farrealm.Zzyxa.knownRecipes.Bolt, 7, "named: the toon's record is where it was")
        Equal(env.CaerdonRecipeData["server 77"], nil, "named: and nothing is filed under a server's number")
    end

    -- No name: the server's number from the toon's GUID. What was saved under the old name
    -- comes along, every toon of it, and what was filed under "" meanwhile for this toon.
    do
        local saved = {
            CaerdonRecipeData = {
                globalRecipeNameToID = { Bolt = 7, Ore = 3 },
                ["Old Realm Name"] = {
                    Zzyxa = { knownRecipes = { Bolt = 7 }, recipes = { Tailoring = { 1, 2 } }, scannedProfessions = { Tailoring = true }, tools = {} },
                    Other = { knownRecipes = { Ore = 3 }, recipes = { Mining = { 3 } } },
                },
                -- Filed since the name was gone: one profession opened again, a recipe
                -- learned, and one whose ID is another than the old record has.
                [""] = {
                    Zzyxa = { knownRecipes = { Stew = 11, Bolt = 8 }, recipes = { Cooking = { 9 } }, scannedProfessions = { Cooking = true }, tools = {} },
                    Stranger = { knownRecipes = { Fish = 9 } },
                },
            },
            CaerdonProfessionData = { ["Old Realm Name"] = { Zzyxa = { Tailoring = { skillLevel = 80 } } }, [""] = { Zzyxa = {} } },
            CaerdonRefreshData = {
                ["Old Realm Name"] = { Zzyxa = { standings = { [72] = 4 }, chosenGearSet = 3 }, Other = { standings = { [47] = 5 } } },
                [""] = { Zzyxa = { standings = { [72] = 5, [47] = 4 } } },
            },
        }
        local api, env, client = Start(saved, "", "Player-6928-0000ABCD")
        local key, from = api:GetRealmKey()
        Equal(key, "server 6928", "hidden: with no realm name the key is the server's number")
        Check(tostring(from):find("server number in the toon's GUID", 1, true) ~= nil, "hidden: and says where it is from: " .. tostring(from))
        local recipes, refresh = env.CaerdonRecipeData, env.CaerdonRefreshData
        local mine = recipes["server 6928"] and recipes["server 6928"].Zzyxa
        Check(mine ~= nil and mine.recipes.Tailoring ~= nil and mine.scannedProfessions.Tailoring == true,
            "hidden: the toon's recorded recipes are under the new key, with nothing recorded again")
        -- Old records and newer ones of the same toon are made one: the older adds what the
        -- newer has not, and the newer stands where both say something.
        Check(mine ~= nil and mine.recipes.Cooking ~= nil and mine.recipes.Cooking[1] == 9 and mine.scannedProfessions.Cooking == true,
            "both: a profession recorded since the name was gone is kept beside the ones recorded before")
        Check(mine ~= nil and mine.knownRecipes.Stew == 11, "both: a recipe learned since is kept")
        Equal(mine and mine.knownRecipes.Bolt, 8, "both: where the two differ the newer record stands")
        Check(recipes["server 6928"].Other ~= nil and recipes["server 6928"].Other.knownRecipes.Ore == 3,
            "hidden: the realm's other toons came along")
        Equal(recipes["Old Realm Name"], nil, "hidden: the old key is gone once everything of it is taken")
        Equal(recipes.globalRecipeNameToID.Bolt, 7, "hidden: what is not a realm's is left alone")
        Check(recipes[""] ~= nil and recipes[""].Zzyxa == nil and recipes[""].Stranger ~= nil,
            "hidden: of the empty key the toon's own record is taken, and another toon's stays for when it is played")
        local kept = refresh["server 6928"] and refresh["server 6928"].Zzyxa
        Check(kept ~= nil and kept.chosenGearSet == 3, "hidden: the gear set last put on is kept")
        Check(kept ~= nil and kept.standings[47] == 4 and kept.standings[72] ~= 4,
            "hidden: of two records the newer one's standings count (the empty key's over the old realm's): " ..
            tostring(kept and kept.standings[47]) .. ", " .. tostring(kept and kept.standings[72]))
        Check(refresh["server 6928"].Other ~= nil and refresh["Old Realm Name"] == nil and refresh[""] == nil,
            "hidden: the same for the standings' table, and an empty key that holds nothing more is gone")
        Check(env.CaerdonProfessionData["server 6928"].Zzyxa.Tailoring ~= nil, "hidden: and for the professions' ranks")
        local taken = api:GetRealmTakeOver()
        Check(taken ~= nil and taken.from == "Old Realm Name" and taken.toons == 2 and taken.fromEmpty == true and taken.candidates == 1,
            "hidden: the export has what was taken over")
        -- What the other toons can use is read from the new key.
        local realmRecipes = env.CaerdonRecipe:GetRealmRecordedRecipes()
        Check(realmRecipes.Other ~= nil and realmRecipes.Zzyxa ~= nil, "hidden: the realm's recorded recipes are those of the server's toons")
        -- And what is written from here on goes under it, by each of the three that write:
        -- the recipes' records (at the world's arrival), the standings (at a reputation
        -- event), the gear set put on.
        client:Fire("PLAYER_ENTERING_WORLD", false, true)
        client:Fire("UPDATE_FACTION")
        client:Tick(40)
        env.CaerdonEquipment:NoteGearSetPutOn(true, 5)
        Check(recipes[""].Zzyxa == nil, "hidden: the recipes' records are not made under the empty key again")
        Check(env.CaerdonProfessionData[""] == nil or env.CaerdonProfessionData[""].Zzyxa == nil, "hidden: nor the professions' ranks")
        Equal(refresh[""], nil, "hidden: nor anything of the standings or the gear set")
        Equal(refresh["server 6928"].Zzyxa.standings[72], 6, "hidden: the standings read now are kept under the server's number")
        Equal(refresh["server 6928"].Zzyxa.chosenGearSet, 5, "hidden: and so is the gear set put on")
    end

    -- A name the account has on two realms: nobody can say which is this server's, so
    -- nothing of either is taken; the empty key's record still is.
    do
        local saved = {
            CaerdonRecipeData = {
                ["Realm One"] = { Zzyxa = { knownRecipes = { Bolt = 7 } } },
                ["Realm Two"] = { Zzyxa = { knownRecipes = { Ore = 3 } } },
                [""] = { Zzyxa = { knownRecipes = { Fish = 9 } } },
            },
        }
        local api, env = Start(saved, "", "Player-6928-0000ABCD")
        api:GetRealmKey()
        local recipes = env.CaerdonRecipeData
        Check(recipes["Realm One"] ~= nil and recipes["Realm Two"] ~= nil, "two realms: neither is taken for this server")
        Equal(recipes["server 6928"].Zzyxa.knownRecipes.Fish, 9, "two realms: what was filed under the empty key is the toon's")
        local taken = api:GetRealmTakeOver()
        Check(taken ~= nil and taken.from == nil and taken.candidates == 2, "two realms: and the export says two hold the name")
    end

    -- A toon nothing was saved for: a table of its own, and no old realm touched.
    do
        local saved = { CaerdonRecipeData = { ["Old Realm Name"] = { Other = { knownRecipes = { Ore = 3 } } } } }
        local api, env = Start(saved, "", "Player-6928-0000ABCD")
        api:GetRealmKey()
        Check(env.CaerdonRecipeData["Old Realm Name"] ~= nil and env.CaerdonRecipeData["Old Realm Name"].Other ~= nil,
            "new toon: a realm that does not hold the toon's name is left as it is")
        Check(type(env.CaerdonRecipeData["server 6928"]) == "table" and type(env.CaerdonRecipeData["server 6928"].Zzyxa) == "table",
            "new toon: and the toon is filed under the server's number")
    end

    -- Another server's toons, saved under their own number, are not an old realm.
    do
        local saved = { CaerdonRecipeData = { ["server 5000"] = { Zzyxa = { knownRecipes = { Ore = 3 } } } } }
        local api, env = Start(saved, "", "Player-6928-0000ABCD")
        api:GetRealmKey()
        Check(env.CaerdonRecipeData["server 5000"] ~= nil and env.CaerdonRecipeData["server 5000"].Zzyxa.knownRecipes.Ore == 3,
            "another server: a toon of the same name under another server's number is not taken")
    end

    -- No name and no GUID yet: nothing to file under, and nothing is kept for the session.
    do
        local api = Start({}, "", nil)
        Equal((api:GetRealmKey()), nil, "no GUID: no key while the client names neither realm nor toon")
    end
end
