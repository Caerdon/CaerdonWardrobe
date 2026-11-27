local ADDON_NAME, namespace = ...

-- GudaBags' bags and bank: the status icon, binding text and level gain on its item buttons.
--
-- GudaBags has a public API for this (GudaBags.API, its Core/PublicAPI.lua): a function
-- registered with OnItemButtonUpdate is called with (button, bagID, slot) after every setup of a
-- button with an item of the toon's own in a bag or bank slot. It says nothing of any other
-- setup: an emptied slot, its "Empty" button, another toon's bags, its guild bank, a button it
-- takes back. Its buttons are pooled and set up again in place, so one that showed an item
-- comes to show none of those with no word to this feature.
--
-- Every setup of a button sets its picture through the game's SetItemButtonTexture, once, and
-- nothing else of GudaBags' does (3.0.9, UI/ItemButton.lua: SetItem, SetEmpty, the pool's
-- reset). For an item of the toon's own the announcement follows in the same call. So a button
-- of this feature's whose picture was set, with no announcement by the next frame, shows
-- nothing of this feature's any more and is cleared. Its count will not do for this: GudaBags
-- sets a stack's count alone where only the count changed.

local addonName = "GudaBags"
local GudaBagsMixin = {}

function GudaBagsMixin:GetName()
    return addonName
end

-- Where this feature attaches to GudaBags (the integration report; see FeatureMixin.lua). The
-- second is no function of GudaBags' but what it does on the way to an announcement: a version
-- that sets a button's picture another way would leave an emptied slot its icon, and reads as
-- a missing hook point here.
local ANNOUNCED = "GudaBags.API.OnItemButtonUpdate"
local PICTURE_FIRST = "SetItemButtonTexture before a button is announced"

-- GudaBags' own marks that say what one of this addon's says, by the field of the button that
-- holds each (3.0.9, UI/ItemButton.lua, CreateButton). One mark for one thing: on a slot this
-- feature draws, GudaBags' is not seen while this addon shows its own (OnButtonDrawn).
--   upgradeArrow        Pawn's arrow (or SimpleItemLevel's), top left; GudaBags has no switch
--                       for it, and this addon's arrow is not always Pawn's verdict
--   questIcon,          the "?" of a quest's item and the "!" of one that starts a quest, top
--   questStarterIcon    left; no switch either. Its gold border for them stays
--   boeText             "BoE" or "BoA", bottom left (its BoE Label and BoA Label)
--   equipSetIcon        an equipment set's mark, bottom left (its Equipment Sets), which is
--                       also a category's mark where the piece is in no set
-- They are GudaBags' own and its API says nothing of them, so each is an optional hook point:
-- one that is gone leaves both marks on the slot and reads as "not there" in the report.
local OWN_MARKS = { "upgradeArrow", "questIcon", "questStarterIcon", "boeText", "equipSetIcon" }
-- Parts that go with a mark and are not looked for by themselves.
local MARK_COMPANIONS = { equipSetIcon = "equipSetIconShadow" }

local OWN_MARK_POINTS = {}
for index, field in ipairs(OWN_MARKS) do
    OWN_MARK_POINTS[index] = "button." .. field
end

GudaBagsMixin.integration = {
    addon = addonName,
    hookPoints = { ANNOUNCED, PICTURE_FIRST },
    optionalHookPoints = OWN_MARK_POINTS,
}

-- The buttons this feature has asked for and not cleared since. Weak keys: they are GudaBags'.
local decorated = setmetatable({}, { __mode = "k" })
-- Of those, the ones whose picture was set and that have not been announced since.
local unannounced = {}
-- The button whose picture was set last, of any window's: what tells that GudaBags still sets
-- a button's picture before it announces it.
local lastPictureSet = nil

-- Set only while a button waits for its announcement.
local watcher = CreateFrame("Frame")
local watching = false

local function ReportError(problem)
    geterrorhandler()(problem)
    return problem
end

