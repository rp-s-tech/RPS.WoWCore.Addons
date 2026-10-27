-- Queue every incoming attack; a server receipt closes each prompt.
-- Buttons use the same PerformAction route as the native Избегание/Блок spells.
local _,ns=...
local R=ns.RPSClient
local frame
local ACTIONS={{"Избегание","evade"},{"Блок (2 ОЭ)","block"},{"Принять","take"}}
local ACTION_NAMES={evade="Избегание",block="Блок"}
local function Selected()
    if frame and frame.selected and R.prompts[frame.selected] then return frame.selected end
    return R.promptOrder[1]
end
local function Step(delta)
    local id=Selected()
    for i,other in ipairs(R.promptOrder) do
        if other==id then
            local nextId=R.promptOrder[(i-1+delta)%#R.promptOrder+1]
            if nextId~=id then frame.selected=nextId; frame.waiting=nil end
            break
        end
    end
end
local Render
function Render()
    local id=Selected()
    local attack=id and R.prompts[id]
    if not attack then
        if frame then frame.choiceAction=nil; frame:Hide() end
        return
    end
    if not frame then
        frame=CreateFrame("Frame","NobleNextDefensePrompt",UIParent,"BackdropTemplate")
        frame:SetSize(410,200); frame:SetPoint("TOP",UIParent,"TOP",0,-180); frame:SetFrameStrata("DIALOG")
        frame:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
        frame:SetBackdropColor(0.08,0.06,0.1,0.95)
        frame.title=frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); frame.title:SetPoint("TOP",0,-14)
        frame.timer=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); frame.timer:SetPoint("TOP",0,-43)
        frame.hint=frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); frame.hint:SetPoint("TOP",0,-60)
        frame.fate=CreateFrame("CheckButton",nil,frame,"UICheckButtonTemplate")
        frame.fate:SetPoint("TOPLEFT",18,-78)
        local label=frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        label:SetPoint("LEFT",frame.fate,"RIGHT",0,0); label:SetText("Судьба к Избеганию (+1d6 за 3 ОЭ)")
        label=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        label:SetPoint("TOPLEFT",22,-108)
        label:SetText("Защита: Уклонение против физической, Сопротивление против магической атаки")
        frame.prev=ns.CreateNGButton(frame,"<",26,22); frame.prev:SetPoint("TOPLEFT",10,-10)
        frame.prev:SetScript("OnClick",function() Step(-1); Render() end)
        frame.next=ns.CreateNGButton(frame,">",26,22); frame.next:SetPoint("TOPRIGHT",-10,-10)
        frame.next:SetScript("OnClick",function() Step(1); Render() end)
        frame.buttons={}
        for i,item in ipairs(ACTIONS) do
            local button=ns.CreateNGButton(frame,item[1],118,26)
            button:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",16+(i-1)*130,15)
            local actionKey=item[2]
            button:SetScript("OnClick",function()
                if frame.waiting then return end
                local requestId=R.PerformAction(actionKey,{attackId=frame.attackId,
                    fate=actionKey=="evade" and frame.fate:GetChecked()==true})
                if requestId then
                    frame.waiting=requestId; frame.sentAt=GetTime(); frame.choiceAction=nil; Render()
                end
            end)
            frame.buttons[i]=button
        end
        frame:SetScript("OnUpdate",function(self)
            local a=R.prompts[self.attackId]; if not a then return end
            local remaining=math.max(0,a.deadline-GetTime())
            self.timer:SetText(self.waiting and "Ожидание подтверждения сервера..."
                or string.format("Атака: %d. Осталось: %.1f сек. В очереди: %d",a.attackTotal,remaining,#R.promptOrder))
            if self.waiting and GetTime()-self.sentAt>10 then
                self.waiting=nil; R.Send("RequestSync"); Render()
            end
        end)
    end
    if frame.attackId~=id then frame.waiting=nil; frame.fate:SetChecked(false) end
    frame.attackId=id
    frame.title:SetText("Вас атакует "..tostring(attack.attackerName))
    local position=1
    for i,other in ipairs(R.promptOrder) do if other==id then position=i end end
    frame.hint:SetText(frame.choiceAction and ("Выберите атаку для «"..(ACTION_NAMES[frame.choiceAction] or frame.choiceAction)
        .."» ("..position.."/"..#R.promptOrder..")") or (#R.promptOrder>1 and ("Атака "..position.." из "..#R.promptOrder) or ""))
    for _,button in ipairs(frame.buttons) do button:SetEnabled(not frame.waiting) end
    frame.prev:SetEnabled(#R.promptOrder>1); frame.next:SetEnabled(#R.promptOrder>1)
    frame:Show()
end
ns.Subscribe("RPS_REACTIONS_CHANGED","combat_prompt",Render)
ns.Subscribe("RPS_DEFENSE_CHOICE","combat_prompt_choice",function(payload)
    Render()
    if not frame then return end
    frame.choiceAction=payload.actionKey
    for _,id in ipairs(payload.attackIds) do
        if R.prompts[id] then frame.selected=id; break end
    end
    Render()
end)
ns.Subscribe("RPS_REQUEST_FAILED","combat_prompt_error",function(payload)
    if frame and frame.waiting==payload.requestId then frame.waiting=nil; Render() end
end)
Render()
