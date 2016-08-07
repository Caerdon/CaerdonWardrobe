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
	components.title = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	components.title:SetText("Caerdon Wardrobe")
	components.title:SetPoint("TOPLEFT", 16, -16)

	components.titleSeparator = self:CreateTexture(nil, "ARTWORK")
	components.titleSeparator:SetColorTexture(0.25, 0.25, 0.25)
	components.titleSeparator:SetSize(600, 1)
	components.titleSeparator:SetPoint("LEFT", self, "TOPLEFT", 10, -40)

	components.bindingTextLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	components.bindingTextLabel:SetText(L["Binding Text"])
	components.bindingTextLabel:SetPoint("TOPLEFT", components.titleSeparator, "BOTTOMLEFT", 0, -10)

	components.bindingTextPositionLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	components.bindingTextPositionLabel:SetText(L["Text Position:"])
	components.bindingTextPositionLabel:SetPoint("TOPLEFT", components.bindingTextLabel, "BOTTOMLEFT", 15, -15)
	components.bindingTextPosition = CreateFrame("Button", "CaerdonWardrobeConfig_BindingTextPosition", self, "UIDropDownMenuTemplate")
	components.bindingTextPosition:SetPoint("TOPLEFT", components.bindingTextPositionLabel, "TOPRIGHT", -9, 9)

	components.showStatusLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	components.showStatusLabel:SetText(L["Show Status On:"])
	components.showStatusLabel:SetPoint("TOPLEFT", components.bindingTextPositionLabel, "BOTTOMLEFT", 0, -15)

	components.showBindingOnBags = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showBindingOnBags", self, "InterfaceOptionsCheckButtonTemplate")
	components.showBindingOnBags:SetPoint("TOPLEFT", components.showStatusLabel, "BOTTOMLEFT", 15, -5)
	components.showBindingOnBagsLabel = _G[components.showBindingOnBags:GetName() .. "Text"]
	components.showBindingOnBagsLabel:SetWidth(80)
	components.showBindingOnBagsLabel:SetText(L["Bank & Bags"])

	components.showBindingOnGuildBank = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showBindingOnGuildBank", self, "InterfaceOptionsCheckButtonTemplate")
	components.showBindingOnGuildBank:SetPoint("LEFT", components.showBindingOnBagsLabel, "RIGHT", 20, 0)
	components.showBindingOnGuildBank:SetPoint("TOP", components.showBindingOnBags, "TOP", 0, 0)
	components.showBindingOnGuildBankLabel = _G[components.showBindingOnGuildBank:GetName() .. "Text"]
	components.showBindingOnGuildBankLabel:SetWidth(80)
	components.showBindingOnGuildBankLabel:SetText(L["Guild Bank"])

	components.showBindingOnMerchant = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showBindingOnMerchant", self, "InterfaceOptionsCheckButtonTemplate")
	components.showBindingOnMerchant:SetPoint("LEFT", components.showBindingOnGuildBankLabel, "RIGHT", 20, 0)
	components.showBindingOnMerchant:SetPoint("TOP", components.showBindingOnGuildBank, "TOP", 0, 0)
	components.showBindingOnMerchantLabel = _G[components.showBindingOnMerchant:GetName() .. "Text"]
	components.showBindingOnMerchantLabel:SetWidth(80)
	components.showBindingOnMerchantLabel:SetText(L["Merchant"])

	components.showGearSets = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showGearSets", self, "InterfaceOptionsCheckButtonTemplate")
	components.showGearSets:SetPoint("TOPLEFT", components.showBindingOnBags, "BOTTOMLEFT", -20, -10)
	components.showGearSetsLabel = _G[components.showGearSets:GetName() .. "Text"]
	components.showGearSetsLabel:SetText(L["Show Gear Sets"])

	components.showBoA = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showBoA", self, "InterfaceOptionsCheckButtonTemplate")
	components.showBoA:SetPoint("LEFT", components.showGearSetsLabel, "RIGHT", 20, 0)
	components.showBoA:SetPoint("TOP", components.showGearSets, "TOP", 0, 0)
	components.showBoALabel = _G[components.showBoA:GetName() .. "Text"]
	components.showBoALabel:SetWidth(140)
	components.showBoALabel:SetText(L["Show Bind on Account"])

	components.showBoE = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showBoE", self, "InterfaceOptionsCheckButtonTemplate")
	components.showBoE:SetPoint("LEFT", components.showBoALabel, "RIGHT", 20, 0)
	components.showBoE:SetPoint("TOP", components.showBoA, "TOP", 0, 0)
	components.showBoELabel = _G[components.showBoE:GetName() .. "Text"]
	components.showBoELabel:SetWidth(140)
	components.showBoELabel:SetText(L["Show Bind on Equip"])

	components.mogIconLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	components.mogIconLabel:SetText(L["Transmog Icon"])
	components.mogIconLabel:SetPoint("TOPLEFT", components.showGearSets, "BOTTOMLEFT", -10, -20)

	components.mogIconPositionLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	components.mogIconPositionLabel:SetText(L["Icon Position:"])
	components.mogIconPositionLabel:SetPoint("TOPLEFT", components.mogIconLabel, "BOTTOMLEFT", 15, -15)
	components.mogIconPosition = CreateFrame("Button", "CaerdonWardrobeConfig_MogIconPosition", self, "UIDropDownMenuTemplate")
	components.mogIconPosition:SetPoint("TOPLEFT", components.mogIconPositionLabel, "TOPRIGHT", -9, 9)


	components.showLearnableLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	components.showLearnableLabel:SetText(L["Show Learnable On:"])
	components.showLearnableLabel:SetPoint("TOPLEFT", components.mogIconPositionLabel, "BOTTOMLEFT", 0, -20)

	components.showLearnableOnBags = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showLearnableOnBags", self, "InterfaceOptionsCheckButtonTemplate")
	components.showLearnableOnBags:SetPoint("TOPLEFT", components.showLearnableLabel, "BOTTOMLEFT", 15, -5)
	components.showLearnableOnBagsLabel = _G[components.showLearnableOnBags:GetName() .. "Text"]
	components.showLearnableOnBagsLabel:SetWidth(80)
	components.showLearnableOnBagsLabel:SetText(L["Bank & Bags"])

	components.showLearnableOnGuildBank = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showLearnableOnGuildBank", self, "InterfaceOptionsCheckButtonTemplate")
	components.showLearnableOnGuildBank:SetPoint("LEFT", components.showLearnableOnBagsLabel, "RIGHT", 20, 0)
	components.showLearnableOnGuildBank:SetPoint("TOP", components.showLearnableOnBags, "TOP", 0, 0)
	components.showLearnableOnGuildBankLabel = _G[components.showLearnableOnGuildBank:GetName() .. "Text"]
	components.showLearnableOnGuildBankLabel:SetWidth(80)
	components.showLearnableOnGuildBankLabel:SetText(L["Guild Bank"])

	components.showLearnableOnMerchant = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showLearnableOnMerchant", self, "InterfaceOptionsCheckButtonTemplate")
	components.showLearnableOnMerchant:SetPoint("LEFT", components.showLearnableOnGuildBankLabel, "RIGHT", 20, 0)
	components.showLearnableOnMerchant:SetPoint("TOP", components.showLearnableOnGuildBank, "TOP", 0, 0)
	components.showLearnableOnMerchantLabel = _G[components.showLearnableOnMerchant:GetName() .. "Text"]
	components.showLearnableOnMerchantLabel:SetWidth(80)
	components.showLearnableOnMerchantLabel:SetText(L["Merchant"])

	components.showLearnableOnAuction = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showLearnableOnAuction", self, "InterfaceOptionsCheckButtonTemplate")
	components.showLearnableOnAuction:SetPoint("LEFT", components.showLearnableOnMerchantLabel, "RIGHT", 20, 0)
	components.showLearnableOnAuction:SetPoint("TOP", components.showLearnableOnMerchant, "TOP", 0, 0)
	components.showLearnableOnAuctionLabel = _G[components.showLearnableOnAuction:GetName() .. "Text"]
	components.showLearnableOnAuctionLabel:SetWidth(100)
	components.showLearnableOnAuctionLabel:SetText(L["Auction House"])


	components.showLearnableOtherLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	components.showLearnableOtherLabel:SetText(L["Show Learnable By Another Toon On:"])
	components.showLearnableOtherLabel:SetPoint("TOPLEFT", components.showLearnableOnBags, "BOTTOMLEFT", -15, -15)

	components.showLearnableOtherOnBags = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showLearnableOtherOnBags", self, "InterfaceOptionsCheckButtonTemplate")
	components.showLearnableOtherOnBags:SetPoint("TOPLEFT", components.showLearnableOtherLabel, "BOTTOMLEFT", 15, -5)
	components.showLearnableOtherOnBagsLabel = _G[components.showLearnableOtherOnBags:GetName() .. "Text"]
	components.showLearnableOtherOnBagsLabel:SetWidth(80)
	components.showLearnableOtherOnBagsLabel:SetText(L["Bank & Bags"])

	components.showLearnableOtherOnGuildBank = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showLearnableOtherOnGuildBank", self, "InterfaceOptionsCheckButtonTemplate")
	components.showLearnableOtherOnGuildBank:SetPoint("LEFT", components.showLearnableOtherOnBagsLabel, "RIGHT", 20, 0)
	components.showLearnableOtherOnGuildBank:SetPoint("TOP", components.showLearnableOtherOnBags, "TOP", 0, 0)
	components.showLearnableOtherOnGuildBankLabel = _G[components.showLearnableOtherOnGuildBank:GetName() .. "Text"]
	components.showLearnableOtherOnGuildBankLabel:SetWidth(80)
	components.showLearnableOtherOnGuildBankLabel:SetText(L["Guild Bank"])

	components.showLearnableOtherOnMerchant = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showLearnableOtherOnMerchant", self, "InterfaceOptionsCheckButtonTemplate")
	components.showLearnableOtherOnMerchant:SetPoint("LEFT", components.showLearnableOtherOnGuildBankLabel, "RIGHT", 20, 0)
	components.showLearnableOtherOnMerchant:SetPoint("TOP", components.showLearnableOtherOnGuildBank, "TOP", 0, 0)
	components.showLearnableOtherOnMerchantLabel = _G[components.showLearnableOtherOnMerchant:GetName() .. "Text"]
	components.showLearnableOtherOnMerchantLabel:SetWidth(80)
	components.showLearnableOtherOnMerchantLabel:SetText(L["Merchant"])

	components.showLearnableOtherOnAuction = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showLearnableOtherOnAuction", self, "InterfaceOptionsCheckButtonTemplate")
	components.showLearnableOtherOnAuction:SetPoint("LEFT", components.showLearnableOtherOnMerchantLabel, "RIGHT", 20, 0)
	components.showLearnableOtherOnAuction:SetPoint("TOP", components.showLearnableOtherOnMerchant, "TOP", 0, 0)
	components.showLearnableOtherOnAuctionLabel = _G[components.showLearnableOtherOnAuction:GetName() .. "Text"]
	components.showLearnableOtherOnAuctionLabel:SetWidth(100)
	components.showLearnableOtherOnAuctionLabel:SetText(L["Auction House"])



	components.showSellableLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	components.showSellableLabel:SetText(L["Show Sellable On:"])
	components.showSellableLabel:SetPoint("TOPLEFT", components.showLearnableOtherOnBags, "BOTTOMLEFT", -15, -15)

	components.showSellableOnBags = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showSellableOnBags", self, "InterfaceOptionsCheckButtonTemplate")
	components.showSellableOnBags:SetPoint("TOPLEFT", components.showSellableLabel, "BOTTOMLEFT", 15, -5)
	components.showSellableOnBagsLabel = _G[components.showSellableOnBags:GetName() .. "Text"]
	components.showSellableOnBagsLabel:SetWidth(80)
	components.showSellableOnBagsLabel:SetText(L["Bank & Bags"])

	components.showSellableOnGuildBank = CreateFrame("CheckButton", "CaerdonWardrobeConfig_showSellableOnGuildBank", self, "InterfaceOptionsCheckButtonTemplate")
	components.showSellableOnGuildBank:SetPoint("LEFT", components.showSellableOnBagsLabel, "RIGHT", 20, 0)
	components.showSellableOnGuildBank:SetPoint("TOP", components.showSellableOnBags, "TOP", 0, 0)
	components.showSellableOnGuildBankLabel = _G[components.showSellableOnGuildBank:GetName() .. "Text"]
	components.showSellableOnGuildBankLabel:SetWidth(80)
	components.showSellableOnGuildBankLabel:SetText(L["Guild Bank"])








	components.mogIconShowAnimation = CreateFrame("CheckButton", "CaerdonWardrobeConfig_MogIconShowAnimation", self, "InterfaceOptionsCheckButtonTemplate")
	components.mogIconShowAnimation:SetPoint("TOPLEFT", components.showSellableOnBags, "BOTTOMLEFT", -20, -15)
	components.mogIconShowAnimationLabel = _G[components.mogIconShowAnimation:GetName() .. "Text"]
	components.mogIconShowAnimationLabel:SetText(L["Show Icon Animation"])

	components.mogIconShowSameLookDifferentItem = CreateFrame("CheckButton", "CaerdonWardrobeConfig_mogIconShowSameLookDifferentItem", self, "InterfaceOptionsCheckButtonTemplate")
	components.mogIconShowSameLookDifferentItem:SetPoint("TOPLEFT", components.mogIconShowAnimation, "BOTTOMLEFT", 0, -10)
	components.mogIconShowSameLookDifferentItemLabel = _G[components.mogIconShowSameLookDifferentItem:GetName() .. "Text"]
	components.mogIconShowSameLookDifferentItemLabel:SetText(L["Include different items / same look (you completionist, you)"])


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
	components.showBindingOnBags:SetChecked(config.Binding.ShowStatus.BankAndBags)
	components.showBindingOnGuildBank:SetChecked(config.Binding.ShowStatus.GuildBank)
	components.showBindingOnMerchant:SetChecked(config.Binding.ShowStatus.Merchant)
	components.showGearSets:SetChecked(config.Binding.ShowGearSets)
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

	components.mogIconShowAnimation:SetChecked(config.Icon.EnableAnimation)
	components.mogIconShowSameLookDifferentItem:SetChecked(config.Icon.ShowLearnable.SameLookDifferentItem)
end

function configFrame:UpdatePendingValues()
	local config = pendingConfig

	config.Binding.Position = UIDropDownMenu_GetSelectedValue(components.bindingTextPosition)
	config.Binding.ShowStatus.BankAndBags = components.showBindingOnBags:GetChecked()
	config.Binding.ShowStatus.GuildBank = components.showBindingOnGuildBank:GetChecked()
	config.Binding.ShowStatus.Merchant = components.showBindingOnMerchant:GetChecked()
	config.Binding.ShowGearSets = components.showGearSets:GetChecked()
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

	config.Icon.EnableAnimation = components.mogIconShowAnimation:GetChecked()
	config.Icon.ShowLearnable.SameLookDifferentItem = components.mogIconShowSameLookDifferentItem:GetChecked()
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
