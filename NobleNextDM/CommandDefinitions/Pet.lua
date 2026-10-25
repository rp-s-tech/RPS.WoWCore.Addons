-- Shared DM/GM pet definitions; registered once by NobleNextDM.
-- CommandDefinitions/Pet.lua — NobleNext `.pet *` (companion / спутник)
-- Источник: Custom/NobleNext/Pet/custom_pet_commands.cpp; UI — GM/Pet/Init.lua.
-- Не путать с vanilla `.pet create|learn|unlearn|level` (cs_pet.cpp).

local _, ns = ...

if not ns.CommandDefinitions or not ns.CommandDefinitions.RegisterMany then
    return
end

local MODE = "system"

ns.CommandDefinitions.RegisterMany({
    {
        path = { "pet" },
        serverPath = "pet",
        syntax = ".pet",
        description = "Справка: управление своим спутником в цели (say/emote/stay/follow/play/pos/tele).",
        args = {},
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
    },
    {
        path = { "pet", "say" },
        serverPath = "pet say",
        syntax = ".pet say <text>",
        description = "Спутник в цели произносит текст (say).",
        args = {
            { name = "text", type = "string", required = true },
        },
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".pet say Привет!" },
    },
    {
        path = { "pet", "emote" },
        serverPath = "pet emote",
        syntax = ".pet emote <text>",
        description = "Текстовый emote от спутника в цели.",
        args = {
            { name = "text", type = "string", required = true },
        },
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".pet emote машет лапой" },
    },
    {
        path = { "pet", "stay" },
        serverPath = "pet stay",
        syntax = ".pet stay",
        description = "Остановить движение спутника (stay).",
        args = {},
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
    },
    {
        path = { "pet", "follow" },
        serverPath = "pet follow",
        syntax = ".pet follow [dist] [angle]",
        description = "Спутник следует за игроком; dist по умолчанию 3 (angle принимается, в ядре не используется).",
        args = {
            { name = "dist", type = "number", required = false },
            { name = "angle", type = "number", required = false },
        },
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".pet follow", ".pet follow 2.5" },
    },
    {
        path = { "pet", "play" },
        serverPath = "pet play",
        syntax = ".pet play <emoteId> [repeat]",
        description = "Анимация спутника: без repeat однократная, с repeat постоянная. Разовые и постоянные анимации имеют разные ID.",
        args = {
            { name = "emoteId", type = "number", required = true },
            { name = "repeat", type = "number", required = false },
        },
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".pet play 1", ".pet play 378 1", ".pet play 0 1" },
    },
    {
        path = { "pet", "pos" },
        serverPath = "pet pos",
        syntax = ".pet pos <standState>",
        description = "Положение тела спутника: 0 стоит, 1 сидит, 3 спит, 7 мёртв. Это не ID анимации.",
        args = {
            { name = "standState", type = "number", required = true },
        },
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".pet pos 0", ".pet pos 1", ".pet pos 3" },
    },
    {
        path = { "pet", "tele" },
        serverPath = "pet tele",
        syntax = ".pet tele",
        description = "Телепорт спутника к позиции игрока.",
        args = {},
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
    },
})
