-- Public shell, shared runtime and GUI adapters. Staff tools are optional packages.
local _, private = ...
local Lib = LibStub and LibStub("NobleNextLib-1.0", true)
if not Lib or (Lib.API_LEVEL or 0) < 5 then
    error("NobleNext requires NobleNextLib 0.3.182 (API_LEVEL >= 5).")
end
local ns = Lib.Runtime
setmetatable(private, {__index=ns, __newindex=ns})
_G.NobleNextAPI = ns
ns.ADDON_NAME = "NobleNext"
ns.ADDON_PREFIX = "NobleNext"

local NNL = Lib

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(ns.ADDON_PREFIX)
end

-- ---------------------------------------------------------------------------
-- Debug helpers
-- ---------------------------------------------------------------------------
local function SafeCall(label, func, ...)
    local ok, result = pcall(func, ...)
    if not ok then
        print("|cffff0000[NobleNext ERROR]|r " .. label .. ": " .. tostring(result))
    end
    return ok, result
end

ns.GO_ADD_PATTERN = ">>%s*Add%s+Game%s+Object%s+'?%d+'?%s*%(([^%)]+)%)%s*%(GUID:%s*(%d+)%)"

local function OnGoSpawned(guid, name, entry)
    guid = tonumber(guid)
    if not guid then return end
    entry = tonumber(entry)
    name = name or "?"
    ns.LastSpawnedGoGuid = guid
    ns.LastSpawnedGoName = name
    ns.LastSpawnedGoEntry = entry
    if ns.SelectionContext and ns.SelectionContext.SetGo then
        ns.SelectionContext.SetGo(guid, entry, name)
    end
    if _G.NobleNextGobMover and _G.NobleNextGobMover.SetTarget then
        _G.NobleNextGobMover.SetTarget(guid, name, nil, entry)
    elseif _G.NobleNextGoMover and _G.NobleNextGoMover.SetTarget then
        _G.NobleNextGoMover.SetTarget(guid, name, nil, entry)
    end
    -- Единый fan-out для undo/прочих подписчиков (см. Core/Events.lua).
    if ns.Emit then
        ns.Emit("GO_SPAWNED", { guid = guid, name = name, entry = entry })
    end
end

-- Единственный парсер CHAT_MSG_SYSTEM для .gob add (GUID).
local gobSpawnFrame = CreateFrame("Frame")
gobSpawnFrame:RegisterEvent("CHAT_MSG_SYSTEM")
gobSpawnFrame:SetScript("OnEvent", function(_, _, msg)
    if not msg then return end
    local name, guid = msg:match(ns.GO_ADD_PATTERN)
    if guid then
        local entry = msg:match(">>%s*Add%s+Game%s+Object%s+'?(%d+)'?")
        OnGoSpawned(guid, name, entry)
    end
end)

-- ---------------------------------------------------------------------------
-- Theme / print (backed by NobleNextLib)
-- ---------------------------------------------------------------------------
ns.COLORS = NNL.Theme.COLORS

function ns.Color(name, text)
    return NNL.Theme.Color(name, text)
end

function ns.Print(msg)
    print(ns.Color("gold", "[" .. ns.ADDON_NAME .. "] ") .. msg)
end

function ns.PrintDebug(msg)
    if NobleNextDB and NobleNextDB.debug then
        print(ns.Color("gray", "[" .. ns.ADDON_NAME .. "|debug] ") .. msg)
    end
end

function ns.PrintError(msg)
    print(ns.Color("error", "[" .. ns.ADDON_NAME .. "] ") .. msg)
end

-- ---------------------------------------------------------------------------
-- CreateNG* adapters (compat shims -> NobleNextLib)
-- ---------------------------------------------------------------------------
function ns.CreateNGSection(parent, titleText, width, height)
    return NNL.Widgets.CreateSectionLegacy(parent, titleText, width, height)
end

function ns.CreateNGButton(parent, text, width, height)
    return NNL.Widgets.CreateButton(parent, {
        text = text,
        width = width,
        height = height,
    })
end

function ns.CreateNGIconButton(parent, name, width, height)
    return NNL.Widgets.CreateIconButton(parent, {
        name = (parent:GetName() or "NobleNext") .. "_IconBtn_" .. tostring(name):gsub("[^%w_]", "_"),
        width = width,
        height = height,
    })
end

function ns.CreateNGLabel(parent, text, outline)
    return NNL.Widgets.CreateLabel(parent, { text = text, outline = outline })
