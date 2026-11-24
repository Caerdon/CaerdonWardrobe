-- A Pet Cage, and the one thing a feature's GetTooltipData is asked for.
--
-- A caged battle pet in the mail or a guild bank is the item 82800 for every pet, so its link
-- says nothing about the pet: the tooltip of the place it lies in does (battlePetSpeciesID),
-- and the status asks the feature for that (CaerdonItemMixin:GetCaerdonStatus,
-- FeatureMixin:GetTooltipData). Every other item is judged from its link's tooltip, and a
-- feature with no such place has no getter of its own.
--
-- The cage was known by its English name, so in any other language it was judged from its
-- link like any item, and every cage was the same cage. It is known by its ID now.
--
-- Hand-made, all of it: no recording holds a cage, and WoW Forever has no battle pets. The
-- item's class is the listing's Enum.ItemClass.Battlepet; the non-English name stands for
-- "any name that is not the English one" and is not a client's. What a client's mail or guild
-- bank tooltip of a cage carries beside battlePetSpeciesID has not been recorded.
--
-- Real code: the addon's item side, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Druid", classFile = "DRUID", race = "NightElf",
        faction = "Alliance", level = 80 }

    local CAGE, POTION = 82800, 990001
    local KNOWN_SPECIES, NEW_SPECIES = 39, 40
    local function Items(cageName)
        return {
            [CAGE] = { name = cageName, quality = 3, level = 1, minLevel = 0, type = "Battle Pets", subType = "BattlePet",
                stack = 1, equipLoc = "", price = 0, classID = 17, subClassID = 0, tooltip = {} },
            [POTION] = { name = "Test Potion", quality = 1, level = 10, minLevel = 5, type = "Consumable", subType = "Potion",
                stack = 5, equipLoc = "", price = 25, classID = 0, subClassID = 1, tooltip = {} },
        }
    end

    local function Start(cageName)
        local items = Items(cageName)
        local game = H.StockGame(TOON, items)
        game:Set("GetBuildInfo", function() return "12.1.5", "70961", "Nov 1 2026", 120105 end)
        game:Set("WOW_PROJECT_ID", 1)
        game:Set("C_PetJournal.GetNumCollectedInfo", function(speciesID)
            if tonumber(speciesID) == KNOWN_SPECIES then
                return 1, 3
            elseif tonumber(speciesID) == NEW_SPECIES then
                return 0, 3
            end
            return nil
        end)
        game:Set("C_PetJournal.GetPetInfoBySpeciesID", function() return nil end)
        local client = H.Client.New({ flavor = "retail", provider = game })
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
        return client, game
    end

    local function Run(label, cageName)
        local client, game = Start(cageName)
        local env = client.env
        Equal(#client.errors, 0, label .. ": the addon starts without an error")

        local function Item(itemID)
            local item = env.CaerdonItem:CreateFromItemID(itemID)
            local loaded = false
            item:ContinueOnItemLoad(function() loaded = true end)
            client:TickUntil(function() return loaded end, 10)
            return item
        end

        -- A window whose places have tooltips of their own, as the mail has.
        local asked = 0
        local placeTooltip
        local window = env.CreateFromMixins(env.CaerdonWardrobeFeatureMixin)
        function window:GetTooltipData(item, locationInfo)
            asked = asked + 1
            return placeTooltip
        end
        local function CageTooltip(speciesID)
            return { type = 0, id = CAGE, battlePetSpeciesID = speciesID, battlePetLevel = 1,
                lines = { { type = 0, leftText = cageName, leftColor = env.CreateColor(1, 1, 1, 1) } } }
        end
        local function Status(item, feature)
            local ready, status
            client:TickUntil(function()
                ready, status = item:GetCaerdonStatus(feature, { index = 1 })
                return ready
            end, 10)
            return status
        end

        local cage = Item(CAGE)
        Equal(cage:GetStatusCacheKey(), nil, label .. ": a cage has no cache key")

        placeTooltip = CageTooltip(NEW_SPECIES)
        Equal(Status(cage, window), "own", label .. ": a pet the toon has none of is one to learn")
        Equal(asked, 1, label .. ": the window was asked for the place's tooltip")
        placeTooltip = CageTooltip(KNOWN_SPECIES)
        Equal(Status(cage, window), "", label .. ": a pet it has is not")
        Equal(asked, 2, label .. ": and asked again, since no verdict about a cage is kept")
        placeTooltip = CageTooltip(NEW_SPECIES)
        Equal(Status(cage, window), "own", label .. ": the next cage is judged for itself")

        -- A window with no place of its own: the mixin's getter, which answers nothing.
        local plain = env.CreateFromMixins(env.CaerdonWardrobeFeatureMixin)
        Equal(plain:GetTooltipData(cage, {}), nil, label .. ": a feature without a getter of its own answers nothing")
        Equal(Status(cage, plain), "", label .. ": and the cage is judged from its link, which names no pet")
        Equal(Status(cage, nil), "", label .. ": as it is with no feature at all")
        -- A place whose tooltip the client does not have, and one with no lines.
        placeTooltip = nil
        Equal(Status(cage, window), "", label .. ": a place with no tooltip is the link's")
        placeTooltip = { type = 0, id = CAGE }
        Equal(Status(cage, window), "", label .. ": a tooltip without lines is read as one with none")

        -- Any other item is never asked of the window.
        asked = 0
        local potion = Item(POTION)
        Check(potion:GetStatusCacheKey() ~= nil, label .. ": another item has a cache key")
        Status(potion, window)
        Status(potion, window)
        Equal(asked, 0, label .. ": the window is not asked about another item")

        Equal(#client.errors, 0, label .. ": no error reached the error handler")
        for _, message in ipairs(client.errors) do
            print("        error: " .. tostring(message))
        end
    end

    Run("another language", "Haustierkäfig")
    Run("English", "Pet Cage")

    -- No feature keeps a getter that only asks for the link's tooltip, which is what the
    -- status does by itself. Read from the files' text.
    local function Walk(dir, found)
        for _, entry in ipairs(H.ListDir(dir, true) or {}) do
            Walk(dir .. "/" .. entry, found)
        end
        for _, file in ipairs(H.ListDir(dir) or {}) do
            if file:match("%.lua$") then
                found[#found + 1] = dir .. "/" .. file
            end
        end
        return found
    end
    local files = Walk(H.addonDir .. "/external", Walk(H.addonDir .. "/features", {}))
    Check(#files > 40, "feature files: found (" .. #files .. ")")
    local getters = 0
    for _, path in ipairs(files) do
        if not path:find("/deprecated/", 1, true) then
            local text = (H.ReadFile(path) or ""):gsub("\r", "")
            for body in text:gmatch("\nfunction [%w_]+:GetTooltipData%([^\n]*\n(.-)\nend\n") do
                getters = getters + 1
                local code = body:gsub("%-%-[^\n]*", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
                local short = path:gsub("^.*/%.%./%.%./", "")
                Check(code ~= "" and code ~= "return {}" and code ~= "return nil", short .. ": its getter answers something")
                Check(code ~= "return C_TooltipInfo.GetHyperlink(item:GetItemLink())",
                    short .. ": its getter is more than the link's tooltip")
            end
        end
    end
    Check(getters >= 20, "feature files: getters for a place are still there (" .. getters .. ")")
end
