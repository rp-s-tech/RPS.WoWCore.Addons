local frames,byName,calls,subscribers,modules={},{},{},{},{}
local clock,shift,combat=10,false,false
GetTime=function() return clock end
GetServerTime=function() return 1000 end
IsShiftKeyDown=function() return shift end
InCombatLockdown=function() return combat end
C_Timer={After=function(_,fn) fn() end}
local pickups={}
C_Spell={PickupSpell=function(id) pickups[#pickups+1]=id end}
local function Frame(kind,name,parent)
    local f={kind=kind,name=name,parent=parent,scripts={},shown=true,enabled=true,text=""}
    frames[#frames+1]=f; if name then byName[name]=f end
    function f:SetScript(event,fn) self.scripts[event]=fn end
    function f:HookScript(event,fn)
        local old=self.scripts[event]
        self.scripts[event]=function(...) if old then old(...) end; fn(...) end
    end
    function f:Show() self.shown=true end
    function f:Hide() self.shown=false end
    function f:IsShown() return self.shown end
    f.IsVisible=f.IsShown
    function f:SetEnabled(value) self.enabled=value end
    function f:SetPoint(...) self.point={...} end
    function f:ClearAllPoints() end
    function f:SetAllPoints() end
    function f:SetSize(w,h) self.width,self.height=w,h end
    function f:SetWidth(value) self.width=value end
    function f:SetHeight(value) self.height=value end
    function f:SetText(value)
        self.text=value
        if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self,false) end
    end
    function f:GetText() return self.text end
    function f:SetChecked(value) self.checked=value end
    function f:GetChecked() return self.checked end
    function f:SetJustifyH() end
    function f:SetFrameStrata() end
    function f:SetBackdrop() end
    function f:SetBackdropColor() end
    function f:SetHighlightTexture() end
    function f:SetAutoFocus() end
    function f:RegisterEvent() end
    function f:RegisterForClicks() end
    function f:RegisterForDrag() end
    function f:SetScrollChild(child) self.content=child end
    function f:GetParent() return self.parent end
    function f:GetFrameLevel() return 1 end
    function f:SetFrameLevel() end
    function f:EnableMouse() end
    function f:SetTexture() end
    function f:SetAtlas(value) self.atlas=value end
    function f:SetTexCoord() end
    function f:SetColorTexture() end
    function f:SetStatusBarTexture() end
    function f:SetStatusBarColor() end
    function f:SetMinMaxValues(low,high) self.maximum=high end
    function f:SetValue(value) self.value=value end
    function f:SetAlpha(value) self.alpha=value end
    function f:CreateTexture() return Frame("Texture",nil,self) end
    function f:CreateFontString() return Frame("FontString",nil,self) end
    return f
end
CreateFrame=Frame
UIParent=Frame("Frame","UIParent")
GameTooltip={SetOwner=function() end,SetText=function() end,AddLine=function() end,Show=function() end}
GameTooltip_Hide=function() end
local ns={CharacterFrameTextures={title={"PaperDollInfoPart1",706,907,483,515}}}
function ns.Subscribe(event,key,fn) subscribers[event]=subscribers[event] or {}; subscribers[event][key]=fn end
function ns.Emit(event,...) for _,fn in pairs(subscribers[event] or {}) do fn(...) end end
function ns.PrintError(text) ns.error=text end
function ns.Print(text) ns.print=text end
function ns.CreateNGButton(parent,text,w,h) local f=Frame("Button",nil,parent); f.text=text; f:SetSize(w,h); return f end
function ns.CreateNGLabel(parent,text) local f=Frame("FontString",nil,parent); f.text=text; return f end
function ns.CreateNGEditBox(parent,name,w,h) local f=Frame("EditBox",name,parent); f:SetSize(w,h); return f end
function ns.RegisterModule(name,builder) modules[name]=builder end
local H,registrations
registrations=0
AIO={AddHandlers=function(name,h) assert(name=="RPS_Combat"); registrations=registrations+1; H=h; return h end,
    Handle=function(...) calls[#calls+1]={...} end}
assert(loadfile(ROOT.."/Addons/NobleNext/Core/RPSClient.lua"))("NobleNext",ns)
local clientEvents=frames[#frames]
local R=ns.RPSClient
local function Payload()
    return {protocol=1,registry={
        {key="health",category="general",name="Здоровье",icon="hp",spellId=0,diceFormula="none"},
        {key="accuracy",category="combat",name="Меткость",icon="dice",spellId=1500001,diceFormula="3d6"},
        {key="weapon_damage",category="weapon",name="Урон",icon="weapon",spellId=1500009,diceFormula="weapon"}},
        profile={curHealth=7,maxHealth=15,curEnergy=3,maxEnergy=10,curWounds=1,maxWounds=3,energySpentRound=2,
            archetype="fighter",raceId="human",weaponDice="1d8",blockDice="1d4",stats={accuracy=2},revision=4},pendingAttackIds={}}
end
H.SyncProfile(nil,Payload())
local function Click(frame) assert(frame.enabled); frame.scripts.OnClick(frame,"LeftButton") end
local cases={}
function cases.sheet()
    assert(loadfile(ROOT.."/Addons/NobleNext/Modules/CharacterFrame/RPS.lua"))("NobleNext",ns)
    local parent=Frame("Frame")
    assert(R.RenderSheet(parent))
    assert(R.sheet.headers[1].Label.text=="Общее")
    assert(R.sheet.rows[1].Value.text=="Человек" and R.sheet.rows[2].Value.text=="Боец")
    local count=#frames
    for i=1,100 do R.RenderSheet(parent) end
    assert(#frames==count and R.sheet.rows[3].Value.text=="7 / 15")
    local row=R.sheet.rows[4]
    row.scripts.OnClick(row,"RightButton")
    local call=calls[#calls]
    assert(call[1]=="RPS_Combat" and call[2]=="RollStat" and call[3]=="accuracy" and call[4]==true and call[6]==4)
    shift=true; row.scripts.OnDragStart(row); assert(pickups[1]==1500001)
    local sent=#calls; row.scripts.OnClick(row,"LeftButton"); assert(#calls==sent)
    combat=true; row.scripts.OnDragStart(row); assert(#pickups==1)
    R.Bind(); R.Send("RequestSync"); assert(registrations==1)
    local updated=Payload(); updated.profile.curHealth=3
    CharacterLevelText=Frame("FontString","CharacterLevelText",UIParent)
    H.SyncProfile(nil,updated); R.RenderSheet(parent)
    assert(#frames==count+1 and R.sheet.rows[3].Value.text=="3 / 15")
    assert(CharacterLevelText.text:find("Боец",1,true) and CharacterLevelText.text:find("1%-го уровня"))
    assert(R.GetLocalizedStatName("evasion")=="Уклонение")
    assert(R.GetLocalizedStatName("weapon_damage")=="Урон")
    assert(R.FormatSystemError("rate_limited"):find("Слишком частые запросы",1,true))
    H.Committed(nil,{requestId="roll-msg",result={kind="roll",statKey="evasion",total=14}})
    assert(ns.print:find("Уклонение",1,true) and ns.print:find("14",1,true))
    H.Error(nil,{code="rate_limited"})
    assert(ns.error:find("Слишком частые запросы",1,true))
end
function cases.prompts()
    assert(loadfile(ROOT.."/Addons/NobleNext/Modules/CombatPrompt/Init.lua"))("NobleNext",ns)
    local function Attack(id) return {attackId=id,attackerName="NPC",attackTotal=12,timeoutSec=30,weaponDice="1d8"} end
    H.PromptDefenseReaction(nil,Attack("one")); H.PromptDefenseReaction(nil,Attack("two"))
    H.PromptDefenseReaction(nil,Attack("one"))
    local f=byName.NobleNextDefensePrompt
    assert(#R.promptOrder==2 and f.attackId=="one")
    Click(f.buttons[3]); assert(f.waiting and not f.buttons[1].enabled and f.shown)
    local request=f.waiting
    H.Error(nil,{requestId=request,code="save_failed"})
    assert(not f.waiting and f.buttons[1].enabled and #R.promptOrder==2)
    Click(f.buttons[1]); H.ReactionClosed(nil,"one")
    assert(f.attackId=="two" and #R.promptOrder==1 and not f.waiting)
    local payload=Payload(); payload.pendingAttackIds={}
    H.SyncProfile(nil,payload)
    assert(#R.promptOrder==0 and not f.shown)
    assert(registrations==1)
end
function cases.dm()
    assert(loadfile(ROOT.."/Addons/NobleNextDM/GM/Battle/RPS.lua"))("NobleNextDM",ns)
    local parent=Frame("Frame")
    local panel=assert(modules["Бой 3d6"])(parent)
    local target={targetGuid="Creature-1",revision=7,name="NPC",canEdit=true,inSystem=true,
        curHealth=10,maxHealth=10,curEnergy=0,maxEnergy=0,armor=0,speed=10,weaponDice="1d6",blockDice="1d4",stats={accuracy=1}}
    H.SyncTarget(nil,target)
    local save
    for _,f in ipairs(frames) do if f.text=="Сохранить цель" then save=f end end
    assert(save and save.enabled)
    Click(save)
    local call=calls[#calls]
    assert(call[2]=="DmSaveTargetStats" and call[3].targetGuid=="Creature-1" and call[3].revision==7)
    assert(not save.enabled)
    H.Error(nil,{code="save_failed",requestId=call[4]})
    assert(save.enabled)
    Click(save)
    local retry=calls[#calls]
    clock=clock+11; panel.scripts.OnUpdate(panel)
    local repeated=calls[#calls]
    assert(repeated[2]=="DmSaveTargetStats" and repeated[3]==retry[3] and repeated[4]==retry[4])
    H.Committed(nil,{requestId=retry[4],result={kind="dm_save"}})
    assert(save.enabled)
    -- Clearing current target keeps remembered/focus unit in the 3d6 inspector.
    H.SyncUnit(nil,{guid="Creature-1",targetGuid="Creature-1",revision=8,name="Remembered NPC",canEdit=true,inSystem=true,
        curHealth=6,maxHealth=10,curEnergy=2,maxEnergy=4,armor=1,speed=10,weaponDice="1d6",blockDice="1d4",stats={accuracy=2}})
    R.target=nil; ns.Emit("RPS_TARGET_CHANGED",nil)
    assert(R.remembered and R.remembered.curHealth==6 and save.enabled)
    -- An empty SyncTarget ({inSystem=false} with no targetGuid) clears R.target without wiping R.remembered.
    H.SyncTarget(nil,{inSystem=false})
    assert(R.remembered and R.remembered.targetGuid=="Creature-1" and save.enabled)
    -- Selecting an out-of-system target shows it as current target (read-only) rather than falling back.
    H.SyncTarget(nil,{targetGuid="Creature-2",name="Other",canEdit=false,inSystem=false})
    assert(not save.enabled)
    H.SyncTarget(nil,nil) -- invalid packets do not overwrite the validated target
    assert(R.target.targetGuid=="Creature-2")
end
function cases.target_request()
    local delayed={}
    C_Timer.After=function(_,fn) delayed[#delayed+1]=fn end
    local count=#calls
    clientEvents.scripts.OnEvent(clientEvents,"PLAYER_TARGET_CHANGED")
    assert(#calls==count+1 and calls[#calls][2]=="RequestTargetSync" and R.target==nil)
    clientEvents.scripts.OnEvent(clientEvents,"PLAYER_TARGET_CHANGED")
    assert(#calls==count+2)
    delayed[1](); assert(#calls==count+2)
    delayed[2](); assert(#calls==count+3)
    UnitGUID=function() return "Player-1-00000002" end
    H.SyncTarget(nil,{inSystem=true,isPlayer=true,guidLow="1"})
    assert(R.target==nil)
    H.SyncTarget(nil,{inSystem=true,isPlayer=true,guidLow="2"})
    assert(R.target.guidLow=="2")
end
function cases.resources()
    hooksecurefunc=function(object,key,fn)
        local original=object[key]
        object[key]=function(...) local result=original(...); fn(...); return result end
    end
    local function Bar()
        local bar=Frame("StatusBar",nil,UIParent)
        bar.TextString=Frame("FontString",nil,bar)
        bar.LeftText=Frame("FontString",nil,bar); bar.RightText=Frame("FontString",nil,bar)
        function bar:UpdateTextString() self.TextString:SetText("native") end
        return bar
    end
    PlayerFrameHealthBar,PlayerFrameManaBar=Bar(),Bar()
    TargetFrameHealthBar,TargetFrameManaBar=Bar(),Bar()
    local guid="Creature-0-1-0-1-100-000000002A"
    local focusGuid=guid
    UnitGUID=function(unit)
        if unit=="focus" then return focusGuid end
        if unit=="player" then return "Player-1-00000001" end
        return guid
    end
    UnitClassification=function() return "minus" end
    checkLevelCalls=0
    local name=Frame("FontString",nil,UIParent)
    local function Target(unit,health,mana)
        local container=Frame("Frame",nil,UIParent)
        container.HealthBar=health
        container.HealthBarMask=Frame("Texture",nil,container)
        container.TempMaxHealthLoss={TempMaxHealthLossTexture=Frame("Texture",nil,container)}
        health.HealthBarTexture=Frame("Texture",nil,health)
        health:SetSize(126,20)
        local frame={unit=unit,healthbar=health,manabar=mana,
            TargetFrameContainer={FrameTexture=Frame("Texture",nil,UIParent)},
            TargetFrameContent={TargetFrameContentMain={HealthBarsContainer=container,ManaBar=mana}}}
        function frame:CheckClassification()
            container:SetSize(125,12)
            container:SetPoint("BOTTOMRIGHT",self.TargetFrameContainer,"LEFT",148,-1)
            self.TargetFrameContainer.FrameTexture:SetAtlas("UI-HUD-UnitFrame-Target-MinusMob-PortraitOn")
        self.healthbar.TextString:SetPoint("CENTER",name,"CENTER",0,0)
        self.manabar:Hide(); self.manabar.pauseUpdates=true
        end
        function frame:CheckLevel() checkLevelCalls=checkLevelCalls+1 end
        function frame:Update() self:CheckClassification(); self:CheckLevel() end
        return frame
    end
    TargetFrame=Target("target",TargetFrameHealthBar,TargetFrameManaBar)
    FocusFrame=Target("focus",Bar(),Bar())
    local originalSetValue=TargetFrameHealthBar.SetValue
    local tooltipPostCall
    local plainTooltip=GameTooltip
    GameTooltip=Frame("GameTooltip",nil,UIParent)
    GameTooltip.StatusBar=Bar()
    Enum={TooltipDataType={Unit=2}}
    TooltipDataProcessor={AddTooltipPostCall=function(kind,fn) assert(kind==2); tooltipPostCall=fn end}
    local framesBefore=#frames
    assert(loadfile(ROOT.."/Addons/NobleNext/Modules/UnitFrames/RPS.lua"))("NobleNext",ns)
    assert(tooltipPostCall)
    local unitEvents
    for i=framesBefore+1,#frames do if frames[i].scripts.OnEvent then unitEvents=frames[i] end end
    assert(unitEvents)
    local pHp=assert(R.GetBarOverlay(PlayerFrameHealthBar))
    local pMp=assert(R.GetBarOverlay(PlayerFrameManaBar))
    local tHp=assert(R.GetBarOverlay(TargetFrameHealthBar))
    local tMp=assert(R.GetBarOverlay(TargetFrameManaBar))
    local fHp=assert(R.GetBarOverlay(FocusFrame.healthbar))
    assert(pHp.value==7 and pMp.maximum==10)
    -- Pending target data is "loading", never a fake "0 / 0" resource.
    assert(tHp.TextString.text=="ОЗ: …" and tMp.TextString.text=="ОЭ: …" and tHp.value==0)
    assert(TargetFrameHealthBar.TextString.alpha==0 and TargetFrameHealthBar.LeftText.alpha==0
        and TargetFrameHealthBar.RightText.alpha==0) -- loading never shows native numbers (D24)
    assert(PlayerFrameHealthBar.lockValues==nil and TargetFrameHealthBar.lockValues==nil)
    assert(TargetFrameHealthBar.value==nil) -- never call SetValue on native secret-value StatusBars
    H.SyncTarget(nil,{inSystem=true,isPlayer=false,guidLow="42",curHealth=4,maxHealth=8,curEnergy=0,maxEnergy=0})
    local target=TargetFrameHealthBar
    assert(tHp.value==4 and tHp.TextString.text=="ОЗ: 4 / 8")
    assert(tMp.TextString.text=="ОЭ: 0 / 0" and tMp.shown)
    assert(target.SetValue==originalSetValue) -- do not intercept low-level native value/layout updates
    TargetFrame:Update(); target:UpdateTextString()
    assert(tHp.value==4 and tHp.TextString.text=="ОЗ: 4 / 8")
    assert(tHp.TextString.point[2]==target)
    assert(tMp.TextString.point[2]==TargetFrameManaBar and tMp.TextString.point[4]==-4)
    assert(TargetFrameManaBar.shown)
    local function CheckLayout(frame)
        frame:Update()
        local container=frame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
        assert(container.height==20 and container.width==126)
        assert(container.point[4]==149 and container.point[5]==-10)
        assert(frame.TargetFrameContainer.FrameTexture.atlas=="UI-HUD-UnitFrame-Target-PortraitOn")
        assert(container.HealthBarMask.atlas=="UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health-Mask")
        assert(frame.manabar.shown)
    end
    CheckLayout(TargetFrame); CheckLayout(FocusFrame)
    assert(fHp.value==4)
    -- Focus = target with hooked CheckLevel: the addon must never call hooked native methods itself.
    checkLevelCalls=0
    R.UpdateResourceBars()
    assert(checkLevelCalls==0)
    TargetFrame:Update(); FocusFrame:Update()
    assert(checkLevelCalls==2)
    -- Self as target/focus uses the local profile.
    local selfGuid=UnitGUID
    UnitGUID=function(unit) return "Player-1-00000001" end
    R.UpdateResourceBars()
    assert(tHp.value==R.profile.curHealth and fHp.value==R.profile.curHealth)
    UnitGUID=selfGuid
    guid="Creature-0-1-0-1-100-000000002B"
    R.UpdateResourceBars(); assert(tHp.value==0 and tHp.TextString.text=="ОЗ: …")
    assert(fHp.value==4) -- keep the confirmed snapshot of the focused GUID
    focusGuid="Creature-0-1-0-1-100-000000002C"
    R.UpdateResourceBars(); assert(fHp.value==0)
    -- Newer clients expose their own normal-layout implementation; use that method.
    local nativeLayouts=0
    function FocusFrame:UpdateHealthBarVisuals(classification)
        assert(classification=="normal"); nativeLayouts=nativeLayouts+1
    end
    FocusFrame:Update(); assert(nativeLayouts>0)
    guid="Creature-0-1-0-1-100-000000002A"
    R.UpdateResourceBars(); assert(tHp.value==4)
    local raidFrame={unit="raid1",displayedUnit="raid1",healthBar=Bar(),powerBar=Bar(),statusText=Frame("FontString",nil,UIParent),
        GetHeight=function() return 44 end}
    UnitExists=function() return true end
    local originalGuid=UnitGUID
    UnitGUID=function(unit)
        if unit=="raid1" then return "Player-1-00000009" end
        return originalGuid(unit)
    end
    H.SyncUnitBatch(nil,{["Player-1-00000009"]={guid="Player-1-00000009",inSystem=true,isPlayer=true,curHealth=12,maxHealth=20,curEnergy=5,maxEnergy=10}})
    R.UpdateCompactRaidFrame(raidFrame)
    assert(R.GetBarOverlay(raidFrame.healthBar).value==12 and R.GetBarOverlay(raidFrame.powerBar).value==5)
    assert(raidFrame.healthBar.value==nil and raidFrame.powerBar.value==nil)
    assert(raidFrame.statusText.text:find("ОЗ 12 / 20",1,true) and raidFrame.statusText.shown)
    -- Nameplates ("индикаторы здоровья") use the same cache; bonus health overflows the maximum.
    local plateBar=Bar()
    local plate={UnitFrame={unit="nameplate1",displayedUnit="nameplate1",healthBar=plateBar,powerBar=Bar(),
        statusText=Frame("FontString",nil,UIParent)}}
    C_NamePlate={GetNamePlates=function() return {plate} end,GetNamePlateForUnit=function() return plate end}
    UnitGUID=function(unit)
        if unit=="nameplate1" then return "Creature-0-1-0-1-200-0000000077" end
        return originalGuid(unit)
    end
    H.SyncUnit(nil,{guid="Creature-0-1-0-1-200-0000000077",inSystem=true,curHealth=18,maxHealth=15,curEnergy=0,maxEnergy=0})
    local plateOv=assert(R.GetBarOverlay(plateBar))
    assert(plateOv.value==15 and plateOv.bonus.value==3 and plateOv.bonus.maximum==15)
    assert(plateOv.TextString.text:find("18 / 15",1,true) and plateOv.TextString.text:find("(+3)",1,true))
    assert(plateBar.value==nil and not R.GetBarOverlay(plate.UnitFrame.powerBar))
    assert(plate.UnitFrame.statusText.text=="")
    -- New nameplate GUIDs are batched; cached ones are not requested again.
    local delayed={}
    C_Timer.After=function(_,fn) delayed[#delayed+1]=fn end
    local before=#calls
    R.QueueUnitSync("Creature-0-1-0-1-200-0000000077")
    R.QueueUnitSync("Creature-0-1-0-1-201-0000000078")
    R.QueueUnitSync("Creature-0-1-0-1-202-0000000079")
    assert(#delayed==1)
    delayed[1]()
    local request=calls[#calls]
    assert(#calls==before+1 and request[2]=="RequestUnitsSync" and #request[3]==2)
    -- Bonus resources on the main target frame.
    H.SyncTarget(nil,{inSystem=true,isPlayer=false,guidLow="42",curHealth=20,maxHealth=8,curEnergy=7,maxEnergy=5})
    assert(tHp.value==8 and tHp.bonus.value==8 and tHp.TextString.text:find("ОЗ: 20 / 8",1,true))
    assert(tHp.TextString.text:find("(+12)",1,true))
    assert(tMp.value==5 and tMp.bonus.value==2 and tMp.TextString.text:find("(+2)",1,true))
    H.SyncTarget(nil,{inSystem=true,isPlayer=false,guidLow="42",curHealth=4,maxHealth=8,curEnergy=0,maxEnergy=0})
    assert(tHp.bonus.value==0 and tHp.TextString.text=="ОЗ: 4 / 8")
    -- D24: a target without an RP profile shows a full grey overlay without native numbers.
    H.SyncTarget(nil,{guid=guid,inSystem=false,isPlayer=false,name="Воин из племени Ледяной Секиры"})
    assert(R.GetUnitDisplayState("target")=="none")
    assert(tHp.shown and tHp.value==1 and tHp.maximum==1 and tHp.TextString.text=="ОЗ: — (нет профиля)")
    assert(tMp.shown and tMp.TextString.text=="ОЭ: —")
    assert(TargetFrameHealthBar.TextString.alpha==0 and TargetFrameHealthBar.LeftText.alpha==0
        and TargetFrameHealthBar.RightText.alpha==0 and TargetFrameManaBar.TextString.alpha==0)
    TargetFrame:Update(); TargetFrameHealthBar:UpdateTextString()
    assert(TargetFrameHealthBar.TextString.alpha==0 and TargetFrameHealthBar.value==nil)
    H.SyncTarget(nil,{inSystem=true,isPlayer=false,guidLow="42",curHealth=4,maxHealth=8,curEnergy=0,maxEnergy=0})
    assert(tHp.TextString.text=="ОЗ: 4 / 8")
    -- Raid member without a profile: grey overlay, "ОЗ: —" in statusText.
    H.SyncUnitBatch(nil,{["Player-1-00000009"]={guid="Player-1-00000009",state="none",inSystem=false,isPlayer=true}})
    UnitGUID=function(unit)
        if unit=="raid1" then return "Player-1-00000009" end
        if unit=="nameplate1" then return "Creature-0-1-0-1-200-0000000077" end
        return originalGuid(unit)
    end
    R.UpdateCompactRaidFrame(raidFrame)
    local raidHp=R.GetBarOverlay(raidFrame.healthBar)
    assert(raidHp.shown and raidHp.value==1 and raidFrame.statusText.text=="ОЗ: —")
    assert(raidFrame.healthBar.TextString.alpha==0 and raidFrame.powerBar.TextString.alpha==0)
    assert(raidFrame.healthBar.value==nil)
    -- Tooltip health bar follows the cached snapshot and refreshes when a newer one arrives.
    local tipBar=GameTooltip.StatusBar
    function GameTooltip:GetUnit() return "Воин", "mouseover" end
    UnitGUID=function(unit)
        if unit=="mouseover" then return "Creature-0-1-0-1-200-0000000077" end
        return originalGuid(unit)
    end
    tooltipPostCall(GameTooltip)
    local tipOv=assert(R.GetBarOverlay(tipBar))
    assert(tipOv.parent==tipBar and tipOv.shown and tipOv.value==15 and tipOv.bonus.value==3)
    assert(tipBar.value==nil)
    H.SyncUnit(nil,{guid="Creature-0-1-0-1-200-0000000077",inSystem=true,curHealth=9,maxHealth=15,curEnergy=0,maxEnergy=0})
    assert(tipOv.value==9 and tipOv.bonus.value==0 and tipOv.TextString.text=="9 / 15")
    GameTooltip.scripts.OnTooltipCleared(GameTooltip)
    assert(not tipOv.shown)
    -- D24: negative answers keep the overlay ("ОЗ: …" for unknown, grey "ОЗ: —" for none).
    local plateGuid="Creature-0-1-0-1-200-0000000077"
    local mouseoverGuid=plateGuid
    UnitGUID=function(unit)
        if unit=="nameplate1" then return plateGuid end
        if unit=="mouseover" then return mouseoverGuid end
        return originalGuid(unit)
    end
    local lines={}
    function GameTooltip:AddLine(text) lines[#lines+1]=text end
    H.SyncUnitBatch(nil,{[plateGuid]={guid=plateGuid,state="unknown",inSystem=false}})
    assert(R.GetUnitDisplayState("nameplate1")=="unknown")
    assert(plateOv.shown and plateOv.value==0 and plateOv.TextString.text=="ОЗ: …")
    assert(plateBar.TextString.alpha==0 and plateBar.value==nil)
    tooltipPostCall(GameTooltip)
    assert(tipOv.shown and tipOv.TextString.text=="ОЗ: …" and tipBar.TextString.alpha==0)
    assert(lines[#lines]=="Данные недоступны")
    H.SyncUnit(nil,{guid=plateGuid,inSystem=false,name="Крестьянин"})
    assert(R.GetUnitDisplayState("nameplate1")=="none")
    assert(plateOv.shown and plateOv.value==1 and plateOv.TextString.text=="ОЗ: —" and plateBar.TextString.alpha==0)
    plateBar:UpdateTextString(); assert(plateBar.TextString.alpha==0)
    tooltipPostCall(GameTooltip)
    assert(lines[#lines]=="Нет профиля")
    assert(tipOv.shown and tipOv.value==1 and tipOv.TextString.text=="ОЗ: —" and tipBar.TextString.alpha==0)
    assert(tipBar.value==nil)
    H.SyncUnit(nil,{guid=plateGuid,inSystem=true,curHealth=5,maxHealth=15,curEnergy=0,maxEnergy=0})
    assert(plateOv.shown and plateOv.value==5 and plateBar.TextString.alpha==0)
    local lineCount=#lines
    tooltipPostCall(GameTooltip)
    assert(#lines==lineCount and tipOv.shown)
    -- A removed plate whose unit is still the mouseover keeps its snapshot; otherwise it is dropped.
    unitEvents.scripts.OnEvent(unitEvents,"NAME_PLATE_UNIT_REMOVED","nameplate1")
    assert(R.LookupUnitByGuid(plateGuid))
    mouseoverGuid=nil
    unitEvents.scripts.OnEvent(unitEvents,"NAME_PLATE_UNIT_REMOVED","nameplate1")
    assert(R.LookupUnitByGuid(plateGuid)==nil and not plateOv.shown and plateBar.TextString.alpha==1)
    assert(R.GetUnitDisplayState("nameplate1")=="loading")
    -- A plate that appears without an answer shows "ОЗ: …", requests its GUID and updates on reply.
    local sentBefore=#calls
    R.UpdateNamePlate("nameplate1")
    assert(plateOv.shown and plateOv.TextString.text=="ОЗ: …" and plateBar.TextString.alpha==0 and plateBar.value==nil)
    local i=1
    while delayed[i] and i<50 do delayed[i](); i=i+1 end
    local requested=false
    for n=sentBefore+1,#calls do
        if calls[n][2]=="RequestUnitsSync" then
            for _,g in ipairs(calls[n][3]) do requested=requested or g==plateGuid end
        end
    end
    assert(requested)
    H.SyncUnitBatch(nil,{[plateGuid]={guid=plateGuid,state="none",inSystem=false}})
    assert(plateOv.shown and plateOv.TextString.text=="ОЗ: —")
    GameTooltip.scripts.OnTooltipCleared(GameTooltip)
    GameTooltip=plainTooltip
    UnitGUID=originalGuid; UnitExists=nil; C_NamePlate=nil
    local count=#frames
    combat=true
    R.profile.curHealth=2; R.UpdateResourceBars()
    assert(#frames==count and pHp.value==2)
    H.Error(nil,{code="system_unavailable"})
    -- Only an unavailable RP system returns native bars (alpha only, no native writes).
    assert(R.IsSystemUnavailable())
    assert(not tHp.shown and not pHp.shown and not tMp.shown)
    assert(TargetFrameHealthBar.TextString.alpha==1 and TargetFrameHealthBar.LeftText.alpha==1
        and PlayerFrameHealthBar.TextString.alpha==1 and TargetFrameHealthBar.value==nil)
    TargetFrameHealthBar:UpdateTextString(); assert(TargetFrameHealthBar.TextString.alpha==1)
    assert(R.GetUnitDisplayState("target")=="error" and R.GetSelfDisplayState()=="error")
    raidFrame.displayedUnit="raid1"; UnitExists=function() return true end
    UnitGUID=function(unit) if unit=="raid1" then return "Player-1-00000009" end return originalGuid(unit) end
    R.UpdateCompactRaidFrame(raidFrame)
    assert(not raidHp.shown and raidFrame.healthBar.TextString.alpha==1 and raidFrame.statusText.text=="")
    UnitGUID=originalGuid; UnitExists=nil
    local restored=0
    UnitHasVehicleUI=function() return true end
    UnitFrameHealthBar_Update=function(bar) restored=restored+1; bar:SetValue(500) end
    UnitFrameManaBar_Update=UnitFrameHealthBar_Update
    R.UpdateResourceBars()
    assert(restored==0 and PlayerFrameHealthBar.value==nil and not pHp.shown and not PlayerFrameHealthBar.lockValues)
end
function cases.guid_normalization()
    local N=R.NormalizeGuid
    -- Server tostring(ObjectGuid) and client UnitGUID produce the same canonical key.
    assert(N("Player-1-0000000A")=="Player-1-0000000A")
    assert(N(" player-1-0000000a ")=="Player-1-0000000A")
    assert(N("Creature-0-1-0-1-100-000000002A")=="Creature-0-1-0-1-100-000000002A")
    assert(N("creature-0-1-0-1-100-000000002a")=="Creature-0-1-0-1-100-000000002A")
    assert(N("Vehicle-0-1-0-1-300-00000000FF")=="Vehicle-0-1-0-1-300-00000000FF")
    assert(N("Pet-0-1-0-1-400-0100000001")=="Pet-0-1-0-1-400-0100000001")
    for _,bad in ipairs({"","12345","Player-","Player--1","Player-1-","Creature-0 1",123,false}) do
        assert(N(bad)==nil, tostring(bad))
    end
    assert(N(string.rep("A",120).."-"..string.rep("1",10))==nil)
    -- Cache keys match whichever side produced the GUID.
    H.SyncUnit(nil,{guid="creature-0-1-0-1-100-000000002a",inSystem=true,curHealth=3,maxHealth=9,curEnergy=0,maxEnergy=0})
    assert(R.unitsByGuid["Creature-0-1-0-1-100-000000002A"].curHealth==3)
    assert(R.LookupUnitByGuid("Creature-0-1-0-1-100-000000002A").curHealth==3)
    UnitGUID=function(unit) if unit=="nameplate1" then return "Creature-0-1-0-1-100-000000002A" end end
    assert(R.GetUnitDisplayState("nameplate1")=="ready")
    -- Same low counter on another map/entry is a different unit: no low-GUID fallback.
    assert(R.LookupUnitByGuid("Creature-0-1-0-2-100-000000002A")==nil)
    UnitGUID=function(unit) if unit=="target" then return "Creature-0-1-0-2-100-000000002A" end end
    assert(not R.IsCurrentTarget(R.unitsByGuid["Creature-0-1-0-1-100-000000002A"]))
    -- A late SyncTarget for the previous selection is cached but never drawn on the new target.
    R.target=nil
    H.SyncTarget(nil,{guid="Creature-0-1-0-1-100-000000002A",inSystem=true,curHealth=8,maxHealth=9})
    assert(R.target==nil and R.unitsByGuid["Creature-0-1-0-1-100-000000002A"].curHealth==8)
    assert(R.GetUnitDisplayState("target")=="loading")
end
function cases.negative_cache()
    local delayed={}
    C_Timer.After=function(_,fn) delayed[#delayed+1]=fn end
    local tokens={target="Creature-0-1-0-1-100-0000000010",nameplate1="Creature-0-1-0-1-100-0000000011",
        nameplate2="Player-1-00000012",nameplate3="Creature-0-1-0-1-100-0000000013"}
    UnitGUID=function(unit) return tokens[unit] end
    H.SyncUnitBatch(nil,{
        [tokens.nameplate1]={guid=tokens.nameplate1,state="unknown",inSystem=false,reason="unresolved"},
        [tokens.nameplate2]={guid=tokens.nameplate2,state="none",inSystem=false,isPlayer=true,name="Гость"},
        [tokens.nameplate3]={guid=tokens.nameplate3,state="ready",inSystem=true,curHealth=6,maxHealth=6,curEnergy=1,maxEnergy=2}})
    assert(R.GetUnitDisplayState("nameplate1")=="unknown")
    assert(R.GetUnitDisplayState("nameplate2")=="none")
    assert(R.GetUnitDisplayState("nameplate3")=="ready")
    assert(R.GetUnitDisplayState("target")=="loading")
    -- Negative answers are cached: no repeated request while the TTL is running.
    local before=#calls
    R.QueueUnitSync(tokens.nameplate1); R.QueueUnitSync(tokens.nameplate2)
    assert(#delayed==0 and #calls==before)
    clock=clock+R.NEGATIVE_TTL.unknown+1
    assert(R.GetUnitDisplayState("nameplate1")=="loading" and R.GetUnitDisplayState("nameplate2")=="none")
    R.QueueUnitSync(tokens.nameplate1)
    assert(#delayed==1); delayed[1]()
    assert(#calls==before+1 and calls[#calls][2]=="RequestUnitsSync" and calls[#calls][3][1]==tokens.nameplate1)
    clock=clock+R.NEGATIVE_TTL.none
    assert(R.GetUnitDisplayState("nameplate2")=="loading")
    -- A positive answer replaces a negative one immediately.
    H.SyncUnit(nil,{guid=tokens.nameplate2,inSystem=true,isPlayer=true,curHealth=2,maxHealth=10,curEnergy=0,maxEnergy=0})
    assert(R.GetUnitDisplayState("nameplate2")=="ready")
    -- Invalidation: a unit that left every visible surface loses its snapshot.
    assert(R.InvalidateGuid(tokens.nameplate3,"nameplate3"))
    assert(R.LookupUnitByGuid(tokens.nameplate3)==nil)
    H.SyncUnit(nil,{guid=tokens.target,inSystem=true,curHealth=4,maxHealth=4,curEnergy=0,maxEnergy=0})
    assert(not R.InvalidateGuid(tokens.target,"nameplate1") and R.LookupUnitByGuid(tokens.target))
    -- GROUP_ROSTER_UPDATE prune keeps only units that are still visible.
    tokens.nameplate2=nil
    R.PruneUnitCache()
    assert(R.LookupUnitByGuid("Player-1-00000012")==nil and R.LookupUnitByGuid(tokens.target))
    -- Target change drops the previous target's snapshot unless it is still shown elsewhere.
    clientEvents.scripts.OnEvent(clientEvents,"PLAYER_TARGET_CHANGED")
    local oldTarget=tokens.target
    tokens.target="Creature-0-1-0-1-100-0000000020"
    clientEvents.scripts.OnEvent(clientEvents,"PLAYER_TARGET_CHANGED")
    assert(R.LookupUnitByGuid(oldTarget)==nil and R.target==nil)
    -- Server answered "no target in context": target is negative, not loading.
    H.SyncTarget(nil,{inSystem=false})
    assert(R.GetUnitDisplayState("target")=="unknown")
    -- Self states: loading -> none (no profile) -> error (system unavailable).
    R.profile,R.available,R.selfState=nil,false,"loading"
    assert(R.GetSelfDisplayState()=="loading" and R.GetUnitDisplayState("player")=="loading")
    H.Error(nil,{code="profile_unavailable"})
    assert(R.GetSelfDisplayState()=="none")
    H.Error(nil,{code="system_unavailable"})
    assert(R.GetSelfDisplayState()=="error" and R.GetUnitDisplayState("nameplate1")=="error")
    H.SyncProfile(nil,Payload())
    assert(R.GetSelfDisplayState()=="ready")
end
function cases.silent_server()
    local delayed={}
    C_Timer.After=function(_,fn) delayed[#delayed+1]=fn end
    R.profile,R.available,R.selfState,R.serverAnswered=nil,false,"loading",nil
    clientEvents.scripts.OnEvent(clientEvents,"PLAYER_LOGIN")
    assert(calls[#calls][2]=="RequestSync" and not R.IsSystemUnavailable())
    assert(R.GetUnitDisplayState("nameplate1")=="loading")
    delayed[#delayed]()
    assert(R.IsSystemUnavailable())
    H.SyncUnit(nil,{guid="Creature-0-1-0-1-100-0000000031",inSystem=false})
    assert(not R.IsSystemUnavailable())
    -- A late answer after the timeout clears the native fallback; system_unavailable sets it.
    H.Error(nil,{code="system_unavailable"})
    assert(R.IsSystemUnavailable())
    H.SyncProfile(nil,Payload())
    assert(not R.IsSystemUnavailable())
    local savedAIO=AIO; AIO=nil; R.available=false
    assert(R.IsSystemUnavailable())
    AIO=savedAIO
end
function cases.sheet_states()
    assert(loadfile(ROOT.."/Addons/NobleNext/Modules/CharacterFrame/RPS.lua"))("NobleNext",ns)
    local parent=Frame("Frame")
    assert(R.RenderSheet(parent) and R.SelfStateText()==nil)
    H.Error(nil,{code="system_unavailable"})
    R.RenderSheet(parent)
    assert(R.SelfStateText()=="Данные недоступны: показаны последние подтверждённые значения.")
    assert(R.sheet.rows[3].Value.text:find("7 / 15",1,true))
    R.profile,R.selfState=nil,"loading"
    assert(not R.RenderSheet(parent) and not R.sheet.shown)
    assert(R.SelfStateText()=="Ожидание данных сервера…")
    H.Error(nil,{code="profile_unavailable"})
    assert(R.SelfStateText()=="Нет профиля.")
end
return cases
