local Lib = LibStub("NobleNextLib-1.0")
local Resize = Lib.Resize

local function Clamp(v, minV, maxV)
    if minV and v < minV then v = minV end
    if maxV and v > maxV then v = maxV end
    return v
end

--- Attach SE resize behavior.
--- options: minWidth, minHeight, maxWidth, maxHeight, allowShrink, onSizeChanged, onResizeStop
local function ResolveLimits(options)
    options = options or {}
    local minW = options.minWidth or 780
    local minH = options.minHeight or 480
    local maxW = options.maxWidth or 1400
    local maxH = options.maxHeight or 900
    if not options.allowShrink then
        -- Migration mode: do not allow smaller than current default shell.
        minW = math.max(minW, options.defaultWidth or 920)
        minH = math.max(minH, options.defaultHeight or 600)
    end
    return minW, minH, maxW, maxH
end

function Resize.UpdateLimits(frame, options)
    if not frame then
        return
    end
    local minW, minH, maxW, maxH = ResolveLimits(options)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minW, minH, maxW, maxH)
    end
    local state = frame._nnResize
    if state then
        state.minWidth = minW
        state.minHeight = minH
        state.maxWidth = maxW
        state.maxHeight = maxH
        local grabber = state.grabber
        if grabber and PanelResizeButtonMixin and PanelResizeButtonMixin.Init then
            PanelResizeButtonMixin.Init(grabber, frame, minW, minH, maxW, maxH)
        end
    end
end

function Resize.Attach(frame, options)
    options = options or {}
    local minW, minH, maxW, maxH = ResolveLimits(options)

    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minW, minH, maxW, maxH)
    end

    local grabber
    if Lib.HasPanelResize() then
        grabber = CreateFrame("Button", nil, frame, "PanelResizeButtonTemplate")
        grabber:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
        if PanelResizeButtonMixin and PanelResizeButtonMixin.Init then
            PanelResizeButtonMixin.Init(grabber, frame, minW, minH, maxW, maxH)
        end
        if grabber.SetOnResizeStoppedCallback then
            grabber:SetOnResizeStoppedCallback(function()
                if options.onResizeStop then
                    options.onResizeStop(frame:GetWidth(), frame:GetHeight())
                end
            end)
        end
    else
        grabber = CreateFrame("Button", nil, frame)
        grabber:SetSize(16, 16)
        grabber:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
        local tex = grabber:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grabber:SetNormalTexture(tex)
        grabber:SetScript("OnMouseDown", function()
            frame:StartSizing("BOTTOMRIGHT")
        end)
        grabber:SetScript("OnMouseUp", function()
            frame:StopMovingOrSizing()
            local state = frame._nnResize or {}
            local w = Clamp(frame:GetWidth(), state.minWidth or minW, state.maxWidth or maxW)
            local h = Clamp(frame:GetHeight(), state.minHeight or minH, state.maxHeight or maxH)
            frame:SetSize(w, h)
            if options.onResizeStop then
                options.onResizeStop(w, h)
            end
        end)
    end

    -- Single dispatcher: do not overwrite existing OnSizeChanged blindly.
    frame:HookScript("OnSizeChanged", function(self, w, h)
        local state = self._nnResize or {}
        w = Clamp(w or self:GetWidth(), state.minWidth or minW, state.maxWidth or maxW)
        h = Clamp(h or self:GetHeight(), state.minHeight or minH, state.maxHeight or maxH)
        if options.onSizeChanged then
            options.onSizeChanged(w, h)
        end
    end)

    frame._nnResize = {
        grabber = grabber,
        minWidth = minW,
        minHeight = minH,
        maxWidth = maxW,
        maxHeight = maxH,
    }
    return grabber
end
