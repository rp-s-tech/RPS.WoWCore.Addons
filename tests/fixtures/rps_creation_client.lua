-- R03 client: creation wizard over AIO RPS_Combat, session draft and CharacterFrame states.
local frames,byName,calls,subscribers={},{},{},{}
local clock=10
local delayed={}
GetTime=function() return clock end
GetServerTime=function() return 1000 end
IsShiftKeyDown=function() return false end
InCombatLockdown=function() return false end
UnitName=function() return "Тестер" end
UISpecialFrames={}
C_Timer={After=function(delay,fn) delayed[#delayed+1]={delay=delay,fn=fn} end}
local function RunTimers(maxDelay)
    for _=1,20 do
        local todo,rest={},{}
        for _,t in ipairs(delayed) do if t.delay<=maxDelay then todo[#todo+1]=t else rest[#rest+1]=t end end
        delayed=rest
        if #todo==0 then return end
        for _,t in ipairs(todo) do t.fn() end
    end
end
-- Unknown widget methods are no-ops; unknown lowercase fields stay nil like real frames.
local noop=function() end
local function Frame(kind,name,parent)
    local f={kind=kind,name=name,parent=parent,scripts={},shown=true,enabled=true,text=""}
    setmetatable(f,{__index=function(_,k) if type(k)=="string" and k:match("^%u") then return noop end end})
    frames[#frames+1]=f; if name then byName[name]=f end
    function f:SetScript(event,fn) self.scripts[event]=fn end
    function f:Show() local was=self.shown; self.shown=true; if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
    function f:Hide() self.shown=false end
    function f:IsShown() return self.shown end
    f.IsVisible=f.IsShown
    function f:SetEnabled(value) self.enabled=value and true or false end
    function f:SetPoint(...) self.point={...} end
    function f:SetSize(w,h) self.width,self.height=w,h end
    function f:SetText(value)
        self.text=value
        if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self,false) end
    end
    function f:GetText() return self.text end
    function f:GetStringHeight() return 28 end
    function f:GetParent() return self.parent end
    function f:CreateTexture() return Frame("Texture",nil,self) end
    function f:CreateFontString() return Frame("FontString",nil,self) end
    return f
end
CreateFrame=Frame
UIParent=Frame("Frame","UIParent")
GameTooltip={SetOwner=noop,SetText=noop,AddLine=noop,Show=noop}
GameTooltip_Hide=noop
StaticPopupDialogs={}
local popups={}
StaticPopup_Show=function(name) popups[#popups+1]=name end
local ns={CharacterFrameTextures={title={"PaperDollInfoPart1",706,907,483,515}}}
function ns.Subscribe(event,key,fn) subscribers[event]=subscribers[event] or {}; subscribers[event][key]=fn end
function ns.Emit(event,...) for _,fn in pairs(subscribers[event] or {}) do fn(...) end end
function ns.PrintError(text) ns.error=text end
function ns.Print(text) ns.print=text end
function ns.CreateNGButton(parent,text,w,h) local f=Frame("Button",nil,parent); f.text=text; f:SetSize(w,h); return f end
function ns.CreateNGEditBox(parent,name,w,h) local f=Frame("EditBox",name,parent); f:SetSize(w,h); return f end
local slash={}
function ns.RegisterSlashCommand(key,handler,aliases) slash[key]={handler=handler,aliases=aliases}; return true end
local H,registrations=nil,0
AIO={AddHandlers=function(name,h) assert(name=="RPS_Combat"); registrations=registrations+1; H=h; return h end,
    Handle=function(...) calls[#calls+1]={...} end}
local function Load(path) assert(loadfile(ROOT.."/Addons/NobleNext/"..path))("NobleNext",ns) end
Load("Core/RPSClient.lua")
local R=ns.RPSClient
Load("Modules/CharacterFrame/RPS.lua")
Load("Modules/CharacterCreation/State.lua")
Load("Modules/CharacterCreation/Wizard.lua")
local C=ns.CharacterCreation

-- Real SyncProfile shape: creation = Cr.SyncSummary next to profile; its revision is the creation revision.
local function Profile(state,creationRevision,creation)
    return {protocol=1,registry={
        {key="health",category="general",name="Здоровье",icon="hp",spellId=0,diceFormula="none"}},
        profile={curHealth=7,maxHealth=15,curEnergy=3,maxEnergy=10,curWounds=0,maxWounds=3,energySpentRound=0,
            archetype="fighter",raceId="human",weaponDice="1d8",blockDice="1d4",stats={},revision=40},
        creation=creation or (state and {state=state,revision=creationRevision or 0,catalogVersion="",rpName="",
            starterGranted=false,confirmedAt=0,rpLevel=1}) or nil,
        pendingAttackIds={}}
end
local function Options(state)
    local items={}
    for i=1,7 do items[i]={key="item"..i,name="Предмет "..i,slot=i==1 and "main_hand" or "pack",kind="weapon",dice=i==1 and "1d8" or nil} end
    return {catalogVersion="test-1",
        races={
            {key="orc",name="Орк",size="medium",sizeName="Средний",preset="default",presetVersion=1,
                features={{key="orc_default",name="Без расовых особенностей (заглушка)",text="Нет бонусов"}}},
            {key="human",name="Человек",size="средний",features={{key="human_a",name="Гибкость",text="А"},{key="human_b",name="Стойкость",text="Б"}}},
            {key="tauren",name="Таурен",size="large",sizeName="большой",features={{key="tauren_a",name="Традиции предков",text="+1 очко",masteryFree=1},{key="tauren_b",name="Мощь",text="В"}}},
            {key="pandaren",name="Пандарен",available=false,unavailableReason="каталог не завершён",features={}}},
        traits={
            {key="gifted",name="Одарённость",text="Г",needsChoice=true,choices={{key="fire",name="Огонь"},{key="frost",name="Лёд"}}},
            {key="lucky",name="Любимец судьбы",text="Д"}},
        archetypes={
            {key="fighter",name="Боец",featureName="Мастер оружия",featureText="Е"},
            {key="healer",name="Целитель",featureName="Целебные чары",featureText="Ж"}},
        mastery={keys={"skill","knowledge","endurance","craft"},basePoints=2},
        starter={maxItems=6,items=items},
        state=state or {creationState="legacy",state="legacy",revision=4}}
end
local function Last() return calls[#calls] end
local function Wizard() return byName.NobleNextCharacterCreation end
local function Click(frame) assert(frame.enabled,"button disabled"); frame.scripts.OnClick(frame,"LeftButton") end
local function FindRow(text)
    for _,row in ipairs(C.Wizard.rows) do
        if row.shown and row.Label.text:find(text,1,true) then return row end
    end
    error("row not found: "..text)
end
local function RowText(row) return C.Wizard.Plain(row.Label.text.." "..row.Right.text.." "..row.Sub.text) end
local function Choose(text) FindRow(text).scripts.OnClick(FindRow(text)) end
local function Sheet() return C.Wizard.SheetText() end
local function Has(text,needle) return text:find(needle,1,true)~=nil end
local function OpenWithOptions(state)
    slash.NOBLENEXTRPS.handler("create")
    assert(Last()[1]=="RPS_Combat" and Last()[2]=="RequestCharacterOptions")
    H.CharacterOptions(nil,Options(state))
    return Wizard()
end
local function FillDraft(f)
    Click(f.tabs[1]); Choose("Человек"); Choose("Гибкость")
    Click(f.tabs[2]); Choose("Любимец судьбы")
    Click(f.tabs[3]); Click(C.Wizard.mastery[1].plus); Click(C.Wizard.mastery[2].plus)
    Click(f.tabs[4]); Choose("Боец")
end
H.SyncProfile(nil,Profile("legacy"))

local cases={}
function cases.open_and_navigate()
    assert(registrations==1 and R.handlers.CharacterOptions==C.handlers.CharacterOptions)
    assert(slash.NOBLENEXTRPS.aliases[1]=="rps")
    local f=OpenWithOptions()
    -- Five steps starting with the race; no text input and no equipment step (starter vendor).
    assert(f.shown and f.parent==UIParent and C.step==1 and #C.STEPS==5 and #f.tabs==5)
    assert(C.STEPS[1].key=="race" and C.STEPS[5].key=="confirm" and C.Wizard.nameBox==nil)
    for _,step in ipairs(C.STEPS) do assert(step.key~="starter", "no equipment step") end
    for _,frame in ipairs(frames) do assert(frame.kind~="EditBox","no EditBox may remain") end
    assert(not f.back.enabled and not f.next.enabled and f.stepError.text:find("Выберите расу",1,true))
    -- Race rows are clickable buttons with the size on the right; unfinished entries show the reason.
    local human=FindRow("Человек"); assert(human.kind=="Button" and human.enabled and human.Bg.shown and not human.Selected.shown)
    local panda=FindRow("Пандарен"); assert(Has(RowText(panda),"каталог не завершён") and not panda.enabled)
    panda.scripts.OnClick(panda); assert(C.draft.race==nil)
    assert(Has(RowText(FindRow("Таурен")),"размер: большой"))
    Choose("Таурен"); assert(C.draft.race=="tauren" and not f.next.enabled)
    assert(FindRow("Таурен").Selected.shown and FindRow("Таурен").Label.text:find("ffd100",1,true))
    assert(not C.Wizard.Plain(FindRow("Таурен").Label.text):find(">",1,true), "selection is shown by colour, not a marker")
    -- Racial features open indented right under the selected race; other races' features stay hidden.
    local order={}
    for i,row in ipairs(C.Wizard.rows) do if row.shown then order[#order+1]=row end end
    local at; for i,row in ipairs(order) do if row.Label.text:find("Таурен",1,true) then at=i end end
    assert(order[at+1].entry.header and order[at+1].entry.indent==18 and order[at+1].Label.text:find("выберите одну",1,true))
    assert(order[at+2].Label.text:find("Традиции предков",1,true) and order[at+2].entry.indent==18)
    assert(order[at+2].Right.text:find("Мастерства",1,true))
    assert(not pcall(FindRow,"Гибкость"), "features of other races are not listed")
    assert(order[at].entry.icon=="atlas:raceicon128-tauren-male")
    -- Hovering an unselected row shows the POI-style card; the selected row does not repeat it.
    local human=FindRow("Человек"); human.scripts.OnEnter(human)
    local hover=C.Wizard.hover
    assert(hover and hover.shown and hover.data.title=="Человек" and Has(hover.data.body,"Гибкость"))
    assert(hover.data.meta=="Размер: средний")
    human.scripts.OnLeave(human); assert(not hover.shown)
    Choose("Традиции предков"); assert(C.draft.racialFeature=="tauren_a" and f.next.enabled)
    assert(f.stepError.text:find("Шаг заполнен",1,true))
    -- The chosen feature gets an inline card under the feature list.
    local card=C.Wizard.cards[1]
    assert(card.shown and card.data.title=="Традиции предков" and card.data.body=="+1 очко"
        and Has(card.data.meta,"+1 очко Мастерства"))
    -- A stub race gets its single default feature automatically and a grey tag.
    Choose("Орк"); assert(C.draft.race=="orc" and C.draft.racialFeature=="orc_default" and f.next.enabled)
    assert(Has(RowText(FindRow("Орк")),C.STUB_TAG) and Has(RowText(FindRow("Без расовых особенностей")),C.STUB_TAG))
    -- Changing the race drops the dependent feature.
    Choose("Человек"); assert(C.draft.race=="human" and C.draft.racialFeature==nil)
    Choose("Стойкость")
    Click(f.next); assert(C.step==2 and f.back.enabled)
    Choose("Одарённость"); assert(not f.next.enabled and f.stepError.text:find("дополнительный выбор",1,true))
    Choose("Лёд"); assert(C.draft.traitChoice=="frost" and f.next.enabled)
    Choose("Любимец судьбы"); assert(C.draft.traitChoice==nil)
    Click(f.back); assert(C.step==1)
    -- Closing and reopening keeps the session draft.
    C.Close(); assert(not f.shown)
    slash.NOBLENEXTRPS.handler("create")
    assert(f.shown and C.draft.race=="human" and C.draft.trait=="lucky" and C.draft.rpName==nil)
    H.CharacterOptions(nil,Options())
    assert(C.draft.racialFeature=="human_b", "a reload of the same catalog keeps valid choices")
    slash.NOBLENEXTRPS.handler("help"); assert(ns.print:find("/rps create",1,true) and ns.print:find("/rps race reset",1,true))
end
function cases.missing_checklist()
    local f=OpenWithOptions()
    -- Local checklist before any server answer; tabs of incomplete steps are marked.
    local text=Sheet()
    assert(Has(text,"Ещё не указано:") and Has(text,"* Раса") and Has(text,"* Расовая особенность")
        and Has(text,"* Общая черта") and Has(text,"осталось распределить 2 из 2") and Has(text,"* Архетип"))
    assert(not Has(text,"Есть незаполненные шаги"))
    assert(f.tabs[1].text:find("ff9933",1,true) and f.tabs[1].text:find("*",1,true))
    assert(not f.tabs[5].text:find("*",1,true))
    Choose("Человек"); Choose("Гибкость")
    text=Sheet(); assert(not Has(text,"* Раса") and Has(text,"* Общая черта"))
    assert(not f.tabs[1].text:find("*",1,true))
    Click(f.tabs[2]); Choose("Одарённость")
    assert(Has(Sheet(),"Дополнительный выбор черты"))
    -- A fresh server preview with missing[] replaces the local list.
    RunTimers(C.PREVIEW_DELAY); assert(Last()[2]=="PreviewCharacter")
    H.CharacterPreview(nil,{ok=false,errors={},missing={
        {step=2,field="traitChoice",message_ru="Выбор для «Одарённости»"},
        {step="archetype",field="archetype",message_ru="Архетип не выбран"}}})
    text=Sheet()
    assert(Has(text,"* Выбор для «Одарённости» (шаг 2)") and Has(text,"* Архетип не выбран (шаг 4)"))
    assert(not Has(text,"Стартовый набор") and not f.tabs[5].text:find("*",1,true))
    assert(not Has(text,"Общая черта") and f.tabs[4].text:find("*",1,true) and not f.tabs[3].text:find("*",1,true))
    -- The next local change falls back to the local list until the server answers again.
    Choose("Лёд"); text=Sheet()
    assert(not Has(text,"Выбор для") and Has(text,"* Архетип") and Has(text,"осталось распределить"))
end
function cases.preview_and_errors()
    local f=OpenWithOptions()
    Click(f.tabs[1]); Choose("Таурен"); Choose("Традиции предков")
    local before=#calls
    RunTimers(C.PREVIEW_DELAY)
    assert(#calls==before+1, "debounced: one preview for several changes")
    local call=Last()
    assert(call[2]=="PreviewCharacter" and call[3].race=="tauren" and call[3].racialFeature=="tauren_a")
    assert(call[3].rpName==nil and call[3].mastery.skill==0 and call[3].mastery.craft==0 and #call[3].starterItems==0)
    -- The extra Tauren point is a hint; the server still decides.
    Click(f.tabs[3])
    assert(C.MasteryBudget()==3 and C.Wizard.mastery[1].shown)
    for _=1,3 do Click(C.Wizard.mastery[1].plus) end
    assert(C.draft.mastery.skill==3 and not C.Wizard.mastery[2].plus.enabled)
    Click(f.tabs[1]); Choose("Мощь")
    assert(C.MasteryBudget()==2 and C.draft.mastery.skill==2, "budget recalculated after the feature change")
    RunTimers(C.PREVIEW_DELAY)
    assert(Last()[2]=="PreviewCharacter" and Last()[3].mastery.skill==2)
    -- Errors of unopened steps stay hidden; opened steps show them in Russian.
    H.CharacterPreview(nil,{ok=false,errors={
        {code="mastery_points_mismatch",field="mastery",message_ru="Нужно распределить ровно 2 очка Мастерства."},
        {code="required",field="archetype",message_ru="Выберите архетип."}}})
    assert(#C.VisibleErrors()==1 and f.tabs[3].text:find("ff5a5a",1,true))
    assert(Has(Sheet(),"Шаг 3: Нужно распределить") and not Has(Sheet(),"Шаг 4:"))
    Click(f.tabs[3]); assert(f.stepError.text:find("Нужно распределить ровно 2",1,true))
    Click(f.tabs[5]); assert(#C.VisibleErrors()==2 and f.confirm.shown and not f.confirm.enabled)
end
function cases.confirm_flow()
    local f=OpenWithOptions({creationState="legacy",revision=5})
    FillDraft(f)
    RunTimers(C.PREVIEW_DELAY)
    assert(Last()[2]=="PreviewCharacter")
    Click(f.tabs[5]); assert(f.confirm.shown and not f.next.shown and not f.confirm.enabled)
    H.CharacterPreview(nil,{ok=true,sheet={maxHealth=15,maxEnergy=10,accuracy=2,healing=0,evasion=-1,resistance=0,
        speed=10,armor=1,mastery={skill=1,knowledge=1,endurance=0,craft=0},abilitySlots=2,block="1+0+1",
        passive={"Мастер оружия: удар","Кровавое неистовство: +1 к Урону"}},
        warnings={{code="resources_kept",message_ru="Текущие ОЗ сохраняются"}}})
    -- Sheet in blocks with headers; signed values coloured; passives as separate paragraphs.
    local text=Sheet()
    for _,needle in ipairs({"Ресурсы","ОЗ: 15","Боевые бонусы","Меткость: +2","Уклонение: -1","Защита и движение",
        "Броня: 1","Мастерство","Навык: +1","Способности","Ячейки: 2","Особенности","Мастер оружия - удар",
        "Кровавое неистовство - +1 к Урону"}) do assert(Has(text,needle),needle) end
    assert(not Has(text,"Ещё не указано"))
    local colours={}
    for _,line in ipairs(C.Wizard.sheet.lines) do
        if line.Right.shown then colours[C.Wizard.Plain(line.Right.text)]=line.Right.text:match("^|cff(%x%x%x%x%x%x)") end
    end
    assert(colours["+2"]=="4cff4c" and colours["-1"]=="ff5a5a" and colours["0"]=="ffffff")
    -- Summary step blocks: origin, development, one item per line, warnings.
    local summary=C.Wizard.SummaryText()
    for _,needle in ipairs({"Происхождение","Раса: Человек","Размер: средний","Особенность: Гибкость","Развитие",
        "Черта: Любимец судьбы","Архетип: Боец","Мастерство","Навык: +1","Знание: +1","Внимание",
        "* Текущие ОЗ сохраняются","первый раз бесплатно"}) do assert(Has(summary,needle),needle) end
    assert(not Has(summary,"Выбор черты"), "no trait choice line for a trait without a choice")
    -- Every summary header has a divider under it.
    local dividers=0
    for _,line in ipairs(C.Wizard.summary.lines) do if line.Line.shown then dividers=dividers+1 end end
    assert(dividers==4, "four headers: origin, development, mastery, warnings")
    assert(f.confirm.enabled)
    Click(f.confirm)
    local call=Last()
    assert(call[2]=="ConfirmCharacter" and call[3].archetype=="fighter" and call[3].trait=="lucky" and #call[3].starterItems==0)
    assert(not Has(summary,"Снаряжение"))
    assert(call[3].rpName==nil, "rpName is never sent")
    assert(call[4]==5 and type(call[5])=="string" and call[5]~="")
    assert(not f.confirm.enabled and f.confirm.text=="Сохранение…" and not f.back.enabled)
    local sent=#calls; f.confirm.scripts.OnClick(f.confirm); assert(#calls==sent, "no double submit")
    -- revision_conflict keeps the draft and reloads the options.
    H.CharacterError(nil,{code="revision_conflict",message_ru="Профиль изменился.",requestId=call[5]})
    assert(Last()[2]=="RequestCharacterOptions" and C.draft.archetype=="fighter" and f.status.text:find("Профиль изменился",1,true))
    H.CharacterOptions(nil,Options({creationState="legacy",revision=6}))
    assert(f.confirm.enabled)
    Click(f.confirm)
    local second=Last(); assert(second[4]==6 and second[5]~=call[5])
    -- A foreign requestId does not unlock; a timeout does and the retry reuses the requestId.
    H.CharacterError(nil,{code="rate_limited",requestId="other"}); assert(not f.confirm.enabled)
    RunTimers(C.CONFIRM_TIMEOUT)
    assert(f.confirm.enabled and f.status.text:find("не ответил",1,true))
    Click(f.confirm); assert(Last()[5]==second[5])
    -- Generic RPS_Combat error for the same requestId unlocks the button.
    H.Error(nil,{code="rate_limited",requestId=second[5]})
    assert(f.confirm.enabled)
    Click(f.confirm)
    H.CharacterConfirmed(nil,{requestId=Last()[5],revision=7,creation={state="complete",revision=7,starterGranted=true},
        profile={archetype="fighter",raceId="human",revision=41}})
    assert(not f.shown and C.draft==nil and C.GetState()=="complete" and ns.print:find("подтверждён",1,true))
    H.SyncProfile(nil,Profile("complete",7))
    slash.NOBLENEXTRPS.handler("create"); H.CharacterOptions(nil,Options({creationState="complete",revision=7}))
    Click(f.tabs[5]); assert(not f.confirm.enabled and f.status.text:find("уже подтверждён",1,true))
end
function cases.character_frame_states()
    local parent=Frame("Frame")
    assert(R.RenderSheet(parent))
    assert(R.sheet.rows[1].Value.text=="Раса не выбрана" and R.sheet.rows[2].Value.text=="Архетип не выбран")
    local box=R.creationBox
    assert(box and box.shown and box.Label.text:find("Старый профиль",1,true))
    assert(box.Button.text=="Настроить RP-персонажа" and R.sheet.point[5]==52)
    Click(box.Button); assert(Wizard().shown and Last()[2]=="RequestCharacterOptions")
    C.Close()
    H.SyncProfile(nil,Profile("none",5)); R.RenderSheet(parent)
    assert(box.shown and box.Label.text=="RP-персонаж не настроен" and R.sheet.rows[1].Value.text=="Раса не выбрана")
    H.SyncProfile(nil,Profile("reconfigure",6)); R.RenderSheet(parent)
    assert(box.shown and box.Label.text=="Разрешена перенастройка" and R.sheet.rows[1].Value.text=="Человек")
    H.SyncProfile(nil,Profile("complete",7)); R.RenderSheet(parent)
    assert(not box.shown and R.sheet.rows[2].Value.text=="Боец" and R.sheet.point[5]==6)
    -- Without creationState the sheet keeps the old display and asks the server once for the state.
    C.state=nil; C.options=nil; C.probed=nil
    local before=#calls
    H.SyncProfile(nil,Profile(nil,8)); R.RenderSheet(parent)
    assert(not box.shown and R.sheet.rows[1].Value.text=="Человек")
    RunTimers(1)
    assert(#calls==before+1 and Last()[2]=="RequestCharacterOptions")
    H.CharacterOptions(nil,Options({creationState="legacy",revision=8})); R.RenderSheet(parent)
    assert(box.shown and R.sheet.rows[1].Value.text=="Раса не выбрана")
    -- A newer SyncProfile.creation wins over older options; older sync loses to newer options.
    H.SyncProfile(nil,Profile("complete",9)); R.RenderSheet(parent)
    assert(C.GetState()=="complete" and not box.shown)
    H.SyncProfile(nil,Profile("legacy",3)); assert(C.GetState()=="legacy")
    -- Backward compatibility: profile.creationState without a creation table.
    C.state=nil
    local old=Profile(nil); old.profile.creationState="none"
    H.SyncProfile(nil,old); R.RenderSheet(parent)
    assert(C.syncCreation==nil and C.GetState()=="none" and box.Label.text=="RP-персонаж не настроен")
    assert(not box.ResetButton.shown, "no reset button without raceUpdateAvailable")
end
local function RaceProfile(state,revision,extra)
    local creation={state=state,revision=revision,catalogVersion="",starterGranted=true,confirmedAt=0,rpLevel=1}
    for k,v in pairs(extra or {}) do creation[k]=v end
    return Profile(nil,nil,creation)
end
function cases.scope_race_locking()
    H.SyncProfile(nil,RaceProfile("reconfigure",10,{scope="race",raceUpdateAvailable=false}))
    assert(C.Scope()=="race")
    local f=OpenWithOptions({creationState="reconfigure",revision=10,scope="race",
        draft={trait="lucky",archetype="fighter",mastery={skill=1,knowledge=1}}})
    assert(C.step==1 and C.draft.trait=="lucky" and C.draft.race==nil)
    assert(Has(C.Wizard.desc.text,"Обновление расовых данных"))
    -- Only the race and the summary are open; locked steps refuse navigation and edits.
    for i=2,4 do assert(not f.tabs[i].enabled and f.tabs[i].text:find("999999",1,true),"tab "..i.." locked") end
    assert(f.tabs[1].enabled and f.tabs[5].enabled)
    assert(C.GoTo(2)==false and C.step==1)
    assert(C.SetField("trait","gifted")==false and C.draft.trait=="lucky")
    assert(C.ToggleStarter==nil and C.AdjustMastery("craft",1)==false)
    Choose("Орк"); assert(C.draft.racialFeature=="orc_default" and f.next.enabled)
    Click(f.next); assert(C.step==5, "Далее skips locked steps")
    Click(f.back); assert(C.step==1)
    -- A step that becomes incomplete (Tauren free mastery point) is unlocked so the player is not stuck.
    Choose("Таурен"); Choose("Традиции предков")
    assert(f.tabs[3].enabled and not f.tabs[2].enabled)
    Click(f.tabs[3]); assert(C.step==3 and C.AdjustMastery("craft",1))
    -- Reopening in scope race always starts on the race step.
    C.Close(); slash.NOBLENEXTRPS.handler("create"); assert(C.step==1)
    -- Missing fields keep the old behaviour: no scope, every step open.
    H.SyncProfile(nil,RaceProfile("reconfigure",11,{}))
    C.state.scope=nil
    assert(C.Scope()==nil and C.GoTo(2) and f.tabs[2].enabled)
end
function cases.race_reset()
    local parent=Frame("Frame")
    H.SyncProfile(nil,RaceProfile("complete",7,{raceUpdateAvailable=true})); R.RenderSheet(parent)
    local box=R.creationBox
    assert(box.shown and not box.Button.shown and box.ResetButton.shown and box.ResetButton.text=="Сбросить расовые данные")
    assert(Has(box.Label.text,"обновление расовых данных") and R.sheet.point[5]==52)
    -- The button only asks for confirmation; the request goes out after OnAccept.
    local before=#calls
    Click(box.ResetButton)
    assert(popups[#popups]==C.RESET_POPUP and #calls==before)
    local dialog=StaticPopupDialogs[C.RESET_POPUP]
    assert(dialog and dialog.button1=="Сбросить" and dialog.hideOnEscape)
    dialog.OnAccept()
    local call=Last(); assert(call[2]=="ResetRaceData" and type(call[3])=="string" and C.resetPending==call[3])
    dialog.OnAccept(); assert(#calls==before+1, "no double reset while pending")
    H.CharacterError(nil,{code="race_preset_current",message_ru="Расовые данные уже актуальны.",requestId=call[3]})
    assert(C.resetPending==nil and Has(ns.print,"уже актуальны"))
    -- /rps race reset does the same; SyncProfile with scope race opens the wizard on the race step.
    local shown=#popups
    slash.NOBLENEXTRPS.handler("race reset")
    assert(#popups==shown+1 and popups[#popups]==C.RESET_POPUP)
    dialog.OnAccept(); local second=Last(); assert(second[2]=="ResetRaceData" and second[3]~=call[3])
    H.SyncProfile(nil,RaceProfile("reconfigure",8,{scope="race",raceUpdateAvailable=false}))
    assert(C.resetPending==nil and Wizard().shown and C.step==1 and Last()[2]=="RequestCharacterOptions")
    assert(Has(ns.print,"сброшены"))
    -- Both setup and reset needed: two buttons stacked.
    C.Close()
    H.SyncProfile(nil,RaceProfile("reconfigure",9,{raceUpdateAvailable=true})); R.RenderSheet(parent)
    assert(box.Button.shown and box.ResetButton.shown and R.sheet.point[5]==76)
    -- Without raceUpdateAvailable the button hides and the slash only explains.
    H.SyncProfile(nil,RaceProfile("complete",10,{})); R.RenderSheet(parent)
    assert(not box.shown)
    shown=#popups; slash.NOBLENEXTRPS.handler("race reset")
    assert(#popups==shown and Has(ns.print,"недоступно"))
    -- A timeout unlocks a pending reset.
    H.SyncProfile(nil,RaceProfile("complete",11,{raceUpdateAvailable=true}))
    C.ResetRace(); assert(C.resetPending)
    RunTimers(C.CONFIRM_TIMEOUT); assert(C.resetPending==nil and Has(ns.print,"не ответил"))
    -- RaceDataReset answer (before the next SyncProfile) also opens the wizard in scope race.
    local id=C.ResetRace()
    H.RaceDataReset(nil,{requestId="foreign",state="reconfigure",revision=12,scope="race"}); assert(C.resetPending==id)
    H.RaceDataReset(nil,{requestId=id,targetGuid=1,state="reconfigure",revision=12,scope="race"})
    assert(C.resetPending==nil and C.Scope()=="race" and Wizard().shown and C.step==1)
end
-- Contract: answers are built by the real server module (05_RPS_Creation + resolver) from the client's wire draft.
function cases.server_contract()
    package.path=ROOT.."/NobleNextLua/?.lua;"..package.path
    local Cr=require("Modules.RPS_Combat.05_RPS_Creation")
    local V=require("Modules.RPS_Combat.04_RPS_Resolver")
    local rec={state="legacy",revision=0,catalogVersion="",rpName="",starterGranted=false,confirmedAt=0,
        race="human",racialFeature="",archetype="fighter",traits={""},traitChoice="",
        mastery={skill=0,knowledge=0,endurance=0,craft=0}}
    local function Sync(r) local s=Cr.Summary(r); s.rpLevel=1; return Profile(nil,nil,s) end
    local function Localize(errors)
        local out={}
        for i,e in ipairs(errors) do out[i]={code=e.code,field=e.field,message_ru=Cr.Message(e.code)} end
        return out
    end
    local function Serve(draft)
        local norm,errors=Cr.NormalizeDraft(draft,1)
        if not norm then H.CharacterPreview(nil,{ok=false,errors=Localize(errors)}); return nil end
        local sheet=assert(V.Resolve(norm.input))
        H.CharacterPreview(nil,{ok=true,sheet=Cr.SheetSummary(sheet),catalogVersion=Cr.Options.catalogVersion,
            warnings={{code="resources_kept",message_ru=Cr.Message("resources_kept")}}})
        return norm
    end
    H.SyncProfile(nil,Sync(rec))
    assert(C.syncCreation.state=="legacy" and C.GetState()=="legacy")
    local parent=Frame("Frame"); R.RenderSheet(parent)
    assert(R.creationBox.shown and R.sheet.rows[1].Value.text=="Раса не выбрана")
    slash.NOBLENEXTRPS.handler("create")
    local options={}
    for k,v in pairs(Cr.Options) do options[k]=v end
    options.state=Cr.Summary(rec); options.state.creationState=rec.state
    options.state.draft={rpName="",archetype="fighter"}; options.state.rpLevel=1
    H.CharacterOptions(nil,options)
    local f=Wizard()
    assert(C.draft.archetype=="fighter" and C.draft.race==nil, "legacy draft seeds the wizard")
    local tauren=C.Find(options.races,"tauren")
    local free; for _,feat in ipairs(tauren.features) do if feat.masteryFree then free=feat end end
    assert(free, "server marks the Tauren free point as masteryFree")
    Click(f.tabs[1]); Choose(tauren.name); Choose(free.name)
    assert(C.MasteryBudget()==3)
    local trait; for _,t in ipairs(options.traits) do if not t.needsChoice then trait=t; break end end
    Click(f.tabs[2]); Choose(trait.name)
    RunTimers(C.PREVIEW_DELAY)
    assert(Last()[2]=="PreviewCharacter" and not Serve(Last()[3]))
    Click(f.tabs[3])
    assert(f.stepError.text:find(Cr.Message("mastery_points_mismatch"),1,true))
    for i=1,3 do Click(C.Wizard.mastery[i].plus) end
    RunTimers(C.PREVIEW_DELAY)
    assert(Serve(Last()[3]) and C.preview.ok and #C.VisibleErrors()==0)
    Click(f.tabs[5])
    assert(Has(Sheet(),"ОЗ: ") and Has(Sheet(),"Блок: ") and Has(Sheet(),"Ресурсы") and not Has(Sheet(),"table:"))
    assert(f.confirm.enabled)
    Click(f.confirm)
    local call=Last()
    assert(call[2]=="ConfirmCharacter" and call[4]==0 and call[5]:match("^[%w_-]+$"))
    local norm=assert(Cr.NormalizeDraft(call[3],1))
    assert(norm.n.race=="tauren" and norm.n.mastery.knowledge==1 and #norm.items==0)
    -- invalid_draft from Confirm carries field errors and unlocks the button.
    H.CharacterError(nil,{code="invalid_draft",message_ru=Cr.Message("invalid_draft"),requestId=call[5],
        errors=Localize({{code="mastery_points_mismatch",field="mastery"}})})
    assert(not C.pending and f.tabs[3].text:find("ff5a5a",1,true) and f.status.text:find(Cr.Message("invalid_draft"),1,true))
    RunTimers(C.PREVIEW_DELAY); Serve(Last()[3]); Click(f.confirm)
    call=Last()
    local done={}; for k,v in pairs(rec) do done[k]=v end
    done.state,done.revision,done.race,done.racialFeature,done.traits=
        "complete",1,"tauren",free.key,{trait.key}
    done.mastery={skill=1,knowledge=1,endurance=1,craft=0}
    H.CharacterConfirmed(nil,{requestId=call[5],revision=1,creation=Cr.Summary(done),profile={archetype="fighter",raceId="tauren"}})
    assert(C.GetState()=="complete" and C.state.revision==1 and not f.shown)
    H.SyncProfile(nil,Sync(done)); R.profile.raceId="tauren"; R.RenderSheet(parent)
    assert(not R.creationBox.shown and R.sheet.rows[1].Value.text=="Таурен")
end
function cases.error_routing()
    local f=OpenWithOptions()
    assert(C.ErrorStep({field="starterItems[2]"})==5 and C.ErrorStep({field="traits"})==2
        and C.ErrorStep({field="mastery.skill"})==3 and C.ErrorStep({field="rpLevel"})==5
        and C.ErrorStep({field="rpName"})==5 and C.ErrorStep({step="archetype"})==4 and C.ErrorStep({step=2})==2)
    Click(f.tabs[1]); Choose("Человек"); Choose("Гибкость")
    RunTimers(C.PREVIEW_DELAY); assert(C.inflight==1)
    -- Preview rate_limited comes without requestId: resend, no status, no unlock of anything else.
    local before=#calls
    H.CharacterError(nil,{code="rate_limited",message_ru="Слишком частые запросы"})
    assert(C.inflight==0 and C.status==nil)
    RunTimers(C.PREVIEW_DELAY); assert(#calls==before+1 and Last()[2]=="PreviewCharacter")
    -- Options failure without requestId stops loading and explains why.
    H.CharacterError(nil,{code="creation_unavailable",message_ru="Создание персонажа недоступно: схема БД не применена"})
    assert(not C.loading and f.status.text:find("схема БД",1,true))
    -- The local hint and the same server error are shown once.
    Choose("Таурен")
    H.CharacterPreview(nil,{ok=false,errors={{code="racial_feature_required",field="racialFeature",
        message_ru="Выберите одну расовую особенность"}}})
    local _,count=C.Wizard.Plain(f.stepError.text):gsub("Выберите одну расовую особенность","")
    assert(count==1, "duplicate step message: "..f.stepError.text)
    -- An error about an empty choice is already in the checklist, so the sheet has no "Ошибки" block for it.
    assert(not Has(Sheet(),"Ошибки") and Has(Sheet(),"Ещё не указано:"))
end
function cases.archetype_reset()
    local parent=Frame("Frame")
    H.SyncProfile(nil,RaceProfile("complete",7,{archetypeResetCost=0})); R.RenderSheet(parent)
    local box=R.creationBox
    assert(box.shown and box.ArchetypeButton.shown and not box.Button.shown and not box.ResetButton.shown)
    assert(Has(box.ArchetypeButton.text,"бесплатно") and box.Label.text=="" and R.sheet.point[5]==36)
    -- The button only asks; the popup names the price and sends it as the expected cost.
    local before=#calls
    Click(box.ArchetypeButton)
    local dialog=StaticPopupDialogs[C.ARCHETYPE_POPUP]
    assert(popups[#popups]==C.ARCHETYPE_POPUP and #calls==before)
    assert(dialog.button1=="Сменить" and dialog.hideOnEscape and Has(dialog.text,"Стоимость: бесплатно"))
    dialog.OnAccept(nil,0)
    local call=Last(); assert(call[2]=="ResetArchetype" and call[3]==0 and C.archetypeResetPending==call[4])
    dialog.OnAccept(nil,0); assert(#calls==before+1, "no double reset while pending")
    H.CharacterError(nil,{code="not_enough_money",message_ru="Недостаточно денег для смены архетипа",requestId=call[4]})
    assert(C.archetypeResetPending==nil and Has(ns.print,"Недостаточно денег"))
    -- A paid reset: price on the button and in the popup; /rps archetype reset does the same.
    H.SyncProfile(nil,RaceProfile("complete",8,{archetypeResetCost=1000})); R.RenderSheet(parent)
    assert(Has(box.ArchetypeButton.text,"10 с."))
    slash.NOBLENEXTRPS.handler("archetype reset")
    assert(popups[#popups]==C.ARCHETYPE_POPUP and Has(dialog.text,"10 с."))
    dialog.OnAccept(nil,1000); local paid=Last(); assert(paid[2]=="ResetArchetype" and paid[3]==1000)
    -- SyncProfile with scope archetype opens the wizard on the archetype step, other steps locked.
    H.SyncProfile(nil,RaceProfile("reconfigure",9,{scope="archetype"}))
    assert(C.archetypeResetPending==nil and Wizard().shown and C.step==4 and Last()[2]=="RequestCharacterOptions")
    assert(Has(ns.print,"Архетип сброшен"))
    H.CharacterOptions(nil,Options({creationState="reconfigure",revision=9,scope="archetype",
        draft={race="human",racialFeature="human_a",trait="lucky",mastery={skill=1,knowledge=1}}}))
    local f=Wizard()
    assert(C.step==4 and C.draft.archetype==nil and Has(C.Wizard.desc.text,"Смена архетипа"))
    for i=1,3 do assert(not f.tabs[i].enabled,"tab "..i.." locked") end
    assert(f.tabs[4].enabled and f.tabs[5].enabled and C.SetField("race","tauren")==false and C.GoTo(1)==false)
    assert(FindRow("Целитель").entry.icon:find("FlashHeal",1,true))
    Choose("Целитель"); assert(C.draft.archetype=="healer")
    local card=C.Wizard.cards[1]
    assert(card.shown and card.data.title=="Целитель" and Has(card.data.meta,"Целебные чары") and Has(card.data.body,"Ж"))
    Click(f.next); assert(C.step==5)
    -- While the reconfigure is pending the sheet offers setup, not another archetype reset.
    R.RenderSheet(parent); assert(box.Button.shown and not box.ArchetypeButton.shown)
    C.Close()
    -- ArchetypeReset answer (before the next SyncProfile) also opens the archetype step.
    H.SyncProfile(nil,RaceProfile("complete",10,{archetypeResetCost=1500}))
    local id=C.ResetArchetype(); assert(Last()[3]==1500)
    H.ArchetypeReset(nil,{requestId="foreign",state="reconfigure",revision=11,scope="archetype"})
    assert(C.archetypeResetPending==id)
    H.ArchetypeReset(nil,{requestId=id,state="reconfigure",revision=11,scope="archetype",cost=1500})
    assert(C.archetypeResetPending==nil and C.Scope()=="archetype" and Wizard().shown and C.step==4)
    -- A timeout unlocks a pending reset; without a price the slash only explains.
    C.Close()
    H.SyncProfile(nil,RaceProfile("complete",12,{archetypeResetCost=500}))
    C.ResetArchetype(); assert(C.archetypeResetPending)
    RunTimers(C.CONFIRM_TIMEOUT); assert(C.archetypeResetPending==nil and Has(ns.print,"не ответил"))
    H.SyncProfile(nil,RaceProfile("complete",13,{}))
    local shown=#popups; slash.NOBLENEXTRPS.handler("archetype reset")
    assert(#popups==shown and Has(ns.print,"недоступна"))
end
return cases
