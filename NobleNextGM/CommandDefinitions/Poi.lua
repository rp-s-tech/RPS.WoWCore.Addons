-- Loaded through the NobleNextGM private extension namespace.
-- CommandDefinitions/Poi.lua — каталог `.poi` (custom_poi_commands.cpp)
-- + алиас `.poilist` → `.poi list` (custom_nn_commands.cpp).

local _, ns = ...

if not ns.CommandDefinitions or not ns.CommandDefinitions.RegisterMany then
    return
end

local MODE = "system"

ns.CommandDefinitions.RegisterMany({
    ---------------------------------------------------------------------------
    -- help / root
    ---------------------------------------------------------------------------
    {
        path = { "poi" },
        serverPath = "poi",
        syntax = ".poi",
        description = "Справка по командам POI (точки интереса на карте).",
        args = {},
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".poi", ".poi help" },
    },
    {
        path = { "poi", "help" },
        serverPath = "poi help",
        syntax = ".poi help",
        description = "Показать справку по `.poi`.",
        args = {},
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".poi help" },
    },

    ---------------------------------------------------------------------------
    -- create / delete / list / sync
    ---------------------------------------------------------------------------
    {
        path = { "poi", "create" },
        serverPath = "poi create",
        syntax = ".poi create [name] [legacyType] [description] [color]",
        description = "Создать POI в позиции игрока. Короткая форма: name/type/desc/color; полная: owner type name desc color.",
        args = {
            { name = "name", type = "string", required = false },
            { name = "legacyType", type = "number", required = false },
            { name = "description", type = "string", required = false },
            { name = "color", type = "number", required = false },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = {
            ".poi create",
            ".poi create Test 2",
            ".poi create \"Горные бандиты\" 2 \"Дом у каналов\" 1",
        },
    },
    {
        path = { "poi", "delete" },
        serverPath = "poi delete",
        syntax = ".poi delete <id>",
        description = "Удалить POI по числовому id.",
        args = {
            { name = "id", type = "number", required = true },
        },
        destructive = "delete",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".poi delete 12" },
    },
    {
        path = { "poi", "list" },
        aliases = {
            { "poilist" },
        },
        serverPath = "poi list",
        syntax = ".poi list",
        description = "Список POI из БД (id, имя, map, type, владелец). Алиас `.poilist`.",
        args = {},
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".poi list", ".poilist" },
    },
    {
        path = { "poi", "sync" },
        serverPath = "poi sync",
        syntax = ".poi sync",
        description = "Отправить полный список POI клиенту (RPC sync).",
        args = {},
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".poi sync" },
    },

    ---------------------------------------------------------------------------
    -- set *
    ---------------------------------------------------------------------------
    {
        path = { "poi", "set", "name" },
        serverPath = "poi set name",
        syntax = ".poi set name <id> <name>",
        description = "Сменить название POI.",
        args = {
            { name = "id", type = "number", required = true },
            { name = "name", type = "string", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".poi set name 12 Новый пост" },
    },
    {
        path = { "poi", "set", "description" },
        aliases = {
            { "poi", "set", "des" },
        },
        serverPath = "poi set description",
        syntax = ".poi set description <id> <description>",
        description = "Сменить описание POI (алиас `.poi set des`).",
        args = {
            { name = "id", type = "number", required = true },
            { name = "description", type = "string", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".poi set description 12 Дом у каналов", ".poi set des 12 Текст" },
    },
    {
        path = { "poi", "set", "position" },
        serverPath = "poi set position",
        syntax = ".poi set position <id>",
        description = "Перенести POI в текущую позицию игрока.",
        args = {
            { name = "id", type = "number", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".poi set position 12" },
    },
    {
        path = { "poi", "set", "type" },
        serverPath = "poi set type",
        syntax = ".poi set type <id> <type>",
        description = "Установить тип POI (1–4).",
        args = {
            { name = "id", type = "number", required = true },
            { name = "type", type = "number", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".poi set type 12 2" },
    },
    {
        path = { "poi", "set", "icon" },
        serverPath = "poi set icon",
        syntax = ".poi set icon <id> <iconKey>",
        description = "Установить ключ иконки POI.",
        args = {
            { name = "id", type = "number", required = true },
            { name = "iconKey", type = "string", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".poi set icon 12 tavern" },
    },
    {
        path = { "poi", "set", "color" },
        serverPath = "poi set color",
        syntax = ".poi set color <id> <color>",
        description = "Установить цвет POI (0–6: ничей/Альянс/Орда/нейтрал/общественное/другое/сюжет).",
        args = {
            { name = "id", type = "number", required = true },
            { name = "color", type = "number", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".poi set color 12 1" },
    },
    {
        path = { "poi", "set", "apply" },
        serverPath = "poi set apply",
        syntax = ".poi set apply <id> <type> <iconKey> <color> <ownerType> <updatePosition> <owner>",
        description = "Пакетно применить type/icon/color/owner и опционально позицию.",
        args = {
            { name = "id", type = "number", required = true },
            { name = "type", type = "number", required = true },
            { name = "iconKey", type = "string", required = true },
            { name = "color", type = "number", required = true },
            { name = "ownerType", type = "number", required = true },
            { name = "updatePosition", type = "number", required = true },
            { name = "owner", type = "string", required = false },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".poi set apply 12 2 tavern 1 1 1 Alice" },
    },

    ---------------------------------------------------------------------------
    -- set owner *
    ---------------------------------------------------------------------------
    {
        path = { "poi", "set", "owner", "player" },
        serverPath = "poi set owner player",
        syntax = ".poi set owner player <id> [playerName]",
        description = "Назначить владельцем игрока (без имени — текущий / self).",
        args = {
            { name = "id", type = "number", required = true },
            { name = "playerName", type = "string", required = false },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".poi set owner player 12", ".poi set owner player 12 Alice" },
    },
    {
        path = { "poi", "set", "owner", "org" },
        serverPath = "poi set owner org",
        syntax = ".poi set owner org <id> <orgName>",
        description = "Назначить владельцем организацию.",
        args = {
            { name = "id", type = "number", required = true },
            { name = "orgName", type = "string", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".poi set owner org 12 Горные бандиты" },
    },
    {
        path = { "poi", "set", "owner", "system" },
        serverPath = "poi set owner system",
        syntax = ".poi set owner system <id> [label]",
        description = "Назначить системного владельца POI (опциональная метка).",
        args = {
            { name = "id", type = "number", required = true },
            { name = "label", type = "string", required = false },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".poi set owner system 12", ".poi set owner system 12 Сюжет" },
    },
    {
        path = { "poi", "set", "owner", "npc" },
        serverPath = "poi set owner npc",
        syntax = ".poi set owner npc <id> <npcName>",
        description = "Назначить владельцем NPC (имя/метка).",
        args = {
            { name = "id", type = "number", required = true },
            { name = "npcName", type = "string", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".poi set owner npc 12 Street Guard" },
    },
})
