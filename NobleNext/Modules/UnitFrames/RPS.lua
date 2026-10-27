-- Render RP resources through untainted child StatusBar overlays so Blizzard's
-- 12.1.5 secret-number StatusBars and UnitFrameHealPredictionBars never taint.
local _, ns = ...
local R = ns.RPSClient
local barStates = {}
local barOverlays = {}
local hookedBars = {}
local hookedFrames = {}
local hookedClassBars = {}
local customStatusFrames = {}
local nativeHidden = {}

local SafeGuid = R.SafeGuid

local function UnitFrame(unit)
    if unit == "player" then return PlayerFrame end
    if unit == "focus" then return FocusFrame end
    return TargetFrame
end

local function ResolveUnitFrameParts(frame, unit)
    if not frame then
        if unit == "player" then
            return PlayerFrame_GetHealthBar and PlayerFrame_GetHealthBar() or PlayerFrameHealthBar,
                PlayerFrame_GetManaBar and PlayerFrame_GetManaBar() or PlayerFrameManaBar
        end
        local prefix = unit == "focus" and "FocusFrame" or "TargetFrame"
        return _G[prefix .. "HealthBar"], _G[prefix .. "ManaBar"]
    end

    local contentMain = (frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain)
        or (frame.PlayerFrameContent and frame.PlayerFrameContent.PlayerFrameContentMain)
    local contextual = (frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentContextual)
        or (frame.PlayerFrameContent and frame.PlayerFrameContent.PlayerFrameContentContextual)

    local healthBar = frame.healthbar
        or frame.HealthBar
        or (contentMain and contentMain.HealthBarsContainer and contentMain.HealthBarsContainer.HealthBar)
        or (frame.HealthBarContainer and frame.HealthBarContainer.HealthBar)

    local manaBar = frame.manabar
        or frame.ManaBar
        or (contentMain and contentMain.ManaBar)
        or (contentMain and contentMain.ManaBarArea and contentMain.ManaBarArea.ManaBar)

    if not healthBar and unit == "player" then
        healthBar = PlayerFrame_GetHealthBar and PlayerFrame_GetHealthBar() or PlayerFrameHealthBar
    end
    if not manaBar and unit == "player" then
        manaBar = PlayerFrame_GetManaBar and PlayerFrame_GetManaBar() or PlayerFrameManaBar
    end

    local nameFS = frame.name or (contentMain and contentMain.Name) or frame.Name
    local levelFS = frame.levelText or (contentMain and contentMain.LevelText) or frame.LevelText
    local highLevelTex = frame.highLevelTexture
        or (contextual and contextual.HighLevelTexture)
        or (contentMain and contentMain.HighLevelTexture)
    local deadText = frame.deadText
        or (contentMain and contentMain.HealthBarsContainer and contentMain.HealthBarsContainer.DeadText)

    return healthBar, manaBar, nameFS, levelFS, highLevelTex, deadText, contentMain
end

local function Bars(unit)
    local frame = UnitFrame(unit)
    local healthBar, manaBar = ResolveUnitFrameParts(frame, unit)
    return healthBar, manaBar
end

local function SelfProfileFor(unit)
    if not R.available or not R.profile then return end
    local guid, playerGuid = SafeGuid(unit), SafeGuid("player")
    if guid and playerGuid and guid == playerGuid then return R.profile end
end

function R.TargetResourceProfile()
    local selfProfile = SelfProfileFor("target")
    if selfProfile then return selfProfile end
    local p = R.target
    if p and p.inSystem and R.IsCurrentTarget(p) then return p end
    local state, data = R.GetUnitDisplayState("target")
    if state == "ready" and data and data.inSystem then return data end
end

function R.GetBarOverlay(bar)
    return bar and barOverlays[bar] or nil
end

local NATIVE_TEXT_KEYS = {
    "TextString",
    "Text",
    "HealthBarText",
    "ManaBarText",
    "CenterText",
    "LeftText",
    "RightText",
    "DeadText",
    "UnconsciousText",
}

