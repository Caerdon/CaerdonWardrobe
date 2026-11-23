-- Set bonuses.
--
-- What putting a piece on would do to the bonuses of the item sets the toon wears pieces of (a
-- tier set and the like; not a saved gear set): which bonus it would bring, which it would
-- end. An upgrade's arrow goes by the piece alone, and the piece it takes the place of may be
-- one of the four that hold a bonus. The piece's tooltip says so in a line
-- (features/Tooltip.lua, AddSetBonusChanges; Tooltip.ShowSetBonusChanges). No icon and no
-- verdict is made from it (author decision: a warning, in both directions, and no arrow held
-- back).
--
-- The client has no function for any of it: none gives the pieces a bonus needs, none the
-- pieces worn of a set. It is all on a piece's tooltip, as lines written from three of the
-- client's format strings, which are read back through NS.FormatPattern:
--   ITEM_SET_NAME        "Defias Leather (1/5)": the set, and how many of its pieces are worn.
--                        Only the first number is used: the second, and the list of pieces
--                        under the line, were seen to change with what is worn (retail).
--   ITEM_SET_BONUS_GRAY  "(2) Set: +5 Arcane Resistance.": a bonus the toon does not have, and
--                        the pieces it begins at.
--   ITEM_SET_BONUS       "Set: +5 Arcane Resistance.": a bonus the toon has. No number.
-- So what a piece would bring is read off its own tooltip (the pieces worn, one more, and the
-- number of each bonus not had). What it would end is not: a bonus the toon has is written
-- without its number. That number is remembered instead, from any tooltip of the set that
-- showed the bonus while the toon did not have it (CaerdonSetBonusData, for the account: it is
-- the game's data, not the toon's). A tooltip is seen whenever a piece of the set is judged for
-- its icon (CaerdonItem.lua hands it over, NoteTooltip) or hovered, and a piece taken off lies
-- in the bags with fewer worn, so the number is mostly there before it is needed. Where it is
-- not, the line says "may".
--
-- One thing is taken from the tooltips seen and not from a function: the bonuses stand in the
-- order of their pieces, fewest first (every recorded tooltip of both clients; 2, 3, 4, 5 on WoW
-- Forever). By it a bonus whose number is not remembered needs no more pieces than a later one
-- whose number is. A set whose remembered numbers are not in that order is not reasoned about
-- that way.
--
-- What is worn alone is looked at, not a saved gear set that is not on.
--
-- CaerdonItemMixin:GetSetBonusChanges() is the entry point for callers; the Debug Frame export
-- prints what this file made of a piece under "[Set Bonuses]" (CaerdonSetBonuses:Describe).

local ADDON_NAME, NS = ...

CaerdonSetBonuses = {}

-- Saved: CaerdonSetBonusData[set] = {
--   name = the set's name as the tooltip had it,
--   bonuses = how many bonus lines the set's tooltip had,
--   pieces = { [position among those lines] = the pieces the bonus begins at },
-- }
-- A set is filed under its ID where the item info names one, else under its name.
local function Store()
    if type(CaerdonSetBonusData) ~= "table" then
        CaerdonSetBonusData = {}
    end
    return CaerdonSetBonusData
end

-- Made at the first reading and not as the file loads, so that a session that never meets a
-- set's piece asks for none of the three strings.
local matchers
local function Matchers()
    if matchers == nil then
        local name = NS.FormatPattern.Compile(ITEM_SET_NAME)
        local needs = NS.FormatPattern.Compile(ITEM_SET_BONUS_GRAY)
        local has = NS.FormatPattern.Compile(ITEM_SET_BONUS)
        matchers = (name and needs and has) and { name = name, needs = needs, has = has } or false
    end
    return matchers or nil
end

local function LineText(line)
    local text = type(line) == "table" and line.leftText or nil
    if text == nil or issecretvalue(text) or type(text) ~= "string" then
        return ""
    end
    return text
end

