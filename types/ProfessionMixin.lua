CaerdonProfession = {}
CaerdonProfessionMixin = {}

--[[static]] function CaerdonProfession:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonProfession:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonWardrobeItemDataMixin, CaerdonProfessionMixin)
    itemType.item = caerdonItem
    return itemType
end

function CaerdonProfessionMixin:GetProfessionInfo()
    local result = {
        needsItem = false
    }

    local hasSkillLine, meetsMinRank = CaerdonRecipe:GetPlayerSkillInfo(self.item:GetItemSubType(), 0)
    if hasSkillLine then
        local slots = C_TradeSkillUI.GetProfessionSlots(Enum.Profession[self.item:GetItemSubType()])
        local availableItems = {};
        for i = 1, #slots do
            local link = GetInventoryItemLink("player", slots[i])
            if not link then
                GetInventoryItemsForSlot(slots[i], availableItems);
            end
        end

        local packedLocation, itemLink
        for packedLocation, checkLink in pairs(availableItems) do
            if checkLink == self.item:GetItemLink() then
                result.needsItem = true
            end
        end
    end

    return result
end
