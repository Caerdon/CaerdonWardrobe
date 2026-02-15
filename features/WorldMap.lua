local WorldMapMixin = {}
local version, build, date, tocversion = GetBuildInfo()

local function EnsureHoverHook(pin)
	if not pin or type(pin.HookScript) ~= "function" or pin.caerdonDebugHoverHooked then
		return
	end

	pin.caerdonDebugHoverHooked = true

	pin:HookScript("OnEnter", function(self)
		if CaerdonAPI and CaerdonAPI.SetManualHoverContext then
			local context = {
				itemLink = self.caerdonDebugItemLink,
			}
			CaerdonAPI:SetManualHoverContext(self, context)
		end
	end)

	pin:HookScript("OnLeave", function(self)
		if CaerdonAPI and CaerdonAPI.ClearManualHoverContext then
			CaerdonAPI:ClearManualHoverContext(self)
		end
	end)
end

function WorldMapMixin:GetName()
	return "WorldMap"
end

function WorldMapMixin:Init()
	hooksecurefunc (WorldMap_WorldQuestPinMixin, "RefreshVisuals", function (...)
		if not IsModifiedClick("COMPAREITEMS") and not ShoppingTooltip1:IsShown() then
			self:UpdatePin(...);
		end
	end)
end

function WorldMapMixin:GetTooltipData(item, locationInfo)
	return C_TooltipInfo.GetHyperlink(item:GetItemLink())
end

function WorldMapMixin:Refresh()
	CaerdonWardrobeFeatureMixin:Refresh(self)
	if not WorldMapFrame or not WorldMapFrame:IsShown() then
		return
	end
	for pin in WorldMapFrame:EnumeratePinsByTemplate("WorldMap_WorldQuestPinTemplate") do
		if pin.questID then
			self:UpdatePin(pin)
		end
	end
end

function WorldMapMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
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
			shouldShow = true
		},
		oldExpansionIcon = {
			shouldShow = false
		},
        sellableIcon = {
            shouldShow = false
        }
	}
end

function WorldMapMixin:UpdatePin(pin)
		-- QuestEventListener:AddCallback(pin.questID, function()
		local options = {
			statusProminentSize = 15,
			-- TODO: Review binding positioning
			bindingScale = .8,
			statusOffsetY = 10,
			statusOffsetX = 10,
			relativeFrame = pin.NormalTexture
		}

		local questLink = GetQuestLink(pin.questID)
		if not questLink then 
			local questName = C_QuestLog.GetTitleForQuestID(pin.questID)
			local questLevel = C_QuestLog.GetQuestDifficultyLevel(pin.questID)
			questLink = format("|cff808080|Hquest:%d:%d|h[%s]|h|r", pin.questID, questLevel, questName)
		end

		local questItem = CaerdonItem:CreateFromItemLink(questLink)
		local itemData = questItem:GetItemData()
		if not itemData then
			pin.caerdonDebugItemLink = nil
			CaerdonWardrobe:ClearButton(pin)
			return
		end

		-- local questInfo = itemData:GetQuestInfo()

		-- TODO: Review if necessary to iterate through rewards and find unknown ones...
		local bestIndex, bestType = QuestUtils_GetBestQualityItemRewardIndex(pin.questID)
		-- local reward
		-- if bestType == "reward" then
		-- 	reward = questInfo.rewards[bestIndex]
		-- elseif bestType == "choice" then
		-- 	reward = questInfo.choices[bestIndex]
		-- end

		if not bestType then
			pin.caerdonDebugItemLink = nil
			CaerdonWardrobe:ClearButton(pin)
			return
		end

		local itemLink = GetQuestLogItemLink(bestType, bestIndex, pin.questID)
		if not itemLink then
			pin.caerdonDebugItemLink = nil
			CaerdonWardrobe:ClearButton(pin)
			return
		end

		local item = CaerdonItem:CreateFromItemLink(itemLink)
		pin.caerdonDebugItemLink = itemLink
		EnsureHoverHook(pin)
		CaerdonWardrobe:UpdateButton(pin, item, self, {
			locationKey = format("%d", pin.questID),
			questID = pin.questID,
			questItem
		}, options)
	-- end)
end

CaerdonWardrobe:RegisterFeature(WorldMapMixin)
