-- Vendor goods.
--
-- Whether vendors sell an item, and how many of them do. The ingredient rule asks: thread,
-- spices or a vial are what any toon buys where it stands, so one another toon's recipes take
-- is not worth the mail (CaerdonItemMixin:GetIngredientStatus, in CaerdonItem.lua).
--
-- The client has no answer to "does a vendor sell this" away from the vendor's own window. So
-- the answer is QuestieDB's, where that is loaded: its item data names the NPCs that sell an
-- item (LibQuestieDB.Item, field "vendors"). Without it nothing is known and nothing is said.
--
-- "Common" is by the number of vendors. The data does not say whether a vendor's stock is
-- limited, and the materials a few vendors sell a handful of (leather, herbs, enchanting dust)
-- are worth sending. In QuestieDB's WoW Forever data those have 1 to 12 vendors and the
-- supplies every trade vendor sells have 21 and more (docs/dev-notes.md, Ingredients).
--
-- CaerdonItemMixin:GetVendorInfo() is the entry point for callers; the Debug Frame export
-- prints it in "[Ingredients]".

CaerdonVendorGoods = {}

-- The version of QuestieDB's contract this was written for: the quest module's, so the two ask
-- the library the same question (CaerdonQuestItems.lua).
local QUESTIEDB_CONTRACT = 2
-- From this many vendors on, an item is one any toon buys for itself.
local COMMON_VENDOR_COUNT = 20

-- Kept once it is found. Not finding it is not kept: QuestieDB loads after this addon.
local library

-- QuestieDB's item data, or nil and why not.
local function ResolveItems()
    if library then
        return library.Item
    end
    local lib = _G.LibQuestieDB
    if type(lib) ~= "table" then
        return nil, "QuestieDB is not loaded"
    end
    if type(lib.RequireContract) ~= "function" then
        return nil, "this QuestieDB is not one the addon can read"
    end
    local ok, compatible = pcall(lib.RequireContract, QUESTIEDB_CONTRACT)
    local items = lib.Item
    if not (ok and compatible) or type(items) ~= "table" or type(items.Get) ~= "function" then
        return nil, "this QuestieDB is not one the addon can read"
    end
    library = lib
    return items
end

-- How many vendors sell the item (0 for none), or nil and why it is not known.
--
-- Not kept here: the status made from it is cached with the item, and the test addon's
-- recorder needs every run to ask the library again.
function CaerdonVendorGoods:GetVendorCount(itemID)
    local items, reason = ResolveItems()
    if not items then
        return nil, reason
    end
    local ok, vendors = pcall(items.Get, itemID, "vendors")
    if not ok then
        return nil, "QuestieDB gave an error: " .. tostring(vendors)
    end
    return type(vendors) == "table" and #vendors or 0
end

-- nil when nothing says who sells the item (no QuestieDB), otherwise
--   { vendorCount = how many vendors sell it,
--     isCommon = so many that any toon buys it for itself,
--     commonFrom = the number that takes,
--     source = where the answer is from }
function CaerdonVendorGoods:GetItemInfo(itemID)
    if not itemID then
        return nil
    end
    local count = self:GetVendorCount(itemID)
    if not count then
        return nil
    end
    return {
        vendorCount = count,
        isCommon = count >= COMMON_VENDOR_COUNT,
        commonFrom = COMMON_VENDOR_COUNT,
        source = "QuestieDB",
    }
end

-- For the Debug Frame export: why nothing is known about the item, when nothing is.
function CaerdonVendorGoods:GetDebugState(itemID)
    local _, reason = self:GetVendorCount(itemID)
    return { unknownReason = reason, commonFrom = COMMON_VENDOR_COUNT }
end
