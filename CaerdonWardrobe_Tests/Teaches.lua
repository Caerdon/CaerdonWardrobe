-- What teaches what: every item of the classes Consumable and Recipe, by what its tooltip
-- says it teaches.
--
-- The addon takes an item for a recipe by its class, and by seven English words before a
-- colon where the client files a recipe under Consumable; which items those are is written
-- down nowhere. A tooltip has a line of a type of its own for what an item teaches
-- (ItemSpellTriggerLearn) with the spell's ID, and for a recipe item that spell is the recipe
-- (the contract recipe.taughtSpell). So the line may be the mark the words stand in for.
-- This asks a client: it walks every item ID the client has a record of, loads the items of
-- the two classes, and counts them by shape:
--
--   the class and subclass, what the addon takes the item for, how many teaching lines its
--   tooltip has, whether it has a skill requirement line ("Requires Tailoring (50)"), and
--   what the client says of the spell the item itself teaches: whether it is a recipe of a
--   trade skill (C_TradeSkillUI.GetTradeSkillLineForRecipe), whether
--   C_TradeSkillUI.GetRecipeInfo answers for it, and C_TradeSkillUI.IsRecipeProfessionLearned.
--   That spell is the last teaching line's: a recipe's tooltip has the lines of the item it
--   makes before its own, and the made item may teach something itself (seen in a WoW
--   Forever client: four schematics for mechanical pets). Such an item is kept with all of
--   its spells.
--
--   For an item that teaches, also what would say whether this toon can learn it and has:
--   whether the tooltip holds a made item's lines, its class line ("Classes: Hunter") and its
--   level line, each met or not by the line's own field, whether it says "Already known", and
--   whether the client calls the taught spell known (C_SpellBook.IsSpellKnown). A star on a
--   class book or a rune would rest on these, and nothing on file says what they are there.
--
-- A shape keeps a few items as examples, and more where it is one of those asked about:
--   a Consumable that teaches (a recipe filed under Consumable, if its spell is a recipe);
--   an item the addon takes for a recipe that is none by its class (the seven words);
--   a Recipe that teaches and has no skill requirement line (the tooltip then says nothing
--   about whether the toon has the profession).
--
-- Nothing is decided from it. It is some thousands of item loads, a hundred at a time, each
-- hundred waited for, which presses on the client's item cache (ItemCache.lua): stand still
-- with the bags closed. A run stops after four minutes and the next one goes on from there.
--
-- An item the client has a record of is not one its game has: asked for, such an item
-- mostly brings no answer at all, so a hundred is given up on once nothing more has come
-- for a moment.

local _, T = ...

-- A scenario of the offline harness makes these small.
T.TeachesLimits = {
    firstID = 1,
    lastID = 450000, -- item IDs are walked up to here
    batch = 100,     -- items asked for at a time
    seconds = 240,   -- one run
}
local QUIET = 0.3           -- seconds without a new arrival after which a hundred is given up on
local BATCH_TIMEOUT = 1.5
local WALK_PER_FRAME = 3000 -- item IDs looked at between two frames
local EXAMPLES = 4          -- items kept per shape
local EXAMPLES_ASKED = 80   -- and per shape that is asked about

local function Cached(itemID)
    return C_Item.IsItemDataCachedByID(itemID) == true
end

-- What a C_TradeSkillUI function answers for a spell, or "<error>" where it raises one for a
-- spell that is no recipe.
local function Ask(name, spellID)
    local fn = C_TradeSkillUI[name]
    if type(fn) ~= "function" then
        return "<no function>"
    end
    local ok, first, second = pcall(fn, spellID)
    if not ok then
        return "<error>"
    end
    return first, second
end

local function YesNo(value)
    return value and "yes" or "no"
end