-- A tooltip's lines about an item set, or nil where it has none:
--   { name, worn (pieces of the set that are on), total,
--     bonuses = { { needs = pieces, text } for one the toon does not have,
--                 { active = true, text } for one it has, ... } in the tooltip's order,
--     legacy = the client says the set's bonuses no longer work }
-- The set's line is known by the client's format and by what follows it: its pieces, each on a
-- line that begins with a blank. Another line of that shape with none under it is passed over.
function CaerdonSetBonuses:Read(tooltipData)
    local lines = type(tooltipData) == "table" and tooltipData.lines or nil
    local m = Matchers()
    if type(lines) ~= "table" or not m then
        return nil
    end
    local reading, pieces = nil, 0
    for _, line in ipairs(lines) do
        local text = LineText(line)
        local known = false
        if reading then
            local needs, needsText = m.needs:Match(text)
            needs = tonumber(needs)
            local hasText = not needs and m.has:Match(text) or nil
            if needs then
                reading.bonuses[#reading.bonuses + 1] = { needs = needs, text = needsText }
                known = true
            elseif hasText then
                reading.bonuses[#reading.bonuses + 1] = { active = true, text = hasText }
                known = true
            elseif text == ITEM_SET_LEGACY_INACTIVE_BONUS then
                reading.legacy = true
                known = true
            elseif not text:find("%S") or text == ITEM_SET_BONUS_NO_VALID_SPEC then
                known = true
            elseif #reading.bonuses == 0 and not reading.legacy and text:find("^%s") then
                pieces = pieces + 1
                known = true
            end
            if not known then
                if pieces > 0 then
                    -- Past the set's lines.
                    break
                end
                reading = nil
            end
        end
        if not reading then
            local name, worn, total = m.name:Match(text)
            worn, total = tonumber(worn), tonumber(total)
            if name and worn and total then
                reading, pieces = { name = name, worn = worn, total = total, bonuses = {} }, 0
            end
        end
    end
    if reading and pieces == 0 then
        return nil
    end
    return reading
end

-- What a tooltip showed of a set is kept: the pieces of each bonus the toon does not have.
-- A set whose tooltip has another number of bonus lines than it had is begun anew (a spec's
-- own bonuses, a patch), and a number that cannot be so (more pieces than are worn, for a bonus
-- the toon has) is dropped.
function CaerdonSetBonuses:Remember(key, reading)
    if key == nil or type(reading) ~= "table" or reading.legacy or #reading.bonuses == 0 then
        return
    end
    local store = Store()
    local count = #reading.bonuses
    local known = store[key]
    if type(known) ~= "table" or type(known.pieces) ~= "table" or known.bonuses ~= count then
        known = nil
        store[key] = nil
    end
    for position, bonus in ipairs(reading.bonuses) do
        if bonus.needs then
            if not known then
                known = { name = reading.name, bonuses = count, pieces = {} }
                store[key] = known
            end
            known.pieces[position] = bonus.needs
        elseif known and known.pieces[position] and known.pieces[position] > reading.worn then
            known.pieces[position] = nil
        end
    end
end

-- The pieces each bonus of a reading begins at, as far as that is known (position -> pieces):
-- from its own line for a bonus the toon does not have, remembered for one it has. Second:
-- whether the known numbers stand in ascending order. What is remembered has been held against
-- this reading by then (Remember, which ReadLink calls for every reading it makes).
local function PiecesOf(key, reading)
    local known = Store()[key]
    local remembered = type(known) == "table" and type(known.pieces) == "table" and known.pieces or nil
    local pieces, ordered, last = {}, true, 0
    for position, bonus in ipairs(reading.bonuses) do
        local count = bonus.needs
        if not count and remembered and type(remembered[position]) == "number" then
            count = remembered[position]
        end
        if count then
            pieces[position] = count
            if count < last then
                ordered = false
            end
            last = count
        end
    end
    return pieces, ordered
end

-- A link's set lines, with the set's ID where the item info names one (setID) and what the set
-- is filed under (key). nil where the tooltip has none; second: the tooltip is not there yet.
local function ReadLink(link)
    local data = C_TooltipInfo and C_TooltipInfo.GetHyperlink(link) or nil
    if type(data) ~= "table" or type(data.lines) ~= "table" then
        return nil, true
    end
    local reading = CaerdonSetBonuses:Read(data)
    if not reading then
        for _, line in ipairs(data.lines) do
            if LineText(line) == RETRIEVING_ITEM_INFO then
                return nil, true
            end
        end
        return nil, false
    end
    local setID = select(16, C_Item.GetItemInfo(link))
    reading.setID = type(setID) == "number" and setID or nil
    reading.key = reading.setID or reading.name
    CaerdonSetBonuses:Remember(reading.key, reading)
    return reading, false
end

-- From the status code, which has both in hand for every piece it judges: a tooltip of a set's
-- piece, for what it shows of the set's bonuses. Nothing is asked of the client.
function CaerdonSetBonuses:NoteTooltip(setID, tooltipData)
    if type(setID) ~= "number" then
        return
    end
    local reading = self:Read(tooltipData)
    if reading then
        self:Remember(setID, reading)
    end
end

local function SameSet(a, b)
    if a.setID and b.setID then
        return a.setID == b.setID
    end
    return a.name == b.name
end

-- What a change of `delta` pieces worn does to one set's bonuses, added to entries:
--   { kind = "gain", set = name, pieces }   a bonus it would bring
--   { kind = "loss", set = name, pieces }   a bonus it would end
--   { kind = "maybe", set = name }          a bonus the toon has that may end: the pieces it
--                                           begins at are not remembered
local function AddSetChange(entries, reading, delta)
    if reading.legacy or delta == 0 then
        return
    end
    local newCount = math.max(reading.worn + delta, 0)
    local pieces, ordered = PiecesOf(reading.key, reading)
    if delta > 0 then
        local said = {}
        for _, bonus in ipairs(reading.bonuses) do
            if bonus.needs and bonus.needs <= newCount and not said[bonus.needs] then
                said[bonus.needs] = true
                entries[#entries + 1] = { kind = "gain", set = reading.name, pieces = bonus.needs }
            end
        end
        return
    end

    local lost, counts = {}, {}
    for position, bonus in ipairs(reading.bonuses) do
        local count = pieces[position]
        if bonus.active and count and count > newCount and not lost[count] then
            lost[count] = true
            counts[#counts + 1] = count
        end
    end
    -- A bonus the toon has whose pieces are not remembered: no more than are worn, and no more
    -- than a later bonus it has (the order of the lines). It ends if it needs more than would
    -- be left; where every such number already has its line, nothing more is to be said.
    local maybe = false
    for position, bonus in ipairs(reading.bonuses) do
        if bonus.active and not pieces[position] then
            local upper = reading.worn
            if ordered then
                for later = position + 1, #reading.bonuses do
                    if reading.bonuses[later].active and pieces[later] then
                        upper = math.min(upper, pieces[later])
                        break
                    end
                end
            end
            for count = newCount + 1, upper do
                if not lost[count] then
                    maybe = true
                end
            end
        end
    end
    table.sort(counts)
    for _, count in ipairs(counts) do
        entries[#entries + 1] = { kind = "loss", set = reading.name, pieces = count }
    end
    if maybe then
        entries[#entries + 1] = { kind = "maybe", set = reading.name }
    end
end

local function EntryText(entry)
    return entry.kind .. ":" .. tostring(entry.set) .. ":" .. tostring(entry.pieces)
end

-- What the piece would do in one of the places it can go (slots: what it would take off):
-- entries, the name of the first piece taken off (nil for an empty place), and whether a
-- tooltip was not there to read.
local function ChoiceChanges(own, slots)
    local sets, replaced, incomplete = {}, nil, false
    local function Count(reading, delta)
        for _, entry in ipairs(sets) do
            if SameSet(entry.reading, reading) then
                entry.delta = entry.delta + delta
                return
            end
        end
        sets[#sets + 1] = { reading = reading, delta = delta }
    end
    if own then
        Count(own, 1)
    end
    for _, slot in ipairs(slots) do
        local wornLink = GetInventoryItemLink("player", slot)
        if wornLink then
            replaced = replaced or wornLink
            local worn, notThere = ReadLink(wornLink)
            if worn then
                Count(worn, -1)
            elseif notThere then
                incomplete = true
            end
        end
    end
    local entries = {}
    for _, entry in ipairs(sets) do
        AddSetChange(entries, entry.reading, entry.delta)
    end
    return entries, replaced, incomplete
end

local function Signature(entries)
    local texts = {}
    for index, entry in ipairs(entries) do
        texts[index] = EntryText(entry)
    end
    return table.concat(texts, "|")
end

-- The last answer, for a tooltip that is filled again and again while the pointer rests on its
-- item. Gone when the worn gear changes: nothing else changes what a set's tooltips show.
local lastLink, lastChanges, lastWhy
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
watcher:SetScript("OnEvent", function()
    lastLink, lastChanges, lastWhy = nil, nil, nil
end)

-- For the scenarios and the recorder: nothing kept from before.
function CaerdonSetBonuses:ForgetAnswers()
    lastLink, lastChanges, lastWhy = nil, nil, nil
end

-- What wearing the piece would do to the set bonuses of what is worn: a list of entries as
-- AddSetChange makes them, or nil where it would do nothing (second: why, for the export).
-- A piece that can go in two places (a ring, a trinket, a one-hander) and would not do the same
-- in both has each place's entries, with `inPlaceOf` the name of the piece that place holds, or
-- `emptySlot = true`.
function CaerdonSetBonuses:GetChanges(item)
    if not item or item:IsItemEmpty() or item:GetCaerdonItemType() ~= CaerdonItemType.Equipment then
        return nil, "not a piece of equipment"
    end
    local link = item:GetItemLink()
    if not link then
        return nil, "a piece without a link"
    end
    if link == lastLink then
        return lastChanges, lastWhy
    end
    local choices = CaerdonEquipment.GetSlotChoices and CaerdonEquipment:GetSlotChoices(item:GetInventoryTypeName()) or nil
    if not choices or #choices == 0 then
        return nil, "not a piece for a slot"
    end
    for _, slots in ipairs(choices) do
        for _, slot in ipairs(slots) do
            if GetInventoryItemLink("player", slot) == link then
                return nil, "the piece is being worn"
            end
        end
    end

    local own, ownNotThere = ReadLink(link)
    local incomplete = ownNotThere
    local perChoice, same = {}, true
    for index, slots in ipairs(choices) do
        local entries, replaced, notThere = ChoiceChanges(own, slots)
        incomplete = incomplete or notThere
        perChoice[index] = { entries = entries, replaced = replaced }
        if index > 1 and Signature(entries) ~= Signature(perChoice[1].entries) then
            same = false
        end
    end

    local changes = {}
    if same then
        changes = perChoice[1].entries
    else
        for _, choice in ipairs(perChoice) do
            local name = choice.replaced and (choice.replaced:match("%[(.-)%]") or choice.replaced) or nil
            for _, entry in ipairs(choice.entries) do
                entry.inPlaceOf = name
                entry.emptySlot = name == nil or nil
                changes[#changes + 1] = entry
            end
        end
    end

    local answer, why = nil, nil
    if #changes > 0 then
        answer = changes
    elseif incomplete then
        why = "a tooltip it is read from is not there yet"
    elseif own then
        why = "no bonus begins or ends with it"
    else
        why = "neither the piece nor what it would take off is of an item set"
    end
    if not incomplete then
        lastLink, lastChanges, lastWhy = link, answer, why
    end
    return answer, why
end

-- For the Debug Frame export: what this file reads off the piece, remembers of its set and
-- would say in its tooltip, a line each.
function CaerdonSetBonuses:Describe(item)
    local lines = {}
    local function add(text, ...)
        lines[#lines + 1] = select("#", ...) > 0 and text:format(...) or text
    end
    local link = item and item:GetItemLink()
    if not link then
        return lines
    end
    local function DescribeReading(label, reading)
        local parts = {}
        local pieces, ordered = PiecesOf(reading.key, reading)
        for position, bonus in ipairs(reading.bonuses) do
            parts[position] = ("%d: %s, %s"):format(position, bonus.active and "had" or "not had",
                pieces[position] and (pieces[position] .. " pieces" .. (bonus.active and " (remembered)" or "")) or
                "pieces not remembered")
        end
        add("%s: \"%s\" (filed under %s), %d worn%s; bonuses %s%s", label, tostring(reading.name),
            reading.setID and ("set " .. reading.setID) or "its name", reading.worn,
            reading.legacy and ", a legacy set whose bonuses do not work" or "",
            #parts > 0 and table.concat(parts, "; ") or "none",
            ordered and "" or " (not in ascending order: no number is reasoned from another)")
    end
    local own, notThere = ReadLink(link)
    if own then
        DescribeReading("Read Off Its Tooltip", own)
    else
        add("Read Off Its Tooltip: %s", notThere and "the tooltip is not there yet" or "no item set")
    end
    local choices = CaerdonEquipment.GetSlotChoices and item.GetInventoryTypeName and
        CaerdonEquipment:GetSlotChoices(item:GetInventoryTypeName()) or nil
    local seen = {}
    for _, slots in ipairs(choices or {}) do
        for _, slot in ipairs(slots) do
            local wornLink = GetInventoryItemLink("player", slot)
            if wornLink and not seen[slot] then
                seen[slot] = true
                local worn, wornNotThere = ReadLink(wornLink)
                if worn then
                    DescribeReading(("Worn In Slot %d"):format(slot), worn)
                else
                    add("Worn In Slot %d: %s", slot, wornNotThere and "its tooltip is not there yet" or "no item set")
                end
            end
        end
    end
    self:ForgetAnswers()
    local changes, why = self:GetChanges(item)
    if not changes then
        add("Wearing It: nothing to say (%s)", tostring(why))
    end
    for _, entry in ipairs(changes or {}) do
        local what = entry.kind == "gain" and ("would bring the %d-piece bonus"):format(entry.pieces) or
            entry.kind == "loss" and ("would end the %d-piece bonus"):format(entry.pieces) or
            "may end a bonus (the pieces it begins at are not remembered)"
        add("Wearing It: \"%s\" %s%s", tostring(entry.set), what,
            entry.inPlaceOf and (" in place of " .. entry.inPlaceOf) or entry.emptySlot and " in the empty slot" or "")
    end
    return lines
end
