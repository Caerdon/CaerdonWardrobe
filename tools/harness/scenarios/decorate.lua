-- A window's button handed over by what the window has for it (CaerdonWardrobe:Decorate).
--
-- A window that shows items it does not hold (a vendor's page, a list's row) has a link or an
-- ID, and the item's data may not be with the client yet. The button is asked for once the
-- data is, and by then the row may show something else: the page was turned, the row was
-- cleared, the window asked again. Decorate owns that wait and lets a late answer draw only
-- where nothing was said about the button in between.
--
--   1. What it is given: a link, an ID, an item the window made, nothing.
--   2. An item whose data is here is asked for at once; one whose data is not, when it comes.
--   3. A row asked for again, or cleared, while its item loads is not drawn by the late answer.
--   4. The vendor window's own file goes through it: a page turned while its items load.
--   5. The auction house's sell slot: an item put in has its icon, and the slot emptied has none.
--   6. An item that answers more than once (a piece of equipment, when the other items of its
--      look have loaded): every answer of a wait asks, until the window says something else.
--
-- In 3 also: what the core itself says about a button while its item loads (a refresh, a
-- retry, a request the queue drops) is not the window's word, and a row that is two buttons
-- (WhenItemLoaded).
--
-- The game is hand-made, and the scenario says when an item's data comes. Real code: the core,
-- FeatureMixin.lua, CaerdonItem.lua and features/Merchant.lua.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 29 }

    local function Start(flavor, more)
        local items = {}
        for id = 940001, 940024 do
            items[id] = { name = "Scrap " .. id, quality = 1, level = 5, minLevel = 0, type = "Miscellaneous", subType = "Junk",
                stack = 20, price = 5, classID = 15, subClassID = 0 }
        end
        for id, item in pairs(more or {}) do
            items[id] = item
        end
        local game = H.StockGame(TOON, items)
        local world = { game = game, asked = {}, cleared = {}, held = {}, here = {}, notSame = {} }

        -- An item's data is with the client once the scenario says so (Arrive). The client is
        -- asked by ID or by link.
        local function IDOf(reference)
            return tonumber(reference) or tonumber(tostring(reference):match("item:(%d+)"))
        end
        game:Set("C_Item.IsItemDataCachedByID", function(reference) return world.here[IDOf(reference)] == true end)
        -- As the client: an item it has is answered from inside the call.
        game:Set("C_Item.RequestLoadItemDataByID", function(reference)
            local id = IDOf(reference)
            if world.here[id] then
                world.client:Fire("ITEM_DATA_LOAD_RESULT", id, true)
            else
                world.held[id] = true
            end
        end)

        local client = H.Client.New({ flavor = flavor, provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))

        local WindowMixin = {}
        function WindowMixin:GetName() return "Window" end
        function WindowMixin:Init() end
        function WindowMixin:GetTooltipData() return nil end
        -- A row the scenario says shows another item by now (the queue asks before it draws).
        function WindowMixin:IsSameItem(button) return not world.notSame[button] end
        client.env.CaerdonWardrobe:RegisterFeature(WindowMixin)

        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(10)

        world.client, world.env, world.namespace = client, client.env, namespace
        local core = client.env.CaerdonWardrobe
        world.core, world.window = core, core:GetFeature("Window")

        -- What the core is asked for and what is cleared, in the order it happens. The real
        -- functions run all the same.
        local realUpdate, realClear = core.UpdateButton, core.ClearButton
        function core:UpdateButton(button, item, feature, locationInfo, options)
            world.asked[#world.asked + 1] = { button = button, id = item and item:GetItemID(), item = item,
                key = locationInfo and locationInfo.locationKey }
            return realUpdate(self, button, item, feature, locationInfo, options)
        end
        function core:ClearButton(button)
            world.cleared[button] = (world.cleared[button] or 0) + 1
            return realClear(self, button)
        end

        -- The drawing is not this scenario's: what is asked for is.
        function core:SetItemButtonStatus() end
        function core:SetItemButtonMogStatusFilter() end
        function core:SetItemButtonBindType() end

        function world.Arrive(id)
            world.here[id] = true
            if world.held[id] then
                world.held[id] = nil
                client:Fire("ITEM_DATA_LOAD_RESULT", id, true)
            end
        end
        function world.Button()
            local button = client:NewFrame("Button")
            button:SetSize(37, 37)
            return button
        end
        function world.AskedFor(button)
            local ids = {}
            for _, ask in ipairs(world.asked) do
                if ask.button == button then
                    ids[#ids + 1] = tostring(ask.id)
                end
            end
            return table.concat(ids, ",")
        end
        function world.TimesAsked(button)
            local count = 0
            for _, ask in ipairs(world.asked) do
                if ask.button == button then
                    count = count + 1
                end
            end
            return count
        end
        return world
    end

    for _, flavor in ipairs({ "forever", "retail" }) do
        local label = flavor .. ": "
        local world = Start(flavor)
        local core, client, window, game = world.core, world.client, world.window, world.game
        local CaerdonItem = world.env.CaerdonItem

        ----------------------------------------------------------------------------------
        -- 1. What it is given
        ----------------------------------------------------------------------------------

        world.Arrive(940001)
        world.Arrive(940002)
        world.Arrive(940003)
        local byLink, byID, byItem, byNothing = world.Button(), world.Button(), world.Button(), world.Button()
        local item = window:Decorate(byLink, game.Link(940001), { locationKey = "row1" }, {})
        Check(item ~= nil and item:GetItemID() == 940001, label .. "given: a link makes its item, which is handed back")
        Equal(world.AskedFor(byLink), "940001", label .. "given: and the button is asked for with it")
        Equal(world.asked[#world.asked].key, "row1", label .. "given: at the place the window named")
        item = window:Decorate(byID, 940002, { locationKey = "row2" }, {})
        Check(item ~= nil and item:GetItemID() == 940002, label .. "given: an ID makes its item")
        Equal(world.AskedFor(byID), "940002", label .. "given: and the button is asked for")
        local made = CaerdonItem:CreateFromItemLink(game.Link(940003), { ownCopy = true })
        item = window:Decorate(byItem, made, { locationKey = "row3" }, {})
        Check(item == made, label .. "given: an item the window made is the one used")
        Check(world.asked[#world.asked].item == made, label .. "given: with what the window put on it")
        Equal(window:Decorate(byNothing, nil, { locationKey = "row4" }, {}), nil, label .. "given: nothing gives no item")
        Equal(world.cleared[byNothing], 1, label .. "given: and the button is cleared")
        Equal(world.AskedFor(byNothing), "", label .. "given: and not asked for")
        client:Tick(5)
        Equal(#client.errors, 0, label .. "given: no error (" .. tostring(client.errors[1]) .. ")")

        ----------------------------------------------------------------------------------
        -- 2. The wait
        ----------------------------------------------------------------------------------

        local waits = world.Button()
        window:Decorate(waits, game.Link(940004), { locationKey = "wait" }, {})
        Equal(world.AskedFor(waits), "", label .. "wait: a button is not asked for before its item's data is here")
        client:Tick(5)
        Equal(world.AskedFor(waits), "", label .. "wait: however long that takes")
        world.Arrive(940004)
        client:Tick(2)
        Equal(world.AskedFor(waits), "940004", label .. "wait: and once when it comes")

        ----------------------------------------------------------------------------------
        -- 3. A row that has moved on
        ----------------------------------------------------------------------------------

        -- Asked for again with another item whose data is here: the page was turned.
        local turned = world.Button()
        window:Decorate(turned, game.Link(940005), { locationKey = "turned" }, {})
        window:Decorate(turned, game.Link(940001), { locationKey = "turned" }, {})
        world.Arrive(940005)
        client:Tick(2)
        Equal(world.AskedFor(turned), "940001", label .. "moved on: the item of the page before is not drawn over the row")

        -- Both still loading, and the earlier one's data comes last.
        local both = world.Button()
        window:Decorate(both, game.Link(940006), { locationKey = "both" }, {})
        window:Decorate(both, game.Link(940007), { locationKey = "both" }, {})
        world.Arrive(940007)
        client:Tick(2)
        world.Arrive(940006)
        client:Tick(2)
        Equal(world.AskedFor(both), "940007", label .. "moved on: of two that load, the one asked for last is the one drawn")

        -- Both still loading, and the earlier one's data comes first.
        local inOrder = world.Button()
        window:Decorate(inOrder, game.Link(940013), { locationKey = "inOrder" }, {})
        window:Decorate(inOrder, game.Link(940014), { locationKey = "inOrder" }, {})
        world.Arrive(940013)
        client:Tick(2)
        Equal(world.AskedFor(inOrder), "", label .. "moved on: the earlier of two is not drawn when its data comes first")
        world.Arrive(940014)
        client:Tick(2)
        Equal(world.AskedFor(inOrder), "940014", label .. "moved on: and the later one is, when its own comes")

        -- The page turned, and turned back before the other page's item came: the row has the
        -- item it had, whose data is here, and the button's item never changed.
        local back = world.Button()
        window:Decorate(back, game.Link(940001), { locationKey = "back" }, {})
        client:Tick(2)
        window:Decorate(back, game.Link(940015), { locationKey = "back" }, {})
        window:Decorate(back, game.Link(940001), { locationKey = "back" }, {})
        world.Arrive(940015)
        client:Tick(2)
        Equal(world.AskedFor(back), "940001,940001", label .. "moved on: a page turned and turned back keeps the row's own item")

        -- Cleared while it loads.
        local emptied = world.Button()
        window:Decorate(emptied, game.Link(940008), { locationKey = "emptied" }, {})
        window:Decorate(emptied, nil, { locationKey = "emptied" }, {})
        world.Arrive(940008)
        client:Tick(2)
        Equal(world.AskedFor(emptied), "", label .. "moved on: a row cleared while its item loaded stays clear")

        -- Cleared by the core's own function, and asked for by it.
        local byCore = world.Button()
        window:Decorate(byCore, game.Link(940009), { locationKey = "byCore" }, {})
        core:ClearButton(byCore)
        world.Arrive(940009)
        client:Tick(2)
        Equal(world.AskedFor(byCore), "", label .. "moved on: so does one the window cleared itself")
        local direct = world.Button()
        window:Decorate(direct, game.Link(940010), { locationKey = "direct" }, {})
        core:UpdateButton(direct, CaerdonItem:CreateFromItemLink(game.Link(940002)), window, { locationKey = "direct" }, {})
        world.Arrive(940010)
        client:Tick(2)
        Equal(world.AskedFor(direct), "940002", label .. "moved on: and one the window asked for itself keeps that")

        -- Asked for by the window itself with the item the button already had: nothing is
        -- cleared for that, and the other item's late answer is still not the row's.
        local kept = world.Button()
        local own = CaerdonItem:CreateFromItemLink(game.Link(940003))
        core:UpdateButton(kept, own, window, { locationKey = "kept" }, {})
        client:Tick(2)
        window:Decorate(kept, game.Link(940016), { locationKey = "kept" }, {})
        core:UpdateButton(kept, own, window, { locationKey = "kept" }, {})
        world.Arrive(940016)
        client:Tick(2)
        Equal(world.AskedFor(kept), "940003,940003", label .. "moved on: nor is a row the window asked for again with the item it had")

        -- The same item asked for twice while it loads: one request, not two.
        local twice = world.Button()
        window:Decorate(twice, game.Link(940011), { locationKey = "twice" }, {})
        window:Decorate(twice, game.Link(940011), { locationKey = "twice" }, {})
        world.Arrive(940011)
        client:Tick(2)
        Equal(world.AskedFor(twice), "940011", label .. "moved on: a row asked for twice with one item is asked for once")

        -- Another button's wait is its own.
        local one, other = world.Button(), world.Button()
        window:Decorate(one, game.Link(940012), { locationKey = "one" }, {})
        window:Decorate(other, game.Link(940001), { locationKey = "other" }, {})
        world.Arrive(940012)
        client:Tick(2)
        Equal(world.AskedFor(one), "940012", label .. "moved on: what is said about another button changes nothing for this one")
        Equal(#client.errors, 0, label .. "moved on: no error (" .. tostring(client.errors[1]) .. ")")

        -- What the core says about a button is not its window's word. The row shows the item
        -- that loads all the while, so its answer is still the row's.

        -- A refresh asks again for what the button was last asked for.
        local refreshed = world.Button()
        window:Decorate(refreshed, game.Link(940001), { locationKey = "refreshed" }, {})
        client:Tick(2)
        window:Decorate(refreshed, game.Link(940017), { locationKey = "refreshed" }, {})
        core:RefreshItems("the scenario")
        client:Tick(6)
        Equal(world.AskedFor(refreshed), "940001,940001", label .. "the core's word: a refresh asks again for what the button had")
        world.Arrive(940017)
        client:Tick(2)
        Equal(world.AskedFor(refreshed), "940001,940001,940017", label .. "the core's word: and the item that loaded meanwhile is still drawn")

        -- The queue drops a request whose row shows another item by now, and clears the button.
        local dropped = world.Button()
        core:UpdateButton(dropped, CaerdonItem:CreateFromItemLink(game.Link(940002)), window, { locationKey = "dropped" }, {})
        window:Decorate(dropped, game.Link(940018), { locationKey = "dropped" }, {})
        world.notSame[dropped] = true
        local clearedBefore = world.cleared[dropped] or 0
        client:Tick(2)
        Check((world.cleared[dropped] or 0) > clearedBefore, label .. "the core's word: the queue clears a row that shows another item by now")
        world.notSame[dropped] = nil
        world.Arrive(940018)
        client:Tick(2)
        Equal(world.AskedFor(dropped), "940002,940018", label .. "the core's word: and that item is drawn when it comes")

        -- A verdict that is not ready is asked for again in a moment.
        local retried = world.Button()
        local unready = CaerdonItem:CreateFromItemLink(game.Link(940003))
        function unready:GetCaerdonStatus() return false, "something of the scenario's" end
        core:UpdateButton(retried, unready, window, { locationKey = "retried" }, {})
        client:Tick(2)
        window:Decorate(retried, game.Link(940019), { locationKey = "retried" }, {})
        client:Tick(25)
        Check(world.TimesAsked(retried) >= 2, label .. "the core's word: a verdict that was not ready is asked for again (" ..
            world.AskedFor(retried) .. ")")
        world.Arrive(940019)
        client:Tick(2)
        Equal(world.asked[#world.asked].button == retried and world.asked[#world.asked].id, 940019,
            label .. "the core's word: and the item that loaded meanwhile is drawn all the same")

        -- A draw that fails costs the button its icon.
        local failed = world.Button()
        local broken = CaerdonItem:CreateFromItemLink(game.Link(940003))
        function broken:GetCaerdonStatus() error("the scenario's own error") end
        core:UpdateButton(failed, broken, window, { locationKey = "failed" }, {})
        window:Decorate(failed, game.Link(940020), { locationKey = "failed" }, {})
        clearedBefore = world.cleared[failed] or 0
        client:Tick(2)
        Equal(#client.errors, 1, label .. "the core's word: a draw that fails is reported")
        Check(tostring(client.errors[1]):find("the scenario's own error", 1, true) ~= nil,
            label .. "the core's word: as the error it was (" .. tostring(client.errors[1]) .. ")")
        client.errors[1] = nil
        Check((world.cleared[failed] or 0) > clearedBefore, label .. "the core's word: and its button is cleared")
        world.Arrive(940020)
        client:Tick(2)
        Equal(world.AskedFor(failed), "940003,940020", label .. "the core's word: the item that loaded meanwhile is drawn after it")

        -- A row that is two of the core's buttons: one wait, which is the row's.
        local row, part = world.Button(), world.Button()
        local function AskRow(id)
            local item = CaerdonItem:CreateFromItemLink(game.Link(id))
            core:WhenItemLoaded(row, item, function()
                core:UpdateButton(row, item, window, { locationKey = "row" }, {})
                core:UpdateButton(part, item, window, { locationKey = "row-part" }, {})
            end)
        end
        AskRow(940021)
        Equal(world.AskedFor(row) .. "/" .. world.AskedFor(part), "/", label .. "two buttons: neither is asked for before the item's data is here")
        world.Arrive(940021)
        client:Tick(2)
        Equal(world.AskedFor(row) .. "/" .. world.AskedFor(part), "940021/940021", label .. "two buttons: both are when it comes")
        AskRow(940022)
        AskRow(940001)
        world.Arrive(940022)
        client:Tick(2)
        Equal(world.AskedFor(row) .. "/" .. world.AskedFor(part), "940021,940001/940021,940001",
            label .. "two buttons: a row that moved on has neither drawn by the late answer")
        -- The row's own button cleared by the window (its column switched off): the wait is over.
        AskRow(940023)
        core:ClearButton(row)
        world.Arrive(940023)
        client:Tick(2)
        Equal(world.AskedFor(part), "940021,940001", label .. "two buttons: nor one whose row the window cleared")
        -- An item the window has loaded already is answered from inside the call.
        local loaded = CaerdonItem:CreateFromItemLink(game.Link(940002))
        loaded:ContinueOnItemLoad(function() end)
        local answers = 0
        core:WhenItemLoaded(row, loaded, function() answers = answers + 1 end)
        Equal(answers, 1, label .. "two buttons: an item that has its data is answered at once")
        client:Tick(2)
        Equal(answers, 1, label .. "two buttons: and once")
        Equal(#client.errors, 0, label .. "the core's word, two buttons: no error (" .. tostring(client.errors[1]) .. ")")
    end

    --------------------------------------------------------------------------------------
    -- 4. The vendor window
    --------------------------------------------------------------------------------------

    for _, flavor in ipairs({ "forever", "retail" }) do
        local label = flavor .. ", vendor: "
        local world = Start(flavor)
        local core, client, game, env = world.core, world.client, world.game, world.env

        -- A vendor of two pages, one row each; the second page's item is here, the first's is not.
        world.Arrive(940002)
        local page = { [1] = 940001, [2] = 940002 }
        local merchantFrame = client:NewFrame("Frame")
        merchantFrame.page, merchantFrame.selectedTab = 1, 1
        rawset(env, "MerchantFrame", merchantFrame)
        rawset(env, "MERCHANT_ITEMS_PER_PAGE", 1)
        rawset(env, "BUYBACK_ITEMS_PER_PAGE", 1)
        local row = world.Button()
        rawset(env, "MerchantItem1ItemButton", row)
        rawset(env, "MerchantItem1", client:NewFrame("Frame"))
        local buyback = world.Button()
        rawset(env, "MerchantBuyBackItemItemButton", buyback)
        rawset(env, "GetMerchantItemLink", function(index) return page[index] and game.Link(page[index]) or nil end)
        rawset(env, "GetNumBuybackItems", function() return 0 end)
        rawset(env, "GetBuybackItemInfo", function() return nil end)
        rawset(env, "GetBuybackItemLink", function() return nil end)

        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "features/Merchant.lua", world.namespace)
        local vendor = core:GetFeature("Merchant")
        Check(vendor ~= nil, label .. "the file registers its feature")
        if vendor then
            vendor.merchantItems = {}
            function vendor:ShouldFilterItems() return false end
            local ran, problem = pcall(vendor.ProcessMerchantButtons, vendor)
            Check(ran, label .. "the first page is walked (" .. tostring(problem) .. ")")
            Equal(world.AskedFor(row), "", label .. "the row waits for its item's data")
            Check(vendor.merchantItems[1] ~= nil and vendor.merchantItems[1].item ~= nil and
                vendor.merchantItems[1].item:GetItemID() == 940001, label .. "the row's item is kept for the filter")
            merchantFrame.page = 2
            page[1], page[2] = nil, nil
            page[2] = 940002
            ran, problem = pcall(vendor.ProcessMerchantButtons, vendor)
            Check(ran, label .. "the second page is walked (" .. tostring(problem) .. ")")
            Equal(world.AskedFor(row), "940002", label .. "the row is asked for with the second page's item")
            world.Arrive(940001)
            client:Tick(3)
            Equal(world.AskedFor(row), "940002", label .. "and the first page's item, come late, is not drawn over it")
            Equal(world.cleared[buyback] ~= nil, true, label .. "the buyback button with nothing in it is cleared")
        end
        Equal(#client.errors, 0, label .. "no error (" .. tostring(client.errors[1]) .. ")")
    end

    --------------------------------------------------------------------------------------
    -- 5. The auction house's sell slot
    --------------------------------------------------------------------------------------

    -- The window is a stand-in written from the client's own functions, the same in both
    -- flavors (Blizzard_AuctionHouseUI/Shared): AuctionHouseFrameMixin:SetPostItem empties
    -- both slots and fills one; a slot is emptied by its display's SetItemLocation(nil), which
    -- a right click, a drag off the slot and a posted auction all end in, and which never
    -- comes through SetPostItem.
    for _, flavor in ipairs({ "forever", "retail" }) do
        local label = flavor .. ", sell slot: "
        local world = Start(flavor)
        local core, client, game, env = world.core, world.client, world.game, world.env
        world.Arrive(940001)
        -- What is asked for and what is cleared is the matter here, not the copy's verdict.
        function core:ProcessItem() end

        -- One item in the backpack's first slot.
        local function InSlot(location)
            return type(location) == "table" and location.IsBagAndSlot and location:IsBagAndSlot() and
                select(1, location:GetBagAndSlot()) == 0 and select(2, location:GetBagAndSlot()) == 1
        end
        game:Set("C_Item.DoesItemExist", function(location) return InSlot(location) end)
        game:Set("C_Item.GetItemLink", function(location) return InSlot(location) and game.Link(940001) or nil end)
        game:Set("C_Item.GetItemID", function(location) return InSlot(location) and 940001 or nil end)
        game:Set("C_Item.IsBound", function() return false end)
        game:Set("C_Item.GetItemName", function(location) return InSlot(location) and "Scrap 940001" or nil end)
        game:Set("C_Item.GetItemQuality", function(location) return InSlot(location) and 1 or nil end)
        game:Set("C_Item.GetItemIcon", function(location) return InSlot(location) and 134400 or nil end)
        game:Set("C_Item.GetCurrentItemLevel", function(location) return InSlot(location) and 5 or nil end)
        game:Set("C_Item.GetStackCount", function(location) return InSlot(location) and 1 or 0 end)
        game:Set("C_Item.IsItemDataCached", function(location) return InSlot(location) end)
        game:Set("C_Container.GetContainerNumSlots", function(bag) return bag == 0 and 16 or 0 end)
        game:Set("C_Container.GetContainerItemID", function(bag, slot) return bag == 0 and slot == 1 and 940001 or nil end)

        local function ItemDisplay()
            local display = { ItemButton = world.Button() }
            function display:Reset() self.itemLink = nil end
            function display:SetItemInternal(item)
                if self.itemValidationFunc and not self.itemValidationFunc(self) then
                    return false
                end
                self.item = item
                if not item then
                    self:Reset()
                    return true
                end
                self.itemLink = item
                return true
            end
            function display:SetItemLocation(location)
                if location == nil then
                    self:SetItemInternal(nil)
                    return true
                end
                return self:SetItemInternal(env.C_Item.GetItemLink(location))
            end
            return display
        end
        local function SellFrame()
            local frame = { ItemDisplay = ItemDisplay() }
            function frame:SetItem(location) self.ItemDisplay:SetItemLocation(location) end
            return frame
        end
        local MODES = { ItemSell = "ItemSell", CommoditiesSell = "CommoditiesSell" }
        rawset(env, "AuctionHouseFrameDisplayMode", MODES)
        local house = {
            ItemSellFrame = SellFrame(), CommoditiesSellFrame = SellFrame(),
            AuctionsFrame = { ItemDisplay = ItemDisplay(), AllAuctionsList = { ScrollBox = {} } },
            BrowseResultsFrame = { ItemList = { ScrollBox = {} } },
        }
        function house:GetDisplayMode() return self.displayMode end
        function house:SelectBrowseResult() end
        function house:ClearPostItem()
            self.CommoditiesSellFrame:SetItem(nil)
            self.ItemSellFrame:SetItem(nil)
        end
        function house:SetPostItem(location)
            self:ClearPostItem()
            self.displayMode = self.commodity and MODES.CommoditiesSell or MODES.ItemSell
            if self.commodity then
                self.CommoditiesSellFrame:SetItem(location)
            else
                self.ItemSellFrame:SetItem(location)
            end
        end
        rawset(env, "AuctionHouseFrame", house)
        if rawget(env, "ScrollUtil") == nil then
            rawset(env, "ScrollUtil", {})
        end
        local addCallback = env.ScrollUtil.AddInitializedFrameCallback
        env.ScrollUtil.AddInitializedFrameCallback = function() end
        if env.CaerdonAuctionValue then
            function env.CaerdonAuctionValue:RecordDepositSample() end
        end

        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "features/Auction.lua", world.namespace)
        local auction = core:GetFeature("Auction")
        Check(auction ~= nil, label .. "the file registers its feature")
        if auction then
            auction.waitingForItemKeyInfo = {}
            auction.shouldHookAuction = true
            local hooked, problem = pcall(auction.AUCTION_HOUSE_SHOW, auction)
            Check(hooked, label .. "the window is attached to (" .. tostring(problem) .. ")")

            local slot, commodities = house.ItemSellFrame.ItemDisplay.ItemButton, house.CommoditiesSellFrame.ItemDisplay.ItemButton
            local location = env.ItemLocation:CreateFromBagAndSlot(0, 1)
            house:SetPostItem(location)
            client:Tick(2)
            Equal(world.AskedFor(slot), "940001", label .. "an item put in the slot is asked for")
            Equal(world.AskedFor(commodities), "", label .. "and the other slot is not")
            -- Two clearings and no more: the client empties both slots before it fills one, and
            -- the core clears a button it is asked for with another item than it had.
            Equal(world.cleared[slot], 2, label .. "the item going into the display clears nothing by itself")
            local clearedBefore = world.cleared[slot] or 0
            local askedBefore = #world.asked

            -- Taken out again: a right click on the slot.
            house.ItemSellFrame.ItemDisplay:SetItemLocation(nil)
            client:Tick(2)
            Check((world.cleared[slot] or 0) > clearedBefore, label .. "the slot emptied is cleared")
            Equal(#world.asked, askedBefore, label .. "and nothing is asked for")
            Check(slot.caerdonDebugItemLink == nil, label .. "the slot no longer names the item for the Debug Frame")

            -- Put in again, as a commodity this time, and taken out.
            house.commodity = true
            house:SetPostItem(location)
            client:Tick(2)
            Equal(world.AskedFor(commodities), "940001", label .. "a commodity put in its slot is asked for")
            clearedBefore = world.cleared[commodities] or 0
            house.CommoditiesSellFrame.ItemDisplay:SetItemLocation(nil)
            client:Tick(2)
            Check((world.cleared[commodities] or 0) > clearedBefore, label .. "and its slot emptied is cleared")

            -- A display that refuses the change keeps what it shows, and so does the icon.
            house:SetPostItem(location)
            client:Tick(2)
            clearedBefore = world.cleared[commodities] or 0
            house.CommoditiesSellFrame.ItemDisplay.itemValidationFunc = function() return false end
            house.CommoditiesSellFrame.ItemDisplay:SetItemLocation(nil)
            Equal(world.cleared[commodities] or 0, clearedBefore, label .. "a display that refuses to be emptied keeps its icon")
        end
        env.ScrollUtil.AddInitializedFrameCallback = addCallback
        Equal(#client.errors, 0, label .. "no error (" .. tostring(client.errors[1]) .. ")")
    end

    --------------------------------------------------------------------------------------
    -- 6. An item that answers more than once
    --------------------------------------------------------------------------------------

    -- A piece of equipment answers when its own data is here, and again when the other items
    -- of its look have loaded (CaerdonEquipmentMixin:LoadSources, which is the real one here).
    -- Four looks of two pieces each: the first of a pair is here and asked for, the second
    -- comes later.
    local function Piece(name, appearanceID, sourceID)
        return { name = name, quality = 2, level = 25, minLevel = 20, type = "Armor", subType = "Leather",
            stack = 1, equipLoc = "INVTYPE_HAND", price = 500, classID = 4, subClassID = 2, bindType = 2,
            tooltip = { { text = "Binds when equipped", type = 20, bonding = 7 } },
            appearance = { appearanceID = appearanceID, sourceID = sourceID } }
    end
    for _, flavor in ipairs({ "forever", "retail" }) do
        local label = flavor .. ", more than one answer: "
        local pieces = {}
        for pair = 0, 3 do
            pieces[940101 + pair * 2] = Piece("Glove " .. pair, 5501 + pair, 7501 + pair * 2)
            pieces[940102 + pair * 2] = Piece("Other Glove " .. pair, 5501 + pair, 7502 + pair * 2)
        end
        local world = Start(flavor, pieces)
        local core, client, window, game = world.core, world.client, world.window, world.game
        -- What is asked for is the matter here, not the piece's verdict.
        function core:ProcessItem() end
        world.Arrive(940001)
        for pair = 0, 3 do
            world.Arrive(940101 + pair * 2)
        end

        -- Nothing else said: the answer that comes with the look's other piece asks again.
        local piece = world.Button()
        window:Decorate(piece, game.Link(940101), { locationKey = "piece" }, {})
        local atOnce = world.TimesAsked(piece)
        Check(atOnce >= 1, label .. "a piece whose own data is here is asked for at once")
        client:Tick(2)
        Equal(world.TimesAsked(piece), atOnce, label .. "and not again while its look's other piece loads")
        world.Arrive(940102)
        client:Tick(2)
        Equal(world.TimesAsked(piece), atOnce + 1, label .. "the other piece come, it is asked for again")
        Equal(world.asked[#world.asked].id, 940101, label .. "with the piece itself")

        -- The row moved on in between.
        local moved = world.Button()
        window:Decorate(moved, game.Link(940103), { locationKey = "moved" }, {})
        window:Decorate(moved, game.Link(940001), { locationKey = "moved" }, {})
        local before = world.AskedFor(moved)
        world.Arrive(940104)
        client:Tick(2)
        Equal(world.AskedFor(moved), before, label .. "a row that shows another item by then is left alone")

        -- The row cleared in between.
        local emptied = world.Button()
        window:Decorate(emptied, game.Link(940105), { locationKey = "emptied" }, {})
        core:ClearButton(emptied)
        before = world.AskedFor(emptied)
        world.Arrive(940106)
        client:Tick(2)
        Equal(world.AskedFor(emptied), before, label .. "and so is one the window cleared")

        -- A refresh in between is the core's word: the wait goes on.
        local kept = world.Button()
        window:Decorate(kept, game.Link(940107), { locationKey = "kept" }, {})
        client:Tick(2)
        before = world.TimesAsked(kept)
        core:RefreshItems("the scenario")
        client:Tick(6)
        Equal(world.TimesAsked(kept), before + 1, label .. "a refresh asks for the piece again")
        world.Arrive(940108)
        client:Tick(2)
        Equal(world.TimesAsked(kept), before + 2, label .. "and the other piece, come after it, still does")
        Equal(#client.errors, 0, label .. "no error (" .. tostring(client.errors[1]) .. ")")
    end

    --------------------------------------------------------------------------------------
    -- 7. The auction house's results
    --------------------------------------------------------------------------------------

    -- A row of the results waits twice: for what the client knows of its key, then for its
    -- item's data. The list gives a row to another result as it scrolls, and neither answer may
    -- then draw on it. The feature's own file, with rows that are plain buttons.
    for _, flavor in ipairs({ "forever", "retail" }) do
        local label = flavor .. ", results: "
        local world = Start(flavor)
        local core, client, game, env = world.core, world.client, world.game, world.env
        function core:ProcessItem() end
        world.Arrive(940001)
        world.Arrive(940002)

        -- What the client knows of a key, once the scenario says it does.
        local known = {}
        local function Key(id) return { itemID = id, itemLevel = 5, itemSuffix = 0, battlePetSpeciesID = 0 } end
        game:Set("C_AuctionHouse.GetItemKeyInfo", function(itemKey) return known[itemKey.itemID] and { quality = 1 } or nil end)
        game:Set("C_AuctionHouse.GetItemKeyRequiredLevel", function() return 0 end)
        game:Set("C_TooltipInfo.GetItemKey", function(id) return { hyperlink = game.Link(id) } end)

        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "features/Auction.lua", world.namespace)
        local auction = core:GetFeature("Auction")
        Check(auction ~= nil, label .. "the file registers its feature")
        if auction then
            auction.waitingForItemKeyInfo = {}
            local function Show(row, id)
                row.rowData = { itemKey = Key(id) }
                auction:OnInitializedFrame(nil, row, {})
            end

            -- The row's item loads, and the row is given another result meanwhile.
            known[940003], known[940001] = true, true
            local row = world.Button()
            Show(row, 940003)
            Equal(world.AskedFor(row), "", label .. "a row waits for its item's data")
            Show(row, 940001)
            Equal(world.AskedFor(row), "940001", label .. "given another result, it is asked for with that")
            world.Arrive(940003)
            client:Tick(2)
            Equal(world.AskedFor(row), "940001", label .. "and the first result's item, come late, is not drawn over it")

            -- Left alone, it is asked for when its item comes.
            known[940004] = true
            local patient = world.Button()
            Show(patient, 940004)
            world.Arrive(940004)
            client:Tick(2)
            Equal(world.AskedFor(patient), "940004", label .. "a row left alone is asked for when its item's data comes")

            -- The client does not know the key yet, and the row is given another result
            -- before it does.
            world.Arrive(940005)
            local scrolled = world.Button()
            Show(scrolled, 940005)
            Equal(world.AskedFor(scrolled), "", label .. "a row whose key the client does not know yet is not asked for")
            Show(scrolled, 940002)
            known[940002] = true
            Show(scrolled, 940002)
            Equal(world.AskedFor(scrolled), "940002", label .. "given a result whose key is known, it is")
            known[940005] = true
            auction:ITEM_KEY_ITEM_INFO_RECEIVED(940005)
            client:Tick(2)
            Equal(world.AskedFor(scrolled), "940002", label .. "and the first key's answer, come late, draws nothing on it")

            -- Left alone, it is asked for when the client knows the key.
            world.Arrive(940006)
            local waiting = world.Button()
            Show(waiting, 940006)
            known[940006] = true
            auction:ITEM_KEY_ITEM_INFO_RECEIVED(940006)
            client:Tick(2)
            Equal(world.AskedFor(waiting), "940006", label .. "a row left alone is asked for when its key's answer comes")
        end
        Equal(#client.errors, 0, label .. "no error (" .. tostring(client.errors[1]) .. ")")
    end
end
