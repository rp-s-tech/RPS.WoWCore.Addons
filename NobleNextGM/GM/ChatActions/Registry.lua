-- Loaded through the NobleNextGM private extension namespace.
-- GM/ChatActions/Registry.lua — реестр kind-обработчиков system-chat action links

local _, ns = ...

ns.ChatActions = ns.ChatActions or {}
local R = ns.ChatActions

R.ADDON = "NobleNext"
R.kinds = R.kinds or {}
R._order = R._order or {}
R._rewriteCache = R._rewriteCache or {}

function R.IsAllowed()
    return ns.Access and ns.Access.Allows and ns.Access.Allows(2) == true
end

local function readableString(value)
    return type(value) == "string" and not (issecretvalue and issecretvalue(value))
end

if ns.Subscribe then
    ns.Subscribe("ACCESS_CHANGED", "chat-actions", function()
        R._rewriteCache = {}
        R._lastActionKey, R._lastActionAt = nil, nil
        for _, def in pairs(R.kinds) do if def.reset then def.reset() end end
    end)
end

function R.RegisterKind(kind, def)
    if type(kind) ~= "string" or kind == "" or type(def) ~= "table" then
        return false
    end
    if type(def.match) ~= "function" or type(def.rewrite) ~= "function" or type(def.handle) ~= "function" then
        return false
    end
    local isNew = R.kinds[kind] == nil
    R.kinds[kind] = def
    if isNew then
        R._order[#R._order + 1] = kind
    end
    return true
end

function R.HasOurButtons(msg)
    if not readableString(msg) then
        return false
    end
    return msg:find("addon:" .. R.ADDON .. ":", 1, true) ~= nil
end

function R.MakeLink(kind, action, id, entry, label, color)
    local payload = string.format("addon:%s:%s:%s:%s", R.ADDON, kind, action, tostring(id))
    if entry then
        payload = payload .. ":" .. tostring(entry)
    end
    return string.format("|H%s|h|c%s[%s]|r|h", payload, color, label)
end

--- addon:NobleNext:<kind>:<action>:<id>[:<entry>]
function R.Parse(link)
    if not readableString(link) then
        return nil
    end
    local payload = link:match("|H([^|]+)|h") or link
    local addon, kind, action, id, entry =
        payload:match("^addon:([^:]+):([^:]+):([^:]+):(%d+):(%d+)$")
    if not addon then
        addon, kind, action, id =
            payload:match("^addon:([^:]+):([^:]+):([^:]+):(%d+)$")
    end
    if addon ~= R.ADDON or not kind or not action or not id then
        return nil
    end
    if entry == "" then
        entry = nil
    end
    return kind, action, id, entry
end

function R.Rewrite(msg, lineID)
    if not R.IsAllowed() or not readableString(msg) or msg == "" or R.HasOurButtons(msg) then
        return msg
    end
    -- Blizzard invokes message filters once for each chat frame. One event may
    -- update SelectionContext only once; separate identical commands still work.
    local now = GetTime and GetTime() or 0
    local eventID = type(lineID) == "number" and not (issecretvalue and issecretvalue(lineID))
        and lineID > 0 and lineID or nil
    for _, cached in ipairs(R._rewriteCache) do
        if cached.message == msg and ((eventID and cached.id == eventID)
            or (not eventID and not cached.id and now - cached.at < 0.05)) then return cached.result end
    end
    local result = msg
    for i = 1, #R._order do
        local kind = R._order[i]
        local def = R.kinds[kind]
        if def and def.match(msg) then
            result = def.rewrite(msg) or msg
            break
        end
    end
    R._rewriteCache[#R._rewriteCache + 1] = { id=eventID, at=now, message=msg, result=result }
    if #R._rewriteCache > 64 then table.remove(R._rewriteCache, 1) end
    return result
end

function R.OnSetItemRef(link, text, button, frame)
    if not R.IsAllowed() then return end
    local kind, action, id, entry = R.Parse(link)
    if not kind then
        return
    end
    -- Debounce same payload within one frame / short window (belt-and-suspenders vs double hooks).
    local key = table.concat({ kind, action, tostring(id), tostring(entry or "") }, ":")
    local now = (GetTime and GetTime()) or 0
    if R._lastActionKey == key and R._lastActionAt and (now - R._lastActionAt) < 0.05 then
        return
    end
    R._lastActionKey = key
    R._lastActionAt = now

    local def = R.kinds[kind]
    if def and def.handle then
        def.handle(action, id, entry, { text = text, button = button, frame = frame })
    end
end

-- Back-compat aliases used by Docs / older callers
ns.GobChat = ns.GobChat or {}
ns.GobChat.ADDON = R.ADDON
ns.GobChat.ParseAddonLink = function(link)
    return R.Parse(link)
end
ns.GobChat.OnSetItemRef = function(link, text, button, frame)
    R.OnSetItemRef(link, text, button, frame)
end
