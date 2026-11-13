-- Outdated food and drink.
--
-- A food or drink item counts as outdated - and gets the sellable icon - when the toon carries
-- a better one of the same kind that it can use right now. Comparing against what is carried,
-- rather than against the toon's level alone, means the last stack is never marked just because
-- a better tier exists somewhere at a vendor.
--
--   kind:   "food" (restores health), "drink" (restores mana). Items that restore both are left
--           alone. Nothing in the item API separates the two, so the tooltip's restore line is
--           read (localized HEALTH / MANA words).
--   buff:   food with an extra effect ("well fed") is only ever compared with other buff food.
--   better: a higher required level, or the same required level and a larger restore amount.
--
-- Hunters feed food to their pet, and a pet still eats food well below its own level, so for a
-- hunter food must also sit more than HUNTER_FOOD_LEVEL_GAP item levels below the toon's level.
--
-- CaerdonItemMixin:GetFoodDrinkInfo() is the entry point for callers; the Debug Frame export
-- prints the classification and the comparison ("[Food and Drink]").

local ADDON_NAME, NS = ...

CaerdonFoodDrink = {}

local HUNTER_FOOD_LEVEL_GAP = 20

local FOOD_DRINK_SUBCLASS = Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.Fooddrink or 5

-- itemID -> classification (only stored once the tooltip gave a restore line)
local classifications = {}
-- Carried food and drink: { items = { [itemID] = classification }, signature = "..." }
local carried

local function LowerWord(globalName, fallback)
    local word = _G[globalName]
    if type(word) ~= "string" or word == "" then
        word = fallback
    end
    return word:lower()
end

local function IsFoodDrinkItem(itemID)
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    return classID == Enum.ItemClass.Consumable and subClassID == FOOD_DRINK_SUBCLASS
end

