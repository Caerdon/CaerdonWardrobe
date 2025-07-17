local ADDON_NAME, NS = ...
local L = NS.L

CaerdonWardrobeFeatureMixin = {}
function CaerdonWardrobeFeatureMixin:GetName()
    -- Must be unique
    error("Caerdon Wardrobe: Must provide a feature name")
end

function CaerdonWardrobeFeatureMixin:Init()
    -- init and return array of frame events you'd like to receive
    error(format("Caerdon Wardrobe: Must provide Init implementation for %s", self:GetName()))
end

function CaerdonWardrobeFeatureMixin:GetTooltipData(item, locationInfo)
    error(format("Caerdon Wardrobe: Must provide GetTooltipData implementation for %s", self:GetName()))
end

function CaerdonWardrobeFeatureMixin:Refresh(feature)
    -- Primarily used for global transmog refresh when appearances learned right now
    if feature then
        CaerdonWardrobe:CancelPending(feature)
    end
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
    local showUpgradeIcon = not item:HasItemLocationBankOrBags() or CaerdonWardrobeConfig.Icon.ShowUpgrades.BankAndBags
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

    return displayInfo
end

function CaerdonWardrobeFeatureMixin:OnUpdate()
    -- Called from the main frame's OnUpdate
end
