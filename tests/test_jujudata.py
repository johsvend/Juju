"""Tests for the Juju data tools.   python -m unittest discover -s tests -v"""
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "tools"))

import ingest  # noqa: E402
import jujudata  # noqa: E402
import merge_submissions  # noqa: E402

SAVEDVARS = r'''
JujuDB = {
["mobs"] = {
[38] = {
["kills"] = 20,
["items"] = {
[2589] = 7,
[752] = 30,
},
},
[30] = {
["kills"] = 0,
["items"] = {
},
},
["bad"] = {
["kills"] = "x",
},
},
["id"] = "a1b2c3d4e5f6",
["exports"] = {
[1795000000] = {
},
},
["itemNames"] = {
[77777] = "Weird \"Thing\"",
},
["target"] = {
["enabled"] = true,
},
}
'''


class ParserTests(unittest.TestCase):
    def test_savedvariables(self):
        sub = jujudata.parse_submission(SAVEDVARS)
        self.assertEqual(sub["id"], "a1b2c3d4e5f6")
        self.assertEqual(sub["serial"], 1795000000)
        self.assertEqual(sub["mobs"][38]["kills"], 20)
        self.assertEqual(sub["mobs"][38]["items"][2589], 7)
        self.assertEqual(sub["mobs"][38]["items"][752], 20, "capped to kills")
        self.assertNotIn(30, sub["mobs"], "mobs without kills are dropped")
        self.assertEqual(sub["dropped"], 1, "bad entry skipped, not fatal")

    def test_export(self):
        sub = jujudata.parse_submission("noise JUJU1;abcd1234;1795000001;38:10:2589=3,752=1/30:5: noise")
        self.assertEqual(sub["id"], "abcd1234")
        self.assertEqual(sub["mobs"][38], {"kills": 10, "items": {2589: 3, 752: 1}})
        self.assertEqual(sub["mobs"][30], {"kills": 5, "items": {}})

    def test_skinning_keys(self):
        # skinning stats travel as npc + 10,000,000
        sub = jujudata.parse_submission("JUJU1;abcd;1;10002248:4:4234=3,4232=1/2248:16:")
        self.assertEqual(sub["mobs"][10002248], {"kills": 4, "items": {4234: 3, 4232: 1}})
        self.assertIn(2248, sub["mobs"])

    def test_cap_per_player(self):
        sub = jujudata.parse_submission("JUJU1;abcd;1;38:50000:2589=25000")
        self.assertEqual(sub["mobs"][38]["kills"], jujudata.MAX_KILLS_PER_MOB)
        self.assertEqual(sub["mobs"][38]["items"][2589], jujudata.MAX_KILLS_PER_MOB // 2)

    def test_rejects_garbage(self):
        for bad in ["hello", "", "JUJU1;abcd;1;", "JujuDB = { [\"mobs\"] = { } }",
                    "JujuDB = os.execute('x')", "JUJU1;abcd;1;38:x:1=2"]:
            with self.assertRaises(jujudata.BadData, msg=bad):
                jujudata.parse_submission(bad)

    def test_never_executes(self):
        # function calls are not table literals: rejected, not run
        with self.assertRaises(jujudata.BadData):
            jujudata.parse_savedvariables('JujuDB = { ["mobs"] = loadstring("x")() }')


class MergeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        ingest.SUBMISSIONS = self.dir
        ingest.AUTHORS = os.path.join(self.dir, "authors.json")

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name, text):
        with open(os.path.join(self.dir, name), "w", encoding="utf-8") as f:
            f.write(text)

    def test_merge_and_newest_wins(self):
        self.write("p1-old.txt", "JUJU1;aaaa;100;38:10:2589=1")
        self.write("p1-new.txt", "JUJU1;aaaa;200;38:20:2589=4")
        self.write("p2.txt", "JUJU1;bbbb;150;38:30:2589=6/30:5:")
        self.write("junk.txt", "not juju")
        subs, problems = merge_submissions.load_all(self.dir)
        self.assertEqual(set(subs), {"aaaa", "bbbb"})
        self.assertEqual(subs["aaaa"]["serial"], 200)
        kills, items, players = merge_submissions.merge(subs)
        self.assertEqual(kills[38], 50)
        self.assertEqual(items[38][2589], 10)
        self.assertEqual(players[38], 2)
        self.assertEqual(players[30], 1)
        self.assertEqual(len(problems), 1)

    def test_ingest_files_normalizes(self):
        src = os.path.join(self.dir, "upload.lua.in")
        with open(src, "w", encoding="utf-8") as f:
            f.write(SAVEDVARS)
        ok, msg = ingest.from_files([src])
        self.assertTrue(ok, msg)
        with open(os.path.join(self.dir, "a1b2c3d4e5f6.txt"), encoding="utf-8") as f:
            stored = f.read()
        self.assertTrue(stored.startswith("JUJU1;a1b2c3d4e5f6;1795000000;"))
        self.assertNotIn("Weird", stored, "only numbers are stored")

    def test_older_does_not_replace_newer(self):
        ingest.store(jujudata.parse_submission("JUJU1;cccc;500;38:10:"), "new")
        with self.assertRaises(jujudata.BadData):
            ingest.store(jujudata.parse_submission("JUJU1;cccc;400;38:99:"), "old")

    def test_one_player_per_account(self):
        a = jujudata.parse_submission("JUJU1;dddd;1;38:10:")
        b = jujudata.parse_submission("JUJU1;eeee;2;38:10:")
        ingest.store(a, "a"); ingest.one_player_per_account("someone", a)
        ingest.store(b, "b"); ingest.one_player_per_account("someone", b)
        self.assertFalse(os.path.exists(os.path.join(self.dir, "dddd.txt")))
        self.assertTrue(os.path.exists(os.path.join(self.dir, "eeee.txt")))

    def test_issue_body_paste(self):
        os.environ["ISSUE_BODY"] = "### Juju-data\n\n```\nJUJU1;ffff;9;38:12:2589=2\n```"
        os.environ["ISSUE_NUMBER"] = "7"
        os.environ["ISSUE_AUTHOR"] = "tester"
        ok, msg = ingest.from_issue()
        self.assertTrue(ok, msg)
        self.assertTrue(os.path.exists(os.path.join(self.dir, "ffff.txt")))
        os.environ["ISSUE_BODY"] = "nothing here"
        with self.assertRaises(jujudata.BadData):
            ingest.from_issue()


class SignTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import jujusign
        cls.sign = jujusign
        cls.key = jujusign.keygen()

    def test_roundtrip_and_tamper(self):
        text = b"JUJUPACK1\nversion=5\n38=10|1|2589:3\n#abcd=1\n"
        sig = self.sign.sign(text, self.key)
        self.assertTrue(self.sign.verify(text, sig, self.key["n"]))
        self.assertFalse(self.sign.verify(text.replace(b"10|1", b"99|1"), sig, self.key["n"]))
        other = self.sign.keygen()
        self.assertFalse(self.sign.verify(text, sig, other["n"]))

    def test_canonical_matches_file_lines(self):
        subs = {"abcd": {"serial": 7, "mobs": {38: {"kills": 10, "items": {2589: 3}}}}}
        kills, items, players = merge_submissions.merge(subs)
        body = merge_submissions.pack_body(subs, kills, items, players)
        self.assertEqual(body, "38=10|1|2589:3\n#abcd=7")
        self.assertEqual(merge_submissions.canonical(5, body), "JUJUPACK1\nversion=5\n38=10|1|2589:3\n#abcd=7\n")


if __name__ == "__main__":
    unittest.main()
