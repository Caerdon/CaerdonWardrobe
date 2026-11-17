-- Raw facts about an item, read straight from the client.
--
-- A verdict test stores these next to the verdict. They tell a regression (the verdict
-- changed, the facts did not) from drift (the toon learned the look, levelled, trained), so
-- they must come from the client's APIs and never from the addon's own processing.

local _, T = ...

local Facts = {}
T.Facts = Facts

local function Bool(value)
    return value and true or false
end

-- Only what the saved variables can hold and a comparison can use.
function Facts.Scalars(source)
    local copy = {}
    if type(source) ~= "table" then
        return copy
    end
    for key, value in pairs(source) do
        local kind = type(value)
        if type(key) == "string" and not issecretvalue(value)
            and (kind == "string" or kind == "number" or kind == "boolean") then
            copy[key] = value
        end
    end
    return copy
end

-- What every kind of item has. toonLevel is here because a level-up changes verdicts, and
-- levelMet because a shape can only ask for a value, not for "at least".
function Facts.Item(item)
    local link, itemID = item:GetItemLink(), item:GetItemID()
    local name, _, quality, itemLevel, minLevel, _, _, maxStack, equipLoc, _, sellPrice, classID, subClassID,
    bindType, expansionID = C_Item.GetItemInfo(link)
    -- A quest that takes the item puts the quest icon before most others (a look to learn
    -- among them), so the item says nothing about another rule for as long. No client API
    -- maps an item to a quest: this is the quest module's answer, an input like the setting
    -- in Facts.Appearance. Kept only when true, so the facts on file compare as they did.
    local questIconOn = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon and CaerdonWardrobeConfig.Icon.ShowQuestItems
    local questInfo = questIconOn and item:GetQuestItemInfo() or nil
    return {
        questTakes = (questInfo and questInfo.hasQuestValue) and true or nil,
        levelMet = (minLevel or 0) <= UnitLevel("player"),
        itemID = itemID,
        name = name,
        quality = quality,
        itemLevel = itemLevel,
        minLevel = minLevel,
        maxStack = maxStack,
        equipLoc = equipLoc,
        sellPrice = sellPrice,
        classID = classID,
        subClassID = subClassID,
        bindType = bindType,
        expansionID = expansionID,
        canUse = Bool(C_PlayerInfo.CanUseItem(itemID)),
        toonLevel = UnitLevel("player"),
    }
end

-- Equipment with an appearance. Missing answers are stored as false, so a shape can ask for
-- "no use error" with useError = false.
function Facts.Appearance(item, facts)
    local link = item:GetItemLink()
    local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(link)
    facts.appearanceID = appearanceID or false
    facts.sourceID = sourceID or false
    if not sourceID then
        return facts
    end

    local info = C_TransmogCollection.GetSourceInfo(sourceID)
    if info then
        facts.sourceCollected = Bool(info.isCollected)
        facts.sourceValid = Bool(info.isValidSourceForPlayer)
        facts.useError = info.useErrorType or false
        facts.category = info.categoryID or false
    end

    local playerReady, playerCanCollect = C_TransmogCollection.PlayerCanCollectSource(sourceID)
    facts.playerCollectReady = Bool(playerReady)
    facts.playerCanCollect = Bool(playerCanCollect)
    local accountReady, accountCanCollect = C_TransmogCollection.AccountCanCollectSource(sourceID)
    facts.accountCollectReady = Bool(accountReady)
    facts.accountCanCollect = Bool(accountCanCollect)

    -- The look is known from another item. Which toon that other item is for matters to the
    -- verdict, so the collected other sources are told apart: one this toon can use
    -- (lookKnownUsable), one it cannot (lookKnownUnusable). Both can be true.
    facts.lookKnownElsewhere = false
    facts.lookKnownUsable = false
    facts.lookKnownUnusable = false
    if appearanceID then
        for _, otherSource in ipairs(C_TransmogCollection.GetAllAppearanceSources(appearanceID) or {}) do
            if otherSource ~= sourceID then
                if C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(otherSource) then
                    facts.lookKnownElsewhere = true
                end
                local other = C_TransmogCollection.GetSourceInfo(otherSource)
                if other and other.isCollected then
                    if other.isValidSourceForPlayer then
                        facts.lookKnownUsable = true
                    else
                        facts.lookKnownUnusable = true
                    end
                end
            end
        end
    end

    -- The one setting a status of this kind hangs on: whether a look known from another item
    -- is shown as learnable at all (ownPlus, otherPlus). It is the player's choice, an input
    -- like the toon's level, and a shape that expects a Plus status has to ask for it.
    local shown = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon and CaerdonWardrobeConfig.Icon.ShowLearnable
    facts.sameLookShown = Bool(shown and shown.SameLookDifferentItem)
    return facts
end

function Facts.Toy(item, facts)
    facts.isToy = C_ToyBox.GetToyInfo(item:GetItemID()) ~= nil
    facts.toyCollected = Bool(PlayerHasToy(item:GetItemID()))
    return facts
end

function Facts.Mount(item, facts)
    local mountID = C_MountJournal.GetMountFromItem(item:GetItemID())
    facts.mountID = mountID or false
    if mountID then
        facts.mountCollected = Bool(select(11, C_MountJournal.GetMountInfoByID(mountID)))
    end
    return facts
end

local READERS = { appearance = Facts.Appearance, toy = Facts.Toy, mount = Facts.Mount }

-- kind: "appearance", "toy", "mount", or nil for the general facts alone.
function Facts.Read(kind, item)
    local facts = Facts.Item(item)
    local reader = kind and READERS[kind]
    if reader then
        reader(item, facts)
    end
    return facts
end

-- The tooltip's lines as the client hands them out, every field kept.
function Facts.TooltipLines(link)
    local data = C_TooltipInfo.GetHyperlink(link)
    local lines = {}
    for index, line in ipairs(data and data.lines or {}) do
        lines[index] = T.Plain(line, 3)
    end
    return lines
end

------------------------------------------------------------------------------------------
-- Comparing (no client calls below)
------------------------------------------------------------------------------------------

-- Where facts do not fit a shape: a list of { key, want, have }, or nil when they fit.
function Facts.Mismatch(shape, facts)
    local misses
    for _, key in ipairs(T.SortedKeys(shape)) do
        if facts[key] ~= shape[key] then
            misses = misses or {}
            misses[#misses + 1] = { key = key, want = shape[key], have = facts[key] }
        end
    end
    return misses
end

-- What changed between two sets of facts: key -> { before, after }, or nil when equal.
function Facts.Diff(before, after)
    local changed
    local function note(key)
        changed = changed or {}
        changed[key] = { before = before[key], after = after[key] }
    end
    for key, value in pairs(before) do
        if after[key] ~= value then note(key) end
    end
    for key in pairs(after) do
        if before[key] == nil then note(key) end
    end
    return changed
end

function Facts.DescribeMisses(misses)
    local parts = {}
    for _, miss in ipairs(misses) do
        parts[#parts + 1] = ("%s is %s, not %s"):format(miss.key, tostring(miss.have), tostring(miss.want))
    end
    return table.concat(parts, "; ")
end

function Facts.DescribeDiff(changed)
    local parts = {}
    for _, key in ipairs(T.SortedKeys(changed)) do
        parts[#parts + 1] = ("%s %s -> %s"):format(key, tostring(changed[key].before), tostring(changed[key].after))
    end
    return table.concat(parts, "; ")
end
