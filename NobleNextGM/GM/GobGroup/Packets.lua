-- Loaded through the NobleNextGM private extension namespace.
-- GM/GobGroup/Packets.lua — разбор chunked NN_GOBGROUP (без CHAT_MSG_SYSTEM)

local _, ns = ...

ns.GobGroupPackets = ns.GobGroupPackets or {}
local P = ns.GobGroupPackets

P.PREFIX = "NN_GOBGROUP"

local listeners = {}

local capsChunks = {}
local capsChunkCount = nil
local capsChunkBase = nil
local capsMap = {}
local capsReady = false

local infoPending = nil
local listPending = nil
local nearPending = nil
local blueprintListPending = nil

local state = {
    capsMap = capsMap,
    capsReady = false,
    info = nil,
    list = nil,
    near = nil,
    status = nil,
    lastResult = nil,
    blueprintList = nil,
    blueprintInfo = nil,
    blueprintStatus = nil,
    lastBlueprintResult = nil,
}

P.State = state

local function notify(event, payload)
    local list = listeners[event]
    if not list then
        return
    end
    for i = 1, #list do
        local ok, err = pcall(list[i], payload)
        if not ok and ns.PrintError then
            ns.PrintError("GobGroupPackets[" .. event .. "]: " .. tostring(err))
        end
    end
end

