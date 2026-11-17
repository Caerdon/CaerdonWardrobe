-- Profession tools.
--
-- On a client without profession gear slots the tools a profession needs are ordinary items in
-- the bags: a Mining Pick, a Blacksmith Hammer, an Arclight Spanner. To every other check they
-- look like a weak weapon that lost to the one equipped, i.e. something to sell. This module
-- says which items are tools of a profession the toon has right now, so they are left alone.
--
-- Two sources:
--   known items:  a short list of classic tools (KNOWN_TOOLS) with the professions that need
--                 them. Gathering has no recipe that names its tool, so the Mining Pick and the
--                 Skinning Knife can only come from here. Used only where tools are carried in
--                 the bags (see ToolsCarriedInBags).
--   recipe tools: the tool names the toon's own recipes ask for, recorded by
--                 types/RecipeMixin.lua whenever a profession window is open. Whatever the
--                 client names is a tool there, so this needs no gate and picks up tools this
--                 file has never heard of.
--
-- An item is a tool when it is a known item, when its name is a tool's name, or - equippable
-- items only - when its name contains one ("Keen Skinning Knife"). The last one is a guess:
-- nothing in the item API says which items stand in for a tool.
--
-- CaerdonItemMixin:GetProfessionToolInfo() is the entry point for callers; the Debug Frame
-- export prints everything this knows ("[Profession Tools]").

local ADDON_NAME, NS = ...

CaerdonProfessionTools = {}

-- Base profession skill lines, as select(7, GetProfessionInfo(index)) reports them.
local BLACKSMITHING, MINING, ENGINEERING, SKINNING = 164, 186, 202, 393

local KNOWN_TOOLS = {
    [2901] = { MINING },                     -- Mining Pick
    [7005] = { SKINNING },                   -- Skinning Knife
    [5956] = { BLACKSMITHING, ENGINEERING }, -- Blacksmith Hammer
    [6219] = { ENGINEERING },                -- Arclight Spanner
    [10498] = { ENGINEERING },               -- Gyromatic Micro-Adjustor
}

-- A tool name shorter than this is not searched for inside other item names.
local MIN_CONTAINED_NAME_LENGTH = 8
-- While a known tool's name is not cached yet, the context is rebuilt at most this often.
local PENDING_RETRY_SECONDS = 1

local context
-- itemID -> info table, or false for "not a tool"
local verdicts = {}

-- Retail equips profession tools in their own slots and stopped asking for the classic ones.
-- No API says "this client wants tools in the bags"; the classic ranged slot is the same
-- equipment model and is known to read true on WoW Forever and false on retail.
local function ToolsCarriedInBags()
    return C_PaperDollInfo ~= nil and C_PaperDollInfo.IsRangedSlotShown ~= nil and
        C_PaperDollInfo.IsRangedSlotShown() == true
end

-- The toon's professions right now: { names = { [name] = true }, skillLines = { [id] = name } }
local function ReadProfessions()
    local names, skillLines = {}, {}
    if GetProfessions and GetProfessionInfo then
        for _, professionIndex in pairs({ GetProfessions() }) do
            local name, _, _, _, _, _, skillLine = GetProfessionInfo(professionIndex)
            if name and name ~= "" then
                names[name] = true
                if skillLine then
                    skillLines[skillLine] = name
                end
            end
        end
    end
    return names, skillLines
end

local function AddToolName(ctx, toolName, professionName, source)
    local key = toolName:lower()
    local entry = ctx.toolNames[key]
    if not entry then
        entry = { name = toolName, professions = {}, source = source }
        ctx.toolNames[key] = entry
    end
    entry.professions[professionName] = true
end

local function BuildContext()
    local names, skillLines = ReadProfessions()
    local ctx = {
        professionNames = names,
        skillLines = skillLines,
        carriedInBags = ToolsCarriedInBags(),
        knownItems = {}, -- itemID -> { professions = { [name] = true }, name = item name or nil }
        toolNames = {},  -- lower-case tool name -> { name, professions = { [name] = true }, source }
        namesPending = false,
        builtAt = GetTime and GetTime() or 0,
    }

    if ctx.carriedInBags then
        for itemID, toolSkillLines in pairs(KNOWN_TOOLS) do
            local professions
            for _, skillLine in ipairs(toolSkillLines) do
                local professionName = skillLines[skillLine]
                if professionName then
                    professions = professions or {}
                    professions[professionName] = true
                end
            end
            if professions then
                local itemName = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or nil
                ctx.knownItems[itemID] = { professions = professions, name = itemName }
                if itemName and itemName ~= "" then
                    for professionName in pairs(professions) do
                        AddToolName(ctx, itemName, professionName, "known tool item")
                    end
                else
                    ctx.namesPending = true
                    if C_Item.RequestLoadItemDataByID then
                        C_Item.RequestLoadItemDataByID(itemID)
                    end
                end
            end
        end
    end

    -- Tool names the toon's own recipes ask for. A profession the toon dropped keeps its saved
    -- entry, so it only counts while the toon still has that profession.
    local recorded = CaerdonRecipe and CaerdonRecipe.GetRecordedTools and CaerdonRecipe:GetRecordedTools()
    if type(recorded) == "table" then
        for professionName, entry in pairs(recorded) do
            if type(entry) == "table" and type(entry.names) == "table" then
                local currentName = (names[professionName] and professionName) or
                    (entry.skillLine and skillLines[entry.skillLine]) or nil
                if currentName then
                    for toolName in pairs(entry.names) do
                        if type(toolName) == "string" and toolName ~= "" then
                            AddToolName(ctx, toolName, currentName, "recipe tool")
                        end
                    end
                end
            end
        end
    end

    return ctx
