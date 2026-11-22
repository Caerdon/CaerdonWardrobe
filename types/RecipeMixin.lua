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
    -- The realm's key, and "" while the client can name none yet: what is filed there is
    -- taken over when it can (CaerdonAPI:GetRealmKey).
    local realmName = CaerdonAPI:GetRealmKey() or ""

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

    -- What this toon's own recipes take and how hard each was when its profession window was
    -- last open, by profession name (RecordRecipes below has the fields). Read by
    -- CaerdonIngredients.
    if not CaerdonRecipeData[realmName][playerName].recipes then
        CaerdonRecipeData[realmName][playerName].recipes = {}
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

-- The items a recipe takes: { [itemID] = quantity }, or nil when the client has no schematic
-- for it right now. Only what the recipe cannot be made without: an optional slot (retail's
-- modifying and finishing reagents) is left out. A slot that takes one of several items
-- (retail's quality tiers) names each of them.
local function ReadRecipeReagents(recipeID)
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok or type(schematic) ~= "table" or type(schematic.reagentSlotSchematics) ~= "table" then
        return nil
    end

    local basic = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 1
    local reagents = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        if type(slot) == "table" and type(slot.reagents) == "table" and
            (slot.reagentType == basic or slot.required == true) then
            for _, reagent in ipairs(slot.reagents) do
                local itemID = type(reagent) == "table" and reagent.itemID
                if type(itemID) == "number" and itemID > 0 then
                    reagents[itemID] = slot.quantityRequired or 1
                end
            end
        end
    end
    return reagents
end

-- professionName -> { recipes, schematics, ms }: what the last recording of this session read.
-- For the export; not saved.
local recordingStats = {}

-- Saves what each recipe of the open profession takes and what the client says about it for
-- this toon: whether it is learned and how hard it is (the colour of its name in the classic
-- list; Enum.TradeskillRelativeDifficulty). The client only says that while the profession is
-- open, so it is written down here with the rank it was said at.
--
--   PlayerRecipeData.recipes[professionName] = {
--       skillLine = the base profession's skill line,
--       rank, maxRank = the toon's rank when this was read, line = the skill line it is of,
--       complete = the list held every recipe (not a filtered one),
--       build = the client build the reagents were read in,
--       recipes = { [recipeID] = { name, learned, difficulty, canSkillUp, skillUps,
--                                  maxTrivialLevel, sourceType, reagents = { [itemID] = quantity } } } }
--
-- infos: recipeID -> the client's recipe info, as GatherRecipes read it.
-- A recipe's reagents are read once per client build: they are the cost of this (a schematic
-- per recipe), and only the client's data changes them.
local function RecordRecipes(recipeIDs, infos, complete)
    local baseInfo = TradeSkillCall("GetBaseProfessionInfo")
    local professionName = baseInfo and (baseInfo.parentProfessionName or baseInfo.professionName)
    if not professionName or professionName == "" then
        return
    end

    local startedAt = debugprofilestop()
    local build = select(2, GetBuildInfo())
    local previous = PlayerRecipeData.recipes[professionName]
    if type(previous) ~= "table" or type(previous.recipes) ~= "table" then
        previous = nil
    end
    local before = previous and previous.recipes or {}
    local sameBuild = previous ~= nil and previous.build == build
    -- A filtered list says nothing about the recipes it leaves out, so those stay as they were.
    local recipes = complete and {} or before

    local count, schematics = 0, 0
    for _, recipeID in ipairs(recipeIDs) do
        local info = infos[recipeID]
        if info then
            local reagents = sameBuild and before[recipeID] and before[recipeID].reagents or nil
            if not reagents then
                reagents = ReadRecipeReagents(recipeID)
                schematics = schematics + 1
            end
            recipes[recipeID] = {
                name = info.name,
                learned = info.learned == true,
                difficulty = info.relativeDifficulty,
                canSkillUp = info.canSkillUp == true,
                skillUps = info.numSkillUps,
                maxTrivialLevel = info.maxTrivialLevel,
                sourceType = info.sourceType,
                reagents = reagents,
            }
            count = count + 1
        end
    end

    -- The rank the difficulties were said at: the open skill line's where the client has one
    -- with a rank (on WoW Forever a secondary profession has no rank of its own, only its one
    -- child line's), otherwise the base profession's.
    local rank, maxRank, line = baseInfo.skillLevel, baseInfo.maxSkillLevel, baseInfo.professionName
    local childInfo = TradeSkillCall("GetChildProfessionInfo")
    if type(childInfo) == "table" and (childInfo.skillLevel or 0) > 0 then
        rank, maxRank, line = childInfo.skillLevel, childInfo.maxSkillLevel, childInfo.professionName
    end

    PlayerRecipeData.recipes[professionName] = {
        skillLine = baseInfo.parentProfessionID or baseInfo.professionID or (previous and previous.skillLine),
        rank = rank,
        maxRank = maxRank,
        line = line,
        complete = complete or (previous ~= nil and previous.complete == true),
        build = build,
        recipes = recipes,
    }
    recordingStats[professionName] = {
        recipes = count,
        schematics = schematics,
        ms = debugprofilestop() - startedAt,
    }

    if CaerdonIngredients then
        CaerdonIngredients:OnRecipesRecorded()
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
    local infos = {}
    for _, recipeID in ipairs(recipeIDs) do
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if recipeInfo then
            infos[recipeID] = recipeInfo
            CaerdonRecipeData.globalRecipeNameToID[recipeInfo.name] = recipeID

            if recipeInfo.learned and isOwn then
                PlayerRecipeData.knownRecipes[recipeInfo.name] = recipeID
            end
        end
    end

    -- Remember that this profession's list is now complete, so other toons can tell "does not
    -- know the recipe" from "never looked" (CaerdonRecipe:GetOtherToonRecipeInfo).
    local complete = #recipeIDs > 0 and (hasFullList or IsRecipeListUnfiltered())
    if isOwn and complete then
        local baseInfo = TradeSkillCall("GetBaseProfessionInfo")
        local professionName = baseInfo and (baseInfo.parentProfessionName or baseInfo.professionName)
        if professionName and professionName ~= "" then
            PlayerRecipeData.scannedProfessions[professionName] = true
        end
    end

    if isOwn then
        RecordRecipeTools(recipeIDs)
        if #recipeIDs > 0 then
            RecordRecipes(recipeIDs, infos, complete)
        end
    end
end

-- What this toon's recipes take and how hard each was, as saved by RecordRecipes (nil before
-- the saved variables are loaded).
function CaerdonRecipe:GetRecordedRecipes()
    return PlayerRecipeData and PlayerRecipeData.recipes
