local Lib = LibStub("NobleNextLib-1.0")
local Theme = Lib.Theme
local Tabs = Lib.Tabs

local function Utf8Len(s)
    s = tostring(s or "")
    local _, cont = s:gsub("[\128-\191]", "")
    return #s - cont
end

local function MeasureTextWidth(text)
    -- GameFontNormalSmall ~7px/glyph + pad; count UTF-8 characters, not bytes.
    local n = Utf8Len(text)
    return math.max(72, math.min(180, 20 + (n * 8)))
end

function Tabs.SetSelected(btn, selected)
    if not btn then return end
    if btn.SetBackdrop then
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
    btn._nnSelected = selected and true or false
end

function Tabs.Create(parent, text, id, onClick)
    local width = MeasureTextWidth(text)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, 26)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp")
    Theme.Apply(btn, "tab")

    -- BackdropTemplate Button has no default FontString.
    local fs = btn:CreateFontString(nil, "OVERLAY", Theme.FONT.small)
    btn:SetFontString(fs)
    fs:SetJustifyH("CENTER")
    fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn:SetText(text or "")

    btn.tabText = text
    btn.tabId = id
    btn:SetScript("OnClick", function(self)
        if onClick then onClick(self, self.tabId) end
    end)
    Tabs.SetSelected(btn, false)
    return btn
end

--- Create a horizontal tab bar.
--- tabs = { { id=, label= }, ... }
--- onSelect(id, btn)
function Tabs.CreateBar(parent, tabDefs, onSelect, options)
    options = options or {}
    local bar = CreateFrame("Frame", options.name, parent)
    bar:SetHeight(options.height or 28)
    if options.width then
        bar:SetWidth(options.width)
    else
        bar:SetPoint("LEFT", parent, "LEFT", 0, 0)
        bar:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    end

    bar.buttons = {}
    bar.selectedId = nil
    local x = options.padX or 0
    local gap = options.gap or 4

    local function Select(id)
        bar.selectedId = id
        for _, btn in ipairs(bar.buttons) do
            Tabs.SetSelected(btn, btn.tabId == id)
        end
        if onSelect then
            onSelect(id)
        end
    end

    for i, def in ipairs(tabDefs or {}) do
        local btn = Tabs.Create(bar, def.label or def[1], def.id or def[2] or i, function(_, id)
            Select(id)
        end)
        btn:SetPoint("LEFT", bar, "LEFT", x, 0)
        x = x + btn:GetWidth() + gap
        table.insert(bar.buttons, btn)
    end

    bar.Select = Select
    bar.SetSelected = function(_, id) Select(id) end
    if tabDefs and tabDefs[1] then
        Select(tabDefs[1].id or tabDefs[1][2] or 1)
    end
    return bar
end

--- Optional TabSystemOwner wrapper when SharedXML TabSystem is available.
function Tabs.CreateOwner(parent, options)
    options = options or {}
    if not Lib.HasTabSystem() then
        -- Fallback: simple bar + content frames managed by caller.
        return Tabs.CreateBar(parent, options.tabs or {}, options.onSelect, options)
    end

    local owner = CreateFrame("Frame", options.name, parent, "TabSystemOwnerTemplate")
    owner:SetSize(options.width or 200, options.height or 28)
    local tabSystem = CreateFrame("Frame", nil, owner, "TabSystemTemplate")
    tabSystem:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, 0)
    owner:SetTabSystem(tabSystem)
    if TabSystemOwnerMixin and TabSystemOwnerMixin.OnLoad then
        TabSystemOwnerMixin.OnLoad(owner)
    end

    owner._nnContents = {}
    for _, def in ipairs(options.tabs or {}) do
        local content = def.content
        local id = owner:AddNamedTab(def.label or def.id, content)
        owner._nnContents[id] = content
        if def.id then
            owner._nnContents[def.id] = content
        end
    end
    return owner
end
