-- Snapshot and diff: what the addon decides and draws for everything in the bags and bank.
--
-- One from before a change to the addon's code and one from after; the diff is every item
-- whose status, text or icon is no longer the same. This is the guard for refactoring. Every
-- session takes one by itself and compares it with the last session's (at the end of this
-- file); /cwtest snapshot base and /cwtest snapshot do the same on demand, against a base that
-- stays until it is replaced.
--
-- Every item is sent through the addon's own queue and drawn on a hidden button that belongs
-- to the tests, under a stand-in for the Bags or Bank feature. So the result does not depend
-- on which bag addon is installed or which windows are open, and nothing on screen changes.
-- The bank's contents can only be read while the bank is open.

local _, T = ...

------------------------------------------------------------------------------------------
-- Keys and comparing (no client calls)
------------------------------------------------------------------------------------------

-- The item a link stands for, without the two fields that say who looked at it (the linking
-- toon's level and specialization), so the same item keeps its key after a level-up.
function T.ItemKey(link)
    local itemString = link:match("|H(item:[^|]+)|h") or link:match("^(item:[%-%d:]+)$")
    if not itemString then
        return link:match("|H([^|]+)|h") or link
    end
    local parts = {}
    for part in (itemString .. ":"):gmatch("([^:]*):") do
        parts[#parts + 1] = part
    end
    if parts[10] then parts[10] = "" end -- linkLevel
    if parts[11] then parts[11] = "" end -- specializationID
    while #parts > 2 and parts[#parts] == "" do
        parts[#parts] = nil
    end
    return table.concat(parts, ":")
end

local DRAWN_FIELDS = { "icon", "iconColor", "iconAlpha", "iconSize", "iconPoint", "desaturated", "badge", "text", "gain" }

-- Everything a player would see, as one string to compare.
local function Signature(entry)
    local parts = { tostring(entry.status), tostring(entry.binding) }
    local drawn = entry.drawn or {}
    for _, field in ipairs(DRAWN_FIELDS) do
        parts[#parts + 1] = tostring(drawn[field])
    end
    return table.concat(parts, "|")
end
T.SnapshotSignature = Signature

-- What a player would see of an entry, by field.
local function Visible(entry)
    local seen = { status = entry.status, binding = entry.binding, note = entry.note }
    local drawn = entry.drawn or {}
    for _, field in ipairs(DRAWN_FIELDS) do
        seen[field] = drawn[field]
    end
    return seen
end

-- Dotted keys whose values differ between two plain tables.
local function DeepDiff(before, after, prefix, found)
    found = found or {}
    prefix = prefix or ""
    local keys = {}
    for key in pairs(type(before) == "table" and before or {}) do keys[key] = true end
    for key in pairs(type(after) == "table" and after or {}) do keys[key] = true end
    for _, key in ipairs(T.SortedKeys(keys)) do
        local left = type(before) == "table" and before[key] or nil
        local right = type(after) == "table" and after[key] or nil
        if type(left) == "table" or type(right) == "table" then
            DeepDiff(left, right, prefix .. tostring(key) .. ".", found)
        elseif left ~= right then
            found[#found + 1] = ("%s%s: %s -> %s"):format(prefix, tostring(key), tostring(left), tostring(right))
        end
    end
    return found
end
T.DeepDiff = DeepDiff

-- Compares two snapshots. Only containers both of them read are compared (a base taken
-- away from the bank says nothing about the bank), and only items both of them hold: an item
-- that came or went is listed, not judged.
function T.DiffSnapshots(base, after)
    local shared = {}
    for container in pairs(base.containers) do
        if after.containers[container] ~= nil then
            shared[container] = true
        end
    end

    local function Group(snapshot)
        local groups = {}
        for _, entry in ipairs(snapshot.entries) do
            if shared[entry.bag] then
                local group = groups[entry.key]
                if not group then
                    group = { link = entry.link, entries = {} }
                    groups[entry.key] = group
                end
                group.entries[#group.entries + 1] = entry
            end
        end
        -- Copies of an item are one case unless they differ (a locked box beside an open one),
        -- so splitting a stack is not a change.
        for _, group in pairs(groups) do
            local signatures = {}
            group.bySignature = {}
            for _, entry in ipairs(group.entries) do
                local signature = Signature(entry)
                if not group.bySignature[signature] then
                    group.bySignature[signature] = entry
                    signatures[#signatures + 1] = signature
                end
            end
            table.sort(signatures)
            group.signature = table.concat(signatures, "\n")
        end
        return groups
    end

    -- The copy of an item that the other snapshot has no match for.
    local function Unmatched(group, other)
        for _, signature in ipairs(T.SortedKeys(group.bySignature)) do
            if not other.bySignature[signature] then
                return group.bySignature[signature]
            end
        end
        return group.entries[1]
    end

    local before, now = Group(base), Group(after)
    local diff = {
        base = { at = base.at, label = base.label, subjectVersion = base.subjectVersion, build = base.build },
        after = { at = after.at, label = after.label, subjectVersion = after.subjectVersion, build = after.build },
        same = 0,
        changed = {},
        onlyInBase = {},
        onlyInAfter = {},
        containersCompared = T.SortedKeys(shared),
        settingsChanged = DeepDiff(base.config, after.config),
    }
    for _, key in ipairs(T.SortedKeys(before)) do
        local old, new = before[key], now[key]
        if not new then
            diff.onlyInBase[#diff.onlyInBase + 1] = old.link
        elseif old.signature == new.signature then
            diff.same = diff.same + 1
        else
            local first, second = Unmatched(old, new), Unmatched(new, old)
            local shown = T.Facts.Diff(Visible(first), Visible(second)) or {}
            diff.changed[#diff.changed + 1] = {
                key = key,
                link = new.link,
                shown = shown,
                summary = T.Facts.DescribeDiff(shown),
                copies = { before = #old.entries, after = #new.entries },
                why = T.Facts.Diff(first.why or {}, second.why or {}),
                transmog = T.Facts.Diff(first.transmog or {}, second.transmog or {}),
            }
        end
    end
    for _, key in ipairs(T.SortedKeys(now)) do
        if not before[key] then
            diff.onlyInAfter[#diff.onlyInAfter + 1] = now[key].link
        end
    end
    return diff
end

------------------------------------------------------------------------------------------
-- Drawing on hidden buttons
------------------------------------------------------------------------------------------

local holder
local buttons = {}
local awaiting = {} -- button -> function called when the addon has drawn it

local function GetButton(index)
    if not holder then
        holder = CreateFrame("Frame", nil, UIParent)
        holder:SetSize(37, 37)
        holder:SetPoint("CENTER")
        holder:Hide()
    end
    local button = buttons[index]
    if not button then
        local ok
        ok, button = pcall(CreateFrame, "ItemButton", nil, holder)
        if not ok then
            button = CreateFrame("Button", nil, holder)
            button.icon = button:CreateTexture(nil, "BORDER")
            button.icon:SetAllPoints()
        end
        button:SetSize(37, 37) -- the default slot, which the icon sizes are defined against
        button:SetPoint("CENTER")
        buttons[index] = button
    end
    return button
end

-- A feature that draws like the real one but answers to its own name, so its requests never
-- share a queue key with the real window's, and that reports each finished draw.
local proxies = {}

local function GetProxy(featureName)
    local proxy = proxies[featureName]
    if proxy == nil then
        local real = CaerdonWardrobe:GetFeature(featureName)
        if not real then
            proxies[featureName] = false
            return nil
        end
        proxy = setmetatable({}, { __index = real })
        function proxy:GetName()
            return "Tests:" .. featureName
        end
        function proxy:GetStatusRuleName()
            return real:GetStatusRuleName()
        end
        function proxy:IsSameItem()
            return true
        end
        function proxy:OnButtonDrawn(button)
            local finish = awaiting[button]
            if finish then
                awaiting[button] = nil
                finish()
            end
        end
        proxies[featureName] = proxy
    end
    return proxy or nil
end

local function Round(value, places)
    local factor = 10 ^ places
    return math.floor(value * factor + 0.5) / factor
end

-- What the addon left on a button: icon, text and level gain.
local function ReadDrawn(button)
    local drawn = {}
    local overlay = CaerdonWardrobe:GetCaerdonButton(button)
    if not overlay then
        return drawn
    end
    local hasIcon, hasText, hasGain = CaerdonWardrobe:GetDrawnParts(button)
    local icon = overlay.mogStatus
    if hasIcon and icon then
        drawn.icon = tostring((icon.GetAtlas and icon:GetAtlas()) or icon:GetTexture())
        local r, g, b = icon:GetVertexColor()
        drawn.iconColor = ("%.2f,%.2f,%.2f"):format(r, g, b)
        drawn.iconAlpha = Round(icon:GetAlpha(), 2)
        drawn.iconSize = Round(icon:GetWidth(), 1)
        local point, _, _, x, y = icon:GetPoint(1)
        if point then
            drawn.iconPoint = ("%s %.1f %.1f"):format(point, x or 0, y or 0)
        end
        drawn.desaturated = icon:IsDesaturated() and true or false
        drawn.badge = overlay.caerdonHasUpgradeBadge and true or false
    end
    if hasText and overlay.bindsOnText then
        drawn.text = overlay.bindsOnText:GetText()
    end
    if hasGain and overlay.upgradeDeltaText then
        drawn.gain = overlay.upgradeDeltaText:GetText()
    end
    return drawn
end

-- For the other check that draws on the hidden buttons (Rotation.lua). Jobs run one at a
-- time, so the buttons are shared: whoever used one clears it.
T.HiddenButton = GetButton
T.FeatureProxy = GetProxy
T.ReadDrawn = ReadDrawn

-- finish is called once the addon has drawn the hidden button; nil stops waiting for it.
function T.AwaitDraw(button, finish)
    awaiting[button] = finish
end

------------------------------------------------------------------------------------------
-- Taking a snapshot
------------------------------------------------------------------------------------------

local DRAW_TIMEOUT = 30

-- part: "bags" or "bank" for one of the two; nil for the bags, and the bank while it is open.
local function ListContainers(part)
    local list = {}
    if part ~= "bank" then
        for bag = Enum.BagIndex.Backpack, Enum.BagIndex.ReagentBag do
            list[#list + 1] = { id = bag, feature = "Bags" }
        end
    end
    if part ~= "bags" and T.IsOpen("bank") then
        for _, bankType in ipairs({ Enum.BankType.Character, Enum.BankType.Account }) do
            -- A client without that kind of bank may refuse the question.
            local ok, tabIDs = pcall(C_Bank.FetchPurchasedBankTabIDs, bankType)
            for _, tabID in ipairs(ok and tabIDs or {}) do
                list[#list + 1] = { id = tabID, feature = "Bank" }
            end
        end
    end
    return list
end
T.ListContainers = ListContainers

-- Why an item was never drawn: how far it got on the way to a draw.
local function DescribeStuck(pending)
    local item = pending.item
    local stuck = {
        loadCalledBack = pending.loaded,     -- ContinueOnItemLoad came back
        updateRequested = pending.requested, -- so UpdateButton was called
        itemCached = item:IsItemCached() and true or false,
        customDataLoaded = item.customDataLoaded and true or false,
    }
    local hasLink, link = pcall(item.GetItemLink, item)
    stuck.hasLink = hasLink and link ~= nil
    -- The addon's own answer now: not ready means the tooltip never became readable.
    local ok, isReady, status = pcall(item.GetCaerdonStatus, item, pending.proxy, pending.locationInfo)
    if ok then
        stuck.statusReady = isReady and true or false
        stuck.status = status
    else
        stuck.statusError = tostring(isReady)
    end
    return stuck
end

-- Inside a job. Returns the snapshot.
local function Take(label, part)
    local toon, client = T.GetToon(), T.GetClient()
    local snapshot = {
        label = label,
        at = GetServerTime(),
        toon = toon.key,
        sig = toon.signature,
        flavor = client.flavor,
        build = client.build,
        subjectVersion = C_AddOns.GetAddOnMetadata(T.SUBJECT, "Version"),
        addons = T.NoteAddons(),
        part = part,
        bank = part ~= "bags" and T.IsOpen("bank") and true or false,
        config = T.Plain(CaerdonWardrobeConfig, 5),
        containers = {},
        entries = {},
    }

    local waiting, used = 0, 0
    local pendingByEntry = {}
    for _, container in ipairs(ListContainers(part)) do
        local proxy = GetProxy(container.feature)
        local filled = 0
        for slot = 1, C_Container.GetContainerNumSlots(container.id) do
            local info = C_Container.GetContainerItemInfo(container.id, slot)
            if proxy and info and info.hyperlink then
                filled = filled + 1
                used = used + 1
                local button = GetButton(used)
                local entry = {
                    bag = container.id,
                    slot = slot,
                    itemID = info.itemID,
                    link = info.hyperlink,
                    count = info.stackCount,
                    key = T.ItemKey(info.hyperlink) .. (info.isBound and "|B" or ""),
                }
                snapshot.entries[#snapshot.entries + 1] = entry

                local item = CaerdonItem:CreateFromBagAndSlot(container.id, slot)
                local locationInfo = { bag = container.id, slot = slot }
                local options = container.feature == "Bank" and { relativeFrame = button.icon } or {}
                waiting = waiting + 1
                awaiting[button] = function()
                    waiting = waiting - 1
                    entry.drawn = ReadDrawn(button)
                    -- The verdict behind the draw; the addon has it cached by now.
                    local _, status, bindingStatus, bindingResult = item:GetCaerdonStatus(proxy, locationInfo)
                    entry.status, entry.binding = status, bindingStatus
                    entry.type = tostring(item:GetCaerdonItemType())
                    entry.why = T.Facts.Scalars(bindingResult)
                    local data = item:GetItemData()
                    if data and data.GetTransmogInfo then
                        entry.transmog = T.Facts.Scalars(data:GetTransmogInfo())
                    end
                end
                local pending = { item = item, proxy = proxy, locationInfo = locationInfo, loaded = false, requested = false }
                pendingByEntry[entry] = pending
                item:ContinueOnItemLoad(function()
                    pending.loaded = true
                    -- The addon may call back twice (notes: LoadSources).
                    if not pending.requested and awaiting[button] then
                        pending.requested = true
                        CaerdonWardrobe:UpdateButton(button, item, proxy, locationInfo, options)
                    end
                end)
                if used % 25 == 0 then
                    T.Yield()
                end
            end
        end
        snapshot.containers[container.id] = filled
    end

    T.WaitUntil(function() return waiting == 0 end, DRAW_TIMEOUT)

    snapshot.notDrawn = 0
    for index = 1, used do
        local button = buttons[index]
        if awaiting[button] then
            awaiting[button] = nil
            snapshot.notDrawn = snapshot.notDrawn + 1
        end
        CaerdonWardrobe:ClearButton(button)
        CaerdonWardrobe:ClearButtonState(button)
    end
    for _, entry in ipairs(snapshot.entries) do
        if not entry.drawn then
            entry.note = "never drawn (item or tooltip not ready)"
            entry.stuck = DescribeStuck(pendingByEntry[entry])
        end
    end
    return snapshot
end

-- /cwtest snapshot base: this is what later snapshots are compared with.
-- /cwtest snapshot: compare with the base. Without a base, this one becomes it.
function T.TakeSnapshot(asBase)
    T.Start("snapshot", function()
        T.Print("reading the bags%s...", T.IsOpen("bank") and " and the bank" or " (the bank is closed, so it is left out)")
        local snapshot = Take(asBase and "base" or "after")
        local store = T.db.snapshots[snapshot.toon] or {}
        T.db.snapshots[snapshot.toon] = store

        local summary = ("%d items%s"):format(#snapshot.entries,
            snapshot.notDrawn > 0 and (", %d never drawn"):format(snapshot.notDrawn) or "")
        if asBase or not store.base then
            snapshot.label = "base"
            store.base, store.last, store.diff = snapshot, nil, nil
            T.Print("base snapshot taken: %s. Reload to save it, change the code, then /cwtest snapshot.", summary)
        else
            store.last = snapshot
            store.diff = T.DiffSnapshots(store.base, snapshot)
            local diff = store.diff
            -- nil when the base's set is no longer on record.
            diff.addonsChanged = T.DiffAddonSets(T.GetAddonSet(store.base.addons), T.GetAddonSet(snapshot.addons))
            T.Print("snapshot taken: %s. Against the base: %d the same, %s%d changed|r, %d only in the base, %d new.",
                summary, diff.same, #diff.changed > 0 and "|cffff4040" or "|cff40ff40", #diff.changed,
                #diff.onlyInBase, #diff.onlyInAfter)
            for index = 1, math.min(#diff.changed, 8) do
                local change = diff.changed[index]
                print(("  %s: %s"):format(change.link, change.summary))
            end
            if #diff.settingsChanged > 0 then
                T.Print("the addon's settings differ from the base (%d values), which can change what is drawn.",
                    #diff.settingsChanged)
            end
            if diff.addonsChanged == nil then
                T.Print("the base is too old to say which other addons it was taken with: take a new base.")
            elseif #diff.addonsChanged > 0 then
                T.Print("other addons differ from the base (%d), which can change what is drawn: take a new base before judging a change.",
                    #diff.addonsChanged)
                for index = 1, math.min(#diff.addonsChanged, 6) do
                    print("  " .. diff.addonsChanged[index])
                end
            end
        end
        if T.OnTestsFinished then
            T.OnTestsFinished()
        end
    end)
end

------------------------------------------------------------------------------------------
-- By itself, once a session
------------------------------------------------------------------------------------------

-- A change is proven by what was drawn before it against what is drawn after, and the
-- "before" cannot be asked for by hand: the game is often closed while the code is changed,
-- and the next login already runs the new code. So every session records by itself what the
-- bags show, and the bank the first time it is opened, and compares each with the same
-- record of the session before. The last session is the base.
--
-- A reload is a session too, so a comparison is between two loads of the code. What each one
-- found is kept as a short history: the reload that saves a result has taken the next record
-- by the time anyone reads it.

local AUTO_KEEP = 12      -- comparisons kept per toon
local AUTO_CHANGES = 40   -- changed items kept per comparison
local autoAllowed = false -- nothing is drawn by the tests before the login record is written
local autoStarted = {}    -- part -> true once this session has asked for it

local function AutoSnapshot(part)
    if not autoAllowed or autoStarted[part] or T.GetPlan().autoSnapshot == false then
        return
    end
    -- A rotation run counts what each stop draws, so the tests draw nothing of their own into it.
    if T.db.rotation and T.db.rotation.run then
        return
    end
    autoStarted[part] = true
    T.Start("snapshot of the " .. part, function()
        -- The window's own draws first: the bank draws everything when it opens.
        if not T.WaitForIdle(0.5, 30) or (part == "bank" and not T.IsOpen("bank")) then
            autoStarted[part] = nil
            return
        end
        local snapshot = Take("session", part)
        if part == "bank" and not T.IsOpen("bank") then
            -- Closed while it was read: what was read is not the whole bank. Next time.
            autoStarted[part] = nil
            return
        end
        if #snapshot.entries == 0 then
            return
        end

        local store = T.db.snapshots[snapshot.toon] or {}
        T.db.snapshots[snapshot.toon] = store
        store.auto = store.auto or { history = {} }
        local previous = store.auto[part]
        store.auto[part] = snapshot
        if not previous then
            return
        end

        local diff = T.DiffSnapshots(previous, snapshot)
        diff.part = part
        diff.items = #snapshot.entries
        diff.notDrawn = snapshot.notDrawn
        -- nil when the earlier session's set is no longer on record.
        diff.addonsChanged = T.DiffAddonSets(T.GetAddonSet(previous.addons), T.GetAddonSet(snapshot.addons))
        diff.changedCount = #diff.changed
        for index = #diff.changed, AUTO_CHANGES + 1, -1 do
            diff.changed[index] = nil
        end
        T.Push(store.auto.history, diff, AUTO_KEEP)

        -- Said only when something is drawn differently: that is what a change must explain.
        if diff.changedCount > 0 then
            T.Print("|cffff4040%d of %d items in the %s are drawn differently than in the last session:|r",
                diff.changedCount, diff.same + diff.changedCount, part)
            for index = 1, math.min(#diff.changed, 6) do
                local change = diff.changed[index]
                print(("  %s: %s"):format(change.link, change.summary))
            end
            local settings, addons = #diff.settingsChanged, #(diff.addonsChanged or {})
            if settings > 0 or addons > 0 then
                T.Print("the addon's settings (%d values) or other addons (%d) differ too, which can be why.",
                    settings, addons)
            end
        end
    end)
end

-- Called once the login record is written (Commands.lua).
function T.StartAutoSnapshots()
    autoAllowed = true
    AutoSnapshot("bags")
    if T.IsOpen("bank") then
        AutoSnapshot("bank")
    end
end

T.RegisterEvent("BANKFRAME_OPENED", function()
    AutoSnapshot("bank")
end)

------------------------------------------------------------------------------------------
-- Probing single items
------------------------------------------------------------------------------------------

-- Everything the client and the addon say about some items, by ID: the way to look at an
-- item the toon does not carry, or to find a replacement for a retired test case.
function T.ProbeItems(itemIDs, quiet)
    T.Start("probe", function()
        local toon = T.GetToon()
        local store = T.db.probes[toon.key] or {}
        T.db.probes[toon.key] = store
        for _, itemID in ipairs(itemIDs) do
            local probe = { at = GetServerTime(), sig = toon.signature, build = T.GetClient().build }
            local item, why = T.LoadItem(itemID)
            if not item then
                probe.note = why
            else
                local facts = T.Facts.Item(item)
                T.Facts.Appearance(item, facts)
                T.Facts.Toy(item, facts)
                T.Facts.Mount(item, facts)
                probe.link = item:GetItemLink()
                probe.facts = facts
                probe.type = tostring(item:GetCaerdonItemType())
                probe.tooltip = T.Facts.TooltipLines(probe.link)
                local ready, status, bindingStatus, bindingResult = T.GetVerdict(item)
                if ready then
                    probe.status, probe.binding = status, bindingStatus
                    probe.why = T.Facts.Scalars(bindingResult)
                    local data = item:GetItemData()
                    if data and data.GetTransmogInfo then
                        probe.transmog = T.Facts.Scalars(data:GetTransmogInfo())
                    end
                else
                    probe.note = "the addon had no verdict (tooltip not ready)"
                end
            end
            store[itemID] = probe
            if not quiet then
                T.Print("item %d: %s", itemID, probe.note or ("status " .. tostring(probe.status)))
            end
            T.Yield()
        end
    end)
end
