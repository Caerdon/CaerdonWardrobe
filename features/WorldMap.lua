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

	if GetNumQuestLogRewards(pin.questID) > 0 then
		local itemName, itemTexture, numItems, quality, isUsable, itemID = GetQuestLogRewardInfo(1, pin.questID)
		CaerdonWardrobe:UpdateButton(itemID, "QuestButton", { itemID = itemID, questID = pin.questID }, pin, options)
	else
		CaerdonWardrobe:ClearButton(pin)
	end
end

WorldMap = CreateFromMixins(WorldMapMixin)
WorldMap:OnLoad()
