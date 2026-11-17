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
-- Hunters feed food to their pet. Where the client says what the pet eats (WoW Forever), the
-- food kept for it is chosen from everything carried that it eats, raw meat included: the
-- PET_FOOD_PIECES best pieces that fit in one or two kinds, a piece counting for the square
-- of its item level. Two kinds at most, so that pet food does not fill the bags a few pieces
-- at a time. By item level, because higher food is good for longer; squared, so that the level
-- outweighs the count (counted plainly, ten pieces of level 14 beat four of level 30) while
-- the count still decides between kinds of about one level. Food kept that way is never
-- outdated, and any other food is judged as for another class.
--
-- Where the client cannot say (retail, or no pet seen yet this session), food must instead sit
-- more than HUNTER_FOOD_LEVEL_GAP item levels below the toon's level to be outdated.
--
-- CaerdonItemMixin:GetFoodDrinkInfo() is the entry point for callers; the Debug Frame export
-- prints the classification and the comparison ("[Food and Drink]").

local ADDON_NAME, NS = ...

CaerdonFoodDrink = {}

local HUNTER_FOOD_LEVEL_GAP = 20
local PET_FOOD_PIECES = 20

local FOOD_DRINK_SUBCLASS = Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.Fooddrink or 5

-- itemID -> classification (only stored once the tooltip gave a restore line)
local classifications = {}
-- Carried food and drink: { items = { [itemID] = classification }, signature = "...",
-- petFood = nil or { candidates = { { itemID, count, level } }, kept = { [itemID] = true } } }
local carried
-- itemID -> true / false: what the client said the pet eats, asked while a pet was out. nil
-- until one was. Kept while the pet is away (dismissed, dead, or the toon is mounted), so
-- that its food is not marked for sale and unmarked again each time.
local petEats

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

-- The client's pet functions, for a hunter on a client that has them; nil otherwise.
local function PetFoodSource()
    local petInfo = C_PetInfo
    if not (petInfo and petInfo.CanPetEatItem and petInfo.GetPetFoodTypes) then
        return nil
    end
    local _, classFile = UnitClass("player")
    if classFile ~= "HUNTER" then
        return nil
    end
    return petInfo
end

-- A pet that is out and has a diet. Without a diet the client has nothing to answer from, and
-- "eats nothing" would be taken for an answer.
local function PetIsOut(petInfo)
    if not UnitExists("pet") then
        return false
    end
    local diet = petInfo.GetPetFoodTypes()
    return type(diet) == "table" and #diet > 0
end

-- What `first` and, after it, `second` give of the pieces worth carrying: each piece counts
-- for the square of its item level, the higher kind first.
local function PetFoodValue(first, second)
    local taken = math.min(first.count, PET_FOOD_PIECES)
    local value = taken * first.level * first.level
    if second then
        value = value + math.min(second.count, PET_FOOD_PIECES - taken) * second.level * second.level
    end
    return value
end

-- The one or two kinds to keep for the pet out of everything carried that it eats. One kind
-- wins over two that give no more.
local function ChoosePetFood(candidates)
    table.sort(candidates, function(a, b)
        if a.level ~= b.level then
            return a.level > b.level
        elseif a.count ~= b.count then
            return a.count > b.count
        end
        return a.itemID < b.itemID
    end)

    local kept, best = {}, -1
    for i, first in ipairs(candidates) do
        local value = PetFoodValue(first)
        if value > best then
            best, kept = value, { [first.itemID] = true }
        end
        for j = i + 1, #candidates do
            local second = candidates[j]
            value = PetFoodValue(first, second)
            if value > best then
                best, kept = value, { [first.itemID] = true, [second.itemID] = true }
            end
        end
    end
    return kept
end

