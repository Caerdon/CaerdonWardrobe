CaerdonQuest = {}
CaerdonQuestMixin = {}

local version, build, date, tocversion = GetBuildInfo()
local isShadowlands = tonumber(build) > 35700

--[[static]] function CaerdonQuest:CreateFromCaerdonItem(caerdonItem)
	if type(caerdonItem) ~= "table" or not caerdonItem.GetCaerdonItemType then
		error("Usage: CaerdonQuest:CreateFromCaerdonItem(caerdonItem)", 2)
	end

    local itemType = CreateFromMixins(CaerdonQuestMixin)
    itemType.item = caerdonItem
    return itemType
end

function CaerdonQuestMixin:GetQuestInfo()
    local item = self.item
    local linkType, linkOptions, name = LinkUtil.ExtractLink(self.item:GetItemLink());
    local questID = strsplit(":", linkOptions);

    local questName
    if isShadowlands then
        questName = C_QuestLog.GetTitleForQuestID(questID)
    else
        questName = C_QuestLog.GetQuestInfo(questID)
    end

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

    local tagInfo
    local isWorldQuest
    local isBonusObjective

    if isShadowlands then
        tagInfo = C_QuestLog.GetQuestTagInfo(questID)
        isWorldQuest = C_QuestLog.IsWorldQuest(questID)
        isBonusObjective = (C_QuestLog.IsQuestTask(questID) and not isWorldQuest)
    else
        local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex, displayExpiration = GetQuestTagInfo(questID)
        tagInfo = { tagID = tagID, tagName = tagName, worldQuestType = worldQuestType, rarity = rarity,
            isElite = isElite, tradeskillLineIndex = tradeSkillLineIndex, displayExpiration = displayExpiration
        }
        isWorldQuest = worldQuestType ~= nil
        isBonusObjective = IsQuestTask(questID) and not isWorldQuest
    end

    local isQuestLog = QuestInfoFrame.questLog or isWorldQuest
    if isQuestLog then
        numQuestRewards = GetNumQuestLogRewards(questID)
        numQuestChoices = GetNumQuestLogChoices(questID)
        numQuestSpellRewards = GetNumQuestLogRewardSpells(questID)
        numQuestCurrencies = GetNumQuestLogRewardCurrencies(questID)
        totalXp, baseXp = GetQuestLogRewardXP(questID)
        honorAmount = GetQuestLogRewardHonor(questID)
        rewardMoney = GetQuestLogRewardMoney(questID)
    else
        numQuestRewards = GetNumQuestRewards()
        numQuestChoices = GetNumQuestChoices()
        numQuestSpellRewards = GetNumRewardSpells()
        numQuestCurrencies = GetNumRewardCurrencies()
        totalXp, baseXp = GetRewardXP()
        honorAmount = GetRewardHonor()
        rewardMoney = GetRewardMoney()
    end

    for i = 1, numQuestRewards do
        local itemLink, name, texture, numItems, quality, isUsable, itemID
        if isQuestLog then
            name, texture, numItems, quality, isUsable, itemID = GetQuestLogRewardInfo(i, questID)
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
