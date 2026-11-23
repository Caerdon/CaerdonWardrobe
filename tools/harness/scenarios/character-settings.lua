-- The toon's own settings (CaerdonWardrobeCharacterConfig, saved per character), from the
-- settings page's side.
--
-- Most options are the player's and one table for every toon (CaerdonWardrobeConfig). An
-- option marked perCharacter describes the toon, and the page keeps it with the toon. Today
-- that is one list on the Icons page, under "Also for gear I am not wearing": the toon's gear
-- sets and the specs no gear set speaks for, each with a switch, and each gear set with the
-- Pawn scale it is scored on. Here:
--   1. The list has a row per spec of the toon's class that has no gear set, under a line that
--      names the toon and says the choice is kept per character. A spec with a gear set has
--      that set's row instead, and the set's switch is the spec's.
--   2. A switch nobody clicked shows what the equipment code takes the spec as: on with a gear
--      set assigned to it or with its scale shown in Pawn by the player's choice, off
--      otherwise. No table is made for the toon by that, and the first click writes that
--      switch alone. The switch's tooltip says which it is: on or off by the player's choice,
--      or because of a gear set or of what Pawn shows.
--   3. A click writes to the toon's table and not to the player's settings, and refreshes the
--      icons once; an ordinary option still writes to the player's settings alone.
--   4. The page shows what the toon's table says each time it is displayed, so another toon's
--      table (the client loads one per character) shows that toon's choice.
--   5. Saved data that is no table reads as "never chosen" and is replaced by the first click.
--      The switches hang on the option above the list; the scales do not.
--   6. A gear set's row has the scale the set is tied to and a list of the scales it can be
--      tied to. The rows are the toon's sets as they are each time the page shows, and the
--      rest of the page moves with their number. A choice is written to the toon's table and
--      refreshes the icons once. A set tied to a scale that no spec owns has a switch of its
--      own; one with neither has none to click. A set that is scored and holds a piece with
--      a PVP floor has a second switch, "PvP", which hangs on nothing. A set that is deleted
--      takes its tie and its switches with it.
--   7. A page with such a list has the height of what is above it, the list as it is now and
--      what is below.
--
-- What the equipment code makes of the choice is scenarios/pawn-scales.lua. That the client
-- keeps one table per character is the client's part and is not proven by this.
--
-- The frames are the harness's, with what a checkbox and a dropdown need added here: a state
-- for "checked" and "enabled" and the text region the template brings. Real text widths,
-- wrapping and the page's look are not in it.
--
-- Real code: the whole addon's item side, config/Config.lua, ConfigPanel.lua and Icons.lua,
-- Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Druid", classFile = "DRUID", race = "Tauren",
        faction = "Horde", level = 90 }
    local SPECS = { "Balance", "Feral", "Guardian", "Restoration" }
    local BALANCE, FERAL, GUARDIAN, RESTORATION = "\"MrRobot\":DRUID1", "\"MrRobot\":DRUID2", "\"MrRobot\":DRUID3",
        "\"MrRobot\":DRUID4"

    local function Start()
        local game = H.StockGame(TOON, {})
        local world = { game = game, refreshes = {}, registrants = {}, visible = {} }
        -- What a spec nobody chose is taken from: the gear set assigned to a spec, and the
        -- scales Pawn shows (one here, Guardian's).
        game:Set("C_EquipmentSet.GetEquipmentSetForSpec", function(specIndex)
            return world.setForSpec and world.setForSpec[specIndex] or nil
        end)
        -- Pawn's own scale for each spec of the class: a spec is a loadout through its scale.
        world.scales = {}
        for index, scaleName in ipairs({ BALANCE, FERAL, GUARDIAN, RESTORATION }) do
            world.scales[scaleName] = { ClassID = 3, SpecID = index, Provider = "MrRobot",
                LocalizedName = "Druid: " .. SPECS[index] }
        end
        game:Set("PawnCommon.Scales", world.scales)
        -- Pawn's part that scores an item on a scale: a list of scales to choose from is only
        -- offered where it is there.
        game:Set("PawnGetItemData", function() return nil end)
        game:Set("PawnGetSingleValueFromItem", function() return nil end)
        -- The toon's gear sets, and the client's function that deletes one.
        game:Set("C_EquipmentSet.GetEquipmentSetIDs", function() return world.setIDs or {} end)
        game:Set("C_EquipmentSet.GetEquipmentSetInfo", function(setID)
            local name = world.setNames and world.setNames[setID]
            if name then
                return name, nil, setID, false, 10, 0
            end
        end)
        game:Set("C_EquipmentSet.DeleteEquipmentSet", function(setID) world.deleted = setID end)
        -- The character window's two ways of saying which spec a set is for. No event follows.
        local function Unassign(setID)
            for specIndex, assigned in pairs(world.setForSpec or {}) do
                if assigned == setID then
                    world.setForSpec[specIndex] = nil
                end
            end
        end
        game:Set("C_EquipmentSet.AssignSpecToEquipmentSet", function(setID, specIndex)
            Unassign(setID)
            world.setForSpec = world.setForSpec or {}
            world.setForSpec[specIndex] = setID
        end)
        game:Set("C_EquipmentSet.UnassignEquipmentSetSpec", Unassign)
        -- A dropdown's menu, as far as the entries it is given.
        world.menu = {}
        game:Set("UIDropDownMenu_CreateInfo", function() return {} end)
        game:Set("UIDropDownMenu_AddButton", function(info) world.menu[#world.menu + 1] = info end)
        game:Set("PawnIsScaleVisible", function(name) return world.visible[name] == true end)
        game:Set("GetSpecialization", function() return 3 end)
        game:Set("GetSpecializationInfoForClassID", function(_, index)
            return 100 + index, SPECS[index], "", 9000 + index
        end)
        game:Set("C_SpecializationInfo.GetNumSpecializationsForClassID", function() return #SPECS end)
        game:Set("Settings.RegisterCanvasLayoutSubcategory", function() return {}, {} end)
        game:Set("SettingsRegistrar.AddRegistrant", function(_, registrant)
            world.registrants[#world.registrants + 1] = registrant
        end)
        game:Set("PlaySound", function() end)
        -- The game's tooltip, as far as a page's option fills it: the lines it was given.
        world.tooltip = { lines = {} }
        game:Set("GameTooltip", {
            SetOwner = function(_, owner) world.tooltip.owner, world.tooltip.lines = owner, {} end,
            GetOwner = function() return world.tooltip.owner end,
            SetText = function(_, text) world.tooltip.title = text end,
            AddLine = function(_, text) table.insert(world.tooltip.lines, text) end,
            Show = function() end,
            Hide = function() world.tooltip.owner = nil end,
        })
        game:Set("SOUNDKIT", { IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857 })

        local client = H.Client.New({ flavor = "retail", provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)

        -- A checkbox knows whether it is checked and usable, and both templates bring a text.
        local newFrame = client.env.CreateFrame
        rawset(client.env, "CreateFrame", function(frameType, name, parent, template)
            local frame = newFrame(frameType, name, parent, template)
            if frameType == "CheckButton" then
                local checked, enabled = false, true
                rawset(frame, "SetChecked", function(_, value) checked = value and true or false end)
                rawset(frame, "GetChecked", function() return checked end)
                rawset(frame, "SetEnabled", function(_, value) enabled = value and true or false end)
                rawset(frame, "IsEnabled", function() return enabled end)
            end
            if frameType == "CheckButton" or template == "UIDropDownMenuTemplate" then
                rawset(frame, "Text", newFrame("FontString", nil, frame))
            end
            return frame
        end)

        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/ConfigPanel.lua", namespace)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Icons.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)
        world.client, world.env, world.namespace = client, client.env, namespace

        local core = client.env.CaerdonWardrobe
        local refreshItems = core.RefreshItems
        function core:RefreshItems(reason, detail, changed)
            world.refreshes[#world.refreshes + 1] = reason
            world.lastDetail = detail
            return refreshItems(self, reason, detail, changed)
        end

        -- The settings window builds the pages once it is there.
        namespace.SettingsCategory = namespace.SettingsCategory or {}
        local framesBefore = #client.frames
        for _, registrant in ipairs(world.registrants) do
            registrant()
        end
        -- The page's frame is the one the window refreshes each time it shows the page.
        for index = framesBefore + 1, #client.frames do
            if rawget(client.frames[index], "OnRefresh") then
                world.page = client.frames[index]
            end
        end
        return world
    end

    local function Texts(world)
        local texts = {}
        for _, frame in ipairs(world.client.frames) do
            local text = frame:GetText()
            if type(text) == "string" then
                texts[text] = true
            end
        end
        return texts
    end

    -- What the player's click on a checkbox does.
    local function Click(world, checkbox, checked)
        world.refreshes = {}
        checkbox:SetChecked(checked)
        checkbox:GetScript("OnClick")(checkbox)
    end

    -- The text of the tooltip the control shows under the mouse.
    local function Hover(world, control)
        control:GetScript("OnEnter")(control)
        local text = table.concat(world.tooltip.lines, "\n")
        control:GetScript("OnLeave")(control)
        return text
    end
    local function Says(text, part)
        return type(text) == "string" and text:find(part, 1, true) ~= nil
    end
    local FOLLOWS = "Until you click it, it follows the gear sets you assign and the scales you have Pawn show."

    local world = Start()
    local env = world.env
    Equal(#world.client.errors, 0, "start: no error reached the error handler")
    for _, message in ipairs(world.client.errors) do
        Check(false, "start: " .. message)
    end
    Equal(#world.registrants, 1, "start: the Icons page asked to be built")
    Check(world.page ~= nil, "start: and its frame is there to be refreshed")

    -- The list, and its rows by the name they show.
    local list = env.CaerdonWardrobegearSetScale
    Check(list ~= nil, "page: the Icons page has the list")
    local function RowsShown()
        local count = 0
        for _, row in ipairs(list.rows) do
            count = count + (row:IsShown() and 1 or 0)
        end
        return count
    end
    local function Row(name)
        for _, row in ipairs(list.rows) do
            if row:IsShown() and row.name:GetText() == name then
                return row
            end
        end
        return nil
    end
    local function Tick(name)
        local row = Row(name)
        return row and row.check or nil
    end
    local function Ticked(name)
        local tick = Tick(name)
        if tick == nil then
            return "no row"
        end
        return tick:GetChecked()
    end

    -- 1. A row per spec with no gear set, and the line above them.
    Equal(RowsShown(), #SPECS, "page: a toon with no gear sets has a row per spec of its class")
    for index = 1, #SPECS do
        local row = list.rows[index]
        Equal(row.name:GetText(), SPECS[index], "page: row " .. index .. " is named for its spec")
        Equal(env.CaerdonEquipment:GetSpecsWithoutGearSet()[index].icon, 9000 + index, "page: with the spec's icon")
        Equal(row.note:GetText(), "No gear set: what you wear, on Druid: " .. SPECS[index],
            "page: and says what such a spec is measured by")
        Check(row.note:IsShown() and not row.dropdown:IsShown(), "page: in the place of a scale to choose, row " .. index)
        Check(row.check ~= nil and row.check == env["CaerdonWardrobegearSetScaleCheck" .. index],
            "page: a switch at the head of row " .. index)
    end
    Check(Says(list.header:GetText(), "Zzyxa's specs (kept per character). Ticked: its upgrades show while you wear something else."),
        "page: the line names the toon and says the choice is its own: " .. tostring(list.header:GetText()))
    Check(Says(list.header:GetText(), "A gear set you save in the character window gets a row here"),
        "page: and that a gear set would be listed too")
    Equal(env.CaerdonWardrobeotherSpec1, nil, "page: there is no second list of specs")
    local shared = env.CaerdonWardrobeshowOtherSpecUpgrades
    Check(shared ~= nil and shared.caerdonInfo.perCharacter == nil, "page: the option above the list is the player's, for every toon")
    Equal(shared and shared.Text:GetText(), "Also for gear I am not wearing", "page: and is named for what the rows are")
    Equal(list.caerdonDependsOn, shared, "page: the rows' switches hang on it")
    -- That option is off as the settings start on a client with specs: the switches are there
    -- to be read and not to be clicked until it is on.
    Equal(shared:GetChecked(), false, "page: it is off as the settings start")
    Equal(list.rows[1].check:IsEnabled(), false, "page: so no row's switch can be clicked yet")
    Click(world, shared, true)
    Equal(list.rows[1].check:IsEnabled(), true, "page: and with it on they can")

    -- 2. Nobody chose: what the game and Pawn say, and nothing made.
    for index = 1, #SPECS do
        Equal(Ticked(SPECS[index]), false,
            "never chosen: with no gear set and no scale shown, spec " .. index .. " shows as off")
    end
    local hint = Hover(world, Tick("Balance"))
    Check(Says(hint, "Show upgrades for Balance while you play another specialization."), "tooltip: what the switch does: " .. hint)
    Check(Says(hint, "Off because no gear set is assigned to Balance and Pawn is not set to show its scale. " .. FOLLOWS),
        "tooltip: off, and why, for a spec with neither sign")
    Check(Says(hint, "Kept for this character only."), "tooltip: and that the choice is the character's")
    Equal(world.tooltip.title, "Balance", "tooltip: under the spec's name")
    -- A gear set the client ties to a spec has the row in the spec's place, and its switch.
    world.setForSpec = { [2] = 21 }
    world.setIDs, world.setNames = { 21 }, { [21] = "Cat" }
    world.page.OnRefresh()
    Equal(RowsShown(), #SPECS, "never chosen: a spec's gear set has a row and the spec none beside it")
    Equal(list.rows[1].name:GetText(), "Cat", "never chosen: the gear sets come first")
    Equal(Row("Feral"), nil, "never chosen: the spec is not listed a second time")
    Check(Row("Cat").dropdown:IsShown() and not Row("Cat").note:IsShown(), "never chosen: a gear set's row has a scale to choose")
    Equal(Row("Cat").text:GetText(), "By its specialization (Feral)", "never chosen: which is its spec's until it is tied")
    Equal(Ticked("Cat"), true, "never chosen: a gear set assigned to a spec shows it as on")
    Equal(Ticked("Balance"), false, "never chosen: and no other spec")
    Check(Says(list.header:GetText(), "Zzyxa's gear sets and specs (kept per character).") and
        Says(list.header:GetText(), "The scale is what a gear set is scored on."),
        "never chosen: the line is for both kinds of row: " .. tostring(list.header:GetText()))
    Check(Says(Hover(world, Tick("Cat")), "On because a gear set is assigned to Feral. " .. FOLLOWS),
        "tooltip: on because of the gear set: " .. Hover(world, Tick("Cat")))
    Equal(world.tooltip.title, "Cat", "tooltip: under the gear set's name")
    world.visible = { [GUARDIAN] = true }
    world.page.OnRefresh()
    Equal(Ticked("Guardian"), true, "never chosen: a scale the player has Pawn show does too")
    Check(Says(Hover(world, Tick("Guardian")), "On because Pawn is set to show the Guardian scale. " .. FOLLOWS),
        "tooltip: on because of Pawn's shown scale: " .. Hover(world, Tick("Guardian")))
    rawset(env, "PawnOptions", { AutoSelectScales = true })
    world.page.OnRefresh()
    Equal(Ticked("Guardian"), false, "never chosen: not a scale Pawn shows by itself")
    hint = Hover(world, Tick("Guardian"))
    Check(Says(hint, "Off because no gear set is assigned to Guardian. " .. FOLLOWS) and not Says(hint, "Pawn is not set"),
        "tooltip: with Pawn picking its scales, off for want of a gear set alone: " .. hint)
    Equal(env.CaerdonWardrobeCharacterConfig, nil, "tooltip: a look at it writes nothing for the toon")
    Equal(Ticked("Cat"), true, "never chosen: the spec with the gear set stays on")
    Equal(env.CaerdonWardrobeCharacterConfig, nil, "never chosen: and the toon has no table")
    -- The first click writes its own switch and leaves the others to follow the game.
    Click(world, Tick("Balance"), true)
    local own = env.CaerdonWardrobeCharacterConfig
    Equal(type(own) == "table" and own.Icon.OtherSpecs.DRUID1, true, "first click: the clicked spec is written")
    Equal(type(own) == "table" and own.Icon.OtherSpecs.DRUID2, nil, "first click: a spec that only showed as on is not")
    hint = Hover(world, Tick("Balance"))
    Check(Says(hint, "On by your choice.") and not Says(hint, "Until you click it"),
        "tooltip: a clicked switch is the player's choice and follows nothing: " .. hint)
    Check(Says(Hover(world, Tick("Cat")), "On because a gear set is assigned to Feral."),
        "tooltip: the unclicked one beside it still gives the game's reason")
    Click(world, Tick("Balance"), false)
    Check(Says(Hover(world, Tick("Balance")), "Off by your choice."), "tooltip: switched off, it says that")
    Click(world, Tick("Balance"), true)
    -- The set is no spec's any more: the spec has its own row again, and follows the game.
    world.setForSpec = nil
    world.page.OnRefresh()
    Equal(Ticked("Balance"), true, "first click: the choice stands when the game says otherwise")
    Equal(Ticked("Feral"), false, "first click: and the unclicked spec follows the game")
    Equal(RowsShown(), #SPECS + 1, "first click: with the gear set, now no spec's, in a row of its own")
    -- A gear set with no spec and no scale is not scored on its own: no switch to click.
    Equal(Row("Cat").text:GetText(), "Not tied", "no scale: a gear set no spec owns starts untied")
    Check(Tick("Cat"):GetChecked() == false and Tick("Cat"):IsEnabled() == false, "no scale: its switch is empty and cannot be clicked")
    Check(Says(Hover(world, Tick("Cat")), "Choose a Pawn scale for it first."), "no scale: and says what to do: " .. Hover(world, Tick("Cat")))
    Equal(Tick("Balance"):IsEnabled(), true, "no scale: a row beside it is as usable as before")
    rawset(env, "CaerdonWardrobeCharacterConfig", nil)
    rawset(env, "PawnOptions", nil)
    world.visible = {}

    -- From here every spec has a gear set assigned, so a switch nobody clicked shows as on.
    world.setForSpec = { 11, 12, 13, 14 }
    world.setIDs, world.setNames = { 11, 12, 13, 14 }, { [11] = "One", [12] = "Two", [13] = "Three", [14] = "Four" }
    world.page.OnRefresh()
    Equal(RowsShown(), 4, "sets for all: a row per gear set, and no spec beside them")

    -- 3. A click.
    Click(world, Tick("Two"), false)
    own = env.CaerdonWardrobeCharacterConfig
    Equal(type(own), "table", "click: the toon's table is made")
    Equal(own and own.Icon and own.Icon.OtherSpecs and own.Icon.OtherSpecs.DRUID2, false, "click: with the set's spec off in it")
    Equal(own and own.Icon and own.Icon.OtherSets, nil, "click: a spec's gear set is switched by its spec, not by the set")
    Equal(env.CaerdonWardrobeConfig.Icon.OtherSpecs, nil, "click: and nothing about specs in the player's settings")
    Equal(#world.refreshes, 1, "click: one refresh")
    Equal(world.refreshes[1], "settings", "click: named for the settings")
    Click(world, Tick("Two"), true)
    Equal(env.CaerdonWardrobeCharacterConfig.Icon.OtherSpecs.DRUID2, true, "click: switched on again, it is on in the toon's table")
    Click(world, Tick("Four"), false)

    -- An ordinary option is the player's.
    local before = H.DeepCopy(env.CaerdonWardrobeCharacterConfig)
    local gearSets = env.CaerdonWardrobeshowUpgradeOnGearSets
    Equal(gearSets:GetChecked(), true, "shared: an ordinary option shows the player's setting")
    Equal(gearSets.Text:GetText(), "On pieces saved in a gear set", "shared: named for the piece it is about")
    Check(Says(Hover(world, gearSets), "Show the arrow on items that belong to a saved gear set."),
        "shared: and its tooltip is its text, as before")
    Click(world, gearSets, false)
    Equal(env.CaerdonWardrobeConfig.Icon.ShowUpgradeOnGearSets, false, "shared: its click writes to the player's settings")
    Equal(env.CaerdonWardrobeCharacterConfig.Icon.ShowUpgradeOnGearSets, nil, "shared: and not to the toon's table")
    Equal(env.CaerdonWardrobeCharacterConfig.Icon.OtherSpecs.DRUID2, before.Icon.OtherSpecs.DRUID2, "shared: which is as it was")
    Equal(env.CaerdonWardrobeCharacterConfig.Icon.OtherSpecs.DRUID4, false, "shared: with the other spec's choice in it")

    -- The lines the addon adds to a tooltip have their switches on this page, each in the block
    -- of the icon its line explains, and each writes to the tooltip's own settings. The upgrade
    -- lines' switch is its own: it can be changed while the arrow is off.
    do
        local lines, learners = env.CaerdonWardrobeshowLoadoutUpgrades, env.CaerdonWardrobeshowRecipeLearners
        Check(lines ~= nil and learners ~= nil, "tooltip lines: both switches are on the Icons page")
        Equal(lines and lines:GetChecked(), true, "tooltip lines: the upgrade lines are on as the settings start")
        Click(world, lines, false)
        Equal(env.CaerdonWardrobeConfig.Tooltip.ShowLoadoutUpgrades, false, "tooltip lines: a click writes to the tooltip's settings")
        Equal(env.CaerdonWardrobeConfig.Icon.ShowLoadoutUpgrades, nil, "tooltip lines: and not among the icon's")
        Equal(#world.refreshes, 1, "tooltip lines: with one refresh")
        Click(world, lines, true)
        Click(world, learners, false)
        Equal(env.CaerdonWardrobeConfig.Tooltip.ShowRecipeLearners, false, "tooltip lines: the toon's name the same way")
        Click(world, learners, true)
        local arrow = env.CaerdonWardrobeshowUpgradeIcon
        Click(world, arrow, false)
        Equal(lines:IsEnabled(), true, "tooltip lines: the upgrade lines' switch does not hang on the arrow's")
        Equal(gearSets:IsEnabled(), false, "tooltip lines: as an option under the arrow does")
        -- The auction house's upgrade column is one more place of the arrow's: its switch is
        -- under the arrow's here, and writes to the auction house's settings.
        local column = env.CaerdonWardrobeauctionUpgradeColumn
        Check(column ~= nil and column:IsEnabled() == false, "upgrade column: its switch is on this page and hangs on the arrow's")
        Equal(column and column.Text:GetText(), "In the auction house", "upgrade column: named as a place of the arrow's, like the one above it")
        Click(world, arrow, true)
        Equal(column and column:IsEnabled(), true, "upgrade column: usable with the arrow on")
        Click(world, column, false)
        Equal(env.CaerdonWardrobeConfig.Auction.UpgradeColumn, false, "upgrade column: a click writes to the auction house's settings")
        Click(world, column, true)
        Equal(env.CaerdonWardrobeauctionIconColumn, nil, "icon column: it has no switch")
        -- The grey gear has a block that says what it is, and no switch.
        Check(Texts(world)["Learnable later"] == true, "gear: the page says what the grey gear is")
    end

    -- 4. Another toon's table, as the client loads one per character.
    rawset(env, "CaerdonWardrobeCharacterConfig", { Icon = { OtherSpecs = { DRUID1 = false } } })
    world.page.OnRefresh()
    Equal(Ticked("One"), false, "another toon: its spec that is off shows as off")
    Equal(Ticked("Two"), true, "another toon: and the rest as on")
    Equal(Ticked("Four"), true, "another toon: the first toon's choice is not shown")
    Equal(gearSets:GetChecked(), false, "another toon: the player's setting is the same for it")
    rawset(env, "CaerdonWardrobeCharacterConfig", nil)
    world.page.OnRefresh()
    Equal(Ticked("One"), true, "another toon: one with no table shows every spec as on")

    -- 5. Saved data that is no table.
    rawset(env, "CaerdonWardrobeCharacterConfig", 7)
    world.page.OnRefresh()
    Equal(Ticked("Three"), true, "broken: saved data that is no table reads as never chosen")
    Click(world, Tick("Three"), false)
    own = env.CaerdonWardrobeCharacterConfig
    Equal(type(own) == "table" and own.Icon.OtherSpecs.DRUID3, false, "broken: and the first click makes the table anew")
    rawset(env, "CaerdonWardrobeCharacterConfig", { Icon = { OtherSpecs = { DRUID3 = false } } })

    -- The switches follow the option above the list.
    Click(world, shared, false)
    Equal(Tick("One"):IsEnabled(), false, "depends: with the option off the switches cannot be changed")
    Equal(env.CaerdonWardrobeCharacterConfig.Icon.OtherSpecs.DRUID3, false, "depends: and the toon's choice stays")
    world.page.OnRefresh()
    Equal(Tick("One"):IsEnabled(), false, "depends: nor after the page is shown again")
    Click(world, shared, true)
    Equal(Tick("One"):IsEnabled(), true, "depends: with it on again they can")

    -- 6. The toon's gear sets, each with the Pawn scale it is scored on.
    -- Pawn has a scale for two of the class's specs here, one of the player's own and one of
    -- another class.
    local OWN, MAGE = "My tanking", "\"MrRobot\":MAGE1"
    world.scales[BALANCE], world.scales[RESTORATION] = nil, nil
    world.scales[OWN] = {}
    world.scales[MAGE] = { ClassID = 8, SpecID = 1, Provider = "MrRobot", LocalizedName = "Mage: Arcane" }
    local equipment = env.CaerdonEquipment
    local scrollChild = list:GetParent()
    -- Which gear sets hold a piece with a PVP floor is the equipment code's to find
    -- (scenarios/pawn-scales.lua); here it is said for it.
    function equipment:GearSetHasPvpFloor(setID)
        return world.pvpFloor ~= nil and world.pvpFloor[setID] == true
    end
    world.pvpFloor = { [41] = true }
    local function Open(row)
        world.menu = {}
        row.dropdown.initialize()
        local titles, checked = {}, {}
        for index, entry in ipairs(world.menu) do
            titles[index] = tostring(entry.text)
            if entry.checked then
                checked[#checked + 1] = tostring(entry.text)
            end
        end
        return world.menu, table.concat(titles, " | "), table.concat(checked, " | ")
    end
    local function Choose(entry)
        world.refreshes = {}
        entry.func()
    end
    local ROW, LINE = 34, 16

    -- The list changes its height, so what the page holds after it hangs below it.
    Equal(env.CaerdonWardrobeshowUpgradeIcon:GetParent(), scrollChild, "gear sets: what is above the list is laid out on the page")
    local below = env.CaerdonWardrobeshowQuestItems:GetParent()
    Check(below ~= nil and below ~= scrollChild and below:GetParent() == scrollChild,
        "gear sets: what is below it is laid out on a frame of its own, which hangs below the list")

    -- No gear sets, on a client with talent trees, which has no specs to list either: one line
    -- that says what the list is for.
    local api = env.CaerdonAPI
    local hadTrees = api.GetTalentTrees
    rawset(env, "CaerdonWardrobeCharacterConfig", nil)
    world.setForSpec = { [3] = 31 }
    world.setIDs, world.setNames = nil, nil
    api.GetTalentTrees = function() return { { index = 1 }, { index = 2 }, { index = 3 } } end
    world.page.OnRefresh()
    Equal(RowsShown(), 0, "gear sets: a toon with none has no row")
    Equal(list.header:IsShown(), true, "gear sets: and one line")
    Check(Says(list.header:GetText(), "Zzyxa has no gear sets."), "gear sets: which says so: " .. tostring(list.header:GetText()))
    Equal(list:GetHeight(), LINE, "gear sets: the list is that line high")
    local emptyHeight = scrollChild:GetHeight()
    api.GetTalentTrees = hadTrees

    -- Two sets: one no spec is tied to, and Guardian's. Feral has neither a set nor a set's
    -- scale, so it has a row as a spec.
    world.setIDs, world.setNames = { 41, 31 }, { [31] = "Bear", [41] = "Arena" }
    world.page.OnRefresh()
    Equal(RowsShown(), 3, "gear sets: a row for each set, and one for the spec with none")
    Equal(list.rows[3].name:GetText(), "Feral", "gear sets: the spec comes after the sets")
    Check(Says(list.header:GetText(), "Zzyxa's gear sets and specs (kept per character)."),
        "gear sets: under a line that names the toon and says the choice is its own")
    Equal(list.rows[1].name:GetText(), "Arena", "gear sets: in the client's order")
    Equal(list.rows[1].text:GetText(), "Not tied", "gear sets: a set nobody tied, and no spec's, is not tied")
    Equal(list.rows[2].name:GetText(), "Bear", "gear sets: the second set")
    Equal(list.rows[2].text:GetText(), "By its specialization (Guardian)", "gear sets: a spec's set goes by the spec until it is tied")
    Equal(scrollChild:GetHeight(), emptyHeight + 3 * ROW, "gear sets: the page grows by a row for each")
    Equal(env.CaerdonWardrobeCharacterConfig, nil, "gear sets: showing them writes nothing")
    Check(Tick("Arena"):IsEnabled() == false and Ticked("Arena") == false, "gear sets: a set with no scale has no switch to click")
    Check(Row("Arena").mark ~= nil and Row("Arena").mark:IsShown() == (world.pvpFloor ~= nil and world.pvpFloor[41] == true),
        "pvp mark: a set that is not scored yet is offered it by what it holds, as any set")
    Equal(Row("Bear").mark:IsShown(), false, "pvp mark: nor has a set with no piece that has a PVP floor")
    Check(Tick("Bear"):IsEnabled() == true and Ticked("Bear") == true, "gear sets: its spec's set has the spec's, on for the set")

    -- The scales to choose from.
    local menu, titles, checked = Open(list.rows[1])
    Equal(titles, "Not tied | Druid: Feral | Druid: Guardian (used by Bear) | My tanking",
        "gear sets: the class's scales in the order of its specs, then the player's own, and no other class's")
    -- A scale is one gear set's: Guardian's is Bear's, through the spec the client ties it to.
    Check(menu[3].disabled == true and menu[3].func == nil, "gear sets: a scale another set is scored on cannot be chosen")
    Equal(menu[3].tooltipWhileDisabled, true, "gear sets: and still says why")
    Check(Says(menu[3].tooltipText, "Bear is scored on this one as the set assigned to Guardian in the character window"),
        "gear sets: through the spec it is assigned to: " .. tostring(menu[3].tooltipText))
    Check(menu[2].disabled == nil and type(menu[2].func) == "function", "gear sets: a scale no set has can be")
    Equal(checked, "Not tied", "gear sets: the entry in effect is the one marked")
    Check(Says(menu[1].tooltipText, "your gear is scored for the specialization you are playing."),
        "gear sets: what an untied set goes by: " .. tostring(menu[1].tooltipText))
    Check(Says(menu[2].tooltipText, "While you wear this gear set, upgrades are scored on this scale") and
        Says(menu[2].tooltipText, "Kept for this character only."), "gear sets: what a tie does, and where it is kept")

    -- A choice.
    Choose(menu[2])
    own = env.CaerdonWardrobeCharacterConfig
    Equal(type(own) == "table" and own.Icon.GearSetScales[41], FERAL, "choice: written to the toon's table, by the set's ID")
    Equal(env.CaerdonWardrobeConfig.Icon.GearSetScales, nil, "choice: and not to the player's settings")
    Equal(#world.refreshes, 1, "choice: one refresh")
    Equal(world.refreshes[1], "settings", "choice: named for the settings")
    Equal(list.rows[1].text:GetText(), "Druid: Feral", "choice: the row shows it at once")
    Equal(list.rows[2].text:GetText(), "By its specialization (Guardian)", "choice: the other row is as it was")
    -- The set speaks for the scale now: the spec whose scale it is has no row beside it, and
    -- the set has a switch of its own, on until it is clicked.
    Equal(RowsShown(), 2, "choice: the spec whose scale the set was given is no longer listed by itself")
    Equal(scrollChild:GetHeight(), emptyHeight + 2 * ROW, "choice: and the page is a row shorter")
    Check(Tick("Arena"):IsEnabled() == true and Ticked("Arena") == true, "its own switch: a set with a scale of its own has one, on")
    Check(Says(Hover(world, Tick("Arena")), "Show upgrades for this gear set, in red, while you wear another.") and
        Says(Hover(world, Tick("Arena")), "Kept for this character only."), "its own switch: which says what it does")
    Equal(equipment:IsGearSetWanted(41), true, "its own switch: and the equipment code takes the set as wanted")
    Click(world, Tick("Arena"), false)
    Equal(own.Icon.OtherSets[41], false, "its own switch: a click is written to the toon's table, by the set's ID")
    Equal(world.lastDetail, "Icon.OtherSets.41 = false, this toon's", "its own switch: and the refresh says which value the click wrote")
    Equal(env.CaerdonWardrobeConfig.Icon.OtherSets, nil, "its own switch: and not to the player's settings")
    Equal(own.Icon.OtherSpecs, nil, "its own switch: nor as a spec's")
    Equal(#world.refreshes, 1, "its own switch: with one refresh")
    Equal(equipment:IsGearSetWanted(41), false, "its own switch: the equipment code reads it")
    Check(Says(equipment:GetGearSetScaleDescription(), "\"Arena\" (41) tied to Druid: Feral, its upgrades switched off while another set is worn"),
        "its own switch: and the export says so: " .. tostring(equipment:GetGearSetScaleDescription()))
    world.page.OnRefresh()
    Equal(Ticked("Arena"), false, "its own switch: shown as off when the page shows again")
    Click(world, Tick("Arena"), true)
    Equal(own.Icon.OtherSets[41], true, "its own switch: and on again")

    -- The second switch of a row: the set is one for PVP.
    world.page.OnRefresh()
    local mark = Row("Arena").mark
    Check(mark:IsShown() == true and mark:GetChecked() == false, "pvp mark: a scored set with a piece that has a floor is offered it, off")
    Equal(mark.Text:GetText(), "PvP", "pvp mark: under its name")
    Equal(mark, env.CaerdonWardrobegearSetScaleMark1, "pvp mark: at the row's end, a control of its own")
    Check(Says(Hover(world, mark), "Score this gear set as it is in PvP.") and Says(Hover(world, mark), "Kept for this character only."),
        "pvp mark: its tooltip says what it does: " .. Hover(world, mark))
    Equal(Row("Bear").mark:IsShown(), false, "pvp mark: the set beside it has none")
    Click(world, mark, true)
    Equal(own.Icon.PvpSets[41], true, "pvp mark: a click is written to the toon's table, by the set's ID")
    Equal(env.CaerdonWardrobeConfig.Icon.PvpSets, nil, "pvp mark: and not to the player's settings")
    Equal(#world.refreshes, 1, "pvp mark: with one refresh")
    Equal(equipment:IsPvpGearSet(41), true, "pvp mark: the equipment code reads it")
    Check(Says(equipment:GetGearSetScaleDescription(), "\"Arena\" (41) tied to Druid: Feral, marked as a PVP set"),
        "pvp mark: and the export says so: " .. tostring(equipment:GetGearSetScaleDescription()))
    -- It hangs on nothing: with the option above the list off, it can still be clicked.
    Click(world, shared, false)
    Check(Tick("Arena"):IsEnabled() == false and mark:IsEnabled() == true, "pvp mark: usable with the red arrows switched off")
    Click(world, shared, true)
    -- A marked set keeps its mark to be unticked, also with the piece gone from it.
    world.pvpFloor = nil
    world.page.OnRefresh()
    Check(Row("Arena").mark:IsShown() == true and Row("Arena").mark:GetChecked() == true, "pvp mark: a marked set shows it as long as it is marked")
    Click(world, Row("Arena").mark, false)
    Equal(own.Icon.PvpSets[41], false, "pvp mark: unticked")
    world.page.OnRefresh()
    Equal(Row("Arena").mark:IsShown(), false, "pvp mark: and then it is gone with the piece")
    world.pvpFloor = { [41] = true }
    world.page.OnRefresh()
    -- Two sets on one scale, where one of them is marked for PVP: the toon has no scale of
    -- its own for PVP, and the set takes the one its spec's set is scored on.
    do
        local hadRefreshes = world.refreshes
        local menu, titles = Open(list.rows[1])
        Equal(titles, "Not tied | Druid: Feral | Druid: Guardian (used by Bear) | My tanking",
            "shared scale: not marked, a scale another set has is not offered")
        Check(Says(menu[3].tooltipText, "A scale is for one gear set, or for two where one of them is marked PvP"),
            "shared scale: and its entry says when it would be: " .. tostring(menu[3].tooltipText))
        Click(world, Row("Arena").mark, true)
        Check(Says(Hover(world, Row("Arena").mark), "A set marked PvP can use the scale another gear set is scored on"),
            "shared scale: the mark's tooltip says what it allows: " .. Hover(world, Row("Arena").mark))
        menu, titles = Open(list.rows[1])
        Equal(titles, "Not tied | Druid: Feral | Druid: Guardian (also used by Bear) | My tanking",
            "shared scale: marked for PVP, the scale of the spec's own set is offered, with whose it is")
        Check(menu[3].disabled == nil and type(menu[3].func) == "function", "shared scale: and can be chosen")
        Check(Says(menu[3].tooltipText, "Bear is scored on this scale too.") and Says(menu[3].tooltipText, "the same weights serve both"),
            "shared scale: its entry says why that works: " .. tostring(menu[3].tooltipText))
        Choose(menu[3])
        Equal(own.Icon.GearSetScales[41], "\"MrRobot\":DRUID3", "shared scale: the tie is written as any other")
        Equal(list.rows[1].text:GetText(), "Druid: Guardian", "shared scale: and shown by the scale's name")
        Check(Says(equipment:GetGearSetScaleDescription(), "\"Arena\" (41) tied to Druid: Guardian, marked as a PVP set"),
            "shared scale: the equipment code reads it: " .. tostring(equipment:GetGearSetScaleDescription()))
        -- The other set sees the same from its side, and keeps its own scale.
        menu, titles = Open(list.rows[2])
        Equal(titles, "By its specialization (Guardian) | Druid: Feral | Druid: Guardian (also used by Arena) | My tanking",
            "shared scale: the spec's own set is told who else has its scale")
        Check(menu[3].disabled == nil, "shared scale: and could be tied to it as well")
        -- A second set marked for PVP could not take it: one of each kind.
        world.setIDs, world.setNames[51] = { 41, 31, 51 }, "Duels"
        world.pvpFloor[51] = true
        own.Icon.PvpSets[51] = true
        world.page.OnRefresh()
        menu, titles = Open(list.rows[3])
        Equal(titles, "Not tied | Druid: Feral | Druid: Guardian (used by Arena) | My tanking",
            "shared scale: a second marked set is not offered the scale the first has")
        Check(menu[3].disabled == true, "shared scale: it cannot be chosen")
        world.setIDs, world.setNames[51], world.pvpFloor[51], own.Icon.PvpSets[51] = { 41, 31 }, nil, nil, nil
        world.page.OnRefresh()
        -- The mark taken away: the set keeps its scale, which is never greyed for its own row.
        Click(world, Row("Arena").mark, false)
        menu, titles = Open(list.rows[1])
        Equal(titles, "Not tied | Druid: Feral | Druid: Guardian | My tanking", "shared scale: unmarked again, the set's own scale stays its entry")
        Choose(menu[2])
        Equal(own.Icon.GearSetScales[41], "\"MrRobot\":DRUID2", "shared scale: and it can be tied elsewhere again")
        world.page.OnRefresh()
        world.refreshes = hadRefreshes
    end
    Check(Says(equipment:GetGearSetScaleDescription(), "\"Arena\" (41) tied to Druid: Feral"),
        "choice: and the equipment code reads it: " .. tostring(equipment:GetGearSetScaleDescription()))
    menu, titles, checked = Open(list.rows[1])
    Equal(checked, "Druid: Feral", "choice: the scale chosen is the one marked then")
    -- The spec's own set, to a scale of the player's own; and back.
    menu, titles = Open(list.rows[2])
    Equal(menu[1].text, "By its specialization (Guardian)", "choice: a spec's set has that as its first entry")
    Check(Says(menu[1].tooltipText, "assigned to Guardian in the character window"), "choice: with why")
    Equal(titles, "By its specialization (Guardian) | Druid: Feral (used by Arena) | Druid: Guardian | My tanking",
        "one set a scale: the scale Arena was tied to is not offered to Bear")
    Check(menu[2].disabled == true and menu[2].func == nil, "one set a scale: it cannot be chosen")
    Check(Says(menu[2].tooltipText, "Arena is scored on this one. Choose another scale for Arena first."),
        "one set a scale: and says whose it is: " .. tostring(menu[2].tooltipText))
    Check(menu[3].disabled == nil, "one set a scale: the scale of a set's own spec is not another set's")
    Choose(menu[4])
    Equal(own.Icon.GearSetScales[31], OWN, "choice: a scale of the player's own")
    Equal(list.rows[2].text:GetText(), "My tanking", "choice: shown by its name")
    menu, titles, checked = Open(list.rows[1])
    Equal(titles, "Not tied | Druid: Feral | Druid: Guardian | My tanking (used by Bear)",
        "one set a scale: tied elsewhere, Bear has that scale and no longer its spec's")
    Equal(checked, "Druid: Feral", "one set a scale: a set's own scale stays the one marked")
    menu = Open(list.rows[2])
    Choose(menu[1])
    Equal(own.Icon.GearSetScales[31], nil, "choice: the first entry takes the tie away")
    Equal(#world.refreshes, 1, "choice: with one refresh")
    Equal(list.rows[2].text:GetText(), "By its specialization (Guardian)", "choice: and the set goes by its spec again")

    -- Two sets that came by one scale all the same: each row keeps its own, and neither is
    -- greyed in its own menu.
    own.Icon.GearSetScales[31] = FERAL
    world.page.OnRefresh()
    menu, titles, checked = Open(list.rows[2])
    Check(menu[2].disabled == nil and checked == "Druid: Feral",
        "one set a scale: a scale two sets have is each one's own in its menu: " .. titles)
    menu, titles, checked = Open(list.rows[1])
    Check(menu[2].disabled == nil and checked == "Druid: Feral", "one set a scale: in the other's too: " .. titles)
    own.Icon.GearSetScales[31] = nil

    -- A scale that is gone from Pawn: said, and no entry is the one chosen.
    own.Icon.GearSetScales[31] = "Old scale"
    world.page.OnRefresh()
    Equal(list.rows[2].text:GetText(), "Old scale (no longer in Pawn)", "gone: the row says the scale is gone")
    menu, titles, checked = Open(list.rows[2])
    Equal(checked, "", "gone: and no entry is marked")
    menu, titles = Open(list.rows[1])
    Equal(titles, "Not tied | Druid: Feral | Druid: Guardian (used by Bear) | My tanking",
        "gone: a set whose scale is gone has its spec's scale again")
    own.Icon.GearSetScales[31] = nil

    -- A set nobody tied and no spec's, named as a spec of the class is: scored on the scale
    -- Pawn has for that spec, by its name, and the spec has no row beside it. The names are
    -- compared without their case and the blanks around them. In a client a renamed set and a
    -- changed tie both come with a refresh, which empties what the equipment code kept; here
    -- that is called by hand.
    local keptTies, keptPvp = own.Icon.GearSetScales, own.Icon.PvpSets
    own.Icon.GearSetScales, own.Icon.PvpSets = {}, nil
    local function Reread()
        equipment:InvalidateCaches()
        world.page.OnRefresh()
    end
    world.setNames[41] = " feral "
    Reread()
    Equal(list.rows[1].text:GetText(), "By its name (Feral)", "by name: a set named as a spec is goes by that spec")
    Equal(RowsShown(), 2, "by name: and the spec has no row beside its set")
    Check(Tick(" feral "):IsEnabled() == true and Ticked(" feral ") == true, "by name: it has a set's own switch, on")
    menu, titles, checked = Open(list.rows[1])
    Equal(titles, "By its name (Feral) | Druid: Feral | Druid: Guardian (used by Bear) | My tanking",
        "by name: the first entry says what the set goes by")
    Equal(checked, "By its name (Feral)", "by name: and is the one marked")
    Check(Says(menu[1].tooltipText, "named as the specialization Feral is") and
        Says(menu[1].tooltipText, "Choose a scale below to score it on another."),
        "by name: with why, and what to do about it: " .. tostring(menu[1].tooltipText))
    Check(Says(equipment:GetGearSetScaleDescription(), "(41) scored on Druid: Feral by its name, which is Feral's"),
        "by name: the export says so: " .. tostring(equipment:GetGearSetScaleDescription()))
    menu, titles = Open(list.rows[2])
    Equal(titles, "By its specialization (Guardian) | Druid: Feral (used by  feral ) | Druid: Guardian | My tanking",
        "by name: the scale is that set's for the other sets")
    -- A spec given to the set in the character window, with the settings shut as that window
    -- needs them to be. The game sends no event for it: the client's function is watched and
    -- the addon refreshes, so the page says what the set is now when it is next opened, and
    -- not what the equipment code had kept from before.
    Check(Says(equipment:GetGearSetScaleDescription(), "(a spec given to a set or taken from it is heard: yes)"),
        "assigned: the export says the client's two functions are watched: " .. tostring(equipment:GetGearSetScaleDescription()))
    world.page:Hide()
    world.refreshes = {}
    env.C_EquipmentSet.AssignSpecToEquipmentSet(41, 2)
    Equal(table.concat(world.refreshes, ","), "gear sets", "assigned: one refresh of the addon's for a spec given to a set")
    world.page:Show()
    world.page.OnRefresh()
    Equal(list.rows[1].text:GetText(), "By its specialization (Feral)", "assigned: the page opened after it says what the set is now")
    world.page:Hide()
    world.refreshes = {}
    env.C_EquipmentSet.UnassignEquipmentSetSpec(41)
    Equal(table.concat(world.refreshes, ","), "gear sets", "unassigned: one refresh for a spec taken from a set")
    world.page:Show()
    world.page.OnRefresh()
    Equal(list.rows[1].text:GetText(), "By its name (Feral)", "unassigned: and the page opened after it has the set by its name again")
    Check(Tick(" feral "):IsEnabled() == true and Ticked(" feral ") == true, "unassigned: with the set's own switch, on as it was")

    -- The player's own tie comes first, and the spec is one without a set again.
    own.Icon.GearSetScales[41] = OWN
    Reread()
    Equal(list.rows[1].text:GetText(), "My tanking", "by name: a scale the player chose comes first")
    Equal(RowsShown(), 3, "by name: and the spec is listed by itself again")
    own.Icon.GearSetScales[41] = nil
    -- A name two sets have says nothing for either.
    world.setIDs, world.setNames[51] = { 41, 31, 51 }, "Feral"
    Reread()
    Check(list.rows[1].text:GetText() == "Not tied" and list.rows[3].text:GetText() == "Not tied" and RowsShown() == 4,
        "by name: two sets of one name are neither taken by it")
    world.setIDs, world.setNames[51] = { 41, 31 }, nil
    -- A scale another set of the same kind is tied to is that set's, whatever a set is named.
    own.Icon.GearSetScales[31] = FERAL
    Reread()
    Equal(list.rows[1].text:GetText(), "Not tied", "by name: not on a scale another set is tied to")
    own.Icon.GearSetScales[31] = nil
    -- A set the client assigns to a spec is that spec's, whatever it is named; and a spec
    -- with a set assigned takes no other by its name.
    world.setNames[41], world.setNames[31] = "Arena", "Feral"
    Reread()
    Equal(list.rows[2].text:GetText(), "By its specialization (Guardian)", "by name: a set assigned to a spec goes by that")
    Equal(RowsShown(), 3, "by name: and the spec it is named after is still one without a set")
    world.setNames[41], world.setNames[31] = "Guardian", "Bear"
    Reread()
    Equal(list.rows[1].text:GetText(), "Not tied", "by name: a spec that has a set assigned takes no other by its name")
    -- A client with talent trees: by the tree's name, on the scale Pawn has for the tree.
    world.setNames[41], world.setNames[31] = "Arena", "Feral Combat"
    api.GetTalentTrees = function()
        return { { index = 1, name = "Balance" }, { index = 2, name = "Feral Combat" }, { index = 3, name = "Restoration" } }
    end
    Reread()
    Equal(list.rows[2].text:GetText(), "By its name (Feral Combat)", "by name: on a client with trees, by the tree's name")
    menu = Open(list.rows[2])
    Check(Says(menu[1].tooltipText, "named as the talent tree Feral Combat is"), "by name: and says so: " .. tostring(menu[1].tooltipText))
    Check(Says(equipment:GetGearSetScaleDescription(), "(31) scored on Druid: Feral by its name, which is Feral Combat's"),
        "by name: the tree's scale is the one Pawn has for it: " .. tostring(equipment:GetGearSetScaleDescription()))
    Check(Tick("Feral Combat"):IsEnabled() == true, "by name: with a switch of its own there too")
    api.GetTalentTrees = hadTrees
    world.setNames[31] = "Bear"
    own.Icon.GearSetScales, own.Icon.PvpSets = keptTies, keptPvp
    Reread()

    -- A client with talent trees has no spec for a set to go by, and none to list.
    api.GetTalentTrees = function() return { { index = 1 }, { index = 2 }, { index = 3 } } end
    world.page.OnRefresh()
    Equal(RowsShown(), 2, "trees: the rows are the gear sets alone")
    Check(Says(list.header:GetText(), "Zzyxa's gear sets (kept per character)."), "trees: and the line names them alone")
    Check(Tick("Bear"):IsEnabled() == false, "trees: a set with no scale has no switch to click there either")
    Check(Tick("Arena"):IsEnabled() == true, "trees: one with a scale has")
    Equal(list.rows[2].text:GetText(), "Not tied", "trees: no set goes by a specialization there")
    menu = Open(list.rows[2])
    Check(Says(menu[1].tooltipText, "your gear is scored for the talent tree you have the most points in."),
        "trees: and an untied set goes by the leading tree: " .. tostring(menu[1].tooltipText))
    menu, titles = Open(list.rows[1])
    Equal(titles, "Not tied | Druid: Feral | Druid: Guardian | My tanking", "trees: no set has a scale through a spec there")
    menu, titles = Open(list.rows[2])
    Equal(titles, "Not tied | Druid: Feral (used by Arena) | Druid: Guardian | My tanking",
        "trees: and a tie takes a scale there as it does with specs")
    api.GetTalentTrees = hadTrees

    -- Another toon's table, and its sets.
    rawset(env, "CaerdonWardrobeCharacterConfig", { Icon = { GearSetScales = { [31] = FERAL } } })
    world.page.OnRefresh()
    Equal(list.rows[1].text:GetText(), "Not tied", "another toon: the first toon's tie is not shown")
    Equal(list.rows[2].text:GetText(), "Druid: Feral", "another toon: its own is")
    world.setIDs = { 31 }
    world.page.OnRefresh()
    Equal(RowsShown(), 1, "another toon: with one set, one row")
    Equal(list.rows[1].name:GetText(), "Bear", "another toon: for that set")
    Equal(list.rows[1].text:GetText(), "Druid: Feral", "another toon: with its scale")
    Equal(scrollChild:GetHeight(), emptyHeight + ROW, "another toon: and the page is a row shorter")

    -- A set that is deleted takes its tie and its switch with it: the client gives its ID to
    -- the next set made.
    env.CaerdonWardrobeCharacterConfig.Icon.OtherSets = { [31] = false, [41] = false }
    env.CaerdonWardrobeCharacterConfig.Icon.PvpSets = { [31] = true, [41] = true }
    env.C_EquipmentSet.DeleteEquipmentSet(31)
    Equal(world.deleted, 31, "deleted: the client's own function ran")
    Equal(env.CaerdonWardrobeCharacterConfig.Icon.GearSetScales[31], nil, "deleted: and the set's tie is gone")
    Equal(env.CaerdonWardrobeCharacterConfig.Icon.OtherSets[31], nil, "deleted: with its switch")
    Equal(env.CaerdonWardrobeCharacterConfig.Icon.OtherSets[41], false, "deleted: another set's stays")
    Equal(env.CaerdonWardrobeCharacterConfig.Icon.PvpSets[31], nil, "deleted: and its PVP mark is gone")
    Equal(env.CaerdonWardrobeCharacterConfig.Icon.PvpSets[41], true, "deleted: another set's stays as well")
    Check(Says(equipment:GetGearSetScaleDescription(), "(a deleted set's tie goes with it: yes)"),
        "deleted: the export says the client's function is watched: " .. tostring(equipment:GetGearSetScaleDescription()))
    world.page.OnRefresh()
    Equal(list.rows[1].text:GetText(), "By its specialization (Guardian)", "deleted: a new set with that ID starts untied")

    -- Without Pawn there is nothing to choose: the list takes no room.
    rawset(env, "PawnGetSingleValueFromItem", false)
    world.page.OnRefresh()
    Equal(RowsShown(), 0, "no Pawn: no row")
    Equal(list.header:IsShown(), false, "no Pawn: and no line")
    Equal(list:GetHeight(), 1, "no Pawn: the list keeps a height, for what hangs below it")
    Equal(scrollChild:GetHeight(), emptyHeight - LINE + 1, "no Pawn: and the page is as high as without it")
    rawset(env, "PawnGetSingleValueFromItem", nil)
    rawset(env, "CaerdonWardrobeCharacterConfig", nil)
    world.setIDs, world.setNames = nil, nil
    world.page.OnRefresh()
    Equal(RowsShown(), 1, "no Pawn: with Pawn again, the spec that has no gear set is listed")
    Equal(scrollChild:GetHeight(), emptyHeight + ROW, "no Pawn: and the page is as high as that")

    -- 7. A page's height with such a list: a page of this scenario's own, with one row above
    -- the list and one below. 16 above the first row, 26 a row, 24 below the last.
    do
        local panel = env.CreateFromMixins(env.CaerdonWardrobeConfigPanelMixin)
        function panel:GetTitle() return "A page" end
        panel:Init()
        local entries, chosen = nil, {}
        panel:AddCheckbox({ key = "pageAbove", text = "Above", configSection = "Icon", configValue = "ShowUpgradeIcon" })
        local own = panel:AddDropdownList({
            key = "pageList",
            rows = function() return entries end,
            header = function(count) return count .. " rows" end,
            choices = function(row)
                return { { title = "One", value = 1 }, { title = "Two", value = 2 },
                    { title = "Three", value = 3, disabled = true, tooltip = "Why not" } }
            end,
            choose = function(row, value) chosen[#chosen + 1] = row.text .. "=" .. tostring(value) end,
        })
        panel:AddCheckbox({ key = "pageBelow", text = "Below", configSection = "Icon", configValue = "ShowUpgradeIcon" })
        panel:FinishLayout()
        local child = own:GetParent()
        Equal(child:GetHeight(), 16 + 26 + 1 + 26 + 24, "page: above, a list with nothing to choose from, below")
        entries = {}
        panel:RefreshControls()
        Equal(own.header:GetText(), "0 rows", "page: the line is asked for with the number of rows")
        Equal(child:GetHeight(), 16 + 26 + LINE + 26 + 24, "page: a list with its line alone")
        entries = { { text = "First", value = 2, title = "Two" }, { text = "Second", title = "" }, { text = "Third", title = "" } }
        panel:RefreshControls()
        Equal(child:GetHeight(), 16 + 26 + LINE + 3 * ROW + 26 + 24, "page: and with three rows")
        world.menu = {}
        own.rows[1].dropdown.initialize()
        Equal(#world.menu, 3, "page: a row's menu has the choices it was given")
        Check(world.menu[1].checked == false and world.menu[2].checked == true, "page: with the row's value marked")
        Check(world.menu[3].disabled == true and world.menu[3].func == nil, "page: a choice that cannot be made is greyed and has no click")
        Check(world.menu[3].tooltipWhileDisabled == true and world.menu[3].tooltipText == "Why not",
            "page: and keeps its tooltip, which says why")
        Check(world.menu[1].disabled == nil and world.menu[1].tooltipWhileDisabled == nil and
            type(world.menu[1].func) == "function", "page: the others are as they were")
        world.menu[1].func()
        Equal(chosen[1], "First=1", "page: a click is handed the row and the value")
        entries = { { text = "First", title = "" } }
        panel:RefreshControls()
        Equal(child:GetHeight(), 16 + 26 + LINE + ROW + 26 + 24, "page: and with one again")
        Check(own.rows[2]:IsShown() == false and own.rows[3]:IsShown() == false, "page: the rows of what is gone are not shown")
        -- A page with no such list is as high as what was laid out.
        local plain = env.CreateFromMixins(env.CaerdonWardrobeConfigPanelMixin)
        function plain:GetTitle() return "A plain page" end
        plain:Init()
        local only = plain:AddCheckbox({ key = "pagePlain", text = "Only", configSection = "Icon", configValue = "ShowUpgradeIcon" })
        plain:FinishLayout()
        Equal(only:GetParent():GetHeight(), 16 + 26 + 24, "page: one with no list is as high as what was laid out")
    end

    Equal(#world.client.errors, 0, "end: no error reached the error handler")
    for _, message in ipairs(world.client.errors) do
        Check(false, "end: " .. message)
    end
end
