-- Use the native command channel to keep lookup RBAC, matching and limits.
local _, ns = ...
local NNL = LibStub("NobleNextLib-1.0")
local Search = {}
ns.GobObjectSearch = Search

local PREFIX, PAGE_SIZE, MAX_RESULTS = "TrinityCore", 50, 1000
local alphabet, echoSpace = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz", 62^3
local sequence, issued = math.random(0, echoSpace - 1), 0
local pending, selected, win, ui
local mode = "lookup"
local rows, page, notice = {}, 1, ""
local statusText = "Введите название объекта и нажмите «Найти»."
local rebuild

local function allowed()
    return ns.Access and ns.Access.Allows(2)
end

local function text(value)
    return type(value) == "string" and not (issecretvalue and issecretvalue(value)) and value or ""
end

local function display(value)
    return (value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "||"))
end

local function queryText(value)
    return text(value):match("^%s*(.-)%s*$") or ""
end

local function render()
    if not ui then return end
    local ready = allowed() and not pending
    ui.status:SetText(statusText)
    ui.query:SetEnabled(mode == "lookup")
    ui.search:SetText(mode == "nearby" and "Обновить" or "Найти")
    ui.hint:SetText(mode == "nearby" and "Радар: объекты текущей фазы в радиусе 50 метров. Выберите объект для редактирования."
        or "Все слова должны встречаться в названии. Например: wmo kobold house")
    ui.search:SetEnabled(ready and true or false)
    ui.previous:SetEnabled(ready and page > 1 or false)
    ui.next:SetEnabled(ready and page * PAGE_SIZE < #rows or false)
    ui.spawn:SetEnabled(ready and selected ~= nil or false)
    ui.temporary:SetEnabled(ready and selected ~= nil or false)
    ui.page:SetText(tostring(page))
    ui.selected:SetText(selected and string.format("Выбрано: %s\nEntry: %d", display(selected.name), selected.entry)
        or (mode == "nearby" and "Выберите объект в списке для редактирования." or "Выберите объект в списке для установки."))
    ui.empty:SetShown(#rows == 0)
    ui.empty:SetText(pending and "Идёт поиск..." or (mode == "nearby" and "Рядом нет сохранённых объектов текущей фазы."
        or "Введите или уточните слова из названия и нажмите «Найти»."))
    ui.list:Refresh()
end

local function setStatus(value)
    statusText = value
    render()
end

local function resultStatus()
    statusText = #rows > 0 and string.format("Найдено: %d. Страница %d/%d. Результаты: %d–%d.", #rows, page,
        math.max(1, math.ceil(#rows / PAGE_SIZE)), #rows > 0 and (page - 1) * PAGE_SIZE + 1 or 0,
        math.min(page * PAGE_SIZE, #rows)) or "Объекты не найдены. Уточните слова запроса."
    if notice ~= "" then statusText = statusText .. "\n" .. notice end
end

rebuild = function()
    local visible = {}
    for i = (page - 1) * PAGE_SIZE + 1, math.min(page * PAGE_SIZE, #rows) do visible[#visible + 1] = rows[i] end
    ui.list:SetRows(visible)
    render()
end

local function fail(value)
    pending = nil
    setStatus(value)
end

local function beginSearch()
    if not allowed() or pending then return end
    local query = mode == "nearby" and "" or queryText(ui.query:GetText())
    local _, length = query:gsub("[^\128-\191]", "")
    if mode == "lookup" and (length < 2 or query:find("%c") or query:find("|", 1, true)) then
        setStatus("Введите слова из названия объекта, минимум два символа, без ссылок и переносов строк.")
        return
    end
    local command = mode == "nearby" and "gobject near 50" or ("lookup object like " .. query)
    if #command + 5 > 255 then setStatus("Сократите поисковый запрос."); return end
    local character = text(UnitGUID("player"))
    local name = text(UnitName("player"))
    if character == "" or name == "" or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
        setStatus("Поиск недоступен. Дождитесь входа в мир и обновите интерфейс.")
        return
    end
    if issued >= echoSpace then setStatus("Обновите интерфейс командой /reload, чтобы продолжить поиск."); return end
    issued, sequence = issued + 1, (sequence + 1) % echoSpace
    -- Access discovery uses alphanumeric echoes; reserve a separate namespace.
    local n, parts = sequence, { "!" }
    for i = 4, 2, -1 do
        local digit = n % 62
        parts[i], n = alphabet:sub(digit + 1, digit + 1), math.floor(n / 62)
    end
    local token = { echo = table.concat(parts), character = character, query = query, mode = mode, rows = {}, seen = {}, notices = {} }
    pending, selected, rows, page, notice = token, nil, {}, 1, ""
    statusText = mode == "nearby" and "Загрузка ближайших объектов..." or ("Идёт поиск: " .. display(query))
    rebuild()
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, "i" .. token.echo .. command, "WHISPER", name)
    local codes = Enum and Enum.SendAddonMessageResult
    if not ok or result == false or (codes and type(result) == "number" and result ~= codes.Success) then
        fail("Не удалось отправить поиск. Повторите запрос.")
        return
    end
    C_Timer.After(12, function()
        if pending == token then fail("Ответ не получен. Повторите поиск; установка автоматически не выполняется.") end
    end)
end

local function spawn(temporary)
    if not allowed() or pending or not selected then return end
    local command = (temporary and "gobject add temp " or "gobject add ") .. tostring(selected.entry)
    if ns.RunGmCommand(command) then
        setStatus("Команда установки отправлена. Подтверждение сервера появится в чате.")
    else
        setStatus("Не удалось отправить команду установки.")
    end
end

local function createWindow()
    win = NNL.Window.CreateMini({ name = "NobleNextObjectSearch", title = "Поиск объектов",
        icon = "Interface\\Icons\\inv_misc_spyglass_03", width = 660, height = 560, strata = "HIGH", closeOnEscape = true })
    local body = win:GetContent()
    ui = {}
    local hint = ns.CreateNGLabel(body, "Все слова должны встречаться в названии. Например: wmo kobold house")
    ui.hint = hint
    hint:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -10)
    hint:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -10)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)
    ui.search = ns.CreateNGButton(body, "Найти", 84, 24)
    ui.search:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -32)
    ui.search:SetScript("OnClick", beginSearch)
    ui.query = ns.CreateNGEditBox(body, "ObjectSearch_Query", 400, 24)
    ui.query:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -32)
    ui.query:SetPoint("RIGHT", ui.search, "LEFT", -8, 0)
    ui.query:SetScript("OnEnterPressed", function(self) self:ClearFocus(); beginSearch() end)
    ui.query:SetScript("OnTextChanged", function()
        if pending and queryText(ui.query:GetText()) ~= pending.query then
            fail("Запрос изменён. Нажмите «Найти».")
        elseif not pending and (#rows > 0 or selected) then
            selected, rows, page, notice = nil, {}, 1, ""
            statusText = "Запрос изменён. Нажмите «Найти»."
            rebuild()
        end
    end)
    ui.status = ns.CreateNGLabel(body, statusText)
    ui.status:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -64)
    ui.status:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -64)
    ui.status:SetHeight(32)
    ui.status:SetJustifyH("LEFT")
    ui.status:SetWordWrap(true)

    local section = ns.CreateNGSection(body)
    section:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -100)
    section:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 104)
    ui.list = NNL.Scroll.CreateList(section, {
        rowHeight = 40,
        onClick = function(row)
            if not allowed() or pending then return end
            selected = row
            local mover = _G.NobleNextGobMover
            if mover and mover.SelectTemplate then mover.SelectTemplate(row.entry, row.name) end
            if row.guid and mover and mover.SetTarget then mover.SetTarget(row.guid, row.name, row.phaseId, row.entry) end
            render()
        end,
        renderRow = function(button, row)
            if not button.title then
                button.title = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                button.title:SetPoint("TOPLEFT", button, "TOPLEFT", 8, -5)
                button.title:SetPoint("TOPRIGHT", button, "TOPRIGHT", -8, -5)
                button.title:SetJustifyH("LEFT")
                button.title:SetWordWrap(false)
                button.meta = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                button.meta:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 8, 5)
                button.meta:SetTextColor(0.7, 0.7, 0.7)
                button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                button:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(self.title:GetText(), 1, 0.82, 0, true)
                    GameTooltip:AddLine(self.meta:GetText(), 0.8, 0.8, 0.8)
                    GameTooltip:Show()
                end)
                button:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
            NNL.Theme.Apply(button, row == selected and "rowSelected" or "row")
            button:SetEnabled(allowed() and not pending or false)
            button.title:SetText(display(row.name))
            button.meta:SetText("Entry: " .. row.entry .. (row.guid and ("  |  GUID: " .. row.guid) or ""))
        end,
    })
    ui.list:SetPoint("TOPLEFT", section, "TOPLEFT", 6, -6)
    ui.list:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", -8, 6)
    ui.empty = ns.CreateNGLabel(section, "")
    ui.empty:SetPoint("TOPLEFT", section, "TOPLEFT", 14, -16)
    ui.empty:SetPoint("TOPRIGHT", section, "TOPRIGHT", -30, -16)
    ui.empty:SetJustifyH("LEFT")
    ui.empty:SetWordWrap(true)
    ui.selected = ns.CreateNGLabel(body, "")
    ui.selected:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 12, 58)
    ui.selected:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 58)
    ui.selected:SetHeight(36)
    ui.selected:SetJustifyH("LEFT")
    ui.selected:SetWordWrap(true)
    ui.spawn = ns.CreateNGButton(body, "Поставить здесь", 160, 24)
    ui.spawn:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 12, 14)
    ui.spawn:SetScript("OnClick", function() spawn(false) end)
    ui.temporary = NNL.Widgets.CreateButton(body, { text = "Поставить временно", width = 164, height = 24,
        tooltip = "Временный объект не сохраняется сам. Для сохранения его нужно запечь.", onClick = function() spawn(true) end })
    ui.temporary:SetPoint("LEFT", ui.spawn, "RIGHT", 8, 0)
    ui.next = ns.CreateNGButton(body, "Далее", 64, 24)
    ui.next:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 14)
    ui.page = ns.CreateNGEditBox(body, "ObjectSearch_Page", 38, 24)
    ui.page:SetPoint("RIGHT", ui.next, "LEFT", -6, 0)
    ui.page:SetNumeric(true)
    ui.previous = ns.CreateNGButton(body, "Назад", 64, 24)
    ui.previous:SetPoint("RIGHT", ui.page, "LEFT", -6, 0)
    local function goToPage(number)
        if pending or not allowed() then return end
        if number and number == math.floor(number) and number >= 1 and number <= math.max(1, math.ceil(#rows / PAGE_SIZE)) then
            page = number; resultStatus(); rebuild()
        else
            render()
        end
    end
    ui.previous:SetScript("OnClick", function() goToPage(page - 1) end)
    ui.next:SetScript("OnClick", function() goToPage(page + 1) end)
    ui.page:SetScript("OnEnterPressed", function(self) self:ClearFocus(); goToPage(tonumber(self:GetText())) end)
    win.frame:HookScript("OnHide", function()
        if pending then fail("Поиск закрыт. Нажмите «Найти», чтобы повторить запрос.") end
    end)
    rebuild()
end

function Search.Open(query)
    if not allowed() then return false end
    if mode ~= "lookup" then
        mode, pending, selected, rows, page, notice = "lookup", nil, nil, {}, 1, ""
    end
    if not win then createWindow() end
    win:SetMinimized(false)
    win:Show()
    query = queryText(query)
    if query ~= "" then
        ui.query:SetText(query)
        beginSearch()
    else
        ui.query:SetFocus()
    end
    rebuild()
    return true
end

function Search.OpenNearby()
    if not allowed() then return false end
    if not win then createWindow() end
    mode, pending, selected, rows, page, notice = "nearby", nil, nil, {}, 1, ""
    ui.query:SetText("")
    win:SetMinimized(false)
    win:Show()
    beginSearch()
    return true
end

ns.RegisterAddonPrefix(PREFIX, function(_, message, channel, sender)
    local token = pending
    if not token or not allowed() or channel ~= "WHISPER" or text(sender) == "" or not ns.Util.IsSelfSender(sender)
        or text(UnitGUID("player")) ~= token.character or text(message) == "" or message:sub(2, 5) ~= token.echo then return end
    local opcode, body = message:sub(1, 1), message:sub(6)
    if opcode == "a" and body == "" then
        token.ack = true
    elseif opcode == "m" and token.ack then
        local rawEntry, name = body:match("|Hgameobject_entry:(%d+)|h%[(.-)%]|h")
        local guid
        if token.mode == "nearby" then
            rawEntry = body:match("Entry:%s*(%d+)")
            local rawGuid, label = body:match("|Hgameobject:(%d+)|h%[(.-)%]|h")
            guid = tonumber(rawGuid)
            name = label and label:match("^(.-)%s+X:")
            if not guid or guid <= 0 or guid > 9007199254740991 or not name then rawEntry = nil end
        end
        local entry = tonumber(rawEntry)
        local key = guid or entry
        if entry and entry > 0 and entry <= 4294967295 then
            if not token.seen[key] then
                if #token.rows < MAX_RESULTS then
                    token.seen[key] = true
                    token.rows[#token.rows + 1] = { entry = entry, name = name, guid = guid, phaseId = tonumber(body:match("%[RP phase: (%d+)%]")) }
                else token.truncated = true end
            end
        elseif #token.notices < 3 then
            token.notices[#token.notices + 1] = display(body)
        end
    elseif (opcode == "o" or opcode == "f") and body == "" then
        if opcode == "f" or not token.ack then
            fail("Сервер отклонил поиск. " .. table.concat(token.notices, " "))
            return
        end
        pending, rows, page = nil, token.rows, 1
        if token.mode == "lookup" then table.sort(rows, function(a, b) return a.entry < b.entry end) end
        notice = table.concat(token.notices, " ")
        if token.truncated then notice = "Показаны первые " .. MAX_RESULTS .. " объектов. Уточните запрос. " .. notice end
        resultStatus()
        rebuild()
    end
end, { key = "gm-object-search" })

ns.RegisterSlashCommand("NNGOBSEARCH", Search.Open, { "nngobsearch" })
if ns.RegisterQuickAction then
    ns.RegisterQuickAction({ id = "gobsearch", title = "Поиск объектов", icon = "Interface\\Icons\\inv_misc_spyglass_03",
        order = 204, requiredLevel = 2, allowInCombat = true, onClick = function() return Search.Open() end })
end
ns.Subscribe("ACCESS_CHANGED", "gm-object-search", function()
    if not allowed() then
        pending, selected, rows, page, notice = nil, nil, {}, 1, ""
        statusText = "Для поиска объектов требуется подтверждённый доступ ГМ."
        if ui then rebuild(); win:Hide() end
    end
end)
