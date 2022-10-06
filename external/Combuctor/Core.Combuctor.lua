local addonName = "Combuctor"
local CombuctorMixin = {}

function CombuctorMixin:GetName()
    return addonName
end

function CombuctorMixin:Init()
	hooksecurefunc(Combuctor.Item, "Update", function(...) self:OnUpdateSlot(...) end)
end

function CombuctorMixin:GetTooltipInfo(tooltip, item, locationInfo)
	local tooltipInfo
	if locationInfo.isOffline then
		if not item:IsItemEmpty() then
			tooltipInfo = MakeBaseTooltipInfo("GetHyperlink", item:GetItemLink());
		end
	elseif not item:HasItemLocationBankOrBags() then
		local speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetGuildBankItem(locationInfo.tab, locationInfo.index)
		tooltipInfo = MakeBaseTooltipInfo("GetGuildBankItem", locationInfo.tab, locationInfo.index);
	elseif locationInfo.bag == BANK_CONTAINER then
		tooltipInfo = MakeBaseTooltipInfo("GetInventoryItem", "player", BankButtonIDToInvSlotID(locationInfo.slot));
	else
		local hasCooldown, repairCost, speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetBagItem(locationInfo.bag, locationInfo.slot)
		tooltipInfo = MakeBaseTooltipInfo("GetBagItem", locationInfo.bag, locationInfo.slot);
	end

	return tooltipInfo
end

function CombuctorMixin:Refresh()
	Combuctor.Frames:Update()
end

function CombuctorMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
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

function CombuctorMixin:OnUpdateSlot(button)
	local bag, slot = button:GetBag(), button:GetID()
	if button.info.cached then
		if button.info.link then
			local item = CaerdonItem:CreateFromItemLink(button.info.link)
			CaerdonWardrobe:UpdateButton(button, item, self, {
				locationKey = format("bag%d-slot%d", bag, slot),
				isOffline = true
			}, { showMogIcon = true, showBindStatus = true, showSellables = true } )
		else
			CaerdonWardrobe:ClearButton(button)
		end
	else
		if bag ~= "vault" then
			local tab = GetCurrentGuildBankTab()
			if Combuctor:InGuild() and tab == bag then
				local itemLink = GetGuildBankItemLink(tab, slot)
				if itemLink then
					local item = CaerdonItem:CreateFromItemLink(itemLink)
					CaerdonWardrobe:UpdateButton(button, item, self, {
						locationKey = format("tab%d-index%d", tab, slot),
						tab = tab,
						index = slot
					}, { showMogIcon = true, showBindStatus = true, showSellables = true } )
				else
					CaerdonWardrobe:ClearButton(button)
				end
			else
				local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
				CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot }, { showMogIcon = true, showBindStatus = true, showSellables = true } )
			end
		end
	end
end

local Version = nil
local isActive = false

if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		Version = GetAddOnMetadata(addonName, "Version")
		CaerdonWardrobe:RegisterFeature(CombuctorMixin)
		isActive = true
	end
end

WagoAnalytics:Switch(addonName, isActive)
