package.path = ROOT .. "/NobleNextLua/?.lua;" .. package.path
local C = require("Modules.RPS_Combat.00_RPS_Config")
package.loaded["Core.DB"] = {EscapeSqlString=function(s) return s:gsub("'", "''") end}
local I = require("Modules.RPS_Combat.09_RPS_Consumables")
local defs = require("Modules.RPS_Combat.08_RPS_ConsumableCatalog")
local cases = {}
local function profile()
    return {isPlayer=true, curHealth=5, maxHealth=15, curEnergy=2, maxEnergy=10, curWounds=0, maxWounds=3}
end
function cases.plan()
    local p = profile()
    assert(I.Plan(p, defs[1801001]) == 15)
    assert(p.curHealth == 5)
    assert(I.Plan(p, defs[1801002]) == 7)
    p.curHealth = 14
    assert(I.Plan(p, defs[1801001]) == 15)
    p.curHealth = 15
    assert(not I.Plan(p, defs[1801001]))
    p.curHealth = 20
    assert(not I.Plan(p, defs[1801001]))
    p.curHealth = 0
    assert(not I.Plan(p, defs[1801001]))
    p.curHealth = 5; p.deathOutcome = "death"
    assert(not I.Plan(p, defs[1801001]))
    p.deathOutcome = nil; p.curWounds = 3
    assert(not I.Plan(p, defs[1801001]))
