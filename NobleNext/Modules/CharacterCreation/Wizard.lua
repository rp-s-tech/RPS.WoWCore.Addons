-- Wizard window: five steps over the session draft, sheet and errors from the server preview.
-- Own insecure frames parented to UIParent; no Blizzard frame is modified. No text input:
-- RP names live in TotalRP, so keyboard focus never leaves the game.
-- Choices that depend on a selected row (racial feature, trait choice, archetype details) open
-- indented right under that row; descriptions use the POI-style card (icon, title, meta, divider, body).
local _, ns = ...
local C = ns.CharacterCreation
local W = { rows = {}, cards = {} }
C.Wizard = W

local WIDTH, HEIGHT = 740, 580
local PANEL_TOP, PANEL_HEIGHT = 88, 436
local LEFT_X, LEFT_WIDTH = 12, 436
local SIDE_X, SIDE_PANEL_WIDTH = 456, 272
local LIST_WIDTH, LIST_HEIGHT = 400, 362
local SIDE_WIDTH, SIDE_HEIGHT = 236, 388
local ROW_WIDTH, INDENT = LIST_WIDTH - 24, 18
local RED, GOLD, GRAY, LABEL, GREEN, WHITE, ORANGE = "ff5a5a", "ffd100", "999999", "c8c8c8", "4cff4c", "ffffff", "ff9933"
local SOLID = "Interface\\Buttons\\WHITE8X8"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local ICONS = {
    race = "Interface\\Icons\\Achievement_Character_Human_Male",
    feature = "Interface\\Icons\\Spell_Holy_MagicalSentry",
    trait = "Interface\\Icons\\Spell_Nature_EnchantArmor",
    mastery = "Interface\\Icons\\Spell_Holy_SealOfWisdom",
    archetype = "Interface\\Icons\\Ability_Warrior_BattleShout",
    confirm = "Interface\\Icons\\INV_Misc_Note_01",
    sheet = "Interface\\Icons\\INV_Misc_Book_09",
    resources = "Interface\\Icons\\Spell_Holy_Restoration",
    combat = "Interface\\Icons\\INV_Sword_04",
    defense = "Interface\\Icons\\INV_Shield_06",
    abilities = "Interface\\Icons\\INV_Misc_Book_11",
    passives = "Interface\\Icons\\Spell_Holy_MagicalSentry",
}
local STEP_ICONS = { race = ICONS.race, trait = ICONS.trait, mastery = ICONS.mastery,
    archetype = ICONS.archetype, confirm = ICONS.confirm }
-- Atlases exist for every playable race; ogre and high elf have no race atlas in the client.
local RACE_ICONS = {
    orc = "atlas:raceicon128-orc-male", troll = "atlas:raceicon128-troll-male",
    tauren = "atlas:raceicon128-tauren-male", forsaken = "atlas:raceicon128-undead-male",
    blood_elf = "atlas:raceicon128-bloodelf-male", ogre = "Interface\\Icons\\Achievement_Reputation_Ogre",
    goblin = "atlas:raceicon128-goblin-male", pandaren = "atlas:raceicon128-pandaren-male",
    human = "atlas:raceicon128-human-male", high_elf = "Interface\\Icons\\Achievement_Character_Bloodelf_Female",
    dwarf = "atlas:raceicon128-dwarf-male", night_elf = "atlas:raceicon128-nightelf-male",
    draenei = "atlas:raceicon128-draenei-male", gnome = "atlas:raceicon128-gnome-male",
}
local ARCHETYPE_ICONS = {
    defender = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
    fighter = "Interface\\Icons\\Ability_Warrior_OffensiveStance",
    healer = "Interface\\Icons\\Spell_Holy_FlashHeal",
    caster = "Interface\\Icons\\Spell_Frost_FrostBolt02",
}
local MASTERY_ICONS = {
    skill = "Interface\\Icons\\Ability_Marksmanship",
    knowledge = "Interface\\Icons\\INV_Misc_Book_11",
    endurance = "Interface\\Icons\\Spell_Holy_DevotionAura",
    craft = "Interface\\Icons\\Trade_BlackSmithing",
}
local TRAIT_ICONS = {}
for key, name in pairs({
    full_coverage = "INV_Chest_Plate04", combo = "Ability_Rogue_SliceDice", executioner = "INV_Axe_02",
    fortunes_favorite = "INV_Misc_Coin_01", bodyguard = "Ability_Warrior_ShieldWall",
    tenacity = "Spell_Nature_Regenerate", tactical_advantage = "INV_Misc_Map_01",
    gifted = "Spell_Arcane_MindMastery", expert = "INV_Misc_Book_08", size_matters = "Ability_Hunter_Pet_Bear",
    mighty_build = "Spell_Nature_Strength", lucky = "INV_Misc_Dice_02", meditation = "Spell_Holy_MindSooth",
    magic_ward = "Spell_Arcane_ArcaneResilience", cobra_reflexes = "Ability_Hunter_Pet_WindSerpent",
    combat_experience = "Ability_Warrior_Revenge", natural_healer = "Spell_Holy_Heal",
    natural_healer_rework = "Spell_Holy_Heal", window_of_opportunity = "INV_Misc_PocketWatch_01",
    size_doesnt_matter = "Ability_Rogue_Feint", battering_ram = "Ability_Warrior_Charge", loner = "Ability_Stealth",
    wrecker = "INV_Hammer_04", tireless = "Ability_Rogue_Sprint", not_one_step_back = "Spell_Holy_SealOfProtection",
    rationality = "Spell_Arcane_ArcanePotency", summoner = "Spell_Shadow_SummonVoidWalker",
    beast_slayer = "Ability_Hunter_Pet_Wolf", field_medicine = "INV_Misc_Bandage_08",
    adrenaline_rush = "Spell_Nature_Bloodlust", reckless = "Ability_Warrior_Rampage",
    cavalier = "Ability_Mount_RidingHorse", exorcist = "Spell_Holy_Excorcism_02",
    victory_rush = "Ability_Warrior_Devastate", sky_eclipser = "Ability_Hunter_Pet_Bat",
    self_preservation = "Spell_Nature_SpiritWolf", blood_fountain = "Spell_Shadow_LifeDrain",
    phalanx = "INV_Spear_04", fully_armed = "INV_Sword_27", ambush_master = "Ability_Rogue_Ambush",
    guileless = "Spell_Holy_PureOfHeart", overwhelming_power = "Ability_Warrior_IntensifyRage",
    pack_hunt = "Ability_Hunter_Pet_Raptor",
}) do TRAIT_ICONS[key] = "Interface\\Icons\\" .. name end
W.ICONS, W.RACE_ICONS, W.ARCHETYPE_ICONS, W.MASTERY_ICONS, W.TRAIT_ICONS =
    ICONS, RACE_ICONS, ARCHETYPE_ICONS, MASTERY_ICONS, TRAIT_ICONS

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

