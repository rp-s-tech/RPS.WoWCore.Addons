-- Shared extension ownership, guarded adapters and dependency-aware loading.
-- The library stays passive until the NobleNext shell calls AttachShell().
local ns = LibStub("NobleNextLib-1.0").Runtime
if ns.Extensions then return end
local Extensions = {}; ns.Extensions = Extensions
local packages = {
    { name="NobleNextDM", minimum=1, dependencies={"NobleNext"} },
    { name="NobleNextGM", minimum=2, dependencies={"NobleNext","NobleNextDM"} },
}
local known, namespaces, loaded, failures = {}, {}, {}, {}
for _, package in ipairs(packages) do known[package.name] = package end
local loading, attached = false, false

function Extensions.GetPackages()
    local result = {}
    for _, package in ipairs(packages) do
        local dependencies = {}
        for i, dependency in ipairs(package.dependencies) do dependencies[i] = dependency end
        result[#result+1] = {name=package.name, minimum=package.minimum, dependencies=dependencies}
    end
    return result
end

function Extensions.GetStatus()
    local result = {}
    for _, package in ipairs(packages) do
        local allowed = ns.Access.Allows(package.minimum)
        local state = loaded[package.name] and (allowed and "loaded" or "inactive")
            or ns.Access.GetLevel()==nil and "access_unknown"
            or not allowed and "access_denied" or failures[package.name] and "load_failed" or "not_loaded"
        result[#result+1] = {name=package.name,minimum=package.minimum,loaded=loaded[package.name]==true,
            allowed=allowed,state=state,reason=failures[package.name]}
    end
    return result
end

local function denied(minimum)
    if ns.Access.Allows(minimum) then return false end
    if ns.PrintError then
        ns.PrintError("Доступ не подтверждён сервером: требуется GM-уровень " .. minimum .. ".")
    end
    return true
end

function ns.InitializeExtension(private, addonName, minimum)
    local package = known[addonName]
    assert(type(private)=="table" and package and package.minimum==minimum, "Invalid NobleNext extension")
    if namespaces[addonName] then
        assert(namespaces[addonName]==private, "NobleNext extension already has a namespace: " .. addonName)
        return private
    end
    assert(not rawget(private,"_extensionReady"), "NobleNext namespace is already owned")
    assert(ns.CommandDefinitions and ns.CommandDefinitions.ForOwner, "Shared command registry is missing")
    local commandDefinitions = ns.CommandDefinitions.ForOwner(addonName, minimum)
    namespaces[addonName] = private
    rawset(private,"_extensionReady",true)
    rawset(private,"AddonIdentity",addonName)
    setmetatable(private,{__index=ns,__newindex=ns})
    -- Stable wrappers preserve idempotence of shared slash/prefix registries.
    local guarded = setmetatable({}, {__mode="k"})
    local function guard(fn)
        assert(type(fn)=="function", "Extension handler must be a function")
        if not guarded[fn] then
            guarded[fn] = function(...)
                if denied(minimum) then return false end
                return fn(...)
            end
        end
        return guarded[fn]
    end
    rawset(private,"Guard",guard)
    rawset(private,"CommandDefinitions",commandDefinitions)
    rawset(private,"RegisterModule",function(spec, init, tooltip)
        return ns.RegisterModule(spec,init,tooltip,minimum,addonName)
    end)
    rawset(private,"RegisterQuickAction",function(spec)
        return ns.RegisterQuickAction(spec,minimum,addonName)
    end)
    rawset(private,"RegisterSlashCommand",function(key,handler,aliases)
        return ns.RegisterSlashCommand(key,guard(handler),aliases)
    end)
    for _,key in ipairs({"SendGmWhisper","RunGmCommand","AIOHandle","ShowModule"}) do
        rawset(private,key,guard(function(...) return ns[key](...) end))
    end
    rawset(private,"EnqueueCommand",guard(function(command,opts)
        local copy={}
        for key,value in pairs(opts or {}) do copy[key]=value end
        copy.requiredLevel=math.max(minimum,tonumber(copy.requiredLevel) or 0)
        return ns.EnqueueCommand(command,copy)
    end))
    local aioProxies = setmetatable({}, {__mode="k"})
    rawset(private,"GetAIO",function()
        local aio = ns.GetAIO()
        if not aio then return nil end
        if not aioProxies[aio] then
            aioProxies[aio] = setmetatable({Handle=guard(function(...) return aio.Handle(...) end)},{__index=aio})
        end
        return aioProxies[aio]
    end)
    rawset(private,"RegisterAddonPrefix",function(prefix,handler,opts)
        return ns.RegisterAddonPrefix(prefix,guard(handler),opts)
    end)
    return private
end

function Extensions.IsLoading()
    return loading == true
end

function Extensions.LoadAllowed()
    if not attached or loading or ns.Access.GetLevel()==nil then return false end
    local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    if not load then
        for _,package in ipairs(packages) do failures[package.name]="load_api_unavailable" end
        return false
    end
    loading = true
    local loadedAny = false
    for _,package in ipairs(packages) do
        if ns.Access.Allows(package.minimum) and not loaded[package.name] then
            local dependenciesReady = true
            for _,dependency in ipairs(package.dependencies) do
                if known[dependency] and not loaded[dependency] then
                    dependenciesReady = false; failures[package.name]="dependency: "..dependency
                end
            end
            if dependenciesReady then
                local ok, success, reason = pcall(load,package.name)
                if ok and success then
                    loaded[package.name] = true
                    failures[package.name] = nil
                    loadedAny = true
                elseif ns.PrintError then
                    local failure=tostring(ok and reason or success)
                    if failures[package.name]~=failure then
                        ns.PrintError("Не загружен " .. package.name .. ": " .. failure .. ". /nn status — диагностика.")
                    end
                    failures[package.name]=failure
                else
                    failures[package.name]=tostring(ok and reason or success)
                end
            end
        end
    end
    loading = false
    if loadedAny then
        if ns.ApplyAccessVisibility then ns.ApplyAccessVisibility() end
        if ns.Emit then ns.Emit("QUICK_ACTIONS_CHANGED") end
    end
    return true
end

function Extensions.AttachShell()
    assert(_G.NobleNextAPI==ns, "NobleNext shell must own the shared runtime")
    if attached then return end
    attached = true
    ns.Subscribe("ACCESS_CHANGED","NobleNextPackages",function()
        if ns.ClearCommandQueue then ns.ClearCommandQueue() end
        if ns.ApplyAccessVisibility then ns.ApplyAccessVisibility() end
        Extensions.LoadAllowed()
    end)
    -- A renewed role also retries a package that was absent/disabled earlier,
    -- without cancelling commands or registering successful packages twice.
    ns.Subscribe("ACCESS_CONFIRMED","NobleNextPackageRetry",function(value,_,previous)
        if value==previous then Extensions.LoadAllowed() end
    end)
    local reported
    ns.Subscribe("ACCESS_STATUS_CHANGED","NobleNextAccessNotice",function()
        local state=ns.Access.GetStatus()
        if state.reason=="confirmed" then reported=nil; return end
        if state.level==nil and state.state~="transferring" and not state.checking and state.reason~="not_requested" and state.reason~="offline"
            and reported~=state.reason and ns.PrintError then
            reported=state.reason
            ns.PrintError("Уровень доступа не подтверждён ("..state.reason.."). /nn status — диагностика и повторная проверка.")
        end
    end)
    local retryFrame=CreateFrame("Frame")
    retryFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    retryFrame:SetScript("OnEvent",Extensions.LoadAllowed)
    Extensions.LoadAllowed()
end