end

function ns.CreateNGEditBox(parent, name, width, height)
    return NNL.Widgets.CreateEditBoxLegacy(parent, name, width, height)
end

function ns.CreateNGTab(parent, text, index, onClick)
    return NNL.Tabs.Create(parent, text, index, function(btn)
        if onClick then onClick(btn) end
    end)
end

function ns.SetNGTabSelected(btn, selected)
    return NNL.Tabs.SetSelected(btn, selected)
end

function ns.CreateMiniWindow(options)
    if NNL.Window and NNL.Window.CreateMini then
        return NNL.Window.CreateMini(options)
    end
    return nil
end

ns.Layout = NNL.Layout
ns.Confirm = NNL.Confirm
ns.NNL = NNL

-- ---------------------------------------------------------------------------
-- Saved variables / UI layout schema
-- ---------------------------------------------------------------------------
local LAYOUT_VERSION = 3
local SIDEBAR_W = 180
local DEFAULT_W, DEFAULT_H = 960, 620
local MIN_W, MIN_H = 820, 500 -- post-migration: enlarge + shrink (wider sidebar)
local MAX_W, MAX_H = 1400, 900
local ALLOW_SHRINK = true

local function DefaultWindow()
    return {
        width = DEFAULT_W,
        height = DEFAULT_H,
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
    }
end

local function ValidateWindow(win)
    if type(win) ~= "table" then return DefaultWindow() end
    local points = {
        CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
        TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
    }
    local w = tonumber(win.width)
    local h = tonumber(win.height)
    local x = tonumber(win.x) or 0
    local y = tonumber(win.y) or 0
    if not w or not h or w ~= w or h ~= h then
        return DefaultWindow()
    end
    local point = points[win.point] and win.point or "CENTER"
    local rel = points[win.relativePoint] and win.relativePoint or point
    w = math.max(MIN_W, math.min(MAX_W, w))
    h = math.max(MIN_H, math.min(MAX_H, h))
    return {
        width = w,
        height = h,
        point = point,
        relativePoint = rel,
        x = x,
        y = y,
    }
end

local function EnsureDB()
    NobleNextDB = NobleNextDB or {}
    NobleNextCharDB = NobleNextCharDB or {}
    NobleNextDB.ui = NobleNextDB.ui or {}
    if NobleNextDB.ui.layoutVersion ~= LAYOUT_VERSION then
        NobleNextDB.ui.layoutVersion = LAYOUT_VERSION
        if not NobleNextDB.ui.window then
            NobleNextDB.ui.window = DefaultWindow()
        end
    end
    NobleNextDB.ui.window = ValidateWindow(NobleNextDB.ui.window)
    return NobleNextDB
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "NobleNext" then
        EnsureDB()
    elseif event == "PLAYER_LOGIN" then
        EnsureDB()
    end
end)

function ns.ResetLayout()
    EnsureDB()
    NobleNextDB.ui.window = DefaultWindow()
    if ns._shell and ns._shell.frame then
        local win = NobleNextDB.ui.window
        ns._shell.frame:ClearAllPoints()
        ns._shell.frame:SetSize(win.width, win.height)
        ns._shell.frame:SetPoint(win.point, UIParent, win.relativePoint, win.x, win.y)
    end
    ns.Print("Размер окна сброшен (/nn resetlayout).")
end

function ns.SetAllowShrink(enabled)
    ALLOW_SHRINK = enabled and true or false
    if enabled then
        MIN_W, MIN_H = 820, 500
        DEFAULT_W, DEFAULT_H = 960, 620
    else
        MIN_W, MIN_H = 960, 620
        DEFAULT_W, DEFAULT_H = 960, 620
    end
    if shell and shell.SetResizeLimits then
        shell:SetResizeLimits(MIN_W, MIN_H, MAX_W, MAX_H, ALLOW_SHRINK)
    end
end

-- ---------------------------------------------------------------------------
-- Module registry (stable id + legacy title keys)
-- ---------------------------------------------------------------------------
ns.modules = {} -- keyed by stable id
ns.modulesByTitle = {} -- legacy title -> id

