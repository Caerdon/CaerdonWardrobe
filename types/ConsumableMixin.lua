CaerdonConsumable = {}
CaerdonConsumableMixin = {}

local ADDON_NAME, NS = ...
local L = NS.L

--[[static]] function CaerdonConsumable:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonConsumable:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonWardrobeItemDataMixin, CaerdonConsumableMixin)
    itemType.item = caerdonItem

    return itemType
end

function CaerdonConsumableMixin:GetConsumableInfo()
    local needsItem = false
    local otherNeedsItem = false
    local validForCharacter = true

    local itemLink = self.item:GetItemLink()
    local transmogSetID = C_Item.GetItemLearnTransmogSet(itemLink)
    if transmogSetID then
        local transmogSetInfo = C_TransmogSets.GetSetInfo(transmogSetID)
        if not transmogSetInfo.collected then
            needsItem = true
            validForCharacter = transmogSetInfo.validForCharacter
        end
    end

    local itemName = C_Item.GetItemInfo(self.item:GetItemLink())
    local factionName, changed = string.gsub(itemName, L["Contract: "], "")
    if changed > 0 then
        local expansionIndex = 0
        for expansionIndex = 0, LE_EXPANSION_LEVEL_CURRENT do
            local majorFactionIDs = C_MajorFactions.GetMajorFactionIDs(expansionIndex);
            for index, majorFactionID in ipairs(majorFactionIDs) do
                local factionData = C_MajorFactions.GetMajorFactionData(majorFactionID)
                if factionData.name == factionName or factionData.name == L["The "] .. factionName then -- Silly but "Contract: Assembly of the Deeps" needs to match "The Assembly of the Deeps"
                    local hasMaxRenown = C_MajorFactions.HasMaximumRenown(majorFactionID)
                    local isAccountWideRenown = C_Reputation.IsAccountWideReputation(majorFactionID)
                    if hasMaxRenown then
                        if not isAccountWideRenown then
                            needsItem = false
                            otherNeedsItem = true
                        end
                    else
                        needsItem = true
                    end
                end
            end
        end
    end

    -- May not need any of this for anything but keeping around
    -- local spellID = C_Item.GetFirstTriggeredSpellForItem(caerdonItem:GetItemID(), caerdonItem:GetItemQuality())
    -- if spellID then
    --     print("Spell ID: " .. spellID)
    --     print("Item ID: " .. caerdonItem:GetItemID())
    -- end
    -- local spellName, spellID = C_Item.GetItemSpell(caerdonItem:GetItemLink())
    -- print(spellName)

    return {
        needsItem = needsItem,
        otherNeedsItem = otherNeedsItem,
        validForCharacter = validForCharacter
    }
end