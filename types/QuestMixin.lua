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
    local item = self.item
    -- TODO: Temp... pulls out quality info to allow extract link to work - may need to consolidate and use elsewhere or figure out if there's a new way to parse.
    local tempLink = self.item:GetItemLink():gsub(" |A:.*|a]", "]")
    local linkType, linkOptions, name = LinkUtil.ExtractLink(tempLink);
    if not linkOptions then return end
    
    local questID = strsplit(":", linkOptions);
    
    local waitingForItems = {}

    function ProcessTheItem(itemID)
        waitingForItems[itemID] = nil
        if not next(waitingForItems) then
            callbackFunction()
        end
    end

    function FailTheItem(itemID)
        waitingForItems[itemID] = nil
        print("Failed to load item " .. itemID)
        if not next(waitingForItems) then
            callbackFunction()
        end
    end

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

            -- Using CaerdonItemEventListener instead of CaerdonItem here to avoid recursively diving
            if not waitingForItems[itemID] then
                waitingForItems[itemID] = true
                CaerdonItemEventListener:AddCallback(itemID, GenerateClosure(ProcessTheItem, itemID), GenerateClosure(FailTheItem, itemID))
            end
        end

        for i = 1, numQuestChoices do
            local itemLink, name, texture, numItems, quality, isUsable, itemID
            if isQuestLog then
                name, texture, numItems, quality, isUsable, itemID = GetQuestLogChoiceInfo(i, questID)
            else
                name, texture, numItems, quality, isUsable, itemID = GetQuestItemInfo("choice", i)
            end

            if not waitingForItems[itemID] then
                waitingForItems[itemID] = true
                CaerdonItemEventListener:AddCallback(itemID, GenerateClosure(ProcessTheItem, itemID), GenerateClosure(FailTheItem, itemID))
            end
        end

        if #waitingForItems == 0 then
            callbackFunction()
        end
    end

    return function () end -- No cancel function for now
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
    -- TODO: Works but requires active quest log open:    local questID = QuestInfoFrame.questLog and C_QuestLog.GetSelectedQuest() or GetQuestID();

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

    local rewardCurrencies = C_QuestInfoSystem.GetQuestRewardCurrencies(questID) or {};
    numQuestCurrencies = #rewardCurrencies

    local isQuestLog = QuestInfoFrame.questLog or isWorldQuest
    if isQuestLog then
        if C_QuestLog.ShouldShowQuestRewards(questID) then
            numQuestRewards = GetNumQuestLogRewards(questID)
            numQuestChoices = GetNumQuestLogChoices(questID, true)
            totalXp, baseXp = GetQuestLogRewardXP(questID)
            honorAmount = GetQuestLogRewardHonor(questID)
            rewardMoney = GetQuestLogRewardMoney(questID)
            majorFactionRepRewards = C_QuestLog.GetQuestLogMajorFactionReputationRewards(questID);
            skillName, skillIcon, skillPoints = GetQuestLogRewardSkillPoints(questID);
        end
    else
		if ( QuestFrameRewardPanel:IsShown() or C_QuestLog.ShouldShowQuestRewards(questID) ) then
            numQuestRewards = GetNumQuestRewards()
            numQuestChoices = GetNumQuestChoices()
            totalXp, baseXp = GetRewardXP()
            honorAmount = GetRewardHonor()
            rewardMoney = GetRewardMoney()
            majorFactionRepRewards = C_QuestOffer.GetQuestOfferMajorFactionReputationRewards();
            skillName, skillIcon, skillPoints = GetRewardSkillPoints();
        end
    end

    -- TODO: Look at reworking this section to return CaerdonItems as rewards
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
        local itemLink, name, texture, numItems, quality, isUsable, itemID, isValid

        local lootType = 0; -- LOOT_LIST_ITEM
		if ( QuestInfoFrame.questLog ) then
			lootType = GetQuestLogChoiceInfoLootType(i);
		else
			lootType = GetQuestItemInfoLootType("choice", i);
		end

		if (lootType == 0) then -- LOOT_LIST_ITEM
            if isQuestLog then
                name, texture, numItems, quality, isUsable, itemID = GetQuestLogChoiceInfo(i, questID)
                itemLink = GetQuestLogItemLink("choice", i, questID)
            else
                name, texture, numItems, quality, isUsable = GetQuestItemInfo("choice", i)
                itemLink = GetQuestItemLink("choice", i)
            end
        elseif (lootType == 1) then -- LOOT_LIST_CURRENCY
			local currencyInfo = QuestInfoFrame.questLog and C_QuestLog.GetQuestRewardCurrencyInfo(questItem.questID, i, isChoice) or C_QuestOffer.GetQuestRewardCurrencyInfo("choice", i);

            isValid = currencyInfo and currencyInfo.currencyID ~= nil;

            name = currencyInfo.name
            quantity = currencyInfo.totalRewardAmount
            quality = currencyInfo.quality
            itemID = currencyInfo.currencyID
            itemLink = C_CurrencyInfo.GetCurrencyLink(itemID, quantity)

            local factionID = C_CurrencyInfo.GetFactionGrantedByCurrency(itemID)
            local hasMaxRenown = C_MajorFactions.HasMaximumRenown(factionID)
            isUsable = not hasMaxRenown
        end

        choices[i] = {
            name = name,
            quantity = numItems,
            quality = quality,
            isUsable = isUsable,
            itemID = itemID,
            itemLink = itemLink,
            isValid = isValid
        }
    end

    local spellRewards = C_QuestInfoSystem.GetQuestRewardSpells(questID) or {};
	for i, spellID in ipairs(spellRewards) do
		if spellID and spellID > 0 then
			local spellInfo = C_QuestInfoSystem.GetQuestRewardSpellInfo(questID, spellID);
			local knownSpell = IsSpellKnownOrOverridesKnown(spellID);
            local canLearn = false;

			-- only allow the spell reward if user can learn it
			if spellInfo then
                if spellInfo.texture and not knownSpell and (not spellInfo.isBoostSpell or IsCharacterNewlyBoosted()) and (not spellInfo.garrFollowerID or not C_Garrison.IsFollowerCollected(spellInfo.garrFollowerID)) then
                    canLearn = true
                end

                spellRewards[i] = {
                    name = spellInfo.name,
                    isTradeskillSpell = spellInfo.isTradeskill,
                    isSpellLearned = spellInfo.isSpellLearned,
                    canLearn = canLearn,
                    isBoostSpell = spellInfo.isBoostSpell,
                    garrisonFollowerID = spellInfo.garrFollowerID,
                    spellID = spellID,
                    genericUnlock = spellInfo.genericUnlock,
                    type = spellInfo.type
                }
            end
        end
    end

    numQuestCurrencies = #rewardCurrencies
    for index, currencyReward in ipairs(rewardCurrencies) do
        isValid = currencyReward and currencyReward.currencyID ~= nil;
        local name = currencyReward.name
        local currencyID = currencyReward.currencyID
        local itemLink = C_CurrencyInfo.GetCurrencyLink(currencyID, quantity)

        currencyRewards[index] = {
            isValid = isValid,
            name = name,
            numItems = numItems,
            currencyID = currencyID,
            itemLink = itemLink
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
