CaerdonProfession = {}
CaerdonProfessionMixin = {}

--[[static]] function CaerdonProfession:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonProfession:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonWardrobeItemDataMixin, CaerdonProfessionMixin)
    itemType.item = caerdonItem
    return itemType
end

function CaerdonProfessionMixin:GetProfessionInfo()
    local result = {
        needsItem = false
    }

    local hasSkillLine, meetsMinRank, rank, maxRank = CaerdonRecipe:GetPlayerSkillInfo(self.item, self.item:GetItemSubType(), 0)
    if hasSkillLine and C_TradeSkillUI.GetSkillLineForGear then
        local skillLine = C_TradeSkillUI.GetSkillLineForGear(self.item:GetItemLink()) --itemInfo
        if skillLine then
            local professionInfo = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLine)
            local slots = C_TradeSkillUI.GetProfessionSlots(professionInfo.profession)

            local accessoryGears = {}
            local toolGear = nil

            for i = 1, #slots do
                local currentEquippedLink = nil

                -- TODO: This will capture slots with equipment, but is there a way to get the inventory type for an unequipped slot?  Making assumption of one tool and many accessories for now.
                local equipLocation = ItemLocation:CreateFromEquipmentSlot(slots[i])
                if equipLocation and equipLocation:HasAnyLocation() and equipLocation:IsValid() then
                    currentEquippedLink = GetInventoryItemLink("player", slots[i])
        
                    local slotType = C_Item.GetItemInventoryType(equipLocation)
                    if slotType == Enum.InventoryType.IndexProfessionToolType then
                        if not toolGearLink then
                            toolGear = { link = currentEquippedLink, location = equipLocation }
                        else
                            error("Unexpected secondary profession tool.  Has: " .. toolGearLink .. ", Adding: " .. currentEquippedLink)
                        end
                    elseif slotType == Enum.InventoryType.IndexProfessionGearType then
                        accessoryGears[#accessoryGears + 1] = { link = currentEquippedLink, location = equipLocation }
                    else
                        error("Unexpected profession inventory type: " .. tostring(slotType))
                    end
                end

                -- TODO: Do I need to do this if I have the logic outside the loop to evaluate each type?  Only thing is that this can accurately
                -- account for things I may not have (with regard to GetInventoryItemsForSlot)... skipping for now
                -- if self.item:HasItemLocation() then
                --     local availableItems = {};
                --     GetInventoryItemsForSlot(slots[i], availableItems);

                --     local packedLocation, itemLink
                --     for packedLocation, checkLink in pairs(availableItems) do
                --         if checkLink == self.item:GetItemLink() then
                --             if not currentEquippedLink then
                --                 result.needsItem = true
                --             else
                --                 local equippedItemLevel = C_Item.GetCurrentItemLevel(equipLocation)
                --                 if equippedItemLevel < self.item:GetCurrentItemLevel() then
                --                     result.needsItem = true
                --                 end
                --             end
                --         end
                --     end
                -- end
            end

            if not needsItem then
                local inventoryType = self.item:GetInventoryType()
                if inventoryType == Enum.InventoryType.IndexProfessionToolType then
                    if not toolGear then
                        result.needsItem = true
                    else
                        local equippedItemLevel = C_Item.GetCurrentItemLevel(toolGear.location)
                        if equippedItemLevel < self.item:GetCurrentItemLevel() then
                            result.needsItem = true
                        end
                    end
                elseif inventoryType == Enum.InventoryType.IndexProfessionGearType then
                    if #accessoryGears == 0 then
                        result.needsItem = true
                    else
                        local matchingItem = nil
                        for i = 1, #accessoryGears do
                            local accessoryGear = accessoryGears[i]
                            -- local tooltipInfo = C_TooltipInfo.GetHyperlink(accessoryGear.link)
                            -- DevTools_Dump(tooltipInfo)
                            local isUnique, limitCategoryName, limitCategoryCount, limitCategoryID = C_Item.GetItemUniquenessByID(accessoryGear.link)
                            if isUnique and limitCategoryCount == 1 then -- assuming we can just equip if more than one of the category is allowed
                                local itemCategoryID = select(4, C_Item.GetItemUniquenessByID(self.item:GetItemLink()))
                                if itemCategoryID == limitCategoryID then
                                    matchingItem = accessoryGear
                                end
                            end
                        end

                        if not matchingItem and #accessoryGears < #slots - 1 then -- Didn't find a similar unique item and have an open slot
                            result.needsItem = true
                        elseif matchingItem then
                            local equippedItemLevel = C_Item.GetCurrentItemLevel(matchingItem.location)
                            if equippedItemLevel < self.item:GetCurrentItemLevel() then
                                result.needsItem = true
                            end
                        end
                    end
                end
            end
        end
    end

    return result
end
