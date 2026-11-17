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

    local STATUSES = { "own", "ownPlus", "other", "otherPlus", "otherNoLoot", "otherPlusNoLoot", "otherSpec",
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
            info = { pawnOffTreeUpgrade = true, upgradeItemLevelDelta = 3, upgradeStatus = "upgradeLowSkill" } },
        { name = "other spec", binding = "WuE",
            info = { upgradeMatchesSpec = false, pawnIdentifiedUpgrade = true, upgradeStatus = "upgrade",
                upgradeItemLevelDelta = 2 },
            config = function(config) config.Icon.ShowMismatchedSpecUpgrades = true end },
        { name = "pawn", info = { pawnIdentifiedUpgrade = true, upgradeStatus = "upgrade" } },
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
            local info = variant.info and H.DeepCopy(variant.info) or nil
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
        Equal(results["gear set"].upgrade.hasIcon, false, "sets: and is never drawn as an upgrade")

        local off = results["icons switched off"]
        Equal(off.own.hasIcon, false, "rules: a window that shows no learnable icon gets none")
        Equal(off.sellable.hasIcon, false, "rules: nor a sell icon")
        Equal(off.upgrade.hasIcon, false, "rules: nor an upgrade arrow")
        Equal(off.own.badge, false, "rules: nor its badge")
        Equal(off.own.gain, nil, "rules: nor a level gain")
        Equal(off.own.text, "|cFF00FF00BoE|r", "rules: its text stays")
        Equal(results["text switched off"].own.text, "", "rules: text switched off is no text")
        Equal(results["text switched off"].own.hasText, false, "rules: and says so")
        Equal(results["no window"].own.hasIcon, false, "rules: a draw with no window has no rules to show an icon by")
        local standIn = results["learnable icons off"].own
        Equal(standIn.texture, "Interface\\Buttons\\JumpUpArrow", "rules: an upgrade whose learnable icon is off is drawn as the upgrade")
        Equal(standIn.badge, false, "rules: with no badge, the arrow being the icon")
        Equal(standIn.width, plain.upgrade.width, "rules: at the upgrade arrow's size, not the star's")
        Equal(standIn.gain, "+5", "rules: and with its level gain")
        Equal(results["in the bags"].auction.hasIcon, true, "rules: the auction icon shows in the bags")
        Equal(plain.auction.hasIcon, true, "rules: elsewhere an auction status falls back to the sell icon")
        Equal(plain.auction.texture, "Interface\\Store\\category-icon-bag", "rules: which is the bag")

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
