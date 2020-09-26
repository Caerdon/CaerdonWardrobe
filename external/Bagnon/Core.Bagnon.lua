local addonName = "Bagnon"
local BagnonMixin = {}

function BagnonMixin:GetName()
    return addonName
end

function BagnonMixin:Init()
	hooksecurefunc(Bagnon.Item, "Update", function(...) self:OnUpdateSlot(...) end)
end

function BagnonMixin:SetTooltipItem(tooltip, item, locationInfo)
	if locationInfo.isOffline then
		if not item:IsItemEmpty() then
			tooltip:SetHyperlink(item:GetItemLink())
		end
	elseif not locationInfo.isBankOrBags then
		local speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetGuildBankItem(locationInfo.tab, locationInfo.index)
	elseif locationInfo.bag == BANK_CONTAINER then
		local hasItem, hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
	else
		local hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetBagItem(locationInfo.bag, locationInfo.slot)
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
	elseif not locationInfo.isBankOrBags then
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
		if bagnon.info.link then
			local item = CaerdonItem:CreateFromItemLink(bagnonItem.info.link)
			CaerdonWardrobe:UpdateButton(bagnonItem, item, self, { isOffline = true }, { showMogIcon = true, showBindStatus = true, showSellables = true } )
		else
			CaerdonWardrobe:ClearButton(bagnonItem)
		end
	else
		if bag ~= "vault" then
			local tab = GetCurrentGuildBankTab()
			if Bagnon:InGuild() and tab == bag then
				local itemLink = GetGuildBankItemLink(tab, slot)
				if itemLink then
					local item = CaerdonItem:CreateFromItemLink(itemLink)
					CaerdonWardrobe:UpdateButton(bagnonItem, item, self, { tab = tab, index = slot }, { showMogIcon = true, showBindStatus = true, showSellables = true } )
				else
					CaerdonWardrobe:ClearButton(bagnonItem)
				end
			else
				local itemLink = GetContainerItemLink(bag, slot)
				if itemLink then
					local item = CaerdonItem:CreateFromItemLink(itemLink)
					CaerdonWardrobe:UpdateButton(bagnonItem, item, self, { bag = bag, slot = slot, isBankOrBags = true }, { showMogIcon = true, showBindStatus = true, showSellables = true } )
				else
					CaerdonWardrobe:ClearButton(bagnonItem)
				end
			end
		end
	end
end

local Version = nil
if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		Version = GetAddOnMetadata(addonName, "Version")
		CaerdonWardrobe:RegisterFeature(BagnonMixin)
	end
end
