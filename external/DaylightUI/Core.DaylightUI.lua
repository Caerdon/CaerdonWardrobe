local ADDON_NAME = ...

local addonName = "DaylightUI"

-- Daylight UI (WoW Forever) has windows of its own in the place of several of the game's. The
-- features here attach through its public API (DaylightUI.API, its API.md), which is promised
-- to keep working within a major version; with another one they stay quiet. Where the API has
-- no word of a window, a feature hooks a function of Daylight UI's own through that API, which
-- the API allows and makes no promise for (AttachAndNote).
local function GetAPI()
    local API = DaylightUI.API
    if type(API) == "table" and API.major == 1 then
        return API
    end
end

-- A function of Daylight UI's own, hooked or wrapped through its API (API.For(addon).Hook or
-- .Wrap, which its API allows and does not promise the functions for). Daylight UI runs the
-- hook contained, under the name given to API.For, and refuses a table that is not its own. That
-- it took the hook is noted as a hook point of its own (`label`), so a Daylight UI that refuses
-- it reads as a missing hook point in the integration report and raises no error: it hands back
-- a handle where it took it, and the function in the table is another one after the first hook.
local function AttachAndNote(feature, attach, owner, key, label, fn)
    local before = owner[key]
    local handle = attach(owner, key, fn)
    local inPlace = owner[key]
    local attached = type(handle) == "table" or inPlace ~= before
    feature:NoteHookPoint(label, { attached = attached and inPlace or nil }, "attached")
    return attached
end

-- An icon of Daylight UI's is a bag slot in miniature: a row's or a line's is 28 across, a
-- tile's 34, against a bag slot's 37. The status icon is sized to it (GetSlotStatusSize) and the
-- texts with it (GetSlotScale), so the player's layout holds there as it does in the bags; with
-- the texts at a bag slot's size the level gain lay across the star on a row and "BoE" across
-- the icon on a line (both seen in the Forever client). A list cuts off what hangs over its
-- edge, so the icon moves inside where there is no room. `sized` is the frame or the texture
-- whose size is the icon's, `madeSize` the size Daylight UI made the icon with, for one that is
-- not laid out yet.
--
-- Daylight UI's pages put an icon 4.5 to 5 from the edge of their list (5 measured on a line
-- of the profession list), which is what the status icon hangs over a corner by, give or take
-- one: 4.5 on a line, 5.5 at its full size on a tile. A tenth of the icon may be cut off
-- there before it moves inside, where it is a fifth smaller and lies on the item: it then
-- hangs over its corner as the player's layout has it, and still moves inside when the
-- player makes it much larger.
local ICON_CUT_ALLOWED = 0.1

local function GetIconOptions(sized, madeSize)
    local width, height = sized:GetSize()
    if (width or 0) < 1 or (height or 0) < 1 then
        width = tonumber(madeSize) or 0
        height = width
    end
    return {
        statusProminentSize = CaerdonWardrobe:GetSlotStatusSize(width, height),
        slotScale = CaerdonWardrobe:GetSlotScale(width, height),
        keepInsideWhenClipped = true,
        clipCutAllowed = ICON_CUT_ALLOWED,
    }
end

-- The size Daylight UI makes a line's icon with, for one that is not laid out yet.
local function GetLineIconSize()
    local parts = type(DaylightUI.Win) == "table" and DaylightUI.Win.Parts or nil
    return type(parts) == "table" and parts.LINE_ICON or nil
end

-- A line of a list: Daylight UI puts the line's spec on it.
local function IsLine(piece)
    return type(piece) == "table" and type(piece.lineSpec) == "table" and type(piece.icon) == "table"
end

-- An item's tile of one of Daylight UI's pages (a letter's attachment, a quest's reward):
-- Daylight UI puts the tile's spec on it before it sets its icon, and makes the icon with its
-- size on the tile. A page's other pieces, a text, a line, are none.
local function IsItemTile(piece)
    return type(piece) == "table" and type(piece.spec) == "table" and type(piece.icon) == "table" and
        type(piece.iconSize) == "number"
end

-- A tile's icon, by the size Daylight UI made it with. A stack's count is at the icon's foot.
local function GetItemTileOptions(tile, hasCount)
    return {
        statusProminentSize = CaerdonWardrobe:GetSlotStatusSize(tile.iconSize, tile.iconSize),
        slotScale = CaerdonWardrobe:GetSlotScale(tile.iconSize, tile.iconSize),
        keepInsideWhenClipped = true,
        clipCutAllowed = ICON_CUT_ALLOWED,
        hasCount = hasCount,
    }
end

-- A frame of Daylight UI's that its API hands no holder for (a row, a line, a tile of a page)
-- gets a frame of this addon's on it, over its icon: the button the core is asked for. Kept
-- per feature as `entries[frame] = { holder = that frame, key = what was last asked for it }`.
-- Daylight UI's frame owns the tooltip; the Debug Frame finds what was asked of it through the
-- note.
local function GetEntry(entries, frame)
    local entry = entries[frame]
    if not entry then
        local holder = CreateFrame("Frame", nil, frame)
        holder:SetAllPoints(frame.icon)
        entry = { holder = holder }
        entries[frame] = entry
        CaerdonWardrobe:NoteButtonOn(frame, holder)
    end
    return entry
end

-- Such a frame shows no item any more.
local function ReleaseEntry(entry)
    if entry and entry.key then
        entry.key = nil
        CaerdonWardrobe:ClearButton(entry.holder)
        -- Without the key, a request still on its way for this frame is dropped instead of
        -- drawn on a pooled one.
        CaerdonWardrobe:ClearButtonState(entry.holder)
    end
end

-- Daylight UI shows a vendor's goods on tiles of its own, in its NPC window, and holds the
-- game's MerchantFrame aside while it does: the Merchant feature's icons land on buttons
-- nobody sees. This feature decorates Daylight UI's tiles instead, by the vendor's rules:
--   * API.On("FrameStyled", ...) comes for each tile on show after every fill of the shelf
--     (a vendor opened, a search, money or the bags changed), API.On("FrameRemoved", ...) when
--     a tile is hidden or the window closes. Tiles are pooled.
--   * API.ShopItem(tile) says what a tile holds: the tab ("buy" or "buyback"), the game's
--     index there, and the item's link.
--   * API.Attach(tile) is a plain frame of Daylight UI's over the tile, for another addon to
--     draw on: the overlay is made on that, never on the tile. API.GetPart(tile, "icon") is
--     the tile's icon, which the overlay is laid over.
-- A vendor window that stands in for Daylight UI's own hands its tiles over the same way.
local VendorMixin = {}

-- Tiles on show: [tile] = what was last asked for it (its tab, index, link and whether it has
-- a count) and whether it is a sample's. With no link it is asked for whatever it holds: the
-- game had none yet, or a refresh forgot it. Weak keys: the tiles are Daylight UI's.
local shownTiles = setmetatable({}, { __mode = "k" })

function VendorMixin:GetName()
    return "DaylightUIVendor"
end

-- The vendor's own rules, asked of its feature so the two cannot drift apart.
function VendorMixin:GetStatusRules()
    local merchant = CaerdonWardrobe:GetFeature("Merchant")
    return merchant and merchant:GetStatusRules()
end

