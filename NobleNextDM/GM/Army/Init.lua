-- Loaded through the NobleNextDM private extension namespace.
-- GM/Army/Init.lua — модуль управления армией NPC

local _, ns = ...

local AIO_HANDLER = "ArmyHandlers"

local CMD_SELECT_TARGET = "AddTargetToSelection"
local CMD_UNSELECT      = "UnselectAll"
local CMD_DELETE        = "CallTableToDel"
local CMD_SET_EMOTE     = "SetEmoteToNPC"

local selectedCount = 0

-- Incoming AIO handlers live only in NobleNextLua GM/Army/NNArmyClient.lua.
-- Addon keeps state + On* callbacks for the AIO client bridge.
_G.NobleNextArmy = _G.NobleNextArmy or {}

local function UpdateCounter(label, count)
    selectedCount = count or 0
    label:SetText("Выделено NPC: " .. selectedCount)
end

local function GetNpcTable()
    return (_G.NobleNextArmy and _G.NobleNextArmy.NPCTable) or {}
end

-- ---------------------------------------------------------------------------
-- Module initialization
-- ---------------------------------------------------------------------------
local function InitArmyModule(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:Hide()

    local CounterLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    CounterLabel:SetText("Выделено NPC: 0")
    CounterLabel:SetTextColor(ns.COLORS.goldRaw.r, ns.COLORS.goldRaw.g, ns.COLORS.goldRaw.b)
    CounterLabel:SetPoint("TOP", f, "TOP", 0, -10)
    f.counter = CounterLabel

    local ContentSection = ns.CreateNGSection(f, "Выделение и действия", nil, 158)
    ContentSection:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -40)
    ContentSection:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -40)

    local function CreateArmyButton(text, column, y, onClick, style)
        local btn = ns.NNL.Widgets.CreateButton(ContentSection, {
            text = text, width = 220, height = 28, style = style,
        })
        btn:SetPoint("TOPLEFT", ContentSection, "TOPLEFT", 14 + column * 232, y)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    CreateArmyButton("+ Выделить цель", 0, -36, function()
        ns.AIOHandle(AIO_HANDLER, CMD_SELECT_TARGET)
    end, "primary")

    CreateArmyButton("Снять выделение", 0, -72, function()
        ns.AIOHandle(AIO_HANDLER, CMD_UNSELECT)
    end, "ghost")

    CreateArmyButton("Убрать из мира", 1, -36, function()
        ns.Confirm.Show({
            text = "Убрать выделенных NPC из мира? Их записи в базе данных сохранятся.",
            onAccept = function()
                ns.AIOHandle(AIO_HANDLER, CMD_DELETE, GetNpcTable())
            end,
        })
    end, "danger")

    -- The server's DeleteAllNpcInGroupPerm currently only despawns creatures.
    -- Do not present that alias as permanent database deletion.
    local permanent = CreateArmyButton("Удаление из базы недоступно", 1, -72, nil, "ghost")
    permanent:SetEnabledEx(false, "Серверный обработчик пока выполняет только деспавн NPC.")
    local selectionHint = ns.CreateNGLabel(ContentSection, "Выберите NPC в мире и добавьте его в группу. Лимит: 50 NPC.")
    selectionHint:SetPoint("TOPLEFT", ContentSection, "TOPLEFT", 14, -116)
    selectionHint:SetPoint("RIGHT", ContentSection, "RIGHT", -14, 0)
    selectionHint:SetJustifyH("LEFT")

    local EmoteSection = ns.CreateNGSection(f, "Постоянная анимация группы", nil, 142)
    EmoteSection:SetPoint("TOPLEFT", ContentSection, "BOTTOMLEFT", 0, -12)
    EmoteSection:SetPoint("TOPRIGHT", ContentSection, "BOTTOMRIGHT", 0, -12)

    local EmoteLabel = ns.CreateNGLabel(EmoteSection, "ID анимации:")
    EmoteLabel:SetPoint("TOPLEFT", EmoteSection, "TOPLEFT", 14, -76)

    local EmoteBox = ns.CreateNGEditBox(EmoteSection, "EmoteBox", 100, 24)
    EmoteBox:SetPoint("TOPLEFT", EmoteSection, "TOPLEFT", 126, -70)
    EmoteBox:SetNumeric(true)
    EmoteBox:SetText("0")

    local EmoteBtn = ns.CreateNGButton(EmoteSection, "Применить", 108, 26)
    EmoteBtn:SetPoint("LEFT", EmoteBox, "RIGHT", 15, 0)
    local function applyEmote()
        local id = tonumber(EmoteBox:GetText())
        if not id or id < 0 or id > 4294967295 or id ~= math.floor(id) then
            ns.PrintError("Введите целый ID анимации от 0 до 4294967295.")
            return
        end
        ns.AIOHandle(AIO_HANDLER, CMD_SET_EMOTE, GetNpcTable(), id)
        EmoteBox:ClearFocus()
    end
    EmoteBtn:SetScript("OnClick", applyEmote)
    EmoteBox:SetScript("OnEnterPressed", applyEmote)
    -- ArmyHandlers.SetEmoteToNPC calls EmoteState, not SetStandState.
    local presets = { { "Сброс", 0 }, { "Сидеть", 13 }, { "Спать", 12 }, { "Мёртв", 65 } }
    local presetLabel = ns.CreateNGLabel(EmoteSection, "Пресет:")
    presetLabel:SetPoint("TOPLEFT", EmoteSection, "TOPLEFT", 14, -40)
    local presetDropdown = ns.NNL.Widgets.CreateDropdown(EmoteSection, {
        name = "NobleNextArmyEmoteDropdown", width = 220, defaultText = "Свой ID анимации",
        menu = function(_, root)
            for _, preset in ipairs(presets) do
                root:CreateRadio(preset[1], function(value) return tonumber(EmoteBox:GetText()) == value end,
                    function(value) EmoteBox:SetText(tostring(value)) end, preset[2])
            end
        end,
    })
    presetDropdown:SetPoint("TOPLEFT", EmoteSection, "TOPLEFT", 126, -34)
    EmoteBox:HookScript("OnTextChanged", function() presetDropdown:GenerateMenu() end)
    local emoteHint = ns.CreateNGLabel(EmoteSection, "Выберите пресет или введите ID, затем нажмите «Применить». Анимация зависит от модели NPC.")
    emoteHint:SetPoint("TOPLEFT", EmoteSection, "TOPLEFT", 14, -108)
    emoteHint:SetPoint("RIGHT", EmoteSection, "RIGHT", -14, 0)
    emoteHint:SetJustifyH("LEFT")

    local NoteLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    NoteLabel:SetText("Движение группы: способности управления NPC (.npccontrol).")
    NoteLabel:SetTextColor(0.6, 0.6, 0.6, 1)
    NoteLabel:SetPoint("TOPLEFT", EmoteSection, "BOTTOMLEFT", 14, -14)

    f.UpdateCounter = function(count) UpdateCounter(CounterLabel, count) end

    return f
