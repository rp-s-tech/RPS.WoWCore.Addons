-- «Развитие»: native levels/XP from the server (RP level = server level - 9). Read-only for the player:
-- XP comes from the DM, the level rises automatically, there is no "level up" button.
local _, ns = ...
local R = ns.RPSClient
local P = { data = nil }
ns.Progression = P

local ERRORS = {
    invalid_request_id = "Некорректный идентификатор запроса.",
    invalid_amount     = "Количество опыта: целое число от 1 до 500.",
    invalid_reason     = "Укажите причину (3–200 символов).",
    invalid_target     = "Выберите игрока.",
    target_unavailable = "Игрок не в сети.",
    target_dead        = "Мёртвый персонаж не получает опыт.",
    at_cap             = "Персонаж уже на максимальном RP-уровне (10).",
    xp_not_applied     = "Сервер не начислил опыт.",
    receipt_unavailable = "Журнал выдачи недоступен.",
    receipt_failed     = "Опыт начислен, но квитанция не сохранена.",
    pending_recovery   = "Выдача опыта ожидает подтверждения. Проверяйте тот же запрос.",
    receipt_incomplete = "Старая запись выдачи требует сверки ведущим.",
    xp_commit_unavailable = "Выдача опыта временно недоступна: требуется обновление сервера.",
    xp_curve_mismatch  = "Таблица опыта сервера не соответствует настройкам развития.",
    xp_config_mismatch = "Настройки сервера не разрешают точную выдачу опыта.",
    xp_level_cap_mismatch = "Предел уровня сервера не соответствует RP-развитию. Проверьте конфигурацию сервера.",
    xp_gain_blocked    = "У игрока отключён опыт или действует бонус приглашённого друга.",
    invalid_native_level = "Уровень персонажа вне диапазона развития.",
}

function P.ErrorText(code)
    return ERRORS[code] or (R and R.FormatSystemError and R.FormatSystemError(code)) or tostring(code)
end

local function CharDB()
    NobleNextCharDB = NobleNextCharDB or {}
    return NobleNextCharDB
end

