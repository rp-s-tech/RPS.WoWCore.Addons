package.path = ROOT .. "/NobleNextLua/?.lua;" .. package.path
local C = require("Modules.RPS_Combat.00_RPS_Config")
local K = require("Modules.RPS_Combat.03_RPS_Catalog")
local V = require("Modules.RPS_Combat.04_RPS_Resolver")
local cases = {}

local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = Copy(item) end
    return out
end

local NONE = {}

-- Neutral choices: medium race whose feature is trigger-only and a trait without sheet stats.
local function Input(overrides)
    local input = {archetype = "fighter", rpLevel = 1, race = "blood_elf", racialFeature = "mana_tap",
        trait = "full_coverage", mastery = {skill = 1, endurance = 1}}
    for key, value in pairs(overrides or {}) do
        if value == NONE then input[key] = nil else input[key] = value end
    end
    return input
end

local function Sheet(overrides)
    local sheet, code, errors = V.Resolve(Input(overrides))
    assert(sheet, tostring(code) .. " " .. tostring(errors and errors[1] and errors[1].field))
    return sheet
end

local function Code(overrides)
    local sheet, code = V.Resolve(Input(overrides))
    assert(sheet == nil and code, "expected an error")
    return code
end

local function HasTrace(sheet, stat, source, op, value)
    for _, entry in ipairs(sheet.trace[stat] or {}) do
        if entry.source == source and entry.op == op and (value == nil or entry.value == value) then return entry end
    end
end

local function Passive(sheet, source)
    for _, entry in ipairs(sheet.passive) do if entry.source == source then return entry end end
end

