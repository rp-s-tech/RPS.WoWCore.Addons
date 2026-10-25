-- Loaded through the NobleNextGM private extension namespace.
-- CommandDefinitions/_Manifest.lua — точка подключения каталогов команд
-- Ядро: Core/CommandDefinitions.lua (ns.CommandDefinitions).
-- Каталоги (GObject/Npc/Go/Tele/Gps/Lookup и др.) регистрируются через
--   ns.CommandDefinitions.Register / RegisterMany / RegisterFamily
-- и должны загружаться ПОСЛЕ этого файла (добавлять в NobleNext.toc ниже).
--
-- Файл намеренно не содержит команд: это стабильный якорь порядка загрузки toc.

local _, ns = ...

-- Гарантируем наличие API, если toc переупорядочен по ошибке.
ns.CommandDefinitions = ns.CommandDefinitions or {}
