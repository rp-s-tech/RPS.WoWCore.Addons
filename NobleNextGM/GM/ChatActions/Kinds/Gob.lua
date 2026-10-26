-- Loaded through the NobleNextGM private extension namespace.
-- GM/ChatActions/Kinds/Gob.lua — GO chat buttons (payload совместим с прежним GobChat)

local _, ns = ...

local R = ns.ChatActions
if not R or not R.RegisterKind then
    return
end

local BTN = {
    sel      = { action = "sel",      label = "Sel",  color = "ff00ccff", tip = "Выбрать GO (GobMover)" },
    add      = { action = "add",      label = "Add",  color = "ff629404", tip = "Добавить такой же GO" },
    del      = { action = "del",      label = "Del",  color = "ffff4444", tip = "Удалить GO" },
    move     = { action = "move",     label = "Move", color = "ffff9900", tip = "Открыть GobMover" },
    go       = { action = "go",       label = "Go",   color = "ff629404", tip = "Телепорт к GO" },
    activate = { action = "activate", label = "Act",  color = "ffffd100", tip = "Активировать GO" },
    info     = { action = "info",     label = "Info", color = "ff66ccff", tip = "Проверить GO (.gobject check)" },
}

local ACTION_TIP = {}
for _, def in pairs(BTN) do
    ACTION_TIP[def.action] = def.tip
end

local function SendCmd(cmd)
    if not R.IsAllowed or not R.IsAllowed() then return end
    if ns.EnqueueCommand then
        ns.EnqueueCommand(cmd, { tag = "gobchat" })
    elseif ns.RunGmCommand then
        ns.RunGmCommand(cmd)
    else
        ns.PrintError("RunGmCommand недоступен.")
    end
end

local function SetGobMoverTarget(guid, name, entry)
    if not R.IsAllowed or not R.IsAllowed() then return end
    guid = tonumber(guid) or 0
    if guid == 0 then
        return
    end
    name = name or ("GO " .. tostring(guid))
    if ns.SelectionContext and ns.SelectionContext.SetGo then
        ns.SelectionContext.SetGo(guid, entry, name)
    end
    local mover = _G.NobleNextGobMover or _G.NobleNextGoMover
    if mover and mover.SetTarget then
        mover.SetTarget(guid, name, nil, entry)
    end
    -- GobGroup consumes the SelectionContext event above; do not notify it twice.
end

local function OpenGobMover()
    if ns.ShowModule then
        ns.ShowModule("Gob Mover")
        return
    end
    if SlashCmdList and SlashCmdList["NNGOBMOVER"] then
        SlashCmdList["NNGOBMOVER"]()
    end
end

local function MakeGobLink(action, guid, entry, label, color)
    return R.MakeLink("gob", action, guid, entry, label, color)
end

