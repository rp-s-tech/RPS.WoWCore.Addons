-- Forever/Camelot presentation adapted to the 12.1.5 retail paper doll.
-- Native equipment buttons, sidebars and stat setters retain their handlers.
local _, ns = ...
local Sheet = { rows = {}, categories = {} }
ns.CharacterSheet = Sheet
local PATH = "Interface\\AddOns\\NobleNext\\Assets\\CharacterFrame\\"
local LEFT, RIGHT, HEIGHT, HEADER = 398, 233, 500, 78

local function Texture(region, name)
    local info = ns.CharacterFrameTextures[name]
    assert(info, "Missing character texture: " .. name)
    region:SetTexture(PATH .. info[1])
    region:SetTexCoord(info[2]/1024, info[3]/1024, info[4]/1024, info[5]/1024)
end

local function Anchor(frame, parent, x, y, right, bottom)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", right, bottom)
end

local function Readable(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
end

local function Damage(low, high)
    if not Readable(low) or not Readable(high) or high <= 0 then return nil end
    return string.format("%d – %d", math.floor(low), math.ceil(high))
end

local function Offhand()
    local _, speed = UnitAttackSpeed("player")
    if not Readable(speed) or speed <= 0 then return nil end
    local _, _, low, high = UnitDamage("player")
    return Damage(low, high)
end

local function Ranged()
    local speed, low, high = UnitRangedDamage("player")
    if not Readable(speed) or speed <= 0 then return nil end
    return Damage(low, high)
end

-- Category order follows Camelot/PaperDollFrameConstants.lua. Removed classic
-- mechanics are explicit unavailable rows, never invented values or skill ranks.
Sheet.categories = {
    { "Общее", {
        {"HEALTH", "Здоровье"}, {"POWER"}, {"MOVESPEED", "Скорость движения"},
    } },
    { "Основные характеристики", {
        {"STRENGTH", "Сила"}, {"AGILITY", "Ловкость"}, {"STAMINA", "Выносливость"},
        {"INTELLECT", "Интеллект"},
        {"SPIRIT", "Дух", unavailable="Дух не используется как основная характеристика в Retail 12.1.5."},
    } },
    { "Оружие", {
        {"ATTACK_DAMAGE", "Правая рука"},
        {"OFFHAND_DAMAGE", "Левая рука", read=Offhand},
        {"RANGED_DAMAGE", "Дальний бой", read=Ranged},
        {"ATTACK_AP", "Сила атаки"}, {"ATTACK_ATTACKSPEED", "Скорость атаки"},
    } },
    { "Заклинания", {
        {"SPELLPOWER", "Сила заклинаний"}, {"MANAREGEN", "Восполнение маны"},
    } },
    { "Усиления", {
        {"CRITCHANCE", "Критический удар"}, {"HASTE", "Скорость"},
        {"MASTERY", "Искусность"}, {"VERSATILITY", "Универсальность"},
        {"LIFESTEAL", "Самоисцеление"}, {"AVOIDANCE", "Избегание"},
    } },
    { "Защита", {
        {"DEFENSE", "Навык защиты", unavailable="Классический навык защиты отсутствует в Retail 12.1.5."},
        {"ARMOR", "Броня"}, {"DODGE", "Уклонение"},
        {"PARRY", "Парирование"}, {"BLOCK", "Блок"},
    } },
}

local function Unavailable(row, reason)
    row.Value:SetText("—")
    row.tooltip = row.definition[2] or "Характеристика"
    row.tooltip2 = reason or "Нет применимого значения или данные временно недоступны."
    row.onEnterFunc = nil
end

function Sheet:Refresh()
    if not self.scroll or not self.panel:IsVisible() then return end
    if ns.RPSClient and ns.RPSClient.RenderSheet and ns.RPSClient.RenderSheet(self.panel) then
        self.scroll:Hide()
        return
    end
    for _, row in ipairs(self.rows) do
        local definition = row.definition
        row.tooltip, row.tooltip2, row.tooltip3, row.tooltip4 = nil, nil, nil, nil
        row.onEnterFunc, row.UpdateTooltip = nil, nil
        row.Value:SetText("—")
        local ok = true
        if definition.unavailable then
            Unavailable(row, definition.unavailable)
        elseif definition.read then
            local value
            ok, value = pcall(definition.read)
            if ok and value then
                row.Value:SetText(value)
                row.tooltip = definition[2] .. ": " .. value
            else Unavailable(row) end
        else
            local info = PAPERDOLL_STATINFO and PAPERDOLL_STATINFO[definition[1]]
            if info then
                ok = pcall(info.updateFunc, row, "player")
                if not ok or not row:IsShown() then Unavailable(row) end
            else Unavailable(row) end
        end
        if definition[2] then row.Label:SetText(definition[2] .. ":") end
        row.Label:SetTextColor(1, 0.82, 0)
        row.Value:SetTextColor(1, 1, 1)
        row:Show()
    end
end

local function Tooltip(row)
    if row.onEnterFunc then
        local ok = pcall(row.onEnterFunc, row)
        if ok then return end
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.tooltip or row.definition[2] or "Характеристика")
    for _, key in ipairs({"tooltip2", "tooltip3", "tooltip4"}) do
        if row[key] then GameTooltip:AddLine(row[key], 1, 0.82, 0, true) end
    end
    GameTooltip:Show()
