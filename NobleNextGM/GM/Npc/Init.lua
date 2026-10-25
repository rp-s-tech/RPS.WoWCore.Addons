-- Loaded through the NobleNextGM private extension namespace.
-- GM/Npc/Init.lua — контекст NPC: move/delete/add/go + near-cache

local _, ns = ...

local Ui = {}

local function SendCmd(cmd, tag)
    cmd = tostring(cmd or ""):gsub("^%.", "")
    if ns.EnqueueCommand then
        ns.EnqueueCommand(cmd, { tag = tag or "npcpanel" })
    elseif ns.RunGmCommand then
        ns.RunGmCommand(cmd)
    else
        ns.PrintError("RunGmCommand недоступен.")
    end
end

local function FormatCmd(path, argValues, fallback)
    local CD = ns.CommandDefinitions
    if CD and CD.Find and CD.Format then
        local def = CD.Find(path)
        if def then
            local cmd = CD.Format(def, argValues)
            if cmd and cmd ~= "" then
                return cmd
            end
        end
    end
    return fallback
end

local function Positive(v)
    local n = tonumber(v)
    return n and n > 0 and n or nil
end

local function UpdateContextLabel()
    if not Ui.contextText then
        return
    end
    local npc = ns.SelectionContext and ns.SelectionContext.GetNpc and ns.SelectionContext.GetNpc()
    if not npc then
        Ui.contextText:SetText("|cffb06a6aНет активного NPC - выберите в чате [Sel] или укажите GUID.|r")
        return
    end
    Ui.contextText:SetText(string.format(
        "|cff7fe39aАКТИВНЫЙ NPC|r  guid=%s  entry=%s  %s",
        tostring(npc.guid or "-"),
        tostring(npc.entry or "-"),
        npc.name or ""
    ))
    if Ui.guidBox and npc.guid then
        Ui.guidBox:SetText(tostring(npc.guid))
    end
    if Ui.entryBox and npc.entry then
        Ui.entryBox:SetText(tostring(npc.entry))
    end
end

