-- Skillet's profession window (external/Skillet/Core.Skillet.lua).
--
-- Skillet hands a row of its recipe list to every function registered with
-- AddPreButtonShowCallback just before it shows the row: (button, trade, skillIndex, row,
-- recipeID), with no recipe ID for a header's row, and takes what the function returns as a
-- button to show in the row's place. The rows are a fixed set, filled again at every scroll.
-- The stand-in below has that, its hide callback, UpdateDetailWindow, GetRecipe and
-- currentRecipeInfo in the shapes of its source (b-morgan/Skillet, UI/MainFrame.lua,
-- UI/DetailFrame.lua, SkilletData.lua; 2026-11-23, its TOC names both clients).
--
--   1. The feature registers beside Skillet and finds its three hook points.
--   2. A recipe's row is asked for with what the recipe makes: the client's link for it, or
--      the item of Skillet's own record where the client has no word of the recipe.
--   3. A header's row and a recipe that makes nothing are cleared, and so is a row Skillet
--      hides. Nothing is returned to Skillet.
--   4. A row filled with another recipe is asked for with that recipe's item.
--   5. The icon goes behind the recipe's name, and before the counts where the name is long.
--   6. The selected recipe's icon in the detail pane.
--   7. An error of the feature's goes to the error handler and not into Skillet's pass.
--   8. A Skillet with the show callback alone.
--
-- Logic only: where the icon lies on a row has not been seen in a client.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 29 }

    local BOOTS, BELT, HELM = 951001, 951002, 951003
    local ITEMS = {}
    for _, id in ipairs({ BOOTS, BELT, HELM }) do
        ITEMS[id] = { name = "Made Thing " .. id, quality = 1, level = 5, minLevel = 0, type = "Miscellaneous",
            subType = "Junk", stack = 20, price = 5, classID = 15, subClassID = 0 }
    end

    -- Recipes: the client knows 7001 and 7004, Skillet alone has 7002 (the item as the text
    -- its saved line is split into), and 7003 makes nothing.
    local RECIPE_BOOTS, RECIPE_BELT, RECIPE_NOTHING, RECIPE_HELM = 7001, 7002, 7003, 7004
    -- 7005: the client knows it and names nothing made; Skillet's record has the recipe's own
    -- ID in the item's place. 7006: the client has no word, and the record's ID is no item.
    local RECIPE_NO_LINK, RECIPE_NO_ITEM = 7005, 7006

    local function Start(flavor, skilletHas)
        local game = H.StockGame(TOON, ITEMS)
        local world = { game = game, asked = {}, cleared = {}, show = {}, hide = {}, clientRecipes = {} }

        world.clientRecipes[RECIPE_BOOTS] = { recipeID = RECIPE_BOOTS, hyperlink = game.Link(BOOTS) }
        world.clientRecipes[RECIPE_HELM] = { recipeID = RECIPE_HELM, hyperlink = game.Link(HELM) }
        world.clientRecipes[RECIPE_NO_LINK] = { recipeID = RECIPE_NO_LINK }
        game:Set("C_TradeSkillUI.GetRecipeInfo", function(recipeID)
            if world.clientFails then
                error("the client's recipe call raised an error")
            end
            return world.clientRecipes[recipeID]
        end)

        local skillet = {
            recipes = {
                [RECIPE_BOOTS] = { spellID = RECIPE_BOOTS, itemID = tostring(BOOTS) },
                [RECIPE_BELT] = { spellID = RECIPE_BELT, itemID = tostring(BELT) },
                [RECIPE_NOTHING] = { spellID = RECIPE_NOTHING, itemID = 0 },
                [RECIPE_HELM] = { spellID = RECIPE_HELM, itemID = tostring(HELM) },
                [RECIPE_NO_LINK] = { spellID = RECIPE_NO_LINK, itemID = tostring(BOOTS) },
                [RECIPE_NO_ITEM] = { spellID = RECIPE_NO_ITEM, itemID = "1265618" },
            },
        }
        function skillet:AddPreButtonShowCallback(method) world.show[#world.show + 1] = method end
        function skillet:GetRecipe(id) return self.recipes[id] or { spellID = 0, itemID = 0 } end
        if skilletHas ~= "the show callback alone" then
            function skillet:AddPreButtonHideCallback(method) world.hide[#world.hide + 1] = method end
            function skillet:UpdateDetailWindow() end
        end
        world.skillet = skillet
        game:Set("Skillet", skillet)
        game:Set("C_AddOns.GetAddOnInfo", function(name) return name, name, "", name == "Skillet" end)
        game:Set("C_AddOns.IsAddOnLoaded", function(name) return name == "Skillet" end)
        game:Set("C_AddOns.GetAddOnMetadata", function() return "5.50" end)

        local client = H.Client.New({ flavor = flavor, provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
        local core = client.env.CaerdonWardrobe
        if not core:GetFeature("Skillet") then
            client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "external/Skillet/Core.Skillet.lua", namespace)
        end

        world.detailIcon = client:NewFrame("Button", "SkilletSkillIcon")
        world.detailIcon:SetSize(37, 37)

        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(10)

        world.client, world.env, world.namespace, world.core = client, client.env, namespace, core
        world.feature = core:GetFeature("Skillet")

        local realUpdate, realClear = core.UpdateButton, core.ClearButton
        function core:UpdateButton(button, item, feature, locationInfo, options)
            world.asked[#world.asked + 1] = { button = button, id = item and item:GetItemID(), feature = feature,
                key = locationInfo and locationInfo.locationKey, options = options, locationInfo = locationInfo }
            return realUpdate(self, button, item, feature, locationInfo, options)
        end
        function core:ClearButton(button)
            world.cleared[button] = (world.cleared[button] or 0) + 1
            return realClear(self, button)
        end
        function core:SetItemButtonStatus() end
        function core:SetItemButtonMogStatusFilter() end
        function core:SetItemButtonBindType() end

        -- A row as Skillet's template makes it: 293 wide, with its level, name and counts.
        function world.Row(index, nameWidth, levelWidth, countsWidth)
            local rowName = "SkilletScrollButton" .. index
            local row = client:NewFrame("Button", rowName)
            row:SetSize(293, 16)
            local level = client:NewFrame("FontString", rowName .. "Level", row)
            level:SetWidth(levelWidth or 0)
            local name = client:NewFrame("FontString", rowName .. "Name", row)
            rawset(name, "GetStringWidth", function() return nameWidth or 80 end)
            local counts = client:NewFrame("FontString", rowName .. "Counts", row)
            counts:SetWidth(countsWidth or 10)
            return row
        end
        -- As Skillet's show_button and hide_button call the registered functions.
        function world.Show(row, recipeID)
            local returned = {}
            for _, method in ipairs(world.show) do
                returned[#returned + 1] = tostring((method(row, "Leatherworking", 3, 1, recipeID)))
            end
            client:Tick(3)
            return table.concat(returned, ",")
        end
        function world.Hide(row)
            for _, method in ipairs(world.hide) do
                method(row, "Leatherworking", 3, 1)
            end
            client:Tick(3)
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
        return world
    end

    for _, flavor in ipairs({ "forever", "retail" }) do
        local label = flavor .. ": "
        local world = Start(flavor)
        local feature = world.feature

        -- 1.
        Check(feature ~= nil, label .. "the file registers its feature beside Skillet")
        Equal(#world.show, 1, label .. "one function is registered for a row that is shown")
        Equal(#world.hide, 1, label .. "and one for a row that is hidden")
        local noted = feature and feature.hookPointsNoted or {}
        for _, point in ipairs({ "Skillet:AddPreButtonShowCallback", "Skillet:AddPreButtonHideCallback", "Skillet.UpdateDetailWindow" }) do
            Equal(noted[point] and noted[point].found, 1, label .. "the hook point " .. point .. " is noted as found")
        end
        Equal(#world.client.errors, 0, label .. "no error at the start")

        -- 2.
        local row = world.Row(1)
        Equal(world.Show(row, RECIPE_BOOTS), "nil", label .. "a recipe's row: nothing is returned to Skillet")
        Equal(world.Last(row).id, BOOTS, label .. "a recipe's row is asked for with the item the client says it makes")
        Equal(world.Last(row).key, "recipe" .. RECIPE_BOOTS, label .. "under the recipe's own key")
        Check(world.Last(row).feature == feature, label .. "as the Skillet feature's button")

        local second = world.Row(2)
        world.Show(second, RECIPE_BELT)
        Equal(world.Last(second).id, BELT, label .. "a recipe the client has no word of: the item of Skillet's own record")

        -- 3.
        local third = world.Row(3)
        Equal(world.Show(third, nil), "nil", label .. "a header's row: nothing is returned")
        Equal(world.TimesAsked(third), 0, label .. "a header's row is not asked for")
        Equal(world.cleared[third], 1, label .. "and is cleared")
        world.Show(third, RECIPE_NOTHING)
        Equal(world.TimesAsked(third), 0, label .. "a recipe that makes nothing is not asked for")
        Equal(world.cleared[third], 2, label .. "and its row is cleared")
        world.Show(third, RECIPE_NO_LINK)
        Equal(world.TimesAsked(third), 0, label .. "a recipe the client knows and names nothing made for is not asked for by Skillet's record")
        world.Show(third, RECIPE_NO_ITEM)
        Equal(world.TimesAsked(third), 0, label .. "an ID of Skillet's record that is no item is not asked for")
        Equal(world.cleared[third], 4, label .. "and both rows are cleared")
        local before = world.cleared[row] or 0
        world.Hide(row)
        Equal((world.cleared[row] or 0) - before, 1, label .. "a row Skillet hides is cleared")

        -- 4.
        world.Show(second, RECIPE_HELM)
        Equal(world.Last(second).id, HELM, label .. "a row filled with another recipe is asked for with that recipe's item")
        Equal(world.Last(second).key, "recipe" .. RECIPE_HELM, label .. "under that recipe's key")
        world.Show(second, nil)
        Check((world.cleared[second] or 0) >= 1, label .. "and cleared when a header takes the row")

        -- 5. The name starts 16 from the left edge, behind the level's text.
        local short = world.Row(4, 80, 0, 10)
        world.Show(short, RECIPE_BOOTS)
        local options = world.Last(short).options or {}
        Equal(options.overrideStatusPosition, "LEFT", label .. "placement: measured from the row's left edge")
        Equal(options.statusOffsetX, 16 + 80 + 6.5 + 2, label .. "placement: right behind a short name")
        Equal(options.fixedLayout, true, label .. "placement: fitted by hand, not by the player's layout")
        -- A row has the icon alone; the selected recipe's icon has the texts too.
        local rowRules = feature:GetDisplayRules(short, nil, feature, world.Last(short).locationInfo)
        Equal(rowRules.bindingStatus, false, label .. "rules: no binding text on a row, where Skillet has its counts")
        Equal(rowRules.levelGain, nil, label .. "rules: the level gain as the core has it, in a place of the row's own")
        local gain = options.levelGainAnchor or {}
        Equal(gain.point, "LEFT", label .. "placement: a number that goes with the icon is measured from the row's left edge too")
        Equal(gain.x, options.statusOffsetX + 6.5 + 2, label .. "placement: and stands right behind the icon")
        local selectedRules = feature:GetDisplayRules(world.detailIcon, nil, feature, { isSelectedRecipe = true })
        Equal(selectedRules.bindingStatus, true, label .. "rules: the selected recipe's icon has the binding text")
        Equal(selectedRules.levelGain, nil, label .. "rules: and the level gain as the core has it")
        local indented = world.Row(5, 80, 28, 10)
        world.Show(indented, RECIPE_BOOTS)
        Equal((world.Last(indented).options or {}).statusOffsetX, 16 + 28 + 80 + 6.5 + 2, label .. "placement: after the level's text too")
        local long = world.Row(6, 400, 0, 40)
        world.Show(long, RECIPE_BOOTS)
        -- The name's room is 293 - 16 - 40 = 237; the icon keeps its own 13 of it.
        Equal((world.Last(long).options or {}).statusOffsetX, 16 + (237 - 13) + 6.5 + 2, label .. "placement: before the counts where the name is long")
        Check(world.Last(short).options ~= world.Last(indented).options, label .. "placement: each row has its own options")

        -- 6.
        local icon = world.detailIcon
        world.skillet.currentRecipeInfo = world.clientRecipes[RECIPE_HELM]
        world.skillet:UpdateDetailWindow(3)
        world.client:Tick(3)
        Equal(world.Last(icon).id, HELM, label .. "detail: the selected recipe's icon is asked for with what it makes")
        Equal(world.Last(icon).key, "selectedrecipe" .. RECIPE_HELM, label .. "detail: under its own key")
        world.skillet.currentRecipeInfo = nil
        local clearedBefore = world.cleared[icon] or 0
        world.skillet:UpdateDetailWindow(-1)
        world.client:Tick(3)
        Equal((world.cleared[icon] or 0) - clearedBefore, 1, label .. "detail: no recipe selected clears it")
        world.skillet.currentRecipeInfo = world.clientRecipes[RECIPE_BOOTS]
        icon:Hide()
        clearedBefore = world.cleared[icon] or 0
        local askedBefore = world.TimesAsked(icon)
        world.skillet:UpdateDetailWindow(3)
        world.client:Tick(3)
        Equal((world.cleared[icon] or 0) - clearedBefore, 1, label .. "detail: an icon Skillet hid is cleared")
        Equal(world.TimesAsked(icon), askedBefore, label .. "detail: and not asked for")
        icon:Show()

        Equal(#world.client.errors, 0, label .. "no error reached the error handler so far")

        -- 7.
        world.clientFails = true
        local failing = world.Row(7)
        local ok, returned = pcall(world.Show, failing, RECIPE_BOOTS)
        Check(ok, label .. "an error of the feature's does not reach Skillet's pass (" .. tostring(returned) .. ")")
        Equal(returned, "nil", label .. "and nothing is returned to Skillet then either")
        Equal(#world.client.errors, 1, label .. "the error goes to the error handler")
        world.clientFails = false

        -- 8.
        local old = Start(flavor, "the show callback alone")
        Check(old.feature ~= nil, label .. "an older Skillet: the feature registers")
        Equal(#old.show, 1, label .. "an older Skillet: the rows' function is registered")
        local oldRow = old.Row(1)
        old.Show(oldRow, RECIPE_BOOTS)
        Equal(old.Last(oldRow).id, BOOTS, label .. "an older Skillet: a recipe's row is asked for")
        local oldNoted = old.feature and old.feature.hookPointsNoted or {}
        Equal(oldNoted["Skillet.UpdateDetailWindow"] and oldNoted["Skillet.UpdateDetailWindow"].missing, 1,
            label .. "an older Skillet: the detail pane's hook is noted as missing")
        Equal(#old.client.errors, 0, label .. "an older Skillet: no error")
    end
end
