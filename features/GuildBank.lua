local GuildBankMixin = {}

function GuildBankMixin:GetName()
	return "GuildBank"
end

function GuildBankMixin:Init()
	return { "ADDON_LOADED" }
end

function GuildBankMixin:ADDON_LOADED(name)
	if name == "Blizzard_GuildBankUI" then
		hooksecurefunc("GuildBankFrame_Update", function(...) self:OnGuildBankFrameUpdate(...) end)
	end
end

function GuildBankMixin:SetTooltipItem(tooltip, item, locationInfo)
	local speciesID, level, breedQuality, maxHealth, power, speed, name = tooltip:SetGuildBankItem(locationInfo.tab, locationInfo.index)
end

function GuildBankMixin:Refresh()
end

function GuildBankMixin:GetDisplayInfo()
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
end

function GuildBankMixin:OnGuildBankFrameUpdate()
	if( GuildBankFrame.mode == "bank" ) then
		local tab = GetCurrentGuildBankTab();
		local button, index, column;
		local texture, itemCount, locked, isFiltered, quality;

		for i=1, MAX_GUILDBANK_SLOTS_PER_TAB do
			index = mod(i, NUM_SLOTS_PER_GUILDBANK_GROUP);
			if ( index == 0 ) then
				index = NUM_SLOTS_PER_GUILDBANK_GROUP;
			end

			if self.isGuildBankFrameUpdateRequested then
				return
			end

			column = ceil((i-0.5)/NUM_SLOTS_PER_GUILDBANK_GROUP);
			button = _G["GuildBankColumn"..column.."Button"..index];

			local options = {
				showMogIcon = true,
				showBindStatus = true,
				showSellables = true
			}

			local itemLink = GetGuildBankItemLink(tab, i)
			if itemLink then
				local item = CaerdonItem:CreateFromItemLink(itemLink)
				CaerdonWardrobe:UpdateButton(button, item, self, {
					locationKey = format("tab%d-index%d", tab, i),
					tab = tab,
					index = i
				}, options)
			else
				CaerdonWardrobe:ClearButton(button)
			end
		end
	end
end

CaerdonWardrobe:RegisterFeature(GuildBankMixin)

-- GUILDBANKBAGSLOTS_CHANGED
-- GUILDBANKFRAME_OPENED
