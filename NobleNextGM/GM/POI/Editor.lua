-- Loaded through the NobleNextGM private extension namespace.
-- GM/POI/Editor.lua — UI /nnpoi
local _, ns = ...
local NNL = LibStub("NobleNextLib-1.0")

ns.PoiEditor = ns.PoiEditor or {}
local Ui = {}
local MAX_COMMAND_LEN = 1024
local MAX_NAME_LEN = 80
local MAX_DESC_LEN = 220

local initColorDropdown
local syncColorDropdownButton

local function quoteArg(value)
    value = tostring(value or "")
    value = value:gsub("\\", "\\\\"):gsub('"', '\\"')
    return '"' .. value .. '"'
end

local function quoteTailArg(value)
    return tostring(value or "")
end

local function runPoiCommand(command, quiet)
    if not quiet then
        ns.PoiEditor.SetStatus("Команда: " .. command, "info")
    end
    return ns.RunGmCommand(command)
end

local function commandLen(command)
    return #("." .. tostring(command or ""))
end

local function runLimitedCommand(command, label, quiet)
    if commandLen(command) > MAX_COMMAND_LEN then
        ns.PoiEditor.SetStatus(string.format(
            "%s слишком длинная команда (%d/%d). Сократите текст.",
            label or "POI",
            commandLen(command),
            MAX_COMMAND_LEN
        ), "error")
        return false
    end
    return runPoiCommand(command, quiet)
end

local function requireId()
    local id = tonumber(Ui.IdBox and Ui.IdBox:GetText())
    if not id or id <= 0 or id ~= math.floor(id) then
        ns.PrintError("Укажите ID POI (выберите из списка).")
        return nil
    end
    return id
end

local function getOwnerMode()
    return tonumber(Ui.OwnerTypeValue) or 1
end

local function refreshAvailability()
    local allowed = ns.Access and ns.Access.Allows(2) == true or false
    local id = tonumber(Ui.IdBox and Ui.IdBox:GetText())
    local selected = id and id > 0 and id == math.floor(id)
    if Ui.OwnerBox then
        local enabled = allowed and getOwnerMode() ~= 3
        Ui.OwnerBox:SetEnabled(enabled)
        Ui.OwnerBox:SetAlpha(enabled and 1 or 0.45)
        if not enabled then Ui.OwnerBox:ClearFocus() end
    end
    if Ui.ApplyBtn then Ui.ApplyBtn:SetEnabled(allowed and selected or false) end
    if Ui.DeleteBtn then Ui.DeleteBtn:SetEnabled(allowed and selected or false) end
    if Ui.CreateBtn then Ui.CreateBtn:SetEnabled(allowed) end
end

local function refreshPreview()
    refreshAvailability()
    local entry = ns.PoiIconEntry(Ui.SelectedIconKey)
    if Ui.IconPreview then
        local tex = ns.PoiIconForKey(entry.key, entry.type)
        if not Ui.IconPreview:SetTexture(tex) then
            Ui.IconPreview:SetTexture(ns.PoiFallbackIconForKey(entry.key, entry.type))
        end
        local r, g, b = ns.PoiColorRgb(Ui.SelectedColorKey)
        Ui.IconPreview:SetVertexColor(r, g, b)
    end
    if Ui.PreviewColor then
        Ui.PreviewColor:SetText(ns.PoiColorLabel(Ui.SelectedColorKey))
    end
    syncColorDropdownButton()
    if Ui.OwnerLabel then
        Ui.OwnerLabel:SetText(ns.PoiOwnerDisplay({
            ownerType = Ui.OwnerTypeValue,
            ownerName = Ui.OwnerBox and Ui.OwnerBox:GetText() or "",
        }))
    end
end

local function applyIconSelection(entry)
    if not entry then return end
    Ui.SelectedIconKey = entry.key
    Ui.SelectedLegacyType = entry.legacy
    refreshPreview()
    initColorDropdown()
end

local function setIconDropdown(key)
    applyIconSelection(ns.PoiIconEntry(key))
    if not Ui.IconDropdown then return end
    Ui.IconDropdown:GenerateMenu()
end

