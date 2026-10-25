-- Loaded through the NobleNextGM private extension namespace.
-- GM/POI/Init.lua — bootstrap POI (C++ sync через RPC_POI_INFO)

local _, ns = ...

ns.PoiEditor = ns.PoiEditor or {}
_G.NobleNextPoi = _G.NobleNextPoi or {}

local ADDON_PREFIX = "RPC_POI_INFO"
local syncRequested = false
local function allowed() return ns.Access and ns.Access.Allows(2) == true end

_G.NobleNextPoi.OnSetList = function(rows)
    if not allowed() then return end
    ns.PoiEditor.OnSetList(rows)
end

_G.NobleNextPoi.OnNotice = function(level, message)
    if not allowed() then return end
    if ns.PoiEditor and ns.PoiEditor.SetStatus then
        ns.PoiEditor.SetStatus(message or "", level or "info")
    end
end

local function handleAddonPoiPacket(message)
    if not allowed() then return end
    local data = ns.PoiParsePacket(message)
    if not data then
        return
    end

    if not ns.PoiSync or not ns.PoiSync.ApplyDelta then
        local err = "POI sync: ns.PoiSync.ApplyDelta недоступен (Sync.lua не загружен?)"
        if ns.PrintError then
            ns.PrintError(err)
        end
        if ns.PrintDebug then
            ns.PrintDebug(err)
        end
        if ns.PoiEditor and ns.PoiEditor.SetStatus then
            ns.PoiEditor.SetStatus(err, "error")
        end
        return
    end

    ns.PoiSync.ApplyDelta(data)
end

local function isPlayerInWorld()
    return UnitGUID("player") ~= nil
end

function ns.PoiRequestSyncFromAddon()
    if not allowed() then return false end
    if syncRequested then
        return false
    end
    if not ns.PoiSync or not ns.PoiSync.ApplyDelta then
        return false
    end
    if not ns.RunGmCommand then
        return false
    end
    if not isPlayerInWorld() then
        return false
    end

    if ns.RunGmCommand("poi sync") ~= true then return false end
    syncRequested = true
    if ns.PrintDebug then
        ns.PrintDebug("POI: sync запрошен аддоном при загрузке")
    end
    return true
end

local function onPoiModuleReady()
    -- Init.lua — последний файл POI в .toc; откладываем фоновый .poi sync,
    -- чтобы не забивать канал и UI-поток в момент открытия меню и загрузки вкладок.
    if isPlayerInWorld() then
        C_Timer.After(1.5, function()
            ns.PoiRequestSyncFromAddon()
        end)
    end
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
end

ns.RegisterAddonPrefix(ADDON_PREFIX, function(_, message)
    handleAddonPoiPacket(message)
end, { key = "poi" })

local poiFrame = CreateFrame("Frame")
poiFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
poiFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" and not syncRequested then
        onPoiModuleReady()
    end
end)

C_Timer.After(0, function()
    ns.RegisterSlashCommand("NNPOI", function() ns.ShowModule("POI") end, "nnpoi")
end)

ns.RegisterModule("POI", function(parent)
    return ns.PoiEditor.Init(parent)
end, "Точки интереса на карте")

onPoiModuleReady()
ns.Subscribe("ACCESS_CHANGED", "gm.poi-sync", function()
    if not allowed() then
        syncRequested = false
        return
    end
    if not syncRequested then
        onPoiModuleReady()
    end
end)
