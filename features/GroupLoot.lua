local GroupLootMixin, GroupLoot = {}

function GroupLootMixin:OnLoad()
    GroupLootFrame1:HookScript("OnShow", function(...) GroupLoot:OnGroupLootFrameShow(...) end)
    GroupLootFrame2:HookScript("OnShow", function(...) GroupLoot:OnGroupLootFrameShow(...) end)
    GroupLootFrame3:HookScript("OnShow", function(...) GroupLoot:OnGroupLootFrameShow(...) end)
    GroupLootFrame4:HookScript("OnShow", function(...) GroupLoot:OnGroupLootFrameShow(...) end)
end

function GroupLootMixin:OnGroupLootFrameShow(frame)
	local itemLink = GetLootRollItemLink(frame.rollID)
	CaerdonWardrobe:UpdateButtonLink(itemLink, "GroupLootFrame", { index = frame.rollID, link = itemLink}, frame.IconFrame, nil)
end

GroupLoot = CreateFromMixins(GroupLootMixin)
GroupLoot:OnLoad()
