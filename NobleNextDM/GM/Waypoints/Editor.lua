-- Shared DM/GM editor for NobleNext route drafts and saved snapshots.
local _, ns = ...
local PAGE_SIZE = 50
local ACTION_NAMES = { [1] = "Бег", [2] = "Пауза", [3] = "Шаг", [4] = "Посадка", [5] = "Взлёт" }
local serial = 0

local function Integer(text, minimum, maximum)
    local n = tonumber(text)
    if n and n == math.floor(n) and n >= minimum and n <= maximum then return n end
end

local function InitEditor(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:Hide()
    local snapshot, pending, selected
    local rows, actions = {}, {}
    local request, render

    local title = ns.CreateNGLabel(f, "Точки маршрута выбранного НИП")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    local status = ns.CreateNGLabel(f, "Выберите НИП и обновите список.")
    status:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -74)
    status:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -74)
    status:SetHeight(32)
    status:SetWordWrap(true)
    status:SetJustifyH("LEFT")

    local function Button(text, width, anchor, point, x, y)
        local b = ns.CreateNGButton(f, text, width, 24)
        b:SetPoint("TOPLEFT", anchor, point, x, y)
        return b
    end
    local refresh = Button("Обновить", 96, f, "TOPLEFT", 12, -40)
    local start = Button("Запустить", 88, refresh, "TOPRIGHT", 6, 0)
    local bake = Button("Запечь", 76, start, "TOPRIGHT", 6, 0)
    local previous = Button("Назад", 58, bake, "TOPRIGHT", 10, 0)
    local pageBox = ns.CreateNGEditBox(f, nil, 38, 24)
    pageBox:SetPoint("LEFT", previous, "RIGHT", 6, 0)
    pageBox:SetNumeric(true)
    pageBox:SetText("1")
    local nextPage = Button("Далее", 58, pageBox, "TOPRIGHT", 6, 0)

    local section = ns.CreateNGSection(f, "Действия маршрута")
    section:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -112)
    section:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 48)
    local list = ns.NNL.Scroll.CreateList(section, {
        rowHeight = 44,
        onClick = function(p)
            if snapshot and not pending and snapshot.Status ~= "saving" then selected = p.Index; render() end
        end,
        renderRow = function(row, p)
            if not row.title then
                row.current = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.current:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
                row.current:SetWidth(72)
                row.current:SetJustifyH("RIGHT")
                row.current:SetTextColor(0.45, 0.9, 0.6)
                row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -5)
                row.title:SetPoint("RIGHT", row.current, "LEFT", -6, 0)
                row.title:SetJustifyH("LEFT")
                row.title:SetWordWrap(false)
                row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.meta:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 6)
                row.meta:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 6)
                row.meta:SetJustifyH("LEFT")
                row.meta:SetWordWrap(false)
                row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                row:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(self.title:GetText(), 1, 0.82, 0)
                    GameTooltip:AddLine(self.meta:GetText(), 0.8, 0.8, 0.8, true)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
            local isSelected = selected == p.Index
            ns.NNL.Theme.Apply(row, isSelected and "rowSelected" or "row")
            row:SetEnabled(not pending and snapshot.Status ~= "saving")
            row.title:SetText(string.format("%d. %s", p.Index, ACTION_NAMES[p.Kind]))
            row.title:SetTextColor(isSelected and 1 or 0.92, isSelected and 0.82 or 0.92, isSelected and 0 or 0.92)
            row.current:SetText(snapshot.Current == p.Index and "Текущая" or "")
            local text = p.Kind == 2 and string.format("Пауза %.3g с", p.Wait / 1000)
                or string.format("X %.2f, Y %.2f, Z %.2f", p.X, p.Y, p.Z)
            if p.Kind ~= 2 and p.Wait > 0 then text = text .. string.format(", пауза %.3g с", p.Wait / 1000) end
            if p.Emote > 0 then text = text .. string.format(", эмоция %d", p.Emote) end
            row.meta:SetText(text)
        end,
    })
    list:SetPoint("TOPLEFT", section, "TOPLEFT", 6, -26)
    list:SetPoint("BOTTOMRIGHT", section, "BOTTOMRIGHT", -8, 8)
    -- Keep the list's data array: SetRows resets the native scroll position.
    list:SetRows(rows)
    local empty = ns.CreateNGLabel(section, "В маршруте пока нет действий.")
    empty:SetPoint("TOPLEFT", section, "TOPLEFT", 14, -32)

    local up = Button("Выше", 64, f, "BOTTOMLEFT", 12, 36)
    local down = Button("Ниже", 64, up, "TOPRIGHT", 6, 0)
    local remove = Button("Удалить", 80, down, "TOPRIGHT", 6, 0)
    local swapLabel = ns.CreateNGLabel(f, "С номером")
    swapLabel:SetPoint("LEFT", remove, "RIGHT", 12, 0)
    local swapBox = ns.CreateNGEditBox(f, nil, 42, 24)
    swapBox:SetPoint("LEFT", swapLabel, "RIGHT", 6, 0)
    swapBox:SetNumeric(true)
    local swap = Button("Обменять", 90, swapBox, "TOPRIGHT", 6, 0)
    actions = { up, down, remove, swap }

    render = function()
        local ready = snapshot and not pending and snapshot.Status ~= "saving"
        local editable = ready and not snapshot.Native and snapshot.Revision > 0
        for i = #rows, 1, -1 do rows[i] = nil end
        if snapshot then
            for index = (snapshot.Page - 1) * PAGE_SIZE + 1, math.min(snapshot.Page * PAGE_SIZE, snapshot.Total) do
                rows[#rows + 1] = snapshot.Points[index]
            end
        end
        list:Refresh()
        empty:SetShown(snapshot ~= nil and snapshot.Total == 0 and not pending)
        for _, b in ipairs(actions) do b:SetEnabled(editable and selected ~= nil or false) end
        up:SetEnabled(editable and selected and selected > 1 or false)
        down:SetEnabled(editable and selected and selected < snapshot.Total or false)
        start:SetEnabled(editable and snapshot.Total > 0 or false)
        bake:SetEnabled(editable and true or false)
        previous:SetEnabled(ready and snapshot.Page > 1 or false)
        nextPage:SetEnabled(ready and snapshot.Page * PAGE_SIZE < snapshot.Total or false)
    end

    request = function(page, verb, first, second)
        local target = UnitGUID("target")
        if not target or not target:match("^Creature%-") then
            snapshot, pending, selected = nil, nil, nil
            status:SetText("Выберите НИП и обновите список.")
            render()
            return
        end
        serial = serial + 1
        local samePage = snapshot and snapshot.Guid:lower() == target:lower() and snapshot.Page == page
        local command
        if verb and snapshot then
            command = string.format(".%s %d%s %d %s %d %d %d", verb, first,
                second and (" " .. second) or "", snapshot.Revision, snapshot.Guid, page, serial, PAGE_SIZE)
        else
            command = string.format(".wplist %d %d %s %d", page, serial, target, PAGE_SIZE)
        end
        local token = { Id = serial, Target = target, Page = page,
            Selected = samePage and not verb and selected, Revision = snapshot and snapshot.Revision }
        pending = token
        if not samePage then snapshot, selected = nil, nil end
        status:SetText("Ожидание списка от сервера...")
        render()
        if not samePage then list.Scroll:SetVerticalScroll(0) end
        if not ns.RunGmCommand(command) then
            pending, snapshot, selected = nil, nil, nil
            status:SetText("Не удалось отправить запрос. Обновите список.")
            render()
            return
        end
        C_Timer.After(12, function()
            if pending == token then
                pending, snapshot, selected = nil, nil, nil
                status:SetText("Ответ не получен. Обновите список; изменения автоматически не повторяются.")
                render()
            end
        end)
    end

    local function SwapWith(index)
        if snapshot and selected and index and index >= 1 and index <= snapshot.Total then
            request(snapshot.Page, "wpswap", selected, index)
        end
    end
    up:SetScript("OnClick", function() if selected then SwapWith(selected - 1) end end)
    down:SetScript("OnClick", function() if selected then SwapWith(selected + 1) end end)
    swap:SetScript("OnClick", function() SwapWith(Integer(swapBox:GetText(), 1, snapshot and snapshot.Total or 0)) end)
    remove:SetScript("OnClick", function()
        if snapshot and selected then request(snapshot.Page, "wpremove", selected) end
    end)
    refresh:SetScript("OnClick", function() request(snapshot and snapshot.Page or 1) end)
    previous:SetScript("OnClick", function() if snapshot then request(snapshot.Page - 1) end end)
    nextPage:SetScript("OnClick", function() if snapshot then request(snapshot.Page + 1) end end)
    pageBox:SetScript("OnEnterPressed", function(self)
        local page = Integer(self:GetText(), 1, snapshot and math.max(1, math.ceil(snapshot.Total / PAGE_SIZE)) or 1)
        if page then request(page) end
        self:ClearFocus()
    end)
    start:SetScript("OnClick", function()
        if not snapshot or (UnitGUID("target") or ""):lower() ~= snapshot.Guid:lower() then request(1);return end
        if ns.RunGmCommand(".wpgo") then request(snapshot.Page) end
    end)
    bake:SetScript("OnClick", function()
        if not snapshot or (UnitGUID("target") or ""):lower() ~= snapshot.Guid:lower() then request(1);return end
        if ns.RunGmCommand(".rps persist wp-bake") then
            snapshot, selected = nil, nil
            status:SetText("Дождитесь подтверждения сохранения в чате, затем обновите список.")
            render()
        end
    end)

    ns.RegisterAddonPrefix("NN_WAYPOINTS", function(_, message, _, sender)
        if not pending or not ns.Util.IsSelfSender(sender) or UnitGUID("target") ~= pending.Target then return end
        local fields = {}
        for part in (message .. "|"):gmatch("([^|]*)|") do fields[#fields + 1] = part end
        if tonumber(fields[2]) ~= pending.Id then return end
        if fields[1] == "ERROR" then
            pending, snapshot, selected = nil, nil, nil
            status:SetText("Список изменился или НИП недоступен. Проверьте выделение и обновите список.")
            render()
        elseif fields[1] == "PAGE" and #fields == 8 then
            local revision = Integer(fields[4], 0, 4294967295)
            local total = Integer(fields[5], 0, 4294967295)
            local page = Integer(fields[6], 1, 536870912)
            local current = Integer(fields[7], 0, 4294967295)
            if revision and total and page and current and page <= math.max(1, math.ceil(total / PAGE_SIZE))
                and fields[3]:lower() == pending.Target:lower()
                and ({ saving = true, blocked = true, running = true, stopped = true })[fields[8]] then
                pending.Data = { Guid = fields[3], Revision = revision, Total = total, Page = page,
                    Current = current, Status = fields[8], Points = {} }
            end
        elseif fields[1] == "SOURCE" and #fields == 5 and pending.Data then
            local data = pending.Data
            local path = Integer(fields[5], 0, 4294967295)
            if tonumber(fields[3]) == data.Revision and path and (fields[4] == "native" or fields[4] == "draft") then
                data.Native, data.PathId = fields[4] == "native", path
            end
        elseif fields[1] == "POINT" and #fields == 10 and pending.Data then
            local data = pending.Data
            local index = Integer(fields[4], (data.Page - 1) * PAGE_SIZE + 1, math.min(data.Page * PAGE_SIZE, data.Total))
            local kind = Integer(fields[5], 1, 5)
            local x, y, z = tonumber(fields[6]), tonumber(fields[7]), tonumber(fields[8])
            local wait, emote = Integer(fields[9], 0, 4294967295), Integer(fields[10], 0, 4294967295)
            if tonumber(fields[3]) == data.Revision and index and kind and x and y and z and wait and emote
                and math.abs(x) < math.huge and math.abs(y) < math.huge and math.abs(z) < math.huge then
                data.Points[index] = { Index = index, Kind = kind, X = x, Y = y, Z = z, Wait = wait, Emote = emote }
            end
        elseif fields[1] == "END" and pending.Data and tonumber(fields[3]) == pending.Data.Revision then
            local data = pending.Data
            local token = pending
            pending = nil
            for index = (data.Page - 1) * PAGE_SIZE + 1, math.min(data.Page * PAGE_SIZE, data.Total) do
                if not data.Points[index] then
                    snapshot, selected = nil, nil
                    status:SetText("Получен неполный список. Обновите страницу.")
                    render()
                    return
                end
            end
            snapshot = data
            selected = data.Page == token.Page and data.Revision == token.Revision and token.Selected or nil
            pageBox:SetText(tostring(data.Page))
            local state = data.Status == "blocked" and ("Недостижимо действие " .. data.Current)
                or data.Status == "saving" and "Сохранение" or data.Status == "running" and "Выполняется" or "Остановлен"
            if data.Native then
                status:SetText(string.format("Штатный маршрут %d. %s. Точек: %d. Страница %d/%d. Только просмотр.",
                    data.PathId, state, data.Total, data.Page, math.max(1, math.ceil(data.Total / PAGE_SIZE))))
            else
                status:SetText(string.format("%s. Действий: %d. Страница %d/%d. Правки временные до «Запечь».",
                    state, data.Total, data.Page, math.max(1, math.ceil(data.Total / PAGE_SIZE))))
            end
            render()
            if data.Page ~= token.Page then list.Scroll:SetVerticalScroll(0) end
        end
    end, { key = "waypoint_editor" })

    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:SetScript("OnEvent", function() if f:IsShown() then request(1) end end)
    f:SetScript("OnShow", function() request(1) end)
    f:SetScript("OnHide", function() pending, snapshot, selected = nil, nil, nil; render() end)
    render()
    return f
end

ns.RegisterModule("Точки маршрута", InitEditor, "Все точки, паузы и эмоции НИП: просмотр, удаление и обмен местами")
