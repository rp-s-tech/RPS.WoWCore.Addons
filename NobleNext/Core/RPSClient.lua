-- Public player route; server-side self/scene checks own authorization.
local _, ns = ...
local R = {
    registry = {},
    profile = nil,
    target = nil,
    focus = nil,
    remembered = nil,
    unitsByGuid = {},
    prompts = {},
    promptOrder = {},
    available = false,
    generation = 0,
}
ns.RPSClient = R

local FALLBACK_STAT_NAMES = {
    health        = "Здоровье",
    energy        = "Энергия",
    armor         = "Броня",
    speed         = "Скорость",
    accuracy      = "Меткость",
    healing       = "Исцеление",
    evasion       = "Уклонение",
    resistance    = "Сопротивление",
    skill         = "Навык",
    knowledge     = "Знание",
    endurance     = "Упорство",
    craft         = "Ремесло",
    weapon_damage = "Урон (Оружие)",
    shield_block  = "Блокирование (Щит)",
}

local ERROR_LABELS_RU = {
    rate_limited               = "Слишком частые запросы, подождите 1 сек.",
    insufficient_energy        = "Недостаточно ОЭ.",
    not_enough_energy          = "Недостаточно ОЭ.",
    round_budget_exhausted     = "Превышен лимит траты ОЭ за раунд.",
    round_limit                = "Превышен лимит траты ОЭ за раунд.",
    target_outside_system      = "С этой целью нельзя взаимодействовать.",
    out_of_system              = "С этой целью нельзя взаимодействовать.",
    incapacitated              = "Вы тяжело ранены (0 ОЗ) — действия недоступны.",
    wounded_zero_hp            = "Вы тяжело ранены (0 ОЗ) — действия недоступны.",
    permission_denied          = "Недостаточно прав доступа.",
    access_denied              = "Недостаточно прав доступа.",
    target_changed             = "Цель изменилась перед сохранением.",
    stale_profile              = "Данные устарели, запрошена повторная синхронизация.",
    actor_busy                 = "Персонаж занят обработкой предыдущего действия.",
    request_pending            = "Запрос уже обрабатывается сервером.",
    request_conflict           = "Конфликт идентификатора запроса.",
    pending_recovery           = "Результат действия ожидает восстановления. Повторите тот же запрос.",
    receipt_incomplete         = "Сохранённый результат требует сверки ведущим.",
    invalid_receipt            = "Не удалось прочитать сохранённый результат.",
    reaction_unavailable       = "Окно защитной реакции уже закрыто.",
    reaction_queue_full        = "Очередь защитных реакций цели заполнена.",
    system_unavailable         = "Действие временно недоступно.",
    save_failed                = "Ошибка сохранения профиля в БД.",
    partial_commit             = "Частичная ошибка сохранения в БД.",
    profile_unavailable        = "Ролевой профиль не найден.",
    target_unavailable         = "Выберите корректную цель.",
    stat_not_rollable          = "Эта характеристика не предусматривает броска.",
    invalid_dice               = "Некорректная формула кости.",
    invalid_field              = "Некорректное числовое значение поля.",
    invalid_stats              = "Некорректные значения характеристик.",
    no_incoming_attack         = "Нет входящей атаки.",
    attack_no_target           = "Для атаки выберите цель.",
    attack_pending             = "Предыдущая атака по этой цели ещё ждёт ответа.",
    invalid_action             = "Некорректное действие.",
    invalid_reaction           = "Некорректная защитная реакция.",
}

function R.GetLocalizedStatName(statKey)
    for _, def in ipairs(R.registry or {}) do
        if def.key == statKey and def.name and def.name ~= "" then
            return def.name
        end
    end
    return FALLBACK_STAT_NAMES[statKey] or tostring(statKey)
end

function R.FormatSystemError(code)
    return ERROR_LABELS_RU[code] or tostring(code)
end

-- Current health/energy may exceed the maximum; the surplus is shown as "(+N)".
function R.FormatResource(current, maximum, label)
    current, maximum = tonumber(current) or 0, tonumber(maximum) or 0
    local text = (label and (label .. ": ") or "") .. current .. " / " .. maximum
    if current > maximum then
        text = text .. " |cffffd24d(+" .. (current - maximum) .. ")|r"
    end
    return text
