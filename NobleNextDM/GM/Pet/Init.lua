-- Loaded through the NobleNextDM private extension namespace.
local _, ns = ...

-- The chat protocol has no request ID. Translate only the exact usage reply for
-- a command sent by this panel, then at most its immediately following detail.
local pendingReply, filterInstalled
local PET_COMMANDS = { say=true, emote=true, stay=true, follow=true, play=true, pos=true, tele=true }
local function FilterPetReply(_, _, message, ...)
    if not pendingReply or GetTime() > pendingReply.expires
        or (issecretvalue and issecretvalue(message)) or type(message) ~= "string" then return false end
    local plain = message:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local lineID = select(10, ...)
    if (issecretvalue and issecretvalue(lineID)) or type(lineID) ~= "number" or lineID <= 0 then lineID = nil end
    local command = plain:match("^There is no detailed usage information associated with 'pet (%a+)'%.?$")
    if command == pendingReply.command then
        if not pendingReply.helpSeen then
            pendingReply.helpSeen = true
            pendingReply.helpLine = lineID
            pendingReply.detailUntil = math.min(pendingReply.expires, GetTime() + 0.5)
        end
        return false, "NobleNext: команда спутника не выполнена. Убедитесь, что спутник призван, активен и выбран в цели; вы должны иметь право управлять им.", ...
    end
    if pendingReply.detailUntil and GetTime() <= pendingReply.detailUntil
        and plain:match("^If this is a custom command, use 'trinity_string'")
        and (not lineID or not pendingReply.helpLine or lineID == pendingReply.helpLine + 1) then
        return true
    end
    -- Any intervening system message breaks the two-line reply correlation.
    pendingReply.detailUntil = nil
    return false
end

local function SendGmCommand(cmd)
    pendingReply = nil
    if not UnitExists("target") or UnitIsPlayer("target") then
        ns.PrintError("Призовите спутника и выберите его в цели.")
        return false
    end
    local addFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
    if not filterInstalled and addFilter then
        addFilter("CHAT_MSG_SYSTEM", FilterPetReply)
        filterInstalled = true
    end
    if not ns.RunGmCommand(cmd) then
        ns.PrintError("Не удалось отправить действие спутника. Проверьте доступ и повторите попытку.")
        return false
    end
    local command = cmd:match("^%.pet (%a+)")
    if PET_COMMANDS[command] then pendingReply = {command=command, expires=GetTime() + 2.5} end
    return true
end

