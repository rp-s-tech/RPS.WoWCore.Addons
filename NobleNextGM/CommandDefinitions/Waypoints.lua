-- Loaded through the NobleNextGM private extension namespace.
-- CommandDefinitions/Waypoints.lua — vanilla `.wp *` (cs_wp.cpp) + NobleNext runtime waypoints
-- NobleNext: Custom/NobleNext/Waypoints/custom_waypoints_commands.cpp (wpmove/wpwalk/…).

local _, ns = ...

if not ns.CommandDefinitions or not ns.CommandDefinitions.RegisterMany then
    return
end

local MODE = "system"

ns.CommandDefinitions.RegisterMany({
    ---------------------------------------------------------------------------
    -- vanilla .wp (cs_wp.cpp)
    ---------------------------------------------------------------------------
    {
        path = { "wp", "add" },
        serverPath = "wp add",
        syntax = ".wp add [pathId]",
        description = "Добавить waypoint-ноду в позицию игрока (pathId или путь выделенного NPC / новый path).",
        args = {
            { name = "pathId", type = "number", required = false },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".wp add", ".wp add 12345" },
    },
    {
        path = { "wp", "load" },
        serverPath = "wp load",
        syntax = ".wp load <pathId>",
        description = "Назначить pathId выделенному NPC (creature_addon + WAYPOINT_MOTION_TYPE).",
        args = {
            { name = "pathId", type = "number", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".wp load 12345" },
    },
    {
        path = { "wp", "modify" },
        serverPath = "wp modify",
        syntax = ".wp modify <del|move>",
        description = "Изменить выделенный visual waypoint: del — удалить ноду, move — перенести к игроку.",
        args = {
            { name = "action", type = "choice", required = true, choices = { "del", "move" } },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".wp modify del", ".wp modify move" },
    },
    {
        path = { "wp", "unload" },
        serverPath = "wp unload",
        syntax = ".wp unload",
        description = "Снять загруженный path с выделенного NPC (БД + idle motion).",
        args = {},
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
    },
    {
        path = { "wp", "reload" },
        serverPath = "wp reload",
        syntax = ".wp reload <pathId>",
        description = "Перезагрузить waypoint path из БД в память.",
        args = {
            { name = "pathId", type = "number", required = true },
        },
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".wp reload 12345" },
    },
    {
        path = { "wp", "show" },
        serverPath = "wp show",
        syntax = ".wp show <on|off|info> [pathId]",
        description = "Визуализация path: on/off/info; pathId опционален (иначе у выделенного NPC).",
        args = {
            { name = "mode", type = "choice", required = true, choices = { "on", "off", "info" } },
            { name = "pathId", type = "number", required = false },
        },
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".wp show on", ".wp show info 12345", ".wp show off" },
    },
    {
        path = { "wp", "move" },
        serverPath = "wp move",
        syntax = ".wp move <wpId> <pathId> <moveType>",
        description = "Установить move_type точки в waypoint_data (0/1/2) и перезагрузить path.",
        args = {
            { name = "wpId", type = "number", required = true },
            { name = "pathId", type = "number", required = true },
            { name = "moveType", type = "number", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".wp move 1 12345 0" },
    },
    {
        path = { "wp", "delay" },
        serverPath = "wp delay",
        syntax = ".wp delay <wpId> <pathId> <seconds>",
        description = "Установить delay точки waypoint_data (секунды -> мс в БД).",
        args = {
            { name = "wpId", type = "number", required = true },
            { name = "pathId", type = "number", required = true },
            { name = "seconds", type = "number", required = true },
        },
        destructive = "db",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".wp delay 1 12345 5" },
    },
    {
        path = { "wp", "lookup" },
        serverPath = "wp lookup",
        syntax = ".wp lookup",
        description = "Показать точки waypoint_data для pathId выделенного NPC.",
        args = {},
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
    },

    ---------------------------------------------------------------------------
    -- NobleNext runtime waypoints (не путать с .wp *)
    ---------------------------------------------------------------------------
    {
        path = { "wpmove" },
        serverPath = "wpmove",
        syntax = ".wpmove",
        description = "NobleNext: добавить точку бега маршрута выделенного NPC в позицию игрока.",
        args = {},
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
    },
    {
        path = { "wpwalk" },
        serverPath = "wpwalk",
        syntax = ".wpwalk",
        description = "NobleNext: добавить точку шага маршрута выделенного NPC в позицию игрока.",
        args = {},
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
    },
    {
        path = { "wpwait" },
        serverPath = "wpwait",
        syntax = ".wpwait <seconds>",
        description = "NobleNext: точка ожидания на маршруте (минимум 0.5 сек).",
        args = {
            { name = "seconds", type = "number", required = true },
        },
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".wpwait 2" },
    },
    {
        path = { "wpemote" },
        serverPath = "wpemote",
        syntax = ".wpemote <emoteId> <seconds>",
        description = "NobleNext: точка ожидания с эмоцией (минимум 0.5 сек).",
        args = {
            { name = "emoteId", type = "number", required = true },
            { name = "seconds", type = "number", required = true },
        },
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".wpemote 1 3" },
    },
    {
        path = { "wpclear" },
        serverPath = "wpclear",
        syntax = ".wpclear",
        description = "NobleNext: очистить runtime-маршрут выделенного NPC.",
        args = {},
        destructive = true,
        console = false,
        responseMode = MODE,
        executable = true,
    },
    {
        path = { "wpgo" },
        serverPath = "wpgo",
        syntax = ".wpgo",
        description = "NobleNext: запустить runtime-маршрут выделенного NPC.",
        args = {},
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
    },
    {
        path = { "wpstop" },
        serverPath = "wpstop",
        syntax = ".wpstop",
        description = "NobleNext: остановить runtime-маршрут выделенного NPC.",
        args = {},
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
    },
    {
        path = { "npcsetstate" },
        serverPath = "npcsetstate",
        syntax = ".npcsetstate <standState>",
        description = "NobleNext: установить стойку (stand state) выделенного NPC.",
        args = {
            { name = "standState", type = "number", required = true },
        },
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".npcsetstate 0", ".npcsetstate 1" },
    },
})
