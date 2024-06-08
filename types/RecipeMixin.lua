CaerdonRecipe = {}
CaerdonRecipeMixin = {}

local TradeSkillLines = {
    [171] = { title = "Alchemy" },
        [2823] = { title = "Dragon Isles Alchemy", parentID = 171, expansionID = 9 },
        [2750] = { title = "Shadowlands Alchemy", parentID = 171, expansionID = 8 },
        [2478] = { title = "Battle for Azeroth Alchemy", parentID = 171, expansionID = 7 },
        [2479] = { title = "Legion Alchemy", parentID = 171, expansionID = 6 },
        [2480] = { title = "Draenor Alchemy", parentID = 171, expansionID = 5 },
        [2481] = { title = "Pandaria Alchemy", parentID = 171, expansionID = 4 },
        [2482] = { title = "Cataclysm Alchemy", parentID = 171, expansionID = 3 },
        [2483] = { title = "Northrend Alchemy", parentID = 171, expansionID = 2 },
        [2484] = { title = "Outland Alchemy", parentID = 171, expansionID = 1 },
        [2485] = { title = "Alchemy", parentID = 171, expansionID = 0 },

    [794] = { title = "Archaeology" },

    [164] = { title = "Blacksmithing" },
        [2822] = { title = "Dragon Isles Blacksmithing", parentID = 164, expansionID = 9 },
        [2751] = { title = "Shadowlands Blacksmithing", parentID = 164, expansionID = 8 },
        [2437] = { title = "Battle for Azeroth Blacksmithing", parentID = 164, expansionID = 7 },
        [2454] = { title = "Legion Blacksmithing", parentID = 164, expansionID = 6 },
        [2472] = { title = "Draenor Blacksmithing", parentID = 164, expansionID = 5 },
        [2473] = { title = "Pandaria Blacksmithing", parentID = 164, expansionID = 4 },
        [2474] = { title = "Cataclysm Blacksmithing", parentID = 164, expansionID = 3 },
        [2475] = { title = "Northrend Blacksmithing", parentID = 164, expansionID = 2 },
        [2476] = { title = "Outland Blacksmithing", parentID = 164, expansionID = 1 },
        [2477] = { title = "Blacksmithing", parentID = 164, expansionID = 0 },

    [185] = { title = "Cooking" },
        [2824] = { title = "Dragon Isles Cooking", parentID = 185, expansionID = 9 },
        [2752] = { title = "Shadowlands Cooking", parentID = 185, expansionID = 8 },
        [2541] = { title = "Battle for Azeroth Cooking", parentID = 185, expansionID = 7 },
        [2542] = { title = "Legion Cooking", parentID = 185, expansionID = 6 },
        [2543] = { title = "Draenor Cooking", parentID = 185, expansionID = 5 },
        [2544] = { title = "Pandaria Cooking", parentID = 185, expansionID = 4 },
            -- Pandaria cooking specializations
            [980] = { title = "Way of the Brew", parentID = 185, expansionID = 4 },
            [975] = { title = "Way of the Grill", parentID = 185, expansionID = 4 },
            [979] = { title = "Way of the Oven", parentID = 185, expansionID = 4 },
            [977] = { title = "Way of the Pot", parentID = 185, expansionID = 4 },
            [978] = { title = "Way of the Steamer", parentID = 185, expansionID = 4 },
            [976] = { title = "Way of the Wok", parentID = 185, expansionID = 4 },
        [2545] = { title = "Cataclysm Cooking", parentID = 185, expansionID = 3 },
        [2546] = { title = "Northrend Cooking", parentID = 185, expansionID = 2 },
        [2547] = { title = "Outland Cooking", parentID = 185, expansionID = 1 },
        [2548] = { title = "Cooking", parentID = 185, expansionID = 0 },

    [333] = { title = "Enchanting" },
        [2825] = { title = "Dragon Isles Enchanting", parentID = 333, expansionID = 9 },
        [2753] = { title = "Shadowlands Enchanting", parentID = 333, expansionID = 8 },
        [2486] = { title = "Battle for Azeroth Enchanting", parentID = 333, expansionID = 7 },
        [2487] = { title = "Legion Enchanting", parentID = 333, expansionID = 6 },
        [2488] = { title = "Draenor Enchanting", parentID = 333, expansionID = 5 },
        [2489] = { title = "Pandaria Enchanting", parentID = 333, expansionID = 4 },
        [2491] = { title = "Cataclysm Enchanting", parentID = 333, expansionID = 3 },
        [2492] = { title = "Northrend Enchanting", parentID = 333, expansionID = 2 },
        [2493] = { title = "Outland Enchanting", parentID = 333, expansionID = 1 },
        [2494] = { title = "Enchanting", parentID = 333, expansionID = 0 },

    [202] = { title = "Engineering" },
        [2827] = { title = "Dragon Isles Engineering", parentID = 202, expansionID = 9 },
        [2755] = { title = "Shadowlands Engineering", parentID = 202, expansionID = 8 },
        [2499] = { title = "Battle for Azeroth Engineering", parentID = 202, expansionID = 7 },
        [2500] = { title = "Legion Engineering", parentID = 202, expansionID = 6 },
        [2501] = { title = "Draenor Engineering", parentID = 202, expansionID = 5 },
        [2502] = { title = "Pandaria Engineering", parentID = 202, expansionID = 4 },
        [2503] = { title = "Cataclysm Engineering", parentID = 202, expansionID = 3 },
        [2504] = { title = "Northrend Engineering", parentID = 202, expansionID = 2 },
        [2505] = { title = "Outland Engineering", parentID = 202, expansionID = 1 },
        [2506] = { title = "Engineering", parentID = 202, expansionID = 0 },

    [356] = { title = "Fishing" },
        [2826] = { title = "Dragon Isles Fishing", parentID = 356, expansionID = 9 },
        [2754] = { title = "Shadowlands Fishing", parentID = 356, expansionID = 8 },
        [2585] = { title = "Battle for Azeroth Fishing", parentID = 356, expansionID = 8 },
        [2586] = { title = "Legion Fishing", parentID = 356, expansionID = 7 },
        [2587] = { title = "Draenor Fishing", parentID = 356, expansionID = 5 },
        [2588] = { title = "Pandaria Fishing", parentID = 356, expansionID = 4 },
        [2589] = { title = "Cataclysm Fishing", parentID = 356, expansionID = 3 },
        [2590] = { title = "Northrend Fishing", parentID = 356, expansionID = 2 },
        [2591] = { title = "Outland Fishing", parentID = 356, expansionID = 1 },
        [2592] = { title = "Fishing", parentID = 356, expansionID = 0 },

    [182] = { title = "Herbalism" },
        [2832] = { title = "Dragon Isles Herbalism", parentID = 182, expansionID = 9 },
        [2760] = { title = "Shadowlands Herbalism", parentID = 182, expansionID = 8 },
        [2549] = { title = "Battle for Azeroth Herbalism", parentID = 182, expansionID = 7 },
        [2550] = { title = "Legion Herbalism", parentID = 182, expansionID = 6 },
        [2551] = { title = "Draenor Herbalism", parentID = 182, expansionID = 5 },
        [2552] = { title = "Pandaria Herbalism", parentID = 182, expansionID = 4 },
        [2553] = { title = "Cataclysm Herbalism", parentID = 182, expansionID = 3 },
        [2554] = { title = "Northrend Herbalism", parentID = 182, expansionID = 2 },
        [2555] = { title = "Outland Herbalism", parentID = 182, expansionID = 1 },
        [2556] = { title = "Herbalism", parentID = 182, expansionID = 0 },

    [773] = { title = "Inscription" },
        [2756] = { title = "Dragon Isles Inscription", parentID = 773, expansionID = 9 },
        [2756] = { title = "Shadowlands Inscription", parentID = 773, expansionID = 8 },
        [2507] = { title = "Battle for Azeroth Inscription", parentID = 773, expansionID = 7 },
        [2508] = { title = "Legion Inscription", parentID = 773, expansionID = 6 },
        [2509] = { title = "Draenor Inscription", parentID = 773, expansionID = 5 },
        [2510] = { title = "Pandaria Inscription", parentID = 773, expansionID = 4 },
        [2511] = { title = "Cataclysm Inscription", parentID = 773, expansionID = 3 },
        [2512] = { title = "Northrend Inscription", parentID = 773, expansionID = 2 },
        [2513] = { title = "Outland Inscription", parentID = 773, expansionID = 1 },
        [2514] = { title = "Inscription", parentID = 773, expansionID = 0 },

    [755] = { title = "Jewelcrafting" },
        [2829] = { title = "Dragon Isles Jewelcrafting", parentID = 755, expansionID = 9 },
        [2757] = { title = "Shadowlands Jewelcrafting", parentID = 755, expansionID = 8 },
        [2517] = { title = "Battle for Azeroth Jewelcrafting", parentID = 755, expansionID = 7 },
        [2518] = { title = "Legion Jewelcrafting", parentID = 755, expansionID = 6 },
        [2519] = { title = "Draenor Jewelcrafting", parentID = 755, expansionID = 5 },
        [2520] = { title = "Pandaria Jewelcrafting", parentID = 755, expansionID = 4 },
        [2521] = { title = "Cataclysm Jewelcrafting", parentID = 755, expansionID = 3 },
        [2522] = { title = "Northrend Jewelcrafting", parentID = 755, expansionID = 2 },
        [2523] = { title = "Outland Jewelcrafting", parentID = 755, expansionID = 1 },
        [2524] = { title = "Jewelcrafting", parentID = 755, expansionID = 0 },

    [165] = { title = "Leatherworking" },
        [2830] = { title = "Dragon Isles Leatherworking", parentID = 165, expansionID = 9 },
        [2758] = { title = "Shadowlands Leatherworking", parentID = 165, expansionID = 8 },
        [2525] = { title = "Battle for Azeroth Leatherworking", parentID = 165, expansionID = 7 },
        [2526] = { title = "Legion Leatherworking", parentID = 165, expansionID = 6 },
        [2527] = { title = "Draenor Leatherworking", parentID = 165, expansionID = 5 },
        [2528] = { title = "Pandaria Leatherworking", parentID = 165, expansionID = 4 },
        [2529] = { title = "Cataclysm Leatherworking", parentID = 165, expansionID = 3 },
        [2530] = { title = "Northrend Leatherworking", parentID = 165, expansionID = 2 },
        [2531] = { title = "Outland Leatherworking", parentID = 165, expansionID = 1 },
        [2532] = { title = "Leatherworking", parentID = 165, expansionID = 0 },

    [186] = { title = "Mining" },
        [2833] = { title = "Dragon Isles Mining", parentID = 186, expansionID = 9 },
        [2761] = { title = "Shadowlands Mining", parentID = 186, expansionID = 8 },
        [2565] = { title = "Battle for Azeroth Mining", parentID = 186, expansionID = 7 },
        [2566] = { title = "Legion Mining", parentID = 186, expansionID = 6 },
        [2567] = { title = "Draenor Mining", parentID = 186, expansionID = 5 },
        [2568] = { title = "Pandaria Mining", parentID = 186, expansionID = 4 },
        [2569] = { title = "Cataclysm Mining", parentID = 186, expansionID = 3 },
        [2570] = { title = "Northrend Mining", parentID = 186, expansionID = 2 },
        [2571] = { title = "Outland Mining", parentID = 186, expansionID = 1 },
        [2572] = { title = "Mining", parentID = 186, expansionID = 0 },

    [393] = { title = "Skinning" },
        [2834] = { title = "Dragon Isles Skinning", parentID = 393, expansionID = 9 },
        [2762] = { title = "Shadowlands Skinning", parentID = 393, expansionID = 8 },
        [2557] = { title = "Battle for Azeroth Skinning", parentID = 393, expansionID = 7 },
        [2558] = { title = "Legion Skinning", parentID = 393, expansionID = 6 },
        [2559] = { title = "Draenor Skinning", parentID = 393, expansionID = 5 },
        [2560] = { title = "Pandaria Skinning", parentID = 393, expansionID = 4 },
        [2561] = { title = "Cataclysm Skinning", parentID = 393, expansionID = 3 },
        [2562] = { title = "Northrend Skinning", parentID = 393, expansionID = 2 },
        [2563] = { title = "Outland Sknning", parentID = 393, expansionID = 1 },
        [2564] = { title = "Skinning", parentID = 393, expansionID = 0 },

    [197] = { title = "Tailoring" },
        [2831] = { title = "Dragon Isles Tailoring", parentID = 197, expansionID = 9 },
        [2759] = { title = "Shadowlands Tailoring", parentID = 197, expansionID = 8 },
        [2533] = { title = "Battle for Azeroth Tailoring", parentID = 197, expansionID = 7 },
        [2534] = { title = "Legion Tailoring", parentID = 197, expansionID = 6 },
        [2535] = { title = "Draenor Tailoring", parentID = 197, expansionID = 5 },
        [2536] = { title = "Pandaria Tailoring", parentID = 197, expansionID = 4 },
        [2537] = { title = "Cataclysm Tailoring", parentID = 197, expansionID = 3 },
        [2538] = { title = "Northrend Tailoring", parentID = 197, expansionID = 2 },
        [2539] = { title = "Outland Tailoring", parentID = 197, expansionID = 1 },
        [2540] = { title = "Tailoring", parentID = 197, expansionID = 0 },

    -- Misc
    [633] = { title = "Lockpicking" },
    [960] = { title = "Runeforging" },

    [2847] = { title = "Tuskarr Fishing Gear", expansionID = 9 },
    [2787] = { title = "Abominable Stitching", expansionID = 8 },
    [2791] = { title = "Ascension Crafting", expansionID = 8 },
    [2819] = { title = "Protoform Synthesis", expansionID = 8 },
    [2720] = { title = "Junkyard Tinkering", expansionID = 7 },
}