-- One of GudaBags' own marks, seen or not. GudaBags shows and hides its marks itself, at a
-- button's setup and for the arrow whenever Pawn has news, so the mark is left shown or hidden
-- as GudaBags has it and made invisible: nothing of GudaBags' sets a mark's alpha.
local function SetOwnMarkSeen(button, field, seen)
    local alpha = seen and 1 or 0
    local mark = button[field]
    if type(mark) == "table" and type(mark.SetAlpha) == "function" then
        mark:SetAlpha(alpha)
    end
    local companion = MARK_COMPANIONS[field] and button[MARK_COMPANIONS[field]]
    if type(companion) == "table" and type(companion.SetAlpha) == "function" then
        companion:SetAlpha(alpha)
    end
end

-- A button that is no longer this feature's has every mark of GudaBags' as GudaBags shows it:
-- the buttons are pooled, and the next one to use it may be its guild bank's.
local function ShowOwnMarks(button)
    for _, field in ipairs(OWN_MARKS) do
        SetOwnMarkSeen(button, field, true)
    end
end

local function ClearUnannounced()
    watcher:SetScript("OnUpdate", nil)
    watching = false
    for button in pairs(unannounced) do
        unannounced[button] = nil
        decorated[button] = nil
        xpcall(ShowOwnMarks, ReportError, button)
        -- One failure stays alone: the buttons after it are still cleared.
        xpcall(CaerdonWardrobe.ClearButton, ReportError, CaerdonWardrobe, button,
            "GudaBags set it up with no item of this toon's own")
    end
end

-- Runs for every item button of every window, so it does no more than this.
local function OnItemButtonTexture(button)
    lastPictureSet = button
    if button and decorated[button] then
        unannounced[button] = true
        if not watching then
            watching = true
            watcher:SetScript("OnUpdate", ClearUnannounced)
        end
    end
end

-- A bag slot of GudaBags' as a default bag slot: the icon at a slot's proportion and the texts
-- with it, so the player's layout holds at every icon size GudaBags offers (22 to 64). No upper
-- limit: the slot is as big as the player made it. The bank scrolls and cuts off what hangs
-- over its edge, so the icon moves inside where there is no room.
local function GetSlotOptions(button)
    local width, height = button:GetSize()
    return {
        statusProminentSize = CaerdonWardrobe:GetSlotStatusSize(width, height, true),
        slotScale = CaerdonWardrobe:GetSlotScale(width, height),
        keepInsideWhenClipped = true,
    }
end

