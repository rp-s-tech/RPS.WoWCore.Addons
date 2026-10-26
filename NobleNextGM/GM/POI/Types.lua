-- Loaded through the NobleNextGM private extension namespace.
-- GM/POI/Types.lua
local _, ns = ...

-- Категория (1–4) для C++ type; иконка задаётся отдельно через icon_key.
ns.PoiTypes = {
    { id = 1, label = "Информация",      color = "CED83E" },
    { id = 2, label = "Сюжетная точка",  color = "9389D6" },
    { id = 3, label = "Лагерь / здание", color = "38A047" },
    { id = 4, label = "Башня / опасная", color = "D35B43" },
}

-- Все иконки POI (вид на карте). legacy — sfpoi-тип для .poi create.
ns.PoiIconTypes = {
    { key = "Misc",   label = "Информация",       type = 1, legacy = 0 },
    { key = "Story",  label = "Сюжетная точка",   type = 2, legacy = 4 },
    { key = "Camp",   label = "Лагерь / стоянка", type = 3, legacy = 1 },
    { key = "House",  label = "Жилой дом",        type = 3, legacy = 2 },
    { key = "Tavern", label = "Таверна",          type = 3, legacy = 1 },
    { key = "Tower",  label = "Башня / форпост",  type = 4, legacy = 3 },
    { key = "Skull",  label = "Опасная зона",     type = 4, legacy = 3 },
}

ns.PoiOwnerTypes = {
    { id = 1, label = "Игрок" },
    { id = 2, label = "Организация" },
    { id = 3, label = "Система" },
    { id = 4, label = "NPC" },
}

ns.PoiColors = {
    [0] = { label = "Ничей",        color = "CED83E" },
    [1] = { label = "Альянс",       color = "2D6BFF" },
    [2] = { label = "Орда",         color = "D92222" },
    [3] = { label = "Нейтрал",      color = "D6C26A" },
    [4] = { label = "Общественное", color = "38A047" },
    [5] = { label = "Другое",       color = "9389D6" },
    [6] = { label = "Личный сюжет", color = "D35B43" },
}

function ns.PoiIconEntry(key)
    if not key then return ns.PoiIconTypes[1] end
    for _, entry in ipairs(ns.PoiIconTypes) do
        if entry.key == key then return entry end
    end
    return ns.PoiIconTypes[1]
end

function ns.PoiIconLabel(key)
    return ns.PoiIconEntry(key).label
end

function ns.PoiTypeLabel(poiType)
    local t = tonumber(poiType) or 1
    for _, entry in ipairs(ns.PoiTypes) do
        if entry.id == t then return entry.label end
    end
    return "Тип " .. tostring(t)
end

function ns.PoiOwnerLabel(ownerType)
    ownerType = tonumber(ownerType) or 1
    for _, entry in ipairs(ns.PoiOwnerTypes) do
        if entry.id == ownerType then return entry.label end
    end
    return "Владелец"
end

function ns.PoiOwnerDisplay(data)
    if not data then return "Владелец: ?" end

    local ownerType = tonumber(data.ownerType) or 1
    local ownerName = data.ownerName or data.owner or ""

    if ownerType == 3 then
        return "Владелец: System"
    elseif ownerType == 2 then
        return "Организация: " .. (ownerName ~= "" and ownerName or "?")
    elseif ownerType == 4 then
        return "NPC: " .. (ownerName ~= "" and ownerName or "?")
    end

    return "Игрок: " .. (ownerName ~= "" and ownerName or "?")
end

function ns.PoiColorLabel(colorKey)
    local entry = ns.PoiColors[tonumber(colorKey) or 0]
    return entry and entry.label or ns.PoiColors[0].label
end

function ns.PoiColorMarkup(entry)
    if not entry then return "" end
    return string.format("|cff%s[]|r %s", entry.color, entry.label)
end

function ns.PoiDescriptionForStorage(value)
    value = tostring(value or "")
    value = value:gsub("\r\n", "\n"):gsub("\r", "\n")
    return value:gsub("\n", "\\n")
end

function ns.PoiDescriptionForEdit(value)
    value = tostring(value or "")
    value = value:gsub("\r\n", "\n"):gsub("\r", "\n")
    return value:gsub("\\n", "\n")
end

function ns.PoiFormatDescription(value)
    value = ns.PoiDescriptionForEdit(value)
    value = value:gsub("|", "||")
    value = value:gsub("<[bB]>(.-)</[bB]>", "|cffffd100%1|r")
    return value
end

function ns.PoiColorRgb(colorKey)
    local entry = ns.PoiColors[tonumber(colorKey) or 0] or ns.PoiColors[0]
    local hex = entry.color or "CED83E"
    return tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255
end
