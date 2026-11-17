-- What the addon does with no window open: on every item tooltip anyone fills, and on every
-- change in the bags.
--
-- Two things are held here. The auction module remembers the stackable items it has judged,
-- to notice when a change in how many are owned turns a verdict; that list must not outlive
-- the verdicts it was made from. And the tooltip handler, which remembers what the pointer is
-- on for the debug hotkey, leaves the same answer as before while making nothing new per
-- tooltip.
--
-- The game is hand-made: two trade goods, an auction addon with one price for both, and a
-- count of each that the scenario sets.
--
-- Real code: the addon's item side and core, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Rogue", classFile = "ROGUE", race = "Human",
        faction = "Alliance", level = 10 }

    local function Goods(name)
        return { name = name, quality = 1, level = 1, minLevel = 0, type = "Tradeskill", subType = "Meat",
            stack = 20, price = 10, classID = 7, subClassID = 8 }
    end
    local MEAT, HIDE = 950001, 950002
    local ITEMS = { [MEAT] = Goods("Chunk of Test Meat"), [HIDE] = Goods("Scrap of Test Hide") }

    -- At 3s apiece one is not worth the trip for a level 10 toon and two are.
    local PRICE = 300
    local owned = { [MEAT] = 2, [HIDE] = 1 }
    local countAsked = {}

    local game = H.StockGame(TOON, ITEMS)
    game:Set("C_Item.GetItemCount", function(itemID)
        countAsked[#countAsked + 1] = itemID
        return owned[itemID] or 0
    end)
    game:Set("Auctionator.API.v1.GetAuctionPriceByItemLink", function() return PRICE end)
    game:Set("Auctionator.API.v1.GetAuctionAgeByItemLink", function() return 0 end)
    game:Set("Auctionator.API.v1.RegisterForDBUpdate", function() end)

    local client = H.Client.New({ flavor = "forever", provider = game })
    game.client = client
    H.LoadBlizzardBase(client)
    local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
    client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
    rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
    client:Fire("ADDON_LOADED", "CaerdonWardrobe")
    client:Fire("VARIABLES_LOADED")
    client:Fire("PLAYER_LOGIN")
    client:Fire("PLAYER_ENTERING_WORLD", true, false)
    client:Tick(40)
    local env = client.env
    Equal(#client.errors, 0, "start: no error reached the error handler")

    local core, auction = env.CaerdonWardrobe, env.CaerdonAuctionValue
    local refreshes = 0
    local refreshItems = core.RefreshItems
    function core:RefreshItems(...)
        refreshes = refreshes + 1
        return refreshItems(self, ...)
    end

    local function Status(itemID)
        local item = env.CaerdonItem:CreateFromItemID(itemID)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        client:TickUntil(function() return loaded end, 10)
        local ready, status = item:GetCaerdonStatus()
        return ready and (status or "") or "<not ready>"
    end

    -- Which items a change in the bags makes the module ask the client about.
    local function AskedOnBagChange()
        countAsked = {}
        auction:OnBagsChanged()
        table.sort(countAsked)
        return table.concat(countAsked, " ")
    end

    --------------------------------------------------------------------------------------
    -- The stacks the auction module keeps an eye on
    --------------------------------------------------------------------------------------

    Equal(AskedOnBagChange(), "", "stacks: nothing is looked at before anything was judged")
    Equal(Status(MEAT), "auctionGoods", "stacks: two of the meat are worth listing")
    Equal(Status(HIDE), "", "stacks: one hide is not")
    Equal(AskedOnBagChange(), MEAT .. " " .. HIDE, "stacks: both are looked at on a change in the bags")
    Equal(refreshes, 0, "stacks: and nothing is refreshed while the counts stand")

    -- A full refresh throws every verdict away. What is judged again afterwards is watched
    -- again; what is not (a stack in a bag that stays closed, an item since sold) is not.
    core:RefreshItems()
    client:Tick(20)
    refreshes = 0
    Equal(AskedOnBagChange(), "", "refresh: no stack is looked at once its verdict is gone")
    Equal(Status(MEAT), "auctionGoods", "refresh: the meat is judged again")
    Equal(AskedOnBagChange(), tostring(MEAT), "refresh: and it alone is looked at again")

    -- The hide was not judged again and a second one arrives meanwhile: nobody notices, and
    -- nobody has to, because its next draw judges it on what is owned then.
    owned[HIDE] = 2
    Equal(AskedOnBagChange(), tostring(MEAT), "unwatched: a change in a stack that is not watched is not looked at")
    Equal(refreshes, 0, "unwatched: and refreshes nothing")
    Equal(Status(HIDE), "auctionGoods", "unwatched: its next draw has the verdict for two")
    Equal(AskedOnBagChange(), MEAT .. " " .. HIDE, "unwatched: and it is watched from then on")

    -- A watched stack whose count turns its verdict refreshes every icon, once.
    owned[MEAT] = 1
    client:Fire("BAG_UPDATE_DELAYED")
    Equal(refreshes, 1, "turned: one meat left refreshes the icons")
    client:Tick(20)
    Equal(AskedOnBagChange(), "", "turned: after which nothing is watched until it is judged again")
    Equal(Status(MEAT), "", "turned: one meat is not worth listing")
    Equal(Status(HIDE), "auctionGoods", "turned: two hides still are")
    client:Fire("BAG_UPDATE_DELAYED")
    Equal(refreshes, 1, "turned: and a change in the bags with the counts as they are refreshes nothing")

    -- A count that changes without turning the verdict is taken note of and nothing else.
    owned[HIDE] = 5
    client:Fire("BAG_UPDATE_DELAYED")
    Equal(refreshes, 1, "more: five hides are still worth listing, so nothing is refreshed")

    --------------------------------------------------------------------------------------
    -- The item under the pointer
    --------------------------------------------------------------------------------------

    local api = env.CaerdonAPI
    local tooltip = {}
    local function Seen(data)
        api:OnTooltipItem(tooltip, data)
        return api.lastTooltipContext or {}
    end

    local link = game.Link(MEAT)
    local context = Seen({ hyperlink = link })
    Equal(context.itemLink, link, "tooltip: the link is kept")
    Equal(context.itemID, MEAT, "tooltip: with the item's ID read off it")
    Check(context.tooltip == tooltip and type(context.timestamp) == "number", "tooltip: and whose tooltip it was, and when")
    Check(context.bag == nil and context.slot == nil, "tooltip: no slot where the data names none")

    Equal(Seen({ itemID = 11, id = 12, itemId = 13 }).itemID, 11, "tooltip: itemID is read first")
    Equal(Seen({ id = 12, itemId = 13 }).itemID, 12, "tooltip: then id")
    Equal(Seen({ itemId = 13 }).itemID, 13, "tooltip: then itemId")
    Equal(Seen({ id = 0, itemId = 13 }).itemID, 13, "tooltip: an ID of nought is passed over")
    Equal(Seen({ hyperlink = link, id = 12 }).itemID, 12, "tooltip: the data's ID goes before the link's")
    Equal(Seen({ id = 12 }).itemLink, nil, "tooltip: and the link of the tooltip before is gone")

    context = Seen({ id = 12, bagID = 1, bagIndex = 2, containerID = 3, containerIndex = 4, bag = 5,
        slotIndex = 6, slot = 7, slotID = 8, containerSlot = 9 })
    Check(context.bag == 1 and context.slot == 6, "tooltip: bagID and slotIndex are read first")
    context = Seen({ id = 12, bagIndex = 2, containerID = 3, containerIndex = 4, bag = 5, slot = 7, slotID = 8,
        containerSlot = 9 })
    Check(context.bag == 2 and context.slot == 7, "tooltip: then bagIndex and slot")
    context = Seen({ id = 12, containerID = 3, containerIndex = 4, bag = 5, slotID = 8, containerSlot = 9 })
    Check(context.bag == 3 and context.slot == 8, "tooltip: then containerID and slotID")
    context = Seen({ id = 12, containerIndex = 4, bag = 5, containerSlot = 9 })
    Check(context.bag == 4 and context.slot == 9, "tooltip: then containerIndex and containerSlot")
    context = Seen({ id = 12, bag = 0, slot = 1 })
    Check(context.bag == 0 and context.slot == 1, "tooltip: then bag, and the backpack's nought counts")
    context = Seen({ bag = 0, slot = 3 })
    Check(context.bag == 0 and context.slot == 3 and context.itemID == nil, "tooltip: a slot alone is enough to keep")

    context = Seen({ id = 12 })
    local before = api.lastTooltipContext
    api:OnTooltipItem(tooltip, nil)
    Check(api.lastTooltipContext == before and before.itemID == 12, "tooltip: no data leaves what was there")
    context = Seen({ leftText = "not an item" })
    Check(context.itemID == nil and context.itemLink == nil, "tooltip: data that names no item leaves none behind")

    -- A held tooltip is filled again several times a second. Nothing is made for it: the
    -- handler writes into the table it already has.
    Seen({ hyperlink = link, bagID = 0, slotIndex = 1 })
    collectgarbage("collect")
    collectgarbage("stop")
    local data = { hyperlink = link, bagID = 0, slotIndex = 1 }
    local memoryBefore = collectgarbage("count")
    for _ = 1, 2000 do
        api:OnTooltipItem(tooltip, data)
    end
    local grownKB = collectgarbage("count") - memoryBefore
    collectgarbage("restart")
    Check(grownKB < 50, ("tooltip: two thousand tooltips make no garbage (%.1f KB)"):format(grownKB))

    Equal(#client.errors, 0, "end: no error reached the error handler")
    for _, message in ipairs(client.errors) do
        Check(false, "error: " .. message)
    end
end