function P.On(event, handler)
    if type(handler) ~= "function" or type(event) ~= "string" then
        return nil
    end
    local list = listeners[event]
    if not list then
        list = {}
        listeners[event] = list
    end
    list[#list + 1] = handler
    return function()
        for i = #list, 1, -1 do
            if list[i] == handler then
                table.remove(list, i)
            end
        end
    end
end

local function unescapeField(s)
    s = tostring(s or "")
    local out = {}
    local i = 1
    while i <= #s do
        local c = s:sub(i, i)
        if c == "\\" and i < #s then
            local escaped = s:sub(i + 1, i + 1)
            if escaped == "n" then
                out[#out + 1] = "\n"
            elseif escaped == "r" then
                out[#out + 1] = "\r"
            elseif escaped == "|" or escaped == "\\" then
                out[#out + 1] = escaped
            else
                out[#out + 1] = "\\"
                out[#out + 1] = escaped
            end
            i = i + 2
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

local function splitPipe(message)
    local parts = {}
    local buf = {}
    local i = 1
    local n = #message
    while i <= n do
        local c = message:sub(i, i)
        if c == "\\" and i < n then
            buf[#buf + 1] = message:sub(i, i + 1)
            i = i + 2
        elseif c == "|" then
            parts[#parts + 1] = unescapeField(table.concat(buf))
            buf = {}
            i = i + 1
        else
            buf[#buf + 1] = c
            i = i + 1
        end
    end
    parts[#parts + 1] = unescapeField(table.concat(buf))
    return parts
end

local function toFlag(v)
    v = tostring(v or ""):lower()
    return v == "1" or v == "true" or v == "yes"
end

local function parseObjectFields(parts, startIndex, inGroup, isRoot)
    if inGroup == nil then
        inGroup = toFlag(parts[startIndex + 7])
    end
    if isRoot == nil then
        isRoot = toFlag(parts[startIndex + 8])
    end
    return {
        guid = tonumber(parts[startIndex]) or 0,
        entry = tonumber(parts[startIndex + 1]) or 0,
        map = tonumber(parts[startIndex + 2]) or 0,
        x = tonumber(parts[startIndex + 3]) or 0,
        y = tonumber(parts[startIndex + 4]) or 0,
        z = tonumber(parts[startIndex + 5]) or 0,
        o = tonumber(parts[startIndex + 6]) or 0,
        inGroup = inGroup,
        isRoot = isRoot,
        id = tonumber(parts[startIndex]) or 0,
        name = tostring(parts[startIndex + 1] or ""),
    }
end

local function resetCapsChunks(chunkCount, indexBase)
    capsChunks = {}
    capsChunkCount = chunkCount
    capsChunkBase = indexBase
end

local function mergeCapsChunk(chunkIndex, chunkCount, fields)
    capsChunks[chunkIndex] = fields
    local complete = true
    local merged = {}
    for i = 1, chunkCount do
        local chunk = capsChunks[i]
        if not chunk then
            complete = false
            break
        end
        for j = 1, #chunk do
            merged[#merged + 1] = chunk[j]
        end
    end
    if not complete then
        return
    end

    for k in pairs(capsMap) do
        capsMap[k] = nil
    end
    for i = 1, #merged do
        local token = merged[i]
        local path, allowed = token:match("^(.+):%d+:([01])$")
        if not path then
            path, allowed = token:match("^(.+):([01])$")
        end
        if path then
            local ok = allowed == "1"
            local dottedPath = path:lower()
            local spacedPath = dottedPath:gsub("%.", " ")
            capsMap[dottedPath] = ok
            capsMap[spacedPath] = ok
            capsMap["." .. dottedPath] = ok
        end
    end
    capsChunks = {}
    capsChunkCount = nil
    capsChunkBase = nil
    capsReady = true
    state.capsReady = true
    state.capsMap = capsMap
    notify("caps", capsMap)
end

local function handleCaps(parts)
    local chunkIndex = tonumber(parts[2])
    local chunkCount = tonumber(parts[3]) or 1
    if chunkCount < 1 then
        chunkCount = 1
    end
    if chunkIndex == nil then
        chunkIndex = 1
    end
    local fields = {}
    for i = 4, #parts do
        if parts[i] ~= "" then
            fields[#fields + 1] = parts[i]
        end
    end
    if chunkCount <= 1 then
        resetCapsChunks(1, chunkIndex == 0 and 0 or 1)
        mergeCapsChunk(1, 1, fields)
        return
    end

    if chunkIndex == 0 then
        resetCapsChunks(chunkCount, 0)
    elseif chunkIndex == 1 and capsChunkBase ~= 0 then
        resetCapsChunks(chunkCount, 1)
    elseif capsChunkCount ~= chunkCount then
        return
    end

    if capsChunkBase == nil then
        return
    end

    local normalizedIndex = capsChunkBase == 0 and chunkIndex + 1 or chunkIndex
    if normalizedIndex < 1 or normalizedIndex > chunkCount then
        return
    end
    mergeCapsChunk(normalizedIndex, chunkCount, fields)
end

local function handleInfoBegin(parts)
    infoPending = {
        objectGuid = tonumber(parts[2]) or 0,
        groupRoot = tonumber(parts[3]) or 0,
        name = parts[4] or "",
        memberCount = tonumber(parts[5]) or 0,
        dirty = toFlag(parts[6]),
        busy = toFlag(parts[7]),
        object = nil,
        members = {},
    }
end

local function handleInfoObject(parts)
    if not infoPending then
        return
    end
    infoPending.object = parseObjectFields(parts, 2)
    infoPending.object.serverPhaseId = tonumber(parts[11]) or 0
end

local function handleInfoMember(parts)
    if not infoPending then
        return
    end
    local row = parseObjectFields(parts, 2, true, false)
    row.serverPhaseId = tonumber(parts[9]) or 0
    infoPending.members[#infoPending.members + 1] = row
end

local function handleInfoEnd(parts)
    if not infoPending then
        return
    end
    local endGuid = tonumber(parts[2])
    if endGuid and infoPending.objectGuid ~= 0 and endGuid ~= infoPending.objectGuid then
        if ns.PrintDebug then
            ns.PrintDebug("GobGroup INFO_END guid mismatch")
        end
    end
    state.info = infoPending
    infoPending = nil
    notify("info", state.info)
end

local function handleListBegin(parts)
    listPending = {
        mapFilter = parts[2] or "all",
        count = tonumber(parts[3]) or 0,
        items = {},
    }
end

local function handleListItem(parts)
    if not listPending then
        return
    end
    local root = tonumber(parts[2]) or 0
    listPending.items[#listPending.items + 1] = {
        id = root,
        root = root,
        name = parts[3] or "",
        members = tonumber(parts[4]) or 0,
        map = tonumber(parts[5]) or 0,
        serverPhaseId = tonumber(parts[6]) or 0,
        desc = string.format("map=%s members=%s RP phase=%s",
            tostring(parts[5] or "?"), tostring(parts[4] or "?"), tostring(parts[6] or "0")),
    }
end

local function handleListEnd()
    if not listPending then
        return
    end
    state.list = listPending
    listPending = nil
    notify("list", state.list)
end

local function handleNearBegin(parts)
    nearPending = {
        map = tonumber(parts[2]) or 0,
        radius = tonumber(parts[3]) or 0,
        count = tonumber(parts[4]) or 0,
        items = {},
        itemsByRoot = {},
    }
end

local function handleNearItem(parts)
    if not nearPending then
        return
    end

    local rootText = tostring(parts[2] or "0")
    local item = nearPending.itemsByRoot[rootText]
    if not item then
        local root = tonumber(rootText) or 0
        item = {
            id = root,
            root = root,
            name = "",
            members = tonumber(parts[4]) or 0,
            map = tonumber(parts[5]) or 0,
            distance = tonumber(parts[6]) or 0,
            x = tonumber(parts[7]) or 0,
            y = tonumber(parts[8]) or 0,
            z = tonumber(parts[9]) or 0,
            nameChunks = {},
            nameChunkCount = tonumber(parts[11]) or 1,
            serverPhaseId = tonumber(parts[12]) or 0,
        }
        nearPending.itemsByRoot[rootText] = item
        nearPending.items[#nearPending.items + 1] = item
    end

    local chunkIndex = tonumber(parts[10]) or 1
    local chunkCount = tonumber(parts[11]) or 1
    if chunkIndex >= 1 and chunkIndex <= chunkCount then
        item.nameChunks[chunkIndex] = parts[3] or ""
        item.nameChunkCount = chunkCount
    end
end

local function handleNearEnd()
    if not nearPending then
        return
    end

    for i = 1, #nearPending.items do
        local item = nearPending.items[i]
        local chunks = {}
        for chunkIndex = 1, item.nameChunkCount do
            chunks[#chunks + 1] = item.nameChunks[chunkIndex] or ""
        end
        item.name = table.concat(chunks)
        item.nameChunks = nil
        item.nameChunkCount = nil
        item.desc = string.format("%.1f yd | map=%d | RP phase=%d | members=%d | (%.1f %.1f %.1f)",
            item.distance, item.map, item.serverPhaseId or 0, item.members, item.x, item.y, item.z)
    end

    nearPending.itemsByRoot = nil
    state.near = nearPending
    nearPending = nil
    notify("near", state.near)
end

local function handleStatus(parts)
    local status = {
        groupGuid = tonumber(parts[2]) or 0,
        dirty = toFlag(parts[3]),
        busy = toFlag(parts[4]),
        jobState = parts[5] or "",
    }
    state.status = status
    notify("status", status)
end

local MUTATION_VERBS = {
    create = true, add = true, remove = true, scan = true, addnear = true,
    dissolve = true, delete = true, capture = true, recalc = true, sync = true,
    move = true, turn = true, relocate = true, cleanup = true, reload = true,
    use = true, target = true,
}

local function handleResult(parts)
    local result = {
        verb = (parts[2] or ""):lower(),
        status = (parts[3] or ""):lower(),
        detail = parts[4] or "",
    }
    for i = 5, #parts do
        result.detail = result.detail .. "|" .. parts[i]
    end
    state.lastResult = result
    notify("result", result)
end

local function handleBlueprintListBegin(parts)
    blueprintListPending = {
        filter = parts[2] or "",
        count = tonumber(parts[3]) or 0,
        items = {},
    }
end

local function handleBlueprintListRow(parts)
    if not blueprintListPending then
        return
    end
    -- ROW|key|id|owner|name|members|public|canMutate|description
    blueprintListPending.items[#blueprintListPending.items + 1] = {
        key = parts[2] or "",
        id = tonumber(parts[3]) or 0,
        ownerAccount = tonumber(parts[4]) or 0,
        name = parts[5] or "",
        members = tonumber(parts[6]) or 0,
        isPublic = (parts[7] == "1"),
        canMutate = (parts[8] == "1"),
        description = parts[9] or "",
    }
end

local function handleBlueprintListEnd()
    if not blueprintListPending then
        return
    end
    state.blueprintList = blueprintListPending
    blueprintListPending = nil
    notify("blueprint_list", state.blueprintList)
end

local function handleBlueprintInfo(parts)
    -- INFO|key|id|owner|name|physMembers|public|canMutate|canSetPublic|virtualRoot|description
    state.blueprintInfo = {
        key = parts[2] or "",
        id = tonumber(parts[3]) or 0,
        ownerAccount = tonumber(parts[4]) or 0,
        name = parts[5] or "",
        members = tonumber(parts[6]) or 0,
        isPublic = (parts[7] == "1"),
        canMutate = (parts[8] == "1"),
        canSetPublic = (parts[9] == "1"),
        virtualRoot = (parts[10] == "1"),
        description = parts[11] or "",
        parts = {},
        entries = {},
    }
end

local function handleBlueprintInfoPart(parts)
    if not state.blueprintInfo then
        return
    end
    state.blueprintInfo.parts[#state.blueprintInfo.parts + 1] = {
        id = tonumber(parts[2]) or 0,
        type = parts[3] or "base",
        label = parts[4] or "",
        sourceRoot = tonumber(parts[5]) or 0,
    }
end

local function handleBlueprintInfoMember(parts)
    if not state.blueprintInfo then
        return
    end
    -- MEMBER|id|partId|sort|isRoot|entry
    state.blueprintInfo.entries[#state.blueprintInfo.entries + 1] = {
        id = tonumber(parts[2]) or 0,
        partId = tonumber(parts[3]) or 0,
        sort = tonumber(parts[4]) or 0,
        isRoot = (parts[5] == "1"),
        entry = tonumber(parts[6]) or 0,
        index = tonumber(parts[2]) or 0, -- compat
    }
end

local function handleBlueprintInfoEnd()
    if not state.blueprintInfo then
        return
    end
    notify("blueprint_info", state.blueprintInfo)
end

local function handleBlueprintResult(parts)
    local result = {
        verb = (parts[2] or ""):lower(),
        status = (parts[3] or ""):lower(),
        detail = parts[4] or "",
    }
    for i = 5, #parts do
        result.detail = result.detail .. "|" .. parts[i]
    end
    state.lastBlueprintResult = result
    notify("blueprint_result", result)
end

local function handleBlueprintStatus(parts)
    local status = {
        line = parts[2] or "",
    }
    for i = 3, #parts do
        status.line = status.line .. "|" .. parts[i]
    end
    state.blueprintStatus = status
    notify("blueprint_status", status)
end

function P.HandleMessage(message)
    message = tostring(message or "")
    if message == "" then
        return
    end

    -- Optional short channel prefix before payload (never strip tabs inside fields).
    local tabPos = message:find("\t", 1, true)
    if tabPos and tabPos <= 16 then
        message = message:sub(tabPos + 1)
    end

    local parts = splitPipe(message)
    local kind = (parts[1] or ""):upper()
    if kind == "CAPS" then
        handleCaps(parts)
    elseif kind == "INFO_BEGIN" then
        handleInfoBegin(parts)
    elseif kind == "INFO_OBJECT" then
        handleInfoObject(parts)
    elseif kind == "INFO_MEMBER" then
        handleInfoMember(parts)
    elseif kind == "INFO_END" then
        handleInfoEnd(parts)
    elseif kind == "LIST_BEGIN" then
        handleListBegin(parts)
    elseif kind == "LIST_ITEM" then
        handleListItem(parts)
    elseif kind == "LIST_END" then
        handleListEnd()
    elseif kind == "NEAR_BEGIN" then
        handleNearBegin(parts)
    elseif kind == "NEAR_ITEM" then
        handleNearItem(parts)
    elseif kind == "NEAR_END" then
        handleNearEnd()
    elseif kind == "STATUS" then
        handleStatus(parts)
    elseif kind == "RESULT" then
        handleResult(parts)
    elseif kind == "BLUEPRINT_LIST_BEGIN" then
        handleBlueprintListBegin(parts)
    elseif kind == "BLUEPRINT_LIST_ROW" then
        handleBlueprintListRow(parts)
    elseif kind == "BLUEPRINT_LIST_END" then
        handleBlueprintListEnd()
    elseif kind == "BLUEPRINT_INFO" then
        handleBlueprintInfo(parts)
    elseif kind == "BLUEPRINT_INFO_PART" then
        handleBlueprintInfoPart(parts)
    elseif kind == "BLUEPRINT_INFO_MEMBER" then
        handleBlueprintInfoMember(parts)
    elseif kind == "BLUEPRINT_INFO_END" then
        handleBlueprintInfoEnd()
    elseif kind == "BLUEPRINT_RESULT" then
        handleBlueprintResult(parts)
    elseif kind == "BLUEPRINT_STATUS" then
        handleBlueprintStatus(parts)
    elseif ns.PrintDebug then
        ns.PrintDebug("GobGroup unknown packet: " .. kind)
    end
end

function P.GetCapsMap()
    return capsMap
end

function P.IsCapsReady()
    return capsReady
end

function P.IsMutationVerb(verb)
    return MUTATION_VERBS[(verb or ""):lower()] == true
end

function P.CanVerb(verb)
    if not capsReady then
        return true
    end
    local path = "gobject group " .. tostring(verb or ""):lower()
    if capsMap[path] ~= nil then
        return capsMap[path] and true or false
    end
    if ns.CommandDefinitions and ns.CommandDefinitions.Find and ns.CommandDefinitions.CanRun then
        local def = ns.CommandDefinitions.Find(path)
        if def then
            return ns.CommandDefinitions.CanRun(def, capsMap)
        end
    end
    return false
end

function P.CanBlueprintVerb(verb)
    if not capsReady then
        return true
    end
    local path = "gobject blueprint " .. tostring(verb or ""):lower()
    if capsMap[path] ~= nil then
        return capsMap[path] and true or false
    end
    if ns.CommandDefinitions and ns.CommandDefinitions.Find and ns.CommandDefinitions.CanRun then
        local def = ns.CommandDefinitions.Find(path)
        if def then
            return ns.CommandDefinitions.CanRun(def, capsMap)
        end
    end
    return false
end
