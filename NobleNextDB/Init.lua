local _, ns = ...
local manifest = ns.manifest
local API = {}
local factories, decoded, jobs, references = {}, {}, {}, {}
local raceById = {}
local schedule = C_Timer and C_Timer.After
local eventFrame = CreateFrame("Frame")

for _, race in ipairs(manifest.races) do
    raceById[race.race_id] = race
end

local function report(callback, data, reason)
    local ok, err = pcall(callback, data, reason)
    if not ok and geterrorhandler then
        geterrorhandler()(err)
    end
end

local function finish(job, data, reason)
    if jobs[job.key] ~= job then return end
    jobs[job.key] = nil
    job.thread = nil
    if data and (references[job.key] or 0) > 0 then
        decoded[job.key] = data
    end
    local leases = job.leases
    job.leases = nil
    for _, lease in ipairs(leases) do
        if lease.active and lease.callback then
            local callback = lease.callback
            lease.callback = nil
            report(callback, data, reason)
        end
    end
end

local function decodeModel(raceId, sex)
    local result = { race_id = raceId, sex = sex, build_id = manifest.metadata.build_id,
        locale = manifest.metadata.locale, models = {}, requirements = {},
        requirementsById = {}, requirement_choices = {}, requiredChoicesByRequirement = {} }
    local model
    local count = 0
    local started = debugprofilestop and debugprofilestop()
    factories[raceId][sex](function(tag, row)
        if tag == "model" then
            assert(not model and row.race_id == raceId and row.sex == sex, "Catalog model mismatch")
            model = row
            model.options, model.optionsById, model.choicesById = {}, {}, {}
            result.models[sex] = model
        elseif tag == "option" then
            assert(model and row.chr_model_id == model.chr_model_id, "Catalog option model mismatch")
            row.choices, row.choicesById = {}, {}
            model.optionsById[row.option_id] = row
            table.insert(model.options, row)
        elseif tag == "choice" then
            local option = assert(model and model.optionsById[row.option_id], "Unknown catalog option")
            table.insert(option.choices, row)
            option.choicesById[row.choice_id] = row
            model.choicesById[row.choice_id] = row
        elseif tag == "requirement" then
            table.insert(result.requirements, row)
            result.requirementsById[row.requirement_id] = row
        elseif tag == "dependency" then
            table.insert(result.requirement_choices, row)
            local list = result.requiredChoicesByRequirement[row.requirement_id] or {}
            result.requiredChoicesByRequirement[row.requirement_id] = list
            table.insert(list, row.required_choice_id)
        else
            error("Unknown catalog row")
        end
        count = count + 1
        if count % 40 == 0 or (started and debugprofilestop() - started >= 2) then
            coroutine.yield()
            started = debugprofilestop and debugprofilestop()
        end
    end)
    assert(model, "Missing catalog model")
    return result
end

local step
step = function(job)
    if jobs[job.key] ~= job then return end
    if InCombatLockdown and InCombatLockdown() then
        job.waitingForCombat = true
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    job.waitingForCombat = nil
    if not job.thread then
        job.thread = coroutine.create(function() return decodeModel(job.raceId, job.sex) end)
    end
    local ok, result = coroutine.resume(job.thread)
    if not ok then finish(job, nil, "invalid_catalog"); return end
    if coroutine.status(job.thread) == "dead" then
        finish(job, result)
    else
        schedule(0, function() step(job) end)
    end
end

eventFrame:SetScript("OnEvent", function()
    eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    for _, job in pairs(jobs) do
        if job.waitingForCombat then schedule(0, function() step(job) end) end
    end
end)

function API.RegisterModel(raceId, sex, buildId, sourceChecksum, factory)
    assert(raceById[raceId] and buildId == manifest.metadata.build_id, "Catalog metadata mismatch")
    assert(sex == 0 or sex == 1, "Invalid catalog sex")
    assert(sourceChecksum == manifest.metadata.package_checksum, "Catalog source mismatch")
    assert(type(factory) == "function", "Invalid catalog factory")
    factories[raceId] = factories[raceId] or {}
    factories[raceId][sex] = factory
end

function API.GetMetadata()
    return manifest.metadata
end

function API.GetRaceList()
    return manifest.races
end

function API.GetClasses()
    return manifest.classes
end

-- Mirror the NPC requirement projection in RolePlayCustomNpcOps.cpp, not player unlocks.
-- Source ReqType maps to native Flags; bit 0 is ChrCustomizationReqFlag::HasRequirements.
local specialRaceBits = { [34] = 11, [35] = 12, [36] = 13, [37] = 14, [52] = 16,
    [70] = 15, [84] = 17, [85] = 18, [86] = 20, [91] = 19 }

local function raceBit(raceId)
    if (raceId >= 1 and raceId <= 11) or raceId == 22 or (raceId >= 24 and raceId <= 32) then
        return raceId - 1
    end
    return specialRaceBits[raceId]
end

local function unsigned32(value)
    local number = tonumber(value)
    if not number or number % 1 ~= 0 or number < -2147483648 or number > 4294967295 then return nil end
    return number < 0 and number + 4294967296 or number
end

local function hasBit(value, bit)
    return math.floor(value / 2 ^ bit) % 2 == 1
end

