local MerchantMixin = {}
local isDragonflight = select(4, GetBuildInfo()) > 100000

function MerchantMixin:GetName()
    return "Merchant"
end

function MerchantMixin:Init()
    hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function(...) self:OnMerchantUpdate(...) end)
    hooksecurefunc("MerchantFrame_UpdateBuybackInfo", function(...) self:OnBuybackUpdate(...) end)

    if isDragonflight then
        return { "MERCHANT_UPDATE", "TOOLTIP_DATA_UPDATE" }
    else
        return { "MERCHANT_UPDATE" }
    end
end

function MerchantMixin:MERCHANT_UPDATE()
	self:Refresh()
end

function MerchantMixin:TOOLTIP_DATA_UPDATE()
	if self.refreshTimer then
		self.refreshTimer:Cancel()
	end

	self.refreshTimer = C_Timer.NewTimer(0.1, function ()
		self:Refresh()
	end, 1)
end

function MerchantMixin:GetTooltipData(item, locationInfo)
    if MerchantFrame.selectedTab == 1 then
        if locationInfo.slot == "buybackbutton" then
            return C_TooltipInfo.GetBuybackItem(GetNumBuybackItems())
        else
            return C_TooltipInfo.GetMerchantItem(locationInfo.slot)
        end
    else
        return C_TooltipInfo.GetBuybackItem(locationInfo.slot)
    end
end

function MerchantMixin:SetTooltipItem(tooltip, item, locationInfo)
    if MerchantFrame.selectedTab == 1 then
        if locationInfo.slot == "buybackbutton" then
            tooltip:SetBuybackItem(GetNumBuybackItems())
        else
            tooltip:SetMerchantItem(locationInfo.slot)
        end
    else
        tooltip:SetBuybackItem(locationInfo.slot)
    end
end

function MerchantMixin:Refresh()
    if MerchantFrame:IsShown() then 
        if MerchantFrame.selectedTab == 1 then
            self:OnMerchantUpdate()
        else
            self:OnBuybackUpdate()
        end
    end
end

function MerchantMixin:GetDisplayInfo()
	return {
		bindingStatus = {
			shouldShow = CaerdonWardrobeConfig.Binding.ShowStatus.Merchant
        },
        ownIcon = {
            shouldShow = CaerdonWardrobeConfig.Icon.ShowLearnable.Merchant
        },
        otherIcon = {
            shouldShow = CaerdonWardrobeConfig.Icon.ShowLearnableByOther.Merchant
        },
        oldExpansionIcon = {
            shouldShow = false
        },
        sellableIcon = {
            shouldShow = false
        }
	}
end

function MerchantMixin:OnMerchantUpdate()
    local options = { 
    }

	for i=1, MERCHANT_ITEMS_PER_PAGE, 1 do
		local index = (((MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE) + i)

		local button = _G["MerchantItem"..i.."ItemButton"];

		local slot = index

        local itemLink = GetMerchantItemLink(index)
        if itemLink then
            local item = CaerdonItem:CreateFromItemLink(itemLink)
            CaerdonWardrobe:UpdateButton(button, item, self, { 
                locationKey = format("merchantitem-%d", slot),
                slot = slot
            }, options)
        else
            CaerdonWardrobe:ClearButton(button)
        end
    end
    
    local numBuybackItems = GetNumBuybackItems()
    local buybackName, buybackTexture, buybackPrice, buybackQuantity, buybackNumAvailable, buybackIsUsable = GetBuybackItemInfo(numBuybackItems)
    if buybackName then
        local itemLink = GetBuybackItemLink(numBuybackItems)
        local slot = "buybackbutton"
        if itemLink then
    		local item = CaerdonItem:CreateFromItemLink(itemLink)
            CaerdonWardrobe:UpdateButton(MerchantBuyBackItemItemButton, item, self, {
                locationKey = format("buybackbutton"),
                slot = slot
            }, options)
        else
            CaerdonWardrobe:ClearButton(MerchantBuyBackItemItemButton)
        end
    else
        CaerdonWardrobe:ClearButton(MerchantBuyBackItemItemButton)
    end
end

function MerchantMixin:OnBuybackUpdate()
	local numBuybackItems = GetNumBuybackItems();

	for index=1, BUYBACK_ITEMS_PER_PAGE, 1 do -- Only 1 actual page for buyback right now
		if index <= numBuybackItems then
			local button = _G["MerchantItem"..index.."ItemButton"];

			local slot = index

            local itemLink = GetBuybackItemLink(index)
            if itemLink then
                local item = CaerdonItem:CreateFromItemLink(itemLink)
                CaerdonWardrobe:UpdateButton(button, item, self, {
                    locationKey = format("buybackitem-%d", slot),
                    slot = slot
                }, { })
            else
                CaerdonWardrobe:ClearButton(button)
            end
		end
	end
end

CaerdonWardrobe:RegisterFeature(MerchantMixin)
