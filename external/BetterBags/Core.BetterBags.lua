local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "BetterBags"
local BetterBagsMixin = {}

function BetterBagsMixin:GetName()
    return addonName
end

-- BetterBags v0.5.6 renamed bagItem.data to currentData and leaves it nil for
-- free slots. slotkey ("bagID_slotID") is set for every physical slot, so use
-- it first and fall back to the data table for older versions.
local function GetBagAndSlot(bagItem)
    if type(bagItem.slotkey) == "string" then
        local bag, slot = bagItem.slotkey:match("^(%-?%d+)_(%d+)$")
        if bag then
            return tonumber(bag), tonumber(slot)
        end
    end

    local data = bagItem.currentData or bagItem.data
    if data and data.bagid and data.slotid then
        return data.bagid, data.slotid
    end
end

-- BetterBags item buttons currently drawn, so Refresh() can revisit them. BetterBags only
-- sends item/Updated when a button's draw inputs change (item, count, quality, ...), which
-- a newly learned appearance or a gear swap does not touch - and reopening the bag does
-- not redraw unchanged buttons either. Weak keys: BetterBags owns the button objects.
local trackedBagItems = setmetatable({}, { __mode = "k" })

function BetterBagsMixin:UpdateBagItem(bagItem)
    local button = bagItem.button
    local bag, slot = GetBagAndSlot(bagItem)
    if not button or not bag then
        return
    end

    local options = {
        statusProminentSize = 16,
        statusOffsetX = 7,
        statusOffsetY = 7
    }

    local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
    CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot }, options)
end

function BetterBagsMixin:Init()
    local BetterBags = LibStub('AceAddon-3.0'):GetAddon('BetterBags')
    local events = BetterBags:GetModule("Events")
    events:RegisterMessage('item/Updated', function (_, bagItem)
        trackedBagItems[bagItem] = true
        self:UpdateBagItem(bagItem)
    end)

    -- Sent when a button is released back to BetterBags' pool; its next draw is a full one
    -- (item/Updated), so it can be forgotten until then.
    events:RegisterMessage('item/Clearing', function (_, bagItem)
        trackedBagItems[bagItem] = nil
    end)

  -- self.mod = BetterBags:NewModule("CaerdonWardrobeBetterBagsUpdate", "ABEvent-1.0")
	-- self.mod.uiName = L["Caerdon Wardrobe"]
	-- self.mod.uiDesc= L["Identifies transmog appearances that still need to be learned"]

	-- self.mod.OnEnable = function(mod)
	-- 	mod:RegisterMessage('BetterBags_UpdateButton', 'UpdateButton')
	-- end

	-- self.mod.UpdateButton = function(mod, event, button)
	-- 	local bag = button.bag
	-- 	local slot = button.slot

	-- 	local options = {
	-- 	}

	-- 	local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
	-- 	CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot }, options)
	-- end
end

function BetterBagsMixin:GetTooltipData(item, locationInfo)
	if locationInfo.bag == BANK_CONTAINER then
		return C_TooltipInfo.GetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
	else
		return C_TooltipInfo.GetBagItem(locationInfo.bag, locationInfo.slot)
	end
end

function BetterBagsMixin:Refresh()
    CaerdonWardrobeFeatureMixin:Refresh(self)

    for bagItem in pairs(trackedBagItems) do
        local bag, slot = GetBagAndSlot(bagItem)
        -- Only revisit slots the client can describe right now. Free slots have nothing to
        -- show, and bank slots are unreadable away from the bank: re-running those would
        -- clear an icon that BetterBags will not ask us to draw again.
        if bag and C_Container.GetContainerItemID(bag, slot) then
            self:UpdateBagItem(bagItem)
        end
    end
end

-- BetterBags' own vendor window ("Next" vendor). It parks Blizzard's MerchantFrame under a hidden
-- parent and draws its own cards, so the Merchant feature's icons land on buttons nobody sees.
-- This feature decorates BetterBags' vendor buttons instead and follows the Merchant rules.
local BetterBagsVendorMixin = {}

-- NextVendorButtonFrame objects (BetterBags owns them and pools them).
local trackedVendorButtons = setmetatable({}, { __mode = "k" })

function BetterBagsVendorMixin:GetName()
    return "BetterBagsVendor"
end

function BetterBagsVendorMixin:GetStatusRuleName()
    return "Merchant"
end

