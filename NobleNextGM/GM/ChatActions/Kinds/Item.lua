-- Loaded through the NobleNextGM private extension namespace.
-- GM/ChatActions/Kinds/Item.lua — кнопки additem в system chat

local _, ns = ...

local R = ns.ChatActions
if not R or not R.RegisterKind then
    return
end

local ITEM_BTN = {
    add     = { action = "add",     label = "+1",  color = "ff629404" },
    destroy = { action = "destroy", label = "Des", color = "ffff4444" },
}

local function SendCmd(cmd)
    if ns.EnqueueCommand then
        ns.EnqueueCommand(cmd, { tag = "gobchat" })
    elseif ns.RunGmCommand then
        ns.RunGmCommand(cmd)
    else
        ns.PrintError("RunGmCommand недоступен.")
    end
end

local function MakeItemLink(action, itemId, label, color)
    return R.MakeLink("item", action, itemId, nil, label, color)
end

local function BuildItemButtons(itemId)
    itemId = tostring(itemId or "")
    if itemId == "" then
        return ""
    end
    local parts = {}
    for _, key in ipairs({ "add", "destroy" }) do
        local def = ITEM_BTN[key]
        parts[#parts + 1] = MakeItemLink(def.action, itemId, def.label, def.color)
    end
    return " " .. table.concat(parts, " ")
end

local function ExtractItemId(msg)
    local id = msg:match("|Hitem:(%d+)")
    if id then
        return id
    end
    id = msg:match("[Ii]tem%s+'?(%d+)'?")
    if id then
        return id
    end
    id = msg:match("[Aa]dditem.-[Ii]tem[Ii]d%s*=%s*(%d+)")
    if id then
        return id
    end
    id = msg:match("[Aa]dd%s*[Ii]tem.-(%d+)")
    if id then
        return id
    end
    id = msg:match("[Cc]ommand%s*:?%s*[Aa]dditem.-(%d+)")
    if id then
        return id
    end
    if msg:lower():find("additem", 1, true) or msg:lower():find("add item", 1, true) then
        id = msg:match("(%d+)")
    end
    return id
end

local function IsAddItemMessage(msg)
    local lower = msg:lower()
    if msg:find("|Hitem:", 1, true) and (
        lower:find("additem", 1, true)
        or lower:find("add item", 1, true)
        or lower:find("itemid", 1, true)
    ) then
        return true
    end
    if lower:find("additem", 1, true) or lower:find("add item", 1, true) then
        return true
    end
    return false
end

local function HandleItemAction(action, itemId)
    itemId = tonumber(itemId)
    if not itemId then
        return
    end
    if action == "add" then
        SendCmd("additem " .. itemId .. " 1")
        return
    end
    if action == "destroy" then
        SendCmd("additem " .. itemId .. " -1")
        return
    end
end

R.RegisterKind("item", {
    match = IsAddItemMessage,
    rewrite = function(msg)
        local itemId = ExtractItemId(msg)
        if not itemId then
            return msg
        end
        return msg .. BuildItemButtons(itemId)
    end,
    handle = HandleItemAction,
})

ns.GobChat = ns.GobChat or {}
ns.GobChat.MakeItemLink = MakeItemLink
ns.GobChat.BuildItemButtons = BuildItemButtons
ns.GobChat.HandleItemAction = HandleItemAction
