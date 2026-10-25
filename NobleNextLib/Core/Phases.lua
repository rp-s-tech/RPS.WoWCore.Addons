-- Core/Phases.lua — клиент API протокола NN_RPPHASE.
-- ВАЖНО: phase/character/version IDs остаются decimal strings: не tonumber().

local ns = LibStub("NobleNextLib-1.0").Runtime

ns.Phases = ns.Phases or {}
local P = ns.Phases

P.PREFIX = "NN_RPPHASE"
-- CAPS→CONTEXT→LIST sync + multipart LIST with capability fields needs headroom.
P.TIMEOUT = 15
P.State = P.State or {
    current = nil,
    list = {},
    details = {},
    data = {},
    rules = {},
    caps = nil,
    lastError = nil,
}

local bitlib = bit or bit32
local requestSequence = 0
local pending = {}
local assemblies = {}
local listeners = {}
local pendingTransition = nil
-- Serialize self-whisper bursts: CAPS/CONTEXT/LIST must not race on the same channel.
local sendQueue = {}
local sendBusy = false

local function decimalId(value, allowZero)
    value = tostring(value or "")
    if not value:match("^%d+$") or (not allowZero and value == "0") then
        return nil
    end
    value = value:gsub("^0+", "")
    if value == "" then
        return allowZero and "0" or nil
    end
    return value
end

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalizeU32(value)
    if value < 0 then
        return value + 4294967296
    end
    return value
end

-- FNV-1a 32-bit. Умножение разбито на 16-bit части, чтобы Lua double не терял точность.
local function fnv1a(value)
    if not bitlib or not bitlib.bxor then
        return nil
    end
    local hash = 2166136261
    for i = 1, #value do
        hash = normalizeU32(bitlib.bxor(hash, value:byte(i)))
        local low = hash % 65536
        local high = math.floor(hash / 65536)
        hash = (low * 403 + ((low * 256 + high * 403) % 65536) * 65536) % 4294967296
    end
    local digits = "0123456789abcdef"
    local out = {}
    for i = 8, 1, -1 do
        out[i] = digits:sub((hash % 16) + 1, (hash % 16) + 1)
        hash = math.floor(hash / 16)
    end
    return table.concat(out)
end

