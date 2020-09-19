local AreEqual, Exists, Replace, IsTrue, IsFalse
local CustomEventTrigger = "CAERDON_SHARED_TESTS_DATA_LOADED"
local Tests
local frame

if IsAddOnLoaded("WoWUnit") then
    frame = CreateFrame("frame")
    AreEqual, Exists, Replace, IsTrue, IsFalse = WoWUnit.AreEqual, WoWUnit.Exists, WoWUnit.Replace, WoWUnit.IsTrue, WoWUnit.IsFalse
    Tests = WoWUnit("Shared Tests", CustomEventTrigger)

    frame:RegisterEvent "PLAYER_LOGIN"
    frame:SetScript("OnEvent", function(this, event, ...)
        if event == "PLAYER_LOGIN" then
            local continuableContainer = ContinuableContainer:Create();
            continuableContainer:AddContinuable(CaerdonItem:CreateFromItemLink("|cff0070dd|Hitem:93607::::::::60:581:::1:6874:1:9:50:::|h[Crafted Dreadful Gladiator's Cloak of Alacrity]|h|r"));
        
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
    beforeTestValue = CaerdonWardrobeConfig.Debug.Enabled
    CaerdonWardrobeConfig.Debug.Enabled = true
end

function Tests:AfterEach()
    CaerdonWardrobeConfig.Debug.Enabled = beforeTestValue
    beforeTestValue = nil
end

function Tests:DreadfulGladiatorsCloakNeed()
    local item = CaerdonItem:CreateFromItemLink("|cff0070dd|Hitem:93607::::::::60:581:::1:6874:1:9:50:::|h[Crafted Dreadful Gladiator's Cloak of Alacrity]|h|r")
    -- print("Test:", item:GetItemLink())
    
    local data = item:GetItemData()
    local info = data:GetTransmogInfo()

    AreEqual(true, info.isTransmog)
    AreEqual(false, info.isBindOnPickup)
    AreEqual(18277, info.appearanceID)
    AreEqual(48836, info.sourceID)
    AreEqual(info.canEquip, info.needsItem)
    AreEqual(UnitLevel("player") >= item:GetMinLevel(), info.hasMetRequirements)
    AreEqual(not info.canEquip, info.otherNeedsItem)
    AreEqual(false, info.isCompletionistItem)
    AreEqual(true, info.matchesLootSpec)
end
