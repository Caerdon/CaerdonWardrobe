local CaerdonWardrobeConfigDisplay = CreateFromMixins(CaerdonWardrobeConfigPanelMixin)

local ADDON_NAME, NS = ...
local L = NS.L

-- How things are drawn, plus the few settings that are not about an icon.

function CaerdonWardrobeConfigDisplay:GetTitle()
    return "Display"
end

function CaerdonWardrobeConfigDisplay:Register()
    self:Init()

    self:AddTitle("Display", "How the icons and text are drawn, and the settings that are not about an icon.")

    self:AddSection("Icons")
    self:AddCheckbox({ key = "enableIconAnimation", text = "Animate icons", tooltip = "Turns the icon animation on or off, mostly seen on unlearned and openable items.", configSection = "Icon", configValue = "EnableAnimation" })
    self:AddDropdown({ key = "iconPosition", text = "Icon corner:", configSection = "Icon", configValue = "Position" }, {
        { title = "Top Left",     value = "TOPLEFT",     tooltip = "Show the primary icon in the top left" },
        { title = "Top Right",    value = "TOPRIGHT",    tooltip = "Show the primary icon in the top right" },
        { title = "Bottom Left",  value = "BOTTOMLEFT",  tooltip = "Show the primary icon in the bottom left" },
        { title = "Bottom Right", value = "BOTTOMRIGHT", tooltip = "Show the primary icon in the bottom right" }
    })

    self:AddSection("Binding text")
    self:AddDropdown({ key = "bindingPosition", text = "Position:", configSection = "Binding", configValue = "Position" }, {
        { title = "Top",    value = "TOP",    tooltip = "Show the binding text on the top of the item" },
        { title = "Center", value = "CENTER", tooltip = "Show the binding text on the center of the item" },
        { title = "Bottom", value = "BOTTOM", tooltip = "Show the binding text on the bottom of the item" }
    })

    self:AddSection("Vendor window")
    self:AddCheckbox({ key = "merchantHideCollectedItems", text = "Gray out items I have already collected", tooltip = "Grays out and fades vendor items that you have already learned or collected.", configSection = "Merchant", configSubsection = "Filter", configValue = "HideCollected" })
    self:AddCheckbox({ key = "merchantSuppressLegionRemixHelperWarning", text = "Hide the Legion Remix Helper conflict warning", tooltip = "Don't show the warning about Legion Remix Helper's merchant filtering being enabled.", configSection = "Merchant", configSubsection = "Filter", configValue = "SuppressLegionRemixHelperWarning" })

    self:AddSection("Tooltip")
    self:AddCheckbox({ key = "showRecipeLearners", text = "Add who could learn a recipe to its tooltip", tooltip = "Adds a line to a recipe's tooltip naming your other toons on this realm that have the profession and have not learned it.", configSection = "Tooltip", configValue = "ShowRecipeLearners" })

    self:AddSection("Debug")
    self:AddCheckbox({ key = "enableDebug", text = "Enable debug", tooltip = "Adds debugging details to item tooltips.", configSection = "Debug", configValue = "Enabled" })
    self:AddButton("Open Debug Frame", function()
        CaerdonWardrobeConfigMixin:OpenDebugFrame()
    end, { tooltip = "Opens the debug frame, which shows everything the addon knows about an item." })

    self:FinishLayout()
end

SettingsRegistrar:AddRegistrant(function() CaerdonWardrobeConfigDisplay:Register() end)
