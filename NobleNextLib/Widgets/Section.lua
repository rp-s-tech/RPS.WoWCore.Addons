local Lib = LibStub("NobleNextLib-1.0")
local Theme = Lib.Theme
local Widgets = Lib.Widgets

function Widgets.CreateSection(parent, options)
    options = options or {}
    local titleText = options.title or options.titleText
    local width = options.width
    local height = options.height

    local c = CreateFrame("Frame", options.name, parent, "BackdropTemplate")
    if width and height then
        c:SetSize(width, height)
    elseif width then
        c:SetWidth(width)
    elseif height then
        c:SetHeight(height)
    end
    Theme.Apply(c, "section")

    if titleText then
        local lbl = c:CreateFontString(nil, "OVERLAY", Theme.FONT.normal)
        lbl:SetText(titleText)
        local g = Theme.COLORS.goldRaw
        lbl:SetTextColor(g.r, g.g, g.b)
        lbl:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -8)
        lbl:SetPoint("TOPRIGHT", c, "TOPRIGHT", -12, -8)
        lbl:SetJustifyH("LEFT")
        c.Title = lbl
        if options.divider ~= false then
            local divider = c:CreateTexture(nil, "ARTWORK")
            divider:SetHeight(1)
            divider:SetPoint("TOPLEFT", c, "TOPLEFT", 10, -26)
            divider:SetPoint("TOPRIGHT", c, "TOPRIGHT", -10, -26)
            divider:SetColorTexture(1, 0.82, 0, 0.18)
            c.Divider = divider
        end
    end

    return c
end

function Widgets.CreateSectionLegacy(parent, titleText, width, height)
    return Widgets.CreateSection(parent, {
        title = titleText,
        width = width,
        height = height,
        -- Legacy panels position their first row as high as y=-22. Do not
        -- draw a divider through those controls without migrating the layout.
        divider = false,
    })
end
