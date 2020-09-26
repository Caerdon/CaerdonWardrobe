CaerdonMount = {}
CaerdonMountMixin = {}

--[[static]] function CaerdonMount:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonMount:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonMountMixin)
    itemType.item = caerdonItem
    return itemType
end

function CaerdonMountMixin:GetMountInfo()
    local mountID = C_MountJournal.GetMountFromItem(self.item:GetItemID())
    if mountID then
        local name, spellID, icon, isActive, isUsable, sourceType, isFavorite, isFactionSpecific, faction, shouldHideOnChar, isCollected, mountID = C_MountJournal.GetMountInfoByID(mountID)
        return {
            name = name,
            isUsable = isUsable,
            isFactionSpecific = isFactionSpecific,
            factionID = faction,
            needsItem = not isCollected
        }
    else
        return {
            isEquipment = true, -- assuming for now - can look up via itemlocation if needed
            needsItem = not C_MountJournal.IsMountEquipmentApplied()
        }
    end
end
