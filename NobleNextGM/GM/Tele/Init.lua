-- Loaded through the NobleNextGM private extension namespace.
-- GM/Tele/Init.lua — избранные именованные телепорты (.tele)

local _, ns = ...
local NNL = LibStub("NobleNextLib-1.0")

local MODULE_NAME = "Tele"
local selectedIndex = nil

local function EnsureDb()
    NobleNextCharDB = NobleNextCharDB or {}
    if type(NobleNextCharDB.TeleFavorites) ~= "table" then
        NobleNextCharDB.TeleFavorites = {}
    end
    return NobleNextCharDB.TeleFavorites
end

local function NormalizeName(name)
    if name == nil then
        return ""
    end
    return tostring(name):match("^%s*(.-)%s*$") or ""
end

local function FormatTeleCmd(path, argValues, fallback)
    local CD = ns.CommandDefinitions
    if CD and CD.Find and CD.Format then
        local def = CD.Find(path)
        if def then
            local cmd = CD.Format(def, argValues)
            if cmd and cmd ~= "" then
                return cmd
            end
        end
    end
    return fallback
end

local function SendTeleCmd(cmd, tag)
    if not cmd or cmd == "" then
        return false
    end
    if ns.PrintDebug then
        ns.PrintDebug("Tele -> " .. cmd)
    end
    if ns.EnqueueCommand then
        ns.EnqueueCommand(cmd, { tag = tag or "tele" })
        return true
    end
    if ns.RunGmCommand then
        return ns.RunGmCommand(cmd)
    end
    ns.PrintError("Нет API отправки GM-команд.")
    return false
end

local function FindFavoriteIndex(name)
    local list = EnsureDb()
    local key = name:lower()
    for i = 1, #list do
        local entry = list[i]
        if entry and NormalizeName(entry.name):lower() == key then
            return i
        end
    end
    return nil
end

