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
        -- TODO
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
    local tooltipData = self:ProcessTooltipData(GameTooltip:GetTooltipData())
    if tooltipData then
        if tooltipData.hyperlink then
            self:DumpLinkDetails(tooltipData.hyperlink)
        end

        if tooltipData.additionalHyperlink then
            self:DumpLinkDetails(tooltipData.additionalHyperlink)
        end
    end
end

function CaerdonAPIMixin:ProcessTooltipData(tooltipData)
    if not tooltipData then return end

    local data = {
        type = tooltipData.type,
        lines = {},
        isCaerdonProcessed = true
    }

    local k,v
    for k,v in pairs(tooltipData.args) do
        local key = v.field
        if v.field == "hyperlink" and data.hyperlink then -- already has a hyperlink... assuming for now that first hyperlink is a recipe / creator of this one
            if data.additionalHyperlink then
                error("Please report error - Unexpected additional hyperlink for " .. data.hyperlink)
            end
            
            key = "additionalHyperlink"
        end

        if v.colorVal then
            data[key] = v.colorVal:GenerateHexColor()
        else
            data[key] = v.stringVal or v.intVal or v.floatVal or v.colorVal or v.guidVal or v.boolVal 
        end
    end

    for kLine, vLine in pairs(tooltipData.lines) do
        data.lines[kLine] = {}

        for k,v in pairs(vLine.args) do

            if v.colorVal then
                data.lines[kLine][v.field] = v.colorVal:GenerateHexColor()
            else
                data.lines[kLine][v.field] = v.stringVal or v.intVal or v.floatVal or v.colorVal or v.guidVal or v.boolVal 
            end
        end
    end

    if data.guid and not data.hyperlink then
        data.hyperlink = C_Item.GetItemLinkByGUID(data.guid);
    end

    return data
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