local MODULE_DEFAULTS = {
    ["RP Фазы"] = { id = "phase", order = 100, group = "world", groupOrder = 10, groupLabel = "Мир", icon = "Interface/Icons/inv_misc_map02", slash = "/nnphases" },
    ["POI"] = { title = "Точки интереса", id = "poi", order = 110, group = "world", groupOrder = 10, groupLabel = "Мир", icon = "Interface/Icons/inv_misc_map_01", slash = "/nnpoi" },
    ["Tele"] = { title = "Телепорты", id = "tele", order = 120, group = "world", groupOrder = 10, groupLabel = "Мир", icon = "Interface/Icons/spell_arcane_teleportstormwind", slash = "/nntele" },
    ["Gob Mover"] = { title = "Объекты", id = "gobmover", order = 200, group = "objects", groupOrder = 20, groupLabel = "Объекты", icon = "Interface/Icons/garrison_building_workshop", slash = "/nngobmover" },
    ["GobGroup"] = { title = "Группы объектов", id = "gobgroup", order = 210, group = "objects", groupOrder = 20, groupLabel = "Объекты", icon = "Interface/Icons/inv_misc_map02", slash = "/nngobgroup" },
    ["Custom NPC"] = { title = "Шаблоны NPC", id = "customnpc", order = 220, group = "objects", groupOrder = 20, groupLabel = "Объекты", icon = "Interface/Icons/inv_misc_head_human_01", slash = "/nncustomnpc" },
    ["NPC"] = { title = "Существа", id = "npc", order = 300, group = "creatures", groupOrder = 30, groupLabel = "Существа", icon = "Interface/Icons/inv_misc_head_dragon_01", slash = "/nnnpc" },
    ["Армия"] = { id = "army", order = 310, group = "creatures", groupOrder = 30, groupLabel = "Существа", icon = "Interface/Icons/ability_hunter_beasttraining", slash = "/nnarmy" },
    ["Спутник"] = { id = "pet", order = 320, group = "creatures", groupOrder = 30, groupLabel = "Существа", icon = "Interface/Icons/ability_hunter_beastcall", slash = "/nnpet" },
    ["Вейпоинты"] = { title = "Маршруты", id = "waypoints", order = 330, group = "creatures", groupOrder = 30, groupLabel = "Существа", icon = "Interface/Icons/ability_hunter_pathfinding", slash = "/nnwaypoints" },
    ["Бой"] = { id = "battle", order = 340, group = "creatures", groupOrder = 30, groupLabel = "Существа", icon = "Interface/Icons/ability_warrior_challange", slash = "/nnbattle" },
    ["Мастер"] = { id = "master", order = 400, group = "director", groupOrder = 40, groupLabel = "Режиссёр", icon = "Interface/Icons/inv_misc_book_09", slash = "/nnmaster" },
    ["Команды"] = { id = "commands", order = 410, group = "director", groupOrder = 40, groupLabel = "Режиссёр", icon = "Interface/Icons/inv_misc_book_11", slash = "/nn commands" },
    ["Трансмог"] = { id = "transmog", order = 500, group = "client", groupOrder = 50, groupLabel = "Клиент", icon = "Interface/Icons/inv_chest_cloth_30", slash = "/nntransmogsync" },
    -- Ids keep the values derived from the title before these entries existed.
    ["Бой 3d6"] = { id = "Бой_3d6", order = 510, group = "client", groupOrder = 50, groupLabel = "Клиент", icon = "Interface/Icons/INV_Misc_Dice_01" },
    ["Предметы RP"] = { id = "Предметы_rp", order = 520, group = "client", groupOrder = 50, groupLabel = "Клиент", icon = "Interface/Icons/INV_MISC_RUNE_01" },
}

local function ResolveModuleId(nameOrId)
    if not nameOrId then return nil end
    if ns.modules[nameOrId] then return nameOrId end
    return ns.modulesByTitle[nameOrId]
end