end

local function SkinScrollBar(bar)
    -- MinimalScrollBar is shared by Retail and Camelot. Preserve its native
    -- thumb sizing, drag, wheel, and stepper state handling.
    if not bar or not bar.Track then return end
    for _, region in ipairs({bar.Track.Thumb.Begin, bar.Track.Thumb.Middle, bar.Track.Thumb.End}) do
        region:SetVertexColor(1, 0.78, 0.48)
    end
end

local function PaneBorder(pane)
    if pane.NobleNextBorder then return end
    local border = pane:CreateTexture(nil, "OVERLAY")
    border:SetAtlas("common-insideframe")
    border:SetAllPoints()
    border:SetVertexColor(1, 0.78, 0.48)
    pane.NobleNextBorder = border
end

local function CreateStats()
    -- Parenting to the native pane preserves its Show/Hide and sidebar selection.
    local panel = CreateFrame("Frame", "NobleNextCharacterStats", CharacterStatsPane)
    panel:SetAllPoints()
    panel:SetFrameLevel(CharacterStatsPane:GetFrameLevel() + 10)
    panel:EnableMouse(true)
    Sheet.panel = panel
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local _, class = UnitClass("player")
    local classTexture = string.lower(class or "") .. "-bg"
    Texture(bg, ns.CharacterFrameTextures[classTexture] and classTexture or "stat-bg")

    PaneBorder(panel)
    local scroll = CreateFrame("ScrollFrame", "NobleNextCharacterStatsScroll", panel, "ScrollFrameTemplate")
    scroll:EnableMouseWheel(true)
    Anchor(scroll, panel, 9, -8, -25, 9)
    Sheet.scroll = scroll
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(RIGHT - 38)
    scroll:SetScrollChild(content)
    Sheet.content = content
    local bar = scroll.ScrollBar or _G.NobleNextCharacterStatsScrollScrollBar
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 7, -9)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 7, 9)
        SkinScrollBar(bar)
    end

    local y, index = 0, 0
    for _, category in ipairs(Sheet.categories) do
        local header = CreateFrame("Frame", nil, content)
        header:SetSize(RIGHT - 38, 32)
        header:SetPoint("TOPLEFT", 0, -y)
        local banner = header:CreateTexture(nil, "BACKGROUND")
        banner:SetAllPoints(); Texture(banner, "title")
        local title = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("CENTER"); title:SetText(category[1])
        y = y + 34
        for rowIndex, definition in ipairs(category[2]) do
            index = index + 1
            local row = CreateFrame("Frame", nil, content, "CharacterStatFrameTemplate")
            row.definition = definition
            row:SetSize(RIGHT - 38, 23)
            row:SetPoint("TOPLEFT", 0, -y)
            row.Label:ClearAllPoints(); row.Label:SetPoint("LEFT", 6, 0)
            row.Label:SetWidth(124); row.Label:SetJustifyH("LEFT")
            row.Label:SetText((definition[2] or "Ресурс") .. ":")
            row.Value:ClearAllPoints(); row.Value:SetPoint("RIGHT", -5, 0)
            row.Value:SetWidth(60); row.Value:SetJustifyH("RIGHT")
            row.Background:ClearAllPoints(); row.Background:SetAllPoints()
            Texture(row.Background, "line-bounce2")
            row.Background:SetAlpha(rowIndex % 2 == 0 and 0.85 or 0.15)
            row:EnableMouse(true)
            row:SetScript("OnEnter", Tooltip)
            row:SetScript("OnLeave", GameTooltip_Hide)
            Sheet.rows[index] = row
            y = y + 23
        end
        y = y + 5
    end
    content:SetHeight(y)
    local elapsed = 0
    panel:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= 0.25 then
            elapsed = 0
            Sheet:Refresh()
        end
    end)
    panel:SetScript("OnShow", function()
        Sheet:Refresh()
        if ns.RPSClient then ns.RPSClient.Send("RequestSync") end
    end)
