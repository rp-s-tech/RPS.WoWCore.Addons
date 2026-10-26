local Lib = LibStub("NobleNextLib-1.0")
local ns = Lib.Runtime
local LAUNCHER_SIZE = 36
local SIZE, STEP, PAD, EDGE = 44, 52, 8, 8
local COLUMN_GAP, ANCHOR_GAP, LABEL_MAX = 24, 14, 204
local MIN_ROW_WIDTH, MAX_COLUMNS = 204, 3

-- The logo already includes a high-resolution ring and transparent corners.
-- Render it whole; the legacy minimap border becomes pixelated at larger scales.
function ns.CreateLauncherIcon(parent, texture, isLogo, size)
    size = size or LAUNCHER_SIZE
    local scale = size / LAUNCHER_SIZE
    if isLogo then
        local icon = parent:CreateTexture(nil, "ARTWORK")
        icon:SetSize(28 * scale, 28 * scale)
        icon:SetPoint("CENTER")
        -- Prepared at 128px with antialiased edges and explicit 8-bit alpha.
        -- A distinct path also avoids reusing the legacy BLP texture cache.
        icon:SetTexture("Interface\\AddOns\\NobleNext\\Assets\\LogoLauncher.tga", "CLAMP", "CLAMP", "LINEAR")
        icon:SetSnapToPixelGrid(false)
        icon:SetTexelSnappingBias(0)
        return icon
    end
    local background = parent:CreateTexture(nil, "BACKGROUND")
    background:SetTexture(136467)
    background:SetSize(28 * scale, 28 * scale)
    background:SetPoint("CENTER")
    local icon = parent:CreateTexture(nil, "ARTWORK")
    local iconSize = 25 * scale
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("CENTER")
    icon:SetTexture(texture)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    local border = parent:CreateTexture(nil, "OVERLAY")
    border:SetTexture(136430)
    border:SetSize(50 * size / 31, 50 * size / 31)
    border:SetPoint("TOPLEFT")
    return icon
end

local function isInside(focus, frame)
    while focus do
        if focus == frame then return true end
        focus = focus.GetParent and focus:GetParent()
    end
    return false
end

