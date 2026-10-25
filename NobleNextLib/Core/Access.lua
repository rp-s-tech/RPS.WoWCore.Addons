-- Server-confirmed UI role. Neither ordinary chat nor saved variables grant it.
local ns = LibStub("NobleNextLib-1.0").Runtime
if ns.Access then return end
local Access = {}; ns.Access = Access
local PREFIX, LEGACY, TTL, INTERVAL, TIMEOUT = "NN_ACCESS", "TrinityCore", 45, 20, 8
local level, source, expires, pending, fallback, requested = nil, nil, 0, nil, nil, -INTERVAL
local sequence, epoch, reason, online = 0, 0, "not_requested", true
local character, confirmedGeneration, transfer
local loginGeneration = 0
local alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local echoSpace, echoCount = 62^4, 0
local echoSequence = math.random(0, 62^4-1)
local function now() return GetTime and GetTime() or 0 end
local function emit(event, ...) if ns.Emit then ns.Emit(event, ...) end end
local function playerIdentity()
    if not UnitGUID then return nil end
    local ok, guid = pcall(UnitGUID, "player")
    if not ok or (issecretvalue and issecretvalue(guid)) or type(guid) ~= "string" or guid == "" then return nil end
    return guid
end
local function status(value)
    if reason ~= value then reason=value; emit("ACCESS_STATUS_CHANGED") end
end
local function revoke(value)
    local previous=level
    level, source, expires, confirmedGeneration = nil, nil, 0, nil
    status(value)
    if previous ~= nil then emit("ACCESS_CHANGED", nil, previous) end
end
local function invalidateRequests()
    epoch=epoch+1
    pending, fallback, requested = nil, nil, -INTERVAL
end
function Access.Reset(value)
    invalidateRequests()
    loginGeneration=loginGeneration+1
    character, transfer = nil, nil
    revoke(value or "not_requested")
end
function Access.GetLevel()
    -- Expiry must not discard an in-flight refresh of the same session.
    if level ~= nil and now() >= expires then revoke("expired") end
    if level ~= nil and online and not transfer then
        local identity=playerIdentity()
        if not identity or identity~=character or confirmedGeneration~=loginGeneration then
            Access.Reset(identity and "identity_changed" or "identity_unavailable")
        end
    end
    -- A retained lease is diagnostic state only while the world is unloading.
    return online and not transfer and level or nil
end
function Access.GetStatus()
    local visible=Access.GetLevel()
    return {level=visible,source=visible~=nil and source or nil,cachedLevel=transfer and level or nil,
        expiresIn=math.max(0,expires-now()),reason=reason,
        state=transfer and "transferring" or visible~=nil and "confirmed" or (pending or fallback) and "checking" or "unknown",
        checking=pending~=nil or fallback~=nil, transport=pending and PREFIX or fallback and LEGACY or nil}
end
function Access.Allows(required)
    required=tonumber(required)
    if not required or required<0 or required~=math.floor(required) then return false end
    if required==0 then return true end
    local actual=Access.GetLevel()
    return actual~=nil and actual>=required
end
local function ownSender(sender)
    if type(sender)~="string" or sender=="" then return false end
    local name, realm
    if UnitFullName then name,realm=UnitFullName("player") end
    name=name or (UnitName and UnitName("player"))
    if not name then return false end
    local function normalize(s) return (s:gsub("%s+", ""):lower()) end
    sender,name=normalize(sender),normalize(name)
    return sender==name or (realm and realm~="" and sender==name.."-"..normalize(realm))
