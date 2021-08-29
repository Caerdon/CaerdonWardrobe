--  TradeSkillFrame.DetailsFrame  RefreshDisplay

local TradeSkillMixin = {}

local version, build, date, tocversion = GetBuildInfo()
local isShadowlands = tonumber(build) > 35700

function TradeSkillMixin:GetName()
	return "TradeSkill"
end

function TradeSkillMixin:Init()
	return { "ADDON_LOADED", "PLAYER_LOOT_SPEC_UPDATED" }
end

function TradeSkillMixin:ADDON_LOADED(name)
	if name == "Blizzard_TradeSkillUI" then
		hooksecurefunc(TradeSkillFrame.DetailsFrame, "RefreshDisplay", function (...) self:OnTradeSkillDetailsRefreshDisplay(...) end)
		hooksecurefunc(TradeSkillFrame.RecipeList, "RefreshDisplay", function (...) self:OnTradeSkillRecipeListRefreshDisplay(...) end)
		TradeSkillFrame.RecipeList.scrollBar:HookScript("OnValueChanged", function(...) self:OnRecipeListUpdate(...) end)
    end
end

function TradeSkillMixin:PLAYER_LOOT_SPEC_UPDATED()
	self:Refresh()
end

function TradeSkillMixin:SetTooltipItem(tooltip, item, locationInfo)
    tooltip:SetHyperlink(item:GetItemLink())
end

function TradeSkillMixin:Refresh()
	if TradeSkillFrame and TradeSkillFrame:IsShown() then
        self:OnTradeSkillRecipeListRefreshDisplay(TradeSkillFrame.RecipeList)
	end
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

function TradeSkillMixin:OnRecipeListUpdate()
    self:Refresh()
end

function TradeSkillMixin:OnTradeSkillRecipeListRefreshDisplay(recipeList)
	local offset = HybridScrollFrame_GetOffset(recipeList);

	for i, button in ipairs(recipeList.buttons) do
		local dataIndex = offset + i;
		local tradeSkillInfo = recipeList.dataList[dataIndex];
		if tradeSkillInfo then
			if tradeSkillInfo.type == "recipe" and tradeSkillInfo.recipeID ~= nil then
                local options = {
                    relativeFrame = button.icon,
                    statusProminentSize = 15,
                    statusOffsetX = 9,
                    statusOffsetY = 8,
                    bindingScale = 0.8,
                    overrideBindingPosition = "LEFT",
                    bindingOffsetY = 0,
                    bindingOffsetX = 25
                }
        
                local itemLink = C_TradeSkillUI.GetRecipeItemLink(tradeSkillInfo.recipeID);
                if itemLink then
                    local item = CaerdonItem:CreateFromItemLink(itemLink)
                    CaerdonWardrobe:UpdateButton(button, item, self, { 
                        locationKey = format("recipe%d", tradeSkillInfo.recipeID),
                        selectedRecipeID = tradeSkillInfo.recipeID
                    }, options)
                else
                    CaerdonWardrobe:ClearButton(button)
                end
            else
                CaerdonWardrobe:ClearButton(button)
            end
		else
			CaerdonWardrobe:ClearButton(button)
		end
	end
end

function TradeSkillMixin:OnTradeSkillDetailsRefreshDisplay(detailsFrame)
    local button = detailsFrame.Contents.ResultIcon
    local options = {
        relativeFrame = button.icon
    }

    if detailsFrame.selectedRecipeID then
        local itemLink = C_TradeSkillUI.GetRecipeItemLink(detailsFrame.selectedRecipeID);
        if itemLink then
            local item = CaerdonItem:CreateFromItemLink(itemLink)
            CaerdonWardrobe:UpdateButton(button, item, self, { 
                locationKey = format("SelectedRecipe%d", detailsFrame.selectedRecipeID),
                selectedRecipeID = detailsFrame.selectedRecipeID
            }, options)
        else
            CaerdonWardrobe:ClearButton(button)
        end
    else
        CaerdonWardrobe:ClearButton(button)
    end
end

CaerdonWardrobe:RegisterFeature(TradeSkillMixin)
