package.path = ROOT .. "/NobleNextLua/?.lua;" .. package.path
local cases = {}
local C = require("Modules.RPS_Combat.00_RPS_Config")
local S = require("Modules.RPS_Combat.01_RPS_Storage")
local V = require("Modules.RPS_Combat.04_RPS_Resolver")
local M = require("Modules.RPS_Combat.02_RPS_Combat")
local I = require("Modules.RPS_Combat.07_RPS_Items")
local guid = "Item-1-0020000000000001"
local J1 = [[{"version":1,"revision":1,"name":"Named","description":"","modifiers":{"maxHealth":2,"accuracy":1,"mastery.skill":1}}]]
local J2 = [[{"version":1,"revision":2,"name":"Named II","description":"","modifiers":{"armor":1}}]]
local J3 = [[{"version":1,"revision":1,"name":"Budget","description":"","modifiers":{"energySpendLimit":2}}]]
local parsed = {
    [J1] = {version=1, revision=1, name="Named", description="", modifiers={maxHealth=2, accuracy=1, ["mastery.skill"]=1}},
    [J2] = {version=1, revision=2, name="Named II", description="", modifiers={armor=1}},
    [J3] = {version=1, revision=1, name="Budget", description="", modifiers={energySpendLimit=2}},
}
local WRAP = '{"version":1,"revision":1,"name":"","description":"","modifiers":'
RpsParseItemMetadata = function(json)
    if parsed[json] then return parsed[json], json end
    local body = json:sub(1, #WRAP) == WRAP and json:sub(#WRAP + 1, -2)
    if not body or not body:match("^{.*}$") then return nil, "invalid" end
    local modifiers = {}
    for key, value in body:gmatch('"([%w%.]+)":(%-?%d+)') do modifiers[key] = tonumber(value) end
    return {version=1, revision=1, name="", description="", modifiers=modifiers}, json
end
local function CachedJson(item)
    local metadata = I.Cached(item)
    for json, value in pairs(parsed) do if value == metadata then return json end end
end
local function NewItem(itemGuid, low, entry)
    local item = {entry=entry, maxStack=1, quality=1, enchants={0, 0, 0, 0}, class=4, subclass=1, inventoryType=5}
    function item:GetGUID() return itemGuid end
    function item:GetClass() return self.class end
    function item:GetSubClass() return self.subclass end
    function item:GetInventoryType() return self.inventoryType end
    function item:GetGUIDLow() return low end
    function item:GetEntry() return self.entry end
    function item:GetCount() return 1 end
    function item:GetMaxStackCount() return self.maxStack end
    function item:GetQuality() return 0 end
    function item:IsInTrade() return false end
    return item
end
RpsGetItemQuality = function(item) return item.quality end
RpsGetItemEnchants = function(item) return (table.unpack or unpack)(item.enchants) end
local applied = {}
RpsSetItemEnchant = function(_, item, slot, id) item.enchants[slot + 1] = id; applied[#applied + 1] = "e" .. slot .. "=" .. id; return true end
RpsSetItemGrade = function(_, item, quality) item.quality = quality; applied[#applied + 1] = "q=" .. quality; return true end
local function Query(rows)
    local i, q = 1, {}
    function q:GetString(col) return rows[i][col+1] end
    q.GetUInt32, q.GetUInt64, q.GetUInt8 = q.GetString, q.GetString, q.GetString
    function q:NextRow() i=i+1; return rows[i] ~= nil end
    return q
end
local function Setup()
    local messages, transactions, receipt, nativeJson, syncs, nativeReads = {}, {}, nil, nil, 0, 0
    local p = {equipped={}, staff=true}
    function p:GetGUIDLow() return "1" end
    function p:GetGUID() return "Player-1-00000001" end
    function p:ToPlayer() return self end
    function p:GetEquippedItemBySlot(slot) return self.equipped[slot] end
    function p:GetItemByPos() return self.item end
    function p:GetName() return "Ведущий" end
    function p:GetSelection() return self.selection end
    function p:SaveToDB() self.saved = (self.saved or 0) + 1 end
    function p:SendBroadcastMessage() end
    local item = NewItem(guid, "9007199254740993", 1800001)
    item.valid = true
    local carriers = {[1800001]=true, [1800002]=true, [1800003]=true}
    RpsIsRoleplayItem = function(entry) return carriers[entry] == true and (entry ~= 1800001 or item.valid) end
    p.item = item
    GetPlayersInWorld = function() return {p} end
    GetPlayerByGUID = function(wanted) return wanted == p:GetGUID() and p end
    RpsFindOwnedItem = function(owner, wanted) return owner == p and wanted == guid and item or nil end
    local clock = 0
    GetCurrTime = function() clock=clock+500; return clock end
    local N = {HasStaffPermission=function(player) return player.staff end, Log=function() end,
        AIO={Handle=function(_,_,method,payload) messages[#messages+1]={method=method, payload=payload} end}}
    package.loaded.NobleNext=N
    local R = {ready=true, Storage=S, Combat=M, SyncPlayerState=function() syncs=syncs+1 end,
        NormalizeWireGuid=function(value) return type(value) == "string" and value ~= "" and value or nil end}
    M.BroadcastUnitUpdate = function() end
    CreateLuaEvent = function() end
    local H = {}
    I.Install(R,H)
    RpsCommitAsync = function(pool, sql, callback)
        transactions[#transactions+1]={pool=pool, sql=sql, callback=callback}
    end
    CharDBQuery = function(sql)
        if sql:find("FROM item_instance",1,true) then
            nativeReads=nativeReads+1
            if sql:find("SELECT ii.guid,",1,true) then return Query({{item:GetGUIDLow(), nativeJson or "", nativeJson and 0 or 1}}) end
            return Query({{nativeJson or "", nativeJson and 0 or 1}})
        end
        if sql:find("COUNT",1,true) then return Query({{receipt and 1 or 0}}) end
        if receipt then return Query({receipt}) end
    end
    S.PlayerProfiles, S.Creation = {}, { ["1"]={state="none"} }
    local base = S.BuildDefaultPlayerProfile(p)
    base.revision=1
    for _, key in ipairs({"accuracy","healing","evasion","resistance","skill","knowledge","endurance","craft"}) do
        base.stats[key]=0
    end
    S.PlayerProfiles["1"]=base
    local state={p=p, item=item, H=H, base=base, messages=messages, transactions=transactions}
    function state:SetNative(json) nativeJson=json end
    function state:Advance(ms) clock=clock+ms end
    function state:Reads() return nativeReads end
    function state:Syncs() return syncs end
    function state:SetReceipt(signature, result) receipt={signature,"done",assert(S.EncodeReceipt(result)),"item_metadata"} end
    function state:Flush(saved) local tx=table.remove(transactions,1); assert(tx); tx.callback(saved); return tx end
    return state
end

function cases.overlay()
    local t=Setup()
    t:SetNative(J1); t.p.equipped[0]=t.item
    local effective=I.WithEquipment(t.p,t.base)
    assert(effective.maxHealth==t.base.maxHealth+2)
    assert(effective.stats.accuracy==t.base.stats.accuracy+1)
    assert(effective.stats.skill==t.base.stats.skill+1)
    assert(t.base.stats.accuracy~=effective.stats.accuracy)
    local repeated=I.WithEquipment(t.p,effective)
    assert(repeated.maxHealth==effective.maxHealth and repeated.stats.accuracy==effective.stats.accuracy)
    assert(S.BuildSave(effective)==S.BuildSave(t.base))
    t.p.equipped[0]=nil
    assert(I.WithEquipment(t.p,effective).maxHealth==t.base.maxHealth)
end

function cases.caps()
    local t=Setup()
    local trait
    local K=require("Modules.RPS_Combat.03_RPS_Catalog")
    for key, entry in pairs(K.Traits) do
        for _, op in ipairs(entry.mechanics or {}) do
            if op.target=="accuracy" and op.op=="cap" then trait=key end
        end
    end
    assert(trait,"need a fixed accuracy trait")
    local creation={state="complete",archetype="fighter",race="blood_elf",racialFeature="mana_tap",
        traits={trait},mastery={skill=1,endurance=1,knowledge=0,craft=0}}
    local input=require("Modules.RPS_Combat.06_RPS_Progression").SheetInput(creation,1)
    local baseSheet=assert(V.Resolve(input))
    t.base.stats.accuracy=baseSheet.accuracy
    S.Creation["1"]=creation
    t:SetNative(J1); t.p.equipped[0]=t.item
    assert(I.WithEquipment(t.p,t.base).stats.accuracy<=2)
    creation.racialFeature="invalid_feature"
    assert(I.WithEquipment(t.p,t.base).stats.accuracy==t.base.stats.accuracy,
        "invalid confirmed choices must not bypass the sheet resolver")
end

function cases.damage()
    local t=Setup()
    t:SetNative(J1); t.p.equipped[0]=t.item
    local effective=I.WithEquipment(t.p,t.base)
    local hit=assert(M.ApplyDamageToUnit(effective,3,"physical",0))
    local oldHealth=t.base.curHealth
    S.SaveProfiles({hit},function(ok) assert(ok) end)
    t:Flush(true)
    assert(S.PlayerProfiles["1"].curHealth==oldHealth-3)
    assert(S.PlayerProfiles["1"].maxHealth==t.base.maxHealth)
    assert(S.PlayerProfiles["1"].stats.accuracy==t.base.stats.accuracy)
end

function cases.read()
    local t=Setup()
    t:SetNative(J1)
    t.H.RequestItemMetadata(t.p,guid)
    local reply=t.messages[#t.messages].payload
    assert(reply.state=="ready" and reply.metadata.name=="Named" and CachedJson(t.item)==J1)
    t.H.RequestItemMetadata(t.p,"Item-1-0000000000000002")
    assert(t.messages[#t.messages].payload.state=="unknown")
end

function cases.editor()
    local t=Setup()
    I.Set(t.p,255,0,J1,"test change","edit_1")
    assert(CachedJson(t.item)==nil and #t.transactions==1)
    local tx=t.transactions[1]
    assert(tx.pool=="characters" and #tx.sql==2)
    assert(tx.sql[1]:find("9007199254740993",1,true))
    assert(tx.sql[1]:find("rm.item_guid IS NULL",1,true))
    assert(tx.sql[2]:find("INSERT INTO rps_item_metadata",1,true))
    assert(not tx.sql[2]:find("UPDATE item_instance",1,true))
    local signature="255:0:test change:"..J1
    t:SetReceipt(signature,{guid=guid,revision=1,json=J1})
    t:SetNative(J1)
    t:Flush(true)
    assert(CachedJson(t.item)==J1 and t.messages[#t.messages].payload.ok)
    I.Install({ready=true,Combat=M,SyncPlayerState=function() end,NormalizeWireGuid=function(value) return tostring(value) end},t.H)
    I.Set(t.p,255,0,J1,"test change","edit_1")
    assert(#t.transactions==0 and t.messages[#t.messages].payload.duplicate)
    t.p.item=nil
    I.Set(t.p,255,0,J1,"test change","edit_1")
    assert(t.messages[#t.messages].payload.ok)
    -- Replay keeps its old reply while native memory follows the newer durable revision.
    t:SetNative(J2)
    I.Set(t.p,255,0,J1,"test change","edit_1")
    assert(t.messages[#t.messages].payload.revision==1 and CachedJson(t.item)==J2)
end

function cases.failure()
    local t=Setup()
    I.Set(t.p,255,0,J1,"test change","edit_1")
    t:Flush(false)
    assert(CachedJson(t.item)==nil and t.messages[#t.messages].payload.code=="save_failed")
    I.Set(t.p,255,0,J2,"test change","edit_2")
    assert(#t.transactions==0 and t.messages[#t.messages].payload.code=="stale_item")
    t.item.maxStack=20
    I.Set(t.p,255,0,J1,"test change","edit_3")
    assert(#t.transactions==0 and t.messages[#t.messages].payload.code=="item_not_rp_only")
    t:SetReceipt("different",{})
    I.Set(t.p,255,0,J1,"test change","edit_1")
    assert(t.messages[#t.messages].payload.code=="request_conflict")
end

function cases.recovery()
    local t=Setup()
    t:SetNative(J1); t.p.equipped[0]=t.item
    local effective=I.WithEquipment(t.p,t.base)
    assert(CachedJson(t.item)==J1 and effective.maxHealth==t.base.maxHealth+2)
    local reads=t:Reads()
    I.WithEquipment(t.p,t.base)
    assert(t:Reads()==reads,"normal reads must not query DB on each action")
    t:SetNative(J2)
    t:Advance(31000)
    effective=I.WithEquipment(t.p,t.base)
    assert(CachedJson(t.item)==J2 and effective.armor==1 and effective.maxHealth==t.base.maxHealth)
end

function cases.poll()
    local t=Setup()
    I.PollPlayer(t.p)
    local syncs=t:Syncs()
    I.PollPlayer(t.p)
    assert(t:Syncs()==syncs)
    t:SetNative(J1); t.p.equipped[0]=t.item
    I.PollPlayer(t.p)
    assert(t:Syncs()==syncs+1)
    t.p.equipped[0]=nil
    I.PollPlayer(t.p)
    assert(t:Syncs()==syncs+2)
end

function cases.budget()
    local t=Setup()
    t:SetNative(J3); t.p.equipped[0]=t.item
    local effective=I.WithEquipment(t.p,t.base)
    assert(effective.energySpendLimit==8)
    local spent=assert(M.SpendEnergy(effective,8))
    S.SaveProfiles({spent},function(ok) assert(ok) end)
    t:Flush(true)
    assert(S.PlayerProfiles["1"].energySpentRound==8)
    t.p.equipped[0]=nil
    local unequipped=I.WithEquipment(t.p,S.PlayerProfiles["1"])
    local rejected,code=M.SpendEnergy(unequipped,1)
    assert(not rejected and code=="round_budget_exhausted")
    assert(M.SpendEnergy(unequipped,0))
end

local function DefinitionQuery(tables)
    return function(sql)
        for name, rows in pairs(tables) do
            if sql:find("FROM " .. name .. "$") or sql:find("FROM " .. name .. " ") then
                return #rows > 0 and Query(rows) or nil
            end
        end
    end
end

function cases.sets()
    local t=Setup()
    local problems=I.LoadDefinitions(DefinitionQuery({
        rps_item_set={{"guard","Комплект стража"}},
        rps_item_set_bonus={{"guard",2,'{"maxEnergy":1}'},{"guard",3,'{"maxHealth":1}'}},
        rps_item_template={{1800001,'{"maxHealth":1}',"guard"},{1800002,"","guard"},{1800003,'{"speed":1}',""}},
    }))
    assert(#problems==0)
    local second=NewItem("Item-1-0020000000000002","9007199254740994",1800002)
    t.p.equipped[0]=t.item
    local one=I.WithEquipment(t.p,t.base)
    assert(one.maxHealth==t.base.maxHealth+1 and one.maxEnergy==t.base.maxEnergy, "one piece: own property only")
    t.p.equipped[1]=second
    local two=I.WithEquipment(t.p,t.base)
    assert(two.maxHealth==t.base.maxHealth+1 and two.maxEnergy==t.base.maxEnergy+1, "two pieces reach the first threshold")
    local kinds={}
    for _, source in ipairs(two.itemModifiers) do kinds[source.kind]=(kinds[source.kind] or 0)+1 end
    assert(kinds.item==1 and kinds.set==1)
    -- A non-set item adds its own property but never advances the set counter.
    t.p.equipped[2]=NewItem("Item-1-0020000000000003","9007199254740995",1800003)
    local mixed=I.WithEquipment(t.p,t.base)
    assert(mixed.speed==t.base.speed+1 and mixed.maxHealth==t.base.maxHealth+1)
    -- Bonuses are recomputed from the current equipment, not accumulated.
    t.p.equipped[1]=nil
    assert(I.WithEquipment(t.p,mixed).maxEnergy==t.base.maxEnergy)
end

function cases.definitions_validation()
    Setup()
    local problems=I.LoadDefinitions(DefinitionQuery({
        rps_item_set={{"guard","Комплект стража"}},
        rps_item_set_bonus={{"missing",2,'{"maxEnergy":1}'},{"guard",2,"broken"}},
        rps_item_template={{1800002,'{"maxHealth":1}',"unknown_set"},{40582,'{"maxHealth":1}',""},{1800003,"broken",""}},
        rps_item_enchant={{18001,"enchant","A",'{"accuracy":1}',""},{18002,"enchant","B","broken",""},{18501,"socket","C","{}",""}},
    }))
    table.sort(problems)
    assert(table.concat(problems,",")=="enchant:18002,enchant:18501,set_bonus:guard:2,set_bonus:missing:2,template:1800002,template:1800003",
        table.concat(problems,","))
end

local CATALOG = {
    rps_item_enchant={{18001,"enchant","Чары точности",'{"accuracy":1}',""},{18005,"enchant","Сияние","{}","Пустышка"},
        {18501,"gem","Камень жизни",'{"maxHealth":1}',""},{18503,"gem","Камень стойкости",'{"resistance":1}',""}},
}

-- Enchant and gems count on any single item, gems only within the slots of the current grade.
function cases.enchants()
    local t=Setup()
    assert(#I.LoadDefinitions(DefinitionQuery(CATALOG))==0)
    local native=NewItem("Item-1-0020000000000009","9007199254741001",40582)
    native.quality, native.enchants = 2, {18001, 18501, 18503, 0}
    t.p.equipped[0]=native
    local effective=I.WithEquipment(t.p,t.base)
    assert(effective.stats.accuracy==t.base.stats.accuracy+1)
    assert(effective.maxHealth==t.base.maxHealth+1, "uncommon has one gem slot")
    assert(effective.stats.resistance==t.base.stats.resistance, "second gem stays dormant at uncommon")
    native.quality=3
    assert(I.WithEquipment(t.p,t.base).stats.resistance==t.base.stats.resistance+1, "rare opens the second gem slot")
    native.enchants={18501, 18001, 0, 0}
    local swapped=I.WithEquipment(t.p,t.base)
    assert(swapped.maxHealth==t.base.maxHealth and swapped.stats.accuracy==t.base.stats.accuracy, "kinds must match slots")
    native.maxStack=20
    assert(I.WithEquipment(t.p,t.base).stats.accuracy==t.base.stats.accuracy, "stackable items carry nothing")
end

function cases.enchant_staff()
    local t=Setup()
    assert(#I.LoadDefinitions(DefinitionQuery(CATALOG))==0)
    local function last() return t.messages[#t.messages].payload end
    t.item.quality=1
    assert(I.Enchant(t.p,t.p,255,0,"enchant",0,18001) and t.item.enchants[1]==18001)
    assert(not I.Enchant(t.p,t.p,255,0,"gem",1,18501) and last().code=="no_gem_slot", "common has no gem slots")
    assert(not I.Enchant(t.p,t.p,255,0,"enchant",0,18501) and last().code=="unknown_enchant", "a gem is not an enchant")
    assert(not I.Enchant(t.p,t.p,255,0,"enchant",0,99999) and last().code=="unknown_enchant")
    assert(not I.Enchant(t.p,t.p,255,0,"grade",0,6) and last().code=="invalid_grade")
    assert(I.Enchant(t.p,t.p,255,0,"grade",0,4) and t.item.quality==4)
    assert(I.Enchant(t.p,t.p,255,0,"gem",3,18503) and t.item.enchants[4]==18503)
    assert(I.Enchant(t.p,t.p,255,0,"enchant",0,0) and t.item.enchants[1]==0, "0 removes the enchant")
    assert(t.p.saved==4 and last().ok)
    t.p.staff=false
    assert(not I.Enchant(t.p,t.p,255,0,"enchant",0,18001) and last().code=="permission_denied")
    t.p.staff=true
    t.item.maxStack=20
    assert(not I.Enchant(t.p,t.p,255,0,"enchant",0,18001) and last().code=="item_not_rp_only")
    t.item.maxStack=1
    -- Chat command targets the selected player, AIO state lists equipment and catalog.
    t.p.selection=t.p
    assert(I.Command(t.p,"rps item gem 255 0 1 18501")==false and t.item.enchants[2]==18501)
    t.p.equipped[0]=t.item
    t.H.RequestItemEnchantState(t.p,t.p:GetGUID())
    local state=last()
    assert(#state.catalog==4 and state.state.slots[1].gems[1]==18501 and state.state.slots[1].grade==4)
    t.H.RequestItemMetadata(t.p,guid)
    local reply=last()
    assert(reply.rpItem and reply.gemSlots==3 and #reply.enchants==2
        and reply.enchants[1].name=="Камень жизни" and reply.enchants[2].socket==3)
end

-- Hand items follow the design document: type from the native subclass or rps_item_equip_type,
-- damage/block dice in the effective profile only, base dice restored before saving.
function cases.weapons()
    local t=Setup()
    assert(#I.LoadDefinitions(DefinitionQuery({rps_item_equip_type={{2129,"shield_medium"},{7,"no_such_key"}}}))==1)
    S.Creation["1"]={state="complete",archetype="fighter",race="human",racialFeature="human_default",
        traits={"fortunes_favorite"},mastery={skill=1,endurance=1,knowledge=0,craft=0}}
    local function Hand(slot, entry, class, subclass, quality, inventoryType)
        local item=NewItem("Item-1-00200000000001"..slot..entry%10,"90071992547410"..slot,entry)
        item.class, item.subclass, item.quality, item.inventoryType = class, subclass, quality, inventoryType or 13
        t.p.equipped[slot]=item
        return item
    end
    local base=I.WithEquipment(t.p,t.base)
    assert(base.weaponDice~=nil and base.blockDice==t.base.blockDice, "unarmed keeps the base block")
    Hand(15,8,2,8,1,17)
    local sword=I.WithEquipment(t.p,t.base)
    assert(sword.weaponDice:match("^1d12"), sword.weaponDice)
    assert(I.BaseProfile(sword).weaponDice==t.base.weaponDice and S.BuildSave(sword)==S.BuildSave(t.base))
    Hand(15,8,2,8,2,17)
    local good=I.WithEquipment(t.p,t.base)
    local function Bonus(dice) return tonumber(dice:match("[+-]%d+$") or "0") end
    assert(Bonus(good.weaponDice)==Bonus(sword.weaponDice)+1, "quality adds +1 damage")
    Hand(16,2129,4,6,1)
    assert(I.WithEquipment(t.p,t.base).blockDice==t.base.blockDice, "a two-handed weapon drops the shield")
    Hand(15,4,2,4,1,13)
    local shielded=I.WithEquipment(t.p,t.base)
    assert(shielded.weaponDice:match("^1d8") and shielded.blockDice:match("^1d6"), shielded.blockDice)
    Hand(16,2362,4,6,1)
    assert(I.WithEquipment(t.p,t.base).blockDice:match("^1d4"), "an unlisted shield is small")
    t.p.equipped[16]=nil
    Hand(15,3,2,3,1,26)
    assert(I.WithEquipment(t.p,t.base).weaponDice:match("^3d6"), "a gun is a two-handed gunpowder weapon")
    Hand(15,6,2,6,1,13)
    assert(I.WithEquipment(t.p,t.base).weaponDice:match("^1d6"), "a one-handed polearm is a one-handed long weapon")
    -- The tooltip gets the type and the item's own dice.
    local item=Hand(15,8,2,8,1,17)
    RpsFindOwnedItem=function() return item end
    t.H.RequestItemMetadata(t.p,"Item-1-0020000000000158")
    local reply=t.messages[#t.messages].payload
    assert(reply.equip and reply.equip.name:find("Двуручное",1,true) and reply.equip.dice.strike=="1d12"
        and reply.equip.dice.throw=="1d4" and reply.equip.quality=="Простое")
end

-- The isolated MySQL suite executes these actual server-generated statements.
function cases.export(path, revision)
    local t=Setup()
    if revision==2 then t:SetNative(J1) end
    I.Set(t.p,255,0,revision==2 and J2 or J1,"test change",revision==2 and "edit_2" or "edit_1")
    assert(#t.transactions==1,"editor did not emit a transaction")
    local file=assert(io.open(path,"w"))
    for _, sql in ipairs(t.transactions[1].sql) do file:write(sql,";\n") end
    file:close()
end
function cases.vendor()
    local t = Setup()
    assert(#I.LoadDefinitions(DefinitionQuery({rps_item_equip_type={
        {2362,"shield_small"},{2129,"shield_medium"},{1200,"shield_large"},{152866,"one_handed_reach"}}})) == 0)
    local entries = {
        {25,2,7,21,1}, {36,2,4,21,1}, {37,2,0,13,1}, {2092,2,15,13,1},
        {2362,4,6,14,1}, {35,2,10,17,1}, {1194,2,8,17,1}, {12282,2,1,17,1},
        {2361,2,5,17,1}, {2504,2,2,15,1}, {2508,2,3,26,1}, {57243,2,6,17,1},
        {23347,2,18,26,1}, {223425,2,19,26,1}, {152866,2,6,13,0},
        {2129,4,6,14,1}, {1200,4,6,14,1},
    }
    local byEntry = {}
    for _, row in ipairs(entries) do byEntry[row[1]] = row end
    RpsGetItemTemplate = function(entry)
        local row = byEntry[entry]
        if row then return row[2], row[3], row[4], row[5], 1 end
    end
    GetCurrTime = function() return 100 end -- All vendor/comparison requests arrive in one frame.
    for _, row in ipairs(entries) do
        t.H.RequestItemTemplate(t.p,row[1])
        local reply = t.messages[#t.messages].payload
        local item = NewItem(guid, "1", row[1])
        item.class,item.subclass,item.inventoryType,item.quality = row[2],row[3],row[4],row[5]
        local owned = I.EquipInfo(item)
        assert(reply.entry == row[1] and reply.equip.name == owned.name)
        assert(not reply.equip.name:find("·",1,true))
        assert(reply.metadata == nil and reply.guid == nil)
        assert(reply.equip.block or next(reply.equip.dice), "every starter weapon/shield has RP dice")
        assert(reply.equip.block == owned.block)
        for mode, dice in pairs(owned.dice or {}) do assert(reply.equip.dice[mode] == dice) end
    end
    local before = #t.messages
    t.H.RequestItemMetadata(t.p,guid)
    assert(#t.messages == before + 1, "owned comparison is not dropped after a preview burst")
    t.H.RequestItemTemplate(t.p,999999)
    assert(t.messages[#t.messages].payload.state == "unknown")
    before = #t.messages
    for _, entry in ipairs({-1, 1.5, "25", math.huge}) do t.H.RequestItemTemplate(t.p,entry) end
    assert(#t.messages == before)
end


function cases.property_overrides()
    local t = Setup()
    assert(#I.LoadDefinitions(DefinitionQuery(CATALOG)) == 0)
    t.item.quality, t.item.enchants = 3, {18001, 18501, 18503, 0}
    t.p.equipped[0] = t.item
    local json = "property_override_fixture"
    parsed[json] = {version=1, revision=1, name="", description="", modifiers={maxHealth=2},
        properties={accuracy=-2, armor=3}, runes={["1"]={}, ["2"]={resistance=-3, maxEnergy=2}}}
    t:SetNative(json)
    local effective = I.WithEquipment(t.p,t.base)
    assert(effective.stats.accuracy == t.base.stats.accuracy - 2, "override replaces native +1, never adds both")
    assert(effective.armor == t.base.armor + 3)
    assert(effective.maxHealth == t.base.maxHealth + 2, "empty rune overrides the old health gem")
    assert(effective.stats.resistance == t.base.stats.resistance - 3)
    assert(effective.maxEnergy == t.base.maxEnergy + 2)
    t.item.quality = 2
    effective = I.WithEquipment(t.p,t.base)
    assert(effective.stats.resistance == t.base.stats.resistance, "quality closes an overridden rune too")
    assert(effective.maxEnergy == t.base.maxEnergy)
end

function cases.property_editor()
    local t = Setup()
    local json = [[{"version":1,"revision":1,"name":"","description":"","modifiers":{},"properties":{"accuracy":-2,"maxHealth":4}}]]
    parsed[json] = {version=1, revision=1, name="", description="", modifiers={}, properties={accuracy=-2,maxHealth=4}}
    local function Edit(id, values, targetGuid, itemGuid)
        t.H.DmItemProperties(t.p,targetGuid or t.p:GetGUID(),itemGuid or guid,0,0,"enchant",0,
            values or {accuracy=-2,maxHealth=4},"test change",id)
    end
    Edit("props_1")
    assert(#t.transactions == 1, t.messages[#t.messages] and t.messages[#t.messages].payload.code)
    assert(t.transactions[1].sql[1]:find("ii.owner_guid=1",1,true))
    assert(CachedJson(t.item) == nil, "no publish before commit")
    for _, message in ipairs(t.messages) do assert(message.method ~= "ItemChanged", "no item event before commit") end
    local signature = table.concat({"properties",t.p:GetGUID(),guid,0,0,"enchant",0,"test change",[[{"accuracy":-2,"maxHealth":4}]]},":")
    t:SetReceipt(signature,{guid=guid,revision=1,json=json}); t:SetNative(json); t:Flush(true)
    assert(t.messages[#t.messages].payload.ok)
    local snapshot = t.messages[#t.messages].payload.state
    assert(snapshot and snapshot.target==t.p:GetGUID() and snapshot.slots[1].metadata.revision==1,
        "confirmed result carries current editor state")
    t.p.item = nil; t:SetNative(J2)
    Edit("props_1")
    assert(#t.transactions == 0 and t.messages[#t.messages].payload.duplicate, "replay precedes moved item check")
    Edit("props_1",{accuracy=-3,maxHealth=4})
    assert(t.messages[#t.messages].payload.code == "request_conflict")
    t.p.staff=false; local before=#t.messages; Edit("props_2"); assert(#t.messages==before)
end

return cases
