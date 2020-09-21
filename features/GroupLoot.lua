local GroupLootMixin = {}

function GroupLootMixin:GetName()
    return "GroupLoot"
end

function GroupLootMixin:Init()
    GroupLootFrame1:HookScript("OnShow", function(...) self:OnGroupLootFrameShow(...) end)
    GroupLootFrame2:HookScript("OnShow", function(...) self:OnGroupLootFrameShow(...) end)
    GroupLootFrame3:HookScript("OnShow", function(...) self:OnGroupLootFrameShow(...) end)
    GroupLootFrame4:HookScript("OnShow", function(...) self:OnGroupLootFrameShow(...) end)
end

function GroupLootMixin:SetTooltipItem(tooltip, item, locationInfo)
    tooltip:SetLootRollItem(locationInfo.index)
end

function GroupLootMixin:Refresh()
end

function GroupLootMixin:OnGroupLootFrameShow(frame)
	local itemLink = GetLootRollItemLink(frame.rollID)
	CaerdonWardrobe:UpdateButtonLink(itemLink, self:GetName(), { index = frame.rollID, link = itemLink}, frame.IconFrame, nil)
end

CaerdonWardrobe:RegisterFeature(GroupLootMixin)
