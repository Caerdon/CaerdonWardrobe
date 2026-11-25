-- The loot window's rows (features/Loot.lua).
--
-- The window builds one row per slot when it opens, and the list tells the feature of each
-- row it builds. A slot whose item the client has no data for yet has no link then. When the
-- data comes, or the slot changes, the client says LOOT_SLOT_CHANGED and the window fills the
-- row in itself, without building it again: the list's callback does not come a second time.
-- A feature that listens to the list alone left such a row without an icon for as long as the
-- window was open.
--
--   1. How the feature attaches: under its own name at the list, and to the client's event.
--   2. A row built with a link is asked for; one built without is cleared.
--   3. LOOT_SLOT_CHANGED asks for that slot's row, and no other: a link that has come, an
--      item that is another now, a slot with no row.
--   4. A full refresh asks for every row again.
--   5. A row is asked for again when its fade-in has ended, and every row when the window's
--      has: an icon drawn inside a fade comes out of it with no alpha (seen on WoW Forever).
--   6. What the export says of it.
--
-- The game is hand-made and proves the feature's logic only: that the client gives no link
-- for an item it has no data for, and says LOOT_SLOT_CHANGED when it has, is the client's to
-- show (the export's [Loot Window] section). The window and its list are stand-ins with the
-- functions the feature uses. Real code: the core, FeatureMixin.lua, features/Loot.lua.

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
        local world = { game = game, slots = {}, rows = {}, asked = {}, cleared = {}, registered = {} }

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

        -- The window: its list holds the rows that are built, in the order of their slots.
        -- A fade-in: the scenario says when it has ended.
        local function Fade()
            local fade = { hooks = {} }
            function fade:HookScript(script, handler)
                self.hooks[#self.hooks + 1] = { script = script, handler = handler }
            end
            function fade:End()
                for _, hook in ipairs(self.hooks) do
                    if hook.script == "OnFinished" then
                        hook.handler(self)
                    end
                end
            end
            return fade
        end
        world.pool = {}

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

        -- The window opens on these slots: a row is built for each and the list says so. The
        -- list's rows are used again, as the client's are.
        function world.Open(slots)
            world.slots, world.rows = slots, {}
            window:Show()
            for index = 1, #slots do
                local row = world.pool[index]
                if not row then
                    row = client:NewFrame("Frame", nil, window)
                    row.Item = client:NewFrame("Button", nil, row)
                    row.ShowAnim = Fade()
                    world.pool[index] = row
                end
                local elementData = { slotIndex = index, group = slots[index].money and 1 or 0, quality = 1 }
                function row:GetElementData() return elementData end
                function row:GetSlotIndex() return elementData.slotIndex end
                world.rows[index] = row
                for _, registration in ipairs(world.registered) do
                    registration.callback(registration.owner, row, elementData)
                end
            end
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
        local client, loot, game = world.client, world.loot, world.game

        ----------------------------------------------------------------------------------
        -- 1. How the feature attaches
        ----------------------------------------------------------------------------------

        Check(loot ~= nil, label .. "attach: the file registers its feature")
        Equal(#world.registered, 1, label .. "attach: one callback at the list")
        local registration = world.registered[1] or {}
        Check(registration.scrollBox == world.window.ScrollBox, label .. "attach: at the loot window's list")
        Check(registration.owner == loot, label .. "attach: under the feature itself, which no other addon names")
        local hearsChange = false
        for _, frame in ipairs(client.frames) do
            if frame == world.core and frame:IsEventRegistered("LOOT_SLOT_CHANGED") then
                hearsChange = true
            end
        end
        Check(hearsChange, label .. "attach: and the client's word that a slot changed is heard")

        ----------------------------------------------------------------------------------
        -- 2. Rows as they are built
        ----------------------------------------------------------------------------------

        world.Open({
            { id = 950001, known = true },
            { id = 950002, known = false },
            { money = true },
        })
        local withLink, withoutLink, money = world.rows[1].Item, world.rows[2].Item, world.rows[3].Item
        Equal(world.AskedFor(withLink), "950001", label .. "built: a row with a link is asked for")
        Equal(world.asked[1] and world.asked[1].key, "1", label .. "built: at its slot")
        Check(world.asked[1] and world.asked[1].feature == loot, label .. "built: by the loot window")
        Equal(world.AskedFor(withoutLink), "", label .. "built: a row the client has no link for is not asked for")
        Check((world.cleared[withoutLink] or 0) >= 1, label .. "built: and is cleared")
        Equal(world.AskedFor(money), "", label .. "built: nor is the money's row")
        client:Tick(3)
        Equal(world.AskedFor(withoutLink), "", label .. "built: nothing brings the missing link's row by itself")

        ----------------------------------------------------------------------------------
        -- 3. A slot the client changed
        ----------------------------------------------------------------------------------

        world.slots[2].known = true
        client:Fire("LOOT_SLOT_CHANGED", 2)
        client:Tick(2)
        Equal(world.AskedFor(withoutLink), "950002", label .. "changed: the row is asked for once its link has come")
        Equal(world.asked[#world.asked].key, "2", label .. "changed: at its slot")
        Equal(world.AskedFor(withLink), "950001", label .. "changed: and no other row is asked for again")

        world.slots[1] = { id = 950003, known = true }
        client:Fire("LOOT_SLOT_CHANGED", 1)
        client:Tick(2)
        Equal(world.AskedFor(withLink), "950001,950003", label .. "changed: a slot that holds another item now is asked for with it")

        world.slots[2].known = false
        local clearedBefore = world.cleared[withoutLink] or 0
        client:Fire("LOOT_SLOT_CHANGED", 2)
        client:Tick(2)
        Check((world.cleared[withoutLink] or 0) > clearedBefore, label .. "changed: a slot whose link is gone again is cleared")
        world.slots[2].known = true

        local askedBefore = #world.asked
        client:Fire("LOOT_SLOT_CHANGED", 7)
        client:Tick(2)
        Equal(#world.asked, askedBefore, label .. "changed: a slot with no row asks for nothing")

        ----------------------------------------------------------------------------------
        -- 4. A full refresh
        ----------------------------------------------------------------------------------

        client:Fire("LOOT_SLOT_CHANGED", 2)
        client:Tick(2)
        world.asked = {}
        loot:Refresh()
        client:Tick(2)
        Equal(world.AskedFor(withLink), "950003", label .. "refresh: every row is asked for again")
        Equal(world.AskedFor(withoutLink), "950002", label .. "refresh: with what its slot holds now")
        Equal(world.AskedFor(money), "", label .. "refresh: and the money's row is not")

        ----------------------------------------------------------------------------------
        -- 5. A fade-in that has ended
        ----------------------------------------------------------------------------------

        world.asked = {}
        world.rows[1].ShowAnim:End()
        client:Tick(2)
        Equal(world.AskedFor(withLink), "950003", label .. "fade: a row is asked for again when its fade-in has ended")
        Equal(world.AskedFor(withoutLink), "", label .. "fade: and only that row")
        world.asked = {}
        world.window.ShowAnim:End()
        client:Tick(2)
        Equal(world.AskedFor(withLink), "950003", label .. "fade: the window's fade-in asks for every row")
        Equal(world.AskedFor(withoutLink), "950002", label .. "fade: each with what its slot holds")
        Equal(world.AskedFor(money), "", label .. "fade: and the money's row is not asked for")
        Equal(#world.rows[1].ShowAnim.hooks, 1, label .. "fade: a row is listened to once")

        ----------------------------------------------------------------------------------
        -- 6. The export
        ----------------------------------------------------------------------------------

        local report = world.Report()
        Check(report:find("Item Rows Built: 1 with a link, 1 before the client had one", 1, true) ~= nil,
            label .. "export: the rows built, by whether the client had a link (" .. report .. ")")
        Check(report:find("3 with a link then, 1 still without, 1 with no row in the list", 1, true) ~= nil,
            label .. "export: and the slots the client changed")
        Check(report:find("- slot 2: " .. game.Link(950002) .. "; built before the client had a link, changed by the client 3 times; the icon's alpha as a fade-in ended: ",
            1, true) ~= nil, label .. "export: a row built without a link says so")
        Check(report:find(" where the draw set ", 1, true) ~= nil, label .. "export: with the icon's alpha as a fade-in left it")
        Check(report:find("; its button: asked for by Loot", 1, true) ~= nil, label .. "export: and what is on its button")
        Check(report:find("- slot 3: no link; holds no item now", 1, true) ~= nil, label .. "export: the money's row is named as no item's")

        local firstRow = world.rows[1]
        world.Close()
        Check(world.Report():find("Open Now: no", 1, true) ~= nil, label .. "export: a closed window lists no rows")

        -- A fade-in that ends on a row the list has taken back asks for nothing.
        world.asked = {}
        firstRow.ShowAnim:End()
        world.window.ShowAnim:End()
        client:Tick(2)
        Equal(#world.asked, 0, label .. "fade: a row given back to the list is not asked for")

        -- The window opened again builds its rows anew, on the rows it had: a row's history
        -- is its own, and the row is not listened to a second time.
        world.Open({ { id = 950004, known = true } })
        Check(world.rows[1] == firstRow, label .. "again: the list uses its row again")
        Check(world.Report():find("- slot 1: " .. game.Link(950004) .. "; built with a link, changed by the client 0 times; the icon's alpha as a fade-in ended: no fade-in ended with an icon on it",
            1, true) ~= nil, label .. "export: a row built anew starts over")
        Equal(#firstRow.ShowAnim.hooks, 1, label .. "again: and it is still listened to once")
        world.asked = {}
        firstRow.ShowAnim:End()
        client:Tick(2)
        Equal(world.AskedFor(firstRow.Item), "950004", label .. "again: its fade-in asks for what it shows now")

        Equal(#client.errors, 0, label .. "no error (" .. tostring(client.errors[1]) .. ")")
    end
end
