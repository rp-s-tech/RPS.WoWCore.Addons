"""Native instance properties, effective sheets and confirmed staff edits."""
import lua_runtime as runtime


class NativeItems(runtime.LuaRuntimeCase):
    def run_case(self, name):
        fixture = runtime.ROOT / "Addons/tests/fixtures/rps_native_items.lua"
        self.run_lua("ROOT=[[" + runtime.ROOT.as_posix() + "]]\n"
                     "local cases=assert(loadfile([[" + fixture.as_posix() + "]]))()\ncases." + name + "()")

    def test_equipment_bonus_never_accumulates_or_enters_profile_save(self):
        self.run_case("overlay")

    def test_caps_still_apply_after_equipment(self):
        self.run_case("caps")

    def test_damage_survives_unequip_and_profile_commit(self):
        self.run_case("damage")

    def test_metadata_read_checks_ownership_and_repairs_confirmed_memory(self):
        self.run_case("read")

    def test_editor_waits_for_commit_and_replays_after_lost_memory(self):
        self.run_case("editor")

    def test_editor_rejects_failure_conflict_and_stale_revision(self):
        self.run_case("failure")

    def test_equipment_recovers_after_lost_commit_callback_without_poll_queries(self):
        self.run_case("recovery")

    def test_equip_and_unequip_push_only_changed_snapshots(self):
        self.run_case("poll")

    def test_modified_round_budget_survives_save_and_unequip(self):
        self.run_case("budget")

    def test_entry_properties_and_set_thresholds_follow_current_equipment(self):
        self.run_case("sets")

    def test_invalid_definitions_are_skipped_and_reported(self):
        self.run_case("definitions_validation")

    def test_enchant_and_grade_gem_slots_apply_to_any_single_item(self):
        self.run_case("enchants")

    def test_staff_enchant_gem_grade_validation_and_state(self):
        self.run_case("enchant_staff")

    def test_hand_items_follow_design_document_types_and_dice(self):
        self.run_case("weapons")

    def test_all_starter_weapons_have_matching_vendor_and_owned_dice(self):
        self.run_case("vendor")

    def test_server_item_text_and_catalog_follow_client_glyph_policy(self):
        import runpy
        policy = runpy.run_path(str(runtime.ROOT / "Addons/tools/check_ui_text.py"))
        for name in ("07_RPS_Items.lua", "03_RPS_Catalog.lua"):
            path = runtime.ROOT / "NobleNextLua/Modules/RPS_Combat" / name
            with self.subTest(source=name):
                self.assertEqual(policy["check_file"](path), [])

    def test_properties_and_runes_replace_legacy_signed_modifiers(self):
        self.run_case("property_overrides")

    def test_numeric_editor_confirms_and_replays_exact_intent_after_transfer(self):
        self.run_case("property_editor")