function CaerdonRecipe:GetPlayerSkillInfo(requiredSkill, requiredRank)
    local hasSkillLine = false
    local meetsMinRank = false
    local rank, maxRank

    for skillLineID, data in pairs(TradeSkillLines) do
        local professionInfo = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLineID)
        if requiredSkill == professionInfo.professionName then
            if professionInfo.skillLevel and professionInfo.skillLevel > 0 then
                hasSkillLine = true
                rank = professionInfo.skillLevel
                maxRank = professionInfo.maxSkillLevel
            else
                -- TODO: Fallback if TradeSkill UI hasn't been opened, yet - keep looking for a way to solve this.
                local parentSkillLine
                if data.parentID then
                    local parentInfo = C_TradeSkillUI.GetProfessionInfoBySkillLineID(data.parentID)
                    parentName = parentInfo.professionName
                end
                
                local prof1, prof2, arch, fish, cook = GetProfessions();

                -- TODO: This is so ugly... sort out how to throw into an array.
                local matchingProfession
                local name, texture, numSpells, spelloffset, skillLine, rankModifier, specializationIndex, specializationOffset, skillLineName
                if prof1 then
                    name, texture, rank, maxRank, numSpells, spelloffset, skillLine, rankModifier, specializationIndex, specializationOffset, skillLineName = GetProfessionInfo(prof1);
                    if skillLine == skillLineID or skillLine == data.parentID then
                        matchingProfession = prof1
                    end
                end

                if prof2 and not matchingProfession then
                    name, texture, rank, maxRank, numSpells, spelloffset, skillLine, rankModifier, specializationIndex, specializationOffset, skillLineName = GetProfessionInfo(prof2);
                    if skillLine == skillLineID or skillLine == data.parentID then
                        matchingProfession = prof2
                    end
                end

                if arch and not matchingProfession then
                    name, texture, rank, maxRank, numSpells, spelloffset, skillLine, rankModifier, specializationIndex, specializationOffset, skillLineName = GetProfessionInfo(arch);
                    if skillLine == skillLineID or skillLine == data.parentID then
                        matchingProfession = arch
                    end
                end

                if fish and not matchingProfession then
                    name, texture, rank, maxRank, numSpells, spelloffset, skillLine, rankModifier, specializationIndex, specializationOffset, skillLineName = GetProfessionInfo(fish);
                    if skillLine == skillLineID or skillLine == data.parentID then
                        matchingProfession = fish
                    end
                end

                if cook and not matchingProfession then
                    name, texture, rank, maxRank, numSpells, spelloffset, skillLine, rankModifier, specializationIndex, specializationOffset, skillLineName = GetProfessionInfo(cook);
                    if skillLine == skillLineID or skillLine == data.parentID then
                        matchingProfession = cook
                    end
                end

                if matchingProfession then
                    hasSkillLine = true

                    if skillLineName == requiredSkill and rank >= tonumber(requiredRank) then
                        meetsMinRank = true
                    end
                end
            end

            if professionInfo.skillLevel and professionInfo.skillLevel >= tonumber(requiredRank) then
                meetsMinRank = true
            end

            break
        end
    end

    return hasSkillLine, meetsMinRank, rank, maxRank
