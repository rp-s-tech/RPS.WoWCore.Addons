local _, ns = ...
local R = ns.RPSClient
local processor = TooltipDataProcessor
local itemType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
local nameType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemName
if not R or not processor or not processor.AddTooltipPostCall or itemType == nil then return end

local unpack = unpack or table.unpack
-- Cached instances never expire; each new hover asks the server once and keeps showing the last answer meanwhile.
local RETRY = 5
local cache, pending = {}, {}
local watched = setmetatable({}, { __mode = "k" })
local sessions = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local stats = {
    { "maxHealth", "health" }, { "maxEnergy", "energy" }, { "armor", "armor" }, { "speed", "speed" },
    { "accuracy", "accuracy" }, { "healing", "healing" }, { "evasion", "evasion" }, { "resistance", "resistance" },
    { "mastery.skill", "skill" }, { "mastery.knowledge", "knowledge" },
    { "mastery.endurance", "endurance" }, { "mastery.craft", "craft" },
    { "woundLimit", nil, "Предел ран" }, { "healDifficulty", nil, "Сложность исцеления" },
    { "energySpendLimit", nil, "Лимит затрат энергии" },
}

local function secret(value) return issecretvalue and issecretvalue(value) end
local function integer(value, maximum)
    return not secret(value) and type(value) == "number" and value == value
        and math.abs(value) <= (maximum or 2147483647) and value % 1 == 0
end
local function guidKey(value)
    if secret(value) or type(value) ~= "string" or not R.NormalizeGuid then return end
    local guid = R.NormalizeGuid(value)
    if not guid then return end
    local kind, tail = guid:match("^(%a+)%-(.+)$")
    if kind and kind:lower() == "item" then return "Item-" .. tail end
end
local function safeText(value)
    if secret(value) or type(value) ~= "string" or #value > 4096 then return end
    return (value:gsub("%c", " "):gsub("|", "||"))
end

-- Shared by the native line/comparison filter; template links never establish RP identity.
function R.IsNativeRoleplayItem(guid, entry)
    if not integer(entry) then return false end
    local key = guidKey(guid)
    local known = key and cache[key]
    return known ~= nil and known.entry == entry and known.rpOnly == true
end

local function templateKey(entry)
    if not integer(entry) or entry < 1 then return end
    local getInfo = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    local class = getInfo and select(6, getInfo(entry))
    if not secret(class) and (class == 2 or class == 4) then return "Template:" .. entry end
end

local function itemData(data)
    if secret(data) or type(data) ~= "table" or secret(data.type) or data.type ~= itemType
        or not integer(data.id) or secret(data.lines) or type(data.lines) ~= "table" then return end
    if secret(data.guid) then return end
    local guid = guidKey(data.guid) or (data.guid == nil and templateKey(data.id))
    if not guid then return end
    for _, line in ipairs(data.lines) do
        if secret(line) or type(line) ~= "table" or secret(line.type) or secret(line.lineIndex)
            or secret(line.leftText) or secret(line.rightText) then return end
    end
    return guid
end

local function primaryData(tooltip)
    if tooltip.GetPrimaryTooltipData then return tooltip:GetPrimaryTooltipData() end
    if tooltip.GetTooltipData then return tooltip:GetTooltipData() end
end

-- Sums only integer values of known keys; anything else in a payload is ignored.
local function sums(sources)
    local values = {}
    for index, stat in ipairs(stats) do
        local value = 0
        for _, modifiers in ipairs(sources) do
            local part = modifiers[stat[1]]
            if integer(part) then value = value + part end
        end
        values[index] = value
    end
    return values
end

local function statLabel(stat)
    return safeText(stat[3] or R.GetLocalizedStatName(stat[2])) or stat[1]
end

