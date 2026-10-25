local Lib = LibStub("NobleNextLib-1.0")
local Theme = Lib.Theme

local PRESETS = {
    window = {
        bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 64, edgeSize = 20,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
        color = { 0.09, 0.10, 0.13, 0.97 },
        border = { 0.72, 0.60, 0.32, 0.98 },
    },
    miniWindow = {
        bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 64, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
        color = { 0.07, 0.08, 0.11, 0.96 },
        border = { 0.78, 0.64, 0.28, 0.96 },
    },
    header = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
        color = { 0.12, 0.10, 0.07, 0.95 },
        border = { 0.68, 0.54, 0.22, 0.85 },
    },
    surface = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
        color = { 0.06, 0.07, 0.09, 0.88 },
        border = { 0.24, 0.26, 0.32, 0.65 },
    },
    section = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
        color = { 0.08, 0.09, 0.12, 0.86 },
        border = { 0.32, 0.28, 0.18, 0.62 },
    },
    card = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
        color = { 0.10, 0.11, 0.15, 0.92 },
        border = { 0.52, 0.42, 0.20, 0.78 },
    },
    input = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 0, edgeSize = 8,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
        color = { 0.02, 0.03, 0.05, 0.78 },
        border = { 0.45, 0.48, 0.55, 0.85 },
    },
    row = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
        color = { 0.07, 0.08, 0.10, 0.84 },
        border = { 0.24, 0.24, 0.28, 0.55 },
    },
    rowSelected = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
        color = { 0.22, 0.18, 0.08, 0.94 },
        border = { 0.95, 0.78, 0.22, 0.95 },
    },
    tab = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
        color = { 0.08, 0.09, 0.12, 0.88 },
        border = { 0.28, 0.30, 0.36, 0.65 },
    },
    tabSelected = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
        color = { 0.24, 0.19, 0.08, 0.96 },
        border = { 1, 0.82, 0, 1 },
    },
}

function Theme.Apply(frame, presetName)
    if not frame or not frame.SetBackdrop then
        return frame
    end
    local preset = PRESETS[presetName or "surface"] or PRESETS.surface
    frame:SetBackdrop({
        bgFile = preset.bgFile,
        edgeFile = preset.edgeFile,
        tile = preset.tile,
        tileSize = preset.tileSize,
        edgeSize = preset.edgeSize,
        insets = preset.insets,
    })
    frame:SetBackdropColor(unpack(preset.color))
    frame:SetBackdropBorderColor(unpack(preset.border))
    return frame
end

--- Apply SharedUIPanelTemplates / Epsilon-style header & inner-shadow chrome when supported by client.
function Theme.DecorateWindow(frame, options)
    if not frame or not frame.CreateTexture then
        return
    end
    options = options or {}
    local headerH = options.headerHeight or 30
    local inset = options.inset or 4

    local titleBg = frame.CreateTexture and frame:CreateTexture(nil, "BACKGROUND")
    if titleBg then
        if titleBg.SetPoint then
            titleBg:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
            titleBg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
        end
        if titleBg.SetHeight then titleBg:SetHeight(headerH) end
        if titleBg.SetColorTexture then
            titleBg:SetColorTexture(0.14, 0.11, 0.06, 0.92)
        end
        frame.TitleBg = titleBg
    end

    local streak = frame.CreateTexture and frame:CreateTexture(nil, "BORDER")
    if streak then
        if streak.SetAtlas then
            pcall(streak.SetAtlas, streak, "_GM_BehaviorMessage_Top_InnerShadow", false)
        end
        if streak.SetPoint then
            streak:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -(inset + headerH))
            streak:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -(inset + headerH))
        end
        if streak.SetHeight then streak:SetHeight(14) end
        if streak.SetAlpha then streak:SetAlpha(0.45) end
        frame.TopTileStreaks = streak
    end

    local headerLine = frame.CreateTexture and frame:CreateTexture(nil, "ARTWORK")
    if headerLine then
        if headerLine.SetPoint then
            headerLine:SetPoint("TOPLEFT", frame, "TOPLEFT", inset + 2, -(inset + headerH))
            headerLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(inset + 2), -(inset + headerH))
        end
        if headerLine.SetHeight then headerLine:SetHeight(1) end
        if headerLine.SetColorTexture then
            headerLine:SetColorTexture(0.85, 0.68, 0.24, 0.55)
        end
        frame.HeaderDivider = headerLine
    end
end

Theme.ApplyBackdrop = Theme.Apply
