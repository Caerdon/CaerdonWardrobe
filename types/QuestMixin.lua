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

    local questName = C_QuestLog.GetQuestInfo(questID)
    local level = C_QuestLog.GetQuestDifficultyLevel(questID)

    local rewards = {}
    local choices = {}
    local spellRewards = {}
    local currencyRewards = {}

    local numQuestRewards = GetNumQuestLogRewards(questID);
	for i = 1, numQuestRewards do
        local itemName, itemTexture, quantity, quality, isUsable, itemID = GetQuestLogRewardInfo(i, questID);
        rewards[i] = {
            name = itemName,
            quantity = quantity,
            quality = quality,
            isUsable = isUsable,
            itemID = itemID
        }
	end

    local numQuestChoices = GetNumQuestLogChoices(questID);
	for i = 1, numQuestChoices do
		local itemName, itemTexture, quantity, quality, isUsable, itemID = GetQuestLogChoiceInfo(i, questID);
        choices[i] = {
            name = itemName,
            quantity = quantity,
            quality = quality,
            isUsable = isUsable,
            itemID = itemID
        }
    end

    local numQuestSpellRewards = GetNumQuestLogRewardSpells(questID);
    for i = 1, numQuestSpellRewards do
        local texture, name, isTradeskillSpell, isSpellLearned, hideSpellLearnText, isBoostSpell, garrisonFollowerID, genericUnlock, spellID = GetQuestLogRewardSpell(i, questID)
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

    local numQuestCurrencies = GetNumQuestLogRewardCurrencies(questID)
    for i = 1, numQuestCurrencies do
        local name, texture, numItems, currencyID = GetQuestLogRewardCurrencyInfo(i, questID)
        currencyRewards[i] = {
            name = name,
            numItems = numItems,
            currencyID = currencyID
        }
    end

    local isOnQuest = C_QuestLog.IsOnQuest(questID)
    local totalXp, baseXp = GetQuestLogRewardXP(questID)
    local honorAmount = GetQuestLogRewardHonor(questID)
    local questHasWarModeBonus = C_QuestLog.QuestCanHaveWarModeBonus(questID);
    local rewardMoney = GetQuestLogRewardMoney(questID)
 
    -- local isWarModeDesired = C_PvP.IsWarModeDesired();
    -- if (isWarModeDesired and questHasWarModeBonus) then
    --     tooltip:AddLine(WAR_MODE_BONUS_PERCENTAGE_XP_FORMAT:format(C_PvP.GetWarModeRewardBonus()));
    -- end

    -- TODO: Review C_QuestLog in Shadowlands for more info to add - also has QuestMixin
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

    local tradeskillLineID = tagInfo.tradeskillLineIndex and select(7, GetProfessionInfo(tagInfo.tradeskillLineIndex))
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
