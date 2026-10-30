"""DM item editor input, replay and target switching."""
import lua_runtime as runtime

class ItemEditor(runtime.LuaRuntimeCase):
    def run_case(self, name):
        fixture = runtime.ROOT / "Addons/tests/fixtures/rps_item_editor.lua"
        self.run_lua("ROOT=[[" + runtime.ROOT.as_posix() + "]]\nlocal cases=assert(loadfile([[" + fixture.as_posix() + "]]))()\ncases." + name + "()")

    def test_save_signed_fields_and_retry_preserves_draft(self):
        self.run_case("save_retry")

    def test_target_change_catalog_removal_and_integer_validation(self):
        self.run_case("target_and_catalog")

    def test_refresh_preserves_draft_and_selection(self):
        self.run_case("snapshot_and_selection")

    def test_rejected_rune_does_not_block_other_operations(self):
        self.run_case("rejected_operation")

    def test_target_switch_ignores_previous_save(self):
        self.run_case("switch_while_pending")
