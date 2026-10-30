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

local ICONS = {
    target = "Interface\\Icons\\Ability_Marksmanship",
    stats = "Interface\\Icons\\INV_Misc_Dice_01",
    xp = "Interface\\Icons\\INV_Misc_Book_11",
    resources = "Interface\\Icons\\Spell_Holy_Restoration",
    defense = "Interface\\Icons\\INV_Shield_06",
    combat = "Interface\\Icons\\INV_Sword_04",
    mastery = "Interface\\Icons\\Spell_Holy_SealOfWisdom",
}

local function Icon(parent, path, size)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size or 16, size or 16)
    icon:SetTexture(path)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return icon
end

-- Titled block with an icon and a divider under the title (NobleNextLib section style).
local function Section(parent, title, icon)
    local widgets = ns.NNL and ns.NNL.Widgets
    local section
    if widgets and widgets.CreateSection then
        section = widgets.CreateSection(parent, { title = title })
    else
        section = CreateFrame("Frame", nil, parent)
        section.Title = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        section.Title:SetText(title)
    end
    Icon(section, icon):SetPoint("TOPLEFT", section, "TOPLEFT", 10, -6)
    section.Title:ClearAllPoints()
    section.Title:SetPoint("TOPLEFT", section, "TOPLEFT", 32, -8)
    section.Title:SetPoint("TOPRIGHT", section, "TOPRIGHT", -12, -8)
    return section
end

