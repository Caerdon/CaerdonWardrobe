local addonName = "Bagnon"
local BagnonMixin = {}

function BagnonMixin:GetName()
    return addonName
end

function BagnonMixin:Init()
	hooksecurefunc(Bagnon.Item, "Update", function(...) self:OnUpdateSlot(...) end)
end

function BagnonMixin:GetTooltipData(item, locationInfo)
	if locationInfo.isOffline then
		if not item:IsItemEmpty() then
			return C_TooltipInfo.GetHyperlink(item:GetItemLink())
		end
	elseif not item:HasItemLocationBankOrBags() then
		return C_TooltipInfo.GetGuildBankItem(locationInfo.tab, locationInfo.index)
	elseif locationInfo.bag == BANK_CONTAINER then
		return C_TooltipInfo.GetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
	else
		return C_TooltipInfo.GetBagItem(locationInfo.bag, locationInfo.slot)
	end
end

function BagnonMixin:Refresh()
	Bagnon.Frames:Update()
end

function BagnonMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	if locationInfo.isOffline then
		local showBindingStatus = CaerdonWardrobeConfig.Binding.ShowStatus.BankAndBags
		local showOwnIcon = CaerdonWardrobeConfig.Icon.ShowLearnable.BankAndBags
		local showOtherIcon = CaerdonWardrobeConfig.Icon.ShowLearnableByOther.BankAndBags
		local showSellableIcon = CaerdonWardrobeConfig.Icon.ShowSellable.BankAndBags
	
		return {
			bindingStatus = {
				shouldShow = showBindingStatus
			},
			ownIcon = {
				shouldShow = showOwnIcon
			},
			otherIcon = {
				shouldShow = showOtherIcon
			},
			sellableIcon = {
				shouldShow = showSellableIcon
			}
		}
	elseif not item:HasItemLocationBankOrBags() then
		return {
			bindingStatus = {
				shouldShow = CaerdonWardrobeConfig.Binding.ShowStatus.GuildBank
			},
			ownIcon = {
				shouldShow = CaerdonWardrobeConfig.Icon.ShowLearnable.GuildBank
			},
			otherIcon = {
				shouldShow = CaerdonWardrobeConfig.Icon.ShowLearnableByOther.GuildBank
			},
			sellableIcon = {
				shouldShow = CaerdonWardrobeConfig.Icon.ShowSellable.GuildBank
			}
		}
	else
		return {}
	end
end

function BagnonMixin:OnUpdateSlot(bagnonItem)
	local bag, slot = bagnonItem:GetBag(), bagnonItem:GetID()
	if bagnonItem.info.cached then
		if bagnonItem.info.link then
			local item = CaerdonItem:CreateFromItemLink(bagnonItem.info.link)
			CaerdonWardrobe:UpdateButton(bagnonItem, item, self, { 
				locationKey = format("bag%d-slot%d", bag, slot),
				isOffline = true
			}, { } )
		else
			CaerdonWardrobe:ClearButton(bagnonItem)
		end
	else
		if bag ~= "vault" then
			local tab = GetCurrentGuildBankTab()
			local owner = bagnonItem.frame and bagnonItem.frame.GetOwner and bagnonItem.frame:GetOwner()
			if owner and owner.isguild and tab == bag then
				local itemLink = GetGuildBankItemLink(tab, slot)
				if itemLink then
					local item = CaerdonItem:CreateFromItemLink(itemLink)
					CaerdonWardrobe:UpdateButton(bagnonItem, item, self, {
						locationKey = format("tab%d-index%d", tab, slot),
						tab = tab,
						index = slot
					}, { } )
				else
					CaerdonWardrobe:ClearButton(bagnonItem)
				end
			else
				local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
				CaerdonWardrobe:UpdateButton(bagnonItem, item, self, { bag = bag, slot = slot }, { } )
			end
		end
	end
end

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
	if C_AddOns.IsAddOnLoaded(addonName) then
		Version = C_AddOns.GetAddOnMetadata(addonName, "Version")
		CaerdonWardrobe:RegisterFeature(BagnonMixin)
		isActive = true
	end
end

-- WagoAnalytics:Switch(addonName, isActive)