local NATIVE_SUBREGION_KEYS = {
    "MyHealPredictionBar",
    "OtherHealPredictionBar",
    "HealAbsorbBar",
    "TotalAbsorbBar",
    "OverAbsorbGlow",
    "OverHealAbsorbGlow",
    "PlayerFrameHealthBarAnimatedLoss",
    "PlayerFrameTempMaxHealthLoss",
    "TempMaxHealthLoss",
    "TempMaxHealthLossDivider",
    "ManaCostPredictionBar",
    "FeedbackFrame",
    "FullPowerFrame",
    "Spark",
}

local function SetNativeBarVisualsAlpha(bar, alpha)
    if not bar then return end
    local nativeTex = (bar.GetStatusBarTexture and bar:GetStatusBarTexture())
        or bar.HealthBarTexture
        or bar.ManaBarTexture
    if nativeTex and nativeTex.SetAlpha then
        nativeTex:SetAlpha(alpha)
    end
    local parent = bar.GetParent and bar:GetParent() or nil
    for _, key in ipairs(NATIVE_TEXT_KEYS) do
        local fs, parentFs = bar[key], parent and parent[key]
        if fs and fs.SetAlpha then
            fs:SetAlpha(alpha)
        end
        if parentFs and parentFs ~= fs and parentFs.SetAlpha then
            parentFs:SetAlpha(alpha)
        end
    end
    for _, key in ipairs(NATIVE_SUBREGION_KEYS) do
        local sub = bar[key] or (parent and parent[key])
        if sub and sub.SetAlpha then
            sub:SetAlpha(alpha)
        end
    end
end

local function HideNative(bar)
    nativeHidden[bar] = true
    SetNativeBarVisualsAlpha(bar, 0)
end

local NO_DATA_COLOR = { 0.5, 0.5, 0.5 }
local HEALTH_COLOR = { 0, 1, 0 }
local ENERGY_COLOR = { 0, 0.45, 1 }

local BONUS_COLORS = {
    ["ОЗ"] = { 1.0, 0.82, 0.2 },
    ["ОЭ"] = { 0.55, 0.9, 1.0 },
}

-- Current may exceed maximum: the base bar fills to the maximum and the surplus is
-- drawn as a second "bonus" bar on top, so overflow is visible without rescaling.
local function SetOverlayValues(overlay, current, maximum, color, bonusColor)
    current = math.max(0, tonumber(current) or 0)
    maximum = math.max(0, tonumber(maximum) or 0)
    overlay:SetMinMaxValues(0, math.max(1, maximum))
    overlay:SetValue(math.min(current, maximum))
    overlay:SetStatusBarColor(color[1], color[2], color[3], 1)
    local bonusBar = overlay.bonus
    if bonusBar then
        local bonus = math.max(0, current - maximum)
        local span = maximum > 0 and maximum or math.max(1, bonus)
        bonusBar:SetMinMaxValues(0, span)
        bonusBar:SetValue(math.min(bonus, span))
        bonusColor = bonusColor or BONUS_COLORS["ОЗ"]
        bonusBar:SetStatusBarColor(bonusColor[1], bonusColor[2], bonusColor[3], 0.9)
    end
end

