import lua_runtime as runtime


class StarterTooltip(runtime.LuaRuntimeCase):
    def run_case(self, name):
        path = runtime.ROOT / "Addons/tests/fixtures/rps_starter_tooltip.lua"
        self.run_lua("ROOT=[[" + runtime.ROOT.as_posix() + "]]\n"
                     "local cases=assert(loadfile([[" + path.as_posix() + "]]))()\ncases." + name + "()")

    def test_carrier_lines_and_normal_items(self):
        self.run_case("lines")

    def test_rp_properties_replace_native_stats_in_place(self):
        self.run_case("inject")

    def test_without_item_class_api_only_confirmed_carriers_are_filtered(self):
        self.run_case("no_item_api")

    def test_reused_tooltip_has_no_stale_item_state(self):
        self.run_case("reuse")

    def test_comparison_preserves_items_but_removes_native_deltas(self):
        self.run_case("comparison")

    def test_unavailable_and_secret_data_are_left_to_client(self):
        self.run_case("unavailable")
