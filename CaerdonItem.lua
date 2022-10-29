CaerdonItem = {}
CaerdonItemMixin = {}

local version, build, date, tocversion = GetBuildInfo()
local isShadowlands = tonumber(build) > 35700

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
    return CreateFromMixins(
        ItemMixin,
        CaerdonItemMixin
    )
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
end

-- Add a callback to be executed when item data is loaded, if the item data is already loaded then execute it immediately
function CaerdonItemMixin:ContinueOnItemLoad(callbackFunction)
    if type(callbackFunction) ~= "function" then
        error("Usage: ContinueOnLoad(callbackFunction)", 2);
    end

    if not self:IsItemEmpty() then
        ItemEventListener:AddCallback(self:GetItemID(), function ()
            -- TODO: Update things and delay callback if needed for tooltip data
            -- Make sure any dependent data is loaded
            local itemData = self:GetItemData()

            -- Allows for override of continue return if additional data needs to get loaded from a specific mixin (i.e. equipment sources)
            if itemData then
                itemData:ContinueOnItemDataLoad(callbackFunction)
            else
                callbackFunction()
            end
        end)
    elseif self:GetCaerdonItemType() == CaerdonItemType.Quest then
        local linkType, linkOptions, name = LinkUtil.ExtractLink(self:GetItemLink());
        local questID = tonumber(strsplit(":", linkOptions), 10)
        QuestEventListener:AddCallback(questID, function ()
            -- TODO: Update things and delay callback if needed for tooltip data
            -- Make sure any dependent data is loaded
            local itemData = self:GetItemData()

            -- Allows for override of continue return if additional data needs to get loaded from a specific mixin (i.e. equipment sources)
            if itemData then
                itemData:ContinueOnItemDataLoad(callbackFunction)
            else
                callbackFunction()
            end
        end)
    else
        callbackFunction()
    end
end

-- Same as ContinueOnItemLoad, except it returns a function that when called will cancel the continue
function CaerdonItemMixin:ContinueWithCancelOnItemLoad(callbackFunction)
    if type(callbackFunction) ~= "function" then
        error("Usage: ContinueWithCancelOnItemLoad(callbackFunction)", 2);
    end

    if not self:IsItemEmpty() then
        local itemDataCancel
        local itemCancel = ItemEventListener:AddCancelableCallback(self:GetItemID(), function ()
            -- TODO: Update things and delay callback if needed for tooltip data
            local itemData = self:GetItemData()
            if itemData then
                itemDataCancel = itemData:ContinueWithCancelOnItemDataLoad(callbackFunction)
            else
                callbackFunction()
            end
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
        local itemCancel = QuestEventListener:AddCancelableCallback(questID, function ()
            -- TODO: Update things and delay callback if needed for tooltip data
            local itemData = self:GetItemData()
            if itemData then
                itemDataCancel = itemData:ContinueWithCancelOnItemDataLoad(callbackFunction)
            else
                callbackFunction()
            end
        end);

        return function()
            if type(itemDataCancel) == "function" then
                itemDataCancel()
            end

            itemCancel()
        end;
    else
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

-- local itemID, itemType, itemSubType, itemEquipLoc, icon, itemTypeID, itemSubClassID = GetItemInfoInstant(self:GetStaticBackingItem())

-- TODO: Find lint rule - always need parens around select to reduce to single value
function CaerdonItemMixin:GetItemType()
    if not self:IsItemEmpty() then
        return (select(2, GetItemInfoInstant(self:GetItemID())))
    end
end

function CaerdonItemMixin:GetItemSubType()
    if not self:IsItemEmpty() then
        return (select(3, GetItemInfoInstant(self:GetItemID())))
    end
end

function CaerdonItemMixin:GetEquipLocation()
    if not self:IsItemEmpty() then
        local equipLocation = (select(4, GetItemInfoInstant(self:GetItemID())))
        if equipLocation == "" then
            return nil
        end
        return equipLocation
    end

    return nil
end

function CaerdonItemMixin:GetItemTypeID()
    if not self:IsItemEmpty() then
        return (select(6, GetItemInfoInstant(self:GetItemID())))
    end
end

function CaerdonItemMixin:GetItemSubTypeID()
    if not self:IsItemEmpty() then
        return (select(7, GetItemInfoInstant(self:GetItemID())))
    end
end

function CaerdonItemMixin:GetHasUse() -- requires item data to be loaded
    if not self:IsItemEmpty() then
        local spellName, spellID = GetItemSpell(self:GetItemID())
        return spellID ~= nil
    end
end

-- local itemName, itemLinkInfo, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
-- itemEquipLoc, iconFileDataID, itemSellPrice, itemTypeID, itemSubTypeID, bindType, expacID, itemSetID, 
-- isCraftingReagent = GetItemInfo(self:GetItemLink())
function CaerdonItemMixin:GetMinLevel() -- requires item data to be loaded
    if not self:IsItemEmpty() then
        return (select(5, GetItemInfo(self:GetItemLink())))
    end
end

function CaerdonItemMixin:GetBinding() -- requires item data to be loaded
    if not self:IsItemEmpty() then
        local bindType = (select(14, GetItemInfo(self:GetItemLink())))

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
        elseif bindType == 8 then -- BoA, apparently
            binding = CaerdonItemBind.BindOnAccount
        elseif bindType ~= nil then
            print(self:GetItemLink() .. ": Please report - Unknown binding type " .. tostring(bindType))
        end

        return binding
    end
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
        return (select(15, GetItemInfo(self:GetItemLink())))
    end
end

function CaerdonItemMixin:GetSetID()
    if not self:IsItemEmpty() then
        return (select(16, GetItemInfo(self:GetItemLink())))
    end
end

function CaerdonItemMixin:GetIsCraftingReagent()  -- requires item data to be loaded
    if not self:IsItemEmpty() then
        return (select(17, GetItemInfo(self:GetItemLink())))
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
        local isConduit = isShadowlands and C_Soulbinds.IsItemConduitByItemInfo(itemLink)

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
                print("Unknown item type " .. tostring(typeID) .. ", " .. tostring(linkType) .. " (unknown): " .. itemLink)
            end
        elseif linkType == "keystone" then
            caerdonType = CaerdonItemType.Unhandled
        else
            print("Unknown type " .. tostring(typeID) .. ", " .. tostring(linkType) .. " (unknown): " .. itemLink)
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
        elseif caerdonType == CaerdonItemType.Conduit then
            self.caerdonItemData = CaerdonConduit:CreateFromCaerdonItem(self)
        elseif caerdonType == CaerdonItemType.Consumable then
            self.caerdonItemData = CaerdonConsumable:CreateFromCaerdonItem(self)
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
