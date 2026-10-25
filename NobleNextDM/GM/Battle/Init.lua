-- Loaded through the NobleNextDM private extension namespace.
-- GM/Battle/Init.lua — боевая панель (ОЗ, броня, характеристики)

local _, ns = ...

local function SendGmCommand(cmd)
    if not ns.RunGmCommand(cmd) then
        ns.PrintError("Не удалось отправить команду: " .. tostring(cmd))
    end
end

local function IsNpcTarget()
    return UnitExists("target") and not UnitIsPlayer("target")
end

local function CreateLabeledEditBox(parent, label, x, y, width)
    local lbl = ns.CreateNGLabel(parent, label)
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local box = ns.CreateNGEditBox(parent, label .. "Box", width or 50, 20)
    box:SetNumeric(true)
    box:SetText("0")
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 70, y)
    return box
end

local function StretchSection(section, relativeTo, yOffset)
    section:SetPoint("TOPLEFT", relativeTo, "TOPLEFT", 0, yOffset or 0)
    section:SetPoint("TOPRIGHT", relativeTo, "TOPRIGHT", 0, yOffset or 0)
end

-- ---------------------------------------------------------------------------
-- Module initialization
-- ---------------------------------------------------------------------------
local function InitBattleModule(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:Hide()

    local pad = CreateFrame("Frame", nil, f)
    ns.Layout.Fill(pad, f, { left = 8, right = 8, top = 8, bottom = 8 })

    -- Primary stats
    local StatsSection = ns.CreateNGSection(pad, "ОЗ / Броня / Энергия / Фокус / Раны", nil, 150)
    StretchSection(StatsSection, pad, 0)

    local HpBox = CreateLabeledEditBox(StatsSection, "ОЗ:", 10, -25, 50)
    local ApBox = CreateLabeledEditBox(StatsSection, "Броня:", 320, -25, 50)
    local EnBox = CreateLabeledEditBox(StatsSection, "Энергия:", 10, -55, 50)
    local FocusBox = CreateLabeledEditBox(StatsSection, "Фокус:", 320, -55, 50)
    local WoundBox = CreateLabeledEditBox(StatsSection, "Раны:", 10, -85, 50)

    local function CreateBattleButton(parentFrame, text, x, y, width, leftCmd, rightCmd)
        local btn = ns.CreateNGButton(parentFrame, text, width or 70, 22)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", x, y)
        btn:SetScript("OnClick", function(self, button)
            local cmd = (button == "RightButton" and rightCmd) and rightCmd or leftCmd
            if cmd then SendGmCommand(cmd()) end
        end)
        return btn
    end

    -- HP row
    CreateBattleButton(StatsSection, "Set", 130, -25, 36,
        function() return ".rps character set hp " .. (HpBox:GetText() or "0") end,
        function() return ".rps character set armor " .. (HpBox:GetText() or "0") end)
    CreateBattleButton(StatsSection, "Dam", 170, -25, 36,
        function() return ".rps character dam hp " .. (HpBox:GetText() or "0") end,
        function() return ".rps character remove armor " .. (HpBox:GetText() or "0") end)
    CreateBattleButton(StatsSection, "Add", 210, -25, 36,
        function() return ".rps character add hp " .. (HpBox:GetText() or "0") end,
        function() return ".rps character add armor " .. (HpBox:GetText() or "0") end)

    -- Armor row (using ApBox)
    CreateBattleButton(StatsSection, "Set", 440, -25, 36,
        function() return ".rps character set armor " .. (ApBox:GetText() or "0") end)
    CreateBattleButton(StatsSection, "Dam", 480, -25, 36,
        function() return ".rps character remove armor " .. (ApBox:GetText() or "0") end)
    CreateBattleButton(StatsSection, "Add", 520, -25, 36,
        function() return ".rps character add armor " .. (ApBox:GetText() or "0") end)

    -- Energy row
    CreateBattleButton(StatsSection, "Set", 130, -55, 36,
        function() return ".rps character set en " .. (EnBox:GetText() or "0") end)
    CreateBattleButton(StatsSection, "Dam", 170, -55, 36,
        function() return ".rps character dam en " .. (EnBox:GetText() or "0") end)
    CreateBattleButton(StatsSection, "Add", 210, -55, 36,
        function() return ".rps character add en " .. (EnBox:GetText() or "0") end)

    -- Focus row
    CreateBattleButton(StatsSection, "Set", 440, -55, 36,
        function() return ".rps character set focus " .. (FocusBox:GetText() or "0") end)
    CreateBattleButton(StatsSection, "Dam", 480, -55, 36,
        function() return ".rps character remove focus " .. (FocusBox:GetText() or "0") end)
    CreateBattleButton(StatsSection, "Add", 520, -55, 36,
        function() return ".rps character add focus " .. (FocusBox:GetText() or "0") end)

    -- Wound row
    CreateBattleButton(StatsSection, "Рана", 130, -85, 50,
        function() return ".rps character set wound " .. (WoundBox:GetText() or "0") end)
    CreateBattleButton(StatsSection, "WakeUp", 185, -85, 60,
        function() return ".rps character wakeup" end)

    -- NPC characteristics
    local CharSection = ns.CreateNGSection(pad, "Характеристики NPC", nil, 100)
    CharSection:SetPoint("TOPLEFT", StatsSection, "BOTTOMLEFT", 0, -12)
    CharSection:SetPoint("TOPRIGHT", StatsSection, "BOTTOMRIGHT", 0, -12)

    local StrBox = CreateLabeledEditBox(CharSection, "Сила:", 10, -25, 50)
    local AgiBox = CreateLabeledEditBox(CharSection, "Ловк:", 160, -25, 50)
    local IntBox = CreateLabeledEditBox(CharSection, "Инт:", 310, -25, 50)
    local PhysBox = CreateLabeledEditBox(CharSection, "ФизЗащ:", 460, -25, 50)
    local MagBox = CreateLabeledEditBox(CharSection, "МагЗащ:", 10, -55, 50)

    local SetStatsBtn = ns.CreateNGButton(CharSection, "Установить", 120, 24)
    SetStatsBtn:SetPoint("TOPLEFT", CharSection, "TOPLEFT", 460, -55)
    SetStatsBtn:SetScript("OnClick", function()
        if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
        SendGmCommand(".npcsetstat 1 " .. (StrBox:GetText() or "0"))
        SendGmCommand(".npcsetstat 2 " .. (AgiBox:GetText() or "0"))
        SendGmCommand(".npcsetstat 3 " .. (IntBox:GetText() or "0"))
        SendGmCommand(".npcsetstat 5 " .. (PhysBox:GetText() or "0"))
        SendGmCommand(".npcsetstat 6 " .. (MagBox:GetText() or "0"))
    end)

    -- NPC Roll
    local RollSection = ns.CreateNGSection(pad, "Бросок NPC", nil, 70)
    RollSection:SetPoint("TOPLEFT", CharSection, "BOTTOMLEFT", 0, -12)
    RollSection:SetPoint("TOPRIGHT", CharSection, "BOTTOMRIGHT", 0, -12)

    local RollBox = ns.CreateNGEditBox(RollSection, "RollBox", 180, 22)
    RollBox:SetPoint("TOPLEFT", RollSection, "TOPLEFT", 10, -25)
    RollBox:SetText(UnitIsPlayer("target") and (GetUnitName("target") or "") or "")

    local RollTypeBox = ns.CreateNGEditBox(RollSection, "RollTypeBox", 50, 22)
    RollTypeBox:SetNumeric(true)
    RollTypeBox:SetText("1")
    RollTypeBox:SetPoint("TOPLEFT", RollBox, "TOPRIGHT", 10, 0)

    local RollBtn = ns.CreateNGButton(RollSection, "Бросок", 90, 24)
    RollBtn:SetPoint("TOPLEFT", RollTypeBox, "TOPRIGHT", 10, 0)
    RollBtn:SetScript("OnClick", function()
        local target = RollBox:GetText()
        local t = RollTypeBox:GetText() or "1"
        if target and target ~= "" then
            if target:find("%s") then
                target = '"' .. target:gsub('"', '\\"') .. '"'
            end
            SendGmCommand(".npcroll " .. target .. " " .. t)
        else
            SendGmCommand(".npcroll " .. t)
        end
    end)

    -- Effects
    local EffectsSection = ns.CreateNGSection(pad, "Эффекты", nil, 70)
    EffectsSection:SetPoint("TOPLEFT", RollSection, "BOTTOMLEFT", 0, -12)
    EffectsSection:SetPoint("TOPRIGHT", RollSection, "BOTTOMRIGHT", 0, -12)

    local EffectBox = ns.CreateNGEditBox(EffectsSection, "EffectBox", 80, 22)
    EffectBox:SetNumeric(true)
    EffectBox:SetText("1")
    EffectBox:SetPoint("TOPLEFT", EffectsSection, "TOPLEFT", 10, -25)

    local EffectButtons = {
        { "Бафф", ".rps character set buff " },
        { "Дебафф", ".rps character set debuff " },
        { "Статус", ".rps character set status " },
        { "Действие", ".rps character set actions " },
        { "Рана", ".rps character set harm " },
    }

    for i, info in ipairs(EffectButtons) do
        local btn = ns.CreateNGButton(EffectsSection, info[1], 60, 22)
        btn:SetPoint("TOPLEFT", EffectsSection, "TOPLEFT", 110 + (i - 1) * 70, -25)
        btn:SetScript("OnClick", function()
            if not IsNpcTarget() then ns.PrintError("Возьмите в цель NPC."); return end
            SendGmCommand(info[2] .. (EffectBox:GetText() or "1"))
        end)
    end

    return f
end

-- ---------------------------------------------------------------------------
-- Slash command & registration
-- ---------------------------------------------------------------------------
C_Timer.After(0, function()
    ns.RegisterSlashCommand("NNBATTLE", function() ns.ShowModule("Бой") end, "nnbattle")
end)

ns.RegisterModule("Бой", InitBattleModule, "Боевая панель (ОЗ/броня/энергия/характеристики)")
