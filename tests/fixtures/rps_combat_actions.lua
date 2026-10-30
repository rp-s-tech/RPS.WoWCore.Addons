-- R02: action spells (Атака/Избегание/Блок) separate from the ten standalone dice.
-- Server cases load the real WORLD runtime with native-commit and AIO doubles; client cases
-- load RPSClient + CombatPrompt with frame doubles. Each case runs in a fresh Lua state.
package.path=ROOT.."/NobleNextLua/?.lua;"..package.path
local cases={}

local transactions,messages,timers,events={},{},{},{}
local players,queue={},{}
local clock,ms=1000,0
local handlers,R,C,S,M
local spellStatus={}
local definitions

local function Query(rows)
    local i,q=1,{}
    function q:GetString(col) return rows[i][col+1] end
    q.GetUInt8,q.GetUInt32,q.GetUInt64,q.GetInt32=q.GetString,q.GetString,q.GetString,q.GetString
    function q:NextRow() i=i+1; return rows[i]~=nil end
    return q
end
local function Definitions()
    definitions={}
    for i,row in ipairs({{"accuracy","combat",1500001,"3d6"},{"evasion","combat",1500003,"3d6"},
        {"resistance","combat",1500004,"3d6"},{"skill","mastery",1500005,"3d6"},{"shield_block","weapon",1500010,"shield"}}) do
        definitions[i]={row[1],row[2],i,row[1],"dice",row[3],row[4],0,""}
    end
