-- What the addon's code makes of the housing catalog's answers: the counts it reads off an
-- entry, the lookup by record when the item's entry says nothing is owned, and the status
-- that comes of each.
--
-- The catalog answers in the shape it has since 12.0.5 (recordID, entryType, totalNumStored,
-- totalNumPlaced on the entry itself), written by hand from Blizzard's description of it in
-- Blizzard_Deprecated/Mainline/Deprecated_12_0_5.lua. So this proves what the code decides
-- from such answers, and nothing about what a client answers. Housing is retail only: the
-- client here says it is retail.
--
-- Real code: the addon's item side, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Druid", classFile = "DRUID", race = "Tauren",
        faction = "Horde", level = 90 }
    local DECOR, ROOM = 1, 2                                   -- Enum.HousingCatalogEntryType
    local SUB_DECOR, SUB_DYE, SUB_SERVICE = 0, 1, 5            -- Enum.ItemHousingSubclass

    local function Housing(name, subClassID, more)
        local item = { name = name, quality = 1, level = 1, minLevel = 0, type = "Housing", subType = "Decor",
            stack = 20, price = 100, classID = 20, subClassID = subClassID or SUB_DECOR }
        for key, value in pairs(more or {}) do
            item[key] = value
        end
        return item
    end

    local function Entry(recordID, stored, placed, more)
        local entry = { recordID = recordID, entryType = DECOR, totalNumStored = stored, totalNumPlaced = placed,
            remainingRedeemable = 0, firstAcquisitionBonus = 0, iconAtlas = "housing-decor-" .. recordID,
            sourceText = "Vendor" }
        for key, value in pairs(more or {}) do
            entry[key] = value
        end
        return entry
    end

    local ITEMS = {
        [920001] = Housing("Sturdy Chair"),        -- five stored, one placed
        [920002] = Housing("Placed Lamp"),         -- none stored, six placed
        [920003] = Housing("Unowned Rug"),         -- none, with a first acquisition bonus
        [920004] = Housing("Crated Vase"),         -- the catalog knows nothing; two in the bags
        [920005] = Housing("Twin Record Stool"),   -- nothing by item, two stored by its ID as a record
        [920006] = Housing("Redeemable Bench"),    -- none stored, three still to redeem
        [920007] = Housing("Full Shelf", SUB_DECOR, { stack = 5 }), -- at its limit
        [920008] = Housing("Azure Dye", SUB_DYE),
        [920009] = Housing("House Call", SUB_SERVICE), -- a service item, one in the bags
        [920010] = Housing("Unknown Crate"),       -- nothing anywhere: still on its way
        [920011] = Housing("Redeemable Twin"),     -- three to redeem, and an entry under its ID as a record
        -- Service items the catalog knows nothing about and the bags do not hold (a warband
        -- bank copy is not counted): one whose tooltip says the toon knows what it teaches,
        -- as the Harvesting Hatchet's did in a retail client, and one that does not.
        [920012] = Housing("Known Hatchet", SUB_SERVICE,
            { tooltip = { { text = "Already known", type = 0, r = 1, g = 0.125, b = 0.125 } } }),
        [920013] = Housing("New Hatchet", SUB_SERVICE),
    }
    local BY_ITEM = {
        [920001] = Entry(501, 5, 1),
        [920002] = Entry(502, 0, 6),
        [920003] = Entry(503, 0, 0, { firstAcquisitionBonus = 25 }),
        [920005] = Entry(505, 0, 0),
        [920006] = Entry(506, 0, 0, { remainingRedeemable = 3 }),
        [920007] = Entry(507, 4, 1),
        [920011] = Entry(511, 0, 0, { remainingRedeemable = 3 }),
    }
    local BY_RECORD = {
        [DECOR .. ":" .. 920005] = Entry(920005, 2, 0),
        [DECOR .. ":" .. 920011] = Entry(920011, 7, 0),
    }
    local IN_BAGS = { [920004] = 2, [920009] = 1 }

    local asked = {}

    local function Start()
        local game = H.StockGame(TOON, ITEMS)
        game:Set("GetBuildInfo", function() return "12.1.5", "70783", "Nov 1 2026", 120105 end)
        game:Set("WOW_PROJECT_ID", 1)
        game:Set("C_Item.GetItemCount", function(itemID) return IN_BAGS[itemID] or 0 end)
        -- A table of its own for every answer, as the client gives one.
        game:Set("C_HousingCatalog.GetCatalogEntryInfoByItem", function(link, ...)
            asked[#asked + 1] = { "byItem", select("#", ...) }
            local entry = BY_ITEM[tonumber(tostring(link):match("item:(%d+)")) or link]
            return entry and H.DeepCopy(entry) or nil
        end)
        game:Set("C_HousingCatalog.GetCatalogEntryInfoByRecordID", function(entryType, recordID, ...)
            asked[#asked + 1] = { "byRecord", select("#", ...) }
            local entry = BY_RECORD[tostring(entryType) .. ":" .. tostring(recordID)]
            return entry and H.DeepCopy(entry) or nil
        end)
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
        return client
    end

    local client = Start()
    local env = client.env
    Equal(#client.errors, 0, "start: no error reached the error handler")

    local function Load(itemID)
        local item = env.CaerdonItem:CreateFromItemID(itemID)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        client:TickUntil(function() return loaded end, 10)
        return loaded and item or nil
    end

    local function Info(itemID)
        local item = Load(itemID)
        Check(item ~= nil, itemID .. ": the item loads")
        if not item then
            return {}, nil
        end
        Equal(item:GetCaerdonItemType(), env.CaerdonItemType.Housing, itemID .. ": it is a housing item to the addon")
        local data = item:GetItemData()
        return data and data.GetHousingInfo and data:GetHousingInfo() or {}, item
    end

    local function Status(item)
        local ready, status = item:GetCaerdonStatus()
        return ready and (status or "") or "<not ready>"
    end

    -- Stored and placed: the entry's totals.
    do
        local info, item = Info(920001)
        Equal(info.ownedStored, 5, "stored and placed: stored")
        Equal(info.placedCount, 1, "stored and placed: placed")
        Equal(info.totalOwned, 6, "stored and placed: owned in all")
        Equal(info.isUnowned, false, "stored and placed: not unowned")
        Equal(info.showQuantity, true, "stored and placed: there is a quantity to show")
        Equal(info.recordID, 501, "stored and placed: the entry's record")
        Equal(info.entryType, DECOR, "stored and placed: the entry's type")
        Equal(info.iconAtlas, "housing-decor-501", "stored and placed: the entry's icon")
        Equal(info.usedRecordFallback, nil, "stored and placed: the lookup by record is not needed")
        Equal(info.isPending, false, "stored and placed: nothing is on its way")
        Equal(item and Status(item), "housingOwned", "stored and placed: status")
    end

    -- Every copy placed: owned although nothing is stored.
    do
        local info, item = Info(920002)
        Equal(info.ownedStored, 0, "all placed: none stored")
        Equal(info.placedCount, 6, "all placed: placed")
        Equal(info.totalOwned, 6, "all placed: owned in all")
        Equal(info.isUnowned, false, "all placed: not unowned")
        Equal(info.showQuantity, false, "all placed: no stored quantity to show")
        Equal(item and Status(item), "housingOwned", "all placed: status")
    end

    -- Not owned: something to get, with its bonus.
    do
        local info, item = Info(920003)
        Equal(info.totalOwned, 0, "unowned: nothing owned")
        Equal(info.isUnowned, true, "unowned: unowned")
        Equal(info.firstAcquisitionBonus, 25, "unowned: the first acquisition bonus")
        Equal(info.recordID, 503, "unowned: the record stays the entry's own")
        Equal(info.usedRecordFallback, nil, "unowned: the lookup by record found nothing")
        Equal(info.isPending, false, "unowned: an entry is an answer")
        Equal(item and Status(item), "own", "unowned: status")
    end

    -- No entry, copies in the bags: not redeemed yet, so not owned, and not waited for.
    do
        local info, item = Info(920004)
        Equal(info.bagCount, 2, "in the bags: counted")
        Equal(info.totalOwned, 0, "in the bags: a copy in the bags is not owned decor")
        Equal(info.isPending, false, "in the bags: nothing to wait for")
        Equal(item and Status(item), "own", "in the bags: status")
    end

    -- Nothing owned by the item's entry, and an entry under the item's ID as a record: that
    -- one is taken. (Whether an item's ID is ever its record's is the client's to say.)
    do
        local info, item = Info(920005)
        Equal(info.usedRecordFallback, true, "by record: the lookup by record answered")
        Equal(info.recordFromItem, 505, "by record: what the item's own entry said is kept for the export")
        Equal(info.recordID, 920005, "by record: the record is the one found")
        Equal(info.ownedStored, 2, "by record: its stored count")
        Equal(info.totalOwned, 2, "by record: owned")
        Equal(item and Status(item), "housingOwned", "by record: status")
    end

    -- Still to redeem counts as owned, once, not on top of what is stored.
    do
        local info, item = Info(920006)
        Equal(info.remainingRedeemable, 3, "redeemable: read")
        Equal(info.totalOwned, 3, "redeemable: owned")
        Equal(info.showQuantity, true, "redeemable: a quantity to show")
        Equal(item and Status(item), "housingOwned", "redeemable: status")
    end

    -- What is still to redeem is owned already: the lookup by record is not asked, whatever
    -- it would say.
    do
        local info = Info(920011)
        Equal(info.usedRecordFallback, nil, "redeemable twin: the lookup by record is not used")
        Equal(info.recordID, 511, "redeemable twin: the record is the item's own entry")
        Equal(info.totalOwned, 3, "redeemable twin: owned is what is to redeem")
    end

    -- At the item's limit (its stack size, which also caps the counts read): nothing more to
    -- do with another copy.
    do
        local info, item = Info(920007)
        Equal(info.maxStack, 5, "at the limit: the limit")
        Equal(info.totalOwned, 5, "at the limit: owned")
        Equal(item and Status(item), "", "at the limit: no status")
    end

    -- A dye gets no icon, owned or not, and is not waited for: the catalog has no entry for
    -- a dye.
    do
        local info, item = Info(920008)
        Equal(info.isDye, true, "dye: known as one")
        Equal(info.isPending, false, "dye: nothing is on its way")
        Equal(item and Status(item), "", "dye: no status")
    end

    -- A service item counts the copy in the bags.
    do
        local info, item = Info(920009)
        Equal(info.isServiceItem, true, "service: known as one")
        Equal(info.totalOwned, 1, "service: the copy in the bags counts")
        Equal(item and Status(item), "housingOwned", "service: status")
    end

    -- A service item away from the bags, with no entry: not waited for either. What it shows
    -- is the tooltip's to say: nothing once the toon knows what it teaches.
    do
        local info, item = Info(920012)
        Equal(info.isPending, false, "known service item: nothing is on its way")
        Equal(info.totalOwned, 0, "known service item: no count says it is owned")
        Equal(item and Status(item), "", "known service item: no status, although nothing counts as owned")
        info, item = Info(920013)
        Equal(info.isPending, false, "new service item: nothing is on its way")
        Equal(item and Status(item), "own", "new service item: something to get")
    end

    -- Nothing known anywhere: still on its way.
    do
        local info = Info(920010)
        Equal(info.isPending, true, "nothing known: pending")
        Equal(info.totalOwned, 0, "nothing known: nothing owned")
    end

    -- The catalog is asked the way it is asked since 12.0.5: no "try owned" argument.
    do
        local extra = 0
        for _, call in ipairs(asked) do
            extra = extra + call[2]
        end
        Check(#asked > 0, "calls: the catalog was asked")
        Equal(extra, 0, "calls: with no argument beyond the item, or the type and the record")
        Equal(rawget(env, "C_HousingCatalog") and rawget(env.C_HousingCatalog, "GetCatalogEntryInfo"), nil,
            "calls: and never for an entry by its old compound ID")
    end

    Equal(#client.errors, 0, "end: no error reached the error handler")
    for _, message in ipairs(client.errors) do
        Check(false, "error: " .. message)
    end
end
