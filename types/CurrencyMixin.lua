CaerdonCurrency = {}
CaerdonCurrencyMixin = {}

--[[static]] function CaerdonCurrency:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonCurrency:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonWardrobeItemDataMixin, CaerdonCurrencyMixin)
    itemType.item = caerdonItem
    return itemType
end

function CaerdonCurrencyMixin:GetCurrencyInfo()
  local currencyInfo = C_CurrencyInfo.GetCurrencyInfoFromLink(self.item:GetItemLink())
  -- DevTools_Dump(currencyInfo)
  if not currencyInfo then
    -- Currency data not cached yet; defer rather than indexing a nil value.
    return { isNotReady = true, needsItem = false, otherNeedsItem = false }
  end
  local hasMaxRenown = false
  local isAccountWideRenown = false

  local factionID = C_CurrencyInfo.GetFactionGrantedByCurrency(currencyInfo.currencyID)
  if factionID then
    hasMaxRenown = C_MajorFactions.HasMaximumRenown(factionID)
    isAccountWideRenown = C_Reputation.IsAccountWideReputation(factionID)
  end

  return {
    name = currencyInfo.name,
    totalEarned = currencyInfo.totalEarned,
    maxWeeklyQuantity = currencyInfo.maxWeeklyQuantity,
    maxQuantity = currencyInfo.maxQuantity,
    factionID = factionID,
    needsItem = factionID and not hasMaxRenown,
    otherNeedsItem = factionID and not isAccountWideRenown
  }
end