end

local function SkinTabs()
    if InCombatLockdown() then return end
    for i = 1, 3 do
        local tab = _G["PaperDollSidebarTab" .. i]
        if tab then
            tab.TabBg:ClearAllPoints(); tab.TabBg:SetPoint("CENTER")
            tab.TabBg:SetSize(42, 42)
            Texture(tab.TabBg, GetPaperDollSideBarFrame(i):IsShown() and "stattab-selected" or "stattab")
            tab.Hider:SetAlpha(0)
        end
    end
end

local function TintNineSlice(frame)
    if not frame or not frame.NineSlice then return end
    for _, region in ipairs({frame.NineSlice:GetRegions()}) do
        if region.SetVertexColor then region:SetVertexColor(1, 0.78, 0.48) end
    end
end

local function SkinSlots()
    local names = {"Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist",
        "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand"}
    for _, name in ipairs(names) do
        local slot = _G["Character" .. name .. "Slot"]
        if slot then
            -- Hide only the old decorative background, retaining the item icon,
            -- quality border, cooldown, sockets, enchants and secure click logic.
            slot:DisableDrawLayer("BACKGROUND")
            local old = _G[slot:GetName() .. "Frame"]
            if old then old:SetAlpha(0) end
            local normal = slot:GetNormalTexture()
            if normal then normal:SetAlpha(0) end
            local border = slot:CreateTexture(nil, "BORDER", nil, -1)
            border:SetSize(50, 50); border:SetPoint("CENTER")
            Texture(border, "gearslot")
        end
    end
end

local function ClearModelBackground()
    for _, name in ipairs({"BackgroundTopLeft", "BackgroundTopRight", "BackgroundBotLeft", "BackgroundBotRight", "BackgroundOverlay"}) do
        if CharacterModelScene[name] then CharacterModelScene[name]:SetAlpha(0) end
    end
end

local function SkinListEntry(owner, button)
    if owner ~= Sheet then button = owner end -- ForEachFrame(frame, data) vs callback(owner, frame, data)
    if button.Name then button.Name:SetTextColor(1, 0.82, 0) end
    for _, key in ipairs({"Left", "Right", "Middle"}) do
        if button[key] and button[key].SetVertexColor then button[key]:SetVertexColor(1, 0.78, 0.48) end
    end
end

local function SkinTitle(button, data)
    -- Native backgrounds are fixed at 169 px, while ScrollBox stretches rows.
    -- Keep selection/check and click logic, replacing only the decorative art.
    for _, key in ipairs({"BgTop", "BgMiddle", "BgBottom"}) do button[key]:SetAlpha(0) end
    Anchor(button.Stripe, button, 0, 0, 0, 0)
    Texture(button.Stripe, "line-bounce2")
    button.Stripe:SetAlpha(data.index % 2 == 0 and 0.55 or 0.18)
    button.Stripe:Show()
    Anchor(button.SelectedBar, button, 0, 0, 0, 0)
    button.SelectedBar:SetColorTexture(0.65, 0.43, 0.12, 0.4)
    button.SelectedBar:SetAlpha(1)
    button.SelectedBar:SetBlendMode("BLEND")
    local highlight = button:GetHighlightTexture()
    Anchor(highlight, button, 0, 0, 0, 0)
    highlight:SetColorTexture(1, 0.82, 0.45, 0.15)
    highlight:SetBlendMode("BLEND")
    button.text:SetTextColor(1, 0.82, 0)
end