local function BuildGobButtons(guid, entry)
    guid = tostring(guid or "")
    if not guid:match("^%d+$") or guid == "0" then
        return ""
    end
    entry = tostring(entry or "")
    if not entry:match("^%d+$") then
        entry = nil
    end

    local parts = {}
    for _, key in ipairs({ "sel", "add", "move", "go", "del", "activate", "info" }) do
        if key ~= "add" or entry then
            local def = BTN[key]
            parts[#parts + 1] = MakeGobLink(def.action, guid, entry, def.label, def.color)
        end
    end
    return " " .. table.concat(parts, " ")
end

local function BuildEntrySpawnButtons(entry)
    entry = tostring(entry or "")
    if not entry:match("^%d+$") or entry == "0" then
        return ""
    end
    local def = BTN.add
    return " " .. MakeGobLink(def.action, "0", entry, def.label, def.color)
end

local function ConfirmGobDelete(guid)
    StaticPopupDialogs["NOBLENEXT_GOBCHAT_DELETE"] = {
        text = string.format("Удалить GameObject с GUID %s?", guid),
        button1 = DELETE or YES,
        button2 = CANCEL or NO,
        OnAccept = function()
            SendCmd("gobject delete " .. guid)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("NOBLENEXT_GOBCHAT_DELETE")
end

local function ExtractStandaloneTemplateId(msg)
    -- Strip GUID tokens first: bare "ID:" otherwise matches the suffix of "GUID:".
    local cleaned = tostring(msg or ""):gsub("GUID:%s*%d+", "")
    return cleaned:match("ID:%s*(%d+)")
end

local function ExtractGoIdentity(msg)
    -- Prefer the GUID/ID pair so template entry stays separate from spawn GUID.
    local guid, entry = msg:match("GUID:%s*(%d+).-ID:%s*(%d+)")
    if guid then
        return guid, entry
    end

    entry = msg:match("Add%s+Game%s+Object%s+'?(%d+)'?")
        or msg:match("%(Entry:%s*(%d+)%)")
        or msg:match("|Hgameobject_entry:(%d+)|h")
        or ExtractStandaloneTemplateId(msg)

    guid = msg:match("|Hgameobject:(%d+)|h")
    if guid then
        return guid, entry
    end

    guid = msg:match("GUID:%s*(%d+)")
    if guid then
        return guid, entry
    end
    guid = msg:match("^%s*(%d+)%s*%(Entry:")
    if guid then
        return guid, entry
    end
    guid = msg:match("(%d+)%s*%(Entry:")
    return guid, entry
end

local function ExtractGoTemplateEntry(msg)
    local entry = msg:match("|Hgameobject_entry:(%d+)|h")
    if entry then
        return entry
    end
    if not msg:find("|Hgameobject:", 1, true) and not msg:find("(Entry:", 1, true) then
        entry = msg:match("^%s*(%d+)%s*%-%s*%[")
    end
    return entry
end

local function IsGoEntryLookupMessage(msg)
    if msg:find("|Hgameobject_entry:", 1, true) then
        return true
    end
    if msg:match("^%s*%d+%s*%-%s*%[")
        and not msg:find("|Hgameobject:", 1, true)
        and not msg:find("(Entry:", 1, true)
    then
        return true
    end
    return false
end

local function IsActionableGoMessage(msg)
    if msg:match("^%s*Selected object%s*:") then
        return true
    end
    -- .gobject check / target detail lines also carry GUID:/ID:
    if msg:find("|Hgameobject:", 1, true)
        and msg:match("GUID:%s*%d+")
        and (msg:match("GUID:%s*%d+.-ID:%s*%d+") or ExtractStandaloneTemplateId(msg))
    then
        return true
    end
    if msg:find("Add Game Object", 1, true) then
        return true
    end
    -- near / list rows: "guid (Entry: entry) - |Hgameobject:..."
    if msg:match("%d+%s*%(Entry:%s*%d+%)") then
        return true
    end
    if msg:find("|Hgameobject:", 1, true) and msg:match("^%s*%d+%s*%-") then
        return true
    end
    return false
end

local function HandleGobAction(action, guid, entry)
    if not R.IsAllowed or not R.IsAllowed() then return end
    guid = tostring(guid or "")
    if not guid:match("^%d+$") then
        return
    end
    entry = tostring(entry or "")
    if not entry:match("^%d+$") then
        entry = nil
    end

    if action == "add" then
        if entry then
            SendCmd("gobject add " .. entry)
        end
        return
    end

    if guid == "0" then
        return
    end

    if action == "sel" then
        SetGobMoverTarget(guid, nil, entry)
        if ns.Print then
            ns.Print("Цель GO GUID " .. tostring(guid))
        end
        return
    end

    if action == "del" then
        ConfirmGobDelete(guid)
        return
    end

    if action == "move" then
        SetGobMoverTarget(guid, nil, entry)
        OpenGobMover()
        return
    end

    if action == "go" then
        SendCmd("go gameobject " .. guid)
        return
    end

    if action == "activate" then
        SendCmd("gobject activate " .. guid)
        return
    end

    if action == "info" then
        SendCmd("gobject check " .. guid)
        return
    end
end

local function ExtractGoName(msg)
    return msg:match("|Hgameobject:%d+|h%[(.-)%]|h")
        or msg:match("%[([^%]]+)%]%s*GUID:")
end

-- LANG_GAMEOBJECT_DETAIL wraps the hyperlink in |cffffffff...|r. Parse the
-- visible record without color escapes, but keep the original chat text intact.
local function parseText(msg)
    return (msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- .gobject target часто шлёт заголовок "Selected object:" и GUID-строку
-- отдельными CHAT_MSG_SYSTEM; связываем их для авто-SetTarget.
local pendingTargetSelect
local function isSelectedHeader(msg) return msg:match("^%s*Selected object%s*:") ~= nil end
local function isPlainSelectedRecord(msg)
    return msg:match("^%s*%[[^%]\r\n]+%]%s*GUID:%s*%d+%s+ID:%s*%d+") ~= nil
        or msg:match("^%s*GUID:%s*%d+%s+ID:%s*%d+") ~= nil
end
local function isSelectedRecord(msg)
    return isPlainSelectedRecord(msg)
        or msg:match("^%s*|Hgameobject:%d+|h%[[^%]\r\n]+%]|h%s*GUID:%s*%d+%s+ID:%s*%d+") ~= nil
end
local function isOtherEntity(msg)
    return msg:find("|Hcreature:", 1, true) or msg:find("|Hcreature_entry:", 1, true)
        or msg:find("|Hunit:", 1, true) or msg:match("^%s*Selected creature")
        or msg:match("^%s*Selected unit")
end
local function Match(msg)
    msg = parseText(msg)
    local now = GetTime and GetTime() or 0
    if pendingTargetSelect and now >= pendingTargetSelect.expires then pendingTargetSelect = nil end
    if isOtherEntity(msg) then pendingTargetSelect = nil; return false end
    if isSelectedHeader(msg) then return true end
    if pendingTargetSelect then
        if isSelectedRecord(msg) then return true end
        -- Some LANG_GAMEOBJECT_DETAIL layouts put [name] on its own line.
        -- Permit that one optional line, never an arbitrary unbounded context.
        local name = msg:match("^%s*%[([^%]\r\n]+)%]%s*$")
        if name and not pendingTargetSelect.name then pendingTargetSelect.name = name; return false end
        pendingTargetSelect = nil
    end
    -- Near/list/add output still gets its own buttons, but cannot consume a
    -- preceding target header as permission to select a different object.
    return IsGoEntryLookupMessage(msg) or IsActionableGoMessage(msg)
end

local function NotifyChatRecord(record)
    local mover = _G.NobleNextGobMover or _G.NobleNextGoMover
    if mover and type(mover.OnChatRecord) == "function" then
        pcall(mover.OnChatRecord, record)
    end
end

local function Rewrite(msg)
    local original = msg
    msg = parseText(msg)
    local selectedBody = msg:match("^%s*Selected object%s*:%s*(.-)%s*$")
    if selectedBody then
        pendingTargetSelect = { expires=(GetTime and GetTime() or 0) + 1 }
        if selectedBody ~= "" and not isSelectedRecord(selectedBody) then
            pendingTargetSelect.name = selectedBody:match("^%[([^%]\r\n]+)%]$")
            if not pendingTargetSelect.name then pendingTargetSelect = nil end
        end
    end

    if IsGoEntryLookupMessage(msg) then
        pendingTargetSelect = nil
        local entry = ExtractGoTemplateEntry(msg)
        if entry then
            local name = msg:match("|Hgameobject_entry:%d+|h%[(.-)%]|h") or msg:match("%[([^%]]+)%]")
            NotifyChatRecord({ entry = tonumber(entry), name = name, kind = "lookup" })
            return original .. BuildEntrySpawnButtons(entry)
        end
        return original
    end
    if IsActionableGoMessage(msg) or (pendingTargetSelect and isPlainSelectedRecord(msg)) then
        local guid, entry = ExtractGoIdentity(msg)
        if not guid and ns.GO_ADD_PATTERN then
            local _, addGuid = msg:match(ns.GO_ADD_PATTERN)
            guid = addGuid
        end
        if guid then
            local goName = ExtractGoName(msg) or (pendingTargetSelect and pendingTargetSelect.name)
            NotifyChatRecord({ guid = tonumber(guid), entry = tonumber(entry), name = goName, kind = "world" })
            -- .gobject target -> сразу цель GobMover / SelectionContext
            -- (кнопка «Выбрать ближайший GO» = тот же путь).
            if pendingTargetSelect and (isSelectedRecord(msg) or (selectedBody and isSelectedRecord(selectedBody))) then
                SetGobMoverTarget(guid, goName, entry)
                pendingTargetSelect = nil
            end
            return original .. BuildGobButtons(guid, entry)
        end
    end
    return original
end

R.RegisterKind("gob", {
    match = Match,
    rewrite = Rewrite,
    handle = HandleGobAction,
    reset = function() pendingTargetSelect = nil end,
})

-- Tooltips for short Sel/Add/Move/Go/Del/Act/Info labels in chat.
if not R._gobTooltipHooked and type(hooksecurefunc) == "function" then
    R._gobTooltipHooked = true
    local function showTip(link)
        if not R.IsAllowed or not R.IsAllowed() then return end
        if type(link) ~= "string" or not link:find("addon:NobleNext:gob:", 1, true) then
            return
        end
        local action = link:match("addon:NobleNext:gob:([^:]+):")
        local tip = action and ACTION_TIP[action]
        if not tip or not GameTooltip then
            return
        end
        GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(tip, 1, 0.82, 0)
        R._gobTooltipShown = true
        GameTooltip:Show()
    end
    local function hideTip()
        if R._gobTooltipShown and GameTooltip then
            GameTooltip:Hide()
        end
        R._gobTooltipShown = nil
    end
    if ChatFrame_OnHyperlinkEnter then
        hooksecurefunc("ChatFrame_OnHyperlinkEnter", function(_, link)
            showTip(link)
        end)
    end
    if ChatFrame_OnHyperlinkLeave then
        hooksecurefunc("ChatFrame_OnHyperlinkLeave", function()
            hideTip()
        end)
    end
    if ns.Subscribe then ns.Subscribe("ACCESS_CHANGED", "gob-chat-tooltip", hideTip) end
end

-- Back-compat surface for GobChat callers / Docs
ns.GobChat = ns.GobChat or {}
ns.GobChat.MakeGobLink = function(action, guid, entry, label, color)
    return MakeGobLink(action, guid, entry, label, color)
end
ns.GobChat.BuildGobButtons = BuildGobButtons
ns.GobChat.BuildEntrySpawnButtons = BuildEntrySpawnButtons
ns.GobChat.HandleGobAction = HandleGobAction
