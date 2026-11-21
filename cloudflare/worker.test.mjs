// node --test cloudflare/   (GitHub API is simulated, nothing leaves the machine)
import { test } from "node:test";
import assert from "node:assert/strict";
import worker, { parseExport, normalize } from "./worker.js";

// in-memory fake of the GitHub contents API
function fakeGitHub() {
  const files = new Map();      // path -> { content(base64), sha }
  let n = 0;
  const calls = [];
  globalThis.fetch = async (url, init = {}) => {
    const u = new URL(url);
    const path = decodeURIComponent(u.pathname.replace(/^\/repos\/[^/]+\/[^/]+\/contents\//, ""));
    calls.push({ method: init.method, path, auth: init.headers.authorization });
    if (init.method === "GET") {
      const f = files.get(path);
      return f ? new Response(JSON.stringify(f), { status: 200 }) : new Response("{}", { status: 404 });
    }
    const body = JSON.parse(init.body);
    const cur = files.get(path);
    if (cur && body.sha !== cur.sha) return new Response("{}", { status: 409 });
    files.set(path, { content: body.content, sha: `sha${++n}` });
    return new Response("{}", { status: cur ? 200 : 201 });
  };
  return { files, calls };
}

const env = { GITHUB_TOKEN: "t0ken", REPO: "o/r", BRANCH: "main", GITHUB_API: "https://api.example" };
const post = (body, ip = "1.2.3.4") =>
  worker.fetch(new Request("https://w/submit", { method: "POST", body, headers: { "cf-connecting-ip": ip } }), env);

test("parse + normalize + caps", () => {
  const s = parseExport("x JUJU1;ABCD1234;100;38:10:2589=3,752=99/30:0:/99999999:5:");
  assert.equal(s.id, "abcd1234");
  assert.equal(s.mobs.get(38).items.get(752), 10, "capped to kills");
  assert.ok(!s.mobs.has(30), "0 kills dropped");
  assert.ok(!s.mobs.has(99999999), "bad npc id dropped");
  assert.equal(normalize(s), "JUJU1;abcd1234;100;38:10:752=10,2589=3\n");
  const big = parseExport("JUJU1;abcd;1;38:50000:2589=25000");
  assert.equal(big.mobs.get(38).kills, 5000);
  assert.equal(big.mobs.get(38).items.get(2589), 2500);
});

test("rejects garbage and future timestamps", () => {
  for (const bad of ["hello", "JUJU1;abcd;1;", "JUJU1;abcd;1;38:x:1=2", "JUJU1;zz;1;38:1:"]) {
    assert.throws(() => parseExport(bad));
  }
  assert.throws(() => parseExport(`JUJU1;abcd;${Math.floor(Date.now() / 1000) + 999999};38:1:`));
});

test("stores, newest wins, older ignored", async () => {
  const gh = fakeGitHub();
  let r = await post("JUJU1;aaaa;100;38:10:2589=1");
  assert.equal(r.status, 200);
  assert.equal((await r.json()).status, "saved");
  assert.equal(atob(gh.files.get("data/submissions/aaaa.txt").content), "JUJU1;aaaa;100;38:10:2589=1\n");
  assert.equal(gh.calls[0].auth, "Bearer t0ken");
  r = await post("JUJU1;aaaa;200;38:20:2589=4");
  assert.equal((await r.json()).status, "saved");
  r = await post("JUJU1;aaaa;150;38:99:");
  assert.equal((await r.json()).status, "up-to-date");
  assert.match(atob(gh.files.get("data/submissions/aaaa.txt").content), /;200;38:20:2589=4/);
});

test("bad input -> 400, wrong path -> 404, health check", async () => {
  fakeGitHub();
  assert.equal((await post("nope")).status, 400);
  const r404 = await worker.fetch(new Request("https://w/other", { method: "POST", body: "x" }), env);
  assert.equal(r404.status, 404);
  const ok = await worker.fetch(new Request("https://w/"), env);
  assert.equal(ok.status, 200);
});

test("rate limit", async () => {
  fakeGitHub();
  let left = 1;
  const limited = { ...env, LIMITER: { limit: async () => ({ success: left-- > 0 }) } };
  const req = () => new Request("https://w/submit", { method: "POST", body: "JUJU1;bbbb;1;38:1:" });
  assert.equal((await worker.fetch(req(), limited)).status, 200);
  assert.equal((await worker.fetch(req(), limited)).status, 429);
});

test("too large -> 413", async () => {
  fakeGitHub();
  assert.equal((await post("x".repeat(600 * 1024))).status, 413);
});
