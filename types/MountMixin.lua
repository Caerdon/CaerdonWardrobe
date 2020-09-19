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