local function applyColorSelection(colorId)
    Ui.SelectedColorKey = tonumber(colorId) or 0
    refreshPreview()
end

local function setColorDropdown(colorKey)
    applyColorSelection(colorKey)
    if not Ui.ColorDropdown then return end
    Ui.ColorDropdown:GenerateMenu()
    syncColorDropdownButton()
end

syncColorDropdownButton = function()
    if Ui.ColorDropdown then Ui.ColorDropdown:GenerateMenu() end
end

local function buildApplyCommand(id)
    local entry = ns.PoiIconEntry(Ui.SelectedIconKey)
    local colorKey = tonumber(Ui.SelectedColorKey) or 0
    local ownerMode = getOwnerMode()
    local posFlag = (Ui.ApplyPositionCheck and Ui.ApplyPositionCheck:GetChecked()) and 1 or 0
    local ownerText = Ui.OwnerBox and Ui.OwnerBox:GetText() or ""

    local cmd = string.format(
        "poi set apply %d %d %s %d %d %d",
        id, entry.type, entry.key, colorKey, ownerMode, posFlag
    )

    if ownerMode == 3 then
        return cmd
    end
    if ownerMode == 2 or ownerMode == 4 then
        return cmd .. " " .. quoteTailArg(ownerText)
    end
    if ownerText ~= "" then
        return cmd .. " " .. quoteTailArg(ownerText)
    end
    return cmd
end

local function saveProperties()
    local id = requireId()
    if not id then return end
    local commands = { { buildApplyCommand(id), "Свойства" } }
    local name = Ui.NameBox and Ui.NameBox:GetText() or ""
    local desc = ns.PoiDescriptionForStorage(Ui.DescBox and Ui.DescBox:GetText() or "")

    if name ~= "" then
        -- These handlers take Tail, not TokenizePoiArgs: escaping would be stored literally.
        table.insert(commands, { "poi set name " .. id .. " " .. quoteTailArg(name), "Имя" })
    end
    if Ui.DescBox then
        table.insert(commands, { "poi set des " .. id .. " " .. (desc ~= "" and quoteTailArg(desc) or '""'), "Описание" })
    end

    for _, item in ipairs(commands) do
        if commandLen(item[1]) > MAX_COMMAND_LEN then
            ns.PoiEditor.SetStatus(string.format(
                "%s не сохранено: команда %d/%d символов.",
                item[2],
                commandLen(item[1]),
                MAX_COMMAND_LEN
            ), "error")
            return
        end
    end

    ns.PoiEditor.SetStatus("Сохраняем POI...", "info")
    for i, item in ipairs(commands) do
        runLimitedCommand(item[1], item[2], i > 1)
    end
end

local function createdRequestSent()
    -- The new ID is not yet known. Never leave Apply pointing at the old selection.
    if Ui.IdBox then Ui.IdBox:SetText("") end
    refreshAvailability()
    ns.PoiEditor.SetStatus("Запрос создания отправлен. Выберите новую точку в списке, затем задайте остальные свойства через «Применить».", "info")
end

local function createPoiFromEditor()
    local name = Ui.NameBox and Ui.NameBox:GetText() or ""
    local desc = ns.PoiDescriptionForStorage(Ui.DescBox and Ui.DescBox:GetText() or "")
    local legacyType = tonumber(Ui.SelectedLegacyType) or 0
    local colorKey = tonumber(Ui.SelectedColorKey) or 0
    local iconKey = Ui.SelectedIconKey or "Misc"

    if name == "" and desc == "" and legacyType == 0 and colorKey == 0 then
        if runPoiCommand("poi create") then createdRequestSent() end
        return
    end

    local command = "poi create " .. quoteArg(name ~= "" and name or "Точка интереса")
    if legacyType ~= 0 or desc ~= "" or colorKey ~= 0 then
        command = command .. " " .. legacyType
    end
    if desc ~= "" or colorKey ~= 0 then
        -- The create tokenizer drops empty quoted tokens. Preserve the description
        -- position with whitespace so the following color remains the fourth arg.
        command = command .. " " .. quoteArg(desc ~= "" and desc or " ")
    end
    if colorKey ~= 0 then
        command = command .. " " .. colorKey
    end

    if not runLimitedCommand(command, "Создание") then return end
    createdRequestSent()

    if iconKey ~= "Misc" and iconKey ~= "Story" and iconKey ~= "Camp" and iconKey ~= "House" and iconKey ~= "Tower" then
        ns.PoiEditor.SetStatus(
            "Запрос отправлен. После появления новой точки выберите её в списке и нажмите \"Применить\" для иконки \"" .. ns.PoiIconLabel(iconKey) .. "\".",
            "warning"
        )
    end