function cases.catalog()
    local errors = K.Validate()
    assert(#errors == 0, table.concat(errors, ","))
    assert(K.CATALOG_VERSION == "lv3-book-2026-10-27.4")
    local races, defaults, features, traits = 0, 0, 0, 0
    for _, key in ipairs(K.RaceOrder) do
        local race = K.Races[key]
        if K.Available(race) then races = races + 1 end
        if race.preset == "default" then
            defaults = defaults + 1
            assert(race.bookStatus == "in_development" and race.features[1].key == key .. "_default")
        end
        assert(race.presetVersion == 1 and K.RacePresetVersion(key) == 1)
        features = features + #race.features
    end
    for _, key in ipairs(K.TraitOrder) do if K.Available(K.Traits[key]) then traits = traits + 1 end end
    assert(races == 14 and defaults == 6 and features == 22 and traits == 19 and #K.TraitOrder == 43)
    assert(table.concat(K.RaceOrder, ",") == "orc,troll,tauren,forsaken,blood_elf,ogre,goblin,pandaren,"
        .. "human,high_elf,dwarf,night_elf,draenei,gnome")
    assert(K.Races.forsaken.name == "Нежить (Отрекшийся)" and K.Races.orc.preset == "book")
    assert(K.Races.gnome.size == "small" and K.RacePresetVersion("murloc") == 0)
    assert(K.DEFAULT_RACE_PRESET.preset == "default" and K.DEFAULT_RACE_PRESET.presetVersion == 1)
    assert(K.Races.blood_elf.name == "Эльф крови" and K.Available(K.Races.pandaren))
    assert(K.Races.tauren.size == "large" and K.Races.ogre.size == "large" and K.Races.goblin.size == "small")
    assert(#K.ArchetypeOrder == 4)
    local thresholds = {0, 20, 45, 75, 115, 165, 225, 300, 390, 500}
    for level, xp in ipairs(thresholds) do
        assert(K.Xp[level].xpStart == xp and K.Xp[level].serverLevel == level + 9)
        assert(K.LevelForXp(xp) == level)
    end
    assert(K.LevelForXp(499) == 9 and K.LevelForXp(5000) == 10)
    assert(K.RpLevelFromServerLevel(10) == 1 and K.RpLevelFromServerLevel(19) == 10)
    assert(K.RpLevelFromServerLevel(9) == nil and K.ServerLevelFromRpLevel(10) == 19)
    assert(K.Weapons.two_handed_common.dice.strike == "1d12")
    assert(K.Weapons.two_handed_gunpowder.bookTypos and K.Weapons.two_handed_gunpowder.todo:match("TODO"))
    assert(K.Sizes.small.speed == 12 and K.Sizes.medium.speed == 10 and K.Sizes.large.speed == 8)
    assert(K.StepDie("1d1", 1) == "1d4" and K.StepDie("1d12", 5) == "1d20" and K.StepDie("2d6", 1) == "2d6")
    local fixing = 0
    for _, key in ipairs(K.TraitOrder) do if K.Traits[key].fixing then fixing = fixing + 1 end end
    assert(fixing == 4)
end

-- Independent transcription of catalog_archetypes.json at levels 1/5/10.
local PROFILES = {
    defender = {[1] = {20, 8, 0, -1, 2, 1, 0}, [5] = {29, 12, 0, 0, 2, 1, 2}, [10] = {40, 18, 2, 1, 4, 3, 4}},
    fighter = {[1] = {15, 10, 2, 0, 1, -1, 0}, [5] = {21, 15, 2, 0, 1, 0, 2}, [10] = {30, 22, 4, 1, 3, 2, 4}},
    healer = {[1] = {10, 12, -1, 2, 0, 1, 0}, [5] = {15, 18, 0, 2, 0, 1, 2}, [10] = {22, 27, 1, 4, 2, 3, 4}},
    caster = {[1] = {10, 14, 1, 0, -1, 2, 0}, [5] = {14, 23, 1, 0, 0, 2, 2}, [10] = {20, 34, 3, 1, 2, 4, 4}},
}
local FIELDS = {"maxHealth", "maxEnergy", "accuracy", "healing", "evasion", "resistance", "abilitySlots"}

function cases.profiles()
    for arch, levels in pairs(PROFILES) do
        for level, expected in pairs(levels) do
            local sheet = Sheet({archetype = arch, rpLevel = level})
            for i, field in ipairs(FIELDS) do
                assert(sheet[field] == expected[i], arch .. ":" .. level .. ":" .. field .. "=" .. tostring(sheet[field]))
            end
            assert(sheet.speed == 10 and sheet.armor == 0 and sheet.woundLimit == 3 and sheet.healDifficulty == 8)
            assert(sheet.energySpendLimit == 6 and sheet.size == "medium")
            assert(sheet.serverLevel == level + 9 and sheet.version == K.CATALOG_VERSION)
            assert(HasTrace(sheet, "accuracy", "archetype:" .. arch, "base", expected[3]))
        end
    end
    -- Catalog and the live config agree on every archetype value 1..10.
    for _, arch in ipairs(K.ArchetypeOrder) do
        local cfg = C.Archetypes[arch]
        for level, row in ipairs(K.Archetypes[arch].levels) do
            assert(cfg.health[level] == row.maxHealth and cfg.energy[level] == row.maxEnergy, arch .. level)
            for _, stat in ipairs({"accuracy", "healing", "evasion", "resistance"}) do
                assert(cfg.stats[stat][level] == row[stat], arch .. ":" .. level .. ":" .. stat)
            end
        end
    end
end

function cases.healer_d17()
    local stats = C.Archetypes.healer.stats
    assert(stats.evasion[1] == 0 and stats.resistance[1] == 1)
    assert(stats.evasion[10] == 2 and stats.resistance[10] == 3)
    local feature = K.Archetypes.healer.features[1]
    assert(#K.Archetypes.healer.features == 1 and feature.key == "healing_magic" and feature.name == "Целебные чары")
    local sheet = Sheet({archetype = "healer", rpLevel = 1})
    assert(sheet.evasion == 0 and sheet.resistance == 1)
    local innate
    for _, attack in ipairs(sheet.attacks) do if attack.hand == "innate" then innate = attack end end
    assert(innate and innate.canHeal == true and innate.healDieStep == 1 and innate.energyCost == 1)
end

function cases.fixing_traits()
    local fighter = Sheet({archetype = "fighter", rpLevel = 10, trait = "combat_experience"})
    assert(fighter.accuracy == 2, fighter.accuracy)
    assert(HasTrace(fighter, "accuracy", "archetype:fighter", "base", 4))
    assert(HasTrace(fighter, "accuracy", "trait:combat_experience", "set", 2))
    assert(HasTrace(fighter, "accuracy", "trait:combat_experience", "cap", 2).applied == false)
    local boosted = Sheet({archetype = "fighter", rpLevel = 10, trait = "combat_experience",
        extraModifiers = {{source = "gm:test", op = "add", target = "accuracy", value = 1}}})
    assert(boosted.accuracy == 2 and HasTrace(boosted, "accuracy", "trait:combat_experience", "cap", 2).applied == true)
    -- Small size +1 evasion is cut by the cap; an armor penalty still lowers it.
    local goblin = Sheet({archetype = "caster", race = "goblin", racialFeature = "cheating", trait = "cobra_reflexes"})
    assert(goblin.evasion == 2)
    local armored = Sheet({archetype = "caster", trait = "cobra_reflexes", equipment = {armor = {key = "armor_light"}}})
    assert(armored.evasion == 1 and armored.armor == 2)
    assert(Sheet({archetype = "healer", rpLevel = 10, trait = "natural_healer"}).healing == 2)
    assert(Sheet({archetype = "fighter", trait = "natural_healer"}).healing == 2)
    local magic = Sheet({archetype = "caster", rpLevel = 10, racialFeature = "arcane_affinity",
        trait = "magic_ward"})
    assert(magic.resistance == 2 and HasTrace(magic, "resistance", "race:blood_elf:arcane_affinity", "add", 1))
    assert(Code({trait = "combat_experience", extraModifiers = {{source = "gm", op = "set", target = "accuracy",
        value = 3}}}) == "conflicting_set")
end

function cases.sizes()
    local goblin = Sheet({race = "goblin", racialFeature = "cheating"})
    assert(goblin.size == "small" and goblin.speed == 12)
    assert(goblin.evasion == 2 and goblin.maxHealth == 13 and goblin.resistance == -2)
    assert(#goblin.trace.speed == 1, "size speed must not be added twice")
    assert(Sheet({race = "goblin", racialFeature = "time_is_money"}).speed == 14)
    local tauren = Sheet({race = "tauren", racialFeature = "hardiness"})
    assert(tauren.size == "large" and tauren.speed == 8 and tauren.evasion == 0)
    assert(tauren.resistance == 0 and tauren.maxHealth == 15 + 2 + 1)
    local grown = Sheet({race = "goblin", racialFeature = "cheating", trait = "size_matters"})
    assert(grown.size == "medium" and grown.speed == 10 and grown.evasion == 1 and grown.maxHealth == 15)
    assert(HasTrace(grown, "size", "trait:size_matters", "set", "medium"))
    local medium = Sheet({trait = "size_matters"})
    assert(medium.size == "medium" and #medium.skipped == 1)
    -- "Закалка" lowers the total armor/shield speed penalty by 1.
    local loaded = Sheet({race = "tauren", racialFeature = "hardiness", equipment = {armor = {key = "armor_heavy"},
        mainHand = {key = "one_handed_common"}, offHand = {key = "shield_large"}}})
    assert(loaded.speed == 8 - 2 - 2 + 1 and loaded.evasion == 0 - 2 - 2 and loaded.armor == 4)
    assert(Sheet({race = "pandaren", racialFeature = "liquid_courage"}).speed == 11)
end

function cases.mastery_points()
    assert(Code({race = "tauren", racialFeature = "ancestral_traditions"}) == "mastery_points_mismatch")
    local tauren = Sheet({race = "tauren", racialFeature = "ancestral_traditions", mastery = {craft = 3}})
    assert(tauren.mastery.craft == 3 and tauren.mastery.skill == 0 and tauren.masteryPoints == 3)
    assert(HasTrace(tauren, "masteryPoints", "race:tauren:ancestral_traditions", "add", 1))
    assert(Code({race = "tauren", racialFeature = "hardiness", mastery = {craft = 3}}) == "mastery_points_mismatch")
    assert(Code({mastery = {skill = 1}}) == "mastery_points_mismatch")
    assert(Code({mastery = {skill = 3, craft = -1}}) == "invalid_mastery")
    assert(Code({mastery = {skill = 1, persistence = 1}}) == "unknown_mastery")
    local orc = Sheet({race = "orc", racialFeature = "dominance"})
    assert(orc.mastery.endurance == 2 and HasTrace(orc, "mastery.endurance", "race:orc:dominance", "add", 1))
    local ogre = Sheet({race = "ogre", racialFeature = "two_heads_better"})
    assert(ogre.mastery.knowledge == 1 and ogre.maxHealth == 15 + 2 + 2 and ogre.maxEnergy == 12)
    assert(#Passive(ogre, "race:ogre:two_heads_better").mechanics > 0)
    assert(Sheet({race = "pandaren", racialFeature = "gourmet"}).mastery.craft == 1)
end

function cases.gifted()
    for _, arch in ipairs(K.ArchetypeOrder) do
        for level = 1, 10 do
            assert(Sheet({archetype = arch, rpLevel = level}).abilitySlots == K.Archetypes[arch].levels[level].abilitySlots)
        end
    end
    local expected = {0, 1, 1, 2, 2, 3, 3, 4, 4, 4}
    for level, slots in ipairs(expected) do
        local sheet = Sheet({rpLevel = level, trait = "gifted"})
        assert(sheet.abilitySlots == slots, level .. ":" .. sheet.abilitySlots)
        assert(sheet.abilitySlotList[1].unlockLevel == 2 and sheet.abilitySlotList[4].cost == 6)
    end
    local plain = Sheet({rpLevel = 3})
    assert(plain.abilitySlotList[1].unlockLevel == 3 and plain.abilitySlotList[1].open and not plain.abilitySlotList[2].open)
end

function cases.idempotent()
    local input = Input({rpLevel = 5, trait = "mighty_build", race = "goblin", racialFeature = "time_is_money",
        equipment = {armor = {key = "armor_light"}, mainHand = {key = "two_handed_common", quality = "quality"}},
        extraModifiers = {{source = "gm:1", op = "add", target = "maxEnergy", value = 2}}})
    local before = Copy(input)
    local first = assert(V.Resolve(input))
    local second = assert(V.Resolve(input))
    assert(Equal(first, second) and Equal(input, before))
    assert(first.maxHealth == 21 - 2 + 5 and first.maxEnergy == 17 and first.speed == 12 + 2 - 1)
    assert(HasTrace(first, "maxHealth", "trait:mighty_build", "add", 5).perLevel == true)
    first.maxHealth = 999
    assert(V.Resolve(input).maxHealth == 24)
end

function cases.validation()
    assert(Code({archetype = "paladin"}) == "unknown_archetype")
    assert(Code({rpLevel = 0}) == "invalid_level" and Code({rpLevel = 11}) == "invalid_level")
    assert(Code({rpLevel = 1.5}) == "invalid_level")
    assert(Sheet({rpLevel = NONE, serverLevel = 19}).rpLevel == 10)
    assert(Code({rpLevel = NONE, serverLevel = 9}) == "invalid_level")
    assert(Code({race = "dragon"}) == "unknown_race")
    assert(Code({race = "human", racialFeature = NONE}) == "racial_feature_required")
    assert(Code({race = "human", racialFeature = "gnome_default"}) == "racial_feature_not_of_race")
    -- Default preset: no mechanics, the book size only, listed as a passive placeholder.
    local human = Sheet({race = "human", racialFeature = "human_default"})
    assert(human.size == "medium" and human.speed == 10 and Passive(human, "race:human:human_default"))
    local gnome = Sheet({race = "gnome", racialFeature = "gnome_default"})
    assert(gnome.size == "small" and gnome.speed == 12 and gnome.evasion == 2)
    assert(Code({race = "orc", racialFeature = "regeneration"}) == "racial_feature_not_of_race")
    assert(Code({racialFeature = "laser_eyes"}) == "unknown_racial_feature")
    assert(Code({racialFeature = false}) == "unknown_racial_feature")
    assert(Code({trait = NONE}) == "trait_required")
    assert(Code({trait = NONE, traits = {"executioner", "executioner"}}) == "trait_duplicate")
    assert(Code({trait = NONE, traits = {"executioner", "lucky"}}) == "too_many_traits")
    assert(Code({trait = "battering_ram"}) == "trait_unavailable")
    assert(Code({trait = "no_such"}) == "unknown_trait")
    assert(Code({trait = "expert"}) == "trait_choice_required")
    assert(Code({trait = "expert", traitChoice = "magic"}) == "invalid_trait_choice")
    local expert = Sheet({trait = "expert", traitChoice = "craft"})
    assert(Passive(expert, "trait:expert").mechanics[1].target == "mastery.craft.threshold_step")
    assert(Code({equipment = {mainHand = {key = "two_handed_common"}, offHand = {key = "shield_small"}}})
        == "hands_conflict")
    assert(Code({equipment = {mainHand = {key = "shield_small"}}}) == "slot_mismatch")
    assert(Code({equipment = {offHand = {key = "two_handed_reach"}}}) == "slot_mismatch")
    assert(Code({equipment = {armor = {key = "one_handed_common"}}}) == "slot_mismatch")
    assert(Code({equipment = {back = {key = "armor_light"}}}) == "slot_mismatch")
    assert(Code({equipment = {mainHand = {key = "laser"}}}) == "unknown_item")
    assert(Code({equipment = {mainHand = {key = "one_handed_common", quality = "epic"}}}) == "invalid_quality")
    assert(Code({extraModifiers = {{source = "gm", op = "mul", target = "accuracy", value = 2}}}) == "invalid_modifier")
    assert(Code({extraModifiers = {{source = "gm", op = "add", target = "luck", value = 2}}}) == "invalid_modifier")
    assert(select(2, V.Resolve(nil)) == "invalid_input")
    local _, _, errors = V.Resolve({archetype = "x", rpLevel = 99, race = "orc", racialFeature = "berserk",
        trait = "battering_ram", mastery = {}})
    assert(#errors >= 4)
end

function cases.derived()
    local fighter = Sheet({equipment = {mainHand = {key = "one_handed_throwing"}}})
    assert(fighter.damageBonus.strike == 1 and fighter.damageBonus.throw == 1 and fighter.damageBonus.shot == 1)
    local strike, throw
    for _, a in ipairs(fighter.attacks) do
        if a.item == "one_handed_throwing" and a.mode == "strike" then strike = a end
        if a.item == "one_handed_throwing" and a.mode == "throw" then throw = a end
    end
    assert(strike.dice == "1d6" and strike.bonus == 1 and throw.range == 10 and throw.bonus == 1)
    local crafter = Sheet({mastery = {craft = 2}, equipment = {mainHand = {key = "two_handed_common"}}})
    assert(crafter.damageBonus.anyWeapon == 1 and crafter.attacks[2].dice == "1d12" and crafter.attacks[2].bonus == 1)
    local defender = Sheet({archetype = "defender", equipment = {mainHand = {key = "one_handed_common"}}})
    assert(defender.damageBonus.strike == 0 and defender.attacks[2].bonus == 0)
    assert(Passive(defender, "archetype:defender:brawler"))
    local caster = Sheet({archetype = "caster", mastery = {knowledge = 2},
        equipment = {mainHand = {key = "one_handed_magic"}}})
    local innate, wand
    for _, a in ipairs(caster.attacks) do
        if a.hand == "innate" then innate = a end
        if a.item == "one_handed_magic" and a.mode == "magic" then wand = a end
    end
    assert(innate.dice == "1d4" and innate.max == 2 and wand.dice == "1d6" and wand.energyCost == 1 and not wand.canHeal)
    -- D09 (book): no shield 1 + Resistance + Armor; shield die + Resistance + quality.
    local bare = Sheet({})
    assert(bare.block.flat == 0 and bare.block.base == 1 and bare.block.resistance == -1 and bare.block.armor == 0)
    assert(Sheet({rpLevel = 10}).block.flat == 3 and Sheet({rpLevel = 10}).block.die == nil)
    assert(Sheet({rpLevel = 10, equipment = {armor = {key = "armor_heavy"}}}).block.flat == 1 + 2 + 4)
    local weak = Sheet({equipment = {offHand = {key = "shield_small"}}})
    assert(weak.block.die == "1d4" and weak.block.flat == -1 and weak.block.armor == nil)
    local plated = Sheet({rpLevel = 10, equipment = {armor = {key = "armor_light"}, offHand = {key = "shield_small", quality = "poor"}}})
    assert(plated.block.flat == 2 - 1 and plated.block.quality == -1)
    local meat = Sheet({race = "ogre", racialFeature = "meat_shield"})
    assert(meat.block.die == nil and meat.block.flat == 1 + 0 + 0)
    assert(Passive(meat, "race:ogre:meat_shield").key == "meat_shield")
    local shield = Sheet({rpLevel = 10, equipment = {offHand = {key = "shield_medium", quality = "quality"}}})
    assert(shield.block.die == "1d6" and shield.block.flat == 3)
    assert(Sheet({equipment = {offHand = {key = "shield_large"}}}).block.fullBlockCost == 4)
    local ogre = Sheet({race = "ogre", racialFeature = "meat_shield", equipment = {offHand = {key = "shield_small"}}})
    assert(ogre.block.die == "1d6" and ogre.block.flat == 0)
    local lucky = Sheet({rpLevel = 7, trait = "fortunes_favorite"})
    assert(lucky.fateDie.die == "1d12" and lucky.fateDie.minResult == 8 and lucky.fateDie.deathSave == false)
    assert(Sheet({}).fateDie.die == "1d6")
    assert(Sheet({trait = "combo"}).energySpendLimit == 8)
    local hardy = Sheet({trait = "tenacity"})
    assert(hardy.woundLimit == 4 and hardy.extra.deathSaveBonus == 1)
    assert(Sheet({race = "forsaken", racialFeature = "restless_dead"}).woundLimit == 4)
    assert(Sheet({race = "troll", racialFeature = "berserk"}).armor == -2)
    assert(Sheet({race = "orc", racialFeature = "blood_fury"}).healDifficulty == 10)
    assert(Passive(Sheet({trait = "bodyguard"}), "trait:bodyguard").key == "bodyguard")
end

-- Every selectable race feature and general trait changes the sheet or is listed as passive.
function cases.no_decorative_choices()
    local baseline = Sheet({})
    local function Changed(sheet, source)
        if Passive(sheet, source) then return true end
        for _, entries in pairs(sheet.trace) do
            for _, entry in ipairs(entries) do if entry.source == source then return true end end
        end
        return false
    end
    for _, raceKey in ipairs(K.RaceOrder) do
        local race = K.Races[raceKey]
        if K.Available(race) then
            for _, feature in ipairs(race.features) do
                local mastery = feature.key == "ancestral_traditions" and {skill = 1, endurance = 1, craft = 1} or nil
                local sheet = Sheet({race = raceKey, racialFeature = feature.key, mastery = mastery})
                assert(Changed(sheet, "race:" .. raceKey .. ":" .. feature.key), feature.key)
            end
        end
    end
    for _, key in ipairs(K.TraitOrder) do
        if K.Available(K.Traits[key]) then
            local sheet = Sheet({trait = key, traitChoice = K.Traits[key].choice and "skill" or nil})
            assert(Changed(sheet, "trait:" .. key), key)
        end
    end
    assert(not Changed(baseline, "trait:executioner"))
end

return cases
