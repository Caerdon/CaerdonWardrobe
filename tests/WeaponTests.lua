local AreEqual, Exists, Replace, IsTrue, IsFalse
local CustomEventTrigger = "CAERDON_WEAPON_TESTS_DATA_LOADED"
local Tests
local frame

if IsAddOnLoaded("WoWUnit") then
    frame = CreateFrame("frame")
    AreEqual, Exists, Replace, IsTrue, IsFalse = WoWUnit.AreEqual, WoWUnit.Exists, WoWUnit.Replace, WoWUnit.IsTrue, WoWUnit.IsFalse
    Tests = WoWUnit("Weapon Tests", CustomEventTrigger)

    frame:RegisterEvent "PLAYER_LOGIN"
    frame:SetScript("OnEvent", function(this, event, ...)
        if event == "PLAYER_LOGIN" then
            local continuableContainer = ContinuableContainer:Create();
            continuableContainer:AddContinuable(CaerdonItem:CreateFromItemLink("|cff1eff00|Hitem:36445::::::::20:64:512:28:2:1695:3869:67:::|h[Riveted Shield of the Fireflash]|h|r"));
            continuableContainer:AddContinuable(CaerdonItem:CreateFromItemLink("|cff1eff00|Hitem:25114::::::::20:64:512:30:2:1707:3871:118:::|h[Doomsayer's Mace of the Aurora]|h|r"));
            continuableContainer:AddContinuable(CaerdonItem:CreateFromItemLink("|cff1eff00|Hitem:116550::::::::20:64:512:28:3:3875:103:517:96:::|h[Auchenai Mace of the Quickblade]|h|r"));
            continuableContainer:AddContinuable(CaerdonItem:CreateFromItemLink("|cff1eff00|Hitem:36495::::::::20:64:512:36:2:1707:3871:112:::|h[Ferrous Hammer of the Aurora]|h|r"));
        
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

function Tests:RivetedShieldKnownOnlyByPaladin()
    local item = CaerdonItem:CreateFromItemLink("|cff1eff00|Hitem:36445::::::::20:64:512:28:2:1695:3869:67:::|h[Riveted Shield of the Fireflash]|h|r")
    -- print("Test:", item:GetItemLink())
    
    local data = item:GetItemData()
    local info = data:GetTransmogInfo()

    AreEqual(true, info.isTransmog)
    AreEqual(false, info.isBindOnPickup)
    AreEqual(9541, info.appearanceID)
    AreEqual(17182, info.sourceID)
    AreEqual(info.canEquip, info.needsItem)
    AreEqual(UnitLevel("player") >= item:GetMinLevel(), info.hasMetRequirements)
    AreEqual(not info.canEquip, info.otherNeedsItem)
    -- TODO: Known issue: GetItemSpecInfo only returns specs if it's an item you can use.
    -- This results in not knowing an item is actually needed for appearances for other specs.
    -- Keep tabs on other API options to fix this but treat as completionist item if not wearable.
    -- The source in this case is 37445, item 72983
    -- I think it's working right now because it's lower level, so that logic kicked in
    AreEqual(false, info.isCompletionistItem) -- this is what it should be (ideally)
    AreEqual(true, info.matchesLootSpec)
end

function Tests:DoomsayerMaceNeed()
    local item = CaerdonItem:CreateFromItemLink("|cff1eff00|Hitem:25114::::::::20:64:512:30:2:1707:3871:118:::|h[Doomsayer's Mace of the Aurora]|h|r")
    -- print("Test:", item:GetItemLink())
    
    local data = item:GetItemData()
    local info = data:GetTransmogInfo()

    AreEqual(true, info.isTransmog)
    AreEqual(false, info.isBindOnPickup)
    AreEqual(5607, info.appearanceID)
    AreEqual(10111, info.sourceID)
    AreEqual(info.canEquip, info.needsItem)
    AreEqual(UnitLevel("player") >= item:GetMinLevel(), info.hasMetRequirements)
    AreEqual(not info.canEquip, info.otherNeedsItem)
    AreEqual(false, info.isCompletionistItem)
    AreEqual(true, info.matchesLootSpec)
end

function Tests:AuchenaiMaceCompletionist()
    local item = CaerdonItem:CreateFromItemLink("|cff1eff00|Hitem:116550::::::::20:64:512:28:3:3875:103:517:96:::|h[Auchenai Mace of the Quickblade]|h|r")
    -- print("Test:", item:GetItemLink())
    
    local data = item:GetItemData()
    local info = data:GetTransmogInfo()

    AreEqual(true, info.isTransmog)
    AreEqual(false, info.isBindOnPickup)
    AreEqual(22003, info.appearanceID)
    AreEqual(65412, info.sourceID)
    AreEqual(info.canEquip, info.needsItem)
    AreEqual(UnitLevel("player") >= item:GetMinLevel(), info.hasMetRequirements)
    AreEqual(not info.canEquip, info.otherNeedsItem)
    AreEqual(true, info.isCompletionistItem)
    AreEqual(true, info.matchesLootSpec)   
end

function Tests:FerrousHammerCompletionist()
    local item = CaerdonItem:CreateFromItemLink("|cff1eff00|Hitem:36495::::::::20:64:512:36:2:1707:3871:112:::|h[Ferrous Hammer of the Aurora]|h|r")
    -- print("Test:", item:GetItemLink())
    
    local data = item:GetItemData()
    local info = data:GetTransmogInfo()

    AreEqual(true, info.isTransmog)
    AreEqual(false, info.isBindOnPickup)
    AreEqual(9571, info.appearanceID)
    AreEqual(17232, info.sourceID)
    AreEqual(info.canEquip, info.needsItem)
    AreEqual(UnitLevel("player") >= item:GetMinLevel(), info.hasMetRequirements)
    AreEqual(not info.canEquip, info.otherNeedsItem)
    AreEqual(true, info.isCompletionistItem)
    AreEqual(true, info.matchesLootSpec)   
end
