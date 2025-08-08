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
    local toyItemID, toyName, icon, isFavorite, hasFanfare = C_ToyBox.GetToyInfo(itemID)

    -- Prefer the toyItemID returned by the API when available; otherwise fall back to the original itemID
    local checkItemID = toyItemID or itemID
    local hasToy = false
    if checkItemID ~= nil then
        hasToy = PlayerHasToy(checkItemID)
    end

    return {
        name = toyName,
        isFavorite = isFavorite,
        needsItem = not hasToy
    }
end
