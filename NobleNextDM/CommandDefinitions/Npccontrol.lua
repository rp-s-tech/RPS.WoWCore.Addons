-- Shared DM/GM army chat definitions; registered once by NobleNextDM.
-- CommandDefinitions/Npccontrol.lua — NobleNext Army (`.npccontrol` / `.deleteselected`)
-- Источник: Custom/NobleNext/Army/custom_army_commands.cpp.
-- Основной UI: /nnarmy (GM/Army).

local _, ns = ...

if not ns.CommandDefinitions or not ns.CommandDefinitions.RegisterMany then
    return
end

local MODE = "system"

ns.CommandDefinitions.RegisterMany({
    {
        path = { "npccontrol" },
        serverPath = "npccontrol",
        syntax = ".npccontrol",
        description = "Включить режим Army Controller (аура). Управление армией — через UI /nnarmy.",
        args = {},
        destructive = false,
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".npccontrol" },
    },
    {
        path = { "deleteselected" },
        serverPath = "deleteselected",
        syntax = ".deleteselected",
        description = "Удаление выделенных NPC армии — через UI /nnarmy (или AIO ArmyHandlers), не этим чат-вызовом.",
        args = {},
        destructive = "delete",
        console = false,
        responseMode = MODE,
        executable = true,
        examples = { ".deleteselected" },
    },
})