end

-- The same for every toon of this realm that has a recording, this one included:
-- { [toon name] = its recipes table }.
function CaerdonRecipe:GetRealmRecordedRecipes()
    local found = {}
    local realmRecipes = CaerdonRecipeData and CaerdonRecipeData[CaerdonAPI:GetRealmKey() or ""]
    if type(realmRecipes) == "table" then
        for toonName, toonData in pairs(realmRecipes) do
            if type(toonData) == "table" and type(toonData.recipes) == "table" then
                found[toonName] = toonData.recipes
            end
        end
    end
    return found
end

-- What the last recording of each profession read this session, for the export:
-- { [professionName] = { recipes, schematics, ms } }.
function CaerdonRecipe:GetRecordingStats()
    return recordingStats
end

-- The tools this toon's recipes ask for, as saved by RecordRecipeTools (nil before the saved
-- variables are loaded).
function CaerdonRecipe:GetRecordedTools()
    return PlayerRecipeData and PlayerRecipeData.tools
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

-- For the refresh watcher (CaerdonRefresh.lua): the ranks saved for this toon, which a recipe's
-- verdict reads through FindSkillLine. Adds one key per skill line to the reading.
--
-- They are saved first. The watcher's frame hears an event before this file's does, so at a
-- profession point it would read the toon's new rank beside the rank saved before the point,
-- and find the saved one changed when the burst is over: two refreshes for one point.
function CaerdonRecipe:AddSkillReading(reading)
    if type(PlayerProfessionData) ~= "table" then
        return
    end
    GatherAllProfessionData()
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
        -- A recipe recorded as not learned is learned now. Its difficulty stays as it was said.
        for _, entry in pairs(PlayerRecipeData.recipes) do
            local recorded = type(entry) == "table" and type(entry.recipes) == "table" and entry.recipes[recipeID]
            if recorded and not recorded.learned then
                recorded.learned = true
                if CaerdonIngredients then
                    CaerdonIngredients:OnRecipesRecorded()
                end
            end
        end
    elseif event == "SKILL_LINES_CHANGED" then
        -- print("Skill lines CHANGED")
        GatherAllProfessionData()
    end
