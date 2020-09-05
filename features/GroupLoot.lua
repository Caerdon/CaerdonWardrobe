local GroupLootMixin, GroupLoot = {}

function GroupLootMixin:OnLoad()
    GroupLootFrame1:HookScript("OnShow", function(...) GroupLoot:OnGroupLootFrameShow(...) end)
    GroupLootFrame2:HookScript("OnShow", function(...) GroupLoot:OnGroupLootFrameShow(...) end)
    GroupLootFrame3:HookScript("OnShow", function(...) GroupLoot:OnGroupLootFrameShow(...) end)
    GroupLootFrame4:HookScript("OnShow", function(...) GroupLoot:OnGroupLootFrameShow(...) end)
end

function GroupLootMixin:OnGroupLootFrameShow(frame)
	local itemLink = GetLootRollItemLink(frame.rollID)
	if itemLink == nil then
		CaerdonWardrobe:ClearButton(frame.IconFrame)
		return
	end

	local itemID = CaerdonWardrobe:GetItemID(itemLink)
	if itemID then
		CaerdonWardrobe:UpdateButton(itemID, "GroupLootFrame", { index = frame.rollID, link = itemLink}, frame.IconFrame, nil)
	else
		CaerdonWardrobe:ClearButton(frame.IconFrame)
	end
end

GroupLoot = CreateFromMixins(GroupLootMixin)
GroupLoot:OnLoad()
