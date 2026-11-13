-- Auction value for items the addon would otherwise call "sellable".
--
-- Answers one question: is listing this on the auction house worth more than vendoring it?
-- Prices come from Auctionator (optional, detected at runtime). Nothing here knows how often an
-- item actually sells: Auctionator records listings (lowest price and quantity seen per day),
-- never sales. The verdict therefore leans on three things instead:
--
--   1. A cautious price: the lower of the last seen price and the median of the recent daily
--      lows, so one silly listing on a thin market does not decide it.
--   2. The deposit counted more than once (DEPOSIT_RISK_MULTIPLIER), which is the same as
--      assuming most listings of this kind need more than one attempt.
--   3. A required profit that scales with the vendor value and the toon's level.
--
--   profit   = quantity * (price * (1 - AH cut) - vendor price) - deposit * risk multiplier
--   required = clamp(vendor value * margin, floor, MAX_REQUIRED_PROFIT)
--   auction when profit >= required
--
-- Two rule sets (RULES): single items such as gear are slow, one-off sales, so the deposit
-- counts twice and the profit has to match the vendor value. Stackable goods are fungible and
-- trade at a well-defined price, so the deposit counts once, a quarter of the vendor value is
-- margin enough, and the whole quantity owned is judged as one trip.
--
-- CaerdonItemMixin:GetAuctionValueInfo() is the entry point for callers; the Debug Frame export
-- prints every number behind a verdict ("[Auction Value]").

local ADDON_NAME, NS = ...

CaerdonAuctionValue = {}

local CALLER_ID = "CaerdonWardrobe"

-- The auction house keeps this share of a successful sale.
local AH_CUT = 0.05
-- A price older than this many days is ignored.
local MAX_PRICE_AGE_DAYS = 7
-- Daily lows from this many days back feed the median, once at least MIN_HISTORY_DAYS exist.
local HISTORY_WINDOW_DAYS = 14
local MIN_HISTORY_DAYS = 3

-- Deposit model until the auction house has shown a real one (see RecordDepositSample):
-- the larger of a flat minimum and a share of the vendor price.
local DEFAULT_MIN_DEPOSIT = 100 -- 1s
local DEFAULT_DEPOSIT_RATE = 0.15
-- depositRisk: a deposit is only lost when the listing expires; counting it twice assumes
--   roughly one listing in three sells.
-- margin: share of the vendor value the profit has to reach (before the floor and the cap).
local RULES = {
    single = { name = "single item", depositRisk = 2, margin = 1 },
    stack = { name = "stackable", depositRisk = 1, margin = 0.25 }
}

-- "Worth the trip" floor in copper for the automatic setting: FLOOR_PER_LEVEL a level.
local FLOOR_PER_LEVEL = 25
local MIN_FLOOR = 100
-- Past this profit the "at least double the vendor value" rule stops growing.
local MAX_REQUIRED_PROFIT = 10000 -- 1g

-- Scans report prices in bursts; one refresh covers them.
local REFRESH_DELAY = 1

local providerState = {
    registered = false,
    error = nil,
    lastUpdate = nil,
    updateCount = 0
}

-- Stackable items judged this session, by item ID (see OnBagsChanged).
local trackedStacks = {}

local function GetAuctionatorAPI()
    local auctionator = _G.Auctionator
    local api = auctionator and auctionator.API and auctionator.API.v1
    if api and api.GetAuctionPriceByItemLink then
        return api
    end
    return nil
end

function CaerdonAuctionValue:IsAvailable()
    return GetAuctionatorAPI() ~= nil
end

local function GetSavedData()
    if type(CaerdonAuctionData) ~= "table" then
        CaerdonAuctionData = {}
    end
    return CaerdonAuctionData
end