end)

-- The recipe name a recipe item teaches: the item name without its "Pattern: " style prefix.
-- This is the key of globalRecipeNameToID and of every toon's knownRecipes.
--
-- The prefix is whatever stands before the name's first colon, in any language: "Recipe: ",
-- "Rezept: ", "Recette : " (a space before the colon), "配方：" (a full-width colon and no
-- space). A list of the English words found nothing in another language's client, and left
-- out English ones as well ("Manual: "). A name without a colon is the recipe's as it is
-- ("Expert Cookbook").
local FULL_WIDTH_COLON = "\239\188\154"
function CaerdonRecipe:GetRecipeNameFromItemName(itemName)
    if type(itemName) ~= "string" then
        return ""
    end
    local colon, colonEnd = itemName:find(":", 1, true)
    local wide, wideEnd = itemName:find(FULL_WIDTH_COLON, 1, true)
    if wide and (not colon or wide < colon) then
        colonEnd = wideEnd
    end
    if not colonEnd then
        return itemName
    end
    local recipeName = itemName:sub(colonEnd + 1):gsub("^%s+", "")
    if recipeName == "" then
        return itemName
    end
    return recipeName
end

local function GetRecipeNameFromItem(item)
    return CaerdonRecipe:GetRecipeNameFromItemName(item:GetItemName())
end

-- A name with its first letter as a capital, nil where that letter is none this knows or is
-- one already. The client's string.upper goes by bytes and knows a to z only; this knows the
-- two-byte letters of the Latin and the Cyrillic alphabet as well (é, ñ, э), which is what
-- Spanish and Russian names start with.
function CaerdonRecipe:CapitalizeFirstLetter(name)
    if type(name) ~= "string" then
        return nil
    end
    local first, second = name:byte(1, 2)
    if not first then
        return nil
    end
    if first >= 97 and first <= 122 then
        return string.char(first - 32) .. name:sub(2)
    end
    if not second then
        return nil
    end
    local lead, trail
    if first == 0xC3 and second >= 0xA0 and second <= 0xBE and second ~= 0xB7 then
        lead, trail = 0xC3, second - 0x20 -- à to þ, without the division sign
    elseif first == 0xD0 and second >= 0xB0 and second <= 0xBF then
        lead, trail = 0xD0, second - 0x20 -- а to п
    elseif first == 0xD1 and second >= 0x80 and second <= 0x8F then
        lead, trail = 0xD0, second + 0x20 -- р to я
    elseif first == 0xD1 and second == 0x91 then
        lead, trail = 0xD0, 0x81 -- ё
    end
    if not lead then
        return nil
    end
    return string.char(lead, trail) .. name:sub(3)
end

