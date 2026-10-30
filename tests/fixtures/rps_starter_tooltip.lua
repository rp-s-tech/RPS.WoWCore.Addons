local cases = {}
local file = ROOT .. "/Addons/NobleNext/Modules/ItemTooltip/StarterOutfit.lua"
local CLASSES = { [25] = 2, [10061] = 15, [40582] = 4 }
for id = 1800001, 1800011 do CLASSES[id] = 4 end

local client
local function R_injected(_, tooltip) return client.itemTooltipInjected[tooltip] end
local function setup(R)
    client = R
    Enum = { TooltipDataType = { Item = 0, Unit = 2 }, TooltipDataLineType = {
        None = 0, ItemName = 22, ItemBinding = 20, EquipSlot = 21,
        FlavorText = 37, ErrorLine = 41, DisabledLine = 42,
        UsageRequirement = 43, SellPrice = 11, ItemLevel = 31, ItemEnchantmentPermanent = 15,
    } }
    C_Item = { GetItemInfoInstant = function(id)
        local classID = CLASSES[id]
        if classID then return id, "", "", "", 0, classID, 0 end
    end }
    local callbacks = {}
    TooltipDataProcessor = { AllTypes = "ALL", AddLinePreCall = function(kind, fn)
        assert(kind == "ALL")
        callbacks.line = fn
    end }
    TooltipComparisonManager = { SetItemTooltip = function() end }
    hooksecurefunc = function(object, key, fn)
        assert(object == TooltipComparisonManager and key == "SetItemTooltip")
        callbacks.compare = fn
    end
    issecretvalue = function(value) return type(value) == "table" and value.secret == true end
    assert(loadfile(file))("NobleNext", { RPSClient = R })
    return callbacks
end

