-- Loaded through the NobleNextGM private extension namespace.
-- GM/GobGroup/Init.lua — bootstrap панели soft spatial GO groups

local _, ns = ...

local PREFIX = (ns.GobGroupPackets and ns.GobGroupPackets.PREFIX) or "NN_GOBGROUP"

local function handleAddonMessage(prefix, message, _, sender)
    if prefix ~= PREFIX then
        return
    end
    if not ns.Util.IsSelfSender(sender) then
        return
    end
    if ns.GobGroupPackets and ns.GobGroupPackets.HandleMessage then
        ns.GobGroupPackets.HandleMessage(message)
    end
end

ns.RegisterAddonPrefix(PREFIX, handleAddonMessage, { key = "gobgroup" })
ns.Subscribe("SELECTION_GO_CHANGED", "gm.gobgroup-selection", function(record)
    if not ns.Access or not ns.Access.Allows(2) then return end
    if ns.GobGroupPanel and ns.GobGroupPanel.SetObjectGuid then
        ns.GobGroupPanel.SetObjectGuid(record and record.guid or nil)
    end
end)

local function ShowGobGroup()
    ns.ShowModule("GobGroup")
end

C_Timer.After(0, function()
    ns.RegisterSlashCommand("NNGOBGROUP", ShowGobGroup, "nngobgroup")
end)

ns.RegisterModule("GobGroup", function(parent)
    return ns.GobGroupPanel.Init(parent)
end, "Soft spatial-группы GameObject (.gobject group)")

-- Обновляем доступность действий после входа; OnShow повторит запрос при открытии.
local function requestInitialState()
    if ns.GobGroupPanel and ns.GobGroupPanel.RequestAvailability then
        C_Timer.After(1.0, function()
            ns.GobGroupPanel.RequestAvailability()
        end)
    end
end
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", requestInitialState)
if IsLoggedIn and IsLoggedIn() then requestInitialState() end
