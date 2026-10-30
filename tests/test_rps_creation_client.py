import unittest

import lua_runtime as runtime


class RpsCreationClient(runtime.LuaRuntimeCase):
    def run_case(self, name):
        path = runtime.ROOT / "Addons/tests/fixtures/rps_creation_client.lua"
        self.run_lua("ROOT=[[" + runtime.ROOT.as_posix() + "]]\n"
                     "local cases=assert(loadfile([[" + path.as_posix() + "]]))()\ncases." + name + "()")

    def test_open_wizard_steps_and_session_draft(self):
        self.run_case("open_and_navigate")

    def test_debounced_preview_budget_and_field_errors(self):
        self.run_case("preview_and_errors")

    def test_confirm_request_id_lock_conflict_and_timeout(self):
        self.run_case("confirm_flow")

    def test_character_frame_creation_states(self):
        self.run_case("character_frame_states")

    def test_contract_with_real_server_payloads(self):
        self.run_case("server_contract")

    def test_errors_without_request_id(self):
        self.run_case("error_routing")

    def test_missing_checklist_local_and_server(self):
        self.run_case("missing_checklist")

    def test_scope_race_locks_other_steps(self):
        self.run_case("scope_race_locking")

    def test_race_reset_button_popup_and_slash(self):
        self.run_case("race_reset")

    def test_archetype_reset_price_popup_and_scope(self):
        self.run_case("archetype_reset")


class CreationToc(unittest.TestCase):
    def test_module_files_registered_after_rps_client(self):
        toc = (runtime.ROOT / "Addons/NobleNext/NobleNext.toc").read_text(encoding="utf-8-sig").splitlines()
        state = toc.index("Modules/CharacterCreation/State.lua")
        self.assertEqual(toc[state + 1], "Modules/CharacterCreation/Wizard.lua")
        self.assertLess(toc.index("Core/RPSClient.lua"), state)
        self.assertLess(toc.index("Modules/CharacterFrame/RPS.lua"), state)


if __name__ == "__main__":
    unittest.main()
