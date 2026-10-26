-- RP rows in the existing character sheet.
local _, ns = ...
local R = ns.RPSClient
local archetypes = { defender = "Защитник", fighter = "Боец", healer = "Целитель", caster = "Заклинатель" }
local races = {
    human = "Человек",
    troll = "Тролль",
    orc = "Орк",
    forsaken = "Отрекшийся",
    tauren = "Таурен",
    goblin = "Гоблин",
    sin_dorei = "Син'дорай",
    ogre = "Огр",
}
local sections = {
    { "Общее", { general = true } },
    { "Основные характеристики", { combat = true, mastery = true } },
    { "Оружие", { weapon = true } },
}

local function Value(def, p)
    if def.key == "rp_race" then return races[p.raceId] or (UnitRace and UnitRace("player")) or p.raceId or "Не указана" end
    if def.key == "rp_archetype" then return archetypes[p.archetype] or p.archetype or "Не указан" end
    if def.key == "health" then return R.FormatResource(p.curHealth, p.maxHealth) end
    if def.key == "energy" then return R.FormatResource(p.curEnergy, p.maxEnergy) end
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
    local lvl = tonumber(R.profile.level) or 1
    CharacterLevelText:SetText(string.format("|cffffd100%s|r %d-го уровня", arch, lvl))
    if not levelHooked and PaperDollFrame_SetLevel and hooksecurefunc then
        levelHooked = true
        hooksecurefunc("PaperDollFrame_SetLevel", function()
            if R.profile then R.UpdateCharacterHeaderLevelText() end
        end)
    end
end

function R.RenderSheet(parent)
    if not R.profile then return false end
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
                            if not R.available then GameTooltip:AddLine("Нет подтверждения сервера.", 1, 0.3, 0.3) end
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