end

local function initIconDropdown()
    Ui.IconDropdown:SetupMenu(function(_, rootDescription)
        for _, entry in ipairs(ns.PoiIconTypes) do
            rootDescription:CreateRadio(entry.label,
                function(value) return Ui.SelectedIconKey == value.key end,
                applyIconSelection, entry)
        end
    end)
end

initColorDropdown = function()
    if not Ui.ColorDropdown then return end
    Ui.ColorDropdown:SetupMenu(function(_, rootDescription)
        for colorId = 0, 6 do
            rootDescription:CreateRadio(ns.PoiColorLabel(colorId),
                function(value) return Ui.SelectedColorKey == value end,
                applyColorSelection, colorId)
        end
    end)
end

local function createMultilineEditBox(parent, name, width, height, maxLetters)
    local shell = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    shell:SetSize(width, height)
    if shell.SetBackdrop then
        shell:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, tileSize = 0, edgeSize = 8,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        shell:SetBackdropColor(0, 0, 0, 0.5)
        shell:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
    end

    local scroll = NNL.Scroll.CreateFrame(shell)
    scroll:SetPoint("TOPLEFT", shell, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -24, 6)

    local edit = CreateFrame("EditBox", (parent:GetName() or "NobleNext") .. "_Edit_" .. name, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("GameFontHighlight")
    edit:SetWidth(width - 34)
    edit:SetMaxLetters(maxLetters or MAX_DESC_LEN)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnCursorChanged", function(self, _, y, _, cursorHeight)
        ScrollingEdit_OnCursorChanged(self, 0, y, 0, cursorHeight)
    end)
    edit:SetScript("OnUpdate", function(self, elapsed)
        ScrollingEdit_OnUpdate(self, elapsed, scroll)
    end)
    scroll:SetScrollChild(edit)

    return shell, edit
end

function ns.PoiEditor.SetStatus(message, level)
    if not Ui.StatusText then
        if level == "error" and ns.PrintError then ns.PrintError(message) end
        return
    end

    local r, g, b = 0.75, 0.75, 0.75
    if level == "success" then
        r, g, b = 0.45, 1.0, 0.45
    elseif level == "warning" then
        r, g, b = 1.0, 0.82, 0.25
    elseif level == "error" then
        r, g, b = 1.0, 0.25, 0.25
    elseif level == "info" then
        r, g, b = 0.55, 0.75, 1.0
    end

    Ui.StatusText:SetText(message or "")
    Ui.StatusText:SetTextColor(r, g, b)
end

function ns.PoiEditor.UpdateListFromCache()
    if not Ui.List or not ns.PoiCache or not ns.PoiCache.AllEntries then
        return
    end
    if Ui.Root and Ui.Root.IsShown and not Ui.Root:IsShown() then
        Ui.listDirty = true
        return
    end
    Ui.listDirty = false
    Ui.List:SetRows(ns.PoiCache.AllEntries())
end

function ns.PoiEditor.OnSelectPoi(id, name, desc, poiType, ownerType, ownerName, iconKey, colorKey)
    if Ui.IdBox then Ui.IdBox:SetText(tostring(id or "")) end
    if Ui.NameBox then Ui.NameBox:SetText(name or "") end
    if Ui.DescBox then Ui.DescBox:SetText(ns.PoiDescriptionForEdit(desc or "")) end
    if Ui.OwnerBox then Ui.OwnerBox:SetText(ownerName or "") end
    Ui.OwnerTypeValue = tonumber(ownerType) or 1
    if Ui.OwnerTypeBox then
        Ui.OwnerTypeBox:GenerateMenu()
    end

    local resolvedKey = iconKey
    if not resolvedKey or resolvedKey == "" then
        for _, icon in ipairs(ns.PoiIconTypes) do
            if icon.type == tonumber(poiType) then
                resolvedKey = icon.key
                break
            end
        end
        resolvedKey = resolvedKey or "Misc"
    end
    setIconDropdown(resolvedKey)
    setColorDropdown(colorKey)
    refreshAvailability()