function P.Lines(data)
    data = data or P.data
    if type(data) ~= "table" then return { "Данные развития загружаются…" } end
    local lines = {}
    lines[#lines + 1] = string.format("RP-уровень: %d из %d (уровень персонажа %d)",
        data.rpLevel or 1, data.maxRpLevel or 10, data.serverLevel or 0)
    if data.atCap then
        lines[#lines + 1] = string.format("Максимальный уровень. Накоплено опыта: %d", data.xpTotal or 0)
    else
        local xp, needed = data.xp or 0, data.xpNeeded or 0
        lines[#lines + 1] = string.format("Опыт: %d / %d (до %d-го уровня осталось %d)",
            xp, needed, (data.rpLevel or 1) + 1, math.max(0, needed - xp))
        lines[#lines + 1] = string.format("Всего опыта: %d", data.xpTotal or 0)
    end
    local total = type(data.slots) == "table" and #data.slots or 0
    lines[#lines + 1] = string.format("Персональные способности: открыто %d из %d%s",
        data.abilitySlots or 0, total, data.gifted and " (Одарённость)" or "")
    for _, slot in ipairs(type(data.slots) == "table" and data.slots or {}) do
        lines[#lines + 1] = string.format("  Слот %d — %d ОЭ, RP-уровень %d: %s", slot.slot or 0, slot.cost or 0,
            slot.unlockLevel or 0, slot.open and "открыт" or "закрыт")
    end
    local nextUnlock = data.nextUnlock
    if type(nextUnlock) == "table" then
        lines[#lines + 1] = string.format("Следующее открытие: RP-уровень %d — %s", nextUnlock.rpLevel or 0,
            tostring(nextUnlock.text or ""))
    else
        lines[#lines + 1] = "Все слоты персональных способностей открыты."
    end
    lines[#lines + 1] = "Опыт выдаёт ведущий; уровень повышается автоматически."
    return lines
end

local function NotifyLevelUp(from, to)
    local text = string.format("Новый RP-уровень: %d (был %d)", to, from)
    P.lastLevelUp = { from = from, to = to }
    if ns.Print then ns.Print(text) end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(text, 1, 0.82, 0.3) end
    if ns.Emit then ns.Emit("RPS_LEVEL_UP", P.lastLevelUp) end
end

local handlers = {}

function handlers.Progression(_, payload)
    if type(payload) ~= "table" or type(payload.rpLevel) ~= "number" or type(payload.serverLevel) ~= "number" then return end
    local db = CharDB()
    local seen = tonumber(db.rpsProgressionSeenLevel)
    local levelUp = type(payload.levelUp) == "table" and payload.levelUp or nil
    -- The last seen level survives /reload and relog, so a level gained while the window was closed is still announced.
    if levelUp and type(levelUp.to) == "number" and levelUp.to > (tonumber(levelUp.from) or levelUp.to) then
        if not seen or seen < levelUp.to then NotifyLevelUp(seen or levelUp.from, levelUp.to) end
    elseif seen and payload.rpLevel > seen then
        NotifyLevelUp(seen, payload.rpLevel)
    end
    db.rpsProgressionSeenLevel = payload.rpLevel
    P.data = payload
    if ns.Emit then ns.Emit("RPS_PROGRESSION_CHANGED", payload) end
    if P.Render then P.Render() end
end

function handlers.DmGrantXpResult(_, payload)
    if type(payload) ~= "table" then return end
    if ns.Emit then ns.Emit("RPS_XP_GRANT_RESULT", payload) end
end
P.handlers = handlers

local attachedTo
local function Attach()
    local H = R and R.handlers
    if not H or attachedTo == H then return end
    for name, fn in pairs(handlers) do H[name] = fn end
    attachedTo = H
end
if R then
    local bind = R.Bind
    function R.Bind()
        local ok = bind()
        Attach()
        return ok
    end
    Attach()
end

local lastRequest
function P.Request(force)
    local now = GetTime and GetTime() or 0
    if not force and lastRequest and now - lastRequest < 1 then return false end
    lastRequest = now
    return R ~= nil and R.Send("RequestProgression")
end

if ns.Subscribe then
    ns.Subscribe("RPS_PROFILE_CHANGED", "Progression", function(profile)
        if type(profile) == "table" and (not P.data or profile.level ~= P.data.sheetLevel) then P.Request() end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:SetScript("OnEvent", function()
    if C_Timer and C_Timer.After then C_Timer.After(0.5, function() P.Request(true) end) else P.Request(true) end
end)

-- /rps is shared with the character creation wizard: "dev" is handled here, everything else goes to the previous handler.
local SLASH_KEY = "NOBLENEXTRPS"
local function InstallSlash()
    if not SlashCmdList then return end
    local previous = SlashCmdList[SLASH_KEY]
    if previous and previous == P.Slash then return end
    function P.Slash(msg)
        local cmd = (tostring(msg or ""):match("^%s*(%S*)") or ""):lower()
        if cmd == "dev" or cmd == "развитие" then
            if P.Toggle then P.Toggle() end
        elseif previous then
            previous(msg)
        elseif ns.Print then
            ns.Print("/rps dev — развитие персонажа.")
        end
    end
    if previous then
        SlashCmdList[SLASH_KEY] = P.Slash
    elseif ns.RegisterSlashCommand then
        ns.RegisterSlashCommand(SLASH_KEY, P.Slash, { "rps" })
    else
        _G["SLASH_" .. SLASH_KEY .. "1"] = "/rps"
        SlashCmdList[SLASH_KEY] = P.Slash
    end
end
P.InstallSlash = InstallSlash
if C_Timer and C_Timer.After then C_Timer.After(0, InstallSlash) else InstallSlash() end
