-- Loaded through the NobleNextGM private extension namespace.
-- CommandDefinitions/Tele.lua — каталог `.tele *` (cs_tele.cpp)
-- Vanilla only: 8 leaves. Именованные локации game_tele — НЕ `.gobject tele`.
-- `.tele` и `.tele name` — executable default-узлы с дочерними командами.

local _, ns = ...

ns.CommandDefinitions.RegisterMany({
    -- Default empty child of tele (HandleTeleCommand)
    {
        path = { "tele" },
        serverPath = "tele",
        syntax = ".tele <teleName|tele-link>",
        description = "Телепорт себя на именованную локацию game_tele (не путать с `.gobject tele`).",
        args = {
            { name = "teleName", type = "string", required = true },
        },
        destructive = false,
        console = false,
        responseMode = "system",
        executable = true,
        examples = { ".tele stormwind", ".tele [Tele:1]" },
    },
    {
        path = { "tele", "add" },
        serverPath = "tele add",
        syntax = ".tele add <name>",
        description = "Создать именованную локацию game_tele в текущей позиции.",
        args = {
            { name = "name", type = "string", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = "system",
        examples = { ".tele add myplace" },
    },
    {
        path = { "tele", "del" },
        serverPath = "tele del",
        syntax = ".tele del <teleName|tele-link>",
        description = "Удалить именованную локацию game_tele.",
        args = {
            { name = "teleName", type = "string", required = true },
        },
        destructive = "delete",
        console = true,
        responseMode = "system",
        examples = { ".tele del myplace" },
    },
    -- Default empty child of tele name (HandleTeleNameCommand); also has npc/* children
    {
        path = { "tele", "name" },
        serverPath = "tele name",
        syntax = ".tele name [player] <teleName|$home|tele-link>",
        description = "Телепорт игрока на game_tele или `$home` (homebind).",
        args = {
            { name = "player", type = "string", required = false },
            { name = "where", type = "string", required = true },
        },
        destructive = false,
        console = true,
        responseMode = "system",
        executable = true,
        examples = { ".tele name Bob stormwind", ".tele name $home" },
    },
    {
        path = { "tele", "name", "npc", "id" },
        serverPath = "tele name npc id",
        syntax = ".tele name npc id <player> <entry|creature_entry-link>",
        description = "Телепорт игрока к единственному спавну существа с данным entry.",
        args = {
            { name = "player", type = "string", required = true },
            { name = "entry", type = "entry", required = true },
        },
        destructive = false,
        console = true,
        responseMode = "system",
        examples = { ".tele name npc id Bob 31146" },
    },
    {
        path = { "tele", "name", "npc", "guid" },
        serverPath = "tele name npc guid",
        syntax = ".tele name npc guid <player> <spawnId|creature-link>",
        description = "Телепорт игрока к существу по spawn GUID.",
        args = {
            { name = "player", type = "string", required = true },
            { name = "spawnId", type = "spawnId", required = true },
        },
        destructive = false,
        console = true,
        responseMode = "system",
        examples = { ".tele name npc guid Bob 123456" },
    },
    {
        path = { "tele", "name", "npc", "name" },
        serverPath = "tele name npc name",
        syntax = ".tele name npc name <player> <creatureName...>",
        description = "Телепорт игрока к существу по LIKE имени шаблона.",
        args = {
            { name = "player", type = "string", required = true },
            { name = "creatureName", type = "string", required = true },
        },
        destructive = false,
        console = true,
        responseMode = "system",
        examples = { ".tele name npc name Bob Stormwind Guard" },
    },
    {
        path = { "tele", "group" },
        serverPath = "tele group",
        syntax = ".tele group <teleName|tele-link>",
        description = "Телепорт группы выбранного игрока на именованную локацию.",
        args = {
            { name = "teleName", type = "string", required = true },
        },
        destructive = false,
        console = false,
        responseMode = "system",
        examples = { ".tele group stormwind" },
    },
})