local function RefreshNearList()
    if not Ui.nearList then
        return
    end
    local rows = (ns.SelectionContext and ns.SelectionContext.GetNearNpcs and ns.SelectionContext.GetNearNpcs()) or {}
    Ui.nearList:SetRows(rows)
    if Ui.nearHint then
        Ui.nearHint:SetText(string.format("Кэш near/чат: %d. Клик - сделать активным.", #rows))
    end
end

local function ConfirmDelete(guid)
    StaticPopupDialogs["NOBLENEXT_NPC_PANEL_DELETE"] = {
        text = string.format("Удалить NPC GUID %s?", guid),
        button1 = DELETE or YES,
        button2 = CANCEL or NO,
        OnAccept = function()
            SendCmd(FormatCmd("npc delete", { guid = guid, [1] = guid }, "npc delete " .. guid), "npcpanel:del")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("NOBLENEXT_NPC_PANEL_DELETE")
end

local function InitNpcModule(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:Hide()
    Ui.root = f

    f:SetScript("OnShow", function()
        UpdateContextLabel()
        RefreshNearList()
    end)

    local Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    Title:SetText("NPC")
    Title:SetTextColor(ns.COLORS.goldRaw.r, ns.COLORS.goldRaw.g, ns.COLORS.goldRaw.b)
    Title:SetPoint("TOP", f, "TOP", 0, -8)

    local help = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    help:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
    help:SetTextColor(0.6, 0.6, 0.6, 1)
    help:SetText("Чат: .npc near / .lookup creature -> [Sel][Move][Go][Del][Info] / [Add]. Turn = Move к вам.")

    local ctx = ns.CreateNGSection(f, "Контекст", nil, 70)
    ctx:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -36)
    ctx:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -36)
    ctx:SetHeight(70)
    Ui.contextText = ctx:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    Ui.contextText:SetPoint("TOPLEFT", ctx, "TOPLEFT", 12, -28)
    Ui.contextText:SetPoint("TOPRIGHT", ctx, "TOPRIGHT", -12, -28)
    Ui.contextText:SetJustifyH("LEFT")

    local act = ns.CreateNGSection(f, "Действия", nil, 140)
    act:SetPoint("TOPLEFT", ctx, "BOTTOMLEFT", 0, -8)
    act:SetPoint("TOPRIGHT", ctx, "BOTTOMRIGHT", 0, -8)
    act:SetHeight(140)

    local guidLbl = ns.CreateNGLabel(act, "GUID:")
    guidLbl:SetPoint("TOPLEFT", act, "TOPLEFT", 12, -28)
    Ui.guidBox = ns.CreateNGEditBox(act, "NpcPanel_Guid", 100, 22)
    Ui.guidBox:SetPoint("LEFT", guidLbl, "RIGHT", 6, 0)
    Ui.guidBox:SetNumeric(true)

    local entryLbl = ns.CreateNGLabel(act, "Entry:")
    entryLbl:SetPoint("LEFT", Ui.guidBox, "RIGHT", 12, 0)
    Ui.entryBox = ns.CreateNGEditBox(act, "NpcPanel_Entry", 80, 22)
    Ui.entryBox:SetPoint("LEFT", entryLbl, "RIGHT", 6, 0)
    Ui.entryBox:SetNumeric(true)

    local function ResolveGuid()
        return Positive(Ui.guidBox:GetText())
            or (ns.SelectionContext and ns.SelectionContext.GetNpc() and ns.SelectionContext.GetNpc().guid)
    end

    local function ResolveEntry()
        return Positive(Ui.entryBox:GetText())
            or (ns.SelectionContext and ns.SelectionContext.GetNpc() and ns.SelectionContext.GetNpc().entry)
    end

    local selBtn = ns.CreateNGButton(act, "Sel", 60, 22)
    local moveBtn = ns.CreateNGButton(act, "Move", 70, 22)
    local goBtn = ns.CreateNGButton(act, "Go", 60, 22)
    local delBtn = ns.CreateNGButton(act, "Del", 60, 22)
    local infoBtn = ns.CreateNGButton(act, "Info", 60, 22)
    local addBtn = ns.CreateNGButton(act, "Add", 60, 22)
    local nearBtn = ns.CreateNGButton(act, "Near", 70, 22)

    local actionButtons = { selBtn, moveBtn, goBtn, delBtn, infoBtn, addBtn, nearBtn }
    local function layoutActionRow()
        local wrapW = math.max(200, (act:GetWidth() or 600) - 24)
        if ns.Layout and ns.Layout.PlaceRow then
            ns.Layout.PlaceRow(actionButtons, act, 12, -58, 6, wrapW)
        else
            selBtn:SetPoint("TOPLEFT", act, "TOPLEFT", 12, -58)
            for i = 2, #actionButtons do
                actionButtons[i]:SetPoint("LEFT", actionButtons[i - 1], "RIGHT", 6, 0)
            end
        end
    end
    act:SetScript("OnSizeChanged", layoutActionRow)
    layoutActionRow()

    selBtn:SetScript("OnClick", function()
        local g = ResolveGuid()
        if not g then
            ns.PrintError("Укажите GUID NPC.")
            return
        end
        ns.SelectionContext.SetNpc(g, ResolveEntry(), nil)
        UpdateContextLabel()
    end)

    moveBtn:SetScript("OnClick", function()
        local g = ResolveGuid()
        if not g then
            ns.PrintError("Укажите GUID NPC.")
            return
        end
        SendCmd(FormatCmd("npc move", { guid = g, [1] = g }, "npc move " .. g), "npcpanel:move")
        ns.SelectionContext.SetNpc(g, ResolveEntry(), nil)
        UpdateContextLabel()
    end)

    goBtn:SetScript("OnClick", function()
        local g = ResolveGuid()
        if not g then
            ns.PrintError("Укажите GUID NPC.")
            return
        end
        SendCmd(FormatCmd("go creature", { creature = g, [1] = g }, "go creature " .. g), "npcpanel:go")
    end)

    delBtn:SetScript("OnClick", function()
        local g = ResolveGuid()
        if not g then
            ns.PrintError("Укажите GUID NPC.")
            return
        end
        ConfirmDelete(g)
    end)

    infoBtn:SetScript("OnClick", function()
        local g = ResolveGuid()
        if g and ns.SelectionContext then
            ns.SelectionContext.SetNpc(g, ResolveEntry(), nil)
        end
        SendCmd(FormatCmd("npc info", {}, "npc info"), "npcpanel:info")
    end)

    addBtn:SetScript("OnClick", function()
        local e = ResolveEntry()
        if not e then
            ns.PrintError("Укажите entry для .npc add.")
            return
        end
        SendCmd(FormatCmd("npc add", { entry = e, [1] = e }, "npc add " .. e), "npcpanel:add")
    end)

    nearBtn:SetScript("OnClick", function()
        SendCmd(FormatCmd("npc near", {}, "npc near"), "npcpanel:near")
        C_Timer.After(0.4, RefreshNearList)
    end)

    local nearSec = ns.CreateNGSection(f, "Недавние NPC (чат / near)")
    nearSec:SetPoint("TOPLEFT", act, "BOTTOMLEFT", 0, -8)
    nearSec:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 28)

    Ui.nearHint = nearSec:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Ui.nearHint:SetPoint("TOPLEFT", nearSec, "TOPLEFT", 12, -24)
    Ui.nearHint:SetPoint("TOPRIGHT", nearSec, "TOPRIGHT", -12, -24)
    Ui.nearHint:SetJustifyH("LEFT")
    Ui.nearHint:SetTextColor(0.7, 0.72, 0.75, 1)

    local listHost = CreateFrame("Frame", nil, nearSec)
    listHost:SetPoint("TOPLEFT", nearSec, "TOPLEFT", 8, -44)
    listHost:SetPoint("BOTTOMRIGHT", nearSec, "BOTTOMRIGHT", -8, 8)
    local listScroll = CreateFrame("ScrollFrame", nil, listHost, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", listHost, "TOPLEFT", 0, 0)
    listScroll:SetPoint("BOTTOMRIGHT", listHost, "BOTTOMRIGHT", -22, 0)
    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetWidth(560)
    listChild:SetHeight(24)
    listScroll:SetScrollChild(listChild)

    Ui.nearList = ns.VirtualList.Create(listChild, {
        width = 560,
        visibleCount = 7,
        rowHeight = 22,
        scrollFrame = listScroll,
        onClick = function(row)
            if row and row.guid then
                ns.SelectionContext.SetNpc(row.guid, row.entry, row.name)
                UpdateContextLabel()
            end
        end,
        renderRow = function(btn, row)
            local fs = btn.fs or btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.fs = fs
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", btn, "LEFT", 6, 0)
            fs:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            fs:SetJustifyH("LEFT")
            fs:SetText(string.format("GUID %s  entry=%s  %s",
                tostring(row.guid or "-"),
                tostring(row.entry or "-"),
                row.name or ""))
        end,
    })

    UpdateContextLabel()
    RefreshNearList()
    return f
end

ns.RegisterModule("NPC", InitNpcModule, "Контекст NPC: near / move / delete / add")

C_Timer.After(0, function()
    ns.RegisterSlashCommand("NNNPC", function() ns.ShowModule("NPC") end, "nnnpc")
end)
