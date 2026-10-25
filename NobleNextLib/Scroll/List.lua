local Lib = LibStub("NobleNextLib-1.0")
local Theme = Lib.Theme
local Scroll = Lib.Scroll
local SafeString = Lib.Runtime.Util.SafeString

-- Use the same wheel path over content and over the native bar. The bar's
-- controller normalizes the wheel direction and owns clamping/callbacks.
function Scroll.HandleMouseWheel(frame, delta)
    if not delta or delta == 0 then return end
    local bar = frame.ScrollBar
    if bar and bar.OnMouseWheel then
        bar:OnMouseWheel(delta)
    elseif frame._nnTemplateMouseWheel then
        frame._nnTemplateMouseWheel(frame, delta)
    end
end

-- Shared scroll-frame factory. Keep native drag, stepper, vertical-scroll and
-- range handling; route only the wheel through the bar's working controller.
function Scroll.CreateFrame(parent, name)
    local modern = ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar
    local frame = CreateFrame("ScrollFrame", name, parent,
        modern and "ScrollFrameTemplate" or "UIPanelScrollFrameTemplate")
    -- Explicitly receive wheel input over empty content as well as child rows;
    -- installing the template script alone does not enable it on every build.
    frame:EnableMouseWheel(true)
    frame._nnTemplateMouseWheel = frame:GetScript("OnMouseWheel")
    frame:SetScript("OnMouseWheel", Scroll.HandleMouseWheel)
    local bar = frame.ScrollBar
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, -2)
        bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 6, 2)
        if bar.SetHideIfUnscrollable then bar:SetHideIfUnscrollable(true) end
    end
    frame:HookScript("OnScrollRangeChanged", function(self, _, range)
        range = range or self:GetVerticalScrollRange() or 0
        if bar and not bar.SetHideIfUnscrollable then bar:SetShown(range > 0.5) end
        local offset = self:GetVerticalScroll() or 0
        if offset > range then self:SetVerticalScroll(math.max(0, range)) end
    end)
    return frame
end

local function FindScrollFrame(frame)
    local p = frame
    while p do
        if p.GetObjectType and p:GetObjectType() == "ScrollFrame" then
            return p
        end
        p = p.GetParent and p:GetParent() or nil
    end
    return nil
end

local function ResetScroll(state)
    state.offset = 0
    if state.scrollFrame and state.scrollFrame.SetVerticalScroll then
        state.scrollFrame:SetVerticalScroll(0)
    end
end

local function ClampOffset(state, total)
    -- visibleCount includes an overscan row, not the number of full rows on
    -- screen. Clamping to it leaves the final list item unrendered at the bottom.
    local height = state.scrollFrame and state.scrollFrame:GetHeight() or state.visibleCount * state.rowHeight
    local maxOffset = math.max(0, math.floor((total * state.rowHeight + 8 - height) / state.rowHeight))
    if state.offset > maxOffset then
        state.offset = maxOffset
    end
    if state.offset < 0 then
        state.offset = 0
    end
    return maxOffset
end

