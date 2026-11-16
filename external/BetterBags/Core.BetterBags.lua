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

-- The look of a default Blizzard bag slot (a 20 px icon on a 37 px slot, hanging over the corner),
-- scaled to the slot: BetterBags' slots follow its theme and icon scale. With no offsets passed,
-- the core keeps the inset in proportion to the icon. The Next panels leave more room around the
-- grid than the overhang needs; the classic bags leave none at the left and top, so there the
-- core moves the icon inside the slot (keepInsideWhenClipped).
local function GetSlotOptions(button)
    local width, height = button:GetSize()
    return {
        -- No upper limit: the slot is as big as the player made it in BetterBags.
        statusProminentSize = CaerdonWardrobe:GetSlotStatusSize(width, height, true),
        keepInsideWhenClipped = true
    }
end

function BetterBagsMixin:UpdateBagItem(bagItem)
    local button = bagItem.button
    local bag, slot = GetBagAndSlot(bagItem)
    if not button or not bag then
        return
    end

    local options = GetSlotOptions(button)

    local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
    CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot }, options)
end

-- Where this feature attaches to BetterBags (the integration report; see FeatureMixin.lua).
-- A message is a name BetterBags sends: that the registration exists does not prove the message
-- is still sent, only a draw does.
BetterBagsMixin.integration = {
    addon = addonName,
    hookPoints = { "Events:RegisterMessage item/Updated", "Events:RegisterMessage item/Clearing" },
}

function BetterBagsMixin:Init()
    local BetterBags = LibStub('AceAddon-3.0'):GetAddon('BetterBags')
    local events = BetterBags:GetModule("Events")
    self:NoteHookPoint("Events:RegisterMessage item/Updated", events, "RegisterMessage")
    self:NoteHookPoint("Events:RegisterMessage item/Clearing", events, "RegisterMessage")
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
	return C_TooltipInfo.GetBagItem(locationInfo.bag, locationInfo.slot)
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

    local options = GetSlotOptions(button)
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
        self:NoteHookPoint("NextVendorButton." .. methodName, vendorButton, methodName)
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

-- The buttons' draw methods are wrapped one button at a time, so those points are reached when
-- BetterBags' vendor window first shows an item.
BetterBagsVendorMixin.integration = {
    addon = addonName,
    hookPoints = {
        "Events:RegisterMessage vendor/NewButton",
        "NextVendorButton.SetBuy", "NextVendorButton.SetBuyback", "NextVendorButton.SetRepair", "NextVendorButton.Release",
    },
}

function BetterBagsVendorMixin:Init()
    local BetterBags = LibStub('AceAddon-3.0'):GetAddon('BetterBags')
    local events = BetterBags:GetModule("Events")
    self:NoteHookPoint("Events:RegisterMessage vendor/NewButton", events, "RegisterMessage")

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

-- BetterBags' own guild bank ("Next" guild bank). Blizzard's GuildBankFrame stays hidden while it is
-- open, so the GuildBank feature's icons land on buttons nobody sees. This feature decorates
-- BetterBags' guild bank buttons instead and follows the GuildBank rules.
local BetterBagsGuildBankMixin = {}

-- NextGuildButtonFrame objects (BetterBags owns them and pools them).
local trackedGuildButtons = setmetatable({}, { __mode = "k" })

function BetterBagsGuildBankMixin:GetName()
    return "BetterBagsGuildBank"
end

function BetterBagsGuildBankMixin:GetStatusRuleName()
    return "GuildBank"
end

-- The guild bank tab and slot a button shows an item of, or nil for a free slot or a pooled button.
-- data is set by SetItemFromData and cleared by SetFreeSlots and Release; tab is the item's own
-- tab, also in the view that shows every tab at once.
local function GetGuildTabAndSlot(guildButton)
    local data = guildButton.data
    if type(data) == "table" and guildButton.tab and data.slotid then
        return guildButton.tab, data.slotid
    end
end

function BetterBagsGuildBankMixin:UpdateGuildButton(guildButton)
    local button = guildButton.button
    if not button then
        return
    end

    local tab, slot = GetGuildTabAndSlot(guildButton)
    local itemLink = tab and GetGuildBankItemLink(tab, slot)
    if not itemLink then
        button.caerdonDebugItemLink = nil
        CaerdonWardrobe:ClearButton(button)
        return
    end

    -- The tooltip is owned by this button, which is where the debug keybind looks.
    button.caerdonDebugItemLink = itemLink

    local options = GetSlotOptions(button)
    local locationInfo = {
        locationKey = format("tab%d-index%d", tab, slot),
        tab = tab,
        index = slot
    }

    local item = CaerdonItem:CreateFromItemLink(itemLink)
    local function doUpdate()
        -- The button may have been redrawn for something else while the item loaded.
        local currentTab, currentSlot = GetGuildTabAndSlot(guildButton)
        if currentTab == tab and currentSlot == slot and GetGuildBankItemLink(tab, slot) == itemLink then
            CaerdonWardrobe:UpdateButton(button, item, self, locationInfo, options)
        end
    end

    if item:IsItemDataCached() then
        doUpdate()
    else
        item:ContinueOnItemLoad(doUpdate)
    end
end

BetterBagsGuildBankMixin.integration = {
    addon = addonName,
    hookPoints = { "Events:RegisterMessage guild/Updated" },
}

function BetterBagsGuildBankMixin:Init()
    local BetterBags = LibStub('AceAddon-3.0'):GetAddon('BetterBags')
    local events = BetterBags:GetModule("Events")
    self:NoteHookPoint("Events:RegisterMessage guild/Updated", events, "RegisterMessage")

    -- Sent after every draw of a button, for an item and for a free slot. A released button is
    -- hidden and sends nothing; its next draw is announced again.
    events:RegisterMessage('guild/Updated', function(_, guildButton)
        if type(guildButton) ~= "table" then
            return
        end
        trackedGuildButtons[guildButton] = true
        -- A problem on this side must not interrupt BetterBags' guild bank draw.
        local ok, failure = pcall(self.UpdateGuildButton, self, guildButton)
        if not ok then
            geterrorhandler()(failure)
        end
    end)
end

function BetterBagsGuildBankMixin:GetTooltipData(item, locationInfo)
    return C_TooltipInfo.GetGuildBankItem(locationInfo.tab, locationInfo.index)
end

function BetterBagsGuildBankMixin:GetDisplayInfo(button, item)
    local guildBankFeature = CaerdonWardrobe:GetFeature("GuildBank")
    if guildBankFeature then
        return guildBankFeature:GetDisplayInfo(button, item)
    end
    return {}
end

function BetterBagsGuildBankMixin:Refresh()
    CaerdonWardrobeFeatureMixin:Refresh(self)

    for guildButton in pairs(trackedGuildButtons) do
        -- Pooled buttons and free slots have no item; BetterBags draws them again when they do.
        if GetGuildTabAndSlot(guildButton) and guildButton.frame and guildButton.frame:IsShown() then
            self:UpdateGuildButton(guildButton)
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
		CaerdonWardrobe:RegisterFeature(BetterBagsGuildBankMixin)
		isActive = true
	end
end

-- WagoAnalytics:Switch(addonName, isActive)
