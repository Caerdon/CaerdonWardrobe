local ADDON_NAME, namespace = ...
local L = namespace.L

-- Skillet's profession window: the status icon of what a recipe makes on each row of its
-- recipe list, and on the icon of the recipe that is selected, as the game's own profession
-- window has them (features/TradeSkill.lua).
--
-- Skillet calls a function registered with AddPreButtonShowCallback just before it shows a row:
-- (button, trade, skillIndex, row, recipeID), with no recipe ID for a header's row. What the
-- function returns is taken as a button to show in the row's place, so this one returns nothing.
-- The rows are a fixed set that is filled again at every scroll.

local addonName = "Skillet"
local SkilletMixin = {}

function SkilletMixin:GetName()
    return addonName
end

-- Where this feature attaches to Skillet (the integration report; see FeatureMixin.lua).
SkilletMixin.integration = {
    addon = addonName,
    hookPoints = { "Skillet:AddPreButtonShowCallback" },
    optionalHookPoints = { "Skillet:AddPreButtonHideCallback", "Skillet.UpdateDetailWindow" },
}

-- An error of this feature's must not end Skillet's own pass over its rows.
local function Guarded(method, feature, ...)
    local ok, problem = pcall(method, feature, ...)
    if not ok then
        geterrorhandler()(problem)
    end
end

function SkilletMixin:Init()
    if self:NoteHookPoint("Skillet:AddPreButtonShowCallback", Skillet, "AddPreButtonShowCallback") then
        Skillet:AddPreButtonShowCallback(function(button, trade, skillIndex, row, recipeID)
            Guarded(self.OnRowShown, self, button, recipeID)
        end)
    end
    if self:NoteHookPoint("Skillet:AddPreButtonHideCallback", Skillet, "AddPreButtonHideCallback") then
        Skillet:AddPreButtonHideCallback(function(button)
            Guarded(self.OnRowHidden, self, button)
        end)
    end
    if self:NoteHookPoint("Skillet.UpdateDetailWindow", Skillet, "UpdateDetailWindow") then
        hooksecurefunc(Skillet, "UpdateDetailWindow", function()
            Guarded(self.OnDetailUpdated, self)
        end)
    end
end

