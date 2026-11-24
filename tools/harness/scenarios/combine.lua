-- The combine icon of an item in the bags, which is read off its use spell's text, when the
-- client has not loaded that text yet.
--
-- A retail client showed the case: after a login the icon was missing on whichever items'
-- spells were not loaded, and there after a reload. Here the game is hand-made: a spell's
-- text is empty until its data has been asked for and has come. The items are made from their
-- IDs and told they lie in a bag slot, which is all the status code asks of a slot here.
--
-- Real code: the addon's item side, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Druid", classFile = "DRUID", race = "Tauren",
        faction = "Horde", level = 90 }

    local function Thing(name, spellID)
        return { name = name, quality = 2, level = 1, minLevel = 0, type = "Miscellaneous", subType = "Other",
            stack = 20, price = 0, classID = 15, subClassID = 4, spell = { name = name .. " Use", id = spellID } }
    end

    local ITEMS = {
        [940001] = Thing("Ready Ledger", 7001),     -- its spell's text is loaded
        [940002] = Thing("Late Handiwork", 7002),   -- its text comes when asked for
        [940003] = Thing("Lost Rebar", 7003),       -- the client has no data for its spell
        [940004] = Thing("Plain Recipe", 7004),     -- loaded, and has no text
        [940005] = Thing("Late Recipe", 7005),      -- comes when asked for, and has no text
        [940006] = Thing("Late Twin", 7002),        -- the same spell as the handiwork
    }
    local TEXT = { [7001] = "Combine 5 of these into a ledger.", [7002] = "Combine 10 of these into a handiwork.",
        [7004] = "", [7005] = "" }

    local loaded, asked, slotOf = { [7001] = true, [7004] = true }, {}, {}
    local refreshes = 0

    local game = H.StockGame(TOON, ITEMS)
    game:Set("C_Spell.IsSpellDataCached", function(spellID) return loaded[spellID] == true end)
    game:Set("C_Spell.GetSpellDescription", function(spellID) return loaded[spellID] and TEXT[spellID] or "" end)
    game:Set("C_Spell.IsSpellUsable", function() return true end)
    game:Set("C_Spell.RequestLoadSpellData", function(spellID)
        asked[spellID] = (asked[spellID] or 0) + 1
        local client = game.client
        client.env.C_Timer.After(0, function()
            if TEXT[spellID] ~= nil then
                loaded[spellID] = true
            end
            client:Fire("SPELL_DATA_LOAD_RESULT", spellID, TEXT[spellID] ~= nil)
        end)
    end)
    game:Set("C_Container.GetContainerItemInfo", function(bag, slot)
        local id = slotOf[slot]
        return id and { itemID = id, stackCount = 1, hyperlink = game.Link(id), isLocked = false, quality = 2,
            isReadable = false, hasLoot = false } or nil
    end)
    game:Set("C_Container.GetContainerItemPurchaseInfo", function() return nil end)
    game:Set("C_Item.GetStackCount", function() return 1 end)

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
    local env = client.env
    Equal(#client.errors, 0, "start: no error reached the error handler")

    local core = env.CaerdonWardrobe
    Check(type(core) == "table" and type(core.RefreshItems) == "function", "start: the core is there to be asked for a refresh")
    local refreshItems = core.RefreshItems
    function core:RefreshItems(...)
        refreshes = refreshes + 1
        return refreshItems(self, ...)
    end

    -- An item made from its ID and told which bag slot it lies in.
    local nextSlot = 0
    local function InBags(itemID)
        local item = env.CaerdonItem:CreateFromItemID(itemID)
        local ready = false
        item:ContinueOnItemLoad(function() ready = true end)
        client:TickUntil(function() return ready end, 10)
        nextSlot = nextSlot + 1
        local slot = nextSlot
        slotOf[slot] = itemID
        local location = {
            GetBagAndSlot = function() return 0, slot end,
            HasAnyLocation = function() return true end,
            IsBagAndSlot = function() return true end,
        }
        function item:HasItemLocationBankOrBags() return true end
        function item:GetItemLocation() return location end
        return item
    end

    local function Status(item)
        local ready, status = item:GetCaerdonStatus()
        return ready and (status or "") or "<not ready>"
    end

    local ready, late, lost = InBags(940001), InBags(940002), InBags(940003)
    local plain, lateRecipe, twin = InBags(940004), InBags(940005), InBags(940006)
    refreshes, asked = 0, {}

    -- The first draw, as after a login.
    Equal(Status(ready), "canCombine", "first draw: a loaded text is read")
    Equal(asked[7001], nil, "first draw: and its data is not asked for")
    Equal(Status(late), "", "first draw: an unloaded text gives no icon yet")
    Equal(asked[7002], 1, "first draw: its data is asked for")
    Equal(Status(twin), "", "first draw: nor for the second item with that spell")
    Equal(Status(late), "", "first draw: asked again before the answer, still none")
    Equal(asked[7002], 1, "first draw: and the data is asked for once, whoever asks")
    Equal(Status(lost), "", "first draw: a spell the client has no data for gives no icon")
    Equal(asked[7003], 1, "first draw: its data is asked for")
    Equal(Status(plain), "", "first draw: a loaded spell with no text gives no icon")
    Equal(asked[7004], nil, "first draw: and is not asked for")
    Equal(Status(lateRecipe), "", "first draw: an unloaded spell with no text gives no icon")
    Equal(asked[7005], 1, "first draw: its data is asked for")
    Equal(refreshes, 0, "first draw: nothing refreshed yet")

    -- The answers come.
    client:Tick(20)
    Equal(refreshes, 1, "answers: one refresh, for the one text that came (not for the spell without a text, not for the one without data)")
    Equal(Status(late), "canCombine", "answers: the late text is read now")
    Equal(Status(twin), "canCombine", "answers: for both items with that spell")
    Equal(Status(ready), "canCombine", "answers: the first item is as it was")
    Equal(Status(lost), "", "answers: no data, no icon")
    Equal(Status(lateRecipe), "", "answers: no text, no icon")

    -- Later refreshes ask the client for nothing again and cause no refresh of their own.
    core:RefreshItems()
    client:Tick(20)
    refreshes = 0
    Equal(Status(late), "canCombine", "later: still read")
    Equal(Status(lost), "", "later: still none for the spell without data")
    Equal(Status(lateRecipe), "", "later: still none for the spell without a text")
    client:Tick(20)
    Equal(asked[7002], 1, "later: the late spell was asked for once in all")
    Equal(asked[7003], 1, "later: so was the one without data, although it is still not loaded")
    Equal(asked[7005], 1, "later: and the one without a text")
    Equal(refreshes, 0, "later: no refresh comes of it")

    Equal(#client.errors, 0, "end: no error reached the error handler")
    for _, message in ipairs(client.errors) do
        Check(false, "error: " .. message)
    end
end
