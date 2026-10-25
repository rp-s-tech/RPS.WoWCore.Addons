-- Addon settings participate in the native Edit Mode transaction. They are not
-- C_EditMode systems: Blizzard only accepts its own Enum.EditModeSystem values.
local Lib = LibStub("NobleNextLib-1.0")
local ns = Lib.Runtime
local Edit = {}
ns.LauncherEditMode = Edit

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function display(value) return ns.Util.SafeString(value, "") end

function Edit:Capture()
    local data = self.launcher.db
    local ui = NobleNextDB and NobleNextDB.ui
    return {mode=data.mode, customPos=copy(data.customPos), iconScale=data.iconScale,
        quickActions=copy(ui and ui.quickActions)}
end

function Edit:Restore(snapshot)
    if not snapshot or not self.launcher.db then return end
    self.restoring = true
    local launcher, data = self.launcher, self.launcher.db
    launcher:StopDragging(false)
    data.mode, data.customPos, data.iconScale = snapshot.mode, copy(snapshot.customPos), snapshot.iconScale
    NobleNextDB.ui.quickActions = copy(snapshot.quickActions)
    -- SetIconScale intentionally rejects changes in combat. Keep the saved
    -- value restored, and apply its presentation when combat ends.
    if not launcher:SetIconScale(snapshot.iconScale) then self.restorePresentation = true end
    launcher:ApplyPosition()
    launcher:CloseFlyout()
    if ns.RefreshQuickActionPresentation then ns.RefreshQuickActionPresentation() end
    self.restoring = false
    self:RefreshControls()
end

function Edit:CanChange()
    return self.active and self.manager and self.manager:IsEditModeActive()
        and self.manager:IsShown() and not self.manager:IsEditModeLocked() and not inCombat()
end

function Edit:UpdateNativeDirty()
    if not self.manager or self.updatingDirty then return end
    self.updatingDirty = true
    -- Recompute from Blizzard's frames; never clear their unsaved changes.
    self.manager:CheckForSystemActiveChanges()
    if self.active and self.dirty then self.manager:SetHasActiveChanges(true) end
    self.updatingDirty = false
end

function Edit:NotifyChanged()
    if not self.active or self.restoring or not self.baseline then return end
    self.dirty = not equal(self.baseline, self:Capture())
    self:UpdateNativeDirty()
    self:RefreshControls()
end

function Edit:CloseSettings()
    if self.dialog then self.dialog:Hide() end
    if self.selection and self:CanChange() then self.selection:ShowHighlighted() end
end

