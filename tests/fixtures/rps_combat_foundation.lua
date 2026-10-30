package.path = ROOT .. "/NobleNextLua/?.lua;" .. package.path
local C = require("Modules.RPS_Combat.00_RPS_Config")
local S = require("Modules.RPS_Combat.01_RPS_Storage")
local M = require("Modules.RPS_Combat.02_RPS_Combat")
local cases = {}

local function Rows()
    return {
        {key="skill", category="mastery", sortOrder=10, name="Навык", icon="dice", spellId=0,
            diceFormula="3d6", defaultValue=0, description=""},
        {key="health", category="general", sortOrder=10, name="ОЗ", icon="hp", spellId=0,
            diceFormula="none", defaultValue=15, description=""},
        {key="accuracy", category="combat", sortOrder=10, name="Меткость", icon="dice", spellId=1500001,
            diceFormula="3d6", defaultValue=0, description=""},
    }
end

local function Fixed(values)
    local i = 0
    return function(low, high)
        i = i + 1
        assert(values[i] and values[i] >= low and values[i] <= high)
        return values[i]
    end
end

function cases.rolls()
    local energy, triples, distribution = 0, 0, {}
    for a = 1, 6 do for b = 1, 6 do for c = 1, 6 do
        local counts = {}
        for _, face in ipairs({a,b,c}) do counts[face] = (counts[face] or 0) + 1 end
        local expected = 0
        for face, count in pairs(counts) do if count >= 2 then expected = face end end
        local roll = assert(C.Roll3d6(-2, 4, 0, Fixed({a,b,c})))
        assert(roll.total == a+b+c+2 and roll.diceSum == a+b+c)
        assert(roll.energyGained == expected and roll.matchedFace == expected)
        energy = energy + roll.energyGained
        distribution[a+b+c] = (distribution[a+b+c] or 0) + 1
        if counts[a] == 3 then triples = triples + 1 end
        local tired = assert(C.Roll3d6(0, 0, 3, Fixed({a,b,c})))
        assert(tired.energyGained == math.max(0, expected-3))
    end end end
    assert(energy == 336 and triples == 6)
    assert(distribution[3] == 1 and distribution[10] == 27 and distribution[18] == 1)
    assert(not C.Roll3d6(0/0, 0, 0))
    assert(not C.Roll3d6(0, -1, 0))
    assert(not pcall(C.Roll3d6, 0, 0, 0, function() return 7 end))
end

function cases.dice()
    local low = assert(C.RollDiceString("2d6-1", 0, Fixed({1,1})))
    local high = assert(C.RollDiceString("2d6+1", 0, Fixed({6,6})))
    assert(low.total == 1 and high.total == 13)
    assert(C.RollDiceString("1d4-10", 0, Fixed({1})).total == 0)
    assert(C.RollDiceString("0").total == 0 and C.RollDiceString("12", 3).total == 15)
    assert(C.RollDiceString("1D20", 0, Fixed({20})).total == 20)
    for _, formula in ipairs({"", "none", "weapon", "0d6", "21d6", "1d0", "1d101", "1d6+",
        "1d6-", "1d6+1x", "1d6;DROP", "1d6+1001", "1.5d6", "1d6+nan", " 1d6", "-1001"}) do
        assert(not C.ParseDice(formula), formula)
    end
    assert(not C.RollDiceString("1d6", math.huge))
end

function cases.registry()
    local rows = Rows()
    assert(C.ReplaceStatDefinitions(rows))
    assert(C.StatOrder[1].key == "health" and C.StatOrder[3].key == "skill")
    assert(C.SpellToStatKey[1500001] == "accuracy")
    rows[1].name = "changed"
    assert(C.StatDefs.skill.name == "Навык")
    local old = C.StatDefs
    rows = Rows(); rows[1].spellId = 1500001
    assert(not C.ReplaceStatDefinitions(rows) and C.StatDefs == old)
    rows = Rows(); rows[1].key = "accuracy"
    assert(not C.ReplaceStatDefinitions(rows) and C.StatDefs == old)
    rows = Rows(); rows[1].diceFormula = "1d6+"
    assert(not C.ReplaceStatDefinitions(rows) and C.StatDefs == old)
    assert(not C.LoadStatDefinitions(function() return nil end) and C.StatDefs == old)
    rows = Rows(); rows[3].spellId = 0
    assert(C.ReplaceStatDefinitions(rows) and next(C.SpellToStatKey) == nil)
