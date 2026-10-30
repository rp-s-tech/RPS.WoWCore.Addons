package.path=ROOT.."/NobleNextLua/?.lua;"..package.path
local transactions,messages,events,timers={},{},{},{}
local players={}
local clock,milliseconds=1000,0
os.time=function() return clock end
GetCurrTime=function() milliseconds=milliseconds+500; return milliseconds end
RpsRuntimeEpoch=function() return "testepoch" end
RpsIsDiceSpell=function() return true end
GetStateMapId=function() return -1 end
GetPlayersInWorld=function() return players end
GetPlayerByGUID=function(guid) for _,p in ipairs(players) do if p:GetGUID()==guid then return p end end end
RpsTargetContext=function(player,target,edit) return player.context==target.context and (not edit or player.admin) end
RpsPollDiceCasts=function() return {} end
RegisterPlayerEvent=function(id,fn) events[id]=fn end
CreateLuaEvent=function(fn) timers[#timers+1]=fn end
RpsCommitAsync=function(pool,sql,callback) transactions[#transactions+1]={pool=pool,sql=sql,callback=callback} end
local function Query(rows)
    local i,q=1,{}
    function q:GetString(col) return rows[i][col+1] end
    q.GetUInt8,q.GetUInt32,q.GetUInt64,q.GetInt32=q.GetString,q.GetString,q.GetString,q.GetString
    function q:NextRow() i=i+1; return rows[i]~=nil end
    return q
end
local definitions={}
for i,key in ipairs({"accuracy","evasion","resistance","skill"}) do
    definitions[i]={key,"combat",i,key,"dice",0,"3d6",0,""}
end
WorldDBQuery=function(sql)
    if sql:find("FROM rps_stat_definitions",1,true) then return definitions[1] and Query(definitions) or nil end
    if sql:find("COUNT",1,true) then return Query({{0}}) end
end
local pendingRows,storedReceipt={},nil
CharDBQuery=function(sql)
    if storedReceipt and sql:find("rps_action_receipts",1,true) and sql:find("WHERE",1,true) then
        if sql:find("COUNT",1,true) then return Query({{1}}) end
        return Query({storedReceipt})
    end
    if sql:find("COUNT(*) FROM rps_pending_attacks",1,true) then return Query({{#pendingRows}}) end
    if sql:find("FROM rps_pending_attacks",1,true) then return Query(pendingRows) end
    if sql:find("COUNT",1,true) then return Query({{0,0}}) end
end
local handlers
local N={IsMainState=function() return true end,Log=function() end,HasStaffPermission=function(p) return p.admin end,
    AIO={AddHandlers=function(name,h) assert(not handlers); handlers=h; return h end,
        Handle=function(player,prefix,method,payload) messages[#messages+1]={player=player,method=method,payload=payload} end}}
package.loaded.NobleNext=N
_G.NN_BOOTSTRAP_ACTIVE=true
local R=require("Modules.RPS_Combat.Init")
local C,S=R.Config,R.Storage
assert(R.ready)
local function Player(id,admin)
    local p={id=id,admin=admin,context="scene"}
    function p:GetGUIDLow() return self.id end
    function p:GetItemByPos() return nil end
    function p:GetGUID() return "Player-"..self.id end
    function p:GetName() return "P"..self.id end
    function p:GetSelection() return self.target end
    function p:ToPlayer() return self end
    function p:ToCreature() end
    p.known,p.learnCalls,p.learnFails,p.notes,p.chat={},0,0,{},{}
    function p:HasSpell(id) return self.known[id]==true end
    function p:LearnSpell(id)
        self.learnCalls=self.learnCalls+1
        if self.learnFails>0 then self.learnFails=self.learnFails-1 else self.known[id]=true end
    end
    function p:SendNotification(text) self.notes[#self.notes+1]=text end
    function p:SendBroadcastMessage(text) self.chat[#self.chat+1]=text end
    players[#players+1]=p
    return p
end
local a,b=Player("4294967297",true),Player("4294967298",false)
local function Profile(player)
    local p=assert(S.BuildDefaultPlayerProfile(player)); p.revision=1; p.name=player:GetName()
    p.stats.evasion,p.stats.resistance=1,2
    S.PlayerProfiles[p.guid]=p
    return p
end
local pa,pb=Profile(a),Profile(b)
local function Flush(ok)
    local transaction=table.remove(transactions,1); assert(transaction,"no transaction")
    transaction.callback(ok~=false)
    return transaction
end
local function Count(method)
    local n=0; for _,msg in ipairs(messages) do if msg.method==method then n=n+1 end end; return n
end
local function LastError()
    for i=#messages,1,-1 do if messages[i].method=="Error" then return messages[i].payload.code end end
end
local cases={}
function cases.attack_replay_before_target_checks()
    a.target=b
    local args={revision=1,targetGuid=b:GetGUID()}
    handlers.PerformAction(a,"attack",args,"replay-attack")
    assert(#transactions==1)
    a.target=nil
    handlers.PerformAction(a,"attack",args,"replay-attack")
    assert(LastError()=="request_pending" and #transactions==1)
    Flush()
    local record=R.Seen[a.id]["replay-attack"]
    local original=record.result
    assert(original.attackId and R.PendingAttacks[original.attackId])
    storedReceipt={record.signature,"done",assert(S.EncodeReceipt(original))}
    R.Seen={}
    math.random=function() error("attack replay rerolled") end
    local n=Count("Committed")
    handlers.PerformAction(a,"attack",args,"replay-attack")
    assert(Count("Committed")==n+1 and #transactions==0)
    local result=messages[#messages].payload.result
    assert(result.attackId==original.attackId and result.total==original.total and result.energyApplied==original.energyApplied)
    handlers.PerformAction(a,"attack",{revision=1,targetGuid=a:GetGUID()},"replay-attack")
    assert(LastError()=="request_conflict")
end

function cases.reaction_replay_after_reload()
    a.target=b
    handlers.PerformAction(a,"attack",{revision=1},"attack-reaction")
    Flush()
    local attackId=R.Seen[a.id]["attack-reaction"].result.attackId
    handlers.SendDefenseReaction(b,attackId,"BLOCK","evasion",false,"replay-reaction")
    assert(#transactions==1)
    Flush()
    local record=R.Seen[b.id]["replay-reaction"]
    local original=record.result
    local profile=S.PlayerProfiles[b.id]
    assert(not R.PendingAttacks[attackId] and original.outcome.damage)
    storedReceipt={record.signature,"done",assert(S.EncodeReceipt(original))}
    R.Seen={}
    math.random=function() error("reaction replay rerolled") end
    local n=Count("Committed")
    handlers.SendDefenseReaction(b,attackId,"BLOCK","evasion",false,"replay-reaction")
    assert(Count("Committed")==n+1 and S.PlayerProfiles[b.id]==profile and #transactions==0)
    local result=messages[#messages].payload.result
    assert(result.attackId==original.attackId and result.outcome.choice==original.outcome.choice)
    assert(result.outcome.damage.damage==original.outcome.damage.damage and result.outcome.block.base==original.outcome.block.base)
    handlers.SendDefenseReaction(b,attackId,"TAKE","evasion",false,"replay-reaction")
    assert(LastError()=="request_conflict")
end

function cases.new_hit_at_zero_and_replay()
    a.target=b
    pa.stats.accuracy=100
    pb.curHealth,pb.curWounds,pb.armor=0,0,0
    for i=1,2 do
        handlers.PerformAction(a,"attack",{revision=S.PlayerProfiles[a.id].revision},"hit-"..i)
        Flush()
        local id=R.Seen[a.id]["hit-"..i].result.attackId
        handlers.SendDefenseReaction(b,id,"TAKE","evasion",false,"take-"..i)
        Flush()
        assert(S.PlayerProfiles[b.id].curHealth==0 and S.PlayerProfiles[b.id].curWounds==i)
        local profile=S.PlayerProfiles[b.id]
        handlers.SendDefenseReaction(b,id,"TAKE","evasion",false,"take-"..i)
        assert(S.PlayerProfiles[b.id]==profile and #transactions==0)
    end
end

function cases.commit()
    handlers.RollStat(a,"skill",true,"roll-one",1)
    assert(#transactions==1 and Count("Committed")==0 and pa.curEnergy==10)
    assert(S.PlayerProfiles[pa.guid]==pa and next(R.Locks))
    Flush(false)
    assert(LastError()=="save_failed" and S.PlayerProfiles[pa.guid]==pa and not next(R.Locks))
    handlers.RollStat(a,"skill",true,"roll-two",1)
    assert(#transactions==1)
    Flush()
    assert(Count("Committed")==1 and S.PlayerProfiles[pa.guid].revision==2)
    local committed=S.PlayerProfiles[pa.guid]
    handlers.RollStat(a,"skill",true,"roll-two",1)
    assert(#transactions==0 and S.PlayerProfiles[pa.guid]==committed and Count("Committed")==2)
    handlers.RollStat(a,"accuracy",true,"roll-two",1)
    assert(LastError()=="request_conflict" and #transactions==0)
end
function cases.permissions()
    a.target=b
    handlers.DmSaveTargetStats(b,{targetGuid=a:GetGUID(),revision=1,maxHealth=20},"bad")
    assert(LastError()=="permission_denied" and #transactions==0)
    handlers.DmSaveTargetStats(a,{targetGuid=a:GetGUID(),revision=1,maxHealth=20},"changed")
    assert(LastError()=="target_changed" and #transactions==0)
    handlers.DmSaveTargetStats(a,{targetGuid=b:GetGUID(),revision=1,armor=3},"save")
    assert(#transactions==1 and pb.armor==0)
    handlers.RollStat(b,"skill",false,"busy",1)
    assert(LastError()=="actor_busy" and #transactions==1)
    Flush()
    assert(S.PlayerProfiles[pb.guid].armor==3 and S.PlayerProfiles[pb.guid].revision==2)
    -- Bonus resources above the maximum are a valid DM edit.
    local maxH,maxE=S.PlayerProfiles[pb.guid].maxHealth,S.PlayerProfiles[pb.guid].maxEnergy
    handlers.DmSaveTargetStats(a,{targetGuid=b:GetGUID(),revision=2,curHealth=maxH+5,curEnergy=maxE+3},"bonus")
    assert(#transactions==1, tostring(LastError()))
    Flush()
    assert(S.PlayerProfiles[pb.guid].curHealth==maxH+5 and S.PlayerProfiles[pb.guid].curEnergy==maxE+3)
    assert(S.PlayerProfiles[pb.guid].revision==3)
    b.context="other"
    handlers.DmSaveTargetStats(a,{targetGuid=b:GetGUID(),revision=3,armor=4},"phase")
    assert(LastError()=="permission_denied")
end
function cases.reactions()
    a.target=b
    handlers.PerformAction(a,"attack",{revision=1},"attack")
    assert(Count("PromptDefenseReaction")==0)
    local t=Flush()
    assert(t.pool=="characters" and #t.sql==3 and Count("PromptDefenseReaction")>0)
    local id,attack=next(R.PendingAttacks); assert(id and attack.defenderGuid==pb.guid)
    handlers.SendDefenseReaction(a,id,"TAKE","evasion",false,"foreign")
    assert(LastError()=="reaction_unavailable" and #transactions==0)
    handlers.SendDefenseReaction(b,id,"TAKE","evasion",false,"take")
    assert(#transactions==1 and Count("ReactionClosed")==0)
    handlers.SendDefenseReaction(b,id,"TAKE","evasion",false,"take")
    assert(LastError()=="request_pending" and #transactions==1)
    Flush()
    assert(not R.PendingAttacks[id] and Count("ReactionClosed")==1)
    -- Startup reload restores durable pending rows and enforces their deadline.
    pendingRows={{"restored","4294967297","4294967298","P",15,"1d8","physical",clock-1}}
    events[42](42,a,"rps reload")
    assert(R.PendingAttacks.restored)
    for _,fn in ipairs(timers) do fn() end
    assert(#transactions==1)
    Flush()
    assert(not R.PendingAttacks.restored)
    assert(events[42](42,a,"rps character set hp 5")==nil)
end
local function Npc()
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
    return npc
end
function cases.partial()
    local npc=Npc(); a.target=npc
    local p=S.BuildCreatureProfile(npc); p.stats.evasion=-100
    S.RuntimeNpcs[p.runtimeKey]=p
    -- GetCreatureStats must also have a matching baseline to create an uncached instance.
    handlers.PerformAction(a,"attack",{fate=true,revision=1},"cross")
    assert(#transactions==1 and transactions[1].pool=="characters")
    Flush()
    assert(#transactions==1 and transactions[1].pool=="world" and Count("Committed")==0)
    Flush(false)
    assert(LastError()=="partial_commit" and Count("Committed")==0)
    assert(S.PlayerProfiles[pa.guid].revision==2 and S.RuntimeNpcs[p.runtimeKey]==p)
end
function cases.creation()
    S.ReleasePlayer(a)
    handlers.RequestSync(a)
    assert(#transactions==1 and Count("SyncProfile")==0)
    Flush()
    assert(Count("SyncProfile")==1 and S.PlayerProfiles[a.id].revision==1)
    -- A commit can finish after logout without accessing an old Player userdata.
    S.ReleasePlayer(b); handlers.RequestSync(b)
    table.remove(players,2)
    Flush()
    assert(not R.Locks["p:"..b.id])
end
function cases.map()
    GetStateMapId=function() return 0 end
    local queued=0
    local reply={true}
    RpsQueueDiceCast=function(player,spell) queued=queued+1; assert(not spell.cancelled and not spell.finished); return table.unpack(reply) end
    local old=RegisterPlayerEvent
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
    definitions[1][6]=1500001
    assert(loadfile(ROOT.."/NobleNextLua/Modules/RPS_Combat/Map.lua"))()
    assert(itemHooks[1801001] and itemHooks[1801002])
    local function Dice()
        return {GetEntry=function() return 1500001 end,
            Cancel=function(self) self.cancelled=true end,Finish=function(self) self.finished=true end}
    end
    local spell=Dice()
    assert(events[12] and events[13])
    mapHook(5,a,spell); assert(queued==1 and spell.finished and not spell.cancelled and #a.notes==0)
    local other={GetEntry=function() return 123 end,Cancel=function() error("native spell cancelled") end,
        Finish=function() error("native spell finished") end}
    mapHook(5,a,other); assert(queued==1)
    -- A refused enqueue still cancels the native cast but never silently.
    reply={false,"queue_full"}
    local full=Dice()
    mapHook(5,a,full); assert(full.cancelled and not full.finished and a.notes[#a.notes]=="Очередь бросков переполнена")
    reply={false,"cast_pending"}
    local pending=Dice()
    mapHook(5,a,pending); assert(pending.cancelled and not pending.finished and a.notes[#a.notes]=="Предыдущий бросок ещё обрабатывается")
    RpsQueueDiceCast=nil
    local unavailable=Dice()
    mapHook(5,a,unavailable); assert(queued==3 and unavailable.cancelled and not unavailable.finished and a.notes[#a.notes]=="Бросок недоступен")
    RegisterPlayerEvent=old
end
function cases.binding()
    RpsCommitAsync=function() error("disabled unsafe method") end
    handlers.RollStat(a,"skill",false,"binding",1)
    assert(LastError()=="commit_binding_error" and not next(R.Locks) and S.PlayerProfiles[a.id]==pa)
end
function cases.receipt()
    handlers.RollStat(a,"skill",false,"durable",1); Flush()
    local record=R.Seen[a.id].durable
    storedReceipt={record.signature,"done",assert(S.EncodeReceipt(record.result))}
    R.Seen={}
    math.random=function() error("duplicate rerolled after reload") end
    local count=Count("Committed")
    handlers.RollStat(a,"skill",false,"durable",1)
    assert(#transactions==0 and Count("Committed")==count+1)
    storedReceipt[2]="pending"
    R.Seen={}
    handlers.RollStat(a,"skill",false,"durable",1)
    assert(LastError()=="pending_recovery" and #transactions==0)
end
function cases.cache()
    for i=1,70 do
        handlers.RollStat(a,"skill",false,"r"..i,S.PlayerProfiles[a.id].revision)
        assert(#transactions==1); Flush()
    end
    local count=0; for _ in pairs(R.Seen[a.id]) do count=count+1 end
    assert(count==64 and Count("Committed")==70)
end
function cases.startup_diagnostics()
    definitions[1][6]=1500001
    RpsIsDiceSpell=function() return false end
    events[42](42,a,"rps reload")
    -- One bad spell loses only its mapping; the registry and the runtime stay available.
    assert(R.ready and R.unavailableReason==nil and R.degradedReason=="dice_spells_unavailable:accuracy:1500001:unsafe")
    assert(C.StatDefs.accuracy and C.SpellToStatKey[1500001]==nil and #transactions==0)
    assert(R.SpellStatuses[a.id].accuracy.status=="unsafe" and a.learnCalls==0)
    definitions={}
    events[42](42,a,"rps reload")
    assert(not R.ready and R.unavailableReason=="registry_unavailable")
    assert(messages[#messages].payload.reason==R.unavailableReason)
    for i,key in ipairs({"accuracy","evasion","resistance","skill"}) do definitions[i]={key,"combat",i,key,"dice",0,"3d6",0,""} end
    RpsIsDiceSpell=function() return true end
    local binding=RpsCommitAsync
    RpsCommitAsync=nil
    events[42](42,a,"rps reload")
    assert(not R.ready and R.unavailableReason=="missing_binding:RpsCommitAsync")
    RpsCommitAsync=binding
    events[42](42,a,"rps reload")
    assert(R.ready and R.unavailableReason==nil)
    b.context="scene"
    local beforeBatch=#messages
    handlers.RequestUnitsSync(a,{b:GetGUID()})
    assert(#messages>beforeBatch and messages[#messages].method=="SyncUnitBatch")
    assert(messages[#messages].payload[b:GetGUID()].curHealth==pb.curHealth)
end
local function SpellRegistry()
    local reasons={[1500001]="ok",[1500003]="no_spellinfo",[1500004]="effect:0:6"}
    RpsDiceSpellStatus=function(id) local r=reasons[id] or "no_spellinfo"; return r=="ok",r end
    definitions[1][6],definitions[2][6],definitions[3][6],definitions[4][6]=1500001,1500003,1500004,0
end
local function LastSync(player)
    for i=#messages,1,-1 do
        if messages[i].method=="SyncProfile" and messages[i].player==player then return messages[i].payload end
    end
end
function cases.spell_statuses()
    SpellRegistry()
    events[42](42,a,"rps reload")
    assert(R.ready and R.unavailableReason==nil)
    assert(R.degradedReason=="dice_spells_unavailable:evasion:1500003:no_spellinfo,resistance:1500004:effect:0:6")
    assert(C.SpellToStatKey[1500001]=="accuracy" and not C.SpellToStatKey[1500003] and not C.SpellToStatKey[1500004])
    assert(C.StatDefs.evasion.configuredSpellId==1500003 and C.StatDefs.evasion.spellId==0)
    local st=R.SpellStatuses[a.id]
    assert(st.accuracy.status=="ok" and st.accuracy.id==1500001 and a.known[1500001])
    assert(st.evasion.status=="no_spellinfo" and st.evasion.id==1500003)
    assert(st.resistance.status=="unsafe" and st.resistance.reason=="effect:0:6")
    assert(st.skill.status=="unmapped" and st.skill.id==0)
    local sync=LastSync(a); assert(sync and sync.spells and sync.spells.accuracy.status=="ok" and sync.registry and sync.profile)
    -- Already known spell is not relearned on the next sync.
    local calls=a.learnCalls
    handlers.RequestSync(a); assert(a.learnCalls==calls and LastSync(a).spells.accuracy.status=="ok")
end
function cases.learn_retry()
    SpellRegistry()
    events[42](42,a,"rps reload")
    -- One transient refusal is recovered by the single bounded retry on login.
    b.known,b.learnCalls,b.learnFails={},0,1
    events[3](3,b)
    assert(R.SpellStatuses[b.id].accuracy.status=="ok" and b.learnCalls==2 and b.known[1500001])
    -- A persistent refusal is reported and not retried on every sync.
    b.known,b.learnCalls,b.learnFails={},0,100
    R.LearnFailed[b.id]=nil
    events[3](3,b)
    assert(R.SpellStatuses[b.id].accuracy.status=="learn_failed" and b.learnCalls==2)
    assert(LastSync(b).spells.accuracy.status=="learn_failed")
    handlers.RequestSync(b)
    assert(b.learnCalls==2 and R.SpellStatuses[b.id].accuracy.status=="learn_failed")
    -- Login without a ready profile still issues spells.
    b.learnFails,b.known,b.learnCalls=0,{},0
    S.ReleasePlayer(b)
    events[3](3,b)
    assert(b.known[1500001] and R.SpellStatuses[b.id].accuracy.status=="ok")
end
function cases.diag_spells()
    SpellRegistry()
    events[42](42,a,"rps reload")
    b.known,b.learnCalls,b.learnFails={},0,0
    R.LearnFailed[b.id]={[1500001]=true}
    a.target=b; a.chat={}
    assert(events[42](42,a,"rps diag spells")==false)
    local text=table.concat(a.chat,"\n")
    assert(a.chat[1]:find("ready=true",1,true) and a.chat[1]:find("player=P"..b.id,1,true))
    assert(a.chat[1]:find("degraded=dice_spells_unavailable:evasion:1500003:no_spellinfo",1,true))
    assert(text:find("accuracy id=1500001 check=ok has=false -> has=true status=ok",1,true))
    assert(text:find("evasion id=1500003 check=no_spellinfo has=false -> has=false status=no_spellinfo",1,true))
    assert(text:find("resistance id=1500004 check=effect:0:6",1,true))
    assert(text:find("skill id=0 check=unmapped has=- status=unmapped",1,true))
    assert(b.known[1500001] and LastSync(b).spells.accuracy.status=="ok")
    -- Non-staff cannot run diagnostics; unrelated .rps subcommands are not swallowed.
    b.chat={}
    assert(events[42](42,b,"rps diag spells")==false and #b.chat==0)
    assert(events[42](42,a,"rps diag other")==nil)
    a.target=nil; a.chat={}
    events[42](42,a,"rps diag spells")
    assert(a.chat[1]:find("player=P"..a.id,1,true))
end
function cases.cast_feedback()
    SpellRegistry()
    events[42](42,a,"rps reload")
    a.notes={}
    local queue={{player=a,spellId=1500001,rejected="target_changed"},{player=a,spellId=1500009}}
    RpsPollDiceCasts=function() local q=queue; queue={}; return q end
    for _,fn in ipairs(timers) do fn() end
    assert(a.notes[1]=="Бросок отменён: цель изменилась" and a.notes[2]=="Бросок недоступен: спелл отключён")
    assert(#transactions==0)
end
return cases