function GudaBagsMixin:OnItemButtonUpdate(button, bag, slot)
    -- Noted at the first announcement and whenever it comes out the other way, not at each one.
    local pictureFirst = lastPictureSet == button
    if self.pictureFirst ~= pictureFirst then
        self.pictureFirst = pictureFirst
        if pictureFirst then
            self:NoteHookCalled(PICTURE_FIRST)
        else
            self:NoteHookPoint(PICTURE_FIRST) -- nothing to look for: noted as missing
        end
    end

    if type(button) ~= "table" then
        return
    end
    unannounced[button] = nil
    if type(bag) ~= "number" or type(slot) ~= "number" then
        return
    end

    if not self.ownMarksNoted then
        self.ownMarksNoted = true
        for index, field in ipairs(OWN_MARKS) do
            self:NoteHookPoint(OWN_MARK_POINTS[index], button[field], "SetAlpha")
        end
    end

    decorated[button] = true
    -- A slot the client has no item in (a place that is no bag of the client's) clears the
    -- button: the core does that for an item that is not there.
    local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
    local locationInfo, options = { bag = bag, slot = slot }, GetSlotOptions(button)
    -- The two that go by a setting alone are put right before the draw, which comes a frame
    -- later at the earliest: GudaBags has just shown its arrow.
    self:YieldMarksBySetting(button, item, locationInfo, options)
    CaerdonWardrobe:UpdateButton(button, item, self, locationInfo, options)
end

-- The arrow and the quest marks give way wherever this addon's own are switched on for the
-- slot, whatever is on it: where this addon says a piece is no upgrade, or a quest's item is
-- spent, GudaBags' mark would say otherwise beside it. The core's own answer for this window is
-- asked, so a rule it gains for the bags counts here too.
function GudaBagsMixin:YieldMarksBySetting(button, item, locationInfo, options)
    local shown = self:GetDisplayInfoInternal(button, item, self, locationInfo, options)
    SetOwnMarkSeen(button, "upgradeArrow", not shown.upgradeIcon.shouldShow)
    local questMarksSeen = not shown.questIcon.shouldShow
    SetOwnMarkSeen(button, "questIcon", questMarksSeen)
    SetOwnMarkSeen(button, "questStarterIcon", questMarksSeen)
end

local function IsInGearSet(item)
    local sets = CaerdonEquipment and CaerdonEquipment.GetEquipmentSetsOf and CaerdonEquipment:GetEquipmentSetsOf(item)
    return type(sets) == "table" and #sets > 0
end

-- Called by the core after every draw of one of this feature's buttons.
--
-- The bind label and the set's mark give way by what the draw left on the slot. This addon's
-- text is the binding ("BoE", "BoA", "WuE") or a gear set's name, by its own settings for
-- each, so GudaBags' label is not seen under a text of this addon's and is seen where there
-- is none: a binding this addon is set not to name is still named by GudaBags. Its set mark
-- is not seen on a piece this addon has shown the gear set of, by name or by icon.
function GudaBagsMixin:OnButtonDrawn(button, item, locationInfo, options)
    self:YieldMarksBySetting(button, item, locationInfo, options)

    local hasIcon, hasText = CaerdonWardrobe:GetDrawnParts(button)
    SetOwnMarkSeen(button, "boeText", not hasText)
    local binding = CaerdonWardrobeConfig.Binding
    local setShown = IsInGearSet(item) and ((binding.ShowGearSets and hasText) or (binding.ShowGearSetsAsIcon and hasIcon))
    SetOwnMarkSeen(button, "equipSetIcon", not setShown)
end

-- For the layout editor's callout, which is where a player with GudaBags reads what this addon
-- does differently in its window.
function GudaBagsMixin:GetLayoutNote()
    return "GudaBags: where Caerdon Wardrobe shows its own upgrade arrow, quest icon, binding text or gear " ..
        "set on a slot, GudaBags' mark for the same is hidden there (its upgrade arrow, its quest marks, " ..
        "its BoE and BoA labels, its equipment set mark). Switch one of those off in Caerdon Wardrobe's " ..
        "settings and GudaBags' own shows again."
end

function GudaBagsMixin:Init()
    local API = type(GudaBags) == "table" and GudaBags.API or nil
    if not self:NoteHookPoint(ANNOUNCED, API, "OnItemButtonUpdate") then
        return
    end

    hooksecurefunc("SetItemButtonTexture", OnItemButtonTexture)

    -- GudaBags runs a registered function contained and prints what it raised to the chat
    -- window. An error of this feature's goes to the error handler like any other.
    API.OnItemButtonUpdate(function(button, bag, slot)
        xpcall(self.OnItemButtonUpdate, ReportError, self, button, bag, slot)
    end)
end

function GudaBagsMixin:GetTooltipData(item, locationInfo)
    return C_TooltipInfo.GetBagItem(locationInfo.bag, locationInfo.slot)
end

-- No Refresh() of its own: GudaBags announces a button whenever it comes to show another item,
-- and a button that shows none is cleared above, so what the core remembers of each button is
-- what is on it and the default asks for that again. GudaBags does not set its buttons up again
-- when its window opens as it was; a button that is not on screen is owed its draw by the
-- default.

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
    if C_AddOns.IsAddOnLoaded(addonName) then
        Version = C_AddOns.GetAddOnMetadata(addonName, "Version")
        CaerdonWardrobe:RegisterFeature(GudaBagsMixin)
        isActive = true
    end
end

-- WagoAnalytics:Switch(addonName, isActive)
