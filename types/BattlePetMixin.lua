CaerdonBattlePet = {}
CaerdonBattlePetMixin = {}

--[[static]] function CaerdonBattlePet:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonBattlePet:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonWardrobeItemDataMixin, CaerdonBattlePetMixin)
    itemType.item = caerdonItem
    return itemType
end

-- Battle pet links (battlepet:...) don't populate WoW's ItemMixin backing data,
-- so IsItemEmpty() is always true. Override to skip that check since battle pets
-- work entirely from the link text.
function CaerdonBattlePetMixin:ContinueOnItemDataLoad(callbackFunction)
    if type(callbackFunction) ~= "function" then
        error("Usage: ContinueOnItemDataLoad(callbackFunction)", 2)
    end
    callbackFunction()
end

function CaerdonBattlePetMixin:GetBattlePetInfo()
    local linkType, linkOptions, displayText = LinkUtil.ExtractLink(self.item:GetItemLink())

    local itemType = CaerdonItemType.BattlePet
    local needsItem = false

    local speciesID, level, quality, health, power, speed, petID, displayID = strsplit(":", linkOptions);
    -- local owned = C_PetJournal.GetOwnedBattlePetString(speciesID);

    local petName, petIcon, petType, creatureID, sourceText, description, isWild, canBattle, isTradeable, isUnique, isObtainable, displayID = C_PetJournal.GetPetInfoBySpeciesID(speciesID);

    local numCollected = C_PetJournal.GetNumCollectedInfo(speciesID)
    if numCollected == 0 then
        needsItem = true
    end

    return {
        needsItem = needsItem,
        name = displayText,
        petType = petType,
        creatureID = creatureID,
        sourceText = sourceText,
        isWild = isWild,
        canBattle = canBattle,
        isTradeable = isTradeable,
        isUnique = isUnique,
        isObtainable = isObtainable,
        speciesID = tonumber(speciesID),
        displayID = tonumber(displayID),
        numCollected = numCollected,
        quality = tonumber(quality),
        level = tonumber(level),
        health = tonumber(health),
        power = tonumber(power),
        speed = tonumber(speed),
        petID = tonumber(petID),
    }
end