--- RegisterModule(title, init, tooltip) — legacy
--- RegisterModule({ id, title, init, ... }) — new
function ns.RegisterModule(nameOrSpec, initFunc, tooltip, requiredLevel, owner)
    local spec
    if type(nameOrSpec) == "table" then
        spec = nameOrSpec
    else
        local defaults = MODULE_DEFAULTS[nameOrSpec] or {}
        spec = {
            id = defaults.id or tostring(nameOrSpec):gsub("%s+", "_"):lower(),
            title = defaults.title or nameOrSpec,
            init = initFunc,
            tooltip = tooltip or nameOrSpec,
            order = defaults.order or 500,
            group = defaults.group or "other",
            groupOrder = defaults.groupOrder or 90,
            groupLabel = defaults.groupLabel,
            icon = defaults.icon,
            slash = defaults.slash,
        }
    end

    local id = spec.id
    if not id or not spec.init then
        ns.PrintError("RegisterModule: нужен id и init")
        return
    end

    local module = {
        id = id,
        title = spec.title or id,
        init = spec.init,
        tooltip = spec.tooltip or spec.title or id,
        order = spec.order or 500,
        group = spec.group or "other",
        groupOrder = spec.groupOrder or 90,
        groupLabel = spec.groupLabel,
        icon = spec.icon,
        slash = spec.slash,
        OnContentSizeChanged = spec.OnContentSizeChanged,
        open = spec.open,
        requiredLevel = math.max(tonumber(requiredLevel) or 0, tonumber(spec.requiredLevel) or 0),
        owner = owner or "NobleNext",
    }
    local previous = ns.modules[id]
    if previous then
        for key, value in pairs(module) do
            if previous[key] ~= value then
                ns.PrintError("RegisterModule: модуль уже зарегистрирован владельцем " .. previous.owner .. ": " .. id)
                return nil
            end
        end
        for key, value in pairs(previous) do
            if key ~= "frame" and module[key] ~= value then
                ns.PrintError("RegisterModule: изменение существующего модуля запрещено: " .. id)
                return nil
            end
        end
        return previous
    end
    if ns.modulesByTitle[module.title] and ns.modulesByTitle[module.title] ~= id then
        ns.PrintError("RegisterModule: заголовок уже используется: " .. module.title)
        return nil
    end
    ns.modules[id] = module
    ns.modulesByTitle[spec.title or id] = id
    -- Keep legacy module/slash callers working after presentation labels change.
    if type(nameOrSpec) == "string" then ns.modulesByTitle[nameOrSpec] = id end

    if ns._sidebar and not (ns.Extensions and ns.Extensions.IsLoading and ns.Extensions.IsLoading()) then
        ns._RebuildSidebar()
    end
    if ns.Emit and not (ns.Extensions and ns.Extensions.IsLoading and ns.Extensions.IsLoading()) then
        ns.Emit("QUICK_ACTIONS_CHANGED")
    end
    return module
end

-- ---------------------------------------------------------------------------
-- Shell (NobleNextLib Window + Navigation sidebar)
-- ---------------------------------------------------------------------------
local shell
local sidebar
local contentFrame
local currentModuleId
local menuHint
local popoutWindows = {}

local function DockModuleInternal(id)
    local mod = id and ns.modules[id]
    local pop = id and popoutWindows[id]
    if pop then
        pop:Hide()
    end
    if mod and mod.frame and contentFrame then
        if mod.frame.SetParent then
            mod.frame:SetParent(contentFrame)
        end
        mod.frame:ClearAllPoints()
        mod.frame:SetAllPoints(contentFrame)
    end
end

function ns.DockModule(nameOrId)
    local id = ResolveModuleId(nameOrId) or nameOrId
    if not id then return false end
    if id == "gobmover" and NobleNextDB and NobleNextDB.ui then
        NobleNextDB.ui.gobFloating = false
    end
    if id == "gobmover" and _G.NobleNextGobMover and _G.NobleNextGobMover.CloseMiniSuite then
        _G.NobleNextGobMover.CloseMiniSuite()
    end
    DockModuleInternal(id)
    return ns.ShowModule(id)
end

