CaerdonQuest = {}
CaerdonQuestMixin = {}

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

    local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex, displayExpiration = GetQuestTagInfo(questID)
    local tradeskillLineID = tradeskillLineIndex and select(7, GetProfessionInfo(tradeskillLineIndex))
    local isWorldQuest = worldQuestType ~= nil
    local isBonusObjective = IsQuestTask(questID) and not isWorldQuest
    local isRepeatable = C_QuestLog.IsQuestReplayable(questID)
    local isCurrentlyDisabled = C_QuestLog.IsQuestDisabledForSession(questID)
    
    return {
        questID = questID,
        rewards = rewards,
        choices = choices,
        spellRewards = spellRewards,
        isOnQuest = isOnQuest,
        xpGain = totalXp,
        honorGain = honorAmount,
        hasWarModeBonus = questHasWarModeBonus,
        rewardMoney = rewardMoney,
        currencyRewards = currencyRewards,
        tagID = tagID,
        tagName = tagName,
        isWorldQuest = isWorldQuest,
        worldQuestType = worldQuestType,
        isBonusObjective = isBonusObjective,
        isRepeatable = isRepeatable,
        isCurrentlyDisabled = isCurrentlyDisabled,
        relatedTradeskill = tradeskillLineID
    }
end
