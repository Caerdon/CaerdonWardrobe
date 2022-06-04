local ADDON_NAME, NS = ...
local L = NS.L
local components, pendingConfig

local configFrame = CreateFrame("Frame", nil, InterfaceOptionsFramePanelContainer)

local function PropagateErrors(func)
	-- Make sure that errors aren't swallowed for InterfaceOption callbacks
	return function() xpcall(function () func(configFrame) end, geterrorhandler()) end
end

function configFrame:InitializeConfig()
	self:Hide()
	self:CreateComponents()
	NS:RegisterConfigFrame(self)
end

function configFrame:CreateComponents()
	components = {}
	-- components.title = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	-- components.title:SetText("Caerdon Wardrobe")
	-- components.title:SetPoint("TOPLEFT", 16, -16)

	-- components.titleSeparator = self:CreateTexture(nil, "ARTWORK")
	-- components.titleSeparator:SetColorTexture(0.25, 0.25, 0.25)
	-- components.titleSeparator:SetSize(600, 1)
	-- components.titleSeparator:SetPoint("LEFT", self, "TOPLEFT", 10, -40)

	components.bindingTextLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	components.bindingTextLabel:SetText(L["Binding Text"])
	components.bindingTextLabel:SetPoint("TOPLEFT", 16, -16)

	components.enableDebug = CreateFrame("CheckButton", "CaerdonWardrobeConfig_enableDebug", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.enableDebug.SetValue = function(_, value) end
	components.enableDebugLabel = _G[components.enableDebug:GetName() .. "Text"]
	components.enableDebugLabel:SetText(L["Enable Debug"])
	components.enableDebug:SetPoint("TOPRIGHT", -16 - (components.enableDebugLabel:GetWidth()), -16)

	-- components.bindingTextLabel:SetPoint("TOPLEFT", components.titleSeparator, "BOTTOMLEFT", 0, -10)

	components.bindingTextPositionLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	components.bindingTextPositionLabel:SetText(L["Text Position:"])
	components.bindingTextPositionLabel:SetPoint("TOPLEFT", components.bindingTextLabel, "BOTTOMLEFT", 15, -15)
	components.bindingTextPosition = CreateFrame("Button", "CaerdonWardrobeConfig_BindingTextPosition", self, "UIDropDownMenuTemplate")
	components.bindingTextPosition:SetPoint("TOPLEFT", components.bindingTextPositionLabel, "TOPRIGHT", -9, 9)

	components.showStatusLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	components.showStatusLabel:SetText(L["Show Status On:"])
	components.showStatusLabel:SetPoint("TOPLEFT", components.bindingTextPositionLabel, "BOTTOMLEFT", 0, -15)

	components.showBindingOnBags = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showBindingOnBags", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showBindingOnBags:SetPoint("TOPLEFT", components.showStatusLabel, "BOTTOMLEFT", 15, -5)
	components.showBindingOnBags.SetValue = function(_, value) end
	components.showBindingOnBagsLabel = _G[components.showBindingOnBags:GetName() .. "Text"]
	components.showBindingOnBagsLabel:SetWidth(80)
	components.showBindingOnBagsLabel:SetText(L["Bank & Bags"])

	components.showBindingOnGuildBank = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showBindingOnGuildBank", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showBindingOnGuildBank:SetPoint("LEFT", components.showBindingOnBagsLabel, "RIGHT", 20, 0)
	components.showBindingOnGuildBank:SetPoint("TOP", components.showBindingOnBags, "TOP", 0, 0)
	components.showBindingOnGuildBank.SetValue = function(_, value) end
	components.showBindingOnGuildBankLabel = _G[components.showBindingOnGuildBank:GetName() .. "Text"]
	components.showBindingOnGuildBankLabel:SetWidth(80)
	components.showBindingOnGuildBankLabel:SetText(L["Guild Bank"])

	components.showBindingOnMerchant = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showBindingOnMerchant", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showBindingOnMerchant:SetPoint("LEFT", components.showBindingOnGuildBankLabel, "RIGHT", 20, 0)
	components.showBindingOnMerchant:SetPoint("TOP", components.showBindingOnGuildBank, "TOP", 0, 0)
	components.showBindingOnMerchant.SetValue = function(_, value) end
	components.showBindingOnMerchantLabel = _G[components.showBindingOnMerchant:GetName() .. "Text"]
	components.showBindingOnMerchantLabel:SetWidth(80)
	components.showBindingOnMerchantLabel:SetText(L["Merchant"])

	components.showGearSets = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showGearSets", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showGearSets:SetPoint("TOPLEFT", components.showBindingOnBags, "BOTTOMLEFT", -20, -10)
	components.showGearSets.SetValue = function(_, value) end
	components.showGearSetsLabel = _G[components.showGearSets:GetName() .. "Text"]
	components.showGearSetsLabel:SetText(L["Show Gear Sets"])

	components.showGearSetsAsIcon = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showGearSetsAsIcon", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showGearSetsAsIcon:SetPoint("TOPLEFT", components.showGearSets, "BOTTOMLEFT", 22, 8)
	components.showGearSetsAsIcon.SetValue = function(_, value) end
	components.showGearSetsAsIconLabel = _G[components.showGearSetsAsIcon:GetName() .. "Text"]
	components.showGearSetsAsIconLabel:SetText(L["As Icons"])

	components.showBoA = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showBoA", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showBoA:SetPoint("LEFT", components.showGearSetsLabel, "RIGHT", 20, 0)
	components.showBoA:SetPoint("TOP", components.showGearSets, "TOP", 0, 0)
	components.showBoA.SetValue = function(_, value) end
	components.showBoALabel = _G[components.showBoA:GetName() .. "Text"]
	components.showBoALabel:SetWidth(140)
	components.showBoALabel:SetText(L["Show Bind on Account"])

	components.showBoE = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showBoE", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showBoE:SetPoint("LEFT", components.showBoALabel, "RIGHT", 20, 0)
	components.showBoE:SetPoint("TOP", components.showBoA, "TOP", 0, 0)
	components.showBoE.SetValue = function(_, value) end
	components.showBoELabel = _G[components.showBoE:GetName() .. "Text"]
	components.showBoELabel:SetWidth(140)
	components.showBoELabel:SetText(L["Show Bind on Equip"])

	components.mogIconLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	components.mogIconLabel:SetText(L["Transmog Icon"])
	components.mogIconLabel:SetPoint("TOPLEFT", components.showGearSetsAsIcon, "BOTTOMLEFT", -10, -20)

	components.mogIconPositionLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	components.mogIconPositionLabel:SetText(L["Icon Position:"])
	components.mogIconPositionLabel:SetPoint("TOPLEFT", components.mogIconLabel, "BOTTOMLEFT", 15, -15)
	components.mogIconPosition = CreateFrame("Button", "CaerdonWardrobeConfig_MogIconPosition", self, "UIDropDownMenuTemplate")
	components.mogIconPosition:SetPoint("TOPLEFT", components.mogIconPositionLabel, "TOPRIGHT", -9, 9)


	components.showLearnableLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	components.showLearnableLabel:SetText(L["Show Learnable On:"])
	components.showLearnableLabel:SetPoint("TOPLEFT", components.mogIconPositionLabel, "BOTTOMLEFT", 0, -20)

	components.showLearnableOnBags = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showLearnableOnBags", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showLearnableOnBags:SetPoint("TOPLEFT", components.showLearnableLabel, "BOTTOMLEFT", 15, -5)
	components.showLearnableOnBags.SetValue = function(_, value) end
	components.showLearnableOnBagsLabel = _G[components.showLearnableOnBags:GetName() .. "Text"]
	components.showLearnableOnBagsLabel:SetWidth(80)
	components.showLearnableOnBagsLabel:SetText(L["Bank & Bags"])

	components.showLearnableOnGuildBank = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showLearnableOnGuildBank", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showLearnableOnGuildBank:SetPoint("LEFT", components.showLearnableOnBagsLabel, "RIGHT", 20, 0)
	components.showLearnableOnGuildBank:SetPoint("TOP", components.showLearnableOnBags, "TOP", 0, 0)
	components.showLearnableOnGuildBank.SetValue = function(_, value) end
	components.showLearnableOnGuildBankLabel = _G[components.showLearnableOnGuildBank:GetName() .. "Text"]
	components.showLearnableOnGuildBankLabel:SetWidth(80)
	components.showLearnableOnGuildBankLabel:SetText(L["Guild Bank"])

	components.showLearnableOnMerchant = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showLearnableOnMerchant", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showLearnableOnMerchant:SetPoint("LEFT", components.showLearnableOnGuildBankLabel, "RIGHT", 20, 0)
	components.showLearnableOnMerchant:SetPoint("TOP", components.showLearnableOnGuildBank, "TOP", 0, 0)
	components.showLearnableOnMerchant.SetValue = function(_, value) end
	components.showLearnableOnMerchantLabel = _G[components.showLearnableOnMerchant:GetName() .. "Text"]
	components.showLearnableOnMerchantLabel:SetWidth(80)
	components.showLearnableOnMerchantLabel:SetText(L["Merchant"])

	components.showLearnableOnAuction = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showLearnableOnAuction", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showLearnableOnAuction:SetPoint("LEFT", components.showLearnableOnMerchantLabel, "RIGHT", 20, 0)
	components.showLearnableOnAuction:SetPoint("TOP", components.showLearnableOnMerchant, "TOP", 0, 0)
	components.showLearnableOnAuction.SetValue = function(_, value) end
	components.showLearnableOnAuctionLabel = _G[components.showLearnableOnAuction:GetName() .. "Text"]
	components.showLearnableOnAuctionLabel:SetWidth(100)
	components.showLearnableOnAuctionLabel:SetText(L["Auction House"])


	components.showLearnableOtherLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	components.showLearnableOtherLabel:SetText(L["Show Learnable By Another Toon On:"])
	components.showLearnableOtherLabel:SetPoint("TOPLEFT", components.showLearnableOnBags, "BOTTOMLEFT", -15, -15)

	components.showLearnableOtherOnBags = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showLearnableOtherOnBags", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showLearnableOtherOnBags:SetPoint("TOPLEFT", components.showLearnableOtherLabel, "BOTTOMLEFT", 15, -5)
	components.showLearnableOtherOnBags.SetValue = function(_, value) end
	components.showLearnableOtherOnBagsLabel = _G[components.showLearnableOtherOnBags:GetName() .. "Text"]
	components.showLearnableOtherOnBagsLabel:SetWidth(80)
	components.showLearnableOtherOnBagsLabel:SetText(L["Bank & Bags"])

	components.showLearnableOtherOnGuildBank = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showLearnableOtherOnGuildBank", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showLearnableOtherOnGuildBank:SetPoint("LEFT", components.showLearnableOtherOnBagsLabel, "RIGHT", 20, 0)
	components.showLearnableOtherOnGuildBank:SetPoint("TOP", components.showLearnableOtherOnBags, "TOP", 0, 0)
	components.showLearnableOtherOnGuildBank.SetValue = function(_, value) end
	components.showLearnableOtherOnGuildBankLabel = _G[components.showLearnableOtherOnGuildBank:GetName() .. "Text"]
	components.showLearnableOtherOnGuildBankLabel:SetWidth(80)
	components.showLearnableOtherOnGuildBankLabel:SetText(L["Guild Bank"])

	components.showLearnableOtherOnMerchant = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showLearnableOtherOnMerchant", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showLearnableOtherOnMerchant:SetPoint("LEFT", components.showLearnableOtherOnGuildBankLabel, "RIGHT", 20, 0)
	components.showLearnableOtherOnMerchant:SetPoint("TOP", components.showLearnableOtherOnGuildBank, "TOP", 0, 0)
	components.showLearnableOtherOnMerchant.SetValue = function(_, value) end
	components.showLearnableOtherOnMerchantLabel = _G[components.showLearnableOtherOnMerchant:GetName() .. "Text"]
	components.showLearnableOtherOnMerchantLabel:SetWidth(80)
	components.showLearnableOtherOnMerchantLabel:SetText(L["Merchant"])

	components.showLearnableOtherOnAuction = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showLearnableOtherOnAuction", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showLearnableOtherOnAuction:SetPoint("LEFT", components.showLearnableOtherOnMerchantLabel, "RIGHT", 20, 0)
	components.showLearnableOtherOnAuction:SetPoint("TOP", components.showLearnableOtherOnMerchant, "TOP", 0, 0)
	components.showLearnableOtherOnAuction.SetValue = function(_, value) end
	components.showLearnableOtherOnAuctionLabel = _G[components.showLearnableOtherOnAuction:GetName() .. "Text"]
	components.showLearnableOtherOnAuctionLabel:SetWidth(100)
	components.showLearnableOtherOnAuctionLabel:SetText(L["Auction House"])



	components.showSellableLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	components.showSellableLabel:SetText(L["Show Sellable On:"])
	components.showSellableLabel:SetPoint("TOPLEFT", components.showLearnableOtherOnBags, "BOTTOMLEFT", -15, -15)

	components.showSellableOnBags = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showSellableOnBags", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showSellableOnBags:SetPoint("TOPLEFT", components.showSellableLabel, "BOTTOMLEFT", 15, -5)
	components.showSellableOnBags.SetValue = function(_, value) end
	components.showSellableOnBagsLabel = _G[components.showSellableOnBags:GetName() .. "Text"]
	components.showSellableOnBagsLabel:SetWidth(80)
	components.showSellableOnBagsLabel:SetText(L["Bank & Bags"])

	components.showSellableOnGuildBank = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showSellableOnGuildBank", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showSellableOnGuildBank:SetPoint("LEFT", components.showSellableOnBagsLabel, "RIGHT", 20, 0)
	components.showSellableOnGuildBank:SetPoint("TOP", components.showSellableOnBags, "TOP", 0, 0)
	components.showSellableOnGuildBank.SetValue = function(_, value) end
	components.showSellableOnGuildBankLabel = _G[components.showSellableOnGuildBank:GetName() .. "Text"]
	components.showSellableOnGuildBankLabel:SetWidth(80)
	components.showSellableOnGuildBankLabel:SetText(L["Guild Bank"])


	components.showOldLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	components.showOldLabel:SetText(L["Show Old Expansion Items:"])
	components.showOldLabel:SetPoint("TOPLEFT", components.showSellableOnBags, "BOTTOMLEFT", -15, -15)

	components.showOldReagents = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showOldReagents", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showOldReagents:SetPoint("TOPLEFT", components.showOldLabel, "BOTTOMLEFT", 15, -5)
	components.showOldReagents.SetValue = function(_, value) end
	components.showOldReagentsLabel = _G[components.showOldReagents:GetName() .. "Text"]
	components.showOldReagentsLabel:SetText(L["Reagents"])

	components.showOldOther = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showOldOther", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showOldOther:SetPoint("LEFT", components.showOldReagentsLabel, "RIGHT", 65, 0)
	components.showOldOther:SetPoint("TOP", components.showOldReagents, "TOP", 0, 0)
	components.showOldOther.SetValue = function(_, value) end
	components.showOldOtherLabel = _G[components.showOldOther:GetName() .. "Text"]
	components.showOldOtherLabel:SetText(L["Other Items"])

	components.showOldUsable = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showOldUsable", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showOldUsable:SetPoint("LEFT", components.showOldOtherLabel, "RIGHT", 65, 0)
	components.showOldUsable:SetPoint("TOP", components.showOldOther, "TOP", 0, 0)
	components.showOldUsable.SetValue = function(_, value) end
	components.showOldUsableLabel = _G[components.showOldUsable:GetName() .. "Text"]
	components.showOldUsableLabel:SetText(L["Include Usable Items"])

	components.showOldUnknown = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showOldUnknown", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showOldUnknown:SetPoint("TOPLEFT", components.showOldReagents, "BOTTOMLEFT", 0, -5)
	components.showOldUnknown.SetValue = function(_, value) end
	components.showOldUnknownLabel = _G[components.showOldUnknown:GetName() .. "Text"]
	components.showOldUnknownLabel:SetText(L["Include Unknown Expansion"])

	components.showOldAuctionHouse = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showOldAuctionHouse", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showOldAuctionHouse:SetPoint("LEFT", components.showOldUnknownLabel, "RIGHT", 30, 0)
	components.showOldAuctionHouse:SetPoint("TOP", components.showOldUnknown, "TOP", 0, 0)
	components.showOldAuctionHouse.SetValue = function(_, value) end
	components.showOldAuctionHouseLabel = _G[components.showOldAuctionHouse:GetName() .. "Text"]
	components.showOldAuctionHouseLabel:SetText(L["Show in Auction House"])







	components.mogIconShowAnimation = CreateFrame("CheckButton", "CaerdonWardrobeConfig_MogIconShowAnimation", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.mogIconShowAnimation:SetPoint("TOPLEFT", components.showOldUnknown, "BOTTOMLEFT", -20, -15)
	components.mogIconShowAnimation.SetValue = function(_, value) end
	components.mogIconShowAnimationLabel = _G[components.mogIconShowAnimation:GetName() .. "Text"]
	components.mogIconShowAnimationLabel:SetText(L["Show Icon Animation"])

	components.showQuestItems = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showQuestItems", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.showQuestItems:SetPoint("LEFT", components.mogIconShowAnimationLabel, "RIGHT", 20, 0)
	components.showQuestItems:SetPoint("TOP", components.mogIconShowAnimation, "TOP", 0, 0)
	components.showQuestItems.SetValue = function(_, value) end
	components.showQuestItemsLabel = _G[components.showQuestItems:GetName() .. "Text"]
	components.showQuestItemsLabel:SetText(L["Show Quest Items"])

	components.mogIconShowSameLookDifferentItem = CreateFrame("CheckButton", "CaerdonWardrobeConfig_mogIconShowSameLookDifferentItem", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.mogIconShowSameLookDifferentItem:SetPoint("TOPLEFT", components.mogIconShowAnimation, "BOTTOMLEFT", 0, -10)
	components.mogIconShowSameLookDifferentItem.SetValue = function(_, value) end
	components.mogIconShowSameLookDifferentItemLabel = _G[components.mogIconShowSameLookDifferentItem:GetName() .. "Text"]
	components.mogIconShowSameLookDifferentItemLabel:SetText(L["Include different items / same look (you completionist, you)"])

	components.mogIconShowSameLookDifferentLevel = CreateFrame("CheckButton", "CaerdonWardrobeConfig_mogIconShowSameLookDifferentLevel", self, "InterfaceOptionsSmallCheckButtonTemplate")
	components.mogIconShowSameLookDifferentLevel:SetPoint("LEFT", components.mogIconShowSameLookDifferentItem, "RIGHT", 350, 0)
	components.mogIconShowSameLookDifferentLevel:SetPoint("TOP", components.mogIconShowSameLookDifferentItem, "TOP", 0, 0)
	components.mogIconShowSameLookDifferentLevel.SetValue = function(_, value) end
	components.mogIconShowSameLookDifferentLevelLabel = _G[components.mogIconShowSameLookDifferentLevel:GetName() .. "Text"]
	components.mogIconShowSameLookDifferentLevelLabel:SetText(L["Include different levels"])

	components.mogIconShowSameLookDifferentItem:HookScript("OnClick", function()
		self:UpdateCheckStatus(components.mogIconShowSameLookDifferentItem, components.mogIconShowSameLookDifferentLevel)
	end)
end

function configFrame:UpdateCheckStatus(parentBox, childBox)
	if parentBox:GetChecked() then
		childBox:Enable()
	else
		childBox:Disable()
	end
end

function configFrame:InitializeMogIconPosition()
	self:AddMogIconPositionDropDownItem("Top Left", "TOPLEFT")
	self:AddMogIconPositionDropDownItem("Top Right", "TOPRIGHT")
	self:AddMogIconPositionDropDownItem("Bottom Left", "BOTTOMLEFT")
	self:AddMogIconPositionDropDownItem("Bottom Right", "BOTTOMRIGHT")

	UIDropDownMenu_SetSelectedValue(components.mogIconPosition, pendingConfig.Icon.Position)
end

function configFrame:InitializeBindingTextPosition()
	self:AddBindingTextPositionDropDownItem("Top", "TOP")
	self:AddBindingTextPositionDropDownItem("Center", "CENTER")
	self:AddBindingTextPositionDropDownItem("Bottom", "BOTTOM")

	UIDropDownMenu_SetSelectedValue(components.bindingTextPosition, pendingConfig.Binding.Position)
end

function configFrame:AddMogIconPositionDropDownItem(name, value)
	local info = UIDropDownMenu_CreateInfo()
	info.text = name
	info.value = value
	info.func = function(self, arg1, arg2, checked)
		UIDropDownMenu_SetSelectedValue(components.mogIconPosition, value)
		pendingConfig.Icon.Position = value
	end

	UIDropDownMenu_AddButton(info)
end

function configFrame:AddBindingTextPositionDropDownItem(name, value)
	local info = UIDropDownMenu_CreateInfo()
	info.text = name
	info.value = value
	info.func = function(self, arg1, arg2, checked)
		UIDropDownMenu_SetSelectedValue(components.bindingTextPosition, value)
		pendingConfig.Binding.Position = value
	end

	UIDropDownMenu_AddButton(info)
end

function configFrame:ApplyConfig(config)
	pendingConfig = CopyTable(config)
end

function configFrame:RefreshComponents()
	local config = pendingConfig

	UIDropDownMenu_Initialize(components.bindingTextPosition, function() self:InitializeBindingTextPosition() end)
	components.enableDebug:SetChecked(config.Debug.Enabled)
	components.showBindingOnBags:SetChecked(config.Binding.ShowStatus.BankAndBags)
	components.showBindingOnGuildBank:SetChecked(config.Binding.ShowStatus.GuildBank)
	components.showBindingOnMerchant:SetChecked(config.Binding.ShowStatus.Merchant)
	components.showGearSets:SetChecked(config.Binding.ShowGearSets)
	components.showGearSetsAsIcon:SetChecked(config.Binding.ShowGearSetsAsIcon)
	components.showBoA:SetChecked(config.Binding.ShowBoA)
	components.showBoE:SetChecked(config.Binding.ShowBoE)

	UIDropDownMenu_Initialize(components.mogIconPosition, function() self:InitializeMogIconPosition() end)

	components.showLearnableOnBags:SetChecked(config.Icon.ShowLearnable.BankAndBags)
	components.showLearnableOnGuildBank:SetChecked(config.Icon.ShowLearnable.GuildBank)
	components.showLearnableOnMerchant:SetChecked(config.Icon.ShowLearnable.Merchant)
	components.showLearnableOnAuction:SetChecked(config.Icon.ShowLearnable.Auction)

	components.showLearnableOtherOnBags:SetChecked(config.Icon.ShowLearnableByOther.BankAndBags)
	components.showLearnableOtherOnGuildBank:SetChecked(config.Icon.ShowLearnableByOther.GuildBank)
	components.showLearnableOtherOnMerchant:SetChecked(config.Icon.ShowLearnableByOther.Merchant)
	components.showLearnableOtherOnAuction:SetChecked(config.Icon.ShowLearnableByOther.Auction)

	components.showSellableOnBags:SetChecked(config.Icon.ShowSellable.BankAndBags)
	components.showSellableOnGuildBank:SetChecked(config.Icon.ShowSellable.GuildBank)

	components.showOldReagents:SetChecked(config.Icon.ShowOldExpansion.Reagents)
	components.showOldOther:SetChecked(config.Icon.ShowOldExpansion.Other)
	components.showOldUnknown:SetChecked(config.Icon.ShowOldExpansion.Unknown)
	components.showOldUsable:SetChecked(config.Icon.ShowOldExpansion.Usable)
	components.showOldAuctionHouse:SetChecked(config.Icon.ShowOldExpansion.Auction)

	components.mogIconShowAnimation:SetChecked(config.Icon.EnableAnimation)

	components.showQuestItems:SetChecked(config.Icon.ShowQuestItems)

	components.mogIconShowSameLookDifferentItem:SetChecked(config.Icon.ShowLearnable.SameLookDifferentItem)
	components.mogIconShowSameLookDifferentLevel:SetChecked(config.Icon.ShowLearnable.SameLookDifferentLevel)

	self:UpdateCheckStatus(components.mogIconShowSameLookDifferentItem, components.mogIconShowSameLookDifferentLevel)
end

function configFrame:UpdatePendingValues()
	local config = pendingConfig

	config.Binding.Position = UIDropDownMenu_GetSelectedValue(components.bindingTextPosition)
	config.Debug.Enabled = components.enableDebug:GetChecked()
	config.Binding.ShowStatus.BankAndBags = components.showBindingOnBags:GetChecked()
	config.Binding.ShowStatus.GuildBank = components.showBindingOnGuildBank:GetChecked()
	config.Binding.ShowStatus.Merchant = components.showBindingOnMerchant:GetChecked()
	config.Binding.ShowGearSets = components.showGearSets:GetChecked()
	config.Binding.ShowGearSetsAsIcon = components.showGearSetsAsIcon:GetChecked()
	config.Binding.ShowBoA = components.showBoA:GetChecked()
	config.Binding.ShowBoE = components.showBoE:GetChecked()
	
	config.Icon.Position = UIDropDownMenu_GetSelectedValue(components.mogIconPosition)

	config.Icon.ShowLearnable.BankAndBags = components.showLearnableOnBags:GetChecked()
	config.Icon.ShowLearnable.GuildBank = components.showLearnableOnGuildBank:GetChecked()
	config.Icon.ShowLearnable.Merchant = components.showLearnableOnMerchant:GetChecked()
	config.Icon.ShowLearnable.Auction = components.showLearnableOnAuction:GetChecked()

	config.Icon.ShowLearnableByOther.BankAndBags = components.showLearnableOtherOnBags:GetChecked()
	config.Icon.ShowLearnableByOther.GuildBank = components.showLearnableOtherOnGuildBank:GetChecked()
	config.Icon.ShowLearnableByOther.Merchant = components.showLearnableOtherOnMerchant:GetChecked()
	config.Icon.ShowLearnableByOther.Auction = components.showLearnableOtherOnAuction:GetChecked()

	config.Icon.ShowSellable.BankAndBags = components.showSellableOnBags:GetChecked()
	config.Icon.ShowSellable.GuildBank = components.showSellableOnGuildBank:GetChecked()

	config.Icon.ShowOldExpansion.Reagents = components.showOldReagents:GetChecked()
	config.Icon.ShowOldExpansion.Other = components.showOldOther:GetChecked()
	config.Icon.ShowOldExpansion.Unknown = components.showOldUnknown:GetChecked()
	config.Icon.ShowOldExpansion.Usable = components.showOldUsable:GetChecked()
	config.Icon.ShowOldExpansion.Auction = components.showOldAuctionHouse:GetChecked()

	config.Icon.EnableAnimation = components.mogIconShowAnimation:GetChecked()
	config.Icon.ShowQuestItems = components.showQuestItems:GetChecked()
	config.Icon.ShowLearnable.SameLookDifferentItem = components.mogIconShowSameLookDifferentItem:GetChecked()
	config.Icon.ShowLearnable.SameLookDifferentLevel = components.mogIconShowSameLookDifferentLevel:GetChecked()
end

function configFrame:OnConfigLoaded()
	self:ApplyConfig(CaerdonWardrobeConfig)

	self.name = "Caerdon Wardrobe"
	self.okay = PropagateErrors(self.OnSave)
	self.cancel = PropagateErrors(self.OnCancel)
	self.default = PropagateErrors(self.OnResetToDefaults)
	self.refresh = PropagateErrors(self.OnRefresh)

	InterfaceOptions_AddCategory(self)
end

function configFrame:OnSave()
	self:UpdatePendingValues()
	CaerdonWardrobeConfig = CopyTable(pendingConfig)
	CaerdonWardrobe:RefreshItems()
end

function configFrame:OnCancel()
	self:ApplyConfig(CaerdonWardrobeConfig)
end

function configFrame:OnResetToDefaults()
	self:ApplyConfig(NS:GetDefaultConfig())
end

function configFrame:OnRefresh()
	self:RefreshComponents()
end

configFrame:InitializeConfig()
