-- Looks a piece would have after it is changed.
--
-- A season's piece is not done with the look it has. Raised on its upgrade track it takes the
-- look of the next track's gear, and the Catalyst turns it into the class set's piece for its
-- slot. Where the collection lacks one of those looks, the piece is the way to it, although
-- its own look is known: it is not junk.
--
-- The client has no call for "what would this piece look like afterwards". What is used:
--
--   Upgrade. C_Item.GetItemUpgradeInfo names the track and the rank. The tracks Veteran,
--   Champion, Hero and Myth stand for the looks of Raid Finder, Normal, Heroic and Mythic gear,
--   and a piece raised far enough on its track gets the look of the next one. Those looks are
--   sources of one item that differ in their modifier (itemModID 4, 0, 1, 3). So the look to
--   gain is the source of the same item with the next track's modifier, where the piece does
--   not have that one already. The rank at which the look turns is not needed for that: a
--   piece past it already has the source.
--
--   Catalyst. C_Item.IsItemConvertibleAndValidForPlayer says whether this copy is one the
--   Catalyst takes. What it gives is a piece of a set of the toon's class, found among the
--   client's sets (C_TransmogSets) by the icon the client names for the converted piece
--   (C_Item.GetItemConversionOutputIcon), which comes a moment after it is first asked for;
--   nothing is said until it is here. The converted piece keeps the bonuses of the one put
--   in, so its look is asked of the client for this piece's link with the set piece's item
--   ID in place of its own, and checked against the icon.
--
-- Nothing here is a table of seasons. Where one of the client's answers is missing or does
-- not fit the others, nothing is said about the piece, which leaves it as it was judged
-- without this module. The export's "[Looks After a Change]" prints every answer.
--
-- CaerdonItemMixin:GetTransformLookInfo() is the entry point for callers (CaerdonItem.lua).

CaerdonTransformLooks = {}

-- The four looks of a season's gear, lowest first, by the modifier a source carries.
local TIER_MOD_IDS = { 4, 0, 1, 3 }
local TIER_BY_MOD_ID = { [4] = 1, [0] = 2, [1] = 3, [3] = 4 }
local TIER_NAMES = { "Raid Finder", "Normal", "Heroic", "Mythic" }
-- The upgrade tracks whose gear has those looks, by the client's ID of the track's name
-- (ItemUpgradeInfo.trackStringID): Veteran, Champion, Hero, Myth.
local TIER_BY_TRACK = { [972] = 1, [973] = 2, [974] = 3, [978] = 4 }
local HIGHEST_TIER = 4
-- The sources of one item are made together, so their IDs lie side by side. How far from the
-- piece's own source the one for another difficulty is looked for.
local SIBLING_REACH = 8
-- How often the icons are drawn again for one copy because the client's conversion data came.
local CONVERSION_REDRAWS_PER_COPY = 2

-- The slots the Catalyst takes, by the client's name of the equipment location. A robe is
-- turned into the set's chest piece.
local SLOTS = {
    INVTYPE_HEAD = "head",
    INVTYPE_SHOULDER = "shoulder",
    INVTYPE_CHEST = "chest",
    INVTYPE_ROBE = "chest",
    INVTYPE_WAIST = "waist",
    INVTYPE_LEGS = "legs",
    INVTYPE_FEET = "feet",
    INVTYPE_WRIST = "wrist",
    INVTYPE_HAND = "hand",
    INVTYPE_CLOAK = "cloak",
}

-- Link -> whether a copy with this link is asked about the Catalyst: false, or the slot. What
-- a link says does not change, so this is kept for the session.
local convertibleByLink = {}
-- The sets of the toon's class, newest first. Built when the first copy is one the Catalyst
-- takes, and kept: the client's sets do not change in a session.
local families
-- Item ID -> true while a set piece's data is asked for, false once the client has given it,
-- "refused" where the client said it has none to give.
local awaitedItems = {}
local refreshPending = false
-- Item GUID -> how often the icons were drawn again for it: the copies judged while the
-- client had no icon for their converted piece.
local awaitedConversions = {}