end

-- Wire GUID contract: the server's tostring(ObjectGuid) and the client's UnitGUID share
-- one text format; this block must stay byte-identical to NobleNextLua/Modules/RPS_Combat/Init.lua.
local WIRE_GUID_KINDS = {
    player = "Player", creature = "Creature", pet = "Pet", vehicle = "Vehicle", gameobject = "GameObject",
}
local function NormalizeWireGuid(value)
    if type(value) ~= "string" then
        if type(value) ~= "userdata" then return nil end
        value = tostring(value)
    end
    value = value:match("^%s*(.-)%s*$")
    if value == "" or #value > 128 then return nil end
    local kind, rest = value:match("^(%a+)%-([%w%-]+)$")
    if not kind or rest:find("%-%-") or rest:find("^%-") or rest:sub(-1) == "-" then return nil end
    return (WIRE_GUID_KINDS[kind:lower()] or kind) .. "-" .. rest:upper()
end
R.NormalizeGuid = NormalizeWireGuid

-- Negative answers expire so a unit that gets a profile or comes back into context is re-read.
R.NEGATIVE_TTL = { none = 60, unknown = 15 }
R.DISPLAY_STATE_TEXT = {
    loading = "…",
    error   = "ошибка",
    none    = "Нет профиля",
    unknown = "Данные недоступны",
    unavailable = "Недоступно",
}
-- Resource caption per non-ready state; native numbers are never shown for them.
R.RESOURCE_STATE_TEXT = {
    loading = "…",
    unknown = "…",
    none    = "—",
    error   = "ошибка",
}
R.selfState = "loading"
R.SYNC_TIMEOUT = 15

-- Native bars return only when this module is down: disabled
-- (system_unavailable), no AIO, or the server never answered after RequestSync.
function R.IsSystemUnavailable()
    if R.available then return false end
    return R.selfState == "error" or R.serverSilent == true or not AIO or not AIO.Handle
end

local function SafeGuid(unit)
    if not UnitGUID then return nil end
    local guid = UnitGUID(unit)
    if not guid or (issecretvalue and issecretvalue(guid)) then return nil end
    return NormalizeWireGuid(guid)
end
R.SafeGuid = SafeGuid

local function PayloadGuid(payload)
    return NormalizeWireGuid(payload.guid) or NormalizeWireGuid(payload.targetGuid)
end

local function MatchUnitGuid(unitGuid, payload)
    unitGuid = NormalizeWireGuid(unitGuid)
    if not unitGuid or type(payload) ~= "table" then return false end
    local payloadGuid = PayloadGuid(payload)
    if payloadGuid then return payloadGuid == unitGuid end
    -- Legacy payloads carry only the low counter; never used when a full GUID is present.
    local kind, hex = unitGuid:match("^(%a+)%-.*%-(%x+)$")
    local counter = hex and tonumber(hex, 16)
    if counter ~= nil and counter <= 9007199254740991 and payload.guidLow ~= nil then
        return (kind == "Player") == (payload.isPlayer == true) and counter == tonumber(payload.guidLow)
    end
    return false
end

function R.IsCurrentTarget(payload)
    return MatchUnitGuid(SafeGuid("target"), payload)
end

local function LowAlias(payload)
    if payload.guidLow == nil then return nil end
    return (payload.isPlayer and "p:" or "n:") .. tostring(payload.guidLow)
end

local function StoreUnitPayload(payload, explicitGuid)
    if type(payload) ~= "table" then return end
    local g = NormalizeWireGuid(explicitGuid) or PayloadGuid(payload)
    if g then
        payload.guid = g
        payload.targetGuid = NormalizeWireGuid(payload.targetGuid) or g
        payload.state = payload.state or (payload.inSystem and "ready" or "none")
        if payload.inSystem then
            payload.expiresAt = nil
        else
            payload.expiresAt = GetTime() + (R.NEGATIVE_TTL[payload.state] or R.NEGATIVE_TTL.unknown)
        end
        R.unitsByGuid[g] = payload
        return
    end
    local alias = LowAlias(payload)
    if alias then R.unitsByGuid[alias] = payload end