local function escapeField(value)
    local hex = "0123456789abcdef"
    local out = {}
    value = tostring(value or "")
    for i = 1, #value do
        local byte = value:byte(i)
        if byte == 92 then
            out[#out + 1] = "\\\\"
        elseif byte == 124 then
            out[#out + 1] = "\\|"
        elseif byte == 10 then
            out[#out + 1] = "\\n"
        elseif byte == 13 then
            out[#out + 1] = "\\r"
        elseif byte == 9 then
            out[#out + 1] = "\\t"
        elseif byte < 32 or byte == 127 or byte >= 128 then
            out[#out + 1] = "\\x" .. hex:sub(math.floor(byte / 16) + 1, math.floor(byte / 16) + 1)
                .. hex:sub((byte % 16) + 1, (byte % 16) + 1)
        else
            out[#out + 1] = string.char(byte)
        end
    end
    return table.concat(out)
end

local function unescapeField(value)
    local out = {}
    local i = 1
    value = tostring(value or "")
    while i <= #value do
        local char = value:sub(i, i)
        if char ~= "\\" then
            out[#out + 1] = char
            i = i + 1
        else
            local escaped = value:sub(i + 1, i + 1)
            if escaped == "" then
                return nil
            elseif escaped == "\\" or escaped == "|" then
                out[#out + 1] = escaped
                i = i + 2
            elseif escaped == "n" then
                out[#out + 1] = "\n"
                i = i + 2
            elseif escaped == "r" then
                out[#out + 1] = "\r"
                i = i + 2
            elseif escaped == "t" then
                out[#out + 1] = "\t"
                i = i + 2
            elseif escaped == "x" then
                local hex = value:sub(i + 2, i + 3)
                local byte = tonumber(hex, 16)
                if not byte then
                    return nil
                end
                out[#out + 1] = string.char(byte)
                i = i + 4
            else
                return nil
            end
        end
    end
    return table.concat(out)
end

-- Делит только по неэкранированным "|"; содержимое item остаётся escaped до checksum.
local function splitRaw(value)
    local parts, buffer = {}, {}
    local escaped = false
    for i = 1, #value do
        local char = value:sub(i, i)
        if char == "|" and not escaped then
            parts[#parts + 1] = table.concat(buffer)
            buffer = {}
        else
            buffer[#buffer + 1] = char
        end
        if char == "\\" and not escaped then
            escaped = true
        else
            escaped = false
        end
    end
    parts[#parts + 1] = table.concat(buffer)
    return parts
end

local function splitEscapedLines(value)
    local lines, start = {}, 1
    local i = 1
    while i <= #value - 1 do
        if value:sub(i, i + 1) == "\\n" then
            local slashes = 0
            local j = i - 1
            while j >= 1 and value:sub(j, j) == "\\" do
                slashes = slashes + 1
                j = j - 1
            end
            if slashes % 2 == 0 then
                lines[#lines + 1] = value:sub(start, i - 1)
                start = i + 2
                i = i + 2
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
    lines[#lines + 1] = value:sub(start)
    return lines
end

local function parseRecord(raw)
    local record = {}
    for _, token in ipairs(splitRaw(raw)) do
        local key, rawValue = token:match("^([^=]+)=(.*)$")
        if key then
            local value = unescapeField(rawValue)
            if value == nil then
                return nil
            end
            record[key] = value
        end
    end
    return record
end

local function parseRecords(raw)
    local records = {}
    for _, line in ipairs(splitEscapedLines(raw)) do
        if line ~= "" then
            local record = parseRecord(line)
            if not record then
                return nil
            end
            records[#records + 1] = record
        end
    end
    return records
end

local function base64Encode(value)
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local out = {}
    for i = 1, #value, 3 do
        local a, b, c = value:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        out[#out + 1] = alphabet:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
        out[#out + 1] = alphabet:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
        out[#out + 1] = b and alphabet:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or "="
        out[#out + 1] = c and alphabet:sub(n % 64 + 1, n % 64 + 1) or "="
    end
    return table.concat(out)
end

local function base64Decode(value)
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local decode = {}
    for i = 1, #alphabet do
        decode[alphabet:sub(i, i)] = i - 1
    end
    local out = {}
    value = tostring(value or "")
    if #value % 4 ~= 0 then
        return nil
    end
    for i = 1, #value, 4 do
        local a, b = decode[value:sub(i, i)], decode[value:sub(i + 1, i + 1)]
        local c, d = decode[value:sub(i + 2, i + 2)], decode[value:sub(i + 3, i + 3)]
        local padC, padD = value:sub(i + 2, i + 2) == "=", value:sub(i + 3, i + 3) == "="
        if not a or not b or (not padC and not c) or (not padD and not d) or (padC and not padD) then
            return nil
        end
        local n = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if not padC then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
        if not padD then out[#out + 1] = string.char(n % 256) end
    end
    return table.concat(out)
end

local function emit(event, ...)
    local handlers = listeners[event]
    if not handlers then
        return
    end
    for i = 1, #handlers do
        local ok, err = pcall(handlers[i], ...)
        if not ok and ns.PrintError then
            ns.PrintError("Phases[" .. event .. "]: " .. tostring(err))
        end
    end
end

function P.On(event, handler)
    if type(event) ~= "string" or type(handler) ~= "function" then
        return nil
    end
    listeners[event] = listeners[event] or {}
    listeners[event][#listeners[event] + 1] = handler
    return function()
        local handlers = listeners[event] or {}
        for i = #handlers, 1, -1 do
            if handlers[i] == handler then
                table.remove(handlers, i)
            end
        end
    end
end

local function ownWhisperTargets()
    -- Prefer bare UnitName first (AIO/Transmog). Name-Realm often fails CanWhisper
    -- for self-target on private realms / connected-realm clients.
    local targets, seen = {}, {}
    local function push(value)
        value = tostring(value or "")
        if value == "" or seen[value] then
            return
        end
        seen[value] = true
        targets[#targets + 1] = value
    end
    push(UnitName and UnitName("player"))
    local fullName, realm = UnitFullName and UnitFullName("player")
    push(fullName)
    if fullName and realm and realm ~= "" then
        push(fullName .. "-" .. realm)
    end
    return targets
end

local function addonSendSucceeded(result)
    -- Legacy API: nil/true = ok, false = fail.
    if result == false then
        return false
    end
    if result == true or result == nil then
        return true
    end
    -- Retail/Midnight: Enum.SendAddonMessageResult.Success == 0 (truthy in Lua!).
    local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success
    if success ~= nil then
        return result == success
    end
    return result == 0
end

local function ensurePrefixRegistered()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(P.PREFIX)
    end
end

local function sendRaw(message)
    -- Deferred/multipart traffic must observe the current server-confirmed role.
    if not ns.Access or not ns.Access.Allows(1) then
        return false, "dm_access_required"
    end
    ensurePrefixRegistered()
    local targets = ownWhisperTargets()
    if #targets == 0 then
        return false, "player name unavailable"
    end
    local lastResult = nil
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        for i = 1, #targets do
            lastResult = C_ChatInfo.SendAddonMessage(P.PREFIX, message, "WHISPER", targets[i])
            if addonSendSucceeded(lastResult) then
                return true
            end
        end
        return false, "addon send failed:" .. tostring(lastResult)
    end
    if SendAddonMessage then
        SendAddonMessage(P.PREFIX, message, "WHISPER", targets[1])
        return true
    end
    return false, "addon messaging unavailable"
end

local function pumpSendQueue()
    if sendBusy or #sendQueue == 0 then
        return
    end
    sendBusy = true
    local job = table.remove(sendQueue, 1)
    local ok, sent, errorText = pcall(sendRaw, job.message)
    if not ok then
        sendBusy = false
        if job.onSent then
            job.onSent(false, "send_exception:" .. tostring(sent))
        end
        pumpSendQueue()
        return
    end
    if not sent then
        sendBusy = false
        if job.onSent then
            job.onSent(false, errorText or "send_failed")
        end
        pumpSendQueue()
        return
    end
    local onSentOk, onSentErr = pcall(function()
        if job.onSent then
            job.onSent(true)
        end
    end)
    if not onSentOk and ns.PrintError then
        ns.PrintError("Phases send onSent: " .. tostring(onSentErr))
    end
    -- Small delay keeps addon-whisper packets ordered on the client→server channel.
    C_Timer.After(0.05, function()
        sendBusy = false
        pumpSendQueue()
    end)
end

local function enqueueRaw(message, onSent)
    sendQueue[#sendQueue + 1] = { message = message, onSent = onSent }
    pumpSendQueue()
end

local function complete(requestId, ok, response)
    local entry = pending[requestId]
    pending[requestId] = nil
    if not entry or type(entry.callback) ~= "function" then
        return
    end
    local success, err = pcall(entry.callback, ok, response)
    if not success and ns.PrintError then
        ns.PrintError("Phases callback: " .. tostring(err))
    end
end

local function nextRequestId()
    requestSequence = requestSequence + 1
    return "p" .. tostring(requestSequence)
end

local function request(operation, fields, expectedType, callback)
    local requestId = nextRequestId()
    local parts = { operation, requestId }
    for i = 1, #(fields or {}) do
        parts[#parts + 1] = escapeField(fields[i])
    end
    pending[requestId] = {
        callback = callback,
        expectedType = expectedType,
        payload = nil,
        result = nil,
    }
    enqueueRaw(table.concat(parts, "|"), function(sent, errorText)
        if not sent then
            complete(requestId, false, { reason = errorText or "send_failed" })
            return
        end
        C_Timer.After(P.TIMEOUT, function()
            if pending[requestId] then
                P.State.lastError = "timeout"
                complete(requestId, false, { reason = "timeout", requestId = requestId })
            end
        end)
    end)
    return requestId
end

local function finishIfReady(requestId)
    local entry = pending[requestId]
    if not entry then
        return
    end
    -- Multipart upload подтверждает каждый chunk как `accepted`; это не финал.
    if entry.result and entry.result.status ~= "ok" and entry.result.status ~= "accepted" then
        P.State.lastError = entry.result.detail or entry.result.status
        complete(requestId, false, entry.result)
        return
    end
    if entry.result and entry.result.status == "ok"
        and (not entry.expectedType or entry.payload ~= nil)
    then
        complete(requestId, true, entry.payload or entry.result)
    end
end

local function failPending(requestId, reason)
    reason = tostring(reason or "protocol_error")
    P.State.lastError = reason
    local entry = pending[requestId]
    if entry then
        complete(requestId, false, { reason = reason, requestId = requestId })
    end
end

local function normalizePayload(typeName, raw)
    if typeName == "LIST" or typeName == "MEMBERS" then
        local records = parseRecords(raw)
        if not records then
            return nil
        end
        return records
    end
    local record = parseRecord(raw)
    if not record then
        return nil
    end
    return record
end

local function applyPayload(typeName, requestId, payload)
    if typeName == "CONTEXT" then
        local previous = P.State.current
        P.State.current = payload
        emit("context", payload, previous)
        if requestId == "0" or pendingTransition then
            local transition = pendingTransition
            pendingTransition = nil
            emit("NOBLENEXT_PHASE_CHANGED", payload, previous, transition)
        end
    elseif typeName == "LIST" then
        P.State.list = payload
        emit("list", payload)
    elseif typeName == "INFO" then
        local phaseId = decimalId(payload.phase, true)
        if phaseId then
            payload.phase = phaseId
            P.State.details[phaseId] = P.State.details[phaseId] or {}
            P.State.details[phaseId].info = payload
        end
        emit("info", payload)
    elseif typeName == "MEMBERS" then
        local phaseId = payload[1] and decimalId(payload[1].phase, true)
        if phaseId then
            P.State.details[phaseId] = P.State.details[phaseId] or {}
            P.State.details[phaseId].members = payload
        end
        emit("members", payload)
    elseif typeName == "RULES" then
        local phaseId = decimalId(payload.phase, true)
        if phaseId then
            P.State.rules[phaseId] = payload
            P.State.details[phaseId] = P.State.details[phaseId] or {}
            P.State.details[phaseId].rules = payload
        end
        emit("rules", payload)
    elseif typeName == "CAPS" then
        P.State.caps = payload
        emit("caps", payload)
    elseif typeName == "DATA" then
        if payload.value and payload.encoding == "base64" then
            payload.decodedValue = base64Decode(payload.value)
        end
        local phaseId = decimalId(payload.phase, true)
        if phaseId and payload.namespace and payload.key then
            P.State.data[phaseId] = P.State.data[phaseId] or {}
            P.State.data[phaseId][payload.namespace .. ":" .. payload.key] = payload
        end
        emit("data", payload)
    elseif typeName == "EVENT" then
        pendingTransition = payload.event == "transition" and payload or pendingTransition
        emit("event", payload)
    end
end

-- Called by the shared transport below, independent of optional Phase panels.
function P.HandlePacket(message)
    local parts = splitRaw(tostring(message or ""))
    local typeName = (parts[1] or ""):upper()
    local requestId = parts[2] or ""
    local state = (parts[3] or ""):lower()
    if typeName == "" or requestId == "" then
        return
    end

    if typeName == "RESULT" then
        local payload = table.concat(parts, "|", 7)
        local expectedChecksum = parts[6]
        if not expectedChecksum or fnv1a(payload) ~= expectedChecksum:lower() then
            failPending(requestId, "invalid RESULT checksum")
            return
        end
        local result = {
            status = unescapeField(parts[7] or "") or "error",
            detail = unescapeField(parts[8] or "") or "",
        }
        local entry = pending[requestId]
        if entry then
            entry.result = result
            finishIfReady(requestId)
        end
        emit("result", requestId, result)
        return
    end

    local key = typeName .. "|" .. requestId
    if state == "begin" then
        local count = tonumber(parts[5] or "")
        if not count or count < 1 or not parts[6] then
            failPending(requestId, "malformed " .. typeName .. " begin")
            return
        end
        assemblies[key] = { count = count, checksum = parts[6]:lower(), chunks = {} }
        return
    end
    local assembly = assemblies[key]
    if not assembly then
        -- Orphan item/end without begin: fail the matching pending request immediately.
        if state == "item" or state == "end" then
            failPending(requestId, "orphan " .. typeName .. " " .. state)
        end
        return
    end
    if state == "item" then
        local index, count = tonumber(parts[4] or ""), tonumber(parts[5] or "")
        if index and count == assembly.count and index >= 1 and index <= assembly.count
            and type(parts[6]) == "string" and parts[6]:lower() == assembly.checksum
        then
            -- Chunk body may contain raw '|' (value-escaped wire). Rejoin tail.
            -- Taking only parts[7] truncates CAPS/LIST and fails FNV checksum.
            assembly.chunks[index] = table.concat(parts, "|", 7)
        else
            assemblies[key] = nil
            failPending(requestId, "malformed " .. typeName .. " item")
        end
        return
    end
    if state ~= "end" or tonumber(parts[5] or "") ~= assembly.count or (parts[6] or ""):lower() ~= assembly.checksum then
        assemblies[key] = nil
        failPending(requestId, "malformed " .. typeName .. " end")
        return
    end
    local chunks = {}
    for index = 1, assembly.count do
        if assembly.chunks[index] == nil then
            assemblies[key] = nil
            failPending(requestId, "incomplete " .. typeName .. " chunks")
            return
        end
        chunks[#chunks + 1] = assembly.chunks[index]
    end
    assemblies[key] = nil
    local raw = table.concat(chunks)
    if fnv1a(raw) ~= assembly.checksum then
        failPending(requestId, "invalid " .. typeName .. " checksum")
        return
    end
    local payload = normalizePayload(typeName, raw)
    if payload == nil then
        failPending(requestId, "malformed " .. typeName .. " payload")
        return
    end
    applyPayload(typeName, requestId, payload)
    local entry = pending[requestId]
    if entry and entry.expectedType == typeName then
        entry.payload = payload
        finishIfReady(requestId)
    end
end

-- Ordered CAPS → CONTEXT → LIST used by Codex refresh.
function P.Sync(callback)
    local result = { caps = nil, current = nil, list = nil }
    P.GetCaps(function(okCaps, caps)
        result.caps = caps
        if not okCaps then
            if callback then callback(false, { reason = (caps and (caps.detail or caps.reason)) or "caps_failed", stage = "caps" }) end
            return
        end
        P.GetCurrent(function(okContext, current)
            result.current = current
            if not okContext then
                if callback then callback(false, { reason = (current and (current.detail or current.reason)) or "context_failed", stage = "context" }) end
                return
            end
            P.List(function(okList, list)
                result.list = list or {}
                if callback then
                    callback(okList, okList and result or {
                        reason = (list and (list.detail or list.reason)) or "list_failed",
                        stage = "list",
                        caps = result.caps,
                        current = result.current,
                    })
                end
            end)
        end)
    end)
end

function P.GetCurrent(callback)
    return request("CONTEXT", { "get" }, "CONTEXT", callback)
end

function P.List(callback)
    return request("LIST", {}, "LIST", callback)
end

-- Phases where caller account is owner (not merely manager/member).
function P.ListOwned(callback)
    return request("LIST", { "owned" }, "LIST", callback)
end

function P.GetCaps(callback)
    return request("CAPS", {}, "CAPS", callback)
end

-- scope: "global" (default) or "map"; mapId required only for map scope.
function P.Create(name, description, scope, mapId, callback)
    name = trim(name)
    description = trim(description)
    scope = trim(scope or "global"):lower()
    if name == "" then
        if callback then callback(false, { reason = "name_required" }) end
        return nil
    end
    if scope ~= "global" and scope ~= "map" then
        if callback then callback(false, { reason = "invalid_scope" }) end
        return nil
    end
    local mapToken = ""
    if scope == "map" then
        mapToken = decimalId(mapId)
        if not mapToken then
            if callback then callback(false, { reason = "map_id_required" }) end
            return nil
        end
    end
    return request("CREATE", { name, scope, mapToken, description }, "INFO", callback)
end

function P.Archive(phaseId, callback)
    phaseId = decimalId(phaseId)
    if not phaseId then
        if callback then callback(false, { reason = "invalid_phase_id" }) end
        return nil
    end
    return request("ARCHIVE", { phaseId, "confirm" }, nil, callback)
end

function P.Unarchive(phaseId, callback)
    phaseId = decimalId(phaseId)
    if not phaseId then
        if callback then callback(false, { reason = "invalid_phase_id" }) end
        return nil
    end
    return request("UNARCHIVE", { phaseId, "confirm" }, nil, callback)
end

function P.Invite(phaseId, playerName, role, callback)
    phaseId = decimalId(phaseId)
    playerName = trim(playerName)
    role = trim(role or "viewer"):lower()
    if not phaseId or playerName == "" then
        if callback then callback(false, { reason = "phase_and_player_required" }) end
        return nil
    end
    return request("INVITE", { phaseId, playerName, role }, nil, callback)
end

function P.Revoke(phaseId, playerName, callback)
    phaseId = decimalId(phaseId)
    playerName = trim(playerName)
    if not phaseId or playerName == "" then
        if callback then callback(false, { reason = "phase_and_player_required" }) end
        return nil
    end
    return request("REVOKE", { phaseId, playerName, "confirm" }, nil, callback)
end

function P.SetRole(phaseId, playerName, role, callback)
    phaseId = decimalId(phaseId)
    playerName = trim(playerName)
    role = trim(role or ""):lower()
    if not phaseId or playerName == "" or role == "" then
        if callback then callback(false, { reason = "phase_player_role_required" }) end
        return nil
    end
    return request("SET_ROLE", { phaseId, playerName, role }, nil, callback)
end

function P.SetPublic(phaseId, isPublic, callback)
    phaseId = decimalId(phaseId)
    if not phaseId then
        if callback then callback(false, { reason = "invalid_phase_id" }) end
        return nil
    end
    local token = (isPublic == true or isPublic == "1" or isPublic == 1) and "true" or "false"
    return request("SET_PUBLIC", { phaseId, token }, nil, callback)
end

function P.Rename(phaseId, name, callback)
    phaseId = decimalId(phaseId)
    name = trim(name)
    if not phaseId or name == "" then
        if callback then callback(false, { reason = "phase_and_name_required" }) end
        return nil
    end
    return request("RENAME", { phaseId, name }, "INFO", callback)
end

function P.SetOwner(phaseId, characterName, callback)
    phaseId = decimalId(phaseId)
    characterName = trim(characterName)
    if not phaseId or characterName == "" then
        if callback then callback(false, { reason = "phase_and_owner_required" }) end
        return nil
    end
    return request("SET_OWNER", { phaseId, characterName, "force" }, nil, callback)
end

-- Снимок одной phase: INFO → MEMBERS → RULES (сериализовано).
function P.Get(phaseId, callback)
    phaseId = decimalId(phaseId)
    if not phaseId then
        if callback then callback(false, { reason = "invalid_phase_id" }) end
        return nil
    end
    local result = { phase = phaseId }
    request("INFO", { phaseId }, "INFO", function(okInfo, info)
        result.info = info
        if not okInfo then
            if callback then callback(false, result) end
            return
        end
        request("MEMBERS", { phaseId }, "MEMBERS", function(okMembers, members)
            result.members = members
            if not okMembers then
                if callback then callback(false, result) end
                return
            end
            request("RULES", { phaseId }, "RULES", function(okRules, rules)
                result.rules = rules
                if callback then callback(okRules, result) end
            end)
        end)
    end)
    return phaseId
end

function P.Enter(phaseId, callback)
    phaseId = decimalId(phaseId)
    if not phaseId then
        if callback then callback(false, { reason = "invalid_phase_id" }) end
        return nil
    end
    return request("CONTEXT", { "enter", phaseId }, "CONTEXT", callback)
end

function P.Goto(phaseId, callback)
    phaseId = decimalId(phaseId)
    if not phaseId then
        if callback then callback(false, { reason = "invalid_phase_id" }) end
        return nil
    end
    return request("CONTEXT", { "goto", phaseId }, "CONTEXT", callback)
end

function P.Leave(callback)
    return request("CONTEXT", { "leave" }, "CONTEXT", callback)
end

function P.GetData(namespace, key, callback)
    local current = P.State.current
    local phaseId = current and decimalId(current.phase)
    if not phaseId or trim(namespace) == "" or trim(key) == "" then
        if callback then callback(false, { reason = "active_phase_and_key_required" }) end
        return nil
    end
    return request("DATA", { "get", phaseId, trim(namespace), trim(key) }, "DATA", callback)
end

function P.SetData(namespace, key, value, expectedVersion, callback)
    local current = P.State.current
    local phaseId = current and decimalId(current.phase)
    expectedVersion = decimalId(expectedVersion or "0", true)
    namespace, key = trim(namespace), trim(key)
    if not phaseId or namespace == "" or key == "" or not expectedVersion then
        if callback then callback(false, { reason = "active_phase_namespace_key_version_required" }) end
        return nil
    end

    local encoded = base64Encode(tostring(value or ""))
    local checksum = fnv1a(encoded)
    if not checksum then
        if callback then callback(false, { reason = "fnv_unavailable" }) end
        return nil
    end
    local chunkSize = 172 -- <= 512 chunks for max 64 KiB value and < server payload limit.
    local count = math.max(1, math.ceil(#encoded / chunkSize))
    if count > 512 then
        if callback then callback(false, { reason = "value_too_large" }) end
        return nil
    end

    local requestId = nextRequestId()
    pending[requestId] = { callback = callback, expectedType = "DATA", payload = nil, result = nil }
    local function queueFields(fields, onSent)
        local escaped = {}
        for i = 1, #fields do escaped[i] = escapeField(fields[i]) end
        enqueueRaw(table.concat(escaped, "|"), onSent)
    end
    queueFields({
        "DATA", requestId, "put_begin", phaseId, namespace, key, expectedVersion, tostring(count), checksum,
    }, function(sent, errorText)
        if not sent then
            complete(requestId, false, { reason = errorText or "send_failed" })
            return
        end
        local index = 1
        local function sendNext()
            if index > count then
                queueFields({ "DATA", requestId, "put_end" }, function(endSent, endError)
                    if not endSent then
                        complete(requestId, false, { reason = endError or "send_failed" })
                        return
                    end
                    C_Timer.After(P.TIMEOUT, function()
                        if pending[requestId] then
                            P.State.lastError = "timeout"
                            complete(requestId, false, { reason = "timeout", requestId = requestId })
                        end
                    end)
                end)
                return
            end
            local chunk = encoded:sub((index - 1) * chunkSize + 1, index * chunkSize)
            local current = index
            index = index + 1
            queueFields({ "DATA", requestId, "put_item", tostring(current), tostring(count), chunk }, function(itemSent, itemError)
                if not itemSent then
                    complete(requestId, false, { reason = itemError or "send_failed" })
                    return
                end
                sendNext()
            end)
        end
        sendNext()
    end)
    return requestId
end

-- Protocol receipt belongs to the runtime, not to a load-on-demand panel.
local function handleMessage(prefix, message, _, sender)
    if prefix == P.PREFIX and ns.Util.IsSelfSender(sender) then
        P.HandlePacket(message)
    end
end
ns.RegisterAddonPrefix(P.PREFIX, handleMessage, { key = "phase" })
local phaseEvents = CreateFrame("Frame")
phaseEvents:RegisterEvent("PLAYER_LOGIN")
phaseEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
phaseEvents:SetScript("OnEvent", ensurePrefixRegistered)
