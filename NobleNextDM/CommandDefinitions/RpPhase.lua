-- DM phase catalog; server owner/capability/RBAC checks remain authoritative.
-- CommandDefinitions/RpPhase.lua — `.rps phase` (alias `.rps phase`); BIGINT IDs как строки.

local _, ns = ...

local phaseId = { name = "phaseId", type = "string", required = true }
local spawnId = { name = "spawnId", type = "string", required = true }

ns.CommandDefinitions.RegisterMany({
    {
        path = { "rps", "phase", "help" },
        syntax = ".rps phase help",
        description = "Справка по logical RP World Maps phases.",
        args = {}, destructive = false, console = false, responseMode = "system",
    },
    {
        path = { "rps", "phase", "create" },
        syntax = ".rps phase create \"<name>\" [--global|--map <map-id>] [description]",
        description = "Создать глобальную phase (по умолчанию) или явно ограничить её одной картой.",
        args = {
            { name = "name", type = "string", required = true },
            { name = "scope", type = "choice", required = false, choices = { "--global", "--map" } },
            { name = "mapId", type = "number", required = false },
            { name = "description", type = "string", required = false },
        },
        destructive = "db", console = false, responseMode = "system",
    },
    {
        path = { "rps", "phase", "list" },
        syntax = ".rps phase list [my|--all-phases]",
        description = "Список доступных RP phases; my = свои (owner/member, включая archive); RBAC 3045 — все.",
        args = {
            { name = "scope", type = "literal", required = false, choices = { "my", "--all-phases" } },
        },
        destructive = false, console = false, responseMode = "system",
    },
    {
        path = { "rps", "phase", "info" },
        syntax = ".rps phase info <phase-id> [--all-phases]",
        description = "Информация и ACL phase.",
        args = { phaseId, { name = "all", type = "literal", required = false, choices = { "--all-phases" } } },
        destructive = false, console = false, responseMode = "system",
    },
    {
        path = { "rps", "phase", "enter" },
        syntax = ".rps phase enter <phase-id>",
        description = "Войти в logical server-authoritative context phase.",
        args = { phaseId }, destructive = false, console = false, responseMode = "structured",
        packets = { "EVENT", "CONTEXT" },
    },
    {
        path = { "rps", "phase", "leave" },
        syntax = ".rps phase leave",
        description = "Вернуться в common context (phase 0).",
        args = {}, destructive = false, console = false, responseMode = "structured",
        packets = { "EVENT", "CONTEXT" },
    },
    {
        path = { "rps", "phase", "invite" },
        syntax = ".rps phase invite <phase-id> <player> <viewer|editor|manager>",
        description = "Выдать ACL участнику; server проверяет manager role.",
        args = {
            phaseId, { name = "player", type = "string", required = true },
            { name = "role", type = "choice", required = true, choices = { "viewer", "editor", "manager" } },
        },
        destructive = "db", console = false, responseMode = "system",
    },
    {
        path = { "rps", "phase", "revoke" },
        syntax = ".rps phase revoke <phase-id> <player> confirm",
        description = "Отозвать ACL участника; требуется confirm.",
        args = {
            phaseId, { name = "player", type = "string", required = true },
            { name = "confirm", type = "literal", required = true, choices = { "confirm" } },
        },
        destructive = "db", console = false, responseMode = "system",
    },
    {
        path = { "rps", "phase", "archive" },
        syntax = ".rps phase archive <phase-id> confirm",
        description = "Soft-archive phase; Owner или staff RBAC 3045 + confirm.",
        args = { phaseId, { name = "confirm", type = "literal", required = true, choices = { "confirm" } } },
        destructive = "db", console = false, responseMode = "system",
    },
    {
        path = { "rps", "phase", "unarchive" },
        syntax = ".rps phase unarchive <phase-id> confirm",
        description = "Разархивировать soft-archive; manager/owner или staff RBAC 3045 + confirm.",
        args = { phaseId, { name = "confirm", type = "literal", required = true, choices = { "confirm" } } },
        destructive = "db", console = false, responseMode = "system",
    },

    {
        path = { "rps", "phase", "spawn", "info" },
        syntax = ".rps phase spawn info <creature|gameobject> <spawn-id> [--all-phases]",
        description = "Показать mapping spawn → RP phase.",
        args = {
            { name = "spawnType", type = "choice", required = true, choices = { "creature", "gameobject" } },
            spawnId, { name = "all", type = "literal", required = false, choices = { "--all-phases" } },
        },
        destructive = false, console = false, responseMode = "system",
    },
    {
        path = { "rps", "phase", "spawn", "assign" },
        syntax = ".rps phase spawn assign <phase-id> <creature|gameobject> <spawn-id> confirm",
        description = "Назначить spawn phase; GO group назначается atomically.",
        args = {
            phaseId, { name = "spawnType", type = "choice", required = true, choices = { "creature", "gameobject" } },
            spawnId, { name = "confirm", type = "literal", required = true, choices = { "confirm" } },
        },
        destructive = "db", console = false, responseMode = "system",
    },
    {
        path = { "rps", "phase", "spawn", "clear" },
        syntax = ".rps phase spawn clear <creature|gameobject> <spawn-id> confirm",
        description = "Снять mapping spawn с phase.",
        args = {
            { name = "spawnType", type = "choice", required = true, choices = { "creature", "gameobject" } },
            spawnId, { name = "confirm", type = "literal", required = true, choices = { "confirm" } },
        },
        destructive = "db", console = false, responseMode = "system",
    },
    {
        path = { "rps", "phase", "set", "name" },
        syntax = ".rps phase set name <phase-id> \"<name>\"",
        description = "Переименовать phase; только Owner или staff.",
        args = {
            phaseId,
            { name = "name", type = "string", required = true },
        },
        destructive = "db", console = false, responseMode = "system",
    },
    {
        path = { "rps", "phase", "set", "public" },
        syntax = ".rps phase set public <phase-id> true|false",
        description = "Публичность phase; mutate только Owner/staff.",
        args = {
            phaseId,
            { name = "value", type = "choice", required = true, choices = { "true", "false" } },
        },
        destructive = "db", console = false, responseMode = "system",
    },
    {
        path = { "rps", "phase", "set", "owner" },
        syntax = ".rps phase set owner <phase-id> <character|0> force",
        description = "Сменить owner account по имени персонажа; 0 = Server. Owner/staff + force.",
        args = {
            phaseId,
            { name = "characterOrZero", type = "string", required = true },
            { name = "force", type = "literal", required = true, choices = { "force" } },
        },
        destructive = "db", console = false, responseMode = "system",
    },

    {
        path = { "rps", "phase", "set", "role" },
        syntax = ".rps phase set role <phase-id> <character> viewer|editor|manager",
        description = "Membership role: Manager выдаёт viewer/editor; manager — только Owner/staff.",
        args = {
            phaseId,
            { name = "character", type = "string", required = true },
            { name = "role", type = "choice", required = true, choices = { "viewer", "editor", "manager" } },
        },
        destructive = "db", console = false, responseMode = "system",
    },
    {
        path = { "rps", "phase", "set", "spawn" },
        syntax = ".rps phase set spawn <phase-id>",
        description = "Сохранить текущую позицию как enter spawn фазы.",
        args = { phaseId },
        destructive = "db", console = false, responseMode = "system",
    },
    {
        path = { "rps", "phase", "set", "enter-spawn" },
        syntax = ".rps phase set enter-spawn <phase-id> true|false",
        description = "Автотелепорт на spawn при enter (если spawn задан).",
        args = {
            phaseId,
            { name = "value", type = "choice", required = true, choices = { "true", "false" } },
        },
        destructive = "db", console = false, responseMode = "system",
    },
    {
        path = { "rps", "phase", "goto" },
        syntax = ".rps phase goto <phase-id>",
        description = "Transition и телепорт на spawn фазы (spawn обязателен).",
        args = { phaseId },
        destructive = false, console = false, responseMode = "structured",
        packets = { "EVENT", "CONTEXT" },
    },
})
