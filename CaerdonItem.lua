local ADDON_NAME, NS = ...
local L = NS.L

CaerdonItem = {}
CaerdonItemMixin = {}

local version, build, date, tocversion = GetBuildInfo()
local isWarWithin = select(4, GetBuildInfo()) >= 110000

-- Should not be translated - used to provide me with screenshots for debugging.
CaerdonItemType = {
    Empty = "Empty",
    Unknown = "Unknown",
    Unhandled = "Unhandled",
    BattlePet = "Battle Pet", -- pets that have been caged
    CompanionPet = "Companion Pet", -- unlearned pets
    Conduit = "Conduit",
    Consumable = "Consumable",
    Currency = "Currency",
    Equipment = "Equipment",
		Miscellaneous = "Miscellaneous",
    Mount = "Mount",
    Profession = "Profession",
    Recipe = "Recipe",
    Quest = "Quest",
    Toy = "Toy"
}

CaerdonItemBind = {
    None = "None",
    BindOnAccount = "Bind on Account",
    BindOnPickup = "Bind on Pickup",
    BindOnEquip = "Bind on Equip",
    BindOnUse = "Bind on Use",
    QuestItem = "Quest Item",
	Unknown = "Unknown",
}

local function CreateItem()
    local item = CreateFromMixins(
        ItemMixin,
        CaerdonItemMixin
    )
		item.customDataLoaded = false
		return item
end

--[[static]] function CaerdonItem:CreateFromItemLink(itemLink, extraData)
	if type(itemLink) ~= "string" then
		error("Usage: CaerdonItem:CreateFromItemLink(itemLinkString)", 2);
	end

    local item = CreateItem()
    item:SetItemLink(itemLink)
    item.extraData = extraData
    
	return item;
end

--[[static]] function CaerdonItem:CreateFromItemID(itemIDCheck)
    local itemID = tonumber(itemIDCheck)
	if type(itemID) ~= "number" then
		error("Usage: CaerdonItem:CreateFromItemID(itemID)", 2);
    end
    
    local item = CreateItem()
    item:SetItemID(itemID)
    return item;
end

--[[static]] function CaerdonItem:CreateFromItemLocation(itemLocation)
	if type(itemLocation) ~= "table" or type(itemLocation.HasAnyLocation) ~= "function" or not itemLocation:HasAnyLocation() then
		error("Usage: Item:CreateFromItemLocation(notEmptyItemLocation)", 2);
	end
	local item = CreateItem()
	item:SetItemLocation(itemLocation);
	return item;
end

--[[static]] function CaerdonItem:CreateFromBagAndSlot(bagID, slotIndex)
	if type(bagID) ~= "number" or type(slotIndex) ~= "number" then
		error("Usage: Item:CreateFromBagAndSlot(bagID, slotIndex)", 2);
	end
	local item = CreateItem()
	item:SetItemLocation(ItemLocation:CreateFromBagAndSlot(bagID, slotIndex));
	return item;
end

--[[static]] function CaerdonItem:CreateFromEquipmentSlot(equipmentSlotIndex)
	if type(equipmentSlotIndex) ~= "number" then
		error("Usage: Item:CreateFromEquipmentSlot(equipmentSlotIndex)", 2);
	end
	local item = CreateItem()
	item:SetItemLocation(ItemLocation:CreateFromEquipmentSlot(equipmentSlotIndex));
	return item;
end

