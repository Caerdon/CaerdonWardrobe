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

    -- Columns of the addon's in the client's own lists: the player's to refuse, and what a
    -- column holds goes with it.
    self:AddSection("Auction house")
    self:AddCheckbox({ key = "auctionIconColumn", text = "Show the icon column", tooltip = "Adds a narrow first column to the list of auctions for this addon's icon. Off: the list has no icon of this addon's.", configSection = "Auction", configValue = "IconColumn" })
    self:AddCheckbox({ key = "auctionUpgradeColumn", text = "Show the upgrade column", tooltip = "Adds a column for the upgrade arrow and the item level gain while you browse weapons or armor you could wear, and one for each auction's upgrade percentage on the page of such a piece. Off: neither is shown. Needs the upgrade arrow on the Icons page. The list of auctions has the column only while your settings leave something to put in it.", configSection = "Auction", configValue = "UpgradeColumn" })

    -- Another addon's window with markers of its own, so someone who chose its look may want it
    -- left alone. Only offered to those who have it.
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("DialogueUI") then
        self:AddSection("Dialogue UI")
        self:AddCheckbox({ key = "showOnDialogueUI", text = "Show icons on its quest rewards", tooltip = "Draws this addon's icons and binding text on the quest rewards in Dialogue UI's window. Which icons show there follows the quest reward settings on the Icons page. Blizzard's own quest windows are not affected.", configSection = "Icon", configValue = "ShowOnDialogueUI" })
    end

    self:AddSection("Tooltip")
    self:AddCheckbox({ key = "showRecipeLearners", text = "Name the toon a recipe or an ingredient is for in its tooltip", tooltip = "Adds a line to the tooltip of a recipe naming your other toons on this realm that have the profession and have not learned it, and to the tooltip of an ingredient this toon has no use for naming the toons whose recipes take it.", configSection = "Tooltip", configValue = "ShowRecipeLearners" })
    self:AddCheckbox({ key = "showLoadoutUpgrades", text = "Say what an upgrade is for, and by how much, in its tooltip", tooltip = "Adds a line to the tooltip of gear that is an upgrade: for what you are wearing, for one of your gear sets, or for another specialization. It names the gear set or spec and how much better the piece is on that spec's Pawn scale, with the arrow the piece has in your bags. Shown at the bottom with Pawn's lines, in place of Pawn's own upgrade note and its \"your best\" marks for the same spec. The lines for other gear follow \"Also for my other specs\" on the Icons page.", configSection = "Tooltip", configValue = "ShowLoadoutUpgrades" })

    self:AddSection("Debug")
    self:AddCheckbox({ key = "enableDebug", text = "Enable debug", tooltip = "Adds debugging details to item tooltips.", configSection = "Debug", configValue = "Enabled" })
    self:AddButton("Open Debug Frame", function()
        CaerdonWardrobeConfigMixin:OpenDebugFrame()
    end, { tooltip = "Opens the debug frame, which shows everything the addon knows about an item." })

    self:FinishLayout()
end

SettingsRegistrar:AddRegistrant(function() CaerdonWardrobeConfigDisplay:Register() end)
