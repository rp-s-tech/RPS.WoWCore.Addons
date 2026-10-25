-- Loaded through the NobleNextDM private extension namespace.
-- GM/Phase/Init.lua — bootstrap Codex RP World Maps и обязательный resync.

local _, ns = ...

local MODULE_NAME = "RP Фазы"

ns.RegisterModule(MODULE_NAME, function(parent)
    return ns.PhasePanel.Init(parent)
end, "Поиск RP-фаз, вход и управление участниками")

local function showCodex()
    ns.ShowModule(MODULE_NAME)
end

C_Timer.After(0, function()
    ns.RegisterSlashCommand("NNPHASES", showCodex, { "nnphases", "nnphasecodex" })
end)

-- ReloadUI может восстановить SavedVariables, но не server-authoritative context.
-- Поэтому всегда повторно читаем CONTEXT после входа/перезагрузки интерфейса.
local function requestInitialState()
    C_Timer.After(0.5, function()
        if ns.Phases then
            ns.Phases.GetCurrent(function() end)
        end
    end)
end
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", requestInitialState)
if IsLoggedIn and IsLoggedIn() then requestInitialState() end
