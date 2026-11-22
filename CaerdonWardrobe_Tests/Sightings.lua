-- Bag states: checks that wait for an item.
--
-- "Openable", "locked", "readable" and "refundable" belong to one copy of an item in one bag
-- slot, and whether a binding text is shown depends on whether that copy is bound. None of
-- that can be had from an item ID, so no pool can be written for these cases. Instead the
-- bags are read whenever they change, and a slot that fits a case is checked then: the
-- client's facts about the slot against the addon's answer for it. Every checked item is
-- kept, so the results say which cases a client has shown and which it never has.
--
-- The facts are read here, straight from the client, never from the addon's own processing.

local _, T = ...

local KEEP_PER_CASE = 8       -- records kept per case
local CHECKS_PER_SESSION = 12 -- verdicts asked for per case in one session
local SCAN_DELAY = 2          -- seconds after the bags changed
local BUSY_DELAY = 5          -- seconds before trying again while something else runs

------------------------------------------------------------------------------------------
-- The cases
------------------------------------------------------------------------------------------

-- fits(facts) says whether a slot is a case of this kind. expect is written by hand from the
-- rule beside it and must not be worked out by the logic it tests:
--   status   the addon's status for the slot
--   binding  "none": no binding text; "some": a binding text
-- A case without expect is only recorded: something the notes still have a question about.
-- slotState marks the states of one copy in one slot, which two copies of an item can differ in.
local LONG_COOLDOWN_SECONDS = 24 * 60 * 60

T.SightingCases = {
    {
        id = "openable",
        rule = "an item with loot that is not locked is openable (CLAUDE.md, status order 10)",
        slotState = true,
        expect = { status = "openable" },
        fits = function(facts) return facts.hasLoot and not facts.lockedLine and not facts.tooltipNotReady end,
    },
    {
        id = "locked",
        rule = "an item with loot whose bag tooltip says Locked is locked",
        slotState = true,
        expect = { status = "locked" },
        fits = function(facts) return facts.hasLoot and facts.lockedLine end,
    },
    {
        id = "readable",
        rule = "a readable item is readable, unless it has the quest icon",
        slotState = true,
        expect = { status = "readable" },
        fits = function(facts) return facts.isReadable and not facts.hasLoot and not facts.questIcon end,
    },
    {
        id = "readableForQuest",
        rule = "a readable item of a quest (a quest takes it, or a quest item whose quests are not all behind the toon) keeps the quest icon",
        slotState = true,
        expect = { status = "quest" },
        fits = function(facts) return facts.isReadable and not facts.hasLoot and facts.questIcon end,
    },
    {
        id = "refundable",
        rule = "an item the vendor still takes back is refundable",
        slotState = true,
        expect = { status = "refundable" },
        fits = function(facts) return facts.refundable and not facts.hasLoot and not facts.isReadable end,
    },
    {
        id = "soulbound",
        rule = "a bind on equip or bind on use item that has been bound shows no binding text, unless an equipment set holds it",
        expect = { binding = "none" },
        fits = function(facts)
            return facts.isBound and not facts.inEquipmentSet and
                (facts.bindType == Enum.ItemBind.OnEquip or facts.bindType == Enum.ItemBind.OnUse)
        end,
    },
    {
        id = "boundInSet",
        rule = "a bound piece that an equipment set holds shows the set's name where the binding text goes",
        expect = { binding = "some" },
        fits = function(facts) return facts.isBound and facts.inEquipmentSet end,
    },
    {
        id = "bindOnEquip",
        rule = "a bind on equip item that is not bound yet shows a binding text",
        expect = { binding = "some" },
        fits = function(facts) return not facts.isBound and facts.bindType == Enum.ItemBind.OnEquip end,
    },
    {
        id = "accountBindType",
        rule = "bind type 7 (ToWoWAccount): does such an item exist, and what does its tooltip say",
        fits = function(facts) return facts.bindType == Enum.ItemBind.ToWoWAccount end,
    },
    -- The addon shows "openable" whatever the container's cooldown. These two record what a
    -- client says about such an item, so what it should show can be decided from one.
    {
        id = "lootOnCooldown",
        rule = "an item with loot that is on a cooldown: what the client reports and what the addon shows meanwhile",
        fits = function(facts) return facts.hasLoot and (facts.cooldownSeconds or 0) > 0 end,
    },
    {
        id = "longCooldown",
        rule = "an item without loot on a cooldown of a day or more (an egg that hatches?): is the wait a cooldown at all",
        fits = function(facts) return not facts.hasLoot and (facts.cooldownSeconds or 0) >= LONG_COOLDOWN_SECONDS end,
    },
}

