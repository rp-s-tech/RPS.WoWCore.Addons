-- Item edits use the server's modifier catalog and confirmed revisioned writes.
local _, ns = ...
local R = ns.RPSClient
if not R then return end
local SLOT_NAMES = { [0] = "Голова", "Шея", "Плечи", "Рубашка", "Грудь", "Пояс", "Ноги", "Ступни", "Запястья", "Кисти рук",
    "Палец 1", "Палец 2", "Аксессуар 1", "Аксессуар 2", "Спина", "Правая рука", "Левая рука", "Дальний бой", "Гербовая накидка" }
local GRADES = { [0] = "Низкое", "Обычное", "Необычное", "Редкое", "Эпическое", "Легендарное" }
local ACTIONS = { { "enchant", 0, "Характеристики" }, { "gem", 1, "Руна 1" }, { "gem", 2, "Руна 2" },
    { "gem", 3, "Руна 3" }, { "grade", 0, "Качество" }, { "ability", 0, "Способность" } }
local ERRORS = { no_gem_slot = "Для этой руны нужно повысить качество предмета.",
    stale_item = "Предмет уже изменён. Обновите данные.", save_failed = "Запись не подтверждена. Повторите сохранение.",
    actor_busy = "Предмет ещё сохраняется. Повторите сохранение.", invalid_reason = "Укажите причину изменения.",
    invalid_item_metadata = "Проверьте значения характеристик.", item_unavailable = "Предмет недоступен.",
    request_conflict = "Содержание запроса изменилось. Обновите данные." }
local ICONS = { item = "Interface\\Icons\\INV_Chest_Plate01", values = "Interface\\Icons\\INV_MISC_RUNE_01",
    save = "Interface\\Icons\\INV_Misc_Note_01" }
local function ItemName(entry)
    return C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(entry) or ("#" .. tostring(entry))
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
    local mark = section:CreateTexture(nil, "ARTWORK")
    mark:SetSize(16, 16)
    mark:SetTexture(icon)
    mark:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    mark:SetPoint("TOPLEFT", section, "TOPLEFT", 10, -6)
    section.Title:ClearAllPoints()
    section.Title:SetPoint("TOPLEFT", section, "TOPLEFT", 32, -8)
    section.Title:SetPoint("TOPRIGHT", section, "TOPRIGHT", -12, -8)
    return section