end

-- Explicit negative entry: the server could not resolve the GUID or it has no RP profile.
local function CacheNegative(guid, state, extra)
    guid = NormalizeWireGuid(guid)
    if not guid then return end
    local entry = { guid = guid, targetGuid = guid, inSystem = false, state = state or "unknown" }
    if type(extra) == "table" then
        entry.name, entry.isPlayer, entry.canEdit = extra.name, extra.isPlayer, extra.canEdit
        entry.guidLow, entry.reason = extra.guidLow, extra.reason
    end
    StoreUnitPayload(entry, guid)
    return entry
end
R.CacheNegative = CacheNegative

function R.LookupUnitByGuid(guid)
    if not guid or (issecretvalue and issecretvalue(guid)) then return nil end
    guid = NormalizeWireGuid(guid)
    if not guid then return nil end
    local entry = R.unitsByGuid[guid]
    if entry and entry.expiresAt and GetTime() >= entry.expiresAt then
        R.unitsByGuid[guid] = nil
        return nil
    end
    if entry then return entry end
    local kind, hex = guid:match("^(%a+)%-.*%-(%x+)$")
    local counter = hex and tonumber(hex, 16)
    if counter ~= nil and counter <= 9007199254740991 then
        local prefix = (kind == "Player") and "p:" or "n:"
        local byLow = R.unitsByGuid[prefix .. tostring(counter)]
        if byLow then return byLow end
    end
    return nil
end

local MAX_NAMEPLATES = 40

