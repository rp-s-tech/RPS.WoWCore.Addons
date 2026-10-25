-- Loaded through the NobleNextGM private extension namespace.
-- GM/ChatActions/Kinds/Npc.lua — кнопки для .npc near / .lookup creature / spawn GUID

local _, ns = ...

local R = ns.ChatActions
if not R or not R.RegisterKind then
    return
end

local BTN = {
    sel  = { action = "sel",  label = "Sel",  color = "ff00ccff" },
    add  = { action = "add",  label = "Add",  color = "ff629404" },
    move = { action = "move", label = "Move", color = "ffff9900" },
    go   = { action = "go",   label = "Go",   color = "ff629404" },
    del  = { action = "del",  label = "Del",  color = "ffff4444" },
    info = { action = "info", label = "Info", color = "ffffd100" },
}

local function SendCmd(cmd, tag)
    cmd = tostring(cmd or ""):gsub("^%.", "")
    if ns.EnqueueCommand then
        ns.EnqueueCommand(cmd, { tag = tag or "npcchat" })
    elseif ns.RunGmCommand then
        ns.RunGmCommand(cmd)
    else
        ns.PrintError("RunGmCommand недоступен.")
    end
end

local function FormatCmd(path, argValues, fallback)
    local CD = ns.CommandDefinitions
    if CD and CD.Find and CD.Format then
        local def = CD.Find(path)
        if def then
            local cmd = CD.Format(def, argValues)
            if cmd and cmd ~= "" then
                return cmd
            end
        end
    end
    return fallback
end

local function ExtractNpcName(msg)
    local name = msg:match("|Hcreature:%d+|h%[(.-)%s+X:")
    if name and name ~= "" then
        return name
    end
    name = msg:match("|Hcreature:%d+|h%[(.-)%]|h")
    if name and name ~= "" then
        return name
    end
    name = msg:match("|Hcreature_entry:%d+|h%[(.-)%]|h")
    if name and name ~= "" then
        return name
    end
    return nil
end

local function ExtractCreatureGuid(msg)
    local guid = msg:match("|Hcreature:(%d+)|h")
    if guid then
        return guid
    end
    -- raw add success: Creature … [GUID: N] / GUID: N
    if msg:lower():find("creature", 1, true) or msg:find("NPC", 1, true) then
        guid = msg:match("[Gg]UID:%s*(%d+)")
    end
    return guid
end

local function ExtractCreatureEntry(msg)
    local entry = msg:match("|Hcreature_entry:(%d+)|h")
    if entry then
        return entry
    end
    entry = msg:match("%(Entry:%s*(%d+)%)")
        or msg:match("entry%s*[:=]%s*(%d+)")
    return entry
end

local function IsCreatureEntryLookup(msg)
    return msg:find("|Hcreature_entry:", 1, true) ~= nil
end

local function IsCreatureInstanceMessage(msg)
    if msg:find("|Hcreature:", 1, true) then
        return true
    end
    if msg:match("[Gg]UID:%s*%d+") and (
        msg:lower():find("creature", 1, true)
        or msg:find("NPC", 1, true)
        or msg:find("Spawned", 1, true)
    ) then
        return true
    end
    return false
end

local function BuildInstanceButtons(guid, entry)
    guid = tostring(guid or "")
    if not guid:match("^%d+$") or guid == "0" then
        return ""
    end
    entry = tostring(entry or "")
    if not entry:match("^%d+$") then
        entry = nil
    end
    local parts = {}
    for _, key in ipairs({ "sel", "move", "go", "del", "info" }) do
        local def = BTN[key]
        parts[#parts + 1] = R.MakeLink("npc", def.action, guid, entry, def.label, def.color)
    end
    return " " .. table.concat(parts, " ")
end

local function BuildEntrySpawnButtons(entry)
    entry = tostring(entry or "")
    if not entry:match("^%d+$") or entry == "0" then
        return ""
    end
    local def = BTN.add
    return " " .. R.MakeLink("npc", def.action, "0", entry, def.label, def.color)
end

local function ConfirmNpcDelete(guid)
    StaticPopupDialogs["NOBLENEXT_NPCCHAT_DELETE"] = {
        text = string.format("Удалить NPC с GUID %s?", guid),
        button1 = DELETE or YES,
        button2 = CANCEL or NO,
        OnAccept = function()
            local cmd = FormatCmd("npc delete", { guid = guid, [1] = guid }, "npc delete " .. guid)
            SendCmd(cmd, "npcchat:del")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("NOBLENEXT_NPCCHAT_DELETE")
end

local function HandleNpcAction(action, guid, entry)
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
            local cmd = FormatCmd("npc add", { entry = entry, [1] = entry }, "npc add " .. entry)
            SendCmd(cmd, "npcchat:add")
            if ns.SelectionContext then
                ns.SelectionContext.SetNpc(nil, entry, nil)
            end
        end
        return
    end

    if guid == "0" then
        return
    end

    if action == "sel" then
        if ns.SelectionContext then
            ns.SelectionContext.SetNpc(guid, entry, nil)
            ns.SelectionContext.RememberNearNpc({ guid = guid, entry = entry })
        end
        if ns.Print then
            ns.Print("Цель NPC GUID " .. tostring(guid))
        end
        return
    end

    if action == "move" then
        local cmd = FormatCmd("npc move", { guid = guid, [1] = guid }, "npc move " .. guid)
        SendCmd(cmd, "npcchat:move")
        if ns.SelectionContext then
            ns.SelectionContext.SetNpc(guid, entry, nil)
        end
        return
    end

    if action == "go" then
        local cmd = FormatCmd("go creature", { creature = guid, [1] = guid }, "go creature " .. guid)
        SendCmd(cmd, "npcchat:go")
        return
    end

    if action == "del" then
        ConfirmNpcDelete(guid)
        return
    end

    if action == "info" then
        -- info работает по выделенному NPC; сначала пробуем go? нет — только info + context
        if ns.SelectionContext then
            ns.SelectionContext.SetNpc(guid, entry, nil)
        end
        SendCmd(FormatCmd("npc info", {}, "npc info"), "npcchat:info")
        return
    end
end

local function Rewrite(msg)
    if IsCreatureEntryLookup(msg) then
        local entry = ExtractCreatureEntry(msg)
        if entry then
            local name = ExtractNpcName(msg)
            if ns.SelectionContext then
                -- не затираем активный guid; только мягкий entry hint не нужен здесь
            end
            return msg .. BuildEntrySpawnButtons(entry)
        end
        return msg
    end
    if IsCreatureInstanceMessage(msg) then
        local guid = ExtractCreatureGuid(msg)
        local entry = ExtractCreatureEntry(msg)
        local name = ExtractNpcName(msg)
        if guid then
            if ns.SelectionContext then
                ns.SelectionContext.RememberNearNpc({ guid = guid, entry = entry, name = name })
            end
            return msg .. BuildInstanceButtons(guid, entry)
        end
    end
    return msg
end

R.RegisterKind("npc", {
    match = function(msg)
        return IsCreatureEntryLookup(msg) or IsCreatureInstanceMessage(msg)
    end,
    rewrite = Rewrite,
    handle = HandleNpcAction,
})
