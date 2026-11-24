-- A profession the toon has dropped is none it has (types/RecipeMixin.lua,
-- ResetMissingProfessionLevel).
--
-- A WoW Forever hunter that had left Herbalism at rank 44 saw the grey gear, "learnable
-- later", on Blueprint: Greenhouse 273106 ("Requires Herbalism (140)"). Its saved ranks had
-- the profession's own at 44 beside its one line's at 0: a rank is saved only ever upwards,
-- the reset for a dropped profession took its lines alone, and the highest of the two is the
-- rank that is read. The saved ranks here are that toon's in shape; the blueprint's lines are
-- its export's (the made item's skill line above the teaching line, the item's own below).
--
-- Real code: the addon, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 36 }

    local LEARN_LINE, USE_LINE, REQUIREMENT_LINE, NESTED = 38, 44, 43, 19
    local RED = { r = 1, g = 0.125, b = 0.125 }
    local function Requires(text)
        return { text = text, type = REQUIREMENT_LINE, usable = false, r = RED.r, g = RED.g, b = RED.b }
    end
    local BLUEPRINT, PATTERN = 994001, 994002

    local function Start(flavor, professions)
        local items = {
            [BLUEPRINT] = { name = "Blueprint: Test House", quality = 2, level = 25, minLevel = 0, type = "Recipe", subType = "Book",
                stack = 1, price = 375, classID = 9, subClassID = 0, bindType = 0, tooltip = {
                    { text = "", type = NESTED },
                    { text = "Use: Places a Test House.", type = USE_LINE, spellID = 73001 },
                    Requires("Requires Herbalism (140)"),
                    { text = "Use: Teaches you how to place a Test House at a campsite.", type = LEARN_LINE, spellID = 73002 },
                    { text = "Simple Wood (2)" },
                    Requires("Requires Herbalism (140)"),
                } },
            [PATTERN] = { name = "Pattern: Test Shirt", quality = 2, level = 25, minLevel = 0, type = "Recipe", subType = "Tailoring",
                stack = 1, price = 375, classID = 9, subClassID = 2, bindType = 0, tooltip = {
                    { text = "Use: Teaches you how to sew a Test Shirt.", type = LEARN_LINE, spellID = 73003 },
                    Requires("Requires Tailoring (165)"),
                } },
        }
        local saved = { CaerdonProfessionData = { Farrealm = { Zzyxa = {
            -- Dropped at 44: the profession's own rank stayed, its line's was taken to 0.
            Herbalism = { skillLineID = 182, skillName = "Herbalism", skillLevel = 44,
                childSkillLines = { Herbalism = { skillLineID = 2944, skillName = "Herbalism", skillLevel = 0 } } },
            Tailoring = { skillLineID = 197, skillName = "Tailoring", skillLevel = 128,
                childSkillLines = { Tailoring = { skillLineID = 2948, skillName = "Tailoring", skillLevel = 128 } } },
        } } } }

        local game = H.StockGame(TOON, items)
        game:Set("GetProfessions", function()
            local slots = {}
            for index in ipairs(professions) do
                slots[index] = index
            end
            return unpack(slots)
        end)
        game:Set("GetProfessionInfo", function(index)
            return professions[index], nil, 128, 225
        end)
        game:Set("C_TradeSkillUI.GetRecipeInfo", function() return nil end)
        game:Set("C_SpellBook.IsSpellKnown", function() return false end)

        local client = H.Client.New({ flavor = flavor, provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
        for name, value in pairs(saved) do
            rawset(client.env, name, H.DeepCopy(value))
        end
        local skill = client.env.Enum.TooltipDataUsageRequirementType.Skill
        for _, item in pairs(items) do
            for _, line in ipairs(item.tooltip) do
                if line.type == REQUIREMENT_LINE then
                    line.requirementType = skill
                end
            end
        end
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)
        Equal(#client.errors, 0, flavor .. ": no error reached the error handler at the start (" .. tostring(client.errors[1]) .. ")")
        return client
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
        -- The toon has Tailoring and no Herbalism any more.
        local client = Start(flavor, { "Tailoring" })
        local ranks = client.env.CaerdonProfessionData.Farrealm.Zzyxa
        Equal(ranks.Herbalism.skillLevel, 0, flavor .. ": the dropped profession's own rank is taken to 0 with its line's")
        Equal(client.env.CaerdonRecipe:GetSavedRank("Herbalism"), 0, flavor .. ": and so is the rank that is read")
        Equal(ranks.Tailoring.skillLevel, 128, flavor .. ": a profession the toon has keeps its rank")
        Equal(Status(client, BLUEPRINT), "collected", flavor .. ": an item that asks for the dropped profession is none to learn later")
        Equal(Status(client, PATTERN), "lowSkill", flavor .. ": one that asks for more of a profession the toon has still is")
        Equal(#client.errors, 0, flavor .. ": no error reached the error handler (" .. tostring(client.errors[1]) .. ")")

        -- With no profession named by the client, nothing says the toon has none.
        client = Start(flavor, {})
        ranks = client.env.CaerdonProfessionData.Farrealm.Zzyxa
        Equal(ranks.Herbalism.skillLevel, 44, flavor .. ": while the client names no profession, a saved rank is left alone")
        Equal(ranks.Tailoring.skillLevel, 128, flavor .. ": every one of them")
    end
end
