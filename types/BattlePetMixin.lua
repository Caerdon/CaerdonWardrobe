CaerdonBattlePet = {}
CaerdonBattlePetMixin = {}

--[[static]] function CaerdonBattlePet:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonBattlePet:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonBattlePetMixin)
    itemType.item = caerdonItem
    return itemType
end

function CaerdonBattlePetMixin:GetBattlePetInfo()
    local linkType, linkOptions, displayText = LinkUtil.ExtractLink(self.item:GetItemLink())

    local itemType = CaerdonItemType.BattlePet
    local speciesID, level, quality, health, power, speed, petID, displayID = strsplit(":", linkOptions);
    local numCollected = C_PetJournal.GetNumCollectedInfo(speciesID)

    return {
        speciesID = tonumber(speciesID),
        level = tonumber(level),
        quality = tonumber(quality),
        health = tonumber(health),
        power = tonumber(power),
        speed = tonumber(speed),
        petID = tonumber(petID),
        displayID = tonumber(displayID),
        name = displayText,
        numCollected = numCollected
    }
end