end

function cases.codec()
    for _, id in ipairs({"4294967297", "9007199254740993", "18446744073709551615"}) do
        assert(C.IdString(id) == id)
    end
    assert(C.IdString("00042") == "42" and C.IdString(0) == "0")
    for _, id in ipairs({"18446744073709551616", "1e3", "-1", "1;DROP", "", "0.1"}) do
        assert(not C.IdString(id))
    end
    assert(not C.IdString(9007199254740992) and not C.IdString(math.huge))
    local encoded = assert(S.EncodeFlatJson({accuracy=-2, inactive_stat=3, skill=0}))
    assert(encoded == '{"accuracy":-2,"inactive_stat":3,"skill":0}')
    local decoded = assert(S.DecodeFlatJson(' { "accuracy": -2, "skill":0 } '))
    assert(decoded.accuracy == -2 and decoded.skill == 0)
    assert(next(assert(S.DecodeFlatJson("{}"))) == nil)
    for _, text in ipairs({'{"a":1,"a":2}', '{"a":1,}', '{"a":1} garbage', '{"a":1.5}',
        '{"a":01}', '{"a":true}', '{"a":"1"}', '{"a":{"x":1}}', '{"bad-key":1}', '{"a":1001}'}) do
        assert(not S.DecodeFlatJson(text), text)
    end
    assert(not S.EncodeFlatJson({x="quote\""}))
end

local function Query(rows)
    if #rows == 0 then return nil end
    local index, q = 1, {}
    function q:GetString(col) return rows[index][col+1] end
    q.GetUInt8, q.GetUInt32, q.GetUInt64, q.GetInt32 = q.GetString, q.GetString, q.GetString, q.GetString
    function q:NextRow() index = index + 1; return rows[index] ~= nil end
    return q
end