local function Note(trace, text, ...)
    if trace then
        trace[#trace + 1] = select("#", ...) > 0 and text:format(...) or text
    end
end

local function TierName(tier)
    return TIER_NAMES[tier] or "no"
end

-- What the collection says of a source: "collected", "knownLook" (the look is known from
-- another item) or "missing" (nothing collected has the look), and the client's info for it.
-- nil where the client has no such source.
local function LookState(sourceID)
    local info = C_TransmogCollection.GetSourceInfo(sourceID)
    if not info then
        return nil
    end
    if info.isCollected or C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID) then
        return "collected", info
    end
    if info.visualID then
        for _, otherID in ipairs(C_TransmogCollection.GetAllAppearanceSources(info.visualID) or {}) do
            if otherID ~= sourceID and C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(otherID) then
                return "knownLook", info
            end
        end
    end
    return "missing", info
end

-- The piece's upgrade track, as far as it matters here: the tier of looks it stands for (nil
-- for a track with none), whether it is a current one, and whether the piece can still rise.
-- nil where the client has no upgrade info for the link.
local function ReadTrack(itemLink, upgradeDisabled, trace)
    if not (C_Item and C_Item.GetItemUpgradeInfo) then
        Note(trace, "upgrade track: this client has no upgrade info")
        return nil
    end
    local upgrade = C_Item.GetItemUpgradeInfo(itemLink)
    if not upgrade then
        Note(trace, "upgrade track: none")
        return nil
    end
    local current, highest = upgrade.currentLevel or 0, upgrade.maxLevel or 0
    local tier = TIER_BY_TRACK[upgrade.trackStringID]
    -- A past season's piece keeps a track with no ranks, or a line greyed out in its tooltip.
    local live = current > 0 and not upgradeDisabled
    Note(trace, "upgrade track: %s (%s), rank %s of %s, %s look%s", tostring(upgrade.trackString),
        tostring(upgrade.trackStringID), tostring(current), tostring(highest), TierName(tier),
        upgradeDisabled and ", greyed out in the tooltip" or "")
    return { tier = tier, live = live, canRise = live and current < highest }
end

-- The source of the same item for another difficulty, looked for beside the piece's own.
local function FindSiblingSource(sourceID, itemID, modID)
    local function Try(candidate)
        if candidate > 0 and C_TransmogCollection.GetSourceItemID(candidate) == itemID then
            local info = C_TransmogCollection.GetSourceInfo(candidate)
            if info and info.itemModID == modID then
                return candidate
            end
        end
    end
    for distance = 1, SIBLING_REACH do
        local found = Try(sourceID - distance) or Try(sourceID + distance)
        if found then
            return found
        end
    end
end

-- The look the piece gains by being raised on its track, or nil.
local function UpgradeLook(itemID, sourceID, track, trace)
    if not track then
        return nil
    end
    if not track.tier then
        Note(trace, "upgrade: its track has no look of its own to move on from")
        return nil
    end
    if track.tier >= HIGHEST_TIER then
        Note(trace, "upgrade: its track is the highest")
        return nil
    end
    if not track.canRise then
        Note(trace, "upgrade: the piece cannot be raised (a track no longer current, or its last rank)")
        return nil
    end
    local own = C_TransmogCollection.GetSourceInfo(sourceID)
    if not own then
        Note(trace, "upgrade: the client has no info for the piece's source %s", tostring(sourceID))
        return nil
    end
    local wanted = track.tier + 1
    local modID = TIER_MOD_IDS[wanted]
    if own.itemModID == modID then
        Note(trace, "upgrade: the piece has the %s look already", TierName(wanted))
        return nil
    end
    local sibling = FindSiblingSource(sourceID, itemID, modID)
    if not sibling then
        Note(trace, "upgrade: no %s source of this item within %d of source %s (its own modifier: %s)",
            TierName(wanted), SIBLING_REACH, tostring(sourceID), tostring(own.itemModID))
        return nil
    end
    local state, info = LookState(sibling)
    if not state then
        return nil
    end
    if info.visualID == own.visualID then
        Note(trace, "upgrade: the %s source %d has the look the piece has now", TierName(wanted), sibling)
        return nil
    end
    Note(trace, "upgrade: raised, it has the %s look, source %d of appearance %s: %s", TierName(wanted), sibling,
        tostring(info.visualID), state)
    return { how = "upgrade", sourceID = sibling, appearanceID = info.visualID, state = state, tier = wanted }
