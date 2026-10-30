-- R04: native levels/XP (D01/D02). Server: real Init + 06 with a native GiveXP double that calls the MAP hooks.
-- Client: RPSClient + Progression module + DM «Бой 3d6» XP control.
local cases = {}

local function Query(rows)
    local i, q = 1, {}
    function q:GetString(col) return rows[i][col + 1] end
    q.GetUInt8, q.GetUInt32, q.GetUInt64, q.GetInt32 = q.GetString, q.GetString, q.GetString, q.GetString
    function q:NextRow() i = i + 1; return rows[i] ~= nil end
    return q
end

local XP_FOR = {[10] = 20, [11] = 25, [12] = 30, [13] = 40, [14] = 50, [15] = 60, [16] = 75, [17] = 90, [18] = 110}
local MAX_LEVEL = 19

local function Server()
    package.path = ROOT .. "/NobleNextLua/?.lua;" .. package.path
    local E = {transactions = {}, messages = {}, timers = {}, events = {}, mapEvents = {}, players = {},
        receipts = {}, dbPlayers = {}, logs = {}, clock = 1000}
    local ms = 0
    os.time = function() return E.clock end
    GetCurrTime = function() ms = ms + 500; return ms end
    RpsRuntimeEpoch = function() return "epoch" end
    RpsIsDiceSpell = function() return true end
    RpsXpGrantContext = function() return MAX_LEVEL, false, XP_FOR end
    GetStateMapId = function() return -1 end
    GetPlayersInWorld = function() local copy = {}; for i, p in ipairs(E.players) do copy[i] = p end; return copy end
    GetPlayerByGUID = function(guid) for _, p in ipairs(E.players) do if p:GetGUID() == guid then return p end end end
    RpsTargetContext = function() return true end
    RpsPollDiceCasts = function() return {} end
    RegisterPlayerEvent = function(id, fn) E.events[id] = fn end
    CreateLuaEvent = function(fn) E.timers[#E.timers + 1] = fn end
    RpsCommitAsync = function(pool, sql, cb) E.transactions[#E.transactions + 1] = {pool = pool, sql = sql, callback = cb} end
    RpsSaveXpAsync = function(player, sql, cb)
        E.transactions[#E.transactions + 1] = {pool = "characters", sql = sql, callback = cb,
            nativeXp = {id = player.id, level = player.level, xp = player.xp}}
    end
    local definitions = {}
    for i, key in ipairs({"accuracy", "healing", "evasion", "resistance", "skill"}) do
        definitions[i] = {key, i <= 4 and "combat" or "mastery", i, key, "dice", 0, "3d6", 0, ""}
    end
    WorldDBQuery = function(sql)
        if sql:find("FROM rps_stat_definitions", 1, true) then return Query(definitions) end
        if sql:find("COUNT", 1, true) then return Query({{0}}) end
    end
    CharDBQuery = function(sql)
        local issuer, request = sql:match("issuer_guid=(%d+) AND request_id='([^']*)'")
        if issuer and sql:find("rps_action_receipts", 1, true) then
            local row = E.receipts[issuer .. "|" .. request]
            if sql:find("COUNT", 1, true) then return Query({{row and 1 or 0}}) end
            return row and Query({{row.signature, row.state, row.payload}}) or nil
        end
        if sql:find("result_kind='xp_grant'",1,true) then
            local target = sql:match("attack_id='([^']*)'")
            local rows = {}
            for _, row in pairs(E.receipts) do
                if row.target == target and row.state == "pending" then
                    rows[#rows+1] = {row.issuer, row.request, row.signature, row.payload}
                end
            end
            if sql:find("COUNT",1,true) then return Query({{#rows}}) end
            return #rows>0 and Query(rows) or nil
        end
        if sql:find("COUNT(*) FROM rps_pending_attacks", 1, true) then return Query({{0}}) end
        if sql:find("COUNT", 1, true) then return Query({{0, 0}}) end
    end
    local handlers
    local N = {IsMainState = function() return true end, Log = function(_, text) E.logs[#E.logs + 1] = text end,
        HasStaffPermission = function(p) return p.admin end,
        AIO = {AddHandlers = function(_, h) assert(not handlers); handlers = h; return h end,
            Handle = function(player, prefix, method, payload)
                E.messages[#E.messages + 1] = {player = player, prefix = prefix, method = method, payload = payload}
            end}}
    package.loaded.NobleNext = N
    _G.NN_BOOTSTRAP_ACTIVE = true
    local R = require("Modules.RPS_Combat.Init")
    assert(R.ready, tostring(R.unavailableReason))
    local P = require("Modules.RPS_Combat.06_RPS_Progression")
    local register = RegisterPlayerEvent
    RegisterPlayerEvent = function(id, fn) E.mapEvents[id] = fn end
    P.InstallMap()
    RegisterPlayerEvent = register
    assert(E.mapEvents[12] and E.mapEvents[13] and not E.events[12] and not E.events[13])
    E.R, E.S, E.P, E.H, E.N = R, R.Storage, P, handlers, N
    assert(handlers.RequestProgression and handlers.DmGrantXp)

    -- Player::GiveXP: hook, cap, level loop with ON_LEVEL_CHANGE per level.
    function E.Player(id, admin, level)
        local p = {id = id, admin = admin, level = level or 10, xp = 0, alive = true, data = {}, chat = {}, saved = 0,
            notes = {}, levelEvents = 0}
        function p:GetGUIDLow() return self.id end
        function p:GetGUID() return string.format("Player-1-%08X", tonumber(self.id)) end
        function p:GetName() return "P" .. self.id end
        function p:GetSelection() return self.target end
        function p:ToPlayer() return self end
        function p:ToCreature() end
        function p:HasSpell() return true end
        function p:LearnSpell() end
        function p:GetPlayersInRange() return {} end
        function p:SendNotification(text) self.notes[#self.notes + 1] = text end
        function p:SendBroadcastMessage(text) self.chat[#self.chat + 1] = text end
        function p:GetLevel() return self.level end
        function p:GetXP() return self.xp end
        function p:GetXPForNextLevel() return XP_FOR[self.level] or 0 end
        function p:IsAlive() return self.alive end
        function p:SaveToDB() self.saved = self.saved + 1 end
        function p:Data()
            local owner = self
            return {Get = function(_, k) return owner.data[k] end, Set = function(_, k, v) owner.data[k] = v end}
        end
        function p:GiveXP(xp, victim)
            if xp < 1 or not self.alive then return end
            local changed = E.mapEvents[12](12, self, xp, victim)
            if type(changed) == "number" then xp = changed end
            if self.level >= MAX_LEVEL then return end
            local newXp = self.xp + xp
            while self.level < MAX_LEVEL and newXp >= (XP_FOR[self.level] or 0) do
                newXp = newXp - XP_FOR[self.level]
                self.level = self.level + 1
                self.levelEvents = self.levelEvents + 1
                E.mapEvents[13](13, self, self.level - 1)
            end
            self.xp = newXp
        end
        E.dbPlayers[id] = {level = p.level, xp = p.xp}
        E.players[#E.players + 1] = p
        return p
    end
    function E.Profile(player, level)
        local profile = assert(E.S.BuildDefaultPlayerProfile(player))
        profile.revision, profile.level = 1, level or 1
        E.S.PlayerProfiles[profile.guid] = profile
        return profile
    end
    -- Decode the deliberately narrow INSERT VALUES emitted by the real module;
    -- respect doubled SQL quotes and escaped backslashes in serialized payloads.
    local function Values(sql)
        local text = assert(sql:match("VALUES%s*%((.*)%)"))
        local values, i = {}, 1
        while i <= #text do
            local c = text:sub(i,i)
            if c:match("[%s,]") then i=i+1
            elseif c == "'" then
                local out = {}; i=i+1
                while i <= #text do
                    c=text:sub(i,i)
                    if c == "'" and text:sub(i+1,i+1) == "'" then out[#out+1]="'"; i=i+2
                    elseif c == "'" then i=i+1; break
                    elseif c == string.char(92) and text:sub(i+1,i+1)==c then out[#out+1]=c; i=i+2
                    else out[#out+1]=c; i=i+1 end
                end
                values[#values+1]=table.concat(out)
            else
                local value,pos=text:match("^(%-?%d+)()",i)
                assert(value,"unsupported fixture SQL")
                values[#values+1]=value; i=pos
            end
        end
        return values
    end
    function E.Flush(ok)
        local t = table.remove(E.transactions, 1); assert(t, "no transaction")
        if ok ~= false then
            for _, sql in ipairs(t.sql) do
                if sql:find("INSERT INTO rps_action_receipts",1,true) then
                    local v=Values(sql)
                    E.receipts[v[1].."|"..v[2]]={issuer=v[1],request=v[2],signature=v[3],state=v[4],target=v[9],payload=v[10]}
                elseif sql:find("UPDATE rps_action_receipts",1,true) then
                    local issuer,request=sql:match("issuer_guid=(%d+) AND request_id='([^']*)'")
                    local row=assert(E.receipts[issuer.."|"..request])
                    row.state="done"
                end
            end
            if t.nativeXp then
                E.dbPlayers[t.nativeXp.id]={level=t.nativeXp.level,xp=t.nativeXp.xp}
                for _, player in ipairs(E.players) do if player.id==t.nativeXp.id then player.saved=player.saved+1 end end
            end
        end
        t.callback(ok ~= false)
        return t
    end
    function E.FlushAll() while #E.transactions > 0 do E.Flush() end end
    function E.Last(method, player)
        for i = #E.messages, 1, -1 do
            local m = E.messages[i]
            if m.method == method and (not player or m.player == player) then return m.payload end
        end
    end
    function E.Count(method, player)
        local n = 0
        for _, m in ipairs(E.messages) do if m.method == method and (not player or m.player == player) then n = n + 1 end end
        return n
    end
    function E.Tick() for _, fn in ipairs(E.timers) do fn() end end
    return E
end

-- L03: non-DM sources (kill, gathering, spell effect, scripts) are reduced to 0; the guard admits only the exact grant.
function cases.xp_block()
    local E = Server()
    local P, b = E.P, E.Player("4294967298", false)
    b:GiveXP(30, nil)
    assert(b.level == 10 and b.xp == 0)
    b:GiveXP(30, {mob = true})
    assert(b.level == 10 and b.xp == 0)
    assert(P.FilterXp(b, 30, nil) == 0 and P.FilterXp(b, 0, nil) == nil)
    b.data[P.GRANT_KEY] = 25
    assert(P.FilterXp(b, 30, nil) == 0 and P.FilterXp(b, 25, {}) == 0 and P.FilterXp(b, 25, nil) == nil)
    b.data[P.GRANT_KEY] = nil
    -- A player-side request carries no amount and cannot grant XP.
    E.H.RequestProgression(b, 999, "fake")
    assert(b.level == 10 and b.xp == 0 and E.Last("Progression", b).xp == 0)
end

-- L02: DM grant passes the hook, is logged, idempotent by requestId and durable after reload.
function cases.dm_grant()
    local E = Server()
    local P, H = E.P, E.H
    local a, b = E.Player("4294967297", true), E.Player("4294967298", false)
    local pb = E.Profile(b)
    H.DmGrantXp(a, b:GetGUID(), 20, "Квест на ферме", "xp-1")
    assert(b.level == 10 and b.xp == 0 and b.saved == 0)
    assert(#E.transactions == 1 and E.Count("Progression", b) == 0)
    E.Flush()
    assert(b.level == 11 and b.xp == 0 and b.saved == 0)
    assert(b.data[P.GRANT_KEY] == nil and next(P.LocalGuard) == nil)
    assert(#E.transactions == 1 and E.transactions[1].nativeXp and E.transactions[1].sql[1]:find("state='done'",1,true))
    assert(E.Count("DmGrantXpResult", a) == 0)
    E.FlushAll()
    local result = E.Last("DmGrantXpResult", a)
    assert(result.ok and result.requestId == "xp-1" and result.newLevel == 11 and result.newXp == 0 and result.rpLevel == 2)
    assert(E.S.PlayerProfiles[pb.guid].level == 2 and E.S.PlayerProfiles[pb.guid].maxHealth == 16)
    local audit = table.concat(E.logs, "\n")
    assert(audit:find("xp_grant issuer=4294967297", 1, true) and audit:find("reason=Квест на ферме", 1, true))
    assert(b.chat[#b.chat]:find("+20", 1, true))
    -- Same intent: stored result, no second XP.
    H.DmGrantXp(a, b:GetGUID(), 20, "Квест на ферме", "xp-1")
    assert(b.level == 11 and b.xp == 0 and #E.transactions == 0)
    result = E.Last("DmGrantXpResult", a)
    assert(result.ok and result.duplicate and result.newLevel == 11)
    -- Different payload under the same id.
    H.DmGrantXp(a, b:GetGUID(), 25, "Квест на ферме", "xp-1")
    assert(E.Last("DmGrantXpResult", a).code == "request_conflict" and b.level == 11)
    -- After Lua reload the durable receipt answers instead of a new grant.
    assert(E.receipts[a.id .. "|xp-1"].state == "done")
    P.world.Grants = {}
    H.DmGrantXp(a, b:GetGUID(), 20, "Квест на ферме", "xp-1")
    result = E.Last("DmGrantXpResult", a)
    assert(result.ok and result.duplicate and result.newLevel == 11 and b.level == 11 and b.xp == 0)
    P.world.Grants = {}
    H.DmGrantXp(a, b:GetGUID(), 21, "Другая причина", "xp-1")
    assert(E.Last("DmGrantXpResult", a).code == "request_conflict" and b.xp == 0)
end

-- L02/L04: one grant crosses four levels; each level is applied once, wounds/surplus/budget are kept.
function cases.multi_level()
    local E = Server()
    local P, H, S = E.P, E.H, E.S
    local a, b = E.Player("4294967297", true), E.Player("4294967298", false)
    local pb = E.Profile(b)
    pb.curHealth, pb.curWounds, pb.curEnergy, pb.energySpentRound = 5, 2, 12, 3
    local calls, maxima = 0, P.Maxima
    P.Maxima = function(...) calls = calls + 1; return maxima(...) end
    H.DmGrantXp(a, b:GetGUID(), 120, "Победа в осаде", "xp-multi")
    assert(b.level == 10 and #E.transactions == 1)
    E.Flush()
    assert(b.level == 14 and b.xp == 5 and b.levelEvents == 4)
    assert(calls == 0 and #E.transactions == 1)
    E.FlushAll()
    assert(calls == 5, "one sheet per crossed level plus the start: " .. calls)
    local p = S.PlayerProfiles[pb.guid]
    assert(p.level == 5 and p.maxHealth == 21 and p.curHealth == 11, p.maxHealth .. "/" .. p.curHealth)
    assert(p.maxEnergy == 15 and p.curEnergy == 17 and p.curWounds == 2 and p.energySpentRound == 3)
    assert(p.stats.accuracy == 2 and p.stats.resistance == 0)
    local push = E.Last("Progression", b)
    assert(push.levelUp.from == 1 and push.levelUp.to == 5 and push.rpLevel == 5 and push.abilitySlots == 2)
    -- ON_LEVEL_CHANGE flags only cause a push; the already applied levels are not re-applied.
    local pushes = E.Count("Progression", b)
    E.Tick(); E.Tick()
    assert(#E.transactions == 0 and S.PlayerProfiles[pb.guid] == p and E.Count("Progression", b) == pushes + 1)
    assert(b.data[P.LEVEL_KEY] == nil)
    P.Maxima = maxima
end

-- Resolver path for a confirmed character; Одарённость opens slots at 2/4/6/8.
function cases.resolver_gifted()
    local E = Server()
    local P, H, S = E.P, E.H, E.S
    local V = require("Modules.RPS_Combat.04_RPS_Resolver")
    local a, b = E.Player("4294967297", true), E.Player("4294967298", false)
    local pb = E.Profile(b)
    local creation = {guid = pb.guid, state = "complete", archetype = "fighter", race = "blood_elf",
        racialFeature = "mana_tap", traits = {"gifted"}, traitChoice = "",
        mastery = {skill = 1, knowledge = 0, endurance = 1, craft = 0}}
    S.Creation[pb.guid] = creation
    local one = assert(P.SheetInput(creation, 1)) and assert(V.Resolve(P.SheetInput(creation, 1)))
    local two = assert(V.Resolve(P.SheetInput(creation, 2)))
    pb.maxHealth, pb.curHealth, pb.maxEnergy, pb.curEnergy = one.maxHealth, one.maxHealth, one.maxEnergy, one.maxEnergy
    H.DmGrantXp(a, b:GetGUID(), 20, "Сцена", "xp-res")
    E.FlushAll()
    local p = S.PlayerProfiles[pb.guid]
    assert(p.level == 2 and p.maxHealth == two.maxHealth and p.maxEnergy == two.maxEnergy)
    assert(table.concat(E.logs, "\n"):find("source=resolver", 1, true))
    H.RequestProgression(b)
    local data = E.Last("Progression", b)
    assert(data.gifted and data.abilitySlots == 1 and data.slots[1].unlockLevel == 2 and data.slots[1].open)
    assert(data.nextUnlock.rpLevel == 4 and data.nextUnlock.text:find("3 ОЭ", 1, true))
end

-- L06: cap at server 19 = RP 10; the grant over the cap is refused, no 11th level.
function cases.cap()
    local E = Server()
    local H = E.H
    local a, b = E.Player("4294967297", true), E.Player("4294967298", false)
    b.level, b.xp = 18, 100
    local pb = E.Profile(b, 9)
    H.DmGrantXp(a, b:GetGUID(), 501, "Слишком много", "xp-big")
    assert(E.Last("DmGrantXpResult", a).code == "invalid_amount" and b.level == 18)
    H.DmGrantXp(a, b:GetGUID(), 50, "Финал кампании", "xp-cap")
    E.FlushAll()
    assert(b.level == 19 and E.Last("DmGrantXpResult", a).ok)
    local data = E.Last("Progression", b)
    assert(data.rpLevel == 10 and data.atCap and data.xpNeeded == 0 and data.xpTotal == 500 and data.maxRpLevel == 10)
    assert(data.nextUnlock == nil and data.abilitySlots == 4)
    assert(E.S.PlayerProfiles[pb.guid].level == 10)
    H.DmGrantXp(a, b:GetGUID(), 10, "Ещё опыт", "xp-after")
    local result = E.Last("DmGrantXpResult", a)
    assert(result.code == "at_cap" and result.newLevel == 19 and b.level == 19 and #E.transactions == 0)
    assert(E.P.RpLevel(25) == 10 and E.P.RpLevel(10) == 1 and E.P.RpLevel(1) == 1)
end

-- L03: only staff, valid input, online and alive target.
function cases.permissions()
    local E = Server()
    local H, R = E.H, E.R
    local a, b = E.Player("4294967297", true), E.Player("4294967298", false)
    H.DmGrantXp(b, a:GetGUID(), 20, "Сам себе", "deny")
    assert(E.Last("DmGrantXpResult", b).code == "permission_denied" and a.level == 10)
    H.DmGrantXp(b, b:GetGUID(), 20, "Сам себе", "deny-self")
    assert(E.Last("DmGrantXpResult", b).code == "permission_denied" and b.level == 10)
    H.DmGrantXp(a, b:GetGUID(), 20, "  ", "no-reason")
    assert(E.Last("DmGrantXpResult", a).code == "invalid_reason")
    H.DmGrantXp(a, b:GetGUID(), 2.5, "Дробь", "fraction")
    assert(E.Last("DmGrantXpResult", a).code == "invalid_amount")
    H.DmGrantXp(a, b:GetGUID(), 20, "Плохой id", "bad id!")
    local bad = E.Last("DmGrantXpResult", a)
    assert(bad.code == "invalid_request_id" and bad.requestId == nil)
    H.DmGrantXp(a, "Player-1-0FFFFFFF", 20, "Нет в сети", "offline")
    assert(E.Last("DmGrantXpResult", a).code == "target_unavailable")
    b.alive = false
    H.DmGrantXp(a, b:GetGUID(), 20, "Мёртв", "dead")
    assert(E.Last("DmGrantXpResult", a).code == "target_dead" and b.level == 10)
    b.alive = true
    R.ready = false
    H.DmGrantXp(a, b:GetGUID(), 20, "Нет системы", "down")
    assert(E.Last("DmGrantXpResult", a).code == "system_unavailable" and b.level == 10)
    R.ready = true
    assert(#E.transactions == 0)
end

-- Progression payload for the player screen.
function cases.payload()
    local E = Server()
    local b = E.Player("4294967298", false)
    b.level, b.xp = 12, 10
    E.H.RequestProgression(b)
    local data = E.Last("Progression", b)
    assert(data.serverLevel == 12 and data.rpLevel == 3 and data.xp == 10 and data.xpNeeded == 30)
    assert(data.xpTotal == 55 and data.maxRpLevel == 10 and data.atCap == false and data.gifted == false)
    assert(data.abilitySlots == 1 and #data.slots == 4 and data.slots[1].cost == 2 and data.slots[1].open)
    assert(data.nextUnlock.rpLevel == 5 and data.nextUnlock.text:find("3 ОЭ", 1, true))
end

-- Level changes from other sources (GM .levelup, offline) apply once; a busy actor or failed save is retried later.
function cases.reconcile()
    local E = Server()
    local H, R, S = E.H, E.R, E.S
    local a, b = E.Player("4294967297", true), E.Player("4294967298", false)
    local pb = E.Profile(b)
    R.Locks["p:" .. pb.guid] = true
    H.DmGrantXp(a, b:GetGUID(), 20, "Во время броска", "xp-busy")
    assert(b.level == 10 and #E.transactions == 0 and E.Last("DmGrantXpResult", a).code == "actor_busy")
    b.level = 11
    E.FlushAll()
    E.Tick()
    assert(#E.transactions == 0 and S.PlayerProfiles[pb.guid].level == 1)
    R.Locks["p:" .. pb.guid] = nil
    E.Tick()
    assert(#E.transactions == 1)
    E.Flush(false)
    assert(S.PlayerProfiles[pb.guid].level == 1 and not R.Locks["p:" .. pb.guid])
    E.Tick()
    assert(#E.transactions == 0)
    E.clock = E.clock + 31
    b.level = 13
    E.Tick()
    E.Flush()
    local p = S.PlayerProfiles[pb.guid]
    assert(p.level == 4 and p.maxHealth == 20 and E.Last("Progression", b).levelUp.to == 4)
    E.Tick()
    assert(#E.transactions == 0)
end

local function LoseMemory(E)
    E.P.world.Grants, E.P.world.PendingTargets, E.P.world.Checked = {}, {}, {}
    E.R.Locks = {}
end

function cases.intent_failure()
    local E = Server()
    local a,b = E.Player("1",true),E.Player("2",false)
    E.Profile(b)
    E.H.DmGrantXp(a,b:GetGUID(),20,"Сцена","intent-fail")
    assert(b.level==10 and #b.chat==0 and #E.transactions==1)
    E.Flush(false)
    assert(b.level==10 and E.dbPlayers[b.id].level==10 and not next(E.receipts))
    assert(E.Last("DmGrantXpResult",a).code=="save_failed" and not next(E.R.Locks))
    LoseMemory(E)
    E.H.DmGrantXp(a,b:GetGUID(),20,"Сцена","intent-fail")
    E.FlushAll()
    assert(b.level==11 and b.levelEvents==1 and E.dbPlayers[b.id].level==11)
end

function cases.final_failure_reload()
    local E = Server()
    local a,b = E.Player("1",true),E.Player("2",false)
    E.Profile(b)
    E.H.DmGrantXp(a,b:GetGUID(),25,"Квест 'Лес'","lost")
    E.Flush()
    assert(b.level==11 and b.xp==5 and b.levelEvents==1 and E.Count("Progression",b)==0)
    E.Flush(false)
    assert(E.dbPlayers[b.id].level==10 and E.receipts["1|lost"].state=="pending")
    assert(not E.Last("DmGrantXpResult",a).ok and #b.chat==0)
    LoseMemory(E)
    E.H.DmGrantXp(a,b:GetGUID(),25,"Квест 'Лес'","lost")
    assert(b.levelEvents==1 and #E.transactions==1)
    E.FlushAll()
    assert(E.receipts["1|lost"].state=="done" and E.dbPlayers[b.id].xp==5 and b.saved==1)
    local first=E.Last("DmGrantXpResult",a)
    assert(first.ok and first.newXp==5 and first.rpLevel==2 and first.amount==25 and first.levelsGained==1)
    LoseMemory(E)
    b.level,b.xp=13,7
    E.H.DmGrantXp(a,b:GetGUID(),25,"Квест 'Лес'","lost")
    local again=E.Last("DmGrantXpResult",a)
    for _,key in ipairs({"newLevel","newXp","rpLevel","amount","levelsGained","targetGuid"}) do assert(again[key]==first[key],key) end
    assert(again.duplicate and b.level==13 and b.xp==7 and #b.chat==1 and #E.transactions==0)
end

function cases.crash_recovery()
    local E = Server()
    local a,b = E.Player("1",true),E.Player("2",false)
    E.Profile(b)
    E.H.DmGrantXp(a,b:GetGUID(),120,"Осада","crash")
    E.Flush()
    assert(b.level==14 and E.receipts["1|crash"].state=="pending")
    -- Discard the uncommitted native state and callback, as on a process crash.
    E.transactions={}
    b.level,b.xp,b.levelEvents=E.dbPlayers[b.id].level,E.dbPlayers[b.id].xp,0
    LoseMemory(E)
    E.P.world.Recover(b)
    assert(b.level==14 and b.xp==5 and b.levelEvents==4 and #E.transactions==1)
    E.FlushAll()
    assert(E.receipts["1|crash"].state=="done" and E.dbPlayers[b.id].level==14)
    E.P.world.Recover(b)
    assert(b.levelEvents==4 and #E.transactions==0)
end

function cases.pending_logout_and_serialization()
    local E = Server()
    local a,b = E.Player("1",true),E.Player("2",false)
    E.Profile(b)
    E.H.DmGrantXp(a,b:GetGUID(),20,"Сцена","offline")
    E.H.DmGrantXp(a,b:GetGUID(),20,"Сцена","offline")
    assert(E.Last("DmGrantXpResult",a).code=="request_pending" and #E.transactions==1)
    E.H.DmGrantXp(a,b:GetGUID(),20,"Другая сцена","another")
    assert(E.Last("DmGrantXpResult",a).code=="pending_recovery" and b.level==10)
    table.remove(E.players,2)
    E.Flush()
    assert(b.level==10 and E.receipts["1|offline"].state=="pending" and #E.transactions==0)
    E.players[#E.players+1]=b
    E.clock=E.clock+31
    E.P.world.Recover(b)
    table.remove(E.players,1)
    E.FlushAll()
    assert(b.level==11 and E.receipts["1|offline"].state=="done" and b.saved==1)
end

function cases.conflicting_native_state()
    local E = Server()
    local a,b = E.Player("1",true),E.Player("2",false)
    E.Profile(b)
    E.H.DmGrantXp(a,b:GetGUID(),20,"Сцена","conflict")
    b.xp=7
    E.Flush()
    assert(b.level==10 and b.xp==7 and #E.transactions==0)
    assert(E.Last("DmGrantXpResult",a).code=="pending_recovery" and E.receipts["1|conflict"].state=="pending")
    b.xp=0
    E.H.DmGrantXp(a,b:GetGUID(),20,"Сцена","conflict")
    E.FlushAll()
    assert(b.level==11 and b.levelEvents==1 and E.Last("DmGrantXpResult",a).ok)
end

function cases.binding_and_query_failure()
    local E = Server()
    local a,b = E.Player("1",true),E.Player("2",false)
    local save=RpsSaveXpAsync
    RpsSaveXpAsync=nil
    E.H.DmGrantXp(a,b:GetGUID(),20,"Сцена","no-binding")
    assert(E.Last("DmGrantXpResult",a).code=="xp_commit_unavailable" and b.level==10 and #E.transactions==0)
    RpsSaveXpAsync=save
    local query=CharDBQuery
    CharDBQuery=function(sql) if sql:find("result_kind='xp_grant'",1,true) then return nil end; return query(sql) end
    E.H.DmGrantXp(a,b:GetGUID(),20,"Сцена","no-query")
    assert(E.Last("DmGrantXpResult",a).code=="pending_recovery" and #E.transactions==0 and b.level==10)
end

function cases.export_xp_sql(directory)
    local E = Server()
    local a,b = E.Player("1",true),E.Player("2",false)
    E.H.DmGrantXp(a,b:GetGUID(),25,"scene","sql-atomic")
    local file=assert(io.open(directory.."/intent.sql","w"))
    file:write(E.transactions[1].sql[1]); file:close()
    E.Flush()
    local transaction=E.transactions[1]
    file=assert(io.open(directory.."/receipt.sql","w"))
    file:write(transaction.sql[1]); file:close()
    file=assert(io.open(directory.."/native.txt","w"))
    file:write(transaction.nativeXp.level," ",transaction.nativeXp.xp," ",transaction.nativeXp.id); file:close()
end

function cases.uncertain_intent_commit()
    local E = Server()
    local a,b = E.Player("1",true),E.Player("2",false)
    E.H.DmGrantXp(a,b:GetGUID(),20,"Сцена","uncertain")
    -- The DB committed, but the callback reports an unknown/failing outcome.
    local callback=E.transactions[1].callback
    E.transactions[1].callback=function() callback(false) end
    E.Flush()
    assert(E.receipts["1|uncertain"].state=="pending" and b.level==11 and #E.transactions==1)
    E.FlushAll()
    assert(E.Last("DmGrantXpResult",a).ok and b.levelEvents==1 and E.dbPlayers[b.id].level==11)
end

function cases.native_configuration_and_legacy_receipt()
    local E = Server()
    local a,b = E.Player("1",true),E.Player("2",false)
    RpsXpGrantContext=function() return 90,false,XP_FOR end
    E.H.DmGrantXp(a,b:GetGUID(),20,"Сцена","cap-config")
    assert(E.Last("DmGrantXpResult",a).code=="xp_level_cap_mismatch" and b.level==10 and #E.transactions==0)
    local wrong={}; for k,v in pairs(XP_FOR) do wrong[k]=v end; wrong[15]=999
    RpsXpGrantContext=function() return 19,false,wrong end
    E.H.DmGrantXp(a,b:GetGUID(),20,"Сцена","curve-config")
    assert(E.Last("DmGrantXpResult",a).code=="xp_curve_mismatch" and #E.transactions==0)
    RpsXpGrantContext=function() return 19,true,XP_FOR end
    E.H.DmGrantXp(a,b:GetGUID(),20,"Сцена","bonus-config")
    assert(E.Last("DmGrantXpResult",a).code=="xp_gain_blocked" and #E.transactions==0)
    RpsXpGrantContext=function() return 19,false,XP_FOR end
    E.receipts["1|old"]={signature="xp:"..b:GetGUID()..":20:Сцена",state="done",target=b.id}
    E.H.DmGrantXp(a,b:GetGUID(),20,"Сцена","old")
    assert(E.Last("DmGrantXpResult",a).code=="receipt_incomplete" and b.level==10 and #E.transactions==0)
end

local function Client()
    local C = {frames = {}, calls = {}, subscribers = {}, modules = {}, clock = 10}
    GetTime = function() return C.clock end
    GetServerTime = function() return 1000 end
    C_Timer = {After = function(_, fn) fn() end}
    NobleNextCharDB = nil
    local function Frame(kind, name, parent)
        local f = {kind = kind, name = name, parent = parent, scripts = {}, shown = true, enabled = true, text = ""}
        C.frames[#C.frames + 1] = f
        if name then _G[name] = f end
        function f:SetScript(event, fn) self.scripts[event] = fn end
        function f:HookScript(event, fn)
            local old = self.scripts[event]
            self.scripts[event] = function(...) if old then old(...) end; fn(...) end
        end
        function f:Show() self.shown = true end
        function f:Hide() self.shown = false end
        function f:IsShown() return self.shown end
        function f:SetEnabled(value) self.enabled = value end
        function f:SetText(value) self.text = value end
        function f:GetText() return self.text end
        function f:SetMinMaxValues(_, high) self.maximum = high end
        function f:SetValue(value) self.value = value end
        function f:CreateFontString() return Frame("FontString", nil, self) end
        function f:CreateTexture() return Frame("Texture", nil, self) end
        function f:SetScrollChild(child) self.content = child end
        function f:SetSize(w, h) self.width, self.height = w, h end
        setmetatable(f, {__index = function() return function() end end})
        return f
    end
    CreateFrame = Frame
    UIParent = Frame("Frame", "UIParent")
    local ns = {}
    function ns.Subscribe(event, key, fn) C.subscribers[event] = C.subscribers[event] or {}; C.subscribers[event][key] = fn end
    function ns.Emit(event, ...) for _, fn in pairs(C.subscribers[event] or {}) do fn(...) end end
    function ns.PrintError(text) ns.error = text end
    function ns.Print(text) ns.print = text end
    function ns.CreateNGButton(parent, text, w, h) local f = Frame("Button", nil, parent); f.text = text; f:SetSize(w, h); return f end
    function ns.CreateNGLabel(parent, text) local f = Frame("FontString", nil, parent); f.text = text; return f end
    function ns.CreateNGEditBox(parent, name, w, h) local f = Frame("EditBox", name, parent); f:SetSize(w, h); return f end
    function ns.RegisterModule(name, builder) C.modules[name] = builder end
    SlashCmdList = {}
    C.wizard = 0
    SlashCmdList.NOBLENEXTRPS = function() C.wizard = C.wizard + 1 end
    AIO = {AddHandlers = function(name, h) assert(name == "RPS_Combat"); C.H = h; return h end,
        Handle = function(...) C.calls[#C.calls + 1] = {...} end}
    assert(loadfile(ROOT .. "/Addons/NobleNext/Core/RPSClient.lua"))("NobleNext", ns)
    assert(loadfile(ROOT .. "/Addons/NobleNext/Modules/Progression/State.lua"))("NobleNext", ns)
    assert(loadfile(ROOT .. "/Addons/NobleNext/Modules/Progression/Frame.lua"))("NobleNext", ns)
    C.ns, C.R, C.P, C.Frame = ns, ns.RPSClient, ns.Progression, Frame
    function C.Last(method)
        for i = #C.calls, 1, -1 do if C.calls[i][2] == method then return C.calls[i] end end
    end
    return C
end

local function Payload(rp, extra)
    local data = {serverLevel = rp + 9, rpLevel = rp, xp = 5, xpNeeded = 25, xpTotal = 25, maxRpLevel = 10,
        abilitySlots = 0, gifted = false, atCap = false, slots = {
            {slot = 1, cost = 2, unlockLevel = 3, open = rp >= 3}, {slot = 2, cost = 3, unlockLevel = 5, open = rp >= 5},
            {slot = 3, cost = 4, unlockLevel = 7, open = rp >= 7}, {slot = 4, cost = 6, unlockLevel = 9, open = rp >= 9}},
        nextUnlock = {rpLevel = 3, text = "Слот персональной способности 1 (2 ОЭ)"}}
    for k, v in pairs(extra or {}) do data[k] = v end
    return data
end

function cases.client_screen()
    local C = Client()
    local H, P, ns = C.H, C.P, C.ns
    assert(H.Progression and H.DmGrantXpResult, "handlers attached to the single RPS_Combat table")
    H.Progression(nil, Payload(2))
    assert(P.data.rpLevel == 2 and NobleNextCharDB.rpsProgressionSeenLevel == 2 and P.lastLevelUp == nil)
    local text = table.concat(P.Lines(), "\n")
    assert(text:find("RP-уровень: 2 из 10", 1, true) and text:find("Опыт: 5 / 25", 1, true))
    assert(text:find("Следующее открытие: RP-уровень 3", 1, true) and text:find("ведущий", 1, true))
    H.Progression(nil, Payload(3, {levelUp = {from = 2, to = 3}}))
    assert(P.lastLevelUp.to == 3 and ns.print:find("Новый RP-уровень: 3", 1, true))
    -- A level gained while away is announced once after relog.
    ns.print = nil; P.lastLevelUp = nil
    NobleNextCharDB.rpsProgressionSeenLevel = 3
    H.Progression(nil, Payload(5))
    assert(P.lastLevelUp.from == 3 and P.lastLevelUp.to == 5)
    ns.print = nil
    H.Progression(nil, Payload(5))
    assert(ns.print == nil)
    H.Progression(nil, Payload(10, {atCap = true, xpNeeded = 0, xpTotal = 500, nextUnlock = false}))
    text = table.concat(P.Lines(), "\n")
    assert(text:find("Максимальный уровень", 1, true) and not text:find("11", 1, true))
    -- /rps dev opens the screen; other /rps subcommands still reach the wizard.
    SlashCmdList.NOBLENEXTRPS("dev")
    assert(NobleNextProgressionFrame and NobleNextProgressionFrame.shown and C.Last("RequestProgression"))
    SlashCmdList.NOBLENEXTRPS("create")
    assert(C.wizard == 1)
    for _, f in ipairs(C.frames) do
        assert(not tostring(f.text):find("Повысить", 1, true), "no manual level-up control")
    end
    H.Progression(nil, {rpLevel = "x"})
    assert(P.data.rpLevel == 10)
end

function cases.client_dm()
    local C = Client()
    local H, R, ns = C.H, C.R, C.ns
    assert(loadfile(ROOT .. "/Addons/NobleNextDM/GM/Battle/RPS.lua"))("NobleNextDM", ns)
    local panel = assert(C.modules["Бой 3d6"])(C.Frame("Frame"))
    local grant, amount, reason
    for _, f in ipairs(C.frames) do
        if f.text == "Выдать XP" then grant = f end
        if f.kind == "EditBox" and f.width == 50 then amount = f end
        if f.kind == "EditBox" and f.width == 210 then reason = f end
    end
    assert(grant and amount and reason and panel)
    H.SyncTarget(nil, {targetGuid = "Creature-1", name = "NPC", canEdit = true, inSystem = true, isPlayer = false,
        curHealth = 1, maxHealth = 1, curEnergy = 0, maxEnergy = 0, armor = 0, speed = 10, stats = {}})
    assert(not grant.enabled)
    H.SyncTarget(nil, {targetGuid = "Player-1-0000000B", name = "Игрок", canEdit = false, inSystem = true, isPlayer = true,
        curHealth = 10, maxHealth = 15, curEnergy = 0, maxEnergy = 10, armor = 0, speed = 10, stats = {}, revision = 2})
    assert(grant.enabled)
    amount:SetText("15"); reason:SetText("")
    local before = #C.calls
    grant.scripts.OnClick(grant)
    assert(#C.calls == before and ns.error:find("причину", 1, true))
    reason:SetText("Квест")
    grant.scripts.OnClick(grant)
    local call = C.Last("DmGrantXp")
    assert(call[3] == "Player-1-0000000B" and call[4] == 15 and call[5] == "Квест" and type(call[6]) == "string")
    assert(not grant.enabled)
    -- Timeout resends the same immutable request.
    local watch
    for _, f in ipairs(C.frames) do if f.scripts.OnUpdate and f ~= panel then watch = f end end
    C.clock = C.clock + 11; watch.scripts.OnUpdate(watch)
    local again = C.Last("DmGrantXp")
    assert(again ~= call and again[6] == call[6] and again[4] == 15)
    H.DmGrantXpResult(nil, {ok=false,code="pending_recovery",requestId=call[6]})
    assert(not grant.enabled and NobleNextCharDB.rpsPendingXpGrant.id==call[6])
    C.clock=C.clock+11; watch.scripts.OnUpdate(watch)
    C.clock=C.clock+11; watch.scripts.OnUpdate(watch)
    assert(grant.enabled and grant.text=="Проверить выдачу")
    amount:SetText("99"); reason:SetText("Другой запрос")
    grant.scripts.OnClick(grant)
    again=C.Last("DmGrantXp")
    assert(again[6]==call[6] and again[4]==15 and again[5]=="Квест" and not grant.enabled)
    H.DmGrantXpResult(nil, {ok = false, code = "permission_denied", requestId = "other"})
    assert(not grant.enabled)
    H.DmGrantXpResult(nil, {ok = true, requestId = call[6], newLevel = 11, newXp = 0, rpLevel = 2})
    assert(grant.enabled and reason.text == "")
    assert(NobleNextCharDB.rpsPendingXpGrant==nil and grant.text=="Выдать XP")
    amount:SetText("600"); reason:SetText("Много")
    before = #C.calls
    grant.scripts.OnClick(grant)
    assert(#C.calls == before)
    amount:SetText("5"); grant.scripts.OnClick(grant)
    local denied = C.Last("DmGrantXp")
    H.DmGrantXpResult(nil, {ok = false, code = "permission_denied", requestId = denied[6]})
    assert(grant.enabled)
end

function cases.client_pending_reload()
    local C = Client()
    local target="Player-1-0000000B"
    NobleNextCharDB={rpsPendingXpGrant={id="saved-request",args={target,15,"Квест","saved-request"},name="Игрок"}}
    assert(loadfile(ROOT.."/Addons/NobleNextDM/GM/Battle/RPS.lua"))("NobleNextDM",C.ns)
    local panel=assert(C.modules["Бой 3d6"])(C.Frame("Frame"))
    local watch
    for _,f in ipairs(C.frames) do if f.scripts.OnUpdate and f~=panel then watch=f end end
    C.clock=C.clock+11; watch.scripts.OnUpdate(watch)
    local call=C.Last("DmGrantXp")
    assert(call[3]==target and call[4]==15 and call[5]=="Квест" and call[6]=="saved-request")
    C.H.DmGrantXpResult(nil,{ok=true,requestId="saved-request",newLevel=11,newXp=0,rpLevel=2})
    assert(NobleNextCharDB.rpsPendingXpGrant==nil)
end

return cases
