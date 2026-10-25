-- Loaded through the NobleNextGM private extension namespace.
-- GM/POI/MapPins.lua
local _, ns = ...
local function allowed() return ns.Access and ns.Access.Allows(2) == true end

ns.PoiMapPins = ns.PoiMapPins or {}
local views = {}
local function loadPinsLibrary()
    if LibStub then
        local lib = LibStub("HereBeDragons-Pins-2.0", true)
        if lib then return lib end
    end

    local loader = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    if loader then
        pcall(loader, "HereBeDragons")
    end

    return LibStub and LibStub("HereBeDragons-Pins-2.0", true)
end

local pinsLib = loadPinsLibrary()
local GROUP_RADIUS = 10
local GROUP_VISIBLE_ROWS = 7
local GROUP_ROW_HEIGHT = 46
local detailFrame
local detailRows = {}
local CARD_WIDTH = 330

-- Trinity GetPositionX/Y -> HereBeDragons world coordinates (same axis order as legacy POI).
local function poiToHbdWorld(poi)
    local map = tonumber(poi.map) or 0
    local serverX = tonumber(poi.x) or 0
    local serverY = tonumber(poi.y) or 0
    return map, serverY, serverX
end

local function groupCentroid(group)
    local count = #group.entries
    if count == 0 then
        return 0, 0
    end
    return group.x / count, group.y / count
end

local function findGroupForPoint(groups, data)
    local x = tonumber(data.x) or 0
    local y = tonumber(data.y) or 0
    local map = tonumber(data.map) or 0
    local radius2 = GROUP_RADIUS * GROUP_RADIUS

    for _, group in ipairs(groups) do
        if group.map == map then
            local cx, cy = groupCentroid(group)
            local dx, dy = cx - x, cy - y
            if (dx * dx) + (dy * dy) <= radius2 then
                return group
            end
        end
    end

    return nil
end

local function ensureDetailFrame()
    if detailFrame then return detailFrame end

    local f = CreateFrame("Frame", "NNPoiDetailFrame", UIParent, "BackdropTemplate")
    f:SetSize(CARD_WIDTH, 150)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        f:SetBackdropColor(0.02, 0.02, 0.02, 0.92)
        f:SetBackdropBorderColor(0.55, 0.55, 0.6, 0.9)
    end

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(24, 24)
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -16)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
    f.title:SetPoint("RIGHT", f, "RIGHT", -58, 0)
    f.title:SetJustifyH("LEFT")
    f.title:SetText("POI")

    f.meta = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.meta:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -46)
    f.meta:SetWidth(CARD_WIDTH - 36)
    f.meta:SetJustifyH("LEFT")
    f.meta:SetTextColor(0.58, 0.58, 0.58)

    f.line = f:CreateTexture(nil, "ARTWORK")
    f.line:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.line:SetSize(CARD_WIDTH - 44, 1)
    f.line:SetPoint("TOP", f.meta, "BOTTOM", 0, -8)
    f.line:SetVertexColor(0.9, 0.9, 0.9, 0.22)

    f.desc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.desc:SetPoint("TOPLEFT", f.line, "BOTTOMLEFT", 0, -10)
    f.desc:SetWidth(CARD_WIDTH - 44)
    f.desc:SetJustifyH("LEFT")
    f.desc:SetJustifyV("TOP")

    f.idText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.idText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 12)
    f.idText:SetTextColor(0.48, 0.48, 0.52)

    f.groupScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.groupScroll:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -44)
    f.groupScroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 16)
    f.groupScroll:EnableMouseWheel(true)
    f.groupScroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local maxScroll = self:GetVerticalScrollRange() or 0
        local nextValue = current - (delta * GROUP_ROW_HEIGHT)
        if nextValue < 0 then nextValue = 0 end
        if nextValue > maxScroll then nextValue = maxScroll end
        self:SetVerticalScroll(nextValue)
    end)
    f.groupScroll:Hide()

    f.groupChild = CreateFrame("Frame", nil, f.groupScroll)
    f.groupChild:SetSize(CARD_WIDTH - 54, GROUP_VISIBLE_ROWS * GROUP_ROW_HEIGHT)
    f.groupScroll:SetScrollChild(f.groupChild)

    detailFrame = f
    return f
end

local function clearDetailRows()
    for _, row in ipairs(detailRows) do
        row:Hide()
    end
end

local function showSingleDetail(data)
    if not allowed() then return end
    local f = ensureDetailFrame()
    clearDetailRows()
    f.icon:Show()
    f.meta:Show()
    f.line:Show()
    f.desc:Show()
    f.idText:Show()
    f.groupScroll:Hide()

    f.title:SetText(data.name or "POI")
    ns.PoiApplyColoredIcon(f.icon, data.iconKey, data.type, data.colorKey)
    f.meta:SetText(string.format("%s  |  %s", ns.PoiTypeLabel(data.type), ns.PoiOwnerDisplay(data)))
    f.idText:SetText("#" .. tostring(data.id or 0))

    local desc = ns.PoiFormatDescription(data.desc or "")
    f.desc:SetText(desc ~= "" and desc or "|cff777777Описание не задано.|r")
    f:SetHeight(math.max(128, 108 + f.desc:GetStringHeight()))
    f:Show()
