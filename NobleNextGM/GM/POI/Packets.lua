-- Loaded through the NobleNextGM private extension namespace.
-- GM/POI/Packets.lua
local _, ns = ...

local function splitMessage(message)
    local result = {}
    for part in (message .. "[&]"):gmatch("(.-)%[&%]") do
        table.insert(result, part)
    end
    return result
end

local function toBoolean(str)
    str = tostring(str or ""):lower()
    return str == "true" or str == "1"
end

function ns.PoiParsePacket(message)
    message = tostring(message or "")
    local tabPos = message:find("\t", 1, true)
    if tabPos then
        message = message:sub(tabPos + 1)
    end

    local info = splitMessage(message)
    local id = tonumber(info[1])
    if #info < 9 or not id then return nil end

    return {
        id = id,
        owner = info[2],
        name = info[3],
        desc = info[4],
        type = tonumber(info[5]),
        x = tonumber(info[6]),
        y = tonumber(info[7]),
        map = tonumber(info[8]),
        deleted = toBoolean(info[9]),
        ownerType = tonumber(info[10]) or 1,
        ownerGuid = tonumber(info[11]) or 0,
        iconKey = info[12] or "Misc",
        colorKey = tonumber(info[13]) or 0,
    }
end
