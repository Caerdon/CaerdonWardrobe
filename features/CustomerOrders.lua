local CustomerOrdersMixin = {}

function CustomerOrdersMixin:GetName()
	return "CustomerOrders"
end

function CustomerOrdersMixin:Init(frame)
	self.orderContinuableContainer = ContinuableContainer:Create()

	return {
        "ADDON_LOADED"
	}
end

function CustomerOrdersMixin:ADDON_LOADED(name)
    if name == "Blizzard_ProfessionsCustomerOrders" then
        ScrollUtil.AddInitializedFrameCallback(ProfessionsCustomerOrdersFrame.BrowseOrders.RecipeList.ScrollBox, function (...) self:OnInitializedFrame(...) end, self, false)
        hooksecurefunc(ProfessionsCustomerOrdersFrame.Form, "Init", function (...) self:OnSchematicFormInit(...) end)
    end
end

function CustomerOrdersMixin:OnInitializedFrame(frame, elementData)
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
            showMogIcon=true, 
            showBindStatus=true,
            showSellables=false,
            -- relativeFrame=cell.Icon
    })
end

function CustomerOrdersMixin:SetTooltipItem(tooltip, item, locationInfo)
	-- local option = locationInfo.option
	-- if option then
        -- local reagents = {};
        -- TODO: Do I need to get this somehow?  New link method seems fine...
        -- C_TradeSkillUI.SetTooltipRecipeResultItem(option.spellID, reagents);
        -- DevTools_Dump(tooltip)
	-- else
		tooltip:SetHyperlink(item:GetItemLink())
	-- end
end

function CustomerOrdersMixin:Refresh()
end

function CustomerOrdersMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	return {
		bindingStatus = {
			shouldShow = false
		},
		ownIcon = {
			shouldShow = true
		},
		otherIcon = {
			shouldShow = true
		},
		questIcon = {
			shouldShow = false
		},
		oldExpansionIcon = {
			shouldShow = false
		},
        sellableIcon = {
            shouldShow = false
        }
	}
end

function CustomerOrdersMixin:OnSchematicFormInit(frame, recipeInfo)
    C_Timer.After(0, function ()
        local button = ProfessionsCustomerOrdersFrame.Form.OutputIcon
        local recipeID = ProfessionsCustomerOrdersFrame.Form.order.transaction:GetRecipeID();
		local reagents = nil;
		local outputItemInfo = C_TradeSkillUI.GetRecipeOutputItemData(recipeID, reagents, recipeInfo.transaction:GetRecraftAllocation());

        local options = {
        }

        local itemLink = outputItemInfo.hyperlink
        if itemLink then
            local item = CaerdonItem:CreateFromItemLink(itemLink)
            CaerdonWardrobe:UpdateButton(button, item, self, { 
                locationKey = format("selectedrecipe%d",  item:GetItemID()),
                selectedRecipeID =  recipeID
            }, options)
        else
            local recipeSchematic = ProfessionsCustomerOrdersFrame.Form.order.transaction:GetRecipeSchematic()
            local item = CaerdonItem:CreateFromItemID(recipeSchematic.outputItemID)
            CaerdonWardrobe:UpdateButton(button, item, self, { 
                locationKey = format("selectedrecipe%d",  item:GetItemID()),
                selectedRecipeID =  recipeID
            }, options)
            end
    end)
end

CaerdonWardrobe:RegisterFeature(CustomerOrdersMixin)
