-- Character creation: session draft and creation messages on the AIO RPS_Combat channel.
-- The server is the authority: the client never computes the sheet, rolls or stores the draft.
local _, ns = ...
local R = ns.RPSClient
local C = {
    options = nil,
    state = nil,
    draft = nil,
    step = 1,
    visited = { [1] = true },
    preview = nil,
    previewFingerprint = nil,
    inflight = 0,
    previewGeneration = 0,
    pending = nil,
    retry = nil,
    status = nil,
    errors = {},
    warnings = {},
}
ns.CharacterCreation = C

-- RP names belong to TotalRP; the wizard has no text input and never sends rpName.
C.STEPS = {
    { key = "race",      title = "Раса" },
    { key = "trait",     title = "Черта" },
    { key = "mastery",   title = "Мастерство" },
    { key = "archetype", title = "Архетип" },
    { key = "starter",   title = "Снаряжение" },
    { key = "confirm",   title = "Итог" },
}
C.STEP_INDEX = {}
for i, step in ipairs(C.STEPS) do C.STEP_INDEX[step.key] = i end
C.FIELD_STEP = {
    race = 1, racialFeature = 1, trait = 2, traits = 2, traitChoice = 2,
    mastery = 3, archetype = 4, starterItems = 5,
}
C.STUB_TAG = "заглушка, бонусы в разработке"
C.MASTERY_NAMES = { skill = "Навык", knowledge = "Знание", endurance = "Упорство", craft = "Ремесло" }
C.DEFAULT_MASTERY_KEYS = { "skill", "knowledge", "endurance", "craft" }
C.STATE_TEXT = {
    none        = "не выполнена",
    legacy      = "старый профиль, выбор не подтверждён",
    reconfigure = "разрешена перенастройка",
    complete    = "завершена",
}
C.PREVIEW_DELAY = 0.5
C.PREVIEW_TIMEOUT = 5
C.CONFIRM_TIMEOUT = 15
C.RESET_POPUP = "NOBLENEXT_RPS_RACE_RESET"

local ERROR_TEXT = {
    revision_conflict = "Профиль изменился на сервере: варианты перезагружены, черновик сохранён. Подтвердите ещё раз.",
    already_confirmed = "Персонаж уже подтверждён. Перенастройку выполняет ведущий.",
    race_preset_current = "Расовые данные уже актуальны: сбрасывать нечего.",
}

local function Find(list, key)
    if type(list) ~= "table" or key == nil then return nil end
    for _, entry in ipairs(list) do
        if type(entry) == "table" and entry.key == key then return entry end
    end
    return nil
end
C.Find = Find

function C.ChoiceKey(choice)
    if type(choice) == "table" then return choice.key end
    return choice
end

function C.ChoiceName(choice)
    if type(choice) == "table" then return choice.name or tostring(choice.key) end
    return tostring(choice)
end

local function HasChoice(choices, key)
    for _, choice in ipairs(choices) do
        if C.ChoiceKey(choice) == key then return true end
    end
    return false
end

local function Notify()
    if C.OnChange then C.OnChange() end
    if ns.Emit then ns.Emit("RPS_CREATION_CHANGED") end
end
C.Notify = Notify

local function StateOf(record)
    if type(record) ~= "table" then return nil end
    local state = record.creationState or record.state
    return type(state) == "string" and state or nil
end

-- Newest of SyncProfile.creation and the creation answers, compared by the creation revision
-- (character_rps_creation.revision, not the profile revision). profile.creationState is a legacy fallback.
function C.GetState()
    local sync, state = C.syncCreation, C.state
    local fromSync, fromState = StateOf(sync), StateOf(state)
    if fromSync and (not fromState or (tonumber(sync.revision) or 0) >= (tonumber(state.revision) or 0)) then
        return fromSync
    end
    if fromState then return fromState end
    local profile = R.profile
    return profile and type(profile.creationState) == "string" and profile.creationState or nil
end

function C.NeedsSetup()
    local state = C.GetState()
    return state == "none" or state == "legacy" or state == "reconfigure"
end

-- Unknown state (older server) keeps the previous sheet behaviour.
function C.ChoiceConfirmed()
    local state = C.GetState()
    return state == nil or state == "complete" or state == "reconfigure"
end

-- "race": only the race must be re-chosen after a preset update; other steps keep confirmed values.
function C.Scope()
    if C.GetState() == "complete" then return nil end
    local sync, state = C.syncCreation, C.state
    local scope = (sync and sync.scope) or (state and state.scope)
    return type(scope) == "string" and scope or nil