end



--[[static]] function CaerdonRecipe:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonRecipe:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonWardrobeItemDataMixin, CaerdonRecipeMixin)
    itemType.item = caerdonItem

    -- You would think one of these... but no.
    -- local recipeName, recipeID = C_Item.GetItemSpell(caerdonItem:GetItemID())
    -- local recipeName, recipeID = C_Item.GetItemSpell(caerdonItem:GetItemLocation())
    -- print(recipeName or "" .. ": " .. tostring(recipeID))

    -- local spellID = C_Item.GetFirstTriggeredSpellForItem(caerdonItem:GetItemID(), caerdonItem:GetItemQuality())
    -- if spellID then
    --     print("Spell ID: " .. spellID)
    -- end
    -- local spellName, spellID = C_Item.GetItemSpell(caerdonItem:GetItemLink())
    -- print(spellName)

    if caerdonItem.extraData and caerdonItem.extraData.recipeInfo then
        itemType.recipe = caerdonItem.extraData.recipeInfo
    end

    if not itemType.recipe then
        local checkName = caerdonItem:GetItemName()
        local recipeName = string.gsub(checkName or "", "Recipe: ", "")
        recipeName = string.gsub(recipeName, "Schematic: ", "")
        recipeName = string.gsub(recipeName, "Design: ", "")
        recipeName = string.gsub(recipeName, "Plans: ", "")

        -- local recipeSpellID = C_Spell.GetSpellIDForSpellIdentifier(recipeName)
        -- C_Spell.GetSpellTradeSkillLink(recipeName)
        -- if recipeSpellID then
        --     print("Spell ID: " .. recipeSpellID)
        --     local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeSpellID)
        --     if recipeInfo then
        --         DevTools_Dump(recipeInfo)
        --     end
        -- end

        itemType.recipe = nil

        -- TODO: This is not ideal, but I haven't identified a great way to get the recipe spell ID from the item ID.
        -- local loaded, reason = C_AddOns.LoadAddOn("Blizzard_Professions")
        -- DevTools_Dump("Loaded: " .. tostring(loaded) .. ", " .. tostring(reason))

        -- print("Loaded: " .. tostring(loaded) .. ", " .. tostring(reason))

        -- local lines = C_TradeSkillUI.GetAllProfessionTradeSkillLines()
        -- local lineIndex
        -- for lineIndex = 1, #lines do
        --     local professionInfo = C_TradeSkillUI.GetProfessionInfoBySkillLineID(lines[lineIndex])
        --     print(professionInfo.professionName)
        -- end

        -- local professionInfo = C_TradeSkillUI.GetProfessionInfoBySkillLineID(185)

        -- DevTools_Dump(lines)
        -- C_TradeSkillUI.CloseTradeSkill()
        -- DevTools_Dump(C_TradeSkillUI)

        -- local professionInfo = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLineID)
        -- C_TradeSkillUI.SetProfessionChildSkillLineID(professionInfo.professionID)

        -- local currBaseProfessionInfo = C_TradeSkillUI.GetBaseProfessionInfo();
        -- if currBaseProfessionInfo == nil or currBaseProfessionInfo.professionID ~= skillLineID then
            -- C_TradeSkillUI.OpenTradeSkill(185);
            -- CastSpellByName("Jewelcrafting")
        -- end

        -- TODO: Doesn't return secondary profession info
        -- local tradeSkillLineIDs = C_TradeSkillUI.GetAllProfessionTradeSkillLines()

        -- local tradeSkillIndex
        -- for tradeSkillIndex = 1, #tradeSkillLineIDs do
        --     local professionInfo = C_TradeSkillUI.GetProfessionInfoBySkillLineID(tradeSkillLineIDs[tradeSkillIndex])
        --     print(professionInfo.professionName)
        -- end

        -- for skill, data in pairs(TradeSkillLines) do
        --     local professionInfo = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skill)
        --     -- print(professionInfo.professionName)
        -- end

        local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs();
        -- DevTools_Dump(recipeIDs)
        local recipeIndex
        for recipeIndex = 1, #recipeIDs do
            local checkRecipe = C_TradeSkillUI.GetRecipeInfo(recipeIDs[recipeIndex]);
            -- print("Checking recipe: " .. checkRecipe.name .. " (" .. checkRecipe.recipeID .. ")")
            if checkRecipe.name == recipeName then
                -- print("Found recipe: " .. checkRecipe.name .. " (" .. checkRecipe.recipeID .. ")")
                itemType.recipe = checkRecipe;
                break
            end
        end
    end

    return itemType
