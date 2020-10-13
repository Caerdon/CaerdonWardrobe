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
    if itemLink then
        local item = CaerdonItem:CreateFromItemLink(itemLink)
        CaerdonWardrobe:UpdateButton(frame.IconFrame, item, self, {
            locationKey = format("%d", frame.rollID),
            index = frame.rollID,
            link = itemLink
        }, nil)
    else
        CaerdonWardrobe:ClearButton(frame.IconFrame)
    end
end

CaerdonWardrobe:RegisterFeature(GroupLootMixin)
