"""Take one submission in, check it, store it cleaned in data/submissions/.

From files (e.g. sent in Discord):
    python tools/ingest.py Juju.lua [more files...]

From a GitHub issue (used by .github/workflows/juju-data.yml):
    ISSUE_BODY=... ISSUE_NUMBER=12 python tools/ingest.py --issue

The stored file is a normalized export line (JUJU1;...), never the original
upload, so nothing unchecked ends up in the repo. A message for the issue
comment is written to data/ingest-result.md.
"""
import io
import os
import re
import sys
import urllib.parse
import urllib.request
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jujudata  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUBMISSIONS = os.path.join(ROOT, "data", "submissions")
RESULT = os.path.join(ROOT, "data", "ingest-result.md")

# only GitHub's own attachment links are downloaded
ATTACH_RE = re.compile(r"https://github\.com/(?:user-attachments/files/\d+/[^\s)\]>\"']+|"
                       r"[\w.-]+/[\w.-]+/files/\d+/[^\s)\]>\"']+)")
ALLOWED_HOSTS = ("github.com", "objects.githubusercontent.com", "github-production-user-asset")


def normalize(sub):
    parts = []
    for npc in sorted(sub["mobs"]):
        m = sub["mobs"][npc]
        items = ",".join(f"{i}={n}" for i, n in sorted(m["items"].items()))
        parts.append(f"{npc}:{m['kills']}:{items}")
    return f"JUJU1;{sub['id']};{sub['serial']};" + "/".join(parts) + "\n"


def store(sub, name):
    os.makedirs(SUBMISSIONS, exist_ok=True)
    # one file per player id: a new submission replaces the old one
    path = os.path.join(SUBMISSIONS, f"{sub['id']}.txt")
    if os.path.exists(path):                     # never replace newer data with older
        with open(path, encoding="utf-8") as f:
            old = jujudata.parse_export(f.read())
        if old and old["serial"] > sub["serial"]:
            raise jujudata.BadData("en nyere innsending fra samme spiller finnes allerede")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(normalize(sub))
    kills = sum(m["kills"] for m in sub["mobs"].values())
    return (f"{name}: {len(sub['mobs'])} mobs, {kills} kills"
            + (f" ({sub['dropped']} ugyldige linjer hoppet over)" if sub["dropped"] else ""))


def _download(url):
    req = urllib.request.Request(url, headers={"User-Agent": "juju-data-ingest"})
    with urllib.request.urlopen(req, timeout=30) as r:
        host = urllib.parse.urlparse(r.geturl()).hostname or ""
        if not any(h in host for h in ALLOWED_HOSTS):
            raise jujudata.BadData(f"vedlegget ligger på en ukjent server: {host}")
        data = r.read(jujudata.MAX_INPUT_BYTES + 1)
    if len(data) > jujudata.MAX_INPUT_BYTES:
        raise jujudata.BadData("vedlegget er for stort")
    return data


def _text_from_bytes(data, name):
    if name.lower().endswith(".zip") or data[:2] == b"PK":
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            for info in z.infolist():
                n = info.filename.lower()
                if n.endswith((".lua", ".txt")) and info.file_size <= jujudata.MAX_INPUT_BYTES:
                    return z.read(info).decode("utf-8", "replace")
        raise jujudata.BadData("fant ingen .lua eller .txt i zip-filen")
    return data.decode("utf-8", "replace")


AUTHORS = os.path.join(ROOT, "data", "authors.json")


def one_player_per_account(author, sub):
    """A GitHub account counts as one player: if it sent data under another
    Juju id before, that older file is removed. Stops one person from adding
    many fake 'players' through repeated submissions."""
    import json
    if not author or not re.fullmatch(r"[A-Za-z0-9-]{1,39}", author):
        return
    try:
        with open(AUTHORS, encoding="utf-8") as f:
            authors = json.load(f)
    except (OSError, ValueError):
        authors = {}
    old = authors.get(author)
    if old and old != sub["id"] and re.fullmatch(r"[0-9a-f]{4,32}", old):
        try:
            os.remove(os.path.join(SUBMISSIONS, f"{old}.txt"))
        except OSError:
            pass
    authors[author] = sub["id"]
    with open(AUTHORS, "w", encoding="utf-8", newline="\n") as f:
        json.dump(authors, f, indent=1, sort_keys=True)
        f.write("\n")


def from_issue():
    body = os.environ.get("ISSUE_BODY", "")
    number = os.environ.get("ISSUE_NUMBER", "?")
    author = os.environ.get("ISSUE_AUTHOR", "")
    texts = []
    if jujudata.EXPORT_RE.search(body):
        texts.append(("innlimt tekst", body))
    for url in ATTACH_RE.findall(body)[:5]:
        texts.append((url.rsplit("/", 1)[-1], None, url))
    if not texts:
        raise jujudata.BadData("fant verken innlimt Juju-eksport (JUJU1;...) eller et vedlegg")
    lines, ok = [], False
    for entry in texts:
        name = entry[0]
        try:
            text = entry[1] if entry[1] is not None else _text_from_bytes(_download(entry[2]), name)
            sub = jujudata.parse_submission(text)
            lines.append("✅ " + store(sub, name))
            one_player_per_account(author, sub)
            ok = True
        except (jujudata.BadData, OSError, zipfile.BadZipFile) as e:
            lines.append(f"❌ {name}: {e}")
    return ok, f"Innsending fra issue #{number}:\n\n" + "\n".join(f"- {l}" for l in lines)


def from_files(paths):
    lines, ok = [], False
    for p in paths:
        try:
            with open(p, "rb") as f:
                text = _text_from_bytes(f.read(jujudata.MAX_INPUT_BYTES + 1), p)
            lines.append("OK   " + store(jujudata.parse_submission(text), os.path.basename(p)))
            ok = True
        except (jujudata.BadData, OSError, zipfile.BadZipFile) as e:
            lines.append(f"FEIL {os.path.basename(p)}: {e}")
    return ok, "\n".join(lines)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--issue":
        try:
            ok, msg = from_issue()
        except jujudata.BadData as e:
            ok, msg = False, f"❌ {e}"
        os.makedirs(os.path.dirname(RESULT), exist_ok=True)
        with open(RESULT, "w", encoding="utf-8") as f:
            f.write(msg + "\n")
    elif len(sys.argv) > 1:
        ok, msg = from_files(sys.argv[1:])
    else:
        print(__doc__)
        return 2
    print(msg)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
