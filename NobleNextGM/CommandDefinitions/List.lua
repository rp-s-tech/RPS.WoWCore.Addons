-- Loaded through the NobleNextGM private extension namespace.
-- CommandDefinitions/List.lua — каталог `.list *` (cs_list.cpp)
-- Wave: creature / object / item (+ auras). Кормят те же chat-кнопки, что near/lookup.

local _, ns = ...

if not ns.CommandDefinitions or not ns.CommandDefinitions.RegisterMany then
    return
end

local MODE = "system"

ns.CommandDefinitions.RegisterMany({
    {
        path = { "list", "creature" },
        serverPath = "list creature",
        syntax = ".list creature <entry|creature_entry-link> [count]",
        description = "Список спавнов creature по entry (ближайшие к игроку; по умолчанию 10). Ссылки Hcreature.",
        args = {
            { name = "entry", type = "creatureEntry", required = true },
            { name = "count", type = "number", required = false },
        },
        destructive = false,
        console = true,
        responseMode = MODE,
        executable = true,
        examples = { ".list creature 6", ".list creature 6 25" },
    },
    {
        path = { "list", "object" },
        serverPath = "list object",
        syntax = ".list object <entry|gameobject_entry-link> [count]",
        description = "Список спавнов gameobject по entry (ближайшие к игроку; по умолчанию 10). Ссылки Hgameobject.",
        args = {
            { name = "entry", type = "entry", required = true },
            { name = "count", type = "number", required = false },
        },
        destructive = false,
        console = true,
        responseMode = MODE,
        executable = true,
        examples = { ".list object 179908", ".list object 179908 20" },
    },
    {
        path = { "list", "item" },
        serverPath = "list item",
        syntax = ".list item <item|item-link> [count]",
        description = "Где встречается предмет (инвентарь/банк/почта и т.п.; лимит по умолчанию 10).",
        args = {
            { name = "item", type = "item", required = true },
            { name = "count", type = "number", required = false },
        },
        destructive = false,
        console = true,
        responseMode = MODE,
        executable = true,
        examples = { ".list item 6948", ".list item [Hitem:6948] 20" },
    },
    {
        path = { "list", "auras" },
        serverPath = "list auras",
        syntax = ".list auras",
        description = "Список всех аур выделенной цели.",
        args = {},
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".list auras" },
    },
    {
        path = { "list", "auras", "id" },
        serverPath = "list auras id",
        syntax = ".list auras id <spellId>",
        description = "Ауры цели с данным spellId.",
        args = {
            { name = "spellId", type = "number", required = true },
        },
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".list auras id 17800" },
    },
    {
        path = { "list", "auras", "name" },
        serverPath = "list auras name",
        syntax = ".list auras name <namePart>",
        description = "Ауры цели по подстроке имени заклинания.",
        args = {
            { name = "namePart", type = "string", required = true },
        },
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".list auras name shield" },
    },
})
