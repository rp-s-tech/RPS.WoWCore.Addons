-- Loaded through the NobleNextGM private extension namespace.
-- CommandDefinitions/Gps.lua — каталог `.gps` (cs_misc.cpp HandleGPSCommand)
-- Legacy read-only inspector: координаты/зона/grid/vmap выбран system chat (report).

local _, ns = ...

ns.CommandDefinitions.RegisterMany({
    {
        path = { "gps" },
        serverPath = "gps",
        syntax = ".gps [player|creature|gameobject-link]",
        description = "Отчёт GPS: карта, зона, координаты, grid/cell, vmap/mmap (только чтение, system chat).",
        args = {
            { name = "targetLink", type = "string", required = false },
        },
        destructive = false,
        console = false,
        responseMode = "system",
        executable = true,
        examples = { ".gps", ".gps [Player:Name]", ".gps [Creature:123]" },
    },
})
