"""R03/R06 server: creation options, preview, confirm, starter kit, legacy and staff reconfigure."""
import lua_runtime as runtime


class RpsCreationServer(runtime.LuaRuntimeCase):
    def run_case(self, name):
        path = runtime.ROOT / "Addons/tests/fixtures/rps_creation_server.lua"
        self.run_lua("ROOT=[[" + runtime.ROOT.as_posix() + "]]\n"
                     "local cases=assert(loadfile([[" + path.as_posix() + "]]))()\ncases." + name + "()")

    def test_c01_options_and_states(self):
        self.run_case("options")

    def test_c04_server_validation(self):
        self.run_case("validation")

    def test_c02_preview_does_not_persist(self):
        self.run_case("preview_not_persisting")

    def test_c03_confirm_persists_and_reloads(self):
        self.run_case("confirm_persists")

    def test_c03_confirm_creates_missing_profile_first(self):
        self.run_case("new_player_without_profile")

    def test_c06_idempotent_request_id(self):
        self.run_case("idempotent_request")

    def test_c06_revision_conflict_and_failed_commit(self):
        self.run_case("revision_conflict")

    def test_e01_starter_kit_once(self):
        self.run_case("starter_kit")

    def test_c07_legacy_profile_kept(self):
        self.run_case("legacy_migration")

    def test_c08_reconfigure_staff_only(self):
        self.run_case("reconfigure_staff_only")

    def test_c05_racial_free_mastery_point(self):
        self.run_case("racial_free_point")

    def test_preview_lists_missing_fields(self):
        self.run_case("preview_missing")

    def test_d23_default_race_preset(self):
        self.run_case("default_race_preset")

    def test_d23_staff_race_reset(self):
        self.run_case("race_reset_staff")

    def test_d23_player_race_reset_after_preset_update(self):
        self.run_case("race_reset_player")

    def test_player_archetype_reset_free_then_paid(self):
        self.run_case("archetype_reset_paid")

    def test_creation_schema_missing_keeps_combat(self):
        self.run_case("schema_unavailable")
