import lua_runtime as runtime


class NativeItemTooltip(runtime.LuaRuntimeCase):
    def run_case(self, name):
        path = runtime.ROOT / "Addons/tests/fixtures/rps_native_item_tooltip.lua"
        self.run_lua("ROOT=[[" + runtime.ROOT.as_posix() + "]]\n"
                     "local cases=assert(loadfile([[" + path.as_posix() + "]]))()\ncases." + name + "()")

    def test_exact_instance_name_and_russian_stats(self):
        self.run_case("render")

    def test_template_links_and_reused_tooltip_never_inherit_metadata(self):
        self.run_case("reuse")

    def test_late_reply_does_not_show_hidden_or_replace_other_instance(self):
        self.run_case("late")

    def test_secret_and_forbidden_data_are_untouched(self):
        self.run_case("secret")

    def test_pending_deduplication_and_five_second_cache(self):
        self.run_case("expiry")

    def test_none_unknown_and_invalid_server_payloads(self):
        self.run_case("validation")

    def test_entry_definitions_and_set_bonuses(self):
        self.run_case("definitions")

    def test_enchant_description_gems_and_empty_sockets(self):
        self.run_case("enchants")

    def test_revision_uses_native_uint32_boundary(self):
        self.run_case("revision")

    def test_existing_aio_channel_and_progression_bind_chain(self):
        self.run_case("bind")

    def test_custom_carrier_filter_requires_fresh_exact_instance_confirmation(self):
        self.run_case("carrier")

    def test_custom_carrier_comparison_keeps_normal_item_lines(self):
        self.run_case("carrier_comparison")

    def test_vendor_preview_and_owned_metadata_remain_separate(self):
        self.run_case("vendor")

    def test_signed_multi_properties_runes_and_native_ability(self):
        self.run_case("signed_properties")

    def test_confirmed_change_updates_visible_tooltip(self):
        self.run_case("changed_item")