end
local function parseLevel(raw)
    if type(raw)~="string" or not raw:match("^%d+$") or #raw>3
        or (#raw>1 and raw:sub(1,1)=="0") then return nil end
    local value=tonumber(raw)
    if value and value<=255 then return value end
end
local function send(prefix, message)
    local name=UnitName and UnitName("player")
    if not name or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
    local ok,result=pcall(C_ChatInfo.SendAddonMessage,prefix,message,"WHISPER",name)
    if not ok or result==false then return false end
    local codes=Enum and Enum.SendAddonMessageResult
    return not (codes and type(result)=="number" and result~=codes.Success)
end
local function confirm(value, via)
    local previous=level
    level,source,expires,pending,fallback=value,via,now()+TTL,nil,nil
    confirmedGeneration=loginGeneration
    status("confirmed")
    if previous~=value then emit("ACCESS_CHANGED",value,previous) end
    emit("ACCESS_CONFIRMED",value,via,previous)
end
local function legacyRequest()
    -- Four echo bytes are imposed by the existing server protocol. Never reuse
    -- one in this Lua session; Reset invalidates all pending response state.
    if echoCount>=echoSpace then status("correlation_exhausted"); return false end
    echoCount=echoCount+1; echoSequence=(echoSequence+1)%echoSpace
    local n,parts=echoSequence,{}
    for i=4,1,-1 do local digit=n%62; parts[i]=alphabet:sub(digit+1,digit+1); n=math.floor(n/62) end
    fallback={echo=table.concat(parts),epoch=epoch,deadline=now()+TIMEOUT,ack=false,
        character=character,generation=loginGeneration}
    status("waiting_account")
    -- Discovery intentionally bypasses the privileged command queue.
    if not send(LEGACY,"i"..fallback.echo.."account") then
        fallback=nil; status("send_failed"); return false
    end
    return true
end
local function expireRequests()
    if pending and now()>=pending.deadline then
        pending=nil
        if online then legacyRequest() end
    end
    if fallback and now()>=fallback.deadline then fallback=nil; status("account_timeout") end
end
function Access.Request()
    Access.GetLevel()
    if not online or transfer then return false end
    local identity=playerIdentity()
    if not identity then Access.Reset("identity_unavailable"); return false end
    if character and identity~=character then Access.Reset("identity_changed") end
    character=identity
    expireRequests()
    local time=now()
    if not online or pending or fallback or time-requested<INTERVAL then return false end
    sequence=sequence+1
    local nonce=string.format("nn_%d_%d_%d",math.floor(time*1000),sequence,math.random(100000,999999))
    pending={nonce=nonce,epoch=epoch,deadline=time+TIMEOUT,character=character,generation=loginGeneration}; requested=time
    status("waiting_caps")
    if not send(PREFIX,"HELLO|"..nonce) then pending=nil; status("send_failed"); return false end
    return true
end
local function ownsRequest(request)
    if not online or transfer or request.generation~=loginGeneration then return false end
    local identity=playerIdentity()
    if not identity or identity~=request.character then
        Access.Reset(identity and "identity_changed" or "identity_unavailable")
        return false
    end
    return true
end
function Access.Receive(prefix,message,channel,sender)
    if prefix~=PREFIX or channel~="WHISPER" or not ownSender(sender) or type(message)~="string" then return false end
    if pending and pending.epoch==epoch and now()<pending.deadline and ownsRequest(pending)
        and message==("HELLO|"..pending.nonce) then
        -- Unhandled self-whisper was echoed back by WorldSession::HandleChatAddonMessage.
        -- Immediately fall back to TrinityCore account check without waiting 8s.
        pending=nil
        if online then legacyRequest() end
        return false
    end
    local nonce,version,raw=message:match("^CAPS|([%w_-]+)|(%d+)|(%d+)$")
    if not pending or pending.epoch~=epoch or nonce~=pending.nonce or now()>=pending.deadline or not ownsRequest(pending) then return false end
    local value=parseLevel(raw)
    if version~="1" or value==nil then return false end
    confirm(value,PREFIX); return true
end
function Access.ReceiveAccount(prefix,message,channel,sender)
    if prefix~=LEGACY or channel~="WHISPER" or not ownSender(sender) or type(message)~="string" then return false end
    local request=fallback
    if not request or request.epoch~=epoch or now()>=request.deadline or #message<5
        or message:sub(2,5)~=request.echo or not ownsRequest(request) then return false end
    local opcode,body=message:sub(1,1),message:sub(6)
    if opcode=="a" and body=="" and not request.ack then request.ack=true; return true end
    if opcode=="m" and request.ack then
        -- Exact LANG_ACCOUNT_LEVEL=11 on the supported server. Password policy,
        -- arbitrary numbers, localized guesses and email are not role evidence.
        local raw=body:match("^Your account level is: (.*)$")
        if raw~=nil then
            local value=parseLevel(raw)
            if request.level~=nil or value==nil then request.invalid=true else request.level=value end
        end
        -- Other account output is neither retained nor printed.
        return true
    end
    if (opcode=="o" or opcode=="f") and body=="" then
        fallback=nil
        if opcode=="o" and request.ack and not request.invalid and request.level~=nil then
            confirm(request.level,LEGACY); return true
        end
        status(opcode=="f" and "account_failed" or "account_unrecognized")
        return false
    end
    request.invalid=true
    return false
end
function Access.Tick()
    Access.GetLevel()
    if online then Access.Request() end
end
ns.RegisterAddonPrefix(PREFIX,Access.Receive,{key="NobleNextAccess"})
ns.RegisterAddonPrefix(LEGACY,Access.ReceiveAccount,{key="NobleNextAccountAccess"})
local frame=CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN"); frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEAVING_WORLD"); frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent",function(_,event,isInitialLogin,isReloadingUi)
    if event=="PLAYER_LEAVING_WORLD" then
        local previous=Access.GetLevel()
        local identity=playerIdentity()
        invalidateRequests()
        if identity and identity==character then
            transfer={character=identity,generation=loginGeneration}
            online=false
            status("world_transfer")
            if previous~=nil then emit("ACCESS_CHANGED",nil,previous) end
        else
            online=false
            Access.Reset(identity and "identity_changed" or "identity_unavailable")
        end
        return
    end
    if event=="PLAYER_ENTERING_WORLD" then
        local identity=playerIdentity()
        local resume=isInitialLogin==false and isReloadingUi==false and transfer
            and transfer.generation==loginGeneration and identity and transfer.character==identity
        if resume then
            invalidateRequests()
            transfer=nil; online=true
            if level~=nil and now()<expires and confirmedGeneration==loginGeneration then
                status("confirmed")
                emit("ACCESS_CHANGED",level,nil)
            else
                revoke("expired")
            end
        else
            online=true
            Access.Reset(identity and "not_requested" or "identity_unavailable")
        end
        Access.Request()
        return
    end
    online=event=="PLAYER_LOGIN"
    Access.Reset(online and "not_requested" or "offline")
    if online then Access.Request() end
end)
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1,Access.Tick) end
