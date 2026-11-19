local _, NS = ...
local AuctionMixin = {}

function AuctionMixin:GetName()
	return "Auction"
end

-- TODO: Look into ScrollUtil.AddAcquiredFrameCallback and friends for all the ScrollBox integrations
function AuctionMixin:Init(frame)
	self.waitingForItemKeyInfo = {}
	self.auctionContinuableContainer = ContinuableContainer:Create()
	self.shouldHookAuction = true

	return {
		"AUCTION_HOUSE_SHOW",
		"ITEM_KEY_ITEM_INFO_RECEIVED",
		-- "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
		-- "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"
		-- "OWNED_AUCTIONS_UPDATED"
	}
end

-- function AuctionMixin:AUCTION_HOUSE_BROWSE_RESULTS_UPDATED()
-- 	print("Results Updated")
-- 	-- DevTools_Dump(C_AuctionHouse.GetBrowseResults())
-- end

-- function AuctionMixin:AUCTION_HOUSE_BROWSE_RESULTS_ADDED()
-- 	print("Results Added")
-- end

function AuctionMixin:AUCTION_HOUSE_SHOW()
	if (self.shouldHookAuction) then
		self.shouldHookAuction = false
		ScrollUtil.AddInitializedFrameCallback(AuctionHouseFrame.AuctionsFrame.AllAuctionsList.ScrollBox, function (...) self:OnAllAuctionsInitializedFrame(...) end, AuctionHouseFrame.AuctionsFrame.AllAuctionsList, false)
		ScrollUtil.AddInitializedFrameCallback(AuctionHouseFrame.BrowseResultsFrame.ItemList.ScrollBox, function (...) self:OnInitializedFrame(...) end, AuctionHouseFrame.BrowseResultsFrame.ItemList, false)
		-- The listings of one item, which a row of the results opens.
		local itemBuyList = AuctionHouseFrame.ItemBuyFrame and AuctionHouseFrame.ItemBuyFrame.ItemList
		if itemBuyList and itemBuyList.ScrollBox then
			ScrollUtil.AddInitializedFrameCallback(itemBuyList.ScrollBox, function (...) self:OnItemBuyInitializedFrame(...) end, itemBuyList, false)
		end
		if C_AddOns.IsAddOnLoaded("TradeSkillMaster") then
			 -- TSM breaks the normal AH scrollbox frame initialization, so we have to hook into scroll events to ensure we can still show icons
			 -- NOTE: This only ensures icons show up in the Blizzard AH interface.  TSM is unreasonably locked down, so I can't augment it at
			 -- all.
			AuctionHouseFrame.BrowseResultsFrame.ItemList.ScrollBox:RegisterCallback(BaseScrollBoxEvents.OnLayout, function (...) self.OnScrollBoxLayout(..., AuctionHouseFrame.BrowseResultsFrame.ItemList.ScrollBox) end, self);
			AuctionHouseFrame.BrowseResultsFrame.ItemList.ScrollBox:RegisterCallback(BaseScrollBoxEvents.OnScroll, function (...) self.OnScrollBoxScroll(..., AuctionHouseFrame.BrowseResultsFrame.ItemList.ScrollBox) end, self);
		end
		-- The addon's own columns in the two lists (WithColumns).
		local browseFrame, itemBuyFrame = AuctionHouseFrame.BrowseResultsFrame, AuctionHouseFrame.ItemBuyFrame
		if type(browseFrame.SetupTableBuilder) == "function" then
			hooksecurefunc(browseFrame, "SetupTableBuilder", function(frame) self:OnBrowseSetupTableBuilder(frame) end)
			-- Results have come: whether a category of one kind is worn is asked of them, and
			-- the client lays the list out before it has them.
			if type(browseFrame.UpdateBrowseResults) == "function" then
				hooksecurefunc(browseFrame, "UpdateBrowseResults", function(frame) self:OnBrowseSetupTableBuilder(frame, true) end)
			end
			-- The list has its first layout by now: the icon's column from the first search on.
			self:OnBrowseSetupTableBuilder(browseFrame)
		end
		if itemBuyFrame and type(itemBuyFrame.SetItemKey) == "function" then
			hooksecurefunc(itemBuyFrame, "SetItemKey", function(frame, itemKey) self:OnItemBuySetItemKey(frame, itemKey) end)
		end
		hooksecurefunc(AuctionHouseFrame, "SelectBrowseResult", function(...) self:OnSelectBrowseResult(...) end)
		hooksecurefunc(AuctionHouseFrame, "SetPostItem", function(...) self:OnSetPostItem(...) end)
		hooksecurefunc(AuctionHouseFrame.AuctionsFrame.ItemDisplay, "SetItemInternal", function(...) self:OnSetAuctionItemDisplay(...) end)
	end
end

function AuctionMixin:ITEM_KEY_ITEM_INFO_RECEIVED(itemID)
	local processQueue = self.waitingForItemKeyInfo[itemID]
	if processQueue then
		for locationKey, processInfo in pairs(processQueue) do
			local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(processInfo.itemKey)
			if itemKeyInfo then
				self:ProcessItemKeyInfo(processInfo.itemKey, itemKeyInfo, processInfo.frame)
			end
		end

		self.waitingForItemKeyInfo[itemID] = nil
	end
end

function AuctionMixin:OnScrollBoxLayout(scrollBox)
	scrollBox:ForEachFrame(function(frame, elementData)
		self:OnInitializedFrame(AuctionHouseFrame.BrowseResultsFrame, frame, elementData)
	end)
end

local scrollTimer
function AuctionMixin:OnScrollBoxScroll(scrollBox)
	if scrollTimer then
		scrollTimer:Cancel()
	end

	scrollBox:ForEachFrame(function(frame, elementData)
		frame.caerdonDebugItemLink = nil
		self:ClearResultsRow(frame)
	end)

	scrollTimer = C_Timer.NewTimer(0.1, function ()
		scrollBox:ForEachFrame(function(frame, elementData)
			self:OnInitializedFrame(AuctionHouseFrame.BrowseResultsFrame, frame, elementData)
		end)
	end)
end

