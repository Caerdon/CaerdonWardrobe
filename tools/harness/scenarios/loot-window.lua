-- The loot window's rows (features/Loot.lua).
--
-- The window builds one row per slot when it opens, and the list tells the feature of each
-- row it builds. Filling a row plays the row's fade-in, and the window plays one of its own as
-- it opens. What is drawn on a row while a fade runs is not left as it was drawn (seen on WoW
-- Forever: an icon with no alpha, a bounce far too fast), so a row is cleared when it is
-- filled and asked for when both fades have ended.
--
-- A slot whose item the client has no data for yet has no link. When the data comes, or the
-- slot changes, the client says LOOT_SLOT_CHANGED and the window fills the row in again
-- itself, without building it: the list's callback does not come a second time.
--
--   1. How the feature attaches: under its own name at the list, and to the client's event.
--   2. A row that is built is cleared and not asked for while a fade-in runs; it is asked for
--      when its own and the window's have ended, whichever ends last.
--   3. LOOT_SLOT_CHANGED: that slot's row, and no other, waits for its fade-in again.
--   4. A full refresh asks for every row that is not fading in.
--   5. A row given back to the list is not asked for; a row used again waits anew.
--   6. A row with no fade-in to listen to is asked for at once.
--   7. What the export says of it.
--
-- The game is hand-made and proves the feature's logic only: what the client does to a row
-- that fades in is the client's to show (the export's [Loot Window] section). The window, its
-- list and the fades are stand-ins with the functions the feature uses. Real code: the core,
-- FeatureMixin.lua, features/Loot.lua.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 29 }

    local function Start(flavor)
        local items = {}
        for id = 950001, 950006 do
            items[id] = { name = "Scrap " .. id, quality = 1, level = 5, minLevel = 0, type = "Miscellaneous", subType = "Junk",
                stack = 20, price = 5, classID = 15, subClassID = 0 }
        end
        local game = H.StockGame(TOON, items)
        -- slots[index] = { id = the item, known = whether the client has a link for it }, or
        -- { money = true }.
        local world = { game = game, slots = {}, rows = {}, pool = {}, asked = {}, cleared = {}, registered = {} }

        local client = H.Client.New({ flavor = flavor, provider = game })
        game.client = client
        local slotTypes = client.listing.enums.Enum.LootSlotType
        game:Set("GetLootSlotLink", function(index)
            local slot = world.slots[index]
            return slot and slot.id and slot.known and game.Link(slot.id) or nil
        end)
        game:Set("GetLootSlotType", function(index)
            local slot = world.slots[index]
            if not slot then
                return slotTypes.None
            end
            return slot.money and slotTypes.Money or slotTypes.Item
        end)

        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))

        -- A fade-in: played by the window's own code, and ended when the scenario says.
        local function Fade()
            local fade = { hooks = {}, playing = false }
            function fade:HookScript(script, handler)
                self.hooks[#self.hooks + 1] = { script = script, handler = handler }
            end
            function fade:IsPlaying() return self.playing end
            function fade:Play() self.playing = true end
            function fade:End()
                self.playing = false
                for _, hook in ipairs(self.hooks) do
                    if hook.script == "OnFinished" then
                        hook.handler(self)
                    end
                end
            end
            return fade
        end

        -- The window: its list holds the rows that are built, in the order of their slots.
        local window = client:NewFrame("Frame", "LootFrame")
        window:Hide()
        window.ShowAnim = Fade()
        local list = {}
        function list:ForEachFrame(func)
            for _, row in ipairs(world.rows) do
                local result = func(row, row:GetElementData())
                if result then
                    return result
                end
            end
        end
        function list:FindFrameByPredicate(predicate)
            for _, row in ipairs(world.rows) do
                if predicate(row) then
                    return row
                end
            end
        end
        window.ScrollBox = list
        rawset(client.env, "ScrollUtil", {
            AddInitializedFrameCallback = function(scrollBox, callback, owner, iterateExisting)
                world.registered[#world.registered + 1] = { scrollBox = scrollBox, callback = callback, owner = owner,
                    iterateExisting = iterateExisting }
            end,
        })

        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "features/Loot.lua", namespace)
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(10)

        world.client, world.env, world.window = client, client.env, window
        local core = client.env.CaerdonWardrobe
        world.core, world.loot = core, core:GetFeature("Loot")

        local realUpdate, realClear = core.UpdateButton, core.ClearButton
        function core:UpdateButton(button, item, feature, locationInfo, options)
            world.asked[#world.asked + 1] = { button = button, id = item and item:GetItemID(), feature = feature,
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

        -- The window opens on these slots, as the client's does: each row is filled, which
        -- plays its fade-in, and the list says so; then the window plays its own. The list's
        -- rows are used again. plain: rows with no fade-in, as a client might have them.
        function world.Open(slots, plain)
            world.slots, world.rows = slots, {}
            window:Show()
            for index = 1, #slots do
                local row = world.pool[index]
                if not row then
                    row = client:NewFrame("Frame", nil, window)
                    row.Item = client:NewFrame("Button", nil, row)
                    row.ShowAnim = not plain and Fade() or nil
                    world.pool[index] = row
                end
                local elementData = { slotIndex = index, group = slots[index].money and 1 or 0, quality = 1 }
                function row:GetElementData() return elementData end
                function row:GetSlotIndex() return elementData.slotIndex end
                world.rows[index] = row
                if row.ShowAnim then
                    row.ShowAnim:Play()
                end
                for _, registration in ipairs(world.registered) do
                    registration.callback(registration.owner, row, elementData)
                end
            end
            window.ShowAnim:Play()
        end
        -- The client changed a slot: the window fills its row in again, then the event comes.
        function world.Change(index)
            local row = world.rows[index]
            if row and row.ShowAnim then
                row.ShowAnim:Play()
            end
            client:Fire("LOOT_SLOT_CHANGED", index)
        end
        -- The window closes: its rows go back to the list, which takes their slot from them.
        function world.Close()
            for _, row in ipairs(world.rows) do
                row.GetElementData, row.GetSlotIndex = nil, nil
            end
            world.rows = {}
            window:Hide()
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
        function world.Report()
            local text = {}
            for _, line in ipairs(world.loot:GetReportLines()) do
                text[#text + 1] = string.rep("  ", line.indent) .. line.text
            end
            return table.concat(text, "\n")
        end
        return world
    end

    for _, flavor in ipairs({ "forever", "retail" }) do
        local label = flavor .. ": "
        local world = Start(flavor)
        local client, loot, game, window = world.client, world.loot, world.game, world.window

        ----------------------------------------------------------------------------------
        -- 1. How the feature attaches
        ----------------------------------------------------------------------------------

        Check(loot ~= nil, label .. "attach: the file registers its feature")
        Equal(#world.registered, 1, label .. "attach: one callback at the list")
        local registration = world.registered[1] or {}
        Check(registration.scrollBox == window.ScrollBox, label .. "attach: at the loot window's list")
        Check(registration.owner == loot, label .. "attach: under the feature itself, which no other addon names")
        Check(world.core:IsEventRegistered("LOOT_SLOT_CHANGED"), label .. "attach: the client's word that a slot changed is heard")
        Equal(#window.ShowAnim.hooks, 1, label .. "attach: and the end of the window's fade-in")

        ----------------------------------------------------------------------------------
        -- 2. Rows as they are built
        ----------------------------------------------------------------------------------

        world.Open({
            { id = 950001, known = true },
            { id = 950002, known = false },
            { money = true },
        })
        local first, second, money = world.rows[1].Item, world.rows[2].Item, world.rows[3].Item
        Equal(#world.asked, 0, label .. "built: no row is asked for while it fades in")
        Check((world.cleared[first] or 0) >= 1, label .. "built: a row is cleared, of what it showed before")
        client:Tick(3)
        Equal(#world.asked, 0, label .. "built: however long the fades run")

        -- The row's fade-in ends first, the window's after it.
        world.rows[1].ShowAnim:End()
        client:Tick(2)
        Equal(world.AskedFor(first), "", label .. "faded: a row whose own fade-in has ended waits for the window's")
        window.ShowAnim:End()
        client:Tick(2)
        Equal(world.AskedFor(first), "950001", label .. "faded: and is asked for when that has ended")
        Equal(world.asked[1] and world.asked[1].key, "1", label .. "faded: at its slot")
        Check(world.asked[1] and world.asked[1].feature == loot, label .. "faded: by the loot window")
        Equal(world.AskedFor(second), "", label .. "faded: a row still fading in is not asked for by the window's end")

        -- The window's has ended, the row's ends after it.
        world.rows[2].ShowAnim:End()
        world.rows[3].ShowAnim:End()
        client:Tick(2)
        Equal(world.AskedFor(second), "", label .. "faded: a row the client has no link for is not asked for")
        Check((world.cleared[second] or 0) >= 2, label .. "faded: it is cleared")
        Equal(world.AskedFor(money), "", label .. "faded: nor is the money's row asked for")
        Equal(world.AskedFor(first), "950001", label .. "faded: and the row that was asked for is not asked for again")

        ----------------------------------------------------------------------------------
        -- 3. A slot the client changed
        ----------------------------------------------------------------------------------

        world.slots[2].known = true
        world.Change(2)
        client:Tick(2)
        Equal(world.AskedFor(second), "", label .. "changed: the row waits for the fade-in the window plays as it fills it")
        world.rows[2].ShowAnim:End()
        client:Tick(2)
        Equal(world.AskedFor(second), "950002", label .. "changed: and is asked for with the link that has come")
        Equal(world.asked[#world.asked].key, "2", label .. "changed: at its slot")
        Equal(world.AskedFor(first), "950001", label .. "changed: no other row is asked for again")

        world.slots[1] = { id = 950003, known = true }
        local clearedBefore = world.cleared[first] or 0
        world.Change(1)
        Check((world.cleared[first] or 0) > clearedBefore, label .. "changed: a slot that holds another item now is cleared at once")
        world.rows[1].ShowAnim:End()
        client:Tick(2)
        Equal(world.AskedFor(first), "950001,950003", label .. "changed: and asked for with the new item when it has faded in")

        local askedBefore = #world.asked
        client:Fire("LOOT_SLOT_CHANGED", 7)
        client:Tick(2)
        Equal(#world.asked, askedBefore, label .. "changed: a slot with no row asks for nothing")

        ----------------------------------------------------------------------------------
        -- 4. A full refresh
        ----------------------------------------------------------------------------------

        world.asked = {}
        loot:Refresh()
        client:Tick(2)
        Equal(world.AskedFor(first), "950003", label .. "refresh: every row is asked for again")
        Equal(world.AskedFor(second), "950002", label .. "refresh: with what its slot holds now")
        Equal(world.AskedFor(money), "", label .. "refresh: and the money's row is not")

        world.asked = {}
        world.rows[1].ShowAnim:Play()
        loot:Refresh()
        client:Tick(2)
        Equal(world.AskedFor(first), "", label .. "refresh: a row that is fading in is left to its fade-in")
        Equal(world.AskedFor(second), "950002", label .. "refresh: the others are asked for")
        world.rows[1].ShowAnim:End()
        client:Tick(2)
        Equal(world.AskedFor(first), "950003", label .. "refresh: and the row is asked for when it has faded in")

        ----------------------------------------------------------------------------------
        -- 7. The export (of the window as it is now)
        ----------------------------------------------------------------------------------

        local report = world.Report()
        Check(report:find("Item Rows Built: 1 with a link, 1 before the client had one", 1, true) ~= nil,
            label .. "export: the rows built, by whether the client had a link (" .. report .. ")")
        Check(report:find("2 with a link then, 0 still without, 1 with no row in the list", 1, true) ~= nil,
            label .. "export: and the slots the client changed")
        Check(report:find("- slot 2: " .. game.Link(950002) .. "; built before the client had a link (on screen, its button's first use, its fade-in running then: yes), changed by the client 1 times; its button: asked for by Loot",
            1, true) ~= nil, label .. "export: a row says how it was built, and what is on its button")
        Check(report:find("built, waits for its fade-in", 1, true) ~= nil, label .. "export: with what happened to it since, in order")
        Check(report:find("asked (faded in)", 1, true) ~= nil, label .. "export: the ask its fade-in brought among it")
        Check(report:find("- slot 3: no link; holds no item now", 1, true) ~= nil, label .. "export: the money's row is named as no item's")

        ----------------------------------------------------------------------------------
        -- 5. Rows given back, and used again
        ----------------------------------------------------------------------------------

        local firstRow = world.rows[1]
        firstRow.ShowAnim:Play()
        world.Close()
        Check(world.Report():find("Open Now: no", 1, true) ~= nil, label .. "export: a closed window lists no rows")
        world.asked = {}
        firstRow.ShowAnim:End()
        window.ShowAnim:End()
        client:Tick(2)
        Equal(#world.asked, 0, label .. "given back: a fade-in that ends on a row the list has taken back asks for nothing")

        world.Open({ { id = 950004, known = true } })
        Check(world.rows[1] == firstRow, label .. "again: the list uses its row again")
        Equal(#firstRow.ShowAnim.hooks, 1, label .. "again: and the row is still listened to once")
        Check(world.Report():find("- slot 1: " .. game.Link(950004) .. "; built with a link (on screen, its button used before, its fade-in running then: yes), changed by the client 0 times",
            1, true) ~= nil, label .. "again: a row built anew starts its history over")
        -- The window's fade-in ends first this time, the row's after it.
        window.ShowAnim:End()
        client:Tick(2)
        Equal(#world.asked, 0, label .. "again: the row waits for its own fade-in")
        firstRow.ShowAnim:End()
        client:Tick(2)
        Equal(world.AskedFor(firstRow.Item), "950004", label .. "again: and is asked for with what it shows now")

        Equal(#client.errors, 0, label .. "no error (" .. tostring(client.errors[1]) .. ")")

        ----------------------------------------------------------------------------------
        -- 6. A row with no fade-in
        ----------------------------------------------------------------------------------

        local plain = Start(flavor)
        plain.Open({ { id = 950005, known = true } }, true)
        plain.client:Tick(2)
        Equal(plain.AskedFor(plain.rows[1].Item), "950005", label .. "no fade-in: a row with none to wait for is asked for as it is built")
        Equal(#plain.client.errors, 0, label .. "no fade-in: no error (" .. tostring(plain.client.errors[1]) .. ")")
    end
end