local function EnsureOverlay(bar, showText, fontObject, parent)
    if not bar then return nil end
    local overlay = barOverlays[bar]
    if overlay then return overlay end

    parent = parent or (bar.GetParent and bar:GetParent()) or UIParent or bar
    overlay = CreateFrame("StatusBar", nil, parent)
    overlay:SetAllPoints(bar)
    if overlay.SetFrameLevel and bar.GetFrameLevel then
        overlay:SetFrameLevel((bar:GetFrameLevel() or 1) + 3)
    end

    overlay:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    local nativeTex = (bar.GetStatusBarTexture and bar:GetStatusBarTexture())
        or bar.HealthBarTexture
        or bar.ManaBarTexture
    local ovTex = overlay.GetStatusBarTexture and overlay:GetStatusBarTexture()
    if nativeTex and nativeTex.GetAtlas and ovTex and ovTex.SetAtlas then
        local atlas = nativeTex:GetAtlas()
        if atlas and atlas ~= "" then
            ovTex:SetAtlas(atlas, true)
        end
    end
    local mask = (parent and parent.HealthBarMask) or bar.ManaBarMask or bar.HealthBarMask
    if mask and ovTex and ovTex.AddMaskTexture then
        ovTex:AddMaskTexture(mask)
    end

    local bonusBar = CreateFrame("StatusBar", nil, overlay)
    bonusBar:SetAllPoints(overlay)
    if bonusBar.SetFrameLevel and overlay.GetFrameLevel then
        bonusBar:SetFrameLevel((overlay:GetFrameLevel() or 1) + 1)
    end
    bonusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    local bonusTex = bonusBar.GetStatusBarTexture and bonusBar:GetStatusBarTexture()
    if ovTex and ovTex.GetAtlas and bonusTex and bonusTex.SetAtlas then
        local atlas = ovTex:GetAtlas()
        if atlas and atlas ~= "" then bonusTex:SetAtlas(atlas, true) end
    end
    if mask and bonusTex and bonusTex.AddMaskTexture then
        bonusTex:AddMaskTexture(mask)
    end
    bonusBar:SetMinMaxValues(0, 1)
    bonusBar:SetValue(0)
    overlay.bonus = bonusBar

    if showText ~= false then
        local fs = bonusBar:CreateFontString(nil, "OVERLAY", fontObject or "TextStatusBarText")
        fs:SetPoint("CENTER", bar, "CENTER", 0, 0)
        if fs.SetJustifyH then fs:SetJustifyH("CENTER") end
        if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        overlay.text = fs
        overlay.TextString = fs
    end

    barOverlays[bar] = overlay

    if not hookedBars[bar] then
        hookedBars[bar] = true
        local function ReassertAlpha()
            if nativeHidden[bar] then
                SetNativeBarVisualsAlpha(bar, 0)
            end
        end
        if bar.HookScript then
            for _, scriptName in ipairs({ "OnValueChanged", "OnEnter", "OnLeave", "OnShow" }) do
                pcall(bar.HookScript, bar, scriptName, ReassertAlpha)
            end
        end
        if bar.UpdateTextString and hooksecurefunc then
            hooksecurefunc(bar, "UpdateTextString", ReassertAlpha)
        end
    end

    return overlay
end

local function Paint(bar)
    local state = barStates[bar]
    if not state or not state.active then return end
    local overlay = EnsureOverlay(bar, state.showText)
    if not overlay then return end

    HideNative(bar)
    SetOverlayValues(overlay, state.current, state.maximum, state.color, BONUS_COLORS[state.label])

    if overlay.text then
        if not InCombatLockdown() then
            overlay.text:ClearAllPoints()
            overlay.text:SetPoint("CENTER", bar, "CENTER", state.textOffsetX or 0, 0)
        end
        if state.placeholder then
            overlay.text:SetText(state.label .. ": " .. state.placeholder)
        else
            overlay.text:SetText(R.FormatResource(state.current, state.maximum, state.label))
        end
        overlay.text:Show()
    end
    overlay:Show()
end

-- Fallback: only when this module is unavailable the overlay is
-- hidden and the alpha of native regions is restored; native bar methods are never called.
local function FallbackToNative(bar)
    if not bar then return end
    nativeHidden[bar] = nil
    local overlay = barOverlays[bar]
    if overlay then overlay:Hide() end
    SetNativeBarVisualsAlpha(bar, 1)
end

local function RestoreBar(bar, unit, label)
    local state = barStates[bar]
    if not state or not state.active then return end
    state.active = false
    FallbackToNative(bar)
end

local function Update(bar, unit, current, maximum, color, label, vehicle, textOffsetX, placeholder)
    if not bar then return end
    local state = barStates[bar]
    if not state then
        state = { showText = true }
        barStates[bar] = state
    end
    if vehicle then
        RestoreBar(bar, unit, label)
        return
    end
    state.active = true
    state.maximum = type(maximum) == "number" and math.max(0, maximum) or 0
    state.current = type(current) == "number" and math.max(0, current) or 0
    state.color = color
    state.label = label
    state.textOffsetX = textOffsetX or 0
    state.placeholder = placeholder
    Paint(bar)