function AuctionMixin:OnAllAuctionsInitializedFrame(auctionFrame, frame, elementData)
	local button = frame
	local item

	if not elementData then return end

	local browseResult = auctionFrame.tableBuilder:GetDataProviderData(elementData)
	
	if not browseResult.itemLink then
		button.caerdonDebugItemLink = nil
		CaerdonWardrobe:ClearButton(button)
		return
	end

	local item = CaerdonItem:CreateFromItemLink(browseResult.itemLink)
	local itemKey = browseResult.itemKey

	button.caerdonDebugItemLink = browseResult.itemLink

	local function doUpdate()
		CaerdonWardrobe:UpdateButton(button, item, self, {
			locationKey = format("allAuctions%d-%d-%d", itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix),
			itemKey = itemKey
		},
		{
			overrideStatusPosition = "LEFT",
			statusProminentSize = 13,
			statusOffsetX = 7,
			statusOffsetY = 0
		})
	end

	if item:IsItemDataCached() then
		doUpdate()
	else
		item:ContinueOnItemLoad(doUpdate)
	end
end

-- The addon's own columns in the auction house's lists (author decision: first in the row).
--
-- The lists are built by the client's table builder from a layout function a list is given
-- (ItemList:SetTableBuilderLayout). The addon wraps that function: the client's columns, and
-- its own put first. A column is there for a whole list at a time, so when it is there is the
-- feature's to say:
--   The results have a narrow column for the addon's icon: the icon is on rows of every kind
--   (a reagent's as much as a helm's).
--   The results have a second one for the upgrade (the arrow, and the level gain where that
--   is shown) while a gear category is the one selected (weapons, armor) and its pieces are
--   ones the toon wears: a category of several kinds has some that are (all armor); one of a
--   single kind (plate, one-handed axes) is asked of the first row found
--   (IsSelectedCategoryWorn). Read as the client lays the list out anew, and as results come.
--   An item's listings have one for each listing's percentage, while the item opened is a
--   weapon or armor of which a piece could be scored for what is worn
--   (CaerdonEquipment:CanScorePieceForWorn: not gear the toon would not wear), as the
--   client's own selling page changes its columns by the item.
--
-- What a column holds is there with the column and not without it (author decision). Each
-- kind has its switch (Auction.IconColumn, Auction.UpgradeColumn), and the upgrade columns
-- need the upgrade arrow on as well (Icon.ShowUpgradeIcon). With the icon's column off the
-- results have no icon of the addon's. Without the upgrade column, by its switch or because
-- the category has none (another category, a search across everything, gear the toon does not
-- wear), a row has no arrow and no gain, and an item's listings no percentage. Nothing is put
-- on the client's own columns instead: the icon lay on the price, and the gain on the
-- favorite star, before the columns were there.
--
-- The results' upgrade column is also left out where the player's own settings leave nothing
-- to put in it (author decision; CouldResultsHoldUpgrade): the arrow of a higher item level
-- switched off and the level gain not shown, with no row found that Pawn could judge.
--
-- A column is headed by an icon of the addon's, not a word (author decision): the star of a
-- look to learn for the icon's column, the upgrade arrow for the others. A word made the
-- column as wide as the word.
--
-- A cell (CaerdonAuctionCellTemplate, CaerdonWardrobe.xml) is one of a pool, and the builder
-- hands it to another row whenever the table is arranged anew. So a cell fills itself from its
-- row's data, out of what the feature keeps (GetListingText), and nothing is anchored to it
-- from outside: what the core draws on a row of the results is placed from the row's own
-- left edge, where the columns are (AskResultsRow). A row calls OnLineEnter and OnLineLeave
-- on every cell.
local STAR_HEADER = "|TInterface\\Store\\category-icon-featured:14:14:0:0:64:64:16:48:16:48|t"
local ARROW_HEADER = "|TInterface\\Buttons\\JumpUpArrow:14:14:0:0:32:32:0:32:0:32:102:255:51|t"
local COLUMNS = {
	icon = { width = 24, header = STAR_HEADER, leftPadding = 0 },
	results = { width = 44, header = ARROW_HEADER, leftPadding = 0 },
	listing = { width = 56, header = ARROW_HEADER, leftPadding = 6 },
}
-- Where the core's parts go on a row of the results, counted from the row's left edge. The
-- icon in the middle of its column; before the feature has laid the list out (or where it
-- could not), on the price column's left, as it was before the columns.
local ICON_X = COLUMNS.icon.width / 2
local ICON_ON_PRICE_X = 7
local UPGRADE_INSET = 2
local UPGRADE_WIDTH = COLUMNS.results.width - 4
local UPGRADE_ARROW_X = 8

CaerdonAuctionCellMixin = {}

function CaerdonAuctionCellMixin:Init(owner, feature, kind)
	self.caerdonFeature = feature
	self.caerdonKind = kind
end

function CaerdonAuctionCellMixin:Populate(rowData, dataIndex)
	local feature = self.caerdonFeature
	local text = nil
	if feature and self.caerdonKind == "listing" then
		text = feature:GetListingText(rowData)
	end
	self.Text:SetText(text or "")
end

function CaerdonAuctionCellMixin:OnLineEnter()
end

function CaerdonAuctionCellMixin:OnLineLeave()
end

-- The upgrade arrow's own switch: no percentage and no upgrade column without it.
local function WantsUpgrades()
	local iconConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon
	return iconConfig ~= nil and iconConfig.ShowUpgradeIcon ~= false
end

local function WantsIconColumn()
	local auctionConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Auction
	return not (auctionConfig and auctionConfig.IconColumn == false)
end

local function WantsUpgradeColumn()
	local auctionConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Auction
	return WantsUpgrades() and not (auctionConfig and auctionConfig.UpgradeColumn == false)
end

