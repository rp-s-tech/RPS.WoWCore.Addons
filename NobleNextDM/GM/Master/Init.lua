-- Loaded through the NobleNextDM private extension namespace.
-- GM/Master/Init.lua — панель мастера (речь, GO, NPC, инструменты, время/погода)

local _, ns = ...

local AIO_HANDLER = "AIOAddonMasterPanel"

-- Incoming AIO handlers live only in NobleNextLua GM/MasterPanel/NNMasterClient.lua.
_G.NobleNextMaster = _G.NobleNextMaster or {}

-- ---------------------------------------------------------------------------
-- GO Undo tracking for .gob add (via Core GO_SPAWNED fan-out)
-- ---------------------------------------------------------------------------
local UndoGobStack = {}
local UndoGobCooldown = 0

local function PushUndoGob(guid)
    if guid then
        table.insert(UndoGobStack, tonumber(guid))
        while #UndoGobStack > 20 do
            table.remove(UndoGobStack, 1)
        end
    end
end

local function PeekUndoGob()
    if #UndoGobStack == 0 and ns.LastSpawnedGoGuid then
        return ns.LastSpawnedGoGuid
    end
    if #UndoGobStack == 0 then return nil end
    return UndoGobStack[#UndoGobStack]
end

if ns.Subscribe then
    ns.Subscribe("GO_SPAWNED", "master.undoGob", function(payload)
        if payload and payload.guid then
            PushUndoGob(payload.guid)
        end
    end)
end

local CHAT_STATES = {
    { name = "Реплика NPC",           id = 1 },
    { name = "Реплика NPC с жестом",  id = 2 },
    { name = "Действие NPC",          id = 3 },
    { name = "Крик NPC",              id = 4 },
    { name = "Объявление",            id = 5 },
    { name = "Сообщение от NPC",       id = 6 },
}

local NPC_STATES = {
    { name = "Стоит",          id = 0 },
    { name = "Сидит",          id = 1 },
    { name = "Сидит на стуле", id = 2 },
    { name = "Спит",           id = 3 },
    { name = "Низкий стул",    id = 4 },
    { name = "Средний стул",   id = 5 },
    { name = "Высокий стул",   id = 6 },
    { name = "Мёртв",          id = 7 },
    { name = "Колено",         id = 8 },
    { name = "В воде",         id = 9 },
}

local WEATHER_TYPES = {
    { name = "Солнце", id = 1 },
    { name = "Дождь",  id = 2 },
    { name = "Снег",   id = 3 },
    { name = "Буря",   id = 4 },
}

local TIME_PRESETS = {
    { id = 1, name = "Раннее утро" },
    { id = 2, name = "Утро" },
    { id = 3, name = "Полдень" },
    { id = 4, name = "Вечер" },
    { id = 5, name = "Поздний вечер" },
    { id = 6, name = "Ночь" },
}

local function SendGmCommand(cmd)
    if not ns.RunGmCommand(cmd) then
        ns.PrintError("Не удалось отправить команду: " .. tostring(cmd))
        return false
    end
    return true
end

local function NumberInput(box, name, minimum, maximum, integer)
    local value = tonumber(((box:GetText() or ""):gsub(",", ".")))
    if not value or value ~= value or value < minimum or value > maximum
        or (integer and value ~= math.floor(value)) then
        ns.PrintError(name .. ": допустимо " .. minimum .. "-" .. maximum .. (integer and " (целое число)." or "."))
        return nil
    end
    return value
end

local function CreateSection(parent, title, _, height)
    local section = ns.CreateNGSection(parent, title, nil, height)
    section:SetWidth(parent:GetWidth())
    parent:HookScript("OnSizeChanged", function(_, width) section:SetWidth(width) end)
    return section
end

local function IsNpcTarget()
    return UnitExists("target") and not UnitIsPlayer("target")
end

local function HasAudience(radius)
    if radius == 0 and IsInGroup and not IsInGroup() then
        ns.PrintError("Для отправки группе вступите в группу или укажите радиус 1-90 ярдов.")
        return false
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Module initialization
-- ---------------------------------------------------------------------------
local function InitMasterModule(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:Hide()

    -- Tabs
    local Tabs = {}
    local TabButtons = {}
    local CurrentTab = nil

    local function ShowTab(name)
        for tabName, tab in pairs(Tabs) do
            tab.frame:SetShown(tabName == name)
        end
        for _, btn in ipairs(TabButtons) do
            ns.SetNGTabSelected(btn, btn.tabName == name)
        end
        CurrentTab = name
    end

    local function CreateTabButton(text, tabName, x)
        local btn = ns.CreateNGTab(f, text, tabName, function() ShowTab(tabName) end)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", x, -8)
        btn.tabName = tabName
        table.insert(TabButtons, btn)
        return btn
    end

    local function CreateTabFrame(name)
        -- Outer host fills content; inner scroll prevents Tools overflow clip.
        local host = CreateFrame("Frame", nil, f)
        host:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -40)
        host:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8)
        host:Hide()

        local scroll = ns.NNL.Scroll.CreateFrame(host)
        scroll:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -22, 0)
        local tf = CreateFrame("Frame", nil, scroll)
        tf:SetWidth(600)
        tf:SetHeight(620)
        scroll:SetScrollChild(tf)
        host:HookScript("OnSizeChanged", function(_, w)
            if w and w > 60 then
                tf:SetWidth(w - 22)
            end
        end)

        Tabs[name] = { frame = host, body = tf, scroll = scroll }
        return tf
    end

    CreateTabButton("Речь",    "chat",        10)
    CreateTabButton("Объекты", "go",          104)
    CreateTabButton("NPC",     "npc",         198)
    CreateTabButton("Инструменты", "tools",       292)
    CreateTabButton("Время и погода", "timeweather", 410)

    -- -----------------------------------------------------------------------
    -- Tab: Chat
    -- -----------------------------------------------------------------------
    local ChatTab = CreateTabFrame("chat")

    local ChatSection = CreateSection(ChatTab, "Речь и сообщения", 620, 150)
    ChatSection:SetPoint("TOPLEFT", ChatTab, "TOPLEFT", 0, 0)

    local ChatLabel = ns.CreateNGLabel(ChatSection, "Текст:")
    ChatLabel:SetPoint("TOPLEFT", ChatSection, "TOPLEFT", 10, -28)

    -- Multiline EditBox height follows its text, so keep the visible border on
    -- a separate fixed viewport instead of the automatically shrinking edit.
    local ChatHost = CreateFrame("Frame", nil, ChatSection, "BackdropTemplate")
    ChatHost:SetHeight(60)
    ChatHost:SetPoint("TOPLEFT", ChatSection, "TOPLEFT", 10, -42)
    ChatHost:SetPoint("TOPRIGHT", ChatSection, "TOPRIGHT", -10, -42)
    ns.NNL.Theme.Apply(ChatHost, "input")

    local ChatScroll = ns.NNL.Scroll.CreateFrame(ChatHost)
    ChatScroll:SetPoint("TOPLEFT", ChatHost, "TOPLEFT", 6, -6)
    ChatScroll:SetPoint("BOTTOMRIGHT", ChatHost, "BOTTOMRIGHT", -24, 6)

    local ChatBox = CreateFrame("EditBox", "NobleNext_Edit_ChatBox", ChatScroll)
    ChatBox:SetMultiLine(true)
    ChatBox:SetAutoFocus(false)
    ChatBox:SetAltArrowKeyMode(false)
    ChatBox:SetFontObject("GameFontHighlight")
    ChatBox:SetWidth(math.max(1, ChatScroll:GetWidth()))
    ChatBox:SetMaxLetters(350)
    ChatBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ChatBox:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
    ChatBox:SetScript("OnUpdate", function(self, elapsed)
        ScrollingEdit_OnUpdate(self, elapsed, ChatScroll)
    end)
    ChatScroll:SetScrollChild(ChatBox)
    ChatScroll:HookScript("OnSizeChanged", function(_, width)
        ChatBox:SetWidth(math.max(1, width))
    end)
    ChatHost:EnableMouse(true)
    ChatHost:SetScript("OnMouseDown", function() ChatBox:SetFocus() end)

    local currentState = 1
    local UpdateChatOptions
    local ModeLabel = ns.CreateNGLabel(ChatSection, "Режим:")
    ModeLabel:SetPoint("TOPLEFT", ChatSection, "TOPLEFT", 10, -118)
    local ModeDropdown = ns.NNL.Widgets.CreateDropdown(ChatSection, {
        name = "NobleNextMasterChatDropdown", width = 250, defaultText = "Режим сообщения",
        menu = function(_, root)
            for _, state in ipairs(CHAT_STATES) do
                root:CreateRadio(state.name, function(value) return currentState == value end,
                    function(value)
                        currentState = value
                        if UpdateChatOptions then UpdateChatOptions() end
                    end, state.id)
            end
        end,
    })
    ModeDropdown:SetPoint("TOPLEFT", ChatSection, "TOPLEFT", 80, -110)

    local OptSection = CreateSection(ChatTab, "Получатели и оформление", 620, 112)
    OptSection:SetPoint("TOPLEFT", ChatSection, "BOTTOMLEFT", 0, -10)

    local RadiusLabel = ns.CreateNGLabel(OptSection, "Радиус (0=группа):")
    RadiusLabel:SetPoint("TOPLEFT", OptSection, "TOPLEFT", 10, -38)
    local RadiusBox = ns.CreateNGEditBox(OptSection, "RadiusBox", 60, 22)
    RadiusBox:SetNumeric(true)
    RadiusBox:SetText("0")
    RadiusBox:SetPoint("TOPLEFT", OptSection, "TOPLEFT", 150, -34)

    local ColorLabel = ns.CreateNGLabel(OptSection, "Цвет (1-7):")
    ColorLabel:SetPoint("TOPLEFT", OptSection, "TOPLEFT", 10, -68)
    local ColorBox = ns.CreateNGEditBox(OptSection, "ColorBox", 60, 22)
    ColorBox:SetNumeric(true)
    ColorBox:SetText("1")
    ColorBox:SetPoint("TOPLEFT", OptSection, "TOPLEFT", 150, -64)
    local radiusHint = ns.CreateNGLabel(OptSection, "")
    radiusHint:SetPoint("TOPLEFT", OptSection, "TOPLEFT", 10, -92)
    radiusHint:SetPoint("RIGHT", OptSection, "RIGHT", -10, 0)
    radiusHint:SetJustifyH("LEFT")

    local SendBtn = ns.CreateNGButton(ChatTab, "Отправить", 140, 26)
    SendBtn:SetPoint("TOPLEFT", OptSection, "BOTTOMLEFT", 10, -12)
    local ChatHint = ns.CreateNGLabel(ChatTab, "")
    ChatHint:SetPoint("TOPLEFT", SendBtn, "BOTTOMLEFT", 0, -10)
    ChatHint:SetPoint("RIGHT", ChatTab, "RIGHT", -10, 0)
    ChatHint:SetJustifyH("LEFT")
    ChatHint:SetWordWrap(true)
    UpdateChatOptions = function()
        local hasAudience, hasColor = currentState >= 5, currentState == 5
        OptSection:SetShown(hasAudience)
        RadiusLabel:SetShown(hasAudience)
        RadiusBox:SetShown(hasAudience)
        ColorLabel:SetShown(hasColor)
        ColorBox:SetShown(hasColor)
        OptSection:SetHeight(hasColor and 132 or 112)
        radiusHint:ClearAllPoints()
        radiusHint:SetPoint("TOPLEFT", OptSection, "TOPLEFT", 10, hasColor and -92 or -64)
        radiusHint:SetPoint("RIGHT", OptSection, "RIGHT", -10, 0)
        radiusHint:SetText("0 — участники вашей группы. 1–90 ярдов — игроки рядом.")
        SendBtn:ClearAllPoints()
        SendBtn:SetPoint("TOPLEFT", hasAudience and OptSection or ChatSection, "BOTTOMLEFT", 10, -12)
        if currentState == 5 then
            ChatHint:SetText("Цвет применяется только к объявлению. NPC в цели не требуется.")
        elseif currentState == 6 then
            ChatHint:SetText("Выберите NPC. У получателей откроется диалог с его сообщением, текст также появится в чате.")
        elseif currentState == 3 then
            ChatHint:SetText("Выберите NPC и опишите его действие словами. Это текстовая эмоция, а не числовой ID анимации.")
        elseif currentState == 2 then
            ChatHint:SetText("Выберите NPC. Жест речи определяется последним знаком реплики: вопросом, восклицанием или обычной фразой.")
        else
            ChatHint:SetText("Выберите NPC. Дальность реплики или крика определяет сервер; отдельный радиус здесь не используется.")
        end
        ChatTab:SetHeight(150 + (hasAudience and OptSection:GetHeight() + 10 or 0) + 12 + 26 + 56)
    end
    SendBtn:SetScript("OnClick", function()
        local text = (ChatBox:GetText() or ""):match("^%s*(.-)%s*$")
        if not text or text == "" then ns.PrintError("Введите текст сообщения."); return end
        if currentState ~= 6 then text = text:gsub("%s+", " ") end
        if currentState ~= 5 and not IsNpcTarget() then ns.PrintError("Выберите NPC для реплики или сообщения."); return end
        local sent
        if currentState == 1 then
            sent = SendGmCommand(".nnsay " .. text)
        elseif currentState == 2 then
            sent = SendGmCommand(".nnsayemote " .. text)
        elseif currentState == 3 then
            sent = SendGmCommand(".nnemote " .. text)
        elseif currentState == 4 then
            sent = SendGmCommand(".nnyell " .. text)
        elseif currentState == 5 then
            local radius = NumberInput(RadiusBox, "Радиус", 0, 90)
            local color = NumberInput(ColorBox, "Цвет", 1, 7, true)
            if not radius or not color then return end
            if not HasAudience(radius) then return end
            if #text > 355 then ns.PrintError("Объявление слишком длинное. Сократите текст."); return end
            sent = ns.AIOHandle(AIO_HANDLER, "NPCChatRetranslator", text, currentState, radius, color)
        elseif currentState == 6 then
            local radius = NumberInput(RadiusBox, "Радиус", 0, 90)
            if not radius or not HasAudience(radius) then return end
            sent = ns.AIOHandle(AIO_HANDLER, "TalkingHeadRetranslator", text, UnitName("target") or "NPC", "", radius)
        end
        if sent then ChatBox:SetText(""); ChatBox:ClearFocus() end
    end)

    -- -----------------------------------------------------------------------
    -- Tab: GO Cleanup
    -- -----------------------------------------------------------------------
    local GoTab = CreateTabFrame("go")

    local GoSection = CreateSection(GoTab, "Уборка объектов", 620, 180)
    GoSection:SetPoint("TOPLEFT", GoTab, "TOPLEFT", 0, 0)

    local UndoLastBtn = ns.CreateNGButton(GoSection, "Удалить последний созданный объект", 300, 26)
    UndoLastBtn:SetPoint("TOP", GoSection, "TOP", 0, -34)
    UndoLastBtn:SetScript("OnClick", function()
        local guid = PeekUndoGob()
        if not guid then
            ns.PrintError("Нет сохранённых GO для отката.")
            return
        end
        if GetTime() < UndoGobCooldown then
            ns.PrintError("Подождите немного.")
            return
        end
        if SendGmCommand(".gobject delete " .. guid) then
            UndoGobCooldown = GetTime() + 1
            if UndoGobStack[#UndoGobStack] == guid then table.remove(UndoGobStack) end
            if ns.LastSpawnedGoGuid == guid then ns.LastSpawnedGoGuid = nil end
        end
    end)

    local UndoRadiusLabel = ns.CreateNGLabel(GoSection, "Радиус (<=15):")
    UndoRadiusLabel:SetPoint("TOPLEFT", GoSection, "TOPLEFT", 10, -76)
    local UndoRadiusBox = ns.CreateNGEditBox(GoSection, "UndoRadiusBox", 60, 22)
    UndoRadiusBox:SetNumeric(true)
    UndoRadiusBox:SetText("5")
    UndoRadiusBox:SetPoint("TOPLEFT", GoSection, "TOPLEFT", 130, -72)

    local UndoPhaseBtn = ns.NNL.Widgets.CreateButton(GoSection, { text = "Удалить объекты рядом в той же фазе", width = 300, height = 26, style = "danger" })
    UndoPhaseBtn:SetPoint("TOP", GoSection, "TOP", 0, -108)
    UndoPhaseBtn:SetScript("OnClick", function()
        local radius = NumberInput(UndoRadiusBox, "Радиус удаления", 0.1, 15)
        if not radius then return end
        ns.Confirm.Show({
            text = ("Удалить объекты в радиусе %s ярдов с той же маской фазы, что у персонажа? Это удаление, а не восстановление."):format(radius),
            acceptLabel = "Удалить",
            cancelLabel = "Отмена",
            onAccept = function()
                ns.AIOHandle(AIO_HANDLER, "UndoPhaseGobjects", radius)
            end,
        })
    end)

    local NameSection = CreateSection(GoTab, "Удаление по фрагменту имени", 620, 110)
    NameSection:SetPoint("TOPLEFT", GoSection, "BOTTOMLEFT", 0, -10)

    local UndoNameLabel = ns.CreateNGLabel(NameSection, "Имя GO:")
    UndoNameLabel:SetPoint("TOPLEFT", NameSection, "TOPLEFT", 10, -34)
    local UndoNameBox = ns.CreateNGEditBox(NameSection, "UndoNameBox", 200, 22)
    UndoNameBox:SetPoint("TOPLEFT", NameSection, "TOPLEFT", 80, -34)

    local UndoNameBtn = ns.CreateNGButton(NameSection, "Удалить по имени", 300, 26)
    UndoNameBtn:SetPoint("TOP", NameSection, "TOP", 0, -66)
    UndoNameBtn:SetScript("OnClick", function()
        local r = NumberInput(UndoRadiusBox, "Радиус удаления", 0.1, 15)
        local name = (UndoNameBox:GetText() or ""):match("^%s*(.-)%s*$")
        if not r then return end
        if #name < 5 then ns.PrintError("Введите более длинный фрагмент имени (минимум 5 байт)."); return end
        ns.Confirm.Show({
            text = ("Удалить объекты с фрагментом имени \"%s\" в радиусе %s ярдов с той же маской фазы?"):format(name, r),
            acceptLabel = "Удалить",
            cancelLabel = "Отмена",
            onAccept = function()
                ns.AIOHandle(AIO_HANDLER, "UndoPhaseNameGobjects", name, r)
            end,
        })
    end)

    -- -----------------------------------------------------------------------
    -- Tab: NPC
    -- -----------------------------------------------------------------------
    local NpcTab = CreateTabFrame("npc")

    local StateSection = CreateSection(NpcTab, "Положение тела NPC", 620, 126)
    StateSection:SetPoint("TOPLEFT", NpcTab, "TOPLEFT", 0, 0)

    for i, state in ipairs(NPC_STATES) do
        local btn = ns.CreateNGButton(StateSection, state.name, 100, 20)
        btn:SetScript("OnClick", function()
            if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
            SendGmCommand(".npcsetstate " .. state.id)
        end)
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        btn:SetPoint("TOPLEFT", StateSection, "TOPLEFT", 10 + col * 118, -34 - row * 28)
    end

    local MiscSection = CreateSection(NpcTab, "Состояние", 620, 70)
    MiscSection:SetPoint("TOPLEFT", StateSection, "BOTTOMLEFT", 0, -10)

    local WeaponBtn = ns.CreateNGButton(MiscSection, "Убрать оружие", 110, 24)
    WeaponBtn:SetPoint("TOPLEFT", MiscSection, "TOPLEFT", 10, -34)
    WeaponBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
        SendGmCommand(".weapon 0")
    end)

    local MeleeBtn = ns.CreateNGButton(MiscSection, "В руку", 85, 24)
    MeleeBtn:SetPoint("LEFT", WeaponBtn, "RIGHT", 6, 0)
    MeleeBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
        SendGmCommand(".weapon 1")
    end)
    local RangedBtn = ns.CreateNGButton(MiscSection, "Дальний бой", 110, 24)
    RangedBtn:SetPoint("LEFT", MeleeBtn, "RIGHT", 6, 0)
    RangedBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
        SendGmCommand(".weapon 2")
    end)

    local SavePoseBtn = ns.CreateNGButton(MiscSection, "Сохранить позу", 150, 24)
    SavePoseBtn:SetPoint("LEFT", RangedBtn, "RIGHT", 10, 0)
    SavePoseBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
        SendGmCommand(".npcsave")
    end)

    local ScaleSection = CreateSection(NpcTab, "Масштаб и техническая фаза", 620, 118)
    ScaleSection:SetPoint("TOPLEFT", MiscSection, "BOTTOMLEFT", 0, -10)

    local ScaleLabel = ns.CreateNGLabel(ScaleSection, "Масштаб:")
    ScaleLabel:SetPoint("TOPLEFT", ScaleSection, "TOPLEFT", 10, -34)
    local ScaleBox = ns.CreateNGEditBox(ScaleSection, "ScaleBox", 60, 22)
    ScaleBox:SetText("1")
    ScaleBox:SetPoint("TOPLEFT", ScaleSection, "TOPLEFT", 80, -34)
    local ScaleBtn = ns.CreateNGButton(ScaleSection, "Применить", 90, 24)
    ScaleBtn:SetPoint("TOPLEFT", ScaleBox, "TOPRIGHT", 10, 0)
    ScaleBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
        local val = NumberInput(ScaleBox, "Масштаб", 0.1, 10)
        if not val then return end
        SendGmCommand(".npc set scale " .. val)
    end)

    local PhaseLabel = ns.CreateNGLabel(ScaleSection, "Фаза:")
    PhaseLabel:SetPoint("TOPLEFT", ScaleSection, "TOPLEFT", 10, -64)
    local PhaseBox = ns.CreateNGEditBox(ScaleSection, "PhaseBox", 60, 22)
    PhaseBox:SetNumeric(true)
    PhaseBox:SetText("1")
    PhaseBox:SetPoint("TOPLEFT", ScaleSection, "TOPLEFT", 80, -60)
    local PhaseBtn = ns.CreateNGButton(ScaleSection, "Переключить", 110, 24)
    PhaseBtn:SetPoint("TOPLEFT", PhaseBox, "TOPRIGHT", 10, 0)
    PhaseBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
        local val = NumberInput(PhaseBox, "ID технической фазы", 1, 4294967295, true)
        if not val then return end
        SendGmCommand(".modify phase " .. val)
    end)
    local phaseHint = ns.CreateNGLabel(ScaleSection, "Кнопка добавляет или снимает техническую фазу NPC. Для RP-фаз откройте «RP Фазы».")
    phaseHint:SetPoint("TOPLEFT", ScaleSection, "TOPLEFT", 10, -88)
    phaseHint:SetPoint("RIGHT", ScaleSection, "RIGHT", -10, 0)
    phaseHint:SetJustifyH("LEFT")

    local AuraMorphSection = CreateSection(NpcTab, "Аура, модель и визуальный эффект", 620, 146)
    AuraMorphSection:SetPoint("TOPLEFT", ScaleSection, "BOTTOMLEFT", 0, -10)

    local AuraLabel = ns.CreateNGLabel(AuraMorphSection, "Аура ID:")
    AuraLabel:SetPoint("TOPLEFT", AuraMorphSection, "TOPLEFT", 10, -34)
    local AuraBox = ns.CreateNGEditBox(AuraMorphSection, "AuraBox", 80, 22)
    AuraBox:SetPoint("TOPLEFT", AuraMorphSection, "TOPLEFT", 80, -34)
    local AuraAddBtn = ns.CreateNGButton(AuraMorphSection, "Добавить", 80, 24)
    AuraAddBtn:SetPoint("TOPLEFT", AuraBox, "TOPRIGHT", 10, 0)
    AuraAddBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
        local id = NumberInput(AuraBox, "ID ауры", 1, 4294967295, true)
        if not id then return end
        SendGmCommand(".aura " .. id)
    end)
    local AuraDelBtn = ns.CreateNGButton(AuraMorphSection, "Снять", 80, 24)
    AuraDelBtn:SetPoint("TOPLEFT", AuraAddBtn, "TOPRIGHT", 5, 0)
    AuraDelBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
        local id = NumberInput(AuraBox, "ID ауры", 1, 4294967295, true)
        if not id then return end
        SendGmCommand(".unaura " .. id)
    end)

    local MorphLabel = ns.CreateNGLabel(AuraMorphSection, "Морф ID:")
    MorphLabel:SetPoint("TOPLEFT", AuraMorphSection, "TOPLEFT", 10, -66)
    local MorphBox = ns.CreateNGEditBox(AuraMorphSection, "MorphBox", 80, 22)
    MorphBox:SetPoint("TOPLEFT", AuraMorphSection, "TOPLEFT", 80, -62)
    local MorphBtn = ns.CreateNGButton(AuraMorphSection, "Морф", 80, 24)
    MorphBtn:SetPoint("TOPLEFT", MorphBox, "TOPRIGHT", 10, 0)
    MorphBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
        local id = NumberInput(MorphBox, "ID модели", 1, 4294967295, true)
        if not id then return end
        SendGmCommand(".morph " .. id)
    end)
    local DemorphBtn = ns.CreateNGButton(AuraMorphSection, "Сброс", 80, 24)
    DemorphBtn:SetPoint("TOPLEFT", MorphBtn, "TOPRIGHT", 5, 0)
    DemorphBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
        SendGmCommand(".demorph")
    end)

    local VisualLabel = ns.CreateNGLabel(AuraMorphSection, "Визуал ID:")
    VisualLabel:SetPoint("TOPLEFT", AuraMorphSection, "TOPLEFT", 10, -98)
    local VisualBox = ns.CreateNGEditBox(AuraMorphSection, "VisualBox", 80, 22)
    VisualBox:SetPoint("TOPLEFT", AuraMorphSection, "TOPLEFT", 80, -94)
    local VisualBtn = ns.CreateNGButton(AuraMorphSection, "Визуал", 80, 24)
    VisualBtn:SetPoint("TOPLEFT", VisualBox, "TOPRIGHT", 10, 0)
    VisualBox:SetEnabled(false)
    VisualBtn:SetEnabledEx(false, "Визуальные эффекты пока недоступны на этом сервере.")
    local VisualStopBtn = ns.CreateNGButton(AuraMorphSection, "Стоп", 80, 24)
    VisualStopBtn:SetPoint("TOPLEFT", VisualBtn, "TOPRIGHT", 5, 0)
    VisualStopBtn:SetEnabledEx(false, "Остановка визуальных эффектов пока недоступна на этом сервере.")

    -- -----------------------------------------------------------------------
    -- Tab: Tools
    -- -----------------------------------------------------------------------
    local ToolsTab = CreateTabFrame("tools")

    local SummonSection = CreateSection(ToolsTab, "Телепортация", 620, 102)
    SummonSection:SetPoint("TOPLEFT", ToolsTab, "TOPLEFT", 0, 0)

    local SummonLabel = ns.CreateNGLabel(SummonSection, "Имя игрока:")
    SummonLabel:SetPoint("TOPLEFT", SummonSection, "TOPLEFT", 10, -34)
    local SummonBox = ns.CreateNGEditBox(SummonSection, "SummonBox", 200, 22)
    SummonBox:SetPoint("TOPLEFT", SummonSection, "TOPLEFT", 110, -34)

    local SummonBtn = ns.CreateNGButton(SummonSection, "Призвать", 95, 24)
    SummonBtn:SetPoint("TOPLEFT", SummonSection, "TOPLEFT", 10, -66)
    SummonBtn:SetScript("OnClick", function()
        local name = SummonBox:GetText()
        if not name or name == "" then return end
        SendGmCommand(".summon " .. name)
    end)
    local GotoBtn = ns.CreateNGButton(SummonSection, "ТП к игроку", 95, 24)
    GotoBtn:SetPoint("TOPLEFT", SummonBtn, "TOPRIGHT", 10, 0)
    GotoBtn:SetScript("OnClick", function()
        local name = SummonBox:GetText()
        if not name or name == "" then return end
        SendGmCommand(".appear " .. name)
    end)
    local RaidSummonBtn = ns.CreateNGButton(SummonSection, "Призвать группу", 132, 24)
    RaidSummonBtn:SetPoint("TOPLEFT", GotoBtn, "TOPRIGHT", 10, 0)
    RaidSummonBtn:SetScript("OnClick", function()
        local name = SummonBox:GetText()
        if not name or name == "" then return end
        ns.Confirm.Show({
            text = "Призвать к себе группу игрока " .. name .. "?",
            onAccept = function() SendGmCommand(".group summon " .. name) end,
        })
    end)

    local NpcSection = CreateSection(ToolsTab, "NPC", 620, 70)
    NpcSection:SetPoint("TOPLEFT", SummonSection, "BOTTOMLEFT", 0, -10)

    local PossessBtn = ns.CreateNGButton(NpcSection, "Захватить NPC", 150, 24)
    PossessBtn:SetPoint("TOPLEFT", NpcSection, "TOPLEFT", 10, -34)
    PossessBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
        SendGmCommand(".possess")
    end)
    local UnpossessBtn = ns.CreateNGButton(NpcSection, "Отпустить", 150, 24)
    UnpossessBtn:SetPoint("TOPLEFT", PossessBtn, "TOPRIGHT", 15, 0)
    UnpossessBtn:SetScript("OnClick", function() SendGmCommand(".rps release") end)

    local MoveSection = CreateSection(ToolsTab, "Перемещение", 620, 70)
    MoveSection:SetPoint("TOPLEFT", NpcSection, "BOTTOMLEFT", 0, -10)

    local NpcMoveBtn = ns.CreateNGButton(MoveSection, "Перенести спавн NPC", 166, 24)
    NpcMoveBtn:SetPoint("TOPLEFT", MoveSection, "TOPLEFT", 10, -34)
    NpcMoveBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
        SendGmCommand(".npc move")
    end)
    local ArmyBtn = ns.CreateNGButton(MoveSection, "Армия", 95, 24)
    ArmyBtn:SetPoint("TOPLEFT", NpcMoveBtn, "TOPRIGHT", 15, 0)
    ArmyBtn:SetScript("OnClick", function() ns.ShowModule("Армия") end)
    local NpcPanelBtn = ns.CreateNGButton(MoveSection, "Панель NPC", 120, 24)
    NpcPanelBtn:SetPoint("TOPLEFT", ArmyBtn, "TOPRIGHT", 15, 0)
    NpcPanelBtn:SetScript("OnClick", function() ns.ShowModule("NPC") end)
    local TelePanelBtn = ns.CreateNGButton(MoveSection, "Телепорты", 90, 24)
    TelePanelBtn:SetPoint("TOPLEFT", NpcPanelBtn, "TOPRIGHT", 10, 0)
    TelePanelBtn:SetScript("OnClick", function() ns.ShowModule("Tele") end)

    local HistSection = CreateSection(ToolsTab, "История GO / NPC (чат)", 620, 100)
    HistSection:SetPoint("TOPLEFT", MoveSection, "BOTTOMLEFT", 0, -10)
    local HistLabel = HistSection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    HistLabel:SetPoint("TOPLEFT", HistSection, "TOPLEFT", 12, -28)
    HistLabel:SetPoint("RIGHT", HistSection, "RIGHT", -12, 0)
    HistLabel:SetJustifyH("LEFT")
    HistLabel:SetText("-")

    local function RefreshHistoryLabel()
        if not (ns.SelectionContext and ns.SelectionContext.GetHistory) then
            HistLabel:SetText("История выбранных объектов пока недоступна.")
            return
        end
        local rows = ns.SelectionContext.GetHistory()
        if not rows or #rows == 0 then
            HistLabel:SetText("История пуста. Выберите объект или NPC через ссылку в чате.")
            return
        end
        local parts = {}
        for i = 1, math.min(8, #rows) do
            local r = rows[i]
            parts[#parts + 1] = string.format("%s:%s", r.kind or "?", tostring(r.guid or "?"))
        end
        HistLabel:SetText(table.concat(parts, "  |  "))
    end

    local HistSelBtn = ns.CreateNGButton(HistSection, "Обновить", 90, 22)
    HistSelBtn:SetPoint("BOTTOMLEFT", HistSection, "BOTTOMLEFT", 12, 10)
    HistSelBtn:SetScript("OnClick", RefreshHistoryLabel)
    local HistGoBtn = ns.CreateNGButton(HistSection, "К объекту", 90, 22)
    HistGoBtn:SetPoint("LEFT", HistSelBtn, "RIGHT", 8, 0)
    HistGoBtn:SetScript("OnClick", function()
        local go = ns.SelectionContext and ns.SelectionContext.GetGo and ns.SelectionContext.GetGo()
        if not go or not go.guid then
            ns.PrintError("Нет активного GO в контексте.")
            return
        end
        SendGmCommand(".go gameobject " .. go.guid)
    end)
    local HistNpcBtn = ns.CreateNGButton(HistSection, "К NPC", 90, 22)
    HistNpcBtn:SetPoint("LEFT", HistGoBtn, "RIGHT", 8, 0)
    HistNpcBtn:SetScript("OnClick", function()
        local npc = ns.SelectionContext and ns.SelectionContext.GetNpc and ns.SelectionContext.GetNpc()
        if not npc or not npc.guid then
            ns.PrintError("Нет активного NPC в контексте.")
            return
        end
        SendGmCommand(".go creature " .. npc.guid)
    end)
    do
        local toolsHost = Tabs.tools and Tabs.tools.frame
        if toolsHost then
            local prevOnShow = toolsHost:GetScript("OnShow")
            toolsHost:SetScript("OnShow", function(...)
                if prevOnShow then
                    prevOnShow(...)
                end
                RefreshHistoryLabel()
            end)
        end
    end

    local WpSection = CreateSection(ToolsTab, "Маршрут NPC и фиксация сцены", 620, 202)
    WpSection:SetPoint("TOPLEFT", HistSection, "BOTTOMLEFT", 0, -10)

    local WpLabel = ns.CreateNGLabel(WpSection, "Точки временные до команды «Запечь» и подтверждения сервера.")
    WpLabel:SetPoint("TOPLEFT", WpSection, "TOPLEFT", 10, -34)

    local WpMoveBtn = ns.CreateNGButton(WpSection, "+ Бег", 100, 24)
    WpMoveBtn:SetPoint("TOPLEFT", WpSection, "TOPLEFT", 10, -58)
    WpMoveBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
        SendGmCommand(".wpmove")
    end)
    local WpWalkBtn = ns.CreateNGButton(WpSection, "+ Шаг", 100, 24)
    WpWalkBtn:SetPoint("TOPLEFT", WpMoveBtn, "TOPRIGHT", 6, 0)
    WpWalkBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
        SendGmCommand(".wpwalk")
    end)
    local WpClearBtn = ns.CreateNGButton(WpSection, "Очистить", 100, 24)
    WpClearBtn:SetPoint("TOPLEFT", WpWalkBtn, "TOPRIGHT", 6, 0)
    WpClearBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
        SendGmCommand(".wpclear")
    end)
    local WpGoBtn = ns.CreateNGButton(WpSection, "Запустить", 100, 24)
    WpGoBtn:SetPoint("TOPLEFT", WpClearBtn, "TOPRIGHT", 6, 0)
    WpGoBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
        SendGmCommand(".wpgo")
    end)
    local WpEditBtn = ns.CreateNGButton(WpSection, "Точки маршрута", 150, 24)
    WpEditBtn:SetPoint("TOPLEFT", WpGoBtn, "TOPRIGHT", 6, 0)
    WpEditBtn:SetScript("OnClick", function() ns.ShowModule("Точки маршрута") end)

    local WpWaitLabel = ns.CreateNGLabel(WpSection, "Пауза, секунды:")
    WpWaitLabel:SetPoint("TOPLEFT", WpSection, "TOPLEFT", 10, -98)
    local WpWaitBox = ns.CreateNGEditBox(WpSection, "WpWaitBox", 60, 22)
    WpWaitBox:SetPoint("TOPLEFT", WpSection, "TOPLEFT", 150, -94)
    WpWaitBox:SetText("2")
    local WpWaitBtn = ns.CreateNGButton(WpSection, "+ Пауза", 106, 24)
    WpWaitBtn:SetPoint("TOPLEFT", WpWaitBox, "TOPRIGHT", 10, 0)
    WpWaitBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
        local seconds = NumberInput(WpWaitBox, "Длительность", 0.5, 4294967)
        if seconds then SendGmCommand(".wpwait " .. seconds) end
    end)
    local WpEmoteLabel = ns.CreateNGLabel(WpSection, "ID анимации:")
    WpEmoteLabel:SetPoint("TOPLEFT", WpSection, "TOPLEFT", 10, -132)
    local WpEmoteBox = ns.CreateNGEditBox(WpSection, "WpEmoteBox", 60, 22)
    WpEmoteBox:SetPoint("TOPLEFT", WpSection, "TOPLEFT", 150, -128)
    WpEmoteBox:SetText("1")
    WpEmoteBox:SetNumeric(true)
    local WpEmoteBtn = ns.CreateNGButton(WpSection, "+ Анимация", 106, 24)
    WpEmoteBtn:SetPoint("TOPLEFT", WpEmoteBox, "TOPRIGHT", 10, 0)
    WpEmoteBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
        local seconds = NumberInput(WpWaitBox, "Длительность", 0.5, 4294967)
        local id = NumberInput(WpEmoteBox, "ID анимации", 1, 4294967295, true)
        if seconds and id then SendGmCommand(".wpemote " .. id .. " " .. seconds) end
    end)

    local BakeNpcBtn = ns.CreateNGButton(WpSection, "Запечь НИП", 170, 24)
    BakeNpcBtn:SetPoint("TOPLEFT", WpSection, "TOPLEFT", 10, -164)
    BakeNpcBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель временного NPC."); return end
        SendGmCommand(".rps persist npc-bake")
    end)
    local BakeRouteBtn = ns.CreateNGButton(WpSection, "Запечь маршрут", 170, 24)
    BakeRouteBtn:SetPoint("LEFT", BakeNpcBtn, "RIGHT", 6, 0)
    BakeRouteBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC с маршрутом."); return end
        SendGmCommand(".rps persist wp-bake")
    end)
    local BakeGoBtn = ns.CreateNGButton(WpSection, "Запечь объект", 170, 24)
    BakeGoBtn:SetPoint("LEFT", BakeRouteBtn, "RIGHT", 6, 0)
    BakeGoBtn:SetScript("OnClick", function() SendGmCommand(".rps persist go-bake") end)

    -- -----------------------------------------------------------------------
    -- Tab: Time & Weather
    -- -----------------------------------------------------------------------
    local TimeWeatherTab = CreateTabFrame("timeweather")

    local TimeSection = CreateSection(TimeWeatherTab, "Время суток для себя и группы", 620, 108)
    TimeSection:SetPoint("TOPLEFT", TimeWeatherTab, "TOPLEFT", 0, 0)

    -- The commands accept preset indexes, not minutes or WeatherType values.
    local selectedTime = 1
    local TimeDropdown = ns.NNL.Widgets.CreateDropdown(TimeSection, {
        name = "NobleNextMasterTimeDropdown", width = 200, defaultText = "Время суток",
        menu = function(_, root)
            for _, preset in ipairs(TIME_PRESETS) do
                root:CreateRadio(preset.name, function(value) return selectedTime == value end,
                    function(value) selectedTime = value end, preset.id)
            end
        end,
    })
    TimeDropdown:SetPoint("TOPLEFT", TimeSection, "TOPLEFT", 10, -34)
    local ApplyTimeBtn = ns.CreateNGButton(TimeSection, "Применить время", 156, 24)
    ApplyTimeBtn:SetPoint("LEFT", TimeDropdown, "RIGHT", 12, 0)
    ApplyTimeBtn:SetScript("OnClick", function() SendGmCommand(".setgrouptime " .. selectedTime) end)

    local ServerTimeBtn = ns.CreateNGButton(TimeSection, "Серверное время", 150, 22)
    ServerTimeBtn:SetPoint("TOPLEFT", TimeSection, "TOPLEFT", 10, -70)
    ServerTimeBtn:SetScript("OnClick", function() SendGmCommand(".setgrouptime server") end)

    local WeatherSection = CreateSection(TimeWeatherTab, "Погода для себя и группы", 620, 140)
    WeatherSection:SetPoint("TOPLEFT", TimeSection, "BOTTOMLEFT", 0, -10)

    local selectedWeather = 1
    local WeatherDropdown = ns.NNL.Widgets.CreateDropdown(WeatherSection, {
        name = "NobleNextMasterWeatherDropdown", width = 200, defaultText = "Погода",
        menu = function(_, root)
            for _, preset in ipairs(WEATHER_TYPES) do
                root:CreateRadio(preset.name, function(value) return selectedWeather == value end,
                    function(value) selectedWeather = value end, preset.id)
            end
        end,
    })
    WeatherDropdown:SetPoint("TOPLEFT", WeatherSection, "TOPLEFT", 10, -34)

    local WeatherLabel = ns.CreateNGLabel(WeatherSection, "Интенсивность (0-10):")
    WeatherLabel:SetPoint("TOPLEFT", WeatherSection, "TOPLEFT", 10, -76)
    local WeatherStrengthBox = ns.CreateNGEditBox(WeatherSection, "WeatherStrengthBox", 60, 22)
    WeatherStrengthBox:SetNumeric(true)
    WeatherStrengthBox:SetText("5")
    WeatherStrengthBox:SetPoint("TOPLEFT", WeatherSection, "TOPLEFT", 170, -70)

    local ApplyWeatherBtn = ns.CreateNGButton(WeatherSection, "Применить погоду", 156, 24)
    ApplyWeatherBtn:SetPoint("LEFT", WeatherDropdown, "RIGHT", 12, 0)
    ApplyWeatherBtn:SetScript("OnClick", function()
        local strength = NumberInput(WeatherStrengthBox, "Интенсивность", 0, 10, true)
        if strength then SendGmCommand(".weather " .. selectedWeather .. " " .. strength) end
    end)

    local WeatherCancelBtn = ns.CreateNGButton(WeatherSection, "Сбросить погоду у себя", 200, 24)
    WeatherCancelBtn:SetPoint("TOPLEFT", WeatherSection, "TOPLEFT", 10, -102)
    WeatherCancelBtn:SetScript("OnClick", function()
        SendGmCommand(".weather cancel")
    end)

    -- Init
    UpdateChatOptions()
    GoTab:SetHeight(310)
    NpcTab:SetHeight(502)
    ToolsTab:SetHeight(570)
    TimeWeatherTab:SetHeight(268)
    ShowTab("chat")

    return f
end

-- ---------------------------------------------------------------------------
-- Slash command & registration
-- ---------------------------------------------------------------------------
C_Timer.After(0, function()
    ns.RegisterSlashCommand("NNMASTER", function() ns.ShowModule("Мастер") end, "nnmaster")
end)

ns.RegisterModule("Мастер", InitMasterModule, "GM/DM панель управления")


