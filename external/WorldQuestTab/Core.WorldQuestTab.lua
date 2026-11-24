local ADDON_NAME, namespace = ...
local L = namespace.L

-- World Quest Tab: the status of a world quest's item rewards on the reward icons of its list,
-- and of a quest's best reward on its pin on the map.
--
-- Its list is a scroll box of rows that are filled again as it scrolls, so a row is taken when
-- the scroll box has just set it up (ScrollUtil.AddInitializedFrameCallback), with the quest
-- of the row in the element's data. Its pins say when one is set up through its own callback
-- registry ("WQT.MapPinProvider.PinInitialized"). Written against World Quest Tab 12.1.05;
-- the mixins of its rows and pins are its own and not reachable, the frames they are on are.

local addonName = "WorldQuestTab"
local WorldQuestTabMixin = {}

function WorldQuestTabMixin:GetName()
    return addonName
end

-- Where this feature attaches to World Quest Tab (the integration report; see FeatureMixin.lua).
WorldQuestTabMixin.integration = {
    addon = addonName,
    hookPoints = { "WQT_ListContainer:GetQuestScrollBox" },
    optionalHookPoints = { "WQT_CallbackRegistry:RegisterCallback" },
}

-- An error of this feature's must not end the scroll box's or the pin provider's own pass.
local function Guarded(method, feature, ...)
    local ok, problem = pcall(method, feature, ...)
    if not ok then
        geterrorhandler()(problem)
    end
end

function WorldQuestTabMixin:Init()
    local list = WQT_ListContainer
    if self:NoteHookPoint("WQT_ListContainer:GetQuestScrollBox", list, "GetQuestScrollBox") then
        local scrollBox = list:GetQuestScrollBox()
        if scrollBox then
            ScrollUtil.AddInitializedFrameCallback(scrollBox, function(owner, row, elementData)
                Guarded(self.OnRowInitialized, self, row, elementData)
            end, self, false)
        end
    end
    if self:NoteHookPoint("WQT_CallbackRegistry:RegisterCallback", WQT_CallbackRegistry, "RegisterCallback") then
        WQT_CallbackRegistry:RegisterCallback("WQT.MapPinProvider.PinInitialized", function(owner, pin)
            Guarded(self.OnPinInitialized, self, pin)
        end, self)
    end
end

-- A row or a pin shows another quest by the time its item has loaded: the draw is not its own.
function WorldQuestTabMixin:IsSameItem(button, item, locationInfo)
    local owner = locationInfo.owner
    return owner == nil or owner.questID == locationInfo.questID
end

-- The kinds of reward World Quest Tab makes from an item of the quest's rewards.
local function IsItemReward(rewardInfo)
    local types = WQT_REWARDTYPE
    if type(types) ~= "table" or type(rewardInfo.type) ~= "number" then
        return false
    end
    local items = bit.bor(types.weapon or 0, types.equipment or 0, types.conduit or 0, types.relic or 0,
        types.anima or 0, types.item or 0)
    return bit.band(rewardInfo.type, items) ~= 0
end

-- The link of one of a quest's rewards as World Quest Tab lists them. It sorts its rewards,
-- so its index is not the quest's own: the reward is found among the quest's by its item.
function WorldQuestTabMixin:GetRewardLink(questInfo, index)
    local questID = questInfo.questID
    local rewardInfo = questInfo:GetReward(index)
    if not questID or type(rewardInfo) ~= "table" or not IsItemReward(rewardInfo) then
        return nil
    end
    for rewardIndex = 1, GetNumQuestLogRewards(questID) do
        local itemID = select(6, GetQuestLogRewardInfo(rewardIndex, questID))
        if itemID == rewardInfo.id then
            return GetQuestLogItemLink("reward", rewardIndex, questID)
        end
    end
    return nil
end

function WorldQuestTabMixin:OnRowInitialized(row, elementData)
    local rewards = row.GetRewardsFrame and row:GetRewardsFrame()
    local frames = rewards and rewards.rewardFrames
    if type(frames) ~= "table" then
        return
    end
    local questInfo = type(elementData) == "table" and elementData.questInfo or row.questInfo
    for index, rewardFrame in ipairs(frames) do
        local link = questInfo and rewardFrame:IsShown() and self:GetRewardLink(questInfo, index) or nil
        if link then
            self:Decorate(rewardFrame, link, {
                locationKey = format("wqtQuest%dReward%d", questInfo.questID, index),
                questID = questInfo.questID,
                owner = row,
            }, {
                hasCount = rewardFrame.Amount ~= nil and rewardFrame.Amount:IsShown(),
                statusProminentSize = 16,
                itemCountOffset = 9,
            })
        else
            CaerdonWardrobe:ClearButton(rewardFrame)
        end
    end
end

function WorldQuestTabMixin:OnPinInitialized(pin)
    local button = pin.GetButton and pin:GetButton() or pin
    local questID = pin.questID
    local link
    if questID then
        local bestIndex, bestType = QuestUtils_GetBestQualityItemRewardIndex(questID)
        if bestIndex and bestType then
            link = GetQuestLogItemLink(bestType, bestIndex, questID)
        end
    end
    if not link then
        CaerdonWardrobe:ClearButton(button)
        return
    end
    self:Decorate(button, link, {
        locationKey = format("wqtPin%d", questID),
        questID = questID,
        owner = pin,
    }, {
        statusProminentSize = 15,
    })
end

-- What this window shows of an item (FeatureMixin.lua, displayRules). The quest icon follows
-- its setting, as in the other world quest lists. No level gain: a reward's icon is 32 wide
-- with World Quest Tab's own amount (a piece's item level) at its foot.
WorldQuestTabMixin.displayRules = {
    bindingStatus = true,
    ownIcon = true,
    otherIcon = true,
    oldExpansionIcon = false,
    sellableIcon = false,
    levelGain = false,
}

local Version = nil
local isActive = false

if select(4, C_AddOns.GetAddOnInfo(addonName)) then
    if C_AddOns.IsAddOnLoaded(addonName) then
        Version = C_AddOns.GetAddOnMetadata(addonName, "Version")
        CaerdonWardrobe:RegisterFeature(WorldQuestTabMixin)
        isActive = true
    end
end

-- WagoAnalytics:Switch(addonName, isActive)