local function BuildCarried()
    local items = {}
    local parts = {}
    local seen = {}
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

    local petInfo = PetFoodSource()
    local askPet = petInfo ~= nil and PetIsOut(petInfo)
    if askPet then
        petEats = petEats or {}
    end
    local candidates = {}

    for bag = 0, lastBag do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID and not seen[itemID] then
                seen[itemID] = true
                if IsFoodDrinkItem(itemID) then
                    local classification = CaerdonFoodDrink:Classify(itemID, C_Container.GetContainerItemLink(bag, slot))
                    if classification then
                        items[itemID] = classification
                        parts[#parts + 1] = itemID
                    end
                end
                if askPet then
                    petEats[itemID] = petInfo.CanPetEatItem(itemID) and true or false
                end
                if petInfo and petEats and petEats[itemID] then
                    local count = C_Item.GetItemCount(itemID) or 0
                    candidates[#candidates + 1] = {
                        itemID = itemID,
                        count = count > 0 and count or 1,
                        level = math.max(select(4, C_Item.GetItemInfo(itemID)) or 1, 1)
                    }
                end
            end
        end
    end

    table.sort(parts)
    local signature = table.concat(parts, ",")

    -- Known only once a pet has answered; until then the level gap decides.
    local petFood
    if petInfo and petEats then
        petFood = { candidates = candidates, kept = ChoosePetFood(candidates) }
        local keptIDs = {}
        for itemID in pairs(petFood.kept) do
            keptIDs[#keptIDs + 1] = itemID
        end
        table.sort(keptIDs)
        signature = signature .. "|pet:" .. table.concat(keptIDs, ",")
    end

    return { items = items, signature = signature, petFood = petFood }
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

-- Drops what was learned about each food and drink this session as well. Nothing in play
-- calls it: a classification does not change, which is why a refresh keeps it. It is for a
-- test that has to see the addon ask the client everything again (docs/dev-notes.md,
-- Offline Harness).
function CaerdonFoodDrink:ForgetClassifications()
    wipe(classifications)
    carried = nil
    petEats = nil
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
    local petFood = GetCarried().petFood
    if classFile == "HUNTER" and item.kind == "food" and petFood then
        if petFood.kept[itemID] then
            info.reason = "better food carried, but this is kept for the pet"
            return info
        end
        info.isOutdated = true
        info.reason = petEats[itemID] and "better one carried, and the pet has better food" or
            "better one carried, and the pet does not eat it"
        return info
    elseif classFile == "HUNTER" and item.kind == "food" then
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

-- Whether the item is one of the kinds kept for a hunter's pet (ChoosePetFood). Raw meat is no
-- food to this module, so the ingredient rule asks before it calls one outgrown. False where
-- nothing is known of a pet.
function CaerdonFoodDrink:IsKeptForPet(itemID)
    local petFood = GetCarried().petFood
    return petFood ~= nil and petFood.kept[itemID] == true
end

-- What the client says about the hunter's pet and one item, for the export only: no verdict
-- reads it. Asked for any item, since raw meat is a trade good and not food to the rule above.
-- nil for another class and on a client without the pet food functions (retail).
function CaerdonFoodDrink:GetPetFoodDebugState(itemID, itemLink)
    local petInfo = C_PetInfo
    if not (petInfo and petInfo.CanPetEatItem and petInfo.GetPetFoodTypes and petInfo.GetPetHappiness) then
        return nil
    end
    local _, classFile = UnitClass("player")
    if classFile ~= "HUNTER" then
        return nil
    end

    local state = { hasPet = UnitExists("pet") and true or false }
    if state.hasPet then
        state.petName = UnitName("pet")
        state.petLevel = UnitLevel("pet")
    end
    local diet = petInfo.GetPetFoodTypes()
    state.diet = type(diet) == "table" and diet or {}
    state.happiness, state.damagePercentage, state.loyaltyRate = petInfo.GetPetHappiness()
    if itemID then
        state.canEat = petInfo.CanPetEatItem(itemID)
        local link = itemLink or itemID
        state.itemLevel = select(4, C_Item.GetItemInfo(link))
        if petEats then
            state.remembered = petEats[itemID]
        end
    end

    -- What the rule made of the bags: every kind the pet eats, the kept ones marked.
    local petFood = GetCarried().petFood
    state.judged = petFood ~= nil
    if petFood then
        state.pieces = PET_FOOD_PIECES
        state.kept = itemID ~= nil and petFood.kept[itemID] == true
        state.carried = {}
        for _, candidate in ipairs(petFood.candidates) do
            state.carried[#state.carried + 1] = string.format("%s%s x%d (item %d, level %d)",
                petFood.kept[candidate.itemID] and "kept: " or "", tostring(C_Item.GetItemNameByID(candidate.itemID)),
                candidate.count, candidate.itemID, candidate.level)
        end
    end
    return state
end

-- Buying or looting a better stack changes the verdict for the stacks already in the bags, and
-- only the slot that changed is redrawn. Refresh everything when the carried set changes. The
-- kinds kept for the pet are part of that set: they change with the counts, and with the pet
-- (another one, or the first one seen this session).
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterUnitEvent("UNIT_PET", "player")
eventFrame:SetScript("OnEvent", function()
    -- The ingredient rule reads the kinds kept for the pet as well (IsKeptForPet).
    local iconConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon
    if not (iconConfig and (iconConfig.ShowOutdatedFood or iconConfig.ShowOutgrownIngredients or
            iconConfig.ShowIngredientsForOtherToons)) then
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
            CaerdonWardrobe:RefreshItems("food carried")
        end
    else
        carried = current
    end
end)
