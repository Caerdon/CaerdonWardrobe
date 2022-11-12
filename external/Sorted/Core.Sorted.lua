local ADDON_NAME, namespace = ...
local L = namespace.L

local addonName = "Sorted"
local SortedMixin = {}

function SortedMixin:GetName()
    return addonName
end

local refreshTimer

function SortedMixin:Init()
    local Sorted = LibStub("Sorted.")
    local statusProminentSize

    -- Adds a new column that displays Caerdon Wardrobe's icon
    local CreateElement = function(f)
    end

    local UpdateElement = function(button, data)
		local options = {
            overrideStatusPosition = "CENTER",
            statusOffsetX = -0.60,
            statusOffsetY = -0.60,
            statusProminentSize = statusProminentSize,
            isFiltered = data.filtered,
            filterColor = data.tinted
		}

        if data.caerdonItem then
            if Sorted.IsPlayingCharacterSelected() then
    		    CaerdonWardrobe:UpdateButton(button, data.caerdonItem, self, { bag = data.bag, slot = data.slot }, options)
            else
    		    CaerdonWardrobe:UpdateButton(button, data.caerdonItem, self, { locationKey = format("%s-%d-%d", data.link, data.bag, data.slot) }, options)
            end
        else
            CaerdonWardrobe:ClearButton(button)
        end
    end

    local UpdateIcon = function(frame, iconSize, borderThickness, iconShape)
        local button = frame.caerdonButton
        if not button then return end

        local mogStatus = button.mogStatus
        if not mogStatus then return end

        local mogStatusBackground = mogStatus.mogStatusBackground
        if not mogStatusBackground then return end

        statusProminentSize = iconSize
    end
    
    Sorted:AddItemColumn("CAERDONWARDROBE", "Caerdon Wardrobe", 32, CreateElement, UpdateElement, UpdateIcon)
    
    -- Add sorting
    local Sort = function(asc, data1, data2)
        if data1.caerdonStatus == data2.caerdonStatus or not data1.caerdonStatus then
            return Sorted.DefaultItemSort(data1, data2)
        end

        if asc then
            if data1.caerdonStatus == "" then
                return true
            elseif data2.caerdonStatus == "" then
                return false
            end

            if data1.caerdonStatus == "own" or data1.caerdonStatus == "ownPlus" then
                return false
            elseif data2.caerdonStatus == "own" or data2.caerdonStatus == "ownPlus" then
                return true
            elseif data1.caerdonStatus == "other" or data1.caerdonStatus == "otherPlus" then
                return false
            elseif data2.caerdonStatus == "other" or data2.caerdonStatus == "otherPlus" then
                return true
            else
                return data1.caerdonStatus < data2.caerdonStatus
            end
        else
            if data1.caerdonStatus == "" then
                return false
            elseif data2.caerdonStatus == "" then
                return true
            end

            if data1.caerdonStatus == "own" or data1.caerdonStatus == "ownPlus" then
                return true
            elseif data2.caerdonStatus == "own" or data2.caerdonStatus == "ownPlus" then
                return false
            elseif data1.caerdonStatus == "other" or data1.caerdonStatus == "otherPlus" then
                return true
            elseif data2.caerdonStatus == "other" or data2.caerdonStatus == "otherPlus" then
                return false
            else
                return data1.caerdonStatus > data2.caerdonStatus
            end
        end
    end

    Sorted:AddSortMethod("CAERDONWARDROBE", "|TInterface\\MINIMAP\\TRACKING\\Transmogrifier:18:18:0:0:32:32:0:32:0:32|t", Sort, false)
    -- TODO: Look at adding various sort methods for types?
    -- Sorted:AddSortMethod("CAERDONWARDROBE", "|TInterface\\Store\\category-icon-bag:18:18:0:0:32:32:0:32:0:32|t", Sort, false)
    
    local PreSort = function(itemData)
        if Sorted.IsPlayingCharacterSelected() then
            itemData.caerdonItem = CaerdonItem:CreateFromBagAndSlot(itemData.bag, itemData.slot)
        else
            itemData.caerdonItem = CaerdonItem:CreateFromItemLink(itemData.link)
        end

        if not itemData.caerdonItem:IsItemDataCached() then
            itemData.caerdonItem:ContinueOnItemLoad(function ()
                if refreshTimer then
                    refreshTimer:Cancel()
                end
            
                refreshTimer = C_Timer.NewTimer(0.1, function ()
                    Sorted.TriggerFullUpdate()
                end, 1)
            end)
        else
            local isReady, mogStatus, bindingStatus, bindingResult = itemData.caerdonItem:GetCaerdonStatus(feature, locationInfo)
            itemData.caerdonStatus = mogStatus
        end
    end
    Sorted:AddDataToItem("CAERDONWARDROBE", PreSort)
end

function SortedMixin:GetTooltipData(item, locationInfo)
    local Sorted = LibStub("Sorted.")
    if Sorted.IsPlayingCharacterSelected() then
        if locationInfo.bag == BANK_CONTAINER then
            return C_TooltipInfo.GetInventoryItem("player", BankButtonIDToInvSlotID(locationInfo.slot))
        else
            return C_TooltipInfo.GetBagItem(locationInfo.bag, locationInfo.slot)
        end
    else
        return C_TooltipInfo.GetHyperlink(item:GetItemLink())
    end
end

function SortedMixin:Refresh()
end

function SortedMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	return {
		bindingStatus = {
			shouldShow = false
		},
		ownIcon = {
			shouldShow = true
		},
		otherIcon = {
			shouldShow = true
		},
		questIcon = {
			shouldShow = true
		},
		oldExpansionIcon = {
			shouldShow = true
		},
        sellableIcon = {
            shouldShow = true
        }
	}
end

local Version = nil
local isActive = false

if select(4, GetAddOnInfo(addonName)) then
	if IsAddOnLoaded(addonName) then
		Version = GetAddOnMetadata(addonName, 'Version')
		CaerdonWardrobe:RegisterFeature(SortedMixin)
		isActive = true
	end
end

WagoAnalytics:Switch(addonName, isActive)
