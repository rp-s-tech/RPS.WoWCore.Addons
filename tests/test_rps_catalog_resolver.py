"""R05: book catalog embedded in Lua and the pure ResolvedSheet resolver."""
import subprocess
import sys

import lua_runtime as runtime


class RpsCatalogResolver(runtime.LuaRuntimeCase):
    def run_case(self, name):
        fixture = runtime.ROOT / "Addons/tests/fixtures/rps_catalog_resolver.lua"
        self.run_lua("ROOT=[[" + runtime.ROOT.as_posix() + "]]\n"
                     "local cases = assert(loadfile([[" + fixture.as_posix() + "]]))()\n"
                     "cases." + name + "()")

    def test_generated_catalog_is_current(self):
        script = runtime.ROOT / "Docs/Plans/WarChronicles3d6/sources/gen_lua_catalog.py"
        result = subprocess.run([sys.executable, str(script), "--check"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_catalog_counts_and_validation(self):
        self.run_case("catalog")

    def test_archetype_profiles_levels_1_5_10(self):
        self.run_case("profiles")

    def test_healer_profile_d17(self):
        self.run_case("healer_d17")

    def test_fixing_traits_set_and_cap(self):
        self.run_case("fixing_traits")

    def test_size_effects(self):
        self.run_case("sizes")

    def test_mastery_points_and_racial_bonuses(self):
        self.run_case("mastery_points")

    def test_gifted_ability_slots(self):
        self.run_case("gifted")

    def test_idempotent_recompute(self):
        self.run_case("idempotent")

    def test_validation_errors(self):
        self.run_case("validation")

    def test_derived_attacks_block_and_fate(self):
        self.run_case("derived")

    def test_no_decorative_choices(self):
        self.run_case("no_decorative_choices")
