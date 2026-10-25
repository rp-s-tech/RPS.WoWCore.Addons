-- Loaded through the NobleNextGM private extension namespace.
-- GM/Commands/Browser.lua — браузер определений /nn commands [search]

local _, ns = ...

local MODULE_NAME = "Команды"
local selectedDef = nil
local Ui = {}

local function allowed() return ns.Access and ns.Access.Allows(2) == true end
local function currentDef(def)
    if not allowed() or not ns.CommandDefinitions or not def then return nil end
    return ns.CommandDefinitions.Find(def)
end

local function trim(s)
    return (tostring(s or ""):match("^%s*(.-)%s*$")) or ""
end

local function destructiveLabel(d)
    if d == true then
        return "|cffff6666изменяет мир|r"
    end
    if d == false or d == nil then
        return "|cff88ff88только чтение / действие|r"
    end
    local s = tostring(d)
    if s == "delete" then
        return "|cffff4444удаление|r"
    end
    if s == "db" then
        return "|cffff9900изменяет базу|r"
    end
    if s == "metadata" then
        return "|cffffcc66изменяет метаданные|r"
    end
    return "|cffff9900" .. s .. "|r"
end

local function defPathString(def)
    if not def then
        return ""
    end
    if type(def.serverPath) == "string" and def.serverPath ~= "" then
        return def.serverPath
    end
    if type(def.path) == "table" then
        return table.concat(def.path, " ")
    end
    if type(def.path) == "string" then
        return def.path
    end
    return ""
end

