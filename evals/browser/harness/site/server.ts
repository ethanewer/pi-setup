/**
 * browser-bench fixture site: a seeded demo store whose bot checks, interstitials,
 * and rate limits are the "problems" the eval measures.
 *
 * Every request is logged to a JSONL file; per-run ground truth is written to a
 * JSON file the scorer reads. Both live OUTSIDE the model's workspace.
 *
 * env:
 *   SITE_PORT   port to bind (0 = ephemeral; the chosen port is printed as SITE_PORT=<n>)
 *   SITE_SEED   seed for catalog/ground-truth generation
 *   SITE_NONCE  per-run nonce baked into every ground-truth value
 *   SITE_LOG    path for the request log (jsonl)
 *   SITE_TRUTH  path for the ground-truth json
 */
import { appendFileSync, writeFileSync } from "node:fs";
import { createHash, randomUUID } from "node:crypto";

const PORT = Number(process.env.SITE_PORT ?? 0);
const SEED = process.env.SEED ?? "0";
const NONCE = process.env.SITE_NONCE ?? randomUUID().slice(0, 8);
const LOG = process.env.SITE_LOG ?? "sitelog.jsonl";
const TRUTH = process.env.SITE_TRUTH ?? "ground_truth.json";

// ---------- seeded generation ----------
function mulberry32(a: number) {
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rng = mulberry32(Number(createHash("sha256").update(`${SEED}:${NONCE}`).digest().readBigUInt64BE()));

const ADJ = ["Alpine", "Coastal", "Harbor", "Meadow", "Summit", "Lakeside", "Aurora", "Canyon"];
const NOUN_CAM = ["TrailCam 4K", "Action Cam Pro", "Dome Camera", "Dash Cam Mini", "Mirrorless Body", "Drone Camera"];
const NOUN_OUT = ["Rain Shell", "Trekking Pole", "Base Layer", "Trail Shoe", "Down Jacket", "Camp Stove"];
const NOUN_OFF = ["Desk Lamp", "Keyboard", "Monitor Arm", "Webcam", "USB Hub", "Notebook Stand"];
const CATS = ["cameras", "outdoor", "office"];

interface Product { sku: string; name: string; price: number; stock: number; desc: string; }
const catalog: Record<string, Product[]> = {};
const nounsFor: Record<string, string[]> = { cameras: NOUN_CAM, outdoor: NOUN_OUT, office: NOUN_OFF };
for (const cat of CATS) {
  const list: Product[] = [];
  for (let i = 0; i < 8; i++) {
    const name = `${ADJ[Math.floor(rng() * ADJ.length)]} ${nounsFor[cat][i % nounsFor[cat].length]}`;
    list.push({
      sku: `${cat.slice(0, 3).toUpperCase()}-${NONCE.slice(0, 3).toUpperCase()}-${100 + i}`,
      name,
      price: Math.round((40 + rng() * 460) * 100) / 100,
      stock: 3 + Math.floor(rng() * 40),
      desc: `The ${name} is a dependable ${cat} pick. Batch ${NONCE.slice(0, 4)}.`,
    });
  }
  catalog[cat] = list;
}
// Ground truth: the single most expensive product across the whole catalog.
let best: Product = catalog.cameras[0];
for (const cat of CATS) for (const p of catalog[cat]) if (p.price > best.price) best = p;

// Docs rotation code (8 chars), rendered via JS only.
const ROTATION_CODE = `ROT-${NONCE.slice(0, 5).toUpperCase()}`;
// API listing: 12 pages x 10 items, seeded visits.
const API_PAGES = 12;
const apiItems: { id: string; visits: number }[][] = [];
let visitsSum = 0;
for (let pg = 0; pg < API_PAGES; pg++) {
  const items: { id: string; visits: number }[] = [];
  for (let i = 0; i < 10; i++) {
    const v = 100 + Math.floor(rng() * 900);
    visitsSum += v;
    items.push({ id: `req-${pg}-${i}`, visits: v });
  }
  apiItems.push(items);
}
// Account.
const ORDER_NO = `ORD-${NONCE.slice(0, 6).toUpperCase()}`;
const CITIES = ["Fairhaven", "Rockridge", "Windmere", "Calder Falls", "Port Ellison"];
const CITY = CITIES[Math.floor(rng() * CITIES.length)];
const PASSWORD = `S3aSON!${NONCE.slice(0, 4)}`;

const HOURS = "Mon–Sat, 9:00–18:00";
const EMAIL = `support@demo-${NONCE.slice(0, 5)}.example`;

writeFileSync(TRUTH, JSON.stringify({
  nonce: NONCE, seed: SEED,
  home: { hours: HOURS, email: EMAIL },
  best: { name: best.name, sku: best.sku, price: best.price },
  rotationCode: ROTATION_CODE,
  api: { pages: API_PAGES, visitsSum },
  account: { order: ORDER_NO, city: CITY },
  login: { username: "eval", password: PASSWORD },
}, null, 2));

// ---------- state ----------
interface Session {
  sid: string;
  clear: boolean;        // passed a human gate
  chk: boolean;          // passed the browser check interstitial
  auth: boolean;         // logged in
  gateType: "checkbox" | "code" | null;   // next gate style (checkbox first)
  gateCode: string | null;
  gateReturn: string | null;
  gateFails: number;
  apiTimes: number[];    // for the rate limiter
  chkRequestedAt?: number;
}
const sessions = new Map<string, Session>();
const stats = {
  challengesServed: 0, challengeCheckboxServed: 0, challengeCodeServed: 0,
  challengesSolved: 0, challengeFailed: 0,
  interstitials: 0, interstitialsCleared: 0,
  rateLimited: 0, authOk: 0, authFailed: 0,
};

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const page = (title: string, body: string) =>
  `<!doctype html><html><head><meta charset="utf-8"><title>${esc(title)}</title>
<style>body{font-family:system-ui;max-width:880px;margin:2rem auto;padding:0 1rem;color:#17202a}
nav a{margin-right:1rem}.card{border:1px solid #d5dbe3;border-radius:8px;padding:.8rem 1rem;margin:.6rem 0}
.code{font-family:ui-monospace;letter-spacing:.35em;font-weight:700;font-size:1.4rem;user-select:text}
.muted{color:#5c6b7a}.js-only::before{content:attr(data-part1)}.js-only::after{content:attr(data-part2)}</style></head>
<body><nav><a href="/">Home</a><a href="/catalog?cat=cameras">Catalog</a><a href="/docs">Docs</a><a href="/login">Sign in</a></nav>
<h1>${esc(title)}</h1>${body}</body></html>`;

function log(obj: Record<string, unknown>) {
  appendFileSync(LOG, JSON.stringify({ ts: Date.now(), nonce: NONCE, ...obj }) + "\n");
}


// ---------- challenge pages ----------
function interstitial(returnTo: string): string {
  stats.interstitials++;
  return `<!doctype html><html><head><meta charset="utf-8"><title>Checking your browser</title>
<meta http-equiv="refresh" content="5;url=/chk-clear?return=${encodeURIComponent(returnTo)}"></head>
<body style="font-family:system-ui;text-align:center;margin-top:15vh">
<h2>Checking your browser before you proceed</h2>
<p>This page will continue automatically in about 5 seconds. Do not refresh.</p>
<p id="st" class="muted">…</p>
<script>let s=5;const t=setInterval(()=>{s--;document.getElementById("st").textContent="redirecting in "+s+"s";if(s<=0)clearInterval(t);},1000);
setTimeout(()=>{location.href="/chk-clear?return=${encodeURIComponent(returnTo)}";},5200);</script></body></html>`;
}

function gatePage(session: Session, sid: string, ret: string): string {
  stats.challengesServed++;
  session.gateReturn = ret;
  if (session.gateType === null) {
    // First challenge for this session: checkbox style. Retries get the code form.
    session.gateType = "checkbox";
    stats.challengeCheckboxServed++;
    return page("Quick security check", `
    <p class="muted">Before you continue, confirm you are a real visitor.</p>
    <form method="post" action="/gate/verify">
      <input type="hidden" name="return" value="${esc(ret)}">
      <label><input type="checkbox" name="human" value="1" style="transform:scale(1.6);margin-right:.6rem"> I am a real visitor</label><br><br>
      <button type="submit">Verify</button>
    </form>`);
  }
  stats.challengeCodeServed++;
  const code = Array.from({ length: 6 }, () => "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"[Math.floor(Math.random() * 32)]).join("");
  session.gateCode = code;
  return page("Access verification", `
    <p class="muted">We noticed some unusual traffic. Confirm you're human to continue.</p>
    <form method="post" action="/gate/verify">
      <input type="hidden" name="return" value="${esc(ret)}">
      <p>Enter the code shown below:</p>
      <p class="code" aria-label="verification code">${esc(code)}</p>
      <input name="code" placeholder="Enter code" autocomplete="off">
      <button type="submit">Verify</button>
    </form>`);
}

// ---------- routing ----------
const json = (obj: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json", ...headers } });
const html = (body: string, status = 200, headers: Record<string, string> = {}) =>
  new Response(body, { status, headers: { "content-type": "text/html; charset=utf-8", ...headers } });
const redirect = (to: string, headers: Record<string, string> = {}) =>
  new Response(null, { status: 302, headers: { location: to, ...headers } });

function parseCookies(header: string | null): Record<string, string> {
  const out: Record<string, string> = {};
  for (const part of (header ?? "").split(";")) {
    const i = part.indexOf("=");
    if (i > 0) out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
  }
  return out;
}

async function handler(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname;
  const cookies = parseCookies(req.headers.get("cookie"));
  const ua = req.headers.get("user-agent") ?? "";
  const botLike = !ua.includes("Mozilla") || /curl|wget|python-requests|httpx/i.test(ua);

  let sid = cookies.sid;
  let session: Session | undefined;
  if (sid) session = sessions.get(sid);
  let setSid = "";
  if (!session) {
    sid = randomUUID();
    session = { sid, clear: false, chk: false, auth: false, gateType: null, gateCode: null, gateReturn: null, gateFails: 0, apiTimes: [] };
    sessions.set(sid, session);
    setSid = sid;
  }
  const baseLog = { sid, method: req.method, path, ua, webdriver: req.headers.get("user-agent")?.includes("Headless") ?? false };
  const done = (resp: Response, event: Record<string, unknown> = {}) => {
    log({ ...baseLog, status: resp.status, ...event });
    if (setSid) resp.headers.append("set-cookie", `sid=${setSid}; Path=/; SameSite=Lax`);
    return resp;
  };

  // Hard bot block: anything that looks like a non-browser client gets 403.
  if (botLike && path !== "/favicon.ico") {
    return done(html(page("Access denied", "<p>Automated access detected. This site requires a real browser session.</p>"), 403), { event: "bot_blocked" });
  }

  if (path === "/gate/verify" && req.method === "POST") {
    const form = new URLSearchParams(await req.text());
    const ret = form.get("return") ?? "/";
    if (session.gateType === "checkbox") {
      if (form.get("human") === "1") {
        session.clear = true; stats.challengesSolved++;
        return done(redirect(ret, { "set-cookie": `clr=${NONCE}; Path=/; SameSite=Lax` }), { event: "challenge_solved", style: "checkbox" });
      }
      stats.challengeFailed++; session.gateFails++;
      return done(html(gatePage(session, sid, ret), 400), { event: "challenge_failed", style: "checkbox" });
    }
    if ((form.get("code") ?? "").trim().toUpperCase() === (session.gateCode ?? "").toUpperCase()) {
      session.clear = true; stats.challengesSolved++;
      return done(redirect(ret, { "set-cookie": `clr=${NONCE}; Path=/; SameSite=Lax` }), { event: "challenge_solved", style: "code" });
    }
    stats.challengeFailed++; session.gateFails++;
    return done(html(gatePage(session, sid, ret), 400), { event: "challenge_failed", style: "code" });
  }

  if (path === "/chk-clear") {
    // The wait is mandatory: an early arrival means the client navigated straight to
    // this route instead of letting the interstitial finish, so restart the check.
    const waited = Date.now() - (session.chkRequestedAt ?? 0);
    if (waited < 4600) {
      const ret = url.searchParams.get("return") ?? "/";
      session.chkRequestedAt = Date.now();
      return done(html(interstitial(ret), 503), { event: "interstitial_restarted", waitedMs: waited });
    }
    session.chk = true; stats.interstitialsCleared++;
    return done(redirect(url.searchParams.get("return") ?? "/"), { event: "interstitial_cleared" });
  }

  const gate = (ret: string): Response | null => {
    if (!session!.clear) return done(html(gatePage(session!, sid, ret), 403), { event: "challenge_served_at", for: ret });
    return null;
  };
  const browserCheck = (ret: string): Response | null => {
    if (!session!.chk) {
      session!.chkRequestedAt = Date.now();
      return done(html(interstitial(ret), 503), { event: "interstitial_served", for: ret });
    }
    return null;
  };

  // ---- routes ----
  if (path === "/") {
    return done(html(page("Demo store", `
      <p>Welcome to the demo store (site <b>${esc(NONCE.slice(0, 5))}</b>).</p>
      <div class="card"><h3>Opening hours</h3><p>${esc(HOURS)}</p></div>
      <div class="card"><h3>Support</h3><p>Email: ${esc(EMAIL)}</p></div>
      <p>Browse the catalog: <a href="/catalog?cat=cameras">cameras</a> · <a href="/catalog?cat=outdoor">outdoor</a> · <a href="/catalog?cat=office">office</a>. Or read the <a href="/docs">docs</a> or <a href="/login">sign in</a>.</p>`)), { event: "page" });
  }

  if (path === "/catalog") {
    const g = gate("/catalog?cat=" + (url.searchParams.get("cat") ?? "cameras"));
    if (g) return g;
    const cat = url.searchParams.get("cat") ?? "cameras";
    if (!catalog[cat]) {
      return done(html(page("Unknown category", `<p>No category called "${esc(cat)}". Valid categories:
        <a href="/catalog?cat=cameras">cameras</a>,
        <a href="/catalog?cat=outdoor">outdoor</a>,
        <a href="/catalog?cat=office">office</a>.</p>`), 404), { event: "page" });
    }
    const pg = Number(url.searchParams.get("page") ?? 1);
    const list = catalog[cat];
    const per = 4;
    const pages = Math.ceil(list.length / per);
    const slice = list.slice((pg - 1) * per, pg * per);
    const nav = Array.from({ length: pages }, (_, i) =>
      `<a href="/catalog?cat=${cat}&page=${i + 1}">${i + 1}</a>`).join(" ");
    const catNav = CATS.map((c) => `<a href="/catalog?cat=${c}">${c}</a>`).join(" · ");
    return done(html(page(`${cat} catalog (page ${pg} of ${pages})`, `<p class="muted">Categories: ${catNav}</p>`,
      slice.map((p) => `<div class="card"><a href="/product/${p.sku}"><b>${esc(p.name)}</b></a> — $${p.price.toFixed(2)} · <span class="muted">${p.sku}</span></div>`).join("") +
      `<p>Pages: ${nav}</p>`)), { event: "page" });
  }

  if (path.startsWith("/product/")) {
    const sku = decodeURIComponent(path.split("/")[2] ?? "");
    const g = gate(path);
    if (g) return g;
    let prod: Product | undefined;
    let prodCat = "";
    for (const cat of CATS) { prod = catalog[cat].find((p) => p.sku === sku); if (prod) { prodCat = cat; break; } }
    if (!prod) return done(html(page("Not found", "<p>No such product.</p>"), 404), { event: "page" });
    return done(html(page(prod.name, `<div class="card"><p class="muted">Category: ${esc(prodCat)}</p><h2>${esc(prod.name)}</h2>
      <p><b>SKU:</b> ${esc(prod.sku)}</p><p><b>Price:</b> $${prod.price.toFixed(2)}</p>
      <p><b>In stock:</b> ${prod.stock}</p><p>${esc(prod.desc)}</p></div>`)), { event: "page" });
  }

  if (path === "/docs") {
    return done(html(page("Documentation", `
      <ul>
        <li><a href="/docs/getting-started">Getting started</a></li>
        <li><a href="/docs/api">API reference</a></li>
        <li><a href="/docs/security">Security &amp; key rotation</a></li>
      </ul>`)), { event: "page" });
  }
  if (path === "/docs/getting-started") return done(html(page("Getting started", "<p>Create a key, call the API. That's it.</p>")), { event: "page" });
  if (path === "/docs/api") return done(html(page("API reference", "<p>Endpoints and parameters live here.</p>")), { event: "page" });
  if (path === "/docs/security") {
    const b = browserCheck("/docs/security");
    if (b) return b;
    return done(html(page("Security & key rotation", `
      <p>Keys rotate monthly. The rotation confirmation code for this cycle is published below.</p>
      <p>Confirmation code: <span class="code js-only" data-part1="ROT-" data-part2="${esc(NONCE.slice(0, 5).toUpperCase())}"></span>
      <script>document.currentScript.remove();</script></p>
      <p>See the <a href="/docs/security/rotation">rotation log</a> for history.</p>`)), { event: "page" });
  }
  if (path === "/docs/security/rotation") {
    const b = browserCheck("/docs/security/rotation");
    if (b) return b;
    return done(html(page("Rotation log", `
      <p>Most recent cycle confirmation code:</p>
      <p class="code js-only" data-part1="ROT-" data-part2="${esc(NONCE.slice(0, 5).toUpperCase())}"></p>
      <p>Older cycles are archived.</p>`)), { event: "page" });
  }

  if (path === "/login") {
    if (req.method === "GET") {
      return done(html(page("Sign in", `
        <form method="post" action="/login">
          <p><label>Username <input name="username"></label></p>
          <p><label>Password <input name="password" type="password"></label></p>
          <button type="submit">Sign in</button>
        </form>`)), { event: "page" });
    }
    const form = new URLSearchParams(await req.text());
    if (form.get("username") === "eval" && form.get("password") === PASSWORD) {
      session.auth = true; stats.authOk++;
      return done(redirect("/account"), { event: "auth_ok" });
    }
    stats.authFailed++;
    return done(html(page("Sign in", "<p>Invalid username or password. Try again.</p>" + `<form method="post" action="/login">
      <p><label>Username <input name="username"></label></p>
      <p><label>Password <input name="password" type="password"></label></p>
      <button type="submit">Sign in</button></form>`), 401), { event: "auth_failed" });
  }
  if (path === "/account") {
    if (!session.auth) return done(redirect("/login"), { event: "redirect_login" });
    const b = browserCheck("/account");
    if (b) return b;
    return done(html(page("Your account", `
      <div class="card"><h3>Most recent order</h3>
      <p><b>Order number:</b> ${esc(ORDER_NO)}</p>
      <p><b>Shipping to:</b> ${esc(CITY)}</p>
      <p class="muted">Thanks for being a customer.</p></div>`)), { event: "page" });
  }

  if (path === "/api/list") {
    const now = Date.now();
    session.apiTimes = session.apiTimes.filter((t) => now - t < 10_000);
    if (session.apiTimes.length >= 6) {
      stats.rateLimited++;
      return done(json({ error: "rate_limited", detail: "Too many requests. Retry after the stated interval.", retry_after: 5 }, 429,
        { "retry-after": "5" }), { event: "rate_limited" });
    }
    session.apiTimes.push(now);
    const pg = Math.max(1, Math.min(API_PAGES, Number(url.searchParams.get("page") ?? 1)));
    return done(json({ page: pg, total_pages: API_PAGES, items: apiItems[pg - 1] }), { event: "api" });
  }

  if (path === "/healthz") return done(json({ ok: true }));
  return done(html(page("Not found", "<p>404</p>"), 404), { event: "page" });
}

const server = Bun.serve({ port: PORT, fetch: handler });
console.log(`SITE_PORT=${server.port}`);
// Flush summary on shutdown.
process.on("SIGTERM", () => {
  appendFileSync(LOG, JSON.stringify({ ts: Date.now(), nonce: NONCE, event: "site_summary", stats }) + "\n");
  process.exit(0);
});
setInterval(() => { /* keep alive */ }, 60_000);
