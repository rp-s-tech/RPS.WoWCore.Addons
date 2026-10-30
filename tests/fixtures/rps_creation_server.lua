-- R03/R06 server: real Init + 05_RPS_Creation handlers over a small in-memory characters DB.
package.path=ROOT.."/NobleNextLua/?.lua;"..package.path
local transactions,messages,events,players={},{},{},{}
local clock,ms=100000,0
os.time=function() return clock end
GetCurrTime=function() ms=ms+1000; return ms end
RpsRuntimeEpoch=function() return "epoch" end
RpsIsDiceSpell=function() return true end
GetStateMapId=function() return -1 end
GetPlayersInWorld=function() return players end
GetPlayerByGUID=function(guid) for _,p in ipairs(players) do if p:GetGUID()==guid then return p end end end
RpsTargetContext=function() return true end
RpsPollDiceCasts=function() return {} end
RegisterPlayerEvent=function(id,fn) events[id]=fn end
CreateLuaEvent=function() end
RpsCommitAsync=function(pool,sql,callback) transactions[#transactions+1]={pool=pool,sql=sql,callback=callback} end

local db={creation={},receipts={},items={},logs={},stats={},creationSchema=true,presetColumn=true,names={}}
local function Query(rows)
    local i,q=1,{}
    function q:GetString(col) local v=rows[i][col+1]; return v~=nil and tostring(v) or nil end
    function q:GetUInt32(col) return tonumber(rows[i][col+1]) end
    q.GetUInt8,q.GetUInt64,q.GetInt32=q.GetUInt32,q.GetUInt32,q.GetUInt32
    function q:NextRow() i=i+1; return rows[i]~=nil end
    return q
end
local definitions={}
for i,key in ipairs({"accuracy","healing","evasion","resistance","skill","knowledge","endurance","craft"}) do
    definitions[i]={key,i<=4 and "combat" or "mastery",i,key,"dice",0,"3d6",0,""}
end
WorldDBQuery=function(sql)
    if sql:find("FROM rps_stat_definitions",1,true) then return Query(definitions) end
    if sql:find("COUNT",1,true) then return Query({{0}}) end
end
CharDBQuery=function(sql)
    if sql:find("information_schema.COLUMNS",1,true) and sql:find("race_preset_version",1,true) then
        return db.creationSchema and Query({{db.presetColumn and 1 or 0}}) or nil
    end
    local logGuid=sql:match("FROM character_rps_creation_log WHERE guid = (%d+)")
    if logGuid then
        local n=0
        for _,row in ipairs(db.logs) do if tostring(row[1])==logGuid and row[8]=="archetype_reset" then n=n+1 end end
        return Query({{n}})
    end
    local name=sql:match("SELECT guid FROM characters WHERE name = '([^']*)'")
    if name then return db.names[name] and Query({{db.names[name]}}) or nil end
    local guid=sql:match("FROM character_rps_creation WHERE guid = (%d+)")
    if guid then
        if not db.creationSchema then return nil end
        if sql:find("COUNT",1,true) then return Query({{db.creation[guid] and 1 or 0}}) end
        assert(db.presetColumn==(sql:find("race_preset_version",1,true)~=nil),"preset column probe mismatch")
        return Query({{table.unpack(db.creation[guid],2)}})
    end
    local issuer,request=sql:match("rps_action_receipts WHERE issuer_guid=(%d+) AND request_id='([^']*)'")
    if issuer then
        local r=db.receipts[issuer..":"..request]
        if sql:find("COUNT",1,true) then return Query({{r and 1 or 0}}) end
        return Query({{r.signature,r.state}})
    end
    guid=sql:match("COUNT%(%*%) FROM character_rps_stats WHERE guid=(%d+)")
    if guid then return Query({{db.stats[guid] and 1 or 0}}) end
    if sql:find("COUNT",1,true) then return Query({{0,0}}) end
end

-- SQL tuple parser: 'text' with '' escapes, bare numbers/NULL.
local function Tuples(text)
    local out,i,n=nil,1,#text
    local list,current,tok={},nil,nil
    while i<=n do
        local ch=text:sub(i,i)
        if ch=="(" and not current then current={}; tok=nil
        elseif ch=="'" and current then
            local buf={}; i=i+1
            while true do
                local c=text:sub(i,i)
                if c=="'" and text:sub(i+1,i+1)=="'" then buf[#buf+1]="'"; i=i+2
                elseif c=="'" then break
                else
                    if c=="\\" then i=i+1; c=text:sub(i,i) end
                    buf[#buf+1]=c; i=i+1
                end
            end
            tok=table.concat(buf)
        elseif ch=="," and current then current[#current+1]=tok; tok=nil
        elseif ch==")" and current then current[#current+1]=tok; list[#list+1]=current; current,tok=nil,nil
        elseif current and ch:match("[%w%-]") then
            local word=text:match("^[%w%-]+",i); i=i+#word-1
            tok=word=="NULL" and false or tonumber(word) or word
        end
        i=i+1
    end
    return list
end
local function Apply(sql)
    local values=sql:match("VALUES%s*(.*)$") or ""
    if sql:find("INSERT INTO `character_rps_creation`",1,true) then
        local t=Tuples(values:match("^(.-) ON DUPLICATE KEY") or values)[1]
        db.creation[tostring(t[1])]=t
    elseif sql:find("INSERT INTO `character_rps_creation_log`",1,true) then
        db.logs[#db.logs+1]=Tuples(values)[1]
    elseif sql:find("INSERT INTO `character_rps_items`",1,true) then
        for _,t in ipairs(Tuples(values)) do
            for _,row in ipairs(db.items) do
                if row[1]==t[1] and t[9] and row[9]==t[9] then return false end
            end
            db.items[#db.items+1]=t
        end
    elseif sql:find("rps_action_receipts",1,true) then
        local t=Tuples(values)[1]
        db.receipts[tostring(t[1])..":"..t[2]]={signature=t[3],state=t[4]}
    elseif sql:find("INSERT INTO `character_rps_stats`",1,true) then
        db.stats[tostring(Tuples(values:match("^(.-) ON DUPLICATE KEY"))[1][1])]=true
    end
    return true
end

local handlers
local N={IsMainState=function() return true end,Log=function() end,HasStaffPermission=function(p) return p.admin end,
    AIO={AddHandlers=function(name,h) assert(name=="RPS_Combat" and not handlers); handlers=h; return h end,
        Handle=function(player,_,method,payload) messages[#messages+1]={player=player,method=method,payload=payload} end}}
package.loaded.NobleNext=N
_G.NN_BOOTSTRAP_ACTIVE=true
local R=require("Modules.RPS_Combat.Init")
assert(R.ready,R.unavailableReason)
local C,S=R.Config,R.Storage
local K=require("Modules.RPS_Combat.03_RPS_Catalog")
local Cr=R.Creation
assert(Cr and handlers.ConfirmCharacter and handlers.PreviewCharacter and handlers.RequestCharacterOptions
    and handlers.ReconfigureCharacter)

local function Player(id,level,admin)
    local p={id=id,level=level or 10,admin=admin,notes={},money=0}
    function p:GetCoinage() return self.money end
    function p:ModifyMoney(delta) self.money=self.money+delta end
    function p:GetGUIDLow() return self.id end
    function p:GetGUID() return "Player-1-"..self.id end
    function p:GetName() return "P"..self.id end
    function p:GetLevel() return self.level end
    function p:GetSelection() return self.target end
    function p:ToPlayer() return self end
    function p:ToCreature() end
    function p:HasSpell() return true end
    function p:LearnSpell() end
    p.chat={}
    function p:SendNotification(t) self.notes[#self.notes+1]=t end
    function p:SendBroadcastMessage(t) self.chat[#self.chat+1]=t end
    players[#players+1]=p
    return p
end
local function Profile(player)
    local p=assert(S.BuildDefaultPlayerProfile(player)); p.revision=1
    S.PlayerProfiles[p.guid]=p; db.stats[p.guid]=true
    return p
end
local function Flush(ok)
    local t=table.remove(transactions,1); assert(t,"no transaction")
    if ok~=false then for _,sql in ipairs(t.sql) do if not Apply(sql) then ok=false end end end
    t.callback(ok~=false)
    return t
end
local function Count(method,player)
    local n=0
    for _,m in ipairs(messages) do if m.method==method and (not player or m.player==player) then n=n+1 end end
    return n
end
local function Last(method,player)
    for i=#messages,1,-1 do
        local m=messages[i]
        if m.method==method and (not player or m.player==player) then return m.payload end
    end
end
local function Codes(errors)
    local set={}
    for _,e in ipairs(errors or {}) do set[e.code]=true; assert(type(e.message_ru)=="string" and e.message_ru~="") end
    return set
end
local function HasSql(t,needle)
    for _,sql in ipairs(t.sql) do if sql:find(needle,1,true) then return sql end end
end
local function Draft(over)
    local d={race="orc",racialFeature="blood_fury",trait="combo",
        archetype="fighter",mastery={skill=1,knowledge=0,endurance=1,craft=0},
        starterItems={"one_handed_common","shield_small","healing_potion"}}
    for k,v in pairs(over or {}) do d[k]=v end
    return d
end
local function Legacy(guid)
    db.creation[guid]={tonumber(guid),"legacy","","human","","fighter","","",0,0,0,0,0,0,0,0,0,0}
end

local cases={}

function cases.options()
    local a=Player("11",14); Profile(a)
    local b=Player("12"); Profile(b); Legacy(b.id)
    handlers.RequestCharacterOptions(a)
    local o=assert(Last("CharacterOptions",a))
    assert(o.catalogVersion==K.CATALOG_VERSION and #o.races==14 and #o.traits==19 and #o.archetypes==4)
    local names={"Орк","Тролль","Таурен","Нежить (Отрекшийся)","Эльф крови","Огр","Гоблин","Пандарен","Человек",
        "Высший эльф","Дворф","Ночной эльф","Дреней","Гном"}
    for i,race in ipairs(o.races) do
        assert(race.name==names[i] and K.Races[race.key].status=="available" and #race.features>=1, race.key)
        assert(race.presetVersion==1 and (race.preset=="book" or race.preset=="default"))
        if race.preset=="default" then
            assert(#race.features==1 and race.features[1].key==race.key.."_default"
                and race.features[1].name=="Без расовых особенностей (заглушка)" and race.size==K.Races[race.key].size)
        end
    end
    assert(o.races[9].key=="human" and o.races[9].preset=="default" and o.races[14].size=="small")
    for _,t in ipairs(o.traits) do
        assert(K.Traits[t.key].status=="available")
        if t.key=="expert" then assert(t.needsChoice and #t.choices==4) end
    end
    assert(o.mastery.basePoints==2 and #o.mastery.keys==4)
    assert(o.starter.maxItems==6 and #o.starter.items==24)
    for _,item in ipairs(o.starter.items) do assert(item.quality=="simple" and item.key and item.name and item.slot and item.kind) end
    assert(o.state.creationState=="none" and o.state.revision==0 and o.state.draft==nil and o.state.rpLevel==5)
    assert(o.state.rpName==nil and o.state.raceUpdateAvailable==false and o.state.scope==nil)
    handlers.RequestCharacterOptions(b)
    local ob=Last("CharacterOptions",b)
    assert(ob.state.creationState=="legacy" and ob.state.draft.archetype=="fighter" and ob.state.draft.race=="human")
    assert(ob.state.draft.rpName==nil)
    assert(#transactions==0)
end

function cases.validation()
    local a=Player("21"); Profile(a)
    local unavailableTrait
    for _,key in ipairs(K.TraitOrder) do if K.Traits[key].status~="available" then unavailableTrait=key; break end end
    local function Errors(over)
        handlers.PreviewCharacter(a,Draft(over))
        local p=Last("CharacterPreview",a); assert(p.ok==false,"expected errors")
        return Codes(p.errors)
    end
    assert(Errors({archetype="paladin"}).unknown_archetype)
    assert(Errors({race="murloc"}).unknown_race)
    assert(Errors({race="human",racialFeature="x"}).unknown_racial_feature)
    assert(Errors({race="human"}).racial_feature_not_of_race)
    assert(Errors({trait=unavailableTrait}).trait_unavailable)
    assert(Errors({trait="nope"}).unknown_trait)
    assert(Errors({racialFeature={"blood_fury","dominance"}}).unknown_racial_feature)
    assert(Errors({racialFeature="vlastnost_x"}).unknown_racial_feature)
    local foreign
    for _,f in ipairs(K.Races.troll.features) do foreign=f.key end
    assert(Errors({racialFeature=foreign}).racial_feature_not_of_race)
    assert(Errors({trait="expert"}).trait_choice_required)
    assert(Errors({mastery={skill=3,knowledge=0,endurance=0,craft=0}}).mastery_points_mismatch)
    assert(Errors({mastery={skill=-1,knowledge=3,endurance=0,craft=0}}).invalid_mastery)
    assert(Errors({mastery={skill=1.5,knowledge=0.5}}).invalid_mastery)
    assert(Errors({mastery={luck=2}}).unknown_mastery)
    assert(Errors({starterItems="x"}).invalid_starter)
    -- D22: rpName from an old client is ignored, never validated.
    handlers.PreviewCharacter(a,Draft({rpName=string.rep("я",300).."|cff"}))
    assert(Last("CharacterPreview",a).ok)
    -- Client numbers are ignored: the resolver never sees equipment/extraModifiers/levels from the draft.
    handlers.PreviewCharacter(a,Draft({maxHealth=999,rpLevel=10,extraModifiers={{source="x",op="add",target="maxHealth",value=50}},
        equipment={armor={key="armor_heavy"}}}))
    local ok=Last("CharacterPreview",a); assert(ok.ok and ok.sheet.maxHealth==15 and ok.sheet.armor==0 and ok.sheet.rpLevel==1)
    handlers.ConfirmCharacter(a,Draft({race="human"}),0,"bad-1")
    local e=Last("CharacterError",a)
    assert(e.code=="invalid_draft" and e.requestId=="bad-1" and Codes(e.errors).racial_feature_not_of_race)
    handlers.ConfirmCharacter(a,Draft(),0,"bad id!")
    assert(Last("CharacterError",a).code=="invalid_request_id")
    handlers.ConfirmCharacter(a,Draft(),-1,"bad-2")
    assert(Last("CharacterError",a).code=="invalid_revision")
    assert(#transactions==0 and S.GetOrLoadCreation(a.id).state=="none")
end

function cases.preview_not_persisting()
    local a=Player("31",14); Profile(a)
    handlers.PreviewCharacter(a,Draft({archetype="defender"}))
    local p=Last("CharacterPreview",a)
    assert(p.ok and p.sheet.rpLevel==5, tostring(p.errors and p.errors[1].code))
    assert(p.sheet.maxHealth==K.Archetypes.defender.levels[5].maxHealth)
    assert(p.sheet.mastery.endurance==1 and type(p.sheet.passive)=="table" and #p.sheet.passive>0)
    assert(p.sheet.block and p.sheet.block.flat and p.sheet.abilitySlots~=nil)
    local warn={}; for _,w in ipairs(p.warnings) do warn[w.code]=true end
    assert(warn.first_creation)
    assert(#transactions==0 and S.GetOrLoadCreation(a.id).state=="none" and not db.creation[a.id])
    assert(S.PlayerProfiles[a.id].archetype=="fighter")
end

function cases.confirm_persists()
    local a=Player("41",14); local p=Profile(a); p.curHealth=3
    handlers.ConfirmCharacter(a,Draft({archetype="defender"}),0,"c-1")
    assert(#transactions==1 and Count("CharacterConfirmed")==0)
    local t=transactions[1]
    assert(t.pool=="characters" and HasSql(t,"`character_rps_stats`") and HasSql(t,"`character_rps_creation`")
        and HasSql(t,"`character_rps_creation_log`") and HasSql(t,"`character_rps_items`") and HasSql(t,"rps_action_receipts"))
    assert(S.PlayerProfiles[a.id].archetype=="fighter" and R.Locks["p:"..a.id])
    Flush()
    assert(not R.Locks["p:"..a.id])
    local c=assert(Last("CharacterConfirmed",a))
    assert(c.requestId=="c-1" and c.revision==1 and c.creation.state=="complete" and c.profile.archetype=="defender")
    local q=S.PlayerProfiles[a.id]
    local row=K.Archetypes.defender.levels[5]
    assert(q.archetype=="defender" and q.raceId=="orc" and q.racialTrait=="blood_fury" and q.commonTrait=="combo")
    assert(q.level==5 and q.maxHealth==row.maxHealth and q.curHealth==q.maxHealth and q.curEnergy==q.maxEnergy)
    assert(q.stats.evasion==row.evasion and q.stats.endurance==1 and q.stats.skill==1 and q.revision==2)
    local sync=Last("SyncProfile",a); assert(sync.creation.state=="complete" and sync.creation.race=="orc")
    assert(#db.items==3 and db.items[1][5]=="storage" and db.items[1][4]=="simple" and db.items[1][8]=="starter")
    -- Relog: the cache is dropped and the confirmed choice comes back from the DB.
    S.Creation[a.id]=nil
    local rec=assert(S.GetOrLoadCreation(a.id))
    assert(rec.state=="complete" and rec.race=="orc" and rec.archetype=="defender" and rec.traits[1]=="combo"
        and rec.mastery.skill==1 and rec.mastery.endurance==1 and rec.revision==1 and rec.starterGranted
        and rec.rpName==nil and rec.racePresetVersion==1)
    assert(not HasSql(t,"rp_name") and HasSql(t,"`race_preset_version`"))
    assert(rec.catalogVersion==K.CATALOG_VERSION and #db.logs==1 and db.logs[1][4]=="none" and db.logs[1][5]=="complete")
end

function cases.new_player_without_profile()
    local a=Player("45")
    handlers.ConfirmCharacter(a,Draft(),0,"np-1")
    assert(#transactions==1 and not HasSql(transactions[1],"`character_rps_creation`"))
    Flush()
    assert(#transactions==1 and HasSql(transactions[1],"`character_rps_creation`"))
    Flush()
    assert(Last("CharacterConfirmed",a).revision==1 and S.PlayerProfiles[a.id].raceId=="orc")
end

function cases.idempotent_request()
    local a=Player("51"); Profile(a)
    handlers.ConfirmCharacter(a,Draft(),0,"id-1")
    handlers.ConfirmCharacter(a,Draft(),0,"id-1")
    assert(Last("CharacterError",a).code=="request_pending" and #transactions==1)
    Flush()
    assert(Count("CharacterConfirmed",a)==1)
    handlers.ConfirmCharacter(a,Draft(),0,"id-1")
    assert(#transactions==0 and Count("CharacterConfirmed",a)==2 and Last("CharacterConfirmed",a).revision==1)
    handlers.ConfirmCharacter(a,Draft({archetype="caster"}),0,"id-1")
    assert(Last("CharacterError",a).code=="request_conflict" and #transactions==0)
    -- Process restart: memory journal empty, the durable receipt still answers.
    Cr.Seen={}; S.Creation={}
    handlers.ConfirmCharacter(a,Draft(),0,"id-1")
    assert(#transactions==0 and Count("CharacterConfirmed",a)==3)
    handlers.ConfirmCharacter(a,Draft({archetype="caster"}),0,"id-1")
    assert(Last("CharacterError",a).code=="request_conflict")
    assert(#db.items==3)
end

function cases.revision_conflict()
    local a=Player("61"); Profile(a)
    handlers.ConfirmCharacter(a,Draft(),5,"rv-1")
    assert(Last("CharacterError",a).code=="revision_conflict" and #transactions==0)
    handlers.ConfirmCharacter(a,Draft(),0,"rv-2")
    Flush()
    handlers.ConfirmCharacter(a,Draft(),1,"rv-3")
    assert(Last("CharacterError",a).code=="already_configured" and #transactions==0)
    -- A failed commit keeps nothing and the same request ID can be retried.
    local b=Player("62"); Profile(b)
    handlers.ConfirmCharacter(b,Draft(),0,"fail-1")
    Flush(false)
    assert(Last("CharacterError",b).code=="save_failed" and not R.Locks["p:"..b.id])
    assert(S.GetOrLoadCreation(b.id).state=="none" and #db.items==3)
    handlers.ConfirmCharacter(b,Draft(),0,"fail-1")
    assert(#transactions==1); Flush()
    assert(Last("CharacterConfirmed",b).revision==1)
end

function cases.starter_kit()
    local a=Player("71"); Profile(a)
    local seven={}
    for i=1,7 do seven[i]="healing_potion" end
    handlers.PreviewCharacter(a,Draft({starterItems=seven}))
    assert(Codes(Last("CharacterPreview",a).errors).too_many_items)
    handlers.PreviewCharacter(a,Draft({starterItems={{key="one_handed_common",quality="quality"}}}))
    assert(Codes(Last("CharacterPreview",a).errors).invalid_quality)
    handlers.PreviewCharacter(a,Draft({starterItems={"excalibur"}}))
    assert(Codes(Last("CharacterPreview",a).errors).unknown_item)
    handlers.ConfirmCharacter(a,Draft({starterItems=seven}),0,"st-7")
    assert(Last("CharacterError",a).code=="invalid_draft" and #transactions==0)
    local six={"two_handed_common","armor_light","arrow","mana_potion","ration",{key="first_aid_kit",quality="simple"}}
    handlers.ConfirmCharacter(a,Draft({starterItems=six}),0,"st-6")
    Flush()
    assert(#db.items==6 and Last("CharacterConfirmed",a))
    for i,row in ipairs(db.items) do assert(row[1]==71 and row[9]==i and row[5]=="storage") end
    assert(db.items[3][3]=="consumable" and db.items[3][7]==10)
    -- Zero items is a valid choice and still consumes the one-time grant.
    local b=Player("72"); Profile(b)
    handlers.ConfirmCharacter(b,Draft({starterItems={}}),0,"st-0")
    assert(not HasSql(transactions[1],"`character_rps_items`")); Flush()
    assert(S.GetOrLoadCreation(b.id).starterGranted and #db.items==6)
end

function cases.legacy_migration()
    local a=Player("81",12); local p=Profile(a); Legacy(a.id)
    p.curHealth,p.curEnergy,p.curWounds,p.xp,p.armor=7,2,2,30,3
    p.equipJson,p.effectsJson='{"unknown":{"x":1}}','{"burn":2}'
    handlers.RequestSync(a)
    assert(Last("SyncProfile",a).creation.state=="legacy")
    handlers.ConfirmCharacter(a,Draft({archetype="healer"}),0,"lg-1")
    local t=Flush()
    local q=S.PlayerProfiles[a.id]
    assert(q.archetype=="healer" and q.level==3 and q.maxHealth==K.Archetypes.healer.levels[3].maxHealth)
    assert(q.curHealth==7 and q.curEnergy==2 and q.curWounds==2 and q.xp==30)
    assert(q.equipJson=='{"unknown":{"x":1}}' and q.effectsJson=='{"burn":2}')
    assert(#db.items==3 and S.GetOrLoadCreation(a.id).state=="complete")
    local log=db.logs[1]
    assert(log[4]=="legacy" and log[9]:find('"curWounds":2',1,true) and log[9]:find('"xp":30',1,true))
end

function cases.reconfigure_staff_only()
    local staff=Player("91",10,true)
    local a=Player("92"); Profile(a)
    handlers.ReconfigureCharacter(a,a:GetGUID(),"хочу ещё","rc-0")
    assert(Last("CharacterError",a).code=="permission_denied" and #transactions==0)
    handlers.ReconfigureCharacter(staff,a:GetGUID(),"ok","rc-1")
    assert(Last("CharacterError",staff).code=="invalid_reason")
    handlers.ReconfigureCharacter(staff,a:GetGUID(),"Смена архетипа","rc-2")
    assert(Last("CharacterError",staff).code=="not_configured" and #transactions==0)
    handlers.ConfirmCharacter(a,Draft(),0,"a-1"); Flush()
    local p=S.PlayerProfiles[a.id]
    p.curHealth,p.curWounds=4,1
    handlers.ReconfigureCharacter(staff,a:GetGUID(),"Смена архетипа","rc-3")
    local t=assert(transactions[1])
    assert(HasSql(t,"`character_rps_creation_log`") and not HasSql(t,"`character_rps_stats`")); Flush()
    local done=Last("CharacterReconfigured",staff)
    assert(done.state=="reconfigure" and done.revision==2 and done.targetGuid==a.id)
    assert(Last("SyncProfile",a).creation.state=="reconfigure" and #a.notes==1)
    handlers.ReconfigureCharacter(staff,a:GetGUID(),"Смена архетипа","rc-3")
    assert(#transactions==0 and Count("CharacterReconfigured",staff)==2)
    handlers.ReconfigureCharacter(staff,a.id,"Ещё раз","rc-4")
    assert(Last("CharacterError",staff).code=="already_reconfigure")
    handlers.RequestCharacterOptions(a)
    local st=Last("CharacterOptions",a).state
    assert(st.creationState=="reconfigure" and st.revision==2 and st.draft.race=="orc" and st.draft.archetype=="fighter")
    handlers.ConfirmCharacter(a,Draft({archetype="caster"}),2,"a-2")
    assert(not HasSql(transactions[1],"`character_rps_items`")); Flush()
    local q=S.PlayerProfiles[a.id]
    assert(q.archetype=="caster" and q.curHealth==4 and q.curWounds==1 and #db.items==3)
    assert(S.GetOrLoadCreation(a.id).state=="complete" and S.GetOrLoadCreation(a.id).revision==3)
    local log=db.logs[2]; assert(log[3]=="reconfigure" and log[6]==91 and log[8]=="Смена архетипа")
    -- Offline target by low GUID.
    db.creation["99"]={99,"complete","v","orc","blood_fury","fighter","combo","",1,0,1,0,1,0,0,1,0,1}
    handlers.ReconfigureCharacter(staff,"99","Разбор жалобы","rc-5"); Flush()
    assert(db.creation["99"][2]=="reconfigure" and Last("CharacterReconfigured",staff).targetGuid=="99")
end

function cases.racial_free_point()
    local a=Player("101"); Profile(a)
    local race,feature
    for _,key in ipairs(K.RaceOrder) do
        for _,f in ipairs(K.Races[key].features) do
            for _,m in ipairs(f.mechanics or {}) do
                if m.target=="masteryPointsFree" then race,feature=key,f.key end
            end
        end
    end
    assert(race,"no racial feature with a free mastery point")
    handlers.PreviewCharacter(a,Draft({race=race,racialFeature=feature}))
    local p=Last("CharacterPreview",a)
    assert(p.ok==false and Codes(p.errors).mastery_points_mismatch and p.errors[1].message_ru:find("3",1,true))
    handlers.PreviewCharacter(a,Draft({race=race,racialFeature=feature,mastery={skill=1,knowledge=1,endurance=1,craft=0}}))
    p=Last("CharacterPreview",a); assert(p.ok and p.sheet.masteryPoints==3)
end

local function Fields(list)
    local set={}
    for _,m in ipairs(list or {}) do
        assert(type(m.step)=="string" and type(m.message_ru)=="string" and m.message_ru~="")
        set[m.field]=m
    end
    return set
end

function cases.preview_missing()
    local a=Player("121"); Profile(a)
    handlers.PreviewCharacter(a,{})
    local p=Last("CharacterPreview",a)
    assert(p.ok==false and #p.missing==5)
    local order={"race","racialFeature","trait","mastery","archetype"}
    for i,field in ipairs(order) do assert(p.missing[i].field==field, i..":"..tostring(p.missing[i].field)) end
    local f=Fields(p.missing)
    assert(f.mastery.left==2 and f.mastery.message_ru:find("2",1,true) and f.starterItems==nil)
    assert(f.race.step=="race" and f.racialFeature.step=="race" and f.trait.step=="trait" and f.archetype.step=="archetype")
    handlers.PreviewCharacter(a,{race="tauren",racialFeature="ancestral_traditions",trait="expert",mastery={skill=1}})
    f=Fields(Last("CharacterPreview",a).missing)
    assert(not f.race and not f.racialFeature and not f.trait and f.traitChoice and f.traitChoice.step=="trait")
    assert(f.mastery.left==2 and f.archetype and not f.starterItems)
    handlers.PreviewCharacter(a,Draft())
    p=Last("CharacterPreview",a); assert(p.ok and p.missing==nil)
    -- Complete choices but an invalid one: errors explain it, nothing is listed as missing.
    handlers.PreviewCharacter(a,Draft({archetype="fighter",trait="expert",traitChoice="skill",
        mastery={skill=2,knowledge=0,endurance=0,craft=0}}))
    assert(Last("CharacterPreview",a).ok)
    handlers.PreviewCharacter(a,Draft({mastery={skill=3}}))
    p=Last("CharacterPreview",a)
    assert(p.ok==false and Codes(p.errors).mastery_points_mismatch and not Fields(p.missing).mastery)
end

function cases.default_race_preset()
    local a=Player("131",14); Profile(a)
    handlers.PreviewCharacter(a,Draft({race="gnome",racialFeature="gnome_default"}))
    local p=Last("CharacterPreview",a)
    assert(p.ok and p.sheet.size=="small" and p.sheet.speed==12 and p.sheet.race=="gnome")
    handlers.ConfirmCharacter(a,Draft({race="human",racialFeature="human_default"}),0,"dp-1"); Flush()
    local c=Last("CharacterConfirmed",a)
    assert(c.creation.race=="human" and c.creation.racialFeature=="human_default" and c.creation.racePresetVersion==1)
    assert(S.PlayerProfiles[a.id].raceId=="human" and S.PlayerProfiles[a.id].racialTrait=="human_default")
    assert(K.DEFAULT_RACE_PRESET.preset=="default" and K.DEFAULT_RACE_PRESET.presetVersion==1
        and #K.DEFAULT_RACE_PRESET.feature.mechanics==0)
end

function cases.race_reset_staff()
    local staff=Player("201",10,true)
    local a=Player("202"); local p=Profile(a)
    handlers.ConfirmCharacter(a,Draft(),0,"rs-1"); Flush()
    p=S.PlayerProfiles[a.id]; p.curHealth,p.curWounds=4,1
    events[42](42,a,"rps race reset")
    assert(#transactions==0 and a.chat[#a.chat]:find(Cr.Message("permission_denied"),1,true))
    staff.target=nil
    events[42](42,staff,"rps race reset")
    assert(#transactions==0 and staff.chat[#staff.chat]:find(Cr.Message("target_not_found"),1,true))
    staff.target=a
    assert(events[42](42,staff,"rps race reset")==false)
    local t=assert(transactions[1])
    assert(HasSql(t,"`character_rps_creation_log`") and not HasSql(t,"`character_rps_stats`") and not HasSql(t,"`character_rps_items`"))
    Flush()
    assert(staff.chat[#staff.chat]:find("сброшены",1,true) and Last("RaceDataReset",staff).scope=="race")
    local rec=S.GetOrLoadCreation(a.id)
    assert(rec.state=="reconfigure" and rec.race=="" and rec.racialFeature=="" and rec.archetype=="fighter" and rec.revision==2)
    local sync=Last("SyncProfile",a).creation
    assert(sync.state=="reconfigure" and sync.scope=="race" and sync.race==nil and sync.archetype=="fighter"
        and sync.raceUpdateAvailable==false)
    assert(#a.notes==1 and db.logs[2][3]=="reconfigure" and db.logs[2][8]=="race_reset" and db.logs[2][9]:find('"scope":"race"',1,true))
    events[42](42,staff,"rps race reset")
    assert(staff.chat[#staff.chat]:find(Cr.Message("already_reconfigure"),1,true) and #transactions==0)
    handlers.RequestCharacterOptions(a)
    local st=Last("CharacterOptions",a).state
    assert(st.scope=="race" and st.draft.race==nil and st.draft.racialFeature==nil and st.draft.archetype=="fighter")
    -- Scope 'race': only race and racial feature may change.
    handlers.PreviewCharacter(a,Draft({race="human",racialFeature="human_default",archetype="caster"}))
    local pv=Last("CharacterPreview",a); assert(pv.ok==false and Codes(pv.errors).race_scope_only)
    handlers.ConfirmCharacter(a,Draft({race="human",racialFeature="human_default",archetype="caster"}),2,"rs-2")
    local err=Last("CharacterError",a)
    assert(err.code=="race_scope_only" and Codes(err.errors).race_scope_only and #transactions==0)
    assert(S.GetOrLoadCreation(a.id).state=="reconfigure")
    handlers.PreviewCharacter(a,Draft({race="human",racialFeature="human_default"}))
    pv=Last("CharacterPreview",a)
    local warn={}; for _,w in ipairs(pv.warnings) do warn[w.code]=true end
    assert(pv.ok and warn.race_reset_scope and warn.resources_kept)
    handlers.ConfirmCharacter(a,Draft({race="human",racialFeature="human_default"}),2,"rs-3")
    assert(not HasSql(transactions[1],"`character_rps_items`")); Flush()
    rec=S.GetOrLoadCreation(a.id)
    assert(rec.state=="complete" and rec.race=="human" and rec.racePresetVersion==1 and rec.revision==3 and #db.items==3)
    local q=S.PlayerProfiles[a.id]
    assert(q.raceId=="human" and q.curHealth==4 and q.curWounds==1 and q.archetype=="fighter")
    -- The tauren free point: the stored allocation no longer fits, so mastery may be redistributed.
    events[42](42,staff,"rps race reset P202 Смена расы"); Flush()
    assert(db.logs[#db.logs][8]=="race_reset: Смена расы")
    handlers.ConfirmCharacter(a,Draft({race="tauren",racialFeature="ancestral_traditions",
        mastery={skill=1,knowledge=1,endurance=1,craft=0}}),4,"rs-4"); Flush()
    assert(S.GetOrLoadCreation(a.id).race=="tauren" and S.PlayerProfiles[a.id].stats.knowledge==1)
    -- Offline character by name.
    db.names["Offline"]=303
    db.creation["303"]={303,"complete","v","orc","blood_fury","fighter","combo","",1,0,1,0,1,0,0,1,0,1}
    events[42](42,staff,"rps race reset Offline Разбор жалобы"); Flush()
    assert(db.creation["303"][2]=="reconfigure" and db.creation["303"][4]=="" and db.creation["303"][7]=="combo")
    events[42](42,staff,"rps race reset Nobody")
    assert(staff.chat[#staff.chat]:find(Cr.Message("target_not_found"),1,true) and #transactions==0)
end

function cases.race_reset_player()
    local a=Player("211"); Profile(a)
    handlers.ResetRaceData(a,"rr-0")
    assert(Last("CharacterError",a).code=="not_configured")
    handlers.ConfirmCharacter(a,Draft(),0,"rr-c1"); Flush()
    handlers.ResetRaceData(a,"rr-1")
    assert(Last("CharacterError",a).code=="race_preset_current" and #transactions==0)
    handlers.RequestSync(a)
    assert(Last("SyncProfile",a).creation.raceUpdateAvailable==false)
    K.Races.orc.presetVersion=2
    handlers.RequestSync(a)
    assert(Last("SyncProfile",a).creation.raceUpdateAvailable==true)
    handlers.ResetRaceData(a,"rr-2"); Flush()
    local done=Last("RaceDataReset",a)
    assert(done.requestId=="rr-2" and done.scope=="race" and done.state=="reconfigure" and done.revision==2)
    local sync=Last("SyncProfile",a).creation
    assert(sync.scope=="race" and sync.raceUpdateAvailable==false and db.logs[2][6]==211)
    handlers.ResetRaceData(a,"rr-2")
    assert(Count("RaceDataReset",a)==2 and #transactions==0)
    handlers.ResetRaceData(a,"rr-3")
    assert(Last("CharacterError",a).code=="already_reconfigure")
    handlers.ConfirmCharacter(a,Draft(),2,"rr-c2"); Flush()
    local rec=S.GetOrLoadCreation(a.id)
    assert(rec.state=="complete" and rec.racePresetVersion==2 and not Cr.RaceUpdateAvailable(rec))
    K.Races.orc.presetVersion=1
    -- Without race_preset_version the version reads as 0 and a player reset is never offered.
    db.presetColumn=false; S.RacePresetColumn=nil
    local b=Player("212"); Profile(b)
    handlers.ConfirmCharacter(b,Draft(),0,"rr-b1")
    assert(not HasSql(transactions[1],"race_preset_version")); Flush()
    S.Creation[b.id]=nil
    rec=S.GetOrLoadCreation(b.id)
    assert(rec.state=="complete" and rec.racePresetVersion==0 and not Cr.RaceUpdateAvailable(rec))
    handlers.ResetRaceData(b,"rr-b2")
    assert(Last("CharacterError",b).code=="creation_unavailable")
end

function cases.archetype_reset_paid()
    local a=Player("221"); Profile(a)
    handlers.ResetArchetype(a,0,"ar-0")
    assert(Last("CharacterError",a).code=="not_configured" and #transactions==0)
    handlers.ConfirmCharacter(a,Draft(),0,"ar-c1"); Flush()
    handlers.RequestSync(a)
    assert(Last("SyncProfile",a).creation.archetypeResetCost==0)
    -- The first reset is free and touches only the creation record, the log and the receipt.
    handlers.ResetArchetype(a,0,"ar-1")
    local t=assert(transactions[1])
    assert(HasSql(t,"`character_rps_creation_log`") and HasSql(t,"rps_action_receipts")
        and not HasSql(t,"`character_rps_stats`") and not HasSql(t,"`character_rps_items`"))
    Flush()
    local done=Last("ArchetypeReset",a)
    assert(done.requestId=="ar-1" and done.scope=="archetype" and done.state=="reconfigure" and done.cost==0 and a.money==0)
    local rec=S.GetOrLoadCreation(a.id)
    assert(rec.state=="reconfigure" and rec.archetype=="" and rec.race=="orc" and rec.traits[1]=="combo" and rec.revision==2)
    local sync=Last("SyncProfile",a).creation
    assert(sync.scope=="archetype" and sync.archetypeResetCost==nil)
    local log=db.logs[#db.logs]
    assert(log[3]=="reconfigure" and log[6]==221 and log[8]=="archetype_reset" and log[9]:find('"scope":"archetype"',1,true))
    handlers.ResetArchetype(a,0,"ar-1")
    assert(Count("ArchetypeReset",a)==2 and #transactions==0, "same request replays without a second write")
    handlers.ResetArchetype(a,0,"ar-2")
    assert(Last("CharacterError",a).code=="already_reconfigure")
    -- Scope 'archetype': the draft comes without an archetype and only the archetype may change.
    handlers.RequestCharacterOptions(a)
    local st=Last("CharacterOptions",a).state
    assert(st.scope=="archetype" and st.draft.archetype==nil and st.draft.race=="orc" and st.draft.trait=="combo")
    handlers.PreviewCharacter(a,Draft({archetype="caster",race="human",racialFeature="human_default"}))
    local pv=Last("CharacterPreview",a); assert(pv.ok==false and Codes(pv.errors).archetype_scope_only)
    handlers.ConfirmCharacter(a,Draft({archetype="caster",mastery={skill=2,knowledge=0,endurance=0,craft=0}}),2,"ar-c2")
    local err=Last("CharacterError",a)
    assert(err.code=="archetype_scope_only" and Codes(err.errors).archetype_scope_only and #transactions==0)
    handlers.PreviewCharacter(a,Draft({archetype="caster"}))
    pv=Last("CharacterPreview",a)
    local warn={}; for _,w in ipairs(pv.warnings) do warn[w.code]=true end
    assert(pv.ok and warn.archetype_reset_scope and warn.resources_kept)
    S.PlayerProfiles[a.id].curHealth=4
    handlers.ConfirmCharacter(a,Draft({archetype="caster"}),2,"ar-c3")
    assert(not HasSql(transactions[1],"`character_rps_items`")); Flush()
    assert(S.PlayerProfiles[a.id].archetype=="caster" and S.PlayerProfiles[a.id].curHealth==4)
    -- The second reset costs 5 silver: a stale price and missing money are refused.
    handlers.RequestSync(a); assert(Last("SyncProfile",a).creation.archetypeResetCost==500)
    handlers.ResetArchetype(a,0,"ar-3")
    assert(Last("CharacterError",a).code=="archetype_reset_cost_changed" and #transactions==0)
    assert(Last("SyncProfile",a).creation.archetypeResetCost==500, "the price is resynced")
    handlers.ResetArchetype(a,500,"ar-4")
    assert(Last("CharacterError",a).code=="not_enough_money" and #transactions==0 and a.money==0)
    -- Money is taken before the commit and returned when the commit fails.
    a.money=700
    handlers.ResetArchetype(a,500,"ar-5")
    assert(a.money==200 and #transactions==1)
    Flush(false)
    assert(Last("CharacterError",a).code=="save_failed" and a.money==700 and S.GetOrLoadCreation(a.id).state=="complete")
    handlers.ResetArchetype(a,500,"ar-6"); Flush()
    assert(a.money==200 and Last("ArchetypeReset",a).cost==500)
    handlers.ConfirmCharacter(a,Draft({archetype="healer"}),4,"ar-c4"); Flush()
    -- The third costs 10 silver; the count is read back from the log when the cache is empty.
    Cr.ArchetypeResets[a.id]=nil
    handlers.RequestSync(a); assert(Last("SyncProfile",a).creation.archetypeResetCost==1000)
    assert(Cr.ArchetypeResetStep==500)
end

function cases.schema_unavailable()
    db.creationSchema=false
    local a=Player("111"); Profile(a)
    handlers.RequestCharacterOptions(a)
    assert(Last("CharacterError",a).code=="creation_unavailable")
    handlers.RequestSync(a)
    local sync=Last("SyncProfile",a); assert(sync and sync.creation==nil)
    handlers.RollStat(a,"skill",false,"roll-1",1)
    assert(#transactions==1)
end

return cases