-- Pure: "pass", "mismatch" with what differs, or "seen" for a case without an expectation.
function T.JudgeSighting(case, status, binding)
    local expect = case.expect
    if not expect then
        return "seen"
    end
    if expect.status and status ~= expect.status then
        return "mismatch", ("status is %s, expected %s"):format(tostring(status), expect.status)
    end
    local hasText = binding ~= nil and binding ~= ""
    if expect.binding == "none" and hasText then
        return "mismatch", ("binding text is %s, expected none"):format(tostring(binding))
    end
    if expect.binding == "some" and not hasText then
        return "mismatch", "no binding text, expected one"
    end
    return "pass"
end

------------------------------------------------------------------------------------------
-- What the client says about a slot
------------------------------------------------------------------------------------------

local function Bool(value)
    return value and true or false
end

-- The lines these checks need from a tooltip: the lock, the "open me" line, and what the
-- binding line carries.
local function ReadTooltip(data)
    local found = { lockedLine = false, openableLine = false }
    for _, line in ipairs(data and data.lines or {}) do
        local text = line.leftText
        if text ~= nil and not issecretvalue(text) then
            -- The line's type is kept: the addon only reads these texts off some line types.
            if text == LOCKED then
                found.lockedLine = true
                found.lockedLineType = line.type
            elseif text == ITEM_OPENABLE then
                found.openableLine = true
                found.openableLineType = line.type
            elseif text == RETRIEVING_ITEM_INFO then
                found.notReady = true
            end
        end
        if line.type == Enum.TooltipDataLineType.ItemBinding then
            found.bindingLine = T.Plain(line, 2)
        end
    end
    return found
end

