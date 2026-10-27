-- «Развитие» window: RP level, XP progress and personal ability slots. No level-up control.
local _, ns = ...
local P = ns.Progression
local frame
local MAX_LINES = 12

local function Build()
    frame = CreateFrame("Frame", "NobleNextProgressionFrame", UIParent, "BackdropTemplate")
    frame:SetSize(420, 330); frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60); frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    frame:SetBackdropColor(0.08, 0.06, 0.1, 0.95)
    frame:EnableMouse(true)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", 0, -14); frame.title:SetText("Развитие")
    frame.bar = CreateFrame("StatusBar", nil, frame)
    frame.bar:SetSize(380, 14); frame.bar:SetPoint("TOP", 0, -44)
    frame.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    frame.bar:SetStatusBarColor(0.58, 0.0, 0.55)
    frame.lines = {}
    for i = 1, MAX_LINES do
        local line = frame:CreateFontString(nil, "OVERLAY", i == 1 and "GameFontHighlight" or "GameFontHighlightSmall")
        line:SetPoint("TOPLEFT", 20, -66 - (i - 1) * 19); line:SetJustifyH("LEFT")
        frame.lines[i] = line
    end
    frame.close = ns.CreateNGButton(frame, "Закрыть", 100, 24)
    frame.close:SetPoint("BOTTOM", 0, 12)
    frame.close:SetScript("OnClick", function() frame:Hide() end)
    frame:Hide()
end

function P.Render()
    if not frame or not frame:IsShown() then return end
    local data, lines = P.data, P.Lines()
    for i = 1, MAX_LINES do frame.lines[i]:SetText(lines[i] or "") end
    if type(data) == "table" then
        local needed = data.atCap and 1 or math.max(1, data.xpNeeded or 1)
        frame.bar:SetMinMaxValues(0, needed)
        frame.bar:SetValue(data.atCap and needed or math.min(needed, data.xp or 0))
    else
        frame.bar:SetMinMaxValues(0, 1); frame.bar:SetValue(0)
    end
end

function P.Open()
    if not frame then Build() end
    frame:Show()
    P.Render()
    P.Request(true)
    return frame
end

function P.Toggle()
    if frame and frame:IsShown() then frame:Hide(); return frame end
    return P.Open()
end
