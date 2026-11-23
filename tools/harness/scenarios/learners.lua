-- The mail icon for what another toon could learn: a class's spell book, a rune
-- (CaerdonLearners.lua, CaerdonItemMixin:GetLearnerStatus and its place in GetCaerdonStatus).
--
-- Nothing saved says what another toon knows or what class it is, so each toon answers for
-- itself by its own tooltip (the teaching rule of scenarios/taught-by-item.lua) and the
-- answers are saved by realm and toon. Here two toons of one realm are played in turn, each
-- in a client of its own, with the saved tables handed from one to the next as a logout does.
--
-- And the ledger (CaerdonLedger.lua): a toon that has a copy in its bags or its mailbox as
-- they were last seen, or was sent one, is no reason for the icon. That a mail to one's own
-- toon is seen as the mock has it (the SendMail call with the recipient, the attachments
-- read by GetSendMailItem, MAIL_SEND_SUCCESS after it) is read from both clients' mail frame
-- code and not seen in a client.
--
-- The lines are made after a WoW Forever client's tooltips (the test addon's walk); the items
-- and spells are invented, as in taught-by-item.lua. Nothing here has been seen in a client.
--
-- Real code: the addon, Blizzard's base files from the mirror.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local HUNTER = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 33 }
    local MAGE = { name = "Qwyrm", realm = "Farrealm", class = "Mage", classFile = "MAGE", race = "Gnome",
        faction = "Alliance", level = 20 }

    local LEARN_LINE, REQUIREMENT_LINE = 38, 43
    local CONSUMABLE, RECIPE = 0, 9
    local RED = { r = 1, g = 0.125, b = 0.125 }

    local function Requirement(text, kind, met)
        local line = { text = text, type = REQUIREMENT_LINE, kind = kind, usable = met }
        if not met then line.r, line.g, line.b = RED.r, RED.g, RED.b end
        return line
    end
    local function Teaches(spell)
        return { text = "Use: Teaches you something.", type = LEARN_LINE, spellID = spell }
    end

    local MAGE_BOOK, HIGH_MAGE_BOOK, MAGE_RUNE, HUNTER_BOOK, HIGH_HUNTER_BOOK = 994001, 994002, 994003, 994004, 994005
    local BOUND_MAGE_BOOK, UNSEEN_MAGE_BOOK, POTION_RECIPE, PLAIN_POTION, HUNTER_RUNE = 994006, 994007, 994008, 994009, 994010
    local GONE_ITEM = 994999
    local SPELL = { [MAGE_BOOK] = 73001, [HIGH_MAGE_BOOK] = 73002, [MAGE_RUNE] = 73003, [HUNTER_BOOK] = 73004,
        [HIGH_HUNTER_BOOK] = 73005, [BOUND_MAGE_BOOK] = 73006, [UNSEEN_MAGE_BOOK] = 73007, [HUNTER_RUNE] = 73010 }

    -- The items as one toon's client shows them: a class line is met for its class, a level
    -- line for its level.
    local function Items(toon)
        local function Book(name, class, level, extra)
            local tooltip = { Teaches(extra.spell), Requirement("Classes: " .. class, "RaceClass", class == toon.class) }
            if level then
                tooltip[#tooltip + 1] = Requirement("Requires Level " .. level, "Level", toon.level >= level)
            end
            return { name = name, quality = 2, level = 30, minLevel = level or 0, type = extra.type or "Recipe",
                subType = extra.subType or "Book", stack = 1, price = 500, classID = extra.classID or RECIPE,
                subClassID = extra.subClassID or 0, bindType = extra.bindType or 0, tooltip = tooltip }
        end
        local rune = { type = "Consumable", subType = "Other", classID = CONSUMABLE, subClassID = 8 }
        local function Rune(spell)
            return { spell = spell, type = rune.type, subType = rune.subType, classID = rune.classID, subClassID = rune.subClassID }
        end
        local items = {
            [MAGE_BOOK] = Book("Tome of Test Ward", "Mage", 12, { spell = SPELL[MAGE_BOOK] }),
            [HIGH_MAGE_BOOK] = Book("Tome of Test Ward IX", "Mage", 60, { spell = SPELL[HIGH_MAGE_BOOK] }),
            [MAGE_RUNE] = Book("Spell Notes: Tests", "Mage", nil, Rune(SPELL[MAGE_RUNE])),
            [HUNTER_BOOK] = Book("Guide: Test Shot", "Hunter", 20, { spell = SPELL[HUNTER_BOOK] }),
            [HIGH_HUNTER_BOOK] = Book("Guide: Test Shot IX", "Hunter", 34, { spell = SPELL[HIGH_HUNTER_BOOK] }),
            [BOUND_MAGE_BOOK] = Book("Tome of Bound Tests", "Mage", nil, { spell = SPELL[BOUND_MAGE_BOOK], bindType = 1 }),
            [UNSEEN_MAGE_BOOK] = Book("Tome of Unseen Tests", "Mage", nil, { spell = SPELL[UNSEEN_MAGE_BOOK] }),
            [HUNTER_RUNE] = Book("Rune of Tests", "Hunter", nil, Rune(SPELL[HUNTER_RUNE])),
            -- A profession's recipe, and something that teaches nothing: neither is the rule's.
            [POTION_RECIPE] = { name = "Recipe: Test Potion", quality = 2, level = 30, minLevel = 0, type = "Recipe",
                subType = "Alchemy", stack = 1, price = 500, classID = RECIPE, subClassID = 6, bindType = 0,
                tooltip = { Teaches(73008), Requirement("Requires Alchemy (60)", "Skill", false) } },
            [PLAIN_POTION] = { name = "Test Potion", quality = 1, level = 30, minLevel = 0, type = "Consumable",
                subType = "Potion", stack = 20, price = 50, classID = CONSUMABLE, subClassID = 1, bindType = 0, tooltip = {} },
        }
        return items
    end

    -- A toon logs in with what was saved before (the learners' table, or both tables by
    -- name). Returns the client, the spells it knows (a table to write to) and its world:
    -- bags = { itemID ... } one a slot, inbox = { { { itemID, count } ... } ... } a mail each,
    -- attached = { { itemID, count } ... } what lies in the mail being written,
    -- inboxTotal = how many mails the mailbox holds where it shows fewer.
    local function Login(flavor, toon, saved, config)
        local items = Items(toon)
        local game = H.StockGame(toon, items)
        local known = {}
        game:Set("C_SpellBook.IsSpellKnown", function(spell) return known[spell] == true end)
        game:Set("C_TradeSkillUI.GetRecipeInfo", function() return nil end)
        local world = { bags = {}, bank = {}, inbox = {}, attached = {}, sent = {}, auctions = {} }
        game:Set("C_Container.GetContainerNumSlots", function(bag) return bag == 0 and #world.bags or 0 end)
        game:Set("C_Container.GetContainerItemID", function(bag, slot) return bag == 0 and world.bags[slot] or nil end)
        -- As the client counts: the bags, and the bank too where asked, open or not.
        game:Set("C_Item.GetItemCount", function(itemID, includeBank)
            local count = 0
            for _, held in ipairs(world.bags) do
                if held == itemID then count = count + 1 end
            end
            for _, held in ipairs(includeBank and world.bank or {}) do
                if held == itemID then count = count + 1 end
            end
            return count
        end)
        -- world.auctions = { [auctionID] = itemID }
        game:Set("C_AuctionHouse.PlaceBid", function() end)
        game:Set("C_AuctionHouse.ConfirmCommoditiesPurchase", function() end)
        game:Set("C_AuctionHouse.GetAuctionInfoByID", function(auctionID)
            local itemID = world.auctions[auctionID]
            return itemID and { auctionID = auctionID, itemKey = { itemID = itemID } } or nil
        end)
        game:Set("GetInboxNumItems", function() return #world.inbox, world.inboxTotal or #world.inbox end)
        game:Set("GetInboxItem", function(index, attachment)
            local entry = world.inbox[index] and world.inbox[index][attachment]
            if entry then return "an item", entry[1], 134400, entry[2] end
        end)
        game:Set("GetSendMailItem", function(slot)
            local entry = world.attached[slot]
            if entry then return "an item", entry[1], 134400, entry[2] end
        end)
        game:Set("SendMail", function(recipient) world.sent[#world.sent + 1] = recipient end)
        -- features/Tooltip.lua registers with it as it loads.
        game:Set("TooltipDataProcessor.AddTooltipPostCall", function() end)
        game:Set("TooltipDataProcessor.AddLinePreCall", function() end)
        if saved and saved.CaerdonLearnerData == nil and saved.CaerdonLedgerData == nil then
            saved = { CaerdonLearnerData = saved }
        end

        local client = H.Client.New({ flavor = flavor, provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        local settings = H.DeepCopy(namespace:GetDefaultConfig())
        for key, value in pairs(config or {}) do
            settings.Icon[key] = value
        end
        rawset(client.env, "CaerdonWardrobeConfig", settings)
        for name, value in pairs(saved or {}) do
            rawset(client.env, name, H.DeepCopy(value))
        end
        local kinds = client.env.Enum.TooltipDataUsageRequirementType
        for _, item in pairs(items) do
            for _, line in ipairs(item.tooltip) do
                if line.kind then
                    line.requirementType = kinds[line.kind]
                end
            end
        end
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(40)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "features/Tooltip.lua", namespace)
        Equal(#client.errors, 0, flavor .. " " .. toon.name .. ": no error reached the error handler at the start (" .. tostring(client.errors[1]) .. ")")
        return client, known, world, namespace
    end

    -- The lines the addon adds to an item's tooltip for the toons it is for.
    local function TooltipLines(namespace, item)
        local tooltip = { lines = {} }
        function tooltip:AddLine(text, r, g, b)
            self.lines[#self.lines + 1] = { text = text, green = g == 1 }
        end
        namespace.Tooltip:AddTaughtLearners(tooltip, item)
        return tooltip.lines
    end

    -- What a logout leaves for the next toon.
    local function Saved(client)
        return { CaerdonLearnerData = H.DeepCopy(client.env.CaerdonLearnerData),
            CaerdonLedgerData = H.DeepCopy(client.env.CaerdonLedgerData) }
    end
    local function Ledger(client, toon)
        local saved = client.env.CaerdonLedgerData
        return saved and saved[toon.realm] and saved[toon.realm][toon.name] or {}
    end

    local function Status(client, itemID)
        local item = client.env.CaerdonItem:CreateFromItemID(itemID)
        local loaded = false
        item:ContinueOnItemLoad(function() loaded = true end)
        client:TickUntil(function() return loaded end, 10)
        local ready, status
        client:TickUntil(function()
            ready, status = item:GetCaerdonStatus()
            return ready
        end, 10)
        return status, item
    end

    local function Answers(client, toon)
        local saved = client.env.CaerdonLearnerData
        local record = saved and saved[toon.realm] and saved[toon.realm][toon.name]
        return record and record.answers or {}, record and record.spells or {}
    end

    for _, flavor in ipairs({ "forever", "retail" }) do
        local label = flavor .. ": "

        -- 1. The hunter alone on the realm: nothing to send to anybody, and its own answers
        --    are written down for the toons to come.
        local hunter = Login(flavor, HUNTER, nil)
        Equal(Status(hunter, MAGE_BOOK), "collected", label .. "with no other toon a mage's book is as it was")
        Equal(Status(hunter, MAGE_RUNE), "sellable", label .. "and a mage's rune is one to sell, as it was")
        Equal(Status(hunter, HUNTER_BOOK), "own", label .. "the hunter's own book has its star")
        Equal(Status(hunter, HIGH_HUNTER_BOOK), "lowSkill", label .. "and one above its level the gear")
        Status(hunter, HIGH_MAGE_BOOK)
        Status(hunter, BOUND_MAGE_BOOK)
        Status(hunter, HUNTER_RUNE)
        Status(hunter, POTION_RECIPE)
        Status(hunter, PLAIN_POTION)
        local answers, spells = Answers(hunter, HUNTER)
        Equal(answers[MAGE_BOOK], "never", label .. "another class's book is answered \"never\"")
        Equal(answers[MAGE_RUNE], "never", label .. "and so is its rune")
        Equal(answers[HUNTER_BOOK], "own", label .. "its own book \"own\"")
        Equal(answers[HIGH_HUNTER_BOOK], "lowSkill", label .. "one above its level \"lowSkill\"")
        Equal(spells[HUNTER_BOOK], SPELL[HUNTER_BOOK], label .. "the spell of a book it may yet learn is kept with the answer")
        Equal(spells[MAGE_BOOK], nil, label .. "none for an answer that lasts")
        Equal(answers[POTION_RECIPE], nil, label .. "a profession's recipe is not answered for: it has its own rules")
        Equal(answers[PLAIN_POTION], nil, label .. "nor is what teaches nothing")
        local afterHunter = H.DeepCopy(hunter.env.CaerdonLearnerData)
        -- An item the list holds that this build of the game has not.
        afterHunter[HUNTER.realm][HUNTER.name].answers[GONE_ITEM] = "own"

        -- 2. The mage logs in: it answers for what the hunter came across without having
        --    seen any of it, in the background.
        local mage, mageKnown = Login(flavor, MAGE, afterHunter)
        local mageAnswers = Answers(mage, MAGE)
        Equal(next(mageAnswers), nil, label .. "the mage has answered nothing right after its login")
        mage:Tick(30, 1)
        mageAnswers = Answers(mage, MAGE)
        Equal(mageAnswers[MAGE_BOOK], "own", label .. "the mage answers \"own\" for its book, from the realm's list")
        Equal(mageAnswers[HIGH_MAGE_BOOK], "lowSkill", label .. "\"lowSkill\" for the one above its level")
        Equal(mageAnswers[MAGE_RUNE], "own", label .. "\"own\" for its rune")
        Equal(mageAnswers[HUNTER_BOOK], "never", label .. "\"never\" for the hunter's book")
        Equal(mageAnswers[BOUND_MAGE_BOOK], "own", label .. "and it answers for one that cannot be handed over as for any")
        Equal(mageAnswers[GONE_ITEM], nil, label .. "an ID the client has no item for is passed over")
        Equal(mageAnswers[POTION_RECIPE], nil, label .. "what no toon answered for is not on the list")
        Equal(#mage.errors, 0, label .. "no error on the way (" .. tostring(mage.errors[1]) .. ")")
        local state = mage.env.CaerdonLearners:GetDebugState()
        Check(state.asked >= 7 and state.waiting == 0, label .. "the export says how many were asked for: " .. tostring(state.asked))

        -- The mage learns its book with nothing of it on screen: the answer is "known" at once.
        mageKnown[SPELL[MAGE_RUNE]] = true
        mage:Fire("LEARNED_SPELL_IN_SKILL_LINE", SPELL[MAGE_RUNE], 1, false)
        mageAnswers = Answers(mage, MAGE)
        Equal(mageAnswers[MAGE_RUNE], "known", label .. "a spell learned makes its item's answer \"known\" at once")
        Equal(mageAnswers[MAGE_BOOK], "own", label .. "and leaves the other answers")
        local afterMage = H.DeepCopy(mage.env.CaerdonLearnerData)

        -- 3. The hunter again: what the mage can learn now is one to send.
        hunter = Login(flavor, HUNTER, afterMage)
        local status, item = Status(hunter, MAGE_BOOK)
        Equal(status, "send", label .. "a book the mage said it can learn has the mail icon on the hunter")
        local info = item:GetLearnerInfo()
        Check(info ~= nil and #info.now == 1 and info.now[1] == MAGE.name and info.answer == "never",
            label .. "and the learner info names the mage")
        Equal(Status(hunter, HIGH_MAGE_BOOK), "send", label .. "one the mage is below the level of is one to send as well")
        info = select(2, Status(hunter, HIGH_MAGE_BOOK)):GetLearnerInfo()
        Check(info ~= nil and #info.later == 1 and info.later[1] == MAGE.name and #info.now == 0,
            label .. "and the info has it as one for later")
        Equal(Status(hunter, MAGE_RUNE), "sellable", label .. "a rune the mage has learned is one to sell again")
        Equal(Status(hunter, BOUND_MAGE_BOOK), "collected", label .. "a book that binds on pickup is not one to send")
        Equal(select(2, Status(hunter, BOUND_MAGE_BOOK)):GetLearnerInfo(), nil, label .. "and has no learner info")
        Equal(Status(hunter, HUNTER_BOOK), "own", label .. "the hunter's own book keeps its star")
        Equal(Status(hunter, UNSEEN_MAGE_BOOK), "collected", label .. "a book the mage has not answered for has no icon")
        info = select(2, Status(hunter, UNSEEN_MAGE_BOOK)):GetLearnerInfo()
        Check(info ~= nil and #info.toons == 0 and info.unanswered[1] == MAGE.name,
            label .. "and the info says the mage has not answered")
        Equal(Status(hunter, POTION_RECIPE), "collected", label .. "a profession's recipe is left to its own rules")
        Equal(#hunter.errors, 0, label .. "no error (" .. tostring(hunter.errors[1]) .. ")")

        -- Its own answers that may change are asked again at login: the level it has reached
        -- since makes "lowSkill" of the saved "own", with nothing of the book on screen.
        local levelled = H.DeepCopy(afterMage)
        levelled[HUNTER.realm][HUNTER.name].answers[HIGH_HUNTER_BOOK] = "own"
        hunter = Login(flavor, HUNTER, levelled)
        hunter:Tick(30, 1)
        Equal((Answers(hunter, HUNTER))[HIGH_HUNTER_BOOK], "lowSkill", label .. "an answer that may change is asked again at login")
        Equal((Answers(hunter, HUNTER))[MAGE_BOOK], "never", label .. "one that lasts is kept")
        local debug = hunter.env.CaerdonLearners:GetDebugState()
        Check(debug.asked <= 4, label .. "and not asked for again: " .. tostring(debug.asked) .. " asked")

        -- 4. The switch of the recipes for other toons turns it off.
        hunter = Login(flavor, HUNTER, afterMage, { ShowRecipesForOtherToons = false })
        Equal(Status(hunter, MAGE_BOOK), "collected", label .. "switched off, the book has no mail icon")

        -- 5. A second copy of a book the hunter has learned, with another hunter that has not.
        local twoHunters = H.DeepCopy(afterMage)
        twoHunters[HUNTER.realm]["Yrrow"] = { answers = { [HUNTER_BOOK] = "own", [HUNTER_RUNE] = "own" }, spells = {} }
        local known
        hunter, known = Login(flavor, HUNTER, twoHunters)
        Equal(Status(hunter, HUNTER_BOOK), "own", label .. "a book both hunters can learn has the star on the one that holds it")
        known[SPELL[HUNTER_BOOK]] = true
        hunter:Fire("LEARNED_SPELL_IN_SKILL_LINE", SPELL[HUNTER_BOOK], 1, false)
        hunter:Tick(5)
        Equal(Status(hunter, HUNTER_BOOK), "send", label .. "once learned, the second copy is one to send to the other hunter")
        Equal((Answers(hunter, HUNTER))[HUNTER_BOOK], "known", label .. "and its own answer is \"known\"")
        known[SPELL[HUNTER_RUNE]] = true
        hunter:Fire("LEARNED_SPELL_IN_SKILL_LINE", SPELL[HUNTER_RUNE], 1, false)
        hunter:Tick(5)
        Equal(Status(hunter, HUNTER_RUNE), "send", label .. "the same for a rune, which is not called sellable then")
        Equal(#hunter.errors, 0, label .. "no error at the end (" .. tostring(hunter.errors[1]) .. ")")

        -- 6. The ledger. The mage carries a copy of its book: read from its bags when it is
        --    played, and the hunter's copy is then no longer one to send.
        local world
        mage, mageKnown, world = Login(flavor, MAGE, afterMage)
        world.bags = { PLAIN_POTION, MAGE_BOOK }
        mage:Fire("BAG_UPDATE_DELAYED")
        mage:Tick(4, 1)
        Equal(Ledger(mage, MAGE).bags[MAGE_BOOK], 1, label .. "ledger: a listed book in the mage's bags is counted")
        Equal(Ledger(mage, MAGE).bags[PLAIN_POTION], nil, label .. "ledger: what is on no list is not")
        hunter = Login(flavor, HUNTER, Saved(mage))
        status, item = Status(hunter, MAGE_BOOK)
        Equal(status, "collected", label .. "ledger: a book the mage carries a copy of has no mail icon on the hunter")
        info = item:GetLearnerInfo()
        Check(info ~= nil and #info.now == 0 and info.covered[1] == MAGE.name and info.toons[1].bags == 1,
            label .. "ledger: and the info says the mage has one")
        Equal(Status(hunter, HIGH_MAGE_BOOK), "send", label .. "ledger: a book it has no copy of keeps the icon")
        -- The copy is gone from the mage's bags the next time it is played: a sighting replaces.
        mage, mageKnown, world = Login(flavor, MAGE, Saved(hunter))
        mage:Tick(4, 1)
        Equal(Ledger(mage, MAGE).bags[MAGE_BOOK], nil, label .. "ledger: a copy no longer in the bags is no longer counted")
        local emptyBags = Saved(mage)

        -- The hunter sends the book: noted for the mage when the client says the mail went.
        local hunterWorld
        hunter, known, hunterWorld = Login(flavor, HUNTER, emptyBags)
        Equal(Status(hunter, MAGE_BOOK), "send", label .. "sent: before the mail the book is one to send")
        local refreshes = {}
        local core = hunter.env.CaerdonWardrobe
        local refresh = core.RefreshItems
        core.RefreshItems = function(self, reason, detail, ...)
            refreshes[#refreshes + 1] = tostring(reason) .. ": " .. tostring(detail)
            return refresh(self, reason, detail, ...)
        end
        hunterWorld.attached = { { PLAIN_POTION, 5 }, { MAGE_BOOK, 1 } }
        hunter.env.SendMail("stranger", "subject", "")
        hunter:Fire("MAIL_SEND_SUCCESS")
        Equal(#refreshes, 0, label .. "sent: a mail to somebody else is not noted")
        hunter.env.SendMail(MAGE.name:lower() .. "-Farrealm", "subject", "")
        Equal(Status(hunter, MAGE_BOOK), "send", label .. "sent: nothing is noted before the client says the mail went")
        hunter:Fire("MAIL_FAILED")
        hunter:Fire("MAIL_SEND_SUCCESS")
        Equal(#refreshes, 0, label .. "sent: a mail that failed is not noted")
        hunter.env.SendMail(MAGE.name, "subject", "")
        hunter:Fire("MAIL_SEND_SUCCESS")
        Equal(refreshes[1], "sent to another toon: item " .. MAGE_BOOK .. " to " .. MAGE.name,
            label .. "sent: a mail to the mage with its book refreshes, and says why")
        Equal(#refreshes, 1, label .. "sent: once")
        core.RefreshItems = refresh
        Equal(Status(hunter, MAGE_BOOK), "collected", label .. "sent: a second copy is no longer one to send")
        info = select(2, Status(hunter, MAGE_BOOK)):GetLearnerInfo()
        Check(info ~= nil and info.toons[1].sent == 1 and info.covered[1] == MAGE.name, label .. "sent: the info says one is on its way")
        Equal(#hunterWorld.sent, 3, label .. "sent: the client's own SendMail was called each time")
        local afterSend = Saved(hunter)

        -- The mage does not open its mailbox: the note stands. Then it does, and the mailbox
        -- is what counts: with the book in it, and after it took the book out and sold it.
        mage, mageKnown, world = Login(flavor, MAGE, afterSend)
        mage:Tick(4, 1)
        hunter = Login(flavor, HUNTER, Saved(mage))
        Equal(Status(hunter, MAGE_BOOK), "collected", label .. "mailbox: unopened, the sent copy still counts")
        world.inbox = { { { PLAIN_POTION, 5 } }, { { MAGE_BOOK, 1 }, { MAGE_BOOK, 1 } } }
        mage:Fire("MAIL_INBOX_UPDATE")
        Equal(Ledger(mage, MAGE).mail[MAGE_BOOK], 2, label .. "mailbox: the copies in it are counted")
        Equal(next(Ledger(mage, MAGE).sent), nil, label .. "mailbox: and what was sent is let go, since it has been seen")
        hunter = Login(flavor, HUNTER, Saved(mage))
        Equal(Status(hunter, MAGE_BOOK), "collected", label .. "mailbox: a copy in the mage's mailbox counts")
        world.inbox = {}
        mage:Fire("MAIL_INBOX_UPDATE")
        hunter = Login(flavor, HUNTER, Saved(mage))
        Equal(Status(hunter, MAGE_BOOK), "send", label .. "mailbox: taken out and not kept, the book is one to send again")

        -- A mailbox that shows a part of what it holds does not let go of what was sent.
        mage, mageKnown, world = Login(flavor, MAGE, afterSend)
        world.inbox, world.inboxTotal = { { { PLAIN_POTION, 5 } } }, 80
        mage:Fire("MAIL_INBOX_UPDATE")
        Check(Ledger(mage, MAGE).sent[MAGE_BOOK] ~= nil and Ledger(mage, MAGE).mailPartial == true,
            label .. "mailbox: one that shows a part keeps the note of what was sent")

        -- A note older than a mail lives is let go at the toon's login, and counts for nothing before.
        local old = H.DeepCopy(afterSend)
        old.CaerdonLedgerData[MAGE.realm][MAGE.name].sent[MAGE_BOOK][1].at = hunter.env.time() - 31 * 24 * 60 * 60
        hunter = Login(flavor, HUNTER, old)
        Equal(Status(hunter, MAGE_BOOK), "send", label .. "old: a mail that would have run out no longer counts")
        mage = Login(flavor, MAGE, old)
        mage:Tick(4, 1)
        Equal(Ledger(mage, MAGE).sent[MAGE_BOOK], nil, label .. "old: and its note is dropped when the toon is played")

        -- 7. The tooltip: a line a toon, those that can learn it now first, then later, then
        --    those that have a copy; five at most, then how many more.
        local crowd = H.DeepCopy(afterSend)
        local learners, ledgers = crowd.CaerdonLearnerData[HUNTER.realm], crowd.CaerdonLedgerData[HUNTER.realm]
        for index, answer in ipairs({ "lowSkill", "own", "known", "never", "own", "lowSkill", "own" }) do
            learners["Toon" .. index] = { answers = { [MAGE_BOOK] = answer }, spells = {}, level = 10 + index }
            ledgers["Toon" .. index] = { bags = {}, mail = {}, sent = {} }
        end
        ledgers.Toon5.mail[MAGE_BOOK] = 1
        ledgers.Toon7.bags[MAGE_BOOK] = 1
        local namespace
        hunter, known, hunterWorld, namespace = Login(flavor, HUNTER, crowd)
        status, item = Status(hunter, MAGE_BOOK)
        Equal(status, "send", label .. "tooltip: with toons that lack it the book is one to send")
        local lines = TooltipLines(namespace, item)
        Equal(#lines, 6, label .. "tooltip: five toons and a line for the rest")
        Check(lines[1].text == "Could be learned by: Toon2" and lines[1].green, label .. "tooltip: first who can learn it now, in green: " .. tostring(lines[1].text))
        Equal(lines[2].text, "Could be learned at a later level by: Toon1 (level 11)", label .. "tooltip: then who can later, with its level")
        Equal(lines[3].text, "Could be learned at a later level by: Toon6 (level 16)", label .. "tooltip: each on a line")
        Equal(lines[4].text, MAGE.name .. " already has one (on its way to it)", label .. "tooltip: then who has a copy, and where: sent to the mage")
        Equal(lines[5].text, "Toon5 already has one (in its mailbox)", label .. "tooltip: in a mailbox")
        Equal(lines[6].text, "and 1 more of your toons", label .. "tooltip: the one with a copy in its bags is the one more")
        Check(not lines[2].green and not lines[4].green, label .. "tooltip: only the first kind is green")
        Equal(#TooltipLines(namespace, select(2, Status(hunter, PLAIN_POTION))), 0, label .. "tooltip: nothing on an item no toon answered for")
        Equal(#TooltipLines(namespace, select(2, Status(hunter, BOUND_MAGE_BOOK))), 0, label .. "tooltip: nothing on a book that cannot be handed over")
        hunter.env.CaerdonWardrobeConfig.Tooltip.ShowRecipeLearners = false
        Equal(#TooltipLines(namespace, item), 0, label .. "tooltip: switched off, no line")
        Equal(#hunter.errors, 0, label .. "no error with the tooltip (" .. tostring(hunter.errors[1]) .. ")")

        -- 8. A copy the toon does not hold of something it can learn has no star while it
        --    has one already; the copy it holds keeps its own. An item made from its ID lies
        --    nowhere (an auction's row); one a window calls the toon's own is held.
        local function Held(client, itemID)
            local held = client.env.CaerdonItem:CreateFromItemLink(select(2, Status(client, itemID)):GetItemLink(), { ownCopy = true })
            return (select(2, held:GetCaerdonStatus()))
        end
        hunter, known, hunterWorld, namespace = Login(flavor, HUNTER, afterMage)
        local core = hunter.env.CaerdonWardrobe
        local reasons = {}
        local plainRefresh = core.RefreshItems
        core.RefreshItems = function(self, reason, detail, ...)
            reasons[#reasons + 1] = tostring(reason) .. ": " .. tostring(detail)
            return plainRefresh(self, reason, detail, ...)
        end
        Equal(Status(hunter, HUNTER_BOOK), "own", label .. "own copy: with none, a book it can learn has the star wherever it is seen")
        hunterWorld.bags = { HUNTER_BOOK }
        hunter:Fire("BAG_UPDATE_DELAYED")
        hunter:Tick(4, 1)
        Equal(reasons[1], "copies held: item " .. HUNTER_BOOK .. ": the toon has one now (the bags and the bank were read)",
            label .. "own copy: getting one refreshes, and says why")
        status, item = Status(hunter, HUNTER_BOOK)
        Equal(status, "collected", label .. "own copy: with one in the bags, another copy has no star")
        Equal(Held(hunter, HUNTER_BOOK), "own", label .. "own copy: the copy it holds keeps its star")
        local ownLines = {}
        local ownTooltip = { AddLine = function(_, text) ownLines[#ownLines + 1] = text end,
            GetPrimaryTooltipData = function() return { lines = {} } end }
        namespace.Tooltip:AddOwnCopies(ownTooltip, item)
        Equal(ownLines[1], "You already have one to learn (in your bags)", label .. "own copy: the other copy's tooltip says why")
        ownLines = {}
        ownTooltip.GetPrimaryTooltipData = function() return { lines = {}, guid = "Item-1-0-1" } end
        namespace.Tooltip:AddOwnCopies(ownTooltip, item)
        Equal(#ownLines, 0, label .. "own copy: the tooltip of the copy it holds says nothing")
        -- Moved to the bank: still one, and nothing is judged again.
        hunterWorld.bags, hunterWorld.bank = {}, { HUNTER_BOOK }
        hunter:Fire("BAG_UPDATE_DELAYED")
        hunter:Tick(4, 1)
        Equal(#reasons, 1, label .. "bank: a copy moved to the bank refreshes nothing")
        Equal(Ledger(hunter, HUNTER).bank[HUNTER_BOOK], 1, label .. "bank: it is counted there with the bank closed")
        Equal(Ledger(hunter, HUNTER).bags[HUNTER_BOOK], nil, label .. "bank: and no longer in the bags")
        Equal(Status(hunter, HUNTER_BOOK), "collected", label .. "bank: a copy in the bank holds the star back as well")
        Equal(Status(hunter, HIGH_HUNTER_BOOK), "lowSkill", label .. "bank: a book it has no copy of keeps its gear")
        local banked = Saved(hunter)
        -- Gone from the bank: the star is back.
        hunterWorld.bank = {}
        hunter:Fire("BAG_UPDATE_DELAYED")
        hunter:Tick(4, 1)
        Equal(#reasons, 2, label .. "bank: the copy gone refreshes")
        Equal(Status(hunter, HUNTER_BOOK), "own", label .. "bank: and the star is back")

        -- Bought at the auction house and not fetched: it counts from the purchase on.
        hunterWorld.auctions = { [501] = HIGH_HUNTER_BOOK, [502] = PLAIN_POTION, [503] = HUNTER_BOOK }
        hunter.env.C_AuctionHouse.PlaceBid(503, 100)
        Equal(Status(hunter, HUNTER_BOOK), "own", label .. "bought: a bid alone is no purchase")
        hunter.env.C_AuctionHouse.PlaceBid(501, 100)
        hunter.env.C_AuctionHouse.PlaceBid(502, 100)
        hunter:Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 502)
        Equal(#reasons, 2, label .. "bought: what the ledger does not count is not noted")
        hunter:Fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 501)
        Equal(reasons[3], "copies held: item " .. HIGH_HUNTER_BOOK .. ": the toon has one now (bought at the auction house)",
            label .. "bought: the purchase refreshes at once, and says why")
        status, item = Status(hunter, HIGH_HUNTER_BOOK)
        Equal(status, "collected", label .. "bought: the next copy has no gear before the mailbox was opened")
        ownLines = {}
        ownTooltip.GetPrimaryTooltipData = function() return { lines = {} } end
        namespace.Tooltip:AddOwnCopies(ownTooltip, item)
        Equal(ownLines[1], "You already have one to learn (on its way to your mailbox)", label .. "bought: and its tooltip says one is on its way")
        -- The mailbox opened: the copy is counted there, and the note is let go.
        hunterWorld.inbox = { { { HIGH_HUNTER_BOOK, 1 } } }
        hunter:Fire("MAIL_INBOX_UPDATE")
        Equal(Ledger(hunter, HUNTER).mail[HIGH_HUNTER_BOOK], 1, label .. "bought: the mailbox has it once it is opened")
        Equal(next(Ledger(hunter, HUNTER).sent), nil, label .. "bought: and the note of the purchase is let go")
        Equal(#reasons, 3, label .. "bought: which changes nothing about having one")
        Equal(Status(hunter, HIGH_HUNTER_BOOK), "collected", label .. "bought: still no gear on another copy")
        Equal(Held(hunter, HIGH_HUNTER_BOOK), "lowSkill", label .. "bought: the copy in its own mailbox keeps its gear")
        -- Taken out of the mail into the bags, the mailbox's event first: the toon has one
        -- all along, and nothing is judged again (a WoW Forever client judged everything
        -- again for each recipe taken out of a mail).
        hunterWorld.inbox = {}
        hunter:Fire("MAIL_INBOX_UPDATE")
        Equal(#reasons, 3, label .. "taken: the mailbox without it is not judged before the bags are read")
        hunterWorld.bags = { HIGH_HUNTER_BOOK }
        hunter:Fire("BAG_UPDATE_DELAYED")
        hunter:Tick(4, 1)
        Equal(#reasons, 3, label .. "taken: a copy that went from a mail into the bags refreshes nothing")
        Equal(Ledger(hunter, HUNTER).bags[HIGH_HUNTER_BOOK], 1, label .. "taken: it is counted in the bags")
        Equal(Ledger(hunter, HUNTER).mail[HIGH_HUNTER_BOOK], nil, label .. "taken: and no longer in the mailbox")
        -- A mail that went with its copy (sent back, deleted): the bags' reading says so.
        hunterWorld.bags, hunterWorld.inbox = {}, { { { HIGH_HUNTER_BOOK, 1 } } }
        hunter:Fire("MAIL_INBOX_UPDATE")
        hunter:Fire("BAG_UPDATE_DELAYED")
        hunter:Tick(4, 1)
        Equal(#reasons, 3, label .. "taken: back in a mail, the toon still has one")
        hunterWorld.inbox = {}
        hunter:Fire("MAIL_INBOX_UPDATE")
        Equal(#reasons, 3, label .. "taken: a mail gone with its copy is not judged at the mailbox's event")
        hunter:Tick(4, 1)
        Equal(reasons[4], "copies held: item " .. HIGH_HUNTER_BOOK .. ": the toon has none now (the bags and the bank were read)",
            label .. "taken: but once the bags were read and have none, and it says why")
        Equal(#reasons, 4, label .. "taken: once")
        core.RefreshItems = plainRefresh

        -- A copy that lay in the bank before the ledger was there, of something nothing has
        -- asked about: written down the moment the toon comes across the item anywhere, with
        -- no reading of the bags in between (a WoW Forever client: a recipe in each of two
        -- toons' banks, and each took the other to have none).
        local unasked = H.DeepCopy(afterMage)
        unasked[HUNTER.realm][HUNTER.name].answers[HUNTER_RUNE] = nil
        hunter, known, hunterWorld = Login(flavor, HUNTER, unasked)
        hunter:Tick(40, 1)
        hunterWorld.bank = { HUNTER_RUNE }
        Equal(Ledger(hunter, HUNTER).bank[HUNTER_RUNE], nil, label .. "unasked: a rune in the bank that nothing has asked about is not known")
        local before = hunter.env.CaerdonLedger:GetDebugState().bagReads
        Equal(Status(hunter, HUNTER_RUNE), "collected", label .. "unasked: another copy of it has no star")
        Equal(Ledger(hunter, HUNTER).bank[HUNTER_RUNE], 1, label .. "unasked: and what the client counted is written down for the other toons at once")
        Equal(hunter.env.CaerdonLedger:GetDebugState().bagReads, before, label .. "unasked: with no reading of the bags in between")
        hunter:Tick(4, 1)
        Equal(hunter.env.CaerdonLedger:GetDebugState().refreshes, 0, label .. "unasked: and the reading that follows takes it for no change")

        -- The other toons read the bank too: the mage's book in the mage's bank.
        mage, mageKnown, world = Login(flavor, MAGE, afterMage)
        world.bank = { MAGE_BOOK }
        mage:Tick(40, 1)
        Equal(Ledger(mage, MAGE).bank[MAGE_BOOK], 1, label .. "bank: a book the toon could learn is asked about though it never lay in its bags")
        hunter = Login(flavor, HUNTER, Saved(mage))
        status, item = Status(hunter, MAGE_BOOK)
        Equal(status, "collected", label .. "bank: a copy in the mage's bank is no reason to send it another")
        Equal(#hunter.errors + #mage.errors, 0, label .. "no error with own copies (" .. tostring(hunter.errors[1] or mage.errors[1]) .. ")")
        Equal(#mage.errors + #hunter.errors, 0, label .. "no error with the ledger (" .. tostring(mage.errors[1] or hunter.errors[1]) .. ")")
    end
end
