local addonName = "Bagnonium"
local BagnoniumMixin = {}

function BagnoniumMixin:GetName()
    return addonName
end

-- Where this feature attaches to Bagnonium (the integration report; see FeatureMixin.lua).
BagnoniumMixin.integration = {
	addon = addonName,
	hookPoints = { "Bagnonium.Item.Update" },
}

function BagnoniumMixin:Init()
	self:NoteHookPoint("Bagnonium.Item.Update", Bagnonium.Item, "Update")
	hooksecurefunc(Bagnonium.Item, "Update", function(...) self:OnUpdateSlot(...) end)
end

function BagnoniumMixin:GetTooltipData(item, locationInfo)
	if locationInfo.isOffline then
		if not item:IsItemEmpty() then
			return C_TooltipInfo.GetHyperlink(item:GetItemLink())
		end
	elseif not item:HasItemLocationBankOrBags() then
		return C_TooltipInfo.GetGuildBankItem(locationInfo.tab, locationInfo.index)
	else
		return C_TooltipInfo.GetBagItem(locationInfo.bag, locationInfo.slot)
	end
end

function BagnoniumMixin:Refresh()
	Bagnonium.Frames:Update()
end

-- What this window shows of an item (FeatureMixin.lua, displayRules), by the place: a view
-- kept of bags that are not open goes by the settings for the bags, a guild bank by the guild
-- bank's, and the toon's own bags are as the core has them.
local OFFLINE_RULES = {
	bindingStatus = "BankAndBags",
	ownIcon = "BankAndBags",
	otherIcon = "BankAndBags",
	sellableIcon = "BankAndBags",
}
local GUILD_BANK_RULES = {
	bindingStatus = "GuildBank",
	ownIcon = "GuildBank",
	otherIcon = "GuildBank",
	sellableIcon = "GuildBank",
}

function BagnoniumMixin:GetDisplayRules(button, item, feature, locationInfo)
	if locationInfo.isOffline then
		return OFFLINE_RULES
	elseif not item:HasItemLocationBankOrBags() then
		return GUILD_BANK_RULES
	end
end

function BagnoniumMixin:OnUpdateSlot(button)
	local bag, slot = button:GetBag(), button:GetID()
	if button.info.cached then
		if button.info.link then
			local item = CaerdonItem:CreateFromItemLink(button.info.link)
			CaerdonWardrobe:UpdateButton(button, item, self, {
				locationKey = format("bag%d-slot%d", bag, slot),
				isOffline = true
			}, { } )
		else
			CaerdonWardrobe:ClearButton(button)
		end
	else
		if bag ~= "vault" then
			local tab = GetCurrentGuildBankTab()
			local owner = button.frame and button.frame.GetOwner and button.frame:GetOwner()
			if owner and owner.isguild and tab == bag then
				local itemLink = GetGuildBankItemLink(tab, slot)
				if itemLink then
					local item = CaerdonItem:CreateFromItemLink(itemLink)
					CaerdonWardrobe:UpdateButton(button, item, self, {
						locationKey = format("tab%d-index%d", tab, slot),
						tab = tab,
						index = slot
					}, { } )
				else
					CaerdonWardrobe:ClearButton(button)
				end
			else
				local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
				CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot }, { } )
			end
		end
	end
end

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
	if C_AddOns.IsAddOnLoaded(addonName) then
		Version = C_AddOns.GetAddOnMetadata(addonName, "Version")
		CaerdonWardrobe:RegisterFeature(BagnoniumMixin)
		isActive = true
	end
end

-- WagoAnalytics:Switch(addonName, isActive)
