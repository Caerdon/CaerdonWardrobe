-- The toon's own settings (CaerdonWardrobeCharacterConfig, saved per character), from the
-- settings page's side.
--
-- Most options are the player's and one table for every toon (CaerdonWardrobeConfig). An
-- option marked perCharacter describes the toon, and the page keeps it with the toon. Today
-- that is one: which of the toon's specs "Also for my other specs" is for. Here:
--   1. The Icons page offers a switch per spec of the toon's class, under a label that names
--      the toon and says the choice is kept per character.
--   2. A spec nobody chose shows what the equipment code takes it as: on with a gear set
--      assigned to it or with its scale shown in Pawn by the player's choice, off otherwise.
--      No table is made for the toon by that, and the first click writes that switch alone.
--      The switch's tooltip says which it is: on or off by the player's choice, or because of
--      a gear set or of what Pawn shows.
--   3. A click writes to the toon's table and not to the player's settings, and refreshes the
--      icons once; an ordinary option still writes to the player's settings alone.
--   4. The page shows what the toon's table says each time it is displayed, so another toon's
--      table (the client loads one per character) shows that toon's choice.
--   5. Saved data that is no table reads as "never chosen" and is replaced by the first click.
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
    local GUARDIAN = "\"MrRobot\":DRUID3"

    local function Start()
        local game = H.StockGame(TOON, {})
        local world = { game = game, refreshes = {}, registrants = {}, visible = {} }
        -- What a spec nobody chose is taken from: the gear set assigned to a spec, and the
        -- scales Pawn shows (one here, Guardian's).
        game:Set("C_EquipmentSet.GetEquipmentSetForSpec", function(specIndex)
            return world.setForSpec and world.setForSpec[specIndex] or nil
        end)
        game:Set("PawnCommon.Scales", { [GUARDIAN] = { ClassID = 3, SpecID = 3, Provider = "MrRobot" } })
        game:Set("PawnIsScaleVisible", function(name) return world.visible[name] == true end)
        game:Set("GetSpecialization", function() return 3 end)
        game:Set("GetSpecializationInfoForClassID", function(_, index) return 100 + index, SPECS[index] end)
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

    -- 1. The switches and their label.
    local specs = {}
    for index = 1, #SPECS do
        specs[index] = env["CaerdonWardrobeotherSpec" .. index]
        Check(specs[index] ~= nil, "page: a switch for spec " .. index)
        Equal(specs[index] and specs[index].Text:GetText(), SPECS[index], "page: named for spec " .. index)
    end
    Equal(env.CaerdonWardrobeotherSpec5, nil, "page: and none beyond the class's specs")
    local texts = Texts(world)
    Check(texts["Which of Zzyxa's specs (kept per character):"], "page: the label names the toon and says the choice is its own")
    for index = 1, #SPECS do
        local info = specs[index] and specs[index].caerdonInfo or {}
        Equal(info.perCharacter, true, "page: spec " .. index .. " is marked as the toon's own")
        Equal(info.configValue, "DRUID" .. index, "page: and keyed by class file and index")
    end
    local shared = env.CaerdonWardrobeshowOtherSpecUpgrades
    Check(shared ~= nil and shared.caerdonInfo.perCharacter == nil, "page: the option above them is the player's, for every toon")

    -- 2. Nobody chose: what the game and Pawn say, and nothing made.
    for index = 1, #SPECS do
        Equal(specs[index]:GetChecked(), false,
            "never chosen: with no gear set and no scale shown, spec " .. index .. " shows as off")
    end
    local hint = Hover(world, specs[1])
    Check(Says(hint, "Show upgrades for Balance while you play another specialization."), "tooltip: what the switch does: " .. hint)
    Check(Says(hint, "Off because no gear set is assigned to Balance and Pawn is not set to show its scale. " .. FOLLOWS),
        "tooltip: off, and why, for a spec with neither sign")
    Check(Says(hint, "Kept for this character only."), "tooltip: and that the choice is the character's")
    Equal(world.tooltip.title, "Balance", "tooltip: under the spec's name")
    world.setForSpec = { [2] = 21 }
    world.page.OnRefresh()
    Equal(specs[2]:GetChecked(), true, "never chosen: a gear set assigned to a spec shows it as on")
    Equal(specs[1]:GetChecked(), false, "never chosen: and no other spec")
    Check(Says(Hover(world, specs[2]), "On because a gear set is assigned to Feral. " .. FOLLOWS),
        "tooltip: on because of the gear set: " .. Hover(world, specs[2]))
    world.visible = { [GUARDIAN] = true }
    world.page.OnRefresh()
    Equal(specs[3]:GetChecked(), true, "never chosen: a scale the player has Pawn show does too")
    Check(Says(Hover(world, specs[3]), "On because Pawn is set to show the Guardian scale. " .. FOLLOWS),
        "tooltip: on because of Pawn's shown scale: " .. Hover(world, specs[3]))
    rawset(env, "PawnOptions", { AutoSelectScales = true })
    world.page.OnRefresh()
    Equal(specs[3]:GetChecked(), false, "never chosen: not a scale Pawn shows by itself")
    hint = Hover(world, specs[3])
    Check(Says(hint, "Off because no gear set is assigned to Guardian. " .. FOLLOWS) and not Says(hint, "Pawn is not set"),
        "tooltip: with Pawn picking its scales, off for want of a gear set alone: " .. hint)
    Equal(env.CaerdonWardrobeCharacterConfig, nil, "tooltip: a look at it writes nothing for the toon")
    Equal(specs[2]:GetChecked(), true, "never chosen: the spec with the gear set stays on")
    Equal(env.CaerdonWardrobeCharacterConfig, nil, "never chosen: and the toon has no table")
    -- The first click writes its own switch and leaves the others to follow the game.
    Click(world, specs[1], true)
    local own = env.CaerdonWardrobeCharacterConfig
    Equal(type(own) == "table" and own.Icon.OtherSpecs.DRUID1, true, "first click: the clicked spec is written")
    Equal(type(own) == "table" and own.Icon.OtherSpecs.DRUID2, nil, "first click: a spec that only showed as on is not")
    hint = Hover(world, specs[1])
    Check(Says(hint, "On by your choice.") and not Says(hint, "Until you click it"),
        "tooltip: a clicked switch is the player's choice and follows nothing: " .. hint)
    Check(Says(Hover(world, specs[2]), "On because a gear set is assigned to Feral."),
        "tooltip: the unclicked one beside it still gives the game's reason")
    Click(world, specs[1], false)
    Check(Says(Hover(world, specs[1]), "Off by your choice."), "tooltip: switched off, it says that")
    Click(world, specs[1], true)
    world.setForSpec = nil
    world.page.OnRefresh()
    Equal(specs[1]:GetChecked(), true, "first click: the choice stands when the game says otherwise")
    Equal(specs[2]:GetChecked(), false, "first click: and the unclicked spec follows the game")
    rawset(env, "CaerdonWardrobeCharacterConfig", nil)
    rawset(env, "PawnOptions", nil)
    world.visible = {}

    -- From here every spec has a gear set assigned, so a spec nobody chose shows as on.
    world.setForSpec = { 11, 12, 13, 14 }
    world.page.OnRefresh()

    -- 3. A click.
    Click(world, specs[2], false)
    own = env.CaerdonWardrobeCharacterConfig
    Equal(type(own), "table", "click: the toon's table is made")
    Equal(own and own.Icon and own.Icon.OtherSpecs and own.Icon.OtherSpecs.DRUID2, false, "click: with the spec off in it")
    Equal(env.CaerdonWardrobeConfig.Icon.OtherSpecs, nil, "click: and nothing about specs in the player's settings")
    Equal(#world.refreshes, 1, "click: one refresh")
    Equal(world.refreshes[1], "settings", "click: named for the settings")
    Click(world, specs[2], true)
    Equal(env.CaerdonWardrobeCharacterConfig.Icon.OtherSpecs.DRUID2, true, "click: switched on again, it is on in the toon's table")
    Click(world, specs[4], false)

    -- An ordinary option is the player's.
    local before = H.DeepCopy(env.CaerdonWardrobeCharacterConfig)
    local gearSets = env.CaerdonWardrobeshowUpgradeOnGearSets
    Equal(gearSets:GetChecked(), true, "shared: an ordinary option shows the player's setting")
    Check(Says(Hover(world, gearSets), "Show the arrow on items that belong to a saved gear set."),
        "shared: and its tooltip is its text, as before")
    Click(world, gearSets, false)
    Equal(env.CaerdonWardrobeConfig.Icon.ShowUpgradeOnGearSets, false, "shared: its click writes to the player's settings")
    Equal(env.CaerdonWardrobeCharacterConfig.Icon.ShowUpgradeOnGearSets, nil, "shared: and not to the toon's table")
    Equal(env.CaerdonWardrobeCharacterConfig.Icon.OtherSpecs.DRUID2, before.Icon.OtherSpecs.DRUID2, "shared: which is as it was")
    Equal(env.CaerdonWardrobeCharacterConfig.Icon.OtherSpecs.DRUID4, false, "shared: with the other spec's choice in it")

    -- 4. Another toon's table, as the client loads one per character.
    rawset(env, "CaerdonWardrobeCharacterConfig", { Icon = { OtherSpecs = { DRUID1 = false } } })
    world.page.OnRefresh()
    Equal(specs[1]:GetChecked(), false, "another toon: its spec that is off shows as off")
    Equal(specs[2]:GetChecked(), true, "another toon: and the rest as on")
    Equal(specs[4]:GetChecked(), true, "another toon: the first toon's choice is not shown")
    Equal(gearSets:GetChecked(), false, "another toon: the player's setting is the same for it")
    rawset(env, "CaerdonWardrobeCharacterConfig", nil)
    world.page.OnRefresh()
    Equal(specs[1]:GetChecked(), true, "another toon: one with no table shows every spec as on")

    -- 5. Saved data that is no table.
    rawset(env, "CaerdonWardrobeCharacterConfig", 7)
    world.page.OnRefresh()
    Equal(specs[3]:GetChecked(), true, "broken: saved data that is no table reads as never chosen")
    Click(world, specs[3], false)
    own = env.CaerdonWardrobeCharacterConfig
    Equal(type(own) == "table" and own.Icon.OtherSpecs.DRUID3, false, "broken: and the first click makes the table anew")
    rawset(env, "CaerdonWardrobeCharacterConfig", { Icon = { OtherSpecs = { DRUID3 = false } } })

    -- The switches follow the option above them.
    Click(world, shared, false)
    Equal(specs[1]:IsEnabled(), false, "depends: with the option off the switches cannot be changed")
    Equal(env.CaerdonWardrobeCharacterConfig.Icon.OtherSpecs.DRUID3, false, "depends: and the toon's choice stays")
    Click(world, shared, true)
    Equal(specs[1]:IsEnabled(), true, "depends: with it on again they can")

    Equal(#world.client.errors, 0, "end: no error reached the error handler")
    for _, message in ipairs(world.client.errors) do
        Check(false, "end: " .. message)
    end
end