--- Create a virtualized / ScrollBox-backed list.
--- Compatible with legacy VirtualList API: SetRows / SetFilter / GetFiltered / Refresh
---
--- Preferred call:
---   Scroll.CreateList(parent, { rowHeight, width, onClick, renderRow, filterFn, scrollFrame })
--- Legacy call (scrollChild):
---   Scroll.CreateVirtualList(scrollChild, opts)
---
--- onClick contract: onClick(row, button) — first arg is always the row data.
function Scroll.CreateVirtualList(scrollChild, opts)
    opts = opts or {}
    local state = {
        child = scrollChild,
        rowHeight = opts.rowHeight or 22,
        visibleCount = opts.visibleCount or 18,
        width = opts.width or 580,
        buttons = {},
        rows = {},
        filter = "",
        onClick = opts.onClick,
        renderRow = opts.renderRow,
        filterFn = opts.filterFn,
        offset = 0,
        scrollFrame = opts.scrollFrame or FindScrollFrame(scrollChild),
        _scrollHooked = false,
    }

    local function ensureButtons(count)
        count = count or state.visibleCount
        for i = 1, count do
            if not state.buttons[i] then
                local btn = CreateFrame("Button", nil, state.child, "BackdropTemplate")
                btn:SetSize(state.width, state.rowHeight)
                Theme.Apply(btn, "row")
                state.buttons[i] = btn
            else
                state.buttons[i]:SetWidth(state.width)
            end
        end
        for i = count + 1, #state.buttons do
            state.buttons[i]:Hide()
        end
    end

    local function ensureScrollHooks()
        if state._scrollHooked or not state.scrollFrame then
            return
        end
        state._scrollHooked = true
        state.scrollFrame:HookScript("OnSizeChanged", function()
            state:Refresh()
        end)
        state.scrollFrame:HookScript("OnVerticalScroll", function(_, offset)
            state.offset = math.floor((offset or 0) / state.rowHeight)
            state:Refresh()
        end)
    end

    function state:SetViewport(width, height)
        if width and width > 0 then
            self.width = math.floor(width)
        end
        if height and height > 0 then
            self.visibleCount = math.max(3, math.ceil(height / self.rowHeight) + 1)
        end
        self:Refresh()
    end

    function state:SetRows(rows)
        self.rows = rows or {}
        ResetScroll(self)
        self:Refresh()
    end

    function state:SetFilter(text)
        self.filter = SafeString(text):lower()
        ResetScroll(self)
        self:Refresh()
    end

    function state:GetFiltered()
        if self.filter == "" then return self.rows end
        local out = {}
        for _, row in ipairs(self.rows) do
            local ok
            if self.filterFn then
                ok = self.filterFn(row, self.filter)
            else
                local hay = string.format("%s %s %s %s %s",
                    SafeString(row.id),
                    SafeString(row.name),
                    SafeString(row.desc),
                    SafeString(row.owner),
                    SafeString(row.phase, SafeString(row.guid, SafeString(row.character)))
                ):lower()
                ok = hay:find(self.filter, 1, true) ~= nil
            end
            if ok then
                table.insert(out, row)
            end
        end
        return out
    end

    function state:Refresh()
        if not self.scrollFrame then
            self.scrollFrame = FindScrollFrame(self.child)
        end
        ensureScrollHooks()

        if self.scrollFrame and self.scrollFrame.GetHeight then
            local h = self.scrollFrame:GetHeight()
            if h and h > 0 then
                self.visibleCount = math.max(3, math.ceil(h / self.rowHeight) + 1)
            end
            local w = self.scrollFrame:GetWidth()
            if w and w > 20 then
                self.width = math.floor(w - 4)
            end
        end

        ensureButtons(self.visibleCount)
        local filtered = self:GetFiltered()
        local total = #filtered
        ClampOffset(self, total)
        self.child:SetHeight(math.max(24, total * self.rowHeight + 8))

        for i = 1, self.visibleCount do
            local btn = self.buttons[i]
            local rowIndex = self.offset + i
            local row = filtered[rowIndex]
            if row then
                btn:Show()
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", self.child, "TOPLEFT", 2, -4 - (rowIndex - 1) * self.rowHeight)
                btn:SetWidth(self.width)
                if self.renderRow then
                    self.renderRow(btn, row)
                end
                btn:SetScript("OnClick", function(_, mouseButton)
                    if self.onClick then
                        self.onClick(row, mouseButton)
                    end
                end)
            else
                btn:Hide()
            end
        end
    end

    ensureScrollHooks()
    return state
end

function Scroll.CreateList(parent, options)
    options = options or {}
    local host = CreateFrame("Frame", options.name, parent)
    if options.fill then
        Lib.Layout.Fill(host, parent)
    elseif options.width and options.height then
        host:SetSize(options.width, options.height)
    end

    local scroll = Scroll.CreateFrame(host)
    scroll:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -18, 0)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(1)
    child:SetHeight(1)
    scroll:SetScrollChild(child)

    local list = Scroll.CreateVirtualList(child, {
        rowHeight = options.rowHeight,
        width = options.width,
        onClick = options.onClick,
        renderRow = options.renderRow,
        filterFn = options.filterFn,
        visibleCount = options.visibleCount,
        scrollFrame = scroll,
    })

    host.Scroll = scroll
    host.Child = child
    host.List = list
    host.SetRows = function(_, rows) list:SetRows(rows) end
    host.SetFilter = function(_, text) list:SetFilter(text) end
    host.Refresh = function() list:Refresh() end

    host:HookScript("OnSizeChanged", function(_, w)
        if w and w > 40 then
            child:SetWidth(w - 18)
            list:SetViewport(w - 22, host:GetHeight())
        end
    end)

    return host
end
