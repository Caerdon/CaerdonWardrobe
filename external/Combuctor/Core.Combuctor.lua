local addonName = "Combuctor"
local CombuctorMixin = {}

function CombuctorMixin:GetName()
    return addonName
end

function CombuctorMixin:Init()
	hooksecurefunc(Combuctor.Item, "Update", function(...) self:OnUpdateSlot(...) end)
end

function CombuctorMixin:SetTooltipItem(tooltip, item, locationInfo)
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

function CombuctorMixin:Refresh()
	if Combuctor.sets then
		Combuctor:UpdateFrames()
	end
end

function CombuctorMixin:OnUpdateSlot(button)
	local bag, slot = button:GetBag(), button:GetID()
	if button.info.cached then
		CaerdonWardrobe:UpdateButtonLink(button.info.link, self:GetName(), { isOffline = true }, button, { showMogIcon = true, showBindStatus = true, showSellables = true } )
	else
		if bag ~= "vault" then
			local tab = GetCurrentGuildBankTab()
			if Combuctor:InGuild() and tab == bag then
				local itemLink = GetGuildBankItemLink(tab, slot)
				CaerdonWardrobe:UpdateButtonLink(itemLink, self:GetName(), { tab = tab, index = slot }, button, { showMogIcon = true, showBindStatus = true, showSellables = true } )
			else
				local itemLink = GetContainerItemLink(bag, slot)
				CaerdonWardrobe:UpdateButtonLink(itemLink, self:GetName(), { bag = bag, slot = slot, isBankOrBags = true }, button, { showMogIcon = true, showBindStatus = true, showSellables = true } )
			end
		end
	end
end

local Version = nil
if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		Version = GetAddOnMetadata(addonName, "Version")
		CaerdonWardrobe:RegisterFeature(CombuctorMixin)
	end
end
