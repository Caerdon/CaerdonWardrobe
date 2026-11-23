local addonName = "DialogueUI"
local DialogueUIMixin = {}

-- Dialogue UI shows a quest at an NPC (offer, progress, turn-in) in its own window in place of
-- Blizzard's quest frame, so the QuestLog feature has no button to draw on there. This feature
-- decorates Dialogue UI's reward buttons instead. The quest log and the map's quest details are
-- still Blizzard's and stay with the QuestLog feature.

function DialogueUIMixin:GetName()
    return addonName
end

-- Item buttons that show a reward right now: [button] = what was last sent to the core for it
-- (the reward's link, plus whether Dialogue UI had its own upgrade arrow on the button), true
-- while the client has no link for it yet, or SWITCHED_OFF while the player's setting keeps this
-- addon off Dialogue UI's rewards. Dialogue UI pools the buttons (weak keys: they are its
-- own) and releases every one of them before it lays a dialog out again.
local trackedButtons = setmetatable({}, { __mode = "k" })
local SWITCHED_OFF = "off"

-- The player's choice (Display page): nothing of this addon's on Dialogue UI's rewards.
local function IsEnabled()
    local icon = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon
    return not (icon and icon.ShowOnDialogueUI == false)
end

-- Dialogue UI puts its own upgrade arrow on a reward it rates as one (its "Evaluate Item Rewards"
-- option; the verdict is Pawn's where Pawn is installed) and flags the button. On those buttons
-- this addon's arrow and level gain would say the same thing a second time, so they are left out;
-- any other icon stays.
local function HasOwnUpgradeArrow(button)
    return button ~= nil and type(button.DoesButtonHaveMarker) == "function" and
        button:DoesButtonHaveMarker("upgrade") == true
end

-- Dialogue UI marks a reward the toon cannot use with a red "!" in the icon's top right corner:
-- part of its ItemOverlay texture, always on, about 15 px across. Its center, measured in from
-- the top right corner of the 36 px frame the item's border is drawn in.
local ALERT_INSET_X = 6.8
local ALERT_INSET_Y = 7

-- The overlay sits on that frame, Dialogue UI's counterpart to a bag slot, and the layout is
-- fixed, because Dialogue UI has a marker of its own for three of the icon's corners (bottom left
-- its upgrade arrow, top left its highest sell price coin, top right the "!"). This addon's icon
-- goes exactly over the "!": it only shows there for an item that still has something to learn,
-- which says more than "cannot use", and two markers side by side read as a disagreement. At the
-- default slot's size the icon's ring covers the "!". The text keeps the bottom and the level
-- gain the bottom right, where Dialogue UI writes an amount (never on a piece of gear).
local function GetRewardOptions(button)
    local slot = button.AreaDefinitionItemBorder or button.Icon
    return {
        relativeFrame = slot,
        statusProminentSize = slot and CaerdonWardrobe:GetSlotStatusSize(slot:GetSize()) or nil,
        fixedLayout = true,
        overrideStatusPosition = "TOPRIGHT",
        statusOffsetX = ALERT_INSET_X,
        statusOffsetY = ALERT_INSET_Y,
        overrideBindingPosition = "BOTTOM",
        -- Light parchment shows through beside the icon, and with it the square cut of its shadow.
        roundStatusIcon = true,
        hasCount = (tonumber(button.rewardAmount) or 0) > 1
    }
end

function DialogueUIMixin:GetLayoutNote()
    if not IsEnabled() then
        return nil
    end
    return "Dialogue UI: Position, Size and Nudge do not apply on its quest rewards. The icon sits in the " ..
        "top right corner there, over Dialogue UI's own mark for an item the character cannot use, the " ..
        "text at the bottom and the level gain in the bottom right."
end

function DialogueUIMixin:ClearRewardButton(button)
    button.caerdonDebugItemLink = nil
    CaerdonWardrobe:ClearButton(button)
    -- Without the key, a request still on its way for this button is dropped instead of drawn.
    CaerdonWardrobe:ClearButtonState(button)
end

function DialogueUIMixin:ReleaseRewardButton(button)
    if trackedButtons[button] then
        trackedButtons[button] = nil
        self:ClearRewardButton(button)
    end
end

