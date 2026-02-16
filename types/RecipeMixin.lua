CaerdonRecipe = {}
CaerdonRecipeMixin = {}

local PlayerProfessionData
local PlayerRecipeData

local function EnsureVariables()
    -- To reset for now:
    -- CaerdonRecipeData = {}
    -- CaerdonProfessionData = {}

    -- Initialize per-character table for known recipes
    local playerName = UnitName("player")
    local realmName = GetRealmName()

    if not CaerdonProfessionData then
        CaerdonProfessionData = {}
    end

    if not CaerdonProfessionData[realmName] then
        CaerdonProfessionData[realmName] = {}
    end

    if not CaerdonProfessionData[realmName][playerName] then
        CaerdonProfessionData[realmName][playerName] = {}
    end

    PlayerProfessionData = CaerdonProfessionData[realmName][playerName]

    -- Initialize the global table for recipe name to ID mapping
    if not CaerdonRecipeData then
        CaerdonRecipeData = {}
    end

    if not CaerdonRecipeData.globalRecipeNameToID then
        CaerdonRecipeData.globalRecipeNameToID = {}
    end

    if not CaerdonRecipeData[realmName] then
        CaerdonRecipeData[realmName] = {}
    end

    if not CaerdonRecipeData[realmName][playerName] then
        CaerdonRecipeData[realmName][playerName] = {}
    end

    if not CaerdonRecipeData[realmName][playerName].knownRecipes then
        CaerdonRecipeData[realmName][playerName].knownRecipes = {}
    end

    PlayerRecipeData = CaerdonRecipeData[realmName][playerName]
end

local eventFrame = CreateFrame("Frame")
local knownRecipes = {}

-- Function to gather known recipes when the player opens the profession window
local function GatherRecipes()
    if not C_TradeSkillUI.IsTradeSkillReady() then
        return
    end

    -- Get all known recipe IDs
    local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()

    -- Store recipe info
    for _, recipeID in ipairs(recipeIDs) do
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if recipeInfo then
            CaerdonRecipeData.globalRecipeNameToID[recipeInfo.name] = recipeID

            if recipeInfo.learned then
                PlayerRecipeData.knownRecipes[recipeInfo.name] = recipeID
            end
        end
    end
end

-- Function to cache individual profession skill lines (specializations)
local function CacheSkillLine(skillLineID)
    local skillLineInfo = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLineID)
    local playerProfession = PlayerProfessionData

    -- DevTools_Dump(skillLineInfo)
    if skillLineInfo then
        if skillLineInfo.parentProfessionName then
            PlayerProfessionData[skillLineInfo.parentProfessionName] = PlayerProfessionData[skillLineInfo.parentProfessionName] or {}
            PlayerProfessionData[skillLineInfo.parentProfessionName].childSkillLines = PlayerProfessionData[skillLineInfo.parentProfessionName].childSkillLines or {}
            playerProfession = PlayerProfessionData[skillLineInfo.parentProfessionName].childSkillLines
        end

        playerProfession[skillLineInfo.professionName] = playerProfession[skillLineInfo.professionName] or {}
        
        local knownSkillLevel = playerProfession[skillLineInfo.professionName].skillLevel
        if not knownSkillLevel or knownSkillLevel < skillLineInfo.skillLevel then
            -- Store skill line data in the cache
            playerProfession[skillLineInfo.professionName] = {
                skillLineID = skillLineID,
                skillName = skillLineInfo.professionName,
                skillLevel = skillLineInfo.skillLevel
            }
            -- print(skillLineInfo.professionName .. " (" .. skillLineID .. ") cached with skill level: " .. skillLineInfo.skillLevel .. "/" .. skillLineInfo.maxSkillLevel)
        end
    end
end

local function ResetMissingProfessionLevel()
    -- Reset skill level for any currently unlearned ones
    local currentProfessionSlots  = { GetProfessions() }
    local currentProfessions = {}

    for _, currentProfessionSlotID in pairs(currentProfessionSlots) do
        local name, _, skillLevel, maxSkillLevel = GetProfessionInfo(currentProfessionSlotID)
        currentProfessions[name] = true
    end

    for professionIndex, professionData in pairs(PlayerProfessionData) do
        if professionData.childSkillLines then
            if not currentProfessions[professionIndex] then
                for professionChildIndex, professionChildData in pairs(professionData.childSkillLines) do
                    if professionChildData then
                        professionChildData.skillLevel = 0
                    end
                end
            end
        end
    end
end

-- Function to gather and cache all profession data including specializations
local function GatherAllProfessionData()
    if C_TradeSkillUI.IsTradeSkillReady() then
        ResetMissingProfessionLevel()

        -- Get all known skill lines (includes parent and specializations)
        local skillLines = C_TradeSkillUI.GetAllProfessionTradeSkillLines()
        for _, skillLineID in ipairs(skillLines) do
            CacheSkillLine(skillLineID)
        end

        local childProfessionInfos = C_TradeSkillUI.GetChildProfessionInfos()
        for childProfessionIndex = 1, #childProfessionInfos do
            local info = childProfessionInfos[childProfessionIndex]
            CacheSkillLine(info.professionID)
        end
    end
end

