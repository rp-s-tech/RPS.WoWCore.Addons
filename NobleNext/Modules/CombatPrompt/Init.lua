-- Queue every incoming attack; a server receipt closes each prompt.
local _,ns=...
local R=ns.RPSClient
local frame
local function Render()
    local id=R.promptOrder[1]
    local attack=id and R.prompts[id]
    if not attack then if frame then frame:Hide() end; return end
    if not frame then
        frame=CreateFrame("Frame","NobleNextDefensePrompt",UIParent,"BackdropTemplate")
        frame:SetSize(410,180); frame:SetPoint("TOP",UIParent,"TOP",0,-180); frame:SetFrameStrata("DIALOG")
        frame:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
        frame:SetBackdropColor(0.08,0.06,0.1,0.95)
        frame.title=frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); frame.title:SetPoint("TOP",0,-14)
        frame.timer=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); frame.timer:SetPoint("TOP",0,-43)
        frame.fate=CreateFrame("CheckButton",nil,frame,"UICheckButtonTemplate")
        frame.fate:SetPoint("TOPLEFT",18,-65)
        local label=frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        label:SetPoint("LEFT",frame.fate,"RIGHT",0,0); label:SetText("Судьба к Избеганию (+1d6 за 3 ОЭ)")
        frame.resistance=CreateFrame("CheckButton",nil,frame,"UICheckButtonTemplate")
        frame.resistance:SetPoint("TOPLEFT",18,-92)
        label=frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        label:SetPoint("LEFT",frame.resistance,"RIGHT",0,0); label:SetText("Сопротивление вместо Уклонения")
        frame.buttons={}
        for i,item in ipairs({{"Избегание","AVOID"},{"Блок (2 ОЭ)","BLOCK"},{"Принять","TAKE"}}) do
            local button=ns.CreateNGButton(frame,item[1],118,26)
            button:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",16+(i-1)*130,15)
            local choice=item[2]
            button:SetScript("OnClick",function()
                if frame.waiting then return end
                local requestId=R.RequestId()
                if R.Send("SendDefenseReaction",frame.attackId,choice,frame.resistance:GetChecked() and "resistance" or "evasion",
                    choice=="AVOID" and frame.fate:GetChecked()==true,requestId) then
                    frame.waiting=requestId; frame.sentAt=GetTime(); Render()
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
    if frame.attackId~=id then frame.waiting=nil; frame.fate:SetChecked(false); frame.resistance:SetChecked(false) end
    frame.attackId=id
    frame.title:SetText("Вас атакует "..tostring(attack.attackerName))
    for _,button in ipairs(frame.buttons) do button:SetEnabled(not frame.waiting) end
    frame:Show()
end
ns.Subscribe("RPS_REACTIONS_CHANGED","combat_prompt",Render)
ns.Subscribe("RPS_REQUEST_FAILED","combat_prompt_error",function(payload)
    if frame and frame.waiting==payload.requestId then frame.waiting=nil; Render() end
end)
Render()
