-- Loaded through the NobleNextGM private extension namespace.
-- GM/GobGroup/Panel.lua — UI панели GobGroup

local _, ns = ...
local NNL = LibStub("NobleNextLib-1.0")

ns.GobGroupPanel = ns.GobGroupPanel or {}
local Panel = ns.GobGroupPanel
local Packets = ns.GobGroupPackets

local ADDON_PREFIX = Packets and Packets.PREFIX or "NN_GOBGROUP"

local Ui = {
    buttons = {},
    verbButtons = {},
    scanCandidates = {},
}

local ActiveGroup = nil
local CurrentObjectGuid = nil
local PendingCreate = nil
local PendingSelectionGuid = nil
local UpdateActionAvailability
local UpdateContextHeader

local GROUP_REQUIRED_VERBS = {
    add = true,
    remove = true,
    addnear = true,
    capture = true,
    recalc = true,
    sync = true,
    move = true,
    turn = true,
    relocate = true,
    dissolve = true,
    delete = true,
}

local ACTIVE_CONTEXT_VERBS = {
    scan = true,
    status = true,
    check = true,
    target = true,
}

local VERB_LABELS = {
    capabilities = "Доступность команд",
    info = "Инспектор",
    list = "Список групп",
    near = "Поиск групп рядом",
    status = "Состояние",
    check = "Проверка",
    create = "Создание",
    use = "Выбор группы",
    target = "Выбор главного объекта",
    add = "Добавление",
    remove = "Удаление из группы",
    scan = "Поиск рядом",
    addnear = "Добавление рядом",
    capture = "Сохранение позиции",
    recalc = "Пересчёт",
    sync = "Синхронизация",
    move = "Перемещение",
    turn = "Поворот",
    relocate = "Перенос",
    dissolve = "Роспуск группы",
    delete = "Удаление группы",
    cleanup = "Очистка метаданных",
    reload = "Перезагрузка кеша",
}

local function Trim(v)
    return tostring(v or ""):match("^%s*(.-)%s*$")
end

local function PositiveGuid(v)
    local guid = tonumber(Trim(v))
    return guid and guid > 0 and guid or nil
end

local function GroupDisplayName(group)
    if not group then
        return "-"
    end
    local name = Trim(group.name)
    return name ~= "" and name or "без имени"
end

local function SetStatus(text, level)
    if not Ui.statusText then
        return
    end
    local color = { 0.7, 0.9, 0.7 }
    if level == "error" then
        color = { 1, 0.4, 0.4 }
    elseif level == "warning" then
        color = { 1, 0.8, 0.3 }
    elseif level == "info" then
        color = { 0.7, 0.8, 1 }
    end
    Ui.statusText:SetTextColor(color[1], color[2], color[3], 1)
    Ui.statusText:SetText(text or "-")
end

local function TryGobMoverGuid()
    local mover = _G.NobleNextGobMover or _G.NobleNextGoMover
    if mover and type(mover.GetTarget) == "function" then
        local guid = mover.GetTarget()
        if tonumber(guid) and tonumber(guid) > 0 then
            return tonumber(guid)
        end
    end
    if mover and mover._nameLabel then
        local text = mover._nameLabel:GetText() or ""
        local guid = text:match("GUID:%s*(%d+)")
        if guid then
            return tonumber(guid)
        end
    end
    return nil
end

local function ResolveObjectGuid()
    local typed = tonumber(Trim(Ui.objectGuidBox and Ui.objectGuidBox:GetText()))
    if typed and typed > 0 then
        return typed
    end
    if CurrentObjectGuid and CurrentObjectGuid > 0 then
        return CurrentObjectGuid
    end
    local moverGuid = TryGobMoverGuid()
    if moverGuid then
        return moverGuid
    end
    if ns.LastSpawnedGoGuid and ns.LastSpawnedGoGuid > 0 then
        return ns.LastSpawnedGoGuid
    end
    return nil
end

local function ResolveGroupGuid()
    return ActiveGroup and ActiveGroup.root or nil
end

local function ResolveTypedGroupGuid()
    return PositiveGuid(Ui.groupGuidBox and Ui.groupGuidBox:GetText())
end

local function RequireActiveGroup(action)
    local root = ResolveGroupGuid()
    if root then
        return root
    end
    ns.PrintError(string.format(
        "Сначала сделайте группу активной%s.",
        action and (" для действия \"" .. action .. "\"") or ""
    ))
    SetStatus("Действие отменено: группа не выбрана.", "error")
    return nil
end

