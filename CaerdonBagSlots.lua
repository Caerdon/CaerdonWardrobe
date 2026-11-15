-- Bags for the toon's bag slots.
--
-- A bag is worth equipping when a slot it fits is empty or holds something it improves on,
-- and worth nothing to this toon once it would improve none of them. This module holds a bag
-- item against every bag slot it fits, as those slots are right now:
--
--   upgrade: a slot it fits is empty, or it is better than the bag in one of them.
--   spare:   every slot it fits is filled and it is better than none of them.
--   neither: a comparison that cannot be decided stands in the way (see below).
--
-- Three kinds of bag (item class Container):
--   bag:        an ordinary bag (subclass Bag). Fits the normal bag slots.
--   reagent:    a reagent bag (subclass Reagent). Fits the reagent bag slot.
--   profession: every other subclass (herb, engineering, mining, soul, ...). Fits the normal
--               bag slots, and on WoW Forever the reagent bag slot as well (seen in game: an
--               engineering bag and a herb bag were equipped there, the herb bag in a normal
--               slot too). Retail's reagent slot does not take them, and no API says which it
--               is, so that slot counts for a profession bag where the classic ranged slot is
--               shown (the stand-in for "classic equipment rules" used elsewhere) or once a
--               profession bag has been seen in it.
--
-- What is in a slot is read from the item that is really there, never assumed from the slot.
--
-- Better than the bag in a slot:
--   same kind (and for profession bags the same subclass): more slots. Equal is no gain.
--   an ordinary bag against a profession or reagent bag: at least as many slots, because it
--     holds everything the other one does and more.
--   a reagent bag against a profession bag: more slots.
-- Not better: the same pairs the other way round, and a profession bag against an ordinary
--   bag at least as big.
-- Cannot be decided, so no verdict in either direction: a reagent bag against a profession bag
--   with as much room or more, a profession bag against a reagent bag or a profession bag of
--   another subclass, and a profession bag against a smaller ordinary bag (more room for fewer
--   kinds of items). What a reagent bag holds compared with a profession bag is not known.
--
-- Quivers and ammo pouches (item class Quiver, kind "quiver") are compared with their own
-- subclass only: a bigger quiver beats a smaller quiver, and one no bigger than a quiver that
-- is equipped is a spare. Against every other kind of bag, in both directions, the slot is
-- skipped: on classic-era rules a quiver is worn for what it does (ranged attack speed), not
-- for its room, so room says nothing about a quiver against a bag. They fit the normal bag
-- slots only: on WoW Forever a quiver will not go in the reagent bag slot (tried in game).
--
-- A quiver is no use to a toon that shoots nothing (a priest's ranged weapon is a wand), so an
-- empty slot only makes one an upgrade when the toon has the weapon for it equipped right now:
-- a bow or crossbow for a quiver, a gun for an ammo pouch. Read from the equipped item, not
-- from a list of classes. A quiver of the same kind already equipped counts as using one.
--
-- No API gives the size of a bag that is not equipped, so the tooltip's "6 Slot Bag" line is
-- read (the CONTAINER_SLOTS format). Equipped bags are read from the container API.
--
-- CaerdonItemMixin:GetBagSlotInfo() is the entry point for callers; the Debug Frame export
-- prints the slots and the comparison ("[Bag Slots]").

local ADDON_NAME, NS = ...

CaerdonBagSlots = {}

local CONTAINER_CLASS = Enum.ItemClass and Enum.ItemClass.Container or 1
local BAG_SUBCLASS = Enum.ItemContainerSubclass and Enum.ItemContainerSubclass.Bag or 0
local REAGENT_SUBCLASS = Enum.ItemContainerSubclass and Enum.ItemContainerSubclass.Reagent or 11
local QUIVER_CLASS = Enum.ItemClass and Enum.ItemClass.Quiver or 11
local QUIVER_SUBCLASS = Enum.ItemQuiverSubclass and Enum.ItemQuiverSubclass.Quiver or 2
local AMMO_POUCH_SUBCLASS = Enum.ItemQuiverSubclass and Enum.ItemQuiverSubclass.Ammopouch or 3
local WEAPON_CLASS = Enum.ItemClass and Enum.ItemClass.Weapon or 2
local BOW_SUBCLASS = Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Bows or 2
local GUN_SUBCLASS = Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Guns or 3
local CROSSBOW_SUBCLASS = Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Crossbow or 18

-- After a bag event the slots are read at once and again this much later: container sizes
-- can lag behind the event when bags are moved around.
local RECHECK_SECONDS = 0.3

-- itemID -> { size = number, text = tooltip line, matchedBy = "format" | "subtype name" }
local sizes = {}
-- The bag slots as last read: { slots = { ... }, signature = "...", reagentTakesProfession }
local context
local slotsPattern, slotsFormat
-- A profession bag was in the reagent bag slot at some point this session.
local seenProfessionBagInReagentSlot = false

-- "bag", "reagent", "profession" or "quiver" plus the subclass and its name; nil for anything
-- that is neither a Container nor a Quiver. Subclass numbers are only comparable within one
-- kind: quiver subclass 2 (Quiver) is not container subclass 2 (Herb Bag).
local function ClassifyItem(itemInfo)
    if not itemInfo then
        return nil
    end
    local _, _, subTypeName, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemInfo)
    if classID == QUIVER_CLASS then
        return "quiver", subClassID, subTypeName
    end
    if classID ~= CONTAINER_CLASS then
        return nil
    end
    if subClassID == BAG_SUBCLASS then
        return "bag", subClassID, subTypeName
    elseif subClassID == REAGENT_SUBCLASS then
        return "reagent", subClassID, subTypeName
    end
    return "profession", subClassID, subTypeName