function ns.PopoutModule(nameOrId)
    local id = ResolveModuleId(nameOrId) or currentModuleId
    local module = id and ns.modules[id]
    if not module then
        ns.PrintError("Модуль для мини-окна не выбран.")
        return false
    end
    if not ns.Access.Allows(module.requiredLevel or 0) then
        ns.PrintError("Сервер не подтвердил доступ к этому модулю.")
        return false
    end

    if id == "gobmover" and _G.NobleNextGobMover and _G.NobleNextGobMover.OpenMiniSuite then
        if shell and shell:IsShown() then
            shell:Hide()
        end
        _G.NobleNextGobMover.OpenMiniSuite()
        return true
    end

    if not NNL.Window or not NNL.Window.CreateMini then
        return false
    end

    local pop = popoutWindows[id]
    if not pop then
        pop = NNL.Window.CreateMini({
            name = "NobleNextPopout_" .. tostring(id),
            title = module.title or id,
            icon = module.icon,
            width = 640,
            height = 480,
            strata = "HIGH",
            closeOnEscape = false,
            headerButtonText = "В окно",
            headerButtonWidth = 58,
            headerButtonTooltip = "Вернуть этот раздел в общее окно NobleNext",
            onHeaderButton = function()
                ns.DockModule(id)
            end,
            onClose = function()
                if contentFrame and module.frame then
                    if module.frame.SetParent then
                        module.frame:SetParent(contentFrame)
                    end
                    module.frame:ClearAllPoints()
                    module.frame:SetAllPoints(contentFrame)
                    module.frame:Hide()
                end
            end,
        })
        popoutWindows[id] = pop
    end

    local host = pop:GetContent()
    if not module.frame then
        SafeCall("Init module " .. id, function()
            module.frame = module.init(host)
        end)
    end
    if module.frame then
        if module.frame.SetParent then
            module.frame:SetParent(host)
        end
        module.frame:ClearAllPoints()
        module.frame:SetAllPoints(host)
        module.frame:Show()
    end

    if shell and currentModuleId == id then
        shell:Hide()
    end
    pop:Show()
    local w, h = host:GetWidth(), host:GetHeight()
    local bp = NNL.Layout.GetBreakpoint(w)
    if module.OnContentSizeChanged then
        SafeCall("OnContentSizeChanged " .. id, module.OnContentSizeChanged, module, w, h, bp)
    elseif module.frame and module.frame.OnContentSizeChanged then
        SafeCall("frame.OnContentSizeChanged " .. id, module.frame.OnContentSizeChanged, module.frame, w, h, bp)
    end
    return true
end

local function PersistWindow()
    if not shell or not shell.frame then return end
    EnsureDB()
    local f = shell.frame
    -- Normalize to TOPLEFT/UIParent so clamp/drag never restore a bad relativeTo.
    local left = f:GetLeft()
    local top = f:GetTop()
    local parent = UIParent
    if left and top and parent then
        local pLeft, pTop = parent:GetLeft() or 0, parent:GetTop() or 0
        local x = left - pLeft
        local y = top - pTop
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        NobleNextDB.ui.window = ValidateWindow({
            width = f:GetWidth(),
            height = f:GetHeight(),
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            x = x,
            y = y,
        })
        return
    end
    local point, _, relativePoint, x, y = f:GetPoint(1)
    NobleNextDB.ui.window = ValidateWindow({
        width = f:GetWidth(),
        height = f:GetHeight(),
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = x or 0,
        y = y or 0,
    })
end

local function NotifyContentResize()
    if not contentFrame then return end
    local w, h = contentFrame:GetWidth(), contentFrame:GetHeight()
    local bp = NNL.Layout.GetBreakpoint(w)
    for id, mod in pairs(ns.modules) do
        if mod.frame and mod.frame:IsShown() then
            if mod.OnContentSizeChanged then
                SafeCall("OnContentSizeChanged " .. id, mod.OnContentSizeChanged, mod, w, h, bp)
            elseif mod.frame.OnContentSizeChanged then
                SafeCall("frame.OnContentSizeChanged " .. id, mod.frame.OnContentSizeChanged, mod.frame, w, h, bp)
            end
        end
    end
end

local function BuildShell()
    EnsureDB()
    local win = NobleNextDB.ui.window

    shell = NNL.Window.Create({
        name = "NobleNextFrame",
        title = "NobleNext",
        width = win.width,
        height = win.height,
        sidebarWidth = SIDEBAR_W,
        strata = "HIGH",
        closeOnEscape = true,
        resizable = true,
        allowShrink = ALLOW_SHRINK,
        minWidth = MIN_W,
        minHeight = MIN_H,
        maxWidth = MAX_W,
        maxHeight = MAX_H,
        defaultWidth = DEFAULT_W,
        defaultHeight = DEFAULT_H,
        onSizeChanged = function()
            NotifyContentResize()
        end,
        onResizeStop = function()
            PersistWindow()
            NotifyContentResize()
        end,
        popoutText = "Мини-окно",
        onPopout = function()
            if currentModuleId then
                ns.PopoutModule(currentModuleId)
            elseif ns.Access.Allows(2) and _G.NobleNextGobMover and _G.NobleNextGobMover.OpenMiniSuite then
                shell:Hide()
                _G.NobleNextGobMover.OpenMiniSuite()
            end
        end,
    })

    shell.frame:ClearAllPoints()
    shell.frame:SetPoint(win.point, UIParent, win.relativePoint, win.x, win.y)
    -- PanelDragBar does not fire frame OnDragStop; Window.lua calls frame._onDragStop.
    shell.frame._onDragStop = PersistWindow
    shell.frame:HookScript("OnHide", PersistWindow)

    contentFrame = shell:GetContent()
    menuHint = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    menuHint:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 20, -24)
    menuHint:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -20, -24)
    menuHint:SetJustifyH("LEFT")
    menuHint:SetText("Выберите раздел в меню слева.")
    ns._shell = shell
    ns._contentFrame = contentFrame

    sidebar = NNL.Navigation.CreateSidebar(shell:GetSidebar(), {
        width = SIDEBAR_W,
        onSelect = function(id)
            ns.ShowModule(id)
        end,
        onSecondarySelect = function(id)
            ns.PopoutModule(id)
        end,
    })
    NNL.Layout.Fill(sidebar, shell:GetSidebar(), { left = 0, right = 0, top = 0, bottom = 0 })
    ns._sidebar = sidebar
