"""R04: native levels/XP, DM-only grants, level sync of the RP sheet and the «Развитие» screen."""
import lua_runtime as runtime


class RpsProgression(runtime.LuaRuntimeCase):
    def run_case(self, name):
        path = runtime.ROOT / "Addons/tests/fixtures/rps_progression.lua"
        self.run_lua("ROOT=[[" + runtime.ROOT.as_posix() + "]]\n"
                     "local cases=assert(loadfile([[" + path.as_posix() + "]]))()\ncases." + name + "()")

    def test_non_dm_xp_is_blocked(self):
        self.run_case("xp_block")

    def test_dm_grant_passes_and_is_idempotent(self):
        self.run_case("dm_grant")

    def test_multi_level_jump_applies_each_level_once(self):
        self.run_case("multi_level")

    def test_resolver_sheet_and_gifted_slots(self):
        self.run_case("resolver_gifted")

    def test_cap_at_server_level_19(self):
        self.run_case("cap")

    def test_grant_permissions_and_validation(self):
        self.run_case("permissions")

    def test_progression_payload(self):
        self.run_case("payload")

    def test_reconcile_retry_and_no_repeat(self):
        self.run_case("reconcile")

    def test_client_screen_and_slash(self):
        self.run_case("client_screen")

    def test_dm_xp_control(self):
        self.run_case("client_dm")

    def test_failed_intent_never_changes_xp(self):
        self.run_case("intent_failure")

    def test_failed_final_commit_replays_after_memory_loss(self):
        self.run_case("final_failure_reload")

    def test_process_crash_resumes_the_durable_intent(self):
        self.run_case("crash_recovery")

    def test_pending_grant_blocks_new_grants_and_survives_logout(self):
        self.run_case("pending_logout_and_serialization")

    def test_conflicting_native_state_is_not_overwritten(self):
        self.run_case("conflicting_native_state")

    def test_missing_binding_or_receipt_query_prevents_grant(self):
        self.run_case("binding_and_query_failure")

    def test_uncertain_intent_commit_is_looked_up_before_native_change(self):
        self.run_case("uncertain_intent_commit")

    def test_native_configuration_and_legacy_receipts_fail_closed(self):
        self.run_case("native_configuration_and_legacy_receipt")

    def test_client_reload_resumes_the_original_xp_request(self):
        self.run_case("client_pending_reload")
