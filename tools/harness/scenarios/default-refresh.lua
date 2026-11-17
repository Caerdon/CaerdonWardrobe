-- The Refresh() of a window that has none of its own.
--
-- After a full refresh every verdict is gone and each window is told to draw again. A window
-- that says nothing there kept every icon as it was. The core therefore remembers what each
-- button was last asked to show, and a window with no Refresh() of its own is asked for all
-- of it again (CaerdonWardrobe:AskAgain, through CaerdonWardrobeFeatureMixin:Refresh):
--   1. Buttons on screen are drawn again, with the item, the place and the options they were
--      asked with. A button not on screen keeps its icon and is drawn when it comes on screen.
--   2. What is remembered is what is on the button: a cleared button, one given up, one another
--      window took over or one whose window says it shows something else is not asked for.
--   3. One button's failure does not cost the others theirs.
--   4. A window with a Refresh() of its own is left to it.
--   5. The windows this was made for inherit it, and no feature file has an empty Refresh().
--
-- The game is hand-made and the windows are the scenario's own: it proves what the core does
-- with a window's buttons, and nothing about any window of the client or of another addon.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 29 }

    local function Start()
        local items = {
            [930001] = { name = "Linen Scrap", quality = 1, level = 5, minLevel = 0, type = "Miscellaneous", subType = "Junk",
                stack = 20, price = 5, classID = 15, subClassID = 0 },
        }
        local game = H.StockGame(TOON, items)
        local world = { game = game, drawn = {}, ownRefreshes = 0 }

        local function Place(location)
            if type(location) == "table" and location.IsBagAndSlot and location:IsBagAndSlot() then
                local bag, slot = location:GetBagAndSlot()
                return bag == 0 and slot <= 40 and 930001 or nil
            end
        end
        game:Set("C_Item.DoesItemExist", function(location) return Place(location) ~= nil end)
        game:Set("C_Item.GetItemLink", function(location) return Place(location) and game.Link(Place(location)) end)
        game:Set("C_Item.GetItemID", function(location) return Place(location) end)
        game:Set("C_Item.IsBound", function() return false end)
        game:Set("C_Container.GetContainerNumSlots", function(bag) return bag == 0 and 40 or 0 end)
        game:Set("C_Container.GetContainerItemID", function(bag, slot) return bag == 0 and slot <= 40 and 930001 or nil end)
        -- The other addons a feature file looks for before it registers: there once the
        -- scenario says so, which it does after the login (part 5).
        game:Set("C_AddOns.GetAddOnInfo", function(name) return name, name, "", world.otherAddons and world.otherAddons[name] or false end)
        game:Set("C_AddOns.IsAddOnLoaded", function(name) return world.otherAddons and world.otherAddons[name] or false end)
        game:Set("C_AddOns.GetAddOnMetadata", function(name, field) return field == "X-cargBags" and "cargBagsOfTheScenario" or "1" end)

        local client = H.Client.New({ flavor = "forever", provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))

        -- Two windows of the scenario's own. Plain says nothing about a refresh; Own has a
        -- Refresh() that does what the windows with one do first, and no more.
        local PlainMixin = {}
        function PlainMixin:GetName() return "Plain" end
        function PlainMixin:Init() end
        function PlainMixin:GetTooltipData() return nil end
        function PlainMixin:IsSameItem(button) return not (world.notTheSame and world.notTheSame[button]) end
        client.env.CaerdonWardrobe:RegisterFeature(PlainMixin)

        local OwnMixin = {}
        function OwnMixin:GetName() return "Own" end
        function OwnMixin:Init() end
        function OwnMixin:GetTooltipData() return nil end
        function OwnMixin:Refresh()
            client.env.CaerdonWardrobeFeatureMixin:Refresh(self)
            world.ownRefreshes = world.ownRefreshes + 1
        end
        client.env.CaerdonWardrobe:RegisterFeature(OwnMixin)

        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)
        world.client, world.env, world.namespace = client, client.env, namespace
        local core = client.env.CaerdonWardrobe
        world.core = core
        world.plain, world.own = core:GetFeature("Plain"), core:GetFeature("Own")

        -- Every draw and every clearing, as the drawing code is handed it.
        function core:SetItemButtonStatus(button, item, feature, locationInfo, options, status)
            if status ~= "waiting" then
                world.drawn[#world.drawn + 1] = { button = button, item = item, feature = feature,
                    locationInfo = locationInfo, options = options, status = status }
            end
        end
        function core:SetItemButtonMogStatusFilter() end
        function core:SetItemButtonBindType() end
        return world
    end

    local function SlotItem(world, slot)
        local item = world.env.CaerdonItem:CreateFromBagAndSlot(0, slot)
        item.slot = slot
        function item:GetCaerdonItemType() return "Miscellaneous" end
        function item:IsItemDataCached() return true end
        function item:GetCaerdonStatus() return true, "own", nil, {}, nil end
        return item
    end

    -- A request as a window makes it: a place and options of the window's own.
    local function Ask(world, feature, button, item)
        local locationInfo, options = { bag = 0, slot = item.slot }, { statusProminentSize = 13 }
        world.core:UpdateButton(button, item, feature, locationInfo, options)
        return locationInfo, options
    end

    -- How often the button was drawn with an item, and the last entry about it (a clearing is
    -- an entry with no item).
    local function Draws(world, button)
        local count, last = 0, nil
        for _, entry in ipairs(world.drawn) do
            if entry.button == button then
                last = entry
                if entry.item then
                    count = count + 1
                end
            end
        end
        return count, last
    end

    -- A full refresh and the frames until every window has been told and has drawn.
    local function Refresh(world)
        world.drawn, world.ownRefreshes = {}, 0
        world.core:RefreshItems("scenario")
        world.client:Tick(4)
    end

    local function NoErrors(world, label)
        Equal(#world.client.errors, 0, label .. ": no error reached the error handler")
        for _, message in ipairs(world.client.errors) do
            Check(false, label .. ": " .. message)
        end
    end

    --------------------------------------------------------------------------------------
    -- 1. On screen and not
    --------------------------------------------------------------------------------------

    do
        local world = Start()
        local core, client, plain = world.core, world.client, world.plain
        NoErrors(world, "start")
        Check(plain.Refresh == world.env.CaerdonWardrobeFeatureMixin.Refresh, "plain: the window has no Refresh() of its own")

        local window, list = client:NewFrame("Frame"), client:NewFrame("Frame")
        local first, second = client:NewFrame("Button", nil, window), client:NewFrame("Button", nil, window)
        local row = client:NewFrame("Button", nil, list)
        local firstItem, secondItem, rowItem = SlotItem(world, 1), SlotItem(world, 2), SlotItem(world, 3)
        local firstPlace, firstOptions = Ask(world, plain, first, firstItem)
        Ask(world, plain, second, secondItem)
        Ask(world, plain, row, rowItem)
        client:Tick(2)
        Equal((Draws(world, first)) + (Draws(world, second)) + (Draws(world, row)), 3, "asked: the three buttons are drawn")

        Refresh(world)
        local count, last = Draws(world, first)
        Equal(count, 1, "refresh: a button on screen is drawn again, once")
        Check(last and last.item == firstItem, "refresh: with the item it was asked for")
        Check(last and last.locationInfo == firstPlace and last.options == firstOptions,
            "refresh: and the place and the options the window gave")
        Check(last and last.feature == plain, "refresh: as the window's")
        Equal((Draws(world, second)), 1, "refresh: its neighbour too")
        Equal((Draws(world, row)), 1, "refresh: and the row of the other frame")
        Check(core:IsQueueIdle(), "refresh: nothing is left waiting")

        -- The list is hidden as it is: a tab switched away from.
        client:SetFrameShown(list, false)
        Refresh(world)
        Equal((Draws(world, first)), 1, "hidden: the button on screen is drawn at the next refresh")
        Equal((Draws(world, row)), 0, "hidden: the row that is not on screen is not")
        Check(select(2, Draws(world, row)) == nil, "hidden: nor cleared: it keeps the icon it has")
        Check(core:IsQueueIdle(), "hidden: nothing is queued for it")
        Refresh(world)
        Equal((Draws(world, row)), 0, "hidden: nor at the refresh after")
        world.drawn = {}
        client:SetFrameShown(list, true)
        Equal((Draws(world, row)), 0, "shown: nothing is drawn in the frame the list comes back in")
        client:Tick(1)
        count, last = Draws(world, row)
        Equal(count, 1, "shown: the row is drawn in the next, once for both refreshes")
        Check(last and last.item == rowItem, "shown: with its item")
        Equal((Draws(world, first)), 0, "shown: a button that was on screen all along is not drawn again")
        world.drawn = {}
        client:SetFrameShown(list, false)
        client:SetFrameShown(list, true)
        client:Tick(2)
        Equal((Draws(world, row)), 0, "shown: hiding and showing with no refresh in between draws nothing")

        -- A window that does ask when it comes back replaces what was owed: still one draw.
        client:SetFrameShown(list, false)
        Refresh(world)
        world.drawn = {}
        client:SetFrameShown(list, true)
        local newer = SlotItem(world, 4)
        Ask(world, plain, row, newer)
        client:Tick(2)
        count, last = Draws(world, row)
        Equal(count, 1, "asked on show: the window's own request and the owed one are one draw")
        Check(last and last.item == newer, "asked on show: of what the window asked for")

        -- And what it asked for last is what the next refresh asks for.
        Refresh(world)
        count, last = Draws(world, row)
        Check(count == 1 and last.item == newer, "newer: a refresh asks for the item the button was last asked for")
        NoErrors(world, "on screen")
    end

    --------------------------------------------------------------------------------------
    -- 2. What is remembered is what is on the button
    --------------------------------------------------------------------------------------

    do
        local world = Start()
        local core, client, plain, own = world.core, world.client, world.plain, world.own
        local window = client:NewFrame("Frame")
        local function Button() return client:NewFrame("Button", nil, window) end
        local kept, cleared, givenUp, taken, other, emptied = Button(), Button(), Button(), Button(), Button(), Button()
        for index, button in ipairs({ kept, cleared, givenUp, taken, other, emptied }) do
            Ask(world, plain, button, SlotItem(world, index))
        end
        client:Tick(2)

        core:ClearButton(cleared)
        core:ClearButtonState(givenUp)
        local takenItem = SlotItem(world, 10)
        Ask(world, own, taken, takenItem)
        -- The window asks for a button with nothing in it: the button is cleared.
        core:UpdateButton(emptied, nil, plain, { bag = 0, slot = 6 }, {})
        client:Tick(2)

        Refresh(world)
        Equal((Draws(world, kept)), 1, "kept: a button left as it was is drawn again")
        Check(select(2, Draws(world, cleared)) == nil, "cleared: a button the window cleared is not asked for")
        Check(select(2, Draws(world, givenUp)) == nil, "given up: nor one whose state was dropped")
        Check(select(2, Draws(world, emptied)) == nil, "emptied: nor one last asked for with no item")
        Equal((Draws(world, taken)), 0, "taken: a button another window asked for since is not this window's any more")
        Equal(world.ownRefreshes, 1, "taken: that window's own Refresh() ran")
        -- Asked for by name, the button is only its last window's.
        world.drawn = {}
        Check(core:AskAgainFor(taken, plain) == false, "taken: asked for the first window, the button is not asked for")
        Check(core:IsQueueIdle(), "taken: and nothing is queued")
        Check(core:AskAgainFor(taken, own) == true, "taken: asked for the window that has it, it is")
        client:Tick(2)
        local takenCount, takenLast = Draws(world, taken)
        Check(takenCount == 1 and takenLast.item == takenItem and takenLast.feature == own, "taken: with that window's item")
        Check(core:AskAgainFor(client:NewFrame("Button"), plain) == false, "never asked: a button nobody asked for is not asked for")

        -- The window says the button shows something else by now: cleared, and then forgotten.
        world.notTheSame = { [other] = true }
        Refresh(world)
        local count, last = Draws(world, other)
        Check(count == 0 and last ~= nil and last.item == nil, "not the same: the button is cleared when its window disowns the item")
        world.notTheSame = nil
        Refresh(world)
        Check(select(2, Draws(world, other)) == nil, "not the same: and is not asked for after that")

        -- Hidden and cleared before it comes back: nothing is owed any more.
        local list = client:NewFrame("Frame")
        local row = client:NewFrame("Button", nil, list)
        Ask(world, plain, row, SlotItem(world, 7))
        client:Tick(2)
        client:SetFrameShown(list, false)
        Refresh(world)
        core:ClearButton(row)
        world.drawn = {}
        client:SetFrameShown(list, true)
        client:Tick(2)
        Equal((Draws(world, row)), 0, "cleared while hidden: nothing is drawn when the row comes back")

        -- Hidden, then taken by the other window while hidden: the first owes it nothing.
        Ask(world, plain, row, SlotItem(world, 7))
        client:Tick(2)
        client:SetFrameShown(list, false)
        Refresh(world)
        local ownItem = SlotItem(world, 8)
        Ask(world, own, row, ownItem)
        world.drawn = {}
        client:SetFrameShown(list, true)
        client:Tick(2)
        count, last = Draws(world, row)
        Check(count == 1 and last.item == ownItem and last.feature == own, "taken while hidden: only the other window's request is drawn")
        NoErrors(world, "remembered")
    end

    --------------------------------------------------------------------------------------
    -- 3. One failure stays alone
    --------------------------------------------------------------------------------------

    -- Five buttons, and asking for four of them raises an error. Whichever of the five is the
    -- sound one, it is drawn: the order the buttons are walked in is not the scenario's to
    -- choose, so each takes the turn.
    for sound = 1, 5 do
        local world = Start()
        local client, plain = world.client, world.plain
        local window = client:NewFrame("Frame")
        local buttons, items = {}, {}
        for index = 1, 5 do
            buttons[index] = client:NewFrame("Button", nil, window)
            items[index] = SlotItem(world, index)
            Ask(world, plain, buttons[index], items[index])
        end
        client:Tick(2)
        for index = 1, 5 do
            if index ~= sound then
                items[index].IsItemEmpty = function() error("this item cannot be asked for") end
            end
        end
        Refresh(world)
        Equal(#client.errors, 4, "failure " .. sound .. ": each of the four errors reaches the error handler")
        Equal((Draws(world, buttons[sound])), 1, "failure " .. sound .. ": and the sound button is drawn again")
    end

    --------------------------------------------------------------------------------------
    -- 4. A window with a Refresh() of its own
    --------------------------------------------------------------------------------------

    do
        local world = Start()
        local client, own = world.client, world.own
        local window = client:NewFrame("Frame")
        local button = client:NewFrame("Button", nil, window)
        Ask(world, own, button, SlotItem(world, 1))
        client:Tick(2)
        Refresh(world)
        Equal(world.ownRefreshes, 1, "own: the window's Refresh() is called")
        Check(select(2, Draws(world, button)) == nil, "own: and nothing is asked for on its behalf")
        NoErrors(world, "own")
    end

    --------------------------------------------------------------------------------------
    -- 5. The shipped windows
    --------------------------------------------------------------------------------------

    do
        local world = Start()
        local core, client, default = world.core, world.client, world.env.CaerdonWardrobeFeatureMixin.Refresh
        -- The files of the windows that had an empty Refresh(), loaded as the game loads them.
        -- Loading registers the feature; nothing is hooked before its Init, which is not run.
        -- An integration's file registers only beside its addon, so those are said to be there.
        local WINDOWS = {
            { "Auction", "features/Auction.lua" }, { "BlackMarket", "features/BlackMarket.lua" },
            { "CustomerOrders", "features/CustomerOrders.lua" }, { "GroupLoot", "features/GroupLoot.lua" },
            { "GuildBank", "features/GuildBank.lua" }, { "Mail", "features/Mail.lua" },
            { "Mission", "features/Mission.lua" }, { "TradeSkill", "features/TradeSkill.lua" },
            { "AngrierWorldQuests", "external/AngrierWorldQuests/Core.AngrierWorldQuests.lua" },
            { "Auctionator", "external/Auctionator/Core.Auctionator.lua" },
            { "cargBags_Nivaya", "external/CargBags/Core.CargBags.lua" },
            { "LiteBag", "external/LiteBag/Core.LiteBag.lua" },
            { "Skillet", "external/Skillet/Core.Skillet.lua" },
            { "Sorted", "external/Sorted/Core.Sorted.lua" },
            { "VenturePlan", "external/VenturePlan/Core.VenturePlan.lua" },
            { "WorldQuestTracker", "external/WorldQuestTracker/Core.WorldQuestTracker.lua" },
        }
        world.otherAddons = {}
        for _, window in ipairs(WINDOWS) do
            world.otherAddons[window[1]] = true
        end
        rawset(client.env, "cargBagsOfTheScenario", {})
        for _, window in ipairs(WINDOWS) do
            local name, file = window[1], window[2]
            client:LoadAddonFile("CaerdonWardrobe", H.addonDir, file, world.namespace)
            local feature = core:GetFeature(name)
            Check(feature ~= nil, name .. ": the file registers its feature")
            Check(feature and feature.Refresh == default, name .. ": it has the default Refresh()")
            Check(feature and feature.OnButtonOnScreen == world.env.CaerdonWardrobeFeatureMixin.OnButtonOnScreen,
                name .. ": and the default answer to a button coming on screen")
        end

        -- No feature file defines a Refresh() with nothing in it. Comments are not code.
        local function EmptyRefresh(path)
            local file = io.open(path, "r")
            if not file then
                return nil
            end
            local text = file:read("*a"):gsub("%-%-[^\n]*", "")
            file:close()
            return text:match("function%s+[%w_.]+:Refresh%s*%(%s*%)%s*end") ~= nil
        end
        local read = 0
        local function Scan(dir, relative)
            for _, file in ipairs(H.ListDir(dir)) do
                if file:match("%.lua$") then
                    local empty = EmptyRefresh(dir .. "/" .. file)
                    if empty ~= nil then
                        read = read + 1
                        Check(not empty, relative .. "/" .. file .. ": no empty Refresh()")
                    end
                end
            end
        end
        Scan(H.addonDir .. "/features", "features")
        for _, folder in ipairs(H.ListDir(H.addonDir .. "/external", true)) do
            if folder ~= "deprecated" then
                Scan(H.addonDir .. "/external/" .. folder, "external/" .. folder)
            end
        end
        Check(read >= 40, "files: the feature files were read (" .. read .. ")")
        NoErrors(world, "shipped")
    end
end
