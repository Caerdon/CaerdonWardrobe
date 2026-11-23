-- The text the item code reads, in every language both clients come in.
--
-- Some facts are on a tooltip as a line of text and nowhere else. Where the client writes the
-- line from one of its own format strings, the addon reads it back through that string
-- (CaerdonFormatPattern.lua): the skill and rank an item asks for, a bag's size, the PVP
-- floor, the durability, WoW Forever's "Equip:" stats. Here each of those is written with the
-- real string of each of the eleven locales of each client (the listings mirror's
-- GlobalStrings) and read back by the addon's code, in a client of that locale.
--
-- Two things have no format string behind them, and are tested with text from outside:
--   * A food's restore line is a spell's description. The lines below are Wowhead's Classic
--     tooltips of Tough Hunk of Bread (4540) and Refreshing Spring Water (159), fetched
--     2026-11-21 (nether.wowhead.com/classic/tooltip/item/<id>?locale=<n>), with one change:
--     Wowhead writes the amount as 61.2 and 151.2, a client as 61 and 151 (the enUS lines are
--     a Forever client's own, from the fixtures). Its "Use:" words are not always the
--     client's, which the food code does not read. Italian is English there, as in the
--     Forever client's strings.
--   * A recipe item's name. The names below are the same fetch's, of Recipe: Elixir of Minor
--     Agility (2553). Whether the space before the French colon is a no-break space could
--     not be told from the fetch, so both are tried.
-- Nobody has seen any of this in a client that is not enUS.
--
-- Real code: the addon's item side, Blizzard's base files from the mirror. The items are
-- hand-made around the lines.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local LOCALES = { "enUS", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
    local FLAVORS = { "forever", "retail" }

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 33 }

    -- locale -> { the food's line, the drink's line }
    local RESTORE_LINES = {
        enUS = { "Use: Restores 234 health over 21 sec.  Must remain seated while eating.",
            "Use: Restores 1,344 mana over 27 sec.  Must remain seated while drinking.", 234, 1344 },
        deDE = { "Benutzen: Stellt im Verlauf von 18 Sek. 61 Punkt(e) Gesundheit wieder her. Ihr müsst beim Essen sitzen bleiben.",
            "Benutzen: Stellt im Verlauf von 18 Sek. 151 Punkt(e) Mana wieder her. Ihr müsst beim Trinken sitzen bleiben." },
        esES = { "Uso: Restaura 61 p. de salud durante 18 s. Debes permanecer sentado mientras comes.",
            "Uso: Restaura 151 p. de maná durante 18 s. Debes permanecer sentado mientras bebes." },
        frFR = { "Utilise: Rend 61 points de vie en 18 sec. Vous devez rester assis pendant que vous mangez.",
            "Utilise: Rend 151 points de mana en 18 sec. Vous devez rester assis pendant que vous buvez." },
        itIT = { "Usa: Restores 61 health over 18 sec.  Must remain seated while eating.",
            "Usa: Restores 151 mana over 18 sec.  Must remain seated while drinking.", forever = true },
        koKR = { "사용 효과: 18초에 걸쳐 총 61의 생명력이 회복됩니다. 음식을 먹으려면 앉아 있어야 합니다.",
            "사용 효과: 18초에 걸쳐 총 151의 마나가 회복됩니다. 음료를 마시려면 앉아 있어야 합니다." },
        ptBR = { "Uso: Restaura 61 de vida ao longo de 18 s. É preciso ficar sentado enquanto come.",
            "Uso: Recupera 151 de mana ao longo de 18 s. É preciso ficar sentado enquanto bebe." },
        ruRU = { "Использование: Восполняет 61 ед. здоровья за 18 сек. Действие прерывается, если встать с места.",
            "Использование: Восполнение 151 ед. маны за 18 сек. Действие эффекта прерывается, если персонаж встает с места." },
        zhCN = { "使用:  在18秒内恢复总计61点生命值，进食时必须保持坐姿。",
            "使用:  在18秒内恢复总计151点法力值，喝水时必须保持坐姿。" },
        zhTW = { "使用:  在18秒內恢復總計61點生命力，進食時必須保持坐姿。",
            "使用:  在18秒內恢復總計151點法力，飲用時必須保持坐姿。" },
    }
    RESTORE_LINES.esMX = RESTORE_LINES.esES

    -- A recipe item's name and the recipe it names.
    local RECIPE_NAMES = {
        { "Recipe: Elixir of Minor Agility", "Elixir of Minor Agility" },
        { "Rezept: Elixier der schwachen Beweglichkeit", "Elixier der schwachen Beweglichkeit" },
        { "Receta: elixir de agilidad menor", "elixir de agilidad menor" },
        { "Recette : Elixir d'Agilité mineure", "Elixir d'Agilité mineure" },
        { "Recette\194\160: Elixir d'Agilité mineure", "Elixir d'Agilité mineure" },
        { "Receita: Elixir de Agilidade Menor", "Elixir de Agilidade Menor" },
        { "Рецепт: слабый эликсир ловкости", "слабый эликсир ловкости" },
        { "조제법: 최하급 민첩의 비약", "최하급 민첩의 비약" },
        { "配方：初级敏捷药剂", "初级敏捷药剂" },
        { "配方：初級敏捷藥劑", "初級敏捷藥劑" },
        -- The English words the code had a list of, and one it did not have.
        { "Schematic: Rocket Boots", "Rocket Boots" },
        { "Design: Pendant", "Pendant" },
        { "Plans: Thorium Helm", "Thorium Helm" },
        { "Pattern: Swiftstrike Shoulders", "Swiftstrike Shoulders" },
        { "Technique: Glyph", "Glyph" },
        { "Formula: Enchant Bracer", "Enchant Bracer" },
        { "Manual: Heavy Silk Bandage", "Heavy Silk Bandage" },
        -- Only the first colon parts the name; a name without one is the recipe's.
        { "Recipe: Elixir: The Sequel", "Elixir: The Sequel" },
        { "Expert Cookbook", "Expert Cookbook" },
        { "Odd:", "Odd:" },
    }

    -- A text as the client may hold it: with its grammar escapes, or with one of their forms.
    local function Renderings(text)
        local list = { text }
        if text:find("|4[^;|]*;") then
            list[#list + 1] = text:gsub("|4([^:;|]*):[^;|]*;", "%1")
            list[#list + 1] = text:gsub("|4[^;|]*:([^:;|]*);", "%1")
        end
        if text:find("|1[^;|]*;[^;|]*;") then
            list[#list + 1] = text:gsub("|1([^;|]*);[^;|]*;", "%1")
            list[#list + 1] = text:gsub("|1[^;|]*;([^;|]*);", "%1")
        end
        return list
    end

    local RECIPE, BAG, FOOD, DRINK, CHARM = 980001, 980010, 980020, 980021, 980030
    local NOTES = {} -- what the strings are like, printed with CAERDON_LOCALE_NOTES set
    local SKILL = "First Aid"

    -- The clients the test addon's contract text.readBack is run in as well: the plain
    -- format, arguments by position, a plural escape, full-width brackets.
    local WITH_CONTRACT = { ["forever enUS"] = true, ["forever deDE"] = true, ["retail ruRU"] = true, ["retail zhTW"] = true }
    local GEAR = 980040

    local function Run(flavor, locale)
        local where = flavor .. " " .. locale
        local ITEMS = {
            [RECIPE] = { name = "Pattern: Test Cloak", quality = 1, level = 20, minLevel = 0, type = "Recipe",
                subType = "Tailoring", stack = 1, equipLoc = "", price = 100, classID = 9, subClassID = 2, tooltip = {} },
            [FOOD] = { name = "Test Bread", quality = 1, level = 15, minLevel = 5, type = "Consumable",
                subType = "Food & Drink", stack = 20, equipLoc = "", price = 6, classID = 0, subClassID = 5, tooltip = {} },
            [DRINK] = { name = "Test Water", quality = 1, level = 15, minLevel = 5, type = "Consumable",
                subType = "Food & Drink", stack = 20, equipLoc = "", price = 6, classID = 0, subClassID = 5, tooltip = {} },
            [CHARM] = { name = "Test Charm", quality = 2, level = 31, minLevel = 26, type = "Armor",
                subType = "Miscellaneous", stack = 1, equipLoc = "INVTYPE_HOLDABLE", price = 537, classID = 4,
                subClassID = 0, bindType = 2, tooltip = {} },
        }
        for index = 0, 4 do
            ITEMS[BAG + index] = { name = "Test Bag " .. index, quality = 1, level = 15, minLevel = 0, type = "Container",
                subType = "Bag", stack = 1, equipLoc = "INVTYPE_BAG", price = 100, classID = 1, subClassID = 0, tooltip = {} }
        end

        local game = H.StockGame(TOON, ITEMS)
        game:Set("GetLocale", function() return locale end)
        -- The backpack, empty until the contract is run. Set before the client reads any of it:
        -- a function the client has read once is the one it keeps.
        local bag, durabilityLine = {}, nil
        local hyperlink = game.names["C_TooltipInfo.GetHyperlink"]
        game:Set("C_Container.GetContainerNumSlots", function(index) return index == 0 and #bag or 0 end)
        game:Set("C_Container.GetContainerItemID", function(index, slot) return index == 0 and bag[slot] or nil end)
        game:Set("C_Container.GetContainerItemLink", function(index, slot)
            return index == 0 and bag[slot] and game.Link(bag[slot]) or nil
        end)
        game:Set("C_Container.GetContainerItemDurability", function(index, slot)
            if index == 0 and bag[slot] == GEAR then
                return 30, 35
            end
        end)
        game:Set("C_TooltipInfo.GetBagItem", function(index, slot)
            local data = index == 0 and bag[slot] and hyperlink(game.Link(bag[slot])) or nil
            if data and bag[slot] == GEAR and durabilityLine then
                data.lines[#data.lines + 1] = durabilityLine
            end
            return data
        end)
        local client = H.Client.New({ flavor = flavor, locale = locale, provider = game })
        game.client = client
        if not client.listing.hasStrings then
            Check(false, where .. ": the mirror has no GlobalStrings/" .. locale .. ".lua (run update.sh in the Builds folder)")
            return
        end
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)
        local env = client.env
        Equal(#client.errors, 0, where .. ": the addon starts without an error")
        for _, message in ipairs(client.errors) do
            print("        error: " .. tostring(message))
        end
        client.errors = {}
        local strings = client.listing.strings

        local function Item(itemID)
            local item = env.CaerdonItem:CreateFromItemID(itemID)
            local loaded = false
            item:ContinueOnItemLoad(function() loaded = true end)
            client:TickUntil(function() return loaded end, 10)
            return item
        end

        -- The skill and rank of a requirement line.
        local skillFormat = strings.ITEM_MIN_SKILL
        if Check(type(skillFormat) == "string", where .. ": the client has ITEM_MIN_SKILL") or type(skillFormat) == "string" then
            local line = skillFormat:format(SKILL, 125)
            ITEMS[RECIPE].tooltip = { { text = line, type = 43,
                requirementType = env.Enum.TooltipDataUsageRequirementType.Skill } }
            local item = Item(RECIPE)
            local requirement = item:GetSkillRequirement()
            Equal(requirement and requirement.skillName, SKILL, where .. ": the skill of \"" .. line .. "\"")
            Equal(requirement and requirement.rank, 125, where .. ": the rank of \"" .. line .. "\"")
            -- The status's own scan reads the same line.
            item:GetTooltipData()
            Equal(table.concat(namespace.Refresh:GetSkillRequirementsNoted(), ", "), SKILL,
                where .. ": the tooltip scan names the skill")
        end

        -- A bag's size, with the line as the format has it and with each form of its escapes.
        local slotsFormat = strings.CONTAINER_SLOTS
        if type(slotsFormat) == "string" then
            for index, line in ipairs(Renderings(slotsFormat:format(16, "Bag"))) do
                local itemID = BAG + index - 1
                ITEMS[itemID].tooltip = { { text = line } }
                local info = env.CaerdonBagSlots:GetItemInfo(itemID, game.Link(itemID))
                Equal(info and info.size, 16, where .. ": the size of \"" .. line .. "\"")
                Equal(info and info.sizeMatchedBy, "format", where .. ": read by the format, \"" .. line .. "\"")
            end
        else
            Check(false, where .. ": the client has CONTAINER_SLOTS")
        end

        -- The restore line of a food and of a drink.
        local restore = RESTORE_LINES[locale]
        if restore and (not restore.forever or flavor == "forever") then
            ITEMS[FOOD].tooltip = { { text = restore[1], type = 44 } }
            ITEMS[DRINK].tooltip = { { text = restore[2], type = 44 } }
            local food = env.CaerdonFoodDrink:Classify(FOOD, game.Link(FOOD))
            local drink = env.CaerdonFoodDrink:Classify(DRINK, game.Link(DRINK))
            Equal(food and food.kind, "food", where .. ": the bread restores health")
            Equal(food and food.amount, restore[3] or 61, where .. ": the bread's amount")
            Equal(food and food.isBuff, false, where .. ": the bread is plain food")
            Equal(drink and drink.kind, "drink", where .. ": the water restores mana")
            Equal(drink and drink.amount, restore[4] or 151, where .. ": the water's amount")
            Equal(drink and drink.isBuff, false, where .. ": the water is a plain drink")
        end

        -- WoW Forever's "Equip:" stats: each of the client's stat strings, written with numbers,
        -- is a stat and no effect.
        -- A stat string need not start with the client's "Equip:" word (French and Brazilian
        -- Forever clients: none of theirs does), and one of the client's own may be malformed
        -- ("+%1 $d", three Brazilian ones), which Lua cannot write a line from: counted, and
        -- left out, since what a client prints for it is not known.
        -- One Brazilian stat string has no word before it at all ("Aumenta a cura ..."): its
        -- line is no "Equip:" line, which keeps a piece as little as a stat does.
        local equipWord = strings.ITEM_SPELL_TRIGGER_ONEQUIP
        local stats, otherWords, malformed, noEquipLine = 0, {}, {}, 0
        for _, name in ipairs(env.CaerdonItem:GetEquipStatStringNames()) do
            local format = strings[name]
            if type(format) == "string" then
                stats = stats + 1
                local ok, line = H.Guards.pcall(string.format, format, 12, 34)
                if not ok then
                    malformed[#malformed + 1] = name
                else
                    if line:sub(1, #equipWord) ~= equipWord then
                        otherWords[#otherWords + 1] = name
                    end
                    ITEMS[CHARM].tooltip = { { text = line, type = 0, r = 0, g = 1, b = 0 } }
                    local tooltipData = Item(CHARM):GetTooltipData()
                    Check(tooltipData.hasEquipEffectBeyondStats == false,
                        ("%s: %s is no effect, \"%s\""):format(where, name, line))
                    if not tooltipData.hasEquipEffect then
                        noEquipLine = noEquipLine + 1
                    end
                end
            end
        end
        if flavor == "forever" then
            Check(stats > 0, where .. ": the client has stat strings")
            Equal(noEquipLine, locale == "ptBR" and 1 or 0, where .. ": stat strings whose line is no \"Equip:\" line")
            NOTES[#NOTES + 1] = ("%s: %d stat strings, %d that do not start with \"%s\", %d malformed"):format(where, stats,
                #otherWords, tostring(equipWord), #malformed)
        end
        -- A line that is none of them stays an effect, under the client's word and under the
        -- word its stat strings start with.
        local words = { equipWord }
        if otherWords[1] then
            local format = strings[otherWords[1]]
            words[#words + 1] = format:match("^([^%%]-:)")
        end
        for _, word in ipairs(words) do
            ITEMS[CHARM].tooltip = { { text = word .. " something no stat string says 15%.", type = 0, r = 0, g = 1, b = 0 } }
            local tooltipData = Item(CHARM):GetTooltipData()
            Check(tooltipData.hasEquipEffect == true and tooltipData.hasEquipEffectBeyondStats == true,
                ("%s: a line under \"%s\" that is no stat string is an effect"):format(where, word))
        end
        -- A line that starts with neither is no "Equip:" line.
        ITEMS[CHARM].tooltip = { { text = "Chance on hit: something 15%.", type = 0, r = 0, g = 1, b = 0 } }
        Equal(Item(CHARM):GetTooltipData().hasEquipEffect, false, where .. ": a line under another word is no \"Equip:\" line")

        -- An item set's lines (CaerdonSetBonuses): the set's line with the pieces worn, a bonus
        -- the toon has, and one it does not have with the pieces it begins at, as the format has
        -- it and with each form of its escapes. The lines stand as the recorded tooltips have
        -- them: the pieces under the set's line, a blank, the bonuses.
        local setFormat, hasFormat, grayFormat = strings.ITEM_SET_NAME, strings.ITEM_SET_BONUS, strings.ITEM_SET_BONUS_GRAY
        Check(type(setFormat) == "string" and type(hasFormat) == "string" and type(grayFormat) == "string",
            where .. ": the client has ITEM_SET_NAME, ITEM_SET_BONUS and ITEM_SET_BONUS_GRAY")
        if type(setFormat) == "string" and type(hasFormat) == "string" and type(grayFormat) == "string" then
            local function SetLines(grayLine, legacy)
                local lines = {
                    { type = 0, leftText = "Test Helm" },
                    { type = 0, leftText = strings.ITEM_MIN_SKILL:format(SKILL, 125) },
                    { type = 1, leftText = " " },
                    { type = 0, leftText = setFormat:format("Test Set (Heroic)", 3, 8) },
                    { type = 0, leftText = "  Test Helm" },
                    { type = 42, leftText = "  Test Belt (Heroic)" },
                    { type = 1, leftText = " " },
                }
                if legacy then
                    lines[#lines + 1] = { type = 0, leftText = strings.ITEM_SET_LEGACY_INACTIVE_BONUS }
                end
                lines[#lines + 1] = { type = 0, leftText = hasFormat:format("Does a thing: 5% (more).") }
                lines[#lines + 1] = { type = 42, leftText = grayLine }
                lines[#lines + 1] = { type = 1, leftText = " " }
                lines[#lines + 1] = { type = 0, leftText = "Sell Price: 9" }
                return { lines = lines }
            end
            for _, grayLine in ipairs(Renderings(grayFormat:format(4, "+10 Armor: (and more)."))) do
                local reading = env.CaerdonSetBonuses:Read(SetLines(grayLine))
                local told = where .. ": \"" .. grayLine .. "\" under \"" .. setFormat:format("Test Set (Heroic)", 3, 8) .. "\""
                Equal(reading and reading.name, "Test Set (Heroic)", told .. ": the set's name")
                Equal(reading and reading.worn, 3, told .. ": the pieces worn")
                Equal(reading and reading.total, 8, told .. ": the pieces in all")
                Equal(reading and #reading.bonuses, 2, told .. ": two bonuses")
                Equal(reading and reading.bonuses[1] and reading.bonuses[1].active, true, told .. ": the first is one the toon has")
                Equal(reading and reading.bonuses[1] and reading.bonuses[1].text, "Does a thing: 5% (more).", told .. ": with its text")
                Equal(reading and reading.bonuses[2] and reading.bonuses[2].needs, 4, told .. ": the second begins at four pieces")
                Equal(reading and reading.bonuses[2] and reading.bonuses[2].text, "+10 Armor: (and more).", told .. ": with its text")
                Equal(reading and reading.legacy, nil, told .. ": no legacy set")
            end
            if type(strings.ITEM_SET_LEGACY_INACTIVE_BONUS) == "string" then
                local legacy = env.CaerdonSetBonuses:Read(SetLines(grayFormat:format(4, "+10 Armor."), true))
                Equal(legacy and legacy.legacy, true, where .. ": the client's line for a set whose bonuses no longer work is known")
                Equal(legacy and #legacy.bonuses, 2, where .. ": and its bonuses are read past it")
            end
        end

        -- The builder itself, where the code that uses it is not reached by one call.
        local FormatPattern = namespace.FormatPattern
        if FormatPattern then
            local floorFormat = strings.PVP_ITEM_LEVEL_TOOLTIP
            if Check(type(floorFormat) == "string", where .. ": the client has PVP_ITEM_LEVEL_TOOLTIP") or floorFormat then
                local floor = FormatPattern.Compile(floorFormat, { anywhere = true })
                for _, line in ipairs(Renderings(floorFormat:format(606))) do
                    Equal(floor:Match(line), "606", where .. ": the floor of \"" .. line .. "\"")
                end
                Equal(floor:Match(strings.ITEM_MIN_SKILL:format(SKILL, 125)), nil, where .. ": a skill line has no floor")
            end
            local durabilityFormat = strings.DURABILITY_TEMPLATE
            if Check(type(durabilityFormat) == "string", where .. ": the client has DURABILITY_TEMPLATE") or durabilityFormat then
                local durability = FormatPattern.Compile(durabilityFormat, { capture = false })
                local line = durabilityFormat:format(30, 35)
                Check(durability:Match(line) ~= nil, where .. ": \"" .. line .. "\" is the durability line")
                Check(durability:Match("  " .. line .. " ") ~= nil, where .. ": with spaces at its ends too")
                Check(durability:Match(line .. " and more") == nil, where .. ": not with more text behind it")
                Check(durability:Match(strings.ITEM_MIN_SKILL:format(SKILL, 125)) == nil,
                    where .. ": a skill line is no durability line")
            end
            local skill = FormatPattern.Compile(skillFormat, { anywhere = true })
            local name, rank = skill:Match(skillFormat:format("Riding (Fast)", 75))
            Equal(name, "Riding (Fast)", where .. ": a skill's name with brackets of its own")
            Equal(rank, "75", where .. ": and its rank")
        end

        -- The test addon's contract: the same asked of what a toon carries.
        if WITH_CONTRACT[where] then
            ITEMS[GEAR] = { name = "Test Bracers", quality = 2, level = 31, minLevel = 26, type = "Armor", subType = "Mail",
                stack = 1, equipLoc = "INVTYPE_WRIST", price = 537, classID = 4, subClassID = 3, bindType = 2, tooltip = {} }
            ITEMS[RECIPE].tooltip = { { text = skillFormat:format(SKILL, 125), type = 43,
                requirementType = env.Enum.TooltipDataUsageRequirementType.Skill } }
            durabilityLine = { type = 0, leftText = strings.DURABILITY_TEMPLATE:format(30, 35) }
            bag = { RECIPE, BAG, FOOD, DRINK, GEAR }

            local wanted = { ["Core.lua"] = true, ["Runner.lua"] = true, ["Contracts.lua"] = true, ["Plan.lua"] = true }
            local T = H.LoadAddon(client, "CaerdonWardrobe_Tests", H.addonDir .. "/CaerdonWardrobe_Tests",
                function(relative) return not wanted[relative] end)
            client:Fire("ADDON_LOADED", "CaerdonWardrobe_Tests")
            client:Fire("PLAYER_LOGIN")
            local ID = "text.readBack"
            local function Contract()
                T.RunTests({ match = ID, force = true })
                Check(client:TickUntil(function() return not T.IsBusy() end, 120), where .. ", contract: the job ends")
                return (T.db.contracts[T.GetClient().build] or {})[ID] or {}
            end

            local result = Contract()
            Equal(result.status, "pass", where .. ", contract: it passes on the bags (" .. tostring(result.message) .. ")")
            local detail = result.detail or {}
            Equal(detail.items, 5, where .. ", contract: five items")
            Equal(detail.skillLines, 1, where .. ", contract: one skill line")
            Equal(detail.bags, 1, where .. ", contract: one bag")
            Equal(detail.durabilityLines, 1, where .. ", contract: one durability line")
            Equal(detail.foods, 2, where .. ", contract: two foods")
            Equal(detail.foodsNotRead, restore and (not restore.forever or flavor == "forever") and 0 or 2,
                where .. ", contract: both read")
            Equal(detail.locale, locale, where .. ", contract: the client's language is kept")
            Check(tostring((detail.skillExamples or {})[1]):find(SKILL, 1, true) ~= nil, where .. ", contract: the skill line is kept")
            result = Contract()
            Equal((result.detail or {}).skillLines, 2, where .. ", contract: a second run adds to the first")
            Equal(#((result.detail or {}).skillExamples or {}), 1, where .. ", contract: and keeps an example once")

            -- A toon that carries nothing of the kind answers nothing.
            bag = { FOOD, DRINK }
            Equal(Contract().status, "info", where .. ", contract: foods alone are no pass")
            bag = { RECIPE, BAG, FOOD, DRINK, GEAR }

            -- Faults, one at a time: a client that writes a line another way than its string.
            local function Fault(label, plant, undo, expected)
                plant()
                local faulty = Contract()
                Equal(faulty.status, "fail", where .. ", fault, " .. label .. ": the contract fails")
                Check(tostring(faulty.message):find(expected, 1, true) ~= nil,
                    where .. ", fault, " .. label .. ": and says why (" .. tostring(faulty.message) .. ")")
                undo()
            end
            local skillLine = ITEMS[RECIPE].tooltip[1]
            local skillText = skillLine.text
            Fault("a skill line that is not the format's", function() skillLine.text = "Wants " .. SKILL .. " at 125" end,
                function() skillLine.text = skillText end, "was not read")
            Fault("a durability line that is not the format's", function() durabilityLine.leftText = "Wear 30 of 35" end,
                function() durabilityLine.leftText = strings.DURABILITY_TEMPLATE:format(30, 35) end, "has no line")
            -- A bag's size is kept by the module for good, so the odd bag is another item.
            ITEMS[BAG + 4].tooltip = { { text = "Bag, 12 pockets" } }
            Fault("a bag whose size line is not the format's", function() bag[2] = BAG + 4 end, function() bag[2] = BAG end,
                "read by subtype name, not by CONTAINER_SLOTS")
            Equal(Contract().status, "pass", where .. ", contract: and passes again without the faults")
        end

        Equal(#client.errors, 0, where .. ": no error reached the error handler")
        for _, message in ipairs(client.errors) do
            print("        error: " .. tostring(message))
        end
        return env, namespace
    end

    local env, namespace
    for _, flavor in ipairs(FLAVORS) do
        for _, locale in ipairs(LOCALES) do
            local madeEnv, madeNamespace = Run(flavor, locale)
            env, namespace = env or madeEnv, namespace or madeNamespace
        end
    end
    if not env then
        return
    end
    if os.getenv("CAERDON_LOCALE_NOTES") then
        for _, note in ipairs(NOTES) do
            print("        " .. note)
        end
    end

    -- A recipe item's name, which is the same code in every client.
    if env.CaerdonRecipe.GetRecipeNameFromItemName then
        for _, case in ipairs(RECIPE_NAMES) do
            Equal(env.CaerdonRecipe:GetRecipeNameFromItemName(case[1]), case[2], "recipe name of \"" .. case[1] .. "\"")
        end
        Equal(env.CaerdonRecipe:GetRecipeNameFromItemName(nil), "", "recipe name of an item with no name")
    end

    -- The name an item gave against the profession list's. Each pair is Wowhead's name of a
    -- recipe item and of the spell it teaches (the list's name), not a client's: Classic's
    -- items 2553, 6342, 6325 and 2406 with spells 3230, 7443, 7751 and 2158, and retail's
    -- Russian spell 3230. Spanish and Russian write the item's in lower case; where the two
    -- are worded differently nothing finds the recipe, and that is said here, not mended.
    if env.CaerdonRecipe.FindByName then
        local Recipe = env.CaerdonRecipe
        local FOUND = {
            { "Recipe: Elixir of Minor Agility", "Elixir of Minor Agility" },
            { "Receta: elixir de agilidad menor", "Elixir de agilidad menor" },
            { "Fórmula: encantar pechera: maná menor", "Encantar pechera: maná menor" },
            { "Рецепт: слабый эликсир ловкости", "Слабый эликсир ловкости" },
            { "Recette : Elixir d'Agilité mineure", "Elixir d'Agilité mineure" },
        }
        for _, case in ipairs(FOUND) do
            local names = { [case[2]] = 7 }
            Equal(Recipe:FindByName(names, Recipe:GetRecipeNameFromItemName(case[1])), 7, "\"" .. case[1] .. "\" finds \"" .. case[2] .. "\"")
        end
        local NOT_FOUND = {
            { "Receta: pececito luminoso", "Pececito brillante" },
            { "Patrón: botas de cuero refinado", "Botas finas de cuero" },
            { "Рецепт: слабый эликсир ловкости", "Эликсир ловкости II ступени" },
            { "Рецепт: блестящая рыбка", "Рецепт блестящей рыбки" },
            { "Формула чар для нагрудника: мана I", "Чары для нагрудника: мана I" },
        }
        for _, case in ipairs(NOT_FOUND) do
            local names = { [case[2]] = 7 }
            Equal(Recipe:FindByName(names, Recipe:GetRecipeNameFromItemName(case[1])), nil,
                "\"" .. case[1] .. "\" does not find \"" .. case[2] .. "\" (another wording)")
        end
        -- The exact name comes first, and a capital is tried for nothing else.
        Equal(Recipe:FindByName({ ["elixir"] = 1, ["Elixir"] = 2 }, "elixir"), 1, "the name as it is comes before its capital")
        Equal(Recipe:FindByName({ ["elixir"] = 1 }, "Elixir"), nil, "a capital is not made small")
        Equal(Recipe:FindByName({ ["Elixir"] = false }, "Elixir"), false, "a false is an answer")
        Equal(Recipe:FindByName(nil, "Elixir"), nil, "no table, no answer")
        Equal(Recipe:FindByName({}, nil), nil, "no name, no answer")
        local CAPITALS = {
            { "elixir", "Elixir" }, { "Elixir", nil }, { "", nil }, { "9 lives", nil },
            { "élixir", "Élixir" }, { "ñu", "Ñu" }, { "þ", "Þ" }, { "÷", nil }, { "ÿ", nil }, { "É", nil },
            { "а", "А" }, { "п", "П" }, { "р", "Р" }, { "я", "Я" }, { "ё", "Ё" }, { "эликсир", "Эликсир" },
            { "Э", nil }, { "配方", nil }, { "\195", nil },
        }
        for _, case in ipairs(CAPITALS) do
            Equal(Recipe:CapitalizeFirstLetter(case[1]), case[2], "the capital of \"" .. case[1] .. "\"")
        end
        Equal(Recipe:CapitalizeFirstLetter(nil), nil, "the capital of no name")
    end

    -- The builder on formats no client has today.
    local FormatPattern = namespace.FormatPattern
    if FormatPattern then
        local reversed = FormatPattern.Compile("(%2$d) %1$s")
        local name, rank = reversed:Match("(125) Cooking")
        Equal(name, "Cooking", "arguments by position: the first argument, which is second in the text")
        Equal(rank, "125", "arguments by position: the second argument")
        local numbers = FormatPattern.Compile("%2$s de %1$d casillas", { capture = "numbers" })
        Equal(numbers:Match("Bolsa de 6 casillas"), "6", "numbers only: the number, though the text comes first")
        Equal(FormatPattern.Compile("100%% of %d"):Match("100% of 7"), "7", "a percent sign is text")
        Equal(FormatPattern.Compile("%d%%"):Match("15%"), "15", "a percent sign behind an argument")
        Equal(FormatPattern.Compile("+%d [%s] (a.b) x*y?")
            :Match("+5 [Mail] (a.b) x*y?"), "5", "Lua's own pattern characters are text")
        Equal(FormatPattern.Compile("a.b"):Match("axb"), nil, "a dot is a dot")
        Equal(FormatPattern.Compile("%.1f%% faster"):Match("1.5% faster"), "1.5", "a number with a fraction")
        Equal(FormatPattern.Compile("%d |4point:points; left"):Match("1 point left"), "1", "a plural escape, its first form")
        Equal(FormatPattern.Compile("%d |4point:points; left"):Match("3 points left"), "3", "its second form")
        Equal(FormatPattern.Compile("%d |4point:points; left"):Match("3 |4point:points; left"), "3", "the escape itself")
        Equal(FormatPattern.Compile("%d |4point:points; left"):Match("3 points right"), nil, "the text behind it still counts")
        Equal(FormatPattern.Compile("Durability %d / %d"):Match("Durability 30 / 35 more"), nil, "the whole line by default")
        Equal(FormatPattern.Compile("no arguments"):Match(" no arguments "), "no arguments", "a format without arguments")
        Equal(FormatPattern.Compile(nil), nil, "no format, no matcher")
        Equal(FormatPattern.Compile("%s"):Match(12), nil, "a line that is no text matches nothing")
    end
end
