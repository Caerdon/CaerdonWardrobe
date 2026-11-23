local ADDON_NAME, NS = ...
local L = NS.L

CaerdonWardrobeFeatureMixin = {}
function CaerdonWardrobeFeatureMixin:GetName()
    -- Must be unique
    error("Caerdon Wardrobe: Must provide a feature name")
end

-- Which feature's status rules ProcessItem applies (the Merchant / EncounterJournal / CustomerOrders
-- exceptions). A feature that draws another feature's content in its own frames, such as an addon's
-- replacement vendor window, returns that feature's name.
function CaerdonWardrobeFeatureMixin:GetStatusRuleName()
    return self:GetName()
end

function CaerdonWardrobeFeatureMixin:Init()
    -- init and return array of frame events you'd like to receive. An entry is an event's name,
    -- or { name, unit } for a unit event that is only wanted for that unit.
    error(format("Caerdon Wardrobe: Must provide Init implementation for %s", self:GetName()))
end

-- For a window whose addon the client loads on demand: `callback` (a method of the feature) runs
-- once the addon is loaded, at once where it already is. Called from Init, in the place of an
-- ADDON_LOADED handler that compares names.
function CaerdonWardrobeFeatureMixin:WhenAddOnLoaded(addonName, callback)
    CaerdonWardrobe:WhenAddOnLoaded(addonName, self, callback)
end

-- Hook points: where a feature attaches to another addon's code.
--
-- A feature that decorates another addon's frames declares the places it attaches to:
--     SomeMixin.integration = {
--         addon = "SomeAddon",                              -- as the client's addon list names it
--         hookPoints = { "SomeAddon.Item.Update" },         -- the feature does not work without these
--         optionalHookPoints = { "SomeAddon.Item.Flash" },  -- used when the addon has them
--     }
-- and reports each one just before it attaches, with the table and the key it is about to use:
--     self:NoteHookPoint("SomeAddon.Item.Update", SomeAddon.Item, "Update")
-- CaerdonIntegrations turns the two into one line per integration: found, missing, or not reached
-- yet. The label is only a name to read; keep it the same in both places.

local function ReadField(owner, key)
    return owner[key]
end

local function CountHookPoint(feature, label, found)
    local noted = feature.hookPointsNoted
    if not noted then
        noted = {}
        feature.hookPointsNoted = noted
    end
    local entry = noted[label]
    if not entry then
        entry = { found = 0, missing = 0 }
        noted[label] = entry
    end
    if found then
        entry.found = entry.found + 1
    else
        entry.missing = entry.missing + 1
    end
end

-- Returns whether owner[key] is a function. Never throws, whatever the other addon handed over
-- (some namespaces raise an error when an unknown field is read), and changes nothing: the
-- caller attaches exactly as it did before.
function CaerdonWardrobeFeatureMixin:NoteHookPoint(label, owner, key)
    local found = false
    if type(owner) == "table" then
        local ok, value = pcall(ReadField, owner, key)
        found = ok and type(value) == "function"
    end
    CountHookPoint(self, label, found)
    return found
end

-- For a place the other addon calls by itself (a callback it looks up by name): there is nothing
-- to look for beforehand, so the call arriving is the evidence.
function CaerdonWardrobeFeatureMixin:NoteHookCalled(label)
    CountHookPoint(self, label, true)
end

-- The tooltip of the copy at a place in this feature's window (a bag slot, a mail attachment,
-- a guild bank slot), where the client has one that says more than the item's link does. The
-- status asks only for a Pet Cage, whose link says nothing about the pet inside
-- (CaerdonItemMixin:GetCaerdonStatus); every other item is judged from its link's tooltip. A
-- feature with no such place leaves this as it is: nil is "ask the link".
function CaerdonWardrobeFeatureMixin:GetTooltipData(item, locationInfo)
    return nil
end

