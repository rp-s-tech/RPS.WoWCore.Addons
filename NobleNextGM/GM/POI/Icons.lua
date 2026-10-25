-- Loaded through the NobleNextGM private extension namespace.
-- GM/POI/Icons.lua
-- Текстуры: Addons/NobleNext/Assets/POI/POI_*.tga (в путях расширение не указываем).
local _, ns = ...
ns.PoiIcons = {
    Misc   = "Interface/AddOns/NobleNext/Assets/POI/POI_Misc",
    Story  = "Interface/AddOns/NobleNext/Assets/POI/POI_Story",
    Camp   = "Interface/AddOns/NobleNext/Assets/POI/POI_Camp",
    House  = "Interface/AddOns/NobleNext/Assets/POI/POI_House",
    Tavern = "Interface/AddOns/NobleNext/Assets/POI/POI_Tavern",
    Tower  = "Interface/AddOns/NobleNext/Assets/POI/POI_Tower",
    Skull  = "Interface/AddOns/NobleNext/Assets/POI/POI_Skull",
}

ns.PoiFallbackIcons = {
    Misc   = "Interface/Icons/inv_misc_note_01",
    Story  = "Interface/Icons/inv_misc_book_09",
    Camp   = "Interface/Icons/inv_misc_tent_01",
    House  = "Interface/Icons/inv_garrison_building_storehouse",
    Tavern = "Interface/Icons/inv_drink_05",
    Tower  = "Interface/Icons/inv_misc_tower_01",
    Skull  = "Interface/Icons/ability_hunter_markedfordeath",
}

ns.PoiColorIcons = {}

function ns.PoiIconForKey(key, poiType)
    if key and ns.PoiIcons[key] then return ns.PoiIcons[key] end
    if key then
        for _, icon in ipairs(ns.PoiIconTypes or {}) do
            if icon.key == key then
                return ns.PoiIcons[icon.key] or ns.PoiIcons.Misc
            end
        end
    end
    local t = tonumber(poiType) or 1
    if t == 2 then return ns.PoiIcons.Story end
    if t == 3 then return ns.PoiIcons.Camp end
    if t == 4 then return ns.PoiIcons.Tower end
    return ns.PoiIcons.Misc
end

function ns.PoiFallbackIconForKey(key, poiType)
    if key and ns.PoiFallbackIcons[key] then return ns.PoiFallbackIcons[key] end
    if key then
        for _, icon in ipairs(ns.PoiIconTypes or {}) do
            if icon.key == key then
                return ns.PoiFallbackIcons[icon.key] or ns.PoiFallbackIcons.Misc
            end
        end
    end
    local t = tonumber(poiType) or 1
    if t == 2 then return ns.PoiFallbackIcons.Story end
    if t == 3 then return ns.PoiFallbackIcons.Camp end
    if t == 4 then return ns.PoiFallbackIcons.Tower end
    return ns.PoiFallbackIcons.Misc
end

function ns.PoiColorIcon(colorKey)
    return ns.PoiColorIcons[tonumber(colorKey) or 0]
end

function ns.PoiPinColor(poiType, colorKey)
    local colorEntry = ns.PoiColors and ns.PoiColors[tonumber(colorKey) or 0]
    if colorEntry and colorEntry.color then
        return colorEntry.color
    end

    local t = tonumber(poiType) or 1
    for _, entry in ipairs(ns.PoiTypes or {}) do
        if entry.id == t then return entry.color end
    end
    return "CED83E"
end

function ns.PoiApplyColoredIcon(texture, iconKey, poiType, colorKey)
    if not texture or not texture.SetTexture or not texture.SetVertexColor then
        return
    end

    local iconEntry = ns.PoiIconEntry(iconKey or "Misc")
    local tex = ns.PoiIconForKey(iconEntry.key, poiType or iconEntry.type)
    if not tex or not texture:SetTexture(tex) then
        texture:SetTexture(ns.PoiFallbackIconForKey(iconEntry.key, poiType or iconEntry.type))
    end

    local r, g, b = ns.PoiColorRgb(colorKey)
    texture:SetVertexColor(r, g, b, 1)
end
