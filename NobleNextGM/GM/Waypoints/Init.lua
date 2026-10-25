-- Loaded through the NobleNextGM private extension namespace.
-- GM/Waypoints/Init.lua — маршруты NPC

local _, ns = ...

local function SendGmCommand(cmd)
    if not ns.RunGmCommand(cmd) then
        ns.PrintError("Не удалось отправить команду: " .. tostring(cmd))
    end
end

local function Describe(button, text)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(text, 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function ReadNumber(box, label, minimum, maximum, integer)
    local value = tonumber(((box:GetText() or ""):gsub(",", ".")))
    if not value or value ~= value or value < minimum or value > maximum
        or (integer and value ~= math.floor(value)) then
        ns.PrintError(string.format("%s: введите %s от %s до %s.", label,
            integer and "целое число" or "число", tostring(minimum), tostring(maximum)))
        return nil
    end
    return value
end

local function ReadSeconds(box)
    -- WaypointsService converts seconds * 1000 to uint32 milliseconds.
    -- Leave room for float rounding at the upper edge of that conversion.
    return ReadNumber(box, "Время в секундах", 0.5, 4294967, false)
end

-- ---------------------------------------------------------------------------
-- Module initialization
-- ---------------------------------------------------------------------------
local function InitWaypointsModule(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:Hide()

    local Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    Title:SetText("Маршруты NPC")
    Title:SetTextColor(ns.COLORS.goldRaw.r, ns.COLORS.goldRaw.g, ns.COLORS.goldRaw.b)
    Title:SetPoint("TOP", f, "TOP", 0, -10)

    local RecordSection = ns.CreateNGSection(f, "Запись маршрута", nil, 220)
    RecordSection:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -40)
    RecordSection:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -40)

    local btnY = -36

    local MoveBtn = ns.CreateNGButton(RecordSection, "Точка: бег", 130, 26)
    Describe(MoveBtn, "Добавить в маршрут точку в позиции персонажа. NPC добежит до неё после запуска маршрута.")
    MoveBtn:SetPoint("TOPLEFT", RecordSection, "TOPLEFT", 20, btnY)
    MoveBtn:SetScript("OnClick", function()
        SendGmCommand(".wpmove")
    end)

    local WalkBtn = ns.CreateNGButton(RecordSection, "Точка: шаг", 130, 26)
    Describe(WalkBtn, "Добавить в маршрут точку в позиции персонажа. NPC дойдёт до неё шагом после запуска маршрута.")
    WalkBtn:SetPoint("TOPLEFT", MoveBtn, "TOPRIGHT", 15, 0)
    WalkBtn:SetScript("OnClick", function()
        SendGmCommand(".wpwalk")
    end)

    local ClearBtn = ns.CreateNGButton(RecordSection, "Очистить маршрут", 130, 26)
    Describe(ClearBtn, "Остановить маршрут выбранного NPC и удалить все записанные точки.")
    ClearBtn:SetPoint("TOPLEFT", WalkBtn, "TOPRIGHT", 15, 0)
    ClearBtn:SetScript("OnClick", function()
        ns.Confirm.Show({
            text = "Удалить все точки маршрута выбранного NPC?",
            onAccept = function()
                SendGmCommand(".wpclear")
            end,
        })
    end)

    btnY = btnY - 45

    local WaitLabel = ns.CreateNGLabel(RecordSection, "Ожидание (сек):")
    WaitLabel:SetPoint("TOPLEFT", RecordSection, "TOPLEFT", 20, btnY + 4)

    local WaitBox = ns.CreateNGEditBox(RecordSection, "WpWaitBox", 60, 24)
    WaitBox:SetPoint("LEFT", WaitLabel, "RIGHT", 10, 0)
    WaitBox:SetText("2")

    local WaitBtn = ns.CreateNGButton(RecordSection, "Добавить паузу", 120, 26)
    Describe(WaitBtn, "Добавить ожидание в конец маршрута. Сервер принимает длительность от 0.5 секунды.")
    WaitBtn:SetPoint("LEFT", WaitBox, "RIGHT", 10, 0)
    WaitBtn:SetScript("OnClick", function()
        local seconds = ReadSeconds(WaitBox)
        if seconds then SendGmCommand(".wpwait " .. tostring(seconds)) end
    end)

    btnY = btnY - 45

    local EmoteLabel = ns.CreateNGLabel(RecordSection, "ID эмоции:")
    EmoteLabel:SetPoint("TOPLEFT", RecordSection, "TOPLEFT", 20, btnY + 4)

    local EmoteBox = ns.CreateNGEditBox(RecordSection, "WpEmoteBox", 60, 24)
    EmoteBox:SetPoint("LEFT", EmoteLabel, "RIGHT", 10, 0)
    EmoteBox:SetNumeric(true)
    EmoteBox:SetText("1")

    local EmoteTimeLabel = ns.CreateNGLabel(RecordSection, "Время (сек):")
    EmoteTimeLabel:SetPoint("LEFT", EmoteBox, "RIGHT", 15, 0)

    local EmoteTimeBox = ns.CreateNGEditBox(RecordSection, "WpEmoteTimeBox", 60, 24)
    EmoteTimeBox:SetPoint("LEFT", EmoteTimeLabel, "RIGHT", 10, 0)
    EmoteTimeBox:SetText("3")

    local EmoteBtn = ns.CreateNGButton(RecordSection, "Добавить", 100, 26)
    Describe(EmoteBtn, "Добавить в конец маршрута эмоцию на указанное время. ID берётся из Emotes; длительность от 0.5 секунды.")
    EmoteBtn:SetPoint("LEFT", EmoteTimeBox, "RIGHT", 10, 0)
    EmoteBtn:SetScript("OnClick", function()
        local emote = ReadNumber(EmoteBox, "ID эмоции", 0, 4294967295, true)
        local seconds = ReadSeconds(EmoteTimeBox)
        if emote and seconds then
            SendGmCommand(string.format(".wpemote %d %s", emote, tostring(seconds)))
        end
    end)

    btnY = btnY - 50

    local GoBtn = ns.CreateNGButton(RecordSection, "Запустить маршрут", 140, 30)
    Describe(GoBtn, "Начать выполнение записанного маршрута выбранным NPC.")
    GoBtn:SetPoint("TOPLEFT", RecordSection, "TOPLEFT", 20, btnY)
    GoBtn:SetScript("OnClick", function()
        SendGmCommand(".wpgo")
    end)

    local StopBtn = ns.CreateNGButton(RecordSection, "Остановить", 140, 30)
    Describe(StopBtn, "Остановить выполнение маршрута, сохранив записанные точки.")
    StopBtn:SetPoint("TOPLEFT", GoBtn, "TOPRIGHT", 20, 0)
    StopBtn:SetScript("OnClick", function()
        SendGmCommand(".wpstop")
    end)

    local StateSection = ns.CreateNGSection(f, "Стойка NPC", nil, 90)
    StateSection:SetPoint("TOPLEFT", RecordSection, "BOTTOMLEFT", 0, -15)
    StateSection:SetPoint("TOPRIGHT", RecordSection, "BOTTOMRIGHT", 0, -15)

    local StateLabel = ns.CreateNGLabel(StateSection, "Стойка (0-9):")
    StateLabel:SetPoint("TOPLEFT", StateSection, "TOPLEFT", 20, -36)

    local StateBox = ns.CreateNGEditBox(StateSection, "WpStateBox", 60, 24)
    StateBox:SetPoint("LEFT", StateLabel, "RIGHT", 10, 0)
    StateBox:SetNumeric(true)
    StateBox:SetText("0")

    local StateBtn = ns.CreateNGButton(StateSection, "Применить", 120, 26)
    StateBtn:SetPoint("LEFT", StateBox, "RIGHT", 10, 0)
    StateBtn:SetScript("OnClick", function()
        local state = ReadNumber(StateBox, "Стойка", 0, 9, true)
        if state then SendGmCommand(string.format(".npcsetstate %d", state)) end
    end)

    local HelpLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    HelpLabel:SetText("Выберите NPC. Пройдите путь персонажем и добавьте точки бега или шага; затем запустите маршрут. Паузы и эмоции добавляются в конец.")
    HelpLabel:SetTextColor(0.6, 0.6, 0.6, 1)
    HelpLabel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    HelpLabel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    HelpLabel:SetJustifyH("CENTER")
    HelpLabel:SetWordWrap(true)

    return f
end

C_Timer.After(0, function()
    ns.RegisterSlashCommand("NNWAYPOINTS", function() ns.ShowModule("Вейпоинты") end, "nnwaypoints")
end)

ns.RegisterModule("Вейпоинты", InitWaypointsModule, "Маршруты NPC")
