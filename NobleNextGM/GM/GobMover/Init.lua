-- Loaded through the NobleNextGM private extension namespace.
-- GM/GobMover/Init.lua — редактирование GameObject (встроенная панель + модульные мини-окна в стиле Epsilon)

local _, ns = ...
local NNL = LibStub("NobleNextLib-1.0")

local AIO_HANDLER = "NN_GobMover"

local activeGuid = 0
local activeName = "?"
local activeServerPhaseId = 0
local activeEntry = nil
local editMode = "object" -- "object" | "group"

local stepValueText = "1"
local rotValueText = "15"
local scaleValueText = "1"
local entryValueText = ""
local searchValueText = ""

local Ui = {
    stepBoxes = {},
    rotBoxes = {},
    scaleBoxes = {},
    entryBoxes = {},
    searchBoxes = {},
    modeButtons = {},
    scaleLabels = {},
    targetLabels = {},
    subTargetLabels = {},
    historyRows = {},
    mineRows = {},
    historyMode = "recent", -- "recent" | "mine"
    selectedHistoryRow = nil,
}

local SyncTargetPresentation
local RefreshHistoryView
local SetGobIcon

local function PushRecentRecord(record)
    if type(record) ~= "table" then return end
    local guid = tonumber(record.guid) or 0
    local entry = tonumber(record.entry)
    if guid <= 0 and (not entry or entry <= 0) then
        return
    end
    local name = tostring(record.name or "")
    if name == "" or name == "?" then
        name = guid > 0 and ("GO #" .. tostring(guid)) or ("Entry #" .. tostring(entry))
    end
    for i = #Ui.historyRows, 1, -1 do
        local existing = Ui.historyRows[i]
        if (guid > 0 and existing.guid == guid) or (guid == 0 and entry and existing.guid == 0 and existing.entry == entry) then
            entry = entry or existing.entry
            if name:match("^GO #") and existing.name and not existing.name:match("^GO #") then
                name = existing.name
            end
            table.remove(Ui.historyRows, i)
        end
    end
    table.insert(Ui.historyRows, 1, {
        guid = guid,
        entry = entry,
        name = name,
        phaseId = tonumber(record.phaseId) or activeServerPhaseId or 0,
        kind = record.kind or (guid > 0 and "world" or "lookup"),
    })
    while #Ui.historyRows > 60 do
        table.remove(Ui.historyRows)
    end
    if RefreshHistoryView then
        RefreshHistoryView()
    end
end

_G.NobleNextGobMover = _G.NobleNextGobMover or _G.NobleNextGoMover or {}

function _G.NobleNextGobMover.SetTarget(guid, name, serverPhaseId, entry)
    activeGuid = tonumber(guid) or guid or 0
    activeName = name or "?"
    activeServerPhaseId = tonumber(serverPhaseId) or 0
    if entry ~= nil then
        activeEntry = tonumber(entry)
    elseif ns.SelectionContext and ns.SelectionContext.GetGo then
        local ctx = ns.SelectionContext.GetGo()
        if ctx and tonumber(ctx.guid) == activeGuid and ctx.entry then
            activeEntry = tonumber(ctx.entry)
        end
    end
    if _G.NobleNextGobMover._nameLabel then
        _G.NobleNextGobMover._nameLabel:SetText("Цель: " .. activeName
            .. " [GUID: " .. tostring(activeGuid) .. " | Фаза: " .. tostring(activeServerPhaseId) .. "]")
    end
    if tonumber(activeGuid) and tonumber(activeGuid) > 0 then
        PushRecentRecord({
            guid = tonumber(activeGuid),
            entry = activeEntry,
            name = activeName,
            phaseId = activeServerPhaseId,
            kind = "selected",
        })
    end
    if SyncTargetPresentation then
        SyncTargetPresentation()
    end
end

--- Alias for chat / GobGroup / external callers.
function _G.NobleNextGobMover.SelectGuid(guid, name, entry)
    return _G.NobleNextGobMover.SetTarget(guid, name, nil, entry)
end

function _G.NobleNextGobMover.GetTarget()
    return activeGuid, activeName, activeServerPhaseId, activeEntry
end

function _G.NobleNextGobMover.OnChatRecord(record)
    PushRecentRecord(record)
end

_G.NobleNextGoMover = _G.NobleNextGobMover

-- Incoming AIO handlers (SetTarget, MineList) live only in
-- NobleNextLua GM/GobMover/NNGobMoverClient.lua.

local function RequireTarget()
    if activeGuid == 0 then
        ns.PrintError("Сначала выберите объект кнопкой «Ближайший» или из списка личных объектов.")
        return false
    end
    return true
end

local function ParseBoxNumber(box)
    if not box or not box.GetText then return nil end
    return tonumber(((box:GetText() or ""):gsub(",", ".")))
end

local function SyncBoxGroup(list, text, skipBox)
    for _, box in ipairs(list) do
        if box ~= skipBox and box.GetText and box:GetText() ~= text then
            box._nnSyncing = true
            box:SetText(text)
            box._nnSyncing = false
        end
    end
end

local function BindSyncedBox(list, box, initialValue, onChanged)
    if not box then return end
    box:SetText(initialValue or "")
    table.insert(list, box)
    if box.HookScript then
        box:HookScript("OnTextChanged", function(self)
            if self._nnSyncing then return end
            local val = self:GetText() or ""
            onChanged(val, self)
        end)
    end
end

local function SetStepText(val, sourceBox)
    stepValueText = tostring(val or "1")
    SyncBoxGroup(Ui.stepBoxes, stepValueText, sourceBox)
end

local function SetRotText(val, sourceBox)
    rotValueText = tostring(val or "15")
    SyncBoxGroup(Ui.rotBoxes, rotValueText, sourceBox)
end

local function SetScaleText(val, sourceBox)
    scaleValueText = tostring(val or "1")
    SyncBoxGroup(Ui.scaleBoxes, scaleValueText, sourceBox)
end

local function SetEntryText(val, sourceBox)
    entryValueText = tostring(val or "")
    SyncBoxGroup(Ui.entryBoxes, entryValueText, sourceBox)
end

function _G.NobleNextGobMover.SelectTemplate(entry, name)
    entry = tonumber(entry)
    if not entry or entry <= 0 or entry > 4294967295 or entry ~= math.floor(entry) then return false end
    SetEntryText(tostring(entry))
    PushRecentRecord({ entry = entry, name = name, kind = "lookup" })
    return true
end

local function SetSearchText(value, sourceBox)
    searchValueText = tostring(value or "")
    SyncBoxGroup(Ui.searchBoxes, searchValueText, sourceBox)
end

local function RunGroupCommand(cmd)
    if ns.EnqueueCommand then
        ns.EnqueueCommand(cmd, { tag = "gobmover:group" })
    elseif ns.RunGmCommand then
        ns.RunGmCommand(cmd)
    else
        ns.PrintError("RunGmCommand / EnqueueCommand недоступен.")
    end
end

local function SendWorldCommand(cmd, tag)
    if not cmd or cmd == "" then return false end
    if ns.EnqueueCommand then
        ns.EnqueueCommand(cmd, { tag = tag or "gobmover:cmd" })
        return true
    elseif ns.RunGmCommand then
        return ns.RunGmCommand(cmd)
    end
    ns.PrintError("RunGmCommand недоступен.")
    return false
end

--- Object mode -> AIO; Group mode -> `.gobject group nudge|rotate|scale` (server-side).
local function CallEdit(objectMethod, groupBuilder, ...)
    if not RequireTarget() then return end
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if not (objectMethod == "Nudge" and i == 1) then
            if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
                ns.PrintError("Введите число. Для дробной части можно использовать точку или запятую.")
                return
            end
            if objectMethod == "Scale" and value <= 0 then
                ns.PrintError("Масштаб должен быть больше нуля.")
                return
            end
        end
    end
    if editMode == "object" then
        ns.AIOHandle(AIO_HANDLER, objectMethod, activeGuid, ...)
        return
    end
    local cmd = groupBuilder(activeGuid, ...)
    if not cmd or cmd == "" then
        ns.PrintError("Group mode: команда не собрана.")
        return
    end
    RunGroupCommand(cmd)
end

local function TargetNearestGo()
    if ns.RunGmCommand then
        ns.RunGmCommand("gobject target")
    else
        ns.PrintError("RunGmCommand недоступен.")
    end
end

local function PickNearbyGo()
    return ns.GobObjectSearch.OpenNearby()
end

local function ResolveDesiredEntry(box)
    local raw = box and box.GetText and box:GetText() or entryValueText or ""
    raw = tostring(raw):match("^%s*(.-)%s*$") or ""
    local num = tonumber(raw)
    if num and num > 0 and num == math.floor(num) then
        return num
    end
    if activeEntry and activeEntry > 0 then
        return activeEntry
    end
    if ns.SelectionContext and ns.SelectionContext.GetGo then
        local go = ns.SelectionContext.GetGo()
        if go and tonumber(go.entry) and tonumber(go.entry) > 0 then
            return tonumber(go.entry)
        end
    end
    return nil
end

local function SpawnEntryGo(box, isTemp)
    local entry = ResolveDesiredEntry(box)
    if not entry then
        ns.PrintError("Укажите числовой Entry объекта для спавна или выберите GO с известным Entry.")
        return
    end
    if isTemp then
        SendWorldCommand("gobject add temp " .. tostring(entry), "gobmover:addtemp")
    else
        SendWorldCommand("gobject add " .. tostring(entry), "gobmover:add")
    end
end

local function ReplaceTargetEntry(box)
    if not RequireTarget() then return end
    local raw = box and box.GetText and box:GetText() or entryValueText or ""
    local entry = tonumber((tostring(raw):match("^%s*(.-)%s*$")))
    if not entry or entry <= 0 or entry ~= math.floor(entry) then
        ns.PrintError("Для замены укажите новый числовой Entry в поле Entry.")
        return
    end
    SendWorldCommand(string.format("gobject replace %s %d", tostring(activeGuid), entry), "gobmover:replace")
end

local function LookupObjectsByQuery(box)
    local raw = box and box.GetText and box:GetText() or entryValueText or ""
    raw = tostring(raw):match("^%s*(.-)%s*$") or ""
    return ns.GobObjectSearch.Open(raw)
end

