-- Searching for test items.
--
-- A verdict test needs items that fit its shape on the toon at hand, and the account keeps
-- learning the ones it has: a pool runs dry. This walks the wardrobe's appearances, the
-- uncollected ones included, and records items whose raw facts fit a test's shape, each with
-- an appearance of its own, together with the addon's present verdict for it.
--
-- What it finds is a list to read, not a pool: an item goes into VerdictCases.lua by hand.
-- The expected status stays the one written for the shape; the verdict recorded here only
-- shows where the addon disagrees with it today.

local _, T = ...

local WANTED = 8            -- items per test
local MAX_APPEARANCES = 900 -- appearances looked at in one search
local MAX_LOADS = 200       -- items whose data is asked for
local MAX_SECONDS = 150
local LOAD_TIMEOUT = 3

local function Bool(value)
    return value and true or false
end

-- The part of a shape that a source's own record answers, before any item is loaded.
local function SourceFits(shape, info)
    if shape.sourceCollected ~= nil and shape.sourceCollected ~= Bool(info.isCollected) then
        return false
    end
    if shape.sourceValid ~= nil and shape.sourceValid ~= Bool(info.isValidSourceForPlayer) then
        return false
    end
    if shape.useError ~= nil and shape.useError ~= (info.useErrorType or false) then
        return false
    end
    return true
end

