-- The client's own word on a quest that is not in the log: its level, and whether it is trivial
-- for the toon. It comes before the quest data of QuestieDB and AllTheThings, which are other
-- addons' and can be behind the game (CaerdonQuestItems.lua, CaerdonQuestSourceATT.lua).
--
-- The client has that word only for a quest whose data it holds, and it holds a quest's data
-- for the log's quests and for those somebody asked it to load. Without the data it answers
-- all the same: no level (C_QuestLog.GetQuestDifficultyLevel 0) and "not trivial"
-- (C_QuestLog.IsQuestTrivial false, as for a quest ID that does not exist; WoW Forever
-- 1.60.1.71037). So nothing is read of a quest while HaveQuestData says no, and the quest is
-- asked for: C_QuestLog.RequestLoadQuestByID, a few at a time, answered by
-- QUEST_DATA_LOAD_RESULT with the quest's ID. Until then the caller judges from the quest
-- data, and when the answers are in it is told which quests they were for (OnAnswers).
--
-- What the client does not say, with or without the data: the level a quest asks for. That
-- stays the quest data's.
--
-- The requests go through the addon's listener (CaerdonAsyncCallbackSystem.lua), so the
-- counters' ledger has them with every other load: asked, loaded, failed, not answered. They
-- are put from a timer and never from inside a draw, so the ledger files them under this file
-- and not under the window that was drawing.

local ADDON_NAME, NS = ...

local Client = {
    -- function(questIDs): the quests whose data has come since the last call, set by the
    -- quest module, which judges those again.
    OnAnswers = nil,
}
NS.QuestClient = Client

