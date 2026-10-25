-- Loaded through the NobleNextGM private extension namespace.
-- CommandDefinitions/Completeness.lua — эталон пользовательских leaf paths
-- Источник: локальные C++ trees (cs_gobject / GobTele / GobGroup / cs_npc / cs_go / cs_tele / gps / cs_lookup).
-- Внутренний transport endpoint capabilities в браузер команд не входит.

local _, ns = ...

---------------------------------------------------------------------------
-- Expected path counts (families)
---------------------------------------------------------------------------

ns.CommandDefinitionExpectedCounts = {
    gobject    = 58,
    npc        = 46,
    go         = 18,
    tele       = 8,
    gps        = 1,
    lookup     = 7,
    customnpc  = 19,
    poi        = 17,
    list       = 6,
    weather    = 1,
    daytime    = 1,
    setgrouptime = 1,
    wp         = 9,
    -- NobleNext top-level waypoint helpers + npcsetstate
    wpmove = 1, wpwalk = 1, wpwait = 1, wpemote = 1, wpclear = 1, wpgo = 1, wpstop = 1, npcsetstate = 1,
    pet        = 8,
    npccontrol = 1,
    deleteselected = 1,
    rps        = 23,
    total      = 233,
}

---------------------------------------------------------------------------
-- Canonical user command paths (233)
---------------------------------------------------------------------------

ns.CommandDefinitionExpectedPaths = {
    -- gobject vanilla (17) — cs_gobject.cpp
    "gobject activate",
    "gobject delete",
    "gobject info",
    "gobject move",
    "gobject near",
    "gobject list",
    "gobject check",
    "gobject pick",
    "gobject target",
    "gobject rotate",
    "gobject turn",
    "gobject spawngroup",
    "gobject despawngroup",
    "gobject add temp",
    "gobject add",
    "gobject set phase",
    "gobject set state",
    "gobject set scale",
    "gobject replace radius",
    "gobject replace",
    "gobject visibility",
    -- GobTele (2) — custom_gobtele_commands.cpp
    "gobject tele",
    "gobject teleport",
    -- GobGroup (26) — custom_gobgroup_commands.cpp
    "gobject group help",
    "gobject group create",
    "gobject group use",
    "gobject group add",
    "gobject group scan",
    "gobject group addnear",
    "gobject group remove",
    "gobject group dissolve",
    "gobject group delete",
    "gobject group info",
    "gobject group list",
    "gobject group near",
    "gobject group target",
    "gobject group check",
    "gobject group status",
    "gobject group capture",
    "gobject group recalc",
    "gobject group sync",
    "gobject group move",
    "gobject group turn",
    "gobject group nudge",
    "gobject group rotate",
    "gobject group scale",
    "gobject group relocate",
    "gobject group reload",
    "gobject group cleanup",
    -- GobBlueprint (9) — custom_gobblueprint_commands.cpp
    "gobject blueprint help",
    "gobject blueprint list",
    "gobject blueprint info",
    "gobject blueprint new",
    "gobject blueprint update",
    "gobject blueprint spawn",
    "gobject blueprint delete",
    "gobject blueprint rename",
    "gobject blueprint status",

    -- npc (46) — cs_npc.cpp active leaves
    "npc add formation",
    "npc add item",
    "npc add move",
    "npc add temp",
    "npc add",
    "npc set allowmove",
    "npc set entry",
    "npc set factionid",
    "npc set flag",
    "npc set level",
    "npc set link",
    "npc set model",
    "npc set movetype",
    "npc set phase",
    "npc set scale",
    "npc set wanderdistance",
    "npc set spawntime",
    "npc set data",
    "npc set aura",
    "npc set mount",
    "npc set anim",
    "npc set animkit",
    "npc set equipment",
    "npc equip left",
    "npc equip ranged",
    "npc equip right",
    "npc unequip left",
    "npc unequip ranged",
    "npc unequip right",
    "npc info",
    "npc near",
    "npc move",
    "npc playemote",
    "npc say",
    "npc textemote",
    "npc whisper",
    "npc yell",
    "npc tame",
    "npc spawngroup",
    "npc despawngroup",
    "npc delete",
    "npc delete item",
    "npc follow",
    "npc follow stop",
    "npc evade",
    "npc showloot",

    -- go (18) — cs_go.cpp (.go default + xyz share HandleGoXYZCommand)
    "go",
    "go creature",
    "go creature id",
    "go gameobject",
    "go gameobject id",
    "go graveyard",
    "go grid",
    "go quest",
    "go taxinode",
    "go areatrigger",
    "go zonexy",
    "go xyz",
    "go bugticket",
    "go complaintticket",
    "go suggestionticket",
    "go offset",
    "go instance",
    "go boss",

    -- tele (8) — cs_tele.cpp
    "tele",
    "tele add",
    "tele del",
    "tele group",
    "tele name",
    "tele name npc id",
    "tele name npc guid",
    "tele name npc name",

    -- gps (1) — cs_misc.cpp
    "gps",

    -- lookup (7) — cs_lookup.cpp Wave 2A + RP phase
    "lookup creature",
    "lookup object",
    "lookup object like",
    "lookup item",
    "lookup tele",
    "lookup quest",
    "lookup rp phase",

    -- customnpc (19)
    "customnpc",
    "customnpc help",
    "customnpc add",
    "customnpc apply",
    "customnpc list",
    "customnpc delete",
    "customnpc spawn",
    "customnpc spawn temp",
    "customnpc set name",
    "customnpc set scale",
    "customnpc set displayid",
    "customnpc set race",
    "customnpc set gender",
    "customnpc set subname",
    "customnpc clone",
    "customnpc clone player",
    "customnpc clone target",
    "customnpc clone custom",
    "customnpc clone entry",

    -- poi (17)
    "poi",
    "poi help",
    "poi create",
    "poi delete",
    "poi list",
    "poi sync",
    "poi set name",
    "poi set description",
    "poi set position",
    "poi set type",
    "poi set icon",
    "poi set color",
    "poi set apply",
    "poi set owner player",
    "poi set owner org",
    "poi set owner system",
    "poi set owner npc",

    -- list (6)
    "list creature",
    "list object",
    "list item",
    "list auras",
    "list auras id",
    "list auras name",

    -- weather / time (3)
    "weather",
    "daytime",
    "setgrouptime",

    -- waypoints vanilla (9) + NobleNext helpers (8)
    "wp add",
    "wp load",
    "wp modify",
    "wp unload",
    "wp reload",
    "wp show",
    "wp move",
    "wp delay",
    "wp lookup",
    "wpmove",
    "wpwalk",
    "wpwait",
    "wpemote",
    "wpclear",
    "wpgo",
    "wpstop",
    "npcsetstate",

    -- pet (8)
    "pet",
    "pet say",
    "pet emote",
    "pet stay",
    "pet follow",
    "pet play",
    "pet pos",
    "pet tele",

    -- army hooks (2)
    "npccontrol",
    "deleteselected",

    -- RP World Maps / logical phases (22) — CommandDefinitions/RpPhase.lua
    "rps phase help",
    "rps phase create",
    "rps phase list",
    "rps phase info",
    "rps phase enter",
    "rps phase leave",
    "rps phase invite",
    "rps phase revoke",
    "rps phase archive",
    "rps phase unarchive",
    "rps phase reload",
    "rps phase spawn info",
    "rps phase spawn assign",
    "rps phase spawn clear",
    "rps phase set name",
    "rps phase set public",
    "rps phase set owner",
    "rps phase set role",
    "rps phase set spawn",
    "rps phase set enter-spawn",
    "rps phase goto",
    "rps pha set owner",


    -- Client-only panel opener (1)
}

