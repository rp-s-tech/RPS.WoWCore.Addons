local Lib = LibStub("NobleNextLib-1.0")
local Theme = Lib.Theme

Theme.COLORS = {
    primary = "|cff00ccff",
    success = "|cff629404",
    warning = "|cffff9900",
    error = "|cffff0000",
    info = "|cff8bad4c",
    white = "|cffffffff",
    gray = "|cffbbbbbb",
    gold = "|cffffd100",
    goldRaw = { r = 1.0, g = 0.82, b = 0 },
    dark = { r = 0.05, g = 0.06, b = 0.08, a = 0.96 },
    panel = { r = 0.08, g = 0.09, b = 0.12, a = 0.94 },
    surface = { r = 0.07, g = 0.08, b = 0.10, a = 0.92 },
    active = { r = 0.24, g = 0.19, b = 0.08, a = 0.96 },
    border = { r = 0.62, g = 0.50, b = 0.24, a = 0.92 },
    borderMuted = { r = 0.28, g = 0.30, b = 0.36, a = 0.72 },
    textMuted = { r = 0.72, g = 0.74, b = 0.78, a = 1 },
}

Theme.FONT = {
    title = "GameFontNormalLarge",
    normal = "GameFontNormal",
    highlight = "GameFontHighlight",
    small = "GameFontNormalSmall",
    highlightSmall = "GameFontHighlightSmall",
}

Theme.PAD = {
    shell = 12,
    gap = 10,
    titleY = -16,
    sidebarWidth = 180,
    contentInset = 8,
}

function Theme.Color(name, text)
    return (Theme.COLORS[name] or "") .. tostring(text or "") .. "|r"
end
