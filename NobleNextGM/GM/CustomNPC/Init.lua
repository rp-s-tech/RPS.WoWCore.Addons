-- Loaded through the NobleNextGM private extension namespace.
-- GM/CustomNPC/Init.lua — picker-first интерфейс для .customnpc/.cnpc

local _, ns = ...
local NNL = LibStub("NobleNextLib-1.0")

local GENDERS = {
    { value = 0, label = "Мужской" },
    { value = 1, label = "Женский" },
}

local ARMOR_SLOTS = {
    { value = "all", label = "Все" },
    { value = "head", label = "Голова" },
    { value = "shoulders", label = "Плечи" },
    { value = "body", label = "Рубашка" },
    { value = "chest", label = "Грудь" },
    { value = "waist", label = "Пояс" },
    { value = "legs", label = "Ноги" },
    { value = "feet", label = "Ступни" },
    { value = "wrists", label = "Запястья" },
    { value = "hands", label = "Кисти" },
    { value = "tabard", label = "Накидка" },
    { value = "back", label = "Плащ" },
}

local UNEQUIP_SLOTS = {}
for _, entry in ipairs(ARMOR_SLOTS) do
    if entry.value ~= "all" then
        UNEQUIP_SLOTS[#UNEQUIP_SLOTS + 1] = entry
    end
end

local RACE_RU = {
    [1] = "Человек",
    [2] = "Орк",
    [3] = "Дворф",
    [4] = "Ночной эльф",
    [5] = "Нежить",
    [6] = "Таурен",
    [7] = "Гном",
    [8] = "Тролль",
    [9] = "Гоблин",
    [10] = "Эльф крови",
    [11] = "Дреней",
    [22] = "Ворген",
    [24] = "Пандарен",
    [25] = "Пандарен (А)",
    [26] = "Пандарен (О)",
    [27] = "Ночнорождённый",
    [28] = "Таурен Крутогорья",
    [29] = "Эльф Бездны",
    [30] = "Озарённый дреней",
    [31] = "Зандалар",
    [32] = "Култирасец",
    [34] = "Дворф Чёрного Железа",
    [35] = "Вульпера",
    [36] = "Маг'хар",
    [37] = "Механогном",
    [52] = "Драктир",
    [70] = "Драктир",
}

local FALLBACK_RACES = {
    { raceId = 1, name = "Human", available = true },
    { raceId = 2, name = "Orc", available = true },
    { raceId = 3, name = "Dwarf", available = true },
    { raceId = 4, name = "NightElf", available = true },
    { raceId = 5, name = "Scourge", available = true },
    { raceId = 6, name = "Tauren", available = true },
    { raceId = 7, name = "Gnome", available = true },
    { raceId = 8, name = "Troll", available = true },
    { raceId = 9, name = "Goblin", available = true },
    { raceId = 10, name = "BloodElf", available = true },
    { raceId = 11, name = "Draenei", available = true },
    { raceId = 22, name = "Worgen", available = true },
    { raceId = 24, name = "Pandaren", available = true },
}

local function Trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function SendCNPCommand(command)
    if ns.RunGmCommand then
        ns.RunGmCommand(command)
    else
        ns.PrintError("RunGmCommand недоступен.")
    end
end

local function ExtractItemToken(text)
    text = Trim(text)
    if text == "" then
        return nil
    end
    if text:lower() == "self" then
        return "self"
    end
    local itemId = text:match("|Hitem:(%d+)")
    if itemId then
        return itemId
    end
    if tonumber(text) then
        return tostring(math.floor(tonumber(text)))
    end
    return text
end

local function InitSimpleDropdown(dropdown, width, getEntries, onPick)
    UIDropDownMenu_SetWidth(dropdown, width)
    UIDropDownMenu_Initialize(dropdown, function()
        for _, entry in ipairs(getEntries() or {}) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.label
            info.value = entry.value
            info.disabled = entry.disabled
            info.func = function()
                onPick(entry.value, entry.label)
                UIDropDownMenu_SetSelectedValue(dropdown, entry.value)
                UIDropDownMenu_SetText(dropdown, entry.label)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
end

local function FormatRaceLabel(raceId, name)
    return RACE_RU[tonumber(raceId) or -1] or name or ("Раса " .. tostring(raceId))
end

local function InitCustomNpcModule(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:Hide()

    local State = {
        key = nil,
        name = nil,
        entry = nil,
        subName = nil,
        variation = 1,
        modelCount = 1,
        displayId = nil,
        scale = nil,
        isOutfit = false,
        detailReady = false,
        hydrating = false,
        createMode = "clone", -- blank | clone | target
        pendingSelectName = nil,
        raceId = 1,
        gender = 0,
        armorSlot = "head",
        itemSource = "self", -- self | item
        races = {},
        rows = {},
        filter = "",
        showAll = false,
        advancedOpen = false,
        faceOptions = {},
        faceChoices = {},
        faceOptionIndex = nil,
        faceOptionName = nil,
        faceCurrentChoiceIndex = nil,
        faceLoading = false,
        models = {},
    }

    local LookApplyButtons = {}

    local function SetStatus(ok, message)
        if not f.StatusText then return end
        local color = ok and "00cc66" or "ff6666"
        if ok == nil then
            color = "cccccc"
        end
        f.StatusText:SetText("|cff" .. color .. (message or "-") .. "|r")
    end

    local function SetLookApplyEnabled(enabled, reason)
        for _, btn in ipairs(LookApplyButtons) do
            if btn and btn.SetEnabledEx then
                btn:SetEnabledEx(enabled, reason)
            elseif btn and btn.SetEnabled then
                btn:SetEnabled(enabled and true or false)
            end
        end
    end

    local function UpdateContext()
        local key = State.key or "-"
        local name = State.name or "без имени"
        local entry = State.entry and tostring(State.entry) or "-"
        local models = tonumber(State.modelCount) or 1
        local outfitTag = State.isOutfit and "outfit" or "display"
        f.ContextText:SetText(string.format(
            "Активный: %s | %s | entry %s | вариант %d/%d (%s)%s",
            key, name, entry, State.variation or 1, models, outfitTag,
            State.detailReady and "" or " | загрузка…"))
        if f.KeyReadonly then
            f.KeyReadonly:SetText(State.key or "")
        end
        if f.VariationBox and not State.hydrating then
            f.VariationBox:SetText(tostring(State.variation or 1))
        end
        local hasKey = State.key and State.key ~= ""
        if f.EditGateHint then
            f.EditGateHint:SetShown(not hasKey)
        end
    end

    local function AioCall(method, ...)
        if ns.AIOHandle("CustomNpcHandlers", method, ...) then
            return true
        end
        SetStatus(false, "AIO недоступен.")
        return false
    end

    local function ClearFaceBrowser(message)
        State.faceOptions = {}
        State.faceChoices = {}
        State.faceOptionIndex = nil
        State.faceOptionName = nil
        State.faceCurrentChoiceIndex = nil
        State.faceLoading = false
        if f.FaceOptionList then
            f.FaceOptionList:SetRows({})
        end
        if f.FaceChoiceList then
            f.FaceChoiceList:SetRows({})
        end
        if f.FaceHeader then
            f.FaceHeader:SetText(message or "Лицо недоступно.")
        end
    end

    local function UpdateFaceGate()
        local hasKey = State.key and State.key ~= ""
        local ready = hasKey and State.detailReady
        local outfit = ready and State.isOutfit
        local gateText
        if not hasKey then
            gateText = "Выберите NPC в «Каталог»."
        elseif not State.detailReady then
            gateText = "Дождитесь загрузки вида с сервера…"
        elseif not State.isOutfit then
            gateText = "Лицо недоступно: нет outfit (display-only модель)."
        end
        if f.FaceGateHint then
            if gateText then
                f.FaceGateHint:SetText(gateText)
                f.FaceGateHint:Show()
            else
                f.FaceGateHint:Hide()
            end
        end
        if f.FaceHeader then
            f.FaceHeader:SetShown(not gateText)
        end
        if f.FaceListsHost then
            f.FaceListsHost:SetShown(outfit and true or false)
        end
        if not outfit then
            State.faceOptions = {}
            State.faceChoices = {}
            State.faceOptionIndex = nil
            State.faceOptionName = nil
            State.faceCurrentChoiceIndex = nil
            State.faceLoading = false
            if f.FaceOptionList then
                f.FaceOptionList:SetRows({})
            end
            if f.FaceChoiceList then
                f.FaceChoiceList:SetRows({})
            end
        end
    end

    local function RequestNpcDetail(key, variation, keepFaceOption)
        key = key or State.key
        if not key or key == "" then
            return false
        end
        variation = tonumber(variation) or State.variation or 1
        if variation < 1 then
            variation = 1
        end
        local keptOptionIndex = keepFaceOption and tonumber(State.faceOptionIndex) or nil
        local keptOptionName = keepFaceOption and State.faceOptionName or nil
        State.detailReady = false
        SetLookApplyEnabled(false, "Дождитесь загрузки вида с сервера.")
        ClearFaceBrowser("Загрузка вида…")
        UpdateContext()
        UpdateFaceGate()
        -- UpdateFaceGate clears selection while detailReady=false; restore after soft SetFace refresh.
        if keptOptionIndex then
            State.faceOptionIndex = keptOptionIndex
            State.faceOptionName = keptOptionName
        end
        return AioCall("GetNpcDetail", key, variation)
    end

    --- opts.keepFaceOption: preserve selected face option tab across soft refresh (after SetFace).
    local function ScheduleNpcDetailRefresh(opts)
        if not State.key or State.key == "" then
            return
        end
        opts = opts or {}
        local keepFaceOption = opts.keepFaceOption and true or false
        local key = State.key
        local variation = State.variation or 1
        local keptOptionIndex = keepFaceOption and tonumber(State.faceOptionIndex) or nil
        local keptOptionName = keepFaceOption and State.faceOptionName or nil
        C_Timer.After(0.4, function()
            if State.key ~= key then
                return
            end
            if keptOptionIndex then
                State.faceOptionIndex = keptOptionIndex
                State.faceOptionName = keptOptionName
            end
            RequestNpcDetail(key, variation, keepFaceOption)
        end)
    end

    local function UpdateModelsVisibility()
        local count = math.max(1, tonumber(State.modelCount) or 1)
        if f.ModelsSection then
            f.ModelsSection:SetShown(count > 1)
        end
        if f.ModelsHint then
            if count > 1 then
                f.ModelsHint:SetText(string.format("Виды модели: %d (лицо правится для активного вида %d).", count, State.variation or 1))
            else
                f.ModelsHint:SetText("")
            end
        end
    end

    local function RequestFaceOptions()
        local key = State.key
        if not key or key == "" or not State.isOutfit or not State.detailReady then
            UpdateFaceGate()
            return false
        end
        State.faceLoading = true
        if f.FaceHeader then
            f.FaceHeader:SetText(string.format("Вид %d — загрузка опций…", State.variation or 1))
        end
        return AioCall("GetFaceOptions", key, State.variation or 1)
    end

    local function RequestFaceChoices(optionIndex)
        local key = State.key
        optionIndex = tonumber(optionIndex)
        if not key or key == "" or not optionIndex or not State.isOutfit then
            return false
        end
        State.faceLoading = true
        return AioCall("GetFaceChoices", key, optionIndex, State.variation or 1)
    end

    local function RequestModelList()
        local key = State.key
        if not key or key == "" then
            State.models = {}
            if f.ModelList then
                f.ModelList:SetRows({})
            end
            UpdateModelsVisibility()
            return false
        end
        if (tonumber(State.modelCount) or 1) <= 1 then
            State.models = {}
            if f.ModelList then
                f.ModelList:SetRows({})
            end
            UpdateModelsVisibility()
            return false
        end
        return AioCall("GetModelList", key)
    end

    local function RequestFaceBrowser()
        UpdateFaceGate()
        if State.key and State.detailReady and State.isOutfit then
            RequestFaceOptions()
        end
        RequestModelList()
    end

    local function ApplyNpcDetail(detail)
        if type(detail) ~= "table" or not detail.key then
            return
        end
        if State.key and tostring(detail.key) ~= tostring(State.key) then
            return
        end

        State.hydrating = true
        State.key = tostring(detail.key)
        State.name = detail.name or State.name
        State.entry = detail.entry or State.entry
        State.subName = detail.subname or ""
        State.variation = tonumber(detail.variation) or State.variation or 1
        State.modelCount = math.max(1, tonumber(detail.models) or 1)
        State.displayId = detail.displayId
        State.scale = detail.scale
        State.isOutfit = detail.isOutfit and true or false
        State.detailReady = true

        if State.isOutfit then
            if detail.race ~= nil then
                State.raceId = tonumber(detail.race) or State.raceId
            end
            if detail.gender ~= nil then
                State.gender = tonumber(detail.gender) or State.gender
            end
        end

        if f.NameBox then
            f.NameBox:SetText(State.name or "")
        end
        if f.SubNameBox then
            f.SubNameBox:SetText(State.subName or "")
        end
        if f.VariationBox then
            f.VariationBox:SetText(tostring(State.variation))
        end
        if f.DisplayBox then
            f.DisplayBox:SetText(State.displayId and tostring(State.displayId) or "")
        end
        if f.ScaleBox then
            f.ScaleBox:SetText(State.scale ~= nil and tostring(State.scale) or "1")
        end

        if f.RaceDropdown and State.isOutfit then
            local label = FormatRaceLabel(State.raceId, nil)
            for _, race in ipairs(State.races) do
                if tonumber(race.raceId) == tonumber(State.raceId) then
                    label = FormatRaceLabel(race.raceId, race.name)
                    break
                end
            end
            UIDropDownMenu_SetSelectedValue(f.RaceDropdown, State.raceId)
            UIDropDownMenu_SetText(f.RaceDropdown, label)
        end
        if f.GenderDropdown and State.isOutfit then
            local gLabel = "Мужской"
            for _, g in ipairs(GENDERS) do
                if g.value == State.gender then
                    gLabel = g.label
                    break
                end
            end
            UIDropDownMenu_SetSelectedValue(f.GenderDropdown, State.gender)
            UIDropDownMenu_SetText(f.GenderDropdown, gLabel)
        end

        State.hydrating = false
        SetLookApplyEnabled(true)
        UpdateContext()
        UpdateModelsVisibility()
        if State.isOutfit then
            SetStatus(true, "Вид загружен с сервера (outfit).")
        else
            SetStatus(true, "Вид: display-only (не ChrCustomization outfit). Раса/пол с сервера не заданы.")
        end
        RequestFaceBrowser()
    end

    local function SelectRow(row)
        if not row then return end
        local sameKey = State.key and tostring(State.key) == tostring(row.key)
        State.key = row.key
        State.name = row.name
        State.entry = row.entry
        if not sameKey then
            State.variation = 1
            State.detailReady = false
            State.isOutfit = false
            State.modelCount = tonumber(row.models) or 1
            ClearFaceBrowser("Загрузка…")
            State.models = {}
        end
        UpdateContext()
        UpdateModelsVisibility()
        if f.NpcList then
            f.NpcList:Refresh()
        end
        SetStatus(true, "Загрузка вида " .. tostring(row.key) .. "…")
        RequestNpcDetail(State.key, State.variation)
    end

    local function RequireKey()
        if not State.key or State.key == "" then
            SetStatus(false, "Сначала выберите NPC из списка или создайте нового.")
            return nil
        end
        return State.key
    end

    local function OptionalVariationSuffix()
        local variation = tonumber(State.variation)
        if variation and variation > 0 then
            return " " .. tostring(math.floor(variation))
        end
        return ""
    end

    local function RefreshList()
        AioCall("GetNpcList", State.showAll and true or false, 0, 50)
    end

    local function RefreshCatalog()
        AioCall("GetCatalog", true)
    end

    _G.NobleNextCustomNpc = _G.NobleNextCustomNpc or {}
    _G.NobleNextCustomNpc.OnStatus = function(ok, message)
        SetStatus(ok, message)
        if not ok or not State.key or type(message) ~= "string" then
            return
        end
        -- After Reload Status, pull detail for current key.
        if message:find("reload", 1, true) then
            RefreshList()
            RequestNpcDetail(State.key, State.variation)
            return
        end
        if message:find("Face обновлён", 1, true) then
            ScheduleNpcDetailRefresh({ keepFaceOption = true })
        end
    end
    _G.NobleNextCustomNpc.OnNpcList = function(rows)
        State.rows = rows or {}
        local filter = Trim(State.filter):lower()
        local filtered = {}
        for _, row in ipairs(State.rows) do
            local hay = string.format("%s %s %s", row.key or "", row.name or "", tostring(row.entry or "")):lower()
            if filter == "" or hay:find(filter, 1, true) then
                filtered[#filtered + 1] = row
            end
        end
        if f.NpcList then
            f.NpcList:SetRows(filtered)
        end
        if f.CountText then
            f.CountText:SetText(string.format("Показано: %d", #filtered))
        end
        -- After create: select row matching pending display name (last match).
        if State.pendingSelectName and #filtered > 0 then
            local want = Trim(State.pendingSelectName):lower()
            local best
            for _, row in ipairs(filtered) do
                if Trim(row.name or ""):lower() == want then
                    best = row
                end
            end
            State.pendingSelectName = nil
            if best then
                SelectRow(best)
            end
        elseif (not State.key or State.key == "") and #filtered > 0 then
            SelectRow(filtered[#filtered])
        elseif State.key then
            for _, row in ipairs(filtered) do
                if row.key == State.key then
                    State.name = row.name
                    State.entry = row.entry
                    if row.models then
                        State.modelCount = tonumber(row.models) or State.modelCount
                    end
                    UpdateContext()
                    RequestNpcDetail(State.key, State.variation)
                    break
                end
            end
        end
    end
    _G.NobleNextCustomNpc.OnNpcDetail = function(detail)
        ApplyNpcDetail(detail)
    end
    _G.NobleNextCustomNpc.OnFaceOptions = function(payload)
        if type(payload) ~= "table" then
            return
        end
        if State.key and payload.key and tostring(payload.key) ~= tostring(State.key) then
            return
        end
        State.faceLoading = false
        State.faceOptions = payload.options or {}
        if f.FaceOptionList then
            f.FaceOptionList:SetRows(State.faceOptions)
        end
        UpdateFaceGate()
        if not payload.isOutfit then
            ClearFaceBrowser("Нет outfit.")
            return
        end
        if #State.faceOptions == 0 then
            ClearFaceBrowser("Нет опций кастомизации (store/hotfix?).")
            return
        end
        local keep = State.faceOptionIndex
        local pick = nil
        if keep then
            for _, opt in ipairs(State.faceOptions) do
                if tonumber(opt.index) == tonumber(keep) then
                    pick = opt
                    break
                end
            end
        end
        if not pick then
            pick = State.faceOptions[1]
        end
        if pick then
            State.faceOptionIndex = tonumber(pick.index)
            State.faceOptionName = pick.name
            if f.FaceHeader then
                f.FaceHeader:SetText(string.format(
                    "Вид %d — %s (%d/%d)",
                    State.variation or 1,
                    pick.name or ("Опция " .. tostring(pick.index)),
                    tonumber(pick.currentChoiceIndex) or 0,
                    tonumber(pick.choiceCount) or 0))
            end
            if f.FaceOptionList then
                f.FaceOptionList:Refresh()
            end
            RequestFaceChoices(State.faceOptionIndex)
        end
    end
    _G.NobleNextCustomNpc.OnFaceChoices = function(payload)
        if type(payload) ~= "table" then
            return
        end
        if State.key and payload.key and tostring(payload.key) ~= tostring(State.key) then
            return
        end
        if State.faceOptionIndex and payload.optionIndex
            and tonumber(payload.optionIndex) ~= tonumber(State.faceOptionIndex) then
            return
        end
        State.faceLoading = false
        State.faceChoices = payload.choices or {}
        State.faceCurrentChoiceIndex = tonumber(payload.currentChoiceIndex) or 0
        State.faceOptionName = payload.name or State.faceOptionName
        if f.FaceChoiceList then
            f.FaceChoiceList:SetRows(State.faceChoices)
        end
        if f.FaceHeader then
            f.FaceHeader:SetText(string.format(
                "Вид %d — %s -> выбор %d/%d",
                State.variation or 1,
                State.faceOptionName or ("Опция " .. tostring(State.faceOptionIndex or "-")),
                State.faceCurrentChoiceIndex or 0,
                #State.faceChoices))
        end
        if #State.faceChoices == 0 and f.FaceHeader then
            f.FaceHeader:SetText(string.format(
                "Вид %d — %s: нет доступных вариантов",
                State.variation or 1,
                State.faceOptionName or "опция"))
        end
    end
    _G.NobleNextCustomNpc.OnModelList = function(payload)
        if type(payload) ~= "table" then
            return
        end
        if State.key and payload.key and tostring(payload.key) ~= tostring(State.key) then
            return
        end
        State.models = payload.models or {}
        if f.ModelList then
            f.ModelList:SetRows(State.models)
        end
        UpdateModelsVisibility()
    end
    _G.NobleNextCustomNpc.OnCatalog = function(catalog)
        State.races = (catalog and catalog.races) or {}
        if #State.races == 0 then
            State.races = FALLBACK_RACES
        end
        if f.RaceDropdown then
            local label = FormatRaceLabel(State.raceId, nil)
            for _, race in ipairs(State.races) do
                if tonumber(race.raceId) == tonumber(State.raceId) then
                    label = FormatRaceLabel(race.raceId, race.name)
                    break
                end
            end
            UIDropDownMenu_SetSelectedValue(f.RaceDropdown, State.raceId)
            UIDropDownMenu_SetText(f.RaceDropdown, label)
        end
        SetStatus(true, "Каталог рас загружен (" .. tostring(#State.races) .. ").")
    end

    -- Header / context
    local Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    Title:SetText("Свой NPC")
    Title:SetTextColor(ns.COLORS.goldRaw.r, ns.COLORS.goldRaw.g, ns.COLORS.goldRaw.b)
    Title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -8)

    f.ContextText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.ContextText:SetPoint("TOPLEFT", Title, "BOTTOMLEFT", 0, -4)
    f.ContextText:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.ContextText:SetJustifyH("LEFT")
    f.ContextText:SetText("Активный: -")

    f.StatusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.StatusText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
    f.StatusText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 8)
    f.StatusText:SetJustifyH("LEFT")
    SetStatus(nil, "Готово.")

    -- Tabs
    local Tabs = {}
    local TabButtons = {}
    local function ShowTab(name)
        for tabName, tab in pairs(Tabs) do
            tab:SetShown(tabName == name)
        end
        for _, btn in ipairs(TabButtons) do
            ns.SetNGTabSelected(btn, btn.tabName == name)
        end
    end
    local function CreateTabButton(text, tabName, x)
        local btn = ns.CreateNGTab(f, text, tabName, function() ShowTab(tabName) end)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", x, -48)
        btn.tabName = tabName
        TabButtons[#TabButtons + 1] = btn
        return btn
    end
    local function CreateTabFrame(name)
        local host = CreateFrame("Frame", nil, f)
        host:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -78)
        host:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 28)
        host:Hide()
        Tabs[name] = host
        return host
    end

    CreateTabButton("Создать", "create", 12)
    CreateTabButton("Каталог", "catalog", 100)
    CreateTabButton("Вид", "look", 190)
    CreateTabButton("Экип", "gear", 260)
    CreateTabButton("Сервис", "service", 330)

    ------------------------------------------------------------------
    -- Tab: Create
    ------------------------------------------------------------------
    local CreateTab = CreateTabFrame("create")
    local CreateSection = ns.CreateNGSection(CreateTab, "Новый NPC", 620, 210)
    CreateSection:SetPoint("TOPLEFT", CreateTab, "TOPLEFT", 4, -4)
    CreateSection:SetPoint("TOPRIGHT", CreateTab, "TOPRIGHT", -4, -4)

    local NameLabel = ns.CreateNGLabel(CreateSection, "Имя:")
    NameLabel:SetPoint("TOPLEFT", CreateSection, "TOPLEFT", 12, -30)
    local DisplayNameBox = ns.CreateNGEditBox(CreateSection, "CustomNpc_DisplayName", 260, 22)
    DisplayNameBox:SetPoint("LEFT", NameLabel, "RIGHT", 8, 0)

    local CreateSubLabel = ns.CreateNGLabel(CreateSection, "Подпись:")
    CreateSubLabel:SetPoint("TOPLEFT", CreateSection, "TOPLEFT", 12, -58)
    local CreateSubBox = ns.CreateNGEditBox(CreateSection, "CustomNpc_CreateSubName", 260, 22)
    CreateSubBox:SetPoint("LEFT", CreateSubLabel, "RIGHT", 8, 0)

    local ModeLabel = ns.CreateNGLabel(CreateSection, "Источник:")
    ModeLabel:SetPoint("TOPLEFT", CreateSection, "TOPLEFT", 12, -94)
    local modeButtons = {}
    local function SetCreateMode(mode)
        State.createMode = mode
        for m, btn in pairs(modeButtons) do
            ns.SetNGTabSelected(btn, m == mode)
        end
    end
    local function MakeModeBtn(text, mode, x)
        local btn = ns.CreateNGTab(CreateSection, text, mode, function() SetCreateMode(mode) end)
        btn:SetPoint("TOPLEFT", CreateSection, "TOPLEFT", x, -90)
        modeButtons[mode] = btn
        return btn
    end
    MakeModeBtn("Пустой", "blank", 90)
    MakeModeBtn("Клон себя", "clone", 198)
    MakeModeBtn("Клон цели", "target", 306)
    SetCreateMode("clone")

    local CreateBtn = ns.CreateNGButton(CreateSection, "Создать", 120, 26)
    CreateBtn:SetPoint("TOPLEFT", CreateSection, "TOPLEFT", 12, -132)
    CreateBtn:SetScript("OnClick", function()
        local displayName = Trim(DisplayNameBox:GetText())
        if displayName == "" then
            SetStatus(false, "Укажите отображаемое имя.")
            return
        end
        local subName = Trim(CreateSubBox:GetText())
        State.key = nil
        State.name = displayName
        State.pendingSelectName = displayName
        SetStatus(nil, "Создание NPC…")
        if State.createMode == "blank" then
            AioCall("CreateBlank", displayName, subName)
        elseif State.createMode == "target" then
            AioCall("CloneTarget", displayName, subName)
        else
            AioCall("CloneSelf", displayName, subName)
        end
        ShowTab("catalog")
    end)

    local TempHint = CreateSection:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    TempHint:SetPoint("LEFT", CreateBtn, "RIGHT", 12, 0)
    TempHint:SetText("Ключ выдаёт сервер. После создания NPC появится в Каталоге.")

    ------------------------------------------------------------------
    -- Tab: Catalog
    ------------------------------------------------------------------
    local CatalogTab = CreateTabFrame("catalog")
    local SearchBox = ns.CreateNGEditBox(CatalogTab, "CustomNpc_Search", 220, 22)
    SearchBox:SetPoint("TOPLEFT", CatalogTab, "TOPLEFT", 4, -4)
    SearchBox:SetScript("OnTextChanged", function(self)
        State.filter = self:GetText() or ""
        if _G.NobleNextCustomNpc.OnNpcList then
            _G.NobleNextCustomNpc.OnNpcList(State.rows)
        end
    end)

    local RefreshBtn = ns.CreateNGButton(CatalogTab, "Обновить", 90, 22)
    RefreshBtn:SetPoint("LEFT", SearchBox, "RIGHT", 8, 0)
    RefreshBtn:SetScript("OnClick", RefreshList)

    local AllBtn = ns.CreateNGButton(CatalogTab, "Мои / Все", 90, 22)
    AllBtn:SetPoint("LEFT", RefreshBtn, "RIGHT", 6, 0)
    AllBtn:SetScript("OnClick", function()
        State.showAll = not State.showAll
        RefreshList()
        SetStatus(nil, State.showAll and "Список: все (admin)" or "Список: только мои")
    end)

    f.CountText = CatalogTab:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.CountText:SetPoint("LEFT", AllBtn, "RIGHT", 10, 0)
    f.CountText:SetText("Показано: 0")

    f.KeyReadonly = ns.CreateNGEditBox(CatalogTab, "CustomNpc_KeyRO", 120, 22)
    f.KeyReadonly:SetPoint("TOPRIGHT", CatalogTab, "TOPRIGHT", -4, -4)
    f.KeyReadonly:SetText("")
    local KeyROLabel = ns.CreateNGLabel(CatalogTab, "Ключ:")
    KeyROLabel:SetPoint("RIGHT", f.KeyReadonly, "LEFT", -6, 0)

    local listHost = CreateFrame("Frame", nil, CatalogTab)
    listHost:SetPoint("TOPLEFT", CatalogTab, "TOPLEFT", 4, -34)
    listHost:SetPoint("BOTTOMRIGHT", CatalogTab, "BOTTOMRIGHT", -4, 4)
    local scroll = CreateFrame("ScrollFrame", nil, listHost, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", listHost, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", listHost, "BOTTOMRIGHT", -22, 0)
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(560, 400)
    scroll:SetScrollChild(scrollChild)

    f.NpcList = ns.VirtualList.Create(scrollChild, {
        width = 540,
        rowHeight = 30,
        visibleCount = 10,
        onClick = function(row)
            SelectRow(row)
        end,
        renderRow = function(btn, row)
            local fs = btn.fs or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.fs = fs
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -3)
            fs:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            fs:SetJustifyH("LEFT")
            local mark = (State.key == row.key) and "|cffFFD100> |r" or ""
            fs:SetText(mark .. (row.name or "?") .. "  |cffaaaaaa" .. (row.key or "") .. "|r")

            local sub = btn.sub or btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            btn.sub = sub
            sub:ClearAllPoints()
            sub:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 6, 3)
            sub:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            sub:SetJustifyH("LEFT")
            sub:SetText(string.format("entry %s | models %s | equip %s | spawns %s | %s",
                tostring(row.entry or "-"),
                tostring(row.models or "-"),
                tostring(row.equip or "-"),
                tostring(row.spawns or "-"),
                tostring(row.owner or "-")))

            if btn.SetBackdropBorderColor then
                if State.key == row.key then
                    btn:SetBackdropBorderColor(1, 0.82, 0, 1)
                else
                    btn:SetBackdropBorderColor(0.25, 0.2, 0.1, 0.6)
                end
            end
        end,
    })

    ------------------------------------------------------------------
    -- Tab: Look
    ------------------------------------------------------------------
    local LookTab = CreateTabFrame("look")
    local lookScroll = NNL.Scroll.CreateFrame(LookTab)
    lookScroll:SetPoint("TOPLEFT", LookTab, "TOPLEFT", 0, 0)
    lookScroll:SetPoint("BOTTOMRIGHT", LookTab, "BOTTOMRIGHT", -22, 0)
    local LookBody = CreateFrame("Frame", nil, lookScroll)
    LookBody:SetSize(620, 620)
    lookScroll:SetScrollChild(LookBody)
    local function ResizeLookBody()
        local width = lookScroll:GetWidth()
        if width and width > 0 then LookBody:SetWidth(width) end
    end
    lookScroll:HookScript("OnSizeChanged", ResizeLookBody)
    LookTab:HookScript("OnShow", ResizeLookBody)
    local Identity, Body, Face, Advanced -- forward declarations for content height
    local function UpdateLookScrollHeight()
        local modelsH = (f.ModelsSection and f.ModelsSection:IsShown()) and (f.ModelsSection:GetHeight() + 8) or 0
        LookBody:SetHeight(18 + Identity:GetHeight() + 8 + Body:GetHeight() + 8
            + Face:GetHeight() + 8 + modelsH + Advanced:GetHeight() + 16)
    end

    f.EditGateHint = LookBody:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.EditGateHint:SetPoint("TOPLEFT", LookBody, "TOPLEFT", 8, -2)
    f.EditGateHint:SetPoint("TOPRIGHT", LookBody, "TOPRIGHT", -8, -2)
    f.EditGateHint:SetJustifyH("LEFT")
    f.EditGateHint:SetWordWrap(false)
    f.EditGateHint:SetText("Выберите шаблон во вкладке «Каталог».")

    Identity = ns.CreateNGSection(LookBody, "Имя и вариант (с сервера после выбора)", 620, 118)
    Identity:SetPoint("TOPLEFT", LookBody, "TOPLEFT", 4, -18)
    Identity:SetPoint("TOPRIGHT", LookBody, "TOPRIGHT", -4, -18)

    local SetNameLabel = ns.CreateNGLabel(Identity, "Имя:")
    SetNameLabel:SetPoint("TOPLEFT", Identity, "TOPLEFT", 12, -30)
    f.NameBox = ns.CreateNGEditBox(Identity, "CustomNpc_Name", 200, 22)
    f.NameBox:SetPoint("TOPLEFT", Identity, "TOPLEFT", 90, -30)
    local SetNameBtn = ns.CreateNGButton(Identity, "Применить имя", 120, 22)
    SetNameBtn:SetPoint("TOPRIGHT", Identity, "TOPRIGHT", -12, -30)
    f.NameBox:SetPoint("RIGHT", SetNameBtn, "LEFT", -8, 0)
    SetNameBtn:SetScript("OnClick", function()
        local key = RequireKey()
        local name = Trim(f.NameBox:GetText())
        if not key or name == "" then return end
        if not State.detailReady then
            SetStatus(false, "Дождитесь загрузки вида с сервера.")
            return
        end
        SendCNPCommand(".cnpc set name " .. key .. " " .. name)
        State.name = name
        UpdateContext()
        ScheduleNpcDetailRefresh()
    end)

    local SubLabel = ns.CreateNGLabel(Identity, "Подпись:")
    SubLabel:SetPoint("TOPLEFT", Identity, "TOPLEFT", 12, -58)
    f.SubNameBox = ns.CreateNGEditBox(Identity, "CustomNpc_SubName", 200, 22)
    f.SubNameBox:SetPoint("TOPLEFT", Identity, "TOPLEFT", 90, -58)
    local SetSubBtn = ns.CreateNGButton(Identity, "Применить подпись", 130, 22)
    SetSubBtn:SetPoint("TOPRIGHT", Identity, "TOPRIGHT", -12, -58)
    f.SubNameBox:SetPoint("RIGHT", SetSubBtn, "LEFT", -8, 0)
    SetSubBtn:SetScript("OnClick", function()
        local key = RequireKey()
        local subName = Trim(f.SubNameBox:GetText())
        if not key or subName == "" then return end
        if not State.detailReady then
            SetStatus(false, "Дождитесь загрузки вида с сервера.")
            return
        end
        SendCNPCommand(".cnpc set subname " .. key .. " " .. subName)
        ScheduleNpcDetailRefresh()
    end)

    local VarLabel = ns.CreateNGLabel(Identity, "Вариант:")
    VarLabel:SetPoint("TOPLEFT", Identity, "TOPLEFT", 12, -86)
    f.VariationBox = ns.CreateNGEditBox(Identity, "CustomNpc_Variation", 40, 22)
    f.VariationBox:SetPoint("TOPLEFT", Identity, "TOPLEFT", 90, -86)
    f.VariationBox:SetText("1")
    f.VariationBox:SetScript("OnTextChanged", function(self)
        if State.hydrating then
            return
        end
        local v = tonumber(Trim(self:GetText()))
        if not v or v < 1 then
            return
        end
        local maxV = math.max(1, tonumber(State.modelCount) or 1)
        v = math.min(math.floor(v), maxV)
        if v == State.variation then
            return
        end
        State.variation = v
        UpdateContext()
        if State.key then
            RequestNpcDetail(State.key, State.variation)
        end
    end)
    local VarMinus = ns.CreateNGButton(Identity, "-", 22, 22)
    VarMinus:SetPoint("LEFT", f.VariationBox, "RIGHT", 4, 0)
    VarMinus:SetScript("OnClick", function()
        if not State.key then return end
        State.variation = math.max(1, (State.variation or 1) - 1)
        UpdateContext()
        RequestNpcDetail(State.key, State.variation)
    end)
    local VarPlus = ns.CreateNGButton(Identity, "+", 22, 22)
    VarPlus:SetPoint("LEFT", VarMinus, "RIGHT", 2, 0)
    VarPlus:SetScript("OnClick", function()
        if not State.key then return end
        local maxV = math.max(1, tonumber(State.modelCount) or 1)
        State.variation = math.min(maxV, (State.variation or 1) + 1)
        UpdateContext()
        RequestNpcDetail(State.key, State.variation)
    end)

    Body = ns.CreateNGSection(LookBody, "Раса и пол", 620, 100)
    Body:SetPoint("TOPLEFT", Identity, "BOTTOMLEFT", 0, -8)
    Body:SetPoint("TOPRIGHT", Identity, "BOTTOMRIGHT", 0, -8)

    local RaceLabel = ns.CreateNGLabel(Body, "Раса:")
    RaceLabel:SetPoint("TOPLEFT", Body, "TOPLEFT", 12, -32)
    f.RaceDropdown = CreateFrame("Frame", "NobleNextCnpcRaceDD", Body, "UIDropDownMenuTemplate")
    f.RaceDropdown:SetPoint("TOPLEFT", Body, "TOPLEFT", 50, -26)
    InitSimpleDropdown(f.RaceDropdown, 180, function()
        local entries = {}
        local source = (#State.races > 0) and State.races or FALLBACK_RACES
        for _, race in ipairs(source) do
            local id = tonumber(race.raceId)
            if id then
                entries[#entries + 1] = {
                    value = id,
                    label = FormatRaceLabel(id, race.name) .. (race.available == false and " [нет]" or ""),
                    disabled = race.available == false,
                }
            end
        end
        return entries
    end, function(value)
        State.raceId = value
    end)
    UIDropDownMenu_SetSelectedValue(f.RaceDropdown, State.raceId)
    UIDropDownMenu_SetText(f.RaceDropdown, FormatRaceLabel(State.raceId, "Human"))

    local RaceApply = ns.CreateNGButton(Body, "Применить расу", 120, 22)
    RaceApply:SetPoint("TOPLEFT", Body, "TOPLEFT", 280, -30)
    RaceApply:SetScript("OnClick", function()
        local key = RequireKey()
        if not key then return end
        if not State.detailReady then
            SetStatus(false, "Дождитесь загрузки вида с сервера.")
            return
        end
        ClearFaceBrowser("Обновление опций после смены расы…")
        SendCNPCommand(".cnpc set race " .. key .. " " .. tostring(State.raceId) .. OptionalVariationSuffix())
        ScheduleNpcDetailRefresh()
    end)

    local GenderLabel = ns.CreateNGLabel(Body, "Пол:")
    GenderLabel:SetPoint("TOPLEFT", Body, "TOPLEFT", 12, -70)
    f.GenderDropdown = CreateFrame("Frame", "NobleNextCnpcGenderDD", Body, "UIDropDownMenuTemplate")
    f.GenderDropdown:SetPoint("TOPLEFT", Body, "TOPLEFT", 50, -64)
    InitSimpleDropdown(f.GenderDropdown, 120, function()
        return GENDERS
    end, function(value)
        State.gender = value
    end)
    UIDropDownMenu_SetSelectedValue(f.GenderDropdown, State.gender)
    UIDropDownMenu_SetText(f.GenderDropdown, "Мужской")

    local GenderApply = ns.CreateNGButton(Body, "Применить пол", 120, 22)
    GenderApply:SetPoint("TOPLEFT", Body, "TOPLEFT", 280, -68)
    GenderApply:SetScript("OnClick", function()
        local key = RequireKey()
        if not key then return end
        if not State.detailReady then
            SetStatus(false, "Дождитесь загрузки вида с сервера.")
            return
        end
        if State.gender == nil then
            SetStatus(false, "Выберите пол.")
            return
        end
        ClearFaceBrowser("Обновление опций после смены пола…")
        SendCNPCommand(".cnpc set gender " .. key .. " " .. tostring(State.gender) .. OptionalVariationSuffix())
        ScheduleNpcDetailRefresh()
    end)

    local FaceBtn = ns.CreateNGButton(Body, "Лицо из себя", 120, 22)
    FaceBtn:SetPoint("TOPLEFT", Body, "TOPLEFT", 410, -30)
    FaceBtn:SetScript("OnClick", function()
        local key = RequireKey()
        if not key then return end
        if not State.detailReady then
            SetStatus(false, "Дождитесь загрузки вида с сервера.")
            return
        end
        ClearFaceBrowser("Копирование лица с персонажа…")
        SendCNPCommand(".cnpc set face self " .. key .. OptionalVariationSuffix())
        ScheduleNpcDetailRefresh()
    end)

    local GuildBtn = ns.CreateNGButton(Body, "Гильдия из себя", 120, 22)
    GuildBtn:SetPoint("TOPLEFT", Body, "TOPLEFT", 410, -68)
    GuildBtn:SetScript("OnClick", function()
        local key = RequireKey()
        if not key then return end
        SendCNPCommand(".cnpc set guild " .. key .. OptionalVariationSuffix())
        ScheduleNpcDetailRefresh()
    end)

    ------------------------------------------------------------------
    -- Face browser (dense option/choice indices from server C++)
    ------------------------------------------------------------------
    Face = ns.CreateNGSection(LookBody, "Лицо (опции с сервера)", 620, 180)
    Face:SetPoint("TOPLEFT", Body, "BOTTOMLEFT", 0, -8)
    Face:SetPoint("TOPRIGHT", Body, "BOTTOMRIGHT", 0, -8)

    f.FaceGateHint = Face:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.FaceGateHint:SetPoint("TOPLEFT", Face, "TOPLEFT", 12, -26)
    f.FaceGateHint:SetPoint("RIGHT", Face, "RIGHT", -12, 0)
    f.FaceGateHint:SetJustifyH("LEFT")
    f.FaceGateHint:SetText("Выберите NPC в «Каталог».")

    f.FaceHeader = Face:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.FaceHeader:SetPoint("TOPLEFT", Face, "TOPLEFT", 12, -26)
    f.FaceHeader:SetPoint("RIGHT", Face, "RIGHT", -12, 0)
    f.FaceHeader:SetJustifyH("LEFT")
    f.FaceHeader:SetText("Лицо недоступно.")

    f.FaceListsHost = CreateFrame("Frame", nil, Face)
    f.FaceListsHost:SetPoint("TOPLEFT", Face, "TOPLEFT", 8, -44)
    f.FaceListsHost:SetPoint("BOTTOMRIGHT", Face, "BOTTOMRIGHT", -8, 8)
    f.FaceListsHost:Hide()

    local optHost = CreateFrame("Frame", nil, f.FaceListsHost)
    optHost:SetPoint("TOPLEFT", f.FaceListsHost, "TOPLEFT", 0, 0)
    optHost:SetPoint("BOTTOMLEFT", f.FaceListsHost, "BOTTOMLEFT", 0, 0)
    optHost:SetWidth(290)
    local optScroll = CreateFrame("ScrollFrame", nil, optHost, "UIPanelScrollFrameTemplate")
    optScroll:SetPoint("TOPLEFT", optHost, "TOPLEFT", 0, 0)
    optScroll:SetPoint("BOTTOMRIGHT", optHost, "BOTTOMRIGHT", -22, 0)
    local optChild = CreateFrame("Frame", nil, optScroll)
    optChild:SetSize(260, 120)
    optScroll:SetScrollChild(optChild)

    f.FaceOptionList = ns.VirtualList.Create(optChild, {
        width = 260,
        rowHeight = 22,
        visibleCount = 5,
        scrollFrame = optScroll,
        onClick = function(row)
            if not row or State.faceLoading then
                return
            end
            if not State.detailReady or not State.isOutfit then
                return
            end
            State.faceOptionIndex = tonumber(row.index)
            State.faceOptionName = row.name
            if f.FaceOptionList then
                f.FaceOptionList:Refresh()
            end
            RequestFaceChoices(State.faceOptionIndex)
        end,
        renderRow = function(btn, row)
            local fs = btn.fs or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.fs = fs
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", btn, "LEFT", 4, 0)
            fs:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
            fs:SetJustifyH("LEFT")
            local selected = tonumber(State.faceOptionIndex) == tonumber(row.index)
            local mark = selected and "|cffFFD100> |r" or ""
            local cur = tonumber(row.currentChoiceIndex) or 0
            local cnt = tonumber(row.choiceCount) or 0
            fs:SetText(string.format("%s%d: %s |cffaaaaaa%d/%d|r",
                mark, tonumber(row.index) or 0, row.name or "?", cur, cnt))
            if btn.SetBackdropBorderColor then
                if selected then
                    btn:SetBackdropBorderColor(1, 0.82, 0, 1)
                else
                    btn:SetBackdropBorderColor(0.25, 0.2, 0.1, 0.6)
                end
            end
        end,
    })

    local chHost = CreateFrame("Frame", nil, f.FaceListsHost)
    chHost:SetPoint("TOPLEFT", optHost, "TOPRIGHT", 8, 0)
    chHost:SetPoint("BOTTOMRIGHT", f.FaceListsHost, "BOTTOMRIGHT", 0, 0)
    local chScroll = CreateFrame("ScrollFrame", nil, chHost, "UIPanelScrollFrameTemplate")
    chScroll:SetPoint("TOPLEFT", chHost, "TOPLEFT", 0, 0)
    chScroll:SetPoint("BOTTOMRIGHT", chHost, "BOTTOMRIGHT", -22, 0)
    local chChild = CreateFrame("Frame", nil, chScroll)
    chChild:SetSize(260, 120)
    chScroll:SetScrollChild(chChild)
    f.FaceListsHost:HookScript("OnSizeChanged", function(_, width)
        if width and width > 8 then optHost:SetWidth((width - 8) / 2) end
    end)
    optScroll:HookScript("OnSizeChanged", function(_, width)
        if width and width > 0 then optChild:SetWidth(width) end
    end)
    chScroll:HookScript("OnSizeChanged", function(_, width)
        if width and width > 0 then chChild:SetWidth(width) end
    end)

    f.FaceChoiceList = ns.VirtualList.Create(chChild, {
        width = 260,
        rowHeight = 22,
        visibleCount = 5,
        scrollFrame = chScroll,
        onClick = function(row)
            if not row or State.faceLoading then
                return
            end
            local key = RequireKey()
            if not key or not State.detailReady or not State.isOutfit then
                return
            end
            local optionIndex = tonumber(State.faceOptionIndex)
            local choiceIndex = tonumber(row.index)
            if not optionIndex or not choiceIndex then
                return
            end
            if tonumber(State.faceCurrentChoiceIndex) == choiceIndex then
                SetStatus(nil, "Этот вариант уже выбран.")
                return
            end
            State.faceLoading = true
            SetStatus(nil, "Применение лица…")
            AioCall("SetFace", key, optionIndex, choiceIndex, State.variation or 1)
        end,
        renderRow = function(btn, row)
            local fs = btn.fs or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.fs = fs
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", btn, "LEFT", 4, 0)
            fs:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
            fs:SetJustifyH("LEFT")
            local selected = tonumber(State.faceCurrentChoiceIndex) == tonumber(row.index)
            local mark = selected and "|cff00cc66[x] |r" or ""
            fs:SetText(string.format("%s%d: %s", mark, tonumber(row.index) or 0, row.name or "?"))
            if btn.SetBackdropBorderColor then
                if selected then
                    btn:SetBackdropBorderColor(0.2, 0.8, 0.4, 1)
                else
                    btn:SetBackdropBorderColor(0.25, 0.2, 0.1, 0.6)
                end
            end
        end,
    })

    ------------------------------------------------------------------
    -- Model variations (shown when models > 1)
    ------------------------------------------------------------------
    local Models = ns.CreateNGSection(LookBody, "Виды модели", 620, 110)
    Models:SetPoint("TOPLEFT", Face, "BOTTOMLEFT", 0, -8)
    Models:SetPoint("TOPRIGHT", Face, "BOTTOMRIGHT", 0, -8)
    f.ModelsSection = Models
    Models:Hide()

    f.ModelsHint = Models:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.ModelsHint:SetPoint("TOPLEFT", Models, "TOPLEFT", 12, -24)
    f.ModelsHint:SetPoint("RIGHT", Models, "RIGHT", -100, 0)
    f.ModelsHint:SetJustifyH("LEFT")
    f.ModelsHint:SetText("")

    local ApplyVarBtn = ns.CreateNGButton(Models, "Apply вида", 90, 22)
    ApplyVarBtn:SetPoint("TOPRIGHT", Models, "TOPRIGHT", -12, -22)
    ApplyVarBtn:SetScript("OnClick", function()
        if not State.key then
            SetStatus(false, "Сначала выберите NPC.")
            return
        end
        AioCall("ApplySelected", State.variation or 1)
    end)

    local modelHost = CreateFrame("Frame", nil, Models)
    modelHost:SetPoint("TOPLEFT", Models, "TOPLEFT", 8, -46)
    modelHost:SetPoint("BOTTOMRIGHT", Models, "BOTTOMRIGHT", -8, 8)
    local modelScroll = CreateFrame("ScrollFrame", nil, modelHost, "UIPanelScrollFrameTemplate")
    modelScroll:SetPoint("TOPLEFT", modelHost, "TOPLEFT", 0, 0)
    modelScroll:SetPoint("BOTTOMRIGHT", modelHost, "BOTTOMRIGHT", -22, 0)
    local modelChild = CreateFrame("Frame", nil, modelScroll)
    modelChild:SetSize(560, 60)
    modelScroll:SetScrollChild(modelChild)
    modelScroll:HookScript("OnSizeChanged", function(_, width)
        if width and width > 0 then modelChild:SetWidth(width) end
    end)

    f.ModelList = ns.VirtualList.Create(modelChild, {
        width = 560,
        rowHeight = 22,
        visibleCount = 2,
        scrollFrame = modelScroll,
        onClick = function(row)
            if not row or not State.key then
                return
            end
            local v = tonumber(row.variation)
            if not v or v < 1 then
                return
            end
            if v == State.variation and State.detailReady then
                return
            end
            State.variation = v
            ClearFaceBrowser("Смена вида…")
            UpdateContext()
            RequestNpcDetail(State.key, State.variation)
        end,
        renderRow = function(btn, row)
            local fs = btn.fs or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.fs = fs
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", btn, "LEFT", 4, 0)
            fs:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
            fs:SetJustifyH("LEFT")
            local selected = tonumber(State.variation) == tonumber(row.variation)
            local mark = selected and "|cffFFD100> |r" or ""
            local tag = row.isOutfit and "outfit" or "display"
            fs:SetText(string.format("%s%d: displayId=%s scale=%s (%s)",
                mark,
                tonumber(row.variation) or 0,
                tostring(row.displayId or "-"),
                tostring(row.scale or "-"),
                tag))
            if btn.SetBackdropBorderColor then
                if selected then
                    btn:SetBackdropBorderColor(1, 0.82, 0, 1)
                else
                    btn:SetBackdropBorderColor(0.25, 0.2, 0.1, 0.6)
                end
            end
        end,
    })

    Advanced = ns.CreateNGSection(LookBody, "Дополнительно", 620, 90)
    Advanced:SetPoint("TOPLEFT", Models, "BOTTOMLEFT", 0, -8)
    Advanced:SetPoint("TOPRIGHT", Models, "BOTTOMRIGHT", 0, -8)

    -- When Models hidden, pin Advanced under Face.
    local function RelayoutLookSections()
        if Models:IsShown() then
            Advanced:ClearAllPoints()
            Advanced:SetPoint("TOPLEFT", Models, "BOTTOMLEFT", 0, -8)
            Advanced:SetPoint("TOPRIGHT", Models, "BOTTOMRIGHT", 0, -8)
        else
            Advanced:ClearAllPoints()
            Advanced:SetPoint("TOPLEFT", Face, "BOTTOMLEFT", 0, -8)
            Advanced:SetPoint("TOPRIGHT", Face, "BOTTOMRIGHT", 0, -8)
        end
        UpdateLookScrollHeight()
    end
    local _UpdateModelsVisibility = UpdateModelsVisibility
    UpdateModelsVisibility = function()
        _UpdateModelsVisibility()
        RelayoutLookSections()
    end
    RelayoutLookSections()
    UpdateFaceGate()

    local DisplayLabel = ns.CreateNGLabel(Advanced, "Модель (DisplayID):")
    DisplayLabel:SetPoint("TOPLEFT", Advanced, "TOPLEFT", 12, -30)
    f.DisplayBox = ns.CreateNGEditBox(Advanced, "CustomNpc_Display", 80, 22)
    f.DisplayBox:SetPoint("TOPLEFT", Advanced, "TOPLEFT", 170, -30)
    local DisplayBtn = ns.CreateNGButton(Advanced, "Задать", 70, 22)
    DisplayBtn:SetPoint("LEFT", f.DisplayBox, "RIGHT", 6, 0)
    DisplayBtn:SetScript("OnClick", function()
        local key = RequireKey()
        local displayId = tonumber(Trim(f.DisplayBox:GetText()))
        if not key or not displayId then return end
        if not State.detailReady then
            SetStatus(false, "Дождитесь загрузки вида с сервера.")
            return
        end
        SendCNPCommand(".cnpc set displayid " .. key .. " " .. tostring(math.floor(displayId)) .. OptionalVariationSuffix())
        ScheduleNpcDetailRefresh()
    end)

    local ScaleLabel = ns.CreateNGLabel(Advanced, "Масштаб:")
    ScaleLabel:SetPoint("TOPLEFT", Advanced, "TOPLEFT", 12, -60)
    f.ScaleBox = ns.CreateNGEditBox(Advanced, "CustomNpc_Scale", 60, 22)
    f.ScaleBox:SetPoint("TOPLEFT", Advanced, "TOPLEFT", 170, -60)
    f.ScaleBox:SetText("1")
    local ScaleBtn = ns.CreateNGButton(Advanced, "Задать", 70, 22)
    ScaleBtn:SetPoint("LEFT", f.ScaleBox, "RIGHT", 6, 0)
    ScaleBtn:SetScript("OnClick", function()
        local key = RequireKey()
        local scale = Trim(f.ScaleBox:GetText())
        if not key or scale == "" then return end
        if not State.detailReady then
            SetStatus(false, "Дождитесь загрузки вида с сервера.")
            return
        end
        SendCNPCommand(".cnpc set scale " .. key .. " " .. scale .. OptionalVariationSuffix())
        ScheduleNpcDetailRefresh()
    end)

    LookApplyButtons[#LookApplyButtons + 1] = SetNameBtn
    LookApplyButtons[#LookApplyButtons + 1] = SetSubBtn
    LookApplyButtons[#LookApplyButtons + 1] = RaceApply
    LookApplyButtons[#LookApplyButtons + 1] = GenderApply
    LookApplyButtons[#LookApplyButtons + 1] = FaceBtn
    LookApplyButtons[#LookApplyButtons + 1] = DisplayBtn
    LookApplyButtons[#LookApplyButtons + 1] = ScaleBtn
    SetLookApplyEnabled(false, "Сначала выберите NPC — вид загрузится с сервера.")

    ------------------------------------------------------------------
    -- Tab: Gear
    ------------------------------------------------------------------
    local GearTab = CreateTabFrame("gear")
    local Gear = ns.CreateNGSection(GearTab, "Броня и оружие", 620, 170)
    Gear:SetPoint("TOPLEFT", GearTab, "TOPLEFT", 4, -4)
    Gear:SetPoint("TOPRIGHT", GearTab, "TOPRIGHT", -4, -4)

    local SlotLabel = ns.CreateNGLabel(Gear, "Часть брони:")
    SlotLabel:SetPoint("TOPLEFT", Gear, "TOPLEFT", 12, -30)
    f.SlotDropdown = CreateFrame("Frame", "NobleNextCnpcSlotDD", Gear, "UIDropDownMenuTemplate")
    f.SlotDropdown:SetPoint("TOPLEFT", Gear, "TOPLEFT", 100, -24)
    InitSimpleDropdown(f.SlotDropdown, 140, function()
        return ARMOR_SLOTS
    end, function(value)
        State.armorSlot = value
    end)
    UIDropDownMenu_SetSelectedValue(f.SlotDropdown, State.armorSlot)
    UIDropDownMenu_SetText(f.SlotDropdown, "Голова")

    local SourceLabel = ns.CreateNGLabel(Gear, "Источник:")
    SourceLabel:SetPoint("TOPLEFT", Gear, "TOPLEFT", 300, -30)
    local sourceButtons = {}
    local function SetItemSource(mode)
        State.itemSource = mode
        for m, btn in pairs(sourceButtons) do
            if btn.SetBackdropBorderColor then
                if m == mode then
                    btn:SetBackdropBorderColor(1, 0.82, 0, 1)
                else
                    btn:SetBackdropBorderColor(0.25, 0.2, 0.1, 0.6)
                end
            end
        end
        if f.ItemBox then
            f.ItemBox:SetShown(mode == "item")
        end
    end
    local SelfSrc = ns.CreateNGButton(Gear, "С себя", 80, 22)
    SelfSrc:SetPoint("TOPLEFT", Gear, "TOPLEFT", 370, -28)
    SelfSrc:SetScript("OnClick", function() SetItemSource("self") end)
    sourceButtons.self = SelfSrc
    local ItemSrc = ns.CreateNGButton(Gear, "Предмет", 80, 22)
    ItemSrc:SetPoint("LEFT", SelfSrc, "RIGHT", 6, 0)
    ItemSrc:SetScript("OnClick", function() SetItemSource("item") end)
    sourceButtons.item = ItemSrc

    local ItemLabel = ns.CreateNGLabel(Gear, "Предмет/link:")
    ItemLabel:SetPoint("TOPLEFT", Gear, "TOPLEFT", 12, -68)
    f.ItemBox = ns.CreateNGEditBox(Gear, "CustomNpc_Item", 260, 22)
    f.ItemBox:SetPoint("LEFT", ItemLabel, "RIGHT", 8, 0)
    f.ItemBox:SetScript("OnReceiveDrag", function(self)
        local cursorType, itemId = GetCursorInfo()
        if cursorType == "item" and itemId then
            self:SetText(tostring(itemId))
            ClearCursor()
            SetItemSource("item")
        end
    end)
    f.ItemBox:HookScript("OnMouseUp", function(self)
        local cursorType, itemId = GetCursorInfo()
        if cursorType == "item" and itemId then
            self:SetText(tostring(itemId))
            ClearCursor()
            SetItemSource("item")
        end
    end)
    SetItemSource("self")

    local function ResolveArmorItemArg()
        if State.itemSource == "self" then
            return "self"
        end
        return ExtractItemToken(f.ItemBox:GetText())
    end

    local ArmorBtn = ns.CreateNGButton(Gear, "Надеть броню", 120, 24)
    ArmorBtn:SetPoint("TOPLEFT", Gear, "TOPLEFT", 12, -100)
    ArmorBtn:SetScript("OnClick", function()
        local key = RequireKey()
        if not key then return end
        local slot = State.armorSlot or "head"
        local item = ResolveArmorItemArg()
        if not item then
            SetStatus(false, "Укажите предмет или режим «С себя».")
            return
        end
        if slot == "all" and item ~= "self" then
            SetStatus(false, "Слот «Все» работает только с источником «С себя».")
            return
        end
        SendCNPCommand(".cnpc equip armor " .. key .. " " .. slot .. " " .. item .. OptionalVariationSuffix())
    end)

    local AllSelfBtn = ns.CreateNGButton(Gear, "Вся броня с себя", 140, 24)
    AllSelfBtn:SetPoint("LEFT", ArmorBtn, "RIGHT", 8, 0)
    AllSelfBtn:SetScript("OnClick", function()
        local key = RequireKey()
        if not key then return end
        SendCNPCommand(".cnpc equip armor " .. key .. " all self" .. OptionalVariationSuffix())
    end)

    local UnequipBtn = ns.CreateNGButton(Gear, "Снять слот", 100, 24)
    UnequipBtn:SetPoint("LEFT", AllSelfBtn, "RIGHT", 8, 0)
    UnequipBtn:SetScript("OnClick", function()
        local key = RequireKey()
        if not key then return end
        local slot = State.armorSlot
        if not slot or slot == "all" then
            SetStatus(false, "Для снятия выберите конкретный слот (не «Все»).")
            return
        end
        SendCNPCommand(".cnpc unequip armor " .. key .. " " .. slot .. OptionalVariationSuffix())
        SetStatus(nil, "Снятие слота " .. slot .. "…")
    end)

    local RightBtn = ns.CreateNGButton(Gear, "Правая с себя", 110, 24)
    RightBtn:SetPoint("TOPLEFT", Gear, "TOPLEFT", 12, -132)
    RightBtn:SetScript("OnClick", function()
        local key = RequireKey()
        if not key then return end
        local item = ResolveArmorItemArg() or "self"
        SendCNPCommand(".cnpc equip right " .. key .. " " .. item .. OptionalVariationSuffix())
    end)
    local LeftBtn = ns.CreateNGButton(Gear, "Левая с себя", 110, 24)
    LeftBtn:SetPoint("LEFT", RightBtn, "RIGHT", 8, 0)
    LeftBtn:SetScript("OnClick", function()
        local key = RequireKey()
        if not key then return end
        local item = ResolveArmorItemArg() or "self"
        SendCNPCommand(".cnpc equip left " .. key .. " " .. item .. OptionalVariationSuffix())
    end)
    local UnequipR = ns.CreateNGButton(Gear, "Снять правую", 110, 24)
    UnequipR:SetPoint("LEFT", LeftBtn, "RIGHT", 8, 0)
    UnequipR:SetScript("OnClick", function()
        local key = RequireKey()
        if not key then return end
        SendCNPCommand(".cnpc unequip right " .. key .. OptionalVariationSuffix())
        SetStatus(nil, "Снятие правой руки…")
    end)
    local UnequipL = ns.CreateNGButton(Gear, "Снять левую", 110, 24)
    UnequipL:SetPoint("LEFT", UnequipR, "RIGHT", 8, 0)
    UnequipL:SetScript("OnClick", function()
        local key = RequireKey()
        if not key then return end
        SendCNPCommand(".cnpc unequip left " .. key .. OptionalVariationSuffix())
        SetStatus(nil, "Снятие левой руки…")
    end)

    ------------------------------------------------------------------
    -- Tab: Service
    ------------------------------------------------------------------
    local ServiceTab = CreateTabFrame("service")
    local Service = ns.CreateNGSection(ServiceTab, "Спавн и сервис", 620, 150)
    Service:SetPoint("TOPLEFT", ServiceTab, "TOPLEFT", 4, -4)
    Service:SetPoint("TOPRIGHT", ServiceTab, "TOPRIGHT", -4, -4)

    local TempSpawn = ns.CreateNGButton(Service, "Временный спавн", 140, 24)
    TempSpawn:SetPoint("TOPLEFT", Service, "TOPLEFT", 12, -30)
    TempSpawn:SetScript("OnClick", function()
        local key = RequireKey()
        if not key then return end
        SendCNPCommand(".cnpc spawn temp " .. key)
    end)

    local PermSpawn = ns.CreateNGButton(Service, "Постоянный спавн", 140, 24)
    PermSpawn:SetPoint("LEFT", TempSpawn, "RIGHT", 8, 0)
    PermSpawn:SetScript("OnClick", function()
        local key = RequireKey()
        if not key then return end
        if ns.Confirm and ns.Confirm.Show then
            ns.Confirm.Show({
                text = "Постоянный спавн NPC \"" .. key .. "\" в БД?",
                onAccept = function()
                    SendCNPCommand(".cnpc spawn " .. key)
                end,
            })
        else
            SendCNPCommand(".cnpc spawn " .. key)
        end
    end)

    local ReloadBtn = ns.CreateNGButton(Service, "Reload", 90, 24)
    ReloadBtn:SetPoint("LEFT", PermSpawn, "RIGHT", 8, 0)
    ReloadBtn:SetScript("OnClick", function()
        local key = RequireKey()
        if not key then return end
        AioCall("Reload", key)
        C_Timer.After(0.5, function()
            if State.key == key then
                RefreshList()
                RequestNpcDetail(key, State.variation)
            end
        end)
    end)

    local RefreshBtn2 = ns.CreateNGButton(Service, "Refresh", 90, 24)
    RefreshBtn2:SetPoint("LEFT", ReloadBtn, "RIGHT", 8, 0)
    RefreshBtn2:SetScript("OnClick", function()
        local key = RequireKey()
        if not key then return end
        SendCNPCommand(".cnpc refresh " .. key)
    end)

    local ApplyBtn = ns.CreateNGButton(Service, "Apply к select", 120, 24)
    ApplyBtn:SetPoint("TOPLEFT", Service, "TOPLEFT", 12, -68)
    ApplyBtn:SetScript("OnClick", function()
        AioCall("ApplySelected", State.variation or 1)
    end)

    local CatalogBtn = ns.CreateNGButton(Service, "Загрузить каталог рас", 160, 24)
    CatalogBtn:SetPoint("LEFT", ApplyBtn, "RIGHT", 8, 0)
    CatalogBtn:SetScript("OnClick", RefreshCatalog)

    local DeleteBtn = ns.CreateNGButton(Service, "Удалить NPC", 120, 24)
    DeleteBtn:SetPoint("TOPLEFT", Service, "TOPLEFT", 12, -106)
    DeleteBtn:SetScript("OnClick", function()
        local key = RequireKey()
        if not key then return end
        if ns.Confirm and ns.Confirm.Show then
            ns.Confirm.Show({
                text = "Удалить custom NPC \"" .. key .. "\"?\nБудет отправлено: .cnpc delete " .. key,
                onAccept = function()
                    SendCNPCommand(".cnpc delete " .. key)
                    State.key = nil
                    State.name = nil
                    State.entry = nil
                    UpdateContext()
                    RefreshList()
                end,
            })
        else
            SendCNPCommand(".cnpc delete " .. key)
        end
    end)

    local HelpBtn = ns.CreateNGButton(Service, "Help", 70, 24)
    HelpBtn:SetPoint("LEFT", DeleteBtn, "RIGHT", 8, 0)
    HelpBtn:SetScript("OnClick", function()
        SendCNPCommand(".cnpc help")
    end)

    local RemoveVarBtn = ns.CreateNGButton(Service, "Удалить вариант", 130, 24)
    RemoveVarBtn:SetPoint("LEFT", HelpBtn, "RIGHT", 8, 0)
    RemoveVarBtn:SetScript("OnClick", function()
        local key = RequireKey()
        local variation = tonumber(State.variation)
        if not key or not variation or variation < 2 then
            SetStatus(false, "Удаление варианта возможно только для N >= 2.")
            return
        end
        SendCNPCommand(".cnpc remove variation " .. key .. " " .. tostring(math.floor(variation)))
    end)

    f:HookScript("OnShow", function()
        UpdateContext()
        RefreshList()
        RefreshCatalog()
    end)

    UpdateContext()
    ShowTab("create")
    return f
end

local function ShowCustomNpc()
    ns.ShowModule("Custom NPC")
end

C_Timer.After(0, function()
    ns.RegisterSlashCommand("NNCUSTOMNPC", ShowCustomNpc, { "nncustomnpc", "nncnpc" })
end)

ns.RegisterModule("Custom NPC", InitCustomNpcModule, "Создание и настройка custom NPC")
