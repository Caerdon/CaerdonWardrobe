local ADDON_NAME, NS = ...
local L = NS.L

local TooltipMixin, Tooltip = {}

local SpecMap = {
    [250] = "Blood Death Knight",
    [251] = "Frost Death Knight",
    [252] = "Unholy Death Knight",

    [577] = "Havoc Demon Hunter",
    [581] = "Vengeance Demon Hunter",

    [102] = "Balance Druid",
    [103] = "Feral Druid",
    [104] = "Guardian Druid",
    [105] = "Restoration Druid",

    [253] = "Beast Mastery Hunter",
    [254] = "Marksmanship Hunter",
    [255] = "Survival Hunter",

    [62] = "Arcane Mage",
    [63] = "Fire Mage",
    [64] = "Frost Mage",

    [268] = "Brewmaster Monk",
    [270] = "Mistweaver Monk",
    [269] = "Windwalker Monk",

    [65] = "Holy Paladin",
    [66] = "Protection Paladin",
    [70] = "Retribution Paladin",

    [256] = "Discipline Priest",
    [257] = "Holy Priest",
    [258] = "Shadow Priest",

    [259] = "Assassination Rogue",
    [260] = "Outlaw Rogue",
    [261] = "Subtlety Rogue",

    [262] = "Elemental Shaman",
    [263] = "Enhancement Shaman",
    [264] = "Restoration Shamana",

    [265] = "Affliction Warlock",
    [266] = "Demonology Warlock",
    [267] = "Destruction Warlock",

    [71] = "Arms Warrior",
    [72] = "Fury Warrior",
    [73] = "Protection Warrior"
}

function TooltipMixin:OnLoad()
    -- TODO: Add Debug enable option setting
    -- TODO: Figure out how to get Pet/Toy/Mount links working
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(...) Tooltip:OnTooltipSetItem(...) end)
    -- For the "Already known" line of an ensemble that still teaches something
    -- (OnRequirementLine): asked before the client adds a requirement line to any tooltip.
    TooltipDataProcessor.AddLinePreCall(Enum.TooltipDataLineType.UsageRequirement,
        function(...) return Tooltip:OnRequirementLine(...) end)
    -- For the upgrade lines (OweUpgradeLines): the tooltips of the item looked at, and the
    -- comparison tooltips the client puts beside each of them.
    self:PlaceUpgradeLines(GameTooltip, ItemRefTooltip)
    self:NoteComparisonTooltips(ShoppingTooltip1, ShoppingTooltip2, ItemRefShoppingTooltip1, ItemRefShoppingTooltip2)
end

local tooltipItem

-- The item level of the piece a tooltip shows, where its link is not the piece's own: a
-- tooltip the auction house fills by item key (item, level, suffix) has the plain item's link.
-- The item made for the tooltip is told (extraData.overrideItemLevel), as the auction feature
-- tells the item of a row, so that nothing is scored off that link
-- (types/EquipmentMixin.lua, IsKnownByAnotherLink).
local function PieceLevelOf(tooltip)
    local info = tooltip.GetPrimaryTooltipInfo and tooltip:GetPrimaryTooltipInfo()
    if type(info) == "table" and info.getterName == "GetItemKey" and type(info.getterArgs) == "table" then
        return tonumber(info.getterArgs[2])
    end
    return nil
end

-- The suffix the key of such a tooltip names, where it names one, and the name the piece has
-- with it: the auction house's own for the key. The link the tooltip shows is the item's
-- without the suffix, and the item is told that as well (extraData.keySuffix, keyName).
local function PieceSuffixOf(tooltip)
    local info = tooltip.GetPrimaryTooltipInfo and tooltip:GetPrimaryTooltipInfo()
    if type(info) ~= "table" or info.getterName ~= "GetItemKey" or type(info.getterArgs) ~= "table" then
        return nil
    end
    local suffix = tonumber(info.getterArgs[3])
    if not suffix or suffix == 0 then
        return nil
    end
    local keyInfo = C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo({
        itemID = info.getterArgs[1], itemLevel = info.getterArgs[2], itemSuffix = suffix })
    return suffix, keyInfo and keyInfo.itemName or nil
end

-- An item for the link a tooltip shows: the one it had where the link and what its key says
-- of the piece are the same.
local function ItemForTooltip(tooltip, link, had)
    local level = PieceLevelOf(tooltip)
    local suffix, name = PieceSuffixOf(tooltip)
    local hadData = had and had.extraData
    if had and had:GetItemLink() == link and (hadData and hadData.overrideItemLevel or nil) == level and
        (hadData and hadData.keySuffix or nil) == suffix and (hadData and hadData.keyName or nil) == name then
        return had
    end
    local extraData = (level or suffix) and { overrideItemLevel = level, keySuffix = suffix, keyName = name } or nil
    return CaerdonItem:CreateFromItemLink(link, extraData)
end

local function ShowItemTooltip(tooltip)
    local itemName, itemLink, tooltipDataId = TooltipUtil.GetDisplayedItem(tooltip)
    if itemLink and itemName then
        tooltipItem = ItemForTooltip(tooltip, itemLink, tooltipItem)

        -- For merchant recipes (not sure if others), GetDisplayedItem returns the item created from the recipe rather than the recipe itself,
        -- so we compare to see if the ID from the tooltip data is the same as the item ID from the link.  If it's not, indicate it's an embedded item.
        local tooltipData = tooltip:GetPrimaryTooltipData()
        local shownItem = tooltipItem
        if tooltipData.id ~= tooltipItem:GetItemID() then
            shownItem = CaerdonItem:CreateFromItemID(tooltipData.id)
            -- Tooltip:ProcessTooltip(tooltip, tooltipItem, true)
        end

        -- Reported rather than raised, so the item's own lines below are still added.
        xpcall(function() Tooltip:AddRecipeLearners(tooltip, shownItem) end, geterrorhandler())
        xpcall(function() Tooltip:AddIngredientUsers(tooltip, shownItem) end, geterrorhandler())
        xpcall(function() Tooltip:AddTaughtLearners(tooltip, shownItem) end, geterrorhandler())
        xpcall(function() Tooltip:AddOwnCopies(tooltip, shownItem) end, geterrorhandler())
        Tooltip:OweUpgradeLines(tooltip, shownItem)

        Tooltip:ProcessTooltip(tooltip, shownItem, false)
    end
end

function TooltipMixin:OnTooltipSetItem(tooltip)
    if tooltip.caerdonProcessing then
        return
    end

    -- Reported rather than raised: an error anywhere in there would leave caerdonProcessing
    -- set and silence every later tooltip.
    tooltip.caerdonProcessing = true
    xpcall(ShowItemTooltip, geterrorhandler(), tooltip)
    tooltip.caerdonProcessing = false
end

-- Whether an item is an ensemble that still has something to teach: a consumable that teaches
-- a transmog set with a source the account has not collected. The set's own "collected" is
-- not the answer: it says the looks are known, from whichever source, and an ensemble
-- teaches sources (notes: Ensembles). Asked of the client each time, since the item's own
-- data may not have come yet when its tooltip is filled.
local function TeachesUncollectedSource(itemID)
    local transmogSetID = C_Item.GetItemLearnTransmogSet(itemID)
    if not transmogSetID then
        return false
    end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
    if classID ~= Enum.ItemClass.Consumable then
        return false
    end
    local setInfo = C_TransmogSets.GetSetInfo(transmogSetID)
    if not setInfo then
        return false
    end
    if not setInfo.collected then
        return true
    end
    local sourceIDs = C_TransmogSets.GetAllSourceIDs(transmogSetID)
    if sourceIDs then
        for _, sourceID in ipairs(sourceIDs) do
            local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
            if sourceInfo and not sourceInfo.isCollected then
                return true
            end
        end
    end
    return false
end

