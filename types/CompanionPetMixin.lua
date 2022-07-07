CaerdonCompanionPet = {}
CaerdonCompanionPetMixin = {}

--[[static]] function CaerdonCompanionPet:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonCompanion:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonWardrobeItemDataMixin, CaerdonCompanionPetMixin)
    itemType.item = caerdonItem
    return itemType
end

function CaerdonCompanionPetMixin:GetCompanionPetInfo()
    local name, icon, petType, creatureID, sourceText, description, isWild, canBattle, isTradeable, isUnique, isObtainable, displayID, speciesID = C_PetJournal.GetPetInfoByItemID(self.item:GetItemID())
    if creatureID and displayID then
        local needsItem = false
        local numCollected = C_PetJournal.GetNumCollectedInfo(speciesID)
        if numCollected == 0 then
            needsItem = true
        end

        return {
            needsItem = needsItem,
            name = name,
            petType = petType,
            creatureID = creatureID,
            sourceText = sourceText,
            isWild = isWild,
            canBattle = canBattle,
            isTradeable = isTradeable,
            isUnique = isUnique,
            isObtainable = isObtainable,
            speciesID = speciesID,
            displayID = displayID,
            numCollected = numCollected
        }
    end
end