function BetterBagsVendorMixin:UpdateVendorButton(vendorButton)
    local button = vendorButton.button
    if not button then
        return
    end

    -- mode / item / buyback are set by SetBuy / SetBuyback / SetRepair and cleared by Release.
    -- Repair entries are the toon's own gear, which the bag and character frames already cover.
    local mode = vendorButton.mode
    local entry = (mode == "buy" and vendorButton.item) or (mode == "buyback" and vendorButton.buyback) or nil
    local itemLink = entry and entry.link
    if not itemLink or not entry.index then
        button.caerdonDebugItemLink = nil
        CaerdonWardrobe:ClearButton(button)
        return
    end

    -- The tooltip is owned by this button, which is where the debug keybind looks.
    button.caerdonDebugItemLink = itemLink

    local options = {
        statusProminentSize = 16,
        statusOffsetX = 7,
        statusOffsetY = 7
    }
    local locationInfo = {
        locationKey = vendorButton.key or format("%s-%d", mode, entry.index),
        slot = entry.index,
        isBuyback = mode == "buyback"
    }

    local item = CaerdonItem:CreateFromItemLink(itemLink)
    local function doUpdate()
        -- The button may have been redrawn for something else while the item loaded.
        local current = (vendorButton.mode == "buy" and vendorButton.item) or
            (vendorButton.mode == "buyback" and vendorButton.buyback) or nil
        if vendorButton.mode == mode and current and current.link == itemLink then
            CaerdonWardrobe:UpdateButton(button, item, self, locationInfo, options)
        end
    end

    -- Same as the Merchant feature: item data has to be loaded before UpdateButton.
    if item:IsItemDataCached() then
        doUpdate()
    else
        item:ContinueOnItemLoad(doUpdate)
    end
end

-- BetterBags sends no message when a vendor button is drawn, only when one is created
-- (vendor/NewButton). Every draw goes through these methods, so each button's own copy is wrapped;
-- the prototype they come from is private to BetterBags.
local VENDOR_BUTTON_DRAW_METHODS = { "SetBuy", "SetBuyback", "SetRepair", "Release" }

function BetterBagsVendorMixin:TrackVendorButton(vendorButton)
    if type(vendorButton) ~= "table" or trackedVendorButtons[vendorButton] then
        return
    end
    trackedVendorButtons[vendorButton] = true

    for _, methodName in ipairs(VENDOR_BUTTON_DRAW_METHODS) do
        local original = vendorButton[methodName]
        if type(original) == "function" then
            vendorButton[methodName] = function(drawnButton, ...)
                original(drawnButton, ...)
                -- A problem on this side must not interrupt BetterBags' vendor draw.
                local ok, failure = pcall(self.UpdateVendorButton, self, drawnButton)
                if not ok then
                    geterrorhandler()(failure)
                end
            end
        end
    end
end

function BetterBagsVendorMixin:Init()
    local BetterBags = LibStub('AceAddon-3.0'):GetAddon('BetterBags')
    local events = BetterBags:GetModule("Events")

    -- Sent once for each button, before its first draw.
    events:RegisterMessage('vendor/NewButton', function(_, vendorButton)
        self:TrackVendorButton(vendorButton)
    end)

    -- Buttons made before this ran. The module does not exist in older BetterBags versions.
    local vendorButtons = BetterBags:GetModule("NextVendorButton", true)
    if vendorButtons and type(vendorButtons.all) == "table" then
        for _, vendorButton in ipairs(vendorButtons.all) do
            self:TrackVendorButton(vendorButton)
            self:UpdateVendorButton(vendorButton)
        end
    end

    -- The learnable icons are hidden while a copy sits in the bags (Merchant rules).
    return { "BAG_UPDATE_DELAYED" }
end

function BetterBagsVendorMixin:BAG_UPDATE_DELAYED()
    self:Refresh()
end

function BetterBagsVendorMixin:GetTooltipData(item, locationInfo)
    if locationInfo.isBuyback then
        return C_TooltipInfo.GetBuybackItem(locationInfo.slot)
    end
    return C_TooltipInfo.GetMerchantItem(locationInfo.slot)
end

function BetterBagsVendorMixin:GetDisplayInfo(button, item)
    local merchantFeature = CaerdonWardrobe:GetFeature("Merchant")
    if merchantFeature then
        return merchantFeature:GetDisplayInfo(button, item)
    end
    return {}
end

function BetterBagsVendorMixin:Refresh()
    CaerdonWardrobeFeatureMixin:Refresh(self)

    for vendorButton in pairs(trackedVendorButtons) do
        -- Pooled buttons have no mode and stay hidden until BetterBags draws them again.
        if vendorButton.mode and vendorButton.frame and vendorButton.frame:IsShown() then
            self:UpdateVendorButton(vendorButton)
        end
    end
end

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
	if C_AddOns.IsAddOnLoaded(addonName) then
		Version = C_AddOns.GetAddOnMetadata(addonName, 'Version')
		CaerdonWardrobe:RegisterFeature(BetterBagsMixin)
		CaerdonWardrobe:RegisterFeature(BetterBagsVendorMixin)
		isActive = true
	end
end

-- WagoAnalytics:Switch(addonName, isActive)
