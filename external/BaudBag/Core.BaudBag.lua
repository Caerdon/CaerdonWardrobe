local ADDON_NAME, namespace = ...
local L = namespace.L

local Version, MinVersion = nil, '8.0.2'
if select(4, GetAddOnInfo('BaudBag')) then
    Version = GetAddOnMetadata('BaudBag', 'Version')
    CaerdonWardrobe:SetBagAddon()
end

if Version then

    local function ProcessItem(bagId, slotId, button)
        local bag = bagId

        if slotId then
            local slot = slotId
     
            local itemId = GetContainerItemID(bagId, slotId)
            if itemId then
                local options = {
                    showMogIcon=true,
                    showBindStatus=true,
                    showSellables=true
                }

                CaerdonWardrobe:UpdateButton(itemId, bag, slot, button, options)
            else
                CaerdonWardrobe:UpdateButton(nil, bag, slot, button, nil)
            end 
        end
    end

    local function ItemSlotUpdated(self, bagSet, containerId, subContainerId, slotId, button)
        if not IsAddOnLoaded("CaerdonWardrobe") then
            return
        end

        ProcessItem(subContainerId, slotId, button)
    end

    local function OnEvent(self, event, ...)
        local handler = self[event]
        if(handler) then
            handler(self, ...)
        end
    end

    local CaerdonWardrobeBaudBagFrame = CreateFrame("FRAME")
    CaerdonWardrobeBaudBagFrame:RegisterEvent "ADDON_LOADED"
    CaerdonWardrobeBaudBagFrame:SetScript("OnEvent", OnEvent)

    hooksecurefunc(BaudBag, "ItemSlot_Updated", ItemSlotUpdated)


    local function RefreshItems()
        -- Something changed in the transmog collection.  Time to refresh.
        -- Note: This is primarily necessary to support proper event handling
        -- with multiple accounts logged in at the same time (i.e. learning an
        -- appearance on the other account).
        BaudUpdateJoinedBags()
    end

    function CaerdonWardrobeBaudBagFrame:ADDON_LOADED(name)
        if IsLoggedIn() then
            OnEvent(CaerdonWardrobeBaudBagFrame, "PLAYER_LOGIN")
        else
            CaerdonWardrobeBaudBagFrame:RegisterEvent "PLAYER_LOGIN"
        end
    end

    function CaerdonWardrobeBaudBagFrame:PLAYER_LOGIN(...)
        CaerdonWardrobeBaudBagFrame:RegisterEvent "TRANSMOG_COLLECTION_UPDATED"
        CaerdonWardrobeBaudBagFrame:RegisterEvent "TRANSMOG_COLLECTION_SOURCE_ADDED"
        CaerdonWardrobeBaudBagFrame:RegisterEvent "TRANSMOG_COLLECTION_SOURCE_REMOVED"
    end

    function CaerdonWardrobeBaudBagFrame:TRANSMOG_COLLECTION_UPDATED()
        RefreshItems()
    end

    function CaerdonWardrobeBaudBagFrame:TRANSMOG_COLLECTION_SOURCE_ADDED()
        RefreshItems()
    end

    function CaerdonWardrobeBaudBagFrame:TRANSMOG_COLLECTION_SOURCE_REMOVED()
        RefreshItems()
    end
end