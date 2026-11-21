// Juju-mottaker — Cloudflare Worker
//
// The Juju uploader on players' PCs POSTs export text ("JUJU1;id;serial;...")
// to /submit. This Worker checks it (same rules as tools/jujudata.py), and
// stores it as data/submissions/<id>.txt in the GitHub repo through the
// GitHub API. That commit starts the "Juju-data" workflow, which merges all
// submissions into Juju/SharedData.lua.
//
// Secrets / settings (see cloudflare/README.md):
//   GITHUB_TOKEN  fine-grained token: this repo only, "Contents: read and write"
//   REPO          "owner/name"        BRANCH  "main"
//   LIMITER       rate limit binding (per IP)
//
// Submissions are untrusted: only numbers that pass the checks are written,
// as a normalized line. Nothing from the request is ever executed.

const MAX_BODY = 512 * 1024;
const MAX_NPC_ID = 10_000_000;
const MAX_ITEM_ID = 10_000_000;
const MAX_KILLS_PER_MOB = 5000;
const MAX_ITEMS_PER_MOB = 400;
const MAX_MOBS = 20000;
const EXPORT_RE = /JUJU1;([0-9a-fA-F]{4,32});(\d{1,12});([0-9:=,/]*)/;

export class BadData extends Error {}

// export text -> { id, serial, mobs: Map(npc -> {kills, items: Map(item -> n)}) }
export function parseExport(text) {
  const m = EXPORT_RE.exec(text);
  if (!m) throw new BadData("fant ingen Juju-eksport (JUJU1;...)");
  const id = m[1].toLowerCase();
  const serial = Number(m[2]);
  const now = Math.floor(Date.now() / 1000);
  if (serial > now + 86400) throw new BadData("ugyldig tidsstempel");
  const mobs = new Map();
  for (const part of m[3].split("/").filter(Boolean)) {
    const pm = /^(\d+):(\d+):([0-9=,]*)$/.exec(part);
    if (!pm) throw new BadData("ugyldig del i eksporten");
    const npc = Number(pm[1]);
    let kills = Number(pm[2]);
    if (!(npc >= 1 && npc <= MAX_NPC_ID) || kills === 0) continue;
    const items = new Map();
    const list = pm[3].split(",").filter(Boolean);
    if (list.length > MAX_ITEMS_PER_MOB) continue;
    for (const it of list) {
      const im = /^(\d+)=(\d+)$/.exec(it);
      if (!im) throw new BadData("ugyldig item i eksporten");
      const item = Number(im[1]);
      let n = Math.min(Number(im[2]), kills);     // no more drops than corpses
      if (item >= 1 && item <= MAX_ITEM_ID && n > 0) items.set(item, n);
    }
    if (kills > MAX_KILLS_PER_MOB) {              // cap one player's weight, keep ratios
      const f = MAX_KILLS_PER_MOB / kills;
      for (const [i, n] of items) items.set(i, Math.max(1, Math.round(n * f)));
      kills = MAX_KILLS_PER_MOB;
    }
    mobs.set(npc, { kills, items });
    if (mobs.size > MAX_MOBS) throw new BadData("for mange mobs");
  }
  if (mobs.size === 0) throw new BadData("innsendingen inneholder ingen kills");
  return { id, serial, mobs };
}

export function normalize(sub) {
  const parts = [...sub.mobs.keys()].sort((a, b) => a - b).map((npc) => {
    const m = sub.mobs.get(npc);
    const items = [...m.items.keys()].sort((a, b) => a - b).map((i) => `${i}=${m.items.get(i)}`).join(",");
    return `${npc}:${m.kills}:${items}`;
  });
  return `JUJU1;${sub.id};${sub.serial};${parts.join("/")}\n`;
}

function json(status, obj) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

async function github(env, method, path, body) {
  const api = env.GITHUB_API || "https://api.github.com";
  return fetch(`${api}/repos/${env.REPO}/contents/${path}`, {
    method,
    headers: {
      authorization: `Bearer ${env.GITHUB_TOKEN}`,
      accept: "application/vnd.github+json",
      "user-agent": "juju-mottaker",
      "x-github-api-version": "2022-11-28",
      ...(body ? { "content-type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
}

// store one submission; newest serial per player wins
async function store(env, sub) {
  const path = `data/submissions/${sub.id}.txt`;
  const branch = env.BRANCH || "main";
  for (let attempt = 0; attempt < 2; attempt++) {
    let sha;
    const cur = await github(env, "GET", `${path}?ref=${branch}`);
    if (cur.status === 200) {
      const file = await cur.json();
      sha = file.sha;
      const old = atob((file.content || "").replace(/\n/g, ""));
      const om = EXPORT_RE.exec(old);
      if (om && Number(om[2]) >= sub.serial) return { status: "up-to-date" };
    } else if (cur.status !== 404) {
      throw new Error(`GitHub GET ${cur.status}`);
    }
    const put = await github(env, "PUT", path, {
      message: `Juju-data: automatisk innsending (${sub.id.slice(0, 6)})`,
      content: btoa(normalize(sub)),                 // ASCII only
      branch,
      ...(sha ? { sha } : {}),
      committer: { name: "juju-data-bot", email: "juju-data-bot@users.noreply.github.com" },
    });
    if (put.status === 200 || put.status === 201) return { status: "saved" };
    if (put.status !== 409 && put.status !== 422) throw new Error(`GitHub PUT ${put.status}`);
    // someone else wrote the file in between: read again and retry once
  }
  throw new Error("GitHub: konflikt");
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/") {
      return new Response("Juju-mottaker OK\n", { headers: { "content-type": "text/plain" } });
    }
    if (request.method !== "POST" || url.pathname !== "/submit") return json(404, { error: "ukjent adresse" });

    const ip = request.headers.get("cf-connecting-ip") || "unknown";
    if (env.LIMITER) {
      const { success } = await env.LIMITER.limit({ key: ip });
      if (!success) return json(429, { error: "for mange innsendinger – prøv igjen om litt" });
    }
    const len = Number(request.headers.get("content-length") || 0);
    if (len > MAX_BODY) return json(413, { error: "for stor" });
    const text = await request.text();
    if (text.length > MAX_BODY) return json(413, { error: "for stor" });

    let sub;
    try {
      sub = parseExport(text);
    } catch (e) {
      if (e instanceof BadData) return json(400, { error: e.message });
      throw e;
    }
    try {
      const r = await store(env, sub);
      let kills = 0;
      for (const m of sub.mobs.values()) kills += m.kills;
      return json(200, { ...r, mobs: sub.mobs.size, kills });
    } catch (e) {
      return json(502, { error: "kunne ikke lagre akkurat nå", detail: String(e.message || e) });
    }
  },
};
