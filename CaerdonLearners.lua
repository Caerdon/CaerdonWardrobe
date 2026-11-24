-- Learners.
--
-- Which of the player's toons on the realm could learn what an item teaches, for an item that
-- is no profession's recipe: a class's spell book, a rune (CaerdonItem.lua,
-- LearnableByTeachingLine). A recipe has a profession's recorded list to ask; a book has
-- nothing of the kind, and whether a toon can learn it is a line of its tooltip as that toon's
-- client colours it ("Classes: Mage", "Requires Level 22", "Already known").
--
-- So each toon answers for itself, and the answers are saved for the others:
--   "own":      it can learn it now.
--   "lowSkill": it can once it has the level the item asks for.
--   "known":    it has learned it.
--   "never":    a class or race line of the item's own is not met. That does not change.
-- An item is judged when a toon comes across it (GetCaerdonStatus hands the answer in), and
-- that puts it on the realm's list: the items any toon of the realm has an answer for. A toon
-- judges what the list holds and it has no lasting answer for when it logs in, a few at a
-- time in the background; "own" and "lowSkill" are asked again at every login, since the
-- toon may have learned or levelled with the addon off. No class is read off a line and no
-- text is parsed: the answer is the status rule's own.
--
-- A toon that has not answered for an item says nothing about it: it has not been played
-- since some toon first came across the item.
--
-- One status comes of it (CaerdonItemMixin:GetLearnerStatus, in CaerdonItem.lua): "send" for
-- an item this toon has no use for, that can be handed over, and that another toon could
-- learn, now or once it has the level, and has no copy of: none in its bags or its mailbox as
-- they were last seen, and none sent to it since (CaerdonLedger, which counts the items of
-- the realm's list). CaerdonItemMixin:GetLearnerInfo() is the entry point for callers; the
-- Debug Frame export prints it under "[Teaches]".

local ADDON_NAME, NS = ...

CaerdonLearners = {}

-- Saved: CaerdonLearnerData[realm key][toon] = {
--   answers = { [itemID] = "own" | "lowSkill" | "known" | "never" },
--   spells  = { [itemID] = spellID },   what the item teaches, while the toon may yet learn it
--   level   = the toon's level when it was last played (for the tooltip's "at a later level")
-- }
local LASTING = { known = true, never = true }
local VALID = { own = true, lowSkill = true, known = true, never = true }

-- How the background judging is paced: so long after the world is there, so many items a
-- step, a step so often. An item's data is asked of the client first, and one whose tooltip
-- is not there yet is asked again a few times.
local START_DELAY = 8
local STEP_SECONDS = 1
local BATCH = 10
local MAX_TRIES = 3

local function RealmKey()
    return CaerdonAPI and CaerdonAPI.GetRealmKey and CaerdonAPI:GetRealmKey() or nil
end

local function ToonName()
    local name = UnitName("player")
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then
        return nil
    end
    return name
end

-- The realm's toons with a record, or nil. Not created by a read.
local function RealmRecords()
    local realm = RealmKey()
    local saved = CaerdonLearnerData
    local records = realm and type(saved) == "table" and saved[realm] or nil
    return type(records) == "table" and records or nil
end

-- This toon's record, made where there is none. nil while the client names no realm or toon.
local function OwnRecord()
    local realm, toon = RealmKey(), ToonName()
    if not realm or not toon then
        return nil
    end
    if type(CaerdonLearnerData) ~= "table" then
        CaerdonLearnerData = {}
    end
    if type(CaerdonLearnerData[realm]) ~= "table" then
        CaerdonLearnerData[realm] = {}
    end
    local record = CaerdonLearnerData[realm][toon]
    if type(record) ~= "table" then
        record = {}
        CaerdonLearnerData[realm][toon] = record
    end
    if type(record.answers) ~= "table" then
        record.answers = {}
    end
    if type(record.spells) ~= "table" then
        record.spells = {}
    end
    return record
end

-- The other toons' answers by item: { [itemID] = { { toon, answer } ... } }, and the names of
-- every other toon with a record. Built once a session: another toon's saved answers do not
-- change while this one is played.
local othersIndex, otherToons

