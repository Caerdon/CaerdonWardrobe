local GuildBankMixin = {}
local GUILDBANKFRAMEUPDATE_INTERVAL = 0.1

function GuildBankMixin:GetName()
	return "GuildBank"
end

function GuildBankMixin:Init()
	self.isGuildBankFrameUpdateRequested = false
	self.timeSinceLastGuildBankUpdate = nil
	self.guildBankUpdateCoroutine = nil

	return { "ADDON_LOADED" }
end

function GuildBankMixin:SetTooltipItem(tooltip, item, locationInfo)
	local speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetGuildBankItem(locationInfo.tab, locationInfo.index)
end

function GuildBankMixin:Refresh()
end

function GuildBankMixin:OnUpdate(elapsed)
	if self.guildBankUpdateCoroutine then
		if coroutine.status(self.guildBankUpdateCoroutine) ~= "dead" then
			local ok, result = coroutine.resume(self.guildBankUpdateCoroutine)
			if not ok then
				error(result)
			end
		else
			self.guildBankUpdateCoroutine = nil
		end
		return
	end

	if self.isGuildBankFrameUpdateRequested then
		self.isGuildBankFrameUpdateRequested = false
		self.timeSinceLastGuildBankUpdate = 0
	elseif self.timeSinceLastGuildBankUpdate then
		self.timeSinceLastGuildBankUpdate = self.timeSinceLastGuildBankUpdate + elapsed
	end

	if( self.timeSinceLastGuildBankUpdate ~= nil and (self.timeSinceLastGuildBankUpdate > GUILDBANKFRAMEUPDATE_INTERVAL) ) then
		self.timeSinceLastGuildBankUpdate = nil
		self.guildBankUpdateCoroutine = coroutine.create(function () self:OnGuildBankFrameUpdate_Coroutine() end)
	end
end

function GuildBankMixin:ADDON_LOADED(name)
	if name == "Blizzard_GuildBankUI" then
		hooksecurefunc("GuildBankFrame_Update", function(...) self:OnGuildBankFrameUpdate(...) end)
	end
end

function GuildBankMixin:OnGuildBankFrameUpdate_Coroutine()
	if( GuildBankFrame.mode == "bank" ) then
		local tab = GetCurrentGuildBankTab();
		local button, index, column;
		local texture, itemCount, locked, isFiltered, quality;

		for i=1, MAX_GUILDBANK_SLOTS_PER_TAB do
			index = mod(i, NUM_SLOTS_PER_GUILDBANK_GROUP);
			if ( index == 0 ) then
				index = NUM_SLOTS_PER_GUILDBANK_GROUP;

				coroutine.yield()
			end

			if self.isGuildBankFrameUpdateRequested then
				return
			end

			column = ceil((i-0.5)/NUM_SLOTS_PER_GUILDBANK_GROUP);
			button = _G["GuildBankColumn"..column.."Button"..index];

			local bag = "GuildBankFrame"
			local slot = {tab = tab, index = i}

			local options = {
				showMogIcon = true,
				showBindStatus = true,
				showSellables = true
			}

			local itemLink = GetGuildBankItemLink(tab, i)
			CaerdonWardrobe:UpdateButtonLink(itemLink, bag, slot, button, options)
		end
	end
end

function GuildBankMixin:OnGuildBankFrameUpdate()
	self.isGuildBankFrameUpdateRequested = true
end

CaerdonWardrobe:RegisterFeature(GuildBankMixin)

-- GUILDBANKBAGSLOTS_CHANGED
-- GUILDBANKFRAME_OPENED
