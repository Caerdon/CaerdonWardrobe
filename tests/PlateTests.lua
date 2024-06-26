local AreEqual, Exists, Replace, IsTrue, IsFalse
local CustomEventTrigger = "CAERDON_PLATE_TESTS_DATA_LOADED"
local Tests
local frame

if C_AddOns.IsAddOnLoaded("WoWUnit") then
    frame = CreateFrame("frame")
    AreEqual, Exists, Replace, IsTrue, IsFalse = WoWUnit.AreEqual, WoWUnit.Exists, WoWUnit.Replace, WoWUnit.IsTrue, WoWUnit.IsFalse
    Tests = WoWUnit("Plate Tests", CustomEventTrigger)

    frame:RegisterEvent "FIRST_FRAME_RENDERED"
    frame:SetScript("OnEvent", function(this, event, ...)
        if event == "FIRST_FRAME_RENDERED" then
            local continuableContainer = ContinuableContainer:Create();
            -- continuableContainer:AddContinuable(CaerdonItem:CreateFromItemLink("|cff1eff00|Hitem:68751::::::::60:581:::1:6654:2:9:15:28:73:::|h[Imbued Pioneer Bracers]|h|r"));
        
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
