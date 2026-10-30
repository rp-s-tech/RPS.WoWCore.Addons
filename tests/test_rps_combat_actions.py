"""R02: action spells and reactions separate from the ten standalone dice (ACCEPTANCE B01-B08)."""
import lua_runtime as runtime


class RpsCombatActions(runtime.LuaRuntimeCase):
    def run_case(self, name):
        path = runtime.ROOT / "Addons/tests/fixtures/rps_combat_actions.lua"
        self.run_lua("ROOT=[[" + runtime.ROOT.as_posix() + "]]\n"
                     "local cases=assert(loadfile([[" + path.as_posix() + "]]))()\ncases." + name + "()")

    def test_b01_standalone_accuracy_never_attacks(self):
        self.run_case("b01_standalone_accuracy")

    def test_b02_npc_static_threshold_and_tie(self):
        self.run_case("b02_npc_static_threshold")

    def test_b03_npc_rolled_defense_and_pvp_pending(self):
        self.run_case("b03_npc_rolled_and_pvp_pending")

    def test_b04_window_and_spell_share_one_path(self):
        self.run_case("b04_window_and_spell_share_path")

    def test_b05_two_attacks_replay_and_late_cast(self):
        self.run_case("b05_two_attacks_replay_and_carry")

    def test_b06_timeout_has_single_outcome(self):
        self.run_case("b06_timeout_single_outcome")

    def test_b07_block_and_fate_thresholds(self):
        self.run_case("b07_block_and_fate_thresholds")

    def test_b08_no_pending_and_free_dice(self):
        self.run_case("b08_no_pending_and_free_dice")

    def test_block_formula_d09_and_shield_hook(self):
        self.run_case("block_formula")

    def test_action_spells_issue_and_degrade(self):
        self.run_case("action_spells_issue_and_degrade")

    def test_map_queues_action_spells(self):
        self.run_case("map_queues_action_spells")

    def test_client_prompt_uses_perform_action(self):
        self.run_case("client_prompt_actions")
