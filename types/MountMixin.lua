CaerdonMount = {}
CaerdonMountMixin = {}

--[[static]] function CaerdonMount:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonMount:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CaerdonWardrobeItemDataMixin.CreateItemData(CaerdonMountMixin, caerdonItem)
    return itemType
end

function CaerdonMountMixin:GetMountInfo()
    local mountID = C_MountJournal.GetMountFromItem(self.item:GetItemID())
    if mountID then
        local name, spellID, icon, isActive, isUsable, sourceType, isFavorite, isFactionSpecific, faction, shouldHideOnChar, isCollected, mountID = C_MountJournal.GetMountInfoByID(mountID)
        return {
            mountID = mountID,
            spellID = spellID,
            name = name,
            isCollected = isCollected,
            isUsable = isUsable,
            isFactionSpecific = isFactionSpecific,
            factionID = faction,
            shouldHideOnChar = shouldHideOnChar,
            needsItem = not isCollected
        }
    else
        local isEquipmentApplied = C_MountJournal.IsMountEquipmentApplied()
        return {
            isEquipment = true, -- assuming for now - can look up via itemlocation if needed
            isEquipmentApplied = isEquipmentApplied,
            needsItem = not isEquipmentApplied
        }
    end
end