-- Called after every full refresh (CaerdonWardrobe:RefreshItems), when every verdict has been
-- thrown away: the window's buttons are to be asked for again.
--
-- A window that walks its own buttons has a Refresh() of its own and calls this one first with
-- itself, CaerdonWardrobeFeatureMixin:Refresh(self), which drops its requests still waiting.
-- A window with none inherits this, and the core asks again for every button the window last
-- asked for (CaerdonWardrobe:AskAgain). So a Refresh() is written only where the default is
-- not enough, and never left empty: an empty one keeps every icon as it was.
function CaerdonWardrobeFeatureMixin:Refresh(feature)
    if feature then
        CaerdonWardrobe:CancelPending(feature)
    elseif self ~= CaerdonWardrobeFeatureMixin then
        CaerdonWardrobe:AskAgain(self)
    end
end

-- A button the default Refresh() left alone, because it was not on screen, has come on screen
-- (CaerdonWardrobe:AskWhenOnScreen). A window that hands buttons over itself has its own.
function CaerdonWardrobeFeatureMixin:OnButtonOnScreen(button)
    CaerdonWardrobe:AskAgainFor(button, self)
end

function CaerdonWardrobeFeatureMixin:IsSameItem(button, item, locationInfo)
    return true
end

function CaerdonWardrobeFeatureMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus,
                                                    bindingStatus)
    return {}
end

function CaerdonWardrobeFeatureMixin:GetDisplayInfoInternal(button, item, feature, locationInfo, options, mogStatus,
                                                            bindingStatus)
    -- TODO: Temporary for merging - revisit after pushing everything into Mixins
    local showBindingStatus = not item:HasItemLocationBankOrBags() or
        CaerdonWardrobeConfig.Binding.ShowStatus.BankAndBags
    local globalUpgradeEnabled = CaerdonWardrobeConfig.Icon.ShowUpgradeIcon ~= false
    local showUpgradeIcon = globalUpgradeEnabled and
        (not item:HasItemLocationBankOrBags() or CaerdonWardrobeConfig.Icon.ShowUpgrades.BankAndBags)
    local showOwnIcon = not item:HasItemLocationBankOrBags() or CaerdonWardrobeConfig.Icon.ShowLearnable.BankAndBags
    local showOtherIcon = not item:HasItemLocationBankOrBags() or
        CaerdonWardrobeConfig.Icon.ShowLearnableByOther.BankAndBags
    local showSellableIcon = not item:HasItemLocationBankOrBags() or CaerdonWardrobeConfig.Icon.ShowSellable.BankAndBags

    local displayInfo = {
        upgradeIcon = {
            shouldShow = showUpgradeIcon
        },
        bindingStatus = {
            shouldShow = showBindingStatus -- true
        },
        ownIcon = {
            shouldShow = showOwnIcon
        },
        otherIcon = {
            shouldShow = showOtherIcon
        },
        questIcon = {
            shouldShow = CaerdonWardrobeConfig.Icon.ShowQuestItems
        },
        oldExpansionIcon = {
            shouldShow = true
        },
        sellableIcon = {
            shouldShow = showSellableIcon
        },
        -- Only what is in the bags or bank can be listed, so the icon stays there.
        auctionIcon = {
            shouldShow = item:HasItemLocationBankOrBags() and CaerdonWardrobeConfig.Icon.ShowAuctionValue == true
        }
    }

    CaerdonAPI:MergeTable(displayInfo,
        self:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus))

    -- TODO: BoA and BoE settings should be per feature
    if not CaerdonWardrobeConfig.Binding.ShowBoA and bindingStatus == L["BoA"] then
        displayInfo.bindingStatus.shouldShow = false
    end

    if not CaerdonWardrobeConfig.Binding.ShowBoE and bindingStatus == L["BoE"] then
        displayInfo.bindingStatus.shouldShow = false
    end

    if not CaerdonWardrobeConfig.Binding.ShowWuE and bindingStatus == L["WuE"] then
        displayInfo.bindingStatus.shouldShow = false
    end

    return displayInfo
end

function CaerdonWardrobeFeatureMixin:OnUpdate()
    -- Called from the main frame's OnUpdate
end
