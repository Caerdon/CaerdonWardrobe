local AreEqual, Exists, Replace, IsTrue, IsFalse
local CustomEventTrigger = "CAERDON_LEATHER_TESTS_DATA_LOADED"
local Tests
local frame

if IsAddOnLoaded("WoWUnit") then
    frame = CreateFrame("frame")
    AreEqual, Exists, Replace, IsTrue, IsFalse = WoWUnit.AreEqual, WoWUnit.Exists, WoWUnit.Replace, WoWUnit.IsTrue, WoWUnit.IsFalse
    Tests = WoWUnit("Leather Tests", CustomEventTrigger)

    frame:RegisterEvent "PLAYER_LOGIN"
    frame:SetScript("OnEvent", function(this, event, ...)
        if event == "PLAYER_LOGIN" then
            local continuableContainer = ContinuableContainer:Create();
            continuableContainer:AddContinuable(CaerdonItem:CreateFromItemLink("|cff1eff00|Hitem:68751::::::::60:581:::1:6654:2:9:15:28:73:::|h[Imbued Pioneer Bracers]|h|r"));
            continuableContainer:AddContinuable(CaerdonItem:CreateFromItemLink("|cff0070dd|Hitem:172790::::::::120:581::47:4:6516:6515:1537:4785:::|h[Corrupted Aspirant's Leather Gloves]|h|r"));
            continuableContainer:AddContinuable(CaerdonItem:CreateFromItemLink("|cff1eff00|Hitem:154820::::::::60:581:::2:6654:1691:2:9:36:28:190:::|h[Festerroot Jerkin of the Fireflash]|h|r"));
        
            continuableContainer:ContinueOnLoad(function()
                WoWUnit:OnEvent(CustomEventTrigger)
            end);
        end
    end)
else
    Tests = {}
end

local beforeTestValue
function Tests:BeforeEach()
    -- beforeTestValue = CaerdonWardrobeConfig.Debug.Enabled
    -- CaerdonWardrobeConfig.Debug.Enabled = true
end

function Tests:AfterEach()
    -- CaerdonWardrobeConfig.Debug.Enabled = beforeTestValue
    -- beforeTestValue = nil
end

function Tests:ImbuedPioneerBracersNeed()
    local item = CaerdonItem:CreateFromItemLink("|cff1eff00|Hitem:68751::::::::60:581:::1:6654:2:9:15:28:73:::|h[Imbued Pioneer Bracers]|h|r")
    -- print("Test:", item:GetItemLink())
    
    local data = item:GetItemData()
    local info = data:GetTransmogInfo()

    AreEqual(true, info.isTransmog)
    AreEqual(false, info.isBindOnPickup)
    AreEqual(2125, info.appearanceID)
    AreEqual(35153, info.sourceID)
    AreEqual(info.canEquip, info.needsItem)
    AreEqual(true, info.hasMetRequirements)
    AreEqual(not info.canEquip, info.otherNeedsItem)
    AreEqual(false, info.isCompletionistItem)
    AreEqual(true, info.matchesLootSpec)
end

function Tests:CorruptedAspirantGlovesKnown()
    -- Was from Shadowlands I think
    -- local item = CaerdonItem:CreateFromItemLink("|cff0070dd|Hitem:175662::::::::60:581::11:1:6706:2:9:59:28:807:::|h[Starshroud Helm]|h|r")
    local item = CaerdonItem:CreateFromItemLink("|cff0070dd|Hitem:172790::::::::120:581::47:4:6516:6515:1537:4785:::|h[Corrupted Aspirant's Leather Gloves]|h|r")
    -- print("Test:", item:GetItemLink())
    
    local data = item:GetItemData()
    local info = data:GetTransmogInfo()

    AreEqual(true, info.isTransmog)
    AreEqual(true, info.isBindOnPickup)
    AreEqual(40896, info.appearanceID)
    AreEqual(107206, info.sourceID)
    -- AreEqual(42260, info.appearanceID)
    -- AreEqual(109305, info.sourceID)
    AreEqual(false, info.needsItem)
    AreEqual(UnitLevel("player") >= item:GetMinLevel(), info.hasMetRequirements)
    AreEqual(false, info.otherNeedsItem)
    AreEqual(false, info.isCompletionistItem)
    AreEqual(true, info.matchesLootSpec)
end

function Tests:FesterrootJerkinCompletionist()
    local item = CaerdonItem:CreateFromItemLink("|cff1eff00|Hitem:154820::::::::60:581:::2:6654:1691:2:9:36:28:190:::|h[Festerroot Jerkin of the Fireflash]|h|r")
    -- print("Test:", item:GetItemLink())
    
    local data = item:GetItemData()
    local info = data:GetTransmogInfo()

    AreEqual(true, info.isTransmog)
    AreEqual(false, info.isBindOnPickup)
    AreEqual(35958, info.appearanceID)
    AreEqual(91786, info.sourceID)
    AreEqual(info.canEquip, info.needsItem)
    AreEqual(UnitLevel("player") >= item:GetMinLevel(), info.hasMetRequirements)
    AreEqual(not info.canEquip, info.otherNeedsItem)
    AreEqual(true, info.isCompletionistItem)
    AreEqual(true, info.matchesLootSpec)   
end
