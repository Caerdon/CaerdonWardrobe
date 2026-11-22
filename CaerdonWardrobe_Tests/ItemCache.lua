-- The client's item data cache: what makes an item's data leave it.
--
-- C_Item.GetItemInfo, C_Item.GetDetailedItemLevelInfo and a tooltip by link answer only while
-- the item's data is in the client's cache, and the client drops data from it again
-- (Blizzard_ObjectAPI's ItemMixin:IsDataEvictable: "Item data could be evicted from the
-- cache"). That holds for worn pieces as for any other: exports have had every worn piece
-- without item info by its link some seconds after one that had them all. What decides when
-- data goes is not written down anywhere, so this measures it (/cwtest cache).
--
-- A first run (retail 12.1.5.70961) settled two things: left alone for 75 seconds nothing
-- goes, touched or not, read or not, worn or not, and a run of the Lua collector takes
-- nothing; and with some thousands of other items asked for, everything watched went, the worn
-- pieces with it. So data goes by how much else is loaded. This run measures that:
--
--   idle      a shorter repeat of the first: items loaded and left alone, the worn pieces.
--   stream    other items are loaded a hundred at a time, each hundred waited for, so that
--             the count is of items loaded and not of items asked for. Watched meanwhile:
--             items loaded before it and after every thousand (whether data goes in the
--             order it came), items touched after every hundred with C_Item.GetItemInfo
--             (whether use keeps data), and the worn pieces.
--   size      which of the stream's own items are still there afterwards, in the order they
--             were loaded: the newest N and nothing older is a cache of N.
--   evicted   what the client still answers for a worn piece whose data is gone: by its slot,
--             and by its link.
--   back      how long the worn pieces take to be there again once asked for.
--
-- Stand still with the bags closed while it runs (about two minutes): whatever else asks the
-- client for items in that time is counted (the two item events) and not told apart.

local _, T = ...

local SAMPLE = 0.25         -- seconds between readings while idle
local IDLE_SECONDS = 30
local GROUP = 8             -- items in a watched group
local BATCH = 100           -- items of the stream loaded at a time
local STREAM = 8000         -- items of the stream
-- Where the stream's items are looked for: from the low item IDs up. An item the client has a
-- record of is not one its game has: on WoW Forever the IDs from 120000 on exist by
-- C_Item.DoesItemExistByID and 7998 of 8000 of them never loaded, so nothing pressed on the
-- cache and the run said nothing (1.60.1.71037). The low IDs are the oldest items, which both
-- clients' games have.
local STREAM_FROM = 25
local ORDER_EVERY = 1000    -- a new watched group after this many loaded
local KEEP_RUNS = 6

local counting = false
local infoEvents, loadEvents = 0, 0
T.RegisterEvent("GET_ITEM_INFO_RECEIVED", function() if counting then infoEvents = infoEvents + 1 end end)
T.RegisterEvent("ITEM_DATA_LOAD_RESULT", function() if counting then loadEvents = loadEvents + 1 end end)

local function Cached(itemID)
    return C_Item.IsItemDataCachedByID(itemID) == true
end

local function Round(value)
    return math.floor(value * 100 + 0.5) / 100
end

-- Inside a job: `count` items that exist and whose data the client does not have, from `from`
-- on and `stride` apart, so that nobody is likely to be using them. Returns them and where the
-- next search may start.
local function FindUncached(from, count, stride)
    local found, itemID, looked = {}, from, 0
    while #found < count and looked < 400000 do
        if C_Item.DoesItemExistByID(itemID) and not Cached(itemID) then
            found[#found + 1] = itemID
            itemID = itemID + stride
        else
            itemID = itemID + 1
        end
        looked = looked + 1
        if looked % 2000 == 0 then
            T.Yield()
        end
    end
    return found, itemID
end

-- Inside a job: asks for the items' data and waits for it. Returns those that came.
local Load

-- Inside a job: `count` items found as above and loaded, looked for again past the ones the
-- client would not give, so that a watched group is as large as it is meant to be in a client
-- that has records of items its game has not. Returns them and where the next search may start.
local function FindLoaded(from, count, stride)
    local loaded, rounds = {}, 0
    while #loaded < count and rounds < 8 do
        local found
        found, from = FindUncached(from, count - #loaded, stride)
        if #found == 0 then
            break
        end
        for _, itemID in ipairs(Load(found)) do
            loaded[#loaded + 1] = itemID
        end
        rounds = rounds + 1
    end
    return loaded, from
end

Load = function(itemIDs, timeout)
    for _, itemID in ipairs(itemIDs) do
        C_Item.RequestLoadItemDataByID(itemID)
    end
    T.WaitUntil(function()
        for _, itemID in ipairs(itemIDs) do
            if not Cached(itemID) then
                return false
            end
        end
        return true
    end, timeout or 5)
    local loaded = {}
    for _, itemID in ipairs(itemIDs) do
        if Cached(itemID) then
            loaded[#loaded + 1] = itemID
        end
    end
    return loaded
end

local function WornItems()
    local worn = {}
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local location = ItemLocation:CreateFromEquipmentSlot(slot)
        if location:IsValid() and C_Item.DoesItemExist(location) then
            worn[#worn + 1] = { slot = slot, id = C_Item.GetItemID(location), location = location,
                link = GetInventoryItemLink("player", slot) }
        end
    end
    return worn
end

local function WornIDs(worn)
    local ids = {}
    for index, piece in ipairs(worn) do
        ids[index] = piece.id
    end
    return ids
end

-- A group that is read: for each of its items the mark at which it was first found gone
-- (false while it is there), and how often one came back.
local function NewWatch(itemIDs, loadedAt)
    local watch = { ids = itemIDs, gone = {}, back = 0, there = {}, loadedAt = loadedAt }
    for index, itemID in ipairs(itemIDs) do
        watch.gone[index] = false
        watch.there[index] = Cached(itemID)
    end
    return watch
end

local function Read(watch, mark)
    for index, itemID in ipairs(watch.ids) do
        local cached = Cached(itemID)
        if watch.there[index] and not cached then
            if watch.gone[index] == false then
                watch.gone[index] = mark
            end
        elseif cached and not watch.there[index] then
            watch.back = watch.back + 1
        end
        watch.there[index] = cached
    end
end

local function Remaining(watch)
    local count = 0
    for index in ipairs(watch.ids) do
        if watch.there[index] then
            count = count + 1
        end
    end
    return count
end

local function Result(watch)
    return { items = #watch.ids, gone = watch.gone, back = watch.back, left = Remaining(watch), loadedAt = watch.loadedAt }
end

-- What the client answers for the worn pieces right now. By slot first: a question by link
-- asks the client for the data, and would bring it back.
local function WornAnswers(worn)
    local answers = { pieces = #worn, cachedByID = 0, cachedBySlot = 0, levelBySlot = 0, linkBySlot = 0, inventoryLink = 0,
        tooltipBySlot = 0, infoByLink = 0, levelByLink = 0, statsByLink = 0, tooltipByLink = 0, infoByID = 0, instantByID = 0,
        pawnByLink = PawnGetItemData and 0 or nil }
    for _, piece in ipairs(worn) do
        answers.cachedByID = answers.cachedByID + (Cached(piece.id) and 1 or 0)
        answers.cachedBySlot = answers.cachedBySlot + (C_Item.IsItemDataCached(piece.location) and 1 or 0)
        -- 0 is what the client answers for a piece whose data is gone.
        answers.levelBySlot = answers.levelBySlot + ((C_Item.GetCurrentItemLevel(piece.location) or 0) > 0 and 1 or 0)
        answers.linkBySlot = answers.linkBySlot + (C_Item.GetItemLink(piece.location) and 1 or 0)
        answers.inventoryLink = answers.inventoryLink + (GetInventoryItemLink("player", piece.slot) and 1 or 0)
        answers.instantByID = answers.instantByID + (C_Item.GetItemInfoInstant(piece.id) and 1 or 0)
        local tooltip = C_TooltipInfo and C_TooltipInfo.GetInventoryItem and C_TooltipInfo.GetInventoryItem("player", piece.slot)
        answers.tooltipBySlot = answers.tooltipBySlot + ((tooltip and tooltip.lines and #tooltip.lines > 2) and 1 or 0)
    end
    for _, piece in ipairs(worn) do
        local link = piece.link
        if link then
            if PawnGetItemData then
                local data = PawnGetItemData(link)
                answers.pawnByLink = answers.pawnByLink + ((data and data.Link) and 1 or 0)
            end
            answers.levelByLink = answers.levelByLink + (C_Item.GetDetailedItemLevelInfo(link) and 1 or 0)
            answers.statsByLink = answers.statsByLink + ((C_Item.GetItemStats and C_Item.GetItemStats(link)) and 1 or 0)
            local tooltip = C_TooltipInfo and C_TooltipInfo.GetHyperlink and C_TooltipInfo.GetHyperlink(link)
            answers.tooltipByLink = answers.tooltipByLink + ((tooltip and tooltip.lines and #tooltip.lines > 2) and 1 or 0)
            answers.infoByLink = answers.infoByLink + (C_Item.GetItemInfo(link) ~= nil and 1 or 0)
        end
        answers.infoByID = answers.infoByID + (C_Item.GetItemInfo(piece.id) ~= nil and 1 or 0)
    end
    return answers
end

local function Run()
    local toon, client = T.GetToon(), T.GetClient()
    local run = { at = GetServerTime(), toon = toon.key, build = client.build, flavor = client.flavor, version = 2,
        sample = SAMPLE, addons = T.NoteAddons(), framerate = Round(GetFramerate()) }
    T.Print("item cache: about two minutes; stand still with the bags closed")

    local worn = WornItems()
    run.wornAtStart = WornAnswers(worn)

    -- The stream's items, found before anything of it is loaded, and before the groups that
    -- are watched: those are looked for past the stream's last, so that no item is in both.
    local stream, streamID, looked = {}, STREAM_FROM, 0
    while #stream < STREAM and looked < 600000 do
        if C_Item.DoesItemExistByID(streamID) and not Cached(streamID) then
            stream[#stream + 1] = streamID
        end
        streamID = streamID + 1
        looked = looked + 1
        if looked % 2000 == 0 then
            T.Yield()
        end
    end

    -- Idle.
    local nextFrom = streamID
    local idleIDs
    idleIDs, nextFrom = FindLoaded(nextFrom, GROUP, 37)
    Load(WornIDs(worn))
    local idle, idleWorn = NewWatch(idleIDs), NewWatch(WornIDs(worn))
    infoEvents, loadEvents, counting = 0, 0, true
    local began = GetTime()
    while GetTime() - began < IDLE_SECONDS do
        T.Sleep(SAMPLE)
        Read(idle, Round(GetTime() - began))
        Read(idleWorn, Round(GetTime() - began))
    end
    counting = false
    run.idle = { seconds = IDLE_SECONDS, untouched = Result(idle), worn = Result(idleWorn), events = { info = infoEvents, load = loadEvents } }
    T.Print("item cache: idle done; loading %d other items", STREAM)

    -- What is watched through it.
    local touchedIDs, untouchedIDs, orderIDs
    touchedIDs, nextFrom = FindLoaded(nextFrom, GROUP, 37)
    untouchedIDs, nextFrom = FindLoaded(nextFrom, GROUP, 37)
    Load(WornIDs(worn))
    local touched, untouched, streamWorn = NewWatch(touchedIDs, 0), NewWatch(untouchedIDs, 0), NewWatch(WornIDs(worn), 0)
    local order = {}
    local loaded, failed, misses, nextOrder = 0, 0, 0, ORDER_EVERY
    infoEvents, loadEvents, counting = 0, 0, true
    began = GetTime()
    local firstWornGone
    for first = 1, #stream, BATCH do
        local last = math.min(first + BATCH - 1, #stream)
        for index = first, last do
            C_Item.RequestLoadItemDataByID(stream[index])
        end
        -- Waited for until all of the hundred are there, or none has come for a while (an
        -- item the client never loads must not hold up every hundred).
        local most, since = -1, GetTime()
        T.WaitUntil(function()
            local there = 0
            for index = first, last do
                if Cached(stream[index]) then
                    there = there + 1
                end
            end
            if there > most then
                most, since = there, GetTime()
            end
            return there == last - first + 1 or GetTime() - since > 0.3
        end, 1.5)
        for index = first, last do
            if Cached(stream[index]) then
                loaded = loaded + 1
            else
                failed = failed + 1
            end
        end
        Read(touched, loaded)
        Read(untouched, loaded)
        Read(streamWorn, loaded)
        for _, group in ipairs(order) do
            Read(group, loaded)
        end
        if not firstWornGone and Remaining(streamWorn) < #worn then
            firstWornGone = loaded
        end
        -- Use, after the reading: a touched item found gone is asked for again by the touch.
        for _, itemID in ipairs(touchedIDs) do
            if C_Item.GetItemInfo(itemID) == nil then
                misses = misses + 1
            end
        end
        if loaded >= nextOrder and #order < 6 then
            nextOrder = nextOrder + ORDER_EVERY
            orderIDs, nextFrom = FindLoaded(nextFrom, 4, 37)
            order[#order + 1] = NewWatch(orderIDs, loaded)
        end
    end
    counting = false
    local orderResults = {}
    for index, group in ipairs(order) do
        orderResults[index] = Result(group)
    end
    run.stream = { items = #stream, loaded = loaded, failed = failed, seconds = Round(GetTime() - began),
        untouched = Result(untouched), touched = Result(touched), touchedMisses = misses, worn = Result(streamWorn),
        order = orderResults, events = { info = infoEvents, load = loadEvents } }

    -- What is left of the stream itself, in the order it was loaded: runs of there and gone.
    local runs, there, tail = {}, 0, 0
    local current, length
    for index = 1, #stream do
        local cached = Cached(stream[index])
        if cached then
            there = there + 1
        end
        if cached ~= current then
            if current ~= nil and #runs < 60 then
                runs[#runs + 1] = (current and "+" or "-") .. length
            end
            current, length = cached, 0
        end
        length = length + 1
    end
    if current ~= nil and #runs < 60 then
        runs[#runs + 1] = (current and "+" or "-") .. length
    end
    for index = #stream, 1, -1 do
        if not Cached(stream[index]) then
            break
        end
        tail = tail + 1
    end
    run.size = { there = there, of = #stream, newestInARow = tail, runs = runs }

    -- The worn pieces with their data gone: what still answers.
    local evictedWorn = {}
    for _, piece in ipairs(worn) do
        if not Cached(piece.id) then
            evictedWorn[#evictedWorn + 1] = piece
        end
    end
    run.evicted = WornAnswers(evictedWorn)
    run.evicted.firstGoneAfter = firstWornGone

    -- And how long they take to be there again once asked for (the questions by link above
    -- have asked already; this asks outright and waits).
    began = GetTime()
    local frames = 0
    for _, piece in ipairs(worn) do
        C_Item.RequestLoadItemDataByID(piece.id)
    end
    local sameFrame = 0
    for _, piece in ipairs(worn) do
        sameFrame = sameFrame + (Cached(piece.id) and 1 or 0)
    end
    local all = T.WaitUntil(function()
        frames = frames + 1
        for _, piece in ipairs(worn) do
            if not Cached(piece.id) then
                return false
            end
        end
        return true
    end, 5)
    run.back = { pieces = #worn, wereGone = #evictedWorn, thereInTheSameFrame = sameFrame, all = all, frames = frames,
        seconds = Round(GetTime() - began) }

    T.db.itemCache = T.db.itemCache or {}
    T.Push(T.db.itemCache, run, KEEP_RUNS)
    T.Print("item cache: done. %d items loaded; of them %d are still there, the newest %d in a row; the worn pieces first went after %s. /reload saves it.",
        loaded, there, tail, tostring(firstWornGone))
end

-- /cwtest cache evict: other items are loaded until the worn pieces' data has left the cache,
-- and it is left so. That is the state a login can leave behind, made on purpose: what the
-- addon does when a window is opened next is then seen, not waited for. Nothing is saved.
local function Evict()
    local worn = WornItems()
    local function Gone()
        local gone = 0
        for _, piece in ipairs(worn) do
            if not Cached(piece.id) then
                gone = gone + 1
            end
        end
        return gone
    end
    T.Print("item cache: loading other items until the worn pieces' data is gone; keep the bags closed")
    local streamID, loaded = STREAM_FROM, 0
    while Gone() < #worn and loaded < 6000 do
        local batch, looked = {}, 0
        while #batch < BATCH and looked < 20000 do
            if C_Item.DoesItemExistByID(streamID) and not Cached(streamID) then
                batch[#batch + 1] = streamID
            end
            streamID = streamID + 1
            looked = looked + 1
        end
        if #batch == 0 then
            break
        end
        loaded = loaded + #Load(batch, 0.5)
    end
    T.Print("item cache: %d of %d worn pieces are without data after %d other items. Open the bags now.", Gone(), #worn, loaded)
end

function T.ItemCacheCommand(rest)
    if T.IsBusy() then
        T.Print("something else is running (%s)", tostring(T.ActiveJob()))
        return
    end
    if rest and rest:match("^%s*evict") then
        T.Start("item cache: evict", Evict)
    else
        T.Start("item cache", Run)
    end
end
