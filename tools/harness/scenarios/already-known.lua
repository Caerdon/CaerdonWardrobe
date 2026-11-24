-- The "Already known" line of an ensemble that still teaches something
-- (features/Tooltip.lua, OnRequirementLine and TeachesUncollectedSource).
--
-- The client says "Already known" on the tooltip of an ensemble once the toon has used one
-- like it, also while sources of its set are not collected and using it would teach them. The
-- addon keeps that line off the tooltip. It did so after the tooltip was filled, by reading
-- each font string's text and blanking the one that said it. Now the client asks it before a
-- requirement line is added (TooltipDataProcessor.AddLinePreCall) and it answers by the
-- line's requirement type and the item the tooltip is being filled for. A requirement line
-- that names no type is known by the words of its data; a plain line with the words is not
-- asked about and stays, where the code from before blanked it.
--
-- The tooltip code is Blizzard's own, from the mirror: the processor that keeps the
-- callbacks, the handler that fills a tooltip line by line, the functions that put a line
-- on it. Only the frame under them is the scenario's: a list of rows, with font strings
-- that count how often they are read and written.
--
-- The game is hand-made, and so is the line: no recording holds an "Already known" line, of
-- an ensemble or of anything else. That it is a requirement line of the kind NotAlreadyKnown
-- was seen on one retail item (notes: Housing, the service item). The contract
-- tooltip.alreadyKnown asks a client, and tooltip.linePreCall whether a callback of an
-- addon's is asked and obeyed there; both run here against the same tooltip code.
--
-- Real code: the addon's item side and features/Tooltip.lua, the test addon's runner and
-- contracts, Blizzard's base files and tooltip files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 33 }

    local PLAIN, REQUIREMENT = 0, 43
    local LEVEL, KNOWN = 5, 14 -- requirement types
    local CONSUMABLE, MISCELLANEOUS, ARMOR = 0, 15, 4
    local KNOWN_TEXT, LEVEL_TEXT, USE_TEXT = "Already known", "Requires Level 20", "Use: Collect the appearances of this set."
    local BOOK_TEXT, CLASSES_TEXT = "Use: Teaches you how to tie a better knot.", "Classes: Hunter"

    -- The client's line: red, a requirement line of its own kind.
    local function Known(more)
        local line = { text = KNOWN_TEXT, type = REQUIREMENT, requirementType = KNOWN, r = 1, g = 0.125, b = 0.125 }
        for key, value in pairs(more or {}) do line[key] = value end
        return line
    end
    local function Level() return { text = LEVEL_TEXT, type = REQUIREMENT, requirementType = LEVEL } end
    local function Use(text) return { text = text or USE_TEXT, type = PLAIN } end

    -- Sets by what their ensemble still teaches, and the pieces their sources are of.
    local SHIRT, GLOVES, BELT = 993101, 993102, 993103
    local SHIRT_SOURCE, GLOVES_SOURCE, BELT_SOURCE = 7801, 7802, 7803
    local OPEN_SET, VARIANT_SET, DONE_SET, UNKNOWN_SET = 501, 502, 503, 504
    local function Sets()
        return {
            -- Not collected: the gloves' look is not known.
            [OPEN_SET] = { collected = false, sources = { SHIRT_SOURCE, GLOVES_SOURCE } },
            -- Collected for the client, and one source of it is not: the look is known from
            -- another item.
            [VARIANT_SET] = { collected = true, sources = { SHIRT_SOURCE, GLOVES_SOURCE } },
            [DONE_SET] = { collected = true, sources = { SHIRT_SOURCE, BELT_SOURCE } },
            -- [UNKNOWN_SET]: the client has no word on it.
        }
    end

    local OPEN, VARIANTS, DONE, BOOK, TOKEN, WORDS, KINDLESS, LEVELLED, UNHEARD, PEBBLE =
        993001, 993002, 993003, 993004, 993005, 993006, 993007, 993008, 993009, 993010
    local SET_OF = { [OPEN] = OPEN_SET, [VARIANTS] = VARIANT_SET, [DONE] = DONE_SET, [TOKEN] = OPEN_SET,
        [WORDS] = OPEN_SET, [KINDLESS] = OPEN_SET, [LEVELLED] = VARIANT_SET, [UNHEARD] = UNKNOWN_SET }

    -- A consumable as both flavors' recordings have one (the type's name, class 0, the equip
    -- location of what cannot be worn).
    local function Consumable(name, lines)
        return { name = name, quality = 3, level = 1, minLevel = 0, type = "Consumable", subType = "Other", stack = 1,
            equipLoc = "INVTYPE_NON_EQUIP_IGNORE", price = 0, classID = CONSUMABLE, subClassID = 8, bindType = 1,
            tooltip = lines }
    end
    local function Piece(name, appearanceID, sourceID, collected)
        return { name = name, quality = 2, level = 20, minLevel = 20, type = "Armor", subType = "Leather", stack = 1,
            equipLoc = "INVTYPE_HAND", price = 500, classID = ARMOR, subClassID = 2, bindType = 2,
            tooltip = { Level(), { text = CLASSES_TEXT, type = REQUIREMENT, requirementType = 0 } },
            appearance = { appearanceID = appearanceID, sourceID = sourceID, collected = collected } }
    end
    local function Items()
        local token = Consumable("Token of the Open Set", { Use(), Known() })
        token.type, token.subType, token.classID, token.subClassID = "Miscellaneous", "Other", MISCELLANEOUS, 4
        return {
            [OPEN] = Consumable("Ensemble: Open Set", { Use(), Known() }),
            [VARIANTS] = Consumable("Ensemble: Set With Another Source", { Use(), Known() }),
            [DONE] = Consumable("Ensemble: Finished Set", { Use(), Known() }),
            -- Teaches no set.
            [BOOK] = Consumable("Manual: Better Knots", { Use(BOOK_TEXT), Known() }),
            -- Teaches the open set and is no consumable.
            [TOKEN] = token,
            -- The words on a plain line, and on a requirement line that names no kind.
            [WORDS] = Consumable("Ensemble: Plain Words", { Use(), Known({ type = PLAIN, requirementType = false }) }),
            [KINDLESS] = Consumable("Ensemble: No Kind", { Use(), Known({ requirementType = false }) }),
            [LEVELLED] = Consumable("Ensemble: For Level 20", { Level(), Use(), Known() }),
            [UNHEARD] = Consumable("Ensemble: Unheard Of", { Use(), Known() }),
            [PEBBLE] = { name = "Pebble", quality = 0, level = 1, minLevel = 0, type = "Miscellaneous", subType = "Junk",
                stack = 20, equipLoc = "INVTYPE_NON_EQUIP_IGNORE", price = 1, classID = MISCELLANEOUS, subClassID = 0,
                tooltip = { Use("A pebble.") } },
            [SHIRT] = Piece("Set Shirt", 5801, SHIRT_SOURCE, true),
            [GLOVES] = Piece("Set Gloves", 5802, GLOVES_SOURCE, false),
            [BELT] = Piece("Set Belt", 5803, BELT_SOURCE, true),
        }
    end

    local function IdOf(reference)
        return type(reference) == "number" and reference or tonumber(tostring(reference):match("item:(%d+)"))
    end

    -- A client with Blizzard's tooltip code in it, the addon's item side and its Tooltip
    -- feature. world.asked counts what the feature asks the game; world.secret is a value the
    -- client keeps secret; world.setInfoFails makes the game raise an error.
    local function Start(flavor)
        local items, sets = Items(), Sets()
        local game = H.StockGame(TOON, items)
        local world = { game = game, items = items, sets = sets, bag = {},
            asked = { learnSet = 0, setInfo = 0, sources = 0 }, registered = {} }
        local hyperlink = game.names["C_TooltipInfo.GetHyperlink"]
        -- false stands for "no such field" in the items above.
        game:Set("C_TooltipInfo.GetHyperlink", function(link)
            local data = hyperlink(link)
            for _, line in ipairs(data and data.lines or {}) do
                if line.requirementType == false then
                    line.requirementType = nil
                end
            end
            return data
        end)
        game:Set("C_Item.GetItemLearnTransmogSet", function(reference)
            world.asked.learnSet = world.asked.learnSet + 1
            world.askedWith = reference
            return SET_OF[IdOf(reference)]
        end)
        game:Set("C_TransmogSets.GetSetInfo", function(setID)
            world.asked.setInfo = world.asked.setInfo + 1
            if world.setInfoFails then
                error("the game has no set info today", 0)
            end
            return sets[setID] and { setID = setID, collected = sets[setID].collected } or nil
        end)
        game:Set("C_TransmogSets.GetAllSourceIDs", function(setID)
            world.asked.sources = world.asked.sources + 1
            return sets[setID] and sets[setID].sources or {}
        end)
        -- The bags, for the contracts: world.bag is the backpack.
        game:Set("C_Container.GetContainerNumSlots", function(bag) return bag == 0 and #world.bag or 0 end)
        game:Set("C_Container.GetContainerItemID", function(bag, slot) return bag == 0 and world.bag[slot] or nil end)
        game:Set("C_Container.GetContainerItemLink", function(bag, slot)
            return bag == 0 and world.bag[slot] and game.Link(world.bag[slot]) or nil
        end)
        game:Set("C_TooltipInfo.GetBagItem", function(bag, slot)
            return bag == 0 and world.bag[slot] and game.names["C_TooltipInfo.GetHyperlink"](game.Link(world.bag[slot])) or nil
        end)
        -- What Blizzard's tooltip code asks of the client as it loads and as it runs.
        game:Set("C_RestrictedActions.CheckAllowProtectedFunctions", function() return true end)
        game:Set("canaccessallvalues", function() return true end)
        game:Set("forceinsecure", function() end)
        game:Set("CreateSecureDelegate", function(fn) return fn end)
        game:Set("mapvalues", function(fn, ...)
            local results, count = {}, select("#", ...)
            for index = 1, count do
                results[index] = fn((select(index, ...)))
            end
            return unpack(results, 1, count)
        end)

        local client = H.Client.New({ flavor = flavor, provider = game })
        game.client = client
        local env = client.env
        world.client, world.env = client, env
        H.LoadBlizzardBase(client)
        rawset(env, "issecretvalue", function(value) return world.secret ~= nil and value == world.secret end)
        rawset(env, "NORMAL_FONT_COLOR", env.CreateColor(1, 0.82, 0, 1))
        -- The handler takes its copy of C_TooltipInfo as it loads: the two it is asked for
        -- here have to be there by then.
        Check(type(env.C_TooltipInfo.GetHyperlink) == "function" and type(env.C_TooltipInfo.GetBagItem) == "function",
            flavor .. ": the game answers for a link's and a slot's tooltip")
        client:LoadBlizzard("Blizzard_SharedXML/SharedTooltipTemplates.lua")
        client:LoadBlizzard("Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua")
        client:LoadBlizzard("Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua")
        -- Who asks to be called before a line, and for which line type.
        local addLinePreCall = env.TooltipDataProcessor.AddLinePreCall
        env.TooltipDataProcessor.AddLinePreCall = function(lineType, callback)
            world.registered[#world.registered + 1] = lineType
            return addLinePreCall(lineType, callback)
        end

        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "features/Tooltip.lua", namespace)
        world.namespace = namespace
        Equal(#client.errors, 0, flavor .. ": no error reached the error handler at the start (" ..
            tostring(client.errors[1]) .. ")")

        -- A tooltip: Blizzard's handler on a frame of rows. A font string counts its reads and
        -- its writes, which is what the code from before did to find and blank the line.
        function world.NewTooltip(name)
            local tooltip = env.CreateFromMixins(env.TooltipDataHandlerMixin)
            tooltip.rows, tooltip.reads, tooltip.writes = {}, 0, 0
            local function Row(left, right)
                tooltip.rows[#tooltip.rows + 1] = { text = left, right = right, shown = true }
                local index = #tooltip.rows
                rawset(env, name .. "TextLeft" .. index, {
                    GetText = function()
                        tooltip.reads = tooltip.reads + 1
                        return tooltip.rows[index] and tooltip.rows[index].text
                    end,
                    SetText = function(_, text)
                        tooltip.writes = tooltip.writes + 1
                        if tooltip.rows[index] then tooltip.rows[index].text = text end
                    end,
                    Hide = function()
                        tooltip.writes = tooltip.writes + 1
                        if tooltip.rows[index] then tooltip.rows[index].shown = false end
                    end,
                })
            end
            function tooltip:GetName() return name end
            function tooltip:SetOwner() end
            function tooltip:IsForbidden() return false end
            function tooltip:ClearLines() self.rows = {} end
            function tooltip:NumLines() return #self.rows end
            function tooltip:AddLine(text) Row(text) end
            function tooltip:AddDoubleLine(left, right) Row(left, right) end
            function tooltip:Show() self.onScreen = true end
            function tooltip:Hide() self.onScreen = false end
            rawset(env, name, tooltip)
            return tooltip
        end
        -- What is on a tooltip, top to bottom; a row that was hidden says so.
        function world.Shown(tooltip)
            local texts = {}
            for index, row in ipairs(tooltip.rows) do
                texts[index] = row.shown and tostring(row.text) or ("<hidden: " .. tostring(row.text) .. ">")
            end
            return table.concat(texts, " | ")
        end
        -- Fills a tooltip with an item, as the client does for a link.
        function world.Fill(tooltip, itemID)
            tooltip.reads, tooltip.writes = 0, 0
            return tooltip:ProcessInfo({ getterName = "GetHyperlink", getterArgs = env.SafePack(game.Link(itemID)) })
        end
        return world
    end

    local function Lines(...)
        return table.concat({ ... }, " | ")
    end

    -- label, the item, what its tooltip shows below the name.
    local CASES = {
        { "an ensemble whose set is not collected", OPEN, Lines(USE_TEXT) },
        { "an ensemble whose set is collected, with a source that is not", VARIANTS, Lines(USE_TEXT) },
        { "an ensemble with every source collected", DONE, Lines(USE_TEXT, KNOWN_TEXT) },
        { "a book that teaches no set", BOOK, Lines(BOOK_TEXT, KNOWN_TEXT) },
        { "an item that teaches the open set and is no consumable", TOKEN, Lines(USE_TEXT, KNOWN_TEXT) },
        { "an ensemble with the words on a plain line", WORDS, Lines(USE_TEXT, KNOWN_TEXT) },
        { "an ensemble with the words on a requirement line of no kind", KINDLESS, Lines(USE_TEXT) },
        { "an ensemble with a level line as well", LEVELLED, Lines(LEVEL_TEXT, USE_TEXT) },
        { "an ensemble whose set the client has no word on", UNHEARD, Lines(USE_TEXT, KNOWN_TEXT) },
    }

    for _, flavor in ipairs({ "forever", "retail" }) do
        local world = Start(flavor)
        local client, env, game, items, sets = world.client, world.env, world.game, world.items, world.sets
        local Fill, Shown = world.Fill, world.Shown
        local feature = world.namespace.Tooltip

        Equal(env.Enum.TooltipDataLineType.UsageRequirement, REQUIREMENT, flavor .. ": the requirement line's type is the one the cases use")
        Equal(env.Enum.TooltipDataUsageRequirementType.NotAlreadyKnown, KNOWN, flavor .. ": and the kind for what is known")
        Equal(env.Enum.TooltipDataUsageRequirementType.Level, LEVEL, flavor .. ": and for a level")
        Equal(env.Enum.TooltipDataType.Item, 0, flavor .. ": an item's tooltip data is of the type the game hands out")
        Equal(env.Enum.ItemClass.Consumable, CONSUMABLE, flavor .. ": the consumables' class")
        Equal(env.ITEM_SPELL_KNOWN, KNOWN_TEXT, flavor .. ": the client's words for it")

        -- The feature asked once, for requirement lines.
        Equal(#world.registered, 1, flavor .. ": one callback asks to be called before a line")
        Equal(world.registered[1], REQUIREMENT, flavor .. ": for requirement lines")
        Check(type(feature.OnRequirementLine) == "function", flavor .. ": the handler has the name the counters wrap it by")

        -- The mock hands the lines over as the items say.
        do
            local line = env.C_TooltipInfo.GetHyperlink(game.Link(OPEN)).lines[3]
            Check(line.type == REQUIREMENT and line.requirementType == KNOWN and line.usable == false
                and line.leftText == KNOWN_TEXT, flavor .. ": the ensemble's line is a requirement line of the kind, unmet")
            line = env.C_TooltipInfo.GetHyperlink(game.Link(WORDS)).lines[3]
            Check(line.type == PLAIN and line.requirementType == nil and line.leftText == KNOWN_TEXT,
                flavor .. ": the plain line has the words and no kind")
            line = env.C_TooltipInfo.GetHyperlink(game.Link(KINDLESS)).lines[3]
            Check(line.type == REQUIREMENT and line.requirementType == nil, flavor .. ": the line of no kind has none")
        end

        local tooltip = world.NewTooltip("ScenarioTooltip")
        for _, case in ipairs(CASES) do
            local label, itemID = flavor .. ", " .. case[1], case[2]
            Equal(Fill(tooltip, itemID), true, label .. ": the tooltip is filled")
            Equal(Shown(tooltip), Lines(items[itemID].name, case[3]), label .. ": what it shows")
            Equal(tooltip.reads, 0, label .. ": no font string was read")
            Equal(tooltip.writes, 0, label .. ": none was changed")
            Equal(#tooltip:GetPrimaryTooltipData().lines, 1 + #items[itemID].tooltip, label .. ": its data keeps every line")
        end
        Equal(#client.errors, 0, flavor .. ": no error reached the error handler in the cases (" .. tostring(client.errors[1]) .. ")")

        -- What it asks the game, and with what. The handler is looked up as it is called, so
        -- a wrapper put on it afterwards counts (the counters' way).
        do
            local calls = 0
            local real = feature.OnRequirementLine
            feature.OnRequirementLine = function(...)
                calls = calls + 1
                return real(...)
            end
            local function Asked(itemID)
                calls = 0
                world.asked = { learnSet = 0, setInfo = 0, sources = 0 }
                world.askedWith = nil
                Fill(tooltip, itemID)
                return world.asked
            end
            local asked = Asked(PEBBLE)
            Equal(calls, 0, flavor .. ", asked: a tooltip with no requirement line does not come to the handler")
            asked = Asked(GLOVES)
            Equal(calls, 2, flavor .. ", asked: one with two requirement lines comes twice")
            Equal(asked.learnSet, 0, flavor .. ", asked: and a level or a class line asks the game nothing")
            -- A requirement line of no kind with other words: nothing either.
            items[KINDLESS].tooltip[2].text = "Requires a steady hand"
            asked = Asked(KINDLESS)
            Equal(asked.learnSet, 0, flavor .. ", asked: nor does a line of no kind that says something else")
            Equal(Shown(tooltip), Lines(items[KINDLESS].name, USE_TEXT, "Requires a steady hand"), flavor .. ", asked: which stays")
            items[KINDLESS].tooltip[2].text = KNOWN_TEXT
            asked = Asked(BOOK)
            Equal(asked.learnSet, 1, flavor .. ", asked: a known line asks once which set the item teaches")
            Equal(world.askedWith, BOOK, flavor .. ", asked: by the ID in the tooltip's data")
            Equal(asked.setInfo, 0, flavor .. ", asked: and nothing of a set where it teaches none")
            asked = Asked(TOKEN)
            Equal(asked.setInfo, 0, flavor .. ", asked: nor where the item is no consumable")
            asked = Asked(OPEN)
            Equal(asked.setInfo, 1, flavor .. ", asked: a set that is not collected is asked for once")
            Equal(asked.sources, 0, flavor .. ", asked: and its sources are not walked")
            asked = Asked(DONE)
            Equal(asked.sources, 1, flavor .. ", asked: a collected set's sources are walked once")
            feature.OnRequirementLine = real
        end

        -- Only an item's tooltip: the same line in data of another type stays.
        do
            local data = env.C_TooltipInfo.GetHyperlink(game.Link(OPEN))
            data.type = env.Enum.TooltipDataType.Spell
            world.asked.learnSet = 0
            tooltip:ProcessInfo({ tooltipData = data })
            Equal(Shown(tooltip), Lines(items[OPEN].name, USE_TEXT, KNOWN_TEXT), flavor .. ": a spell's tooltip keeps the line")
            Equal(world.asked.learnSet, 0, flavor .. ": and the game is asked nothing for it")
        end

        -- A tooltip that shows two things: the item is the one being added, not the first.
        do
            Fill(tooltip, BOOK)
            tooltip:ProcessInfo({ tooltipData = env.C_TooltipInfo.GetHyperlink(game.Link(OPEN)), append = true })
            Equal(Shown(tooltip), Lines(items[BOOK].name, BOOK_TEXT, KNOWN_TEXT, items[OPEN].name, USE_TEXT),
                flavor .. ": appended to a book's tooltip, the ensemble loses its line and the book keeps its own")
            Fill(tooltip, OPEN)
            tooltip:ProcessInfo({ tooltipData = env.C_TooltipInfo.GetHyperlink(game.Link(BOOK)), append = true })
            Equal(Shown(tooltip), Lines(items[OPEN].name, USE_TEXT, items[BOOK].name, BOOK_TEXT, KNOWN_TEXT),
                flavor .. ": and the other way round")
        end

        -- Asked anew each time the tooltip is filled: the last source learned, the line is
        -- there when the client fills the tooltip again.
        do
            Fill(tooltip, OPEN)
            Equal(Shown(tooltip), Lines(items[OPEN].name, USE_TEXT), flavor .. ", again: off while a source is missing")
            items[GLOVES].appearance.collected, sets[OPEN_SET].collected = true, true
            tooltip:RebuildFromTooltipInfo()
            Equal(Shown(tooltip), Lines(items[OPEN].name, USE_TEXT, KNOWN_TEXT), flavor .. ", again: there once the last is learned")
            items[GLOVES].appearance.collected, sets[OPEN_SET].collected = false, false
            tooltip:RebuildFromTooltipInfo()
            Equal(Shown(tooltip), Lines(items[OPEN].name, USE_TEXT), flavor .. ", again: and off again")
        end

        -- A value the client keeps secret is not compared and not handed back to it.
        do
            local function Secret(value, label)
                world.secret = value
                world.asked.learnSet = 0
                Fill(tooltip, OPEN)
                Equal(Shown(tooltip), Lines(items[OPEN].name, USE_TEXT, KNOWN_TEXT), flavor .. ", secret " .. label .. ": the line stays")
                Equal(world.asked.learnSet, 0, flavor .. ", secret " .. label .. ": and the game is asked nothing")
                world.secret = nil
            end
            Secret(KNOWN, "requirement type")
            Secret(env.Enum.TooltipDataType.Item, "data type")
            Secret(OPEN, "item ID")
            -- The words of a line that names no kind.
            world.secret = KNOWN_TEXT
            Fill(tooltip, KINDLESS)
            Equal(Shown(tooltip), Lines(items[KINDLESS].name, USE_TEXT, KNOWN_TEXT), flavor .. ", secret words: the line stays")
            world.secret = nil
            Fill(tooltip, KINDLESS)
            Equal(Shown(tooltip), Lines(items[KINDLESS].name, USE_TEXT), flavor .. ", secret words: with none, it is off")
            Fill(tooltip, OPEN)
            Equal(Shown(tooltip), Lines(items[OPEN].name, USE_TEXT), flavor .. ", secret: with none, the line is off as before")
        end

        -- An error in the handler: reported, the line is added, and the tooltip after it is
        -- as it should be.
        do
            local before = #client.errors
            world.setInfoFails = true
            Equal(Fill(tooltip, OPEN), true, flavor .. ", error: the tooltip is filled")
            world.setInfoFails = nil
            Equal(Shown(tooltip), Lines(items[OPEN].name, USE_TEXT, KNOWN_TEXT), flavor .. ", error: with every line")
            Equal(#client.errors, before + 1, flavor .. ", error: reported once")
            Check(tostring(client.errors[#client.errors]):find("no set info today", 1, true) ~= nil,
                flavor .. ", error: as the game raised it (" .. tostring(client.errors[#client.errors]) .. ")")
            Fill(tooltip, OPEN)
            Equal(Shown(tooltip), Lines(items[OPEN].name, USE_TEXT), flavor .. ", error: the next tooltip is right")
            Equal(#client.errors, before + 1, flavor .. ", error: and nothing more was reported")
            table.remove(client.errors)
        end

        ----------------------------------------------------------------------------------
        -- The test addon's contracts, against the same tooltip code
        ----------------------------------------------------------------------------------

        local createFrame = env.CreateFrame
        local contractTooltips = {}
        rawset(env, "CreateFrame", function(frameType, name, ...)
            if frameType == "GameTooltip" then
                contractTooltips[#contractTooltips + 1] = world.NewTooltip(name)
                return contractTooltips[#contractTooltips]
            end
            return createFrame(frameType, name, ...)
        end)
        local wanted = { ["Core.lua"] = true, ["Runner.lua"] = true, ["Contracts.lua"] = true, ["Plan.lua"] = true }
        local T = H.LoadAddon(client, "CaerdonWardrobe_Tests", H.addonDir .. "/CaerdonWardrobe_Tests",
            function(relative) return not wanted[relative] end)
        client:Fire("ADDON_LOADED", "CaerdonWardrobe_Tests")
        client:Fire("PLAYER_LOGIN")
        local function Run(id, fresh)
            if fresh then
                (T.db.contracts[T.GetClient().build] or {})[id] = nil
            end
            T.RunTests({ match = id, force = true })
            Check(client:TickUntil(function() return not T.IsBusy() end, 120), flavor .. ", " .. id .. ": the job ends")
            return (T.db.contracts[T.GetClient().build] or {})[id] or {}
        end
        local function Fault(id, label, plant, undo, expected)
            plant()
            local faulty = Run(id)
            Equal(faulty.status, "fail", flavor .. ", " .. id .. ", fault, " .. label .. ": the contract fails")
            Check(tostring(faulty.message):find(expected, 1, true) ~= nil,
                flavor .. ", " .. id .. ", fault, " .. label .. ": and says why (" .. tostring(faulty.message) .. ")")
            undo()
        end

        -- tooltip.alreadyKnown: what the line is in this client's data.
        do
            local ID = "tooltip.alreadyKnown"
            world.bag = { PEBBLE, GLOVES }
            local result = Run(ID)
            Equal(result.status, "info", flavor .. ", " .. ID .. ": bags with nothing known answer nothing (" .. tostring(result.message) .. ")")
            Equal((result.detail or {}).knownLines, 0, flavor .. ", " .. ID .. ": and count no line")

            world.bag = { PEBBLE, BOOK, OPEN, DONE, GLOVES }
            result = Run(ID, true)
            Equal(result.status, "pass", flavor .. ", " .. ID .. ": it passes on the bags (" .. tostring(result.message) .. ")")
            local detail = result.detail or {}
            Equal(detail.items, 5, flavor .. ", " .. ID .. ": five items")
            Equal(detail.knownLines, 6, flavor .. ", " .. ID .. ": three of them say it, in the slot's and the link's tooltip")
            local shape = "type 43, requirementType 14, usable false, \"Already known\""
            Equal((detail.seen or {})["slot: " .. shape], 3, flavor .. ", " .. ID .. ": the slot's lines by what they carry")
            Equal((detail.seen or {})["link: " .. shape], 3, flavor .. ", " .. ID .. ": and the link's")
            local open, done = (detail.ensembles or {})[tostring(OPEN)] or {}, (detail.ensembles or {})[tostring(DONE)] or {}
            Check(open.setID == OPEN_SET and open.setCollected == false and open.sources == 2 and open.uncollected == 1
                and open.slotSaysKnown == true and open.linkSaysKnown == true and open.classID == CONSUMABLE,
                flavor .. ", " .. ID .. ": the open ensemble with what it still teaches")
            Check(done.setID == DONE_SET and done.setCollected == true and done.uncollected == 0 and done.slotSaysKnown == true,
                flavor .. ", " .. ID .. ": and the finished one")
            Equal((detail.ensembles or {})[tostring(BOOK)], nil, flavor .. ", " .. ID .. ": a book is no ensemble")

            result = Run(ID)
            Equal((result.detail or {}).knownLines, 12, flavor .. ", " .. ID .. ": a second run adds to the first")
            Equal(((result.detail or {}).seen or {})["slot: " .. shape], 6, flavor .. ", " .. ID .. ": also to what was seen")

            local line = items[BOOK].tooltip[2]
            Fault(ID, "the words on a plain line", function() line.type, line.requirementType = PLAIN, false end,
                function() line.type, line.requirementType = REQUIREMENT, KNOWN end,
                "the text \"Already known\" is on a line of type 0 with requirement type nil")
            Fault(ID, "the words on a requirement line of another kind", function() line.requirementType = LEVEL end,
                function() line.requirementType = KNOWN end,
                "the text \"Already known\" is on a line of type 43 with requirement type 5")
            Equal(Run(ID).status, "pass", flavor .. ", " .. ID .. ": and passes again without a fault")

            -- Other words on a line of the kind are no fault: retail writes "Already Known" on
            -- a cosmetic piece whose look is collected. They are kept by what they say.
            line.text = "Already Known"
            result = Run(ID, true)
            Equal(result.status, "pass", flavor .. ", " .. ID .. ": other words on a line of the kind are no fault (" .. tostring(result.message) .. ")")
            detail = result.detail or {}
            Equal(detail.knownLines, 6, flavor .. ", " .. ID .. ": the line counts as one of the kind")
            Equal(detail.spellKnownLines, 4, flavor .. ", " .. ID .. ": and not as one with the client's words for a spell")
            Equal((detail.otherWords or {})["\"Already Known\" on item " .. BOOK], 2, flavor .. ", " .. ID .. ": its words are kept with its item")
            result = Run(ID)
            Equal(((result.detail or {}).otherWords or {})["\"Already Known\" on item " .. BOOK], 4, flavor .. ", " .. ID .. ": and added to by a second run")
            world.bag = { PEBBLE, BOOK, GLOVES }
            result = Run(ID, true)
            Equal(result.status, "info", flavor .. ", " .. ID .. ": bags with other words alone say nothing of the client's words")
            Equal((result.detail or {}).spellKnownLines, 0, flavor .. ", " .. ID .. ": and count none of them")
            line.text = KNOWN_TEXT
            world.bag = { PEBBLE, BOOK, OPEN, DONE, GLOVES }
            Equal(Run(ID, true).status, "pass", flavor .. ", " .. ID .. ": and with the client's words back it passes")
        end

        -- tooltip.linePreCall: a callback of an addon's is asked, and obeyed.
        do
            local ID = "tooltip.linePreCall"
            world.bag = { PEBBLE }
            local result = Run(ID)
            Equal(result.status, "skip", flavor .. ", " .. ID .. ": bags with no requirement line are skipped")
            -- An ensemble is passed over: the addon's own handler answers for its line first.
            world.bag = { PEBBLE, OPEN }
            Equal(Run(ID, true).status, "skip", flavor .. ", " .. ID .. ": so are bags where only an ensemble has one")
            world.bag = { PEBBLE, OPEN, GLOVES }

            result = Run(ID, true)
            Equal(result.status, "pass", flavor .. ", " .. ID .. ": it passes (" .. tostring(result.message) .. ")")
            local detail = result.detail or {}
            Equal(detail.itemID, GLOVES, flavor .. ", " .. ID .. ": on the first item with a requirement line that teaches no set")
            Equal(detail.requirementLines, 2, flavor .. ", " .. ID .. ": which has two")
            Equal(detail.lines, 3, flavor .. ", " .. ID .. ": three lines on its tooltip")
            Equal(detail.linesWithOneKeptOff, 2, flavor .. ", " .. ID .. ": two with the first requirement kept off")
            Equal(detail.lineText, LEVEL_TEXT, flavor .. ", " .. ID .. ": the level line")
            Equal(#contractTooltips, 1, flavor .. ", " .. ID .. ": one tooltip of the tests' own")
            Equal(#world.registered, 2, flavor .. ", " .. ID .. ": and one callback of theirs")
            Run(ID)
            Equal(#world.registered, 2, flavor .. ", " .. ID .. ": which a second run does not register again")

            -- Outside the contract its callback answers nothing: the tooltips are as before.
            Fill(tooltip, GLOVES)
            Equal(Shown(tooltip), Lines(items[GLOVES].name, LEVEL_TEXT, CLASSES_TEXT), flavor .. ", " .. ID .. ": another tooltip keeps its lines")

            -- Clients that do otherwise, one at a time, as the tests' tooltip.
            local probe = contractTooltips[1]
            local real = probe.ProcessLineData
            local function Restore()
                probe.ProcessLineData, probe.GetProcessingTooltipInfo = real, env.TooltipDataHandlerMixin.GetProcessingTooltipInfo
            end
            Fault(ID, "a client that adds the line whatever the answer", function()
                probe.ProcessLineData = function(self, lineData, ...)
                    local before = self:NumLines()
                    real(self, lineData, ...)
                    if self:NumLines() == before then
                        self:AddLineDataText(lineData)
                    end
                end
            end, Restore, "the tooltip has 3 lines with one line kept off and 3 with none")
            Fault(ID, "a client that does not ask", function()
                probe.ProcessLineData = function(self, lineData) self:AddLineDataText(lineData) end
            end, Restore, "the callback was not asked while a tooltip with 2 requirement lines was filled")
            Fault(ID, "a client that asks after the line is on", function()
                probe.ProcessLineData = function(self, lineData, ...)
                    self:AddLineDataText(lineData)
                    local add = self.AddLineDataText
                    self.AddLineDataText = function() end
                    real(self, lineData, ...)
                    self.AddLineDataText = add
                end
            end, Restore, "the line the callback was asked about is not where the next line went")
            Fault(ID, "a client whose tooltip does not say what it is being filled from", function()
                probe.GetProcessingTooltipInfo = function() return nil end
            end, Restore, "the tooltip's processing info has data of type nil for nil")
            Equal(Run(ID).status, "pass", flavor .. ", " .. ID .. ": and passes again without a fault")
        end
        Equal(#client.errors, 0, flavor .. ": no error reached the error handler (" .. tostring(client.errors[1]) .. ")")
    end
end
