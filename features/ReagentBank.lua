local ReagentBankMixin = {}

function ReagentBankMixin:GetName()
	return "ReagentBank"
end

function ReagentBankMixin:Init()
    hooksecurefunc("BankFrameItemButton_Update", function(...) self:OnBankItemUpdate(...) end)
end

function ReagentBankMixin:GetTooltipData(item, locationInfo)
	return C_TooltipInfo.GetInventoryItem("player", ReagentBankButtonIDToInvSlotID(locationInfo.slot))
end

function ReagentBankMixin:Refresh()
end

function ReagentBankMixin:OnBankItemUpdate(button)
	local bag = button:GetParent():GetID();
    local slot = button:GetID();

    if bag ~= REAGENTBANK_CONTAINER or not slot or button.isBag then
        return
    end

    local item = CaerdonItem:CreateFromBagAndSlot(bag, slot)
    CaerdonWardrobe:UpdateButton(button, item, self, { bag = bag, slot = slot }, { })
end

CaerdonWardrobe:RegisterFeature(ReagentBankMixin)
