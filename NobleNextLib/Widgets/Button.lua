local Lib = LibStub("NobleNextLib-1.0")
local Theme = Lib.Theme
local Widgets = Lib.Widgets
local SafeString = Lib.Runtime.Util.SafeString

local function ApplyCtaStyle(btn, style)
    local fs = btn.GetFontString and btn:GetFontString()
    local r, g, b = 1, 1, 1
    if style == "danger" then
        if fs then fs:SetTextColor(1, 0.62, 0.55) end
        r, g, b = 0.85, 0.32, 0.28
    elseif style == "ghost" or style == "secondary" then
        if fs then fs:SetTextColor(0.82, 0.84, 0.88) end
        r, g, b = 0.68, 0.72, 0.78
    elseif style == "primary" or style == "active" then
        if fs then fs:SetTextColor(1, 0.92, 0.55) end
        r, g, b = 1, 0.88, 0.45
    else
        if fs then fs:SetTextColor(1, 0.82, 0) end
    end
    for _, key in ipairs({"Left", "Middle", "Right"}) do
        if btn[key] then btn[key]:SetVertexColor(r, g, b) end
    end
end

function Widgets.CreateButton(parent, options)
    options = options or {}
    local text = SafeString(options.text, SafeString(options[1]))
    local width = options.width or options[2] or 100
    local height = options.height or options[3] or 22
    local name = options.name

    local btn = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    btn:SetSize(width, height)
    btn:SetText(text)
    ApplyCtaStyle(btn, options.style)

    if options.onClick then
        btn:SetScript("OnClick", options.onClick)
    end
    if SafeString(options.tooltip) ~= "" then
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(SafeString(options.tooltip), 1, 0.82, 0)
            if options.tooltipLines then
                for _, line in ipairs(options.tooltipLines) do
                    GameTooltip:AddLine(SafeString(line), 0.8, 0.8, 0.8, true)
                end
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    function btn:SetEnabledEx(enabled, reason)
        reason = SafeString(reason)
        -- Capture original tooltip scripts once so disable-reason never permanently replaces them.
        if self._nnTooltipCaptured == nil then
            self._nnOrigOnEnter = self:GetScript("OnEnter")
            self._nnOrigOnLeave = self:GetScript("OnLeave")
            self._nnTooltipCaptured = true
        end

        self:SetEnabled(enabled and true or false)
        if not enabled and reason ~= "" then
            self._disabledReason = reason
            self:SetScript("OnEnter", function(self2)
                GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
                GameTooltip:AddLine(reason, 1, 0.4, 0.3, true)
                GameTooltip:Show()
            end)
            self:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        else
            self._disabledReason = nil
            self:SetScript("OnEnter", self._nnOrigOnEnter)
            self:SetScript("OnLeave", self._nnOrigOnLeave)
        end
    end

    function btn:SetActiveState(active)
        self._nnActive = active and true or false
        ApplyCtaStyle(self, active and "active" or options.style)
    end

    return btn
end

function Widgets.CreateIconButton(parent, options)
    options = options or {}
    local name = options.name
    local width = options.width or 36
    local height = options.height or 36
    local btn = CreateFrame("Button", name, parent)
    btn:SetSize(width, height)
    if options.icon then
        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(options.icon)
        btn.Icon = tex
    end
    if options.onClick then
        btn:SetScript("OnClick", options.onClick)
    end
    return btn
end

function Widgets.CreateLabel(parent, options)
    options = options or {}
    local text = SafeString(options.text, SafeString(options[1]))
    local outline = options.outline or options[2]
    local fontObject = outline and Theme.FONT.normal or Theme.FONT.highlight
    local label = parent:CreateFontString(nil, "OVERLAY", fontObject)
    if outline then
        local g = Theme.COLORS.goldRaw
        label:SetTextColor(g.r, g.g, g.b)
    end
    label:SetText(text)
    return label
end
