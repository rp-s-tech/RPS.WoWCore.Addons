local ns = LibStub("NobleNextLib-1.0").Runtime
local Launcher = {}
ns.MinimapLauncher = Launcher
local SIZE, EDGE, VERSION = 36, 6, 1
local create

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function inCombat() return InCombatLockdown and InCombatLockdown() end

local function settings()
    NobleNextDB = type(NobleNextDB) == "table" and NobleNextDB or {}
    NobleNextDB.ui = type(NobleNextDB.ui) == "table" and NobleNextDB.ui or {}
    local ui = NobleNextDB.ui
    local data = ui.launcher
    if type(data) ~= "table" or data.version ~= VERSION then
        -- Intentional one-time migration: every old rim position becomes docked.
        data = {version=VERSION, mode="docked", leftClickMode="shell"}
        ui.launcher = data
        ui.minimapAngle, ui.minimapCustomPos, ui.minimapPos = nil, nil, nil
    end
    data.leftClickMode = nil
    data.iconScale = finite(data.iconScale) and math.max(1, math.min(3, data.iconScale)) or 2
    local pos = data.customPos
    if data.mode ~= "custom" or type(pos) ~= "table" or not finite(pos.x) or not finite(pos.y) then
        data.mode, data.customPos = "docked", nil
    end
    return data
end

function Launcher:ClampPosition(x, y)
    local scale = self.button:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local halfW = self.button:GetWidth() * scale / 2 + EDGE
    local halfH = self.button:GetHeight() * scale / 2 + EDGE
    return math.max(halfW, math.min(UIParent:GetWidth() - halfW, x)),
        math.max(halfH, math.min(UIParent:GetHeight() - halfH, y))
end

function Launcher:ApplyPosition()
    if not self.button then return end
    local button, data = self.button, self.db
    button:ClearAllPoints()
    if data.mode == "custom" then
        local x, y = self:ClampPosition(data.customPos.x, data.customPos.y)
        data.customPos.x, data.customPos.y = x, y
        button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    else
        button:SetPoint("TOP", Minimap, "BOTTOM", 0, -14)
    end
end

function Launcher:CloseFlyout() if self.flyout then self.flyout:Hide() end end
function Launcher:IsFlyoutShown() return self.flyout and self.flyout:IsShown() or false end
function Launcher:ToggleFlyout()
    if not self.button or self:IsEditMode() then return false end
    if ns.CloseQuickContextMenu then ns.CloseQuickContextMenu() end
    if self:IsFlyoutShown() then self:CloseFlyout(); return false end
    self.flyout = self.flyout or ns.CreateQuickFlyoutBar(self.button)
    return self.flyout:Open()
end
function Launcher:GetIconScale() return self.db and self.db.iconScale or 2 end
function Launcher:SetIconScale(value)
    if not self.db or not finite(value) or inCombat() then return false end
    self.db.iconScale = math.max(1, math.min(3, value))
    self.button:SetSize(SIZE * self.db.iconScale, SIZE * self.db.iconScale)
    self.button.Art:SetScale(self.db.iconScale)
    self:CloseFlyout()
    self:ApplyPosition()
    if ns.LauncherEditMode then ns.LauncherEditMode:NotifyChanged() end
    return true
end
function Launcher:OpenSettings()
    if ns.LauncherEditMode then return ns.LauncherEditMode:OpenSettings() end
    return false
end
function Launcher:IsEditMode() return self.editing == true end
function Launcher:IsLocked() return not self:IsEditMode() end

function Launcher:UpdateDragging()
    if not self.dragging then return end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    x, y = x / scale - self.dragOffsetX, y / scale - self.dragOffsetY
    if not finite(x) or not finite(y) then return end
    x, y = self:ClampPosition(x, y)
    self.dragX, self.dragY = x, y
    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
end