-- The record a run adds to: the one saved for this build while its walk is not over.
local function OpenRecord(restart)
    local client, toon = T.GetClient(), T.GetToon()
    local record = T.db.teaches
    if restart or type(record) ~= "table" or record.build ~= client.build or record.done or not record.cursor then
        record = {
            build = client.build,
            flavor = client.flavor,
            cursor = T.TeachesLimits.firstID,
            runs = 0,
            seconds = 0,
            looked = 0,
            records = {},   -- class name -> items the client has a record of
            loaded = {},    -- class name -> items whose data came
            notLoaded = 0,
            noTooltip = 0,
            shapes = {},    -- shape -> { count, asked, examples }
        }
        T.db.teaches = record
    end
    record.at = GetServerTime()
    record.toon = toon.key
    record.runs = record.runs + 1
    record.stoppedBy = nil

    -- What IsRecipeProfessionLearned has to be read against: the toon's professions, and
    -- whether a profession window has given its list.
    local professions = {}
    for _, profession in ipairs(toon.professions or {}) do
        professions[#professions + 1] = ("%s %s"):format(tostring(profession.name), tostring(profession.rank))
    end
    record.professions = professions
    record.tradeSkillReady = C_TradeSkillUI.IsTradeSkillReady() == true
    local recorded = CaerdonRecipe and CaerdonRecipe.GetRecordedRecipes and CaerdonRecipe:GetRecordedRecipes() or {}
    record.recordedLists = T.SortedKeys(recorded)
    return record
end

-- Reads one loaded item into the record. False while its tooltip is still the client's
-- "retrieving" one.
local function ReadItem(record, entry, lineTypes)
    local itemID = entry.id
    local data = C_TooltipInfo.GetHyperlink("item:" .. itemID)
    local lines = type(data) == "table" and data.lines or nil
    local first = lines and lines[1]
    if not first or issecretvalue(first.leftText) or first.leftText == RETRIEVING_ITEM_INFO then
        return false
    end

    local function Text(line)
        if not issecretvalue(line.leftText) and type(line.leftText) == "string" then
            return line.leftText
        end
        return "?"
    end
    -- A requirement line as kept: its text, whether the toon meets it by the line's own
    -- field, and how many teaching lines stood above it.
    local function Requirement(line, above)
        local met = "?"
        if not issecretvalue(line.usable) and type(line.usable) == "boolean" then
            met = line.usable and "met" or "unmet"
        end
        return { text = Text(line), met = met, above = above }
    end

    local spells, skillLine, saysKnown, hasMadeItem = {}, nil, false, false
    local classLine, levelLine
    for _, line in ipairs(lines) do
        if issecretvalue(line.type) or issecretvalue(line.spellID) or issecretvalue(line.requirementType) then
            -- Nothing to read.
        elseif line.type == lineTypes.learn then
            spells[#spells + 1] = type(line.spellID) == "number" and line.spellID or 0
        elseif lineTypes.nested ~= nil and line.type == lineTypes.nested then
            hasMadeItem = true
        elseif line.type == lineTypes.requirement then
            if lineTypes.skill ~= nil and line.requirementType == lineTypes.skill then
                skillLine = Text(line)
            elseif lineTypes.known ~= nil and line.requirementType == lineTypes.known then
                saysKnown = true
            elseif lineTypes.class ~= nil and line.requirementType == lineTypes.class then
                -- The last of its kind counts, as for the level: with a made item's lines in
                -- the tooltip the made item's own come first.
                classLine = Requirement(line, #spells)
            elseif lineTypes.level ~= nil and line.requirementType == lineTypes.level then
                levelLine = Requirement(line, #spells)
            end
        end
    end

    local addonType = CaerdonItem:CreateFromItemID(itemID):GetCaerdonItemType()
    local spell = spells[#spells]
    local tradeSkill, tradeSkillName, info, professionLearned
    if spell and spell > 0 then
        tradeSkill, tradeSkillName = Ask("GetTradeSkillLineForRecipe", spell)
        info = Ask("GetRecipeInfo", spell)
        professionLearned = Ask("IsRecipeProfessionLearned", spell)
    end
    local isRecipeSpell = type(tradeSkill) == "number" and tradeSkill > 0

    local shape = ("%s / %s, the addon: %s; teaching lines: %d; skill line: %s"):format(entry.className,
        tostring(entry.subType), tostring(addonType), #spells, YesNo(skillLine))
    if spell then
        -- A marker ("<error>") is kept as it is; anything else is there or not.
        local function Answer(value, there)
            if type(value) == "string" and value:sub(1, 1) == "<" then
                return value
            end
            return YesNo(there)
        end
        shape = shape .. ("; the spell: of a trade skill %s, recipe info %s, profession learned %s"):format(
            Answer(tradeSkill, isRecipeSpell), Answer(info, type(info) == "table"), tostring(professionLearned))
    end
    local spellKnown
    if spell then
        if spell > 0 then
            local ok, known = pcall(C_SpellBook.IsSpellKnown, spell)
            spellKnown = ok and tostring(known) or "<error>"
        end
        shape = shape .. ("; a made item's lines: %s; class line: %s; level line: %s; says known: %s; spell known: %s"):format(
            YesNo(hasMadeItem), classLine and classLine.met or "none", levelLine and levelLine.met or "none",
            YesNo(saysKnown), tostring(spellKnown))
    end

    local isRecipeClass = entry.classID == Enum.ItemClass.Recipe
    local asked = (not isRecipeClass and #spells > 0)
        or (not isRecipeClass and addonType == CaerdonItemType.Recipe)
        or (isRecipeClass and #spells > 0 and not skillLine)
    local tally = record.shapes[shape]
    if not tally then
        tally = { count = 0, asked = asked or nil, examples = {} }
        record.shapes[shape] = tally
    end
    tally.count = tally.count + 1
    if #tally.examples < (asked and EXAMPLES_ASKED or EXAMPLES) then
        local example = { id = itemID, name = C_Item.GetItemNameByID(itemID) }
        if spell then
            example.spell = spell
            example.spellName = spell > 0 and C_Spell.GetSpellName(spell) or nil
            example.tradeSkill = isRecipeSpell and tostring(tradeSkillName or tradeSkill) or nil
            example.infoName = type(info) == "table" and info.name or nil
            example.skillLine = skillLine
            -- With how many of the teaching lines stood above each: where the tooltip holds
            -- a made item's lines, that says whose requirement it is.
            if classLine then
                example.classLine = ("%s (%s, below %d of %d teaching lines)"):format(classLine.text, classLine.met,
                    classLine.above, #spells)
            end
            if levelLine then
                example.levelLine = ("%s (%s, below %d of %d teaching lines)"):format(levelLine.text, levelLine.met,
                    levelLine.above, #spells)
            end
        end
        if #spells > 1 then
            example.spells = table.concat(spells, ", ")
        end
        tally.examples[#tally.examples + 1] = example
    end
    return true
end

-- Inside a job: asks for a hundred items and reads those that came.
local function ReadBatch(record, batch, lineTypes)
    for _, entry in ipairs(batch) do
        if not Cached(entry.id) then
            C_Item.RequestLoadItemDataByID(entry.id)
        end
    end
    local most, since = -1, GetTime()
    T.WaitUntil(function()
        local there = 0
        for _, entry in ipairs(batch) do
            if Cached(entry.id) then
                there = there + 1
            end
        end
        if there > most then
            most, since = there, GetTime()
        end
        return there == #batch or GetTime() - since > QUIET
    end, BATCH_TIMEOUT)

    local again = {}
    for _, entry in ipairs(batch) do
        if not Cached(entry.id) then
            record.notLoaded = record.notLoaded + 1
        else
            record.loaded[entry.className] = (record.loaded[entry.className] or 0) + 1
            if not ReadItem(record, entry, lineTypes) then
                again[#again + 1] = entry
            end
        end
    end
    if #again > 0 then
        T.Sleep(0.3)
        for _, entry in ipairs(again) do
            if not ReadItem(record, entry, lineTypes) then
                record.noTooltip = record.noTooltip + 1
            end
        end
    end
end

-- Inside a job.
local function Walk(record)
    local lineTypes = {
        learn = Enum.TooltipDataLineType.ItemSpellTriggerLearn,
        requirement = Enum.TooltipDataLineType.UsageRequirement,
        nested = Enum.TooltipDataLineType.NestedBlock,
        skill = Enum.TooltipDataUsageRequirementType and Enum.TooltipDataUsageRequirementType.Skill,
        known = Enum.TooltipDataUsageRequirementType and Enum.TooltipDataUsageRequirementType.NotAlreadyKnown,
        class = Enum.TooltipDataUsageRequirementType and Enum.TooltipDataUsageRequirementType.RaceClass,
        level = Enum.TooltipDataUsageRequirementType and Enum.TooltipDataUsageRequirementType.Level,
    }
    if type(lineTypes.learn) ~= "number" then
        record.stoppedBy = "the client has no line type for what an item teaches"
        return
    end
    local classNames = { [Enum.ItemClass.Consumable] = "Consumable", [Enum.ItemClass.Recipe] = "Recipe" }

    local limits = T.TeachesLimits
    local startedAt, lastSaid = GetTime(), GetTime()
    local itemID, walked, batch = record.cursor, 0, {}
    while itemID <= limits.lastID do
        local _, _, subType, _, _, classID = C_Item.GetItemInfoInstant(itemID)
        if classID ~= nil then
            record.lastRecord = itemID
        end
        local className = classID ~= nil and classNames[classID] or nil
        if className then
            record.records[className] = (record.records[className] or 0) + 1
            batch[#batch + 1] = { id = itemID, classID = classID, className = className, subType = subType }
        end
        itemID = itemID + 1
        walked = walked + 1
        if #batch >= limits.batch then
            ReadBatch(record, batch, lineTypes)
            batch = {}
            record.cursor = itemID
            if GetTime() - startedAt > limits.seconds then
                record.stoppedBy = ("%s seconds"):format(tostring(limits.seconds))
                break
            end
            if GetTime() - lastSaid > 30 then
                lastSaid = GetTime()
                T.Print("what teaches what: at item %d, %d not loaded so far...", itemID, record.notLoaded)
            end
        elseif walked % WALK_PER_FRAME == 0 then
            T.Yield()
        end
    end
    if not record.stoppedBy then
        if #batch > 0 then
            ReadBatch(record, batch, lineTypes)
        end
        record.cursor, record.done = nil, true
        record.stoppedBy = "every item ID was looked at"
    end
    record.looked = record.looked + walked
    record.seconds = math.floor((record.seconds + GetTime() - startedAt) * 10 + 0.5) / 10
end

-- /cwtest teaches [restart]
function T.TeachesCommand(rest)
    if T.IsBusy() then
        T.Print("something else is running (%s)", tostring(T.ActiveJob()))
        return
    end
    local restart = rest ~= nil and rest:match("^%s*restart") ~= nil
    T.Start("teaches", function()
        if InCombatLockdown() then
            T.Print("out of combat only.")
            return
        end
        local record = OpenRecord(restart)
        if record.runs > 1 then
            T.Print("what teaches what: going on from item %d (run %d); stand still with the bags closed, up to %s seconds...",
                record.cursor, record.runs, tostring(T.TeachesLimits.seconds))
        else
            T.Print("what teaches what: loading every Consumable and Recipe the client has; stand still with the bags closed, up to %s seconds...",
                tostring(T.TeachesLimits.seconds))
        end
        Walk(record)

        local loaded, asked = 0, 0
        for _, count in pairs(record.loaded) do
            loaded = loaded + count
        end
        for _, tally in pairs(record.shapes) do
            if tally.asked then
                asked = asked + tally.count
            end
        end
        T.Print("what teaches what: %d items read in %d shapes, %d of them of a shape that was asked about; %d did not load; stopped because: %s.",
            loaded, #T.SortedKeys(record.shapes), asked, record.notLoaded, tostring(record.stoppedBy))
        if record.done then
            T.Print("/reload saves it.")
        else
            T.Print("/cwtest teaches goes on from item %d; a /reload in between keeps what was read.", record.cursor)
        end
        if T.OnTestsFinished then
            T.OnTestsFinished()
        end
    end)
end