end

function C.RaceUpdateAvailable()
    local sync, state = C.syncCreation, C.state
    if sync and sync.raceUpdateAvailable ~= nil then return sync.raceUpdateAvailable == true end
    return state ~= nil and state.raceUpdateAvailable == true
end

function C.MasteryKeys()
    local mastery = C.options and C.options.mastery
    if type(mastery) == "table" and type(mastery.keys) == "table" and #mastery.keys > 0 then return mastery.keys end
    return C.DEFAULT_MASTERY_KEYS
end

function C.SelectedRace()
    return C.options and C.draft and Find(C.options.races, C.draft.race)
end

function C.SelectedFeature()
    local race = C.SelectedRace()
    return race and Find(race.features, C.draft.racialFeature)
end

function C.SelectedTrait()
    return C.options and C.draft and Find(C.options.traits, C.draft.trait)
end

-- Races without a finished preset carry one "<race>_default" feature without bonuses.
function C.IsStubRace(race)
    if type(race) ~= "table" then return false end
    if race.preset == "default" then return true end
    local features = race.features
    return type(features) == "table" and #features == 1 and type(features[1]) == "table"
        and features[1].key == tostring(race.key) .. "_default"
end

function C.MasteryName(key)
    local names = C.options and C.options.mastery and C.options.mastery.names
    return (type(names) == "table" and names[key]) or C.MASTERY_NAMES[key] or tostring(key)
end

-- Client-side budget is a hint for the +/- buttons; mastery_points_mismatch from the server decides.
function C.MasteryBudget()
    local mastery = C.options and C.options.mastery
    local base = tonumber(mastery and mastery.basePoints) or 2
    local feature = C.SelectedFeature()
    local extra = feature and tonumber(feature.masteryFree) or 0
    return base + extra, extra
end

function C.MasteryUsed()
    local used = 0
    for _, key in ipairs(C.MasteryKeys()) do used = used + (C.draft and C.draft.mastery[key] or 0) end
    return used
end

local function FitMastery()
    local budget = C.MasteryBudget()
    local keys = C.MasteryKeys()
    for i = #keys, 1, -1 do
        local key = keys[i]
        while C.MasteryUsed() > budget and C.draft.mastery[key] > 0 do
            C.draft.mastery[key] = C.draft.mastery[key] - 1
        end
    end
end

function C.StarterLimit()
    local starter = C.options and C.options.starter
    return tonumber(starter and starter.maxItems) or 6
end

