-- Daylight UI's vendor tiles, bag slots, auction rows, mailbox, quest rewards, loot roll cards
-- and profession window (external/DaylightUI/Core.DaylightUI.lua).
--
-- Daylight UI hands the tiles of its vendor window to other addons through DaylightUI.API (its
-- API.md, API version 1.16): a listener of "FrameStyled" is called with ("shoptile", tile, unit,
-- isPreview) for each tile on show after every fill of the shelf, one of "FrameRemoved" when a
-- tile is hidden; API.ShopItem(tile) returns tab, index, itemID, link; API.Attach(tile) a plain
-- frame over the tile, the same one each time and nil for a frame that is not Daylight UI's;
-- API.GetPart(tile, "icon") the tile's icon. The stand-in below has those in the shapes of its
-- installed source (DaylightUI 2.4.0: API.lua, Npc/Shop.lua).
--
--   1. The feature registers beside Daylight UI, finds its four hook points and listens to the
--      two events under this addon's name.
--   2. A tile on show is asked for with its item, on the frame Daylight UI attaches to it and
--      over its icon, as the vendor feature's rules have it.
--   3. A shelf filled again with the same goods asks for nothing; a refresh asks again.
--   4. A tile that keeps its index and holds another item is asked for with that item.
--   5. A buyback tile, and whose tooltip is asked of the game for which tile.
--   6. A tile that is hidden is cleared, and asked for when it shows again.
--   7. A tile the game has no link for yet is cleared and asked for when the link is there.
--   8. A tile that is not on screen at a refresh is left for the shelf's next fill.
--   9. Another kind's frames are not touched; a frame that is not Daylight UI's is not drawn on.
--  10. Another major version of the API, and one that lacks a call: nothing is attached.
--
-- Its bag slots are asked for by Daylight UI itself (DaylightUI_Bags/Plugins.lua: a feature
-- named "Daylight UI" that it registers with this addon once both are loaded, and UpdateButton
-- for a slot that holds an item). A painter of "bagslot" (API.For(addon).Paint(kind, fn)) is
-- called as fn(slot, parts, info) after each fill of a slot, info.itemID and info.link nil for
-- an empty one.
--
--  11. The bag slots' feature finds its two hook points and paints "bagslot" under this
--      addon's name. A slot that empties is cleared, once, with what was asked for it and not
--      drawn; one that holds an item, and one nothing is known of, is left alone.
--  12. A feature registered after the start: a refresh asks again for the buttons it asked
--      for, leaves one that is not on screen for when it is, and does not call its Refresh().
--
-- Its auction house's rows have no word in the API. Every item icon of its windows is set
-- through DaylightUI.Win.Parts.SetItemIcon(frame, texture, quality), which returns the
-- quality's color; a table's row frame has its kind, its index and the row's data on it by
-- then (Windows/Parts.lua, Table:Draw), a search result's data the auction house's key for it
-- (DaylightUI_AuctionHouse/BuyPage.lua, rowOf). API.For(addon).Hook(tbl, name, fn) calls fn
-- after the function with its arguments, keeps the function's results, and returns false
-- for a table it does not take.
--
--  13. The auction rows' feature finds its hook points and hooks the function. A search
--      result's row is asked for with the item of its key, on a frame of this addon's over
--      the row's icon; a row of the toon's own auctions with its item. A row filled again as
--      it was asks for nothing, and no other frame whose icon is set is touched.
--  14. A refresh asks again for a row on screen and leaves one that is not for when it is.
--  15. A hook Daylight UI does not take, and a function that is gone: noted, nothing asked.
--
-- Its mailbox has no word in the API either. Mail/Inbox.lua: Inbox.Render(pane) fills the list
-- and the letter, whose pieces are in Inbox.list.pieces and Inbox.letter.pieces afterwards (a
-- line has its spec as `lineSpec`, with the `id` Inbox.LineIds(letters) gave its letter; an
-- item's tile its spec as `spec`, with the item's name, and the size of its icon as `iconSize`),
-- and Inbox.Picked() is the letter picked, with its `index`. The list leaves out the letters its
-- filters hide. Mail/Send.lua: Send.Render(page) fills the Send page, whose tiles are in
-- Send.page.pieces, the last an empty one (`spec.empty`) while a slot is free.
-- API.For(addon).Wrap(tbl, name, fn) calls fn(original, ...) in the function's place.
--
--  16. The mailbox's feature finds its hook points, hooks the two fills and wraps the ids.
--  17. The tiles of the letter picked are asked for with its attachments, the empty places
--      left out, as copies the toon holds; a fill as it was asks for nothing; a tile that is
--      hidden, and one whose name is not its attachment's, is cleared.
--  18. A letter's line is asked for with the letter's first item, by the id of the line, with
--      letters hidden by a filter and after the inbox has moved up; a letter with no item has
--      nothing on its line. The layout editor's one note names the list beside the rows.
--  19. The Send page's tiles are asked for with the items attached; the empty one is left.
--  20. A refresh asks again for what is on screen and leaves what is not for when it is.
--  21. A wrap Daylight UI does not take, ids that are gone, no word of the letter picked, a
--      mailbox that is gone: noted, and the parts that have their functions are drawn all the
--      same.
--
-- A quest's items, on a quest's page of its NPC window (Npc/Window.lua, tilesFor) and of its
-- quest journal (DaylightUI_Quests/Journal.lua, rewardTiles), are tiles of the same making as a
-- letter's, whose spec has a `link` function that answers with the item's link (a spell's for a
-- spell the quest teaches, nothing for a sample). A vendor's tile has one too, and `shopItem`
-- (Npc/Shop.lua); a material of a recipe has one and `mat` (Craft/Recipe.lua).
--
--  22. The quests' feature hooks the function the icons are set through. A tile that names an
--      item's link is asked for with it, by the QuestLog feature's rules; one that names a
--      spell's, none yet, or is a vendor's or a recipe's, is not.
--
-- A loot roll's card has a frame kind in the API ("rollcard", API 1.13): a painter is called as
-- fn(card, parts, info) with parts.icon a texture and info = { rollID, link, done, sample }, and
-- "FrameRemoved" comes when a card's roll leaves (DaylightUI_Skins/Rolls/Card.lua).
--
--  23. The rolls' feature paints "rollcard" and listens for a card's roll leaving. A card is
--      asked for with the item rolled for, over its icon, by the GroupLoot feature's rules; the
--      game is asked for the tooltip of a roll of its own that is not over.
--
-- The profession window's list has a frame kind too ("craftrow": "FrameStyled" comes with the
-- line and the recipe's ID after each fill, Craft/List.lua). The recipe that is picked has
-- none: Craft/Recipe.lua, Recipe.Fill(pane, recipe) fills its pane, whose first piece is then
-- a line whose spec has the recipe (`recipe`) and a `link` function, which answers with the
-- link of the item made and with nothing for an enchantment.
--
--  24. The profession window's feature listens for the list's lines and hooks the pane's fill.
--      A line is asked for with what the client says its recipe makes, the picked recipe's
--      line with what its own spec says, both by the TradeSkill feature's rules.
--
-- Daylight UI's bags ask with options of their own for every slot (DaylightUI_Bags/Plugins.lua:
-- a fixed place, 16 across) and pin the icon to the slot once, when they make its widget.
--
--  25. With the setting off a slot is drawn with what Daylight UI handed. With it on, with a
--      bag slot's options of this addon's, which carry Daylight UI's: a refresh hands them
--      back, and off again the icon is pinned where Daylight UI had it. An answer that raises
--      an error leaves the request to the window's own options.
--
-- Daylight UI's Rich tooltips (DaylightUI_Tooltip/Rich/Items.lua): on a comparison tooltip's
-- card the client's stat changes are chips at the foot. RichItems.Changes(lines, from, n) makes
-- them from the lines after the item's own (each { left = its text, ... }): it returns the
-- chips, each { text, colour }, and the numbers of the lines they took. The module's parts are
-- reached by DaylightUI:GetModule("Tooltip").ns, and API.Colors() has the colours.
--
--  27. The tooltip's feature wraps that function once Daylight UI's tooltips are loaded. A line
--      this addon wrote is the last of the chips, in the colour of what it is, and is taken as
--      the stat changes' lines are; a line that says more than a chip can stays a line.
--
-- Logic only: where the icon lies on a tile has not been seen in a client.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 29 }

    local ARROWS, BREAD, KNIFE = 952001, 952002, 952003
    local ITEMS = {}
    for _, id in ipairs({ ARROWS, BREAD, KNIFE }) do
        ITEMS[id] = { name = "Sold Thing " .. id, quality = 1, level = 5, minLevel = 0, type = "Miscellaneous",
            subType = "Junk", stack = 20, price = 5, classID = 15, subClassID = 0 }
    end

    local function Start(flavor, apiIs)
        local game = H.StockGame(TOON, ITEMS)
        local world = { game = game, asked = {}, cleared = {}, listeners = {}, info = {}, holders = {}, icons = {},
            stacks = {}, tooltipsAsked = {}, painters = {}, lateRefreshes = 0, iconsSet = 0, hookOwners = {},
            mailbox = {}, sending = {}, ours = {} }

        local api = { major = apiIs == "another major version" and 2 or 1, minor = 16 }
        world.modules = {}
        if apiIs ~= "without Colors" then
            function api.Colors()
                world.coloursAsked = (world.coloursAsked or 0) + 1
                return { GOOD = { 0.5, 0.8, 0.5 }, DAMAGE = { 0.9, 0.4, 0.4 }, LABEL = apiIs ~= "without a colour" and
                    { 0.7, 0.7, 0.6 } or nil }
            end
        end
        function api.On(event, fn, owner)
            world.listeners[#world.listeners + 1] = { event = event, fn = fn, owner = owner }
            return world.listeners[#world.listeners]
        end
        function api.ShopItem(tile)
            local info = world.info[tile]
            if not info then
                return nil
            end
            return info.tab, info.index, info.id, info.link
        end
        function api.Attach(tile)
            return world.holders[tile]
        end
        if apiIs ~= "without GetPart" then
            function api.GetPart(tile, part)
                return part == "icon" and world.icons[tile] or nil
            end
        end
        local parts = {}
        if apiIs ~= "without SetItemIcon" then
            function parts.SetItemIcon(frame, texture, quality)
                world.iconsSet = world.iconsSet + 1
                return 0.1, 0.2, 0.3
            end
        end
        parts.LINE_ICON = 28
        world.parts = parts
        -- The mailbox's two pages, as far as the feature reads them. The fills themselves are
        -- the world's (FillInbox, FillSend), which calls these as Daylight UI does.
        local inbox = { list = { pieces = {} }, letter = { pieces = {} } }
        function inbox.Render(pane)
            world.inboxFills = (world.inboxFills or 0) + 1
        end
        if apiIs ~= "without Picked" then
            function inbox.Picked()
                return world.picked
            end
        end
        if apiIs ~= "without LineIds" then
            function inbox.LineIds(letters)
                local ids = {}
                for _, letter in ipairs(letters) do
                    ids[letter] = "letter:" .. letter.serial
                end
                return ids
            end
        end
        local send = { page = { pieces = {} } }
        function send.Render(page)
            world.sendFills = (world.sendFills or 0) + 1
        end
        world.inboxPage, world.sendPage = inbox, send
        -- The profession window's pane of the recipe that is picked.
        local recipePage = { pane = { pieces = {} } }
        function recipePage.Fill(pane, recipe)
            world.recipeFills = (world.recipeFills or 0) + 1
        end
        world.recipePage = recipePage
        world.ours[parts], world.ours[inbox], world.ours[send], world.ours[recipePage] = true, true, true, true
        function api.For(name)
            return {
                Paint = function(kind, fn)
                    world.painters[#world.painters + 1] = { kind = kind, fn = fn, owner = name }
                    return world.painters[#world.painters]
                end,
                Hook = function(tbl, key, fn)
                    local original = rawget(tbl, key)
                    if apiIs == "the hook refused" or not world.ours[tbl] or type(original) ~= "function" then
                        return false
                    end
                    world.hookOwner = name
                    world.hookOwners[original] = name
                    tbl[key] = function(...)
                        local r, g, b = original(...)
                        fn(...)
                        return r, g, b
                    end
                    return {}
                end,
                Wrap = function(tbl, key, fn)
                    local original = rawget(tbl, key)
                    if apiIs == "the wrap refused" or not world.ours[tbl] or type(original) ~= "function" then
                        return false
                    end
                    world.hookOwners[original] = name
                    tbl[key] = function(...)
                        return fn(original, ...)
                    end
                    return {}
                end,
            }
        end
        world.api = api
        game:Set("DaylightUI", { API = api, Win = { Parts = parts },
            GetModule = function(_, name) return world.modules[name] end,
            Mail = apiIs ~= "without the mailbox" and { Inbox = inbox, Send = send } or nil,
            Craft = apiIs ~= "without the mailbox" and { Recipe = recipePage } or nil })
        game:Set("C_TradeSkillUI.GetRecipeInfo", function(recipeID)
            return world.recipes and world.recipes[recipeID] or nil
        end)
        -- The game's mailbox: world.mailbox[letter] = { [place] = { id, count } }, and
        -- world.sending[slot] the same for the letter being written.
        local function Held(list, place)
            local held = list and list[place]
            if not held then
                return nil
            end
            return ITEMS[held[1]].name, held[1], 134400, held[2] or 1, 1
        end
        game:Set("ATTACHMENTS_MAX_RECEIVE", 16)
        game:Set("ATTACHMENTS_MAX_SEND", 12)
        game:Set("GetInboxItem", function(letter, place) return Held(world.mailbox[letter], place) end)
        game:Set("GetInboxItemLink", function(letter, place)
            local held = world.mailbox[letter] and world.mailbox[letter][place]
            return held and game.Link(held[1]) or nil
        end)
        game:Set("GetInboxHeaderInfo", function(letter)
            local list = world.mailbox[letter]
            if not list then
                return nil
            end
            local first
            for place = 1, 16 do
                first = first or list[place]
            end
            return nil, 134939, "Sender", "Letter", 0, 0, 30, first and 1 or 0, false, false, nil, true, false,
                first and (first[2] or 1) or nil, first and game.Link(first[1]) or nil
        end)
        game:Set("GetSendMailItem", function(slot) return Held(world.sending, slot) end)
        game:Set("GetSendMailItemLink", function(slot)
            local held = world.sending[slot]
            return held and game.Link(held[1]) or nil
        end)
        game:Set("C_TooltipInfo.GetInboxItem", function(letter, place)
            world.tooltipsAsked[#world.tooltipsAsked + 1] = "inbox:" .. letter .. ":" .. tostring(place)
            return { lines = {} }
        end)
        game:Set("C_TooltipInfo.GetLootRollItem", function(rollID)
            world.tooltipsAsked[#world.tooltipsAsked + 1] = "roll:" .. rollID
            return { lines = {} }
        end)
        game:Set("C_TooltipInfo.GetSendMailItem", function(slot)
            world.tooltipsAsked[#world.tooltipsAsked + 1] = "send:" .. slot
            return { lines = {} }
        end)
        game:Set("C_AddOns.GetAddOnInfo", function(name) return name, name, "", name == "DaylightUI" end)
        game:Set("C_AddOns.IsAddOnLoaded", function(name) return name == "DaylightUI" end)
        game:Set("C_AddOns.GetAddOnMetadata", function() return "2.4.0" end)
        game:Set("C_MerchantFrame.GetItemInfo", function(index)
            return { stackCount = world.stacks["buy:" .. index] or 1 }
        end)
        game:Set("GetBuybackItemInfo", function(index)
            return "Sold Thing", 134400, 5, world.stacks["buyback:" .. index] or 1
        end)
        game:Set("C_TooltipInfo.GetMerchantItem", function(index)
            world.tooltipsAsked[#world.tooltipsAsked + 1] = "buy:" .. index
            return { lines = {} }
        end)
        -- The auction house's word on a key: the name the list shows for it, and, on WoW
        -- Forever alone, a real piece among its results.
        game:Set("C_AuctionHouse.GetItemKeyInfo", function(itemKey)
            return { itemName = world.keyNames and world.keyNames[itemKey.itemSuffix] or nil }
        end)
        -- A real piece's link is another text than the item's plain one.
        function world.SampleLink(id)
            return (game.Link(id):gsub("|h%[", ":12722|h[", 1))
        end
        if flavor == "forever" then
            game:Set("C_AuctionHouse.GetItemKeySampleLink", function(itemKey)
                world.samplesAsked = (world.samplesAsked or 0) + 1
                local id = world.samples and world.samples[itemKey.itemSuffix]
                return id and world.SampleLink(id) or nil
            end)
        end
        game:Set("C_TooltipInfo.GetBuybackItem", function(index)
            world.tooltipsAsked[#world.tooltipsAsked + 1] = "buyback:" .. index
            return { lines = {} }
        end)

        local client = H.Client.New({ flavor = flavor, provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
        local core = client.env.CaerdonWardrobe
        if not core:GetFeature("DaylightUIVendor") then
            client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "external/DaylightUI/Core.DaylightUI.lua", namespace)
        end

        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(10)

        -- The vendor's own feature, for its rules, and the auction house's. Loaded after the
        -- start, so they hook nothing of windows the mocked client does not have.
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "features/Merchant.lua", namespace)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "features/Auction.lua", namespace)
        for name, file in pairs({ Mail = "features/Mail.lua", QuestLog = "features/QuestLog.lua", GroupLoot = "features/GroupLoot.lua",
            TradeSkill = "features/TradeSkill.lua" }) do
            if not core:GetFeature(name) then
                client:LoadAddonFile("CaerdonWardrobe", H.addonDir, file, namespace)
            end
        end

        world.client, world.env, world.namespace, world.core = client, client.env, namespace, core
        world.feature = core:GetFeature("DaylightUIVendor")

        local realUpdate, realClear = core.UpdateButton, core.ClearButton
        function core:UpdateButton(button, item, feature, locationInfo, options)
            world.asked[#world.asked + 1] = { button = button, id = item and item:GetItemID(), feature = feature,
                key = locationInfo and locationInfo.locationKey, options = options, locationInfo = locationInfo,
                item = item }
            return realUpdate(self, button, item, feature, locationInfo, options)
        end
        function core:ClearButton(button, ...)
            world.cleared[button] = (world.cleared[button] or 0) + 1
            return realClear(self, button, ...)
        end
        function core:SetItemButtonStatus() end
        -- What each button was last set up with: the options after anything answered for them.
        world.drawnWith = {}
        local realSetup = core.SetupCaerdonButton
        function core:SetupCaerdonButton(button, item, feature, locationInfo, options)
            if button then
                world.drawnWith[button] = options
            end
            return realSetup(self, button, item, feature, locationInfo, options)
        end
        game:Set("C_Container.GetContainerItemInfo", function(bag, slot)
            return { stackCount = world.bagCounts and world.bagCounts[slot] or 1 }
        end)
        function core:SetItemButtonMogStatusFilter() end
        function core:SetItemButtonBindType() end

        -- A tile as Daylight UI makes it: a button with an icon, and the frame it attaches for
        -- other addons once it has reported the tile.
        function world.Tile(isDaylights)
            local tile = client:NewFrame("Button")
            tile:SetSize(250, 40)
            local icon = client:NewFrame("Texture", nil, tile)
            icon:SetSize(30, 30)
            world.icons[tile] = icon
            if isDaylights ~= false then
                world.holders[tile] = client:NewFrame("Frame", nil, tile)
            end
            return tile
        end
        function world.Send(event, kind, tile, unit, isPreview)
            for _, listener in ipairs(world.listeners) do
                if listener.event == event then
                    listener.fn(kind, tile, unit, isPreview)
                end
            end
        end
        -- One fill of the shelf, as Daylight UI reports it: what each tile holds, then
        -- FrameStyled for each. entries: { tile, tab, index, itemID or nil for no link yet }.
        function world.Fill(entries, isPreview)
            for _, entry in ipairs(entries) do
                local tile, tab, index, id = entry[1], entry[2], entry[3], entry[4]
                world.info[tile] = { tab = tab, index = index, id = id, link = id and game.Link(id) or nil }
            end
            for _, entry in ipairs(entries) do
                world.Send("FrameStyled", "shoptile", entry[1], entry[2] .. ":" .. entry[3], isPreview or false)
            end
            client:Tick(3)
        end
        function world.Remove(tile)
            local info = world.info[tile]
            world.info[tile] = nil
            world.Send("FrameRemoved", "shoptile", tile, info and (info.tab .. ":" .. info.index) or nil, false)
            client:Tick(3)
        end
        -- How many listen to an event, and who paints a kind (the names, in a line).
        function world.Listening(event)
            local count = 0
            for _, listener in ipairs(world.listeners) do
                if listener.event == event then
                    count = count + 1
                end
            end
            return count
        end
        function world.PaintersOf(kind)
            local owners = {}
            for _, painter in ipairs(world.painters) do
                if painter.kind == kind then
                    owners[#owners + 1] = tostring(painter.owner)
                end
            end
            return table.concat(owners, ", ")
        end
        -- One painting of a loot roll's card, as Daylight UI reports it to a painter.
        function world.PaintCard(card, info)
            for _, painter in ipairs(world.painters) do
                if painter.kind == "rollcard" then
                    painter.fn(card, { icon = world.icons[card] }, info)
                end
            end
            client:Tick(3)
        end
        -- One fill of a bag slot, as Daylight UI reports it to a painter. Returns how often
        -- the slot was cleared by it (the core clears a button itself when it is first asked
        -- for an item, which is not the painter's doing).
        function world.FillSlot(slot, info)
            local before = world.cleared[slot] or 0
            for _, painter in ipairs(world.painters) do
                if painter.kind == "bagslot" then
                    painter.fn(slot, {}, info)
                end
            end
            return (world.cleared[slot] or 0) - before
        end
        -- An item in a bag slot whose verdict is at hand, and a request for it as Daylight UI's
        -- own feature makes it.
        function world.AskSlot(feature, slot, index)
            local item = client.env.CaerdonItem:CreateFromBagAndSlot(0, index)
            function item:GetCaerdonItemType() return "Miscellaneous" end
            function item:IsItemEmpty() return false end
            function item:IsItemDataCached() return true end
            function item:GetItemID() return ARROWS end
            function item:GetCaerdonStatus() return true, "own", nil, {}, nil end
            core:UpdateButton(slot, item, feature, { bag = 0, slot = index }, { fixedStatusPosition = true })
        end
        -- A row of one of Daylight UI's tables, as the table has it when it fills it, and
        -- one fill of it: the icon set through the table's field, as Daylight UI calls it.
        function world.Row(data, parent)
            local row = client:NewFrame("Button", nil, parent)
            row:SetSize(600, 36)
            row.kind, row.index, row.data, row.iconSize = data and data.kind, 1, data, 28
            row.icon = client:NewFrame("Texture", nil, row)
            return row
        end
        function world.FillRow(row)
            local r, g, b = world.parts.SetItemIcon(row, 134400, 1)
            client:Tick(3)
            return r, g, b
        end
        -- The mailbox's pooled pieces, as a stack of Daylight UI's hands them out: the n-th
        -- piece of a kind is the same frame at every fill, and one a fill does not use is
        -- hidden.
        local pools, pages = {}, {}
        -- The page a pool's pieces are on (a stack's scroll child).
        function world.MailPage(pool)
            pages[pool] = pages[pool] or client:NewFrame("Frame")
            return pages[pool]
        end
        local function Take(pool, at, make)
            pools[pool] = pools[pool] or {}
            local piece = pools[pool][at]
            if not piece then
                piece = make(world.MailPage(pool))
                pools[pool][at] = piece
            end
            piece:Show()
            return piece
        end
        local function HideAll(pool)
            for _, piece in ipairs(pools[pool] or {}) do
                piece:Hide()
            end
        end
        local function Line(pool, at, lineSpec)
            local line = Take(pool, at, function(page)
                local made = client:NewFrame("Button", nil, page)
                made:SetSize(280, 36)
                made.icon = client:NewFrame("Texture", nil, made)
                return made
            end)
            line.lineSpec = lineSpec
            return line
        end
        local function Tile(pool, at, spec)
            local tile = Take(pool, at, function(page)
                local made = client:NewFrame("Button", nil, page)
                made:SetSize(150, 44)
                made.iconSize = 34
                made.icon = client:NewFrame("Texture", nil, made)
                return made
            end)
            tile.spec = spec
            return tile
        end
        function world.MailLine(at) return pools.lines and pools.lines[at] end
        function world.MailTile(at) return pools.tiles and pools.tiles[at] end
        function world.SendTile(at) return pools.sendTiles and pools.sendTiles[at] end
        -- One fill of the inbox page, as Daylight UI does it: an id for each letter, a line
        -- for each one its filters leave (`hidden`: the letters they hide), the letter that is
        -- picked with a tile for each attachment it holds (`misnamed`: a place whose tile is
        -- given another name), and its function. A letter keeps its id while it is the same
        -- letter (`serials`: which letter is at each index; by default the index itself).
        function world.FillInbox(pickedLetter, hidden, misnamed, serials)
            local letters = {}
            for index = 1, 50 do
                if world.mailbox[index] then
                    letters[#letters + 1] = { index = index, serial = serials and serials[index] or index }
                end
            end
            local ids = world.inboxPage.LineIds and world.inboxPage.LineIds(letters) or {}
            HideAll("lines")
            HideAll("header")
            HideAll("tiles")
            local lines, picked = {}, nil
            for _, letter in ipairs(letters) do
                if not (hidden and hidden[letter.index]) then
                    lines[#lines + 1] = Line("lines", #lines + 1, { id = ids[letter], text = "Letter", sub = "Sender" })
                end
                if letter.index == pickedLetter then
                    picked = letter
                end
            end
            world.inboxPage.list.pieces = lines
            world.picked = picked
            local pieces = {}
            if picked then
                -- The letter's head is a line too, with no id; its text a plain piece.
                pieces[1] = Line("header", 1, { text = "Letter", sub = "From Sender" })
                pieces[2] = Take("text", 1, function(page) return client:NewFrame("Frame", nil, page) end)
                local shown = 0
                for place = 1, 16 do
                    local held = world.mailbox[picked.index][place]
                    if held then
                        shown = shown + 1
                        pieces[#pieces + 1] = Tile("tiles", shown, { count = held[2], quality = 1,
                            name = misnamed == place and "Another Thing" or ITEMS[held[1]].name })
                    end
                end
            end
            world.inboxPage.letter.pieces = pieces
            world.inboxPage.Render()
            client:Tick(3)
        end
        -- One fill of the Send page: a tile for each item attached, and one to drop the next
        -- on while a slot is free.
        function world.FillSend(misnamed)
            HideAll("sendTiles")
            local pieces = {}
            for slot = 1, 12 do
                local held = world.sending[slot]
                if held then
                    pieces[#pieces + 1] = Tile("sendTiles", #pieces + 1, { count = held[2], quality = 1,
                        name = misnamed == slot and "Another Thing" or ITEMS[held[1]].name })
                end
            end
            if #pieces < 12 then
                pieces[#pieces + 1] = Tile("sendTiles", #pieces + 1, { name = "Drop an item here", empty = true })
            end
            world.sendPage.page.pieces = pieces
            world.sendPage.Render(world.sendPage.page)
            client:Tick(3)
        end
        -- One fill of the picked recipe's pane: the line of what the recipe makes first (its
        -- spec with the recipe, `carried` where the line is another recipe's), then a text.
        function world.ResultLine() return pools.result and pools.result[1] end
        function world.FillRecipe(recipe, link, carried)
            HideAll("result")
            local pieces = {}
            if recipe then
                pieces[1] = Line("result", 1, { recipe = carried or recipe, text = "Recipe", link = function() return link end })
                pieces[2] = Take("recipeText", 1, function(page) return client:NewFrame("Frame", nil, page) end)
            end
            world.recipePage.pane.pieces = pieces
            world.recipePage.Fill(world.recipePage.pane, recipe)
            client:Tick(3)
        end
        -- What was last asked for on a frame of this addon's on the row, and how often.
        function world.LastOn(row)
            for index = #world.asked, 1, -1 do
                local button = world.asked[index].button
                if type(button) == "table" and button ~= row and button.GetParent and button:GetParent() == row then
                    return world.asked[index]
                end
            end
            return {}
        end
        function world.TimesAskedOn(row)
            local count = 0
            for _, ask in ipairs(world.asked) do
                local button = ask.button
                if type(button) == "table" and (button == row or (button.GetParent and button:GetParent() == row)) then
                    count = count + 1
                end
            end
            return count
        end
        function world.Last(button)
            for index = #world.asked, 1, -1 do
                if world.asked[index].button == button then
                    return world.asked[index]
                end
            end
            return {}
        end
        function world.TimesAsked(button)
            local count = 0
            for _, ask in ipairs(world.asked) do
                if ask.button == button then
                    count = count + 1
                end
            end
            return count
        end
        return world
    end

    for _, flavor in ipairs({ "forever", "retail" }) do
        local label = flavor .. ": "
        local world = Start(flavor)
        local feature, core = world.feature, world.core

        -- 1.
        Check(feature ~= nil, label .. "the file registers its feature beside Daylight UI")
        local noted = feature and feature.hookPointsNoted or {}
        for _, point in ipairs({ "DaylightUI.API.On", "DaylightUI.API.ShopItem", "DaylightUI.API.Attach",
            "DaylightUI.API.GetPart" }) do
            Equal(noted[point] and noted[point].found, 1, label .. "the hook point " .. point .. " is noted as found")
        end
        local events = {}
        for _, listener in ipairs(world.listeners) do
            events[#events + 1] = listener.event .. " as " .. tostring(listener.owner)
        end
        table.sort(events)
        Equal(table.concat(events, ", "), "FrameRemoved as CaerdonWardrobe, FrameRemoved as CaerdonWardrobe, FrameRemoved as CaerdonWardrobe, " ..
            "FrameStyled as CaerdonWardrobe, FrameStyled as CaerdonWardrobe",
            label .. "it listens to the two frame events under this addon's name (as the profession window's feature does, and the roll cards' to one)")
        Equal(#world.client.errors, 0, label .. "no error at the start")

        -- 2.
        local first, second = world.Tile(), world.Tile()
        local firstHolder, secondHolder = world.holders[first], world.holders[second]
        world.stacks["buy:2"] = 5
        world.Fill({ { first, "buy", 1, ARROWS }, { second, "buy", 2, BREAD } })
        Equal(world.Last(firstHolder).id, ARROWS, label .. "a tile is asked for with the item it holds")
        Equal(world.TimesAsked(first), 0, label .. "on the frame Daylight UI attaches, not on the tile itself")
        Check(core:GetAskedOf(first) ~= nil and core:GetAskedOf(first) == core:GetAskedOf(firstHolder),
            label .. "the Debug Frame finds what was asked of the tile from the tile itself")
        Equal(world.Last(firstHolder).key, "buy-1", label .. "under its tab and the game's index")
        Check(world.Last(firstHolder).feature == feature, label .. "as this feature's button")
        local options = world.Last(firstHolder).options or {}
        Check(options.relativeFrame == world.icons[first], label .. "placement: over the tile's icon")
        Equal(options.statusProminentSize, core:GetSlotStatusSize(30, 30), label .. "placement: sized to that icon")
        Equal(options.keepInsideWhenClipped, true, label .. "placement: inside where the shelf leaves no room")
        Equal(options.slotScale, core:GetSlotScale(30, 30), label .. "placement: the texts sized to the icon too")
        Equal(options.clipCutAllowed, 0.1, label .. "placement: a tenth of the icon may be cut off before it moves inside")
        Equal(core:GetSlotScale(37, 37), 1, label .. "(a bag slot's scale is 1)")
        Equal(core:GetSlotScale(54, 54), 1, label .. "(a larger slot's too)")
        Check(core:GetSlotScale(28, 28) < 0.76 and core:GetSlotScale(28, 28) > 0.75, label .. "(a 28 px icon's is its part of a bag slot)")
        Equal(core:GetSlotScale(12, 12), 0.75, label .. "(never below what can be read)")
        Equal(core:GetSlotScale(0, 0), nil, label .. "(none for a frame with no size)")
        Equal(options.hasCount, false, label .. "placement: one of an item has no count")
        Equal((world.Last(secondHolder).options or {}).hasCount, true, label .. "placement: a stack has one")
        local merchant = core:GetFeature("Merchant")
        Check(feature:GetStatusRules() ~= nil and feature:GetStatusRules() == merchant:GetStatusRules(),
            label .. "rules: the vendor feature's status rules")
        local askedItem = core:GetAskedOf(firstHolder)
        Check(feature:GetDisplayRules(firstHolder, askedItem) == merchant:GetDisplayRules(firstHolder, askedItem),
            label .. "rules: and its display rules for the draw")

        -- 3.
        world.Fill({ { first, "buy", 1, ARROWS }, { second, "buy", 2, BREAD } })
        Equal(world.TimesAsked(firstHolder), 1, label .. "a shelf filled again with the same goods asks for nothing")
        feature:Refresh()
        world.client:Tick(3)
        Equal(world.TimesAsked(firstHolder), 2, label .. "a refresh asks for a tile on show again")
        Equal(world.Last(firstHolder).id, ARROWS, label .. "with the item it holds")
        world.Fill({ { first, "buy", 1, ARROWS }, { second, "buy", 2, BREAD } })
        Equal(world.TimesAsked(firstHolder), 2, label .. "and the fill after it asks for nothing")
        world.stacks["buy:1"] = 20
        world.Fill({ { first, "buy", 1, ARROWS }, { second, "buy", 2, BREAD } })
        Equal(world.TimesAsked(firstHolder), 3, label .. "a tile that gained a count is asked for again")
        Equal((world.Last(firstHolder).options or {}).hasCount, true, label .. "with the count")
        world.stacks["buy:1"] = nil

        -- 4.
        world.Fill({ { first, "buy", 1, KNIFE }, { second, "buy", 2, BREAD } })
        Equal(world.Last(firstHolder).id, KNIFE, label .. "a tile that holds another item at its index is asked for with it")
        Equal(world.Last(firstHolder).key, "buy-1", label .. "under the same key")

        -- 5.
        local back = world.Tile()
        local backHolder = world.holders[back]
        world.Fill({ { back, "buyback", 1, BREAD } })
        Equal(world.Last(backHolder).id, BREAD, label .. "a buyback tile is asked for with its item")
        Equal(world.Last(backHolder).key, "buyback-1", label .. "under a key apart from the shop's first tile")
        feature:GetTooltipData(nil, world.Last(backHolder).locationInfo)
        feature:GetTooltipData(nil, world.Last(secondHolder).locationInfo)
        Equal(table.concat(world.tooltipsAsked, ", "), "buyback:1, buy:2",
            label .. "the tooltip of a tile's copy is the game's for its tab and index")
        local sample = world.Tile()
        local sampleHolder = world.holders[sample]
        world.Fill({ { sample, "buy", 1, BREAD } }, true)
        Equal(world.Last(sampleHolder).id, BREAD, label .. "a sample tile is asked for with its item")
        Equal(world.Last(sampleHolder).key, "sample-buy-1", label .. "under a key that is no vendor's")
        Equal(feature:GetTooltipData(nil, world.Last(sampleHolder).locationInfo), nil,
            label .. "and its tooltip is the link's: no vendor is asked")
        Equal(#world.tooltipsAsked, 2, label .. "(the game was not asked for it)")

        -- 6.
        local clearedBefore = world.cleared[firstHolder] or 0
        world.Remove(first)
        Check((world.cleared[firstHolder] or 0) > clearedBefore, label .. "a tile that is hidden is cleared")
        Equal(core:GetAskedOf(firstHolder), nil, label .. "and nothing is remembered as asked of it")
        local askedBefore = world.TimesAsked(firstHolder)
        world.Fill({ { first, "buy", 1, KNIFE } })
        Equal(world.TimesAsked(firstHolder), askedBefore + 1, label .. "shown again with what it held, it is asked for again")

        -- 7.
        local late = world.Tile()
        local lateHolder = world.holders[late]
        world.Fill({ { late, "buy", 7, nil } })
        Equal(world.TimesAsked(lateHolder), 0, label .. "a tile the game has no link for is not asked for")
        Equal(world.cleared[lateHolder], 1, label .. "and is cleared")
        world.Fill({ { late, "buy", 7, ARROWS } })
        Equal(world.Last(lateHolder).id, ARROWS, label .. "the link there, it is asked for")

        -- 8.
        second:Hide()
        askedBefore = world.TimesAsked(secondHolder)
        feature:Refresh()
        world.client:Tick(3)
        Equal(world.TimesAsked(secondHolder), askedBefore, label .. "a tile that is not on screen is not asked for at a refresh")
        second:Show()
        world.Fill({ { second, "buy", 2, BREAD } })
        Equal(world.TimesAsked(secondHolder), askedBefore + 1, label .. "the shelf's next fill asks for it")

        -- 9.
        local slot = world.Tile()
        world.info[slot] = { tab = "buy", index = 9, id = BREAD, link = world.game.Link(BREAD) }
        world.Send("FrameStyled", "bagslot", slot, "0:1", false)
        world.Send("FrameRemoved", "bagslot", slot, "0:1", false)
        world.client:Tick(3)
        Equal(world.TimesAsked(world.holders[slot]), 0, label .. "another kind's frame is not asked for")
        Equal(world.cleared[world.holders[slot]], nil, label .. "nor cleared")
        local foreign = world.Tile(false)
        world.Fill({ { foreign, "buy", 4, BREAD } })
        local drawnOnForeign = 0
        for _, ask in ipairs(world.asked) do
            if ask.button == foreign or ask.button == world.icons[foreign] then
                drawnOnForeign = drawnOnForeign + 1
            end
        end
        Equal(drawnOnForeign, 0, label .. "a frame Daylight UI attaches nothing to is not drawn on")

        Equal(#world.client.errors, 0, label .. "no error reached the error handler")

        -- 11.
        local bagSlots = core:GetFeature("DaylightUIBagSlots")
        Check(bagSlots ~= nil, label .. "bag slots: the file registers its feature")
        local slotNoted = bagSlots and bagSlots.hookPointsNoted or {}
        for _, point in ipairs({ "DaylightUI.API.For", "DaylightUI.API.For(addon).Paint" }) do
            Equal(slotNoted[point] and slotNoted[point].found, 1, label .. "bag slots: the hook point " .. point .. " is noted as found")
        end
        Equal(world.PaintersOf("bagslot"), "CaerdonWardrobe", label .. "bag slots: one painter of the bag slots, under this addon's name")

        -- Daylight UI's own feature, as its Bags module registers it: after the start.
        local LateMixin = {}
        function LateMixin:GetName() return "Daylight UI" end
        function LateMixin:GetDisplayInfo() return {} end
        function LateMixin:GetTooltipData() end
        function LateMixin:Refresh() world.lateRefreshes = world.lateRefreshes + 1 end
        function LateMixin:Init() world.lateInits = (world.lateInits or 0) + 1 end
        core:RegisterFeature(LateMixin)
        local late = core:GetFeature("Daylight UI")

        local bagSlot = world.client:NewFrame("Button")
        bagSlot:SetSize(37, 37)
        local held = { bag = 0, slot = 1, itemID = ARROWS, link = world.game.Link(ARROWS), quality = 1, count = 1 }
        world.AskSlot(late, bagSlot, 1)
        Equal(world.FillSlot(bagSlot, held), 0, label .. "bag slots: a slot that holds an item is not cleared")
        world.client:Tick(3)
        Check(core:GetAskedOf(bagSlot) ~= nil, label .. "bag slots: and what was asked for it stands")
        Equal(world.FillSlot(bagSlot, { bag = 0, slot = 1 }), 1, label .. "bag slots: a slot that empties is cleared")
        Equal(core:GetAskedOf(bagSlot), nil, label .. "bag slots: and nothing is remembered as asked of it")
        -- The slot's record, which the export has for a button that shows nothing too.
        do
            local record = core:GetButtonRecord(bagSlot)
            Check(type(record) == "string" and record:find("^asked for 1 times, last [%d.]+ s ago with item " .. ARROWS .. " by Daylight UI; ") ~= nil,
                label .. "record: what the slot was asked for, how often, and by which window (" .. tostring(record) .. ")")
            Check(type(record) == "string" and record:find(" s ago (Daylight UI said the slot holds nothing); drawn 1 times, last ", 1, true) ~= nil and
                record:find(" as own; a request dropped undrawn never", 1, true) ~= nil,
                label .. "record: why it was last cleared, and what it was drawn as (" .. tostring(record) .. ")")
            Equal(core:GetButtonRecord(world.client:NewFrame("Button")), nil, label .. "record: none for a frame nothing was said of")
            local child = world.client:NewFrame("Frame", nil, bagSlot)
            Equal(core:GetButtonRecord(child), record, label .. "record: found from a part of the button too")
            local bare = world.client:NewFrame("Button")
            core:UpdateButton(bare, nil, late, nil, {})
            local said = core:GetButtonRecord(bare)
            Check(type(said) == "string" and said:find("with nothing by Daylight UI; cleared 1 times, last ", 1, true) ~= nil and
                said:find(" s ago (asked for with nothing to show); drawn never", 1, true) ~= nil,
                label .. "record: a button asked for with nothing says so (" .. tostring(said) .. ")")
        end
        Equal(world.FillSlot(bagSlot, { bag = 0, slot = 1 }), 0,
            label .. "bag slots: an empty slot filled again is not cleared a second time")
        world.AskSlot(late, bagSlot, 1)
        Equal(world.FillSlot(bagSlot, { bag = 0, slot = 1, link = world.game.Link(ARROWS) }), 0,
            label .. "bag slots: an item named by its link alone is an item")
        -- The item leaves before its draw.
        local askedBefore11 = world.TimesAsked(bagSlot)
        world.AskSlot(late, bagSlot, 1)
        Equal(world.FillSlot(bagSlot, { bag = 0, slot = 1 }), 1, label .. "bag slots: emptied again, it is cleared again")
        world.client:Tick(3)
        Equal(core:GetAskedOf(bagSlot), nil, label .. "bag slots: what was asked and not drawn is dropped with it")
        Equal(world.TimesAsked(bagSlot), askedBefore11 + 1, label .. "bag slots: (nothing asked for it since)")
        local unknown = world.client:NewFrame("Button")
        unknown:SetSize(37, 37)
        world.AskSlot(late, unknown, 2)
        Equal(world.FillSlot(unknown, nil), 0, label .. "bag slots: a slot nothing is known of is left alone")

        -- 12.
        world.client:Tick(3)
        local shown = world.client:NewFrame("Button")
        shown:SetSize(37, 37)
        world.AskSlot(late, shown, 11)
        local hiddenBag = world.client:NewFrame("Frame")
        local hiddenSlot = world.client:NewFrame("Button", nil, hiddenBag)
        hiddenSlot:SetSize(37, 37)
        world.AskSlot(late, hiddenSlot, 13)
        world.client:Tick(3)
        world.client:SetFrameShown(hiddenBag, false)
        local shownBefore, hiddenBefore = world.TimesAsked(shown), world.TimesAsked(hiddenSlot)
        local unknownBefore, emptyBefore = world.TimesAsked(unknown), world.TimesAsked(bagSlot)
        core:RefreshItems("scenario")
        world.client:Tick(4)
        Equal(world.TimesAsked(shown), shownBefore + 1, label .. "late feature: a refresh asks again for a button it asked for")
        Equal(world.TimesAsked(unknown), unknownBefore + 1, label .. "late feature: for each of them")
        Equal(world.TimesAsked(bagSlot), emptyBefore, label .. "late feature: not for a slot that was cleared")
        Equal(world.TimesAsked(hiddenSlot), hiddenBefore, label .. "late feature: a button that is not on screen is not asked for")
        world.client:SetFrameShown(hiddenBag, true)
        world.client:Tick(3)
        Equal(world.TimesAsked(hiddenSlot), hiddenBefore + 1, label .. "late feature: and is asked for when it comes on screen")
        Check(world.Last(hiddenSlot).feature == late, label .. "late feature: as that feature's button")
        Equal(world.lateRefreshes, 0, label .. "late feature: its own Refresh() is not called")
        Equal(world.lateInits, nil, label .. "late feature: nor its Init()")
        Equal(#world.client.errors, 0, label .. "bag slots and the late feature: no error")

        -- 13.
        local auctionRows = core:GetFeature("DaylightUIAuction")
        Check(auctionRows ~= nil, label .. "auction: the file registers its feature")
        local rowNoted = auctionRows and auctionRows.hookPointsNoted or {}
        for _, point in ipairs({ "DaylightUI.API.For", "DaylightUI.API.For(addon).Hook", "DaylightUI.Win.Parts.SetItemIcon",
            "DaylightUI.Win.Parts.SetItemIcon hooked" }) do
            Equal(rowNoted[point] and rowNoted[point].found, 1, label .. "auction: the hook point " .. point .. " is noted as found")
        end
        Equal(world.hookOwner, "CaerdonWardrobe", label .. "auction: the hook is made under this addon's name")

        local resultKey = { itemID = ARROWS, itemLevel = 16, itemSuffix = 0, battlePetSpeciesID = 0 }
        local result = world.Row({ kind = "line", key = tostring(ARROWS), base = tostring(ARROWS), itemID = ARROWS,
            itemKey = resultKey, qty = 3, unit = 2200 })
        local r, g, b = world.FillRow(result)
        Equal(table.concat({ r, g, b }, " "), "0.1 0.2 0.3", label .. "auction: Daylight UI's function still answers its caller")
        local asked = world.LastOn(result)
        Equal(asked.id, ARROWS, label .. "auction: a search result's row is asked for with its item")
        Check(asked.button ~= nil and asked.button ~= result, label .. "auction: on a frame of this addon's, not on the row")
        Check(asked.feature == auctionRows, label .. "auction: as this feature's button")
        Equal(asked.key, "row-" .. ARROWS .. "-16", label .. "auction: under the row's key and the listing's level")
        Check(asked.locationInfo and asked.locationInfo.itemKey == resultKey, label .. "auction: with the auction house's key, for its tooltip")
        Equal(asked.item and asked.item.extraData and asked.item.extraData.overrideItemLevel, 16,
            label .. "auction: the item is the Auction feature's for that key (the listing's level beside it)")
        Equal((asked.options or {}).statusProminentSize, core:GetSlotStatusSize(28, 28), label .. "auction: placement: sized to the row's icon")
        Equal((asked.options or {}).keepInsideWhenClipped, true, label .. "auction: placement: inside where the row leaves no room")
        Equal((asked.options or {}).slotScale, core:GetSlotScale(28, 28), label .. "auction: placement: the texts sized to the row's icon too")
        Equal((asked.options or {}).clipCutAllowed, 0.1, label .. "auction: placement: a tenth of the icon may be cut off before it moves inside")
        Equal((asked.options or {}).fixedLayout, nil, label .. "auction: placement: by the player's layout")
        Equal((asked.options or {}).overrideStatusPosition, nil, label .. "auction: placement: the icon where the player put it")
        Equal(auctionRows.GetLayoutNote, nil, label .. "auction: the layout editor has nothing to say of the rows")
        local askedItem13, askedLine13 = core:GetAskedOf(result)
        Check(askedItem13 ~= nil and askedItem13 == asked.item, label .. "auction: the Debug Frame finds what was asked of the row from the row itself")
        Check(type(askedLine13) == "string" and askedLine13:find("DaylightUIAuction", 1, true) ~= nil,
            label .. "auction: and by which window")
        local shown = auctionRows:GetDisplayInfo(asked.button, asked.item, auctionRows, asked.locationInfo, asked.options, "own")
        Equal(shown and shown.bindingStatus and shown.bindingStatus.shouldShow, false, label .. "auction: rules: the Auction feature's answer (no binding text)")
        Equal(shown and shown.statusIcon, nil, label .. "auction: rules: and the whole of a draw on the one button")

        world.FillRow(result)
        Equal(world.TimesAskedOn(result), 1, label .. "auction: a row filled again as it was asks for nothing")
        result.data = { kind = "line", key = tostring(BREAD), itemID = BREAD,
            itemKey = { itemID = BREAD, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } }
        world.FillRow(result)
        Equal(world.LastOn(result).id, BREAD, label .. "auction: a row that shows another result is asked for with it")
        Check(world.LastOn(result).button == asked.button, label .. "auction: on the same frame")

        -- A result that names a suffix. The client's link for the key is the item's without
        -- it; on WoW Forever the client also has a real piece of the key's, and the row is
        -- that piece where it is the key's item.
        Equal(world.samplesAsked, nil, label .. "auction: no sample is asked for a key with no suffix")
        world.keyNames = { [301] = "Sold Thing " .. KNIFE, [302] = "Sold Thing " .. KNIFE .. " of the Bear" }
        world.samples = { [301] = KNIFE, [302] = KNIFE, [303] = BREAD }
        local function Suffixed(suffix)
            local row = world.Row({ kind = "line", key = KNIFE .. ":" .. suffix, itemID = KNIFE,
                itemKey = { itemID = KNIFE, itemLevel = 5, itemSuffix = suffix, battlePetSpeciesID = 0 } })
            world.FillRow(row)
            local item = world.LastOn(row).item
            return item, item and item.extraData or {}
        end
        local equipment = world.env.CaerdonEquipment
        local ownItem, ownExtra = Suffixed(301)
        Equal(ownExtra.keySuffix, 301, label .. "auction: a suffixed result: the key's suffix goes beside the item")
        Equal(ownExtra.overrideItemLevel, 5, label .. "auction: a suffixed result: and the listing's level")
        if flavor == "forever" then
            Check(world.SampleLink(KNIFE) ~= world.game.Link(KNIFE), label .. "(the scenario's sample link is a text of its own)")
            Equal(ownItem and ownItem:GetItemLink(), world.SampleLink(KNIFE), label .. "auction: a suffixed result is the real piece the client has for its key")
            Equal(equipment:IsKnownByItsOwnLink(ownItem), true, label .. "auction: which is the row's own piece: its name is the key's")
            local otherName = Suffixed(302)
            Equal(equipment:IsKnownByItsOwnLink(otherName), false, label .. "auction: a sample of another name is not the row's own piece")
            local otherItem = Suffixed(303)
            Check(otherItem and otherItem:GetItemID() == KNIFE and otherItem:GetItemLink() ~= world.SampleLink(BREAD),
                label .. "auction: a sample that is another item is not used")
            local noSample = Suffixed(304)
            Check(noSample and noSample:GetItemID() == KNIFE, label .. "auction: with no sample the row is the item of its key, as before")
            Equal(equipment:IsKnownByItsOwnLink(noSample), false, label .. "auction: and not known by its own link")
        else
            Equal(world.samplesAsked, nil, label .. "auction: a client without the call is not asked")
            Equal(equipment:IsKnownByItsOwnLink((Suffixed(302))), false, label .. "auction: a result named with a suffix is known by the key's link there, as before")
            Equal(world.samplesAsked, nil, label .. "auction: (and still nothing asked)")
        end

        local mine = world.Row({ kind = "line", auctionID = 77, key = KNIFE .. ":-15", itemID = KNIFE, qty = 1, unit = 500 })
        world.FillRow(mine)
        Equal(world.LastOn(mine).id, KNIFE, label .. "auction: a row of the toon's own auctions is asked for with its item")
        Equal(world.LastOn(mine).key, "row-" .. KNIFE .. ":-15-0", label .. "auction: under its key")

        -- A row of another kind (were it to carry an item), a row with no item, a tile, a
        -- frame of no table. Each has its icon and nothing else on it.
        local step = world.Row({ kind = "step", itemID = ARROWS, qty = 2, unit = 2200 })
        local noItem = world.Row({ kind = "line", qty = 2 })
        local tile = world.Row(nil)
        tile.spec = { texture = 134400 }
        tile.data = { kind = "line", itemID = ARROWS }
        local plain = world.Row({ kind = "line", itemID = ARROWS })
        plain.index = nil
        for _, other in ipairs({ step, noItem, tile, plain }) do
            world.FillRow(other)
        end
        world.parts.SetItemIcon(nil, 134400, 1)
        world.parts.SetItemIcon("a word", 134400, 1)
        Equal(world.TimesAskedOn(step) + world.TimesAskedOn(noItem) + world.TimesAskedOn(tile) + world.TimesAskedOn(plain), 0,
            label .. "auction: a frame that is no item's row is not asked for")
        Equal(step:GetNumChildren() + noItem:GetNumChildren() + tile:GetNumChildren() + plain:GetNumChildren(), 4,
            label .. "auction: and no frame of this addon's is made on it")
        Equal(#world.client.errors, 0, label .. "auction: no error")

        -- 14.
        local page = world.client:NewFrame("Frame")
        local hiddenRow = world.Row({ kind = "line", key = tostring(ARROWS), itemID = ARROWS }, page)
        world.FillRow(hiddenRow)
        world.client:SetFrameShown(page, false)
        local resultBefore, hiddenRowBefore = world.TimesAskedOn(result), world.TimesAskedOn(hiddenRow)
        auctionRows:Refresh()
        world.client:Tick(3)
        Equal(world.TimesAskedOn(result), resultBefore + 1, label .. "auction: a refresh asks again for a row on screen")
        Equal(world.LastOn(result).id, BREAD, label .. "auction: with what it shows")
        Equal(world.TimesAskedOn(hiddenRow), hiddenRowBefore, label .. "auction: a row that is not on screen is not asked for")
        world.client:SetFrameShown(page, true)
        world.client:Tick(3)
        Equal(world.TimesAskedOn(hiddenRow), hiddenRowBefore + 1, label .. "auction: and is asked for when its page comes back")
        world.FillRow(result)
        Equal(world.TimesAskedOn(result), resultBefore + 1, label .. "auction: the fill after a refresh's ask asks for nothing")
        Equal(#world.client.errors, 0, label .. "auction: no error at a refresh")

        -- 16.
        local mail = core:GetFeature("DaylightUIMail")
        Check(mail ~= nil, label .. "mail: the file registers its feature")
        local mailNoted = mail and mail.hookPointsNoted or {}
        local declared = mail and mail.integration and mail.integration.hookPoints or {}
        Equal(#declared, 10, label .. "mail: ten hook points are declared")
        for _, point in ipairs(declared) do
            Equal(mailNoted[point] and mailNoted[point].found, 1, label .. "mail: the hook point " .. point .. " is noted as found")
        end
        local mailOwners = {}
        for _, owner in pairs(world.hookOwners) do
            mailOwners[#mailOwners + 1] = owner
        end
        Equal(table.concat(mailOwners, ", "), "CaerdonWardrobe, CaerdonWardrobe, CaerdonWardrobe, CaerdonWardrobe, CaerdonWardrobe, CaerdonWardrobe",
            label .. "mail: its two hooks and its wrap are made under this addon's name (beside the rows', the quests' and the recipe pane's hooks)")
        local gameMail = core:GetFeature("Mail")
        Check(mail:GetDisplayRules() ~= nil and mail:GetDisplayRules() == gameMail:GetDisplayRules(),
            label .. "mail: rules: the Mail feature's display rules")
        Equal(mail:GetStatusRules(), gameMail:GetStatusRules(), label .. "mail: rules: and its status rules")

        -- 17. Three letters: arrows and a knife with an empty place between, nothing, bread.
        world.mailbox = { { [1] = { ARROWS, 20 }, [3] = { KNIFE } }, {}, { [2] = { BREAD } } }
        world.FillInbox(1)
        local firstTile, secondTile = world.MailTile(1), world.MailTile(2)
        local onFirst, onSecond = world.LastOn(firstTile), world.LastOn(secondTile)
        Equal(onFirst.id, ARROWS, label .. "mail: a letter's tile is asked for with its attachment")
        Check(onFirst.button ~= nil and onFirst.button ~= firstTile, label .. "mail: on a frame of this addon's, not on the tile")
        Check(onFirst.feature == mail, label .. "mail: as this feature's button")
        Equal(onFirst.key, "open-1-1", label .. "mail: under the letter and the attachment's place")
        Equal(onFirst.item and onFirst.item.extraData and onFirst.item.extraData.ownCopy, true,
            label .. "mail: as a copy the toon holds")
        Equal(onSecond.id, KNIFE, label .. "mail: the tile after an empty place is the next attachment the letter holds")
        Equal(onSecond.key, "open-1-3", label .. "mail: under that attachment's place")
        Equal((onFirst.options or {}).statusProminentSize, core:GetSlotStatusSize(34, 34), label .. "mail: placement: sized to the tile's icon")
        Equal((onFirst.options or {}).keepInsideWhenClipped, true, label .. "mail: placement: inside where the letter leaves no room")
        Equal((onFirst.options or {}).fixedLayout, nil, label .. "mail: placement: a tile follows the player's layout")
        Equal((onFirst.options or {}).slotScale, core:GetSlotScale(34, 34), label .. "mail: placement: the texts sized to the tile's icon too")
        Equal((onFirst.options or {}).clipCutAllowed, 0.1, label .. "mail: placement: a tenth of the icon may be cut off before it moves inside")
        Equal((onFirst.options or {}).hasCount, true, label .. "mail: placement: a stack has a count")
        Equal((onSecond.options or {}).hasCount, false, label .. "mail: placement: one of an item has none")
        local tooltipsBefore = #world.tooltipsAsked
        mail:GetTooltipData(nil, onSecond.locationInfo)
        Equal(world.tooltipsAsked[tooltipsBefore + 1], "inbox:1:3", label .. "mail: the tooltip of a tile's copy is the game's for the letter and the place")
        Check(core:GetAskedOf(firstTile) ~= nil and core:GetAskedOf(firstTile) == onFirst.item,
            label .. "mail: the Debug Frame finds what was asked of the tile from the tile itself")
        Equal(world.inboxPage.letter.pieces[1]:GetNumChildren() + world.inboxPage.letter.pieces[2]:GetNumChildren(), 1,
            label .. "mail: the letter's head and its text get no frame of this addon's (the head's one child is its icon)")

        world.FillInbox(1)
        Equal(world.TimesAskedOn(firstTile) + world.TimesAskedOn(secondTile), 2, label .. "mail: a letter filled again as it was asks for nothing")
        -- The arrows are taken: the knife moves to the first tile, the second is hidden.
        world.mailbox[1][1] = nil
        local clearedBefore17 = world.cleared[onSecond.button] or 0
        world.FillInbox(1)
        Equal(world.LastOn(firstTile).id, KNIFE, label .. "mail: a tile that holds another attachment is asked for with it")
        Equal(world.LastOn(firstTile).key, "open-1-3", label .. "mail: under its place in the letter")
        Check(world.LastOn(firstTile).button == onFirst.button, label .. "mail: on the same frame")
        Check((world.cleared[onSecond.button] or 0) > clearedBefore17, label .. "mail: a tile that is hidden is cleared")
        Equal(core:GetAskedOf(secondTile), nil, label .. "mail: and nothing is remembered as asked of it")
        world.FillInbox(3)
        Equal(world.LastOn(firstTile).id, BREAD, label .. "mail: another letter picked, the tile is asked for with its attachment")
        Equal(world.LastOn(firstTile).key, "open-3-2", label .. "mail: under that letter")
        -- A tile that does not say the attachment's name is not this addon's to guess at.
        local askedBefore17 = world.TimesAskedOn(firstTile)
        world.FillInbox(3, nil, 2)
        Equal(world.TimesAskedOn(firstTile), askedBefore17, label .. "mail: a tile whose name is not its attachment's is not asked for")
        Equal(core:GetAskedOf(firstTile), nil, label .. "mail: and is cleared")
        world.FillInbox(3)
        Equal(world.TimesAskedOn(firstTile), askedBefore17 + 1, label .. "mail: named as its attachment again, it is asked for")
        world.FillInbox(nil)
        Equal(core:GetAskedOf(firstTile), nil, label .. "mail: no letter picked, the tile is cleared")
        Equal(#world.client.errors, 0, label .. "mail: no error at a letter")

        -- 18.
        local firstLine, secondLine, thirdLine = world.MailLine(1), world.MailLine(2), world.MailLine(3)
        local onLine = world.LastOn(firstLine)
        Equal(onLine.id, KNIFE, label .. "mail: a letter's line is asked for with the letter's first item")
        Check(onLine.button ~= nil and onLine.button ~= firstLine, label .. "mail: on a frame of this addon's, not on the line")
        Equal(onLine.key, "inbox-1", label .. "mail: under the letter's place in the inbox")
        Equal(onLine.item and onLine.item.extraData and onLine.item.extraData.ownCopy, true, label .. "mail: a line's item is a copy the toon holds")
        Equal((onLine.options or {}).statusProminentSize, core:GetSlotStatusSize(28, 28), label .. "mail: placement: a line's icon is sized to the line's")
        Equal((onLine.options or {}).slotScale, core:GetSlotScale(28, 28), label .. "mail: placement: the texts sized to it too")
        Equal((onLine.options or {}).fixedLayout, nil, label .. "mail: placement: by the player's layout")
        Equal((onLine.options or {}).keepInsideWhenClipped, true, label .. "mail: placement: inside where the list leaves no room")
        Equal(world.TimesAskedOn(secondLine), 0, label .. "mail: a letter with no item has nothing asked for its line")
        Equal(secondLine:GetNumChildren(), 1, label .. "mail: and no frame of this addon's on it")
        Equal(world.LastOn(thirdLine).id, BREAD, label .. "mail: each line by its own letter")
        Equal(world.LastOn(thirdLine).key, "inbox-3", label .. "mail: under that letter's place")
        tooltipsBefore = #world.tooltipsAsked
        mail:GetTooltipData(nil, world.LastOn(thirdLine).locationInfo)
        Equal(world.tooltipsAsked[tooltipsBefore + 1], "inbox:3:nil", label .. "mail: a line's tooltip is the game's for the letter's first item")
        Check(core:GetAskedOf(thirdLine) == world.LastOn(thirdLine).item, label .. "mail: the Debug Frame finds what was asked of the line")
        local linesAsked = world.TimesAskedOn(firstLine) + world.TimesAskedOn(thirdLine)
        world.FillInbox(nil)
        Equal(world.TimesAskedOn(firstLine) + world.TimesAskedOn(thirdLine), linesAsked, label .. "mail: a list filled again as it was asks for nothing")
        -- A filter hides the first letter: the first line is the letter with nothing, the
        -- second the bread's, and the third is hidden.
        world.FillInbox(nil, { [1] = true })
        Equal(core:GetAskedOf(firstLine), nil, label .. "mail: a line that shows a letter with no item is cleared")
        Equal(world.LastOn(secondLine).id, BREAD, label .. "mail: a line is asked for by its letter, not by its place in the list")
        Equal(world.LastOn(secondLine).key, "inbox-3", label .. "mail: under the letter's place in the inbox")
        Equal(core:GetAskedOf(thirdLine), nil, label .. "mail: a line that is hidden is cleared")
        -- The letter with nothing is deleted: the bread's moves up in the inbox.
        world.mailbox = { { [3] = { KNIFE } }, { [2] = { BREAD } } }
        world.FillInbox(nil, nil, nil, { 1, 3 })
        Equal(world.LastOn(secondLine).key, "inbox-2", label .. "mail: a letter that has moved up is asked for at its new place")
        Equal(world.LastOn(firstLine).id, KNIFE, label .. "mail: and the line above it with its own letter again")
        Equal(mail.GetLayoutNote, nil, label .. "mail: the layout editor has nothing to say of the mailbox")
        Equal(#world.client.errors, 0, label .. "mail: no error at the list")

        -- 19.
        world.sending = { [1] = { ARROWS, 5 }, [4] = { BREAD } }
        world.FillSend()
        local sendFirst, sendSecond, sendEmpty = world.SendTile(1), world.SendTile(2), world.SendTile(3)
        Equal(world.LastOn(sendFirst).id, ARROWS, label .. "mail: a tile of the Send page is asked for with the item attached")
        Equal(world.LastOn(sendFirst).key, "send-1", label .. "mail: under its slot")
        Equal((world.LastOn(sendFirst).options or {}).hasCount, true, label .. "mail: with its count")
        Equal(world.LastOn(sendSecond).id, BREAD, label .. "mail: the tile after a free slot is the next item attached")
        Equal(world.LastOn(sendSecond).key, "send-4", label .. "mail: under that slot")
        Equal(world.LastOn(sendSecond).item and world.LastOn(sendSecond).item.extraData.ownCopy, true, label .. "mail: an item being sent is a copy the toon holds")
        tooltipsBefore = #world.tooltipsAsked
        mail:GetTooltipData(nil, world.LastOn(sendSecond).locationInfo)
        Equal(world.tooltipsAsked[tooltipsBefore + 1], "send:4", label .. "mail: its tooltip is the game's for the slot")
        Equal(world.TimesAskedOn(sendEmpty), 0, label .. "mail: the tile to drop an item on is not asked for")
        Equal(sendEmpty:GetNumChildren(), 1, label .. "mail: and gets no frame of this addon's")
        world.FillSend()
        Equal(world.TimesAskedOn(sendFirst) + world.TimesAskedOn(sendSecond), 2, label .. "mail: a Send page filled again as it was asks for nothing")
        -- The arrows are taken back: the bread is on the first tile, the second is the empty one.
        world.sending[1] = nil
        world.FillSend()
        Equal(world.LastOn(sendFirst).id, BREAD, label .. "mail: a tile that holds another item is asked for with it")
        Equal(core:GetAskedOf(sendSecond), nil, label .. "mail: the tile that is the empty one now is cleared")
        local sendAsked = world.TimesAskedOn(sendFirst)
        world.FillSend(4)
        Equal(world.TimesAskedOn(sendFirst), sendAsked, label .. "mail: a tile of the Send page whose name is not its item's is not asked for")
        Equal(core:GetAskedOf(sendFirst), nil, label .. "mail: and is cleared")
        world.FillSend()
        Equal(world.LastOn(sendFirst).id, BREAD, label .. "mail: named as its item again, it is asked for")
        Equal(#world.client.errors, 0, label .. "mail: no error at the Send page")

        -- 20. The default refresh: what the feature asked for is asked for again by the core.
        world.FillInbox(2)
        local openTile = world.MailTile(1)
        Equal(world.LastOn(openTile).id, BREAD, label .. "mail: (the bread's letter is picked)")
        local hiddenPage = world.MailPage("sendTiles")
        world.client:SetFrameShown(hiddenPage, false)
        local tileBefore, lineBefore, sendBefore = world.TimesAskedOn(openTile), world.TimesAskedOn(secondLine), world.TimesAskedOn(sendFirst)
        mail:Refresh()
        world.client:Tick(3)
        Equal(world.TimesAskedOn(openTile), tileBefore + 1, label .. "mail: a refresh asks again for a tile on screen")
        Equal(world.TimesAskedOn(secondLine), lineBefore + 1, label .. "mail: and for a line")
        Equal(world.LastOn(openTile).id, BREAD, label .. "mail: with what it shows")
        Equal(world.TimesAskedOn(sendFirst), sendBefore, label .. "mail: a tile that is not on screen is not asked for")
        world.client:SetFrameShown(hiddenPage, true)
        world.client:Tick(3)
        Equal(world.TimesAskedOn(sendFirst), sendBefore + 1, label .. "mail: and is asked for when its page comes back")
        world.FillInbox(2)
        Equal(world.TimesAskedOn(openTile), tileBefore + 1, label .. "mail: the fill after a refresh asks for nothing")
        Equal(#world.client.errors, 0, label .. "mail: no error at a refresh")

        -- 21.
        local function MailWorld(apiIs)
            local other = Start(flavor, apiIs)
            other.mailbox = { { [1] = { ARROWS } } }
            other.sending = { [1] = { BREAD } }
            other.FillInbox(1)
            other.FillSend()
            local feature = other.core:GetFeature("DaylightUIMail")
            return other, feature, feature and feature.hookPointsNoted or {}
        end
        local unwrapped, _, unwrappedNoted = MailWorld("the wrap refused")
        Equal(unwrappedNoted["DaylightUI.Mail.Inbox.LineIds wrapped"] and unwrappedNoted["DaylightUI.Mail.Inbox.LineIds wrapped"].missing, 1,
            label .. "a wrap Daylight UI does not take: noted as missing")
        Equal(unwrapped.TimesAskedOn(unwrapped.MailLine(1)), 0, label .. "a wrap Daylight UI does not take: no line is asked for")
        Equal(unwrapped.LastOn(unwrapped.MailTile(1)).id, ARROWS, label .. "a wrap Daylight UI does not take: the letter's tiles are asked for all the same")
        Equal(unwrapped.LastOn(unwrapped.SendTile(1)).id, BREAD, label .. "a wrap Daylight UI does not take: and the Send page's")
        Equal(#unwrapped.client.errors, 0, label .. "a wrap Daylight UI does not take: no error")
        local noIds, _, noIdsNoted = MailWorld("without LineIds")
        Equal(noIdsNoted["DaylightUI.Mail.Inbox.LineIds"] and noIdsNoted["DaylightUI.Mail.Inbox.LineIds"].missing, 1,
            label .. "ids that are gone: noted as missing")
        Equal(noIdsNoted["DaylightUI.Mail.Inbox.LineIds wrapped"], nil, label .. "ids that are gone: no wrap is tried")
        Equal(noIds.TimesAskedOn(noIds.MailLine(1)), 0, label .. "ids that are gone: no line is asked for")
        Equal(noIds.LastOn(noIds.MailTile(1)).id, ARROWS, label .. "ids that are gone: the letter's tiles are asked for all the same")
        Equal(#noIds.client.errors, 0, label .. "ids that are gone: no error")
        local noPicked, _, noPickedNoted = MailWorld("without Picked")
        Equal(noPickedNoted["DaylightUI.Mail.Inbox.Picked"] and noPickedNoted["DaylightUI.Mail.Inbox.Picked"].missing, 1,
            label .. "no word of the letter picked: noted as missing")
        Equal(noPicked.TimesAskedOn(noPicked.MailTile(1)), 0, label .. "no word of the letter picked: no tile of a letter is asked for")
        Equal(noPicked.LastOn(noPicked.MailLine(1)).id, ARROWS, label .. "no word of the letter picked: the lines are asked for all the same")
        Equal(#noPicked.client.errors, 0, label .. "no word of the letter picked: no error")
        local unhooked, unhookedMail, unhookedNoted = MailWorld("the hook refused")
        Equal(unhookedNoted["DaylightUI.Mail.Inbox.Render hooked"] and unhookedNoted["DaylightUI.Mail.Inbox.Render hooked"].missing, 1,
            label .. "a hook Daylight UI does not take: the inbox's is noted as missing")
        Equal(unhookedNoted["DaylightUI.Mail.Send.Render hooked"] and unhookedNoted["DaylightUI.Mail.Send.Render hooked"].missing, 1,
            label .. "a hook Daylight UI does not take: and the Send page's")
        Equal(unhooked.TimesAskedOn(unhooked.MailTile(1)) + unhooked.TimesAskedOn(unhooked.MailLine(1)) + unhooked.TimesAskedOn(unhooked.SendTile(1)), 0,
            label .. "a hook Daylight UI does not take: nothing of the mailbox is asked for")
        Equal(#unhooked.client.errors, 0, label .. "a hook Daylight UI does not take: no error at the mailbox")
        local noMail = Start(flavor, "without the mailbox")
        local noMailNoted = noMail.core:GetFeature("DaylightUIMail").hookPointsNoted or {}
        for _, point in ipairs({ "DaylightUI.Mail.Inbox.Render", "DaylightUI.Mail.Inbox.Picked", "DaylightUI.Mail.Inbox.LineIds",
            "DaylightUI.Mail.Send.Render" }) do
            Equal(noMailNoted[point] and noMailNoted[point].missing, 1, label .. "a mailbox that is gone: " .. point .. " is noted as missing")
        end
        Equal(#noMail.client.errors, 0, label .. "a mailbox that is gone: no error")
        Equal(noMail.Listening("FrameStyled"), 2, label .. "a mailbox that is gone: the vendor's tiles and the recipes' lines are attached all the same")
        local noCraftNoted = noMail.core:GetFeature("DaylightUICraft").hookPointsNoted or {}
        Equal(noCraftNoted["DaylightUI.Craft.Recipe.Fill"] and noCraftNoted["DaylightUI.Craft.Recipe.Fill"].missing, 1,
            label .. "a profession window that is gone: the pane's fill is noted as missing")
        Equal(noCraftNoted["DaylightUI.Craft.Recipe.Fill hooked"], nil, label .. "a profession window that is gone: no hook is tried")

        -- 22.
        local quests = core:GetFeature("DaylightUIQuests")
        Check(quests ~= nil, label .. "quests: the file registers its feature")
        local questNoted = quests and quests.hookPointsNoted or {}
        for _, point in ipairs({ "DaylightUI.API.For", "DaylightUI.API.For(addon).Hook", "DaylightUI.Win.Parts.SetItemIcon",
            "DaylightUI.Win.Parts.SetItemIcon hooked" }) do
            Equal(questNoted[point] and questNoted[point].found, 1, label .. "quests: the hook point " .. point .. " is noted as found")
        end
        local questLog = core:GetFeature("QuestLog")
        Check(quests:GetDisplayRules() ~= nil and quests:GetDisplayRules() == questLog:GetDisplayRules(),
            label .. "quests: rules: the QuestLog feature's display rules")
        Equal(quests:GetStatusRules(), questLog:GetStatusRules(), label .. "quests: rules: and its status rules")

        -- A tile of a page, as Daylight UI has it when it sets its icon: its spec on it.
        local function RewardTile(spec)
            local tile = world.Row(nil)
            tile.iconSize, tile.spec = 34, spec
            return tile
        end
        local function LinkOf(id)
            return function() return world.game.Link(id) end
        end
        local reward = RewardTile({ name = "Sold Thing", count = 1, quality = 1, link = LinkOf(KNIFE) })
        world.FillRow(reward)
        local onReward = world.LastOn(reward)
        Equal(onReward.id, KNIFE, label .. "quests: a tile that names an item's link is asked for with that item")
        Check(onReward.button ~= nil and onReward.button ~= reward, label .. "quests: on a frame of this addon's, not on the tile")
        Check(onReward.feature == quests, label .. "quests: as this feature's button")
        Equal(onReward.key, "reward-" .. world.game.Link(KNIFE), label .. "quests: under the item's link")
        Equal((onReward.options or {}).statusProminentSize, core:GetSlotStatusSize(34, 34), label .. "quests: placement: sized to the tile's icon")
        Equal((onReward.options or {}).keepInsideWhenClipped, true, label .. "quests: placement: inside where the page leaves no room")
        Equal((onReward.options or {}).fixedLayout, nil, label .. "quests: placement: a tile follows the player's layout")
        Equal((onReward.options or {}).slotScale, core:GetSlotScale(34, 34), label .. "quests: placement: the texts sized to the tile's icon too")
        Equal((onReward.options or {}).hasCount, false, label .. "quests: placement: one of an item has no count")
        Check(core:GetAskedOf(reward) ~= nil and core:GetAskedOf(reward) == onReward.item,
            label .. "quests: the Debug Frame finds what was asked of the tile from the tile itself")
        Equal(quests:GetTooltipData(onReward.item, onReward.locationInfo), nil, label .. "quests: the tooltip is the link's")
        world.FillRow(reward)
        Equal(world.TimesAskedOn(reward), 1, label .. "quests: a tile filled again as it was asks for nothing")
        reward.spec = { name = "Sold Thing", count = 5, quality = 1, link = LinkOf(BREAD) }
        world.FillRow(reward)
        Equal(world.LastOn(reward).id, BREAD, label .. "quests: a tile that holds another item is asked for with it")
        Equal((world.LastOn(reward).options or {}).hasCount, true, label .. "quests: placement: a stack has a count")
        Check(world.LastOn(reward).button == onReward.button, label .. "quests: on the same frame")
        local countBefore = world.TimesAskedOn(reward)
        reward.spec = { name = "Sold Thing", count = 1, quality = 1, link = LinkOf(BREAD) }
        world.FillRow(reward)
        Equal(world.TimesAskedOn(reward), countBefore + 1, label .. "quests: a tile that lost its count is asked for again")
        Equal((world.LastOn(reward).options or {}).hasCount, false, label .. "quests: without the count")
        -- A spell the quest teaches has a link too, and is no item.
        local rewardAsked = world.TimesAskedOn(reward)
        reward.spec = { name = "A Spell", link = function() return "|cff71d5ff|Hspell:2061:0|h[A Spell]|h|r" end }
        world.FillRow(reward)
        Equal(world.TimesAskedOn(reward), rewardAsked, label .. "quests: a tile that holds a spell is not asked for")
        Equal(core:GetAskedOf(reward), nil, label .. "quests: and what was on it is cleared")
        -- The game has no link yet; then it has.
        local late22, lateLink = nil, nil
        late22 = RewardTile({ name = "Loading", link = function() return lateLink end })
        world.FillRow(late22)
        Equal(world.TimesAskedOn(late22), 0, label .. "quests: a tile the game has no link for yet is not asked for")
        lateLink = world.game.Link(ARROWS)
        world.FillRow(late22)
        Equal(world.LastOn(late22).id, ARROWS, label .. "quests: the link there, it is asked for")
        -- Tiles that are not a quest's: a sample (no link to ask for), a vendor's, a material
        -- of a recipe, and a letter's (which names none).
        local sampleTile = RewardTile({ name = "Sample" })
        local shopTile = RewardTile({ name = "Sold Thing", link = LinkOf(KNIFE), shopItem = {} })
        local material = RewardTile({ name = "Sold Thing", link = LinkOf(KNIFE), mat = {} })
        for _, other in ipairs({ sampleTile, shopTile, material }) do
            world.FillRow(other)
        end
        Equal(world.TimesAskedOn(sampleTile) + world.TimesAskedOn(shopTile) + world.TimesAskedOn(material), 0,
            label .. "quests: a sample's, a vendor's and a recipe's tile are not asked for")
        Equal(sampleTile:GetNumChildren() + shopTile:GetNumChildren() + material:GetNumChildren(), 3,
            label .. "quests: and no frame of this addon's is made on them")
        local lateBefore = world.TimesAskedOn(late22)
        quests:Refresh()
        world.client:Tick(3)
        Equal(world.TimesAskedOn(late22), lateBefore + 1, label .. "quests: a refresh asks again for a tile on screen")
        world.FillRow(late22)
        Equal(world.TimesAskedOn(late22), lateBefore + 1, label .. "quests: the fill after a refresh asks for nothing")
        Equal(#world.client.errors, 0, label .. "quests: no error")

        -- 23.
        local rolls = core:GetFeature("DaylightUIRolls")
        Check(rolls ~= nil, label .. "rolls: the file registers its feature")
        local rollNoted = rolls and rolls.hookPointsNoted or {}
        for _, point in ipairs({ "DaylightUI.API.For", "DaylightUI.API.For(addon).Paint", "DaylightUI.API.On", "DaylightUI.API.Attach" }) do
            Equal(rollNoted[point] and rollNoted[point].found, 1, label .. "rolls: the hook point " .. point .. " is noted as found")
        end
        Equal(world.PaintersOf("rollcard"), "CaerdonWardrobe", label .. "rolls: one painter of the roll cards, under this addon's name")
        local groupLoot = core:GetFeature("GroupLoot")
        Check(rolls:GetDisplayRules() ~= nil and rolls:GetDisplayRules() == groupLoot:GetDisplayRules(),
            label .. "rolls: rules: the GroupLoot feature's display rules")

        local card = world.Tile()
        local cardHolder = world.holders[card]
        world.PaintCard(card, { rollID = 7, link = world.game.Link(KNIFE), done = false, sample = false })
        local onCard = world.Last(cardHolder)
        Equal(onCard.id, KNIFE, label .. "rolls: a card is asked for with the item rolled for")
        Check(onCard.feature == rolls, label .. "rolls: as this feature's button")
        Equal(world.TimesAsked(card), 0, label .. "rolls: on the frame Daylight UI attaches, not on the card itself")
        Equal(onCard.key, "roll-7", label .. "rolls: under the roll's id")
        Check((onCard.options or {}).relativeFrame == world.icons[card], label .. "rolls: placement: over the card's icon")
        Equal((onCard.options or {}).statusProminentSize, core:GetSlotStatusSize(30, 30), label .. "rolls: placement: sized to that icon")
        Equal((onCard.options or {}).slotScale, core:GetSlotScale(30, 30), label .. "rolls: placement: the texts sized to it too")
        Check(core:GetAskedOf(card) ~= nil and core:GetAskedOf(card) == onCard.item,
            label .. "rolls: the Debug Frame finds what was asked of the card from the frame its icon is on")
        local tooltipsBefore23 = #world.tooltipsAsked
        rolls:GetTooltipData(nil, onCard.locationInfo)
        Equal(world.tooltipsAsked[tooltipsBefore23 + 1], "roll:7", label .. "rolls: the tooltip of a roll of the game's is the game's for it")
        -- A pick, a roll: the card is painted again as it was.
        world.PaintCard(card, { rollID = 7, link = world.game.Link(KNIFE), done = false, sample = false })
        Equal(world.TimesAsked(cardHolder), 1, label .. "rolls: a card painted again as it was asks for nothing")
        world.PaintCard(card, { rollID = 7, link = world.game.Link(KNIFE), done = true, sample = false })
        Equal(world.TimesAsked(cardHolder), 2, label .. "rolls: a roll that is over is asked for again")
        Equal(rolls:GetTooltipData(nil, world.Last(cardHolder).locationInfo), nil, label .. "rolls: and its tooltip is the link's")
        Equal(#world.tooltipsAsked, tooltipsBefore23 + 1, label .. "rolls: (the game was not asked for it)")
        world.PaintCard(card, { rollID = 8, link = world.game.Link(BREAD), done = false, sample = false })
        Equal(world.Last(cardHolder).id, BREAD, label .. "rolls: the next roll on a card is asked for with its item")
        Equal(world.Last(cardHolder).key, "roll-8", label .. "rolls: under its own id")
        world.Send("FrameRemoved", "bagslot", card, "0:1", false)
        world.client:Tick(3)
        Check(core:GetAskedOf(cardHolder) ~= nil, label .. "rolls: another kind's frame leaving clears nothing")
        local cardCleared = world.cleared[cardHolder] or 0
        world.Send("FrameRemoved", "rollcard", card, 8, false)
        world.client:Tick(3)
        Equal(core:GetAskedOf(cardHolder), nil, label .. "rolls: a card whose roll has left is cleared")
        Equal((world.cleared[cardHolder] or 0) - cardCleared, 1, label .. "rolls: what was drawn on it with it")
        world.PaintCard(card, { rollID = 8, link = world.game.Link(BREAD), done = false, sample = false })
        Equal(world.TimesAsked(cardHolder), 4, label .. "rolls: shown again with the roll it had, it is asked for again")
        world.PaintCard(card, nil)
        Equal(core:GetAskedOf(cardHolder), nil, label .. "rolls: a card nothing is said of is cleared")
        local sampleCard = world.Tile()
        world.PaintCard(sampleCard, { rollID = -1, link = world.game.Link(ARROWS), done = false, sample = true })
        Equal(world.Last(world.holders[sampleCard]).id, ARROWS, label .. "rolls: a sample card is asked for with its item")
        Equal(world.Last(world.holders[sampleCard]).locationInfo.isGameRoll, false, label .. "rolls: as no roll of the game's")
        local rebuilt = world.Tile()
        world.PaintCard(rebuilt, { rollID = -4, link = world.game.Link(ARROWS), done = false, sample = false })
        Equal(world.Last(world.holders[rebuilt]).locationInfo.isGameRoll, false, label .. "rolls: nor is one with no id of the game's")
        local foreignCard = world.Tile(false)
        world.PaintCard(foreignCard, { rollID = 9, link = world.game.Link(KNIFE), done = false, sample = false })
        Equal(world.TimesAsked(foreignCard) + world.TimesAsked(world.icons[foreignCard]), 0,
            label .. "rolls: a frame Daylight UI attaches nothing to is not drawn on")
        Equal(#world.client.errors, 0, label .. "rolls: no error")

        -- 24.
        local craft = core:GetFeature("DaylightUICraft")
        Check(craft ~= nil, label .. "craft: the file registers its feature")
        local craftNoted = craft and craft.hookPointsNoted or {}
        local craftDeclared = craft and craft.integration and craft.integration.hookPoints or {}
        Equal(#craftDeclared, 7, label .. "craft: seven hook points are declared")
        for _, point in ipairs(craftDeclared) do
            Equal(craftNoted[point] and craftNoted[point].found, 1, label .. "craft: the hook point " .. point .. " is noted as found")
        end
        local tradeSkill = core:GetFeature("TradeSkill")
        Check(craft:GetDisplayRules() ~= nil and craft:GetDisplayRules() == tradeSkill:GetDisplayRules(),
            label .. "craft: rules: the TradeSkill feature's display rules")

        world.recipes = { [501] = { recipeID = 501, hyperlink = world.game.Link(KNIFE) },
            [502] = { recipeID = 502, hyperlink = world.game.Link(BREAD) }, [503] = { recipeID = 503 } }
        local recipeLine = world.Tile()
        local recipeHolder = world.holders[recipeLine]
        world.Send("FrameStyled", "craftrow", recipeLine, 501, false)
        world.client:Tick(3)
        local onRecipe = world.Last(recipeHolder)
        Equal(onRecipe.id, KNIFE, label .. "craft: a line of the list is asked for with what its recipe makes")
        Check(onRecipe.feature == craft, label .. "craft: as this feature's button")
        Equal(world.TimesAsked(recipeLine), 0, label .. "craft: on the frame Daylight UI attaches, not on the line itself")
        Equal(onRecipe.key, "recipe501", label .. "craft: under the recipe's ID")
        Equal(onRecipe.locationInfo and onRecipe.locationInfo.selectedRecipeID, 501, label .. "craft: with the recipe beside it")
        Check((onRecipe.options or {}).relativeFrame == world.icons[recipeLine], label .. "craft: placement: over the line's icon")
        Equal((onRecipe.options or {}).statusProminentSize, core:GetSlotStatusSize(30, 30), label .. "craft: placement: sized to that icon")
        Equal((onRecipe.options or {}).slotScale, core:GetSlotScale(30, 30), label .. "craft: placement: the texts sized to it too")
        Equal((onRecipe.options or {}).clipCutAllowed, 0.1, label .. "craft: placement: a tenth of the icon may be cut off before it moves inside")
        Equal((onRecipe.options or {}).fixedLayout, nil, label .. "craft: placement: by the player's layout")
        Equal((onRecipe.options or {}).keepInsideWhenClipped, true, label .. "craft: placement: inside where the list leaves no room")
        Check(core:GetAskedOf(recipeLine) ~= nil and core:GetAskedOf(recipeLine) == onRecipe.item,
            label .. "craft: the Debug Frame finds what was asked of the line from the line itself")
        world.Send("FrameStyled", "craftrow", recipeLine, 501, false)
        world.client:Tick(3)
        Equal(world.TimesAsked(recipeHolder), 1, label .. "craft: a list filled again as it was asks for nothing")
        world.Send("FrameStyled", "craftrow", recipeLine, 502, false)
        world.client:Tick(3)
        Equal(world.Last(recipeHolder).id, BREAD, label .. "craft: a line that shows another recipe is asked for with what that makes")
        Equal(world.Last(recipeHolder).key, "recipe502", label .. "craft: under that recipe's ID")
        world.Send("FrameStyled", "craftrow", recipeLine, 503, false)
        world.client:Tick(3)
        Equal(core:GetAskedOf(recipeHolder), nil, label .. "craft: a line whose recipe names nothing made is cleared")
        world.Send("FrameStyled", "craftrow", recipeLine, 501, false)
        world.client:Tick(3)
        local recipeCleared = world.cleared[recipeHolder] or 0
        world.Send("FrameRemoved", "rollcard", recipeLine, 501, false)
        world.client:Tick(3)
        Check(core:GetAskedOf(recipeHolder) ~= nil, label .. "craft: another kind's frame leaving clears nothing")
        world.Send("FrameRemoved", "craftrow", recipeLine, 501, false)
        world.client:Tick(3)
        Equal(core:GetAskedOf(recipeHolder), nil, label .. "craft: a line that is hidden is cleared")
        Equal((world.cleared[recipeHolder] or 0) - recipeCleared, 1, label .. "craft: what was drawn on it with it")
        local askedBeforeShown = world.TimesAsked(recipeHolder)
        world.Send("FrameStyled", "craftrow", recipeLine, 501, false)
        world.client:Tick(3)
        Equal(world.TimesAsked(recipeHolder), askedBeforeShown + 1, label .. "craft: shown again with the recipe it had, it is asked for again")
        local askedAsRecipe = world.TimesAsked(recipeHolder)
        world.Send("FrameStyled", "bagslot", recipeLine, 502, false)
        world.client:Tick(3)
        Equal(world.TimesAsked(recipeHolder), askedAsRecipe, label .. "craft: another kind's frame is not asked for")

        -- The recipe that is picked.
        local knife, enchant = { id = 501 }, { id = 504, enchant = true }
        world.FillRecipe(knife, world.game.Link(KNIFE))
        local resultLine = world.ResultLine()
        local onResult = world.LastOn(resultLine)
        Equal(onResult.id, KNIFE, label .. "craft: the picked recipe's line is asked for with what it makes")
        Check(onResult.button ~= nil and onResult.button ~= resultLine, label .. "craft: on a frame of this addon's, not on the line")
        Equal(onResult.key, "selectedrecipe501", label .. "craft: under the recipe's ID, apart from its line in the list")
        Equal(onResult.locationInfo and onResult.locationInfo.isSelectedRecipe, true, label .. "craft: as the recipe that is picked")
        Equal((onResult.options or {}).statusProminentSize, core:GetSlotStatusSize(28, 28), label .. "craft: placement: sized to the line's icon")
        Equal((onResult.options or {}).slotScale, core:GetSlotScale(28, 28), label .. "craft: placement: the texts sized to it too")
        Equal((onResult.options or {}).fixedLayout, nil, label .. "craft: placement: by the player's layout")
        Check(core:GetAskedOf(resultLine) == onResult.item, label .. "craft: the Debug Frame finds what was asked of the line")
        world.FillRecipe(knife, world.game.Link(KNIFE))
        Equal(world.TimesAskedOn(resultLine), 1, label .. "craft: a pane filled again as it was asks for nothing")
        world.FillRecipe({ id = 502 }, world.game.Link(BREAD))
        Equal(world.LastOn(resultLine).id, BREAD, label .. "craft: another recipe picked, its line is asked for with what that makes")
        Equal(world.LastOn(resultLine).key, "selectedrecipe502", label .. "craft: under that recipe's ID")
        world.FillRecipe(enchant, nil)
        Equal(core:GetAskedOf(resultLine), nil, label .. "craft: a recipe that makes no item has nothing on its line")
        world.FillRecipe(knife, world.game.Link(KNIFE))
        Equal(world.LastOn(resultLine).id, KNIFE, label .. "craft: (the knife's recipe is picked again)")
        world.FillRecipe(nil)
        Equal(core:GetAskedOf(resultLine), nil, label .. "craft: no recipe picked, the line is cleared")
        -- A line that carries another recipe than the one the pane was filled for.
        local resultAsked = world.TimesAskedOn(resultLine)
        world.FillRecipe(knife, world.game.Link(KNIFE), { id = 505 })
        Equal(world.TimesAskedOn(resultLine), resultAsked, label .. "craft: a first line that is not the picked recipe's is not asked for")
        Equal(craft.GetLayoutNote, nil, label .. "craft: the layout editor has nothing to say of the profession window")
        Equal(#world.client.errors, 0, label .. "craft: no error")

        -- 25. Daylight UI's bags hand a corner and a size of their own with every request; the
        -- player's layout in their place is a setting, off unless it is chosen.
        do
            local config = world.env.CaerdonWardrobeConfig
            Equal(type(config.DaylightUI) == "table" and config.DaylightUI.OwnLayoutInBags, false,
                label .. "bags' layout: the default is Daylight UI's own placement")
            local theirs = { fixedStatusPosition = true, statusProminentSize = 16 }
            local function Ask(slot, index)
                local item = world.env.CaerdonItem:CreateFromBagAndSlot(0, index)
                function item:GetCaerdonItemType() return "Miscellaneous" end
                function item:IsItemEmpty() return false end
                function item:IsItemDataCached() return true end
                function item:GetItemID() return ARROWS end
                function item:GetCaerdonStatus() return true, "own", nil, {}, nil end
                core:UpdateButton(slot, item, late, { bag = 0, slot = index }, theirs)
                world.client:Tick(3)
                return world.drawnWith[slot]
            end
            local slot25 = world.client:NewFrame("Button")
            slot25:SetSize(37, 37)
            Check(Ask(slot25, 21) == theirs, label .. "bags' layout: off, a slot is drawn with what Daylight UI handed")

            local text, boxLabel, choose, chosen = bagSlots:GetLayoutNote()
            Check(type(text) == "string" and text:find("^Daylight UI: ") ~= nil and text:find("do not apply", 1, true) ~= nil,
                label .. "bags' layout: the layout editor is told the icon's layout does not apply in its bags")
            Check(type(boxLabel) == "string" and boxLabel ~= "", label .. "bags' layout: with a box to choose otherwise")
            Equal(chosen, false, label .. "bags' layout: which is not ticked")

            -- The icon as Daylight UI pins it: once, in its corner of the slot.
            local icon = core:GetCaerdonButton(slot25).mogStatus
            rawset(icon, "ClearAllPoints", function(self) rawset(self, "points", nil) end)
            rawset(icon, "SetPoint", function(self, ...) rawset(self, "points", { ... }) end)
            rawset(icon, "GetPoint", function(self)
                local points = rawget(self, "points")
                if points then
                    return points[1], points[2], points[3], points[4], points[5]
                end
            end)
            icon:SetPoint("TOPRIGHT", slot25, "TOPRIGHT", -3, -3)

            choose(true)
            Equal(config.DaylightUI.OwnLayoutInBags, true, label .. "bags' layout: ticking the box is kept in the settings")
            Equal(select(4, bagSlots:GetLayoutNote()), true, label .. "bags' layout: and the box says so")
            Check(not select(1, bagSlots:GetLayoutNote()):find("do not apply", 1, true), label .. "bags' layout: as does the note")
            local ours = Ask(slot25, 21)
            Check(ours ~= nil and ours ~= theirs, label .. "bags' layout: on, a slot is drawn with options of this addon's")
            Equal(ours.fixedStatusPosition, nil, label .. "bags' layout: the icon is the player's layout's to place")
            Equal(ours.statusProminentSize, core:GetSlotStatusSize(37, 37, true), label .. "bags' layout: at a bag slot's size")
            Equal(ours.slotScale, 1, label .. "bags' layout: the texts at a bag slot's size")
            Equal(ours.keepInsideWhenClipped, true, label .. "bags' layout: inside where the bag leaves no room")
            Equal(ours.hasCount, false, label .. "bags' layout: one of an item has no count")
            Check(Ask(slot25, 21) == ours, label .. "bags' layout: the same options at the next request")
            Check(theirs.fixedStatusPosition == true and theirs.statusProminentSize == 16 and theirs.slotScale == nil,
                label .. "bags' layout: nothing is written into Daylight UI's options")
            world.bagCounts = { [21] = 5 }
            Equal(Ask(slot25, 21).hasCount, true, label .. "bags' layout: a stack has a count")
            world.bagCounts = nil
            local big = world.client:NewFrame("Button")
            big:SetSize(48, 48)
            Equal(Ask(big, 22).statusProminentSize, core:GetSlotStatusSize(48, 48, true), label .. "bags' layout: a larger slot has a larger icon")
            -- The slot's first request comes before it holds anything (Daylight UI makes its
            -- widget with it).
            local fresh = world.client:NewFrame("Button")
            fresh:SetSize(37, 37)
            core:UpdateButton(fresh, nil, late, nil, theirs)
            Equal(#world.client.errors, 0, label .. "bags' layout: a request for nothing raises no error")

            -- The core's own asks at a refresh hand the answer back what it answered.
            core:RefreshItems("scenario")
            world.client:Tick(4)
            Check(world.drawnWith[slot25] ~= theirs and world.drawnWith[slot25].daylightOptions == theirs,
                label .. "bags' layout: a refresh asks again with this addon's options, which carry Daylight UI's")
            -- The core has placed the icon by the layout meanwhile.
            icon:ClearAllPoints()
            icon:SetPoint("CENTER", core:GetCaerdonButton(slot25), "TOPLEFT", 4, -4)
            Ask(slot25, 21)
            choose(false)
            core:RefreshItems("scenario")
            world.client:Tick(4)
            Check(world.drawnWith[slot25] == theirs, label .. "bags' layout: off again, a refresh draws with what Daylight UI handed")
            local point, relativeTo, relativePoint, x, y = icon:GetPoint(1)
            Check(point == "TOPRIGHT" and relativeTo == slot25 and relativePoint == "TOPRIGHT" and x == -3 and y == -3,
                label .. "bags' layout: and the icon is back where Daylight UI pinned it")
            Equal(#world.client.errors, 0, label .. "bags' layout: no error")

            -- An answer that raises an error: the request goes on with the window's options.
            local Raising = {}
            function Raising:GetName() return "Raising" end
            function Raising:Init() end
            core:RegisterFeature(Raising)
            core:AnswerOptionsFor("Raising", function() error("an answer that fails") end)
            local raisingSlot = world.client:NewFrame("Button")
            raisingSlot:SetSize(37, 37)
            local item = world.env.CaerdonItem:CreateFromBagAndSlot(0, 23)
            function item:GetCaerdonItemType() return "Miscellaneous" end
            function item:IsItemEmpty() return false end
            function item:IsItemDataCached() return true end
            function item:GetItemID() return ARROWS end
            function item:GetCaerdonStatus() return true, "own", nil, {}, nil end
            core:UpdateButton(raisingSlot, item, core:GetFeature("Raising"), { bag = 0, slot = 23 }, theirs)
            world.client:Tick(3)
            Check(world.drawnWith[raisingSlot] == theirs, label .. "an answer that fails: the button is drawn with the window's own options")
            Equal(#world.client.errors, 1, label .. "an answer that fails: the error is reported once")
            core:AnswerOptionsFor("Raising", function() return nil end)
            core:UpdateButton(raisingSlot, item, core:GetFeature("Raising"), { bag = 0, slot = 23 }, theirs)
            world.client:Tick(3)
            Check(world.drawnWith[raisingSlot] == theirs, label .. "an answer that says nothing: the button is drawn with the window's own options")
            for index = #world.client.errors, 1, -1 do
                world.client.errors[index] = nil
            end
        end

        -- 26. One upgrade arrow in a bag slot: Daylight UI draws Pawn's in a corner of its own,
        -- and this addon takes that corner where it has drawn an upgrade itself.
        do
            local bagNoted = bagSlots.hookPointsNoted or {}
            Equal(bagNoted["DaylightUI_Bags Baganator.API.RegisterCornerWidget"], nil,
                label .. "one arrow: nothing is looked for before Daylight UI's bags are loaded")
            local widgets, passes = {}, 0
            rawset(world.env, "Baganator", { DaylightUI = true, API = {
                RegisterCornerWidget = function(name, id, onUpdate, onInit, position)
                    widgets[#widgets + 1] = { name = name, id = id, onUpdate = onUpdate, onInit = onInit, position = position }
                end,
                RequestItemButtonsRefresh = function() passes = passes + 1 end,
            } })
            world.client:Fire("ADDON_LOADED", "DaylightUI_Bags")
            for _, point in ipairs({ "DaylightUI_Bags Baganator.API.RegisterCornerWidget",
                "DaylightUI_Bags Baganator.API.RequestItemButtonsRefresh" }) do
                Equal(bagNoted[point] and bagNoted[point].found, 1, label .. "one arrow: the hook point " .. point .. " is noted as found")
            end
            Equal(#widgets, 1, label .. "one arrow: one widget is registered with Daylight UI's bags")
            local widget = widgets[1] or {}
            Equal(widget.id, "caerdon_wardrobe_upgrade", label .. "one arrow: under a name of this addon's")
            Equal(type(widget.position) == "table" and widget.position.corner, "top_left", label .. "one arrow: in the corner Pawn's arrow has there")
            Check(type(widget.position) == "table" and widget.position.priority < 1, label .. "one arrow: ahead of Pawn's, which has priority 1")
            world.client:Fire("ADDON_LOADED", "DaylightUI_Bags")
            Equal(#widgets, 1, label .. "one arrow: a second word of the addon registers nothing twice")

            local function AskAs(slot, index, status)
                local item = world.env.CaerdonItem:CreateFromBagAndSlot(0, index)
                function item:GetCaerdonItemType() return "Miscellaneous" end
                function item:IsItemEmpty() return false end
                function item:IsItemDataCached() return true end
                function item:GetItemID() return ARROWS end
                function item:GetCaerdonStatus() return true, status, nil, {}, nil end
                core:UpdateButton(slot, item, late, { bag = 0, slot = index }, { fixedStatusPosition = true, statusProminentSize = 16 })
                -- The drawing itself is not part of this scenario (scenarios/draw-path.lua has
                -- what an upgrade leaves on a button): what it would leave is put there.
                local overlay = core:GetCaerdonButton(slot)
                overlay.caerdonHasUpgradeIcon = status == "upgrade"
                world.client:Tick(3)
            end
            local slot26 = world.client:NewFrame("Button")
            slot26:SetSize(37, 37)
            local claim = widget.onInit(slot26)
            Check(type(claim) == "table" and type(claim.SetParent) == "function" and claim:GetParent() == slot26,
                label .. "one arrow: the widget is a frame of this addon's on the slot")
            Equal(widget.onUpdate(claim, { itemID = ARROWS }), false, label .. "one arrow: a slot not drawn yet leaves the corner to Pawn's")
            AskAs(slot26, 31, "own")
            Equal(select(4, core:GetDrawnParts(slot26)), false, label .. "one arrow: (a star is no upgrade)")
            Equal(passes, 0, label .. "one arrow: a draw with no upgrade asks for no pass")
            AskAs(slot26, 31, "upgrade")
            Equal(select(4, core:GetDrawnParts(slot26)), true, label .. "one arrow: (the arrow is drawn)")
            Equal(passes, 1, label .. "one arrow: a draw that puts an upgrade on the slot asks Daylight UI to go over its slots")
            Equal(widget.onUpdate(claim, { itemID = ARROWS }), true, label .. "one arrow: and the corner is taken, so Pawn's is not shown")
            AskAs(slot26, 31, "upgrade")
            AskAs(slot26, 31, "upgrade")
            Equal(passes, 1, label .. "one arrow: the pass's own draws ask for no other")
            Equal(widget.onUpdate(claim, { itemID = KNIFE }), false, label .. "one arrow: another item in the slot is not answered for by the last draw")
            Equal(widget.onUpdate(claim, { itemID = ARROWS }), true, label .. "one arrow: (the same item is)")
            Equal(widget.onUpdate(claim, nil), false, label .. "one arrow: nor is a slot nothing is said of")
            Equal(widget.onUpdate(claim, { itemID = ARROWS }), true, label .. "one arrow: (told again)")
            AskAs(slot26, 31, "own")
            Equal(passes, 2, label .. "one arrow: an upgrade that is gone asks for a pass too")
            Equal(widget.onUpdate(claim, { itemID = ARROWS }), false, label .. "one arrow: and the corner is Pawn's again")
            -- The export's word on where a slot's request stands.
            Check(select(2, core:GetAskedOf(slot26)):find("; its request: none waiting; the icon's region: shown ", 1, true) ~= nil,
                label .. "request note: a drawn slot has none waiting, and the icon's region is described (" ..
                tostring(select(2, core:GetAskedOf(slot26))) .. ")")
            do
                local queued = world.client:NewFrame("Button")
                queued:SetSize(37, 37)
                local item = world.env.CaerdonItem:CreateFromBagAndSlot(0, 33)
                function item:GetCaerdonItemType() return "Miscellaneous" end
                function item:IsItemEmpty() return false end
                function item:GetItemID() return ARROWS end
                function item:GetCaerdonStatus() return true, "own", nil, {}, nil end
                -- Its data never comes.
                function item:IsItemDataCached() return false end
                function item:IsDataEvictable() return false end
                function item:ContinueWithCancelOnRecordLoad() return function() end end
                core:UpdateButton(queued, item, late, { bag = 0, slot = 33 }, { fixedStatusPosition = true })
                Check(select(2, core:GetAskedOf(queued)):find("; its request: in the queue", 1, true) ~= nil,
                    label .. "request note: a slot just asked for is in the queue")
                world.client:Tick(3)
                local note = select(2, core:GetAskedOf(queued))
                Check(note:find("; its request: held until its item's data is here, for ", 1, true) ~= nil and
                    note:find(" s, 1 of its window's held in all", 1, true) ~= nil,
                    label .. "request note: a slot whose item has not loaded is held, and says with how many (" .. tostring(note) .. ")")
                core:ClearButton(queued)
                core:ClearButtonState(queued)
            end
            -- Two draws before the pass has come.
            AskAs(slot26, 31, "upgrade")
            AskAs(slot26, 31, "upgrade")
            Equal(passes, 3, label .. "one arrow: two draws before the pass ask for one")
            -- A slot Daylight UI has made no widget for.
            local bare = world.client:NewFrame("Button")
            bare:SetSize(37, 37)
            AskAs(bare, 32, "upgrade")
            Equal(passes, 3, label .. "one arrow: a slot Daylight UI has not asked the widget for asks for no pass")
            Equal(#world.client.errors, 0, label .. "one arrow: no error")
        end

        -- 27. The comparison tooltip's chips.
        do
            local HEAD = "If you replace this item"
            -- Daylight UI's tooltips in a world: the function that makes the chips, as far as
            -- it is read here, and this addon's tooltip feature standing in with what it wrote.
            local function WithTooltips(inWorld, changes)
                local items = { calls = 0 }
                items.Changes = changes or function(lines, from, n)
                    items.calls = items.calls + 1
                    local chips, skip, changing = {}, {}, false
                    for index = from, n do
                        local text = lines[index].left
                        if text == HEAD then
                            changing, skip[index] = true, true
                        elseif changing and text:match("^[%+%-]%d") then
                            chips[#chips + 1] = { text, { 1, 1, 1 } }
                            skip[index] = true
                        end
                    end
                    return chips, skip
                end
                inWorld.ours[items] = true
                inWorld.modules.Tooltip = { ns = { RichItems = items } }
                local written = {}
                inWorld.namespace.Tooltip = {
                    GetReplacementGainOfLine = function(_, text) return written[text] end,
                    GetPlainGain = function(_, gain)
                        if gain and not gain.more then
                            return gain.plain, gain.kind
                        end
                    end,
                }
                return items, written
            end
            local function Texts(chips)
                local texts = {}
                for index, chip in ipairs(chips or {}) do
                    texts[index] = tostring(chip[1]) .. "=" .. table.concat(chip[2] or {}, ",")
                end
                return table.concat(texts, " | ")
            end
            local function Skipped(skip, n)
                local taken = {}
                for index = 1, n do
                    if skip[index] then
                        taken[#taken + 1] = index
                    end
                end
                return table.concat(taken, " ")
            end
            local function Lines(...)
                local lines = {}
                for index = 1, select("#", ...) do
                    lines[index] = { left = (select(index, ...)) }
                end
                return lines
            end

            local tips = core:GetFeature("DaylightUITooltip")
            Check(tips ~= nil, label .. "chips: the feature is registered")
            local tipNoted = tips and tips.hookPointsNoted or {}
            for _, point in ipairs({ "DaylightUI.API.For", "DaylightUI.API.For(addon).Wrap", "DaylightUI.API.Colors" }) do
                Equal(tipNoted[point] and tipNoted[point].found, 1, label .. "chips: the hook point " .. point .. " is noted as found")
            end
            Equal(tipNoted["DaylightUI_Tooltip RichItems.Changes"], nil,
                label .. "chips: nothing is looked for before Daylight UI's tooltips are loaded")
            local items, written = WithTooltips(world)
            local theirs = items.Changes
            world.client:Fire("ADDON_LOADED", "DaylightUI_Tooltip")
            Equal(tipNoted["DaylightUI_Tooltip RichItems.Changes"] and tipNoted["DaylightUI_Tooltip RichItems.Changes"].found, 1,
                label .. "chips: the function is noted as found")
            Equal(tipNoted["DaylightUI_Tooltip RichItems.Changes wrapped"] and tipNoted["DaylightUI_Tooltip RichItems.Changes wrapped"].found, 1,
                label .. "chips: and as wrapped")
            Check(items.Changes ~= theirs, label .. "chips: the function is wrapped")
            Equal(world.hookOwners[theirs], "CaerdonWardrobe", label .. "chips: under this addon's name")
            local wrapped = items.Changes
            world.client:Fire("ADDON_LOADED", "DaylightUI_Tooltip")
            Check(items.Changes == wrapped, label .. "chips: a second word of the addon wraps nothing twice")

            written["OURS gain"] = { plain = "+25% Guardian", kind = "gain" }
            written["OURS loss"] = { plain = "-17% Guardian", kind = "loss" }
            written["OURS even"] = { plain = "+2% Guardian", kind = "even" }
            written["OURS more"] = { plain = "+25% Guardian", kind = "gain", more = true }
            -- The worn piece's two lines, another addon's, the client's changes, this addon's.
            local chips, skip = items.Changes(Lines("Worn Ring", "+3 Stamina", "pawn: Guardian", HEAD, "+5 Stamina", "-2 Spirit",
                "OURS gain"), 3, 7)
            Equal(Texts(chips), "+5 Stamina=1,1,1 | -2 Spirit=1,1,1 | +25% Guardian=0.5,0.8,0.5",
                label .. "chips: this addon's line is the last of the chips, in the colour of a gain")
            Equal(Skipped(skip, 7), "4 5 6 7", label .. "chips: and is taken with the lines of the changes, another addon's left")
            Equal(items.calls, 1, label .. "chips: Daylight UI's own function is called once for it")
            chips, skip = items.Changes(Lines("Worn Ring", HEAD, "+5 Stamina", "OURS loss"), 2, 4)
            Equal(Texts(chips), "+5 Stamina=1,1,1 | -17% Guardian=0.9,0.4,0.4", label .. "chips: a loss in the colour of a loss")
            chips, skip = items.Changes(Lines("Worn Ring", HEAD, "+5 Stamina", "OURS even"), 2, 4)
            Equal(Texts(chips), "+5 Stamina=1,1,1 | +2% Guardian=0.7,0.7,0.6", label .. "chips: neither, in the colour of a label")
            -- The client names no changes: the line is a chip all the same.
            chips, skip = items.Changes(Lines("Worn Ring", "OURS gain"), 2, 2)
            Equal(Texts(chips) .. " / " .. Skipped(skip, 2), "+25% Guardian=0.5,0.8,0.5 / 2",
                label .. "chips: with no changes of the client's the line is a chip by itself")
            -- A line that says more than a chip can.
            chips, skip = items.Changes(Lines("Worn Ring", HEAD, "+5 Stamina", "OURS more"), 2, 4)
            Equal(Texts(chips) .. " / " .. Skipped(skip, 4), "+5 Stamina=1,1,1 / 2 3",
                label .. "chips: a line that says more stays a line")
            -- Two lines of this addon's on one tooltip.
            local askedBefore = world.coloursAsked
            chips, skip = items.Changes(Lines("Worn Ring", HEAD, "OURS gain", "OURS loss"), 2, 4)
            Equal(world.coloursAsked, askedBefore + 1, label .. "chips: the colours are asked for once for a tooltip")
            Equal(Texts(chips), "+25% Guardian=0.5,0.8,0.5 | -17% Guardian=0.9,0.4,0.4", label .. "chips: every line of this addon's, in their order")
            -- Before the lines the card hands over, and a text the tooltip did not write.
            chips, skip = items.Changes(Lines("OURS gain", HEAD, "+5 Stamina", "OURS gain?"), 2, 4)
            Equal(Texts(chips) .. " / " .. Skipped(skip, 4), "+5 Stamina=1,1,1 / 2 3",
                label .. "chips: no line before the ones handed over, and none the tooltip did not write")
            -- The colours are asked for when there is a chip to colour.
            local asked = world.coloursAsked
            items.Changes(Lines("Worn Ring", HEAD, "+5 Stamina"), 2, 3)
            Equal(world.coloursAsked, asked, label .. "chips: no colours are asked for a tooltip with no line of this addon's")
            -- Without the tooltip feature (its file is loaded with the others; a guard).
            local kept = world.namespace.Tooltip
            world.namespace.Tooltip = nil
            chips, skip = items.Changes(Lines("Worn Ring", HEAD, "+5 Stamina", "OURS gain"), 2, 4)
            Equal(Texts(chips) .. " / " .. Skipped(skip, 4), "+5 Stamina=1,1,1 / 2 3", label .. "chips: without the tooltip feature Daylight UI's answer stands")
            world.namespace.Tooltip = kept
            Equal(#world.client.errors, 0, label .. "chips: no error")

            -- A function of Daylight UI's that answers with something else.
            local odd = Start(flavor)
            local oddItems, oddWritten = WithTooltips(odd, function() return nil, "no table" end)
            oddWritten["OURS gain"] = { plain = "+25% Guardian", kind = "gain" }
            odd.client:Fire("ADDON_LOADED", "DaylightUI_Tooltip")
            local first, second = oddItems.Changes(Lines("Worn Ring", "OURS gain"), 2, 2)
            Equal(tostring(first) .. " / " .. tostring(second), "nil / no table", label .. "chips: another answer of Daylight UI's is handed on as it is")
            Equal(#odd.client.errors, 0, label .. "chips: another answer: no error")

            -- A colour the API does not name: the line stays a line.
            local pale = Start(flavor, "without a colour")
            local paleItems, paleWritten = WithTooltips(pale)
            paleWritten["OURS even"] = { plain = "+2% Guardian", kind = "even" }
            paleWritten["OURS gain"] = { plain = "+25% Guardian", kind = "gain" }
            pale.client:Fire("ADDON_LOADED", "DaylightUI_Tooltip")
            chips, skip = paleItems.Changes(Lines("Worn Ring", HEAD, "OURS even", "OURS gain"), 2, 4)
            Equal(Texts(chips) .. " / " .. Skipped(skip, 4), "+25% Guardian=0.5,0.8,0.5 / 2 4",
                label .. "chips: a colour the API does not name leaves that line a line")
            Equal(#pale.client.errors, 0, label .. "chips: a colour not named: no error")

            -- An API without the colours, a wrap Daylight UI refuses, a module without the function.
            local plain = Start(flavor, "without Colors")
            local plainItems = WithTooltips(plain)
            local plainTheirs = plainItems.Changes
            plain.client:Fire("ADDON_LOADED", "DaylightUI_Tooltip")
            local plainNoted = plain.core:GetFeature("DaylightUITooltip").hookPointsNoted or {}
            Equal(plainNoted["DaylightUI.API.Colors"] and plainNoted["DaylightUI.API.Colors"].missing, 1,
                label .. "chips: an API without the colours is noted")
            Check(plainItems.Changes == plainTheirs, label .. "chips: and nothing is wrapped")
            local unwilling = Start(flavor, "the wrap refused")
            local unwillingItems = WithTooltips(unwilling)
            local unwillingTheirs = unwillingItems.Changes
            unwilling.client:Fire("ADDON_LOADED", "DaylightUI_Tooltip")
            local unwillingNoted = unwilling.core:GetFeature("DaylightUITooltip").hookPointsNoted or {}
            Equal(unwillingNoted["DaylightUI_Tooltip RichItems.Changes wrapped"] and
                unwillingNoted["DaylightUI_Tooltip RichItems.Changes wrapped"].missing, 1, label .. "chips: a wrap Daylight UI refuses is noted as missing")
            Check(unwillingItems.Changes == unwillingTheirs, label .. "chips: a wrap refused: the function is Daylight UI's own")
            Equal(#unwilling.client.errors, 0, label .. "chips: a wrap refused: no error")
            local bare = Start(flavor)
            bare.modules.Tooltip = { ns = {} }
            bare.client:Fire("ADDON_LOADED", "DaylightUI_Tooltip")
            local bareNoted = bare.core:GetFeature("DaylightUITooltip").hookPointsNoted or {}
            Equal(bareNoted["DaylightUI_Tooltip RichItems.Changes"] and bareNoted["DaylightUI_Tooltip RichItems.Changes"].missing, 1,
                label .. "chips: a module without the function is noted as missing")
            Equal(bareNoted["DaylightUI_Tooltip RichItems.Changes wrapped"], nil, label .. "chips: and no wrap is tried")
            Equal(#bare.client.errors, 0, label .. "chips: a module without the function: no error")
        end

        -- 15.
        local refused = Start(flavor, "the hook refused")
        -- Baganator itself, which answers its own plugins: nothing of this is done there.
        do
            local registered = 0
            rawset(refused.env, "Baganator", { API = {
                RegisterCornerWidget = function() registered = registered + 1 end,
                RequestItemButtonsRefresh = function() end,
            } })
            refused.client:Fire("ADDON_LOADED", "DaylightUI_Bags")
            Equal(registered, 0, label .. "one arrow: no widget is registered with Baganator's own table")
            local refusedBags = refused.core:GetFeature("DaylightUIBagSlots").hookPointsNoted or {}
            Equal(refusedBags["DaylightUI_Bags Baganator.API.RegisterCornerWidget"] and
                refusedBags["DaylightUI_Bags Baganator.API.RegisterCornerWidget"].missing, 1,
                label .. "one arrow: and the hook point is noted as missing")
        end
        local refusedNoted = refused.feature and refused.core:GetFeature("DaylightUIAuction").hookPointsNoted or {}
        Equal(refusedNoted["DaylightUI.Win.Parts.SetItemIcon hooked"] and refusedNoted["DaylightUI.Win.Parts.SetItemIcon hooked"].missing, 1,
            label .. "a hook Daylight UI does not take: noted as missing")
        local refusedRow = refused.Row({ kind = "line", key = tostring(ARROWS), itemID = ARROWS })
        refused.FillRow(refusedRow)
        Equal(refused.TimesAskedOn(refusedRow), 0, label .. "a hook Daylight UI does not take: nothing is asked for")
        Equal(#refused.client.errors, 0, label .. "a hook Daylight UI does not take: no error")
        Equal(refused.core:GetFeature("DaylightUIBagSlots"):GetLayoutNote(), nil,
            label .. "bags' layout: no note while Daylight UI's bags have not registered with this addon")
        local refusedQuests = refused.core:GetFeature("DaylightUIQuests").hookPointsNoted or {}
        Equal(refusedQuests["DaylightUI.Win.Parts.SetItemIcon hooked"] and refusedQuests["DaylightUI.Win.Parts.SetItemIcon hooked"].missing, 1,
            label .. "a hook Daylight UI does not take: the quests' is noted as missing")
        local refusedTile = refused.Row(nil)
        refusedTile.iconSize, refusedTile.spec = 34, { name = "Sold Thing", link = function() return refused.game.Link(KNIFE) end }
        refused.FillRow(refusedTile)
        Equal(refused.TimesAskedOn(refusedTile), 0, label .. "a hook Daylight UI does not take: no quest's tile is asked for")
        local refusedCraft = refused.core:GetFeature("DaylightUICraft")
        Equal(refusedCraft.hookPointsNoted["DaylightUI.Craft.Recipe.Fill hooked"] and refusedCraft.hookPointsNoted["DaylightUI.Craft.Recipe.Fill hooked"].missing, 1,
            label .. "a hook Daylight UI does not take: the recipe pane's is noted as missing")
        refused.FillRecipe({ id = 501 }, refused.game.Link(KNIFE))
        Equal(refused.TimesAskedOn(refused.ResultLine()), 0, label .. "a hook Daylight UI does not take: the picked recipe's line is not asked for")
        refused.recipes = { [501] = { recipeID = 501, hyperlink = refused.game.Link(KNIFE) } }
        local refusedLine = refused.Tile()
        refused.Send("FrameStyled", "craftrow", refusedLine, 501, false)
        refused.client:Tick(3)
        Equal(refused.Last(refused.holders[refusedLine]).id, KNIFE, label .. "a hook Daylight UI does not take: the list's lines are asked for all the same")
        local gone = Start(flavor, "without SetItemIcon")
        local goneNoted = gone.core:GetFeature("DaylightUIAuction").hookPointsNoted or {}
        Equal(goneNoted["DaylightUI.Win.Parts.SetItemIcon"] and goneNoted["DaylightUI.Win.Parts.SetItemIcon"].missing, 1,
            label .. "a function that is gone: noted as missing")
        Equal(goneNoted["DaylightUI.Win.Parts.SetItemIcon hooked"], nil, label .. "a function that is gone: no hook is tried")
        Equal(#gone.client.errors, 0, label .. "a function that is gone: no error")
        Check(gone.feature ~= nil and gone.Listening("FrameStyled") == 2, label .. "a function that is gone: the vendor's tiles are attached all the same")
        local goneQuests = gone.core:GetFeature("DaylightUIQuests").hookPointsNoted or {}
        Equal(goneQuests["DaylightUI.Win.Parts.SetItemIcon"] and goneQuests["DaylightUI.Win.Parts.SetItemIcon"].missing, 1,
            label .. "a function that is gone: noted as missing by the quests' feature too")
        Equal(gone.PaintersOf("rollcard"), "CaerdonWardrobe", label .. "a function that is gone: the roll cards are painted all the same")

        -- 10.
        local newer = Start(flavor, "another major version")
        Check(newer.feature ~= nil, label .. "another major version: the feature registers")
        Equal(#newer.listeners, 0, label .. "another major version: nothing is attached")
        Equal(#newer.painters, 0, label .. "another major version: nothing is painted")
        Equal(next(newer.hookOwners), nil, label .. "another major version: nothing is hooked")
        Equal(#newer.client.errors, 0, label .. "another major version: no error")
        local lacking = Start(flavor, "without GetPart")
        Equal(lacking.Listening("FrameStyled"), 0, label .. "an API without GetPart: neither the vendor's tiles nor the recipes' lines are attached")
        lacking.FillRecipe({ id = 501 }, lacking.game.Link(KNIFE))
        Equal(lacking.LastOn(lacking.ResultLine()).id, KNIFE, label .. "an API without GetPart: the picked recipe's line is asked for all the same")
        local lackingNoted = lacking.feature and lacking.feature.hookPointsNoted or {}
        Equal(lackingNoted["DaylightUI.API.GetPart"] and lackingNoted["DaylightUI.API.GetPart"].missing, 1,
            label .. "an API without GetPart: the call is noted as missing")
        Equal(lackingNoted["DaylightUI.API.On"] and lackingNoted["DaylightUI.API.On"].found, 1,
            label .. "an API without GetPart: the others as found")
        Equal(#lacking.client.errors, 0, label .. "an API without GetPart: no error")
    end
end