local function ConfirmDeleteGuid(guid, name)
    guid = tonumber(guid) or activeGuid
    if not guid or guid <= 0 then
        ns.PrintError("Сначала выберите объект для удаления.")
        return
    end
    StaticPopupDialogs["NOBLENEXT_GOBMOVER_DELETE"] = {
        text = string.format("Удалить GameObject %s [GUID %s] из мира и БД?", tostring(name or activeName or "?"), tostring(guid)),
        button1 = DELETE or YES,
        button2 = CANCEL or NO,
        OnAccept = function()
            SendWorldCommand("gobject delete " .. tostring(guid), "gobmover:delete")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("NOBLENEXT_GOBMOVER_DELETE")
end

local function OpenInGobGroup()
    if not RequireTarget() then return end
    if ns.GobGroupPanel and ns.GobGroupPanel.SetObjectGuid then
        ns.GobGroupPanel.SetObjectGuid(activeGuid)
    end
    if ns.ShowModule then
        ns.ShowModule("GobGroup")
    end
end

local function SetEditMode(mode)
    editMode = (mode == "group") and "group" or "object"
    for _, pair in ipairs(Ui.modeButtons) do
        if pair.objectBtn and pair.objectBtn.SetActiveState then
            pair.objectBtn:SetActiveState(editMode == "object")
        end
        if pair.groupBtn and pair.groupBtn.SetActiveState then
            pair.groupBtn:SetActiveState(editMode == "group")
        end
        if pair.toggleBtn then
            pair.toggleBtn:SetText(editMode == "group" and "Режим: Группа" or "Режим: Объект")
            SetGobIcon(pair.toggleBtn, editMode == "group" and "Group" or "Object",
                editMode == "group" and "Режим: группа" or "Режим: объект", 28,
                "Переключить редактирование одиночного объекта или всей группы.")
            if pair.toggleBtn.SetActiveState then
                pair.toggleBtn:SetActiveState(true)
            end
        end
        if pair.hint then
            if editMode == "object" then
                pair.hint:SetText("Двигается выбранный объект относительно взгляда персонажа. Масштаб задаётся целиком.")
            else
                pair.hint:SetText("Двигается вся группа объекта (.gob group). Масштаб умножается (1.1 = +10%).")
            end
        end
    end
    for _, lbl in ipairs(Ui.scaleLabels) do
        lbl:SetText(editMode == "group" and "Множитель:" or "Размер:")
    end
    if SyncTargetPresentation then
        SyncTargetPresentation()
    end
end

SyncTargetPresentation = function()
    local hasTarget = tonumber(activeGuid) and tonumber(activeGuid) > 0
    local shortTitle = hasTarget
        and string.format("%s", tostring(activeName or "?"))
        or "Цель не выбрана"
    local subInfo = hasTarget
        and string.format("GUID: %s%s  |  Фаза: %s  |  %s",
            tostring(activeGuid),
            activeEntry and ("  |  Entry: " .. tostring(activeEntry)) or "",
            tostring(activeServerPhaseId or 0),
            editMode == "group" and "ГРУППА" or "ОБЪЕКТ")
        or "Нажмите «Ближайший», «Радар» или выберите строку в истории / чате."

    for _, lbl in ipairs(Ui.targetLabels) do
        lbl:SetText(shortTitle)
    end
    for _, lbl in ipairs(Ui.subTargetLabels) do
        lbl:SetText(subInfo)
    end
end

local function TriggerNudge(dir, stepBox)
    CallEdit("Nudge", function(guid, d, step)
        return string.format("gobject group nudge %s %s %s", tostring(guid), d, tostring(step))
    end, dir, ParseBoxNumber(stepBox))
end

local function TriggerYaw(sign, rotBox)
    local step = ParseBoxNumber(rotBox)
    CallEdit("RotateYaw", function(guid, deg)
        return string.format("gobject group rotate %s %s", tostring(guid), tostring(deg))
    end, step and (sign * step))
end

local function TriggerTilt(dPitchSign, dRollSign, rotBox)
    local step = ParseBoxNumber(rotBox)
    local pitch = (dPitchSign ~= 0) and (step and (dPitchSign * step)) or 0
    local roll = (dRollSign ~= 0) and (step and (dRollSign * step)) or 0
    CallEdit("Tilt", function(guid, p, r)
        return string.format("gobject group rotate %s 0 %s %s", tostring(guid), tostring(p), tostring(r))
    end, pitch, roll)
end

local function TriggerScale(scaleBox)
    CallEdit("Scale", function(guid, factor)
        return string.format("gobject group scale %s %s", tostring(guid), tostring(factor))
    end, ParseBoxNumber(scaleBox))
end

local function TriggerResetRotation()
    if not RequireTarget() then return end
    if editMode ~= "object" then
        ns.PrintError("Сброс поворота доступен только в режиме «Объект».")
        return
    end
    ns.AIOHandle(AIO_HANDLER, "ResetRotation", activeGuid)
end

local directionIcons = {
    F = "Forward", B = "Backward", L = "Left", R = "Right",
    FL = "ForwardLeft", FR = "ForwardRight", BL = "BackLeft", BR = "BackRight",
}
local directionHints = {
    F = "От себя", B = "К себе", L = "Влево", R = "Вправо",
    FL = "От себя влево", FR = "От себя вправо", BL = "К себе влево", BR = "К себе вправо",
}

local gobIcons = {
    Nearest = "Select", ReadEntry = "Inspect", Object = "Settings", Group = "ObjectGroup",
}
SetGobIcon = function(button, icon, title, size, detail)
    NNL.Widgets.SetActionIcon(button, gobIcons[icon] or icon, { title = title, size = size or 32, detail = detail })
end

local function CreateScaleIcon(parent, scaleBox, direction, size)
    local title = direction > 0 and "Масштаб +" or "Масштаб -"
    local button = NNL.Widgets.CreateButton(parent, { text = title })
    SetGobIcon(button, direction > 0 and "ScaleUp" or "ScaleDown", title, size,
        "Изменить поле размера на 0.1. Для применения нажмите «Применить».")
    button:SetScript("OnClick", function()
        local value = ParseBoxNumber(scaleBox)
        if not value or value <= 0 then return end
        SetScaleText(string.format("%.2f", math.max(0.01, value + direction * 0.1)))
    end)
    return button
end

local function MakeGobBtn(parent, text, width, height, style, onClick, tooltip)
    local btn = NNL.Widgets.CreateButton(parent, {
        text = text,
        width = width or 90,
        height = height or 22,
        style = style,
        tooltip = tooltip,
        onClick = onClick,
    })
    if onClick and btn and btn.SetScript then
        btn:SetScript("OnClick", onClick)
    end
    return btn
end

local function BuildPresetChips(parent, presets, x, y, chipW, chipH, onSelect)
    local prev, buttons = nil, {}
    for _, item in ipairs(presets) do
        local label = type(item) == "table" and item[1] or tostring(item)
        local val = type(item) == "table" and item[2] or tostring(item)
        local btn = MakeGobBtn(parent, label, chipW or 36, chipH or 20, "ghost", function()
            onSelect(val)
        end)
        if not prev then
            btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        else
            btn:SetPoint("LEFT", prev, "RIGHT", 3, 0)
        end
        prev = btn
        buttons[#buttons + 1] = btn
    end
    return buttons
end

-- ---------------------------------------------------------------------------
-- Epsilon-style Floating Mini-Windows Suite (Lazy Creation)
-- ---------------------------------------------------------------------------
local MiniSuite = {
    toolbox = nil,
    inspector = nil,
    search = nil,
    history = nil,
}

-- Reuse the common row layout: narrow palettes wrap instead of clipping.
local function MiniRow(parent, controls, y, inset)
    inset = inset or 8
    for _, control in ipairs(controls) do control:SetHeight(control.actionIconSize or 22) end
    return -NNL.Layout.PlaceRow(controls, parent, inset, -y, 4, parent:GetWidth() - inset, "center") + 6
end

local function FitMiniSections(win, sections, footer)
    local body = win:GetContent()
    local lastWidth, arranging
    function win:Relayout()
        local width = body:GetWidth()
        if arranging or width <= 0 or width == lastWidth then return end
        arranging, lastWidth = true, width
        local y = 6
        for _, section in ipairs(sections) do
            local frame = section.frame
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", body, "TOPLEFT", 6, -y)
            frame:SetPoint("TOPRIGHT", body, "TOPRIGHT", -6, -y)
            if section.layout then frame:SetHeight(section.layout(frame)) end
            y = y + frame:GetHeight() + 6
        end
        if footer then y = MiniRow(body, footer, y, 6) end
        self:SetContentHeight(y)
        arranging = false
    end
    body:HookScript("OnSizeChanged", function() win:Relayout() end)
    win:Relayout()
end

RefreshHistoryView = function()
    if not MiniSuite.history or not MiniSuite.history.list then
        return
    end
    local rows = (Ui.historyMode == "mine") and Ui.mineRows or Ui.historyRows
    local filter = ""
    if MiniSuite.history.filterBox and MiniSuite.history.filterBox.GetText then
        filter = (MiniSuite.history.filterBox:GetText() or ""):lower():match("^%s*(.-)%s*$") or ""
    end
    local out = {}
    for _, row in ipairs(rows or {}) do
        local name = tostring(row.name or "?")
        local guidStr = tostring(row.guid or 0)
        local entryStr = tostring(row.entry or "")
        if filter == ""
            or name:lower():find(filter, 1, true)
            or guidStr:find(filter, 1, true)
            or entryStr:find(filter, 1, true)
        then
            out[#out + 1] = row
        end
    end
    MiniSuite.history.list:SetRows(out)
    if MiniSuite.history.emptyText then
        if #out == 0 then
            MiniSuite.history.emptyText:SetText(
                Ui.historyMode == "mine"
                    and "Личных объектов не найдено. Нажмите «Мои БД» для запроса с сервера."
                    or "История пуста. Нажмите «Рядом», «.lo ob» или выберите объект в мире."
            )
            MiniSuite.history.emptyText:Show()
        else
            MiniSuite.history.emptyText:Hide()
        end
    end
    if MiniSuite.history.modeRecentBtn and MiniSuite.history.modeRecentBtn.SetActiveState then
        MiniSuite.history.modeRecentBtn:SetActiveState(Ui.historyMode == "recent")
    end
    if MiniSuite.history.modeMineBtn and MiniSuite.history.modeMineBtn.SetActiveState then
        MiniSuite.history.modeMineBtn:SetActiveState(Ui.historyMode == "mine")
    end
end

local function EnsureMiniInspector()
    if MiniSuite.inspector then
        return MiniSuite.inspector
    end
    if not NNL.Window or not NNL.Window.CreateMini then
        return nil
    end

    local win = NNL.Window.CreateMini({
        name = "NobleNextGobMiniInspector",
        title = "Инспектор и спавн GO",
        icon = "Interface\\Icons\\inv_misc_enggizmos_swissarmy",
        width = 300,
        height = 318,
        strata = "HIGH",
    })
    local body = win:GetContent()

    local infoCard = NNL.Widgets.CreateSection(body, { height = 64, divider = false })
    infoCard:SetPoint("TOPLEFT", body, "TOPLEFT", 6, -6)
    infoCard:SetPoint("TOPRIGHT", body, "TOPRIGHT", -6, -6)
    NNL.Theme.Apply(infoCard, "card")

    local nameLbl = infoCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLbl:SetPoint("TOPLEFT", infoCard, "TOPLEFT", 8, -7)
    nameLbl:SetPoint("TOPRIGHT", infoCard, "TOPRIGHT", -8, -7)
    nameLbl:SetJustifyH("LEFT")
    nameLbl:SetHeight(14)
    if nameLbl.SetWordWrap then nameLbl:SetWordWrap(false) end
    nameLbl:SetTextColor(1, 0.82, 0)
    table.insert(Ui.targetLabels, nameLbl)

    local subLbl = infoCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subLbl:SetPoint("TOPLEFT", infoCard, "TOPLEFT", 8, -25)
    subLbl:SetPoint("TOPRIGHT", infoCard, "TOPRIGHT", -8, -25)
    subLbl:SetHeight(28)
    subLbl:SetJustifyH("LEFT")
    if subLbl.SetWordWrap then subLbl:SetWordWrap(true) end
    subLbl:SetTextColor(0.75, 0.78, 0.84)
    table.insert(Ui.subTargetLabels, subLbl)

    -- Scale Card
    local scaleSec = NNL.Widgets.CreateSection(body, { title = "Масштаб", height = 78 })
    scaleSec:SetPoint("TOPLEFT", infoCard, "BOTTOMLEFT", 0, -6)
    scaleSec:SetPoint("TOPRIGHT", infoCard, "BOTTOMRIGHT", 0, -6)

    local scLbl = ns.CreateNGLabel(scaleSec, "Размер:")
    scLbl:SetSize(72, 20)
    scLbl:SetPoint("TOPLEFT", scaleSec, "TOPLEFT", 8, -32)
    table.insert(Ui.scaleLabels, scLbl)

    local scBox = ns.CreateNGEditBox(scaleSec, "GobMover_MiniScale", 58, 20)
    scBox:SetPoint("LEFT", scLbl, "RIGHT", 6, 0)
    BindSyncedBox(Ui.scaleBoxes, scBox, scaleValueText, SetScaleText)

    local scBtn = MakeGobBtn(scaleSec, "Применить", 88, 20, "primary", function()
        TriggerScale(scBox)
    end)
    scBtn:SetPoint("LEFT", scBox, "RIGHT", 6, 0)
    SetGobIcon(scBtn, "Apply", "Применить масштаб", 36, "Применить указанное значение к объекту или группе.")

    local scaleDown = CreateScaleIcon(scaleSec, scBox, -1, 36)
    local scaleUp = CreateScaleIcon(scaleSec, scBox, 1, 36)

    local scaleChips = BuildPresetChips(scaleSec, { "0.5", "0.75", "1", "1.25", "1.5", "2" }, 8, -54, 38, 20, function(v)
        SetScaleText(v)
    end)

    -- Spawn & Replace Card
    local spawnSec = NNL.Widgets.CreateSection(body, { title = "Спавн и замена (Entry)", height = 76 })
    spawnSec:SetPoint("TOPLEFT", scaleSec, "BOTTOMLEFT", 0, -6)
    spawnSec:SetPoint("TOPRIGHT", scaleSec, "BOTTOMRIGHT", 0, -6)

    local enLbl = ns.CreateNGLabel(spawnSec, "Entry:")
    enLbl:SetSize(40, 20)
    enLbl:SetPoint("TOPLEFT", spawnSec, "TOPLEFT", 8, -30)
    local enBox = ns.CreateNGEditBox(spawnSec, "GobMover_MiniEntry", 76, 20)
    enBox:SetPoint("LEFT", enLbl, "RIGHT", 6, 0)
    BindSyncedBox(Ui.entryBoxes, enBox, entryValueText, SetEntryText)

    local fillActiveBtn = MakeGobBtn(spawnSec, "Из цели", 62, 20, "ghost", function()
        local e = ResolveDesiredEntry(nil)
        if e then
            SetEntryText(tostring(e))
        else
            ns.PrintError("У текущей цели Entry не определён. Нажмите «Инфо» (.gob check).")
        end
    end, "Взять Entry текущего выбранного объекта")
    fillActiveBtn:SetPoint("LEFT", enBox, "RIGHT", 4, 0)

    local spBtn = MakeGobBtn(spawnSec, "Спавн", 60, 20, "primary", function()
        SpawnEntryGo(enBox, false)
    end, "Создать постоянный объект (.gobject add)")
    spBtn:SetPoint("TOPLEFT", spawnSec, "TOPLEFT", 8, -52)

    local tmpBtn = MakeGobBtn(spawnSec, "Врем.", 52, 20, nil, function()
        SpawnEntryGo(enBox, true)
    end, "Временный спавн на 5 мин (.gobject add temp)")
    tmpBtn:SetPoint("LEFT", spBtn, "RIGHT", 4, 0)

    local dupBtn = MakeGobBtn(spawnSec, "Дубль", 54, 20, nil, function()
        SpawnEntryGo(nil, false)
    end, "Создать копию выбранного GO (.gobject add <activeEntry>)")
    dupBtn:SetPoint("LEFT", tmpBtn, "RIGHT", 4, 0)

    local repBtn = MakeGobBtn(spawnSec, "Заменить", 68, 20, nil, function()
        ReplaceTargetEntry(enBox)
    end, "Заменить модель/Entry выбранного объекта с сохранением GUID и позы (.gobject replace)")
    repBtn:SetPoint("LEFT", dupBtn, "RIGHT", 4, 0)

    -- Quick World Operations
    local actSec = NNL.Widgets.CreateSection(body, { title = "Операции в мире", height = 74 })
    actSec:SetPoint("TOPLEFT", spawnSec, "BOTTOMLEFT", 0, -6)
    actSec:SetPoint("TOPRIGHT", spawnSec, "BOTTOMRIGHT", 0, -6)

    local goToBtn = MakeGobBtn(actSec, "Тп к GO", 76, 20, nil, function()
        if RequireTarget() then SendWorldCommand("go gameobject " .. tostring(activeGuid), "gobmover:go") end
    end)
    goToBtn:SetPoint("TOPLEFT", actSec, "TOPLEFT", 8, -28)

    local pullBtn = MakeGobBtn(actSec, "К себе", 76, 20, nil, function()
        if RequireTarget() then SendWorldCommand("gobject move " .. tostring(activeGuid), "gobmover:movehere") end
    end, "Переместить выбранный объект в координаты персонажа (.gobject move)")
    pullBtn:SetPoint("LEFT", goToBtn, "RIGHT", 4, 0)

    local useBtn = MakeGobBtn(actSec, "Актив.", 80, 20, nil, function()
        if RequireTarget() then SendWorldCommand("gobject activate " .. tostring(activeGuid), "gobmover:activate") end
    end, "Активировать дверь/объект (.gobject activate)")
    useBtn:SetPoint("LEFT", pullBtn, "RIGHT", 4, 0)

    local chkBtn = MakeGobBtn(actSec, "Инфо", 76, 20, nil, function()
        if RequireTarget() then SendWorldCommand("gobject check " .. tostring(activeGuid), "gobmover:check") end
    end, "Подробности объекта в чат (.gobject check)")
    chkBtn:SetPoint("TOPLEFT", actSec, "TOPLEFT", 8, -50)

    local grpBtn = MakeGobBtn(actSec, "В группу", 76, 20, nil, OpenInGobGroup)
    grpBtn:SetPoint("LEFT", chkBtn, "RIGHT", 4, 0)

    local delBtn = MakeGobBtn(actSec, "Удалить", 80, 20, "danger", function()
        ConfirmDeleteGuid(activeGuid, activeName)
    end)
    delBtn:SetPoint("LEFT", grpBtn, "RIGHT", 4, 0)

    SetGobIcon(fillActiveBtn, "ReadEntry", "Взять Entry выбранного объекта", 28)
    SetGobIcon(dupBtn, "Duplicate", "Дублировать выбранный объект", 40)
    SetGobIcon(repBtn, "Replace", "Заменить Entry выбранного объекта", 40, "Сохраняет GUID и положение объекта.")
    SetGobIcon(spBtn, "Spawn", "Создать постоянный объект", 40)
    SetGobIcon(tmpBtn, "SpawnTemporary", "Создать временный объект", 40, "Для сохранения после перезапуска объект нужно запечь.")
    SetGobIcon(goToBtn, "Teleport", "Телепортироваться к объекту", 40)
    SetGobIcon(pullBtn, "Pull", "Перенести объект к персонажу", 40)
    SetGobIcon(useBtn, "Activate", "Активировать объект", 40)
    SetGobIcon(chkBtn, "Info", "Информация об объекте в чат", 40)
    SetGobIcon(grpBtn, "Group", "Добавить объект в группу", 40)
    SetGobIcon(delBtn, "Delete", "Удалить объект", 40, "Потребуется подтверждение.")

    local lookupBtn = MakeGobBtn(spawnSec, "Поиск шаблонов", 40, 40, nil, function()
        ns.GobObjectSearch.Open(searchValueText)
    end)
    SetGobIcon(lookupBtn, "Search", "Поиск шаблонов по названию", 40,
        "Найти шаблон для установки. Выбор заполняет поле Entry.")
    local radarBtn = MakeGobBtn(spawnSec, "Радар объектов", 40, 40, nil, PickNearbyGo)
    SetGobIcon(radarBtn, "Radar", "Радар объектов рядом", 40,
        "Объекты текущей фазы в радиусе 50 метров. Выбор меняет текущую цель.")
    local lookupLabel = ns.CreateNGLabel(spawnSec, "Поиск")
    lookupLabel:SetPoint("TOP", lookupBtn, "BOTTOM", 0, -1)
    local radarLabel = ns.CreateNGLabel(spawnSec, "Радар")
    radarLabel:SetPoint("TOP", radarBtn, "BOTTOM", 0, -1)

    FitMiniSections(win, {
        {frame = infoCard},
        {frame = scaleSec, layout = function(section)
            local y = MiniRow(section, {scLbl, scBox, scaleDown, scaleUp, scBtn}, 32)
            return MiniRow(section, scaleChips, y) + 2
        end},
        {frame = spawnSec, layout = function(section)
            local y = MiniRow(section, {enLbl, enBox, fillActiveBtn}, 32)
            return MiniRow(section, {spBtn, tmpBtn, dupBtn, repBtn, lookupBtn, radarBtn}, y) + 18
        end},
        {frame = actSec, layout = function(section)
            return MiniRow(section, {goToBtn, pullBtn, useBtn, chkBtn, grpBtn, delBtn}, 32) + 2
        end},
    })

    MiniSuite.inspector = win
    SyncTargetPresentation()
    return win
end

local function EnsureMiniSearch()
    if MiniSuite.search then return MiniSuite.search end
    if not NNL.Window or not NNL.Window.CreateMini then return nil end
    local win = NNL.Window.CreateMini({
        name = "NobleNextGobMiniSearch", title = "Поиск объектов",
        icon = "Interface\\Icons\\inv_misc_spyglass_03",
        width = 300, height = 120, strata = "HIGH", closeOnEscape = true,
    })
    local section = NNL.Widgets.CreateSection(win:GetContent(), { title = "Название объекта" })
    local searchBox = ns.CreateNGEditBox(section, "GobMover_MiniSearch", 180, 22)
    BindSyncedBox(Ui.searchBoxes, searchBox, searchValueText, SetSearchText)
    local searchButton = MakeGobBtn(section, "Поиск объектов", 32, 32, nil, function()
        LookupObjectsByQuery(searchBox)
    end)
    SetGobIcon(searchButton, "Search", "Поиск объектов по названию", 32)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); LookupObjectsByQuery(self) end)
    local radarButton = MakeGobBtn(section, "Радар рядом", 32, 32, nil, PickNearbyGo)
    SetGobIcon(radarButton, "Radar", "Радар ближайших объектов", 32, "Объекты текущей фазы в радиусе 50 метров.")
    FitMiniSections(win, {
        { frame = section, layout = function(frame)
            return MiniRow(frame, {searchBox, searchButton, radarButton}, 32) + 2
        end },
    })
    MiniSuite.search = win
    return win
end

local function EnsureMiniHistory()
    if MiniSuite.history then
        return MiniSuite.history
    end
    if not NNL.Window or not NNL.Window.CreateMini then
        return nil
    end

    local win = NNL.Window.CreateMini({
        name = "NobleNextGobMiniHistory",
        title = "История и поиск GO",
        icon = "Interface\\Icons\\inv_misc_spyglass_03",
        width = 352,
        height = 296,
        strata = "HIGH",
    })
    local body = win:GetContent()

    local toolbar = CreateFrame("Frame", nil, body)
    local filterBox = ns.CreateNGEditBox(toolbar, "GobMover_MiniFilter", 136, 20)
    filterBox:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 6, -6)
    win.filterBox = filterBox
    filterBox:SetScript("OnTextChanged", function()
        RefreshHistoryView()
    end)
    filterBox:SetScript("OnEnterPressed", function(self)
        LookupObjectsByQuery(self)
        self:ClearFocus()
    end)

    local loBtn = MakeGobBtn(toolbar, "Найти", 50, 20, "primary", function()
        LookupObjectsByQuery(filterBox)
    end, "Открыть поиск объектов по всем словам названия — результаты появятся в отдельном окне")
    loBtn:SetPoint("LEFT", filterBox, "RIGHT", 4, 0)

    local nearBtn = MakeGobBtn(toolbar, "Рядом", 54, 20, nil, function()
        Ui.historyMode = "recent"
        SendWorldCommand("gobject near 25", "gobmover:near")
        RefreshHistoryView()
    end, "Показать объекты в радиусе 25 ярдов (.gobject near 25)")
    nearBtn:SetPoint("LEFT", loBtn, "RIGHT", 4, 0)

    local mineFetchBtn = MakeGobBtn(toolbar, "Мои БД", 56, 20, nil, function()
        Ui.historyMode = "mine"
        ns.AIOHandle(AIO_HANDLER, "GetMineList", false, 0, 200)
        RefreshHistoryView()
    end, "Загрузить список ваших объектов из БД (AIO GetMineList)")
    mineFetchBtn:SetPoint("LEFT", nearBtn, "RIGHT", 4, 0)

    local modeRecentBtn = MakeGobBtn(toolbar, "Недавние / Чат", 148, 20, nil, function()
        Ui.historyMode = "recent"
        RefreshHistoryView()
    end)
    modeRecentBtn:SetPoint("TOPLEFT", filterBox, "BOTTOMLEFT", 0, -4)
    win.modeRecentBtn = modeRecentBtn

    local modeMineBtn = MakeGobBtn(toolbar, "Мои объекты", 148, 20, nil, function()
        Ui.historyMode = "mine"
        if #Ui.mineRows == 0 then
            ns.AIOHandle(AIO_HANDLER, "GetMineList", false, 0, 200)
        end
        RefreshHistoryView()
    end)
    modeMineBtn:SetPoint("LEFT", modeRecentBtn, "RIGHT", 4, 0)
    win.modeMineBtn = modeMineBtn

    local listHost = CreateFrame("Frame", nil, body, "BackdropTemplate")
    listHost:SetHeight(176)
    listHost:SetPoint("TOPLEFT", modeRecentBtn, "BOTTOMLEFT", 0, -4)
    listHost:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -6, 30)
    NNL.Theme.Apply(listHost, "section")

    local scroll = NNL.Scroll.CreateFrame(listHost)
    scroll:SetPoint("TOPLEFT", listHost, "TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", listHost, "BOTTOMRIGHT", -22, 4)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(276, 180)
    scroll:SetScrollChild(child)

    local emptyText = listHost:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyText:SetPoint("TOPLEFT", listHost, "TOPLEFT", 10, -14)
    emptyText:SetPoint("RIGHT", listHost, "RIGHT", -24, 0)
    emptyText:SetJustifyH("LEFT")
    if emptyText.SetWordWrap then emptyText:SetWordWrap(true) end
    win.emptyText = emptyText

    win.list = ns.VirtualList.Create(child, {
        width = 272,
        rowHeight = 24,
        visibleCount = 7,
        scrollFrame = scroll,
        onClick = function(row)
            if not row then return end
            Ui.selectedHistoryRow = row
            if row.entry and tonumber(row.entry) and tonumber(row.entry) > 0 then
                SetEntryText(tostring(row.entry))
            end
            if row.guid and tonumber(row.guid) and tonumber(row.guid) > 0 then
                _G.NobleNextGobMover.SetTarget(row.guid, row.name, row.phaseId, row.entry)
                if ns.SelectionContext and ns.SelectionContext.SetGo then
                    ns.SelectionContext.SetGo(row.guid, row.entry, row.name)
                end
            end
            win.list:Refresh()
        end,
        renderRow = function(btn, row)
            local fs = btn.fs or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.fs = fs
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", btn, "LEFT", 6, 0)
            fs:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            fs:SetJustifyH("LEFT")
            if fs.SetWordWrap then fs:SetWordWrap(false) end

            local isSel = Ui.selectedHistoryRow == row or (row.guid and tonumber(row.guid) > 0 and tonumber(row.guid) == tonumber(activeGuid))
            local prefix = isSel and "|cffffd100* |r" or ""
            local guidTag = (row.guid and tonumber(row.guid) > 0) and string.format("|cff7fe39a[%s]|r", tostring(row.guid)) or "|cff66ccff[шаблон]|r"
            local entryTag = row.entry and string.format(" |cffaaaaaa#%s|r", tostring(row.entry)) or ""
            fs:SetText(string.format("%s%s %s%s", prefix, guidTag, tostring(row.name or "?"), entryTag))
        end,
    })

    -- Bottom action buttons (like EpsilonLibGobHistoryFrame)
    local selActionBtn = MakeGobBtn(body, "Выбрать", 70, 20, "primary", function()
        local r = Ui.selectedHistoryRow
        if not r or not r.guid or tonumber(r.guid) <= 0 then
            ns.PrintError("Выберите объект с GUID в списке.")
            return
        end
        SendWorldCommand("movego " .. tostring(r.guid), "gobmover:hist-sel")
    end)
    selActionBtn:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 6, 6)

    local gotoActionBtn = MakeGobBtn(body, "Тп к GO", 70, 20, nil, function()
        local r = Ui.selectedHistoryRow
        local guid = (r and tonumber(r.guid) and tonumber(r.guid) > 0 and tonumber(r.guid)) or activeGuid
        if not guid or guid <= 0 then
            ns.PrintError("Выберите объект с GUID.")
            return
        end
        SendWorldCommand("go gameobject " .. tostring(guid), "gobmover:hist-go")
    end)
    gotoActionBtn:SetPoint("LEFT", selActionBtn, "RIGHT", 4, 0)

    local spawnActionBtn = MakeGobBtn(body, "Спавн", 70, 20, nil, function()
        local r = Ui.selectedHistoryRow
        if r and r.entry and tonumber(r.entry) > 0 then
            SetEntryText(tostring(r.entry))
        end
        SpawnEntryGo(nil, false)
    end)
    spawnActionBtn:SetPoint("LEFT", gotoActionBtn, "RIGHT", 4, 0)

    local delActionBtn = MakeGobBtn(body, "Удалить", 74, 20, "danger", function()
        local r = Ui.selectedHistoryRow
        local guid = (r and tonumber(r.guid) and tonumber(r.guid) > 0 and tonumber(r.guid)) or activeGuid
        local name = (r and r.name) or activeName
        ConfirmDeleteGuid(guid, name)
    end)
    delActionBtn:SetPoint("LEFT", spawnActionBtn, "RIGHT", 4, 0)

    SetGobIcon(selActionBtn, "Select", "Выбрать объект из истории", 28)
    SetGobIcon(gotoActionBtn, "Teleport", "Телепортироваться к объекту из истории", 28)
    SetGobIcon(spawnActionBtn, "Spawn", "Создать постоянный объект из истории", 28)
    SetGobIcon(delActionBtn, "Delete", "Удалить объект из мира", 28, "Потребуется подтверждение.")

    FitMiniSections(win, {
        {frame = toolbar, layout = function(section)
            filterBox:SetWidth(math.max(100, section:GetWidth() - 188))
            local y = MiniRow(section, {filterBox, loBtn, nearBtn, mineFetchBtn}, 6)
            local tabWidth = math.floor((section:GetWidth() - 20) / 2)
            modeRecentBtn:SetWidth(tabWidth); modeMineBtn:SetWidth(tabWidth)
            return MiniRow(section, {modeRecentBtn, modeMineBtn}, y) + 2
        end},
        {frame = listHost, layout = function(section)
            child:SetWidth(section:GetWidth() - 30)
            if win.list.SetViewport then win.list:SetViewport(section:GetWidth() - 30, 168) end
            return 176
        end},
    }, {selActionBtn, gotoActionBtn, spawnActionBtn, delActionBtn})

    MiniSuite.history = win
    RefreshHistoryView()
    return win