local function VisibleTokens()
    local tokens = { "player", "target", "focus", "mouseover", "targettarget" }
    if IsInRaid and IsInRaid() and GetNumGroupMembers then
        for i = 1, GetNumGroupMembers() do tokens[#tokens + 1] = "raid" .. i end
    elseif IsInGroup and IsInGroup() and GetNumSubgroupMembers then
        for i = 1, GetNumSubgroupMembers() do tokens[#tokens + 1] = "party" .. i end
    end
    for i = 1, MAX_NAMEPLATES do tokens[#tokens + 1] = "nameplate" .. i end
    return tokens
end

function R.IsGuidVisible(guid, exceptToken)
    guid = NormalizeWireGuid(guid)
    if not guid then return false end
    for _, token in ipairs(VisibleTokens()) do
        if token ~= exceptToken and SafeGuid(token) == guid then return true end
    end
    return false
end

-- Drops the cached snapshot of a unit that left every visible surface.
function R.InvalidateGuid(guid, exceptToken)
    guid = NormalizeWireGuid(guid)
    if not guid or R.IsGuidVisible(guid, exceptToken) then return false end
    local entry = R.unitsByGuid[guid]
    R.unitsByGuid[guid] = nil
    if entry then
        local alias = LowAlias(entry)
        if alias and R.unitsByGuid[alias] == entry then R.unitsByGuid[alias] = nil end
    end
    if R.focus and MatchUnitGuid(guid, R.focus) and not SafeGuid("focus") then R.focus = nil end
    return entry ~= nil
end

function R.PruneUnitCache()
    local visible = {}
    for _, token in ipairs(VisibleTokens()) do
        local g = SafeGuid(token)
        if g then visible[g] = true end
    end
    local now = GetTime()
    for key, entry in pairs(R.unitsByGuid) do
        local alias = key:find("^[pn]:") ~= nil
        if (not alias and not visible[key]) or (entry.expiresAt and now >= entry.expiresAt) then
            R.unitsByGuid[key] = nil
        end
    end
end

function R.GetUnitData(unitToken)
    if not unitToken then return nil end
    if UnitExists and not UnitExists(unitToken) then
        local g = SafeGuid(unitToken)
        if not g then return nil end
    end

    local guid = SafeGuid(unitToken)
    local playerGuid = SafeGuid("player")
    if ((UnitIsUnit and UnitIsUnit(unitToken, "player")) or (guid and playerGuid and guid == playerGuid) or unitToken == "player")
        and R.available and R.profile then
        local p = R.profile
        return {
            guid       = playerGuid or p.guid,
            targetGuid = playerGuid or p.guid,
            inSystem   = true,
            isPlayer   = true,
            name       = (UnitName and UnitName("player")) or p.name,
            archetype  = p.archetype,
            raceId     = p.raceId,
            level      = p.level or 1,
            curHealth  = p.curHealth or 0,
            maxHealth  = math.max(1, p.maxHealth or 1),
            curEnergy  = p.curEnergy or 0,
            maxEnergy  = math.max(0, p.maxEnergy or 0),
            curWounds  = p.curWounds or 0,
            maxWounds  = p.maxWounds or 3,
            armor      = p.armor or 0,
            speed      = p.speed or 10,
            weaponDice = p.weaponDice or "1d8",
            blockDice  = p.blockDice or "1d4",
            stats      = p.stats or {},
        }
    end

    if unitToken == "target" and R.target and (not guid or MatchUnitGuid(guid, R.target)) then
        return R.target
    end
    if unitToken == "focus" and R.focus and (not guid or MatchUnitGuid(guid, R.focus)) then
        return R.focus
    end
    local cached = guid and R.LookupUnitByGuid(guid)
    if cached then return cached end
    return nil
end

function R.GetSelfDisplayState()
    if R.profile and R.available then return "ready" end
    if R.selfState == "error" or R.profile then return "error" end
    if R.selfState == "none" then return "none" end
    return "loading"
end

-- "ready" | "loading" | "none" (no RP profile) | "unknown" (server could not resolve) | "error".
function R.GetUnitDisplayState(unitToken)
    if not unitToken then return "unknown" end
    local guid = SafeGuid(unitToken)
    local playerGuid = SafeGuid("player")
    if unitToken == "player" or (guid and playerGuid and guid == playerGuid) then
        local state = R.GetSelfDisplayState()
        return state, state == "ready" and R.profile or nil
    end
    if R.selfState == "error" and not R.available then return "error" end
    local data = R.GetUnitData(unitToken)
    if data then
        if data.inSystem then return "ready", data end
        return (data.state == "unknown") and "unknown" or "none", data
    end
    if unitToken == "target" and guid and R.targetNoneGuid == guid then return "unknown" end
    return "loading"
end

local sequence = 0
function R.RequestId()
    sequence = sequence + 1
    return tostring(GetServerTime()) .. "-" .. math.floor(GetTime() * 1000) .. "-" .. sequence
end

local bound
local function Emit(name, ...) if ns.Emit then ns.Emit(name, ...) end end

function R.Bind()
    if bound then return true end
    if not AIO or not AIO.AddHandlers then return false end
    local H = AIO.AddHandlers("RPS_Combat", {})
    bound = true
    R.handlers = H -- AIO allows one table per channel; Modules/CharacterCreation adds its handlers here.
    local function Answered()
        R.serverAnswered, R.serverSilent = true, nil
    end
    function H.SyncProfile(_, payload)
        Answered()
        if type(payload) ~= "table" or payload.protocol ~= 1 or type(payload.registry) ~= "table"
            or type(payload.profile) ~= "table" or type(payload.profile.revision) ~= "number" then return end
        local parts = {}
        for i, def in ipairs(payload.registry) do
            if i > 128 or type(def) ~= "table" or type(def.key) ~= "string" then return end
            parts[#parts + 1] = table.concat({def.key, def.category or "", def.name or "", def.icon or "",
                tostring(def.spellId), def.diceFormula or "", def.description or ""}, "|")
        end
        local fingerprint = table.concat(parts, "\n")
        if fingerprint ~= R.fingerprint then R.generation = R.generation + 1; R.fingerprint = fingerprint end
        R.registry, R.profile, R.available = payload.registry, payload.profile, true
        R.selfState = "ready"
        if type(payload.pendingAttackIds) == "table" then
            local active = {}; for _, id in ipairs(payload.pendingAttackIds) do active[id] = true end
            for i = #R.promptOrder, 1, -1 do
                local id = R.promptOrder[i]
                if not active[id] then R.prompts[id] = nil; table.remove(R.promptOrder, i) end
            end
            Emit("RPS_REACTIONS_CHANGED")
        end
        Emit("RPS_PROFILE_CHANGED", payload.profile)
        if R.RefreshAllUnitFrames then R.RefreshAllUnitFrames() end
    end
    function H.SyncTarget(_, payload)
        Answered()
        if type(payload) ~= "table" then return end
        local targetGuid = SafeGuid("target")
        local payloadGuid = PayloadGuid(payload)
        if payloadGuid then
            -- A late answer for the previous selection is cached under its own GUID only.
            if targetGuid and payloadGuid ~= targetGuid then StoreUnitPayload(payload); return end
        elseif payload.guidLow and not R.IsCurrentTarget(payload) then
            return
        end
        local hasIdentity = payloadGuid ~= nil or payload.guidLow ~= nil
        R.targetNoneGuid = nil
        if hasIdentity or payload.inSystem then
            StoreUnitPayload(payload, payloadGuid or targetGuid)
            R.target = payload
            R.remembered = payload
            Emit("RPS_REMEMBERED_CHANGED", payload)
            local focusGuid = SafeGuid("focus")
            if focusGuid and MatchUnitGuid(focusGuid, payload) then
                R.focus = payload
                Emit("RPS_FOCUS_CHANGED", payload)
            end
        else
            R.target = nil
            R.targetNoneGuid = targetGuid
        end
        Emit("RPS_TARGET_CHANGED", R.target)
        if R.RefreshAllUnitFrames then R.RefreshAllUnitFrames() end
    end
    function H.SyncUnit(_, payload)
        Answered()
        if type(payload) ~= "table" then return end
        StoreUnitPayload(payload)
        local targetGuid = SafeGuid("target")
        local matchesCurrentTarget = (targetGuid and MatchUnitGuid(targetGuid, payload))
            or (not targetGuid and R.target and ((payload.guid and (R.target.guid == payload.guid or R.target.targetGuid == payload.guid))
                or (payload.targetGuid and (R.target.targetGuid == payload.targetGuid or R.target.guid == payload.targetGuid))))
        if matchesCurrentTarget then
            R.target = payload
            R.remembered = payload
            Emit("RPS_TARGET_CHANGED", payload)
            Emit("RPS_REMEMBERED_CHANGED", payload)
        end
        local focusGuid = SafeGuid("focus")
        if focusGuid and MatchUnitGuid(focusGuid, payload) then
            R.focus = payload
            Emit("RPS_FOCUS_CHANGED", payload)
        end
        if R.remembered and ((payload.guid and (R.remembered.guid == payload.guid or R.remembered.targetGuid == payload.guid))
            or (payload.targetGuid and (R.remembered.targetGuid == payload.targetGuid or R.remembered.guid == payload.targetGuid))
            or (payload.guidLow and R.remembered.guidLow == payload.guidLow and R.remembered.isPlayer == payload.isPlayer)) then
            R.remembered = payload
            Emit("RPS_REMEMBERED_CHANGED", payload)
        end
        if R.RefreshAllUnitFrames then R.RefreshAllUnitFrames() end
    end
    function H.SyncUnitBatch(_, batch)
        Answered()
        if type(batch) ~= "table" then return end
        for guid, data in pairs(batch) do
            if type(data) == "table" then
                local key = type(guid) == "string" and guid or data.guid
                if data.state == "unknown" then
                    CacheNegative(key, "unknown", data)
                else
                    StoreUnitPayload(data, key)
                end
            end
        end
        local targetGuid = SafeGuid("target")
        if targetGuid then
            local found = R.LookupUnitByGuid(targetGuid)
            if found then
                R.target = found
                Emit("RPS_TARGET_CHANGED", R.target)
                if found.state ~= "unknown" then
                    R.remembered = found
                    Emit("RPS_REMEMBERED_CHANGED", R.remembered)
                end
            end
        end
        local focusGuid = SafeGuid("focus")
        if focusGuid then
            local found = R.LookupUnitByGuid(focusGuid)
            if found then
                R.focus = found
                Emit("RPS_FOCUS_CHANGED", R.focus)
            end
        end
        if R.RefreshAllUnitFrames then R.RefreshAllUnitFrames() end
    end
    function H.PromptDefenseReaction(_, payload)
        if type(payload) ~= "table" or type(payload.attackId) ~= "string" then return end
        if not R.prompts[payload.attackId] then
            if #R.promptOrder >= 8 then return end
            R.promptOrder[#R.promptOrder + 1] = payload.attackId
        end
        payload.deadline = GetTime() + math.max(0, tonumber(payload.timeoutSec) or 0)
        R.prompts[payload.attackId] = payload
        Emit("RPS_REACTIONS_CHANGED")
    end
    function H.ReactionClosed(_, attackId)
        R.prompts[attackId] = nil
        for i = #R.promptOrder, 1, -1 do if R.promptOrder[i] == attackId then table.remove(R.promptOrder, i) end end
        Emit("RPS_REACTIONS_CHANGED")
    end
    function H.Error(_, payload)
        Answered()
        if type(payload) ~= "table" then return end
        if payload.code == "system_unavailable" then
            R.available = false
            R.selfState = "error"
        elseif payload.code == "profile_unavailable" and not R.profile and payload.requestId == nil then
            R.selfState = "none"
        end
        if ns.PrintError then
            local label = R.FormatSystemError(payload.code)
            ns.PrintError(label .. (type(payload.reason) == "string" and (" (" .. payload.reason .. ")") or ""))
        end
        Emit("RPS_REQUEST_FAILED", payload)
    end
    function H.Committed(_, payload)
        if type(payload) ~= "table" then return end
        Emit("RPS_COMMITTED", payload)
        local result = payload.result
        if result and result.kind == "roll" and ns.Print then
            local statName = R.GetLocalizedStatName(result.statKey)
            ns.Print("Бросок «" .. tostring(statName) .. "»: " .. tostring(result.total)
                .. (result.damage and (", урон: " .. result.damage) or ""))
        elseif result and result.kind == "attack" and ns.Print then
            ns.Print("Атака: " .. tostring(result.total)
                .. (result.attackId and ", ожидается защита цели" or result.hit and ", попадание" or ", промах")
                .. (result.damage and (", урон: " .. result.damage) or ""))
        elseif result and result.kind == "reaction" and type(result.outcome) == "table" and ns.Print then
            local o = result.outcome
            local damage = type(o.damage) == "table" and o.damage.damage or 0
            ns.Print((R.REACTION_LABELS[o.choice] or tostring(o.choice)) .. (o.timedOut and " (время вышло)" or "")
                .. (o.avoided and ": атака избегнута" or (": получено урона " .. tostring(damage))))
        end
    end
    -- Server asks which open attack a native Избегание/Блок should answer.
    function H.ChooseDefenseAttack(_, payload)
        if type(payload) ~= "table" or type(payload.actionKey) ~= "string" or type(payload.attackIds) ~= "table" then return end
        R.defenseChoice = payload
        if ns.Print then ns.Print("Несколько входящих атак: выберите атаку в окне защиты.") end
        Emit("RPS_DEFENSE_CHOICE", payload)
    end
    function H.AttackResolved(_, payload)
        if type(payload) ~= "table" or not ns.Print then return end
        ns.Print("Цель ответила на атаку: " .. (R.REACTION_LABELS[payload.choice] or tostring(payload.choice))
            .. (payload.avoided and ", атака избегнута" or (", урон: " .. tostring(payload.damage or 0))))
    end
    return true
end

function R.Send(method, ...)
    if not R.Bind() or not AIO.Handle then
        if ns.PrintError then ns.PrintError("AIO недоступен.") end
        return false
    end
    AIO.Handle("RPS_Combat", method, ...)
    return true
end

local MAX_UNITS_PER_REQUEST = 45

function R.RequestVisibleUnitsSync()
    if not AIO or not AIO.Handle then return false end
    local guids, seen = {}, {}
    local function addUnit(tok)
        if UnitExists and not UnitExists(tok) then return end
        local g = SafeGuid(tok)
        if g and not seen[g] then
            seen[g] = true
            guids[#guids + 1] = g
        end
    end
    addUnit("target")
    addUnit("focus")
    addUnit("targettarget")
    if IsInRaid and IsInRaid() and GetNumGroupMembers then
        for i = 1, GetNumGroupMembers() do addUnit("raid" .. i) end
    elseif IsInGroup and IsInGroup() and GetNumSubgroupMembers then
        for i = 1, GetNumSubgroupMembers() do addUnit("party" .. i) end
    end
    for i = 1, MAX_NAMEPLATES do
        if #guids >= MAX_UNITS_PER_REQUEST then break end
        addUnit("nameplate" .. i)
    end
    while #guids > MAX_UNITS_PER_REQUEST do table.remove(guids) end
    if #guids > 0 then
        return R.Send("RequestUnitsSync", guids)
    end
    return false
end

-- Nameplates appear in bursts; batch new GUIDs and request only those not cached yet.
-- The server drops reads closer than 200 ms apart, so unanswered GUIDs are retried once.
local queuedGuids, queueScheduled = {}, false
local FlushUnitQueue
local function ScheduleUnitQueue(delay, retry)
    if queueScheduled then return end
    queueScheduled = true
    C_Timer.After(delay, function() FlushUnitQueue(retry) end)
end
FlushUnitQueue = function(retry)
    queueScheduled = false
    if not AIO or not AIO.Handle then queuedGuids = {}; return end
    local guids = {}
    for guid in pairs(queuedGuids) do
        if #guids >= MAX_UNITS_PER_REQUEST then break end
        queuedGuids[guid] = nil
        if not R.LookupUnitByGuid(guid) then guids[#guids + 1] = guid end
    end
    if #guids > 0 then
        R.Send("RequestUnitsSync", guids)
        if not retry then
            C_Timer.After(1.0, function()
                for _, guid in ipairs(guids) do
                    if not R.LookupUnitByGuid(guid) then queuedGuids[guid] = true end
                end
                if next(queuedGuids) then ScheduleUnitQueue(0, true) end
            end)
        end
    end
    if next(queuedGuids) then ScheduleUnitQueue(0.3, retry) end
end

function R.QueueUnitSync(guid)
    if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return end
    guid = NormalizeWireGuid(guid)
    if not guid or R.LookupUnitByGuid(guid) then return end
    queuedGuids[guid] = true
    ScheduleUnitQueue(0.3, false)
end

function R.Roll(key, fate)
    if not R.available or not R.profile then return false end
    return R.Send("RollStat", key, fate == true, R.RequestId(), R.profile.revision)
end

R.REACTION_LABELS = { AVOID = "Избегание", BLOCK = "Блок", TAKE = "Принять атаку" }

-- Same server route as the native action spells: PerformAction(actionKey, args, requestId).
-- Returns the requestId so a window can wait for its own receipt.
function R.PerformAction(actionKey, args)
    local requestId = R.RequestId()
    args = args or {}
    if actionKey == "attack" then
        if not R.available or not R.profile then return nil end
        args.revision = R.profile.revision
        args.targetGuid = args.targetGuid or (UnitGUID and NormalizeWireGuid(UnitGUID("target")))
    end
    if R.Send("PerformAction", actionKey, args, requestId) then return requestId end
    return nil
end

function R.RequestSelfSync()
    R.Send("RequestSync")
    if not (C_Timer and C_Timer.After) then return end
    C_Timer.After(R.SYNC_TIMEOUT, function()
        if R.serverAnswered then return end
        R.serverSilent = true
        if R.RefreshAllUnitFrames then R.RefreshAllUnitFrames() end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("ADDON_LOADED")
local targetGeneration = 0
local lastTargetGuid
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" then
        R.target = nil; R.targetNoneGuid = nil
        if lastTargetGuid then R.InvalidateGuid(lastTargetGuid) end
        lastTargetGuid = SafeGuid("target")
        Emit("RPS_TARGET_CHANGED", nil)
        targetGeneration = targetGeneration + 1
        local generation = targetGeneration
        R.Send("RequestTargetSync")
        -- Retry only the final selection if the server's read throttle dropped a rapid switch.
        C_Timer.After(0.3, function()
            if generation == targetGeneration and ((not R.target and not R.targetNoneGuid) or
                (R.target.inSystem and R.TargetResourceProfile and not R.TargetResourceProfile())) then
                R.Send("RequestTargetSync")
            end
        end)
    elseif event == "PLAYER_LOGIN" then R.RequestSelfSync()
    elseif not bound and R.Bind() then R.RequestSelfSync() end
end)
R.Bind()
