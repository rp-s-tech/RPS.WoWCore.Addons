"""Exercise real Lua handlers through delayed native-commit and AIO doubles."""
import lua_runtime as runtime


class RpsCombatIntegration(runtime.LuaRuntimeCase):
    def test_attack_replay_ignores_changed_selection_and_pending_queue(self):
        self.run_case("attack_replay_before_target_checks")

    def test_reaction_replay_restores_complete_outcome_after_reload(self):
        self.run_case("reaction_replay_after_reload")

    def test_new_hit_at_zero_adds_wound_but_duplicate_does_not(self):
        self.run_case("new_hit_at_zero_and_replay")

    def run_case(self, name):
        path = runtime.ROOT / "Addons/tests/fixtures/rps_combat_integration.lua"
        self.run_lua("ROOT=[[" + runtime.ROOT.as_posix() + "]]\n"
                     "local cases=assert(loadfile([[" + path.as_posix() + "]]))()\ncases." + name + "()")

    def test_delayed_commit_failure_and_duplicate(self):
        self.run_case("commit")

    def test_actor_lock_and_target_authorization(self):
        self.run_case("permissions")

    def test_reaction_receipt_timeout_and_reload(self):
        self.run_case("reactions")

    def test_partial_cross_pool_failure(self):
        self.run_case("partial")

    def test_profile_creation_is_confirmed_before_sync(self):
        self.run_case("creation")

    def test_map_finishes_accepted_dice_and_cancels_refused_casts(self):
        self.run_case("map")

    def test_binding_failure_releases_lock(self):
        self.run_case("binding")

    def test_durable_receipt_prevents_reroll_after_reload(self):
        self.run_case("receipt")

    def test_completed_request_cache_does_not_block_gameplay(self):
        self.run_case("cache")

    def test_startup_diagnostics_and_recovery(self):
        self.run_case("startup_diagnostics")

    def test_spell_issuance_statuses_in_sync(self):
        self.run_case("spell_statuses")

    def test_learn_failed_bounded_retry(self):
        self.run_case("learn_retry")

    def test_diag_spells_command(self):
        self.run_case("diag_spells")

    def test_dropped_cast_feedback(self):
        self.run_case("cast_feedback")
