CaerdonCompanionPet = {}
CaerdonCompanionPetMixin = {}

--[[static]] function CaerdonCompanionPet:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonCompanion:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonCompanionPetMixin)
    itemType.item = caerdonItem
    return itemType
end

function CaerdonCompanionPetMixin:GetCompanionPetInfo()
    local name, icon, petType, creatureID, sourceText, description, isWild, canBattle, tradeable, unique, obtainable, displayID, speciesID = C_PetJournal.GetPetInfoByItemID(self.item:GetItemID())
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
            tradeable = tradeable,
            unique = unique,
            obtainable = obtainable,
            displayID = displayID,
            speciesID = speciesID,
            quality = itemRarity,
            numCollected = numCollected
        }
    end
end