-- How many quests the client is asked for at a time. Blizzard's own code asks without a
-- limit, a quest at a time as a frame needs it; a bag or an auction list can name a hundred.
-- An item's icon can wait for an answer (MAX_WAIT), so the limit is as long as a list's
-- icons take: asking costs about two hundredths of a millisecond a quest, and an answer
-- took 0.3 s on WoW Forever and 0.6 s on retail with ten at a time.
local MAX_IN_FLIGHT = 25
-- A request that is not answered within this many seconds is given up on. The longest answer
-- seen took 1.9 s (retail, a refusal).
local ANSWER_TIMEOUT = 5
-- For how long after a quest was first asked for a verdict may be put off for the answer
-- (GetFacts' third value). It is below what the queue's own retries of a button that is not
-- ready add up to, so a button is never left without its draw.
local MAX_WAIT = 6
-- The answers of a run are handed on together: this long after one came, and while more are
-- on their way no later than MAX_HOLD after the first that was not handed on.
local ANSWERS_DELAY = 0.5
local MAX_HOLD = 3

-- questID -> "queued" | "sent" | "refused" | "silent". A quest that was answered has no
-- entry: it is asked for again should the client have dropped its data. One the client
-- refused or never answered is not asked for again this session.
local requests = {}
local queue = {}        -- quest IDs, in the order they were asked for
local queuedAt = {}     -- questID -> when it was first asked for, while its answer is out
local sentAt = {}       -- questID -> when, for the ones in flight
local inFlight = 0
local pumpScheduled = false
local watchdog = false

-- questID -> { level, trivial, toonLevel }: what the client said of a quest this session.
-- The client drops data again, and a word that was there for one refresh and gone for the
-- next would turn a verdict back and forth, with a request and a refresh each time. So what
-- it said stands while the toon is of the level it said it for. (The quest log's objective
-- names are kept the same way, for the same reason.)
local kept = {}

local arrived = {}      -- quest IDs whose data came and were not handed on yet
local firstArrival = nil
local answersTimer = false

local stats = {
    asked = 0,          -- requests put to the client
    came = 0,
    refused = 0,        -- the client answered that it has no such data
    silent = 0,         -- no answer within ANSWER_TIMEOUT
    late = 0,           -- an answer after that
    already = 0,        -- the data was there by the time the request's turn came
    timed = 0,          -- answers that came in time, which the waits are of
    waitSeconds = 0,
    longestWait = 0,
    handedOn = 0,       -- runs of answers handed to the quest module
    pumps = 0,          -- frames in which requests were put
    pumpMs = 0,         -- what putting them took, in all
    longestPumpMs = 0,  -- and in one frame at the most
    -- Since the caches were last dropped: questions answered with the client's word, with
    -- what it said earlier this session, and without.
    withData = 0,
    fromMemory = 0,
    without = 0,
}

local supported

-- Both clients have these (the static check); a client without one of them is asked nothing.
local function IsSupported()
    if supported == nil then
        supported = type(HaveQuestData) == "function" and type(C_QuestLog) == "table" and
            type(C_QuestLog.GetQuestDifficultyLevel) == "function" and
            type(C_QuestLog.IsQuestTrivial) == "function" and
            type(C_QuestLog.RequestLoadQuestByID) == "function" and
            type(CaerdonQuestEventListener) == "table"
    end
    return supported
end

-- A quest has its answer, of whatever kind: the buttons whose verdict was put off for it are
-- asked again, and no others (CaerdonWardrobe:RetryWaitingFor).
local function TellWaiting(questID)
    queuedAt[questID] = nil
    if CaerdonWardrobe and CaerdonWardrobe.RetryWaitingFor then
        CaerdonWardrobe:RetryWaitingFor("quest:" .. questID)
    end
end

local function SchedulePump()
    if not pumpScheduled then
        pumpScheduled = true
        C_Timer.After(0, function()
            Client:Pump()
        end)
    end
end

local function HandOnAnswers()
    answersTimer = false
    if #arrived == 0 then
        return
    end
    -- More are on their way: one check for the run, unless it takes too long.
    if (inFlight > 0 or #queue > 0) and firstArrival and GetTime() - firstArrival < MAX_HOLD then
        answersTimer = true
        C_Timer.After(ANSWERS_DELAY, HandOnAnswers)
        return
    end
    local questIDs = arrived
    arrived, firstArrival = {}, nil
    stats.handedOn = stats.handedOn + 1
    if Client.OnAnswers then
        -- One failure stays alone: the next run of answers is handed on all the same.
        xpcall(Client.OnAnswers, geterrorhandler(), questIDs)
    end
end

local function OnAnswer(questID, success)
    local state = requests[questID]
    if state == "sent" then
        inFlight = inFlight - 1
        local waited = GetTime() - (sentAt[questID] or GetTime())
        if success then
            stats.timed = stats.timed + 1
            stats.waitSeconds = stats.waitSeconds + waited
            if waited > stats.longestWait then
                stats.longestWait = waited
            end
        end
    elseif state == "silent" then
        stats.late = stats.late + 1
        stats.silent = stats.silent - 1
    else
        return
    end
    sentAt[questID] = nil

    if success then
        requests[questID] = nil
        stats.came = stats.came + 1
        arrived[#arrived + 1] = questID
        firstArrival = firstArrival or GetTime()
        if not answersTimer then
            answersTimer = true
            C_Timer.After(ANSWERS_DELAY, HandOnAnswers)
        end
    else
        requests[questID] = "refused"
        stats.refused = stats.refused + 1
    end
    TellWaiting(questID)

    if #queue > 0 then
        SchedulePump()
    end
end

-- Gives up on the requests the client has not answered, which frees their places.
local function Watchdog()
    watchdog = false
    local now = GetTime()
    for questID, at in pairs(sentAt) do
        if now - at >= ANSWER_TIMEOUT then
            sentAt[questID] = nil
            requests[questID] = "silent"
            inFlight = inFlight - 1
            stats.silent = stats.silent + 1
            TellWaiting(questID)
        end
    end
    if inFlight > 0 then
        watchdog = true
        C_Timer.After(ANSWER_TIMEOUT / 2, Watchdog)
    end
    if #queue > 0 then
        SchedulePump()
    end
end

-- Puts as many of the waiting requests as there are places for. Always from a timer: the
-- client may answer from inside the call, and a draw is not charged with the asking. What the
-- asking costs is kept, always: it is the price of this file that no draw shows. Through the
-- table, so that the counters' wrapper is the one called.
function Client:Pump()
    pumpScheduled = false
    local startedAt, put = debugprofilestop(), 0
    while inFlight < MAX_IN_FLIGHT and #queue > 0 do
        local questID = table.remove(queue, 1)
        if requests[questID] == "queued" then
            if HaveQuestData(questID) == true then
                -- Somebody else's request brought it meanwhile.
                requests[questID] = nil
                stats.already = stats.already + 1
                TellWaiting(questID)
                arrived[#arrived + 1] = questID
                firstArrival = firstArrival or GetTime()
                if not answersTimer then
                    answersTimer = true
                    C_Timer.After(ANSWERS_DELAY, HandOnAnswers)
                end
            else
                requests[questID] = "sent"
                sentAt[questID] = GetTime()
                inFlight = inFlight + 1
                stats.asked = stats.asked + 1
                put = put + 1
                CaerdonQuestEventListener:AddCallback(questID,
                    function() OnAnswer(questID, true) end,
                    function() OnAnswer(questID, false) end)
            end
        end
    end
    if inFlight > 0 and not watchdog then
        watchdog = true
        C_Timer.After(ANSWER_TIMEOUT / 2, Watchdog)
    end
    if put > 0 then
        local spent = debugprofilestop() - startedAt
        stats.pumps = stats.pumps + 1
        stats.pumpMs = stats.pumpMs + spent
        if spent > stats.longestPumpMs then
            stats.longestPumpMs = spent
        end
    end
end

local WORDS = {
    queued = "the client is asked for it",
    sent = "the client is asked for it",
    refused = "the client has no data of it",
    silent = "the client did not answer",
}

-- What the client says of a quest that is not in the log: { level, trivial }, the level 0
-- where it names none. nil while it has no word, and why as the second value; the quest is
-- then asked for, once. Third value: the answer is on its way and may be waited for (for
-- MAX_WAIT at most); false once the client has refused, was given up on, or took too long.
function Client:GetFacts(questID)
    if type(questID) ~= "number" or questID <= 0 or not IsSupported() then
        return nil, "the client is not asked"
    end

    local toonLevel = UnitLevel("player") or 0
    if HaveQuestData(questID) == true then
        local facts = kept[questID]
        if not facts then
            facts = {}
            kept[questID] = facts
        end
        local level = C_QuestLog.GetQuestDifficultyLevel(questID)
        facts.level = type(level) == "number" and level or 0
        facts.trivial = C_QuestLog.IsQuestTrivial(questID) == true
        facts.toonLevel = toonLevel
        stats.withData = stats.withData + 1
        return facts
    end

    local facts = kept[questID]
    if facts and facts.toonLevel == toonLevel then
        stats.fromMemory = stats.fromMemory + 1
        return facts
    end

    stats.without = stats.without + 1
    if not requests[questID] then
        requests[questID] = "queued"
        queuedAt[questID] = GetTime()
        queue[#queue + 1] = questID
        SchedulePump()
    end
    local state = requests[questID]
    local waiting = (state == "queued" or state == "sent") and queuedAt[questID] ~= nil and
        GetTime() - queuedAt[questID] < MAX_WAIT
    return nil, WORDS[state], waiting
end

-- With the quest module's caches: the counts of one refresh start over. What the client said
-- and what it was asked stay.
function Client:InvalidateCaches()
    stats.withData, stats.fromMemory, stats.without = 0, 0, 0
end

-- Forgets what the client said this session. Nothing in play calls it; the test addon's
-- recorder does, since a replay starts a session of its own (docs/dev-notes.md, Offline
-- Harness).
function Client:Forget()
    wipe(kept)
end

-- For the Debug Frame export.
function Client:GetDebugState()
    local queued, refusedNow, silentNow = 0, 0, 0
    for _, state in pairs(requests) do
        if state == "queued" then
            queued = queued + 1
        elseif state == "refused" then
            refusedNow = refusedNow + 1
        elseif state == "silent" then
            silentNow = silentNow + 1
        end
    end
    local keptCount = 0
    for _ in pairs(kept) do
        keptCount = keptCount + 1
    end
    return {
        supported = IsSupported(),
        asked = stats.asked,
        came = stats.came,
        refused = stats.refused,
        silent = stats.silent,
        late = stats.late,
        already = stats.already,
        averageWait = stats.timed > 0 and stats.waitSeconds / stats.timed or nil,
        longestWait = stats.longestWait,
        inFlight = inFlight,
        queued = queued,
        handedOn = stats.handedOn,
        pumps = stats.pumps,
        pumpMs = stats.pumpMs,
        longestPumpMs = stats.longestPumpMs,
        kept = keptCount,
        withData = stats.withData,
        fromMemory = stats.fromMemory,
        without = stats.without,
    }
end
