CaerdonConsumable = {}
CaerdonConsumableMixin = {}

--[[static]] function CaerdonConsumable:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonConsumable:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonConsumableMixin)
    itemType.item = caerdonItem
    return itemType
end
