-- Loaded through the NobleNextGM private extension namespace.
-- GM/CustomNPC/Init.lua — picker-first интерфейс для .customnpc/.cnpc

local _, ns = ...
local NNL = LibStub("NobleNextLib-1.0")
local MODEL_ROW_HEIGHT = 46

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
    local id = tonumber(text)
    if id and id == math.floor(id) and id > 0 and id <= 4294967295 then return tostring(math.floor(id)) end
    return nil
end

local function SelectDropdownValue(dropdown, value, label)
    dropdown.value = value
    dropdown:SetDefaultText(label or "Выберите")
    dropdown:GenerateMenu()
end

local function InitSimpleDropdown(dropdown, width, getEntries, onPick)
    dropdown:SetWidth(width)
    dropdown:SetupMenu(function(_, menu)
        menu:SetMinimumWidth(width)
        menu:SetScrollMode(220)
        for _, entry in ipairs(getEntries() or {}) do
            local item = menu:CreateRadio(entry.label, function() return dropdown.value == entry.value end, function()
                if entry.disabled then return end
                if onPick(entry.value, entry.label) == false then return end
                SelectDropdownValue(dropdown, entry.value, entry.label)
            end)
            item:SetEnabled(not entry.disabled)
            if entry.tooltip then
                item:SetTooltip(function(tooltip)
                    tooltip:SetText(entry.label)
                    tooltip:AddLine(entry.tooltip, 1, 0.8, 0.3, true)
                end)
            end
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
        faceUsesIds = false,
        faceOptionId = nil,
        faceCurrentChoiceId = nil,
        faceChoiceOffset = 0,
        faceChoiceTotal = 0,
        faceHasMore = false,
        faceSerial = 0,
        facePending = nil,
        editorPending = nil,
        editorRequest = 0,
        facePreview = false,
        closed = false,
        catalogSerial = 0,
        models = {},
        canEdit = false,
        modelPending = false,
        modelRequest = 0,
        createRequest = 0,
        refreshModelDetail = false,
        listOffset = 0,
        listLimit = 50,
        listLoading = false,
        hasMore = false,
    }

    local LookApplyButtons = {}
    local OutfitApplyButtons = {}
    local ModelButtons = {}
    local ShowTab
    local RefreshFaceHeader, LoadFaceCatalog, RequestFaceOptions, UpdateGearGate

    local function ModelLabel(model)
        return string.format("Образ %d — %s", tonumber(model.variation) or 1,
            model.isOutfit and "настраиваемая внешность" or "готовая модель")
    end

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
        local name = State.name or "без имени"
        local entry = State.entry and tostring(State.entry) or "-"
        local models = tonumber(State.modelCount) or 1
        if State.key then
            f.ContextText:SetText(string.format("%s | образ %d из %d | ID %s%s",
                name, State.variation or 1, models, entry, State.detailReady and "" or " | загрузка…"))
        else
            f.ContextText:SetText("Выберите НИПа в каталоге или создайте нового.")
        end
        if f.VariationDropdown then
            SelectDropdownValue(f.VariationDropdown, State.variation, "Образ " .. tostring(State.variation or 1))
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

    local function ReleaseFaceCatalog()
        State.catalogSerial = State.catalogSerial + 1
        if State.catalogLease then State.catalogLease:Release() end
        State.catalogLease, State.catalogData = nil, nil
    end

    local function LoadCatalogModule()
        if not _G.NobleNextData and C_AddOns and C_AddOns.LoadAddOn and not (InCombatLockdown and InCombatLockdown()) then
            pcall(C_AddOns.LoadAddOn, "NobleNextDB")
        end
        return _G.NobleNextData
    end

    local function RaceEntries()
        local catalog = State.activeTab == "look" and LoadCatalogModule() or _G.NobleNextData
        local allowed, entries, currentListed = {}, {}, false
        for _, race in ipairs(catalog and catalog.GetRaceList and catalog.GetRaceList() or {}) do
            local id = tonumber(race.race_id)
            if id then allowed[id] = race.name or true end
        end
        for _, race in ipairs(State.races) do
            local id = tonumber(race.raceId)
            if id and allowed[id] and race.available ~= false then
                entries[#entries + 1] = { value = id, label = FormatRaceLabel(id, type(allowed[id]) == "string" and allowed[id] or race.name) }
                currentListed = currentListed or id == State.confirmedRaceId
            end
        end
        local current = State.confirmedRaceId
        if current and current > 0 and not currentListed then
            entries[#entries + 1] = { value = current, label = FormatRaceLabel(current) .. " (текущая)",
                tooltip = "Сохранённая раса этого образа. Внешность доступна по данным сервера." }
        end
        return entries
    end

    local function FaceLocalRow(row, choice)
        local data = State.catalogData
        local model = data and data.models and data.models[State.gender]
        local id = tonumber(choice and row.choiceId or row.optionId)
        local lookup = model and (choice and model.choicesById or model.optionsById)
        return id and lookup and lookup[id]
    end

    local function FaceName(row, choice)
        local localRow = FaceLocalRow(row, choice)
        local name = (localRow and (localRow.name or localRow.option_name)) or row.name
        if name and name ~= "" and not name:match("^Choice%s+%d+$") then return name end
        if not choice then return "Настройка" end
        local ordinal = localRow and tonumber(localRow.order_index)
        return (State.faceOptionName or "Вариант") .. " — вариант "
            .. tostring(ordinal and ordinal + 1 or row.index or row.choiceId or "")
    end

    local function FaceSwatches(row)
        local localRow = FaceLocalRow(row, true) or {}
        local colors = {}
        for index = 0, 1 do
            local rgb = localRow["swatch" .. index .. "_rgb"]
            local value = type(rgb) == "string" and tonumber(rgb:gsub("^#", ""), 16)
                or tonumber(row["swatch" .. index])
            -- DB2 stores ARGB; zero means no swatch, opaque black remains valid.
            if value and (rgb or value ~= 0) then
                value = value % 16777216
                colors[#colors + 1] = { math.floor(value / 65536) / 255,
                    math.floor(value / 256) % 256 / 255, value % 256 / 255,
                    string.format("#%06X", value) }
            end
        end
        return colors
    end

    local function VisibleFaceOptions(rows, usesIds, preview)
        local skin, other = {}, {}
        for _, row in ipairs(rows) do
            if row.available == true or (preview and row.projection == "unknown")
                or (not usesIds and row.available ~= false) then
                local localRow = FaceLocalRow(row)
                local name = FaceName(row)
                local isSkin = (localRow and localRow.base_section == 0)
                    or name == "Цвет кожи" or name == "Skin Color"
                local group = isSkin and skin or other
                group[#group + 1] = row
            end
        end
        for _, row in ipairs(other) do skin[#skin + 1] = row end
        return skin
    end

    local function ClearFaceBrowser(message)
        State.faceSerial = State.faceSerial + 1
        State.faceOptionsRequest, State.faceChoiceRequest, State.facePending = nil, nil, nil
        State.faceOptionId, State.faceCurrentChoiceId = nil, nil
        State.faceChoiceOffset, State.faceChoiceTotal, State.faceHasMore = 0, 0, false
        State.facePreview = false
        State.faceCatalogError, State.faceProjectedSelections = nil, nil
        ReleaseFaceCatalog()
        State.faceOptions = {}
        State.faceChoices = {}
        State.faceOptionIndex = nil
        State.faceOptionName = nil
        State.faceCurrentChoiceIndex = nil
        State.faceLoading = false
        if f.FaceOptionDropdown then SelectDropdownValue(f.FaceOptionDropdown, nil, "Выберите параметр") end
        if f.FaceChoiceList then
            f.FaceChoiceList:SetRows({})
        end
        if f.FaceHeader then
            f.FaceHeader:SetText(message or "Лицо недоступно.")
        end
        if f.FacePrevious then f.FacePrevious:SetEnabled(false) end
        if f.FaceNext then f.FaceNext:SetEnabled(false) end
    end

    local function ProjectFaceAvailability(optionId, choiceId)
        local catalog = _G.NobleNextData
        local evaluate = catalog and (choiceId and catalog.EvaluateChoice or catalog.EvaluateOption)
        if not evaluate or not State.catalogData then return nil, "server_required" end
        if choiceId then
            return evaluate(State.catalogData, State.gender, optionId, choiceId, State.classId, State.faceProjectedSelections)
        end
        return evaluate(State.catalogData, State.gender, optionId, State.classId, State.faceProjectedSelections)
    end

    local function ShowPreviewChoices(offset)
        local model = State.catalogData and State.catalogData.models[State.gender]
        local option = model and model.optionsById and model.optionsById[State.faceOptionId]
        local choices = {}
        for _, choice in ipairs(option and option.choices or {}) do
            local available, reason = ProjectFaceAvailability(State.faceOptionId, choice.choice_id)
            if available ~= false then
                choices[#choices + 1] = {
                    choiceId = choice.choice_id, name = choice.name, available = available == true,
                    reason = reason or (available == nil and "server_required" or nil), preview = true,
                    projection = available == nil and "unknown" or "allowed",
                }
            end
        end
        State.faceChoiceOffset = math.max(0, math.min(offset or 0, math.max(0, math.floor((#choices - 1) / 100) * 100)))
        State.faceChoiceTotal, State.faceChoices = #choices, {}
        State.faceHasMore = State.faceChoiceOffset + 100 < #choices
        State.faceCurrentChoiceId = State.faceProjectedSelections and State.faceProjectedSelections[State.faceOptionId]
        for index = State.faceChoiceOffset + 1, math.min(State.faceChoiceOffset + 100, #choices) do
            State.faceChoices[#State.faceChoices + 1] = choices[index]
        end
        if f.FaceChoiceList then f.FaceChoiceList:SetRows(State.faceChoices) end
        if RefreshFaceHeader then RefreshFaceHeader() end
    end

    LoadFaceCatalog = function(preview)
        ReleaseFaceCatalog()
        local request = State.catalogSerial
        if State.closed or not State.isOutfit then return end
        State.faceCatalogError = nil
        local function CatalogUnavailable()
            if preview then
                State.faceLoading = false
                State.faceCatalogError = "Каталог недоступен. Примените расу и пол, чтобы запросить варианты у сервера."
                if RefreshFaceHeader then RefreshFaceHeader() end
            end
        end
        local catalog = LoadCatalogModule()
        if not catalog or not catalog.AcquireModel then
            CatalogUnavailable()
            return
        end
        local race, gender = State.raceId, State.gender
        local ok, lease = pcall(catalog.AcquireModel, race, gender, function(data)
            if State.closed or request ~= State.catalogSerial or race ~= State.raceId or gender ~= State.gender then return end
            State.catalogData = data
            if preview then
                local model = data and data.models and data.models[gender]
                State.faceProjectedSelections = {}
                -- Only choices belonging to the draft model can satisfy its dependencies.
                for optionId, choiceId in pairs(State.faceCanonicalChoices or {}) do
                    local option = model and model.optionsById and model.optionsById[optionId]
                    for _, choice in ipairs(option and option.choices or {}) do
                        if choice.choice_id == choiceId then State.faceProjectedSelections[optionId] = choiceId;break end
                    end
                end
                State.faceOptions = {}
                for _, option in ipairs(model and model.options or {}) do
                    local available, reason = ProjectFaceAvailability(option.option_id)
                    State.faceOptions[#State.faceOptions + 1] = {
                        optionId = option.option_id, name = option.option_name or option.name,
                        available = available == true, reason = reason or (available == nil and "server_required" or nil), preview = true,
                        projection = available == nil and "unknown" or (available and "allowed" or "locked"),
                    }
                end
                State.faceOptions = VisibleFaceOptions(State.faceOptions, true, true)
                State.faceLoading = false
                if not model then CatalogUnavailable() end
                local pick = State.faceOptions[1]
                for _, option in ipairs(State.faceOptions) do
                    if option.optionId == State.faceOptionId then pick = option;break end
                end
                State.faceOptionId = pick and pick.optionId
                State.faceOptionName = pick and FaceName(pick)
                if f.FaceOptionDropdown then f.FaceOptionDropdown:GenerateMenu() end
                ShowPreviewChoices(0)
            else
                State.faceOptions = VisibleFaceOptions(State.faceOptions, State.faceUsesIds, false)
                if f.FaceOptionDropdown then f.FaceOptionDropdown:GenerateMenu() end
                if f.FaceChoiceList then f.FaceChoiceList:Refresh() end
            end
            if RefreshFaceHeader then RefreshFaceHeader() end
        end)
        if ok and lease then State.catalogLease = lease else CatalogUnavailable() end
    end

    local function PreviewFaceDraft()
        ClearFaceBrowser()
        if State.raceId == State.confirmedRaceId and State.gender == State.confirmedGender then
            LoadFaceCatalog(false)
            RequestFaceOptions()
            return
        end
        State.facePreview = true
        State.faceUsesIds = true
        State.faceLoading = true
        if f.FaceHeader then f.FaceHeader:SetText("Предпросмотр. Примените расу и пол, чтобы редактировать настройки.") end
        LoadFaceCatalog(true)
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
            gateText = "У готовой модели нельзя изменить лицо. Добавьте образ персонажа или цели во вкладке «Образы»."
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
        for _, frame in ipairs({ f.FaceModeHint, f.FacePageText, f.FacePrevious, f.FaceNext, f.FaceRefresh, f.FaceOptionDropdown }) do
            frame:SetShown(outfit and true or false)
        end
        if not outfit then
            State.faceOptions = {}
            State.faceChoices = {}
            State.faceOptionIndex = nil
            State.faceOptionId = nil
            State.faceOptionName = nil
            State.faceCurrentChoiceIndex = nil
            State.faceLoading = false
            if f.FaceOptionDropdown then f.FaceOptionDropdown:GenerateMenu() end
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
        State.variation = variation
        local keptOptionIndex = keepFaceOption and tonumber(State.faceOptionIndex) or nil
        local keptOptionId = keepFaceOption and tonumber(State.faceOptionId) or nil
        local keptOptionName = keepFaceOption and State.faceOptionName or nil
        State.detailReady = false
        State.detailRequest = (State.detailRequest or 0) + 1
        SetLookApplyEnabled(false, "Дождитесь загрузки вида с сервера.")
        for _, btn in ipairs(ModelButtons) do btn:SetEnabled(false) end
        ClearFaceBrowser("Загрузка вида…")
        UpdateContext()
        UpdateFaceGate()
        -- UpdateFaceGate clears selection while detailReady=false; restore after soft SetFace refresh.
        if keptOptionIndex then
            State.faceOptionIndex = keptOptionIndex
            State.faceOptionName = keptOptionName
        end
        if keptOptionId then State.faceOptionId = keptOptionId end
        return AioCall("GetNpcDetail", key, variation, State.detailRequest)
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
            if State.key ~= key or State.variation ~= variation then
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
        if f.ModelsHint then
            if State.key then
                f.ModelsHint:SetText(string.format("%s | образов: %d | выбран образ %d", State.name or State.key, count, State.variation or 1))
            else
                f.ModelsHint:SetText("Выберите НИПа в каталоге. Здесь будут все его образы.")
            end
        end
        if f.ModelEmpty then
            f.ModelEmpty:SetShown(#State.models == 0)
            f.ModelEmpty:SetText(State.key and "Загрузка образов…" or "Сначала выберите НИПа.")
        end
        for _, btn in ipairs(ModelButtons) do
            btn:SetEnabled(State.key ~= nil and State.detailReady and State.canEdit and not State.modelPending and not State.facePending and not State.editorPending)
        end
        SetLookApplyEnabled(State.detailReady and State.canEdit and not State.modelPending and not State.facePending and not State.editorPending,
            "Выберите доступный образ и дождитесь ответа сервера.")
        if not State.isOutfit then
            for _, button in ipairs(OutfitApplyButtons) do button:SetEnabled(false) end
        end
        if UpdateGearGate then UpdateGearGate() end
        if f.RefreshDetails then
            f.RefreshDetails:SetEnabled(State.key ~= nil and not State.modelPending and not State.facePending and not State.editorPending)
        end
        if f.ModelList then f.ModelList:Refresh() end
    end

    local function ArmFaceReadTimeout(field, request)
        C_Timer.After(15, function()
            if State.closed or State[field] ~= request then return end
            State[field] = nil
            State.faceLoading = false
            if RefreshFaceHeader then RefreshFaceHeader() end
            SetStatus(false, "Не удалось загрузить настройки. Нажмите «Обновить» в разделе внешности.")
        end)
    end

    RequestFaceOptions = function()
        local key = State.key
        if State.closed or not key or key == "" or not State.isOutfit or not State.detailReady then
            UpdateFaceGate()
            return false
        end
        State.faceLoading = true
        State.facePreview = false
        State.faceSerial = State.faceSerial + 1
        State.faceOptionsRequest = State.faceSerial
        if f.FaceHeader then
            f.FaceHeader:SetText(string.format("Вид %d — загрузка опций…", State.variation or 1))
        end
        ArmFaceReadTimeout("faceOptionsRequest", State.faceOptionsRequest)
        return AioCall("GetFaceOptions", key, State.variation or 1, State.faceOptionsRequest)
    end

    local function RequestFaceChoices(option, offset)
        local key = State.key
        option = tonumber(option)
        if State.closed or State.facePreview or not key or key == "" or not option or not State.isOutfit then
            return false
        end
        State.faceLoading = true
        State.faceChoiceOffset = offset or 0
        State.faceSerial = State.faceSerial + 1
        State.faceChoiceRequest = State.faceSerial
        ArmFaceReadTimeout("faceChoiceRequest", State.faceChoiceRequest)
        State.faceChoices = {}
        if f.FaceChoiceList then f.FaceChoiceList:SetRows({}) end
        if RefreshFaceHeader then RefreshFaceHeader() end
        if State.faceUsesIds then
            return AioCall("GetFaceChoicesById", key, option, State.variation or 1,
                State.faceChoiceOffset, 100, State.faceChoiceRequest)
        end
        return AioCall("GetFaceChoices", key, option, State.variation or 1)
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
        return AioCall("GetModelList", key)
    end

    local function RequestFaceBrowser()
        UpdateFaceGate()
        if State.activeTab == "look" and State.key and State.detailReady and State.isOutfit then
            if State.raceId ~= State.confirmedRaceId or State.gender ~= State.confirmedGender then PreviewFaceDraft()
            else LoadFaceCatalog(false);RequestFaceOptions() end
        end
        if #State.models == 0 or #State.models ~= State.modelCount then RequestModelList() end
    end

    local function ApplyNpcDetail(detail, skipFaceRefresh)
        if State.closed or type(detail) ~= "table" or not detail.key then
            return
        end
        if State.modelPending or State.facePending or State.editorPending then return end
        if tostring(detail.key) ~= tostring(State.key) then
            return
        end
        if tonumber(detail.variation) ~= State.variation then
            return
        end
        if detail.requestId ~= nil and detail.requestId ~= State.detailRequest then return end
        if detail.modelRequestId ~= nil and detail.modelRequestId ~= State.modelRequest then return end

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
        State.canEdit = detail.canEdit == true
        State.classId = tonumber(detail.classId)
        State.faceCanonicalChoices = {}
        for _, choice in ipairs(detail.customizations or {}) do
            local optionId, choiceId = tonumber(choice.optionId), tonumber(choice.choiceId)
            if optionId and choiceId then State.faceCanonicalChoices[optionId] = choiceId end
        end
        State.detailReady = true
        for _, model in ipairs(State.models) do
            if tonumber(model.variation) == State.variation then
                model.displayId, model.scale, model.isOutfit = detail.displayId, detail.scale, State.isOutfit
                break
            end
        end

        if State.isOutfit then
            if detail.race ~= nil then
                State.raceId = tonumber(detail.race) or State.raceId
            end
            if detail.gender ~= nil then
                State.gender = tonumber(detail.gender) or State.gender
            end
            State.confirmedRaceId, State.confirmedGender = State.raceId, State.gender
        end

        if f.NameBox and not skipFaceRefresh then
            f.NameBox:SetText(State.name or "")
        end
        if f.SubNameBox and not skipFaceRefresh then
            f.SubNameBox:SetText(State.subName or "")
        end
        if f.DisplayBox and not skipFaceRefresh then
            f.DisplayBox:SetText(State.displayId and tostring(State.displayId) or "")
        end
        if f.ScaleBox and not skipFaceRefresh then
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
            SelectDropdownValue(f.RaceDropdown, State.raceId, label)
        end
        if f.GenderDropdown and State.isOutfit then
            local gLabel = "Мужской"
            for _, g in ipairs(GENDERS) do
                if g.value == State.gender then
                    gLabel = g.label
                    break
                end
            end
            SelectDropdownValue(f.GenderDropdown, State.gender, gLabel)
        end

        State.hydrating = false
        SetLookApplyEnabled(State.canEdit, "Нет права изменять этого НИПа.")
        UpdateContext()
        UpdateModelsVisibility()
        if not State.canEdit then
            SetStatus(nil, "Образ загружен для просмотра. Нет права изменять этого НИПа.")
        elseif State.isOutfit then
            SetStatus(true, "Образ загружен. Можно менять внешность и снаряжение.")
        else
            SetStatus(true, "Готовая модель. Для настройки лица добавьте образ персонажа или цели.")
        end
        if not skipFaceRefresh then RequestFaceBrowser() end
    end

    local function SelectRow(row, detailIncoming)
        if not row then return end
        local sameKey = State.key and tostring(State.key) == tostring(row.key)
        State.key = row.key
        State.name = row.name
        State.entry = row.entry
        if not sameKey then
            State.editorPending = nil
            State.variation = 1
            State.detailReady = false
            State.isOutfit = false
            State.canEdit = false
            State.modelPending = false
            State.refreshModelDetail = false
            SetLookApplyEnabled(false, "Дождитесь загрузки образа с сервера.")
            State.modelCount = tonumber(row.models) or 1
            ClearFaceBrowser("Загрузка…")
            State.models = {}
            if f.ModelList then f.ModelList:SetRows({}) end
        end
        UpdateContext()
        UpdateModelsVisibility()
        if f.NpcList then
            f.NpcList:Refresh()
        end
        SetStatus(true, "Загрузка вида " .. tostring(row.key) .. "…")
        if not detailIncoming then RequestNpcDetail(State.key, State.variation) end
    end

    local function SelectModel(variation)
        if State.modelPending or State.facePending or State.editorPending then
            SetStatus(nil, "Дождитесь завершения изменения образа.");return false
        end
        variation = tonumber(variation)
        if not State.key or not variation or variation < 1 then return end
        if variation == State.variation and State.detailReady then return end
        State.editorPending = nil
        State.variation = variation
        UpdateContext()
        UpdateModelsVisibility()
        RequestNpcDetail(State.key, variation)
    end

    local function ChangeModel(method, source)
        if State.closed or not State.key or not State.detailReady or not State.canEdit or State.modelPending or State.facePending or State.editorPending then return end
        if method ~= "RemoveModel" and #State.models >= 255 then
            SetStatus(false, "Достигнут предел: 255 образов у одного НИПа.")
            return
        end
        State.modelPending = true
        State.modelRequest = State.modelRequest + 1
        local request, key = State.modelRequest, State.key
        UpdateModelsVisibility()
        SetStatus(nil, method == "RemoveModel" and "Удаление образа…" or "Создание нового образа…")
        local sent
        if method == "CopyModel" or method == "RemoveModel" then
            sent = AioCall(method, State.key, State.variation, request)
        else
            sent = AioCall(method, State.key, source, State.variation, request)
        end
        if not sent then
            State.modelPending = false
            UpdateModelsVisibility()
        else
            C_Timer.After(15, function()
                if State.key ~= key or State.modelRequest ~= request or not State.modelPending then return end
                State.modelPending = false
                State.detailReady = false
                State.refreshModelDetail = true
                UpdateModelsVisibility()
                RequestModelList()
                SetStatus(false, "Ответ не получен. Проверьте список образов перед повторным действием.")
            end)
        end
    end

    local function RequireEditable()
        if State.closed then return nil end
        if not State.key or State.key == "" then
            SetStatus(false, "Сначала выберите NPC из списка или создайте нового.")
            return nil
        end
        if not State.detailReady or State.modelPending or State.facePending or State.editorPending then
            SetStatus(false, "Дождитесь загрузки образа и завершения текущего действия.")
            return nil
        end
        if not State.canEdit then
            SetStatus(false, "Нет права изменять этого НИПа.")
            return nil
        end
        return State.key
    end

    local function RunEditorAction(method, operation, ...)
        local key = RequireEditable()
        if not key then return end
        State.editorRequest = State.editorRequest + 1
        local request = {key = key, variation = State.variation, requestId = State.editorRequest, operation = operation}
        State.editorPending = request
        State.detailRequest = (State.detailRequest or 0) + 1
        UpdateModelsVisibility()
        SetStatus(nil, "Выполнение действия на сервере…")
        if not AioCall(method, key, request.variation, request.requestId, operation, ...) then
            State.editorPending = nil
            UpdateModelsVisibility()
            return
        end
        C_Timer.After(15, function()
            if State.editorPending ~= request then return end
            State.editorPending = nil
            RequestNpcDetail(key, request.variation)
            UpdateModelsVisibility()
            SetStatus(false, "Ответ не получен. Образ перечитывается; действие не повторяется.")
        end)
    end

    local function RefreshList()
        State.listLoading = true
        if f.CatalogEmpty then
            f.CatalogEmpty:SetText("Загрузка каталога…")
            f.CatalogEmpty:SetShown(#State.rows == 0)
        end
        if f.PreviousPage then f.PreviousPage:SetEnabled(false) end
        if f.NextPage then f.NextPage:SetEnabled(false) end
        if not AioCall("GetNpcList", State.showAll and true or false, State.listOffset, State.listLimit) then
            State.listLoading = false
            if f.CatalogEmpty then f.CatalogEmpty:SetText("Нет связи с сервером. Нажмите «Обновить».") end
        end
    end

    local function RenderNpcList()
        local filter = Trim(State.filter):lower()
        local filtered = {}
        for _, row in ipairs(State.rows) do
            local hay = string.format("%s %s %s", row.key or "", row.name or "", tostring(row.entry or "")):lower()
            if filter == "" or hay:find(filter, 1, true) then filtered[#filtered + 1] = row end
        end
        if f.NpcList then f.NpcList:SetRows(filtered) end
        if f.CountText then
            f.CountText:SetText(string.format("Страница %d | показано %d из %d", math.floor(State.listOffset / State.listLimit) + 1, #filtered, #State.rows))
        end
        if f.CatalogEmpty then
            f.CatalogEmpty:SetShown(#filtered == 0)
            f.CatalogEmpty:SetText(filter ~= "" and "На этой странице совпадений нет. Измените поиск или перейдите на другую страницу."
                or "НИПов пока нет. Откройте «Создать», чтобы добавить первого.")
        end
        if f.PreviousPage then f.PreviousPage:SetEnabled(State.listOffset > 0 and not State.listLoading) end
        if f.NextPage then f.NextPage:SetEnabled(State.hasMore and not State.listLoading) end
    end

    local function RefreshCatalog()
        AioCall("GetCatalog", true)
    end

    _G.NobleNextCustomNpc = _G.NobleNextCustomNpc or {}
    _G.NobleNextCustomNpc.OnEditorResult = function(payload)
        local pending = State.editorPending
        if State.closed or not pending or payload.requestId ~= pending.requestId or payload.key ~= State.key
            or tonumber(payload.variation) ~= State.variation or payload.operation ~= pending.operation then return end
        State.editorPending = nil
        if payload.ok == true and payload.operation == "delete" then
            State.key, State.name, State.entry, State.models = nil, nil, nil, {}
            State.canEdit, State.detailReady = false, false
            if f.ModelList then f.ModelList:SetRows({}) end
            ShowTab("catalog")
            RefreshList()
        elseif payload.operation == "reload" then
            State.detailReady, State.refreshModelDetail = false, true
            RequestModelList()
        elseif type(payload.detail) == "table" then
            ApplyNpcDetail(payload.detail)
        else
            RequestNpcDetail()
        end
        UpdateContext()
        UpdateModelsVisibility()
        SetStatus(payload.ok == true, payload.message or "Не удалось выполнить действие.")
    end
    _G.NobleNextCustomNpc.OnStatus = function(ok, message)
        SetStatus(ok, message)
        if not ok then
            UpdateModelsVisibility()
            if State.listLoading then
                State.listLoading = false
                if f.CatalogEmpty then
                    f.CatalogEmpty:SetText("Не удалось загрузить каталог. Нажмите «Обновить».")
                    f.CatalogEmpty:SetShown(#State.rows == 0)
                end
            end
        end
        if not ok or not State.key or type(message) ~= "string" then
            return
        end
        -- After Reload Status, pull detail for current key.
        if message:find("reload", 1, true) then
            RefreshList()
            State.detailReady = false
            State.refreshModelDetail = true
            UpdateModelsVisibility()
            RequestModelList()
            return
        end
        if message:find("Face обновлён", 1, true) then
            ScheduleNpcDetailRefresh({ keepFaceOption = true })
        end
    end
    _G.NobleNextCustomNpc.OnNpcList = function(rows, meta)
        meta = meta or {}
        if meta.offset ~= nil and tonumber(meta.offset) ~= State.listOffset then return end
        if meta.canIncludeAll == true and meta.includeAll ~= nil and meta.includeAll ~= State.showAll then return end
        State.rows = rows or {}
        State.listLoading = false
        State.hasMore = meta.hasMore == true
        if meta.includeAll ~= nil then State.showAll = meta.includeAll == true end
        if f.AllNpcButton then
            f.AllNpcButton:SetShown(meta.canIncludeAll == true)
            ns.SetNGTabSelected(f.AllNpcButton, State.showAll)
            ns.SetNGTabSelected(f.MyNpcButton, not State.showAll)
        end
        RenderNpcList()
        if State.key then
            for _, row in ipairs(State.rows) do
                if row.key == State.key then
                    State.name = row.name
                    State.entry = row.entry
                    if row.models then
                        State.modelCount = tonumber(row.models) or State.modelCount
                    end
                    UpdateContext()
                    break
                end
            end
        end
    end
    _G.NobleNextCustomNpc.OnNpcCreated = function(payload)
        if type(payload) ~= "table" or not payload.key then return end
        if f.CreateBtn then f.CreateBtn:SetEnabled(true) end
        State.listOffset = 0
        State.filter = ""
        if f.SearchBox then f.SearchBox:SetText("") end
        SelectRow({ key = payload.key, name = payload.name or State.pendingSelectName, entry = payload.entry, models = 1 }, true)
        State.pendingSelectName = nil
        ShowTab("models")
        RefreshList()
    end
    _G.NobleNextCustomNpc.OnNpcCreateFailed = function(payload)
        if not State.pendingSelectName then return end
        State.pendingSelectName = nil
        if f.CreateBtn then f.CreateBtn:SetEnabled(true) end
        SetStatus(false, type(payload) == "table" and payload.message or "Не удалось создать НИПа.")
    end
    _G.NobleNextCustomNpc.OnNpcDetail = function(detail)
        ApplyNpcDetail(detail)
    end
    local function IsFacePayloadCurrent(payload)
        return not State.closed and State.activeTab == "look" and type(payload) == "table"
            and tostring(payload.key) == tostring(State.key)
            and (payload.variation == nil or tonumber(payload.variation) == State.variation)
    end

    local function FaceLockReason(reason)
        if reason == "server_required" then return "Недостаточно данных для предпросмотра. Доступность проверит сервер." end
        if reason == "class_required" then return "Вариант недоступен для класса этого NPC." end
        if reason == "race_required" then return "Вариант недоступен для выбранной расы." end
        if reason == "choice_required" then return "Сначала измените связанные настройки внешности." end
        if reason == "option_prerequisites" then return "Сначала измените связанные настройки внешности." end
        if reason == "choice_prerequisites" then return "Вариант недоступен при текущих настройках внешности." end
        return "Не выполнены условия для этого варианта."
    end

    local function FaceAvailabilityLabel(row)
        if row.preview then
            if row.projection == "unknown" then return " | проверит сервер" end
            return row.available and " | доступно" or " | недоступно"
        end
        return row.available == false and " | недоступно" or ""
    end

    local function SetFaceTooltip(button, row, choice)
        button:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(FaceName(row, choice))
            if choice then
                for _, color in ipairs(FaceSwatches(row)) do GameTooltip:AddLine(color[4], color[1], color[2], color[3]) end
            end
            if row.available == false then GameTooltip:AddLine(FaceLockReason(row.reason), 1, 0.8, 0.3, true) end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end

    RefreshFaceHeader = function()
        local option = State.faceUsesIds and State.faceOptionId or State.faceOptionIndex
        if f.FaceOptionDropdown then
            SelectDropdownValue(f.FaceOptionDropdown, option, State.faceOptionName or "Выберите параметр")
        end
        if f.FaceHeader then
            f.FaceHeader:SetText(State.facePreview and "Предпросмотр выбранной расы и пола"
                or string.format("Образ %d | %s%s", State.variation or 1,
                    State.faceOptionName or "Выберите настройку",
                    option and ((State.faceUsesIds and " | ID " or " | номер ") .. tostring(option)) or ""))
        end
        if f.FaceModeHint then
            f.FaceModeHint:SetText(State.faceCatalogError or (State.facePreview and "Предпросмотр условий. Для изменения вариантов примените расу и пол."
                or (State.facePending and "Применение варианта…"
                or (State.faceLoading and "Загрузка вариантов…"
                or (State.faceUsesIds and "Сначала выберите цвет кожи. Показаны доступные варианты с исходными ID DB2."
                or "Совместимый режим: номера сервера, а не ID DB2. Обновите сервер для выбора по ID.")))))
        end
        if f.FacePageText then
            f.FacePageText:SetText(string.format("Варианты: %d–%d из %d", State.faceChoiceTotal > 0 and State.faceChoiceOffset + 1 or 0,
                    State.faceChoiceOffset + #State.faceChoices, State.faceChoiceTotal))
        end
        local pageEnabled = State.faceUsesIds and not State.faceLoading and not State.facePending
        if f.FacePrevious then f.FacePrevious:SetEnabled(pageEnabled and State.faceChoiceOffset > 0) end
        if f.FaceNext then f.FaceNext:SetEnabled(pageEnabled and State.faceHasMore) end
    end

    _G.NobleNextCustomNpc.OnFaceOptions = function(payload)
        if not IsFacePayloadCurrent(payload) or State.facePreview then return end
        local usesIds = payload.supportsChoiceIds == true
        if payload.requestId ~= nil and payload.requestId ~= State.faceOptionsRequest then return end
        if usesIds and (not State.faceOptionsRequest or payload.requestId ~= State.faceOptionsRequest) then return end
        State.faceOptionsRequest = nil
        State.faceUsesIds = usesIds
        if payload.classId ~= nil then State.classId = tonumber(payload.classId) end
        State.faceLoading = false
        State.faceOptions = payload.options or {}
        if usesIds then
            -- A fresh full read also reconciles changes whose mutation reply was lost.
            State.faceCanonicalChoices = {}
            for _, option in ipairs(State.faceOptions) do
                local optionId, choiceId = tonumber(option.optionId), tonumber(option.currentChoiceId)
                if optionId and optionId > 0 and choiceId and choiceId > 0 then
                    State.faceCanonicalChoices[optionId] = choiceId
                end
            end
        end
        State.faceOptions = VisibleFaceOptions(State.faceOptions, usesIds, false)
        if f.FaceOptionDropdown then f.FaceOptionDropdown:GenerateMenu() end
        UpdateFaceGate()
        if not payload.isOutfit then ClearFaceBrowser("У готовой модели нет настройки лица.");return end
        if #State.faceOptions == 0 then ClearFaceBrowser("Сервер не предоставил варианты настройки лица.");return end
        local keep = usesIds and State.faceOptionId or State.faceOptionIndex
        local pick
        for _, option in ipairs(State.faceOptions) do
            if tonumber(usesIds and option.optionId or option.index) == keep then pick = option;break end
        end
        if not pick then
            for _, option in ipairs(State.faceOptions) do
                if (usesIds and option.available == true) or (not usesIds and option.available ~= false) then pick = option;break end
            end
        end
        pick = pick or State.faceOptions[1]
        State.faceOptionIndex, State.faceOptionId = tonumber(pick.index), tonumber(pick.optionId)
        State.faceOptionName = FaceName(pick)
        State.faceOptionAvailable = (usesIds and pick.available == true) or (not usesIds and pick.available ~= false)
        State.faceCurrentChoiceId = tonumber(pick.currentChoiceId)
        State.faceCurrentChoiceIndex = tonumber(pick.currentChoiceIndex)
        if f.FaceOptionDropdown then
            SelectDropdownValue(f.FaceOptionDropdown, State.faceUsesIds and State.faceOptionId or State.faceOptionIndex, State.faceOptionName or "Выберите параметр")
        end
        RequestFaceChoices(usesIds and State.faceOptionId or State.faceOptionIndex, 0)
    end

    _G.NobleNextCustomNpc.OnFaceChoices = function(payload)
        if not IsFacePayloadCurrent(payload) or State.facePreview then return end
        if State.faceUsesIds then
            if not State.faceChoiceRequest or payload.requestId ~= State.faceChoiceRequest or tonumber(payload.optionId) ~= State.faceOptionId
                or tonumber(payload.offset or 0) ~= State.faceChoiceOffset then return end
        elseif tonumber(payload.optionIndex) ~= State.faceOptionIndex then return end
        State.faceChoiceRequest = nil
        State.faceLoading = false
        State.faceChoices = {}
        for _, row in ipairs(payload.choices or {}) do
            if row.available == true or (not State.faceUsesIds and row.available ~= false) then
                State.faceChoices[#State.faceChoices + 1] = row
            end
        end
        State.faceCurrentChoiceIndex = tonumber(payload.currentChoiceIndex)
        State.faceCurrentChoiceId = tonumber(payload.currentChoiceId)
        State.faceOptionAvailable = (State.faceUsesIds and payload.optionAvailable == true)
            or (not State.faceUsesIds and payload.optionAvailable ~= false)
        State.faceChoiceTotal = tonumber(payload.total) or #State.faceChoices
        State.faceHasMore = payload.hasMore == true
        if f.FaceChoiceList then f.FaceChoiceList:SetRows(State.faceChoices) end
        RefreshFaceHeader()
        if payload.error then
            SetStatus(false, payload.error)
            if f.FaceModeHint then f.FaceModeHint:SetText(payload.error) end
        end
    end

    _G.NobleNextCustomNpc.OnFaceChanged = function(payload)
        local pending = State.facePending
        if not pending or not IsFacePayloadCurrent(payload) or payload.requestId ~= pending.requestId
            or tonumber(payload.optionId) ~= pending.optionId then return end
        State.facePending = nil
        State.faceLoading = false
        if type(payload.detail) == "table" then ApplyNpcDetail(payload.detail, true) end
        State.faceOptionsRequest = payload.requestId
        if type(payload.options) == "table" then _G.NobleNextCustomNpc.OnFaceOptions(payload.options)
        else RequestFaceOptions() end
        UpdateModelsVisibility()
        SetStatus(true, "Вариант применён. Доступные настройки обновлены сервером.")
    end

    _G.NobleNextCustomNpc.OnFaceChangeFailed = function(payload)
        local pending = State.facePending
        if not pending or not IsFacePayloadCurrent(payload) or payload.requestId ~= pending.requestId
            or tonumber(payload.optionId) ~= pending.optionId then return end
        State.facePending = nil
        State.faceLoading = false
        UpdateModelsVisibility()
        SetStatus(false, payload.message or "Не удалось применить вариант.")
        RequestFaceOptions()
    end
    _G.NobleNextCustomNpc.OnModelList = function(payload)
        if State.closed or State.editorPending or State.facePending or type(payload) ~= "table" then
            return
        end
        if payload.requestId ~= nil and (not State.modelPending or payload.requestId ~= State.modelRequest) then return end
        if State.modelPending and payload.requestId ~= State.modelRequest then return end
        if tostring(payload.key) ~= tostring(State.key) then
            return
        end
        State.models = payload.models or {}
        State.modelCount = #State.models
        if f.ModelList then
            f.ModelList:SetRows(State.models)
        end
        UpdateModelsVisibility()
        if (State.refreshModelDetail or State.variation > #State.models) and #State.models > 0 and not State.modelPending then
            State.refreshModelDetail = false
            RequestNpcDetail(State.key, math.min(State.variation, #State.models))
        end
    end
    _G.NobleNextCustomNpc.OnModelChangeFailed = function(payload)
        if State.closed or not State.modelPending or type(payload) ~= "table"
            or payload.requestId ~= State.modelRequest or tostring(payload.key) ~= tostring(State.key) then return end
        State.modelPending = false
        if payload.operation == "remove" then
            State.detailReady = false
            State.refreshModelDetail = true
            RequestModelList()
        end
        UpdateModelsVisibility()
        SetStatus(false, payload.message or "Не удалось изменить образ.")
    end
    _G.NobleNextCustomNpc.OnModelChanged = function(payload)
        if State.closed or not State.modelPending or type(payload) ~= "table"
            or payload.requestId ~= State.modelRequest or tostring(payload.key) ~= tostring(State.key) then return end
        ClearFaceBrowser("Загрузка образа…")
        State.modelPending = false
        State.refreshModelDetail = false
        State.models = payload.models or {}
        State.modelCount = #State.models
        State.variation = tonumber(payload.variation) or 1
        State.detailReady = false
        if f.ModelList then f.ModelList:SetRows(State.models) end
        if f.ModelScroll and f.ModelScroll.SetVerticalScroll then
            f.ModelScroll:SetVerticalScroll(math.max(0, State.variation * MODEL_ROW_HEIGHT + 8 - f.ModelScroll:GetHeight()))
        end
        UpdateContext()
        UpdateModelsVisibility()
        SetStatus(true, payload.operation == "remove" and "Образ удалён. Загружается выбранный оставшийся образ."
            or ("Добавлен образ " .. tostring(State.variation) .. ". Откройте «Внешность» или «Снаряжение», чтобы изменить его."))
    end
    _G.NobleNextCustomNpc.OnCatalog = function(catalog)
        State.races = (catalog and catalog.races) or {}
        if f.RaceDropdown then
            local label = FormatRaceLabel(State.raceId, nil)
            for _, race in ipairs(State.races) do
                if tonumber(race.raceId) == tonumber(State.raceId) then
                    label = FormatRaceLabel(race.raceId, race.name)
                    break
                end
            end
            SelectDropdownValue(f.RaceDropdown, State.raceId, label)
        end
        SetStatus(true, "Доступные расы обновлены.")
    end

    -- Header / context
    local Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    Title:SetText("Мои НИПы")
    Title:SetTextColor(ns.COLORS.goldRaw.r, ns.COLORS.goldRaw.g, ns.COLORS.goldRaw.b)
    Title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -8)

    f.ContextText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.ContextText:SetPoint("TOPLEFT", Title, "BOTTOMLEFT", 0, -4)
    f.ContextText:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.ContextText:SetJustifyH("LEFT")
    f.ContextText:SetWordWrap(false)
    f.ContextText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12)
    f.ContextText:SetText("Активный: -")

    f.RefreshAppearance = ns.CreateNGButton(f, "Обновить образ в мире", 182, 24)
    f.RefreshAppearance:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -6)
    f.RefreshAppearance:SetScript("OnClick", function() RunEditorAction("WorldAction", "refresh") end)
    LookApplyButtons[#LookApplyButtons + 1] = f.RefreshAppearance
    f.RefreshDetails = ns.CreateNGButton(f, "Обновить данные", 130, 24)
    f.RefreshDetails:SetPoint("RIGHT", f.RefreshAppearance, "LEFT", -6, 0)
    f.RefreshDetails:SetScript("OnClick", function()
        if not State.key or State.closed or State.modelPending or State.facePending or State.editorPending then return end
        RequestNpcDetail()
        UpdateModelsVisibility()
    end)

    f.StatusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.StatusText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
    f.StatusText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 8)
    f.StatusText:SetJustifyH("LEFT")
    f.StatusText:SetWordWrap(false)
    f.StatusText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12)
    SetStatus(nil, "Готово.")

    -- Tabs
    local Tabs = {}
    local TabButtons = {}
    ShowTab = function(name)
        if State.activeTab == "look" and name ~= "look" then
            local wasApplying = State.facePending ~= nil
            ClearFaceBrowser()
            if wasApplying then
                State.detailReady = false
                RequestNpcDetail()
            end
            UpdateModelsVisibility()
        end
        State.activeTab = name
        for tabName, tab in pairs(Tabs) do
            tab:SetShown(tabName == name)
        end
        for _, btn in ipairs(TabButtons) do
            ns.SetNGTabSelected(btn, btn.tabName == name)
        end
        if name == "look" then
            LoadCatalogModule()
            if f.RaceDropdown then f.RaceDropdown:GenerateMenu() end
            RequestFaceBrowser()
        end
        if name ~= "catalog" and name ~= "create" and State.key and not State.detailReady
            and not State.modelPending and not State.facePending and not State.editorPending then RequestNpcDetail() end
    end
    local function CreateTabButton(text, tabName, x)
        local btn = ns.CreateNGTab(f, text, tabName, function()
            ShowTab(tabName)
            if tabName == "catalog" and not State.listLoading then RefreshList() end
        end)
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

    local tabX = 12
    for _, tab in ipairs({ { "Каталог", "catalog" }, { "Создать", "create" }, { "Образы", "models" },
        { "Внешность", "look" }, { "Снаряжение", "gear" }, { "В мире", "service" } }) do
        local button = CreateTabButton(tab[1], tab[2], tabX)
        tabX = tabX + button:GetWidth() + 4
    end

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
    f.CreateBtn = CreateBtn
    CreateBtn:SetPoint("TOPLEFT", CreateSection, "TOPLEFT", 12, -132)
    CreateBtn:SetScript("OnClick", function()
        if State.pendingSelectName then return end
        local displayName = Trim(DisplayNameBox:GetText())
        if displayName == "" then
            SetStatus(false, "Укажите отображаемое имя.")
            return
        end
        local subName = Trim(CreateSubBox:GetText())
        State.key = nil
        State.name = displayName
        State.detailReady = false
        State.canEdit = false
        State.models = {}
        if f.ModelList then f.ModelList:SetRows({}) end
        SetLookApplyEnabled(false, "Дождитесь создания НИПа.")
        UpdateContext()
        UpdateModelsVisibility()
        State.pendingSelectName = displayName
        State.createRequest = State.createRequest + 1
        local request = State.createRequest
        State.listOffset = 0
        State.showAll = false
        CreateBtn:SetEnabled(false)
        SetStatus(nil, "Создание НИПа…")
        local sent
        if State.createMode == "blank" then
            sent = AioCall("CreateBlank", displayName, subName)
        elseif State.createMode == "target" then
            sent = AioCall("CloneTarget", displayName, subName)
        else
            sent = AioCall("CloneSelf", displayName, subName)
        end
        if not sent then
            State.pendingSelectName = nil
            CreateBtn:SetEnabled(true)
        else
            C_Timer.After(15, function()
                if State.createRequest ~= request or not State.pendingSelectName then return end
                State.pendingSelectName = nil
                CreateBtn:SetEnabled(true)
                RefreshList()
                SetStatus(false, "Ответ не получен. Проверьте каталог перед повторным созданием НИПа.")
            end)
        end
    end)

    local TempHint = CreateSection:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    TempHint:SetPoint("TOPLEFT", CreateBtn, "BOTTOMLEFT", 0, -10)
    TempHint:SetPoint("RIGHT", CreateSection, "RIGHT", -12, 0)
    TempHint:SetJustifyH("LEFT")
    TempHint:SetText("После создания откроются образы НИПа. Каждый можно скопировать и изменить отдельно.")

    ------------------------------------------------------------------
    -- Tab: Catalog
    ------------------------------------------------------------------
    local CatalogTab = CreateTabFrame("catalog")
    local SearchLabel = ns.CreateNGLabel(CatalogTab, "Поиск на странице:")
    SearchLabel:SetPoint("TOPLEFT", CatalogTab, "TOPLEFT", 4, -8)
    local SearchBox = ns.CreateNGEditBox(CatalogTab, "CustomNpc_Search", 180, 22)
    f.SearchBox = SearchBox
    SearchBox:SetPoint("TOPLEFT", CatalogTab, "TOPLEFT", 130, -4)
    SearchBox:SetScript("OnTextChanged", function(self)
        State.filter = self:GetText() or ""
        RenderNpcList()
    end)

    local RefreshBtn = ns.CreateNGButton(CatalogTab, "Обновить", 90, 22)
    RefreshBtn:SetPoint("LEFT", SearchBox, "RIGHT", 8, 0)
    RefreshBtn:SetScript("OnClick", RefreshList)

    f.MyNpcButton = ns.CreateNGTab(CatalogTab, "Мои НИПы", "mine", function()
        State.showAll = false
        State.listOffset = 0
        RefreshList()
    end)
    f.MyNpcButton:SetPoint("TOPLEFT", CatalogTab, "TOPLEFT", 4, -34)
    f.AllNpcButton = ns.CreateNGTab(CatalogTab, "Все НИПы", "all", function()
        State.showAll = true
        State.listOffset = 0
        RefreshList()
    end)
    f.AllNpcButton:SetPoint("LEFT", f.MyNpcButton, "RIGHT", 6, 0)
    f.AllNpcButton:Hide()

    f.CountText = CatalogTab:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.CountText:SetPoint("BOTTOMLEFT", CatalogTab, "BOTTOMLEFT", 4, 10)
    f.CountText:SetText("Показано: 0")

    f.PreviousPage = ns.CreateNGButton(CatalogTab, "Назад", 80, 22)
    f.NextPage = ns.CreateNGButton(CatalogTab, "Далее", 80, 22)
    f.NextPage:SetPoint("BOTTOMRIGHT", CatalogTab, "BOTTOMRIGHT", -4, 4)
    f.PreviousPage:SetPoint("RIGHT", f.NextPage, "LEFT", -6, 0)
    f.PreviousPage:SetScript("OnClick", function()
        if State.listLoading or State.listOffset == 0 then return end
        State.listOffset = math.max(0, State.listOffset - State.listLimit)
        RefreshList()
    end)
    f.NextPage:SetScript("OnClick", function()
        if State.listLoading or not State.hasMore then return end
        State.listOffset = State.listOffset + State.listLimit
        RefreshList()
    end)

    local listHost = CreateFrame("Frame", nil, CatalogTab)
    listHost:SetPoint("TOPLEFT", CatalogTab, "TOPLEFT", 4, -66)
    listHost:SetPoint("BOTTOMRIGHT", CatalogTab, "BOTTOMRIGHT", -4, 36)
    local scroll = NNL.Scroll.CreateFrame(listHost)
    scroll:SetPoint("TOPLEFT", listHost, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", listHost, "BOTTOMRIGHT", -22, 0)
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(560, 400)
    scroll:SetScrollChild(scrollChild)
    scroll:HookScript("OnSizeChanged", function(_, width)
        if width and width > 0 then scrollChild:SetWidth(width) end
    end)
    f.CatalogEmpty = listHost:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.CatalogEmpty:SetPoint("TOPLEFT", listHost, "TOPLEFT", 12, -16)
    f.CatalogEmpty:SetPoint("TOPRIGHT", listHost, "TOPRIGHT", -30, -16)
    f.CatalogEmpty:SetJustifyH("LEFT")

    f.NpcList = ns.VirtualList.Create(scrollChild, {
        width = 540,
        rowHeight = 44,
        visibleCount = 10,
        scrollFrame = scroll,
        onClick = function(row)
            SelectRow(row)
            ShowTab("models")
        end,
        renderRow = function(btn, row)
            local fs = btn.fs or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.fs = fs
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -3)
            fs:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -6, -3)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 14)
            local mark = (State.key == row.key) and "|cffFFD100> |r" or ""
            fs:SetText(mark .. (row.name or "?") .. "  |cffaaaaaa" .. (row.key or "") .. "|r")

            local sub = btn.sub or btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            btn.sub = sub
            sub:ClearAllPoints()
            sub:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 6, 3)
            sub:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -6, 3)
            sub:SetJustifyH("LEFT")
            sub:SetWordWrap(false)
            sub:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12)
            sub:SetText(string.format("ID %s | образов: %s | в мире: %s | %s",
                tostring(row.entry or "-"),
                tostring(row.models or "-"),
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
    -- Tab: Models
    ------------------------------------------------------------------
    local ModelsTab = CreateTabFrame("models")
    local Models = ns.CreateNGSection(ModelsTab, "Образы выбранного НИПа", 620, 400)
    Models:SetPoint("TOPLEFT", ModelsTab, "TOPLEFT", 4, -4)
    Models:SetPoint("BOTTOMRIGHT", ModelsTab, "BOTTOMRIGHT", -4, 4)

    f.ModelsHint = Models:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.ModelsHint:SetPoint("TOPLEFT", Models, "TOPLEFT", 12, -28)
    f.ModelsHint:SetPoint("TOPRIGHT", Models, "TOPRIGHT", -12, -28)
    f.ModelsHint:SetJustifyH("LEFT")
    f.ModelsHint:SetWordWrap(false)
    f.ModelsHint:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 13)

    local previous
    for _, action in ipairs({
        { "Скопировать образ", "CopyModel", nil, 152 },
        { "От персонажа", "AddModel", "self", 120 },
        { "От цели", "AddModel", "target", 88 },
        { "Пустой образ", "AddModel", "blank", 104 },
    }) do
        local button = ns.CreateNGButton(Models, action[1], action[4], 24)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        else button:SetPoint("TOPLEFT", Models, "TOPLEFT", 12, -50) end
        local method, source = action[2], action[3]
        button:SetScript("OnClick", function() ChangeModel(method, source) end)
        ModelButtons[#ModelButtons + 1] = button
        previous = button
    end

    local modelHelp = Models:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    modelHelp:SetPoint("TOPLEFT", Models, "TOPLEFT", 12, -82)
    modelHelp:SetPoint("TOPRIGHT", Models, "TOPRIGHT", -12, -82)
    modelHelp:SetJustifyH("LEFT")
    modelHelp:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12)
    modelHelp:SetText("Выбор в списке нужен для редактирования. При новом спавне образ выбирается случайно.\nКопия сохраняет внешность и снаряжение, изменения копии не затрагивают оригинал.")

    local modelScroll = NNL.Scroll.CreateFrame(Models)
    f.ModelScroll = modelScroll
    modelScroll:SetPoint("TOPLEFT", Models, "TOPLEFT", 10, -116)
    modelScroll:SetPoint("BOTTOMRIGHT", Models, "BOTTOMRIGHT", -30, 48)
    local modelChild = CreateFrame("Frame", nil, modelScroll)
    modelChild:SetSize(560, 100)
    modelScroll:SetScrollChild(modelChild)
    modelScroll:HookScript("OnSizeChanged", function(_, width)
        if width and width > 0 then modelChild:SetWidth(width) end
    end)
    f.ModelEmpty = Models:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.ModelEmpty:SetPoint("TOPLEFT", modelScroll, "TOPLEFT", 8, -8)

    f.ModelList = ns.VirtualList.Create(modelChild, {
        width = 560,
        rowHeight = MODEL_ROW_HEIGHT,
        visibleCount = 6,
        scrollFrame = modelScroll,
        onClick = function(row) if row then SelectModel(row.variation) end end,
        renderRow = function(btn, row)
            local title = btn.fs or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.fs = title
            title:ClearAllPoints()
            title:SetPoint("TOPLEFT", btn, "TOPLEFT", 8, -6)
            title:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -8, -6)
            title:SetJustifyH("LEFT")
            title:SetWordWrap(false)
            title:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 14)
            local selected = State.variation == tonumber(row.variation)
            title:SetText((selected and "|cffFFD100> |r" or "") .. ModelLabel(row))
            local sub = btn.sub or btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            btn.sub = sub
            sub:ClearAllPoints()
            sub:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 8, 5)
            sub:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -8, 5)
            sub:SetJustifyH("LEFT")
            sub:SetWordWrap(false)
            sub:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12)
            sub:SetText(string.format("Модель: %s | масштаб: %s%s", tostring(row.displayId or "-"),
                tostring(row.scale or 1), selected and " | выбран для редактирования" or ""))
            if btn.SetBackdropBorderColor then
                if selected then btn:SetBackdropBorderColor(1, 0.82, 0, 1)
                else btn:SetBackdropBorderColor(0.25, 0.2, 0.1, 0.6) end
            end
        end,
    })
    local EditLook = ns.CreateNGButton(Models, "Изменить внешность", 160, 24)
    EditLook:SetPoint("BOTTOMLEFT", Models, "BOTTOMLEFT", 12, 12)
    EditLook:SetScript("OnClick", function() ShowTab("look") end)
    local EditGear = ns.CreateNGButton(Models, "Изменить снаряжение", 160, 24)
    EditGear:SetPoint("LEFT", EditLook, "RIGHT", 8, 0)
    EditGear:SetScript("OnClick", function() ShowTab("gear") end)
    ModelButtons[#ModelButtons + 1] = EditLook
    ModelButtons[#ModelButtons + 1] = EditGear

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
        LookBody:SetHeight(18 + Identity:GetHeight() + 8 + Body:GetHeight() + 8
            + Face:GetHeight() + 8 + Advanced:GetHeight() + 16)
    end

    f.EditGateHint = LookBody:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.EditGateHint:SetPoint("TOPLEFT", LookBody, "TOPLEFT", 8, -2)
    f.EditGateHint:SetPoint("TOPRIGHT", LookBody, "TOPRIGHT", -8, -2)
    f.EditGateHint:SetJustifyH("LEFT")
    f.EditGateHint:SetWordWrap(false)
    f.EditGateHint:SetText("Выберите шаблон во вкладке «Каталог».")

    Identity = ns.CreateNGSection(LookBody, "Имя НИПа и выбранный образ", 620, 126)
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
        local key = RequireEditable()
        local name = Trim(f.NameBox:GetText())
        if not key or name == "" then return end
        if not State.detailReady then
            SetStatus(false, "Дождитесь загрузки вида с сервера.")
            return
        end
        RunEditorAction("SetAppearance", "name", name)
    end)

    local SubLabel = ns.CreateNGLabel(Identity, "Подпись:")
    SubLabel:SetPoint("TOPLEFT", Identity, "TOPLEFT", 12, -58)
    f.SubNameBox = ns.CreateNGEditBox(Identity, "CustomNpc_SubName", 200, 22)
    f.SubNameBox:SetPoint("TOPLEFT", Identity, "TOPLEFT", 90, -58)
    local SetSubBtn = ns.CreateNGButton(Identity, "Применить подпись", 130, 22)
    SetSubBtn:SetPoint("TOPRIGHT", Identity, "TOPRIGHT", -12, -58)
    f.SubNameBox:SetPoint("RIGHT", SetSubBtn, "LEFT", -8, 0)
    SetSubBtn:SetScript("OnClick", function()
        local key = RequireEditable()
        local subName = Trim(f.SubNameBox:GetText())
        if not key or subName == "" then return end
        if not State.detailReady then
            SetStatus(false, "Дождитесь загрузки вида с сервера.")
            return
        end
        RunEditorAction("SetAppearance", "subname", subName)
    end)

    local VarLabel = ns.CreateNGLabel(Identity, "Образ:")
    VarLabel:SetPoint("TOPLEFT", Identity, "TOPLEFT", 12, -94)
    f.VariationDropdown = NNL.Widgets.CreateDropdown(Identity, { name = "NobleNextCnpcVariationDD", width = 220 })
    f.VariationDropdown:SetPoint("TOPLEFT", Identity, "TOPLEFT", 90, -90)
    InitSimpleDropdown(f.VariationDropdown, 220, function()
        local entries = {}
        for _, model in ipairs(State.models) do
            entries[#entries + 1] = { value = model.variation, label = ModelLabel(model) }
        end
        return entries
    end, SelectModel)
    local ManageModels = ns.CreateNGButton(Identity, "Все образы", 120, 22)
    ManageModels:SetPoint("TOPRIGHT", Identity, "TOPRIGHT", -12, -90)
    ManageModels:SetScript("OnClick", function() ShowTab("models") end)

    Body = ns.CreateNGSection(LookBody, "Раса и пол", 620, 100)
    Body:SetPoint("TOPLEFT", Identity, "BOTTOMLEFT", 0, -8)
    Body:SetPoint("TOPRIGHT", Identity, "BOTTOMRIGHT", 0, -8)

    local RaceLabel = ns.CreateNGLabel(Body, "Раса:")
    RaceLabel:SetPoint("TOPLEFT", Body, "TOPLEFT", 12, -32)
    f.RaceDropdown = NNL.Widgets.CreateDropdown(Body, { name = "NobleNextCnpcRaceDD", width = 200 })
    f.RaceDropdown:SetPoint("TOPLEFT", Body, "TOPLEFT", 66, -28)
    InitSimpleDropdown(f.RaceDropdown, 180, RaceEntries, function(value)
        if State.facePending then SetStatus(nil, "Дождитесь применения варианта.");return false end
        State.raceId = value
        PreviewFaceDraft()
    end)
    SelectDropdownValue(f.RaceDropdown, State.raceId, FormatRaceLabel(State.raceId, "Human"))

    local RaceApply = ns.CreateNGButton(Body, "Применить расу", 120, 22)
    RaceApply:SetPoint("TOPLEFT", Body, "TOPLEFT", 280, -30)
    RaceApply:SetScript("OnClick", function()
        local key = RequireEditable()
        if not key then return end
        if not State.detailReady then
            SetStatus(false, "Дождитесь загрузки вида с сервера.")
            return
        end
        local allowed = false
        for _, race in ipairs(RaceEntries()) do if race.value == State.raceId then allowed = true;break end end
        if not allowed then SetStatus(false, "Выберите доступную расу из списка.");return end
        RunEditorAction("SetAppearance", "race", State.raceId)
    end)

    local GenderLabel = ns.CreateNGLabel(Body, "Пол:")
    GenderLabel:SetPoint("TOPLEFT", Body, "TOPLEFT", 12, -70)
    f.GenderDropdown = NNL.Widgets.CreateDropdown(Body, { name = "NobleNextCnpcGenderDD", width = 120 })
    f.GenderDropdown:SetPoint("TOPLEFT", Body, "TOPLEFT", 66, -66)
    InitSimpleDropdown(f.GenderDropdown, 120, function()
        return GENDERS
    end, function(value)
        if State.facePending then SetStatus(nil, "Дождитесь применения варианта.");return false end
        State.gender = value
        PreviewFaceDraft()
    end)
    SelectDropdownValue(f.GenderDropdown, State.gender, "Мужской")

    local GenderApply = ns.CreateNGButton(Body, "Применить пол", 120, 22)
    GenderApply:SetPoint("TOPLEFT", Body, "TOPLEFT", 280, -68)
    GenderApply:SetScript("OnClick", function()
        local key = RequireEditable()
        if not key then return end
        if not State.detailReady then
            SetStatus(false, "Дождитесь загрузки вида с сервера.")
            return
        end
        if State.gender == nil then
            SetStatus(false, "Выберите пол.")
            return
        end
        RunEditorAction("SetAppearance", "gender", State.gender)
    end)

    local FaceBtn = ns.CreateNGButton(Body, "Лицо из себя", 120, 22)
    FaceBtn:SetPoint("TOPLEFT", Body, "TOPLEFT", 410, -30)
    FaceBtn:SetScript("OnClick", function()
        local key = RequireEditable()
        if not key then return end
        if not State.detailReady then
            SetStatus(false, "Дождитесь загрузки вида с сервера.")
            return
        end
        RunEditorAction("SetAppearance", "face_self")
    end)

    local GuildBtn = ns.CreateNGButton(Body, "Гильдия из себя", 120, 22)
    GuildBtn:SetPoint("TOPLEFT", Body, "TOPLEFT", 410, -68)
    GuildBtn:SetScript("OnClick", function()
        local key = RequireEditable()
        if not key then return end
        RunEditorAction("SetAppearance", "guild_self")
    end)

    ------------------------------------------------------------------
    -- Server IDs and lock state; legacy servers retain their explicit index mode.
    ------------------------------------------------------------------
    Face = ns.CreateNGSection(LookBody, "Настройки внешности", 620, 340)
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
    f.FaceHeader:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 14)
    f.FaceHeader:SetWordWrap(false)
    f.FaceHeader:SetText("Лицо недоступно.")

    f.FaceModeHint = Face:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.FaceModeHint:SetPoint("TOPLEFT", Face, "TOPLEFT", 12, -46)
    f.FaceModeHint:SetPoint("TOPRIGHT", Face, "TOPRIGHT", -12, -46)
    f.FaceModeHint:SetJustifyH("LEFT")
    f.FaceModeHint:SetWordWrap(true)
    f.FaceModeHint:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12)

    f.FaceListsHost = CreateFrame("Frame", nil, Face)
    f.FaceListsHost:SetPoint("TOPLEFT", Face, "TOPLEFT", 12, -116)
    f.FaceListsHost:SetPoint("BOTTOMRIGHT", Face, "BOTTOMRIGHT", -8, 42)
    f.FaceListsHost:Hide()

    f.FaceOptionDropdown = NNL.Widgets.CreateDropdown(Face, { width = 360, defaultText = "Выберите параметр" })
    f.FaceOptionDropdown:SetPoint("TOPLEFT", Face, "TOPLEFT", 12, -82)
    f.FaceOptionDropdown:SetPoint("TOPRIGHT", Face, "TOPRIGHT", -12, -82)
    InitSimpleDropdown(f.FaceOptionDropdown, 360, function()
        local entries = {}
        for _, row in ipairs(State.faceOptions) do
            local id = tonumber(State.faceUsesIds and row.optionId or row.index)
            entries[#entries + 1] = { value = id,
                label = FaceName(row) .. (State.faceUsesIds and " | ID " or " | номер ") .. tostring(id or "-") .. FaceAvailabilityLabel(row),
                tooltip = row.available == false and FaceLockReason(row.reason) or nil }
        end
        return entries
    end, function(value)
        if State.facePending or not State.detailReady or not State.isOutfit then return false end
        for _, row in ipairs(State.faceOptions) do
            if tonumber(State.faceUsesIds and row.optionId or row.index) == value then
                State.faceOptionIndex, State.faceOptionId = tonumber(row.index), tonumber(row.optionId)
                State.faceOptionName = FaceName(row)
                State.faceOptionAvailable = (State.faceUsesIds and row.available == true)
                    or (not State.faceUsesIds and row.available ~= false)
                if State.facePreview then ShowPreviewChoices(0)
                else RequestFaceChoices(value, 0) end
                return
            end
        end
        return false
    end)

    local chScroll = NNL.Scroll.CreateFrame(f.FaceListsHost)
    chScroll:SetPoint("TOPLEFT", f.FaceListsHost, "TOPLEFT", 0, 0)
    chScroll:SetPoint("BOTTOMRIGHT", f.FaceListsHost, "BOTTOMRIGHT", -22, 0)
    local chChild = CreateFrame("Frame", nil, chScroll)
    chChild:SetSize(560, 176)
    chScroll:SetScrollChild(chChild)
    chScroll:HookScript("OnSizeChanged", function(_, width)
        if width and width > 0 then chChild:SetWidth(width) end
    end)

    f.FaceChoiceList = ns.VirtualList.Create(chChild, {
        width = 560,
        rowHeight = 44,
        visibleCount = 4,
        scrollFrame = chScroll,
        onClick = function(row)
            if not row or State.faceLoading or State.facePending then return end
            if State.facePreview then
                SetStatus(nil, "Сначала примените выбранные расу и пол.")
                return
            end
            local key = RequireEditable()
            if not key or not State.isOutfit then return end
            if (State.faceUsesIds and row.available ~= true) or row.available == false or State.faceOptionAvailable == false then
                SetStatus(false, FaceLockReason(row.reason))
                return
            end
            local option = State.faceUsesIds and State.faceOptionId or State.faceOptionIndex
            local choice = tonumber(State.faceUsesIds and row.choiceId or row.index)
            if not option or not choice then return end
            local current = State.faceUsesIds and State.faceCurrentChoiceId or State.faceCurrentChoiceIndex
            if current == choice then SetStatus(nil, "Этот вариант уже выбран.");return end
            State.faceLoading = true
            SetStatus(nil, "Применение варианта…")
            if State.faceUsesIds then
                State.faceSerial = State.faceSerial + 1
                local request = State.faceSerial
                State.facePending = { requestId = request, optionId = option }
                UpdateModelsVisibility()
                if not AioCall("SetFaceById", key, option, choice, State.variation, request) then
                    State.facePending = nil
                    State.faceLoading = false
                    UpdateModelsVisibility()
                else
                    C_Timer.After(15, function()
                        if not State.facePending or State.facePending.requestId ~= request then return end
                        State.facePending = nil
                        State.faceLoading = false
                        UpdateModelsVisibility()
                        RequestFaceOptions()
                        SetStatus(false, "Ответ не получен. Настройки перечитываются с сервера; изменение не повторяется.")
                    end)
                end
            else
                if not AioCall("SetFace", key, option, choice, State.variation) then State.faceLoading = false end
            end
            RefreshFaceHeader()
        end,
        renderRow = function(btn, row)
            local colors = FaceSwatches(row)
            local textX = #colors > 0 and 42 or 8
            if not btn.swatchBorder then
                btn.swatchBorder = btn:CreateTexture(nil, "BACKGROUND")
                btn.swatchBorder:SetPoint("LEFT", btn, "LEFT", 8, 0)
                btn.swatchBorder:SetSize(26, 26)
                btn.swatchBorder:SetColorTexture(0.65, 0.65, 0.65, 1)
                btn.swatches = { btn:CreateTexture(nil, "ARTWORK"), btn:CreateTexture(nil, "ARTWORK") }
            end
            btn.swatchBorder:SetShown(#colors > 0)
            for index, texture in ipairs(btn.swatches) do
                local color = colors[index]
                texture:SetShown(color ~= nil)
                if color then
                    texture:ClearAllPoints()
                    texture:SetPoint("LEFT", btn.swatchBorder, "LEFT", 2 + (index - 1) * 11, 0)
                    texture:SetSize(#colors == 1 and 22 or 11, 22)
                    texture:SetColorTexture(color[1], color[2], color[3], 1)
                end
            end
            local fs = btn.fs or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.fs = fs
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", btn, "TOPLEFT", textX, -5)
            fs:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -8, -5)
            fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 14)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            local id = tonumber(State.faceUsesIds and row.choiceId or row.index)
            local selected = (State.faceUsesIds and State.faceCurrentChoiceId or State.faceCurrentChoiceIndex) == id
            fs:SetText((selected and "|cff00cc66[x] |r" or "") .. FaceName(row, true))
            fs:SetTextColor(row.available == false and 0.55 or 1, row.available == false and 0.55 or 1, row.available == false and 0.55 or 1)
            local sub = btn.sub or btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            btn.sub = sub
            sub:ClearAllPoints()
            sub:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", textX, 5)
            sub:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -8, 5)
            sub:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12)
            sub:SetJustifyH("LEFT")
            sub:SetWordWrap(false)
            sub:SetText((State.faceUsesIds and "ID " or "Номер ") .. tostring(id or "-")
                .. (#colors > 0 and (" | " .. colors[1][4] .. (#colors > 1 and " / " .. colors[2][4] or "")) or "")
                .. FaceAvailabilityLabel(row))
            SetFaceTooltip(btn, row, true)
            if btn.SetBackdropBorderColor then
                if selected then btn:SetBackdropBorderColor(0.2, 0.8, 0.4, 1)
                else btn:SetBackdropBorderColor(0.25, 0.2, 0.1, 0.6) end
            end
        end,
    })

    f.FaceRefresh = ns.CreateNGButton(Face, "Обновить", 84, 22)
    f.FaceRefresh:SetPoint("BOTTOMLEFT", Face, "BOTTOMLEFT", 12, 10)
    f.FaceRefresh:SetScript("OnClick", function()
        if State.facePending then return end
        if State.facePreview then LoadFaceCatalog(true) else RequestFaceOptions() end
    end)
    f.FacePageText = Face:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.FacePageText:SetPoint("LEFT", f.FaceRefresh, "RIGHT", 8, 0)
    f.FacePageText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12)
    f.FacePrevious = ns.CreateNGButton(Face, "Предыдущие", 100, 22)
    f.FaceNext = ns.CreateNGButton(Face, "Следующие", 100, 22)
    f.FaceNext:SetPoint("BOTTOMRIGHT", Face, "BOTTOMRIGHT", -12, 10)
    f.FacePrevious:SetPoint("RIGHT", f.FaceNext, "LEFT", -6, 0)
    f.FacePrevious:SetScript("OnClick", function()
        if State.faceUsesIds and State.faceChoiceOffset > 0 and not State.faceLoading and not State.facePending then
            if State.facePreview then ShowPreviewChoices(State.faceChoiceOffset - 100)
            else RequestFaceChoices(State.faceOptionId, math.max(0, State.faceChoiceOffset - 100)) end
        end
    end)
    f.FaceNext:SetScript("OnClick", function()
        if State.faceUsesIds and State.faceHasMore and not State.faceLoading and not State.facePending then
            if State.facePreview then ShowPreviewChoices(State.faceChoiceOffset + 100)
            else RequestFaceChoices(State.faceOptionId, State.faceChoiceOffset + 100) end
        end
    end)
    RefreshFaceHeader()

    Advanced = ns.CreateNGSection(LookBody, "Дополнительно", 620, 90)
    Advanced:SetPoint("TOPLEFT", Face, "BOTTOMLEFT", 0, -8)
    Advanced:SetPoint("TOPRIGHT", Face, "BOTTOMRIGHT", 0, -8)
    UpdateLookScrollHeight()
    UpdateFaceGate()

    local DisplayLabel = ns.CreateNGLabel(Advanced, "Модель (DisplayID):")
    DisplayLabel:SetPoint("TOPLEFT", Advanced, "TOPLEFT", 12, -30)
    f.DisplayBox = ns.CreateNGEditBox(Advanced, "CustomNpc_Display", 80, 22)
    f.DisplayBox:SetPoint("TOPLEFT", Advanced, "TOPLEFT", 170, -30)
    local DisplayBtn = ns.CreateNGButton(Advanced, "Задать", 70, 22)
    DisplayBtn:SetPoint("LEFT", f.DisplayBox, "RIGHT", 6, 0)
    DisplayBtn:SetScript("OnClick", function()
        local key = RequireEditable()
        local displayId = tonumber(Trim(f.DisplayBox:GetText()))
        if not key then return end
        if not displayId or displayId ~= math.floor(displayId) or displayId < 1 or displayId > 4294967295 then
            SetStatus(false, "Укажите положительный целый Display ID.");return
        end
        if not State.detailReady then
            SetStatus(false, "Дождитесь загрузки вида с сервера.")
            return
        end
        RunEditorAction("SetAppearance", "displayid", displayId)
    end)

    local ScaleLabel = ns.CreateNGLabel(Advanced, "Масштаб:")
    ScaleLabel:SetPoint("TOPLEFT", Advanced, "TOPLEFT", 12, -60)
    f.ScaleBox = ns.CreateNGEditBox(Advanced, "CustomNpc_Scale", 60, 22)
    f.ScaleBox:SetPoint("TOPLEFT", Advanced, "TOPLEFT", 170, -60)
    f.ScaleBox:SetText("1")
    local ScaleBtn = ns.CreateNGButton(Advanced, "Задать", 70, 22)
    ScaleBtn:SetPoint("LEFT", f.ScaleBox, "RIGHT", 6, 0)
    ScaleBtn:SetScript("OnClick", function()
        local key = RequireEditable()
        local scale = tonumber(Trim(f.ScaleBox:GetText()))
        if not key then return end
        if not scale or scale ~= scale or scale <= 0 or scale > 3.402823466e38 then
            SetStatus(false, "Масштаб должен быть положительным конечным числом.");return
        end
        if not State.detailReady then
            SetStatus(false, "Дождитесь загрузки вида с сервера.")
            return
        end
        RunEditorAction("SetAppearance", "scale", scale)
    end)

    LookApplyButtons[#LookApplyButtons + 1] = SetNameBtn
    LookApplyButtons[#LookApplyButtons + 1] = SetSubBtn
    LookApplyButtons[#LookApplyButtons + 1] = RaceApply
    LookApplyButtons[#LookApplyButtons + 1] = GenderApply
    LookApplyButtons[#LookApplyButtons + 1] = FaceBtn
    LookApplyButtons[#LookApplyButtons + 1] = DisplayBtn
    LookApplyButtons[#LookApplyButtons + 1] = ScaleBtn
    OutfitApplyButtons = {RaceApply, GenderApply, FaceBtn, GuildBtn}
    SetLookApplyEnabled(false, "Сначала выберите NPC — вид загрузится с сервера.")

    ------------------------------------------------------------------
    -- Tab: Gear
    ------------------------------------------------------------------
    local GearTab = CreateTabFrame("gear")
    local Gear = ns.CreateNGSection(GearTab, "Броня и оружие", 620, 258)
    Gear:SetPoint("TOPLEFT", GearTab, "TOPLEFT", 4, -4)
    Gear:SetPoint("TOPRIGHT", GearTab, "TOPRIGHT", -4, -4)

    local SlotLabel = ns.CreateNGLabel(Gear, "Часть брони:")
    SlotLabel:SetPoint("TOPLEFT", Gear, "TOPLEFT", 12, -30)
    f.SlotDropdown = NNL.Widgets.CreateDropdown(Gear, { name = "NobleNextCnpcSlotDD", width = 140 })
    f.SlotDropdown:SetPoint("TOPLEFT", Gear, "TOPLEFT", 116, -26)
    InitSimpleDropdown(f.SlotDropdown, 140, function()
        return ARMOR_SLOTS
    end, function(value)
        State.armorSlot = value
    end)
    SelectDropdownValue(f.SlotDropdown, State.armorSlot, "Голова")

    local SourceLabel = ns.CreateNGLabel(Gear, "Источник:")
    SourceLabel:SetPoint("TOPLEFT", Gear, "TOPLEFT", 300, -30)
    local sourceButtons = {}
    local function SetItemSource(mode)
        State.itemSource = mode
        for m, btn in pairs(sourceButtons) do
            ns.SetNGTabSelected(btn, m == mode)
        end
        if f.ItemBox then
            f.ItemBox:SetShown(mode == "item")
        end
        if f.ItemLabel then f.ItemLabel:SetShown(mode == "item") end
        if f.ItemSourceHint then f.ItemSourceHint:SetShown(mode == "self") end
    end
    local SelfSrc = ns.CreateNGTab(Gear, "С себя", "self", function() SetItemSource("self") end)
    SelfSrc:SetSize(80, 24)
    SelfSrc:SetPoint("TOPLEFT", Gear, "TOPLEFT", 370, -28)
    sourceButtons.self = SelfSrc
    local ItemSrc = ns.CreateNGTab(Gear, "Предмет", "item", function() SetItemSource("item") end)
    ItemSrc:SetSize(80, 24)
    ItemSrc:SetPoint("LEFT", SelfSrc, "RIGHT", 6, 0)
    sourceButtons.item = ItemSrc
    f.SourceSelfButton, f.SourceItemButton = SelfSrc, ItemSrc

    local ItemLabel = ns.CreateNGLabel(Gear, "Item ID / ссылка:")
    f.ItemLabel = ItemLabel
    ItemLabel:SetPoint("TOPLEFT", Gear, "TOPLEFT", 12, -68)
    f.ItemBox = ns.CreateNGEditBox(Gear, "CustomNpc_Item", 260, 22)
    f.ItemBox:SetPoint("TOPLEFT", Gear, "TOPLEFT", 132, -62)
    f.ItemBox:SetPoint("TOPRIGHT", Gear, "TOPRIGHT", -12, -62)
    f.ItemSourceHint = Gear:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.ItemSourceHint:SetPoint("TOPLEFT", Gear, "TOPLEFT", 12, -64)
    f.ItemSourceHint:SetPoint("TOPRIGHT", Gear, "TOPRIGHT", -12, -64)
    f.ItemSourceHint:SetJustifyH("LEFT")
    f.ItemSourceHint:SetText("Источник — видимые предметы вашего персонажа в соответствующих слотах.")
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
        local key = RequireEditable()
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
        RunEditorAction("SetEquipment", "equip", slot, item)
    end)

    local AllSelfBtn = ns.CreateNGButton(Gear, "Вся броня с себя", 140, 24)
    AllSelfBtn:SetPoint("LEFT", ArmorBtn, "RIGHT", 8, 0)
    AllSelfBtn:SetScript("OnClick", function()
        local key = RequireEditable()
        if not key then return end
        RunEditorAction("SetEquipment", "equip", "all", "self")
    end)

    local UnequipBtn = ns.CreateNGButton(Gear, "Снять слот", 100, 24)
    UnequipBtn:SetPoint("LEFT", AllSelfBtn, "RIGHT", 8, 0)
    UnequipBtn:SetScript("OnClick", function()
        local key = RequireEditable()
        if not key then return end
        local slot = State.armorSlot
        if not slot or slot == "all" then
            SetStatus(false, "Для снятия выберите конкретный слот (не «Все»).")
            return
        end
        RunEditorAction("SetEquipment", "unequip", slot)
    end)

    local RightBtn = ns.CreateNGButton(Gear, "В правую руку", 110, 24)
    RightBtn:SetPoint("TOPLEFT", Gear, "TOPLEFT", 12, -132)
    RightBtn:SetScript("OnClick", function()
        local key = RequireEditable()
        if not key then return end
        local item = ResolveArmorItemArg()
        if not item then SetStatus(false, "Укажите Item ID или ссылку на предмет.");return end
        RunEditorAction("SetEquipment", "equip", "right", item)
    end)
    local LeftBtn = ns.CreateNGButton(Gear, "В левую руку", 110, 24)
    LeftBtn:SetPoint("LEFT", RightBtn, "RIGHT", 8, 0)
    LeftBtn:SetScript("OnClick", function()
        local key = RequireEditable()
        if not key then return end
        local item = ResolveArmorItemArg()
        if not item then SetStatus(false, "Укажите Item ID или ссылку на предмет.");return end
        RunEditorAction("SetEquipment", "equip", "left", item)
    end)
    local UnequipR = ns.CreateNGButton(Gear, "Снять правую", 110, 24)
    UnequipR:SetPoint("LEFT", LeftBtn, "RIGHT", 8, 0)
    UnequipR:SetScript("OnClick", function()
        local key = RequireEditable()
        if not key then return end
        RunEditorAction("SetEquipment", "unequip", "right")
    end)
    local UnequipL = ns.CreateNGButton(Gear, "Снять левую", 110, 24)
    UnequipL:SetPoint("LEFT", UnequipR, "RIGHT", 8, 0)
    UnequipL:SetScript("OnClick", function()
        local key = RequireEditable()
        if not key then return end
        RunEditorAction("SetEquipment", "unequip", "left")
    end)

    f.GearGateHint = Gear:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.GearGateHint:SetPoint("TOPLEFT", Gear, "TOPLEFT", 12, -172)
    f.GearGateHint:SetPoint("TOPRIGHT", Gear, "TOPRIGHT", -12, -172)
    f.GearGateHint:SetJustifyH("LEFT")
    f.GearMakeOutfit = ns.CreateNGButton(Gear, "Добавить образ персонажа", 208, 24)
    f.GearMakeOutfit:SetPoint("BOTTOMLEFT", Gear, "BOTTOMLEFT", 12, 12)
    f.GearMakeOutfit:SetScript("OnClick", function() ChangeModel("AddModel", "self") end)
    UpdateGearGate = function()
        local enabled = State.key ~= nil and State.detailReady and State.canEdit
            and not State.modelPending and not State.facePending and not State.editorPending
        for _, button in ipairs({ArmorBtn, AllSelfBtn, UnequipBtn}) do button:SetEnabled(enabled and State.isOutfit) end
        f.GearMakeOutfit:SetShown(State.detailReady and not State.isOutfit)
        f.GearMakeOutfit:SetEnabled(enabled)
        f.GearGateHint:SetText(not State.detailReady and "Выберите NPC и дождитесь загрузки образа."
            or (State.isOutfit and "Изменения относятся к выбранному образу. После правки его можно обновить в мире кнопкой сверху."
            or "Готовая модель: доступно оружие, одежда встроена в модель. Для изменения одежды добавьте настраиваемый образ."))
    end

    ------------------------------------------------------------------
    -- Tab: Service
    ------------------------------------------------------------------
    local ServiceTab = CreateTabFrame("service")
    local Service = ns.CreateNGSection(ServiceTab, "Спавн и сервис", 620, 268)
    Service:SetPoint("TOPLEFT", ServiceTab, "TOPLEFT", 4, -4)
    Service:SetPoint("TOPRIGHT", ServiceTab, "TOPRIGHT", -4, -4)

    local TempSpawn = ns.CreateNGButton(Service, "Временный спавн", 140, 24)
    TempSpawn:SetPoint("TOPLEFT", Service, "TOPLEFT", 12, -30)
    TempSpawn:SetScript("OnClick", function()
        local key = RequireEditable()
        if not key then return end
        RunEditorAction("WorldAction", "temp")
    end)

    local PermSpawn = ns.CreateNGButton(Service, "Постоянный спавн", 140, 24)
    PermSpawn:SetPoint("LEFT", TempSpawn, "RIGHT", 8, 0)
    PermSpawn:SetScript("OnClick", function()
        local key = RequireEditable()
        if not key then return end
        if ns.Confirm and ns.Confirm.Show then
            ns.Confirm.Show({
                text = "Постоянный спавн NPC \"" .. key .. "\" в БД?",
                onAccept = function()
                    if State.key ~= key then SetStatus(false, "Выбран другой NPC. Повторите действие.");return end
                    RunEditorAction("WorldAction", "spawn")
                end,
            })
        else
            RunEditorAction("WorldAction", "spawn")
        end
    end)

    local ReloadBtn = ns.CreateNGButton(Service, "Перечитать из базы", 158, 24)
    ReloadBtn:SetPoint("TOPLEFT", Service, "TOPLEFT", 12, -68)
    ReloadBtn:SetScript("OnClick", function()
        local key = RequireEditable()
        if not key then return end
        RunEditorAction("WorldAction", "reload")
    end)

    local RefreshBtn2 = ns.CreateNGButton(Service, "Обновить все образы", 170, 24)
    RefreshBtn2:SetPoint("LEFT", ReloadBtn, "RIGHT", 8, 0)
    RefreshBtn2:SetScript("OnClick", function()
        local key = RequireEditable()
        if not key then return end
        RunEditorAction("WorldAction", "refresh_all")
    end)

    local ApplyBtn = ns.CreateNGButton(Service, "Применить к выбранному в мире", 220, 24)
    ApplyBtn:SetPoint("TOPLEFT", Service, "TOPLEFT", 12, -106)
    ApplyBtn:SetScript("OnClick", function()
        RunEditorAction("WorldAction", "apply")
    end)

    local CatalogBtn = ns.CreateNGButton(Service, "Загрузить каталог рас", 160, 24)
    CatalogBtn:SetPoint("LEFT", ApplyBtn, "RIGHT", 8, 0)
    CatalogBtn:SetScript("OnClick", RefreshCatalog)

    local DeleteBtn = ns.CreateNGButton(Service, "Удалить NPC", 120, 24)
    DeleteBtn:SetPoint("TOPLEFT", Service, "TOPLEFT", 12, -144)
    DeleteBtn:SetScript("OnClick", function()
        local key = RequireEditable()
        if not key then return end
        if ns.Confirm and ns.Confirm.Show then
            ns.Confirm.Show({
                text = "Удалить custom NPC \"" .. key .. "\"?\nБудет отправлено: .cnpc delete " .. key,
                onAccept = function()
                    if State.key ~= key then SetStatus(false, "Выбран другой NPC. Повторите удаление.");return end
                    RunEditorAction("WorldAction", "delete")
                end,
            })
        else
            SetStatus(false, "Подтверждение удаления недоступно. Откройте окно повторно.")
        end
    end)

    local HelpBtn = ns.CreateNGButton(Service, "Справка", 70, 24)
    HelpBtn:SetPoint("LEFT", DeleteBtn, "RIGHT", 8, 0)
    HelpBtn:SetScript("OnClick", function()
        SendCNPCommand(".cnpc help")
    end)

    local RemoveVarBtn = ns.CreateNGButton(Service, "Удалить образ", 130, 24)
    RemoveVarBtn:SetPoint("LEFT", HelpBtn, "RIGHT", 8, 0)
    RemoveVarBtn:SetScript("OnClick", function()
        local key = RequireEditable()
        local variation = tonumber(State.variation)
        if not key or not variation or variation < 2 then
            SetStatus(false, "Основной образ удалить нельзя. Выберите дополнительный образ.")
            return
        end
        if ns.Confirm and ns.Confirm.Show then
            ns.Confirm.Show({
                text = "Удалить образ " .. tostring(variation) .. " НИПа «" .. (State.name or key) .. "»? Оставшиеся образы будут перенумерованы.",
                onAccept = function()
                    if State.key ~= key or State.variation ~= variation then
                        SetStatus(false, "Выбран другой образ. Повторите удаление для нужного образа.")
                        return
                    end
                    ChangeModel("RemoveModel")
                end,
            })
        else
            SetStatus(false, "Подтверждение удаления недоступно. Откройте окно повторно.")
        end
    end)

    local WorldHint = Service:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    WorldHint:SetPoint("TOPLEFT", Service, "TOPLEFT", 12, -184)
    WorldHint:SetPoint("TOPRIGHT", Service, "TOPRIGHT", -12, -184)
    WorldHint:SetJustifyH("LEFT")
    WorldHint:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12)
    WorldHint:SetText("Кнопка сверху обновляет выбранный образ у всех использующих его NPC в мире. «Все образы» обновляет весь выбранный шаблон.\n«Из базы» загружает опубликованные изменения сайта. Применение работает с NPC, выбранным командой .npc select.")
    for _, button in ipairs({ GuildBtn, ArmorBtn, AllSelfBtn, UnequipBtn, RightBtn, LeftBtn, UnequipR, UnequipL,
        TempSpawn, PermSpawn, ReloadBtn, RefreshBtn2, ApplyBtn, DeleteBtn, RemoveVarBtn }) do
        LookApplyButtons[#LookApplyButtons + 1] = button
    end

    f:HookScript("OnShow", function()
        State.closed = false
        UpdateContext()
        RefreshList()
        RefreshCatalog()
        if State.key then
            if State.refreshModelDetail then RequestModelList()
            else RequestNpcDetail(State.key, State.variation) end
        end
    end)
    f:HookScript("OnHide", function()
        State.closed = true
        State.editorPending = nil
        State.refreshModelDetail = State.refreshModelDetail or State.modelPending
        State.modelPending = false
        State.modelRequest = State.modelRequest + 1
        State.detailRequest = (State.detailRequest or 0) + 1
        ClearFaceBrowser("Окно закрыто.")
        UpdateModelsVisibility()
    end)

    UpdateContext()
    UpdateModelsVisibility()
    ShowTab("catalog")
    return f
end

local function ShowCustomNpc()
    ns.ShowModule("Custom NPC")
end

C_Timer.After(0, function()
    ns.RegisterSlashCommand("NNCUSTOMNPC", ShowCustomNpc, { "nncustomnpc", "nncnpc" })
end)

ns.RegisterModule("Custom NPC", InitCustomNpcModule, "Создание и настройка custom NPC")