local function Height(fs, fallback)
    return fs.GetStringHeight and fs:GetStringHeight() or fallback or 14
end

-- "atlas:<name>" uses the atlas when the client knows it; anything else is a texture path.
local function SetIcon(texture, icon)
    if not texture then return end
    if not icon then texture:Hide(); return end
    local atlas = icon:match("^atlas:(.+)$")
    local known = atlas and texture.SetAtlas
        and (not (C_Texture and C_Texture.GetAtlasInfo) or C_Texture.GetAtlasInfo(atlas) ~= nil)
    if known then
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetAtlas(atlas)
    else
        texture:SetTexture(atlas and FALLBACK_ICON or icon)
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    texture:Show()
end
W.SetIcon = SetIcon

local function Divider(parent, layer, alpha)
    local line = parent:CreateTexture(nil, layer or "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, alpha or 0.22)
    line:SetHeight(1)
    return line
end

local function Inset(parent, x, y, width, height)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    panel:SetSize(width, height)
    if panel.SetBackdrop then
        panel:SetBackdrop({ bgFile = SOLID, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        panel:SetBackdropColor(0, 0, 0, 0.45)
        panel:SetBackdropBorderColor(0.42, 0.36, 0.22, 0.85)
    end
    return panel
end

local function Signed(value)
    if type(value) ~= "number" then return tostring(value) end
    return value > 0 and ("+" .. value) or tostring(value)
end

local function SignedColor(value)
    if type(value) ~= "number" then return WHITE end
    return value > 0 and GREEN or value < 0 and RED or WHITE
end

-- POI-style card: icon and gold title, grey meta line, thin divider, white body.
-- data = { icon, title, badge?, meta?, body? }
local function NewCard(parent)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if card.SetBackdrop then
        card:SetBackdrop({ bgFile = SOLID, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        card:SetBackdropColor(0.06, 0.06, 0.075, 1)
        card:SetBackdropBorderColor(0.5, 0.44, 0.28, 0.9)
    end
    card.Icon = card:CreateTexture(nil, "ARTWORK")
    card.Icon:SetSize(22, 22)
    card.Icon:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
    card.Title = Text(card, "GameFontNormal")
    card.Title:SetPoint("LEFT", card.Icon, "RIGHT", 8, 0)
    card.Badge = Text(card, "GameFontNormalSmall", 70)
    card.Badge:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -14)
    card.Badge:SetJustifyH("RIGHT")
    card.Meta = Text(card, "GameFontHighlightSmall")
    card.Line = card:CreateTexture(nil, "ARTWORK")
    card.Line:SetColorTexture(0.9, 0.9, 0.9, 0.22)
    card.Line:SetHeight(1)
    card.Body = Text(card, "GameFontHighlightSmall")
    return card
end

local function FillCard(card, data, width)
    card:SetWidth(width)
    SetIcon(card.Icon, data.icon or FALLBACK_ICON)
    card.Title:SetWidth(width - 56 - (data.badge and 70 or 0))
    card.Title:SetText(Paint(GOLD, data.title or ""))
    card.Badge:SetText(data.badge and Paint("7a7a85", data.badge) or "")
    local y = 40
    local meta = data.meta and data.meta ~= "" and data.meta or nil
    card.Meta:ClearAllPoints()
    card.Meta:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -y)
    card.Meta:SetWidth(width - 24)
    card.Meta:SetText(meta and Paint(GRAY, meta) or "")
    if meta then y = y + Height(card.Meta) + 6 end
    card.Line:ClearAllPoints()
    card.Line:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -y)
    card.Line:SetWidth(width - 24)
    y = y + 8
    local body = data.body and data.body ~= "" and data.body or nil
    card.Body:ClearAllPoints()
    card.Body:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -y)
    card.Body:SetWidth(width - 24)
    card.Body:SetText(body or Paint(GRAY, "Описание не задано."))
    y = y + Height(card.Body) + 12
    card:SetHeight(y)
    card.data = data
    return y
end
W.FillCard = FillCard

local function HideHover()
    if W.hover then W.hover:Hide() end
end

local function ShowHover(owner, data)
    local card = W.hover
    if not card then
        card = NewCard(UIParent)
        card:SetFrameStrata("TOOLTIP")
        if card.SetClampedToScreen then card:SetClampedToScreen(true) end
        if card.SetBackdropColor then card:SetBackdropColor(0.02, 0.02, 0.03, 1) end
        W.hover = card
    end
    FillCard(card, data, 300)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", owner, "TOPRIGHT", 14, 0)
    card:Show()
end

-- Block layout shared by the sheet panel and the summary step.
-- items: { header, color?, icon? } | { label, value, color? } | { para } | { gap }.
-- Every header gets a divider under it.
local function NewPool(parent, width, labelWidth, valueJustify)
    return { parent = parent, width = width, labelWidth = labelWidth, valueJustify = valueJustify, lines = {} }
end

local function PoolLine(pool, index)
    local line = pool.lines[index]
    if not line then
        line = { Left = Text(pool.parent), Right = Text(pool.parent),
            Icon = pool.parent:CreateTexture(nil, "ARTWORK"), Line = Divider(pool.parent) }
        line.Icon:SetSize(16, 16)
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
            left:SetFontObject(item.header and "GameFontNormal" or "GameFontHighlightSmall")
            right:Hide(); line.Icon:Hide(); line.Line:Hide()
            if item.header then
                local shift = item.icon and 22 or 0
                if item.icon then
                    line.Icon:ClearAllPoints()
                    line.Icon:SetPoint("TOPLEFT", pool.parent, "TOPLEFT", 4, -y + 1)
                    SetIcon(line.Icon, item.icon)
                end
                left:SetPoint("TOPLEFT", pool.parent, "TOPLEFT", 4 + shift, -y)
                left:SetWidth(pool.width - shift)
                left:SetText(Paint(item.color or GOLD, item.header))
                line.Line:ClearAllPoints()
                line.Line:SetPoint("TOPLEFT", pool.parent, "TOPLEFT", 4, -(y + 18))
                line.Line:SetWidth(pool.width)
                line.Line:Show()
                y = y + 24
            elseif item.label then
                left:SetPoint("TOPLEFT", pool.parent, "TOPLEFT", 10, -y)
                left:SetWidth(pool.labelWidth)
                left:SetText(Paint(LABEL, item.label))
                right:ClearAllPoints()
                right:SetPoint("TOPLEFT", pool.parent, "TOPLEFT", 10 + pool.labelWidth + 4, -y)
                right:SetWidth(pool.width - pool.labelWidth - 10)
                right:SetJustifyH(pool.valueJustify)
                right:SetText(Paint(item.color or WHITE, item.value))
                right:Show()
                y = y + math.min(math.max(14, Height(right)), 40) + 4
            else
                left:SetPoint("TOPLEFT", pool.parent, "TOPLEFT", 10, -y)
                left:SetWidth(pool.width - 6)
                left:SetText(item.para)
                y = y + Height(left) + 4
            end
            left:Show()
            plain[#plain + 1] = Plain(item.header or (item.label and (item.label .. " " .. tostring(item.value))) or item.para)
        end
    end
    for i = used + 1, #pool.lines do
        local line = pool.lines[i]
        line.Left:Hide(); line.Right:Hide(); line.Icon:Hide(); line.Line:Hide()
    end
    return y, table.concat(plain, "\n")
end

local function Row(index)
    local row = W.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, W.content)
    row:SetSize(ROW_WIDTH, 26)
    row.Bg = row:CreateTexture(nil, "BACKGROUND")
    row.Bg:SetAllPoints()
    row.Bg:SetColorTexture(1, 1, 1, 0.05)
    row.Selected = row:CreateTexture(nil, "BORDER")
    row.Selected:SetAllPoints()
    row.Selected:SetColorTexture(0.85, 0.6, 0.1, 0.32)
    row.Edge = row:CreateTexture(nil, "ARTWORK")
    row.Edge:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.Edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.Edge:SetWidth(3)
    row.Edge:SetColorTexture(1, 0.82, 0, 0.9)
    row.Line = Divider(row)
    row.Line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)
    row.Line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 1)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(18, 18)
    row.Icon:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -4)
    row.Label = Text(row, "GameFontHighlight")
    row.Right = Text(row, "GameFontHighlightSmall", 120)
    row.Right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -7)
    row.Right:SetJustifyH("RIGHT")
    row.Sub = Text(row, "GameFontHighlightSmall")
    row:SetScript("OnClick", function(self)
        HideHover()
        if self.entry and self.entry.onClick and not self.entry.disabled then self.entry.onClick() end
    end)
    row:SetScript("OnEnter", function(self)
        local entry = self.entry
        if entry and entry.card and not entry.selected then ShowHover(self, entry.card) end
    end)
    row:SetScript("OnLeave", HideHover)
    W.rows[index] = row
    return row
