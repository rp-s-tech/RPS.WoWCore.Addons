-- Modules/Transmog/Init.lua — синхронизация ViewedOutfit с экипировкой
-- ViewedOutfit с Assigned перекрывает трансмог на предмете; этот модуль подтягивает фактический вид с экипировки.
--
-- Важно: вместо замены secure-функций гардероба (что вызывает taint / action-blocked),
-- модуль ограничивается синхронизацией ViewedOutfit и не трогает проверки пригодности внешностей.

local _, ns = ...
local ADDON_NAME = ns.ADDON_NAME or "NobleNext"
-- Guard для констант, которые могут отсутствовать в других билдах клиента
local NO_TRANSMOG = Constants and Constants.Transmog and Constants.Transmog.NoTransmogID
local DISPLAY_ASSIGNED = Enum and Enum.TransmogOutfitDisplayType and Enum.TransmogOutfitDisplayType.Assigned
local DISPLAY_EQUIPPED = Enum and Enum.TransmogOutfitDisplayType and Enum.TransmogOutfitDisplayType.Equipped
local DISPLAY_HIDDEN = Enum and Enum.TransmogOutfitDisplayType and Enum.TransmogOutfitDisplayType.Hidden
local SLOT_OPTION_NONE = Enum and Enum.TransmogOutfitSlotOption and Enum.TransmogOutfitSlotOption.None
local TYPE_APPEARANCE = Enum and Enum.TransmogType and Enum.TransmogType.Appearance
local TYPE_ILLUSION = Enum and Enum.TransmogType and Enum.TransmogType.Illusion

local panel
local SAVE_OUTFIT_LABEL = TRANSMOG_SAVE_OUTFIT or "Сохранить наряд"

local function report(message, isError)
    if panel then
        panel.Status:SetText(message)
        panel.Status:SetTextColor(isError and 1 or 0.85, isError and 0.55 or 0.85, isError and 0.4 or 0.85)
    end
    if ns.Print then ns.Print(message) else print("[" .. ADDON_NAME .. "] " .. message) end
end

local function unavailableReason()
    if not (NO_TRANSMOG and DISPLAY_ASSIGNED and DISPLAY_EQUIPPED and DISPLAY_HIDDEN
        and SLOT_OPTION_NONE and TYPE_APPEARANCE and TYPE_ILLUSION and TransmogUtil
        and C_TransmogOutfitInfo and C_TransmogOutfitInfo.GetAllSlotLocationInfo
        and C_TransmogOutfitInfo.SetPendingTransmog and C_TransmogOutfitInfo.HasPendingOutfitTransmogs) then
        return "Смена облика недоступна в этой версии клиента."
    end
    if InCombatLockdown and InCombatLockdown() then
        return "Дождитесь окончания боя."
    end
    if not TransmogFrame or not TransmogFrame:IsShown() then
        return "Сначала откройте окно трансмогрификации у трансмогрификатора."
    end
    local ok, pending = pcall(C_TransmogOutfitInfo.HasPendingOutfitTransmogs)
    if not ok then return "Не удалось прочитать выбранный облик. Откройте окно трансмогрификации заново." end
    if pending then
        return "В гардеробе есть несохранённые изменения. Примените или отмените их перед копированием."
    end
end

local function getWeaponOption(outfitSlot)
    local ok, option = pcall(C_TransmogOutfitInfo.GetEquippedSlotOptionFromTransmogSlot, outfitSlot)
    if ok and option then
        return option
    end
    return SLOT_OPTION_NONE
end

local function resolveAppearanceFromItem(location)
    local slotID = location:GetSlotID()
    local itemLoc = ItemLocation:CreateFromEquipmentSlot(slotID)
    if not itemLoc:IsValid() then
        return nil
    end

    local ok1, appliedInfo = pcall(C_Item.GetAppliedItemTransmogInfo, itemLoc)
    local ok2, baseInfo = pcall(C_Item.GetBaseItemTransmogInfo, itemLoc)
    if not ok1 or not ok2 or not appliedInfo or not baseInfo then
        return nil
    end

    local field = location:IsSecondary() and "secondaryAppearanceID" or "appearanceID"
    local appliedID = appliedInfo[field] or NO_TRANSMOG
    local baseID = baseInfo[field] or NO_TRANSMOG
    if appliedID == NO_TRANSMOG or appliedID == baseID then
        return NO_TRANSMOG, DISPLAY_EQUIPPED
    end

    -- ItemTransmogInfo.appearanceID already contains the modified appearance
    -- (source) ID expected by SetPendingTransmog, not a visual ID.
    local sourceID = appliedID

    if C_TransmogCollection.IsAppearanceHiddenVisual(sourceID) then
        return sourceID, DISPLAY_HIDDEN
    end

    return sourceID, DISPLAY_ASSIGNED
