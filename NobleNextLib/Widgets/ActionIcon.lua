local Lib = LibStub("NobleNextLib-1.0")
local Widgets = Lib.Widgets
Lib.Icons = Lib.Icons or {}
local files = {
    Activate = true,
    Apply = true,
    Army = true,
    BackLeft = true,
    BackRight = true,
    Backward = true,
    BakeNPC = true,
    BakeObject = true,
    BakeRoute = true,
    Banner = true,
    BattleDice = true,
    Blueprint = true,
    Bookmark = true,
    Cancel = true,
    Clear = true,
    Clockwise = true,
    Combat = true,
    Compass = true,
    Counterclockwise = true,
    Crystal = true,
    Delete = true,
    Down = true,
    Dragon = true,
    Duplicate = true,
    Equipment = true,
    Eye = true,
    FavoriteAdd = true,
    FavoriteRemove = true,
    Forward = true,
    ForwardLeft = true,
    ForwardRight = true,
    Gears = true,
    Group = true,
    Info = true,
    Inspect = true,
    Left = true,
    Link = true,
    Lock = true,
    Mannequin = true,
    Map = true,
    MapPin = true,
    NPC = true,
    ObjectGroup = true,
    PitchDown = true,
    PitchUp = true,
    Play = true,
    Portal = true,
    Pull = true,
    Radar = true,
    Replace = true,
    Reset = true,
    Right = true,
    Rings = true,
    RollLeft = true,
    RollRight = true,
    Route = true,
    Rulebook = true,
    Run = true,
    ScaleDown = true,
    ScaleUp = true,
    Search = true,
    Select = true,
    ServerRemove = true,
    Settings = true,
    Spawn = true,
    SpawnTemporary = true,
    Stop = true,
    Talk = true,
    Teleport = true,
    Tools = true,
    Treasure = true,
    Up = true,
    Wait = true,
    Walk = true,
    Whistle = true,
}

function Lib.Icons.Get(key)
    assert(files[key], "Unknown NobleNext icon: " .. tostring(key))
    return "Interface\\AddOns\\NobleNext\\Assets\\Icons\\" .. key
end

local function RefreshActionIcon(button, pressed)
    local enabled = button:IsEnabled()
    local icon = button.ActionIcon
    icon:ClearAllPoints()
    if button.actionKeepText then icon:SetPoint("LEFT", button, "LEFT", 5, 0)
    else icon:SetPoint("CENTER", button, "CENTER", 0, 0) end
    icon:SetSize(button.actionIconSize - 4, button.actionIconSize - 4)
    icon:SetTexture(Lib.Icons.Get(button.actionIconKey))
    icon:SetTexCoord(0, 1, 0, 1)
    local tint = enabled and pressed and 0.82 or 1
    icon:SetVertexColor(tint, tint, tint)
    icon:SetDesaturated(not enabled or button.actionModeActive == false)
    icon:SetAlpha(not enabled and 0.45 or (button.actionModeActive == false and 0.35 or 1))
end

function Widgets.SetActionIcon(button, icon, options)
    options = options or {}
    local size, title, detail = options.size or 32, options.title or button:GetText(), options.detail
    button.actionKeepText = options.keepText == true
    button.actionIconSize = size
    button.actionIconKey, button.actionIconTitle, button.actionIconDetail = icon, title, detail
    if not button.actionKeepText then button:SetSize(size, size) end
    -- Keep the action label available to accessibility and UI inspection.
    local label = button.GetFontString and button:GetFontString()
    if label then
        if button.actionKeepText then
            label:ClearAllPoints()
            label:SetPoint("LEFT", button, "LEFT", size + 7, 0)
            label:SetPoint("RIGHT", button, "RIGHT", -5, 0)
        else label:Hide() end
    end
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        if button[key] and not button.actionKeepText then button[key]:Hide() end
    end
    if not button.ActionIcon then
        button.ActionIcon = button:CreateTexture(nil, "ARTWORK")
        if not button.actionKeepText then
            button:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
            button:GetNormalTexture():SetTexCoord(0.2, 0.8, 0.2, 0.8)
            button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
            button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            button:GetHighlightTexture():SetTexCoord(0, 1, 0, 1)
        end
        button.ActionActive = button:CreateTexture(nil, "OVERLAY")
        button.ActionActive:SetAllPoints(button)
        button.ActionActive:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        button.ActionActive:SetVertexColor(1, 0.82, 0)
        button.ActionActive:SetBlendMode("ADD")
        button.ActionActive:Hide()
        function button:SetActiveState(active)
            self.actionModeActive = active
            self.ActionActive:SetShown(active)
            RefreshActionIcon(self)
        end
        button:HookScript("OnMouseDown", function(self) RefreshActionIcon(self, true) end)
        for _, event in ipairs({ "OnMouseUp", "OnShow", "OnEnable", "OnDisable" }) do
            button:HookScript(event, function(self) RefreshActionIcon(self) end)
        end
        if options.title or not button:GetScript("OnEnter") then
            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.actionIconTitle, 1, 0.82, 0)
                if self.actionIconDetail then GameTooltip:AddLine(self.actionIconDetail, 0.8, 0.8, 0.8, true) end
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end
    RefreshActionIcon(button)
end

