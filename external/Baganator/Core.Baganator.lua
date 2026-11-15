local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "Baganator"
local BaganatorMixin = {}

-- Baganator has a placement system of its own. Addons register "corner widgets", the player
-- sorts them into the four corners of a slot in Baganator's settings (Icon Corners), and in each
-- corner the first widget with something to show is the one that shows. The status icon, the
-- binding text (or a gear set's name) and the level gain are three such widgets, so in
-- Baganator's bags:
--   * where a part sits, and whether it or another addon's widget gets the corner, is
--     Baganator's business. options.hostPlacesParts keeps the drawing code from anchoring,
--     showing or hiding the parts; it only fills them.
--   * how big a part is still comes from this addon's layout settings.
--
-- A widget has to say whether it has something to show: true, false, or nil for "not known yet,
-- ask again" (Baganator then asks on the next frame). Items are drawn a moment after they are
-- requested, so the first answer for an item is nil and the real one follows the draw
-- (OnButtonDrawn). Answering true for every item, as this did until 2026-11-14, claimed the
-- corner on items with nothing drawn and hid whatever came after it there.
local WIDGETS = {
    icon = "caerdon_wardrobe_status",
    text = "caerdon_wardrobe_binding",
    gain = "caerdon_wardrobe_level_gain",
}
-- How long an item may stay "not known yet". Baganator asks again every frame for as long as it
-- hears nil, so an item that is never drawn has to end as "nothing to show". If it is drawn
-- after all, Baganator is asked to look again.
local PENDING_LIMIT = 3

local options = {
    fixedStatusPosition = true,
    hostPlacesParts = true,
    statusProminentSize = 16,
}

local NOTHING = { icon = false, text = false, gain = false }

-- Per Baganator item button: which item it was last asked about, what was drawn for it, and
-- what Baganator has been told.
local states = setmetatable({}, { __mode = "k" })

local function ShouldClearBaganatorButton(details)
    if type(details) ~= "table" then
        return true
    end

    if details.itemID or details.itemLink or details.hyperlink or details.itemKey or details.battlePetSpeciesID then
        return false
    end

    return true
end

-- Baganator freezes its ItemButton mixin tables, so we hook SetItemDetails on
-- each button instance rather than on the shared mixin.
local function HookBaganatorButton(itemButton)
    if not itemButton or itemButton.caerdonSetItemDetailsHooked then
        return
    end
    if type(itemButton.SetItemDetails) ~= "function" then
        return
    end
    itemButton.caerdonSetItemDetailsHooked = true
    hooksecurefunc(itemButton, "SetItemDetails", function(button, details)
        if not ShouldClearBaganatorButton(details) then
            return
        end
        states[button] = nil
        CaerdonWardrobe:ClearButton(button)
    end)
end

local function IsWidgetActive(part)
    return Baganator.API.IsCornerWidgetActive(WIDGETS[part]) and true or false
end

local function RequestWidgetRefresh()
    local reasons = Baganator.Constants and Baganator.Constants.RefreshReason
    if reasons and reasons.ItemWidgets then
        Baganator.API.RequestItemButtonsRefresh({ reasons.ItemWidgets })
    else
        Baganator.API.RequestItemButtonsRefresh()
    end
end

function BaganatorMixin:GetName()
    return addonName
end

-- Shown in the layout editor (see "Layout editor" in CLAUDE.md).
function BaganatorMixin:GetLayoutNote()
    return "Baganator: where the icon, the binding text and the level gain sit is set in Baganator's own settings " ..
        "(Icon Corners). Their sizes are set here."
end

-- Nothing is hidden because of what else is on the slot. Until 2026-11-14 the upgrade arrow was
-- left out whenever Baganator's own "Pawn" widget was in one of its corners and Pawn called the
-- item an upgrade, on the assumption that Baganator would show that arrow. It often does not
-- (another widget ahead of it in its corner takes the corner), and this addon's arrow says more
-- than Pawn's (another talent tree's upgrade, a level too low, a gear set item). Which of two
-- arrows shows is the player's choice in Baganator's Icon Corners: in the same corner only the
-- higher one shows.
function BaganatorMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
    return {}
end

-- Has the item on this button drawn. One request serves all three widgets.
function BaganatorMixin:RequestDraw(itemButton, details, state, bag, slot)
    local item, locationInfo
    if bag and slot then
        item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
        locationInfo = { bag = bag, slot = slot }
    elseif details.itemLink then
        item = CaerdonItem:CreateFromItemLink(details.itemLink)
        -- Per button: the same link can sit in several slots of a view that has no bag slots.
        locationInfo = { locationKey = format("%s-%s", details.itemLink, tostring(itemButton)) }
    end

    state.item = item
    if not item then
        state.drawn = NOTHING
        CaerdonWardrobe:ClearButton(itemButton)
        return
    end
    if item:IsItemEmpty() and item:GetCaerdonItemType() == CaerdonItemType.Empty then
        state.drawn = NOTHING -- UpdateButton clears the button and draws nothing
    end
    CaerdonWardrobe:UpdateButton(itemButton, item, self, locationInfo, options)