-- Inside a job: every category's appearances, as lists of appearance IDs. The list follows
-- the wardrobe's filter, so both sides are switched on for the reading and put back.
local function ListAppearances()
    local api = C_TransmogCollection
    local collectedShown, uncollectedShown = api.GetCollectedShown(), api.GetUncollectedShown()
    if not collectedShown then api.SetCollectedShown(true) end
    if not uncollectedShown then api.SetUncollectedShown(true) end

    local lists = {}
    for _, name in ipairs(T.SortedKeys(Enum.TransmogCollectionType)) do
        -- Not every value of the enum is a category the function takes.
        local ok, list = pcall(api.GetCategoryAppearances, Enum.TransmogCollectionType[name])
        if ok and type(list) == "table" and #list > 0 then
            local ids = {}
            for _, appearance in ipairs(list) do
                if not appearance.isHideVisual then
                    ids[#ids + 1] = appearance.visualID
                end
            end
            lists[#lists + 1] = ids
        end
    end

    if not collectedShown then api.SetCollectedShown(false) end
    if not uncollectedShown then api.SetUncollectedShown(false) end
    return lists
end

-- Pure: one list that takes the categories in turn, so the first few hundred appearances
-- cover every slot and weapon type.
function T.Interleave(lists)
    local merged, index, added = {}, 1, true
    while added do
        added = false
        for _, list in ipairs(lists) do
            if list[index] ~= nil then
                merged[#merged + 1] = list[index]
                added = true
            end
        end
        index = index + 1
    end
    return merged
end

-- The verdict tests of this client that look at appearances, with the items their pools hold.
local function ListTests()
    local tests = {}
    local flavor = T.GetClient().flavor
    for _, def in ipairs(T.tests) do
        if def.kind == "verdict" and def.facts == "appearance" and (not def.flavor or def.flavor == flavor) then
            local pooled = {}
            for _, itemID in ipairs(def.pool or {}) do pooled[itemID] = true end
            for _, kind in ipairs(def.kinds) do
                for _, itemID in ipairs(kind.pool or {}) do pooled[itemID] = true end
            end
            tests[#tests + 1] = { def = def, pooled = pooled, found = {}, appearances = {} }
        end
    end
    return tests
end

-- Inside a job. Returns the record.
local function Search(wanted)
    local toon, client = T.GetToon(), T.GetClient()
    local record = {
        at = GetServerTime(),
        toon = toon.key,
        sig = toon.signature,
        flavor = client.flavor,
        build = client.build,
        wanted = wanted,
        tests = {},
    }
    local tests = ListTests()
    local appearances = T.Interleave(ListAppearances())
    record.appearancesKnown = #appearances

    local startedAt = GetTime()
    local looked, loads, notLoaded = 0, 0, 0
    local loaded = {} -- item ID -> the loaded item, or false when it did not load

    local function Open()
        local open = 0
        for _, test in ipairs(tests) do
            if #test.found < wanted then
                open = open + 1
            end
        end
        return open
    end

    for _, appearanceID in ipairs(appearances) do
        if Open() == 0 then
            record.stoppedBy = "every test has its items"
            break
        elseif looked >= MAX_APPEARANCES then
            record.stoppedBy = ("%d appearances looked at"):format(MAX_APPEARANCES)
            break
        elseif loads >= MAX_LOADS then
            record.stoppedBy = ("%d items asked for"):format(MAX_LOADS)
            break
        elseif GetTime() - startedAt > MAX_SECONDS then
            record.stoppedBy = ("%d seconds"):format(MAX_SECONDS)
            break
        end
        looked = looked + 1

        for _, sourceID in ipairs(C_TransmogCollection.GetAllAppearanceSources(appearanceID) or {}) do
            local info = C_TransmogCollection.GetSourceInfo(sourceID)
            local itemID = info and info.itemID
            if itemID and itemID > 0 then
                for _, test in ipairs(tests) do
                    if #test.found < wanted and not test.appearances[appearanceID] and not test.pooled[itemID]
                        and SourceFits(test.def.shape, info) then
                        local item = loaded[itemID]
                        if item == nil then
                            loads = loads + 1
                            item = T.LoadItem(itemID, LOAD_TIMEOUT) or false
                            loaded[itemID] = item
                            if not item then
                                notLoaded = notLoaded + 1
                            end
                        end
                        if item then
                            -- The facts a test will read for this item, which may be another
                            -- source of it than the one that led here.
                            local facts = T.Facts.Read("appearance", item)
                            if not T.Facts.Mismatch(test.def.shape, facts) and facts.appearanceID
                                and not test.appearances[facts.appearanceID] then
                                local ready, status, binding = T.GetVerdict(item, nil, nil, 6)
                                test.appearances[facts.appearanceID] = true
                                test.appearances[appearanceID] = true
                                test.found[#test.found + 1] = {
                                    itemID = itemID,
                                    status = ready and status or nil,
                                    binding = ready and binding or nil,
                                    facts = facts,
                                }
                            end
                        end
                    end
                end
            end
        end
        if looked % 3 == 0 then
            T.Yield()
        end
    end

    record.stoppedBy = record.stoppedBy or "no appearance left"
    record.appearancesLooked, record.itemsAsked, record.itemsNotLoaded = looked, loads, notLoaded
    record.seconds = math.floor((GetTime() - startedAt) * 10 + 0.5) / 10
    for _, test in ipairs(tests) do
        local expected = {}
        for _, kind in ipairs(test.def.kinds) do
            expected[T.DescribeExpectation(kind.expect)] = true
        end
        record.tests[test.def.id] = {
            shape = test.def.shape,
            expected = T.SortedKeys(expected),
            found = test.found,
        }
    end
    return record
end

-- /cwtest search [items per test]
function T.SearchPoolItems(wanted)
    T.Start("search", function()
        if not T.WaitForIdle(0.5, 20) then
            T.Print("the addon's queue did not go idle, so nothing was searched.")
            return
        end
        T.Print("searching the wardrobe for items that fit the verdict tests on this toon (up to %d seconds)...", MAX_SECONDS)
        local record = Search(wanted or WANTED)
        T.db.search[record.toon] = record
        T.Print("%d of %d appearances looked at, %d items asked for (%d did not load), %s seconds; stopped because: %s.",
            record.appearancesLooked, record.appearancesKnown, record.itemsAsked, record.itemsNotLoaded,
            tostring(record.seconds), record.stoppedBy)
        for _, id in ipairs(T.SortedKeys(record.tests)) do
            local statuses = {}
            for _, found in ipairs(record.tests[id].found) do
                local status = tostring(found.status)
                statuses[status] = (statuses[status] or 0) + 1
            end
            local parts = {}
            for _, status in ipairs(T.SortedKeys(statuses)) do
                parts[#parts + 1] = ("%d %s"):format(statuses[status], status)
            end
            print(("  %s: %d items%s"):format(id, #record.tests[id].found,
                #parts > 0 and (" (the addon says: " .. table.concat(parts, ", ") .. ")") or ""))
        end
        T.Print("reload to save it.")
        if T.OnTestsFinished then
            T.OnTestsFinished()
        end
    end)
end
