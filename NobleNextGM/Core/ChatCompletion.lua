-- Loaded through the NobleNextGM private extension namespace.
-- Core/ChatCompletion.lua — Tab-дополнение GM-команд через ns.CommandDefinitions.Complete
-- Активируется только для корней: .gobject / .gob / .lookup / .lo / .npc / .go / .tele / .gps
-- (longest-token: .go не перехватывает .gob / .gobject; .lo не перехватывает .lookup)

local _, ns = ...

-- Roots are derived from the currently visible singleton catalog. New DM/GM
-- families automatically participate; no second family allowlist can drift.
local function rootsLongestFirst()
    local defs = ns.CommandDefinitions
    if not defs or type(defs.GetRoots) ~= "function" then return {} end
    local roots = defs.GetRoots()
    table.sort(roots, function(a,b) return #a == #b and a < b or #a > #b end)
    return roots
end

local cycle = {
    base = nil,
    candidates = {},
    index = 0,
}

local popup
local function allowed() return ns.Access and ns.Access.Allows(2) == true end

local function trim(s)
    return (tostring(s or ""):match("^%s*(.-)%s*$")) or ""
end

--- Первый токен после точки; longest-root match / префикс незавершённого корня.
local function matchCompletionRoot(text)
    local t = trim(text)
    if t:sub(1, 1) ~= "." then
        return nil
    end
    local first = t:match("^%.([%w]+)")
    if not first or first == "" then
        return nil
    end
    first = first:lower()

    for _, root in ipairs(rootsLongestFirst()) do
        if first == root then
            return root
        end
    end

    -- Незавершённый ввод корня: ".gobje" -> gobject, ".g" -> несколько, берём longest prefix match
    local best, bestLen = nil, 0
    for _, root in ipairs(rootsLongestFirst()) do
        if root:sub(1, #first) == first and #root > bestLen then
            best, bestLen = root, #root
        end
    end
    return best
end

local function isOurCompletionContext(text)
    return matchCompletionRoot(text) ~= nil
end

local function candidateToString(c)
    if type(c) == "string" then
        return c
    end
    if type(c) ~= "table" then
        return nil
    end
    -- CommandDefinitions.Complete -> { text=, def=, kind=, detail= }
    local s = c.text or c.insert or c.completion or c.value or c.full or c.serverPath
    if type(s) == "string" and s ~= "" then
        return s
    end
    if type(c.path) == "table" then
        return table.concat(c.path, " ")
    end
    if type(c.path) == "string" then
        return c.path
    end
    return nil
end

local function normalizeInsert(text)
    text = trim(text)
    if text == "" then
        return text
    end
    if text:sub(1, 1) ~= "." then
        text = "." .. text:gsub("^[%./]+", "")
    end
    return text
end

local function ensureLeadingDotList(list)
    local out = {}
    local seen = {}
    for _, c in ipairs(list or {}) do
        local s = candidateToString(c)
        if s then
            s = normalizeInsert(s)
            if s ~= "" and not seen[s] then
                seen[s] = true
                out[#out + 1] = s
            end
        end
    end
    return out
end

local function hidePopup()
    if popup then
        popup:Hide()
    end
end

local function showPopup(candidates, index, anchor)
    if not allowed() then hidePopup(); return end
    if not candidates or #candidates == 0 then
        hidePopup()
        return
    end

    if not popup then
        popup = CreateFrame("Frame", "NobleNextChatCompletionPopup", UIParent, "BackdropTemplate")
        popup:SetFrameStrata("TOOLTIP")
        popup:SetClampedToScreen(true)
        if popup.SetBackdrop then
            popup:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            popup:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
            popup:SetBackdropBorderColor(0.4, 0.3, 0.15, 1)
        end
        popup.lines = {}
        popup:Hide()
    end

    local maxShow = math.min(8, #candidates)
    local width = 320
    local lineH = 14
    local pad = 8
    for i = 1, maxShow do
        local fs = popup.lines[i]
        if not fs then
            fs = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetJustifyH("LEFT")
            fs:SetPoint("TOPLEFT", popup, "TOPLEFT", pad, -pad - (i - 1) * lineH)
            fs:SetWidth(width - pad * 2)
            popup.lines[i] = fs
        end
        local text = candidates[i]
        if i == index then
            fs:SetText("|cffffd100> " .. text .. "|r")
        else
            fs:SetText("|cffbbbbbb  " .. text .. "|r")
        end
        fs:Show()
    end
    for i = maxShow + 1, #popup.lines do
        popup.lines[i]:Hide()
    end

    local extra = (#candidates > maxShow) and 1 or 0
    if extra > 0 then
        local fs = popup.lines[maxShow + 1]
        if not fs then
            fs = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            fs:SetJustifyH("LEFT")
            fs:SetPoint("TOPLEFT", popup, "TOPLEFT", pad, -pad - maxShow * lineH)
            fs:SetWidth(width - pad * 2)
            popup.lines[maxShow + 1] = fs
        end
        fs:SetText(string.format("|cff888888... ещё %d (Tab / Shift-Tab)|r", #candidates - maxShow))
        fs:Show()
    end

    popup:SetSize(width, pad * 2 + (maxShow + extra) * lineH)
    popup:ClearAllPoints()
    if anchor and anchor.GetName then
        popup:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
    else
        popup:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 40, 120)
    end
    popup:Show()

    if popup.fadeTicker then
        popup.fadeTicker:Cancel()
    end
    popup.fadeTicker = C_Timer.NewTimer(4, hidePopup)
end

local function applyCandidate(editBox, text)
    editBox:SetText(text)
    editBox:SetCursorPosition(#text)
end

local function gatherCandidates(text)
    local defs = ns.CommandDefinitions
    if not defs or type(defs.Complete) ~= "function" then
        return {}
    end
    local ok, result = pcall(defs.Complete, text)
    if not ok then
        ns.PrintDebug("CommandDefinitions.Complete error: " .. tostring(result))
        return {}
    end
    if type(result) ~= "table" then
        return {}
    end
    -- Complete может вернуть { candidates = {...} } или плоский список
    if result.candidates and type(result.candidates) == "table" then
        return ensureLeadingDotList(result.candidates)
    end
    return ensureLeadingDotList(result)
end

local function onTabPressed(editBox)
    if not allowed() then hidePopup(); return false end
    if not editBox or not editBox.GetText then
        return
    end

    local text = editBox:GetText() or ""
    if not isOurCompletionContext(text) then
        return false
    end

    local reverse = IsShiftKeyDown and IsShiftKeyDown()

    -- Продолжаем цикл, если текст — один из текущих кандидатов (после предыдущего Tab)
    local continueCycle = false
    if cycle.base and #cycle.candidates > 0 then
        local cur = normalizeInsert(text)
        for _, c in ipairs(cycle.candidates) do
            if c == cur then
                continueCycle = true
                break
            end
        end
        if not continueCycle and text == cycle.base then
            continueCycle = true
        end
    end

    if not continueCycle then
        cycle.base = text
        cycle.candidates = gatherCandidates(text)
        cycle.index = 0
        if #cycle.candidates == 0 and cycle.base ~= text then
            -- no-op
        end
    end

    if #cycle.candidates == 0 then
        -- Повторный Complete от base (без уже вставленного кандидата)
        if continueCycle and cycle.base then
            cycle.candidates = gatherCandidates(cycle.base)
        end
        if #cycle.candidates == 0 then
            hidePopup()
            -- Нет наших кандидатов — отдаём Tab штатному Blizzard-complete.
            return false
        end
    end

    if reverse then
        cycle.index = cycle.index - 1
        if cycle.index < 1 then
            cycle.index = #cycle.candidates
        end
    else
        cycle.index = cycle.index + 1
        if cycle.index > #cycle.candidates then
            cycle.index = 1
        end
    end

    local choice = cycle.candidates[cycle.index]
    if choice then
        applyCandidate(editBox, choice)
        showPopup(cycle.candidates, cycle.index, editBox)
    end
    return true
end

local prevHandler = ChatEdit_CustomTabPressed

function ChatEdit_CustomTabPressed(self)
    local handled = false
    local ok, result = pcall(onTabPressed, self)
    if ok then
        handled = result and true or false
    else
        ns.PrintDebug("ChatCompletion: " .. tostring(result))
    end
    if handled then
        return true
    end
    if prevHandler then
        return prevHandler(self)
    end
end

ns.ChatCompletion = {
    IsActiveContext = isOurCompletionContext,
    MatchRoot = matchCompletionRoot,
    HidePopup = hidePopup,
}

-- Сброс цикла при обычном вводе (не Tab)
local function hookEditBox(editBox)
    if not editBox or editBox._nnChatCompletionHooked then
        return
    end
    editBox._nnChatCompletionHooked = true
    editBox:HookScript("OnTextChanged", function(self, userInput)
        if not allowed() then hidePopup(); return end
        if userInput then
            local t = self:GetText() or ""
            local cur = normalizeInsert(t)
            local isCandidate = false
            for _, c in ipairs(cycle.candidates) do
                if c == cur then
                    isCandidate = true
                    break
                end
            end
            if not isCandidate then
                cycle.base = nil
                cycle.candidates = {}
                cycle.index = 0
                hidePopup()
            end
        end
    end)
    editBox:HookScript("OnEditFocusLost", hidePopup)
end

local function hookAllChatEdits()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb then
            hookEditBox(eb)
        end
    end
    if ChatFrame1EditBox then
        hookEditBox(ChatFrame1EditBox)
    end
end

hookAllChatEdits()
C_Timer.After(0, hookAllChatEdits)
ns.Subscribe("ACCESS_CHANGED", "gm.chat-completion", function()
    cycle.base=nil; cycle.candidates={}; cycle.index=0
    hidePopup()
end)

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    hookAllChatEdits()
end)
