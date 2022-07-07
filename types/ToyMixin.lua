CaerdonToy = {}
CaerdonToyMixin = {}

--[[static]] function CaerdonToy:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonToy:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonWardrobeItemDataMixin, CaerdonToyMixin)
    itemType.item = caerdonItem
    return itemType
end

function CaerdonToyMixin:GetToyInfo()
    local itemID = self.item:GetItemID()
    local itemID, toyName, icon, isFavorite, hasFanfare = C_ToyBox.GetToyInfo(itemID);
    return {
        name = toyName,
        isFavorite = isFavorite,
        needsItem = not PlayerHasToy(itemID)
    }
end