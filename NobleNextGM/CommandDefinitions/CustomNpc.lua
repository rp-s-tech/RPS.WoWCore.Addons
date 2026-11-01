-- Loaded through the NobleNextGM private extension namespace.
-- CommandDefinitions/CustomNpc.lua — каталог `.customnpc` / `.cnpc` (cs_customnpc.cpp)
-- Основные листья: help/add/apply/list/spawn/delete/set*/clone*.
-- Не покрывает equip/unequip/model/face/race-list и прочие расширенные ветки.

local _, ns = ...

if not ns.CommandDefinitions or not ns.CommandDefinitions.RegisterMany then
    return
end

local MODE = "system"

local function cnpcAlias(tokens)
    local a = { "cnpc" }
    for i = 1, #tokens do
        a[#a + 1] = tokens[i]
    end
    return a
end

ns.CommandDefinitions.RegisterMany({
    ---------------------------------------------------------------------------
    -- help / root
    ---------------------------------------------------------------------------
    {
        path = { "customnpc" },
        aliases = {
            { "cnpc" },
        },
        serverPath = "customnpc",
        syntax = ".customnpc",
        description = "Справка по командам Custom NPC (алиас `.cnpc`).",
        args = {},
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".customnpc", ".cnpc" },
    },
    {
        path = { "customnpc", "help" },
        aliases = {
            cnpcAlias({ "help" }),
        },
        serverPath = "customnpc help",
        syntax = ".customnpc help",
        description = "Показать справку по `.customnpc` / `.cnpc`.",
        args = {},
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".customnpc help", ".cnpc help" },
    },

    ---------------------------------------------------------------------------
    -- create / apply / list / delete
    ---------------------------------------------------------------------------
    {
        path = { "customnpc", "add" },
        aliases = {
            cnpcAlias({ "add" }),
        },
        serverPath = "customnpc add",
        syntax = ".customnpc add <displayName>",
        description = "Создать пустой Custom NPC с отображаемым именем; ключ генерируется сервером.",
        args = {
            { name = "displayName", type = "string", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".cnpc add 7th Legion Infantry" },
    },
    {
        path = { "customnpc", "apply" },
        aliases = {
            cnpcAlias({ "apply" }),
        },
        serverPath = "customnpc apply",
        syntax = ".customnpc apply <variation> [key]",
        description = "Применить образ своего NPC, выделенного через `.npc select` в текущей карте и фазе. Необязательный ключ проверяет совпадение выбора.",
        args = {
            { name = "variation", type = "number", required = true },
            { name = "key", type = "string", required = false },
        },
        destructive = true,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".cnpc apply 1" },
    },
    {
        path = { "customnpc", "list" },
        aliases = {
            cnpcAlias({ "list" }),
        },
        serverPath = "customnpc list",
        syntax = ".customnpc list",
        description = "Список зарегистрированных Custom NPC (ключ, entry, owner, модели/экип/спавны).",
        args = {},
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".cnpc list" },
    },
    {
        path = { "customnpc", "delete" },
        aliases = {
            cnpcAlias({ "delete" }),
        },
        serverPath = "customnpc delete",
        syntax = ".customnpc delete <key>",
        description = "Удалить Custom NPC по ключу (и связанные данные).",
        args = {
            { name = "key", type = "string", required = true },
        },
        destructive = "delete",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".cnpc delete mykey" },
    },

    ---------------------------------------------------------------------------
    -- spawn
    ---------------------------------------------------------------------------
    {
        path = { "customnpc", "spawn" },
        aliases = {
            cnpcAlias({ "spawn" }),
        },
        serverPath = "customnpc spawn",
        syntax = ".customnpc spawn <key>",
        description = "Постоянный спавн Custom NPC по ключу в позиции игрока (пишет в БД).",
        args = {
            { name = "key", type = "string", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".cnpc spawn mykey" },
    },
    {
        path = { "customnpc", "spawn", "temp" },
        aliases = {
            cnpcAlias({ "spawn", "temp" }),
        },
        serverPath = "customnpc spawn temp",
        syntax = ".customnpc spawn temp <key>",
        description = "Временный summon Custom NPC по ключу (без постоянного спавна).",
        args = {
            { name = "key", type = "string", required = true },
        },
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".cnpc spawn temp mykey" },
    },

    ---------------------------------------------------------------------------
    -- set *
    ---------------------------------------------------------------------------
    {
        path = { "customnpc", "set", "name" },
        aliases = {
            cnpcAlias({ "set", "name" }),
        },
        serverPath = "customnpc set name",
        syntax = ".customnpc set name <key> <displayName>",
        description = "Сменить отображаемое имя Custom NPC.",
        args = {
            { name = "key", type = "string", required = true },
            { name = "displayName", type = "string", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".cnpc set name mykey 7th Legion Infantry" },
    },
    {
        path = { "customnpc", "set", "scale" },
        aliases = {
            cnpcAlias({ "set", "scale" }),
        },
        serverPath = "customnpc set scale",
        syntax = ".customnpc set scale <key> <scale> [variation]",
        description = "Установить масштаб модели Custom NPC (опционально для вариации).",
        args = {
            { name = "key", type = "string", required = true },
            { name = "scale", type = "number", required = true },
            { name = "variation", type = "number", required = false },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".cnpc set scale mykey 1.1", ".cnpc set scale mykey 1.1 1" },
    },
    {
        path = { "customnpc", "set", "displayid" },
        aliases = {
            cnpcAlias({ "set", "displayid" }),
        },
        serverPath = "customnpc set displayid",
        syntax = ".customnpc set displayid <key> <displayId> [variation]",
        description = "Установить displayId модели Custom NPC.",
        args = {
            { name = "key", type = "string", required = true },
            { name = "displayId", type = "number", required = true },
            { name = "variation", type = "number", required = false },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".cnpc set displayid mykey 12345" },
    },
    {
        path = { "customnpc", "set", "race" },
        aliases = {
            cnpcAlias({ "set", "race" }),
        },
        serverPath = "customnpc set race",
        syntax = ".customnpc set race <key> <race> [variation]",
        description = "Установить расу (outfit) Custom NPC.",
        args = {
            { name = "key", type = "string", required = true },
            { name = "race", type = "string", required = true },
            { name = "variation", type = "number", required = false },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".cnpc set race mykey human", ".cnpc set race mykey 1 1" },
    },
    {
        path = { "customnpc", "set", "gender" },
        aliases = {
            cnpcAlias({ "set", "gender" }),
        },
        serverPath = "customnpc set gender",
        syntax = ".customnpc set gender <key> <gender> [variation]",
        description = "Установить пол Custom NPC (0=male, 1=female).",
        args = {
            { name = "key", type = "string", required = true },
            { name = "gender", type = "number", required = true },
            { name = "variation", type = "number", required = false },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".cnpc set gender mykey 0", ".cnpc set gender mykey 1 1" },
    },
    {
        path = { "customnpc", "set", "subname" },
        aliases = {
            cnpcAlias({ "set", "subname" }),
        },
        serverPath = "customnpc set subname",
        syntax = ".customnpc set subname <key> <subName>",
        description = "Установить подзаголовок (subname) Custom NPC.",
        args = {
            { name = "key", type = "string", required = true },
            { name = "subName", type = "string", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".cnpc set subname mykey Quartermaster" },
    },

    ---------------------------------------------------------------------------
    -- clone *
    ---------------------------------------------------------------------------
    {
        path = { "customnpc", "clone" },
        aliases = {
            cnpcAlias({ "clone" }),
        },
        serverPath = "customnpc clone",
        syntax = ".customnpc clone <displayName>",
        description = "Клонировать внешность текущего игрока в новый Custom NPC.",
        args = {
            { name = "displayName", type = "string", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".cnpc clone My Double" },
    },
    {
        path = { "customnpc", "clone", "player" },
        aliases = {
            cnpcAlias({ "clone", "player" }),
        },
        serverPath = "customnpc clone player",
        syntax = ".customnpc clone player <player> <displayName>",
        description = "Клонировать онлайн-игрока в новый Custom NPC.",
        args = {
            { name = "player", type = "string", required = true },
            { name = "displayName", type = "string", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".cnpc clone player Alice Guard Captain" },
    },
    {
        path = { "customnpc", "clone", "target" },
        aliases = {
            cnpcAlias({ "clone", "target" }),
        },
        serverPath = "customnpc clone target",
        syntax = ".customnpc clone target <displayName>",
        description = "Клонировать выделенное существо/игрока в новый Custom NPC.",
        args = {
            { name = "displayName", type = "string", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".cnpc clone target Street Guard" },
    },
    {
        path = { "customnpc", "clone", "custom" },
        aliases = {
            cnpcAlias({ "clone", "custom" }),
        },
        serverPath = "customnpc clone custom",
        syntax = ".customnpc clone custom <sourceKey> <displayName>",
        description = "Клонировать существующий Custom NPC по ключу в новый ключ.",
        args = {
            { name = "sourceKey", type = "string", required = true },
            { name = "displayName", type = "string", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".cnpc clone custom oldkey New Guard" },
    },
    {
        path = { "customnpc", "clone", "entry" },
        aliases = {
            cnpcAlias({ "clone", "entry" }),
        },
        serverPath = "customnpc clone entry",
        syntax = ".customnpc clone entry <entry> <displayName>",
        description = "Клонировать creature_template/entry во новый Custom NPC.",
        args = {
            { name = "entry", type = "creatureEntry", required = true },
            { name = "displayName", type = "string", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".cnpc clone entry 6 Kobold Scout" },
    },
})
