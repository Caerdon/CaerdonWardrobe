local TradeSkillMixin = {}

local version, build, date, tocversion = GetBuildInfo()
local isShadowlands = tonumber(build) > 35700

function TradeSkillMixin:GetName()
	return "TradeSkill"
end

function TradeSkillMixin:Init()
    return { "TRADE_SKILL_SHOW" }
end

function TradeSkillMixin:TRADE_SKILL_SHOW(name)
    if not self.isHooked then
        self.isHooked = true
        ScrollUtil.AddInitializedFrameCallback(ProfessionsFrame.CraftingPage.RecipeList.ScrollBox, function (...) self:OnInitializedFrame(...) end, self, false)

        -- ProfessionsFrame.CraftingPage.RecipeList.ScrollBox:RegisterCallback("OnDataRangeChanged", self.OnScrollBoxRangeChanged, self)
        hooksecurefunc(ProfessionsFrame.CraftingPage.SchematicForm, "Init", function (...) self:OnSchematicFormInit(...) end)
        -- hooksecurefunc(ProfessionsFrame, "Refresh", function (...) self:Refresh(...) end)
    end
end

function TradeSkillMixin:OnInitializedFrame(frame, elementData)
    -- DevTools_Dump(elementData)
    local button = frame
    local data = elementData:GetData();

    if data.recipeInfo and data.recipeInfo.hyperlink then
        local options = {
            statusProminentSize = 15,
            statusOffsetX = 2,
            statusOffsetY = 9,
            bindingScale = 0.8,
            overrideBindingPosition = "RIGHT",
            bindingOffsetY = 0,
            bindingOffsetX = 0
        }

        local item = CaerdonItem:CreateFromItemLink(data.recipeInfo.hyperlink)
        CaerdonWardrobe:UpdateButton(button, item, self, { 
            locationKey = format("recipe%d",  item:GetItemID()), -- data.recipeInfo.recipeID),
            selectedRecipeID =  data.recipeInfo.recipeID
        }, options)
    else
        CaerdonWardrobe:ClearButton(button)
    end
end

function TradeSkillMixin:OnSchematicFormInit(frame, recipeInfo)
    C_Timer.After(0, function ()
        local button = ProfessionsFrame.CraftingPage.SchematicForm.OutputIcon
        local currentRecipeInfo = ProfessionsFrame.CraftingPage.SchematicForm:GetRecipeInfo();
        local itemLink = currentRecipeInfo.hyperlink
        if itemLink then
            local options = {
            }

            local item = CaerdonItem:CreateFromItemLink(itemLink)
            CaerdonWardrobe:UpdateButton(button, item, self, { 
                locationKey = format("selectedrecipe%d",  item:GetItemID()),
                selectedRecipeID =  recipeInfo.recipeID
            }, options)
        else
            CaerdonWardrobe:ClearButton(button)
        end
    end)
end

function TradeSkillMixin:OnScrollBoxRangeChanged(sortPending)
	local scrollBox = ProfessionsFrame.CraftingPage.RecipeList.ScrollBox
	scrollBox:ForEachFrame(function(button, elementData)
        local data = elementData:GetData();

        if data.recipeInfo and data.recipeInfo.hyperlink then
            local options = {
                statusProminentSize = 15,
                statusOffsetX = 2,
                statusOffsetY = 9,
                bindingScale = 0.8,
                overrideBindingPosition = "RIGHT",
                bindingOffsetY = 0,
                bindingOffsetX = 0
            }

            local item = CaerdonItem:CreateFromItemLink(data.recipeInfo.hyperlink)
            CaerdonWardrobe:UpdateButton(button, item, self, { 
                locationKey = format("recipe%d",  item:GetItemID()), -- data.recipeInfo.recipeID),
                selectedRecipeID =  data.recipeInfo.recipeID
            }, options)
        else
            CaerdonWardrobe:ClearButton(button)
        end
    end)
end

function TradeSkillMixin:SetTooltipItem(tooltip, item, locationInfo)
    tooltip:SetHyperlink(item:GetItemLink())
end

function TradeSkillMixin:Refresh()
    -- self:OnScrollBoxRangeChanged(false)
end

function TradeSkillMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	return {
		bindingStatus = {
			shouldShow = true
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

CaerdonWardrobe:RegisterFeature(TradeSkillMixin)
