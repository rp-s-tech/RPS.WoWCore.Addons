local Lib = LibStub("NobleNextLib-1.0")
local Theme = Lib.Theme
local Navigation = Lib.Navigation
local SafeString = Lib.Runtime.Util.SafeString

local ROW_HEIGHT = 40
local ROW_GAP = 8

local function CreateSidebarButton(parent, item)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize((parent:GetWidth() or 140) - 12, ROW_HEIGHT)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp")
    Theme.Apply(btn, "tab")

    if item.icon then
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(item.icon)
        if icon.SetTexCoord then
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        icon:SetSize(22, 22)
        icon:SetPoint("LEFT", btn, "LEFT", 8, 0)
        btn.Icon = icon
    end

    -- BackdropTemplate Button has no default FontString; create one explicitly.
    local fs = btn:CreateFontString(nil, "OVERLAY", Theme.FONT.normal)
    btn:SetFontString(fs)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", btn, "LEFT", item.icon and 36 or 12, 0)
    fs:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    btn:SetText(SafeString(item.title, SafeString(item.label, SafeString(item.id, "?"))))

    btn.itemId = item.id
    btn.item = item
    return btn
end

local function ApplySelected(btn, selected)
    if selected then
        Theme.Apply(btn, "tabSelected")
        local fs = btn:GetFontString()
        if fs then fs:SetTextColor(1, 0.9, 0.7) end
    else
        Theme.Apply(btn, "tab")
        local fs = btn:GetFontString()
        if fs then fs:SetTextColor(0.75, 0.75, 0.75) end
    end
end

--- Create a fixed-width scrollable sidebar.
--- options: { width=180, onSelect=fn(id, item), items=? }
function Navigation.CreateSidebar(parent, options)
    options = options or {}
    local width = options.width or Theme.PAD.sidebarWidth or 180

    local root = CreateFrame("Frame", options.name, parent, "BackdropTemplate")
    root:SetWidth(width)
    Theme.Apply(root, "surface")

    local scroll = Lib.Scroll.CreateFrame(root)
    scroll:SetPoint("TOPLEFT", root, "TOPLEFT", 4, -6)
    scroll:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -20, 10)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(math.max(1, width - 24))
    child:SetHeight(1)
    scroll:SetScrollChild(child)

    root.Scroll = scroll
    root.Child = child
    root.buttons = {}
    root.headers = {}
    root.items = {}
    root.selectedId = nil
    root.onSelect = options.onSelect
    root.onSecondarySelect = options.onSecondarySelect

    local function Relayout()
        for _, hdr in ipairs(root.headers) do
            hdr:Hide()
        end
        local headerIdx = 0
        local y = -4
        local lastGroup
        for _, btn in ipairs(root.buttons) do
            local item = btn.item
            if item.group and item.group ~= lastGroup and item.groupLabel then
                headerIdx = headerIdx + 1
                local hdr = root.headers[headerIdx]
                if not hdr then
                    hdr = child:CreateFontString(nil, "OVERLAY", Theme.FONT.small or Theme.FONT.normal)
                    if hdr.SetJustifyH then hdr:SetJustifyH("LEFT") end
                    if hdr.SetTextColor then hdr:SetTextColor(0.95, 0.78, 0.25) end
                    root.headers[headerIdx] = hdr
                end
                hdr:ClearAllPoints()
                hdr:SetPoint("TOPLEFT", child, "TOPLEFT", 8, y - 2)
                hdr:SetText(SafeString(item.groupLabel))
                hdr:Show()
                y = y - 18
                lastGroup = item.group
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", 4, y)
            btn:SetWidth(math.max(1, child:GetWidth() - 8))
            y = y - (ROW_HEIGHT + ROW_GAP)
        end
        child:SetHeight(math.max(1, -y - ROW_GAP + 12))
    end

    local function UpdateSelection()
        for _, btn in ipairs(root.buttons) do
            ApplySelected(btn, btn.itemId == root.selectedId)
        end
    end

    local function ScrollButtonIntoView(btn)
        if not btn then
            return
        end
        local point, _, _, _, yOfs = btn:GetPoint(1)
        if not point or yOfs == nil then
            return
        end
        local top = -yOfs
        local cur = scroll:GetVerticalScroll() or 0
        local viewH = scroll:GetHeight() or 0
        if viewH <= 0 then
            return
        end
        if top < cur then
            scroll:SetVerticalScroll(math.max(0, top - 8))
        elseif top + ROW_HEIGHT > cur + viewH then
            scroll:SetVerticalScroll(math.max(0, top + ROW_HEIGHT - viewH + 8))
        end
    end

    function root:SetItems(items)
        for _, btn in ipairs(self.buttons) do
            btn:Hide()
            btn:SetParent(nil)
        end
        wipe(self.buttons)
        self.items = items or {}

        for _, item in ipairs(self.items) do
            local btn = CreateSidebarButton(child, item)
            -- Use the same native bar controller over a button as over its bar.
            btn:EnableMouseWheel(true)
            btn:SetScript("OnMouseWheel", function(_, delta)
                Lib.Scroll.HandleMouseWheel(scroll, delta)
            end)
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:SetScript("OnClick", function(selfBtn, mouseButton)
                if mouseButton == "RightButton" and root.onSecondarySelect then
                    root.onSecondarySelect(selfBtn.itemId, item)
                    return
                end
                root:Select(selfBtn.itemId)
            end)
            btn:SetScript("OnEnter", function(selfBtn)
                GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
                GameTooltip:AddLine(SafeString(item.title, SafeString(item.id)), 1, 0.82, 0)
                local tooltip, slash = SafeString(item.tooltip), SafeString(item.slash)
                if tooltip ~= "" then
                    GameTooltip:AddLine(tooltip, 0.8, 0.8, 0.8, true)
                end
                if slash ~= "" then
                    GameTooltip:AddLine(slash, 0.55, 0.75, 0.95)
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            table.insert(self.buttons, btn)
        end
        Relayout()
        UpdateSelection()
    end

    function root:Select(id, silent)
        self.selectedId = id
        UpdateSelection()

        local selectedBtn
        for _, btn in ipairs(self.buttons) do
            if btn.itemId == id then
                selectedBtn = btn
                break
            end
        end
        -- Scroll is best-effort and must never block module switch.
        pcall(ScrollButtonIntoView, selectedBtn)

        if not silent and self.onSelect then
            local item
            for _, it in ipairs(self.items) do
                if it.id == id then
                    item = it
                    break
                end
            end
            self.onSelect(id, item)
        end
    end

    function root:AddOrUpdateItem(item)
        local found
        for i, it in ipairs(self.items) do
            if it.id == item.id then
                self.items[i] = item
                found = true
                break
            end
        end
        if not found then
            table.insert(self.items, item)
        end
        table.sort(self.items, function(a, b)
            local ga = a.groupOrder or 50
            local gb = b.groupOrder or 50
            if ga ~= gb then return ga < gb end
            local oa = a.order or 500
            local ob = b.order or 500
            if oa ~= ob then return oa < ob end
            return tostring(a.id) < tostring(b.id)
        end)
        self:SetItems(self.items)
    end

    if options.items then
        root:SetItems(options.items)
    end
    root:HookScript("OnSizeChanged", function(_, w)
        child:SetWidth(math.max(1, w - 24))
        Relayout()
    end)

    return root
end
