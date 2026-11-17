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

    -- Professions whose full recipe list has been read into knownRecipes at least once, keyed by
    -- profession name. Without an entry, "not in knownRecipes" only means "never looked".
    if not CaerdonRecipeData[realmName][playerName].scannedProfessions then
        CaerdonRecipeData[realmName][playerName].scannedProfessions = {}
    end

    -- Tools this toon's own recipes ask for, by profession name:
    -- { skillLine = base profession skill line, names = { [tool name] = true } }.
    -- Read by CaerdonProfessionTools.
    if not CaerdonRecipeData[realmName][playerName].tools then
        CaerdonRecipeData[realmName][playerName].tools = {}
    end

    PlayerRecipeData = CaerdonRecipeData[realmName][playerName]
end

local eventFrame = CreateFrame("Frame")
local knownRecipes = {}

-- Calls a C_TradeSkillUI function that may not exist on every client; nil when it does not.
local function TradeSkillCall(name, ...)
    local func = C_TradeSkillUI[name]
    if type(func) ~= "function" then
        return nil
    end
    return func(...)
end

-- The profession window can show someone else's recipes (a linked profession, the guild's, a
-- guild member's) or an NPC's; "learned" then says nothing about this toon.
local function IsOwnTradeSkill()
    return not (TradeSkillCall("IsTradeSkillLinked") or TradeSkillCall("IsTradeSkillGuild") or
        TradeSkillCall("IsTradeSkillGuildMember") or TradeSkillCall("IsNPCCrafting"))
end

-- GetFilteredRecipeIDs returns what the recipe list currently shows, so a search text or a
-- "have materials" style filter makes it a partial list. Only an unfiltered list that includes
-- the learned recipes says anything about a recipe that is absent from it.
local function IsRecipeListUnfiltered()
    if TradeSkillCall("GetOnlyShowMakeableRecipes") or TradeSkillCall("GetOnlyShowSkillUpRecipes") or
        TradeSkillCall("GetOnlyShowFirstCraftRecipes") then
        return false
    end
    if TradeSkillCall("GetShowLearned") == false then
        return false
    end
    if TradeSkillCall("AreAnyInventorySlotsFiltered") or TradeSkillCall("AnyRecipeCategoriesFiltered") then
        return false
    end
    local nameFilter = TradeSkillCall("GetRecipeItemNameFilter")
    if nameFilter and nameFilter ~= "" then
        return false
    end
    return true
end

-- Saves the tools the open profession's recipes ask for ("Tools: Arclight Spanner, Blacksmith
-- Hammer" on the recipe form, which Blizzard builds from the same call). Recipes the toon has
-- not learned yet count too: they name the tools it will need. Names are only ever added.
local function RecordRecipeTools(recipeIDs)
    if type(C_TradeSkillUI.GetRecipeRequirements) ~= "function" then
        return
    end

    local baseInfo = TradeSkillCall("GetBaseProfessionInfo")
    local professionName = baseInfo and (baseInfo.parentProfessionName or baseInfo.professionName)
    if not professionName or professionName == "" then
        return
    end

    local toolType = Enum.RecipeRequirementType and Enum.RecipeRequirementType.Totem or 1
    local entry = PlayerRecipeData.tools[professionName]
    local added = false
    for _, recipeID in ipairs(recipeIDs) do
        local ok, requirements = pcall(C_TradeSkillUI.GetRecipeRequirements, recipeID)
        if ok and type(requirements) == "table" then
            for _, requirement in ipairs(requirements) do
                local toolName = requirement.type == toolType and requirement.name
                if type(toolName) == "string" and toolName ~= "" then
                    if not entry then
                        entry = { names = {} }
                        PlayerRecipeData.tools[professionName] = entry
                    end
                    entry.names = entry.names or {}
                    if not entry.names[toolName] then
                        entry.names[toolName] = true
                        added = true
                    end
                end
            end
        end
    end

    if entry then
        entry.skillLine = baseInfo.parentProfessionID or baseInfo.professionID or entry.skillLine
    end
    if added and CaerdonProfessionTools then
        CaerdonProfessionTools:OnToolsRecorded()
    end
end