-- A list's layout with the addon's columns first, in the order named. kinds: of COLUMNS.
-- The layout made is known for the addon's (layoutBases), so that it is not wrapped again.
function AuctionMixin:WithColumns(base, owner, kinds)
	local feature = self
	local layout = function(tableBuilder)
		base(tableBuilder)
		local columns = tableBuilder:GetColumns()
		for index, kind in ipairs(kinds) do
			local spec = COLUMNS[kind]
			local column = tableBuilder:AddUnsortableFixedWidthColumn(owner, 0, spec.width, spec.leftPadding, 0, spec.header,
				"CaerdonAuctionCellTemplate", feature, kind)
			-- Added last, as the builder adds: among the first in the list instead.
			if #columns > 1 and columns[#columns] == column then
				table.remove(columns)
				table.insert(columns, index, column)
			end
		end
	end
	self.layoutBases = self.layoutBases or setmetatable({}, { __mode = "k" })
	self.layoutBases[layout] = base
	return layout
end

-- The category selected in the auction house, as the client's own table has it: the top one,
-- and the deepest of what was chosen under it (the same where nothing was).
local function SelectedCategory()
	local categoriesList = AuctionHouseFrame and AuctionHouseFrame.GetCategoriesList and AuctionHouseFrame:GetCategoriesList()
	if not (categoriesList and categoriesList.GetSelectedCategory and AuctionCategories) then
		return nil
	end
	local index, subIndex, subSubIndex = categoriesList:GetSelectedCategory()
	local top = index and AuctionCategories[index]
	local deepest = top
	if deepest and subIndex and deepest.subCategories and deepest.subCategories[subIndex] then
		deepest = deepest.subCategories[subIndex]
		if subSubIndex and deepest.subCategories and deepest.subCategories[subSubIndex] then
			deepest = deepest.subCategories[subSubIndex]
		end
	end
	return top, deepest
end

-- Whether the category selected in the auction house is one of gear. By the category's name,
-- which is the client's own string in both flavors; the detail column a category names is the
-- item level in one flavor and the required level in the other.
function AuctionMixin:IsGearCategorySelected()
	local top = SelectedCategory()
	local name = top and top.name
	return name ~= nil and (name == AUCTION_CATEGORY_WEAPONS or name == AUCTION_CATEGORY_ARMOR)
end

-- Whether the category selected holds pieces the toon wears. A category's filters name the
-- item class and subclass of each of its parts (AuctionCategoryMixin:AddFilter). One of
-- several kinds does: some of its rows will be worn. One of a single kind is asked of the
-- first row the search found, every row being of that kind (CaerdonEquipment:IsKindWorn), as
-- long as that row is of the kind: the results can still be an earlier search's. What cannot
-- be told counts as worn.
function AuctionMixin:IsSelectedCategoryWorn()
	local _, category = SelectedCategory()
	local filters = category and category.filters
	if type(filters) ~= "table" or #filters == 0 then
		return true
	end
	local classID, subClassID = filters[1].classID, filters[1].subClassID
	if classID == nil or subClassID == nil then
		return true
	end
	for _, filter in ipairs(filters) do
		if filter.classID ~= classID or filter.subClassID ~= subClassID then
			return true
		end
	end
	local results = C_AuctionHouse and C_AuctionHouse.GetBrowseResults and C_AuctionHouse.GetBrowseResults()
	local first = type(results) == "table" and results[1] or nil
	local itemID = first and first.itemKey and first.itemKey.itemID
	if not itemID or not CaerdonEquipment.IsKindWorn then
		return true
	end
	local _, _, _, _, _, firstClassID, firstSubClassID = C_Item.GetItemInfoInstant(itemID)
	if firstClassID ~= classID or firstSubClassID ~= subClassID then
		return true
	end
	return CaerdonEquipment:IsKindWorn(itemID)
end

