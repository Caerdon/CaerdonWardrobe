-- What a window shows of a draw (a feature's displayRules).
--
-- Every window used to answer with a function that built a table of six answers at each draw,
-- in some twenty spellings. A window whose answers do not depend on the draw now declares them
-- (FeatureMixin.lua), and GetDisplayInfoInternal lays them over what the core has for every
-- window. A window whose answer depends on the item or the button keeps a function, laid over
-- the declaration; a feature that draws another's content answers with that feature's rules.
--
--   1. The shipped declarations: every file that has one loads, and names only rules there
--      are and settings the default settings have.
--   2. The declaration itself, with windows of the scenario's own: what is not named, each
--      kind of value, a function beside it, the binding settings, a rule misnamed.
--   3. Every shipped window that declares, against the answers its function gave (Reference
--      below, with the core's part as it was), over each setting alone and every draw. Six
--      of them differ from their functions in one answer, on purpose: the quest icon.
--   4. Through ProcessItem: the drawing is handed the declared rules.
--
-- Real code: the core, FeatureMixin.lua and the feature files, whose Init is not run (the
-- declaration is on the mixin). The items are plain tables with what the rules read.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Druid", classFile = "DRUID", race = "Night Elf",
        faction = "Alliance", level = 60 }

    -- The rules a draw reads, and the settings a declaration can name a window's key of.
    local RULES = { bindingStatus = true, ownIcon = true, otherIcon = true, questIcon = true, oldExpansionIcon = true,
        sellableIcon = true, upgradeIcon = true, auctionIcon = true, levelGain = true, statusIcon = true }
    local WINDOW_SETTINGS = {
        bindingStatus = { "Binding", "ShowStatus" },
        ownIcon = { "Icon", "ShowLearnable" },
        otherIcon = { "Icon", "ShowLearnableByOther" },
        sellableIcon = { "Icon", "ShowSellable" },
    }

    -- Every setting a display rule reads, by path.
    local SETTINGS = {
        { "Binding", "ShowStatus", "BankAndBags" }, { "Binding", "ShowStatus", "GuildBank" },
        { "Binding", "ShowStatus", "Merchant" },
        { "Binding", "ShowBoA" }, { "Binding", "ShowBoE" }, { "Binding", "ShowWuE" },
        { "Icon", "ShowLearnable", "BankAndBags" }, { "Icon", "ShowLearnable", "GuildBank" },
        { "Icon", "ShowLearnable", "Merchant" },
        { "Icon", "ShowUpgrades", "BankAndBags" }, { "Icon", "ShowUpgradeIcon" },
        { "Icon", "ShowSellable", "BankAndBags" }, { "Icon", "ShowSellable", "GuildBank" },
        { "Icon", "ShowQuestItems" }, { "Icon", "ShowAuctionValue" },
    }
    for _, key in ipairs({ "BankAndBags", "GuildBank", "Merchant", "BlackMarket", "CustomerOrders", "Loot", "GroupLoot",
        "QuestLog", "Mail", "TradeSkill", "DressingRoom", "EncounterJournal" }) do
        SETTINGS[#SETTINGS + 1] = { "Icon", "ShowLearnableByOther", key }
    end

    local function Set(config, path, value)
        local at = config
        for index = 1, #path - 1 do
            at = at[path[index]]
        end
        at[path[#path]] = value
    end

    -- A display answer as text: each rule with what it says, in the rules' order.
    local function Describe(info)
        if type(info) ~= "table" then
            return tostring(info)
        end
        local keys = {}
        for key in pairs(info) do
            keys[#keys + 1] = tostring(key)
        end
        table.sort(keys)
        local parts = {}
        for _, key in ipairs(keys) do
            local entry = info[key]
            if type(entry) == "table" then
                entry = entry.shouldShow
            end
            parts[#parts + 1] = key .. "=" .. tostring(entry)
        end
        return table.concat(parts, " ")
    end

    ----------------------------------------------------------------------------------------
    -- The answers as the windows' functions gave them
    ----------------------------------------------------------------------------------------

    local function ByOther(key)
        return function(config) return config.Icon.ShowLearnableByOther[key] ~= false end
    end
    local function Quest(config) return config.Icon.ShowQuestItems end
    -- The world quest lists of four addons, Angrier World Quests and Sorted showed the quest
    -- icon whatever its setting said (questIcon = true). They follow the setting now, as the
    -- world map and the mission table always did.
    local FOLLOW_THE_QUEST_SETTING = { "VenturePlan", "WorldQuestsList", "WorldQuestTracker", "ZygorGuidesViewer",
        "AngrierWorldQuests", "Sorted" }
    local WORLD_QUESTS = { bindingStatus = true, ownIcon = true, otherIcon = true, questIcon = Quest,
        oldExpansionIcon = false, sellableIcon = false }
    local QUEST_LOG = { bindingStatus = true, ownIcon = true, otherIcon = ByOther("QuestLog"), questIcon = Quest,
        oldExpansionIcon = true, sellableIcon = false }
    local GUILD_BANK = {
        bindingStatus = function(config) return config.Binding.ShowStatus.GuildBank end,
        ownIcon = function(config) return config.Icon.ShowLearnable.GuildBank end,
        otherIcon = function(config) return config.Icon.ShowLearnableByOther.GuildBank end,
        sellableIcon = function(config) return config.Icon.ShowSellable.GuildBank end,
    }
    local FUNCTIONS = {
        BlackMarket = { bindingStatus = true, ownIcon = true, otherIcon = ByOther("BlackMarket"), questIcon = Quest,
            oldExpansionIcon = false, sellableIcon = false },
        CustomerOrders = { bindingStatus = false, ownIcon = true, otherIcon = ByOther("CustomerOrders"), questIcon = false,
            oldExpansionIcon = false, sellableIcon = false },
        DressingRoom = { bindingStatus = false, ownIcon = true, otherIcon = ByOther("DressingRoom"),
            oldExpansionIcon = true, sellableIcon = false },
        EncounterJournal = { bindingStatus = true, ownIcon = true, otherIcon = ByOther("EncounterJournal"), questIcon = Quest,
            oldExpansionIcon = true, sellableIcon = false },
        GroupLoot = { otherIcon = ByOther("GroupLoot") },
        GuildBank = GUILD_BANK,
        ItemConversion = { bindingStatus = false, ownIcon = true, otherIcon = true, questIcon = false,
            oldExpansionIcon = false, sellableIcon = false },
        Loot = { bindingStatus = true, ownIcon = true, otherIcon = ByOther("Loot"), questIcon = Quest,
            oldExpansionIcon = true, sellableIcon = false },
        Mail = { bindingStatus = true, ownIcon = true, otherIcon = ByOther("Mail"), questIcon = Quest,
            oldExpansionIcon = false, sellableIcon = false },
        Mission = { bindingStatus = true, ownIcon = true, otherIcon = true, questIcon = Quest,
            oldExpansionIcon = false, sellableIcon = false },
        QuestLog = QUEST_LOG,
        TradeSkill = { bindingStatus = true, ownIcon = true, otherIcon = ByOther("TradeSkill"), questIcon = false,
            oldExpansionIcon = false, sellableIcon = false },
        WeeklyRewards = { bindingStatus = true, ownIcon = true, otherIcon = true, questIcon = Quest,
            oldExpansionIcon = false, sellableIcon = false },
        WorldMap = { bindingStatus = true, ownIcon = true, otherIcon = true, questIcon = Quest,
            oldExpansionIcon = false, sellableIcon = false },
        AngrierWorldQuests = { bindingStatus = true, ownIcon = true, otherIcon = true, questIcon = Quest,
            oldExpansionIcon = true, sellableIcon = false },
        Baganator = {},
        Narcissus = { bindingStatus = false, ownIcon = true, otherIcon = true, oldExpansionIcon = true,
            sellableIcon = false },
        Sorted = { bindingStatus = false, ownIcon = true, otherIcon = true, questIcon = Quest, oldExpansionIcon = true,
            sellableIcon = true },
        VenturePlan = WORLD_QUESTS,
        WorldQuestsList = WORLD_QUESTS,
        WorldQuestTracker = WORLD_QUESTS,
        ZygorGuidesViewer = WORLD_QUESTS,
        -- Two that draw another window's content and passed its function on.
        BetterBagsGuildBank = GUILD_BANK,
        DialogueUI = QUEST_LOG,
    }

    -- GetDisplayInfoInternal as it was, with the window's function standing as a table.
    local function Reference(config, L, answers, inBags, bindingStatus, ownArrow)
        local elsewhere = not inBags
        local info = {
            upgradeIcon = (config.Icon.ShowUpgradeIcon ~= false) and (elsewhere or config.Icon.ShowUpgrades.BankAndBags),
            bindingStatus = elsewhere or config.Binding.ShowStatus.BankAndBags,
            ownIcon = elsewhere or config.Icon.ShowLearnable.BankAndBags,
            otherIcon = elsewhere or config.Icon.ShowLearnableByOther.BankAndBags,
            questIcon = config.Icon.ShowQuestItems,
            oldExpansionIcon = true,
            sellableIcon = elsewhere or config.Icon.ShowSellable.BankAndBags,
            auctionIcon = inBags and config.Icon.ShowAuctionValue == true,
        }
        for rule, answer in pairs(answers) do
            if type(answer) == "function" then
                info[rule] = answer(config)
            else
                info[rule] = answer
            end
        end
        if ownArrow then
            info.upgradeIcon, info.levelGain = false, false
        end
        if (not config.Binding.ShowBoA and bindingStatus == L["BoA"]) or
            (not config.Binding.ShowBoE and bindingStatus == L["BoE"]) or
            (not config.Binding.ShowWuE and bindingStatus == L["WuE"]) then
            info.bindingStatus = false
        end
        return info
    end

    ----------------------------------------------------------------------------------------

    local function Start(flavor)
        local game = H.StockGame(TOON, {})
        local world = {}
        game:Set("C_AddOns.GetAddOnInfo", function(name) return name, name, "", world.otherAddons or false end)
        game:Set("C_AddOns.IsAddOnLoaded", function(name) return world.otherAddons or false end)
        game:Set("C_AddOns.GetAddOnMetadata", function() return "1" end)
        local client = H.Client.New({ flavor = flavor, provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))

        -- Windows of the scenario's own.
        local function Window(name, mixin)
            function mixin:GetName() return name end
            function mixin:Init() end
            client.env.CaerdonWardrobe:RegisterFeature(mixin)
        end
        Window("Holds", {})
        Window("Offers", { displayRules = { bindingStatus = true, ownIcon = false, otherIcon = "Mail", sellableIcon = "GuildBank",
            questIcon = false, oldExpansionIcon = false } })
        Window("BySettings", { displayRules = { bindingStatus = "Merchant", ownIcon = "Merchant", otherIcon = "Merchant",
            sellableIcon = "BankAndBags" } })
        Window("Beyond", { displayRules = { levelGain = false, statusIcon = false, upgradeIcon = false, auctionIcon = true } })
        local ByDraw = { displayRules = { ownIcon = true, otherIcon = true } }
        function ByDraw:GetDisplayInfo(button, item, feature, locationInfo)
            world.asked = { button = button, item = item, feature = feature, locationInfo = locationInfo }
            if locationInfo and locationInfo.held then
                return { ownIcon = { shouldShow = false }, levelGain = { shouldShow = false } }
            end
        end
        Window("ByDraw", ByDraw)
        Window("Misnamed", { displayRules = { questIcon = "Mail" } })

        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(10)

        world.client, world.env, world.core, world.namespace = client, client.env, client.env.CaerdonWardrobe, namespace
        return world
    end

    local inBags = false
    local item = {}
    function item:HasItemLocationBankOrBags() return inBags end
    function item:GetCaerdonItemType() return "Equipment" end

    local ownArrow = false
    local button = {}
    function button:DoesButtonHaveMarker(kind) return ownArrow and kind == "upgrade" end

    for _, flavor in ipairs({ "forever", "retail" }) do
        local label = flavor .. ": "
        local world = Start(flavor)
        local core, client, namespace = world.core, world.client, world.namespace
        local config = world.env.CaerdonWardrobeConfig
        local defaults = namespace:GetDefaultConfig()
        local L = namespace.L
        Equal(#client.errors, 0, label .. "the addon loads with no error (" .. tostring(client.errors[1]) .. ")")

        local function Shown(feature, locationInfo, bindingStatus)
            return feature:GetDisplayInfoInternal(button, item, feature, locationInfo, {}, "own", bindingStatus)
        end
        local function AllSettings(value)
            for _, path in ipairs(SETTINGS) do
                Set(config, path, value)
            end
        end

        ------------------------------------------------------------------------------------
        -- 1. The shipped declarations
        ------------------------------------------------------------------------------------

        do
            -- Every file that speaks of display rules, loaded as the game loads it. Loading
            -- registers the feature; its Init, which hooks the window, is not run.
            world.otherAddons = true
            local files = {}
            local function Scan(relative)
                for _, file in ipairs(H.ListDir(H.addonDir .. "/" .. relative)) do
                    local text = file:match("%.lua$") and H.ReadFile(H.addonDir .. "/" .. relative .. "/" .. file)
                    if text and (text:find("displayRules", 1, true) or text:find("GetDisplayInfo", 1, true) or
                        text:find("GetDisplayRules", 1, true)) then
                        files[#files + 1] = relative .. "/" .. file
                    end
                end
            end
            Scan("features")
            for _, folder in ipairs(H.ListDir(H.addonDir .. "/external", true)) do
                Scan("external/" .. folder)
            end
            -- And one whose function answered with an empty table, and which now says nothing.
            files[#files + 1] = "external/Baganator/Core.Baganator.lua"
            Check(#files >= 30, label .. "the files that speak of display rules were found (" .. #files .. ")")
            for _, file in ipairs(files) do
                local before = #client.errors
                local ok, problem = H.Guards.pcall(function()
                    client:LoadAddonFile("CaerdonWardrobe", H.addonDir, file, namespace)
                end)
                Check(ok and #client.errors == before, label .. file .. " loads (" ..
                    tostring(problem or client.errors[#client.errors]) .. ")")
            end

            local declaring, named = 0, 0
            for name, feature in pairs(core:GetRegisteredFeatures()) do
                local rules = feature:GetDisplayRules()
                -- (The scenario's own window with a mistake in it is section 2's.)
                if rules ~= nil and name ~= "Misnamed" then
                    declaring = declaring + 1
                    Equal(type(rules), "table", label .. name .. ": the declaration is a table")
                    for rule, shown in pairs(type(rules) == "table" and rules or {}) do
                        named = named + 1
                        Check(RULES[rule], label .. name .. ": " .. tostring(rule) .. " is a rule a draw reads")
                        if type(shown) == "string" then
                            local path = WINDOW_SETTINGS[rule]
                            Check(path ~= nil, label .. name .. ": " .. tostring(rule) .. " has settings by window")
                            local settings = path and defaults[path[1]][path[2]]
                            Equal(type(settings and settings[shown]), "boolean", label .. name .. ": " .. tostring(rule) ..
                                " names the setting " .. shown .. ", which the default settings have")
                        else
                            Equal(type(shown), "boolean", label .. name .. ": " .. tostring(rule) .. " is true, false or a setting")
                        end
                    end
                end
            end
            -- The scenario's own four, and the shipped ones.
            Check(declaring >= 4 + 23, label .. "the windows that declare were read (" .. declaring .. ", " .. named .. " rules)")
        end

        ------------------------------------------------------------------------------------
        -- 2. The declaration itself
        ------------------------------------------------------------------------------------

        do
            local holds, offers, bySettings = core:GetFeature("Holds"), core:GetFeature("Offers"), core:GetFeature("BySettings")
            local beyond, byDraw, misnamed = core:GetFeature("Beyond"), core:GetFeature("ByDraw"), core:GetFeature("Misnamed")
            AllSettings(true)

            -- A window that declares nothing: the core's own answers.
            Equal(holds:GetDisplayRules(), nil, label .. "a window that declares nothing has no rules")
            inBags = false
            Equal(Describe(Shown(holds)), "auctionIcon=false bindingStatus=true oldExpansionIcon=true otherIcon=true " ..
                "ownIcon=true questIcon=true sellableIcon=true upgradeIcon=true",
                label .. "nothing declared, an item elsewhere: everything shown but the auction icon")
            AllSettings(false)
            Equal(Describe(Shown(holds)), "auctionIcon=false bindingStatus=true oldExpansionIcon=true otherIcon=true " ..
                "ownIcon=true questIcon=false sellableIcon=true upgradeIcon=false",
                label .. "nothing declared, an item elsewhere: the bags' settings do not reach it")
            inBags = true
            Equal(Describe(Shown(holds)), "auctionIcon=false bindingStatus=false oldExpansionIcon=true otherIcon=false " ..
                "ownIcon=false questIcon=false sellableIcon=false upgradeIcon=false",
                label .. "nothing declared, an item in the bags: by the bags' settings")
            AllSettings(true)
            Equal(Describe(Shown(holds)), "auctionIcon=true bindingStatus=true oldExpansionIcon=true otherIcon=true " ..
                "ownIcon=true questIcon=true sellableIcon=true upgradeIcon=true",
                label .. "nothing declared, an item in the bags: all of it with the settings on")

            -- True and false stand whatever the settings say, also for an item in the bags.
            AllSettings(false)
            Set(config, { "Icon", "ShowLearnableByOther", "Mail" }, true)
            Equal(Describe(Shown(offers)), "auctionIcon=false bindingStatus=true oldExpansionIcon=false otherIcon=true " ..
                "ownIcon=false questIcon=false sellableIcon=false upgradeIcon=false",
                label .. "declared: true and false stand, a setting named is read, the rest is the core's")
            -- A setting is read at each draw.
            Set(config, { "Icon", "ShowLearnableByOther", "Mail" }, false)
            Set(config, { "Icon", "ShowSellable", "GuildBank" }, true)
            local shown = Shown(offers)
            Equal(shown.otherIcon.shouldShow, false, label .. "declared: the setting switched off is off at the next draw")
            Equal(shown.sellableIcon.shouldShow, true, label .. "declared: and another switched on is on")
            -- Each rule that has settings by window reads its own.
            for rule, path in pairs(WINDOW_SETTINGS) do
                local key = rule == "sellableIcon" and "BankAndBags" or "Merchant"
                AllSettings(false)
                Equal(Shown(bySettings)[rule].shouldShow, false, label .. "declared: " .. rule .. " is off with its setting off")
                Set(config, { path[1], path[2], key }, true)
                local answer = Shown(bySettings)
                Equal(answer[rule].shouldShow, true, label .. "declared: " .. rule .. " goes by its window's setting")
                local on = 0
                for other in pairs(WINDOW_SETTINGS) do
                    on = on + (answer[other].shouldShow and 1 or 0)
                end
                Equal(on, 1, label .. "declared: " .. rule .. "'s setting switches nothing else on")
            end
            -- The declaration is read and not written to.
            Equal(Describe(offers:GetDisplayRules()), "bindingStatus=true oldExpansionIcon=false otherIcon=Mail ownIcon=false " ..
                "questIcon=false sellableIcon=GuildBank", label .. "declared: the declaration is as it was after the draws")
            Check(Shown(offers) ~= Shown(offers), label .. "declared: each draw has an answer of its own")

            -- Rules beyond the eight every window has.
            AllSettings(true)
            inBags = false
            local more = Shown(beyond)
            Equal(more.levelGain and more.levelGain.shouldShow, false, label .. "declared: the level gain can be switched off")
            Equal(more.statusIcon and more.statusIcon.shouldShow, false, label .. "declared: and the status icon")
            Equal(more.upgradeIcon.shouldShow, false, label .. "declared: and the upgrade icon")
            Equal(more.auctionIcon.shouldShow, true, label .. "declared: the auction icon can be had outside the bags")
            Equal(Shown(holds).levelGain, nil, label .. "a window that names neither has no word on the level gain")

            -- A function beside the declaration: what it answers is laid over it.
            local place = { held = false }
            local answer = Shown(byDraw, place)
            Equal(answer.ownIcon.shouldShow, true, label .. "by the draw: nothing answered leaves the declaration")
            Check(world.asked and world.asked.button == button and world.asked.item == item and world.asked.feature == byDraw and
                world.asked.locationInfo == place, label .. "by the draw: the function is handed the draw")
            place.held = true
            answer = Shown(byDraw, place)
            Equal(answer.ownIcon.shouldShow, false, label .. "by the draw: what the function answers comes over the declaration")
            Equal(answer.otherIcon.shouldShow, true, label .. "by the draw: what it leaves out stays as declared")
            Equal(answer.levelGain and answer.levelGain.shouldShow, false, label .. "by the draw: and it can name a rule more")

            -- The binding settings come last, over a declared true.
            inBags = false
            for _, kind in ipairs({ "BoA", "BoE", "WuE" }) do
                AllSettings(true)
                Equal(Shown(offers, nil, L[kind]).bindingStatus.shouldShow, true, label .. kind .. ": shown with its setting on")
                Set(config, { "Binding", "Show" .. kind }, false)
                Equal(Shown(offers, nil, L[kind]).bindingStatus.shouldShow, false, label .. kind .. ": its setting off hides it in a window that declares the text")
                Equal(Shown(offers, nil, "Soulbound").bindingStatus.shouldShow, true, label .. kind .. ": and no other text")
            end
            AllSettings(true)

            -- A setting named for a rule that has none by window is a mistake in the file.
            local ok, problem = H.Guards.pcall(function() return Shown(misnamed) end)
            Check(not ok and tostring(problem):find("Misnamed", 1, true) and tostring(problem):find("questIcon", 1, true),
                label .. "misnamed: a setting for a rule without one raises, naming the window and the rule (" ..
                tostring(problem) .. ")")
        end

        ------------------------------------------------------------------------------------
        -- 3. The shipped windows, against the answers their functions gave
        ------------------------------------------------------------------------------------

        do
            local BINDINGS = { "none", L["BoA"], L["BoE"], L["WuE"], "Soulbound" }
            local compared, differing, first = 0, 0, nil
            local function Walk(name, feature, answers, state)
                for _, bags in ipairs({ false, true }) do
                    inBags = bags
                    for _, binding in ipairs(BINDINGS) do
                        local bindingStatus = binding ~= "none" and binding or nil
                        for _, arrow in ipairs({ false, true }) do
                            ownArrow = arrow
                            local want = Describe(Reference(config, L, answers, bags, bindingStatus,
                                arrow and name == "DialogueUI"))
                            local got = Describe(Shown(feature, {}, bindingStatus))
                            compared = compared + 1
                            if got ~= want then
                                differing = differing + 1
                                first = first or string.format("%s, %s, in the bags %s, text %s: %s, by its function %s", name, state,
                                    tostring(bags), binding, got, want)
                            end
                        end
                    end
                end
                inBags, ownArrow = false, false
            end
            local windows = 0
            for name, answers in pairs(FUNCTIONS) do
                local feature = core:GetFeature(name)
                Check(feature ~= nil, label .. name .. ": the file registers its feature")
                if feature then
                    windows = windows + 1
                    for _, base in ipairs({ true, false }) do
                        AllSettings(base)
                        Walk(name, feature, answers, "every setting " .. tostring(base))
                        for _, path in ipairs(SETTINGS) do
                            Set(config, path, not base)
                            Walk(name, feature, answers, "every setting " .. tostring(base) .. " but " .. table.concat(path, "."))
                            Set(config, path, base)
                        end
                    end
                end
            end
            for _, path in ipairs(SETTINGS) do
                local value = defaults
                for _, key in ipairs(path) do
                    value = value[key]
                end
                Set(config, path, value)
            end
            Equal(windows, 24, label .. "every window of the list was compared")
            Check(compared > 20000, label .. "each setting alone was compared (" .. compared .. ")")
            Equal(differing, 0, label .. "the declared rules give what the functions gave (first: " .. tostring(first) .. ")")

            -- The quest icon follows its setting in every window that shows it.
            for _, name in ipairs(FOLLOW_THE_QUEST_SETTING) do
                local feature = core:GetFeature(name)
                if feature then
                    for _, bags in ipairs({ false, true }) do
                        inBags = bags
                        Set(config, { "Icon", "ShowQuestItems" }, false)
                        Equal(Shown(feature, {}).questIcon.shouldShow, false, label .. name .. ": no quest icon with quest items switched off")
                        Set(config, { "Icon", "ShowQuestItems" }, true)
                        Equal(Shown(feature, {}).questIcon.shouldShow, true, label .. name .. ": and the quest icon with them on")
                    end
                    inBags = false
                    local rules = feature:GetDisplayRules()
                    Equal(rules and rules.questIcon, nil, label .. name .. ": the declaration leaves the quest icon to the core")
                end
            end
            -- Nothing shipped shows it whatever the setting says; three windows never show it.
            local always, never = {}, {}
            for name, feature in pairs(core:GetRegisteredFeatures()) do
                local rules = feature:GetDisplayRules()
                if rules and rules.questIcon == true then
                    always[#always + 1] = name
                elseif rules and rules.questIcon == false and name ~= "Offers" then
                    never[#never + 1] = name
                end
            end
            table.sort(never)
            Equal(table.concat(always, " "), "", label .. "no window declares the quest icon as always on")
            Equal(table.concat(never, " "), "CustomerOrders ItemConversion TradeSkill", label .. "the windows that never show the quest icon")

            -- A window that draws another's content has that window's declaration itself, and
            -- its answer for a draw.
            local guildBank, bagsGuildBank = core:GetFeature("GuildBank"), core:GetFeature("BetterBagsGuildBank")
            local questLog, dialogue = core:GetFeature("QuestLog"), core:GetFeature("DialogueUI")
            local vendor, bagsVendor = core:GetFeature("Merchant"), core:GetFeature("BetterBagsVendor")
            if guildBank and bagsGuildBank and questLog and dialogue and vendor and bagsVendor then
                Check(bagsGuildBank:GetDisplayRules() == guildBank:GetDisplayRules() and guildBank:GetDisplayRules() ~= nil,
                    label .. "BetterBags' guild bank answers with the guild bank's rules themselves")
                Check(dialogue:GetDisplayRules() == questLog:GetDisplayRules() and questLog:GetDisplayRules() ~= nil,
                    label .. "Dialogue UI answers with the quest rewards' rules themselves")
                ownArrow = false
                Equal(dialogue:GetDisplayInfo(button, item), nil, label .. "Dialogue UI: with no arrow of its own it adds nothing")
                ownArrow = true
                Equal(Describe(dialogue:GetDisplayInfo(button, item)), "levelGain=false upgradeIcon=false",
                    label .. "Dialogue UI: with its own arrow, no arrow and no level gain of the addon's")
                ownArrow = false

                -- The vendor's answer depends on what is carried, and its window in BetterBags
                -- gives the same; a declaration the vendor gained would reach it too.
                local carried = false
                function vendor:IsItemInBags() return carried end
                for _, held in ipairs({ false, true }) do
                    carried = held
                    Equal(Describe(Shown(bagsVendor, {})), Describe(Shown(vendor, {})),
                        label .. "BetterBags' vendor answers as the vendor does, an item carried: " .. tostring(held))
                    Equal(Shown(bagsVendor, {}).ownIcon.shouldShow, not held,
                        label .. "BetterBags' vendor: the star only on what is not carried (" .. tostring(held) .. ")")
                end
                vendor.displayRules = { questIcon = false }
                Check(bagsVendor:GetDisplayRules() == vendor.displayRules, label .. "BetterBags' vendor answers with the vendor's rules themselves")
                Equal(Shown(bagsVendor, {}).questIcon.shouldShow, false, label .. "BetterBags' vendor: and they are applied there")
                vendor.displayRules = nil
                Equal(Shown(bagsVendor, {}).questIcon.shouldShow, true, label .. "BetterBags' vendor: without one the quest icon is by its setting")
            else
                Check(false, label .. "the windows that draw another's content are registered")
            end
        end

        ------------------------------------------------------------------------------------
        -- 4. Through ProcessItem
        ------------------------------------------------------------------------------------

        do
            local handed
            function core:SetItemButtonStatus(_, _, _, _, _, _, _, _, displayInfo)
                handed = displayInfo
            end
            function core:SetItemButtonMogStatusFilter() end
            function core:SetItemButtonBindType() end
            local function Drawn(feature)
                local frame = client:NewFrame("Button")
                frame:SetSize(37, 37)
                local piece = {}
                function piece:GetCaerdonItemType() return "Equipment" end
                function piece:HasItemLocationBankOrBags() return false end
                function piece:GetCaerdonStatus() return true, "own", nil, {}, { isTransmog = true }, nil end
                core:SetupCaerdonButton(frame, piece, feature, nil, {})
                handed = nil
                core:ProcessItem(frame, piece, feature, nil, {})
                return handed
            end
            local offered = Drawn(core:GetFeature("Offers"))
            Equal(offered and offered.ownIcon.shouldShow, false, label .. "draw: the drawing is handed the declared rules")
            Equal(offered and offered.oldExpansionIcon.shouldShow, false, label .. "draw: each of them")
            local held = Drawn(core:GetFeature("Holds"))
            Equal(held and held.ownIcon.shouldShow, true, label .. "draw: and the core's own where the window declares nothing")
            Equal(#client.errors, 0, label .. "draw: no error (" .. tostring(client.errors[1]) .. ")")
        end
    end
end
