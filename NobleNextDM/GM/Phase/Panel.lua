-- Loaded through the NobleNextDM private extension namespace.
-- GM/Phase/Panel.lua — Codex logical RP World Maps без C_Epsilon.

local _, ns = ...

ns.PhasePanel = ns.PhasePanel or {}
local Panel = ns.PhasePanel
local P = ns.Phases

local Ui = {}
local selectedId = nil -- decimal string, never a Lua number
local activeTab = "available"
local activeDetailView = "overview"
local ROLE_NAMES = { viewer = "Гость", editor = "Редактор", builder = "Редактор", manager = "Управляющий", owner = "Владелец", none = "Нет доступа" }

local function scopeLabel(map)
    return (not map or map == "" or map == "global") and "Все карты" or ("Карта " .. tostring(map))
end

local function createScroll(parent)
    return ns.NNL.Scroll.CreateFrame(parent)
end

local function reflowMemberList(scroll, child, list)
    local function resize(self, width, height)
        width = width or self:GetWidth()
        height = height or self:GetHeight()
        if width and width > 20 then
            child:SetWidth(width)
            if list.SetViewport then list:SetViewport(width - 4, height) end
        end
    end
    scroll:HookScript("OnSizeChanged", resize)
    resize(scroll)
end

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function phaseId(value)
    value = tostring(value or "")
    if not value:match("^%d+$") then
        return nil
    end
    value = value:gsub("^0+", "")
    return value ~= "" and value or "0"
end

local function db()
    NobleNextCharDB = NobleNextCharDB or {}
    NobleNextCharDB.PhaseFavorites = NobleNextCharDB.PhaseFavorites or {}
    return NobleNextCharDB
end

local function favorite(id)
    return db().PhaseFavorites[id]
end

local CATALOG_ROW_H = 48

local function isPublicRow(row)
    return row and tostring(row.public) == "1"
end

-- Blizzard lock art: LockButton-*-Up (Buttons) with LFG/groupfinder fallbacks.
local function applyVisibilityLock(tex, isPublic)
    if not tex then
        return
    end
    tex:Show()
    tex:SetTexCoord(0, 1, 0, 1)
    if isPublic then
        tex:SetTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
        local path = tex.GetTexture and tex:GetTexture()
        if not path or path == 0 or path == "" then
            if tex.SetAtlas then
                tex:SetAtlas("groupfinder-icon-lock")
            else
                tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-LOCK")
            end
            tex:SetVertexColor(0.45, 0.88, 0.55, 1)
        else
            tex:SetVertexColor(0.55, 0.95, 0.65, 1)
        end
    else
        tex:SetTexture("Interface\\Buttons\\LockButton-Locked-Up")
        local path = tex.GetTexture and tex:GetTexture()
        if not path or path == 0 or path == "" then
            if tex.SetAtlas then
                tex:SetAtlas("groupfinder-icon-lock")
            else
                tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-LOCK")
            end
        end
        tex:SetVertexColor(1, 0.78, 0.28, 1)
    end
end

local function ensureCatalogRow(button)
    if button._nnPhaseRow then
        return button
    end
    button._nnPhaseRow = true

    local strip = button:CreateTexture(nil, "ARTWORK")
    strip:SetWidth(3)
    strip:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -3)
    strip:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 3)
    strip:SetColorTexture(0.75, 0.45, 0.35, 1)
    button.strip = strip

    local lock = button:CreateTexture(nil, "OVERLAY")
    lock:SetSize(22, 22)
    lock:SetPoint("RIGHT", button, "RIGHT", -6, 2)
    button.lockIcon = lock

    local vis = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    vis:SetPoint("TOP", lock, "BOTTOM", 0, -1)
    vis:SetJustifyH("CENTER")
    button.visBadge = vis

    local idText = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    idText:SetPoint("TOPRIGHT", button, "TOPRIGHT", -30, -5)
    idText:SetJustifyH("RIGHT")
    idText:SetTextColor(0.48, 0.48, 0.52)
    button.idText = idText

    local title = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", button, "TOPLEFT", 10, -5)
    title:SetPoint("RIGHT", idText, "LEFT", -4, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    button.title = title

    local meta = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    meta:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    meta:SetPoint("RIGHT", lock, "LEFT", -4, 0)
    meta:SetJustifyH("LEFT")
    meta:SetWordWrap(false)
    meta:SetTextColor(0.72, 0.72, 0.72)
    button.meta = meta

    -- Hide legacy two-line labels if VirtualList reused older buttons.
    if button.label then button.label:Hide() end
    if button.sub then button.sub:Hide() end
    return button
end

local function renderCatalogRow(button, row)
    ensureCatalogRow(button)
    local selected = selectedId == row.phase
    local pub = isPublicRow(row)
    local name = (row.name and row.name ~= "") and row.name or "без имени"
    local scope = scopeLabel(row.map)
    local owner = tostring(row.owner or "-")
    local role = tostring(row.role or "none")
    if role == "builder" then
        role = "editor"
    end

    if button.strip then
        if pub then
            button.strip:SetColorTexture(0.35, 0.72, 0.48, 1)
        else
            button.strip:SetColorTexture(0.82, 0.48, 0.32, 1)
        end
    end
    applyVisibilityLock(button.lockIcon, pub)
    if button.visBadge then
        if pub then
            button.visBadge:SetText("|cff70e08aпубл.|r")
        else
            button.visBadge:SetText("|cffffc85aприв.|r")
        end
    end

    button.idText:SetText("#" .. tostring(row.phase or "?"))
    if selected then
        button.title:SetText("|cffffd100" .. name .. "|r")
    else
        button.title:SetText("|cffffd76a" .. name .. "|r")
    end
    -- POI hover-card style: type / status | Organization
    local metaLine = string.format("%s / %s | Аккаунт: %s | %s",
        pub and "Открытая" or "Закрытая",
        scope,
        owner,
        ROLE_NAMES[role] or role)
    button.meta:SetText(metaLine)
    button._nnTipName = name
    button._nnTipMeta = metaLine
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self._nnTipName or "Фаза", 1, 0.82, 0)
        if self._nnTipMeta then
            GameTooltip:AddLine(self._nnTipMeta, 0.85, 0.85, 0.85, true)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    if button.SetBackdropColor then
        if selected then
            button:SetBackdropColor(0.22, 0.17, 0.08, 0.95)
            button:SetBackdropBorderColor(1, 0.82, 0, 0.85)
        else
            button:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
            button:SetBackdropBorderColor(0.25, 0.20, 0.10, 0.6)
        end
    end
end

local function setStatus(text, isError)
    if not Ui.status then
        return
    end
    Ui.status:SetText(text or "-")
    Ui.status:SetTextColor(isError and 1 or 0.7, isError and 0.38 or 0.85, isError and 0.38 or 0.7, 1)
end

local function roleBadge(role)
    role = tostring(role or "none")
    if role == "builder" then
        role = "editor"
    end
    local colors = {
        viewer = "|cff9eb6d8",
        editor = "|cff75d98b",
        builder = "|cff75d98b", -- legacy alias until protocol migrates
        manager = "|cffffd76a",
        owner = "|cffffa8e6",
        none = "|cffaaaaaa",
    }
    return (colors[role] or "|cffaaaaaa") .. (ROLE_NAMES[role] or role) .. "|r"
end

local function selectedDetail()
    return selectedId and P.State.details[selectedId] or nil
end

local function selectedInfo()
    local detail = selectedDetail()
    return detail and detail.info or nil
end

local function rowCapabilities(row)
    return {
        role = row.role or "none",
        staff = row.staff == "1",
        canEnter = row.can_enter == "1",
        canManage = row.can_manage == "1",
        canArchive = row.can_archive == "1",
    }
