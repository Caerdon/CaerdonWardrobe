-- Loads the addon's own files into a mocked client, in the order the game does: the TOC's
-- lines top to bottom, an XML file's <Script> tags in place, and a <Frame> with a mixin
-- created where it stands with its OnLoad run.
--
-- The whole addon is not loaded by default. The features and integrations hook Blizzard's
-- windows and other addons, which a mocked client does not have; the settings pages build
-- widgets. What is loaded is the item side: everything that decides a status. A scenario that
-- needs more passes its own `skip`.

local H = ...

-- Folders of the addon that the item side does not need.
H.ITEM_SIDE_SKIP = { "^libs/", "^config/", "^features/", "^external/", "^localization/" }

-- Blizzard's Lua that the item side runs on (see the file for why it is a list of its own).
H.BLIZZARD_BASE = dofile(H.dir .. "/blizzard-base.lua")

function H.LoadBlizzardBase(client)
    for _, relative in ipairs(H.BLIZZARD_BASE) do
        client:LoadBlizzard(relative)
    end
end

local function Skipped(relative, skip)
    if type(skip) == "function" then
        return skip(relative)
    end
    for _, pattern in ipairs(skip) do
        if relative:find(pattern) then
            return true
        end
    end
    return false
end

local function DirOf(relative)
    return relative:match("^(.*)/[^/]*$") or ""
end

local function Join(dir, file)
    file = file:gsub("\\", "/")
    return dir == "" and file or (dir .. "/" .. file)
end

-- A <Frame name="X" mixin="M"> ... <OnLoad method="OnLoad"/> ... </Frame> of the addon's XML.
local function CreateXmlFrame(client, attributes, body)
    local name = attributes:match('%f[%w]name%s*=%s*"([^"]+)"')
    local mixin = attributes:match('[mM]ixin%s*=%s*"([^"]+)"')
    local frame = client:NewFrame("Frame", name)
    if attributes:find('hidden%s*=%s*"true"') then
        frame:Hide()
    end
    if mixin then
        for mixinName in mixin:gmatch("[%w_]+") do
            local source = client.env[mixinName]
            if type(source) ~= "table" then
                error(("the frame %s names the mixin %s, which is not there"):format(tostring(name), mixinName), 0)
            end
            for key, value in pairs(source) do
                frame[key] = value
            end
        end
    end
    local onLoad
    for script, method in body:gmatch('<(On%a+)%s+method%s*=%s*"([^"]+)"') do
        if script == "OnLoad" then
            onLoad = frame[method]
        else
            frame:SetScript(script, frame[method])
        end
    end
    if onLoad then
        onLoad(frame)
    end
    return frame
end

local function LoadXml(client, addonName, folder, relative, namespace, skip, loaded)
    local text = H.ReadFile(folder .. "/" .. relative)
    if not text then
        error("the addon names " .. relative .. ", which is missing", 0)
    end
    text = text:gsub("<!%-%-.-%-%->", "")
    local dir = DirOf(relative)
    local position = 1
    while true do
        local scriptAt, scriptEnd, file = text:find('<Script%s+file%s*=%s*"([^"]+)"%s*/>', position)
        local frameAt, frameEnd, attributes, body = text:find("<Frame%s+([^>]-)>(.-)</Frame>", position)
        if not scriptAt and not frameAt then
            break
        end
        if scriptAt and (not frameAt or scriptAt < frameAt) then
            local target = Join(dir, file)
            if not Skipped(target, skip) then
                client:LoadAddonFile(addonName, folder, target, namespace)
                loaded[#loaded + 1] = target
            end
            position = scriptEnd + 1
        else
            if not Skipped(relative, skip) and attributes:find("[mM]ixin%s*=") then
                CreateXmlFrame(client, attributes, body)
            end
            position = frameEnd + 1
        end
    end
end

-- Loads an addon of the repository. folder is where its TOC is; skip is a list of patterns
-- for paths (relative to the folder, forward slashes) to leave out, or a function that says
-- so for a path. Returns the addon's private table and the files loaded.
function H.LoadAddon(client, addonName, folder, skip)
    skip = skip or H.ITEM_SIDE_SKIP
    local toc = H.ReadFile(folder .. "/" .. addonName .. ".toc")
    if not toc then
        error("no TOC file in " .. folder, 0)
    end
    local namespace, loaded = {}, {}
    for line in toc:gmatch("[^\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local relative = line:gsub("\\", "/")
            if not Skipped(relative, skip) then
                if relative:lower():find("%.xml$") then
                    LoadXml(client, addonName, folder, relative, namespace, skip, loaded)
                elseif H.ReadFile(folder .. "/" .. relative) then
                    client:LoadAddonFile(addonName, folder, relative, namespace)
                    loaded[#loaded + 1] = relative
                end
                -- A TOC line for a file that is not there (an untracked *.local.lua) is passed
                -- over, as the client does.
            end
        end
    end
    return namespace, loaded
end