-- Estimated deposit for one listing of an item with this vendor price.
-- Returns the deposit and "measured" / "default" for where the model came from.
function CaerdonAuctionValue:EstimateDeposit(vendorPrice)
    local data = GetSavedData()
    local rate = data.depositRate or DEFAULT_DEPOSIT_RATE
    local minDeposit = data.minDeposit or DEFAULT_MIN_DEPOSIT
    local deposit = math.max(minDeposit, math.floor(rate * (vendorPrice or 0) + 0.5))
    return deposit, (data.depositRate and "measured" or "default")
end

-- Called with the item placed in the auction house sell slot: the one moment the client will
-- tell us a real deposit. Keeps the deposit-to-vendor-price ratio and the smallest deposit seen.
function CaerdonAuctionValue:RecordDepositSample(itemLocation)
    if not (C_AuctionHouse and C_AuctionHouse.CalculateItemDeposit) then
        return
    end
    if not itemLocation or not C_Item.DoesItemExist(itemLocation) then
        return
    end

    local itemLink = C_Item.GetItemLink(itemLocation)
    local vendorPrice = itemLink and select(11, C_Item.GetItemInfo(itemLink))
    if type(vendorPrice) ~= "number" then
        return
    end

    -- Duration 2 is the middle option (8h on WoW Forever, 24h on retail).
    local ok, deposit = pcall(C_AuctionHouse.CalculateItemDeposit, itemLocation, 2, 1)
    if not ok or type(deposit) ~= "number" or deposit <= 0 then
        return
    end

    local data = GetSavedData()
    data.minDeposit = math.min(data.minDeposit or DEFAULT_MIN_DEPOSIT, deposit)

    -- A deposit sitting on the minimum says nothing about the rate.
    if vendorPrice > 0 and (deposit > data.minDeposit or deposit < DEFAULT_MIN_DEPOSIT) then
        local rate = deposit / vendorPrice
        if rate >= 0.01 and rate <= 5 then
            local changed = data.depositRate == nil or math.abs(data.depositRate - rate) > 0.005
            data.depositRate = rate
            if changed and CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
                CaerdonWardrobe:RefreshItems()
            end
        end
    end

    data.lastSample = {
        itemID = C_Item.GetItemID(itemLocation),
        vendorPrice = vendorPrice,
        deposit = deposit,
        time = time()
    }
end

-- The floor in copper and whether it came from the level ("auto") or the setting ("fixed").
function CaerdonAuctionValue:GetProfitFloor()
    local setting = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon and
        CaerdonWardrobeConfig.Icon.AuctionMinProfit
    local fixed = tonumber(setting)
    if fixed then
        return fixed, "fixed"
    end
    local level = UnitLevel("player") or 1
    return math.max(MIN_FLOOR, level * FLOOR_PER_LEVEL), "auto"
end

local function Median(values)
    table.sort(values)
    local count = #values
    if count == 0 then
        return nil
    end
    if count % 2 == 1 then
        return values[(count + 1) / 2]
    end
    return math.floor((values[count / 2] + values[count / 2 + 1]) / 2)
end

-- Daily listing history. Not part of Auctionator's public API, so every step is checked and
-- pcall'd; when it is missing the verdict simply runs on the last seen price.
local function GetHistory(itemLink)
    local auctionator = _G.Auctionator
    local database = auctionator and auctionator.Database
    local utilities = auctionator and auctionator.Utilities
    if not (database and database.GetPriceHistory and utilities and utilities.DBKeyFromLink) then
        return nil
    end

    -- The callback runs immediately when the item is cached, which it is by the time an item
    -- has a status.
    local dbKeys
    pcall(utilities.DBKeyFromLink, itemLink, function(keys)
        dbKeys = keys
    end)
    if type(dbKeys) ~= "table" then
        return nil
    end

    for _, dbKey in ipairs(dbKeys) do
        local ok, history = pcall(database.GetPriceHistory, database, dbKey)
        if ok and type(history) == "table" and #history > 0 then
            return history, dbKey
        end
    end
    return nil
end

