"""Build Juju/DropData.lua from QuestieDB (Forever):
  - Wowhead drop % (support/Forever/DropTables/classicItemDrops.lua + numeric corrections)
  - item -> npcDrops lists (no %) from the baked Item rows
  - NPC name / level / rank / zone (uiMap) from the baked Npc rows
usage: python tools/extract_drops.py [QuestieDB dir] [Juju dir]
  defaults: the QuestieDB in a standard WoW Forever install, and ./Juju
needs: pip install -r tools/requirements.txt
"""
import sys, os, re, base64, collections
import cbor2

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_QDB = r"C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\QuestieDB"
qdir = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_QDB
outdir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "Juju")
meta = {}
for line in open(os.path.join(qdir, "QuestieDB_Forever.toc"), encoding="utf-8"):
    m = re.match(r"^## (X-[^:]+): (.*)$", line.rstrip("\n"))
    if m:
        meta[m.group(1)] = m.group(2).strip()

def stored(key):
    v = meta.get(key)
    if v is None:
        return None
    m = re.match(r"^~(\d+)~$", v)
    if m:
        return "".join(meta[f"{key}-{i}"] for i in range(1, int(m.group(1)) + 1))
    return v

def decode(key):
    raw = stored(key)
    return None if raw is None else cbor2.loads(base64.b64decode(raw))

def field(row, i):
    if isinstance(row, dict):
        return row.get(i)
    if isinstance(row, list):
        return row[i - 1] if len(row) >= i else None
    return None

def text(v):
    return v.decode("utf-8", "replace") if isinstance(v, bytes) else v

# --- Wowhead % --------------------------------------------------------------
def parse_drop_table(path):
    out = collections.defaultdict(dict)
    item = None
    for line in open(path, encoding="utf-8"):
        m = re.match(r"^\s*\[(\d+)\] = \{\s*(?:--\s*(.*))?$", line)
        if m:
            item = int(m.group(1)); continue
        m = re.match(r"^\s*\[(\d+)\] = ([\d.]+),", line)
        if m and item is not None:
            out[item][int(m.group(1))] = float(m.group(2))
            continue
        if re.match(r"^\s*\},?\s*$", line):
            item = None
    return out

dt = os.path.join(qdir, "support", "Forever", "DropTables")
pct = parse_drop_table(os.path.join(dt, "classicItemDrops.lua"))
for item, npcs in parse_drop_table(os.path.join(dt, "itemDropCorrections.lua")).items():
    pct[item].update(npcs)       # numeric corrections only (references are skipped by the regex)

# --- items ------------------------------------------------------------------
item_names, item_npcs = {}, {}
for key in meta:
    m = re.match(r"^X-Item-(\d+)-S$", key)
    if not m:
        continue
    iid = int(m.group(1))
    row = decode(key)
    name = text(field(row, 1))
    drops = decode(f"X-Item-{iid}-2")
    if isinstance(drops, dict):
        drops = list(drops.values())
    if drops:
        item_npcs[iid] = [int(n) for n in drops if isinstance(n, int)]
    if name:
        item_names[iid] = name

items = set(item_npcs) | set(pct)
# --- area -> uiMap ----------------------------------------------------------
zsrc = open(os.path.join(qdir, "support", "Forever", "Zones", "areaIdToUiMapId.lua"), encoding="utf-8").read()
block = zsrc.split("ZoneDB.private.areaIdToUiMapId = [[", 1)[1].split("]]", 1)[0]
area_to_map = {int(a): int(u) for a, u in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", block)}

# --- npcs used by any drop --------------------------------------------------
needed = set()
for iid in items:
    needed.update(item_npcs.get(iid, []))
    needed.update(pct.get(iid, {}).keys())
npcs = {}
for nid in needed:
    row = decode(f"X-Npc-{nid}-S")
    if row is None:
        continue
    name = text(field(row, 1))
    if not name:
        continue
    zone = field(row, 9) or 0
    npcs[nid] = (name, field(row, 4) or 0, field(row, 5) or 0, field(row, 6) or 0, area_to_map.get(int(zone), 0))

def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("|", "/")

lines_items, n_pairs, n_pct = [], 0, 0
for iid in sorted(items):
    name = item_names.get(iid)
    if not name:
        continue
    entries = {}
    for n in item_npcs.get(iid, []):
        if n in npcs:
            entries[n] = None
    for n, p in pct.get(iid, {}).items():
        if n in npcs:
            entries[n] = p
    if not entries:
        continue
    parts = []
    for n, p in sorted(entries.items(), key=lambda kv: -(kv[1] or -1)):
        parts.append(f"{n}:{p:g}" if p is not None else f"{n}")
        n_pairs += 1
        n_pct += p is not None
    lines_items.append(f'[{iid}]="{esc(name)}|' + ",".join(parts) + '",')

lines_npcs = [f'[{nid}]="{esc(v[0])}|{v[1]}|{v[2]}|{v[3]}|{v[4]}",' for nid, v in sorted(npcs.items())]

lua = (
    "----------------------------------------------------------------------\n"
    "-- Juju — drop data (GENERATED from QuestieDB_Forever, do not hand-edit)\n"
    "-- ITEMS[itemID] = \"Name|npc:pct,npc:pct,npc,...\"  (no :pct = drops it, % unknown)\n"
    "-- NPCS[npcID]   = \"Name|minLevel|maxLevel|rank|uiMapID\"\n"
    f"-- {len(lines_items)} items, {len(lines_npcs)} mobs, {n_pairs} drops ({n_pct} with Wowhead %).\n"
    "----------------------------------------------------------------------\n"
    "local _, J = ...\n"
    "J.ITEMS = {\n" + "\n".join(lines_items) + "\n}\n"
    "J.NPCS = {\n" + "\n".join(lines_npcs) + "\n}\n"
)
os.makedirs(outdir, exist_ok=True)
open(os.path.join(outdir, "DropData.lua"), "w", encoding="utf-8", newline="\n").write(lua)
print(f"items {len(lines_items)}  mobs {len(lines_npcs)}  drops {n_pairs}  with% {n_pct}")
print("size KB", os.path.getsize(os.path.join(outdir, "DropData.lua")) // 1024)
