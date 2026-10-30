import lua_runtime as runtime


class Consumables(runtime.LuaRuntimeCase):
    def run_case(self, expression):
        fixture = runtime.ROOT / "Addons/tests/fixtures/rps_consumables.lua"
        self.run_lua("ROOT=[[" + runtime.ROOT.as_posix() + "]]\n"
                     "local cases=assert(loadfile([[" + fixture.as_posix() + "]]))()\n" + expression)

    def test_resource_caps_dead_players_and_full_resources(self):
        self.run_case("cases.plan()")

    def test_confirmed_use_replay_and_target_conflict(self):
        self.run_case("cases.commit('success')")

    def test_failed_write_preserves_item_and_profile(self):
        self.run_case("cases.commit('failure')")

    def test_rp_pending_attack_blocks_use(self):
        self.run_case("cases.commit('battle')")

    def test_actor_lock_blocks_use(self):
        self.run_case("cases.commit('lock')")

    def test_native_context_rejects_out_of_range_or_phase(self):
        self.run_case("cases.commit('context')")

    def test_map_self_fallback_and_nonunit_target(self):
        self.run_case("cases.map()")

    def test_login_recovers_item_after_commit_before_removal(self):
        self.run_case("cases.recovery('login')")

    def test_use_recovers_item_after_crash_without_rehealing(self):
        self.run_case("cases.recovery('use')")

    def test_transferred_consumed_item_cannot_heal_again(self):
        self.run_case("cases.recovery('transfer')")

    def test_transfer_while_pending_uses_global_item_lock(self):
        self.run_case("cases.recovery('transfer_pending')")

    def test_guid_reused_by_different_entry_is_not_consumed(self):
        self.run_case("cases.recovery('different_entry')")