end

local function CardBlock(index)
    local card = W.cards[index]
    if not card then
        card = NewCard(W.content)
        W.cards[index] = card
    end
    return card
end

-- entries: { header=true, text, icon?, indent?, color? } | { card={...}, indent? }
--        | { text, right?, sub?, check?, icon?, indent?, selected, disabled, card, onClick }.
local function RenderRows(entries, top)
    local y, rows, cards = top, 0, 0
    for _, entry in ipairs(entries) do
        local indent = entry.indent or 0
        if entry.card and entry.text == nil then
            cards = cards + 1
            local card = CardBlock(cards)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", W.content, "TOPLEFT", indent, -y)
            y = y + FillCard(card, entry.card, ROW_WIDTH - indent) + 6
            card:Show()
        else
            rows = rows + 1
            local row = Row(rows)
            row.entry = entry
            local width = ROW_WIDTH - indent
            row:SetWidth(width)
            local iconShift = entry.icon and 24 or 0
            row.Label:ClearAllPoints()
            row.Sub:ClearAllPoints()
            SetIcon(row.Icon, entry.icon)
            local height = 26
            if entry.header then
                y = y + 6
                row.Label:SetPoint("TOPLEFT", row, "TOPLEFT", 4 + iconShift, -6)
                row.Label:SetWidth(width - 8 - iconShift)
                row.Label:SetText(Paint(entry.color or GOLD, entry.text))
                row.Right:SetText("")
                row.Sub:SetText("")
                row.Bg:Hide(); row.Selected:Hide(); row.Edge:Hide(); row.Line:Show()
                if entry.icon then row.Icon:ClearAllPoints(); row.Icon:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -3) end
            else
                if entry.icon then row.Icon:ClearAllPoints(); row.Icon:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -4) end
                local mark = entry.check ~= nil and (entry.check and "[x] " or "[ ] ") or ""
                row.Label:SetPoint("TOPLEFT", row, "TOPLEFT", 10 + iconShift, -6)
                row.Label:SetWidth(width - 140 - iconShift)
                if entry.disabled then
                    row.Label:SetText(Paint(GRAY, mark .. entry.text))
                elseif entry.selected then
                    row.Label:SetText(Paint(GOLD, mark .. entry.text))
                else
                    row.Label:SetText(Paint(WHITE, mark .. entry.text))
                end
                row.Right:SetText(entry.right and Paint(GRAY, entry.right) or "")
                row.Sub:SetPoint("TOPLEFT", row, "TOPLEFT", 10 + iconShift, -23)
                row.Sub:SetWidth(width - 20 - iconShift)
                row.Sub:SetText(entry.sub and Paint(entry.subColor or GRAY, entry.sub) or "")
                row.Bg:Show(); row.Line:Hide()
                if entry.selected then row.Selected:Show(); row.Edge:Show() else row.Selected:Hide(); row.Edge:Hide() end
                if entry.sub then height = 28 + math.max(14, Height(row.Sub)) end
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", W.content, "TOPLEFT", indent, -y)
            row:SetHeight(height)
            row:SetEnabled(not entry.header and not entry.disabled)
            row:Show()
            y = y + height + 3
        end
    end
    for i = rows + 1, #W.rows do W.rows[i]:Hide() end
    for i = cards + 1, #W.cards do W.cards[i]:Hide() end
    return y
