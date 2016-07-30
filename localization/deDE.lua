local ADDON_NAME, namespace = ...
local L = namespace.L
local LOCALE = GetLocale()

-- TODO: Just an example of how this works...
-- Will add localized strings if users provide them
if LOCALE == "deDE" then
	L["BoA"] = "BoA"
	L["BoE"] = "BoE"
	L["Equip:"] = "Equip:"
return end