local function evaluateRequirement(data, model, requirementId, classId, selectedByOption)
    requirementId = tonumber(requirementId)
    if requirementId == 0 then return true end
    local requirement = data.requirementsById and data.requirementsById[requirementId]
    if not requirement then return nil, "server_required" end
    local flags = unsigned32(requirement.requirement_type)
    if not flags then return nil, "server_required" end
    if not hasBit(flags, 0) then return true end

    local classMask = unsigned32(requirement.class_mask)
    if not classMask then return nil, "server_required" end
    if classMask ~= 0 then
        classId = tonumber(classId)
        if not classId then return nil, "server_required" end
        if classId % 1 ~= 0 or classId < 1 or classId > 32 or not hasBit(classMask, classId - 1) then
            return false, "class_required"
        end
    end

    local mask0, mask1 = unsigned32(requirement.race_mask_0), unsigned32(requirement.race_mask_1)
    if not mask0 or not mask1 then return nil, "server_required" end
    if data.race_id ~= 0 and not (mask0 == 0 and mask1 == 0)
        and not (mask0 == 4294967295 and mask1 == 4294967295) then
        local bit = raceBit(data.race_id)
        -- The package and native race mapping must agree; never guess for unsupported races.
        if not bit or tonumber(model.playable_race_bit) ~= bit then return nil, "server_required" end
        if not hasBit(bit < 32 and mask0 or mask1, bit % 32) then return false, "race_required" end
    end

    if not data.requiredChoicesByRequirement then return nil, "server_required" end
    local requiredChoices = data.requiredChoicesByRequirement[requirementId]
    if requiredChoices and #requiredChoices > 0 then
        if type(selectedByOption) ~= "table" then return nil, "server_required" end
        local groups = {}
        for _, choiceId in ipairs(requiredChoices) do
            local choice = model.choicesById and model.choicesById[choiceId]
            if not choice or not model.optionsById[choice.option_id] then return nil, "server_required" end
            local group = groups[choice.option_id] or {}
            groups[choice.option_id] = group
            group[choiceId] = true
        end
        -- Native rules are OR within one option, AND between different options.
        for optionId, choices in pairs(groups) do
            if not choices[tonumber(selectedByOption[optionId])] then return false, "choice_required" end
        end
    end
    return true
end

local function catalogOption(data, sex, optionId)
    if type(data) ~= "table" or data.build_id ~= manifest.metadata.build_id
        or type(data.race_id) ~= "number" or not data.models then return nil end
    local model = data.models[tonumber(sex)]
    local option = model and model.optionsById and model.optionsById[tonumber(optionId)]
    if not option then return nil end
    return model, option
end

function API.EvaluateOption(data, sex, optionId, classId, selectedByOption)
    local model, option = catalogOption(data, sex, optionId)
    if not model then return nil, "server_required" end
    return evaluateRequirement(data, model, option.requirement_id, classId, selectedByOption)
end

function API.EvaluateChoice(data, sex, optionId, choiceId, classId, selectedByOption)
    local model, option = catalogOption(data, sex, optionId)
    local choice = option and option.choicesById and option.choicesById[tonumber(choiceId)]
    if not choice then return nil, "server_required" end
    local available, reason = evaluateRequirement(data, model, option.requirement_id, classId, selectedByOption)
    if available ~= true then return available, reason end
    -- ChrCustomizationVisReq is a different namespace and is not checked by native NPC rules.
    return evaluateRequirement(data, model, choice.requirement_id, classId, selectedByOption)
end

function API.AcquireModel(raceId, sex, callback)
    raceId, sex = tonumber(raceId), tonumber(sex)
    local key = tostring(raceId) .. ":" .. tostring(sex)
    assert(type(callback) == "function", "Catalog callback is required")
    local lease = { active = true, callback = callback }
    function lease:Release()
        if not self.active then return end
        self.active, self.callback = false, nil
        if not self.counted then return end
        self.counted = nil
        references[key] = math.max(0, (references[key] or 1) - 1)
        if references[key] == 0 then
            references[key], decoded[key] = nil, nil
            local job = jobs[key]
            if job then job.thread, job.leases = nil, nil end
            jobs[key] = nil
        end
    end
    if not schedule then
        lease:Release()
        return nil, "timer_unavailable"
    end
    if not raceById[raceId] or not factories[raceId] or not factories[raceId][sex] then
        schedule(0, function()
            if lease.active and lease.callback then
                local cb = lease.callback
                lease.callback = nil
                report(cb, nil, not raceById[raceId] and "unknown_race" or "unknown_model")
            end
        end)
        return lease
    end
    lease.counted = true
    references[key] = (references[key] or 0) + 1
    if decoded[key] then
        schedule(0, function()
            if lease.active and lease.callback then
                local cb = lease.callback
                lease.callback = nil
                report(cb, decoded[key])
            end
        end)
    elseif jobs[key] then
        table.insert(jobs[key].leases, lease)
    else
        local job = { key = key, raceId = raceId, sex = sex, leases = { lease } }
        jobs[key] = job
        schedule(0, function() step(job) end)
    end
    return lease
end

-- Diagnostics describe our references, not total Lua/renderer memory or addon unloading.
function API.GetCacheStats()
    local stats = { sourceModels = 0, decodedModels = 0, pendingModels = 0, leases = 0 }
    for _, models in pairs(factories) do
        for _ in pairs(models) do stats.sourceModels = stats.sourceModels + 1 end
    end
    for _ in pairs(decoded) do stats.decodedModels = stats.decodedModels + 1 end
    for _ in pairs(jobs) do stats.pendingModels = stats.pendingModels + 1 end
    for _, count in pairs(references) do stats.leases = stats.leases + count end
    return stats
end

_G.NobleNextData = API
