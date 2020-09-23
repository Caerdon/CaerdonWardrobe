CaerdonToy = {}
CaerdonToyMixin = {}

--[[static]] function CaerdonToy:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonToy:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonToyMixin)
    itemType.item = caerdonItem
    return itemType
end

function CaerdonToy:GetToyInfo()
    -- TODO: Can I get unknown somehow?
    local itemID, toyName, icon, isFavorite, hasFanfare = C_ToyBox.GetToyInfo(self.item:GetItemID());
    return {
        name = toyName,
        isFavorite = isFavorite
    }
end