function ns.CreateQuickFlyoutBar(anchor)
    local bar = CreateFrame("Frame", "NobleNextQuickFlyout", UIParent)
    bar:SetFrameStrata("DIALOG")
    bar:SetClampedToScreen(true)
    bar:SetClampRectInsets(-EDGE, EDGE, EDGE, -EDGE)
    bar:EnableMouse(true)
    bar:Hide()
    bar.rows = {}
    tinsert(UISpecialFrames, "NobleNextQuickFlyout")

    local scroll = Lib.Scroll.CreateFrame(bar)
    local content = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(content)
    bar.Scroll, bar.Content = scroll, content
    bar.overflow = false
    -- This owner knows the final grid extent. Native Update otherwise restores
    -- visibility from a stale range while the scroll child's anchors settle.
    -- The native bar explicitly supports owner-managed visibility in this mode.
    if scroll.ScrollBar and scroll.ScrollBar.SetHideIfUnscrollable then
        scroll.ScrollBar:SetHideIfUnscrollable(false)
    end
    local function updateScrollVisibility()
        if scroll.ScrollBar then scroll.ScrollBar:SetShown(bar.overflow) end
    end
    scroll:HookScript("OnScrollRangeChanged", updateScrollVisibility)
    scroll:HookScript("OnSizeChanged", updateScrollVisibility)
    local function onMouseWheel(_, delta)
        if bar.overflow then Lib.Scroll.HandleMouseWheel(scroll, delta) end
    end
    scroll:SetScript("OnMouseWheel", onMouseWheel)
    if scroll.SetPanExtent then scroll:SetPanExtent(STEP) end
    updateScrollVisibility()
    local measure = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    measure:Hide()

    local animation = bar:CreateAnimationGroup()
    animation:SetToFinalAlpha(true)
    local fade = animation:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(0.12)
    bar:SetScript("OnHide", function()
        animation:Stop()
        bar:SetAlpha(1)
        GameTooltip:Hide()
    end)
    bar:RegisterEvent("GLOBAL_MOUSE_DOWN")
    bar:SetScript("OnEvent", function()
        if not bar:IsShown() then return end
        for _, focus in ipairs(GetMouseFoci()) do
            if isInside(focus, bar) or isInside(focus, anchor) then return end
        end
        bar:Hide()
    end)

    local function acquire(index)
        if bar.rows[index] then return bar.rows[index] end
        local row = CreateFrame("Button", nil, content)
        row:SetHeight(SIZE)
        row:RegisterForClicks("LeftButtonUp")
        row:SetMotionScriptsWhileDisabled(true)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", onMouseWheel)
        row.Circle = CreateFrame("Frame", nil, row)
        row.Circle:SetSize(SIZE, SIZE)
        row.Icon = ns.CreateLauncherIcon(row.Circle, "Interface\\Icons\\INV_Misc_QuestionMark", false, SIZE)
        row.Label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        row.Label:SetWordWrap(false)
        row.Label:SetShadowColor(0, 0, 0, 1)
        row.Label:SetShadowOffset(1, -1)
        row.Background = row:CreateTexture(nil, "BACKGROUND")
        row.Background:SetColorTexture(0.055, 0.045, 0.03, 0.92)
        row.Background:SetHeight(32)
        row.Top = row:CreateTexture(nil, "BORDER")
        row.Bottom = row:CreateTexture(nil, "BORDER")
        for _, line in ipairs({row.Top, row.Bottom}) do
            line:SetColorTexture(1, 0.82, 0, 0.25)
            line:SetHeight(1)
        end
        row.Top:SetPoint("TOPLEFT", row.Background)
        row.Top:SetPoint("TOPRIGHT", row.Background)
        row.Bottom:SetPoint("BOTTOMLEFT", row.Background)
        row.Bottom:SetPoint("BOTTOMRIGHT", row.Background)
        row:SetScript("OnEnter", function(self)
            self.Background:SetColorTexture(0.22, 0.16, 0.07, 0.95)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(self.action.title)
            if self.action.disabledReason then GameTooltip:AddLine(self.action.disabledReason, 0.8, 0.8, 0.8, true) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self.Background:SetColorTexture(0.055, 0.045, 0.03, 0.92)
            GameTooltip:Hide()
        end)
        row:SetScript("OnClick", function(self)
            local id = self.action.id
            -- The registry rechecks current access and availability on click.
            if ns.ExecuteQuickAction(id) then bar:Hide() end
        end)
        bar.rows[index] = row
        return row
    end

    function bar:Rebuild()
        local actions = ns.GetVisibleQuickActions()
        for _, row in ipairs(self.rows) do row:Hide() end
        if #actions == 0 then self:Hide(); return false, "empty" end
        local scale = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local cx, cy = anchor:GetCenter()
        if not cx or not cy then return false end
        cx, cy = cx * scale, cy * scale
        local halfH = anchor:GetHeight() * scale / 2
        local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
        local inwardLeft = cx >= screenW / 2
        local sideSpace = math.min(screenW - EDGE * 2,
            inwardLeft and (cx + SIZE / 2 - EDGE) or (screenW - cx + SIZE / 2 - EDGE))
        local above, below = screenH - cy - halfH - ANCHOR_GAP - EDGE, cy - halfH - ANCHOR_GAP - EDGE
        local allHeight = (#actions - 1) * STEP + SIZE + PAD * 2
        local up = allHeight > below and above > below
        local availableH = math.min(screenH - EDGE * 2, math.max(SIZE + PAD * 2, up and above or below))
        local rowWidth = MIN_ROW_WIDTH
        for _, action in ipairs(actions) do
            measure:SetText(action.title)
            rowWidth = math.max(rowWidth, math.min(LABEL_MAX, measure:GetStringWidth()) + SIZE + 16)
        end
        local maxRows = math.max(1, math.floor((availableH - PAD * 2 - SIZE) / STEP) + 1)
        local columns = 1
        for candidate = 1, math.min(MAX_COLUMNS, #actions) do
            local needsScroll = math.ceil(#actions / candidate) > maxRows
            local neededWidth = candidate * MIN_ROW_WIDTH + (candidate - 1) * COLUMN_GAP
                + PAD * 2 + (needsScroll and 22 or 0)
            if neededWidth > sideSpace then break end
            columns = candidate
            if not needsScroll then break end
        end
        local rowsPerColumn = math.ceil(#actions / columns)
        local contentH = (rowsPerColumn - 1) * STEP + SIZE
        local viewH = math.min(contentH, availableH - PAD * 2)
        local overflow = contentH > viewH + 0.5
        local scrollbarW = overflow and 22 or 0
        rowWidth = math.min(rowWidth, (sideSpace - PAD * 2 - scrollbarW - (columns - 1) * COLUMN_GAP) / columns)
        rowWidth = math.max(SIZE + 12, rowWidth)
        local contentW = columns * rowWidth + (columns - 1) * COLUMN_GAP
        local width, height = contentW + PAD * 2 + scrollbarW, viewH + PAD * 2
        local x = inwardLeft and (cx + SIZE / 2 + PAD + scrollbarW - width) or (cx - SIZE / 2 - PAD)
        local y = up and (cy + halfH + ANCHOR_GAP) or (cy - halfH - ANCHOR_GAP - height)
        x = math.max(EDGE, math.min(screenW - width - EDGE, x))
        y = math.max(EDGE, math.min(screenH - height - EDGE, y))
        self:ClearAllPoints()
        self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
        self.overflow = overflow
        self:SetSize(width, height)
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -PAD)
        scroll:SetSize(contentW, viewH)
        content:SetSize(contentW, contentH)
        for i, action in ipairs(actions) do
            local row = acquire(i)
            row.action = action
            local col, index = math.floor((i - 1) / rowsPerColumn), (i - 1) % rowsPerColumn
            local colX = inwardLeft and (columns - 1 - col) or col
            local indexY = up and (rowsPerColumn - 1 - index) or index
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", colX * (rowWidth + COLUMN_GAP), -indexY * STEP)
            row:SetWidth(rowWidth)
            row.Circle:ClearAllPoints()
            row.Circle:SetPoint(inwardLeft and "RIGHT" or "LEFT")
            row.Label:ClearAllPoints()
            row.Background:ClearAllPoints()
            row.Label:SetWidth(math.max(1, math.min(LABEL_MAX, rowWidth - SIZE - 16)))
            if inwardLeft then
                row.Label:SetPoint("RIGHT", row.Circle, "LEFT", -8, 0)
                row.Background:SetPoint("LEFT", row, "LEFT")
                row.Background:SetPoint("RIGHT", row.Circle, "LEFT", -4, 0)
            else
                row.Label:SetPoint("LEFT", row.Circle, "RIGHT", 8, 0)
                row.Background:SetPoint("LEFT", row.Circle, "RIGHT", 4, 0)
                row.Background:SetPoint("RIGHT", row, "RIGHT")
            end
            row.Label:SetJustifyH(inwardLeft and "RIGHT" or "LEFT")
            row.Label:SetText(action.title)
            row.Icon:SetTexture(action.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            if action.icon == "Interface\\AddOns\\NobleNext\\Assets\\Logo" then
                row.Icon:SetTexCoord(0.09, 0.91, 0.09, 0.91)
                row.Icon:SetSize(21 * SIZE / LAUNCHER_SIZE, 21 * SIZE / LAUNCHER_SIZE)
            else
                row.Icon:SetTexCoord(0, 1, 0, 1)
                row.Icon:SetSize(25 * SIZE / LAUNCHER_SIZE, 25 * SIZE / LAUNCHER_SIZE)
            end
            local enabled = action.enabled ~= false
            row:SetEnabled(enabled)
            row.Icon:SetDesaturated(not enabled)
            if enabled then row.Label:SetTextColor(1, 1, 1) else row.Label:SetTextColor(0.5, 0.5, 0.5) end
            row:Show()
        end
        scroll:UpdateScrollChildRect()
        scroll:SetVerticalScroll(up and math.max(0, contentH - viewH) or 0)
        updateScrollVisibility()
        self.columns, self.growsUp, self.inwardLeft = columns, up, inwardLeft
        return true
    end
    function bar:Open()
        local ready, reason = self:Rebuild()
        if not ready then
            if reason == "empty" then
                GameTooltip:SetOwner(anchor, "ANCHOR_LEFT")
                GameTooltip:SetText("Быстрые действия не выбраны.")
                GameTooltip:AddLine("Shift + ЛКМ — меню и настройки.", 0.85, 0.85, 0.85, true)
                GameTooltip:Show()
            end
            return false
        end
        self:Show()
        -- Refresh once visible too: a hidden scroll frame can still report its
        -- previous native range during the first layout pass.
        scroll:UpdateScrollChildRect()
        scroll:SetVerticalScroll(self.growsUp and math.max(0, content:GetHeight() - scroll:GetHeight()) or 0)
        updateScrollVisibility()
        animation:Stop()
        self:SetAlpha(1)
        animation:Play()
        return true
    end
    if ns.Subscribe then
        ns.Subscribe("ACCESS_CHANGED", "NobleNextQuickFlyout", function() bar:Hide() end)
        ns.Subscribe("QUICK_ACTIONS_CHANGED", "NobleNextQuickFlyout", function() bar:Hide() end)
    end
    return bar
end
