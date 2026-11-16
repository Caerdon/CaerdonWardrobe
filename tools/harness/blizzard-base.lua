-- Blizzard's own Lua that the addon's item side runs on, by path under Interface/AddOns in
-- the source mirror, in load order. The harness loads these instead of mocking them.
--
-- The static check reads the same list: what these files ask the client (Item.lua calls
-- C_Item functions the addon never names) goes into ApiNames.lua with the addon's own names,
-- so a recording holds those answers too. After changing the list, run the static check with
-- --emit-facts.
return {
    "Blizzard_SharedXMLBase/Mixin.lua",
    "Blizzard_SharedXMLBase/TableUtil.lua",
    "Blizzard_SharedXMLBase/FunctionUtil.lua",
    "Blizzard_SharedXMLBase/MathUtil.lua",
    "Blizzard_SharedXMLBase/Color.lua",
    "Blizzard_SharedXML/LinkUtil.lua",
    "Blizzard_ObjectAPI/Mainline/AsyncCallbackSystem.lua",
    "Blizzard_ObjectAPI/Mainline/ContinuableContainer.lua",
    "Blizzard_ObjectAPI/Mainline/ItemLocation.lua",
    "Blizzard_ObjectAPI/Mainline/Item.lua",
}
