CaerdonWardrobeConfigMixin = {}

local ADDON_NAME, NS = ...
local L = NS.L
local components, pendingConfig

CAERDON_CONFIG_LABEL = L["Caerdon Wardrobe... and more!"]
CAERDON_CONFIG_SUBTEXT = L[ [[
This addon started as a simple way for me to track unlearned transmog appearances.  Over the years, it has grown into so much more.  Caerdon Wardrobe now provides tracking of unlearned recipes, pets, mounts, toys, and transmog appearances.  It shows locked and openable containers.  It tracks BoE and BoA bindings, equipment sets, and can highlight gear to sell that is not tradeable, not part of a set, and has no other potentially interesting use.  New for Shadowlands, it also tracks unlearned conduits, and I've even added an old expansion indicator that can help you clean out your bags for your new journey!

Caerdon Wardrobe leverages a set of icons and text where appropriate to call out all of the above items in the following locations: Bank & Bags, Guild Banks, Auction House, Merchants, Dungeon and Raid Journal, Loot Pickup, Group Loot Roll, and the World Map.  It also provides integration for your favorite bag add-ons: AdiBags, ArkInventory, Bagnon, Baud Bag, cargBags_Nivaya, Combuctor, ElvUI, Inventorian, and LiteBag.  Additionally it supports a few other World Quest addons: World Quest Tab and Zygor World Quest Planner.

I try to really focus on performance.  If Caerdon Wardrobe is causing a performance impact on your game, please let me know!
]] ]

function CaerdonWardrobeConfigMixin:OnLoad()
	self:RegisterEvent("VARIABLES_LOADED");

	self.name = "Caerdon Wardrobe"
	self.okay = self.OnSave

	InterfaceOptions_AddCategory(self)
end

function CaerdonWardrobeConfigMixin:OnEvent(event, ...)
	BlizzardOptionsPanel_OnEvent(self, event, ...);

	if ( event == "VARIABLES_LOADED" ) then
		self.variablesLoaded = true;
		self:UnregisterEvent(event);

		if not CaerdonWardrobeConfig or CaerdonWardrobeConfig.Version ~= NS:GetDefaultConfig().Version then
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