end

-- Overlay fill and caption for a state without values: none = full grey "—",
-- loading/unknown = empty "…", error = empty "ошибка"; nil = native bar (module unavailable).
local function NoDataView(displayState)
    local text = R.RESOURCE_STATE_TEXT[displayState]
    if not text then return nil end
    if displayState == "none" then return text, 1, NO_DATA_COLOR end
    return text, 0
end

-- tagged: target/focus add "(нет профиля)" to the health caption of a unit without a profile.
local function ApplyDisplayState(health, energy, unit, displayState, p, vehicle, manaTextOffsetX, tagged)
    if displayState == "ready" and p then
        Update(health, unit, p.curHealth, p.maxHealth, HEALTH_COLOR, "ОЗ", vehicle, 0)
        Update(energy, unit, p.curEnergy, p.maxEnergy, ENERGY_COLOR, "ОЭ", vehicle, manaTextOffsetX)
        return
    end
    local text, fill, color = NoDataView(displayState)
    if not text then
        RestoreBar(health, unit, "ОЗ")
        RestoreBar(energy, unit, "ОЭ")
        return
    end
    local healthText = (tagged and displayState == "none") and (text .. " (нет профиля)") or text
    Update(health, unit, fill, fill, color or HEALTH_COLOR, "ОЗ", vehicle, 0, healthText)
    Update(energy, unit, fill, fill, color or ENERGY_COLOR, "ОЭ", vehicle, manaTextOffsetX, text)
end

local function HidePlayerClassPowerBars()
    if not R.profile then return end
    local classBars = {
        _G.PaladinPowerBarFrame,
        _G.ComboPointPlayerFrame,
        _G.RuneFrame,
        _G.MageArcaneChargesFrame,
        _G.WarlockPowerFrame,
        _G.MonkHarmonyBarFrame,
        _G.EvokerEbonMightBar,
        _G.PlayerFrameBottomManagedFramesContainer,
        _G.PlayerFrameAlternatePowerBarArea,
    }
    for _, bar in ipairs(classBars) do
        if bar and bar.Hide then
            bar:Hide()
            if not hookedClassBars[bar] and hooksecurefunc then
                hookedClassBars[bar] = true
                hooksecurefunc(bar, "Show", function(self)
                    if R.available and R.profile then self:Hide() end
                end)
            end
        end
    end
    if PlayerFrame and PlayerFrame.PlayerFrameContainer and not (UnitHasVehicleUI and UnitHasVehicleUI("player")) then
        local c = PlayerFrame.PlayerFrameContainer
        if c.AlternatePowerFrameTexture and c.AlternatePowerFrameTexture.Hide then
            c.AlternatePowerFrameTexture:Hide()
        end
        if c.FrameTexture and c.FrameTexture.Show then
            c.FrameTexture:Show()
        end
    end
end