---------------------------------------------------------------------------
-- Checker
---------------------------------------------------------------------------

local function debugEnabled()
    return NobleNextDB and NobleNextDB.debugCommands
end

local function chatPrint(msg)
    local frame = DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then
        frame:AddMessage(msg)
    else
        print(msg)
    end
end

local function familyOf(path)
    local root = path:match("^(%S+)")
    return root or "?"
end

local function countByFamily(paths)
    local counts = {}
    for i = 1, #paths do
        local fam = familyOf(paths[i])
        counts[fam] = (counts[fam] or 0) + 1
    end
    return counts
end

--- Local fallback when AssertComplete is missing.
local function runLocalCompletenessCheck()
    local expected = ns.CommandDefinitionExpectedPaths
    local CD = ns.CommandDefinitions

    local missing = {}
    local present = 0

    for i = 1, #expected do
        local path = expected[i]
        local def = CD and CD.Find and CD.Find(path)
        if not def then
            missing[#missing + 1] = path
        else
            present = present + 1
        end
    end

    local ok = #missing == 0
    local result = {
        ok = ok,
        expected = #expected,
        present = present,
        missing = missing,
        familyCounts = countByFamily(expected),
        usedAssertComplete = false,
        ran = true,
    }
    return result
end

local function mergeAssertComplete(result)
    local CD = ns.CommandDefinitions
    if not (CD and CD.AssertComplete) then
        return result
    end

    local ok, missing = CD.AssertComplete(ns.CommandDefinitionExpectedPaths)
    result.usedAssertComplete = true
    result.assertCompleteOk = ok and true or false

    -- Prefer AssertComplete missing list if it reported any (union)
    if type(missing) == "table" then
        local seen = {}
        for i = 1, #result.missing do
            seen[result.missing[i]] = true
        end
        for i = 1, #missing do
            local label = missing[i]
            if label and not seen[label] then
                result.missing[#result.missing + 1] = label
                seen[label] = true
            end
        end
    end

    result.ok = #result.missing == 0
    result.present = result.expected - #result.missing
    return result
end

local function reportResult(result)
    ns.CommandDefinitionCompletenessResult = result

    if not debugEnabled() then
        return
    end

    local prefix = "|cff66ccff[NobleNext CmdDefs]|r "
    chatPrint(string.format(
        "%scompleteness: %d/%d present (gobject=%d npc=%d go=%d tele=%d gps=%d lookup=%d)%s",
        prefix,
        result.present,
        result.expected,
        result.familyCounts.gobject or 0,
        result.familyCounts.npc or 0,
        result.familyCounts.go or 0,
        result.familyCounts.tele or 0,
        result.familyCounts.gps or 0,
        result.familyCounts.lookup or 0,
        result.ok and " — OK" or " — ISSUES"
    ))

    if result.usedAssertComplete then
        chatPrint(prefix .. "AssertComplete: " .. (result.assertCompleteOk and "ok" or "missing defs"))
    else
        chatPrint(prefix .. "AssertComplete API missing — used local fallback")
    end

    for i = 1, #result.missing do
        chatPrint(prefix .. "|cffff6666missing|r " .. result.missing[i])
    end
end

function ns.CommandDefinitionsRunCompletenessCheck()
    local result = runLocalCompletenessCheck()
    result = mergeAssertComplete(result)
    reportResult(result)
    return result
end

-- Run immediately (toc loads this after catalog files) and once on ADDON_LOADED.
ns.CommandDefinitionsRunCompletenessCheck()

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, _, name)
    if name ~= ns.AddonIdentity then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")
    -- Re-run after SavedVariables are guaranteed; catalogs already registered.
    ns.CommandDefinitionsRunCompletenessCheck()
end)