end

local function isCurrentSelected()
    return selectedId and P.State.current and selectedId == P.State.current.phase
end

local function canOpenPhaseDialog(info)
    info = info or selectedInfo()
    if not info then
        return false
    end
    return info.can_rename == "1"
        or info.can_set_public == "1"
        or info.can_set_owner == "1"
        or info.can_archive == "1"
        or info.can_unarchive == "1"
        or info.can_own == "1"
end

local function canOpenMembersDialog(info)
    info = info or selectedInfo()
    if not info then
        return false
    end
    return info.can_invite == "1"
        or info.can_set_role == "1"
        or info.can_revoke == "1"
        or info.can_manage == "1"
end

local function isFavorite(id)
    return favorite(id) ~= nil
end

local function matchesSearch(row, text)
    text = trim(text):lower()
    if text == "" then
        return true
    end
    local saved = favorite(row.phase)
    local tags = saved and tostring(saved.tags or ""):lower() or ""
    local haystack = table.concat({
        tostring(row.phase or ""):lower(),
        tostring(row.name or ""):lower(),
        tostring(row.map or "global"):lower(),
        tostring(row.owner or ""):lower(),
        tostring(row.public == "1" and "public" or "private"),
        tags,
    }, " ")
    return haystack:find(text, 1, true) ~= nil
end

