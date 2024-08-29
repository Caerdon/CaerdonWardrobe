local CaerdonAPIMixin = {}
CaerdonAPI = {}

StaticPopupDialogs.CopyLinkPopup = {
    text = "Item Link String",
	button1 = OKAY,
    OnAccept = function(self)
        local linkText = self.editBox:GetText()
        local selectedLink = gsub(linkText, "\124\124", "\124")
        print(selectedLink)
    end,
    hasEditBox = true,
    enterClicksFirstButton = true,  -- TODO: Not sure why these aren't working ... might need OnKeyDown?
	whileDead = true,
	hideOnEscape = true
}

function CaerdonAPIMixin:OnLoad()
end

function CaerdonAPIMixin:CopyMouseoverLink()
    local link = select(2, GameTooltip:GetItem())
    self:CopyLink(link)
end

function CaerdonAPIMixin:DumpLinkDetails(link)
    if link then
        local originalValue = CaerdonWardrobeConfig.Debug.Enabled
        CaerdonWardrobeConfig.Debug.Enabled = true

        local originalMax = DEVTOOLS_MAX_ENTRY_CUTOFF
        DEVTOOLS_MAX_ENTRY_CUTOFF = 300

        SlashCmdList.DUMP(format("CaerdonAPI:GetItemDetails(CaerdonItem:CreateFromItemLink(\"%s\"))", link))

        DEVTOOLS_MAX_ENTRY_CUTOFF = originalMax
        CaerdonWardrobeConfig.Debug.Enabled = originalValue
    end
end

function CaerdonAPIMixin:GetItemDetails(item)
    local itemData = item:GetItemData()
    local itemResults
    local caerdonType = item:GetCaerdonItemType()

    if caerdonType == CaerdonItemType.BattlePet then
        itemResults = itemData:GetBattlePetInfo()
    elseif caerdonType == CaerdonItemType.CompanionPet then
        itemResults = itemData:GetCompanionPetInfo()
    elseif caerdonType == CaerdonItemType.Conduit then
        itemResults = itemData:GetConduitInfo()
    elseif caerdonType == CaerdonItemType.Consumable then
        itemResults = itemData:GetConsumableInfo()
    elseif caerdonType == CaerdonItemType.Currency then
        itemResults = itemData:GetCurrencyInfo()
    elseif caerdonType == CaerdonItemType.Equipment then
        itemResults = itemData:GetTransmogInfo()
    elseif caerdonType == CaerdonItemType.Mount then
        itemResults = itemData:GetMountInfo()
    elseif caerdonType == CaerdonItemType.Profession then
        itemResults = itemData:GetProfessionInfo()
    elseif caerdonType == CaerdonItemType.Quest then
        itemResults = itemData:GetQuestInfo()
    elseif caerdonType == CaerdonItemType.Recipe then
        itemResults = itemData:GetRecipeInfo()
    elseif caerdonType == CaerdonItemType.Toy then
        itemResults = itemData:GetToyInfo()
    end

    return {
        caerdonType = caerdonType,
        forDebugUse = item:GetForDebugUse(),
        itemResults = itemResults
    }
end

function CaerdonAPIMixin:DumpMouseoverLinkDetails()
    local tooltipData = GameTooltip:GetPrimaryTooltipData()
    if tooltipData then
        if tooltipData.hyperlink then
            self:DumpLinkDetails(tooltipData.hyperlink)
        end

        if tooltipData.additionalHyperlink then
            self:DumpLinkDetails(tooltipData.additionalHyperlink)
        end
    end
end

function CaerdonAPIMixin:CopyLink(itemLink)
    if not itemLink then return end

    local dialog = StaticPopup_Show("CopyLinkPopup")
    dialog.editBox:SetText(gsub(itemLink, "\124", "\124\124"))
    dialog.editBox:HighlightText()
end

function CaerdonAPIMixin:MergeTable(destination, source)
    for k,v in pairs(source) do destination[k] = v end
    return destination
end

-- Leveraging canEquip for now
-- function CaerdonAPIMixin:GetClassArmor()
--     local playerClass, englishClass = UnitClass("player");
--     if (englishClass == "ROGUE" or englishClass == "DRUID" or englishClass == "MONK" or englishClass == "DEMONHUNTER") then
--         classArmor = Enum.ItemArmorSubclass.Leather;
--     elseif (englishClass == "WARRIOR" or englishClass == "PALADIN" or englishClass == "DEATHKNIGHT") then
--         classArmor = Enum.ItemArmorSubclass.Plate;
--     elseif (englishClass == "MAGE" or englishClass == "PRIEST" or englishClass == "WARLOCK") then
--         classArmor = Enum.ItemArmorSubclass.Cloth;
--     elseif (englishClass == "SHAMAN" or englishClass == "HUNTER") then
--         classArmor = Enum.ItemArmorSubclass.Mail;
--     end