local function tooltip(id, kind)
    local t = { info = { tooltipData = { id = id, type = kind or 0, guid = "Item-1-AA" } }, rebuilds = 0,
        clears = 0, lines = {}, CompareHeader = { shown = false, Show = function(self) self.shown = true end } }
    function t:GetProcessingTooltipInfo() return self.info end
    function t:ClearLines() self.clears = self.clears + 1; self.lines = {}; self.CompareHeader.shown = false end
    function t:AddLine(text) self.lines[#self.lines + 1] = text end
    function t:ProcessInfo(info)
        self.rebuilds = self.rebuilds + 1
        self.info = info
    end
    return t
end

function cases.lines()
    local cb = setup()
    for _, id in ipairs({ 25, 40582, 1800001, 1800009, 1800011 }) do
        local t = tooltip(id)
        assert(cb.line(t, { type = 0, leftText = "999 Armor" }) == true)
        assert(cb.line(t, { type = 0, leftText = "Durability 4 / 10" }) == true)
        assert(cb.line(t, { type = 31 }) == true)
        assert(cb.line(t, { type = 15 }) == true, "enchant stats are already in the RP total")
        assert(cb.line(t, { type = 20 }) == true, "binding is hidden: RP equipment stays tradable")
        for _, kind in ipairs({ 22, 21, 37, 41, 42, 43, 11 }) do
            assert(cb.line(t, { type = kind }) == false)
        end
    end
    for _, id in ipairs({ 10061, 1799999 }) do
        assert(cb.line(tooltip(id), { type = 0, leftText = "999 Armor" }) == nil)
    end
    assert(cb.line(tooltip(1800001, 2), { type = 0 }) == nil)
end

function cases.inject()
    local asked = {}
    local cb = setup({ NativeItemPropertyLines = function(guid, id)
        asked[#asked + 1] = guid .. ":" .. id
        if id == 40582 then return { { "+1 Здоровье", 1, 1, 1, true }, { "Гнездо 1: пусто" } } end
    end })
    local t = tooltip(40582)
    for _, kind in ipairs({ 22, 20, 21, 0, 0, 15 }) do cb.line(t, { type = kind }) end
    assert(#t.lines == 2 and t.lines[1] == "+1 Здоровье" and t.lines[2] == "Гнездо 1: пусто")
    assert(#asked == 1 and asked[1] == "Item-1-AA:40582", "one insertion per pass")
    cb.line(t, { type = 22 })
    cb.line(t, { type = 21 })
    assert(#t.lines == 2, "no insertion until a line follows the equip slot")
    cb.line(t, { type = 37 })
    assert(#t.lines == 4 and #asked == 2, "a new pass inserts again before the next visible line")
    assert(R_injected(cb, t) == true, "the pass flag tells NativeItems not to append the same lines")
    t.info = { tooltipData = { id = 40582, type = 0, guid = "Item-1-AA" } } -- a refresh brings a new data table
    for _, kind in ipairs({ 22, 21, 0 }) do cb.line(t, { type = kind }) end
    assert(R_injected(cb, t) == true and #t.lines == 6)
    cb.line(t, { type = 22 })
    assert(R_injected(cb, t) == nil, "a new pass resets the flag until the lines are inserted again")
    local unknown = tooltip(1800001)
    for _, kind in ipairs({ 22, 21, 0 }) do cb.line(unknown, { type = kind }) end
    assert(#unknown.lines == 0, "metadata still loading leaves the tail fallback to NativeItems")
    assert(R_injected(cb, unknown) == nil)
end

function cases.reuse()
    local cb = setup()
    local t = tooltip(1800001)
    assert(cb.line(t, { type = 0 }) == true)
    t.info.tooltipData.id = 10061
    assert(cb.line(t, { type = 0 }) == nil)
    t.info.tooltipData = nil
    assert(cb.line(t, { type = 0 }) == nil)
    t.info = nil
    assert(cb.line(t, { type = 0 }) == nil)
    assert(cb.line({}, { type = 0 }) == nil)
end

function cases.comparison()
    local cb = setup({ NativeItemComparisonLines = function(hovered, equipped)
        return { { "Если вы замените этот предмет:" }, { "+1 Здоровье" } }
    end })
    local main, first, second = tooltip(1800001), tooltip(10061), tooltip(1800002)
    main.shoppingTooltips = { first, second }
    local manager = { tooltip = main, compareInfo = { item = first } }
    function manager:GetSecondaryItem() return second end
    function manager:GetComparisonItemData(displayed) return displayed.info.tooltipData end
    local original = first.info.tooltipData
    first.lines = { "native delta" }
    cb.compare(manager, true)
    assert(first.rebuilds == 1 and first.clears == 1 and first.info.tooltipData == original and first.info.append == true)
    assert(first.CompareHeader.shown, "ClearLines hides the header; it is shown again")
    assert(#first.lines == 3 and first.lines[1] == " " and first.lines[3] == "+1 Здоровье", "native deltas are dropped")
    cb.compare(manager, false)
    assert(second.rebuilds == 1)
    main.info.tooltipData.id = 10061
    cb.compare(manager, true)
    assert(first.rebuilds == 1, "non-equipment on both sides keeps the Blizzard tooltip")
    cb.compare(manager, false)
    assert(second.rebuilds == 2)
    manager.compareInfo.item = nil
    cb.compare(manager, true)
    assert(first.rebuilds == 1)
    second.info.tooltipData = nil
    cb.compare(manager, false)
    assert(second.rebuilds == 2)
    cb.compare({}, true)
end

function cases.unavailable()
    local cb = setup()
    local t = tooltip({ secret = true })
    assert(cb.line(t, { type = 0 }) == nil)
    t.info.tooltipData = { id = 1800001, type = { secret = true } }
    assert(cb.line(t, { type = 0 }) == nil)
    t.info.tooltipData = { id = 1800001, type = 0 }
    assert(cb.line(t, { type = { secret = true } }) == nil)
    C_Item = nil
    TooltipDataProcessor = nil
    assert(loadfile(file))("NobleNext", {})
    Enum = nil
    assert(loadfile(file))("NobleNext", {})
end

function cases.no_item_api()
    local cb = setup()
    C_Item = nil
    assert(cb.line(tooltip(1800001), { type = 0 }) == nil, "without class info only confirmed RP carriers are filtered")
end

return cases