end

local function EnsureMiniToolbox()
    if MiniSuite.toolbox then
        return MiniSuite.toolbox
    end
    if not NNL.Window or not NNL.Window.CreateMini then
        return nil
    end

    local win = NNL.Window.CreateMini({
        name = "NobleNextGobMiniToolbox",
        title = "Пульт маппера",
        icon = "Interface\\Icons\\garrison_building_workshop",
        width = 300,
        height = 352,
        strata = "HIGH",
        point = "RIGHT",
        relativePoint = "RIGHT",
        x = -320,
        y = 40,
        headerButtonText = "В окно",
        headerButtonWidth = 56,
        headerButtonTooltip = "Вернуться в полное окно NobleNext",
        onHeaderButton = function()
            if ns.DockModule then
                ns.DockModule("gobmover")
            else
                _G.NobleNextGobMover.CloseMiniSuite()
                ns.ShowModule("Gob Mover")
            end
        end,
    })
    local body = win:GetContent()

    -- Target Header Strip
    local targetCard = NNL.Widgets.CreateSection(body, { height = 88, divider = false })
    targetCard:SetPoint("TOPLEFT", body, "TOPLEFT", 6, -6)
    targetCard:SetPoint("TOPRIGHT", body, "TOPRIGHT", -6, -6)
    NNL.Theme.Apply(targetCard, "card")

    local tgtName = targetCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tgtName:SetPoint("TOPLEFT", targetCard, "TOPLEFT", 8, -6)
    tgtName:SetPoint("TOPRIGHT", targetCard, "TOPRIGHT", -8, -6)
    tgtName:SetJustifyH("LEFT")
    tgtName:SetHeight(14)
    if tgtName.SetWordWrap then tgtName:SetWordWrap(false) end
    tgtName:SetTextColor(1, 0.82, 0)
    table.insert(Ui.targetLabels, tgtName)

    local tgtSub = targetCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tgtSub:SetPoint("TOPLEFT", targetCard, "TOPLEFT", 8, -24)
    tgtSub:SetPoint("TOPRIGHT", targetCard, "TOPRIGHT", -8, -24)
    tgtSub:SetHeight(28)
    tgtSub:SetJustifyH("LEFT")
    if tgtSub.SetWordWrap then tgtSub:SetWordWrap(true) end
    table.insert(Ui.subTargetLabels, tgtSub)

    local nearTargetBtn = MakeGobBtn(targetCard, "Ближайший", 84, 18, "primary", TargetNearestGo, "Выбрать ближайший объект (.gobject target)")
    nearTargetBtn:SetPoint("BOTTOMLEFT", targetCard, "BOTTOMLEFT", 6, 4)

    local pickBtn = MakeGobBtn(targetCard, "Радар", 58, 18, nil, PickNearbyGo, "Список ближайших объектов из БД (.gobject near 50)")
    pickBtn:SetPoint("LEFT", nearTargetBtn, "RIGHT", 4, 0)

    local modeToggleBtn = MakeGobBtn(targetCard, "Режим: Объект", 108, 18, nil, function()
        SetEditMode(editMode == "object" and "group" or "object")
    end, "Переключить: одиночный объект или вся группа (.gobject group)")
    modeToggleBtn:SetPoint("LEFT", pickBtn, "RIGHT", 4, 0)
    SetGobIcon(nearTargetBtn, "Nearest", "Выбрать ближайший объект", 28)
    SetGobIcon(pickBtn, "Radar", "Радар ближайших объектов", 28)
    SetGobIcon(modeToggleBtn, "Object", "Режим: объект", 28)
    table.insert(Ui.modeButtons, { toggleBtn = modeToggleBtn })

    -- Movement Section
    local moveSec = NNL.Widgets.CreateSection(body, { height = 136, divider = false })
    moveSec:SetPoint("TOPLEFT", targetCard, "BOTTOMLEFT", 0, -6)
    moveSec:SetPoint("TOPRIGHT", targetCard, "BOTTOMRIGHT", 0, -6)

    local stepLbl = ns.CreateNGLabel(moveSec, "Шаг:")
    stepLbl:SetSize(32, 20)
    stepLbl:SetPoint("TOPLEFT", moveSec, "TOPLEFT", 8, -10)
    local miniStepBox = ns.CreateNGEditBox(moveSec, "GobMover_MiniStep", 48, 20)
    miniStepBox:SetPoint("LEFT", stepLbl, "RIGHT", 4, 0)
    BindSyncedBox(Ui.stepBoxes, miniStepBox, stepValueText, SetStepText)

    local stepChips = BuildPresetChips(moveSec, { "0.05", "0.25", "1", "5" }, 104, -10, 36, 20, function(v)
        SetStepText(v)
    end)

    local dpadGrid = {
        { "FL", "F", "FR" },
        { "L",  "",  "R"  },
        { "BL", "B", "BR" },
    }
    local dpadShort = {
        FL = "СЗ", F = "Вперёд", FR = "СВ",
        L = "Влево", R = "Вправо",
        BL = "ЮЗ", B = "Назад", BR = "ЮВ",
    }
    local cellW, cellH, gap = 44, 44, 6
    local origX, origY = 8, -36
    local dpadButtons = {}
    for r = 1, 3 do
        dpadButtons[r] = {}
        for c = 1, 3 do
            local dir = dpadGrid[r][c]
            local x = origX + (c - 1) * (cellW + gap)
            local y = origY - (r - 1) * (cellH + gap)
            if dir ~= "" then
                local b = MakeGobBtn(moveSec, dpadShort[dir], cellW, cellH,
                    (dir == "F" or dir == "B" or dir == "L" or dir == "R") and "primary" or nil,
                    function() TriggerNudge(dir, miniStepBox) end)
                b:SetPoint("TOPLEFT", moveSec, "TOPLEFT", x, y)
                SetGobIcon(b, directionIcons[dir], directionHints[dir], cellH, "Переместить на заданный шаг относительно взгляда персонажа.")
                dpadButtons[r][c] = b
            else
                local centerBtn = MakeGobBtn(moveSec, "Цель", cellW, cellH, nil, TargetNearestGo, "Выбрать ближайший объект (.gobject target)")
                centerBtn:SetPoint("TOPLEFT", moveSec, "TOPLEFT", x, y)
                SetGobIcon(centerBtn, "Select", "Выбрать ближайший объект", cellH)
                dpadButtons[r][c] = centerBtn
            end
        end
    end

    local upBtn = MakeGobBtn(moveSec, "Вверх", 66, 38, "primary", function()
        TriggerNudge("UP", miniStepBox)
    end)
    upBtn:SetPoint("TOPLEFT", moveSec, "TOPLEFT", origX + 3 * (cellW + gap) + 6, origY)

    local downBtn = MakeGobBtn(moveSec, "Вниз", 66, 38, "primary", function()
        TriggerNudge("DOWN", miniStepBox)
    end)
    downBtn:SetPoint("TOPLEFT", upBtn, "BOTTOMLEFT", 0, -10)

    -- Rotation & Tilt Section
    local rotSec = NNL.Widgets.CreateSection(body, { height = 84, divider = false })
    rotSec:SetPoint("TOPLEFT", moveSec, "BOTTOMLEFT", 0, -6)
    rotSec:SetPoint("TOPRIGHT", moveSec, "BOTTOMRIGHT", 0, -6)

    local rotLbl = ns.CreateNGLabel(rotSec, "Угол:")
    rotLbl:SetSize(36, 20)
    rotLbl:SetPoint("TOPLEFT", rotSec, "TOPLEFT", 8, -10)
    local miniRotBox = ns.CreateNGEditBox(rotSec, "GobMover_MiniRotStep", 44, 20)
    miniRotBox:SetPoint("LEFT", rotLbl, "RIGHT", 4, 0)
    BindSyncedBox(Ui.rotBoxes, miniRotBox, rotValueText, SetRotText)

    local rotChips = BuildPresetChips(rotSec, { { "5°", "5" }, { "15°", "15" }, { "45°", "45" }, { "90°", "90" } }, 100, -10, 36, 20, function(v)
        SetRotText(v)
    end)

    local cwBtn = MakeGobBtn(rotSec, "По час.", 80, 20, "primary", function()
        TriggerYaw(-1, miniRotBox)
    end)
    cwBtn:SetPoint("TOPLEFT", rotSec, "TOPLEFT", 8, -34)

    local ccwBtn = MakeGobBtn(rotSec, "Пр. час.", 80, 20, "primary", function()
        TriggerYaw(1, miniRotBox)
    end)
    ccwBtn:SetPoint("LEFT", cwBtn, "RIGHT", 4, 0)

    local rstRotBtn = MakeGobBtn(rotSec, "Сброс 0°", 84, 20, "ghost", TriggerResetRotation)
    rstRotBtn:SetPoint("LEFT", ccwBtn, "RIGHT", 4, 0)

    local pUp = MakeGobBtn(rotSec, "Накл.+", 60, 20, nil, function() TriggerTilt(1, 0, miniRotBox) end)
    pUp:SetPoint("TOPLEFT", rotSec, "TOPLEFT", 8, -58)

    local pDn = MakeGobBtn(rotSec, "Накл.-", 60, 20, nil, function() TriggerTilt(-1, 0, miniRotBox) end)
    pDn:SetPoint("LEFT", pUp, "RIGHT", 4, 0)

    local rL = MakeGobBtn(rotSec, "Крен Л", 60, 20, nil, function() TriggerTilt(0, 1, miniRotBox) end)
    rL:SetPoint("LEFT", pDn, "RIGHT", 4, 0)

    local rR = MakeGobBtn(rotSec, "Крен П", 60, 20, nil, function() TriggerTilt(0, -1, miniRotBox) end)
    rR:SetPoint("LEFT", rL, "RIGHT", 4, 0)

    SetGobIcon(upBtn, "Up", "Поднять объект", cellH)
    SetGobIcon(downBtn, "Down", "Опустить объект", cellH)
    SetGobIcon(cwBtn, "Clockwise", "Повернуть по часовой стрелке", 44)
    SetGobIcon(ccwBtn, "Counterclockwise", "Повернуть против часовой стрелки", 44)
    SetGobIcon(rstRotBtn, "Reset", "Сбросить поворот", 44)
    SetGobIcon(pUp, "PitchUp", "Увеличить наклон", 44)
    SetGobIcon(pDn, "PitchDown", "Уменьшить наклон", 44)
    SetGobIcon(rL, "RollLeft", "Крен влево", 44)
    SetGobIcon(rR, "RollRight", "Крен вправо", 44)

    local pitchLabel = ns.CreateNGLabel(rotSec, "Наклон")
    local rollLabel = ns.CreateNGLabel(rotSec, "Крен")
    pitchLabel:SetSize(92, 18)
    rollLabel:SetSize(92, 18)

    -- Bottom Companion Windows Bar (like Epsilon Launcher / ObjectMover popouts)
    local openInspBtn = MakeGobBtn(body, "Инспектор", 78, 20, nil, function()
        _G.NobleNextGobMover.ToggleMiniInspector()
    end, "Показать/скрыть мини-окно инспектора, масштаба и спавна")
    openInspBtn:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 6, 6)

    local openHistBtn = MakeGobBtn(body, "История", 62, 20, nil, function()
        _G.NobleNextGobMover.ToggleMiniHistory()
    end, "Показать/скрыть мини-окно истории объектов и поиска .lo ob")
    local openSearchBtn = MakeGobBtn(body, "Поиск", 48, 20, nil, function()
        _G.NobleNextGobMover.ToggleMiniSearch()
    end, "Открыть или скрыть отдельное окно поиска и радара")
    openSearchBtn:SetPoint("LEFT", openInspBtn, "RIGHT", 4, 0)
    openHistBtn:SetPoint("LEFT", openSearchBtn, "RIGHT", 4, 0)

    local openGrpBtn = MakeGobBtn(body, "Группы", 64, 20, nil, function()
        if ns.PopoutModule then
            if activeGuid and activeGuid > 0 and ns.GobGroupPanel and ns.GobGroupPanel.SetObjectGuid then
                ns.GobGroupPanel.SetObjectGuid(activeGuid)
            end
            ns.PopoutModule("gobgroup")
        else
            OpenInGobGroup()
        end
    end, "Открыть управление группами объектов (GobGroup)")
    openGrpBtn:SetPoint("LEFT", openHistBtn, "RIGHT", 4, 0)

    FitMiniSections(win, {
        {frame = targetCard, layout = function(section)
            return MiniRow(section, {nearTargetBtn, pickBtn, modeToggleBtn}, 60, 6)
        end},
        {frame = moveSec, layout = function(section)
            local controls = {stepLbl, miniStepBox}
            for _, chip in ipairs(stepChips) do controls[#controls + 1] = chip end
            local y = MiniRow(section, controls, 10)
            local column = cellH
            local left = math.floor((section:GetWidth() - 4 * column - 3 * gap) / 2)
            for r, row in ipairs(dpadButtons) do
                for c, button in ipairs(row) do
                    button:SetSize(column, cellH)
                    button:ClearAllPoints()
                    button:SetPoint("TOPLEFT", section, "TOPLEFT", left + (c - 1) * (column + gap), -y - (r - 1) * (cellH + gap))
                end
            end
            local verticalHeight = cellH
            upBtn:SetSize(column, verticalHeight)
            downBtn:SetSize(column, verticalHeight)
            upBtn:ClearAllPoints(); downBtn:ClearAllPoints()
            upBtn:SetPoint("TOPLEFT", section, "TOPLEFT", left + 3 * (column + gap), -y)
            downBtn:SetPoint("TOPLEFT", upBtn, "BOTTOMLEFT", 0, -cellH - 2 * gap)
            return y + 3 * cellH + 2 * gap + 8
        end},
        {frame = rotSec, layout = function(section)
            local controls = {rotLbl, miniRotBox}
            for _, chip in ipairs(rotChips) do controls[#controls + 1] = chip end
            local y = MiniRow(section, controls, 10)
            y = MiniRow(section, {cwBtn, ccwBtn, rstRotBtn}, y)
            y = MiniRow(section, {pitchLabel, rollLabel}, y)
            return MiniRow(section, {pUp, pDn, rL, rR}, y) + 2
        end},
    }, {openInspBtn, openSearchBtn, openHistBtn, openGrpBtn})

    MiniSuite.toolbox = win
    SetEditMode(editMode)
    SyncTargetPresentation()
    return win
end

function _G.NobleNextGobMover.ToggleMiniInspector()
    if not ns.Access or not ns.Access.Allows(2) then
        ns.PrintError("Инструменты ГМ требуют подтверждённый уровень доступа 2+.")
        return false
    end
    local tb = EnsureMiniToolbox()
    local insp = EnsureMiniInspector()
    if not insp then return false end
    if insp:IsShown() then
        insp:Hide()
        return false
    end
    if tb then
        insp:DockTo(tb, "RIGHT", 6, 0)
    end
    insp:Show()
    return true
end

function _G.NobleNextGobMover.ToggleMiniSearch()
    if not ns.Access or not ns.Access.Allows(2) then
        ns.PrintError("Инструменты ГМ требуют подтверждённый уровень доступа 2+.")
        return false
    end
    local search = EnsureMiniSearch()
    if not search then return false end
    if search:IsShown() then
        search:Hide()
        return false
    end
    local anchor = MiniSuite.inspector
    if not anchor or not anchor:IsShown() then anchor = EnsureMiniToolbox() end
    search:DockTo(anchor, "BOTTOM", 0, 6)
    search:Show()
    return true
end

function _G.NobleNextGobMover.ToggleMiniHistory()
    if not ns.Access or not ns.Access.Allows(2) then
        ns.PrintError("Инструменты ГМ требуют подтверждённый уровень доступа 2+.")
        return false
    end
    local tb = EnsureMiniToolbox()
    local hist = EnsureMiniHistory()
    if not hist then return false end
    if hist:IsShown() then
        hist:Hide()
        return false
    end
    if tb then
        hist:DockTo(tb, "LEFT", 6, 0)
    end
    hist:Show()
    RefreshHistoryView()
    return true
end

function _G.NobleNextGobMover.ToggleMiniToolbox()
    if not ns.Access or not ns.Access.Allows(2) then
        ns.PrintError("Инструменты ГМ требуют подтверждённый уровень доступа 2+.")
        return false
    end
    local tb = EnsureMiniToolbox()
    if not tb then return false end
    return tb:Toggle()
end

function _G.NobleNextGobMover.OpenMiniSuite()
    if not ns.Access or not ns.Access.Allows(2) then
        ns.PrintError("Инструменты ГМ требуют подтверждённый уровень доступа 2+.")
        return false
    end
    if NobleNextDB and NobleNextDB.ui then
        NobleNextDB.ui.gobFloating = true
    end
    local tb = EnsureMiniToolbox()
    local insp = EnsureMiniInspector()
    if not tb then return false end
    tb:Show()
    if insp then
        insp:DockTo(tb, "RIGHT", 6, 0)
        insp:Show()
    end
    if ns._shell and ns._shell:IsShown() then
        ns._shell:Hide()
    end
    return true
end

function _G.NobleNextGobMover.CloseMiniSuite()
    if MiniSuite.toolbox then MiniSuite.toolbox:Hide() end
    if MiniSuite.inspector then MiniSuite.inspector:Hide() end
    if MiniSuite.history then MiniSuite.history:Hide() end
    if MiniSuite.search then MiniSuite.search:Hide() end
end

-- ---------------------------------------------------------------------------
-- Embedded Module inside NobleNextFrame (Compact Two-Column Dashboard)
-- ---------------------------------------------------------------------------
local function InitGobMoverModule(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:Hide()

    local Tabs = {}
    local TabButtons = {}

    local function ShowTab(name)
        for tabName, tab in pairs(Tabs) do
            tab:SetShown(tabName == name)
        end
        for _, btn in ipairs(TabButtons) do
            ns.SetNGTabSelected(btn, btn.tabName == name)
        end
    end

    local function CreateTabButton(text, tabName, x)
        local btn = ns.CreateNGTab(f, text, tabName, function() ShowTab(tabName) end)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", x, -8)
        btn.tabName = tabName
        table.insert(TabButtons, btn)
        return btn
    end

    local function CreateTabFrame(name, noOuterScroll)
        local host = CreateFrame("Frame", nil, f)
        host:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -40)
        host:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8)
        host:Hide()
        Tabs[name] = host
        if noOuterScroll then return host end

        local scroll = NNL.Scroll.CreateFrame(host)
        scroll:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -22, 0)
        local body = CreateFrame("Frame", nil, scroll)
        body:SetWidth(720)
        body:SetHeight(480)
        scroll:SetScrollChild(body)
        host:HookScript("OnSizeChanged", function(_, w)
            if w and w > 60 then
                body:SetWidth(math.max(580, w - 28))
            end
        end)

        Tabs[name] = host
        return body
    end

    CreateTabButton("Управление объектами", "manage", 10)
    CreateTabButton("Личные объекты", "mine", 200)

    local MiniModeTopBtn = MakeGobBtn(f, "Окна маппера (Мини-режим)", 196, 24, "primary", function()
        _G.NobleNextGobMover.OpenMiniSuite()
    end, "Свернуть большое окно и открыть лёгкие плавающие мини-окна маппера (Пульт + Инспектор + История)")
    MiniModeTopBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -8)

    -- -----------------------------------------------------------------------
    -- Tab: Manage (Compact Two-Column Mapper Workspace)
    -- -----------------------------------------------------------------------
    local Manage = CreateTabFrame("manage")

    local HeaderCard = ns.CreateNGSection(Manage, nil, nil, 84)
    HeaderCard:SetPoint("TOPLEFT", Manage, "TOPLEFT", 0, 0)
    HeaderCard:SetPoint("TOPRIGHT", Manage, "TOPRIGHT", 0, 0)

    local Title = HeaderCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    Title:SetText("Редактор объектов")
    Title:SetTextColor(ns.COLORS.goldRaw.r, ns.COLORS.goldRaw.g, ns.COLORS.goldRaw.b)
    Title:SetPoint("TOPLEFT", HeaderCard, "TOPLEFT", 12, -8)

    local NameLabel = HeaderCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    NameLabel:SetText("Цель: нет")
    NameLabel:SetPoint("LEFT", Title, "RIGHT", 14, 0)
    NameLabel:SetPoint("RIGHT", HeaderCard, "RIGHT", -12, 0)
    NameLabel:SetJustifyH("LEFT")
    _G.NobleNextGobMover._nameLabel = NameLabel
    if activeGuid ~= 0 then
        NameLabel:SetText("Цель: " .. activeName
            .. " [GUID: " .. tostring(activeGuid) .. " | Фаза: " .. tostring(activeServerPhaseId) .. "]")
    end

    local TargetBtn = MakeGobBtn(HeaderCard, "Ближайший объект", 150, 24, "primary", TargetNearestGo)
    TargetBtn:SetPoint("TOPLEFT", HeaderCard, "TOPLEFT", 12, -32)

    local PickRadarBtn = MakeGobBtn(HeaderCard, "Радар рядом", 110, 24, nil, PickNearbyGo, "Показать список ближайших объектов текущей фазы (.gobject near 50)")
    PickRadarBtn:SetPoint("LEFT", TargetBtn, "RIGHT", 6, 0)

    SetGobIcon(TargetBtn, "Nearest", "Выбрать ближайший объект", 28)
    SetGobIcon(PickRadarBtn, "Radar", "Радар ближайших объектов", 28)
    -- Mode toggle Object | Group
    local ModeLabel = ns.CreateNGLabel(HeaderCard, "Режим:")
    ModeLabel:SetPoint("LEFT", PickRadarBtn, "RIGHT", 14, 0)

    local ModeObjectBtn = ns.CreateNGButton(HeaderCard, "Объект", 84, 22)
    ModeObjectBtn:SetPoint("LEFT", ModeLabel, "RIGHT", 6, 0)
    local ModeGroupBtn = ns.CreateNGButton(HeaderCard, "Группа", 84, 22)
    ModeGroupBtn:SetPoint("LEFT", ModeObjectBtn, "RIGHT", 6, 0)

    SetGobIcon(ModeObjectBtn, "Object", "Редактировать одиночный объект", 28)
    SetGobIcon(ModeGroupBtn, "Group", "Редактировать группу объектов", 28)

    local ModeHint = HeaderCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ModeHint:SetTextColor(0.72, 0.75, 0.80, 1)
    ModeHint:SetPoint("TOPLEFT", HeaderCard, "TOPLEFT", 12, -62)
    ModeHint:SetPoint("RIGHT", HeaderCard, "RIGHT", -12, 0)
    ModeHint:SetJustifyH("LEFT")
    ModeHint:SetWordWrap(true)

    table.insert(Ui.modeButtons, {
        objectBtn = ModeObjectBtn,
        groupBtn = ModeGroupBtn,
        hint = ModeHint,
    })

    ModeObjectBtn:SetScript("OnClick", function() SetEditMode("object") end)
    ModeGroupBtn:SetScript("OnClick", function() SetEditMode("group") end)

    -- Left Column: Move Section
    local MoveSection = ns.CreateNGSection(Manage, "Перемещение", 300, 262)
    MoveSection:SetPoint("TOPLEFT", HeaderCard, "BOTTOMLEFT", 0, -8)
    MoveSection:SetWidth(300)

    local StepLbl = ns.CreateNGLabel(MoveSection, "Шаг:")
    StepLbl:SetPoint("TOPLEFT", MoveSection, "TOPLEFT", 12, -30)
    local StepBox = ns.CreateNGEditBox(MoveSection, "GobMover_Step", 56, 22)
    StepBox:SetPoint("LEFT", StepLbl, "RIGHT", 6, 0)
    -- NOT SetNumeric: allow decimals and minus
    BindSyncedBox(Ui.stepBoxes, StepBox, stepValueText, SetStepText)

    BuildPresetChips(MoveSection, { "0.05", "0.25", "1", "5" }, 114, -31, 40, 20, function(v)
        SetStepText(v)
    end)

    local PAD = 40
    local PAD_GAP = 4
    local padOriginX = 60
    local padOriginY = -62

    local dirGrid = {
        { "FL", "F", "FR" },
        { "L",  "",  "R"  },
        { "BL", "B", "BR" },
    }
    local dirLabels = {
        FL = "Вперёд-Л", F = "Вперёд", FR = "Вперёд-П",
        L = "Влево", R = "Вправо",
        BL = "Назад-Л", B = "Назад", BR = "Назад-П",
    }

    for row = 1, 3 do
        for col = 1, 3 do
            local dir = dirGrid[row][col]
            local x = padOriginX + (col - 1) * (PAD + PAD_GAP)
            local y = padOriginY - (row - 1) * (PAD + PAD_GAP)
            if dir ~= "" then
                local btn = ns.CreateNGButton(MoveSection, dirLabels[dir], PAD, 32)
                SetGobIcon(btn, directionIcons[dir], directionHints[dir], PAD, "Переместить на заданный шаг относительно взгляда персонажа.")
                btn:SetPoint("TOPLEFT", MoveSection, "TOPLEFT", x, y)
                btn:SetScript("OnClick", function()
                    TriggerNudge(dir, StepBox)
                end)
            end
        end
    end
    local PickBtn = ns.CreateNGButton(MoveSection, "Выбрать", PAD, 32)
    PickBtn:SetPoint("TOPLEFT", MoveSection, "TOPLEFT", padOriginX + PAD + PAD_GAP, padOriginY - PAD - PAD_GAP)
    PickBtn:SetScript("OnClick", TargetNearestGo)

    local UpBtn = ns.CreateNGButton(MoveSection, "Вверх", 68, 44)
    UpBtn:SetPoint("TOPLEFT", MoveSection, "TOPLEFT", padOriginX + 3 * (PAD + PAD_GAP) + 8, padOriginY)
    UpBtn:SetScript("OnClick", function()
        TriggerNudge("UP", StepBox)
    end)

    local DownBtn = ns.CreateNGButton(MoveSection, "Вниз", 68, 44)
    DownBtn:SetPoint("TOPLEFT", UpBtn, "BOTTOMLEFT", 0, -PAD - 2 * PAD_GAP)
    DownBtn:SetScript("OnClick", function()
        TriggerNudge("DOWN", StepBox)
    end)

    SetGobIcon(PickBtn, "Select", "Выбрать ближайший объект", PAD)
    SetGobIcon(UpBtn, "Up", "Поднять объект", PAD)
    SetGobIcon(DownBtn, "Down", "Опустить объект", PAD)

    -- Right Column: Rotation + Scale Sections
    local RotSection = ns.CreateNGSection(Manage, "Поворот / наклон", nil, 176)
    RotSection:SetPoint("TOPLEFT", MoveSection, "TOPRIGHT", 8, 0)
    RotSection:SetPoint("TOPRIGHT", HeaderCard, "BOTTOMRIGHT", 0, -8)

    local RotLbl = ns.CreateNGLabel(RotSection, "Угол (град):")
    RotLbl:SetPoint("TOPLEFT", RotSection, "TOPLEFT", 12, -30)
    local RotBox = ns.CreateNGEditBox(RotSection, "GobMover_RotStep", 54, 22)
    RotBox:SetPoint("LEFT", RotLbl, "RIGHT", 6, 0)
    BindSyncedBox(Ui.rotBoxes, RotBox, rotValueText, SetRotText)

    BuildPresetChips(RotSection, { { "5°", "5" }, { "15°", "15" }, { "45°", "45" }, { "90°", "90" } }, 154, -31, 36, 20, function(v)
        SetRotText(v)
    end)

    local CwBtn = ns.CreateNGButton(RotSection, "По часовой", 104, 24)
    CwBtn:SetPoint("TOPLEFT", RotSection, "TOPLEFT", 12, -60)
    CwBtn:SetScript("OnClick", function()
        TriggerYaw(-1, RotBox)
    end)

    local CcwBtn = ns.CreateNGButton(RotSection, "Против часовой", 118, 24)
    CcwBtn:SetPoint("LEFT", CwBtn, "RIGHT", 6, 0)
    CcwBtn:SetScript("OnClick", function()
        TriggerYaw(1, RotBox)
    end)

    local ResetBtn = ns.CreateNGButton(RotSection, "Сброс поворота", 116, 24)
    ResetBtn:SetPoint("LEFT", CcwBtn, "RIGHT", 6, 0)
    ResetBtn:SetScript("OnClick", TriggerResetRotation)

    -- Tilt: pitch up/down, roll L/R, forward/back
    local PitchUpBtn = ns.CreateNGButton(RotSection, "Вперёд", 76, 24)
    PitchUpBtn:SetPoint("TOPLEFT", CwBtn, "BOTTOMLEFT", 0, -26)
    PitchUpBtn:SetScript("OnClick", function()
        TriggerTilt(1, 0, RotBox)
    end)

    local PitchDnBtn = ns.CreateNGButton(RotSection, "Назад", 76, 24)
    PitchDnBtn:SetPoint("LEFT", PitchUpBtn, "RIGHT", 6, 0)
    PitchDnBtn:SetScript("OnClick", function()
        TriggerTilt(-1, 0, RotBox)
    end)

    local RollLBtn = ns.CreateNGButton(RotSection, "Влево", 76, 24)
    RollLBtn:SetPoint("LEFT", PitchDnBtn, "RIGHT", 14, 0)
    RollLBtn:SetScript("OnClick", function()
        TriggerTilt(0, 1, RotBox)
    end)

    local RollRBtn = ns.CreateNGButton(RotSection, "Вправо", 76, 24)
    RollRBtn:SetPoint("LEFT", RollLBtn, "RIGHT", 6, 0)
    RollRBtn:SetScript("OnClick", function()
        TriggerTilt(0, -1, RotBox)
    end)

    SetGobIcon(CwBtn, "Clockwise", "Повернуть по часовой стрелке", 40)
    SetGobIcon(CcwBtn, "Counterclockwise", "Повернуть против часовой стрелки", 40)
    SetGobIcon(ResetBtn, "Reset", "Сбросить поворот", 40)
    SetGobIcon(PitchUpBtn, "PitchUp", "Увеличить наклон", 40)
    SetGobIcon(PitchDnBtn, "PitchDown", "Уменьшить наклон", 40)
    SetGobIcon(RollLBtn, "RollLeft", "Крен влево", 40)
    SetGobIcon(RollRBtn, "RollRight", "Крен вправо", 40)

    local PitchLabel = ns.CreateNGLabel(RotSection, "Наклон")
    PitchLabel:SetPoint("BOTTOMLEFT", PitchUpBtn, "TOPLEFT", 0, 4)
    local RollLabel = ns.CreateNGLabel(RotSection, "Крен")
    RollLabel:SetPoint("BOTTOMLEFT", RollLBtn, "TOPLEFT", 0, 4)

    -- Scale Section (Right Column bottom, aligned with MoveSection bottom)
    local ScaleSection = ns.CreateNGSection(Manage, "Масштаб", nil, 78)
    ScaleSection:SetPoint("TOPLEFT", RotSection, "BOTTOMLEFT", 0, -8)
    ScaleSection:SetPoint("TOPRIGHT", RotSection, "BOTTOMRIGHT", 0, -8)

    local ScaleLbl = ns.CreateNGLabel(ScaleSection, "Размер:")
    ScaleLbl:SetSize(72, 22)
    ScaleLbl:SetPoint("TOPLEFT", ScaleSection, "TOPLEFT", 12, -32)
    table.insert(Ui.scaleLabels, ScaleLbl)

    local ScaleBox = ns.CreateNGEditBox(ScaleSection, "GobMover_Scale", 50, 22)
    ScaleBox:SetPoint("LEFT", ScaleLbl, "RIGHT", 4, 0)
    BindSyncedBox(Ui.scaleBoxes, ScaleBox, scaleValueText, SetScaleText)

    local ScaleBtn = ns.CreateNGButton(ScaleSection, "Применить размер", 88, 24)
    ScaleBtn:SetPoint("LEFT", ScaleBox, "RIGHT", 8, 0)
    ScaleBtn:SetScript("OnClick", function()
        TriggerScale(ScaleBox)
    end)

    local ScaleDownBtn = CreateScaleIcon(ScaleSection, ScaleBox, -1, 36)
    ScaleDownBtn:SetPoint("LEFT", ScaleBox, "RIGHT", 4, 0)
    local ScaleUpBtn = CreateScaleIcon(ScaleSection, ScaleBox, 1, 36)
    ScaleUpBtn:SetPoint("LEFT", ScaleDownBtn, "RIGHT", 4, 0)
    ScaleBtn:ClearAllPoints()
    ScaleBtn:SetPoint("LEFT", ScaleUpBtn, "RIGHT", 4, 0)
    ScaleBtn:SetText("Применить")
    SetGobIcon(ScaleBtn, "Apply", "Применить масштаб", 36, "Применить указанное значение к объекту или группе.")

    -- Bottom Full-Width Section: Spawn, Replace & World Operations
    local WorldSection = ns.CreateNGSection(Manage, "Спавн, замена и операции с объектом", nil, 120)
    WorldSection:SetPoint("TOPLEFT", MoveSection, "BOTTOMLEFT", 0, -8)
    WorldSection:SetPoint("TOPRIGHT", ScaleSection, "BOTTOMRIGHT", 0, -8)

    local EntryLbl = ns.CreateNGLabel(WorldSection, "Entry:")
    EntryLbl:SetPoint("TOPLEFT", WorldSection, "TOPLEFT", 12, -30)
    local EntryBox = ns.CreateNGEditBox(WorldSection, "GobMover_Entry", 110, 22)
    EntryBox:SetPoint("LEFT", EntryLbl, "RIGHT", 6, 0)
    BindSyncedBox(Ui.entryBoxes, EntryBox, entryValueText, SetEntryText)

    local SpawnBtn = MakeGobBtn(WorldSection, "Спавн (.add)", 96, 22, "primary", function()
        SpawnEntryGo(EntryBox, false)
    end, "Создать постоянный GO по указанному Entry (или дублировать текущий)")
    SpawnBtn:SetPoint("LEFT", EntryBox, "RIGHT", 6, 0)

    local SpawnTempBtn = MakeGobBtn(WorldSection, "Врем. спавн", 92, 22, nil, function()
        SpawnEntryGo(EntryBox, true)
    end, "Временно призвать GO (.gobject add temp)")
    SpawnTempBtn:SetPoint("LEFT", SpawnBtn, "RIGHT", 6, 0)

    local ReplaceBtn = MakeGobBtn(WorldSection, "Заменить Entry", 110, 22, nil, function()
        ReplaceTargetEntry(EntryBox)
    end, "Заменить шаблон выбранного объекта, сохранив его GUID и позицию (.gobject replace)")
    ReplaceBtn:SetPoint("LEFT", SpawnTempBtn, "RIGHT", 6, 0)

    local SearchLabel = ns.CreateNGLabel(WorldSection, "Поиск:")
    SearchLabel:SetPoint("LEFT", ReplaceBtn, "RIGHT", 12, 0)
    local SearchBox = ns.CreateNGEditBox(WorldSection, "GobMover_Search", 142, 22)
    SearchBox:SetPoint("LEFT", SearchLabel, "RIGHT", 6, 0)
    BindSyncedBox(Ui.searchBoxes, SearchBox, searchValueText, SetSearchText)
    SearchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); LookupObjectsByQuery(self) end)

    local LookupBtn = MakeGobBtn(WorldSection, "Поиск объектов", 104, 22, nil, function()
        LookupObjectsByQuery(SearchBox)
    end, "Открыть окно поиска по всем словам названия (.lo ob like)")
    LookupBtn:SetPoint("LEFT", SearchBox, "RIGHT", 6, 0)

    -- Row 2 of WorldSection: Actions on selected GO
    local GoToBtn = MakeGobBtn(WorldSection, "К объекту", 88, 22, nil, function()
        if RequireTarget() then SendWorldCommand("go gameobject " .. tostring(activeGuid), "gobmover:go") end
    end)
    GoToBtn:SetPoint("TOPLEFT", WorldSection, "TOPLEFT", 12, -74)

    local MoveHereBtn = MakeGobBtn(WorldSection, "Перенести к себе", 122, 22, nil, function()
        if RequireTarget() then SendWorldCommand("gobject move " .. tostring(activeGuid), "gobmover:movehere") end
    end)
    MoveHereBtn:SetPoint("LEFT", GoToBtn, "RIGHT", 6, 0)

    local ActivateBtn = MakeGobBtn(WorldSection, "Активировать", 100, 22, nil, function()
        if RequireTarget() then SendWorldCommand("gobject activate " .. tostring(activeGuid), "gobmover:activate") end
    end)
    ActivateBtn:SetPoint("LEFT", MoveHereBtn, "RIGHT", 6, 0)

    local CheckInfoBtn = MakeGobBtn(WorldSection, "Инфо в чат", 90, 22, nil, function()
        if RequireTarget() then SendWorldCommand("gobject check " .. tostring(activeGuid), "gobmover:check") end
    end)
    CheckInfoBtn:SetPoint("LEFT", ActivateBtn, "RIGHT", 6, 0)

    local ToGroupBtn = MakeGobBtn(WorldSection, "В группу…", 86, 22, nil, OpenInGobGroup)
    ToGroupBtn:SetPoint("LEFT", CheckInfoBtn, "RIGHT", 6, 0)

    local DeleteGoBtn = MakeGobBtn(WorldSection, "Удалить GO", 96, 22, "danger", function()
        ConfirmDeleteGuid(activeGuid, activeName)
    end)
    DeleteGoBtn:SetPoint("LEFT", ToGroupBtn, "RIGHT", 6, 0)

    SetGobIcon(ReplaceBtn, "Replace", "Заменить Entry выбранного объекта", 36, "Сохраняет GUID и положение объекта.")
    SetGobIcon(LookupBtn, "Search", "Поиск объектов по названию", 36)
    SetGobIcon(SpawnBtn, "Spawn", "Создать постоянный объект", 36)
    SetGobIcon(SpawnTempBtn, "SpawnTemporary", "Создать временный объект", 36, "Для сохранения после перезапуска объект нужно запечь.")
    SetGobIcon(GoToBtn, "Teleport", "Телепортироваться к объекту", 36)
    SetGobIcon(MoveHereBtn, "Pull", "Перенести объект к персонажу", 36)
    SetGobIcon(ActivateBtn, "Activate", "Активировать объект", 36)
    SetGobIcon(CheckInfoBtn, "Info", "Информация об объекте в чат", 36)
    SetGobIcon(ToGroupBtn, "Group", "Добавить объект в группу", 36)
    SetGobIcon(DeleteGoBtn, "Delete", "Удалить объект", 36, "Потребуется подтверждение.")

    local HelpLabel = Manage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    HelpLabel:SetText("Совет: нажмите «Окна маппера» справа вверху (или ПКМ по разделу «Объекты» в меню), чтобы переключиться на компактные плавающие окошки.")
    HelpLabel:SetTextColor(0.58, 0.62, 0.68, 1)
    HelpLabel:SetPoint("TOPLEFT", WorldSection, "BOTTOMLEFT", 4, -8)
    HelpLabel:SetPoint("RIGHT", Manage, "RIGHT", -8, 0)
    HelpLabel:SetJustifyH("LEFT")
    HelpLabel:SetWordWrap(true)

    SetEditMode("object")

    -- -----------------------------------------------------------------------
    -- Tab: Personal objects (AIO GetMineList -> VirtualList)
    -- -----------------------------------------------------------------------
    local Mine = CreateTabFrame("mine", true)
    local mineShowAllPhases = false
    local mineRows = {}

    local MineTitle = Mine:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    MineTitle:SetText("Личные объекты")
    MineTitle:SetTextColor(ns.COLORS.goldRaw.r, ns.COLORS.goldRaw.g, ns.COLORS.goldRaw.b)
    MineTitle:SetPoint("TOPLEFT", Mine, "TOPLEFT", 4, -4)

    local MineCount = Mine:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    MineCount:SetPoint("LEFT", MineTitle, "RIGHT", 12, 0)
    MineCount:SetText("Показано: 0")

    local RefreshMineBtn = ns.CreateNGButton(Mine, "Обновить", 100, 24)
    RefreshMineBtn:SetPoint("TOPLEFT", MineTitle, "BOTTOMLEFT", 0, -10)
    RefreshMineBtn:SetScript("OnClick", function()
        if not ns.AIOHandle(AIO_HANDLER, "GetMineList", mineShowAllPhases, 0, 200) then
            ns.PrintError("AIO недоступен для списка личных GO.")
        end
    end)

    local PhaseMineBtn = ns.CreateNGButton(Mine, "Текущая фаза", 130, 24)
    PhaseMineBtn:SetPoint("LEFT", RefreshMineBtn, "RIGHT", 8, 0)
    PhaseMineBtn:SetScript("OnClick", function()
        mineShowAllPhases = not mineShowAllPhases
        PhaseMineBtn:SetText(mineShowAllPhases and "Все фазы" or "Текущая фаза")
        if not ns.AIOHandle(AIO_HANDLER, "GetMineList", mineShowAllPhases, 0, 200) then
            ns.PrintError("AIO недоступен для списка личных GO.")
        end
    end)

    local ChatDumpBtn = ns.CreateNGButton(Mine, "Список в чат", 130, 24)
    ChatDumpBtn:SetPoint("LEFT", PhaseMineBtn, "RIGHT", 8, 0)
    ChatDumpBtn:SetScript("OnClick", function()
        if ns.RunGmCommand then
            ns.RunGmCommand("gobject list my")
        else
            ns.PrintError("RunGmCommand недоступен.")
        end
    end)

    local mineListHost = CreateFrame("Frame", nil, Mine)
    mineListHost:SetPoint("TOPLEFT", RefreshMineBtn, "BOTTOMLEFT", 0, -10)
    mineListHost:SetPoint("BOTTOMRIGHT", Mine, "BOTTOMRIGHT", -4, 4)
    local mineScroll = NNL.Scroll.CreateFrame(mineListHost)
    mineScroll:SetPoint("TOPLEFT", mineListHost, "TOPLEFT", 0, 0)
    mineScroll:SetPoint("BOTTOMRIGHT", mineListHost, "BOTTOMRIGHT", -22, 0)
    local mineChild = CreateFrame("Frame", nil, mineScroll)
    mineChild:SetSize(560, 400)
    mineScroll:SetScrollChild(mineChild)
    local MineEmpty = mineListHost:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    MineEmpty:SetPoint("TOPLEFT", mineListHost, "TOPLEFT", 10, -16)
    MineEmpty:SetPoint("RIGHT", mineListHost, "RIGHT", -26, 0)
    MineEmpty:SetJustifyH("LEFT")
    MineEmpty:SetText("Нажмите «Обновить», чтобы увидеть свои объекты.")

    local mineList = ns.VirtualList.Create(mineChild, {
        width = 540,
        rowHeight = 34,
        visibleCount = 12,
        onClick = function(row)
            if not row or not row.guid then return end
            if row.entry then
                SetEntryText(tostring(row.entry))
            end
            if ns.RunGmCommand then
                ns.RunGmCommand("movego " .. tostring(row.guid))
            else
                ns.AIOHandle(AIO_HANDLER, "Select", row.guid)
            end
            ShowTab("manage")
        end,
        renderRow = function(btn, row)
            local fs = btn.fs or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.fs = fs
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -3)
            fs:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            fs:SetJustifyH("LEFT")
            fs:SetText(string.format("%s  |cffaaaaaa[%s]|r", row.name or "?", tostring(row.guid or "-")))

            local sub = btn.sub or btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            btn.sub = sub
            sub:ClearAllPoints()
            sub:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 6, 3)
            sub:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            sub:SetJustifyH("LEFT")
            sub:SetText(string.format("entry %s | map %s | %.1f %.1f %.1f | RP %s",
                tostring(row.entry or "-"),
                tostring(row.map or "-"),
                tonumber(row.x) or 0, tonumber(row.y) or 0, tonumber(row.z) or 0,
                tostring(row.phaseId or 0)))
        end,
    })

    _G.NobleNextGobMover.OnMineList = function(rows)
        mineRows = rows or {}
        Ui.mineRows = mineRows
        mineList:SetRows(mineRows)
        MineEmpty:SetText("Объектов в выбранных фазах пока нет.")
        MineEmpty:SetShown(#mineRows == 0)
        MineCount:SetText(string.format("Показано: %d%s", #mineRows,
            mineShowAllPhases and " (все фазы)" or " (текущая фаза)"))
        if RefreshHistoryView then
            RefreshHistoryView()
        end
    end

    ShowTab("manage")
    return f
end

local function ShowGobMover(msg)
    msg = tostring(msg or ""):lower():match("^%s*(.-)%s*$") or ""
    if msg == "mini" or msg == "float" or msg == "compact" then
        _G.NobleNextGobMover.OpenMiniSuite()
        return
    end
    ns.ShowModule("Gob Mover")
end

C_Timer.After(0, function()
    ns.RegisterSlashCommand("NNGOBMOVER", ShowGobMover, { "nngobmover", "nngomover" })
    ns.RegisterSlashCommand("NNGOBMINI", function()
        _G.NobleNextGobMover.OpenMiniSuite()
    end, { "nngobmini", "nngomini" })
end)

if ns.RegisterQuickAction then
    ns.RegisterQuickAction({
        id = "gobmini",
        title = "Мини-пульт объектов",
        icon = "Interface\\Icons\\garrison_building_workshop",
        order = 205,
        requiredLevel = 2,
        allowInCombat = true,
        onClick = function()
            return _G.NobleNextGobMover.OpenMiniSuite()
        end,
    })
end

if ns.Subscribe then
    ns.Subscribe("ACCESS_CHANGED", "gm.gobmover-mini", function()
        if not (ns.Access and ns.Access.Allows(2)) then
            _G.NobleNextGobMover.CloseMiniSuite()
        end
    end)
end

ns.RegisterModule("Gob Mover", InitGobMoverModule, "Редактирование GameObject (встроенный + модульный мини-режим)")
