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
    elseif caerdonType == CaerdonItemType.Equipment then
            itemResults = itemData:GetTransmogInfo()
    elseif caerdonType == CaerdonItemType.Quest then
        itemResults = itemData:GetQuestInfo()
    elseif caerdonType == CaerdonItemType.Recipe then
        itemResults = itemData:GetRecipeInfo()
    end

    return {
        forDebugUse = item:GetForDebugUse(),
        itemResults = itemResults
    }
end

function CaerdonAPIMixin:DumpMouseoverLinkDetails()
    local link = select(2, GameTooltip:GetItem())
    self:DumpLinkDetails(link)
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

CaerdonAPI = CreateFromMixins(CaerdonAPIMixin)
CaerdonAPI:OnLoad()
