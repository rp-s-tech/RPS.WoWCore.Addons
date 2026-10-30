"""Execute the server-side TZ foundation with Lua and deterministic data doubles."""
import lua_runtime as runtime


class RpsCombatFoundation(runtime.LuaRuntimeCase):
    def run_case(self, name):
        fixture = runtime.ROOT / "Addons/tests/fixtures/rps_combat_foundation.lua"
        self.run_lua("ROOT=[[" + runtime.ROOT.as_posix() + "]]\n"
                     "local cases = assert(loadfile([[" + fixture.as_posix() + "]]))()\n"
                     "cases." + name + "()")

    def test_all_216_rolls(self):
        self.run_case("rolls")

    def test_dice_validation_and_limits(self):
        self.run_case("dice")

    def test_atomic_registry_reload(self):
        self.run_case("registry")

    def test_partial_spell_diagnostics(self):
        self.run_case("spell_diagnostics")

    def test_exact_ids_and_numeric_json(self):
        self.run_case("codec")

    def test_profile_resources_and_opaque_fields(self):
        self.run_case("players")

    def test_npc_cascade_and_runtime_isolation(self):
        self.run_case("npcs")

    def test_npc_cache_reload_failure(self):
        self.run_case("reload")

    def test_energy_budget_and_fate(self):
        self.run_case("budget")

    def test_damage_wounds_and_death_boundaries(self):
        self.run_case("damage")

    def test_defense_ties_block_and_magic(self):
        self.run_case("defense")

    def test_runtime_npc_state_restores_without_baseline(self):
        self.run_case("runtime_restore")
