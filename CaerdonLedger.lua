-- Ledger.
--
-- Whether a toon of the realm already has a copy of an item another toon might send it, or
-- has one on its way. The mail icon says "send this to a toon that can learn it"
-- (CaerdonLearners), and a toon may not be played for weeks: without this the icon would
-- stand on every further copy until the toon had learned the first.
--
-- No move of an item is followed. The ledger holds what was last seen where:
--   bags: what the toon carries, read whenever it is played.
--   bank: what lies in its bank, read with the bags: the client counts an item with the bank
--         in it while the bank is closed (C_Item.GetItemCount; seen on WoW Forever). It
--         cannot be asked what the bank holds, only how many of an item, so the items asked
--         about are the ones somebody named for this toon (asked: NoteWanted, and whatever
--         the ledger counts that was seen in its bags or its mailbox).
--   mail: what its mailbox held when it was last open.
--   sent: what is on its way to its mailbox and was not seen there yet: what another toon
--         of the player's sent it, noted at the send, and what it bought at the auction
--         house itself. Dropped when the toon reads its mailbox, and once the mail would
--         have run out.
-- A sighting replaces what was there, which is how time with the addon off is mended: the
-- item is taken to be where it was last seen until the toon is played and says otherwise.
--
-- Only items somebody named are counted (AddTracked): the ones a toon of the realm answered
-- for in CaerdonLearners, and every item of the class Recipe, which is what the recipes for
-- other toons ask about (CaerdonItemMixin:GetRecipeOtherToonInfo).
--
-- CaerdonLedger:GetHeld(toon, itemID) is what the callers ask of another toon, and
-- CaerdonLedger:GetOwnCopies(itemID) of the one that is played: a copy it does not hold of
-- something it can learn has no star while it has one already (CaerdonItem.lua).

local ADDON_NAME, NS = ...

CaerdonLedger = {}

-- Saved: CaerdonLedgerData[realm key][toon] = {
--   bags = { [itemID] = count }, bank = { [itemID] = count }, mail = { [itemID] = count },
--   asked = { [itemID] = true } the items the client is asked to count for this toon,
--   mailSeen = time() of the mailbox's last reading, mailPartial = it showed only a part,
--   sent = { [itemID] = { { count, at = time(), from = toon } ... } },
-- }

-- How long a mail lies in a mailbox before it is returned or gone. From memory of the game,
-- not seen in a client; a note that is older stops counting.
local MAIL_DAYS = 30
local MAIL_SECONDS = MAIL_DAYS * 24 * 60 * 60
local BAG_DELAY = 1
local SEND_SLOTS = 12   -- ATTACHMENTS_MAX_SEND in both clients
local INBOX_SLOTS = 16  -- ATTACHMENTS_MAX_RECEIVE in both clients

local RECIPE_CLASS = Enum.ItemClass.Recipe
local trackers = {
    function(itemID)
        return select(6, C_Item.GetItemInfoInstant(itemID)) == RECIPE_CLASS
    end,
}