function Launcher:StopDragging(commit)
    if not self.dragging then
        self.dragOffsetX, self.dragOffsetY = nil, nil
        return
    end
    -- A fast release may arrive before another OnUpdate frame.
    if commit and not inCombat() then self:UpdateDragging() end
    self.dragging = false
    self.button:SetScript("OnUpdate", nil)
    if commit and not inCombat() and self.dragX and self.dragY then
        self.db.mode = "custom"
        self.db.customPos = {x=self.dragX, y=self.dragY}
    end
    self.dragX, self.dragY = nil, nil
    self.dragOffsetX, self.dragOffsetY = nil, nil
    self:ApplyPosition()
    if commit and ns.LauncherEditMode then ns.LauncherEditMode:NotifyChanged() end
    self.ignoreClickUntil = GetTime() + 0.1
end

function Launcher:SetEditMode(enabled)
    if enabled and (not self.button or inCombat() or not self.nativeEditActive) then return false end
    self.editing = enabled == true
    self:CloseFlyout()
    if not self.editing then self:StopDragging(false) end
    if self.button then self.button.EditGlow:SetShown(self.editing and not (ns.LauncherEditMode and ns.LauncherEditMode.selection)) end
    return true
end
function Launcher:ResetPosition()
    if inCombat() then return false end
    if not self.button then create() end
    if not self.button then return false end
    self:StopDragging(false)
    self.db.mode, self.db.customPos = "docked", nil
    self:CloseFlyout()
    self:ApplyPosition()
    -- Reset is also the recovery path for a hidden launcher, not only its anchor.
    self.button:SetAlpha(1)
    self.button:Show()
    if ns.LauncherEditMode then ns.LauncherEditMode:NotifyChanged() end
    return true
end
function ns.ResetMinimapButtonPosition() return Launcher:ResetPosition() end