end

function ns._RebuildSidebar()
    if not sidebar then return end
    local items = {}
    for _, mod in pairs(ns.modules) do
        if ns.Access.Allows(mod.requiredLevel or 0) then
        table.insert(items, {
            id = mod.id,
            title = mod.title,
            tooltip = mod.tooltip,
            icon = mod.icon,
            slash = mod.slash,
            order = mod.order,
            group = mod.group,
            groupOrder = mod.groupOrder,
            groupLabel = mod.groupLabel,
        })
        end
    end
    table.sort(items, function(a, b)
        if a.groupOrder ~= b.groupOrder then return a.groupOrder < b.groupOrder end
        if a.order ~= b.order then return a.order < b.order end
        return tostring(a.id) < tostring(b.id)
    end)
    sidebar:SetItems(items)
    if currentModuleId then
        sidebar:Select(currentModuleId, true)
    end
end

function ns.GetContentFrame()
    return contentFrame
end

function ns.ShowModule(name)
    local id = ResolveModuleId(name)
    local module = id and ns.modules[id]
    if not module then
        ns.PrintError("Модуль не найден: " .. tostring(name))
        return
    end
    if not ns.Access.Allows(module.requiredLevel or 0) then
        ns.PrintError("Сервер не подтвердил доступ к этому модулю.")
        return false
    end

    -- An external module owns its real window and selection.
    if module.open then
        local ok, result = SafeCall("Open module " .. id, module.open)
        if ok and result ~= false then
            if shell then shell:Hide() end
            return true
        end
        return false
    end

    if id == "gobmover" and NobleNextDB and NobleNextDB.ui and NobleNextDB.ui.gobFloating
        and _G.NobleNextGobMover and _G.NobleNextGobMover.OpenMiniSuite
        and not (shell and shell:IsShown()) then
        _G.NobleNextGobMover.OpenMiniSuite()
        return true
    end

    if not shell then
        SafeCall("BuildShell", BuildShell)
        ns._RebuildSidebar()
    end
    if not shell or not contentFrame then
        ns.PrintError("Не удалось создать окно NobleNext.")
        return
    end

    if popoutWindows[id] and popoutWindows[id]:IsShown() then
        DockModuleInternal(id)
    end

    if not module.frame then
        SafeCall("Init module " .. id, function()
            module.frame = module.init(contentFrame)
            if module.frame then
                module.frame:ClearAllPoints()
                module.frame:SetAllPoints(contentFrame)
            end
        end)
    elseif module.frame then
        if module.frame.SetParent then
            module.frame:SetParent(contentFrame)
        end
        module.frame:ClearAllPoints()
        module.frame:SetAllPoints(contentFrame)
    end

    for modId, mod in pairs(ns.modules) do
        if mod.frame then
            mod.frame:SetShown(modId == id)
        end
    end

    currentModuleId = id
    if menuHint then menuHint:Hide() end
    EnsureDB()
    NobleNextDB.ui.lastModuleId = id
    if sidebar then
        sidebar:Select(id, true)
    end
    shell:Show()
    NotifyContentResize()
end

