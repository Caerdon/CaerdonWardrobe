local AreEqual, Exists, Replace, IsTrue, IsFalse
local CustomEventTrigger = "CAERDONITEM_TESTS_DATA_LOADED"
local Tests
local frame

if IsAddOnLoaded("WoWUnit") then
    frame = CreateFrame("frame")
    AreEqual, Exists, Replace, IsTrue, IsFalse = WoWUnit.AreEqual, WoWUnit.Exists, WoWUnit.Replace, WoWUnit.IsTrue, WoWUnit.IsFalse
    Tests = WoWUnit("CaerdonItem Tests", CustomEventTrigger)

    frame:RegisterEvent "PLAYER_LOGIN"
    frame:SetScript("OnEvent", function(this, event, ...)
        if event == "PLAYER_LOGIN" then
            local continuableContainer = ContinuableContainer:Create();
            continuableContainer:AddContinuable(CaerdonItem:CreateFromItemID(6125));
        
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

function Tests:DataChangeCanary()
    local item = CaerdonItem:CreateFromItemID(6125)
    local data = item:GetItemData()
    local info = data:GetTransmogInfo()

    IsTrue(info.isTransmog)
    IsFalse(info.isBindOnPickup)
    AreEqual(1979, info.appearanceID)
    AreEqual(2260, info.sourceID)
    IsTrue(info.needsItem)
    IsTrue(info.hasMetRequirements)
    IsFalse(info.otherNeedsItem)
    IsFalse(info.isCompletionistItem)
    IsTrue(info.matchesLootSpec)
    IsTrue(info.canEquip)

    AreEqual("Armor", item:GetItemType())
    AreEqual("Miscellaneous", item:GetItemSubType())
    AreEqual(4, item:GetItemTypeID())
    AreEqual(0, item:GetItemSubTypeID())
    AreEqual("INVTYPE_BODY", item:GetEquipLocation())
    AreEqual(0, item:GetMinLevel())
    AreEqual(2, item:GetItemQuality())
    AreEqual("Bind on Equip", item:GetBinding())
    AreEqual(0, item:GetExpansionID())
    IsFalse(item:GetIsCraftingReagent())
    IsFalse(item:GetHasUse())

    local forDebugUse = item:GetForDebugUse()
    AreEqual("item", forDebugUse.linkType)
    -- TODO: Figure this out
    -- AreEqual(true, strmatch(forDebugUse.linkOptions, format("6125::::::::%d:%%d+:::::::", UnitLevel("player"))) ~= nil)
    AreEqual("[Brawler's Harness]", forDebugUse.linkDisplayText)

    local debugUse = info.forDebugUseOnly
    IsTrue(type(debugUse) == "table")
    IsTrue(debugUse.shouldSearchSources)
    IsFalse(debugUse.currentSourceFound)
    IsFalse(debugUse.otherSourceFound)
    IsTrue(debugUse.isInfoReady)

    AreEqual(1, #debugUse.appearanceSources)
    
    local appearanceSource = debugUse.appearanceSources[1]
    AreEqual(5, appearanceSource.invType)
    AreEqual(1979, appearanceSource.visualID)
    IsFalse(appearanceSource.isCollected)
    AreEqual(2260, appearanceSource.sourceID)
    IsFalse(appearanceSource.isHideVisual)
    AreEqual(6125, appearanceSource.itemID)
    AreEqual("Brawler's Harness", appearanceSource.name)
    AreEqual(0, appearanceSource.itemModID)
    AreEqual(5, appearanceSource.categoryID)
    AreEqual(2, appearanceSource.quality)

    -- See if there is any new, unexpected data coming from WoW
    local appearanceCount = 0
    for k,v in pairs(appearanceSource) do appearanceCount = appearanceCount + 1 end
    AreEqual(11, appearanceCount)

    local sourceInfo = debugUse.sourceInfo
    local sourceCount = 0
    for k,v in pairs(sourceInfo) do
        AreEqual(appearanceSource[k], v)
        sourceCount = sourceCount + 1
    end
    AreEqual(appearanceCount - 1, sourceCount) -- itemSubTypeID isn't injected, so it's one off from appearanceCount

    local infoCount = 0
    for k,v in pairs(info) do infoCount = infoCount + 1 end
    AreEqual(11, infoCount)
end

-- function Tests:MockingTest()
--     Replace('GetRealmName', function() return 'Horseshoe' end)
--     AreEqual('Horseshoe!', Realm())
-- end