-- Function to gather known recipes when the player opens the profession window
local function GatherRecipes()
    if not C_TradeSkillUI.IsTradeSkillReady() then
        return
    end

    -- Get all known recipe IDs. GetAllRecipeIDs is undocumented, so fall back to
    -- the documented filtered list on clients (e.g. WoW Forever) that lack it.
    local hasFullList = C_TradeSkillUI.GetAllRecipeIDs ~= nil
    local getRecipeIDs = C_TradeSkillUI.GetAllRecipeIDs or C_TradeSkillUI.GetFilteredRecipeIDs
    local recipeIDs = getRecipeIDs and getRecipeIDs() or {}
    local isOwn = IsOwnTradeSkill()

    -- Store recipe info
    for _, recipeID in ipairs(recipeIDs) do
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if recipeInfo then
            CaerdonRecipeData.globalRecipeNameToID[recipeInfo.name] = recipeID

            if recipeInfo.learned and isOwn then
                PlayerRecipeData.knownRecipes[recipeInfo.name] = recipeID
            end
        end
    end

    -- Remember that this profession's list is now complete, so other toons can tell "does not
    -- know the recipe" from "never looked" (CaerdonRecipe:GetOtherToonRecipeInfo).
    if isOwn and #recipeIDs > 0 and (hasFullList or IsRecipeListUnfiltered()) then
        local baseInfo = TradeSkillCall("GetBaseProfessionInfo")
        local professionName = baseInfo and (baseInfo.parentProfessionName or baseInfo.professionName)
        if professionName and professionName ~= "" then
            PlayerRecipeData.scannedProfessions[professionName] = true
        end
    end

    if isOwn then
        RecordRecipeTools(recipeIDs)
    end
end

-- The tools this toon's recipes ask for, as saved by RecordRecipeTools (nil before the saved
-- variables are loaded).
function CaerdonRecipe:GetRecordedTools()
    return PlayerRecipeData and PlayerRecipeData.tools
end

-- For the refresh watcher (CaerdonRefresh.lua): the ranks saved for this toon, which a recipe's
-- verdict reads through FindSkillLine. Adds one key per skill line to the reading.
function CaerdonRecipe:AddSkillReading(reading)
    if type(PlayerProfessionData) ~= "table" then
        return
    end
    for name, entry in pairs(PlayerProfessionData) do
        if type(entry) == "table" then
            if type(entry.skillLevel) == "number" then
                reading["saved " .. tostring(name)] = entry.skillLevel
            end
            if type(entry.childSkillLines) == "table" then
                for childName, child in pairs(entry.childSkillLines) do
                    if type(child) == "table" and type(child.skillLevel) == "number" then
                        reading["saved " .. tostring(name) .. " > " .. tostring(childName)] = child.skillLevel
                    end
                end
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
-- Keeps the saved known-recipe list current when a recipe is learned from an item; without it
-- the list only caught up the next time the profession window was opened.
eventFrame:RegisterEvent("NEW_RECIPE_LEARNED")
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
        EnsureVariables()
        local recipeInfo = recipeID and C_TradeSkillUI.GetRecipeInfo(recipeID)
        if recipeInfo and recipeInfo.name then
            CaerdonRecipeData.globalRecipeNameToID[recipeInfo.name] = recipeID
            PlayerRecipeData.knownRecipes[recipeInfo.name] = recipeID
        end
    elseif event == "SKILL_LINES_CHANGED" then
        -- print("Skill lines CHANGED")
        GatherAllProfessionData()
    end
end)

-- The recipe name a recipe item teaches: the item name without its "Pattern: " style prefix.
-- This is the key of globalRecipeNameToID and of every toon's knownRecipes.
local function GetRecipeNameFromItem(item)
    local checkName = item:GetItemName()
    local recipeName = string.gsub(checkName or "", "Recipe: ", "")
    recipeName = string.gsub(recipeName, "Schematic: ", "")
    recipeName = string.gsub(recipeName, "Design: ", "")
    recipeName = string.gsub(recipeName, "Plans: ", "")
    recipeName = string.gsub(recipeName, "Pattern: ", "")
    recipeName = string.gsub(recipeName, "Technique: ", "")
    recipeName = string.gsub(recipeName, "Formula: ", "")
    return recipeName
end

-- The saved skill line a toon has for a profession name. A parent profession and its child skill
-- line can share a name. On WoW Forever every profession has a single child line named exactly
-- like its parent ("Cooking" > "Cooking"), and the secondary professions have no parent skill
-- level at all, so the top-level entry is a bare { childSkillLines = ... } container. Stopping at
-- that entry hid the real rank, so look at the top-level entry and every same-named child and
-- keep the highest level.
local function FindSkillLine(toonProfessions, skillName)
    local found
    local function ConsiderSkillLine(candidate)
        local skillLevel = type(candidate) == "table" and candidate.skillLevel
        if skillLevel and (not found or skillLevel > (found.skillLevel or 0)) then
            found = candidate
        end
    end

    if type(toonProfessions) ~= "table" or not skillName then
        return nil
    end

    ConsiderSkillLine(toonProfessions[skillName])
    for _, professionData in pairs(toonProfessions) do
        if type(professionData) == "table" and professionData.childSkillLines then
            ConsiderSkillLine(professionData.childSkillLines[skillName])
        end
    end
    return found
