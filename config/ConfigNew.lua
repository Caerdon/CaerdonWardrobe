local CaerdonWardrobeConfigMixin = {}

-- local ADDON_NAME, NS = ...
-- local L = NS.L
-- local components, pendingConfig

-- CAERDON_CONFIG_LABEL = L["Caerdon Wardrobe... and more!"]
-- CAERDON_CONFIG_SUBTEXT = L[ [[
-- This addon started as a simple way for me to track unlearned transmog appearances.  Over the years, it has grown into so much more!

-- Caerdon Wardrobe now provides tracking of unlearned recipes, pets, mounts, toys, and transmog appearances.  It shows locked and openable containers.  It tracks BoE and BoA bindings, equipment sets, and can highlight gear to sell that is not tradeable, not part of a set, and has no other potentially interesting use.

-- New for Shadowlands, it also tracks unlearned conduits, and I've even added an old expansion indicator that can help you clean out your bags for your new journey!

-- Caerdon Wardrobe leverages a set of icons and text where appropriate to call out all of the above items in the following locations: Bank & Bags, Guild Banks, Auction House, Merchants, Dungeon and Raid Journal, Loot Pickup, Group Loot Roll, and the World Map.

-- It also provides integration for your favorite bag add-ons: AdiBags, ArkInventory, Bagnon, Bagnonium, Baud Bag, cargBags_Nivaya, ElvUI, Inventorian, and LiteBag.  Additionally it supports a few other World Quest addons: World Quest Tab and Zygor World Quest Planner.

-- I don't like slow addons and try my best to keep this addon from impacting your fun.  If Caerdon Wardrobe is causing a performance impact on your game, please let me know!
-- ]] ]

function CaerdonWardrobeConfigMixin:OnLoad()
	self:RegisterEvent("FIRST_FRAME_RENDERED");

	self.name = "Caerdon Wardrobe"
	-- self.okay = self.OnSave

	-- hooksecurefunc(SettingsPanel, "Open", function(...) self:OnSettingsPanelOpen(...) end)
end



local MyAddOn_SavedVars = {}

function CaerdonWardrobeConfigMixin:OnSettingsPanelOpen(frame)
	C_Timer.After(0, function ()
		local category = Settings.GetCategory("My AddOn")

	do
		local variable = "toggle"
		local name = "Test Checkbox"
		local tooltip = "This is a tooltip for the checkbox."
		local defaultValue = false

		local setting = Settings.RegisterProxySetting(category, variable, MyAddOn_SavedVars, type(defaultValue), name, defaultValue)
		Settings.CreateCheckBox(category, setting, tooltip)
	end
end)
end

local function Register()
-- function CaerdonWardrobeConfigMixin:Register()
	-- local category = Settings.RegisterVerticalLayoutCategory("My AddOn")
	local category = securecall(Settings.RegisterVerticalLayoutCategory, "My AddOn")

	do
		local variable = "toggle"
		local name = "Test Checkbox"
		local tooltip = "This is a tooltip for the checkbox."
		local defaultValue = false

		local setting = securecall(Settings.RegisterProxySetting, category, variable, MyAddOn_SavedVars, type(defaultValue), name, defaultValue)
		-- local setting = Settings.RegisterProxySetting(category, variable, MyAddOn_SavedVars, type(defaultValue), name, defaultValue)
		-- Settings.CreateCheckBox(category, setting, tooltip)
		securecall(Settings.CreateCheckBox, category, setting, tooltip)
	end

	-- do
	-- 	local variable = "slider"
	-- 	local name = "Test Slider"
	-- 	local tooltip = "This is a tooltip for the slider."
	-- 	local defaultValue = 180
	-- 	local minValue = 90
	-- 	local maxValue = 360
	-- 	local step = 10

	-- 	local setting = Settings.RegisterProxySetting(category, variable, MyAddOn_SavedVars, type(defaultValue), name, defaultValue)
	-- 	local options = Settings.CreateSliderOptions(minValue, maxValue, step)
	-- 	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right);
	-- 	Settings.CreateSlider(category, setting, options, tooltip)
	-- end

	-- do
	-- 	local variable = "selection"
	-- 	local defaultValue = 2  -- Corresponds to "Option 2" below.
	-- 	local name = "Test Dropdown"
	-- 	local tooltip = "This is a tooltip for the dropdown."

	-- 	local function GetOptions()
	-- 		local container = Settings.CreateDropDownTextContainer()
	-- 		container:Add(1, "Option 1")
	-- 		container:Add(2, "Option 2")
	-- 		container:Add(3, "Option 3")
	-- 		return container:GetData()
	-- 	end

	-- 	local setting = Settings.RegisterProxySetting(category, variable, MyAddOn_SavedVars, type(defaultValue), name, defaultValue)
	-- 	Settings.CreateDropDown(category, setting, GetOptions, tooltip)
	-- end

	-- Settings.RegisterAddOnCategory(category)
	securecall(Settings.RegisterAddOnCategory, category)
