-- A window that is shown but not on screen gets no draws: the Bank and Merchant features and
-- the BetterBags vendor integration against stubs of their windows. A bag addon with a bank
-- or a vendor of its own keeps Blizzard's window shown under a hidden parent, and a closed
-- BetterBags vendor keeps its cards shown inside a hidden panel.
--   luajit tools/harness/standalone/hidden-windows.lua [repo dir]
-- tools/harness/run.lua runs it with the scenarios. The stubs are written from reading
-- Blizzard's and BetterBags' code, so this checks the features' logic and not those windows.
local ROOT = arg[1] or "."
local checks, failures = 0, 0
local function Check(condition, label)
    checks = checks + 1
    if not condition then failures = failures + 1 print("FAIL: " .. label) end
end

local requests, cleared, cancelled, registered
local function Reset() requests, cleared, cancelled = {}, 0, 0 end
-- The stub core's side of a draw owed to a button that is not on screen.
local hasOverlay, owed = {}, {}
local function OwedCount()
    local count = 0
    for _ in pairs(owed) do count = count + 1 end
    return count
end
-- What the client does when buttons come on screen: each overlay's OnShow, once.
local function PayOwed()
    local due = {}
    for button, debt in pairs(owed) do
        if button:IsVisible() then
            due[#due + 1] = debt
            owed[button] = nil
        end
    end
    for _, debt in ipairs(due) do
        debt.feature:OnButtonOnScreen(debt.context)
    end
end

format = string.format
wipe = function(t) for key in pairs(t) do t[key] = nil end return t end
-- Both forms: a method of a table, and a global function by its name.
hooksecurefunc = function(owner, key, hook)
    if type(owner) == "string" then
        owner, key, hook = _G, owner, key
    end
    local original = owner[key]
    owner[key] = function(...) original(...) hook(...) end
end
C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end }
C_AddOns = {
    GetAddOnInfo = function(name) return name, name, "", true end,
    -- Not the addon the Merchant feature steps aside for (Legion Remix Helper).
    IsAddOnLoaded = function(name) return name == "BetterBags" end,
    GetAddOnMetadata = function() return "1" end,
}
CaerdonItem = {
    CreateFromBagAndSlot = function(_, bag, slot)
        return { bag = bag, slot = slot, IsItemDataCached = function() return true end }
    end,
    CreateFromItemLink = function(_, link)
        return { link = link, IsItemDataCached = function() return true end, GetItemID = function() return tonumber(link) end }
    end,
}
CaerdonWardrobeFeatureMixin = {
    Refresh = function() cancelled = cancelled + 1 end,
    NoteHookPoint = function() return true end,
    -- As the core's (scenarios/decorate.lua has the real one), for an item whose data is here:
    -- the item is made and its button asked for.
    Decorate = function(self, button, source, locationInfo, options)
        local item = type(source) == "string" and CaerdonItem:CreateFromItemLink(source) or source
        CaerdonWardrobe:UpdateButton(button, item, self, locationInfo, options)
        return item
    end,
}
CaerdonWardrobeConfig = {
    Binding = { ShowStatus = { Merchant = true } },
    Icon = { ShowLearnable = { Merchant = true }, ShowLearnableByOther = { Merchant = true } },
}
CaerdonWardrobe = {
    RegisterFeature = function(_, mixin)
        local feature = setmetatable({}, { __index = function(_, key) return mixin[key] or CaerdonWardrobeFeatureMixin[key] end })
        registered[feature:GetName()] = feature
    end,
    GetFeature = function(_, name) return registered[name] end,
    GetSlotStatusSize = function() return 16 end,
    UpdateButton = function(_, button, item, feature, locationInfo)
        requests[#requests + 1] = { button = button, item = item, feature = feature, locationInfo = locationInfo }
        hasOverlay[button], owed[button] = true, nil
    end,
    ClearButton = function() cleared = cleared + 1 end,
    -- As the core's, for an item whose data is here: answered from inside the call.
    WhenItemLoaded = function(_, button, item, callback) callback() end,
    -- As the core's (scenarios/draw-path.lua has the real one): nothing is noted for a button
    -- on screen or one never asked for, and a request settles what was owed.
    AskWhenOnScreen = function(_, button, feature, context)
        if not hasOverlay[button] or button:IsVisible() then
            return false
        end
        owed[button] = { feature = feature, context = context }
        return true
    end,
    SetItemButtonMogStatusFilter = function() end,
}
local namespace = { L = setmetatable({}, { __index = function(_, key) return key end }) }

local function Load(path)
    registered = {}
    assert(loadfile(ROOT .. "/" .. path))("CaerdonWardrobe", namespace)
    assert(next(registered), "the file registered no feature")
    return registered
end

-- A frame as far as these files ask it: shown is its own state, on screen needs every parent
-- shown too.
local function Frame(parent)
    local frame = { shown = true, parent = parent }
    function frame:IsShown() return self.shown end
    function frame:IsVisible() return self.shown and (self.parent == nil or self.parent:IsVisible()) end
    function frame:GetSize() return 37, 37 end
    function frame:GetID() return self.id end
    return frame
end

print("Bank")
do
    -- What a bag addon with a bank of its own does: the bank frame under a hidden parent, the
    -- panel shown inside it.
    local parking = Frame()
    BankPanel = Frame(parking)
    BankPanel.selectedTabID = 6
    BankPanel.UpdateSearchResults = function() end
    BankPanel.RefreshBankPanel = function() end
    BankPanelItemButtonMixin = { Refresh = function() end }
    local buttons = {}
    for slot = 1, 5 do
        local button = Frame(BankPanel)
        -- The last slot is free.
        button.itemInfo = slot < 5 and { itemID = 100 + slot } or nil
        button.GetBankTabID = function() return 6 end
        button.GetContainerSlotID = function() return slot end
        buttons[slot] = button
    end
    function BankPanel:EnumerateValidItems()
        local index = 0
        return function()
            index = index + 1
            return buttons[index]
        end
    end

    local feature = Load("features/Bank.lua").Bank
    feature:Init()

    Reset()
    feature:Refresh()
    Check(cancelled == 1, "on screen: the pending requests are cancelled first")
    Check(#requests == 4 and cleared == 1, "on screen: Refresh asks for the four filled slots and clears the free one: "
        .. #requests .. ", " .. cleared)
    Reset()
    BankPanelItemButtonMixin.Refresh(buttons[2])
    BankPanelItemButtonMixin.Refresh(buttons[5])
    Check(#requests == 1 and requests[1].button == buttons[2] and cleared == 1,
        "on screen: a button the panel refreshes is asked for, a free one cleared")
    Reset()
    BankPanel:RefreshBankPanel()
    Check(#requests == 4, "on screen: the panel's own refresh asks for its buttons: " .. #requests)

    -- Shown, and not on screen.
    parking.shown = false
    Check(BankPanel:IsShown() and not BankPanel:IsVisible(), "parked: the panel is shown and not on screen")
    Reset()
    feature:Refresh()
    Check(cancelled == 1, "parked: Refresh still cancels what was pending")
    Check(#requests == 0 and cleared == 0, "parked: Refresh asks for nothing and clears nothing: " .. #requests .. ", " .. cleared)
    BankPanelItemButtonMixin.Refresh(buttons[2])
    BankPanelItemButtonMixin.Refresh(buttons[5])
    BankPanel:RefreshBankPanel()
    Check(#requests == 0 and cleared == 0, "parked: neither do the panel's refreshes: " .. #requests .. ", " .. cleared)

    -- A button is refreshed before it is shown: the panel is what counts.
    parking.shown = true
    buttons[3].shown = false
    Reset()
    BankPanelItemButtonMixin.Refresh(buttons[3])
    Check(#requests == 1, "on screen again: a button not yet shown is asked for when its panel is on screen")
    buttons[3].shown = true

    -- A panel that was closed the usual way has no tab.
    BankPanel.selectedTabID = nil
    Reset()
    feature:Refresh()
    Check(#requests == 0, "no tab selected: nothing is asked for")
end

print("Merchant")
do
    local parking = Frame()
    MerchantFrame = Frame(parking)
    MerchantFrame.page, MerchantFrame.selectedTab = 1, 1
    MERCHANT_ITEMS_PER_PAGE, BUYBACK_ITEMS_PER_PAGE = 10, 12
    BACKPACK_CONTAINER, NUM_BAG_SLOTS = 0, 4
    Enum = { BagIndex = { ReagentBag = 5 } }
    for index = 1, 12 do
        local button = Frame(MerchantFrame)
        button.id = index
        _G["MerchantItem" .. index .. "ItemButton"] = button
    end
    MerchantBuyBackItemItemButton = Frame(MerchantFrame)
    -- A vendor with seven items, two things sold back to it, and one item in the bags.
    GetMerchantItemLink = function(index) return index <= 7 and tostring(1000 + index) or nil end
    GetNumBuybackItems = function() return 2 end
    GetBuybackItemInfo = function(index) return index >= 1 and index <= 2 and "sold" or nil end
    GetBuybackItemLink = function(index) return index >= 1 and index <= 2 and tostring(2000 + index) or nil end
    local carried = 1003
    C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
        GetContainerItemInfo = function(_, slot) return slot == 1 and { itemID = carried } or nil end,
    }
    MerchantFrame_UpdateMerchantInfo = function() end
    MerchantFrame_UpdateBuybackInfo = function() end

    local feature = Load("features/Merchant.lua").Merchant
    feature:Init()

    Reset()
    MerchantFrame_UpdateMerchantInfo()
    -- Seven items and the one buyback button under them; three item buttons with nothing.
    Check(#requests == 8 and cleared == 3, "on screen: the vendor's update asks for its items: " .. #requests .. ", " .. cleared)
    Reset()
    feature:Refresh()
    Check(#requests == 8, "on screen: Refresh asks for them again: " .. #requests)
    Reset()
    feature:BAG_UPDATE_DELAYED()
    Check(#requests == 8, "on screen: so does a change in the bags: " .. #requests)
    MerchantFrame.selectedTab = 2
    Reset()
    MerchantFrame_UpdateBuybackInfo()
    Check(#requests == 2, "on screen: the buyback tab asks for what was sold: " .. #requests)
    Reset()
    feature:Refresh()
    Check(#requests == 2, "on screen: Refresh on the buyback tab too: " .. #requests)
    MerchantFrame.selectedTab = 1

    parking.shown = false
    Check(MerchantFrame:IsShown() and not MerchantFrame:IsVisible(), "parked: the window is shown and not on screen")
    Reset()
    MerchantFrame_UpdateMerchantInfo()
    MerchantFrame_UpdateBuybackInfo()
    feature:Refresh()
    feature:MERCHANT_UPDATE()
    feature:BAG_UPDATE_DELAYED()
    feature:TOOLTIP_DATA_UPDATE()
    Check(#requests == 0 and cleared == 0, "parked: nothing is asked for and nothing cleared: " .. #requests .. ", " .. cleared)
    -- The vendor window that stands in for it reads this feature's rules, which need the
    -- bags as they are now: the item carried is swapped for another while it is parked.
    local rules = feature:GetDisplayInfo({}, CaerdonItem:CreateFromItemLink("1003"))
    Check(rules.ownIcon.shouldShow == false, "parked: the rules know what is in the bags")
    carried = 1004
    feature:BAG_UPDATE_DELAYED()
    rules = feature:GetDisplayInfo({}, CaerdonItem:CreateFromItemLink("1004"))
    Check(rules.ownIcon.shouldShow == false, "parked: and follow a change in them")
    rules = feature:GetDisplayInfo({}, CaerdonItem:CreateFromItemLink("1003"))
    Check(rules.ownIcon.shouldShow == true, "parked: an item no longer carried gets its icon back")
    Check(#requests == 0, "parked: still nothing asked for")

    parking.shown = true
    Reset()
    MerchantFrame_UpdateMerchantInfo()
    Check(#requests == 8, "on screen again: its update asks as before: " .. #requests)
end

print("BetterBags vendor")
do
    local messages = {}
    local events = { RegisterMessage = function(_, name, handler) messages[name] = handler end }
    local addon = {
        GetModule = function(_, name)
            if name == "Events" then return events end
            return nil
        end,
    }
    LibStub = function() return { GetAddon = function() return addon end } end
    C_Container.GetContainerItemID = function() return 1 end

    local feature = Load("external/BetterBags/Core.BetterBags.lua").BetterBagsVendor
    feature:Init()

    -- BetterBags' vendor panel with three cards, as its buttons are built: a frame, the item
    -- button inside it, and draw methods of the button's own.
    local panel = Frame()
    local cards = {}
    for index = 1, 3 do
        local card = { frame = Frame(panel), button = Frame() }
        function card:SetBuy(item) self.mode, self.item = "buy", item end
        function card:SetBuyback(item) self.mode, self.buyback = "buyback", item end
        function card:SetRepair() self.mode = "repair" end
        function card:Release() self.mode, self.item, self.buyback = nil, nil, nil end
        messages["vendor/NewButton"](nil, card)
        cards[index] = card
    end
    Reset()
    for index, card in ipairs(cards) do
        card:SetBuy({ link = tostring(3000 + index), index = index })
    end
    Check(#requests == 3, "open: every card BetterBags draws is asked for: " .. #requests)
    Reset()
    feature:Refresh()
    Check(#requests == 3, "open: Refresh asks for the cards again: " .. #requests)

    -- The vendor closes: the panel hides, the cards stay as they were.
    panel.shown = false
    Check(cards[1].frame:IsShown() and not cards[1].frame:IsVisible(), "closed: a card is shown and not on screen")
    Reset()
    feature:Refresh()
    Check(cancelled == 1 and #requests == 0, "closed: Refresh asks for none of them: " .. #requests)

    -- The next vendor draws all of its cards, before the panel is on screen or after.
    Reset()
    for index, card in ipairs(cards) do
        card:SetBuy({ link = tostring(4000 + index), index = index })
    end
    Check(#requests == 3, "opening: the cards BetterBags draws are asked for whatever is on screen: " .. #requests)
    panel.shown = true
    Reset()
    feature:Refresh()
    Check(#requests == 3 and requests[1].item.link:find("^400"), "open again: Refresh asks for the new cards")
    Reset()
    cards[2]:Release()
    Check(cleared == 1, "a card given back is cleared")
    feature:Refresh()
    Check(#requests == 2, "and no longer asked for: " .. #requests)
end

print("BetterBags bags")
do
    -- BetterBags does not draw an unchanged button again when its bag opens, so this window
    -- cannot be skipped like the three above: a button that is not on screen is owed a draw.
    local messages = {}
    local events = { RegisterMessage = function(_, name, handler) messages[name] = handler end }
    local addon = { GetModule = function(_, name) return name == "Events" and events or nil end }
    LibStub = function() return { GetAddon = function() return addon end } end
    -- Bag 0: slots 1 to 3 hold something, slot 4 is free.
    local filled = { true, true, true, false }
    C_Container.GetContainerItemID = function(bag, slot) return bag == 0 and filled[slot] and 100 + slot or nil end

    local feature = Load("external/BetterBags/Core.BetterBags.lua").BetterBags
    feature:Init()

    local bagFrame = Frame()
    local bagItems = {}
    for slot = 1, 4 do
        bagItems[slot] = { button = Frame(bagFrame), slotkey = "0_" .. slot }
    end
    local function Asked(...)
        local wanted = {}
        for _, slot in ipairs({ ... }) do wanted[bagItems[slot].button] = true end
        local count = 0
        for _, request in ipairs(requests) do
            if not wanted[request.button] then return false end
            count = count + 1
        end
        return count == select("#", ...)
    end

    Reset()
    for slot = 1, 4 do
        messages["item/Updated"](nil, bagItems[slot])
    end
    Check(#requests == 4, "open: every button BetterBags draws is asked for: " .. #requests)
    Reset()
    feature:Refresh()
    Check(cancelled == 1 and Asked(1, 2, 3), "open: Refresh asks for the filled slots again: " .. #requests)
    Check(OwedCount() == 0, "open: and nothing is owed")

    -- The bag closes. A refresh leaves its buttons alone and owes each a draw, once.
    bagFrame.shown = false
    Reset()
    feature:Refresh()
    Check(cancelled == 1 and #requests == 0, "closed: Refresh asks for none of them: " .. #requests)
    Check(OwedCount() == 3, "closed: the three filled slots are owed a draw: " .. OwedCount())
    feature:Refresh()
    Check(#requests == 0 and OwedCount() == 3, "closed: a second refresh owes them no more: " .. OwedCount())

    -- An item that arrives while the bag is closed is drawn at once, as before.
    filled[4] = true
    Reset()
    messages["item/Updated"](nil, bagItems[4])
    Check(Asked(4), "closed: a button BetterBags draws is asked for whatever is on screen: " .. #requests)
    feature:Refresh()
    Check(OwedCount() == 4, "closed: after the next refresh it is owed one like the others: " .. OwedCount())

    -- Before the bag opens again one button goes back to BetterBags' pool and one slot is
    -- emptied. The bag opens: the rest are asked for.
    messages["item/Clearing"](nil, bagItems[2])
    filled[3] = false
    Reset()
    bagFrame.shown = true
    PayOwed()
    Check(Asked(1, 4), "opening: the buttons owed a draw are asked for, a pooled one and an emptied slot are not: " .. #requests)
    Check(OwedCount() == 0, "opening: nothing is owed afterwards")
    Reset()
    PayOwed()
    Check(#requests == 0, "opening: and nothing is asked for twice")
    Reset()
    feature:Refresh()
    Check(Asked(1, 4), "open again: Refresh asks for what is on screen: " .. #requests)

    -- A button hidden by itself in an open bag (a collapsed section) is owed one too.
    bagItems[1].button.shown = false
    Reset()
    feature:Refresh()
    Check(Asked(4) and OwedCount() == 1, "section: a hidden button of an open bag is left alone and owed: " .. #requests)
    Reset()
    bagItems[1].button.shown = true
    PayOwed()
    Check(Asked(1), "section: and asked for when it is shown: " .. #requests)
end

print(("%d checks, %d failed"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