-- Its display rules go by whether a copy is carried, so they are asked for at each draw. The
-- vendor has no GetDisplayInfo; one it gained would have to be passed on here as well.
function VendorMixin:GetDisplayRules(...)
    local merchant = CaerdonWardrobe:GetFeature("Merchant")
    return merchant and merchant:GetDisplayRules(...)
end

VendorMixin.integration = {
    addon = addonName,
    hookPoints = {
        "DaylightUI.API.On", "DaylightUI.API.ShopItem", "DaylightUI.API.Attach", "DaylightUI.API.GetPart",
    },
}

function VendorMixin:Init()
    local API = GetAPI()
    if not API then
        return
    end
    local found = self:NoteHookPoint("DaylightUI.API.On", API, "On")
    found = self:NoteHookPoint("DaylightUI.API.ShopItem", API, "ShopItem") and found
    found = self:NoteHookPoint("DaylightUI.API.Attach", API, "Attach") and found
    found = self:NoteHookPoint("DaylightUI.API.GetPart", API, "GetPart") and found
    if not found then
        return
    end
    self.API = API

    -- Daylight UI runs a listener contained and names its owner where it raises an error.
    API.On("FrameStyled", function(kind, tile, _, isSample)
        if kind == "shoptile" then
            self:UpdateTile(tile, isSample)
        end
    end, ADDON_NAME)
    API.On("FrameRemoved", function(kind, tile)
        if kind == "shoptile" then
            self:ReleaseTile(tile)
        end
    end, ADDON_NAME)

    -- The learnable icons are hidden while a copy sits in the bags (the vendor's rules).
    return { "BAG_UPDATE_DELAYED" }
end

function VendorMixin:BAG_UPDATE_DELAYED()
    self:Refresh()
end

-- Whether the tile shows a count on its icon, which the binding text then sits above. A
-- sample tile (Daylight UI's options preview) is no vendor's, so the game is not asked.
local function HasCount(tab, index, isSample)
    if isSample then
        return false
    end
    local count
    if tab == "buyback" then
        count = select(4, GetBuybackItemInfo(index))
    else
        local info = C_MerchantFrame.GetItemInfo(index)
        count = info and info.stackCount
    end
    return (tonumber(count) or 0) > 1
end

-- A bag slot in miniature, over the tile's icon (GetIconOptions).
local function GetTileOptions(icon, hasCount)
    local options = GetIconOptions(icon)
    options.relativeFrame = icon
    options.hasCount = hasCount
    return options
end

function VendorMixin:UpdateTile(tile, isSample)
    local API = self.API
    local holder = API.Attach(tile)
    if not holder then
        return
    end

    local asked = shownTiles[tile]
    if not asked then
        asked = {}
        shownTiles[tile] = asked
    end
    asked.isSample = isSample and true or false

    local tab, index, _, link = API.ShopItem(tile)
    local icon = API.GetPart(tile, "icon")
    if not (tab and index and link and icon) then
        -- No link yet: Daylight UI fills the shelf again when the game has it.
        asked.link = nil
        CaerdonWardrobe:ClearButton(holder)
        return
    end

    -- A shelf is filled again whenever money or the bags change. What a tile was last asked
    -- for stands until it holds something else; Refresh() forgets it.
    local hasCount = HasCount(tab, index, isSample)
    if asked.link == link and asked.tab == tab and asked.index == index and asked.hasCount == hasCount then
        return
    end
    asked.tab, asked.index, asked.link, asked.hasCount = tab, index, link, hasCount
    -- The tile owns the tooltip; the Debug Frame finds what was asked of it through this.
    CaerdonWardrobe:NoteButtonOn(tile, holder)

    self:Decorate(holder, link, {
        locationKey = format("%s%s-%d", isSample and "sample-" or "", tab, index),
        slot = index,
        isBuyback = tab == "buyback",
        isSample = asked.isSample,
    }, GetTileOptions(icon, hasCount))
end

function VendorMixin:ReleaseTile(tile)
    if not shownTiles[tile] then
        return
    end
    shownTiles[tile] = nil
    local holder = self.API.Attach(tile)
    if holder then
        CaerdonWardrobe:ClearButton(holder)
        -- Without the key, a request still on its way for this tile is dropped instead of
        -- drawn on a pooled one.
        CaerdonWardrobe:ClearButtonState(holder)
    end
end

function VendorMixin:GetTooltipData(item, locationInfo)
    if locationInfo.isSample then
        return nil
    end
    if locationInfo.isBuyback then
        return C_TooltipInfo.GetBuybackItem(locationInfo.slot)
    end
    return C_TooltipInfo.GetMerchantItem(locationInfo.slot)
end

function VendorMixin:Refresh()
    CaerdonWardrobeFeatureMixin:Refresh(self)

    -- A tile is asked for again while it is on screen. One that is not is asked for at the
    -- shelf's next fill, which every showing of the shelf brings, so nothing is owed to it.
    for tile, asked in pairs(shownTiles) do
        asked.link = nil
        if tile:IsVisible() then
            self:UpdateTile(tile, asked.isSample)
        end
    end
end

-- Daylight UI's bag slots. Its Bags module asks this addon for a slot that holds an item
-- itself (a feature of its own named "Daylight UI", registered once both addons are loaded),
-- and shows and hides the status icon and the binding text as two widgets of its corners. For
-- a slot that holds nothing it asks for nothing: what else was on the slot, the level gain,
-- stayed there when the item left. This feature draws nothing; it clears such a slot.
--
-- A painter of "bagslot" (API.For(addon).Paint) is called after each fill of a slot, with what
-- the slot holds: a table whose item is nil for an empty slot. It is the API's one word of a
-- slot that has emptied, and it comes after Daylight UI's own ask for the slot.
--
-- Where the icon is in a slot is Daylight UI's own word: its Bags module pins the icon in the
-- top right corner of each slot, once, when it makes its widget for the slot, and asks for
-- every slot with options that say so (a fixed place, 16 across). The player can choose their
-- own layout there too (the layout editor's box, off unless ticked): this feature then
-- answers for the placement of that window's requests (CaerdonWardrobe:AnswerOptionsFor) with
-- a bag slot's own, and the core places the icon as it does in any other bag. With the box
-- off again the icon is pinned back where Daylight UI had it, which is remembered per slot:
-- Daylight UI does not pin it a second time.
--
-- One upgrade arrow in a slot. Daylight UI draws Pawn's arrow in its bags itself, as a widget
-- of a slot's top left corner, and has no setting for it; this addon's arrow (or its badge, or
-- its mark of an upgrade to come) was on the same slot, which was two arrows for one verdict.
-- Daylight UI's bags answer the calls Baganator's plugins make (a `Baganator` table of its
-- own while Baganator is off, marked `DaylightUI`), and show one widget per corner, the one
-- with the lowest priority number that says it shows. This feature registers a widget there
-- that draws nothing, in Pawn's corner and ahead of it, which says it shows where this addon
-- has drawn an upgrade on the slot: Pawn's arrow is then not shown, and is where this addon
-- draws none (its arrow switched off, or a verdict that differs). What is on a slot is known
-- once it is drawn (CaerdonWardrobe:NoteDrawsFor), so a draw that changes the answer asks
-- Daylight UI to go over its slots again. Which corner Pawn's arrow has there is Daylight
-- UI's code and not its API: moved, both arrows show again, and nothing else follows.
local BagSlotsMixin = {}

-- The name of the feature Daylight UI's Bags module registers with this addon.
local DAYLIGHT_BAGS_FEATURE = "Daylight UI"

-- [slot] = this addon's options for it, which carry Daylight UI's (`daylightOptions`), and
-- [slot] = where Daylight UI pinned the icon. Weak keys: the slots are Daylight UI's.
local ownSlotOptions = setmetatable({}, { __mode = "k" })
local pinnedIcons = setmetatable({}, { __mode = "k" })

-- The widget that takes Pawn's corner, and the slot's part of it (weak keys throughout: the
-- slots are Daylight UI's): [the widget's frame] = its slot, [slot] = { itemID, upgrade } as
-- this addon last drew it, [slot] = what Daylight UI was last told.
local UPGRADE_CLAIM = "caerdon_wardrobe_upgrade"
local PAWN_CORNER = { corner = "top_left", priority = 0 }
local claimSlots = setmetatable({}, { __mode = "k" })
local drawnOnSlots = setmetatable({}, { __mode = "k" })
local toldOfSlots = setmetatable({}, { __mode = "k" })

local function WantsOwnLayoutInBags()
    local config = CaerdonWardrobeConfig and CaerdonWardrobeConfig.DaylightUI
    return type(config) == "table" and config.OwnLayoutInBags == true
end

local function SetOwnLayoutInBags(chosen)
    if type(CaerdonWardrobeConfig.DaylightUI) ~= "table" then
        CaerdonWardrobeConfig.DaylightUI = {}
    end
    CaerdonWardrobeConfig.DaylightUI.OwnLayoutInBags = chosen and true or false
end

-- Shown in the layout editor's callout while Daylight UI's bags are in use: what does not
-- follow the player's layout there, with the box that makes it follow.
function BagSlotsMixin:GetLayoutNote()
    if not CaerdonWardrobe:GetFeature(DAYLIGHT_BAGS_FEATURE) then
        return nil
    end
    local own = WantsOwnLayoutInBags()
    local text
    if own then
        text = "Daylight UI: its bags and bank follow this layout, by the box below. Daylight UI has marks of " ..
            "its own in a slot's corners there (its binding text at the top left, an equipment set's dot at the " ..
            "top right, the item level at the bottom left), which the icon can lie across."
    else
        text = "Daylight UI: Position, Size and Nudge of the icon do not apply in Daylight UI's bags and bank. " ..
            "Daylight UI puts the icon in the top right corner of a slot there, at a size of its own. Its " ..
            "other windows follow all of this."
    end
    return text, "Use my layout in Daylight UI's bags and bank", SetOwnLayoutInBags, own
end

-- The options a request of Daylight UI's bags is drawn with. `options` is what Daylight UI
-- handed, or what this answered before (the core asks again with what it remembered).
function BagSlotsMixin:AnswerOptions(slot, item, locationInfo, options)
    local theirs = type(options) == "table" and options.daylightOptions or options
    local overlay = slot and CaerdonWardrobe:GetCaerdonButton(slot)
    local icon = overlay and overlay.mogStatus

    if not WantsOwnLayoutInBags() then
        -- Back where Daylight UI pinned it, where the layout has moved it since.
        local pinned = icon and pinnedIcons[slot]
        if pinned then
            local _, relativeTo = icon:GetPoint(1)
            if relativeTo ~= pinned.relativeTo then
                icon:ClearAllPoints()
                icon:SetPoint(pinned.point, pinned.relativeTo, pinned.relativePoint, pinned.x, pinned.y)
            end
        end
        return theirs
    end
    if not slot then
        return theirs
    end

    -- Daylight UI pins the icon to the slot itself; the core anchors it to its own overlay.
    if icon then
        local point, relativeTo, relativePoint, x, y = icon:GetPoint(1)
        if point and relativeTo == slot then
            pinnedIcons[slot] = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y }
        end
    end

    -- A bag slot of whatever size the player gave it there, in a list that scrolls. The stack's
    -- count is Daylight UI's own text, at the slot's foot.
    local width, height = slot:GetSize()
    local hasCount = false
    if type(locationInfo) == "table" and locationInfo.bag and locationInfo.slot then
        local held = C_Container.GetContainerItemInfo(locationInfo.bag, locationInfo.slot)
        hasCount = (held and tonumber(held.stackCount) or 0) > 1
    end
    local ours = ownSlotOptions[slot]
    if not ours or ours.daylightOptions ~= theirs or ours.forWidth ~= width or ours.forHeight ~= height or
        ours.hasCount ~= hasCount then
        ours = {
            statusProminentSize = CaerdonWardrobe:GetSlotStatusSize(width, height, true),
            slotScale = CaerdonWardrobe:GetSlotScale(width, height),
            keepInsideWhenClipped = true,
            hasCount = hasCount,
            daylightOptions = theirs,
            forWidth = width,
            forHeight = height,
        }
        ownSlotOptions[slot] = ours
    end
    return ours
end

-- Slots cleared since they last held an item (weak keys: the slots are Daylight UI's). An
-- empty slot is filled again at every layout of its window, and is cleared once.
local emptySlots = setmetatable({}, { __mode = "k" })

function BagSlotsMixin:GetName()
    return "DaylightUIBagSlots"
end

BagSlotsMixin.integration = {
    addon = addonName,
    hookPoints = { "DaylightUI.API.For", "DaylightUI.API.For(addon).Paint" },
    -- Daylight UI's bags are a module of their own, which the player can leave off.
    optionalHookPoints = {
        "DaylightUI_Bags Baganator.API.RegisterCornerWidget", "DaylightUI_Bags Baganator.API.RequestItemButtonsRefresh",
    },
}

function BagSlotsMixin:Init()
    -- Whatever the API is: Daylight UI's bags ask this addon without it.
    CaerdonWardrobe:AnswerOptionsFor(DAYLIGHT_BAGS_FEATURE, function(...)
        return self:AnswerOptions(...)
    end)
    CaerdonWardrobe:NoteDrawsFor(DAYLIGHT_BAGS_FEATURE, function(slot, item)
        self:OnSlotDrawn(slot, item)
    end)
    self:WhenAddOnLoaded("DaylightUI_Bags", self.ClaimPawnCorner)

    local API = GetAPI()
    if not API then
        return
    end
    if not self:NoteHookPoint("DaylightUI.API.For", API, "For") then
        return
    end
    local me = API.For(ADDON_NAME)
    if not self:NoteHookPoint("DaylightUI.API.For(addon).Paint", me, "Paint") then
        return
    end
    -- Daylight UI runs a painter contained, under the name given to API.For.
    me.Paint("bagslot", function(slot, _, held)
        self:OnSlotFilled(slot, held)
    end)
end

-- Daylight UI's own stand-in for Baganator's plugin calls, and not Baganator's.
function BagSlotsMixin:ClaimPawnCorner()
    local shim = Baganator
    local plugins = type(shim) == "table" and shim.DaylightUI == true and type(shim.API) == "table" and shim.API or nil
    local canClaim = self:NoteHookPoint("DaylightUI_Bags Baganator.API.RegisterCornerWidget", plugins, "RegisterCornerWidget")
    canClaim = self:NoteHookPoint("DaylightUI_Bags Baganator.API.RequestItemButtonsRefresh", plugins,
        "RequestItemButtonsRefresh") and canClaim
    if not canClaim then
        return
    end
    self.plugins = plugins
    -- Daylight UI calls both contained, and drops a widget for good after one error.
    plugins.RegisterCornerWidget("Caerdon Wardrobe: upgrade", UPGRADE_CLAIM, function(claim, details)
        local slot = claimSlots[claim]
        local drawn = slot and drawnOnSlots[slot]
        local upgrade = (drawn ~= nil and type(details) == "table" and drawn.itemID ~= nil and
            drawn.itemID == details.itemID and drawn.upgrade) and true or false
        if slot then
            toldOfSlots[slot] = upgrade
        end
        return upgrade
    end, function(slot)
        local claim = CreateFrame("Frame", nil, slot)
        claim:SetSize(1, 1)
        claimSlots[claim] = slot
        return claim
    end, PAWN_CORNER)
end

-- A slot of Daylight UI's bags was drawn. Where that changes whether an upgrade is on it from
-- what Daylight UI was told, its slots are gone over again (one pass for a burst of them, on
-- the next frame). The pass asks for every slot again, and its draws tell nothing new.
function BagSlotsMixin:OnSlotDrawn(slot, item)
    if not self.plugins or not slot then
        return
    end
    local _, _, _, upgrade = CaerdonWardrobe:GetDrawnParts(slot)
    local drawn = drawnOnSlots[slot]
    if not drawn then
        drawn = {}
        drawnOnSlots[slot] = drawn
    end
    drawn.itemID, drawn.upgrade = item and item:GetItemID() or nil, upgrade
    local told = toldOfSlots[slot]
    if told ~= nil and told ~= upgrade then
        -- Noted as told at once, so that a second draw before the pass does not ask for another.
        toldOfSlots[slot] = upgrade
        self.plugins.RequestItemButtonsRefresh()
    end
end

function BagSlotsMixin:OnSlotFilled(slot, held)
    -- A painter can be called before Daylight UI has said what a frame holds.
    if type(held) ~= "table" then
        return
    end
    if held.itemID or held.link then
        emptySlots[slot] = nil
        return
    end
    if not emptySlots[slot] then
        emptySlots[slot] = true
        -- Also what was asked for the slot and has not been drawn: the item left meanwhile.
        CaerdonWardrobe:ClearButton(slot, "Daylight UI said the slot holds nothing")
    end
end

-- Daylight UI's auction house: the rows of its Buy page and of My auctions. The game's
-- AuctionHouseFrame is not what the player sees there, so the Auction feature's columns are
-- not either. This feature puts the item's status on the icon of each row, by the Auction
-- feature's rules.
--
-- The API has no word of these rows, so this one hooks a function of Daylight UI's own, which
-- its API allows (API.For(addon).Hook, called after the function with its arguments) and does
-- not promise to keep: DaylightUI.Win.Parts.SetItemIcon(frame, texture, quality), which every
-- item icon of its windows is set through. A row of one of its tables is told from the other
-- frames by what it carries (IsItemRow). The integration report names the hook, so an update
-- of Daylight UI that moves the function shows there and not as an error.
local AuctionMixin = {}

-- Rows seen: [row] = { holder = this addon's frame over the row's icon, key = what was last
-- asked for it }. Weak keys: the rows are Daylight UI's, and pooled.
local auctionRows = setmetatable({}, { __mode = "k" })

function AuctionMixin:GetName()
    return "DaylightUIAuction"
end

-- The auction house's own rules and its answer for a draw (its switches on the Icons page).
function AuctionMixin:GetStatusRules()
    local auction = CaerdonWardrobe:GetFeature("Auction")
    return auction and auction:GetStatusRules()
end

function AuctionMixin:GetDisplayRules(...)
    local auction = CaerdonWardrobe:GetFeature("Auction")
    return auction and auction:GetDisplayRules(...)
end

function AuctionMixin:GetDisplayInfo(...)
    local auction = CaerdonWardrobe:GetFeature("Auction")
    return auction and auction:GetDisplayInfo(...)
end

function AuctionMixin:GetTooltipData(item, locationInfo)
    local auction = CaerdonWardrobe:GetFeature("Auction")
    return auction and auction:GetTooltipData(item, locationInfo)
end

AuctionMixin.integration = {
    addon = addonName,
    hookPoints = {
        "DaylightUI.API.For", "DaylightUI.API.For(addon).Hook", "DaylightUI.Win.Parts.SetItemIcon",
        "DaylightUI.Win.Parts.SetItemIcon hooked",
    },
}

function AuctionMixin:Init()
    local API = GetAPI()
    if not API then
        return
    end
    if not self:NoteHookPoint("DaylightUI.API.For", API, "For") then
        return
    end
    local me = API.For(ADDON_NAME)
    local parts = type(DaylightUI.Win) == "table" and DaylightUI.Win.Parts or nil
    local canHook = self:NoteHookPoint("DaylightUI.API.For(addon).Hook", me, "Hook")
    canHook = self:NoteHookPoint("DaylightUI.Win.Parts.SetItemIcon", parts, "SetItemIcon") and canHook
    if not canHook then
        return
    end

    self.hooked = AttachAndNote(self, me.Hook, parts, "SetItemIcon", "DaylightUI.Win.Parts.SetItemIcon hooked", function(frame)
        self:OnItemIconSet(frame)
    end)
end

-- A row of an item in one of Daylight UI's tables: the table gives each row frame its kind,
-- its place in the list and the row's data before it fills it, and an item's row has an icon.
-- The other frames whose icon is set the same way (a vendor's tile, a letter's attachment)
-- carry none of that.
local function IsItemRow(frame)
    if type(frame) ~= "table" or frame.kind ~= "line" or type(frame.index) ~= "number" then
        return false
    end
    local data = frame.data
    return type(data) == "table" and data.kind == "line" and type(data.itemID) == "number" and
        type(frame.icon) == "table" and type(frame.icon.GetSize) == "function"
end

function AuctionMixin:OnItemIconSet(frame)
    if IsItemRow(frame) then
        self:AskRow(frame)
    end
end

function AuctionMixin:AskRow(row)
    local entry = GetEntry(auctionRows, row)

    -- What the row shows: a result of a search carries the auction house's key for it (the
    -- item, and the level and suffix of this listing), an auction of the toon's own the item.
    local data = row.data
    local itemKey = type(data.itemKey) == "table" and type(data.itemKey.itemID) == "number" and data.itemKey or nil
    local key = format("%s-%s", tostring(data.key or data.itemID), tostring(itemKey and itemKey.itemLevel or 0))
    -- A table fills a row again whenever its list is made anew. What a row was last asked for
    -- stands until it shows something else; Refresh() forgets it.
    if entry.key == key then
        return
    end
    entry.key = key

    local auction = CaerdonWardrobe:GetFeature("Auction")
    local source = data.itemID
    if itemKey and auction then
        source = auction:MakeItemForKey(itemKey)
    end
    self:Decorate(entry.holder, source, { locationKey = "row-" .. key, itemKey = itemKey },
        GetIconOptions(entry.holder, row.iconSize))
end

-- A row is filled again when its list changes, not when its page comes back on screen as it
-- was: one that is not on screen is owed its draw for then.
function AuctionMixin:Refresh()
    CaerdonWardrobeFeatureMixin:Refresh(self)

    for row, entry in pairs(auctionRows) do
        if entry.key then
            entry.key = nil
            if not CaerdonWardrobe:AskWhenOnScreen(entry.holder, self, row) then
                self:OnItemIconSet(row)
            end
        end
    end
end

function AuctionMixin:OnButtonOnScreen(row)
    local entry = auctionRows[row]
    if entry then
        entry.key = nil
        self:OnItemIconSet(row)
    end
end

-- Daylight UI's mailbox: the list of letters, the items of the letter that is picked and the
-- items of the Send page. The game's MailFrame is held aside while it shows, so the Mail
-- feature's icons are on buttons nobody sees. This feature puts them on Daylight UI's frames, by
-- the Mail feature's rules: on a letter's line the status of its first item, as on the game's
-- inbox.
--
-- The API has no word of these frames, so this one hooks functions of Daylight UI's own
-- (AttachAndNote), which the integration report names one by one:
--   * DaylightUI.Mail.Inbox.Render(pane) fills the inbox page, the list and the letter. After
--     it the list's lines and the letter's tiles are in the two panes' `pieces`, in reading
--     order, and Inbox.Picked() is the letter that is picked, with its index in the inbox.
--   * DaylightUI.Mail.Inbox.LineIds(letters) gives each letter of that fill the id its line is
--     made with, which is the one word of which letter a line stands for: the list leaves out
--     the letters its search and its filters hide. It is wrapped for what it returns.
--   * DaylightUI.Mail.Send.Render(page) fills the Send page; its tiles are in the page's
--     `pieces`, one to drop an item on last.
-- A letter's tiles are its attachments in the game's order with the empty places left out, and
-- so are the Send page's. A tile is drawn on only where its name is that attachment's: a
-- Daylight UI that fills them another way draws nothing, and nothing wrong.
--
-- Every fill comes as the window opens or while it is open, and the inbox is filled again with
-- each change to it: what a frame was last asked for stands until it shows something else, and
-- a refresh asks again by the default (a frame that is not on screen is owed its draw).
local MailMixin = {}

-- Frames drawn on, a line or a tile: [frame] = { holder = this addon's frame over its icon,
-- key = what was last asked for it }. Weak keys: the frames are Daylight UI's, and pooled.
local mailFrames = setmetatable({}, { __mode = "k" })

-- The frames each part of the window had an item on at its last fill: [part] = { [frame] = true }.
local mailShown = {}

-- Which letter a line of the list stands for, by the line's id, as of the list's last fill.
local lineLetters = {}

function MailMixin:GetName()
    return "DaylightUIMail"
end

-- The mailbox's own rules, asked of its feature so the two cannot drift apart.
function MailMixin:GetStatusRules()
    local mail = CaerdonWardrobe:GetFeature("Mail")
    return mail and mail:GetStatusRules()
end

function MailMixin:GetDisplayRules(...)
    local mail = CaerdonWardrobe:GetFeature("Mail")
    return mail and mail:GetDisplayRules(...)
end

function MailMixin:GetDisplayInfo(...)
    local mail = CaerdonWardrobe:GetFeature("Mail")
    return mail and mail:GetDisplayInfo(...)
end

-- The Mail feature's own goes by the letter the game's window has open, which is none here.
function MailMixin:GetTooltipData(item, locationInfo)
    if locationInfo.type == "send" then
        return C_TooltipInfo.GetSendMailItem(locationInfo.index)
    elseif locationInfo.type == "open" then
        return C_TooltipInfo.GetInboxItem(locationInfo.letter, locationInfo.index)
    end
    -- A letter's line: its first item.
    return C_TooltipInfo.GetInboxItem(locationInfo.letter)
end

MailMixin.integration = {
    addon = addonName,
    hookPoints = {
        "DaylightUI.API.For", "DaylightUI.API.For(addon).Hook", "DaylightUI.API.For(addon).Wrap",
        "DaylightUI.Mail.Inbox.Render", "DaylightUI.Mail.Inbox.Picked", "DaylightUI.Mail.Inbox.LineIds",
        "DaylightUI.Mail.Send.Render",
        "DaylightUI.Mail.Inbox.Render hooked", "DaylightUI.Mail.Inbox.LineIds wrapped", "DaylightUI.Mail.Send.Render hooked",
    },
}

function MailMixin:Init()
    local API = GetAPI()
    if not API then
        return
    end
    if not self:NoteHookPoint("DaylightUI.API.For", API, "For") then
        return
    end
    local me = API.For(ADDON_NAME)
    local mail = type(DaylightUI.Mail) == "table" and DaylightUI.Mail or nil
    local inbox = mail and type(mail.Inbox) == "table" and mail.Inbox or nil
    local send = mail and type(mail.Send) == "table" and mail.Send or nil
    -- Each is looked for whatever the others are, so the report names every one that is gone.
    local canHook = self:NoteHookPoint("DaylightUI.API.For(addon).Hook", me, "Hook")
    local canWrap = self:NoteHookPoint("DaylightUI.API.For(addon).Wrap", me, "Wrap")
    local hasRender = self:NoteHookPoint("DaylightUI.Mail.Inbox.Render", inbox, "Render")
    local hasPicked = self:NoteHookPoint("DaylightUI.Mail.Inbox.Picked", inbox, "Picked")
    local hasLineIds = self:NoteHookPoint("DaylightUI.Mail.Inbox.LineIds", inbox, "LineIds")
    local hasSendRender = self:NoteHookPoint("DaylightUI.Mail.Send.Render", send, "Render")
    self.inbox, self.send = inbox, send

    -- The three parts stand apart: one whose functions are gone leaves the others drawn.
    if canHook and hasRender then
        local hooked = AttachAndNote(self, me.Hook, inbox, "Render", "DaylightUI.Mail.Inbox.Render hooked", function(pane)
            self:OnInboxFilled(pane)
        end)
        self.drawsAttachments = hooked and hasPicked
        if hooked and canWrap and hasLineIds then
            self.drawsLetters = AttachAndNote(self, me.Wrap, inbox, "LineIds", "DaylightUI.Mail.Inbox.LineIds wrapped",
                function(original, ...)
                    local ids = original(...)
                    self:NoteLineIds(ids)
                    return ids
                end)
        end
    end
    if canHook and hasSendRender then
        AttachAndNote(self, me.Hook, send, "Render", "DaylightUI.Mail.Send.Render hooked", function(page)
            self:OnSendFilled(page)
        end)
    end
end

-- One fill of a part of the window. `ask(shown)` asks for each frame that holds an item, through
-- AskFrame; a frame the part had an item on before and has none on now is cleared: Daylight UI
-- hides it, or shows on it a letter with nothing in it.
function MailMixin:FillPart(part, ask)
    local before = mailShown[part]
    local shown = setmetatable({}, { __mode = "k" })
    mailShown[part] = shown
    ask(shown)
    if before then
        for frame in pairs(before) do
            if not shown[frame] then
                ReleaseEntry(mailFrames[frame])
            end
        end
    end
end

-- A copy in the toon's own mailbox, or one it is about to send, is one it holds
-- (CaerdonItemMixin:IsOwnCopy).
function MailMixin:AskFrame(shown, frame, key, link, locationInfo, options)
    local entry = GetEntry(mailFrames, frame)
    shown[frame] = true
    if entry.key == key then
        return
    end
    entry.key = key
    self:Decorate(entry.holder, CaerdonItem:CreateFromItemLink(link, { ownCopy = true }), locationInfo,
        type(options) == "function" and options(entry.holder) or options)
end

function MailMixin:NoteLineIds(ids)
    lineLetters = {}
    if type(ids) ~= "table" then
        return
    end
    for letter, id in pairs(ids) do
        if type(letter) == "table" and type(letter.index) == "number" and id ~= nil then
            lineLetters[id] = letter.index
        end
    end
end

function MailMixin:OnInboxFilled(pane)
    local inbox = self.inbox
    local list = type(pane) == "table" and pane or inbox.list
    local lines = type(list) == "table" and list.pieces or nil
    if self.drawsLetters and type(lines) == "table" then
        self:FillPart("letters", function(shown)
            self:AskLetters(shown, lines)
        end)
    end
    local letter = inbox.letter
    local tiles = type(letter) == "table" and letter.pieces or nil
    if self.drawsAttachments and type(tiles) == "table" then
        local picked = inbox.Picked()
        self:FillPart("attachments", function(shown)
            self:AskAttachments(shown, tiles, type(picked) == "table" and picked.index or nil)
        end)
    end
end

-- A letter's line shows its first item's icon, and so its first item's status.
function MailMixin:AskLetters(shown, lines)
    local madeSize = GetLineIconSize()
    for _, line in ipairs(lines) do
        local letter = IsLine(line) and line.lineSpec.id ~= nil and lineLetters[line.lineSpec.id] or nil
        local link = letter and select(15, GetInboxHeaderInfo(letter)) or nil
        if type(link) == "string" then
            self:AskFrame(shown, line, format("%d|%s", letter, link), link,
                { locationKey = "inbox-" .. letter, type = "inbox", letter = letter },
                function(holder)
                    return GetIconOptions(holder, madeSize)
                end)
        end
    end
end

-- The tiles of a page stand for the attachments it holds, in the game's order, the empty
-- places left out: `nameAt(place)` is the name and the count of what is at a place.
local function NextHeld(nameAt, place, last)
    while place < last do
        place = place + 1
        local name, count = nameAt(place)
        if name then
            return place, name, count
        end
    end
end

function MailMixin:AskAttachments(shown, tiles, letter)
    if type(letter) ~= "number" then
        return
    end
    local function NameAt(place)
        local name, _, _, count = GetInboxItem(letter, place)
        return name, count
    end
    local place, name, count = 0, nil, nil
    for _, tile in ipairs(tiles) do
        if IsItemTile(tile) then
            place, name, count = NextHeld(NameAt, place, ATTACHMENTS_MAX_RECEIVE)
            if not place then
                return
            end
            local link = tile.spec.name == name and GetInboxItemLink(letter, place) or nil
            if type(link) == "string" then
                local hasCount = (tonumber(count) or 0) > 1
                self:AskFrame(shown, tile, format("%d|%d|%s|%s", letter, place, link, tostring(hasCount)), link,
                    { locationKey = format("open-%d-%d", letter, place), type = "open", letter = letter, index = place },
                    GetItemTileOptions(tile, hasCount))
            end
        end
    end
end

function MailMixin:OnSendFilled(page)
    page = type(page) == "table" and page or self.send.page
    local tiles = type(page) == "table" and page.pieces or nil
    if type(tiles) ~= "table" then
        return
    end
    self:FillPart("send", function(shown)
        local function NameAt(place)
            local name, _, _, count = GetSendMailItem(place)
            return name, count
        end
        local place, name, count = 0, nil, nil
        for _, tile in ipairs(tiles) do
            -- The tile to drop an item on comes last, when no item is left for it, and has
            -- no item's name.
            if IsItemTile(tile) then
                place, name, count = NextHeld(NameAt, place, ATTACHMENTS_MAX_SEND)
                if not place then
                    return
                end
                local link = tile.spec.name == name and GetSendMailItemLink(place) or nil
                if type(link) == "string" then
                    local hasCount = (tonumber(count) or 0) > 1
                    self:AskFrame(shown, tile, format("%d|%s|%s", place, link, tostring(hasCount)), link,
                        { locationKey = "send-" .. place, type = "send", index = place }, GetItemTileOptions(tile, hasCount))
                end
            end
        end
    end)
end

-- Daylight UI's quest rewards: the items of a quest's page in its NPC window (what the quest
-- asks for, the rewards to choose from and the ones given) and the rewards of a quest's page in
-- its quest journal. The game's QuestFrame is held aside while the NPC window shows, and the
-- journal is a window of Daylight UI's own, so the QuestLog feature's icons are not seen there.
-- This feature puts them on Daylight UI's tiles, by the QuestLog feature's rules.
--
-- The API has no word of these tiles. Their icons are set through the function the auction
-- rows' are (DaylightUI.Win.Parts.SetItemIcon, hooked here a second time), and a tile says what
-- it holds itself: its spec has the function Daylight UI calls for a Shift-click on the tile
-- (`link`), which answers with the item's link, or a spell's or a currency's, which are left
-- alone. A vendor's tile has one too, and so has a material of a recipe: those two are told by
-- what else their spec carries and are not this feature's (the vendor's tiles are handed over by
-- the API, and this addon draws nothing on a recipe's materials in the game's window either).
-- Every other tile that names a link is taken for a quest's item, which in 2.4.0 is these two
-- windows.
--
-- A tile that is not on show keeps what was asked for it, as a row of the auction house does:
-- its icon is set again when it shows another item, and a refresh asks again by the default.
-- The tooltip is the link's: which quest and which place of it a tile stands for is not said.
local QuestsMixin = {}

-- Tiles drawn on: [tile] = { holder, key }. Weak keys: the tiles are Daylight UI's, and pooled.
local questTiles = setmetatable({}, { __mode = "k" })

function QuestsMixin:GetName()
    return "DaylightUIQuests"
end

-- The quest windows' own rules, asked of their feature so the two cannot drift apart.
function QuestsMixin:GetStatusRules()
    local quests = CaerdonWardrobe:GetFeature("QuestLog")
    return quests and quests:GetStatusRules()
end

function QuestsMixin:GetDisplayRules(...)
    local quests = CaerdonWardrobe:GetFeature("QuestLog")
    return quests and quests:GetDisplayRules(...)
end

function QuestsMixin:GetDisplayInfo(...)
    local quests = CaerdonWardrobe:GetFeature("QuestLog")
    return quests and quests:GetDisplayInfo(...)
end

QuestsMixin.integration = {
    addon = addonName,
    hookPoints = {
        "DaylightUI.API.For", "DaylightUI.API.For(addon).Hook", "DaylightUI.Win.Parts.SetItemIcon",
        "DaylightUI.Win.Parts.SetItemIcon hooked",
    },
}

function QuestsMixin:Init()
    local API = GetAPI()
    if not API then
        return
    end
    if not self:NoteHookPoint("DaylightUI.API.For", API, "For") then
        return
    end
    local me = API.For(ADDON_NAME)
    local parts = type(DaylightUI.Win) == "table" and DaylightUI.Win.Parts or nil
    local canHook = self:NoteHookPoint("DaylightUI.API.For(addon).Hook", me, "Hook")
    canHook = self:NoteHookPoint("DaylightUI.Win.Parts.SetItemIcon", parts, "SetItemIcon") and canHook
    if not canHook then
        return
    end
    AttachAndNote(self, me.Hook, parts, "SetItemIcon", "DaylightUI.Win.Parts.SetItemIcon hooked", function(frame)
        self:OnItemIconSet(frame)
    end)
end

-- The link of the item a tile holds, where the tile is a quest's (above) and holds an item.
local function GetRewardLink(tile)
    if not IsItemTile(tile) then
        return nil
    end
    local spec = tile.spec
    if type(spec.link) ~= "function" or spec.shopItem ~= nil or spec.mat ~= nil then
        return nil
    end
    local link = spec.link()
    if type(link) == "string" and link:find("|Hitem:", 1, true) then
        return link
    end
    return nil
end

function QuestsMixin:OnItemIconSet(tile)
    local link = GetRewardLink(tile)
    if not link then
        -- A tile that held a quest's item and holds a spell, a currency or a sample now.
        ReleaseEntry(questTiles[tile])
        return
    end
    local entry = GetEntry(questTiles, tile)
    local hasCount = (tonumber(tile.spec.count) or 0) > 1
    local key = format("%s|%s", link, tostring(hasCount))
    -- A page is filled again whenever its quest's data comes in. What a tile was last asked
    -- for stands until it holds something else.
    if entry.key == key then
        return
    end
    entry.key = key
    self:Decorate(entry.holder, link, { locationKey = "reward-" .. link, link = link }, GetItemTileOptions(tile, hasCount))
end

-- Daylight UI's loot roll cards, which stand in for the game's roll popups (GroupLootFrame1-4,
-- which the GroupLoot feature draws on). This feature puts the item's status on a card's icon,
-- by the GroupLoot feature's rules, through the API alone:
--   * A painter of "rollcard" (API.For(addon).Paint) is called with the card, its parts (`icon`,
--     a texture) and what it shows (`rollID`, `link`, `done`, `sample`) for a new roll on a card
--     and at each pick, roll and winner.
--   * API.On("FrameRemoved", ...) comes when a card's roll leaves. Cards are reused.
--   * API.Attach(card) is the frame the overlay is made on, laid over the card's icon.
-- A sample card of the options page and a roll rebuilt from the loot history are no rolls of
-- the game's: their tooltip is the link's.
local RollsMixin = {}

-- What each card was last asked for. Weak keys: the cards are Daylight UI's.
local rollCards = setmetatable({}, { __mode = "k" })

function RollsMixin:GetName()
    return "DaylightUIRolls"
end

function RollsMixin:GetStatusRules()
    local rolls = CaerdonWardrobe:GetFeature("GroupLoot")
    return rolls and rolls:GetStatusRules()
end

function RollsMixin:GetDisplayRules(...)
    local rolls = CaerdonWardrobe:GetFeature("GroupLoot")
    return rolls and rolls:GetDisplayRules(...)
end

function RollsMixin:GetDisplayInfo(...)
    local rolls = CaerdonWardrobe:GetFeature("GroupLoot")
    return rolls and rolls:GetDisplayInfo(...)
end

function RollsMixin:GetTooltipData(item, locationInfo)
    if locationInfo.isGameRoll then
        return C_TooltipInfo.GetLootRollItem(locationInfo.index)
    end
    return nil
end

RollsMixin.integration = {
    addon = addonName,
    hookPoints = {
        "DaylightUI.API.For", "DaylightUI.API.For(addon).Paint", "DaylightUI.API.On", "DaylightUI.API.Attach",
    },
}

function RollsMixin:Init()
    local API = GetAPI()
    if not API then
        return
    end
    local found = self:NoteHookPoint("DaylightUI.API.For", API, "For")
    found = self:NoteHookPoint("DaylightUI.API.On", API, "On") and found
    found = self:NoteHookPoint("DaylightUI.API.Attach", API, "Attach") and found
    if not found then
        return
    end
    local me = API.For(ADDON_NAME)
    if not self:NoteHookPoint("DaylightUI.API.For(addon).Paint", me, "Paint") then
        return
    end
    self.API = API
    -- Daylight UI runs a painter and a listener contained, under this addon's name.
    me.Paint("rollcard", function(card, parts, shown)
        self:OnCardPainted(card, parts, shown)
    end)
    API.On("FrameRemoved", function(kind, card)
        if kind == "rollcard" then
            self:ReleaseCard(card)
        end
    end, ADDON_NAME)
end

function RollsMixin:OnCardPainted(card, parts, shown)
    local holder = self.API.Attach(card)
    if not holder then
        return
    end
    local icon = type(parts) == "table" and parts.icon or nil
    local link = type(shown) == "table" and shown.link or nil
    if type(link) ~= "string" or type(icon) ~= "table" then
        -- A painter can be called before Daylight UI has said what a card shows.
        if rollCards[card] then
            rollCards[card] = nil
            CaerdonWardrobe:ClearButton(holder)
        end
        return
    end

    -- The game's own rolls have an id above zero; the tooltip of a roll that is over is the
    -- link's, as Daylight UI's own is.
    local rollID = shown.rollID
    local isGameRoll = type(rollID) == "number" and rollID > 0 and not shown.done and not shown.sample
    local key = format("%s|%s|%s", tostring(rollID), link, tostring(isGameRoll))
    if rollCards[card] == key then
        return
    end
    rollCards[card] = key
    -- The icon's own button owns the tooltip; the Debug Frame finds what was asked of it
    -- through this.
    CaerdonWardrobe:NoteButtonOn(type(icon.GetParent) == "function" and icon:GetParent() or card, holder)

    self:Decorate(holder, link, {
        locationKey = "roll-" .. tostring(rollID),
        index = rollID,
        link = link,
        isGameRoll = isGameRoll,
    }, {
        relativeFrame = icon,
        statusProminentSize = CaerdonWardrobe:GetSlotStatusSize(icon:GetSize()),
        slotScale = CaerdonWardrobe:GetSlotScale(icon:GetSize()),
    })
end

function RollsMixin:ReleaseCard(card)
    if not rollCards[card] then
        return
    end
    rollCards[card] = nil
    local holder = self.API.Attach(card)
    if holder then
        CaerdonWardrobe:ClearButton(holder)
        -- Without the key, a request still on its way for this card is dropped instead of
        -- drawn on the next roll's.
        CaerdonWardrobe:ClearButtonState(holder)
    end
end

-- Daylight UI's profession window: the list of recipes and the recipe that is picked, on the
-- icon of what it makes. The game's ProfessionsFrame is not what the player sees there, so the
-- TradeSkill feature's icons are not either. This feature puts them on Daylight UI's frames, by
-- the TradeSkill feature's rules.
--   * The list's lines have a frame kind in the API ("craftrow"): API.On("FrameStyled", ...)
--     comes with the line and the recipe's ID for each line on show after every fill of the
--     list, API.On("FrameRemoved", ...) when a line is hidden. API.Attach(line) is the frame
--     the overlay is made on, laid over the line's icon (API.GetPart(line, "icon")).
--   * The recipe that is picked has none, so the function that fills its pane is hooked
--     (DaylightUI.Craft.Recipe.Fill(pane, recipe), AttachAndNote). After it the pane's first
--     piece is the line of what the recipe makes: its spec carries the recipe and the function
--     Daylight UI calls for a Shift-click on it (`link`), which answers with the item's link
--     and with nothing for an enchantment.
-- What a recipe of the list makes is the client's word for the profession that is open (the
-- recipe info's hyperlink), as in the game's own window.
local CraftMixin = {}

-- What each line of the list was last asked for (weak keys: the lines are Daylight UI's), and
-- the picked recipe's line: [line] = { holder, key }.
local craftRows = setmetatable({}, { __mode = "k" })
local craftResults = setmetatable({}, { __mode = "k" })

function CraftMixin:GetName()
    return "DaylightUICraft"
end

-- The profession window's own rules, asked of its feature so the two cannot drift apart.
function CraftMixin:GetStatusRules()
    local tradeSkill = CaerdonWardrobe:GetFeature("TradeSkill")
    return tradeSkill and tradeSkill:GetStatusRules()
end

function CraftMixin:GetDisplayRules(...)
    local tradeSkill = CaerdonWardrobe:GetFeature("TradeSkill")
    return tradeSkill and tradeSkill:GetDisplayRules(...)
end

function CraftMixin:GetDisplayInfo(...)
    local tradeSkill = CaerdonWardrobe:GetFeature("TradeSkill")
    return tradeSkill and tradeSkill:GetDisplayInfo(...)
end

CraftMixin.integration = {
    addon = addonName,
    hookPoints = {
        "DaylightUI.API.On", "DaylightUI.API.Attach", "DaylightUI.API.GetPart",
        "DaylightUI.API.For", "DaylightUI.API.For(addon).Hook", "DaylightUI.Craft.Recipe.Fill",
        "DaylightUI.Craft.Recipe.Fill hooked",
    },
}

function CraftMixin:Init()
    local API = GetAPI()
    if not API then
        return
    end
    -- The list and the picked recipe stand apart: each is looked for whatever the other is.
    local canList = self:NoteHookPoint("DaylightUI.API.On", API, "On")
    canList = self:NoteHookPoint("DaylightUI.API.Attach", API, "Attach") and canList
    canList = self:NoteHookPoint("DaylightUI.API.GetPart", API, "GetPart") and canList
    local me = self:NoteHookPoint("DaylightUI.API.For", API, "For") and API.For(ADDON_NAME) or nil
    local craft = type(DaylightUI.Craft) == "table" and DaylightUI.Craft or nil
    local recipe = craft and type(craft.Recipe) == "table" and craft.Recipe or nil
    local canHook = self:NoteHookPoint("DaylightUI.API.For(addon).Hook", me, "Hook")
    canHook = self:NoteHookPoint("DaylightUI.Craft.Recipe.Fill", recipe, "Fill") and canHook
    self.API, self.recipe = API, recipe

    if canList then
        -- Daylight UI runs a listener contained and names its owner where it raises an error.
        API.On("FrameStyled", function(kind, line, recipeID)
            if kind == "craftrow" then
                self:UpdateRow(line, recipeID)
            end
        end, ADDON_NAME)
        API.On("FrameRemoved", function(kind, line)
            if kind == "craftrow" then
                self:ReleaseRow(line)
            end
        end, ADDON_NAME)
    end
    if canHook then
        AttachAndNote(self, me.Hook, recipe, "Fill", "DaylightUI.Craft.Recipe.Fill hooked", function(pane, picked)
            self:OnRecipeFilled(pane, picked)
        end)
    end
end

function CraftMixin:UpdateRow(line, recipeID)
    local API = self.API
    local holder = API.Attach(line)
    if not holder then
        return
    end
    local icon = API.GetPart(line, "icon")
    local recipeInfo = type(recipeID) == "number" and C_TradeSkillUI.GetRecipeInfo(recipeID) or nil
    local link = recipeInfo and recipeInfo.hyperlink
    if not icon or type(link) ~= "string" or link == "" then
        -- A recipe the client names nothing made for.
        if craftRows[line] then
            craftRows[line] = nil
            CaerdonWardrobe:ClearButton(holder)
        end
        return
    end

    -- The list is filled again at every skill-up and whenever the bags change. What a line
    -- was last asked for stands until it shows another recipe.
    local key = format("%d|%s", recipeID, link)
    if craftRows[line] == key then
        return
    end
    craftRows[line] = key
    -- The line owns the tooltip; the Debug Frame finds what was asked of it through this.
    CaerdonWardrobe:NoteButtonOn(line, holder)

    local options = GetIconOptions(icon, GetLineIconSize())
    options.relativeFrame = icon
    self:Decorate(holder, link, { locationKey = format("recipe%d", recipeID), selectedRecipeID = recipeID }, options)
end

function CraftMixin:ReleaseRow(line)
    if not craftRows[line] then
        return
    end
    craftRows[line] = nil
    local holder = self.API.Attach(line)
    if holder then
        CaerdonWardrobe:ClearButton(holder)
        -- Without the key, a request still on its way for this line is dropped instead of
        -- drawn on a pooled one.
        CaerdonWardrobe:ClearButtonState(holder)
    end
end

function CraftMixin:OnRecipeFilled(pane, picked)
    pane = type(pane) == "table" and pane or self.recipe.pane
    local pieces = type(pane) == "table" and pane.pieces or nil
    local line = type(pieces) == "table" and pieces[1] or nil
    local link
    if IsLine(line) and type(picked) == "table" and line.lineSpec.recipe == picked and type(line.lineSpec.link) == "function" then
        link = line.lineSpec.link()
    end
    if type(link) ~= "string" or type(picked.id) ~= "number" then
        -- No recipe picked, or one that makes no item: the pane has one such line, pooled.
        for _, entry in pairs(craftResults) do
            ReleaseEntry(entry)
        end
        return
    end
    local entry = GetEntry(craftResults, line)
    local key = format("%d|%s", picked.id, link)
    if entry.key == key then
        return
    end
    entry.key = key
    self:Decorate(entry.holder, link, {
        locationKey = format("selectedrecipe%d", picked.id),
        selectedRecipeID = picked.id,
        isSelectedRecipe = true,
    }, GetIconOptions(entry.holder, GetLineIconSize()))
end

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
    if C_AddOns.IsAddOnLoaded(addonName) then
        CaerdonWardrobe:RegisterFeature(VendorMixin)
        CaerdonWardrobe:RegisterFeature(BagSlotsMixin)
        CaerdonWardrobe:RegisterFeature(AuctionMixin)
        CaerdonWardrobe:RegisterFeature(MailMixin)
        CaerdonWardrobe:RegisterFeature(QuestsMixin)
        CaerdonWardrobe:RegisterFeature(RollsMixin)
        CaerdonWardrobe:RegisterFeature(CraftMixin)
    end
end