local function NewDraft(seed)
    local draft = { mastery = {}, starterItems = {} }
    if type(seed) == "table" then
        for _, field in ipairs({ "race", "racialFeature", "trait", "traitChoice", "archetype" }) do
            if type(seed[field]) == "string" then draft[field] = seed[field] end
        end
        if type(seed.mastery) == "table" then
            for key, value in pairs(seed.mastery) do draft.mastery[key] = tonumber(value) end
        end
        if type(seed.starterItems) == "table" then
            for _, key in ipairs(seed.starterItems) do
                if type(key) == "string" then draft.starterItems[#draft.starterItems + 1] = key end
            end
        end
    end
    return draft
end

-- Drops selections the current catalog no longer offers; dependent choices follow their parent.
function C.Sanitize()
    local o, d = C.options, C.draft
    if not o or not d then return end
    local race = Find(o.races, d.race)
    if not race or race.available == false then d.race, race = nil, nil end
    if not race or not Find(race.features, d.racialFeature) then d.racialFeature = nil end
    if race and not d.racialFeature and type(race.features) == "table" and #race.features == 1 then
        d.racialFeature = race.features[1].key
    end
    local trait = Find(o.traits, d.trait)
    if not trait or trait.available == false then d.trait, trait = nil, nil end
    if not trait or not trait.needsChoice
        or (type(trait.choices) == "table" and not HasChoice(trait.choices, d.traitChoice)) then
        d.traitChoice = nil
    end
    if not Find(o.archetypes, d.archetype) then d.archetype = nil end
    local mastery = {}
    for _, key in ipairs(C.MasteryKeys()) do
        mastery[key] = math.max(0, math.floor(tonumber(d.mastery and d.mastery[key]) or 0))
    end
    d.mastery = mastery
    FitMastery()
    local items, seen, limit = {}, {}, C.StarterLimit()
    local catalog = o.starter and o.starter.items
    for _, key in ipairs(d.starterItems or {}) do
        if not seen[key] and Find(catalog, key) and #items < limit then
            seen[key] = true
            items[#items + 1] = key
        end
    end
    d.starterItems = items
end

function C.Fingerprint(d)
    d = d or C.draft
    if not d then return "" end
    local parts = { tostring(d.race), tostring(d.racialFeature), tostring(d.trait),
        tostring(d.traitChoice), tostring(d.archetype) }
    for _, key in ipairs(C.MasteryKeys()) do
        parts[#parts + 1] = key .. "=" .. tostring(d.mastery and d.mastery[key] or 0)
    end
    parts[#parts + 1] = table.concat(d.starterItems or {}, ",")
    return table.concat(parts, "|")
end

-- Wire copy with exactly the contract fields.
function C.WireDraft()
    local d = C.draft
    local mastery, items = {}, {}
    for _, key in ipairs(C.MasteryKeys()) do mastery[key] = d.mastery[key] or 0 end
    for i, key in ipairs(d.starterItems) do items[i] = key end
    return {
        race = d.race, racialFeature = d.racialFeature, trait = d.trait,
        traitChoice = d.traitChoice, archetype = d.archetype, mastery = mastery, starterItems = items,
    }
end

local function TraitNeedsChoice(trait)
    return trait and trait.needsChoice and type(trait.choices) == "table" and #trait.choices > 0
end

-- nil when the step has every required local choice; otherwise the reason in Russian.
-- Mastery is not checked here: its budget is a hint and the server decides.
function C.LocalMissing(step)
    local d = C.draft
    if not C.options or not d then return "Варианты ещё не получены с сервера." end
    if step == 1 then
        if not d.race then return "Выберите расу." end
        if not d.racialFeature then return "Выберите одну расовую особенность." end
    elseif step == 2 then
        if not d.trait then return "Выберите общую черту." end
        if TraitNeedsChoice(C.SelectedTrait()) and not d.traitChoice then
            return "Сделайте дополнительный выбор для черты."
        end
    elseif step == 4 then
        if not d.archetype then return "Выберите архетип." end
    elseif step == #C.STEPS then
        for i = 1, #C.STEPS - 1 do
            local missing = C.LocalMissing(i)
            if missing then return missing end
        end
    end
    return nil
end

-- Local checklist {step, field, message_ru} used until the server preview answers.
function C.LocalMissingList()
    local list, d = {}, C.draft
    if not C.options or not d then return list end
    local function Add(field, text) list[#list + 1] = { step = C.FIELD_STEP[field], field = field, message_ru = text } end
    if not d.race then Add("race", "Раса") end
    if not d.racialFeature then Add("racialFeature", "Расовая особенность") end
    if not d.trait then Add("trait", "Общая черта") end
    if TraitNeedsChoice(C.SelectedTrait()) and not d.traitChoice then Add("traitChoice", "Дополнительный выбор черты") end
    local budget, used = C.MasteryBudget(), C.MasteryUsed()
    if used < budget then
        Add("mastery", "Мастерство: осталось распределить " .. (budget - used) .. " из " .. budget)
    end
    if not d.archetype then Add("archetype", "Архетип") end
    return list
end

-- Server fields may be indexed or nested: "starterItems[2]", "traits[1]", "mastery.skill".
function C.ErrorStep(err)
    local base = type(err.field) == "string" and err.field:match("^%a+") or nil
    if C.FIELD_STEP[base] then return C.FIELD_STEP[base] end
    if type(err.step) == "string" and C.STEP_INDEX[err.step] then return C.STEP_INDEX[err.step] end
    local step = tonumber(err.step)
    if step and step >= 1 and step <= #C.STEPS then return math.floor(step) end
    return #C.STEPS
end

-- Server Preview(ok=false).missing for the current draft wins; otherwise the local checklist.
function C.MissingList()
    local preview = C.preview
    if preview and preview.ok == false and type(preview.missing) == "table"
        and C.previewFingerprint == C.Fingerprint() then
        local list = {}
        for _, item in ipairs(preview.missing) do
            if type(item) == "table" then
                list[#list + 1] = { step = C.ErrorStep(item), field = item.field, optional = item.optional == true,
                    message_ru = item.message_ru or item.message or tostring(item.field or "?") }
            end
        end
        return list
    end
    return C.LocalMissingList()
end

function C.StepMissing(step)
    for _, item in ipairs(C.MissingList()) do
        if not item.optional and (item.step or C.ErrorStep(item)) == step then return true end
    end
    return false
end

-- In scope "race" only the race and the summary stay editable; a step the server
-- still reports as incomplete is unlocked so the player is never stuck.
function C.StepLocked(step)
    if C.Scope() ~= "race" or step == 1 or step == #C.STEPS then return false end
    return not C.StepMissing(step)
end

function C.ErrorText(err)
    return err.message_ru or err.message or ERROR_TEXT[err.code] or (R.FormatSystemError and R.FormatSystemError(err.code))
        or tostring(err.code)
end

-- Errors of steps the player has not opened yet stay hidden; the final step shows all of them.
function C.VisibleErrors(step)
    local list = {}
    for _, err in ipairs(C.errors) do
        local errStep = C.ErrorStep(err)
        if C.visited[errStep] and (step == nil or errStep == step) then list[#list + 1] = err end
    end
    return list
end

function C.PreviewFresh()
    return C.preview ~= nil and C.inflight == 0 and C.previewFingerprint == C.Fingerprint()
end

function C.CanConfirm()
    if not C.options or not C.draft or C.pending or C.GetState() == "complete" then return false end
    if C.LocalMissing(#C.STEPS) then return false end
    return C.PreviewFresh() and C.preview.ok == true
end

function C.EnsureDraft()
    if not C.draft then
        C.draft = NewDraft(C.state and C.state.draft)
        C.Sanitize()
    end
    return C.draft
end

function C.SendPreview()
    if not C.options or not C.draft or not C.draft.race then return false end
    local fingerprint = C.Fingerprint()
    if not R.Send("PreviewCharacter", C.WireDraft()) then return false end
    C.inflight = C.inflight + 1
    C.sentFingerprint = fingerprint
    local generation = C.previewGeneration
    C_Timer.After(C.PREVIEW_TIMEOUT, function()
        if generation == C.previewGeneration and C.inflight > 0 and C.sentFingerprint == fingerprint then
            C.inflight = 0
            C.SendPreview()
        end
    end)
    return true
end

function C.SchedulePreview()
    C.previewGeneration = C.previewGeneration + 1
    local generation = C.previewGeneration
    C_Timer.After(C.PREVIEW_DELAY, function()
        if generation == C.previewGeneration then C.SendPreview() end
    end)
end

function C.Changed()
    C.status = nil
    C.SchedulePreview()
    Notify()
end

local function FieldLocked(field)
    local step = C.FIELD_STEP[field]
    return step ~= nil and C.StepLocked(step)
end
C.FieldLocked = FieldLocked

function C.SetField(field, value)
    if FieldLocked(field) then return false end
    local d = C.EnsureDraft()
    if field == "race" and d.race ~= value then d.racialFeature = nil end
    if field == "trait" and d.trait ~= value then d.traitChoice = nil end
    d[field] = value
    C.Sanitize()
    C.Changed()
    return true
end

function C.AdjustMastery(key, delta)
    if FieldLocked("mastery") then return false end
    local d = C.EnsureDraft()
    local value = (d.mastery[key] or 0) + delta
    if value < 0 or (delta > 0 and C.MasteryUsed() >= C.MasteryBudget()) then return false end
    d.mastery[key] = value
    C.Changed()
    return true
end

function C.ToggleStarter(key)
    if FieldLocked("starterItems") then return false end
    local d = C.EnsureDraft()
    for i, other in ipairs(d.starterItems) do
        if other == key then
            table.remove(d.starterItems, i)
            C.Changed()
            return true
        end
    end
    if #d.starterItems >= C.StarterLimit() then return false end
    d.starterItems[#d.starterItems + 1] = key
    C.Changed()
    return true
end

-- Nearest unlocked step in the direction (+1/-1); the current one when there is none.
function C.NextStep(from, direction)
    local step = from + direction
    while step >= 1 and step <= #C.STEPS do
        if not C.StepLocked(step) then return step end
        step = step + direction
    end
    return from
end

function C.GoTo(step)
    step = math.max(1, math.min(#C.STEPS, step))
    if C.StepLocked(step) then return false end
    C.step = step
    C.visited[step] = true
    if step == #C.STEPS then
        for i = 1, #C.STEPS do C.visited[i] = true end
    end
    Notify()
    return true
end

function C.RequestOptions()
    C.loading = true
    if not R.Send("RequestCharacterOptions") then
        C.loading = false
        C.status = "Сервер недоступен (AIO)."
    end
    Notify()
end

-- The server compares it with the creation revision; the profile revision is unrelated.
function C.ExpectedRevision()
    local a = tonumber(C.state and C.state.revision)
    local b = tonumber(C.syncCreation and C.syncCreation.revision)
    if a and b then return math.max(a, b) end
    return a or b or 0
end

function C.Confirm()
    if not C.CanConfirm() then return nil end
    local fingerprint = C.Fingerprint()
    -- A timed-out submit of the same draft is retried with the same requestId (server idempotency).
    local requestId = (C.retry and C.retry.fingerprint == fingerprint) and C.retry.requestId or R.RequestId()
    if not R.Send("ConfirmCharacter", C.WireDraft(), C.ExpectedRevision(), requestId) then return nil end
    C.pending = { requestId = requestId, fingerprint = fingerprint }
    C.retry = nil
    C.status = "Сохранение…"
    C_Timer.After(C.CONFIRM_TIMEOUT, function()
        if C.pending and C.pending.requestId == requestId then
            C.retry = C.pending
            C.pending = nil
            C.status = "Сервер не ответил. Черновик сохранён: подтвердите ещё раз."
            Notify()
        end
    end)
    Notify()
    return requestId
end

-- ResetRaceData(requestId): the server clears race/feature of an outdated preset and answers
-- with SyncProfile.creation.scope = "race" (or CharacterError race_preset_current).
function C.ResetRace()
    if C.resetPending then return nil end
    if not C.RaceUpdateAvailable() then
        if ns.Print then ns.Print("Обновление расовых данных сейчас недоступно.") end
        return nil
    end
    local requestId = R.RequestId()
    if not R.Send("ResetRaceData", requestId) then return nil end
    C.resetPending = requestId
    C_Timer.After(C.CONFIRM_TIMEOUT, function()
        if C.resetPending == requestId then
            C.resetPending = nil
            if ns.Print then ns.Print("Сервер не ответил на сброс расовых данных. Попробуйте ещё раз.") end
            Notify()
        end
    end)
    Notify()
    return requestId
end

local function FinishRaceReset(text)
    C.resetPending = nil
    if ns.Print and text then ns.Print(text) end
    Notify()
end

if StaticPopupDialogs then
    StaticPopupDialogs[C.RESET_POPUP] = {
        text = "Сбросить расовые данные?\nРасу и расовую особенность нужно будет выбрать заново, остальной выбор сохранится.",
        button1 = "Сбросить",
        button2 = "Отмена",
        OnAccept = function() C.ResetRace() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

function C.ConfirmRaceReset()
    if not C.RaceUpdateAvailable() then
        if ns.Print then ns.Print("Обновление расовых данных сейчас недоступно.") end
        return false
    end
    if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs[C.RESET_POPUP] then
        StaticPopup_Show(C.RESET_POPUP)
    else
        C.ResetRace()
    end
    return true
end

local function ResetSession()
    C.draft, C.preview, C.previewFingerprint, C.sentFingerprint = nil, nil, nil, nil
    C.errors, C.warnings = {}, {}
    C.step, C.visited = 1, { [1] = true }
    C.pending, C.retry, C.status = nil, nil, nil
    C.previewGeneration = C.previewGeneration + 1
    C.inflight = 0
end

local handlers = {}

function handlers.CharacterOptions(_, payload)
    if type(payload) ~= "table" or type(payload.races) ~= "table" or type(payload.traits) ~= "table"
        or type(payload.archetypes) ~= "table" then return end
    if C.options and C.options.catalogVersion ~= payload.catalogVersion then C.previewFingerprint = nil end
    C.options = payload
    C.state = type(payload.state) == "table" and payload.state or {}
    C.loading = false
    C.EnsureDraft()
    C.Sanitize()
    if C.draft.race and not C.PreviewFresh() and C.IsOpen and C.IsOpen() then C.SchedulePreview() end
    Notify()
end

function handlers.CharacterPreview(_, payload)
    if type(payload) ~= "table" then return end
    C.inflight = math.max(0, C.inflight - 1)
    C.preview = payload
    C.previewFingerprint = C.inflight == 0 and C.sentFingerprint or nil
    C.errors = (payload.ok == false and type(payload.errors) == "table") and payload.errors or {}
    C.warnings = type(payload.warnings) == "table" and payload.warnings or {}
    Notify()
end

function handlers.CharacterConfirmed(_, payload)
    if type(payload) ~= "table" then return end
    local creation = type(payload.creation) == "table" and payload.creation or {}
    C.state = {
        creationState = StateOf(creation) or "complete",
        revision = tonumber(creation.revision) or tonumber(payload.revision),
    }
    ResetSession()
    if ns.Print then ns.Print("RP-персонаж подтверждён сервером.") end
    if C.OnConfirmed then C.OnConfirmed(payload) end
    if ns.CharacterSheet and ns.CharacterSheet.Refresh then ns.CharacterSheet:Refresh() end
    Notify()
end

-- Confirm errors carry the requestId (except malformed requestId/revision); options and preview
-- failures (rate_limited, creation_unavailable, system_unavailable) come without it.
local function RaceResetDone()
    ResetSession()
    FinishRaceReset("Расовые данные сброшены: выберите расу заново.")
    if C.OnRaceReset then C.OnRaceReset() end
end

function handlers.RaceDataReset(_, payload)
    if type(payload) ~= "table" or not C.resetPending then return end
    if payload.requestId ~= nil and payload.requestId ~= C.resetPending then return end
    if type(payload.creation) == "table" then
        C.syncCreation = payload.creation
    elseif type(payload.state) == "string" then
        C.state = { creationState = payload.state, revision = tonumber(payload.revision), scope = payload.scope }
    end
    RaceResetDone()
end

function handlers.CharacterError(_, payload)
    if type(payload) ~= "table" then return end
    local requestId = payload.requestId
    if C.resetPending and (requestId == C.resetPending or (requestId == nil and payload.code == "race_preset_current")) then
        FinishRaceReset(C.ErrorText(payload))
        return
    end
    if requestId ~= nil and not (C.pending and requestId == C.pending.requestId) then return end
    if requestId == nil and payload.code == "rate_limited" then
        if C.inflight > 0 then
            C.inflight = 0
            C.SchedulePreview()
        elseif C.loading then
            C.loading = false
            C_Timer.After(1, C.RequestOptions)
        end
        return
    end
    C.loading = false
    C.pending = nil
    C.inflight = 0
    C.status = C.ErrorText(payload)
    if type(payload.errors) == "table" and #payload.errors > 0 then
        C.errors = payload.errors
        C.previewFingerprint = nil
        C.SchedulePreview()
    end
    if payload.code == "revision_conflict" then C.RequestOptions() end
    Notify()
end
C.handlers = handlers

local attachedTo
local function Attach()
    local H = R.handlers
    if not H or attachedTo == H then return end
    for name, fn in pairs(handlers) do H[name] = fn end
    -- SyncProfile.creation sits next to payload.profile; RPSClient keeps only the profile.
    local sync = H.SyncProfile
    if sync then
        H.SyncProfile = function(player, payload)
            local resetDone = false
            if type(payload) == "table" and type(payload.profile) == "table" then
                local creation = payload.creation or payload.profile.creation
                C.syncCreation = type(creation) == "table" and creation or nil
                resetDone = C.resetPending ~= nil and C.syncCreation ~= nil and C.syncCreation.scope == "race"
            end
            local result = sync(player, payload)
            if resetDone then RaceResetDone() end
            return result
        end
    end
    attachedTo = H
end
local bind = R.Bind
function R.Bind()
    local ok = bind()
    Attach()
    return ok
end
Attach()

if ns.Subscribe then
    -- Generic RPS_Combat errors (rate_limited, system_unavailable) for our requestId unlock the submit.
    ns.Subscribe("RPS_REQUEST_FAILED", "CharacterCreation", function(payload)
        if type(payload) == "table" and C.resetPending and payload.requestId == C.resetPending then
            FinishRaceReset(C.ErrorText(payload))
        elseif type(payload) == "table" and C.pending and payload.requestId == C.pending.requestId then
            C.pending = nil
            C.status = C.ErrorText(payload)
            Notify()
        end
    end)
    -- Without SyncProfile.creation the state is read once through CharacterOptions.state.
    ns.Subscribe("RPS_PROFILE_CHANGED", "CharacterCreation", function(profile)
        if type(profile) == "table" and not C.syncCreation and profile.creationState == nil
            and not C.options and not C.probed then
            C.probed = true
            C_Timer.After(1, function() if not C.options then C.RequestOptions() end end)
        end
        Notify()
    end)
end