end
local function Later(delta) ms=ms+(delta or 500) end
local function Player(id)
    local p={id=id,context="scene"}
    function p:GetGUIDLow() return self.id end
    function p:GetItemByPos() return nil end
    function p:GetGUID() return "Player-"..self.id end
    function p:GetName() return "P"..self.id end
    function p:GetSelection() return self.target end
    function p:ToPlayer() return self end
    function p:ToCreature() end
    p.known,p.notes,p.chat={},{},{}
    function p:HasSpell(spell) return self.known[spell]==true end
    function p:LearnSpell(spell) self.known[spell]=true end
    function p:SendNotification(text) self.notes[#self.notes+1]=text end
    function p:SendBroadcastMessage(text) self.chat[#self.chat+1]=text end
    players[#players+1]=p
    return p
end
local function Npc(static,evasion,armor)
    local npc={context="scene"}
    function npc:GetGUID() return "Creature-A" end
    function npc:GetGUIDLow() return "42" end
    function npc:GetDBTableGUIDLow() return "7" end
    function npc:GetEntry() return 100 end
    function npc:GetMapId() return 1 end
    function npc:GetInstanceId() return 2 end
    function npc:GetName() return "N" end
    function npc:ToPlayer() end
    function npc:ToCreature() return self end
    local p=S.BuildCreatureProfile(npc)
    p.isStaticThreshold,p.stats.evasion,p.armor=static,evasion,armor or 0
    S.RuntimeNpcs[p.runtimeKey]=p
    return npc,p.runtimeKey
end
-- Deterministic dice: every math.random call must be listed; leftovers fail the case.
local rolls,rollIndex={},0
local function Dice(list) rolls,rollIndex=list,0 end
local function DiceDone() assert(rollIndex==#rolls,"unused dice "..rollIndex.."/"..#rolls) end
local function Flush(ok)
    local transaction=table.remove(transactions,1); assert(transaction,"no transaction")
    transaction.callback(ok~=false)
end
local function FlushAll() local n=0; while #transactions>0 do Flush(); n=n+1 end; return n end
local function Last(method,player)
    for i=#messages,1,-1 do
        local msg=messages[i]
        if msg.method==method and (not player or msg.player==player) then return msg.payload end
    end
end
local function Count(method,player)
    local n=0
    for _,msg in ipairs(messages) do if msg.method==method and (not player or msg.player==player) then n=n+1 end end
    return n
end
local function LastError(player) local e=Last("Error",player); return e and e.code end
local function Poll() for _,fn in ipairs(timers) do fn() end end
local function Cast(player,spellId,rejected)
    queue[#queue+1]={player=player,spellId=spellId,rejected=rejected}
    Later(); Poll()
end

local a,b,c
local function Profile(player)
    local p=assert(S.BuildDefaultPlayerProfile(player)); p.revision=1; p.name=player:GetName()
    p.stats.accuracy,p.stats.evasion,p.stats.resistance=2,1,2
    p.armor,p.weaponDice=1,"1d8"
    S.PlayerProfiles[p.guid]=p
    return p
end
local function Current(player) return S.PlayerProfiles[player.id] end
local function Reset()
    R.PendingAttacks,R.Seen,R.LastReaction,R.Locks={},{},{},{}
    Profile(a); Profile(b); Profile(c)
    transactions,messages={},{}
    for _,p in ipairs(players) do p.notes,p.chat={},{} end
end

local function Server()
    os.time=function() return clock end
    GetCurrTime=function() return ms end
    math.random=function(low,high)
        rollIndex=rollIndex+1
        local value=rolls[rollIndex]
        assert(value and value>=low and value<=high,"unexpected die #"..rollIndex)
        return value
    end
    RpsRuntimeEpoch=function() return "epoch" end
    RpsDiceSpellStatus=function(id)
        local r=spellStatus[id] or ((id>=1500001 and id<=1500013) and "ok" or "no_spellinfo")
        return r=="ok",r
    end
    RpsIsDiceSpell=function(id) return RpsDiceSpellStatus(id) end
    GetStateMapId=function() return -1 end
    GetPlayersInWorld=function() return players end
    GetPlayerByGUID=function(guid) for _,p in ipairs(players) do if p:GetGUID()==guid then return p end end end
    RpsTargetContext=function(player,target,edit) return player.context==target.context and not edit end
    RpsPollDiceCasts=function() local q=queue; queue={}; return q end
    RegisterPlayerEvent=function(id,fn) events[id]=fn end
    CreateLuaEvent=function(fn) timers[#timers+1]=fn end
    RpsCommitAsync=function(pool,sql,callback) transactions[#transactions+1]={pool=pool,sql=sql,callback=callback} end
    Definitions()
    WorldDBQuery=function(sql)
        if sql:find("FROM rps_stat_definitions",1,true) then return Query(definitions) end
        if sql:find("COUNT",1,true) then return Query({{0}}) end
    end
    CharDBQuery=function(sql)
        if sql:find("COUNT",1,true) then return Query({{0,0}}) end
    end
    local N={IsMainState=function() return true end,Log=function() end,HasStaffPermission=function(p) return p.admin end,
        AIO={AddHandlers=function(name,h) assert(name=="RPS_Combat" and not handlers); handlers=h; return h end,
            Handle=function(player,_,method,payload) messages[#messages+1]={player=player,method=method,payload=payload} end}}
    package.loaded.NobleNext=N
    _G.NN_BOOTSTRAP_ACTIVE=true
    R=require("Modules.RPS_Combat.Init")
    C,S,M=R.Config,R.Storage,R.Combat
    assert(R.ready,R.unavailableReason)
    a,b,c=Player("4294967297"),Player("4294967298"),Player("4294967299")
    a.admin=true
    Reset()
end

-- a attacks b with attack dice d (3d6 + Меткость 2); returns the committed pending attack.
local function Attack(attacker,defender,d)
    attacker.target=defender
    Later(); Dice(d)
    handlers.PerformAction(attacker,"attack",{revision=Current(attacker).revision},"atk-"..ms)
    DiceDone(); FlushAll()
    local result=Last("Committed",attacker).result
    assert(result.kind=="attack" and result.attackId,tostring(LastError(attacker)))
    return result.attackId,R.PendingAttacks[result.attackId]
end

function cases.b01_standalone_accuracy()
    Server()
    -- Window roll with a selected PvP target: a plain check, no pending attack, no damage.
    a.target=b
    Later(); Dice({3,4,5})
    handlers.RollStat(a,"accuracy",false,"roll",1)
    DiceDone(); assert(FlushAll()==1)
    local result=Last("Committed",a).result
    assert(result.kind=="roll" and result.statKey=="accuracy" and result.total==14)
    assert(next(R.PendingAttacks)==nil and Count("PromptDefenseReaction")==0 and Current(b).curHealth==15)
    -- The native dice spell 1500001 follows the same standalone path.
    Dice({1,2,4}); Cast(a,1500001); DiceDone(); FlushAll()
    assert(Last("Committed",a).result.kind=="roll" and next(R.PendingAttacks)==nil)
    -- Without a target the check works the same.
    a.target=nil
    Dice({1,2,4}); Cast(a,1500001); DiceDone(); FlushAll()
    assert(Last("Committed",a).result.total==9 and Current(b).curHealth==15)
end

function cases.b02_npc_static_threshold()
    Server()
    local npc,key=Npc(true,10,2)
    a.target=npc
    -- 4+3+5+2 = 14 > 10: hit, 1d8=5 minus Броня 2 once = 3 damage. No extra base 10.
    Later(); Dice({4,3,5,5})
    handlers.PerformAction(a,"attack",{revision=1},"npc-hit")
    DiceDone(); FlushAll()
    local result=Last("Committed",a).result
    assert(result.kind=="attack" and result.hit==true and result.defense==10 and result.damage==3)
    assert(S.RuntimeNpcs[key].curHealth==7 and Count("PromptDefenseReaction")==0)
    -- D18 tie: 4+2+2+2 = 10 is not > 10, no damage die is rolled.
    Later(); Dice({4,2,2})
    handlers.PerformAction(a,"attack",{revision=Current(a).revision},"npc-tie")
    DiceDone(); FlushAll()
    result=Last("Committed",a).result
    assert(result.hit==false and result.damage==nil and S.RuntimeNpcs[key].curHealth==7)
end

function cases.b03_npc_rolled_and_pvp_pending()
    Server()
    local npc,key=Npc(false,1,0)
    a.target=npc
    -- Rolled defense: attack 3+4+3+2=12 vs 3d6+1 = 4+4+3+1 = 12: tie, defender wins.
    Later(); Dice({3,4,3,4,4,3})
    handlers.PerformAction(a,"attack",{revision=1},"npc-rolled")
    DiceDone(); FlushAll()
    assert(Last("Committed",a).result.hit==false and S.RuntimeNpcs[key].curHealth==10)
    -- PvP: one pending attack and a 30 s window for the defender only.
    local id,attack=Attack(a,b,{3,4,5})
    assert(attack.defenderGuid==b.id and attack.attackTotal==14 and attack.expiresAt==clock+30)
    local prompt=Last("PromptDefenseReaction",b)
    assert(prompt and prompt.attackId==id and prompt.timeoutSec==30 and Count("PromptDefenseReaction",a)==0)
    assert(Current(b).curHealth==15)
    -- A second attack on the same defender waits for the first answer.
    Later(); handlers.PerformAction(a,"attack",{revision=Current(a).revision},"again")
    assert(LastError(a)=="attack_pending" and #transactions==0)
    -- No target: explicit refusal, nothing rolled.
    a.target=nil
    Later(); Dice({}); handlers.PerformAction(a,"attack",{revision=Current(a).revision},"none")
    assert(LastError(a)=="attack_no_target" and a.notes[#a.notes]=="Атака: выберите цель")
    -- Target outside the RP system.
    local stranger={context="scene"}
    function stranger:GetGUID() return "Creature-B" end
    function stranger:ToPlayer() end
    function stranger:ToCreature() return nil end
    a.target=stranger
    Later(); handlers.PerformAction(a,"attack",{revision=Current(a).revision},"outside")
    assert(LastError(a)=="target_outside_system")
end

-- Same attack, same dice, Блок through the window or the native spell: identical result.
local function BlockRun(native)
    Reset()
    local id=Attack(a,b,{3,4,5})
    Dice({8})
    if native then Cast(b,1500013)
    else Later(); handlers.PerformAction(b,"block",{attackId=id},"win-block") end
    DiceDone(); assert(FlushAll()==1)
    local result=Last("Committed",b).result
    assert(result.kind=="reaction" and result.attackId==id and result.outcome.choice=="BLOCK")
    assert(not R.PendingAttacks[id] and Count("ReactionClosed",b)==1)
    local p=Current(b)
    return {p.curHealth,p.curEnergy,p.energySpentRound,result.outcome.damage.damage,result.outcome.block.base}
end
function cases.b04_window_and_spell_share_path()
    Server()
    local window,native=BlockRun(false),BlockRun(true)
    -- 8 - (1 + Сопротивление 2) - Броня 1 = 4; 2 ОЭ once.
    assert(window[1]==11 and window[2]==8 and window[3]==2 and window[4]==4 and window[5]==1)
    for i=1,#window do assert(window[i]==native[i],"field "..i) end
    -- Избегание through both routes as well (D18: 12 vs 3d6+1 = 12 → avoided).
    Reset()
    local id=Attack(a,b,{3,4,3})
    Dice({4,4,3}); Cast(b,1500012); DiceDone(); FlushAll()
    local outcome=Last("Committed",b).result.outcome
    assert(outcome.choice=="AVOID" and outcome.avoided and Current(b).curHealth==15 and not R.PendingAttacks[id])
    assert(Last("AttackResolved",a).avoided==true)
end

function cases.b05_two_attacks_replay_and_carry()
    Server()
    local first=Attack(a,b,{3,4,5})
    local second=Attack(c,b,{1,2,4})
    -- Several open attacks: the native spell asks for an explicit choice, nothing resolves.
    Cast(b,1500013)
    local choice=Last("ChooseDefenseAttack",b)
    assert(choice and choice.actionKey=="block" and #choice.attackIds==2 and #transactions==0)
    assert(Current(b).curEnergy==10)
    -- The window answers the first attack; the action bar at the same time gets request_pending.
    Later(); Dice({8}); handlers.PerformAction(b,"block",{attackId=first},"pick-first")
    Cast(b,1500013)
    assert(LastError(b)=="request_pending" and #transactions==1)
    DiceDone(); FlushAll()
    assert(not R.PendingAttacks[first] and R.PendingAttacks[second] and Current(b).curEnergy==8)
    -- Replay of the same request returns the stored receipt without spending ОЭ again.
    local committed=Count("Committed",b)
    Later(); handlers.PerformAction(b,"block",{attackId=first},"pick-first")
    assert(#transactions==0 and Count("Committed",b)==committed+1 and Current(b).curEnergy==8)
    -- A new request for the closed attack never moves to the next one.
    Later(); handlers.PerformAction(b,"block",{attackId=first},"late")
    assert(LastError(b)=="reaction_unavailable" and #transactions==0 and R.PendingAttacks[second])
    -- An attack that arrives right after an answer is not auto-picked by a late cast.
    Later(2000)
    Dice({5,5,6}); Cast(b,1500012); DiceDone(); FlushAll()
    assert(not R.PendingAttacks[second] and Last("Committed",b).result.outcome.avoided)
    local third=Attack(a,b,{1,2,4})
    Cast(b,1500013)
    choice=Last("ChooseDefenseAttack",b)
    assert(choice.attackIds[1]==third and #choice.attackIds==1 and R.PendingAttacks[third] and #transactions==0)
end

function cases.b06_timeout_single_outcome()
    Server()
    local id=Attack(a,b,{3,4,5})
    clock=clock+31
    -- An answer after the deadline becomes TAKE: no ОЭ spent, only Броня applies.
    Later(); Dice({8}); handlers.PerformAction(b,"block",{attackId=id},"late-block")
    DiceDone(); FlushAll()
    local outcome=Last("Committed",b).result.outcome
    assert(outcome.choice=="TAKE" and outcome.timedOut and Current(b).curEnergy==10 and Current(b).curHealth==8)
    -- The timeout loop finds nothing left; a later AVOID cannot replace the confirmed TAKE.
    Later(); Poll(); assert(#transactions==0)
    Later(); handlers.PerformAction(b,"evade",{attackId=id},"after")
    assert(LastError(b)=="reaction_unavailable")
    -- Timeout wins the race: the loop starts TAKE, the concurrent BLOCK is refused.
    clock=1000
    local other=Attack(a,b,{3,4,5})
    clock=clock+31
    Later(); Dice({8}); Poll()
    assert(#transactions==1 and R.PendingAttacks[other].busy)
    Later(); handlers.PerformAction(b,"block",{attackId=other},"race")
    assert(LastError(b)=="request_pending" and #transactions==1)
    DiceDone(); FlushAll()
    assert(not R.PendingAttacks[other] and Current(b).curEnergy==10)
    Later(); handlers.PerformAction(b,"block",{attackId=other},"race")
    assert(LastError(b)=="reaction_unavailable" and Current(b).curEnergy==10)
    clock=1000
end

local function Try(actionKey,fate,setup,dice)
    Reset()
    local id=Attack(a,b,{3,4,5})
    setup(S.PlayerProfiles[b.id])
    local before=S.PlayerProfiles[b.id]
    Dice(dice or {})
    Later(); handlers.PerformAction(b,actionKey,{attackId=id,fate=fate},"try-"..ms)
    DiceDone()
    return id,before
end
function cases.b07_block_and_fate_thresholds()
    Server()
    for _,case in ipairs({{1,0,"insufficient_energy"},{10,5,"round_budget_exhausted"}}) do
        local id,before=Try("block",false,function(p) p.curEnergy,p.energySpentRound=case[1],case[2] end)
        assert(LastError(b)==case[3] and #transactions==0 and R.PendingAttacks[id])
        assert(S.PlayerProfiles[b.id]==before and before.curEnergy==case[1])
    end
    for _,case in ipairs({{2,0},{10,4}}) do
        local id=Try("block",false,function(p) p.curEnergy,p.energySpentRound=case[1],case[2] end,{8})
        FlushAll()
        assert(not R.PendingAttacks[id] and Current(b).curEnergy==case[1]-2 and Current(b).energySpentRound==case[2]+2)
    end
    -- Судьба (+1d6 за 3 ОЭ) for Избегание: refused at 2 ОЭ, accepted at 3 ОЭ.
    local id,before=Try("evade",true,function(p) p.curEnergy=2 end)
    assert(LastError(b)=="insufficient_energy" and R.PendingAttacks[id] and S.PlayerProfiles[b.id]==before)
    id=Try("evade",true,function(p) p.curEnergy=3 end,{6,1,2,4})
    FlushAll()
    local outcome=Last("Committed",b).result.outcome
    assert(outcome.avoided and outcome.roll.total==14 and Current(b).curEnergy==0 and Current(b).energySpentRound==3)
    -- Судьба is not offered for Блок.
    id=Try("block",true,function() end)
    assert(LastError(b)=="invalid_fate_choice" and R.PendingAttacks[id])
end

function cases.b08_no_pending_and_free_dice()
    Server()
    for _,spell in ipairs({1500012,1500013}) do
        Cast(b,spell)
        assert(b.notes[#b.notes]=="Нет входящей атаки" and LastError(b)=="no_incoming_attack" and #transactions==0)
    end
    Later(); handlers.PerformAction(b,"block",{attackId="missing"},"ghost")
    assert(LastError(b)=="reaction_unavailable")
    Later(); handlers.PerformAction(b,"cheat",{},"bad")
    assert(LastError(b)=="invalid_action")
    -- Free Уклонение/Сопротивление/щит dice remain standalone checks and consume no attack.
    local id=Attack(a,b,{3,4,5})
    Dice({1,2,4}); Cast(b,1500003); DiceDone(); FlushAll()
    assert(Last("Committed",b).result.kind=="roll" and R.PendingAttacks[id])
    Dice({3}); Cast(b,1500010); DiceDone(); FlushAll()
    local result=Last("Committed",b).result
    assert(result.kind=="roll" and result.statKey=="shield_block" and result.total==3)
    assert(R.PendingAttacks[id] and Current(b).curHealth==15 and Current(b).curEnergy==10)
end

function cases.block_formula()
    Server()
    local p={stats={resistance=2}}
    assert(M.BlockAbsorb(p)==3)
    p.stats.resistance=-1; assert(M.BlockAbsorb(p)==0)
    p.stats.resistance=-3; assert(M.BlockAbsorb(p)==0)
    assert(not M.BlockAbsorb({stats={}}))
    -- R06 hook: an equipped shield rolls its die and adds quality.
    local hook=M.ResolveShield
    M.ResolveShield=function() return {dice="1d6",quality=1} end
    p.stats.resistance=2
    local value,detail=M.BlockAbsorb(p,function() return 4 end)
    assert(value==7 and detail.shield and detail.roll.total==4)
    M.ResolveShield=hook
    assert(M.AttackHits(13,12) and not M.AttackHits(12,12))
    assert(M.DefenseStatFor({damageType="magic"})=="resistance" and M.DefenseStatFor({damageType="physical"})=="evasion")
end

function cases.action_spells_issue_and_degrade()
    Server()
    -- Default: action spells pass the native check, are learned and reported separately from dice.
    assert(C.SpellToActionKey[1500011]=="attack" and C.SpellToActionKey[1500012]=="evade" and C.SpellToActionKey[1500013]=="block")
    events[3](3,b)
    local st=R.ActionSpellStatuses[b.id]
    assert(st.attack.status=="ok" and st.evade.status=="ok" and st.block.status=="ok" and b.known[1500011] and b.known[1500013])
    assert(st.take==nil and R.SpellStatuses[b.id].accuracy.status=="ok")
    Later(); handlers.RequestSync(b)
    assert(Last("SyncProfile",b).actionSpells.block.status=="ok")
    -- Hotfix SQL not applied: actions degrade, dice keep working, nothing is learned.
    spellStatus={[1500011]="no_spellinfo",[1500012]="no_spellinfo",[1500013]="effect:0:6"}
    events[42](42,a,"rps reload")
    assert(R.ready and R.unavailableReason==nil and R.degradedReason==nil)
    assert(next(C.SpellToActionKey)==nil and C.SpellToStatKey[1500001]=="accuracy")
    c.known={}
    events[3](3,c)
    st=R.ActionSpellStatuses[c.id]
    assert(st.attack.status=="no_spellinfo" and st.block.status=="unsafe" and st.block.reason=="effect:0:6")
    assert(not c.known[1500011] and c.known[1500001])
    -- A cast of an unmapped action id is not treated as an action.
    Cast(c,1500011)
    assert(c.notes[#c.notes]=="Бросок недоступен: спелл отключён" and #transactions==0)
    -- Window actions still work without the spells.
    local id=Attack(a,b,{3,4,5})
    Later(); Dice({8}); handlers.PerformAction(b,"take",{attackId=id},"take")
    DiceDone(); FlushAll()
    assert(Last("Committed",b).result.outcome.choice=="TAKE" and Current(b).curHealth==8)
    -- A registry row claiming an action id keeps it a dice spell only.
    spellStatus={}
    definitions[4][6]=1500011
    events[42](42,a,"rps reload")
    assert(C.SpellToStatKey[1500011]=="skill" and C.SpellToActionKey[1500011]==nil and C.ActionSpellStatus.attack=="collision")
    a.chat={}; a.target=nil
    events[42](42,a,"rps diag spells")
    assert(table.concat(a.chat,"\n"):match("action attack id=1500011 check=collision has=%a+ %-> has=%a+ status=unsafe"))
end

function cases.map_queues_action_spells()
    Server()
    GetStateMapId=function() return 0 end
    local queued=0
    RpsQueueDiceCast=function() queued=queued+1; return true end
    local mapHook
    local itemHooks = {}
    RegisterItemEvent=function(entry,event,fn)
        assert(event==2 and type(fn)=="function")
        itemHooks[entry]=fn
    end
    RegisterPlayerEvent=function(event,fn)
        assert(event==5 or event==12 or event==13)
        if event==5 then mapHook=fn else events[event]=fn end
    end
    assert(loadfile(ROOT.."/NobleNextLua/Modules/RPS_Combat/Map.lua"))()
    assert(itemHooks[1801001] and itemHooks[1801002])
    local function Spell(id)
        return {GetEntry=function() return id end,Cancel=function(self) self.cancelled=true end,
            Finish=function(self) self.finished=true end}
    end
    for _,id in ipairs({1500011,1500012,1500013,1500001}) do
        local spell=Spell(id); mapHook(5,a,spell); assert(spell.finished and not spell.cancelled)
    end
    assert(queued==4 and events[12] and events[13])
    mapHook(5,a,{GetEntry=function() return 77 end,Cancel=function() error("foreign spell cancelled") end,
        Finish=function() error("foreign spell finished") end})
    assert(queued==4)
end

-- Client: CombatPrompt buttons go through PerformAction; ChooseDefenseAttack focuses a selection.
function cases.client_prompt_actions()
    local frames,byName,calls,subscribers={},{},{},{}
    GetTime=function() return 10 end
    GetServerTime=function() return 1000 end
    C_Timer={After=function(_,fn) fn() end}
    local function Frame(kind,name,parent)
        local f={kind=kind,name=name,parent=parent,scripts={},shown=true,enabled=true,text=""}
        frames[#frames+1]=f; if name then byName[name]=f end
        local noop=function() end
        for _,method in ipairs({"SetPoint","ClearAllPoints","SetAllPoints","SetJustifyH","SetFrameStrata","SetBackdrop",
            "SetBackdropColor","RegisterEvent","SetTexture"}) do f[method]=noop end
        function f:SetScript(event,fn) self.scripts[event]=fn end
        function f:Show() self.shown=true end
        function f:Hide() self.shown=false end
        function f:SetEnabled(value) self.enabled=value end
        function f:SetSize(w,h) self.width,self.height=w,h end
        function f:SetText(value) self.text=value end
        function f:SetChecked(value) self.checked=value end
        function f:GetChecked() return self.checked end
        function f:CreateFontString() return Frame("FontString",nil,self) end
        return f
    end
    CreateFrame=Frame
    UIParent=Frame("Frame","UIParent")
    local ns={}
    function ns.Subscribe(event,key,fn) subscribers[event]=subscribers[event] or {}; subscribers[event][key]=fn end
    function ns.Emit(event,...) for _,fn in pairs(subscribers[event] or {}) do fn(...) end end
    function ns.PrintError(text) ns.error=text end
    function ns.Print(text) ns.print=text end
    function ns.CreateNGButton(parent,text,w,h) local f=Frame("Button",nil,parent); f.text=text; f:SetSize(w,h); return f end
    local H
    AIO={AddHandlers=function(name,h) assert(name=="RPS_Combat"); H=h; return h end,Handle=function(...) calls[#calls+1]={...} end}
    assert(loadfile(ROOT.."/Addons/NobleNext/Core/RPSClient.lua"))("NobleNext",ns)
    assert(loadfile(ROOT.."/Addons/NobleNext/Modules/CombatPrompt/Init.lua"))("NobleNext",ns)
    local R=ns.RPSClient
    H.SyncProfile(nil,{protocol=1,registry={},profile={revision=4,stats={}},pendingAttackIds={}})
    local function Attack(id) return {attackId=id,attackerName="P"..id,attackTotal=12,timeoutSec=30,weaponDice="1d8"} end
    H.PromptDefenseReaction(nil,Attack("one")); H.PromptDefenseReaction(nil,Attack("two"))
    local f=byName.NobleNextDefensePrompt
    assert(f.shown and f.attackId=="one" and f.buttons[1].text=="Избегание" and f.buttons[2].text=="Блок (2 ОЭ)")
    -- Native Блок with two open attacks: the server asks to choose; the window focuses that list.
    H.ChooseDefenseAttack(nil,{actionKey="block",attackIds={"two","one"}})
    assert(f.attackId=="two" and f.hint.text:find("Выберите атаку для «Блок»",1,true) and ns.print:find("выберите атаку",1,true))
    f.buttons[2].scripts.OnClick(f.buttons[2],"LeftButton")
    local call=calls[#calls]
    assert(call[1]=="RPS_Combat" and call[2]=="PerformAction" and call[3]=="block" and call[4].attackId=="two"
        and call[4].fate==false and type(call[5])=="string" and f.waiting==call[5])
    -- A second click while waiting sends nothing.
    local sent=#calls; f.buttons[1].scripts.OnClick(f.buttons[1],"LeftButton"); assert(#calls==sent)
    H.ReactionClosed(nil,"two")
    assert(f.attackId=="one" and not f.waiting)
    -- Избегание with Судьба; navigation stays within the queue.
    f.fate:SetChecked(true)
    f.buttons[1].scripts.OnClick(f.buttons[1],"LeftButton")
    call=calls[#calls]
    assert(call[3]=="evade" and call[4].attackId=="one" and call[4].fate==true)
    H.Error(nil,{code="no_incoming_attack",requestId=call[5]})
    assert(ns.error=="Нет входящей атаки." and not f.waiting)
    -- Attack helper carries the profile revision on the same channel.
    local requestId=R.PerformAction("attack")
    call=calls[#calls]
    assert(requestId and call[2]=="PerformAction" and call[3]=="attack" and call[4].revision==4)
    H.Committed(nil,{requestId="x",result={kind="reaction",attackId="one",outcome={choice="BLOCK",damage={damage=4}}}})
    assert(ns.print:find("Блок",1,true) and ns.print:find("4",1,true))
    H.AttackResolved(nil,{attackId="one",choice="AVOID",avoided=true,damage=0})
    assert(ns.print:find("Избегание",1,true))
end

return cases
