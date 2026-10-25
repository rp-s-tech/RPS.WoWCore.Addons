-- GM-only additions to the shared phase family; no duplicate DM definitions.
local _, ns = ...
local phaseId = { name = "phaseId", type = "string", required = true }
ns.CommandDefinitions.RegisterMany({
    {
        path = { "rps", "phase", "reload" },
        syntax = ".rps phase reload",
        description = "Перезагрузить server cache RP phases.",
        args = {}, destructive = false, console = false, responseMode = "system",
    },
    {
        path = { "rps", "pha", "set", "owner" },
        syntax = ".rps pha set owner <phase-id> <character|0>",
        description = "Короткий GM-путь передачи owner без токена force (RBAC 3048).",
        args = {
            phaseId,
            { name = "characterOrZero", type = "string", required = true },
        },
        destructive = "db", console = false, responseMode = "system",
    },
})
