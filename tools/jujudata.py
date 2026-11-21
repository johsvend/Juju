"""Reading and checking Juju data that players send in.

Two input forms:
  * export text from Juju (/juju eksport):
        JUJU1;<id>;<serial>;<npc>:<kills>:<item>=<n>,<item>=<n>/<npc>:...
  * a SavedVariables file (WTF/Account/<account>/SavedVariables/Juju.lua)

Submitted files are untrusted: the Lua file is parsed by a small parser that
only understands table literals (numbers, strings, booleans, nil, nested
tables). Nothing from a submission is ever executed.
"""
import hashlib
import re

MAX_NPC_ID = 10_000_000
MAX_ITEM_ID = 10_000_000
MAX_KILLS_PER_MOB = 5000          # one player's weight per mob is capped here
MAX_ITEMS_PER_MOB = 400
MAX_INPUT_BYTES = 8 * 1024 * 1024


class BadData(ValueError):
    pass


# --------------------------------------------------------------------------
# Lua table-literal parser (SavedVariables)
# --------------------------------------------------------------------------
class _LuaParser:
    _ws = re.compile(r"(?:\s+|--\[(=*)\[.*?\]\1\]|--[^\n]*)+", re.S)
    _num = re.compile(r"-?(?:0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?)")
    _name = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

    def __init__(self, text):
        self.s, self.i, self.depth = text, 0, 0

    def skip(self):
        m = self._ws.match(self.s, self.i)
        if m:
            self.i = m.end()

    def peek(self, lit):
        self.skip()
        return self.s.startswith(lit, self.i)

    def expect(self, lit):
        if not self.peek(lit):
            raise BadData(f"forventet '{lit}' ved posisjon {self.i}")
        self.i += len(lit)

    def string(self):
        self.skip()
        q = self.s[self.i]
        if q == "[":
            m = re.compile(r"\[(=*)\[(.*?)\]\1\]", re.S).match(self.s, self.i)
            if not m:
                raise BadData("ugyldig lang streng")
            self.i = m.end()
            return m.group(2)
        self.i += 1
        out = []
        while True:
            if self.i >= len(self.s):
                raise BadData("streng uten slutt")
            c = self.s[self.i]
            if c == q:
                self.i += 1
                return "".join(out)
            if c == "\\":
                self.i += 1
                e = self.s[self.i]
                if e.isdigit():
                    m = re.compile(r"\d{1,3}").match(self.s, self.i)
                    out.append(chr(int(m.group(0)) % 256))
                    self.i = m.end()
                    continue
                out.append({"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b",
                            "f": "\f", "v": "\v"}.get(e, e))
                self.i += 1
                continue
            out.append(c)
            self.i += 1

    def value(self):
        self.skip()
        if self.i >= len(self.s):
            raise BadData("uventet slutt")
        c = self.s[self.i]
        if c == "{":
            return self.table()
        if c in "\"'" or self.s.startswith("[[", self.i) or self.s.startswith("[=", self.i):
            return self.string()
        for word, val in (("true", True), ("false", False), ("nil", None)):
            if self.s.startswith(word, self.i) and not self.s[self.i + len(word):self.i + len(word) + 1].isalnum():
                self.i += len(word)
                return val
        m = self._num.match(self.s, self.i)
        if m:
            self.i = m.end()
            t = m.group(0)
            if t.lower().startswith(("0x", "-0x")):
                return int(t, 16)
            f = float(t)
            return int(f) if f.is_integer() and "." not in t and "e" not in t.lower() else f
        raise BadData(f"ugyldig verdi ved posisjon {self.i}")

    def table(self):
        self.depth += 1
        if self.depth > 20:
            raise BadData("for dyp tabell")
        self.expect("{")
        out, n = {}, 1
        while not self.peek("}"):
            if self.peek("["):
                self.i += 1
                key = self.value()
                self.expect("]")
                self.expect("=")
                out[key] = self.value()
            else:
                self.skip()
                m = self._name.match(self.s, self.i)
                save = self.i
                if m:
                    self.i = m.end()
                    if self.peek("=") and not self.peek("=="):
                        self.i += 1
                        out[m.group(0)] = self.value()
                    else:
                        self.i = save
                        out[n] = self.value()
                        n += 1
                else:
                    out[n] = self.value()
                    n += 1
            if self.peek(",") or self.peek(";"):
                self.i += 1
        self.expect("}")
        self.depth -= 1
        return out

    def assignments(self):
        out = {}
        while True:
            self.skip()
            if self.i >= len(self.s):
                return out
            m = self._name.match(self.s, self.i)
            if not m:
                raise BadData(f"forventet variabelnavn ved posisjon {self.i}")
            self.i = m.end()
            self.expect("=")
            out[m.group(0)] = self.value()


