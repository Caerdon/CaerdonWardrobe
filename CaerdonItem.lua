CaerdonItem = {}
CaerdonItemMixin = {}

-- Should not be translated - used to provide me with screenshots for debugging.
CaerdonItemType = {
    Empty = "Empty",
    Unknown = "Unknown",
    Unhandled = "Unhandled",
    BattlePet = "Battle Pet", -- pets that have been caged
    CompanionPet = "Companion Pet", -- unlearned pets
    Consumable = "Consumable",
    Equipment = "Equipment",
    Mount = "Mount",
    Recipe = "Recipe",
    Quest = "Quest",
    Toy = "Toy"
}

CaerdonItemBind = {
    None = "None",
    BindOnPickup = "Bind on Pickup",
    BindOnEquip = "Bind on Equip",
    BindOnUse = "Bind on Use",
    QuestItem = "Quest Item",
	Unknown = "Unknown",
}

local function CreateItem()
    return CreateFromMixins(
        ItemMixin,
        CaerdonItemMixin
    )
end

--[[static]] function CaerdonItem:CreateFromItemLink(itemLink)
	if type(itemLink) ~= "string" then
		error("Usage: CaerdonItem:CreateFromItemLink(itemLinkString)", 2);
	end

    local item = CreateItem()
    item:SetItemLink(itemLink)    
	return item;
end

--[[static]] function CaerdonItem:CreateFromItemID(itemID)
	if type(itemID) ~= "number" then
		error("Usage: CaerdonItem:CreateFromItemID(itemID)", 2);
    end
    
    local item = CreateItem()
    item:SetItemID(itemID)
    return item;
end