end

-- ---------------------------------------------------------------------------
-- Server → Client callbacks
-- ---------------------------------------------------------------------------
function _G.NobleNextArmy.OnSelectNewNPCs(NPCTable)
    local list = NPCTable or {}
    local module = ns.modules and ns.modules["Армия"]
    if module and module.frame and module.frame.UpdateCounter then
        module.frame.UpdateCounter(#list)
    end
    ns.ShowModule("Армия")
end

function _G.NobleNextArmy.OnUnselectAll()
    local module = ns.modules and ns.modules["Армия"]
    if module and module.frame and module.frame.UpdateCounter then
        module.frame.UpdateCounter(0)
    end
end

function _G.NobleNextArmy.OnDelete()
    local module = ns.modules and ns.modules["Армия"]
    if module and module.frame and module.frame.UpdateCounter then
        module.frame.UpdateCounter(0)
    end
end

function _G.NobleNextArmy.OnDeletePerm()
    local module = ns.modules and ns.modules["Армия"]
    if module and module.frame and module.frame.UpdateCounter then
        module.frame.UpdateCounter(0)
    end
end

function _G.NobleNextArmy.OnEmoteFrame()
    ns.ShowModule("Армия")
end

function _G.NobleNextArmy.OnCommand(callType, xPos, yPos, zPos)
    ns.AIOHandle(AIO_HANDLER, "CommandToNPC", GetNpcTable(), callType, xPos, yPos, zPos)
end

-- ---------------------------------------------------------------------------
-- Slash command & registration
-- ---------------------------------------------------------------------------
C_Timer.After(0, function()
    ns.RegisterSlashCommand("NNARMY", function() ns.ShowModule("Армия") end, "nnarmy")
end)

ns.RegisterModule("Армия", InitArmyModule, "Управление армией NPC")
