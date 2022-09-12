CaerdonRecipe = {}
CaerdonRecipeMixin = {}

--[[static]] function CaerdonRecipe:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonRecipe:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonWardrobeItemDataMixin, CaerdonRecipeMixin)
    itemType.item = caerdonItem

    -- You would think this one... but no.
    -- local recipeName, recipeID = GetItemSpell(item:GetItemID())
    local recipeName = string.gsub(string.gsub(caerdonItem:GetItemName(), "Recipe: ", ""), "Schematic: ", "")
    self.recipe = nil

    -- TODO: This is not ideal, but I haven't identified a great way to get the recipe spell ID from the item ID.
    local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs();
    for id = 1, #recipeIDs do
      local checkRecipe = C_TradeSkillUI.GetRecipeInfo(recipeIDs[id]);
      if checkRecipe.name == recipeName then
        itemType.recipe = checkRecipe;
        break
      end
    end

    return itemType
end

function CaerdonRecipeMixin:LoadCreatedItems(callbackFunction)
    local item = self.item

    local continuableContainer = ContinuableContainer:Create();
    local cancelFunc = function() end;

    local schematic = C_TradeSkillUI.GetRecipeSchematic(self.recipe.recipeID, false)
    -- TODO: Probably more to do here...
    -- C_TradeSkillUI.GetFactionSpecificOutputItem
    -- DevTools_Dump(schematic)

    if not schematic or not schematic.outputItemID then
        callbackFunction()
    else
        local item = CaerdonItem:CreateFromItemID(schematic.outputItemID)
        if not item:IsItemEmpty() then
            continuableContainer:AddContinuable(item);
        end

        cancelFunc = continuableContainer:ContinueOnLoad(callbackFunction);
    end

    return cancelFunc
end

function CaerdonRecipeMixin:ContinueOnItemDataLoad(callbackFunction)
    if type(callbackFunction) ~= "function" or self.item:IsItemEmpty() then
        error("Usage: NonEmptyItem:ContinueOnLoad(callbackFunction)", 2);
    end

    self:LoadCreatedItems(callbackFunction)
end

-- Allows for override of continue return if additional data needs to get loaded from a specific mixin (i.e. created items)
function CaerdonRecipeMixin:ContinueWithCancelOnItemDataLoad(callbackFunction)
    if type(callbackFunction) ~= "function" or self.item:IsItemEmpty() then
        error("Usage: NonEmptyItem:ContinueOnLoad(callbackFunction)", 2);
    end

    return self:LoadCreatedItems(callbackFunction)
end

function CaerdonRecipeMixin:GetRecipeInfo()
    local item = self.item

    local schematic = C_TradeSkillUI.GetRecipeSchematic(self.recipe.recipeID, false)

    local learned = self.recipe.learned or false
    local createdItem = nil
    local canLearn = C_TradeSkillUI.IsRecipeProfessionLearned(self.recipe.recipeID)

    if schematic.outputItemID ~= nil then
        createdItem = CaerdonItem:CreateFromItemID(schematic.outputItemID)
    end

    -- TODO: Still lots that could likely be evaluated / added here
    -- DevTools_Dump(self.recipe)
    -- DevTools_Dump(C_TradeSkillUI.GetCategoryInfo(self.recipe.categoryID))
    return {
        learned = learned,
        createdItem = createdItem,
        canLearn = canLearn
    }
end