end

local function showGroupDetail(group)
    if not allowed() then return end
    local f = ensureDetailFrame()
    clearDetailRows()
    f.icon:Show()
    ns.PoiApplyColoredIcon(f.icon, group.entries[1].iconKey, group.entries[1].type, group.entries[1].colorKey)
    f.meta:Hide()
    f.line:Hide()
    f.desc:Hide()
    f.idText:Hide()
    f.groupScroll:Show()

    f.title:SetText("POI рядом: " .. tostring(#group.entries))

    local y = 0
    for i, data in ipairs(group.entries) do
        local row = detailRows[i]
        if not row then
            row = CreateFrame("Button", nil, f.groupChild, "BackdropTemplate")
            row:SetSize(CARD_WIDTH - 62, 42)
            if row.SetBackdrop then
                row:SetBackdrop({
                    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 8,
                    insets = { left = 2, right = 2, top = 2, bottom = 2 }
                })
                row:SetBackdropColor(0.02, 0.02, 0.02, 0.5)
                row:SetBackdropBorderColor(0.35, 0.35, 0.38, 0.45)
            end
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(20, 20)
            row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
            row.text:SetWidth(CARD_WIDTH - 142)
            row.text:SetJustifyH("LEFT")
            row.idText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.idText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.idText:SetTextColor(0.48, 0.48, 0.52)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            detailRows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f.groupChild, "TOPLEFT", 0, -y)
        ns.PoiApplyColoredIcon(row.icon, data.iconKey, data.type, data.colorKey)
        row.text:SetText(string.format("|cffffd100%s|r\n|cff999999%s|r", data.name or "POI", ns.PoiOwnerDisplay(data)))
        row.idText:SetText("#" .. tostring(data.id or 0))
        row:SetScript("OnClick", function() showSingleDetail(data) end)
        row:Show()
        y = y + GROUP_ROW_HEIGHT
    end

    f.groupChild:SetHeight(math.max(GROUP_VISIBLE_ROWS * GROUP_ROW_HEIGHT, #group.entries * GROUP_ROW_HEIGHT))
    f.groupScroll:SetVerticalScroll(0)
    f:SetHeight(64 + (math.min(#group.entries, GROUP_VISIBLE_ROWS) * GROUP_ROW_HEIGHT))
    f:Show()
end

local function buildGroups()
    local groups = {}
    local ordered = {}

    for _, data in pairs(POI_Cache) do
        if data and data.id and not data.deleted then
            table.insert(ordered, data)
        end
    end
    table.sort(ordered, function(a, b) return (a.id or 0) < (b.id or 0) end)

    for _, data in ipairs(ordered) do
        local group = findGroupForPoint(groups, data)
        if not group then
            group = {
                map = tonumber(data.map) or 0,
                x = 0,
                y = 0,
                entries = {},
            }
            table.insert(groups, group)
        end

        table.insert(group.entries, data)
        group.x = group.x + (tonumber(data.x) or 0)
        group.y = group.y + (tonumber(data.y) or 0)
    end

    local keyed = {}
    for index, group in ipairs(groups) do
        table.sort(group.entries, function(a, b) return (a.id or 0) < (b.id or 0) end)
        local count = #group.entries
        if count > 0 then
            group.x = group.x / count
            group.y = group.y / count
        end
        keyed[tostring(index)] = group
    end

    return keyed
end

local function applyPinIcon(texture, data, colorKey, alpha)
    ns.PoiApplyColoredIcon(texture, data.iconKey, data.type, colorKey)
    if alpha then
        texture:SetAlpha(alpha)
    end
end

local pinButtonPool = {}

local function acquirePinButton(group)
    local data = group.entries[1]
    local count = #group.entries
    local btn = table.remove(pinButtonPool)
    if not btn then
        btn = CreateFrame("Button", nil, UIParent)
        btn:SetSize(28, 28)
        btn:SetFrameStrata("HIGH")
        btn:RegisterForClicks("LeftButtonUp")

        btn.shadow = btn:CreateTexture(nil, "BACKGROUND")
        btn.shadow:SetSize(23, 23)
        btn.shadow:SetPoint("CENTER", btn, "CENTER", 1, -1)

        btn.tex = btn:CreateTexture(nil, "ARTWORK")
        btn.tex:SetSize(20, 20)
        btn.tex:SetPoint("CENTER", btn, "CENTER", 0, 0)

        btn.badgeBg = btn:CreateTexture(nil, "OVERLAY")
        btn.badgeBg:SetTexture("Interface\\Buttons\\WHITE8X8")
        btn.badgeBg:SetSize(13, 13)
        btn.badgeBg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -1)
        btn.badgeBg:SetVertexColor(0.02, 0.02, 0.02, 0.85)

        btn.badge = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.badge:SetPoint("CENTER", btn.badgeBg, "CENTER", 0, 0)
        btn.badge:SetTextColor(1, 0.82, 0)
        btn.badge:SetShadowColor(0, 0, 0, 1)
        btn.badge:SetShadowOffset(1, -1)
    end

    applyPinIcon(btn.shadow, data, data.colorKey, 0.85)
    btn.shadow:SetVertexColor(0, 0, 0, 0.85)
    applyPinIcon(btn.tex, data, data.colorKey, 1)

    if count > 1 then
        btn.badge:SetText(tostring(count))
        btn.badgeBg:Show()
        btn.badge:Show()
    else
        btn.badgeBg:Hide()
        btn.badge:Hide()
    end

    btn:SetScript("OnEnter", function()
        if not allowed() then return end
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        if count > 1 then
            GameTooltip:AddDoubleLine("POI рядом", tostring(count), 1, 0.82, 0, 0.48, 0.48, 0.52)
            for i = 1, math.min(count, GROUP_VISIBLE_ROWS) do
                local item = group.entries[i]
                GameTooltip:AddDoubleLine(item.name or "POI", "#" .. tostring(item.id or 0), 1, 1, 1, 0.48, 0.48, 0.52)
                GameTooltip:AddLine("  " .. ns.PoiOwnerDisplay(item), 0.65, 0.65, 0.65)
            end
            if count > GROUP_VISIBLE_ROWS then
                GameTooltip:AddLine("... ещё " .. (count - GROUP_VISIBLE_ROWS), 0.7, 0.7, 0.7)
            end
            GameTooltip:AddLine("ЛКМ — открыть список", 1, 0.82, 0)
        else
            GameTooltip:AddDoubleLine(data.name or "POI", "#" .. tostring(data.id or 0), 1, 0.82, 0, 0.48, 0.48, 0.52)
            GameTooltip:AddLine(ns.PoiTypeLabel(data.type) .. "  |  " .. ns.PoiOwnerDisplay(data), 0.65, 0.65, 0.65)
            if data.desc and data.desc ~= "" then
                GameTooltip:AddLine(ns.PoiFormatDescription(data.desc), 1, 1, 1, true)
            end
            GameTooltip:AddLine("ЛКМ — открыть карточку", 1, 0.82, 0)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function()
        if not allowed() then return end
        GameTooltip:Hide()
        if count > 1 then
            showGroupDetail(group)
        else
            showSingleDetail(data)
        end
    end)

    return btn
end

local function removePin(key)
    local entry = views[key]
    if not entry then return end
    if pinsLib then
        if entry.world then pinsLib:RemoveWorldMapIcon(ns, entry.world) end
        if entry.minimap then pinsLib:RemoveMinimapIcon(ns, entry.minimap) end
    end
    if entry.worldBtn then
        entry.worldBtn:Hide()
        pinButtonPool[#pinButtonPool + 1] = entry.worldBtn
    end
    if entry.miniBtn then
        entry.miniBtn:Hide()
        pinButtonPool[#pinButtonPool + 1] = entry.miniBtn
    end
    views[key] = nil
end

function ns.PoiMapPins.ClearAll()
    for key in pairs(views) do
        removePin(key)
    end
end

function ns.PoiMapPins.ApplyOne(data)
    if not allowed() then return end
    if not data or not data.id then return end
    local key = tostring(data.id)
    if data.deleted then
        POI_Cache[key] = nil
    else
        POI_Cache[key] = data
    end

    ns.PoiMapPins.RedrawAll()
end

function ns.PoiMapPins.RedrawAll()
    pinsLib = pinsLib or loadPinsLibrary()
    ns.PoiMapPins.ClearAll()
    if not allowed() then
        if detailFrame then detailFrame:Hide() end
        return
    end
    for key, group in pairs(buildGroups()) do
        local worldBtn = acquirePinButton(group)
        local miniBtn = acquirePinButton(group)

        if pinsLib then
            local map, hbdX, hbdY = poiToHbdWorld(group)
            pinsLib:AddWorldMapIconWorld(ns, worldBtn, map, hbdX, hbdY)
            pinsLib:AddMinimapIconWorld(ns, miniBtn, map, hbdX, hbdY)
        else
            worldBtn:Hide()
            miniBtn:Hide()
        end

        views[key] = { world = worldBtn, minimap = miniBtn, worldBtn = worldBtn, miniBtn = miniBtn }
    end
end

function ns.PoiMapPins.HasLibrary()
    pinsLib = pinsLib or loadPinsLibrary()
    return pinsLib ~= nil
end
ns.Subscribe("ACCESS_CHANGED", "gm.poi-presentation", function()
    if not allowed() then
        ns.PoiMapPins.ClearAll()
        if detailFrame then detailFrame:Hide() end
        GameTooltip:Hide()
    else
        ns.PoiMapPins.RedrawAll()
    end
end)
