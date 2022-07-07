CaerdonConduit = {}
CaerdonConduitMixin = {}

--[[static]] function CaerdonConduit:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonConduit:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonWardrobeItemDataMixin, CaerdonConduitMixin)
    itemType.item = caerdonItem
    return itemType
end

function CaerdonConduitMixin:GetConduitInfo()
    local conduitTypes = { 
        Enum.SoulbindConduitType.Potency,
        Enum.SoulbindConduitType.Endurance,
        Enum.SoulbindConduitType.Finesse
    }

    local needsItem = true
    local conduitKnown = false
    local isUpgrade = false

    for conduitTypeIndex = 1, #conduitTypes do
        if conduitKnown then break end

        local conduitCollection = C_Soulbinds.GetConduitCollection(conduitTypes[conduitTypeIndex])
        for conduitCollectionIndex = 1, #conduitCollection do
            local conduitData = conduitCollection[conduitCollectionIndex]
            if conduitData.conduitItemID == self.item:GetItemID() then
                conduitKnown = conduitData.conduitItemLevel >= self.item:GetCurrentItemLevel()
                isUpgrade = conduitData.conduitItemLevel < self.item:GetCurrentItemLevel()
                break
            end
        end
    end

    if conduitKnown then
        -- TODO: May need to consider spec / class?  Not sure yet
        needsItem = false
    end

    return {
        needsItem = needsItem,
        isUpgrade = isUpgrade
    }
end
