-- RP rows in the existing character sheet.
local _, ns = ...
local R = ns.RPSClient
local archetypes = { defender = "Защитник", fighter = "Боец", healer = "Целитель", caster = "Заклинатель" }
local races = {
    orc = "Орк",
    troll = "Тролль",
    tauren = "Таурен",
    forsaken = "Отрекшийся",
    blood_elf = "Эльф крови",
    sin_dorei = "Син'дорай",
    ogre = "Огр",
    goblin = "Гоблин",
    pandaren = "Пандарен",
    human = "Человек",
    high_elf = "Высший эльф",
    dwarf = "Дворф",
    night_elf = "Ночной эльф",
    draenei = "Дреней",
    gnome = "Гном",
}
local sections = {
    { "Общее", { general = true } },
    { "Основные характеристики", { combat = true, mastery = true } },
    { "Оружие", { weapon = true } },
}

local SELF_STATE_TEXT = {
    loading = "Ожидание данных сервера…",
    none    = "Нет профиля.",
    error   = "Данные недоступны: показаны последние подтверждённые значения.",
}

-- nil when the profile is confirmed; otherwise the user-facing reason.
function R.SelfStateText()
    return SELF_STATE_TEXT[R.GetSelfDisplayState()]
end

-- The technical human/fighter of an unconfirmed profile is not shown as the player's choice.
local function ChoiceConfirmed()
    local C = ns.CharacterCreation
    return not C or C.ChoiceConfirmed()
end

local CREATION_LABELS = {
    none        = "RP-персонаж не настроен",
    legacy      = "Старый профиль: подтвердите выбор",
    reconfigure = "Разрешена перенастройка",
}

local function Value(def, p)
    if def.key == "rp_race" then
        if not ChoiceConfirmed() then return "Раса не выбрана" end
        return races[p.raceId] or p.raceId or "Не указана"
    end
    if def.key == "rp_archetype" then
        if not ChoiceConfirmed() then return "Архетип не выбран" end
        return archetypes[p.archetype] or p.archetype or "Не указан"
    end
    if def.key == "health" or def.key == "energy" then
        local cur, max = p.curHealth, p.maxHealth
        if def.key == "energy" then cur, max = p.curEnergy, p.maxEnergy end
        if cur == nil or max == nil then return R.DISPLAY_STATE_TEXT.loading end
        local text = R.FormatResource(cur, max)
        if R.GetSelfDisplayState() == "error" then text = "|cff999999" .. text .. "|r" end
        return text
    end
    if def.key == "weapon_damage" then return p.weaponDice end
    if def.key == "shield_block" then return p.blockDice end
    if def.key == "armor" or def.key == "speed" then return tostring(p[def.key] or 0) end
    local value = p.stats and p.stats[def.key]
    if value == nil then return "-" end
    return value > 0 and ("+" .. value) or tostring(value)
end

local function Pickup(def)
    if not IsShiftKeyDown() or InCombatLockdown() or not def.spellId or def.spellId <= 0 then return end
    if C_Spell and C_Spell.PickupSpell then C_Spell.PickupSpell(def.spellId)
    elseif PickupSpell then PickupSpell(def.spellId) end
end

local levelHooked = false
function R.UpdateCharacterHeaderLevelText()
    if not CharacterLevelText or not R.profile then return end
    local arch = archetypes[R.profile.archetype] or R.profile.archetype or "Боец"
    if not ChoiceConfirmed() then arch = "Архетип не выбран," end
    local lvl = tonumber(R.profile.level) or 1
    CharacterLevelText:SetText(string.format("|cffffd100%s|r %d-го уровня", arch, lvl))
    if not levelHooked and PaperDollFrame_SetLevel and hooksecurefunc then
        levelHooked = true
        hooksecurefunc("PaperDollFrame_SetLevel", function()
            if R.profile then R.UpdateCharacterHeaderLevelText() end
        end)
    end
end

