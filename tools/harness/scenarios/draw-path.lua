-- The draw path: what happens between a window asking for a button and the icon on it.
--
-- Four things, each with the real code:
--   1. An item and its data find their methods through a metatable, live.
--   2. The queue: the first pass comes a frame after the request, a pass ends when its time is
--      up, a button has one pending request, a request that is no longer the button's is
--      dropped without clearing anything.
--   3. A draw asks the window for its display rules once, and the search dimming of a frame's
--      draws is one timer.
--   4. The drawing itself, written down: every widget call SetItemButtonStatus and
--      SetItemButtonBindType make, for every status across a set of options, settings and
--      transmog infos. Some of it is checked here. All of it can be written to a file:
--
--          CAERDON_DRAW_TRANSCRIPT=<file> luajit tools/harness/run.lua scenarios draw-path
--
--      Two such files, one made in a checkout of the code from before a change to the
--      drawing, say whether the change draws anything differently.
--
-- The game is hand-made. It proves what the code does with a button, and nothing about how a
-- client lays one out.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 29 }

    local function Items()
        return {
            [930001] = { name = "Linen Scrap", quality = 1, level = 5, minLevel = 0, type = "Miscellaneous", subType = "Junk",
                stack = 20, price = 5, classID = 15, subClassID = 0 },
            [930002] = { name = "Field Tunic", quality = 2, level = 20, minLevel = 20, type = "Armor", subType = "Leather",
                stack = 1, equipLoc = "INVTYPE_CHEST", price = 500, classID = 4, subClassID = 2, bindType = 2,
                tooltip = { { text = "Binds when equipped", type = 20, bonding = 2 } },
                appearance = { appearanceID = 6201, sourceID = 8201 } },
        }
    end

    -- Bag 0: slots 1 and 2 hold two copies of one item, the rest alternate.
    local BAG = {}
    for slot = 1, 40 do
        BAG[slot] = (slot <= 2 or slot % 2 == 1) and 930001 or 930002
    end

    local function Start()
        local items = Items()
        local game = H.StockGame(TOON, items)
        local world = { game = game, spent = 0 }

        local function Place(location)
            if type(location) == "table" and location.IsBagAndSlot and location:IsBagAndSlot() then
                local bag, slot = location:GetBagAndSlot()
                return bag == 0 and BAG[slot] or nil
            end
        end
        game:Set("C_Item.DoesItemExist", function(location) return Place(location) ~= nil end)
        game:Set("C_Item.GetItemLink", function(location) return Place(location) and game.Link(Place(location)) end)
        game:Set("C_Item.GetItemID", function(location) return Place(location) end)
        game:Set("C_Item.IsBound", function() return false end)
        game:Set("C_Container.GetContainerNumSlots", function(bag) return bag == 0 and 40 or 0 end)
        game:Set("C_Container.GetContainerItemID", function(bag, slot) return bag == 0 and BAG[slot] or nil end)
        game:Set("BAG_ITEM_QUALITY_COLORS", { [7] = { r = 0, g = 0.8, b = 1 } })

        local client = H.Client.New({ flavor = "forever", provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        world.defaults = namespace:GetDefaultConfig()
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(world.defaults))

        -- A window of the scenario's own. hide: icons its display rules switch off.
        local TestMixin = {}
        function TestMixin:GetName() return "Test" end
        -- An event for every unit and one for the toon alone.
        function TestMixin:Init() return { "BAG_UPDATE_DELAYED", { "UNIT_SPELLCAST_SUCCEEDED", "player" } } end
        function TestMixin:BAG_UPDATE_DELAYED() world.bagUpdates = (world.bagUpdates or 0) + 1 end
        function TestMixin:UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID) world.cast = tostring(unit) .. " " .. tostring(spellID) end
        function TestMixin:Refresh() end
        function TestMixin:GetTooltipData() return nil end
        function TestMixin:GetDisplayInfo()
            world.displayInfos = (world.displayInfos or 0) + 1
            local info = { bindingStatus = { shouldShow = true } }
            for _, key in ipairs(world.hide or {}) do
                info[key] = { shouldShow = false }
            end
            return info
        end
        client.env.CaerdonWardrobe:RegisterFeature(TestMixin)
        world.registered = {}
        local frame = client.env.CaerdonWardrobe
        local registerEvent, registerUnitEvent = frame.RegisterEvent, frame.RegisterUnitEvent
        function frame:RegisterEvent(event)
            world.registered[event] = "every unit"
            return registerEvent(self, event)
        end
        function frame:RegisterUnitEvent(event, unit)
            world.registered[event] = unit
            return registerUnitEvent(self, event, unit)
        end

        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)
        world.client, world.env = client, client.env
        world.core = client.env.CaerdonWardrobe
        world.feature = world.core:GetFeature("Test")

        -- The stopwatch the queue reads: the frame's time plus what the scenario's draws say
        -- they cost. The harness' own does not move within a frame.
        rawset(client.env, "GetTimePreciseSec", function() return client.clock + world.spent / 1000 end)
        return world
    end

    local function NoErrors(world, label)
        Equal(#world.client.errors, 0, label .. ": no error reached the error handler")
        for _, message in ipairs(world.client.errors) do
            Check(false, label .. ": " .. message)
        end
    end

    --------------------------------------------------------------------------------------
    -- 1. Items and item data
    --------------------------------------------------------------------------------------

    do
        local world = Start()
        local env = world.env
        NoErrors(world, "start")

        local item = env.CaerdonItem:CreateFromItemID(930002)
        local ownFunctions = 0
        for _, value in pairs(item) do
            if type(value) == "function" then
                ownFunctions = ownFunctions + 1
            end
        end
        Equal(ownFunctions, 0, "items: an item's own table holds no method")
        Check(type(item.GetCaerdonStatus) == "function", "items: the addon's methods are reached")
        Check(item.GetItemID == env.ItemMixin.GetItemID, "items: and Blizzard's, through the addon's")
        Equal(item:GetItemID(), 930002, "items: which work on the item's own data")
        Check(item.Clear == env.CaerdonItemMixin.Clear and item.Clear ~= env.ItemMixin.Clear,
            "items: a method both have is the addon's")

        -- The counters wrap a method on the mixin after items exist, and the signal modules add
        -- theirs in later files: both have to reach an item that is already made.
        local original = env.CaerdonItemMixin.GetForDebugUse
        env.CaerdonItemMixin.GetForDebugUse = function() return "wrapped" end
        Equal(item:GetForDebugUse(), "wrapped", "items: a method replaced on the mixin later is the one an older item calls")
        env.CaerdonItemMixin.GetForDebugUse = original
        Check(type(item.GetQuestItemInfo) == "function", "items: a signal module's entry point, defined in a later file, is there")

        -- A method set on one item is that item's alone.
        function item:GetForDebugUse() return "mine" end
        Equal(item:GetForDebugUse(), "mine", "items: an item can still be given a method of its own")
        Check(env.CaerdonItem:CreateFromItemID(930002).GetForDebugUse == original, "items: which no other item gets")

        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        world.client:TickUntil(function() return loaded end, 10)
        Check(loaded, "items: the item loads")
        local data = item:GetItemData()
        Check(type(data) == "table", "data: the tunic has item data")
        local own = {}
        for key in pairs(data or {}) do
            own[#own + 1] = tostring(key)
        end
        table.sort(own)
        -- LoadSources keeps what it found on the data object; no method is among it.
        local dataFunctions = 0
        for _, value in pairs(data or {}) do
            if type(value) == "function" then
                dataFunctions = dataFunctions + 1
            end
        end
        Equal(dataFunctions, 0, "data: its own table holds no method (" .. table.concat(own, ", ") .. ")")
        Check(data and data.item == item, "data: it knows its item")
        Check(data and data.GetTransmogInfo == env.CaerdonEquipmentMixin.GetTransmogInfo, "data: its type's methods are reached")
        Check(data and data.Init == env.CaerdonWardrobeItemDataMixin.Init, "data: and the shared ones, through the type's")
        Check(data and data.ContinueOnItemDataLoad == env.CaerdonEquipmentMixin.ContinueOnItemDataLoad,
            "data: a method both have is the type's")
        local junk = env.CaerdonItem:CreateFromItemID(930001)
        Check(junk:GetItemData() == nil or junk:GetItemData().GetTransmogInfo == nil,
            "data: another type's data does not get the equipment's methods")
        NoErrors(world, "items")

        -- A window's events: a plain name is for every unit, { name, unit } for that unit.
        Equal(world.registered.BAG_UPDATE_DELAYED, "every unit", "events: a plain event is registered plainly")
        Equal(world.registered.UNIT_SPELLCAST_SUCCEEDED, "player", "events: a unit event for the unit it names")
        world.client:Fire("BAG_UPDATE_DELAYED")
        world.client:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 1804)
        Equal(world.bagUpdates, 1, "events: the window is handed the plain one")
        Equal(world.cast, "player 1804", "events: and the unit event, with its arguments")
        NoErrors(world, "events")
    end

    --------------------------------------------------------------------------------------
    -- 2. The queue
    --------------------------------------------------------------------------------------

    -- A world whose drawing is a list: { button, item } per draw, { button } per clear.
    local function QueueWorld()
        local world = Start()
        local core = world.core
        world.drawn = {}
        function core:SetItemButtonStatus(button, item, feature, locationInfo, options, status)
            if status ~= "waiting" then
                world.drawn[#world.drawn + 1] = { button = button, item = item, status = status }
            end
        end
        function core:SetItemButtonMogStatusFilter() end
        function core:SetItemButtonBindType() end
        return world
    end

    -- An item in a bag slot whose status costs `cost` ms of the scenario's stopwatch.
    local function SlotItem(world, slot, cost)
        local item = world.env.CaerdonItem:CreateFromBagAndSlot(0, slot)
        item.slot, item.loaded = slot, true
        function item:GetCaerdonItemType() return "Miscellaneous" end
        function item:IsItemDataCached() return self.loaded end
        function item:GetCaerdonStatus()
            world.spent = world.spent + (cost or 0)
            return true, "own", nil, {}, nil
        end
        return item
    end

    local function Ask(world, button, item)
        world.core:UpdateButton(button, item, world.feature, { bag = 0, slot = item.slot }, {})
    end

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

    -- Draws in all; a button's clearing is in the list too and is not one.
    local function DrawCount(world)
        local count = 0
        for _, entry in ipairs(world.drawn) do
            if entry.item then
                count = count + 1
            end
        end
        return count
    end

    local function NewButton(world)
        return world.client:NewFrame("Button")
    end

    -- A verdict that is not ready is asked for again: after a second where nothing says
    -- sooner, and in a moment where the data it was put off for has come.
    do
        local world = QueueWorld()
        local core, client = world.core, world.client
        -- An item whose status is not ready until `world.ready` is set.
        local function WaitingItem(slot)
            local item = SlotItem(world, slot)
            item.tries = 0
            function item:GetCaerdonStatus()
                self.tries = self.tries + 1
                if not (world.ready or self.ready) then
                    -- Third: what it waits for (a tooltip's instance, or a key).
                    return false, self.why or "its tooltip", self.instance or self.waitsFor
                end
                return true, "own", nil, {}, nil
            end
            return item
        end
        local function Drawn(button)
            local count = Draws(world, button)
            return count
        end
        local function Frames(button, limit)
            for frame = 1, limit do
                client:Tick(1)
                if Drawn(button) > 0 then
                    return frame
                end
            end
            return nil
        end

        -- Nothing says sooner: the timer's second.
        local slow = NewButton(world)
        Ask(world, slow, WaitingItem(11))
        client:Tick(3)
        Equal(Drawn(slow), 0, "not ready: nothing is drawn while the verdict is not ready")
        world.ready = true
        local frames = Frames(slow, 40)
        Check(frames ~= nil and frames >= 15, "not ready: with nothing to say sooner it is asked again after about a second (" ..
            tostring(frames) .. " frames of a twentieth)")

        -- The data it waits for comes: asked again in a moment.
        world.ready = false
        local fast = NewButton(world)
        Ask(world, fast, WaitingItem(12))
        client:Tick(3)
        Equal(Drawn(fast), 0, "data awaited: nothing is drawn while the verdict is not ready")
        core:RetryWhenLoaded(4242)
        world.ready = true
        client:Fire("ITEM_DATA_LOAD_RESULT", 4242, true)
        frames = Frames(fast, 40)
        Check(frames ~= nil and frames <= 3, "data awaited: when the data comes the button is drawn in a moment (" .. tostring(frames) .. " frames)")
        local lines = {}
        for _, line in ipairs(world.env.CaerdonCounters:GetReportLines()) do
            lines[#lines + 1] = tostring(line.text)
        end
        Check(table.concat(lines, " / "):find("Draws that waited for a verdict to be ready: 2, waiting ", 1, true) ~= nil and
            table.concat(lines, " / "):find("for its tooltip: 2, ", 1, true) ~= nil,
            "data awaited: the counters say how many draws waited, for what, and how long")

        -- Another item's data is not the one waited for, and nothing is listened to once
        -- nothing is waited for.
        world.ready = false
        local other = NewButton(world)
        local waiting = WaitingItem(13)
        Ask(world, other, waiting)
        client:Tick(3)
        local tries = waiting.tries
        client:Fire("ITEM_DATA_LOAD_RESULT", 99, true)
        client:Tick(3)
        Equal(waiting.tries, tries, "data awaited: an item nobody waits for asks nothing again")
        -- Nor does it while another item is waited for.
        core:RetryWhenLoaded(7000)
        client:Fire("ITEM_DATA_LOAD_RESULT", 99, true)
        client:Tick(3)
        Equal(waiting.tries, tries, "data awaited: nor while another item is the one waited for")
        client:Fire("ITEM_DATA_LOAD_RESULT", 7000, true)
        client:Tick(3)
        Equal(waiting.tries, tries + 1, "data awaited: the one waited for does")
        tries = waiting.tries

        -- A tooltip the client is still looking something up for: the client says when that
        -- is through, by the tooltip's instance, and the button is asked again in a moment.
        do
            world.ready = false
            local tipButton = NewButton(world)
            local tipItem = WaitingItem(14)
            tipItem.instance = 9001
            Ask(world, tipButton, tipItem)
            client:Tick(3)
            Check(core.awaitedTooltips ~= nil and core.awaitedTooltips[9001] == true, "tooltip awaited: the queue waits for the tooltip's instance")
            local asked = tipItem.tries
            client:Fire("TOOLTIP_DATA_UPDATE", 77)
            client:Tick(3)
            Equal(tipItem.tries, asked, "tooltip awaited: another tooltip's lookup asks nothing again")
            client:Fire("TOOLTIP_DATA_UPDATE", 9001)
            client:Tick(3)
            Equal(tipItem.tries, asked + 1, "tooltip awaited: its own does, in a moment")
            Check(core.awaitedTooltips ~= nil and core.awaitedTooltips[9001] == true, "tooltip awaited: still not there, it is waited for again")
            client:Fire("TOOLTIP_DATA_UPDATE")
            client:Tick(3)
            Equal(tipItem.tries, asked + 2, "tooltip awaited: an update that names no tooltip is taken for any")
            tipItem.ready = true
            client:Fire("TOOLTIP_DATA_UPDATE", 9001)
            local frames = Frames(tipButton, 40)
            Check(frames ~= nil and frames <= 3, "tooltip awaited: when it has come the button is drawn in a moment (" .. tostring(frames) .. " frames)")
            Equal(core.awaitedTooltips, nil, "tooltip awaited: and nothing is waited for or listened to after")
            local updates = world.env.CaerdonCounters:GetReport().tooltipUpdates
            Check(updates.waitedFor == 2 and updates.unnamed == 1 and updates.other == 1,
                "tooltip awaited: the counters say which updates were for a tooltip waited for (" .. tostring(updates.waitedFor) .. ", " ..
                tostring(updates.unnamed) .. ", " .. tostring(updates.other) .. ")")
            -- A tooltip with no instance to go by waits for the timer as before.
            local plain = NewButton(world)
            local plainItem = WaitingItem(15)
            Ask(world, plain, plainItem)
            client:Tick(3)
            Equal(core.awaitedTooltips, nil, "tooltip awaited: one with no instance is not waited for by the event")
            plainItem.ready = true
            local slowFrames = Frames(plain, 40)
            Check(slowFrames ~= nil and slowFrames >= 10, "tooltip awaited: it is asked again by the timer (" .. tostring(slowFrames) .. " frames)")
            tries = waiting.tries
        end

        -- What comes is matched to what waits for it: of two buttons that wait for two
        -- things, the arrival of one asks its button again and leaves the other waiting.
        do
            local first, second = WaitingItem(16), WaitingItem(17)
            first.why, first.waitsFor = "the Catalyst's answer", "item:801"
            second.why, second.waitsFor = "the Catalyst's answer", "item:802"
            Ask(world, NewButton(world), first)
            Ask(world, NewButton(world), second)
            client:Tick(3)
            local firstTries, secondTries, otherTries = first.tries, second.tries, waiting.tries
            core:RetryWhenLoaded(801, "item:801")
            core:RetryWhenLoaded(802, "item:802")
            client:Fire("ITEM_DATA_LOAD_RESULT", 801, true)
            client:Tick(3)
            Equal(first.tries, firstTries + 1, "matched: the item that came asks the button again that waits for it")
            Equal(second.tries, secondTries, "matched: and not the button that waits for another item")
            Equal(waiting.tries, otherTries, "matched: nor one that waits for something else altogether")
            core:RetryWaitingFor("item:802")
            client:Tick(3)
            Equal(second.tries, secondTries + 1, "matched: whoever has what a button waits for names it, and that button is asked")
            Equal(first.tries, firstTries + 1, "matched: the first is left alone by it")
            -- Two tooltips: the client names one.
            local tipA, tipB = WaitingItem(18), WaitingItem(19)
            tipA.instance, tipB.instance = 9101, 9102
            Ask(world, NewButton(world), tipA)
            Ask(world, NewButton(world), tipB)
            client:Tick(3)
            local triesA, triesB = tipA.tries, tipB.tries
            firstTries = first.tries
            client:Fire("TOOLTIP_DATA_UPDATE", 9102)
            client:Tick(3)
            Equal(tipB.tries, triesB + 1, "matched: the tooltip the client names asks its button again")
            Equal(tipA.tries, triesA, "matched: and not the button of another tooltip")
            Equal(first.tries, firstTries, "matched: nor one that waits for an item")
            -- The timer still asks all of them, what they wait for or not.
            first.ready, second.ready, tipA.ready, tipB.ready = true, true, true, true
            client:Tick(40)
            Check(first.tries > firstTries and tipA.tries > triesA, "matched: the timer asks every button that still waits, as before")
            tries = waiting.tries
        end

        -- A verdict that waits for several items in turn is tried once for each, and those
        -- tries do not use up the limit of a tooltip that never loads.
        for round = 1, 15 do
            core:RetryWhenLoaded(5000 + round)
            client:Fire("ITEM_DATA_LOAD_RESULT", 5000 + round, true)
            client:Tick(3)
        end
        Check(waiting.tries >= tries + 15, "data awaited: asked again each time something it waits for comes (" ..
            tostring(waiting.tries - tries) .. " times)")
        world.ready = true
        core:RetryWhenLoaded(6000)
        client:Fire("ITEM_DATA_LOAD_RESULT", 6000, false)
        frames = Frames(other, 40)
        Check(frames ~= nil and frames <= 3, "data awaited: and it is still drawn when the last of it has come, refused or not (" ..
            tostring(frames) .. " frames)")
        NoErrors(world, "not ready")
    end

    do
        local world = QueueWorld()
        local core, client = world.core, world.client
        Check(core:IsQueueIdle(), "queue: idle before anything is asked")
        Check(core:GetScript("OnUpdate") == nil, "queue: and not looked at every frame")

        -- The first pass waits for a later frame than the request.
        local button = NewButton(world)
        Ask(world, button, SlotItem(world, 3))
        Check(not core:IsQueueIdle(), "start: a request makes the queue busy")
        Check(core:GetScript("OnUpdate") ~= nil, "start: and wakes it")
        core:GetScript("OnUpdate")(core, 0)
        Equal(DrawCount(world), 0, "start: nothing is drawn in the frame of the request")
        client:Tick(1)
        Equal((Draws(world, button)), 1, "start: it is drawn in the next frame")
        Check(core:IsQueueIdle(), "start: after which the queue is idle")
        Check(core:GetScript("OnUpdate") == nil, "start: and asleep, with no empty pass after the last draw")
        Equal(core:GetButtonRefreshGeneration(button), core:GetRefreshGeneration(), "start: the button carries the refresh generation")

        -- A pass ends when its time is up: the draw that uses the last of 8 ms is the last.
        local function PerFrame(count, cost)
            world.drawn = {}
            local buttons = {}
            for index = 1, count do
                buttons[index] = NewButton(world)
                Ask(world, buttons[index], SlotItem(world, index, cost))
            end
            local frames = {}
            for _ = 1, 40 do
                local before = DrawCount(world)
                client:Tick(1)
                if DrawCount(world) > before then
                    frames[#frames + 1] = DrawCount(world) - before
                end
                if core:IsQueueIdle() then
                    break
                end
            end
            for index = 1, count do
                Equal((Draws(world, buttons[index])), 1, ("budget: button %d of %d was drawn once"):format(index, count))
            end
            return table.concat(frames, ",")
        end
        Equal(PerFrame(20, 1.5), "6,6,6,2", "budget: draws of a millisecond and a half go six to a frame")
        Equal(PerFrame(20, 0), "20", "budget: draws that cost nothing all go in one frame")
        Equal(PerFrame(3, 30), "1,1,1", "budget: a draw longer than the budget still happens, one a frame")
        Equal(PerFrame(30, 0.75), "11,11,8", "budget: three quarters of a millisecond, eleven")
        NoErrors(world, "budget")
    end

    do
        local world = QueueWorld()
        local core, client = world.core, world.client

        -- A button asked for twice before it is drawn is drawn once, with the later answer.
        local button = NewButton(world)
        local first, second = SlotItem(world, 3), SlotItem(world, 3)
        Ask(world, button, first)
        local request = core.waitingToProcess[button]
        Ask(world, button, second)
        Check(core.waitingToProcess[button] == request, "one: the second request takes the place of the first")
        client:Tick(2)
        local count, last = Draws(world, button)
        Equal(count, 1, "one: one draw for two requests")
        Check(last and last.item == second, "one: of the item asked for last")

        -- Two buttons for one slot are two requests.
        world.drawn = {}
        local left, right = NewButton(world), NewButton(world)
        Ask(world, left, SlotItem(world, 5))
        Ask(world, right, SlotItem(world, 5))
        client:Tick(2)
        Equal((Draws(world, left)), 1, "one: of two buttons showing one slot the first is drawn")
        Equal((Draws(world, right)), 1, "one: and the second")

        -- A request that is no longer the button's. Three buttons, a frame's budget of one
        -- draw; a button still waiting in the batch is then asked for the other copy of its
        -- item (the same item ID, so nothing clears it on the way in). The old request must
        -- not be drawn, and must not take the new one with it.
        world.drawn = {}
        local buttons = { NewButton(world), NewButton(world), NewButton(world) }
        for index, each in ipairs(buttons) do
            Ask(world, each, SlotItem(world, 1, 30))
            buttons[each] = index
        end
        client:Tick(1)
        Equal(DrawCount(world), 1, "stale: the first frame drew one of three")
        local waiting
        for _, each in ipairs(buttons) do
            if Draws(world, each) == 0 then
                waiting = each
                break
            end
        end
        local other = SlotItem(world, 2, 30)
        Ask(world, waiting, other)
        client:Tick(6)
        local waitingDraws, waitingLast = Draws(world, waiting)
        Equal(waitingDraws, 1, "stale: the button asked again is drawn once")
        Check(waitingLast and waitingLast.item == other, "stale: with what it was asked for last")
        Check(waitingLast and waitingLast.item ~= nil, "stale: and is not cleared after it")
        Check(core:IsQueueIdle(), "stale: the queue is idle afterwards")

        -- A button given up (its window cleared it and took its key away) is not drawn.
        world.drawn = {}
        local gone = NewButton(world)
        Ask(world, gone, SlotItem(world, 7))
        core:ClearButton(gone)
        core:ClearButtonState(gone)
        client:Tick(2)
        Equal((Draws(world, gone)), 0, "gone: a button that was cleared before its draw is not drawn")
        Check(core:IsQueueIdle(), "gone: and nothing is left waiting for it")

        -- A window whose pending work is cancelled.
        world.drawn = {}
        local cancelled = NewButton(world)
        Ask(world, cancelled, SlotItem(world, 9))
        core:CancelPending(world.feature)
        client:Tick(2)
        Equal(DrawCount(world), 0, "cancel: a cancelled request is not drawn")
        NoErrors(world, "one")
    end

    do
        local world = QueueWorld()
        local core, client = world.core, world.client

        -- An item whose data has to be loaded first: drawn when the answer comes, and a newer
        -- request for its button is not replaced by the older one coming back.
        local answers = {}
        local function Unloaded(slot)
            local item = SlotItem(world, slot)
            item.loaded = false
            function item:IsDataEvictable() return false end
            function item:ContinueWithCancelOnRecordLoad(callback)
                answers[#answers + 1] = function()
                    self.loaded = true
                    callback(self:GetItemID(), true)
                end
                return function() end
            end
            return item
        end

        local button = NewButton(world)
        local slow = Unloaded(3)
        Ask(world, button, slow)
        client:Tick(3)
        Equal(DrawCount(world), 0, "load: an item that is not loaded is not drawn")
        Equal(#answers, 1, "load: the client was asked for it once")
        Check(not core:IsQueueIdle(), "load: the queue is not idle while it waits")
        Check(core:GetScript("OnUpdate") == nil, "load: but it does not run a pass every frame meanwhile")
        answers[1]()
        client:Tick(2)
        local count, last = Draws(world, button)
        Equal(count, 1, "load: it is drawn once the answer is there")
        Check(last and last.item == slow, "load: as the item that was asked for")
        Check(core:IsQueueIdle(), "load: then the queue is idle")

        world.drawn, answers = {}, {}
        local older, newer = Unloaded(4), SlotItem(world, 4)
        Ask(world, button, older)
        client:Tick(3)
        Ask(world, button, newer)
        answers[1]()
        client:Tick(3)
        count, last = Draws(world, button)
        Check(last and last.item == newer, "load: a newer request stands when the older one's item arrives")
        NoErrors(world, "load")
    end

    do
        local world = QueueWorld()
        local core, client, feature = world.core, world.client, world.feature

        -- A draw owed to a button that is not on screen (AskWhenOnScreen): the window is told
        -- once when the button comes on screen. A bag with two buttons; the bag is what opens
        -- and closes.
        local came = {}
        function feature:OnButtonOnScreen(context) came[#came + 1] = context end
        local bag = client:NewFrame("Frame")
        local button, other = client:NewFrame("Button", nil, bag), client:NewFrame("Button", nil, bag)
        Check(core:AskWhenOnScreen(button, feature, "never asked") == false,
            "owed: a button never asked for has no overlay to tell of its coming, so nothing is noted")
        Ask(world, button, SlotItem(world, 3))
        Ask(world, other, SlotItem(world, 4))
        client:Tick(2)
        local overlay = core:GetCaerdonButton(button)
        Check(core:AskWhenOnScreen(button, feature, "on screen") == false, "owed: nothing is noted for a button on screen")
        Check(overlay:GetScript("OnShow") == nil, "owed: and its overlay gets no script")

        client:SetFrameShown(bag, false)
        Check(not overlay:IsVisible(), "owed: with the bag closed the overlay is not on screen")
        Check(core:AskWhenOnScreen(button, feature, "first") == true, "owed: a button of a closed bag is noted")
        Check(core:AskWhenOnScreen(button, feature, "second") == true, "owed: and again at the next refresh")
        Check(core:IsQueueIdle(), "owed: nothing is queued for it")
        world.drawn = {}
        client:Tick(3)
        Equal(DrawCount(world), 0, "owed: and nothing is drawn while the bag is closed")
        Equal(#came, 0, "owed: the window is not told yet")
        client:SetFrameShown(bag, true)
        Equal(#came, 1, "owed: the window is told once when the bag opens")
        Equal(came[1], "second", "owed: with what it handed over last")
        Check(overlay:GetScript("OnShow") == nil, "owed: the script is gone once it has run")
        Check(core:GetCaerdonButton(other):GetScript("OnShow") == nil, "owed: a button nothing was owed to never had one")
        client:SetFrameShown(bag, false)
        client:SetFrameShown(bag, true)
        Equal(#came, 1, "owed: opening the bag again tells nobody")

        -- Asked for in between: the debt is settled, by a request or by a clear.
        client:SetFrameShown(bag, false)
        core:AskWhenOnScreen(button, feature, "third")
        Ask(world, button, SlotItem(world, 3))
        Check(overlay:GetScript("OnShow") == nil, "settled: a request for the button takes the script off")
        client:SetFrameShown(bag, true)
        Equal(#came, 1, "settled: and the window is not told when the bag opens")
        client:Tick(2)
        client:SetFrameShown(bag, false)
        core:AskWhenOnScreen(button, feature, "fourth")
        core:ClearButton(button)
        client:SetFrameShown(bag, true)
        Equal(#came, 1, "settled: nor after the button was cleared")

        -- A button hidden by itself in an open bag (a collapsed section).
        Ask(world, button, SlotItem(world, 3))
        client:Tick(2)
        client:SetFrameShown(button, false)
        Check(core:AskWhenOnScreen(button, feature, "fifth") == true, "section: a hidden button of an open bag is noted")
        Check(core:AskWhenOnScreen(other, feature, "other") == false, "section: its neighbour on screen is not")
        client:SetFrameShown(button, true)
        Equal(came[2], "fifth", "section: and the window is told when the button is shown")

        -- The window asks from there, and the button is drawn a frame later.
        function feature:OnButtonOnScreen(context) Ask(world, context.button, context.item) end
        client:SetFrameShown(bag, false)
        local fresh = SlotItem(world, 3)
        core:AskWhenOnScreen(button, feature, { button = button, item = fresh })
        world.drawn = {}
        client:SetFrameShown(bag, true)
        Equal(DrawCount(world), 0, "paid: nothing is drawn in the frame the bag opens in")
        client:Tick(1)
        local count, last = Draws(world, button)
        Equal(count, 1, "paid: the button is drawn in the next")
        Check(last and last.item == fresh, "paid: with the item the window asked for")
        Equal((Draws(world, other)), 0, "paid: a button nothing was owed to is not drawn")
        Check(overlay:GetScript("OnShow") == nil, "paid: and no script is left")
        NoErrors(world, "owed")

        -- An error in the window's hook is reported and the debt is gone with it.
        function feature:OnButtonOnScreen() error("the window's hook raised an error") end
        client:SetFrameShown(bag, false)
        core:AskWhenOnScreen(button, feature, "sixth")
        client:SetFrameShown(bag, true)
        Equal(#client.errors, 1, "error: an error in the window's hook reaches the error handler")
        Check(overlay:GetScript("OnShow") == nil, "error: and is not raised again at the next opening")
    end

    --------------------------------------------------------------------------------------
    -- 3 and 4. The real drawing, written down
    --------------------------------------------------------------------------------------

    -- Widgets that remember what the drawing reads back, and a list of every call that
    -- changes one. A frame is named by its type and the order it was first seen in.
    local function Recording(world)
        local client = world.client
        local base = client.frameMeta
        local values = setmetatable({}, { __mode = "k" })
        local labels, seen = setmetatable({}, { __mode = "k" }), {}
        local log = {}
        world.log = log

        local function Value(frame)
            local value = values[frame]
            if not value then
                value = {}
                values[frame] = value
            end
            return value
        end
        local function Label(frame)
            local label = labels[frame]
            if not label then
                local kind = frame:GetObjectType()
                seen[kind] = (seen[kind] or 0) + 1
                label = kind .. seen[kind]
                labels[frame] = label
            end
            return label
        end
        world.Label = Label
        local function Text(value)
            local kind = type(value)
            if kind == "table" then
                return type(rawget(value, 0)) == "userdata" and Label(value) or "{...}"
            elseif kind == "number" then
                return ("%.5g"):format(value)
            elseif kind == "string" then
                return '"' .. value .. '"'
            elseif kind == "function" then
                return "<function>"
            end
            return tostring(value)
        end

        local stateful = {}
        function stateful:SetTexture(texture) Value(self).texture, Value(self).atlas = texture, nil end
        function stateful:GetTexture() return Value(self).texture end
        function stateful:SetAtlas(atlas) Value(self).atlas, Value(self).texture = atlas, nil end
        function stateful:GetAtlas() return Value(self).atlas end
        function stateful:SetAlpha(alpha) Value(self).alpha = alpha end
        function stateful:SetVertexColor(r, g, b) Value(self).colour = ("%.2f %.2f %.2f"):format(r, g, b) end
        function stateful:GetAlpha() return Value(self).alpha or 1 end
        function stateful:Play() Value(self).playing = true end
        function stateful:Stop() Value(self).playing = false end
        function stateful:Finish() Value(self).playing = false end
        function stateful:IsPlaying() return Value(self).playing == true end
        function stateful:GetFont() return "Fonts\\FRIZQT__.TTF", 10, "OUTLINE" end
        function stateful:GetStringWidth() return 6 * #(self:GetText() or "") end
        function stateful:GetStringHeight() return 10 end
        function stateful:SetPoint(...) Value(self).point = { ... } end
        function stateful:GetPoint()
            local point = Value(self).point
            if point then
                return point[1], point[2], point[3], point[4], point[5]
            end
        end
        function stateful:ClearAllPoints() Value(self).point = nil end
        function stateful:GetFrameStrata() return "MEDIUM" end
        function stateful:SetFrameLevel(level) Value(self).level = level end
        function stateful:GetFrameLevel() return Value(self).level or 3 end
        function stateful:SetFormattedText(pattern, ...) self:SetText(pattern:format(...)) end
        world.Value = Value

        local wrappers = {}
        client.frameMeta = {
            __index = function(frame, key)
                local method = stateful[key] or base.__index(frame, key)
                if type(method) ~= "function" then
                    return method
                end
                if key:find("^Get%u") or key:find("^Is%u") or key:find("^Has%u") or key:find("^Does%u") then
                    return method
                end
                local wrapper = wrappers[key]
                if not wrapper then
                    wrapper = function(self, ...)
                        if world.recording then
                            local parts = {}
                            for index = 1, select("#", ...) do
                                parts[index] = Text((select(index, ...)))
                            end
                            log[#log + 1] = ("%s:%s(%s)"):format(Label(self), key, table.concat(parts, ", "))
                        end
                        return method(self, ...)
                    end
                    wrappers[key] = wrapper
                end
                return wrapper
            end,
        }
    end

    -- What the drawing reads off an item, as a plain table.
    local function DrawnItem(fields)
        fields = fields or {}
        local data = {}
        function data:GetEquipmentSets() return fields.sets end
        function data:GetHousingInfo() return fields.housing end
        local item = { extraData = fields.extraData }
        function item:GetItemData() return data end
        function item:GetEquipLocation() return fields.equipLoc or "INVTYPE_CHEST" end
        function item:GetCaerdonItemType() return fields.housing and "Housing" or "Equipment" end
        function item:HasItemLocationBankOrBags() return fields.inBags == true end
        return item
    end

    local STATUSES = { "own", "ownPlus", "transform", "other", "otherPlus", "send", "otherNoLoot", "otherPlusNoLoot", "otherSpec",
        "otherSpecPlus", "lowSkill", "lowSkillPlus", "upgrade", "upgradeLowSkill", "upgradeNonEquipment", "sellable",
        "auction", "auctionGoods", "quest", "collected", "oldexpansion", "openable", "locked", "readable",
        "refundable", "canCombine", "readyToCombine", "needForProfession", "housingOwned", "waiting", "notAStatus" }

    -- Each: what one button is drawn with, status after status. config(c) changes the settings,
    -- options(world, button) makes the options table, button(world, button) prepares the button.
    local VARIANTS = {
        { name = "plain" },
        { name = "upgrade", binding = "BoE",
            info = { upgradeItemLevelDelta = 5, isUpgrade = true, upgradeStatus = "upgrade", canEquip = true,
                hasMetRequirements = true } },
        { name = "off-tree", binding = "BoA",
            info = { pawnOffTreeUpgrade = true, upgradeItemLevelDelta = 3, upgradeStatus = "upgradeLowSkill" },
            config = function(config) config.Icon.ShowOtherSpecUpgrades = true end },
        { name = "off-tree, not shown", binding = "BoA",
            info = { pawnOffTreeUpgrade = true, upgradeItemLevelDelta = 3, upgradeStatus = "upgradeLowSkill" } },
        -- Gear for another loot spec that the played spec's scale calls an upgrade: one for
        -- what is worn, drawn in the other spec's red whatever the setting says.
        { name = "other spec", binding = "WuE",
            info = { upgradeMatchesSpec = false, pawnIdentifiedUpgrade = true, upgradeStatus = "upgrade",
                upgradeItemLevelDelta = 2 },
            config = function(config) config.Icon.ShowOtherSpecUpgrades = true end },
        { name = "other spec, setting off", binding = "WuE",
            info = { upgradeMatchesSpec = false, pawnIdentifiedUpgrade = true, upgradeStatus = "upgrade",
                upgradeItemLevelDelta = 2 } },
        -- Gear for another loot spec that only its item level makes an upgrade: one for another
        -- spec, so by the setting, which is off by default: neither arrow nor gain then.
        { name = "other spec by item level", binding = "WuE",
            info = { upgradeMatchesSpec = false, isUpgrade = true, upgradeStatus = "upgrade", upgradeItemLevelDelta = 2 },
            config = function(config) config.Icon.ShowOtherSpecUpgrades = true end },
        { name = "other spec by item level, not shown", binding = "WuE",
            info = { upgradeMatchesSpec = false, isUpgrade = true, upgradeStatus = "upgrade", upgradeItemLevelDelta = 2 } },
        { name = "pawn", info = { pawnIdentifiedUpgrade = true, upgradeStatus = "upgrade" } },
        -- A higher item level whose arrow is switched off: no upgrade, and the gain alone.
        { name = "gain without the arrow", info = { upgradeItemLevelDelta = 3, canEquip = true, hasMetRequirements = true } },
        { name = "level gain switched off", noGain = true, binding = "BoE",
            info = { upgradeItemLevelDelta = 5, isUpgrade = true, upgradeStatus = "upgrade" } },
        { name = "equal level",
            info = { equalItemLevelEquipped = true, canEquip = true, hasMetRequirements = true, matchesLootSpec = true },
            config = function(config) config.Icon.SameLevelBehavior = "neutral" end },
        { name = "equal level, red text",
            info = { equalItemLevelEquipped = true, canEquip = true, hasMetRequirements = true, matchesLootSpec = true,
                unusableNow = true },
            config = function(config) config.Icon.SameLevelBehavior = "neutral" end },
        { name = "gear set", binding = "Alpha", item = { sets = { "Alpha" } },
            config = function(config) config.Binding.ShowGearSets = true end },
        { name = "gear set as icon", binding = "Alpha", item = { sets = { "Alpha" } },
            config = function(config)
                config.Binding.ShowGearSets = true
                config.Binding.ShowGearSetsAsIcon = true
            end },
        -- A gear set's piece that is better than what is worn, with the arrow on such pieces
        -- (the default) and without it, each with the set's name alone and with its icon.
        { name = "gear set, upgrade", binding = "Alpha", item = { sets = { "Alpha" } },
            info = { upgradeItemLevelDelta = 5, isUpgrade = true, upgradeStatus = "upgrade", canEquip = true,
                hasMetRequirements = true },
            config = function(config) config.Binding.ShowGearSets = true end },
        { name = "gear set as icon, upgrade", binding = "Alpha", item = { sets = { "Alpha" } },
            info = { upgradeItemLevelDelta = 5, isUpgrade = true, upgradeStatus = "upgrade", canEquip = true,
                hasMetRequirements = true },
            config = function(config)
                config.Binding.ShowGearSets = true
                config.Binding.ShowGearSetsAsIcon = true
            end },
        { name = "gear set, upgrade, no arrow on sets", binding = "Alpha", item = { sets = { "Alpha" } },
            info = { upgradeItemLevelDelta = 5, isUpgrade = true, upgradeStatus = "upgrade", canEquip = true,
                hasMetRequirements = true },
            config = function(config)
                config.Binding.ShowGearSets = true
                config.Icon.ShowUpgradeOnGearSets = false
            end },
        { name = "gear set as icon, upgrade, no arrow on sets", binding = "Alpha", item = { sets = { "Alpha" } },
            info = { upgradeItemLevelDelta = 5, isUpgrade = true, upgradeStatus = "upgrade", canEquip = true,
                hasMetRequirements = true },
            config = function(config)
                config.Binding.ShowGearSets = true
                config.Binding.ShowGearSetsAsIcon = true
                config.Icon.ShowUpgradeOnGearSets = false
            end },
        -- A set's piece that only another spec's Pawn scale calls an upgrade, and one for another
        -- loot spec: neither gets the arrow or the badge, with the arrow on set pieces on.
        { name = "gear set, other spec's scale", binding = "Alpha", item = { sets = { "Alpha" } },
            info = { pawnOffTreeUpgrade = true, upgradeItemLevelDelta = 3, isUpgrade = true, upgradeStatus = "upgrade" },
            config = function(config) config.Binding.ShowGearSets = true end },
        { name = "gear set as icon, other spec's scale", binding = "Alpha", item = { sets = { "Alpha" } },
            info = { pawnOffTreeUpgrade = true, upgradeItemLevelDelta = 3, isUpgrade = true, upgradeStatus = "upgrade" },
            config = function(config)
                config.Binding.ShowGearSets = true
                config.Binding.ShowGearSetsAsIcon = true
            end },
        { name = "gear set as icon, other loot spec", binding = "Alpha", item = { sets = { "Alpha" } },
            info = { upgradeMatchesSpec = false, upgradeItemLevelDelta = 2, isUpgrade = true, upgradeStatus = "upgrade" },
            config = function(config)
                config.Binding.ShowGearSets = true
                config.Binding.ShowGearSetsAsIcon = true
                config.Icon.ShowOtherSpecUpgrades = true
            end },
        -- A piece kept for a look it would gain: taken to the upgrade vendor, or there and to the
        -- Catalyst, whose mark is then the small one. The plain variant has no word of where.
        { name = "look by raising", info = { transformLook = { route = "upgrade" } } },
        { name = "look at the Catalyst and by raising",
            info = { transformLook = { route = "upgrade", secondRoute = "catalyst" } } },
        -- An upgrade with a look to gain, in a window that draws no arrow: the look's mark stands
        -- in the arrow's place. And one with nothing to gain, which has no icon as before.
        { name = "upgrade with a look to gain, arrows off",
            info = { transformLook = { route = "upgrade" }, upgradeItemLevelDelta = 5, isUpgrade = true,
                upgradeStatus = "upgrade", canEquip = true, hasMetRequirements = true },
            config = function(config) config.Icon.ShowUpgradeIcon = false end },
        { name = "upgrade with a look at the Catalyst and by raising, arrows off",
            info = { transformLook = { route = "upgrade", secondRoute = "catalyst" }, upgradeItemLevelDelta = 5,
                isUpgrade = true, upgradeStatus = "upgrade", canEquip = true, hasMetRequirements = true },
            config = function(config) config.Icon.ShowUpgradeIcon = false end },
        { name = "upgrade, arrows off",
            info = { upgradeItemLevelDelta = 5, isUpgrade = true, upgradeStatus = "upgrade", canEquip = true,
                hasMetRequirements = true },
            config = function(config) config.Icon.ShowUpgradeIcon = false end },
        -- A look worked out for a piece (no route: none counts) is no mark.
        { name = "upgrade with no look that counts, arrows off",
            info = { transformLook = { looks = {} }, isUpgrade = true, upgradeStatus = "upgrade" },
            config = function(config) config.Icon.ShowUpgradeIcon = false end },
        -- The two badges on one piece, which the status code does not make: the arrow stands.
        { name = "look at the Catalyst and by raising, and an upgrade",
            info = { transformLook = { route = "upgrade", secondRoute = "catalyst" }, upgradeStatus = "upgrade" } },
        { name = "look at the Catalyst, icons switched off",
            info = { transformLook = { route = "upgrade", secondRoute = "catalyst" } }, hide = { "ownIcon" } },
        { name = "in the bags", binding = "BoE", item = { inBags = true },
            info = { upgradeItemLevelDelta = 4, upgradeStatus = "upgrade" },
            config = function(config) config.Icon.ShowAuctionValue = true end },
        { name = "relative frame, small, searched", binding = "BoE", searched = true,
            info = { upgradeItemLevelDelta = 7, upgradeStatus = "upgrade" },
            options = function(world, button)
                return { relativeFrame = button.icon, statusProminentSize = 13, isFiltered = true }
            end },
        { name = "filter color, hand-fitted", binding = "BoE",
            info = { upgradeItemLevelDelta = 1, upgradeStatus = "upgrade" },
            options = function()
                return { isFiltered = true, filterColor = { GetRGB = function() return 0.5, 0.25, 0.125 end },
                    fixedLayout = true, overrideStatusPosition = "BOTTOMRIGHT", overrideBindingPosition = "TOP",
                    bindingScale = 0.8, hasCount = true, statusOffsetX = 2, statusOffsetY = 3,
                    statusBackgroundOffsetX = 1, statusBackgroundOffsetY = -1, bindingOffsetX = 2, bindingOffsetY = 4 }
            end },
        { name = "host places parts", binding = "BoE", info = { upgradeItemLevelDelta = 6, upgradeStatus = "upgrade" },
            options = function() return { hostPlacesParts = true } end },
        { name = "round, kept inside", binding = "BoA",
            options = function() return { roundStatusIcon = true, keepInsideWhenClipped = true, statusProminentSize = 24 } end },
        { name = "no window", feature = false, binding = "BoE", info = { upgradeItemLevelDelta = 5, upgradeStatus = "upgrade" } },
        { name = "the player's layout", binding = "BoE", info = { upgradeItemLevelDelta = 5, upgradeStatus = "upgrade" },
            options = function() return { hasCount = true } end,
            config = function(config)
                config.Icon.EnableAnimation = false
                config.Icon.Position, config.Icon.Scale, config.Icon.OffsetX, config.Icon.OffsetY = "BOTTOMLEFT", 150, 2, -3
                config.Binding.Position, config.Binding.Scale, config.Binding.OffsetX = "BOTTOMRIGHT", 120, -1
                config.Icon.UpgradeDelta = { Position = "BOTTOMRIGHT", Scale = 80, OffsetX = 1, OffsetY = 1 }
            end },
        { name = "housing", item = { housing = { iconAtlas = "housing-decor", firstAcquisitionBonus = 10 } } },
        { name = "first craft", item = { extraData = { recipeInfo = { firstCraft = true } } } },
        { name = "icons switched off", binding = "BoE", info = { upgradeItemLevelDelta = 5, upgradeStatus = "upgrade" },
            hide = { "ownIcon", "otherIcon", "sellableIcon", "questIcon", "oldExpansionIcon", "upgradeIcon", "levelGain",
                "auctionIcon" } },
        { name = "text switched off", binding = "BoE", hide = { "bindingStatus" } },
        -- A window that shows upgrades and no learnable icon: the arrow stands in for the icon.
        { name = "learnable icons off", binding = "BoE", info = { upgradeItemLevelDelta = 5, upgradeStatus = "upgrade" },
            hide = { "ownIcon", "otherIcon" } },
        -- A button that is there for the upgrade alone (a list's column for it:
        -- displayInfo.statusIcon off): an upgrade is drawn as the upgrade it is, whatever the
        -- status, and anything else leaves the button without an icon. Last in the list: a case
        -- of its own shifts no other case's widgets.
        { name = "the upgrade alone",
            info = { upgradeItemLevelDelta = 5, isUpgrade = true, upgradeStatus = "upgrade", canEquip = true,
                hasMetRequirements = true },
            hide = { "statusIcon" } },
        { name = "the upgrade alone, where there is none", hide = { "statusIcon" } },
        { name = "the upgrade alone, a gain without the arrow",
            info = { upgradeItemLevelDelta = 3, canEquip = true, hasMetRequirements = true }, hide = { "statusIcon" } },
        -- An upgrade the toon has not the level for yet, one that Pawn names: as a button's
        -- icon, as the badge on a look to learn, and alone in a list's column.
        { name = "an upgrade to come",
            info = { upgradeItemLevelDelta = 5, isUpgrade = true, upgradeStatus = "upgradeLowSkill", canEquip = true,
                pawnIdentifiedUpgrade = true } },
        { name = "an upgrade to come, alone",
            info = { upgradeItemLevelDelta = 5, isUpgrade = true, upgradeStatus = "upgradeLowSkill", canEquip = true,
                pawnIdentifiedUpgrade = true }, hide = { "statusIcon" } },
        -- One button, as a list hands a row to another item: a look to learn with the badge of
        -- an upgrade for now (as "own"), then one with the badge of an upgrade to come (as
        -- "ownPlus", drawn next). info by status.
        { name = "a badge for now, then one to come",
            info = function(status)
                return { upgradeItemLevelDelta = 5, isUpgrade = true, canEquip = true, pawnIdentifiedUpgrade = true,
                    upgradeStatus = status == "own" and "upgrade" or "upgradeLowSkill" }
            end },
    }

    -- One button drawn with every status in turn, the way the queue draws it, with a frame
    -- between two draws for the timers a draw starts. Returns what was on the button after
    -- each status.
    local function DrawVariant(world, variant, direct)
        local core, client = world.core, world.client
        local config = H.DeepCopy(world.defaults)
        config.Icon.ShowUpgradeLevelDelta = not variant.noGain
        if variant.config then
            variant.config(config)
        end
        rawset(client.env, "CaerdonWardrobeConfig", config)
        world.hide = variant.hide

        local button = client:NewFrame("Button")
        button:SetSize(37, 37)
        button.icon = button:CreateTexture()
        button.icon:SetSize(37, 37)
        if variant.searched then
            button.searchOverlay = button:CreateTexture()
        end
        local feature = variant.feature ~= false and world.feature or nil
        local item = DrawnItem(variant.item)
        local after = {}

        for _, status in ipairs(STATUSES) do
            local options = variant.options and variant.options(world, button) or {}
            local info
            if type(variant.info) == "function" then
                info = variant.info(status)
            elseif variant.info then
                info = H.DeepCopy(variant.info)
            end
            world.log[#world.log + 1] = ("== %s / %s"):format(variant.name, status)
            world.recording = true
            core:SetupCaerdonButton(button, item, feature, nil, options)
            if direct then
                -- As the layout editor calls them: each half asks for the display rules itself.
                core:SetItemButtonStatus(button, item, feature, nil, options, status, variant.binding, info)
                core:SetItemButtonMogStatusFilter(button, options.isFiltered)
                core:SetItemButtonBindType(button, item, feature, nil, options, status, variant.binding)
            else
                local drawItem = setmetatable({}, { __index = item })
                -- The binding result carries the status code's own upgrade verdict, which
                -- ProcessItem puts on the transmog info for the badge.
                function drawItem:GetCaerdonStatus()
                    return true, status, variant.binding, { upgradeStatus = info and info.upgradeStatus }, info
                end
                core:ProcessItem(button, drawItem, feature, nil, options)
            end
            client:Tick(3)
            world.recording = false

            local overlay = core:GetCaerdonButton(button)
            local icon = overlay.mogStatus
            local hasIcon, hasText, hasGain = core:GetDrawnParts(button)
            after[status] = {
                texture = icon:GetAtlas() or icon:GetTexture(),
                background = icon.mogStatusBackground:GetTexture(),
                alpha = icon:GetAlpha(),
                text = overlay.bindsOnText:GetText(),
                gain = overlay.upgradeDeltaText:IsShown() and overlay.upgradeDeltaText:GetText() or nil,
                badge = overlay.caerdonHasUpgradeBadge == true,
                colour = world.Value(icon).colour,
                ringColour = world.Value(icon.mogStatusBackground).colour,
                badgeColour = icon.upgradeBadge and world.Value(icon.upgradeBadge).colour or nil,
                badgeRingColour = icon.upgradeBadgeRing and world.Value(icon.upgradeBadgeRing).colour or nil,
                routeBadge = overlay.caerdonHasRouteBadge == true,
                badgeTexture = icon.upgradeBadge and icon.upgradeBadge:IsShown() and
                    (icon.upgradeBadge:GetAtlas() or icon.upgradeBadge:GetTexture()) or nil,
                badgeWidth = icon.upgradeBadge and icon.upgradeBadge:IsShown() and icon.upgradeBadge:GetWidth() or nil,
                ringTexture = icon.upgradeBadgeRing and icon.upgradeBadgeRing:IsShown() and
                    icon.upgradeBadgeRing:GetTexture() or nil,
                hasIcon = hasIcon, hasText = hasText, hasGain = hasGain,
                playing = overlay.mogAnim ~= nil and overlay.mogAnim:IsPlaying(),
                width = icon:GetWidth(),
            }
        end
        world.log[#world.log + 1] = ("== %s / cleared"):format(variant.name)
        world.recording = true
        core:ClearButton(button)
        world.recording = false
        return after
    end

    do
        local world = Start()
        Recording(world)
        local env, core = world.env, world.core
        local results = {}
        -- Through the queue's ProcessItem, then the same again with the two halves called
        -- directly: the same calls on the widgets either way.
        local splitAt
        for _, variant in ipairs(VARIANTS) do
            results[variant.name] = DrawVariant(world, variant, false)
        end
        splitAt = #world.log
        local direct = {}
        for _, variant in ipairs(VARIANTS) do
            direct[variant.name] = DrawVariant(world, variant, true)
        end
        NoErrors(world, "drawing")
        Check(splitAt > 5000, "drawing: the drawing was written down (" .. tostring(splitAt) .. " lines)")

        local RING = "Interface\\HUD\\UIUnitFrameBoss2x"
        local plain = results["plain"]
        Equal(plain.own.texture, "Interface\\Store\\category-icon-featured", "drawn: own is the star")
        Equal(plain.own.width, 20, "drawn: at the full size")
        Equal(plain.own.playing, true, "drawn: and it moves")
        Equal(plain.sellable.texture, "Interface\\Store\\category-icon-bag", "drawn: sellable is the bag")
        Equal(plain.sellable.width, 16, "drawn: as a minor icon")
        Equal(plain.sellable.alpha, 0.9, "drawn: a little see-through")
        Equal(plain.sellable.playing, false, "drawn: and still")
        Equal(plain.upgrade.texture, "Interface\\Buttons\\JumpUpArrow", "drawn: an upgrade is the arrow")
        Equal(plain.upgrade.background, RING, "drawn: on its ring")
        Equal(plain.notAStatus.hasIcon, false, "drawn: a status the drawing does not know leaves no icon")
        Equal(plain.own.gain, nil, "drawn: no level gain without one")

        local upgrade = results["upgrade"]
        Equal(upgrade.upgrade.gain, "+5", "gain: the upgrade shows its level gain")
        Equal(upgrade.upgrade.hasGain, true, "gain: and says so")
        Equal(upgrade.upgrade.badge, false, "gain: with no badge on the arrow itself")
        Equal(upgrade.own.badge, true, "badge: a look to learn that is also an upgrade carries the arrow as a badge")
        Equal(upgrade.own.texture, "Interface\\Store\\category-icon-featured", "badge: on the star")
        Equal(upgrade.own.gain, "+5", "badge: with the level gain")
        Equal(upgrade.notAStatus.texture, "Interface\\Buttons\\JumpUpArrow", "badge: where there is no icon to carry it, the arrow is the icon")
        Equal(upgrade.own.text, "|cFF00FF00BoE|r", "text: the binding text beside it")
        Equal(upgrade.own.hasText, true, "text: and says so")
        Equal(upgrade.waiting.badge, false, "badge: none on the waiting icon")
        Equal(results["level gain switched off"].upgrade.gain, nil, "gain: none with the setting off, which is the default")
        Equal(results["level gain switched off"].own.badge, true, "gain: the badge does not depend on it")

        local equal = results["equal level"]
        Equal(equal.collected.texture, "Interface\\PaperDollInfoFrame\\StatSortArrows", "equal: a tie with the worn piece shows the balance")
        Equal(results["equal level, red text"].collected.hasIcon, false, "equal: not for a piece the toon cannot wear now")
        Equal(plain.collected.hasIcon, false, "equal: and not without the setting")
        Equal(results["gear set as icon"].collected.texture, "Interface\\Store\\category-icon-clothes", "sets: a set piece can show the clothes icon")
        Equal(results["gear set"].collected.text, "|cFFFFFFFFAlpha|r", "sets: or the set's name")

        -- A set's piece that is better than what is worn. The arrow on such pieces is a setting.
        local CLOTHES, ARROW = "Interface\\Store\\category-icon-clothes", "Interface\\Buttons\\JumpUpArrow"
        local named, withIcon = results["gear set, upgrade"], results["gear set as icon, upgrade"]
        Equal(named.upgrade.texture, ARROW, "sets: a set piece that is an upgrade gets the arrow")
        Equal(named.upgrade.gain, "+5", "sets: with the level gain")
        Equal(named.upgrade.text, "|cFFFFFFFFAlpha|r", "sets: beside the set's name")
        Equal(withIcon.upgrade.texture, CLOTHES, "sets: with the set's icon on, the piece keeps that icon")
        Equal(withIcon.upgrade.badge, true, "sets: and the arrow is the badge on it")
        Equal(withIcon.upgrade.gain, "+5", "sets: with the level gain")
        Equal(withIcon.upgradeLowSkill.texture, CLOTHES, "sets: the same below the piece's level")
        Equal(withIcon.upgradeLowSkill.badge, true, "sets: badge and all")
        Equal(results["gear set as icon"].collected.badge, false, "sets: no badge on a set piece that is no upgrade")
        local namedOff = results["gear set, upgrade, no arrow on sets"]
        local iconOff = results["gear set as icon, upgrade, no arrow on sets"]
        Equal(namedOff.upgrade.hasIcon, false, "sets, arrow off: a set piece is never drawn as an upgrade")
        Equal(namedOff.upgrade.gain, "+5", "sets, arrow off: its level gain is")
        Equal(namedOff.own.badge, false, "sets, arrow off: and no other icon of it carries the badge")
        Equal(iconOff.upgrade.texture, CLOTHES, "sets, arrow off: the set's icon stays on a piece that is an upgrade")
        Equal(iconOff.upgrade.badge, false, "sets, arrow off: without the badge")
        Equal(iconOff.upgrade.gain, "+5", "sets, arrow off: with the level gain")
        local otherScale = results["gear set, other spec's scale"]
        local otherScaleIcon = results["gear set as icon, other spec's scale"]
        Equal(otherScale.upgrade.hasIcon, false, "sets, other spec: an upgrade for another spec's scale alone gets no arrow on a set piece")
        Equal(otherScale.own.badge, false, "sets, other spec: and no badge on another icon of it")
        Equal(otherScaleIcon.upgrade.texture, CLOTHES, "sets, other spec: with the set's icon on, that icon")
        Equal(otherScaleIcon.upgrade.badge, false, "sets, other spec: without the badge")
        Equal(results["gear set as icon, other loot spec"].upgrade.badge, false, "sets, other spec: nor for another loot spec's gear")
        Equal(results["off-tree"].upgrade.texture, ARROW, "sets, other spec: a piece of no set keeps that arrow")
        Equal(results["off-tree"].upgradeLowSkill.texture, "Interface\\WorldMap\\Gear_64Grey",
            "sets, other spec: and the mark of an upgrade to come where its level is not reached")

        -- A button for the upgrade alone: the arrow under every status where the piece is an
        -- upgrade, with its gain; nothing where it is none, but under the two statuses that
        -- are the upgrade; and a gain alone where the arrow is not earned.
        local alone, none, gainAlone = results["the upgrade alone"], results["the upgrade alone, where there is none"],
            results["the upgrade alone, a gain without the arrow"]
        for _, status in ipairs(STATUSES) do
            if status ~= "waiting" then
                -- Under the status of an upgrade to come it is that status that is drawn.
                local mark = status == "upgradeLowSkill" and "Interface\\WorldMap\\Gear_64Grey" or ARROW
                Check(alone[status].texture == mark and alone[status].gain == "+5" and alone[status].badge == false,
                    "alone: the arrow and its gain, and no badge, as " .. status .. " (" .. tostring(alone[status].texture) .. ")")
                -- An upgrade's arrow stands still, also under a status whose own icon moves.
                Equal(alone[status].playing, false, "alone: the arrow does not move, as " .. status)
                Equal(none[status].playing, false, "alone: nor does a button with nothing on it, as " .. status)
            end
            if status ~= "upgrade" and status ~= "upgradeLowSkill" then
                Check(none[status].hasIcon == false and none[status].gain == nil, "alone: nothing where the piece is no upgrade, as " .. status)
                Check(gainAlone[status].hasIcon == false and gainAlone[status].gain == "+3",
                    "alone: a gain without the arrow where the arrow is not earned, as " .. status)
            end
        end
        Equal(alone.waiting.hasIcon, false, "alone: no hourglass while the piece is waited for")

        local gainOnly = results["gain without the arrow"]
        Equal(gainOnly.collected.gain, "+3", "gain: a piece that is no upgrade shows a level gain it carries")
        Equal(gainOnly.collected.hasIcon, false, "gain: with no arrow")
        Equal(gainOnly.collected.badge, false, "gain: and no badge")

        -- Gear for another loot spec. What the played spec's scale calls an upgrade is one for
        -- what is worn: drawn whatever the setting says, in the other spec's red. What only its
        -- item level makes one is for another spec: by the setting.
        local RED, YELLOW = "1.00 0.35 0.35", "1.00 1.00 0.00"

        -- An upgrade to come has the mark the addon has for "not yet", the grey gear of the
        -- lowSkill status, in the arrow's place: with no ring, uncoloured and still, as the
        -- icon, as the badge on a look to learn, and alone in a list's column. One for now, of
        -- the same piece, has Pawn's yellow arrow on the upgrade's own ring.
        local GEAR, CYAN = "Interface\\WorldMap\\Gear_64Grey", "0.00 1.00 1.00"
        local function NoTexture(value) return value == nil or value == "" end
        local toCome, toComeAlone = results["an upgrade to come"], results["an upgrade to come, alone"]
        Check(toCome.upgradeLowSkill.texture == GEAR and NoTexture(toCome.upgradeLowSkill.background),
            "to come: the gear, with no ring (" .. tostring(toCome.upgradeLowSkill.texture) .. " on " ..
            tostring(toCome.upgradeLowSkill.background) .. ")")
        Equal(toCome.upgradeLowSkill.texture, plain.lowSkill.texture, "to come: the same mark as a look for later has")
        Equal(toCome.upgradeLowSkill.width, plain.lowSkill.width, "to come: at the same size")
        Equal(toCome.upgradeLowSkill.colour, plain.lowSkill.colour, "to come: and in no colour of an arrow's")
        Equal(toCome.upgradeLowSkill.playing, false, "to come: and still")
        Equal(toCome.upgradeLowSkill.gain, "+5", "to come: with its gain")
        Check(toCome.upgrade.texture == ARROW and toCome.upgrade.colour == YELLOW and toCome.upgrade.ringColour == CYAN,
            "to come: the same piece as an upgrade for now has Pawn's yellow arrow on the upgrade's ring (" ..
            tostring(toCome.upgrade.colour) .. " on " .. tostring(toCome.upgrade.ringColour) .. ")")
        Check(toCome.own.badge == true and toCome.own.badgeTexture == GEAR and NoTexture(toCome.own.ringTexture) and
            toCome.own.badgeColour == "1.00 1.00 1.00", "to come: on a look to learn the badge is the gear, with no ring (" ..
            tostring(toCome.own.badgeTexture) .. ", " .. tostring(toCome.own.ringTexture) .. ", " .. tostring(toCome.own.badgeColour) .. ")")
        Equal(toCome.own.playing, true, "to come: the look's own icon still moves")
        for _, status in ipairs({ "own", "other", "collected", "sellable", "upgradeLowSkill" }) do
            Check(toComeAlone[status].texture == GEAR and NoTexture(toComeAlone[status].background) and
                toComeAlone[status].badge == false and toComeAlone[status].gain == "+5",
                "to come, alone: the gear and its gain, as " .. status .. " (" .. tostring(toComeAlone[status].texture) .. ")")
            Equal(toComeAlone[status].width, plain.lowSkill.width, "to come, alone: at the mark's own size, as " .. status)
            Equal(toComeAlone[status].playing, false, "to come, alone: and still, as " .. status)
        end
        -- A button that had the badge of an upgrade for now and then has one of an upgrade to
        -- come: the ring and the arrow's colour of the first are gone.
        local reused = results["a badge for now, then one to come"]
        Check(reused.own.badgeTexture == ARROW and reused.own.ringTexture == "Interface\\HUD\\UIUnitFrameBoss2x" and
            reused.own.badgeColour == YELLOW, "to come: a button's badge for now is the yellow arrow in its ring")
        Check(reused.ownPlus.badgeTexture == GEAR and NoTexture(reused.ownPlus.ringTexture) and
            reused.ownPlus.badgeColour == "1.00 1.00 1.00",
            "to come: the same button's badge to come is the gear alone, with no ring and no colour left over (" ..
            tostring(reused.ownPlus.badgeTexture) .. ", " .. tostring(reused.ownPlus.ringTexture) .. ", " ..
            tostring(reused.ownPlus.badgeColour) .. ")")
        -- The badge of an upgrade for now is the arrow in its ring.
        Check(results["upgrade"].own.badge == true and results["upgrade"].own.badgeTexture == ARROW and
            results["upgrade"].own.ringTexture == "Interface\\HUD\\UIUnitFrameBoss2x" and
            results["upgrade"].own.badgeRingColour == CYAN,
            "to come: the badge of an upgrade for now is the arrow in the upgrade's ring (" ..
            tostring(results["upgrade"].own.badgeTexture) .. ")")
        local otherShown, otherAlways = results["other spec"], results["other spec, setting off"]
        Equal(otherShown.upgrade.texture, ARROW, "loot spec: with the setting on the piece has the arrow")
        Equal(otherShown.upgrade.gain, "+2", "loot spec: and its level gain")
        Equal(otherShown.own.badge, true, "loot spec: or the badge on another icon")
        Equal(otherShown.upgrade.colour, RED, "loot spec: in red")
        Equal(otherAlways.upgrade.texture, ARROW, "loot spec: with the setting off too, where the played spec's scale calls it an upgrade")
        Equal(otherAlways.upgrade.gain, "+2", "loot spec: with its level gain")
        Equal(otherAlways.upgrade.colour, RED, "loot spec: in red there too, not Pawn's yellow")
        Equal(otherAlways.own.badge, true, "loot spec: and the badge on another icon")
        Equal(otherAlways.own.badgeColour, RED, "loot spec: red as well")
        -- Under every status it is drawn as it is with the setting on.
        for _, status in ipairs(STATUSES) do
            local on, off = otherShown[status], otherAlways[status]
            if on and off then
                Check(on.texture == off.texture and on.badge == off.badge and on.gain == off.gain and
                    on.colour == off.colour and on.badgeColour == off.badgeColour and on.hasIcon == off.hasIcon,
                    "loot spec: drawn with the setting off as with it on, as " .. status)
            end
        end
        Equal(results["pawn"].upgrade.colour, YELLOW, "loot spec: an upgrade of Pawn's for the spec's own gear stays yellow")
        local otherLevel, otherHidden = results["other spec by item level"], results["other spec by item level, not shown"]
        Equal(otherLevel.upgrade.texture, ARROW, "loot spec: an upgrade by item level alone has the arrow with the setting on")
        Equal(otherLevel.upgrade.colour, RED, "loot spec: in red")
        Equal(otherHidden.upgrade.hasIcon, false, "loot spec: with it off, no arrow")
        Equal(otherHidden.upgrade.gain, nil, "loot spec: no level gain")
        Equal(otherHidden.own.badge, false, "loot spec: and no badge")
        local treeHidden = results["off-tree, not shown"]
        Equal(treeHidden.upgradeLowSkill.hasIcon, false, "other spec: the same for an upgrade only another spec's scale sees")
        Equal(treeHidden.upgradeLowSkill.gain, nil, "other spec: with no level gain")
        Equal(otherHidden.own.texture, "Interface\\Store\\category-icon-featured", "loot spec: the look to learn keeps its own icon")

        local off = results["icons switched off"]
        Equal(off.own.hasIcon, false, "rules: a window that shows no learnable icon gets none")
        Equal(off.sellable.hasIcon, false, "rules: nor a sell icon")
        Equal(off.upgrade.hasIcon, false, "rules: nor an upgrade arrow")
        Equal(off.own.badge, false, "rules: nor its badge")
        Equal(off.own.gain, nil, "rules: nor a level gain")
        Equal(off.own.text, "|cFF00FF00BoE|r", "rules: its text stays")
        -- The grey gear is the star's stand-in for something to learn later: drawn where the
        -- star is, and not where a window shows no learnable icon.
        Equal(results["plain"].lowSkill.texture, "Interface\\WorldMap\\Gear_64Grey", "rules: the gear of something to learn later, where the star is shown")
        Equal(results["plain"].lowSkillPlus.hasIcon, true, "rules: and its green form")
        Equal(off.lowSkill.hasIcon, false, "rules: no gear where a window shows no learnable icon")
        Equal(off.lowSkillPlus.hasIcon, false, "rules: nor its green form")
        Equal(results["look at the Catalyst, icons switched off"].lowSkill.hasIcon, false, "rules: with the star's icon alone switched off too")
        Equal(results["text switched off"].own.text, "", "rules: text switched off is no text")
        Equal(results["text switched off"].own.hasText, false, "rules: and says so")
        Equal(results["no window"].own.hasIcon, false, "rules: a draw with no window has no rules to show an icon by")
        local standIn = results["learnable icons off"].own
        Equal(standIn.texture, "Interface\\Buttons\\JumpUpArrow", "rules: an upgrade whose learnable icon is off is drawn as the upgrade")
        Equal(standIn.badge, false, "rules: with no badge, the arrow being the icon")
        Equal(standIn.width, plain.upgrade.width, "rules: at the upgrade arrow's size, not the star's")
        Equal(standIn.gain, "+5", "rules: and with its level gain")
        Equal(standIn.playing, false, "rules: and still, as an upgrade is, though a look to learn moves")
        Equal(results["in the bags"].auction.hasIcon, true, "rules: the auction icon shows in the bags")
        Equal(plain.auction.hasIcon, true, "rules: elsewhere an auction status falls back to the sell icon")
        Equal(plain.auction.texture, "Interface\\Store\\category-icon-bag", "rules: which is the bag")

        -- A piece kept for a look it would gain says where it is taken.
        -- The mocked client has no atlas, so each mark is its plain texture here.
        local CATALYST, VENDOR = "Interface\\Buttons\\UI-RefreshButton", "Interface\\Icons\\Trade_BlackSmithing"
        Equal(plain.transform.texture, CATALYST, "looks: with no word of where, the Catalyst's mark as before")
        Equal(plain.transform.width, plain.sellable.width, "looks: as a minor icon")
        Equal(plain.transform.playing, false, "looks: and still")
        Equal(plain.transform.routeBadge, false, "looks: with nothing on it")
        local raised, both = results["look by raising"], results["look at the Catalyst and by raising"]
        Equal(raised.transform.texture, VENDOR, "looks: a piece that only has to be raised has the upgrade vendor's mark")
        Equal(raised.transform.width, plain.transform.width, "looks: at the Catalyst mark's size")
        Equal(raised.transform.routeBadge, false, "looks: with nothing on it")
        Equal(both.transform.texture, VENDOR, "looks: where both have a part, the vendor's mark is the icon")
        Equal(both.transform.routeBadge, true, "looks: and the Catalyst is the small mark on it")
        Equal(both.transform.badgeTexture, CATALYST, "looks: the Catalyst's mark, which reads at that size")
        Equal(both.transform.ringTexture, "", "looks: without the upgrade arrow's ring")
        Equal(both.transform.badge, false, "looks: and it is not taken for an upgrade's badge")
        Check(both.transform.badgeWidth > upgrade.own.badgeWidth, "looks: larger than the arrow, which sits inside a ring")
        Equal(both.own.routeBadge, false, "looks: no other status carries it")
        Equal(both.collected.badgeTexture, nil, "looks: and it is gone with the next draw")
        Equal(upgrade.own.badgeTexture, ARROW, "looks: an upgrade's badge is the arrow as it was")
        Equal(upgrade.own.ringTexture, RING, "looks: on its ring")
        Equal(upgrade.transform.badge, true, "looks: an upgrade's arrow comes first on the mark, were the two to meet")
        local met = results["look at the Catalyst and by raising, and an upgrade"].transform
        Equal(met.badge, true, "looks: were both to meet on one piece, the upgrade's arrow is the badge")
        Equal(met.routeBadge, false, "looks: and the Catalyst's mark is not drawn over it")
        Equal(met.badgeTexture, ARROW, "looks: the arrow")
        Equal(met.ringTexture, RING, "looks: on its ring")
        -- An upgrade keeps its arrow over the look's mark, and gives way to it where no arrow is drawn.
        Equal(raised.upgrade.texture, ARROW, "looks: an upgrade with a look to gain is drawn as the upgrade")
        Equal(raised.upgrade.routeBadge, false, "looks: with no mark of the look on the arrow")
        local noArrow = results["upgrade with a look to gain, arrows off"]
        Equal(noArrow.upgrade.texture, VENDOR, "looks: with the arrow switched off, the look's mark stands in its place")
        Equal(noArrow.upgrade.width, plain.transform.width, "looks: at the mark's own size")
        Equal(noArrow.upgrade.alpha, plain.transform.alpha, "looks: as see-through as the mark is")
        Equal(noArrow.upgrade.gain, "+5", "looks: with the level gain, which has a setting of its own")
        Equal(noArrow.upgrade.badge, false, "looks: and no arrow as a badge on it")
        Equal(noArrow.upgradeLowSkill.texture, VENDOR, "looks: the same below the piece's level")
        local noArrowBoth = results["upgrade with a look at the Catalyst and by raising, arrows off"]
        Equal(noArrowBoth.upgrade.texture, VENDOR, "looks: the vendor's mark for an upgrade with a look at both")
        Equal(noArrowBoth.upgrade.routeBadge, true, "looks: with the Catalyst's small mark on it")
        Equal(noArrowBoth.upgrade.badgeTexture, CATALYST, "looks: the Catalyst's mark")
        Equal(results["upgrade, arrows off"].upgrade.hasIcon, false, "looks: an upgrade with nothing to gain has no icon with the arrow off")
        Equal(results["upgrade with no look that counts, arrows off"].upgrade.hasIcon, false,
            "looks: nor one whose looks do not count")
        local hidden = results["look at the Catalyst, icons switched off"]
        Equal(hidden.transform.hasIcon, false, "looks: a window that shows no learnable icon shows no mark")
        Equal(hidden.transform.routeBadge, false, "looks: and no small mark without it")

        local searched = results["relative frame, small, searched"]
        Equal(searched.own.alpha, 0.3, "search: an icon on a slot the search has dimmed is dimmed")
        Equal(searched.own.width, 13, "search: at the window's own size")
        Equal(results["housing"].housingOwned.texture, "housing-decor", "housing: the decor's own icon")
        Equal(results["housing"].own.gain, "+10", "housing: the first-acquisition bonus as the gain")

        -- Drawn through the queue or by the two halves directly: the same on the button.
        local differing = {}
        for _, variant in ipairs(VARIANTS) do
            for _, status in ipairs(STATUSES) do
                local one, two = results[variant.name][status], direct[variant.name][status]
                for key, value in pairs(one) do
                    if two[key] ~= value then
                        differing[#differing + 1] = ("%s / %s: %s"):format(variant.name, status, key)
                    end
                end
            end
        end
        Equal(#differing, 0, "direct: the two halves called directly leave the same on the button as a queued draw ("
            .. table.concat(differing, "; ", 1, math.min(#differing, 5)) .. ")")

        local path = os.getenv("CAERDON_DRAW_TRANSCRIPT")
        if path and path ~= "" then
            local file = assert(io.open(path, "wb"))
            file:write(table.concat(world.log, "\n", splitAt + 1), "\n")
            file:close()
            print(("    drawing written to %s (%d lines, the two halves called directly)"):format(path, #world.log - splitAt))
        end
    end

    do
        -- The display rules once per draw, and one timer for a frame's search dimming.
        local world = Start()
        Recording(world)
        local core, client, env = world.core, world.client, world.env
        local timers = 0
        local after = env.C_Timer.After
        env.C_Timer.After = function(seconds, callback)
            timers = timers + 1
            return after(seconds, callback)
        end

        local function Draw(button, status, binding)
            local item = DrawnItem()
            function item:GetCaerdonStatus() return true, status, binding, {}, nil end
            core:SetupCaerdonButton(button, item, world.feature, nil, {})
            core:ProcessItem(button, item, world.feature, nil, {})
        end
        local function Slot(searched)
            local button = client:NewFrame("Button")
            button:SetSize(37, 37)
            if searched ~= nil then
                button.searchOverlay = button:CreateTexture()
                button.searchOverlay:SetShown(searched)
            end
            return button
        end

        local plain = Slot()
        world.displayInfos = 0
        Draw(plain, "own", "BoE")
        Equal(world.displayInfos, 1, "rules: one draw asks the window for its display rules once")
        world.displayInfos = 0
        Draw(plain, nil, nil)
        Equal(world.displayInfos, 0, "rules: a draw with no status and no text does not ask")
        world.displayInfos = 0
        Draw(plain, nil, "BoE")
        Equal(world.displayInfos, 1, "rules: text alone asks once")
        Equal(core:GetCaerdonButton(plain).bindsOnText:GetText(), "|cFF00FF00BoE|r", "rules: and is drawn")

        client:Tick(2)
        timers = 0
        Draw(plain, "own", nil)
        Draw(Slot(), "sellable", nil)
        Equal(timers, 0, "dim: buttons without a search overlay start no timer")

        local dimmed, clear, alsoDimmed = Slot(true), Slot(false), Slot(true)
        Draw(dimmed, "own", nil)
        Draw(clear, "own", nil)
        Draw(alsoDimmed, "sellable", nil)
        Equal(timers, 1, "dim: three draws in a frame on searchable slots start one timer")
        Equal(core:GetCaerdonButton(dimmed).mogStatus:GetAlpha(), 1, "dim: nothing is dimmed in the frame of the draw")
        client:Tick(1)
        Equal(core:GetCaerdonButton(dimmed).mogStatus:GetAlpha(), 0.3, "dim: a frame later the icon on a dimmed slot is dimmed")
        Equal(core:GetCaerdonButton(dimmed).mogStatus.mogStatusBackground:GetAlpha(), 0.3, "dim: with its background")
        Equal(core:GetCaerdonButton(alsoDimmed).mogStatus:GetAlpha(), 0.3, "dim: so is the other one")
        Equal(core:GetCaerdonButton(clear).mogStatus:GetAlpha(), 1, "dim: and not the one whose slot the search left alone")
        Draw(dimmed, "own", nil)
        Equal(timers, 2, "dim: the next frame's draws start a timer of their own")
        NoErrors(world, "rules")
    end
end