function ns.ToggleMainFrame()
    if ns.ApplyAccessVisibility then ns.ApplyAccessVisibility() end
    if not shell then
        SafeCall("BuildShell", BuildShell)
        ns._RebuildSidebar()
    end
    if not shell then
        ns.PrintError("Не удалось создать окно NobleNext.")
        return
    end
    if shell:IsShown() then
        shell:Hide()
        return
    end
    if not currentModuleId then
        EnsureDB()
        local last = NobleNextDB.ui.lastModuleId
        -- The launcher restores only embedded pages. Opening an external window
        -- is a separate, explicit action; external modules must not hijack /nn/minimap.
        if last and ns.modules[last] and not ns.modules[last].open
            and ns.Access.Allows(ns.modules[last].requiredLevel or 0) then
            ns.ShowModule(last)
            return
        end
        local first
        for id, mod in pairs(ns.modules) do
            if not mod.open and ns.Access.Allows(mod.requiredLevel or 0)
                and (not first or (mod.order or 500) < (ns.modules[first].order or 500)) then
                first = id
            end
        end
        if first then
            ns.ShowModule(first)
            return
        end
        if menuHint then menuHint:Show() end
    end
    shell:Show()
end

function ns.ApplyAccessVisibility()
    for id, mod in pairs(ns.modules) do
        if not ns.Access.Allows(mod.requiredLevel or 0) then
            if mod.frame then mod.frame:Hide() end
            if popoutWindows[id] then popoutWindows[id]:Hide() end
            if id == "gobmover" and _G.NobleNextGobMover and _G.NobleNextGobMover.CloseMiniSuite then
                _G.NobleNextGobMover.CloseMiniSuite()
            end
            if currentModuleId == id then
                currentModuleId=nil
                if shell then shell:Hide() end
            end
        end
    end
    ns._RebuildSidebar()
end

-- Build shell/menu after modules register (same tick end).
C_Timer.After(0, function()
    SafeCall("BuildShell", BuildShell)
    SafeCall("RebuildSidebar", ns._RebuildSidebar)
end)

-- ---------------------------------------------------------------------------
-- AIO Bridge
-- ---------------------------------------------------------------------------
function ns.GetAIO()
    return _G.AIO
end

function ns.IsAIOReady()
    local AIO = ns.GetAIO()
    return AIO and AIO.Handle
end

function ns.AIOHandle(handlerName, methodName, ...)
    if not ns.Access.Allows(1) then
        ns.PrintError("Сервер не подтвердил доступ к служебным действиям.")
        return false
    end
    if type(handlerName) ~= "string" or handlerName == "" then
        ns.PrintError("AIOHandle: пустое имя handler.")
        return false
    end
    if type(methodName) ~= "string" or methodName == "" then
        ns.PrintError("AIOHandle: пустое имя method.")
        return false
    end
    local AIO = ns.GetAIO()
    if not AIO or not AIO.Handle then
        ns.PrintError("AIO не загружен. Убедитесь, что аддон AIO_Client установлен и включен.")
        return false
    end
    ns.PrintDebug(string.format("AIO -> %s.%s", handlerName, methodName))
    local ok, err = pcall(AIO.Handle, handlerName, methodName, ...)
    if not ok then
        ns.PrintError(string.format("AIO %s.%s: %s", handlerName, methodName, tostring(err)))
        return false
    end
    return true
end

local function normalizeGmCommand(cmd)
    if cmd == nil then return nil end
    cmd = tostring(cmd):match("^%s*(.-)%s*$")
    if cmd == "" then return nil end
    cmd = cmd:gsub("^[%./]+", "")
    if cmd == "" then return nil end
    return "." .. cmd
end

function ns.SendGmWhisper(cmd)
    if not ns.Access.Allows(1) then
        ns.PrintError("Сервер не подтвердил доступ к служебным командам.")
        return false
    end
    local text = normalizeGmCommand(cmd)
    if not text then return false end
    if not SendChatMessage or not UnitName then
        ns.PrintError("SendChatMessage недоступен.")
        return false
    end
    local target = UnitName("player")
    if not target or target == "" then
        ns.PrintError("Не удалось определить имя персонажа для whisper.")
        return false
    end
    ns.PrintDebug("GM whisper -> " .. text)
    SendChatMessage(text, "WHISPER", nil, target)
    return true
end

function ns.RunGmCommand(cmd)
    return ns.SendGmWhisper(cmd)
end

