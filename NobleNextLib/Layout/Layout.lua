local Lib = LibStub("NobleNextLib-1.0")
local Theme = Lib.Theme
local Layout = Lib.Layout

Layout.Pad = Theme.PAD

function Layout.Fill(frame, parent, insets)
    insets = insets or {}
    local left = insets.left or 0
    local right = insets.right or 0
    local top = insets.top or 0
    local bottom = insets.bottom or 0
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -top)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -right, bottom)
    return frame
end

function Layout.GetBreakpoint(width)
    width = tonumber(width) or 0
    if width < 600 then
        return "compact"
    elseif width < 800 then
        return "standard"
    end
    return "wide"
end

--- Place frames in a horizontal row with optional wrap.
--- frames: array of frames already sized
function Layout.PlaceRow(frames, anchorParent, startX, startY, gap, wrapWidth)
    gap = gap or 6
    startX = startX or 0
    startY = startY or 0
    local x, y = startX, startY
    local rowH = 0
    for _, frame in ipairs(frames or {}) do
        local w = frame:GetWidth() or 80
        local h = frame:GetHeight() or 22
        if wrapWidth and x > startX and (x + w) > wrapWidth then
            x = startX
            y = y - (rowH + gap)
            rowH = 0
        end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", anchorParent, "TOPLEFT", x, y)
        x = x + w + gap
        if h > rowH then rowH = h end
    end
    return y - rowH
end

function Layout.StackVertical(parent, children, options)
    options = options or {}
    local gap = options.gap or 8
    local pad = options.pad or 0
    local y = -pad
    for _, child in ipairs(children or {}) do
        child:ClearAllPoints()
        child:SetPoint("TOPLEFT", parent, "TOPLEFT", pad, y)
        if options.stretchWidth then
            child:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -pad, y)
        end
        y = y - ((child:GetHeight() or 0) + gap)
    end
    return -y + pad
end

function Layout.CreateSplit(parent, options)
    options = options or {}
    local gap = options.gap or Theme.PAD.gap
    local leftWidth = options.leftWidth
    local ratio = options.ratio or 0.4

    local host = CreateFrame("Frame", options.name, parent)
    Layout.Fill(host, parent)

    local left = CreateFrame("Frame", nil, host, "BackdropTemplate")
    local right = CreateFrame("Frame", nil, host, "BackdropTemplate")
    if options.applyTheme ~= false then
        Theme.Apply(left, "surface")
        Theme.Apply(right, "surface")
    end

    local function Relayout()
        local w = host:GetWidth() or 0
        local lw = leftWidth
        if not lw then
            lw = math.floor(w * ratio)
        end
        left:ClearAllPoints()
        right:ClearAllPoints()
        left:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
        left:SetWidth(math.max(120, lw))
        right:SetPoint("TOPLEFT", left, "TOPRIGHT", gap, 0)
        right:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    end

    host:SetScript("OnSizeChanged", Relayout)
    host.Left = left
    host.Right = right
    host.Relayout = Relayout
    Relayout()
    return host
end

function Layout.CreateVertical(parent, options)
    options = options or {}
    local frame
    if CreateFrame and (options.useBlizzard ~= false) then
        -- Prefer VerticalLayoutFrame when available; fall back to plain frame.
        local ok, f = pcall(CreateFrame, "Frame", options.name, parent, "VerticalLayoutFrame")
        if ok and f then
            frame = f
        end
    end
    frame = frame or CreateFrame("Frame", options.name, parent)
    if options.width then frame:SetWidth(options.width) end
    if options.height then frame:SetHeight(options.height) end
    return frame
end