local function BuildOthersIndex()
    local byItem, names = {}, {}
    local own = ToonName()
    for toon, record in pairs(RealmRecords() or {}) do
        if toon ~= own and type(record) == "table" and type(record.answers) == "table" then
            names[#names + 1] = toon
            local level = type(record.level) == "number" and record.level or nil
            for itemID, answer in pairs(record.answers) do
                if VALID[answer] then
                    local answers = byItem[itemID]
                    if not answers then
                        answers = {}
                        byItem[itemID] = answers
                    end
                    answers[#answers + 1] = { toon = toon, answer = answer, level = level }
                end
            end
        end
    end
    table.sort(names)
    return byItem, names
end

local function GetOthersIndex()
    if not othersIndex then
        othersIndex, otherToons = BuildOthersIndex()
    end
    return othersIndex, otherToons
end

-- The realm's list: every item some toon of the realm has an answer for. The ledger counts
-- these.
local listed
local GetListed

-- Whether an item is on the realm's list: a cheap first question for a caller that would
-- otherwise read a tooltip (the tooltip's lines, asked for every item hovered over).
function CaerdonLearners:IsListed(itemID)
    return GetListed()[itemID] == true
end

GetListed = function()
    if not listed then
        listed = {}
        for _, record in pairs(RealmRecords() or {}) do
            if type(record) == "table" and type(record.answers) == "table" then
                for itemID in pairs(record.answers) do
                    listed[itemID] = true
                end
            end
        end
    end
    return listed
end

CaerdonLedger:AddTracked(function(itemID)
    return GetListed()[itemID] == true
end)

-- This toon's answer for an item, as the status rule gave it. spellID: what the item teaches,
-- where its teaching line names a spell.
function CaerdonLearners:NoteOwnAnswer(itemID, answer, spellID)
    if type(itemID) ~= "number" or not VALID[answer] then
        return
    end
    local record = OwnRecord()
    if not record then
        return
    end
    record.answers[itemID] = answer
    record.spells[itemID] = (not LASTING[answer] and type(spellID) == "number") and spellID or nil
    if not LASTING[answer] then
        -- Something this toon may be sent: the client is asked for its count of it, which
        -- knows a copy in the bank.
        CaerdonLedger:NoteWanted(ToonName(), itemID)
    end
    local list = GetListed()
    if not list[itemID] then
        -- New to the realm's list: the bags are read again, in case a copy lies in them.
        list[itemID] = true
        CaerdonLedger:TrackedChanged()
    end
end

-- What the other toons' saved answers say about one item, and what the ledger last saw of it
-- with each of them, with nothing judged: nil where none of them has an answer for it,
-- otherwise { { toon, answer, level, bags, mail, sent = counts or nil, covered = it has a copy } ... }.
--
-- The test addon's recorder keeps this function's answer and a replay puts it in its place
-- (CaerdonWardrobe_Tests/RecordKeys.lua, SEAMS): the answers and the ledger are saved
-- variables, which no recording of a client's answers holds. So everything read from them
-- goes through here.
function CaerdonLearners:GetSavedAnswers(itemID)
    local answers = GetOthersIndex()[itemID]
    if not answers then
        return nil
    end
    local copy = {}
    for index, entry in ipairs(answers) do
        local held = CaerdonLedger:GetHeld(entry.toon, itemID)
        copy[index] = { toon = entry.toon, answer = entry.answer, level = entry.level, bags = held and held.bags or nil,
            bank = held and held.bank or nil, mail = held and held.mail or nil, sent = held and held.sent or nil,
            covered = held ~= nil and held.covered == true }
    end
    return copy
end

-- A toon that could learn it and has no copy first, the ones that can now before the ones
-- that can later; then those that have a copy; then those with nothing to learn.
local function Rank(entry)
    local wants = entry.answer == "own" or entry.answer == "lowSkill"
    if wants and not entry.covered then
        return entry.answer == "own" and 1 or 2
    elseif wants then
        return entry.answer == "own" and 3 or 4
    end
    return entry.answer == "known" and 5 or 6
end
local function SortAnswers(a, b)
    local aRank, bRank = Rank(a), Rank(b)
    if aRank ~= bRank then
        return aRank < bRank
    end
    return a.toon < b.toon
end

-- nil where no other toon has a record, otherwise
--   { answer = this toon's own (handed in),
--     toons = { { toon, answer, level, bags, mail, sent, covered } ... } the other toons that
--             answered, in the order above,
--     now = { names } that can learn it now and have no copy,
--     later = { names } that can once they have its level and have no copy,
--     covered = { names } that could learn it and have a copy, or one on its way,
--     unanswered = { names } with a record and no answer for this item }
function CaerdonLearners:GetItemInfo(itemID, ownAnswer)
    if type(itemID) ~= "number" then
        return nil
    end
    local _, names = GetOthersIndex()
    if #names == 0 then
        return nil
    end
    local info = { answer = ownAnswer, toons = {}, now = {}, later = {}, covered = {}, unanswered = {} }
    local answered = {}
    local saved = self:GetSavedAnswers(itemID)
    for _, entry in ipairs(type(saved) == "table" and saved or {}) do
        if type(entry) == "table" and type(entry.toon) == "string" and VALID[entry.answer] then
            info.toons[#info.toons + 1] = { toon = entry.toon, answer = entry.answer, level = entry.level, bags = entry.bags,
                bank = entry.bank, mail = entry.mail, sent = entry.sent, covered = entry.covered == true }
            answered[entry.toon] = true
        end
    end
    table.sort(info.toons, SortAnswers)
    for _, entry in ipairs(info.toons) do
        local wants = entry.answer == "own" or entry.answer == "lowSkill"
        if wants and entry.covered then
            info.covered[#info.covered + 1] = entry.toon
        elseif entry.answer == "own" then
            info.now[#info.now + 1] = entry.toon
        elseif entry.answer == "lowSkill" then
            info.later[#info.later + 1] = entry.toon
        end
    end
    for _, name in ipairs(names) do
        if not answered[name] then
            info.unanswered[#info.unanswered + 1] = name
        end
    end
    return info
end

------------------------------------------------------------------------------------------
-- This toon's answers for what the realm's list holds
------------------------------------------------------------------------------------------

local queue, queued = {}, {}  -- item IDs to judge, and { [itemID] = tries so far }
local stepTimer
local stats = { asked = 0, answered = 0, notThere = 0, noAnswer = 0 }

local function Enqueue(itemID)
    if type(itemID) == "number" and not queued[itemID] then
        queued[itemID] = 0
        queue[#queue + 1] = itemID
    end
end

local Step

local function Schedule(seconds)
    if stepTimer or #queue == 0 then
        return
    end
    stepTimer = C_Timer.NewTimer(seconds, function()
        stepTimer = nil
        Step()
    end)
end

-- One item, with its data there: the status rule's answer by this toon's own tooltip.
local function Judge(itemID, item)
    local teaching, retrieving = item:GetTeachingInfo()
    if retrieving then
        local tries = (queued[itemID] or 0) + 1
        if tries < MAX_TRIES then
            queued[itemID] = tries
            queue[#queue + 1] = itemID
            Schedule(STEP_SECONDS)
        else
            stats.notThere = stats.notThere + 1
        end
        return
    end
    if teaching and teaching.answer then
        stats.answered = stats.answered + 1
        CaerdonLearners:NoteOwnAnswer(itemID, teaching.answer, teaching.spellID)
    else
        -- Its tooltip teaches nothing by this toon's client. Nothing is noted, so the item is
        -- asked again at the next login.
        stats.noAnswer = stats.noAnswer + 1
    end
end

Step = function()
    if #queue == 0 then
        return
    end
    -- Not in a fight: nothing here is urgent.
    if InCombatLockdown and InCombatLockdown() then
        Schedule(STEP_SECONDS * 5)
        return
    end
    local count = math.min(BATCH, #queue)
    for _ = 1, count do
        local itemID = table.remove(queue, 1)
        -- An ID the client has no item for (a list from another build of the game).
        if C_Item.GetItemInfoInstant(itemID) then
            stats.asked = stats.asked + 1
            local item = CaerdonItem:CreateFromItemID(itemID)
            item:ContinueOnItemLoad(function()
                Judge(itemID, item)
            end)
        else
            stats.notThere = stats.notThere + 1
        end
    end
    Schedule(STEP_SECONDS)
end

-- What this toon has to answer for: every item of the realm's list it has no lasting answer
-- for. only: just its answers of that kind ("lowSkill" after a level).
local function QueueOpenItems(only)
    local record = OwnRecord()
    if not record then
        return
    end
    record.level = UnitLevel("player")
    if not only then
        for _, other in pairs(RealmRecords() or {}) do
            if type(other) == "table" and type(other.answers) == "table" then
                for itemID in pairs(other.answers) do
                    if not LASTING[record.answers[itemID]] then
                        Enqueue(itemID)
                    end
                end
            end
        end
    else
        for itemID, answer in pairs(record.answers) do
            if answer == only then
                queued[itemID] = nil
                Enqueue(itemID)
            end
        end
    end
    Schedule(only and STEP_SECONDS or START_DELAY)
end

-- A spell was learned: the items of this toon's that teach it are answered at once. The item
-- that taught it is used up, so nothing on screen would say so, and the toon's other toons
-- read the saved answer before it next logs in.
local function OnSpellLearned(spellID)
    if type(spellID) ~= "number" then
        return
    end
    local record = OwnRecord()
    if not record then
        return
    end
    for itemID, taught in pairs(record.spells) do
        if taught == spellID then
            record.answers[itemID] = "known"
            record.spells[itemID] = nil
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
local started = false
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if not started then
            started = true
            QueueOpenItems()
        end
    elseif event == "PLAYER_LEVEL_UP" then
        QueueOpenItems("lowSkill")
    elseif event == "LEARNED_SPELL_IN_SKILL_LINE" then
        OnSpellLearned(...)
    end
end)

-- For the Debug Frame export: what the background judging did this session, and how much is
-- saved for the realm.
function CaerdonLearners:GetDebugState()
    local state = { asked = stats.asked, answered = stats.answered, notThere = stats.notThere,
        noAnswer = stats.noAnswer, waiting = #queue, toons = {} }
    for toon, record in pairs(RealmRecords() or {}) do
        if type(record) == "table" and type(record.answers) == "table" then
            local counts = { own = 0, lowSkill = 0, known = 0, never = 0 }
            for _, answer in pairs(record.answers) do
                if counts[answer] then
                    counts[answer] = counts[answer] + 1
                end
            end
            state.toons[#state.toons + 1] = string.format("%s: %d can learn now, %d later, %d known, %d never",
                toon, counts.own, counts.lowSkill, counts.known, counts.never)
        end
    end
    table.sort(state.toons)
    return state
end
