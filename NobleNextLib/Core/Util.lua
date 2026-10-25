local Util = LibStub("NobleNextLib-1.0").Runtime.Util

local function DisplayFallback(value)
    if issecretvalue and issecretvalue(value) then return "" end
    return type(value) == "string" and value or ""
end

-- Prepare editable text only. Native activation also restores alpha, focus
-- regions and chat headers; Show() alone leaves a faded edit box invisible.
function Util.InsertTextIntoChat(text)
    if type(text) ~= "string" or text == "" then return false end
    local choose = ChatFrameUtil and ChatFrameUtil.ChooseBoxForSend or ChatEdit_ChooseBoxForSend
    local activate = ChatFrameUtil and ChatFrameUtil.ActivateChat or ChatEdit_ActivateChat
    local box = choose and choose() or ChatFrame1EditBox
    if not box or box.disableActivate then return false end
    if activate then
        activate(box)
    else
        box:Show()
        if box.SetAlpha then box:SetAlpha(1) end
    end
    box:SetText(text)
    if box.SetFocus then box:SetFocus() end
    if box.HighlightText then box:HighlightText(0, 0) end
    if box.SetCursorPosition then box:SetCursorPosition(#text) end
    return true
end

-- Presentation only: never use a display fallback for IDs, permissions, sender
-- validation or command arguments. Test secrecy before comparing/converting.
function Util.SafeString(value, fallback)
    if issecretvalue and issecretvalue(value) then
        return DisplayFallback(fallback)
    end
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then
        return tostring(value)
    end
    -- Do not invoke __tostring on arbitrary objects or inspect secret tables.
    return DisplayFallback(fallback)
end