local function statLines(sources, prefix)
    local lines = {}
    for index, value in ipairs(sums(sources)) do
        if value ~= 0 then
            lines[#lines + 1] = (prefix or "") .. string.format("%+d", value) .. " " .. statLabel(stats[index])
        end
    end
    return lines
end

local function modifierTable(value)
    if secret(value) or type(value) ~= "table" then return end
    for key, number in pairs(value) do
        if secret(key) or type(key) ~= "string" or not integer(number, 1000) then return end
    end
    return value
end

local function setData(value)
    if secret(value) or type(value) ~= "table" or secret(value.bonuses) or type(value.bonuses) ~= "table" then return end
    local bonuses = {}
    for index, bonus in ipairs(value.bonuses) do
        if index > 18 or secret(bonus) or type(bonus) ~= "table" or not integer(bonus.pieces, 18) then return end
        local modifiers = modifierTable(bonus.modifiers)
        if not modifiers then return end
        bonuses[#bonuses + 1] = { pieces = bonus.pieces, modifiers = modifiers }
    end
    return { name = safeText(value.name) or "", bonuses = bonuses }
end

local EFFECT_NAMES = { equip = "При надевании", use = "При использовании", proc = "При срабатывании" }
local function effectList(value)
    local out = {}
    if value == nil then return out end
    if secret(value) or type(value) ~= "table" then return out end
    for index, effect in ipairs(value) do
        if index > 3 or secret(effect) or type(effect) ~= "table" or secret(effect.trigger)
            or not EFFECT_NAMES[effect.trigger] or not integer(effect.spellId) or effect.spellId < 1 then return {} end
        out[#out + 1] = { trigger = effect.trigger, spellId = effect.spellId }
    end
    return out
end

-- Socket 0 contributes item properties, slots 1..3 contribute runes.
local function enchantList(value)
    if secret(value) or type(value) ~= "table" then return end
    local list = {}
    for index, entry in ipairs(value) do
        if index > 4 or secret(entry) or type(entry) ~= "table" or not integer(entry.socket, 3) or entry.socket < 0
            or secret(entry.kind) or entry.kind ~= (entry.socket == 0 and "enchant" or "gem") then return end
        local modifiers = modifierTable(entry.modifiers)
        if not modifiers then return end
        list[#list + 1] = { socket = entry.socket, name = safeText(entry.name) or "",
            description = safeText(entry.description) or "", modifiers = modifiers, effects = effectList(entry.effects) }
    end
    return list
end

local MODES = { { "strike", "ближний бой" }, { "throw", "метание" }, { "shot", "выстрел" }, { "magic", "магия" } }
local function diceText(value)
    if secret(value) or type(value) ~= "string" or #value > 16 or not (value:match("^%d+d%d+[+-]?%d*$")
        or value:match("^%-?%d+$")) then return end
    return value
end

-- Design-document type of a weapon or shield with its own dice (character bonuses are not included).
local function equipData(value)
    if secret(value) or type(value) ~= "table" then return end
    local name, quality = safeText(value.name), safeText(value.quality)
    if not name or name == "" then return end
    local dice = {}
    if not secret(value.dice) and type(value.dice) == "table" then
        for _, mode in ipairs(MODES) do dice[mode[1]] = diceText(value.dice[mode[1]]) end
    end
    return { name = name, quality = quality or "", block = diceText(value.block), dice = dice }
end

local function equipLines(equip)
    local lines = { { equip.name .. (equip.quality ~= "" and " (" .. equip.quality .. ")" or ""), 1, 0.82, 0, true } }
    local parts = {}
    for _, mode in ipairs(MODES) do
        if equip.dice[mode[1]] then parts[#parts + 1] = mode[2] .. " " .. equip.dice[mode[1]] end
    end
    if #parts > 0 then lines[#lines + 1] = { "Урон: " .. table.concat(parts, ", "), 1, 1, 1, true } end
    if equip.block then lines[#lines + 1] = { "Блок: " .. equip.block .. " + Сопротивление", 1, 1, 1, true } end
    return lines
end

local function sources(known)
    local list = { known.definition or {}, known.metadata and known.metadata.modifiers or {} }
    for _, enchant in ipairs(known.enchants) do list[#list + 1] = enchant.modifiers end
    return list
end

local function fresh(guid, entry)
    local key = guid or templateKey(entry)
    local known = key and cache[key]
    if known and known.entry == entry then return known end
end

local function signature(value)
    if type(value) ~= "table" then return tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    local parts = {}
    for _, key in ipairs(keys) do
        local item = value[key]
        if item == nil then item = value[tonumber(key)] end
        parts[#parts + 1] = key .. "=" .. signature(item)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- Lines that take the place of native stats: { text, r, g, b, wrap }.
local function propertyLines(known)
    local lines = known.equip and equipLines(known.equip) or {}
    for index, value in ipairs(sums(sources(known))) do
        if value ~= 0 then
            local red = value < 0
            lines[#lines + 1] = { string.format("%+d", value) .. " " .. statLabel(stats[index]),
                1, red and 0.1 or 1, red and 0.1 or 1, true }
        end
    end
    local bySocket = {}
    for _, enchant in ipairs(known.enchants) do bySocket[enchant.socket] = enchant end
    -- Numeric enchant contributions are already included in the total; keep only nonnumeric flavor.
    if bySocket[0] and bySocket[0].description ~= "" then lines[#lines + 1] = { bySocket[0].description, 0.1, 1, 0.1, true } end
    for socket = 1, known.gemSlots do
        local gem = bySocket[socket]
        local installed = gem and (next(gem.modifiers) ~= nil or #gem.effects > 0)
        if installed then lines[#lines + 1] = { "Руна " .. socket .. ": установлена", 1, 1, 1, false }
        else lines[#lines + 1] = { "Руна " .. socket .. ": пусто", 0.5, 0.5, 0.5, false } end
    end
    for _, enchant in ipairs(known.enchants) do
        for _, effect in ipairs(enchant.effects) do
            local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(effect.spellId)
            name = safeText(name) or ("Способность #" .. effect.spellId)
            lines[#lines + 1] = { EFFECT_NAMES[effect.trigger] .. ": " .. name, 0.1, 1, 0.1, true }
        end
    end
    return lines
end

-- Used by the native line filter to insert RP properties where native stats would be.
-- nil means the instance is unknown yet; the metadata reply refreshes the tooltip.
function R.NativeItemPropertyLines(guid, entry)
    local known = integer(entry) and fresh(guidKey(guid), entry)
    if known then return propertyLines(known) end
end

function R.NativeItemHasNoVendorValue(guid, entry)
    local known = integer(entry) and fresh(guidKey(guid), entry)
    return known ~= nil and known.noVendorValue == true
end

-- RP replacement summary for the comparison tooltip; nil while either side is still loading.
function R.NativeItemComparisonLines(hovered, equipped)
    if secret(hovered) or secret(equipped) or type(hovered) ~= "table" or type(equipped) ~= "table"
        or not integer(hovered.id) or not integer(equipped.id) then return end
    local new, old = fresh(guidKey(hovered.guid), hovered.id), fresh(guidKey(equipped.guid), equipped.id)
    if not new or not old then return end
    local lines, gained, lost = {}, sums(sources(new)), sums(sources(old))
    for index, stat in ipairs(stats) do
        local delta = gained[index] - lost[index]
        if delta ~= 0 then
            lines[#lines + 1] = { string.format("%+d", delta) .. " " .. statLabel(stat),
                delta > 0 and 0.1 or 1, delta > 0 and 1 or 0.1, 0.1, true }
        end
    end
    local slots = new.gemSlots - old.gemSlots
    if slots ~= 0 then
        lines[#lines + 1] = { "Гнёзда рун: " .. string.format("%+d", slots), slots > 0 and 0.1 or 1, slots > 0 and 1 or 0.1, 0.1, true }
    end
    local retained = {}
    for _, enchant in ipairs(new.enchants) do
        for _, effect in ipairs(enchant.effects) do retained[effect.trigger .. ":" .. effect.spellId] = true end
    end
    for _, enchant in ipairs(old.enchants) do
        for _, effect in ipairs(enchant.effects) do
            local key = effect.trigger .. ":" .. effect.spellId
            if not retained[key] then
                local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(effect.spellId)
                lines[#lines + 1] = { "Будет потеряно: " .. (safeText(name) or ("Способность #" .. effect.spellId)), 1, 0.1, 0.1, true }
                retained[key] = true
            end
        end
    end
    if #lines == 0 then return { { "Ролевые характеристики не изменятся.", 0.5, 0.5, 0.5, true } } end
    table.insert(lines, 1, { "Если вы замените этот предмет:", 1, 0.82, 0, true })
    return lines
end

local function render(tooltip, data, known)
    local metadata = known.metadata or { name = "", description = "", modifiers = {} }
    local name = safeText(metadata.name)
    if name and name ~= "" and nameType ~= nil then
        for _, line in ipairs(data.lines) do
            if line.type == nameType and integer(line.lineIndex) and line.lineIndex > 0 then
                local label = tooltip.GetLeftLine and tooltip:GetLeftLine(line.lineIndex)
                if label and label.SetText then label:SetText(name) end
                break
            end
        end
    end
    if not (R.itemTooltipInjected and R.itemTooltipInjected[tooltip]) then
        for _, line in ipairs(propertyLines(known)) do tooltip:AddLine(unpack(line)) end
    end
    local description = safeText(metadata.description)
    if description and description ~= "" then tooltip:AddLine(description, 0.85, 0.85, 0.85, true) end
    if known.set then
        tooltip:AddLine("Комплект: " .. (known.set.name ~= "" and known.set.name or "без названия"), 1, 0.82, 0)
        for _, bonus in ipairs(known.set.bonuses) do
            for _, line in ipairs(statLines({ bonus.modifiers }, "(" .. bonus.pieces .. ") ")) do
                tooltip:AddLine(line, 1, 0.82, 0, true)
            end
        end
    end
end

local function request(guid, entry)
    local now = GetTime()
    local waiting = pending[guid]
    if waiting and waiting.entry == entry and now - waiting.at < RETRY then return end
    if not R.Bind() then return end
    pending[guid] = { at = now, entry = entry }
    local template = guid:sub(1, 9) == "Template:"
    if not R.Send(template and "RequestItemTemplate" or "RequestItemMetadata", template and entry or guid) then
        pending[guid] = nil
    end
end

local function forget(tooltip) sessions[tooltip] = nil end

processor.AddTooltipPostCall(itemType, function(tooltip, data)
    watched[tooltip] = nil
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local guid = itemData(data)
    if not guid then return end
    watched[tooltip] = guid
    if not hooked[tooltip] and tooltip.HookScript then
        hooked[tooltip] = true
        tooltip:HookScript("OnHide", forget)
    end
    -- Rebuilds of the same hover (comparison refresh, RefreshData) reuse the answer instead of asking again.
    if sessions[tooltip] ~= guid then
        sessions[tooltip] = guid
        request(guid, data.id)
    end
    local known = cache[guid]
    if known and known.entry == data.id and (known.metadata or known.definition or known.set or known.equip
        or #known.enchants > 0 or known.gemSlots > 0) then render(tooltip, data, known) end
end)

local function ItemMetadata(_, payload, template)
    if secret(payload) or type(payload) ~= "table" then return end
    local guid
    if template then guid = templateKey(payload.entry) else guid = guidKey(payload.guid) end
    if not guid or not pending[guid] or not integer(payload.entry) or secret(payload.state) then return end
    local entry = pending[guid].entry
    if payload.entry ~= 0 and payload.entry ~= entry then return end
    if payload.state ~= "ready" and payload.state ~= "none" and payload.state ~= "unknown" then return end
    local metadata
    if payload.state == "ready" then
        if template then return end -- Template replies never carry private instance properties.
        metadata = payload.metadata
        if payload.entry ~= entry or secret(metadata) or type(metadata) ~= "table"
            or secret(metadata.version) or metadata.version ~= 1
            or not integer(metadata.revision, 4294967295) or metadata.revision < 1
            or secret(metadata.modifiers) or type(metadata.modifiers) ~= "table" then return end
    end
    pending[guid] = nil
    local matches = payload.entry == entry
    local rpOnly = matches and not secret(payload.rpOnly) and payload.rpOnly == true
    local definition, set, enchants, gemSlots, equip
    if matches and not secret(payload.rpItem) and payload.rpItem == true then
        equip = equipData(payload.equip)
        definition = not secret(payload.definition) and type(payload.definition) == "table"
            and modifierTable(payload.definition.modifiers) or nil
        set = setData(payload.set)
        enchants = enchantList(payload.enchants)
        gemSlots = integer(payload.gemSlots, 3) and payload.gemSlots >= 0 and payload.gemSlots or 0
    end
    local known = { entry = entry, metadata = metadata, rpOnly = rpOnly, definition = definition, set = set,
        noVendorValue = matches and not secret(payload.noVendorValue) and payload.noVendorValue == true,
        enchants = enchants or {}, gemSlots = gemSlots or 0, equip = equip }
    known.signature = signature(known)
    local previous = cache[guid]
    cache[guid] = known
    if previous and previous.signature == known.signature then return end
    for tooltip, expected in pairs(watched) do
        if expected == guid and not (tooltip.IsForbidden and tooltip:IsForbidden()) then
            local shown = tooltip.IsShown and tooltip:IsShown()
            local data = primaryData(tooltip)
            -- Comparison tooltips have no getter to refresh; the comparison manager rebuilds them itself.
            local comparing = tooltip.CompareHeader and tooltip.CompareHeader.IsShown and tooltip.CompareHeader:IsShown()
            if not secret(shown) and shown and not comparing and itemData(data) == guid and data.id == entry then
                -- Reuse the native getter/line lifecycle; never Show a hidden or reused tooltip.
                if tooltip.RefreshData then tooltip:RefreshData()
                elseif tooltip.RebuildFromTooltipInfo then tooltip:RebuildFromTooltipInfo() end
            end
        end
    end
end

local attached
local function attach()
    if R.handlers and attached ~= R.handlers then
        R.handlers.ItemMetadata = ItemMetadata
        R.handlers.ItemTemplate = function(player, payload) ItemMetadata(player, payload, true) end
        R.handlers.ItemChanged = function(_, payload)
            if secret(payload) or type(payload) ~= "table" then return end
            local guid = guidKey(payload.guid)
            if not guid or not integer(payload.entry) or payload.entry < 1 then return end
            pending[guid] = nil
            request(guid, payload.entry)
        end
        attached = R.handlers
    end
end
local bind = R.Bind
function R.Bind()
    local ok = bind()
    attach()
    return ok
end
attach()