end

-- The sets of the toon's class alone, each with the items it has per slot the Catalyst takes
-- and every item's sources. A set and its difficulty variants are one family. A slot can
-- have more than one item, and an item can be in more than one family: its sources are all
-- that any of them lists.
local function BuildFamilies()
    families = {}
    if not (C_TransmogSets and C_TransmogSets.GetAllSets and C_TransmogSets.GetAllSourceIDs) then
        return families
    end
    local _, _, classID = UnitClass("player")
    if not classID then
        return families
    end
    local classMask = 2 ^ (classID - 1)
    local byKey, byItem = {}, {}
    for _, set in ipairs(C_TransmogSets.GetAllSets() or {}) do
        if set.classMask == classMask then
            local key = set.baseSetID or set.setID
            local family = byKey[key]
            if not family then
                family = { key = key, patchID = 0, slots = {} }
                byKey[key] = family
                families[#families + 1] = family
            end
            if (set.patchID or 0) > family.patchID then
                family.patchID = set.patchID
            end
            for _, sourceID in ipairs(C_TransmogSets.GetAllSourceIDs(set.setID) or {}) do
                local itemID = C_TransmogCollection.GetSourceItemID(sourceID)
                local equipLocation
                if itemID and itemID > 0 then
                    equipLocation = select(4, C_Item.GetItemInfoInstant(itemID))
                end
                local slot = equipLocation and SLOTS[equipLocation]
                if slot then
                    -- One table per item, whichever families list it.
                    local piece = byItem[itemID]
                    if not piece then
                        piece = { itemID = itemID, sources = {}, listed = {} }
                        byItem[itemID] = piece
                    end
                    if not piece.listed[sourceID] then
                        piece.listed[sourceID] = true
                        piece.sources[#piece.sources + 1] = sourceID
                    end
                    local pieces = family.slots[slot]
                    if not pieces then
                        pieces = { has = {} }
                        family.slots[slot] = pieces
                    end
                    if not pieces.has[itemID] then
                        pieces.has[itemID] = true
                        pieces[#pieces + 1] = piece
                    end
                end
            end
        end
    end
    table.sort(families, function(a, b)
        if a.patchID ~= b.patchID then
            return a.patchID > b.patchID
        end
        return a.key > b.key
    end)
    return families
end

-- The icons a set piece can have: its item's own and one per source, since a difficulty's
-- look can have an icon of its own. Kept once the client has answered for every source.
local function PieceIcons(piece)
    if piece.icons then
        return piece.icons
    end
    local icons, complete = {}, true
    local own = select(5, C_Item.GetItemInfoInstant(piece.itemID))
    if own then
        icons[own] = true
    end
    if C_TransmogCollection.GetSourceIcon then
        for _, sourceID in ipairs(piece.sources) do
            local icon = C_TransmogCollection.GetSourceIcon(sourceID)
            if icon then
                icons[icon] = true
            else
                complete = false
            end
        end
    end
    if complete then
        piece.icons = icons
    end
    return icons
end

-- The looks of a piece's sources, as one text to compare two pieces by.
local function LooksKey(piece)
    local looks = {}
    for _, sourceID in ipairs(piece.sources) do
        local info = C_TransmogCollection.GetSourceInfo(sourceID)
        looks[#looks + 1] = info and info.visualID or 0
    end
    table.sort(looks)
    return table.concat(looks, ",")
end

-- For the export: an item of a set for a slot, with its icons.
local function DescribePiece(piece)
    local icons = {}
    for icon in pairs(PieceIcons(piece)) do
        icons[#icons + 1] = icon
    end
    table.sort(icons)
    for index, icon in ipairs(icons) do
        icons[index] = tostring(icon)
    end
    return ("item %d (%d sources; icons %s)"):format(piece.itemID, #piece.sources, table.concat(icons, ", "))
end

-- How many of the newest sets the export describes where none has the icon.
local SETS_DESCRIBED = 4

-- The set piece the Catalyst gives for a slot, and how it was told: the piece of a set of the
-- class that has the icon the client names for the converted piece, the newest set first.
-- Nothing is said without the icon.
--
-- A set can list more than one item for a slot. Where several of them have the icon, the
-- one with the most sources is the set's piece (a piece per difficulty, where another item
-- shares one of its looks); items with as many sources and the same looks are as good as
-- each other; with other looks nothing says which it is.
--
-- More than one set of the class can have a piece with the icon: the season's PVP set shares
-- its looks' icons with the class set (seen: a belt whose converted piece is the class set's,
-- where the PVP set, listed first, has two belts with that icon). So this is the first such
-- set from `startAt` on, with its place in the list, and the caller goes on to the next where
-- the client names none of the piece's sources for the converted link (CatalystLooks).
local function FindSetPiece(slot, icon, trace, startAt)
    local list = families or BuildFamilies()
    for familyIndex = startAt or 1, #list do
        local family = list[familyIndex]
        local matches = {}
        for _, piece in ipairs(family.slots[slot] or {}) do
            if PieceIcons(piece)[icon] then
                matches[#matches + 1] = piece
            end
        end
        if #matches == 1 then
            return matches[1], family, "by the converted piece's icon", familyIndex
        elseif #matches > 1 then
            table.sort(matches, function(a, b)
                if #a.sources ~= #b.sources then
                    return #a.sources > #b.sources
                end
                return a.itemID < b.itemID
            end)
            local first = matches[1]
            for index = 2, #matches do
                local other = matches[index]
                if #other.sources == #first.sources and LooksKey(other) ~= LooksKey(first) then
                    Note(trace, "catalyst: set %s (patch %s) has %d items for the %s slot with the icon %s, and not the same looks: %s and %s",
                        tostring(family.key), tostring(family.patchID), #matches, slot, tostring(icon),
                        DescribePiece(first), DescribePiece(other))
                    return nil
                end
            end
            -- The export names what it was chosen from.
            local others = {}
            for index = 2, #matches do
                others[#others + 1] = ("item %d with %d sources"):format(matches[index].itemID, #matches[index].sources)
            end
            return first, family, ("by the converted piece's icon, among %d items of the set that have it (the others: %s)")
                :format(#matches, table.concat(others, ", ")), familyIndex
        end
    end
    if (startAt or 1) > 1 then
        -- Sets with the icon were found and passed over; the caller says so.
        return nil
    end
    Note(trace, "catalyst: no set of this class has a %s piece with the icon %s (%d sets looked at)", slot,
        tostring(icon), #list)
    if trace then
        local described = 0
        for _, family in ipairs(list) do
            local pieces = family.slots[slot]
            if pieces and described < SETS_DESCRIBED then
                described = described + 1
                local items = {}
                for index, piece in ipairs(pieces) do
                    items[index] = DescribePiece(piece)
                end
                Note(trace, "catalyst: set %s (patch %s) has for the %s slot: %s", tostring(family.key),
                    tostring(family.patchID), slot, table.concat(items, "; "))
            end
        end
    end
    return nil
end

local function RefreshSoon(reason, detail)
    if refreshPending then
        return
    end
    refreshPending = true
    C_Timer.After(0.2, function()
        refreshPending = false
        if CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
            CaerdonWardrobe:RefreshItems(reason, detail)
        end
    end)
end

-- A set piece the client has no data for: asked for, and the verdict that needs it is put off
-- (the status answers not ready and the queue asks again; the data is back two frames after
-- it is asked for). Asked for every time it is found missing, not once a session: the client
-- keeps the data of about two thousand items and drops the least recently used (notes:
-- Upgrades), so a set piece that was here is gone again after a window full of items has
-- drawn. Asked once, the piece then had no look to gain for the rest of the session and was
-- offered for sale. Returns whether the data is on its way; false where the client has said
-- it has none to give, and the piece is then judged without, as before.
local function AwaitItem(itemID)
    local state = awaitedItems[itemID]
    if state == true then
        return true
    elseif state == "refused" then
        return false
    end
    awaitedItems[itemID] = true
    CaerdonCounters:NoteWithoutData("the Catalyst's set piece: asked for, the verdict put off", "item:" .. itemID, true)
    CaerdonItemEventListener:AddCallback(itemID, function()
        awaitedItems[itemID] = false
    end, function()
        awaitedItems[itemID] = "refused"
    end)
    return true
end

-- Whether a copy with this link is one to ask the client about, and its slot. A link's own
-- facts: a slot the Catalyst takes, and upgrade info of any kind, which a season's gear has
-- and nothing else (on WoW Forever no item has it, so nothing is asked there).
local function ConvertibleSlot(itemLink, itemID)
    local slot = convertibleByLink[itemLink]
    if slot == nil then
        slot = false
        -- The slot first: it is every item's link that is asked, and most are no armor.
        local equipLocation = select(4, C_Item.GetItemInfoInstant(itemID))
        local named = equipLocation and SLOTS[equipLocation]
        if named and C_Item.IsItemConvertibleAndValidForPlayer and C_Item.GetItemUpgradeInfo and
            C_Item.GetItemUpgradeInfo(itemLink) then
            slot = named
        end
        convertibleByLink[itemLink] = slot
    end
    return slot or nil
end

-- Whether the Catalyst is asked about this copy: its answer is the copy's, not the link's, so
-- such a copy has a status cache entry of its own (StatusCacheKey in CaerdonItem.lua).
function CaerdonTransformLooks:MayBeConverted(item, itemLink)
    local itemID = item:GetItemID()
    if not (itemLink and itemID and ConvertibleSlot(itemLink, itemID)) then
        return false
    end
    return item:IsItemInPlayersControl() == true
end

-- The looks the piece gains at the Catalyst: as it is, and raised on its track afterwards.
local function CatalystLooks(item, itemLink, itemID, track, trace)
    local slot = ConvertibleSlot(itemLink, itemID)
    if not slot then
        Note(trace, "catalyst: not asked (no slot the Catalyst takes, or no upgrade info)")
        return nil
    end
    local location = item:GetItemLocation()
    if not (location and location:IsValid() and C_Item.DoesItemExist(location)) then
        Note(trace, "catalyst: no copy to ask (a link alone)")
        return nil
    end
    if not C_Item.IsItemConvertibleAndValidForPlayer(location) then
        Note(trace, "catalyst: the client says this copy is not one to convert")
        return nil
    end
    local icon = C_Item.GetItemConversionOutputIcon and C_Item.GetItemConversionOutputIcon(location) or nil
    Note(trace, "catalyst: the client takes this copy; the converted piece's icon: %s", tostring(icon))
    if not icon then
        -- The client sends for it at this first ask, and says when it is here
        -- (ITEM_CONVERSION_DATA_READY). Nothing is said until then: a guess at the set was
        -- wrong where it was tried (a set of the expansion before).
        local guid = C_Item.GetItemGUID(location)
        if guid then
            awaitedConversions[guid] = awaitedConversions[guid] or 0
        end
        Note(trace, "catalyst: no icon yet, so nothing is said (the icons are drawn again when the client has it)")
        return nil
    end

    -- The set's piece is the one with the icon that the client names a source of for this
    -- piece's link with its item in it: the converted piece keeps the bonuses of the one put
    -- in, so that source is its look. A set whose piece the client names none for is not the
    -- one (the PVP set's belt has the class set's icon and looks of other modifiers), and the
    -- next set with the icon is asked.
    local piece, family, how, sourceID
    local startAt = 1
    while true do
        local familyIndex
        piece, family, how, familyIndex = FindSetPiece(slot, icon, trace, startAt)
        if not piece then
            if startAt > 1 then
                Note(trace, "catalyst: no other set of this class has a %s piece with the icon, so nothing is said", slot)
            end
            return nil
        end
        Note(trace, "catalyst: set %s (patch %s), %s piece is item %d with %d sources, found %s", tostring(family.key),
            tostring(family.patchID), slot, piece.itemID, #piece.sources, how)
        if piece.itemID == itemID then
            Note(trace, "catalyst: the piece is the set's own")
            return nil
        end
        if trace then
            -- Every look of the set piece, to tell whether the one named below is the right one.
            for _, candidate in ipairs(piece.sources) do
                local candidateState, candidateInfo = LookState(candidate)
                if candidateState then
                    Note(trace, "catalyst: the set piece's source %d (modifier %s, %s look) of appearance %s: %s", candidate,
                        tostring(candidateInfo.itemModID), TierName(TIER_BY_MOD_ID[candidateInfo.itemModID]),
                        tostring(candidateInfo.visualID), candidateState)
                end
            end
        end

        local converted = itemLink:gsub("item:%d+", "item:" .. piece.itemID, 1)
        local _
        _, sourceID = C_TransmogCollection.GetItemInfo(converted)
        if not sourceID and not C_Item.IsItemDataCachedByID(piece.itemID) then
            local pending = AwaitItem(piece.itemID)
            Note(trace, "catalyst: the client has no data for item %d %s", piece.itemID,
                pending and "just now (asked for; the verdict waits for it)" or "and has said it has none to give")
            return nil, nil, pending
        end
        if sourceID and C_TransmogCollection.GetSourceItemID(sourceID) == piece.itemID then
            break
        end
        if sourceID then
            Note(trace, "catalyst: source %d, named for the converted piece's link, is not one of item %d: not this set's piece",
                sourceID, piece.itemID)
        else
            Note(trace, "catalyst: the client names no source of item %d for the converted piece's link: not this set's piece",
                piece.itemID)
        end
        startAt = familyIndex + 1
    end
    -- The client's icon is the converted piece's own. Where the source worked out from the
    -- link has another icon and one source alone of the set piece has the client's, that
    -- one is the look.
    if C_TransmogCollection.GetSourceIcon then
        local worked = C_TransmogCollection.GetSourceIcon(sourceID)
        if worked and worked ~= icon then
            local byIcon, count = nil, 0
            for _, candidate in ipairs(piece.sources) do
                if C_TransmogCollection.GetSourceIcon(candidate) == icon then
                    byIcon, count = candidate, count + 1
                end
            end
            Note(trace, "catalyst: source %d, named for the converted piece's link, has the icon %s; %d of the set piece's sources have the client's",
                sourceID, tostring(worked), count)
            if count == 1 then
                sourceID = byIcon
            end
        end
    end
    local state, info = LookState(sourceID)
    if not state then
        return nil
    end
    Note(trace, "catalyst: converted, it has source %d (modifier %s) of appearance %s: %s", sourceID,
        tostring(info.itemModID), tostring(info.visualID), state)
    local look = { how = "catalyst", itemID = piece.itemID, sourceID = sourceID, appearanceID = info.visualID,
        state = state, tier = TIER_BY_MOD_ID[info.itemModID] }

    -- Converted and then raised: the set piece's source for the next track's look.
    local raised
    if track and track.canRise and track.tier and track.tier < HIGHEST_TIER then
        local wanted = track.tier + 1
        local modID = TIER_MOD_IDS[wanted]
        if info.itemModID ~= modID then
            for _, candidate in ipairs(piece.sources) do
                local candidateState, candidateInfo = LookState(candidate)
                if candidateState and candidateInfo.itemModID == modID and candidateInfo.visualID ~= info.visualID then
                    Note(trace, "catalyst and upgrade: source %d of appearance %s (%s look): %s", candidate,
                        tostring(candidateInfo.visualID), TierName(wanted), candidateState)
                    raised = { how = "catalystUpgrade", itemID = piece.itemID, sourceID = candidate,
                        appearanceID = candidateInfo.visualID, state = candidateState, tier = wanted }
                    break
                end
            end
        end
    end
    return look, raised
end

-- nil when the piece gains no look by being changed, otherwise
--   { looks = { { how = "upgrade" / "catalyst" / "catalystUpgrade" (converted, then raised),
--                 sourceID, appearanceID = the look it gains,
--                 state = "missing" (nothing collected has the look), "knownLook" (known from
--                         another item) or "collected",
--                 tier = 1 to 4 for Raid Finder to Mythic, where known,
--                 itemID = the set piece, for the Catalyst's },
--               ... },
--     pending = true where the client is without the data of the set's piece just now: it is
--               asked for, and the caller makes no verdict from this answer,
--     needsLook = how the first look that is missing is gained,
--     needsSource = how the first source is gained whose look is known from another item }
--
-- sourceID: the piece's own source, where the caller has it. upgradeDisabled: the tooltip's
-- upgrade line is greyed out. trace: a list that takes a line per answer, for the export.
function CaerdonTransformLooks:GetItemInfo(item, sourceID, upgradeDisabled, trace)
    local itemLink, itemID = item:GetItemLink(), item:GetItemID()
    if not (itemLink and itemID) then
        return nil
    end
    local track = ReadTrack(itemLink, upgradeDisabled, trace)
    if not track then
        -- No upgrade info: not a season's piece, and nothing more is asked.
        return nil
    end
    if not sourceID then
        local _
        _, sourceID = C_TransmogCollection.GetItemInfo(itemLink)
    end
    if trace and sourceID then
        -- Where this is not the track's look or the next one's, the track says little about
        -- the look the piece has (PVP gear).
        local own = C_TransmogCollection.GetSourceInfo(sourceID)
        Note(trace, "its own source: %d (modifier %s, %s look)", sourceID, tostring(own and own.itemModID),
            TierName(own and TIER_BY_MOD_ID[own.itemModID]))
    end

    local looks = {}
    if sourceID then
        looks[#looks + 1] = UpgradeLook(itemID, sourceID, track, trace)
    else
        Note(trace, "upgrade: the piece has no source of its own")
    end
    local converted, convertedAndRaised, pending = CatalystLooks(item, itemLink, itemID, track, trace)
    looks[#looks + 1] = converted
    looks[#looks + 1] = convertedAndRaised
    if pending then
        -- The Catalyst's look cannot be told yet: nothing is said about the piece until it can.
        return { looks = looks, pending = true }
    end
    if #looks == 0 then
        return nil
    end

    local info = { looks = looks }
    for _, look in ipairs(looks) do
        if look.state == "missing" then
            info.needsLook = info.needsLook or look.how
        elseif look.state == "knownLook" then
            info.needsSource = info.needsSource or look.how
        end
    end
    return info
end

-- Where the piece is taken for a look that counts: "catalyst" or "upgrade" (raised on its
-- track, at the upgrade vendor), which is the icon it gets. Where both have a part (a look
-- at each, or one that takes the conversion and the raising) it is "upgrade" with "catalyst"
-- second: the second is drawn small on the first, and of the two marks the Catalyst's is the
-- one that can still be read at that size. nil where no look counts.
-- countKnownLooks: a look known from another item is one to gain ("same look, different
-- item"). canRaise: raising the piece is this toon's to do (its class can use it).
function CaerdonTransformLooks:GetRoute(info, countKnownLooks, canRaise)
    if not info then
        return nil
    end
    local catalyst, upgrade = false, false
    for _, look in ipairs(info.looks) do
        if look.state == "missing" or (countKnownLooks and look.state == "knownLook") then
            if look.how == "upgrade" then
                upgrade = upgrade or (canRaise and true or false)
            elseif look.how == "catalyst" then
                catalyst = true
            elseif look.how == "catalystUpgrade" then
                catalyst, upgrade = true, true
            end
        end
    end
    if catalyst and upgrade then
        return "upgrade", "catalyst"
    elseif catalyst then
        return "catalyst", nil
    elseif upgrade then
        return "upgrade", nil
    end
    return nil
end

-- For the export: the piece the client itself names as the converted one. It does so only
-- while this copy lies in the Catalyst's window, and that is the one check there is of the
-- source worked out above.
local function NoteClientsConvertedPiece(item, info, trace)
    local frame = ItemInteractionFrame
    if not (frame and frame.IsShown and frame:IsShown() and frame.GetItemLocation) then
        Note(trace, "catalyst window: not open (with the piece put into it, this line names the client's own answer)")
        return
    end
    local slotted, own = frame:GetItemLocation(), item:GetItemLocation()
    if not (slotted and own and slotted.IsEqualTo and slotted:IsEqualTo(own)) then
        Note(trace, "catalyst window: open, with another piece or none in it")
        return
    end
    local data = C_TooltipInfo.GetItemInteractionItem and C_TooltipInfo.GetItemInteractionItem()
    local link = data and data.hyperlink
    if not link then
        Note(trace, "catalyst window: this piece is in it, and the client names no converted piece yet")
        return
    end
    local _, convertedSource = C_TransmogCollection.GetItemInfo(link)
    local state, source
    if convertedSource then
        state, source = LookState(convertedSource)
    end
    local derived
    for _, look in ipairs(info and info.looks or {}) do
        if look.how == "catalyst" then
            derived = look.sourceID
        end
    end
    Note(trace, "catalyst window: the client's converted piece is %s, source %s (modifier %s) of appearance %s: %s",
        tostring(link:match("item:[%-%d:]+") or link), tostring(convertedSource), tostring(source and source.itemModID),
        tostring(source and source.visualID), tostring(state))
    if not derived then
        Note(trace, "catalyst window: nothing was worked out to compare it with")
    elseif derived == convertedSource then
        Note(trace, "catalyst window: the source worked out above is the client's")
    else
        Note(trace, "catalyst window: NOT the source worked out above (%d)", derived)
    end
end

-- For the Debug Frame export: every answer behind the verdict for this copy, a line each.
function CaerdonTransformLooks:Explain(item, sourceID, upgradeDisabled)
    local trace = {}
    local info = self:GetItemInfo(item, sourceID, upgradeDisabled, trace)
    NoteClientsConvertedPiece(item, info, trace)
    if info and info.pending then
        -- Asked afresh, the answer is on its way: this is not "none".
        trace[#trace + 1] = "a look to gain: not known just now (the set piece's data is asked for; copy again)"
    else
        trace[#trace + 1] = ("a look to gain: %s; a source to gain: %s"):format(
            tostring(info and info.needsLook or "none"), tostring(info and info.needsSource or "none"))
    end
    return trace, info
end

-- For the test addon's recorder and the harness: a replay starts with nothing known.
function CaerdonTransformLooks:ForgetEverything()
    convertibleByLink = {}
    families = nil
    awaitedItems = {}
    awaitedConversions = {}
end

-- The client's data for a conversion comes after the copy was first asked about: the icon
-- that tells the set. The event names the copy. Draw again when it is one that was judged
-- without the icon, and no more than a couple of times for one copy, so that a copy the
-- client never has an icon for cannot keep the icons redrawing.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ITEM_CONVERSION_DATA_READY")
eventFrame:SetScript("OnEvent", function(_, _, itemGUID)
    local redraws = itemGUID and awaitedConversions[itemGUID]
    if redraws and redraws < CONVERSION_REDRAWS_PER_COPY then
        awaitedConversions[itemGUID] = redraws + 1
        RefreshSoon("conversion data")
    end
end)
