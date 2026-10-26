-- Core/CommandDefinitions.lua — one role-aware catalog engine, no privileged definitions.
--
--[[ Schema (каждое определение)
{
  path = {"gobject","group","info"},           -- токены пути (обязательно)
  aliases = {{"gob","group","info"}},          -- опциональные альтернативные пути
  serverPath = "gobject group info",           -- точная строка пути для сервера
                                               -- (по умолчанию: join(path, " ");
                                               --  сохраняется при нормализации
                                               --  spaced-токенов вроде "delete item")
  syntax = ".gobject group info <object-guid>",
  description = "...",                         -- RU OK
  args = {
    { name="objectGuid", type="spawnId", required=true,
      choices=nil, default=nil },              -- type: string|number|spawnId|
                                               --        guid|choice|literal|...
  },
  destructive = false|true|"metadata"|"db"|"delete",
  console = false,
  responseMode = "system"|"structured"|"silent",
  packets = {"INFO_BEGIN","INFO_OBJECT","..."},
  examples = { ".gobject group info 123" },
  executable = true,                           -- узел может быть executable И иметь children
  children = { ... },                          -- вложенные def (path относительно родителя
                                               -- или абсолютный)
}

API: ns.CommandDefinitions
  Register / RegisterMany / RegisterFamily
  Find / Complete / Validate / Format / CanRun / List / AssertComplete
]]

local ns = LibStub("NobleNextLib-1.0").Runtime
if ns.CommandDefinitions and ns.CommandDefinitions.RegistryVersion == 1 then return end
assert(not ns.CommandDefinitions, "CommandDefinitions registry already initialized by another implementation")
local CD = { RegistryVersion = 1 }
ns.CommandDefinitions = CD
local facades, ownerLevels = {}, {}

local function allowed(minimum)
    return ns.Access and ns.Access.Allows(minimum) == true
end
local function visible(def)
    return def and allowed(def.requiredLevel)
end
local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}; seen[value] = copy
    for key, child in pairs(value) do copy[key] = deepCopy(child, seen) end
    return copy
end
local function equal(a, b, seen)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for key, value in pairs(a) do if not equal(value, b[key], seen) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