-- "Настроить RP-персонажа" under the sheet while the server reports none/legacy/reconfigure;
-- "Сбросить расовые данные" while SyncProfile.creation.raceUpdateAvailable is true;
-- "Сменить архетип" with its price while SyncProfile.creation.archetypeResetCost is present.
-- Visible buttons stack upwards from the bottom of the sheet.
local function UpdateCreationControls(parent, view)
    local C = ns.CharacterCreation
    local state = C and C.GetState()
    local setup = CREATION_LABELS[state]
    local raceUpdate = C and C.RaceUpdateAvailable and C.RaceUpdateAvailable() or false
    local archetypeCost = C and C.ArchetypeResetCost and C.ArchetypeResetCost() or nil
    local label = setup or (raceUpdate and "Доступно обновление расовых данных") or nil
    local box = R.creationBox
    if (label or archetypeCost) and not box then
        box = CreateFrame("Frame", nil, parent)
        box:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 6)
        box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -8, 6)
        box:SetHeight(44)
        box.Label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        box.Label:SetPoint("TOP", box, "TOP", 0, 0)
        box.Button = ns.CreateNGButton(box, "Настроить RP-персонажа", 180, 22)
        box.Button:SetScript("OnClick", function() ns.CharacterCreation.Open() end)
        box.ResetButton = ns.CreateNGButton(box, "Сбросить расовые данные", 180, 22)
        box.ResetButton:SetScript("OnClick", function() ns.CharacterCreation.ConfirmRaceReset() end)
        box.ArchetypeButton = ns.CreateNGButton(box, "Сменить архетип", 180, 22)
        box.ArchetypeButton:SetScript("OnClick", function() ns.CharacterCreation.ConfirmArchetypeReset() end)
        R.creationBox = box
    end
    local shown = {}
    if box then
        local wanted = { { box.Button, setup ~= nil }, { box.ResetButton, raceUpdate },
            { box.ArchetypeButton, archetypeCost ~= nil } }
        for _, item in ipairs(wanted) do
            if item[2] then shown[#shown + 1] = item[1]; item[1]:Show() else item[1]:Hide() end
        end
        for i, button in ipairs(shown) do
            button:ClearAllPoints()
            button:SetPoint("BOTTOM", box, "BOTTOM", 0, (i - 1) * 24)
        end
        if archetypeCost then
            box.ArchetypeButton:SetText("Сменить архетип (" .. C.FormatMoney(archetypeCost) .. ")")
            box.ArchetypeButton:SetEnabled(not C.archetypeResetPending)
        end
        box.Label:SetText(label or "")
        box:SetHeight(#shown * 24 + (label and 20 or 4))
        if #shown > 0 then box:Show() else box:Hide() end
    end
    local inset = #shown > 0 and (#shown * 24 + (label and 28 or 12)) or 6
    if view and view.bottomInset ~= inset then
        view:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -25, inset)
        view.bottomInset = inset
    end
end

function R.RenderSheet(parent)
    if not R.profile then
        if R.sheet then R.sheet:Hide() end
        if R.creationBox then R.creationBox:Hide() end
        return false
    end
    R.UpdateCharacterHeaderLevelText()
    local view = R.sheet
    if not view then
        view = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
        view:SetPoint("TOPLEFT", parent, "TOPLEFT", 9, -6)
        view:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -25, 6)
        view.content = CreateFrame("Frame", nil, view)
        view.content:SetWidth(195)
        view:SetScrollChild(view.content)
        view:SetScript("OnSizeChanged", function(_, width)
            if width and width > 20 then
                local w = width - 4
                view.content:SetWidth(w)
                for _, h in ipairs(view.headers or {}) do
                    h:SetWidth(math.max(120, w - 8))
                end
                for _, r in ipairs(view.rows or {}) do
                    r:SetWidth(w)
                end
            end
        end)
        view.rows = {}
        view.headers = {}
        R.sheet = view
    end
    view:Show()
    UpdateCreationControls(parent, view)
    local contentWidth = (view.content.GetWidth and view.content:GetWidth()) or 195
    if not contentWidth or contentWidth <= 0 then contentWidth = 195 end
    if view.generation ~= R.generation then
        for _, row in ipairs(view.rows) do row:Hide() end
        local y, index = 0, 0
        local definitions = {
            {
                key = "rp_race",
                name = "Раса",
                category = "general",
                diceFormula = "none",
                identity = true,
                description = "Раса из RP-профиля.",
            },
            {
                key = "rp_archetype",
                name = "Архетип",
                category = "general",
                diceFormula = "none",
                identity = true,
                description = "Архетип из RP-профиля.",
            },
        }
        for _, def in ipairs(R.registry) do definitions[#definitions + 1] = def end
        for i, section in ipairs(sections) do
            local header = view.headers[i]
            if not header then
                header = CreateFrame("Frame", nil, view.content)
                header:SetSize(contentWidth - 8, 20)
                local banner = header:CreateTexture(nil, "BACKGROUND")
                banner:SetAllPoints()
                local texture = ns.CharacterFrameTextures.title
                banner:SetTexture("Interface\\AddOns\\NobleNext\\Assets\\CharacterFrame\\" .. texture[1])
                banner:SetTexCoord(texture[2] / 1024, texture[3] / 1024, texture[4] / 1024, texture[5] / 1024)
                header.Label = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                header.Label:SetPoint("CENTER")
                view.headers[i] = header
            end
            header:SetSize(contentWidth - 8, 20)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", view.content, "TOPLEFT", 4, -y)
            header.Label:SetText(section[1])
            y = y + 21
            for _, def in ipairs(definitions) do
                if section[2][def.category] then
                    index = index + 1
                    local row = view.rows[index]
                    if not row then
                        row = CreateFrame("Button", nil, view.content)
                        row:SetSize(contentWidth, 18)
                        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                        row:RegisterForDrag("LeftButton")
                        row.Label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        row.Label:SetPoint("LEFT", row, "LEFT", 3, 0)
                        row.Label:SetWidth(120)
                        row.Label:SetJustifyH("LEFT")
                        if row.Label.SetWordWrap then row.Label:SetWordWrap(false) end
                        row.Value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        row.Value:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                        row.Value:SetWidth(72)
                        row.Value:SetJustifyH("RIGHT")
                        if row.Value.SetWordWrap then row.Value:SetWordWrap(false) end
                        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                        row:SetScript("OnDragStart", function(self) self.dragged = true; Pickup(self.def) end)
                        row:SetScript("OnClick", function(self, button)
                            if self.dragged then self.dragged = nil; return end
                            if IsShiftKeyDown() then Pickup(self.def); return end
                            if self.def.diceFormula ~= "none" then R.Roll(self.def.key, button == "RightButton") end
                        end)
                        row:SetScript("OnEnter", function(self)
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            local title = (R.GetLocalizedStatName and R.GetLocalizedStatName(self.def.key)) or self.def.name
                            GameTooltip:SetText(title)
                            GameTooltip:AddLine(self.def.description or "", 1, 1, 1, true)
                            if self.def.key == "health" then GameTooltip:AddLine("Раны: " .. R.profile.curWounds .. " / " .. R.profile.maxWounds) end
                            if self.def.key == "energy" then GameTooltip:AddLine("Потрачено за раунд: " .. R.profile.energySpentRound .. " / 6") end
                            if self.def.diceFormula ~= "none" then
                                GameTooltip:AddLine("ЛКМ: бросок. ПКМ: Судьба за 3 ОЭ.")
                                GameTooltip:AddLine("Shift + перетаскивание: спелл на панель.")
                            end
                            local creation = self.def.identity and ns.CharacterCreation and ns.CharacterCreation.GetState()
                            if creation then
                                GameTooltip:AddLine("Настройка RP-персонажа: " .. (ns.CharacterCreation.STATE_TEXT[creation] or creation))
                            end
                            local stateText = R.SelfStateText()
                            if stateText then GameTooltip:AddLine(stateText, 1, 0.3, 0.3) end
                            GameTooltip:Show()
                        end)
                        row:SetScript("OnLeave", GameTooltip_Hide)
                        view.rows[index] = row
                    end
                    row.def = def
                    local labelName = def.identity and def.name or ((R.GetLocalizedStatName and R.GetLocalizedStatName(def.key)) or def.name)
                    row.Label:SetText(labelName .. ":")
                    row.Label:SetWidth(def.identity and 65 or 120)
                    row.Value:SetWidth(def.identity and 125 or 70)
                    row:SetSize(contentWidth, 18)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, -y)
                    row:Show()
                    y = y + 18
                end
            end
            y = y + 4
        end
        view.content:SetHeight(y + 4)
        view.generation = R.generation
    end
    for _, row in ipairs(view.rows) do
        if row:IsShown() then row.Value:SetText(Value(row.def, R.profile)) end
    end
    return true
end