end
function cases.map()
    local handlers, calls, notices, queued = {}, 0, {}, nil
    function RegisterItemEvent(entry, event, handler) assert(event==2); handlers[entry]=handler end
    function RpsQueueConsumableUse(_,_,target) calls=calls+1; queued=target; return true end
    local player = {GetTypeId=function() return 6 end, GetSelection=function(self) return self.selection end,
        ToPlayer=function(self) return self end, SendBroadcastMessage=function(_,text) notices[#notices+1]=text end}
    I.InstallMap()
    assert(handlers[1801001](2,player,{},nil)==false and calls==1 and queued==player)
    local other={GetTypeId=function() return 6 end,ToPlayer=function(self) return self end}
    player.selection=other
    assert(handlers[1801002](2,player,{},nil)==false and calls==2 and queued==other)
    assert(handlers[1801001](2,player,{},player)==false and calls==3 and queued==player, "explicit self target wins over selection")
    local npc={GetTypeId=function() return 5 end,ToPlayer=function() end}
    assert(handlers[1801001](2,player,{},npc)==false)
    assert(calls==3 and #notices==1 and notices[1]:find("НИП",1,true))
    local object={GetTypeId=function() return 4 end,ToPlayer=function() end}
    handlers[1801001](2,player,{},object)
    assert(calls==3 and #notices==2, "type 4 is not a player in the current core")
end
local codec = require("smallfolk")
local function setup()
    local env={calls=0, removed=0, notices={}, receipts={}, logs={}, online={}, items={}, profiles={}}
    package.loaded["NobleNext"]={Log=function(_,v) env.logs[#env.logs+1]=v end}
    local function player(id)
        local unit={GetGUIDLow=function() return id end,GetGUID=function() return "Player-"..id end,
            GetTypeId=function() return 6 end,ToPlayer=function(self) return self end,
            IsAlive=function() return true end,IsInCombat=function() return false end,
            SendBroadcastMessage=function(_,v) env.notices[#env.notices+1]=v end}
        function unit:GetItemByPos(bag,slot) return bag==255 and slot==35 and env.items[id] or nil end
        function unit:RemoveItem(item,count) assert(env.items[id]==item and count==1); env.items[id]=nil; env.removed=env.removed+1 end
        env.online["Player-"..id]=unit
        env.profiles[unit]=profile()
        return unit
    end
    env.source,env.target,env.other=player(1),player(2),player(3)
    function env.item(entry)
        return {GetEntry=function() return entry or 1801001 end, GetGUID=function() return "Item-1-A" end,
            GetCount=function() return 1 end, GetMaxStackCount=function() return 1 end, IsInTrade=function() return false end,
            GetBagSlot=function() return 255 end,GetSlot=function() return 35 end}
    end
    env.items[1]=env.item()
    local S={ResolveUnitStats=function(unit) return env.profiles[unit] end,
        CopyProfile=function(v) local d={} for k,x in pairs(v) do d[k]=x end return d end,
        EncodeReceipt=codec.dumps, DecodeReceipt=function(v) return codec.loads(v,#v) end}
    env.R={ready=true,Storage=S,Combat={},Locks={},PendingAttacks={}}
    function CreateLuaEvent() end
    function GetPlayersInWorld() local r={} for _,v in pairs(env.online) do r[#r+1]=v end return r end
    function GetPlayerByGUID(guid) return env.online[guid] end
    function RpsConsumableContext() return not env.badContext end
    function CharDBQuery(sql)
        assert(sql:find("issuer_guid=0",1,true), "Receipt must belong to the item, not the owner")
        if env.receipt then return {GetString=function(_,i) return ({env.signature,"done",env.receipt,"consumable"})[i+1] end} end
    end
    function RpsFindOwnedItem(unit) return env.items[unit:GetGUIDLow()] end
    function RpsCommitAsync(pool,statements,callback)
        assert(pool=="characters"); env.calls=env.calls+1
        assert(env.profiles[env.target].curHealth==5 or env.reusing)
        assert(statements[#statements]:find("VALUES (0,",1,true))
        env.complete=function(ok)
            if ok then env.receipt,env.signature=env.nextPayload,env.nextSignature end
            callback(ok)
        end
    end
    function S.SaveProfiles(drafts,callback,commit,extras)
        local sql=extras.characters[#extras.characters]
        env.nextSignature=sql:match("'consume_Item%-1%-A','([^']+)'")
        env.nextPayload=codec.dumps({kind="consumable",itemGuid="Item-1-A",entry=env.items[env.actor or 1]:GetEntry(),
            ownerGuid=tostring(env.actor or 1),targetGuid="2",amount=10,resource="curHealth",value=15})
        if env.items[env.actor or 1]:GetEntry()==1801002 then
            env.nextPayload=codec.dumps({kind="consumable",itemGuid="Item-1-A",entry=1801002,ownerGuid="1",targetGuid="2",amount=5,resource="curEnergy",value=7})
        end
        local statements={"PROFILE"};for _,v in ipairs(extras.characters) do statements[#statements+1]=v end
        env.statements=statements
        commit("characters",statements,function(ok)
            if ok then env.profiles[env.target]=drafts[1] end
            callback(ok)
        end)
    end
    I.InstallWorld(env.R,{})
    return env
end
function cases.commit(mode)
    local e=setup()
    if mode=="battle" then e.R.PendingAttacks.a={attackerGuid="2",defenderGuid="3"} end
    if mode=="lock" then e.R.Locks["p:2"]=true end
    if mode=="context" then e.badContext=true end
    I.Use(e.source,e.target,"Item-1-A")
    if mode=="battle" or mode=="lock" or mode=="context" then assert(e.calls==0 and e.removed==0); return end
    assert(e.calls==1 and e.profiles[e.target].curHealth==5 and e.removed==0)
    assert(e.R.Locks["p:1"] and e.R.Locks["p:2"] and e.R.Locks["item:Item-1-A"])
    I.Use(e.source,e.target,"Item-1-A"); assert(e.calls==1)
    if mode=="failure" then
        e.complete(false);assert(e.removed==0 and e.profiles[e.target].curHealth==5 and not next(e.R.Locks));return
    end
    e.complete(true)
    assert(e.removed==1 and e.profiles[e.target].curHealth==15 and not next(e.R.Locks))
    I.Use(e.source,e.target,"Item-1-A");assert(e.calls==1)
    I.Use(e.other,e.target,"Item-1-A");assert(e.calls==1 and e.notices[#e.notices]:find("уже использован"))
    I.Use(e.source,e.other,"Item-1-A");assert(e.calls==1 and e.notices[#e.notices]:find("уже использован"))
    e.receipt=codec.dumps({kind="foreign"});I.Use(e.source,e.target,"Item-1-A")
    assert(e.calls==1 and e.notices[#e.notices]:find("проверить"))
end
function cases.recovery(mode)
    local e=setup();I.Use(e.source,e.target,"Item-1-A")
    if mode=="transfer_pending" then
        e.items[3],e.items[1]=e.items[1],nil
        I.Use(e.other,e.target,"Item-1-A");assert(e.calls==1)
        e.complete(true);assert(not e.items[3] and e.removed==1);return
    end
    e.online["Player-1"]=nil;e.online["Player-2"]=nil
    e.complete(true)
    assert(e.removed==0 and e.profiles[e.target].curHealth==15)
    -- Crash/reload drops Lua locks and retains the DB receipt and native inventory.
    I.InstallWorld(e.R,{})
    e.online["Player-1"],e.online["Player-2"]=e.source,e.target
    if mode=="different_entry" then
        e.items[1]=e.item(1801002);e.reusing=true
        I.Recover(e.source);assert(e.removed==0)
        I.Use(e.source,e.target,"Item-1-A");assert(e.calls==2 and e.statements[2]:find("DELETE FROM",1,true))
        e.complete(true);assert(e.removed==1 and e.profiles[e.target].curEnergy==7);return
    end
    if mode=="transfer" then e.items[3],e.items[1]=e.items[1],nil;I.Use(e.other,e.target,"Item-1-A")
    elseif mode=="login" then I.Recover(e.source)
    else I.Use(e.source,e.target,"Item-1-A") end
    assert(e.calls==1 and e.removed==1 and e.profiles[e.target].curHealth==15 and #e.logs>0)
    if mode~="login" then assert(e.notices[#e.notices]:find("Предмет уже использован",1,true)) end
end
return cases