-- byKey["gobject group info"] = def
local byKey = {}
-- aliasKey -> canonical key
local aliasToKey = {}
-- trie root: children[token] = node; node.def / node.children
local root = { children = {} }
-- registration order for List()
local ordered = {}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function splitWhitespace(s)
    local out = {}
    for token in tostring(s or ""):gmatch("%S+") do
        out[#out + 1] = token
    end
    return out
end

--- Flatten path: string | string[] -> tokens[]; spaced elements become multiple tokens.
--- Returns tokens, originalJoined (for serverPath default before flatten join).
local function normalizePath(path)
    if path == nil then
        return nil, nil
    end

    local rawParts
    if type(path) == "string" then
        rawParts = { path }
    elseif type(path) == "table" then
        rawParts = path
    else
        return nil, nil
    end

    local originalPieces = {}
    local tokens = {}
    for i = 1, #rawParts do
        local part = trim(rawParts[i])
        if part ~= "" then
            originalPieces[#originalPieces + 1] = part
            for token in part:gmatch("%S+") do
                tokens[#tokens + 1] = token:lower()
            end
        end
    end

    if #tokens == 0 then
        return nil, nil
    end

    return tokens, table.concat(originalPieces, " ")
end

local function pathKey(tokens)
    return table.concat(tokens, " ")
end

local function stripDotPrefix(text)
    text = trim(text)
    if text:sub(1, 1) == "." then
        text = trim(text:sub(2))
    end
    return text
end

local function copyArray(src)
    if not src then return nil end
    local out = {}
    for i = 1, #src do
        out[i] = src[i]
    end
    return out
end

local function shallowCopyDef(def)
    local out = {}
    for k, v in pairs(def) do
        out[k] = v
    end
    return out
end

local function ensureNode(parent, token)
    local children = parent.children
    local node = children[token]
    if not node then
        node = { children = {}, token = token }
        children[token] = node
    end
    return node
end

local function walkTo(tokens, create)
    local node = root
    for i = 1, #tokens do
        local token = tokens[i]
        local nextNode = node.children[token]
        if not nextNode then
            if not create then
                return nil, i
            end
            nextNode = ensureNode(node, token)
        end
        node = nextNode
    end
    return node
end

local function indexDef(def, tokens, isAlias)
    local key = pathKey(tokens)
    local node = walkTo(tokens, true)
    if not isAlias then
        node.def = def
        if not byKey[key] then
            ordered[#ordered + 1] = def
        end
        byKey[key] = def
    else
        aliasToKey[key] = def.key
        if not node.def then
            node.def = def
        end
        if not node.aliasDefs then
            node.aliasDefs = {}
        end
        node.aliasDefs[#node.aliasDefs + 1] = def
    end
end

local function resolveArgValue(argDef, argValues, index)
    if type(argValues) == "table" then
        if argValues[argDef.name] ~= nil then
            return argValues[argDef.name]
        end
        if argValues[index] ~= nil then
            return argValues[index]
        end
    end
    return nil
end

local function isEmptyValue(v)
    return v == nil or v == ""
end

local function valueInChoices(argDef, value)
    local choices = argDef.choices
    if not choices or #choices == 0 then
        return true
    end
    local s = tostring(value):lower()
    for i = 1, #choices do
        local c = choices[i]
        local name = type(c) == "table" and (c.name or c.value) or c
        if tostring(name):lower() == s then
            return true
        end
    end
    return false
end

local function typeOk(argDef, value)
    if isEmptyValue(value) then
        return true
    end
    local t = argDef.type or "string"
    if t == "number" or t == "spawnId" or t == "guid" or t == "entry" then
        return tonumber(value) ~= nil
    end
    if t == "choice" or t == "literal" then
        return valueInChoices(argDef, value)
    end
    -- string and unknown types: accept any non-validated loosely
    if argDef.choices then
        return valueInChoices(argDef, value)
    end
    return true
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

-- A package owns each canonical definition permanently. Registration may append
-- new children to an existing family but never replace another definition/alias.
local function collect(def, prefix, owner, minimum, out)
    assert(type(def) == "table", "CommandDefinitions: definition must be a table")
    local pathInput = def.path
    if prefix then
        pathInput = copyArray(prefix)
        if type(def.path) == "string" then pathInput[#pathInput + 1] = def.path
        elseif type(def.path) == "table" then
            for _, part in ipairs(def.path) do pathInput[#pathInput + 1] = part end
        elseif def.path ~= nil then error("CommandDefinitions: invalid child path") end
    end
    local tokens, originalJoined = normalizePath(pathInput)
    assert(tokens, "CommandDefinitions: path is required")
    assert(def.owner == nil or def.owner == owner, "CommandDefinitions: owner cannot be overridden")
    local required = def.requiredLevel == nil and minimum or def.requiredLevel
    assert(type(required) == "number" and required == math.floor(required)
        and required >= minimum and required <= 255, "CommandDefinitions: invalid requiredLevel")
    local stored = deepCopy(def)
    stored.path, stored.key = tokens, pathKey(tokens)
    stored.serverPath = trim(def.serverPath or originalJoined):gsub("^[%./]+", "")
    stored.owner, stored.requiredLevel = owner, required
    stored.args = stored.args or {}
    stored.children = nil
    if stored.executable == nil then
        stored.executable = not (def.children and #def.children > 0)
            or (def.args and #def.args > 0) or def.syntax ~= nil or false
    end
    stored.aliases = {}
    local seen = {}
    for _, alias in ipairs(def.aliases or {}) do
        local aliasTokens = normalizePath(alias)
        assert(aliasTokens, "CommandDefinitions: invalid alias")
        local key = pathKey(aliasTokens)
        if key ~= stored.key and not seen[key] then
            stored.aliases[#stored.aliases + 1] = aliasTokens; seen[key] = true
        end
    end
    out[#out + 1] = stored
    for _, child in ipairs(def.children or {}) do collect(child, tokens, owner, minimum, out) end
end

local function registerBatch(list, owner, minimum)
    assert(type(list) == "table", "CommandDefinitions: list required")
    local staged, canonicals, aliases = {}, {}, {}
    for _, def in ipairs(list) do collect(def, nil, owner, minimum, staged) end
    -- Validate the entire batch before touching any persistent index.
    for _, def in ipairs(staged) do
        local existing = canonicals[def.key] or byKey[def.key]
        assert(not existing or equal(existing, def), "CommandDefinitions: duplicate canonical path " .. def.key)
        local aliasOwner = aliasToKey[def.key]
        assert(not aliasOwner or aliasOwner == def.key, "CommandDefinitions: canonical collides with alias " .. def.key)
        canonicals[def.key] = def
    end
    for _, def in ipairs(staged) do
        for _, tokens in ipairs(def.aliases) do
            local key = pathKey(tokens)
            local canonical = canonicals[key] or byKey[key]
            assert(not canonical or canonical.key == def.key, "CommandDefinitions: alias collides with canonical " .. key)
            local existing = aliases[key] or aliasToKey[key]
            assert(not existing or existing == def.key, "CommandDefinitions: duplicate alias " .. key)
            aliases[key] = def.key
        end
    end
    local result = {}
    for _, def in ipairs(staged) do
        if not byKey[def.key] then
            indexDef(def, def.path, false)
            for _, tokens in ipairs(def.aliases) do indexDef(def, tokens, true) end
        end
        result[#result + 1] = deepCopy(byKey[def.key])
    end
    return result
end

---------------------------------------------------------------------------
-- Lookup
---------------------------------------------------------------------------

function CD.Find(pathOrString)
    if pathOrString == nil then
        return nil
    end

    local tokens
    if type(pathOrString) == "table" and pathOrString.key then
        local def = byKey[pathOrString.key]
        return visible(def) and deepCopy(def) or nil
    end

    if type(pathOrString) == "string" then
        tokens = normalizePath(stripDotPrefix(pathOrString))
    else
        tokens = normalizePath(pathOrString)
    end
    if not tokens then
        return nil
    end

    local key = pathKey(tokens)
    local def = byKey[key]
    if def then
        return visible(def) and deepCopy(def) or nil
    end

    local aliased = aliasToKey[key]
    if aliased then
        local def = byKey[aliased]
        return visible(def) and deepCopy(def) or nil
    end

    local node = walkTo(tokens, false)
    if node and visible(node.def) then
        return deepCopy(node.def)
    end
    return nil
end

---------------------------------------------------------------------------
-- Complete (Tab candidates: paths + literal/choice args)
---------------------------------------------------------------------------

local function pushCandidate(out, seen, text, def, kind, detail)
    local key = text:lower()
    if seen[key] then
        return
    end
    seen[key] = true
    out[#out + 1] = {
        text = text,
        def = visible(def) and deepCopy(def) or nil,
        kind = kind, -- "path" | "choice" | "arg"
        detail = detail,
    }
end

local function hasVisible(node)
    if visible(node.def) then return true end
    for _, child in pairs(node.children) do if hasVisible(child) then return true end end
    return false
end

local function sortedChildTokens(node)
    local keys = {}
    for token, child in pairs(node.children) do
        if hasVisible(child) then keys[#keys + 1] = token end
    end
    table.sort(keys)
    return keys
end

function CD.Complete(partialText)
    partialText = tostring(partialText or ""):gsub("^%s*%.?%s*", "")
    local trailingSpace = partialText:match("%s$") ~= nil
    local tokens = splitWhitespace(partialText:lower())
    local out, seen = {}, {}

    local node = root
    local consumed = {}
    local tokenIndex = 1

    -- Сначала потребляем точный путь команды. Остаток считаем аргументами.
    while tokenIndex <= #tokens do
        local token = tokens[tokenIndex]
        local child = node.children[token]
        if not child then
            break
        end
        consumed[#consumed + 1] = token
        node = child
        tokenIndex = tokenIndex + 1
    end

    -- Последний незавершённый токен ещё может быть частью пути, а не аргументом.
    if tokenIndex <= #tokens and tokenIndex == #tokens and not trailingSpace then
        local token = tokens[tokenIndex]
        local pathMatches = 0
        for _, childToken in ipairs(sortedChildTokens(node)) do
            if childToken:sub(1, #token) == token then
                local path = copyArray(consumed) or {}
                path[#path + 1] = childToken
                local child = node.children[childToken]
                pushCandidate(out, seen, table.concat(path, " "), child.def, "path", childToken)
                pathMatches = pathMatches + 1
            end
        end
        if pathMatches > 0 then
            return out
        end
    end

    local provided = {}
    for i = tokenIndex, #tokens do
        provided[#provided + 1] = tokens[i]
    end

    -- Точные дочерние команды всегда доступны рядом с аргументами executable-узла.
    if #provided == 0 then
        for _, childToken in ipairs(sortedChildTokens(node)) do
            local path = copyArray(consumed) or {}
            path[#path + 1] = childToken
            local child = node.children[childToken]
            pushCandidate(out, seen, table.concat(path, " "), child.def, "path", childToken)
        end
    end

    if visible(node.def) and node.def.executable then
        local args = node.def.args or {}
        local completedCount = trailingSpace and #provided or math.max(0, #provided - 1)
        local argIndex = 1

        -- Привязываем уже завершённые значения, разрешая пропуск optional-аргументов.
        for valueIndex = 1, completedCount do
            local value = provided[valueIndex]
            while args[argIndex] do
                local candidate = args[argIndex]
                if typeOk(candidate, value) then
                    argIndex = argIndex + 1
                    break
                end
                if candidate.required == false then
                    argIndex = argIndex + 1
                else
                    break
                end
            end
        end

        local argPrefix = trailingSpace and "" or (provided[#provided] or "")
        local argDef = args[argIndex]
        -- Для текущего prefix можно пропустить несовместимый optional-аргумент.
        while argDef and not argDef.choices and argDef.required == false do
            if argPrefix ~= "" and typeOk(argDef, argPrefix) then
                break
            end
            argIndex = argIndex + 1
            argDef = args[argIndex]
        end
        if argDef and argDef.choices then
            local baseParts = copyArray(consumed) or {}
            for i = 1, completedCount do
                if provided[i] then
                    baseParts[#baseParts + 1] = provided[i]
                end
            end
            local base = table.concat(baseParts, " ")
            for ci = 1, #argDef.choices do
                local choice = argDef.choices[ci]
                local name = type(choice) == "table" and (choice.name or choice.value) or tostring(choice)
                local lowered = tostring(name):lower()
                if argPrefix == "" or lowered:sub(1, #argPrefix) == argPrefix then
                    pushCandidate(out, seen, base .. " " .. name, node.def, "choice", name)
                end
            end
        end
    end

    return out
end

---------------------------------------------------------------------------
-- Validate / Format / CanRun
---------------------------------------------------------------------------

function CD.Validate(def, argValues)
    def = CD.Find(def)
    if not def then
        return false, "unknown command"
    end
    if def.executable == false then
        return false, "command is not executable"
    end

    argValues = argValues or {}
    local args = def.args or {}

    local hasNamedValues = false
    if type(argValues) == "table" then
        for i = 1, #args do
            local name = args[i].name
            if name and argValues[name] ~= nil then
                hasNamedValues = true
                break
            end
        end
    end

    if type(argValues) == "table" and not hasNamedValues then
        local valueIndex = 1
        for i = 1, #args do
            local argDef = args[i]
            local required = argDef.required
            if required == nil then required = true end
            local value = argValues[valueIndex]

            if isEmptyValue(value) then
                value = argDef.default
            end
            if isEmptyValue(value) then
                if required then
                    return false, "missing argument: " .. tostring(argDef.name or i)
                end
            elseif typeOk(argDef, value) then
                valueIndex = valueIndex + 1
            elseif required then
                return false, "invalid argument: " .. tostring(argDef.name or i)
            end
            -- Несовместимый optional-аргумент пропускается без потребления value.
        end
        return true, nil
    end

    for i = 1, #args do
        local argDef = args[i]
        local required = argDef.required
        if required == nil then
            required = true
        end
        local value = resolveArgValue(argDef, argValues, i)
        if isEmptyValue(value) then
            if argDef.default ~= nil then
                value = argDef.default
            end
        end
        if isEmptyValue(value) then
            if required then
                return false, "missing argument: " .. tostring(argDef.name or i)
            end
        elseif not typeOk(argDef, value) then
            return false, "invalid argument: " .. tostring(argDef.name or i)
        end
    end
    return true, nil
end

function CD.Format(def, argValues)
    def = CD.Find(def)
    if not def then
        return nil
    end

    argValues = argValues or {}
    local parts = { "." .. def.serverPath }
    local args = def.args or {}

    for i = 1, #args do
        local argDef = args[i]
        local value = resolveArgValue(argDef, argValues, i)
        if isEmptyValue(value) and argDef.default ~= nil then
            value = argDef.default
        end
        if not isEmptyValue(value) then
            parts[#parts + 1] = tostring(value)
        end
    end

    -- allow extra positional values beyond declared args
    if type(argValues) == "table" then
        local startExtra = #args + 1
        for i = startExtra, #argValues do
            if not isEmptyValue(argValues[i]) then
                parts[#parts + 1] = tostring(argValues[i])
            end
        end
    end

    return table.concat(parts, " ")
end

--- capsMap: path/serverPath -> allowed (truthy). Missing key = not allowed.
function CD.CanRun(def, capsMap)
    def = CD.Find(def)
    if not def then
        return false
    end
    if def.executable == false then
        return false
    end
    if type(capsMap) ~= "table" then
        return false
    end

    local keys = {
        def.serverPath,
        def.key,
        pathKey(def.path),
    }
    for i = 1, #keys do
        local k = keys[i]
        if k and capsMap[k] ~= nil then
            return capsMap[k] and true or false
        end
    end

    -- dotted forms
    if capsMap["." .. def.serverPath] ~= nil then
        return capsMap["." .. def.serverPath] and true or false
    end

    return false
end

---------------------------------------------------------------------------
-- List / AssertComplete
---------------------------------------------------------------------------

function CD.List(filter)
    filter = trim(filter or ""):lower()
    local out = {}
    for i = 1, #ordered do
        local def = ordered[i]
        if visible(def) and filter == "" then
            out[#out + 1] = deepCopy(def)
        elseif visible(def) then
            local hay = table.concat({
                def.key or "",
                def.serverPath or "",
                def.syntax or "",
                def.description or "",
            }, " "):lower()
            if hay:find(filter, 1, true) then
                out[#out + 1] = deepCopy(def)
            end
        end
    end
    return out
end

--- expectedPaths: list of path strings / token arrays that must be registered.
--- Returns ok, missing[]
function CD.AssertComplete(expectedPaths)
    local missing = {}
    if type(expectedPaths) ~= "table" then
        return true, missing
    end
    for i = 1, #expectedPaths do
        local expected = expectedPaths[i]
        if not CD.Find(expected) then
            local label
            if type(expected) == "table" then
                local tokens = normalizePath(expected)
                label = tokens and pathKey(tokens) or tostring(expected)
            else
                label = tostring(expected)
            end
            missing[#missing + 1] = label
        end
    end
    return #missing == 0, missing
end

---------------------------------------------------------------------------
-- Introspection (optional helpers for UI / tests)
---------------------------------------------------------------------------

function CD.Get(key) return CD.Find(key) end
function CD.Count() return #CD.List() end

function CD.GetRoots()
    return sortedChildTokens(root)
end

-- Facades do not own indexes: DM and GM append to the same singleton. Reads use
-- current access, not the role at registration time; stale copies cannot bypass
-- CanRun/Format/Validate after demotion. Registration always stamps this owner.
function CD.ForOwner(owner, minimum)
    assert(type(owner) == "string" and owner ~= "", "CommandDefinitions: owner required")
    assert(type(minimum) == "number" and minimum == math.floor(minimum)
        and minimum >= 1 and minimum <= 255, "CommandDefinitions: minimum level required")
    if facades[owner] then
        assert(ownerLevels[owner] == minimum, "CommandDefinitions: owner level changed")
        return facades[owner]
    end
    local methods = {}
    function methods.Register(def) return registerBatch({def}, owner, minimum)[1] end
    function methods.RegisterMany(list) return registerBatch(list, owner, minimum) end
    methods.RegisterFamily = methods.Register
    for _, name in ipairs({"Find", "Get", "List", "Complete", "Validate", "Format", "CanRun",
            "AssertComplete", "Count", "GetRoots"}) do
        local methodName, method = name, CD[name]
        methods[methodName] = function(...)
            if allowed(minimum) then return method(...) end
            if methodName == "List" or methodName == "Complete" or methodName == "GetRoots" then return {} end
            if methodName == "Count" then return 0 end
            if methodName == "Validate" then return false, "access unavailable" end
            if methodName == "CanRun" then return false end
            if methodName == "AssertComplete" then return false, {"access unavailable"} end
            return nil
        end
    end
    local facade = setmetatable({}, {
        __index=methods, __newindex=function() error("CommandDefinitions facade is read-only") end,
        __metatable=false,
    })
    facades[owner], ownerLevels[owner] = facade, minimum
    return facade
end
