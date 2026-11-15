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

    -- Where things sit on a slot is edited on a slot, not in a list of options: this shows the
    -- current layout on real slots and opens the editor.
    self:AddSection("Layout")
    self:AddLabel("How the icon and the texts you have switched on sit on an item slot right now:")
    local strip, stripHeight = CaerdonWardrobeLayoutEditor:CreateSampleStrip(self.scrollChild)
    self:AddFrame(strip, stripHeight)
    self:RegisterControl({
        caerdonRefresh = function()
            CaerdonWardrobeLayoutEditor:RedrawSamples()
        end
    })
    self:AddButton("Adjust layout...", function()
        CaerdonWardrobeLayoutEditor:Open()
    end, { tooltip = "Closes the settings and opens the layout editor next to your bags, where you can move and resize each part on an example slot." })

    self:AddSection("Icons")
    self:AddCheckbox({ key = "enableIconAnimation", text = "Animate icons", tooltip = "Turns the icon animation on or off, mostly seen on unlearned and openable items.", configSection = "Icon", configValue = "EnableAnimation" })

    self:AddSection("Vendor window")
    self:AddCheckbox({ key = "merchantHideCollectedItems", text = "Gray out items I have already collected", tooltip = "Grays out and fades vendor items that you have already learned or collected.", configSection = "Merchant", configSubsection = "Filter", configValue = "HideCollected" })
    self:AddCheckbox({ key = "merchantSuppressLegionRemixHelperWarning", text = "Hide the Legion Remix Helper conflict warning", tooltip = "Don't show the warning about Legion Remix Helper's merchant filtering being enabled.", configSection = "Merchant", configSubsection = "Filter", configValue = "SuppressLegionRemixHelperWarning" })

    -- Another addon's window with markers of its own, so someone who chose its look may want it
    -- left alone. Only offered to those who have it.
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("DialogueUI") then
        self:AddSection("Dialogue UI")
        self:AddCheckbox({ key = "showOnDialogueUI", text = "Show icons on its quest rewards", tooltip = "Draws this addon's icons and binding text on the quest rewards in Dialogue UI's window. Which icons show there follows the quest reward settings on the Icons page. Blizzard's own quest windows are not affected.", configSection = "Icon", configValue = "ShowOnDialogueUI" })
    end

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
