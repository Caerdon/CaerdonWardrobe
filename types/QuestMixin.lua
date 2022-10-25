CaerdonQuest = {}
CaerdonQuestMixin = {}

local version, build, date, tocversion = GetBuildInfo()

--[[static]] function CaerdonQuest:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonQuest:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonWardrobeItemDataMixin, CaerdonQuestMixin)
    itemType.item = caerdonItem
    return itemType
end

function CaerdonQuestMixin:LoadQuestRewardData(callbackFunction)
    local cancelFunc = function() end;

    local item = self.item
    -- TODO: Temp... pulls out quality info to allow extract link to work - may need to consolidate and use elsewhere or figure out if there's a new way to parse.
    local tempLink = self.item:GetItemLink():gsub(" |A:.*|a]", "]")
    local linkType, linkOptions, name = LinkUtil.ExtractLink(tempLink);
    local questID = strsplit(":", linkOptions);
    
    local numQuestRewards
    local numQuestChoices

    local isWorldQuest = C_QuestLog.IsWorldQuest(questID)

    local isQuestLog = QuestInfoFrame.questLog or isWorldQuest
    if isQuestLog then
        numQuestRewards = GetNumQuestLogRewards(questID)
        numQuestChoices = GetNumQuestLogChoices(questID)
    else
        numQuestRewards = GetNumQuestRewards()
        numQuestChoices = GetNumQuestChoices()
    end

    if numQuestRewards == 0 and numQuestChoices == 0 then
        callbackFunction()
    else
        local continuableContainer = ContinuableContainer:Create();
        for i = 1, numQuestRewards do
            local itemLink, name, texture, numItems, quality, isUsable, itemID
            if isQuestLog then
                name, texture, numItems, quality, isUsable, itemID = GetQuestLogRewardInfo(i, questID)
            else
                name, texture, numItems, quality, isUsable, itemID = GetQuestItemInfo("reward", i)
            end

            local item = Item:CreateFromItemID(itemID)
            if not item:IsItemEmpty() then
                continuableContainer:AddContinuable(item);
            end
        end

        for i = 1, numQuestChoices do
            local itemLink, name, texture, numItems, quality, isUsable, itemID
            if isQuestLog then
                name, texture, numItems, quality, isUsable, itemID = GetQuestLogChoiceInfo(i, questID)
            else
                name, texture, numItems, quality, isUsable, itemID = GetQuestItemInfo("choice", i)
            end

            local item = Item:CreateFromItemID(itemID)
            if not item:IsItemEmpty() then
                continuableContainer:AddContinuable(item);
            end
        end

        cancelFunc = continuableContainer:ContinueOnLoad(callbackFunction);
    end

    return cancelFunc
end


function CaerdonQuestMixin:ContinueOnItemDataLoad(callbackFunction)
    if type(callbackFunction) ~= "function" then
        error("Usage: ContinueOnItemDataLoad(callbackFunction)", 2);
    end

    self:LoadQuestRewardData(callbackFunction)
end

-- Allows for override of continue return if additional data needs to get loaded from a specific mixin (i.e. equipment sources)
function CaerdonQuestMixin:ContinueWithCancelOnItemDataLoad(callbackFunction)
    if type(callbackFunction) ~= "function" then
        error("Usage: ContinueWithCancelOnItemDataLoad(callbackFunction)", 2);
    end

    return self:LoadQuestRewardData(callbackFunction)
end