--     return classArmor
-- end

function CaerdonAPIMixin:CompareCIMI(feature, item, bag, slot)
    if CaerdonWardrobeConfig.Debug.Enabled and CanIMogIt and not item:IsItemEmpty() and item:GetCaerdonItemType() == CaerdonItemType.Equipment then
        item:ContinueOnItemLoad(function ()
            local itemData = item:GetItemData()
            local transmogInfo = itemData:GetTransmogInfo()
            local isReady, mogStatus, bindingStatus, bindingResult = item:GetCaerdonStatus(feature, { bag = bag, slot = slot })

            local mismatch = true

            local modifiedText, compareText = CanIMogIt:GetTooltipText(item:GetItemLink(), bag, slot)
            if compareText == CanIMogIt.KNOWN or compareText == CanIMogIt.KNOWN_BOE or compareText == CanIMogIt.KNOWN_BY_ANOTHER_CHARACTER or compareText == CanIMogIt.KNOWN_BY_ANOTHER_CHARACTER_BOE or
            compareText == CanIMogIt.KNOWN_BUT_TOO_LOW_LEVEL or compareText == CanIMogIt.KNOWN_BUT_TOO_LOW_LEVEL_BOE then
                if mogStatus == "collected" or mogStatus == "sellable" or mogStatus == "upgrade" or mogStatus == "" then
                    mismatch = false
                end
            elseif compareText == CanIMogIt.KNOWN_FROM_ANOTHER_ITEM_BUT_TOO_LOW_LEVEL or compareText == CanIMogIt.KNOWN_FROM_ANOTHER_ITEM_BUT_TOO_LOW_LEVEL_BOE then
                if mogStatus == "lowSkillPlus" then
                    mismatch = false
                end
            elseif compareText == CanIMogIt.NOT_TRANSMOGABLE or compareText == CanIMogIt.NOT_TRANSMOGABLE_BOE then
                if mogStatus == "collected" or mogStatus == "sellable" or mogStatus == "upgrade" then
                    mismatch = false
                end
            elseif compareText == CanIMogIt.UNKNOWABLE_SOULBOUND then
                if not transmogInfo.needsItem and transmogInfo.otherNeedsItem then
                    if mogStatus == "collected" or mogStatus == "sellable" or mogStatus == "upgrade" then
                        mismatch = false
                    end
                end
            elseif compareText == CanIMogIt.UNKNOWABLE_BY_CHARACTER then
                if mogStatus == "other" or mogStatus == "otherPlus" then
                    mismatch = false
                end
            elseif compareText == CanIMogIt.KNOWN_FROM_ANOTHER_ITEM_AND_CHARACTER or compareText == CanIMogIt.KNOWN_FROM_ANOTHER_ITEM_AND_CHARACTER_BOE then
                if mogStatus == "otherPlus" then
                    mismatch = false
                end
            elseif compareText == CanIMogIt.KNOWN_FROM_ANOTHER_ITEM or compareText == CanIMogIt.KNOWN_FROM_ANOTHER_ITEM_BOE then
                if mogStatus == "ownPlus" or mogStatus == "lowSkill" then
                    mismatch = false
                end
            elseif compareText == CanIMogIt.UNKNOWN then
                if mogStatus == "lowSkill" or mogStatus == "own" then
                    mismatch = false
                end
            elseif compareText == nil then
                print("Caerdon (Debug Mode): Close and reopen bags. CIMI data not yet ready: " .. item:GetItemLink())
                mismatch = false
            else
                print("Caerdon (Debug Mode): CIMI Unknown - " .. item:GetItemLink() .. ": " .. tostring(compareText) .. " vs. " .. mogStatus)
            end

            if mismatch then
                print("Caerdon (Debug Mode): CIMI Mismatch - " .. item:GetItemLink() .. " " .. tostring(compareText) .. " vs. " .. mogStatus)
            end
        end)
    end
end

CaerdonAPI = CreateFromMixins(CaerdonAPIMixin)
CaerdonAPI:OnLoad()