end

-- The tooltip format ("%d Slot %s", or a localized one with positional arguments) as a Lua
-- pattern that captures the number.
local function GetSlotsPattern()
    if not slotsPattern then
        slotsFormat = (type(CONTAINER_SLOTS) == "string" and CONTAINER_SLOTS ~= "") and CONTAINER_SLOTS or
            "%d Slot %s"
        local pattern = slotsFormat
        pattern = pattern:gsub("%%%d+%$d", "\1")
        pattern = pattern:gsub("%%d", "\1")
        pattern = pattern:gsub("%%%d+%$s", "\2")
        pattern = pattern:gsub("%%s", "\2")
        pattern = pattern:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
        pattern = pattern:gsub("\1", "(%%d+)")
        pattern = pattern:gsub("\2", ".+")
        slotsPattern = "^%s*" .. pattern .. "%s*$"
    end
    return slotsPattern, slotsFormat
end

-- The number of slots a bag item has, from its tooltip. nil while the tooltip has no such line
-- (item text not loaded yet).
local function ReadSize(itemID, itemLink)
    local known = sizes[itemID]
    if known then
        return known
    end

    local data = C_TooltipInfo and C_TooltipInfo.GetHyperlink and
        C_TooltipInfo.GetHyperlink(itemLink or ("item:" .. itemID))
    if not data or not data.lines then
        return nil
    end

    local pattern = GetSlotsPattern()
    local _, _, subTypeName = C_Item.GetItemInfoInstant(itemID)
    local fallback
    for index, line in ipairs(data.lines) do
        local text = line.leftText and tostring(line.leftText) or nil
        if text and text ~= "" then
            local size = tonumber((text:match(pattern)))
            if size and size > 0 then
                known = { size = size, text = text, matchedBy = "format" }
                break
            end
            -- Should the format ever not match (another client's wording): the one line below
            -- the name that has a single number and names the item's subtype ("Bag").
            if not fallback and index > 1 and type(subTypeName) == "string" and subTypeName ~= "" and
                text:find(subTypeName, 1, true) then
                local count, number = 0, nil
                for digits in text:gmatch("%d+") do
                    count = count + 1
                    number = tonumber(digits)
                end
                if count == 1 and number and number > 0 then
                    fallback = { size = number, text = text, matchedBy = "subtype name" }
                end
            end
        end
    end

    known = known or fallback
    if known then
        sizes[itemID] = known
    end
    return known
end

-- The bag family bits of an item: for a bag, what kind of bag it is; for anything else, which
-- kinds of bag take it. Only printed by the export so far.
local function ItemFamily(itemInfo)
    local getter = (C_Item and C_Item.GetItemFamily) or GetItemFamily
    if not getter or not itemInfo then
        return nil
    end
    local ok, family = pcall(getter, itemInfo)
    return ok and family or nil
end

-- One bag slot:
--   bag:   the container index
--   group: "bag" (a normal bag slot) or "reagent" (the reagent bag slot)
--   state: "empty", "filled", or "pending" (an item is in the slot, its size is not known yet)
--   kind:  what fills it: "bag", "reagent", "profession", "quiver", or "other" (an item of
--          some other class, or one the client names no class for); "other" is never compared
--   size, itemID, classID, subClassID, subTypeName, family, itemFamily, isProfessionBag:
--          everything the client says about it; most of it only for the export
local function ReadSlot(bag, group)
    local slot = { bag = bag, group = group, size = C_Container.GetContainerNumSlots(bag) or 0 }

    local inventoryID
    if C_Container.ContainerIDToInventoryID and GetInventoryItemID then
        local ok, result = pcall(C_Container.ContainerIDToInventoryID, bag)
        if ok and result then
            inventoryID = result
            slot.itemID = GetInventoryItemID("player", inventoryID)
        end
    end

    local kind
    if slot.itemID then
        local _
        _, _, slot.subTypeName, _, _, slot.classID, slot.subClassID = C_Item.GetItemInfoInstant(slot.itemID)
        kind = ClassifyItem(slot.itemID)
        slot.itemFamily = ItemFamily(slot.itemID)
        if inventoryID and IsInventoryItemProfessionBag then
            local ok, result = pcall(IsInventoryItemProfessionBag, "player", inventoryID)
            if ok then
                slot.isProfessionBag = result
            end
        end
    end
    if C_Container.GetContainerNumFreeSlots then
        local _, family = C_Container.GetContainerNumFreeSlots(bag)
        slot.family = family
    end

    if slot.size <= 0 then
        slot.state = slot.itemID and "pending" or "empty"
        return slot
    end

    slot.state = "filled"
    if kind then
        slot.kind = kind
    elseif slot.classID then
        -- A known item that is neither a Container nor a Quiver.
        slot.kind = "other"
    elseif group == "reagent" then
        -- No item to ask.
        slot.kind = "reagent"
    else
        -- No item to ask: an ordinary bag reports bag family 0.
        slot.kind = (slot.family == nil or slot.family == 0) and "bag" or "other"
    end
    return slot
end

-- The classic ranged slot stands in for "classic equipment rules": true on WoW Forever, false
-- on retail (types/EquipmentMixin.lua and CaerdonProfessionTools.lua use it the same way).
local function ClassicEquipmentRules()
    return C_PaperDollInfo ~= nil and C_PaperDollInfo.IsRangedSlotShown ~= nil and
        C_PaperDollInfo.IsRangedSlotShown() == true
end

-- The weapons the toon has equipped that shoot ammunition: { arrows, bullets, text }.
-- The ranged slot on classic equipment rules, the main hand where bows and guns go there.
local function ReadAmmoWeapons()
    local result = { arrows = false, bullets = false }
    local found = {}
    if GetInventoryItemID then
        for _, inventorySlot in ipairs({ INVSLOT_RANGED or 18, INVSLOT_MAINHAND or 16 }) do
            local itemID = GetInventoryItemID("player", inventorySlot)
            if itemID then
                local _, _, subTypeName, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
                if classID == WEAPON_CLASS then
                    if subClassID == BOW_SUBCLASS or subClassID == CROSSBOW_SUBCLASS then
                        result.arrows = true
                    elseif subClassID == GUN_SUBCLASS then
                        result.bullets = true
                    end
                    found[#found + 1] = string.format("slot %d: item %d, weapon subclass %s \"%s\"",
                        inventorySlot, itemID, tostring(subClassID), tostring(subTypeName))
                end
            end
        end
    end
    result.text = #found > 0 and table.concat(found, "; ") or "no weapon in the ranged or main hand slot"
    return result
end

local function BuildContext()
    local bagSlots = NUM_BAG_SLOTS or 4
    local reagentSlots = NUM_REAGENTBAG_SLOTS or 0
    local slots, parts = {}, {}
    for bag = 1, bagSlots + reagentSlots do
        local slot = ReadSlot(bag, bag <= bagSlots and "bag" or "reagent")
        slots[#slots + 1] = slot
        if slot.group == "reagent" and slot.state == "filled" and slot.kind == "profession" then
            seenProfessionBagInReagentSlot = true
        end
        parts[#parts + 1] = string.format("%d:%s:%s:%d:%s", slot.bag, slot.state, tostring(slot.kind),
            slot.size, tostring(slot.itemID or 0))
    end

    local classicRules = ClassicEquipmentRules()
    return {
        slots = slots,
        signature = table.concat(parts, ","),
        -- Not part of the signature: an equipment change refreshes everything by itself.
        ammoWeapons = ReadAmmoWeapons(),
        reagentTakesProfession = classicRules or seenProfessionBagInReagentSlot,
        reagentTakesProfessionWhy = classicRules and "classic equipment rules (ranged slot shown)" or
            seenProfessionBagInReagentSlot and "a profession bag was seen in it this session" or
            "no: retail equipment rules, and none seen in it this session",
    }
end

local function GetContext()
    if not context then
        context = BuildContext()
    end
    return context
end

function CaerdonBagSlots:InvalidateCaches()
    context = nil
end

local function Fits(kind, slot, ctx)
    if kind == "bag" then
        return slot.group == "bag"
    elseif kind == "reagent" then
        return slot.group == "reagent"
    elseif kind == "quiver" then
        return slot.group == "bag"
    end
    return slot.group == "bag" or ctx.reagentTakesProfession
end

-- How a bag of this kind and size compares with the bag in a filled slot:
--   "better":    it should replace that bag
--   "notBetter": it should not
--   "unknown":   cannot be decided (see the top of the file); blocks both verdicts
--   "skip":      the two are not compared at all (a quiver against anything but a quiver of
--                its own subclass); neither blocks a verdict nor counts towards one
local function Compare(kind, subClassID, size, slot)
    local other, otherSize = slot.kind, slot.size
    if other == "other" then
        return "skip"
    end
    if kind == "quiver" or other == "quiver" then
        if kind == other and slot.subClassID == subClassID then
            return size > otherSize and "better" or "notBetter"
        end
        return "skip"
    end
    if kind == "bag" then
        if other == "bag" then
            return size > otherSize and "better" or "notBetter"
        end
        -- It holds everything a profession or reagent bag does, so the same room is a gain.
        return size >= otherSize and "better" or "notBetter"
    elseif kind == "reagent" then
        if other == "reagent" then
            return size > otherSize and "better" or "notBetter"
        elseif other == "profession" then
            return size > otherSize and "better" or "unknown"
        end
        return "unknown"
    end
    if other == "profession" and slot.subClassID == subClassID then
        return size > otherSize and "better" or "notBetter"
    elseif other == "bag" then
        return size <= otherSize and "notBetter" or "unknown"
    end
    return "unknown"
end

local function SlotLabel(slot)
    if slot.kind == "bag" then
        return "bag"
    elseif slot.kind == "reagent" then
        return "reagent bag"
    elseif slot.kind == "profession" or slot.kind == "quiver" then
        return (type(slot.subTypeName) == "string" and slot.subTypeName ~= "") and slot.subTypeName:lower() or
            (slot.kind == "quiver" and "quiver" or "profession bag")
    end
    return "unknown kind of bag"
end

-- nil for anything that is neither a Container nor a Quiver item, otherwise
--   { kind = "bag" | "reagent" | "profession" | "quiver",
--     subClassID, subTypeName = the item's subclass within its item class,
--     isUpgrade = true when it belongs in a bag slot now,
--     isSpare = true when it would improve none of the slots it fits,
--     reason = why, in words,
--     size, sizeText, sizeMatchedBy = how big it is and the tooltip line that said so,
--     slotCount, emptySlots = the slots it fits,
--     reagentSlotCounts = for a profession bag, whether the reagent bag slot is one of them,
--     hasUse = for a quiver, whether the toon has the weapon for it (or such a quiver)
--       equipped; false keeps an empty slot from making it an upgrade,
--     replacesBag = the container whose bag it would replace, when it is an upgrade for a
--       filled slot,
--     comparisons = { { bag, group, result, kind, size, itemID, label } } for every slot it
--       fits; result is "empty", "pending", "size unknown" or one of Compare's }
function CaerdonBagSlots:GetItemInfo(itemID, itemLink)
    if not itemID then
        return nil
    end
    local kind, subClassID, subTypeName = ClassifyItem(itemID)
    if not kind then
        return nil
    end

    local ctx = GetContext()
    local info = {
        kind = kind,
        subClassID = subClassID,
        subTypeName = subTypeName,
        isUpgrade = false,
        isSpare = false,
        slotCount = 0,
        emptySlots = 0,
        comparisons = {},
    }
    if kind == "profession" then
        info.reagentSlotCounts = ctx.reagentTakesProfession
    end

    local size = ReadSize(itemID, itemLink)
    if size then
        info.size = size.size
        info.sizeText = size.text
        info.sizeMatchedBy = size.matchedBy
    end

    local pending, best, blocking, smallestNotBetter = false, nil, nil, nil
    local sameKindEquipped = false
    for _, slot in ipairs(ctx.slots) do
        if Fits(kind, slot, ctx) then
            info.slotCount = info.slotCount + 1
            if slot.state == "filled" and slot.kind == kind and slot.subClassID == subClassID then
                sameKindEquipped = true
            end
            local result
            if slot.state == "empty" then
                info.emptySlots = info.emptySlots + 1
                result = "empty"
            elseif slot.state == "pending" then
                pending = true
                result = "pending"
            elseif not size then
                result = "size unknown"
            else
                result = Compare(kind, subClassID, size.size, slot)
                if result == "better" then
                    if not best or slot.size < best.size then
                        best = slot
                    end
                elseif result == "unknown" then
                    blocking = blocking or slot
                elseif result == "notBetter" then
                    if not smallestNotBetter or slot.size < smallestNotBetter.size then
                        smallestNotBetter = slot
                    end
                end
            end
            info.comparisons[#info.comparisons + 1] = {
                bag = slot.bag,
                group = slot.group,
                result = result,
                kind = slot.kind,
                size = slot.size,
                itemID = slot.itemID,
                label = slot.state == "filled" and SlotLabel(slot) or nil,
            }
        end
    end

    if kind == "quiver" then
        -- Whether this toon shoots what the quiver holds: the weapon for it is equipped, or a
        -- quiver of the same kind already is. An unknown quiver subclass takes either weapon.
        local weapons = ctx.ammoWeapons
        local hasWeapon
        if subClassID == QUIVER_SUBCLASS then
            hasWeapon = weapons.arrows
        elseif subClassID == AMMO_POUCH_SUBCLASS then
            hasWeapon = weapons.bullets
        else
            hasWeapon = weapons.arrows or weapons.bullets
        end
        info.hasUse = hasWeapon or sameKindEquipped
    end

    if info.slotCount == 0 then
        info.reason = "this client has no slot for this kind of bag"
    elseif pending then
        info.reason = "a bag slot's contents are not known yet"
    elseif info.emptySlots > 0 and info.hasUse == false then
        info.reason = string.format("a slot is empty, but nothing equipped shoots what it holds (%s)",
            ctx.ammoWeapons.text)
    elseif info.emptySlots > 0 then
        -- Any bag beats an empty slot, so the size does not have to be readable for this.
        info.isUpgrade = true
        info.reason = info.emptySlots == 1 and "a slot it fits is empty" or
            string.format("%d slots it fits are empty", info.emptySlots)
    elseif not size then
        info.reason = "the tooltip's slot count is not readable yet"
    elseif best then
        info.isUpgrade = true
        info.replacesBag = best.bag
        info.reason = string.format("%s the %s in container %d (%d slots)",
            size.size > best.size and "bigger than" or "as big as, and holds more than,",
            SlotLabel(best), best.bag, best.size)
    elseif blocking then
        info.reason = string.format(
            "against the %s in container %d (%d slots) it cannot be decided which is worth more, so no verdict",
            SlotLabel(blocking), blocking.bag, blocking.size)
    elseif not smallestNotBetter then
        info.reason = kind == "quiver" and
            "no quiver of its kind is equipped and no slot is empty; a quiver is not compared with bags" or
            "every slot it fits holds a quiver or an unknown kind of bag; not compared"
    else
        info.isSpare = true
        info.reason = string.format("would improve none of the slots it fits (the smallest bag there: %s, %d slots)",
            SlotLabel(smallestNotBetter), smallestNotBetter.size)
    end

    return info
end

-- For the Debug Frame export: every slot with what is in it, and how tooltips are read.
function CaerdonBagSlots:GetDebugState()
    local ctx = GetContext()
    local pattern, format = GetSlotsPattern()
    local state = {
        format = format,
        formatIsDefault = not (type(CONTAINER_SLOTS) == "string" and CONTAINER_SLOTS ~= ""),
        pattern = pattern,
        reagentTakesProfession = ctx.reagentTakesProfession,
        reagentTakesProfessionWhy = ctx.reagentTakesProfessionWhy,
        ammoWeapons = string.format("arrows %s, bullets %s (%s)", tostring(ctx.ammoWeapons.arrows),
            tostring(ctx.ammoWeapons.bullets), ctx.ammoWeapons.text),
        groups = { bag = { slots = {} }, reagent = { slots = {} } },
    }
    for _, slot in ipairs(ctx.slots) do
        local group = state.groups[slot.group]
        local name = slot.itemID and C_Item.GetItemNameByID and C_Item.GetItemNameByID(slot.itemID) or nil
        if slot.state == "empty" then
            group.slots[#group.slots + 1] = string.format("container %d: empty", slot.bag)
        else
            if slot.state == "pending" then
                group.pending = true
            end
            -- Everything the client says about the bag that is really there: what a slot
            -- accepts is not documented, so this is how it gets found out.
            group.slots[#group.slots + 1] = string.format(
                "container %d: %s, %d slots (%s, item %s, class %s / subclass %s \"%s\", container family %s, item family %s, IsInventoryItemProfessionBag %s)",
                slot.bag,
                slot.state == "pending" and "pending" or
                slot.kind == "profession" and "profession bag" or
                slot.kind == "quiver" and "quiver" or
                slot.kind == "other" and "not compared" or SlotLabel(slot),
                slot.size, tostring(name or "unknown"), tostring(slot.itemID or "?"),
                tostring(slot.classID), tostring(slot.subClassID), tostring(slot.subTypeName),
                tostring(slot.family), tostring(slot.itemFamily), tostring(slot.isProfessionBag))
        end
    end
    return state
end

-- For the Debug Frame export: the item's bag family bits (see ItemFamily).
function CaerdonBagSlots:GetItemFamily(itemInfo)
    return ItemFamily(itemInfo)
end

-- Equipping, swapping or removing a bag changes the verdict for every other bag on screen,
-- and only the slots that changed are redrawn. Refresh everything when the bag slots changed.
local recheckTimer

local function CheckForChange()
    if not context then
        -- Nothing was judged since the last refresh, so nothing on screen can be stale.
        return
    end
    local current = BuildContext()
    if current.signature ~= context.signature or
        current.reagentTakesProfession ~= context.reagentTakesProfession then
        CaerdonBagSlots:InvalidateCaches()
        if CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
            CaerdonWardrobe:RefreshItems()
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
-- Fires when a bag slot's content changes; guarded in case a client does not have it.
pcall(eventFrame.RegisterEvent, eventFrame, "BAG_CONTAINER_UPDATE")
eventFrame:SetScript("OnEvent", function()
    if not context then
        return
    end
    CheckForChange()
    if recheckTimer then
        recheckTimer:Cancel()
    end
    recheckTimer = C_Timer.NewTimer(RECHECK_SECONDS, function()
        recheckTimer = nil
        CheckForChange()
    end)
end)
