CaerdonWardrobeItemDataMixin = {}

function CaerdonWardrobeItemDataMixin:ContinueOnItemDataLoad(callbackFunction)
    if type(callbackFunction) ~= "function" or self.item:IsItemEmpty() then
        error("Usage: NonEmptyItem:ContinueOnLoad(callbackFunction)", 2);
    end

    callbackFunction()
end

-- Allows for override of continue return if additional data needs to get loaded from a specific mixin (i.e. equipment sources)
function CaerdonWardrobeItemDataMixin:ContinueWithCancelOnItemDataLoad(callbackFunction)
    callbackFunction()

    -- By default, there is nothing to cancel, but if you override, make sure to support canceling.
    return function()
    end;
end

