-- Target inspector for the battle panel.
local _, ns = ...
local R = ns.RPSClient

local function HasTargetGuid(unit)
    return type(unit) == "table" and ((unit.targetGuid and unit.targetGuid ~= "") or (unit.guid and unit.guid ~= ""))
end

local function UnitTargetGuid(unit)
    if type(unit) ~= "table" then return nil end
    return unit.targetGuid or unit.guid
end

local function GetActiveInspectorUnit()
    if R and R.target and HasTargetGuid(R.target) then
        if not UnitExists or UnitExists("target") then
            R.remembered = R.target
            return R.target, "Текущая цель"
        end
    end
    if R and R.focus and HasTargetGuid(R.focus) and (not UnitExists or UnitExists("focus")) then
        return R.focus, "Запомненная цель (Фокус)"
    end
    if R and R.remembered and HasTargetGuid(R.remembered) then
        return R.remembered, "Запомненный юнит"
    end
    if R and R.target and HasTargetGuid(R.target) then
        return R.target, "Текущая цель"
    end
    return nil, "Нет цели"
end

local function Build(parent)
    local panel = CreateFrame("Frame", nil, parent); panel:SetAllPoints(parent)
    local status = ns.CreateNGLabel(panel, "Выберите цель в своей ролевой фазе.")
    status:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12)
    local scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -45)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 55)
    local content = CreateFrame("Frame", nil, scroll); content:SetSize(430, 550); scroll:SetScrollChild(content)
    local fields, statFields = {}, {}
    local schema = {
        { "curHealth", "Текущие ОЗ", 10 },
        { "maxHealth", "Максимальные ОЗ", 10 },
        { "curEnergy", "Текущие ОЭ", 0 },
        { "maxEnergy", "Максимальные ОЭ", 0 },
        { "armor", "Броня", 0 },
        { "speed", "Скорость", 10 },
        { "weaponDice", "Кость урона", "1d6" },
        { "blockDice", "Кость Блока", "1d4" },
    }
    local y, dirty, shown, pending = 0, false, nil, nil
    local pendingPayload, sentAt, retries
    local function Field(key, label, isStat, default)
        local text = ns.CreateNGLabel(content, label .. ":"); text:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y - 3)
        local box = ns.CreateNGEditBox(content, nil, 110, 22); box:SetAutoFocus(false)
        box:SetPoint("TOPLEFT", content, "TOPLEFT", 210, -y); box:SetText(tostring(default or 0))
        box:HookScript("OnTextChanged", function(_, userInput) if userInput then dirty = true end end)
        fields[key] = box; if isStat then statFields[key] = true end
        y = y + 28
    end
    for _, item in ipairs(schema) do Field(item[1], item[2], false, item[3]) end
    local function Registry()
        for _, def in ipairs(R.registry) do
            if (def.category == "combat" or def.category == "mastery") and not fields[def.key] then
                Field(def.key, (R.GetLocalizedStatName and R.GetLocalizedStatName(def.key)) or def.name, true, 0)
            end
        end
        content:SetHeight(y + 10)
    end
    Registry()
    local save = ns.CreateNGButton(panel, "Сохранить цель", 150, 26); save:SetPoint("BOTTOMLEFT", 12, 14)
    local refresh = ns.CreateNGButton(panel, "Обновить", 110, 26); refresh:SetPoint("LEFT", save, "RIGHT", 8, 0)
    local round = ns.CreateNGButton(panel, "Новый раунд цели", 160, 26); round:SetPoint("LEFT", refresh, "RIGHT", 8, 0)

    local function Display(explicitTarget, force)
        local target, sourceLabel = explicitTarget, "Текущая цель"
        if not target or not HasTargetGuid(target) then
            target, sourceLabel = GetActiveInspectorUnit()
        elseif R and target == R.focus then
            sourceLabel = "Запомненная цель (Фокус)"
        elseif R and target == R.remembered and target ~= R.target then
            sourceLabel = "Запомненный юнит"
        end

        local targetGuid = UnitTargetGuid(target)
        if not target or not targetGuid then
            shown = nil
            status:SetText("Выберите доступную цель.")
            save:SetEnabled(false)
            round:SetEnabled(false)
            return
        end
        target.targetGuid = targetGuid
        if not force and shown and UnitTargetGuid(shown) == targetGuid and dirty then
            status:SetText("Есть несохранённые изменения. Обновите данные при конфликте версии.")
            return
        end
        shown = target; dirty = false
        status:SetText(string.format("%s |cff88ccff[%s]|r%s%s",
            target.name or "Цель",
            sourceLabel,
            target.inSystem and "" or " (профиля нет, будет создан)",
            target.canEdit and "" or " - только просмотр"))
        for _, item in ipairs(schema) do fields[item[1]]:SetText(tostring(target[item[1]] or item[3])) end
        for key in pairs(statFields) do fields[key]:SetText(tostring(target.stats and target.stats[key] or 0)) end
        save:SetEnabled(target.canEdit == true and not pending)
        round:SetEnabled(target.canEdit == true and target.isPlayer == true and not pending)
    end

    local function Submit(beginRound)
        if not shown or not shown.canEdit or pending then return end
        if beginRound and dirty then ns.PrintError("Сначала сохраните или обновите поля цели."); return end
        local payload = { targetGuid = UnitTargetGuid(shown), revision = shown.revision or 0, beginRound = beginRound }
        if not beginRound then
            payload.stats = {}
            for key, box in pairs(fields) do
                local text = box:GetText()
                if statFields[key] then
                    payload.stats[key] = tonumber(text)
                    if payload.stats[key] == nil then ns.PrintError("Введите число: " .. key); return end
                elseif key == "weaponDice" or key == "blockDice" then
                    payload[key] = text
                else
                    payload[key] = tonumber(text)
                    if payload[key] == nil then ns.PrintError("Введите число: " .. key); return end
                end
            end
        end
        local id = R.RequestId()
        if R.Send("DmSaveTargetStats", payload, id) then
            pending = id; save:SetEnabled(false); round:SetEnabled(false)
            pendingPayload, sentAt, retries = payload, GetTime(), 0
            status:SetText("Ожидание подтверждения записи...")
        end
    end

    save:SetScript("OnClick", function() Submit(false) end)
    round:SetScript("OnClick", function() Submit(true) end)
    refresh:SetScript("OnClick", function()
        dirty = false
        R.Send("RequestTargetSync")
        if R.RequestVisibleUnitsSync then R.RequestVisibleUnitsSync() end
    end)
    ns.Subscribe("RPS_TARGET_CHANGED", "rps_dm_inspector", function(target) Display(target, false) end)
    ns.Subscribe("RPS_FOCUS_CHANGED", "rps_dm_focus_inspector", function() Display(nil, false) end)
    ns.Subscribe("RPS_REMEMBERED_CHANGED", "rps_dm_remembered_inspector", function() Display(nil, false) end)
    ns.Subscribe("RPS_PROFILE_CHANGED", "rps_dm_registry", Registry)
    ns.Subscribe("RPS_COMMITTED", "rps_dm_commit", function(receipt)
        if receipt.requestId ~= pending then return end
        pending = nil; dirty = false; Display(nil, true)
    end)
    ns.Subscribe("RPS_REQUEST_FAILED", "rps_dm_error", function(error)
        if error.requestId ~= pending then return end
        pending = nil; Display(nil, true)
        local label = (R.FormatSystemError and R.FormatSystemError(error.code)) or tostring(error.code)
        status:SetText("Запись не подтверждена: " .. label)
    end)
    panel:SetScript("OnShow", function()
        Registry()
        R.Send("RequestSync")
        R.Send("RequestTargetSync")
        if R.RequestVisibleUnitsSync then R.RequestVisibleUnitsSync() end
    end)
    panel:SetScript("OnUpdate", function()
        if not pending or GetTime() - sentAt < 10 then return end
        sentAt = GetTime(); retries = retries + 1
        if retries <= 2 then
            -- Retry the same immutable intent; never manufacture a fresh request ID.
            R.Send("DmSaveTargetStats", pendingPayload, pending)
        else
            pending = nil; dirty = false; Display(nil, true)
            status:SetText("Статус записи неизвестен. Обновите цель перед изменениями.")
            R.Send("RequestTargetSync")
        end
    end)
    Display(nil, true)
    return panel
end

ns.RegisterModule("Бой 3d6", Build, "Ролевые характеристики, инспектор цели и бюджет раунда")
