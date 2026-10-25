-- Loaded through the NobleNextGM private extension namespace.
-- CommandDefinitions/Lookup.lua — каталог `.lookup *` (cs_lookup.cpp)
-- Wave 2A: creature / object / object like / item / tele / quest (+ алиасы `.lo`).

local _, ns = ...

if not ns.CommandDefinitions or not ns.CommandDefinitions.RegisterMany then
    return
end

local MODE = "system"

ns.CommandDefinitions.RegisterMany({
    {
        path = { "lookup", "creature" },
        aliases = {
            { "lo", "creature" },
        },
        serverPath = "lookup creature",
        syntax = ".lookup creature <namePart>",
        description = "Поиск creature_template по подстроке имени (локали); ссылки Hcreature_entry.",
        args = {
            { name = "namePart", type = "string", required = true },
        },
        destructive = false,
        console = true,
        responseMode = MODE,
        executable = true,
        examples = { ".lookup creature kobold", ".lo creature wolf" },
    },
    {
        path = { "lookup", "object" },
        aliases = {
            { "lo", "object" },
            { "lo", "ob" },
        },
        serverPath = "lookup object",
        syntax = ".lookup object <namePart>",
        description = "Поиск gameobject_template по подстроке имени; ссылки Hgameobject_entry.",
        args = {
            { name = "namePart", type = "string", required = true },
        },
        destructive = false,
        console = true,
        responseMode = MODE,
        executable = true,
        examples = { ".lookup object chest", ".lo ob door" },
    },
    {
        path = { "lookup", "object", "like" },
        aliases = {
            { "lo", "object", "like" },
            { "lo", "ob", "like" },
        },
        serverPath = "lookup object like",
        syntax = ".lookup object like <token> [token...]",
        description = "Поиск GO: каждое слово должно встречаться в имени (AND, без регистра).",
        args = {
            { name = "tokens", type = "string", required = true },
        },
        destructive = false,
        console = true,
        responseMode = MODE,
        executable = true,
        examples = { ".lookup object like kobold house", ".lo ob like wmo nightelf" },
    },
    {
        path = { "lookup", "item" },
        aliases = {
            { "lo", "item" },
        },
        serverPath = "lookup item",
        syntax = ".lookup item <namePart>",
        description = "Поиск предметов по подстроке имени (ItemSparse / локали).",
        args = {
            { name = "namePart", type = "string", required = true },
        },
        destructive = false,
        console = true,
        responseMode = MODE,
        executable = true,
        examples = { ".lookup item sword", ".lo item potion" },
    },
    {
        path = { "lookup", "tele" },
        aliases = {
            { "lo", "tele" },
        },
        serverPath = "lookup tele",
        syntax = ".lookup tele <namePart>",
        description = "Поиск именованных локаций game_tele по подстроке имени.",
        args = {
            { name = "namePart", type = "string", required = true },
        },
        destructive = false,
        console = true,
        responseMode = MODE,
        executable = true,
        examples = { ".lookup tele stormwind", ".lo tele orgrimmar" },
    },
    {
        path = { "lookup", "quest" },
        aliases = {
            { "lo", "quest" },
        },
        serverPath = "lookup quest",
        syntax = ".lookup quest <namePart>",
        description = "Поиск квестов по подстроке названия; статус относительно выбранного игрока.",
        args = {
            { name = "namePart", type = "string", required = true },
        },
        destructive = false,
        console = true,
        responseMode = MODE,
        executable = true,
        examples = { ".lookup quest wolf", ".lo quest dungeon" },
    },
    {
        path = { "lookup", "rp", "phase" },
        aliases = {
            { "lo", "rp", "phase" },
        },
        serverPath = "lookup rp phase",
        syntax = ".lookup rp phase [query]",
        description = "Поиск discoverable RP phases по id/name/description/owner username (Server для owner 0).",
        args = {
            { name = "query", type = "string", required = false },
        },
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".lookup rp phase", ".lookup rp phase tavern", ".lo rp phase 42" },
    },
})
