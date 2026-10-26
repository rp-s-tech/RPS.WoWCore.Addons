-- Core/AddonMessages.lua — реестр префиксов addon message + диспетчер CHAT_MSG_ADDON
-- Выбор: несколько handler'ов на префикс (append). Замена — opts.replace = true.
-- Keyed regs: opts.key — повторный key заменяет; один и тот же handler не дублируется.

local ns = LibStub("NobleNextLib-1.0").Runtime

ns.AddonMessages = ns.AddonMessages or {}

-- prefix -> { { handler=fn, key?=string }, ... }
local handlersByPrefix = {}

local function ensureRegistered(prefix)
    if type(prefix) ~= "string" or prefix == "" then
        return false
    end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    end
    return true
end

local function removeFromList(list, predicate)
    for i = #list, 1, -1 do
        if predicate(list[i]) then
            table.remove(list, i)
        end
    end
end

local function isRegistered(prefix, registration)
    for _, entry in ipairs(handlersByPrefix[prefix] or {}) do
        if entry == registration then return true end
    end
    return false
end

local function disposer(prefix, registration)
    return function()
        local list = handlersByPrefix[prefix]
        if not list then return end
        removeFromList(list, function(entry) return entry == registration end)
        if #list == 0 then handlersByPrefix[prefix] = nil end
    end
end

---Зарегистрировать обработчик addon-префикса.
---@param prefix string
---@param handler fun(prefix: string, message: string, channel: string, sender: string, ...)
---@param opts? { replace?: boolean, key?: string }
---@return function? unregister
function ns.RegisterAddonPrefix(prefix, handler, opts)
    if type(handler) ~= "function" or type(prefix) ~= "string" or prefix == "" then
        return nil
    end

    ensureRegistered(prefix)
    opts = opts or {}
    local key = opts.key
    local registration = { handler = handler, key = key }

    if opts.replace then
        handlersByPrefix[prefix] = { registration }
    else
        local list = handlersByPrefix[prefix]
        if not list then
            list = {}
            handlersByPrefix[prefix] = list
        end

        if key then
            removeFromList(list, function(entry)
                return entry.key == key
            end)
        else
            -- Защита от повторного добавления того же function ref
            for i = 1, #list do
                if list[i].handler == handler then
                    return disposer(prefix, list[i])
                end
            end
        end

        list[#list + 1] = registration
    end

    return disposer(prefix, registration)
end

function ns.AddonMessages.Dispatch(prefix, message, channel, sender, ...)
    local list = handlersByPrefix[prefix]
    if not list then
        return
    end
    -- снимок: handler может снять себя (unregister) во время вызова
    local n = #list
    local snapshot = {}
    for i = 1, n do
        snapshot[i] = list[i]
    end
    for i = 1, n do
        local entry = snapshot[i]
        if isRegistered(prefix, entry) then
            local ok, err = pcall(entry.handler, prefix, message, channel, sender, ...)
            if not ok and ns.PrintError then
                local label = entry.key and (tostring(prefix) .. "/" .. entry.key) or tostring(prefix)
                ns.PrintError("AddonMessages[" .. label .. "]: " .. tostring(err))
            end
        end
    end
end

function ns.AddonMessages.HasHandlers(prefix)
    local list = handlersByPrefix[prefix]
    return list ~= nil and #list > 0
end

if ns.ADDON_PREFIX then
    ensureRegistered(ns.ADDON_PREFIX)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, prefix, message, channel, sender, ...)
    if event ~= "CHAT_MSG_ADDON" then
        return
    end
    ns.AddonMessages.Dispatch(prefix, message, channel, sender, ...)
end)