end

function CaerdonRecipeMixin:LoadCreatedItems(callbackFunction)
    local item = self.item

    local continuableContainer = ContinuableContainer:Create();
    local cancelFunc = function() end;

    if self.recipe then
        local schematic = C_TradeSkillUI.GetRecipeSchematic(self.recipe.recipeID, false)
        -- TODO: Probably more to do here...
        -- C_TradeSkillUI.GetFactionSpecificOutputItem
        -- DevTools_Dump(schematic)

        if not schematic or not schematic.outputItemID or schematic.outputItemID == item:GetItemID() then -- Some recipes that didn't craft items were self-referential for some reason...
            callbackFunction()
        else
            local item = CaerdonItem:CreateFromItemID(schematic.outputItemID)
            if not item:IsItemEmpty() then
                continuableContainer:AddContinuable(item);
            end

            cancelFunc = continuableContainer:ContinueOnLoad(callbackFunction);
        end
    else
        callbackFunction()
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
    local result = {
        schematic = nil,
        firstCraft = false,
        learned = false,
        createdItem = nil,
        canLearn = false
    }

    if self.recipe then
        result.schematic = C_TradeSkillUI.GetRecipeSchematic(self.recipe.recipeID, false)

        result.firstCraft = self.recipe.firstCraft
        result.learned = self.recipe.learned or false
        result.createdItem = nil
        result.canLearn = C_TradeSkillUI.IsRecipeProfessionLearned(self.recipe.recipeID)

        if result.schematic.outputItemID ~= nil then
            result.createdItem = CaerdonItem:CreateFromItemID(result.schematic.outputItemID)
        end
    else
        result = nil
    end

    -- TODO: Still lots that could likely be evaluated / added here
    -- DevTools_Dump(self.recipe)
    -- DevTools_Dump(C_TradeSkillUI.GetCategoryInfo(self.recipe.categoryID))
    return result
end