function Edit:RefreshControls()
    if not self.dialog or not self.dialog:IsShown() or self.refreshing then return end
    self.refreshing = true
    local dialog, enabled = self.dialog, self:CanChange()
    dialog.Scale:SetValue(self.launcher:GetIconScale() * 100)
    dialog.Scale:SetEnabled(enabled)
    dialog.Reset:SetEnabled(enabled)
    local available = ns.GetAvailableQuickActions and ns.GetAvailableQuickActions() or {}
    for index, action in ipairs(available) do
        local check = dialog.checks[index]
        if not check then
            check = CreateFrame("Frame", nil, dialog.ListContent, "EditModeCheckButtonTemplate")
            check.fixedWidth, check.fixedHeight = 274, 32
            check.labelFont, check.disabledLabelFont = "GameFontHighlightMedium", "GameFontDisableMed2"
            check:SetSize(274, 32)
            check.Label:SetWidth(232)
            check:SetPoint("TOPLEFT", 0, -(index - 1) * 32)
            check:SetCallback(function(checked, isUserInput)
                if isUserInput and self:CanChange() and check.actionId then
                    ns.SetQuickActionVisible(check.actionId, checked)
                end
                self:RefreshControls()
            end)
            dialog.checks[index] = check
        end
        check.actionId = action.id
        check:SetLabelText(display(action.title))
        check.Button:SetChecked(action.visible == true)
        check:Show()
        check:SetControlEnabled(enabled)
    end
    for index = #available + 1, #dialog.checks do
        dialog.checks[index].actionId = nil
        dialog.checks[index]:Hide()
    end
    dialog.ListContent:SetHeight(math.max(1, #available * 32))
    dialog.Scroll:UpdateScrollChildRect()
    self.refreshing = false
end

function Edit:CreateUI()
    if self.dialog or not self.launcher.button then return end
    local button = self.launcher.button
    local selection = CreateFrame("Frame", "NobleNextLauncherSelection", button, "EditModeSystemSelectionTemplate")
    self.selection = selection
    if button.EditGlow then button.EditGlow:Hide() end
    selection:SetAllPoints(button)
    selection:SetSystem({GetSystemName=function() return "NobleNext" end})
    -- Keep the native selection art/hover/tooltip, but not SelectSystem(),
    -- which is defined only for Blizzard's registered system frames.
    local function forward(event, ...)
        local handler = button:GetScript(event)
        if handler then handler(button, ...) end
    end
    selection:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "LeftButton" and self:CanChange() then
            forward("OnMouseDown", mouseButton)
            self:OpenSettings()
        end
    end)
    selection:SetScript("OnMouseUp", function(_, mouseButton) forward("OnMouseUp", mouseButton) end)
    selection:SetScript("OnDragStart", function() if self:CanChange() then forward("OnDragStart") end end)
    selection:SetScript("OnDragStop", function() forward("OnDragStop") end)
    selection:Hide()

    local dialog = CreateFrame("Frame", "NobleNextLauncherSettings", UIParent)
    self.dialog = dialog
    dialog:Hide()
    dialog:SetSize(328, 432)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetFrameLevel(200)
    dialog:SetClampedToScreen(true)
    dialog:SetMovable(true)
    dialog:SetDontSavePosition(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
    dialog:SetScript("OnDragStop", function(frame) frame:StopMovingOrSizing() end)
    dialog.Border = CreateFrame("Frame", nil, dialog, "DialogBorderTranslucentTemplate")
    dialog.Border:SetAllPoints()
    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -17)
    title:SetText("NobleNext")
    dialog.Close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    dialog.Close:SetPoint("TOPRIGHT")
    dialog.Close:SetScript("OnClick", function() self:CloseSettings() end)
    local label = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 22, -52)
    label:SetText("Размер значка")
    dialog.Scale = CreateFrame("Frame", nil, dialog, "MinimalSliderWithSteppersTemplate")
    dialog.Scale:SetPoint("TOPLEFT", 24, -80)
    dialog.Scale:SetWidth(278)
    dialog.Scale.RightText:ClearAllPoints()
    dialog.Scale.RightText:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -22, -52)
    local formatters = {
        [MinimalSliderWithSteppersMixin.Label.Right]=function(value) return ("%d%%"):format(math.floor(value + 0.5)) end,
        [MinimalSliderWithSteppersMixin.Label.Min]=function() return "100%" end,
        [MinimalSliderWithSteppersMixin.Label.Max]=function() return "300%" end,
    }
    dialog.Scale:Init(self.launcher:GetIconScale() * 100, 100, 300, 40, formatters)
    dialog.Scale:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        if not self.refreshing and self:CanChange() then self.launcher:SetIconScale(value / 100) end
    end, self)
    local actionsLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    actionsLabel:SetPoint("TOPLEFT", 22, -132)
    actionsLabel:SetText("Быстрые действия по ПКМ")
    dialog.Scroll = Lib.Scroll.CreateFrame(dialog)
    dialog.Scroll:SetPoint("TOPLEFT", 18, -155)
    dialog.Scroll:SetPoint("BOTTOMRIGHT", -30, 78)
    dialog.ListContent = CreateFrame("Frame", nil, dialog.Scroll)
    dialog.ListContent:SetSize(274, 1)
    dialog.Scroll:SetScrollChild(dialog.ListContent)
    dialog.checks = {}
    dialog.Reset = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    dialog.Reset:SetSize(276, 24)
    dialog.Reset:SetPoint("BOTTOM", 0, 43)
    dialog.Reset:SetText("Вернуть значок под миникарту")
    dialog.Reset:SetScript("OnClick", function() if self:CanChange() then self.launcher:ResetPosition() end end)
    local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 20, 16)
    hint:SetPoint("BOTTOMRIGHT", -20, 16)
    hint:SetText("Сохранить или отменить — в панели редактирования WoW.")
end

function Edit:Enter()
    if self.active or not self.launcher.db then return end
    self.active, self.dirty = true, false
    self.baseline, self.pendingDraft, self.savingDraft = self:Capture(), nil, nil
    self.layoutIndex = self.manager.layoutInfo and self.manager.layoutInfo.activeLayout
    self:CreateUI()
    if self.selection and self:CanChange() then self.selection:ShowHighlighted() end
end

function Edit:Revert()
    if not self.active then return end
    self:Restore(self.baseline)
    self.dirty = false
    self:CloseSettings()
    self:UpdateNativeDirty()
end

function Edit:Saved()
    local draft = self.savingDraft
    if not draft then return end
    self.savingDraft = nil
    -- SavedLayouts callbacks have no ordering guarantee. Save-and-Exit can
    -- already have reverted/closed Edit Mode when SaveLayouts returns here.
    -- Commit the captured draft after that native transaction has completed.
    self:Restore(draft)
    if self.active then
        self.baseline, self.pendingDraft, self.dirty = self:Capture(), nil, false
        self:UpdateNativeDirty()
    end
end

function Edit:Exit()
    if self.active then self:Restore(self.baseline) end
    self.active, self.dirty, self.baseline, self.pendingDraft = false, false, nil, nil
    if self.dialog then self.dialog:Hide() end
    if self.selection then self.selection:Hide() end