end

local function resolveAppearancePending(location)
    local itemTransmogID, itemDisplayType = resolveAppearanceFromItem(location)
    if itemTransmogID ~= nil then
        return itemTransmogID, itemDisplayType
    end

    local ok, visual = pcall(C_Transmog.GetSlotVisualInfo, location:GetData())
    if not ok or not visual then
        return nil
    end

    local appliedSource = visual.appliedSourceID
    local baseSource = visual.baseSourceID
    if appliedSource == NO_TRANSMOG then
        appliedSource = baseSource
    end

    local isTransmogrified = appliedSource ~= baseSource
        and appliedSource ~= NO_TRANSMOG
        and baseSource ~= NO_TRANSMOG

    if not isTransmogrified then
        return NO_TRANSMOG, DISPLAY_EQUIPPED
    end

    if C_TransmogCollection.IsAppearanceHiddenVisual(appliedSource) then
        return appliedSource, DISPLAY_HIDDEN
    end

    return appliedSource, DISPLAY_ASSIGNED
end

local function resolveIllusionPending(location)
    local ok, visual = pcall(C_Transmog.GetSlotVisualInfo, location:GetData())
    if not ok or not visual then
        return nil
    end

    local appliedSource = visual.appliedSourceID
    local baseSource = visual.baseSourceID
    if appliedSource == NO_TRANSMOG then
        appliedSource = baseSource
    end

    local hasIllusion = appliedSource ~= baseSource
        and appliedSource ~= NO_TRANSMOG
        and baseSource ~= NO_TRANSMOG

    if not hasIllusion then
        return NO_TRANSMOG, DISPLAY_EQUIPPED
    end

    if C_TransmogCollection.IsSpellItemEnchantmentHiddenVisual(appliedSource) then
        return appliedSource, DISPLAY_HIDDEN
    end

    return appliedSource, DISPLAY_ASSIGNED
end

local function slotNeedsUpdate(outfitSlot, transmogType, weaponOption, transmogID, displayType)
    local ok, viewed = pcall(C_TransmogOutfitInfo.GetViewedOutfitSlotInfo, outfitSlot, transmogType, weaponOption)
    if not ok or not viewed then
        return true
    end
    if viewed.transmogID ~= transmogID or viewed.displayType ~= displayType then
        return true
    end
    if viewed.warning and viewed.warning ~= Enum.TransmogOutfitSlotWarning.Ok then
        return true
    end
    return false
end

local function syncFromEquipped()
    if not C_TransmogOutfitInfo or not C_TransmogOutfitInfo.GetAllSlotLocationInfo then
        return false
    end

    local ok, appearanceSlotInfo, illusionSlotInfo = pcall(C_TransmogOutfitInfo.GetAllSlotLocationInfo)
    if not ok then
        return false
    end
    if not appearanceSlotInfo and not illusionSlotInfo then
        return false
    end

    local changed, failed = 0, 0

    if appearanceSlotInfo then
        for _, slotInfo in ipairs(appearanceSlotInfo) do
            local okLoc, location = pcall(TransmogUtil.CreateTransmogLocation, slotInfo.slotName, slotInfo.type, slotInfo.isSecondary)
            if okLoc and location and location:IsAppearance() then
                local transmogID, displayType = resolveAppearancePending(location)
                if transmogID ~= nil then
                    local outfitSlot = location:GetSlot()
                    local weaponOption = getWeaponOption(outfitSlot)
                    if slotNeedsUpdate(outfitSlot, TYPE_APPEARANCE, weaponOption, transmogID, displayType) then
                        local okSet = pcall(C_TransmogOutfitInfo.SetPendingTransmog, outfitSlot, TYPE_APPEARANCE, weaponOption, transmogID, displayType)
                        if okSet then
                            changed = changed + 1
                        else
                            failed = failed + 1
                        end
                    end
                end
            end
        end
    end

    if illusionSlotInfo then
        for _, slotInfo in ipairs(illusionSlotInfo) do
            local okLoc, location = pcall(TransmogUtil.CreateTransmogLocation, slotInfo.slotName, slotInfo.type, slotInfo.isSecondary)
            if okLoc and location and location:IsIllusion() then
                local transmogID, displayType = resolveIllusionPending(location)
                if transmogID ~= nil then
                    local outfitSlot = location:GetSlot()
                    local weaponOption = getWeaponOption(outfitSlot)
                    if slotNeedsUpdate(outfitSlot, TYPE_ILLUSION, weaponOption, transmogID, displayType) then
                        local okSet = pcall(C_TransmogOutfitInfo.SetPendingTransmog, outfitSlot, TYPE_ILLUSION, weaponOption, transmogID, displayType)
                        if okSet then
                            changed = changed + 1
                        else
                            failed = failed + 1
                        end
                    end
                end
            end
        end
    end

    return changed, failed