local function FullResourceLayout(frame)
    if not frame then return end
    local _, manaBar, nameFS, levelFS, highLevelTex, deadText, main = ResolveUnitFrameParts(frame)
    if nameFS then
        if nameFS.SetWordWrap then nameFS:SetWordWrap(false) end
        if nameFS.SetMaxLines then nameFS:SetMaxLines(1) end
    end
    if deadText and deadText.SetAlpha then
        deadText:SetAlpha(0)
    end
    if levelFS and highLevelTex and highLevelTex.IsShown and highLevelTex:IsShown() then
        if levelFS.Hide then levelFS:Hide() end
    end
    if InCombatLockdown() then return end

    local container = main and main.HealthBarsContainer
    if not container or not frame.TargetFrameContainer then return end

    local isMinus = UnitClassification and UnitClassification(frame.unit) == "minus"
    if isMinus then
        frame.TargetFrameContainer.FrameTexture:SetAtlas("UI-HUD-UnitFrame-Target-PortraitOn", true)
        if frame.threatIndicator then
            frame.threatIndicator:SetAtlas("UI-HUD-UnitFrame-Target-PortraitOn-InCombat", true)
        end
        if frame.UpdateHealthBarVisuals then
            frame:UpdateHealthBarVisuals("normal")
        end
        if container.TempMaxHealthLoss and container.TempMaxHealthLoss.TempMaxHealthLossTexture then
            container.TempMaxHealthLoss.TempMaxHealthLossTexture:SetAtlas("UI-HUD-UnitFrame-Target-PortraitOn-Bar-TempHPLoss", true)
        end
        if container.HealthBar and container.HealthBar.HealthBarTexture then
            container.HealthBar.HealthBarTexture:SetAtlas("UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health", true)
        end
        if container.HealthBarMask then
            container.HealthBarMask:SetAtlas("UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health-Mask", true)
            container.HealthBarMask:ClearAllPoints()
            container.HealthBarMask:SetPoint("TOPLEFT", -1, 6)
        end
    end

    -- Ensure Slot 2 (HealthBarsContainer: y = -40..-60) and Slot 3 (ManaBar: y = -61..-71)
    -- are always in their proper 3-row positions below Slot 1 (Name & Level: y = -26..-38).
    container:SetSize(126, 20)
    container:ClearAllPoints()
    container:SetPoint("BOTTOMRIGHT", frame.TargetFrameContainer, "LEFT", 149, -10)
    if manaBar then
        manaBar:ClearAllPoints()
        manaBar:SetPoint("TOPRIGHT", container, "BOTTOMRIGHT", 8, -1)
        manaBar:Show()
    end
end

local updating = false

local function HookTargetLayout()
    for _, unit in ipairs({ "target", "focus" }) do
        local frame = UnitFrame(unit)
        if frame and not hookedFrames[frame] then
            hookedFrames[frame] = true
            for _, method in ipairs({ "Update", "CheckClassification", "CheckLevel", "CheckDead" }) do
                if frame[method] and hooksecurefunc then
                    hooksecurefunc(frame, method, function() R.UpdateTargetLikeFrame(unit) end)
                end
            end
        end
    end
    if PlayerFrame_Update and not hookedFrames.PlayerFrame_Update and hooksecurefunc then
        hookedFrames.PlayerFrame_Update = true
        hooksecurefunc("PlayerFrame_Update", function() R.UpdateTargetLikeFrame("player") end)
    end
    for _, fnName in ipairs({
        "CompactUnitFrame_UpdateAll",
        "CompactUnitFrame_UpdateHealth",
        "CompactUnitFrame_UpdatePower",
        "CompactUnitFrame_UpdateStatusText",
    }) do
        if _G[fnName] and not hookedFrames[fnName] and hooksecurefunc then
            hookedFrames[fnName] = true
            hooksecurefunc(fnName, function(frame)
                if not updating then R.UpdateCompactRaidFrame(frame) end
            end)
        end
    end
end

-- Units still waiting for an answer are batched into RequestUnitsSync; target and player
-- have their own SyncTarget/SyncProfile requests and the server throttles reads.
local function QueueIfLoading(unit, state)
    if state == "loading" and unit ~= "target" and unit ~= "player" and R.QueueUnitSync then
        R.QueueUnitSync(SafeGuid(unit))
    end
end

local function DisplayStateFor(unit)
    if R.IsSystemUnavailable() then return "unavailable" end
    local state, data = R.GetUnitDisplayState(unit)
    QueueIfLoading(unit, state)
    return state, data
end

local function MainDisplayState(unit)
    if R.IsSystemUnavailable() then return "unavailable" end
    if unit == "player" then
        local state = R.GetSelfDisplayState()
        return state, state == "ready" and R.profile or nil
    end
    local selfProfile = SelfProfileFor(unit)
    if selfProfile then return "ready", selfProfile end
    if unit == "target" then
        local p = R.TargetResourceProfile()
        if p then return "ready", p end
    end
    local state, data = R.GetUnitDisplayState(unit)
    if state ~= "ready" and unit == "focus" then
        local guid, targetGuid = SafeGuid("focus"), SafeGuid("target")
        if guid and guid == targetGuid then return MainDisplayState("target") end
    end
    QueueIfLoading(unit, state)
    return state, data
