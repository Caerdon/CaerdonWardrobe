local AreEqual, Exists, Replace, IsTrue, IsFalse
local CustomEventTrigger = "CAERDON_MAIL_TESTS_DATA_LOADED"
local Tests
local frame

if IsAddOnLoaded("WoWUnit") then
    frame = CreateFrame("frame")
    AreEqual, Exists, Replace, IsTrue, IsFalse = WoWUnit.AreEqual, WoWUnit.Exists, WoWUnit.Replace, WoWUnit.IsTrue, WoWUnit.IsFalse
    Tests = WoWUnit("Mail Tests", CustomEventTrigger)

    frame:RegisterEvent "PLAYER_LOGIN"
    frame:SetScript("OnEvent", function(this, event, ...)
        if event == "PLAYER_LOGIN" then
            local continuableContainer = ContinuableContainer:Create();
            continuableContainer:AddContinuable(CaerdonItem:CreateFromItemLink("|cff1eff00|Hitem:106552::::::::20:64:512:29:2:3854:107:120:::|h[Warpscale Legguards of the Quickblade]|h|r"));
        
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

function Tests:WarpscaleLegguardsCompletionist()
    local item = CaerdonItem:CreateFromItemLink("|cff1eff00|Hitem:106552::::::::20:64:512:29:2:3854:107:120:::|h[Warpscale Legguards of the Quickblade]|h|r")
    -- print("Test:", item:GetItemLink())
    
    local data = item:GetItemData()
    local info = data:GetTransmogInfo()

    AreEqual(true, info.isTransmog)
    AreEqual(false, info.isBindOnPickup)
    AreEqual(21908, info.appearanceID)
    AreEqual(57603, info.sourceID)
    AreEqual(info.canEquip, info.needsItem)
    AreEqual(UnitLevel("player") >= item:GetMinLevel(), info.hasMetRequirements)
    AreEqual(not info.canEquip, info.otherNeedsItem)
    AreEqual(true, info.isCompletionistItem)
    AreEqual(true, info.matchesLootSpec)   
end
