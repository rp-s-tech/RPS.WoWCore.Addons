import re
import unittest

import lua_runtime as runtime


class RpsCombatClient(runtime.LuaRuntimeCase):
    def run_case(self, name):
        path = runtime.ROOT / "Addons/tests/fixtures/rps_combat_client.lua"
        self.run_lua("ROOT=[[" + runtime.ROOT.as_posix() + "]]\n"
                     "local cases=assert(loadfile([[" + path.as_posix() + "]]))()\ncases." + name + "()")

    def test_one_channel_and_pooled_character_sheet(self):
        self.run_case("sheet")

    def test_queue_waits_for_server_receipt_and_resync(self):
        self.run_case("prompts")

    def test_dm_target_revision_and_failed_save(self):
        self.run_case("dm")

    def test_rp_resource_projection_and_target_change(self):
        self.run_case("resources")

    def test_immediate_target_request_and_final_retry(self):
        self.run_case("target_request")

    def test_wire_guid_normalization_and_identity(self):
        self.run_case("guid_normalization")

    def test_negative_answers_ttl_and_invalidation(self):
        self.run_case("negative_cache")

    def test_character_sheet_display_states(self):
        self.run_case("sheet_states")

    def test_silent_server_falls_back_to_native(self):
        self.run_case("silent_server")


class WireGuidContract(unittest.TestCase):
    """Client and server must normalize GUIDs with the same code."""

    @staticmethod
    def extract(relative):
        text = (runtime.ROOT / relative).read_text(encoding="utf-8")
        match = re.search(r"^local WIRE_GUID_KINDS = \{.*?^local function NormalizeWireGuid\(value\)\n.*?^end\n",
                          text, re.S | re.M)
        assert match, relative
        return match.group(0)

    def test_client_and_server_blocks_are_identical(self):
        client = self.extract("Addons/NobleNext/Core/RPSClient.lua")
        server = self.extract("NobleNextLua/Modules/RPS_Combat/Init.lua")
        self.assertEqual(client, server)

    def test_server_answers_every_requested_guid(self):
        text = (runtime.ROOT / "NobleNextLua/Modules/RPS_Combat/Init.lua").read_text(encoding="utf-8")
        body = re.search(r"function H\.RequestUnitsSync\(.*?\nend\n", text, re.S).group(0)
        self.assertIn('state="unknown"', body)
        self.assertIn("NormalizeWireGuid(guidStr)", body)