-- What a recipe makes: a link, or failing that an item ID, or nothing.
--
-- The client's word comes first, as in the game's own window (the recipe info's hyperlink). It
-- answers for the profession that is open, which is the one Skillet shows. Skillet's own record
-- of the recipe has the spell the client knows it by and the item it makes, for a recipe the
-- client says nothing of (one of another toon's that Skillet kept).
function SkilletMixin:GetRecipeOutput(recipeID)
    if type(recipeID) ~= "number" or recipeID <= 0 then
        return nil
    end

    local recipe
    if type(Skillet.GetRecipe) == "function" then
        local ok, found = pcall(Skillet.GetRecipe, Skillet, recipeID)
        if ok and type(found) == "table" then
            recipe = found
        end
    end

    local spellID = recipeID
    if recipe and type(recipe.spellID) == "number" and recipe.spellID > 0 then
        spellID = recipe.spellID
    end
    local recipeInfo = C_TradeSkillUI.GetRecipeInfo(spellID)
    if recipeInfo then
        -- The client knows the recipe: where it names nothing made, nothing is.
        if type(recipeInfo.hyperlink) == "string" and recipeInfo.hyperlink ~= "" then
            return recipeInfo.hyperlink
        end
        return nil
    end

    -- Skillet's record has the recipe's own ID in the item's place for a recipe that makes no
    -- item, which the client was then asked to load at every row shown (retail 12.1.5,
    -- Skillet 5.68): only an ID the client calls an item is one.
    local itemID = recipe and tonumber(recipe.itemID)
    if itemID and itemID > 0 and C_Item.GetItemInfoInstant(itemID) ~= nil then
        return itemID
    end
    return nil
end

local ROW_ICON_SIZE = 13

-- A row is a line of text 16 high: an arrow or a star at its left, a level, the recipe's name,
-- and counts at its right edge. The icon goes right behind the name, before the counts where
-- the name runs that far. Read off the row as Skillet has just filled it.
function SkilletMixin:GetRowOptions(button)
    local rowName = button.GetName and button:GetName()
    local level = rowName and _G[rowName .. "Level"]
    local name = rowName and _G[rowName .. "Name"]
    local counts = rowName and _G[rowName .. "Counts"]

    -- The level's text starts 16 from the row's left edge and the name follows it.
    local nameLeft = 16 + (level and level:GetWidth() or 0)
    local nameRoom = (button:GetWidth() or 0) - nameLeft - (counts and counts:IsShown() and counts:GetWidth() or 0)
    local nameWidth = name and name:GetStringWidth() or 0
    if nameRoom > 0 and nameWidth > nameRoom - ROW_ICON_SIZE then
        nameWidth = nameRoom - ROW_ICON_SIZE
    end

    local iconCentre = nameLeft + math.max(nameWidth, 0) + ROW_ICON_SIZE / 2 + 2
    return {
        fixedLayout = true,
        overrideStatusPosition = "LEFT",
        statusProminentSize = ROW_ICON_SIZE,
        statusOffsetX = iconCentre,
        statusOffsetY = 0,
        -- A number that goes with the icon (a piece's level gain, a decor's house XP) stands
        -- right behind it: the row's bottom right, where it would go, is Skillet's counts.
        levelGainAnchor = { point = "LEFT", x = iconCentre + ROW_ICON_SIZE / 2 + 2, y = 0 },
    }
end

function SkilletMixin:OnRowShown(button, recipeID)
    local output = self:GetRecipeOutput(recipeID)
    if not output then
        -- A header's row, or a recipe that makes nothing to show.
        CaerdonWardrobe:ClearButton(button)
        return
    end
    self:Decorate(button, output, {
        locationKey = format("recipe%d", recipeID),
        selectedRecipeID = recipeID,
    }, self:GetRowOptions(button))
end

function SkilletMixin:OnRowHidden(button)
    CaerdonWardrobe:ClearButton(button)
end

-- The recipe that is selected, on the icon of what it makes. Skillet keeps what it knows of
-- that recipe (currentRecipeInfo) and hides the icon where there is nothing to show.
function SkilletMixin:OnDetailUpdated()
    local button = SkilletSkillIcon
    if not button then
        return
    end
    local selected = Skillet.currentRecipeInfo
    local recipeID = type(selected) == "table" and selected.recipeID or nil
    local output = button:IsShown() and self:GetRecipeOutput(recipeID) or nil
    if not output then
        CaerdonWardrobe:ClearButton(button)
        return
    end
    self:Decorate(button, output, {
        locationKey = format("selectedrecipe%d", recipeID),
        selectedRecipeID = recipeID,
        isSelectedRecipe = true,
    }, {})
end

-- What this window shows of an item (FeatureMixin.lua, displayRules): what the game's own
-- profession window shows, by the same setting for what another toon can learn. A row has no
-- binding text: its right edge is Skillet's own counts, and the text was drawn across them
-- (retail 12.1.5, Skillet 5.68). The selected recipe's icon has room for it.
SkilletMixin.displayRules = {
    bindingStatus = false,
    ownIcon = true,
    otherIcon = "TradeSkill",
    questIcon = false,
    oldExpansionIcon = false,
    sellableIcon = false,
}
local SELECTED_RECIPE_RULES = {
    bindingStatus = true,
    ownIcon = true,
    otherIcon = "TradeSkill",
    questIcon = false,
    oldExpansionIcon = false,
    sellableIcon = false,
}

function SkilletMixin:GetDisplayRules(button, item, feature, locationInfo)
    return locationInfo and locationInfo.isSelectedRecipe and SELECTED_RECIPE_RULES or self.displayRules
end

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
    if C_AddOns.IsAddOnLoaded(addonName) then
        Version = C_AddOns.GetAddOnMetadata(addonName, "Version")
        CaerdonWardrobe:RegisterFeature(SkilletMixin)
        isActive = true
    end
end

-- WagoAnalytics:Switch(addonName, isActive)