-- The client's "Already known" line is kept off the tooltip of an ensemble that still has a
-- source to teach: the toon has used one like it, and using this one teaches the rest.
--
-- Asked by the client before it adds a requirement line to a tooltip, whichever tooltip it is
-- filling (TooltipDataProcessor.AddLinePreCall). True keeps the line off; the tooltip's data
-- still holds it. The line is known by its requirement type, and by the data line's words
-- only where a requirement line names no type; the item by the data the tooltip is being
-- filled from. No font string is read. A value the client keeps secret is left alone.
function TooltipMixin:OnRequirementLine(tooltip, lineData)
    if type(lineData) ~= "table" then
        return nil
    end
    local requirementTypes = Enum.TooltipDataUsageRequirementType
    local requirementType = lineData.requirementType
    if issecretvalue(requirementType) then
        return nil
    elseif requirementType == nil then
        local text = lineData.leftText
        if text == nil or issecretvalue(text) or text ~= ITEM_SPELL_KNOWN then
            return nil
        end
    elseif not requirementTypes or requirementType ~= requirementTypes.NotAlreadyKnown then
        return nil
    end
    local info = tooltip and tooltip.GetProcessingTooltipInfo and tooltip:GetProcessingTooltipInfo()
    local data = info and info.tooltipData
    if type(data) ~= "table" or issecretvalue(data.type) or data.type ~= Enum.TooltipDataType.Item then
        return nil
    end
    local itemID = data.id
    if issecretvalue(itemID) or type(itemID) ~= "number" then
        return nil
    end
    return TeachesUncollectedSource(itemID) or nil
end

-- Whether the tooltip carries the client's "Already known" line.
local function TooltipSaysAlreadyKnown(tooltip)
    local data = tooltip.GetPrimaryTooltipData and tooltip:GetPrimaryTooltipData()
    local requirementTypes = Enum.TooltipDataUsageRequirementType
    for _, line in ipairs(data and data.lines or {}) do
        if line.type == Enum.TooltipDataLineType.UsageRequirement and requirementTypes and
            line.requirementType == requirementTypes.NotAlreadyKnown then
            return true
        end
        if line.leftText == ITEM_SPELL_KNOWN then
            return true
        end
    end
    return false
end

-- Recipe items that can still be handed over: which of the player's other toons on this realm
-- could learn the recipe, from the saved per-toon profession data. The possible lines:
--   green: toons that have the profession at the rank the item asks for, lack this recipe and
--          have no copy of the item
--   gray:  toons that lack it and whose rank is below what the item asks for (they are a
--          reason for the mail icon too); toons that lack it and have a copy already, by the
--          ledger; and toons that have the profession but whose recipes were never recorded.
--          That last one only on a recipe this toon already knows, where it explains why
--          there is no sellable icon; anywhere else it would nag on every recipe of that
--          profession.
-- The number is the toon's rank in the profession, to hold against the "Requires" line.
-- With AddIngredientUsers and AddTaughtLearners the tooltip text that names the toons the
-- mail icon is for; Tooltip.ShowRecipeLearners turns all three off.
function TooltipMixin:AddRecipeLearners(tooltip, item)
    local tooltipConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Tooltip
    if tooltipConfig and tooltipConfig.ShowRecipeLearners == false then
        return
    end
    if not item or item:IsItemEmpty() or item:GetCaerdonItemType() ~= CaerdonItemType.Recipe then
        return
    end

    local otherToons = item:GetRecipeOtherToonInfo()
    if not otherToons then
        return
    end

    -- covered: the toons of the list that have a copy (true), or those that have none (false);
    -- nil for all of them.
    local function ListToons(toons, covered)
        local parts = {}
        for _, toon in ipairs(toons) do
            if covered == nil or (toon.covered == true) == covered then
                table.insert(parts, format("%s (%s %d)", toon.name, otherToons.professionName, toon.rank))
            end
        end
        return table.concat(parts, ", ")
    end

    local wrap = true
    local missing = ListToons(otherToons.missing, false)
    if missing ~= "" then
        tooltip:AddLine(format(L["Could be learned by: %s"], missing), 0.4, 1, 0, wrap)
    end
    local tooLow = ListToons(otherToons.tooLow, false)
    if tooLow ~= "" and otherToons.requirement then
        tooltip:AddLine(format(L["Needs %s %d first: %s"], otherToons.requirement.skillName, otherToons.requirement.rank,
            tooLow), 0.6, 0.6, 0.6, wrap)
    end
    local covered = ListToons(otherToons.missing, true)
    local coveredLow = ListToons(otherToons.tooLow, true)
    if covered ~= "" and coveredLow ~= "" then
        covered = covered .. ", " .. coveredLow
    elseif covered == "" then
        covered = coveredLow
    end
    if covered ~= "" then
        tooltip:AddLine(format(L["Already has one to learn: %s"], covered), 0.6, 0.6, 0.6, wrap)
    end
    local saysKnown = #otherToons.unknown > 0 and TooltipSaysAlreadyKnown(tooltip)
    if #otherToons.unknown > 0 and saysKnown then
        tooltip:AddLine(format(L["Recipes not recorded yet (open the profession on that toon): %s"],
            ListToons(otherToons.unknown)), 0.6, 0.6, 0.6, wrap)
    end
end

-- An ingredient this toon has no use for: which of the player's other toons on this realm
-- have a recipe that takes it, from their saved recordings (CaerdonIngredients). The names
-- behind the mail icon, with each toon's rank as its last session left it.
--   green: toons a recipe still gives skill for
--   gray:  toons that know a recipe that takes it and get no skill from it, where the setting
--          counts those (Icon.IngredientsForOtherToons "any")
-- Only where the rule gives the mail icon (CaerdonItemMixin:GetIngredientStatus), so nothing
-- while this toon has a use for the item itself. Tooltip.ShowRecipeLearners turns it off with
-- the recipe lines.
function TooltipMixin:AddIngredientUsers(tooltip, item)
    local tooltipConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Tooltip
    if tooltipConfig and tooltipConfig.ShowRecipeLearners == false then
        return
    end
    local iconConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Icon
    if not iconConfig or not item or item:IsItemEmpty() or not item.GetIngredientStatus then
        return
    end

    local status, info = item:GetIngredientStatus()
    if status ~= "send" or not info then
        return
    end

    local function ListToons(toons, skip)
        local parts = {}
        for _, toon in ipairs(toons) do
            local key = toon.name .. "\n" .. toon.professionName
            if not (skip and skip[key]) then
                table.insert(parts, format("%s (%s %s)", toon.name, toon.professionName, tostring(toon.rank)))
            end
        end
        return table.concat(parts, ", ")
    end

    local wrap = true
    local listed = {}
    if #info.skillFor > 0 then
        for _, toon in ipairs(info.skillFor) do
            listed[toon.name .. "\n" .. toon.professionName] = true
        end
        tooltip:AddLine(format(L["Gives skill to: %s"], ListToons(info.skillFor)), 0.4, 1, 0, wrap)
    end
    if iconConfig.IngredientsForOtherToons == "any" then
        local others = ListToons(info.usedBy, listed)
        if others ~= "" then
            tooltip:AddLine(format(L["Used in recipes of: %s"], others), 0.6, 0.6, 0.6, wrap)
        end
    end
end

