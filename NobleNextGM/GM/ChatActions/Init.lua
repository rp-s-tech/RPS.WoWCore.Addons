-- Loaded through the NobleNextGM private extension namespace.
-- GM/ChatActions/Init.lua — единый CHAT_MSG_SYSTEM filter + SetItemRef dispatcher

local _, ns = ...

local R = ns.ChatActions
if not R then
    return
end

local function FilterSystemMessage(_self, _event, message, ...)
    -- CHAT_MSG_SYSTEM payload #11 is lineID (message is #1).
    local rewritten = R.Rewrite(message, select(10, ...))
    return false, rewritten, ...
end

local function RegisterChatFilter()
    if R._chatFilterRegistered then
        return
    end
    if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_SYSTEM", FilterSystemMessage)
        R._chatFilterRegistered = true
    elseif ChatFrame_AddMessageEventFilter then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", FilterSystemMessage)
        R._chatFilterRegistered = true
    end
end

-- Blizzard addon: links fire EventRegistry("SetItemRef") inside SetItemRef.
-- Installing BOTH EventRegistry and hooksecurefunc doubles every chat action (e.g. two gobject add).
local function RegisterLinkHandler()
    if R._linkHandlerRegistered then
        return
    end
    if EventRegistry and EventRegistry.RegisterCallback then
        if EventRegistry.UnregisterCallback then
            pcall(function()
                EventRegistry:UnregisterCallback("SetItemRef", R)
            end)
        end
        EventRegistry:RegisterCallback("SetItemRef", function(_, link, text, button, frame)
            R.OnSetItemRef(link, text, button, frame)
        end, R)
        R._linkHandlerRegistered = true
        return
    end

    if type(hooksecurefunc) == "function" and type(SetItemRef) == "function" then
        hooksecurefunc("SetItemRef", function(link, text, button, frame)
            if type(link) == "string" and link:find("addon:NobleNext:", 1, true) then
                R.OnSetItemRef(link, text, button, frame)
            end
        end)
        R._linkHandlerRegistered = true
    end
end

RegisterChatFilter()
RegisterLinkHandler()
if not (R._chatFilterRegistered and R._linkHandlerRegistered) and not R._registrationFrame then
    local frame = CreateFrame("Frame")
    R._registrationFrame = frame
    frame:RegisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function()
        RegisterChatFilter(); RegisterLinkHandler()
        if R._chatFilterRegistered and R._linkHandlerRegistered then frame:UnregisterAllEvents() end
    end)
end
