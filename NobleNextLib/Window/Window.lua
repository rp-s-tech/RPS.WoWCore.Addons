local Lib = LibStub("NobleNextLib-1.0")
local Theme = Lib.Theme
local Layout = Lib.Layout
local Resize = Lib.Resize
local Window = Lib.Window

--- Create a generic resizable window with optional sidebar slot.
--- options:
---   name, title, width, height, sidebarWidth, strata, resizable,
---   minWidth, minHeight, maxWidth, maxHeight, allowShrink,
---   onSizeChanged, onResizeStop
function Window.Create(options)
    options = options or {}
    local width = options.width or 820
    local height = options.height or 540
    local sidebarWidth = options.sidebarWidth
    local pad = Theme.PAD.shell
    local gap = Theme.PAD.gap

    local frame = CreateFrame("Frame", options.name, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER", 0, 0)
    frame:SetFrameStrata(options.strata or "HIGH")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    -- Named frames participate in Blizzard layout cache; SavedVariables own position.
    if frame.SetDontSavePosition then
        frame:SetDontSavePosition(true)
    end
    if frame.SetUserPlaced then
        frame:SetUserPlaced(false)
    end
    frame:Hide()
    Theme.Apply(frame, "window")
    if Theme.DecorateWindow then
        Theme.DecorateWindow(frame, { headerHeight = 32, inset = 6 })
    end

    -- ESC closes via Blizzard CloseSpecialWindows when frame has a global name.
    if options.name and options.closeOnEscape ~= false then
        local already
        for i = 1, #UISpecialFrames do
            if UISpecialFrames[i] == options.name then
                already = true
                break
            end
        end
        if not already then
            tinsert(UISpecialFrames, options.name)
        end
    end

    local titleFS = frame:CreateFontString(nil, "OVERLAY", Theme.FONT.title)
    titleFS:SetText(options.title or "")
    local g = Theme.COLORS.goldRaw
    titleFS:SetTextColor(g.r, g.g, g.b)
    titleFS:SetPoint("TOP", frame, "TOP", 0, Theme.PAD.titleY)

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Drag: prefer PanelDragBar when available, else whole frame.
    -- Callers may set frame._onDragStop via Window / shell after Create.
    local function FireDragStop()
        if type(frame._onDragStop) == "function" then
            frame._onDragStop(frame)
        end
    end

    if Lib.HasPanelDragBar() then
        local drag = CreateFrame("Frame", nil, frame, "PanelDragBarTemplate")
        drag:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
        drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -140, -8)
        drag:SetHeight(24)
        if PanelDragBarMixin and PanelDragBarMixin.Init then
            PanelDragBarMixin.Init(drag, frame)
        end
        if drag.SetOnDragStopCallback then
            drag:SetOnDragStopCallback(function()
                FireDragStop()
                return true -- continue StopMovingOrSizing
            end)
        else
            drag:HookScript("OnDragStop", FireDragStop)
        end
        frame.DragBar = drag
    else
        if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            FireDragStop()
        end)
    end

    local sidebar, content
    if sidebarWidth and sidebarWidth > 0 then
        sidebar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        sidebar:SetWidth(sidebarWidth)
        sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -42)
        sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
        Theme.Apply(sidebar, "surface")

        content = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", gap, 0)
        content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
        Theme.Apply(content, "surface")
    else
        content = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        content:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -42)
        content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
        Theme.Apply(content, "surface")
    end

    if options.resizable ~= false then
        Resize.Attach(frame, {
            minWidth = options.minWidth,
            minHeight = options.minHeight,
            maxWidth = options.maxWidth,
            maxHeight = options.maxHeight,
            defaultWidth = width,
            defaultHeight = height,
            allowShrink = options.allowShrink,
            onSizeChanged = options.onSizeChanged,
            onResizeStop = options.onResizeStop,
        })
    end

    local minimizeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    minimizeBtn:SetSize(24, 20)
    minimizeBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    minimizeBtn:SetText("_")

    local popoutBtn
    if type(options.onPopout) == "function" then
        popoutBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        popoutBtn:SetSize(88, 20)
        popoutBtn:SetPoint("RIGHT", minimizeBtn, "LEFT", -4, 0)
        popoutBtn:SetText(options.popoutText or "Мини-окно")
        popoutBtn:SetScript("OnClick", function()
            options.onPopout()
        end)
        if popoutBtn.SetScript then
            popoutBtn:HookScript("OnEnter", function(self)
                if not GameTooltip or not GameTooltip.SetOwner then return end
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:AddLine("Открыть раздел в компактном окне", 1, 0.82, 0)
                GameTooltip:AddLine("Удобно для маппинга и ведения сцен без большого окна.", 0.85, 0.85, 0.85, true)
                GameTooltip:Show()
            end)
            popoutBtn:HookScript("OnLeave", function()
                if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
            end)
        end
    end

    local shell = {
        frame = frame,
        titleFS = titleFS,
        closeBtn = closeBtn,
        minimizeBtn = minimizeBtn,
        popoutBtn = popoutBtn,
        sidebar = sidebar,
        content = content,
        minimized = false,
        expandedHeight = height,
    }

    function shell:SetMinimized(minimized)
        minimized = minimized and true or false
        if self.minimized == minimized then return end
        local top = frame.GetTop and frame:GetTop()
        local left = frame.GetLeft and frame:GetLeft()
        if minimized then
            self.expandedHeight = frame:GetHeight() or height
            self.minimized = true
            if sidebar then sidebar:Hide() end
            if content then content:Hide() end
            if frame._nnResizeGrip then frame._nnResizeGrip:Hide() end
            frame:SetHeight(38)
            minimizeBtn:SetText("+")
        else
            self.minimized = false
            frame:SetHeight(self.expandedHeight or height)
            if sidebar then sidebar:Show() end
            if content then content:Show() end
            if frame._nnResizeGrip then frame._nnResizeGrip:Show() end
            minimizeBtn:SetText("_")
        end
        if left and top and UIParent and UIParent.GetLeft and UIParent.GetTop then
            local pLeft = UIParent:GetLeft() or 0
            local pTop = UIParent:GetTop() or 0
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left - pLeft, top - pTop)
        end
    end

    function shell:IsMinimized()
        return self.minimized == true
    end

    minimizeBtn:SetScript("OnClick", function()
        shell:SetMinimized(not shell:IsMinimized())
    end)

    function shell:SetTitle(text)
        titleFS:SetText(text or "")
    end

    function shell:GetContent()
        return content
    end

    function shell:GetSidebar()
        return sidebar
    end

    function shell:Show()
        frame:Show()
    end

    function shell:Hide()
        frame:Hide()
    end

    function shell:SetShown(shown)
        frame:SetShown(shown and true or false)
    end

    function shell:IsShown()
        return frame:IsShown()
    end

    function shell:SetResizeLimits(minWidth, minHeight, maxWidth, maxHeight, allowShrink)
        Resize.UpdateLimits(frame, {
            minWidth = minWidth,
            minHeight = minHeight,
            maxWidth = maxWidth,
            maxHeight = maxHeight,
            allowShrink = allowShrink,
            defaultWidth = options.defaultWidth or width,
            defaultHeight = options.defaultHeight or height,
        })
    end

    return shell