local function SetupCurrencyTransfer(button)
    if not button then return end
    hooksecurefunc(button, "UpdateEnabledState", function()
        if not button.currencyID or C_CurrencyInfo.IsAccountCharacterCurrencyDataReady()
            or C_CurrencyInfo.IsCurrencyTransferInProgress() then
            button.NobleNextWait = nil
            button.Text:SetText(CURRENCY_TRANSFER_TOGGLE_BUTTON_LABEL)
            return
        end
        local wait = button.NobleNextWait
        if not wait or wait.currencyID ~= button.currencyID then
            wait = {currencyID = button.currencyID}
            button.NobleNextWait = wait
            C_Timer.After(8, function()
                if button.NobleNextWait == wait and button:IsVisible() then
                    wait.expired = true
                    button:UpdateEnabledState()
                end
            end)
        end
        if wait.expired then
            button:SetLoadingSpinnerShown(false)
            button:SetEnabled(false)
            button.Text:SetText("Перенос недоступен")
            button:SetDisabledTooltip("Данные валют других персонажей не получены. Закройте и снова откройте сведения о валюте, чтобы повторить запрос.", "ANCHOR_RIGHT")
        end
    end)
    button:HookScript("OnHide", function() button.NobleNextWait = nil end)
end

local function SetupPage(page, kind, popup)
    if not page or page.NobleNextLayout then return end
    page.NobleNextLayout = true
    local bg = page:CreateTexture(nil, "BACKGROUND", nil, -5)
    bg:SetAllPoints(CharacterFrame.Inset); Texture(bg, "general-bg")
    local host = CreateFrame("Frame", nil, page)
    host:SetAllPoints(CharacterFrame.InsetRight)
    page.NobleNextDetailsHost = host
    local empty = host:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("CENTER"); empty:SetWidth(RIGHT - 35)
    empty:SetText(kind == "reputation" and "Выберите фракцию для просмотра описания." or "Выберите валюту для просмотра описания.")
    page.NobleNextEmpty = empty
    if page.ScrollBox and ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
        ScrollUtil.AddInitializedFrameCallback(page.ScrollBox, SkinListEntry, Sheet, true)
    end
    if popup then
        popup:SetParent(host)
        if popup.Border then popup.Border:Hide() end
        local close = popup.CloseButton or popup["$parent.CloseButton"]
        if close then close:Hide() end
        -- Remove the old detached-dialog artwork, retaining all native controls.
        for _, region in ipairs({popup:GetRegions()}) do
            if region:GetObjectType() == "Texture" then region:SetAlpha(0) end
        end
        popup:HookScript("OnShow", function() empty:Hide() end)
        popup:HookScript("OnHide", function() empty:Show() end)
        empty:SetShown(not popup:IsShown())
    end
    page:HookScript("OnShow", function() Sheet:Layout() end)
    if kind == "currency" and popup then
        SetupCurrencyTransfer(popup.CurrencyTransferToggleButton)
        local description = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        description:SetJustifyH("LEFT")
        description:SetJustifyV("TOP")
        Anchor(description, popup, 14, -70, -14, 110)
        popup.NobleNextDescription = description
        hooksecurefunc(page, "UpdatePopup", function(_, button)
            popup.Title:SetText(button.elementData.name or "Валюта")
            local info = C_CurrencyInfo.GetCurrencyInfo(button.elementData.currencyID)
            description:SetText(info and info.description or "")
            Sheet:Layout()
        end)
    elseif popup then
        local progress = CreateFrame("StatusBar", nil, popup, "ReputationBarTemplate")
        progress:SetSize(RIGHT - 35, 15)
        progress:SetPoint("TOP", 0, -49)
        progress.LeftTexture:SetWidth((RIGHT - 35) * 0.6)
        progress.RightTexture:SetWidth((RIGHT - 35) * 0.4)
        progress.LeftTexture:SetVertexColor(1, 0.8, 0.5)
        progress.RightTexture:SetVertexColor(1, 0.8, 0.5)
        progress:Hide()
        popup.NobleNextProgress = progress
        hooksecurefunc(popup, "Refresh", function()
            -- Selection notifications refresh the detail before the list's bars.
            C_Timer.After(0, function() if popup:IsShown() then Sheet:Layout() end end)
        end)
    end
end