-- The facts of one slot, and its link. nil for an empty slot.
local function ReadSlot(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or not info.hyperlink then
        return nil
    end
    local facts = {
        itemID = info.itemID,
        hasLoot = Bool(info.hasLoot),
        isReadable = Bool(info.isReadable),
        isBound = Bool(info.isBound),
        refundable = false,
    }
    -- nil until the client has the item's data: the binding cases then wait for a later scan.
    -- A caged pet's link is not an item link and has no bind type to ask for.
    if info.hyperlink:find("|Hitem:", 1, true) then
        facts.bindType = select(14, C_Item.GetItemInfo(info.hyperlink))
    end
    -- A readable item with the quest icon keeps it: one a quest takes, and one of the Quest
    -- class until every quest known for it is behind the toon. No client API maps an item to
    -- a quest: this is the quest module's answer, an input as in Facts.Item, and asked only of
    -- what can be read.
    if facts.isReadable and info.itemID then
        facts.questIcon = false
        if CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon and CaerdonWardrobeConfig.Icon.ShowQuestItems then
            local questInfo = CaerdonQuestItems:GetItemQuestInfo(info.itemID, (C_Item.GetItemInfo(info.hyperlink)))
            local ofQuestClass = select(6, C_Item.GetItemInfoInstant(info.itemID)) == Enum.ItemClass.Questitem
            facts.questIcon = (questInfo ~= nil and questInfo.hasQuestValue == true) or
                (ofQuestClass and not (questInfo ~= nil and questInfo.isOver == true and not questInfo.repeatableLeft))
        end
    end
    -- The client's own answer to "is this copy in an equipment set".
    if C_Container.GetContainerItemEquipmentSetInfo then
        facts.inEquipmentSet = Bool((C_Container.GetContainerItemEquipmentSetInfo(bag, slot)))
    end

    local purchase = C_Container.GetContainerItemPurchaseInfo(bag, slot, false)
    if purchase and purchase.refundSeconds then
        facts.refundSeconds = purchase.refundSeconds
        -- Blizzard's own test for "this can still be handed back" (ContainerFrame.lua).
        facts.refundable = not (purchase.itemCount == 0 and purchase.money == 0 and purchase.currencyCount == 0)
    end

    if facts.hasLoot then
        -- Locked or not is a line of the slot's own tooltip; nothing else says it.
        local tooltip = ReadTooltip(C_TooltipInfo.GetBagItem(bag, slot))
        facts.lockedLine, facts.openableLine = tooltip.lockedLine, tooltip.openableLine
        facts.tooltipNotReady = tooltip.notReady and true or nil
    end
    -- Kept for every item with loot, and for any other item only while a cooldown runs.
    local start, duration, enable = C_Container.GetContainerItemCooldown(bag, slot)
    if facts.hasLoot or (duration or 0) > 0 then
        facts.cooldownSeconds, facts.cooldownEnable = duration, enable
        if (duration or 0) > 0 then
            facts.cooldownStart = start
        end
    end
    return facts, info.hyperlink
end

-- The slot state a set of facts stands for, or "none".
local function SlotStateOf(facts)
    for _, case in ipairs(T.SightingCases) do
        if case.slotState and case.fits(facts) then
            return case.id
        end
    end
    return "none"
end

------------------------------------------------------------------------------------------
-- Results
------------------------------------------------------------------------------------------

-- Keeps the newest records of a case. A mismatch is the last to go.
local function Store(caseID, key, record)
    local records = T.db.sightings[caseID]
    if not records then
        records = {}
        T.db.sightings[caseID] = records
    end
    local previous = records[key]
    if previous and previous.result ~= record.result then
        record.previous = { result = previous.result, status = previous.status, binding = previous.binding,
            at = previous.at, subjectVersion = previous.subjectVersion }
    end
    records[key] = record

    local keys = T.SortedKeys(records)
    if #keys > KEEP_PER_CASE then
        table.sort(keys, function(a, b)
            local left, right = records[a], records[b]
            local leftKept, rightKept = left.result == "mismatch", right.result == "mismatch"
            if leftKept ~= rightKept then
                return leftKept
            end
            return left.at > right.at
        end)
        for index = KEEP_PER_CASE + 1, #keys do
            records[keys[index]] = nil
        end
    end
    return previous
end

-- Per case: { id, rule, expect, items, pass, mismatch, seen, last }.
function T.GetSightingRows()
    local rows = {}
    for _, case in ipairs(T.SightingCases) do
        local row = { id = case.id, rule = case.rule, expect = case.expect, items = 0, pass = 0, mismatch = 0, seen = 0 }
        for _, record in pairs(T.db.sightings[case.id] or {}) do
            row.items = row.items + 1
            if row[record.result] then
                row[record.result] = row[record.result] + 1
            end
            if not row.last or record.at > row.last then
                row.last = record.at
            end
        end
        rows[#rows + 1] = row
    end
    return rows
end

------------------------------------------------------------------------------------------
-- Checking
------------------------------------------------------------------------------------------

local checked = {}      -- case id .. key -> true: asked this session
local checkedCount = {} -- case id -> how many this session
local scanPending = false
local ready = false     -- nothing is asked of the addon before the login record is written

-- Inside a job: the addon's answer for one candidate, judged and stored.
local function Check(candidate)
    local case, bag, slot = candidate.case, candidate.bag, candidate.slot
    -- Time has passed since the scan: the item may have moved or changed state.
    local facts, link = ReadSlot(bag, slot)
    if not facts or link ~= candidate.link or not case.fits(facts) then
        checked[candidate.mark] = nil
        return
    end
    facts.otherCopies = candidate.otherCopies

    local toon = T.GetToon()
    local record = {
        at = GetServerTime(),
        toon = toon.key,
        sig = toon.signature,
        build = T.GetClient().build,
        subjectVersion = C_AddOns.GetAddOnMetadata(T.SUBJECT, "Version"),
        link = link,
        bag = bag,
        slot = slot,
        facts = facts,
    }

    -- The slot's own tooltip beside the tooltip of the bare link, which is the one the addon
    -- reads: where the two disagree, the addon cannot know the state of this copy.
    local slotTooltip = ReadTooltip(C_TooltipInfo.GetBagItem(bag, slot))
    local linkTooltip = ReadTooltip(C_TooltipInfo.GetHyperlink(link))
    facts.bindingLine = slotTooltip.bindingLine
    facts.lockedLineType, facts.openableLineType = slotTooltip.lockedLineType, slotTooltip.openableLineType
    facts.linkLockedLine = linkTooltip.lockedLine
    facts.linkLockedLineType, facts.linkOpenableLineType = linkTooltip.lockedLineType, linkTooltip.openableLineType
    facts.linkBindingLine = linkTooltip.bindingLine
    if not case.expect then
        record.tooltip = T.Facts.TooltipLines(link)
        -- The slot's own lines too: what is left of a wait belongs to the copy, not the link.
        record.slotTooltip = {}
        local slotData = C_TooltipInfo.GetBagItem(bag, slot)
        for index, line in ipairs(slotData and slotData.lines or {}) do
            record.slotTooltip[index] = T.Plain(line, 3)
        end
    end

    -- The bare link first, the way a mail or loot window asks before the item reaches the bags.
    -- The addon keeps a verdict per link, and the slot's answer must not be the link's.
    local linkItem = CaerdonItem:CreateFromItemLink(link)
    local linkLoaded = false
    linkItem:ContinueOnItemLoad(function() linkLoaded = true end)
    if T.WaitUntil(function() return linkLoaded end, 10) then
        local linkReady, linkStatus = T.GetVerdict(linkItem, nil, nil, 8)
        if linkReady then
            record.linkStatus = linkStatus or ""
        end
    end

    local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
    local loaded = false
    item:ContinueOnItemLoad(function() loaded = true end)
    local feature = CaerdonWardrobe:GetFeature(candidate.feature)
    local isReady, status, binding, bindingResult
    if T.WaitUntil(function() return loaded end, 10) then
        isReady, status, binding, bindingResult = T.GetVerdict(item, feature, { bag = bag, slot = slot }, 8)
    end
    if not isReady then
        -- Not an answer (the item or its tooltip never became ready): ask again at the next scan.
        checked[candidate.mark] = nil
        return
    end
    record.status, record.binding = status, binding
    record.why = T.Facts.Scalars(bindingResult)
    record.result, record.message = T.JudgeSighting(case, status, binding)

    local previous = Store(case.id, candidate.key, record)
    if record.result == "mismatch" then
        T.Print("|cffff4040bag state %s:|r %s: %s%s", case.id, link, record.message,
            candidate.otherCopies and " (another copy of it is in a different state)" or "")
    elseif not previous and candidate.firstOfCase then
        T.Print("bag state %s seen for the first time: %s, %s.", case.id, link,
            record.result == "pass" and "the addon agrees" or "recorded")
    end
end

-- Reads the bags (and the bank while it is open) and queues a check for every slot that
-- fits a case and has not been asked about this session. Cheap: no call into the addon.
local function Scan()
    local slots, copies = {}, {}
    for _, container in ipairs(T.ListContainers()) do
        for slot = 1, C_Container.GetContainerNumSlots(container.id) do
            local facts, link = ReadSlot(container.id, slot)
            if facts then
                -- The addon keeps one verdict per link (and bound state): copies of an item
                -- that differ in their slot state share it.
                local key = T.ItemKey(link) .. (facts.isBound and "|B" or "")
                local state = SlotStateOf(facts)
                copies[key] = copies[key] or {}
                copies[key][state] = (copies[key][state] or 0) + 1
                slots[#slots + 1] = { bag = container.id, slot = slot, feature = container.feature, facts = facts,
                    link = link, key = key, state = state }
            end
        end
    end

    local candidates = {}
    for _, entry in ipairs(slots) do
        for _, case in ipairs(T.SightingCases) do
            local mark = case.id .. "|" .. entry.key
            if not checked[mark] and (checkedCount[case.id] or 0) < CHECKS_PER_SESSION and case.fits(entry.facts) then
                checked[mark] = true
                checkedCount[case.id] = (checkedCount[case.id] or 0) + 1
                local others
                for state, count in pairs(copies[entry.key]) do
                    if state ~= entry.state then
                        others = others or {}
                        others[state] = count
                    end
                end
                candidates[#candidates + 1] = {
                    case = case, mark = mark, bag = entry.bag, slot = entry.slot, feature = entry.feature,
                    link = entry.link, key = entry.key, otherCopies = others,
                    firstOfCase = next(T.db.sightings[case.id] or {}) == nil,
                }
            end
        end
    end
    return candidates
end

local Schedule

local function RunScan()
    scanPending = false
    -- Never while something is being measured, and never in combat: wait and look again.
    if InCombatLockdown() or T.timingRun or T.IsBusy() then
        Schedule(BUSY_DELAY)
        return
    end
    local candidates = Scan()
    if #candidates == 0 then
        return
    end
    T.Start("sightings", function()
        for _, candidate in ipairs(candidates) do
            Check(candidate)
            T.Yield()
        end
        if T.OnTestsFinished then
            T.OnTestsFinished()
        end
    end)
end

Schedule = function(delay)
    if not ready or scanPending then
        return
    end
    scanPending = true
    C_Timer.After(delay or SCAN_DELAY, RunScan)
end

-- Called once the login record is written (Commands.lua), and by /cwtest sightings.
function T.ScanSightings()
    ready = true
    Schedule(0)
end

T.RegisterEvent("BAG_UPDATE_DELAYED", function() Schedule() end)
T.RegisterEvent("BANKFRAME_OPENED", function() Schedule() end)

function T.PrintSightings()
    T.Print("bag states, checked when an item shows one (%s):", T.GetClient().flavor)
    for _, row in ipairs(T.GetSightingRows()) do
        local state
        if row.items == 0 then
            state = "|cffaaaaaanot seen yet|r"
        elseif row.mismatch > 0 then
            state = ("|cffff4040%d of %d items disagree|r"):format(row.mismatch, row.items)
        elseif row.expect then
            state = ("|cff40ff40%d of %d items agree|r"):format(row.pass, row.items)
        else
            state = ("|cff9999ff%d items recorded|r"):format(row.items)
        end
        print(("  %s: %s"):format(row.id, state))
    end
end
