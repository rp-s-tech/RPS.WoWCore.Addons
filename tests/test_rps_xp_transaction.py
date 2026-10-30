"""Exercise emitted XP/receipt statements using SQLite transactions, not a live realm.

This verifies transaction failure semantics; MySQL migrations and native callbacks
still need the separate server/DB acceptance scenarios.
"""
import re
import sqlite3
import tempfile
from pathlib import Path

import lua_runtime as runtime


class RpsXpTransaction(runtime.LuaRuntimeCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        output = Path(directory.name)
        fixture = runtime.ROOT / "Addons/tests/fixtures/rps_progression.lua"
        self.run_lua("ROOT=[[" + runtime.ROOT.as_posix() + "]]\n"
                     "local cases=assert(loadfile([[" + fixture.as_posix() + "]]))()\n"
                     "cases.export_xp_sql([[" + output.as_posix() + "]])")
        source = (runtime.ROOT / "RPS.WoWCore/src/server/game/LuaEngine/methods/TrinityCore/RpsCombatMethods.h").read_text(encoding="utf-8")
        template = re.search(r'"(UPDATE characters SET level=\{\}, xp=\{\} WHERE guid=\{\})"', source)
        self.assertIsNotNone(template, "Update the integration fixture if the native statement changes")
        self.native = template[1].format(*(int(value) for value in (output / "native.txt").read_text().split()))
        self.receipt = (output / "receipt.sql").read_text()
        self.db = sqlite3.connect(":memory:")
        self.addCleanup(self.db.close)
        self.db.executescript("""
            CREATE TABLE characters(guid INTEGER PRIMARY KEY, level INTEGER, xp INTEGER);
            INSERT INTO characters VALUES(2,10,0);
            CREATE TABLE rps_action_receipts(
                issuer_guid INTEGER, request_id TEXT, signature TEXT, state TEXT,
                result_kind TEXT, stat_key TEXT, total INTEGER, damage INTEGER,
                attack_id TEXT, result_payload TEXT, PRIMARY KEY(issuer_guid,request_id));
        """)
        with self.db:
            self.db.execute((output / "intent.sql").read_text())

    def assert_state(self, native, receipt):
        self.assertEqual(self.db.execute("SELECT level,xp FROM characters WHERE guid=2").fetchone(), native)
        self.assertEqual(self.db.execute("SELECT state FROM rps_action_receipts").fetchone()[0], receipt)

    def test_receipt_failure_rolls_back_native_xp(self):
        self.db.execute("""CREATE TRIGGER fail_receipt BEFORE UPDATE ON rps_action_receipts
                        BEGIN SELECT RAISE(ABORT,'receipt failure'); END""")
        with self.assertRaises(sqlite3.IntegrityError), self.db:
            self.db.execute(self.native)
            self.db.execute(self.receipt)
        self.assert_state((10, 0), "pending")
        self.db.execute("DROP TRIGGER fail_receipt")
        with self.db:
            self.db.execute(self.native)
            self.db.execute(self.receipt)
        self.assert_state((11, 5), "done")

    def test_native_failure_leaves_recoverable_intent(self):
        self.db.execute("""CREATE TRIGGER fail_xp BEFORE UPDATE ON characters
                        BEGIN SELECT RAISE(ABORT,'native failure'); END""")
        with self.assertRaises(sqlite3.IntegrityError), self.db:
            self.db.execute(self.native)
            self.db.execute(self.receipt)
        self.assert_state((10, 0), "pending")
