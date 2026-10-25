-- Loaded through the NobleNextGM private extension namespace.
-- CommandDefinitions/WeatherTime.lua — NobleNext `.weather` / `.daytime` / `.setgrouptime`
-- Источник: Custom/NobleNext/Weather + Time (custom_weather_commands / custom_daytime_commands).

local _, ns = ...

if not ns.CommandDefinitions or not ns.CommandDefinitions.RegisterMany then
    return
end

local MODE = "system"

ns.CommandDefinitions.RegisterMany({
    {
        path = { "weather" },
        serverPath = "weather",
        syntax = ".weather <id|cancel> [strength 0-10] [player]",
        description = "Локальная погода: 1 солнце, 2 дождь, 3 снег, 4 буря; cancel — сброс. Без цели и в группе — всей группе.",
        args = {
            { name = "idOrCancel", type = "string", required = false },
            { name = "strength", type = "number", required = false },
            { name = "player", type = "player", required = false },
        },
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".weather 2 7", ".weather cancel", ".weather 3 5 Bob" },
    },
    {
        path = { "daytime" },
        serverPath = "daytime",
        syntax = ".daytime [id|server]",
        description = "Клиентское время суток для себя: 1–6 пресеты (раннее утро…ночь), server — серверное время. Без аргумента — справка.",
        args = {
            { name = "preset", type = "string", required = false },
        },
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".daytime 3", ".daytime server" },
    },
    {
        path = { "setgrouptime" },
        serverPath = "setgrouptime",
        syntax = ".setgrouptime [id|server]",
        description = "Клиентское время суток для группы (и себя): 1–6 пресеты, server — сброс. Без аргумента — справка.",
        args = {
            { name = "preset", type = "string", required = false },
        },
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".setgrouptime 4", ".setgrouptime server" },
    },
})
