CaerdonRecipe = {}
CaerdonRecipeMixin = {}

--[[static]] function CaerdonRecipe:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonRecipe:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonWardrobeItemDataMixin, CaerdonRecipeMixin)
    itemType.item = caerdonItem
    return itemType
end
