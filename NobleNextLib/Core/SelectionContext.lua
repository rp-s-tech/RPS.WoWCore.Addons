-- Core/SelectionContext.lua — текущий GO/NPC + кольцевая история для chat/UI

local ns = LibStub("NobleNextLib-1.0").Runtime

ns.SelectionContext = ns.SelectionContext or {}
local Ctx = ns.SelectionContext

local HISTORY_MAX = 10
local transientStorage = {}

local state = {
    go = nil,   -- { guid, entry, name }
    npc = nil,  -- { guid, entry, name }
    history = {}, -- { kind, guid, entry, name, t }
}

local function PositiveId(v)
    local n = tonumber(v)
    return n and n > 0 and n or nil
end

local function EnsureCharDB()
    -- The shell owns legacy SavedVariables. Lib-only clients keep an in-memory
    -- context and never manufacture the shell's settings globals.
    return type(NobleNextCharDB) == "table" and NobleNextCharDB or transientStorage
end

local function Persist()
    local db = EnsureCharDB()
    db.SelectionGo = state.go and {
        guid = state.go.guid,
        entry = state.go.entry,
        name = state.go.name,
    } or nil
    db.SelectionNpc = state.npc and {
        guid = state.npc.guid,
        entry = state.npc.entry,
        name = state.npc.name,
    } or nil
end

local function Restore()
    local db = EnsureCharDB()
    if type(db.SelectionGo) == "table" and PositiveId(db.SelectionGo.guid) then
        state.go = {
            guid = PositiveId(db.SelectionGo.guid),
            entry = PositiveId(db.SelectionGo.entry),
            name = db.SelectionGo.name,
        }
    end
    if type(db.SelectionNpc) == "table" and PositiveId(db.SelectionNpc.guid) then
        state.npc = {
            guid = PositiveId(db.SelectionNpc.guid),
            entry = PositiveId(db.SelectionNpc.entry),
            name = db.SelectionNpc.name,
        }
    end
end

function Ctx.PushHistory(kind, record)
    if not kind or type(record) ~= "table" then
        return
    end
    local guid = PositiveId(record.guid)
    if not guid then
        return
    end
    local entry = {
        kind = kind,
        guid = guid,
        entry = PositiveId(record.entry),
        name = record.name,
        t = GetTime and GetTime() or 0,
    }
    -- dedupe head
    if state.history[1]
        and state.history[1].kind == kind
        and state.history[1].guid == guid
    then
        state.history[1] = entry
        return
    end
    table.insert(state.history, 1, entry)
    while #state.history > HISTORY_MAX do
        table.remove(state.history)
    end
end

function Ctx.GetHistory(kind)
    if not kind then
        return state.history
    end
    local out = {}
    for i = 1, #state.history do
        if state.history[i].kind == kind then
            out[#out + 1] = state.history[i]
        end
    end
    return out
end

function Ctx.SetGo(guid, entry, name)
    guid = PositiveId(guid)
    if not guid then
        state.go = nil
        Persist()
        return false
    end
    state.go = {
        guid = guid,
        entry = PositiveId(entry),
        name = name or ("GO " .. tostring(guid)),
    }
    Ctx.PushHistory("go", state.go)
    Persist()

    ns.LastSpawnedGoGuid = ns.LastSpawnedGoGuid or guid
    ns.Emit("SELECTION_GO_CHANGED", state.go)
    return true
end

function Ctx.GetGo()
    return state.go
end

function Ctx.ClearGo()
    state.go = nil
    Persist()
    ns.Emit("SELECTION_GO_CHANGED", nil)
end

function Ctx.SetNpc(guid, entry, name)
    guid = PositiveId(guid)
    if not guid then
        -- entry-only select (lookup) — keep soft entry context without guid
        entry = PositiveId(entry)
        if not entry then
            state.npc = nil
            Persist()
            return false
        end
        state.npc = {
            guid = nil,
            entry = entry,
            name = name or ("NPC entry " .. tostring(entry)),
        }
        Persist()
        return true
    end
    state.npc = {
        guid = guid,
        entry = PositiveId(entry),
        name = name or ("NPC " .. tostring(guid)),
    }
    Ctx.PushHistory("npc", state.npc)
    Persist()
    return true
end

function Ctx.GetNpc()
    return state.npc
end

function Ctx.ClearNpc()
    state.npc = nil
    Persist()
end

function Ctx.RememberNearNpc(row)
    if type(row) ~= "table" then
        return
    end
    local db = EnsureCharDB()
    db.NpcNearCache = db.NpcNearCache or {}
    local cache = db.NpcNearCache
    local guid = PositiveId(row.guid)
    if not guid then
        return
    end
    for i = #cache, 1, -1 do
        if cache[i].guid == guid then
            table.remove(cache, i)
        end
    end
    table.insert(cache, 1, {
        guid = guid,
        entry = PositiveId(row.entry),
        name = row.name,
    })
    while #cache > 30 do
        table.remove(cache)
    end
end

function Ctx.GetNearNpcs()
    return EnsureCharDB().NpcNearCache or {}
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    Restore()
end)