local function InitPetModule(parent)
    local host = CreateFrame("Frame", nil, parent)
    host:SetAllPoints(parent)
    host:Hide()
    local scroll = ns.NNL.Scroll.CreateFrame(host)
    scroll:SetPoint("TOPLEFT", host, "TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -22, 0)
    local f = CreateFrame("Frame", nil, scroll)
    f:SetWidth(math.max(1, scroll:GetWidth()))
    f:SetHeight(460)
    scroll:SetScrollChild(f)
    scroll:HookScript("OnSizeChanged", function(_, width) f:SetWidth(math.max(1, width)) end)

    local title = ns.CreateNGLabel(f, "Выберите своего спутника в цели. Все действия применяются к нему.")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -10)
    title:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    title:SetJustifyH("LEFT")

    local function section(text, height, previous)
        local frame = ns.CreateNGSection(f, text, nil, height)
        if previous then
            frame:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -8)
            frame:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, -8)
        else
            frame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -34)
            frame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -34)
        end
        return frame
    end
    local function button(owner, text, x, y, width, action, tooltip)
        local btn = ns.NNL.Widgets.CreateButton(owner, {
            text = text, width = width, height = 24, onClick = action, tooltip = tooltip,
        })
        btn:SetPoint("TOPLEFT", owner, "TOPLEFT", x, y)
        return btn
    end

    local actions = section("Речь и движение", 102)
    local textBox = ns.CreateNGEditBox(actions, "PetTextBox", 300, 24)
    textBox:SetPoint("TOPLEFT", actions, "TOPLEFT", 14, -34)
    textBox:SetPoint("RIGHT", actions, "RIGHT", -14, 0)
    local function speak(command)
        local text = (textBox:GetText() or ""):match("^%s*(.-)%s*$")
        if text == "" then ns.PrintError("Введите реплику или описание действия спутника."); return end
        if SendGmCommand(command .. text) then textBox:SetText(""); textBox:ClearFocus() end
    end
    button(actions, "Сказать", 14, -66, 100, function() speak(".pet say ") end, "Реплика от имени спутника")
    button(actions, "Действие", 122, -66, 100, function() speak(".pet emote ") end, "Текстовое действие, а не анимация")
    button(actions, "Стоять", 230, -66, 100, function() SendGmCommand(".pet stay") end, "Остановить движение спутника")
    button(actions, "Ко мне", 338, -66, 100, function() SendGmCommand(".pet tele") end, "Телепортировать спутника к персонажу")

    local follow = section("Следование", 70, actions)
    local distanceLabel = ns.CreateNGLabel(follow, "Дистанция, ярды:")
    distanceLabel:SetPoint("TOPLEFT", follow, "TOPLEFT", 14, -40)
    local distance = ns.CreateNGEditBox(follow, "PetDistBox", 72, 24)
    distance:SetPoint("TOPLEFT", follow, "TOPLEFT", 145, -34)
    -- C++ accepts Optional<float>; SetNumeric(true) would reject the decimal separator.
    distance:SetText("3")
    button(follow, "Следовать", 230, -34, 120, function()
        local value = tonumber(((distance:GetText() or ""):gsub(",", ".")))
        if not value or value ~= value or value == math.huge or value < 0 then
            ns.PrintError("Введите неотрицательную дистанцию, например 3 или 2,5.")
            return
        end
        SendGmCommand(".pet follow " .. tostring(value))
    end, "Дистанция в ярдах. Угол следования задаёт сервер; отдельный угол сейчас не поддерживается.")

    local pose = section("Положение тела", 66, follow)
    -- .pet pos uses UnitStandStateType, unlike Army's EmoteState.
    local standState = 0
    local poseDropdown = ns.NNL.Widgets.CreateDropdown(pose, {
        name = "NobleNextPetPoseDropdown", width = 180, defaultText = "Положение тела",
        menu = function(_, root)
            for _, entry in ipairs({ { "Стоять", 0 }, { "Сидеть", 1 }, { "Спать", 3 }, { "Мёртв", 7 } }) do
                root:CreateRadio(entry[1], function(value) return standState == value end,
                    function(value) standState = value end, entry[2])
            end
        end,
    })
    poseDropdown:SetPoint("TOPLEFT", pose, "TOPLEFT", 14, -34)
    button(pose, "Применить позу", 206, -34, 142,
        function() SendGmCommand(".pet pos " .. standState) end)

    local animation = section("Анимация", 164, pose)
    -- One-shot and state IDs are different enum entries, not interchangeable modes.
    local isState = false
    local presetDropdown, modeDropdown
    local emote = ns.CreateNGEditBox(animation, "PetEmoteBox", 72, 24)
    emote:SetPoint("TOPLEFT", animation, "TOPLEFT", 324, -66)
    emote:SetNumeric(true)
    emote:SetText("1")
    local presetLabel = ns.CreateNGLabel(animation, "Пресет:")
    presetLabel:SetPoint("TOPLEFT", animation, "TOPLEFT", 14, -40)
    presetDropdown = ns.NNL.Widgets.CreateDropdown(animation, {
        name = "NobleNextPetEmoteDropdown", width = 260, defaultText = "Свой ID анимации",
        menu = function(_, root)
            for _, family in ipairs({
                { title = "Однократные", state = false, entries = { { "Говорить", 1 }, { "Поклон", 2 }, { "Салют", 66 }, { "Атака без оружия", 35 } } },
                { title = "Постоянные", state = true, entries = { { "Разговор", 378 }, { "Танец", 10 }, { "Работа", 173 }, { "Сброс", 0 } } },
            }) do
                root:CreateTitle(family.title)
                for _, entry in ipairs(family.entries) do
                    local preset = { id = entry[2], state = family.state }
                    root:CreateRadio(entry[1], function(value)
                        return isState == value.state and tonumber(emote:GetText()) == value.id
                    end, function(value)
                        isState = value.state
                        emote:SetText(tostring(value.id))
                        if modeDropdown then modeDropdown:GenerateMenu() end
                    end, preset)
                end
            end
        end,
    })
    presetDropdown:SetPoint("TOPLEFT", animation, "TOPLEFT", 104, -34)
    local modeLabel = ns.CreateNGLabel(animation, "Режим:")
    modeLabel:SetPoint("TOPLEFT", animation, "TOPLEFT", 14, -72)
    modeDropdown = ns.NNL.Widgets.CreateDropdown(animation, {
        name = "NobleNextPetEmoteModeDropdown", width = 170, defaultText = "Режим анимации",
        menu = function(_, root)
            for _, entry in ipairs({ { "Однократно", false }, { "Постоянно", true } }) do
                root:CreateRadio(entry[1], function(value) return isState == value end,
                    function(value) isState = value; presetDropdown:GenerateMenu() end, entry[2])
            end
        end,
    })
    modeDropdown:SetPoint("TOPLEFT", animation, "TOPLEFT", 104, -66)
    local idLabel = ns.CreateNGLabel(animation, "ID:")
    idLabel:SetPoint("TOPLEFT", animation, "TOPLEFT", 290, -72)
    emote:HookScript("OnTextChanged", function() presetDropdown:GenerateMenu() end)
    local function play()
        local id = tonumber(emote:GetText())
        if not id or id < 0 or id > 4294967295 or id ~= math.floor(id) then
            ns.PrintError("Введите целый ID анимации от 0 до 4294967295.")
            return
        end
        SendGmCommand(".pet play " .. id .. (isState and " 1" or ""))
    end
    button(animation, "Применить", 406, -66, 112, play)
    local hint = ns.CreateNGLabel(animation, "Выбор пресета не отправляет команду. Для своего ID выберите режим: разовые и постоянные анимации различаются. Результат зависит от модели.")
    hint:SetPoint("TOPLEFT", animation, "TOPLEFT", 14, -106)
    hint:SetPoint("RIGHT", animation, "RIGHT", -14, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    local function UpdateHintHeight()
        local height = math.max(164, 106 + hint:GetStringHeight() + 14)
        if animation:GetHeight() ~= height then animation:SetHeight(height) end
        f:SetHeight(34 + 102 + 8 + 70 + 8 + 66 + 8 + height + 12)
    end
    animation:HookScript("OnSizeChanged", UpdateHintHeight)
    host:HookScript("OnShow", UpdateHintHeight)
    UpdateHintHeight()
    return host
end

ns.RegisterModule("Спутник", InitPetModule, "Речь, движение и анимации вашего спутника")
C_Timer.After(0, function()
    ns.RegisterSlashCommand("NNPET", function() ns.ShowModule("Спутник") end, "nnpet")
end)
