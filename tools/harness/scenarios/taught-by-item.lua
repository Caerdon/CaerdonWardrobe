-- A star for what teaches the toon a spell: a class's spell book, a rune (CaerdonItem.lua,
-- LearnableByTeachingLine and the Recipe and Consumable branches of GetCaerdonStatus).
--
-- Such an item is no profession's recipe: it asks for no skill, and no list has what it
-- teaches. A WoW Forever client's tooltips (the test addon's walk, 1.60.1.71037, a hunter)
-- have what the rule goes by: the item's own teaching line with the spell, and below it the
-- item's own class line ("Classes: Hunter", with whether the toon meets it) and level line.
-- A made item's lines stand above the teaching line (a recipe for a potion only warriors and
-- druids drink has the potion's "Classes: Warrior, Druid" there), and are not the item's.
--
-- The lines here are made after those tooltips; the items and spells are invented. A learned
-- book or rune has not been seen in a client: "Already known" on one is the client's line as
-- a recipe item has it.
--
-- Real code: the addon, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 33 }

    local LEARN_LINE, REQUIREMENT_LINE = 38, 43
    local CONSUMABLE, RECIPE = 0, 9
    local RED = { r = 1, g = 0.125, b = 0.125 }

    local function Teaches(spell)
        return { text = "Use: Teaches you something.", type = LEARN_LINE, spellID = spell }
    end
    local function Class(text, met)
        local line = { text = "Classes: " .. text, type = REQUIREMENT_LINE, kind = "RaceClass", usable = met }
        if not met then line.r, line.g, line.b = RED.r, RED.g, RED.b end
        return line
    end
    local function Level(level, met)
        local line = { text = "Requires Level " .. level, type = REQUIREMENT_LINE, kind = "Level", usable = met }
        if not met then line.r, line.g, line.b = RED.r, RED.g, RED.b end
        return line
    end
    local function Skill(text, met)
        local line = { text = text, type = REQUIREMENT_LINE, kind = "Skill", usable = met }
        if not met then line.r, line.g, line.b = RED.r, RED.g, RED.b end
        return line
    end
    local KNOWN_LINE = { text = "Already known", type = REQUIREMENT_LINE, kind = "NotAlreadyKnown", usable = false,
        r = RED.r, g = RED.g, b = RED.b }

    local function Book(name, tooltip)
        return { name = name, quality = 2, level = 30, minLevel = 0, type = "Recipe", subType = "Book", stack = 1,
            price = 500, classID = RECIPE, subClassID = 0, bindType = 0, tooltip = tooltip }
    end
    local function Rune(name, tooltip)
        return { name = name, quality = 2, level = 30, minLevel = 0, type = "Consumable", subType = "Other", stack = 1,
            price = 500, classID = CONSUMABLE, subClassID = 8, bindType = 0, tooltip = tooltip }
    end

    local OWN_BOOK, HIGH_BOOK, MAGE_BOOK, KNOWN_BOOK, SILENT_KNOWN_BOOK = 993001, 993002, 993003, 993004, 993005
    local OWN_RUNE, MAGE_RUNE, MAKER_BOOK, POTION_RECIPE, PLAIN_BOOK, PLAIN_POTION = 993006, 993007, 993008, 993009, 993010, 993011
    local SECOND_COPY_SPELL = 72001
    local SILENT_SPELL = 72005

    local function Start(flavor)
        local items = {
            -- A book of the toon's class that it can read now, and one for a level it has not.
            [OWN_BOOK] = Book("Guide: Test Shot", { Teaches(SECOND_COPY_SPELL), Class("Hunter", true), Level(20, true) }),
            [HIGH_BOOK] = Book("Guide: Test Shot IX", { Teaches(72002), Class("Hunter", true), Level(60, false) }),
            -- Another class's.
            [MAGE_BOOK] = Book("Tome of Test Ward", { Teaches(72003), Class("Mage", false), Level(22, true) }),
            -- Learned: by the tooltip's word, and by the client's word on the spell alone.
            [KNOWN_BOOK] = Book("Guide: Old Shot", { Teaches(72004), Class("Hunter", true), KNOWN_LINE }),
            [SILENT_KNOWN_BOOK] = Book("Guide: Quiet Shot", { Teaches(SILENT_SPELL), Class("Hunter", true) }),
            -- Runes: the toon's class, and another's.
            [OWN_RUNE] = Rune("Rune of Tests", { Teaches(72006), Class("Hunter", true) }),
            [MAGE_RUNE] = Rune("Spell Notes: Tests", { Teaches(72007), Class("Mage", false) }),
            -- A book of the toon's class whose made item is another class's: the class line
            -- above the teaching line is the made item's.
            [MAKER_BOOK] = Book("Guide: Test Trap", { Class("Mage", false), Level(50, false), Teaches(72008), Class("Hunter", true) }),
            -- A profession's recipe the toon has no profession for stays what it was, whoever
            -- may drink what it makes.
            [POTION_RECIPE] = Book("Recipe: Test Rage Potion",
                { Class("Warrior, Druid", false), Teaches(72009), Skill("Requires Alchemy (60)", false) }),
            -- Nothing taught at all.
            [PLAIN_BOOK] = Book("Empty Tome", {}),
            [PLAIN_POTION] = Rune("Test Potion", {}),
        }
        items[POTION_RECIPE].subType = "Alchemy"

        local game = H.StockGame(TOON, items)
        local known = { [SILENT_SPELL] = true }
        local asked = {}
        game:Set("C_SpellBook.IsSpellKnown", function(spell)
            asked[spell] = (asked[spell] or 0) + 1
            return known[spell] == true
        end)
        game:Set("C_TradeSkillUI.GetRecipeInfo", function() return nil end)

        local client = H.Client.New({ flavor = flavor, provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)
        Equal(#client.errors, 0, flavor .. ": no error reached the error handler at the start (" .. tostring(client.errors[1]) .. ")")

        local kinds = client.env.Enum.TooltipDataUsageRequirementType
        for _, item in pairs(items) do
            for _, line in ipairs(item.tooltip) do
                if line.kind then
                    line.requirementType = kinds[line.kind]
                    Check(line.requirementType ~= nil, flavor .. ": the client has the requirement type " .. line.kind)
                end
            end
        end
        return client, known, asked
    end

    local function Status(client, itemID)
        local item = client.env.CaerdonItem:CreateFromItemID(itemID)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        client:TickUntil(function() return loaded end, 10)
        local ready, status
        client:TickUntil(function()
            ready, status = item:GetCaerdonStatus()
            return ready
        end, 10)
        return status
    end

    for _, flavor in ipairs({ "forever", "retail" }) do
        local client, known, asked = Start(flavor)
        Equal(client.env.Enum.TooltipDataLineType.ItemSpellTriggerLearn, LEARN_LINE, flavor .. ": the teaching line's type is the client's")

        Equal(Status(client, OWN_BOOK), "own", flavor .. ": a book of the toon's class that it has not learned has the star")
        Equal(Status(client, HIGH_BOOK), "lowSkill", flavor .. ": one for a level it has not reached is learnable later")
        Check(Status(client, MAGE_BOOK) ~= "own" and Status(client, MAGE_BOOK) ~= "lowSkill",
            flavor .. ": another class's book has no star (" .. tostring(Status(client, MAGE_BOOK)) .. ")")
        Check(Status(client, KNOWN_BOOK) ~= "own", flavor .. ": a book the tooltip calls known has none (" .. tostring(Status(client, KNOWN_BOOK)) .. ")")
        Check(Status(client, SILENT_KNOWN_BOOK) ~= "own",
            flavor .. ": nor one whose spell the client calls known where the tooltip says nothing (" .. tostring(Status(client, SILENT_KNOWN_BOOK)) .. ")")
        Equal(Status(client, OWN_RUNE), "own", flavor .. ": a rune of the toon's class has the star")
        Check(Status(client, MAGE_RUNE) ~= "own" and Status(client, MAGE_RUNE) ~= "lowSkill",
            flavor .. ": another class's rune has none (" .. tostring(Status(client, MAGE_RUNE)) .. ")")
        Equal(Status(client, MAKER_BOOK), "own",
            flavor .. ": a class line and a level line above the teaching line are the made item's, not the book's")
        Equal(Status(client, POTION_RECIPE), "collected",
            flavor .. ": a profession's recipe is not judged by this rule, whatever its made item's class line says")
        Equal(Status(client, PLAIN_BOOK), "collected", flavor .. ": a book that teaches nothing is as before")
        Check(Status(client, PLAIN_POTION) ~= "own", flavor .. ": and so is a potion (" .. tostring(Status(client, PLAIN_POTION)) .. ")")

        -- Learned while a second copy lies in the bags: the event for that spell judges again,
        -- the event for any other spell does nothing.
        local core = client.env.CaerdonWardrobe
        local refreshes = {}
        local refresh = core.RefreshItems
        core.RefreshItems = function(self, reason, detail, ...)
            refreshes[#refreshes + 1] = tostring(reason) .. " " .. tostring(detail)
            return refresh(self, reason, detail, ...)
        end
        Check(client.env.CaerdonItem:IsTaughtSpellJudged(SECOND_COPY_SPELL), flavor .. ": the book's spell is one a kept verdict rests on")
        client:Fire("LEARNED_SPELL_IN_SKILL_LINE", 99999, 1, false)
        client:Tick(5)
        Equal(#refreshes, 0, flavor .. ": a spell no verdict rests on refreshes nothing")
        known[SECOND_COPY_SPELL] = true
        client:Fire("LEARNED_SPELL_IN_SKILL_LINE", SECOND_COPY_SPELL, 1, false)
        client:Tick(5)
        Equal(refreshes[1], "spell learned " .. SECOND_COPY_SPELL, flavor .. ": learning the book's spell refreshes, and says why")
        Equal(#refreshes, 1, flavor .. ": once")
        Check(Status(client, OWN_BOOK) ~= "own", flavor .. ": and the second copy has lost its star (" .. tostring(Status(client, OWN_BOOK)) .. ")")
        Equal(Status(client, OWN_RUNE), "own", flavor .. ": the rune keeps its own")
        core.RefreshItems = refresh

        Check((asked[72009] or 0) == 0, flavor .. ": the client is not asked about a profession recipe's spell")
        Equal(#client.errors, 0, flavor .. ": no error reached the error handler (" .. tostring(client.errors[1]) .. ")")
    end
end