end

local function Option(text, selected, onClick, card, disabledReason)
    return {
        text = text, title = text, selected = selected, onClick = onClick, card = card,
        disabled = disabledReason ~= nil, sub = disabledReason,
    }
end

local function NameOf(list, key)
    local entry = C.Find(list, key)
    return entry and (entry.name or entry.key) or "не выбрано"
end

local function RaceIcon(race) return race and RACE_ICONS[race.key] or ICONS.race end

local function RaceCard(race, unavailable)
    local names = {}
    for _, f in ipairs(race.features or {}) do names[#names + 1] = f.name or f.key end
    local body
    if unavailable then
        body = Paint(ORANGE, unavailable)
    elseif C.IsStubRace(race) then
        body = Paint(GRAY, C.STUB_TAG)
    else
        body = "Расовые особенности (выберите одну):\n" .. table.concat(names, "\n")
    end
    local size = race.sizeName or race.size
    return { icon = RaceIcon(race), title = race.name or race.key, meta = size and ("Размер: " .. size) or nil, body = body }
end

local function FeatureCard(race, feature)
    local meta = "Расовая особенность: " .. tostring(race.name or race.key)
    if tonumber(feature.masteryFree) then meta = meta .. "  |  +" .. feature.masteryFree .. " очко Мастерства" end
    return { icon = ICONS.feature, title = feature.name or feature.key, meta = meta, body = feature.text }
end

local function TraitCard(trait, unavailable)
    local meta = "Общая черта" .. (trait.needsChoice and "  |  требует выбрать Мастерство" or "")
    local body = trait.text
    if unavailable then body = Paint(ORANGE, unavailable) .. (body and ("\n\n" .. body) or "") end
    return { icon = TRAIT_ICONS[trait.key] or ICONS.trait, title = trait.name or trait.key, meta = meta, body = body }
end

local function ArchetypeCard(archetype)
    local body = archetype.description and (archetype.description .. "\n\n") or ""
    if archetype.featureName then
        body = body .. Paint(GOLD, archetype.featureName) .. ": " .. tostring(archetype.featureText or "")
    end
    return { icon = ARCHETYPE_ICONS[archetype.key] or ICONS.archetype, title = archetype.name or archetype.key,
        meta = archetype.featureName and ("Особенность архетипа: " .. archetype.featureName) or "Архетип", body = body }
end

local STEP_RENDER = {}

function STEP_RENDER.race(d, o)
    local entries = { { header = true, text = "Раса", icon = ICONS.race } }
    local selected = C.SelectedRace()
    for _, race in ipairs(o.races) do
        local unavailable = race.available == false and (race.unavailableReason or "недоступно в текущем каталоге") or nil
        local size = race.sizeName or race.size
        local entry = Option(race.name or race.key, d.race == race.key,
            function() C.SetField("race", race.key) end, RaceCard(race, unavailable), unavailable)
        entry.icon = RaceIcon(race)
        entry.right = size and ("размер: " .. size) or nil
        if not unavailable and C.IsStubRace(race) then entry.sub = C.STUB_TAG end
        entries[#entries + 1] = entry
        if selected and selected.key == race.key then
            local stub = C.IsStubRace(race)
            local feature = C.SelectedFeature()
            entries[#entries + 1] = { header = true, indent = INDENT, icon = ICONS.feature,
                color = (feature or stub) and GOLD or ORANGE,
                text = stub and "Расовая особенность" or "Расовая особенность: выберите одну" }
            for _, f in ipairs(race.features or {}) do
                local option = Option(f.name or f.key, d.racialFeature == f.key,
                    function() C.SetField("racialFeature", f.key) end, FeatureCard(race, f))
                option.indent = INDENT
                if stub then option.sub = C.STUB_TAG end
                if tonumber(f.masteryFree) then option.right = "+" .. f.masteryFree .. " Мастерства" end
                entries[#entries + 1] = option
            end
            if feature then entries[#entries + 1] = { card = FeatureCard(race, feature), indent = INDENT } end
        end
    end
    local desc = "Выберите расу: под ней откроется выбор расовой особенности. Наведите на строку, чтобы увидеть описание."
    if C.Scope() == "race" then
        desc = Paint(ORANGE, "Обновление расовых данных: выберите расу и особенность заново. Остальные шаги закреплены.")
            .. "\n\n" .. desc
    end
    return desc, entries
end

function STEP_RENDER.trait(d, o)
    local entries = { { header = true, text = "Общая черта (одна)", icon = ICONS.trait } }
    local selected = C.SelectedTrait()
    for _, trait in ipairs(o.traits) do
        local unavailable = trait.available == false and (trait.unavailableReason or "недоступна") or nil
        local entry = Option(trait.name or trait.key, d.trait == trait.key,
            function() C.SetField("trait", trait.key) end, TraitCard(trait, unavailable), unavailable)
        entry.icon = TRAIT_ICONS[trait.key] or ICONS.trait
        if trait.needsChoice and not unavailable then entry.right = "+ выбор" end
        entries[#entries + 1] = entry
        if selected and selected.key == trait.key then
            entries[#entries + 1] = { card = TraitCard(trait), indent = INDENT }
            if trait.needsChoice and type(trait.choices) == "table" then
                entries[#entries + 1] = { header = true, indent = INDENT, icon = ICONS.mastery,
                    color = d.traitChoice and GOLD or ORANGE, text = "Дополнительный выбор: Мастерство" }
                for _, choice in ipairs(trait.choices) do
                    local key = C.ChoiceKey(choice)
                    local option = Option(C.ChoiceName(choice), d.traitChoice == key,
                        function() C.SetField("traitChoice", key) end,
                        type(choice) == "table" and choice.text and { icon = MASTERY_ICONS[key] or ICONS.mastery,
                            title = C.ChoiceName(choice), body = choice.text } or nil)
                    option.indent, option.icon = INDENT, MASTERY_ICONS[key] or ICONS.mastery
                    entries[#entries + 1] = option
                end
            end
        end
    end
    return "Выберите одну общую черту. Описание выбранной черты открывается под ней.", entries
end

function STEP_RENDER.mastery(d)
    local budget, extra = C.MasteryBudget()
    local used = C.MasteryUsed()
    for i, key in ipairs(C.MasteryKeys()) do
        local line = W.mastery[i]
        if line then
            local value = d.mastery[key] or 0
            line.key = key
            SetIcon(line.Icon, MASTERY_ICONS[key] or ICONS.mastery)
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
    return desc, {}, 4 * 32 + 6
end

function STEP_RENDER.archetype(d, o)
    local entries = { { header = true, text = "Архетип", icon = ICONS.archetype } }
    for _, archetype in ipairs(o.archetypes) do
        local entry = Option(archetype.name or archetype.key, d.archetype == archetype.key,
            function() C.SetField("archetype", archetype.key) end, ArchetypeCard(archetype))
        entry.icon = ARCHETYPE_ICONS[archetype.key] or ICONS.archetype
        entry.sub = archetype.featureName and ("Особенность: " .. archetype.featureName) or nil
        entries[#entries + 1] = entry
        if d.archetype == archetype.key then
            entries[#entries + 1] = { card = ArchetypeCard(archetype), indent = INDENT }
        end
    end
    local desc = "Архетип не связан с классом WoW. Описание выбранного архетипа открывается под ним."
    if C.Scope() == "archetype" then
        desc = Paint(ORANGE, "Смена архетипа: выберите новый архетип. Остальные шаги закреплены.") .. "\n\n" .. desc
    end
    return desc, entries
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
        { header = "Происхождение", icon = RaceIcon(race) },
        { label = "Раса:", value = race and (race.name or race.key) or Paint(ORANGE, "не выбрана") },
    }
    local size = race and (race.sizeName or race.size)
    if size then items[#items + 1] = { label = "Размер:", value = size } end
    items[#items + 1] = { label = "Особенность:", value = featureText }
    items[#items + 1] = { gap = 10 }
    items[#items + 1] = { header = "Развитие", icon = ICONS.archetype }
    if C.state and C.state.rpLevel then items[#items + 1] = { label = "RP-уровень:", value = C.state.rpLevel } end
    items[#items + 1] = { label = "Черта:", value = trait and (trait.name or trait.key) or Paint(ORANGE, "не выбрана") }
    if trait and trait.needsChoice then
        items[#items + 1] = { label = "Выбор черты:", value = choiceName and tostring(choiceName) or Paint(ORANGE, "не выбран") }
    end
    items[#items + 1] = { label = "Архетип:", value = d.archetype and NameOf(o.archetypes, d.archetype) or Paint(ORANGE, "не выбран") }
    items[#items + 1] = { gap = 10 }
    items[#items + 1] = { header = "Мастерство", icon = ICONS.mastery }
    local any = false
    for _, key in ipairs(C.MasteryKeys()) do
        local value = d.mastery[key] or 0
        if value > 0 then
            any = true
            items[#items + 1] = { label = C.MasteryName(key) .. ":", value = "+" .. value, color = GREEN }
        end
    end
    if not any then items[#items + 1] = { para = Paint(ORANGE, "Очки ещё не распределены.") } end
    if #C.warnings > 0 then
        items[#items + 1] = { gap = 10 }
        items[#items + 1] = { header = "Внимание", color = ORANGE }
        for _, warning in ipairs(C.warnings) do
            local text = type(warning) == "table" and (warning.message_ru or warning.code) or warning
            items[#items + 1] = { para = Paint(ORANGE, "* " .. tostring(text)) }
        end
    end
    items[#items + 1] = { gap = 10 }
    items[#items + 1] = { para = Paint(GRAY, "Архетип можно сменить позже кнопкой под листом персонажа: "
        .. "первый раз бесплатно, затем за серебро. Остальное меняет ведущий.") }
    return items
end

function STEP_RENDER.confirm()
    return "Проверьте выбор. Итоговые характеристики рассчитывает сервер (панель справа).", {}
end

-- A server error about an empty choice repeats the "Ещё не указано" checklist; only real errors are shown.
local CHOICE_FIELDS = { race = true, racialFeature = true, trait = true, traitChoice = true, archetype = true }
local function ShownErrors(step)
    local list = {}
    for _, err in ipairs(C.VisibleErrors(step)) do
        local field = type(err.field) == "string" and err.field:match("^%a+") or nil
        if not (field and CHOICE_FIELDS[field] and C.draft and C.draft[field] == nil) then list[#list + 1] = err end
    end
    return list
end

local SHEET_BLOCKS = {
    { "Ресурсы", ICONS.resources, { { "rpLevel", "RP-уровень" }, { "maxHealth", "ОЗ" }, { "maxEnergy", "ОЭ" },
        { "woundLimit", "Лимит Ран" }, { "fateDie", "Кость Судьбы" } } },
    { "Боевые бонусы", ICONS.combat, { { "accuracy", "Меткость", true }, { "healing", "Исцеление", true },
        { "evasion", "Уклонение", true }, { "resistance", "Сопротивление", true } } },
    { "Защита и движение", ICONS.defense, { { "armor", "Броня" }, { "block", "Блок" }, { "speed", "Скорость" } } },
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
    local errors = ShownErrors()
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
        for _, def in ipairs(block[3]) do
            local value = sheet[def[1]]
            if def[1] == "block" and value ~= nil then value = BlockText(value) end
            if value ~= nil then
                rows[#rows + 1] = { label = def[2] .. ":", value = def[3] and Signed(value) or tostring(value),
                    color = def[3] and SignedColor(value) or WHITE }
            end
        end
        if #rows > 0 then
            items[#items + 1] = { header = block[1], icon = block[2] }
            for _, row in ipairs(rows) do items[#items + 1] = row end
            items[#items + 1] = { gap = 8 }
        end
    end
    if type(sheet.mastery) == "table" then
        items[#items + 1] = { header = "Мастерство", icon = ICONS.mastery }
        for _, key in ipairs(C.MasteryKeys()) do
            local value = sheet.mastery[key]
            if value ~= nil then
                items[#items + 1] = { label = C.MasteryName(key) .. ":", value = Signed(value), color = SignedColor(value) }
            end
        end
        items[#items + 1] = { gap = 8 }
    elseif sheet.mastery ~= nil then
        items[#items + 1] = { header = "Мастерство", icon = ICONS.mastery }
        items[#items + 1] = { para = tostring(sheet.mastery) }
        items[#items + 1] = { gap = 8 }
    end
    if sheet.abilitySlots ~= nil then
        items[#items + 1] = { header = "Способности", icon = ICONS.abilities }
        items[#items + 1] = { label = "Ячейки:", value = tostring(sheet.abilitySlots) }
        items[#items + 1] = { gap = 8 }
    end
    local passives = type(sheet.passive) == "table" and sheet.passive or {}
    if #passives > 0 then
        items[#items + 1] = { header = "Особенности", icon = ICONS.passives }
        for _, passive in ipairs(passives) do
            items[#items + 1] = { para = PassiveText(passive) }
            items[#items + 1] = { gap = 4 }
        end
    end
    return items
end

-- Tab state: "locked" | "error" | "missing" | "done" | "open"; the text keeps the colour and the "*" mark.
local function TabState(i)
    if C.StepLocked(i) then return "locked" end
    if #ShownErrors(i) > 0 then return "error" end
    if i < #C.STEPS and C.options and C.draft and C.StepMissing(i) then return "missing" end
    if i < #C.STEPS and C.options and C.draft then return "done" end
    return "open"
end

local TAB_COLORS = { locked = GRAY, error = RED, missing = ORANGE, done = WHITE, open = WHITE }
local TAB_BARS = { error = { 1, 0.35, 0.35, 0.9 }, missing = { 1, 0.6, 0.2, 0.8 }, done = { 0.3, 0.85, 0.3, 0.6 } }

local function PaintTab(tab, i, step)
    local state = TabState(i)
    local title = i .. ". " .. C.STEPS[i].title .. (state == "missing" and " *" or "")
    local active = i == step
    tab:SetText(Paint(active and state ~= "error" and state ~= "missing" and GOLD or TAB_COLORS[state], title))
    if tab.Bg then
        if active then tab.Bg:SetColorTexture(0.24, 0.18, 0.06, 0.95)
        elseif state == "locked" then tab.Bg:SetColorTexture(0.05, 0.05, 0.06, 0.9)
        else tab.Bg:SetColorTexture(0.1, 0.1, 0.12, 0.95) end
        local bar = active and { 1, 0.82, 0, 1 } or TAB_BARS[state]
        if bar then tab.Bar:SetColorTexture(bar[1], bar[2], bar[3], bar[4]); tab.Bar:Show() else tab.Bar:Hide() end
        tab.Bar:SetHeight(active and 3 or 2)
    end
end

-- The local hint and a server error often say the same thing; show it once.
local function StepMessages(step, o, d)
    local list, seen = {}, {}
    local function Add(color, text)
        local key = Plain(text):gsub("[%s%.]+$", "")
        if seen[key] then return end
        seen[key] = true
        list[#list + 1] = Paint(color, text)
    end
    local missing = o and d and C.LocalMissing(step)
    if missing and step ~= #C.STEPS then Add(ORANGE, missing) end
    for _, err in ipairs(ShownErrors(step)) do Add(RED, C.ErrorText(err)) end
    if #list == 0 and o and d then
        if step < #C.STEPS then
            Add(GREEN, "Шаг заполнен.")
        elseif C.CanConfirm() then
            Add(GREEN, "Всё готово: проверьте выбор и нажмите «Подтвердить».")
        end
    end
    return table.concat(list, "\n")
end

local function HideIdleScrollBar(scroll)
    local bar = scroll.ScrollBar
    if type(bar) == "table" and bar.SetHideIfUnscrollable then bar:SetHideIfUnscrollable(true) end
end

local function FitScroll(scroll, contentHeight, viewHeight)
    if contentHeight <= viewHeight and scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
end

function W.Render()
    local f = W.frame
    if not f or not f:IsShown() then return end
    local o, d, step = C.options, C.draft, C.step
    for i, tab in ipairs(f.tabs) do
        PaintTab(tab, i, step)
        tab:SetEnabled(not C.StepLocked(i))
    end
    SetIcon(f.stepIcon, STEP_ICONS[C.STEPS[step].key])
    f.stepTitle:SetText("Шаг " .. step .. " из " .. #C.STEPS .. ": " .. C.STEPS[step].title)
    for _, line in ipairs(W.mastery) do line:Hide() end
    local desc, entries, controls = "", {}, 0
    if o and d then
        desc, entries, controls = STEP_RENDER[C.STEPS[step].key](d, o)
        controls = controls or 0
    else
        desc = C.loading and "Загрузка вариантов с сервера…" or "Варианты не получены. Закройте и откройте мастер ещё раз."
    end
    f.stepError:SetText(StepMessages(step, o, d))
    W.desc:SetText(desc)
    local top = math.max(28, Height(W.desc, 28)) + 10
    W.controlsTop = top
    for i, line in ipairs(W.mastery) do
        line:ClearAllPoints(); line:SetPoint("TOPLEFT", W.content, "TOPLEFT", 0, -(top + (i - 1) * 32))
    end
    local height = RenderRows(entries, top + controls)
    if o and d and C.STEPS[step].key == "confirm" then
        height, W.summaryPlain = RenderBlocks(W.summary, SummaryItems(d, o), top)
    else
        RenderBlocks(W.summary, {}, top)
        W.summaryPlain = ""
    end
    W.content:SetHeight(height + 8)
    FitScroll(W.scroll, height + 8, LIST_HEIGHT)
    local sheetHeight
    sheetHeight, W.sheetPlain = RenderBlocks(W.sheet, SheetItems(), 0)
    f.sheetContent:SetHeight(sheetHeight + 8)
    FitScroll(f.sheetScroll, sheetHeight + 8, SIDE_HEIGHT)
    local back, forward = C.NextStep(step, -1), C.NextStep(step, 1)
    f.back:SetEnabled(back ~= step and not C.pending)
    local last = step == #C.STEPS
    if last then f.next:Hide(); f.confirm:Show() else f.next:Show(); f.confirm:Hide() end
    f.next:SetEnabled(not last and o ~= nil and forward ~= step and not C.LocalMissing(step))
    f.confirm:SetEnabled(C.CanConfirm())
    f.confirm:SetText(C.pending and "Сохранение…" or "Подтвердить")
    local status = C.status
    if not status and C.GetState() == "complete" then
        status = "Персонаж уже подтверждён. Архетип можно сменить кнопкой под листом персонажа."
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
    -- Solid dark fill: the tooltip texture let the world and other windows show through.
    f:SetBackdrop({ bgFile = SOLID, edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    f:SetBackdropColor(0.035, 0.035, 0.045, 0.97)
    f:SetBackdropBorderColor(0.78, 0.66, 0.36, 1)
    f:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "NobleNextCharacterCreation") end

    local band = f:CreateTexture(nil, "BORDER")
    band:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
    band:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    band:SetHeight(34)
    band:SetColorTexture(0.14, 0.11, 0.05, 0.9)
    local bandLine = Divider(f, "ARTWORK", 0.55)
    bandLine:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -40)
    bandLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -40)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -15)
    title:SetText("Создание RP-персонажа")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Flat step tabs: dark plate, coloured underline (gold active, green done, orange missing, red error).
    f.tabs = {}
    for i in ipairs(C.STEPS) do
        local tab = CreateFrame("Button", nil, f)
        tab:SetSize(136, 26)
        tab:SetPoint("TOPLEFT", f, "TOPLEFT", 14 + (i - 1) * 142, -48)
        tab.Bg = tab:CreateTexture(nil, "BACKGROUND")
        tab.Bg:SetAllPoints()
        tab.Bar = tab:CreateTexture(nil, "ARTWORK")
        tab.Bar:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
        tab.Bar:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
        local hl = tab:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.07)
        local label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("CENTER", tab, "CENTER", 0, 1)
        tab:SetFontString(label)
        tab:SetScript("OnClick", function() C.GoTo(i) end)
        f.tabs[i] = tab
    end
    local tabLine = Divider(f)
    tabLine:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -81)
    tabLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -81)

    local left = Inset(f, LEFT_X, PANEL_TOP, LEFT_WIDTH, PANEL_HEIGHT)
    f.left = left
    f.stepIcon = left:CreateTexture(nil, "ARTWORK")
    f.stepIcon:SetSize(20, 20)
    f.stepIcon:SetPoint("TOPLEFT", left, "TOPLEFT", 10, -8)
    f.stepTitle = Text(left, "GameFontNormal", LEFT_WIDTH - 50)
    f.stepTitle:SetPoint("LEFT", f.stepIcon, "RIGHT", 8, 0)
    f.stepError = Text(left, "GameFontHighlightSmall", LEFT_WIDTH - 24)
    f.stepError:SetPoint("TOPLEFT", left, "TOPLEFT", 12, -32)
    local leftLine = Divider(left)
    leftLine:SetPoint("TOPLEFT", left, "TOPLEFT", 8, -60)
    leftLine:SetPoint("TOPRIGHT", left, "TOPRIGHT", -8, -60)

    local scroll = CreateFrame("ScrollFrame", nil, left, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", left, "TOPLEFT", 8, -66)
    scroll:SetSize(LIST_WIDTH, LIST_HEIGHT)
    HideIdleScrollBar(scroll)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(LIST_WIDTH - 20, LIST_HEIGHT)
    scroll:SetScrollChild(content)
    W.scroll, W.content = scroll, content
    W.desc = Text(content, "GameFontHighlightSmall", LIST_WIDTH - 28)
    W.desc:SetPoint("TOPLEFT", content, "TOPLEFT", 4, 0)
    W.desc:SetTextColor(0.72, 0.72, 0.72)
    W.summary = NewPool(content, LIST_WIDTH - 32, 120, "LEFT")

    W.mastery = {}
    for i = 1, 4 do
        local line = CreateFrame("Frame", nil, content)
        line:SetSize(LIST_WIDTH - 30, 30)
        line.Bg = line:CreateTexture(nil, "BACKGROUND")
        line.Bg:SetAllPoints()
        line.Bg:SetColorTexture(1, 1, 1, 0.05)
        line.Icon = line:CreateTexture(nil, "ARTWORK")
        line.Icon:SetSize(20, 20)
        line.Icon:SetPoint("LEFT", line, "LEFT", 6, 0)
        line.Label = Text(line, "GameFontNormal", 130)
        line.Label:SetPoint("LEFT", line, "LEFT", 34, 0)
        line.Value = Text(line, "GameFontNormal", 40)
        line.Value:SetPoint("LEFT", line, "LEFT", 170, 0)
        line.Value:SetJustifyH("RIGHT")
        line.minus = ns.CreateNGButton(line, "-", 26, 22)
        line.minus:SetPoint("LEFT", line, "LEFT", 226, 0)
        line.minus:SetScript("OnClick", function() C.AdjustMastery(line.key, -1) end)
        line.plus = ns.CreateNGButton(line, "+", 26, 22)
        line.plus:SetPoint("LEFT", line.minus, "RIGHT", 6, 0)
        line.plus:SetScript("OnClick", function() C.AdjustMastery(line.key, 1) end)
        W.mastery[i] = line
    end

    local side = Inset(f, SIDE_X, PANEL_TOP, SIDE_PANEL_WIDTH, PANEL_HEIGHT)
    f.side = side
    local sideIcon = side:CreateTexture(nil, "ARTWORK")
    sideIcon:SetSize(20, 20)
    sideIcon:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -8)
    SetIcon(sideIcon, ICONS.sheet)
    local sideTitle = Text(side, "GameFontNormal", SIDE_PANEL_WIDTH - 50)
    sideTitle:SetPoint("LEFT", sideIcon, "RIGHT", 8, 0)
    sideTitle:SetText("Лист персонажа " .. Paint(GRAY, "(расчёт сервера)"))
    local sideLine = Divider(side)
    sideLine:SetPoint("TOPLEFT", side, "TOPLEFT", 8, -34)
    sideLine:SetPoint("TOPRIGHT", side, "TOPRIGHT", -8, -34)
    local sideScroll = CreateFrame("ScrollFrame", nil, side, "ScrollFrameTemplate")
    sideScroll:SetPoint("TOPLEFT", side, "TOPLEFT", 8, -40)
    sideScroll:SetSize(SIDE_WIDTH, SIDE_HEIGHT)
    HideIdleScrollBar(sideScroll)
    f.sheetScroll = sideScroll
    f.sheetContent = CreateFrame("Frame", nil, sideScroll)
    f.sheetContent:SetSize(SIDE_WIDTH, SIDE_HEIGHT)
    sideScroll:SetScrollChild(f.sheetContent)
    W.sheet = NewPool(f.sheetContent, SIDE_WIDTH - 8, 130, "RIGHT")

    local footLine = Divider(f)
    footLine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 50)
    footLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 50)
    f.back = ns.CreateNGButton(f, "Назад", 110, 26)
    f.back:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
    f.back:SetScript("OnClick", function() C.GoTo(C.NextStep(C.step, -1)) end)
    f.next = ns.CreateNGButton(f, "Далее", 110, 26)
    f.next:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
    f.next:SetScript("OnClick", function() C.GoTo(C.NextStep(C.step, 1)) end)
    f.confirm = ns.CreateNGButton(f, "Подтвердить", 130, 26)
    f.confirm:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
    f.confirm:SetScript("OnClick", function() C.Confirm() end)
    f.status = Text(f, "GameFontHighlightSmall", WIDTH - 300)
    f.status:SetPoint("BOTTOM", f, "BOTTOM", 0, 22)
    f.status:SetJustifyH("CENTER")
    f:SetScript("OnShow", W.Render)
    f:SetScript("OnHide", HideHover)
    return f
end

function C.IsOpen()
    return W.frame ~= nil and W.frame:IsShown()
end

function C.Open()
    local f = W.frame or Build()
    if C.options then C.EnsureDraft() end
    local scoped = C.SCOPE_STEP[C.Scope() or ""]
    if scoped or C.StepLocked(C.step) then
        C.step = scoped or 1
        C.visited[C.step] = true
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
C.OnArchetypeReset = function() C.Open() end

local HELP = "/rps create — мастер создания RP-персонажа; /rps race reset — сбросить устаревшие расовые данные; "
    .. "/rps archetype reset — сменить архетип (первый раз бесплатно)."

local function Slash(msg)
    local words = {}
    for word in tostring(msg or ""):gmatch("%S+") do words[#words + 1] = word:lower() end
    local cmd, arg = words[1] or "", words[2] or ""
    local reset = arg == "reset" or arg == "сброс"
    if cmd == "create" or cmd == "создать" then
        C.Open()
    elseif (cmd == "race" or cmd == "раса") and reset then
        C.ConfirmRaceReset()
    elseif (cmd == "archetype" or cmd == "архетип") and reset then
        C.ConfirmArchetypeReset()
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