-- What a table keyed by the profession list's recipe names has for the name a recipe item
-- gave. Spanish and Russian write the recipe's name in lower case after the item's prefix
-- ("Receta: elixir de agilidad menor") and with a capital in the list ("Elixir de agilidad
-- menor"), so a name the table lacks is asked once more with its first letter as a capital.
-- That is all it mends: where the item and the list word the name differently, as Classic's
-- data does for some recipes in both languages, the item finds no recipe by its name.
function CaerdonRecipe:FindByName(names, recipeName)
    if type(names) ~= "table" or recipeName == nil then
        return nil
    end
    local found = names[recipeName]
    if found == nil then
        local capitalized = CaerdonRecipe:CapitalizeFirstLetter(recipeName)
        if capitalized then
            found = names[capitalized]
        end
    end
    return found
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

-- The rank saved for one of this toon's skill lines by name, nil when none is.
function CaerdonRecipe:GetSavedRank(skillName)
    local skillLine = FindSkillLine(PlayerProfessionData, skillName)
    return skillLine and skillLine.skillLevel or nil
end

-- The same for another toon of this realm, as its last session left it. A profession it
-- dropped reads 0.
function CaerdonRecipe:GetToonRank(toonName, skillName)
    local realmProfessions = CaerdonProfessionData and CaerdonProfessionData[CaerdonAPI:GetRealmKey() or ""]
    local skillLine = type(realmProfessions) == "table" and FindSkillLine(realmProfessions[toonName], skillName)
    return skillLine and skillLine.skillLevel or nil
end

-- Function to check if a recipe is known based on previously gathered data
local function GetRecipe(item)
    -- print(item:GetItemLink())
    local recipeName = GetRecipeNameFromItem(item)

    local recipeID = CaerdonRecipe:FindByName(CaerdonRecipeData.globalRecipeNameToID, recipeName)
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

-- The names of every recipe in a toon's recording of a profession's whole list, learned or
-- not: { [recipe name] = true }. Kept per recording; a new recording is a new table.
local recordedNames = setmetatable({}, { __mode = "k" })

-- Whether a toon's recorded list of the profession has a recipe of this name, learned or not.
-- nil when it has no recording of the whole list (RecordRecipes): then nothing says.
local function IsInRecordedList(toonRecipes, professionName, recipeName)
    local recordings = type(toonRecipes) == "table" and toonRecipes.recipes
    local entry = type(recordings) == "table" and recordings[professionName]
    if type(entry) ~= "table" or entry.complete ~= true or type(entry.recipes) ~= "table" then
        return nil
    end
    local names = recordedNames[entry]
    if not names then
        names = {}
        for _, recipe in pairs(entry.recipes) do
            if type(recipe) == "table" and recipe.name then
                names[recipe.name] = true
            end
        end
        recordedNames[entry] = names
    end
    return CaerdonRecipe:FindByName(names, recipeName) == true
end

-- The cap a toon's recording of the profession was made at, where the profession is one skill
-- line (WoW Forever: the recorded line has the profession's name). With a line per expansion
-- (retail) the recorded cap is one line's and says nothing about the profession. nil otherwise.
local function RecordedCap(toonRecipes, professionName)
    local recordings = type(toonRecipes) == "table" and toonRecipes.recipes
    local entry = type(recordings) == "table" and recordings[professionName]
    if type(entry) == "table" and entry.line == professionName and type(entry.maxRank) == "number" and entry.maxRank > 0 then
        return entry.maxRank
    end
    return nil
end

-- The player's other toons on this realm that have the recipe item's profession, from the saved
-- per-toon data, and whether each one's saved recipe list holds this recipe. Returns nil when no
-- other toon has the profession, otherwise
--   { professionName, recipeName,
--     knownByPlayer = this toon's own saved list has the recipe,
--     requirement = what the item asks for (CaerdonItemMixin:GetSkillRequirement), read only
--                   when a toon lacks the recipe,
--     capTaught = the cap the item raises the profession to, for a book of that kind,
--     toons = { { name, rank, knowsRecipe, recipesRecorded, inRecordedList,
--                 cap = its recorded cap, hasCap = it is at the cap the item gives,
--                 skillRank = its saved rank in the skill the item asks for } ... },
--     missing = { toons that lack it and can learn it now },
--     tooLow = { toons that lack it and whose rank is below what the item asks for },
--     unknown = { toons whose list for this profession was never recorded },
--     notInList = { toons whose recorded whole list has no recipe of this name, where nothing
--                   else says whether they have what the item teaches } }
-- (missing / tooLow / unknown / notInList hold the same entries as toons, sorted by name.)
-- A toon's list is only as fresh as its last session: it is filled when that toon opens the
-- profession window or learns a recipe, and recipesRecorded is set once the window has shown
-- the full list (see GatherRecipes). Nobody can say whether an "unknown" toon needs the recipe.
--
-- "Not among the recipes it knows" is not "can learn it". An item of class Recipe may teach
-- something that is no recipe of the profession's list: a book that raises the profession's cap
-- (Expert Cookbook 16072) is in no toon's list before or after it is learned, and read as one
-- every other toon could learn. So where a toon's whole list is recorded, the recipe must be
-- in it; a name that is not says nothing about that toon (notInList). A toon whose list was
-- read before whole lists were recorded (inRecordedList nil) is judged as before, by the
-- recipes it knows, until its profession window is next opened.
--
-- A book of that kind is judged by caps instead: the cap it gives is the one number of its use
-- line, taken as a cap only when it is above the rank the book asks for, and the toon's cap is
-- the one its recording was made at (as old as its profession window's last opening, and only
-- where the profession is one skill line). At or above the book's cap the toon has learned it;
-- below, it lacks it. Without either cap the toon stays in notInList.
--
-- A toon that lacks it can learn it only at the rank the item asks for ("Requires Cooking
-- (125)"): one whose saved rank in that skill is lower is in tooLow, not in missing. A toon
-- with no saved rank for that skill at all is not held back by it: nothing says its rank.
function CaerdonRecipe:GetOtherToonRecipeInfo(item)
    local professionName = item:GetItemSubType()
    local recipeName = GetRecipeNameFromItem(item)
    if not professionName or professionName == "" or recipeName == "" then
        return nil
    end

    -- By the realm's key, as everything saved by realm and toon is filed (the realm's name
    -- is an empty text on WoW Forever).
    local realmName = CaerdonAPI:GetRealmKey() or ""
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
                    knowsRecipe = CaerdonRecipe:FindByName(knownRecipes, recipeName) ~= nil,
                    recipesRecorded = (type(scanned) == "table" and scanned[professionName] == true) or false,
                    inRecordedList = IsInRecordedList(toonRecipes, professionName, recipeName),
                    cap = RecordedCap(toonRecipes, professionName),
                    professions = toonProfessions,
                })
            end
        end
    end

    if #toons == 0 then
        return nil
    end

    table.sort(toons, function(a, b) return a.name < b.name end)
    -- What the item asks for, read when the first toon that lacks the recipe needs it.
    local requirement, requirementRead, capTaught
    local function Requirement()
        if not requirementRead then
            requirementRead = true
            requirement = item.GetSkillRequirement and item:GetSkillRequirement() or nil
            if requirement and requirement.useNumber and requirement.useNumber > requirement.rank then
                capTaught = requirement.useNumber
            end
        end
        return requirement
    end

    local missing, unknown, notInList, tooLow = {}, {}, {}, {}
    for _, toon in ipairs(toons) do
        local toonProfessions = toon.professions
        toon.professions = nil
        local lacksIt = false
        if toon.knowsRecipe then
            -- Nothing to hand over.
        elseif not toon.recipesRecorded then
            table.insert(unknown, toon)
        elseif toon.inRecordedList == false then
            -- No recipe of its list: a book that raises the cap, if the caps say so.
            Requirement()
            if capTaught and toon.cap then
                toon.hasCap = toon.cap >= capTaught
                lacksIt = not toon.hasCap
            else
                table.insert(notInList, toon)
            end
        else
            lacksIt = true
        end
        if lacksIt then
            local asked = Requirement()
            if asked then
                local skillLine = FindSkillLine(toonProfessions, asked.skillName)
                toon.skillRank = skillLine and skillLine.skillLevel or nil
            end
            if asked and toon.skillRank and toon.skillRank < asked.rank then
                table.insert(tooLow, toon)
            else
                table.insert(missing, toon)
            end
        end
    end
    local playerRecipes = type(realmRecipes) == "table" and realmRecipes[playerName]
    local playerKnown = type(playerRecipes) == "table" and playerRecipes.knownRecipes
    return {
        professionName = professionName,
        recipeName = recipeName,
        knownByPlayer = (type(playerKnown) == "table" and playerKnown[recipeName] ~= nil) or false,
        toons = toons,
        requirement = requirement,
        capTaught = capTaught,
        missing = missing,
        tooLow = tooLow,
        unknown = unknown,
        notInList = notInList,
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