create = function()
    if Launcher.button or not Minimap then return end
    Launcher.db = settings()
    local button = CreateFrame("Button", "NobleNextMinimapButton", UIParent)
    Launcher.button, ns._minimapButton = button, button
    button:SetSize(SIZE * Launcher.db.iconScale, SIZE * Launcher.db.iconScale)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(100)
    button:SetClampedToScreen(true)
    button:SetClampRectInsets(-EDGE, EDGE, EDGE, -EDGE)
    button:SetDontSavePosition(true)
    button:SetMovable(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    button.Art = CreateFrame("Frame", nil, button)
    button.Art:SetSize(SIZE, SIZE)
    button.Art:SetPoint("CENTER")
    button.Art:SetScale(Launcher.db.iconScale)
    button.Icon = ns.CreateLauncherIcon(button.Art, "Interface\\AddOns\\NobleNext\\Assets\\Logo", true)
    local glow = button:CreateTexture(nil, "OVERLAY")
    glow:SetAllPoints()
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(0.2, 0.8, 1, 0.9)
    glow:Hide()
    button.EditGlow = glow
    Launcher:ApplyPosition()

    local function captureGrabOffset()
        local cx, cy = button:GetCenter()
        if not cx or not cy then return end
        local scale = UIParent:GetEffectiveScale()
        local factor = button:GetEffectiveScale() / scale
        local cursorX, cursorY = GetCursorPosition()
        Launcher.dragOffsetX, Launcher.dragOffsetY = cursorX / scale - cx * factor, cursorY / scale - cy * factor
    end
    button:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        Launcher.dragOffsetX, Launcher.dragOffsetY = nil, nil
        if not Launcher:IsLocked() and not inCombat() then captureGrabOffset() end
    end)
    button:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "LeftButton" and not Launcher.dragging then
            Launcher.dragOffsetX, Launcher.dragOffsetY = nil, nil
        end
    end)
    button:SetScript("OnDragStart", function()
        if Launcher:IsLocked() or inCombat() then return end
        -- The cursor can already have crossed the screen by OnDragStart.
        -- Preserve where the original press grabbed the icon instead.
        if not Launcher.dragOffsetX or not Launcher.dragOffsetY then captureGrabOffset() end
        if not Launcher.dragOffsetX or not Launcher.dragOffsetY then return end
        Launcher.dragging = true
        GameTooltip:Hide()
        Launcher:UpdateDragging()
        button:SetScript("OnUpdate", function()
            if inCombat() then Launcher:SetEditMode(false); return end
            Launcher:UpdateDragging()
        end)
    end)
    button:SetScript("OnDragStop", function() Launcher:StopDragging(true) end)
    button:SetScript("OnHide", function() Launcher:SetEditMode(false) end)
    button:SetScript("OnClick", function(_, mouseButton)
        if Launcher.ignoreClickUntil and GetTime() < Launcher.ignoreClickUntil then return end
        if Launcher:IsEditMode() then
            Launcher:OpenSettings()
        elseif mouseButton == "RightButton" then
            Launcher:ToggleFlyout()
        elseif mouseButton == "LeftButton" then
            Launcher:CloseFlyout()
            if IsShiftKeyDown() then ns.OpenQuickContextMenu(button)
            else ns.ToggleMainFrame() end
        end
    end)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(button, "ANCHOR_LEFT")
        GameTooltip:AddLine("NobleNext", 1, 0.82, 0)
        if Launcher:IsEditMode() then
            GameTooltip:AddLine("Перетащите значок; нажмите для настройки", 1, 1, 1)
            GameTooltip:AddLine("Сохранение и отмена — в режиме редактирования WoW.", 0.8, 0.8, 0.8)
        else
            GameTooltip:AddLine("ЛКМ — открыть NobleNext", 1, 1, 1)
            GameTooltip:AddLine("Shift + ЛКМ — все действия и настройки", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("ПКМ — выбранные быстрые действия", 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Minimap:HookScript("OnSizeChanged", function() if Launcher.db.mode == "docked" then Launcher:ApplyPosition() end end)
end

local hookedGameMenu
local function hookGameMenu()
    local menu = _G.GameMenuFrame
    if not menu or menu == hookedGameMenu then return end
    menu:HookScript("OnShow", function() Launcher:SetEditMode(false) end)
    hookedGameMenu = menu
end

function ns.InitializeMinimapLauncher()
    if Launcher.eventFrame then return Launcher end
    local events = CreateFrame("Frame")
    Launcher.eventFrame = events
    for _, event in ipairs({"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED"}) do events:RegisterEvent(event) end
    events:SetScript("OnEvent", function(_, event, addon)
        if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then hookGameMenu() end
        if event == "ADDON_LOADED" and addon == "NobleNext" or event == "PLAYER_LOGIN" then
            create()
        elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LOGOUT" then
            Launcher:SetEditMode(false)
            if ns.CloseQuickContextMenu then ns.CloseQuickContextMenu() end
        elseif event == "PLAYER_REGEN_ENABLED" then
            Launcher:CloseFlyout()
            if ns.CloseQuickContextMenu then ns.CloseQuickContextMenu() end
            if Launcher.nativeEditActive and EditModeManagerFrame and EditModeManagerFrame:IsShown()
                and EditModeManagerFrame:IsEditModeActive() then Launcher:SetEditMode(true) end
        elseif (event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED") and Launcher.button then
            Launcher:StopDragging(false)
            Launcher:ApplyPosition()
            if Launcher:IsFlyoutShown() then Launcher.flyout:Rebuild() end
        end
    end)
    hookGameMenu()
    if ns.InitializeLauncherEditMode then ns.InitializeLauncherEditMode(Launcher) end
    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function()
            Launcher.nativeEditActive = true
            Launcher:SetEditMode(true)
        end, Launcher)
        EventRegistry:RegisterCallback("EditMode.Exit", function()
            Launcher.nativeEditActive = false
            Launcher:SetEditMode(false)
        end, Launcher)
    end
    -- Initialization can run after PLAYER_LOGIN (for example after a late load).
    -- SavedVariables are already available then; do not wait for another login.
    if IsLoggedIn and IsLoggedIn() then create() end
    return Launcher
end