local function LayoutPage(page, popup, reputation)
    if not page then return end
    SetupPage(page, reputation and "reputation" or "currency", popup)
    if not page:IsShown() then return end
    if page.filterDropdown then
        page.filterDropdown:ClearAllPoints()
        page.filterDropdown:SetPoint("TOPRIGHT", CharacterFrame.Inset, "TOPRIGHT", -24, -7)
    end
    if page.ScrollBox then Anchor(page.ScrollBox, CharacterFrame.Inset, 6, -40, -24, 5) end
    if popup then
        Anchor(popup, CharacterFrame.InsetRight, 0, 0, 0, 0)
        popup.Title:ClearAllPoints(); popup.Title:SetPoint("TOP", 0, -18)
        popup.Title:SetWidth(RIGHT - 30); popup.Title:SetJustifyH("CENTER")
        if reputation then
            Anchor(popup.ScrollingDescription, popup, 14, -82, -26, 110)
            local progress = popup.NobleNextProgress
            progress:Hide()
            -- Mirror the native bar, including renown/friendship/paragon handling;
            -- do not recreate their formulas or change the selected faction.
            if page.ScrollBox and page.ScrollBox.ForEachFrame and C_Reputation then
                local selected = C_Reputation.GetSelectedFaction()
                page.ScrollBox:ForEachFrame(function(entry)
                    local source = entry.Content and entry.Content.ReputationBar
                    if entry.factionIndex == selected and source then
                        progress:SetMinMaxValues(source:GetMinMaxValues())
                        progress:SetValue(source:GetValue())
                        progress:SetStatusBarColor(source:GetStatusBarColor())
                        progress.BarText:SetText(source.barProgressText or source.reputationStandingText)
                        progress:Show()
                    end
                end)
            end
            if popup.Divider then popup.Divider:Hide() end
            for i, button in ipairs({popup.AtWarCheckbox, popup.MakeInactiveCheckbox, popup.WatchFactionCheckbox}) do
                button:ClearAllPoints(); button:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 12, 78 - (i - 1) * 25)
            end
            if popup.ViewRenownButton then
                popup.ViewRenownButton:ClearAllPoints(); popup.ViewRenownButton:SetPoint("BOTTOM", 0, 6)
            end
        else
            popup.InactiveCheckbox:ClearAllPoints(); popup.InactiveCheckbox:SetPoint("BOTTOMLEFT", 12, 75)
            popup.BackpackCheckbox:ClearAllPoints(); popup.BackpackCheckbox:SetPoint("BOTTOMLEFT", 12, 50)
            local transfer = popup.CurrencyTransferToggleButton
            if transfer then
                transfer:ClearAllPoints(); transfer:SetPoint("BOTTOM", popup, "BOTTOM", 0, 14)
                transfer:SetWidth(RIGHT - 28)
            end
        end
    end
end

