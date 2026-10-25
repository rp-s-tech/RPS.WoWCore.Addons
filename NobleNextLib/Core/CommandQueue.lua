-- Core/CommandQueue.lua — серийная очередь GM-команд (self-whisper)
-- Отправка через ns.SendGmWhisper / ns.RunGmCommand; ответ — expectPrefix (CHAT_MSG_ADDON) или fire-and-forget.

local ns = LibStub("NobleNextLib-1.0").Runtime

ns.CommandQueue = ns.CommandQueue or {}

local DEFAULT_TIMEOUT = 10

---@class NobleNextCommandOpts
---@field timeout? number секунды; при expectPrefix по умолчанию 10
---@field onResult? fun(ok: boolean, payload: any)
---@field tag? string
---@field expectPrefix? string ждать CHAT_MSG_ADDON с этим префиксом
---@field requiredLevel? number минимальный подтверждённый уровень; по умолчанию DM (1)

local queue = {}
local active = nil -- { command, opts, unreg, timerCancel }
local pumping = false
local clearingDepth = 0

local function callResult(entry, ok, payload)
    local cb = entry and entry.opts and entry.opts.onResult
    if type(cb) ~= "function" then
        return
    end
    local success, err = pcall(cb, ok, payload)
    if not success and ns.PrintError then
        ns.PrintError("CommandQueue onResult: " .. tostring(err))
    end
end

local function cancelTimer(entry)
    if entry and entry.timerCancel then
        entry.timerCancel()
        entry.timerCancel = nil
    end
end

local function detachExpect(entry)
    if entry and entry.unreg then
        entry.unreg()
        entry.unreg = nil
    end
end

local function finishActive(ok, payload)
    local entry = active
    if not entry then
        return
    end
    cancelTimer(entry)
    detachExpect(entry)
    active = nil
    callResult(entry, ok, payload)
    pumping = false
    -- следующий тик — не блокировать handler addon message
    C_Timer.After(0, function()
        ns.CommandQueue._Pump()
    end)
end

function ns.CommandQueue._Pump()
    if active or pumping or clearingDepth > 0 then
        return
    end
    if #queue == 0 then
        return
    end

    pumping = true
    local entry = table.remove(queue, 1)
    active = entry

    local opts = entry.opts or {}
    local expectPrefix = opts.expectPrefix
    local timeout = opts.timeout
    if timeout == nil then
        timeout = expectPrefix and DEFAULT_TIMEOUT or 0
    end

    if expectPrefix and ns.RegisterAddonPrefix then
        entry.unreg = ns.RegisterAddonPrefix(expectPrefix, function(prefix, message, channel, sender, ...)
            if active ~= entry then
                return
            end
            if not ns.Util.IsSelfSender(sender) then
                return
            end
            finishActive(true, {
                prefix = prefix,
                message = message,
                channel = channel,
                sender = sender,
            })
        end)
    end

    -- Recheck when dequeued, not only when the extension enqueues its action.
    -- A queued GM action must not survive a demotion to DM or expired identity.
    local requiredLevel = entry.requiredLevel
    if not ns.Access or not ns.Access.Allows(requiredLevel) then
        finishActive(false, { reason = "access_denied", command = entry.command,
            requiredLevel = requiredLevel })
        return
    end

    local sent = false
    if ns.SendGmWhisper then
        sent = ns.SendGmWhisper(entry.command) and true or false
    elseif ns.RunGmCommand then
        sent = ns.RunGmCommand(entry.command) and true or false
    end

    if not sent then
        finishActive(false, { reason = "send_failed", command = entry.command })
        return
    end

    -- без expectPrefix: сразу следующий (сериальная отправка без ожидания ответа)
    if not expectPrefix then
        finishActive(true, { reason = "sent", command = entry.command })
        return
    end

    if timeout and timeout > 0 then
        local cancelled = false
        entry.timerCancel = function()
            cancelled = true
        end
        C_Timer.After(timeout, function()
            if cancelled or active ~= entry then
                return
            end
            finishActive(false, { reason = "timeout", command = entry.command, expectPrefix = expectPrefix })
        end)
    end
end

---Поставить GM-команду в очередь.
---@param commandText string текст команды (с точкой или без)
---@param opts? NobleNextCommandOpts
---@return number|nil queueId индекс в очереди (1-based на момент enqueue) или nil
function ns.EnqueueCommand(commandText, opts)
    if commandText == nil or tostring(commandText):match("^%s*$") then
        return nil
    end
    opts = opts or {}
    queue[#queue + 1] = {
        command = tostring(commandText),
        opts = opts,
        requiredLevel = opts.requiredLevel or 1,
    }
    local id = #queue
    if ns.PrintDebug then
        ns.PrintDebug(string.format("EnqueueCommand #%d%s: %s",
            id,
            opts.tag and (" [" .. opts.tag .. "]") or "",
            tostring(commandText)))
    end
    ns.CommandQueue._Pump()
    return id
end

---Очистить очередь и отменить активную команду.
---@param tag? string если задан — только записи с этим tag
function ns.ClearCommandQueue(tag)
    local function shouldClear(entry)
        if not tag then
            return true
        end
        return entry.opts and entry.opts.tag == tag
    end

    -- Detach the whole cancellation set before notifying any callback. Callbacks
    -- may enqueue fresh work, but cannot pump a command selected for cancellation.
    clearingDepth = clearingDepth + 1
    local cancelled, kept = {}, {}
    if active and shouldClear(active) then
        local entry = active
        cancelTimer(entry)
        detachExpect(entry)
        active = nil
        pumping = false
        cancelled[#cancelled + 1] = entry
    end

    for i = 1, #queue do
        local entry = queue[i]
        if shouldClear(entry) then
            cancelled[#cancelled + 1] = entry
        else
            kept[#kept + 1] = entry
        end
    end
    queue = kept

    for _, entry in ipairs(cancelled) do
        callResult(entry, false, { reason = "cancel", command = entry.command })
    end
    clearingDepth = clearingDepth - 1

    -- Fresh callback-enqueued work remains queued, in order, and goes through
    -- the usual live access fence only after every cancellation notification.
    if clearingDepth == 0 and not active then
        C_Timer.After(0, function()
            ns.CommandQueue._Pump()
        end)
    end
end

function ns.CommandQueue.GetPendingCount()
    return #queue + (active and 1 or 0)
end

local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
logoutFrame:SetScript("OnEvent", function()
    ns.ClearCommandQueue()
end)