end

function R.UpdateStandardUnitFrame(frame, unitToken, isCompactParty)
    if not frame then return end
    unitToken = unitToken or frame.unit
    if not unitToken then return end
    if UnitExists and not UnitExists(unitToken) and not SafeGuid(unitToken) then return end

    local isTargetOrFocus = (frame == TargetFrame or frame == FocusFrame or unitToken == "target" or unitToken == "focus")
    if isTargetOrFocus then
        FullResourceLayout(frame)
    end

    local healthBar, manaBar, nameFS = ResolveUnitFrameParts(frame, unitToken)
    if nameFS and nameFS.SetWordWrap then
        nameFS:SetWordWrap(false)
    end
    if not healthBar or not manaBar then return end

    local displayState, p
    if unitToken == "player" or unitToken == "target" or unitToken == "focus" then
        displayState, p = MainDisplayState(unitToken)
    else
        displayState, p = DisplayStateFor(unitToken)
    end

    local vehicle = unitToken == "player" and UnitHasVehicleUI and UnitHasVehicleUI("player")
    local manaTextOffsetX = isTargetOrFocus and -4 or 0
    ApplyDisplayState(healthBar, manaBar, unitToken, displayState, p, vehicle, manaTextOffsetX,
        isTargetOrFocus and not isCompactParty)
end

function R.RestoreCompactFrame(frame)
    if not frame then return end
    if frame.healthBar and barOverlays[frame.healthBar] then FallbackToNative(frame.healthBar) end
    if frame.powerBar and barOverlays[frame.powerBar] then FallbackToNative(frame.powerBar) end
    if customStatusFrames[frame] and frame.statusText then frame.statusText:SetText("") end
    customStatusFrames[frame] = nil
end

function R.UpdateCompactRaidFrame(frame)
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
    local unit = frame.displayedUnit or frame.unit
    if type(unit) ~= "string" or unit == "" then return end
    if UnitExists and not UnitExists(unit) then return end
    local isNamePlate = unit:find("^nameplate") ~= nil
    if frame.name and frame.name.SetWordWrap and not isNamePlate then
        frame.name:SetWordWrap(false)
    end

    local displayState, data = DisplayStateFor(unit)
    local ready = displayState == "ready" and data
    local noDataText, fill, noDataColor
    if not ready then
        noDataText, fill, noDataColor = NoDataView(displayState)
        if not noDataText then
            R.RestoreCompactFrame(frame)
            return
        end
    end

    if frame.healthBar then
        local hpOv = EnsureOverlay(frame.healthBar, isNamePlate,
            isNamePlate and (_G.SystemFont_NamePlate_Outlined and "SystemFont_NamePlate_Outlined" or "GameFontHighlightSmallOutline") or nil)
        if hpOv then
            HideNative(frame.healthBar)
            if ready then
                SetOverlayValues(hpOv, data.curHealth, data.maxHealth, { 0.0, 0.85, 0.0 }, BONUS_COLORS["ОЗ"])
            else
                SetOverlayValues(hpOv, fill, fill, noDataColor or { 0.0, 0.85, 0.0 })
            end
            if hpOv.TextString then
                hpOv.TextString:SetText(ready and R.FormatResource(data.curHealth, data.maxHealth) or ("ОЗ: " .. noDataText))
                hpOv.TextString:Show()
            end
            hpOv:Show()
        end
    end

    if frame.powerBar and not isNamePlate then
        local mpOv = EnsureOverlay(frame.powerBar, false)
        if mpOv then
            HideNative(frame.powerBar)
            if ready then
                SetOverlayValues(mpOv, data.curEnergy, data.maxEnergy, { 0.0, 0.44, 0.95 }, BONUS_COLORS["ОЭ"])
            else
                SetOverlayValues(mpOv, fill, fill, noDataColor or { 0.0, 0.44, 0.95 })
            end
            mpOv:Show()
        end
    end

    if frame.statusText and not isNamePlate then
        customStatusFrames[frame] = true
        frame.statusText:ClearAllPoints()
        frame.statusText:SetPoint("BOTTOMLEFT", frame.healthBar or frame, "BOTTOMLEFT", 3, 2)
        frame.statusText:SetPoint("BOTTOMRIGHT", frame.healthBar or frame, "BOTTOMRIGHT", -3, 2)
        if frame.statusText.SetWordWrap then frame.statusText:SetWordWrap(false) end

        if not ready then
            frame.statusText:SetText("ОЗ: " .. noDataText)
        else
            local h = (frame.GetHeight and frame:GetHeight()) or 36
            local health = R.FormatResource(data.curHealth, data.maxHealth)
            if h >= 42 then
                frame.statusText:SetText("ОЗ " .. health .. " | ОЭ " .. (tonumber(data.curEnergy) or 0))
            else
                frame.statusText:SetText(health)
            end
        end
        frame.statusText:Show()
    end