function Sheet:Layout()
    if InCombatLockdown() then self.pendingLayout = true; return end
    self.pendingLayout = false
    local paper = PaperDollFrame:IsShown()
    local reputation = ReputationFrame and ReputationFrame:IsShown()
    local currency = TokenFrame and TokenFrame:IsShown()
    local styled = paper or reputation or currency
    if not styled then
        CharacterFrame:SetHeight(self.originalHeight)
        CharacterFrame.Inset:ClearAllPoints()
        for _, point in ipairs(self.originalInset) do CharacterFrame.Inset:SetPoint(unpack(point)) end
        -- Other subframes use their full native width, not the paper-doll width
        -- captured at installation (reputation/currency can have different sizes).
        CharacterFrame.Inset:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", -6, PANEL_INSET_BOTTOM_OFFSET or 4)
    elseif paper then
        CharacterFrame:SetHeight(HEIGHT)
        CharacterFrame:SetWidth(LEFT + (CharacterFrame.Expanded and RIGHT + 1 or 0) + 8)
        local inset, right = CharacterFrame.Inset, CharacterFrame.InsetRight
        inset:ClearAllPoints()
        inset:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 4, -28)
        inset:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMLEFT", LEFT + 4, 6)
        Anchor(right, CharacterFrame, LEFT + 5, -28, -4, 6)
        PaperDollSidebarTabs:ClearAllPoints()
        PaperDollSidebarTabs:SetPoint("TOP", right, "TOP", 0, -8)
        PaperDollSidebarTabs:SetSize(RIGHT - 8, 40)
        PaperDollSidebarTabs:SetShown(CharacterFrame.Expanded)
        if PaperDollSidebarTabs.DecorLeft then PaperDollSidebarTabs.DecorLeft:Hide() end
        if PaperDollSidebarTabs.DecorRight then PaperDollSidebarTabs.DecorRight:Hide() end
        -- Visual order: portrait, equipment, titles; the original IDs/handlers stay.
        for position, id in ipairs({1, 3, 2}) do
            local tab = _G["PaperDollSidebarTab" .. id]
            tab:ClearAllPoints(); tab:SetPoint("CENTER", PaperDollSidebarTabs, "CENTER", (position - 2) * 43, 0)
        end
        CharacterLevelText:ClearAllPoints()
        CharacterLevelText:SetPoint("TOP", right, "TOP", 0, -49)
        CharacterLevelText:SetWidth(RIGHT - 10)
        CharacterLevelText:SetFontObject(GameFontNormalMed2Outline)
        CharacterLevelText:SetShown(CharacterFrame.Expanded)
        Anchor(CharacterStatsPane, right, 1, -HEADER, -1, 0)
        for _, pane in ipairs({PaperDollFrame.TitleManagerPane, PaperDollFrame.EquipmentManagerPane}) do
            if pane then
                Anchor(pane, right, 1, -HEADER, -1, 0)
                PaneBorder(pane)
                -- Retail's child lists are anchored to CharacterFrameInsetRight,
                -- not their pane. Reanchor those too, below the shared header.
                local equipment = pane == PaperDollFrame.EquipmentManagerPane
                Anchor(pane.ScrollBox, pane, 9, -10, -25, equipment and 42 or 12)
                pane.ScrollBar:ClearAllPoints()
                pane.ScrollBar:SetPoint("TOPLEFT", pane.ScrollBox, "TOPRIGHT", 7, -8)
                pane.ScrollBar:SetPoint("BOTTOMLEFT", pane.ScrollBox, "BOTTOMRIGHT", 7, 8)
                SkinScrollBar(pane.ScrollBar)
                if equipment then
                    pane.EquipSet:ClearAllPoints()
                    pane.EquipSet:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 10, 10)
                    pane.SaveSet:ClearAllPoints()
                    pane.SaveSet:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -10, 10)
                    pane.EquipSet:SetWidth(99); pane.SaveSet:SetWidth(99)
                end
            end
        end
        Anchor(CharacterModelScene, inset, 42, -1, -42, 14)
        ClearModelBackground()
        local camera = CharacterModelScene.GetActiveCamera and CharacterModelScene:GetActiveCamera()
        if camera and camera ~= self.fittedCamera then
            local distance = camera:GetZoomDistance()
            if Readable(distance) then camera:SetZoomDistance(distance * 0.88); self.fittedCamera = camera end
        end
        CharacterModelScene.ControlFrame:ClearAllPoints()
        CharacterModelScene.ControlFrame:SetPoint("TOP", inset, "TOP", 0, -8)
        CharacterHeadSlot:ClearAllPoints(); CharacterHeadSlot:SetPoint("TOPLEFT", inset, "TOPLEFT", 8, -48)
        CharacterHandsSlot:ClearAllPoints(); CharacterHandsSlot:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -8, -48)
        CharacterMainHandSlot:ClearAllPoints()
        CharacterMainHandSlot:SetPoint("BOTTOM", inset, "BOTTOM", -22, 26)
        CharacterSecondaryHandSlot:ClearAllPoints()
        CharacterSecondaryHandSlot:SetPoint("LEFT", CharacterMainHandSlot, "RIGHT", 6, 0)
        self.expand:Show()
        local direction = CharacterFrame.Expanded and "Prev" or "Next"
        self.expand:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-Up")
        self.expand:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-Down")
        SkinTabs()
    else
        CharacterFrame:SetHeight(HEIGHT)
        CharacterFrame:SetWidth(LEFT + RIGHT + 9)
        local inset, right = CharacterFrame.Inset, CharacterFrame.InsetRight
        inset:ClearAllPoints()
        inset:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 4, -28)
        inset:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMLEFT", LEFT + 4, 6)
        Anchor(right, CharacterFrame, LEFT + 5, -28, -4, 6)
        right:Show()
    end
    LayoutPage(ReputationFrame, ReputationFrame and ReputationFrame.ReputationDetailFrame, true)
    LayoutPage(TokenFrame, TokenFramePopup, false)
    if not paper then self.expand:Hide() end
    self.header:SetShown(paper)
    if CharacterFrame.TopTileStreaks then CharacterFrame.TopTileStreaks:SetAlpha(styled and 0 or 1) end
    if CharacterFrame.Background then CharacterFrame.Background:SetAlpha(styled and 0 or 1) end
    if CharacterFrame.Inset.Bg then CharacterFrame.Inset.Bg:SetAlpha(styled and 0 or 1) end
    if CharacterFrame.InsetRight.Bg then CharacterFrame.InsetRight.Bg:SetAlpha(styled and 0 or 1) end
    if CharacterFrame.Inset.NineSlice then CharacterFrame.Inset.NineSlice:SetAlpha(styled and 0 or 1) end