end

-- Function to check if a recipe is known based on previously gathered data
local function GetRecipe(item)
    -- print(item:GetItemLink())
    local recipeName = GetRecipeNameFromItem(item)

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
    professionInfo = FindSkillLine(PlayerProfessionData, requiredSkill)
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
        -- GetProfessions() lays its slots out differently per client (retail: two primaries,
        -- archaeology, fishing, cooking; WoW Forever: two primaries, first aid, fishing, cooking,
        -- with room for more), so walk every return value rather than naming five of them.
        local professionIDs = { GetProfessions() }
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

-- The player's other toons on this realm that have the recipe item's profession, from the saved
-- per-toon data, and whether each one's saved recipe list holds this recipe. Returns nil when no
-- other toon has the profession, otherwise
--   { professionName, recipeName,
--     knownByPlayer = this toon's own saved list has the recipe,
--     toons = { { name, rank, knowsRecipe, recipesRecorded } ... },
--     missing = { toons whose recorded list lacks the recipe: they can learn it },
--     unknown = { toons whose list for this profession was never recorded } }
-- (missing / unknown hold the same entries as toons, sorted by name.)
-- A toon's list is only as fresh as its last session: it is filled when that toon opens the
-- profession window or learns a recipe, and recipesRecorded is set once the window has shown
-- the full list (see GatherRecipes). Nobody can say whether an "unknown" toon needs the recipe.
function CaerdonRecipe:GetOtherToonRecipeInfo(item)
    local professionName = item:GetItemSubType()
    local recipeName = GetRecipeNameFromItem(item)
    if not professionName or professionName == "" or recipeName == "" then
        return nil
    end

    local realmName = GetRealmName()
    local playerName = UnitName("player")
    local realmProfessions = CaerdonProfessionData and CaerdonProfessionData[realmName]
    if type(realmProfessions) ~= "table" then
        return nil
    end
    local realmRecipes = CaerdonRecipeData and CaerdonRecipeData[realmName]

    local toons = {}
    for toonName, toonProfessions in pairs(realmProfessions) do
        if toonName ~= playerName then
            local skillLine = FindSkillLine(toonProfessions, professionName)
            local rank = skillLine and skillLine.skillLevel
            if rank and rank > 0 then
                local toonRecipes = type(realmRecipes) == "table" and realmRecipes[toonName]
                local knownRecipes = type(toonRecipes) == "table" and toonRecipes.knownRecipes
                local scanned = type(toonRecipes) == "table" and toonRecipes.scannedProfessions
                table.insert(toons, {
                    name = toonName,
                    rank = rank,
                    knowsRecipe = (type(knownRecipes) == "table" and knownRecipes[recipeName] ~= nil) or false,
                    recipesRecorded = (type(scanned) == "table" and scanned[professionName] == true) or false
                })
            end
        end
    end

    if #toons == 0 then
        return nil
    end

    table.sort(toons, function(a, b) return a.name < b.name end)
    local missing, unknown = {}, {}
    for _, toon in ipairs(toons) do
        if not toon.knowsRecipe then
            table.insert(toon.recipesRecorded and missing or unknown, toon)
        end
    end
    local playerRecipes = type(realmRecipes) == "table" and realmRecipes[playerName]
    local playerKnown = type(playerRecipes) == "table" and playerRecipes.knownRecipes
    return {
        professionName = professionName,
        recipeName = recipeName,
        knownByPlayer = (type(playerKnown) == "table" and playerKnown[recipeName] ~= nil) or false,
        toons = toons,
        missing = missing,
        unknown = unknown
    }
end

--[[static]] function CaerdonRecipe:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonRecipe:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CaerdonWardrobeItemDataMixin.CreateItemData(CaerdonRecipeMixin, caerdonItem)

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

-- Other toons on this realm with this recipe's profession and whether they know it; nil when
-- none has the profession. See CaerdonRecipe:GetOtherToonRecipeInfo for the fields.
function CaerdonRecipeMixin:GetOtherToonRecipeInfo()
    return CaerdonRecipe:GetOtherToonRecipeInfo(self.item)
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

        -- C_TradeSkillUI.GetRecipeInfo().learned can return false when the profession
        -- window isn't open (e.g. browsing the AH). Fall back to the saved known
        -- recipes data which was populated when the profession window was last open.
        if not result.learned and PlayerRecipeData and PlayerRecipeData.knownRecipes then
            local recipeName = self.recipe.name
            if recipeName and PlayerRecipeData.knownRecipes[recipeName] then
                result.learned = true
            end
        end

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