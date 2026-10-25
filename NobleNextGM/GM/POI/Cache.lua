-- Loaded through the NobleNextGM private extension namespace.
-- GM/POI/Cache.lua — локальный кэш POI (delta от RPC_POI_INFO)
local _, ns = ...

POI_Cache = POI_Cache or {}

ns.PoiCache = {
    revision = 0,
}

function ns.PoiCache.Upsert(data)
    if not data or not data.id then return end
    local key = tostring(data.id)
    if data.deleted then
        POI_Cache[key] = nil
    else
        POI_Cache[key] = data
    end
    ns.PoiCache.revision = (ns.PoiCache.revision or 0) + 1
end

function ns.PoiCache.HasEntries()
    return next(POI_Cache) ~= nil
end

function ns.PoiCache.Count()
    local n = 0
    for _ in pairs(POI_Cache) do
        n = n + 1
    end
    return n
end

function ns.PoiCache.AllEntries()
    local out = {}
    for _, data in pairs(POI_Cache) do
        table.insert(out, data)
    end
    table.sort(out, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return out
end
