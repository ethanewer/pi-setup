# Task overview — observatory origin, login session, npm tree

You are operating an observatory-monitoring workstation rooted at `/app`. It
contains a **local HTTP origin** that you must talk to and two programming
goals (a Python client and a Node.js dependency repair). The grading oracle
later **executes** your deliverables against *fresh* origin servers (different
station data, different HTML edge cases, stricter session handling) and
re-checks the resulting artifacts and the installed npm tree. Your client must
therefore be written generically against the documented protocol — never
hard-coded to the reference data shown below.

Work only under `/app`. Do **not** modify `/app/origin.py` or
`/app/ref_config.json`. Do not delete the fixture tree. Everything that is
checked lives under `/app`.

---

## Deliverables

1. `/app/solve.py` — an **executable** Python 3 client. Standard library only
   (`urllib`, `json`, `html.parser`, `http.cookiejar`). No pip packages.
2. `/app/answer.json` — the JSON report produced by **running** `solve.py`
   against the live reference origin (see below).
3. A complete, installable `node_modules` tree for the npm project at `/app`
   such that `sector-srv` and its transitive dependency `motif` both resolve.

---

## Goal 1 — Fetch and parse the stations dashboard

The origin listens on `127.0.0.1:<port>`. Issue `GET /` and parse the returned
HTML into an ordered list of station records.

### Stations page contract

- The page contains a table rendered as `<table id="stations">`.
- Other tables may be present (e.g. `<table id="algorithms">` or similar).
  Only the table whose `id` is exactly `stations` is used; ignore all others.
- Data rows are `<tr>` containing `<td>` cells in a **fixed column order**:
  `[id, name, city, tempF]`.
  - `id` is a string with mixed letters/digits and punctuation (e.g. `R-7/9`,
    `C-01`).
  - `tempF` is a number (may be negative or fractional).
- A header row uses `<th>` cells (sometimes with `class="head"`). A data row
  always contains at least one `<td>`; th-only rows are skipped.
- A footer/summary row may exist, e.g. `<tr class="footer"><td>N stations
  total</td></tr>`. It is a one-cell row; a real data row must therefore have
  **at least two** cells, so one-cell/footer/stats rows are skipped.
- **Malformed rows must be handled.** Some scenarios deliberately truncate
  rows:
  - 3 cells `[id, name, city]` → `tempF` omitted → report `null`;
  - 2 cells `[id, name]` → `city` and `tempF` omitted → city `""`, tempF `null`;
  - an empty `city` cell (`<td></td>`) → report empty-string city `""`.
  Column position is fixed (only trailing columns are ever missing).
- Whitespace/newlines between tags may be messy; trim every cell.

Your output must preserve **document (top-to-bottom) order**.

Report `title` from the first `title` element text.

---

## Goal 2 — Complete a login + logout session

With a **single persistent cookie jar**, walk the full session on the origin:

1. `GET /login`: origin sets a session cookie named `sid` and returns an HTML
   `<form>` containing a hidden `<input name="nonce" value="N">`. Read `nonce`.
2. `POST /login` with `application/x-www-form-urlencoded` body fields
   `username`, `password`, `nonce`. Success requires all of:
   - the request carries the `sid` cookie the origin just issued;
   - body `nonce` equals the nonce from the login page;
   - credentials are **username `tinker`**, **password `ironclad-2024`**;
   - and, on stricter deployments, the request also carries header
     `X-Nonce: <nonce>`.
   Success → HTTP 200 `{"ok": true, "sid": "..."}`; failure → HTTP 401
   `{"ok": false}`.
3. `GET /session`: authenticated only → HTTP 200 `{"sid": "...",
   "logged_in": true}`; otherwise 401.
4. `POST /logout`: authenticated only → HTTP 200 `{"ok": true,
   "logged_out": true}`; otherwise 401.

Two deployment variants your client **must** survive:

- **Header-nonce deployments** require `X-Nonce` on every `POST /login`.
  Sending it unconditionally is harmless.
- **Session-cookie rotation**: some scenarios swap the `sid` cookie value on a
  successful login (the success response's `Set-Cookie`). A single cookie jar
  tracks this automatically — never hardcode `sid`, never hand-roll cookie
  parsing; read the authoritative `sid` from the `GET /session` response.

Report those values in `session`.

---

## Goal 3 — npm tree

The npm project at `/app` declares a top-level dependency `sector-srv`.
Currently it is not usable: `sector-srv` needs the transitive module `motif`,
but its manifest `/app/vendor/sector-srv/package.json` pins `motif` to a
relative `file:` path that does **not** exist, so the dependency cannot resolve
and `require("sector-srv")` throws `MODULE_NOT_FOUND`.

Repair it so that:

1. `require("sector-srv")` from `/app` works without errors;
2. its `motif` dependency is present and linked. The real `motif` library is at
   `/app/vendor/motif` (so from within `/app/vendor/sector-srv` it is reachable
   via the sibling path `file:../motif`);
3. `npm install` completes cleanly and the full tree installs with no required
   module missing.

You may edit any `package.json` under the manifest (`/app` and `/app/vendor/…`).
Do not change which package `sector-srv` receives besides fixing its `motif`
resolution. The graders validate the **end state** of the installed tree (they
do not re-run `npm install` on the pristine image): it must satisfy

```
node -e "const s=require('sector-srv');const st=s.stamp();
         if(st.stream!=='motif-core'||st.build!==1) process.exit(1)"
```

i.e. `stamp().stream === 'motif-core'` and `stamp().build === 1`.

---

## Report JSON

`/app/answer.json` and every `--out` file must be this exact structure:

```json
{
  "title": "<page title>",
  "stations": [
    {"id": "R-102", "name": "East Bay", "city": "Fairfield", "tempF": 41.2}
  ],
  "session": {"sid": "<sid>", "logged_in": true, "logged_out": true}
}
```

- `stations` in document order, exactly the `#stations` data rows (no headers,
  footers, decoy tables).
- `tempF` numeric when parseable, else `null`; `city` text or `""`.
- `session.sid` equals the `sid` returned by `GET /session`.

## CLI to implement

```
python3 /app/solve.py --origin http://127.0.0.1:<port> --out <path>
```

`--origin` and `--out` are required. `--out` receives the JSON report. Do not
print extra text that makes the machine-report parsing ambiguous.

## Reference run (develop against a live origin)

```
python3 /app/origin.py /app/ref_config.json 20080 &
python3 /app/solve.py --origin http://127.0.0.1:20080 --out /app/answer.json
```

For the reference origin the session sid is `ADR7a`, and `stations` data
matches `/app/ref_config.json`. Use these only to sanity-check your pipeline;
hidden scenarios differ in station data, HTML malformation, `X-Nonce`
requirement, and/or `sid` rotation but all follow this documented protocol.

## Constraints

- Python 3 + Node tooling only (urllib, html.parser, cookie jar, npm, node).
  No `requests`, `beautifulsoup`, `scrapy`, or network packages.
- You may launch helper processes locally (like the origin) during
  development; the grader starts its own origins for each scenario.
- Keep `/app/solve.py` executable. Do everything under `/app`.