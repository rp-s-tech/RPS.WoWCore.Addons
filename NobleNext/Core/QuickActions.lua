-- Public quick navigation. Opening a menu never executes a game command.
local ns = LibStub("NobleNextLib-1.0").Runtime
local actions, contextMenu = {}, nil
local fallbackIcon = "Interface\\Icons\\INV_Misc_QuestionMark"
local defaultVisible = {
    ["module:transmog"]=true, character=true, profile=true, barbershop=true,
    ["module:phase"]=true, ["module:master"]=true, ["module:gobmover"]=true,
}

local function finiteNumber(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return fallback end
    return value
end

function ns.CloseQuickContextMenu()
    if contextMenu and Menu and Menu.GetManager then
        Menu.GetManager():CloseMenu(contextMenu)
    end
    contextMenu = nil
end

-- Extensions call this through their owner/minimum-level wrapper.
function ns.RegisterQuickAction(spec, minimum, owner)
    if type(spec) ~= "table" or type(spec.id) ~= "string" or spec.id == ""
        or spec.id:find("^module:") or type(spec.title) ~= "string"
        or type(spec.onClick) ~= "function"
        or (spec.isAvailable ~= nil and type(spec.isAvailable) ~= "function") then
        ns.PrintError("Быстрое действие: нужны уникальный id, название и обработчик.")
        return false
    end
    local action = {
        id=spec.id, title=spec.title, icon=spec.icon or fallbackIcon,
        order=finiteNumber(spec.order, 500), owner=owner or "NobleNext",
        requiredLevel=math.max(0, finiteNumber(minimum, 0), finiteNumber(spec.requiredLevel, 0)),
        onClick=spec.onClick, isAvailable=spec.isAvailable,
        allowInCombat=spec.allowInCombat == true,
    }
    local previous = actions[action.id]
    if previous then
        for key, value in pairs(action) do
            if previous[key] ~= value then
                ns.PrintError("Быстрое действие уже зарегистрировано: " .. action.id)
                return false
            end
        end
        for key, value in pairs(previous) do
            if action[key] ~= value then
                ns.PrintError("Быстрое действие уже зарегистрировано: " .. action.id)
                return false
            end
        end
        return true
    end
    actions[action.id] = action
    if ns.Emit then ns.Emit("QUICK_ACTIONS_CHANGED") end
    return true
end

local function resolve(id)
    if type(id) ~= "string" then return nil end
    local moduleId = id:match("^module:(.+)$")
    if moduleId then
        local module = ns.modules and ns.modules[moduleId]
        if not module then return nil end
        return {
            id=id, title=moduleId == "transmog" and "Трансмогрификация" or module.title,
            icon=module.icon or fallbackIcon,
            order=moduleId == "transmog" and 10 or module.order or 500, requiredLevel=module.requiredLevel or 0,
            allowInCombat=true, onClick=function() return ns.ShowModule(moduleId) end,
        }
    end
    return actions[id]
end

local function available(action)
    if not action or not ns.Access.Allows(action.requiredLevel) then return false end
    if action.isAvailable then
        local ok, result = pcall(action.isAvailable)
        return ok and result == true
    end
    return true
end

local function combatReason(action)
    if not action.allowInCombat and InCombatLockdown and InCombatLockdown() then
        return "Действие доступно после выхода из боя."
    end
end

-- Reads must not initialize SavedVariables while addon files are loading.
local function savedSelection()
    local db = type(NobleNextDB) == "table" and NobleNextDB
    local ui = db and type(db.ui) == "table" and db.ui
    local selection = ui and type(ui.quickActions) == "table" and ui.quickActions
    return selection and type(selection.visible) == "table" and selection.visible
end

function ns.IsQuickActionVisible(id)
    if not resolve(id) then return false end
    local selection = savedSelection()
    if selection and type(selection[id]) == "boolean" then return selection[id] end
    return defaultVisible[id] == true
end

function ns.RefreshQuickActionPresentation()
    if ns.Emit then ns.Emit("QUICK_ACTIONS_CHANGED") end
end

function ns.SetQuickActionVisible(id, visible)
    if type(visible) ~= "boolean" or not available(resolve(id)) then return false end
    if type(NobleNextDB) ~= "table" then return false end
    if ns.IsQuickActionVisible(id) == visible then return true end
    NobleNextDB.ui = type(NobleNextDB.ui) == "table" and NobleNextDB.ui or {}
    local ui = NobleNextDB.ui
    ui.quickActions = type(ui.quickActions) == "table" and ui.quickActions or {}
    ui.quickActions.version = 1
    ui.quickActions.visible = type(ui.quickActions.visible) == "table" and ui.quickActions.visible or {}
    ui.quickActions.visible[id] = visible
    if ns.LauncherEditMode then ns.LauncherEditMode:NotifyChanged() end
    ns.RefreshQuickActionPresentation()
    return true
end

-- Settings and the full native menu use this list, independent of flyout selection.
function ns.GetAvailableQuickActions()
    local result = {}
    local function append(action)
        if available(action) then
            local reason = combatReason(action)
            result[#result+1] = {id=action.id, title=action.title, icon=action.icon,
                requiredLevel=action.requiredLevel, order=action.order,
                enabled=reason == nil, disabledReason=reason,
                visible=ns.IsQuickActionVisible(action.id)}
        end
    end
    for _, action in pairs(actions) do append(action) end
    for id in pairs(ns.modules or {}) do append(resolve("module:" .. id)) end
    table.sort(result, function(a, b)
        if a.requiredLevel ~= b.requiredLevel then return a.requiredLevel < b.requiredLevel end
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    return result
end

function ns.GetVisibleQuickActions()
    local result = {}
    for _, action in ipairs(ns.GetAvailableQuickActions()) do
        if action.visible then result[#result+1] = action end
    end
    return result
end

function ns.ExecuteQuickAction(id)
    local action = resolve(id)
    local reason
    if not available(action) then
        reason = "Действие недоступно: проверьте права или загрузку нужного аддона."
    else
        reason = combatReason(action)
    end
    if reason then ns.PrintError(reason); return false, reason end
    local ok, result, detail = pcall(action.onClick)
    if not ok or result == false then
        reason = ok and ns.Util.SafeString(detail, "Действие не выполнено.")
            or "Не удалось открыть действие. Проверьте состояние аддона."
        if reason == "" then reason = "Действие не выполнено." end
        ns.PrintError(reason)
        return false, reason
    end
    return true
end

local function trpReady()
    local api = TRP3_API
    return type(api) == "table" and type(api.register) == "table"
        and type(api.register.openPageByUnitID) == "function"
        and type(api.navigation) == "table" and type(api.navigation.openMainFrame) == "function"
        and type(api.globals) == "table" and type(api.globals.player_id) == "string"
end

ns.RegisterQuickAction({id="character", title="Характеристики", order=20, allowInCombat=true,
    icon="Interface\\Icons\\Ability_Warrior_OffensiveStance",
    isAvailable=function() return type(ToggleCharacter) == "function" end,
    onClick=function() ToggleCharacter("PaperDollFrame") end})
ns.RegisterQuickAction({id="profile", title="Описание персонажа", order=30, allowInCombat=true,
    icon="Interface\\Icons\\INV_Misc_Book_09", isAvailable=trpReady,
    onClick=function()
        TRP3_API.register.openPageByUnitID(TRP3_API.globals.player_id)
        TRP3_API.navigation.openMainFrame()
    end})
ns.RegisterQuickAction({id="barbershop", title="Парикмахерская", order=40,
    icon="Interface\\Icons\\INV_Misc_Comb_02",
    isAvailable=function() return type(SendChatMessage) == "function" and type(UnitName) == "function" end,
    onClick=function()
        local name = UnitName("player")
        if (issecretvalue and issecretvalue(name)) or type(name) ~= "string" or name == "" then
            return false, "Не удалось определить имя персонажа."
        end
        -- A fixed player command, not a lower-privilege generic GM transport.
        SendChatMessage(".barbershop", "WHISPER", nil, name)
    end})

function ns.OpenQuickContextMenu(anchor)
    local launcher = ns.MinimapLauncher
    if not MenuUtil or not MenuUtil.CreateContextMenu then
        ns.PrintError("Быстрое меню недоступно. Откройте главное окно командой /nn.")
        return false
    end
    if launcher then launcher:CloseFlyout() end
    ns.CloseQuickContextMenu()
    contextMenu = MenuUtil.CreateContextMenu(anchor, function(_, root)
        -- Native menu frames are pooled. Never keep a released proxy that could
        -- later refer to another addon's menu; submenu releases share this hook.
        root:AddMenuReleasedCallback(function(menu)
            if contextMenu == menu then contextMenu = nil end
        end)
        root:CreateTitle("Меню")
        local section = 0
        for _, action in ipairs(ns.GetAvailableQuickActions()) do
            local group = action.requiredLevel >= 2 and 2 or action.requiredLevel >= 1 and 1 or 0
            if group ~= section then
                root:CreateDivider()
                root:CreateTitle(group == 1 and "Мастер (ДМ)" or "Инструменты мира (ГМ)")
                section = group
            end
            local id = action.id
            local item = root:CreateButton(action.title, function() ns.ExecuteQuickAction(id) end)
            item:SetEnabled(action.enabled)
            if action.disabledReason then
                local reason = action.disabledReason
                item:SetTooltip(function(tooltip) tooltip:AddLine(reason) end)
            end
        end
        if not launcher then return end
        root:CreateDivider()
        root:CreateButton("Настройки быстрых действий", function() launcher:OpenSettings() end)
    end)
    return true
end

function NobleNext_OnAddonCompartmentClick(_, buttonName)
    if buttonName == "RightButton" then
        if ns.MinimapLauncher then ns.MinimapLauncher:ToggleFlyout()
        else ns.OpenQuickContextMenu(AddonCompartmentFrame or UIParent) end
    elseif IsShiftKeyDown and IsShiftKeyDown() then
        ns.OpenQuickContextMenu(AddonCompartmentFrame or UIParent)
    else
        ns.ToggleMainFrame()
    end
end

function NobleNext_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    GameTooltip:AddLine("NobleNext")
    GameTooltip:AddLine("ЛКМ — главное окно; ПКМ — быстрые действия", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Shift+ЛКМ — все действия и настройки", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function NobleNext_OnAddonCompartmentLeave() GameTooltip:Hide() end

if ns.Subscribe then
    ns.Subscribe("ACCESS_CHANGED", "NobleNextQuickContext", ns.CloseQuickContextMenu)
    ns.Subscribe("QUICK_ACTIONS_CHANGED", "NobleNextQuickContextRefresh", ns.CloseQuickContextMenu)
end