function cases.spell_diagnostics()
    local reasons = {[1500001]="ok", [1500002]="no_spellinfo", [1500003]="effect:1:2"}
    RpsDiceSpellStatus = function(id) local r = reasons[id] or "no_spellinfo"; return r == "ok", r end
    assert(select(2, C.SpellStatus(0)) == "unmapped" and select(2, C.SpellStatus(1500002)) == "no_spellinfo")
    local rows = {{key="a", spellId=1500001}, {key="b", spellId=1500002}, {key="c", spellId=0}, {key="d", spellId=1500003}}
    local bad = C.DiagnoseSpells(rows)
    assert(#bad == 2 and bad[1].key == "b" and bad[1].reason == "no_spellinfo")
    assert(bad[2].key == "d" and bad[2].spellId == 1500003 and bad[2].reason == "effect:1:2")
    local function Row(key, sort, id) return {key, "combat", sort, key, "dice", id, "3d6", 0, ""} end
    local function Load(list) return function() return Query(list) end end
    assert(C.LoadStatDefinitions(Load({Row("accuracy",1,1500001), Row("healing",2,1500002), Row("skill",3,0)})))
    assert(C.SpellToStatKey[1500001] == "accuracy" and C.SpellToStatKey[1500002] == nil)
    assert(C.StatDefs.healing.spellId == 0 and C.StatDefs.healing.configuredSpellId == 1500002)
    assert(C.StatDefs.healing.spellUnavailable == "no_spellinfo" and C.StatDefs.accuracy.spellUnavailable == nil)
    assert(#C.SpellDiagnostics == 1 and C.SpellDiagnosticsText() == "healing:1500002:no_spellinfo")
    -- Even an entirely bad spell set keeps the stat registry usable.
    assert(C.LoadStatDefinitions(Load({Row("accuracy",1,1500003), Row("healing",2,1500002)})))
    assert(next(C.SpellToStatKey) == nil and #C.SpellDiagnostics == 2 and C.StatDefs.accuracy)
    -- Legacy binding without a reason.
    RpsDiceSpellStatus = nil
    RpsIsDiceSpell = function(id) return id == 1500001 end
    assert(select(2, C.SpellStatus(1500002)) == "unsafe" and C.SpellStatus(1500001))
    RpsIsDiceSpell = nil
    assert(select(2, C.SpellStatus(1500001)) == "no_binding")
    assert(not C.LoadStatDefinitions(function() return nil end))
end

function cases.players()
    assert(C.ReplaceStatDefinitions(Rows()))
    local player = {GetGUIDLow=function() return "4294967297" end}
    local p = assert(S.BuildDefaultPlayerProfile(player))
    assert(p.guid == "4294967297" and p.maxHealth == 15 and p.curEnergy == 10 and p.stats.accuracy == 2)
    assert(p.stats.skill == 0)
    assert(not S.BuildDefaultPlayerProfile(player, "unknown"))
    local queries = 0
    local function Load(sql)
        assert(sql:find("WHERE guid = 4294967297", 1, true))
        queries = queries + 1
        return Query({{"fighter","human","trait","common",3,45,7,18,4,12,5,2,3,1,9,"2d6-1","1d4",
            '{"accuracy":-1,"retired":2}', '{"hand":{"item":"x"}}', '{"burn":{"charges":2}}'}})
    end
    p = assert(S.GetOrLoadPlayerProfile(player, Load))
    assert(p.curHealth == 7 and p.energySpentRound == 5 and p.curWounds == 2)
    assert(p.stats.retired == 2 and p.stats.skill == 0 and p.stats.accuracy == -1)
    assert(p.equipJson == '{"hand":{"item":"x"}}' and p.effectsJson == '{"burn":{"charges":2}}')
    assert(S.GetOrLoadPlayerProfile(player, Load) == p and queries == 1)
    S.ReleasePlayer(player)
    local missing, err = S.GetOrLoadPlayerProfile(player, function() return nil end)
    assert(missing == nil and err == "profile_missing_or_query_failed" and next(S.PlayerProfiles) == nil)
end

local function Creature(guid, spawn, entry, instance)
    return {GetGUID=function() return guid end, GetDBTableGUIDLow=function() return spawn end,
        GetEntry=function() return entry end, GetMapId=function() return 1 end,
        GetInstanceId=function() return instance or 0 end, GetName=function() return "NPC" end}
end

local function Baseline()
    return {entry=100, source="template", curHealth=20, maxHealth=20, curEnergy=4, maxEnergy=4,
        stats={evasion=7}, roleType="minion", isStaticThreshold=true, isPlayer=false}
end

function cases.npcs()
    S.NpcTemplateCache[100] = Baseline()
    S.NpcSpawnCache["4294967297"] = Baseline()
    S.NpcSpawnCache["4294967297"].source = "guid"
    S.NpcSpawnCache["4294967297"].curHealth = 8
    local a = Creature("Creature-A", "4294967297", 100, 1)
    local b = Creature("Creature-B", "4294967297", 100, 2)
    local pa, pb = assert(S.GetCreatureStats(a)), assert(S.GetCreatureStats(b))
    assert(pa.source == "guid" and pb.curHealth == 8 and pa ~= pb)
    pa.curHealth, pa.stats.evasion = 1, -3
    assert(pb.curHealth == 8 and pb.stats.evasion == 7 and S.NpcSpawnCache["4294967297"].curHealth == 8)
    local t1 = assert(S.GetCreatureStats(Creature("Temp-A", "0", 100)))
    local t2 = assert(S.GetCreatureStats(Creature("Temp-B", "0", 100)))
    assert(t1 ~= t2 and t1.source == "template")
    assert(S.GetCreatureStats(Creature("Other", "0", 101)) == nil)
    local bad, err = S.GetCreatureStats(Creature("Changed", "4294967297", 101))
    assert(not bad and err == "spawn_template_changed")
    assert(S.GetCreatureStats(a) == pa)
    S.ReleaseCreature(a)
    assert(S.RuntimeNpcs[pa.runtimeKey] == nil and S.GetCreatureStats(b) == pb)
end

function cases.reload()
    local function Load(sql)
        if sql:find("COUNT", 1, true) then return Query({{1}}) end
        if sql:find("FROM rps_creature_template_stats", 1, true) then
            return Query({{100,"minion",1,20,4,2,10,"2d6","1d4",'{"evasion":7}'}})
        end
        return Query({{"4294967297","named",100,"boss",0,30,10,2,10,"2d6+2","1d6",
            '{"evasion":3}',9,2,'{"burn":1}'}})
    end
    assert(S.LoadNpcCaches(Load))
    assert(S.NpcTemplateCache[100].stats.evasion == 7)
    assert(S.NpcSpawnCache["4294967297"].curHealth == 9)
    local creature = Creature("live", "4294967297", 100)
    local p = assert(S.GetCreatureStats(creature)); p.curHealth = 1
    assert(S.LoadNpcCaches(Load) and S.GetCreatureStats(creature).curHealth == 1)
    local old = S.NpcSpawnCache
    assert(not S.LoadNpcCaches(function() return nil end) and S.NpcSpawnCache == old)
    assert(S.LoadNpcCaches(function() return Query({{0}}) end))
    assert(next(S.NpcSpawnCache) == nil and next(S.NpcTemplateCache) == nil)
    assert(S.GetCreatureStats(creature) == p)
end

local function Profile()
    return {guid="1", curHealth=15, maxHealth=15, curEnergy=10, maxEnergy=10,
        energySpentRound=0, curWounds=0, maxWounds=3, armor=2, isPlayer=true,
        stats={accuracy=2, evasion=1, resistance=2}, weaponDice="1d8", blockDice="1d4"}
end

local function CombatRegistry()
    local rows = Rows()
    for i, key in ipairs({"evasion", "resistance"}) do
        rows[#rows+1] = {key=key, category="combat", sortOrder=20+i, name=key, icon="dice", spellId=0,
            diceFormula="3d6", defaultValue=0, description=""}
    end
    assert(C.ReplaceStatDefinitions(rows))
end

function cases.budget()
    CombatRegistry()
    local p = Profile()
    local draft = assert(M.SpendEnergy(p, 6))
    assert(draft.curEnergy == 4 and draft.energySpentRound == 6 and p.curEnergy == 10)
    local rejected, err = M.SpendEnergy(draft, 2)
    assert(not rejected and err == "round_budget_exhausted" and draft.curEnergy == 4)
    p.curEnergy = 2
    rejected, err = M.ExecuteStatRoll(p, "accuracy", true, function() error("RNG must not run") end)
    assert(not rejected and err == "insufficient_energy" and p.curEnergy == 2)
    p.curEnergy = 10
    local roll
    draft, roll = M.ExecuteStatRoll(p, "accuracy", true, Fixed({4,6,6,1}), 2)
    assert(draft.curEnergy == 10 and draft.energySpentRound == 3)
    assert(roll.total == 19 and roll.energyGained == 4 and roll.energyApplied == 3)
    assert(p.curEnergy == 10 and p.energySpentRound == 0)
    -- Bonus energy above the maximum is spendable and never trimmed by natural regain.
    p.curEnergy = 14
    draft = assert(M.SpendEnergy(p, 3))
    assert(draft.curEnergy == 11)
    draft, roll = M.ExecuteStatRoll(p, "accuracy", false, Fixed({6,6,6}), 0)
    assert(draft.curEnergy == 14 and roll.energyApplied == 0)
    p.curEnergy = 10
    p.curHealth, p.curWounds = 0, 1
    rejected, err = M.ExecuteStatRoll(p, "accuracy", false)
    assert(not rejected and err == "incapacitated")
end

function cases.damage()
    local p = Profile()
    local draft, result = M.ApplyDamageToUnit(p, 8, "physical", 3)
    assert(draft.curHealth == 12 and result.damage == 3 and p.curHealth == 15)
    draft, result = M.ApplyDamageToUnit(p, 8, "magic", 3)
    assert(draft.curHealth == 10 and result.damage == 5)
    -- Bonus health above the maximum is accepted and absorbs damage first.
    p.curHealth = 20
    draft, result = M.ApplyDamageToUnit(p, 4, "magic", 0)
    assert(draft.curHealth == 16 and not result.woundAdded)
    p.curHealth = 15
    p.curHealth = 1
    draft, result = M.ApplyDamageToUnit(p, 20, "physical", 0)
    assert(draft.curHealth == 0 and draft.curWounds == 1 and result.woundAdded)
    draft, result = M.ApplyDamageToUnit(draft, 20, "physical", 0)
    assert(draft.curWounds == 2 and result.woundAdded)
    draft, result = M.ApplyDamageToUnit(draft, 2, "physical", 0)
    assert(draft.curWounds == 2 and not result.woundAdded and result.damage == 0)
    p.curWounds = 2
    for _, test in ipairs({{{1,1,4},"death"}, {{1,1,5},"injury"}, {{4,4,4},"injury"},
        {{4,4,5},"defeated"}, {{5,6,6},"defeated"}, {{6,6,6},"second_wind"}}) do
        draft, result = M.ApplyDamageToUnit(p, 20, "physical", 0, Fixed(test[1]))
        assert(result.deathOutcome == test[2] and p.curWounds == 2)
        if test[2] == "second_wind" then
            assert(draft.curHealth == 15 and draft.curEnergy == 10 and draft.curWounds == 2)
        else assert(draft.curHealth == 0 and draft.curWounds == 3) end
    end
    assert(not M.ApplyDamageToUnit(p, -1, "physical", 0))
end

function cases.defense()
    CombatRegistry()
    local p = Profile()
    local attack = {attackTotal=11, weaponDice="1d8", damageType="physical"}
    local draft, result = M.HandleDefenseReaction(p, attack, "AVOID", "evasion", false, Fixed({3,3,4}))
    assert(result.avoided and draft.curHealth == 15 and p.curHealth == 15)
    -- D09 without a shield: 1 + Сопротивление 2 absorbs 3, then Броня 2 applies: 8 - 3 - 2 = 3.
    draft, result = M.HandleDefenseReaction(p, attack, "BLOCK", "resistance", false, Fixed({8}))
    assert(draft.curHealth == 12 and draft.curEnergy == 8 and draft.energySpentRound == 2)
    assert(result.damage.damage == 3 and result.block.base == 1 and p.energySpentRound == 0)
    attack.damageType = "magic"
    draft, result = M.HandleDefenseReaction(p, attack, "TAKE", "evasion", false, Fixed({8}))
    assert(draft.curHealth == 7)
    p.energySpentRound = 6
    local rejected, err = M.HandleDefenseReaction(p, attack, "BLOCK", "resistance", false)
    assert(not rejected and err == "round_budget_exhausted")
    assert(not M.HandleDefenseReaction(p, attack, "cheat", "evasion", false))
    assert(not M.HandleDefenseReaction(p, attack, "TAKE", "evasion", true))
    assert(M.GetNpcDefense({isStaticThreshold=true, stats={evasion=7}}, "evasion") == 7)
    assert(M.GetNpcDefense({isStaticThreshold=false, stats={evasion=2}}, "evasion", Fixed({1,2,3})) == 8)
    assert(not M.GetNpcDefense({isStaticThreshold=true, stats={}}, "evasion"))
end

function cases.runtime_restore()
    S.RuntimePersistence=true
    RpsRuntimeEpoch=function() return "epoch" end
    WorldDBQuery=function(sql)
        assert(sql:find("epoch:1:0:Temp",1,true))
        if sql:find("COUNT",1,true) then return Query({{1}}) end
        return Query({{"0","temporary",100,"minion",1,20,4,2,10,"2d6","1d4",'{"evasion":7}',3,1,'{"burn":2}',9}})
    end
    local creature=Creature("Temp","0",100)
    local p=assert(S.GetCreatureStats(creature))
    assert(p.curHealth==3 and p.curEnergy==1 and p.revision==9 and p.effectsJson=='{"burn":2}')
    S.RuntimeNpcs={}
    assert(S.GetCreatureStats(creature).curHealth==3)
    WorldDBQuery=function() return Query({{0}}) end
    S.RuntimeNpcs={}
    assert(not S.GetCreatureStats(creature))
end

return cases
