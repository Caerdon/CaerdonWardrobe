local CustomerOrdersMixin = {}

function CustomerOrdersMixin:GetName()
	return "CustomerOrders"
end

-- An order's piece is marked by the loot spec chosen, and as not to be had where this toon
-- cannot collect its source (FeatureMixin.lua, statusRules).
CustomerOrdersMixin.statusRules = { otherSpec = true, noLoot = true }

function CustomerOrdersMixin:Init(frame)
	self.orderContinuableContainer = ContinuableContainer:Create()

	self:WhenAddOnLoaded("Blizzard_ProfessionsCustomerOrders", self.OnCustomerOrdersLoaded)
	return {}
end

function CustomerOrdersMixin:OnCustomerOrdersLoaded()
    ScrollUtil.AddInitializedFrameCallback(ProfessionsCustomerOrdersFrame.BrowseOrders.RecipeList.ScrollBox, function (...) self:OnInitializedFrame(...) end, ProfessionsCustomerOrdersFrame.BrowseOrders.RecipeList, false)
    hooksecurefunc(ProfessionsCustomerOrdersFrame.Form, "InitSchematic", function (...) self:OnSchematicFormInit(...) end)
end

function CustomerOrdersMixin:OnInitializedFrame(listFrame, frame, elementData)
    local button = frame
    local outputItemData = C_TradeSkillUI.GetRecipeOutputItemData(elementData.option.spellID)
    local item = CaerdonItem:CreateFromItemLink(outputItemData.hyperlink)

    CaerdonWardrobe:UpdateButton(button, item, self, {
            locationKey = format("%d", elementData.option.itemID),
            option = elementData.option
        },  
        {
            overrideStatusPosition = "LEFT",
            statusProminentSize = 13,
            statusOffsetX = 3,
            statusOffsetY = 0,
            -- relativeFrame=cell.Icon
    })
end

-- What this window shows of an item (FeatureMixin.lua, displayRules).
CustomerOrdersMixin.displayRules = {
	bindingStatus = false,
	ownIcon = true,
	otherIcon = "CustomerOrders",
	questIcon = false,
	oldExpansionIcon = false,
	sellableIcon = false,
}

function CustomerOrdersMixin:OnSchematicFormInit(frame)
    -- DevTools_Dump(frame)
    -- print("=====================")
    -- DevTools_Dump(frame.transaction)
    -- if not frame.transaction then return end

    C_Timer.After(0, function ()
        local button = frame.OutputIcon
        local recipeID = frame.transaction:GetRecipeID();
        -- local recipeID = frame.order.spellID
		local reagents = nil;
		local outputItemInfo = C_TradeSkillUI.GetRecipeOutputItemData(recipeID, reagents, frame.transaction:GetRecraftAllocation());

        local options = {
        }

        local itemLink = outputItemInfo.hyperlink
        if itemLink then
            -- print(itemLink)
            local item = CaerdonItem:CreateFromItemLink(itemLink)
            CaerdonWardrobe:UpdateButton(button, item, self, { 
                locationKey = format("selectedrecipe%d",  item:GetItemID()),
                selectedRecipeID =  recipeID
            }, options)
        else
            local recipeSchematic = ProfessionsCustomerOrdersFrame.Form.transaction:GetRecipeSchematic()
            local item = CaerdonItem:CreateFromItemID(recipeSchematic.outputItemID)
            CaerdonWardrobe:UpdateButton(button, item, self, { 
                locationKey = format("selectedrecipe%d",  item:GetItemID()),
                selectedRecipeID =  recipeID
            }, options)
            end
    end)
end

CaerdonWardrobe:RegisterFeature(CustomerOrdersMixin)
