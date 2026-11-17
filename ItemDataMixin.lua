CaerdonWardrobeItemDataMixin = {}

-- The data object of an item finds its methods through its metatable, as the item itself does
-- (CaerdonItem.lua): its type's mixin first, then this one. A type's mixin is linked to this
-- one the first time it is used, so a type file only names its mixin here.
local baseMetatable = { __index = CaerdonWardrobeItemDataMixin }
local typeMetatables = {}

--[[static]]
function CaerdonWardrobeItemDataMixin.CreateItemData(typeMixin, caerdonItem)
    local metatable = typeMetatables[typeMixin]
    if not metatable then
        setmetatable(typeMixin, baseMetatable)
        metatable = { __index = typeMixin }
        typeMetatables[typeMixin] = metatable
    end
    return setmetatable({ item = caerdonItem }, metatable)
end

function CaerdonWardrobeItemDataMixin:Init()
	-- init and return array of frame events you'd like to receive
	-- error(format("Caerdon Wardrobe: Must provide Init implementation for %s", self:GetName()))
end

function CaerdonWardrobeItemDataMixin:ContinueOnItemDataLoad(callbackFunction)
    if type(callbackFunction) ~= "function" or self.item:IsItemEmpty() then
        error("Usage: NonEmptyItem:ContinueOnLoad(callbackFunction)", 2);
    end

    callbackFunction()
end

-- Nothing to cancel here. One function for every call: a new one per item was garbage.
local function NothingToCancel()
end

-- Allows for override of continue return if additional data needs to get loaded from a specific mixin (i.e. equipment sources)
function CaerdonWardrobeItemDataMixin:ContinueWithCancelOnItemDataLoad(callbackFunction)
    callbackFunction()

    -- By default, there is nothing to cancel, but if you override, make sure to support canceling.
    return NothingToCancel
end