--[[static]] function CaerdonItem:CreateFromSpeciesInfo(speciesID, level, quality, health, power, speed, customName, petID)
    -- TODO: This is a terrible hack until Blizzard gives me more to work with (mostly for tooltips where I don't have an itemLink).
	if type(speciesID) ~= "number" then
		error("Usage: CaerdonItem:CreateFromSpeciesInfo(speciesID, level, quality, health, power, speed, customName, petID)", 2);
	end

    local name, _, _, _, _, _, _, _, _, _, _, displayID = C_PetJournal.GetPetInfoBySpeciesID(speciesID);
    local itemLink = format("|cff0070dd|Hbattlepet:%d:%d:%d:%d:%d:%d:%x:%d|h[%s]|h|r", speciesID, level, quality, health, power, speed, petID or 0, displayID, customName or name)
    return CaerdonItem:CreateFromItemLink(itemLink)
end

--[[static]] function CaerdonItem:CreateFromItemGUID(itemGUID)
    if type(itemGUID) ~= "string" then
        error("Usage: CaerdonItem:CreateFromItemGUID(itemGUIDString)", 2);
    end

    local item = CreateItem();
    item:SetItemGUID(itemGUID);
    return item;
end


function CaerdonItemMixin:Clear()
    ItemMixin.Clear(self)
    self.caerdonItemType = nil
    self.caerdonItemData = nil
		self.customDataLoaded = false
end

function CaerdonItemMixin:IsItemDataCached() -- Checks for both item and any custom data
	return self:IsItemCached() and self.customDataLoaded;
end

function CaerdonItemMixin:IsItemCached()
	local isItemCached = true

	if self:GetStaticBackingItem() then
		isItemCached = C_Item.IsItemDataCachedByID(self:GetStaticBackingItem());
	end

	if not isItemCached and not self:IsItemEmpty() then
		if self:HasItemLocation() then
			isItemCached = C_Item.IsItemDataCached(self:GetItemLocation());
		else
			isItemCached = false
		end
	end

	-- print("Item ID: " .. self:GetItemID() .. " IsItemCached: " .. tostring(isItemCached))
	return isItemCached;
end

-- Add a callback to be executed when item data is loaded, if the item data is already loaded then execute it immediately
function CaerdonItemMixin:ContinueOnItemLoad(callbackFunction)
    if type(callbackFunction) ~= "function" then
        error("Usage: ContinueOnLoad(callbackFunction)", 2);
    end

		function ProcessTheItem()
			-- TODO: Update things and delay callback if needed for tooltip data
			-- Make sure any dependent data is loaded
			local itemData = self:GetItemData()

			-- Allows for override of continue return if additional data needs to get loaded from a specific mixin (i.e. equipment sources)
			if itemData then
					itemData:ContinueOnItemDataLoad(GenerateClosure(function () 
						self.customDataLoaded = true
						callbackFunction() 
					end))
			else
					self.customDataLoaded = true
					callbackFunction()
			end
		end

		function FailTheItem()
			self.customDataLoaded = false
			-- TODO: Should I provide an errorCallback in this case?
			print("ITEM LOAD FAILED: " .. self:GetItemID())
			callbackFunction()
		end

		if not self:IsItemCached() then
			if not self:IsItemEmpty() then
					CaerdonItemEventListener:AddCallback(self:GetItemID(), GenerateClosure(ProcessTheItem), FailTheItem)
			elseif self:GetCaerdonItemType() == CaerdonItemType.Quest then
					local linkType, linkOptions, name = LinkUtil.ExtractLink(self:GetItemLink());
					local questID = tonumber(strsplit(":", linkOptions), 10)
					CaerdonQuestEventListener:AddCallback(questID, GenerateClosure(ProcessTheItem), FailTheItem)
			else
				ProcessTheItem()
			end
		else
			ProcessTheItem()
		end
end

-- Same as ContinueOnItemLoad, except it returns a function that when called will cancel the continue
function CaerdonItemMixin:ContinueWithCancelOnItemLoad(callbackFunction)
    if type(callbackFunction) ~= "function" then
        error("Usage: ContinueWithCancelOnItemLoad(callbackFunction)", 2);
    end

    if not self:IsItemEmpty() then
        local itemDataCancel
        local itemCancel = CaerdonItemEventListener:AddCancelableCallback(self:GetItemID(), function ()
            -- TODO: Update things and delay callback if needed for tooltip data
            local itemData = self:GetItemData()
            if itemData then
                itemDataCancel = itemData:ContinueWithCancelOnItemDataLoad(function () 
									self.customDataLoaded = true
									callbackFunction()
								end)
            else
							self.customDataLoaded = true
							callbackFunction()
            end
        end, function ()
					self.customDataLoaded = false
					-- TODO: Should I provide an errorCallback in this case?
					print("ITEM LOAD FAILED: " .. self:GetItemID())
					callbackFunction()
				end);

        return function()
            if type(itemDataCancel) == "function" then
                itemDataCancel()
            end

            itemCancel()
        end;
    elseif self:GetCaerdonItemType() == CaerdonItemType.Quest then
        local linkType, linkOptions, name = LinkUtil.ExtractLink(self:GetItemLink());
        local questID = tonumber(strsplit(":", linkOptions), 10);

        local itemDataCancel
        local itemCancel = CaerdonQuestEventListener:AddCancelableCallback(questID, function ()
            -- TODO: Update things and delay callback if needed for tooltip data
            local itemData = self:GetItemData()
            if itemData then
                itemDataCancel = itemData:ContinueWithCancelOnItemDataLoad(function ()
									self.customDataLoaded = true
									callbackFunction()
								end)
            else
							self.customDataLoaded = true
							callbackFunction()
            end
        end, function ()
					self.customDataLoaded = false
					-- TODO: Should I provide an errorCallback in this case?
					print("QUEST ITEM LOAD FAILED: " .. self:GetItemID())
					callbackFunction()
				end);

        return function()
            if type(itemDataCancel) == "function" then
                itemDataCancel()
            end

            itemCancel()
        end;
    else
				self.customDataLoaded = true
				callbackFunction()
				return function () end
    end
end

function CaerdonItemMixin:SetItemLink(itemLink)
    ItemMixin.SetItemLink(self, itemLink)
end

function CaerdonItemMixin:SetItemID(itemID)
    -- Used for embedded item tooltip rewards
    ItemMixin.SetItemID(self, itemID)
end

-- local itemID, itemType, itemSubType, itemEquipLoc, icon, itemTypeID, itemSubClassID = C_Item.GetItemInfoInstant(self:GetStaticBackingItem())

-- TODO: Find lint rule - always need parens around select to reduce to single value
function CaerdonItemMixin:GetItemType()
    if not self:IsItemEmpty() then
        return (select(2, C_Item.GetItemInfoInstant(self:GetItemID())))
    end
end

function CaerdonItemMixin:GetItemSubType()
    if not self:IsItemEmpty() then
        return (select(3, C_Item.GetItemInfoInstant(self:GetItemID())))
    end
end

function CaerdonItemMixin:GetEquipLocation()
    if not self:IsItemEmpty() then
        local equipLocation = (select(4, C_Item.GetItemInfoInstant(self:GetItemID())))
        if equipLocation == "" then
            return nil
        end
        return equipLocation
    end

    return nil
end

function CaerdonItemMixin:GetItemTypeID()
    if not self:IsItemEmpty() then
        return (select(6, C_Item.GetItemInfoInstant(self:GetItemID())))
    end
end

function CaerdonItemMixin:GetItemSubTypeID()
    if not self:IsItemEmpty() then
        return (select(7, C_Item.GetItemInfoInstant(self:GetItemID())))
    end
end

function CaerdonItemMixin:GetHasUse() -- requires item data to be loaded
    if not self:IsItemEmpty() then
        local spellName, spellID = C_Item.GetItemSpell(self:GetItemID())
        return spellID ~= nil
    end
end

-- local itemName, itemLinkInfo, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
-- itemEquipLoc, iconFileDataID, itemSellPrice, itemTypeID, itemSubTypeID, bindType, expacID, itemSetID, 
-- isCraftingReagent = C_Item.GetItemInfo(self:GetItemLink())
function CaerdonItemMixin:GetMinLevel() -- requires item data to be loaded
    if not self:IsItemEmpty() then
        return (select(5, C_Item.GetItemInfo(self:GetItemLink())))
    end
end

function CaerdonItemMixin:GetBinding() -- requires item data to be loaded
		local caerdonType = self:GetCaerdonItemType()
		local binding = CaerdonItemBind.Unknown

		if not self:IsItemEmpty() then
        local bindType = (select(14, C_Item.GetItemInfo(self:GetItemLink())))
        if bindType == 0 then
            binding = CaerdonItemBind.None
        elseif bindType == 1 then -- BoP
            binding = CaerdonItemBind.BindOnPickup
        elseif bindType == 2 then -- BoE
					local isWarboundUntilEquip = C_Item.IsItemBindToAccountUntilEquip(self:GetItemLink())
					if isWarboundUntilEquip then -- WuE
						if caerdonType == CaerdonItemType.Currency then
							binding = CaerdonItemBind.None
						else
							binding = CaerdonItemBind.WarboundUntilEquip
						end
					else
						binding = CaerdonItemBind.BindOnEquip
					end
        elseif bindType == 3 then -- BoU
            binding = CaerdonItemBind.BindOnUse
        elseif bindType == 4 then -- Quest
            binding = CaerdonItemBind.QuestItem
        elseif bindType == 8 then -- BoA, apparently
            -- TODO: This was working... and then seemingly not... keep an eye out.
            binding = CaerdonItemBind.BindOnAccount
        elseif bindType ~= nil then
            print(self:GetItemLink() .. ": Please report - Unknown binding type " .. tostring(bindType))
        end
		else
			  binding = CaerdonItemBind.None
		end

		return binding
end

function CaerdonItemMixin:HasItemLocationBankOrBags()
    local itemLocation = self:GetItemLocation()
    if itemLocation and itemLocation:IsBagAndSlot() then
        return true
    else
        return false
    end
end

function CaerdonItemMixin:IsSoulbound()
    if self:IsItemInPlayersControl() then
        return C_Item.IsBound(self:GetItemLocation())
    else
        return false
    end
end

function CaerdonItemMixin:GetExpansionID() -- requires item data to be loaded
    if not self:IsItemEmpty() then
        return (select(15, C_Item.GetItemInfo(self:GetItemLink())))
    end
end

function CaerdonItemMixin:GetSetID()
    if not self:IsItemEmpty() then
        return (select(16, C_Item.GetItemInfo(self:GetItemLink())))
    end
end

function CaerdonItemMixin:GetIsCraftingReagent()  -- requires item data to be loaded
    if not self:IsItemEmpty() then
        return (select(17, C_Item.GetItemInfo(self:GetItemLink())))
    else
        return false
    end
end

function IsUnhandledType(typeID, subTypeID)
    return typeID == Enum.ItemClass.Container or
        typeID == Enum.ItemClass.Gem or
        typeID == Enum.ItemClass.Reagent or
        typeID == Enum.ItemClass.Projectile or
        typeID == Enum.ItemClass.Tradegoods or
        typeID == Enum.ItemClass.ItemEnhancement or
        typeID == Enum.ItemClass.Quiver or 
        typeID == Enum.ItemClass.Key or
        typeID == Enum.ItemClass.Glyph or
        typeID == Enum.ItemClass.WoWToken or
        typeID == nil
end

function CaerdonItemMixin:GetCaerdonItemType()
    local itemLink = self:GetItemLink()
    if not itemLink then
        return CaerdonItemType.Empty
    end

    -- TODO: Keep an eye on this - caching type now that I'm handling ItemLocation may not be a good idea
    -- if I want to support swapping the item out
    if not self.caerdonItemType then
        local caerdonType = CaerdonItemType.Unknown
        local tempLink = itemLink:gsub(" |A:.*|a]", "]") -- TODO: Temp hack to remove quality from link that breaks ExtractLink

        local linkType, linkOptions, displayText = LinkUtil.ExtractLink(tempLink)
        local typeID = self:GetItemTypeID()
        local subTypeID = self:GetItemSubTypeID()

        local toylink = typeID and C_ToyBox.GetToyLink(self:GetItemID())
        local isConduit = C_Soulbinds.IsItemConduitByItemInfo(itemLink)

        if toylink then
            caerdonType = CaerdonItemType.Toy
        elseif isConduit then
            caerdonType = CaerdonItemType.Conduit
		elseif linkType == "battlepet" then
            caerdonType = CaerdonItemType.BattlePet
        elseif linkType == "quest" then
            caerdonType = CaerdonItemType.Quest
        elseif linkType == "currency" then
            caerdonType = CaerdonItemType.Currency
        elseif linkType == "mount" then
            caerdonType = CaerdonItemType.Mount
        elseif linkType == "item" or linkType == nil then -- Assuming item if we don't have a linkType
            -- TODO: Switching to just checking type for equipment 
            -- instead of using GetEquipLocation (since containers are equippable)
            -- Keep an eye on this
            if IsUnhandledType(typeID, subTypeID) then
                caerdonType = CaerdonItemType.Unhandled
            elseif typeID == Enum.ItemClass.Armor or typeID == Enum.ItemClass.Weapon then
                caerdonType = CaerdonItemType.Equipment
            elseif typeID == Enum.ItemClass.Battlepet then
                caerdonType = CaerdonItemType.BattlePet
            elseif typeID == Enum.ItemClass.Consumable then
                caerdonType = CaerdonItemType.Consumable
            elseif typeID == Enum.ItemClass.Miscellaneous then
                if subTypeID == Enum.ItemMiscellaneousSubclass.CompanionPet then
                    local name, icon, petType, creatureID, sourceText, description, isWild, canBattle, isTradeable, isUnique, isObtainable, displayID, speciesID = C_PetJournal.GetPetInfoByItemID(self:GetItemID());
                    if creatureID and displayID then
                        caerdonType = CaerdonItemType.CompanionPet
                    else
                        caerdonType = CaerdonItemType.Unhandled
                    end
                elseif subTypeID == Enum.ItemMiscellaneousSubclass.Mount or subTypeID == Enum.ItemMiscellaneousSubclass.MountEquipment then
                    caerdonType = CaerdonItemType.Mount
								elseif subTypeID == Enum.ItemMiscellaneousSubclass.Other then
									caerdonType = CaerdonItemType.Miscellaneous
                else
                    caerdonType = CaerdonItemType.Unhandled
                end
            elseif typeID == Enum.ItemClass.Questitem then
                caerdonType = CaerdonItemType.Quest
            elseif typeID == Enum.ItemClass.Recipe then
                caerdonType = CaerdonItemType.Recipe
            elseif typeID == Enum.ItemClass.Profession then
                caerdonType = CaerdonItemType.Profession
            else
                print("Caerdon: Unknown item type " .. tostring(typeID) .. ", " .. tostring(linkType) .. " (unknown): " .. itemLink)
            end
		elseif linkType == "achievement" then
            caerdonType = CaerdonItemType.Unhandled
		elseif linkType == "journal" then
            caerdonType = CaerdonItemType.Unhandled
        elseif linkType == "keystone" then
            caerdonType = CaerdonItemType.Unhandled
		elseif linkType == "spell" then
            caerdonType = CaerdonItemType.Unhandled
        else
            print("Caerdon: Unknown type " .. tostring(typeID) .. ", " .. tostring(linkType) .. " (unknown): " .. itemLink)
        end

        self.caerdonItemType = caerdonType
    end

    return self.caerdonItemType
end

function CaerdonItemMixin:GetTooltipData(data)
	if not data then
		data = C_TooltipInfo and C_TooltipInfo.GetHyperlink(self:GetItemLink()) or nil
	end

	if not data then return {} end

	local bindTextTable = {
		[ITEM_ACCOUNTBOUND]        = L["BoA"],
		[ITEM_BNETACCOUNTBOUND]    = L["BoA"],
		[ITEM_BIND_TO_ACCOUNT]     = L["BoA"],
		[ITEM_BIND_TO_BNETACCOUNT] = L["BoA"]
		-- [ITEM_BIND_ON_EQUIP]       = L["BoE"],
		-- [ITEM_BIND_ON_USE]         = L["BoE"]
	}

	local tooltipData = {
		canLearn = false,
		canCombine = false,
		hasEquipEffect = false,
		isRelearn = false,
		bindingStatus = nil,
		isRetrieving = false,
		isSoulbound = false,
		isKnownSpell = false,
		isLocked = false,
		isOpenable = false,
		supercedingSpellNotKnown = false,
		foundRedRequirements = false,
		requiredTradeSkillMissingOrUnleveled = false,
		requiredTradeSkillTooLow = false,
		embeddedLink = data.hyperlink
	}

	-- TODO: Hack to handle Pet Cage - need to move down into BattlePetMixin and get CaerdonItem to handle it upfront if needed.
	local isBattlePet = self:GetCaerdonItemType() == CaerdonItemType.BattlePet
	if isBattlePet then
		if data.battlePetSpeciesID then
	    -- local item = CaerdonItem:CreateFromSpeciesInfo(data.battlePetSpeciesID, data.battlePetLevel, data.battlePetBreedQuality, data.battlePetMaxHealth, data.battlePetPower, data.battlePetSpeed, data.battlePetName, battlePetID)
			local numCollected = C_PetJournal.GetNumCollectedInfo(data.battlePetSpeciesID)
			if numCollected == 0 then
					tooltipData.canLearn = true
			end
		end
	end

	local itemSpellName, itemSpellID = C_Item.GetItemSpell(self:GetItemLink())
	local isStudyItem = itemSpellName == L["Studying"] -- A bunch of these so working off name for now: itemSpellID == 450824 or itemSpellID == 462909 --Spell: "Studying"
	local isRecipe = self:GetCaerdonItemType() == CaerdonItemType.Recipe
	local isMiscellaneousStudy = self:GetCaerdonItemType() == CaerdonItemType.Miscellaneous and isStudyItem
	local lines = data.lines or {}

	for lineIndex, line in ipairs(data.lines) do
		local lineText = line.leftText
		if line.type == Enum.TooltipDataLineType.None or
			line.type == Enum.TooltipDataLineType.ItemEnchantmentPermanent or
				line.type == Enum.TooltipDataLineType.ItemBinding then
			if lineText then
				-- TODO: Find a way to identify Equip Effects without tooltip scanning
				if strmatch(lineText, ITEM_SPELL_TRIGGER_ONEQUIP) then -- it has an equip effect
					tooltipData.hasEquipEffect = true
				end

				-- NOTE: I had removed the check for isRecipe for some reason... but then things like Reaves would get flagged as canLearn.
				-- Keep an eye out and figure out what to do if needed
				if isRecipe or isMiscellaneousStudy then
					-- TODO: Don't like matching this hard-coded string but not sure how else
					-- to prevent the expensive books from showing as learnable when I don't
					-- know how to tell if they have recipes you need.
					if strmatch(lineText, L["Use: Re%-learn .*"]) then
						tooltipData.isRelearn = true
					end

					-- TODO: Not tagging a few items like this - GetItemSpell returns nil
					-- if self:GetItemID() == 224423 then
					-- 	DevTools_Dump(data)
					-- end
				
					if data.hyperlink and C_Item.GetItemInfoInstant(data.hyperlink) ~= self:GetItemID() then -- Skip self-referential items for now
						local spellName, spellID = C_Item.GetItemSpell(data.hyperlink)
						if spellID then
								-- local isUsable = C_Spell.IsSpellUsable(spellID)
								-- print(tostring(spellName) .. tostring(spellID) .. self:GetItemLink())
								local recipeInfo = C_TradeSkillUI.GetRecipeInfo(spellID)
								if recipeInfo.learned then
									tooltipData.canLearn = false
									-- print(self:GetItemLink() .. " already learned")
								else
									tooltipData.canLearn = true
									-- print("Can learn " .. self:GetItemLink() .. " creates " .. data.hyperlink)
								end
						-- TODO: Likely don't need this now that profession data load is handled upfront.
						-- else
						-- 	-- TODO: Assume it's learnable for the moment since some items don't give the data
						-- 	tooltipData.canLearn = true
						end
					end
				end

				-- TODO: Keeping for a bit but I have this handled at my overrides at the end that check usable spells from items
				-- if (self:GetCaerdonItemType() == CaerdonItemType.Consumable or self:GetCaerdonItemType() == CaerdonItemType.Quest) and self:HasItemLocation() then
				-- 	local location = self:GetItemLocation()
				-- 	local maxStackCount = C_Item.GetItemMaxStackSize(location)
				-- 	local currentStackCount = C_Item.GetStackCount(location)
			
				-- 	local combineCount = tonumber((strmatch(lineText, L["Use: Combine (%d+)"]) or 0))
				-- 	if combineCount > 1 then
				-- 		tooltipData.canCombine = true
				-- 		if combineCount <= currentStackCount then
				-- 			tooltipData.readyToCombine = true
				-- 		end
				-- 	end
				-- end

				if not tooltipData.bindingStatus then
					-- Check binding status - TODO: Is there a non-scan way?
					tooltipData.bindingStatus = bindTextTable[lineText]
				end

				if strmatch(lineText, L["Use: .* ([%d,]+) reputation"]) then
						if CaerdonWardrobeConfig.Binding.ShowBoARepItems then
							tooltipData.canLearn = true
						end
					elseif strmatch(lineText, L["Use: Marks your map with the location"]) then
						tooltipData.canLearn = true
					elseif strmatch(lineText, L["Use: Unlocks this customization"]) then
						tooltipData.canLearn = true
					-- TODO: Review - removed because I think this is handled by recipe management
					-- elseif strmatch(lineText, L["Use: Study to increase your"]) then
					-- 	tooltipData.canLearn = true
					elseif lineText == RETRIEVING_ITEM_INFO then
						tooltipData.isRetrieving = true
						break
					elseif lineText == ITEM_SOULBOUND then
						tooltipData.isSoulbound = true
					elseif lineText == ITEM_SPELL_KNOWN then
						tooltipData.isKnownSpell = true
					elseif lineText == LOCKED then
						tooltipData.isLocked = true
					elseif lineText == ITEM_OPENABLE then
						tooltipData.isOpenable = true
					elseif lineText == TOOLTIP_SUPERCEDING_SPELL_NOT_KNOWN then
						tooltipData.supercedingSpellNotKnown = true
					end
				end

				local hex = line.leftColor:GenerateHexColor()
				-- TODO: Generated hex color includes alpha value so need to check for full red.
				-- TODO: Provide option to show stars on BoE recipes that aren't for current toon
				-- TODO: Surely there's a better way than checking hard-coded color values for red-like things
				-- if hex == "fe1f1f" then -- TODO: this was old value... check to see if still needed for anything
				if hex == "ffff2020" then
					tooltipData.foundRedRequirements = true
				end
		elseif line.type == Enum.TooltipDataLineType.Blank then
		elseif line.type == Enum.TooltipDataLineType.UnitName then
		elseif line.type == Enum.TooltipDataLineType.GemSocket then
		elseif line.type == Enum.TooltipDataLineType.AzeriteEssenceSlot then
		elseif line.type == Enum.TooltipDataLineType.AzeriteEssencePower then
		-- elseif line.type == Enum.TooltipDataLineType.LearnableSpell then
		elseif line.type == Enum.TooltipDataLineType.UnitThreat then
		elseif line.type == Enum.TooltipDataLineType.QuestObjective then
		elseif line.type == Enum.TooltipDataLineType.AzeriteItemPowerDescription then
		elseif line.type == Enum.TooltipDataLineType.RuneforgeLegendaryPowerDescription then
		elseif line.type == Enum.TooltipDataLineType.SellPrice then
		elseif line.type == Enum.TooltipDataLineType.ProfessionCraftingQuality then
		elseif line.type == Enum.TooltipDataLineType.SpellName then
		elseif line.type == Enum.TooltipDataLineType.CurrencyTotal then
		elseif line.type == Enum.TooltipDataLineType.ItemEnchantmentPermanent then
		elseif line.type == Enum.TooltipDataLineType.UnitOwner then
		elseif line.type == Enum.TooltipDataLineType.QuestTitle then
		elseif line.type == Enum.TooltipDataLineType.QuestPlayer then
		elseif line.type == Enum.TooltipDataLineType.NestedBlock then
		elseif line.type == Enum.TooltipDataLineType.RestrictedRaceClass then
		elseif line.type == Enum.TooltipDataLineType.RestrictedFaction then
		elseif line.type == Enum.TooltipDataLineType.RestrictedSkill then
			if isRecipe or isMiscellaneousStudy then
				-- TODO: Some day - look into saving toon skill lines / ranks into a DB and showing
				-- which toons could learn a recipe.
				local replaceSkill = "%w"
				
				-- Remove 1$ and 2$ from ITEM_MIN_SKILL for German at least (probably all): Benötigt %1$s (%2$d)
				local skillCheck = string.gsub(ITEM_MIN_SKILL, "1%$", "")
				skillCheck = string.gsub(skillCheck, "2%$", "")
				skillCheck = string.gsub(skillCheck, "%%s", "%(.+%)")
				if GetLocale() == "zhCN" then
					skillCheck = string.gsub(skillCheck, "（%%d）", "（%(%%d+%)）")
				else
					skillCheck = string.gsub(skillCheck, "%(%%d%)", "%%%(%(%%d+%)%%%)")
				end

				if strmatch(lineText, skillCheck) then
					local _, _, requiredSkill, requiredRank = string.find(lineText, skillCheck)

					local hasSkillLine, meetsMinRank, rank, maxRank = CaerdonRecipe:GetPlayerSkillInfo(requiredSkill, requiredRank)
					-- print(self:GetItemLink() .. "hasSkillLine: " .. tostring(hasSkillLine) .. ", meetsMinRank: " .. tostring(meetsMinRank))

					tooltipData.requiredTradeSkillMissingOrUnleveled = not hasSkillLine
					tooltipData.requiredTradeSkillTooLow = hasSkillLine and not meetsMinRank
					tooltipData.canLearn = hasSkillLine

					-- if not hasSkillLine then -- or rank == maxRank then -- TODO: Not sure why I was checking maxRank here...
					-- 	-- tooltipData.canLearn = false -- TODO: Confirm if I need to do this - GetRecipeInfo appears to be returning nil for unknown recipes?
					-- 	local prof1, prof2, archaeology, fishing, cooking, firstAid = GetProfessions()

					-- 	local _, _, _, _, _, _, itemSubType = C_Item.GetItemInfo(self:GetItemLink())
					-- 	local professionName = itemSubType

					-- 	local prof
					-- 	-- Get information about each profession the player has
					-- 	local profList = {prof1, prof2, archaeology, fishing, cooking, firstAid}
					-- 	for _, prof in ipairs(profList) do
					-- 			if prof then
					-- 					local name, _, rank, _, _, _, skillLine = GetProfessionInfo(prof)
					-- 					if name == professionName then
					-- 						tooltipData.requiredTradeSkillMissingOrUnleveled = false
					-- 					end
					-- 			end
					-- 	end
										
					-- 	-- local spellName, spellID = C_Item.GetItemSpell(data.hyperlink)
					-- 	-- if spellID then
					-- 	-- 	-- local isUsable = C_Spell.IsSpellUsable(spellID)
					-- 	-- 	-- print(tostring(spellName) .. tostring(spellID) .. self:GetItemLink())
					-- 	-- 	local recipeInfo = C_TradeSkillUI.GetRecipeInfo(spellID)
					-- 	-- 	if recipeInfo then
					-- 	-- 		tooltipData.requiredTradeSkillMissingOrUnleveled = false -- TODO: Verify - seemed to not retrieve if missing skill
					-- 	-- 	end
					-- 	-- 	-- DevTools_Dump(recipeInfo)
					-- 	-- end

					-- else
					-- 	tooltipData.canLearn = true
					-- end
				end		
			end
		elseif line.type == Enum.TooltipDataLineType.RestrictedPvPMedal then
		elseif line.type == Enum.TooltipDataLineType.RestrictedReputation then
		elseif line.type == Enum.TooltipDataLineType.RestrictedSpellKnown then
			tooltipData.canLearn = false
			tooltipData.isKnownSpell = true
		elseif line.type == Enum.TooltipDataLineType.RestrictedLevel then
		elseif line.type == Enum.TooltipDataLineType.EquipSlot then
		elseif line.type == Enum.TooltipDataLineType.ItemName then
		else
			if CaerdonWardrobeConfig.Debug.Enabled then
				print("Caerdon: TOOLTIP PROCESSING NEEDED: " .. self:GetItemLink() .. ", type: " .. tostring(line.type))
				-- DevTools_Dump(line)
			end
		end
	end

	-- if self:GetItemID() == 224418 then
	-- 	DevTools_Dump(tooltipData)
	-- end
	-- DevTools_Dump(tooltipData)
	return tooltipData
end


-- { Name = "None", Type = "TooltipDataLineType", EnumValue = 0 },
-- { Name = "Blank", Type = "TooltipDataLineType", EnumValue = 1 },
-- { Name = "UnitName", Type = "TooltipDataLineType", EnumValue = 2 },
-- { Name = "GemSocket", Type = "TooltipDataLineType", EnumValue = 3 },
-- { Name = "AzeriteEssenceSlot", Type = "TooltipDataLineType", EnumValue = 4 },
-- { Name = "AzeriteEssencePower", Type = "TooltipDataLineType", EnumValue = 5 },
-- { Name = "LearnableSpell", Type = "TooltipDataLineType", EnumValue = 6 },
-- { Name = "UnitThreat", Type = "TooltipDataLineType", EnumValue = 7 },
-- { Name = "QuestObjective", Type = "TooltipDataLineType", EnumValue = 8 },
-- { Name = "AzeriteItemPowerDescription", Type = "TooltipDataLineType", EnumValue = 9 },
-- { Name = "RuneforgeLegendaryPowerDescription", Type = "TooltipDataLineType", EnumValue = 10 },
-- { Name = "SellPrice", Type = "TooltipDataLineType", EnumValue = 11 },
-- { Name = "ProfessionCraftingQuality", Type = "TooltipDataLineType", EnumValue = 12 },
-- { Name = "SpellName", Type = "TooltipDataLineType", EnumValue = 13 },
-- { Name = "CurrencyTotal", Type = "TooltipDataLineType", EnumValue = 14 },
-- { Name = "ItemEnchantmentPermanent", Type = "TooltipDataLineType", EnumValue = 15 },
-- { Name = "UnitOwner", Type = "TooltipDataLineType", EnumValue = 16 },
-- { Name = "QuestTitle", Type = "TooltipDataLineType", EnumValue = 17 },
-- { Name = "QuestPlayer", Type = "TooltipDataLineType", EnumValue = 18 },
-- { Name = "NestedBlock", Type = "TooltipDataLineType", EnumValue = 19 },
-- { Name = "ItemBinding", Type = "TooltipDataLineType", EnumValue = 20 },

function CaerdonItemMixin:IsSellable()
    local itemID = self:GetItemID()
	local isSellable = itemID ~= nil
	if itemID == 23192 then -- Tabard of the Scarlet Crusade needs to be worn for a vendor at Darkmoon Faire
		isSellable = false
	elseif itemID == 116916 then -- Gorepetal's Gentle Grasp allows faster herbalism in Draenor
		isSellable = false
	end
	return isSellable
end

function CaerdonItemMixin:IsCollectible()
	local caerdonType = self:GetCaerdonItemType()
	return caerdonType == CaerdonItemType.BattlePet or
		caerdonType == CaerdonItemType.CompanionPet or
		caerdonType == CaerdonItemType.Mount or
		caerdonType == CaerdonItemType.Recipe or
		caerdonType == CaerdonItemType.Toy
end

function CaerdonItemMixin:GetBindingStatus(tooltipData)
	local itemID = self:GetItemID()
	local itemLink = self:GetItemLink()
	local itemData = self:GetItemData()
	local caerdonType = self:GetCaerdonItemType()

	local bindingStatus
	local needsItem = true
	local hasEquipEffect = false

	local isBindOnPickup = false
	local isBindOnUse = false
	local unusableItem = false
	local skillTooLow = false
	local foundRedRequirements = false
	local isLocked = false
	local isOpenable = false
	
	local isCollectionItem = self:IsCollectible()

	local itemName, itemLinkInfo, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
	itemEquipLoc, iconFileDataID, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID, 
	isCraftingReagent = C_Item.GetItemInfo(itemLink)

	local binding = self:GetBinding()

	if binding == CaerdonItemBind.None then
		bindingStatus = ""
	elseif binding == CaerdonItemBind.BindOnPickup then
		isBindOnPickup = true
	elseif binding == CaerdonItemBind.BindOnEquip then
		bindingStatus = L["BoE"]
	elseif binding == CaerdonItemBind.WarboundUntilEquip then
		bindingStatus = L["WuE"]
	elseif binding == CaerdonItemBind.BindOnUse then
		isBindOnUse = true
		bindingStatus = L["BoE"]
	elseif binding == CaerdonItemBind.QuestItem then
		bindingStatus = ""
	elseif binding == CaerdonItemBind.BindOnAccount then
		bindingStatus = L["BoA"]
	end

	if self:IsSoulbound() then
		isBindOnPickup = true
		bindingStatus = nil
	end

	if tooltipData then
		hasEquipEffect = tooltipData.hasEquipEffect

		if tooltipData.isRelearn then
			needsItem = false
		end

		if not bindingStatus then
			bindingStatus = tooltipData.bindingStatus
		end

		if caerdonType ~= CaerdonItemType.Recipe then -- ignore red on recipes for now... should be handling correctly through the recipe checks
			if tooltipData.foundRedRequirements then -- TODO: See about getting rid of this eventually and having specific checks (if possible)
				unusableItem = true
				if caerdonType ~= CaerdonItemType.Recipe then
					skillTooLow = true
				end
			end
		end

		if tooltipData.isKnownSpell then
			needsItem = false
			unusableItem = true
			skillTooLow = false
		end

		isLocked = tooltipData.isLocked
		isOpenable = tooltipData.isOpenable

		if tooltipData.supercedingSpellNotKnown then
			unusableItem = true
			skillTooLow = true
		end

		if tooltipData.requiredTradeSkillMissingOrUnleveled then
			unusableItem = true
			-- if isBindOnPickup then -- assume all unknown not needed for now
				needsItem = false
			-- end
		else
			if tooltipData.requiredTradeSkillTooLow then
				unusableItem = true
				skillTooLow = true
				needsItem = true -- still need this but need to rank up
			else
				needsItem = true
			end
		end
	end

	if not bindingStatus and (isCollectionItem or isLocked or isOpenable) then
		-- TODO: This can be useful on everything but needs to be configurable per type before doing so
		if not isBindOnPickup then
			bindingStatus = L["BoE"]
		end
	end

	if caerdonType == CaerdonItemType.Conduit then
		local conduitInfo = itemData:GetConduitInfo()
		needsItem = conduitInfo.needsItem
	elseif caerdonType == CaerdonItemType.CompanionPet or caerdonType == CaerdonItemType.BattlePet then
		local petInfo = 
			(caerdonType == CaerdonItemType.CompanionPet and itemData:GetCompanionPetInfo()) or
			(caerdonType == CaerdonItemType.BattlePet and itemData:GetBattlePetInfo())
		needsItem = petInfo.needsItem
	elseif caerdonType == CaerdonItemType.Recipe then
		local recipeInfo = itemData:GetRecipeInfo()
		if recipeInfo and recipeInfo.learned then -- TODO: This still ends up flagging a few of the weird self-referential ones that aren't learned... look into later.
			needsItem = false
		elseif tooltipData.canLearn then
			needsItem = true
		else
			needsItem = false
		end
	end

	-- Haven't seen a reason for this, yet, and should be handled in each type
	-- if isCollectionItem and unusableItem then
	-- 	if not isRecipe then
	-- 		needsItem = false
	-- 	end
	-- end

	return { 
		bindingStatus = bindingStatus, 
		needsItem = needsItem, 
		hasEquipEffect = hasEquipEffect,
		isBindOnPickup = isBindOnPickup, 
		unusableItem = unusableItem, 
		isLocked = isLocked, 
		skillTooLow = skillTooLow
	}
end

function CaerdonItemMixin:GetCaerdonStatus(feature, locationInfo) -- TODO: Need to remove feature/locationInfo but keeping it for now in case refactor to GetHyperlink causes any issues - also need to remove the GetTooltipData calls
	local itemLink = self:GetItemLink()
	if not itemLink then
		-- Requiring an itemLink for now unless I find a reason not to
		return
	end


	local data = nil
	if self:GetItemName() == L["Pet Cage"] then
		-- Was hoping to just use the item link but battlepets in particular cause issues showing up as Pet Cage.
		-- Could check CaerdonItemType for BattlePet, but just going to do this for now.
		data = C_TooltipInfo and feature and feature:GetTooltipData(self, locationInfo) or nil
	end

	local tooltipData = self:GetTooltipData(data)

	if tooltipData and tooltipData.isRetrieving then -- Tooltip data isn't loaded yet....
		isReady = false
		return isReady
	end

	local itemID = self:GetItemID()
	local caerdonType = self:GetCaerdonItemType()
	local itemData = self:GetItemData()
	local itemLocation = self:GetItemLocation()

	local bindingResult = self:GetBindingStatus(tooltipData)
	local bindingStatus = bindingResult.bindingStatus

	local itemName, itemLinkInfo, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
	itemEquipLoc, iconFileDataID, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID, 
	isCraftingReagent = C_Item.GetItemInfo(itemLink)

	local playerLevel = UnitLevel("player")

	local mogStatus = ""
	local isReady = true

	if not self:IsCollectible() and caerdonType ~= CaerdonItemType.Conduit and caerdonType ~= CaerdonItemType.Equipment then
		local expansionID = expacID
		if expansionID and expansionID >= 0 and expansionID < GetExpansionLevel() then 
			local shouldShowExpansion = false

			if expansionID > 0 or CaerdonWardrobeConfig.Icon.ShowOldExpansion.Unknown then
				if isCraftingReagent and CaerdonWardrobeConfig.Icon.ShowOldExpansion.Reagents then
					shouldShowExpansion = true
				elseif self:GetHasUse() and CaerdonWardrobeConfig.Icon.ShowOldExpansion.Usable then
					shouldShowExpansion = true
				elseif not isCraftingReagent and not self:GetHasUse() and CaerdonWardrobeConfig.Icon.ShowOldExpansion.Other then
					shouldShowExpansion = true
				end
			end

			if shouldShowExpansion then
				mogStatus = "oldexpansion"
			end
		end
	end

	local isQuestItem = itemClassID == Enum.ItemClass.Questitem
	if isQuestItem and CaerdonWardrobeConfig.Icon.ShowQuestItems then
		mogStatus = "quest"
	end

	if caerdonType == CaerdonItemType.CompanionPet or caerdonType == CaerdonItemType.BattlePet then
		local petInfo = 
			(caerdonType == CaerdonItemType.CompanionPet and itemData:GetCompanionPetInfo()) or
			(caerdonType == CaerdonItemType.BattlePet and itemData:GetBattlePetInfo())
		if petInfo.needsItem or tooltipData.canLearn then
			if bindingResult.unusableItem then
				mogStatus = "other"
			else
				mogStatus = "own"
			end
		end
	elseif caerdonType == CaerdonItemType.Conduit then
		if bindingResult.needsItem then
			local conduitInfo = itemData:GetConduitInfo()
			if conduitInfo.isUpgrade then
				mogStatus = "upgradeNonEquipment"
			else
				mogStatus = "own"
			end
		elseif tooltipData.canLearn then
			if bindingResult.skillTooLow then
				mogStatus = "lowSkill"
			else
				mogStatus = "own"
			end
		end
	elseif caerdonType == CaerdonItemType.Consumable then
		local consumableInfo = itemData:GetConsumableInfo()
		if consumableInfo.needsItem then
			if consumableInfo.validForCharacter then
				mogStatus = "own"
			else
				mogStatus = "other"
			end
		elseif tooltipData.canCombine then
			mogStatus = "canCombine"
			if tooltipData.readyToCombine then
				mogStatus = "readyToCombine"
			end
			-- TODO: Keep an eye on this - should be able to incorporate info GetConsumableInfo as needed
		-- elseif tooltipData.canLearn then
		-- 	if bindingResult.skillTooLow then
		-- 		mogStatus = "lowSkill"
		-- 	else
		-- 		mogStatus = "own"
		-- 	end
		else
			mogStatus = "collected"
		end
	elseif caerdonType == CaerdonItemType.Currency then
		local currencyInfo = itemData:GetCurrencyInfo()
		if currencyInfo.needsItem then
			mogStatus = "own"
		elseif currencyInfo.otherNeedsItem then
			mogStatus = "other"
		end
	elseif caerdonType == CaerdonItemType.Equipment then
		local transmogInfo = itemData:GetTransmogInfo()
		if transmogInfo then
			if transmogInfo.isTransmog then
				if transmogInfo.needsItem then
					if not transmogInfo.isCompletionistItem then
						if transmogInfo.hasMetRequirements and not tooltipData.foundRedRequirements then
							mogStatus = "own"
						else
							mogStatus = "lowSkill"
						end
					else
						if CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem then
							if transmogInfo.hasMetRequirements and not tooltipData.foundRedRequirements then
								mogStatus = "ownPlus"
							else
								mogStatus = "lowSkillPlus"
							end
						end
					end
				elseif transmogInfo.otherNeedsItem then
					if not bindingResult.isBindOnPickup then
						if not transmogInfo.isCompletionistItem then
							mogStatus = "other"
						else
							if CaerdonWardrobeConfig.Icon.ShowLearnable.SameLookDifferentItem then
								mogStatus = "otherPlus"
							end
						end
					else
						mogStatus = "collected"
					end
				elseif transmogInfo.isUpgrade then
					if transmogInfo.hasMetRequirements then
						mogStatus = "upgrade"
					else
						mogStatus = "upgradeLowSkill"
					end
				else
					-- if transmogInfo.hasMetRequirements then
						mogStatus = "collected"
					-- Don't mark as lowSkill for equipment if it's known but not the right level... too much noise
					-- else
					-- 	mogStatus = "lowSkill"
					-- end
				end
			elseif transmogInfo.isUpgrade then
				if transmogInfo.hasMetRequirements then
					mogStatus = "upgrade"
				else
					mogStatus = "upgradeLowSkill"
				end
			else
				if not transmogInfo.hasMetRequirements then
					mogStatus = "lowSkill"
				else
					mogStatus = "collected"
				end
			end

			local equipmentSets = itemData:GetEquipmentSets()
			if equipmentSets then
					if #equipmentSets > 1 then
							bindingStatus = "*" .. equipmentSets[1]
					else
							bindingStatus = equipmentSets[1]
					end
			else
					if mogStatus == "collected" and 
							self:IsSellable() and 
							not self:GetHasUse() and
							not self:GetSetID() and
							not bindingResult.hasEquipEffect then
									mogStatus = "sellable"
					end
			end
		end
	elseif caerdonType == CaerdonItemType.Mount then
		local mountInfo = itemData:GetMountInfo()
		if mountInfo.needsItem then
			local factionGroup = nil
			local playerFactionGroup = nil
			if mountInfo.isFactionSpecific then
				factionGroup = PLAYER_FACTION_GROUP[mountInfo.factionID]
				playerFactionGroup = UnitFactionGroup("player")
			end

			if (not itemMinLevel or playerLevel >= itemMinLevel) and (factionGroup == playerFactionGroup) then
				mogStatus = "own"
			else
				mogStatus = "other"
			end
		end
	elseif caerdonType == CaerdonItemType.Profession then
		local professionInfo = itemData:GetProfessionInfo()
		if professionInfo.needsItem then
			mogStatus = "needForProfession"
		end
	elseif caerdonType == CaerdonItemType.Quest then
		if tooltipData.canCombine then
			mogStatus = "canCombine"
			if tooltipData.readyToCombine then
				mogStatus = "readyToCombine"
			end
		end
	elseif caerdonType == CaerdonItemType.Recipe then
		if tooltipData.canCombine then
			mogStatus = "canCombine"
			if tooltipData.readyToCombine then
				mogStatus = "readyToCombine"
			end
		elseif bindingResult.needsItem then
			if bindingResult.unusableItem then
				if bindingResult.skillTooLow then
					mogStatus = "lowSkill"
				end
				-- Don't show these for now
				-- mogStatus = "other"
			else
				mogStatus = "own"
			end

			-- Let's just ignore the Librams for now until I decide what to do about them
			if itemID == 11732 or 
			   itemID == 11733 or
			   itemID == 11734 or 
			   itemID == 11736 or 
			   itemID == 11737 or
			   itemID == 18332 or
			   itemID == 18333 or
			   itemID == 18334 or
			   itemID == 21288 then
				if CaerdonWardrobeConfig.Icon.ShowOldExpansion.Usable then
					mogStatus = "oldexpansion"
				else
					mogStatus = nil
				end
			end
		-- else
		-- 	local recipeInfo = itemData:GetRecipeInfo()

		-- 	if tooltipData.canLearn then
		-- 		if bindingResult.skillTooLow then
		-- 			mogStatus = "lowSkill"
		-- 		else
		-- 			mogStatus = "own"
		-- 		end
		-- 	end
		else
			mogStatus = "collected"
		end
	elseif caerdonType == CaerdonItemType.Toy then
		local toyInfo = itemData:GetToyInfo()
		if toyInfo.needsItem then
			mogStatus = "own"
		else
			mogStatus = "sellable"
		end
	elseif tooltipData and tooltipData.canLearn then
		if bindingResult.skillTooLow then
			mogStatus = "lowSkill"
		else
			mogStatus = "own"
		end
	end

	if self:HasItemLocationBankOrBags() then
		local bag, slot = itemLocation:GetBagAndSlot()
		
		local containerID = bag
		local containerSlot = slot

		local texture, itemCount, locked, quality, readable, lootable
		if C_Container and C_Container.GetContainerItemInfo then
			local containerItemInfo = C_Container.GetContainerItemInfo(containerID, containerSlot)
			if containerItemInfo then
				itemCount = containerItemInfo.stackCount
				locked = containerItemInfo.isLocked
				quality = containerItemInfo.quality
				readable = containerItemInfo.isReadable
				lootable = containerItemInfo.hasLoot
			end
		else 
			texture, itemCount, locked, quality, readable, lootable, _ = GetContainerItemInfo(containerID, containerSlot)
		end

		if lootable then
			local startTime, duration, isEnabled
			if C_Container and C_Container.GetContainerItemCooldown then
				startTime, duration, isEnabled = C_Container.GetContainerItemCooldown(containerID, containerSlot)
			else
				startTime, duration, isEnabled = GetContainerItemCooldown(containerID, containerSlot)
			end
			if duration > 0 and not isEnabled then
				mogStatus = "refundable" -- Can't open yet... show timer
			else
				if bindingResult.isLocked then
					mogStatus = "locked"
				else
					mogStatus = "openable"
				end
			end
		elseif readable then
			mogStatus = "readable"
		else
			local isEquipped = false
			local money, itemCount, refundSec, currencyCount, hasEnchants
			if C_Container and C_Container.GetContainerItemPurchaseInfo then
				local info = C_Container.GetContainerItemPurchaseInfo(bag, slot, isEquipped)
				money = info and info.money
				itemCount = info and info.itemCount
				refundSec = info and info.refundSeconds
				currencyCount = info and info.currencyCount
				hasEnchants = info and info.hasEnchants
			else
				money, itemCount, refundSec, currencyCount, hasEnchants = GetContainerItemPurchaseInfo(bag, slot, isEquipped)
			end
			if refundSec then
				mogStatus = "refundable"
			end
		end
	end

	-- TODO: C_Item.GetItemLearnTransmogSet

	local spellName, spellID = C_Item.GetItemSpell(self:GetItemLink())
	if spellID then
		local spellDescription
		spellDescription = C_Spell.GetSpellDescription(spellID) or ""
		-- local isCollectDescription = string.find(spellDescription, L["^Collect .* appearances.*"]) ~= nil
		local isCombineDescription = string.find(spellDescription, L["^Combine"]) ~= nil
		local isArrangeDescription = string.find(spellDescription, L["^Arrange %d+"]) ~= nil
		local CheckUsable = C_Spell and C_Spell.IsSpellUsable or IsUsableSpell
		-- if isCollectDescription and CheckUsable(spellID) then
		-- 	mogStatus = "own"
		-- elseif
		if self:HasItemLocationBankOrBags() then
			if (spellID == 433080 or spellID == 439058) then -- Breaking Down / Attuning Stone Wing (if in bags)
				-- TODO: Better to figure out a way to identify spells that create currency if possible
				mogStatus = "own"
			elseif isCombineDescription or isArrangeDescription then -- and mogStatus == "" then
				if CheckUsable(spellID) then
					local maxStackCount = C_Item.GetItemMaxStackSize(itemLocation)
					local currentStackCount = C_Item.GetStackCount(itemLocation)
			
					local combineCount = tonumber((strmatch(spellDescription, L["Combine (%d+)"]) or strmatch(spellDescription, L["Arrange (%d+)"]) or 0))
					if combineCount > 1 then
						mogStatus = "canCombine"
						if combineCount <= currentStackCount then
							mogStatus = "readyToCombine"
						end
					else
						mogStatus = "readyToCombine"
					end
				else
					mogStatus = "canCombine"
				end
			end
		end
	end

	return isReady, mogStatus, bindingStatus, bindingResult
end

function CaerdonItemMixin:GetItemData()
    if not self.caerdonItemData then
        local caerdonType = self:GetCaerdonItemType()

        if caerdonType == CaerdonItemType.BattlePet then
            self.caerdonItemData = CaerdonBattlePet:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.CompanionPet then
						self.caerdonItemData = CaerdonCompanionPet:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Conduit then
						self.caerdonItemData = CaerdonConduit:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Consumable then
						self.caerdonItemData = CaerdonConsumable:CreateFromCaerdonItem(self)
				elseif caerdonType == CaerdonItemType.Currency then
						self.caerdonItemData = CaerdonCurrency:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Equipment then
            self.caerdonItemData = CaerdonEquipment:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Mount then
            self.caerdonItemData = CaerdonMount:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Profession then
            self.caerdonItemData = CaerdonProfession:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Quest then
            self.caerdonItemData = CaerdonQuest:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Recipe then
            self.caerdonItemData = CaerdonRecipe:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Toy then
            self.caerdonItemData = CaerdonToy:CreateFromCaerdonItem(self)
        end
    end
    
    return self.caerdonItemData
end

function CaerdonItemMixin:GetForDebugUse()
    if self:GetItemLink() then
        local linkType, linkOptions, displayText = LinkUtil.ExtractLink(self:GetItemLink())
        local forDebugUse = CaerdonWardrobeConfig.Debug.Enabled and {
            linkType = linkType,
            linkOptions = linkOptions,
            linkDisplayText = displayText
        }

        return forDebugUse
    end
end