-- A class's spell book or a rune that can be handed over: which of the player's other toons
-- on this realm could learn it, each by its own saved answer (CaerdonLearners), a line a
-- toon, in the order the learner info has them:
--   green: can learn it now and has no copy
--   gray:  can learn it at a later level (with the level it had when last played), and one
--          that could learn it and has a copy already, with where the ledger last saw it
-- A toon of another class, one that has learned it and one that has not answered get no
-- line. No more than LEARNER_LINES toons, then how many more (author decision: five).
-- Tooltip.ShowRecipeLearners turns it off with the recipe and the ingredient lines.
local LEARNER_LINES = 5
function TooltipMixin:AddTaughtLearners(tooltip, item)
    local tooltipConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Tooltip
    if tooltipConfig and tooltipConfig.ShowRecipeLearners == false then
        return
    end
    -- An item no toon has answered for has nothing to say, and its tooltip is not read for it.
    if not item or item:IsItemEmpty() or not item.GetLearnerInfo or not CaerdonLearners:IsListed(item:GetItemID()) then
        return
    end
    local info = item:GetLearnerInfo()
    if not info then
        return
    end

    local lines = {}
    for _, entry in ipairs(info.toons) do
        if entry.answer == "own" or entry.answer == "lowSkill" then
            if entry.covered then
                local where = ((entry.bags or 0) > 0 and L["in its bags"]) or
                    ((entry.bank or 0) > 0 and L["in its bank"]) or
                    ((entry.mail or 0) > 0 and L["in its mailbox"]) or L["on its way to it"]
                lines[#lines + 1] = { format(L["%s already has one (%s)"], entry.toon, where), 0.6, 0.6, 0.6 }
            elseif entry.answer == "own" then
                lines[#lines + 1] = { format(L["Could be learned by: %s"], entry.toon), 0.4, 1, 0 }
            elseif entry.level then
                lines[#lines + 1] = { format(L["Could be learned at a later level by: %s (level %d)"], entry.toon, entry.level), 0.6, 0.6, 0.6 }
            else
                lines[#lines + 1] = { format(L["Could be learned at a later level by: %s"], entry.toon), 0.6, 0.6, 0.6 }
            end
        end
    end
    local wrap = true
    for index = 1, math.min(#lines, LEARNER_LINES) do
        local line = lines[index]
        tooltip:AddLine(line[1], line[2], line[3], line[4], wrap)
    end
    if #lines > LEARNER_LINES then
        tooltip:AddLine(format(L["and %d more of your toons"], #lines - LEARNER_LINES), 0.6, 0.6, 0.6, wrap)
    end
end

-- A copy the toon does not hold of something it could learn and already has a copy of: why
-- it has no star (CaerdonItem.lua, GetCaerdonStatus: bindingResult.ownCopies), and where the
-- copy is. Not on the copy it holds: a tooltip filled from a copy of the toon's own names it
-- (the data's guid), and then nothing is asked.
-- Tooltip.ShowRecipeLearners turns it off with the lines that name other toons.
function TooltipMixin:AddOwnCopies(tooltip, item)
    local tooltipConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Tooltip
    if tooltipConfig and tooltipConfig.ShowRecipeLearners == false then
        return
    end
    if not item or item:IsItemEmpty() or not item.GetItemID or not CaerdonLedger:IsTracked(item:GetItemID()) then
        return
    end
    local data = tooltip.GetPrimaryTooltipData and tooltip:GetPrimaryTooltipData()
    if type(data) == "table" and data.guid ~= nil then
        return
    end
    local isReady, _, _, bindingResult = item:GetCaerdonStatus()
    local copies = isReady and bindingResult and bindingResult.ownCopies or nil
    if not copies then
        return
    end
    local where = (copies.bags > 0 and L["in your bags"]) or (copies.bank > 0 and L["in your bank"]) or
        (copies.mail > 0 and L["in your mailbox"]) or L["on its way to your mailbox"]
    tooltip:AddLine(format(L["You already have one to learn (%s)"], where), 0.6, 0.6, 0.6, true)
end

-- A piece of equipment that would be an upgrade: for what is worn (the yellow arrow), and for
-- gear the toon keeps beside it (the red arrow: another spec, or the played spec's gear set
-- where its piece is not the one worn; types/EquipmentMixin.lua). One line for each, saying
-- which and by how much on that spec's Pawn scale. The comparison is the addon's own in every
-- case (author decision: it is the one that knows the gear sets, and the one to be taught
-- more), and Pawn's note for the same scale gives way to it (below).
--
-- The line is built like the one Pawn adds for a scale it shows, which sits in the same
-- tooltip (author decision): icon, name, an arrow, "+16% upgrade", the percentage a whole
-- number. The icon and the name are the gear set's where its piece was the one to beat, the
-- spec's otherwise; the name is in the scale's colour as Pawn has it. The arrow and the gain
-- are the arrow the addon draws on the piece's button, in the button's colour for that kind of
-- upgrade (yellow for what is worn, red for other gear; the upgrade arrow in
-- CaerdonWardrobe.lua), so that the line and the icon read as one thing.
-- Tooltip.ShowLoadoutUpgrades turns the lines off; those for other gear are not said where
-- their arrows are off (Icon.ShowOtherSpecUpgrades).
local LOADOUT_ARROW = "|TInterface\\Buttons\\JumpUpArrow:0:0:0:0:32:32:0:32:0:32:255:89:89|t"
local LOADOUT_GAIN_COLOUR = "ff5959"
local WORN_ARROW = "|TInterface\\Buttons\\JumpUpArrow:0:0:0:0:32:32:0:32:0:32:255:255:0|t"
local WORN_GAIN_COLOUR = "ffff00"
-- Pawn's colour for a scale that has none of its own.
local LOADOUT_NAME_COLOUR = "8ec3e6"

-- Tooltip.KeepPawnUpgradeNotes: Pawn's own upgrade notes and marks stay as Pawn makes them,
-- beside the addon's lines (author decision: off by default, a tooltip gives one answer; on
-- for the player who wants to see both and judge the addon's numbers by Pawn's).
local function KeepsPawnNotes()
    local tooltipConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Tooltip
    return tooltipConfig ~= nil and tooltipConfig.KeepPawnUpgradeNotes == true
end

local function WantsLoadoutLines(item)
    local tooltipConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Tooltip
    if tooltipConfig and tooltipConfig.ShowLoadoutUpgrades == false then
        return false
    end
    return item ~= nil and not item:IsItemEmpty() and item:GetCaerdonItemType() == CaerdonItemType.Equipment and
        CaerdonEquipment.GetLoadoutUpgradeList ~= nil
end

-- Gear for another loot spec that the played spec's scale calls an upgrade for what is worn
-- all the same (the stat that does nothing for the spec weighs nothing on it; otherSpecs on
-- the entry): the worn gear's line, in the red its arrow has on the button and not in yellow,
-- and after the gain whose gear the piece is, "(Balance / Restoration gear)" (author
-- decision: the player is to know of the upgrade, and to know before a roll that it is the
-- kind the client calls off-spec). The note is grey, as the client greys that stat's line.
local NOTE_COLOUR = "808080"
local function OtherSpecNote(upgrade)
    if type(upgrade.otherSpecs) ~= "table" or #upgrade.otherSpecs == 0 then
        return ""
    end
    return format("  |cff%s%s|r", NOTE_COLOUR, format(L["(%s gear)"], table.concat(upgrade.otherSpecs, " / ")))
end

-- The yellow of what is worn: not for gear of another loot spec.
local function IsWornGain(upgrade)
    return upgrade.worn == true and upgrade.otherSpecs == nil
end

-- A piece the toon has not the level for yet (atLevel on the entry) is an upgrade to come.
-- Its line stands, so that Pawn's own note for the scale does not stand in its place, with
-- the mark the addon has for "usable later" where the arrow would be and the level after the
-- gain (author decision).
local LATER_MARK = "|TInterface\\WorldMap\\Gear_64Grey:0:0:0:0:64:64:6:58:6:58|t"
local function GainMark(upgrade)
    if type(upgrade.atLevel) == "number" then
        return LATER_MARK
    end
    return IsWornGain(upgrade) and WORN_ARROW or LOADOUT_ARROW
end
local function LaterNote(upgrade)
    if type(upgrade.atLevel) ~= "number" then
        return ""
    end
    return format("  |cff%s%s|r", NOTE_COLOUR, format(L["(at level %d)"], upgrade.atLevel))
end

-- A weapon weighed for both hands (pair on the entry; author decision: a pair of one-handers
-- is weighed against a two-hander, which Pawn does not do). The note says what the gain is
-- over or with: a two-hander against both the pieces it would replace, a one-hander together
-- with the best piece carried for the other hand, by its name.
local function PairNote(upgrade)
    local text
    if upgrade.pair == "both" then
        text = L["(for both hands)"]
    elseif upgrade.pair == "alone" then
        text = L["(with the other hand empty)"]
    elseif upgrade.pair == "partner" and type(upgrade.partner) == "string" then
        text = format(L["(with %s)"], upgrade.partner:match("%[(.-)%]") or upgrade.partner)
    end
    return text and format("  |cff%s%s|r", NOTE_COLOUR, text) or ""
end

-- A gear set marked for PVP (pvp on the entry): the gain is at the levels the pieces' PVP floors
-- raise them to, which is not what Pawn's own note or the pieces' tooltips show.
local function PvpNote(upgrade)
    return upgrade.pvp and format("  |cff%s%s|r", NOTE_COLOUR, L["(at PvP levels)"]) or ""
end

-- A weapon whose hands are judged apart (hand on the entry; author decision: where the
-- class's scale has a half for the off hand's weapon, a one-hander has a verdict for each
-- hand): the note says which hand the gain is in.
local function HandNote(upgrade)
    local text
    if upgrade.hand == "off" then
        text = L["(in the off hand)"]
    elseif upgrade.hand == "main" then
        text = L["(in the main hand)"]
    end
    return text and format("  |cff%s%s|r", NOTE_COLOUR, text) or ""
end

local function AddUpgradeLine(tooltip, upgrade)
    local icon = upgrade.icon and format("|T%s:0|t ", tostring(upgrade.icon)) or ""
    -- No percentage against a piece the scale gives no value.
    local gain = upgrade.percent and format(L["+%d%% upgrade"], upgrade.percent) or L["upgrade"]
    local worn = IsWornGain(upgrade)
    tooltip:AddLine(format("|cff%s%s%s:|r  %s|cff%s%s|r%s%s%s%s%s", upgrade.colour or LOADOUT_NAME_COLOUR, icon,
        tostring(upgrade.name), GainMark(upgrade),
        worn and WORN_GAIN_COLOUR or LOADOUT_GAIN_COLOUR, gain, PairNote(upgrade), HandNote(upgrade),
        PvpNote(upgrade), OtherSpecNote(upgrade), LaterNote(upgrade)), 1, 1, 1, true)
end

-- The lines by themselves, with Pawn's own lines left as they are: one is left out where
-- Pawn's line for the scale says the same percentage (saidByPawn).
function TooltipMixin:AddLoadoutUpgrades(tooltip, item)
    if not WantsLoadoutLines(item) then
        return
    end
    for _, upgrade in ipairs(CaerdonEquipment:GetLoadoutUpgradeList(item) or {}) do
        if not upgrade.saidByPawn then
            AddUpgradeLine(tooltip, upgrade)
        end
    end
end

-- What wearing the piece would do to the bonuses of the item sets the toon wears pieces of (a
-- tier set's and the like; CaerdonSetBonuses): a line for each bonus it would bring or end
-- (author decision: a warning in both directions, the upgrade's arrow is not held back for
-- it). The set's name in the colour the client writes it in, then what happens: green for a
-- bonus gained, the client's red for one lost, and "may lose" where the pieces a bonus begins
-- at are not yet known. A piece that can go in two places and would not do the same in both
-- says for each line which worn piece it is about.
-- The lines stand with the upgrade lines (below), for a piece that is an upgrade and for one
-- that is not: a piece that only completes a bonus is worth knowing of too. None for a piece
-- that is being worn, none in a comparison tooltip. Tooltip.ShowSetBonusChanges turns them off.
local SET_NAME_COLOUR = "ffd100"
local SET_GAIN_COLOUR = "00ff00"
local SET_LOSS_COLOUR = "ff2020"

function TooltipMixin:AddSetBonusChanges(tooltip, item)
    local tooltipConfig = CaerdonWardrobeConfig and CaerdonWardrobeConfig.Tooltip
    if tooltipConfig and tooltipConfig.ShowSetBonusChanges == false then
        return
    end
    if item == nil or item:IsItemEmpty() or item:GetCaerdonItemType() ~= CaerdonItemType.Equipment then
        return
    end
    for _, change in ipairs(item:GetSetBonusChanges() or {}) do
        local text, colour
        if change.kind == "gain" then
            text, colour = format(L["gains the %d-piece set bonus"], change.pieces), SET_GAIN_COLOUR
        elseif change.kind == "loss" then
            text, colour = format(L["loses the %d-piece set bonus"], change.pieces), SET_LOSS_COLOUR
        else
            text, colour = L["may lose a set bonus"], SET_LOSS_COLOUR
        end
        local note = change.inPlaceOf and format(L["(in place of %s)"], change.inPlaceOf) or
            change.emptySlot and L["(in the empty slot)"] or nil
        tooltip:AddLine(format("|cff%s%s:|r  |cff%s%s|r%s", SET_NAME_COLOUR, tostring(change.set), colour, text,
            note and format("  |cff%s%s|r", NOTE_COLOUR, note) or ""), 1, 1, 1, true)
    end
end

-- Where the lines go, and what becomes of Pawn's (author decisions: at the bottom, as Pawn's
-- are; and no line of Pawn's that contradicts ours).
--
-- Pawn adds its lines after the client has filled the tooltip, in one function,
-- PawnAddValuesToTooltip(tooltip, itemValues, upgradeInfo, ...): a line per scale it shows,
-- with "+N% upgrade" for each scale upgradeInfo names (read in Pawn 2.14.4). The addon's own
-- handler runs earlier, among every addon's handlers for the item, so a line added there
-- lands in the middle of the tooltip. So the handler only notes the item, and the lines are
-- added from that function of Pawn's, which the addon wraps: after Pawn's own, at the bottom.
--
-- The same wrap takes out of upgradeInfo every scale the addon has a line for that is the same
-- comparison or a better one (what is worn; another spec), and the scales whose gear set
-- decides in Pawn's place whether it has a line or not
-- (CaerdonEquipment:GetPawnScalesGivenToSets): Pawn's note for such a scale is against the
-- worn gear, ours against the set's piece, and the two side by side read as one fact with two
-- numbers (seen: 6% and 2% for one cloak). Pawn then prints the scale's line without an
-- upgrade note, or none where it shows upgrades only. A note of Pawn's for a scale the addon
-- says nothing about stays.
--
-- Pawn's note for the scale the worn gear is judged on gives way too where the addon calls
-- the piece no upgrade, and for the spec's other scales (CaerdonEquipment:
-- GetWornScalesJudged; author decision: no line of Pawn's that contradicts the addon's
-- verdict): the icon and the comparison are the addon's there, and Pawn's "+35% upgrade"
-- stood under a piece both called worse.
--
-- All of it is the default and not the only way: with Tooltip.KeepPawnUpgradeNotes on, Pawn
-- is told what it said itself, notes and marks, and the addon's lines are added as ever.
-- Where Pawn then names an upgrade on a scale and the addon calls the piece none, the addon
-- adds its own number in grey (AddLossLine, CaerdonEquipment:GetLoadoutLossList), so that the
-- two views stand side by side and Pawn's is not read as both.
--
-- Pawn's "your best" and "your second best" marks (its next two arguments, scale name ->
-- true) go the same way for every scale the addon judges itself
-- (CaerdonEquipment:GetPawnScalesJudged) and every scale it has a line for: Pawn takes them
-- from the pieces it has seen worn, and "second best" beside the addon's "+14% upgrade" for
-- the same name was seen. Pawn has no setting that hides them alone: its three tooltip modes
-- are values and upgrades, upgrades only (with these marks), and values only.
--
-- Nothing of Pawn's is touched with Tooltip.ShowLoadoutUpgrades off or
-- Tooltip.KeepPawnUpgradeNotes on, for an item the handler did not note, or where reading
-- fails.
--
-- Not done: a hook on the tooltip's ProcessInfo to add the lines once it is filled. Pawn's
-- item data comes from a tooltip of its own, filled like any other, so such a hook ran inside
-- the reading it had started and never came back.
--
-- Without that function (another Pawn) the lines are added in the handler, to the client's
-- own item tooltips alone, and Pawn's stay as they are.
--
-- A comparison tooltip (the worn piece shown beside the item looked at) gets none of those
-- lines (author decision): what the worn piece would be for another gear set, right beside
-- the lines of the piece in question, reads as being about that piece. Pawn's notes and marks
-- are left out there by the same rules as anywhere. What it gets is what the client's own
-- "If you replace this item" is about: what the piece looked at would do in the place of this
-- worn one, by the addon's scoring (CaerdonEquipment:GetReplacementGains; author decision).
-- A ring's own line says it is an upgrade and not for which of the two rings; here each ring
-- has its number, a gain with the arrow and the colour of the line it belongs to, a loss in
-- grey. One line, for the gear that is on: another gear set that has the worn piece too has
-- its line in the item's own tooltip, not here (author decision).
--
-- Those lines go under the client's stat changes, as the last of them (author decision), and
-- not with Pawn's. The client builds a comparison tooltip in
-- TooltipComparisonManager:SetItemTooltip: it clears the tooltip, fills it with the worn
-- piece (ProcessInfo, where the addon's handler and Pawn's step run), then adds "If you
-- replace this item" and the changes (TooltipComparisonManager.lua, the same in both
-- flavors). Nothing of the addon's is called after those lines, so its handler only counts
-- the building (OweUpgradeLines), and the lines are added when a tooltip's OnUpdate next
-- runs: a comparison tooltip's own, and that of the client's item tooltips, whose OnUpdate
-- is where a bag button's tooltip is set again five times a second (GameTooltip_OnUpdate),
-- so the lines are back right after the building that cleared them and before the frame is
-- drawn. The piece looked at is the one in the tooltip that owns the comparison tooltip (the
-- manager makes it the owner); both pieces are read off their tooltips
-- (TooltipUtil.GetDisplayedItem).
--
-- Not done: a secure hook after TooltipComparisonManager:SetItemTooltip. Retail client
-- (12.1.5.70961): each time a bag button set its tooltip, each comparison tooltip was built
-- twice, and the hook ran after the first building and not after the second, which cleared
-- the line it had added. Why it did not run is not known. The addon's handler ran in both.
--
-- What the addon last made of each comparison tooltip is kept for the Debug Frame export
-- (NoteComparison): none of this can be seen offline, and an export is made after the
-- pointer has left the item, when the comparison is gone.
local upgradeItems = {}
local clientTooltips = {}
local comparisonTooltips = {}
-- Comparison tooltip -> how often the client has filled it since the addon last looked.
local pendingBuilds = {}
local pawnAddsValues = nil

local LOSS_COLOUR = "808080"
local function AddReplacementLine(tooltip, gain)
    local icon = gain.icon and format("|T%s:0|t ", tostring(gain.icon)) or ""
    local text
    if gain.upgrade then
        local worn = IsWornGain(gain)
        text = format("%s|cff%s%s|r%s%s%s%s", GainMark(gain),
            worn and WORN_GAIN_COLOUR or LOADOUT_GAIN_COLOUR,
            gain.percent and format(L["+%d%% upgrade"], gain.percent) or L["upgrade"], PairNote(gain), PvpNote(gain),
            OtherSpecNote(gain), LaterNote(gain))
    else
        text = format("|cff%s%s|r%s%s", LOSS_COLOUR, gain.percent and format("%+d%%", gain.percent) or L["no upgrade"],
            PairNote(gain), PvpNote(gain))
    end
    tooltip:AddLine(format("|cff%s%s%s:|r  %s", gain.colour or LOADOUT_NAME_COLOUR, icon, tostring(gain.name), text),
        1, 1, 1, true)
end

-- With Pawn's own notes kept (Tooltip.KeepPawnUpgradeNotes): the addon's number for a piece
-- it calls no upgrade on a scale Pawn calls it one on, in the grey a loss has above, with the
-- notes that say what the number is by. Without it Pawn's "+35% upgrade" stood there alone
-- and read as the addon's view too.
local function AddLossLine(tooltip, loss)
    local icon = loss.icon and format("|T%s:0|t ", tostring(loss.icon)) or ""
    tooltip:AddLine(format("|cff%s%s%s:|r  |cff%s%s|r%s%s%s", loss.colour or LOADOUT_NAME_COLOUR, icon, tostring(loss.name),
        LOSS_COLOUR, loss.percent and format("%+d%%", loss.percent) or L["no upgrade"],
        PairNote(loss), HandNote(loss), PvpNote(loss)), 1, 1, 1, true)
end

-- For a list a window draws itself (the auction house's listings of one item): a gain as the
-- lines above have it, without the name and the word: the arrow and "+12%" in the arrow's
-- colour. Nothing for a piece that is no upgrade.
function TooltipMixin:GetShortGainText(gain)
    if type(gain) ~= "table" or not gain.upgrade then
        return nil
    end
    local worn = IsWornGain(gain)
    return format("%s|cff%s%s|r", GainMark(gain), worn and WORN_GAIN_COLOUR or LOADOUT_GAIN_COLOUR,
        gain.percent and format("%+d%%", gain.percent) or L["upgrade"])
end

-- The piece a tooltip shows, as an item: made from its link, and kept for that tooltip while
-- it shows the same link. Nothing for an owner that is no tooltip.
local shownItems = {}
local function ItemShownIn(tooltip)
    if type(tooltip) ~= "table" or type(tooltip.IsTooltipType) ~= "function" then
        return nil
    end
    local _, link = TooltipUtil.GetDisplayedItem(tooltip)
    if not link then
        return nil
    end
    local item = ItemForTooltip(tooltip, link, shownItems[tooltip])
    shownItems[tooltip] = item
    return item
end

local function TooltipName(tooltip)
    return tostring(tooltip and tooltip.GetName and tooltip:GetName() or "a tooltip")
end

-- What the addon last made of a comparison tooltip, for the export: { time, text, count (the
-- same thing that many times in a row), lastTime, sample }. One for a tooltip: the next thing
-- that is not the same takes its place.
local comparisonNotes = {}
local function NoteComparison(tooltip, text, ...)
    if select("#", ...) > 0 then
        text = format(text, ...)
    end
    local now = GetTime()
    local note = comparisonNotes[tooltip]
    if note and note.text == text then
        note.count = note.count + 1
        note.lastTime = now
        return note
    end
    note = { time = now, text = text, count = 1, lastTime = now }
    comparisonNotes[tooltip] = note
    return note
end

-- A comparison tooltip as it stands: whether it is shown, how many lines it has against how
-- many it had when the addon last added to it (fewer: it was built again since), and whether
-- its last line lies inside its frame (below it: the tooltip was not sized for the line).
-- Geometry and counts alone; no line's text is read.
local lastBuilt = {}
local function DescribeComparisonTooltip(tooltip)
    local count = tooltip.NumLines and tooltip:NumLines() or 0
    local built = lastBuilt[tooltip]
    local parts = { format("%s, %d lines", tooltip.IsShown and tooltip:IsShown() and "shown" or "hidden", count) }
    if built then
        parts[#parts + 1] = format("%d when the addon last added to it (%d its own)", built.lines, built.added)
    else
        parts[#parts + 1] = "the addon has added nothing to it"
    end
    local lastLine = count > 0 and _G[TooltipName(tooltip) .. "TextLeft" .. count] or nil
    if lastLine and lastLine.GetBottom and tooltip.GetBottom then
        local lineBottom, frameBottom = lastLine:GetBottom(), tooltip:GetBottom()
        if lineBottom and frameBottom then
            parts[#parts + 1] = format("last line ends %.1f %s the frame's bottom edge (%s)", math.abs(lineBottom - frameBottom),
                lineBottom >= frameBottom and "above" or "BELOW", lastLine:IsShown() and "line shown" or "line hidden")
        end
    end
    return table.concat(parts, "; ")
end

-- How a comparison tooltip stands a moment after the addon added to it, while it is still on
-- screen and between two of the client's buildings: read once for a note. Fewer lines than the
-- addon left it with says something built it again after the addon's turn, which is how the
-- lines were once added and never seen.
local SAMPLE_DELAY = 0.1
local function SampleComparisonTooltip(tooltip, note)
    if note.sampled or not (C_Timer and C_Timer.After) then
        return
    end
    note.sampled = true
    C_Timer.After(SAMPLE_DELAY, function()
        note.sample = DescribeComparisonTooltip(tooltip)
    end)
end

-- For the Debug Frame export: each comparison tooltip as it stands now, by name, with what the
-- addon last made of it: { { state, last (or nil), sample (or nil) } ... }.
function TooltipMixin:GetComparisonReport()
    local now = GetTime()
    local report = {}
    for tooltip in pairs(comparisonTooltips) do
        local entry = { state = TooltipName(tooltip) .. ": " .. DescribeComparisonTooltip(tooltip) }
        local note = comparisonNotes[tooltip]
        if note then
            entry.last = format("%.1f s ago: %s%s", now - note.lastTime, note.text,
                note.count > 1 and format(" (%d times in a row, over %.1f s)", note.count, note.lastTime - note.time) or "")
            if note.sample then
                entry.sample = format("%.1f s after its lines were first added: %s", SAMPLE_DELAY, note.sample)
            end
        end
        report[#report + 1] = entry
    end
    table.sort(report, function(a, b) return a.state < b.state end)
    return report
end

-- A comparison tooltip the client has built since the addon last looked: its lines are gone
-- with the building, and are added again under the client's.
local function AddReplacementLines(tooltip)
    local builds = pendingBuilds[tooltip]
    pendingBuilds[tooltip] = nil
    -- Hidden: the client shows it again only by building it again.
    if not tooltip:IsShown() then
        return
    end
    local worn = ItemShownIn(tooltip)
    local looked = worn and ItemShownIn(tooltip:GetOwner()) or nil
    if not looked then
        NoteComparison(tooltip, "built %d times; %s", builds,
            worn and "the tooltip it stands beside names no item" or "it shows no item")
        return
    end
    local wornLink, lookedLink = worn:GetItemLink(), looked:GetItemLink()
    if not WantsLoadoutLines(looked) or not CaerdonEquipment.GetReplacementGains then
        NoteComparison(tooltip, "looked at %s, worn %s: built %d times; no lines wanted (the setting, or no equipment)",
            lookedLink, wornLink, builds)
        return
    end
    local before = tooltip:NumLines()
    local gains, why = CaerdonEquipment:GetReplacementGains(looked, worn)
    for _, gain in ipairs(gains or {}) do
        AddReplacementLine(tooltip, gain)
    end
    local after = tooltip:NumLines()
    lastBuilt[tooltip] = { lines = after, added = after - before }
    if after == before then
        NoteComparison(tooltip, "looked at %s, worn %s: built %d times, nothing added (%s)",
            lookedLink, wornLink, builds, tostring(why or "no reason given"))
        return
    end
    -- The tooltip took its size before these lines.
    tooltip:Show()
    SampleComparisonTooltip(tooltip, NoteComparison(tooltip,
        "looked at %s, worn %s: built %d times, added %d (the tooltip had %d lines, has %d)",
        lookedLink, wornLink, builds, after - before, before, after))
end

-- From a tooltip's OnUpdate (see above): every comparison tooltip built since the last time.
function TooltipMixin:CatchUpComparisons()
    if next(pendingBuilds) == nil then
        return
    end
    for tooltip in pairs(comparisonTooltips) do
        if pendingBuilds[tooltip] then
            xpcall(AddReplacementLines, geterrorhandler(), tooltip)
        end
    end
end

function TooltipMixin:OweUpgradeLines(tooltip, item)
    if comparisonTooltips[tooltip] then
        pendingBuilds[tooltip] = (pendingBuilds[tooltip] or 0) + 1
    end
    if pawnAddsValues then
        upgradeItems[tooltip] = item
    elseif clientTooltips[tooltip] then
        xpcall(function() Tooltip:AddLoadoutUpgrades(tooltip, item) end, geterrorhandler())
        xpcall(function() Tooltip:AddSetBonusChanges(tooltip, item) end, geterrorhandler())
    end
end

-- upgradeInfo without the scales named: a table of its own, and the one given where it names
-- none of them. Never nil for a table: without upgradeInfo Pawn says other things.
local function WithoutScales(upgradeInfo, scales)
    local kept, dropped = {}, false
    for _, upgrade in ipairs(upgradeInfo) do
        if scales[upgrade.ScaleName] then
            dropped = true
        else
            kept[#kept + 1] = upgrade
        end
    end
    return dropped and kept or upgradeInfo
end

-- A table of marks (scale name -> true) without the scales named: one of its own, and the one
-- given where it names none of them or is no table.
local function WithoutMarks(marks, scales)
    if type(marks) ~= "table" then
        return marks
    end
    local kept, dropped = {}, false
    for scaleName, mark in pairs(marks) do
        if scales[scaleName] then
            dropped = true
        else
            kept[scaleName] = mark
        end
    end
    return dropped and kept or marks
end

function TooltipMixin:PawnAddsValues(tooltip, itemValues, upgradeInfo, bestFor, secondBestFor, ...)
    local item = upgradeItems[tooltip]
    upgradeItems[tooltip] = nil
    local upgrades, setScales, judgedScales, offHandScale, notWeighed, wornScales, losses
    local keepsNotes = KeepsPawnNotes()
    if item then
        local ok, list, scales, judged, offHand, unlike, worn = pcall(function()
            if not WantsLoadoutLines(item) then
                return nil, nil, nil, nil, nil, nil
            end
            if keepsNotes then
                -- Nothing of Pawn's gives way: the lists that say what would are not asked.
                return CaerdonEquipment:GetLoadoutUpgradeList(item), nil, nil, nil, nil, nil
            end
            return CaerdonEquipment:GetLoadoutUpgradeList(item), CaerdonEquipment:GetPawnScalesGivenToSets(),
                CaerdonEquipment:GetPawnScalesJudged(),
                CaerdonEquipment.GetOffHandScaleJudged and CaerdonEquipment:GetOffHandScaleJudged(item) or nil,
                CaerdonEquipment.GetScalesNotWeighed and CaerdonEquipment:GetScalesNotWeighed(item) or nil,
                CaerdonEquipment.GetWornScalesJudged and CaerdonEquipment:GetWornScalesJudged(item) or nil
        end)
        if ok then
            upgrades, setScales, judgedScales, offHandScale, notWeighed, wornScales = list, scales, judged, offHand, unlike, worn
        end
    end
    if keepsNotes and item and type(upgradeInfo) == "table" and #upgradeInfo > 0 and not comparisonTooltips[tooltip] then
        local ok, list = pcall(function()
            return WantsLoadoutLines(item) and CaerdonEquipment.GetLoadoutLossList and
                CaerdonEquipment:GetLoadoutLossList(item) or nil
        end)
        losses = ok and list or nil
    end
    if (upgrades or setScales or judgedScales or offHandScale or notWeighed or wornScales) and not keepsNotes then
        local ours = {}
        for scaleName in pairs(setScales or ours) do
            ours[scaleName] = true
        end
        -- The scale the worn gear is judged on, where the addon calls the piece no upgrade
        -- (an upgrade has its line, below), and the spec's other scales.
        for scaleName in pairs(wornScales or {}) do
            ours[scaleName] = true
        end
        -- A thrown weapon for a toon that shoots, or the other way round: not weighed on a
        -- scale that weighs ranged damage, so Pawn's note for such a scale gives way.
        for scaleName in pairs(notWeighed or {}) do
            ours[scaleName] = true
        end
        -- The scale for the off hand's weapon, where the addon has judged that hand itself:
        -- Pawn's note for it is against the weaker of both weapons, and gives way whether the
        -- addon's verdict is an upgrade, with its line, or none.
        if offHandScale then
            ours[offHandScale] = true
        end
        -- Not for the played spec's own set: that line is against the set's saved piece,
        -- and Pawn's note for the scale is against the worn one. Where the addon has a
        -- verdict on the worn one the note has given way already (the yellow line's entry,
        -- or wornScales above); this leaves it where the addon has none.
        for _, upgrade in ipairs(upgrades or {}) do
            if not upgrade.own then
                ours[upgrade.scale] = true
            end
        end
        if type(upgradeInfo) == "table" then
            upgradeInfo = WithoutScales(upgradeInfo, ours)
        end
        for scaleName in pairs(judgedScales or {}) do
            ours[scaleName] = true
        end
        bestFor, secondBestFor = WithoutMarks(bestFor, ours), WithoutMarks(secondBestFor, ours)
    end

    pawnAddsValues(tooltip, itemValues, upgradeInfo, bestFor, secondBestFor, ...)

    -- None of these in a comparison tooltip: what it gets comes after the client's own lines
    -- (CatchUpComparisons).
    if upgrades and not comparisonTooltips[tooltip] then
        xpcall(function()
            for _, upgrade in ipairs(upgrades) do
                AddUpgradeLine(tooltip, upgrade)
            end
        end, geterrorhandler())
    end
    -- Pawn's notes kept: the addon's number for the gear it calls the piece no upgrade for,
    -- where Pawn names an upgrade on that gear's scale. Whatever line the addon has for other
    -- gear on the same scale (two gear sets can be scored on one): Pawn's note is one, and
    -- reads as being about each.
    if losses then
        xpcall(function()
            local pawnNamed = {}
            for _, upgrade in ipairs(upgradeInfo) do
                pawnNamed[upgrade.ScaleName] = true
            end
            for _, loss in ipairs(losses) do
                if pawnNamed[loss.scale] then
                    AddLossLine(tooltip, loss)
                end
            end
        end, geterrorhandler())
    end
    -- The set bonuses the piece would bring or end: under the upgrade lines, whether it has
    -- any of those or not.
    if item and not comparisonTooltips[tooltip] then
        xpcall(function() Tooltip:AddSetBonusChanges(tooltip, item) end, geterrorhandler())
    end
end

-- A tooltip whose OnUpdate adds the comparison lines that are owed: once for a tooltip.
local updateWatched = {}
local function WatchUpdates(tooltip)
    if updateWatched[tooltip] or not tooltip.HookScript then
        return
    end
    updateWatched[tooltip] = true
    tooltip:HookScript("OnUpdate", function()
        Tooltip:CatchUpComparisons()
    end)
end

-- At load: the comparison tooltips the client puts beside its item tooltips.
function TooltipMixin:NoteComparisonTooltips(...)
    for index = 1, select("#", ...) do
        local tooltip = select(index, ...)
        if tooltip and not comparisonTooltips[tooltip] then
            comparisonTooltips[tooltip] = true
            WatchUpdates(tooltip)
        end
    end
end

-- At load: the client's own item tooltips, and the wrap of Pawn's function where Pawn has it.
function TooltipMixin:PlaceUpgradeLines(...)
    for index = 1, select("#", ...) do
        local tooltip = select(index, ...)
        if tooltip then
            clientTooltips[tooltip] = true
            WatchUpdates(tooltip)
        end
    end
    if type(PawnAddValuesToTooltip) == "function" then
        pawnAddsValues = PawnAddValuesToTooltip
        PawnAddValuesToTooltip = function(...) return Tooltip:PawnAddsValues(...) end
    end
end

function TooltipMixin:AddTooltipData(tooltip, item, title, value, valueColor)
    local noWrap = false;
    local wrap = true;

    local identifiedType = item:GetCaerdonItemType()

    valueColor = valueColor or HIGHLIGHT_FONT_COLOR

    if not title then
        GameTooltip_AddErrorLine(tooltip, format("Dev Error", "Missing Title"));
        return
    end

    if title and value == nil then
        GameTooltip_AddErrorLine(tooltip, format("Missing %s", title));
    elseif tooltip == BattlePetTooltip or tooltip == FloatingBattlePetTooltip or identifiedType == CaerdonItemType.Currency then -- assuming this for now
        tooltip:ProcessLineData({
            type = 'Caerdon',
            leftText = format("%s: %s", title, value),
            leftColor = HIGHLIGHT_FONT_COLOR,
            wrapText = wrap,
            leftOffset = 0
        })
    else
        tooltip:ProcessLineData({
            type = 'Caerdon',
            leftText = format("%s:", title),
            leftColor = HIGHLIGHT_FONT_COLOR,
            rightText = tostring(value),
            rightColor = valueColor,
            wrapText = wrap,
            leftOffset = 0
        })
    end
end

function TooltipMixin:AddTooltipDoubleData(tooltip, item, title, value, title2, value2, valueColor)
    local noWrap = false;
    local wrap = true;

    local identifiedType = item:GetCaerdonItemType()

    valueColor = valueColor or HIGHLIGHT_FONT_COLOR

    if not title or not title2 then
        GameTooltip_AddErrorLine(tooltip, format("Dev Error", "Missing Title"));
        return
    end

    if value == nil then
        GameTooltip_AddErrorLine(tooltip, format("Missing %s", title));
    end

    if value2 == nil then
        GameTooltip_AddErrorLine(tooltip, format("Missing %s", title2));
    end

    if value ~= nil and value2 ~= nil then
        if tooltip == BattlePetTooltip or tooltip == FloatingBattlePetTooltip or identifiedType == CaerdonItemType.Currency then -- assuming this for now
            GameTooltip_AddColoredLine(tooltip, format("%s: %s", title, value), HIGHLIGHT_FONT_COLOR, wrap)
            GameTooltip_AddColoredLine(tooltip, format("%s: %s", title2, value2), HIGHLIGHT_FONT_COLOR, wrap)
        else
            GameTooltip_AddColoredDoubleLine(tooltip, format("%s / %s:", title, title2), format("%s / %s", value, value2),
                HIGHLIGHT_FONT_COLOR, valueColor, wrap);
        end
    elseif value ~= nil then
        if tooltip == BattlePetTooltip or tooltip == FloatingBattlePetTooltip then -- assuming this for now
            GameTooltip_AddColoredLine(tooltip, format("%s: %s", title, value), HIGHLIGHT_FONT_COLOR, wrap)
        else
            GameTooltip_AddColoredDoubleLine(tooltip, format("%s:", title), tostring(value), HIGHLIGHT_FONT_COLOR,
                valueColor, wrap);
        end
    elseif value2 ~= nil then
        if tooltip == BattlePetTooltip or tooltip == FloatingBattlePetTooltip then -- assuming this for now
            GameTooltip_AddColoredLine(tooltip, format("%s: %s", title, value2), HIGHLIGHT_FONT_COLOR, wrap)
        else
            GameTooltip_AddColoredDoubleLine(tooltip, format("%s:", title), tostring(value2), HIGHLIGHT_FONT_COLOR,
                valueColor, wrap);
        end
    end
end

local cancelFuncs = {}
function TooltipMixin:ProcessTooltip(tooltip, item, isEmbedded)
    -- if not tooltip.info then return end -- tooltip needs access to tooltipInfo or things just break

    if not CaerdonWardrobeConfig.Debug.Enabled then
        -- Not doing anything other than debug for tooltips right now
        return
    end

    if cancelFuncs[tooltip] then
        cancelFuncs[tooltip]()
        cancelFuncs[tooltip] = nil
    end

    local function continueLoad()
        GameTooltip_AddBlankLineToTooltip(tooltip);
        GameTooltip_AddColoredLine(tooltip, "Caerdon Wardrobe " .. (isEmbedded and "Associated Item" or ""),
            LIGHTBLUE_FONT_COLOR);

        local forDebugUse = item:GetForDebugUse()
        local identifiedType = item:GetCaerdonItemType()

        local identifiedColor = GREEN_FONT_COLOR
        if identifiedType == CaerdonItemType.Unknown then
            identifiedColor = RED_FONT_COLOR
        end

        if not isEmbedded and identifiedType ~= CaerdonItemType.Currency then
            local specIndex = CaerdonAPI:GetPlayerSpecializationIndex()
            local specID
            if specIndex then
                specID = CaerdonAPI:GetSpecializationInfo(specIndex)
            end
            self:AddTooltipData(tooltip, item, "Spec", SpecMap[specID] or specID or "None")
            self:AddTooltipData(tooltip, item, "Level", UnitLevel("player"))

            local englishFaction = UnitFactionGroup("player")
            self:AddTooltipData(tooltip, item, "Faction", englishFaction)

            GameTooltip_AddBlankLineToTooltip(tooltip);
        end

        self:AddTooltipData(tooltip, item, "Identified Type", identifiedType, identifiedColor)
        if forDebugUse then
            local optionsLength = strlen(forDebugUse.linkOptions or "")
            local optionsEnd = ""
            if optionsLength > 30 then
                optionsEnd = "..."
            end

            self:AddTooltipDoubleData(tooltip, item, "Link Type", forDebugUse.linkType or "Missing", "Options",
                (strsub(forDebugUse.linkOptions or "", 1, 30) .. optionsEnd) or "Missing")
        end

        if item:GetItemQuality() then
            self:AddTooltipData(tooltip, item, "Quality", _G[format("ITEM_QUALITY%d_DESC", item:GetItemQuality())],
                item:GetItemQualityColor().color)
        end

        local itemLocation = item:GetItemLocation()
        if itemLocation and itemLocation:HasAnyLocation() then
            if itemLocation:IsEquipmentSlot() then
                self:AddTooltipData(tooltip, item, "Equipment Slot", tostring(itemLocation:GetEquipmentSlot()))
            end

            if itemLocation:IsBagAndSlot() and not item:IsItemEmpty() then
                local bag, slot = itemLocation:GetBagAndSlot();
                self:AddTooltipDoubleData(tooltip, item, "Bag", bag, "Slot", slot)

                local canTransmog, error = C_Item.CanItemTransmogAppearance(itemLocation)
                self:AddTooltipData(tooltip, item, "Can Item Transmog Appearance", tostring(canTransmog))
            end
        end

        if identifiedType ~= CaerdonItemType.BattlePet and identifiedType ~= CaerdonItemType.Quest and identifiedType ~= CaerdonItemType.Currency then
            GameTooltip_AddBlankLineToTooltip(tooltip);

            self:AddTooltipData(tooltip, item, "Item ID", item:GetItemID())
            self:AddTooltipDoubleData(tooltip, item, "Item Type", item:GetItemType(), "SubType", item:GetItemSubType())
            self:AddTooltipDoubleData(tooltip, item, "Item Type ID", item:GetItemTypeID(), "SubType ID",
                item:GetItemSubTypeID())
            self:AddTooltipData(tooltip, item, "Binding", item:GetBinding())

            GameTooltip_AddBlankLineToTooltip(tooltip);

            self:AddTooltipData(tooltip, item, "Expansion ID", item:GetExpansionID())
            self:AddTooltipData(tooltip, item, "Is Crafting Reagent", tostring(item:GetIsCraftingReagent()))
        end


        -- All data from here on out should come from the API
        -- TODO: Add additional option to show item link since it's so large?
        -- self:AddTooltipData(tooltip, item, "Item Link", gsub(item:GetItemLink(), "\124", "\124\124"))

        if identifiedType == CaerdonItemType.BattlePet or identifiedType == CaerdonItemType.CompanionPet then
            self:AddPetInfoToTooltip(tooltip, item)
        elseif identifiedType == CaerdonItemType.Equipment then
            self:AddTransmogInfoToTooltip(tooltip, item)
        end

        GameTooltip_CalculatePadding(tooltip)
    end

    if not item:IsItemEmpty() and not item:IsItemDataCached() then
        cancelFuncs[tooltip] = item:ContinueWithCancelOnItemLoad(continueLoad)
    else
        continueLoad()
    end
end

function TooltipMixin:AddPetInfoToTooltip(tooltip, item)
    local itemType = item:GetCaerdonItemType()

    if itemType ~= CaerdonItemType.BattlePet and itemType ~= CaerdonItemType.CompanionPet then
        return
    end

    local itemData = item:GetItemData()

    if itemType == CaerdonItemType.CompanionPet then
        GameTooltip_AddBlankLineToTooltip(tooltip);

        local petInfo = itemData:GetCompanionPetInfo()
        local speciesID = petInfo.speciesID
        self:AddTooltipData(tooltip, item, "Species ID", speciesID)
        self:AddTooltipData(tooltip, item, "Num Collected", petInfo.numCollected or 0)
        self:AddTooltipData(tooltip, item, "Pet Type", petInfo.petType)
        self:AddTooltipData(tooltip, item, "Source", petInfo.sourceText)
    elseif itemType == CaerdonItemType.BattlePet then
        local petInfo = itemData:GetBattlePetInfo()
        local speciesID = petInfo.speciesID
        self:AddTooltipData(tooltip, item, "Species ID", petInfo.speciesID)
        self:AddTooltipData(tooltip, item, "Num Collected", petInfo.numCollected or 0)
    end
end

function TooltipMixin:AddTransmogInfoToTooltip(tooltip, item)
    local itemData = item:GetItemData()
    local transmogInfo = itemData:GetTransmogInfo()

    self:AddTooltipData(tooltip, item, "Item Equip Location", item:GetEquipLocation())

    if item:GetSetID() then
        self:AddTooltipData(tooltip, item, "Item Set ID", item:GetSetID())
    end

    local equipmentSets = itemData:GetEquipmentSets()
    if equipmentSets then
        local setNames = equipmentSets[1]
        for setIndex = 2, #equipmentSets do
            setNames = setNames .. ", " .. equipmentSets[setIndex]
        end

        self:AddTooltipData(tooltip, item, "Equipment Sets", setNames)
    end

    if transmogInfo.isTransmog then
        self:AddTooltipData(tooltip, item, "Appearance ID", transmogInfo.appearanceID)
        self:AddTooltipData(tooltip, item, "Source ID", transmogInfo.sourceID)

        GameTooltip_AddBlankLineToTooltip(tooltip);

        self:AddTooltipData(tooltip, item, "Needs Item", transmogInfo.needsItem)
        self:AddTooltipData(tooltip, item, "Other Needs Item", transmogInfo.otherNeedsItem)
        self:AddTooltipData(tooltip, item, "Is Completionist Item", transmogInfo.isCompletionistItem)
        self:AddTooltipData(tooltip, item, "Matches Loot Spec", transmogInfo.matchesLootSpec)

        local requirementsColor = (transmogInfo.hasMetRequirements == false and RED_FONT_COLOR) or nil
        self:AddTooltipData(tooltip, item, "Has Met Requirements", transmogInfo.hasMetRequirements, requirementsColor)
        self:AddTooltipData(tooltip, item, "Item Min Level", item:GetMinLevel())
        self:AddTooltipData(tooltip, item, "Can Equip", transmogInfo.canEquip)

        local matchedSources = transmogInfo.forDebugUseOnly.matchedSources
        if matchedSources and #matchedSources > 0 then
            for k, v in pairs(matchedSources) do
                self:AddTooltipData(tooltip, item, "Matched Source", v.name)
            end
        else
            self:AddTooltipData(tooltip, item, "Matched Source", false)
        end

        local appearanceInfo = transmogInfo.forDebugUseOnly.appearanceInfo
        if appearanceInfo then
            GameTooltip_AddBlankLineToTooltip(tooltip);

            self:AddTooltipData(tooltip, item, "Appearance Collected", appearanceInfo.appearanceIsCollected)
            self:AddTooltipData(tooltip, item, "Source Collected", appearanceInfo.sourceIsCollected)
            self:AddTooltipData(tooltip, item, "Is Conditionally Known", appearanceInfo.sourceIsCollectedConditional)
            self:AddTooltipData(tooltip, item, "Is Permanently Known", appearanceInfo.sourceIsCollectedPermanent)
            self:AddTooltipData(tooltip, item, "Has Non-level Reqs", appearanceInfo.appearanceHasAnyNonLevelRequirements)
            self:AddTooltipData(tooltip, item, "Meets Non-level Reqs", appearanceInfo
                .appearanceMeetsNonLevelRequirements)
            self:AddTooltipData(tooltip, item, "Appearance Is Usable", appearanceInfo.appearanceIsUsable)
            self:AddTooltipData(tooltip, item, "Meets Condition", appearanceInfo.meetsTransmogPlayerCondition)
        else
        end
    end
end

Tooltip = CreateFromMixins(TooltipMixin)
-- For the counters, which time OnTooltipSetItem (CaerdonCounters.lua, Attach).
NS.Tooltip = Tooltip
Tooltip:OnLoad()