end

local function UpdateMainUnit(unit)
    local displayState, p = MainDisplayState(unit)
    if unit ~= "player" and UnitFrame(unit) then FullResourceLayout(UnitFrame(unit)) end
    local vehicle = unit == "player" and UnitHasVehicleUI and UnitHasVehicleUI("player")
    local health, energy = Bars(unit)
    local manaTextOffsetX = (unit ~= "player") and -4 or 0
    ApplyDisplayState(health, energy, unit, displayState, p, vehicle, manaTextOffsetX, unit ~= "player")
end

-- Native hooks fire from inside our own updates (Blizzard re-runs CheckLevel/Update on
-- layout changes); without this guard target+focus recursion grows exponentially.
local function Guarded(fn, ...)
    if updating then return end
    updating = true
    local ok, err = pcall(fn, ...)
    updating = false
    if not ok then error(err, 0) end
end

function R.UpdateTargetLikeFrame(unit)
    Guarded(function()
        if unit == "player" then HidePlayerClassPowerBars() end
        UpdateMainUnit(unit)
    end)
end

local function UpdateAll()
    HookTargetLayout()
    HidePlayerClassPowerBars()
    for _, unit in ipairs({ "player", "target", "focus" }) do
        UpdateMainUnit(unit)
    end

    if PartyFrame and PartyFrame.PartyMemberFramePool and PartyFrame.PartyMemberFramePool.EnumerateActive then
        for memberFrame in PartyFrame.PartyMemberFramePool:EnumerateActive() do
            R.UpdateStandardUnitFrame(memberFrame, memberFrame.unit, true)
        end
    else
        for i = 1, 4 do
            local pf = _G["PartyMemberFrame" .. i]
            if pf then R.UpdateStandardUnitFrame(pf, pf.unit or ("party" .. i), true) end
        end
    end

    if CompactRaidFrameContainer and CompactRaidFrameContainer.ApplyToFrames then
        CompactRaidFrameContainer:ApplyToFrames("normal", function(frame)
            R.UpdateCompactRaidFrame(frame)
        end)
    end

    for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
        if plate.UnitFrame then R.UpdateCompactRaidFrame(plate.UnitFrame) end
    end
end

-- Unit tooltip health bar. The overlay is parented to the bar itself so it hides
-- together with it on item/spell tooltips.
local tooltipUnit
local function TooltipBar()
    return GameTooltip and (GameTooltip.StatusBar or _G.GameTooltipStatusBar)
end

local function HideTooltipOverlay()
    local bar = TooltipBar()
    local overlay = bar and barOverlays[bar]
    if overlay and overlay:IsShown() then FallbackToNative(bar) end
end