local function SummarizeHistory(history)
    local newestDay
    for _, entry in ipairs(history) do
        local day = tonumber(entry.rawDay)
        if day and (not newestDay or day > newestDay) then
            newestDay = day
        end
    end
    if not newestDay then
        return nil
    end

    local lows = {}
    local maxAvailable
    for _, entry in ipairs(history) do
        local day = tonumber(entry.rawDay)
        if day and day > newestDay - HISTORY_WINDOW_DAYS and type(entry.minSeen) == "number" then
            lows[#lows + 1] = entry.minSeen
            if type(entry.available) == "number" and (not maxAvailable or entry.available > maxAvailable) then
                maxAvailable = entry.available
            end
        end
    end

    return {
        daysSeen = #lows,
        medianLow = #lows >= MIN_HISTORY_DAYS and Median(lows) or nil,
        maxAvailable = maxAvailable
    }
end

local function HasRandomSuffix(itemLink)
    local suffix = itemLink:match("item:%-?%d*:%-?%d*:%-?%d*:%-?%d*:%-?%d*:%-?%d*:(%-?%d+)")
    suffix = tonumber(suffix)
    return suffix ~= nil and suffix ~= 0
end

-- Everything behind the verdict for one item. Always returns a table; `shouldAuction` is the
-- verdict and `reason` says why in words (used by the Debug Frame export).
--   vendorPrice: copper a vendor pays (nil / 0 when it cannot be vendored)
--   blockedReason: set by the caller when the item cannot be listed at all (soulbound, ...)
--   options.stackable: judge by the stackable rules
--   options.quantity: how many the toon owns (stackable items; defaults to 1)
--   options.itemID: lets a later change in the owned quantity refresh the icons
function CaerdonAuctionValue:GetItemAuctionInfo(itemLink, vendorPrice, blockedReason, options)
    vendorPrice = vendorPrice or 0
    local rule = options and options.stackable and RULES.stack or RULES.single
    local quantity = math.max(1, options and options.quantity or 1)
    local vendorValue = vendorPrice * quantity

    local info = {
        shouldAuction = false,
        vendorPrice = vendorPrice,
        quantity = quantity,
        vendorValue = vendorValue,
        rule = rule.name,
        margin = rule.margin,
        cut = AH_CUT,
        depositRiskMultiplier = rule.depositRisk,
        maxPriceAgeDays = MAX_PRICE_AGE_DAYS
    }

    info.floor, info.floorSource = self:GetProfitFloor()
    info.deposit, info.depositSource = self:EstimateDeposit(vendorValue)
    info.required = math.min(math.max(math.floor(vendorValue * rule.margin), info.floor),
        math.max(MAX_REQUIRED_PROFIT, info.floor))

    if blockedReason then
        info.reason = blockedReason
        return info
    end

    local api = GetAuctionatorAPI()
    if not api then
        info.reason = "no price source (Auctionator not loaded)"
        return info
    end
    info.source = "Auctionator"

    local ok, lastPrice = pcall(api.GetAuctionPriceByItemLink, CALLER_ID, itemLink)
    if not ok then
        info.reason = "price lookup failed: " .. tostring(lastPrice)
        return info
    end
    if type(lastPrice) ~= "number" or lastPrice <= 0 then
        info.reason = "never seen on the auction house"
        return info
    end
    info.lastPrice = lastPrice

    if api.GetAuctionAgeByItemLink then
        local ageOk, age = pcall(api.GetAuctionAgeByItemLink, CALLER_ID, itemLink)
        if ageOk and type(age) == "number" then
            info.ageDays = age
        end
    end

    local history, dbKey = GetHistory(itemLink)
    if history then
        info.dbKey = dbKey
        local summary = SummarizeHistory(history)
        if summary then
            info.daysSeen = summary.daysSeen
            info.medianLow = summary.medianLow
            info.maxAvailable = summary.maxAvailable
        end
    end
    info.randomSuffix = HasRandomSuffix(itemLink)

    if not info.ageDays then
        info.reason = "price has no recent scan behind it"
        return info
    end
    if info.ageDays > MAX_PRICE_AGE_DAYS then
        info.reason = string.format("price is %d days old (limit %d)", info.ageDays, MAX_PRICE_AGE_DAYS)
        return info
    end

    info.price = info.medianLow and math.min(lastPrice, info.medianLow) or lastPrice
    info.net = math.floor(info.price * (1 - AH_CUT))
    info.profit = quantity * (info.net - vendorPrice) - info.deposit * rule.depositRisk

    if info.profit >= info.required then
        info.shouldAuction = true
        info.reason = "profit meets the requirement"
    else
        info.reason = "profit below the requirement"
    end

    if options and options.stackable and options.itemID and not options.untracked then
        trackedStacks[options.itemID] = {
            itemLink = itemLink,
            vendorPrice = vendorPrice,
            quantity = quantity,
            shouldAuction = info.shouldAuction
        }
    end
    return info
end

-- How many of an item the toon owns, bank included: what one trip to the auction house lists.
function CaerdonAuctionValue:GetOwnedQuantity(itemID)
    local getItemCount = C_Item and C_Item.GetItemCount or GetItemCount
    local count = getItemCount and itemID and getItemCount(itemID, true)
    if type(count) ~= "number" or count < 1 then
        return 1
    end
    return count
end

-- A stack's verdict depends on how many are owned. Looting one more only redraws the slot it
-- landed in, so when the new total flips a verdict every icon is refreshed.
local function OnBagsChanged()
    if not next(trackedStacks) then
        return
    end
    for itemID, tracked in pairs(trackedStacks) do
        local quantity = CaerdonAuctionValue:GetOwnedQuantity(itemID)
        if quantity ~= tracked.quantity then
            local info = CaerdonAuctionValue:GetItemAuctionInfo(tracked.itemLink, tracked.vendorPrice, nil,
                { stackable = true, quantity = quantity, untracked = true })
            if info.shouldAuction ~= tracked.shouldAuction then
                wipe(trackedStacks)
                if CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
                    CaerdonWardrobe:RefreshItems()
                end
                return
            end
            tracked.quantity = quantity
        end
    end
end

function CaerdonAuctionValue:GetDebugState()
    local data = GetSavedData()
    return {
        available = self:IsAvailable(),
        registered = providerState.registered,
        error = providerState.error,
        lastUpdate = providerState.lastUpdate,
        updateCount = providerState.updateCount,
        depositRate = data.depositRate,
        minDeposit = data.minDeposit,
        lastSample = data.lastSample,
        defaultDepositRate = DEFAULT_DEPOSIT_RATE,
        defaultMinDeposit = DEFAULT_MIN_DEPOSIT
    }
end

-- New prices change verdicts, so a finished scan refreshes the icons.
local refreshTimer
local function OnPricesUpdated()
    providerState.lastUpdate = GetTime()
    providerState.updateCount = providerState.updateCount + 1

    if not (CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon and CaerdonWardrobeConfig.Icon.ShowAuctionValue) then
        return
    end
    if refreshTimer then
        refreshTimer:Cancel()
    end
    refreshTimer = C_Timer.NewTimer(REFRESH_DELAY, function()
        refreshTimer = nil
        if CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
            CaerdonWardrobe:RefreshItems()
        end
    end)
end

local function RegisterForUpdates()
    if providerState.registered then
        return
    end
    local api = GetAuctionatorAPI()
    if not (api and api.RegisterForDBUpdate) then
        return
    end
    local ok, err = pcall(api.RegisterForDBUpdate, CALLER_ID, OnPricesUpdated)
    if ok then
        providerState.registered = true
        providerState.error = nil
    else
        providerState.error = tostring(err)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "BAG_UPDATE_DELAYED" then
        OnBagsChanged()
    elseif event == "PLAYER_LOGIN" or addonName == "Auctionator" then
        RegisterForUpdates()
        if providerState.registered then
            self:UnregisterEvent("ADDON_LOADED")
        end
    end
end)
