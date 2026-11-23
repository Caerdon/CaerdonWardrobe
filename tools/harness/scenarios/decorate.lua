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
--
-- The game is hand-made, and the scenario says when an item's data comes. Real code: the core,
-- FeatureMixin.lua, CaerdonItem.lua and features/Merchant.lua.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 29 }

    local function Start(flavor)
        local items = {}
        for id = 940001, 940016 do
            items[id] = { name = "Scrap " .. id, quality = 1, level = 5, minLevel = 0, type = "Miscellaneous", subType = "Junk",
                stack = 20, price = 5, classID = 15, subClassID = 0 }
        end
        local game = H.StockGame(TOON, items)
        local world = { game = game, asked = {}, cleared = {}, held = {}, here = {} }

        -- An item's data is with the client once the scenario says so (Arrive). The client is
        -- asked by ID or by link.
        local function IDOf(reference)
            return tonumber(reference) or tonumber(tostring(reference):match("item:(%d+)"))
        end
        game:Set("C_Item.IsItemDataCachedByID", function(reference) return world.here[IDOf(reference)] == true end)
        game:Set("C_Item.RequestLoadItemDataByID", function(reference) world.held[IDOf(reference)] = true end)

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
end
