-- A use that has to be aimed at an enemy does not keep a learned piece (CaerdonItem.lua,
-- HasHostileUse and the equipment branch of GetCaerdonStatus).
--
-- Any use spell used to keep a learned piece from "sellable", so that nothing fun or special
-- is marked for sale. A Forever hunter's Torch of Holy Flame 7344 ("Use: Decrease the armor
-- of target by 50 for 1 min.") was kept that way. The client says whether an item's use needs
-- an enemy (C_Item.IsHarmfulItem); such a use is a combat effect and no longer keeps a piece,
-- except on a trinket, on a piece that asks for a skill and on one no vendor pays for.
--
-- The game is hand-made: what the client answers for a real item is not in it. The torch's
-- line is the text a Forever client gave (build 1.60.1); that the client calls its use
-- harmful has not been seen.
--
-- Real code: the addon's item side, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 33 }

    local ON_USE, ON_EQUIP, REQUIREMENT = 44, 45, 43
    local GREEN = { r = 0, g = 1, b = 0 }
    local function Line(text, lineType)
        return { text = text, type = lineType, r = GREEN.r, g = GREEN.g, b = GREEN.b }
    end
    local TORCH_LINE = Line("Use: Decrease the armor of target by 50 for 1 min. (1 Min Cooldown)", ON_USE)
    local skillLine = { text = "Requires Engineering (125)", type = REQUIREMENT }

    local nextSource = 7500
    local function Piece(name, slot, more)
        nextSource = nextSource + 1
        local item = { name = name, quality = 2, level = 33, minLevel = 0, type = "Armor", subType = "Miscellaneous",
            stack = 1, equipLoc = slot, price = 5000, classID = 4, subClassID = 0, bindType = 1,
            tooltip = { { text = "+5 Spirit" } } }
        if slot ~= "INVTYPE_TRINKET" then
            item.appearance = { appearanceID = nextSource - 2000, sourceID = nextSource, collected = true }
        end
        for key, value in pairs(more or {}) do
            item[key] = value
        end
        return item
    end
    local HOSTILE = { name = "Holy Flame", id = 9176, hostile = true }

    local ITEMS = {
        -- The torch: a stat and a use aimed at an enemy.
        [980001] = Piece("Torch", "INVTYPE_HOLDABLE", { spell = HOSTILE, tooltip = { { text = "+5 Spirit" }, TORCH_LINE } }),
        -- A use cast on a friend, and one that is aimed at nothing.
        [980002] = Piece("Mending Orb", "INVTYPE_HOLDABLE", { spell = { name = "Mend", id = 90002, friendly = true },
            tooltip = { Line("Use: Heals a friend for 50.", ON_USE) } }),
        [980003] = Piece("Odd Lantern", "INVTYPE_HOLDABLE", { spell = { name = "Glow", id = 90003 },
            tooltip = { Line("Use: You glow for 10 min.", ON_USE) } }),
        -- The torch's use on a piece that asks for a skill, and on one no vendor pays for.
        [980004] = Piece("Gadget", "INVTYPE_HOLDABLE", { spell = HOSTILE, tooltip = { TORCH_LINE, skillLine } }),
        [980005] = Piece("Quest Tool", "INVTYPE_HOLDABLE", { spell = HOSTILE, price = 0, tooltip = { TORCH_LINE } }),
        -- With an equip line that is a stat, and with one that is an effect.
        [980006] = Piece("Battle Torch", "INVTYPE_HOLDABLE", { spell = HOSTILE,
            tooltip = { Line("Equip: +12 Attack Power."), TORCH_LINE } }),
        [980007] = Piece("Swift Torch", "INVTYPE_HOLDABLE", { spell = HOSTILE,
            tooltip = { Line("Equip: Increases ranged attack speed by 10%.", ON_EQUIP), TORCH_LINE } }),
        -- No use at all.
        [980008] = Piece("Plain Orb", "INVTYPE_HOLDABLE"),
        -- Trinkets: the torch's use, and a ring with it for comparison. Both tie what is worn.
        [980010] = Piece("Battle Charm", "INVTYPE_TRINKET", { spell = HOSTILE, tooltip = { TORCH_LINE } }),
        [980011] = Piece("Battle Band", "INVTYPE_FINGER", { spell = HOSTILE, tooltip = { TORCH_LINE } }),
        -- Worn: a two-handed sword of a lower level with nothing in the off-hand (the hunter of
        -- the export), so an off-hand piece is no upgrade, no tie and not outdone; and
        -- trinkets and rings of the candidates' level that do something else.
        [980900] = { name = "Worn Greatsword", quality = 2, level = 25, minLevel = 20, type = "Weapon",
            subType = "Two-Handed Swords", stack = 1, equipLoc = "INVTYPE_2HWEAPON", price = 900, classID = 2,
            subClassID = 8, bindType = 1, tooltip = { { text = "+9 Stamina" } },
            appearance = { appearanceID = 5398, sourceID = 7498, collected = true } },
        [980901] = Piece("Worn Charm", "INVTYPE_TRINKET", { tooltip = { { text = "+4 Stamina" } } }),
        [980902] = Piece("Worn Band", "INVTYPE_FINGER", { tooltip = { { text = "+4 Stamina" } } }),
    }
    local WORN = { [16] = 980900, [13] = 980901, [14] = 980901, [11] = 980902, [12] = 980902 }

    local function Start(flavor)
        local game = H.StockGame(TOON, ITEMS)
        local function Worn(location)
            return type(location) == "table" and location.IsEquipmentSlot and location:IsEquipmentSlot()
                and WORN[location:GetEquipmentSlot()] or nil
        end
        local hyperlink = game.names["C_TooltipInfo.GetHyperlink"]
        game:Set("GetInventoryItemID", function(_, slot) return WORN[slot] end)
        game:Set("GetInventoryItemLink", function(_, slot) return WORN[slot] and game.Link(WORN[slot]) or nil end)
        game:Set("C_Item.DoesItemExist", function(location) return Worn(location) ~= nil end)
        game:Set("C_Item.GetItemLink", function(location) return Worn(location) and game.Link(Worn(location)) end)
        game:Set("C_Item.GetItemID", function(location) return Worn(location) end)
        game:Set("C_Item.GetItemQuality", function(location) return Worn(location) and ITEMS[Worn(location)].quality end)
        game:Set("C_Item.GetItemName", function(location) return Worn(location) and ITEMS[Worn(location)].name end)
        game:Set("C_Item.IsBound", function() return false end)
        game:Set("C_Item.GetCurrentItemLevel", function(location) return Worn(location) and ITEMS[Worn(location)].level end)
        game:Set("C_TooltipInfo.GetInventoryItem", function(_, slot)
            return WORN[slot] and hyperlink(game.Link(WORN[slot])) or nil
        end)
        game:Set("C_Item.GetItemInventoryType", function(location)
            return Worn(location) == 980900 and game.client.env.Enum.InventoryType.Index2HweaponType or 0
        end)
        game:Set("GetInstanceInfo", function() return "Elsewhere", "none" end)
        -- How often the client is asked what an item's use is aimed at, by item.
        local asked = {}
        local harmful = game.names["C_Item.IsHarmfulItem"]
        game:Set("C_Item.IsHarmfulItem", function(reference)
            asked[reference] = (asked[reference] or 0) + 1
            return harmful(reference)
        end)

        local client = H.Client.New({ flavor = flavor, provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        local config = H.DeepCopy(namespace:GetDefaultConfig())
        -- A tie is no reason to keep a piece here, so the trinket and the ring are decided by
        -- their use alone.
        config.Icon.SameLevelBehavior = "sellable"
        rawset(client.env, "CaerdonWardrobeConfig", config)
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)
        Equal(#client.errors, 0, flavor .. ": no error reached the error handler at the start")
        skillLine.requirementType = client.env.Enum.TooltipDataUsageRequirementType.Skill
        Check(skillLine.requirementType ~= nil, flavor .. ": the client has the skill requirement type")
        return client, asked
    end

    local function Judge(client, itemID)
        local item = client.env.CaerdonItem:CreateFromItemID(itemID)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        client:TickUntil(function() return loaded end, 10)
        local ready, status, bindingResult
        client:TickUntil(function()
            local _
            ready, status, _, bindingResult = item:GetCaerdonStatus()
            return ready
        end, 10)
        return status, bindingResult or {}, item
    end

    -- The client has the question on both flavors, and the rule is the same on both.
    for _, flavor in ipairs({ "forever", "retail" }) do
        local client, asked = Start(flavor)
        local function Status(itemID)
            return (Judge(client, itemID))
        end
        local label = flavor .. ", "

        local status, _, torch = Judge(client, 980001)
        Equal(torch:HasHostileUse(), true, label .. "torch: its use is aimed at an enemy")
        Equal(status, "sellable", label .. "torch: a use aimed at an enemy does not keep it")
        Equal(Status(980002), "collected", label .. "a use cast on a friend keeps the piece")
        Equal(Status(980003), "collected", label .. "a use aimed at nothing keeps the piece")

        local gadgetStatus, gadget = Judge(client, 980004)
        Equal(gadget.hasSkillRequirement, true, label .. "gadget: the scan finds its skill requirement")
        Equal(gadgetStatus, "collected", label .. "gadget: a piece that asks for a skill is kept")
        Equal(Status(980005), "collected", label .. "quest tool: a piece no vendor pays for is kept")
        Equal(asked[980005], nil, label .. "quest tool: and the client is not asked about its use")

        -- Only Forever has stat equip lines; on retail the line is an effect (equip-stat-lines.lua).
        Equal(Status(980006), flavor == "forever" and "sellable" or "collected",
            label .. "an equip line beside the use counts as it does without the use")
        Equal(Status(980007), "collected", label .. "an equip effect beside the use keeps the piece")
        Equal(Status(980008), "sellable", label .. "no use: sellable, as before")
        Equal(asked[980008], nil, label .. "no use: and the client is not asked")

        Equal(Status(980010), "collected", label .. "trinket: kept whatever its use is aimed at")
        Equal(asked[980010], nil, label .. "trinket: and the client is not asked")
        Equal(Status(980011), "sellable", label .. "ring: the same use and the same tie, and it is not kept")

        Equal(#client.errors, 0, label .. "no error reached the error handler")
        for _, message in ipairs(client.errors) do
            print("        error: " .. tostring(message))
        end
    end
end