local function FormatBlueprintCmd(verb, argValues)
    local path = "gobject blueprint " .. verb
    local CD = ns.CommandDefinitions
    if CD and CD.Find and CD.Format then
        local def = CD.Find(path)
        if def then
            local cmd = CD.Format(def, argValues)
            if cmd and cmd ~= "" then
                return cmd
            end
        end
    end

    local parts = { ".gobject blueprint", verb }
    if type(argValues) == "table" then
        if #argValues > 0 then
            for i = 1, #argValues do
                if argValues[i] ~= nil and argValues[i] ~= "" then
                    parts[#parts + 1] = tostring(argValues[i])
                end
            end
        else
            for _, key in ipairs({ "name", "oldName", "newName", "filter" }) do
                local v = argValues[key]
                if v ~= nil and v ~= "" then
                    parts[#parts + 1] = tostring(v)
                end
            end
        end
    end
    return table.concat(parts, " ")
end

local function SendBlueprintCmd(verb, argValues, tag)
    -- Multi-argument handlers tokenize the key separately; a typed display name
    -- containing spaces could otherwise address a different template.
    if verb == "rename" or verb == "set-public" or verb:find("^member ") then
        local selectedKey = Trim(Ui.selectedBlueprint and Ui.selectedBlueprint.key)
        local keyIndex = (verb == "member add" or verb == "member remove") and 2 or 1
        local requestedKey = Trim(argValues and (argValues.oldName or argValues.name or argValues[keyIndex]))
        if selectedKey == "" or selectedKey:find("%s") or requestedKey ~= selectedKey then
            ns.PrintError("Сначала выберите шаблон в серверном списке, затем повторите действие.")
            SetStatus("Действие не отправлено: выберите шаблон в списке.", "warning")
            return false
        end
    end
    local cmd = FormatBlueprintCmd(verb, argValues)
    -- Always append our own flag: a name may itself end with the word "silent".
    -- The server removes exactly one trailing flag, preserving the user's name.
    cmd = cmd .. " silent"
    if ns.PrintDebug then
        ns.PrintDebug("GobBlueprint -> " .. cmd)
    end
    SetStatus("Отправка…", "info")
    if ns.EnqueueCommand then
        ns.EnqueueCommand(cmd, { tag = tag or ("gobblueprint:" .. verb) })
    elseif ns.RunGmCommand then
        ns.RunGmCommand(cmd)
    else
        ns.PrintError("Нет API отправки GM-команд.")
        return false
    end
    return true
end

local function FormatGroupCmd(verb, argValues)
    local path = "gobject group " .. verb
    local CD = ns.CommandDefinitions
    if CD and CD.Find and CD.Format then
        local def = CD.Find(path)
        if def then
            local cmd = CD.Format(def, argValues)
            if cmd and cmd ~= "" then
                return cmd
            end
        end
    end

    local parts = { ".gobject group", verb }
    if type(argValues) == "table" then
        if #argValues > 0 then
            for i = 1, #argValues do
                if argValues[i] ~= nil and argValues[i] ~= "" then
                    parts[#parts + 1] = tostring(argValues[i])
                end
            end
        else
            -- named map: preserve common order for fallback
            local order = {
                "objectGuid", "rootGuid", "groupGuid", "memberGuid", "guid",
                "radius", "name", "x", "y", "z", "orientation", "o", "mapId",
                "silent", "confirm", "fullForce",
            }
            local seen = {}
            for i = 1, #order do
                local key = order[i]
                local v = argValues[key]
                if v ~= nil and v ~= "" then
                    parts[#parts + 1] = tostring(v)
                    seen[key] = true
                end
            end
            for k, v in pairs(argValues) do
                if type(k) == "string" and not seen[k] and v ~= nil and v ~= "" then
                    parts[#parts + 1] = tostring(v)
                end
            end
        end
    end
    return table.concat(parts, " ")
end

local MAX_SCAN_RADIUS = 100
local MAX_NEAR_RADIUS = 1000

local function SendGroupCmd(verb, argValues, tag)
    local cmd = FormatGroupCmd(verb, argValues)
    if ns.PrintDebug then
        ns.PrintDebug("GobGroup -> " .. cmd)
    end
    SetStatus("Отправка: " .. cmd, "info")
    if ns.EnqueueCommand then
        -- Fire-and-forget: structured replies arrive via Packets.On(NN_GOBGROUP).
        ns.EnqueueCommand(cmd, { tag = tag or ("gobgroup:" .. verb) })
    elseif ns.RunGmCommand then
        ns.RunGmCommand(cmd)
    else
        ns.PrintError("Нет API отправки GM-команд.")
        return false
    end
    return true
end

UpdateContextHeader = function()
    if not Ui.contextGroupText then
        return
    end

    if ActiveGroup then
        local stateParts = {}
        if ActiveGroup.busy == nil then
            stateParts[#stateParts + 1] = "задача: -"
        elseif ActiveGroup.busy then
            stateParts[#stateParts + 1] = "|cffff8040занята|r"
        else
            stateParts[#stateParts + 1] = "|cff75d98bготова|r"
        end
        if ActiveGroup.dirty == nil then
            stateParts[#stateParts + 1] = "изменения: -"
        elseif ActiveGroup.dirty then
            stateParts[#stateParts + 1] = "|cffffd25eесть изменения|r"
        else
            stateParts[#stateParts + 1] = "сохранена"
        end
        Ui.contextGroupText:SetText(string.format(
            "|cff7fe39aАКТИВНАЯ ГРУППА|r  |cffffd76aroot %d|r  |  %s  |  Объектов: %s  |  Карта: %s  | Фаза: %s |  %s",
            ActiveGroup.root,
            GroupDisplayName(ActiveGroup),
            tostring(ActiveGroup.members or "-"),
            tostring(ActiveGroup.map or "-"),
            tostring(ActiveGroup.serverPhaseId or 0),
            table.concat(stateParts, ", ")
        ))
        if Ui.contextFrame and Ui.contextFrame.SetBackdrop then
            Ui.contextFrame:SetBackdropColor(0.06, 0.16, 0.09, 0.96)
            Ui.contextFrame:SetBackdropBorderColor(0.82, 0.66, 0.18, 0.95)
        end
    else
        Ui.contextGroupText:SetText("|cffff6b6bГРУППА НЕ ВЫБРАНА|r  |cff9a9a9a- сначала выберите группу|r")
        if Ui.contextFrame and Ui.contextFrame.SetBackdrop then
            Ui.contextFrame:SetBackdropColor(0.16, 0.07, 0.07, 0.96)
            Ui.contextFrame:SetBackdropBorderColor(0.42, 0.32, 0.32, 0.9)
        end
    end

    Ui.contextObjectText:SetText(string.format(
        "Текущий объект / GUID: |cffffffff%s|r",
        CurrentObjectGuid and tostring(CurrentObjectGuid) or "не выбран"
    ))

    if Ui.refreshBlueprintSource then
        Ui.refreshBlueprintSource()
    end
end

function Panel.SetActiveGroup(root, metadata)
    root = PositiveGuid(root)
    if not root then
        Panel.ClearActiveGroup()
        return false
    end

    metadata = type(metadata) == "table" and metadata or {}
    local previous = ActiveGroup and ActiveGroup.root == root and ActiveGroup or {}
    ActiveGroup = {
        root = root,
        name = metadata.name ~= nil and metadata.name or previous.name,
        members = metadata.members ~= nil and metadata.members
            or metadata.memberCount ~= nil and metadata.memberCount
            or previous.members,
        map = metadata.map ~= nil and metadata.map or previous.map,
        serverPhaseId = metadata.serverPhaseId ~= nil and metadata.serverPhaseId or previous.serverPhaseId,
        dirty = metadata.dirty,
        busy = metadata.busy,
    }
    if metadata.dirty == nil then ActiveGroup.dirty = previous.dirty end
    if metadata.busy == nil then ActiveGroup.busy = previous.busy end
    if Ui.groupGuidBox then
        Ui.groupGuidBox:SetText(tostring(root))
    end
    UpdateContextHeader()
    if UpdateActionAvailability then
        UpdateActionAvailability()
    end
    if Ui.updateAddPreview then
        Ui.updateAddPreview()
    end
    if Ui.groupList then
        Ui.groupList:Refresh()
    end
    if NobleNextCharDB then
        NobleNextCharDB.GobGroupActiveRoot = root
    end
    return true
end

function Panel.ClearActiveGroup()
    ActiveGroup = nil
    if Ui.groupGuidBox then
        Ui.groupGuidBox:SetText("")
    end
    UpdateContextHeader()
    if UpdateActionAvailability then
        UpdateActionAvailability()
    end
    if Ui.updateAddPreview then
        Ui.updateAddPreview()
    end
    if Ui.groupList then
        Ui.groupList:Refresh()
    end
    if NobleNextCharDB then
        NobleNextCharDB.GobGroupActiveRoot = nil
    end
end

function Panel.SetObjectGuid(guid)
    guid = PositiveGuid(guid)
    CurrentObjectGuid = guid
    if Ui.objectGuidBox then
        Ui.objectGuidBox:SetText(guid and tostring(guid) or "")
    end
    UpdateContextHeader()
    if UpdateActionAvailability then
        UpdateActionAvailability()
    end
    return guid ~= nil
end

function Panel.RefreshActive()
    local root = ResolveGroupGuid()
    if not root then
        ns.PrintError("Сначала сделайте группу активной.")
        return false
    end
    local objectGuid = CurrentObjectGuid or root
    SendGroupCmd("info", { objectGuid = objectGuid, [1] = objectGuid }, "gobgroup:refresh-info")
    SendGroupCmd("status", { groupGuid = root, [1] = root }, "gobgroup:refresh-status")
    return true
end

function Panel.ShowTab(name)
    if Ui.showTab then
        return Ui.showTab(name)
    end
    return false
end

function Panel.SetScanCandidates(candidates)
    Ui.scanCandidates = type(candidates) == "table" and candidates or {}
    if Ui.scanList then
        Ui.scanList.offset = 0
        Ui.scanList:SetRows(Ui.scanCandidates)
    end
    if Ui.scanEmpty then
        Ui.scanEmpty:SetShown(#Ui.scanCandidates == 0)
    end
end

local function PollStatusUntilIdle(groupGuid, attempt)
    attempt = attempt or 1
    if not groupGuid or attempt > 12 then
        return
    end

    SendGroupCmd("status", { groupGuid = groupGuid, [1] = groupGuid }, "gobgroup:poll-status")
    C_Timer.After(math.min(0.4 * attempt, 2.0), function()
        local st = Packets and Packets.State and Packets.State.status
        if st and st.groupGuid == groupGuid and st.busy then
            PollStatusUntilIdle(groupGuid, attempt + 1)
            return
        end

        local objectGuid = ResolveObjectGuid() or groupGuid
        SendGroupCmd("info", { objectGuid = objectGuid, [1] = objectGuid }, "gobgroup:refresh-info")
    end)
end

local function RefreshInspector()
    local guid = ResolveObjectGuid()
    if not guid then
        ns.PrintError("Укажите GUID объекта.")
        return
    end
    Panel.SetObjectGuid(guid)
    SendGroupCmd("info", { objectGuid = guid, [1] = guid }, "gobgroup:info")
end

local function RefreshStatus()
    local guid = RequireActiveGroup("обновить состояние")
    if not guid then
        return
    end
    SendGroupCmd("status", { groupGuid = guid, [1] = guid }, "gobgroup:status")
end

UpdateActionAvailability = function()
    local ready = Packets and Packets.IsCapsReady and Packets.IsCapsReady()
    for verb, btn in pairs(Ui.verbButtons) do
        local allowed = true
        if ready and Packets.CanVerb then
            allowed = Packets.CanVerb(verb)
        end
        local groupMissing = (GROUP_REQUIRED_VERBS[verb] or ACTIVE_CONTEXT_VERBS[verb]) and not ActiveGroup
        local memberMissing = verb == "add" and not PositiveGuid(Ui.memberGuidBox and Ui.memberGuidBox:GetText())
        if allowed and not groupMissing and not memberMissing then
            btn:Enable()
            btn:SetAlpha(1)
            btn:Show()
            btn.disabledReason = nil
        else
            btn:Disable()
            btn:SetAlpha(0.35)
            if not allowed then
                btn.disabledReason = "Сервер не разрешил выполнение этой команды."
            elseif groupMissing then
                btn.disabledReason = "Сначала сделайте группу активной."
            elseif memberMissing then
                btn.disabledReason = "Укажите GUID объекта, который нужно добавить."
            end
        end
    end
end

local function ApplyCapsToButtons()
    UpdateActionAvailability()
end

local function UpdateInspectorLabels()
    local info = Packets and Packets.State and Packets.State.info
    if not info then
        if Ui.groupLabel then
            Ui.groupLabel:SetText("Группа: -")
        end
        if Ui.flagsLabel then
            Ui.flagsLabel:SetText("Изменения / задача: -")
        end
        if Ui.memberList then
            Ui.memberList:SetRows({})
        end
        return
    end

    Panel.SetObjectGuid(info.objectGuid)
    if info.groupRoot and info.groupRoot > 0 then
        local map = info.object and info.object.map
        Panel.SetActiveGroup(info.groupRoot, {
            name = info.name,
            members = info.memberCount,
            map = map,
            serverPhaseId = info.object and info.object.serverPhaseId,
            dirty = info.dirty,
            busy = info.busy,
        })
        if PendingSelectionGuid == info.objectGuid then
            PendingSelectionGuid = nil
        end
    elseif PendingSelectionGuid and PendingSelectionGuid == info.objectGuid then
        Panel.ClearActiveGroup()
        PendingSelectionGuid = nil
        SetStatus("Указанный объект не входит в группу.", "warning")
    end

    local groupText
    if not info.groupRoot or info.groupRoot == 0 then
        groupText = "Объект не входит в группу"
    else
        groupText = string.format("Root %d  |  members %d  |  %s",
            info.groupRoot, info.memberCount or 0, info.name ~= "" and info.name or "без имени")
    end
    if Ui.groupLabel then
        Ui.groupLabel:SetText(groupText)
    end
    if Ui.flagsLabel then
        Ui.flagsLabel:SetText(string.format("Изменения: %s  |  Задача: %s",
            info.dirty and "да" or "нет",
            info.busy and "да" or "нет"))
    end
    local rows = {}
    if not info.groupRoot or info.groupRoot == 0 then
        local obj = info.object
        if obj then
            rows[#rows + 1] = {
                id = obj.guid,
                guid = obj.guid,
                entry = obj.entry,
                name = string.format("ВНЕ ГРУППЫ  entry=%d", obj.entry or 0),
                desc = string.format("map=%d RP phase=%d (%.1f %.1f %.1f)",
                    obj.map or 0, obj.serverPhaseId or 0, obj.x or 0, obj.y or 0, obj.z or 0),
                isRoot = false,
            }
        end
    else
        local obj = info.object
        if obj and obj.isRoot then
            rows[#rows + 1] = {
                id = obj.guid,
                guid = obj.guid,
                entry = obj.entry,
                name = string.format("ROOT  entry=%d", obj.entry or 0),
                desc = string.format("map=%d RP phase=%d (%.1f %.1f %.1f)",
                    obj.map or 0, obj.serverPhaseId or 0, obj.x or 0, obj.y or 0, obj.z or 0),
                isRoot = true,
            }
        else
            rows[#rows + 1] = {
                id = info.groupRoot,
                guid = info.groupRoot,
                entry = 0,
                name = "ROOT",
                desc = "канонический root",
                isRoot = true,
            }
        end
    end
    for i = 1, #(info.members or {}) do
        local m = info.members[i]
        local selected = m.guid == info.objectGuid and "  |cffffd100выбран|r" or ""
        rows[#rows + 1] = {
            id = m.guid,
            guid = m.guid,
            entry = m.entry,
            name = string.format("MEMBER  entry=%d%s", m.entry or 0, selected),
            desc = string.format("map=%d RP phase=%d (%.1f %.1f %.1f)",
                m.map or 0, m.serverPhaseId or 0, m.x or 0, m.y or 0, m.z or 0),
            isRoot = false,
        }
    end
    if Ui.memberList then
        Ui.memberList:SetRows(rows)
    end
end

local function UpdateStatusLabels()
    local st = Packets and Packets.State and Packets.State.status
    if not st or not Ui.flagsLabel then
        return
    end
    local jobLabels = {
        None = "нет",
        Queued = "в очереди",
        Calculated = "рассчитана",
        DbPending = "запись в БД",
        RuntimePending = "применение в мире",
        Completed = "завершена",
        Failed = "ошибка",
    }
    Ui.flagsLabel:SetText(string.format("Изменения: %s  |  Задача: %s  |  %s",
        st.dirty and "да" or "нет",
        st.busy and "да" or "нет",
        jobLabels[st.jobState] or (st.jobState ~= "" and st.jobState or "-")))
    if ActiveGroup and (st.groupGuid == ActiveGroup.root or st.groupGuid == 0) then
        Panel.SetActiveGroup(ActiveGroup.root, {
            dirty = st.dirty,
            busy = st.busy,
        })
    end
end

local function UpdateListRows()
    local list = Packets and Packets.State and Packets.State.list
    if not Ui.groupList then
        return
    end
    Ui.groupListMode = "list"
    Ui.groupList:SetRows((list and list.items) or {})
    if Ui.groupListHint then
        Ui.groupListHint:SetText(string.format(
            "Все группы%s: %d. Нажмите строку, чтобы сделать группу активной.",
            list and list.mapFilter and list.mapFilter ~= "all" and (" на map " .. tostring(list.mapFilter)) or "",
            list and #(list.items or {}) or 0))
    end
end

local function UpdateNearRows()
    local near = Packets and Packets.State and Packets.State.near
    if not Ui.groupList then
        return
    end
    Ui.groupListMode = "near"
    Ui.groupList:SetRows((near and near.items) or {})
    if Ui.groupListHint then
        Ui.groupListHint:SetText(string.format(
            "Рядом на map %s, радиус %.1f: %d. Список отсортирован по расстоянию.",
            near and near.map or "-",
            near and near.radius or 0,
            near and #(near.items or {}) or 0))
    end
end

local function Confirm(title, text, onAccept)
    StaticPopupDialogs["NN_GOBGROUP_CONFIRM"] = {
        text = text,
        button1 = YES,
        button2 = NO,
        OnAccept = function()
            if onAccept then
                onAccept()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("NN_GOBGROUP_CONFIRM")
    if title and ns.PrintDebug then
        ns.PrintDebug("Confirm: " .. title)
    end
end

local function BindVerb(btn, verb)
    Ui.verbButtons[verb] = btn
end

local function MakeBtn(parent, text, width, verb, onClick)
    local style = (verb == "delete" or verb == "cleanup" or verb == "dissolve") and "danger"
        or (verb == "create" or verb == "use") and "primary" or nil
    local btn = NNL.Widgets.CreateButton(parent, {text = text, width = width or 90, height = 22, style = style})
    if verb then
        BindVerb(btn, verb)
        if btn.SetMotionScriptsWhileDisabled then
            btn:SetMotionScriptsWhileDisabled(true)
        end
        btn:SetScript("OnEnter", function(self)
            if self:IsEnabled() then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Действие недоступно", 1, 0.35, 0.35)
            GameTooltip:AddLine(self.disabledReason or "Проверьте активный контекст.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    btn:SetScript("OnClick", onClick)
    return btn
end

function Panel.RequestAvailability()
    SendGroupCmd("capabilities", {}, "gobgroup:caps")
end

function Panel.OnShow()
    Panel.RequestAvailability()
    if not ActiveGroup and NobleNextCharDB then
        local savedRoot = PositiveGuid(NobleNextCharDB.GobGroupActiveRoot)
        if savedRoot then
            PendingSelectionGuid = savedRoot
            if Ui.groupGuidBox then
                Ui.groupGuidBox:SetText(tostring(savedRoot))
            end
            Panel.SetObjectGuid(savedRoot)
            SetStatus(string.format("Проверяю сохранённую группу root %d...", savedRoot), "warning")
            SendGroupCmd("use", { groupGuid = savedRoot, [1] = savedRoot }, "gobgroup:restore-use")
            SendGroupCmd("info", { objectGuid = savedRoot, [1] = savedRoot }, "gobgroup:restore-info")
            SendGroupCmd("status", { groupGuid = savedRoot, [1] = savedRoot }, "gobgroup:restore-status")
        end
    end
    local guid = ResolveObjectGuid()
    if guid then
        Panel.SetObjectGuid(guid)
    end
    UpdateContextHeader()
    UpdateActionAvailability()
end

function Panel.Init(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:Hide()
    Ui.root = f

    f:SetScript("OnShow", function()
        Panel.OnShow()
    end)

    local Tabs = {}
    local TabButtons = {}

    local function ShowTab(name)
        if not Tabs[name] then
            return false
        end
        for tabName, tab in pairs(Tabs) do
            tab:SetShown(tabName == name)
        end
        for _, btn in ipairs(TabButtons) do
            ns.SetNGTabSelected(btn, btn.tabName == name)
        end
        Ui.activeTab = name
        return true
    end
    Ui.showTab = ShowTab

    local function CreateTabButton(text, tabName, x)
        local btn = ns.CreateNGTab(f, text, tabName, function() ShowTab(tabName) end)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", x, -78)
        btn.tabName = tabName
        TabButtons[#TabButtons + 1] = btn
        return btn
    end

    local function CreateTabFrame(name)
        local tf = CreateFrame("Frame", nil, f)
        tf:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -108)
        tf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 28)
        tf:Hide()
        Tabs[name] = tf
        return tf
    end

    Ui.contextFrame = ns.CreateNGSection(f, nil, nil, 66)
    Ui.contextFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -6)
    Ui.contextFrame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -6)
    Ui.contextFrame:SetHeight(66)

    Ui.contextGroupText = Ui.contextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    Ui.contextGroupText:SetPoint("TOPLEFT", Ui.contextFrame, "TOPLEFT", 12, -14)
    Ui.contextGroupText:SetPoint("TOPRIGHT", Ui.contextFrame, "TOPRIGHT", -12, -14)
    Ui.contextGroupText:SetJustifyH("LEFT")

    Ui.contextObjectText = Ui.contextFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Ui.contextObjectText:SetPoint("TOPLEFT", Ui.contextFrame, "TOPLEFT", 12, -40)
    Ui.contextObjectText:SetPoint("TOPRIGHT", Ui.contextFrame, "TOPRIGHT", -12, -40)
    Ui.contextObjectText:SetJustifyH("LEFT")
    Ui.contextObjectText:SetTextColor(0.75, 0.78, 0.8, 1)
    UpdateContextHeader()

    CreateTabButton("Инспектор", "inspect", 10)
    CreateTabButton("Состав", "members", 118)
    CreateTabButton("Трансформ", "xform", 210)
    CreateTabButton("Сервис", "service", 318)
    CreateTabButton("Шаблоны", "blueprint", 410)

    Ui.statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Ui.statusText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
    Ui.statusText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 8)
    Ui.statusText:SetJustifyH("LEFT")
    SetStatus("Готово. Выберите объект или сделайте группу активной.", "info")

    -----------------------------------------------------------------------
    -- Tab: Inspector
    -----------------------------------------------------------------------
    local inspect = CreateTabFrame("inspect")

    local inspSection = ns.CreateNGSection(inspect, "Инспектор объекта", nil, 122)
    inspSection:SetPoint("TOPLEFT", inspect, "TOPLEFT", 0, 0)
    inspSection:SetPoint("TOPRIGHT", inspect, "TOPRIGHT", 0, 0)
    inspSection:SetHeight(122)

    local guidLbl = ns.CreateNGLabel(inspSection, "GUID объекта:")
    guidLbl:SetPoint("TOPLEFT", inspSection, "TOPLEFT", 12, -28)
    Ui.objectGuidBox = ns.CreateNGEditBox(inspSection, "GobGroup_ObjectGuid", 110, 22)
    Ui.objectGuidBox:SetPoint("LEFT", guidLbl, "RIGHT", 8, 0)
    Ui.objectGuidBox:SetNumeric(true)
    Ui.objectGuidBox:SetScript("OnTextChanged", function(self)
        CurrentObjectGuid = PositiveGuid(self:GetText())
        UpdateContextHeader()
    end)

    local fillLast = MakeBtn(inspSection, "Последний GO", 100, nil, function()
        if ns.LastSpawnedGoGuid and ns.LastSpawnedGoGuid > 0 then
            Panel.SetObjectGuid(ns.LastSpawnedGoGuid)
        else
            ns.PrintError("Последний созданный GO не найден.")
        end
    end)
    fillLast:SetPoint("LEFT", Ui.objectGuidBox, "RIGHT", 8, 0)

    local fillMover = MakeBtn(inspSection, "Текущий GO", 90, nil, function()
        local g = TryGobMoverGuid()
        if g then
            Panel.SetObjectGuid(g)
        else
            ns.PrintError("Текущий GO в GobMover не выбран.")
        end
    end)
    fillMover:SetPoint("LEFT", fillLast, "RIGHT", 6, 0)

    local infoBtn = MakeBtn(inspSection, "Показать", 70, "info", RefreshInspector)
    infoBtn:SetPoint("LEFT", fillMover, "RIGHT", 6, 0)

    local groupGuidLbl = ns.CreateNGLabel(inspSection, "GUID группы:")
    groupGuidLbl:SetPoint("TOPLEFT", inspSection, "TOPLEFT", 12, -58)
    Ui.groupGuidBox = ns.CreateNGEditBox(inspSection, "GobGroup_GroupGuid", 110, 22)
    Ui.groupGuidBox:SetPoint("LEFT", groupGuidLbl, "RIGHT", 8, 0)
    Ui.groupGuidBox:SetNumeric(true)

    local activateBtn = MakeBtn(inspSection, "Сделать активной", 130, "use", function()
        local root = ResolveTypedGroupGuid()
        if not root then
            ns.PrintError("Введите root GUID или GUID участника группы.")
            return
        end
        Panel.ClearActiveGroup()
        Ui.groupGuidBox:SetText(tostring(root))
        PendingSelectionGuid = root
        Panel.SetObjectGuid(root)
        SendGroupCmd("use", { groupGuid = root, [1] = root }, "gobgroup:use")
        SendGroupCmd("info", { objectGuid = root, [1] = root }, "gobgroup:use-info")
        SendGroupCmd("status", { groupGuid = root, [1] = root }, "gobgroup:use-status")
        SetStatus(string.format("Проверяю группу по GUID %d...", root), "warning")
    end)
    activateBtn:SetPoint("LEFT", Ui.groupGuidBox, "RIGHT", 8, 0)

    local statusBtn = MakeBtn(inspSection, "Состояние", 90, "status", RefreshStatus)
    statusBtn:SetPoint("LEFT", activateBtn, "RIGHT", 6, 0)

    local checkBtn = MakeBtn(inspSection, "Проверить", 90, "check", function()
        local g = RequireActiveGroup("проверить группу")
        if not g then return end
        SendGroupCmd("check", { groupGuid = g, [1] = g })
    end)
    checkBtn:SetPoint("LEFT", statusBtn, "RIGHT", 6, 0)

    Ui.groupLabel = inspSection:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    Ui.groupLabel:SetPoint("TOPLEFT", inspSection, "TOPLEFT", 12, -88)
    Ui.groupLabel:SetPoint("RIGHT", inspSection, "CENTER", -8, 0)
    Ui.groupLabel:SetJustifyH("LEFT")
    Ui.groupLabel:SetText("Группа: -")

    Ui.flagsLabel = inspSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Ui.flagsLabel:SetPoint("TOPLEFT", inspSection, "TOP", 8, -88)
    Ui.flagsLabel:SetPoint("TOPRIGHT", inspSection, "TOPRIGHT", -12, -88)
    Ui.flagsLabel:SetJustifyH("LEFT")
    Ui.flagsLabel:SetTextColor(0.75, 0.75, 0.75, 1)
    Ui.flagsLabel:SetText("Изменения / задача: -")

    local memSection = ns.CreateNGSection(inspect, "Состав группы")
    memSection:SetPoint("TOPLEFT", inspSection, "BOTTOMLEFT", 0, -8)
    memSection:SetPoint("BOTTOMRIGHT", inspect, "BOTTOMRIGHT", 0, 0)

    local scroll = NNL.Scroll.CreateFrame(memSection)
    scroll:SetPoint("TOPLEFT", memSection, "TOPLEFT", 8, -28)
    scroll:SetPoint("BOTTOMRIGHT", memSection, "BOTTOMRIGHT", -28, 8)
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(560)
    scrollChild:SetHeight(24)
    scroll:SetScrollChild(scrollChild)

    Ui.memberList = ns.VirtualList.Create(scrollChild, {
        width = 550,
        visibleCount = 8,
        rowHeight = 22,
        scrollFrame = scroll,
        onClick = function(row)
            if row and row.guid then
                Panel.SetObjectGuid(row.guid)
                if not row.isRoot and Ui.memberGuidBox then
                    Ui.memberGuidBox:SetText(tostring(row.guid))
                    UpdateActionAvailability()
                end
            end
        end,
        renderRow = function(btn, row)
            local fs = btn.fs or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.fs = fs
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", btn, "LEFT", 6, 0)
            fs:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            fs:SetJustifyH("LEFT")
            fs:SetText(string.format("GUID %d  %s  %s", row.guid or row.id or 0, row.name or "", row.desc or ""))
        end,
    })

    -----------------------------------------------------------------------
    -- Tab: Members / create
    -----------------------------------------------------------------------
    local members = CreateTabFrame("members")

    local createSec = ns.CreateNGSection(members, "Создание и выбор группы", nil, 92)
    createSec:SetPoint("TOPLEFT", members, "TOPLEFT", 0, 0)
    createSec:SetPoint("TOPRIGHT", members, "TOPRIGHT", 0, 0)
    createSec:SetHeight(92)

    local nameLbl = ns.CreateNGLabel(createSec, "Имя:")
    nameLbl:SetPoint("TOPLEFT", createSec, "TOPLEFT", 12, -30)
    Ui.nameBox = ns.CreateNGEditBox(createSec, "GobGroup_Name", 180, 22)
    Ui.nameBox:SetPoint("LEFT", nameLbl, "RIGHT", 8, 0)

    local createBtn = MakeBtn(createSec, "Создать", 80, "create", function()
        local g = ResolveObjectGuid()
        if not g then
            ns.PrintError("Нужен GUID объекта, который станет root.")
            return
        end
        local name = Trim(Ui.nameBox:GetText())
        local args = { rootGuid = g, [1] = g }
        if name ~= "" then
            args.name = name
            args[2] = name
        end
        if SendGroupCmd("create", args) then
            PendingCreate = { root = g, name = name }
            SetStatus(string.format("Создание группы с root %d...", g), "warning")
        end
    end)
    createBtn:SetPoint("LEFT", Ui.nameBox, "RIGHT", 10, 0)

    local targetBtn = MakeBtn(createSec, "Выбрать root в мире", 150, "target", function()
        local g = RequireActiveGroup("выбрать root в мире")
        if not g then return end
        SendGroupCmd("target", { groupGuid = g, [1] = g })
    end)
    targetBtn:SetPoint("LEFT", createBtn, "RIGHT", 6, 0)

    local hint = createSec:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", createSec, "TOPLEFT", 12, -62)
    hint:SetPoint("TOPRIGHT", createSec, "TOPRIGHT", -12, -62)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(0.65, 0.65, 0.65, 1)
    hint:SetText("\"Создать\" использует GUID объекта как root. Активную группу задайте в Инспекторе или списке.")

    local editSec = ns.CreateNGSection(members, "Добавление и удаление объектов", nil, 164)
    editSec:SetPoint("TOPLEFT", createSec, "BOTTOMLEFT", 0, -8)
    editSec:SetPoint("TOPRIGHT", createSec, "BOTTOMRIGHT", 0, -8)
    editSec:SetHeight(164)

    local memLbl = ns.CreateNGLabel(editSec, "GUID объекта:")
    memLbl:SetPoint("TOPLEFT", editSec, "TOPLEFT", 12, -30)
    Ui.memberGuidBox = ns.CreateNGEditBox(editSec, "GobGroup_MemberGuid", 90, 22)
    Ui.memberGuidBox:SetPoint("LEFT", memLbl, "RIGHT", 8, 0)
    Ui.memberGuidBox:SetNumeric(true)

    local currentMemberBtn = MakeBtn(editSec, "Текущий GO", 90, nil, function()
        local guid = ResolveObjectGuid()
        if not guid then
            ns.PrintError("Текущий GO не выбран.")
            return
        end
        Ui.memberGuidBox:SetText(tostring(guid))
        Panel.SetObjectGuid(guid)
        UpdateActionAvailability()
    end)
    currentMemberBtn:SetPoint("LEFT", Ui.memberGuidBox, "RIGHT", 6, 0)

    local lastMemberBtn = MakeBtn(editSec, "Последний GO", 90, nil, function()
        local guid = PositiveGuid(ns.LastSpawnedGoGuid)
        if not guid then
            ns.PrintError("Последний созданный GO не найден.")
            return
        end
        Ui.memberGuidBox:SetText(tostring(guid))
        Panel.SetObjectGuid(guid)
        UpdateActionAvailability()
    end)
    lastMemberBtn:SetPoint("LEFT", currentMemberBtn, "RIGHT", 6, 0)

    local addBtn = MakeBtn(editSec, "Добавить", 80, "add", function()
        local group = RequireActiveGroup("добавить объект")
        local member = PositiveGuid(Ui.memberGuidBox:GetText())
        if not group or not member or member <= 0 then
            ns.PrintError("Выберите активную группу и укажите GUID объекта.")
            return
        end
        SendGroupCmd("add", { groupGuid = group, memberGuid = member, [1] = group, [2] = member })
    end)
    addBtn:SetPoint("LEFT", lastMemberBtn, "RIGHT", 6, 0)
    Ui.addButton = addBtn

    local removeBtn = MakeBtn(editSec, "Убрать", 80, "remove", function()
        local group = RequireActiveGroup("убрать объект")
        local member = PositiveGuid(Ui.memberGuidBox:GetText())
        if not group or not member or member <= 0 then
            ns.PrintError("Выберите активную группу и укажите GUID объекта.")
            return
        end
        SendGroupCmd("remove", { groupGuid = group, memberGuid = member, [1] = group, [2] = member })
    end)
    removeBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)

    local saveAsTplBtn = MakeBtn(editSec, "Сохранить как шаблон…", 160, nil, function()
        Panel.ShowTab("blueprint")
        if Ui.blueprintNameBox then
            Ui.blueprintNameBox:SetFocus()
        end
        SetStatus("Введите имя шаблона и нажмите «Сохранить группу как шаблон».", "info")
    end)
    saveAsTplBtn:SetPoint("LEFT", removeBtn, "RIGHT", 8, 0)
    Ui.buttons.blueprint_bridge = saveAsTplBtn

    Ui.addPreview = editSec:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Ui.addPreview:SetPoint("TOPLEFT", editSec, "TOPLEFT", 12, -62)
    Ui.addPreview:SetPoint("TOPRIGHT", editSec, "TOPRIGHT", -12, -62)
    Ui.addPreview:SetJustifyH("LEFT")
    Ui.addPreview:SetTextColor(0.82, 0.75, 0.5, 1)

    local function UpdateAddPreview()
        local member = PositiveGuid(Ui.memberGuidBox:GetText())
        if not ActiveGroup then
            Ui.addPreview:SetText("|cffb06a6aСначала сделайте группу активной.|r")
        elseif not member then
            Ui.addPreview:SetText(string.format(
                "Добавить GO - в группу %d (%s)",
                ActiveGroup.root, GroupDisplayName(ActiveGroup)
            ))
        else
            Ui.addPreview:SetText(string.format(
                "Добавить GO %d в группу %d (%s)",
                member, ActiveGroup.root, GroupDisplayName(ActiveGroup)
            ))
        end
        UpdateActionAvailability()
    end
    Ui.updateAddPreview = UpdateAddPreview
    Ui.memberGuidBox:SetScript("OnTextChanged", UpdateAddPreview)

    local radLbl = ns.CreateNGLabel(editSec, "Радиус:")
    radLbl:SetPoint("TOPLEFT", editSec, "TOPLEFT", 12, -91)
    Ui.radiusBox = ns.CreateNGEditBox(editSec, "GobGroup_Radius", 60, 22)
    Ui.radiusBox:SetPoint("LEFT", radLbl, "RIGHT", 8, 0)
    Ui.radiusBox:SetText("10")

    local scanBtn = MakeBtn(editSec, "Найти рядом", 105, "scan", function()
        local group = RequireActiveGroup("найти рядом")
        local radius = tonumber(Trim(Ui.radiusBox:GetText()))
        if not group or not radius or radius <= 0 or radius > MAX_SCAN_RADIUS then
            ns.PrintError(string.format("Нужны активная группа и радиус в диапазоне (0, %d].", MAX_SCAN_RADIUS))
            return
        end
        SendGroupCmd("scan", { groupGuid = group, radius = radius, [1] = group, [2] = radius })
    end)
    scanBtn:SetPoint("LEFT", Ui.radiusBox, "RIGHT", 8, 0)

    local addNearBtn = MakeBtn(editSec, "Добавить рядом", 120, "addnear", function()
        local group = RequireActiveGroup("добавить рядом")
        local radius = tonumber(Trim(Ui.radiusBox:GetText()))
        if not group or not radius or radius <= 0 or radius > MAX_SCAN_RADIUS then
            ns.PrintError(string.format("Нужны активная группа и радиус в диапазоне (0, %d].", MAX_SCAN_RADIUS))
            return
        end
        Confirm("addnear",
            string.format("Добавить все GO в радиусе %.1f к группе %d?\nКоманда: .gobject group addnear %d %.1f confirm",
                radius, group, group, radius),
            function()
                SendGroupCmd("addnear", {
                    groupGuid = group, radius = radius, confirm = "confirm",
                    [1] = group, [2] = radius, [3] = "confirm",
                })
            end)
    end)
    addNearBtn:SetPoint("LEFT", scanBtn, "RIGHT", 6, 0)

    local captureBtn = MakeBtn(editSec, "Сохранить позицию", 150, "capture", function()
        local group = RequireActiveGroup("сохранить позицию")
        local g = ResolveObjectGuid()
        if not group or not g then
            ns.PrintError("Выберите активную группу и текущий объект.")
            return
        end
        SendGroupCmd("capture", { guid = g, [1] = g })
    end)
    captureBtn:SetPoint("TOPLEFT", editSec, "TOPLEFT", 12, -125)

    local scanSec = ns.CreateNGSection(members, "Как добавлять объекты", nil, 76)
    scanSec:SetPoint("TOPLEFT", editSec, "BOTTOMLEFT", 0, -8)
    scanSec:SetPoint("TOPRIGHT", editSec, "BOTTOMRIGHT", 0, -8)
    scanSec:SetHeight(76)

    local scanHelp = scanSec:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scanHelp:SetPoint("TOPLEFT", scanSec, "TOPLEFT", 12, -28)
    scanHelp:SetPoint("TOPRIGHT", scanSec, "TOPRIGHT", -12, -28)
    scanHelp:SetJustifyH("LEFT")
    scanHelp:SetTextColor(0.7, 0.72, 0.75, 1)
    scanHelp:SetText("Один GO: выберите его в чате [Sel] -> \"Текущий GO\" -> \"Добавить\".  Несколько: \"Найти рядом\" показывает dry-run в чате, \"Добавить рядом\" выполняет пакетное добавление с подтверждением.")
    UpdateAddPreview()

    -----------------------------------------------------------------------
    -- Tab: Transform
    -----------------------------------------------------------------------
    local xform = CreateTabFrame("xform")

    local syncSec = ns.CreateNGSection(xform, "Относительные позиции", nil, 70)
    syncSec:SetPoint("TOPLEFT", xform, "TOPLEFT", 0, 0)
    syncSec:SetPoint("TOPRIGHT", xform, "TOPRIGHT", 0, 0)
    syncSec:SetHeight(70)

    local recalcBtn = MakeBtn(syncSec, "Пересчитать", 110, "recalc", function()
        local g = RequireActiveGroup("пересчитать относительные позиции")
        if not g then return end
        SendGroupCmd("recalc", { groupGuid = g, [1] = g })
    end)
    recalcBtn:SetPoint("TOPLEFT", syncSec, "TOPLEFT", 12, -30)

    local syncBtn = MakeBtn(syncSec, "Синхронизировать", 150, "sync", function()
        local g = RequireActiveGroup("синхронизировать группу")
        if not g then return end
        SendGroupCmd("sync", { groupGuid = g, [1] = g })
    end)
    syncBtn:SetPoint("LEFT", recalcBtn, "RIGHT", 6, 0)

    local moveSec = ns.CreateNGSection(xform, "Перемещение и поворот")
    moveSec:SetPoint("TOPLEFT", syncSec, "BOTTOMLEFT", 0, -8)
    moveSec:SetPoint("BOTTOMRIGHT", xform, "BOTTOMRIGHT", 0, 0)

    local function coordBox(parent, name, label, x, y, w, default)
        local lbl = ns.CreateNGLabel(parent, label)
        lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        local box = ns.CreateNGEditBox(parent, name, w or 70, 22)
        box:SetPoint("LEFT", lbl, "RIGHT", 6, 0)
        if default then
            box:SetText(default)
        end
        return box
    end

    Ui.xBox = coordBox(moveSec, "GobGroup_X", "X:", 12, -30, 70)
    Ui.yBox = coordBox(moveSec, "GobGroup_Y", "Y:", 140, -30, 70)
    Ui.zBox = coordBox(moveSec, "GobGroup_Z", "Z:", 268, -30, 70)
    Ui.oBox = coordBox(moveSec, "GobGroup_O", "O:", 396, -30, 70)
    Ui.mapBox = coordBox(moveSec, "GobGroup_Map", "Карта:", 12, -66, 70)

    local moveBtn = MakeBtn(moveSec, "Переместить", 110, "move", function()
        local g = RequireActiveGroup("переместить группу")
        if not g then return end
        local xText, yText, zText = Trim(Ui.xBox:GetText()), Trim(Ui.yBox:GetText()), Trim(Ui.zBox:GetText())
        if xText ~= "" or yText ~= "" or zText ~= "" then
            local x, y, z = tonumber(xText), tonumber(yText), tonumber(zText)
            if not x or not y or not z then
                ns.PrintError("Для перемещения заполните все координаты X, Y, Z числами.")
                return
            end
            SendGroupCmd("move", {
                groupGuid = g, x = x, y = y, z = z,
                [1] = g, [2] = x, [3] = y, [4] = z,
            })
        else
            SendGroupCmd("move", { groupGuid = g, [1] = g })
        end
    end)
    moveBtn:SetPoint("TOPLEFT", moveSec, "TOPLEFT", 12, -110)

    local turnBtn = MakeBtn(moveSec, "Повернуть", 100, "turn", function()
        local g = RequireActiveGroup("повернуть группу")
        if not g then return end
        local oText = Trim(Ui.oBox:GetText())
        if oText ~= "" then
            local o = tonumber(oText)
            if not o then
                ns.PrintError("Ориентация должна быть числом.")
                return
            end
            SendGroupCmd("turn", { groupGuid = g, orientation = o, [1] = g, [2] = o })
        else
            SendGroupCmd("turn", { groupGuid = g, [1] = g })
        end
    end)
    turnBtn:SetPoint("LEFT", moveBtn, "RIGHT", 6, 0)

    local relocBtn = MakeBtn(moveSec, "На другую карту", 140, "relocate", function()
        local g = RequireActiveGroup("перенести группу")
        local mapId = tonumber(Trim(Ui.mapBox:GetText()))
        local x = tonumber(Trim(Ui.xBox:GetText()))
        local y = tonumber(Trim(Ui.yBox:GetText()))
        local z = tonumber(Trim(Ui.zBox:GetText()))
        local o = tonumber(Trim(Ui.oBox:GetText()))
        if not g or not mapId or not x or not y or not z or not o then
            ns.PrintError("Перенос: активная группа, map, X, Y, Z и O обязательны.")
            return
        end
        Confirm("relocate",
            string.format("Перенести группу %d на карту %d (%.2f %.2f %.2f o=%.2f)?\nТребуется подтверждение.",
                g, mapId, x, y, z, o),
            function()
                SendGroupCmd("relocate", {
                    groupGuid = g, mapId = mapId, x = x, y = y, z = z, o = o, confirm = "confirm",
                    [1] = g, [2] = mapId, [3] = x, [4] = y, [5] = z, [6] = o, [7] = "confirm",
                })
            end)
    end)
    relocBtn:SetPoint("LEFT", turnBtn, "RIGHT", 6, 0)

    local helpX = moveSec:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    helpX:SetPoint("TOPLEFT", moveSec, "TOPLEFT", 12, -150)
    helpX:SetPoint("TOPRIGHT", moveSec, "TOPRIGHT", -12, -150)
    helpX:SetJustifyH("LEFT")
    helpX:SetTextColor(0.65, 0.65, 0.65, 1)
    helpX:SetText("Без координат используются позиция и ориентация игрока. Перенос на другую карту требует подтверждения.")

    -----------------------------------------------------------------------
    -- Tab: Service
    -----------------------------------------------------------------------
    local service = CreateTabFrame("service")

    local listSec = ns.CreateNGSection(service, "Выбор группы")
    listSec:SetPoint("TOPLEFT", service, "TOPLEFT", 0, 0)
    listSec:SetPoint("BOTTOMRIGHT", service, "BOTTOMRIGHT", 0, 128)

    local nearRadiusLbl = ns.CreateNGLabel(listSec, "Рядом:")
    nearRadiusLbl:SetPoint("TOPLEFT", listSec, "TOPLEFT", 12, -28)
    Ui.nearRadiusBox = ns.CreateNGEditBox(listSec, "GobGroup_NearRadius", 52, 22)
    Ui.nearRadiusBox:SetPoint("LEFT", nearRadiusLbl, "RIGHT", 6, 0)
    Ui.nearRadiusBox:SetText("50")

    local nearBtn = MakeBtn(listSec, "Найти рядом", 100, "near", function()
        local radius = tonumber(Trim(Ui.nearRadiusBox:GetText()))
        if not radius or radius <= 0 or radius > MAX_NEAR_RADIUS then
            ns.PrintError(string.format("Радиус поиска групп должен быть в диапазоне (0, %d].", MAX_NEAR_RADIUS))
            return
        end
        SendGroupCmd("near", { radius = radius, [1] = radius }, "gobgroup:near")
    end)
    nearBtn:SetPoint("LEFT", Ui.nearRadiusBox, "RIGHT", 6, 0)

    local mapFilterLbl = ns.CreateNGLabel(listSec, "Карта:")
    mapFilterLbl:SetPoint("LEFT", nearBtn, "RIGHT", 12, 0)
    Ui.listMapBox = ns.CreateNGEditBox(listSec, "GobGroup_ListMap", 52, 22)
    Ui.listMapBox:SetPoint("LEFT", mapFilterLbl, "RIGHT", 6, 0)
    Ui.listMapBox:SetNumeric(true)

    local listBtn = MakeBtn(listSec, "Все / карта", 95, "list", function()
        local mapId = Trim(Ui.listMapBox:GetText())
        if mapId ~= "" then
            local numericMapId = tonumber(mapId)
            if not numericMapId then
                ns.PrintError("Фильтр карты должен быть числом.")
                return
            end
            SendGroupCmd("list", { mapId = numericMapId, [1] = numericMapId })
        else
            SendGroupCmd("list", {})
        end
    end)
    listBtn:SetPoint("LEFT", Ui.listMapBox, "RIGHT", 6, 0)

    local reloadBtn = MakeBtn(listSec, "Обновить кеш", 110, "reload", function()
        SendGroupCmd("reload", {})
    end)
    reloadBtn:SetPoint("LEFT", listBtn, "RIGHT", 6, 0)

    local toTplBtn = MakeBtn(listSec, "В шаблон…", 100, nil, function()
        if not RequireActiveGroup("сохранить как шаблон") then
            return
        end
        Ui.pendingBlueprintPick = nil
        Panel.ShowTab("blueprint")
        if Ui.blueprintNameBox then
            Ui.blueprintNameBox:SetFocus()
        end
        if Ui.refreshBlueprintSource then
            Ui.refreshBlueprintSource()
        end
        SetStatus("Активная группа — источник. Введите имя и сохраните / перезапишите шаблон.", "info")
    end)
    toTplBtn:SetPoint("LEFT", reloadBtn, "RIGHT", 6, 0)
    Ui.buttons.service_to_blueprint = toTplBtn

    Ui.groupListHint = listSec:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Ui.groupListHint:SetPoint("TOPLEFT", listSec, "TOPLEFT", 12, -55)
    Ui.groupListHint:SetPoint("TOPRIGHT", listSec, "TOPRIGHT", -12, -55)
    Ui.groupListHint:SetJustifyH("LEFT")
    Ui.groupListHint:SetTextColor(0.7, 0.72, 0.75, 1)
    Ui.groupListHint:SetText("Клик по группе = активный источник. «В шаблон…» — снимок на вкладке Шаблоны.")

    local listScroll = NNL.Scroll.CreateFrame(listSec)
    listScroll:SetPoint("TOPLEFT", listSec, "TOPLEFT", 8, -76)
    listScroll:SetPoint("BOTTOMRIGHT", listSec, "BOTTOMRIGHT", -28, 8)
    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetWidth(560)
    listChild:SetHeight(24)
    listScroll:SetScrollChild(listChild)

    Ui.groupList = ns.VirtualList.Create(listChild, {
        width = 550,
        visibleCount = 6,
        rowHeight = 22,
        scrollFrame = listScroll,
        onClick = function(row)
            if row and row.root then
                Panel.SetActiveGroup(row.root, {
                    name = row.name,
                    members = row.members,
                    map = row.map,
                    serverPhaseId = row.serverPhaseId,
                })
                Panel.SetObjectGuid(row.root)
                SendGroupCmd("use", { groupGuid = row.root, [1] = row.root }, "gobgroup:list-use")
                SendGroupCmd("info", { objectGuid = row.root, [1] = row.root }, "gobgroup:list-info")
                SendGroupCmd("status", { groupGuid = row.root, [1] = row.root }, "gobgroup:list-status")
                if Ui.pendingBlueprintPick then
                    Ui.pendingBlueprintPick = nil
                    Panel.ShowTab("blueprint")
                    SetStatus(string.format(
                        "Источник: root %d. Введите имя и нажмите «Сохранить группу как шаблон» / «Перезаписать».",
                        row.root
                    ), "info")
                else
                    Panel.ShowTab("inspect")
                    SetStatus(string.format("Группа root %d сделана активной.", row.root), "info")
                end
            end
        end,
        renderRow = function(btn, row)
            local fs = btn.fs or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.fs = fs
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", btn, "LEFT", 6, 0)
            fs:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            fs:SetJustifyH("LEFT")
            local selected = ActiveGroup and ActiveGroup.root == row.root
            if btn.SetBackdropColor then
                btn:SetBackdropColor(
                    selected and 0.22 or 0.08,
                    selected and 0.17 or 0.08,
                    selected and 0.04 or 0.08,
                    0.92)
            end
            if row.distance then
                fs:SetText(string.format("root %d  %s  | %.1f ярд  | RP phase=%d  | members=%d  | (%.1f %.1f %.1f)",
                    row.root or 0, row.name ~= "" and row.name or "без имени",
                    row.distance or 0, row.serverPhaseId or 0, row.members or 0, row.x or 0, row.y or 0, row.z or 0))
            else
                fs:SetText(string.format("root %d  %s  | members=%d  | map=%d | RP phase=%d",
                    row.root or 0, row.name ~= "" and row.name or "без имени",
                    row.members or 0, row.map or 0, row.serverPhaseId or 0))
            end
        end,
    })
    local danger = ns.CreateNGSection(service, "Опасные операции", nil, 120)
    danger:SetPoint("BOTTOMLEFT", service, "BOTTOMLEFT", 0, 0)
    danger:SetPoint("BOTTOMRIGHT", service, "BOTTOMRIGHT", 0, 0)
    danger:SetHeight(120)

    local dissolveBtn = MakeBtn(danger, "Распустить", 110, "dissolve", function()
        local g = RequireActiveGroup("распустить группу")
        if not g then return end
        Confirm("dissolve",
            string.format("Распустить группу %d?\nУдалится только metadata, GO останутся.", g),
            function()
                SendGroupCmd("dissolve", { groupGuid = g, [1] = g })
            end)
    end)
    dissolveBtn:SetPoint("TOPLEFT", danger, "TOPLEFT", 12, -32)

    local cleanupBtn = MakeBtn(danger, "Очистить метаданные", 160, "cleanup", function()
        Confirm("cleanup",
            "Удалить orphan group metadata по всему миру?\nGO не удаляются. Команда: .gobject group cleanup confirm",
            function()
                SendGroupCmd("cleanup", { confirm = "confirm", [1] = "confirm" })
            end)
    end)
    cleanupBtn:SetPoint("LEFT", dissolveBtn, "RIGHT", 8, 0)

    local deleteBtn = MakeBtn(danger, "Удалить всю группу", 160, "delete", function()
        local g = RequireActiveGroup("удалить всю группу")
        if not g then return end
        Confirm("delete",
            string.format("|cffff4444ПОЛНОЕ УДАЛЕНИЕ|r группы %d.\nБудут удалены root и ВСЕ members из runtime и БД.\n\nКоманда: .gobject group delete %d full-force\n\nЭто необратимо. Продолжить?", g, g),
            function()
                SendGroupCmd("delete", {
                    groupGuid = g, fullForce = "full-force",
                    [1] = g, [2] = "full-force",
                })
            end)
    end)
    deleteBtn:SetPoint("LEFT", cleanupBtn, "RIGHT", 8, 0)

    local dangerHint = danger:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dangerHint:SetPoint("TOPLEFT", danger, "TOPLEFT", 12, -70)
    dangerHint:SetPoint("TOPRIGHT", danger, "TOPRIGHT", -12, -70)
    dangerHint:SetJustifyH("LEFT")
    dangerHint:SetTextColor(1, 0.5, 0.4, 1)
    dangerHint:SetText("\"Распустить\" сохраняет GO. \"Удалить всю группу\" необратимо удаляет root и все объекты.")

    -----------------------------------------------------------------------
    -- Tab: Шаблоны (Blueprint library — snapshot of active GobGroup)
    -----------------------------------------------------------------------
    local blueprint = CreateTabFrame("blueprint")

    local srcSec = ns.CreateNGSection(blueprint, "Источник для снимка", nil, 92)
    srcSec:SetPoint("TOPLEFT", blueprint, "TOPLEFT", 0, 0)
    srcSec:SetPoint("TOPRIGHT", blueprint, "TOPRIGHT", 0, 0)
    srcSec:SetHeight(92)

    Ui.blueprintSourceText = srcSec:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    Ui.blueprintSourceText:SetPoint("TOPLEFT", srcSec, "TOPLEFT", 12, -28)
    Ui.blueprintSourceText:SetPoint("TOPRIGHT", srcSec, "TOPRIGHT", -12, -28)
    Ui.blueprintSourceText:SetJustifyH("LEFT")

    Ui.blueprintHint = srcSec:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Ui.blueprintHint:SetPoint("TOPLEFT", srcSec, "TOPLEFT", 12, -48)
    Ui.blueprintHint:SetPoint("TOPRIGHT", srcSec, "TOPRIGHT", -12, -48)
    Ui.blueprintHint:SetJustifyH("LEFT")
    Ui.blueprintHint:SetTextColor(0.7, 0.72, 0.75, 1)
    Ui.blueprintHint:SetText("Шаблон = снимок активной группы. Другую группу: «Выбрать группу…» -> клик в списке -> вернуться и сохранить.")

    local pickGroupBtn = MakeBtn(srcSec, "Выбрать группу…", 140, "list", function()
        Ui.pendingBlueprintPick = true
        Panel.ShowTab("service")
        SetStatus("Выберите группу в списке (Найти рядом / Все) — вернёмся на «Шаблоны» автоматически.", "info")
    end)
    pickGroupBtn:SetPoint("TOPLEFT", srcSec, "TOPLEFT", 12, -66)
    Ui.buttons.blueprint_pick_group = pickGroupBtn

    local pickNearBtn = MakeBtn(srcSec, "Найти рядом", 110, "near", function()
        Ui.pendingBlueprintPick = true
        Panel.ShowTab("service")
        local radius = tonumber(Trim(Ui.nearRadiusBox and Ui.nearRadiusBox:GetText() or "")) or 50
        if radius <= 0 or radius > MAX_NEAR_RADIUS then
            radius = 50
        end
        SendGroupCmd("near", { radius = radius, [1] = radius }, "gobblueprint:pick-near")
        SetStatus(string.format("Ищем группы в радиусе %d… Клик по строке -> источник снимка.", radius), "info")
    end)
    pickNearBtn:SetPoint("LEFT", pickGroupBtn, "RIGHT", 8, 0)
    Ui.buttons.blueprint_pick_near = pickNearBtn

    local function ActiveGroupGoCount()
        if not ActiveGroup then
            return 0
        end
        local members = tonumber(ActiveGroup.members) or 0
        return members + 1 -- root + members
    end

    Ui.refreshBlueprintSource = function()
        if not Ui.blueprintSourceText then
            return
        end
        if ActiveGroup and ActiveGroup.root then
            local n = ActiveGroupGoCount()
            Ui.blueprintSourceText:SetText(string.format(
                "|cff7fe39aИсточник:|r root %d «%s» — |cffffd76a%d GO|r",
                ActiveGroup.root, GroupDisplayName(ActiveGroup), n
            ))
        else
            Ui.blueprintSourceText:SetText("|cffff6b6bИсточник: нет активной группы|r — захват недоступен")
        end
        if Ui.refreshBlueprintActions then
            Ui.refreshBlueprintActions()
        end
    end

    local saveSec = ns.CreateNGSection(blueprint, "Создать / перезаписать шаблон", nil, 78)
    saveSec:SetPoint("TOPLEFT", srcSec, "BOTTOMLEFT", 0, -8)
    saveSec:SetPoint("TOPRIGHT", srcSec, "BOTTOMRIGHT", 0, -8)
    saveSec:SetHeight(78)

    local bpNameLbl = ns.CreateNGLabel(saveSec, "Имя шаблона:")
    bpNameLbl:SetPoint("TOPLEFT", saveSec, "TOPLEFT", 12, -30)
    Ui.blueprintNameBox = ns.CreateNGEditBox(saveSec, "GobGroup_BlueprintName", 160, 22)
    Ui.blueprintNameBox:SetPoint("LEFT", bpNameLbl, "RIGHT", 8, 0)
    Ui.blueprintNameBox:SetScript("OnTextChanged", function()
        if Ui.refreshBlueprintActions then
            Ui.refreshBlueprintActions()
        end
    end)

    -- Prefer Account-Id key for mutate/spawn/info; typed name for `new`.
    local function SelectedBlueprintName()
        if Ui.selectedBlueprint then
            local key = Trim(Ui.selectedBlueprint.key or "")
            if key ~= "" then
                return key
            end
        end
        local typed = Trim(Ui.blueprintNameBox:GetText())
        if typed ~= "" then
            return typed
        end
        if Ui.selectedBlueprint then
            local name = Trim(Ui.selectedBlueprint.name or "")
            if name ~= "" then
                return name
            end
        end
        return nil
    end

    local function SelectedBlueprintTypedName()
        local typed = Trim(Ui.blueprintNameBox:GetText())
        if typed ~= "" then
            return typed
        end
        return nil
    end

    local function SelectedBlueprintDisplayName()
        if Ui.selectedBlueprint and Trim(Ui.selectedBlueprint.name or "") ~= "" then
            return Trim(Ui.selectedBlueprint.name)
        end
        return SelectedBlueprintTypedName() or SelectedBlueprintName() or "?"
    end

    local function ReloadBlueprintInfo()
        local key = SelectedBlueprintName()
        if not key then
            return
        end
        SendBlueprintCmd("info", { name = key, [1] = key }, "gobblueprint:info")
    end

    local function FormatBlueprintMemberLabel(m)
        local entry = tonumber(m.entry) or 0
        local id = tonumber(m.id) or 0
        local partId = tonumber(m.partId) or 0
        if entry == 0 then
            if m.isRoot then
                return string.format("[CENTER]  id=%d", id)
            end
            return string.format("[ROOT]  id=%d", id)
        end
        if m.isRoot then
            return string.format("[ROOT]  entry=%d  id=%d", entry, id)
        end
        return string.format("entry=%d  id=%d  part=%d", entry, id, partId)
    end

    -----------------------------------------------------------------------
    -- BlueprintManagerDlg (состав шаблона)
    -----------------------------------------------------------------------
    local function styleBlueprintDialog(f)
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 14,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            f:SetBackdropColor(0.05, 0.05, 0.06, 0.96)
            f:SetBackdropBorderColor(0.85, 0.7, 0.25, 0.95)
        end
    end

    local function RefreshBlueprintManagerMembers(info)
        local dlg = Ui.blueprintManagerDlg
        if not dlg or not dlg.memberList then
            return
        end
        dlg.memberList:SetRows((info and info.entries) or {})
        if dlg.title then
            local key = (info and info.key) or (Ui.selectedBlueprint and Ui.selectedBlueprint.key) or "?"
            local name = (info and info.name) or (Ui.selectedBlueprint and Ui.selectedBlueprint.name) or ""
            dlg.title:SetText(string.format("Состав: %s «%s»", key, name))
        end
        if dlg.publicDD and info then
            local v = info.isPublic and "1" or "0"
            dlg.publicValue = v
            UIDropDownMenu_SetSelectedValue(dlg.publicDD, v)
            UIDropDownMenu_SetText(dlg.publicDD, info.isPublic and "Публичный" or "Приватный")
        end
    end

    local function EnsureBlueprintManagerDlg()
        if Ui.blueprintManagerDlg then
            return Ui.blueprintManagerDlg
        end

        local f = CreateFrame("Frame", "NobleNextGobBlueprintManager", UIParent, "BackdropTemplate")
        f:SetSize(520, 440)
        f:SetPoint("CENTER", 0, 30)
        styleBlueprintDialog(f)
        f:Hide()
        Ui.blueprintManagerDlg = f
        f.publicValue = "0"
        f.selectedMember = nil

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOPLEFT", 14, -12)
        f.title:SetTextColor(1, 0.82, 0)
        f.title:SetText("Состав шаблона")

        local close = ns.CreateNGButton(f, "X", 24, 22)
        close:SetPoint("TOPRIGHT", -10, -10)
        close:SetScript("OnClick", function() f:Hide() end)

        local pubLbl = ns.CreateNGLabel(f, "Доступ:")
        pubLbl:SetPoint("TOPLEFT", 14, -42)
        f.publicDD = CreateFrame("Frame", "NobleNextGobBlueprintPublicDD", f, "UIDropDownMenuTemplate")
        f.publicDD:SetPoint("TOPLEFT", 70, -38)
        UIDropDownMenu_SetWidth(f.publicDD, 130)
        UIDropDownMenu_Initialize(f.publicDD, function()
            for _, entry in ipairs({
                { value = "0", label = "Приватный" },
                { value = "1", label = "Публичный" },
            }) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = entry.label
                info.value = entry.value
                info.func = function()
                    f.publicValue = entry.value
                    UIDropDownMenu_SetSelectedValue(f.publicDD, entry.value)
                    UIDropDownMenu_SetText(f.publicDD, entry.label)
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        local applyPublic = MakeBtn(f, "Применить", 90, nil, function()
            local key = SelectedBlueprintName()
            if not key then
                ns.PrintError("Шаблон не выбран.")
                return
            end
            local flag = f.publicValue == "1" and "1" or "0"
            SendBlueprintCmd("set-public", { [1] = key, [2] = flag }, "gobblueprint:set-public")
        end)
        applyPublic:SetPoint("LEFT", f.publicDD, "RIGHT", 8, 2)
        f.applyPublicBtn = applyPublic

        local listHost = CreateFrame("Frame", nil, f)
        listHost:SetPoint("TOPLEFT", 12, -78)
        listHost:SetPoint("TOPRIGHT", -28, -78)
        listHost:SetHeight(180)
        local scroll = NNL.Scroll.CreateFrame(listHost)
        scroll:SetPoint("TOPLEFT", 0, 0)
        scroll:SetPoint("BOTTOMRIGHT", 0, 0)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetWidth(460)
        child:SetHeight(24)
        scroll:SetScrollChild(child)

        f.memberList = ns.VirtualList.Create(child, {
            width = 450,
            visibleCount = 7,
            rowHeight = 22,
            scrollFrame = scroll,
            onClick = function(row)
                f.selectedMember = row
                SetStatus(string.format("Member id=%d выбран.", tonumber(row and row.id) or 0), "info")
            end,
            renderRow = function(btn, row)
                local fs = btn.fs or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                btn.fs = fs
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", btn, "LEFT", 6, 0)
                fs:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
                fs:SetJustifyH("LEFT")
                fs:SetText(FormatBlueprintMemberLabel(row or {}))
            end,
        })

        local y = -270
        local function place(btn, x)
            btn:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
        end

        local addGoBtn = MakeBtn(f, "Добавить GO", 110, nil, function()
            local key = SelectedBlueprintName()
            local anchor = RequireActiveGroup("добавить GO в шаблон")
            local guid = ResolveObjectGuid()
            if not key or not anchor then
                return
            end
            if not guid then
                ns.PrintError("Нет текущего GO (guid).")
                return
            end
            SendBlueprintCmd("member add", {
                [1] = "object", [2] = key, [3] = anchor, [4] = guid,
            }, "gobblueprint:member-add")
        end)
        place(addGoBtn, 14)

        local addGrpBtn = MakeBtn(f, "Добавить группу", 130, nil, function()
            local key = SelectedBlueprintName()
            local root = RequireActiveGroup("добавить группу в шаблон")
            if not key or not root then
                return
            end
            SendBlueprintCmd("member add", {
                [1] = "group", [2] = key, [3] = root, [4] = root,
            }, "gobblueprint:member-add")
        end)
        place(addGrpBtn, 132)

        local rmObjBtn = MakeBtn(f, "Убрать объект", 120, nil, function()
            local key = SelectedBlueprintName()
            local m = f.selectedMember
            if not key or not m or not m.id then
                ns.PrintError("Выберите member в списке.")
                return
            end
            SendBlueprintCmd("member remove", {
                [1] = "object", [2] = key, [3] = m.id,
            }, "gobblueprint:member-remove")
        end)
        place(rmObjBtn, 270)

        local rmGrpBtn = MakeBtn(f, "Убрать группу", 120, nil, function()
            local key = SelectedBlueprintName()
            local m = f.selectedMember
            if not key or not m then
                ns.PrintError("Выберите member/part в списке.")
                return
            end
            local partId = tonumber(m.partId) or 0
            if partId <= 0 then
                ns.PrintError("У выбранной строки нет part id.")
                return
            end
            SendBlueprintCmd("member remove", {
                [1] = "group", [2] = key, [3] = partId,
            }, "gobblueprint:member-remove")
        end)
        place(rmGrpBtn, 398)

        y = -300
        local entryLbl = ns.CreateNGLabel(f, "Entry:")
        entryLbl:SetPoint("TOPLEFT", 14, y)
        f.entryBox = ns.CreateNGEditBox(f, "GobGroup_BlueprintEntry", 80, 22)
        f.entryBox:SetPoint("LEFT", entryLbl, "RIGHT", 8, 0)

        local replaceBtn = MakeBtn(f, "Заменить entry", 120, nil, function()
            local key = SelectedBlueprintName()
            local m = f.selectedMember
            local entry = tonumber(Trim(f.entryBox:GetText()))
            if not key or not m or not m.id then
                ns.PrintError("Выберите member и укажите entry.")
                return
            end
            if not entry or entry < 0 then
                ns.PrintError("Некорректный entry.")
                return
            end
            SendBlueprintCmd("member replace", {
                [1] = key, [2] = m.id, [3] = entry,
            }, "gobblueprint:member-replace")
        end)
        replaceBtn:SetPoint("LEFT", f.entryBox, "RIGHT", 8, 0)

        local setRootBtn = MakeBtn(f, "Сделать root", 110, nil, function()
            local key = SelectedBlueprintName()
            local m = f.selectedMember
            if not key or not m or not m.id then
                ns.PrintError("Выберите member.")
                return
            end
            SendBlueprintCmd("member setroot", {
                [1] = key, [2] = m.id,
            }, "gobblueprint:member-setroot")
        end)
        setRootBtn:SetPoint("LEFT", replaceBtn, "RIGHT", 8, 0)

        y = -332
        local setCenterBtn = MakeBtn(f, "Центр здесь", 120, nil, function()
            local key = SelectedBlueprintName()
            if not key then
                ns.PrintError("Шаблон не выбран.")
                return
            end
            SendBlueprintCmd("member setcenter", {
                [1] = key, [2] = "player",
            }, "gobblueprint:member-setcenter")
        end)
        setCenterBtn:SetPoint("TOPLEFT", 14, y)

        local refreshBtn = MakeBtn(f, "Обновить", 90, nil, ReloadBlueprintInfo)
        refreshBtn:SetPoint("LEFT", setCenterBtn, "RIGHT", 8, 0)

        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("TOPLEFT", 14, -370)
        hint:SetPoint("TOPRIGHT", -14, -370)
        hint:SetJustifyH("LEFT")
        hint:SetTextColor(0.7, 0.72, 0.75, 1)
        hint:SetText("Добавить GO: текущий объект + активная группа как anchor. Убрать группу — по part id выбранной строки.")

        f.actionButtons = {
            applyPublic, addGoBtn, addGrpBtn, rmObjBtn, rmGrpBtn,
            replaceBtn, setRootBtn, setCenterBtn, refreshBtn,
        }
        return f
    end

    local function OpenBlueprintManager()
        local key = SelectedBlueprintName()
        if not key then
            ns.PrintError("Выберите шаблон в списке.")
            return
        end
        local dlg = EnsureBlueprintManagerDlg()
        dlg.selectedMember = nil
        dlg.title:SetText(string.format("Состав: %s «%s»", key, SelectedBlueprintDisplayName()))
        dlg:Show()
        ReloadBlueprintInfo()
    end

    local bpNewBtn = MakeBtn(saveSec, "Сохранить группу как шаблон", 200, nil, function()
        local name = SelectedBlueprintTypedName()
        if not name then
            ns.PrintError("Укажите имя шаблона.")
            return
        end
        if not RequireActiveGroup("сохранить шаблон") then
            return
        end
        SendBlueprintCmd("new", { name = name, [1] = name }, "gobblueprint:new")
    end)
    bpNewBtn:SetPoint("LEFT", Ui.blueprintNameBox, "RIGHT", 10, 0)
    Ui.buttons.blueprint_new = bpNewBtn

    local bpUpdateBtn = MakeBtn(saveSec, "Перезаписать шаблон", 150, nil, function()
        local key = SelectedBlueprintName()
        if not key then
            ns.PrintError("Укажите/выберите шаблон для перезаписи.")
            return
        end
        if not RequireActiveGroup("перезаписать шаблон") then
            return
        end
        local n = ActiveGroupGoCount()
        local display = SelectedBlueprintDisplayName()
        Confirm("blueprint-update",
            string.format(
                "Перезаписать шаблон «%s» (%s) составом активной группы (%d GO)?\nЭкземпляры в мире не изменятся.",
                display, key, n
            ),
            function()
                SendBlueprintCmd("update", { name = key, [1] = key }, "gobblueprint:update")
            end)
    end)
    bpUpdateBtn:SetPoint("LEFT", bpNewBtn, "RIGHT", 8, 0)
    Ui.buttons.blueprint_update = bpUpdateBtn

    local libSec = ns.CreateNGSection(blueprint, "Библиотека шаблонов")
    libSec:SetPoint("TOPLEFT", saveSec, "BOTTOMLEFT", 0, -8)
    libSec:SetPoint("BOTTOMRIGHT", blueprint, "BOTTOMRIGHT", 0, 0)

    Ui.blueprintListScope = Ui.blueprintListScope or "mine"

    local scopeMineBtn = MakeBtn(libSec, "Мои", 55, nil, function()
        Ui.blueprintListScope = "mine"
        if Ui.refreshBlueprintScopeButtons then Ui.refreshBlueprintScopeButtons() end
        if Ui.RefreshBlueprintListCmd then Ui.RefreshBlueprintListCmd() end
    end)
    scopeMineBtn:SetPoint("TOPLEFT", libSec, "TOPLEFT", 12, -28)
    Ui.buttons.blueprint_scope_mine = scopeMineBtn

    local scopePublicBtn = MakeBtn(libSec, "Публичные", 90, nil, function()
        Ui.blueprintListScope = "public"
        if Ui.refreshBlueprintScopeButtons then Ui.refreshBlueprintScopeButtons() end
        if Ui.RefreshBlueprintListCmd then Ui.RefreshBlueprintListCmd() end
    end)
    scopePublicBtn:SetPoint("LEFT", scopeMineBtn, "RIGHT", 4, 0)
    Ui.buttons.blueprint_scope_public = scopePublicBtn

    local scopeAllBtn = MakeBtn(libSec, "Все", 50, nil, function()
        Ui.blueprintListScope = "all"
        if Ui.refreshBlueprintScopeButtons then Ui.refreshBlueprintScopeButtons() end
        if Ui.RefreshBlueprintListCmd then Ui.RefreshBlueprintListCmd() end
    end)
    scopeAllBtn:SetPoint("LEFT", scopePublicBtn, "RIGHT", 4, 0)
    Ui.buttons.blueprint_scope_all = scopeAllBtn

    Ui.refreshBlueprintScopeButtons = function()
        local scope = Ui.blueprintListScope or "mine"
        scopeMineBtn:SetText(scope == "mine" and "* Мои" or "Мои")
        scopePublicBtn:SetText(scope == "public" and "* Публичные" or "Публичные")
        scopeAllBtn:SetText(scope == "all" and "* Все" or "Все")
    end
    Ui.refreshBlueprintScopeButtons()

    local bpFilterLbl = ns.CreateNGLabel(libSec, "Поиск:")
    bpFilterLbl:SetPoint("LEFT", scopeAllBtn, "RIGHT", 10, 0)
    Ui.blueprintFilterBox = ns.CreateNGEditBox(libSec, "GobGroup_BlueprintFilter", 100, 22)
    Ui.blueprintFilterBox:SetPoint("LEFT", bpFilterLbl, "RIGHT", 6, 0)

    local function RefreshBlueprintListCmd()
        local scope = Ui.blueprintListScope or "mine"
        local filter = Trim(Ui.blueprintFilterBox:GetText())
        if filter ~= "" then
            SendBlueprintCmd("list", { [1] = scope, [2] = filter }, "gobblueprint:list")
        else
            SendBlueprintCmd("list", { [1] = scope }, "gobblueprint:list")
        end
    end
    Ui.RefreshBlueprintListCmd = RefreshBlueprintListCmd

    local bpListBtn = MakeBtn(libSec, "Обновить", 80, nil, RefreshBlueprintListCmd)
    bpListBtn:SetPoint("LEFT", Ui.blueprintFilterBox, "RIGHT", 6, 0)
    Ui.buttons.blueprint_list = bpListBtn

    local bpSpawnBtn = MakeBtn(libSec, "Поставить здесь", 120, nil, function()
        local key = SelectedBlueprintName()
        if not key then
            ns.PrintError("Выберите шаблон в списке или укажите имя.")
            return
        end
        local members = Ui.selectedBlueprint and tonumber(Ui.selectedBlueprint.members) or nil
        if members == 0 then
            ns.PrintError("Шаблон пуст (0 GO). Удалите или перезапишите из активной группы.")
            return
        end
        SendBlueprintCmd("spawn", { name = key, [1] = key }, "gobblueprint:spawn")
    end)
    bpSpawnBtn:SetPoint("TOPLEFT", libSec, "TOPLEFT", 12, -56)
    Ui.buttons.blueprint_spawn = bpSpawnBtn

    local bpMembersBtn = MakeBtn(libSec, "Состав…", 90, nil, OpenBlueprintManager)
    bpMembersBtn:SetPoint("LEFT", bpSpawnBtn, "RIGHT", 6, 0)
    Ui.buttons.blueprint_members = bpMembersBtn

    local bpPublicBtn = MakeBtn(libSec, "Публичный/Приватный", 150, nil, function()
        local key = SelectedBlueprintName()
        if not key then
            ns.PrintError("Выберите шаблон.")
            return
        end
        local info = Ui.blueprintInfo
        local cur = false
        if info and info.key == key then
            cur = info.isPublic and true or false
        elseif Ui.selectedBlueprint then
            cur = Ui.selectedBlueprint.isPublic and true or false
        end
        local flag = cur and "0" or "1"
        SendBlueprintCmd("set-public", { [1] = key, [2] = flag }, "gobblueprint:set-public")
    end)
    bpPublicBtn:SetPoint("LEFT", bpMembersBtn, "RIGHT", 6, 0)
    Ui.buttons.blueprint_set_public = bpPublicBtn

    local bpInfoBtn = MakeBtn(libSec, "Подробнее", 90, nil, function()
        local key = SelectedBlueprintName()
        if not key then
            ns.PrintError("Выберите шаблон.")
            return
        end
        SendBlueprintCmd("info", { name = key, [1] = key }, "gobblueprint:info")
    end)
    bpInfoBtn:SetPoint("LEFT", bpPublicBtn, "RIGHT", 6, 0)
    Ui.buttons.blueprint_info = bpInfoBtn

    local bpDeleteBtn = MakeBtn(libSec, "Удалить", 80, nil, function()
        local key = SelectedBlueprintName()
        if not key then
            ns.PrintError("Выберите шаблон.")
            return
        end
        Confirm("blueprint-delete",
            string.format("Удалить шаблон «%s» (%s)?\nМировые экземпляры не затрагиваются.",
                SelectedBlueprintDisplayName(), key),
            function()
                SendBlueprintCmd("delete", { name = key, [1] = key }, "gobblueprint:delete")
            end)
    end)
    bpDeleteBtn:SetPoint("LEFT", bpInfoBtn, "RIGHT", 6, 0)
    Ui.buttons.blueprint_delete = bpDeleteBtn

    local bpRenameLbl = ns.CreateNGLabel(libSec, "Новое имя:")
    bpRenameLbl:SetPoint("TOPLEFT", libSec, "TOPLEFT", 12, -84)
    Ui.blueprintRenameBox = ns.CreateNGEditBox(libSec, "GobGroup_BlueprintRename", 140, 22)
    Ui.blueprintRenameBox:SetPoint("LEFT", bpRenameLbl, "RIGHT", 8, 0)

    local bpRenameBtn = MakeBtn(libSec, "Переименовать", 110, nil, function()
        local oldKey = SelectedBlueprintName()
        local newName = Trim(Ui.blueprintRenameBox:GetText())
        if not oldKey or newName == "" then
            ns.PrintError("Укажите шаблон и новое имя.")
            return
        end
        SendBlueprintCmd("rename", {
            oldName = oldKey,
            newName = newName,
            [1] = oldKey,
            [2] = newName,
        }, "gobblueprint:rename")
    end)
    bpRenameBtn:SetPoint("LEFT", Ui.blueprintRenameBox, "RIGHT", 8, 0)
    Ui.buttons.blueprint_rename = bpRenameBtn

    Ui.blueprintInfoText = libSec:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Ui.blueprintInfoText:SetPoint("LEFT", bpRenameBtn, "RIGHT", 12, 0)
    Ui.blueprintInfoText:SetJustifyH("LEFT")
    Ui.blueprintInfoText:SetText("Выберите шаблон в списке.")

    local bpScroll = NNL.Scroll.CreateFrame(libSec)
    bpScroll:SetPoint("TOPLEFT", libSec, "TOPLEFT", 8, -114)
    bpScroll:SetPoint("BOTTOMRIGHT", libSec, "BOTTOMRIGHT", -28, 8)
    local bpChild = CreateFrame("Frame", nil, bpScroll)
    bpChild:SetWidth(560)
    bpChild:SetHeight(24)
    bpScroll:SetScrollChild(bpChild)

    local function RefreshBlueprintList(payload)
        if not Ui.blueprintList then
            return
        end
        Ui.blueprintList:SetRows((payload and payload.items) or {})
    end

    local function SetBlueprintButtonEnabled(btn, allowed)
        if not btn then
            return
        end
        if btn.SetEnabled then
            btn:SetEnabled(allowed and true or false)
        elseif btn.Enable and btn.Disable then
            if allowed then btn:Enable() else btn:Disable() end
        end
    end

    Ui.refreshBlueprintActions = function()
        local hasGroup = ActiveGroup and ActiveGroup.root and true or false
        local typedName = SelectedBlueprintTypedName()
        local keyOrName = SelectedBlueprintName()
        local hasKey = keyOrName and keyOrName ~= ""
        local hasTyped = typedName and typedName ~= ""
        local sel = Ui.selectedBlueprint
        local info = Ui.blueprintInfo
        local selectedMembers = sel and tonumber(sel.members)
        if selectedMembers == nil and info then
            selectedMembers = tonumber(info.members)
        end
        local canSpawn = hasKey and selectedMembers ~= 0
        local canMutate = true
        if sel and sel.canMutate == false then
            canMutate = false
        elseif info and info.canMutate == false and (not sel or info.key == (sel.key or keyOrName)) then
            canMutate = false
        end
        local canSetPublic = false
        if info and info.canSetPublic then
            canSetPublic = true
        elseif sel and sel.canSetPublic then
            canSetPublic = true
        end

        local function cap(verb)
            if Packets and Packets.CanBlueprintVerb then
                return Packets.CanBlueprintVerb(verb)
            end
            return true
        end

        SetBlueprintButtonEnabled(Ui.buttons.blueprint_new, hasGroup and hasTyped and cap("new"))
        SetBlueprintButtonEnabled(Ui.buttons.blueprint_update, hasGroup and hasKey and canMutate and cap("update"))
        SetBlueprintButtonEnabled(Ui.buttons.blueprint_spawn, canSpawn and cap("spawn"))
        SetBlueprintButtonEnabled(Ui.buttons.blueprint_info, hasKey and cap("info"))
        SetBlueprintButtonEnabled(Ui.buttons.blueprint_delete, hasKey and canMutate and cap("delete"))
        SetBlueprintButtonEnabled(Ui.buttons.blueprint_rename, hasKey and canMutate and cap("rename"))
        SetBlueprintButtonEnabled(Ui.buttons.blueprint_list, cap("list"))
        SetBlueprintButtonEnabled(Ui.buttons.blueprint_members, hasKey and cap("info"))
        -- set-public may be absent from CommandDefinitions/caps map; gate by info.canSetPublic.
        SetBlueprintButtonEnabled(Ui.buttons.blueprint_set_public, hasKey and canSetPublic)
    end

    Ui.blueprintList = ns.VirtualList.Create(bpChild, {
        width = 550,
        visibleCount = 6,
        rowHeight = 22,
        scrollFrame = bpScroll,
        onClick = function(row)
            if not row then
                return
            end
            Ui.selectedBlueprint = row
            -- keep key on selection; fill name into editbox
            if Ui.blueprintNameBox then
                Ui.blueprintNameBox:SetText(row.name or "")
            end
            local n = tonumber(row.members) or 0
            local vis = row.isPublic and "public" or "private"
            if n == 0 then
                SetStatus(string.format(
                    "Шаблон %s «%s» пустой (0 GO) — удалите или перезапишите.",
                    row.key or "?", row.name or "?"
                ), "warning")
            else
                SetStatus(string.format("Выбран %s «%s» — %d GO [%s].",
                    row.key or "?", row.name or "?", n, vis), "info")
            end
            if Ui.refreshBlueprintActions then
                Ui.refreshBlueprintActions()
            end
            if row.key and row.key ~= "" then
                SendBlueprintCmd("info", { name = row.key, [1] = row.key }, "gobblueprint:select-info")
            end
        end,
        renderRow = function(btn, row)
            local fs = btn.fs or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.fs = fs
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", btn, "LEFT", 6, 0)
            fs:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            fs:SetJustifyH("LEFT")
            local n = tonumber(row.members) or 0
            local key = (row.key and row.key ~= "") and row.key or "?"
            local label = (row.name and row.name ~= "") and row.name or "без имени"
            local vis = row.isPublic and "public" or "private"
            if n == 0 then
                fs:SetText(string.format("|cffff6b6b[!] %s %s — 0 GO [%s]|r", key, label, vis))
            else
                fs:SetText(string.format("%s %s — %d GO [%s]", key, label, n, vis))
            end
        end,
    })

    local function ApplyBlueprintCaps()
        if Ui.refreshBlueprintActions then
            Ui.refreshBlueprintActions()
        end
    end

    local function ApplyAllCaps()
        ApplyCapsToButtons()
        ApplyBlueprintCaps()
    end

    Ui.refreshBlueprintSource()

    if Packets and Packets.On then
        Packets.On("caps", function()
            ApplyAllCaps()
        end)
        Packets.On("blueprint_list", function(payload)
            RefreshBlueprintList(payload)
            SetStatus("Список шаблонов обновлён.", "info")
            if Ui.refreshBlueprintActions then
                Ui.refreshBlueprintActions()
            end
        end)
        Packets.On("blueprint_info", function(info)
            Ui.blueprintInfo = info
            if info and Ui.selectedBlueprint then
                local sk = Ui.selectedBlueprint.key
                if not sk or sk == "" or sk == info.key then
                    Ui.selectedBlueprint.key = info.key
                    Ui.selectedBlueprint.name = info.name
                    Ui.selectedBlueprint.members = info.members
                    Ui.selectedBlueprint.isPublic = info.isPublic
                    Ui.selectedBlueprint.canMutate = info.canMutate
                    Ui.selectedBlueprint.canSetPublic = info.canSetPublic
                end
            end
            if Ui.blueprintInfoText and info then
                local n = tonumber(info.members) or 0
                local vis = info.isPublic and "public" or "private"
                if n == 0 then
                    Ui.blueprintInfoText:SetText(string.format(
                        "|cffff6b6b%s «%s» пуст (0 GO) [%s]|r",
                        info.key or "?", info.name or "?", vis))
                else
                    Ui.blueprintInfoText:SetText(string.format(
                        "%s «%s» — %d GO [%s]",
                        info.key or "?", info.name or "?", n, vis))
                end
            end
            RefreshBlueprintManagerMembers(info)
            if Ui.refreshBlueprintActions then
                Ui.refreshBlueprintActions()
            end
            SetStatus("Состав шаблона обновлён.", "info")
        end)
        Packets.On("blueprint_status", function(status)
            -- BuildStatus already returns RU lines — show as-is.
            SetStatus((status and status.line) or "Нет задачи", "info")
        end)
        Packets.On("blueprint_result", function(result)
            if not result then
                return
            end
            if result.status == "error" then
                SetStatus(string.format("%s: %s", result.verb or "шаблон", result.detail or "ошибка"), "error")
                return
            end
            local detail = result.detail or ""
            local verb = result.verb or ""
            if verb == "new" then
                SetStatus("Шаблон сохранён: " .. detail, "info")
            elseif verb == "update" then
                SetStatus("Шаблон перезаписан: " .. detail, "info")
            elseif verb == "spawn" then
                if result.status == "queued" then
                    SetStatus("Ставим шаблон у ваших ног…", "warning")
                else
                    local keyOrName, root = detail:match("^([^:]+):(%d+)$")
                    if root then
                        SetStatus(string.format(
                            "Поставлен «%s» как группа %s. Можно взять группу на вкладке Список.",
                            keyOrName or "?", root
                        ), "info")
                    else
                        SetStatus("Шаблон поставлен: " .. detail, "info")
                    end
                end
            elseif verb == "delete" then
                SetStatus("Шаблон удалён: " .. detail, "info")
                Ui.selectedBlueprint = nil
                Ui.blueprintInfo = nil
            elseif verb == "set-public" then
                SetStatus("Публичность шаблона обновлена.", "info")
            elseif verb:find("member", 1, true) then
                SetStatus("Состав шаблона изменён.", "info")
            else
                SetStatus(string.format("%s: готово — %s", verb ~= "" and verb or "шаблон", detail), "info")
            end
            if verb == "new" or verb == "update"
                or verb == "delete" or verb == "rename" or verb == "set-public" then
                RefreshBlueprintListCmd()
            end
            if verb == "set-public" or verb:find("member", 1, true) then
                ReloadBlueprintInfo()
            end
        end)
        Packets.On("info", function(info)
            UpdateInspectorLabels()
            if info and (not info.groupRoot or info.groupRoot == 0) then
                SetStatus("Объект не входит в группу.", "warning")
            else
                SetStatus("Данные объекта и активной группы обновлены.", "info")
            end
        end)
        Packets.On("status", function()
            UpdateStatusLabels()
            SetStatus("Состояние задачи обновлено.", "info")
        end)
        Packets.On("list", function()
            UpdateListRows()
            SetStatus("Список групп обновлён.", "info")
        end)
        Packets.On("near", function()
            UpdateNearRows()
            SetStatus("Ближайшие группы обновлены. Выберите строку.", "info")
        end)
        Packets.On("result", function(result)
            if not result then
                return
            end
            local st = result.status
            if st == "error" then
                SetStatus(string.format("%s: ошибка - %s",
                    VERB_LABELS[result.verb] or result.verb, result.detail or ""), "error")
                if result.verb == "create" then
                    PendingCreate = nil
                elseif result.verb == "use" then
                    PendingSelectionGuid = nil
                    Panel.ClearActiveGroup()
                end
                return
            end
            if st == "ok" or st == "queued" then
                if st == "ok" and result.verb == "near" then
                    SetStatus("Ближайшие группы загружены. Выберите строку.", "info")
                    return
                elseif st == "ok" and result.verb == "list" then
                    SetStatus("Список групп загружен. Выберите строку.", "info")
                    return
                end
                local message = st == "queued"
                    and string.format("%s: задача поставлена.", VERB_LABELS[result.verb] or result.verb)
                    or string.format("%s: готово.", VERB_LABELS[result.verb] or result.verb)
                SetStatus(message, st == "queued" and "warning" or "info")
                local verb = result.verb
                local objectGuid = ResolveObjectGuid()
                local groupGuid = ResolveGroupGuid()

                if verb == "delete" then
                    if Packets and Packets.State then
                        Packets.State.info = nil
                        Packets.State.status = nil
                    end
                    Panel.SetObjectGuid(nil)
                    Panel.ClearActiveGroup()
                    if Ui.groupLabel then Ui.groupLabel:SetText("Группа: удалена") end
                    if Ui.flagsLabel then Ui.flagsLabel:SetText("Изменения / задача: -") end
                    if Ui.memberList then Ui.memberList:SetRows({}) end
                    if Ui.updateAddPreview then Ui.updateAddPreview() end
                    C_Timer.After(0.15, function()
                        SendGroupCmd("list", {}, "gobgroup:refresh-list")
                    end)
                elseif verb == "cleanup" or verb == "reload" then
                    C_Timer.After(0.15, function()
                        SendGroupCmd("list", {}, "gobgroup:refresh-list")
                    end)
                elseif verb == "dissolve" then
                    Panel.ClearActiveGroup()
                    if Ui.updateAddPreview then Ui.updateAddPreview() end
                    if objectGuid then
                        C_Timer.After(0.15, function()
                            SendGroupCmd("info", { objectGuid = objectGuid, [1] = objectGuid }, "gobgroup:refresh-info")
                        end)
                    end
                elseif verb == "create" then
                    local created = PendingCreate
                    PendingCreate = nil
                    if created and created.root then
                        Panel.SetActiveGroup(created.root, { name = created.name })
                        Panel.SetObjectGuid(created.root)
                        Panel.ShowTab("inspect")
                        if Ui.updateAddPreview then Ui.updateAddPreview() end
                        C_Timer.After(0.15, function()
                            SendGroupCmd("info", { objectGuid = created.root, [1] = created.root }, "gobgroup:create-info")
                            SendGroupCmd("status", { groupGuid = created.root, [1] = created.root }, "gobgroup:create-status")
                            SendGroupCmd("list", {}, "gobgroup:create-list")
                        end)
                    end
                elseif verb == "add" or verb == "addnear" or
                       verb == "remove" or verb == "capture" or verb == "recalc" or
                       verb == "sync" or verb == "move" or verb == "turn" or verb == "relocate" then
                    if st == "queued" and groupGuid then
                        PollStatusUntilIdle(groupGuid, 1)
                    else
                        if objectGuid then
                            C_Timer.After(0.15, function()
                                SendGroupCmd("info", { objectGuid = objectGuid, [1] = objectGuid }, "gobgroup:refresh-info")
                            end)
                        end
                        if groupGuid then
                            C_Timer.After(0.25, function()
                                SendGroupCmd("status", { groupGuid = groupGuid, [1] = groupGuid }, "gobgroup:refresh-status")
                            end)
                        end
                    end
                end
            else
                SetStatus(string.format("%s: неизвестный результат %s", result.verb, st or "?"), "warning")
            end
        end)
    end

    ShowTab("inspect")
    ApplyAllCaps()
    return f
end