local function InitTeleModule(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:Hide()

    local Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    Title:SetText("Избранные телепорты")
    Title:SetTextColor(ns.COLORS.goldRaw.r, ns.COLORS.goldRaw.g, ns.COLORS.goldRaw.b)
    Title:SetPoint("TOP", f, "TOP", 0, -10)

    local HelpLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    HelpLabel:SetText("Избранное сохраняется для этого персонажа. «Создать здесь» добавляет общую точку на сервере. Имя точки: без пробелов; используйте подчёркивания.")
    HelpLabel:SetTextColor(0.6, 0.6, 0.6, 1)
    HelpLabel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    HelpLabel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    HelpLabel:SetJustifyH("CENTER")
    HelpLabel:SetWordWrap(true)

    local EditSection = ns.CreateNGSection(f, "Телепорт и избранное", nil, 184)
    EditSection:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 36)
    EditSection:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 36)
    EditSection:SetHeight(184)

    local ListSection = ns.CreateNGSection(f, "Избранное")
    ListSection:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -40)
    ListSection:SetPoint("BOTTOMRIGHT", EditSection, "TOPRIGHT", 0, 12)

    local CountLabel = ns.CreateNGLabel(ListSection, "Всего: 0")
    CountLabel:SetPoint("TOPRIGHT", ListSection, "TOPRIGHT", -12, -8)

    local scroll = NNL.Scroll.CreateFrame(ListSection)
    scroll:SetPoint("TOPLEFT", ListSection, "TOPLEFT", 8, -34)
    scroll:SetPoint("BOTTOMRIGHT", ListSection, "BOTTOMRIGHT", -28, 8)
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(560)
    scrollChild:SetHeight(24)
    scroll:SetScrollChild(scrollChild)

    local Ui = {}

    local NameLabel = ns.CreateNGLabel(EditSection, "Имя:")
    NameLabel:SetPoint("TOPLEFT", EditSection, "TOPLEFT", 20, -38)

    local NameBox = ns.CreateNGEditBox(EditSection, "TeleNameBox", 190, 24)
    NameBox:SetPoint("TOPLEFT", NameLabel, "TOPRIGHT", 10, 0)

    local NoteLabel = ns.CreateNGLabel(EditSection, "Заметка:")
    NoteLabel:SetPoint("TOPLEFT", NameBox, "TOPRIGHT", 16, 0)

    local NoteBox = ns.CreateNGEditBox(EditSection, "TeleNoteBox", 190, 24)
    NoteBox:SetPoint("TOPLEFT", NoteLabel, "TOPRIGHT", 10, 0)

    local SelectedLabel = ns.CreateNGLabel(EditSection, "Выбрано: -")
    SelectedLabel:SetPoint("TOPLEFT", EditSection, "TOPLEFT", 20, -62)

    local function RefreshSelectedLabel()
        local name = NormalizeName(NameBox:GetText())
        if name == "" then
            SelectedLabel:SetText("Выбрано: -")
        else
            local note = NormalizeName(NoteBox:GetText())
            if note ~= "" then
                SelectedLabel:SetText("Выбрано: " .. name .. " (" .. note .. ")")
            else
                SelectedLabel:SetText("Выбрано: " .. name)
            end
        end
    end

    local function SelectFavorite(index)
        local list = EnsureDb()
        local entry = list[index]
        if not entry then
            selectedIndex = nil
            RefreshSelectedLabel()
            return
        end
        selectedIndex = index
        NameBox:SetText(entry.name or "")
        NoteBox:SetText(entry.note or "")
        RefreshSelectedLabel()
        if Ui.List then
            Ui.List:Refresh()
        end
    end

    local function RefreshList()
        local list = EnsureDb()
        local rows = {}
        for i = 1, #list do
            local entry = list[i]
            rows[#rows + 1] = {
                id = i,
                index = i,
                name = entry.name or "?",
                desc = entry.note or "",
                note = entry.note or "",
            }
        end
        CountLabel:SetText("Всего: " .. tostring(#rows))
        if Ui.List then
            Ui.List:SetRows(rows)
        end
        if selectedIndex and not list[selectedIndex] then
            selectedIndex = nil
        end
        RefreshSelectedLabel()
    end

    Ui.List = ns.VirtualList.Create(scrollChild, {
        width = 558,
        rowHeight = 28,
        visibleCount = 7,
        scrollFrame = scroll,
        onClick = function(row)
            SelectFavorite(row.index)
        end,
        renderRow = function(btn, row)
            local fs = btn.fs or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.fs = fs
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -4)
            fs:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            fs:SetJustifyH("LEFT")
            local mark = (selectedIndex == row.index) and "|cffFFD100> |r" or ""
            fs:SetText(mark .. (row.name or "?"))

            local sub = btn.sub or btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            btn.sub = sub
            sub:ClearAllPoints()
            sub:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 6, 3)
            sub:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            sub:SetJustifyH("LEFT")
            local note = row.note or ""
            -- Let the font string clip at its width; byte slicing corrupts UTF-8.
            sub:SetText(note ~= "" and note or "без заметки")

            if btn.SetBackdropBorderColor then
                if selectedIndex == row.index then
                    btn:SetBackdropBorderColor(1, 0.82, 0, 1)
                else
                    btn:SetBackdropBorderColor(0.25, 0.2, 0.1, 0.6)
                end
            end
        end,
    })

    NameBox:SetScript("OnTextChanged", function()
        RefreshSelectedLabel()
    end)
    NoteBox:SetScript("OnTextChanged", function()
        RefreshSelectedLabel()
    end)
    NameBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    NoteBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    local function CurrentName()
        return NormalizeName(NameBox:GetText())
    end
    local function ServerName()
        local name = CurrentName()
        if name == "" or name:find("%s") or name:find('["|]') then
            ns.PrintError("Для серверной точки укажите имя без пробелов, кавычек и ссылок. Например: Лагерь_у_реки.")
            return nil
        end
        return name
    end

    local GoBtn = NNL.Widgets.CreateButton(EditSection, {text = "Телепорт", width = 110, height = 26, style = "primary"})
    GoBtn:SetPoint("TOPLEFT", EditSection, "TOPLEFT", 20, -95)
    GoBtn:SetScript("OnClick", function()
        local name = ServerName()
        if not name then return end
        local cmd = FormatTeleCmd("tele", { teleName = name }, ".tele " .. name)
        SendTeleCmd(cmd, "tele:go")
    end)

    local AddFavBtn = ns.CreateNGButton(EditSection, "В избранное", 120, 26)
    AddFavBtn:SetPoint("TOPLEFT", GoBtn, "TOPRIGHT", 8, 0)
    AddFavBtn:SetScript("OnClick", function()
        local name = CurrentName()
        if name == "" then
            ns.PrintError("Укажите имя для избранного.")
            return
        end
        local note = NormalizeName(NoteBox:GetText())
        local list = EnsureDb()
        local idx = FindFavoriteIndex(name)
        if idx then
            list[idx].name = name
            list[idx].note = note
            selectedIndex = idx
            ns.Print("Обновлено избранное: " .. name)
        else
            list[#list + 1] = { name = name, note = note }
            selectedIndex = #list
            ns.Print("Добавлено в избранное: " .. name)
        end
        RefreshList()
    end)

    local AddDbBtn = ns.CreateNGButton(EditSection, "Создать здесь", 150, 26)
    AddDbBtn:SetPoint("TOPLEFT", GoBtn, "BOTTOMLEFT", 0, -10)
    AddDbBtn:SetScript("OnClick", function()
        local name = ServerName()
        if not name then return end
        local cmd = FormatTeleCmd("tele add", { name = name }, ".tele add " .. name)
        SendTeleCmd(cmd, "tele:add")
    end)

    local DelFavBtn = ns.CreateNGButton(EditSection, "Убрать из избранного", 160, 26)
    DelFavBtn:SetPoint("TOPLEFT", AddFavBtn, "TOPRIGHT", 8, 0)
    DelFavBtn:SetScript("OnClick", function()
        local name = CurrentName()
        if name == "" then
            ns.PrintError("Укажите имя избранного.")
            return
        end
        local idx = FindFavoriteIndex(name)
        if not idx then
            ns.PrintError("В избранном нет: " .. name)
            return
        end
        table.remove(EnsureDb(), idx)
        if selectedIndex == idx then
            selectedIndex = nil
        elseif selectedIndex and selectedIndex > idx then
            selectedIndex = selectedIndex - 1
        end
        ns.Print("Удалено из избранного: " .. name)
        RefreshList()
    end)

    local DelDbBtn = NNL.Widgets.CreateButton(EditSection, {text = "Удалить с сервера", width = 150, height = 26, style = "danger"})
    DelDbBtn:SetPoint("TOPLEFT", AddDbBtn, "TOPRIGHT", 8, 0)
    DelDbBtn:SetScript("OnClick", function()
        local name = ServerName()
        if not name then return end
        StaticPopupDialogs["NOBLENEXT_TELE_DEL_DB"] = {
            text = string.format("Удалить именованный телепорт \"%s\" из БД (.tele del)?", name),
            button1 = DELETE or YES,
            button2 = CANCEL or NO,
            OnAccept = function()
                local cmd = FormatTeleCmd("tele del", { teleName = name }, ".tele del " .. name)
                SendTeleCmd(cmd, "tele:del")
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("NOBLENEXT_TELE_DEL_DB")
    end)

    f:SetScript("OnShow", function()
        RefreshList()
    end)

    RefreshList()
    return f
end

ns.RegisterModule(MODULE_NAME, InitTeleModule, "Избранные телепорты (.tele)")

local function RegisterTeleSlash()
    ns.RegisterSlashCommand("NNTELE", function() ns.ShowModule(MODULE_NAME) end, "nntele")
end

C_Timer.After(0, RegisterTeleSlash)