local function rowsForTab()
    local result = {}
    local search = Ui.search and Ui.search:GetText() or ""
    for _, row in ipairs(P.State.list or {}) do
        local id = phaseId(row.phase)
        if id then
            row.phase = id
            local caps = rowCapabilities(row)
            local show = false
            if activeTab == "available" then
                -- Server LIST already applies discovery ACL; enter button uses can_enter only.
                show = caps.canEnter or caps.staff or caps.role ~= "none" or row.public == "1"
            elseif activeTab == "managed" then
                show = caps.canManage or caps.canArchive
            elseif activeTab == "owned" then
                -- Account owner (effective role), not mere manager membership.
                show = tostring(caps.role or ""):lower() == "owner"
            elseif activeTab == "favorites" then
                show = isFavorite(id)
            end
            if show and matchesSearch(row, search) then
                result[#result + 1] = row
            end
        end
    end
    return result
end

local function updateListStatus(receivedCount, shownCount, isError, errorText)
    if isError then
        setStatus(errorText or "Ошибка списка.", true)
        return
    end
    setStatus(string.format("Список: получено %d / показано %d.", receivedCount or 0, shownCount or 0))
end

local function refreshCreateVisibility()
    local caps = P.State.caps
    local canCreate = caps and caps.can_create == "1"
    if Ui.createFrame then
        Ui.createFrame:SetShown(canCreate == true)
    end
    if Ui.layoutLeftColumn then
        Ui.layoutLeftColumn()
    end
end

local function updateDetails()
    local info = selectedInfo()
    if Ui.tags and Ui.detailLoadedId ~= selectedId then
        Ui.tags:SetText((selectedId and favorite(selectedId) or {}).tags or "")
        Ui.detailLoadedId = selectedId
    end
    if not info then
        for _, control in ipairs({ Ui.enter, Ui.gotoBtn, Ui.favorite, Ui.archive, Ui.phaseManageBtn, Ui.membersManageBtn }) do
            control:SetEnabled(false)
        end
    end
    if Ui.detailEmpty then
        Ui.detailEmpty:SetShown(not selectedId)
    end
    if Ui.detailCard then
        Ui.detailCard:SetShown(selectedId ~= nil)
    end
    if Ui.refreshDetailView then Ui.refreshDetailView() end

    if not selectedId then
        if Ui.detailEmpty then
            Ui.detailEmpty:SetText("Выберите фазу в каталоге, чтобы увидеть описание, участников и доступные действия.")
        end
        if Ui.memberList then
            Ui.memberList:SetRows({})
        end
        return
    end

    if not info then
        if Ui.cardTitle then
            Ui.cardTitle:SetText("Загрузка #" .. selectedId .. "...")
        end
        if Ui.cardMeta then
            Ui.cardMeta:SetText("Получаем описание и права доступа...")
        end
        if Ui.cardBody then
            Ui.cardBody:SetText("")
        end
        return
    end

    local detail = selectedDetail()
    local members = detail and detail.members or {}
    local contextRole = info.role or (isCurrentSelected() and (P.State.current.role or "viewer")) or "none"
    local state = info.archived == "1" and "архив" or (info.enabled == "1" and "активна" or "выключена")
    local scope = scopeLabel(info.map)
    local pub = info.public == "1"
    local name = (info.name and info.name ~= "") and info.name or "Без имени"

    if Ui.cardLock then
        applyVisibilityLock(Ui.cardLock, pub)
    end
    if Ui.cardVis then
        Ui.cardVis:SetText(pub and "|cff70e08aПубличная|r" or "|cffffc85aПриватная|r")
    end
    if Ui.cardTitle then
        Ui.cardTitle:SetText(name)
    end
    if Ui.cardId then
        Ui.cardId:SetText("#" .. selectedId)
    end
    if Ui.cardMeta then
        Ui.cardMeta:SetText(string.format("%s / %s | Аккаунт: %s",
            pub and "Публичная" or "Приватная",
            scope,
            tostring(info.owner or info.owner_account or "-")))
        Ui.cardMeta:SetWordWrap(true)
    end
    if Ui.cardBody then
        local body = {
            "Статус: " .. state
                .. "  |  Роль: " .. roleBadge(contextRole)
                .. (info.staff == "1" and "  |  |cff9eb6d8Мастер|r" or "")
                .. "  |  участников: " .. tostring(info.members or #members),
            "Описание: " .. ((info.description and info.description ~= "") and info.description or "|cff777777не задано|r"),
            "Точка входа: " .. ((info.spawn_set == "1")
                and ("карта " .. tostring(info.spawn_map or "?") .. (info.enter_spawn == "1" and " (при входе)" or ""))
                or "не задана"),
            "Права: вход=" .. (info.can_enter == "1" and "да" or "нет")
                .. "  телепорт=" .. (info.can_goto == "1" and "да" or "нет")
                .. "  участники=" .. (info.can_manage == "1" and "да" or "нет")
                .. "  владелец=" .. (info.can_own == "1" and "да" or "нет"),
    }
        Ui.cardBody:SetText(table.concat(body, "\n"))
        if Ui.cardBodyScroll then
            local h = Ui.cardBody:GetStringHeight() or 0
            Ui.cardBodyScroll:GetScrollChild():SetHeight(math.max(1, h + 8))
            Ui.cardBodyScroll:UpdateScrollChildRect()
            local max = math.max(0, h - (Ui.cardBodyScroll:GetHeight() or 0) + 8)
            if Ui.cardBodyScroll.SetVerticalScroll then
                Ui.cardBodyScroll:SetVerticalScroll(0)
            end
            if Ui.cardBodyScroll._nnMax then
                Ui.cardBodyScroll._nnMax = max
            end
        end
    end

    if Ui.memberList then
        Ui.memberList:SetRows(members)
    end
    if Ui.enter then
        Ui.enter:SetEnabled(info.can_enter == "1")
    end
    if Ui.gotoBtn then
        Ui.gotoBtn:SetEnabled(info.can_goto == "1")
    end
    if Ui.leave then
        Ui.leave:SetEnabled(P.State.current and P.State.current.phase ~= "0")
    end
    if Ui.favorite then
        Ui.favorite:SetEnabled(true)
        Ui.favorite:SetText(isFavorite(selectedId) and "Убрать" or "В избранное")
    end
    if Ui.archive then
        local archived = info.archived == "1"
        Ui.archive:SetText(archived and "Разархивировать" or "Архивировать")
        if archived then
            Ui.archive:SetEnabled(info.can_unarchive == "1")
        else
            Ui.archive:SetEnabled(info.can_archive == "1")
        end
    end
    if Ui.phaseManageBtn then
        Ui.phaseManageBtn:SetEnabled(canOpenPhaseDialog(info))
    end
    if Ui.membersManageBtn then
        Ui.membersManageBtn:SetEnabled(canOpenMembersDialog(info))
    end
end

local function refreshRows()
    if Ui.list then
        Ui.list:SetRows(rowsForTab())
        Ui.list:Refresh()
    end
    refreshCreateVisibility()
    updateDetails()
end

local function loadSelected(id)
    id = phaseId(id)
    if not id then
        return
    end
    selectedId = id
    if Ui.tags then Ui.tags:SetText((favorite(id) or {}).tags or "") end
    updateDetails()
    P.Get(id, function(ok, result)
        if not ok then
            setStatus("Данные фазы #" .. id .. " недоступна.", true)
            return
        end
        setStatus("Данные фазы #" .. id .. " обновлена.")
        updateDetails()
        refreshRows()
    end)
end

function Panel.OpenPhase(id)
    id = phaseId(id)
    if not id then
        return false
    end
    selectedId = id
    ns.ShowModule("RP Фазы")
    setStatus("Открываю фазу #" .. id .. "...")
    P.Get(id, function(ok, result)
        if not ok then
            selectedId = id
            updateDetails()
            setStatus("Фаза #" .. id .. " недоступна или удалена: "
                .. tostring((result and (result.detail or result.reason)) or "phase unavailable"), true)
            refreshRows()
            return
        end
        setStatus("Данные фазы #" .. id .. " обновлена.")
        updateDetails()
        refreshRows()
    end)
    return true
end

function Panel.EnterSelected()
    if not selectedId then
        return
    end
    setStatus("Вхожу в фазу #" .. selectedId .. "...")
    P.Enter(selectedId, function(ok, response)
        if not ok then
            setStatus("Вход отклонён сервером: " .. tostring(response.detail or response.reason or "ошибка"), true)
            return
        end
        setStatus("Активная фаза обновлена.")
        updateDetails()
    end)
end

function Panel.GotoSelected()
    if not selectedId then
        return
    end
    local info = selectedInfo()
    if info and info.can_goto ~= "1" then
        setStatus("Телепорт недоступен: не задана точка входа или нет доступа.", true)
        return
    end
    setStatus("Запрашиваю телепорт в фазу #" .. selectedId .. "...")
    P.Goto(selectedId, function(ok, response)
        if not ok then
            setStatus("Телепорт отклонён: " .. tostring(response.detail or response.reason or "ошибка"), true)
            return
        end
        setStatus("Телепорт выполнен.")
        updateDetails()
    end)
end

local function makePhaseLink(action, id, label)
    local registry = ns.ChatActions
    if registry and registry.MakeLink then
        -- AARRGGBB required; 6-digit colors break |c parsing and look like raw codes.
        return registry.MakeLink("phase", action, id, nil, label, "ff8bad4c")
    end
    return "#" .. tostring(id)
end

local function chatAddMessage(msg)
    local frame = DEFAULT_CHAT_FRAME or (ChatFrame1)
    if frame and frame.AddMessage then
        frame:AddMessage(msg)
        return true
    end
    if ns.Print then
        ns.Print(msg)
        return false
    end
    return false
end

function Panel.PrintSelectedLink()
    if not selectedId then
        return
    end
    local open = makePhaseLink("open", selectedId, "Открыть #" .. selectedId)
    local enter = makePhaseLink("enter", selectedId, "Войти")
    local gotoLink = makePhaseLink("goto", selectedId, "Телепорт")
    -- Local clickable addon links (ChatFrame interprets |H).
    chatAddMessage("|cffffd100[NobleNext]|r RP-фаза: " .. open .. " " .. enter .. " " .. gotoLink)
    -- Plain text that survives whisper / copy-paste to other players.
    local share = string.format(".rps phase enter %s", selectedId)
    local info = string.format(".rps phase info %s", selectedId)
    chatAddMessage("|cffaaaaaaПоделиться:|r " .. share .. "  |  " .. info)
    if ns.Util.InsertTextIntoChat(share) then
        setStatus("Команда подготовлена в строке чата; отправка — вручную.")
    else
        setStatus("Ссылка добавлена в журнал. Строка ввода чата сейчас недоступна.", true)
    end
end

local function syncFromServer()
    setStatus("Обновляем список фаз и доступные действия...")
    P.Sync(function(ok, response)
        refreshCreateVisibility()
        updateDetails()
        refreshRows()
        if not ok then
            local stage = response and response.stage or "?"
            local reason = response and (response.detail or response.reason) or "unknown"
            -- send_failed / addon send failed:* = клиент не отправил; timeout = нет ответа.
            updateListStatus(0, 0, true, "Не удалось обновить список [" .. tostring(stage) .. "]: " .. tostring(reason))
            if ns.PrintError then
                ns.PrintError("Не удалось обновить фазы [" .. tostring(stage) .. "]: " .. tostring(reason))
            end
            return
        end
        local received = #(P.State.list or {})
        local shown = #rowsForTab()
        updateListStatus(received, shown, false)
    end)
end

local function createPhaseFromForm()
    local name = Ui.createName and trim(Ui.createName:GetText()) or ""
    local description = Ui.createDesc and trim(Ui.createDesc:GetText()) or ""
    local mapText = Ui.createMap and trim(Ui.createMap:GetText()) or ""
    if name == "" then setStatus("Введите название фазы.", true); return end
    if #name > 96 or #description > 255 then
        setStatus("Название слишком длинное (до 96 байт) или описание превышает 255 байт.", true)
        return
    end
    if mapText ~= "" and (not mapText:match("^%d+$") or tonumber(mapText) > 4294967295) then
        setStatus("ID карты должен быть целым неотрицательным числом. Пустое поле: все карты.", true)
        return
    end
    local scope = "global"
    local mapId = nil
    if mapText ~= "" then
        scope = "map"
        mapId = mapText
    end
    setStatus("Создаю фазу...")
    P.Create(name, description, scope, mapId, function(ok, response)
        if not ok then
            setStatus("Создание отклонено: " .. tostring(response.detail or response.reason or "ошибка"), true)
            return
        end
        local createdId = response and phaseId(response.phase)
        setStatus(createdId and ("Фаза #" .. createdId .. " создана.") or "Фаза создана.")
        if Ui.createName then Ui.createName:SetText("") end
        if Ui.createDesc then Ui.createDesc:SetText("") end
        if Ui.createMap then Ui.createMap:SetText("") end
        P.List(function()
            refreshRows()
            if createdId then
                loadSelected(createdId)
            end
        end)
    end)
end

local function archiveSelected()
    if not selectedId then
        return
    end
    local id = selectedId
    local info = selectedInfo()
    local unarchive = info and info.archived == "1"
    local key = unarchive and "NOBLENEXT_PHASE_UNARCHIVE" or "NOBLENEXT_PHASE_ARCHIVE"
    StaticPopupDialogs[key] = {
        text = unarchive
            and string.format("Разархивировать RP-фазу #%s?", id)
            or string.format("Архивировать RP-фазу #%s?\nДанные сохранятся; фазу можно будет восстановить.", id),
        button1 = YES or "Да",
        button2 = NO or "Нет",
        OnAccept = function()
            setStatus((unarchive and "Разархивирую" or "Архивирую") .. " фазу #" .. id .. "...")
            local api = unarchive and P.Unarchive or P.Archive
            api(id, function(ok, response)
                if not ok then
                    setStatus((unarchive and "Unarchive" or "Архив") .. " отклонён: "
                        .. tostring(response.detail or response.reason or "ошибка"), true)
                    return
                end
                setStatus("Фаза #" .. id .. (unarchive and " разархивирована." or " архивирована."))
                syncFromServer()
            end)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show(key)
end

local function createDetailContent(host, name, minHeight)
    local scroll = createScroll(host)
    scroll:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -22, 0)
    local content = CreateFrame("Frame", name, scroll)
    content:SetSize(1, minHeight)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnSizeChanged", function(self, width, height)
        if width and width > 20 then content:SetWidth(width) end
        content:SetHeight(math.max(minHeight, height or self:GetHeight()))
    end)
    if scroll:GetWidth() > 20 then content:SetWidth(scroll:GetWidth()) end
    content:SetHeight(math.max(minHeight, scroll:GetHeight()))
    return content, scroll
end

local function initSimpleDropdown(dropdown, width, getEntries, onPick)
    UIDropDownMenu_SetWidth(dropdown, width)
    UIDropDownMenu_Initialize(dropdown, function()
        for _, entry in ipairs(getEntries() or {}) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.label
            info.value = entry.value
            info.func = function()
                onPick(entry.value, entry.label)
                UIDropDownMenu_SetSelectedValue(dropdown, entry.value)
                UIDropDownMenu_SetText(dropdown, entry.label)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
end

local PhaseDlg = { publicValue = "0", roleValue = "viewer" }
local MembersDlg = { roleValue = "viewer" }

local function ensurePhaseDialog()
    if PhaseDlg.frame then
        return PhaseDlg.frame
    end
    local f = createDetailContent(Ui.detailViews.settings, "NobleNextPhaseOwn", 340)
    PhaseDlg.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    PhaseDlg.title:SetPoint("TOPLEFT", 4, -4)
    PhaseDlg.title:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    PhaseDlg.title:SetWordWrap(false)
    PhaseDlg.title:SetTextColor(1, 0.82, 0)

    local nameLabel = ns.CreateNGLabel(f, "Имя:")
    nameLabel:SetPoint("TOPLEFT", 4, -28)
    PhaseDlg.nameBox = ns.CreateNGEditBox(f, "PhaseOwnName", 160, 22)
    PhaseDlg.nameBox:SetPoint("TOPLEFT", 4, -46)
    local saveName = ns.CreateNGButton(f, "Сохранить", 90, 22)
    saveName:SetPoint("TOPRIGHT", -4, -46)
    PhaseDlg.nameBox:SetPoint("RIGHT", saveName, "LEFT", -6, 0)
    saveName:SetScript("OnClick", function()
        local id = PhaseDlg.phaseId
        if not id then return end
        P.Rename(id, PhaseDlg.nameBox:GetText(), function(ok, response)
            if not ok then
                setStatus("Не удалось изменить название: " .. tostring(response.detail or response.reason), true)
                return
            end
            setStatus("Название фазы обновлено.")
            loadSelected(id)
            PhaseDlg.refresh()
        end)
    end)

    local pubLabel = ns.CreateNGLabel(f, "Публичность:")
    pubLabel:SetPoint("TOPLEFT", 4, -82)
    PhaseDlg.publicDD = CreateFrame("Frame", "NobleNextPhasePublicDD", f, "UIDropDownMenuTemplate")
    PhaseDlg.publicDD:SetPoint("TOPLEFT", -12, -96)
    UIDropDownMenu_SetWidth(PhaseDlg.publicDD, 140)
    initSimpleDropdown(PhaseDlg.publicDD, 140, function()
        return {
            { value = "0", label = "Приватная" },
            { value = "1", label = "Публичная" },
        }
    end, function(value)
        PhaseDlg.publicValue = value
    end)
    local applyPublic = ns.CreateNGButton(f, "Применить", 90, 22)
    applyPublic:SetPoint("TOPRIGHT", -4, -100)
    applyPublic:SetScript("OnClick", function()
        local id = PhaseDlg.phaseId
        if not id then return end
        P.SetPublic(id, PhaseDlg.publicValue == "1", function(ok, response)
            if not ok then
                setStatus("Не удалось изменить публичность: " .. tostring(response.detail or response.reason), true)
                return
            end
            setStatus("Публичность обновлена.")
            loadSelected(id)
            PhaseDlg.refresh()
        end)
    end)

    local ownerLabel = ns.CreateNGLabel(f, "Владелец (персонаж):")
    ownerLabel:SetPoint("TOPLEFT", 4, -136)
    PhaseDlg.ownerBox = ns.CreateNGEditBox(f, "PhaseOwnOwner", 160, 22)
    PhaseDlg.ownerBox:SetPoint("TOPLEFT", 4, -154)
    local transfer = ns.CreateNGButton(f, "Передать", 90, 22)
    transfer:SetPoint("TOPRIGHT", -4, -154)
    PhaseDlg.ownerBox:SetPoint("RIGHT", transfer, "LEFT", -6, 0)
    transfer:SetScript("OnClick", function()
        local id = PhaseDlg.phaseId
        local name = trim(PhaseDlg.ownerBox:GetText())
        if not id or name == "" then
            setStatus("Укажите имя персонажа нового владельца (0 = сервер).", true)
            return
        end
        StaticPopupDialogs["NOBLENEXT_PHASE_SET_OWNER"] = {
            text = string.format("Передать владение фазой #%s персонажу %s?", id, name),
            button1 = YES or "Да",
            button2 = NO or "Нет",
            OnAccept = function()
                P.SetOwner(id, name, function(ok, response)
                    if not ok then
                        setStatus("Не удалось передать владение: " .. tostring(response.detail or response.reason), true)
                        return
                    end
                    setStatus("Владелец изменён.")
                    loadSelected(id)
                    PhaseDlg.refresh()
                end)
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show("NOBLENEXT_PHASE_SET_OWNER")
    end)

    PhaseDlg.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    PhaseDlg.hint:SetPoint("TOPLEFT", 4, -186)
    PhaseDlg.hint:SetPoint("RIGHT", -4, 0)
    PhaseDlg.hint:SetJustifyH("LEFT")
    PhaseDlg.hint:SetWordWrap(true)
    PhaseDlg.hint:SetText("Введите имя персонажа нового владельца. Значение 0 передаёт фазу серверу. Передача требует подтверждения.")

    local descriptionLabel = ns.CreateNGLabel(f, "Описание")
    descriptionLabel:SetPoint("TOPLEFT", PhaseDlg.hint, "BOTTOMLEFT", 0, -14)
    PhaseDlg.description = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    PhaseDlg.description:SetPoint("TOPLEFT", descriptionLabel, "BOTTOMLEFT", 0, -6)
    PhaseDlg.description:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    PhaseDlg.description:SetJustifyH("LEFT")
    PhaseDlg.description:SetWordWrap(true)
    local descriptionHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    descriptionHint:SetPoint("TOPLEFT", PhaseDlg.description, "BOTTOMLEFT", 0, -8)
    descriptionHint:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    descriptionHint:SetJustifyH("LEFT")
    descriptionHint:SetWordWrap(true)
    descriptionHint:SetText("Описание задаётся при создании фазы. Здесь оно доступно только для просмотра.")
    local function reflowSettings()
        UIDropDownMenu_SetWidth(PhaseDlg.publicDD, math.max(60, f:GetWidth() - 122))
        f:SetHeight(math.max(340, 248 + PhaseDlg.hint:GetStringHeight()
            + PhaseDlg.description:GetStringHeight() + descriptionHint:GetStringHeight()))
    end
    f:HookScript("OnSizeChanged", reflowSettings)

    function PhaseDlg.refresh()
        local id = PhaseDlg.phaseId
        local info = id and P.State.details[id] and P.State.details[id].info
        PhaseDlg.title:SetText("Настройки фазы")
        PhaseDlg.nameBox:SetEnabled(info and info.can_rename == "1")
        saveName:SetEnabled(info and info.can_rename == "1")
        applyPublic:SetEnabled(info and info.can_set_public == "1")
        PhaseDlg.ownerBox:SetEnabled(info and info.can_set_owner == "1")
        transfer:SetEnabled(info and info.can_set_owner == "1")
        if info then
            if PhaseDlg.loadedId ~= id then PhaseDlg.ownerBox:SetText("") end
            PhaseDlg.loadedId = id
            PhaseDlg.nameBox:SetText(info.name or "")
            PhaseDlg.description:SetText(info.description and info.description ~= "" and info.description or "Описание не задано.")
            PhaseDlg.publicValue = info.public == "1" and "1" or "0"
            UIDropDownMenu_SetSelectedValue(PhaseDlg.publicDD, PhaseDlg.publicValue)
            UIDropDownMenu_SetText(PhaseDlg.publicDD, PhaseDlg.publicValue == "1" and "Публичная" or "Приватная")
            reflowSettings()
        end
    end

    PhaseDlg.frame = f
    f:Hide()
    return f
end

local function ensureMembersDialog()
    if MembersDlg.frame then
        return MembersDlg.frame
    end
    local f = createDetailContent(Ui.detailViews.rights, "NobleNextPhaseMembers", 350)
    MembersDlg.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    MembersDlg.title:SetPoint("TOPLEFT", 4, -4)
    MembersDlg.title:SetTextColor(1, 0.82, 0)

    local charLabel = ns.CreateNGLabel(f, "Персонаж:")
    charLabel:SetPoint("TOPLEFT", 4, -28)
    MembersDlg.charBox = ns.CreateNGEditBox(f, "PhaseMemberName", 130, 22)
    MembersDlg.charBox:SetPoint("TOPLEFT", 4, -46)
    MembersDlg.charBox:SetPoint("RIGHT", f, "RIGHT", -4, 0)

    local roleLabel = ns.CreateNGLabel(f, "Роль:")
    roleLabel:SetPoint("TOPLEFT", 4, -84)
    MembersDlg.roleDD = CreateFrame("Frame", "NobleNextPhaseRoleDD", f, "UIDropDownMenuTemplate")
    MembersDlg.roleDD:SetPoint("TOPLEFT", 40, -78)
    UIDropDownMenu_SetWidth(MembersDlg.roleDD, 100)
    initSimpleDropdown(MembersDlg.roleDD, 100, function()
        local info = MembersDlg.phaseId and P.State.details[MembersDlg.phaseId]
            and P.State.details[MembersDlg.phaseId].info
        local entries = {
            { value = "viewer", label = "Гость" },
            { value = "editor", label = "Редактор" },
        }
        if info and info.can_grant_manager == "1" then
            entries[#entries + 1] = { value = "manager", label = "Управляющий" }
        end
        return entries
    end, function(value)
        MembersDlg.roleValue = value
    end)

    local grant = ns.CreateNGButton(f, "Выдать", 70, 22)
    grant:SetPoint("TOPLEFT", 4, -112)
    grant:SetScript("OnClick", function()
        local id = MembersDlg.phaseId
        if not id then return end
        P.Invite(id, MembersDlg.charBox:GetText(), MembersDlg.roleValue or "viewer", function(ok, response)
            if not ok then
                setStatus("Не удалось выдать доступ: " .. tostring(response.detail or response.reason), true)
                return
            end
            setStatus("Доступ предоставлен.")
            loadSelected(id)
            MembersDlg.refresh()
        end)
    end)
    local revoke = ns.CreateNGButton(f, "Отозвать", 80, 22)
    revoke:SetPoint("LEFT", grant, "RIGHT", 4, 0)
    revoke:SetScript("OnClick", function()
        local id = MembersDlg.phaseId
        local charName = trim(MembersDlg.charBox:GetText())
        if not id or charName == "" then
            setStatus("Укажите или выберите персонажа.", true)
            return
        end
        StaticPopupDialogs["NOBLENEXT_PHASE_REVOKE"] = {
            text = string.format("Отозвать доступ у %s?", charName),
            button1 = YES or "Да",
            button2 = NO or "Нет",
            OnAccept = function()
                P.Revoke(id, charName, function(ok, response)
                    if not ok then
                        setStatus("Не удалось отозвать доступ: " .. tostring(response.detail or response.reason), true)
                        return
                    end
                    setStatus("Доступ отозван.")
                    loadSelected(id)
                    MembersDlg.refresh()
                end)
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show("NOBLENEXT_PHASE_REVOKE")
    end)
    local setRole = ns.CreateNGButton(f, "Сменить роль", 100, 22)
    setRole:SetPoint("TOPLEFT", grant, "BOTTOMLEFT", 0, -4)
    setRole:SetScript("OnClick", function()
        local id = MembersDlg.phaseId
        local charName = trim(MembersDlg.charBox:GetText())
        if not id or charName == "" then
            setStatus("Укажите или выберите персонажа.", true)
            return
        end
        P.SetRole(id, charName, MembersDlg.roleValue or "viewer", function(ok, response)
            if not ok then
                setStatus("Не удалось сменить роль: " .. tostring(response.detail or response.reason), true)
                return
            end
            setStatus("Роль обновлена.")
            loadSelected(id)
            MembersDlg.refresh()
        end)
    end)

    MembersDlg.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    MembersDlg.hint:SetPoint("TOPLEFT", 4, -170)
    MembersDlg.hint:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    MembersDlg.hint:SetJustifyH("LEFT")
    MembersDlg.hint:SetWordWrap(true)
    MembersDlg.hint:SetText("Выберите участника в списке или введите имя персонажа. Управляющий назначает гостей и редакторов; владелец — также управляющих.")
    local membersLabel = ns.CreateNGLabel(f, "Участники:")
    membersLabel:SetPoint("TOPLEFT", MembersDlg.hint, "BOTTOMLEFT", 0, -8)
    local listHost = CreateFrame("Frame", nil, f)
    listHost:SetPoint("TOPLEFT", membersLabel, "BOTTOMLEFT", 0, -6)
    listHost:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 10)
    local membersScroll = createScroll(listHost)
    membersScroll:SetPoint("TOPLEFT", listHost, "TOPLEFT", 0, 0)
    membersScroll:SetPoint("BOTTOMRIGHT", listHost, "BOTTOMRIGHT", -22, 0)
    local membersChild = CreateFrame("Frame", nil, membersScroll)
    membersChild:SetWidth(1)
    membersChild:SetHeight(24)
    membersScroll:SetScrollChild(membersChild)
    MembersDlg.list = ns.VirtualList.Create(membersChild, {
        width = 1,
        rowHeight = 22,
        visibleCount = 7,
        scrollFrame = membersScroll,
        onClick = function(row)
            if not row then return end
            local charName = (row.name and row.name ~= "") and row.name or nil
            if not charName then
                setStatus("Нет имени персонажа.", true)
                return
            end
            MembersDlg.charBox:SetText(charName)
            -- Dropdown grants ACL roles only; owner is account-level (shown in list badge).
            local role = tostring(row.acl_role or row.role or "viewer")
            if role == "builder" then role = "editor" end
            if role == "owner" then role = "manager" end
            local info = selectedInfo()
            if role == "manager" and not (info and info.can_grant_manager == "1") then role = "viewer" end
            MembersDlg.roleValue = role
            UIDropDownMenu_SetSelectedValue(MembersDlg.roleDD, role)
            UIDropDownMenu_SetText(MembersDlg.roleDD, ROLE_NAMES[role] or role)
        end,
        renderRow = function(button, row)
            local label = button.label or button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            button.label = label
            label:ClearAllPoints()
            label:SetPoint("LEFT", button, "LEFT", 4, 0)
            label:SetPoint("RIGHT", button, "RIGHT", -4, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            local charName = (row.name and row.name ~= "") and row.name or ("#" .. tostring(row.character or "?"))
            label:SetText(charName .. "  |  " .. roleBadge(row.role))
            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(charName, 1, 0.82, 0)
                if row.account and row.account ~= "" then
                    GameTooltip:AddLine("Аккаунт: " .. row.account, 0.7, 0.8, 0.9)
                end
                GameTooltip:AddLine("Роль: " .. (ROLE_NAMES[row.role] or tostring(row.role or "?")), 0.85, 0.85, 0.85)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", GameTooltip_Hide)
        end,
    })
    reflowMemberList(membersScroll, membersChild, MembersDlg.list)
    local function resizeActions()
        local width = math.max(1, (f:GetWidth() - 12) / 2)
        grant:SetWidth(width)
        revoke:SetWidth(width)
        setRole:SetWidth(math.max(1, f:GetWidth() - 8))
        UIDropDownMenu_SetWidth(MembersDlg.roleDD, math.max(60, f:GetWidth() - 86))
        local minHeight = 290 + MembersDlg.hint:GetStringHeight()
        if f:GetHeight() < minHeight then f:SetHeight(minHeight) end
    end
    f:HookScript("OnSizeChanged", resizeActions)
    resizeActions()

    function MembersDlg.refresh()
        local id = MembersDlg.phaseId
        local detail = id and P.State.details[id]
        local info = detail and detail.info
        local members = detail and detail.members or {}
        MembersDlg.title:SetText("Права участников")
        if MembersDlg.loadedId ~= id then MembersDlg.charBox:SetText("") end
        MembersDlg.loadedId = id
        if not info or (MembersDlg.roleValue == "manager" and info.can_grant_manager ~= "1") then
            MembersDlg.roleValue = "viewer"
        end
        initSimpleDropdown(MembersDlg.roleDD, 110, function()
            local entries = {
                { value = "viewer", label = "Гость" },
                { value = "editor", label = "Редактор" },
            }
            if info and info.can_grant_manager == "1" then
                entries[#entries + 1] = { value = "manager", label = "Управляющий" }
            end
            return entries
        end, function(value)
            MembersDlg.roleValue = value
        end)
        UIDropDownMenu_SetSelectedValue(MembersDlg.roleDD, MembersDlg.roleValue or "viewer")
        UIDropDownMenu_SetText(MembersDlg.roleDD, ROLE_NAMES[MembersDlg.roleValue or "viewer"])
        grant:SetEnabled(info and info.can_invite == "1")
        revoke:SetEnabled(info and info.can_revoke == "1")
        setRole:SetEnabled(info and info.can_set_role == "1")
        MembersDlg.charBox:SetEnabled(info and canOpenMembersDialog(info))
        resizeActions()
        if MembersDlg.list then
            MembersDlg.list:SetRows(members)
            MembersDlg.list:Refresh()
        end
    end

    MembersDlg.frame = f
    f:Hide()
    return f
end

local function showDetailView(view)
    if view == "settings" and not canOpenPhaseDialog() then view = "overview" end
    if view == "rights" and not canOpenMembersDialog() then view = "overview" end
    activeDetailView = view
    if view == "settings" then ensurePhaseDialog():Show() end
    if view == "rights" then ensureMembersDialog():Show() end
    for key, container in pairs(Ui.detailViews or {}) do
        container:SetShown(selectedInfo() ~= nil and key == view)
        ns.SetNGTabSelected(Ui.detailViewButtons[key], key == view)
    end
    if PhaseDlg.frame then
        PhaseDlg.phaseId = selectedId
        PhaseDlg.refresh()
    end
    if MembersDlg.frame then
        MembersDlg.phaseId = selectedId
        MembersDlg.refresh()
    end
end

function Panel.Init(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    title:SetText("RP-фазы")
    title:SetTextColor(ns.COLORS.goldRaw.r, ns.COLORS.goldRaw.g, ns.COLORS.goldRaw.b)

    local searchLabel = ns.CreateNGLabel(f, "Поиск:")
    searchLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -42)
    Ui.search = ns.CreateNGEditBox(f, "PhaseSearch", 180, 22)
    Ui.search:SetPoint("LEFT", searchLabel, "RIGHT", 6, 0)
    Ui.search:SetScript("OnTextChanged", function()
        refreshRows()
        local received = #(P.State.list or {})
        updateListStatus(received, #rowsForTab(), false)
    end)

    local clearSearch = ns.CreateNGButton(f, "X", 28, 22)
    clearSearch:SetPoint("LEFT", Ui.search, "RIGHT", 4, 0)
    clearSearch:SetScript("OnClick", function()
        if Ui.search then
            Ui.search:SetText("")
        end
        refreshRows()
        updateListStatus(#(P.State.list or {}), #rowsForTab(), false)
    end)

    local reload = ns.CreateNGButton(f, "Обновить", 90, 22)
    reload:SetPoint("LEFT", clearSearch, "RIGHT", 8, 0)
    reload:SetScript("OnClick", function()
        syncFromServer()
    end)

    local tabOrder = { "available", "managed", "owned", "favorites" }
    local tabNames = {
        available = "Доступные",
        managed = "Управляемые",
        owned = "Личные",
        favorites = "Избранное",
    }
    local prevTab = nil
    for _, name in ipairs(tabOrder) do
        local button = ns.CreateNGTab(f, tabNames[name], "Phase_" .. name, function()
            activeTab = name
            refreshRows()
            for other, tab in pairs(Ui.tabs or {}) do
                ns.SetNGTabSelected(tab, other == activeTab)
            end
        end)
        Ui.tabs = Ui.tabs or {}
        Ui.tabs[name] = button
        if prevTab then
            button:SetPoint("TOPLEFT", prevTab, "TOPRIGHT", 6, 0)
        else
            button:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -72)
        end
        prevTab = button
    end

    Ui.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Ui.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
    Ui.status:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 8)
    Ui.status:SetJustifyH("LEFT")

    -- Left/right split fills remaining space; create form sits inside left column.
    local leftHost = CreateFrame("Frame", nil, f)
    leftHost:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -104)
    leftHost:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 28)
    leftHost:SetWidth(268)

    local left = ns.CreateNGSection(leftHost, "Каталог")
    left:SetPoint("TOPLEFT", leftHost, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", leftHost, "BOTTOMRIGHT", 0, 126)

    local listScroll = createScroll(left)
    listScroll:SetPoint("TOPLEFT", left, "TOPLEFT", 8, -34)
    listScroll:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -28, 8)
    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetWidth(228)
    listChild:SetHeight(24)
    listScroll:SetScrollChild(listChild)
    -- VirtualList hooks ScrollFrame OnSizeChanged/OnVerticalScroll itself.
    Ui.list = ns.VirtualList.Create(listChild, {
        width = 224,
        rowHeight = CATALOG_ROW_H,
        visibleCount = 6,
        scrollFrame = listScroll,
        onClick = function(row) loadSelected(row.phase) end,
        renderRow = renderCatalogRow,
    })

    Ui.createFrame = ns.CreateNGSection(leftHost, "Создать фазу")
    Ui.createFrame:SetPoint("BOTTOMLEFT", leftHost, "BOTTOMLEFT", 0, 0)
    Ui.createFrame:SetPoint("BOTTOMRIGHT", leftHost, "BOTTOMRIGHT", 0, 0)
    Ui.createFrame:SetHeight(154)
    Ui.createFrame:Hide()
    local nameLabel = ns.CreateNGLabel(Ui.createFrame, "Имя:")
    nameLabel:SetPoint("TOPLEFT", Ui.createFrame, "TOPLEFT", 10, -38)
    nameLabel:SetWidth(68)
    nameLabel:SetJustifyH("LEFT")
    Ui.createName = ns.CreateNGEditBox(Ui.createFrame, "PhaseCreateName", 176, 20)
    Ui.createName:SetPoint("TOPLEFT", Ui.createFrame, "TOPLEFT", 80, -34)
    local mapLabel = ns.CreateNGLabel(Ui.createFrame, "Карта ID:")
    mapLabel:SetPoint("TOPLEFT", Ui.createFrame, "TOPLEFT", 10, -64)
    mapLabel:SetWidth(68)
    mapLabel:SetJustifyH("LEFT")
    Ui.createMap = ns.CreateNGEditBox(Ui.createFrame, "PhaseCreateMap", 176, 20)
    Ui.createMap:SetPoint("TOPLEFT", Ui.createFrame, "TOPLEFT", 80, -60)
    Ui.createMap:SetText("")
    local mapHint = Ui.createFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mapHint:SetPoint("TOPLEFT", Ui.createFrame, "TOPLEFT", 80, -82)
    mapHint:SetText("Пусто: все карты")
    local descLabel = ns.CreateNGLabel(Ui.createFrame, "Описание:")
    descLabel:SetPoint("TOPLEFT", Ui.createFrame, "TOPLEFT", 10, -106)
    descLabel:SetWidth(68)
    descLabel:SetJustifyH("LEFT")
    Ui.createDesc = ns.CreateNGEditBox(Ui.createFrame, "PhaseCreateDesc", 176, 20)
    Ui.createDesc:SetPoint("TOPLEFT", Ui.createFrame, "TOPLEFT", 80, -102)
    local createBtn = ns.NNL.Widgets.CreateButton(Ui.createFrame, { text = "Создать", width = 100, height = 20, style = "primary" })
    createBtn:SetPoint("BOTTOMRIGHT", Ui.createFrame, "BOTTOMRIGHT", -12, 6)
    createBtn:SetScript("OnClick", createPhaseFromForm)

    Ui.layoutLeftColumn = function()
        local createH = (Ui.createFrame and Ui.createFrame:IsShown()) and 162 or 0
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", leftHost, "TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMRIGHT", leftHost, "BOTTOMRIGHT", 0, createH)
    end
    Ui.layoutLeftColumn()

    local rightHost = ns.CreateNGSection(f, "Выбранная фаза")
    rightHost:SetPoint("TOPLEFT", leftHost, "TOPRIGHT", 10, 0)
    rightHost:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 28)
    -- At the minimum shell height the summary and actions must also scroll;
    -- otherwise they leave no usable viewport for the lower member list.
    local detailScroll = createScroll(rightHost)
    detailScroll:SetPoint("TOPLEFT", rightHost, "TOPLEFT", 0, -30)
    detailScroll:SetPoint("BOTTOMRIGHT", rightHost, "BOTTOMRIGHT", -22, 0)
    local right = CreateFrame("Frame", nil, detailScroll)
    right:SetSize(1, 360)
    detailScroll:SetScrollChild(right)
    detailScroll:HookScript("OnSizeChanged", function(self, width, height)
        if width and width > 20 then right:SetWidth(width) end
        right:SetHeight(math.max(360, height or self:GetHeight()))
    end)
    if detailScroll:GetWidth() > 20 then right:SetWidth(detailScroll:GetWidth()) end
    right:SetHeight(math.max(360, detailScroll:GetHeight()))

    Ui.detailEmpty = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Ui.detailEmpty:SetPoint("TOPLEFT", right, "TOPLEFT", 14, -44)
    Ui.detailEmpty:SetPoint("TOPRIGHT", right, "TOPRIGHT", -14, -44)
    Ui.detailEmpty:SetJustifyH("LEFT")
    Ui.detailEmpty:SetJustifyV("TOP")
    Ui.detailEmpty:SetTextColor(0.7, 0.7, 0.7)
    Ui.detailEmpty:SetText("Выберите фазу в каталоге, чтобы увидеть описание, участников и доступные действия.")

    -- Compact summary; long descriptions remain available through native scrolling.
    Ui.detailCard = CreateFrame("Frame", nil, right, "BackdropTemplate")
    Ui.detailCard:SetPoint("TOPLEFT", right, "TOPLEFT", 10, -36)
    Ui.detailCard:SetPoint("TOPRIGHT", right, "TOPRIGHT", -10, -36)
    Ui.detailCard:SetHeight(112)
    if Ui.detailCard.SetBackdrop then
        Ui.detailCard:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        Ui.detailCard:SetBackdropColor(0.02, 0.02, 0.02, 0.72)
        Ui.detailCard:SetBackdropBorderColor(0.55, 0.55, 0.6, 0.85)
    end
    Ui.detailCard:Hide()

    Ui.cardLock = Ui.detailCard:CreateTexture(nil, "ARTWORK")
    Ui.cardLock:SetSize(32, 32)
    Ui.cardLock:SetPoint("TOPLEFT", Ui.detailCard, "TOPLEFT", 12, -10)

    Ui.cardVis = Ui.detailCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    Ui.cardVis:SetPoint("TOP", Ui.cardLock, "BOTTOM", 0, -2)
    Ui.cardVis:SetJustifyH("CENTER")

    Ui.cardTitle = Ui.detailCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Ui.cardTitle:SetPoint("TOPLEFT", Ui.cardLock, "TOPRIGHT", 10, -2)
    Ui.cardTitle:SetPoint("RIGHT", Ui.detailCard, "RIGHT", -48, 0)
    Ui.cardTitle:SetJustifyH("LEFT")
    Ui.cardTitle:SetWordWrap(false)
    Ui.cardTitle:SetTextColor(1, 0.82, 0)

    Ui.cardId = Ui.detailCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    Ui.cardId:SetPoint("TOPRIGHT", Ui.detailCard, "TOPRIGHT", -12, -14)
    Ui.cardId:SetTextColor(0.48, 0.48, 0.52)

    Ui.cardMeta = Ui.detailCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Ui.cardMeta:SetPoint("TOPLEFT", Ui.cardTitle, "BOTTOMLEFT", 0, -4)
    Ui.cardMeta:SetPoint("RIGHT", Ui.detailCard, "RIGHT", -12, 0)
    Ui.cardMeta:SetJustifyH("LEFT")
    Ui.cardMeta:SetWordWrap(true)
    Ui.cardMeta:SetTextColor(0.72, 0.72, 0.72)

    local cardLine = Ui.detailCard:CreateTexture(nil, "ARTWORK")
    cardLine:SetTexture("Interface\\Buttons\\WHITE8X8")
    cardLine:SetHeight(1)
    cardLine:SetPoint("TOPLEFT", Ui.detailCard, "TOPLEFT", 12, -58)
    cardLine:SetPoint("TOPRIGHT", Ui.detailCard, "TOPRIGHT", -12, -58)
    cardLine:SetVertexColor(0.9, 0.9, 0.9, 0.22)

    Ui.cardBodyScroll = createScroll(Ui.detailCard)
    Ui.cardBodyScroll:SetPoint("TOPLEFT", cardLine, "BOTTOMLEFT", 0, -6)
    Ui.cardBodyScroll:SetPoint("BOTTOMRIGHT", Ui.detailCard, "BOTTOMRIGHT", -28, 8)
    local bodyChild = CreateFrame("Frame", nil, Ui.cardBodyScroll)
    bodyChild:SetSize(1, 1)
    Ui.cardBodyScroll:SetScrollChild(bodyChild)
    Ui.cardBody = bodyChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Ui.cardBody:SetPoint("TOPLEFT", bodyChild, "TOPLEFT", 0, 0)
    Ui.cardBody:SetWidth(300)
    Ui.cardBody:SetJustifyH("LEFT")
    Ui.cardBody:SetJustifyV("TOP")
    Ui.cardBody:SetWordWrap(true)
    Ui.cardBodyScroll:HookScript("OnSizeChanged", function(self, width)
        if Ui.cardBody and width and width > 40 then
            bodyChild:SetWidth(width)
            Ui.cardBody:SetWidth(width - 8)
            bodyChild:SetHeight(math.max(1, Ui.cardBody:GetStringHeight() + 8))
        end
    end)

    Ui.enter = ns.NNL.Widgets.CreateButton(right, { text = "Войти", width = 132, height = 22, style = "primary" })
    Ui.enter:SetPoint("TOPLEFT", Ui.detailCard, "BOTTOMLEFT", 2, -8)
    Ui.enter:SetScript("OnClick", Panel.EnterSelected)
    Ui.gotoBtn = ns.CreateNGButton(right, "Телепорт", 132, 22)
    Ui.gotoBtn:SetPoint("LEFT", Ui.enter, "RIGHT", 4, 0)
    Ui.gotoBtn:SetScript("OnClick", Panel.GotoSelected)
    Ui.leave = ns.CreateNGButton(right, "Покинуть", 132, 22)
    Ui.leave:SetPoint("TOPLEFT", Ui.enter, "BOTTOMLEFT", 0, -4)
    Ui.leave:SetScript("OnClick", function()
        P.Leave(function(ok, response)
            setStatus(ok and "Контекст сброшен сервером." or ("Выход не выполнен: " .. tostring(response.detail or response.reason)), not ok)
            updateDetails()
        end)
    end)
    Ui.favorite = ns.CreateNGButton(right, "В избранное", 132, 22)
    Ui.favorite:SetPoint("LEFT", Ui.leave, "RIGHT", 4, 0)
    Ui.favorite:SetScript("OnClick", function()
        if not selectedId then return end
        local saved = favorite(selectedId)
        if saved then
            db().PhaseFavorites[selectedId] = nil
        else
            db().PhaseFavorites[selectedId] = { tags = "" }
        end
        refreshRows()
    end)
    Ui.archive = ns.NNL.Widgets.CreateButton(right, { text = "Архивировать", width = 132, height = 22, style = "danger" })
    Ui.archive:SetPoint("TOPLEFT", Ui.leave, "BOTTOMLEFT", 0, -4)
    Ui.archive:SetScript("OnClick", archiveSelected)
    local link = ns.CreateNGButton(right, "Ссылка в чат", 132, 22)
    link:SetPoint("LEFT", Ui.archive, "RIGHT", 4, 0)
    link:SetScript("OnClick", Panel.PrintSelectedLink)

    Ui.detailViews, Ui.detailViewButtons = {}, {}
    for _, view in ipairs({ "overview", "settings", "rights" }) do
        local container = CreateFrame("Frame", nil, right)
        container:SetPoint("TOPLEFT", Ui.archive, "BOTTOMLEFT", 0, -10)
        container:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -12, 0)
        container:Hide()
        Ui.detailViews[view] = container
    end
    local overview = Ui.detailViews.overview
    local tagsLabel = ns.CreateNGLabel(overview, "Теги:")
    tagsLabel:SetPoint("TOPLEFT", overview, "TOPLEFT", 0, -8)
    Ui.tags = ns.CreateNGEditBox(overview, "PhaseTags", 235, 22)
    Ui.tags:SetPoint("LEFT", tagsLabel, "RIGHT", 6, 0)
    Ui.tags:SetPoint("RIGHT", overview, "RIGHT", 0, 0)
    Ui.tags:SetScript("OnEnterPressed", function(self)
        if selectedId then
            db().PhaseFavorites[selectedId] = db().PhaseFavorites[selectedId] or {}
            db().PhaseFavorites[selectedId].tags = trim(self:GetText())
            refreshRows()
        end
        self:ClearFocus()
    end)

    local membersTitle = ns.CreateNGLabel(overview, "Участники:")
    membersTitle:SetPoint("TOPLEFT", overview, "TOPLEFT", 0, -34)
    local membersHost = CreateFrame("Frame", nil, overview)
    membersHost:SetPoint("TOPLEFT", membersTitle, "BOTTOMLEFT", 0, -6)
    membersHost:SetPoint("BOTTOMRIGHT", overview, "BOTTOMRIGHT", 0, 10)
    local membersScroll = createScroll(membersHost)
    membersScroll:SetPoint("TOPLEFT", membersHost, "TOPLEFT", 0, 0)
    membersScroll:SetPoint("BOTTOMRIGHT", membersHost, "BOTTOMRIGHT", -20, 0)
    local membersChild = CreateFrame("Frame", nil, membersScroll)
    membersChild:SetWidth(1)
    membersChild:SetHeight(24)
    membersScroll:SetScrollChild(membersChild)
    Ui.memberList = ns.VirtualList.Create(membersChild, {
        width = 1,
        rowHeight = 20,
        visibleCount = 3,
        scrollFrame = membersScroll,
        onClick = function() end,
        renderRow = function(button, row)
            local label = button.label or button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            button.label = label
            label:ClearAllPoints()
            label:SetPoint("LEFT", button, "LEFT", 2, 0)
            label:SetPoint("RIGHT", button, "RIGHT", -2, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            local charName = (row.name and row.name ~= "") and row.name or ("#" .. tostring(row.character or "?"))
            label:SetText(charName .. "  |  " .. roleBadge(row.role))
        end,
    })
    reflowMemberList(membersScroll, membersChild, Ui.memberList)

    local previous
    for _, entry in ipairs({ { "overview", "Обзор" }, { "settings", "Настройки" }, { "rights", "Права" } }) do
        local view = entry[1]
        local button = ns.CreateNGTab(right, entry[2], "PhaseDetail_" .. view, function() showDetailView(view) end)
        button:SetHeight(22)
        button:SetPoint("TOPLEFT", previous or right, previous and "TOPRIGHT" or "TOPLEFT", previous and 4 or 12, previous and 0 or -4)
        Ui.detailViewButtons[view] = button
        previous = button
    end
    Ui.phaseManageBtn = Ui.detailViewButtons.settings
    Ui.membersManageBtn = Ui.detailViewButtons.rights
    Ui.refreshDetailView = function() showDetailView(activeDetailView) end
    local function reflowDetails()
        local width = right:GetWidth()
        if not width or width <= 40 then return end
        local actionWidth = (width - 28) / 2
        for _, button in ipairs({ Ui.enter, Ui.gotoBtn, Ui.leave, Ui.favorite, Ui.archive, link }) do
            button:SetWidth(actionWidth)
        end
        for _, button in pairs(Ui.detailViewButtons) do button:SetWidth((width - 32) / 3) end
    end
    right:HookScript("OnSizeChanged", reflowDetails)
    reflowDetails()
    updateDetails()

    P.On("NOBLENEXT_PHASE_CHANGED", function()
        updateDetails()
        refreshRows()
    end)
    P.On("list", refreshRows)
    P.On("caps", refreshCreateVisibility)

    f:SetScript("OnShow", function()
        ns.SetNGTabSelected(Ui.tabs.available, activeTab == "available")
        ns.SetNGTabSelected(Ui.tabs.managed, activeTab == "managed")
        ns.SetNGTabSelected(Ui.tabs.owned, activeTab == "owned")
        ns.SetNGTabSelected(Ui.tabs.favorites, activeTab == "favorites")
        syncFromServer()
        refreshRows()
    end)
    return f
end