-- button.objectType / type / index are Dialogue UI's own: what the button shows ("item",
-- "currency", "spell", ...), the quest item type ("reward", "choice", "required") and its index.
function DialogueUIMixin:UpdateRewardButton(button)
    local rewardType, index = button.type, button.index

    -- Rewards only: a required item is handed in, not received.
    if button.objectType ~= "item" or not index or (rewardType ~= "reward" and rewardType ~= "choice") then
        self:ReleaseRewardButton(button)
        return
    end

    if not IsEnabled() then
        -- Still tracked, so Refresh draws it once the setting is switched back on. Dialogue UI
        -- sets a button again many times a second; clearing it once is enough.
        if trackedButtons[button] ~= SWITCHED_OFF then
            trackedButtons[button] = SWITCHED_OFF
            self:ClearRewardButton(button)
        end
        return
    end

    local itemLink = GetQuestItemLink(rewardType, index)
    if not itemLink then
        -- Not sent by the server yet. Dialogue UI sets the button again when it arrives, and
        -- QUEST_ITEM_UPDATE comes back here as well.
        trackedButtons[button] = true
        self:ClearRewardButton(button)
        return
    end

    -- Dialogue UI sets a button again, many times a second, while it waits for the item's name.
    -- Its arrow can arrive a moment after the item, which is a reason to draw again.
    local drawn = itemLink .. (HasOwnUpgradeArrow(button) and "#arrow" or "")
    if trackedButtons[button] == drawn then
        return
    end
    trackedButtons[button] = drawn

    -- The debug keybind reads the link from the frame under the mouse; Dialogue UI's own tooltip
    -- is not one it knows.
    button.caerdonDebugItemLink = itemLink

    local questID = GetQuestID() or 0
    local locationInfo = {
        locationKey = format("%s-quest%d-index%d", rewardType, questID, index),
        questID = questID,
        index = index,
        type = rewardType
    }
    local options = GetRewardOptions(button)

    -- A button that is released or set to something else while its item loads is cleared or
    -- asked for anew above, each time what is tracked for it changes, so the answer that comes
    -- late is not drawn (Decorate).
    self:Decorate(button, itemLink, locationInfo, options)
end

-- Dialogue UI has put its arrow on a button, either inside SetItem (the button is not tracked
-- yet and SetItem's own hook follows) or a moment later.
function DialogueUIMixin:OnUpgradeArrowShown(button)
    if trackedButtons[button] then
        self:UpdateRewardButton(button)
    end
end

-- Where this feature attaches to Dialogue UI (the integration report; see FeatureMixin.lua).
DialogueUIMixin.integration = {
    addon = addonName,
    hookPoints = { "DUIDialogItemButtonMixin.SetItem", "DUIDialogItemButtonMixin.OnRelease" },
    optionalHookPoints = { "DUIDialogItemButtonMixin.ShowUpgradeIcon" },
}

function DialogueUIMixin:Init()
    local buttonMixin = DUIDialogItemButtonMixin
    self:NoteHookPoint("DUIDialogItemButtonMixin.SetItem", buttonMixin, "SetItem")
    self:NoteHookPoint("DUIDialogItemButtonMixin.OnRelease", buttonMixin, "OnRelease")
    self:NoteHookPoint("DUIDialogItemButtonMixin.ShowUpgradeIcon", buttonMixin, "ShowUpgradeIcon")
    if type(buttonMixin) ~= "table" or type(buttonMixin.SetItem) ~= "function" or
        type(buttonMixin.OnRelease) ~= "function" then
        return
    end

    -- A problem on this side must not interrupt Dialogue UI's layout.
    local function Guarded(method)
        return function(button)
            local ok, failure = pcall(method, self, button)
            if not ok then
                geterrorhandler()(failure)
            end
        end
    end

    -- The button template copies the mixin's functions when a button is created, and Dialogue UI
    -- creates its buttons for the first quest it shows, so hooking the table reaches all of them.
    -- Every item draw goes through SetItem; OnRelease returns a button to the pool.
    hooksecurefunc(buttonMixin, "SetItem", Guarded(self.UpdateRewardButton))
    hooksecurefunc(buttonMixin, "OnRelease", Guarded(self.ReleaseRewardButton))
    if type(buttonMixin.ShowUpgradeIcon) == "function" then
        hooksecurefunc(buttonMixin, "ShowUpgradeIcon", Guarded(self.OnUpgradeArrowShown))
    end

    return { "QUEST_ITEM_UPDATE" }
end

function DialogueUIMixin:QUEST_ITEM_UPDATE()
    self:Refresh()
end

function DialogueUIMixin:GetTooltipData(item, locationInfo)
    -- Only while the dialog still shows the quest the button was drawn for.
    local questID = GetQuestID()
    if not questID or questID == 0 or questID ~= locationInfo.questID then
        return
    end

    return C_TooltipInfo.GetQuestItem(locationInfo.type, locationInfo.index, true)
end

-- The same icons as on Blizzard's quest rewards, under the same settings, minus the upgrade arrow
-- and the level gain where Dialogue UI shows its own arrow.
function DialogueUIMixin:GetDisplayInfo(button, ...)
    local questLogFeature = CaerdonWardrobe:GetFeature("QuestLog")
    local displayInfo = questLogFeature and questLogFeature:GetDisplayInfo(button, ...) or {}
    if HasOwnUpgradeArrow(button) then
        displayInfo.upgradeIcon = { shouldShow = false }
        displayInfo.levelGain = { shouldShow = false }
    end
    return displayInfo
end

function DialogueUIMixin:Refresh()
    CaerdonWardrobeFeatureMixin:Refresh(self)

    for button in pairs(trackedButtons) do
        -- Forget the link, so the button is sent to the core again.
        trackedButtons[button] = true
        self:UpdateRewardButton(button)
    end
end

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
    if C_AddOns.IsAddOnLoaded(addonName) then
        CaerdonWardrobe:RegisterFeature(DialogueUIMixin)
    end
end