end
local function Build(parent)
    local panel = CreateFrame("Frame", nil, parent); panel:SetAllPoints(parent)
    local state, selectedSlot, fields, catalog, pending, expectedTarget = nil, nil, {}, {}, nil, nil
    local dirty, waiting, requestSerial = false, false, 0
    local slotDropdown, actionDropdown, gradeDropdown, abilityDropdown, reason
    local action, grade, serial, ability = ACTIONS[1], 1, 0, 0
    local itemBox = Section(panel, "Предмет", ICONS.item)
    itemBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    itemBox:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
    itemBox:SetHeight(120)
    -- "Свойства" is as tall as its fields, scrolling only when the window is too short; "Сохранение" follows it.
    local valuesBox = Section(panel, "Свойства", ICONS.values)
    valuesBox:SetPoint("TOPLEFT", itemBox, "BOTTOMLEFT", 0, -8)
    valuesBox:SetPoint("TOPRIGHT", itemBox, "BOTTOMRIGHT", 0, -8)
    valuesBox:SetHeight(200)
    local saveBox = Section(panel, "Сохранение", ICONS.save)
    saveBox:SetPoint("TOPLEFT", valuesBox, "BOTTOMLEFT", 0, -8)
    saveBox:SetPoint("TOPRIGHT", valuesBox, "BOTTOMRIGHT", 0, -8)
    saveBox:SetHeight(96)
    local status = ns.CreateNGLabel(itemBox, "Выберите игрока целью; без цели — ваши предметы.")
    status:SetPoint("TOPLEFT", itemBox, "TOPLEFT", 14, -34)
    local hint = ns.CreateNGLabel(valuesBox, "Целые значения со знаком. Пустое поле или 0 удаляет свойство.")
    hint:SetPoint("TOPLEFT", valuesBox, "TOPLEFT", 14, -34)
    local valuesScroll = CreateFrame("ScrollFrame", nil, valuesBox, "ScrollFrameTemplate")
    valuesScroll:SetPoint("TOPLEFT", valuesBox, "TOPLEFT", 8, -56)
    valuesScroll:SetPoint("BOTTOMRIGHT", valuesBox, "BOTTOMRIGHT", -28, 8)
    if type(valuesScroll.ScrollBar) == "table" and valuesScroll.ScrollBar.SetHideIfUnscrollable then
        valuesScroll.ScrollBar:SetHideIfUnscrollable(true)
    end
    local valuesContent = CreateFrame("Frame", nil, valuesScroll)
    valuesContent:SetSize(560, 220)
    valuesScroll:SetScrollChild(valuesContent)
    local ROW, FIXED = 27, 8 + 120 + 8 + 8 + 96 + 8
    local function Layout()
        local width = tonumber((panel.GetWidth and panel:GetWidth())) or 640
        local height = tonumber((panel.GetHeight and panel:GetHeight())) or 480
        local active = {}
        local editing = action[1] ~= "grade" and action[1] ~= "ability"
        for _, field in ipairs(fields) do if field.active then active[#active + 1] = field end end
        local inner = math.max(300, width - 16 - 36)
        local columns = inner >= 520 and 2 or 1
        local columnWidth = math.floor(inner / columns)
        local perColumn = math.ceil(#active / columns)
        for index, field in ipairs(active) do
            local column, row = math.floor((index - 1) / perColumn), (index - 1) % perColumn
            local x = column * columnWidth
            field.label:ClearAllPoints(); field.box:ClearAllPoints()
            field.label:SetPoint("TOPLEFT", valuesContent, "TOPLEFT", 6 + x, -4 - row * ROW)
            field.box:SetPoint("TOPLEFT", valuesContent, "TOPLEFT", x + math.min(200, columnWidth - 76), -row * ROW)
        end
        local rows = editing and perColumn or 0
        valuesContent:SetSize(inner, math.max(1, rows * ROW))
        local needed = 56 + rows * ROW + (rows > 0 and 10 or 0)
        valuesBox:SetHeight(math.max(64, math.min(needed, height - FIXED)))
    end
    panel:SetScript("OnSizeChanged", Layout)
    local function Current()
        for _, item in ipairs(state and state.slots or {}) do if item.slot == selectedSlot then return item end end
    end
    local function Fill()
        local item, values = Current(), {}
        dirty = false
        if action[1] == "gem" and (not item or action[2] > (item.gemSlots or 0)) then action = ACTIONS[1] end
        grade = item and item.grade or 1
        ability = item and catalog[item.enchant] and #(catalog[item.enchant].effects or {}) > 0 and item.enchant or 0
        if item then
            local metadata = item.metadata or {}
            if action[1] == "enchant" then values = metadata.properties
            else values = metadata.runes and metadata.runes[tostring(action[2])] end
            if not values then
                local id = action[1] == "enchant" and item.enchant or item.gems and item.gems[action[2]]
                values = catalog[id] and catalog[id].modifiers or {}
            end
        end
        for _, field in ipairs(fields) do
            field.label:SetShown(field.active and action[1] ~= "grade" and action[1] ~= "ability"); field.box:SetShown(field.active and action[1] ~= "grade" and action[1] ~= "ability")
            field.box:SetText(values[field.key] and tostring(values[field.key]) or "")
            field.box:EnableMouse(not pending); field.box:EnableKeyboard(not pending)
        end
        for _, dropdown in ipairs({ slotDropdown, actionDropdown, gradeDropdown, abilityDropdown }) do
            dropdown:SetEnabled(not pending); dropdown:GenerateMenu()
        end
        gradeDropdown:SetShown(action[1] == "grade"); abilityDropdown:SetShown(action[1] == "ability")
        hint:SetText(action[1] == "grade" and "Качество определяет число доступных рун."
            or action[1] == "ability" and "Способность применяется штатной механикой предмета."
            or "Целые значения со знаком. Пустое поле или 0 удаляет свойство.")
        Layout()
    end
    local label = ns.CreateNGLabel(itemBox, "Предмет:"); label:SetPoint("TOPLEFT", itemBox, "TOPLEFT", 14, -60)
    slotDropdown = ns.NNL.Widgets.CreateDropdown(itemBox, { width = 440, defaultText = "Выберите предмет", menu = function(_, root)
        for _, item in ipairs(state and state.slots or {}) do
            root:CreateRadio((SLOT_NAMES[item.slot] or item.slot) .. ": " .. ItemName(item.entry),
                function(v) return selectedSlot == v end, function(v) selectedSlot = v; Fill() end, item.slot)
        end
    end })
    slotDropdown:SetPoint("TOPLEFT", itemBox, "TOPLEFT", 110, -56)
    label = ns.CreateNGLabel(itemBox, "Изменить:"); label:SetPoint("TOPLEFT", itemBox, "TOPLEFT", 14, -92)
    actionDropdown = ns.NNL.Widgets.CreateDropdown(itemBox, { width = 190, defaultText = "Характеристики", menu = function(_, root)
        for _, entry in ipairs(ACTIONS) do
            local item = Current()
            if entry[1] ~= "gem" or (item and entry[2] <= (item.gemSlots or 0)) then
                root:CreateRadio(entry[3], function(v) return action == v end, function(v)
                    action = v; Fill()
                end, entry)
            end
        end
    end })
    actionDropdown:SetPoint("TOPLEFT", itemBox, "TOPLEFT", 110, -88)
    gradeDropdown = ns.NNL.Widgets.CreateDropdown(itemBox, { width = 140, defaultText = "Обычное", menu = function(_, root)
        for n = 0, #GRADES do root:CreateRadio(GRADES[n], function(v) return grade == v end, function(v) grade = v end, n) end
    end })
    gradeDropdown:SetPoint("LEFT", actionDropdown, "RIGHT", 8, 0); gradeDropdown:Hide()
    abilityDropdown = ns.NNL.Widgets.CreateDropdown(itemBox, { width = 240, defaultText = "Снять способность", menu = function(_, root)
        root:CreateRadio("Снять способность", function() return ability == 0 end, function() ability = 0 end)
        local ids = {}
        for id, entry in pairs(catalog) do if entry.kind == "enchant" and entry.effects and #entry.effects > 0 then ids[#ids + 1] = id end end
        table.sort(ids)
        for _, id in ipairs(ids) do root:CreateRadio(catalog[id].name, function(v) return ability == v end, function(v) ability = v end, id) end
    end })
    abilityDropdown:SetPoint("LEFT", actionDropdown, "RIGHT", 8, 0); abilityDropdown:Hide()
    label = ns.CreateNGLabel(saveBox, "Причина:"); label:SetPoint("TOPLEFT", saveBox, "TOPLEFT", 14, -38)
    reason = ns.CreateNGEditBox(saveBox, nil, 440, 22); reason:SetAutoFocus(false)
    reason:SetPoint("TOPLEFT", saveBox, "TOPLEFT", 110, -34)
    local function Target()
        local unit = R.target
        return type(unit) == "table" and unit.isPlayer == true and (unit.targetGuid or unit.guid) or nil
    end
    local Request
    local function Bind()
        if not R.Bind() or not R.handlers then return false end
        R.handlers.ItemEnchantState = function(_, payload)
            if type(payload) ~= "table" then return end
            if expectedTarget and payload.state and payload.state.target ~= expectedTarget then return end
            if payload.requestId and payload.requestId ~= requestSerial then return end
            if pending or dirty then return end
            state = payload.state
            if payload.catalog then
                catalog = {}
                for _, item in ipairs(payload.catalog) do catalog[item.id] = item end
            end
            if payload.stats then
                for _, field in ipairs(fields) do field.active = false; field.label:Hide(); field.box:Hide() end
                for index, stat in ipairs(payload.stats) do
                    local field = fields[index]
                    if not field then
                        field = { label = ns.CreateNGLabel(valuesContent, ""), box = ns.CreateNGEditBox(valuesContent, nil, 66, 22) }
                        fields[index] = field; field.box:SetAutoFocus(false)
                        field.box:SetScript("OnTextChanged", function(_, userInput) if userInput then dirty = true end end)
                    end
                    field.key, field.limit, field.active = stat.key, stat.limit, true
                    field.label:SetText(stat.label .. ":")
                end
            end
            status:SetText(state and ("Предметы: " .. tostring(state.name)) or "Игрок не найден.")
            Fill()
        end
        R.handlers.ItemMetadataResult = function(_, result)
            if type(result) ~= "table" or not pending or result.requestId ~= pending.id then return end
            waiting = false
            if result.ok then
                pending, dirty = nil, false
                if result.state and result.state.target == expectedTarget then
                    R.handlers.ItemEnchantState(nil, {state = result.state})
                else Request() end
                status:SetText("Характеристики сохранены.")
            else
                if result.code ~= "save_failed" and result.code ~= "actor_busy" then
                    pending = nil
                    for _, dropdown in ipairs({ slotDropdown, actionDropdown, gradeDropdown, abilityDropdown }) do dropdown:SetEnabled(true) end
                    for _, field in ipairs(fields) do field.box:EnableMouse(true); field.box:EnableKeyboard(true) end
                end
                status:SetText(ERRORS[result.code] or "Изменение отклонено. Проверьте предмет и обновите данные.")
            end
        end
        R.handlers.ItemEnchantResult = function(_, result)
            if type(result) ~= "table" or (result.target and result.target ~= expectedTarget) then return end
            status:SetText(result.ok and (result.operation == "ability" and "Способность изменена." or "Качество изменено.")
                or ERRORS[result.code] or "Изменение отклонено. Обновите данные.")
        end
        return true
    end
    Request = function()
        if Bind() then
            local nextTarget = Target() or (UnitGUID and UnitGUID("player"))
            if nextTarget ~= expectedTarget then
                selectedSlot, state, pending, waiting = nil, nil, nil, false
                Fill()
            end
            expectedTarget = nextTarget
            requestSerial = requestSerial + 1
            R.Send("RequestItemEnchantState", Target(), requestSerial)
        end
    end
    local apply = ns.CreateNGButton(saveBox, "Сохранить", 130, 26); apply:SetPoint("BOTTOMLEFT", saveBox, "BOTTOMLEFT", 12, 10)
    local refresh = ns.CreateNGButton(panel, "Обновить", 110, 26); refresh:SetPoint("LEFT", apply, "RIGHT", 8, 0)
    apply:SetScript("OnClick", function()
        if not Bind() then return end
        if pending then waiting = true; R.Send("DmItemProperties", unpack(pending.args)); return end
        local item = Current()
        if not item then ns.PrintError("Выберите предмет."); return end
        requestSerial = requestSerial + 1
        if action[1] == "grade" then R.Send("DmItemEnchant", state.target, 255, item.slot, "grade", 0, grade); return end
        if action[1] == "ability" then R.Send("DmItemEnchant", state.target, 255, item.slot, "ability", 0, ability); return end
        local values = {}
        for _, field in ipairs(fields) do
            if field.active then
                local text = field.box:GetText(); local value = text == "" and 0 or tonumber(text)
                if not value or value % 1 ~= 0 or math.abs(value) > field.limit then
                    ns.PrintError("Допустимое значение: от -" .. field.limit .. " до " .. field.limit .. "."); return
                end
                if value ~= 0 then values[field.key] = value end
            end
        end
        if #reason:GetText() < 3 then ns.PrintError("Укажите причину изменения."); return end
        serial = serial + 1
        local id = "item_" .. tostring(GetServerTime()) .. "_" .. tostring(math.floor(GetTime() * 1000)) .. "_" .. serial
        pending = { id = id, args = { state.target, item.guid, item.slot, item.metadata and item.metadata.revision or 0,
            action[1], action[2], values, reason:GetText(), id } }
        waiting = true
        for _, dropdown in ipairs({ slotDropdown, actionDropdown, gradeDropdown, abilityDropdown }) do dropdown:SetEnabled(false) end
        for _, field in ipairs(fields) do field.box:ClearFocus(); field.box:EnableMouse(false); field.box:EnableKeyboard(false) end
        status:SetText("Сохранение… Повторное нажатие проверит тот же запрос.")
        R.Send("DmItemProperties", unpack(pending.args))
    end)
    refresh:SetScript("OnClick", function()
        if waiting then status:SetText("Дождитесь сохранения или повторите его тем же запросом."); return end
        pending, dirty = nil, false; status:SetText("Обновление предметов…"); Request()
    end)
    ns.Subscribe("RPS_TARGET_CHANGED", "rps_dm_items", function()
        if (Target() or (UnitGUID and UnitGUID("player"))) == expectedTarget then return end
        if panel:IsShown() then Request() end
    end)
    panel:SetScript("OnShow", Request)
    return panel
end
ns.RegisterModule("Предметы RP", Build, "Характеристики, руны и качество предметов")
