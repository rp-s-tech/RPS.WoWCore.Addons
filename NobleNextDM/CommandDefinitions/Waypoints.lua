local _, ns = ...
if not ns.CommandDefinitions or not ns.CommandDefinitions.RegisterMany then return end
ns.CommandDefinitions.RegisterMany({
    {
        path = { "wplist" }, serverPath = "wplist", syntax = ".wplist [page]",
        description = "Показать все действия маршрута выбранного НИП по страницам: бег, шаг, паузы и эмоции.",
        args = { { name = "page", type = "number", required = false } },
        destructive = false, console = false, responseMode = "system", executable = true,
    },
    {
        path = { "wpremove" }, serverPath = "wpremove", syntax = ".wpremove <point>",
        description = "Удалить действие из черновика маршрута и остановить исполнение. Для сохранения запеките маршрут.",
        args = { { name = "point", type = "number", required = true } },
        destructive = true, console = false, responseMode = "system", executable = true,
    },
    {
        path = { "wpswap" }, serverPath = "wpswap", syntax = ".wpswap <first> <second>",
        description = "Поменять два действия маршрута местами и остановить исполнение. Для сохранения запеките маршрут.",
        args = { { name = "first", type = "number", required = true }, { name = "second", type = "number", required = true } },
        destructive = true, console = false, responseMode = "system", executable = true,
    },
})