-- The client has laid the list of results out (at first, and anew for a search in another
-- category), results have come, or a setting may have changed (onlyIfChanged): the icon's
-- column, and the upgrade's with a gear category the toon wears, each where its switch is on.
-- The rows go by what is there (AskResultsRow). Returns whether the list was laid out anew.
function AuctionMixin:OnBrowseSetupTableBuilder(browseFrame, onlyIfChanged)
	local list = browseFrame and browseFrame.ItemList
	local current = list and list.tableBuilderLayoutFunction
	if type(current) ~= "function" or type(list.SetTableBuilderLayout) ~= "function" then
		self.resultsKinds, self.resultsUpgradeLeft, self.resultsUpgradeHeldBack = nil, nil, nil
		return false
	end
	local kinds = {}
	if WantsIconColumn() then
		kinds[#kinds + 1] = "icon"
	end
	-- The upgrade's column where it could have anything in it (CouldResultsHoldUpgrade): held
	-- back, and not refused, where a row not drawn yet could change that (NoteRowLink).
	local heldBack = false
	if WantsUpgradeColumn() and self:IsGearCategorySelected() and self:IsSelectedCategoryWorn() then
		if self:CouldResultsHoldUpgrade() then
			kinds[#kinds + 1] = "results"
		else
			heldBack = true
		end
	end
	self.resultsUpgradeHeldBack = heldBack
	local wanted = table.concat(kinds, " ")
	local ours = self.layoutBases ~= nil and self.layoutBases[current] ~= nil
	if onlyIfChanged and wanted == (self.resultsKinds or "") and (ours or wanted == "") then
		return false
	end

	-- Where the upgrade's column begins in a row: after the icon's, where that is there.
	local iconColumn, upgradeColumn = kinds[1] == "icon", kinds[#kinds] == "results"
	self.resultsKinds = wanted
	self.resultsUpgradeLeft = upgradeColumn and ((iconColumn and COLUMNS.icon.width or 0) + UPGRADE_INSET) or nil

	local base = ours and self.layoutBases[current] or current
	if #kinds > 0 then
		list:SetTableBuilderLayout(self:WithColumns(base, browseFrame, kinds))
	elseif ours then
		list:SetTableBuilderLayout(base)
	else
		return false
	end
	return true
end

-- The page of an item's listings has been given its item: with the column for a weapon or
-- armor of which a piece could be scored for what is worn (not gear the toon would not wear,
-- and not where nothing is scored: no Pawn, a client without specs), since the column would
-- have nothing in it; the client's own layout for anything else.
function AuctionMixin:OnItemBuySetItemKey(itemBuyFrame, itemKey)
	local list = itemBuyFrame and itemBuyFrame.ItemList
	if not (list and type(list.SetTableBuilderLayout) == "function" and AuctionHouseTableBuilder and
		AuctionHouseTableBuilder.GetItemBuyListLayout) then
		return
	end
	local itemID = type(itemKey) == "table" and itemKey.itemID or nil
	local wants = itemID ~= nil and WantsUpgradeColumn() and CaerdonEquipment.CanScorePieceForWorn ~= nil and
		CaerdonEquipment:CanScorePieceForWorn(itemID)
	if wants == (self.listingColumn == true) then
		return
	end
	self.listingColumn = wants
	local base = AuctionHouseTableBuilder.GetItemBuyListLayout(itemBuyFrame, list)
	list:SetTableBuilderLayout(wants and self:WithColumns(base, itemBuyFrame, { "listing" }) or base)
end

-- The listings of one item (AuctionHouseFrame.ItemBuyFrame, the page a row of the results
-- opens; the same list template as the results', in both flavors:
-- Blizzard_AuctionHouseItemBuyFrame.lua). A row of the results stands for every listing of an
-- item at a level and has the plain item's link. These rows are the listings themselves
-- (C_AuctionHouse.GetItemSearchResultInfo), each with its own link.
--
-- They are all one item at one level, so its look to learn and its level gain are the same on
-- every row: those go on the page's own item button, once. What differs is what each listing
-- rolled, so a row has the one thing that tells them apart: what the piece would do for what
-- is worn (CaerdonEquipment:GetBestReplacementGain), as the arrow and a percentage, where it
-- is an upgrade (author decision), in the addon's column. The page's button is drawn from the
-- best listing seen, so its arrow says that something in here is an upgrade, and from the
-- first listing while none is; until a listing has come it is made from the item key, as the
-- row of the results was.

local function KeyText(itemKey)
	if type(itemKey) ~= "table" then
		return ""
	end
	return format("%s-%s-%s", tostring(itemKey.itemID), tostring(itemKey.itemLevel), tostring(itemKey.itemSuffix))
end

-- The cell of the addon's column in a row of listings, as the row stands now.
local function ListingCell(frame)
	local cells = frame.cells
	if type(cells) == "table" then
		for _, cell in ipairs(cells) do
			if cell.caerdonKind == "listing" then
				return cell
			end
		end
	end
	return nil
end

-- What a listing's cell shows: kept for the page by the listing's auction, since a cell is
-- filled when its row is, which can be before its piece has been looked at and again later.
function AuctionMixin:GetListingText(rowData)
	local page = self.listingPage
	local text = page and type(rowData) == "table" and page.texts[rowData.auctionID]
	return text or nil
end

-- An item for an item key, as a row of the results has it (ProcessItemKeyInfo): the level the
-- key names goes beside the link, which is the plain item's, and the look where the row names
-- one.
function AuctionMixin:MakeItemForKey(itemKey, appearanceLink)
	local extraData = {}
	if type(itemKey.itemLevel) == "number" and itemKey.itemLevel > 0 then
		extraData.overrideItemLevel = itemKey.itemLevel
	end
	local link
	if appearanceLink then
		local appearanceSourceID = string.match(appearanceLink, ".*transmogappearance:(%d*)")
		local _, itemAppearanceID, _, _, _, itemLink = C_TransmogCollection.GetAppearanceSourceInfo(appearanceSourceID)
		extraData.appearanceSourceID = appearanceSourceID
		extraData.appearanceID = itemAppearanceID
		link = itemLink
	end
	local item
	if link then
		item = CaerdonItem:CreateFromItemLink(link, extraData)
	else
		item = CaerdonItem:CreateFromItemID(itemKey.itemID)
		item.extraData = extraData
	end
	return item
end

function AuctionMixin:OnItemBuyInitializedFrame(itemList, frame, elementData)
	if not elementData then return end

	local rowData = nil
	local tableBuilder = itemList and itemList.tableBuilder
	if tableBuilder and tableBuilder.GetDataProviderData then
		rowData = tableBuilder:GetDataProviderData(elementData)
	end
	if type(rowData) ~= "table" then
		rowData = frame.rowData
	end

	if type(rowData) ~= "table" or not rowData.itemLink then
		frame.caerdonAuctionID = nil
		frame.caerdonDebugItemLink = nil
		return
	end

	local item = CaerdonItem:CreateFromItemLink(rowData.itemLink)
	local auctionID = rowData.auctionID
	frame.caerdonAuctionID = auctionID
	frame.caerdonDebugItemLink = rowData.itemLink

	local function doUpdate()
		-- The row stands for another listing by the time the item's data came.
		if frame.caerdonAuctionID ~= auctionID then
			return
		end
		self:ShowListingGain(frame, item, rowData)
	end

	if item:IsItemDataCached() then
		doUpdate()
	else
		item:ContinueOnItemLoad(doUpdate)
	end
end

-- A listing whose item's data is there: its percentage for its cell, and its word to the
-- page's button. Only with the upgrade arrow on (Icon.ShowUpgradeIcon): this is that arrow,
-- for a row.
function AuctionMixin:ShowListingGain(frame, item, rowData)
	local gain = nil
	if WantsUpgrades() and CaerdonEquipment.GetBestReplacementGain and
		item:GetCaerdonItemType() == CaerdonItemType.Equipment then
		gain = CaerdonEquipment:GetBestReplacementGain(item)
	end
	local text = gain and NS.Tooltip and NS.Tooltip.GetShortGainText and NS.Tooltip:GetShortGainText(gain) or nil
	self:NoteListing(rowData, text and gain.percent or nil, text)
	local cell = ListingCell(frame)
	if cell and cell.Text then
		cell.Text:SetText(text or "")
	end
end

-- What the listings seen so far say: each one's text for its cell, and for the page's button
-- the first of them and the one that gains most. A listing of another item key starts the
-- page anew.
function AuctionMixin:NoteListing(rowData, percent, text)
	local key = KeyText(rowData.itemKey)
	local page = self.listingPage
	if not page or page.key ~= key then
		page = { key = key, texts = {} }
		self.listingPage = page
	end
	if rowData.auctionID ~= nil then
		page.texts[rowData.auctionID] = text or false
	end
	local changed = false
	if not page.firstLink then
		page.firstLink = rowData.itemLink
		changed = true
	end
	if percent and (not page.bestPercent or percent > page.bestPercent) then
		page.bestPercent, page.bestLink = percent, rowData.itemLink
		changed = true
	end
	if changed then
		self:UpdateListingButton()
	end
end

function AuctionMixin:UpdateListingButton()
	local page = self.listingPage
	local link = page and (page.bestLink or page.firstLink)
	local itemBuyFrame = AuctionHouseFrame and AuctionHouseFrame.ItemBuyFrame
	local button = itemBuyFrame and itemBuyFrame.ItemDisplay and itemBuyFrame.ItemDisplay.ItemButton
	if not link or not button or page.shownLink == link then
		return
	end
	page.shownLink = link

	local item = CaerdonItem:CreateFromItemLink(link)
	local function doUpdate()
		-- Another page, or a better listing, by the time the item's data came.
		if self.listingPage ~= page or page.shownLink ~= link then
			return
		end
		button.caerdonDebugItemLink = link
		CaerdonWardrobe:UpdateButton(button, item, self, {
			locationKey = "BrowseResultButton"
		},
		{
			statusProminentSize = 24,
			statusOffsetX = 5,
			statusOffsetY = 5
		})
	end

	if item:IsItemDataCached() then
		doUpdate()
	else
		item:ContinueOnItemLoad(doUpdate)
	end
end

-- A refresh: the buttons the core drew are asked for again as any window's are. Then what is
-- the feature's own. The results are laid out anew where a switch for a column has changed,
-- and their rows on screen are asked for with the places that go with the columns (a request
-- kept by the core has the places it was made with). The percentages of an item's listings
-- are the feature's own drawing, so those on screen are walked.
function AuctionMixin:Refresh()
	CaerdonWardrobeFeatureMixin.Refresh(self)
	if not AuctionHouseFrame or self.shouldHookAuction then
		return
	end

	self:LayOutResultsAnew()

	local itemBuyList = AuctionHouseFrame.ItemBuyFrame and AuctionHouseFrame.ItemBuyFrame.ItemList
	if itemBuyList and itemBuyList.ScrollBox and itemBuyList:IsVisible() then
		local page = self.listingPage
		if page then
			page.bestPercent, page.bestLink, page.shownLink = nil, nil, nil
			page.texts = {}
		end
		itemBuyList.ScrollBox:ForEachFrame(function(frame, elementData)
			self:OnItemBuyInitializedFrame(itemBuyList, frame, elementData)
		end)
	end
end

-- The results are laid out anew where the columns wanted have changed, and their rows on
-- screen are then asked for again, with the parts that go with the columns.
function AuctionMixin:LayOutResultsAnew()
	local browseFrame = AuctionHouseFrame and AuctionHouseFrame.BrowseResultsFrame
	local resultsList = browseFrame and browseFrame.ItemList
	if self:OnBrowseSetupTableBuilder(browseFrame, true) and resultsList and resultsList.ScrollBox and
		resultsList:IsVisible() then
		resultsList.ScrollBox:ForEachFrame(function(frame, elementData)
			self:OnInitializedFrame(resultsList, frame, elementData)
		end)
	end
end

-- Whether the results' upgrade column could have anything in it, by the player's own settings
-- (author decision: no column that those leave empty).
--   The level gain, where that is shown (Icon.ShowUpgradeLevelDelta).
--   The arrow of a higher item level, where that counts (CaerdonEquipment:CountsItemLevel:
--   always without Pawn, Icon.ShowItemLevelUpgrades with it).
--   Otherwise an arrow can only be Pawn's, and Pawn is asked only about a row whose link is
--   the piece's own (the key's level is the link's): one of the results found has to be such
--   a row. That is known of a row once it has been drawn (NoteRowLink), and kept by its key.
function AuctionMixin:CouldResultsHoldUpgrade()
	local iconConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon
	if iconConfig and iconConfig.ShowUpgradeLevelDelta then
		return true
	end
	if not CaerdonEquipment.CountsItemLevel or CaerdonEquipment:CountsItemLevel() then
		return true
	end
	local ownLinks = self.rowsOfOwnLink
	local results = ownLinks and C_AuctionHouse and C_AuctionHouse.GetBrowseResults and C_AuctionHouse.GetBrowseResults()
	for _, result in ipairs(type(results) == "table" and results or {}) do
		if ownLinks[KeyText(result.itemKey)] then
			return true
		end
	end
	return false
end

-- A row of the results has its item, while the upgrade's column is held back for having
-- nothing in it: whether the row's link is the piece's own is kept by its key. The first such
-- row brings the column, on the next frame, since a row is drawn from inside the list's own
-- layout; rows drawn in the same frame owe one layout between them.
function AuctionMixin:NoteRowLink(item, itemKey)
	if not self.resultsUpgradeHeldBack or type(itemKey) ~= "table" or not CaerdonEquipment.IsKnownByItsOwnLink then
		return
	end
	local key = KeyText(itemKey)
	self.rowsOfOwnLink = self.rowsOfOwnLink or {}
	if self.rowsOfOwnLink[key] ~= nil then
		return
	end
	local own = CaerdonEquipment:IsKnownByItsOwnLink(item) and true or false
	self.rowsOfOwnLink[key] = own
	if own and not self.resultsLayoutOwed then
		self.resultsLayoutOwed = true
		C_Timer.After(0, function()
			self.resultsLayoutOwed = nil
			self:LayOutResultsAnew()
		end)
	end
end

-- The part of a row of the results that is its upgrade: a frame of the row's own over the
-- addon's upgrade column, which the core draws on as on a button of its own. left: where the
-- column begins in the row; nil to have the frame as it is, if the row has one.
local function ResultsUpgradeFrame(row, left)
	local frame = row.caerdonUpgradeFrame
	if not frame then
		if not left then
			return nil
		end
		frame = CreateFrame("Frame", nil, row)
		row.caerdonUpgradeFrame = frame
	end
	if left then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", row, "TOPLEFT", left, 0)
		frame:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", left, 0)
		frame:SetWidth(UPGRADE_WIDTH)
	end
	return frame
end

-- A row of the results is asked of the core as two buttons, one for each of the addon's
-- columns, and each only where its column is there (see the head of the columns):
--   the row itself, for the icon: any status but the upgrade's arrow, badge and level gain
--   (GetDisplayInfo, auctionPart "icon");
--   the frame over the upgrade column, for the upgrade alone: the arrow where the piece is
--   one, with its level gain (auctionPart "upgrade"). Not for a pet (noUpgrade).
-- A part whose column is not there is cleared, and never asked for.
function AuctionMixin:AskResultsRow(row, item, locationKey, itemKey, noUpgrade)
	if not noUpgrade then
		self:NoteRowLink(item, itemKey)
	end
	local kinds = self.resultsKinds
	-- No layout of the feature's yet: the icon where it was before the columns.
	local iconX = kinds == nil and ICON_ON_PRICE_X or ICON_X
	if WantsIconColumn() and (kinds == nil or kinds:find("icon", 1, true)) then
		CaerdonWardrobe:UpdateButton(row, item, self, {
			locationKey = locationKey,
			itemKey = itemKey,
			auctionPart = "icon"
		},
		{
			overrideStatusPosition = "LEFT",
			statusProminentSize = 13,
			statusOffsetX = iconX,
			statusOffsetY = 0
		})
	else
		CaerdonWardrobe:ClearButton(row)
	end

	local left = not noUpgrade and self.resultsUpgradeLeft or nil
	local upgradeFrame = ResultsUpgradeFrame(row, left)
	if upgradeFrame and left then
		CaerdonWardrobe:UpdateButton(upgradeFrame, item, self, {
			locationKey = locationKey .. "-upgrade",
			itemKey = itemKey,
			auctionPart = "upgrade"
		},
		{
			overrideStatusPosition = "LEFT",
			statusProminentSize = 13,
			statusOffsetX = UPGRADE_ARROW_X,
			statusOffsetY = 0,
			fixedLayout = true
		})
	elseif upgradeFrame then
		CaerdonWardrobe:ClearButton(upgradeFrame)
	end
end

-- A row of the results that shows nothing of the addon's now: both its parts.
function AuctionMixin:ClearResultsRow(row)
	CaerdonWardrobe:ClearButton(row)
	if row.caerdonUpgradeFrame then
		CaerdonWardrobe:ClearButton(row.caerdonUpgradeFrame)
	end
end

function AuctionMixin:ProcessItemKeyInfo(itemKey, itemKeyInfo, button)
	local item
	local rowData = button.rowData

	local locationKey = format("%d-%d-%d-%d", itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix, ((itemKeyInfo and itemKeyInfo.quality) or 0))

	if itemKeyInfo and itemKeyInfo.battlePetLink then
		item = CaerdonItem:CreateFromItemLink(itemKeyInfo.battlePetLink)
		button.caerdonDebugItemLink = itemKeyInfo.battlePetLink

		local function doUpdate()
			self:AskResultsRow(button, item, format("pet-%s", itemKeyInfo.battlePetLink), itemKey, true)
		end

		if item:IsItemDataCached() then
			doUpdate()
		else
			item:ContinueOnItemLoad(doUpdate)
		end
	elseif rowData.appearanceLink then
		-- Using appearance link if it's available due to not getting full item link from AH in any other way right now.
		-- This fixes Nimble Hexweave Cloak, for example, but doesn't fix Ceremonious Greaves (which doesn't have appearanceLink)
		local appearanceSourceID = string.match(rowData.appearanceLink, ".*transmogappearance:(%d*)")
		local category, itemAppearanceID, canHaveIllusion, icon, isCollected, itemLink, transmoglink, sourceType, itemSubClass =
			C_TransmogCollection.GetAppearanceSourceInfo(appearanceSourceID)

		-- Pass itemKey.itemLevel directly as overrideItemLevel since item links from AH don't encode the actual listing's ilvl
		local extraData = {
			appearanceSourceID = appearanceSourceID,
			appearanceID = itemAppearanceID,
			overrideItemLevel = itemKey.itemLevel
		}

		if itemLink then
			item = CaerdonItem:CreateFromItemLink(itemLink, extraData)
		else
			item = CaerdonItem:CreateFromItemID(itemKey.itemID)
			item.extraData = extraData
		end

		button.caerdonDebugItemLink = itemLink or item:GetItemLink()

		CaerdonAPI:CompareCIMI(self, item)

		local function doUpdate()
			self:AskResultsRow(button, item, locationKey, itemKey)
		end

		if item:IsItemDataCached() then
			doUpdate()
		else
			item:ContinueOnItemLoad(doUpdate)
		end
	else
		-- Pass itemKey.itemLevel directly as overrideItemLevel since item links from AH don't encode the actual listing's ilvl
		local extraData = { overrideItemLevel = itemKey.itemLevel }

		-- C_TooltipInfo.GetItemKey().hyperlink is unstable for recipes: the first call
		-- returns the recipe link, but after item data loads the tooltip resolves the
		-- embedded created item and hyperlink flips to the crafted piece's link.
		-- Use CreateFromItemID for recipes to avoid this; other items keep the full
		-- hyperlink for scaling/ilvl data.
		local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemKey.itemID)
		local isRecipe = classID == Enum.ItemClass.Recipe

		if isRecipe then
			item = CaerdonItem:CreateFromItemID(itemKey.itemID)
			item.extraData = extraData
		else
			local requiredLevel = C_AuctionHouse.GetItemKeyRequiredLevel(itemKey)
			local tooltipData = C_TooltipInfo and C_TooltipInfo.GetItemKey(itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix, requiredLevel)

			if tooltipData and tooltipData.hyperlink then
				item = CaerdonItem:CreateFromItemLink(tooltipData.hyperlink, extraData)
			else
				-- Fall back to itemID if we can't get a proper link
				item = CaerdonItem:CreateFromItemID(itemKey.itemID)
				item.extraData = extraData
			end
		end

		button.caerdonDebugItemLink = item:GetItemLink()

		CaerdonAPI:CompareCIMI(self, item)

		local function doUpdate()
			self:AskResultsRow(button, item, locationKey, itemKey)
		end

		if item:IsItemDataCached() then
			doUpdate()
		else
			item:ContinueOnItemLoad(doUpdate)
		end
	end
end

function AuctionMixin:OnInitializedFrame(auctionFrame, frame, elementData)
	if not elementData then return end
	if not frame.rowData then return end

	local itemKey = frame.rowData.itemKey
	local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(itemKey)
	if not itemKeyInfo then
		local processKey = format("%d-%d-%d-%d", itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix, itemKey.battlePetSpeciesID)
		self.waitingForItemKeyInfo[itemKey.itemID] = self.waitingForItemKeyInfo[itemKey.itemID] or {}
		self.waitingForItemKeyInfo[itemKey.itemID][processKey] = { itemKey = itemKey, frame = frame }
		frame.caerdonDebugItemLink = nil
		self:ClearResultsRow(frame)
		return
	end

	self:ProcessItemKeyInfo(itemKey, itemKeyInfo, frame)
end

function AuctionMixin:GetTooltipData(item, locationInfo)
	local itemKey = locationInfo.itemKey
	if itemKey and itemKey.itemID and itemKey.itemLevel and itemKey.itemSuffix then
		local requiredLevel = C_AuctionHouse.GetItemKeyRequiredLevel(itemKey)
		return C_TooltipInfo.GetItemKey(itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix, requiredLevel)
	else
		return C_TooltipInfo.GetHyperlink(item:GetItemLink())
	end
end

function AuctionMixin:GetDisplayInfo(button, item, feature, locationInfo, options, mogStatus, bindingStatus)
	local info = {
		bindingStatus = {
			shouldShow = false
		},
		ownIcon = {
			shouldShow = CaerdonWardrobeConfig.Icon.ShowLearnable.Auction
		},
		otherIcon = {
			shouldShow = CaerdonWardrobeConfig.Icon.ShowLearnableByOther.Auction
		},
		questIcon = {
			shouldShow = false
		},
		oldExpansionIcon = {
			shouldShow = CaerdonWardrobeConfig.Icon.ShowOldExpansion.Auction
		},
        sellableIcon = {
            shouldShow = false
        }
	}
	-- A row of the results is two buttons, one for each of the addon's columns (AskResultsRow):
	-- the icon's has nothing of the upgrade, and the upgrade's has the upgrade alone.
	local part = locationInfo and locationInfo.auctionPart
	if part == "icon" then
		info.upgradeIcon = { shouldShow = false }
		info.levelGain = { shouldShow = false }
	elseif part == "upgrade" then
		info.statusIcon = { shouldShow = false }
	end
	return info
end

function AuctionMixin:OnSetAuctionItemDisplay(frame, itemDisplayItem)
	local itemDisplay = AuctionHouseFrame.AuctionsFrame.ItemDisplay
	local itemButton = itemDisplay.ItemButton

	if itemDisplay.itemValidationFunc and not itemDisplay.itemValidationFunc(itemDisplay) then
		return;
	end

	if not itemDisplayItem then
		itemButton.caerdonDebugItemLink = nil
		CaerdonWardrobe:ClearButton(itemButton)
		return;
	end

	if itemDisplay.itemLink == nil then
		itemButton.caerdonDebugItemLink = nil
		CaerdonWardrobe:ClearButton(itemButton)
		return;
	end

	local item = CaerdonItem:CreateFromItemLink(itemDisplay.itemLink)

	itemButton.caerdonDebugItemLink = itemDisplay.itemLink

	local function doUpdate()
		CaerdonWardrobe:UpdateButton(itemButton, item, self, {
			locationKey = "ItemAuctionItemDisplayButton",
			itemKey = itemDisplay.itemKey
		},
		{
			statusProminentSize = 24,
			statusOffsetX = 5,
			statusOffsetY = 5
		})
	end

	if item:IsItemDataCached() then
		doUpdate()
	else
		item:ContinueOnItemLoad(doUpdate)
	end
end

-- function AuctionMixin:OWNED_AUCTIONS_UPDATED()
-- 	-- self:UpdateItemList(AuctionHouseFrame.AuctionsFrame.AllAuctionsList, 1)
-- end

-- function AuctionMixin:OnScrollBoxRangeChanged(sortPending)
-- 	self:UpdateItemList(AuctionHouseFrame.BrowseResultsFrame.ItemList, 2)
-- end

-- function AuctionMixin:UpdateItemList(itemList, buttonCellIndex)
-- 	if self.auctionTimer then
-- 		self.auctionTimer:Cancel()
-- 	end

-- 	-- TODO: Battle Pet scans are not clean, yet.
-- 	self.auctionContinuableContainer:Cancel()

-- 	self.auctionTimer = C_Timer.NewTimer(0.05, function() 
-- 		local index = itemList.ScrollBox:GetDataIndexBegin();
-- 		itemList.ScrollBox:ForEachFrame(function(button)
-- 			local browseResult = itemList.tableBuilder:GetDataProviderData(index)
-- 			if browseResult then
-- 				local item = CaerdonItem:CreateFromItemID(browseResult.itemKey.itemID)
-- 				if not item:IsItemEmpty() then
-- 					self.auctionContinuableContainer:AddContinuable(item)
-- 				end
-- 			end

-- 			index = index + 1;
-- 		end);

-- 		self.auctionContinuableContainer:ContinueOnLoad(function()
-- 			-- local checkOffset = itemList:GetScrollOffset();
-- 			-- -- TODO: Not sure if this is actually doing anything - hasn't been triggered, yet.
-- 			-- if checkOffset ~= offset then 
-- 			-- 	return
-- 			-- end

-- 			-- for i, button in ipairs(buttons) do
-- 			local dataIndex = itemList.ScrollBox:GetDataIndexBegin();
-- 			local dataIndexEnd = itemList.ScrollBox:GetDataIndexEnd();
-- 			local frameCount = itemList.ScrollBox:GetFrameCount()
-- 			local offset = 0
-- 			if frameCount < dataIndexEnd then
-- 				offset = frameCount - dataIndexEnd
-- 			end
-- 			itemList.ScrollBox:ForEachFrame(function(button)
-- 				local slot = dataIndex + offset
-- 				local browseResult = itemList.tableBuilder:GetDataProviderData(dataIndex)
-- 				if browseResult then
-- 					local row = itemList.tableBuilder.rows[slot] -- TODO: This is matching on the wrong row... probably unsorted?  Searching through for now.
-- 					for i, checkRow in ipairs(itemList.tableBuilder.rows) do
-- 						if checkRow.rowData == browseResult then
-- 							row = checkRow
-- 						end
-- 					end

-- 					local cell = row.cells[buttonCellIndex]
			
-- 					if button then
-- 						local item
-- 						local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(browseResult.itemKey)
		
-- 						if itemKeyInfo and itemKeyInfo.battlePetLink then
-- 							item = CaerdonItem:CreateFromItemLink(itemKeyInfo.battlePetLink)
-- 						else
-- 							item = CaerdonItem:CreateFromItemID(browseResult.itemKey.itemID)
-- 						end

-- 						CaerdonWardrobe:UpdateButton(button, item, self, {
-- 							locationKey = format("%d", slot),
-- 							index = slot,
-- 							itemKey = browseResult.itemKey
-- 						},  
-- 						{
-- 							overrideStatusPosition = "LEFT",
-- 							statusProminentSize = 13,
-- 							statusOffsetX = -4,
-- 							statusOffsetY = 0,
-- 							relativeFrame=cell.Icon
-- 						})
-- 					end
-- 				end
-- 				dataIndex = dataIndex + 1;
-- 			end)
-- 		end)
-- 	end, 1)
-- end

function AuctionMixin:OnSelectBrowseResult(frame, browseResult)
	local itemKey = browseResult.itemKey
	local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(itemKey)
	-- A new page of listings: what they say for this button comes as they do (NoteListing).
	local page = { key = KeyText(itemKey), texts = {} }
	self.listingPage = page

	local item
	if itemKeyInfo and itemKeyInfo.battlePetLink then
		item = CaerdonItem:CreateFromItemLink(itemKeyInfo.battlePetLink)
	else
		item = self:MakeItemForKey(itemKey, browseResult.appearanceLink)
	end

	local button = AuctionHouseFrame.ItemBuyFrame.ItemDisplay.ItemButton
	button.caerdonDebugItemLink = item:GetItemLink()

	local function doUpdate()
		-- A listing has spoken for the button, or another row was opened, since.
		if self.listingPage ~= page or page.shownLink then
			return
		end
		CaerdonWardrobe:UpdateButton(button, item, self, {
			locationKey = "BrowseResultButton",
			itemKey = itemKey
		},
		{
			statusProminentSize = 24,
			statusOffsetX = 5,
			statusOffsetY = 5
		})
	end

	if item:IsItemDataCached() then
		doUpdate()
	else
		item:ContinueOnItemLoad(doUpdate)
	end
end

function AuctionMixin:OnSetPostItem(frame, itemLocation)
	local displayMode = AuctionHouseFrame:GetDisplayMode()
	local item = CaerdonItem:CreateFromItemLocation(itemLocation)

	-- The sell slot is the only place the client reports a real deposit; the auction value
	-- verdicts use it in place of their built-in guess.
	if displayMode == AuctionHouseFrameDisplayMode.ItemSell then
		CaerdonAuctionValue:RecordDepositSample(itemLocation)
	end

	local itemSellButton = AuctionHouseFrame.ItemSellFrame.ItemDisplay.ItemButton
	local commoditiesSellButton = AuctionHouseFrame.CommoditiesSellFrame.ItemDisplay.ItemButton
	if displayMode == AuctionHouseFrameDisplayMode.ItemSell then
		commoditiesSellButton.caerdonDebugItemLink = nil
		CaerdonWardrobe:ClearButton(commoditiesSellButton)

		itemSellButton.caerdonDebugItemLink = item:GetItemLink()

		local function doUpdate()
			CaerdonWardrobe:UpdateButton(itemSellButton, item, self, {
				locationKey = "ItemSellFrameButton",
				itemKey = AuctionHouseFrame.ItemSellFrame.listDisplayedItemKey
			},
			{
				statusProminentSize = 24,
				statusOffsetX = 5,
				statusOffsetY = 5
			})
		end

		if item:IsItemDataCached() then
			doUpdate()
		else
			item:ContinueOnItemLoad(doUpdate)
		end
	elseif displayMode == AuctionHouseFrameDisplayMode.CommoditiesSell then
		itemSellButton.caerdonDebugItemLink = nil
		CaerdonWardrobe:ClearButton(itemSellButton)

		commoditiesSellButton.caerdonDebugItemLink = item:GetItemLink()

		local function doUpdate()
			CaerdonWardrobe:UpdateButton(commoditiesSellButton, item, self, {
				locationKey = "ItemCommoditiesSellFrameButton"
			},
			{
				statusProminentSize = 24,
				statusOffsetX = 5,
				statusOffsetY = 5
			})
		end

		if item:IsItemDataCached() then
			doUpdate()
		else
			item:ContinueOnItemLoad(doUpdate)
		end
	else
		commoditiesSellButton.caerdonDebugItemLink = nil
		CaerdonWardrobe:ClearButton(commoditiesSellButton)
		itemSellButton.caerdonDebugItemLink = nil
		CaerdonWardrobe:ClearButton(itemSellButton)
	end
end

function AuctionMixin:OnClearPostItem(frame)
	local itemSellButton = AuctionHouseFrame.ItemSellFrame.ItemDisplay.ItemButton
	local commoditiesSellButton = AuctionHouseFrame.CommoditiesSellFrame.ItemDisplay.ItemButton

	commoditiesSellButton.caerdonDebugItemLink = nil
	CaerdonWardrobe:ClearButton(commoditiesSellButton)
	itemSellButton.caerdonDebugItemLink = nil
	CaerdonWardrobe:ClearButton(itemSellButton)
end

CaerdonWardrobe:RegisterFeature(AuctionMixin)