end

-- function CaerdonWardrobeConfigMixin:Register()
-- CaerdonWardrobeConfig = {}

-- local function Register()
-- 	local category, layout = Settings.RegisterVerticalLayoutCategory("Caerdon Wardrobe");
-- 	-- ... setting initializers assigned to layout.
--     do
--         local variable = "DebugEnabled"
--         -- local name = "Debug"
-- 		local name = "Enable Debug"
--         local tooltip = "Adds additional debugging info to tooltips"
--         local defaultValue = false

--         local setting = Settings.RegisterProxySetting(category, variable, CaerdonWardrobeConfig, type(defaultValue), name, defaultValue)
--         Settings.CreateCheckBox(category, setting, tooltip)
--     end

-- 	Settings.RegisterAddOnCategory(category);
-- end

-- Register()
-- SettingsRegistrar:AddRegistrant(Register)
securecall(SettingsRegistrar.AddRegistrant, SettingsRegistrar, Register)

-- EventUtil.ContinueAfterAllEvents(Register, "SETTINGS_LOADED", "FIRST_FRAME_RENDERED")

-- function CaerdonWardrobeConfigMixin:OnEvent(event, ...)
-- 	if ( event == "SETTINGS_LOADED" ) then
-- 		-- C_Timer.After(0, function ()
-- 		-- 	self:Register()
-- 		-- end)
-- 		-- self.variablesLoaded = true;
-- 		-- self:UnregisterEvent(event);

-- 		-- if not CaerdonWardrobeConfig or CaerdonWardrobeConfig.Version ~= NS:GetDefaultConfig().Version then
-- 		-- 	CaerdonWardrobeConfig = CopyTable(NS:GetDefaultConfig())
-- 		-- end

-- 		-- CaerdonWardrobe:RefreshItems()
-- 	elseif ( event == "FIRST_FRAME_RENDERED" ) then
-- 		C_Timer.After(0, function ()
-- 			self:Register()
-- 		end)
-- 		-- SettingsRegistrar:AddRegistrant(self.Register);
-- 	end
-- end

-- function CaerdonWardrobeConfigMixin:OnSave()
-- 	-- Make sure that errors aren't swallowed for InterfaceOption callbacks
-- 	xpcall(function()
-- 		CaerdonWardrobe:RefreshItems()
-- 	end, geterrorhandler())
-- end

-- function NS:GetDefaultConfig()
-- 	return {
-- 		Version = 21,

-- 		Debug = {
-- 			Enabled = false
-- 		},

-- 		Icon = {
-- 			EnableAnimation = true,
-- 			Position = "TOPLEFT",

-- 			ShowLearnable = {
-- 				BankAndBags = true,
-- 				GuildBank = true,
-- 				Merchant = true,
-- 				Auction = true,
-- 				SameLookDifferentItem = false,
-- 				SameLookDifferentLevel = true
-- 			},

-- 			ShowLearnableByOther = {
-- 				BankAndBags = true,
-- 				GuildBank = true,
-- 				Merchant = true,
-- 				Auction = true,
-- 				EncounterJournal = true
-- 			},

-- 			ShowSellable = {
-- 				BankAndBags = true,
-- 				GuildBank = false
-- 			},

-- 			ShowOldExpansion = {
-- 				Unknown = false,
-- 				Reagents = true,
-- 				Usable = false,
-- 				Other = false,
-- 				Auction = true
-- 			},

-- 			ShowQuestItems = true
-- 		},

-- 		Binding = {
-- 			ShowStatus = {
-- 				BankAndBags = true,
-- 				GuildBank = true,
-- 				Merchant = true
-- 			},

-- 			ShowBoA = true,
--			ShowBoARepItems = false,
-- 			ShowBoE = true,
-- 			ShowGearSets = true,
-- 			ShowGearSetsAsIcon = false,
-- 			Position = "BOTTOM"
-- 		}
-- 	}
-- end