end

function ns.PoiEditor.OnSetList(rows)
    if Ui.List then
        Ui.List:SetRows(rows or {})
    end
    if ns.PoiMapPins and ns.PoiMapPins.RedrawAll then
        ns.PoiMapPins.RedrawAll()
    end
    if ns.PoiMapPins and not ns.PoiMapPins.HasLibrary() then
        ns.PoiEditor.SetStatus("Список POI загружен, но HereBeDragons не найден: метки на карте скрыты.", "warning")
    else
        ns.PoiEditor.SetStatus(string.format("Список POI: %d строк.", #(rows or {})), "success")
    end
end

function ns.PoiEditor.RefreshList()
    ns.PoiEditor.SetStatus("Загружаем точки с сервера...", "info")
    runPoiCommand("poi sync")
end

function ns.PoiEditor.Init(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:Hide()
    Ui.Root = f

    f:SetScript("OnShow", function()
        refreshAvailability()
        if ns.PoiCache and ns.PoiCache.HasEntries and ns.PoiCache.HasEntries() then
            ns.PoiEditor.UpdateListFromCache()
        elseif ns.PoiRequestSyncFromAddon and ns.PoiRequestSyncFromAddon() then
            ns.PoiEditor.SetStatus("Загружаем точки с сервера...", "info")
        elseif Ui.listDirty then
            ns.PoiEditor.UpdateListFromCache()
        end
    end)

    local Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    Title:SetText("Точки интереса")
    Title:SetTextColor(ns.COLORS.goldRaw.r, ns.COLORS.goldRaw.g, ns.COLORS.goldRaw.b)
    Title:SetPoint("TOP", f, "TOP", 0, -8)

    local Help = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Help:SetText("Выберите точку в списке. Изменения сохраняются кнопкой «Применить».")
    Help:SetTextColor(0.5, 0.5, 0.5)
    Help:SetPoint("BOTTOM", f, "BOTTOM", 0, 6)

    Ui.StatusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Ui.StatusText:SetPoint("BOTTOM", Help, "TOP", 0, 4)
    Ui.StatusText:SetText("POI готов.")
    Ui.StatusText:SetTextColor(0.55, 0.75, 1.0)

    -- Правая колонка: список.
    local ListSection = ns.CreateNGSection(f, "Список")
    ListSection:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -32)
    ListSection:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 36)
    ListSection:SetWidth(218)

    Ui.SearchBox = ns.CreateNGEditBox(ListSection, "PoiSearch", 184, 22)
    Ui.SearchBox:SetPoint("TOPLEFT", ListSection, "TOPLEFT", 12, -36)
    Ui.SearchBox:SetPoint("TOPRIGHT", ListSection, "TOPRIGHT", -12, -36)
    Ui.SearchBox:SetScript("OnTextChanged", function(self)
        if Ui.List then Ui.List:SetFilter(self:GetText()) end
    end)

    local scroll = NNL.Scroll.CreateFrame(ListSection)
    scroll:SetPoint("TOPLEFT", ListSection, "TOPLEFT", 8, -64)
    scroll:SetPoint("BOTTOMRIGHT", ListSection, "BOTTOMRIGHT", -28, 8)
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(180)
    scrollChild:SetHeight(24)
    scroll:SetScrollChild(scrollChild)

    Ui.List = ns.VirtualList.Create(scrollChild, {
        width = 178,
        visibleCount = 21,
        scrollFrame = scroll,
        onClick = function(row)
            ns.PoiEditor.OnSelectPoi(row.id, row.name, row.desc, row.type, row.ownerType, row.ownerName or row.owner, row.iconKey, row.colorKey)
        end,
        renderRow = function(btn, row)
            if not btn.icon then
                btn.icon = btn:CreateTexture(nil, "ARTWORK")
                btn.icon:SetSize(16, 16)
                btn.icon:SetPoint("LEFT", btn, "LEFT", 4, 0)
            end
            local tex = ns.PoiIconForKey(row.iconKey, row.type)
            if not btn.icon:SetTexture(tex) then
                btn.icon:SetTexture(ns.PoiFallbackIconForKey(row.iconKey, row.type))
            end
            btn.icon:SetVertexColor(ns.PoiColorRgb(row.colorKey))

            local fs = btn.fs or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.fs = fs
            fs:SetPoint("LEFT", btn.icon, "RIGHT", 4, 0)
            fs:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
            fs:SetJustifyH("LEFT")
            fs:SetText(string.format("#%d %s", row.id, row.name or "?"))
        end,
    })

    -- Свойства и компактное превью рядом со списком.
    local EditSection = ns.CreateNGSection(f, "Свойства точки")
    EditSection:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -32)
    EditSection:SetPoint("BOTTOMRIGHT", ListSection, "BOTTOMLEFT", -8, 0)

    local CreateBtn = NNL.Widgets.CreateButton(EditSection, {text = "Создать здесь", width = 110, height = 24, style = "primary",
        tooltip = "Создать новую точку в позиции персонажа",
        tooltipLines = {"Владелец новой точки - ваш текущий персонаж. Имя, описание и цвет берутся из формы.",
            "После создания выберите новую точку в списке. Другого владельца и дополнительные свойства задайте через «Применить»."}})
    Ui.CreateBtn = CreateBtn
    CreateBtn:SetPoint("TOPLEFT", EditSection, "TOPLEFT", 10, -30)
    CreateBtn:SetScript("OnClick", function()
        ns.PoiEditor.SetStatus("Создаём POI...", "info")
        createPoiFromEditor()
    end)

    local SyncBtn = ns.CreateNGButton(EditSection, "Обновить", 84, 24)
    SyncBtn:SetPoint("LEFT", CreateBtn, "RIGHT", 4, 0)
    SyncBtn:SetScript("OnClick", function() runPoiCommand("poi sync") end)

    local DelBtn = NNL.Widgets.CreateButton(EditSection, {text = "Удалить", width = 76, height = 24, style = "danger"})
    Ui.DeleteBtn = DelBtn
    DelBtn:SetPoint("LEFT", SyncBtn, "RIGHT", 4, 0)
    DelBtn:SetScript("OnClick", function()
        local id = requireId()
        if id then
            ns.PoiEditor.SetStatus("Удаляем POI...", "warning")
            runPoiCommand("poi delete " .. id)
        end
    end)

    local IdLabel = ns.CreateNGLabel(EditSection, "ID")
    IdLabel:SetPoint("TOPLEFT", EditSection, "TOPLEFT", 70, -60)
    Ui.IdBox = ns.CreateNGEditBox(EditSection, "PoiId", 44, 22)
    Ui.IdBox:SetNumeric(true)
    Ui.IdBox:SetEnabled(false) -- selection comes from the server list, never a guessed new ID
    Ui.IdBox:SetPoint("TOPLEFT", EditSection, "TOPLEFT", 114, -60)

    local NameLabel = ns.CreateNGLabel(EditSection, "Имя")
    NameLabel:SetPoint("TOPLEFT", EditSection, "TOPLEFT", 70, -86)
    Ui.NameBox = ns.CreateNGEditBox(EditSection, "PoiName", 150, 22)
    Ui.NameBox:SetMaxLetters(MAX_NAME_LEN)
    Ui.NameBox:SetPoint("TOPLEFT", EditSection, "TOPLEFT", 114, -86)
    Ui.NameBox:SetPoint("RIGHT", EditSection, "RIGHT", -12, 0)

    local DescLabel = ns.CreateNGLabel(EditSection, "Описание")
    DescLabel:SetPoint("TOPLEFT", EditSection, "TOPLEFT", 10, -114)
    Ui.DescShell, Ui.DescBox = createMultilineEditBox(EditSection, "PoiDesc", 268, 52, MAX_DESC_LEN)
    Ui.DescShell:SetPoint("TOPLEFT", EditSection, "TOPLEFT", 10, -132)
    Ui.DescShell:SetPoint("TOPRIGHT", EditSection, "TOPRIGHT", -10, -132)

    local IconLabel = ns.CreateNGLabel(EditSection, "Тип")
    IconLabel:SetPoint("TOPLEFT", EditSection, "TOPLEFT", 10, -192)
    Ui.IconDropdown = NNL.Widgets.CreateDropdown(EditSection, { width = 210 })
    Ui.IconDropdown:SetPoint("TOPLEFT", EditSection, "TOPLEFT", 114, -192)

    local ColorLabel = ns.CreateNGLabel(EditSection, "Цвет")
    ColorLabel:SetPoint("TOPLEFT", EditSection, "TOPLEFT", 10, -222)
    Ui.ColorDropdown = NNL.Widgets.CreateDropdown(EditSection, { name = "NNPoiColorDropdown", width = 210 })
    Ui.ColorDropdown:SetPoint("TOPLEFT", EditSection, "TOPLEFT", 114, -222)

    local OwnerTypeLabel = ns.CreateNGLabel(EditSection, "Владелец")
    OwnerTypeLabel:SetPoint("TOPLEFT", EditSection, "TOPLEFT", 10, -252)
    Ui.OwnerTypeValue = 1
    Ui.OwnerTypeBox = NNL.Widgets.CreateDropdown(EditSection, {
        width = 210,
        menu = function(_, rootDescription)
            for _, entry in ipairs(ns.PoiOwnerTypes) do
                rootDescription:CreateRadio(entry.label,
                    function(value) return Ui.OwnerTypeValue == value end,
                    function(value) Ui.OwnerTypeValue = value; refreshPreview() end, entry.id)
            end
        end,
    })
    Ui.OwnerTypeBox:SetPoint("TOPLEFT", EditSection, "TOPLEFT", 114, -252)

    local OwnerNameLabel = ns.CreateNGLabel(EditSection, "Имя владельца")
    OwnerNameLabel:SetPoint("TOPLEFT", EditSection, "TOPLEFT", 10, -282)
    OwnerNameLabel:SetWidth(98)
    OwnerNameLabel:SetWordWrap(false)
    Ui.OwnerBox = ns.CreateNGEditBox(EditSection, "PoiOwner", 210, 22)
    Ui.OwnerBox:SetPoint("TOPLEFT", EditSection, "TOPLEFT", 114, -282)
    Ui.OwnerBox:SetScript("OnTextChanged", function() refreshPreview() end)

    Ui.IconPreview = EditSection:CreateTexture(nil, "ARTWORK")
    Ui.IconPreview:SetSize(48, 48)
    Ui.IconPreview:SetPoint("TOPLEFT", EditSection, "TOPLEFT", 10, -60)

    Ui.ApplyPositionCheck = CreateFrame("CheckButton", nil, EditSection, "UICheckButtonTemplate")
    Ui.ApplyPositionCheck:SetSize(26, 26)
    Ui.ApplyPositionCheck.text = Ui.ApplyPositionCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Ui.ApplyPositionCheck.text:SetPoint("LEFT", Ui.ApplyPositionCheck, "RIGHT", 2, 0)
    Ui.ApplyPositionCheck.text:SetText("Перенести точку к персонажу")

    local ApplyBtn = ns.CreateNGButton(EditSection, "Применить все изменения", 268, 24)
    Ui.ApplyBtn = ApplyBtn
    ApplyBtn:SetPoint("BOTTOMLEFT", EditSection, "BOTTOMLEFT", 10, 10)
    ApplyBtn:SetPoint("BOTTOMRIGHT", EditSection, "BOTTOMRIGHT", -10, 10)
    ApplyBtn:SetScript("OnClick", saveProperties)
    -- Keep the footer below the final owner row at the 820x500 shell minimum.
    Ui.ApplyPositionCheck:SetPoint("BOTTOMLEFT", ApplyBtn, "TOPLEFT", 0, 6)

    initIconDropdown()
    initColorDropdown()
    setIconDropdown("Misc")
    setColorDropdown(0)
    Ui.OwnerTypeBox:GenerateMenu()
    refreshAvailability()
    ns.Subscribe("ACCESS_CHANGED", "gm.poi-editor", refreshAvailability)

    return f
end