end

function Edit:AttachManager()
    if self.manager or not EditModeManagerFrame then return end
    self.manager = EditModeManagerFrame
    local manager = self.manager
    manager:HookScript("OnHide", function()
        self.launcher:SetEditMode(false)
        if self.dialog then self.dialog:Hide() end
        if self.selection then self.selection:Hide() end
    end)
    manager:HookScript("OnShow", function()
        if self:CanChange() then
            if self.launcher.nativeEditActive then self.launcher:SetEditMode(true) end
            if self.selection then self.selection:ShowHighlighted() end
        end
    end)
    hooksecurefunc(manager, "SetHasActiveChanges", function(_, value)
        if not value and self.active and self.dirty and not self.updatingDirty then
            self.updatingDirty = true
            manager:SetHasActiveChanges(true)
            self.updatingDirty = false
        end
    end)
    hooksecurefunc(manager, "ClearSelectedSystem", function() self:CloseSettings() end)
    hooksecurefunc(manager, "SelectSystem", function() self:CloseSettings() end)
    hooksecurefunc(manager, "RevertAllChanges", function() self:Revert() end)
    -- OnLoad captured the original RevertAllChanges in GenerateClosure before
    -- this posthook existed. Observe the native button without replacing it.
    manager.RevertAllChangesButton:HookScript("OnClick", function()
        self.pendingDraft, self.savingDraft = nil, nil
        self:Revert()
    end)
    hooksecurefunc(manager, "PrepareSystemsForSave", function()
        if self.active then
            -- MakeNewLayout has already reverted the active preset at this
            -- point; its matching addon draft was captured before the dialog.
            self.savingDraft = copy(self.pendingDraft or self:Capture())
        end
    end)
    hooksecurefunc(manager, "SaveLayouts", function() self:Saved() end)
    hooksecurefunc(manager, "ShowNewLayoutDialog", function()
        if self.active then self.pendingDraft = self:Capture() end
    end)
    hooksecurefunc(manager, "UpdateLayoutInfo", function()
        local index = manager.layoutInfo and manager.layoutInfo.activeLayout
        if self.active and index ~= self.layoutIndex then
            self.pendingDraft = nil
            self:Revert()
            self.layoutIndex = index
        end
    end)
end

function Edit:OpenSettings()
    if inCombat() then return false end
    self:AttachManager()
    local manager = self.manager
    if not manager or not self.launcher.button then return false end
    if not manager:IsEditModeActive() then
        if not manager:CanEnterEditMode() then return false end
        if GameMenuFrame and GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
        ShowUIPanel(manager)
    end
    if not self:CanChange() then return false end
    manager:ClearSelectedSystem()
    self:CreateUI()
    if not self.dialog then return false end
    self.dialog:ClearAllPoints()
    local screenScale = UIParent:GetEffectiveScale()
    local right = manager:GetRight()
    local rightEdge = right and right * manager:GetEffectiveScale() / screenScale
    local dialogWidth = self.dialog:GetWidth() * self.dialog:GetEffectiveScale() / screenScale
    if rightEdge and rightEdge + dialogWidth + 16 > UIParent:GetWidth() then
        self.dialog:SetPoint("TOPRIGHT", manager, "TOPLEFT", -16, 0)
    else
        self.dialog:SetPoint("TOPLEFT", manager, "TOPRIGHT", 16, 0)
    end
    self.dialog:Show()
    self.selection:ShowSelected()
    self:RefreshControls()
    return true
end

function ns.InitializeLauncherEditMode(launcher)
    if Edit.launcher then return Edit end
    Edit.launcher = launcher
    Edit:AttachManager()
    EventRegistry:RegisterCallback("EditMode.Enter", function() Edit:AttachManager(); Edit:Enter() end, Edit)
    EventRegistry:RegisterCallback("EditMode.Exit", function() Edit:Exit() end, Edit)
    EventRegistry:RegisterCallback("EditMode.NewLayoutCancel", function() Edit.pendingDraft = nil end, Edit)
    local events = CreateFrame("Frame")
    events:RegisterEvent("ADDON_LOADED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function(_, event)
        if event == "ADDON_LOADED" then Edit:AttachManager()
        elseif event == "PLAYER_REGEN_DISABLED" then
            if Edit.dialog then Edit.dialog:Hide() end
            if Edit.selection then Edit.selection:Hide() end
        elseif Edit.restorePresentation then
            Edit.restoring = true
            launcher:SetIconScale(launcher.db.iconScale)
            Edit.restoring, Edit.restorePresentation = false, nil
        end
    end)
    if ns.Subscribe then
        for _, event in ipairs({"ACCESS_CHANGED", "QUICK_ACTIONS_CHANGED"}) do
            ns.Subscribe(event, "NobleNextLauncherSettings", function() Edit:RefreshControls() end)
        end
    end
    return Edit
end