end

local function TransmogSyncHandler()
    local reason = unavailableReason()
    if reason then report(reason, true); return end
    local changed, failed = syncFromEquipped()
    if changed == false then
        report("Не удалось прочитать экипировку. Попробуйте открыть гардероб заново.", true)
    elseif failed > 0 then
        report("Часть предметов не удалось скопировать. Проверьте доступность обликов в гардеробе.", true)
    elseif changed > 0 then
        if panel then panel.hasPreviewResult = true end
        report("Облик подготовлен. Проверьте результат и стоимость, затем нажмите «" .. SAVE_OUTFIT_LABEL .. "» в гардеробе.")
    else
        report("Выбранный облик уже соответствует экипировке.")
    end
end

C_Timer.After(0, function()
    ns.RegisterSlashCommand("NNTRANSMOGSYNC", TransmogSyncHandler, "nntransmogsync")
end)

local function InitTransmogModule(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:Hide()
    panel = f
    f.lastReason = unavailableReason()

    local section = ns.CreateNGSection(f, "Облик экипировки", nil, 226)
    section:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
    section:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)

    local desc = section:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    desc:SetText("Скопируйте внешний вид надетых вещей в выбранный облик гардероба.")
    desc:SetPoint("TOPLEFT", section, "TOPLEFT", 16, -38)
    desc:SetPoint("TOPRIGHT", section, "TOPRIGHT", -16, -38)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)

    local steps = section:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    steps:SetText("1. Откройте окно трансмогрификации и выберите облик.\n2. Скопируйте экипировку кнопкой ниже.\n3. Проверьте результат и стоимость, затем нажмите «" .. SAVE_OUTFIT_LABEL .. "» в гардеробе.")
    steps:SetPoint("TOPLEFT", section, "TOPLEFT", 16, -78)
    steps:SetPoint("TOPRIGHT", section, "TOPRIGHT", -16, -78)
    steps:SetJustifyH("LEFT")
    steps:SetWordWrap(true)
    steps:SetSpacing(5)

    local syncBtn = ns.NNL.Widgets.CreateButton(section, {
        text = "Скопировать экипировку", width = 230, height = 28, style = "primary",
        onClick = TransmogSyncHandler,
        tooltip = "Подготовить облик для просмотра",
        tooltipLines = { "Сохранение и оплата выполняются кнопкой «" .. SAVE_OUTFIT_LABEL .. "» в гардеробе." },
    })
    syncBtn:SetPoint("BOTTOMLEFT", section, "BOTTOMLEFT", 16, 20)

    local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("TOPLEFT", section, "BOTTOMLEFT", 12, -16)
    status:SetPoint("TOPRIGHT", section, "BOTTOMRIGHT", -12, -16)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(true)
    f.Status = status
    f.SyncButton = syncBtn

    local function refresh()
        local reason = unavailableReason()
        syncBtn:SetEnabledEx(not reason, reason)
        status:SetText(reason or "Готово к копированию. Новый облик появится в окне трансмогрификации.")
        status:SetTextColor(0.85, 0.85, 0.85)
    end
    f:SetScript("OnShow", refresh)
    -- Poll only the visible help panel: native pending edits have no stable addon event.
    -- No equipment event or window opening changes appearances or commits money.
    f:SetScript("OnUpdate", function(_, elapsed)
        f.refreshElapsed = (f.refreshElapsed or 0) + elapsed
        if f.refreshElapsed < 0.5 then return end
        f.refreshElapsed = 0
        local reason = unavailableReason()
        syncBtn:SetEnabledEx(not reason, reason)
        if reason ~= f.lastReason then
            -- Keep the successful preview message while our own changes are pending.
            if not reason or not f.hasPreviewResult or not TransmogFrame or not TransmogFrame:IsShown() then
                status:SetText(reason or "Готово к копированию. Новый облик появится в окне трансмогрификации.")
                f.hasPreviewResult = nil
            end
            f.lastReason = reason
        end
    end)
    return f
end

ns.RegisterModule("Трансмог", InitTransmogModule, "Скопировать внешний вид экипировки в выбранный облик")