--[[static]] function CaerdonItem:CreateFromSpeciesInfo(speciesID, level, quality, health, power, speed, name, petID)
    -- TODO: This is a terrible hack until Blizzard gives me more to work with (mostly for tooltips where I don't have an itemLink).
	if type(speciesID) ~= "number" then
		error("Usage: CaerdonItem:CreateFromSpeciesInfo(speciesID, level, quality, health, power, speed, customName)", 2);
	end

    local battlePetDisplayID = nil -- Can we get it?

    local itemLink = format("|cff0070dd|Hbattlepet:%d:%d:%d:%d:%d:%d:%x:%d|h[%s]|h|r", speciesID, level, quality, health, power, speed, petID, battlePetDisplayID, name)
    return CaerdonItem:CreateFromItemLink(itemLink)
end

function CaerdonItemMixin:Clear()
    ItemMixin.Clear(self)
    self.caerdonItemType = nil
    self.caerdonItemData = nil
end

-- Add a callback to be executed when item data is loaded, if the item data is already loaded then execute it immediately
function CaerdonItemMixin:ContinueOnItemLoad(callbackFunction)
    if type(callbackFunction) ~= "function" or self:IsItemEmpty() then
        error("Usage: NonEmptyItem:ContinueOnLoad(callbackFunction)", 2);
    end

    ItemEventListener:AddCallback(self:GetItemID(), function ()
        -- TODO: Update things and delay callback if needed for tooltip data
        callbackFunction()
    end);
end

-- Same as ContinueOnItemLoad, except it returns a function that when called will cancel the continue
function CaerdonItemMixin:ContinueWithCancelOnItemLoad(callbackFunction)
    if type(callbackFunction) ~= "function" or self:IsItemEmpty() then
        error("Usage: NonEmptyItem:ContinueWithCancelOnItemLoad(callbackFunction)", 2);
    end

    return ItemEventListener:AddCancelableCallback(self:GetItemID(), function ()
        -- TODO: Update things and delay callback if needed for tooltip data
        callbackFunction()
    end);
end

function CaerdonItemMixin:SetItemLink(itemLink)
    ItemMixin.SetItemLink(self, itemLink)
end

function CaerdonItemMixin:SetItemID(itemID)
    -- Used for embedded item tooltip rewards
    ItemMixin.SetItemID(self, itemID)
end

-- local itemID, itemType, itemSubType, itemEquipLoc, icon, itemTypeID, itemSubClassID = GetItemInfoInstant(self:GetStaticBackingItem())

-- TODO: Find lint rule - always need parens around select to reduce to single value

-- TODO: May need to fix to not call GetStaticBackingItem (or fix it) in the case of
-- itemLink instead of itemID - not sure if it works correctly... need to test.
function CaerdonItemMixin:GetItemType()
    if not self:IsItemEmpty() then
        return (select(2, GetItemInfoInstant(self:GetStaticBackingItem())))
    end
end

function CaerdonItemMixin:GetItemSubType()
    if not self:IsItemEmpty() then
        return (select(3, GetItemInfoInstant(self:GetStaticBackingItem())))
    end
end

function CaerdonItemMixin:GetEquipLocation()
    if not self:IsItemEmpty() then
        local equipLocation = (select(4, GetItemInfoInstant(self:GetStaticBackingItem())))
        if equipLocation == "" then
            return nil
        end
        return equipLocation
    end

    return nil
end

function CaerdonItemMixin:GetItemTypeID()
    if not self:IsItemEmpty() then
        return (select(6, GetItemInfoInstant(self:GetStaticBackingItem())))
    end
end

function CaerdonItemMixin:GetItemSubTypeID()
    if not self:IsItemEmpty() then
        return (select(7, GetItemInfoInstant(self:GetStaticBackingItem())))
    end
end

function CaerdonItemMixin:GetHasUse() -- requires item data to be loaded
    if not self:IsItemEmpty() then
        local spellName, spellID = GetItemSpell(self:GetStaticBackingItem())
        return spellID ~= nil
    end
end

-- local itemName, itemLinkInfo, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
-- itemEquipLoc, iconFileDataID, itemSellPrice, itemTypeID, itemSubTypeID, bindType, expacID, itemSetID, 
-- isCraftingReagent = GetItemInfo(self:GetStaticBackingItem())
function CaerdonItemMixin:GetMinLevel() -- requires item data to be loaded
    if not self:IsItemEmpty() then
        return (select(5, GetItemInfo(self:GetStaticBackingItem())))
    end
end

function CaerdonItemMixin:GetBinding() -- requires item data to be loaded
    if not self:IsItemEmpty() then
        local bindType = (select(14, GetItemInfo(self:GetStaticBackingItem())))

        local binding = CaerdonItemBind.Unknown
        if bindType == 0 then
            binding = CaerdonItemBind.None
        elseif bindType == 1 then -- BoP
            binding = CaerdonItemBind.BindOnPickup
        elseif bindType == 2 then -- BoE
            binding = CaerdonItemBind.BindOnEquip
        elseif bindType == 3 then -- BoU
            binding = CaerdonItemBind.BindOnUse
        elseif bindType == 4 then -- Quest
            binding = CaerdonItemBind.QuestItem
        end

        return binding
    end
end

function CaerdonItemMixin:GetExpansionID() -- requires item data to be loaded
    if not self:IsItemEmpty() then
        return (select(15, GetItemInfo(self:GetStaticBackingItem())))
    end
end

function CaerdonItemMixin:GetSetID()
    if not self:IsItemEmpty() then
        return (select(16, GetItemInfo(self:GetStaticBackingItem())))
    end
end

function CaerdonItemMixin:GetIsCraftingReagent()  -- requires item data to be loaded
    if not self:IsItemEmpty() then
        return (select(17, GetItemInfo(self:GetStaticBackingItem())))
    else
        return false
    end
end

function IsUnhandledType(typeID, subTypeID)
    return typeID == LE_ITEM_CLASS_CONTAINER or
        typeID == LE_ITEM_CLASS_GEM or
        typeID == LE_ITEM_CLASS_REAGENT or
        typeID == LE_ITEM_CLASS_PROJECTILE or
        typeID == LE_ITEM_CLASS_TRADEGOODS or
        typeID == LE_ITEM_CLASS_ITEM_ENHANCEMENT or
        typeID == LE_ITEM_CLASS_QUIVER or 
        typeID == LE_ITEM_CLASS_KEY or
        typeID == LE_ITEM_CLASS_GLYPH or
        typeID == LE_ITEM_CLASS_WOW_TOKEN
end

function CaerdonItemMixin:GetCaerdonItemType()
    if not self.caerdonItemType then
        local linkType, linkOptions, displayText = LinkUtil.ExtractLink(self:GetItemLink())
        local caerdonType = CaerdonItemType.Unknown
        local typeID = self:GetItemTypeID()
        local subTypeID = self:GetItemSubTypeID()

        if linkType == "item" then
            -- TODO: Switching to just checking type for equipment 
            -- instead of using GetEquipLocation (since containers are equippable)
            -- Keep an eye on this
            if IsUnhandledType(typeID, subTypeID) then
                caerdonType = CaerdonItemType.Unhandled
            elseif typeID == LE_ITEM_CLASS_ARMOR or typeID == LE_ITEM_CLASS_WEAPON then
                caerdonType = CaerdonItemType.Equipment
            elseif typeID == LE_ITEM_CLASS_BATTLEPET then
                caerdonType = CaerdonItemType.BattlePet
            elseif typeID == LE_ITEM_CLASS_CONSUMABLE then
                -- TODO: I've seen toys in both consumable/other and misc/other but worried about holiday, etc - can I get more specific?
                local itemIDInfo, toyName, icon = C_ToyBox.GetToyInfo(self:GetItemID())
                if (itemIDInfo and toyName) then
                    caerdonType = CaerdonItemType.Toy
                else
                    caerdonType = CaerdonItemType.Consumable
                end
            elseif typeID == LE_ITEM_CLASS_MISCELLANEOUS then
                if subTypeID == LE_ITEM_MISCELLANEOUS_COMPANION_PET then
                    local name, icon, petType, creatureID, sourceText, description, isWild, canBattle, tradeable, unique, obtainable, displayID, speciesID = C_PetJournal.GetPetInfoByItemID(self:GetItemID());
                    if creatureID and displayID then
                        caerdonType = CaerdonItemType.CompanionPet
                    end
                elseif subTypeID == LE_ITEM_MISCELLANEOUS_MOUNT or subTypeID == LE_ITEM_MISCELLANEOUS_MOUNT_EQUIPMENT then
                    caerdonType = CaerdonItemType.Mount
                else
                    local itemIDInfo, toyName, icon = C_ToyBox.GetToyInfo(self:GetItemID())
                    if (itemIDInfo and toyName) then
                        caerdonType = CaerdonItemType.Toy
                    else
                        caerdonType = CaerdonItemType.Unhandled
                    end
                end
            elseif typeID == LE_ITEM_CLASS_QUESTITEM then
                caerdonType = CaerdonItemType.Quest
            elseif typeID == LE_ITEM_CLASS_RECIPE then
                caerdonType = CaerdonItemType.Recipe
            end
        elseif linkType == "battlepet" then
            caerdonType = CaerdonItemType.BattlePet
        elseif linkType == "quest" then
            caerdonType = CaerdonItemType.Quest
        end

        self.caerdonItemType = caerdonType
    end

    return self.caerdonItemType
end

function CaerdonItemMixin:GetItemData()
    if not self.caerdonItemData then
        local caerdonType = self:GetCaerdonItemType()

        if caerdonType == CaerdonItemType.BattlePet then
            self.caerdonItemData = CaerdonBattlePet:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.CompanionPet then
            self.caerdonItemData = CaerdonCompanionPet:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Consumable then
            self.caerdonItemData = CaerdonConsumable:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Equipment then
            self.caerdonItemData = CaerdonEquipment:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Mount then
            self.caerdonItemData = CaerdonMount:CreateFromCaerdonItem(self)
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