end

-- Baganator's question for one widget: does this part have something to show on this button?
function BaganatorMixin:Ask(itemButton, details, part)
    if not itemButton or type(details) ~= "table" then
        return false
    end

    local bag = itemButton.GetBagID and itemButton:GetBagID() or nil
    local slot = itemButton.GetID and itemButton:GetID() or nil
    local itemKey = format("%s:%s:%s", tostring(bag), tostring(slot), tostring(details.itemLink))
    local generation = CaerdonWardrobe:GetRefreshGeneration()

    local state = states[itemButton]
    if not state or state.itemKey ~= itemKey then
        state = { itemKey = itemKey, answered = {} }
        states[itemButton] = state
    end
    if state.generation ~= generation then
        -- A new item, or the same item after something changed (a look learned, a setting): have
        -- it drawn. For the same item the last result stands in until the new one is there, so
        -- the icons do not blink off on every refresh; OnButtonDrawn corrects it if it changed.
        state.generation = generation
        state.requestedAt = GetTime()
        state.gaveUp = nil
        self:RequestDraw(itemButton, details, state, bag, slot)
    end

    local drawn = state.drawn
    if drawn then
        state.answered[part] = drawn[part]
        return drawn[part]
    end
    if state.gaveUp or GetTime() - state.requestedAt > PENDING_LIMIT then
        state.gaveUp = true
        state.answered[part] = false
        return false
    end
    return nil
end

-- Called by the core after it drew one of this feature's buttons.
function BaganatorMixin:OnButtonDrawn(itemButton, item)
    local state = states[itemButton]
    if not state or state.item ~= item then
        return -- drawn for a request this button has moved on from
    end

    local hasIcon, hasText, hasGain = CaerdonWardrobe:GetDrawnParts(itemButton)
    local drawn = { icon = hasIcon, text = hasText, gain = hasGain }
    state.drawn = drawn

    -- A part the player took out of Baganator's corners is not placed by anyone. The icon and the
    -- level gain stay hidden then (nothing shows them); the text has to be emptied.
    if hasText and not IsWidgetActive("text") then
        local caerdonButton = CaerdonWardrobe:GetCaerdonButton(itemButton)
        if caerdonButton and caerdonButton.bindsOnText then
            caerdonButton.bindsOnText:SetText("")
        end
    end

    -- Baganator already holds an answer for this item that the draw proved wrong (it gave up
    -- waiting, or the stand-in from before a refresh no longer fits): have it ask again.
    local stale = false
    for part, answer in pairs(state.answered) do
        if answer ~= drawn[part] then
            stale = true
        end
    end
    if stale then
        state.answered = {}
        RequestWidgetRefresh()
    end
end

function BaganatorMixin:Init()
    local function Register(label, part, regionName, defaultPosition)
        Baganator.API.RegisterCornerWidget(label, WIDGETS[part], function(region, details)
            local itemButton = region.caerdonItemButton or region:GetParent():GetParent()
            return self:Ask(itemButton, details, part)
        end, function(itemButton)
            HookBaganatorButton(itemButton)
            -- With no item, this only creates the overlay and its parts ahead of time.
            CaerdonWardrobe:UpdateButton(itemButton, nil, self, nil, options)
            local caerdonButton = CaerdonWardrobe:GetCaerdonButton(itemButton)
            local region = caerdonButton and caerdonButton[regionName]
            if region then
                region.caerdonItemButton = itemButton
            end
            return region
        end, defaultPosition)
    end

    Register("Caerdon Status", "icon", "mogStatus", { corner = "top_right", priority = 1 })
    Register("Caerdon Binding", "text", "bindsOnText", { corner = "bottom_left", priority = 2 })
    -- Ahead of Baganator's stack count: gear that shows a level gain does not stack.
    Register("Caerdon Level Gain", "gain", "upgradeDeltaText", { corner = "bottom_right", priority = 1 })
end

function BaganatorMixin:GetTooltipData(item, locationInfo)
    -- if locationInfo.bag == BANK_CONTAINER then
    -- 	return C_TooltipInfo.GetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
    -- else
    -- 	return C_TooltipInfo.GetBagItem(locationInfo.bag, locationInfo.slot)
    -- end
end

function BaganatorMixin:Refresh()
    if IsWidgetActive("icon") or IsWidgetActive("text") or IsWidgetActive("gain") then
        Baganator.API.RequestItemButtonsRefresh()
    end
end

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
    if C_AddOns.IsAddOnLoaded(addonName) then
        Version = C_AddOns.GetAddOnMetadata(addonName, 'Version')
        CaerdonWardrobe:RegisterFeature(BaganatorMixin)
        isActive = true
    end
end

-- WagoAnalytics:Switch(addonName, isActive)