local function buildTemplate(def)
    def = currentDef(def)
    if not def then
        return ""
    end
    if type(def.syntax) == "string" and def.syntax ~= "" then
        local s = def.syntax:gsub("^[Ss]yntax:%s*", "")
        s = trim(s)
        if s:sub(1, 1) ~= "." then
            s = "." .. s:gsub("^[%./]+", "")
        end
        return s
    end
    local defs = ns.CommandDefinitions
    if defs and type(defs.Format) == "function" then
        local ok, formatted = pcall(defs.Format, def, {})
        if ok and type(formatted) == "string" and formatted ~= "" then
            if formatted:sub(1, 1) ~= "." then
                formatted = "." .. formatted:gsub("^[%./]+", "")
            end
            return formatted
        end
    end
    local path = defPathString(def)
    if path == "" then
        return ""
    end
    local parts = { "." .. path:gsub("^[%./]+", "") }
    for _, arg in ipairs(def.args or {}) do
        local name = arg.name or "arg"
        if arg.required then
            parts[#parts + 1] = "<" .. name .. ">"
        else
            parts[#parts + 1] = "[" .. name .. "]"
        end
    end
    return table.concat(parts, " ")
end

local function isSafeExecute(def)
    def = currentDef(def)
    if not def then
        return false
    end
    if def.executable == false then return false end
    if def.destructive and def.destructive ~= false then
        return false
    end
    if def.responseMode == "structured" then
        return false
    end
    -- только без обязательных args (иначе шаблон невалиден)
    for _, arg in ipairs(def.args or {}) do
        if arg.required then
            return false
        end
    end
    return true
end

local function executeDef(def)
    def = currentDef(def)
    if not isSafeExecute(def) then
        ns.PrintError("Выполнение доступно только для безопасных команд без обязательных аргументов. Используйте \"Вставить\".")
        return false
    end
    -- Syntax is an editable template with placeholders, never executable text.
    local format = ns.CommandDefinitions and ns.CommandDefinitions.Format
    local ok, formatted = false, nil
    if type(format) == "function" then ok, formatted = pcall(format, def, {}) end
    local cmd = ok and type(formatted) == "string" and trim(formatted):gsub("^%.", "") or ""
    if cmd == "" then
        ns.PrintError("Не удалось собрать команду. Используйте «Вставить шаблон» и заполните аргументы.")
        return false
    end
    local sent
    if ns.EnqueueCommand then
        sent = ns.EnqueueCommand(cmd, { tag = "cmdbrowser:exec", requiredLevel = def.requiredLevel })
    elseif ns.RunGmCommand then
        sent = ns.RunGmCommand(cmd)
    else
        ns.PrintError("RunGmCommand недоступен.")
        return false
    end
    if not sent then return false end
    if ns.Print then
        ns.Print("Отправлено: ." .. cmd)
    end
    return true
end

local function insertIntoChat(text)
    if not allowed() then return false end
    text = trim(text)
    if text == "" then
        return false
    end
    if text:sub(1, 1) ~= "." then
        text = "." .. text:gsub("^[%./]+", "")
    end

    if not ns.Util.InsertTextIntoChat(text) then
        ns.PrintError("Строка ввода чата сейчас недоступна.")
        return false
    end
    ns.Print("Шаблон вставлен в чат (не отправлен): " .. text)
    return true
end

local function gatherDefs(filterText)
    if not allowed() then return {} end
    local defsApi = ns.CommandDefinitions
    if not defsApi then
        return {}
    end

    local filter = trim(filterText):lower()
    local list

    if type(defsApi.List) == "function" then
        local ok, result = pcall(defsApi.List, filter ~= "" and filter or nil)
        if ok and type(result) == "table" then
            list = result
        end
    end

    if type(list) ~= "table" then
        return {}
    end

    -- List() applies text and live role filters for every registered family.
    local out = {}
    for _, def in ipairs(list) do
        if type(def) == "table" then
            out[#out + 1] = def
        end
    end

    table.sort(out, function(a, b)
        return defPathString(a) < defPathString(b)
    end)
    return out
end

local function refreshDetail(def)
    def = currentDef(def)
    selectedDef = def
    if not Ui.Detail then
        return
    end
    if not def then
        Ui.Detail:SetText("Выберите команду из списка.\n\nКаталоги CommandDefinitions ещё не загружены или пусты.")
        return
    end
    local lines = {
        ns.Color("gold", defPathString(def)),
        "",
        ns.Color("white", "Синтаксис: ") .. (def.syntax or buildTemplate(def)),
        ns.Color("white", "Описание: ") .. (def.description or "-"),
        ns.Color("white", "Воздействие: ") .. destructiveLabel(def.destructive),
    }
    if def.examples and def.examples[1] then
        lines[#lines + 1] = ns.Color("white", "Пример: ") .. tostring(def.examples[1])
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = ns.Color("gray", "Клик - детали. Shift+клик или кнопка - вставить шаблон.")
    Ui.Detail:SetText(table.concat(lines, "\n"))
end

local function refreshList(filterText)
    local defs = gatherDefs(filterText)
    if Ui.CountLabel then
        Ui.CountLabel:SetText(string.format("Найдено: %d", #defs))
    end

    local rows = {}
    for index, def in ipairs(defs) do
        rows[#rows + 1] = {
            id = index,
            name = defPathString(def),
            desc = def.description or "",
            def = def,
            destructive = def.destructive,
        }
    end

    if Ui.List then
        Ui.List:SetRows(rows)
    end

    if selectedDef then
        local still = false
        local want = defPathString(selectedDef)
        for _, row in ipairs(rows) do
            if row.def == selectedDef or defPathString(row.def) == want then
                still = true
                selectedDef = row.def
                break
            end
        end
        if not still then
            selectedDef = rows[1] and rows[1].def or nil
        end
    elseif rows[1] then
        selectedDef = rows[1].def
    else
        selectedDef = nil
    end
    refreshDetail(selectedDef)
end

local function InitCommandsModule(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:Hide()

    local Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    Title:SetText("Команды")
    Title:SetTextColor(ns.COLORS.goldRaw.r, ns.COLORS.goldRaw.g, ns.COLORS.goldRaw.b)
    Title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)

    local Help = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    Help:SetText("Все доступные определения DM и GM. Вставка шаблона в чат без выполнения; права проверяет сервер.")
    Help:SetPoint("TOPLEFT", Title, "BOTTOMLEFT", 0, -4)
    Help:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    Help:SetJustifyH("LEFT")

    local SearchLabel = ns.CreateNGLabel(f, "Поиск:")
    SearchLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -48)

    Ui.SearchBox = ns.CreateNGEditBox(f, "CmdBrowserSearch", 280, 22)
    Ui.SearchBox:SetPoint("LEFT", SearchLabel, "RIGHT", 8, 0)
    Ui.SearchBox:SetScript("OnTextChanged", function(self)
        refreshList(self:GetText())
    end)
    Ui.SearchBox:SetScript("OnEnterPressed", function(self)
        refreshList(self:GetText())
        self:ClearFocus()
    end)

    Ui.CountLabel = ns.CreateNGLabel(f, "Найдено: 0")
    Ui.CountLabel:SetPoint("LEFT", Ui.SearchBox, "RIGHT", 12, 0)

    local InsertBtn = ns.CreateNGButton(f, "Вставить в чат", 120, 22)
    InsertBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -46)
    InsertBtn:SetScript("OnClick", function()
        if not selectedDef then
            ns.PrintError("Сначала выберите команду.")
            return
        end
        insertIntoChat(buildTemplate(selectedDef))
    end)

    local ListSection = ns.CreateNGSection(f, "Список")
    ListSection:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -78)
    ListSection:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
    ListSection:SetWidth(310)

    local scroll = CreateFrame("ScrollFrame", nil, ListSection, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", ListSection, "TOPLEFT", 8, -28)
    scroll:SetPoint("BOTTOMRIGHT", ListSection, "BOTTOMRIGHT", -28, 8)
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(270)
    scrollChild:SetHeight(24)
    scroll:SetScrollChild(scrollChild)

    Ui.List = ns.VirtualList.Create(scrollChild, {
        width = 268,
        rowHeight = 38,
        visibleCount = 12,
        scrollFrame = scroll,
        onClick = function(row)
            selectedDef = row.def
            refreshDetail(selectedDef)
            if IsShiftKeyDown and IsShiftKeyDown() then
                insertIntoChat(buildTemplate(selectedDef))
            end
        end,
        renderRow = function(btn, row)
            local fs = btn.fs or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.fs = fs
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -4)
            fs:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            if fs.SetMaxLines then fs:SetMaxLines(1) end
            local dest = ""
            if row.destructive and row.destructive ~= false then
                dest = " |cffff6666*|r"
            end
            fs:SetText((row.name or "?") .. dest)

            local sub = btn.sub or btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            btn.sub = sub
            sub:ClearAllPoints()
            sub:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 6, 3)
            sub:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            sub:SetJustifyH("LEFT")
            sub:SetWordWrap(false)
            if sub.SetMaxLines then sub:SetMaxLines(1) end
            -- Let FontString clip at a glyph boundary, never truncate UTF-8 bytes.
            sub:SetText(row.desc or "")
        end,
    })

    local DetailSection = ns.CreateNGSection(f, "Детали")
    DetailSection:SetPoint("TOPLEFT", ListSection, "TOPRIGHT", 10, 0)
    DetailSection:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)

    local detailScroll = CreateFrame("ScrollFrame", nil, DetailSection, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT", DetailSection, "TOPLEFT", 8, -28)
    detailScroll:SetPoint("BOTTOMRIGHT", DetailSection, "BOTTOMRIGHT", -28, 44)
    local detailChild = CreateFrame("Frame", nil, detailScroll)
    detailChild:SetWidth(250)
    detailChild:SetHeight(1)
    detailScroll:SetScrollChild(detailChild)

    Ui.Detail = detailChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Ui.Detail:SetPoint("TOPLEFT", detailChild, "TOPLEFT", 4, -2)
    Ui.Detail:SetPoint("TOPRIGHT", detailChild, "TOPRIGHT", -4, -2)
    Ui.Detail:SetJustifyH("LEFT")
    Ui.Detail:SetJustifyV("TOP")
    if Ui.Detail.SetNonSpaceWrap then
        Ui.Detail:SetNonSpaceWrap(true)
    end
    Ui.Detail:SetText("Выберите команду из списка.")

    detailScroll:SetScript("OnSizeChanged", function(self, width)
        local inner = math.max(80, (width or 0) - 8)
        detailChild:SetWidth(inner)
        if Ui.Detail then
            Ui.Detail:SetWidth(inner - 8)
            detailChild:SetHeight(math.max(1, (Ui.Detail:GetStringHeight() or 0) + 8))
        end
    end)

    local _refreshDetail = refreshDetail
    refreshDetail = function(def)
        _refreshDetail(def)
        if Ui.Detail and detailChild then
            local w = detailChild:GetWidth() or 250
            Ui.Detail:SetWidth(math.max(80, w - 8))
            detailChild:SetHeight(math.max(1, (Ui.Detail:GetStringHeight() or 0) + 8))
            detailScroll:SetVerticalScroll(0)
        end
    end

    local InsertBtn2 = ns.CreateNGButton(DetailSection, "Вставить шаблон", 130, 24)
    InsertBtn2:SetPoint("BOTTOMLEFT", DetailSection, "BOTTOMLEFT", 16, 12)
    InsertBtn2:SetScript("OnClick", function()
        if not selectedDef then
            ns.PrintError("Сначала выберите команду.")
            return
        end
        insertIntoChat(buildTemplate(selectedDef))
    end)

    local ExecBtn = ns.CreateNGButton(DetailSection, "Выполнить", 100, 24)
    ExecBtn:SetPoint("BOTTOMRIGHT", DetailSection, "BOTTOMRIGHT", -16, 12)
    ExecBtn:SetScript("OnClick", function()
        if not selectedDef then
            ns.PrintError("Сначала выберите команду.")
            return
        end
        executeDef(selectedDef)
    end)
    ExecBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Только безопасные команды без обязательных args", 1, 1, 1)
        GameTooltip:AddLine("Shift+клик по списку только вставляет шаблон в чат", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    ExecBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    f:SetScript("OnShow", function()
        local preset = Ui._pendingFilter
        Ui._pendingFilter = nil
        if preset and Ui.SearchBox then
            Ui.SearchBox:SetText(preset)
        end
        refreshList(Ui.SearchBox and Ui.SearchBox:GetText() or "")
    end)

    return f
end

function ns.ShowCommandsBrowser(search)
    if not allowed() then return false end
    search = trim(search)
    local module = ns.modules[MODULE_NAME]
    if module and module.frame and Ui.SearchBox then
        if search ~= "" then
            Ui.SearchBox:SetText(search)
        end
        ns.ShowModule(MODULE_NAME)
        refreshList(Ui.SearchBox:GetText())
        return
    end
    Ui._pendingFilter = (search ~= "") and search or nil
    ns.ShowModule(MODULE_NAME)
end

ns.RegisterModule(MODULE_NAME, InitCommandsModule, "Справочник GM-команд (gobject/lookup/npc/poi/tele/...)")

C_Timer.After(0, function()
    local function open(msg)
        ns.ShowCommandsBrowser(trim(msg))
    end
    ns.RegisterSlashCommand("NNCOMMANDS", open, "nncommands")
end)

ns.Subscribe("ACCESS_CHANGED", "gm.command-browser", function()
    refreshList(Ui.SearchBox and Ui.SearchBox:GetText() or "")
end)
