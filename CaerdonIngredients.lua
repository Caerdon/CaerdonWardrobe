-- Ingredients.
--
-- What an item is still good for as an ingredient of a recipe: of the toon's own, and of the
-- other toons of the realm. An ingredient has a use while a recipe that takes it still gives
-- skill, learned or not. One whose recipes are all gray has been outgrown.
--
-- Two statuses come of it (CaerdonItemMixin:GetIngredientStatus, in CaerdonItem.lua):
--   "send":     this toon has no use for it and another toon's recipes do: mail it.
--   "sellable": this toon's recipes have outgrown it and nobody else wants it.
-- An ingredient a recipe of this toon's still gives skill for is kept, with no icon. One no
-- recorded recipe of this toon's takes is never called sellable: nothing says what else it
-- is good for.
--
-- The data is types/RecipeMixin.lua's: every recipe of a profession with what it takes and
-- what the client said about it, written down whenever that profession's window is open (the
-- client only says how hard a recipe is while it is). A profession that was never opened has
-- nothing here: "no recipe takes it" is only ever said about the professions that were
-- recorded. Every toon's recording is saved, which is how another toon's use is known; what
-- is known of it is as old as that toon's last session.
--
-- CaerdonItemMixin:GetIngredientInfo() is the entry point for callers; the Debug Frame export
-- prints all of it ("[Ingredients]").

local ADDON_NAME, NS = ...

CaerdonIngredients = {}

local Difficulty = Enum.TradeskillRelativeDifficulty or {}
local TRIVIAL = Difficulty.Trivial or 3
-- The colours of the classic recipe list, which is how players name these.
local DIFFICULTY_NAMES = {
    [Difficulty.Optimal or 0] = "orange",
    [Difficulty.Medium or 1] = "yellow",
    [Difficulty.Easy or 2] = "green",
    [TRIVIAL] = "gray",
}

-- This toon: { byItem = { [itemID] = { { professionName, recipeID, recipe, entry, quantity,
--   rankNow } ... } }, recorded = { [profession name now] = entry }, notRecorded = { names },
--   dropped = { names } }
local index
-- The other toons of the realm: { [itemID] = { { toon, professionName, recipeID, recipe,
--   quantity, toonRank, rank } ... } }. Built once a session: another toon's saved data does
-- not change while this one is played.
local othersIndex

-- The toon's professions right now: { [name] = true }, { [skill line] = name }, { [name] = rank }
local function ReadProfessions()
    local names, skillLines, ranks = {}, {}, {}
    if GetProfessions and GetProfessionInfo then
        for _, professionIndex in pairs({ GetProfessions() }) do
            local name, _, rank, _, _, _, skillLine = GetProfessionInfo(professionIndex)
            if name and name ~= "" then
                names[name] = true
                ranks[name] = rank
                if skillLine then
                    skillLines[skillLine] = name
                end
            end
        end
    end
    return names, skillLines, ranks
end

local function SortUses(a, b)
    if (a.toon or "") ~= (b.toon or "") then
        return (a.toon or "") < (b.toon or "")
    end
    if a.professionName ~= b.professionName then
        return a.professionName < b.professionName
    end
    local aName, bName = tostring(a.recipe.name), tostring(b.recipe.name)
    if aName ~= bName then
        return aName < bName
    end
    return a.recipeID < b.recipeID
end

