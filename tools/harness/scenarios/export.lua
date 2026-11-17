-- The tooltip sections of the Copy Details export (features/DebugFrame.lua,
-- GetTooltipReportRows): every line of an item's tooltip with every field it carries.
--
-- The tooltips here are hand-made in the shape a Forever client answered with (the fixtures
-- hold real ones), plus fields no client has: the point of the export is that a field nobody
-- knew of shows up, so that is what is asked of it. This proves what the export prints for
-- given answers and nothing about what a client answers.
--
-- The second half is the test addon's contract export.tooltipLines, which asks the same of
-- the export for every item in the bags of a client: here against bags of three items, and
-- against an export that leaves a field or a line out.
--
-- The last part is the contract tooltip.gameOnly: that nothing an addon adds to a tooltip is
-- in the data the addon reads. The tooltip frame here is a model written for this file (it
-- asks for its data, shows the lines, runs the callbacks), so this proves that the contract
-- tells a client that keeps the two apart from one that does not, and nothing about clients.
--
-- Real code: the addon's item side and features/DebugFrame.lua, of the test addon Core,
-- Runner, Contracts and Plan, Blizzard's base files from the mirror. The Debug Frame's window
-- is never built: the file is loaded after the addon's features were started.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 29 }
    local ITEMS = {
        [920001] = { name = "Soldier's Bracers", quality = 2, level = 15, minLevel = 10, type = "Armor", subType = "Mail",
            stack = 1, equipLoc = "INVTYPE_WRIST", price = 204, classID = 4, subClassID = 3, bindType = 2 },
        [920002] = { name = "Soldier's Girdle", quality = 2, level = 15, minLevel = 10, type = "Armor", subType = "Mail",
            stack = 1, equipLoc = "INVTYPE_WAIST", price = 210, classID = 4, subClassID = 3, bindType = 2 },
        [920003] = { name = "Cracked Fang", quality = 0, level = 5, minLevel = 0, type = "Miscellaneous", subType = "Junk",
            stack = 20, price = 12, classID = 15, subClassID = 0 },
        [920004] = { name = "Reins of the Dun Ram", quality = 4, level = 1, minLevel = 10, type = "Miscellaneous",
            subType = "Mount", stack = 1, price = 0, classID = 15, subClassID = 5, bindType = 1 },
        [920005] = { name = "Moss Toad", quality = 1, level = 1, minLevel = 0, type = "Miscellaneous",
            subType = "Companion Pets", stack = 1, price = 0, classID = 15, subClassID = 2, bindType = 1 },
    }

    local game = H.StockGame(TOON, ITEMS)
    local client = H.Client.New({ flavor = "forever", provider = game })
    game.client = client
    local env = client.env
    H.LoadBlizzardBase(client)
    local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
    client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
    rawset(env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
    client:Fire("ADDON_LOADED", "CaerdonWardrobe")
    client:Fire("VARIABLES_LOADED")
    client:Fire("PLAYER_LOGIN")
    client:Fire("PLAYER_ENTERING_WORLD", true, false)
    client:Tick(40)
    client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "features/DebugFrame.lua", namespace)
    local feature = env.CaerdonWardrobe:GetFeature("DebugFrame")
    Check(type(feature) == "table" and type(feature.GetTooltipReportRows) == "function",
        "the Debug Frame feature is registered and has the tooltip rows")
    if type(feature) ~= "table" or type(feature.GetTooltipReportRows) ~= "function" then
        return
    end

    local LINK = game.Link(920001)
    local WHITE, GREEN, RED, GOLD = { 1, 1, 1 }, { 0.1176470592617989, 1, 0 }, { 1, 0.12549020349979401, 0.12549020349979401 },
        { 1, 0.82352942228317261, 0 }

    local function Color(rgb)
        return env.CreateColor(rgb[1], rgb[2], rgb[3], 1)
    end

    -- A tooltip as the client hands it over. binding is the bonding value and its text.
    local function Tooltip(binding, more)
        local data = {
            type = 0, id = 920001, hyperlink = LINK, dataInstanceID = 0, isAzeriteItem = false,
            lines = {
                { type = 22, leftText = "Soldier's Bracers", leftColor = Color(GREEN), quality = 2 },
                { type = 20, leftText = binding.text, leftColor = Color(WHITE), bonding = binding.bonding },
                { type = 21, leftText = "Wrist", leftColor = Color(WHITE), rightText = "Mail", rightColor = Color(RED),
                    isValidInvSlot = true, isValidItemType = false },
                { type = 0, leftText = "63 Armor", leftColor = Color(WHITE) },
                { type = 43, leftText = "Requires Level 10", leftColor = Color(WHITE), level = 10, requirementType = 5,
                    usable = true },
                { type = 11, leftText = "", leftColor = Color(GOLD), price = 204, maxPrice = -1 },
            },
        }
        for key, value in pairs(more or {}) do
            data[key] = value
        end
        return data
    end

    local ON_EQUIP = { bonding = 7, text = "Binds when equipped" }
    local SOULBOUND = { bonding = 3, text = "Soulbound" }

    local asked = {}
    local answers = {}
    game:Set("C_TooltipInfo.GetHyperlink", function(link)
        asked[#asked + 1] = "GetHyperlink " .. tostring(link)
        if answers.makeLink then
            return answers.makeLink(link)
        end
        if answers.byLink then
            return answers.byLink[link]
        end
        return answers.link
    end)
    game:Set("C_TooltipInfo.GetBagItem", function(bag, slot)
        asked[#asked + 1] = ("GetBagItem %s %s"):format(tostring(bag), tostring(slot))
        if answers.makeSlot then
            return answers.makeSlot(bag, slot)
        end
        if answers.bySlot then
            return answers.bySlot[bag .. ":" .. slot]
        end
        return answers.bag
    end)
    game:Set("C_TooltipInfo.GetInventoryItem", function(unit, slot)
        asked[#asked + 1] = ("GetInventoryItem %s %s"):format(tostring(unit), tostring(slot))
        return answers.equipped
    end)

    local function Rows(link, location)
        asked = {}
        local rows = feature:GetTooltipReportRows(link, location)
        local texts = {}
        for index, row in ipairs(rows) do
            texts[index] = string.rep("  ", row.indent) .. row.text
        end
        return texts, table.concat(texts, "\n")
    end

    -- The index of the first row that is exactly this text, from a row on.
    local function Find(texts, text, from)
        for index = from or 1, #texts do
            if texts[index] == text then
                return index
            end
        end
        return nil
    end

    local function Count(texts, text)
        local count = 0
        for _, row in ipairs(texts) do
            if row == text then
                count = count + 1
            end
        end
        return count
    end

    --------------------------------------------------------------------------------------
    -- A bare link: one tooltip, every line, every field
    --------------------------------------------------------------------------------------

    do
        answers = { link = Tooltip(ON_EQUIP) }
        local texts, all = Rows(LINK, nil)
        Equal(#asked, 1, "link: one question")
        Equal(asked[1], "GetHyperlink " .. LINK, "link: for the link's tooltip")
        Equal(texts[1], "", "link: a blank row before the section")
        Equal(texts[2], "[Tooltip Lines (Raw)]", "link: the section's name")
        Equal(texts[3], "  Asked: C_TooltipInfo.GetHyperlink(link), which the status is computed from", "link: what was asked")
        Equal(texts[4], "  Data: dataInstanceID=0, hyperlink=" .. LINK .. ", id=920001, isAzeriteItem=false, type=0 (Item)",
            "link: the answer's own fields, sorted, without its lines")
        Equal(texts[5], "  [1] type=22 (ItemName) color=ff1eff00  L: Soldier's Bracers", "link: the name line")
        Equal(texts[6], "      quality=2", "link: its field")
        Equal(texts[7], "  [2] type=20 (ItemBinding) color=ffffffff  L: Binds when equipped", "link: the binding line")
        Equal(texts[8], "      bonding=7 (BindOnEquip)", "link: its field, with the enum's name")
        Equal(texts[9], "  [3] type=21 (EquipSlot) color=ffffffff rcolor=ffff2020  L: Wrist  |  R: Mail",
            "link: the slot line with both columns and the red of the right one")
        Equal(texts[10], "      isValidInvSlot=true, isValidItemType=false", "link: its two fields")
        Equal(texts[11], "  [4] type=0 (None) color=ffffffff  L: 63 Armor", "link: a plain line")
        Equal(texts[12], "  [5] type=43 (UsageRequirement) color=ffffffff  L: Requires Level 10",
            "link: a line with nothing but its texts has no second row, so the next line follows")
        Equal(texts[13], "      level=10, requirementType=5 (Level), usable=true", "link: the requirement's fields")
        Equal(texts[14], "  [6] type=11 (SellPrice) color=ffffd200  L: ", "link: the price line has no text")
        Equal(texts[15], "      maxPrice=-1, price=204", "link: and its fields")
        Equal(#texts, 15, "link: nothing else")
        Check(not all:find("leftColor", 1, true) and not all:find("GenerateHexColor", 1, true),
            "link: a color is its hex value, not a field and not its methods")
    end

    --------------------------------------------------------------------------------------
    -- What nobody has seen yet is printed too
    --------------------------------------------------------------------------------------

    do
        local data = Tooltip(ON_EQUIP, { hasDynamicData = true, repairCost = 40 })
        data.lines[4].someNewField = 12
        data.lines[4].wrapText = true
        data.lines[4].nested = { b = 2, a = { deep = { deeper = 1 } } }
        data.lines[5].tint = env.CreateColor(1, 0.5, 0, 1)
        data.lines[7] = { type = 99, leftText = "A line of a type no listing has", leftColor = Color(WHITE), bonding = 99 }
        data.lines[8] = { type = 1 }
        answers = { link = data }
        local texts = Rows(LINK, nil)
        Equal(texts[4],
            "  Data: dataInstanceID=0, hasDynamicData=true, hyperlink=" .. LINK
                .. ", id=920001, isAzeriteItem=false, repairCost=40, type=0 (Item)", "new: fields of the answer itself")
        local at = Find(texts, "  [4] type=0 (None) color=ffffffff  L: 63 Armor")
        Check(at ~= nil, "new: the line is there")
        Equal(at and texts[at + 1], "      nested={a={deep={...}}, b=2}, someNewField=12, wrapText=true",
            "new: every field of a line, a table two levels deep")
        at = Find(texts, "  [5] type=43 (UsageRequirement) color=ffffffff  L: Requires Level 10")
        Equal(at and texts[at + 1], "      level=10, requirementType=5 (Level), tint={a=1, b=0, g=0.5, r=1}, usable=true",
            "new: a color under a name nobody knows is its numbers, without a color object's methods")
        at = Find(texts, "  [7] type=99 color=ffffffff  L: A line of a type no listing has")
        Check(at ~= nil, "new: an unknown line type has its number and no name")
        Equal(at and texts[at + 1], "      bonding=99", "new: an unknown enum value has its number and no name")
        Equal(texts[#texts], "  [8] type=1 (Blank)  L: ", "new: a line with no text and no color")
    end

    --------------------------------------------------------------------------------------
    -- An item in a bag slot: the slot's tooltip, then the link's
    --------------------------------------------------------------------------------------

    do
        answers = { bag = Tooltip(ON_EQUIP, { guid = "Item-1-0-4000000000000001", dataInstanceID = 566 }), link = Tooltip(ON_EQUIP) }
        local texts = Rows(LINK, env.ItemLocation:CreateFromBagAndSlot(2, 7))
        Equal(table.concat(asked, "; "), "GetBagItem 2 7; GetHyperlink " .. LINK, "bag: the slot is asked, then the link")
        Equal(texts[2], "[Tooltip Lines (Raw)]", "bag: the slot's tooltip comes first, under the old name")
        Equal(texts[3], "  Asked: C_TooltipInfo.GetBagItem(2, 7)", "bag: what was asked")
        Equal(texts[4],
            "  Data: dataInstanceID=566, guid=Item-1-0-4000000000000001, hyperlink=" .. LINK
                .. ", id=920001, isAzeriteItem=false, type=0 (Item)", "bag: the slot's answer")
        local second = Find(texts, "[Tooltip Lines (Link)]")
        Equal(second, 17, "bag: the link's section follows the slot's fifteen rows and a blank one")
        Equal(texts[16], "", "bag: the blank row")
        Equal(texts[18], "  Asked: C_TooltipInfo.GetHyperlink(link), which the status is computed from", "bag: the link's question")
        Equal(texts[19], "  Data: dataInstanceID=0, hyperlink=" .. LINK .. ", id=920001, isAzeriteItem=false, type=0 (Item)",
            "bag: the link's answer, which differs and is printed")
        Equal(texts[20], "  Lines: 6, each the same as the slot's", "bag: equal lines are not printed twice")
        Equal(#texts, 20, "bag: nothing else")
    end

    -- The copy in the slot is bound and the link cannot know.
    do
        answers = { bag = Tooltip(SOULBOUND), link = Tooltip(ON_EQUIP) }
        local texts = Rows(LINK, env.ItemLocation:CreateFromBagAndSlot(0, 1))
        local second = Find(texts, "[Tooltip Lines (Link)]")
        Check(second ~= nil, "bound: the link's section is there")
        Equal(Count(texts, "      bonding=3 (Soulbound)"), 1, "bound: the slot says soulbound")
        Equal(Count(texts, "      bonding=7 (BindOnEquip)"), 1, "bound: the link says bind on equip")
        Check(second and Find(texts, "      bonding=3 (Soulbound)") < second and Find(texts, "      bonding=7 (BindOnEquip)") > second,
            "bound: each in its own section")
        Equal(Count(texts, "  [4] type=0 (None) color=ffffffff  L: 63 Armor"), 2,
            "bound: where one line differs the link's lines are printed whole")
        Equal(Find(texts, "  Lines: 6, each the same as the slot's"), nil, "bound: and not called the same")
    end

    -- A field alone is a difference: same texts, another value.
    do
        local slot = Tooltip(ON_EQUIP)
        slot.lines[3].isValidItemType = true
        answers = { bag = slot, link = Tooltip(ON_EQUIP) }
        local texts = Rows(LINK, env.ItemLocation:CreateFromBagAndSlot(0, 1))
        Equal(Find(texts, "  Lines: 6, each the same as the slot's"), nil, "field: a field that differs is a difference")
        Equal(Count(texts, "      isValidInvSlot=true, isValidItemType=true"), 1, "field: the slot's value")
        Equal(Count(texts, "      isValidInvSlot=true, isValidItemType=false"), 1, "field: the link's value")
    end

    -- The slot's tooltip is not there.
    do
        answers = { bag = nil, link = Tooltip(ON_EQUIP) }
        local texts = Rows(LINK, env.ItemLocation:CreateFromBagAndSlot(0, 1))
        Equal(texts[3], "  Asked: C_TooltipInfo.GetBagItem(0, 1)", "no slot answer: the question is still named")
        Equal(texts[4], "  Answer: nil", "no slot answer: and that nothing came")
        Equal(texts[6], "[Tooltip Lines (Link)]", "no slot answer: the link's section follows")
        Equal(Count(texts, "  [4] type=0 (None) color=ffffffff  L: 63 Armor"), 1, "no slot answer: with its lines printed")
    end

    --------------------------------------------------------------------------------------
    -- Worn, and nothing to ask about
    --------------------------------------------------------------------------------------

    do
        answers = { equipped = Tooltip(SOULBOUND), link = Tooltip(SOULBOUND) }
        local texts = Rows(LINK, env.ItemLocation:CreateFromEquipmentSlot(9))
        Equal(table.concat(asked, "; "), "GetInventoryItem player 9; GetHyperlink " .. LINK, "worn: the equipment slot is asked")
        Equal(texts[3], "  Asked: C_TooltipInfo.GetInventoryItem(\"player\", 9)", "worn: what was asked")
        Equal(texts[#texts], "  Lines: 6, each the same as the slot's", "worn: the link's lines compared with the slot's")
    end

    do
        answers = {}
        local texts = Rows(nil, nil)
        Equal(#texts, 0, "nothing: no link and no location is no section")
        Equal(#asked, 0, "nothing: and no question")
        texts = Rows(LINK, env.ItemLocation:CreateEmpty())
        Equal(texts[2], "[Tooltip Lines (Raw)]", "empty location: the link alone, under the old name")
        Equal(texts[4], "  Answer: nil", "empty location: a link the client has no tooltip for says so")
    end

    --------------------------------------------------------------------------------------
    -- The test addon's contract: the same asked of every item in the bags
    --------------------------------------------------------------------------------------

    do
        -- The backpack: bracers whose two tooltips agree, a girdle that is bound and worn
        -- down in its slot, an empty slot, and junk whose slot has no tooltip yet.
        local BAG = { [1] = 920001, [2] = 920002, [4] = 920003 }
        local girdleSlot = Tooltip(SOULBOUND)
        girdleSlot.lines[5] = { type = 0, leftText = "Durability 20 / 25", leftColor = Color(WHITE) }
        girdleSlot.lines[6] = { type = 11, leftText = "", leftColor = Color(GOLD), price = 180, maxPrice = -1 }
        girdleSlot.lines[7] = { type = 0, leftText = "Cooldown remaining: 36 min", leftColor = Color(WHITE) }
        local fang = { type = 0, id = 920003,
            lines = { { type = 22, leftText = "Cracked Fang", leftColor = Color(WHITE), quality = 0 } } }
        answers = {
            bySlot = { ["0:1"] = Tooltip(ON_EQUIP), ["0:2"] = girdleSlot },
            byLink = { [game.Link(920001)] = Tooltip(ON_EQUIP), [game.Link(920002)] = Tooltip(ON_EQUIP),
                [game.Link(920003)] = fang },
        }
        game:Set("C_Container.GetContainerNumSlots", function(bag) return bag == 0 and 4 or 0 end)
        game:Set("C_Container.GetContainerItemID", function(bag, slot) return bag == 0 and BAG[slot] or nil end)
        game:Set("C_Container.GetContainerItemLink", function(bag, slot)
            return bag == 0 and BAG[slot] and game.Link(BAG[slot]) or nil
        end)

        local wanted = { ["Core.lua"] = true, ["Runner.lua"] = true, ["Contracts.lua"] = true, ["Plan.lua"] = true }
        local T = H.LoadAddon(client, "CaerdonWardrobe_Tests", H.addonDir .. "/CaerdonWardrobe_Tests",
            function(relative) return not wanted[relative] end)
        client:Fire("ADDON_LOADED", "CaerdonWardrobe_Tests")
        client:Fire("PLAYER_LOGIN")

        local function Run(id)
            id = id or "export.tooltipLines"
            T.RunTests({ match = id, force = true })
            Check(client:TickUntil(function() return not T.IsBusy() end, 120), "contract: the job ends")
            return (T.db.contracts["1.60.1.70938"] or {})[id] or {}
        end

        local result = Run()
        Equal(result.status, "pass", "contract: the export passes on the bags (" .. tostring(result.message) .. ")")
        local detail = result.detail or {}
        Equal(detail.items, 3, "contract: three items, the empty slot left out")
        Equal(detail.linkSame, 1, "contract: one whose link says what its slot says")
        Equal(detail.linkDiffers, 2, "contract: two whose link says something else")
        local differs = detail.differs or {}
        local binding = differs["type=20 (ItemBinding)"] or {}
        Equal(binding.slotOnly, 1, "contract: one binding line only the slot has")
        Equal(binding.linkOnly, 1, "contract: and one only the link has")
        Equal((binding.slotExamples or {})[1], "type=20 (ItemBinding) color=ffffffff  L: Soulbound  {bonding=3 (Soulbound)}",
            "contract: the slot's example, with its field")
        Equal((binding.linkExamples or {})[1],
            "type=20 (ItemBinding) color=ffffffff  L: Binds when equipped  {bonding=7 (BindOnEquip)}", "contract: the link's example")
        local plain = differs["type=0 (None)"] or {}
        Equal(plain.slotOnly, 2, "contract: the durability and the cooldown are the slot's alone")
        Equal((plain.slotExamples or {})[1], "type=0 (None) color=ffffffff  L: Durability 20 / 25",
            "contract: a type that is many kinds of line keeps an example of each: the durability")
        Equal((plain.slotExamples or {})[2], "type=0 (None) color=ffffffff  L: Cooldown remaining: 36 min", "contract: and the cooldown")
        Equal(plain.linkOnly, 0, "contract: the armor line both have is no difference")
        Equal(#(plain.linkExamples or { 1 }), 0, "contract: and no example")
        local price = differs["type=11 (SellPrice)"] or {}
        Equal((price.slotExamples or {})[1], "type=11 (SellPrice) color=ffffd200  L:   {maxPrice=-1, price=180}",
            "contract: a line that differs in a field alone is listed")
        Equal((differs["type=22 (ItemName)"] or {}).linkOnly, 1,
            "contract: every line of a link whose slot has no tooltip is the link's alone")
        Equal((differs["type=43 (UsageRequirement)"] or {}).linkOnly, 1, "contract: a line the slot lacks is the link's alone")
        local sample = detail.sample or {}
        Equal(sample.differs, true, "contract: the sample kept is an item whose two tooltips differ")
        Equal(sample.link, game.Link(920002), "contract: the first such item")
        Equal((sample.rows or {})[2], "[Tooltip Lines (Raw)]", "contract: with the export's rows as they are printed")
        Check(Find(sample.rows or {}, "[Tooltip Lines (Link)]") ~= nil, "contract: both sections")

        -- The same bags a little later add to what is on record: the cooldown has run on,
        -- and the girdle's slot has a line it did not have.
        girdleSlot.lines[7].leftText = "Cooldown remaining: 35 min"
        girdleSlot.lines[8] = { type = 0, leftText = "<Made by Zzyxa>", leftColor = Color(WHITE) }
        result = Run()
        Equal(result.status, "pass", "contract: a second run passes")
        Equal((result.detail or {}).items, 6, "contract: and adds its items to the first run's")
        Equal((((result.detail or {}).differs or {})["type=20 (ItemBinding)"] or {}).slotOnly, 2, "contract: and its differences")
        plain = ((result.detail or {}).differs or {})["type=0 (None)"] or {}
        Equal(plain.slotOnly, 5, "contract: five plain lines of the slot's alone by now")
        Equal(#(plain.slotExamples or {}), 3, "contract: of three kinds, the cooldown with another number being no new one")
        Equal((plain.slotExamples or {})[3], "type=0 (None) color=ffffffff  L: <Made by Zzyxa>", "contract: the new kind is added")

        -- An export that prints the fields of some lines only, as it did before, fails.
        local real = feature.GetTooltipReportRows
        feature.GetTooltipReportRows = function(self, ...)
            local kept = {}
            for _, row in ipairs(real(self, ...)) do
                if not row.text:find("bonding=", 1, true) then
                    kept[#kept + 1] = row
                end
            end
            return kept
        end
        result = Run()
        Equal(result.status, "fail", "contract: an export without a line's field fails")
        Check(tostring(result.message):find("line 2 (type 20) does not show its field bonding", 1, true) ~= nil,
            "contract: and names the line and the field (" .. tostring(result.message) .. ")")

        -- One that drops a line fails too.
        feature.GetTooltipReportRows = function(self, ...)
            local kept = {}
            for _, row in ipairs(real(self, ...)) do
                if not row.text:find("63 Armor", 1, true) then
                    kept[#kept + 1] = row
                end
            end
            return kept
        end
        result = Run()
        Equal(result.status, "fail", "contract: an export without a line fails")
        Check(tostring(result.message):find("5 rows for 6 tooltip lines", 1, true) ~= nil,
            "contract: and counts (" .. tostring(result.message) .. ")")

        -- So does one that is whole for the slot and leaves a field out for the link.
        feature.GetTooltipReportRows = function(self, ...)
            local kept, inLink = {}, false
            for _, row in ipairs(real(self, ...)) do
                inLink = inLink or row.text == "[Tooltip Lines (Link)]"
                if not (inLink and row.text:find("quality=", 1, true)) then
                    kept[#kept + 1] = row
                end
            end
            return kept
        end
        result = Run()
        Equal(result.status, "fail", "contract: an export without a field of the link's line fails")
        Check(tostring(result.message):find(", link: line 1 (type 22) does not show its field quality", 1, true) ~= nil,
            "contract: and says it is the link's (" .. tostring(result.message) .. ")")

        -- An addon without the function is skipped, not failed.
        feature.GetTooltipReportRows = nil
        T.db.contracts["1.60.1.70938"]["export.tooltipLines"] = nil
        result = Run()
        Equal(result.status, "skip", "contract: an addon without the function is skipped")
        feature.GetTooltipReportRows = real

        ----------------------------------------------------------------------------------
        -- The contract tooltip.gameOnly, against a model of the tooltip frame
        ----------------------------------------------------------------------------------

        -- How this client behaves; each case below changes one thing.
        local behaves = { fresh = true, callbacks = true, leaks = false, insecure = {} }
        local shared, handedOut
        local postCalls = {}
        game:Set("TooltipDataProcessor.AddTooltipPostCall", function(_, callback) postCalls[#postCalls + 1] = callback end)
        -- Straight into the client's globals: it has both names already and asks the game once.
        rawset(env, "issecurevariable", function(_, name)
            if behaves.insecure[name] then
                return false, behaves.insecure[name]
            end
            return true, nil
        end)
        rawset(env, "InCombatLockdown", function() return false end)
        answers = {
            makeSlot = function()
                if behaves.fresh then
                    handedOut = Tooltip(SOULBOUND)
                else
                    shared = shared or Tooltip(SOULBOUND)
                    handedOut = shared
                end
                return handedOut
            end,
            makeLink = function() return Tooltip(ON_EQUIP) end,
        }

        -- The frame: it asks for data of its own, shows each line, then runs what addons
        -- registered. A leaking client writes a line added to the frame into the data too.
        local tooltipsMade = 0
        local function ModelTooltip(name)
            tooltipsMade = tooltipsMade + 1
            local tooltip = { shown = {} }
            function tooltip:SetOwner() end
            function tooltip:Hide() end
            function tooltip:NumLines() return #self.shown end
            function tooltip:AddLine(text)
                self.shown[#self.shown + 1] = text
                local index = #self.shown
                rawset(env, name .. "TextLeft" .. index, { GetText = function() return self.shown[index] end })
                if behaves.leaks and self.data and self.filled then
                    self.data.lines[#self.data.lines + 1] = { type = 0, leftText = text }
                end
            end
            function tooltip:SetBagItem(bag, slot)
                self.shown, self.filled = {}, false
                self.data = env.C_TooltipInfo.GetBagItem(bag, slot)
                for _, line in ipairs(self.data.lines) do
                    self:AddLine(line.leftText)
                end
                self.filled = true
                if behaves.callbacks then
                    for _, callback in ipairs(postCalls) do
                        callback(self, self.data)
                    end
                end
            end
            return tooltip
        end
        local createFrame = env.CreateFrame
        rawset(env, "CreateFrame", function(frameType, name, ...)
            if frameType == "GameTooltip" then
                return ModelTooltip(name)
            end
            return createFrame(frameType, name, ...)
        end)

        local function GameOnly(change)
            behaves = { fresh = true, callbacks = true, leaks = false, insecure = {} }
            shared = nil
            for key, value in pairs(change or {}) do
                behaves[key] = value
            end
            T.db.contracts["1.60.1.70938"]["tooltip.gameOnly"] = nil
            return Run("tooltip.gameOnly")
        end

        result = GameOnly()
        Equal(result.status, "pass", "game only: a client that keeps frame and data apart passes (" .. tostring(result.message) .. ")")
        Equal((result.detail or {}).dataLines, 6, "game only: the data has the game's six lines")
        Equal((result.detail or {}).frameLines, 7, "game only: the frame has them and the added one")
        Equal(#((result.detail or {}).replaced or { 1 }), 0, "game only: no function is called replaced")
        Check(((result.detail or {}).functions or 0) >= 2, "game only: the functions were looked at")
        Equal(#postCalls, 1, "game only: one callback registered")

        result = GameOnly({ leaks = true })
        Equal(result.status, "pass", "game only: a frame that writes the added line into its own table harms nobody")
        result = GameOnly({ leaks = true, fresh = false })
        Equal(result.status, "fail", "game only: unless that table is the one everybody is handed")
        Check(tostring(result.message):find("is in the data of C_TooltipInfo.GetBagItem", 1, true) ~= nil,
            "game only: and it says where the line turned up (" .. tostring(result.message) .. ")")

        result = GameOnly({ fresh = false })
        Equal(result.status, "fail", "game only: one table for every call fails, whoever changes it")
        Check(tostring(result.message):find("return the same table", 1, true) ~= nil,
            "game only: and says so (" .. tostring(result.message) .. ")")

        result = GameOnly({ insecure = { GetHyperlink = "SomeAddon" } })
        Equal(result.status, "fail", "game only: a function an addon replaced fails")
        Check(tostring(result.message):find("GetHyperlink (SomeAddon)", 1, true) ~= nil,
            "game only: and names the function and the addon (" .. tostring(result.message) .. ")")

        result = GameOnly({ callbacks = false })
        Equal(result.status, "fail", "game only: when the added line never reached the frame, nothing was shown")
        Check(tostring(result.message):find("so the test shows nothing", 1, true) ~= nil,
            "game only: and that is what it says (" .. tostring(result.message) .. ")")

        Equal(#postCalls, 1, "game only: the callback is registered once however often it runs")
        Equal(tooltipsMade, 1, "game only: and one frame made")

        -- The callback stays registered for the session: it must leave every other tooltip,
        -- the player's among them, as it is.
        behaves = { fresh = true, callbacks = true, leaks = false, insecure = {} }
        local players = ModelTooltip("PlayersTooltip")
        players:SetBagItem(0, 1)
        Equal(players:NumLines(), 6, "game only: another tooltip filled afterwards gets no line from the test")

        Equal(#T.db.errors, 0, "contract: no error of the tests' own")
        for _, entry in ipairs(T.db.errors) do
            Check(false, "contract: " .. tostring(entry.message))
        end
    end

    --------------------------------------------------------------------------------------
    -- A mount and a pet: the journal's answers in their own sections
    --------------------------------------------------------------------------------------

    do
        -- What the rest of the export asks for and this client has no answer to.
        game:Set("C_AddOns.GetAddOnInfo", function(name) return name, name, "", true, nil, "INSECURE" end)
        game:Set("PLAYER_FACTION_GROUP", { [0] = "Horde", [1] = "Alliance" })

        local journal = { mountCollected = false, petsCollected = 0 }
        game:Set("C_MountJournal.GetMountFromItem", function(itemID) return itemID == 920004 and 77 or nil end)
        game:Set("C_MountJournal.GetMountInfoByID", function(mountID)
            if mountID == 77 then
                return "Dun Ram", 7770, 132248, false, true, 3, false, true, 1, false, journal.mountCollected, 77
            end
        end)
        game:Set("C_PetJournal.GetPetInfoByItemID", function(itemID)
            if itemID == 920005 then
                return "Moss Toad", 132230, 5, 4400, "Vendor", "A toad.", false, true, true, false, true, 5500, 880
            end
        end)
        game:Set("C_PetJournal.GetNumCollectedInfo", function(speciesID)
            if speciesID == 880 then
                return journal.petsCollected, 3
            end
            return 0, 0
        end)

        -- The rows of one section, from its title to the blank line after it.
        local function Section(link, title)
            local payload = feature:BuildClipboardPayload(env.CaerdonItem:CreateFromItemLink(link))
            local rows, inside = {}, false
            for line in (payload .. "\n"):gmatch("(.-)\n") do
                if line == title then
                    inside = true
                elseif inside and line == "" then
                    break
                elseif inside then
                    rows[#rows + 1] = line
                end
            end
            return inside and table.concat(rows, "\n") or nil, payload
        end

        local mount = Section(game.Link(920004), "[Mount]")
        Equal(mount, table.concat({
            "  Mount ID: 77", "  Spell ID: 7770", "  Name: Dun Ram", "  Is Collected: false", "  Is Usable: true",
            "  Is Faction Specific: true", "  Faction ID: 1", "  Hidden On Character: false", "  Is Equipment: nil",
            "  Equipment Applied: nil", "  Needs Item: true" }, "\n"), "mount: the journal's answer, uncollected")
        journal.mountCollected = true
        mount = Section(game.Link(920004), "[Mount]")
        Check(mount and mount:find("  Is Collected: true\n", 1, true) and mount:find("  Needs Item: false", 1, true),
            "mount: collected once the journal says so (" .. tostring(mount) .. ")")

        local pet = Section(game.Link(920005), "[Pet]")
        Equal(pet, table.concat({
            "  Species ID: 880", "  Name: Moss Toad", "  Num Collected: 0", "  Limit: 3", "  Is Unique: false",
            "  Is Tradeable: true", "  Is Obtainable: true", "  Can Battle: true", "  Needs Item: true" }, "\n"),
            "pet: the journal's answer, none collected")
        journal.petsCollected = 1
        pet = Section(game.Link(920005), "[Pet]")
        Check(pet and pet:find("  Num Collected: 1\n", 1, true) and pet:find("  Needs Item: false", 1, true),
            "pet: one collected (" .. tostring(pet) .. ")")

        local none, payload = Section(LINK, "[Mount]")
        Equal(none, nil, "a piece of armor has no mount section")
        Check(not payload:find("[Pet]", 1, true), "and no pet section")
    end

    Equal(#client.errors, 0, "no error reached the error handler")
    for _, message in ipairs(client.errors) do
        Check(false, message)
    end
end