function R.UpdateTooltipHealth(unit)
    local bar = TooltipBar()
    if not bar then return end
    tooltipUnit = unit
    local guid = unit and SafeGuid(unit)
    if not guid then HideTooltipOverlay(); return end
    local displayState, data = DisplayStateFor(unit)
    local ready = displayState == "ready" and data
    local noDataText, fill, noDataColor
    if not ready then
        noDataText, fill, noDataColor = NoDataView(displayState)
        if not noDataText then HideTooltipOverlay(); return displayState end
    end
    local overlay = EnsureOverlay(bar, true, "GameFontHighlightSmallOutline", bar)
    if not overlay then return displayState end
    HideNative(bar)
    if ready then
        SetOverlayValues(overlay, data.curHealth, data.maxHealth, { 0.0, 0.85, 0.0 }, BONUS_COLORS["ОЗ"])
    else
        SetOverlayValues(overlay, fill, fill, noDataColor or { 0.0, 0.85, 0.0 })
    end
    if overlay.TextString then
        overlay.TextString:SetText(ready and R.FormatResource(data.curHealth, data.maxHealth) or ("ОЗ: " .. noDataText))
        overlay.TextString:Show()
    end
    overlay:Show()
    return displayState
end

local function RefreshTooltipHealth()
    if tooltipUnit and GameTooltip and GameTooltip:IsShown() then
        R.UpdateTooltipHealth(tooltipUnit)
    end
end

local function TooltipUnitToken(tooltip)
    local unit
    if tooltip.GetUnit then
        local _, token = tooltip:GetUnit()
        unit = token
    end
    if unit == nil or (issecretvalue and issecretvalue(unit)) then
        unit = UnitExists and UnitExists("mouseover") and "mouseover" or nil
    end
    return unit
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if tooltip ~= GameTooltip then return end
        local displayState = R.UpdateTooltipHealth(TooltipUnitToken(tooltip))
        local line = displayState ~= "ready" and displayState ~= "loading" and R.DISPLAY_STATE_TEXT[displayState]
        if displayState == "error" then line = "Ошибка данных" end
        if line and tooltip.AddLine then tooltip:AddLine(line, 0.6, 0.6, 0.6) end
    end)
end
if GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipCleared", function()
        tooltipUnit = nil
        HideTooltipOverlay()
    end)
end

function R.UpdateNamePlate(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if plate and plate.UnitFrame then
        Guarded(R.UpdateCompactRaidFrame, plate.UnitFrame)
    end
end

function R.UpdateResourceBars()
    Guarded(function()
        UpdateAll()
        RefreshTooltipHealth()
    end)
end

R.RefreshAllUnitFrames = R.UpdateResourceBars

ns.Subscribe("RPS_PROFILE_CHANGED", "RPSResourceBars", R.UpdateResourceBars)
ns.Subscribe("RPS_TARGET_CHANGED", "RPSResourceBars", R.UpdateResourceBars)
ns.Subscribe("RPS_FOCUS_CHANGED", "RPSResourceBars", R.UpdateResourceBars)
ns.Subscribe("RPS_REQUEST_FAILED", "RPSResourceBars", R.UpdateResourceBars)

local events = CreateFrame("Frame")
for _, event in ipairs({
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_REGEN_ENABLED",
    "UNIT_ENTERED_VEHICLE",
    "UNIT_EXITED_VEHICLE",
    "ADDON_LOADED",
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
}) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        if R.QueueUnitSync then R.QueueUnitSync(SafeGuid(unit)) end
        R.UpdateNamePlate(unit)
        return
    end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        R.InvalidateGuid(SafeGuid(unit), unit)
        local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
        if plate and plate.UnitFrame then R.RestoreCompactFrame(plate.UnitFrame) end
        return
    end
    if event == "GROUP_ROSTER_UPDATE" then R.PruneUnitCache() end
    if (event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_FOCUS_CHANGED" or event == "GROUP_ROSTER_UPDATE")
        and R.RequestVisibleUnitsSync then
        R.RequestVisibleUnitsSync()
    end
    R.UpdateResourceBars()
end)

if UnitFrameManaBar_UpdateType and hooksecurefunc then
    hooksecurefunc("UnitFrameManaBar_UpdateType", function(bar) Paint(bar) end)
end
R.UpdateResourceBars()
