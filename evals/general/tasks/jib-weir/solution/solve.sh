#!/bin/bash
# jib-weir oracle. Installs the reference TypeScript implementation into /app,
# builds it with the bundled tsc, GENERATES the OpenAPI document from the zod
# schemas, then proves the deliverable by starting the server via the shipped
# /app/start.sh and exercising the real HTTP surface against the visible
# dataset. Never reads /tests.
set -eu

# install the reference project (the deliverable tree the agent is expected to
# produce itself; this copy is the oracle's equivalent work)
cp -r /solution/solver/. /app/
chmod +x /app/start.sh

cd /app
node_modules/.bin/tsc -p tsconfig.json || { echo "oracle: tsc failed" >&2; exit 1; }

# generate /app/openapi.json from the zod schemas
node dist/scripts/generate-openapi.js || { echo "oracle: openapi generation failed" >&2; exit 1; }
[ -s /app/openapi.json ] || { echo "oracle: /app/openapi.json not produced" >&2; exit 1; }

# smoke the deliverable: boot the server and exercise the contract end to end.
bash /app/start.sh 8780 /app/data/media.json || { echo "oracle: start.sh failed" >&2; exit 1; }
trap 'if [ -f /tmp/jib-weir-server.pid ]; then kill "$(cat /tmp/jib-weir-server.pid)" 2>/dev/null || true; fi' EXIT

node - <<'NODE'
const base = "http://127.0.0.1:8780";
async function req(method, path, body) {
  const opts = { method, headers: {} };
  if (body !== undefined) {
    opts.headers["Content-Type"] = "application/json";
    opts.body = JSON.stringify(body);
  }
  const r = await fetch(base + path, opts);
  const text = await r.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* non-JSON */ }
  return { status: r.status, json };
}
async function main() {
  const health = await req("GET", "/health");
  if (health.status !== 200) throw new Error("health " + health.status);

  // pagination: walk the whole visible dataset
  const seen = [];
  let cursor = null;
  for (let guard = 0; guard < 100; guard += 1) {
    const q = "/api/media?limit=7" + (cursor ? "&cursor=" + encodeURIComponent(cursor) : "");
    const page = await req("GET", q);
    if (page.status !== 200) throw new Error("list " + page.status);
    if (!Array.isArray(page.json.items)) throw new Error("bad page body");
    seen.push(...page.json.items);
    cursor = page.json.next_cursor;
    if (cursor === null) break;
  }
  if (seen.length < 1) throw new Error("empty catalogue");

  const created = await req("POST", "/api/media", {
    title: "oracle smoke entry", year: 2005, rating: 61, medium: "film",
    tags: ["smoke"],
  });
  if (created.status !== 201 || created.json.item.title !== "oracle smoke entry") {
    throw new Error("create failed: " + created.status);
  }
  const bad = await req("POST", "/api/media", { title: "", year: 1899, rating: 1, medium: "podcast" });
  if (bad.status !== 400 || bad.json.error.code !== "validation_failed") {
    throw new Error("validation envelope missing on malformed POST");
  }
  const missing = await req("GET", "/api/media/9999999");
  if (missing.status !== 404 || missing.json.error.code !== "not_found") {
    throw new Error("404 envelope wrong");
  }
  const doc = await req("GET", "/openapi.json");
  if (doc.status !== 200 || typeof doc.json.openapi !== "string") {
    throw new Error("openapi route wrong");
  }
  console.log("oracle smoke OK: %d seed items, create/patch/validation/404 all correct", seen.length);
}
main().catch((err) => { console.error("oracle smoke failed:", err.message); process.exit(1); });
NODE

echo "jib-weir oracle complete: /app/start.sh + /app/openapi.json delivered"