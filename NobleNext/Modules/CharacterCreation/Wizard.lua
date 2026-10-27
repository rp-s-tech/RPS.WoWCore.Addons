-- Wizard window: six steps over the session draft, sheet and errors from the server preview.
-- Own insecure frames parented to UIParent; no Blizzard frame is modified. No text input:
-- RP names live in TotalRP, so keyboard focus never leaves the game.
local _, ns = ...
local C = ns.CharacterCreation
local W = { rows = {} }
C.Wizard = W

local WIDTH, HEIGHT = 720, 560
local LIST_WIDTH, LIST_HEIGHT = 400, 370
local SIDE_X, SIDE_WIDTH, SIDE_HEIGHT = 450, 236, 392
local RED, GOLD, GRAY, LABEL, GREEN, WHITE, ORANGE = "ff5a5a", "ffd100", "999999", "c8c8c8", "4cff4c", "ffffff", "ff9933"

local function Paint(hex, text) return "|cff" .. hex .. tostring(text) .. "|r" end

local function Plain(text)
    return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
W.Plain = Plain

local function Text(parent, template, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    if width then fs:SetWidth(width) end
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    return fs
end

local function Signed(value)
    if type(value) ~= "number" then return tostring(value) end
    return value > 0 and ("+" .. value) or tostring(value)
end

local function SignedColor(value)
    if type(value) ~= "number" then return WHITE end
    return value > 0 and GREEN or value < 0 and RED or WHITE
end

-- Block layout shared by the sheet panel and the summary step.
-- items: { header, color? } | { label, value, color? } | { para } | { gap }.
local function NewPool(parent, width, labelWidth, valueJustify)
    return { parent = parent, width = width, labelWidth = labelWidth, valueJustify = valueJustify, lines = {} }
end

local function PoolLine(pool, index)
    local line = pool.lines[index]
    if not line then
        line = { Left = Text(pool.parent), Right = Text(pool.parent) }
        pool.lines[index] = line
    end
    return line
end

local function RenderBlocks(pool, items, top)
    local y, used, plain = top, 0, {}
    for _, item in ipairs(items) do
        if item.gap then
            y = y + item.gap
        else
            used = used + 1
            local line = PoolLine(pool, used)
            local left, right = line.Left, line.Right
            left:ClearAllPoints()
            left:SetPoint("TOPLEFT", pool.parent, "TOPLEFT", 4, -y)
            left:SetFontObject(item.header and "GameFontNormal" or "GameFontHighlightSmall")
            right:Hide()
            if item.header then
                left:SetWidth(pool.width)
                left:SetText(Paint(item.color or GOLD, item.header))
                y = y + 18
            elseif item.label then
                left:SetWidth(pool.labelWidth)
                left:SetText(Paint(LABEL, item.label))
                right:ClearAllPoints()
                right:SetPoint("TOPLEFT", pool.parent, "TOPLEFT", 4 + pool.labelWidth + 4, -y)
                right:SetWidth(pool.width - pool.labelWidth - 4)
                right:SetJustifyH(pool.valueJustify)
                right:SetText(Paint(item.color or WHITE, item.value))
                right:Show()
                local height = math.max(14, right.GetStringHeight and right:GetStringHeight() or 14)
                y = y + math.min(height, 40) + 2
            else
                left:SetWidth(pool.width)
                left:SetText(item.para)
                y = y + (left.GetStringHeight and left:GetStringHeight() or 14) + 4
            end
            left:Show()
            plain[#plain + 1] = Plain(item.header or (item.label and (item.label .. " " .. tostring(item.value))) or item.para)
        end
    end
    for i = used + 1, #pool.lines do
        pool.lines[i].Left:Hide()
        pool.lines[i].Right:Hide()
    end
    return y, table.concat(plain, "\n")
end

local function Row(index)
    local row = W.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, W.content)
    row:SetSize(LIST_WIDTH - 24, 24)
    row.Bg = row:CreateTexture(nil, "BACKGROUND")
    row.Bg:SetAllPoints()
    row.Bg:SetColorTexture(1, 1, 1, 0.06)
    row.Selected = row:CreateTexture(nil, "BORDER")
    row.Selected:SetAllPoints()
    row.Selected:SetColorTexture(0.85, 0.6, 0.1, 0.35)
    row.Edge = row:CreateTexture(nil, "ARTWORK")
    row.Edge:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.Edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.Edge:SetWidth(3)
    row.Edge:SetColorTexture(1, 0.82, 0, 0.9)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.Label = Text(row, "GameFontHighlight", LIST_WIDTH - 150)
    row.Label:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -5)
    row.Right = Text(row, "GameFontHighlightSmall", 120)
    row.Right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
    row.Right:SetJustifyH("RIGHT")
    row.Sub = Text(row, "GameFontHighlightSmall", LIST_WIDTH - 48)
    row.Sub:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -21)
    row:SetScript("OnClick", function(self)
        if self.entry and self.entry.onClick and not self.entry.disabled then self.entry.onClick() end
    end)
    row:SetScript("OnEnter", function(self)
        local entry = self.entry
        if not entry or not entry.tooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(entry.title or entry.text)
        GameTooltip:AddLine(entry.tooltip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    W.rows[index] = row
    return row
end

-- entries: { header=true, text } or { text, right?, sub?, check?, selected, disabled, tooltip, onClick }.
local function RenderRows(entries, top)
    local y = top
    for i, entry in ipairs(entries) do
        local row = Row(i)
        row.entry = entry
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", W.content, "TOPLEFT", 0, -y)
        local height = 24
        if entry.header then
            row.Label:SetText(Paint(GOLD, entry.text))
            row.Right:SetText("")
            row.Sub:SetText("")
            row.Bg:Hide(); row.Selected:Hide(); row.Edge:Hide()
            height = 22
            y = y + 4
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", W.content, "TOPLEFT", 0, -y)
        else
            local mark = entry.check ~= nil and (entry.check and "[x] " or "[ ] ") or (entry.selected and "> " or "")
            if entry.disabled then
                row.Label:SetText(Paint(GRAY, mark .. entry.text))
            elseif entry.selected then
                row.Label:SetText(Paint(GOLD, mark .. entry.text))
            else
                row.Label:SetText(Paint(WHITE, mark .. entry.text))
            end
            row.Right:SetText(entry.right and Paint(GRAY, entry.right) or "")
            row.Sub:SetText(entry.sub and Paint(entry.subColor or GRAY, entry.sub) or "")
            row.Bg:Show()
            if entry.selected then row.Selected:Show(); row.Edge:Show() else row.Selected:Hide(); row.Edge:Hide() end
            if entry.sub then height = 24 + math.max(14, row.Sub.GetStringHeight and row.Sub:GetStringHeight() or 14) end
        end
        row:SetHeight(height)
        row:SetEnabled(not entry.header and not entry.disabled)
        row:Show()
        y = y + height + 3
    end
    for i = #entries + 1, #W.rows do W.rows[i]:Hide() end
    return y
end

local function Option(text, selected, onClick, tooltip, disabledReason)
    return {
        text = text, title = text, selected = selected, onClick = onClick, tooltip = tooltip,
        disabled = disabledReason ~= nil, sub = disabledReason,
    }
end

local function NameOf(list, key)
    local entry = C.Find(list, key)
    return entry and (entry.name or entry.key) or "не выбрано"
end

local SLOT_NAMES = {
    oneHand = "одноручное", twoHand = "двуручное", offHand = "левая рука",
    armor = "доспех", consumable = "расходник",
}

local function ItemDetails(item)
    local details = {}
    for _, part in ipairs({ SLOT_NAMES[item.slot] or item.slot, item.dice,
        item.armor and ("Броня " .. item.armor), (tonumber(item.stack) or 1) > 1 and ("x" .. item.stack) }) do
        if part and part ~= "" then details[#details + 1] = tostring(part) end
    end
    return table.concat(details, ", ")
end

local STEP_RENDER = {}

function STEP_RENDER.race(d, o)
    local entries = { { header = true, text = "Раса" } }
    for _, race in ipairs(o.races) do
        local unavailable = race.available == false and (race.unavailableReason or "недоступно в текущем каталоге") or nil
        local size = race.sizeName or race.size
        local entry = Option(race.name or race.key, d.race == race.key,
            function() C.SetField("race", race.key) end, race.text, unavailable)
        entry.right = size and ("размер: " .. size) or nil
        if not unavailable and C.IsStubRace(race) then entry.sub = C.STUB_TAG end
        entries[#entries + 1] = entry
    end
    local race = C.SelectedRace()
    local feature = C.SelectedFeature()
    if race then
        local stub = C.IsStubRace(race)
        entries[#entries + 1] = { header = true, text = stub and "Расовая особенность" or "Расовая особенность (одна)" }
        for _, f in ipairs(race.features or {}) do
            local entry = Option(f.name or f.key, d.racialFeature == f.key,
                function() C.SetField("racialFeature", f.key) end, f.text)
            if stub then entry.sub = C.STUB_TAG end
            entries[#entries + 1] = entry
        end
    end
    local desc = "Выберите расу из списка, затем одну расовую особенность."
    if race then
        desc = Paint(GOLD, race.name or race.key) .. (race.text and (": " .. race.text) or "")
        if feature then
            desc = desc .. "\n\n" .. Paint(GOLD, feature.name or feature.key) .. ": " .. tostring(feature.text or "")
        end
        if C.IsStubRace(race) then desc = desc .. "\n" .. Paint(GRAY, "(" .. C.STUB_TAG .. ")") end
    end
    if C.Scope() == "race" then
        desc = Paint(ORANGE, "Обновление расовых данных: выберите расу и особенность заново. Остальные шаги закреплены.")
            .. "\n\n" .. desc
    end
    return desc, entries
end

function STEP_RENDER.trait(d, o)
    local entries = { { header = true, text = "Общая черта (одна)" } }
    for _, trait in ipairs(o.traits) do
        local unavailable = trait.available == false and (trait.unavailableReason or "недоступна") or nil
        entries[#entries + 1] = Option(trait.name or trait.key, d.trait == trait.key,
            function() C.SetField("trait", trait.key) end, trait.text, unavailable)
    end
    local trait = C.SelectedTrait()
    if trait and trait.needsChoice and type(trait.choices) == "table" then
        entries[#entries + 1] = { header = true, text = "Дополнительный выбор" }
        for _, choice in ipairs(trait.choices) do
            local key = C.ChoiceKey(choice)
            entries[#entries + 1] = Option(C.ChoiceName(choice), d.traitChoice == key,
                function() C.SetField("traitChoice", key) end, type(choice) == "table" and choice.text or nil)
        end
    end
    local desc = trait and (Paint(GOLD, trait.name or trait.key) .. ": " .. tostring(trait.text or "")) or "Выберите одну общую черту."
    return desc, entries
end

function STEP_RENDER.mastery(d)
    local budget, extra = C.MasteryBudget()
    local used = C.MasteryUsed()
    for i, key in ipairs(C.MasteryKeys()) do
        local line = W.mastery[i]
        if line then
            local value = d.mastery[key] or 0
            line.key = key
            line.Label:SetText(Paint(LABEL, C.MasteryName(key)))
            line.Value:SetText(Paint(value > 0 and GREEN or WHITE, Signed(value)))
            line.minus:SetEnabled(value > 0)
            line.plus:SetEnabled(used < budget)
            line:Show()
        end
    end
    local left = budget - used
    local desc = "Распределите очки Мастерства между Навыком, Знанием, Упорством и Ремеслом.\n"
        .. "Распределено: " .. Paint(left > 0 and ORANGE or GREEN, used .. " из " .. budget)
        .. (left > 0 and (", осталось " .. left) or "")
    if extra > 0 then
        desc = desc .. "\nРасовая особенность даёт +" .. extra .. " распределяемое очко отдельно от фиксированных бонусов (проверит сервер)."
    end
    return desc, {}, 4 * 28 + 4
end

function STEP_RENDER.archetype(d, o)
    local entries = { { header = true, text = "Архетип" } }
    for _, archetype in ipairs(o.archetypes) do
        local tip = archetype.featureName and (archetype.featureName .. ": " .. (archetype.featureText or "")) or nil
        local entry = Option(archetype.name or archetype.key, d.archetype == archetype.key,
            function() C.SetField("archetype", archetype.key) end, tip)
        entry.sub = archetype.featureName and ("Особенность: " .. archetype.featureName) or nil
        entries[#entries + 1] = entry
    end
    local selected = C.Find(o.archetypes, d.archetype)
    local desc = "Архетип не связан с классом WoW."
    if selected then
        desc = Paint(GOLD, selected.name or selected.key) .. (selected.description and (": " .. selected.description) or ".")
            .. "\n\nОсобенность «" .. tostring(selected.featureName) .. "»: " .. tostring(selected.featureText or "")
    end
    return desc, entries
end

function STEP_RENDER.starter(d, o)
    local limit = C.StarterLimit()
    local chosen = {}
    for _, key in ipairs(d.starterItems) do chosen[key] = true end
    local entries = { { header = true, text = "Выбрано: " .. #d.starterItems .. " из " .. limit } }
    for _, item in ipairs(o.starter and o.starter.items or {}) do
        local full = not chosen[item.key] and #d.starterItems >= limit
        local entry = Option(item.name or item.key, chosen[item.key] == true, function() C.ToggleStarter(item.key) end)
        entry.check = chosen[item.key] == true
        entry.disabled = full
        local details = ItemDetails(item)
        entry.sub = (details ~= "" and details or nil)
        if full then entry.sub = (entry.sub and (entry.sub .. " - ") or "") .. "лимит набора" end
        entries[#entries + 1] = entry
    end
    return "Стартовое снаряжение: до " .. limit .. " предметов. Набор выдаётся один раз при подтверждении.", entries
end

local function SummaryItems(d, o)
    local trait = C.SelectedTrait()
    local choiceName = d.traitChoice
    for _, choice in ipairs(trait and type(trait.choices) == "table" and trait.choices or {}) do
        if C.ChoiceKey(choice) == d.traitChoice then choiceName = C.ChoiceName(choice) end
    end
    local race, feature = C.SelectedRace(), C.SelectedFeature()
    local featureText = feature and (feature.name or feature.key) or Paint(ORANGE, "не выбрана")
    if feature and C.IsStubRace(race) then featureText = featureText .. " " .. Paint(GRAY, "(" .. C.STUB_TAG .. ")") end
    local items = {
        { header = "Происхождение" },
        { label = "Раса:", value = race and (race.name or race.key) or Paint(ORANGE, "не выбрана") },
        { label = "Особенность:", value = featureText },
        { gap = 8 },
        { header = "Развитие" },
    }
    if C.state and C.state.rpLevel then items[#items + 1] = { label = "RP-уровень:", value = C.state.rpLevel } end
    items[#items + 1] = { label = "Черта:", value = trait and ((trait.name or trait.key)
        .. (choiceName and (" (" .. tostring(choiceName) .. ")") or "")) or Paint(ORANGE, "не выбрана") }
    items[#items + 1] = { label = "Архетип:", value = d.archetype and NameOf(o.archetypes, d.archetype) or Paint(ORANGE, "не выбран") }
    local mastery = {}
    for _, key in ipairs(C.MasteryKeys()) do
        if (d.mastery[key] or 0) > 0 then mastery[#mastery + 1] = C.MasteryName(key) .. " " .. Paint(GREEN, "+" .. d.mastery[key]) end
    end
    items[#items + 1] = { label = "Мастерство:", value = #mastery > 0 and table.concat(mastery, ", ") or Paint(ORANGE, "не распределено") }
    items[#items + 1] = { gap = 8 }
    items[#items + 1] = { header = "Снаряжение" }
    if #d.starterItems == 0 then items[#items + 1] = { para = Paint(GRAY, "Ничего не выбрано.") } end
    for _, key in ipairs(d.starterItems) do
        items[#items + 1] = { para = "* " .. Paint(WHITE, NameOf(o.starter and o.starter.items, key)) }
    end
    if #C.warnings > 0 then
        items[#items + 1] = { gap = 8 }
        items[#items + 1] = { header = "Внимание", color = ORANGE }
        for _, warning in ipairs(C.warnings) do
            local text = type(warning) == "table" and (warning.message_ru or warning.code) or warning
            items[#items + 1] = { para = Paint(ORANGE, tostring(text)) }
        end
    end
    items[#items + 1] = { gap = 8 }
    items[#items + 1] = { para = Paint(GRAY, "Выбор подтверждается один раз; повторная настройка — через ведущего.") }
    return items
end

function STEP_RENDER.confirm()
    return "Проверьте выбор. Итоговый лист рассчитывает сервер (справа).", {}
end

local SHEET_BLOCKS = {
    { "Ресурсы", { { "rpLevel", "RP-уровень" }, { "maxHealth", "ОЗ" }, { "maxEnergy", "ОЭ" },
        { "woundLimit", "Лимит Ран" }, { "fateDie", "Кость Судьбы" } } },
    { "Боевые бонусы", { { "accuracy", "Меткость", true }, { "healing", "Исцеление", true },
        { "evasion", "Уклонение", true }, { "resistance", "Сопротивление", true } } },
    { "Защита и движение", { { "armor", "Броня" }, { "block", "Блок" }, { "speed", "Скорость" } } },
}

-- Server block = {die, flat, base}: "1d4 + 1" with a shield, otherwise the flat value.
local function BlockText(block)
    if type(block) ~= "table" then return tostring(block) end
    local flat = tonumber(block.flat) or tonumber(block.base) or 0
    if block.die then return tostring(block.die) .. (flat ~= 0 and (" " .. Signed(flat):gsub("^%+", "+ ")) or "") end
    return tostring(flat)
end

-- Server passives are "Name: text"; the name is highlighted before " - ".
local function PassiveText(text)
    text = tostring(text)
    local name, rest = text:match("^(.-):%s+(.+)$")
    if not name or name == "" or #name > 80 then name, rest = text:match("^(.-)%s+%-%s+(.+)$") end
    if name and name ~= "" then return Paint(GOLD, name) .. " - " .. rest end
    return text
end

local function SheetItems()
    local items = {}
    local missing = C.options and C.draft and C.MissingList() or {}
    if #missing > 0 then
        items[#items + 1] = { header = "Ещё не указано:", color = ORANGE }
        for _, item in ipairs(missing) do
            local step = item.step and C.STEPS[item.step]
            local text = "* " .. tostring(item.message_ru)
            if item.optional then text = Paint(GRAY, text .. " (необязательно)") end
            items[#items + 1] = { para = text .. (step and Paint(GRAY, " (шаг " .. item.step .. ")") or "") }
        end
        items[#items + 1] = { gap = 8 }
    end
    local errors = C.VisibleErrors()
    if #errors > 0 then
        items[#items + 1] = { header = "Ошибки", color = RED }
        for _, err in ipairs(errors) do
            items[#items + 1] = { para = Paint(RED, "Шаг " .. C.ErrorStep(err) .. ": " .. C.ErrorText(err)) }
        end
        items[#items + 1] = { gap = 8 }
    end
    if not C.preview then
        items[#items + 1] = { para = Paint(GRAY, C.draft and C.draft.race and "Расчёт…"
            or "Выберите расу, чтобы получить расчёт сервера.") }
        return items
    end
    if not C.PreviewFresh() then items[#items + 1] = { para = Paint(GRAY, "Пересчёт…") } end
    local sheet = C.preview.sheet
    if not (C.preview.ok and type(sheet) == "table") then return items end
    for _, block in ipairs(SHEET_BLOCKS) do
        local rows = {}
        for _, def in ipairs(block[2]) do
            local value = sheet[def[1]]
            if def[1] == "block" and value ~= nil then value = BlockText(value) end
            if value ~= nil then
                rows[#rows + 1] = { label = def[2] .. ":", value = def[3] and Signed(value) or tostring(value),
                    color = def[3] and SignedColor(value) or WHITE }
            end
        end
        if #rows > 0 then
            items[#items + 1] = { header = block[1] }
            for _, row in ipairs(rows) do items[#items + 1] = row end
            items[#items + 1] = { gap = 8 }
        end
    end
    if type(sheet.mastery) == "table" then
        items[#items + 1] = { header = "Мастерство" }
        for _, key in ipairs(C.MasteryKeys()) do
            local value = sheet.mastery[key]
            if value ~= nil then
                items[#items + 1] = { label = C.MasteryName(key) .. ":", value = Signed(value), color = SignedColor(value) }
            end
        end
        items[#items + 1] = { gap = 8 }
    elseif sheet.mastery ~= nil then
        items[#items + 1] = { header = "Мастерство" }
        items[#items + 1] = { para = tostring(sheet.mastery) }
        items[#items + 1] = { gap = 8 }
    end
    if sheet.abilitySlots ~= nil then
        items[#items + 1] = { header = "Способности" }
        items[#items + 1] = { label = "Ячейки:", value = tostring(sheet.abilitySlots) }
        items[#items + 1] = { gap = 8 }
    end
    local passives = type(sheet.passive) == "table" and sheet.passive or {}
    if #passives > 0 then
        items[#items + 1] = { header = "Особенности" }
        for _, passive in ipairs(passives) do
            items[#items + 1] = { para = PassiveText(passive) }
            items[#items + 1] = { gap = 4 }
        end
    end
    return items
end

local function TabTitle(i, step)
    local title = i .. ". " .. C.STEPS[i].title
    if C.StepLocked(i) then return Paint(GRAY, title) end
    if #C.VisibleErrors(i) > 0 then return Paint(RED, title) end
    if i < #C.STEPS and C.options and C.draft and C.StepMissing(i) then return Paint(ORANGE, title .. " *") end
    if i == step then return Paint(GOLD, title) end
    return title
end

function W.Render()
    local f = W.frame
    if not f or not f:IsShown() then return end
    local o, d, step = C.options, C.draft, C.step
    for i, tab in ipairs(f.tabs) do
        tab:SetText(TabTitle(i, step))
        tab:SetEnabled(not C.StepLocked(i))
    end
    f.stepTitle:SetText("Шаг " .. step .. " из " .. #C.STEPS .. ": " .. C.STEPS[step].title)
    for _, line in ipairs(W.mastery) do line:Hide() end
    local desc, entries, controls = "", {}, 0
    if o and d then
        desc, entries, controls = STEP_RENDER[C.STEPS[step].key](d, o)
        controls = controls or 0
    else
        desc = C.loading and "Загрузка вариантов с сервера…" or "Варианты не получены. Закройте и откройте мастер ещё раз."
    end
    local stepErrors = {}
    for _, err in ipairs(C.VisibleErrors(step)) do stepErrors[#stepErrors + 1] = Paint(RED, C.ErrorText(err)) end
    local missing = o and d and C.LocalMissing(step)
    if missing and step ~= #C.STEPS then table.insert(stepErrors, 1, Paint(ORANGE, missing)) end
    f.stepError:SetText(table.concat(stepErrors, "\n"))
    W.desc:SetText(desc)
    local top = math.max(28, (W.desc.GetStringHeight and W.desc:GetStringHeight() or 28)) + 10
    W.controlsTop = top
    for i, line in ipairs(W.mastery) do
        line:ClearAllPoints(); line:SetPoint("TOPLEFT", W.content, "TOPLEFT", 0, -(top + (i - 1) * 28))
    end
    local height = RenderRows(entries, top + controls)
    if o and d and C.STEPS[step].key == "confirm" then
        height, W.summaryPlain = RenderBlocks(W.summary, SummaryItems(d, o), top)
    else
        RenderBlocks(W.summary, {}, top)
        W.summaryPlain = ""
    end
    W.content:SetHeight(height + 8)
    local sheetHeight
    sheetHeight, W.sheetPlain = RenderBlocks(W.sheet, SheetItems(), 0)
    f.sheetContent:SetHeight(sheetHeight + 8)
    local back, forward = C.NextStep(step, -1), C.NextStep(step, 1)
    f.back:SetEnabled(back ~= step and not C.pending)
    local last = step == #C.STEPS
    if last then f.next:Hide(); f.confirm:Show() else f.next:Show(); f.confirm:Hide() end
    f.next:SetEnabled(not last and o ~= nil and forward ~= step and not C.LocalMissing(step))
    f.confirm:SetEnabled(C.CanConfirm())
    f.confirm:SetText(C.pending and "Сохранение…" or "Подтвердить")
    local status = C.status
    if not status and C.GetState() == "complete" then
        status = "Персонаж уже подтверждён. Перенастройку выполняет ведущий."
    elseif not status and last and not C.CanConfirm() then
        status = C.LocalMissing(#C.STEPS) or (not C.PreviewFresh() and "Ожидание расчёта сервера…") or "Исправьте ошибки, отмеченные красным."
    end
    f.status:SetText(status or "")
end

function W.SheetText() return W.sheetPlain or "" end
function W.SummaryText() return W.summaryPlain or "" end

local function Build()
    local f = CreateFrame("Frame", "NobleNextCharacterCreation", UIParent, "BackdropTemplate")
    W.frame = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0.08, 0.06, 0.1, 0.96)
    f:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "NobleNextCharacterCreation") end

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -14)
    title:SetText("Создание RP-персонажа")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    f.tabs = {}
    for i in ipairs(C.STEPS) do
        local tab = ns.CreateNGButton(f, "", 112, 22)
        tab:SetPoint("TOPLEFT", f, "TOPLEFT", 12 + (i - 1) * 116, -42)
        tab:SetScript("OnClick", function() C.GoTo(i) end)
        f.tabs[i] = tab
    end
    f.stepTitle = Text(f, "GameFontNormal", LIST_WIDTH)
    f.stepTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -74)
    f.stepError = Text(f, "GameFontHighlightSmall", LIST_WIDTH)
    f.stepError:SetPoint("TOPLEFT", f.stepTitle, "BOTTOMLEFT", 0, -4)

    local scroll = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -118)
    scroll:SetSize(LIST_WIDTH, LIST_HEIGHT)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(LIST_WIDTH - 20, LIST_HEIGHT)
    scroll:SetScrollChild(content)
    W.scroll, W.content = scroll, content
    W.desc = Text(content, "GameFontHighlightSmall", LIST_WIDTH - 28)
    W.desc:SetPoint("TOPLEFT", content, "TOPLEFT", 4, 0)
    W.summary = NewPool(content, LIST_WIDTH - 32, 110, "LEFT")

    W.mastery = {}
    for i = 1, 4 do
        local line = CreateFrame("Frame", nil, content)
        line:SetSize(LIST_WIDTH - 30, 26)
        line.Label = Text(line, "GameFontNormal", 140)
        line.Label:SetPoint("LEFT", line, "LEFT", 8, 0)
        line.Value = Text(line, "GameFontNormal", 40)
        line.Value:SetPoint("LEFT", line, "LEFT", 150, 0)
        line.Value:SetJustifyH("RIGHT")
        line.minus = ns.CreateNGButton(line, "-", 26, 22)
        line.minus:SetPoint("LEFT", line, "LEFT", 210, 0)
        line.minus:SetScript("OnClick", function() C.AdjustMastery(line.key, -1) end)
        line.plus = ns.CreateNGButton(line, "+", 26, 22)
        line.plus:SetPoint("LEFT", line.minus, "RIGHT", 6, 0)
        line.plus:SetScript("OnClick", function() C.AdjustMastery(line.key, 1) end)
        W.mastery[i] = line
    end

    local sideTitle = Text(f, "GameFontNormal", SIDE_WIDTH)
    sideTitle:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE_X, -74)
    sideTitle:SetText("Лист персонажа (расчёт сервера)")
    local side = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    side:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE_X, -96)
    side:SetSize(SIDE_WIDTH, SIDE_HEIGHT)
    f.sheetContent = CreateFrame("Frame", nil, side)
    f.sheetContent:SetSize(SIDE_WIDTH, SIDE_HEIGHT)
    side:SetScrollChild(f.sheetContent)
    W.sheet = NewPool(f.sheetContent, SIDE_WIDTH - 8, 130, "RIGHT")

    f.back = ns.CreateNGButton(f, "Назад", 110, 26)
    f.back:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)
    f.back:SetScript("OnClick", function() C.GoTo(C.NextStep(C.step, -1)) end)
    f.next = ns.CreateNGButton(f, "Далее", 110, 26)
    f.next:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
    f.next:SetScript("OnClick", function() C.GoTo(C.NextStep(C.step, 1)) end)
    f.confirm = ns.CreateNGButton(f, "Подтвердить", 130, 26)
    f.confirm:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
    f.confirm:SetScript("OnClick", function() C.Confirm() end)
    f.status = Text(f, "GameFontHighlightSmall", WIDTH - 290)
    f.status:SetPoint("BOTTOM", f, "BOTTOM", 0, 20)
    f.status:SetJustifyH("CENTER")
    f:SetScript("OnShow", W.Render)
    return f
end

function C.IsOpen()
    return W.frame ~= nil and W.frame:IsShown()
end

function C.Open()
    local f = W.frame or Build()
    if C.options then C.EnsureDraft() end
    if C.Scope() == "race" or C.StepLocked(C.step) then
        C.step = 1
        C.visited[1] = true
    end
    f:Show()
    if not C.pending then C.RequestOptions() end
    if C.draft and C.draft.race and not C.PreviewFresh() then C.SchedulePreview() end
    W.Render()
    return f
end

function C.Close()
    if W.frame then W.frame:Hide() end
end

C.OnChange = W.Render
C.OnConfirmed = C.Close
C.OnRaceReset = function() C.Open() end

local HELP = "/rps create — мастер создания RP-персонажа; /rps race reset — сбросить устаревшие расовые данные."

local function Slash(msg)
    local words = {}
    for word in tostring(msg or ""):gmatch("%S+") do words[#words + 1] = word:lower() end
    local cmd, arg = words[1] or "", words[2] or ""
    if cmd == "create" or cmd == "создать" then
        C.Open()
    elseif (cmd == "race" or cmd == "раса") and (arg == "reset" or arg == "сброс") then
        C.ConfirmRaceReset()
    elseif ns.Print then
        ns.Print(HELP)
    end
end
C.Slash = Slash
if ns.RegisterSlashCommand then
    ns.RegisterSlashCommand("NOBLENEXTRPS", Slash, { "rps" })
elseif SlashCmdList then
    SLASH_NOBLENEXTRPS1 = "/rps"
    SlashCmdList.NOBLENEXTRPS = Slash
end