-- Register for event when the trade skill data source changes
eventFrame:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("SKILL_LINES_CHANGED")
eventFrame:RegisterEvent("SKILL_LINE_SPECS_UNLOCKED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "VARIABLES_LOADED" then
        -- DevTools_Dump(CaerdonRecipeData.globalRecipeNameToID)
        -- DevTools_Dump(PlayerRecipeData.knownRecipes)
        EnsureVariables()
        GatherAllProfessionData()
    elseif event == "PLAYER_ENTERING_WORLD" then
        EnsureVariables()
        ResetMissingProfessionLevel()
        GatherAllProfessionData()
    elseif event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        -- print("Trade skills changed")
        GatherAllProfessionData()
        GatherRecipes()
    elseif event == "NEW_RECIPE_LEARNED" then
        local recipeID = ...
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if recipeInfo then
            CaerdonRecipeData.globalRecipeNameToID[recipeInfo.name] = recipeID
            PlayerRecipeData.knownRecipes[recipeInfo.name] = recipeID
        end
    elseif event == "SKILL_LINES_CHANGED" then
        -- print("Skill lines CHANGED")
        GatherAllProfessionData()
    end
end)

-- Function to check if a recipe is known based on previously gathered data
function GetRecipe(item)
    -- print(item:GetItemLink())
    local checkName = item:GetItemName()
    local recipeName = string.gsub(checkName or "", "Recipe: ", "")
    recipeName = string.gsub(recipeName, "Schematic: ", "")
    recipeName = string.gsub(recipeName, "Design: ", "")
    recipeName = string.gsub(recipeName, "Plans: ", "")
    recipeName = string.gsub(recipeName, "Pattern: ", "")

    local recipeID = CaerdonRecipeData.globalRecipeNameToID[recipeName]
    if recipeID then
        -- DevTools_Dump(C_TradeSkillUI.GetRecipeInfo(recipeID))
        return C_TradeSkillUI.GetRecipeInfo(recipeID)
    else
        -- print("Unknown recipe " .. recipeName)
        return nil
    end
end

function CaerdonRecipe:GetPlayerSkillInfo(item, requiredSkill, requiredRank)
    -- print(item:GetItemLink() .. requiredSkill .. requiredRank)
    local hasSkillLine = false
    local meetsMinRank = false
    local rank, professionInfo

    -- local itemData = item:GetItemData()
    -- if itemData and itemData.recipe then
    --     local recipeID = itemData.recipe.recipeID
    --     professionInfo = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
    --     if requiredSkill ~= professionInfo.professionName then
    --         professionInfo = nil
    --     end
    -- end

    -- if not professionInfo or professionInfo.skillLevel == 0 then
    professionInfo = PlayerProfessionData[requiredSkill]
    if not professionInfo then
        for professionIndex, professionData in pairs(PlayerProfessionData) do
            if professionData.childSkillLines then
                professionInfo = professionData.childSkillLines[requiredSkill]
                if professionInfo then
                    break
                end
            end
        end
    end
    -- end

    if professionInfo then
        if professionInfo.skillLevel and professionInfo.skillLevel > 0 then
            hasSkillLine = true
            rank = professionInfo.skillLevel
        end

        local requiredRankNum = tonumber(requiredRank)
        if professionInfo.skillLevel and requiredRankNum and professionInfo.skillLevel >= requiredRankNum then
            meetsMinRank = true
        end
    end

    if not hasSkillLine then
        local prof1, prof2, arch, fishing, cooking = GetProfessions()
        local professionIDs = {prof1, prof2, arch, fishing, cooking}
        for _, professionID in pairs(professionIDs) do
            if professionID then
                local name, _, skillLevel, maxSkillLevel = GetProfessionInfo(professionID)
                if item:GetItemSubType() == name then
                    hasSkillLine = true
                    meetsMinRank = false
                end
            end
        end
    end

    return hasSkillLine, meetsMinRank, rank
end

--[[static]] function CaerdonRecipe:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonRecipe:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonWardrobeItemDataMixin, CaerdonRecipeMixin)
    itemType.item = caerdonItem

    if caerdonItem.extraData and caerdonItem.extraData.recipeInfo then
        itemType.recipe = caerdonItem.extraData.recipeInfo
    end

    -- local itemID = caerdonItem:GetItemID()
    -- local quality = caerdonItem:GetItemQuality()
    -- print(caerdonItem:GetItemLink() .. ", Item ID: " .. tostring(itemID) .. ", " .. tostring(quality))

    -- if not itemType.recipe and itemID and quality then
    --     local spellID = C_Item.GetFirstTriggeredSpellForItem(itemID, quality)
    --     if spellID then
    --         local spellInfo = C_Spell.GetSpellInfo(spellID)
    --         local recipeInfo = C_TradeSkillUI.GetRecipeInfo(spellID)
    --         itemType.recipe = recipeInfo
    --         print(recipeInfo.recipeID)
    --     end
    -- end

    if not itemType.recipe then
        itemType.recipe, itemType.hasProfession = GetRecipe(itemType.item)
    end

    return itemType
end

function CaerdonRecipeMixin:LoadCreatedItems(callbackFunction)
    local item = self.item

    -- Lazy re-evaluation (same as GetRecipeInfo)
    if not self.recipe and item then
        self.recipe = GetRecipe(item)
    end

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

    -- Call callback immediately. The recipe's own status (learned/canLearn)
    -- doesn't require the created item to be loaded first. Waiting for it
    -- via LoadCreatedItems delays UpdateButton, which prevents the icon from
    -- appearing on merchant items before the display settles.
    callbackFunction()
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

    -- Lazy re-evaluation: if recipe was nil at creation time (e.g. merchant items
    -- where GetItemName() wasn't available yet), retry now that data may be loaded.
    if not self.recipe and item then
        self.recipe = GetRecipe(item)
    end

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
        result.canLearn = not result.learned and C_TradeSkillUI.IsRecipeProfessionLearned(self.recipe.recipeID)

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