end

local function GetContext()
    if context and context.namesPending and GetTime and
        GetTime() - context.builtAt >= PENDING_RETRY_SECONDS then
        context = nil
    end
    if not context then
        context = BuildContext()
    end
    return context
end

local function SortedKeys(set)
    local list = {}
    for key in pairs(set) do
        list[#list + 1] = key
    end
    table.sort(list)
    return list
end

local function IsEquippable(itemID)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
    return equipLoc ~= nil and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
end

-- nil when the item is not a tool of one of the toon's professions, otherwise
--   { isTool = true,
--     professions = { sorted profession names that use it },
--     toolName = the tool it is or stands in for,
--     source = "known tool item" | "recipe tool",
--     match = "item" | "name" | "name contains" }
function CaerdonProfessionTools:GetItemInfo(itemID, itemName)
    if not itemID then
        return nil
    end

    local ctx = GetContext()
    local cached = verdicts[itemID]
    if cached ~= nil then
        return cached or nil
    end

    local info
    local known = ctx.knownItems[itemID]
    if known then
        info = {
            isTool = true,
            professions = SortedKeys(known.professions),
            toolName = known.name or itemName,
            source = "known tool item",
            match = "item",
        }
    elseif type(itemName) == "string" and itemName ~= "" then
        local lowerName = itemName:lower()
        local entry = ctx.toolNames[lowerName]
        local match = "name"
        if not entry and IsEquippable(itemID) then
            -- The longest tool name wins, so the answer does not depend on table order.
            local bestLength = 0
            for toolKey, candidate in pairs(ctx.toolNames) do
                if #toolKey >= MIN_CONTAINED_NAME_LENGTH and #toolKey > bestLength and
                    lowerName:find(toolKey, 1, true) then
                    entry = candidate
                    bestLength = #toolKey
                    match = "name contains"
                end
            end
        end
        if entry then
            info = {
                isTool = true,
                professions = SortedKeys(entry.professions),
                toolName = entry.name,
                source = entry.source,
                match = match,
            }
        end
    end

    -- "Not a tool" is only final once the item has a name and every known tool's name is in.
    if info then
        verdicts[itemID] = info
    elseif type(itemName) == "string" and itemName ~= "" and not ctx.namesPending then
        verdicts[itemID] = false
    end

    return info
end

function CaerdonProfessionTools:InvalidateCaches()
    context = nil
    wipe(verdicts)
end

-- types/RecipeMixin.lua read a tool name it had not saved before.
function CaerdonProfessionTools:OnToolsRecorded()
    self:InvalidateCaches()
    if CaerdonWardrobe and CaerdonWardrobe.RefreshItems then
        CaerdonWardrobe:RefreshItems("tools recorded")
    end
end

-- For the Debug Frame export.
function CaerdonProfessionTools:GetDebugState()
    local ctx = GetContext()
    local professions = {}
    for skillLine, name in pairs(ctx.skillLines) do
        professions[#professions + 1] = string.format("%s (%d)", name, skillLine)
    end
    for name in pairs(ctx.professionNames) do
        local hasSkillLine = false
        for _, lineName in pairs(ctx.skillLines) do
            if lineName == name then
                hasSkillLine = true
                break
            end
        end
        if not hasSkillLine then
            professions[#professions + 1] = name .. " (no skill line)"
        end
    end
    table.sort(professions)

    local tools = {}
    for _, entry in pairs(ctx.toolNames) do
        tools[#tools + 1] = string.format("%s: %s (%s)", entry.name,
            table.concat(SortedKeys(entry.professions), ", "), entry.source)
    end
    table.sort(tools)

    local recordedProfessions = {}
    local recorded = CaerdonRecipe and CaerdonRecipe.GetRecordedTools and CaerdonRecipe:GetRecordedTools()
    if type(recorded) == "table" then
        for professionName, entry in pairs(recorded) do
            local count = 0
            if type(entry) == "table" and type(entry.names) == "table" then
                for _ in pairs(entry.names) do
                    count = count + 1
                end
            end
            recordedProfessions[#recordedProfessions + 1] = string.format("%s (%d)", professionName, count)
        end
        table.sort(recordedProfessions)
    end

    return {
        carriedInBags = ctx.carriedInBags,
        namesPending = ctx.namesPending,
        professions = professions,
        tools = tools,
        recordedProfessions = recordedProfessions,
    }
end

-- Learning or dropping a profession changes which items are tools. No event is listened for
-- here: the refresh watcher reads the toon's professions on SKILL_LINES_CHANGED and refreshes
-- everything when they changed (CaerdonRefresh.lua), which empties the context above.
