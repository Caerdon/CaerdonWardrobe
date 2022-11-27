CaerdonWardrobeConfigMixin = {}

local ADDON_NAME, NS = ...
local L = NS.L
local components, pendingConfig

CAERDON_CONFIG_LABEL = L["Caerdon Wardrobe... and more!"]
CAERDON_CONFIG_SUBTEXT = L[ [[
This addon started as a simple way for me to track unlearned transmog appearances.  Over the years, it has grown into so much more!

Caerdon Wardrobe now provides tracking of unlearned recipes, pets, mounts, toys, and transmog appearances.  It shows locked and openable containers.  It tracks BoE and BoA bindings, equipment sets, and can highlight gear to sell that is not tradeable, not part of a set, and has no other potentially interesting use.

New for Shadowlands, it also tracks unlearned conduits, and I've even added an old expansion indicator that can help you clean out your bags for your new journey!

Caerdon Wardrobe leverages a set of icons and text where appropriate to call out all of the above items in the following locations: Bank & Bags, Guild Banks, Auction House, Merchants, Dungeon and Raid Journal, Loot Pickup, Group Loot Roll, and the World Map.

It also provides integration for your favorite bag add-ons: AdiBags, ArkInventory, Bagnon, Baud Bag, cargBags_Nivaya, Combuctor, ElvUI, Inventorian, and LiteBag.  Additionally it supports a few other World Quest addons: World Quest Tab and Zygor World Quest Planner.

I don't like slow addons and try my best to keep this addon from impacting your fun.  If Caerdon Wardrobe is causing a performance impact on your game, please let me know!
]] ]

function CaerdonWardrobeConfigMixin:OnLoad()
	self:RegisterEvent("VARIABLES_LOADED");

	self.name = "Caerdon Wardrobe"
	self.okay = self.OnSave

	self.OnCommit = self.okay;
	self.OnDefault = self.default;
	self.OnRefresh = self.refresh;

	local category, layout = Settings.RegisterCanvasLayoutCategory(self, self.name, self.name);
	category.ID = self.name;
	Settings.RegisterAddOnCategory(category);

	-- Any anchors assigned to the frame will be disposed. Intended anchors need to be provided through
	-- the layout object. If no anchor points are provided, the frame will be anchored to TOPLEFT (0,0)
	-- and BOTTOMRIGHT (0,0).
	-- layout:AddAnchorPoint("TOPLEFT", 10, -10);
	-- layout:AddAnchorPoint("BOTTOMRIGHT", -10, 10);
	
end

function CaerdonWardrobeConfigMixin:OnEvent(event, ...)
	-- BlizzardOptionsPanel_OnEvent(self, event, ...);

	if ( event == "VARIABLES_LOADED" ) then
		self.variablesLoaded = true;
		self:UnregisterEvent(event);

		if not CaerdonWardrobeConfig or CaerdonWardrobeConfig.Version ~= NS:GetDefaultConfig().Version then
			print("Caerdon: Old settings detected - updating to defaults.  Please check your settings!")
			CaerdonWardrobeConfig = CopyTable(NS:GetDefaultConfig())
		end
	
		CaerdonWardrobe:RefreshItems()
	end
end

function CaerdonWardrobeConfigMixin:OnSave()
	-- Make sure that errors aren't swallowed for InterfaceOption callbacks
	xpcall(function()
		CaerdonWardrobe:RefreshItems()
	end, geterrorhandler())
end

function NS:GetDefaultConfig()
	return {
		Version = 22,
		
		Debug = {
			Enabled = false
		},

		Icon = {
			EnableAnimation = true,
			Position = "TOPLEFT",

			ShowLearnable = {
				BankAndBags = true,
				GuildBank = true,
				Merchant = true,
				Auction = true,
				SameLookDifferentItem = false,
				SameLookDifferentLevel = true
			},

			ShowUpgrades = {
				BankAndBags = true
			},

			ShowLearnableByOther = {
				BankAndBags = true,
				GuildBank = true,
				Merchant = true,
				Auction = true,
				EncounterJournal = true
			},

			ShowSellable = {
				BankAndBags = true,
				GuildBank = false
			},

			ShowOldExpansion = {
				Unknown = false,
				Reagents = true,
				Usable = false,
				Other = false,
				Auction = true
			},

			ShowQuestItems = true
		},

		Binding = {
			ShowStatus = {
				BankAndBags = true,
				GuildBank = true,
				Merchant = true
			},

			ShowBoA = true,
			ShowBoE = true,
			ShowGearSets = true,
			ShowGearSetsAsIcon = false,
			Position = "BOTTOM"
		}
	}
end
