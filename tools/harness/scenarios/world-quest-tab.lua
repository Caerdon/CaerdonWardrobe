-- World Quest Tab's list and pins (external/WorldQuestTab/Core.WorldQuestTab.lua).
--
-- The stand-in has what the feature reads of World Quest Tab 12.1.05, in the shapes of its
-- source: the list container with its scroll box, a row with its rewards frame and reward
-- frames, a quest's info with its sorted rewards (GetReward), the reward types as flags
-- (WQT_REWARDTYPE), and the callback registry that says when a pin is set up.
--
--   1. The feature registers beside World Quest Tab and finds its hook points.
--   2. A row's reward icons: an item reward is asked for with the quest's own link for it,
--      found by its item, since World Quest Tab sorts a quest's rewards.
--   3. A currency, gold, and a reward frame that is hidden are cleared.
--   4. A row that shows another quest by the time the item loads is not this draw's.
--   5. A pin: the quest's best reward, and cleared where the quest has none.
--   6. An error of the feature's goes to the error handler and not into the scroll box.
--
-- Logic only: no client has shown it yet.

return function(H, S)
    local Check, Equal = S.Check, S.Equal

    local TOON = { name = "Zzyxa", realm = "Farrealm", class = "Hunter", classFile = "HUNTER", race = "Dwarf",
        faction = "Alliance", level = 29 }

    local CLOAK, GEM = 952001, 952002
    local ITEMS = {}
    for _, id in ipairs({ CLOAK, GEM }) do
        ITEMS[id] = { name = "Reward " .. id, quality = 2, level = 5, minLevel = 0, type = "Miscellaneous",
            subType = "Junk", stack = 20, price = 5, classID = 15, subClassID = 0 }
    end
    local QUEST, OTHER_QUEST, BARE_QUEST = 61001, 61002, 61003
    local TYPES = { weapon = 1, equipment = 2, conduit = 4, relic = 8, anima = 16, artifact = 32, spell = 64, item = 128,
        currency = 256, gold = 512, honor = 1024, reputation = 2048, xp = 4096, missing = 8192, none = 0 }

    local function Start(flavor)
        local game = H.StockGame(TOON, ITEMS)
        local world = { game = game, asked = {}, cleared = {}, rowCallbacks = {}, registered = {} }

        -- The quest's own rewards, in the client's order: the gem first, the cloak second.
        local questRewards = { [QUEST] = { GEM, CLOAK }, [OTHER_QUEST] = { GEM }, [BARE_QUEST] = {} }
        game:Set("GetNumQuestLogRewards", function(questID) return #(questRewards[questID] or {}) end)
        game:Set("GetQuestLogRewardInfo", function(index, questID)
            local id = (questRewards[questID] or {})[index]
            if world.clientFails then
                error("the client's reward call raised an error")
            end
            return id and ITEMS[id].name, 134400, 1, 2, true, id, 5
        end)
        game:Set("GetQuestLogItemLink", function(kind, index, questID)
            local id = (questRewards[questID] or {})[index]
            return id and game.Link(id) or nil
        end)
        game:Set("QuestUtils_GetBestQualityItemRewardIndex", function(questID)
            if #(questRewards[questID] or {}) == 0 then
                return nil, nil
            end
            return 1, "reward"
        end)
        game:Set("ScrollUtil", { AddInitializedFrameCallback = function(scrollBox, callback, owner)
            world.rowCallbacks[#world.rowCallbacks + 1] = { scrollBox = scrollBox, callback = callback, owner = owner }
        end })
        game:Set("WQT_REWARDTYPE", TYPES)
        game:Set("WQT_CallbackRegistry", { RegisterCallback = function(registry, event, callback, owner)
            world.registered[event] = { callback = callback, owner = owner }
        end })
        world.scrollBox = {}
        game:Set("WQT_ListContainer", { GetQuestScrollBox = function() return world.scrollBox end })
        game:Set("C_AddOns.GetAddOnInfo", function(name) return name, name, "", name == "WorldQuestTab" end)
        game:Set("C_AddOns.IsAddOnLoaded", function(name) return name == "WorldQuestTab" end)
        game:Set("C_AddOns.GetAddOnMetadata", function() return "12.1.05" end)

        local client = H.Client.New({ flavor = flavor, provider = game })
        game.client = client
        H.LoadBlizzardBase(client)
        local namespace = H.LoadAddon(client, "CaerdonWardrobe", H.addonDir)
        client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "config/Config.lua", namespace)
        rawset(client.env, "CaerdonWardrobeConfig", H.DeepCopy(namespace:GetDefaultConfig()))
        local core = client.env.CaerdonWardrobe
        if not core:GetFeature("WorldQuestTab") then
            client:LoadAddonFile("CaerdonWardrobe", H.addonDir, "external/WorldQuestTab/Core.WorldQuestTab.lua", namespace)
        end
        client:Fire("ADDON_LOADED", "CaerdonWardrobe")
        client:Fire("VARIABLES_LOADED")
        client:Fire("PLAYER_LOGIN")
        client:Fire("PLAYER_ENTERING_WORLD", true, false)
        client:Tick(10)

        world.client, world.env, world.core = client, client.env, core
        world.feature = core:GetFeature("WorldQuestTab")

        local realUpdate, realClear = core.UpdateButton, core.ClearButton
        function core:UpdateButton(button, item, feature, locationInfo, options)
            world.asked[#world.asked + 1] = { button = button, id = item and item:GetItemID(), feature = feature,
                key = locationInfo and locationInfo.locationKey, locationInfo = locationInfo }
            return realUpdate(self, button, item, feature, locationInfo, options)
        end
        function core:ClearButton(button)
            world.cleared[button] = (world.cleared[button] or 0) + 1
            return realClear(self, button)
        end
        function core:SetItemButtonStatus() end
        function core:SetItemButtonMogStatusFilter() end
        function core:SetItemButtonBindType() end

        -- A quest's info as World Quest Tab keeps it: its rewards sorted its own way.
        function world.QuestInfo(questID, rewards)
            local info = { questID = questID, rewardList = rewards }
            function info:GetReward(index) return self.rewardList[index] end
            return info
        end
        -- A row with three reward frames, the first `shown` of them shown.
        function world.Row(shown)
            local row = client:NewFrame("Button")
            local rewards = { rewardFrames = {} }
            for index = 1, 3 do
                local frame = client:NewFrame("Frame", nil, row)
                frame:SetSize(32, 32)
                frame.Amount = client:NewFrame("FontString", nil, frame)
                frame:SetShown(index <= shown)
                rewards.rewardFrames[index] = frame
            end
            function row:GetRewardsFrame() return rewards end
            row.frames = rewards.rewardFrames
            return row
        end
        function world.Fill(row, questInfo)
            row.questInfo, row.questID = questInfo, questInfo.questID
            for _, entry in ipairs(world.rowCallbacks) do
                entry.callback(entry.owner, row, { questInfo = questInfo })
            end
            client:Tick(3)
        end
        function world.Last(button)
            for index = #world.asked, 1, -1 do
                if world.asked[index].button == button then
                    return world.asked[index]
                end
            end
            return {}
        end
        return world
    end

    for _, flavor in ipairs({ "retail" }) do
        local label = flavor .. ": "
        local world = Start(flavor)
        local feature = world.feature

        -- 1.
        Check(feature ~= nil, label .. "the file registers its feature beside World Quest Tab")
        Equal(#world.rowCallbacks, 1, label .. "the list's rows are listened for, once")
        Check(world.rowCallbacks[1] and world.rowCallbacks[1].scrollBox == world.scrollBox, label .. "on World Quest Tab's own scroll box")
        Check(world.registered["WQT.MapPinProvider.PinInitialized"] ~= nil, label .. "a pin set up is listened for")
        local noted = feature and feature.hookPointsNoted or {}
        Equal(noted["WQT_ListContainer:GetQuestScrollBox"] and noted["WQT_ListContainer:GetQuestScrollBox"].found, 1,
            label .. "the list's hook point is noted as found")
        Equal(#world.client.errors, 0, label .. "no error at the start")

        -- 2. World Quest Tab lists the cloak first and the gem second; the quest has them the
        -- other way round.
        local row = world.Row(3)
        world.Fill(row, world.QuestInfo(QUEST, {
            { id = CLOAK, type = TYPES.equipment, amount = 5 },
            { id = GEM, type = TYPES.item, amount = 1 },
            -- A currency whose ID is also an item's among the quest's rewards.
            { id = GEM, type = TYPES.currency, amount = 50 },
        }))
        Equal(world.Last(row.frames[1]).id, CLOAK, label .. "the first reward icon is asked for with the cloak, the quest's second reward")
        Equal(world.Last(row.frames[2]).id, GEM, label .. "the second with the gem, the quest's first")
        Equal(world.Last(row.frames[1]).key, "wqtQuest" .. QUEST .. "Reward1", label .. "under the quest's and the icon's own key")
        Check(world.Last(row.frames[1]).feature == feature, label .. "as the World Quest Tab feature's button")

        -- 3.
        Equal(world.Last(row.frames[3]).id, nil, label .. "a currency is not asked for")
        Check((world.cleared[row.frames[3]] or 0) >= 1, label .. "and its icon is cleared")
        local hidden = world.Row(1)
        world.Fill(hidden, world.QuestInfo(QUEST, {
            { id = CLOAK, type = TYPES.equipment, amount = 5 },
            { id = GEM, type = TYPES.item, amount = 1 },
        }))
        Equal(world.Last(hidden.frames[1]).id, CLOAK, label .. "a shown reward icon is asked for")
        Equal(world.Last(hidden.frames[2]).id, nil, label .. "a reward icon World Quest Tab hides is not")
        Check((world.cleared[hidden.frames[2]] or 0) >= 1, label .. "and is cleared")
        local gold = world.Row(1)
        world.Fill(gold, world.QuestInfo(BARE_QUEST, { { id = 0, type = TYPES.gold, amount = 500 } }))
        Equal(world.Last(gold.frames[1]).id, nil, label .. "gold is not asked for")

        -- 4.
        local asked = world.Last(row.frames[1])
        Check(feature:IsSameItem(row.frames[1], nil, asked.locationInfo) == true, label .. "the row still shows the quest: the draw is its own")
        row.questID = OTHER_QUEST
        Check(feature:IsSameItem(row.frames[1], nil, asked.locationInfo) == false, label .. "the row shows another quest by now: the draw is not")
        row.questID = QUEST

        -- 5.
        local pinCallback = world.registered["WQT.MapPinProvider.PinInitialized"]
        local pin = world.client:NewFrame("Frame")
        local pinButton = world.client:NewFrame("Button", nil, pin)
        function pin:GetButton() return pinButton end
        pin.questID = QUEST
        pinCallback.callback(pinCallback.owner, pin)
        world.client:Tick(3)
        Equal(world.Last(pinButton).id, GEM, label .. "a pin's button is asked for with the quest's best reward")
        Equal(world.Last(pinButton).key, "wqtPin" .. QUEST, label .. "under the pin's own key")
        pin.questID = BARE_QUEST
        local before = world.cleared[pinButton] or 0
        pinCallback.callback(pinCallback.owner, pin)
        world.client:Tick(3)
        Equal((world.cleared[pinButton] or 0) - before, 1, label .. "a pin of a quest with no item is cleared")

        Equal(#world.client.errors, 0, label .. "no error reached the error handler so far")

        -- 6.
        world.clientFails = true
        local ok, problem = pcall(world.Fill, world.Row(1), world.QuestInfo(QUEST, { { id = CLOAK, type = TYPES.equipment, amount = 5 } }))
        Check(ok, label .. "an error of the feature's does not reach the scroll box (" .. tostring(problem) .. ")")
        Equal(#world.client.errors, 1, label .. "it goes to the error handler")
        world.clientFails = false

        -- The declaration: no level gain over World Quest Tab's own amount.
        Equal(feature.displayRules.levelGain, false, label .. "no level gain on a reward's icon")
    end
end