end

--- Create a compact Epsilon-style floating mini-window with minimize/dock support.
--- options:
---   name, title, icon, width, height, strata, closeOnEscape,
---   headerButtonText, headerButtonTooltip, onHeaderButton, onClose, onShow
function Window.CreateMini(options)
    options = options or {}
    local width = options.width or 300
    local height = options.height or 380

    local frame = CreateFrame("Frame", options.name, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint(options.point or "CENTER", UIParent, options.relativePoint or "CENTER", options.x or 0, options.y or 0)
    if frame.SetFrameStrata then frame:SetFrameStrata(options.strata or "HIGH") end
    if frame.SetToplevel then frame:SetToplevel(true) end
    if frame.EnableMouse then frame:EnableMouse(true) end
    if frame.SetMovable then frame:SetMovable(true) end
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    if frame.SetUserPlaced then frame:SetUserPlaced(false) end
    frame:Hide()

    Theme.Apply(frame, "miniWindow")
    if Theme.DecorateWindow then
        Theme.DecorateWindow(frame, { headerHeight = 26, inset = 3 })
    end

    if options.name and options.closeOnEscape then
        local already
        for i = 1, #UISpecialFrames do
            if UISpecialFrames[i] == options.name then
                already = true
                break
            end
        end
        if not already then
            tinsert(UISpecialFrames, options.name)
        end
    end

    local iconTex
    if options.icon and frame.CreateTexture then
        iconTex = frame:CreateTexture(nil, "ARTWORK")
        if iconTex.SetSize then iconTex:SetSize(16, 16) end
        if iconTex.SetPoint then iconTex:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -7) end
        if iconTex.SetTexture then iconTex:SetTexture(options.icon) end
        if iconTex.SetTexCoord then iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end

    local titleFS = frame:CreateFontString(nil, "OVERLAY", Theme.FONT.normal)
    titleFS:SetText(options.title or "")
    local g = Theme.COLORS.goldRaw
    titleFS:SetTextColor(g.r, g.g, g.b)
    titleFS:SetJustifyH("LEFT")
    if titleFS.SetWordWrap then titleFS:SetWordWrap(false) end
    titleFS:SetPoint("TOPLEFT", frame, "TOPLEFT", options.icon and 28 or 10, -8)

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)

    local minimizeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    minimizeBtn:SetSize(20, 18)
    minimizeBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    minimizeBtn:SetText("_")

    local headerBtn
    if options.headerButtonText and type(options.onHeaderButton) == "function" then
        headerBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        headerBtn:SetSize(options.headerButtonWidth or 62, 18)
        headerBtn:SetPoint("RIGHT", minimizeBtn, "LEFT", -3, 0)
        headerBtn:SetText(options.headerButtonText)
        headerBtn:SetScript("OnClick", options.onHeaderButton)
        if options.headerButtonTooltip and headerBtn.HookScript then
            headerBtn:HookScript("OnEnter", function(self)
                if not GameTooltip or not GameTooltip.SetOwner then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(options.headerButtonTooltip, 1, 0.82, 0, true)
                GameTooltip:Show()
            end)
            headerBtn:HookScript("OnLeave", function()
                if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
            end)
        end
        titleFS:SetPoint("RIGHT", headerBtn, "LEFT", -4, 0)
    else
        titleFS:SetPoint("RIGHT", minimizeBtn, "LEFT", -4, 0)
    end

    local body = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -31)
    body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
    Theme.Apply(body, "surface")

    local mini = {
        frame = frame,
        body = body,
        titleFS = titleFS,
        iconTex = iconTex,
        closeBtn = closeBtn,
        minimizeBtn = minimizeBtn,
        headerBtn = headerBtn,
        minimized = false,
        expandedHeight = height,
        userMoved = false,
    }

    local function FireDragStop()
        mini.userMoved = true
        local top = frame.GetTop and frame:GetTop()
        local left = frame.GetLeft and frame:GetLeft()
        if left and top and UIParent and UIParent.GetLeft and UIParent.GetTop then
            local pLeft = UIParent:GetLeft() or 0
            local pTop = UIParent:GetTop() or 0
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left - pLeft, top - pTop)
        end
        if type(options.onDragStop) == "function" then
            options.onDragStop(mini)
        end
    end

    if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
    frame:SetScript("OnMouseDown", function(self)
        if self.Raise then self:Raise() end
    end)
    frame:SetScript("OnDragStart", function(self)
        if self.Raise then self:Raise() end
        if self.StartMoving then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        if self.StopMovingOrSizing then self:StopMovingOrSizing() end
        FireDragStop()
    end)

    closeBtn:SetScript("OnClick", function()
        frame:Hide()
        if type(options.onClose) == "function" then
            options.onClose(mini)
        end
    end)

    if type(options.onShow) == "function" then
        frame:HookScript("OnShow", function()
            options.onShow(mini)
        end)
    end

    function mini:SetMinimized(minimized)
        minimized = minimized and true or false
        if self.minimized == minimized then return end
        local top = frame.GetTop and frame:GetTop()
        local left = frame.GetLeft and frame:GetLeft()
        if minimized then
            self.expandedHeight = frame:GetHeight() or height
            self.minimized = true
            body:Hide()
            frame:SetHeight(30)
            minimizeBtn:SetText("+")
        else
            self.minimized = false
            frame:SetHeight(self.expandedHeight or height)
            body:Show()
            minimizeBtn:SetText("_")
        end
        if left and top and UIParent and UIParent.GetLeft and UIParent.GetTop then
            local pLeft = UIParent:GetLeft() or 0
            local pTop = UIParent:GetTop() or 0
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left - pLeft, top - pTop)
        end
    end

    function mini:IsMinimized()
        return self.minimized == true
    end

    minimizeBtn:SetScript("OnClick", function()
        mini:SetMinimized(not mini:IsMinimized())
    end)

    function mini:SetTitle(text)
        titleFS:SetText(text or "")
    end

    function mini:GetContent()
        return body
    end

    function mini:Show()
        frame:Show()
        if frame.Raise then frame:Raise() end
    end

    function mini:Hide()
        frame:Hide()
    end

    function mini:SetShown(shown)
        if shown then self:Show() else self:Hide() end
    end

    function mini:IsShown()
        return frame:IsShown()
    end

    function mini:Toggle()
        if self:IsShown() then
            self:Hide()
            return false
        end
        self:Show()
        return true
    end

    function mini:DockTo(anchorFrame, side, offsetX, offsetY)
        if self.userMoved or not anchorFrame then return end
        local target = anchorFrame.frame or anchorFrame
        side = side or "RIGHT"
        offsetX = offsetX or 6
        offsetY = offsetY or 0
        frame:ClearAllPoints()
        if side == "LEFT" then
            frame:SetPoint("TOPRIGHT", target, "TOPLEFT", -math.abs(offsetX), offsetY)
        elseif side == "BOTTOM" then
            frame:SetPoint("TOPLEFT", target, "BOTTOMLEFT", offsetX, -math.abs(offsetY ~= 0 and offsetY or 6))
        else
            local right = target.GetRight and target:GetRight()
            local screenW = UIParent and UIParent.GetWidth and UIParent:GetWidth()
            if right and screenW and (right + width + 16 > screenW) then
                frame:SetPoint("TOPRIGHT", target, "TOPLEFT", -math.abs(offsetX), offsetY)
            else
                frame:SetPoint("TOPLEFT", target, "TOPRIGHT", math.abs(offsetX), offsetY)
            end
        end
    end

    return mini
end