function CaerdonQuestMixin:GetQuestInfo()
    local item = self.item
    local linkType, linkOptions, name = LinkUtil.ExtractLink(self.item:GetItemLink());
    local questID = strsplit(":", linkOptions);

    local questName = C_QuestLog.GetTitleForQuestID(questID)

    local level = C_QuestLog.GetQuestDifficultyLevel(questID)

    local rewards = {}
    local choices = {}
    local spellRewards = {}
    local currencyRewards = {}

    local numQuestRewards
    local numQuestChoices
    local numQuestSpellRewards
    local numQuestCurrencies
    local totalXp, baseXp
    local honorAmount
    local rewardMoney
    local majorFactionRepRewards
    local skillName, skillIcon, skillPoints

    local tagInfo
    local isWorldQuest
    local isBonusObjective

    tagInfo = C_QuestLog.GetQuestTagInfo(questID)
    isWorldQuest = C_QuestLog.IsWorldQuest(questID)
    isBonusObjective = (C_QuestLog.IsQuestTask(questID) and not isWorldQuest)

    local isQuestLog = QuestInfoFrame.questLog or isWorldQuest
    if isQuestLog then
        numQuestRewards = GetNumQuestLogRewards(questID)
        numQuestChoices = GetNumQuestLogChoices(questID, true)
        numQuestSpellRewards = GetNumQuestLogRewardSpells(questID)
        numQuestCurrencies = GetNumQuestLogRewardCurrencies(questID)
        totalXp, baseXp = GetQuestLogRewardXP(questID)
        honorAmount = GetQuestLogRewardHonor(questID)
        rewardMoney = GetQuestLogRewardMoney(questID)
        majorFactionRepRewards = C_QuestLog.GetQuestLogMajorFactionReputationRewards(questID);
        skillName, skillIcon, skillPoints = GetQuestLogRewardSkillPoints(questID);
    else
        numQuestRewards = GetNumQuestRewards()
        numQuestChoices = GetNumQuestChoices()
        numQuestSpellRewards = GetNumRewardSpells()
        numQuestCurrencies = GetNumRewardCurrencies()
        totalXp, baseXp = GetRewardXP()
        honorAmount = GetRewardHonor()
        rewardMoney = GetRewardMoney()
        majorFactionRepRewards = C_QuestOffer.GetQuestOfferMajorFactionReputationRewards();
        skillName, skillIcon, skillPoints = GetRewardSkillPoints();
    end

    for i = 1, numQuestRewards do
        local itemLink, name, texture, numItems, quality, isUsable, itemID
        if isQuestLog then
            name, texture, numItems, quality, isUsable, itemID = GetQuestLogRewardInfo(i, questID)
            itemLink = GetQuestLogItemLink("reward", i, questID)
        else
            name, texture, numItems, quality, isUsable = GetQuestItemInfo("reward", i)
            itemLink = GetQuestItemLink("reward", i)
        end

        rewards[i] = {
            name = name,
            quantity = numItems,
            quality = quality,
            isUsable = isUsable,
            itemID = itemID,
            itemLink = itemLink
        }
	end

    for i = 1, numQuestChoices do
        local itemLink, name, texture, numItems, quality, isUsable, itemID
        if isQuestLog then
            name, texture, numItems, quality, isUsable, itemID = GetQuestLogChoiceInfo(i, questID)
            itemLink = GetQuestLogItemLink("choice", i, questID)
        else
            name, texture, numItems, quality, isUsable = GetQuestItemInfo("choice", i)
            itemLink = GetQuestItemLink("choice", i)
        end

        choices[i] = {
            name = name,
            quantity = numItems,
            quality = quality,
            isUsable = isUsable,
            itemID = itemID,
            itemLink = itemLink
        }
    end

    for i = 1, numQuestSpellRewards do
        local texture, name, isTradeskillSpell, isSpellLearned, hideSpellLearnText, isBoostSpell, garrisonFollowerID, genericUnlock, spellID
        if isQuestLog then
            texture, name, isTradeskillSpell, isSpellLearned, hideSpellLearnText, isBoostSpell, garrisonFollowerID, genericUnlock, spellID = GetQuestLogRewardSpell(i, questID)
        else
            texture, name, isTradeskillSpell, isSpellLearned, hideSpellLearnText, isBoostSpell, garrisonFollowerID, genericUnlock, spellID = GetRewardSpell(i)
        end

        spellRewards[i] = {
            name = name,
            isTradeskillSpell = isTradeskillSpell,
            isSpellLearned = isSpellLearned,
            isBoostSpell = isBoostSpell,
            garrisonFollowerID = garrisonFollowerID,
            spellID = spellID,
            genericUnlock = genericUnlock
        }
    end

    for i = 1, numQuestCurrencies do
        local name, texture, quality, amount, currencyID;
        if isQuestLog then
            name, texture, amount, currencyID, quality = GetQuestLogRewardCurrencyInfo(i, questID)
        else
            name, texture, amount, quality = GetQuestCurrencyInfo("reward", i);
            currencyID = GetQuestCurrencyID("reward", i);
        end
    
        currencyRewards[i] = {
            name = name,
            numItems = numItems,
            currencyID = currencyID
        }
    end

    local isOnQuest = C_QuestLog.IsOnQuest(questID)
    local questHasWarModeBonus = C_QuestLog.QuestCanHaveWarModeBonus(questID);
 
    -- local isWarModeDesired = C_PvP.IsWarModeDesired();
    -- if (isWarModeDesired and questHasWarModeBonus) then
    --     tooltip:AddLine(WAR_MODE_BONUS_PERCENTAGE_XP_FORMAT:format(C_PvP.GetWarModeRewardBonus()));
    -- end

    -- TODO: Review C_QuestLog in Shadowlands for more info to add - also has QuestMixin
    local tradeskillLineID = tagInfo and tagInfo.tradeskillLineIndex and select(7, GetProfessionInfo(tagInfo.tradeskillLineIndex))
    local isRepeatable = C_QuestLog.IsQuestReplayable(questID)
    local isCurrentlyDisabled = C_QuestLog.IsQuestDisabledForSession(questID)
    
    return {
        name = questName,
        questID = questID,
        level = level,
        rewards = rewards,
        choices = choices,
        spellRewards = spellRewards,
        isOnQuest = isOnQuest,
        xpGain = totalXp,
        honorGain = honorAmount,
        hasWarModeBonus = questHasWarModeBonus,
        rewardMoney = rewardMoney,
        currencyRewards = currencyRewards,
        tagInfo = tagInfo,
        tagID = tagID,
        tagName = tagName,
        isWorldQuest = isWorldQuest,
        worldQuestType = worldQuestType,
        isBonusObjective = isBonusObjective,
        isRepeatable = isRepeatable,
        isCurrentlyDisabled = isCurrentlyDisabled,
        tradeskillLineID = tradeskillLineID
    }
end