def parse_savedvariables(text):
    return _LuaParser(text).assignments()


# --------------------------------------------------------------------------
# One submission -> {"id", "serial", "mobs": {npc: {"kills", "items": {item: n}}}}
# --------------------------------------------------------------------------
def _int(v, lo, hi, what):
    if isinstance(v, bool) or not isinstance(v, (int, float)) or v != int(v):
        raise BadData(f"{what} er ikke et heltall")
    v = int(v)
    if not lo <= v <= hi:
        raise BadData(f"{what} utenfor gyldig område: {v}")
    return v


def _clean_mobs(raw_mobs):
    """Check and cap one player's counts. Bad entries are dropped, not fatal."""
    mobs, dropped = {}, 0
    for npc, m in raw_mobs.items():
        try:
            npc = _int(npc, 1, MAX_NPC_ID, "npc-id")
            kills = _int(m.get("kills", 0), 0, 10_000_000, "kills")
            items = m.get("items") or {}
            if not isinstance(items, dict) or len(items) > MAX_ITEMS_PER_MOB:
                raise BadData("ugyldig item-liste")
            clean = {}
            for item, n in items.items():
                item = _int(item, 1, MAX_ITEM_ID, "item-id")
                n = _int(n, 0, 10_000_000, "antall")
                if n > kills:          # an item can't drop from more corpses than were looted
                    n = kills
                if n > 0:
                    clean[item] = n
        except (BadData, AttributeError):
            dropped += 1
            continue
        if kills == 0:
            continue
        if kills > MAX_KILLS_PER_MOB:  # cap one player's weight, keep the ratios
            f = MAX_KILLS_PER_MOB / kills
            clean = {i: max(1, round(n * f)) for i, n in clean.items()}
            kills = MAX_KILLS_PER_MOB
        mobs[npc] = {"kills": kills, "items": clean}
    return mobs, dropped


EXPORT_RE = re.compile(r"JUJU1;([0-9a-fA-F]{4,32});(\d{1,12});([0-9:=,/]*)")


def parse_export(text):
    m = EXPORT_RE.search(text)
    if not m:
        return None
    pid, serial, body = m.group(1).lower(), int(m.group(2)), m.group(3)
    raw = {}
    for part in filter(None, body.split("/")):
        pm = re.fullmatch(r"(\d+):(\d+):([0-9=,]*)", part)
        if not pm:
            raise BadData(f"ugyldig del i eksporten: {part[:40]}")
        items = {}
        for it in filter(None, pm.group(3).split(",")):
            im = re.fullmatch(r"(\d+)=(\d+)", it)
            if not im:
                raise BadData(f"ugyldig item i eksporten: {it[:40]}")
            items[int(im.group(1))] = int(im.group(2))
        raw[int(pm.group(1))] = {"kills": int(pm.group(2)), "items": items}
    mobs, dropped = _clean_mobs(raw)
    return {"id": pid, "serial": serial, "mobs": mobs, "dropped": dropped, "form": "eksport"}


def parse_savedvariables_file(text):
    data = parse_savedvariables(text)
    db = data.get("JujuDB")
    if not isinstance(db, dict) or not isinstance(db.get("mobs"), dict):
        raise BadData("fant ikke JujuDB.mobs i filen")
    pid = db.get("id")
    if not (isinstance(pid, str) and re.fullmatch(r"[0-9a-fA-F]{4,32}", pid)):
        # old Juju without id: a stable id from the content, so re-sending
        # the same file doesn't count twice
        pid = "f" + hashlib.sha1(text.encode("utf-8", "replace")).hexdigest()[:15]
    exports = db.get("exports") if isinstance(db.get("exports"), dict) else {}
    serial = max([int(k) for k in exports if isinstance(k, (int, float))] or [0])
    mobs, dropped = _clean_mobs(db["mobs"])
    return {"id": pid.lower(), "serial": serial, "mobs": mobs, "dropped": dropped, "form": "savedvariables"}


def parse_submission(text):
    """Accept export text or a SavedVariables file. Raises BadData."""
    if len(text.encode("utf-8", "replace")) > MAX_INPUT_BYTES:
        raise BadData("filen er for stor")
    sub = parse_export(text)
    if sub is None:
        if "JujuDB" not in text:
            raise BadData("fant verken en Juju-eksport (JUJU1;...) eller JujuDB i teksten")
        sub = parse_savedvariables_file(text)
    if not sub["mobs"]:
        raise BadData("innsendingen inneholder ingen kills")
    return sub
