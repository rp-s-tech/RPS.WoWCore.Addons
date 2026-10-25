-- Loaded through the NobleNextGM private extension namespace.
-- GM/POI/Sync.lua — применение delta от C++ (RPC_POI_INFO) с батчингом пачки .poi sync
local _, ns = ...

ns.PoiSync = ns.PoiSync or {}

local flushGeneration = 0
local burstCount = 0
local lastDelta = nil

local function flushPending()
    local count = burstCount
    local data = lastDelta
    burstCount = 0
    lastDelta = nil

    if ns.PoiMapPins and ns.PoiMapPins.RedrawAll then
        ns.PoiMapPins.RedrawAll()
    end
    if ns.PoiEditor and ns.PoiEditor.UpdateListFromCache then
        ns.PoiEditor.UpdateListFromCache()
    end
    if not data or not ns.PoiEditor or not ns.PoiEditor.SetStatus then
        return
    end
    if count > 1 then
        local total = (ns.PoiCache and ns.PoiCache.Count and ns.PoiCache.Count()) or count
        if ns.PoiMapPins and not ns.PoiMapPins.HasLibrary() then
            ns.PoiEditor.SetStatus(string.format("Список POI синхронизирован (%d), но HereBeDragons не найден.", total), "warning")
        else
            ns.PoiEditor.SetStatus(string.format("Список POI синхронизирован: %d точек.", total), "success")
        end
    elseif data.deleted then
        ns.PoiEditor.SetStatus(string.format("POI #%d удалён.", data.id or 0), "warning")
    elseif ns.PoiMapPins and not ns.PoiMapPins.HasLibrary() then
        ns.PoiEditor.SetStatus(string.format("POI #%d обновлён, но HereBeDragons не найден: метка скрыта.", data.id or 0), "warning")
    else
        ns.PoiEditor.SetStatus(string.format("POI #%d обновлён.", data.id or 0), "success")
    end
end

ns.PoiSync.Flush = flushPending

function ns.PoiSync.ApplyDelta(data)
    if not data then return end
    ns.PoiCache.Upsert(data)
    lastDelta = data
    burstCount = burstCount + 1
    flushGeneration = flushGeneration + 1
    local gen = flushGeneration

    -- C++ SendFullList streams 1 packet per 10ms. Coalesce the burst so we
    -- do not rebuild all map pins and sort the editor list on every packet.
    if C_Timer and C_Timer.After then
        C_Timer.After(0.15, function()
            if gen ~= flushGeneration then return end
            flushPending()
        end)
    else
        flushPending()
    end
end