-- fn(itemID): true for an item the ledger is to count.
function CaerdonLedger:AddTracked(fn)
    if type(fn) == "function" then
        trackers[#trackers + 1] = fn
    end
end

local function IsTracked(itemID)
    if type(itemID) ~= "number" then
        return false
    end
    for index = 1, #trackers do
        if trackers[index](itemID) then
            return true
        end
    end
    return false
end

-- Whether the ledger counts an item (for the export).
function CaerdonLedger:IsTracked(itemID)
    return IsTracked(itemID)
end

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

local function RealmRecords()
    local realm = RealmKey()
    local records = realm and type(CaerdonLedgerData) == "table" and CaerdonLedgerData[realm] or nil
    return type(records) == "table" and records or nil
end

local function OwnRecord()
    local realm, toon = RealmKey(), ToonName()
    if not realm or not toon then
        return nil
    end
    if type(CaerdonLedgerData) ~= "table" then
        CaerdonLedgerData = {}
    end
    if type(CaerdonLedgerData[realm]) ~= "table" then
        CaerdonLedgerData[realm] = {}
    end
    local record = CaerdonLedgerData[realm][toon]
    if type(record) ~= "table" then
        record = {}
        CaerdonLedgerData[realm][toon] = record
    end
    for _, field in ipairs({ "bags", "bank", "mail", "sent", "asked" }) do
        if type(record[field]) ~= "table" then
            record[field] = {}
        end
    end
    return record
end

-- What of a toon's notes still counts: those of a mail that has not run out.
local function PendingSent(notes, now)
    local count = 0
    for _, note in ipairs(type(notes) == "table" and notes or {}) do
        if type(note) == "table" and type(note.at) == "number" and now - note.at < MAIL_SECONDS then
            count = count + (tonumber(note.count) or 1)
        end
    end
    return count
end

-- nil for a toon the ledger has no record of (not played since the ledger was there), else
--   { bags, bank, mail, sent = counts, covered = any of them is above zero,
--     mailSeen = when its mailbox was last read, or nil }
function CaerdonLedger:GetHeld(toon, itemID)
    local records = RealmRecords()
    local record = records and records[toon]
    if type(record) ~= "table" or type(itemID) ~= "number" then
        return nil
    end
    local held = {
        bags = type(record.bags) == "table" and tonumber(record.bags[itemID]) or 0,
        bank = type(record.bank) == "table" and tonumber(record.bank[itemID]) or 0,
        mail = type(record.mail) == "table" and tonumber(record.mail[itemID]) or 0,
        sent = PendingSent(type(record.sent) == "table" and record.sent[itemID], time()),
        mailSeen = record.mailSeen,
    }
    held.covered = held.bags > 0 or held.bank > 0 or held.mail > 0 or held.sent > 0
    return held
end

-- A toon of the realm is one to send this item to, says the toon that is played: the item is
-- asked about when that toon is next played, so that a copy in its bank is known; at once
-- where it is the toon that is played. For a toon without a record nothing is noted.
local ReadBagsSoon
function CaerdonLedger:NoteWanted(toon, itemID)
    local records = RealmRecords()
    local record = records and records[toon]
    if type(record) ~= "table" or type(itemID) ~= "number" then
        return
    end
    if type(record.asked) ~= "table" then
        record.asked = {}
    end
    local isNew = not record.asked[itemID]
    record.asked[itemID] = true
    if isNew and toon == ToonName() then
        ReadBagsSoon()
    end
end

------------------------------------------------------------------------------------------
-- The toon that is played: its bags and its mailbox
------------------------------------------------------------------------------------------

local stats = { bagReads = 0, mailReads = 0, sends = 0, noted = 0, bought = 0, refreshes = 0,
    landed = 0, landingSlowest = 0, landingLost = 0 }

-- A copy taken out of a mail is between the mailbox and the bags for a while: the mailbox
-- shows it gone before the bags have it, and a reading of the bags a second later did not
-- have it either (a retail client). Counted nowhere, it would be a copy the toon lost and
-- found again, and everything would be judged again twice for each one taken. So it is
-- counted as on its way until the client's count of the bags has risen, and for
-- LANDING_SECONDS at most: a mail that went with its copy (sent back, deleted) never lands.
--   landing[itemID] = { count, at = GetTime(), bags = the client's count when it left the mail }
local LANDING_SECONDS = 10
local landing = {}

-- How many copies of an item are still on their way from a mail into the bags, given the
-- client's count of the bags now.
local function StillLanding(itemID, inBags)
    local entry = landing[itemID]
    if not entry then
        return 0
    end
    local waited = GetTime() - entry.at
    if inBags > entry.bags then
        landing[itemID] = nil
        stats.landed = stats.landed + 1
        stats.landingSlowest = math.max(stats.landingSlowest, waited)
        return 0
    elseif waited >= LANDING_SECONDS then
        landing[itemID] = nil
        stats.landingLost = stats.landingLost + 1
        return 0
    end
    return entry.count
end

-- The items whose count a verdict was made from, and not only whether the toon has one
-- (NoteCountJudged): for these a changed count judges again.
local countJudged = {}

-- A verdict compared how many copies the toon has of an item with how many of its other toons
-- want one (CaerdonItem.lua: a copy it does not hold is no longer one to send once it has
-- enough).
function CaerdonLedger:NoteCountJudged(itemID)
    if type(itemID) == "number" then
        countJudged[itemID] = true
    end
end

-- The client's count of an item in the bags, and in the bank and the reagent bank.
local function ClientCounts(itemID)
    local bags = tonumber(C_Item.GetItemCount(itemID)) or 0
    local all = tonumber(C_Item.GetItemCount(itemID, true, false, true)) or 0
    return bags, math.max(all - bags, 0)
end

-- How many of each counted item the toon has, wherever, as of the last look (CheckHeld).
local lastHeld

-- What the toon that is played has of an item, wherever: asked of the client for the bags and
-- the bank, of its record for the mailbox and for what is on its way there.
--   { bags, bank, mail, coming, total }
--
-- What the client counts of an item the ledger counts is written down as it is asked, and
-- the item is asked about from then on: the toon's other toons read it there. A WoW Forever
-- client showed why: a recipe that had gone into a toon's bank before the ledger was there
-- was in nobody's list of items to ask about, so the other toon took it to have none until
-- it had been played once more.
function CaerdonLedger:GetOwnCopies(itemID)
    local copies = { bags = 0, bank = 0, mail = 0, coming = 0, total = 0 }
    if type(itemID) ~= "number" then
        return copies
    end
    copies.bags, copies.bank = ClientCounts(itemID)
    local record = OwnRecord()
    if record then
        -- One taken out of a mail and not in the bags yet is said to be in the mailbox still.
        copies.mail = (tonumber(record.mail[itemID]) or 0) + StillLanding(itemID, copies.bags)
        copies.coming = PendingSent(record.sent[itemID], time())
    end
    copies.total = copies.bags + copies.bank + copies.mail + copies.coming
    if record and IsTracked(itemID) then
        record.asked[itemID] = true
        record.bags[itemID] = copies.bags > 0 and copies.bags or nil
        record.bank[itemID] = copies.bank > 0 and copies.bank or nil
        -- Known from here on, so the next reading does not take it for a change.
        if lastHeld then
            lastHeld[itemID] = copies.total > 0 and copies.total or nil
        end
    end
    return copies
end

-- A verdict was made from which items the toon has a copy of (a second copy has no star),
-- so the items are judged again when that is no longer so for one of them; a copy moved from
-- the bags to the bank, or from a mail into the bags, changes nothing. How many it has
-- matters only for an item a verdict counted (NoteCountJudged).
local function CheckHeld(why)
    local record = OwnRecord()
    if not record then
        return
    end
    local now = time()
    local held = {}
    local function Add(itemID, count)
        count = tonumber(count) or 0
        if count > 0 then
            held[itemID] = (held[itemID] or 0) + count
        end
    end
    -- First what is between a mail and the bags: one that has landed since the bags were
    -- last read is in the client's count and not yet in the record's.
    for itemID in pairs(landing) do
        local inBags = ClientCounts(itemID)
        local flying = StillLanding(itemID, inBags)
        if flying > 0 then
            Add(itemID, flying)
        else
            record.bags[itemID] = inBags > 0 and inBags or nil
        end
    end
    for _, counts in ipairs({ record.bags, record.bank, record.mail }) do
        for itemID, count in pairs(counts) do
            Add(itemID, count)
        end
    end
    for itemID, notes in pairs(record.sent) do
        Add(itemID, PendingSent(notes, now))
    end
    local before = lastHeld
    lastHeld = held
    if not before then
        return
    end
    -- One that came or went altogether is named before one whose count changed.
    local changed, counted
    for itemID, count in pairs(held) do
        if not before[itemID] then
            changed, counted = itemID, false
            break
        elseif before[itemID] ~= count and countJudged[itemID] and not changed then
            changed, counted = itemID, true
        end
    end
    if not changed or counted then
        for itemID in pairs(before) do
            if not held[itemID] then
                changed, counted = itemID, false
                break
            end
        end
    end
    if changed and CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
        stats.refreshes = stats.refreshes + 1
        local what
        if counted then
            what = string.format("the toon has %d now, had %d", held[changed], before[changed])
        else
            what = held[changed] and "the toon has one now" or "the toon has none now"
        end
        CaerdonWardrobe:RefreshItems("copies held", string.format("item %d: %s (%s)", changed, what, why))
    end
end

local function ReadBags()
    local record = OwnRecord()
    if not record then
        return
    end
    stats.bagReads = stats.bagReads + 1
    -- What lies in the bags and is counted is asked about from here on, so that it is
    -- followed into the bank.
    local seen = {}
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID and not seen[itemID] then
                seen[itemID] = true
                if IsTracked(itemID) then
                    record.asked[itemID] = true
                end
            end
        end
    end
    local bags, bank = {}, {}
    for itemID in pairs(record.asked) do
        local inBags, inBank = ClientCounts(itemID)
        -- A slot that holds it is a copy, whatever the count says.
        if inBags == 0 and seen[itemID] then
            inBags = 1
        end
        bags[itemID] = inBags > 0 and inBags or nil
        bank[itemID] = inBank > 0 and inBank or nil
        -- Asked about while a copy may still come to light: held somewhere, or wanted.
        if inBags == 0 and inBank == 0 and not IsTracked(itemID) then
            record.asked[itemID] = nil
        end
    end
    record.bags, record.bank = bags, bank
    CheckHeld("the bags and the bank were read")
end

local bagTimer
ReadBagsSoon = function()
    if bagTimer then
        return
    end
    bagTimer = C_Timer.NewTimer(BAG_DELAY, function()
        bagTimer = nil
        ReadBags()
    end)
end

-- An item was named to be counted after the bags were last read.
function CaerdonLedger:TrackedChanged()
    ReadBagsSoon()
end

-- The mailbox as it shows now. It lists a part of a full mailbox; then what was sent is not
-- dropped, since the mail may be in the part not shown.
local function ReadMailbox()
    local record = OwnRecord()
    if not record then
        return
    end
    stats.mailReads = stats.mailReads + 1
    local shown, total = GetInboxNumItems()
    shown, total = tonumber(shown) or 0, tonumber(total) or 0
    local counts = {}
    for index = 1, shown do
        for attachment = 1, INBOX_SLOTS do
            local _, itemID, _, count = GetInboxItem(index, attachment)
            if itemID and IsTracked(itemID) then
                counts[itemID] = (counts[itemID] or 0) + (tonumber(count) or 1)
                record.asked[itemID] = true
            end
        end
    end
    local before = record.mail or {}
    record.mail = counts
    record.mailSeen = time()
    record.mailPartial = total > shown or nil
    if not record.mailPartial then
        record.sent = {}
    end
    -- A copy the mailbox no longer shows is on its way into the bags (landing, above). The
    -- bags are read once more when it can no longer be, which is when a mail that went with
    -- its copy is found out.
    local took = false
    for itemID, count in pairs(before) do
        local fewer = (tonumber(count) or 0) - (tonumber(counts[itemID]) or 0)
        if fewer > 0 then
            local entry = landing[itemID]
            landing[itemID] = { count = (entry and entry.count or 0) + fewer, at = GetTime(),
                bags = entry and entry.bags or ClientCounts(itemID) }
            took = true
        end
    end
    if took then
        ReadBagsSoon()
        C_Timer.After(LANDING_SECONDS + 0.1, ReadBagsSoon)
    end
    CheckHeld("the mailbox was read")
end

-- Notes of a mail that has run out are let go.
local function DropOldNotes()
    local record = OwnRecord()
    if not record then
        return
    end
    local now = time()
    for itemID, notes in pairs(record.sent) do
        for index = #notes, 1, -1 do
            local note = notes[index]
            if type(note) ~= "table" or type(note.at) ~= "number" or now - note.at >= MAIL_SECONDS then
                table.remove(notes, index)
            end
        end
        if #notes == 0 then
            record.sent[itemID] = nil
        end
    end
end

------------------------------------------------------------------------------------------
-- A mail to another toon of the realm
------------------------------------------------------------------------------------------

-- The realm's toon a typed recipient stands for ("qwyrm", "Qwyrm-Farrealm"), or nil. Only a
-- toon with a record: one that has been played since the ledger was there.
local function FindToon(recipient)
    if type(recipient) ~= "string" then
        return nil
    end
    local name = recipient:match("^%s*([^%-%s]+)") or ""
    local lower = name:lower()
    local own = ToonName()
    for toon in pairs(RealmRecords() or {}) do
        if toon ~= own and (toon == name or toon:lower() == lower) then
            return toon
        end
    end
    return nil
end

-- What the mail being sent holds, read when it is handed to the client; noted for the
-- recipient when the client says it went.
local pending

local function OnSendMail(recipient)
    pending = nil
    local toon = FindToon(recipient)
    if not toon then
        return
    end
    local items
    for slot = 1, ATTACHMENTS_MAX_SEND or SEND_SLOTS do
        local _, itemID, _, count = GetSendMailItem(slot)
        if itemID and IsTracked(itemID) then
            items = items or {}
            items[itemID] = (items[itemID] or 0) + (tonumber(count) or 1)
        end
    end
    if items then
        pending = { toon = toon, items = items }
    end
end

local function OnMailSent()
    local sent = pending
    pending = nil
    if not sent then
        return
    end
    local records = RealmRecords()
    local record = records and records[sent.toon]
    if type(record) ~= "table" then
        return
    end
    if type(record.sent) ~= "table" then
        record.sent = {}
    end
    stats.sends = stats.sends + 1
    local from, now = ToonName(), time()
    local first
    for itemID, count in pairs(sent.items) do
        local notes = record.sent[itemID]
        if type(notes) ~= "table" then
            notes = {}
            record.sent[itemID] = notes
        end
        notes[#notes + 1] = { count = count, at = now, from = from }
        stats.noted = stats.noted + 1
        first = first or itemID
    end
    -- A verdict that said "send it" was made from what the toon lacked.
    if first and CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
        CaerdonWardrobe:RefreshItems("sent to another toon", string.format("item %d to %s", first, sent.toon))
    end
end

if hooksecurefunc and SendMail then
    hooksecurefunc("SendMail", OnSendMail)
end

------------------------------------------------------------------------------------------
-- Bought at the auction house: on its way to the toon's own mailbox
------------------------------------------------------------------------------------------

-- An auction bought lands in the mailbox, which says nothing until it is next opened. So the
-- purchase is noted like a mail sent to the toon: at the call that buys (the auction's item
-- is asked while the auction is still there), and counted when the client says the purchase
-- went through. A bid that is no buyout brings no such word. Blizzard's auction house of
-- both clients buys through these calls.
local AH_SOURCE = "the auction house"
local bids = {}  -- [auctionID] = itemID of an auction bid on this session
local commodity  -- { itemID, count } of the purchase being confirmed

local function NoteBought(itemID, count)
    local record = OwnRecord()
    if not record or not IsTracked(itemID) then
        return
    end
    local notes = record.sent[itemID]
    if type(notes) ~= "table" then
        notes = {}
        record.sent[itemID] = notes
    end
    notes[#notes + 1] = { count = count or 1, at = time(), from = AH_SOURCE }
    record.asked[itemID] = true
    stats.bought = stats.bought + 1
    CheckHeld("bought at the auction house")
end

if hooksecurefunc and C_AuctionHouse and C_AuctionHouse.PlaceBid then
    hooksecurefunc(C_AuctionHouse, "PlaceBid", function(auctionID)
        local info = auctionID and C_AuctionHouse.GetAuctionInfoByID(auctionID)
        local itemID = type(info) == "table" and type(info.itemKey) == "table" and info.itemKey.itemID or nil
        if type(itemID) == "number" then
            bids[auctionID] = itemID
        end
    end)
end
if hooksecurefunc and C_AuctionHouse and C_AuctionHouse.ConfirmCommoditiesPurchase then
    hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, quantity)
        commodity = type(itemID) == "number" and { itemID = itemID, count = tonumber(quantity) or 1 } or nil
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("MAIL_INBOX_UPDATE")
eventFrame:RegisterEvent("MAIL_SEND_SUCCESS")
eventFrame:RegisterEvent("MAIL_FAILED")
eventFrame:RegisterEvent("AUCTION_HOUSE_PURCHASE_COMPLETED")
eventFrame:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
eventFrame:RegisterEvent("COMMODITY_PURCHASE_FAILED")
local started = false
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if not started then
            started = true
            DropOldNotes()
        end
        ReadBagsSoon()
    elseif event == "BAG_UPDATE_DELAYED" then
        ReadBagsSoon()
    elseif event == "MAIL_INBOX_UPDATE" then
        ReadMailbox()
    elseif event == "MAIL_SEND_SUCCESS" then
        OnMailSent()
    elseif event == "MAIL_FAILED" then
        pending = nil
    elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
        local auctionID = ...
        local itemID = auctionID and bids[auctionID]
        if itemID then
            bids[auctionID] = nil
            NoteBought(itemID, 1)
        end
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        local bought = commodity
        commodity = nil
        if bought then
            NoteBought(bought.itemID, bought.count)
        end
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        commodity = nil
    end
end)

-- For the Debug Frame export.
function CaerdonLedger:GetDebugState()
    local record = OwnRecord()
    local function Count(counts)
        local items = 0
        for _ in pairs(type(counts) == "table" and counts or {}) do
            items = items + 1
        end
        return items
    end
    return {
        bagReads = stats.bagReads, mailReads = stats.mailReads,
        landed = stats.landed, landingSlowest = stats.landingSlowest, landingLost = stats.landingLost,
        sends = stats.sends, noted = stats.noted,
        bought = stats.bought, refreshes = stats.refreshes,
        askedItems = record and Count(record.asked) or 0,
        bankItems = record and Count(record.bank) or 0,
        bagItems = record and Count(record.bags) or 0,
        mailItems = record and Count(record.mail) or 0,
        sentItems = record and Count(record.sent) or 0,
        mailSeen = record and record.mailSeen or nil,
        mailPartial = record and record.mailPartial or nil,
        mailDays = MAIL_DAYS,
    }
end