local function Build(parent)
    local panel = CreateFrame("Frame", nil, parent); panel:SetAllPoints(parent)
    local targetBox = Section(panel, "Цель", ICONS.target)
    targetBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    targetBox:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
    targetBox:SetHeight(58)
    local status = ns.CreateNGLabel(targetBox, "Выберите цель в своей ролевой фазе.")
    status:SetPoint("TOPLEFT", targetBox, "TOPLEFT", 14, -34)
    status:SetPoint("TOPRIGHT", targetBox, "TOPRIGHT", -14, -34)

    local xpBox = Section(panel, "Выдача опыта", ICONS.xp)
    xpBox:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 8)
    xpBox:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)
    xpBox:SetHeight(66)

    local statsBox = Section(panel, "Характеристики цели", ICONS.stats)
    statsBox:SetPoint("TOPLEFT", targetBox, "BOTTOMLEFT", 0, -8)
    statsBox:SetPoint("BOTTOMRIGHT", xpBox, "TOPRIGHT", 0, 8)
    local scroll = CreateFrame("ScrollFrame", nil, statsBox, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", statsBox, "TOPLEFT", 10, -34)
    scroll:SetPoint("BOTTOMRIGHT", statsBox, "BOTTOMRIGHT", -28, 46)
    if type(scroll.ScrollBar) == "table" and scroll.ScrollBar.SetHideIfUnscrollable then
        scroll.ScrollBar:SetHideIfUnscrollable(true)
    end
    local content = CreateFrame("Frame", nil, scroll); content:SetSize(430, 550); scroll:SetScrollChild(content)
    local fields, statFields, groups = {}, {}, {}
    local schema = {
        { "Ресурсы", ICONS.resources, {
            { "curHealth", "Текущие ОЗ", 10 },
            { "maxHealth", "Максимальные ОЗ", 10 },
            { "curEnergy", "Текущие ОЭ", 0 },
            { "maxEnergy", "Максимальные ОЭ", 0 } } },
        { "Защита и урон", ICONS.defense, {
            { "armor", "Броня", 0 },
            { "speed", "Скорость", 10 },
            { "weaponDice", "Кость урона", "1d6" },
            { "blockDice", "Кость Блока", "1d4" } } },
    }
    local y, dirty, shown, pending = 0, false, nil, nil
    local pendingPayload, sentAt, retries
    -- Groups are laid out by Reflow: one column in a narrow window, two (shortest column first) in a wide one.
    local blocks = {}
    local function Group(title, icon)
        local line = content:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 0.82, 0, 0.2)
        line:SetHeight(1)
        blocks[#blocks + 1] = { icon = Icon(content, icon, 14),
            label = ns.CreateNGLabel(content, "|cffffd100" .. title .. "|r"), line = line, fields = {} }
    end
    local function Field(key, label, isStat, default)
        local text = ns.CreateNGLabel(content, label .. ":")
        local box = ns.CreateNGEditBox(content, nil, 110, 22); box:SetAutoFocus(false)
        box:SetText(tostring(default or 0))
        box:HookScript("OnTextChanged", function(_, userInput) if userInput then dirty = true end end)
        fields[key] = box; if isStat then statFields[key] = true end
        local block = blocks[#blocks]
        block.fields[#block.fields + 1] = { text = text, box = box }
    end
    local function Reflow()
        local width = math.max(300, tonumber((scroll.GetWidth and scroll:GetWidth())) or 430)
        local columns = width >= 640 and 2 or 1
        local columnWidth = math.floor(width / columns)
        local heights = { 0, 0 }
        for _, block in ipairs(blocks) do
            local column = (columns == 2 and heights[2] < heights[1]) and 2 or 1
            local x, top = (column - 1) * columnWidth, heights[column]
            if top > 0 then top = top + 8 end
            block.icon:ClearAllPoints(); block.icon:SetPoint("TOPLEFT", content, "TOPLEFT", x, -top - 1)
            block.label:ClearAllPoints(); block.label:SetPoint("TOPLEFT", content, "TOPLEFT", x + 20, -top)
            block.line:ClearAllPoints(); block.line:SetPoint("TOPLEFT", content, "TOPLEFT", x, -top - 18)
            block.line:SetWidth(columnWidth - 16)
            top = top + 26
            for _, field in ipairs(block.fields) do
                field.text:ClearAllPoints(); field.text:SetPoint("TOPLEFT", content, "TOPLEFT", x + 10, -top - 3)
                field.box:ClearAllPoints()
                field.box:SetPoint("TOPLEFT", content, "TOPLEFT", x + math.min(190, columnWidth - 130), -top)
                top = top + 28
            end
            heights[column] = top
        end
        y = math.max(heights[1], heights[2])
        content:SetSize(width, y + 10)
    end
    scroll:SetScript("OnSizeChanged", Reflow)
    local baseFields = {}
    for _, group in ipairs(schema) do
        Group(group[1], group[2])
        for _, item in ipairs(group[3]) do
            Field(item[1], item[2], false, item[3])
            baseFields[#baseFields + 1] = item
        end
    end
    local REGISTRY_GROUPS = { { "combat", "Боевые бонусы", ICONS.combat }, { "mastery", "Мастерство", ICONS.mastery } }
    local function Registry()
        for _, group in ipairs(REGISTRY_GROUPS) do
            for _, def in ipairs(R.registry) do
                if def.category == group[1] and not fields[def.key] then
                    if not groups[group[1]] then groups[group[1]] = true; Group(group[2], group[3]) end
                    Field(def.key, (R.GetLocalizedStatName and R.GetLocalizedStatName(def.key)) or def.name, true, 0)
                end
            end
        end
        Reflow()
    end
    Registry()
    local save = ns.CreateNGButton(statsBox, "Сохранить цель", 150, 26); save:SetPoint("BOTTOMLEFT", statsBox, "BOTTOMLEFT", 12, 10)
    local refresh = ns.CreateNGButton(statsBox, "Обновить", 110, 26); refresh:SetPoint("LEFT", save, "RIGHT", 8, 0)
    local round = ns.CreateNGButton(statsBox, "Новый раунд цели", 160, 26); round:SetPoint("LEFT", refresh, "RIGHT", 8, 0)
    -- XP only from the DM; the server checks staff rights and replays the same requestId idempotently.
    local xpLabel = ns.CreateNGLabel(xpBox, "Опыт:"); xpLabel:SetPoint("TOPLEFT", xpBox, "TOPLEFT", 14, -38)
    local xpAmount = ns.CreateNGEditBox(xpBox, nil, 50, 22); xpAmount:SetAutoFocus(false)
    xpAmount:SetPoint("TOPLEFT", xpBox, "TOPLEFT", 60, -34); xpAmount:SetText("")
    local xpReasonLabel = ns.CreateNGLabel(xpBox, "Причина:"); xpReasonLabel:SetPoint("LEFT", xpAmount, "RIGHT", 12, 0)
    local xpReason = ns.CreateNGEditBox(xpBox, nil, 210, 22); xpReason:SetAutoFocus(false)
    xpReason:SetPoint("LEFT", xpReasonLabel, "RIGHT", 8, 0); xpReason:SetText("")
    local xpGrant = ns.CreateNGButton(xpBox, "Выдать XP", 100, 24); xpGrant:SetPoint("LEFT", xpReason, "RIGHT", 8, 0)
    local xpWatch = CreateFrame("Frame", nil, panel)
    NobleNextCharDB = NobleNextCharDB or {}
    local xpPending = NobleNextCharDB.rpsPendingXpGrant
    if xpPending then xpPending.sentAt, xpPending.retries = GetTime(), 0 end
    local function SetXpPending(value)
        xpPending = value
        NobleNextCharDB.rpsPendingXpGrant = value
    end

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
            xpGrant:SetEnabled(xpPending ~= nil and xpPending.retries > 2)
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
        for _, item in ipairs(baseFields) do fields[item[1]]:SetText(tostring(target[item[1]] or item[3])) end
        for key in pairs(statFields) do fields[key]:SetText(tostring(target.stats and target.stats[key] or 0)) end
        save:SetEnabled(target.canEdit == true and not pending)
        round:SetEnabled(target.canEdit == true and target.isPlayer == true and not pending)
        xpGrant:SetEnabled((xpPending ~= nil and xpPending.retries > 2) or (target.isPlayer == true and not xpPending))
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

    local function GrantXp()
        if xpPending then
            local a = xpPending.args
            xpPending.sentAt, xpPending.retries = GetTime(), 0
            R.Send("DmGrantXp", a[1], a[2], a[3], a[4])
            xpGrant:SetEnabled(false)
            status:SetText("Проверка прежней выдачи опыта: ожидание подтверждения...")
            return
        end
        if not shown or shown.isPlayer ~= true then return end
        local amount = tonumber(xpAmount:GetText())
        if not amount or amount < 1 or amount > 500 or amount % 1 ~= 0 then
            ns.PrintError("Опыт: целое число от 1 до 500."); return
        end
        local reason = (xpReason:GetText() or ""):match("^%s*(.-)%s*$")
        if #reason < 3 then ns.PrintError("Укажите причину выдачи опыта."); return end
        local id = R.RequestId()
        local args = { UnitTargetGuid(shown), amount, reason, id }
        if R.Send("DmGrantXp", args[1], args[2], args[3], args[4]) then
            SetXpPending({ id = id, args = args, sentAt = GetTime(), retries = 0, name = shown.name })
            xpGrant:SetEnabled(false)
            status:SetText("Выдача опыта: ожидание ответа сервера...")
        end
    end
    xpGrant:SetScript("OnClick", GrantXp)
    xpWatch:SetScript("OnUpdate", function()
        if not xpPending or xpPending.retries > 2 or GetTime() - xpPending.sentAt < 10 then return end
        xpPending.sentAt = GetTime(); xpPending.retries = xpPending.retries + 1
        if xpPending.retries <= 2 then
            local a = xpPending.args
            R.Send("DmGrantXp", a[1], a[2], a[3], a[4])
        else
            xpGrant:SetEnabled(true)
            xpGrant:SetText("Проверить выдачу")
            status:SetText("Подтверждение не получено. Проверьте прежнюю выдачу тем же запросом.")
        end
    end)
    ns.Subscribe("RPS_XP_GRANT_RESULT", "rps_dm_xp", function(result)
        if not xpPending or result.requestId ~= xpPending.id then return end
        if not result.ok and (result.code == "request_pending" or result.code == "pending_recovery"
            or result.code == "receipt_incomplete") then
            status:SetText("Выдача опыта ожидает подтверждения. Проверяется прежний запрос.")
            return
        end
        local name = xpPending.name or "Игрок"
        SetXpPending(nil)
        xpGrant:SetText("Выдать XP")
        xpGrant:SetEnabled(shown ~= nil and shown.isPlayer == true)
        if result.ok then
            xpReason:SetText("")
            status:SetText(string.format("%s: опыт выдан, уровень %s (RP %s)%s", name, tostring(result.newLevel),
                tostring(result.rpLevel or "?"), result.code and (" — " .. tostring(result.code)) or ""))
        else
            local label = (ns.Progression and ns.Progression.ErrorText and ns.Progression.ErrorText(result.code))
                or (R.FormatSystemError and R.FormatSystemError(result.code)) or tostring(result.code)
            status:SetText("Опыт не выдан: " .. label)
        end
    end)
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
