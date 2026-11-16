-- The BaudBag and Inventorian integration files against stubs of their addons: Refresh() has
-- to ask for every button again.
--   luajit tools/harness/standalone/integration-refresh.lua [repo dir]
-- tools/harness/run.lua runs it with the scenarios. The stubs are written from reading the
-- two addons' code, so this checks the integrations' logic and not those addons.
local ROOT = arg[1] or "."
local checks, failures = 0, 0
local function Check(condition, label)
    checks = checks + 1
    if not condition then failures = failures + 1 print("FAIL: " .. label) end
end

local requests, cleared, cancelled, registered
local function Reset() requests, cleared, cancelled = {}, 0, 0 end

format = string.format
BANK_CONTAINER = -1
hooksecurefunc = function(owner, key, hook)
    local original = owner[key]
    owner[key] = function(...) original(...) hook(...) end
end
C_Timer = { After = function(_, fn) fn() end }
C_AddOns = {
    GetAddOnInfo = function(name) return name, name, "", true end,
    IsAddOnLoaded = function() return true end,
    GetAddOnMetadata = function() return "1" end,
}
C_Container = { GetContainerItemID = function() return 1 end }
CaerdonItem = {
    CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end,
    CreateFromItemLink = function(_, link) return { link = link } end,
}
CaerdonWardrobeFeatureMixin = {
    Refresh = function(_, feature) cancelled = cancelled + 1 end,
    NoteHookPoint = function() return true end,
}
CaerdonWardrobe = {
    RegisterFeature = function(_, mixin)
        registered = setmetatable({}, { __index = function(_, key) return mixin[key] or CaerdonWardrobeFeatureMixin[key] end })
    end,
    UpdateButton = function(_, button, item, feature, locationInfo)
        requests[#requests + 1] = { button = button, item = item, locationInfo = locationInfo }
    end,
    ClearButton = function() cleared = cleared + 1 end,
}
local namespace = { L = setmetatable({}, { __index = function(_, key) return key end }) }

local function Load(path)
    registered = nil
    assert(loadfile(ROOT .. "/" .. path))("CaerdonWardrobe", namespace)
    assert(registered, "the file registered no feature")
    return registered
end

print("BaudBag")
do
    BaudBag = {
        ItemSlot_Updated = function() end,
        Cache = { UsesCache = function(_, bag) return bag == 6 end, GetBagCache = function() return { [1] = { Link = "link" } } end },
    }
    local feature = Load("external/BaudBag/Core.BaudBag.lua")
    feature:Init()
    Reset()
    local a, b, c = {}, {}, {}
    BaudBag:ItemSlot_Updated("set", 1, 0, 3, a)
    BaudBag:ItemSlot_Updated("set", 1, 1, 2, b)
    BaudBag:ItemSlot_Updated("set", 2, 6, 1, c) -- a bank bag read from the cache
    Check(#requests == 3, "three draws asked for when the slots are reported: " .. #requests)
    BaudBag:ItemSlot_Updated("set", 1, 0, 4, a) -- the button moves to another slot
    Reset()
    feature:Refresh()
    Check(cancelled == 1, "the feature's pending requests are cancelled first")
    Check(#requests == 3, "Refresh asks for every tracked button again: " .. #requests)
    local seen = {}
    for _, request in ipairs(requests) do
        local where = request.locationInfo
        seen[request.button] = where.isOffline and "offline" or (where.bag .. "/" .. where.slot)
    end
    Check(seen[a] == "0/4" and seen[b] == "1/2" and seen[c] == "offline", "each for the slot it was last drawn for: " .. tostring(seen[a]))
end

print("Inventorian")
do
    local function Button(bag, slot, cached)
        return { bag = bag, slot = slot, GetInfo = function() return nil, 1, false, 1, false, false, cached and "link" or nil end,
            IsCached = function() return cached end }
    end
    local addon = {
        bag = { itemContainer = { UpdateSlot = function() end, items = { [1] = Button(0, 1), [102] = Button(1, 2) } } },
        bank = { itemContainer = { UpdateSlot = function() end, items = { [601] = Button(6, 1, true) } } },
    }
    function addon:NewModule() return {} end
    LibStub = function() return { GetAddon = function() return addon end } end
    local feature = Load("external/Inventorian/Core.Inventorian.lua")
    feature:Init()
    Reset()
    feature:Refresh()
    Check(#requests == 3, "Refresh reads the windows even before the module is enabled: " .. #requests)
    feature.mod.OnEnable(feature.mod)
    Reset()
    addon.bag.itemContainer:UpdateSlot(0, 1)
    Check(#requests == 1 and requests[1].button == addon.bag.itemContainer.items[1], "a reported slot is drawn")
    Reset()
    feature:Refresh()
    Check(cancelled == 1 and #requests == 3, "Refresh asks for every button of both windows again: " .. #requests)
    local offline = 0
    for _, request in ipairs(requests) do
        if request.locationInfo.isOffline then offline = offline + 1 end
    end
    Check(offline == 1, "the bank away from the bank is drawn from its link")
    addon.bag, addon.bank = nil, nil
    Reset()
    feature:Refresh()
    Check(#requests == 0, "without its windows Refresh does nothing and raises no error")
end

print(("%d checks, %d failed"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
