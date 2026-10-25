local Lib = LibStub("NobleNextLib-1.0")
local Theme = Lib.Theme
local StateView = Lib.StateView

local LEVEL_COLORS = {
    idle = { 0.70, 0.70, 0.70 },
    loading = { 0.85, 0.85, 0.55 },
    empty = { 0.70, 0.70, 0.70 },
    success = { 0.40, 0.85, 0.45 },
    warning = { 1.00, 0.70, 0.25 },
    error = { 1.00, 0.40, 0.35 },
    info = { 0.55, 0.75, 0.95 },
}

function StateView.Create(parent, options)
    options = options or {}
    local frame = CreateFrame("Frame", options.name, parent)
    if options.width and options.height then
        frame:SetSize(options.width, options.height)
    else
        frame:SetSize(options.width or 200, options.height or 40)
    end

    local text = frame:CreateFontString(nil, "OVERLAY", Theme.FONT.highlightSmall)
    text:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    text:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    text:SetJustifyH(options.justifyH or "LEFT")
    text:SetJustifyV(options.justifyV or "MIDDLE")
    frame.Text = text
    frame.level = "idle"

    function frame:SetState(level, message)
        self.level = level or "idle"
        local color = LEVEL_COLORS[self.level] or LEVEL_COLORS.idle
        self.Text:SetTextColor(color[1], color[2], color[3], 1)
        self.Text:SetText(message or "")
        self:Show()
    end

    function frame:Clear()
        self:SetState("idle", "")
    end

    frame:SetState(options.level or "idle", options.text or "")
    return frame
end

Lib.Widgets.CreateStateView = StateView.Create
