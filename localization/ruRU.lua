local ADDON_NAME, namespace = ...
local L = namespace.L
local LOCALE = GetLocale()

-- TODO: Just an example of how this works...
-- Will add localized strings if users provide them
if LOCALE == "ruRU" then
	L["BoA"] = "Привязано к учетной записи"
	L["BoE"] = "Привязано при надевании"
	L["Equip:"] = "При надевании:"
end
