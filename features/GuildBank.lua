local GuildBankMixin = {}

function GuildBankMixin:GetName()
	return "GuildBank"
end

function GuildBankMixin:Init()
	self:WhenAddOnLoaded("Blizzard_GuildBankUI", self.OnGuildBankLoaded)
	return {}
end

function GuildBankMixin:OnGuildBankLoaded()
	hooksecurefunc(GuildBankFrame, "Update", function(...) self:OnGuildBankFrameUpdate(...) end)
end

function GuildBankMixin:GetTooltipData(item, locationInfo)
	return C_TooltipInfo.GetGuildBankItem(locationInfo.tab, locationInfo.index)
end

-- What this window shows of an item (FeatureMixin.lua, displayRules).
GuildBankMixin.displayRules = {
	bindingStatus = "GuildBank",
	ownIcon = "GuildBank",
	otherIcon = "GuildBank",
	sellableIcon = "GuildBank",
}

function GuildBankMixin:OnGuildBankFrameUpdate()
	-- TODO: They moved these local to Blizzard_GuildBankUI so hard-coding here for now.
	local MAX_GUILDBANK_SLOTS_PER_TAB = 98;
	local NUM_SLOTS_PER_GUILDBANK_GROUP = 14;

	if( GuildBankFrame.mode == "bank" ) then
		local tab = GetCurrentGuildBankTab();
		local button, index, column;
		local texture, itemCount, locked, isFiltered, quality;

		if ( GuildBankFrame.noViewableTabs ) then
			return;
		end

		for i=1, MAX_GUILDBANK_SLOTS_PER_TAB do
			index = mod(i, NUM_SLOTS_PER_GUILDBANK_GROUP);
			if ( index == 0 ) then
				index = NUM_SLOTS_PER_GUILDBANK_GROUP;
			end

			-- if self.isGuildBankFrameUpdateRequested then
			-- 	return
			-- end

			column = ceil((i-0.5)/NUM_SLOTS_PER_GUILDBANK_GROUP);

			button = GuildBankFrame.Columns[column].Buttons[index];

			local options = {
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
