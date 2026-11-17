-- A weapon skill's points and the refresh watcher (CaerdonRefresh.lua, the skills watch).
--
-- A Forever client showed the cost: a two-handed sword's skill went from 29 to 49 in eighteen
-- minutes of fighting, a point at a time, and every point redrew every icon. No icon had
-- been made from that rank. The watch reads such a line as there or not, until the tooltip of
-- an item asks for a rank of it; here that is shown with the item code's own tooltip scan.
--
-- Real code: the addon's item side and its watcher, Blizzard's base files from the mirror.
-- The items and the skill list are hand-made: whether a Forever item asks for a rank of a
-- weapon skill at all is not known, which is why the code does not assume either answer.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 31 }

    local RED = { r = 1, g = 0.125, b = 0.125 }
    local function Holdable(name, sourceID, tooltip)
        return { name = name, quality = 2, level = 31, minLevel = 26, type = "Armor", subType = "Miscellaneous",
            stack = 1, equipLoc = "INVTYPE_HOLDABLE", price = 0, classID = 4, subClassID = 0, bindType = 1,
            tooltip = tooltip, appearance = { appearanceID = sourceID - 2000, sourceID = sourceID, collected = true } }
    end

    -- The requirement types are the client's and are filled in once it is there.
    local swordsLine = { text = "Requires Swords (100)", type = 43, r = RED.r, g = RED.g, b = RED.b }
    local firstAidLine = { text = "Requires First Aid (50)", type = 43 }
    local levelLine = { text = "Requires Level 12", type = 43 }
    local ITEMS = {
        -- Asks for a rank of a weapon skill.
        [960001] = Holdable("Fencer's Token", 7301, { swordsLine }),
        -- Asks for a level, and a lock's line that reads like a skill's but is an error line.
        [960002] = Holdable("Latched Charm", 7302, { levelLine,
            { text = "Requires Pick Lock (1)", type = 41, r = RED.r, g = RED.g, b = RED.b } }),
        -- Asks for a rank of a skill no fight raises.
        [960003] = Holdable("Medic's Charm", 7303, { firstAidLine }),
    }

    local lines = {
        { skillID = 6, name = "Weapon Skills", isHeader = true, rank = 0 },
        { skillID = 43, name = "Swords", isHeader = false, rank = 97 },
        { skillID = 95, name = "Defense", isHeader = false, rank = 150 },
        { skillID = 129, name = "First Aid", isHeader = false, rank = 40 },
    }
    local SWORDS, DEFENSE, FIRST_AID = lines[2], lines[3], lines[4]

    local game = H.StockGame(TOON, ITEMS)
    game:Set("GetInstanceInfo", function() return "Wetlands", "none" end)
    game:Set("C_SkillInfo.GetNumSkillLines", function() return #lines end)
    game:Set("C_SkillInfo.GetSkillLineInfo", function(index) return lines[index] end)

    local client = H.Client.New({ flavor = "forever", provider = game })
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
    local env = client.env
    Equal(#client.errors, 0, "start: no error reached the error handler")

    local requirement = env.Enum.TooltipDataUsageRequirementType
    swordsLine.requirementType, firstAidLine.requirementType = requirement.Skill, requirement.Skill
    levelLine.requirementType = requirement.Level
    Check(requirement.Skill ~= nil and requirement.Level ~= nil, "start: the client has both requirement types")

    local function Draw(itemID)
        local item = env.CaerdonItem:CreateFromItemID(itemID)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        client:TickUntil(function() return loaded end, 10)
        local ready
        client:TickUntil(function()
            ready = item:GetCaerdonStatus()
            return ready
        end, 10)
        return ready
    end

    -- A skill line event, the check after its burst and the refresh that may follow; how many
    -- refreshes that made.
    local function Refreshes()
        local before = env.CaerdonWardrobe.refreshGeneration
        client:Fire("SKILL_LINES_CHANGED")
        client:Tick(60)
        return env.CaerdonWardrobe.refreshGeneration - before
    end
    local function Noted()
        return table.concat(namespace.Refresh:GetSkillRequirementsNoted(), ", ")
    end

    Refreshes() -- the first reading, whatever came before it
    Equal(Refreshes(), 0, "quiet: an event with the same skills refreshes nothing")

    -- Points as a fight brings them, before any item asked for a rank.
    SWORDS.rank, DEFENSE.rank = 98, 151
    Equal(Refreshes(), 0, "fight: a point of Swords and one of Defense refresh nothing")
    FIRST_AID.rank = 41
    Equal(Refreshes(), 1, "other: a point of a skill no fight raises refreshes")

    -- A level requirement and a lock's line are not a skill's rank asked for.
    Check(Draw(960002), "charm: its status is made")
    Equal(Noted(), "", "charm: a level requirement and an error line name no skill")
    SWORDS.rank = 99
    Equal(Refreshes(), 0, "charm: and Swords still refreshes nothing")

    -- A skill no fight raises was read by rank before, and naming it changes nothing.
    Check(Draw(960003), "medic: its status is made")
    Equal(Noted(), "First Aid", "medic: the tooltip scan names the skill of its requirement line")
    Equal(Refreshes(), 0, "medic: which is no change for a line already read by rank")

    -- The item that asks for a rank of Swords.
    Check(Draw(960001), "token: its status is made")
    Equal(Noted(), "First Aid, Swords", "token: Swords is named too")
    Equal(Refreshes(), 1, "token: the next event reads the rank of Swords where it read the line being there")
    SWORDS.rank = 100
    Equal(Refreshes(), 1, "token: and from then on a point of Swords refreshes")
    DEFENSE.rank = 152
    Equal(Refreshes(), 0, "token: Defense, which nothing asked for, still does not")

    -- A full refresh forgets the verdicts, not what the game's items ask for.
    env.CaerdonWardrobe:RefreshItems("test")
    client:Tick(20)
    Equal(Noted(), "First Aid, Swords", "refresh: the skills asked for are kept")
    SWORDS.rank = 101
    Equal(Refreshes(), 1, "refresh: and Swords is still read by rank")

    Equal(#client.errors, 0, "end: no error reached the error handler")
    for _, message in ipairs(client.errors) do
        print("        error: " .. tostring(message))
    end
end
