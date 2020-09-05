local WorldMapMixin, WorldMap = {}

function WorldMapMixin:OnLoad()
	hooksecurefunc (WorldMap_WorldQuestPinMixin, "RefreshVisuals", function (self)
		if not IsModifiedClick("COMPAREITEMS") and not ShoppingTooltip1:IsShown() then
			WorldMap:UpdatePin(self);
		end
	end)
end

function WorldMapMixin:UpdatePin(pin)
	local options = {
		iconOffset = -5,
		iconSize = 60,
		overridePosition = "TOPRIGHT",
		-- itemCountOffset = 10,
		-- bindingScale = 0.9
	}

	local itemLink, itemName, itemTexture, numItems, quality, isUsable, itemID

	if GetNumQuestLogRewards(pin.questID) > 0 then
		itemName, itemTexture, numItems, quality, isUsable, itemID = GetQuestLogRewardInfo(1, pin.questID)

		if itemID then
			_, itemLink = GetItemInfo(itemID)
		end
	end
			
	CaerdonWardrobe:UpdateButtonLink(itemLink, "QuestButton", { itemID = itemID, questID = pin.questID }, pin, options)
end

WorldMap = CreateFromMixins(WorldMapMixin)
WorldMap:OnLoad()
