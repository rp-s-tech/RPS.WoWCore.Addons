-- Core/Events.lua — keyed pub/sub + slash registration + sender helpers

local ns = LibStub("NobleNextLib-1.0").Runtime

ns.Events = ns.Events or {}
ns.Util = ns.Util or {}

-- eventName → { [key] = subscription }; identity distinguishes replacements.
local subscribers = {}

---Подписаться на событие. Повторный key заменяет handler (с диагностикой).
---@param eventName string
---@param key string
---@param handler fun(...): any
---@return function unsubscribe
function ns.Subscribe(eventName, key, handler)
    if type(eventName) ~= "string" or eventName == "" then
        return function() end
    end
    if type(key) ~= "string" or key == "" then
        if ns.PrintError then
            ns.PrintError("Subscribe: пустой key для " .. tostring(eventName))
        end
        return function() end
    end
    if type(handler) ~= "function" then
        if ns.PrintError then
            ns.PrintError("Subscribe: handler не функция (" .. tostring(eventName) .. "/" .. key .. ")")
        end
        return function() end
    end

    local bucket = subscribers[eventName]
    if not bucket then
        bucket = {}
        subscribers[eventName] = bucket
    end
    if bucket[key] and bucket[key].handler ~= handler and ns.PrintDebug then
        ns.PrintDebug(string.format("Events: replace %s/%s", eventName, key))
    end
    local subscription = { handler = handler }
    bucket[key] = subscription

    return function()
        local current = subscribers[eventName]
        if current and current[key] == subscription then
            ns.Unsubscribe(eventName, key)
        end
    end
end

function ns.Unsubscribe(eventName, key)
    local bucket = subscribers[eventName]
    if not bucket then
        return
    end
    bucket[key] = nil
    if next(bucket) == nil then
        subscribers[eventName] = nil
    end
end

function ns.Emit(eventName, ...)
    local bucket = subscribers[eventName]
    if not bucket then
        return
    end
    local snapshot = {}
    for k, subscription in pairs(bucket) do
        snapshot[#snapshot + 1] = { key = k, subscription = subscription }
    end
    for i = 1, #snapshot do
        local entry = snapshot[i]
        local current = subscribers[eventName]
        if current and current[entry.key] == entry.subscription then
            local ok, err = pcall(entry.subscription.handler, ...)
            if not ok and ns.PrintError then
                ns.PrintError(string.format("Events[%s/%s]: %s", tostring(eventName), tostring(entry.key), tostring(err)))
            end
        end
    end
end

ns.Events.Subscribe = ns.Subscribe
ns.Events.Unsubscribe = ns.Unsubscribe
ns.Events.Emit = ns.Emit

-- ---------------------------------------------------------------------------
-- Slash commands (idempotent by SlashCmdList key)
-- ---------------------------------------------------------------------------
local registeredSlash = {} -- key → handler

---Зарегистрировать slash-команду. Повторный key с другим handler — диагностика, без silent overwrite.
---@param key string ключ SlashCmdList (например "NNARMY")
---@param handler fun(msg: string, editBox: any)
---@param aliases string|string[] алиасы без ведущего "/"
---@return boolean
function ns.RegisterSlashCommand(key, handler, aliases)
    if type(key) ~= "string" or key == "" or type(handler) ~= "function" then
        if ns.PrintError then
            ns.PrintError("RegisterSlashCommand: неверные аргументы")
        end
        return false
    end

    key = key:upper()
    local prev = registeredSlash[key] or SlashCmdList[key]
    if prev and prev ~= handler then
        if ns.PrintError then
            ns.PrintError("RegisterSlashCommand: ключ уже занят: " .. key)
        end
        return false
    end
    if prev == handler then
        return true
    end

    local list
    if type(aliases) == "string" then
        list = { aliases }
    elseif type(aliases) == "table" then
        list = aliases
    else
        list = {}
    end
    if #list == 0 then
        if ns.PrintError then
            ns.PrintError("RegisterSlashCommand: нет aliases для " .. key)
        end
        return false
    end

    -- Normalize: strip leading slash, drop empties / duplicates
    local seen = {}
    local clean = {}
    for i = 1, #list do
        local a = tostring(list[i] or ""):gsub("^/+", ""):lower()
        if a ~= "" and not seen[a] then
            seen[a] = true
            clean[#clean + 1] = a
        end
    end
    if #clean == 0 then
        return false
    end

    -- Blizzard RegisterNewSlashCommand requires exactly two aliases in 12.0.7.
    -- The standard numbered globals support any nonzero number of aliases.
    for i = 1, #clean do
        _G["SLASH_" .. key .. i] = "/" .. clean[i]
    end
    -- Always expose SlashCmdList[key] for programmatic callers (e.g. ChatActions).
    SlashCmdList[key] = handler

    registeredSlash[key] = handler
    return true
end

-- ---------------------------------------------------------------------------
-- Sender helpers (server-push may omit sender)
-- ---------------------------------------------------------------------------
local function normalizedName(value)
    return tostring(value or ""):gsub("%s+", ""):lower()
end

local function shortName(value)
    value = tostring(value or "")
    local bare = value:match("^([^%-]+)")
    return normalizedName(bare or value)
end

---Проверка, что addon-message от самого игрока (или server-push с пустым sender).
---@param sender? string
---@return boolean
function ns.Util.IsSelfSender(sender)
    if sender == nil or sender == "" then
        return true
    end

    local name, realm
    if UnitFullName then
        name, realm = UnitFullName("player")
    end
    if not name or name == "" then
        name = UnitName and UnitName("player")
    end
    if not name or name == "" then
        return false
    end

    local actual = normalizedName(sender)
    local own = normalizedName(name)
    if actual == own then
        return true
    end
    if realm and realm ~= "" and actual == normalizedName(name .. "-" .. realm) then
        return true
    end
    if shortName(sender) == own then
        return true
    end
    if Ambiguate then
        local ambi = normalizedName(Ambiguate(sender, "none"))
        if ambi == own or shortName(ambi) == own then
            return true
        end
    end
    return false
end