local function AddUse(byItem, itemID, use)
    local uses = byItem[itemID]
    if not uses then
        uses = {}
        byItem[itemID] = uses
    end
    uses[#uses + 1] = use
end

local function BuildIndex()
    local names, skillLines, ranks = ReadProfessions()
    local built = { byItem = {}, recorded = {}, notRecorded = {}, dropped = {} }

    -- A profession the toon dropped keeps its saved recording, so it only counts while the toon
    -- still has that profession.
    local recorded = CaerdonRecipe and CaerdonRecipe.GetRecordedRecipes and CaerdonRecipe:GetRecordedRecipes()
    if type(recorded) == "table" then
        for professionName, entry in pairs(recorded) do
            if type(entry) == "table" and type(entry.recipes) == "table" then
                local currentName = (names[professionName] and professionName) or
                    (entry.skillLine and skillLines[entry.skillLine]) or nil
                if currentName then
                    built.recorded[currentName] = entry
                    -- The rank to hold a recipe's gray rank against: the toon's rank now, where
                    -- the profession is one skill line (WoW Forever: the open line has the
                    -- profession's name). Where it has a line per expansion (retail) the rank
                    -- of the profession is not the rank of a recipe's line, and nil leaves the
                    -- reading to the recorded colour.
                    local rankNow = entry.line == professionName and ranks[currentName] or nil
                    for recipeID, recipe in pairs(entry.recipes) do
                        if type(recipe) == "table" and type(recipe.reagents) == "table" then
                            for itemID, quantity in pairs(recipe.reagents) do
                                AddUse(built.byItem, itemID, { professionName = currentName, recipeID = recipeID,
                                    recipe = recipe, entry = entry, quantity = quantity, rankNow = rankNow })
                            end
                        end
                    end
                else
                    built.dropped[#built.dropped + 1] = professionName
                end
            end
        end
    end

    for _, uses in pairs(built.byItem) do
        table.sort(uses, SortUses)
    end
    for name in pairs(names) do
        if not built.recorded[name] then
            built.notRecorded[#built.notRecorded + 1] = name
        end
    end
    table.sort(built.notRecorded)
    table.sort(built.dropped)
    return built
end

local function GetIndex()
    if not index then
        index = BuildIndex()
    end
    return index
end

local function BuildOthersIndex()
    local byItem = {}
    local playerName = UnitName("player")
    local realm = CaerdonRecipe and CaerdonRecipe.GetRealmRecordedRecipes and CaerdonRecipe:GetRealmRecordedRecipes() or {}
    for toonName, professions in pairs(realm) do
        if toonName ~= playerName then
            for professionName, entry in pairs(professions) do
                if type(entry) == "table" and type(entry.recipes) == "table" then
                    -- The rank its last session saved, else the one of its recording. A
                    -- profession it dropped reads 0 and counts for nothing.
                    local toonRank = CaerdonRecipe.GetToonRank and CaerdonRecipe:GetToonRank(toonName, professionName)
                        or entry.rank
                    if type(toonRank) == "number" and toonRank > 0 then
                        local rank = entry.line == professionName and toonRank or nil
                        for recipeID, recipe in pairs(entry.recipes) do
                            if type(recipe) == "table" and type(recipe.reagents) == "table" then
                                for itemID, quantity in pairs(recipe.reagents) do
                                    AddUse(byItem, itemID, { toon = toonName, professionName = professionName,
                                        recipeID = recipeID, recipe = recipe, quantity = quantity,
                                        toonRank = toonRank, rank = rank })
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    for _, uses in pairs(byItem) do
        table.sort(uses, SortUses)
    end
    return byItem
end

local function GetOthersIndex()
    if not othersIndex then
        othersIndex = BuildOthersIndex()
    end
    return othersIndex
end

-- Whether a recorded recipe counts as a use, the colour of its difficulty when it was recorded,
-- and the reading in words.
-- true: it gives skill; false: it is gray; nil: the client gave no difficulty for it.
-- Learned or not makes no difference to the count: a recipe still to be learned that would
-- give skill is a use as well.
--
-- rankNow: the toon's rank in the recipe's skill line, where that is known (BuildIndex). The
-- client's maxTrivialLevel is the rank a recipe is gray from (WoW Forever: every gray recipe
-- of three exports had one at or below the toon's rank, every other one above it), so with a
-- rank the reading does not age with the recording. Without one the recorded colour decides.
local function ReadRecipe(recipe, rankNow)
    local difficultyName = DIFFICULTY_NAMES[recipe.difficulty]
    local known = recipe.learned and "known" or "not learned"
    local grayFrom = recipe.maxTrivialLevel
    if type(rankNow) == "number" and rankNow > 0 and type(grayFrom) == "number" and grayFrom > 0 then
        if rankNow >= grayFrom then
            return false, difficultyName, string.format("%s, gray from rank %d", known, grayFrom)
        end
        return true, difficultyName, string.format("%s, %s skill until rank %d", known,
            recipe.learned and "gives" or "would give", grayFrom)
    end
    if not difficultyName then
        return nil, nil, known .. ", the client gave no difficulty"
    end
    if recipe.difficulty == TRIVIAL then
        return false, difficultyName, known .. ", gray"
    end
    return true, difficultyName,
        string.format("%s, %s skill (%s)", known, recipe.learned and "gives" or "would give", difficultyName)
end

-- One recorded recipe that takes an item, as plain facts.
local function Flatten(use)
    local recipe = use.recipe
    return {
        toon = use.toon,
        toonRank = use.toonRank,
        professionName = use.professionName,
        recipeID = use.recipeID,
        name = recipe.name,
        quantity = use.quantity,
        learned = recipe.learned == true,
        difficulty = recipe.difficulty,
        canSkillUp = recipe.canSkillUp,
        skillUps = recipe.skillUps,
        maxTrivialLevel = recipe.maxTrivialLevel,
        sourceType = recipe.sourceType,
        recordedRank = use.entry and use.entry.rank or nil,
        -- The rank the reading is by; nil where the recorded colour decides.
        rank = use.rankNow or use.rank,
    }
end

-- What the saved recordings say about one item, with nothing judged: nil when no recorded
-- recipe takes it, otherwise { own = { facts ... }, others = { facts ... } } (Flatten).
--
-- The test addon's recorder keeps this function's answer and a replay puts it in its place
-- (CaerdonWardrobe_Tests/RecordKeys.lua, SEAMS): the recordings are saved variables, which no
-- recording of a client's answers holds. So everything read from them goes through here, and
-- GetItemInfo judges from the answer alone.
function CaerdonIngredients:GetRecordedUses(itemID)
    local own = GetIndex().byItem[itemID]
    local others = GetOthersIndex()[itemID]
    if not own and not others then
        return nil
    end
    local uses = { own = {}, others = {} }
    for _, use in ipairs(own or {}) do
        uses.own[#uses.own + 1] = Flatten(use)
    end
    for _, use in ipairs(others or {}) do
        uses.others[#uses.others + 1] = Flatten(use)
    end
    return uses
end

local function SortToons(a, b)
    if a.name ~= b.name then
        return a.name < b.name
    end
    return a.professionName < b.professionName
end

-- nil when no recorded recipe takes the item, otherwise
--   { recipes = { this toon's: { professionName, recipeID, name, quantity, learned,
--                   difficulty, difficultyName, canSkillUp, skillUps, maxTrivialLevel, sourceType,
--                   recordedRank = the toon's rank when the difficulty was said,
--                   rankNow = its rank now, where the reading is by rank (ReadRecipe),
--                   isUse = true / false / nil (ReadRecipe), reading = the same in words } ... },
--     hasUse = one of them counts as a use,
--     undecided = how many the client gave no difficulty for,
--     isOutgrown = this toon's recipes take it and every one is gray,
--     others = { other toons': { toon, toonRank, professionName, recipeID, name, quantity,
--                   learned, isUse, reading } ... },
--     skillFor = { { name, professionName, rank } ... } the toons a recipe gives skill for,
--     usedBy = the same plus the toons that know a recipe that takes it, gray or not }
function CaerdonIngredients:GetItemInfo(itemID)
    if not itemID then
        return nil
    end
    local uses = self:GetRecordedUses(itemID)
    if type(uses) ~= "table" then
        return nil
    end

    local info = { recipes = {}, hasUse = false, undecided = 0, others = {}, skillFor = {}, usedBy = {} }
    for _, fact in ipairs(uses.own or {}) do
        local isUse, difficultyName, reading = ReadRecipe(fact, fact.rank)
        info.recipes[#info.recipes + 1] = {
            professionName = fact.professionName,
            recipeID = fact.recipeID,
            name = fact.name,
            quantity = fact.quantity,
            learned = fact.learned,
            difficulty = fact.difficulty,
            difficultyName = difficultyName,
            canSkillUp = fact.canSkillUp,
            skillUps = fact.skillUps,
            maxTrivialLevel = fact.maxTrivialLevel,
            sourceType = fact.sourceType,
            recordedRank = fact.recordedRank,
            rankNow = fact.rank,
            isUse = isUse,
            reading = reading,
        }
        if isUse then
            info.hasUse = true
        elseif isUse == nil then
            info.undecided = info.undecided + 1
        end
    end
    info.isOutgrown = #info.recipes > 0 and not info.hasUse and info.undecided == 0

    local skillSeen, usedSeen = {}, {}
    for _, fact in ipairs(uses.others or {}) do
        local isUse, _, reading = ReadRecipe(fact, fact.rank)
        info.others[#info.others + 1] = {
            toon = fact.toon,
            toonRank = fact.toonRank,
            professionName = fact.professionName,
            recipeID = fact.recipeID,
            name = fact.name,
            quantity = fact.quantity,
            learned = fact.learned,
            isUse = isUse,
            reading = reading,
        }
        local key = tostring(fact.toon) .. "\n" .. tostring(fact.professionName)
        local who = { name = tostring(fact.toon), professionName = tostring(fact.professionName), rank = fact.toonRank }
        if isUse and not skillSeen[key] then
            skillSeen[key] = true
            info.skillFor[#info.skillFor + 1] = who
        end
        if (isUse or fact.learned) and not usedSeen[key] then
            usedSeen[key] = true
            info.usedBy[#info.usedBy + 1] = who
        end
    end
    table.sort(info.skillFor, SortToons)
    table.sort(info.usedBy, SortToons)
    return info
end

-- changed: what the refresh is about (CaerdonWardrobe:RefreshItems), nil for anything. The
-- index follows from the recordings and from the toon's professions and their ranks. A
-- recording drops it by itself (OnRecipesRecorded), and neither a change of clothes nor
-- something learned changes a profession or a rank, so a refresh about one of those keeps it.
-- The other toons' index is kept for the session whatever the refresh.
function CaerdonIngredients:InvalidateCaches(changed)
    if changed == "worn" or changed == "collection" then
        return
    end
    index = nil
end

-- itemID -> "use" | "gray" | "undecided", for every item this toon's recorded recipes take.
local function Summarize(built)
    local summary = {}
    for itemID, uses in pairs(built.byItem) do
        local state = "gray"
        for _, use in ipairs(uses) do
            local isUse = ReadRecipe(use.recipe, use.rankNow)
            if isUse then
                state = "use"
                break
            elseif isUse == nil then
                state = "undecided"
            end
        end
        summary[itemID] = state
    end
    return summary
end

-- types/RecipeMixin.lua wrote a recording, or marked a recorded recipe as learned. A verdict
-- is kept per item link, so the items are judged again when what a recording says about one
-- of them is no longer what the last one said: in practice a profession's first recording.
-- With no index there is nothing to compare: none was asked for since the last refresh, so
-- no verdict on screen was made from one.
function CaerdonIngredients:OnRecipesRecorded()
    local before = index
    index = nil
    if not before then
        return
    end
    local was, is = Summarize(before), Summarize(GetIndex())
    local changed
    for itemID, state in pairs(is) do
        if was[itemID] ~= state then
            changed = itemID
            break
        end
    end
    if not changed then
        for itemID in pairs(was) do
            if is[itemID] == nil then
                changed = itemID
                break
            end
        end
    end
    if changed and CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
        CaerdonWardrobe:RefreshItems("recipes recorded",
            string.format("item %s: %s -> %s", tostring(changed), tostring(was[changed]), tostring(is[changed])))
    end
end

-- For the Debug Frame export: what is recorded for this toon, and what the client says right
-- now about each of this toon's recipes that take the item (it answers for one profession at a
-- time, which is why the recordings exist).
function CaerdonIngredients:GetDebugState(itemID)
    local built = GetIndex()
    local state = { recorded = {}, notRecorded = built.notRecorded, dropped = built.dropped, clientNow = {} }

    local stats = CaerdonRecipe and CaerdonRecipe.GetRecordingStats and CaerdonRecipe:GetRecordingStats() or {}
    for professionName, entry in pairs(built.recorded) do
        local count, learned = 0, 0
        for _, recipe in pairs(entry.recipes) do
            count = count + 1
            if type(recipe) == "table" and recipe.learned then
                learned = learned + 1
            end
        end
        local rankNow = CaerdonRecipe.GetSavedRank and
            (CaerdonRecipe:GetSavedRank(entry.line) or CaerdonRecipe:GetSavedRank(professionName))
        local line = string.format("%s: %d recipes, %d known, %s list, said at rank %s of %s (%s), rank now %s",
            professionName, count, learned, entry.complete and "the whole" or "a filtered",
            tostring(entry.rank), tostring(entry.maxRank), tostring(entry.line), tostring(rankNow))
        local session = stats[professionName]
        if session then
            line = line .. string.format("; this session: %d recipes and %d schematics read in %.1f ms",
                session.recipes, session.schematics, session.ms)
        else
            line = line .. "; not opened this session"
        end
        state.recorded[#state.recorded + 1] = line
    end
    table.sort(state.recorded)

    if itemID then
        for _, use in ipairs(built.byItem[itemID] or {}) do
            local now = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(use.recipeID)
            if type(now) == "table" then
                state.clientNow[use.recipeID] = string.format(
                    "learned %s, difficulty %s, canSkillUp %s, numSkillUps %s, maxTrivialLevel %s, sourceType %s, disabled %s (%s)",
                    tostring(now.learned), tostring(now.relativeDifficulty), tostring(now.canSkillUp),
                    tostring(now.numSkillUps), tostring(now.maxTrivialLevel), tostring(now.sourceType),
                    tostring(now.disabled), tostring(now.disabledReason))
                -- The skill line the recipe belongs to and the toon's rank in it: one line per
                -- profession on WoW Forever, one per expansion on retail, where a line the toon
                -- never trained is the case nothing has shown yet.
                if C_TradeSkillUI.GetProfessionInfoByRecipeID then
                    local ok, line = pcall(C_TradeSkillUI.GetProfessionInfoByRecipeID, use.recipeID)
                    state.clientNow[use.recipeID] = state.clientNow[use.recipeID] .. "; line: " ..
                        (ok and type(line) == "table" and string.format("%s (%s) rank %s of %s", tostring(line.professionName),
                            tostring(line.professionID), tostring(line.skillLevel), tostring(line.maxSkillLevel)) or "no answer")
                end
                -- Where a recipe that is not learned comes from, which Blizzard's recipe form
                -- shows for one. Whether a toon can ever learn a recipe is not in its info.
                if not use.recipe.learned and C_TradeSkillUI.GetRecipeSourceText then
                    local ok, source = pcall(C_TradeSkillUI.GetRecipeSourceText, use.recipeID)
                    state.clientNow[use.recipeID] = state.clientNow[use.recipeID] .. "; source: " ..
                        (ok and type(source) == "string" and source ~= "" and source:gsub("%s+", " ") or "no answer")
                end
            else
                state.clientNow[use.recipeID] = "no answer"
            end
        end
    end

    return state
end
