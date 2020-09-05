local GroupLootMixin, GroupLoot = {}

function GroupLootMixin:OnLoad()
    GroupLootFrame1:HookScript("OnShow", function() GroupLoot:OnGroupLootFrameShow(self) end)
    GroupLootFrame2:HookScript("OnShow", function() GroupLoot:OnGroupLootFrameShow(self) end)
    GroupLootFrame3:HookScript("OnShow", function() GroupLoot:OnGroupLootFrameShow(self) end)
    GroupLootFrame4:HookScript("OnShow", function() GroupLoot:OnGroupLootFrameShow(self) end)
end

function GroupLootMixin:OnGroupLootFrameShow(frame)
	-- local texture, name, count, quality, bindOnPickUp, canNeed, canGreed, canDisenchant, reasonNeed, reasonGreed, reasonDisenchant, deSkillRequired = GetLootRollItemInfo(frame.rollID)
	-- if name == nil then
	-- 	return
	-- end

	local itemLink = GetLootRollItemLink(frame.rollID)
	if itemLink == nil then
		return
	end

	CaerdonWardrobe:UpdateButtonLink(itemLink, "GroupLootFrame", { index = frame.rollID, link = itemLink}, frame.IconFrame, nil)
end

GroupLoot = CreateFromMixins(GroupLootMixin)
GroupLoot:OnLoad()
