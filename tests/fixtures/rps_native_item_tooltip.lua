local cases = {}
local prefix = ROOT .. "/Addons/NobleNext/"
local A, B = "Item-1-00000000000000AA", "Item-1-00000000000000BB"

local function setup(deferred)
    local clock, post, pre, compare, calls, registrations = 10, nil, nil, nil, {}, 0
    C_Item = nil
    GetItemInfoInstant = nil
    GetTime = function() return clock end
    CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
    issecretvalue = function(value) return type(value) == "table" and value.secret == true end
    Enum = { TooltipDataType = { Item = 0 }, TooltipDataLineType = { ItemName = 22 } }
    TooltipDataProcessor = { AllTypes = "ALL",
        AddTooltipPostCall = function(kind, fn) assert(kind == 0); post = fn end,
        AddLinePreCall = function(kind, fn) assert(kind == "ALL"); pre = fn end }
    TooltipComparisonManager = { SetItemTooltip = function() end }
    hooksecurefunc = function(object, method, fn)
        assert(object == TooltipComparisonManager and method == "SetItemTooltip"); compare = fn
    end
    local function connect()
        AIO = {
            AddHandlers = function(channel, handlers)
                assert(channel == "RPS_Combat")
                registrations = registrations + 1
                return handlers
            end,
            Handle = function(...) calls[#calls + 1] = { ... } end,
        }
    end
    AIO = nil
    if not deferred then connect() end
    local ns = {}
    assert(loadfile(prefix .. "Core/RPSClient.lua"))("NobleNext", ns)
    assert(loadfile(prefix .. "Modules/ItemTooltip/StarterOutfit.lua"))("NobleNext", ns)
    assert(loadfile(prefix .. "Modules/ItemTooltip/NativeItems.lua"))("NobleNext", ns)
    local env = { R = ns.RPSClient, ns = ns, calls = calls, connect = connect, line = pre, compare = compare }
    function env.time(value) clock = value end
    function env.registrations() return registrations end
    function env.tooltip(guid, entry)
        local t = { shown = true, refreshes = 0, shows = 0, forbidden = false }
        function t:IsShown() return self.shown end
        function t:IsForbidden() return self.forbidden end
        function t:GetPrimaryTooltipData() return self.data end
        function t:GetTooltipData() return self.data end
        function t:GetLeftLine(index) assert(index == 1); return self.label end
        function t:AddLine(text) self.lines[#self.lines + 1] = text end
        function t:Show() self.shows = self.shows + 1; self.shown = true end
        function t:reset()
            self.lines = {}
            self.label = { text = "Native name", SetText = function(label, text) label.text = text end }
        end
        function t:open(newGuid, newEntry)
            self.data = { type = 0, id = newEntry or 1800001, guid = newGuid,
                lines = { { type = 22, lineIndex = 1, leftText = "Native name" } } }
            self:reset()
            post(self, self.data)
        end
        function t:RefreshData()
            self.refreshes = self.refreshes + 1
            self:reset()
            post(self, self.data)
        end
        function t:ProcessInfo(info)
            self.data = info.tooltipData
            self.appended = info.append
            self:RefreshData()
        end
        function t:ClearLines() self.lines = {} end
        function t:process() post(self, self.data) end
        function t:HookScript(name, fn) assert(name == "OnHide"); self.onHide = fn end
        function t:hide() self.shown = false; if self.onHide then self.onHide(self) end; self.shown = true end
        t:open(guid, entry)
        return t
    end
    function env.reply(guid, metadata, state, entry, rpOnly, extra)
        local payload = { guid = guid, entry = entry or 1800001,
            state = state or "ready", metadata = metadata, rpOnly = rpOnly, rpItem = true }
        for key, value in pairs(extra or {}) do payload[key] = value end
        env.R.handlers.ItemMetadata(nil, payload)
    end
    return env
end

local function metadata(name)
    return { version = 1, revision = 1, name = name or "Именная рубаха", description = "Сшита вручную.",
        modifiers = { maxHealth = 2, maxEnergy = 1, armor = 1, speed = -1, accuracy = 1, healing = 2,
            evasion = 1, resistance = 1, ["mastery.skill"] = 1, ["mastery.knowledge"] = 2,
            ["mastery.endurance"] = 1, ["mastery.craft"] = 3, woundLimit = 1,
            healDifficulty = -1, energySpendLimit = 1, nativeArmor = 500 } }
end

function cases.render()
    local e = setup()
    local t = e.tooltip("item-1-00000000000000aa")
    assert(#e.calls == 1 and e.calls[1][1] == "RPS_Combat"
        and e.calls[1][2] == "RequestItemMetadata" and e.calls[1][3] == A)
    local m = metadata("Рубаха |cffff0000мага|r\n")
    m.description = "Текст |Hitem:1|hссылка|h\001"
    e.reply(A, m)
    assert(t.label.text == "Рубаха ||cffff0000мага||r " and t.refreshes == 1 and t.shows == 0)
    local expected = { "+2 Здоровье", "+1 Энергия",
        "+1 Броня", "-1 Скорость", "+1 Меткость", "+2 Исцеление", "+1 Уклонение", "+1 Сопротивление",
        "+1 Навык", "+2 Знание", "+1 Упорство", "+3 Ремесло", "+1 Предел ран",
        "-1 Сложность исцеления", "+1 Лимит затрат энергии", "Текст ||Hitem:1||hссылка||h " }
    assert(#t.lines == #expected)
    for i, line in ipairs(expected) do assert(t.lines[i] == line, tostring(i) .. ": " .. tostring(t.lines[i])) end
    assert(t.data.lines[1].leftText == "Native name", "native tooltip data must not be rewritten")
end

function cases.reuse()
    local e = setup()
    local t = e.tooltip(A)
    e.reply(A, metadata())
    t:open(nil)
    assert(t.label.text == "Native name" and #t.lines == 0 and #e.calls == 1)
    t:open(B)
    assert(t.label.text == "Native name" and #t.lines == 0 and #e.calls == 2)
    e.reply(B, metadata("Вторая рубаха"))
    assert(t.label.text == "Вторая рубаха")
    t:open(A)
    assert(t.label.text == "Именная рубаха" and #e.calls == 3, "a new hover asks again but shows the cached answer at once")
    t:open(A, 10061)
    assert(t.label.text == "Native name" and #t.lines == 0, "same GUID with mismatched entry is not metadata")
end

function cases.late()
    local e = setup()
    local t = e.tooltip(A)
    t:open(B)
    e.reply(A, metadata())
    assert(t.refreshes == 0 and t.label.text == "Native name")
    t.shown = false
    e.reply(B, metadata("Вторая рубаха"))
    assert(t.refreshes == 0 and not t.shown and t.shows == 0)
    t.shown = true
    t:open(B)
    assert(t.label.text == "Вторая рубаха")
    local hidden = e.tooltip("Item-1-CC")
    hidden.data.guid = A -- native primary data changed before another post callback
    e.reply("Item-1-CC", metadata("Late"))
    assert(hidden.refreshes == 0 and hidden.label.text == "Native name")
end

function cases.secret()
    local e = setup()
    local secret = { secret = true }
    for _, field in ipairs({ "guid", "type", "id", "lines" }) do
        local t = e.tooltip(nil)
        t.data.guid = A
        t.data[field] = secret
        t:process()
        assert(#e.calls == 0 and #t.lines == 0)
    end
    for _, field in ipairs({ "type", "lineIndex", "leftText", "rightText" }) do
        local t = e.tooltip(nil)
        t.data.guid = A
        t.data.lines[1][field] = secret
        t:process()
        assert(#e.calls == 0)
    end
    local forbidden = e.tooltip(nil)
    forbidden.forbidden = true
    forbidden:open(A)
    assert(#e.calls == 0)
    local t = e.tooltip(A)
    t.data.lines[1].leftText = secret
    e.reply(A, metadata())
    assert(t.refreshes == 0 and t.shows == 0)
    local shown = e.tooltip(B)
    shown.shown = secret
    e.reply(B, metadata())
    assert(shown.refreshes == 0)
end

-- One request per hover; rebuilds of the same hover and unchanged answers never refresh or blank the tooltip.
function cases.expiry()
    local e = setup()
    local t = e.tooltip(A)
    t:open(A)
    e.tooltip(A)
    assert(#e.calls == 1, "same hover and a concurrent request are deduplicated")
    e.reply(A, metadata())
    local lines = #t.lines
    e.time(100)
    t:process()
    assert(#e.calls == 1 and t.label.text == "Именная рубаха", "the cache does not expire")
    t:hide(); t:open(A)
    assert(#e.calls == 2 and t.label.text == "Именная рубаха" and #t.lines == lines, "new hover keeps the old answer visible")
    local refreshes = t.refreshes
    e.reply(A, metadata())
    assert(t.refreshes == refreshes, "an unchanged answer does not rebuild the tooltip")
    t:hide(); t:open(A)
    local m = metadata("Новая рубаха")
    m.revision = 2
    e.reply(A, m)
    assert(#e.calls == 3 and t.refreshes == refreshes + 1 and t.label.text == "Новая рубаха")
    t:hide(); t:open(A)
    t:hide(); t:open(A)
    assert(#e.calls == 4, "an unanswered request is not repeated at once")
    e.time(105)
    t:hide(); t:open(A)
    assert(#e.calls == 5, "an unanswered request is retried on a later hover")
end

function cases.validation()
    local e = setup()
    local t = e.tooltip(A)
    local wrong = metadata()
    wrong.revision = 0
    e.reply(A, wrong)
    e.reply(A, metadata(), "invalid")
    e.reply(A, metadata(), "ready", 10061)
    assert(t.refreshes == 0)
    local m = metadata()
    m.modifiers.maxHealth, m.modifiers.armor, m.modifiers.speed = 0, 0.5, { secret = true }
    e.reply(A, m)
    assert(t.refreshes == 1)
    for _, line in ipairs(t.lines) do
        assert(not line:find("Здоровье", 1, true) and not line:find("Броня", 1, true) and not line:find("Скорость", 1, true))
    end
    for _, state in ipairs({ "none", "unknown" }) do
        t:hide(); t:open(A)
        e.reply(A, nil, state, 0)
        assert(t.label.text == "Native name" and #t.lines == 0)
        local count = #e.calls
        t:open(A)
        assert(#e.calls == count, "a negative response is cached for the hover too")
    end
end

function cases.definitions()
    local e = setup()
    local guard = { definition = { modifiers = { maxHealth = 1 }, set = "guard" },
        set = { key = "guard", name = "Стража", bonuses = { { pieces = 2, modifiers = { armor = 1 } } } } }
    local function same(lines, expected)
        assert(#lines == #expected, tostring(#lines))
        for i, line in ipairs(expected) do assert(lines[i] == line, tostring(i) .. ": " .. tostring(lines[i])) end
    end
    local t = e.tooltip(A)
    e.reply(A, nil, "none", 1800001, true, guard)
    assert(t.label.text == "Native name")
    same(t.lines, { "+1 Здоровье", "Комплект: Стража", "(2) +1 Броня" })

    local named = e.tooltip(B)
    local m = metadata("Шлем")
    m.modifiers = { maxHealth = 2, armor = { secret = true } }
    e.reply(B, m, "ready", 1800001, true, guard)
    assert(named.label.text == "Шлем")
    same(named.lines, { "+3 Здоровье", "Сшита вручную.", "Комплект: Стража", "(2) +1 Броня" })

    local native = e.tooltip("Item-1-EE", 40582)
    e.reply("Item-1-EE", nil, "none", 40582, false, guard)
    same(native.lines, { "+1 Здоровье", "Комплект: Стража", "(2) +1 Броня" })
    assert(not e.R.IsNativeRoleplayItem("Item-1-EE", 40582), "native items keep their own tooltip lines")

    local plain = e.tooltip("Item-1-CC")
    e.reply("Item-1-CC", nil, "none", 1800001, false,
        { rpItem = false, definition = guard.definition, set = guard.set })
    assert(#plain.lines == 0, "definitions never apply to a stackable item")

    local broken = e.tooltip("Item-1-DD")
    e.reply("Item-1-DD", nil, "none", 1800001, true, { definition = { modifiers = { maxHealth = 0.5 } },
        set = { name = "x", bonuses = { { pieces = 0.5, modifiers = {} } } } })
    assert(#broken.lines == 0, "invalid definition and set payloads are dropped")
end

function cases.enchants()
    local e = setup()
    local t = e.tooltip(A, 40582)
    e.reply(A, nil, "none", 40582, false, { gemSlots = 3, enchants = {
        { kind = "enchant", socket = 0, id = 18005, name = "Сияние", description = "Клинок мягко светится.", modifiers = {} },
        { kind = "gem", socket = 1, id = 18501, name = "Камень жизни", description = "", modifiers = { maxHealth = 1 } },
        { kind = "gem", socket = 3, id = 18502, name = "Камень меткости", description = "", modifiers = { accuracy = 1 } } } })
    local expected = { "+1 Здоровье", "+1 Меткость", "Клинок мягко светится.",
        "Руна 1: установлена", "Руна 2: пусто", "Руна 3: установлена" }
    assert(#t.lines == #expected, tostring(#t.lines))
    for i, line in ipairs(expected) do assert(t.lines[i] == line, tostring(i) .. ": " .. tostring(t.lines[i])) end

    local empty = e.tooltip(B, 40582)
    e.reply(B, nil, "none", 40582, false, { gemSlots = 1, enchants = {} })
    assert(#empty.lines == 1 and empty.lines[1] == "Руна 1: пусто")

    local wrong = e.tooltip("Item-1-CC", 40582)
    e.reply("Item-1-CC", nil, "none", 40582, false, { gemSlots = 0, enchants = {
        { kind = "gem", socket = 0, name = "x", modifiers = { maxHealth = 1 } } } })
    assert(#wrong.lines == 0, "a gem in the enchant socket drops the list")
end

function cases.bind()
    local e = setup(true)
    assert(loadfile(prefix .. "Modules/Progression/State.lua"))("NobleNext", e.ns)
    e.tooltip(A)
    assert(#e.calls == 0 and e.registrations() == 0)
    e.connect()
    e.tooltip(A)
    assert(#e.calls == 1 and e.registrations() == 1)
    assert(e.R.handlers.ItemMetadata and e.R.handlers.Progression and e.R.handlers.SyncProfile)
    local handlers = e.R.handlers
    e.R.Bind()
    assert(e.R.handlers == handlers and e.registrations() == 1)
end

function cases.revision()
    local e = setup()
    local t = e.tooltip(A)
    for _, invalid in ipairs({ 4294967296, -1, 1.5 }) do
        local m = metadata()
        m.revision = invalid
        e.reply(A, m)
        assert(t.refreshes == 0 and t.label.text == "Native name")
    end
    local m = metadata()
    m.revision = 4294967295
    e.reply(A, m)
    assert(t.refreshes == 1 and t.label.text == "Именная рубаха")
end

function cases.carrier()
    local e = setup()
    local t = e.tooltip(A, 1900123)
    assert(not e.R.IsNativeRoleplayItem(A, 1900123))
    assert(e.line(t, { type = 0 }) == nil)
    local named = e.tooltip("Item-1-FF", 1900123)
    e.reply("Item-1-FF", metadata(), "ready", 1900123)
    assert(not e.R.IsNativeRoleplayItem("Item-1-FF", 1900123), "metadata alone does not hide native stats")
    e.reply(A, metadata(), "ready", 1900123, true)
    assert(e.R.IsNativeRoleplayItem(A, 1900123))
    assert(e.line(t, { type = 0 }) == true and e.line(t, { type = 22 }) == false)
    assert(not e.R.IsNativeRoleplayItem(A, 10061))
    assert(not e.R.IsNativeRoleplayItem(nil, 1900123))
    assert(not e.R.IsNativeRoleplayItem({ secret = true }, 1900123))
    t:open(B, 1900123)
    assert(e.line(t, { type = 0 }) == nil, "another instance has no confirmed carrier policy")
    e.reply(B, nil, "none", 1900123, true)
    assert(e.line(t, { type = 0 }) == true, "unnamed RP-only carriers use the same policy")
    t:open(nil, 1900123)
    assert(e.line(t, { type = 0 }) == nil)
    e.time(15)
    assert(e.R.IsNativeRoleplayItem(A, 1900123) and e.R.IsNativeRoleplayItem(B, 1900123), "a confirmed carrier stays known")
    t:open(A, 1900123)
    assert(e.line(t, { type = 0 }) == true)
    e.reply(A, nil, "none", 1900123, "true")
    assert(not e.R.IsNativeRoleplayItem(A, 1900123), "string is not boolean authorization")
    local ordinary = e.tooltip("Item-1-CC", 10061)
    e.reply("Item-1-CC", nil, "none", 10061, false)
    assert(e.line(ordinary, { type = 0 }) == nil)
end

function cases.carrier_comparison()
    local e = setup()
    local main, normal = e.tooltip(A, 1900123), e.tooltip(B, 10061)
    e.reply(A, metadata(), "ready", 1900123, true)
    local manager = { tooltip = main, compareInfo = { item = normal } }
    main.shoppingTooltips = { normal }
    function manager:GetComparisonItemData(displayed) return displayed.data end
    local native = normal.data
    e.compare(manager, true)
    assert(normal.refreshes == 1 and normal.appended == true and normal.data == native and normal.label.text == "Native name")
    assert(e.line(normal, { type = 0 }) == nil, "comparison retains the ordinary item's own lines")
    assert(#normal.lines == 0, "no RP summary while the equipped item is still loading")
    e.reply(B, nil, "none", 10061, false, { gemSlots = 1, enchants = {
        { kind = "enchant", socket = 0, id = 18005, name = "Сияние", description = "", modifiers = { accuracy = 2 } } } })
    e.compare(manager, true)
    local text = table.concat(normal.lines, "\n")
    assert(text:find("Если вы замените этот предмет:", 1, true), text)
    assert(text:find("+2 Здоровье", 1, true) and text:find("-1 Меткость", 1, true), text)
    assert(text:find("Гнёзда рун: -1", 1, true) and not text:find("Будет потеряно: Сияние", 1, true), text)
    local before = normal.refreshes
    main:open(nil, 10062)
    e.compare(manager, true)
    assert(normal.refreshes == before, "ordinary versus ordinary retains Blizzard comparison")
    main:open(A, 1900123)
    e.time(15)
    e.compare(manager, true)
    assert(normal.refreshes == before + 1, "a confirmed carrier keeps the RP comparison")
end

function cases.vendor()
    local e = setup()
    C_Item = { GetItemInfoInstant = function(entry) return entry, nil, nil, nil, nil, 2 end }
    local t = e.tooltip(nil, 25)
    assert(#e.calls == 1 and e.calls[1][2] == "RequestItemTemplate" and e.calls[1][3] == 25)
    local equip = {name = "Одноручное оружие: Обычное", quality = "Простое", dice = {strike = "1d8", throw = "1"}}
    e.R.handlers.ItemTemplate(nil, {entry = 25, state = "none", rpItem = true, equip = equip, noVendorValue = true})
    assert(e.R.NativeItemHasNoVendorValue(nil, 25))
    assert(t.refreshes == 1 and t.lines[1] == "Одноручное оружие: Обычное (Простое)")
    assert(t.lines[2] == "Урон: ближний бой 1d8, метание 1")
    assert(e.R.NativeItemPropertyLines(nil, 25)[2][1] == t.lines[2])
    assert(not e.R.IsNativeRoleplayItem(nil, 25), "a public template is not an owned carrier")
    t:open(A, 25)
    assert(#t.lines == 0 and e.calls[#e.calls][2] == "RequestItemMetadata")
    e.reply(A, metadata("Мой меч"), "ready", 25, false, {equip = equip})
    assert(t.label.text == "Мой меч")
    t:open(nil, 25)
    assert(t.label.text == "Native name" and #t.lines == 2, "private instance properties never leak to the vendor")
    t:open(nil, 36)
    local before = t.refreshes
    e.R.handlers.ItemTemplate(nil, {entry = 25, state = "none", rpItem = true, equip = equip})
    assert(t.refreshes == before and #t.lines == 0, "late preview cannot replace another entry")
    e.R.handlers.ItemTemplate(nil, {entry = 36, state = "ready", rpItem = true, metadata = metadata()})
    assert(t.label.text == "Native name" and #t.lines == 0)
    e.R.handlers.ItemTemplate(nil, {entry = 36, state = "none", rpItem = true, equip = equip})
    assert(#t.lines == 2)
end

function cases.signed_properties()
    local e = setup()
    local t = e.tooltip(A, 25)
    local m = {version = 1, revision = 1, name = "", description = "", modifiers = {maxHealth = 2}}
    e.reply(A, m, "ready", 25, false, {definition = {modifiers = {maxHealth = 1}}, gemSlots = 2, enchants = {
        {kind = "enchant", socket = 0, name = "Hidden preset", modifiers = {accuracy = 3, maxEnergy = -1},
            effects = {{trigger = "use", spellId = 123}}},
        {kind = "gem", socket = 1, name = "", modifiers = {accuracy = -1, ["mastery.skill"] = 2}},
        {kind = "gem", socket = 2, name = "Removed old rune", modifiers = {}}
    }})
    local text = table.concat(t.lines, "\n")
    assert(text:find("+3 Здоровье", 1, true) and text:find("-1 Энергия", 1, true))
    assert(text:find("+2 Меткость", 1, true) and text:find("+2 Навык", 1, true))
    assert(text:find("Руна 1: установлена", 1, true) and text:find("Руна 2: пусто", 1, true))
    assert(text:find("При использовании: Способность #123", 1, true))
    assert(not text:find("Hidden preset", 1, true) and not text:find("Removed old rune", 1, true))
end

function cases.changed_item()
    local e = setup()
    local t = e.tooltip(A)
    e.reply(A, metadata())
    local calls, refreshes = #e.calls, t.refreshes
    e.R.handlers.ItemChanged(nil, {guid=A,entry=1800001})
    assert(#e.calls==calls+1 and e.calls[#e.calls][2]=="RequestItemMetadata")
    local changed=metadata(); changed.revision=2; changed.modifiers.maxHealth=8
    e.reply(A, changed)
    assert(t.refreshes==refreshes+1 and t.lines[1]=="+8 Здоровье", "visible tooltip refreshes without another hover")
    t:process(); assert(#e.calls==calls+1, "refresh does not create a request loop")
    e.R.handlers.ItemChanged(nil,{guid="invalid",entry=1800001})
    assert(#e.calls==calls+1)
end
return cases