-- ---------------------------------------------------------------------------
-- Slash command
-- ---------------------------------------------------------------------------
function ns.PrintStatus()
    local access=ns.Access.GetStatus()
    ns.Print("Комплект "..tostring(NNL.VERSION).."; доступ: "..access.state
        .."; GM-уровень: "..tostring(access.level or "неизвестен").."; источник: "..tostring(access.source or "—")
        .."; причина: "..tostring(access.reason).."; осталось: "..math.ceil(access.expiresIn).." сек.")
    for _,package in ipairs(ns.Extensions and ns.Extensions.GetStatus() or {}) do
        ns.Print(package.name..": "..package.state..(package.reason and (" ("..package.reason..")") or ""))
    end
    ns.Print("/nn status retry — повторить проверку доступа и загрузку расширений.")
    local launcher = ns.MinimapLauncher
    local button = launcher and launcher.button
    ns.Print("Иконка: " .. (not button and "не создана" or (button:IsShown() and "показана" or "скрыта"))
        .. "; восстановление: /nn minimap reset.")
end

local function NobleNextSlashHandler(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    rest = rest or ""
    if cmd == "" or cmd == "menu" then
        if ns.Access.GetLevel()==nil then
            ns.Print("Служебные разделы ожидают подтверждения уровня. /nn status — состояние проверки.")
        end
        ns.ToggleMainFrame()
    elseif cmd == "minimap" then
        local launcher = ns.MinimapLauncher
        if not launcher then ns.PrintError("Иконка ещё не загружена."); return end
        local action = rest:lower()
        if action == "reset" then
            if launcher:ResetPosition() then
                ns.Print("Иконка показана; положение сброшено под миникарту.")
            else
                ns.PrintError("Не удалось восстановить иконку. Завершите бой и повторите /nn minimap reset.")
            end
        elseif action == "lock" then launcher:SetEditMode(false)
        elseif action == "edit" then launcher:OpenSettings()
        else ns.Print("Иконка: /nn minimap reset, /nn minimap lock, /nn minimap edit.") end
    elseif cmd == "status" then
        if rest:lower()=="retry" then
            if not ns.Access.Request() then
                ns.Print("Проверка уже выполняется либо ещё действует интервал повторного запроса (20 сек.).")
            end
            if ns.Extensions then ns.Extensions.LoadAllowed() end
        end
        ns.PrintStatus()
    elseif cmd == "commands" or cmd == "cmds" then
        if not ns.Access.Allows(2) then
            ns.PrintError("Справочник мастера требует GM-уровень 2 или выше.")
        elseif ns.ShowCommandsBrowser then
            ns.ShowCommandsBrowser(rest)
        else
            ns.PrintError("Браузер команд не загружен (GM/Commands/Browser.lua).")
        end
    elseif cmd == "debug" then
        EnsureDB()
        NobleNextDB.debug = not NobleNextDB.debug
        ns.Print("debug mode: " .. (NobleNextDB.debug and "ON" or "OFF"))
    elseif cmd == "gobgroup" then
        ns.ShowModule("gobgroup")
    elseif cmd == "resetlayout" then
        ns.ResetLayout()
    elseif cmd == "help" then
        ns.Print("Команды: /nn, /nn status, /nn resetlayout, /nntransmogsync. Служебные разделы открываются по уровню, подтверждённому сервером.")
        ns.Print("Иконка: /nn minimap reset | lock | edit. ПКМ — быстрые действия; Shift+ЛКМ — все действия и настройки.")
        if ns.Access.Allows(1) then ns.Print("ДМ: /nnmaster, /nnarmy, /nnpet, /nnbattle, /nnphases") end
        if ns.Access.Allows(2) then ns.Print("ГМ: /nn commands, /nngobmover, /nngobgroup, /nnnpc, /nnpoi, /nntele, /nnwaypoints") end
        ns.Print("Отладка AIO: /nn debug")
    end
end

local function RegisterSlashCommands()
    if ns.RegisterSlashCommand then
        ns.RegisterSlashCommand("NOBLENEXT", NobleNextSlashHandler, { "nn", "noblenext" })
    elseif RegisterNewSlashCommand then
        RegisterNewSlashCommand(NobleNextSlashHandler, "nn", "noblenext")
    else
        SLASH_NOBLENEXT1 = "/nn"
        SLASH_NOBLENEXT2 = "/noblenext"
        SlashCmdList["NOBLENEXT"] = NobleNextSlashHandler
    end
end

C_Timer.After(0, RegisterSlashCommands)

ns.Print("Core loaded (NobleNextLib " .. tostring(NNL.VERSION) .. "). /nn для меню.")