end

local function Install()
    if Sheet.installed or not CharacterFrame or not CharacterStatsPane or not CharacterModelScene then return end
    if InCombatLockdown() then return end
    Sheet.installed = true
    Sheet.originalHeight = CharacterFrame:GetHeight()
    Sheet.originalInset = {}
    for i = 1, CharacterFrame.Inset:GetNumPoints() do Sheet.originalInset[i] = {CharacterFrame.Inset:GetPoint(i)} end
    local scene = CharacterModelScene
    for _, name in ipairs({"BackgroundTopLeft", "BackgroundTopRight", "BackgroundBotLeft", "BackgroundBotRight", "BackgroundOverlay"}) do
        if scene[name] then scene[name]:SetAlpha(0) end
    end
    for _, suffix in ipairs({"TopLeft", "TopRight", "BottomLeft", "BottomRight", "Left", "Right", "Top", "Bottom", "Bottom2"}) do
        local region = _G["PaperDollInnerBorder" .. suffix]
        if region then region:SetAlpha(0) end
    end
    local bg = scene:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints(CharacterFrame.Inset); Texture(bg, "general-bg")
    local header = CharacterFrame.InsetRight:CreateTexture(nil, "ARTWORK")
    header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT"); header:SetHeight(HEADER)
    Texture(header, "stat-stonebg3")
    Sheet.header = header
    local rightBackground = CharacterFrame.InsetRight:CreateTexture(nil, "BACKGROUND", nil, -5)
    rightBackground:SetAllPoints(); Texture(rightBackground, "stat-bg")
    local expand = CreateFrame("Button", nil, PaperDollItemsFrame)
    expand:SetSize(28, 28)
    expand:SetPoint("TOPRIGHT", CharacterFrame.Inset, "TOPRIGHT", -6, -6)
    expand:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    expand:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        if CharacterFrame.Expanded then CharacterFrame:Collapse() else CharacterFrame:Expand() end
    end)
    expand:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(CharacterFrame.Expanded and "Скрыть информацию" or "Показать информацию")
        GameTooltip:Show()
    end)
    expand:SetScript("OnLeave", GameTooltip_Hide)
    Sheet.expand = expand
    TintNineSlice(CharacterFrame); TintNineSlice(CharacterFrame.InsetRight)
    SkinSlots(); CreateStats()
    hooksecurefunc(CharacterFrame, "UpdateSize", function() Sheet:Layout() end)
    hooksecurefunc("PaperDollFrame_SetLevel", function() Sheet:Layout() end)
    hooksecurefunc("PaperDollFrame_UpdateSidebarTabs", SkinTabs)
    hooksecurefunc("SetPaperDollBackground", ClearModelBackground)
    hooksecurefunc("PaperDollTitlesPane_InitButton", SkinTitle)
    local titles = PaperDollFrame.TitleManagerPane.ScrollBox
    if titles.ForEachFrame then titles:ForEachFrame(SkinTitle) end
    PaperDollFrame:HookScript("OnShow", function() Sheet:Layout(); Sheet:Refresh() end)
    PaperDollFrame:HookScript("OnHide", function() Sheet:Layout() end)
    Sheet:Layout()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
    Install()
    if Sheet.installed and Sheet.pendingLayout then Sheet:Layout() end
end)
if IsLoggedIn and IsLoggedIn() then Install() end