-- Reads the restore line out of the tooltip. Returns nil while the tooltip has no such line
-- (item or spell text not loaded yet, or not really food or drink).
local function ReadRestoreLine(itemLink)
    local data = C_TooltipInfo and C_TooltipInfo.GetHyperlink(itemLink)
    if not data or not data.lines then
        return nil
    end

    local healthWord = LowerWord("HEALTH", "health")
    local manaWord = LowerWord("MANA", "mana")

    for _, line in ipairs(data.lines) do
        local text = line.leftText and tostring(line.leftText) or nil
        if text and text:find("%d") then
            local lower = text:lower()
            local hasHealth = lower:find(healthWord, 1, true) ~= nil
            local hasMana = lower:find(manaWord, 1, true) ~= nil
            if hasHealth or hasMana then
                -- The line ends in a cooldown note, "(1 |4Sec:Sec; Cooldown)" on WoW Forever:
                -- drop it and any plural escape so their digits are not counted as effects.
                local counted = text:gsub("%s*%([^%)]*%)%s*$", ""):gsub("|4[^;]*;", "")
                local numbers = {}
                for number in counted:gmatch("%d[%d,%.]*") do
                    numbers[#numbers + 1] = tonumber((number:gsub("[,%.]", ""))) or 0
                end
                local kind = hasHealth and hasMana and "both" or hasHealth and "food" or "drink"
                -- "Restores 61 health over 18 sec": an amount and a duration (one more amount
                -- when both are restored). Anything beyond that is an extra effect.
                local expected = kind == "both" and 3 or 2
                return {
                    kind = kind,
                    amount = numbers[1] or 0,
                    isBuff = #numbers > expected,
                    text = text
                }
            end
        end
    end
    return nil
end

-- kind / amount / isBuff / requiredLevel / itemLevel for a food or drink item; nil for anything
-- else or while its tooltip is not available.
function CaerdonFoodDrink:Classify(itemID, itemLink)
    if not itemID then
        return nil
    end
    local known = classifications[itemID]
    if known then
        return known
    end
    if not IsFoodDrinkItem(itemID) then
        return nil
    end

    itemLink = itemLink or select(2, C_Item.GetItemInfo(itemID))
    if not itemLink then
        return nil
    end
    local name, _, _, itemLevel, requiredLevel, _, _, _, _, _, _, _, _, _, _, _, isCraftingReagent =
        C_Item.GetItemInfo(itemLink)
    if not name then
        return nil
    end

    local restore = ReadRestoreLine(itemLink)
    if not restore then
        return nil
    end

    local classification = {
        itemID = itemID,
        name = name,
        kind = restore.kind,
        amount = restore.amount,
        isBuff = restore.isBuff,
        text = restore.text,
        requiredLevel = requiredLevel or 0,
        itemLevel = itemLevel or 0,
        isCraftingReagent = isCraftingReagent == true
    }
    classifications[itemID] = classification
    return classification
end

local function BuildCarried()
    local items = {}
    local parts = {}
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

    for bag = 0, lastBag do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID and not items[itemID] and IsFoodDrinkItem(itemID) then
                local classification = CaerdonFoodDrink:Classify(itemID, C_Container.GetContainerItemLink(bag, slot))
                if classification then
                    items[itemID] = classification
                    parts[#parts + 1] = itemID
                end
            end
        end
    end

    table.sort(parts)
    return { items = items, signature = table.concat(parts, ",") }
end

local function GetCarried()
    if not carried then
        carried = BuildCarried()
    end
    return carried
end

function CaerdonFoodDrink:InvalidateCaches()
    carried = nil
end

local function IsBetter(candidate, item)
    if candidate.requiredLevel ~= item.requiredLevel then
        return candidate.requiredLevel > item.requiredLevel
    end
    return candidate.amount > item.amount
end

-- The verdict for one item, or nil when it is not food or drink (or not readable yet).
--   isOutdated: mark it sellable
--   reason: why, in words
--   betterItem: the carried item that beats it, when there is one
function CaerdonFoodDrink:GetItemInfo(itemID, itemLink)
    local item = self:Classify(itemID, itemLink)
    if not item then
        return nil
    end

    local info = {
        isOutdated = false,
        kind = item.kind,
        amount = item.amount,
        isBuff = item.isBuff,
        requiredLevel = item.requiredLevel,
        itemLevel = item.itemLevel,
        text = item.text
    }

    local playerLevel = UnitLevel("player") or 1
    if item.kind == "both" then
        info.reason = "restores health and mana; left alone"
        return info
    end
    if item.isCraftingReagent then
        info.reason = "crafting reagent"
        return info
    end
    if item.requiredLevel > playerLevel then
        info.reason = "not usable yet"
        return info
    end

    local better
    for otherID, other in pairs(GetCarried().items) do
        if otherID ~= itemID and other.kind == item.kind and other.isBuff == item.isBuff and
            other.requiredLevel <= playerLevel and IsBetter(other, item) then
            if not better or IsBetter(other, better) then
                better = other
            end
        end
    end

    if not better then
        info.reason = "nothing better of this kind in the bags"
        return info
    end
    info.betterItem = better

    local _, classFile = UnitClass("player")
    if classFile == "HUNTER" and item.kind == "food" then
        info.hunterLevelGap = HUNTER_FOOD_LEVEL_GAP
        if item.itemLevel >= playerLevel - HUNTER_FOOD_LEVEL_GAP then
            info.reason = string.format("better food carried, but a hunter's pet still eats this (item level %d, cut-off below %d)",
                item.itemLevel, playerLevel - HUNTER_FOOD_LEVEL_GAP)
            return info
        end
    end

    info.isOutdated = true
    info.reason = "better one carried"
    return info
end

-- Buying or looting a better stack changes the verdict for the stacks already in the bags, and
-- only the slot that changed is redrawn. Refresh everything when the carried set changes.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:SetScript("OnEvent", function()
    if not (CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon and CaerdonWardrobeConfig.Icon.ShowOutdatedFood) then
        return
    end
    local previous = carried
    if not previous then
        -- Nothing was judged since the last refresh, so nothing on screen can be stale.
        return
    end
    local current = BuildCarried()
    if current.signature ~= previous.signature then
        carried = nil
        if CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
            CaerdonWardrobe:RefreshItems()
        end
    else
        carried = current
    end
end)
