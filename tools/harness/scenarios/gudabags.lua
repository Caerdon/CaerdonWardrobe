-- GudaBags' bags and bank (external/GudaBags/Core.GudaBags.lua).
--
-- GudaBags calls every function registered with GudaBags.API.OnItemButtonUpdate as
-- (button, bagID, slot) at the end of a button's setup with an item of the toon's own in a bag
-- or bank slot, and for no other setup: an emptied slot, its "Empty" button, another toon's
-- bags, its guild bank, a button it takes back. Every setup sets the button's picture once
-- through the game's SetItemButtonTexture, and a stack's count is also set alone, with no
-- setup. The stand-in below has that in the shapes of its source (GudaBags 3.0.9:
-- Core/PublicAPI.lua, UI/ItemButton.lua SetItem, SetEmpty and the pool's reset, UI/BagFrame.lua
-- for the count set alone; its TOC names both clients).
--
--   1. The feature registers beside GudaBags, finds the API's function and registers one of
--      its own. What GudaBags does before an announcement is not known until the first one.
--   2. A button set up with an item is asked for with that slot's item, as a bag slot.
--   3. A button set up again with another item is asked for with that item, and one set up
--      again as it was is asked for again; neither is cleared by the feature.
--   4. A stack's count set alone clears nothing.
--   5. A button that comes to show no item of the toon's own is cleared by the next frame and
--      not asked for: an emptied slot, the "Empty" button, another toon's bags, a guild bank's
--      item, a button taken back. One taken back and handed out again with an item is asked for.
--   6. A button the feature never asked for is left alone, GudaBags' and any other window's.
--   7. A refresh asks again for what is on the buttons, and for nothing on a cleared one.
--   8. One button's clearing that fails does not cost the others theirs.
--   9. An error of the feature's goes to the error handler and not to GudaBags' chat line.
--  10. A GudaBags that announces a button whose picture it did not set: noted as missing.
--  11. A GudaBags with no API: nothing is attached and nothing raised.
--  12. GudaBags' own marks for what this addon shows too (fields of its button, CreateButton):
--      its arrow and its quest marks are not seen while this addon's are switched on, its bind
--      label not under a text of this addon's, its set mark not where this addon has shown the
--      piece's gear set. A button that is no longer the feature's has them all again, the marks
--      with no counterpart are never touched, and a button without the parts raises nothing.
--
-- Logic only, against a stand-in: nothing here says where an icon lies on a slot of GudaBags'.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 29 }

    local SCRAP, CLOTH, HIDE = 952001, 952002, 952003
    local ITEMS = {}
    for _, id in ipairs({ SCRAP, CLOTH, HIDE }) do
        ITEMS[id] = { name = "Carried Thing " .. id, quality = 1, level = 5, minLevel = 0, type = "Miscellaneous",
            subType = "Junk", stack = 20, price = 5, classID = 15, subClassID = 0 }
    end

    local ANNOUNCED = "GudaBags.API.OnItemButtonUpdate"
    local PICTURE_FIRST = "SetItemButtonTexture before a button is announced"
    local CLEARED_BY_FEATURE = "GudaBags set it up with no item of this toon's own"

    local function Start(flavor, gudaBagsHas)
        local game = H.StockGame(TOON, ITEMS)
        -- slots: "bag/slot" -> item ID, what the client has in the toon's bags and bank.
        local world = { game = game, asked = {}, cleared = {}, clearedWhy = {}, drawn = {}, hooks = {}, printed = {},
            slots = {} }

        local function Place(location)
            if type(location) == "table" and location.IsBagAndSlot and location:IsBagAndSlot() then
                local bag, slot = location:GetBagAndSlot()
                return world.slots[bag .. "/" .. slot]
            end
        end
        game:Set("C_Item.DoesItemExist", function(location) return Place(location) ~= nil end)
        game:Set("C_Item.GetItemLink", function(location) return Place(location) and game.Link(Place(location)) end)
        game:Set("C_Item.GetItemID", function(location) return Place(location) end)
        game:Set("C_Item.IsBound", function() return false end)
        game:Set("C_Container.GetContainerNumSlots", function() return 16 end)
        game:Set("C_Container.GetContainerItemID", function(bag, slot) return world.slots[bag .. "/" .. slot] end)
        -- As the client's own: nothing for no button.
        game:Set("SetItemButtonTexture", function(button, texture)
            if button then
                button.shownTexture = texture
            end
        end)
        game:Set("SetItemButtonCount", function(button, count)
            if button then
                button.count = count
            end
        end)

        if gudaBagsHas ~= "no API" then
            game:Set("GudaBags", { API = {
                OnItemButtonUpdate = function(callback)
                    if type(callback) == "function" then
                        world.hooks[#world.hooks + 1] = callback
                    end
                end,
            } })
        else
            game:Set("GudaBags", {})
        end
        game:Set("C_AddOns.GetAddOnInfo", function(name) return name, name, "", name == "GudaBags" end)
        game:Set("C_AddOns.IsAddOnLoaded", function(name) return name == "GudaBags" end)
        game:Set("C_AddOns.GetAddOnMetadata", function() return "3.0.9" end)

        local client = H.Client.New({ flavor = flavor, provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
        local core = client.env.CaerdonWardrobe
        if not core:GetFeature("GudaBags") then
            client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "external/GudaBags/Core.GudaBags.lua", namespace)
        end

        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(10)

        world.client, world.env, world.namespace, world.core = client, client.env, namespace, core
        world.feature = core:GetFeature("GudaBags")

        -- The item of a slot, with a verdict of the scenario's own: what is asked for and what
        -- is cleared is the matter here, not what the item is.
        local realCreate = client.env.CaerdonItem.CreateFromBagAndSlot
        rawset(client.env.CaerdonItem, "CreateFromBagAndSlot", function(self, bag, slot)
            if world.itemsFail then
                error("the item of the slot could not be made")
            end
            local item = realCreate(self, bag, slot)
            if world.slots[bag .. "/" .. slot] then
                function item:GetCaerdonItemType() return "Miscellaneous" end
                function item:IsItemDataCached() return true end
                function item:GetCaerdonStatus() return true, "own", nil, {}, nil end
            end
            return item
        end)

        local realUpdate, realClear = core.UpdateButton, core.ClearButton
        function core:UpdateButton(button, item, feature, locationInfo, options)
            world.asked[#world.asked + 1] = { button = button, id = item and item:GetItemID(), feature = feature,
                locationInfo = locationInfo, options = options }
            return realUpdate(self, button, item, feature, locationInfo, options)
        end
        -- The feature's own clears are told from the core's (a button asked for with another
        -- item is cleared by the core on the way) by the reason given.
        function core:ClearButton(button, why)
            if why == CLEARED_BY_FEATURE then
                world.cleared[button] = (world.cleared[button] or 0) + 1
                if world.clearFails and world.clearFails[button] then
                    error("this button cannot be cleared")
                end
            end
            world.clearedWhy[button] = why
            return realClear(self, button, why)
        end
        -- What a draw leaves on a button is the scenario's to say (world.icon, world.text, by
        -- item ID), as the drawing code notes it for GetDrawnParts.
        world.icon, world.text, world.inSet = {}, {}, {}
        function core:SetItemButtonStatus(button, item, feature, locationInfo, options, status)
            if status ~= "waiting" then
                world.drawn[#world.drawn + 1] = { button = button, id = item and item:GetItemID() }
            end
            local overlay = self:GetCaerdonButton(button)
            if overlay then
                overlay.caerdonHasIcon = item ~= nil and world.icon[item:GetItemID()] == true
            end
        end
        function core:SetItemButtonMogStatusFilter() end
        function core:SetItemButtonBindType(button, item)
            local overlay = self:GetCaerdonButton(button)
            if overlay then
                overlay.caerdonHasText = item ~= nil and world.text[item:GetItemID()] == true
            end
        end
        rawset(client.env.CaerdonEquipment, "GetEquipmentSetsOf", function(_, item)
            return world.inSet[item:GetItemID()] and { "A gear set" } or nil
        end)

        world.window = client:NewFrame("Frame", "GudaBagsBagFrame")
        local made = 0
        -- One of GudaBags' own marks on a button: what the feature does to it is its alpha.
        local function Mark()
            return { alpha = 1, SetAlpha = function(self, alpha) self.alpha = alpha end }
        end
        -- A button of GudaBags' pool, at the icon size given (its default look is a bag slot's),
        -- with the marks its CreateButton makes on every one.
        function world.Button(size)
            made = made + 1
            local wrapper = client:NewFrame("Frame", "GudaBagsItemButton" .. made .. "Wrapper", world.window)
            local button = client:NewFrame("Button", "GudaBagsItemButton" .. made, wrapper)
            button:SetSize(size or 37, size or 37)
            button.wrapper = wrapper
            if gudaBagsHas ~= "no marks" then
                for _, field in ipairs({ "upgradeArrow", "questIcon", "questStarterIcon", "boeText", "equipSetIcon",
                    "equipSetIconShadow", "junkIcon", "itemLevelText" }) do
                    button[field] = Mark()
                end
            end
            return button
        end
        -- Which of GudaBags' marks the feature has left to be seen on a button, in one word each.
        function world.Seen(button)
            local seen = {}
            for _, field in ipairs({ "upgradeArrow", "questIcon", "questStarterIcon", "boeText", "equipSetIcon",
                "equipSetIconShadow", "junkIcon", "itemLevelText" }) do
                if button[field] and button[field].alpha == 1 then
                    seen[#seen + 1] = field
                end
            end
            return table.concat(seen, " ")
        end
        local function Announce(button, itemData)
            for index = 1, #world.hooks do
                local ok, problem = pcall(world.hooks[index], button, itemData.bagID, itemData.slot)
                if not ok then
                    world.printed[#world.printed + 1] = problem
                end
            end
        end
        -- ItemButton:SetItem(button, itemData, size, isReadOnly).
        function world.SetItem(button, itemData, isReadOnly, without)
            button.itemData, button.isReadOnly = itemData, isReadOnly or false
            button:SetShown(true)
            if itemData and itemData.isEmptySlots then
                client.env.SetItemButtonTexture(button, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
                client.env.SetItemButtonCount(button, itemData.emptyCount or 0)
                return
            end
            if without ~= "its picture set" then
                client.env.SetItemButtonTexture(button, itemData and 134400 or nil)
            end
            client.env.SetItemButtonCount(button, itemData and itemData.count or 0)
            if not isReadOnly and itemData and itemData.bagID and itemData.slot and not itemData.isGuildBank
                and not itemData.isEmptySlots then
                Announce(button, itemData)
            end
        end
        -- ItemButton:SetEmpty(button, bagID, slot, size, isReadOnly, isGuildBank).
        function world.SetEmpty(button, bag, slot)
            button.itemData, button.isReadOnly = { bagID = bag, slot = slot, isGuildBank = false }, false
            client.env.SetItemButtonTexture(button, nil)
            client.env.SetItemButtonCount(button, 0)
        end
        -- The pool's reset, for a button GudaBags takes back.
        function world.Release(button)
            button:SetShown(false)
            button.itemData = nil
            client.env.SetItemButtonTexture(button, nil)
            client.env.SetItemButtonCount(button, 0)
        end
        -- A slot's item as GudaBags' scanner records it, and in the client's bags.
        function world.Held(bag, slot, itemID, count)
            world.slots[bag .. "/" .. slot] = itemID
            return { bagID = bag, slot = slot, itemID = itemID, link = game.Link(itemID), count = count or 1 }
        end
        function world.Last(button)
            for index = #world.asked, 1, -1 do
                if world.asked[index].button == button then
                    return world.asked[index]
                end
            end
            return {}
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
        function world.TimesDrawn(button, id)
            local count = 0
            for _, draw in ipairs(world.drawn) do
                if draw.button == button and (id == nil or draw.id == id) then
                    count = count + 1
                end
            end
            return count
        end
        function world.Cleared(button)
            return world.cleared[button] or 0
        end
        return world
    end

    local function Noted(feature, point)
        local noted = feature and feature.hookPointsNoted or {}
        return noted[point] or { found = 0, missing = 0 }
    end

    for _, flavor in ipairs({ "forever", "retail" }) do
        local label = flavor .. ": "
        local world = Start(flavor)
        local feature, client, core = world.feature, world.client, world.core

        -- 1.
        Check(feature ~= nil, label .. "the file registers its feature beside GudaBags")
        Equal(#world.hooks, 1, label .. "one function is registered with the API")
        Equal(Noted(feature, ANNOUNCED).found, 1, label .. "the API's function is noted as found")
        Equal(Noted(feature, PICTURE_FIRST).found + Noted(feature, PICTURE_FIRST).missing, 0,
            label .. "what GudaBags does before an announcement is not known before the first one")
        Check(feature and feature.initFinished == true, label .. "its Init finished")
        Check(feature and feature.Refresh == world.env.CaerdonWardrobeFeatureMixin.Refresh,
            label .. "it has the default Refresh()")
        Equal(#client.errors, 0, label .. "no error at the start")

        -- 2.
        local first = world.Button()
        world.SetItem(first, world.Held(0, 1, SCRAP))
        Equal(world.Last(first).id, SCRAP, label .. "a button set up with an item is asked for with the slot's item")
        local place = world.Last(first).locationInfo or {}
        Check(place.bag == 0 and place.slot == 1, label .. "at its bag and slot")
        Check(world.Last(first).feature == feature, label .. "as the GudaBags feature's button")
        local options = world.Last(first).options or {}
        Equal(options.statusProminentSize, core:GetSlotStatusSize(37, 37, true), label .. "placement: the icon at a bag slot's proportion")
        Equal(options.slotScale, 1, label .. "placement: the texts at a bag slot's size on a slot of that size")
        Equal(options.keepInsideWhenClipped, true, label .. "placement: inside where its list cuts it off")
        Equal(Noted(feature, PICTURE_FIRST).found, 1, label .. "the picture was set before the announcement: noted as found")
        client:Tick(3)
        Equal(world.TimesDrawn(first, SCRAP), 1, label .. "and it is drawn")
        Equal(world.Cleared(first), 0, label .. "an announced button is not cleared")

        local small, large = world.Button(22), world.Button(64)
        world.SetItem(small, world.Held(0, 2, CLOTH))
        world.SetItem(large, world.Held(0, 3, HIDE))
        Equal((world.Last(small).options or {}).slotScale, 0.75, label .. "placement: smaller texts on GudaBags' smallest slot")
        Equal((world.Last(large).options or {}).statusProminentSize, core:GetSlotStatusSize(64, 64, true),
            label .. "placement: no upper limit on its largest")
        Check(world.Last(small).options ~= world.Last(large).options, label .. "placement: each button has its own options")
        Equal(world.TimesAsked(first), 1, label .. "another button's setup asks for no button but its own")
        client:Tick(3)

        -- 3.
        world.SetItem(first, world.Held(0, 4, CLOTH))
        Equal(world.Last(first).id, CLOTH, label .. "a button set up again with another item is asked for with that item")
        Check((world.Last(first).locationInfo or {}).slot == 4, label .. "at that item's slot")
        client:Tick(3)
        Equal(world.TimesDrawn(first, CLOTH), 1, label .. "and drawn with it")
        Equal(world.Cleared(first), 0, label .. "the feature clears nothing on the way")
        local askedBefore = world.TimesAsked(first)
        world.SetItem(first, world.Held(0, 4, CLOTH))
        client:Tick(3)
        Equal(world.TimesAsked(first) - askedBefore, 1, label .. "a button set up again as it was is asked for again")
        Equal(world.Cleared(first), 0, label .. "and not cleared")
        Equal(Noted(feature, PICTURE_FIRST).found, 1, label .. "the picture's note is made once, not at every announcement")

        -- 4.
        askedBefore = world.TimesAsked(first)
        world.env.SetItemButtonCount(first, 7)
        client:Tick(3)
        Equal(world.Cleared(first), 0, label .. "a stack's count set alone clears nothing")
        Equal(world.TimesAsked(first), askedBefore, label .. "and asks for nothing")

        -- 5.
        world.slots["0/4"] = nil
        world.SetEmpty(first, 0, 4)
        Equal(world.Cleared(first), 0, label .. "an emptied slot: not cleared inside GudaBags' own call")
        client:Tick(1)
        Equal(world.Cleared(first), 1, label .. "an emptied slot: cleared by the next frame")
        Equal(world.TimesAsked(first), askedBefore, label .. "an emptied slot: not asked for")
        client:Tick(3)
        Equal(world.Cleared(first), 1, label .. "an emptied slot: cleared once")
        world.SetEmpty(first, 0, 4)
        client:Tick(2)
        Equal(world.Cleared(first), 1, label .. "an empty slot set up again as empty is not cleared a second time")

        world.SetItem(first, world.Held(0, 4, SCRAP))
        client:Tick(2)
        Equal(world.Last(first).id, SCRAP, label .. "an item back in the slot: the button is asked for again")
        world.SetItem(first, { isEmptySlots = true, emptyCount = 12, bagID = 0, slot = 9 })
        client:Tick(2)
        Equal(world.Cleared(first), 2, label .. "the \"Empty\" button: a button that becomes it is cleared")

        world.SetItem(small, { bagID = 0, slot = 2, itemID = HIDE, link = world.game.Link(HIDE), count = 1 }, true)
        client:Tick(2)
        Equal(world.Cleared(small), 1, label .. "another toon's bags: a button that comes to show them is cleared")
        Check(world.Last(small).id == CLOTH, label .. "another toon's bags: and not asked for with that toon's item")

        world.SetItem(large, { bagID = 1, slot = 3, itemID = SCRAP, link = world.game.Link(SCRAP), count = 1, isGuildBank = true })
        client:Tick(2)
        Equal(world.Cleared(large), 1, label .. "a guild bank's item: the button is cleared")

        local pooled = world.Button()
        world.SetItem(pooled, world.Held(0, 5, HIDE))
        client:Tick(2)
        world.Release(pooled)
        client:Tick(2)
        Equal(world.Cleared(pooled), 1, label .. "a button GudaBags takes back is cleared")
        askedBefore = world.TimesAsked(pooled)
        world.SetItem(pooled, world.Held(-1, 7, CLOTH))
        client:Tick(2)
        Equal(world.TimesAsked(pooled) - askedBefore, 1, label .. "handed out again with a bank slot's item, it is asked for")
        Check((world.Last(pooled).locationInfo or {}).bag == -1 and world.Last(pooled).id == CLOTH, label .. "at the bank's slot")
        Equal(world.Cleared(pooled), 1, label .. "and not cleared again")

        -- A slot the client has no item in: the core clears what is asked for with nothing there.
        local keyring = world.Button()
        world.SetItem(keyring, { bagID = -2, slot = 1, itemID = SCRAP, link = world.game.Link(SCRAP), count = 1 })
        client:Tick(2)
        Equal(world.TimesDrawn(keyring, SCRAP), 0, label .. "a slot the client has no item in is not drawn")
        Equal(#client.errors, 0, label .. "and raises no error")

        -- 6.
        local never = world.Button()
        world.SetEmpty(never, 0, 12)
        world.SetItem(never, { isEmptySlots = true, emptyCount = 3, bagID = 0, slot = 12 })
        local elsewhere = client:NewFrame("Button", "MerchantItem1ItemButton")
        world.env.SetItemButtonTexture(elsewhere, 134400)
        world.env.SetItemButtonTexture(nil, 134400)
        client:Tick(3)
        Equal(world.Cleared(never), 0, label .. "a button of GudaBags' that was never asked for is left alone")
        Equal(world.Cleared(elsewhere), 0, label .. "and so is another window's")
        Check(world.clearedWhy[never] == nil and world.clearedWhy[elsewhere] == nil, label .. "by the core too")

        -- 7.
        local kept = world.Button()
        world.SetItem(kept, world.Held(0, 6, HIDE))
        client:Tick(3)
        world.drawn, world.asked = {}, {}
        core:RefreshItems("scenario")
        client:Tick(4)
        Equal(world.TimesDrawn(kept, HIDE), 1, label .. "refresh: a button on screen is drawn again with its item")
        Equal(world.TimesDrawn(pooled, CLOTH), 1, label .. "refresh: and the bank's")
        Equal(world.TimesDrawn(first), 0, label .. "refresh: a cleared button is not asked for")
        Equal(world.TimesDrawn(small) + world.TimesDrawn(large), 0, label .. "refresh: nor one that shows another toon's item or a guild bank's")
        client:SetFrameShown(world.window, false)
        world.drawn = {}
        core:RefreshItems("scenario")
        client:Tick(4)
        Equal(world.TimesDrawn(kept), 0, label .. "refresh: a closed bag's button keeps its icon")
        client:SetFrameShown(world.window, true)
        client:Tick(2)
        Equal(world.TimesDrawn(kept, HIDE), 1, label .. "refresh: and is drawn when the bag opens as it was")
        Equal(#client.errors, 0, label .. "no error reached the error handler so far")

        -- 8.
        local one, two, three = world.Button(), world.Button(), world.Button()
        for index, button in ipairs({ one, two, three }) do
            world.SetItem(button, world.Held(1, index, SCRAP))
        end
        client:Tick(3)
        world.clearFails = { [one] = true, [two] = true, [three] = true }
        for index, button in ipairs({ one, two, three }) do
            world.SetEmpty(button, 1, index)
        end
        client:Tick(2)
        Equal(world.Cleared(one) + world.Cleared(two) + world.Cleared(three), 3,
            label .. "failure: every button's clearing is tried when each of them fails")
        Equal(#client.errors, 3, label .. "failure: and each error reaches the error handler")
        world.clearFails = nil
        client.errors = {}

        -- 9.
        world.itemsFail = true
        local failing = world.Button()
        world.SetItem(failing, world.Held(1, 8, HIDE))
        Equal(#world.printed, 0, label .. "an error of the feature's is not left to GudaBags to print")
        Equal(#client.errors, 1, label .. "it goes to the error handler")
        world.itemsFail = false
        client.errors = {}
        world.SetItem(failing, world.Held(1, 8, HIDE))
        client:Tick(2)
        Equal(world.Last(failing).id, HIDE, label .. "and the button is asked for at its next setup")

        -- 10.
        local changed = Start(flavor)
        local quiet = changed.Button()
        changed.SetItem(quiet, changed.Held(0, 1, SCRAP), false, "its picture set")
        Equal(changed.Last(quiet).id, SCRAP, label .. "a GudaBags that sets no picture first: the button is still asked for")
        Equal(Noted(changed.feature, PICTURE_FIRST).missing, 1, label .. "and the point is noted as missing")
        Equal(Noted(changed.feature, PICTURE_FIRST).found, 0, label .. "not as found")
        changed.SetItem(quiet, changed.Held(0, 1, SCRAP), false, "its picture set")
        Equal(Noted(changed.feature, PICTURE_FIRST).missing, 1, label .. "once, not at every announcement")
        Equal(#changed.client.errors, 0, label .. "with no error")

        -- 12. GudaBags' own marks. Its junk coin and its item level have no counterpart here.
        do
            local marks = Start(flavor)
            local mClient, mCore, mFeature = marks.client, marks.core, marks.feature
            local config = marks.env.CaerdonWardrobeConfig
            local ALL = "upgradeArrow questIcon questStarterIcon boeText equipSetIcon equipSetIconShadow junkIcon itemLevelText"
            local OTHERS = "junkIcon itemLevelText"
            local plain = marks.Button()
            Equal(marks.Seen(plain), ALL, label .. "marks: a button nobody asked for has all of GudaBags' marks")

            -- Defaults: the arrow and the quest icon are on for the bags.
            marks.SetItem(plain, marks.Held(0, 1, SCRAP))
            Equal(marks.Seen(plain), "boeText equipSetIcon equipSetIconShadow " .. OTHERS,
                label .. "marks: its arrow and its quest marks are gone with the announcement, before the draw")
            mClient:Tick(3)
            Equal(marks.Seen(plain), "boeText equipSetIcon equipSetIconShadow " .. OTHERS,
                label .. "marks: a slot with no text of this addon's keeps GudaBags' bind label and set mark")
            for _, field in ipairs({ "upgradeArrow", "questIcon", "questStarterIcon", "boeText", "equipSetIcon" }) do
                Equal(Noted(mFeature, "button." .. field).found, 1, label .. "marks: " .. field .. " is noted as found")
            end
            marks.SetItem(marks.Button(), marks.Held(0, 9, SCRAP))
            Equal(Noted(mFeature, "button.boeText").found, 1, label .. "marks: once, not for every button")

            -- This addon's text on the slot: GudaBags' bind label gives way, its set mark does
            -- not (the piece is in no gear set, so the text is a binding's).
            marks.text[CLOTH] = true
            local bound = marks.Button()
            marks.SetItem(bound, marks.Held(0, 2, CLOTH))
            mClient:Tick(3)
            Equal(marks.Seen(bound), "equipSetIcon equipSetIconShadow " .. OTHERS,
                label .. "marks: under a text of this addon's GudaBags' bind label is not seen")

            -- A gear set's piece with the set's name on it, and one with the set's icon.
            marks.text[HIDE], marks.inSet[HIDE] = true, true
            local setPiece = marks.Button()
            marks.SetItem(setPiece, marks.Held(0, 3, HIDE))
            mClient:Tick(3)
            Equal(marks.Seen(setPiece), OTHERS, label .. "marks: a gear set's name on the slot: GudaBags' set mark is not seen, nor its shadow")
            config.Binding.ShowGearSets, config.Binding.ShowGearSetsAsIcon = false, true
            marks.text[HIDE], marks.icon[HIDE] = false, true
            mCore:RefreshItems("scenario")
            mClient:Tick(4)
            Equal(marks.Seen(setPiece), "boeText " .. OTHERS, label .. "marks: a gear set's icon on the slot: the same, and the bind label is back")
            config.Binding.ShowGearSetsAsIcon = false
            mCore:RefreshItems("scenario")
            mClient:Tick(4)
            Equal(marks.Seen(setPiece), "boeText equipSetIcon equipSetIconShadow " .. OTHERS,
                label .. "marks: gear sets not shown by this addon: GudaBags' set mark is seen")
            config.Binding.ShowGearSets = true

            -- The two that go by a setting.
            config.Icon.ShowUpgrades.BankAndBags = false
            mCore:RefreshItems("scenario")
            mClient:Tick(4)
            Equal(marks.Seen(plain), "upgradeArrow boeText equipSetIcon equipSetIconShadow " .. OTHERS,
                label .. "marks: this addon's arrow off for the bags: GudaBags' arrow is seen")
            config.Icon.ShowUpgrades.BankAndBags = true
            config.Icon.ShowUpgradeIcon = false
            mCore:RefreshItems("scenario")
            mClient:Tick(4)
            Check(plain.upgradeArrow.alpha == 1, label .. "marks: and with this addon's arrow off everywhere")
            config.Icon.ShowUpgradeIcon = true
            config.Icon.ShowQuestItems = false
            mCore:RefreshItems("scenario")
            mClient:Tick(4)
            Equal(marks.Seen(plain), "questIcon questStarterIcon boeText equipSetIcon equipSetIconShadow " .. OTHERS,
                label .. "marks: this addon's quest icon off: GudaBags' quest marks are seen, its arrow is not")
            config.Icon.ShowQuestItems = true
            mCore:RefreshItems("scenario")
            mClient:Tick(4)

            -- A button that is no longer the feature's has every mark as GudaBags shows it.
            marks.slots["0/2"] = nil
            marks.SetEmpty(bound, 0, 2)
            mClient:Tick(2)
            Equal(marks.Seen(bound), ALL, label .. "marks: an emptied slot's button has all of GudaBags' marks again")
            marks.Release(setPiece)
            mClient:Tick(2)
            Equal(marks.Seen(setPiece), ALL, label .. "marks: and so has one GudaBags takes back")

            local note = mFeature:GetLayoutNote()
            Check(type(note) == "string" and note:find("^GudaBags: ") ~= nil, label .. "marks: the layout editor's callout says so, under GudaBags' name")
            Equal(#mClient.errors, 0, label .. "marks: no error")

            -- A GudaBags whose buttons have none of these parts.
            local bare = Start(flavor, "no marks")
            local bareButton = bare.Button()
            bare.SetItem(bareButton, bare.Held(0, 1, SCRAP))
            bare.client:Tick(3)
            Equal(bare.Last(bareButton).id, SCRAP, label .. "marks: a GudaBags without the parts: the button is asked for all the same")
            Equal(Noted(bare.feature, "button.upgradeArrow").missing, 1, label .. "marks: a GudaBags without the parts: noted as missing")
            bare.SetEmpty(bareButton, 0, 1)
            bare.client:Tick(2)
            Equal(#bare.client.errors, 0, label .. "marks: a GudaBags without the parts: no error")
        end

        -- 11.
        local old = Start(flavor, "no API")
        Check(old.feature ~= nil, label .. "a GudaBags with no API: the feature registers")
        Check(old.feature and old.feature.initFinished == true, label .. "a GudaBags with no API: its Init finishes")
        Equal(Noted(old.feature, ANNOUNCED).missing, 1, label .. "a GudaBags with no API: the function is noted as missing")
        local untouched = old.Button()
        old.SetItem(untouched, old.Held(0, 1, SCRAP))
        old.SetEmpty(untouched, 0, 1)
        old.client:Tick(3)
        Equal(old.TimesAsked(untouched) + old.Cleared(untouched), 0, label .. "a GudaBags with no API: nothing is asked for or cleared")
        Equal(#old.client.errors, 0, label .. "a GudaBags with no API: no error")
    end
end
