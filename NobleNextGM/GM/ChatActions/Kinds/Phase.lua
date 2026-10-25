-- Loaded through the NobleNextGM private extension namespace.
-- GM/ChatActions/Kinds/Phase.lua — phase hyperlinks из Codex.
-- id передаётся и хранится как decimal string, без tonumber().

local _, ns = ...

local registry = ns.ChatActions
if not registry or not registry.RegisterKind then
    return
end

local function insertChatLink(text, link)
    local full = text
    if type(link) == "string" and link ~= "" and (not full or not full:find("|H", 1, true)) then
        -- Reconstruct display hyperlink if only payload was passed.
        full = string.format("|H%s|h[%s]|h", link, link)
    end
    if type(full) ~= "string" or full == "" then
        return false
    end
    if ChatEdit_InsertLink and ChatEdit_InsertLink(full) then
        return true
    end
    local edit = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if edit and edit.InsertLink then
        edit:InsertLink(full)
        return true
    end
    if edit and edit.SetText then
        edit:SetText((edit:GetText() or "") .. full)
        return true
    end
    return false
end

local function isChatLinkClick(button)
    if IsModifiedClick and IsModifiedClick("CHATLINK") then
        return true
    end
    if IsShiftKeyDown and IsShiftKeyDown() then
        return true
    end
    return button == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown()
end

registry.RegisterKind("phase", {
    match = function()
        return false -- Phase ссылки создаёт сам Codex, rewrite CHAT_MSG_SYSTEM не требуется.
    end,
    rewrite = function(message)
        return message
    end,
    handle = function(action, id, entry, ctx)
        ctx = ctx or {}
        if isChatLinkClick(ctx.button) then
            local text = ctx.text
            if type(text) ~= "string" or text == "" then
                local label = action == "enter" and ("Войти #" .. tostring(id))
                    or action == "goto" and ("Goto #" .. tostring(id))
                    or ("Открыть #" .. tostring(id))
                text = registry.MakeLink("phase", action, id, nil, label, "ff8bad4c")
            end
            insertChatLink(text)
            return
        end

        if action == "open" then
            if ns.PhasePanel and ns.PhasePanel.OpenPhase then
                ns.PhasePanel.OpenPhase(id)
            end
            return
        end

        -- enter / goto: server transition only — do not open Codex panel.
        if action == "enter" and ns.Phases and ns.Phases.Enter then
            ns.Phases.Enter(id, function(ok, response)
                if ns.Print then
                    if ok then
                        ns.Print("RP phase enter #" .. tostring(id) .. " ok.")
                    else
                        ns.Print("RP phase enter #" .. tostring(id) .. " failed: "
                            .. tostring(response and (response.detail or response.reason) or "error"))
                    end
                end
            end)
            return
        end

        if action == "goto" and ns.Phases and ns.Phases.Goto then
            ns.Phases.Goto(id, function(ok, response)
                if ns.Print then
                    if ok then
                        ns.Print("RP phase goto #" .. tostring(id) .. " ok.")
                    else
                        ns.Print("RP phase goto #" .. tostring(id) .. " failed: "
                            .. tostring(response and (response.detail or response.reason) or "error"))
                    end
                end
            end)
        end
    end,
})
